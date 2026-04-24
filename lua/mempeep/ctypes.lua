--- Dump C style version of descriptor or struct.

local M = {}

local primitive_compatible_size_impl = {}

--- Check if descriptor can be represented by a C++ Primitive.
-- If so, returns its size, otherwise returns nil.
-- Basically checks if it has a flat layout.
local primitive_compatible_size = function(desc)
  local impl = primitive_compatible_size_impl[desc.tag]
  if not impl then return nil end
  return impl(desc)
end

primitive_compatible_size_impl.Primitive = function(desc)
  return string.packsize(desc.fmt)
end

primitive_compatible_size_impl.Bounded = function(desc)
  return primitive_compatible_size(desc.desc)
end

primitive_compatible_size_impl.Array = function(desc)
  local elem_size = primitive_compatible_size(desc.desc)
  if not elem_size then return nil end
  return desc.n * elem_size
end

primitive_compatible_size_impl.Struct = function(desc)
  local offset = 0
  for _, item in ipairs(desc.fields) do
    if item.tag == "Skip" then
      offset = offset + item.n
    elseif item.tag == "Seek" then
      return nil
    elseif item.tag == "Field" then
      local field_size = primitive_compatible_size(item.desc)
      if not field_size then return nil end
      offset = offset + field_size
    end
  end
  return offset
end

local remote_ctype_impl = {}

function M.remote_ctype(desc, addr_size)
  local impl = remote_ctype_impl[desc.tag]
  assert(impl, "unknown descriptor tag: " .. tostring(desc.tag))
  return impl(desc, addr_size)
end

local native_ctype_impl = {}

function M.native_ctype(desc)
  local impl = native_ctype_impl[desc.tag]
  assert(impl, "unknown descriptor tag: " .. tostring(desc.tag))
  return impl(desc)
end

local mempeep_ctype_impl = {}

function M.mempeep_ctype(desc, namespace)
  local impl = mempeep_ctype_impl[desc.tag]
  assert(impl, "unknown descriptor tag: " .. tostring(desc.tag))
  return impl(desc, namespace)
end

local fmt_to_ctype_impl = {}
fmt_to_ctype_impl.i1 = "int8_t"
fmt_to_ctype_impl.i2 = "int16_t"
fmt_to_ctype_impl.i4 = "int32_t"
fmt_to_ctype_impl.i8 = "int64_t"
fmt_to_ctype_impl.I1 = "uint8_t"
fmt_to_ctype_impl.I2 = "uint16_t"
fmt_to_ctype_impl.I4 = "uint32_t"
fmt_to_ctype_impl.I8 = "uint64_t"
fmt_to_ctype_impl.f = "float"
fmt_to_ctype_impl.d = "double"

local fmt_to_ctype = function(fmt)
  local typ = fmt_to_ctype_impl[fmt]
  if typ then return typ end
  local n = fmt:match("^c(%d+)$")
  if n then return "std::array<char, " .. n .. ">" end
  error("unknown format '" .. tostring(fmt) .. "'")
  return typ
end

local fmt_to_prim_impl = {}
fmt_to_prim_impl.i1 = "Int8"
fmt_to_prim_impl.i2 = "Int16"
fmt_to_prim_impl.i4 = "Int32"
fmt_to_prim_impl.i8 = "Int64"
fmt_to_prim_impl.I1 = "UInt8"
fmt_to_prim_impl.I2 = "UInt16"
fmt_to_prim_impl.I4 = "UInt32"
fmt_to_prim_impl.I8 = "UInt64"
fmt_to_prim_impl.f = "Float"
fmt_to_prim_impl.d = "Double"

remote_ctype_impl.Primitive = function(desc, addr_size)
  assert(desc.fmt)
  return string.packsize(desc.fmt), fmt_to_ctype(desc.fmt)
end

native_ctype_impl.Primitive = function(desc)
  assert(desc.fmt)
  return fmt_to_ctype(desc.fmt)
end

mempeep_ctype_impl.Primitive = function(desc, namespace)
  assert(desc.fmt)
  local prim = fmt_to_prim_impl[desc.fmt]
  if prim then return namespace .. prim end
  return namespace .. "Primitive<" .. fmt_to_ctype(desc.fmt) .. ">"
end

remote_ctype_impl.Bounded = function(desc, addr_size)
  return M.remote_ctype(desc.desc, addr_size)
end

native_ctype_impl.Bounded = function(desc)
  return M.native_ctype(desc.desc)
end

mempeep_ctype_impl.Bounded = function(desc, namespace)
  local inner = M.mempeep_ctype(desc.desc, namespace)
  return string.format("%sBounded<%s, %d, %d>", namespace, inner, desc.min, desc.max)
end

remote_ctype_impl.ZString = function(desc, addr_size)
  return addr_size, "char*"
end

native_ctype_impl.ZString = function(desc)
  return "std::string"
