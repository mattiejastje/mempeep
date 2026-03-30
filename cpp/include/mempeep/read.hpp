#pragma once

#include <concepts>  // std::unsigned_integral
#include <cstdint>   // std::uint64_t
#include <limits>    // std::numeric_limits
#include <mempeep/detail/concepts/memory.hpp>
#include <mempeep/detail/concepts/tracer.hpp>
#include <mempeep/descriptors.hpp>
#include <optional>  // std::optional
#include <utility>   // std::ignore

namespace mempeep::detail {

// Abstract unsigned addition with overflow check.
template <std::unsigned_integral S, std::unsigned_integral T>
[[nodiscard]] constexpr std::optional<S> checked_add(S s, T t) noexcept {
  if (t > std::numeric_limits<S>::max() - s) return {};
  return static_cast<S>(s + t);
}

// Advance address by n with traced error in case of overflow.
template <IsAddress Addr, IsTracer Tracer>
[[nodiscard]] std::optional<Addr> advance(
  Addr addr, std::size_t n, Tracer& tracer
) {
  auto u = checked_add(addr, n);
  if (!u) tracer.error(Error::ADDRESS_OVERFLOW);
  return u;
}

// Cursor tracks the current read position.
//
// It starts at a given address and advances as each item is read.
// It becomes nullopt when the current position can no longer be determined,
// for example, due to a failed memory read or an address overflow.
//
// Key invariant: a cursor only becomes nullopt if an error was already
// reported to the tracer. nullopt without a tracer error never occurs.
//
// Errors are contained locally: a child's cursor becoming nullopt
// does not invalidate the parent's cursor. This allows reading to continue
// past failed items (e.g. a bad address), recovering as much data as
// possible. Child errors are still reported through the tracer.
template <IsMemoryReader MemoryReader>
using Cursor = std::optional<address_t<MemoryReader>>;

// Forward declaration for mutual recursion.
template <IsDescriptor Desc, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value(
  address_t<MemoryReader> addr,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Desc>& out
);

template <IsPrimitive T, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  Primitive<T>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Primitive<T>>& out  // T
) {
  if (reader(address, sizeof(out), &out)) {
    tracer.value(out);
    return advance(address, sizeof(out), tracer);
  } else {
    tracer.error(Error::READ_FAILED);
    return {};
  }
}

template <
  std::unsigned_integral LenT,
  std::size_t MaxLen,
  IsMemoryReader MemoryReader,
  IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  LenString<LenT, MaxLen>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<LenString<LenT, MaxLen>>& out  // std::string
) {
  LenT len{};
  auto cursor = read_value<Primitive<LenT>>(address, reader, tracer, len);
  if (!cursor) return {};
  if (len > MaxLen) {
    tracer.error(Error::STRING_TOO_LONG);
    return {};
  }
  out.resize(len);
  if (len == 0) {
    tracer.value(out);
    return cursor;
  }
  else if (reader(*cursor, len, out.data())) {
    tracer.value(out);
    return advance(*cursor, len, tracer);
  } else {
    tracer.error(Error::READ_FAILED);
    return {};
  }
}

template <auto N, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_fields_item_impl(
  Pad<N> item,
  address_t<MemoryReader>,
  address_t<MemoryReader> address,
  const MemoryReader&,
  Tracer& tracer,
  auto&
) {
  return advance(address, N, tracer);
}

template <auto N, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_fields_item_impl(
  Seek<N> item,
  address_t<MemoryReader> base,
  address_t<MemoryReader> address,
  const MemoryReader&,
  Tracer& tracer,
  auto&
) {
  return advance(base, N, tracer);
}

template <
  IsDescriptor Desc,
  auto M,
  IsMemoryReader MemoryReader,
  IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_fields_item_impl(
  Field<Desc, M> item,
  address_t<MemoryReader>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  member_class_t<M>& out  // ensure out.*M is valid
) {
  return read_value<Desc>(address, reader, tracer, out.*M);
}

