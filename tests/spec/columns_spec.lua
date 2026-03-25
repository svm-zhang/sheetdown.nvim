local columns = require("sheetdown.columns")
local helpers = require("tests.helpers")

return {
	{
		name = "columns.parse_expression accepts names and preserves order",
		run = function()
			local parsed = assert(
				columns.parse_expression(
					"city,name",
					{ "name", "age", "city" }
				)
			)
			helpers.eq(parsed.indices, { 3, 1 })
			helpers.eq(parsed.headers, { "city", "name" })
		end,
	},
	{
		name = "columns.parse_expression accepts numeric indexes",
		run = function()
			local parsed = assert(
				columns.parse_expression("2,1", { "name", "age", "city" })
			)
			helpers.eq(parsed.indices, { 2, 1 })
		end,
	},
	{
		name = "columns.parse_expression rejects duplicate columns",
		run = function()
			local parsed, err =
				columns.parse_expression("1,name", { "name", "age" })
			helpers.eq(parsed, nil)
			helpers.match(err, "more than once")
		end,
	},
}
