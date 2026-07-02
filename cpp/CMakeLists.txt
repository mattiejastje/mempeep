add_library(mempeep INTERFACE)

option(MEMPEEP_USE_FMTLIB "Use fmt::formatter instead of std::formatter in log_tracer.hpp" OFF)

target_include_directories(mempeep INTERFACE include)
target_compile_features(mempeep INTERFACE cxx_std_23)

if(CMAKE_PROJECT_NAME STREQUAL PROJECT_NAME AND BUILD_TESTING)
  find_package(doctest CONFIG REQUIRED)
  add_subdirectory(test)
  if(NOT ENABLE_COVERAGE)
    add_subdirectory(examples)
  endif()
endif()