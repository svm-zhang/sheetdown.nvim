local reader = require("sheetdown.reader")

local M = {}

local alignment_order = { "left", "right", "center" }
local row_mode_order = { "head", "tail" }
local separator = string.rep("─", 20)

local valid_alignments = {}
for _, value in ipairs(alignment_order) do
	valid_alignments[value] = true
end

local valid_row_modes = {}
for _, value in ipairs(row_mode_order) do
	valid_row_modes[value] = true
end

local function cycle_value(order, current)
	for index, value in ipairs(order) do
		if value == current then
			return order[(index % #order) + 1]
		end
	end

	return order[1]
end

local function render_choice_line(label, values, current)
	local parts = { ("%s: "):format(label) }

	for index, value in ipairs(values) do
		if index > 1 then
			parts[#parts + 1] = "  "
		end

		parts[#parts + 1] = (
			(current == value and "[x]" or "[ ]") .. " " .. value
		)
	end

	return table.concat(parts)
end

local function selected_items_or_empty(items)
	return items or {}
end

local function string_width(value)
	return vim.api.nvim_strwidth(value or "")
end

local function truncate_selected_summary(headers, items, max_width)
	local selected = {}
	for _, item in ipairs(selected_items_or_empty(items)) do
		selected[#selected + 1] = headers[item.column_index]
	end

	if #selected == 0 then
		return "(none selected)"
	end

	local full = table.concat(selected, ", ")
	if not max_width or string_width(full) <= max_width then
		return full
	end

	local kept = {}
	local kept_width = 0

	for index, header in ipairs(selected) do
		local segment = (#kept > 0 and ", " or "") .. header
		local next_width = kept_width + string_width(segment)
		local hidden = #selected - index
		local suffix = hidden > 0 and (" ... (+%d)"):format(hidden) or ""

		if next_width + string_width(suffix) <= max_width then
			kept[#kept + 1] = header
			kept_width = next_width
		else
			break
		end
	end

	if #kept == 0 then
		return ("... (+%d)"):format(#selected)
	end

	local hidden = #selected - #kept
	if hidden == 0 then
		return table.concat(kept, ", ")
	end

	return table.concat(kept, ", ") .. (" ... (+%d)"):format(hidden)
end

---Create the shared enhanced-UI state object.
---
---The picker keeps track of which columns are on and in what order. This state
---object only stores table-render options.
---@param headers string[]
---@param config table
---@return table
function M.create(headers, config)
	local default_rows = (config or {}).default_rows or {}
	local default_alignment = (config or {}).default_alignment or "left"
	local default_mode = default_rows.mode or "head"
	local default_count = tonumber(default_rows.count) or 5

	if default_count % 1 ~= 0 or default_count < 1 then
		default_count = 5
	end

	local state = {
		alignment = valid_alignments[default_alignment] and default_alignment
			or "left",
		row_input_kind = "count",
		row_count = math.floor(default_count),
		row_mode = valid_row_modes[default_mode] and default_mode or "head",
		row_range = ("1:%d"):format(math.floor(default_count)),
		active_section = nil,
	}

	if default_mode == "range" then
		state.row_input_kind = "range"
	end

	return state
end

---@param state table
---@return string
function M.cycle_alignment(state)
	state.alignment = cycle_value(alignment_order, state.alignment)
	return state.alignment
end

---@param state table
---@return string|nil, string|nil
function M.cycle_row_mode(state)
	if state.row_input_kind ~= "count" then
		return nil, "Row mode only applies when using a numeric row count."
	end

	state.row_mode = cycle_value(row_mode_order, state.row_mode)
	return state.row_mode
end

---@param state table
---@return string
function M.current_row_detail(state)
	if state.row_input_kind == "range" then
		return state.row_range
	end

	return tostring(state.row_count)
end

---@return string
function M.row_detail_label()
	return "Rows or range"
end

---@param state table
---@param value string
---@return true|nil, string|nil
function M.set_current_row_detail(state, value)
	local text = vim.trim(value or "")
	if text == "" then
		return nil, "Rows or range must be a positive integer or start:end."
	end

	local count = tonumber(text)
	if text:match("^%d+$") and count and count % 1 == 0 and count >= 1 then
		state.row_input_kind = "count"
		state.row_count = math.floor(count)
		return true
	end

	if not text:find(":", 1, true) then
		return nil, "Rows or range must be a positive integer or start:end."
	end

	local range, range_error = reader.parse_range(text)
	if not range then
		return nil, range_error
	end

	state.row_input_kind = "range"
	state.row_range = ("%d:%d"):format(range.start, range.finish)
	return true
end

---@param state table
---@return table|nil, string|nil
function M.parse_row_selection(state)
	if state.row_input_kind == "range" then
		return reader.parse_range(state.row_range)
	end

	return {
		mode = state.row_mode,
		count = state.row_count,
	}
end

---@param headers string[]
---@return table[]
function M.column_items(headers)
	local items = {}

	for index, header in ipairs(headers) do
		items[#items + 1] = {
			idx = index,
			column_index = index,
			label = header,
			text = header,
		}
	end

	return items
end

---@param items table[]|nil
---@return integer[]
function M.selected_indices(items)
	local indices = {}

	for _, item in ipairs(selected_items_or_empty(items)) do
		indices[#indices + 1] = item.column_index
	end

	return indices
end

---@param headers string[]
---@param items table[]|nil
---@return string[]
function M.selected_headers(headers, items)
	local selected = {}

	for _, item in ipairs(selected_items_or_empty(items)) do
		selected[#selected + 1] = headers[item.column_index]
	end

	return selected
end

---@param headers string[]
---@param state table
---@param items table[]|nil
---@return table|nil, string|nil
function M.build_result(headers, state, items)
	local indices = M.selected_indices(items)
	if #indices == 0 then
		return nil, "No columns selected."
	end

	local row_selection, row_error = M.parse_row_selection(state)
	if not row_selection then
		return nil, row_error
	end

	return {
		parsed_columns = {
			indices = indices,
			headers = M.selected_headers(headers, items),
		},
		alignment = state.alignment,
		row_selection = row_selection,
	}
end

---@param state table
---@param section string|nil
function M.set_active_section(state, section)
	state.active_section = section
end

---@param state table
function M.clear_active_section(state)
	state.active_section = nil
end

---@param headers string[]
---@param state table
---@param items table[]|nil
---@param opts? { width?: integer }
---@return table
function M.preview_spec(headers, state, items, opts)
	local width = opts and opts.width or nil
	local summary_width = width and math.max(width - 2, 12) or nil
	local lines = {
		"Selected",
		"  " .. truncate_selected_summary(headers, items, summary_width),
		separator,
		"Table Render Option",
		"  " .. render_choice_line("Alignment", alignment_order, state.alignment),
	}
	local focus_lines = {
		alignment = 5,
	}

	if state.row_input_kind == "count" then
		lines[#lines + 1] = ("  # rows: %d"):format(state.row_count)
		focus_lines.row_detail = #lines
		lines[#lines + 1] = "  "
			.. render_choice_line("Row mode", row_mode_order, state.row_mode)
		focus_lines.row_mode = #lines
	else
		lines[#lines + 1] = "  Range: " .. state.row_range
		focus_lines.row_detail = #lines
	end

	lines[#lines + 1] = separator
	lines[#lines + 1] = "Key Hints"
	lines[#lines + 1] = "  Navigation"
	lines[#lines + 1] = "    Go to column selection: <C-j>/<Down>   Go to search: <i>   Confirm: <CR>   Close: <Esc>"
	lines[#lines + 1] = "  Column Selection"
	lines[#lines + 1] = "    Include/Exclude toggle: <Tab>   Select all: <c>   Exclude all: <u>"
	lines[#lines + 1] = "  Render Option"
	if state.row_input_kind == "count" then
		lines[#lines + 1] = "    Alignment: <a>   Row mode: <m>   Rows or range: <d>"
	else
		lines[#lines + 1] = "    Alignment: <a>   Rows or range: <d>"
	end

	return {
		title = "Table Render Option",
		lines = lines,
		focus_lines = focus_lines,
	}
end

---@param headers string[]
---@param state table
---@param items table[]|nil
---@param opts? { width?: integer }
---@return string[]
function M.preview_lines(headers, state, items, opts)
	return M.preview_spec(headers, state, items, opts).lines
end

return M
