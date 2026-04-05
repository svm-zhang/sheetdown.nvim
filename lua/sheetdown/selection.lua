local M = {}
local anchor_namespace = vim.api.nvim_create_namespace("sheetdown.selection.anchor")

-- Visual marks can be placed one column past the line content. Clamp them so
-- later text extraction works against real buffer positions.
--
-- `nvim_buf_get_mark()` returns mark-like positions: 1-based rows and 0-based
-- columns. For a line like "abc", the character columns are 0, 1, and 2, and
-- the useful end-of-line boundary is 3.
--
-- Neovim may also report an end-of-line mark as `v:maxcol` (a large sentinel
-- value). Clamp turns that back into a real line-local column before
-- `nvim_buf_get_text()` is called.
local function clamp_col(bufnr, row, col)
	local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
		or ""
	return math.max(0, math.min(col, #line))
end

local function is_blank(line)
	return line == nil or line:match("^%s*$") ~= nil
end

-- Normalize visual mark order so every downstream helper can assume
-- start <= finish, even when the user selected backwards.
-- a and b are (row, col) tuples.
local function sort_marks(a, b)
	if a[1] < b[1] then
		return a, b
	end

	if a[1] > b[1] then
		return b, a
	end

	if a[2] <= b[2] then
		return a, b
	end

	return b, a
end

-- Make sure to get a sane selection range.
local function normalize_range(bufnr, raw_start, raw_finish)
	local start_mark, finish_mark = sort_marks(raw_start, raw_finish)
	return {
		start_row = start_mark[1],
		start_col = clamp_col(bufnr, start_mark[1], start_mark[2]),
		end_row = finish_mark[1],
		end_col = clamp_col(bufnr, finish_mark[1], finish_mark[2]),
	}
end

local function extmark_range(bufnr, extmark_id)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil, "Original selection buffer is no longer available."
	end

	local extmark = vim.api.nvim_buf_get_extmark_by_id(
		bufnr,
		anchor_namespace,
		extmark_id,
		{ details = true }
	)
	if not extmark or #extmark == 0 then
		return nil, "Original selection is no longer available."
	end

	local details = extmark[3] or {}
	if details.end_row == nil or details.end_col == nil then
		return nil, "Original selection is no longer available."
	end

	local end_col = math.max(extmark[2], details.end_col - 1)

	return {
		start_row = extmark[1] + 1,
		start_col = extmark[2],
		end_row = details.end_row + 1,
		end_col = end_col,
	}
end

-- Extract the text within the given normalized range.
local function extract_text(bufnr, range)
	local text = vim.api.nvim_buf_get_text(
		bufnr,
		range.start_row - 1,
		range.start_col,
		range.end_row - 1,
		range.end_col + 1,
		{}
	)

	return table.concat(text, "\n")
end

local function strip_wrappers(text)
	text = vim.trim(text)

	local first = text:sub(1, 1)
	local last = text:sub(-1)
	if
		(first == '"' or first == "'" or first == "`")
		and first == last
		and #text >= 2
	then
		return text:sub(2, -2)
	end

	return text
end

-- A visual selection may include Markdown wrappers around the path:
-- - plain text:   ../data/people.csv
-- - inline code:  `../data/people.csv`
-- - fenced block: ```\n../data/people.csv\n```
--
-- Strip those wrappers and enforce the v0.1.0 rule that the selection must
-- resolve to exactly one non-empty path.
local function extract_candidate_path(raw_text)
	local lines = vim.split(raw_text, "\n", { plain = true })
	local filtered = {}

	for _, line in ipairs(lines) do
		local trimmed = vim.trim(line)
		if
			trimmed ~= ""
			and not trimmed:match("^```")
			and not trimmed:match("^~~~")
		then
			filtered[#filtered + 1] = strip_wrappers(trimmed)
		end
	end

	if #filtered == 0 then
		return nil, "Selected path is empty."
	end

	if #filtered > 1 then
		return nil, "Selection must resolve to a single file path."
	end

	local path = vim.trim(filtered[1])
	if path == "" then
		return nil, "Selected path is empty."
	end

	return path
end

local function fence_info(line)
	local fence = line:match("^%s*([`~][`~][`~]+)")
	if not fence then
		return nil
	end

	return {
		char = fence:sub(1, 1),
		len = #fence,
	}
end

local function matches_fence(line, open)
	local candidate = fence_info(line)
	return candidate
		and candidate.char == open.char
		and candidate.len >= open.len
end

local function selection_within_region(range, region)
	return range.start_row >= region.start_row
		and range.end_row <= region.end_row
end

-- Walk fenced regions in document order so target detection is based on actual
-- balanced blocks, not on ad hoc upward scans from the selected row.
--
-- This matters in mixed documents. For example, if an inline path appears
-- between two separate fenced blocks, it must remain an "insert below" target
-- instead of being mistaken for part of the earlier fence.
local function find_containing_fence(lines, range)
	local open_row
	local open_fence

	for current_row = 1, #lines do
		local candidate = fence_info(lines[current_row])
		if candidate then
			if not open_fence then
				open_row = current_row
				open_fence = candidate
			elseif matches_fence(lines[current_row], open_fence) then
				local region = {
					start_row = open_row,
					end_row = current_row,
				}

				if selection_within_region(range, region) then
					return region
				end

				open_row, open_fence = nil, nil
			end
		end

		if not open_fence and current_row > range.end_row then
			break
		end
	end

	return nil
end

-- For plain text and inline-code paths, the table is inserted below the whole
-- paragraph rather than immediately below the selected line. A "paragraph" here
-- is the current run of non-blank lines.
local function find_paragraph_end(lines, row)
	local current = row
	while
		current < #lines
		and lines[current + 1]
		and lines[current + 1]:match("%S")
	do
		current = current + 1
	end
	return current
end

local function build_target(lines, range)
	local fenced = find_containing_fence(lines, range)
	if fenced then
		return {
			kind = "replace_range",
			start_row = fenced.start_row,
			end_row = fenced.end_row,
		}
	end

	return {
		kind = "insert_after_row",
		row = find_paragraph_end(lines, range.end_row),
	}
end

local function next_nonblank_row(lines, row)
	local current = row + 1
	while current <= #lines and is_blank(lines[current]) do
		current = current + 1
	end
	return current
end

---Extract the selected path and decide how the table should be applied.
---
---Target rules in v0.1.0:
--- - plain text path      -> insert below the containing paragraph
--- - inline-code path     -> insert below the containing paragraph
--- - fenced code block    -> replace the entire fenced block
---@param bufnr integer
---@return table|nil, string|nil
function M.get(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local raw_start = vim.api.nvim_buf_get_mark(bufnr, "<")
	local raw_finish = vim.api.nvim_buf_get_mark(bufnr, ">")
	if raw_start[1] == 0 or raw_finish[1] == 0 then
		return nil,
			"Select a file path in visual mode before running :TableFromFile."
	end

	local range = normalize_range(bufnr, raw_start, raw_finish)

	local raw_text = extract_text(bufnr, range)
	local candidate_path, clean_error = extract_candidate_path(raw_text)
	if not candidate_path then
		return nil, clean_error
	end

	local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	return {
		bufnr = bufnr,
		candidate_path = candidate_path,
		range = range,
		target = build_target(all_lines, range),
	}
end

---Check whether the current buffer still has a usable visual selection.
---@param bufnr integer
---@return boolean
function M.has_visual_marks(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()

	local raw_start = vim.api.nvim_buf_get_mark(bufnr, "<")
	local raw_finish = vim.api.nvim_buf_get_mark(bufnr, ">")
	return raw_start[1] ~= 0 and raw_finish[1] ~= 0
end

---Clear persisted visual marks so a later normal-mode command run does not
---mistake stale marks for a fresh selection.
---@param bufnr integer
function M.clear_visual_marks(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
	vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
end

---Create a durable anchor for the original selection so table insertion can be
---resolved again after the buffer changes while the enhanced UI session is
---hidden.
---@param selection_info table
---@return table|nil, string|nil
function M.create_anchor(selection_info)
	local range = selection_info.range
	if not range then
		return nil, "Missing selection range."
	end

	local extmark_id = vim.api.nvim_buf_set_extmark(
		selection_info.bufnr,
		anchor_namespace,
		range.start_row - 1,
		range.start_col,
		{
			end_row = range.end_row - 1,
			end_col = range.end_col + 1,
			right_gravity = false,
			end_right_gravity = true,
			strict = false,
		}
	)

	return {
		bufnr = selection_info.bufnr,
		extmark_id = extmark_id,
	}
end

---Resolve the current anchored range.
---@param anchor table
---@return table|nil, string|nil
function M.resolve_range(anchor)
	return extmark_range(anchor.bufnr, anchor.extmark_id)
end

---Resolve the current apply target for a hidden enhanced-UI session.
---@param anchor table
---@return table|nil, string|nil
function M.resolve_target(anchor)
	local range, range_error = M.resolve_range(anchor)
	if not range then
		return nil, range_error
	end

	local all_lines = vim.api.nvim_buf_get_lines(anchor.bufnr, 0, -1, false)
	return {
		bufnr = anchor.bufnr,
		range = range,
		target = build_target(all_lines, range),
	}
end

---Dispose a previously created anchor.
---@param anchor table|nil
function M.dispose_anchor(anchor)
	if not anchor then
		return
	end

	if not vim.api.nvim_buf_is_valid(anchor.bufnr) then
		return
	end

	pcall(
		vim.api.nvim_buf_del_extmark,
		anchor.bufnr,
		anchor_namespace,
		anchor.extmark_id
	)
end

---Insert or replace the generated table based on the target from `get()`.
---
---`replace_range` is used for fenced blocks.
---`insert_after_row` is used for plain text and inline-code selections.
---@param selection_info table
---@param table_lines string[]
function M.apply(selection_info, table_lines)
	local bufnr = selection_info.bufnr
	local target = selection_info.target
	local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	if target.kind == "replace_range" then
		local replacement = vim.deepcopy(table_lines)
		local previous_line = all_lines[target.start_row - 1]
		local next_line = all_lines[target.end_row + 1]
		local leading_blank = previous_line and not is_blank(previous_line)

		if leading_blank then
			table.insert(replacement, 1, "")
		end

		if next_line and not is_blank(next_line) then
			replacement[#replacement + 1] = ""
		end

		vim.api.nvim_buf_set_lines(
			bufnr,
			target.start_row - 1,
			target.end_row,
			false,
			replacement
		)
		vim.api.nvim_win_set_cursor(
			0,
			{ target.start_row + (leading_blank and 1 or 0), 0 }
		)
		return
	end

	local next_content_row = next_nonblank_row(all_lines, target.row)
	local insert_lines = { "" }
	vim.list_extend(insert_lines, table_lines)
	if next_content_row <= #all_lines then
		insert_lines[#insert_lines + 1] = ""
	end

	vim.api.nvim_buf_set_lines(
		bufnr,
		target.row,
		next_content_row - 1,
		false,
		insert_lines
	)
	vim.api.nvim_win_set_cursor(0, { target.row + 2, 0 })
end

return M
