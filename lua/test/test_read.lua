local d = require("mempeep.descriptors")
local read = require("mempeep.read")
local memory = require("mempeep.test.memory")
local ok_tracer = require("mempeep.tracers.ok_tracer")

-- ---------------------------------------------------------------------------
-- Integers
-- ---------------------------------------------------------------------------

do
  local reader = memory.mock_memory_reader("I4", "\x44\x33\x22\x11")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Int32, 0, reader, tracer)
  assert(ok)
  assert(v == 0x11223344)
end

-- non-zero offset read
do
  local reader = memory.mock_memory_reader("I4", "\xFF\xFF\x44\x33\x22\x11\xFF\xFF")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Int32, 2, reader, tracer)
  assert(ok)
  assert(v == 0x11223344)
end

-- i8 (signed, -1)
do
  local reader = memory.mock_memory_reader("I4", "\xFF")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Int8, 0, reader, tracer)
  assert(ok)
  assert(v == -1)
end

-- i16
do
  local reader = memory.mock_memory_reader("I4", "\xE8\x03")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Int16, 0, reader, tracer)
  assert(ok)
  assert(v == 1000)
end

-- i64
do
  local reader = memory.mock_memory_reader("I4", "\x15\xCD\x5B\x07\x00\x00\x00\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Int64, 0, reader, tracer)
  assert(ok)
  assert(v == 123456789)
end

-- scalar with unreadable address returns error
do
  local reader = memory.mock_memory_reader("I4", "")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Int32, 0, reader, tracer)
  assert(not ok)
  assert(v == nil)
end

-- ---------------------------------------------------------------------------
-- Struct
-- ---------------------------------------------------------------------------

