local M = {}

-- Escape the minimum set of characters needed for safe Markdown table cells.
-- Newlines are flattened because the renderer produces one physical line per
-- Markdown table row in v0.1.0.
local function escape_cell(value)
	value = tostring(value or "")
	value = value:gsub("\r", "")
	value = value:gsub("\n", " ")
	value = value:gsub("|", "\\|")
	return value
end

local function alignment_marker(alignment, width)
	width = math.max(width, 3)
	local dashes = string.rep("-", width)

	if alignment == "left" then
		return ":" .. dashes:sub(2)
	end

	if alignment == "center" then
		if width == 3 then
			return ":-:"
		end
		return ":" .. string.rep("-", width - 2) .. ":"
	end

	return dashes:sub(1, width - 1) .. ":"
end

local function pad_right(text, width)
	return text .. string.rep(" ", width - #text)
end

-- Rows are padded to the widest cell in each output column so the Markdown is
-- easy to read in source form, not only after rendering.
local function format_row(cells, widths)
	local padded = {}
	for index, cell in ipairs(cells) do
		padded[#padded + 1] = " " .. pad_right(cell, widths[index]) .. " "
	end
	return "|" .. table.concat(padded, "|") .. "|"
end

---Render a Markdown table from the selected columns and rows.
---
---`column_indices` lets the caller both filter and reorder columns without
---rewriting the row data structure beforehand.
---@param args table
---@return string[]
function M.render(args)
	local headers = args.headers
	local rows = args.rows
	local indices = args.column_indices
	local alignment = args.alignment or "left"

	local rendered_headers = {}
	local widths = {}

	for _, index in ipairs(indices) do
		local header = escape_cell(headers[index])
		rendered_headers[#rendered_headers + 1] = header
		widths[#widths + 1] = math.max(#header, 3)
	end

	local rendered_rows = {}
	for _, row in ipairs(rows) do
		local rendered_row = {}
		for output_index, source_index in ipairs(indices) do
			local value = escape_cell(row[source_index])
			rendered_row[#rendered_row + 1] = value
			widths[output_index] = math.max(widths[output_index], #value, 3)
		end
		rendered_rows[#rendered_rows + 1] = rendered_row
	end

	local lines = {}
	lines[#lines + 1] = format_row(rendered_headers, widths)

	local alignment_cells = {}
	for index, width in ipairs(widths) do
		alignment_cells[#alignment_cells + 1] =
			alignment_marker(alignment, width)
	end
	lines[#lines + 1] = format_row(alignment_cells, widths)

	for _, row in ipairs(rendered_rows) do
		lines[#lines + 1] = format_row(row, widths)
	end

	return lines
end

return M
