local helpers = require("tests.helpers")
local selection = require("sheetdown.selection")

local function create_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function set_single_line_marks(bufnr, row, line, needle)
  local start_col = assert(line:find(needle, 1, true)) - 1
  local end_col = start_col + #needle - 1
  vim.api.nvim_buf_set_mark(bufnr, "<", row, start_col, {})
  vim.api.nvim_buf_set_mark(bufnr, ">", row, end_col, {})
end

local function set_range_marks(bufnr, start_row, start_col, end_row, end_col)
  vim.api.nvim_buf_set_mark(bufnr, "<", start_row, start_col, {})
  vim.api.nvim_buf_set_mark(bufnr, ">", end_row, end_col, {})
end

return {
  {
    name = "selection.get extracts an inline-code path and inserts below the paragraph",
    run = function()
      local line = "Inline `../data/quoted.csv`"
      local bufnr = create_buffer({
        line,
        "",
        "Next paragraph.",
      })
      set_single_line_marks(bufnr, 1, line, "../data/quoted.csv")

      local info = assert(selection.get(bufnr))

      helpers.eq(info.candidate_path, "../data/quoted.csv")
      helpers.eq(info.target, {
        kind = "insert_after_row",
        row = 1,
      })
    end,
  },
  {
    name = "selection.get treats a full fenced-block selection as a replace target",
    run = function()
      local lines = {
        "```text",
        "../data/people.tsv",
        "```",
        "",
        "After block.",
      }
      local bufnr = create_buffer(lines)
      set_range_marks(bufnr, 1, 0, 3, #lines[3] - 1)

      local info = assert(selection.get(bufnr))

      helpers.eq(info.candidate_path, "../data/people.tsv")
      helpers.eq(info.target, {
        kind = "replace_range",
        start_row = 1,
        end_row = 3,
      })
    end,
  },
  {
    name = "selection.get keeps an inline path between fenced blocks as an insert target",
    run = function()
      local line = "Inline `../data/quoted.csv`"
      local bufnr = create_buffer({
        "```text",
        "../data/people.tsv",
        "```",
        "",
        line,
        "",
        "```text",
        "../data/people.csv",
        "```",
      })
      set_single_line_marks(bufnr, 5, line, "../data/quoted.csv")

      local info = assert(selection.get(bufnr))

      helpers.eq(info.candidate_path, "../data/quoted.csv")
      helpers.eq(info.target, {
        kind = "insert_after_row",
        row = 5,
      })
    end,
  },
  {
    name = "selection.get keeps a plain-text path between fenced blocks as an insert target",
    run = function()
      local line = "Reference: ../data/people.csv"
      local bufnr = create_buffer({
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
      set_single_line_marks(bufnr, 5, line, "../data/people.csv")

      local info = assert(selection.get(bufnr))

      helpers.eq(info.candidate_path, "../data/people.csv")
      helpers.eq(info.target, {
        kind = "insert_after_row",
        row = 5,
      })
    end,
  },
  {
    name = "selection.get rejects selections that resolve to multiple paths",
    run = function()
      local lines = {
        "../data/people.csv",
        "../data/quoted.csv",
      }
      local bufnr = create_buffer(lines)
      set_range_marks(bufnr, 1, 0, 2, #lines[2] - 1)

      local info, err = selection.get(bufnr)

      helpers.eq(info, nil)
      helpers.eq(err, "Selection must resolve to a single file path.")
    end,
  },
  {
    name = "selection.apply inserts a table below the target row with spacing",
    run = function()
      local bufnr = create_buffer({
        "Path: ../data/people.csv",
        "",
        "Next paragraph.",
      })

      selection.apply({
        bufnr = bufnr,
        target = {
          kind = "insert_after_row",
          row = 1,
        },
      }, {
        "| name |",
        "| :--- |",
      })

      helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
        "Path: ../data/people.csv",
        "",
        "| name |",
        "| :--- |",
        "",
        "Next paragraph.",
      })
    end,
  },
  {
    name = "selection.apply replaces the full target range",
    run = function()
      local bufnr = create_buffer({
        "Before",
        "```text",
        "../data/people.tsv",
        "```",
        "After",
      })

      selection.apply({
        bufnr = bufnr,
        target = {
          kind = "replace_range",
          start_row = 2,
          end_row = 4,
        },
      }, {
        "| name |",
        "| :--- |",
      })

      helpers.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), {
        "Before",
        "| name |",
        "| :--- |",
        "After",
      })
    end,
  },
}
