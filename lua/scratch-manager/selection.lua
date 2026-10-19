---Custom selection UI for scratch-manager.nvim
---Provides telescope-like interface for selecting scratch buffers

local M = {}

-- Load extracted modules
local ui = require("scratch-manager.ui")
local utils = require("scratch-manager.utils")

-- Selection UI state
---Highlight a range with an extmark (nvim_buf_add_highlight is deprecated); col_end -1 = end of line
---@param buf number
---@param ns number
---@param group string
---@param line number 0-based
---@param col_start number
---@param col_end number
local function add_highlight(buf, ns, group, line, col_start, col_end)
	if col_end == -1 then
		local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, line, line + 1, false)
		col_end = ok and #(lines[1] or "") or 0
	end
	pcall(vim.api.nvim_buf_set_extmark, buf, ns, line, col_start, { end_col = col_end, hl_group = group })
end

local selection_ui = {
	header_buf = nil,
	header_win = nil,
	content_buf = nil,
	content_win = nil,
	items = {},
	callback = nil,
	selected_idx = 1,
	max_visible_items = 20, -- Will be set from config
	opts = {},
}

---Close the selection UI
---@private
local function close_selection_ui()
	-- Close header window and buffer
	if selection_ui.header_win and vim.api.nvim_win_is_valid(selection_ui.header_win) then
		vim.api.nvim_win_close(selection_ui.header_win, true)
	end
	if selection_ui.header_buf and vim.api.nvim_buf_is_valid(selection_ui.header_buf) then
		vim.api.nvim_buf_delete(selection_ui.header_buf, { force = true })
	end

	-- Close content window and buffer
	if selection_ui.content_win and vim.api.nvim_win_is_valid(selection_ui.content_win) then
		vim.api.nvim_win_close(selection_ui.content_win, true)
	end
	if selection_ui.content_buf and vim.api.nvim_buf_is_valid(selection_ui.content_buf) then
		vim.api.nvim_buf_delete(selection_ui.content_buf, { force = true })
	end

	selection_ui.header_buf = nil
	selection_ui.header_win = nil
	selection_ui.content_buf = nil
	selection_ui.content_win = nil
	selection_ui.items = {}
	selection_ui.callback = nil
	selection_ui.selected_idx = 1
	selection_ui.opts = {}
end

---Create header window with sticky header content
---@param config table Configuration object
---@param layout table Layout information
---@param win_config table Base window configuration
---@private
local function create_header_window(config, layout, win_config)
	local widths = layout.column_widths
	local win_width = layout.window_width

	-- Create header buffer
	selection_ui.header_buf = vim.api.nvim_create_buf(false, true)

	-- Build header lines with optional file counter
	local counter_text = selection_ui.opts.counter_text
	if not counter_text and config.ui.file_counter then
		local file_count = #selection_ui.items
		counter_text = string.format("%d files", file_count)
	end

	local header, counter_highlight = utils.format_columns(
		" ",
		"",
		"Filename",
		config.ui.show_git_branch and "Branch" or nil,
		config.ui.show_path and "Working Directory" or "",
		widths,
		config,
		counter_text, -- Will be nil if file_counter is disabled
		win_width, -- Add window width for right-alignment calculation
		(widths.age_width or 0) > 0 and "Age" or nil
	)
	local separator_width = win_width - 2 -- Account for window borders
	local separator = string.rep("─", separator_width)

	local header_lines = { header, separator }

	-- Set header content
	vim.api.nvim_buf_set_lines(selection_ui.header_buf, 0, -1, false, header_lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = selection_ui.header_buf })

	-- Create header window (fixed position, height = 2, no bottom border)
	local header_config = vim.tbl_deep_extend("force", win_config, {
		height = 2,
		zindex = 20, -- Higher than content window
		border = { "┌", "─", "┐", "│", "", "", "", "│" }, -- No bottom border
	})

	selection_ui.header_win = vim.api.nvim_open_win(selection_ui.header_buf, false, header_config)

	-- Define file counter highlight group from config
	vim.api.nvim_set_hl(0, "ScratchManagerFileCount", config.highlights.file_counter)

	-- Define window title highlight group from config
	vim.api.nvim_set_hl(0, "ScratchManagerWindowTitle", config.highlights.window_title)

	-- Apply file counter highlighting if present
	if counter_highlight then
		local counter_ns_id = vim.api.nvim_create_namespace("scratch-manager-file-count")
		add_highlight(
			selection_ui.header_buf,
			counter_ns_id,
			counter_highlight.group,
			0, -- First line (header)
			counter_highlight.start_col,
			counter_highlight.end_col
		)
	end

	-- Apply header highlighting
	local header_ns_id = vim.api.nvim_create_namespace("scratch-manager-header")
	add_highlight(selection_ui.header_buf, header_ns_id, "ScratchManagerSelectHeader", 0, 0, -1)
	add_highlight(selection_ui.header_buf, header_ns_id, "ScratchManagerSeparator", 1, 0, -1)
