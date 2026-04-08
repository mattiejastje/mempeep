local M = {}

--- Make a mock reader backed by a flat string.
-- Addresses are byte offsets into data (0-based).
function M.mock_memory_reader(fmt, data)
  local reader = {}
  reader.fmt = fmt
  function reader:read(addr, size)
    if addr < 0 or addr + size > #data then
      return nil
    end
    return data:sub(addr + 1, addr + size)
  end
  return reader
end

return M
