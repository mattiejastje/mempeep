// not a doctest since we only need static_asserts
#include <cstdint>
#include <mempeep/size.hpp>

using namespace mempeep;

static_assert(byte_size<Int8, uint32_t>() == 1);
static_assert(byte_size<Int16, uint32_t>() == 2);
static_assert(byte_size<Int32, uint32_t>() == 4);
static_assert(byte_size<Int64, uint32_t>() == 8);
static_assert(byte_size<UInt8, uint32_t>() == 1);
static_assert(byte_size<UInt16, uint32_t>() == 2);
static_assert(byte_size<UInt32, uint32_t>() == 4);
static_assert(byte_size<UInt64, uint32_t>() == 8);
static_assert(byte_size<Float, uint32_t>() == 4);
static_assert(byte_size<Double, uint32_t>() == 8);
static_assert(byte_size<RemoteAddr<Int16, uint32_t>, uint32_t>() == 2);
static_assert(byte_size<RemoteAddr<Int64, uint32_t>, uint32_t>() == 8);

static_assert(byte_size<Bounded<Int32, -10, 10>, uint32_t>() == 4);

static_assert(byte_size<ZString<16>, uint32_t>() == 16);
static_assert(byte_size<ZString<256>, uint32_t>() == 256);
static_assert(byte_size<RemoteAddr<ZString<256>, uint32_t>, uint32_t>() == 256);

static_assert(byte_size<RawAddr<uint32_t>, uint32_t>() == 4);
static_assert(byte_size<RawAddr<uint64_t>, uint64_t>() == 8);

static_assert(byte_size<Ref<Int32>, uint32_t>() == 4);
static_assert(byte_size<Ref<Int32>, uint64_t>() == 8);
static_assert(byte_size<NullableRef<Int32>, uint32_t>() == 4);
static_assert(byte_size<NullableRef<Int32>, uint64_t>() == 8);

static_assert(byte_size<Array<Int32, 4>, uint32_t>() == 16);
static_assert(byte_size<Array<Int32, 4>, uint64_t>() == 16);
static_assert(byte_size<Array<Ref<Int32>, 4>, uint32_t>() == 16);
static_assert(byte_size<Array<Ref<Int32>, 4>, uint64_t>() == 32);

static_assert(byte_size<Vector<Int32, 0x1000>, uint32_t>() == 8);
static_assert(byte_size<Vector<Int32, 0x1000>, uint64_t>() == 16);

struct Node {
  uint64_t id;
  uint64_t next;
};

using TNode = Primitive<Node>;

static_assert(
  byte_size<List<TNode, &Node::next, ListKind::CIRCULAR, 0x1000>, uint32_t>()
  == 4
);
static_assert(
  byte_size<List<TNode, &Node::next, ListKind::CIRCULAR, 0x1000>, uint64_t>()
  == 8
);

struct Flat {
  int32_t x;
  int32_t y;
};

using TFlat
  = Struct<Flat, Fields<Field<Int32, &Flat::x>, Field<Int32, &Flat::y>>>;

static_assert(byte_size<TFlat, uint32_t>() == 8);

struct Sparse {
  int32_t x;
  int32_t y;
};

// Seek<8> sets offset to 8, Field<Int32> advances to 12, Skip<2> advances to 14
using TSparse = Struct<
  Sparse,
  Fields<Field<Int32, &Sparse::x>, Seek<8>, Field<Int32, &Sparse::y>, Skip<2>>>;

static_assert(byte_size<TSparse, uint32_t>() == 14);

struct WithRef {
  int32_t a;
  int32_t b;
};

using TWithRef = Struct<
  WithRef,
  Fields<Field<Int32, &WithRef::a>, Field<Ref<Int32>, &WithRef::b>>>;

static_assert(byte_size<TWithRef, uint32_t>() == 8);
static_assert(byte_size<TWithRef, uint64_t>() == 12);

struct Inner {
  int32_t a;
  int32_t b;
};

struct Outer {
  Inner inner;
  int32_t c;
};

using TInner
  = Struct<Inner, Fields<Field<Int32, &Inner::a>, Field<Int32, &Inner::b>>>;

using TOuter = Struct<
  Outer,
  Fields<Field<TInner, &Outer::inner>, Field<Int32, &Outer::c>>>;

static_assert(byte_size<TInner, uint32_t>() == 8);
static_assert(byte_size<TOuter, uint32_t>() == 12);

struct Outer2 {
  RemoteValue<TInner, uint32_t> inner;
  int32_t c;
};

using TOuter2 = Struct<
  Outer,
  Fields<
    Field<RemoteAddr<TInner, uint32_t>, &Outer2::inner>,
    Field<Int32, &Outer2::c>>>;

static_assert(byte_size<TOuter2, uint32_t>() == 12);

int main() { return 0; }