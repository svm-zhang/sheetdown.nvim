local columns = require("sheetdown.columns")
local config = require("sheetdown.config")
local dialect = require("sheetdown.dialect")
local path = require("sheetdown.path")
local reader = require("sheetdown.reader")
local selection = require("sheetdown.selection")
local markdown_table = require("sheetdown.table")
local ui = require("sheetdown.ui")

local M = {}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "sheetdown" })
end

---Run the full table-from-file workflow.
---
--- 1. read the visual selection
--- 2. resolve the local file path
--- 3. detect the delimiter from the header
--- 4. read and validate headers
--- 5. prompt for options
--- 6. read the requested rows
--- 7. render and apply the Markdown table
function M.run()
	local bufnr = vim.api.nvim_get_current_buf()

	-- Gets visually selected texts/code blocks in current buffer
	local selection_info, selection_error = selection.get(bufnr)
	if not selection_info then
		notify(selection_error, vim.log.levels.ERROR)
		return
	end

	-- Resolves path.
	local resolved, path_error =
		path.resolve(selection_info.candidate_path, bufnr)
	if not resolved then
		notify(path_error, vim.log.levels.ERROR)
		return
	end

	local detected, dialect_error = dialect.detect_file(resolved.absolute)
	if not detected then
		notify(
			("%s Please fix the source file and try again."):format(
				dialect_error
			),
			vim.log.levels.ERROR
		)
		return
	end

	local headers, header_error =
		reader.read_headers(resolved.absolute, detected.delimiter)
	if not headers then
		notify(header_error, vim.log.levels.ERROR)
		return
	end

	local _, map_error = columns.validate_headers(headers)
	if map_error then
		notify(map_error, vim.log.levels.ERROR)
		return
	end

	ui.prompt(headers, config.get(), function(options, prompt_error)
		if prompt_error then
			notify(prompt_error, vim.log.levels.ERROR)
			return
		end

		if not options then
			return
		end

		local rows, read_error = reader.read_selection(
			resolved.absolute,
			detected.delimiter,
			options.row_selection,
			#headers
		)
		if not rows then
			notify(read_error, vim.log.levels.ERROR)
			return
		end

		if #rows == 0 then
			notify(
				"Empty output after filtering. Adjust the selected rows and try again.",
				vim.log.levels.ERROR
			)
			return
		end

		local table_lines = markdown_table.render({
			headers = headers,
			rows = rows,
			column_indices = options.parsed_columns.indices,
			alignment = options.alignment,
		})

		selection.apply(selection_info, table_lines)
		notify(("Inserted table from %s"):format(resolved.absolute))
	end)
end

return M
