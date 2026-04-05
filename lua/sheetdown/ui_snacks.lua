local ui_session = require("sheetdown.ui_session")
local notify = require("sheetdown.notify")

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
	["  Session"] = true,
}

local picker_by_session = {}
local active_session

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

local function set_input_text(input, value)
	if not input or not input.win or not input.win.buf then
		return
	end

	vim.api.nvim_buf_set_lines(input.win.buf, 0, -1, false, { value or "" })
	pcall(vim.api.nvim_win_set_cursor, input.win.win, { 1, #(value or "") })
end

local function apply_input_display_tweaks(input, session)
	if not input or not input.win or not input.win:valid() then
		return
	end

	if input.win.opts and input.win.opts.wo then
		input.win.opts.wo.statuscolumn = ""
	end

	pcall(vim.api.nvim_set_option_value, "statuscolumn", "", {
		win = input.win.win,
	})

	if session then
		session:set_search_text(current_input_text(input))
	end

	update_input_placeholder(input)
end

local function patch_input_display(picker, session)
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

		apply_input_display_tweaks(self, session)
	end
end

local function remember_picker(session, picker)
	active_session = session
	picker_by_session[session] = picker
end

local function forget_picker(session)
	if active_session == session then
		active_session = nil
	end

	picker_by_session[session] = nil
end

local function render_preview(picker, session)
	if not picker or not picker.preview then
		return
	end

	local preview_win = picker.preview.win
	if not preview_win or not preview_win:valid() then
		return
	end

	local spec = session:preview_spec({
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

	local target = spec.focus_lines[session:active_section()] or 1
	pcall(vim.api.nvim_win_set_cursor, preview_win.win, { target, 0 })
end

local function sync_picker_selection(picker, session)
	if not picker or not picker.list or not picker.list.set_selected then
		return
	end

	picker.list:set_selected(session:selected_items())
end

local function current_picker_item(picker)
	if picker and picker.current then
		return picker:current({ resolve = false })
	end

	return picker and picker.list and picker.list.current or nil
end

local function refresh(picker, session)
	render_preview(picker, session)
	if picker and picker.input and picker.input.update then
		picker.input:update()
	end
end

local function sync_input_from_session(picker, session)
	if not picker or not picker.input then
		return
	end

	local text = session:search_value()

	if picker.input.filter then
		picker.input.filter.pattern = text
		picker.input.filter.search = text
	end

	if picker.input.set then
		picker.input:set(text, text)
	else
		set_input_text(picker.input, text)
		if picker.input.update then
			picker.input:update()
		end
	end

	if picker.refresh then
		picker:refresh()
	elseif picker.find then
		picker:find({ refresh = true })
	end
end

local function focus_input(picker, session)
	session:focus_input()
	picker:focus("input", { show = true })
	refresh(picker, session)
end

local function focus_list(picker, session)
	session:focus_list()
	picker:focus("list", { show = true })
	refresh(picker, session)
end

local function focus_preview_section(picker, session, section)
	session:focus_preview(section)
	picker:focus("preview", { show = true })
	refresh(picker, session)
end

local function format_column(item, picker)
	local session = picker.sheetdown_session
	local selected = session and session:is_selected(item) or false
	if not selected and picker.list and picker.list.is_selected then
		selected = picker.list:is_selected(item)
	end

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

local function edit_row_detail(Snacks, session, picker)
	Snacks.input({
		prompt = ("%s: "):format(session:row_detail_label()),
		default = session:current_row_detail(),
	}, function(value)
		if value == nil then
			focus_preview_section(picker, session, "row_detail")
			return
		end

		local ok, err = session:set_row_detail(value)
		if not ok then
			notify.error(err)
		end

		focus_preview_section(picker, session, "row_detail")
	end)
end

local function apply_session_focus(picker, session)
	if session:focus_name() == "list" then
		return focus_list(picker, session)
	end

	if session:focus_name() == "preview" then
		return focus_preview_section(picker, session, session:active_section())
	end

	return focus_input(picker, session)
end

---Open an enhanced snacks.nvim session against the given durable session
---object. The same session may later be reopened after an internal hide/restore
---transition without recreating its selection or render-option state.
---@param session table
---@param on_done fun(result: table|nil, err: string|nil)
function M.open_session(session, on_done)
	local Snacks = require("snacks")
	local completed = false
	local items = session:column_items()

	local ok, err = session:activate()
	if not ok then
		on_done(nil, err)
		return nil
	end

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
			render_preview(ctx.picker, session)
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
					r = "sheetdown_reset_session",
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
					r = "sheetdown_reset_session",
					u = "sheetdown_exclude_all",
				},
			},
		},
		actions = {
			confirm = function(current_picker)
				local result, result_error = session:confirm()
				if not result then
					notify.error(result_error)
					refresh(current_picker, session)
					return
				end

				completed = true
				current_picker:close()
				vim.schedule(function()
					on_done(result, nil)
				end)
			end,
			sheetdown_cycle_alignment = function(current_picker)
				session:cycle_alignment()
				focus_preview_section(current_picker, session, "alignment")
			end,
			sheetdown_cycle_row_mode = function(current_picker)
				local _, cycle_error = session:cycle_row_mode()
				if cycle_error then
					notify.error(cycle_error)
					focus_preview_section(current_picker, session, "row_detail")
					return
				end

				focus_preview_section(current_picker, session, "row_mode")
			end,
			sheetdown_edit_row_detail = function(current_picker)
				edit_row_detail(Snacks, session, current_picker)
			end,
			sheetdown_exclude_all = function(current_picker)
				session:exclude_all()
				sync_picker_selection(current_picker, session)
				focus_list(current_picker, session)
			end,
			sheetdown_focus_input = function(current_picker)
				focus_input(current_picker, session)
			end,
			sheetdown_focus_list = function(current_picker)
				focus_list(current_picker, session)
			end,
			sheetdown_select_all = function(current_picker)
				session:select_all()
				sync_picker_selection(current_picker, session)
				focus_list(current_picker, session)
			end,
			sheetdown_reset_session = function(current_picker)
				local ok, reset_error = session:reset()
				if not ok then
					notify.error(reset_error)
					refresh(current_picker, session)
					return
				end

				sync_input_from_session(current_picker, session)
				sync_picker_selection(current_picker, session)
				focus_input(current_picker, session)
			end,
			sheetdown_toggle_current = function(current_picker)
				session:toggle_column(current_picker_item(current_picker))
				sync_picker_selection(current_picker, session)
				focus_list(current_picker, session)
			end,
		},
		on_show = function(current_picker)
			current_picker.sheetdown_session = session
			remember_picker(session, current_picker)
			sync_input_from_session(current_picker, session)
			sync_picker_selection(current_picker, session)
			apply_session_focus(current_picker, session)
		end,
		on_close = function()
			forget_picker(session)

			if completed then
				return
			end

			if session:status_name() == "hidden" then
				return
			end

			session:cancel()
			vim.schedule(function()
				on_done(nil, nil)
			end)
		end,
		})

	patch_input_display(picker, session)
	if picker and picker.input then
		sync_input_from_session(picker, session)
	end

	return picker
end

---Collect table options with a visible picker-based snacks.nvim workflow.
---@param headers string[]
---@param config table
---@param on_done fun(result: table|nil, err: string|nil)
function M.prompt(headers, config, on_done)
	local session = ui_session.create(headers, config)
	return M.open_session(session, on_done)
end

---Return the currently open enhanced-UI session.
---@return table|nil
function M.active_session()
	return active_session
end

---Hide the currently open picker for the given enhanced-UI session.
---@param session table
---@return boolean|nil, string|nil
function M.hide_session(session)
	local picker = picker_by_session[session]
	if not picker then
		return nil, "No active sheetdown enhanced UI session for this buffer."
	end

	local ok, err = session:hide()
	if not ok then
		return nil, err
	end

	-- Clear adapter-owned active state before closing so rapid repeated
	-- :TableFromFile calls do not observe a hidden session as still active
	-- while the picker is finishing its close callback.
	forget_picker(session)
	picker:close()
	return true
end

return M
