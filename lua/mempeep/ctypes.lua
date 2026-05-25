--- Dump C style version of descriptor or struct.

local M = {}

local hex_str = function(n)
  if n >= 0 then
    return string.format("0x%x", n)
  else
    return string.format("-0x%x", -n)
  end
end

local primitive_compatible_size_impl = {}

--- Check if descriptor can be represented by a C++ Primitive.
-- If so, returns its size, otherwise returns nil.
-- Basically checks if it has a flat layout.
local primitive_compatible_size = function(desc, addr_size)
  local impl = primitive_compatible_size_impl[desc.tag]
  if not impl then
    return nil
  end
  return impl(desc, addr_size)
end

primitive_compatible_size_impl.Primitive = function(desc, addr_size)
  return string.packsize(desc.fmt)
end

primitive_compatible_size_impl.Bounded = function(desc, addr_size)
  return primitive_compatible_size(desc.desc, addr_size)
end

primitive_compatible_size_impl.Array = function(desc, addr_size)
  local elem_size = primitive_compatible_size(desc.desc, addr_size)
  if not elem_size then
    return nil
  end
  return desc.n * elem_size
end

primitive_compatible_size_impl.RawAddr = function(desc, addr_size)
  return addr_size
end

primitive_compatible_size_impl.Struct = function(desc, addr_size)
  local offset = 0
  for _, item in ipairs(desc.fields) do
    if item.tag == "Skip" then
      if item.n < 0 then
        return nil
      end
      offset = offset + item.n
    elseif item.tag == "Seek" then
      return nil
    elseif item.tag == "Field" then
      local field_size = primitive_compatible_size(item.desc, addr_size)
      if not field_size then
        return nil
      end
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

function M.native_ctype(desc, addr_size, namespace)
  local impl = native_ctype_impl[desc.tag]
  assert(impl, "unknown descriptor tag: " .. tostring(desc.tag))
  return impl(desc, addr_size, namespace)
end

local mempeep_ctype_impl = {}

function M.mempeep_ctype(desc, addr_size, namespace)
  local impl = mempeep_ctype_impl[desc.tag]
  assert(impl, "unknown descriptor tag: " .. tostring(desc.tag))
  return impl(desc, addr_size, namespace)
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
  if typ then
    return typ
  end
  local n = fmt:match("^c(%d+)$")
  if n then
    return "std::array<char, " .. n .. ">"
  end
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

local addr_size_to_ctype_impl = {
  [1] = "uint8_t",
  [2] = "uint16_t",
  [4] = "uint32_t",
  [8] = "uint64_t",
}

local addr_size_to_ctype = function(addr_size)
  local typ = addr_size_to_ctype_impl[addr_size]
  if typ then
    return typ
  end
  error("unsupported address size " .. tostring(addr_size))
end

remote_ctype_impl.Primitive = function(desc, addr_size)
  assert(desc.fmt)
  return string.packsize(desc.fmt), fmt_to_ctype(desc.fmt)
end

native_ctype_impl.Primitive = function(desc, addr_size, namespace)
  assert(desc.fmt)
  return fmt_to_ctype(desc.fmt)
end

mempeep_ctype_impl.Primitive = function(desc, addr_size, namespace)
  assert(desc.fmt)
  local prim = fmt_to_prim_impl[desc.fmt]
  if prim then
    return namespace .. prim
  end
  return namespace .. "Primitive<" .. fmt_to_ctype(desc.fmt) .. ">"
end

remote_ctype_impl.RemoteAddr = function(desc, addr_size)
  return M.remote_ctype(desc.desc, addr_size)
end

native_ctype_impl.RemoteAddr = function(desc, addr_size, namespace)
  addr_ctype = addr_size_to_ctype(addr_size)
  return namespace .. "RemoteValue<" .. M.mempeep_ctype(desc.desc, addr_size, namespace) .. ", " .. addr_ctype .. ">"
end

mempeep_ctype_impl.RemoteAddr = function(desc, addr_size, namespace)
  addr_ctype = addr_size_to_ctype(addr_size)
  return namespace .. "RemoteAddr<" .. M.mempeep_ctype(desc.desc, addr_size, namespace) .. ", " .. addr_ctype .. ">"
