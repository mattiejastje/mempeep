local d = require("mempeep.descriptors")
local c = require("mempeep.ctypes")

local Point = d.Struct("Point", { d.Field(d.Int16, "x"), d.Seek(8), d.Field(d.Int16, "y"), d.Skip(2) })
local Node = d.Struct("Node", { d.Field(d.Int64, "data"), d.Field(d.RawAddr(), "next") })
local Points = d.Struct("Points", { d.Field(d.Vector(Point, 0x1000), "points") })

do
  local size, typ = c.remote_ctype(d.Int8, 4)
  assert(size == 1)
  assert(typ == "int8_t")
end

do
  local size, typ = c.remote_ctype(d.Int64, 4)
  assert(size == 8)
  assert(typ == "int64_t")
end

do
  local size, typ = c.remote_ctype(Point, 4)
  assert(size == 12)
  assert(typ == "Point")
end

do
  local size, typ = c.remote_ctype(d.RawAddr(), 4)
  assert(size == 4)
  assert(typ == "void*")
end

do
  local size, typ = c.remote_ctype(d.RawAddr(), 8)
  assert(size == 8)
  assert(typ == "void*")
end

do
  local size, typ = c.remote_ctype(d.Ref(Point), 4)
  assert(size == 4)
  assert(typ == "Point*")
end

do
  local size, typ = c.remote_ctype(d.Ref(Point), 8)
  assert(size == 8)
  assert(typ == "Point*")
end

do
  local size, typ = c.remote_ctype(d.NullableRef(Point), 4)
  assert(size == 4)
  assert(typ == "Point*")
end

do
  local size, typ = c.remote_ctype(d.NullableRef(Point), 8)
  assert(size == 8)
  assert(typ == "Point*")
end

do
  local size, typ = c.remote_ctype(d.Array(Point, 10), 4)
  assert(size == 120)
  assert(typ == "std::array<Point, 0xa>")
end

do
  local size, typ = c.remote_ctype(d.Vector(Point, 0x1000), 4)
  assert(size == 8)
  assert(typ == "Point*")
end

do
  local size, typ = c.remote_ctype(d.Vector(Point, 0x1000), 8)
  assert(size == 16)
  assert(typ == "Point*")
end

do
  local size, typ = c.remote_ctype(d.CircularList(Node, "next", 0x1000), 4)
  assert(size == 4)
  assert(typ == "Node*")
end

do
  local size, typ = c.remote_ctype(d.CircularList(Node, "next", 0x1000), 8)
  assert(size == 8)
  assert(typ == "Node*")
end

local mock_out = function(text)
  local lines = {}
  for line in text:gmatch("[^\n]+") do
    table.insert(lines, line)
  end
  local out = {}
  function out:write(s)
    for line in s:gmatch("[^\n]+") do
      assert(line == lines[1], "expected '" .. lines[1] .. "' but got '" .. s .. "'")
    end
    table.remove(lines, 1)
  end
  return out
end

do
  c.remote_struct_cdecls(Points, 4, mock_out([[
struct Point {
  int16_t x;  // offset 0x0
  int8_t _pad0[0x6];
  int16_t y;  // offset 0x8
  int8_t _pad1[0x2];
};
struct Points {
  Point* points_begin;  // offset 0x0
  Point* points_end;    // offset 0x4
};]]))
  c.native_struct_cdecls(Points, "", mock_out([[
struct Point {
  int16_t x;
  uint8_t _pad0[0x6];
  int16_t y;
  uint8_t _pad1[0x2];
};
struct Points {
  std::vector<Point> points;
};
using TPoints = Struct<
  Points,
  Fields<
    Field<Vector<Primitive<Point>, 0x1000>, &Points::points>>>;
]]))
end

-- native_struct_cdecls: flat struct (no padding) emits Primitive alias
do
  local Flat = d.Struct("Flat", { d.Field(d.Int16, "x"), d.Field(d.Int16, "y") })
  c.native_struct_cdecls(Flat, "", mock_out([[
struct Flat {
  int16_t x;
  int16_t y;
};
]]))
end

-- native_struct_cdecls: Struct with Skip emits padding members and Primitive alias
do
  local Padded = d.Struct("Padded", { d.Field(d.Int16, "x"), d.Skip(2), d.Field(d.Int16, "y"), d.Skip(2) })
  c.native_struct_cdecls(Padded, "", mock_out([[
struct Padded {
  int16_t x;
  uint8_t _pad0[0x2];
  int16_t y;
  uint8_t _pad1[0x2];
};
]]))
end

