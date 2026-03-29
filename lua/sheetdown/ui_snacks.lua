local ui_state = require("sheetdown.ui_state")

local M = {}

local placeholder_namespace = vim.api.nvim_create_namespace(
	"sheetdown.ui_snacks.placeholder"
)
local preview_namespace = vim.api.nvim_create_namespace("sheetdown.ui_snacks.preview")

local major_headings = {
	["Selected"] = true,
	["Table Render Option"] = true,
	["Key Hints"] = true,
}

local subheadings = {
	["  Navigation"] = true,
	["  Column Selection"] = true,
	["  Render Option"] = true,
}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "sheetdown" })
end

local function selected_items(picker)
	if not picker or not picker.selected then
		return {}
	end

	return picker:selected({ fallback = false })
end

local function current_input_text(input)
	if not input or not input.win or not input.win.buf then
		return ""
	end

	local lines = vim.api.nvim_buf_get_lines(input.win.buf, 0, 1, false)
	return lines[1] or ""
end

local function update_input_placeholder(input)
	if not input or not input.win or not input.win.buf then
		return
	end

	vim.api.nvim_buf_clear_namespace(input.win.buf, placeholder_namespace, 0, -1)

	if current_input_text(input) ~= "" then
		return
	end

	vim.api.nvim_buf_set_extmark(input.win.buf, placeholder_namespace, 0, 0, {
		virt_text = {
			{ "Search column ...", "Comment" },
		},
		virt_text_pos = "overlay",
	})
end

local function apply_input_display_tweaks(input)
	if not input or not input.win or not input.win:valid() then
		return
	end

	if input.win.opts and input.win.opts.wo then
		input.win.opts.wo.statuscolumn = ""
	end

	pcall(vim.api.nvim_set_option_value, "statuscolumn", "", {
		win = input.win.win,
	})

	update_input_placeholder(input)
end

local function patch_input_display(picker)
	if not picker or not picker.input then
		return
	end

	local original_update = picker.input.update

	-- Wrap the existing update hook instead of replacing it so sheetdown keeps
	-- its placeholder/statuscolumn tweaks without discarding snacks.nvim input
	-- behavior.
	picker.input.update = function(self, ...)
		if original_update then
			original_update(self, ...)
		end

		apply_input_display_tweaks(self)
	end
end

local function render_preview(picker, headers, state)
	if not picker or not picker.preview then
		return
	end

	local preview_win = picker.preview.win
	if not preview_win or not preview_win:valid() then
		return
	end

	local spec = ui_state.preview_spec(headers, state, selected_items(picker), {
		width = vim.api.nvim_win_get_width(preview_win.win),
	})
	picker.preview:reset()
	picker.preview:minimal()
	picker.preview:set_title(spec.title)
	picker.preview:set_lines(spec.lines)
	vim.api.nvim_buf_clear_namespace(preview_win.buf, preview_namespace, 0, -1)

	for line_number, line in ipairs(spec.lines) do
		local row = line_number - 1

		if major_headings[line] then
			vim.api.nvim_buf_set_extmark(
				preview_win.buf,
				preview_namespace,
				row,
				0,
				{
					end_col = #line,
					hl_group = "Title",
				}
			)
		elseif subheadings[line] then
			vim.api.nvim_buf_set_extmark(
				preview_win.buf,
				preview_namespace,
				row,
				2,
				{
					end_col = #line,
					hl_group = "Identifier",
				}
			)
		elseif line:match("^─+$") then
			vim.api.nvim_buf_set_extmark(
				preview_win.buf,
				preview_namespace,
				row,
				0,
				{
					end_col = #line,
					hl_group = "Comment",
				}
			)
		end

		local search_from = 1
		while true do
			local key_start, key_finish = line:find("<[^>]+>", search_from)
			if not key_start then
				break
			end

			vim.api.nvim_buf_set_extmark(
				preview_win.buf,
				preview_namespace,
				row,
				key_start - 1,
				{
					end_col = key_finish,
					hl_group = "Special",
				}
			)
			search_from = key_finish + 1
		end

		local suffix_start, suffix_finish = line:find("%.%.%. %(%+%d+%)")
		if suffix_start then
			vim.api.nvim_buf_set_extmark(
				preview_win.buf,
				preview_namespace,
				row,
				suffix_start - 1,
				{
					end_col = suffix_finish,
					hl_group = "Comment",
				}
			)
		end
	end

	local target = spec.focus_lines[state.active_section] or 1
	pcall(vim.api.nvim_win_set_cursor, preview_win.win, { target, 0 })
