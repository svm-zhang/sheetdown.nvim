local config = require("sheetdown.config")
local helpers = require("tests.helpers")
local selection = require("sheetdown.selection")
local ui_helpers = require("tests.ui_helpers")

local root = helpers.repo_root()
local buffer_counter = 0

local function create_markdown_buffer(lines)
	buffer_counter = buffer_counter + 1
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(bufnr)
	vim.api.nvim_buf_set_name(
		bufnr,
		("%s/fixtures/integration/lifecycle.%d.test.md"):format(
			root,
			buffer_counter
		)
	)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	return bufnr
end

local function set_visual_marks(bufnr, row, line, needle)
	local start_col = assert(line:find(needle, 1, true))
	local finish_col = start_col + #needle - 2
	vim.api.nvim_buf_set_mark(bufnr, "<", row, start_col - 1, {})
	vim.api.nvim_buf_set_mark(bufnr, ">", row, finish_col, {})
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

local function with_mock_enhanced_ui(opts, fn)
	local mock_ui
	local registry
	local state = {
		active = nil,
		callbacks = {},
	}

	function state.cancel(session)
		state.active = nil
		assert(session:cancel())

		local on_done = state.callbacks[session]
		if on_done then
			on_done(nil, nil)
		end
	end

	mock_ui = {
		resolve_backend = function()
			return "snacks"
		end,
		active_session = function()
			return state.active
		end,
		hide_session = function(session)
			local ok, err = session:hide()
			if not ok then
				return nil, err
			end

			state.active = nil
			return true
		end,
		open_session = function(session, _, on_done)
			local ok, err = session:activate()
			if not ok then
				on_done(nil, err)
				return nil, err
			end

			state.active = session
			state.callbacks[session] = on_done
			return { session = session }
		end,
	}

	config.setup(vim.tbl_deep_extend("force", {
		ui = { backend = "snacks" },
	}, opts or {}))

	ui_helpers.unload("sheetdown.commands")
	ui_helpers.unload("sheetdown.session_registry")

	local ok, err = xpcall(function()
		ui_helpers.with_module("sheetdown.ui", mock_ui, function()
			registry = require("sheetdown.session_registry")
			local commands = require("sheetdown.commands")
			fn(commands, registry, state)
		end)
	end, debug.traceback)

	if registry then
		registry.clear_all()
	end
	ui_helpers.unload("sheetdown.commands")
	ui_helpers.unload("sheetdown.session_registry")
	config.setup({})

	if not ok then
		error(err)
	end
end

