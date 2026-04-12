# Local Testing

This guide is for manual testing from a local checkout before making permanent
changes to your Neovim config.

## Fixture file

Use `fixtures/manual/sample.md` for quick manual testing.

That file is important because it already contains relative fixture paths such
as `../data/people.csv`, `../data/people.tsv`, and `../data/people.data`. Open
the file in place from the repository checkout. If you copy it elsewhere, those
relative paths will no longer resolve correctly.

## One-off manual test session

Replace `<sheetdown-root>` below with the path to your local checkout.

1. Open the sample file with your normal Neovim config:

   ```bash
   nvim <sheetdown-root>/fixtures/manual/sample.md
   ```

2. In that session, add the checkout to `runtimepath`:

   ```vim
   :set runtimepath+=<sheetdown-root>
   ```

3. Load the plugin command for the current session only:

   ```vim
   :runtime plugin/sheetdown.lua
   ```

4. Confirm the command exists:

   ```vim
   :echo exists(':TableFromFile')
   ```

   Expected result: `2`

If you already installed `sheetdown.nvim` through your plugin manager, you can
skip the `runtimepath` and `:runtime` steps and go straight to the test cases
below.

### Optional snacks.nvim-backed UI

If your Neovim config already installs `snacks.nvim` with its `picker` and
`input` modules enabled, `sheetdown.nvim` will use the richer
`snacks.nvim`-backed UI.

If not, the plugin falls back to the previous `vim.ui.*` prompt flow.

That means the same manual test cases below are still valid in both modes. The
difference is only the prompt UI:

- `snacks.nvim` mode: one picker-based screen
- fallback mode: the original sequence of input/select prompts

In `snacks.nvim` mode, the picker opens with search focused and a placeholder.
Type immediately to filter columns, use `<C-j>` as the primary way to move
into the list, use `<Down>` as a secondary choice, and use `i` to return to
search.

Columns start unchecked in `snacks.nvim` mode. The order you toggle them on
becomes the output column order. `c` selects all columns in source order, `u`
clears the full selection, and `r` resets the picker state back to configured
defaults.

With `backend="auto"` (enabling `snacks.nvim`), repeated `:TableFromFile`
is lifecycle-aware:

- while the UI is open, running `:TableFromFile` again hides it
- from normal mode, running `:TableFromFile` again restores the hidden session
- `<Esc>` closes and discards the session instead of hiding it

## Test cases

All test cases below assume you opened `fixtures/manual/sample.md` from this
repository checkout.

### Plain text path

1. Move to the `../data/people.csv` line.
2. Enter visual mode and select only the path text.
3. Run:

   ```vim
   :TableFromFile
   ```

4. If the `snacks.nvim`-backed UI is active:
   - type to filter if helpful
   - use `<C-j>` to move into the list
   - use `<Tab>` on `name`, then on `city`, so the output order is `name, city`
   - use `a` until alignment shows `left`
   - use `d`, enter `2`, and confirm the detail prompt
   - if needed, use `m` until row mode shows `head`
   - confirm the picker
5. If the fallback UI is active:
   - accept or edit the column prompt
   - choose an alignment
   - choose `head`
   - enter `2`
6. Confirm that a Markdown table is inserted below that paragraph.

### snacks.nvim-backed UI minimize and resume

1. Return to `../data/people.csv`.
2. Select the path and run `:TableFromFile`.
3. In `snacks.nvim` mode only, toggle a couple of columns and change one option.
4. Run `:TableFromFile` again while the picker is still open.
5. Confirm that the picker hides without inserting anything.
6. Return to normal mode in the Markdown buffer and run `:TableFromFile` again.
7. Confirm that the same session reopens with the same selected columns and
   render options.
8. Press `<Esc>`, then run `:TableFromFile` again from normal mode.
9. Confirm that the old session does not resume after `<Esc>` and that a fresh
   visual selection is required.

### Inline code path

1. Move to the `` `../data/quoted.csv` `` line.
2. Select the path text. Selecting the surrounding backticks also works.
3. Run `:TableFromFile`.
4. In `snacks.nvim` mode, use `<Tab>` on `name`, then `quote`, before confirming.
5. In fallback mode, try columns like `name,quote`.
6. Confirm that a table is inserted below the paragraph and the original inline
   code stays unchanged.

### Fenced code block path

1. Move to the `../data/people.tsv` line inside the fenced block.
2. Select only the path text.
3. Run `:TableFromFile`.
4. In `snacks.nvim` mode, press `c` to select all columns, use `d` to set `1`, keep
   `head` if needed with `m`, then confirm.
5. In fallback mode, choose `head` and enter `1`.
6. Confirm that the entire fenced block is replaced with a Markdown table.

### Heading-adjacent fenced block

1. Move to the `Heading-adjacent fenced block` section.
2. Select the `../data/people.tsv` path inside that fenced block.
3. Run `:TableFromFile`.
4. In `snacks.nvim` mode, press `c` to select all columns, use `d` to set `1`, keep
   `head` if needed with `m`, and confirm.
5. In fallback mode, choose `head` and enter `1`.
6. Confirm that the fenced block is replaced and that a blank line is inserted
   between the section heading and the replacement table.

### Ambiguous header rejection

1. Move to the `` `../data/ambiguous.csv` `` line.
2. Select the path.
3. Run `:TableFromFile`.
4. Confirm that the command fails before any prompt with an ambiguous-header
   error.

### Malformed body rejection

1. Move to the `../data/malformed_body.tsv` fenced block.
2. Select the path.
3. Run `:TableFromFile`.
4. Complete the UI on a normal path:
   - `snacks.nvim` mode: confirm the picker screen
   - fallback mode: complete the original prompt chain
5. Confirm that the command later fails with a row-parse error for the TSV
   body.

### Invalid column input

1. Return to `../data/people.csv`.
2. Select the path.
3. Run `:TableFromFile`.
4. In fallback mode, enter `missing_column` at the first prompt.
5. In `snacks.nvim` mode, this case no longer applies directly because columns are
   selected from the picker instead of typed by name.
6. Confirm that fallback mode still fails immediately after the first prompt
   instead of
   continuing to alignment or row prompts.

### Nonstandard extension

1. Move to the `` `../data/people.data` `` line.
2. Select the path.
3. Run `:TableFromFile`.
4. In `snacks.nvim` mode, press `c` to select all columns, use `d` to set `1`, keep
   `head` if needed with `m`, then confirm.
5. In fallback mode, choose `head` and enter `1`.
6. Confirm that the command succeeds even though the file does not end in
   `.csv` or `.tsv`.

## Optional temporary mapping

If you want a mapping only for the current buffer and current session:

```vim
:xnoremap <buffer> <leader>st :<C-U>TableFromFile<CR>
```

This does not change your config on disk.

Use the normal visual command-line form shown above. Do not use a visual
`<Cmd>...` mapping here, because this command depends on the current visual
selection marks.

## Headless test suite

From the repository root:

```bash
nvim --headless -u tests/minimal_init.lua -i NONE -c "lua require('tests.run')" -c "qall!"
```