end

---Create content window with scrollable items
---@param config table Configuration object
---@param layout table Layout information
---@param win_config table Base window configuration
---@private
local function create_content_window(config, layout, win_config)
	local widths = layout.column_widths

	-- Create content buffer
	selection_ui.content_buf = vim.api.nvim_create_buf(false, true)

	-- Build content lines (items + footer)
	local content_lines = {}
	local item_highlights = {}

	-- Add ALL items with highlight tracking
	for i, item in ipairs(selection_ui.items) do
		local line, highlights = ui.format_item_line(item, widths, i == selection_ui.selected_idx, config)
		table.insert(content_lines, line)
		if highlights then
			-- Store highlights for this line (no offset needed since content starts at line 1)
			item_highlights[i] = highlights
		end
	end

	-- No footer in content - footer is now a separate window

	-- Set content
	vim.api.nvim_buf_set_lines(selection_ui.content_buf, 0, -1, false, content_lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = selection_ui.content_buf })

	-- Create content window (positioned below header, with bottom border)
	local content_config = vim.tbl_deep_extend("force", win_config, {
		row = win_config.row + 3, -- Position below header (header=2 rows, so +3 to clear it)
		height = win_config.height - 2, -- Subtract header height only
		zindex = 10, -- Lower than header window
		border = { "", "", "", "│", "┘", "─", "└", "│" }, -- No top border, has bottom border for footer
	})

	selection_ui.content_win = vim.api.nvim_open_win(selection_ui.content_buf, true, content_config)

	-- Dimmed rows (e.g. pads from another branch, or whose source file is gone), under the icon color
	local dim_ns_id = vim.api.nvim_create_namespace("scratch-manager-dim")
	vim.api.nvim_set_hl(0, "ScratchManagerSelectDim", { link = "Comment", default = true })
	for i, item in ipairs(selection_ui.items) do
		if item.dim then
			add_highlight(selection_ui.content_buf, dim_ns_id, "ScratchManagerSelectDim", i - 1, 0, -1)
		end
	end

	-- Apply icon highlighting
	local icon_ns_id = vim.api.nvim_create_namespace("scratch-manager-icons")
	for line_num, highlight_info in pairs(item_highlights) do
		local hl_group, col_start, col_end = unpack(highlight_info)
		add_highlight(selection_ui.content_buf, icon_ns_id, hl_group, line_num - 1, col_start, col_end)
	end
end