template <
  IsFieldsItem FieldsItem,
  IsMemoryReader MemoryReader,
  IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_fields_item(
  FieldsItem item,
  address_t<MemoryReader> base,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  auto& out
) {
  tracer.begin_fields_item(address, item);
  auto cursor = read_fields_item_impl(item, base, address, reader, tracer, out);
  tracer.end_fields_item();
  return cursor;
}

// read_value_impl are the dispatch implementations for read_value
// dispatch happens on first argument

template <IsAddress AddrT, IsMemoryReader MemoryReader, IsTracer Tracer>
  requires(
    std::numeric_limits<address_t<MemoryReader>>::max()
    <= std::numeric_limits<AddrT>::max()
  )
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  RawAddr<AddrT>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<RawAddr<AddrT>>& out  // AddrT
) {
  address_t<MemoryReader> raw{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, raw
  );
  if (cursor) out = static_cast<AddrT>(raw);
  return cursor;
}

template <IsDescriptor Desc, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  Ref<Desc>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Ref<Desc>>& out  // native_type_t<Desc>
) {
  address_t<MemoryReader> out_ptr{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, out_ptr
  );
  if (!cursor) return {};
  if (out_ptr) {
    // we always try to read as much as possible
    // so ignore output since cursor is still valid, only inner read failed
    std::ignore = read_value<Desc>(out_ptr, reader, tracer, out);
  } else {
    tracer.error(Error::ADDRESS_NULL);
  }
  return cursor;
}

template <IsDescriptor Desc, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  NullableRef<Desc>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<NullableRef<Desc>>& out  // std::optional
) {
  address_t<MemoryReader> out_ptr{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, out_ptr
  );
  if (!cursor) return {};
  out.reset();
  if (out_ptr) {
    auto& out_value = out.emplace();
    // we always try to read as much as possible
    // so ignore output since cursor is still valid, only inner read failed
    // keep field emplaced even if read fails to retain partially read data
    std::ignore = read_value<Desc>(out_ptr, reader, tracer, out_value);
  }
  // note: null out_ptr is ok, no error reported
  return cursor;
}

template <
  IsDescriptor Desc,
  std::size_t N,
  IsMemoryReader MemoryReader,
  IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  Array<Desc, N>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Array<Desc, N>>& out  // std::array
) {
  Cursor<MemoryReader> cursor{address};
  for (std::size_t i = 0; i < N; ++i) {
    if (!cursor) return {};
    tracer.begin_element(static_cast<std::uint64_t>(*cursor), i);
    cursor = read_value<Desc>(*cursor, reader, tracer, out[i]);
    tracer.end_element();
  }
  return cursor;
}

template <
  IsDescriptor Desc,
  std::size_t MaxLen,
  IsMemoryReader MemoryReader,
  IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  Vector<Desc, MaxLen>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Vector<Desc, MaxLen>>& out  // std::vector
) {
  address_t<MemoryReader> begin_ptr{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, begin_ptr
  );
  if (!cursor) return {};
  address_t<MemoryReader> end_ptr{};
  cursor = read_value<Primitive<address_t<MemoryReader>>>(
    *cursor, reader, tracer, end_ptr
  );
  if (!cursor) return {};
  if (begin_ptr > end_ptr) {
    tracer.error(Error::VECTOR_INVALID_RANGE);
    return cursor;
  }
  std::size_t count = 0;
  out.clear();
  Cursor<MemoryReader> vector_cursor{begin_ptr};
  while (vector_cursor && *vector_cursor < end_ptr) {
    auto& elem = out.emplace_back();
    tracer.begin_element(*vector_cursor, count);
    vector_cursor = read_value<Desc>(*vector_cursor, reader, tracer, elem);
    tracer.end_element();
    if (++count > MaxLen) {
      tracer.error(Error::VECTOR_TOO_LONG);
      return cursor;
    }
  }
  if (vector_cursor && *vector_cursor != end_ptr) {
    tracer.error(Error::VECTOR_MISALIGNED);
  }
  return cursor;
}

