--- Log tracer: prints every user-visible primitive read as it is encountered.

local M = {}

--- format an integer address as a zero-padded lowercase hex string
local function fmt_addr(addr)
  if addr >= 0 and addr <= 0xFFFFFFFF then
    return string.format("%08x", addr)
  end
  return string.format("%016x", addr)
end

--- build the display path from the path stack
local function build_path(stack)
  local parts = {}
  for _, label in ipairs(stack) do
    parts[#parts + 1] = label
  end
  return table.concat(parts, ".")
end

--- Create a new log tracer instance.
-- @param out file handle to write output to (default: io.stdout)
-- @return tracer table implementing the mempeep tracer interface
function M.new(out)
  out = out or io.stdout

  local t = {
    ok = true,
    _path_stack = {},
    _addr_stack = {},
  }

  function t:error(e)
    self.ok = false
    local addr = self._addr_stack[#self._addr_stack] or 0
    local path = build_path(self._path_stack)
    out:write(string.format("[%s] %s = <%s>\n", fmt_addr(addr), path, e))
  end

  function t:success()
    return self.ok
  end

  function t:value(v)
    local addr = self._addr_stack[#self._addr_stack] or 0
    local path = build_path(self._path_stack)
    local repr
    if type(v) == "number" then
      if math.type(v) == "integer" then
        repr = string.format("%d (0x%x)", v, v)
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
    out:write(string.format("[%s] %s = %s\n", fmt_addr(addr), path, repr))
  end

  function t:begin_item(address, item)
    if item.tag == "Field" then
      self._path_stack[#self._path_stack + 1] = item.key
    else
      self._path_stack[#self._path_stack + 1] = false -- sentinel
    end
  end

  function t:end_item()
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

return M
