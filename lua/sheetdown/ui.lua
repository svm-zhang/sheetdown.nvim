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

M.resolve_backend = resolve_backend

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

---Open an existing durable enhanced-UI session through the active backend.
---@param session table
---@param config table
---@param on_done fun(result: table|nil, err: string|nil)
---@return table|nil, string|nil
function M.open_session(session, config, on_done)
	local backend, backend_error = resolve_backend(config)
	if not backend then
		on_done(nil, backend_error)
		return nil, backend_error
	end

	if backend == "snacks" then
		return require("sheetdown.ui_snacks").open_session(session, on_done)
	end

	local err = "Enhanced UI sessions are not available for the fallback backend."
	on_done(nil, err)
	return nil, err
end

---Return the currently open enhanced-UI session, if any.
---@param config table
---@return table|nil, string|nil
function M.active_session(config)
	local backend, backend_error = resolve_backend(config)
	if not backend then
		return nil, backend_error
	end

	if backend == "snacks" then
		return require("sheetdown.ui_snacks").active_session()
	end

	return nil
end

---Hide the currently open enhanced-UI session.
---@param session table
---@param config table
---@return boolean|nil, string|nil
function M.hide_session(session, config)
	local backend, backend_error = resolve_backend(config)
	if not backend then
		return nil, backend_error
	end

	if backend == "snacks" then
		return require("sheetdown.ui_snacks").hide_session(session)
	end

	return nil, "Enhanced UI sessions are not available for the fallback backend."
end

return M
