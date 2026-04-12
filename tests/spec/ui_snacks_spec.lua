local helpers = require("tests.helpers")
local ui_helpers = require("tests.ui_helpers")
local ui_session = require("sheetdown.ui_session")

return {
	{
		name = "ui_snacks.prompt builds an input-focused picker with fourth-pass controls and highlights",
		run = function()
			ui_helpers.unload("sheetdown.ui_snacks")

			local captured_opts
			local picker, probe

			ui_helpers.with_module("snacks", {
				input = function() end,
				picker = {
					pick = function(opts)
						captured_opts = opts
						picker, probe = ui_helpers.make_fake_picker(opts.items)
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
				helpers.eq(captured_opts.win.list.keys.r, "sheetdown_reset_session")
				helpers.eq(captured_opts.win.list.keys.u, "sheetdown_exclude_all")

				captured_opts.on_show(picker)
				helpers.ok(picker.sheetdown_session)
				helpers.eq(picker.sheetdown_session:status_name(), "open")
				helpers.eq(#picker.list.selected, 0)
				helpers.eq(probe.focused(), "input")
				helpers.eq(probe.refresh_calls(), 1)
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
				helpers.ok(#probe.preview_lines() > 0)

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
				picker.list.current = captured_opts.items[2]
				captured_opts.actions.sheetdown_toggle_current(picker)
				helpers.eq(
					vim.tbl_map(function(item)
						return item.column_index
					end, picker.list.selected),
					{ 1, 3 }
				)
				captured_opts.actions.sheetdown_toggle_current(picker)
				helpers.eq(
					vim.tbl_map(function(item)
						return item.column_index
					end, picker.list.selected),
					{ 1, 3, 2 }
				)
				captured_opts.actions.sheetdown_exclude_all(picker)
				helpers.eq(#picker.list.selected, 0)

				captured_opts.actions.sheetdown_select_all(picker)
				picker.input.win.buf = probe.input_buf()
				vim.api.nvim_buf_set_lines(probe.input_buf(), 0, -1, false, { "ci" })
				picker.input:update()
				captured_opts.actions.sheetdown_reset_session(picker)
				helpers.eq(#picker.list.selected, 0)
				helpers.eq(probe.focused(), "input")
				helpers.eq(vim.api.nvim_buf_get_lines(probe.input_buf(), 0, -1, false), {
					"",
				})
			end)

			probe.cleanup()
			ui_helpers.unload("sheetdown.ui_snacks")

			if not ok then
				error(err)
			end
		end,
	},
	{
		name = "ui_snacks.open_session restores a hidden session into picker state",
		run = function()
			ui_helpers.unload("sheetdown.ui_snacks")

			local captured_opts
			local picker, probe
			local session = ui_session.create(
				{ "name", "age", "city" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 5 },
				}
			)

			assert(session:open())
			assert(session:toggle_column(3))
			assert(session:toggle_column(1))
			session:focus_preview("alignment")
			session:set_search_text("ci")
			assert(session:hide())

			ui_helpers.with_module("snacks", {
				input = function() end,
				picker = {
					pick = function(opts)
						captured_opts = opts
						picker, probe = ui_helpers.make_fake_picker(opts.items)
						return picker
					end,
				},
			}, function()
				local ui_snacks = require("sheetdown.ui_snacks")
				ui_snacks.open_session(session, function() end)
			end)

			local ok, err = pcall(function()
				captured_opts.on_show(picker)

				helpers.eq(session:status_name(), "open")
				helpers.eq(probe.focused(), "preview")
				helpers.eq(probe.refresh_calls(), 1)
				helpers.eq(
					vim.tbl_map(function(item)
						return item.column_index
					end, picker.list.selected),
					{ 3, 1 }
				)
				helpers.eq(probe.applied_query(), "ci")
				helpers.eq(probe.visible_items(), { "city" })

				local lines = probe.preview_lines()
				helpers.eq(lines[2], "  city, name")

				captured_opts.actions.sheetdown_reset_session(picker)
				helpers.ok(probe.refresh_calls() >= 2)
				helpers.eq(probe.applied_query(), "")
				helpers.eq(probe.visible_items(), { "name", "age", "city" })
				helpers.eq(
					vim.tbl_map(function(item)
						return item.column_index
					end, picker.list.selected),
					{}
				)
			end)

			probe.cleanup()
			ui_helpers.unload("sheetdown.ui_snacks")

			if not ok then
				error(err)
			end
		end,
	},
	{
		name = "ui_snacks.open_session restores saved query only once per reopen",
		run = function()
			ui_helpers.unload("sheetdown.ui_snacks")

			local session = ui_session.create(
				{ "alpha", "single", "sink", "signal", "since" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 5 },
				}
			)
			local ui_snacks

			local function open_once()
				local captured_opts
				local picker, probe

				ui_helpers.with_module("snacks", {
					input = function() end,
					picker = {
						pick = function(opts)
							captured_opts = opts
							picker, probe = ui_helpers.make_fake_picker(opts.items)
							return picker
						end,
					},
				}, function()
					ui_snacks = require("sheetdown.ui_snacks")
					ui_snacks.open_session(session, function() end)
				end)

				captured_opts.on_show(picker)
				return picker, probe
			end

			assert(session:open())
			session:set_search_text("sin")
			assert(session:hide())

			local ok, err = pcall(function()
				local first_probe
				_, first_probe = open_once()
				helpers.eq(session:status_name(), "open")
				helpers.eq(first_probe.refresh_calls(), 1)
				helpers.eq(first_probe.applied_query(), "sin")
				helpers.eq(first_probe.visible_items(), { "single", "sink", "since" })

				assert(ui_snacks.hide_session(session))
				helpers.eq(session:status_name(), "hidden")

				local second_probe
				_, second_probe = open_once()
				helpers.eq(session:status_name(), "open")
				helpers.eq(second_probe.refresh_calls(), 1)
				helpers.eq(second_probe.applied_query(), "sin")
				helpers.eq(second_probe.visible_items(), { "single", "sink", "since" })

				first_probe.cleanup()
				second_probe.cleanup()
			end)

			ui_helpers.unload("sheetdown.ui_snacks")

			if not ok then
				error(err)
			end
		end,
	},
	{
		name = "ui_snacks.hide_session clears adapter active state before picker close completes",
		run = function()
			ui_helpers.unload("sheetdown.ui_snacks")

			local captured_opts
			local picker, probe
			local done_calls = 0
			local session = ui_session.create(
				{ "name", "age", "city" },
				{
					default_alignment = "left",
					default_rows = { mode = "head", count = 5 },
				}
			)

			ui_helpers.with_module("snacks", {
				input = function() end,
				picker = {
					pick = function(opts)
						captured_opts = opts
						picker, probe = ui_helpers.make_fake_picker(opts.items)
						return picker
					end,
				},
			}, function()
				local ui_snacks = require("sheetdown.ui_snacks")
				ui_snacks.open_session(session, function()
					done_calls = done_calls + 1
				end)
			end)

			local ok, err = pcall(function()
				local ui_snacks = require("sheetdown.ui_snacks")

				captured_opts.on_show(picker)
				helpers.eq(ui_snacks.active_session(), session)
				helpers.eq(session:status_name(), "open")

				assert(ui_snacks.hide_session(session))
				helpers.eq(session:status_name(), "hidden")
				helpers.eq(ui_snacks.active_session(), nil)

				captured_opts.on_close()
				helpers.eq(done_calls, 0)
				helpers.eq(ui_snacks.active_session(), nil)
			end)

			probe.cleanup()
			ui_helpers.unload("sheetdown.ui_snacks")

			if not ok then
				error(err)
			end
		end,
	},
}
