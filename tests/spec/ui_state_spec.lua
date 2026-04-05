local helpers = require("tests.helpers")
local ui_state = require("sheetdown.ui_state")

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

			local result, err = ui_state.build_result({ "name" }, state, {})
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
				"    Alignment: <a>   Row mode: <m>   Rows or range: <d>   Reset: <r>"
			)
			helpers.eq(lines[16], "  Session")
			helpers.eq(lines[17], "    Hide and resume: run :TableFromFile again")
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
			helpers.eq(
				lines[14],
				"    Alignment: <a>   Rows or range: <d>   Reset: <r>"
			)
			helpers.eq(lines[15], "  Session")
			helpers.eq(lines[16], "    Hide and resume: run :TableFromFile again")
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
}
