#pragma once

#include <concepts>  // std::unsigned_integral
#include <cstdint>   // std::uint64_t
#include <limits>    // std::numeric_limits
#include <mempeep/concepts/memory.hpp>
#include <mempeep/concepts/tracer.hpp>
#include <mempeep/descriptor.hpp>
#include <optional>  // std::optional
#include <utility>   // std::ignore

namespace mempeep::detail {

struct NoScope {};

// Deduces Tracer::Scope from Tracer, avoiding repetition at call sites.
// make_scope is called for fields items (Field, Pad, Seek).
template <IsTracer Tracer, IsAddress Address, IsFieldsItem Item>
auto make_scope(Tracer& tracer, Address address, Item item) {
  if constexpr (IsScopedTracer<Tracer>) {
    const auto addr = static_cast<std::uint64_t>(address);
    return typename Tracer::Scope(tracer, addr, item);
  } else {
    return NoScope{};
  }
}

// Deduces Tracer::DescScope from Tracer, avoiding repetition at call sites.
// make_desc_scope is called for descriptors (Primitive, Struct, Array, ...).
template <IsTracer Tracer, IsAddress Address, IsDescriptor Desc>
auto make_desc_scope(Tracer& tracer, Address address, Desc desc) {
  if constexpr (IsDescScopedTracer<Tracer>) {
    const auto addr = static_cast<std::uint64_t>(address);
    return typename Tracer::DescScope(tracer, addr, desc);
  } else {
    return NoScope{};
  }
}

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
  native_type_t<Primitive<T>>& target  // T
) {
  if (reader(address, sizeof(target), &target)) {
    if constexpr (requires { tracer.value(target); }) {
      tracer.value(target);
    }
    return advance(address, sizeof(target), tracer);
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
  native_type_t<LenString<LenT, MaxLen>>& target  // std::string
) {
  LenT len{};
  auto cursor = read_value<Primitive<LenT>>(address, reader, tracer, len);
  if (!cursor) return {};
  if (len > MaxLen) {
    tracer.error(Error::STRING_TOO_LONG);
    return {};
  }
  target.resize(len);
  if (len == 0) return cursor;  // reader might reject size 0
  if (reader(*cursor, len, target.data())) {
    if constexpr (requires { tracer.value(target); }) {
      tracer.value(target);
    }
    return advance(*cursor, len, tracer);
  } else {
    tracer.error(Error::READ_FAILED);
    return {};
  }
}

template <auto N, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_fields_item(
  Pad<N> item,
  address_t<MemoryReader>,
  address_t<MemoryReader> address,
  const MemoryReader&,
  Tracer& tracer,
  auto&
) {
  [[maybe_unused]] auto scope = make_scope(tracer, address, item);
  return advance(address, N, tracer);
}

template <auto N, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_fields_item(
  Seek<N> item,
  address_t<MemoryReader> base,
  address_t<MemoryReader> address,
  const MemoryReader&,
  Tracer& tracer,
  auto&
) {
  [[maybe_unused]] auto scope = make_scope(tracer, address, item);
  return advance(base, N, tracer);
}

template <
  IsDescriptor Desc,
  auto M,
  IsMemoryReader MemoryReader,
  IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_fields_item(
  Field<Desc, M> item,
  address_t<MemoryReader>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  detail::member_class_t<M>& target  // ensure target.*M is valid
) {
  [[maybe_unused]] auto scope = make_scope(tracer, address, item);
  return read_value<Desc>(address, reader, tracer, target.*M);
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
  native_type_t<RawAddr<AddrT>>& target  // AddrT
) {
  address_t<MemoryReader> raw{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, raw
  );
  if (cursor) target = static_cast<AddrT>(raw);
  return cursor;
}

template <IsDescriptor Desc, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  Ref<Desc>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Ref<Desc>>& target  // native_type_t<Desc>
) {
  address_t<MemoryReader> target_ptr{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, target_ptr
  );
  if (!cursor) return {};
  if (target_ptr) {
    // we always try to read as much as possible
    // so ignore output since cursor is still valid, only inner read failed
    std::ignore = read_value<Desc>(target_ptr, reader, tracer, target);
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
  native_type_t<NullableRef<Desc>>& target  // std::optional
) {
  address_t<MemoryReader> target_ptr{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, target_ptr
  );
  if (!cursor) return {};
  target.reset();
  if (target_ptr) {
    auto& target_value = target.emplace();
    // we always try to read as much as possible
    // so ignore output since cursor is still valid, only inner read failed
    // keep field emplaced even if read fails to retain partially read data
    std::ignore = read_value<Desc>(target_ptr, reader, tracer, target_value);
  }
  // note: null target_ptr is ok, no error reported
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
  native_type_t<Array<Desc, N>>& target  // std::array
) {
  Cursor<MemoryReader> cursor{address};
  for (auto& elem : target) {
    if (!cursor) return {};  // quit when cursor becomes invalid
    cursor = read_value<Desc>(*cursor, reader, tracer, elem);
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
  native_type_t<Vector<Desc, MaxLen>>& target  // std::vector
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
  if (begin_ptr == 0) {
    tracer.error(Error::ADDRESS_NULL);
    return cursor;
  }
  if (begin_ptr > end_ptr) {
    tracer.error(Error::VECTOR_INVALID_RANGE);
    return cursor;
  }
  std::size_t count = 0;
  target.clear();
  Cursor<MemoryReader> vector_cursor{begin_ptr};
  while (vector_cursor && *vector_cursor < end_ptr) {
    auto& elem = target.emplace_back();
    vector_cursor = read_value<Desc>(*vector_cursor, reader, tracer, elem);
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
    <= std::numeric_limits<detail::member_type_t<Next>>::max()
  )
[[nodiscard]] Cursor<MemoryReader> read_value_impl(
  CircularList<Desc, Next, MaxLen>,
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<CircularList<Desc, Next, MaxLen>>& target
) {
  address_t<MemoryReader> head_ptr{};
  auto cursor = read_value<Primitive<address_t<MemoryReader>>>(
    address, reader, tracer, head_ptr
  );
  if (!cursor) return {};
  if (head_ptr == 0) return cursor;  // empty list
  Cursor<MemoryReader> list_cursor{head_ptr};
  std::size_t count = 0;
  target.clear();
  do {
    auto& elem = target.emplace_back();
    if (!read_value<Desc>(*list_cursor, reader, tracer, elem)) return cursor;
    list_cursor = static_cast<address_t<MemoryReader>>(elem.*Next);
    if (!list_cursor) {
      tracer.error(Error::ADDRESS_NULL);
      return cursor;
    }
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
  native_type_t<Struct<T, Fields<Items...>>>& target  // T
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
     && (cursor = read_fields_item(Items{}, address, *cursor, reader, tracer, target))
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
  [[maybe_unused]] auto scope = make_desc_scope(tracer, addr, Desc{});
  return read_value_impl(Desc{}, addr, reader, tracer, out);
}

}  // namespace mempeep::detail

namespace mempeep {

/**
 * @brief Reads data from remote memory into a native object.
 *
 * Reads `native_type_t<Desc>` from `address` using `reader`, populating
 * `target`. Attempts to read as much as possible even after partial
 * failures. Returns the result of `tracer.success()`.
 *
 * @tparam Desc          Descriptor controlling how the value is read.
 * @tparam MemoryReader  Type satisfying IsMemoryReader.
 * @tparam Tracer        Type satisfying IsTracer.
 * @param reader  The memory reader.
 * @param address Remote address to read from.
 * @param target  Native object to populate.
 * @param tracer  Receives error reports; its `success()` is returned.
 * @return The result of `tracer.success()` (convertible to bool).
 */
template <IsDescriptor Desc, IsMemoryReader MemoryReader, IsTracer Tracer>
[[nodiscard]] auto read(
  address_t<MemoryReader> address,
  const MemoryReader& reader,
  Tracer& tracer,
  native_type_t<Desc>& target
) {
  std::ignore = detail::read_value<Desc>(address, reader, tracer, target);
  return tracer.success();
};

}  // namespace mempeep