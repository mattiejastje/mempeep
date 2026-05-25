#pragma once

#include <concepts>  // std::same_as
#include <cstddef>   // std::size_t
#include <mempeep/detail/concepts/descriptor.hpp>
#include <mempeep/detail/concepts/fields_item.hpp>
#include <mempeep/detail/member_traits.hpp>

// In this file we set up everything for the Struct descriptor.
// The syntax is `Struct<T, Fields<Field<...>, Skip<...>, Seek<...>, ...>>`.
// So we need `Field`, `Skip`, `Seek`, and `Fields`.
// `Struct` is defined in `descriptor.hpp` along with the other descriptors.

namespace mempeep {

/**
 * @brief A field of a struct.
 *
 * Example: `Field<Primitive<int>, &X::x>`.
 *
 * @tparam Desc The descriptor (how it is stored in remote memory).
 * @tparam M    The field to deserialize into (where it is copied to natively).
 */
template <IsDescriptor Desc, auto M>
  requires std::same_as<native_type_t<Desc>, member_type_t<M>>
struct Field {
  using fields_item_tag = void;
  using desc_type = Desc;
};

/**
 * @brief Skip relative to the current position in the layout.
 * @tparam N Number of bytes.
 */
template <std::ptrdiff_t N>
struct Skip {
  using fields_item_tag = void;
  static constexpr std::ptrdiff_t skip = N;
};

/**
 * @brief Absolute offset relative to base position of the layout.
 *
 * Seeks are not required to be monotonically increasing. This allows
 * skipping around a non-linear layout. It is the caller's responsibility to
 * ensure the offsets are correct.
 *
 * @tparam N The offset in bytes.
 */
template <std::ptrdiff_t N>
struct Seek {
  using fields_item_tag = void;
  static constexpr std::ptrdiff_t seek = N;
};

/**
 * @brief Sequence of field items.
 *
 * @tparam Items The field items, mapping the memory layout.
 */
template <IsFieldsItem... Items>
struct Fields {};

}  // namespace mempeep