end

mempeep_ctype_impl.ZString = function(desc, namespace)
  return namespace .. "ZString<0x" .. string.format("%x", desc.max_len) .. ">"
end

remote_ctype_impl.RawAddr = function(desc, addr_size)
  return addr_size, "void*"
end

native_ctype_impl.RawAddr = function(desc)
  return "uintptr_t"
end

mempeep_ctype_impl.RawAddr = function(desc, namespace)
  return namespace .. "RawAddr<uintptr_t>"
end

remote_ctype_impl.Ref = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return addr_size, ref_ctype .. "*"
end

native_ctype_impl.Ref = function(desc)
  return M.native_ctype(desc.desc)
end

mempeep_ctype_impl.Ref = function(desc, namespace)
  return namespace .. "Ref<" .. M.mempeep_ctype(desc.desc, namespace) .. ">"
end

remote_ctype_impl.NullableRef = remote_ctype_impl.Ref

native_ctype_impl.NullableRef = function(desc)
  return "std::optional<" .. M.native_ctype(desc.desc) .. ">"
end

mempeep_ctype_impl.NullableRef = function(desc, namespace)
  return namespace .. "NullableRef<" .. M.mempeep_ctype(desc.desc, namespace) .. ">"
end

remote_ctype_impl.Array = function(desc, addr_size)
  local ref_size, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return desc.n * ref_size, "std::array<" .. ref_ctype .. ", 0x" .. string.format("%x", desc.n) .. ">"
end

native_ctype_impl.Array = function(desc)
  return "std::array<" .. M.native_ctype(desc.desc) .. ", 0x" .. string.format("%x", desc.n) .. ">"
end

mempeep_ctype_impl.Array = function(desc, namespace)
  if primitive_compatible_size(desc) then
    return "Primitive<" .. M.native_ctype(desc) .. ">"
  else
    return namespace .. "Array<" .. M.mempeep_ctype(desc.desc, namespace) .. ", 0x" .. string.format("%x", desc.n) .. ">"
  end
end

remote_ctype_impl.Vector = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return 2 * addr_size, ref_ctype .. "*"
end

native_ctype_impl.Vector = function(desc)
  return "std::vector<" .. M.native_ctype(desc.desc) .. ">"
end

mempeep_ctype_impl.Vector = function(desc, namespace)
  return namespace .. "Vector<" .. M.mempeep_ctype(desc.desc, namespace) .. ", 0x" .. string.format("%x", desc.max_len) .. ">"
end

remote_ctype_impl.List = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return addr_size, ref_ctype .. "*"
end

native_ctype_impl.List = function(desc)
  return "std::vector<" .. M.native_ctype(desc.desc) .. ">"
end

mempeep_ctype_impl.List = function(desc, namespace)
  return namespace .. "List<" .. M.mempeep_ctype(desc.desc, namespace) .. ", &" .. desc.desc.name .. "::" .. desc.next_key .. ", 0x" .. string.format("%x", desc.max_len) .. ">"
end

remote_ctype_impl.Struct = function(desc, addr_size)
  local size = 0
  for _, item in ipairs(desc.fields) do
    if item.tag == "Skip" then
      size = size + item.n
    elseif item.tag == "Seek" then
      size = item.n
    elseif item.tag == "Field" then
      local field_size, _ = M.remote_ctype(item.desc, addr_size)
      size = size + field_size
    end
  end
  return size, desc.name
end

native_ctype_impl.Struct = function(desc)
  return desc.name
end

mempeep_ctype_impl.Struct = function(desc, namespace)
  if primitive_compatible_size(desc) then
    return namespace .. "Primitive<" .. desc.name .. ">"
  else
    return "T" .. desc.name
  end
end

function M.remote_struct_cdecl(desc, addr_size, out)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  out:write(string.format("struct %s {\n", desc.name))
  local offset = 0
  local pad_index = 0
  for i, item in ipairs(desc.fields) do
    if item.tag == "Skip" then
      out:write(string.format("  int8_t _pad%d[0x%x];\n", pad_index, item.n))
      pad_index = pad_index + 1
      offset = offset + item.n
    elseif item.tag == "Seek" then
      out:write(string.format("  int8_t _pad%d[0x%x];\n", pad_index, item.n - offset))
      pad_index = pad_index + 1
      offset = item.n
    elseif item.tag == "Field" then
      local field_size, field_ctype = M.remote_ctype(item.desc, addr_size)
      if item.desc.tag == "Vector" then
        out:write(string.format("  %s %s_begin;  // offset 0x%x\n", field_ctype, item.key, offset))
        out:write(string.format("  %s %s_end;    // offset 0x%x\n", field_ctype, item.key, offset + addr_size))
      else
        out:write(string.format("  %s %s;  // offset 0x%x\n", field_ctype, item.key, offset))
      end
      offset = offset + field_size
    end
  end
  out:write("};\n\n")
