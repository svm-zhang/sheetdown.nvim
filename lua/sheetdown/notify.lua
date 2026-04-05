local config = require("sheetdown.config")

local M = {}

local function notify(message, level)
	vim.notify(message, level, { title = "sheetdown" })
end

local function info_enabled()
	local notifications = (config.get().notifications or {})
	return notifications.enabled ~= false
end

---Show an informational sheetdown notification when info notices are enabled.
---@param message string
function M.info(message)
	if not info_enabled() then
		return
	end

	notify(message, vim.log.levels.INFO)
end

---Show an error notification regardless of the informational notification
---setting.
---@param message string
function M.error(message)
	notify(message, vim.log.levels.ERROR)
end

return M