-- Point{x=10, y=20}
do
  local Point = d.Struct("Point", { d.Field(d.Int32, "x"), d.Field(d.Int32, "y") })
  local reader = memory.mock_memory_reader("I4", "\x0A\x00\x00\x00\x14\x00\x00\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(Point, 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(v.x == 10)
  assert(v.y == 20)
end

-- Struct with Skip: a=1 at offset 0, 4 skip bytes, b=2 at offset 8
do
  local Skipped = d.Struct("Skipped", { d.Field(d.Int32, "a"), d.Skip(4), d.Field(d.Int32, "b") })
  local reader = memory.mock_memory_reader("I4", "\x01\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(Skipped, 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(v.a == 1)
  assert(v.b == 2)
end

-- Struct with Seek: a=7 at offset 0, b=99 at offset 8
do
  local Sparse = d.Struct("Sparse", { d.Field(d.Int32, "a"), d.Seek(8), d.Field(d.Int32, "b") })
  local reader = memory.mock_memory_reader("I4", "\x07\x00\x00\x00\x00\x00\x00\x00\x63\x00\x00\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(Sparse, 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(v.a == 7)
  assert(v.b == 99)
end

-- ---------------------------------------------------------------------------
-- Array
-- ---------------------------------------------------------------------------

-- array of 3 x i32: 10, 20, 30
do
  local reader = memory.mock_memory_reader("I4", "\x0A\x00\x00\x00\x14\x00\x00\x00\x1E\x00\x00\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Array(d.Int32, 3), 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(#v == 3)
  assert(v[1] == 10)
  assert(v[2] == 20)
  assert(v[3] == 30)
end

-- array of 2 x Point{i16 x, i16 y}: (1,2), (3,4)
do
  local Point = d.Struct("Point", { d.Field(d.Int16, "x"), d.Field(d.Int16, "y") })
  local reader = memory.mock_memory_reader("I4", "\x01\x00\x02\x00\x03\x00\x04\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Array(Point, 2), 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(#v == 2)
  assert(v[1].x == 1)
  assert(v[1].y == 2)
  assert(v[2].x == 3)
  assert(v[2].y == 4)
end

-- ---------------------------------------------------------------------------
-- Vector
-- ---------------------------------------------------------------------------

-- vector of 3 x i32: begin=8, end=20; elements 100, 200, 300
do
  local reader = memory.mock_memory_reader(
    "I4",
    "\x08\x00\x00\x00" -- begin = 8
      .. "\x14\x00\x00\x00" -- end   = 20
      .. "\x64\x00\x00\x00" -- [0] = 100
      .. "\xC8\x00\x00\x00" -- [1] = 200
      .. "\x2C\x01\x00\x00" -- [2] = 300
  )
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Vector(d.Int32, 0x1000), 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(#v == 3)
  assert(v[1] == 100)
  assert(v[2] == 200)
  assert(v[3] == 300)
end

-- Empty vector (begin == end)
do
  local reader = memory.mock_memory_reader("I4", "\x08\x00\x00\x00" .. "\x08\x00\x00\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Vector(d.Int32, 0x1000), 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(#v == 0)
end

-- Vector begin > end: error
do
  local reader = memory.mock_memory_reader("I4", "\x10\x00\x00\x00" .. "\x08\x00\x00\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Vector(d.Int32, 0x1000), 0, reader, tracer)
  assert(not ok)
  assert(v == nil)
end

-- Unreadable vector pointers
do
  local reader = memory.mock_memory_reader("I4", "")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.Vector(d.Int32, 0x1000), 0, reader, tracer)
  assert(not ok)
  assert(v == nil)
end

-- ---------------------------------------------------------------------------
-- Circular list
-- ---------------------------------------------------------------------------

-- Three-node circular list: A -> B -> C -> A
-- Each node: value(i32) at +0, next(weak ptr) at +4 => 8 bytes/node
-- head ptr at offset 0; node A at 4, B at 12, C at 20
do
  local Node = d.Struct("Node", { d.Field(d.Int32, "value"), d.Field(d.RawAddr(), "next") })
  local reader = memory.mock_memory_reader(
    "I4",
    "\x04\x00\x00\x00" -- head ptr = 4
      .. "\x01\x00\x00\x00\x0C\x00\x00\x00" -- A: value=1, next=12
      .. "\x02\x00\x00\x00\x14\x00\x00\x00" -- B: value=2, next=20
      .. "\x03\x00\x00\x00\x04\x00\x00\x00" -- C: value=3, next=4
  )
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.CircularList(Node, "next", 0x1000), 0, reader, tracer)
  assert(ok)
  assert(v)
  assert(#v == 3)
  assert(v[1].value == 1)
  assert(v[2].value == 2)
  assert(v[3].value == 3)
end

-- Empty circular list (head pointer is null)
do
  local Node = d.Struct("Node", { d.Field(d.Int32, "value"), d.Field(d.RawAddr(), "next") })
  local reader = memory.mock_memory_reader("I4", "\x00\x00\x00\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.CircularList(Node, "next", 0x1000), 0, reader, tracer)
  assert(ok)
  assert(v)
  assert(#v == 0)
end

-- Unreadable head pointer
do
  local Node = d.Struct("Node", { d.Field(d.Int32, "value"), d.Field(d.RawAddr(), "next") })
  local reader = memory.mock_memory_reader("I4", "")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.CircularList(Node, "next", 0x1000), 0, reader, tracer)
  assert(not ok)
  assert(v == nil)
end

-- ---------------------------------------------------------------------------
-- Nested struct
-- ---------------------------------------------------------------------------

do
  local Inner = d.Struct("Inner", { d.Field(d.Int32, "a"), d.Field(d.Int32, "b") })
  local Outer = d.Struct("Outer", { d.Field(Inner, "inner"), d.Field(d.Int32, "c") })
  local reader = memory.mock_memory_reader(
    "I4",
    "\x0B\x00\x00\x00" -- a = 11
      .. "\x16\x00\x00\x00" -- b = 22
      .. "\x21\x00\x00\x00" -- c = 33
  )
  local tracer = ok_tracer.new()
  local v, ok = read.read(Outer, 0, reader, tracer)
  assert(ok)
  assert(v)
  assert(v.inner.a == 11)
  assert(v.inner.b == 22)
  assert(v.c == 33)
end

-- ---------------------------------------------------------------------------
-- PrimitiveArray
-- ---------------------------------------------------------------------------

-- 1D: three int16s
do
  local reader = memory.mock_memory_reader("I4", "\x01\x00\x02\x00\x03\x00")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.PrimitiveArray("i2", {3}), 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(#v == 3)
  assert(v[1] == 1)
  assert(v[2] == 2)
  assert(v[3] == 3)
end

-- 2D: PrimArray("I1", {2, 3}) => std::array<std::array<uint8_t,3>,2>
do
  local reader = memory.mock_memory_reader("I4", "\x01\x02\x03\x04\x05\x06")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.PrimitiveArray("I1", {2, 3}), 0, reader, tracer)
  assert(ok)
  assert(v ~= nil)
  assert(#v == 2)
  assert(#v[1] == 3)
  assert(#v[2] == 3)
  assert(v[1][1] == 1)
  assert(v[1][2] == 2)
  assert(v[1][3] == 3)
  assert(v[2][1] == 4)
  assert(v[2][2] == 5)
  assert(v[2][3] == 6)
end

-- Fails cleanly on short read
do
  local reader = memory.mock_memory_reader("I4", "\x01\x02")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.PrimitiveArray("I1", {3, 2}), 0, reader, tracer)
  assert(not ok)
end

-- ---------------------------------------------------------------------------
-- ZString
-- ---------------------------------------------------------------------------

-- Null terminator present before max_len
do
  local reader = memory.mock_memory_reader("I1", "\2\0hello\0world")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.ZString(11), 0, reader, tracer)
  assert(ok)
  assert(v == "hello")
end

-- No null terminator within max_len: returns all max_len bytes as-is
do
  local reader = memory.mock_memory_reader("I1", "\1abcdefg\0")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.ZString(4), 0, reader, tracer)
  assert(not ok)
  assert(v == "abcd")
end

-- Null terminator at position 0: empty string
do
  local reader = memory.mock_memory_reader("I1", "\1\0abc")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.ZString(4), 0, reader, tracer)
  assert(ok)
  assert(v == "")
end

-- Non-zero start offset
do
  local reader = memory.mock_memory_reader("I1", "\xFF\xFF\3hi\0")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.ZString(3), 2, reader, tracer)
  assert(ok)
  assert(v == "hi")
end

-- Unreadable address
do
  local reader = memory.mock_memory_reader("I4", "")
  local tracer = ok_tracer.new()
  local v, ok = read.read(d.ZString(4), 0, reader, tracer)
  assert(not ok)
  assert(v == nil)
end

-- ZString inside a Struct: cursor lands after the fixed-size slot
do
  local S = d.Struct("S", { d.Field(d.ZString(4), "name"), d.Field(d.Int32, "value") })
  local reader = memory.mock_memory_reader("I4", "\x08\0\0\0\x2A\x00\x00\x00hi\0\0")
  local tracer = ok_tracer.new()
  local v, ok = read.read(S, 0, reader, tracer)
  assert(ok)
  assert(v.name == "hi")
  assert(v.value == 42)
end