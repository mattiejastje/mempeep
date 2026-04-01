// not a doctest since we only need static_asserts
#include <cstdint>
#include <mempeep/read_size.hpp>

using namespace mempeep;

struct Obj {
  int32_t x;
  int32_t y;
};

using TObj = Struct<
  Obj,
  Fields<
    Skip<4>,
    Field<Primitive<int32_t>, &Obj::x>,
    Skip<8>,
    Field<Primitive<int32_t>, &Obj::y>>>;

using TObjSeek = Struct<
  Obj,
  Fields<
    Skip<4>,
    Field<Primitive<int32_t>, &Obj::x>,
    Seek<10>,
    Field<Primitive<int32_t>, &Obj::y>>>;

struct Node {
  Obj data;
  uint64_t next_node;
};

using TNode = Struct<
  Node,
  Fields<Field<TObj, &Node::data>, Field<RawAddr<uint64_t>, &Node::next_node>>>;

static_assert(read_size<Primitive<int8_t>, 4> == 1);
static_assert(read_size<Primitive<int16_t>, 4> == 2);
static_assert(read_size<Primitive<int32_t>, 4> == 4);
static_assert(read_size<Primitive<int64_t>, 4> == 8);
static_assert(read_size<Primitive<int8_t>, 8> == 1);
static_assert(read_size<Primitive<int16_t>, 8> == 2);
static_assert(read_size<Primitive<int32_t>, 8> == 4);
static_assert(read_size<Primitive<int64_t>, 8> == 8);
static_assert(read_size<Primitive<Obj>, 4> == 8);
static_assert(read_size<Primitive<Obj>, 8> == 8);
static_assert(read_size<RawAddr<uint64_t>, 4> == 4);
static_assert(read_size<RawAddr<uint64_t>, 8> == 8);
static_assert(read_size<Ref<Primitive<Obj>>, 4> == 4);
static_assert(read_size<Ref<Primitive<Obj>>, 8> == 8);
static_assert(read_size<NullableRef<Primitive<Obj>>, 4> == 4);
static_assert(read_size<NullableRef<Primitive<Obj>>, 8> == 8);
static_assert(read_size<Array<Primitive<Obj>, 10>, 4> == 80);
static_assert(read_size<Array<Primitive<Obj>, 10>, 8> == 80);
static_assert(read_size<Vector<Primitive<Obj>, 0x1000>, 4> == 8);
static_assert(read_size<Vector<Primitive<Obj>, 0x1000>, 8> == 16);
static_assert(read_size<CircularList<TNode, &Node::next_node, 0x1000>, 4> == 4);
static_assert(read_size<CircularList<TNode, &Node::next_node, 0x1000>, 8> == 8);
static_assert(read_size<TObj, 4> == 20);
static_assert(read_size<TObj, 8> == 20);
static_assert(read_size<TObjSeek, 4> == 14);
static_assert(read_size<TObjSeek, 8> == 14);

int main() { return 0; };