end

remote_ctype_impl.Bounded = function(desc, addr_size)
  return M.remote_ctype(desc.desc, addr_size)
end

native_ctype_impl.Bounded = function(desc, addr_size, namespace)
  return M.native_ctype(desc.desc, addr_size, namespace)
end

mempeep_ctype_impl.Bounded = function(desc, addr_size, namespace)
  local inner = M.mempeep_ctype(desc.desc, addr_size, namespace)
  return string.format("%sBounded<%s, %d, %d>", namespace, inner, desc.min, desc.max)
end

remote_ctype_impl.ZString = function(desc, addr_size)
  return desc.max_len, string.format("char[%d]", desc.max_len)
end

native_ctype_impl.ZString = function(desc, addr_size, namespace)
  return "std::string"
end

mempeep_ctype_impl.ZString = function(desc, addr_size, namespace)
  return namespace .. "ZString<" .. hex_str(desc.max_len) .. ">"
end

remote_ctype_impl.RawAddr = function(desc, addr_size)
  return addr_size, "void*"
end

native_ctype_impl.RawAddr = function(desc, addr_size, namespace)
  return addr_size_to_ctype(addr_size)
end

mempeep_ctype_impl.RawAddr = function(desc, addr_size, namespace)
  return namespace .. "RawAddr<" .. addr_size_to_ctype(addr_size) .. ">"
end

remote_ctype_impl.Ref = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  if string.find(ref_ctype, "^char%[%d+%]$") then
    -- sadly can't write char[..]* in C, fall back to char*
    ref_ctype = "char"
  end
  return addr_size, ref_ctype .. "*"
end

native_ctype_impl.Ref = function(desc, addr_size, namespace)
  return M.native_ctype(desc.desc, addr_size, namespace)
end

mempeep_ctype_impl.Ref = function(desc, addr_size, namespace)
  return namespace .. "Ref<" .. M.mempeep_ctype(desc.desc, addr_size, namespace) .. ">"
end

remote_ctype_impl.NullableRef = remote_ctype_impl.Ref

native_ctype_impl.NullableRef = function(desc, addr_size, namespace)
  return "std::optional<" .. M.native_ctype(desc.desc, addr_size, namespace) .. ">"
end

mempeep_ctype_impl.NullableRef = function(desc, addr_size, namespace)
  return namespace .. "NullableRef<" .. M.mempeep_ctype(desc.desc, addr_size, namespace) .. ">"
end

remote_ctype_impl.Array = function(desc, addr_size)
  local ref_size, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return desc.n * ref_size, "std::array<" .. ref_ctype .. ", " .. hex_str(desc.n) .. ">"
end

native_ctype_impl.Array = function(desc, addr_size, namespace)
  return "std::array<" .. M.native_ctype(desc.desc, addr_size, namespace) .. ", " .. hex_str(desc.n) .. ">"
end

mempeep_ctype_impl.Array = function(desc, addr_size, namespace)
  if primitive_compatible_size(desc, addr_size) then
    return "Primitive<" .. M.native_ctype(desc, addr_size, namespace) .. ">"
  else
    return namespace
      .. "Array<"
      .. M.mempeep_ctype(desc.desc, addr_size, namespace)
      .. ", "
      .. hex_str(desc.n)
      .. ">"
  end
end

remote_ctype_impl.Vector = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return 2 * addr_size, ref_ctype .. "*"
end

native_ctype_impl.Vector = function(desc, addr_size, namespace)
  return "std::vector<" .. M.native_ctype(desc.desc, addr_size, namespace) .. ">"
end

mempeep_ctype_impl.Vector = function(desc, addr_size, namespace)
  return namespace
    .. "Vector<"
    .. M.mempeep_ctype(desc.desc, addr_size, namespace)
    .. ", "
    .. hex_str(desc.max_len)
    .. ">"
end

remote_ctype_impl.List = function(desc, addr_size)
  local _, ref_ctype = M.remote_ctype(desc.desc, addr_size)
  return addr_size, ref_ctype .. "*"
