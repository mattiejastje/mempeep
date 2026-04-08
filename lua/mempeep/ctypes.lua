--- Dump C style version of descriptor or struct.

local M = {}

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

function M.mempeep_ctype(desc)
  local impl = mempeep_ctype_impl[desc.tag]
  assert(impl, "unknown descriptor tag: " .. tostring(desc.tag))
  return impl(desc)
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

remote_ctype_impl.Primitive = function(desc, addr_size)
  assert(desc.fmt)
  return string.packsize(desc.fmt), fmt_to_ctype(desc.fmt)
end

native_ctype_impl.Primitive = function(desc)
  assert(desc.fmt)
  return fmt_to_ctype(desc.fmt)
end

mempeep_ctype_impl.Primitive = function(desc)
  assert(desc.fmt)
  return "mempeep::Primitive<" .. fmt_to_ctype(desc.fmt) .. ">"
end

remote_ctype_impl.RawAddr = function(desc, addr_size)
  return addr_size, "void*"
end

native_ctype_impl.RawAddr = function(desc)
  return "uintptr_t"
end

mempeep_ctype_impl.RawAddr = function(desc)
  return "mempeep::RawAddr<uintptr_t>"
end

remote_ctype_impl.Ref = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return addr_size, ref_ctype .. "*"
end

native_ctype_impl.Ref = function(desc)
  return M.native_ctype(desc.desc)
end

mempeep_ctype_impl.Ref = function(desc)
  return "mempeep::Ref<" .. M.mempeep_ctype(desc.desc) .. ">"
end

remote_ctype_impl.NullableRef = remote_ctype_impl.Ref

native_ctype_impl.NullableRef = function(desc)
  return "std::optional<" .. M.native_ctype(desc.desc) .. ">"
end

mempeep_ctype_impl.NullableRef = function(desc)
  return "mempeep::NullableRef<" .. M.mempeep_ctype(desc.desc) .. ">"
end

remote_ctype_impl.Array = function(desc, addr_size)
  local ref_size, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return desc.n * ref_size, "std::array<" .. ref_ctype .. ", " .. desc.n .. ">"
end

native_ctype_impl.Array = function(desc)
  return "std::array<" .. M.native_ctype(desc.desc) .. ", " .. desc.n .. ">"
end

mempeep_ctype_impl.Array = function(desc)
  return "mempeep::Array<" .. M.mempeep_ctype(desc.desc) .. ", " .. desc.n .. ">"
end

remote_ctype_impl.Vector = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return 2 * addr_size, ref_ctype .. "*"
end

native_ctype_impl.Vector = function(desc)
  return "std::vector<" .. M.native_ctype(desc.desc) .. ">"
end

mempeep_ctype_impl.Vector = function(desc)
  return "mempeep::Vector<" .. M.mempeep_ctype(desc.desc) .. ", 0x" .. string.format("%x", desc.max_len) .. ">"
end

remote_ctype_impl.CircularList = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return addr_size, ref_ctype .. "*"
end

native_ctype_impl.CircularList = function(desc)
  return "std::vector<" .. M.native_ctype(desc.desc) .. ">"
end

mempeep_ctype_impl.CircularList = function(desc)
  return "mempeep::CircularList<" .. M.mempeep_ctype(desc.desc) .. ", &" .. desc.desc.name .. "::" .. desc.next_key .. ", 0x" .. string.format("%x", desc.max_len) .. ">"
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

mempeep_ctype_impl.Struct = function(desc)
  return "T" .. desc.name
end

