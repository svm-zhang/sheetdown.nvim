local M = {}

-- v0.1.0 supports Unix-style absolute paths on macOS/Linux only.
local function is_absolute(path)
	return path:sub(1, 1) == "/"
end

---Resolve a visual-selected path relative to the current buffer.
---
---Resolution order:
--- - trim the selected text
--- - expand `~` and other Vim path expressions
--- - resolve relative paths from the current buffer's directory
--- - reject anything that is not a readable `.csv` or `.tsv` file
---@param raw_path string
---@param bufnr integer
---@return table|nil, string|nil
function M.resolve(raw_path, bufnr)
	raw_path = vim.trim(raw_path or "")
	if raw_path == "" then
		return nil, "Selected path is empty."
	end

	local expanded = vim.fn.expand(raw_path)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local base_dir

	if bufname == "" then
		base_dir = vim.fn.getcwd()
	else
		base_dir = vim.fn.fnamemodify(bufname, ":p:h")
	end

	local candidate = expanded
	if not is_absolute(candidate) then
		candidate = base_dir .. "/" .. candidate
	end

	local absolute = vim.fn.fnamemodify(candidate, ":p")
	if vim.fn.filereadable(absolute) ~= 1 then
		return nil, ("File not found or unreadable: %s"):format(absolute)
	end

	-- Allow for other suffix as long as the data table itself is defined as
	-- a CSV or TSV in the future. Extension itself should not be authoritative.
	local extension = absolute:match("%.([^.]+)$")
	extension = extension and extension:lower() or ""
	if extension ~= "csv" and extension ~= "tsv" then
		return nil,
			("Unsupported file type for %s. Use a .csv or .tsv file."):format(
				absolute
			)
	end

	return {
		raw = raw_path,
		absolute = absolute,
		extension = extension,
		base_dir = base_dir,
	}
end

return M
