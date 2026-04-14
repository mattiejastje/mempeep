#pragma once

#include <concepts>                 // std::same_as, std::convertible_to
#include <cstdint>                  // std::uint64_t, std::size_t
#include <mempeep/descriptors.hpp>  // Primitive, Skip (representative tag types)
#include <mempeep/errors.hpp>       // Error

namespace mempeep {

/**
 * @brief Observes all read operations and summarises whether any errors
 * occurred.
 *
 * error() is called once per error encountered during a read. It receives
 * an Error value describing what went wrong. The same error code may be
 * reported multiple times if multiple reads fail.
 *
 * success() is called once at the end of a read to determine the return
 * value of mempeep::read(). By convention it returns true if no errors
 * were reported and false otherwise, but callers should not assume this:
 * a tracer may implement custom logic, for example treating certain error
 * codes as non-fatal.
 * 
 * @note This concept is checked against representative argument types only.
 * Implementations must accept any IsFieldsItem for begin_fields_item and
 * any IsDescriptor for begin_desc. The simplest way to satisfy this is a
 * templated method:
 * 
 * @code
 * template <IsFieldsItem Item>
 * void begin_fields_item(std::uint64_t address, Item item) {}
 *
 * template <IsDescriptor Desc>
 * void begin_desc(std::uint64_t address, Desc desc) {}
 * @endcode
 *
 * @tparam Tracer The type to check.
 */
template <typename Tracer>
concept IsTracer = requires(
  Tracer& tracer, Error error, std::uint64_t address, std::size_t index
) {
  // Error reporting and final result.
  { tracer.error(error) } -> std::same_as<void>;
  { tracer.success() } -> std::convertible_to<bool>;

  // Called after each successful Primitive read.
  // Checked with 0 as representative.
  { tracer.value(0) } -> std::same_as<void>;

  // Called around each fields item (Field, Skip, Seek) inside a Struct.
  // begin_item receives the address and a tag value (e.g. Skip<N>{},
  // Field<Desc,M>{}, Seek<N>{}). Checked here with Skip<0> as a
  // representative.
  { tracer.begin_fields_item(address, Skip<0>{}) } -> std::same_as<void>;
  { tracer.end_fields_item() } -> std::same_as<void>;

  // Called around each element of a container
  // (such as Array, Vector, or CircularList).
  // index is the zero-based position of the element.
  { tracer.begin_element(address, index) } -> std::same_as<void>;
  { tracer.end_element() } -> std::same_as<void>;

  // Called around each descriptor read (Primitive, Struct, Ref, ...).
  // begin_desc receives the address and a tag value (e.g. Primitive<T>{},
  // Struct<T,F>{}, ...). Checked here with Primitive<int> as a
  // representative.
  { tracer.begin_desc(address, Primitive<int>{}) } -> std::same_as<void>;
  { tracer.end_desc() } -> std::same_as<void>;
};

}  // namespace mempeep