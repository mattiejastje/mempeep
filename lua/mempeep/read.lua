--- Reading values from remote memory using descriptors.

local errors = require("mempeep.errors")

local M = {}

-- Maximum representable value for each supported address format string.
-- For "I8" Lua integers are signed 64-bit, so the ceiling is math.maxinteger
-- (0x7FFFFFFFFFFFFFFF) rather than 0xFFFFFFFFFFFFFFFF. Overflow is detected
-- against this ceiling.
local addr_max = {
  ["I1"] = 0xFF,
  ["I2"] = 0xFFFF,
  ["I4"] = 0xFFFFFFFF,
  ["I8"] = math.maxinteger,
}

--- Advance address by n bytes, reporting ADDRESS_OVERFLOW if the result would
-- exceed the maximum value representable by the reader's address format.
-- @param address integer current address
-- @param n integer number of bytes to advance
-- @param reader reader table { fmt, read }
-- @param tracer tracer table
-- @return integer|nil new cursor: address, or nil on overflow
local function advance(address, n, reader, tracer)
  local max = addr_max[reader.fmt]
  assert(max, "unsupported address format: " .. tostring(reader.fmt))
  if n > max - address then
    tracer:error(errors.ADDRESS_OVERFLOW)
    return nil
  end
  return address + n
end

--------------------------------------------------------------------------------
-- read_value_impl dispatch table
-- Each entry is a function(desc, address, reader, tracer) -> cursor, value
--------------------------------------------------------------------------------

local read_value_impl = {}

--- Primitive: read desc.fmt:packsize() bytes directly and unpack them.
read_value_impl.Primitive = function(desc, address, reader, tracer)
  local size = desc.fmt:packsize()
  local bytes = reader:read(address, size)
  if not bytes then
    tracer:error(errors.READ_FAILED)
    return nil, nil
  end
  local value = desc.fmt:unpack(bytes)
  tracer:value(value)
  return advance(address, size, reader, tracer), value
end

--- RawAddr: read one address-sized integer without following it.
-- Reads via Primitive using the reader's own address format.
read_value_impl.RawAddr = function(desc, address, reader, tracer)
  return read_value({ tag = "Primitive", fmt = reader.fmt }, address, reader, tracer)
end

--- LenString: read a length-prefixed string.
read_value_impl.LenString = function(desc, address, reader, tracer)
  local cursor, len = read_value({ tag = "Primitive", fmt = desc.len_fmt }, address, reader, tracer)
  if not cursor then
    return nil, nil
  end

  if len > desc.max_len then
    tracer:error(errors.STRING_TOO_LONG)
    return nil, nil
  end

  if len == 0 then
    tracer:value("")
    return cursor, ""
  end

  local str_bytes = reader:read(cursor, len)
  if not str_bytes then
    tracer:error(errors.READ_FAILED)
    return nil, nil
  end
  tracer:value(str_bytes)
  return advance(cursor, len, reader, tracer), str_bytes
end

--- Ref: read an address and follow it, reading the pointee using desc.desc.
-- Reports ADDRESS_NULL if the address is zero.
read_value_impl.Ref = function(desc, address, reader, tracer)
  local cursor, ptr = read_value({ tag = "Primitive", fmt = reader.fmt }, address, reader, tracer)
  if not cursor then
    return nil, nil
  end

  if ptr == 0 then
    tracer:error(errors.ADDRESS_NULL)
    -- cursor is still valid; we just could not follow the pointer
    return cursor, nil
  end

  -- We always try to read as much as possible. Inner failure does not
  -- invalidate our cursor, which sits after the pointer word, not the
  -- pointee.
  local _, value = read_value(desc.desc, ptr, reader, tracer)
  return cursor, value
end

--- NullableRef: like Ref but a null address is allowed and yields nil.
read_value_impl.NullableRef = function(desc, address, reader, tracer)
  local cursor, ptr = read_value({ tag = "Primitive", fmt = reader.fmt }, address, reader, tracer)
  if not cursor then
    return nil, nil
  end

  if ptr == 0 then
    -- null is not an error for NullableRef
    return cursor, nil
  end

  local _, value = read_value(desc.desc, ptr, reader, tracer)
  return cursor, value
end

--- Array: read desc.n consecutive elements using desc.desc.
read_value_impl.Array = function(desc, address, reader, tracer)
  local arr = {}
  local cursor = address
  for i = 1, desc.n do
    if not cursor then
      break
    end
    local value
    tracer:begin_element(cursor, i - 1) -- 0-based index
    cursor, value = read_value(desc.desc, cursor, reader, tracer)
    tracer:end_element()
    arr[i] = value
  end
  return cursor, arr
end

