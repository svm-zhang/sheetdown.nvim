local columns = require("sheetdown.columns")
local config = require("sheetdown.config")
local dialect = require("sheetdown.dialect")
local notify = require("sheetdown.notify")
local path = require("sheetdown.path")
local reader = require("sheetdown.reader")
local selection = require("sheetdown.selection")
local session_registry = require("sheetdown.session_registry")
local markdown_table = require("sheetdown.table")
local ui = require("sheetdown.ui")
local ui_session = require("sheetdown.ui_session")

local M = {}

local function entry_label(entry)
	return ("%s (line %d)"):format(entry.resolved.absolute, entry.original_line)
end

local function discard_entry(bufnr)
	local entry = session_registry.clear(bufnr)
	if entry and entry.anchor then
		selection.dispose_anchor(entry.anchor)
	end

	return entry
end

local function resolve_source(selection_info, bufnr)
	local resolved, path_error =
		path.resolve(selection_info.candidate_path, bufnr)
	if not resolved then
		return nil, path_error
	end

	local detected, dialect_error = dialect.detect_file(resolved.absolute)
	if not detected then
		return nil,
			("%s Please fix the source file and try again."):format(dialect_error)
	end

	local headers, header_error =
		reader.read_headers(resolved.absolute, detected.delimiter)
	if not headers then
		return nil, header_error
	end

	local _, map_error = columns.validate_headers(headers)
	if map_error then
		return nil, map_error
	end

	return {
		resolved = resolved,
		detected = detected,
		headers = headers,
	}
end

local function build_entry(selection_info, source_info, current_config)
	local anchor, anchor_error = selection.create_anchor(selection_info)
	if not anchor then
		return nil, anchor_error
	end

	return {
		bufnr = selection_info.bufnr,
		anchor = anchor,
		detected = source_info.detected,
		headers = source_info.headers,
		original_line = selection_info.range.start_row,
		resolved = source_info.resolved,
		session = ui_session.create(
			source_info.headers,
			current_config,
			{ bufnr = selection_info.bufnr }
		),
	}
end

local function same_entry_identity(entry, selection_info, source_info)
	if entry.resolved.absolute ~= source_info.resolved.absolute then
		return false
	end

	local anchored_range = selection.resolve_range(entry.anchor)
	if not anchored_range then
		return false
	end

	if anchored_range.start_row ~= selection_info.range.start_row then
		return false
	end

	if anchored_range.end_row ~= selection_info.range.end_row then
		return false
	end

	if anchored_range.start_row ~= anchored_range.end_row then
		return true
	end

	return not (
		selection_info.range.end_col < anchored_range.start_col
		or selection_info.range.start_col > anchored_range.end_col
	)
end

local function apply_result(entry, options)
	local rows, read_error = reader.read_selection(
		entry.resolved.absolute,
		entry.detected.delimiter,
		options.row_selection,
		#entry.headers
	)
	if not rows then
		discard_entry(entry.bufnr)
		notify.error(read_error)
		return
	end

	if #rows == 0 then
		discard_entry(entry.bufnr)
		notify.error(
			"Empty output after filtering. Adjust the selected rows and try again."
		)
		return
	end

	local table_lines = markdown_table.render({
		headers = entry.headers,
		rows = rows,
		column_indices = options.parsed_columns.indices,
		alignment = options.alignment,
	})

	local apply_info, apply_error = selection.resolve_target(entry.anchor)
	if not apply_info then
		discard_entry(entry.bufnr)
		notify.error(apply_error)
		return
	end

	selection.apply(apply_info, table_lines)
	discard_entry(entry.bufnr)
	notify.info(("Inserted table from %s"):format(entry.resolved.absolute))
end

local function open_enhanced_entry(entry, current_config)
	session_registry.set(entry)

	local picker = ui.open_session(entry.session, current_config, function(options, prompt_error)
		if prompt_error then
			discard_entry(entry.bufnr)
			notify.error(prompt_error)
			return
		end

		if not options then
			if entry.session:status_name() == "cancelled" then
				notify.info(("Session closed: %s"):format(entry_label(entry)))
				discard_entry(entry.bufnr)
			end
			return
		end

		apply_result(entry, options)
	end)

	if not picker then
		discard_entry(entry.bufnr)
		return nil
	end

	selection.clear_visual_marks(entry.bufnr)
	return true
