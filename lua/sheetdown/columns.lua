local M = {}

-- Validate the header row once up front so later column parsing can assume:
-- - no empty names
-- - no duplicate names
-- This keeps the prompt parser focused on names vs. numeric indexes instead of
-- repeating header-shape checks in multiple places.
local function validate_headers(headers)
	local map = {}

	for index, header in ipairs(headers) do
		if header == "" then
			return nil, "Malformed header: empty column name."
		end

		if map[header] then
			return nil,
				("Malformed header: duplicate column name '%s'."):format(
					header
				)
		end

		map[header] = index
	end

	return map
end

-- "Simple" headers are safe to show directly in the default prompt expression.
--
-- Examples:
-- - "name"       -> simple
-- - "full name"  -> simple
-- - " name"      -> not simple, trimming would change the meaning
-- - "last,name"  -> not simple, commas collide with the prompt syntax
--
-- If any header is not simple, we fall back to numeric indexes in the default
-- prompt so the user sees an unambiguous expression like "1,2,3".
local function is_simple_header(header)
	return header ~= ""
		and header == vim.trim(header)
		and not header:find(",", 1, true)
end

---Validate header names and return a name-to-index map.
---@param headers string[]
---@return table|nil, string|nil
function M.validate_headers(headers)
	return validate_headers(headers)
end

---Build the default column-selection expression shown in the first prompt.
---
---Examples:
--- - headers = { "name", "email", "id" } -> "name,email,id"
--- - headers = { "last,name", "email" }  -> "1,2"
---
---Using names is friendlier when the names are safe to do so. Falling back to
---indexes keeps the default expression valid even when a header itself
---contains punctuation that would be ambiguous.
---@param headers string[]
---@return string
function M.default_expression(headers)
	local all_simple = true
	for _, header in ipairs(headers) do
		if not is_simple_header(header) then
			all_simple = false
			break
		end
	end

	-- Show column name in the prompt.
	if all_simple then
		return table.concat(headers, ",")
	end

	-- Fall back to index-based column-selection prompt.
	local indices = {}
	for index = 1, #headers do
		indices[#indices + 1] = tostring(index)
	end

	return table.concat(indices, ",")
end

---Parse the column prompt into ordered source-column indexes.
---
---The expression accepts either header names or 1-based numeric indexes, and
---the order in the prompt becomes the output column order.
---
---Examples:
--- - "name,email" -> columns named "name", then "email"
--- - "3,1"        -> third column first, then first column
--- - ""           -> keep all columns in source order
---@param expression string
---@param headers string[]
---@return table|nil, string|nil
function M.parse_expression(expression, headers)
	local header_map, header_error = validate_headers(headers)
	if not header_map then
		return nil, header_error
	end

	expression = vim.trim(expression or "")
	-- When no column selected, keep all in the source table.
	if expression == "" then
		local indices = {}
		for index = 1, #headers do
			indices[#indices + 1] = index
		end

		return {
			indices = indices,
			headers = vim.deepcopy(headers),
		}
	end

	local indices = {}
	local selected_headers = {}
	local seen = {}

	-- Parse the expression received from prompt and obtain selected column
	-- names and order.
	for token in expression:gmatch("[^,]+") do
		local piece = vim.trim(token)
		if piece ~= "" then
			local index = tonumber(piece)
			if index then
				if index % 1 ~= 0 then
					return nil,
						("Selected column index must be an integer: %s"):format(
							piece
						)
				end

				index = math.floor(index)
				if index < 1 or index > #headers then
					return nil,
						("Selected column index out of range: %s"):format(
							piece
						)
				end
			else
				index = header_map[piece]
				if not index then
					return nil, ("Selected column not found: %s"):format(piece)
				end
			end

			if seen[index] then
				return nil,
					("Selected column listed more than once: %s"):format(piece)
			end

			seen[index] = true
			indices[#indices + 1] = index
			selected_headers[#selected_headers + 1] = headers[index]
		end
	end

	if #indices == 0 then
		return nil, "No columns selected."
	end

	return {
		indices = indices,
		headers = selected_headers,
	}
end

return M