end

native_ctype_impl.List = function(desc, addr_size, namespace)
  return "std::vector<" .. M.native_ctype(desc.desc, addr_size, namespace) .. ">"
end

mempeep_ctype_impl.List = function(desc, addr_size, namespace)
  return namespace
    .. "List<"
    .. M.mempeep_ctype(desc.desc, addr_size, namespace)
    .. ", &"
    .. desc.desc.name
    .. "::"
    .. desc.next_key
    .. ", "
    .. namespace
    .. "ListKind::"
    .. desc.kind
    .. ", "
    .. hex_str(desc.max_len)
    .. ">"
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

native_ctype_impl.Struct = function(desc, addr_size, namespace)
  return desc.name
end

mempeep_ctype_impl.Struct = function(desc, addr_size, namespace)
  if primitive_compatible_size(desc, addr_size) then
    return namespace .. "Primitive<" .. desc.name .. ">"
  else
    return "T" .. desc.name
  end
end

function M.remote_struct_cdecl(desc, addr_size, out)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  out:write(string.format("struct %s {\n", desc.name))
  local offset = 0
  for i, item in ipairs(desc.fields) do
    if item.tag == "Skip" then
      offset = offset + item.n
    elseif item.tag == "Seek" then
      offset = item.n
    elseif item.tag == "Field" then
      local field_size, field_ctype = M.remote_ctype(item.desc, addr_size)
      if item.desc.tag == "Vector" then
        out:write(string.format("  %s %s_begin;  // offset %s\n", field_ctype, item.key, hex_str(offset)))
        out:write(string.format("  %s %s_end;    // offset %s\n", field_ctype, item.key, hex_str(offset + addr_size)))
      else
        out:write(string.format("  %s %s;  // offset %s\n", field_ctype, item.key, hex_str(offset)))
      end
      offset = offset + field_size
    end
  end
  out:write("};\n\n")
end

local native_struct_cdecl_1 = function(desc, addr_size, namespace, out)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  out:write(string.format("struct %s {\n", desc.name))
  if primitive_compatible_size(desc, addr_size) then
    local offset = 0
    local pad_index = 0
    for _, item in ipairs(desc.fields) do
      if item.tag == "Skip" then
        out:write(string.format("  uint8_t _pad%d[%s];\n", pad_index, hex_str(item.n)))
        pad_index = pad_index + 1
        offset = offset + item.n
      elseif item.tag == "Seek" then
        error("primitive compatible struct cannot have Seek")
      elseif item.tag == "Field" then
        local field_size = primitive_compatible_size(item.desc, addr_size)
        assert(field_size ~= nil)
        local field_native_ctype = M.native_ctype(item.desc, addr_size, namespace)
        out:write(string.format("  %s %s;\n", field_native_ctype, item.key))
        offset = offset + field_size
      end
    end
  else
    for _, item in ipairs(desc.fields) do
      if item.tag == "Field" then
        local field_ctype = M.native_ctype(item.desc, addr_size, namespace)
        out:write(string.format("  %s %s;\n", field_ctype, item.key))
      end
    end
  end
  out:write("};\n\n")
end

