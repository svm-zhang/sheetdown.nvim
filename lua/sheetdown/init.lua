local config = require("sheetdown.config")
local commands = require("sheetdown.commands")

local M = {}

---Configure sheetdown and return the effective config.
---@param opts? table
---@return table
function M.setup(opts)
	return config.setup(opts)
end

---Run the public table-generation workflow.
function M.table_from_file()
	commands.run()
end

return M
