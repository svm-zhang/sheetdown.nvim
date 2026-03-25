if vim.g.loaded_sheetdown then
  return
end

vim.g.loaded_sheetdown = true

-- Keep the bootstrap file narrow: it only registers the public user command and
-- delegates real work to the Lua module.
vim.api.nvim_create_user_command("TableFromFile", function()
  require("sheetdown").table_from_file()
end, {
  desc = "Insert a Markdown table from a selected CSV or TSV path",
  range = true,
})
