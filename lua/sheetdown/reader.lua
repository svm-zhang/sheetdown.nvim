local M = {}

local function normalize_line(line)
  return (line or ""):gsub("\r$", "")
end

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

local function csv_name(delimiter)
  if delimiter == "\t" then
    return "TSV"
  end

  return "CSV"
end

---Parse a single CSV or TSV record without embedded newlines.
---
---Examples:
--- - 'Ada,42' with ',' -> { "Ada", "42" }
--- - '"Ada, Lovelace",42' with ',' -> { "Ada, Lovelace", "42" }
--- - '"say ""hi"""' with ',' -> { 'say "hi"' }
---
---This parser is intentionally narrow for v0.1.0:
--- - quoted delimiters are supported
--- - escaped quotes via `""` are supported
--- - embedded newlines inside quoted fields are not supported
---@param line string
---@param delimiter string
---@return string[]|nil, string|nil
function M.parse_line(line, delimiter)
  line = normalize_line(line)

  local fields = {}
  local current = {}
  local in_quotes = false
  local at_field_start = true
  local index = 1

  -- Walk the line one byte at a time so we can distinguish:
  -- - delimiter characters inside quotes
  -- - escaped quotes ("")
  -- - invalid quotes inside unquoted text
  while index <= #line do
    local char = line:sub(index, index)

    if in_quotes then
      if char == '"' then
        if line:sub(index + 1, index + 1) == '"' then
          current[#current + 1] = '"'
          index = index + 2
        else
          in_quotes = false
          index = index + 1
        end
      else
        current[#current + 1] = char
        index = index + 1
      end
    else
      if char == delimiter then
        fields[#fields + 1] = table.concat(current)
        current = {}
        at_field_start = true
        index = index + 1
      elseif char == '"' and at_field_start then
        in_quotes = true
        index = index + 1
      elseif char == '"' then
        return nil, "Unexpected quote inside an unquoted field."
      else
        current[#current + 1] = char
        at_field_start = false
        index = index + 1
      end
    end
  end

  if in_quotes then
    return nil, "Unclosed quoted field."
  end

  fields[#fields + 1] = table.concat(current)
  return fields
end

---Parse a row range in `start:end` form.
---
---The range counts data rows only. The header row is not part of this index.
---For example, `1:5` means "first through fifth data rows after the header".
---@param expression string
---@return table|nil, string|nil
function M.parse_range(expression)
  expression = vim.trim(expression or "")
  local start_text, finish_text = expression:match("^(%d+)%s*:%s*(%d+)$")
  if not start_text then
    return nil, "Invalid range. Use start:end, for example 1:5."
  end

  local start_index = tonumber(start_text)
  local finish_index = tonumber(finish_text)
  if start_index < 1 or finish_index < start_index then
    return nil, "Invalid range. The start must be at least 1 and the end must be greater than or equal to the start."
  end

  return {
    mode = "range",
    start = start_index,
    finish = finish_index,
  }
end

---Read and validate the first non-blank row as the header.
---
---We trim header cells here because users often write headers such as
---`name, email`, and the rest of the plugin wants stable header names without
--- leading or trailing whitespace.
---@param path string
---@param delimiter string
---@return string[]|nil, string|nil
function M.read_headers(path, delimiter)
  local handle, open_error = io.open(path, "r")
  if not handle then
    return nil, open_error
  end

  local line_number = 0
  local header_line

  for raw_line in handle:lines() do
    line_number = line_number + 1
    raw_line = normalize_line(raw_line)
    if not is_blank(raw_line) then
      header_line = raw_line
      break
    end
  end

  handle:close()

  if not header_line then
    return nil, "The file is empty."
  end

  local headers, parse_error = M.parse_line(header_line, delimiter)
  if not headers then
    return nil, ("Malformed header at line %d: %s"):format(line_number, parse_error)
  end

  local seen = {}
  for index, header in ipairs(headers) do
    headers[index] = vim.trim(header)
    if headers[index] == "" then
      return nil, "Malformed header: empty column name."
    end

    if seen[headers[index]] then
      return nil, ("Malformed header: duplicate column name '%s'."):format(headers[index])
    end

    seen[headers[index]] = true
  end

  return headers
end

---Read only the requested slice of data rows after the header.
---
---Mode behavior:
--- - `head`: stop as soon as enough rows are collected
--- - `tail`: keep only the last N rows seen so far
--- - `range`: collect rows whose 1-based data-row index is within start..finish
---
---Each parsed row must match the header width. That gives clearer errors for
--- malformed body rows such as a stray delimiter or a missing column.
---@param path string
---@param delimiter string
---@param row_selection table
---@param expected_columns integer
---@return string[][]|nil, string|nil
function M.read_selection(path, delimiter, row_selection, expected_columns)
  local handle, open_error = io.open(path, "r")
  if not handle then
    return nil, open_error
  end

  local rows = {}
  local header_seen = false
  local line_number = 0
  local data_row_index = 0

  for raw_line in handle:lines() do
    line_number = line_number + 1
    raw_line = normalize_line(raw_line)

    if not is_blank(raw_line) then
      if not header_seen then
        header_seen = true
      else
        local fields, parse_error = M.parse_line(raw_line, delimiter)
        if not fields then
          handle:close()
          return nil, ("Failed to parse %s at line %d in %s. %s"):format(
            csv_name(delimiter),
            line_number,
            path,
            parse_error
          )
        end

        if #fields ~= expected_columns then
          handle:close()
          return nil, ("Failed to parse %s at line %d in %s. Expected %d columns but found %d."):format(
            csv_name(delimiter),
            line_number,
            path,
            expected_columns,
            #fields
          )
        end

        data_row_index = data_row_index + 1

        if row_selection.mode == "head" then
          if data_row_index <= row_selection.count then
            rows[#rows + 1] = fields
          end

          if data_row_index >= row_selection.count then
            break
          end
        elseif row_selection.mode == "tail" then
          if #rows == row_selection.count then
            table.remove(rows, 1)
          end
          rows[#rows + 1] = fields
        elseif row_selection.mode == "range" then
          if data_row_index >= row_selection.start and data_row_index <= row_selection.finish then
            rows[#rows + 1] = fields
          end

          if data_row_index > row_selection.finish then
            break
          end
        else
          handle:close()
          return nil, ("Unsupported row mode: %s"):format(tostring(row_selection.mode))
        end
      end
    end
  end

  handle:close()
  return rows
end

return M
