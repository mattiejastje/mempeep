--- Log tracer: prints every user-visible primitive read as it is encountered.

local M = {}

--- format an integer address as a zero-padded lowercase hex string
local function fmt_addr(addr)
  if addr >= 0 and addr <= 0xFFFFFFFF then
    return string.format("[%08x]", addr)
  end
  return string.format("[%016x]", addr)
end

M.log_level = {
  ERRORS = 0,
  VALUES = 1,
}

M.log_entry_kind = {
  ERR = 0,
  VAL = 1,
}

--- Create a new log tracer instance.
-- @param out file handle to write output to (default: io.stdout)
-- @return tracer table implementing the mempeep tracer interface
function M.new(on_entry, level)
  local t = {
    ok = true,
    _path_stack = {},
    _addr_stack = {},
  }

  function t:error(e)
    self.ok = false
    on_entry({
      address = self._addr_stack[#self._addr_stack] or 0,
      path = table.concat(self._path_stack),
      text = e,
      kind = M.log_entry_kind.ERR,
    })
  end

  function t:success()
    return self.ok
  end

  function t:value(v)
    if level >= M.log_level.VALUES then
      local repr
      if type(v) == "number" then
        if math.type(v) == "integer" then
          if v >= 0 then
            repr = string.format("0x%x", v)
          else
            repr = string.format("-0x%x", -v)
          end
        else
          repr = tostring(v)
        end
      elseif type(v) == "string" then
        repr = '"'
          .. v:gsub("[%c\x80-\xff]", function(c)
            return string.format("\\x%02x", c:byte())
          end)
          .. '"'
      else
        repr = tostring(v)
      end
      on_entry({
        address = self._addr_stack[#self._addr_stack] or 0,
        path = table.concat(self._path_stack),
        text = repr,
        kind = M.log_entry_kind.VAL,
      })
    end
  end

  function t:begin_fields_item(address, item)
    if item.tag == "Field" then
      self._path_stack[#self._path_stack + 1] = "." .. item.key
    else
      self._path_stack[#self._path_stack + 1] = ""
    end
  end

  function t:end_fields_item()
    self._path_stack[#self._path_stack] = nil
  end

  function t:begin_element(address, index)
    self._path_stack[#self._path_stack + 1] = "[" .. index .. "]"
  end

  function t:end_element()
    self._path_stack[#self._path_stack] = nil
  end

  function t:begin_desc(address, desc)
    self._addr_stack[#self._addr_stack + 1] = address
  end

  function t:end_desc()
    self._addr_stack[#self._addr_stack] = nil
  end

  return t
end

function M.make_stream_log_tracer(out, level)
  out = out or io.stdout

  local on_entry = function(entry)
    addr_str = fmt_addr(entry.address)
    if entry.kind == M.log_entry_kind.ERR then
      out:write(string.format("%s %s <%s>\n", addr_str, entry.path, entry.text))
    else
      out:write(string.format("%s %s = %s\n", addr_str, entry.path, entry.text))
    end
  end

  return M.new(on_entry, level or M.log_level.ERRORS)
end

return M
