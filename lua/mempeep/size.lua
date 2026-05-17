local M = {}

--- Return the fixed remote byte size of a descriptor.
-- @param desc descriptor
-- @param addr_fmt string address format (e.g. "I4")
-- @return integer byte size
function M.byte_size(desc, addr_fmt)
  local addr_size = string.packsize(addr_fmt)
  local tag = desc.tag
  if tag == "Primitive" then
    return string.packsize(desc.fmt)
  elseif tag == "Bounded" then
    return M.byte_size(desc.desc, addr_fmt)
  elseif tag == "ZString" then
    return desc.max_len
  elseif tag == "RawAddr" or tag == "Ref" or tag == "NullableRef" or tag == "List" then
    return addr_size
  elseif tag == "Array" then
    local elem = M.byte_size(desc.desc, addr_fmt)
    return elem * desc.n
  elseif tag == "Vector" then
    return 2 * addr_size
  elseif tag == "Struct" then
    local offset = 0
    for _, item in ipairs(desc.fields) do
      if item.tag == "Skip" then
        offset = offset + item.n
      elseif item.tag == "Seek" then
        offset = item.n
      elseif item.tag == "Field" then
        local s = M.byte_size(item.desc, addr_fmt)
        offset = offset + s
      end
    end
    return offset
  elseif tag == "RemoteAddr" then
    return M.byte_size(desc.desc, addr_fmt)
  end
  error("unknown descriptor tag: " .. tostring(desc.tag))
end

return M
