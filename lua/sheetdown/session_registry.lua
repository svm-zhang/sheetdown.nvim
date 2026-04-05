local M = {}

local entries = {}

---Get the current enhanced session entry for a markdown buffer.
---@param bufnr integer
---@return table|nil
function M.get(bufnr)
	return entries[bufnr]
end

---Store the current enhanced session entry for a markdown buffer.
---@param entry table
---@return table
function M.set(entry)
	entries[entry.bufnr] = entry
	return entry
end

---Remove and return the current enhanced session entry for a markdown buffer.
---@param bufnr integer
---@return table|nil
function M.clear(bufnr)
	local entry = entries[bufnr]
	entries[bufnr] = nil
	return entry
end

---Reset the in-memory registry. This is only used by tests.
function M.clear_all()
	entries = {}
end

return M