local native_struct_cdecl_2 = function(desc, addr_size, namespace, out)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  if primitive_compatible_size(desc, addr_size) then
    return
  end
  out:write("using T" .. desc.name .. " = " .. namespace .. "Struct<\n")
  out:write("  " .. desc.name .. ",\n")
  out:write("  " .. namespace .. "Fields<\n")
  for i, item in ipairs(desc.fields) do
    local is_last = (i == #desc.fields)
    local comma = is_last and ">>;\n\n" or ",\n"
    if item.tag == "Skip" then
      out:write(string.format("    %sSkip<%s>%s", namespace, hex_str(item.n), comma))
    elseif item.tag == "Seek" then
      out:write(string.format("    %sSeek<%s>%s", namespace, hex_str(item.n), comma))
    elseif item.tag == "Field" then
      local mtype = M.mempeep_ctype(item.desc, addr_size, namespace)
      out:write(string.format("    %sField<%s, &%s::%s>%s", namespace, mtype, desc.name, item.key, comma))
    end
  end
end

function M.native_struct_cdecl(desc, addr_size, namespace, out)
  native_struct_cdecl_1(desc, addr_size, namespace, out)
  native_struct_cdecl_2(desc, addr_size, namespace, out)
end

--- Collect all Struct descriptors reachable from `desc` in topological order
-- (dependencies before dependents). Each struct is visited at most once.
-- @param desc descriptor to walk
-- @param visited table used to track already-visited struct names
-- @param order table (array) accumulating structs in declaration order
local function collect_structs(desc, visited, order)
  if desc.tag == "Primitive" or desc.tag == "RawAddr" or desc.tag == "ZString" then
    return
  elseif
    desc.tag == "Ref"
    or desc.tag == "NullableRef"
    or desc.tag == "Array"
    or desc.tag == "Vector"
    or desc.tag == "List"
    or desc.tag == "Bounded"
    or desc.tag == "RemoteAddr"
  then
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
-- @param descs descriptors to collect structs from
-- @param addr_size integer size in bytes of the remote address type
-- @param out output stream
function M.remote_struct_cdecls(descs, addr_size, out)
  each_struct(descs, function(s)
    M.remote_struct_cdecl(s, addr_size, out)
  end)
end

--- Write all Struct declarations reachable from `descs` in correct declaration
-- order (dependencies before dependents), using the native C++ layout.
-- @param descs descriptors to collect structs from
-- @param out output stream
function M.native_struct_cdecls(descs, addr_size, namespace, out)
  each_struct(descs, function(s)
    M.native_struct_cdecl(s, addr_size, namespace, out)
  end)
end

--- Collect all C++ includes required to declare the native types reachable
-- from `desc`. Each include is a string such as `"<vector>"`.
-- @param desc descriptor to walk
-- @param visited table used to track already-visited struct names
-- @param includes table used to accumulate required include strings
local function walk_native_includes(desc, visited, includes)
  if desc.tag == "Primitive" then
    if desc.fmt ~= "f" and desc.fmt ~= "d" then
      includes["<cstdint>"] = true
    end
  elseif desc.tag == "RemoteAddr" then
    includes["<cstdint>"] = true
  elseif desc.tag == "RawAddr" then
    includes["<cstdint>"] = true
  elseif desc.tag == "Bounded" then
    walk_native_includes(desc.desc, visited, includes)
  elseif desc.tag == "ZString" then
    includes["<string>"] = true
  elseif desc.tag == "NullableRef" then
    includes["<optional>"] = true
    walk_native_includes(desc.desc, visited, includes)
  elseif desc.tag == "Ref" then
    walk_native_includes(desc.desc, visited, includes)
  elseif desc.tag == "Array" then
    includes["<array>"] = true
    walk_native_includes(desc.desc, visited, includes)
  elseif desc.tag == "Vector" or desc.tag == "List" then
    includes["<vector>"] = true
    walk_native_includes(desc.desc, visited, includes)
  elseif desc.tag == "Struct" then
    if visited[desc.name] then return end
    visited[desc.name] = true
    for _, item in ipairs(desc.fields) do
      if item.tag == "Field" then
        walk_native_includes(item.desc, visited, includes)
      end
    end
  else
    error("walk_native_includes: unknown descriptor tag: " .. tostring(desc.tag))
  end
end

--- Write #include directives for all C++ headers required by `descs`.
-- Always includes <mempeep/descriptors.hpp>. Additional headers are
-- determined by walking the descriptor tree.
-- @param descs array of descriptors to walk
-- @param out output stream
function M.write_native_includes(descs, out)
  local visited = {}
  local includes = { ["<mempeep/descriptors.hpp>"] = true }
  for _, desc in ipairs(descs) do
    walk_native_includes(desc, visited, includes)
  end
  local sorted = {}
  for inc in pairs(includes) do
    sorted[#sorted + 1] = inc
  end
  table.sort(sorted)
  for _, inc in ipairs(sorted) do
    out:write("#include " .. inc .. "\n")
  end
end

return M
