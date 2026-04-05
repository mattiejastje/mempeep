#pragma once

#include <cstddef>     // std::size_t
#include <cstdint>     // std::uint64_t
#include <format>      // std::format_to
#include <mempeep/descriptors.hpp>
#include <mempeep/errors.hpp>
#include <nameof.hpp>
#include <ostream>  // std::ostream
#include <print>    // std::print
#include <ranges>   // std::ranges
#include <string_view>
#include <variant>
#include <vector>

namespace mempeep {

enum class LogLevel {
  ERRORS = 0,
  VALUES = 1,
};

/**
 * @brief A single path segment, either a named field or an array index.
 *
 * Named field segments hold a string_view into the compile-time string
 * produced by nameof: no ownership required. Index segments hold the
 * zero-based integer index directly. No string conversion is performed
 * until the segment is formatted.
 */
using PathSegment = std::variant<std::string_view, std::size_t>;

/**
 * @brief A single structured log entry produced during a read.
 *
 * Carries either a successfully read value or an error code, along with
 * the remote address and the path to the field being read.
 * Callers may inspect `payload` to distinguish values from errors.
 * 
 * All fields are non-owning views or references into data owned by the
 * LogTracer that constructed this entry. The entry must not outlive the
 * value() or error() call that created it.
 *
 * @tparam T The type of the payload: a primitive value type, or Error.
 */
template <typename T>
struct LogEntry {
  /** @brief Remote address at which the read was attempted. */
  std::uint64_t address;

  /** @brief Reference to the tracer's live path stack. */
  const std::vector<PathSegment>& path;

  /** @brief Reference to the raw payload value or error code. */
  const T& payload;
};

}  // namespace mempeep

// ---------------------------------------------------------------------------
// std::formatter specialisations, defined outside the mempeep namespace.
// ---------------------------------------------------------------------------

/**
 * Formats a PathSegment as either ".fieldname" or "[index]".
 */
template <>
struct std::formatter<mempeep::PathSegment> {
  constexpr auto parse(std::format_parse_context& ctx) { return ctx.begin(); }

  template <typename FormatContext>
  auto format(const mempeep::PathSegment& seg, FormatContext& ctx) const {
    return std::visit(
      [&ctx](const auto& v) {
        if constexpr (std::is_same_v<
                        std::decay_t<decltype(v)>,
                        std::string_view>) {
          return std::format_to(ctx.out(), ".{}", v);
        } else {
          return std::format_to(ctx.out(), "[{}]", v);
        }
      },
      seg
    );
  }
};

/**
 * Formats a LogEntry<T> by walking the path stack and formatting the
 * payload on demand. No intermediate strings are constructed.
 *
 * Output format:
 *   values: [address] .field[index]... = <value>
 *   errors: [address] .field[index]... ! <error name>
 */
template <typename T>
struct std::formatter<mempeep::LogEntry<T>> {
  constexpr auto parse(std::format_parse_context& ctx) { return ctx.begin(); }

  template <typename FormatContext>
  auto format(const mempeep::LogEntry<T>& entry, FormatContext& ctx) const {
    auto out = std::format_to(ctx.out(), "[{:08x}] ", entry.address);
    for (const auto& seg : entry.path) {
      out = std::format_to(out, "{}", seg);
    }
    if constexpr (std::is_same_v<T, mempeep::Error>) {
      out = std::format_to(out, " ! {}", mempeep::error_name(entry.payload));
    } else if constexpr (std::is_integral_v<T>) {
      out = std::format_to(out, " = {:#x}", entry.payload);
    } else if constexpr (std::formattable<T, char>) {
      out = std::format_to(out, " = {}", entry.payload);
    } else {
      out = std::format_to(out, " = ...");
    }
    return out;
  }
};

namespace mempeep {

/**
 * @brief Log tracer that defers all string formatting to the callback.
 *
 * Maintains a path stack of PathSegment variants and an address stack of
 * uint64_t. On each primitive read or error, constructs a LogEntry holding
 * non-owning references into these stacks and invokes the callback. No heap
 * allocations occur in the hot path.
 *
 * The callback must be a callable accepting a const LogEntry<T>& for any T
 * that may appear as a primitive native type, and also const LogEntry<Error>&.
 * The simplest way to satisfy this is a struct with a templated operator().
 *
 * LogTracer is templated on OnLogEntry so the call can be inlined by the
 * compiler. Use the OnEntryPrint() helper to
 * obtain a suitable callback for writing to a stream.
 *
 * @tparam OnLogEntry Callable type invoked once per log entry.
 */
template <typename OnLogEntry>
struct LogTracer {
  OnLogEntry on_log_entry;
  LogLevel level = LogLevel::ERRORS;
  bool ok = true;

  /**
   * @brief Path stack: each entry is either a named field (string_view)
   * or an array index (size_t). Built incrementally; never converted to a
   * string until the entry is formatted inside the callback.
   */
  std::vector<PathSegment> path_stack;

  /** @brief Address stack, one entry per active begin_desc call. */
  std::vector<std::uint64_t> addr_stack;

  void error(Error e) {
    ok = false;
    on_log_entry(
      LogEntry<Error>{
        .address = addr_stack.empty() ? 0u : addr_stack.back(),
        .path = path_stack,
        .payload = e,
      }
    );
  }

  bool success() const { return ok; }

  template <typename T>
  void value(const T& val) {
    if (level >= LogLevel::VALUES) {
      on_log_entry(
        LogEntry<T>{
          .address = addr_stack.empty() ? 0u : addr_stack.back(),
          .path = path_stack,
          .payload = val,
        }
      );
    }
  }

  template <typename Item>
  void begin_fields_item(std::uint64_t, Item) {
    path_stack.emplace_back(std::string_view{});
  }

  template <IsDescriptor Desc, auto M>
  void begin_fields_item(std::uint64_t, Field<Desc, M>) {
    path_stack.emplace_back(nameof::nameof_member<M>());
  }

  void end_fields_item() { path_stack.pop_back(); }

  void begin_element(std::uint64_t, std::size_t index) {
    path_stack.emplace_back(index);
  }

  void end_element() { path_stack.pop_back(); }

  template <typename Desc>
  void begin_desc(std::uint64_t address, Desc) {
    addr_stack.emplace_back(address);
  }

  void end_desc() { addr_stack.pop_back(); }
};

// ---------------------------------------------------------------------------
// Built-in callback helpers
// ---------------------------------------------------------------------------

/**
 * @brief Callback struct that prints each LogEntry to a stream.
 *
 * Templated operator() satisfies the requirement that the callback accept
 * LogEntry<T> for any T.
 */
struct OnLogEntryPrint {
  std::ostream& out;

  template <typename T>
  void operator()(const LogEntry<T>& entry) const {
    std::print(out, "{}\n", entry);
  }
};

}  // namespace mempeep