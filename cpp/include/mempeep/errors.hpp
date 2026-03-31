#pragma once

#include <string_view>

namespace mempeep {

enum class Error {
  READ_FAILED,
  ADDRESS_NULL,
  ADDRESS_OVERFLOW,
  CIRCULAR_LIST_TOO_LONG,
  PRIMITIVE_OUT_OF_BOUNDS,
  STRING_TOO_LONG,
  VECTOR_INVALID_RANGE,
  VECTOR_MISALIGNED,
  VECTOR_TOO_LONG,
};

constexpr std::string_view error_name(Error e) {
  switch (e) {
    case Error::READ_FAILED:
      return "READ_FAILED";
    case Error::ADDRESS_NULL:
      return "ADDRESS_NULL";
    case Error::ADDRESS_OVERFLOW:
      return "ADDRESS_OVERFLOW";
    case Error::CIRCULAR_LIST_TOO_LONG:
      return "CIRCULAR_LIST_TOO_LONG";
    case Error::PRIMITIVE_OUT_OF_BOUNDS:
      return "PRIMITIVE_OUT_OF_BOUNDS";
    case Error::STRING_TOO_LONG:
      return "STRING_TOO_LONG";
    case Error::VECTOR_INVALID_RANGE:
      return "VECTOR_INVALID_RANGE";
    case Error::VECTOR_MISALIGNED:
      return "VECTOR_MISALIGNED";
    case Error::VECTOR_TOO_LONG:
      return "VECTOR_TOO_LONG";
    default:
      return "UNKNOWN_ERROR";
  }
}

}