---Update only the selection highlighting (fast)
---@private
local function update_selection_highlighting()
	if not selection_ui.content_buf or not vim.api.nvim_buf_is_valid(selection_ui.content_buf) then
		return
	end

	local ns_id = vim.api.nvim_create_namespace("scratch-manager-select")
	vim.api.nvim_buf_clear_namespace(selection_ui.content_buf, ns_id, 0, -1)

	-- Highlight selected item FIRST (so icon highlights can override it)
	if selection_ui.selected_idx > 0 and selection_ui.selected_idx <= #selection_ui.items then
		local line_idx = selection_ui.selected_idx - 1 -- Convert 1-based selected_idx to 0-based buffer line
		add_highlight(selection_ui.content_buf, ns_id, "Visual", line_idx, 0, -1)
	end

	-- Icon highlights live in their own namespace that is never cleared, so they persist
	-- across selection updates without being re-applied (Visual only sets a background)

	-- Set cursor position (shift down by 1 from original position with bounds checking)
	if selection_ui.content_win and vim.api.nvim_win_is_valid(selection_ui.content_win) then
		local cursor_line = selection_ui.selected_idx -- Convert 1-based selected_idx to 1-based cursor position
		local buffer_line_count = vim.api.nvim_buf_line_count(selection_ui.content_buf)

		-- Ensure cursor doesn't go beyond buffer bounds
		if cursor_line <= buffer_line_count then
			vim.api.nvim_win_set_cursor(selection_ui.content_win, { cursor_line, 0 })
		end
	end
end

---Handle key press in selection UI with scroll support
---
---Wrap-around navigation logic:
---• Down (j): When near end (> items-2), wrap to position 1
---• Up (k): When near beginning (< 2), wrap to position items-1
---• The -2/-1 offsets account for display buffer structure and ensure
---  smooth navigation without cursor positioning errors
---
---@param key string The pressed key
---@param config table Configuration object
---@private
local function handle_selection_key(key, config)
	if key == "j" or key == "<Down>" then
		-- Wrap around: if at end, go to beginning
		if selection_ui.selected_idx >= #selection_ui.items then
			selection_ui.selected_idx = 1
		else
			selection_ui.selected_idx = selection_ui.selected_idx + 1
		end
		update_selection_highlighting() -- Fast update, no rebuilding
	elseif key == "k" or key == "<Up>" then
		-- Wrap around: if at beginning, go to end
		if selection_ui.selected_idx <= 1 then
			selection_ui.selected_idx = #selection_ui.items
		else
			selection_ui.selected_idx = selection_ui.selected_idx - 1
		end
		update_selection_highlighting() -- Fast update, no rebuilding
	elseif key == "<CR>" or key == "<Space>" then
		-- Select current item
		local selected_item = selection_ui.items[selection_ui.selected_idx]
		local callback = selection_ui.callback
		close_selection_ui()
		if callback and selected_item then
			callback(selected_item)
		end
	elseif key == "<Esc>" or key == "q" then
		-- Cancel selection
		local callback = selection_ui.callback
		close_selection_ui()
		if callback then
			callback(nil)
		end
	end
end