function M.remote_struct_cdecl(desc, addr_size)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  print(string.format("struct %s {", desc.name))
  local offset = 0
  for i, item in ipairs(desc.fields) do
    if item.tag == "Skip" then
      print(string.format("  int8_t _unknown%d[0x%x];", i, item.n))
      offset = offset + item.n
    elseif item.tag == "Seek" then
      print(string.format("  int8_t _unknown%d[0x%x];", i, item.n - offset))
      offset = item.n
    elseif item.tag == "Field" then
      local field_size, field_ctype = M.remote_ctype(item.desc, addr_size)
      if item.desc.tag == "Vector" then
        print(string.format("  %s %s_begin;  // offset 0x%x", field_ctype, item.key, offset))
        print(string.format("  %s %s_end;    // offset 0x%x", field_ctype, item.key, offset + addr_size))
      else
        print(string.format("  %s %s;  // offset 0x%x", field_ctype, item.key, offset))
      end
      offset = offset + field_size
    end
  end
  print("};")
end

function M.native_struct_cdecl(desc)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  print(string.format("struct %s {", desc.name))
  local offset = 0
  for _, item in ipairs(desc.fields) do
    if item.tag == "Field" then
      local field_ctype = M.native_ctype(item.desc)
      print(string.format("  %s %s;", field_ctype, item.key))
    end
  end
  print("};")
end

function M.mempeep_struct_cdecl(desc, out)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  out:write("using T" .. desc.name .. " = mempeep::Struct<\n")
  out:write("  " .. desc.name .. ",\n")
  out:write("  mempeep::Fields<\n")
  for i, item in ipairs(desc.fields) do
    local is_last = (i == #desc.fields)
    local comma = is_last and ">>;\n" or ",\n"
    if item.tag == "Skip" then
      out:write("    mempeep::Skip<" .. item.n .. ">" .. comma)
    elseif item.tag == "Seek" then
      out:write("    mempeep::Seek<" .. item.n .. ">" .. comma)
    elseif item.tag == "Field" then
      local mtype = M.mempeep_ctype(item.desc)
      out:write("    mempeep::Field<" .. mtype .. ", &" .. desc.name .. "::" .. item.key .. ">" .. comma)
    end
  end
end

--- Collect all Struct descriptors reachable from `desc` in topological order
-- (dependencies before dependents). Each struct is visited at most once.
-- @param desc descriptor to walk
-- @param visited table used to track already-visited struct names
-- @param order table (array) accumulating structs in declaration order
local function collect_structs(desc, visited, order)
  if desc.tag == "Primitive" or desc.tag == "RawAddr" then
    return
  elseif desc.tag == "Ref" or desc.tag == "NullableRef" or desc.tag == "Array" or desc.tag == "Vector" or desc.tag == "CircularList" then
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

--- Apply `fn` to all Struct descriptors reachable from `desc` in topological
-- order (dependencies before dependents).
-- @param desc descriptor to walk
-- @param fn function(desc) called once per unique reachable Struct
local function each_struct(desc, fn)
  local visited = {}
  local order = {}
  collect_structs(desc, visited, order)
  for _, s in ipairs(order) do
    fn(s)
  end
end

--- Print all Struct declarations reachable from `desc` in correct declaration
-- order (dependencies before dependents), using the remote C layout.
-- @param desc descriptor to collect structs from
-- @param addr_size integer size in bytes of the remote address type
function M.remote_struct_cdecls(desc, addr_size, out)
  each_struct(desc, function(s)
    M.remote_struct_cdecl(s, addr_size, out)
    out:write("\n")
  end)
end

--- Print all Struct declarations reachable from `desc` in correct declaration
-- order (dependencies before dependents), using the native C++ layout.
-- @param desc descriptor to collect structs from
function M.native_struct_cdecls(desc, out)
  each_struct(desc, function(s)
    M.native_struct_cdecl(s, out)
    out:write("\n")
  end)
end

--- Print all Struct declarations reachable from `desc` in correct declaration
-- order (dependencies before dependents), using the mempeep C++ layout.
-- @param desc descriptor to collect structs from
function M.mempeep_struct_cdecls(desc, out)
  each_struct(desc, function(s)
    M.mempeep_struct_cdecl(s, out)
    out:write("\n")
  end)
end

return M