return {
	{
		name = "commands.run hides and restores an enhanced session on repeated command runs",
		run = function()
			local absolute = root .. "/fixtures/data/people.csv"

			with_mock_enhanced_ui({}, function(commands, registry, state)
				local lines = { "../data/people.csv" }
				local bufnr = create_markdown_buffer(lines)
				set_visual_marks(bufnr, 1, lines[1], "../data/people.csv")

				local notices = with_mock_notify(function()
					commands.run()

					local entry = registry.get(bufnr)
					helpers.ok(entry)
					helpers.eq(state.active, entry.session)
					helpers.eq(selection.has_visual_marks(bufnr), false)

					commands.run()
					helpers.eq(state.active, nil)
					helpers.eq(entry.session:status_name(), "hidden")

					commands.run()
					helpers.eq(state.active, entry.session)
					helpers.eq(entry.session:status_name(), "open")
				end)

				helpers.eq(notices, {
					("Session hidden: %s (line 1). Run :TableFromFile again to resume."):format(
						absolute
					),
					("Resumed session: %s (line 1)"):format(absolute),
				})
			end)
		end,
	},
	{
		name = "commands.run discards a hidden session when a different path is selected",
		run = function()
			local first = root .. "/fixtures/data/people.csv"
			local second = root .. "/fixtures/data/quoted.csv"

			with_mock_enhanced_ui({}, function(commands, registry, state)
				local lines = {
					"../data/people.csv",
					"",
					"../data/quoted.csv",
				}
				local bufnr = create_markdown_buffer(lines)

				set_visual_marks(bufnr, 1, lines[1], "../data/people.csv")
				commands.run()

				local original = assert(registry.get(bufnr))
				with_mock_notify(function()
					commands.run()
				end)
				helpers.eq(original.session:status_name(), "hidden")

				set_visual_marks(bufnr, 3, lines[3], "../data/quoted.csv")
				local notices = with_mock_notify(function()
					commands.run()
				end)

				local replacement = assert(registry.get(bufnr))
				helpers.ok(replacement.session ~= original.session)
				helpers.eq(state.active, replacement.session)
				helpers.eq(replacement.resolved.absolute, second)

				helpers.eq(notices, {
					("Discarded hidden session: %s (line 1)"):format(first),
					("Opened new session: %s (line 3)"):format(second),
				})
			end)
		end,
	},
	{
		name = "commands.run discards a closed enhanced session instead of restoring it",
		run = function()
			local absolute = root .. "/fixtures/data/people.csv"

			with_mock_enhanced_ui({}, function(commands, registry, state)
				local lines = { "../data/people.csv" }
				local bufnr = create_markdown_buffer(lines)
				set_visual_marks(bufnr, 1, lines[1], "../data/people.csv")

				commands.run()

				local entry = assert(registry.get(bufnr))
				local discard_notices = with_mock_notify(function()
					state.cancel(entry.session)
				end)
				helpers.eq(registry.get(bufnr), nil)
				helpers.eq(discard_notices, {
					("Session closed: %s (line 1)"):format(absolute),
				})

				local notices = with_mock_notify(function()
					commands.run()
				end)

				helpers.eq(notices, {
					"Select a file path in visual mode before running :TableFromFile.",
				})
			end)
		end,
	},
	{
		name = "commands.run resumes the previous hidden session after a failed replacement attempt",
		run = function()
			local absolute = root .. "/fixtures/data/people.csv"

			with_mock_enhanced_ui({}, function(commands, registry, state)
				local lines = {
					"../data/people.csv",
					"",
					"../data/ambiguous.csv",
				}
				local bufnr = create_markdown_buffer(lines)

				set_visual_marks(bufnr, 1, lines[1], "../data/people.csv")
				commands.run()

				local original = assert(registry.get(bufnr))
				with_mock_notify(function()
					commands.run()
				end)
				helpers.eq(original.session:status_name(), "hidden")
				helpers.eq(state.active, nil)

				set_visual_marks(bufnr, 3, lines[3], "../data/ambiguous.csv")
				local error_notices = with_mock_notify(function()
					commands.run()
				end)

				helpers.match(error_notices[1], "Please fix the source file and try again.")
				helpers.eq(original.session:status_name(), "hidden")
				helpers.eq(selection.has_visual_marks(bufnr), false)

				local resume_notices = with_mock_notify(function()
					commands.run()
				end)

				helpers.eq(state.active, original.session)
				helpers.eq(original.session:status_name(), "open")
				helpers.eq(resume_notices, {
					("Resumed session: %s (line 1)"):format(absolute),
				})
			end)
		end,
	},
	{
		name = "commands.run suppresses informational lifecycle notices when notifications are disabled",
		run = function()
			with_mock_enhanced_ui({
				notifications = { enabled = false },
			}, function(commands, registry, state)
				local lines = { "../data/people.csv" }
				local bufnr = create_markdown_buffer(lines)
				set_visual_marks(bufnr, 1, lines[1], "../data/people.csv")

				local notices = with_mock_notify(function()
					commands.run()
					commands.run()
					commands.run()
				end)

				helpers.eq(notices, {})

				local entry = assert(registry.get(bufnr))
				state.cancel(entry.session)

				local error_notices = with_mock_notify(function()
					commands.run()
				end)

				helpers.eq(error_notices, {
					"Select a file path in visual mode before running :TableFromFile.",
				})
			end)
		end,
	},
}
