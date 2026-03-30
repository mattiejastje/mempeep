#pragma once

#include <cstddef>  // std::size_t
#include <cstdint>  // std::uint64_t
#include <mempeep/errors.hpp>

namespace mempeep {

/**
 * @brief Minimal IsTracer implementation that reports whether any error
 * occurred. Suitable when error details are not needed.
 */
struct OkTracer {
  bool ok = true;

  void error(Error) { ok = false; }

  bool success() const { return ok; }

  template <typename T>
  void value(const T&) {}

  template <typename Desc>
  void begin_desc(std::uint64_t address, Desc desc) {}

  void end_desc() {}

  template <typename FieldsItem>
  void begin_fields_item(std::uint64_t address, FieldsItem item) {}

  void end_fields_item() {}

  void begin_element(std::uint64_t address, std::size_t index) {}

  void end_element() {}
};

}  // namespace mempeep