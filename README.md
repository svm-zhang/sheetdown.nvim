# sheetdown.nvim

`sheetdown.nvim` turns a visually selected local CSV or TSV path in a Markdown
buffer into a Markdown table.

This plugin is still an ongoing effort. `v0.1.0` is the first narrow release,
focused on a simple Markdown-authoring workflow inside Neovim.

## Features

- Turn a visually selected local `.csv` or `.tsv` path into a Markdown table
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

## Usage

The `v0.1.0` workflow is intentionally small:

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

### Column prompt

The first prompt controls both column inclusion and output order.

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

The config surface is intentionally small in `v0.1.0`.

```lua
require("sheetdown").setup({
  default_alignment = "left",
  default_rows = {
    mode = "head",
    count = 5,
  },
})
```

Supported options:

- `default_alignment`: `"left"`, `"center"`, or `"right"`
- `default_rows.mode`: `"head"`, `"tail"`, or `"range"`
- `default_rows.count`: default row count for `head` and `tail`