--- Vector: read a begin/end address pair, then each element using desc.desc.
read_value_impl.Vector = function(desc, address, reader, tracer)
  local addr_desc = { tag = "Primitive", fmt = reader.fmt }

  local cursor, begin_ptr = read_value(addr_desc, address, reader, tracer)
  if not cursor then
    return nil, nil
  end

  local end_ptr
  cursor, end_ptr = read_value(addr_desc, cursor, reader, tracer)
  if not cursor then
    return nil, nil
  end

  if begin_ptr == 0 then
    tracer:error(errors.ADDRESS_NULL)
    return cursor, nil
  end

  if begin_ptr > end_ptr then
    tracer:error(errors.VECTOR_INVALID_RANGE)
    return cursor, nil
  end

  local vec = {}
  local vec_cursor = begin_ptr
  local index = 0
  while vec_cursor and vec_cursor < end_ptr do
    local value
    tracer:begin_element(vec_cursor, index)
    vec_cursor, value = read_value(desc.desc, vec_cursor, reader, tracer)
    tracer:end_element()
    vec[#vec + 1] = value
    index = index + 1
    if index > desc.max_len then
      tracer:error(errors.VECTOR_TOO_LONG)
      return cursor, vec
    end
  end
  if vec_cursor and vec_cursor ~= end_ptr then
    tracer:error(errors.VECTOR_MISALIGNED)
  end
  return cursor, vec
end

--- CircularList: read a circular intrusive linked list.
read_value_impl.CircularList = function(desc, address, reader, tracer)
  local cursor, head_ptr = read_value({ tag = "Primitive", fmt = reader.fmt }, address, reader, tracer)
  if not cursor then
    return nil, nil
  end

  if head_ptr == 0 then
    return cursor, {}
  end

  local list = {}
  local list_cursor = head_ptr
  local index = 0
  repeat
    local node
    tracer:begin_element(list_cursor, index)
    list_cursor, node = read_value(desc.desc, list_cursor, reader, tracer)
    tracer:end_element()
    list[#list + 1] = node -- save partial data even if read fails
    if not list_cursor then
      return cursor, list
    end
    local next_addr = node[desc.next_key]
    if not next_addr or next_addr == 0 then
      tracer:error(errors.ADDRESS_NULL)
      return cursor, list
    end
    list_cursor = next_addr
    index = index + 1
    if index > desc.max_len then
      tracer:error(errors.CIRCULAR_LIST_TOO_LONG)
      return cursor, list
    end
  until list_cursor == head_ptr

  return cursor, list
end

--- Struct: read fields in order, dispatching each through `read_fields_item`.
-- Field values are returned by `read_fields_item` and collected into `out` here.
read_value_impl.Struct = function(desc, address, reader, tracer)
  local out = {}
  local cursor = address
  for _, item in ipairs(desc.fields) do
    if not cursor then
      break
    end
    local value
    cursor, value = read_fields_item(item, address, cursor, reader, tracer)
    if item.tag == "Field" then
      out[item.key] = value
    end
  end
  return cursor, out
end

--------------------------------------------------------------------------------
-- read_value
--------------------------------------------------------------------------------

--- Read a value described by desc from address.
-- @param desc descriptor table
-- @param address integer remote address
-- @param reader reader table
-- @param tracer tracer table
-- @return cursor after the read and the decoded value
read_value = function(desc, address, reader, tracer)
  tracer:begin_desc(address, desc)
  local impl = read_value_impl[desc.tag]
  assert(impl, "unknown descriptor tag: " .. tostring(desc.tag))
  local cursor, value = impl(desc, address, reader, tracer)
  tracer:end_desc()
  return cursor, value
end

--------------------------------------------------------------------------------
-- read_fields_item dispatch table
-- Each entry is a function(item, base, address, reader, tracer) -> cursor, value
-- Pad and Seek return nil as value. Field returns the decoded value.
--------------------------------------------------------------------------------

local read_fields_item_impl = {}

--- Pad: advance address by item.n bytes without reading.
read_fields_item_impl.Pad = function(item, base, address, reader, tracer)
  return advance(address, item.n, reader, tracer), nil
end

--- Seek: seek to an absolute offset from the struct base address.
read_fields_item_impl.Seek = function(item, base, address, reader, tracer)
  return advance(base, item.n, reader, tracer), nil
end

--- Field: read and return the decoded value; the caller assigns it.
read_fields_item_impl.Field = function(item, base, address, reader, tracer)
  return read_value(item.desc, address, reader, tracer)
end

--------------------------------------------------------------------------------
-- read_fields_item
--------------------------------------------------------------------------------

--- Dispatch a single fields item, advancing the cursor.
-- Returns the new cursor and, for Field items, the decoded value (nil otherwise).
-- The caller (read_value_impl.Struct) is responsible for assigning the value.
-- @param item fields item table (Field, Pad, or Seek)
-- @param base integer base address of the enclosing struct
-- @param address integer current address
-- @param reader reader table { fmt, read }
-- @param tracer tracer table
-- @return integer|nil, any cursor after the item and the decoded value (or nil)
read_fields_item = function(item, base, address, reader, tracer)
  tracer:begin_fields_item(address, item)
  local impl = read_fields_item_impl[item.tag]
  assert(impl, "unknown fields item tag: " .. tostring(item.tag))
  local next_cursor, value = impl(item, base, address, reader, tracer)
  tracer:end_fields_item()
  return next_cursor, value
end

--------------------------------------------------------------------------------
-- Public entry point
--------------------------------------------------------------------------------

--- Read data from remote memory using a descriptor, returning a fresh value.
-- Attempts to read as much as possible even after partial failures.
-- Returns the decoded value and the result of tracer:success().
--
-- The tracer must implement:
--   error(self, e)                     called on each error
--   success(self) -> bool              called once at the end
--   value(self, v)                     called after each primitive read
--   begin_fields_item(self, address, item)    called before each fields item
--   end_fields_item(self)                     called after each fields item
--   begin_element(self, address, index) called before each collection element
--   end_element(self)                  called after each collection element
--   begin_desc(self, address, desc)    called before each descriptor read
--   end_desc(self)                     called after each descriptor read
--
-- @param desc table descriptor controlling how the value is read
-- @param address integer remote address to read from
-- @param reader table { fmt: string, read(self, address, size) -> string|nil }
-- @param tracer table (see above)
-- @return any, boolean decoded value and tracer:success()
function M.read(desc, address, reader, tracer)
  local _, value = read_value(desc, address, reader, tracer)
  return value, tracer:success()
end

return M
