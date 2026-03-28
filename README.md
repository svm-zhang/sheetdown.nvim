# sheetdown.nvim

`sheetdown.nvim` turns a visually selected local file containing CSV or TSV
data in a Markdown buffer into a Markdown table.

This plugin is still an ongoing effort.

## Features

- Turn a visually selected local file containing CSV or TSV data into a
  Markdown table
- Detect CSV or TSV data from file content instead of requiring a specific
  filename extension
- Use an optional enhanced `snacks.nvim` UI for searchable column selection and
  merged table options
- Fall back to the original `vim.ui.input()` / `vim.ui.select()` flow when the
  enhanced backend is unavailable
- Insert below the containing paragraph for plain text and inline code paths
- Replace the entire fenced code block for fenced path selections
- Select columns by name or index, with input order controlling output order
- Support `head N`, `tail N`, and `start:end` row modes
- Support left, center, and right alignment

## Installation

### lazy.nvim

```lua
{
  "svm-zhang/sheetdown.nvim",
  cmd = { "TableFromFile" },
  ft = { "markdown" },
  config = function()
    require("sheetdown").setup()
  end,
}
```

### Optional enhanced UI with snacks.nvim

If `snacks.nvim` is installed, `sheetdown.nvim` will use the richer `v0.2.0`
UI automatically by default.

```lua
{
  "svm-zhang/sheetdown.nvim",
  cmd = { "TableFromFile" },
  ft = { "markdown" },
  dependencies = {
    {
      "folke/snacks.nvim",
      opts = {
        input = { enabled = true },
        picker = { enabled = true },
      },
    },
  },
  config = function()
    require("sheetdown").setup()
  end,
}
```

If `snacks.nvim` is not installed, `sheetdown.nvim` keeps using the previous
prompt flow through `vim.ui.input()` and `vim.ui.select()`.

## Usage

The `sheetdown.nvim` workflow is:

1. Write a local path in Markdown
2. Visually select the path
3. Run `:TableFromFile` or a visual mapping
4. Choose columns, alignment, and rows
5. Insert the generated table

Run the command from visual mode:

```vim
:TableFromFile
```

If you want a visual mapping, use the normal visual command-line form:

```vim
:xnoremap <leader>mt :<C-U>TableFromFile<CR>
```

Do not use a visual `<Cmd>...` mapping here. This command depends on the
current visual selection marks.

### Enhanced UI

When `snacks.nvim` is available, `sheetdown.nvim` opens a single picker-based
screen that keeps search, column selection, current options, and key hints
visible together:

- searchable column selection
- visible alignment choices
- visible row-render choices
- selected-column summary

Columns start unchecked in the enhanced UI. The order you toggle them on
becomes the output column order.

In this enhanced UI:

- the search field opens focused with a placeholder
- type immediately to filter columns
- `<C-j>/<Down>` moves from the search input into the list
- `<i>` returns from the list to the search input
- `<Tab>` toggles the current column
- `<c>` selects all columns
- `<u>` clears all columns
- `<a>` cycles alignment
- `<d>` sets either `N` or `start:end`
- `<m>` cycles `head` / `tail` when the current row detail is numeric
- `<CR>` confirms
- `<Esc>` closes the UI

### Fallback column prompt

Without `snacks.nvim`, the first prompt controls both column inclusion and
output order.

Examples:

```text
name,email,id
1,3,2
```

Rules:

- Tokens are comma-separated
- Each token may be a header name or a 1-based numeric index
- Token order becomes output order
- An empty input keeps all columns in source order

### Row modes

Supported row selection modes:

- `head N`
- `tail N`
- `start:end`

## Example

Before:

```md
Quarterly results:
`./results.csv`
```

After:

```md
Quarterly results:
`./results.csv`

| quarter | revenue | margin |
| :------ | :------ | :----- |
| Q1      | 120     | 34%    |
| Q2      | 128     | 36%    |
```

## Configuration

The config surface is intentionally small.

```lua
require("sheetdown").setup({
  default_alignment = "left",
  default_rows = {
    mode = "head",
    count = 5,
  },
  ui = {
    backend = "auto",
  },
})
```

Supported options:

- `default_alignment`: `"left"`, `"center"`, or `"right"`
- `default_rows.mode`: `"head"`, `"tail"`, or `"range"`
- `default_rows.count`: default row count for `head` and `tail`
- `ui.backend`:
  - `"auto"`: use `snacks.nvim` when available, otherwise fall back to `vim.ui.*`
  - `"snacks"`: require the enhanced backend
  - `"vim_ui"`: force the original prompt flow
