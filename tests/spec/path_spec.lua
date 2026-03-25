local helpers = require("tests.helpers")
local path = require("sheetdown.path")

local root = helpers.repo_root()

return {
	{
		name = "path.resolve resolves relative paths from the current buffer",
		run = function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(
				bufnr,
				root .. "/fixtures/manual/path-spec-one.md"
			)

			local resolved = assert(path.resolve("../data/people.csv", bufnr))
			helpers.eq(resolved.absolute, root .. "/fixtures/data/people.csv")
			helpers.eq(resolved.extension, "csv")
		end,
	},
	{
		name = "path.resolve rejects unsupported extensions",
		run = function()
			local bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(
				bufnr,
				root .. "/fixtures/manual/path-spec-two.md"
			)

			local resolved, err = path.resolve("../manual/sample.md", bufnr)
			helpers.eq(resolved, nil)
			helpers.match(err, "Unsupported file type")
		end,
	},
}