end

local native_struct_cdecl_1 = function(desc, out)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  out:write(string.format("struct %s {\n", desc.name))
  if primitive_compatible_size(desc) then
    local offset = 0
    local pad_index = 0
    for _, item in ipairs(desc.fields) do
      if item.tag == "Skip" then
        out:write(string.format("  uint8_t _pad%d[0x%x];\n", pad_index, item.n))
        pad_index = pad_index + 1
        offset = offset + item.n
      elseif item.tag == "Seek" then
        local gap = item.n - offset
        if gap > 0 then
          out:write(string.format("  uint8_t _pad%d[0x%x];\n", pad_index, gap))
          pad_index = pad_index + 1
        end
        offset = item.n
      elseif item.tag == "Field" then
        local field_size = primitive_compatible_size(item.desc)
        assert(field_size ~= nil)
        local field_native_ctype = M.native_ctype(item.desc)
        out:write(string.format("  %s %s;\n", field_native_ctype, item.key))
        offset = offset + field_size
      end
    end
  else
    for _, item in ipairs(desc.fields) do
      if item.tag == "Field" then
        local field_ctype = M.native_ctype(item.desc)
        out:write(string.format("  %s %s;\n", field_ctype, item.key))
      end
    end
  end
  out:write("};\n\n")
end

local native_struct_cdecl_2 = function(desc, namespace, out)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  if primitive_compatible_size(desc) then return end
  out:write("using T" .. desc.name .. " = " .. namespace .. "Struct<\n")
  out:write("  " .. desc.name .. ",\n")
  out:write("  " .. namespace .. "Fields<\n")
  for i, item in ipairs(desc.fields) do
    local is_last = (i == #desc.fields)
    local comma = is_last and ">>;\n\n" or ",\n"
    if item.tag == "Skip" then
      out:write(string.format("    %sSkip<0x%x>%s", namespace, item.n, comma))
    elseif item.tag == "Seek" then
      out:write(string.format("    %sSeek<0x%x>%s", namespace, item.n, comma))
    elseif item.tag == "Field" then
      local mtype = M.mempeep_ctype(item.desc, namespace)
      out:write(string.format("    %sField<%s, &%s::%s>%s", namespace, mtype, desc.name, item.key, comma))
    end
  end
end

function M.native_struct_cdecl(desc, namespace, out)
  native_struct_cdecl_1(desc, out)
  native_struct_cdecl_2(desc, namespace, out)
end

--- Collect all Struct descriptors reachable from `desc` in topological order
-- (dependencies before dependents). Each struct is visited at most once.
-- @param desc descriptor to walk
-- @param visited table used to track already-visited struct names
-- @param order table (array) accumulating structs in declaration order
local function collect_structs(desc, visited, order)
  if desc.tag == "Primitive" or desc.tag == "RawAddr" or desc.tag == "ZString" then
    return
  elseif desc.tag == "Ref" or desc.tag == "NullableRef" or desc.tag == "Array" or desc.tag == "Vector" or desc.tag == "List" or desc.tag == "Bounded" then
    collect_structs(desc.desc, visited, order)
  elseif desc.tag == "Struct" then
    if visited[desc.name] then
      return
    end
    -- Mark before recursing to handle any forward references gracefully.
    visited[desc.name] = true
    -- Recurse into each Field's descriptor first so dependencies come before
    -- the struct that uses them.
    for _, item in ipairs(desc.fields) do
      if item.tag == "Field" then
        collect_structs(item.desc, visited, order)
      end
    end
    order[#order + 1] = desc
  else
    error("collect_structs: unknown descriptor tag: " .. tostring(desc.tag))
  end
end

--- Apply `fn` to all Struct descriptors reachable from `descs` in topological
-- order (dependencies before dependents).
-- @param descs descriptors to walk
-- @param fn function(desc) called once per unique reachable Struct
local function each_struct(descs, fn)
  local visited = {}
  local order = {}
  for _, desc in ipairs(descs) do
    collect_structs(desc, visited, order)
  end
  for _, s in ipairs(order) do
    fn(s)
  end
end

--- Write all Struct declarations reachable from `descs` in correct declaration
-- order (dependencies before dependents), using the remote C layout.
-- @param descs descriptor to collect structs from
-- @param addr_size integer size in bytes of the remote address type
-- @param out output stream
function M.remote_struct_cdecls(descs, addr_size, out)
  each_struct(descs, function(s)
    M.remote_struct_cdecl(s, addr_size, out)
  end)
end

--- Write all Struct declarations reachable from `descs` in correct declaration
-- order (dependencies before dependents), using the native C++ layout.
-- @param descs descriptor to collect structs from
-- @param out output stream
function M.native_struct_cdecls(descs, namespace, out)
  each_struct(descs, function(s)
    M.native_struct_cdecl(s, namespace, out)
  end)
end

return M
