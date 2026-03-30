--- Tracer that simply reports whether or not errors occurred.
local M = {}

function M.new()
  local t = { ok = true }
  function t:error(e)
    self.ok = false
  end
  function t:success()
    return self.ok
  end
  function t:value(v) end
  function t:begin_fields_item(address, item) end
  function t:end_fields_item() end
  function t:begin_desc(address, desc) end
  function t:end_desc() end
  function t:begin_element(address, index) end
  function t:end_element() end
  return t
end

return M