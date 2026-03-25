local reader = require("sheetdown.reader")

local M = {}

local function is_blank(line)
	return line:match("^%s*$") ~= nil
end

local function first_nonblank_line(path)
	local handle, open_error = io.open(path, "r")
	if not handle then
		return nil, open_error
	end

	for raw_line in handle:lines() do
		raw_line = raw_line:gsub("\r$", "")
		if not is_blank(raw_line) then
			handle:close()
			return raw_line
		end
	end

	handle:close()
	return nil, "The file is empty."
end

local function header_candidate(header_line, delimiter, format)
	local fields = reader.parse_line(header_line, delimiter)
	if not fields or #fields < 2 then
		return nil
	end

	return {
		delimiter = delimiter,
		format = format,
		width = #fields,
		headers = fields,
	}
end

---Detect whether the header is comma- or tab-delimited.
---
---This is intentionally header-first in v0.1.0. Do not inspect body rows to
--- "fix" the delimiter choice later. The first non-blank line defines the file
--- schema, and later malformed rows are handled by the reader as parse errors.
---@param lines string[]
---@return table|nil, string|nil
function M.detect_from_lines(lines)
	local header_line

	for _, line in ipairs(lines) do
		if not is_blank(line) then
			header_line = line
			break
		end
	end

	if not header_line then
		return nil, "The file is empty."
	end

	local csv_candidate = header_candidate(header_line, ",", "csv")
	local tsv_candidate = header_candidate(header_line, "\t", "tsv")

	if csv_candidate and not tsv_candidate then
		return csv_candidate
	end

	if tsv_candidate and not csv_candidate then
		return tsv_candidate
	end

	-- Ambiguous case: both command and tab present.
	if csv_candidate and tsv_candidate then
		return nil,
			"Could not detect a supported delimiter from the header. The header is ambiguous between comma and tab."
	end

	return nil,
		"Could not detect a supported delimiter from the header. Use comma or tab in the header row."
end

---Detect the delimiter from the first non-blank line in the file.
---@param path string
---@return table|nil, string|nil
function M.detect_file(path)
	local header_line, read_error = first_nonblank_line(path)
	if not header_line then
		return nil, read_error
	end

	return M.detect_from_lines({ header_line })
end

return M
