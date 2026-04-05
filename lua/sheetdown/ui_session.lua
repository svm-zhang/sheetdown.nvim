local ui_state = require("sheetdown.ui_state")

local M = {}

local Session = {}
Session.__index = Session

local function current_bufnr(opts)
	if opts and opts.bufnr then
		return opts.bufnr
	end

	return vim.api.nvim_get_current_buf()
end

local function build_item_index(items)
	local by_index = {}

	for _, item in ipairs(items) do
		by_index[item.column_index] = item
	end

	return by_index
end

local function resolve_index(self, item_or_index)
	if type(item_or_index) == "table" then
		return item_or_index.column_index
	end

	if type(item_or_index) == "number" then
		return item_or_index
	end

	return nil
end

local function remove_selected_index(order, target)
	local remaining = {}

	for _, index in ipairs(order) do
		if index ~= target then
			remaining[#remaining + 1] = index
		end
	end

	return remaining
end

local function lifecycle_error(from_status, action)
	return ("Cannot %s a session in %s state."):format(action, from_status)
end

---Create a durable enhanced-UI session that owns selection, lifecycle, and
---render-option state independently of a picker instance.
---@param headers string[]
---@param config table
---@param opts? { bufnr?: integer }
---@return table
function M.create(headers, config, opts)
	local items = ui_state.column_items(headers)
	local config_snapshot = vim.deepcopy(config or {})

	return setmetatable({
		bufnr = current_bufnr(opts),
		headers = vim.deepcopy(headers),
		config = config_snapshot,
		items = items,
		items_by_index = build_item_index(items),
		options = ui_state.create(headers, config_snapshot),
		selected_order = {},
		selected_lookup = {},
		search_text = "",
		focus_target = "input",
		status = "new",
	}, Session)
end

function Session:status_name()
	return self.status
end

function Session:set_search_text(text)
	self.search_text = text or ""
end

function Session:search_value()
	return self.search_text
end

function Session:column_items()
	return self.items
end

function Session:selected_indices()
	return vim.deepcopy(self.selected_order)
end

function Session:selected_items()
	local selected = {}

	for _, index in ipairs(self.selected_order) do
		selected[#selected + 1] = self.items_by_index[index]
	end

	return selected
end

function Session:is_selected(item_or_index)
	local index = resolve_index(self, item_or_index)
	if not index then
		return false
	end

	return self.selected_lookup[index] == true
end

function Session:replace_selection(indices)
	self.selected_order = {}
	self.selected_lookup = {}

	for _, index in ipairs(indices or {}) do
		if self.items_by_index[index] and not self.selected_lookup[index] then
			self.selected_lookup[index] = true
			self.selected_order[#self.selected_order + 1] = index
		end
	end

	return self:selected_items()
end

function Session:toggle_column(item_or_index)
	local index = resolve_index(self, item_or_index)
	if not index or not self.items_by_index[index] then
		return nil, "Unknown column."
	end

	if self.selected_lookup[index] then
		self.selected_lookup[index] = nil
		self.selected_order = remove_selected_index(self.selected_order, index)
	else
		self.selected_lookup[index] = true
		self.selected_order[#self.selected_order + 1] = index
	end

	return self:selected_items()
end

function Session:select_all()
	local indices = {}

	for _, item in ipairs(self.items) do
		indices[#indices + 1] = item.column_index
	end

	return self:replace_selection(indices)
end

function Session:exclude_all()
	return self:replace_selection({})
end

function Session:focus_input()
	self.focus_target = "input"
	ui_state.clear_active_section(self.options)
end

function Session:focus_list()
	self.focus_target = "list"
	ui_state.clear_active_section(self.options)
end

function Session:focus_preview(section)
	self.focus_target = "preview"
	ui_state.set_active_section(self.options, section)
end

function Session:focus_name()
	return self.focus_target
end

function Session:active_section()
	return self.options.active_section
end

function Session:cycle_alignment()
	return ui_state.cycle_alignment(self.options)
end

function Session:cycle_row_mode()
	return ui_state.cycle_row_mode(self.options)
end

function Session:current_row_detail()
	return ui_state.current_row_detail(self.options)
end

function Session:row_detail_label()
	return ui_state.row_detail_label()
end

function Session:set_row_detail(value)
	return ui_state.set_current_row_detail(self.options, value)
end

function Session:preview_spec(opts)
	return ui_state.preview_spec(
		self.headers,
		self.options,
		self:selected_items(),
		opts
	)
end

function Session:build_result()
	return ui_state.build_result(self.headers, self.options, self:selected_items())
end

function Session:reset()
	if self.status ~= "new" and self.status ~= "open" and self.status ~= "hidden" then
		return nil, lifecycle_error(self.status, "reset")
	end

	self.options = ui_state.create(self.headers, self.config)
	self:replace_selection({})
	self:set_search_text("")
	self:focus_input()
	return true
end

function Session:open()
	if self.status ~= "new" then
		return nil, lifecycle_error(self.status, "open")
	end

	self.status = "open"
	return true
end

function Session:hide()
	if self.status ~= "open" then
		return nil, lifecycle_error(self.status, "hide")
	end

	self.status = "hidden"
	return true
end

function Session:restore()
	if self.status ~= "hidden" then
		return nil, lifecycle_error(self.status, "restore")
	end

	self.status = "open"
	return true
end

function Session:activate()
	if self.status == "new" then
		return self:open()
	end

	if self.status == "hidden" then
		return self:restore()
	end

	if self.status == "open" then
		return true
	end

	return nil, lifecycle_error(self.status, "activate")
end

function Session:confirm()
	if self.status ~= "open" then
		return nil, lifecycle_error(self.status, "confirm")
	end

	local result, err = self:build_result()
	if not result then
		return nil, err
	end

	self.status = "confirmed"
	return result
end

function Session:cancel()
	if self.status ~= "new" and self.status ~= "open" and self.status ~= "hidden" then
		return nil, lifecycle_error(self.status, "cancel")
	end

	self.status = "cancelled"
	return true
end

return M
