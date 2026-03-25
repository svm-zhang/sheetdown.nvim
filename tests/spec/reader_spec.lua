local helpers = require("tests.helpers")
local reader = require("sheetdown.reader")

local root = "/Users/simo/work/bio/code/sheetdown"

return {
  {
    name = "reader.parse_line supports quoted commas and escaped quotes",
    run = function()
      local fields = assert(reader.parse_line('Bob,"He said ""hi""",Berlin', ","))
      helpers.eq(fields, { "Bob", 'He said "hi"', "Berlin" })
    end,
  },
  {
    name = "reader.parse_range parses inclusive ranges",
    run = function()
      local range = assert(reader.parse_range("2:5"))
      helpers.eq(range, {
        mode = "range",
        start = 2,
        finish = 5,
      })
    end,
  },
  {
    name = "reader.read_selection supports head slices",
    run = function()
      local rows = assert(reader.read_selection(
        root .. "/fixtures/data/people.csv",
        ",",
        { mode = "head", count = 2 },
        3
      ))

      helpers.eq(rows, {
        { "Alice", "30", "Paris" },
        { "Bob", "41", "Berlin" },
      })
    end,
  },
  {
    name = "reader.read_selection supports tail slices",
    run = function()
      local rows = assert(reader.read_selection(
        root .. "/fixtures/data/people.csv",
        ",",
        { mode = "tail", count = 2 },
        3
      ))

      helpers.eq(rows, {
        { "Bob", "41", "Berlin" },
        { "Cara", "28", "Seoul" },
      })
    end,
  },
}
