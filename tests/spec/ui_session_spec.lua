local helpers = require("tests.helpers")
local ui_session = require("sheetdown.ui_session")

local function new_session()
	return ui_session.create(
		{ "name", "age", "city" },
		{
			default_alignment = "left",
			default_rows = { mode = "head", count = 5 },
		},
		{ bufnr = 7 }
	)
end

return {
	{
		name = "ui_session owns column selection order outside the picker",
		run = function()
			local session = new_session()
			assert(session:open())

			assert(session:toggle_column(3))
			assert(session:toggle_column(1))

			helpers.eq(session:selected_indices(), { 3, 1 })
			helpers.eq(
				vim.tbl_map(function(item)
					return item.label
				end, session:selected_items()),
				{ "city", "name" }
			)

			local result = assert(session:build_result())
			helpers.eq(result.parsed_columns.indices, { 3, 1 })
			helpers.eq(result.parsed_columns.headers, { "city", "name" })
		end,
	},
	{
		name = "ui_session tracks lifecycle transitions for hide and restore",
		run = function()
			local session = new_session()

			helpers.eq(session:status_name(), "new")
			assert(session:open())
			helpers.eq(session:status_name(), "open")
			assert(session:hide())
			helpers.eq(session:status_name(), "hidden")
			assert(session:restore())
			helpers.eq(session:status_name(), "open")
		end,
	},
	{
		name = "ui_session keeps focus and search state through hide and restore",
		run = function()
			local session = new_session()

			assert(session:open())
			session:set_search_text("ci")
			session:focus_preview("alignment")
			assert(session:toggle_column(3))
			assert(session:hide())
			assert(session:restore())

			helpers.eq(session:search_value(), "ci")
			helpers.eq(session:focus_name(), "preview")
			helpers.eq(session:active_section(), "alignment")
			helpers.eq(session:selected_indices(), { 3 })
		end,
	},
	{
		name = "ui_session confirm finalizes an open session",
		run = function()
			local session = new_session()

			assert(session:open())
			assert(session:toggle_column(2))

			local result = assert(session:confirm())
			helpers.eq(session:status_name(), "confirmed")
			helpers.eq(result.parsed_columns.indices, { 2 })
			helpers.eq(result.parsed_columns.headers, { "age" })
		end,
	},
	{
		name = "ui_session rejects invalid lifecycle transitions",
		run = function()
			local session = new_session()

			local ok, err = session:hide()
			helpers.eq(ok, nil)
			helpers.match(err, "Cannot hide")

			assert(session:open())
			assert(session:cancel())
			helpers.eq(session:status_name(), "cancelled")

			local restore_ok, restore_err = session:restore()
			helpers.eq(restore_ok, nil)
			helpers.match(restore_err, "Cannot restore")
		end,
	},
}