---Create custom selection UI
---@param items table List of items to select from
---@param opts table Options (title, etc.)
---@param callback function Callback function when item is selected
---@param config table Configuration object
function M.create_custom_selection(items, opts, callback, config)
	if #items == 0 then
		if callback then
			callback(nil)
		end
		return
	end

	selection_ui.items = items
	selection_ui.callback = callback
	selection_ui.opts = opts or {}
	selection_ui.selected_idx = math.max(1, math.min(selection_ui.opts.start_idx or 1, #items))
	selection_ui.max_visible_items = config.selection.max_items

	-- Calculate optimal window size and column widths
	local layout = ui.calculate_optimal_layout(items, config)
	local width = layout.window_width

	-- Calculate height for window scrolling approach
	local max_visible_items = selection_ui.max_visible_items
	local base_height = 2 + math.min(#items, max_visible_items) -- header + separator + items (fits the list)

	-- Respect screen size limits
	local constants = utils.get_layout_constants()
	local height = math.min(base_height, math.floor(vim.o.lines * constants.SCREEN_HEIGHT_RATIO))

	local action_hints = selection_ui.opts.hints or "<CR> Select, <Esc> quit"

	-- Base window configuration
	local base_win_opts = {
		relative = "editor",
		width = width,
		zindex = 15,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = opts.prompt or "Select Scratch Buffer",
		title_pos = "center",
		footer = action_hints,
		footer_pos = "center",
	}

	-- Create header and content windows
	create_header_window(config, layout, base_win_opts)
	create_content_window(config, layout, base_win_opts)

	-- Apply custom highlight groups for all windows (including footer)
	vim.api.nvim_set_option_value(
		"winhighlight",
		"FloatBorder:ScratchManagerSelectBorder,FloatTitle:ScratchManagerWindowTitle,FloatFooter:ScratchManagerSelectFooter",
		{ win = selection_ui.header_win }
	)
	vim.api.nvim_set_option_value(
		"winhighlight",
		"FloatBorder:ScratchManagerSelectBorder,FloatFooter:ScratchManagerSelectFooter",
		{ win = selection_ui.content_win }
	)

	-- Set up keymaps (on content buffer since that's where focus is)
	local keymap_opts = { buffer = selection_ui.content_buf, nowait = true, silent = true }
	vim.keymap.set("n", "j", function()
		handle_selection_key("j", config)
	end, keymap_opts)
	vim.keymap.set("n", "k", function()
		handle_selection_key("k", config)
	end, keymap_opts)
	vim.keymap.set("n", "<Down>", function()
		handle_selection_key("<Down>", config)
	end, keymap_opts)
	vim.keymap.set("n", "<Up>", function()
		handle_selection_key("<Up>", config)
	end, keymap_opts)
	vim.keymap.set("n", "<CR>", function()
		handle_selection_key("<CR>", config)
	end, keymap_opts)
	vim.keymap.set("n", "<Space>", function()
		handle_selection_key("<Space>", config)
	end, keymap_opts)
	vim.keymap.set("n", "<Esc>", function()
		handle_selection_key("<Esc>", config)
	end, keymap_opts)
	vim.keymap.set("n", "q", function()
		handle_selection_key("q", config)
	end, keymap_opts)

	-- Extra keys (opts.actions): key -> { fn = function(items, idx), modes = { "n", "x" } }. In visual
	-- mode the action gets every selected row. The action decides whether to close the list.
	for key, action in pairs(selection_ui.opts.actions or {}) do
		vim.keymap.set(action.modes or "n", key, function()
			local first, last = selection_ui.selected_idx, selection_ui.selected_idx
			local mode = vim.fn.mode()
			if mode == "v" or mode == "V" or mode == "\22" then
				first, last = vim.fn.line("v"), vim.fn.line(".")
				if first > last then
					first, last = last, first
				end
				vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
			end
			local chosen = {}
			for i = math.max(1, first), math.min(last, #selection_ui.items) do
				table.insert(chosen, selection_ui.items[i])
			end
			if #chosen > 0 then
				action.fn(chosen, first)
			end
		end, vim.tbl_extend("force", keymap_opts, { desc = action.desc }))
	end

	-- Close on buffer leave (content buffer). Scheduled, so it must not close a newer list opened
	-- in the meantime (actions reopen the list)
	local list_buf = selection_ui.content_buf
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = list_buf,
		once = true,
		callback = function()
			vim.schedule(function()
				if selection_ui.content_buf ~= list_buf then
					return
				end
				if selection_ui.callback then
					selection_ui.callback(nil)
				end
				close_selection_ui()
			end)
		end,
	})

	-- Initial selection highlighting
	update_selection_highlighting()
end

-- Expose internal functions for testing (following established pattern)
---Close the list without choosing (for actions that continue elsewhere)
M.close = close_selection_ui
M._state = selection_ui
M._close_selection_ui = close_selection_ui
M._create_header_window = create_header_window
M._create_content_window = create_content_window
M._update_selection_highlighting = update_selection_highlighting
M._handle_selection_key = handle_selection_key

return M
