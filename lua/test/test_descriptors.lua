local d = require("mempeep.descriptors")

do
  d.assert_string("hello world")
  local ok, err = pcall(d.assert_string, 1337)
  assert(not ok)
end

do
  d.assert_fmt("I1")
  d.assert_fmt("I2")
  d.assert_fmt("I4")
  d.assert_fmt("I8")
  d.assert_fmt("i1")
  d.assert_fmt("i2")
  d.assert_fmt("i4")
  d.assert_fmt("i8")
  d.assert_fmt("f")
  d.assert_fmt("d")
end

do
  d.assert_uint_fmt("I1")
  d.assert_uint_fmt("I2")
  d.assert_uint_fmt("I4")
  d.assert_uint_fmt("I8")
  local ok, err = pcall(d.assert_uint_fmt, "i4")
  assert(not ok)
end

do
  d.assert_count(0)
  d.assert_count(0x1000)
  local ok, err = pcall(d.assert_count, -1)
  assert(not ok)
end

do
  d.assert_descriptor(d.Primitive("i4"))
  d.assert_descriptor(d.Int32)
  d.assert_descriptor(d.UInt32)
  d.assert_descriptor(d.RawAddr())
  d.assert_descriptor(d.Ref(d.Int32))
  d.assert_descriptor(d.NullableRef(d.Int32))
  d.assert_descriptor(d.Array(d.Int32, 10))
  d.assert_descriptor(d.Vector(d.Int32, 0x1000))
  local Node = d.assert_descriptor(d.Struct("Node", { d.Field(d.Int32, "data"), d.Field(d.RawAddr(), "next") }))
  d.assert_descriptor(d.CircularList(Node, "next", 0x1000))
end
