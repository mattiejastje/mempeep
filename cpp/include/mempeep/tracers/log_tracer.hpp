#pragma once

#include <format>
#include <mempeep/descriptor.hpp>
#include <nameof.hpp>
#include <ostream>
#include <print>

namespace mempeep::detail {

std::string build_path(const std::vector<std::string>& path_stack) {
  std::string result;
  for (const auto& part : path_stack) result += part;
  return result;
}

}  // namespace mempeep::detail

namespace mempeep {

/** @brief Simple log tracer.
 *
 * Logs every primitive read and every error encountered during a read.
 * Output format: [address] path = value
 * Tracks whether any error occurred.
 */
struct LogTracer {
  std::ostream& out;
  bool ok = true;
  std::vector<std::string> path_stack;
  std::vector<std::uint64_t> addr_stack;

  void error(mempeep::Error e) {
    ok = false;
    std::print(
      out,
      "[{:08x}] {} = {}\n",
      addr_stack.empty() ? 0 : addr_stack.back(),
      detail::build_path(path_stack),
      error_name(e)
    );
  }

  bool success() const { return ok; }

  template <typename T>
  void value(const T& val) {
    std::string repr;
    if constexpr (std::is_integral_v<T>) {
      repr = std::format("{:#x}", val);
    } else if constexpr (std::formattable<T, char>) {
      repr = std::format("{}", val);
    } else {
      repr = "...";
    }
    std::print(
      out,
      "[{:08x}] {} = {}\n",
      addr_stack.empty() ? 0 : addr_stack.back(),
      detail::build_path(path_stack),
      repr
    );
  }

  template <typename Item>
  void begin_fields_item(std::uint64_t, Item) {
    path_stack.push_back("");
  }

  template <mempeep::IsDescriptor Desc, auto M>
  void begin_fields_item(std::uint64_t, mempeep::Field<Desc, M>) {
    path_stack.push_back("." + std::string(nameof::nameof_member<M>()));
  }

  void end_fields_item() { path_stack.pop_back(); }

  void begin_element(std::uint64_t, std::size_t index) {
    path_stack.push_back("[" + std::to_string(index) + "]");
  }

  void end_element() { path_stack.pop_back(); }

  template <typename Desc>
  void begin_desc(std::uint64_t address, Desc) {
    addr_stack.push_back(address);
  }

  void end_desc() { addr_stack.pop_back(); }
};

}  // namespace mempeep