local commands = require("sheetdown.commands")
local helpers = require("tests.helpers")

local root = "/Users/simo/work/bio/code/sheetdown"

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
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_name(bufnr, root .. "/fixtures/manual/integration-plain.md")

      local line = "The data lives at ../data/people.csv."
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        line,
        "",
        "Next paragraph.",
      })
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
    name = "commands.run inserts below for the sample inline path between fenced blocks",
    run = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_name(bufnr, root .. "/fixtures/manual/integration-sample-inline.md")
      vim.api.nvim_buf_set_lines(
        bufnr,
        0,
        -1,
        false,
        vim.fn.readfile(root .. "/fixtures/manual/sample.md")
      )

      local line = vim.api.nvim_buf_get_lines(bufnr, 31, 32, false)[1]
      set_visual_marks(bufnr, 32, line, "../data/ambiguous.case_2.csv")

      with_mock_ui({ "left", "head" }, { "", "2" }, function()
        commands.run()
      end)

      helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 29, 40, false), {
        "## Ambiguous case 2",
        "",
        "This reveals the current implementation problem: `../data/ambiguous.case_2.csv`",
        "",
        "| name  age | city   |",
        "| :-------- | :----- |",
        "| Alice 30  | Paris  |",
        "| Bob 41,   | Berlin |",
        "",
        "## sheetdown.test.csv",
        "",
      })
    end,
  },
  {
    name = "commands.run replaces a fenced code block with a table",
    run = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_name(bufnr, root .. "/fixtures/manual/integration-fenced.md")

      local line = "../data/people.tsv"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```text",
        line,
        "```",
        "",
        "After block.",
      })
      set_visual_marks(bufnr, 2, line, "../data/people.tsv")

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
    name = "commands.run inserts below for a plain-text path between fenced blocks",
    run = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_name(bufnr, root .. "/fixtures/manual/integration-plain-between-fences.md")

      local line = "Reference: ../data/people.csv"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```text",
        "../data/people.tsv",
        "```",
        "",
        line,
        "",
        "```text",
        "../data/quoted.csv",
        "```",
      })
      set_visual_marks(bufnr, 5, line, "../data/people.csv")

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
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_name(bufnr, root .. "/fixtures/manual/integration-mixed-fenced.md")

      local line = "../data/people.tsv"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "Top `../data/quoted.csv`",
        "",
        "```text",
        line,
        "```",
        "",
        "Bottom ../data/people.csv",
      })
      set_visual_marks(bufnr, 4, line, "../data/people.tsv")

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
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_name(bufnr, root .. "/fixtures/manual/integration-invalid-column.md")

      local line = "../data/people.csv"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
      set_visual_marks(bufnr, 1, line, "../data/people.csv")

      local tracker = {
        input_calls = 0,
        select_calls = 0,
      }

      local notices = with_mock_notify(function()
        with_mock_ui({ "left", "head" }, { "missing_column", "2" }, function()
          commands.run()
        end, tracker)
      end)

      helpers.eq(tracker.input_calls, 1)
      helpers.eq(tracker.select_calls, 0)
      helpers.eq(notices, { "Selected column not found: missing_column" })
    end,
  },
  {
    name = "commands.run rejects ambiguous headers before prompting",
    run = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_name(bufnr, root .. "/fixtures/manual/integration-bad-header.md")

      local line = "../data/ambiguous.csv"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
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
      helpers.match(notices[1], "Please fix the source file and try again.")
    end,
  },
  {
    name = "commands.run rejects malformed body rows under a valid header schema",
    run = function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_name(bufnr, root .. "/fixtures/manual/integration-bad-body.md")

      local line = "../data/malformed_body.tsv"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
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
