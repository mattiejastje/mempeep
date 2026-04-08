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
  assert(typ == "std::array<Point, 10>")
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

do
  local size, typ = c.remote_ctype(d.PrimitiveArray("i2", {3}), 4)
  assert(size == 6)
  assert(typ == "std::array<int16_t, 3>")
end

do
  local size, typ = c.remote_ctype(d.PrimitiveArray("I1", {2, 3}), 4)
  assert(size == 6)
  assert(typ == "std::array<std::array<uint8_t, 3>, 2>")
end

do
  local size, typ = c.remote_ctype(d.PrimitiveArray("i4", {4, 3, 2}), 4)
  assert(size == 96)
  assert(typ == "std::array<std::array<std::array<int32_t, 2>, 3>, 4>")
end

do
  c.remote_struct_cdecls(Points, 4, io.stdout)
  c.native_struct_cdecls(Points, "", io.stdout)
end
