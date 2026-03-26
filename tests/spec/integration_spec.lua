local commands = require("sheetdown.commands")
local helpers = require("tests.helpers")

local root = helpers.repo_root()

local function load_integration_buffer(name)
	local path = root .. "/fixtures/integration/" .. name
	local lines = vim.fn.readfile(path)
	local bufnr = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_name(bufnr, path)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	return bufnr, lines
end

local function set_visual_marks(bufnr, row, text, needle)
	local start_col = assert(text:find(needle, 1, true))
	local finish_col = start_col + #needle - 2
	vim.api.nvim_buf_set_mark(bufnr, "<", row, start_col - 1, {})
	vim.api.nvim_buf_set_mark(bufnr, ">", row, finish_col, {})
end

local function with_mock_ui(select_responses, input_responses, fn, tracker)
	local original_select = vim.ui.select
	local original_input = vim.ui.input
	local selects = vim.deepcopy(select_responses)
	local inputs = vim.deepcopy(input_responses)

	vim.ui.select = function(items, _, callback)
		if tracker then
			tracker.select_calls = tracker.select_calls + 1
		end

		local response = table.remove(selects, 1)
		if response == nil then
			error("missing mocked select response")
		end

		local choice = response
		if type(response) == "number" then
			choice = items[response]
		end

		callback(choice)
	end

	vim.ui.input = function(_, callback)
		if tracker then
			tracker.input_calls = tracker.input_calls + 1
		end

		local response = table.remove(inputs, 1)
		callback(response)
	end

	local ok, err = xpcall(fn, debug.traceback)
	vim.ui.select = original_select
	vim.ui.input = original_input
	if not ok then
		error(err)
	end
end

