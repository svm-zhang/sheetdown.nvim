local M = {}

local defaults = {
	default_alignment = "left",
	default_rows = {
		mode = "head",
		count = 5,
	},
	ui = {
		backend = "auto",
	},
}

local values = vim.deepcopy(defaults)

---Get the current plugin configuration.
---
---A deep copy is returned so callers cannot accidentally mutate the global
---config table in place.
---@return table
function M.get()
	return vim.deepcopy(values)
end

---Merge user configuration with defaults.
---
---`default_rows` is merged deeply so callers can override only `mode` or only
---`count` without rebuilding the whole nested table.
---@param opts? table
---@return table
function M.setup(opts)
	opts = opts or {}
	values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
	return M.get()
end

return M
