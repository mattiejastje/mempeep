local d = require("mempeep.descriptors")
local log_tracer = require("mempeep.tracers.log_tracer")
local memory = require("mempeep.test.memory")
local read = require("mempeep.read")

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
  local Inner = d.Struct("Inner", { d.Field(d.Int32, "a"), d.Field(d.Int32, "b") })
  local Outer = d.Struct("Outer", { d.Field(Inner, "inner"), d.Field(d.Int32, "c") })
  local reader = memory.mock_memory_reader(
    "I4",
    "\x0B\x00\x00\x00" -- a = 11
      .. "\x16\x00\x00\x00" -- b = 22
      .. "\x21\x00\x00\x00" -- c = 33
  )
  local out = mock_out([[
[00000000] .inner.a = 0xb
[00000004] .inner.b = 0x16
[00000008] .c = 0x21
]])
  local tracer = log_tracer.new(log_tracer.on_entry_write(out), log_tracer.log_level.VALUES)
  local v, ok = read.read(Outer, 0, reader, tracer)
  assert(ok)
  assert(v)
  assert(v.inner.a == 11)
  assert(v.inner.b == 22)
  assert(v.c == 33)
end
