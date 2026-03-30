d = require("mempeep.descriptors")
log_tracer = require("mempeep.tracers.log_tracer")
memory = require("mempeep.test.memory")
read = require("mempeep.read")

Int32 = d.Primitive("i4")

local mock_out = function(lines)
  local out = {}
  function out:write(s)
    assert(s:sub(-1) == "\n", "missing newline after '" .. s .. "'")
    assert(s:sub(1, -2) == lines[1], "expected '" .. lines[1] .. "' but got '" .. s:sub(1, -2) .. "'")
    table.remove(lines, 1)
  end
  return out
end

do
  local Inner = d.Struct(d.Field(Int32, "a"), d.Field(Int32, "b"))
  local Outer = d.Struct(d.Field(Inner, "inner"), d.Field(Int32, "c"))
  local reader = memory.mock_memory_reader(
    "I4",
    "\x0B\x00\x00\x00" -- a = 11
      .. "\x16\x00\x00\x00" -- b = 22
      .. "\x21\x00\x00\x00" -- c = 33
  )
  local out = mock_out({ "[00000000] .inner.a = 0xb", "[00000004] .inner.b = 0x16", "[00000008] .c = 0x21" })
  local tracer = log_tracer.make_stream_log_tracer(out, log_tracer.log_level.VALUES)
  local v, ok = read.read(Outer, 0, reader, tracer)
  assert(ok)
  assert(v)
  assert(v.inner.a == 11)
  assert(v.inner.b == 22)
  assert(v.c == 33)
end
