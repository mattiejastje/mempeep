#pragma once

#include <deque>       // std::deque (used as iterable stack)
#include <format>      // std::format
#include <functional>  // std::function
#include <mempeep/descriptors.hpp>
#include <mempeep/errors.hpp>
#include <nameof.hpp>
#include <ostream>  // std::ostream
#include <print>    // std::print
#include <ranges>   // std::ranges

namespace mempeep {

enum class LogLevel {
  ERRORS = 0,
  VALUES = 1,
};

/**
 * @brief A single structured log entry produced during a read.
 *
 * Carries either a successfully read value or an error code, along with
 * the remote address and the dot-notation path to the field being read.
 * Callers may inspect `payload` to distinguish values from errors.
 */
struct LogEntry {
  /** @brief Kind of log entry. */
  enum class Kind { ERR, VAL };

  /** @brief Remote address at which the read was attempted. */
  std::uint64_t address;

  /** @brief Path to the field. */
  std::string path;

  /** @brief Formatted string representation of the value or error name. */
  std::string text;

  /** @brief Whether this entry carries a value or an error code. */
  Kind kind;
};

}  // namespace mempeep

// formatter for LogEntry, must be defined out of mempeep scope
template <>
struct std::formatter<mempeep::LogEntry> {
  constexpr auto parse(std::format_parse_context& ctx) { return ctx.begin(); }

  template <typename FormatContext>
  auto format(const mempeep::LogEntry& entry, FormatContext& ctx) const {
    const auto sep
      = (entry.kind == mempeep::LogEntry::Kind::VAL) ? " = " : " ! ";
    return std::format_to(
      ctx.out(), "[{:08x}] {}{}{}", entry.address, entry.path, sep, entry.text
    );
  }
};

namespace mempeep {

/** @brief Callback type invoked once per log entry. */
using LogCallback = std::function<void(const LogEntry&)>;

/** @brief Simple log tracer.
 *
 * Logs every primitive read and every error encountered during a read.
 * Output format: [address] path = value
 * Tracks whether any error occurred.
 */
struct LogTracer {
  LogCallback on_entry;
  LogLevel level = LogLevel::ERRORS;
  bool ok = true;
  std::deque<std::string> path_stack;
  std::deque<std::uint64_t> addr_stack;

  void error(mempeep::Error e) {
    ok = false;
    on_entry(
      LogEntry{
        .address = addr_stack.empty() ? 0u : addr_stack.back(),
        .path = std::ranges::to<std::string>(std::views::join(path_stack)),
        .text = std::string(error_name(e)),
        .kind = LogEntry::Kind::ERR,
      }
    );
  }

  bool success() const { return ok; }

  template <typename T>
  void value(const T& val) {
    if (level >= LogLevel::VALUES) {
      std::string repr;
      if constexpr (std::is_integral_v<T>) {
        repr = std::format("{:#x}", val);
      } else if constexpr (std::formattable<T, char>) {
        repr = std::format("{}", val);
      } else {
        repr = "...";
      }
      on_entry(
        LogEntry{
          .address = addr_stack.empty() ? 0u : addr_stack.back(),
          .path = std::ranges::to<std::string>(std::views::join(path_stack)),
          .text = std::move(repr),
          .kind = LogEntry::Kind::VAL,
        }
      );
    }
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

/** @brief Callback which simply prints the log entry to a stream. */
LogCallback on_entry_print(std::ostream& out) {
  return [&out](const LogEntry& entry) { std::print(out, "{}\n", entry); };
}

}  // namespace mempeep
