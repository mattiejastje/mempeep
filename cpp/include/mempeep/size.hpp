#pragma once

#include <cstddef>  // std::size_t
#include <mempeep/descriptors.hpp>
#include <mempeep/detail/concepts/address.hpp>

namespace mempeep {

// Forward declaration for mutual recursion.
template <IsDescriptor Desc, IsAddress AddrT>
consteval std::size_t byte_size() noexcept;

}  // namespace mempeep

namespace mempeep::detail {

template <IsPrimitive T, IsAddress AddrT>
consteval std::size_t byte_size_impl(Primitive<T>, AddrT) noexcept {
  return sizeof(T);
}

template <IsDescriptor Desc, IsAddress AddrT>
consteval std::size_t byte_size_impl(RemoteAddr<Desc, AddrT>, AddrT) noexcept {
  return byte_size<Desc, AddrT>();
}

template <
  IsDescriptor Desc,
  native_type_t<Desc> Min,
  native_type_t<Desc> Max,
  IsAddress AddrT>
consteval std::size_t byte_size_impl(Bounded<Desc, Min, Max>, AddrT) noexcept {
  return byte_size<Desc, AddrT>();
}

template <std::size_t MaxLen, IsAddress AddrT>
consteval std::size_t byte_size_impl(ZString<MaxLen>, AddrT) noexcept {
  return MaxLen;
}

template <IsAddress AddrT>
consteval std::size_t byte_size_impl(RawAddr<AddrT>, AddrT) noexcept {
  return sizeof(AddrT);
}

template <IsDescriptor Desc, IsAddress AddrT>
consteval std::size_t byte_size_impl(Ref<Desc>, AddrT) noexcept {
  return sizeof(AddrT);
}

template <IsDescriptor Desc, IsAddress AddrT>
consteval std::size_t byte_size_impl(NullableRef<Desc>, AddrT) noexcept {
  return sizeof(AddrT);
}

template <IsDescriptor Desc, std::size_t N, IsAddress AddrT>
consteval std::size_t byte_size_impl(Array<Desc, N>, AddrT) noexcept {
  return N * byte_size<Desc, AddrT>();
}

template <IsDescriptor Desc, std::size_t MaxLen, IsAddress AddrT>
consteval std::size_t byte_size_impl(Vector<Desc, MaxLen>, AddrT) noexcept {
  return 2 * sizeof(AddrT);
}

template <
  IsDescriptor Desc,
  auto Next,
  ListKind Kind,
  std::size_t MaxLen,
  IsAddress AddrT>
consteval std::size_t byte_size_impl(
  List<Desc, Next, Kind, MaxLen>, AddrT
) noexcept {
  return sizeof(AddrT);
}

template <typename T, IsFieldsItem... Items, IsAddress AddrT>
consteval std::size_t byte_size_impl(
  Struct<T, Fields<Items...>>, AddrT
) noexcept {
  std::size_t offset = 0;
  (
    [&] {
      if constexpr (requires { Items::skip; })
        offset += Items::skip;
      else if constexpr (requires { Items::seek; })
        offset = Items::seek;
      else
        offset += byte_size<typename Items::desc_type, AddrT>();
    }(),
    ...
  );
  return offset;
}

}  // namespace mempeep::detail

namespace mempeep {

/**
 * @brief Size in bytes of a descriptor.
 *
 * Returns the number of bytes consumed in remote memory by descriptor
 * @p Desc when the reader uses address type @p AddrT.
 *
 * For descriptors whose remote size depends on the address type (e.g.
 * @ref Ref, @ref Vector), @p AddrT determines the size of each address.
 * For purely fixed-size descriptors (e.g. @ref Primitive, @ref ZString),
 * @p AddrT is unused but must still be provided for a uniform call site.
 *
 * @tparam Desc  The descriptor whose remote byte size is queried.
 * @tparam AddrT The address type of the memory reader. Must satisfy
 *               @ref IsAddress.
 * @return Byte size as a @c std::size_t compile-time constant.
 */
template <IsDescriptor Desc, IsAddress AddrT>
consteval std::size_t byte_size() noexcept {
  return detail::byte_size_impl(Desc{}, AddrT{});
}

}  // namespace mempeep