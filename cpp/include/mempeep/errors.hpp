#pragma once

#include <string_view>

namespace mempeep {

enum class Error {
  READ_FAILED,
  ADDRESS_NULL,
  ADDRESS_OVERFLOW,
  LIST_TOO_LONG,
  LIST_UNEXPECTED_CYCLE,
  LIST_UNEXPECTED_NULL,
  PRIMITIVE_OUT_OF_BOUNDS,
  VECTOR_INVALID_RANGE,
  VECTOR_MISALIGNED,
  VECTOR_TOO_LONG,
  ZSTRING_TOO_LONG,
};

constexpr std::string_view error_name(Error e) {
  switch (e) {
    case Error::READ_FAILED:
      return "READ_FAILED";
    case Error::ADDRESS_NULL:
      return "ADDRESS_NULL";
    case Error::ADDRESS_OVERFLOW:
      return "ADDRESS_OVERFLOW";
    case Error::LIST_TOO_LONG:
      return "LIST_TOO_LONG";
    case Error::LIST_UNEXPECTED_CYCLE:
      return "LIST_UNEXPECTED_CYCLE";
    case Error::LIST_UNEXPECTED_NULL:
      return "LIST_UNEXPECTED_NULL";
    case Error::PRIMITIVE_OUT_OF_BOUNDS:
      return "PRIMITIVE_OUT_OF_BOUNDS";
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