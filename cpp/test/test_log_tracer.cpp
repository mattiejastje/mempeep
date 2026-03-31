#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest/doctest.h>

#include <mempeep/read.hpp>
#include <mempeep/test/memory.hpp>
#include <mempeep/tracers/log_tracer.hpp>

using namespace mempeep;

using TInt32 = Primitive<int32_t>;

struct Inner {
  int32_t a;
  int32_t b;
};

using TInner
  = Struct<Inner, Fields<Field<TInt32, &Inner::a>, Field<TInt32, &Inner::b>>>;

struct Outer {
  Inner inner;
  int32_t c;
};

using TOuter = Struct<
  Outer,
  Fields<Field<TInner, &Outer::inner>, Field<TInt32, &Outer::c>>>;

TEST_CASE("simple") {
  auto reader = test::MockMemoryReader<uint8_t>{
    "\x0B\x00\x00\x00\x16\x00\x00\x00\x21\x00\x00\x00"
  };
  Outer outer{};
  std::stringstream out;
  auto tracer = LogTracer{on_entry_print(out), LogLevel::VALUES};
  CHECK(read<TOuter>(0, reader, tracer, outer));
  CHECK_EQ(out.str(), R"([00000000] .inner.a = 0xb
[00000004] .inner.b = 0x16
[00000008] .c = 0x21
)");
  CHECK_EQ(outer.inner.a, 0x0b);
  CHECK_EQ(outer.inner.b, 0x16);
  CHECK_EQ(outer.c, 0x21);
  CHECK(tracer.success());
}
