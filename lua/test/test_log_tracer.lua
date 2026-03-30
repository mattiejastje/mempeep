d = require("mempeep.descriptors")
log_tracer = require("mempeep.tracers.log_tracer")
memory = require("mempeep.test.memory")
read = require("mempeep.read")

Int32 = d.Primitive("i4")

do
  local Inner = d.Struct(d.Field(Int32, "a"), d.Field(Int32, "b"))
  local Outer = d.Struct(d.Field(Inner, "inner"), d.Field(Int32, "c"))
  local reader = memory.mock_memory_reader(
    "I4",
    "\x0B\x00\x00\x00" -- a = 11
      .. "\x16\x00\x00\x00" -- b = 22
      .. "\x21\x00\x00\x00" -- c = 33
  )
  local tracer = log_tracer.new()
  local v, ok = read.read(Outer, 0, reader, tracer)
  assert(ok)
  assert(v)
  assert(v.inner.a == 11)
  assert(v.inner.b == 22)
  assert(v.c == 33)
end
