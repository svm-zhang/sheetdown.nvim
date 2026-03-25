local helpers = require("tests.helpers")
local markdown_table = require("sheetdown.table")

return {
  {
    name = "table.render builds a Markdown table with alignment",
    run = function()
      local lines = markdown_table.render({
        headers = { "name", "age", "city" },
        rows = {
          { "Alice", "30", "Paris" },
          { "Bob", "41", "Berlin" },
        },
        column_indices = { 1, 3 },
        alignment = "left",
      })

      helpers.eq(lines, {
        "| name  | city   |",
        "| :---- | :----- |",
        "| Alice | Paris  |",
        "| Bob   | Berlin |",
      })
    end,
  },
}