-- native_struct_cdecls: Struct with Seek emits padding members and Primitive alias
do
  local Sparse = d.Struct("Sparse", { d.Field(d.Int16, "x"), d.Seek(8), d.Field(d.Int16, "y"), d.Skip(2) })
  c.native_struct_cdecls(Sparse, "", mock_out([[
struct Sparse {
  int16_t x;
  uint8_t _pad0[0x6];
  int16_t y;
  uint8_t _pad1[0x2];
};
]]))
end

-- native_struct_cdecls: Struct with Bounded field emits Primitive alias
do
  local Bounded = d.Struct("Bounded", { d.Field(d.Bounded(d.Int32, 0, 100), "a") })
  c.native_struct_cdecls(Bounded, "", mock_out([[
struct Bounded {
  int32_t a;
};
]]))
end

-- native_struct_cdecls: Struct with Array field emits Primitive alias
do
  local WithArray = d.Struct("WithArray", { d.Field(d.Array(d.Int16, 4), "items") })
  c.native_struct_cdecls(WithArray, "", mock_out([[
struct WithArray {
  std::array<int16_t, 0x4> items;
};
]]))
end

-- native_struct_cdecls: non-primitive Struct with primitive Array field emits Primitive descriptor
do
  local WithPrimArray = d.Struct("WithPrimArray", { d.Field(d.Ref(d.Int32), "a"), d.Field(d.Array(d.Int16, 4), "items") })
  c.native_struct_cdecls(WithPrimArray, "", mock_out([[
struct WithPrimArray {
  int32_t a;
  std::array<int16_t, 0x4> items;
};
using TWithPrimArray = Struct<
  WithPrimArray,
  Fields<
    Field<Ref<Int32>, &WithPrimArray::a>,
    Field<Primitive<std::array<int16_t, 0x4>>, &WithPrimArray::items>>>;
]]))
end

-- native_struct_cdecls: nested compatible Structs emit Primitive aliases
do
  local Inner = d.Struct("Inner", { d.Field(d.Int16, "a"), d.Field(d.Int16, "b") })
  local Outer = d.Struct("Outer", { d.Field(Inner, "inner"), d.Field(d.Int32, "c") })
  c.native_struct_cdecls(Outer, "", mock_out([[
struct Inner {
  int16_t a;
  int16_t b;
};
struct Outer {
  Inner inner;
  int32_t c;
};
]]))
end

-- native_struct_cdecls: Struct with Ref emits full Fields alias
do
  local WithRef = d.Struct("WithRef", { d.Field(d.Int32, "a"), d.Field(d.Ref(d.Int32), "b") })
  c.native_struct_cdecls(WithRef, "", mock_out([[
struct WithRef {
  int32_t a;
  int32_t b;
};
using TWithRef = Struct<
  WithRef,
  Fields<
    Field<Int32, &WithRef::a>,
    Field<Ref<Int32>, &WithRef::b>>>;
]]))
end

-- native_struct_cdecls: Struct with RawAddr emits full Fields alias
do
  local WithAddr = d.Struct("WithAddr", { d.Field(d.Int32, "a"), d.Field(d.RawAddr(), "ptr") })
  c.native_struct_cdecls(WithAddr, "", mock_out([[
struct WithAddr {
  int32_t a;
  uintptr_t ptr;
};
using TWithAddr = Struct<
  WithAddr,
  Fields<
    Field<Int32, &WithAddr::a>,
    Field<RawAddr<uintptr_t>, &WithAddr::ptr>>>;
]]))
end

-- native_struct_cdecls: Struct with Vector emits full Fields alias
do
  local WithVec = d.Struct("WithVec", { d.Field(d.Int32, "a"), d.Field(d.Vector(d.Int32, 0x1000), "items") })
  c.native_struct_cdecls(WithVec, "", mock_out([[
struct WithVec {
  int32_t a;
  std::vector<int32_t> items;
};
using TWithVec = Struct<
  WithVec,
  Fields<
    Field<Int32, &WithVec::a>,
    Field<Vector<Int32, 0x1000>, &WithVec::items>>>;
]]))
end

-- native_struct_cdecls: nested incompatible Struct emits full Fields alias
do
  local Inner = d.Struct("Inner", { d.Field(d.Int32, "a"), d.Field(d.Ref(d.Int32), "b") })
  local Outer = d.Struct("Outer", { d.Field(Inner, "inner"), d.Field(d.Int32, "c") })
  c.native_struct_cdecls(Outer, "", mock_out([[
struct Inner {
  int32_t a;
  int32_t b;
};
using TInner = Struct<
  Inner,
  Fields<
    Field<Int32, &Inner::a>,
    Field<Ref<Int32>, &Inner::b>>>;
struct Outer {
  Inner inner;
  int32_t c;
};
using TOuter = Struct<
  Outer,
  Fields<
    Field<TInner, &Outer::inner>,
    Field<Int32, &Outer::c>>>;
]]))
end