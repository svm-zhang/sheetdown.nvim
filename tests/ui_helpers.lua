local M = {}

function M.unload(name)
	package.loaded[name] = nil
end

function M.with_module(name, value, fn)
	local original = package.loaded[name]
	package.loaded[name] = value

	local ok, err = xpcall(fn, debug.traceback)
	package.loaded[name] = original
	if not ok then
		error(err)
	end
end

local function create_float(width, height)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = 1,
		col = 1,
		width = width,
		height = height,
		style = "minimal",
		border = "single",
	})

	return {
		buf = buf,
		win = win,
		opts = { wo = {} },
		valid = function(self)
			return vim.api.nvim_win_is_valid(self.win)
		end,
	}
end

local function close_float(float)
	if float and float.win and vim.api.nvim_win_is_valid(float.win) then
		vim.api.nvim_win_close(float.win, true)
	end

	if float and float.buf and vim.api.nvim_buf_is_valid(float.buf) then
		vim.api.nvim_buf_delete(float.buf, { force = true })
	end
end

function M.make_fake_picker(items)
	local input_win = create_float(50, 1)
	local preview_win = create_float(90, 12)
	local input_update_calls = 0
	local preview_title
	local preview_lines
	local focused

	local picker = {}
	picker.list = {
		selected = {},
		current = items[1],
		is_selected = function(self, item)
			for _, selected in ipairs(self.selected) do
				if selected.column_index == item.column_index then
					return true
				end
			end

			return false
		end,
		select = function(self)
			local current = self.current
			if not current then
				return
			end

			if self:is_selected(current) then
				local remaining = {}
				for _, selected in ipairs(self.selected) do
					if selected.column_index ~= current.column_index then
						remaining[#remaining + 1] = selected
					end
				end
				self.selected = remaining
				return
			end

			self.selected[#self.selected + 1] = current
		end,
		set_selected = function(self, selected)
			self.selected = selected or {}
		end,
	}
	picker.selected = function()
		return picker.list.selected
	end
	picker.current = function()
		return picker.list.current
	end
	picker.focus = function(_, win)
		focused = win
	end
	picker.close = function() end
	picker.preview = {
		win = preview_win,
		wo = {},
		reset = function() end,
		minimal = function() end,
		set_title = function(_, value)
			preview_title = value
		end,
		set_lines = function(_, lines)
			preview_lines = vim.deepcopy(lines)
			vim.api.nvim_buf_set_lines(preview_win.buf, 0, -1, false, lines)
		end,
	}
	picker.input = {
		win = input_win,
		update = function()
			input_update_calls = input_update_calls + 1
		end,
	}

	return picker, {
		cleanup = function()
			close_float(input_win)
			close_float(preview_win)
		end,
		focused = function()
			return focused
		end,
		preview_title = function()
			return preview_title
		end,
		preview_lines = function()
			return preview_lines
		end,
		preview_extmarks = function()
			return vim.api.nvim_buf_get_extmarks(
				preview_win.buf,
				-1,
				0,
				-1,
				{ details = true }
			)
		end,
		input_extmarks = function()
			return vim.api.nvim_buf_get_extmarks(
				input_win.buf,
				-1,
				0,
				-1,
				{ details = true }
			)
		end,
		input_buf = function()
			return input_win.buf
		end,
		input_update_calls = function()
			return input_update_calls
		end,
	}
end

return M
