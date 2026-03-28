local fallback = require("sheetdown.ui_fallback")

local M = {}

local function resolve_backend(config)
	local requested = ((config.ui or {}).backend) or "auto"

	if requested == "fallback" or requested == "vim_ui" then
		return "fallback"
	end

	local snacks_available = pcall(require, "snacks")
	if requested == "snacks" then
		if snacks_available then
			return "snacks"
		end

		return nil, "snacks.nvim UI backend requested but snacks.nvim is not available."
	end

	if requested == "auto" then
		return snacks_available and "snacks" or "fallback"
	end

	return nil, ("Unknown UI backend: %s"):format(requested)
end

---Collect table options through the configured UI backend.
---@param headers string[]
---@param config table
---@param on_done fun(result: table|nil, err: string|nil)
function M.prompt(headers, config, on_done)
	local backend, backend_error = resolve_backend(config)
	if not backend then
		on_done(nil, backend_error)
		return
	end

	if backend == "snacks" then
		return require("sheetdown.ui_snacks").prompt(headers, config, on_done)
	end

	return fallback.prompt(headers, config, on_done)
end

return M
