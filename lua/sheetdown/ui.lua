local columns = require("sheetdown.columns")
local reader = require("sheetdown.reader")

local M = {}

-- The first prompt does two jobs at once:
-- - choose which columns to keep
-- - define the output order
--
-- The parser accepts either names or indexes, so the UI can stay simple while
-- still covering the agreed v0.1.0 workflow.
local function prompt_columns(headers, on_done)
	vim.ui.input({
		prompt = "Columns (names or indexes): ",
		default = columns.default_expression(headers),
	}, function(input)
		if input == nil then
			on_done(nil)
			return
		end

		local parsed_columns, parse_error =
			columns.parse_expression(input, headers)
		if not parsed_columns then
			on_done(nil, parse_error)
			return
		end

		on_done(parsed_columns)
	end)
end

-- Alignment is a single choice for the whole rendered table in v0.1.0.
local function prompt_alignment(config, on_done)
	local default_alignment = config.default_alignment or "left"
	local items = { "left", "center", "right" }

	vim.ui.select(items, {
		prompt = "Alignment:",
		format_item = function(item)
			if item == default_alignment then
				return item .. " (default)"
			end

			return item
		end,
	}, function(choice)
		if choice == nil then
			on_done(nil)
			return
		end

		on_done(choice)
	end)
end

-- Row details are prompted only after the mode is known so the UI stays
-- linear: choose the mode first, then fill in the one extra value it needs.
local function prompt_row_detail(row_mode, config, on_done)
	local default_rows = config.default_rows or {}

	if row_mode == "head" or row_mode == "tail" then
		vim.ui.input({
			prompt = ("%s row count: "):format(
				row_mode == "head" and "Head" or "Tail"
			),
			default = tostring(default_rows.count or 5),
		}, function(input)
			if input == nil then
				on_done(nil)
				return
			end

			local count = tonumber(vim.trim(input))
			if not count or count % 1 ~= 0 or count < 1 then
				on_done(nil, "Row count must be a positive integer.")
				return
			end

			on_done({
				mode = row_mode,
				count = math.floor(count),
			})
		end)
		return
	end

	vim.ui.input({
		prompt = "Range start:end: ",
		default = "1:5",
	}, function(input)
		if input == nil then
			on_done(nil)
			return
		end

		local range, range_error = reader.parse_range(input)
		if not range then
			on_done(nil, range_error)
			return
		end

		on_done(range)
	end)
end

-- We surface the configured default row mode in the picker text, but still let
-- the user choose a different mode for this single command run.
local function prompt_row_mode(config, on_done)
	local default_mode = (config.default_rows or {}).mode or "head"
	local items = { "head", "tail", "range" }

	vim.ui.select(items, {
		prompt = "Row mode:",
		format_item = function(item)
			if item == default_mode then
				return item .. " (default)"
			end

			return item
		end,
	}, function(choice)
		if choice == nil then
			on_done(nil)
			return
		end

		prompt_row_detail(choice, config, on_done)
	end)
end

---Collect table options from the user in the same order as the workflow.
---
---Prompt order:
--- 1. columns
--- 2. alignment
--- 3. row mode and its detail
---@param headers string[]
---@param config table
---@param on_done fun(result: table|nil, err: string|nil)
function M.prompt(headers, config, on_done)
	prompt_columns(headers, function(parsed_columns, column_error)
		if column_error then
			on_done(nil, column_error)
			return
		end

		if parsed_columns == nil then
			on_done(nil, nil)
			return
		end

		prompt_alignment(config, function(alignment)
			if alignment == nil then
				on_done(nil, nil)
				return
			end

			prompt_row_mode(config, function(row_selection, row_error)
				if row_error then
					on_done(nil, row_error)
					return
				end

				if row_selection == nil then
					on_done(nil, nil)
					return
				end

				on_done({
					parsed_columns = parsed_columns,
					alignment = alignment,
					row_selection = row_selection,
				}, nil)
			end)
		end)
	end)
end

return M