end

local function refresh(picker, headers, state)
	render_preview(picker, headers, state)
	if picker and picker.input and picker.input.update then
		picker.input:update()
	end
end

local function focus_input(picker, headers, state)
	ui_state.clear_active_section(state)
	picker:focus("input", { show = true })
	refresh(picker, headers, state)
end

local function focus_list(picker, headers, state)
	ui_state.clear_active_section(state)
	picker:focus("list", { show = true })
	refresh(picker, headers, state)
end

local function focus_preview_section(picker, headers, state, section)
	ui_state.set_active_section(state, section)
	picker:focus("preview", { show = true })
	refresh(picker, headers, state)
end

local function format_column(item, picker)
	local selected = picker.list:is_selected(item)
	return {
		{ selected and "[x]" or "[ ]", selected and "SnacksPickerSelected" or "SnacksPickerUnselected" },
		{ " " },
		{ ("%2d"):format(item.column_index), "Number" },
		{ " " },
		{ item.label },
	}
end

local function build_layout()
	return {
		layout = {
			backdrop = false,
			width = 0.58,
			min_width = 92,
			max_width = 116,
			height = 0.72,
			min_height = 22,
			box = "vertical",
			border = true,
			title = " {title} ",
			title_pos = "center",
			{ win = "input", height = 1, border = "bottom" },
			{ win = "list", border = "none" },
			{
				win = "preview",
				height = 15,
				border = "top",
				title = "{preview}",
				title_pos = "left",
			},
		},
	}
end

local function edit_row_detail(Snacks, state, picker, headers)
	Snacks.input({
		prompt = ("%s: "):format(ui_state.row_detail_label()),
		default = ui_state.current_row_detail(state),
	}, function(value)
		if value == nil then
			focus_preview_section(picker, headers, state, "row_detail")
			return
		end

		local ok, err = ui_state.set_current_row_detail(state, value)
		if not ok then
			notify(err, vim.log.levels.ERROR)
		end

		focus_preview_section(picker, headers, state, "row_detail")
	end)
end