end

local function run_fallback(bufnr, current_config)
	local selection_info, selection_error = selection.get(bufnr)
	if not selection_info then
		notify.error(selection_error)
		return
	end

	local source_info, source_error = resolve_source(selection_info, bufnr)
	if not source_info then
		notify.error(source_error)
		return
	end

	ui.prompt(source_info.headers, current_config, function(options, prompt_error)
		if prompt_error then
			notify.error(prompt_error)
			return
		end

		if not options then
			return
		end

		local rows, read_error = reader.read_selection(
			source_info.resolved.absolute,
			source_info.detected.delimiter,
			options.row_selection,
			#source_info.headers
		)
		if not rows then
			notify.error(read_error)
			return
		end

		if #rows == 0 then
			notify.error(
				"Empty output after filtering. Adjust the selected rows and try again."
			)
			return
		end

		local table_lines = markdown_table.render({
			headers = source_info.headers,
			rows = rows,
			column_indices = options.parsed_columns.indices,
			alignment = options.alignment,
		})

		selection.apply(selection_info, table_lines)
		notify.info(("Inserted table from %s"):format(source_info.resolved.absolute))
	end)
end

local function restore_hidden_entry(entry, current_config)
	if open_enhanced_entry(entry, current_config) then
		notify.info(("Resumed session: %s"):format(entry_label(entry)))
	end
end

local function replace_hidden_entry(existing, replacement, current_config)
	local discarded = discard_entry(existing.bufnr)
	if discarded then
		notify.info(("Discarded hidden session: %s"):format(entry_label(discarded)))
	end

	if open_enhanced_entry(replacement, current_config) then
		notify.info(("Opened new session: %s"):format(entry_label(replacement)))
	end
end

local function handle_hidden_entry(entry, current_config)
	if not selection.has_visual_marks(entry.bufnr) then
		restore_hidden_entry(entry, current_config)
		return
	end

	local selection_info, selection_error = selection.get(entry.bufnr)
	if not selection_info then
		notify.error(selection_error)
		return
	end

	local source_info, source_error = resolve_source(selection_info, entry.bufnr)
	if not source_info then
		selection.clear_visual_marks(entry.bufnr)
		notify.error(source_error)
		return
	end

	if same_entry_identity(entry, selection_info, source_info) then
		restore_hidden_entry(entry, current_config)
		return
	end

	local replacement, replacement_error =
		build_entry(selection_info, source_info, current_config)
	if not replacement then
		selection.clear_visual_marks(entry.bufnr)
		notify.error(replacement_error)
		return
	end

	replace_hidden_entry(entry, replacement, current_config)
end

local function hide_active_entry(current_config)
	local active_session, active_error = ui.active_session(current_config)
	if active_error then
		notify.error(active_error)
		return true
	end

	if not active_session then
		return false
	end

	local entry = session_registry.get(active_session.bufnr)
	local ok, hide_error = ui.hide_session(active_session, current_config)
	if not ok then
		notify.error(hide_error)
		return true
	end

	selection.clear_visual_marks(active_session.bufnr)

	if entry then
		notify.info(
			("Session hidden: %s. Run :TableFromFile again to resume."):format(
				entry_label(entry)
			)
		)
	else
		notify.info("Session hidden. Run :TableFromFile again to resume.")
	end

	return true
end

---Run the full table-from-file workflow.
function M.run()
	local current_config = config.get()
	local backend, backend_error = ui.resolve_backend(current_config)
	if not backend then
		notify.error(backend_error)
		return
	end

	if backend ~= "snacks" then
		return run_fallback(vim.api.nvim_get_current_buf(), current_config)
	end

	if hide_active_entry(current_config) then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local existing = session_registry.get(bufnr)
	if existing and existing.session:status_name() == "hidden" then
		return handle_hidden_entry(existing, current_config)
	end

	if existing then
		discard_entry(bufnr)
	end

	local selection_info, selection_error = selection.get(bufnr)
	if not selection_info then
		notify.error(selection_error)
		return
	end

	local source_info, source_error = resolve_source(selection_info, bufnr)
	if not source_info then
		notify.error(source_error)
		return
	end

	local entry, entry_error = build_entry(selection_info, source_info, current_config)
	if not entry then
		notify.error(entry_error)
		return
	end

	open_enhanced_entry(entry, current_config)
end

return M
