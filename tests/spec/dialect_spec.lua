local dialect = require("sheetdown.dialect")
local helpers = require("tests.helpers")

return {
	{
		name = "dialect.detect_from_lines detects CSV from the header row",
		run = function()
			local detected = assert(dialect.detect_from_lines({
				"name,age,city",
				"Alice,30,Paris",
				"Bob,41,Berlin",
			}))

			helpers.eq(detected.format, "csv")
			helpers.eq(detected.delimiter, ",")
		end,
	},
	{
		name = "dialect.detect_from_lines detects TSV from the header row",
		run = function()
			local detected = assert(dialect.detect_from_lines({
				"name\tage\tcity",
				"Alice\t30\tParis",
				"Bob\t41\tBerlin",
			}))

			helpers.eq(detected.format, "tsv")
			helpers.eq(detected.delimiter, "\t")
		end,
	},
	{
		name = "dialect.detect_from_lines follows the header even if later rows are messy",
		run = function()
			local detected = assert(dialect.detect_from_lines({
				"name\tage\tcity",
				"Alice,30,Paris",
				"Bob 41,\tBerlin",
			}))

			helpers.eq(detected.format, "tsv")
			helpers.eq(detected.delimiter, "\t")
		end,
	},
	{
		name = "dialect.detect_from_lines rejects ambiguous header schemas",
		run = function()
			local detected, err = dialect.detect_from_lines({
				"name,age\tcity",
				"Alice,30\tParis",
				"Bob,41\tBerlin",
			})

			helpers.eq(detected, nil)
			helpers.match(err, "header")
			helpers.match(err, "ambiguous")
		end,
	},
	{
		name = "dialect.detect_from_lines rejects headers without a supported delimiter",
		run = function()
			local detected, err = dialect.detect_from_lines({
				"name age city",
				"Alice 30 Paris",
			})

			helpers.eq(detected, nil)
			helpers.match(err, "Use comma or tab")
		end,
	},
}