---Collect table options with a visible picker-based snacks.nvim workflow.
---@param headers string[]
---@param config table
---@param on_done fun(result: table|nil, err: string|nil)
function M.prompt(headers, config, on_done)
	local Snacks = require("snacks")
	local state = ui_state.create(headers, config)
	local completed = false
	local items = ui_state.column_items(headers)

	local picker = Snacks.picker.pick({
		source = "sheetdown_columns",
		title = "Sheetdown",
		prompt = "",
		focus = "input",
		items = items,
		layout = build_layout(),
		matcher = {
			sort_empty = false,
		},
		sort = {
			fields = { "score:desc", "idx" },
		},
		formatters = {
			selected = {
				show_always = false,
				unselected = false,
			},
		},
		icons = {
			ui = {
				selected = "",
				unselected = "",
			},
		},
		preview = function(ctx)
			render_preview(ctx.picker, headers, state)
		end,
		format = format_column,
		win = {
			input = {
				keys = {
					["/"] = false,
					["<A-d>"] = false,
					["<A-f>"] = false,
					["<A-h>"] = false,
					["<A-i>"] = false,
					["<A-m>"] = false,
					["<A-p>"] = false,
					["<A-r>"] = false,
					["<A-w>"] = false,
					["<C-a>"] = false,
					["<Esc>"] = {
						"cancel",
						mode = { "i", "n" },
					},
					["<C-j>"] = {
						"sheetdown_focus_list",
						mode = { "i", "n" },
					},
					["<NL>"] = {
						"sheetdown_focus_list",
						mode = { "i", "n" },
					},
					["<Down>"] = {
						"sheetdown_focus_list",
						mode = { "i", "n" },
					},
					["<Tab>"] = {
						"sheetdown_toggle_current",
						mode = { "i", "n" },
					},
				},
			},
			list = {
				keys = {
					["/"] = "sheetdown_focus_input",
					["<A-d>"] = false,
					["<A-f>"] = false,
					["<A-h>"] = false,
					["<A-i>"] = false,
					["<A-m>"] = false,
					["<A-p>"] = false,
					["<A-r>"] = false,
					["<A-w>"] = false,
					["<C-a>"] = false,
					["<Esc>"] = "cancel",
					["<Tab>"] = "sheetdown_toggle_current",
					["<CR>"] = "confirm",
					["<Down>"] = false,
					["<C-j>"] = "sheetdown_focus_list",
					["<NL>"] = "sheetdown_focus_list",
					a = "sheetdown_cycle_alignment",
					c = "sheetdown_select_all",
					d = "sheetdown_edit_row_detail",
					i = "sheetdown_focus_input",
					m = "sheetdown_cycle_row_mode",
					u = "sheetdown_exclude_all",
				},
			},
			preview = {
				wo = {
					conceallevel = 0,
					cursorline = true,
					linebreak = true,
					wrap = true,
				},
				keys = {
					["<Esc>"] = "cancel",
					["<CR>"] = "confirm",
					["<C-j>"] = "sheetdown_focus_list",
					["<NL>"] = "sheetdown_focus_list",
					["<Down>"] = "sheetdown_focus_list",
					a = "sheetdown_cycle_alignment",
					c = "sheetdown_select_all",
					d = "sheetdown_edit_row_detail",
					i = "sheetdown_focus_input",
					m = "sheetdown_cycle_row_mode",
					u = "sheetdown_exclude_all",
				},
			},
		},
		actions = {
			confirm = function(current_picker)
				local result, result_error =
					ui_state.build_result(headers, state, selected_items(current_picker))
				if not result then
					notify(result_error, vim.log.levels.ERROR)
					refresh(current_picker, headers, state)
					return
				end

				completed = true
				current_picker:close()
				vim.schedule(function()
					on_done(result, nil)
				end)
			end,
			sheetdown_cycle_alignment = function(current_picker)
				ui_state.cycle_alignment(state)
				focus_preview_section(current_picker, headers, state, "alignment")
			end,
			sheetdown_cycle_row_mode = function(current_picker)
				local _, err = ui_state.cycle_row_mode(state)
				if err then
					notify(err, vim.log.levels.ERROR)
					focus_preview_section(current_picker, headers, state, "row_detail")
					return
				end

				focus_preview_section(current_picker, headers, state, "row_mode")
			end,
			sheetdown_edit_row_detail = function(current_picker)
				edit_row_detail(Snacks, state, current_picker, headers)
			end,
			sheetdown_exclude_all = function(current_picker)
				current_picker.list:set_selected({})
				focus_list(current_picker, headers, state)
			end,
			sheetdown_focus_input = function(current_picker)
				focus_input(current_picker, headers, state)
			end,
			sheetdown_focus_list = function(current_picker)
				focus_list(current_picker, headers, state)
			end,
			sheetdown_select_all = function(current_picker)
				current_picker.list:set_selected(items)
				focus_list(current_picker, headers, state)
			end,
			sheetdown_toggle_current = function(current_picker)
				current_picker.list:select()
				focus_list(current_picker, headers, state)
			end,
		},
		on_show = function(current_picker)
			current_picker.list:set_selected({})
			focus_input(current_picker, headers, state)
		end,
		on_close = function()
			if completed then
				return
			end

			vim.schedule(function()
				on_done(nil, nil)
			end)
		end,
	})

	patch_input_display(picker)
	if picker and picker.input then
		picker.input:update()
	end

	return picker
end

return M
