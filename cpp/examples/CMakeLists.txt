file(GLOB TEST_SOURCES "*.cpp")
foreach(TEST_SOURCE ${TEST_SOURCES})
  cmake_path(GET TEST_SOURCE STEM TEST_NAME)
  add_executable(${TEST_NAME} ${TEST_SOURCE})
  # nameof is required only by tracers/log_tracer.hpp.
  # Users who do not use this header do not need it.
  target_link_libraries(${TEST_NAME} PRIVATE mempeep nameof::nameof)
  add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
endforeach()