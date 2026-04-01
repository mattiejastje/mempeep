--- Dump C style version of descriptor or struct.

local M = {}

local desc_to_ctype_impl = {}

function M.desc_to_ctype(desc, addr_size)
  local impl = desc_to_ctype_impl[desc.tag]
  assert(impl, "unknown descriptor tag: " .. tostring(desc.tag))
  return impl(desc, addr_size)
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
  typ = fmt_to_ctype_impl[fmt]
  assert(typ, "unknown format '" .. tostring(fmt) .. "'")
  return typ
end

desc_to_ctype_impl.Primitive = function(desc, addr_size)
  assert(desc.fmt)
  return string.packsize(desc.fmt), fmt_to_ctype(desc.fmt)
end

desc_to_ctype_impl.RawAddr = function(desc, addr_size)
  return addr_size, "void*"
end

desc_to_ctype_impl.Ref = function(desc, addr_size)
  _, ref_ctype = M.desc_to_ctype(desc.desc, addr_size)
  return addr_size, ref_ctype .. "*"
end

desc_to_ctype_impl.NullableRef = desc_to_ctype_impl.Ref

desc_to_ctype_impl.Array = function(desc, addr_size)
  local ref_size, ref_ctype = M.desc_to_ctype(desc.desc, addr_size)
  return desc.n * ref_size, "std::array<" .. ref_ctype .. ", " .. desc.n .. ">"
end

desc_to_ctype_impl.Vector = function(desc, addr_size)
  local _, ref_ctype = M.desc_to_ctype(desc.desc, addr_size)
  return 2 * addr_size, "std::vector<" .. ref_ctype .. ">"
end

desc_to_ctype_impl.CircularList = function(desc, addr_size)
  local _, ref_ctype = M.desc_to_ctype(desc.desc, addr_size)
  return addr_size, ref_ctype .. "*"
end

desc_to_ctype_impl.Struct = function(desc, addr_size)
  local size = 0
  for _, item in ipairs(desc.fields) do
    if item.tag == "Skip" then
      size = size + item.n
    elseif item.tag == "Seek" then
      size = item.n
    elseif item.tag == "Field" then
      local field_size, _ = M.desc_to_ctype(item.desc, addr_size)
      size = size + field_size
    end
  end
  return size, desc.name
end

function M.struct_to_cdecl(desc, addr_size)
  assert(desc.tag == "Struct", "descriptor must be Struct, but got " .. tostring(desc.tag))
  print(string.format("struct %s {", desc.name))
  local offset = 0
  for _, item in ipairs(desc.fields) do
    if item.tag == "Skip" then
      offset = offset + item.n
    elseif item.tag == "Seek" then
      offset = item.n
    elseif item.tag == "Field" then
      local field_size, field_ctype = M.desc_to_ctype(item.desc, addr_size)
      print(string.format("  %s %s;  // offset 0x%x", field_ctype, item.key, offset))
      offset = offset + field_size
    end
  end
  print("};")
end

return M
