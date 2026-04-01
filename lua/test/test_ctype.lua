local d = require("mempeep.descriptors")
local c = require("mempeep.ctype")

local Int8 = d.Primitive("i1")
local Int16 = d.Primitive("i2")
local Int32 = d.Primitive("i4")
local Int64 = d.Primitive("i8")
local Point = d.Struct("Point", { d.Field(Int16, "x"), d.Seek(8), d.Field(Int16, "y"), d.Skip(2) })
local Node = d.Struct("Node", { d.Field(Int64, "data"), d.Field(d.RawAddr(), "next") })

do
  local size, typ = c.desc_to_ctype(Int8, 4)
  assert(size == 1)
  assert(typ == "int8_t")
end

do
  local size, typ = c.desc_to_ctype(Int64, 4)
  assert(size == 8)
  assert(typ == "int64_t")
end

do
  local size, typ = c.desc_to_ctype(Point, 4)
  assert(size == 12)
  assert(typ == "Point")
end

do
  local size, typ = c.desc_to_ctype(d.RawAddr(), 4)
  assert(size == 4)
  assert(typ == "void*")
end

do
  local size, typ = c.desc_to_ctype(d.RawAddr(), 8)
  assert(size == 8)
  assert(typ == "void*")
end

do
  local size, typ = c.desc_to_ctype(d.Ref(Point), 4)
  assert(size == 4)
  assert(typ == "Point*")
end

do
  local size, typ = c.desc_to_ctype(d.Ref(Point), 8)
  assert(size == 8)
  assert(typ == "Point*")
end

do
  local size, typ = c.desc_to_ctype(d.NullableRef(Point), 4)
  assert(size == 4)
  assert(typ == "Point*")
end

do
  local size, typ = c.desc_to_ctype(d.NullableRef(Point), 8)
  assert(size == 8)
  assert(typ == "Point*")
end

do
  local size, typ = c.desc_to_ctype(d.Array(Point, 10), 4)
  assert(size == 120)
  assert(typ == "std::array<Point, 10>")
end

do
  local size, typ = c.desc_to_ctype(d.Vector(Point, 0x1000), 4)
  assert(size == 8)
  assert(typ == "std::vector<Point>")
end

do
  local size, typ = c.desc_to_ctype(d.Vector(Point, 0x1000), 8)
  assert(size == 16)
  assert(typ == "std::vector<Point>")
end

do
  local size, typ = c.desc_to_ctype(d.CircularList(Node, "next", 0x1000), 4)
  assert(size == 4)
  assert(typ == "Node*")
end

do
  local size, typ = c.desc_to_ctype(d.CircularList(Node, "next", 0x1000), 8)
  assert(size == 8)
  assert(typ == "Node*")
end

do
  c.struct_to_cdecl(Point)
end