template <
  IsDescriptor Desc,
  auto Next,
  std::size_t MaxLen,
  IsMemoryReader MemoryReader,
  IsTracer Tracer>
  requires(
    std::numeric_limits<address_t<MemoryReader>>::max()
    <= std::numeric_limits<member_type_t<Next>>::max()
  )
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  CircularList<Desc, Next, MaxLen>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<CircularList<Desc, Next, MaxLen>>& out
) {
  address_t<MemoryReader> head_ptr{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, head_ptr
  );
  if (!cursor) return {};
  if (head_ptr == 0) return cursor;  // empty list
  Cursor<MemoryReader> list_cursor{head_ptr};
  std::size_t count = 0;
  out.clear();
  do {
    auto& elem = out.emplace_back();
    tracer.begin_element(*list_cursor, count);
    auto cursor = read_value<Desc>(*list_cursor, reader, tracer, elem);
    tracer.end_element();
    if (!cursor) return cursor;
    const auto next_addr = static_cast<address_t<MemoryReader>>(elem.*Next);
    if (next_addr == 0) {
      tracer.error(Error::ADDRESS_NULL);
      return cursor;
    }
    list_cursor = next_addr;
    if (++count > MaxLen) {
      tracer.error(Error::CIRCULAR_LIST_TOO_LONG);
      return cursor;
    }
  } while (*list_cursor != head_ptr);
  return cursor;
}

template <
  IsFieldsItem... Items,
  typename T,
  IsMemoryReader MemoryReader,
  IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  Struct<T, Fields<Items...>>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Struct<T, Fields<Items...>>>& out  // T
) {
  Cursor<MemoryReader> cursor{address};
  // Process each field item in order, stopping if the cursor becomes nullopt.
  // This is a comma fold: (expr, ...) evaluates each expr left-to-right.
  // Each expr is: cursor && (cursor = read_fields_item(...))
  // The && is plain short-circuit evaluation, not a fold operator:
  // if cursor is nullopt (falsy), the assignment is skipped.
  // Items{} constructs a tag value at zero cost to select the right overload.
  ((
     cursor
     && (cursor = read_fields_item(Items{}, address, *cursor, reader, tracer, out))
   ),
   ...);
  return cursor;
}

/**
 * @brief Reads value from `addr` using the descriptor `Desc`.
 *
 * Writes into `out`, and returns the cursor positioned just after the
 * bytes consumed at `addr` (not at the pointee for `Ref`, `Vector`, ...).
 */
template <IsDescriptor Desc, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value(
  address_t<MemoryReader> addr,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Desc>& out
) {
  tracer.begin_desc(addr, Desc{});
  auto cursor = read_value_impl(Desc{}, addr, reader, tracer, out);
  tracer.end_desc();
  return cursor;
}

}  // namespace mempeep::detail

namespace mempeep {

/**
 * @brief Reads data from remote memory into a native object.
 *
 * Reads `native_type_t<Desc>` from `address` using `reader`, populating
 * `out`. Attempts to read as much as possible even after partial
 * failures. Returns the result of `tracer.success()`.
 *
 * @tparam Desc          Descriptor controlling how the value is read.
 * @tparam MemoryReader  Type satisfying IsMemoryReader.
 * @tparam Tracer        Type satisfying IsTracer.
 * @param reader  The memory reader.
 * @param address Remote address to read from.
 * @param out     Native object to populate.
 * @param tracer  Receives error reports; its `success()` is returned.
 * @return The result of `tracer.success()` (convertible to bool).
 */
template <IsDescriptor Desc, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] auto read(
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Desc>& out
) {
  std::ignore = detail::read_value<Desc>(address, reader, tracer, out);
  return tracer.success();
};

}  // namespace mempeep