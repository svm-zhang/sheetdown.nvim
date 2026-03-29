local helpers = require("tests.helpers")
local ui_state = require("sheetdown.ui_state")

local function unload(name)
	package.loaded[name] = nil
end

local function with_module(name, value, fn)
	local original = package.loaded[name]
	package.loaded[name] = value

	local ok, err = xpcall(fn, debug.traceback)
	package.loaded[name] = original
	if not ok then
		error(err)
	end
end

local function create_float(width, height)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = 1,
		col = 1,
		width = width,
		height = height,
		style = "minimal",
		border = "single",
	})

	return {
		buf = buf,
		win = win,
		opts = { wo = {} },
		valid = function(self)
			return vim.api.nvim_win_is_valid(self.win)
		end,
	}
end

local function close_float(float)
	if float and float.win and vim.api.nvim_win_is_valid(float.win) then
		vim.api.nvim_win_close(float.win, true)
	end

	if float and float.buf and vim.api.nvim_buf_is_valid(float.buf) then
		vim.api.nvim_buf_delete(float.buf, { force = true })
	end
end

local function make_fake_picker(items)
	local input_win = create_float(50, 1)
	local preview_win = create_float(90, 12)
	local input_update_calls = 0
	local preview_title
	local preview_lines
	local focused

	local picker = {}
	picker.list = {
		selected = {},
		current = items[1],
		is_selected = function(self, item)
			for _, selected in ipairs(self.selected) do
				if selected.column_index == item.column_index then
					return true
				end
			end

			return false
		end,
		select = function(self)
			local current = self.current
			if not current then
				return
			end

			if self:is_selected(current) then
				local remaining = {}
				for _, selected in ipairs(self.selected) do
					if selected.column_index ~= current.column_index then
						remaining[#remaining + 1] = selected
					end
				end
				self.selected = remaining
				return
			end

			self.selected[#self.selected + 1] = current
		end,
		set_selected = function(self, selected)
			self.selected = selected or {}
		end,
	}
	picker.selected = function()
		return picker.list.selected
	end
	picker.focus = function(_, win)
		focused = win
	end
	picker.close = function() end
	picker.preview = {
		win = preview_win,
		wo = {},
		reset = function() end,
		minimal = function() end,
		set_title = function(_, value)
			preview_title = value
		end,
		set_lines = function(_, lines)
			preview_lines = vim.deepcopy(lines)
			vim.api.nvim_buf_set_lines(preview_win.buf, 0, -1, false, lines)
		end,
	}
	picker.input = {
		win = input_win,
		update = function()
			input_update_calls = input_update_calls + 1
		end,
	}

	return picker, {
		cleanup = function()
			close_float(input_win)
			close_float(preview_win)
		end,
		focused = function()
			return focused
		end,
		preview_title = function()
			return preview_title
		end,
		preview_lines = function()
			return preview_lines
		end,
		preview_extmarks = function()
			return vim.api.nvim_buf_get_extmarks(
				preview_win.buf,
				-1,
				0,
				-1,
				{ details = true }
			)
		end,
		input_extmarks = function()
			return vim.api.nvim_buf_get_extmarks(
				input_win.buf,
				-1,
				0,
				-1,
				{ details = true }
			)
		end,
		input_buf = function()
			return input_win.buf
		end,
		input_update_calls = function()
			return input_update_calls
		end,
	}
end

return {
	{
		name = "ui_state.build_result keeps selected columns in selection order",
		run = function()
			local state = ui_state.create(
				{ "name", "age", "city" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 5 },
				}
			)

			local result = assert(ui_state.build_result(
				{ "name", "age", "city" },
				state,
				{
					{ column_index = 3 },
					{ column_index = 1 },
				}
			))

			helpers.eq(result.parsed_columns.indices, { 3, 1 })
			helpers.eq(result.parsed_columns.headers, { "city", "name" })
		end,
	},
	{
		name = "ui_state.parse_row_selection parses positive counts",
		run = function()
			local state = ui_state.create(
				{ "name" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 7 },
				}
			)

			local row_selection = assert(ui_state.parse_row_selection(state))
			helpers.eq(row_selection, { mode = "head", count = 7 })
		end,
	},
	{
		name = "ui_state.set_current_row_detail switches to explicit range mode",
		run = function()
			local state = ui_state.create(
				{ "name" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 5 },
				}
			)

			assert(ui_state.set_current_row_detail(state, "3:9"))
			local row_selection = assert(ui_state.parse_row_selection(state))
			helpers.eq(row_selection, {
				mode = "range",
				start = 3,
				finish = 9,
			})
		end,
	},
	{
		name = "ui_state.build_result rejects empty selections",
		run = function()
			local state = ui_state.create(
				{ "name" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 5 },
				}
			)

			local result, err =
				ui_state.build_result({ "name" }, state, {})
			helpers.eq(result, nil)
			helpers.match(err, "No columns selected")
		end,
	},
	{
		name = "ui_state.preview_lines shows grouped key hints and render options",
		run = function()
			local state = ui_state.create(
				{ "name", "age", "city" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 5 },
				}
			)

			local lines = ui_state.preview_lines(
				{ "name", "age", "city" },
				state,
				{
					{ column_index = 3 },
					{ column_index = 1 },
				}
			)

			helpers.eq(lines[1], "Selected")
			helpers.eq(lines[2], "  city, name")
			helpers.eq(lines[4], "Table Render Option")
			helpers.eq(lines[5], "  Alignment: [x] left  [ ] right  [ ] center")
			helpers.eq(lines[6], "  # rows: 5")
			helpers.eq(lines[7], "  Row mode: [x] head  [ ] tail")
			helpers.eq(lines[9], "Key Hints")
			helpers.eq(lines[10], "  Navigation")
				helpers.eq(
					lines[11],
					"    Go to column selection: <C-j>/<Down>   Go to search: <i>   Confirm: <CR>   Close: <Esc>"
				)
			helpers.eq(lines[12], "  Column Selection")
			helpers.eq(
				lines[13],
				"    Include/Exclude toggle: <Tab>   Select all: <c>   Exclude all: <u>"
			)
			helpers.eq(lines[14], "  Render Option")
			helpers.eq(
				lines[15],
				"    Alignment: <a>   Row mode: <m>   Rows or range: <d>"
			)
		end,
	},
	{
		name = "ui_state.preview_lines hides row mode when detail is a range",
		run = function()
			local state = ui_state.create(
				{ "name", "age", "city" },
				{
					default_alignment = "left",
					default_rows = { mode = "range", count = 5 },
				}
			)

			local lines = ui_state.preview_lines(
				{ "name", "age", "city" },
				state,
				{}
			)

			helpers.eq(lines[6], "  Range: 1:5")
			helpers.eq(lines[14], "    Alignment: <a>   Rows or range: <d>")
		end,
	},
	{
		name = "ui_state.preview_lines truncates the selected summary by available width",
		run = function()
			local state = ui_state.create(
				{ "alpha", "beta", "gamma", "delta", "epsilon" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 5 },
				}
			)

			local lines = ui_state.preview_lines(
				{ "alpha", "beta", "gamma", "delta", "epsilon" },
				state,
				{
					{ column_index = 1 },
					{ column_index = 2 },
					{ column_index = 3 },
					{ column_index = 4 },
					{ column_index = 5 },
				},
				{ width = 24 }
			)

			helpers.match(lines[2], "... (+")
		end,
	},
	{
		name = "ui_snacks.prompt builds an input-focused picker with fourth-pass controls and highlights",
		run = function()
			unload("sheetdown.ui_snacks")

			local captured_opts
			local picker, probe

			with_module("snacks", {
				input = function() end,
				picker = {
					pick = function(opts)
						captured_opts = opts
						picker, probe = make_fake_picker(opts.items)
						return picker
					end,
				},
			}, function()
				local ui_snacks = require("sheetdown.ui_snacks")

				ui_snacks.prompt(
					{ "name", "age", "city" },
					{
						default_alignment = "left",
						default_rows = { mode = "head", count = 5 },
					},
					function() end
				)
			end)

			local ok, err = pcall(function()
				helpers.eq(captured_opts.focus, "input")
				helpers.eq(captured_opts.title, "Sheetdown")
				helpers.eq(captured_opts.prompt, "")
				helpers.eq(captured_opts.layout.layout[3].win, "preview")
				helpers.eq(captured_opts.formatters.selected.unselected, false)
				helpers.eq(captured_opts.icons.ui.selected, "")
				helpers.eq(captured_opts.icons.ui.unselected, "")
				helpers.eq(captured_opts.win.input.keys["/"], false)
				helpers.eq(captured_opts.win.input.keys["<Esc>"][1], "cancel")
				helpers.eq(captured_opts.win.input.keys["<C-j>"][1], "sheetdown_focus_list")
				helpers.eq(captured_opts.win.input.keys["<NL>"][1], "sheetdown_focus_list")
				helpers.eq(captured_opts.win.input.keys["<Down>"][1], "sheetdown_focus_list")
				helpers.eq(captured_opts.win.input.keys["<Tab>"][1], "sheetdown_toggle_current")
				helpers.eq(captured_opts.win.list.keys["<C-j>"], "sheetdown_focus_list")
				helpers.eq(captured_opts.win.list.keys["<NL>"], "sheetdown_focus_list")
				helpers.eq(captured_opts.win.list.keys.a, "sheetdown_cycle_alignment")
				helpers.eq(captured_opts.win.list.keys.c, "sheetdown_select_all")
				helpers.eq(captured_opts.win.list.keys.d, "sheetdown_edit_row_detail")
				helpers.eq(captured_opts.win.list.keys.i, "sheetdown_focus_input")
				helpers.eq(captured_opts.win.list.keys.m, "sheetdown_cycle_row_mode")
				helpers.eq(captured_opts.win.list.keys.u, "sheetdown_exclude_all")

				captured_opts.on_show(picker)
				helpers.eq(#picker.list.selected, 0)
				helpers.eq(probe.focused(), "input")
				helpers.ok(probe.input_update_calls() >= 1)

				local extmarks = probe.input_extmarks()
				helpers.ok(#extmarks > 0)
				helpers.ok(#probe.preview_extmarks() > 0)

				local foreign_namespace =
					vim.api.nvim_create_namespace("sheetdown.ui_spec.foreign")
				vim.api.nvim_buf_set_extmark(
					probe.input_buf(),
					foreign_namespace,
					0,
					0,
					{
						virt_text = {
							{ "foreign", "WarningMsg" },
						},
						virt_text_pos = "overlay",
					}
				)
				local update_calls_before = probe.input_update_calls()
				picker.input:update()
				helpers.eq(probe.input_update_calls(), update_calls_before + 1)
				local foreign_extmarks = vim.api.nvim_buf_get_extmarks(
					probe.input_buf(),
					foreign_namespace,
					0,
					-1,
					{ details = true }
				)
				helpers.eq(#foreign_extmarks, 1)

				helpers.eq(probe.preview_title(), "Table Render Option")
				local lines = probe.preview_lines()
				helpers.eq(lines[1], "Selected")
				helpers.eq(lines[2], "  (none selected)")
				helpers.eq(lines[10], "  Navigation")
				helpers.eq(lines[12], "  Column Selection")
				helpers.eq(lines[14], "  Render Option")

				local selected_chunks = captured_opts.format(
					{ column_index = 2, label = "age" },
					{
						list = {
							is_selected = function()
								return true
							end,
						},
					}
				)
				helpers.eq(selected_chunks[1][1], "[x]")

				local unselected_chunks = captured_opts.format(
					{ column_index = 1, label = "name" },
					{
						list = {
							is_selected = function()
								return false
							end,
						},
					}
				)
				helpers.eq(unselected_chunks[1][1], "[ ]")

				captured_opts.actions.sheetdown_select_all(picker)
				helpers.eq(#picker.list.selected, 3)
				captured_opts.actions.sheetdown_exclude_all(picker)
				helpers.eq(#picker.list.selected, 0)
			end)

			probe.cleanup()
			unload("sheetdown.ui_snacks")

			if not ok then
				error(err)
			end
		end,
	},
	{
		name = "ui.prompt falls back to the vim.ui flow when snacks is unavailable in auto mode",
		run = function()
			unload("sheetdown.ui")

			with_module("sheetdown.ui_fallback", {
				prompt = function(headers, config, on_done)
					helpers.eq(headers, { "name" })
					helpers.eq(config.ui.backend, "auto")
					on_done({ ok = true }, nil)
				end,
			}, function()
				local ui = require("sheetdown.ui")
				local called = false

				ui.prompt({ "name" }, { ui = { backend = "auto" } }, function(result, err)
					called = true
					helpers.eq(err, nil)
					helpers.eq(result, { ok = true })
				end)

				helpers.ok(called)
			end)

			unload("sheetdown.ui")
		end,
	},
	{
		name = "ui.prompt accepts the explicit fallback backend name",
		run = function()
			unload("sheetdown.ui")

			with_module("sheetdown.ui_fallback", {
				prompt = function(headers, config, on_done)
					helpers.eq(headers, { "name" })
					helpers.eq(config.ui.backend, "fallback")
					on_done({ ok = "fallback" }, nil)
				end,
			}, function()
				local ui = require("sheetdown.ui")
				local called = false

				ui.prompt(
					{ "name" },
					{ ui = { backend = "fallback" } },
					function(result, err)
						called = true
						helpers.eq(err, nil)
						helpers.eq(result, { ok = "fallback" })
					end
				)

				helpers.ok(called)
			end)

			unload("sheetdown.ui")
		end,
	},
	{
		name = "ui.prompt routes to the snacks backend when snacks is available in auto mode",
		run = function()
			unload("sheetdown.ui")

			with_module("snacks", {}, function()
				with_module("sheetdown.ui_snacks", {
					prompt = function(headers, config, on_done)
						helpers.eq(headers, { "name" })
						helpers.eq(config.ui.backend, "auto")
						on_done({ ok = "snacks" }, nil)
					end,
				}, function()
					local ui = require("sheetdown.ui")
					local called = false

					ui.prompt(
						{ "name" },
						{ ui = { backend = "auto" } },
						function(result, err)
							called = true
							helpers.eq(err, nil)
							helpers.eq(result, { ok = "snacks" })
						end
					)

					helpers.ok(called)
				end)
			end)

			unload("sheetdown.ui")
		end,
	},
	{
		name = "ui.prompt reports a clear error when snacks backend is explicitly requested but unavailable",
		run = function()
			unload("sheetdown.ui")
			unload("snacks")

			local ui = require("sheetdown.ui")
			local received_error

			ui.prompt({ "name" }, { ui = { backend = "snacks" } }, function(_, err)
				received_error = err
			end)

			helpers.match(received_error, "snacks.nvim UI backend requested")
			unload("sheetdown.ui")
		end,
	},
}
