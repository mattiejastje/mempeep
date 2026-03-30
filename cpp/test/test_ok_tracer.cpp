#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <mempeep/tracers/ok_tracer.hpp>

using namespace mempeep;

TEST_CASE("init") {
  OkTracer tracer{};
  CHECK(tracer.success());
}

TEST_CASE("error") {
  OkTracer tracer{};
  tracer.error(Error::READ_FAILED);
  CHECK(!tracer.success());
}