local function with_mock_notify(fn)
	local original_notify = vim.notify
	local notices = {}

	vim.notify = function(message)
		notices[#notices + 1] = message
	end

	local ok, err = xpcall(fn, debug.traceback)
	vim.notify = original_notify
	if not ok then
		error(err)
	end

	return notices
end

return {
	{
		name = "commands.run inserts a table below a plain-text paragraph",
		run = function()
			local bufnr, lines = load_integration_buffer("plain.md")
			local line = lines[1]
			set_visual_marks(bufnr, 1, line, "../data/people.csv")

			with_mock_ui({ "left", "head" }, { "name,city", "2" }, function()
				commands.run()
			end)

			helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
				"The data lives at ../data/people.csv.",
				"",
				"| name  | city   |",
				"| :---- | :----- |",
				"| Alice | Paris  |",
				"| Bob   | Berlin |",
				"",
				"Next paragraph.",
			})
		end,
	},
	{
		name = "commands.run accepts CSV data from a file with a nonstandard extension",
		run = function()
			local bufnr, lines = load_integration_buffer("nonstandard_extension.md")
			local line = lines[1]
			set_visual_marks(bufnr, 1, line, "../data/people.data")

			with_mock_ui({ "left", "head" }, { "name,city", "1" }, function()
				commands.run()
			end)

			helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
				"../data/people.data",
				"",
				"| name  | city  |",
				"| :---- | :---- |",
				"| Alice | Paris |",
			})
		end,
	},
	{
		name = "commands.run inserts below for an inline path between fenced blocks",
		run = function()
			local bufnr, lines =
				load_integration_buffer("inline_between_fences.md")

			local row, line =
				helpers.find_line(lines, "../data/ambiguous.case_2.csv")
			set_visual_marks(bufnr, row, line, "../data/ambiguous.case_2.csv")

			with_mock_ui({ "left", "head" }, { "", "2" }, function()
				commands.run()
			end)

			helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 6, 20, false), {
				"## Ambiguous case 2",
				"",
				"This reveals the current implementation problem: `../data/ambiguous.case_2.csv`",
				"",
				"| name  age | city   |",
				"| :-------- | :----- |",
				"| Alice 30  | Paris  |",
				"| Bob 41,   | Berlin |",
				"",
				"## Lower fenced block",
				"",
				"```text",
				"../data/malformed_body.tsv",
				"```",
			})
		end,
	},
	{
		name = "commands.run replaces a fenced code block with a table",
		run = function()
			local bufnr, lines = load_integration_buffer("fenced.md")
			local row, line = helpers.find_line(lines, "../data/people.tsv")
			set_visual_marks(bufnr, row, line, "../data/people.tsv")

			with_mock_ui({ "center", "head" }, { "", "1" }, function()
				commands.run()
			end)

			helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
				"| name  | age | city  |",
				"| :---: | :-: | :---: |",
				"| Alice | 30  | Paris |",
				"",
				"After block.",
			})
		end,
	},
	{
		name = "commands.run adds a leading blank line when replacing a fenced block below a heading",
		run = function()
			local bufnr, lines = load_integration_buffer("fenced_under_heading.md")
			local row, line = helpers.find_line(lines, "../data/people.tsv")
			set_visual_marks(bufnr, row, line, "../data/people.tsv")

			with_mock_ui({ "center", "head" }, { "", "1" }, function()
				commands.run()
			end)

			helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
				"## Some header",
				"",
				"| name  | age | city  |",
				"| :---: | :-: | :---: |",
				"| Alice | 30  | Paris |",
			})
		end,
	},
	{
		name = "commands.run inserts below for a plain-text path between fenced blocks",
		run = function()
			local bufnr, lines =
				load_integration_buffer("plain_between_fences.md")
			local row, line = helpers.find_line(lines, "../data/people.csv")
			set_visual_marks(bufnr, row, line, "../data/people.csv")

			with_mock_ui({ "left", "head" }, { "name,city", "1" }, function()
				commands.run()
			end)

			helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
				"```text",
				"../data/people.tsv",
				"```",
				"",
				"Reference: ../data/people.csv",
				"",
				"| name  | city  |",
				"| :---- | :---- |",
				"| Alice | Paris |",
				"",
				"```text",
				"../data/quoted.csv",
				"```",
			})
		end,
	},
	{
		name = "commands.run replaces only the selected fenced block in a mixed layout",
		run = function()
			local bufnr, lines = load_integration_buffer("mixed_fenced.md")
			local row, line = helpers.find_line(lines, "../data/people.tsv")
			set_visual_marks(bufnr, row, line, "../data/people.tsv")

			with_mock_ui({ "center", "head" }, { "", "1" }, function()
				commands.run()
			end)

			helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
				"Top `../data/quoted.csv`",
				"",
				"| name  | age | city  |",
				"| :---: | :-: | :---: |",
				"| Alice | 30  | Paris |",
				"",
				"Bottom ../data/people.csv",
			})
		end,
	},
	{
		name = "commands.run fails immediately on an invalid column expression",
		run = function()
			local bufnr, lines = load_integration_buffer("invalid_column.md")
			local line = lines[1]
			set_visual_marks(bufnr, 1, line, "../data/people.csv")

			local tracker = {
				input_calls = 0,
				select_calls = 0,
			}

			local notices = with_mock_notify(function()
				with_mock_ui(
					{ "left", "head" },
					{ "missing_column", "2" },
					function()
						commands.run()
					end,
					tracker
				)
			end)

			helpers.eq(tracker.input_calls, 1)
			helpers.eq(tracker.select_calls, 0)
			helpers.eq(
				notices,
				{ "Selected column not found: missing_column" }
			)
		end,
	},
	{
		name = "commands.run rejects ambiguous headers before prompting",
		run = function()
			local bufnr, lines =
				load_integration_buffer("ambiguous_header.md")
			local line = lines[1]
			set_visual_marks(bufnr, 1, line, "../data/ambiguous.csv")

			local tracker = {
				input_calls = 0,
				select_calls = 0,
			}

			local notices = with_mock_notify(function()
				with_mock_ui({}, {}, function()
					commands.run()
				end, tracker)
			end)

			helpers.eq(tracker.input_calls, 0)
			helpers.eq(tracker.select_calls, 0)
			helpers.match(notices[1], "header")
			helpers.match(
				notices[1],
				"Please fix the source file and try again."
			)
		end,
	},
	{
		name = "commands.run rejects malformed body rows under a valid header schema",
		run = function()
			local bufnr, lines = load_integration_buffer("malformed_body.md")
			local line = lines[1]
			set_visual_marks(bufnr, 1, line, "../data/malformed_body.tsv")

			local notices = with_mock_notify(function()
				with_mock_ui({ "left", "head" }, { "", "2" }, function()
					commands.run()
				end)
			end)

			helpers.match(notices[1], "Failed to parse TSV")
			helpers.match(notices[1], "Expected 3 columns but found 2")
		end,
	},
}
