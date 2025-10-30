---UI and layout management for scratch-manager.nvim
---Handles window sizing, column layout, and item formatting

local M = {}

-- Load icons module for icon handling
local icons = require("scratch-manager.icons")
-- Load utils module for shared formatting
local utils = require("scratch-manager.utils")

---Get formatted filename from scratch buffer name
---@param name string Buffer name
---@return string filename Formatted filename
local function get_scratch_filename(name)
	if not name then
		return ""
	end
	local match = name:match("Scratch Pad %((.+)%)")
	return match or name
end

---Calculate optimal window width and column widths based on content
---@param items table List of scratch buffer items
---@param config table Configuration object
---@return table {window_width: number, column_widths: table}
function M.calculate_optimal_layout(items, config)
	-- Break down layout calculation into focused, testable functions
	local content_analysis = utils.analyze_content_lengths(items, config)
	local width_calculation = utils.calculate_ideal_widths(content_analysis, config)
	local final_layout = utils.apply_layout_constraints(width_calculation, config)

	return final_layout
end

---Format a single item line for display
---@param item table Scratch buffer item
---@param widths table Column widths
---@param is_selected boolean Whether this item is currently selected
---@param config table Configuration object
---@return string line Formatted display line
---@return table|nil highlights Highlight information {group, col_start, col_end} or nil
function M.format_item_line(item, widths, is_selected, config)
	-- Extract components from item

	-- Extract components
	local filename = get_scratch_filename(item.name or "")
	local cwd = item.cwd and vim.fn.fnamemodify(item.cwd, ":p:~") or ""
	local branch = config.ui.show_git_branch and utils.get_git_branch(item.cwd) or nil

	-- Get icon with proper fallback handling
	local icon, icon_hl = utils.get_display_icon(filename, item.ft, config.ui.show_icon)

	-- Apply truncation to all text fields
	filename = utils.truncate_text(filename, widths.filename_width)
	if config.ui.show_git_branch and branch then
		branch = utils.truncate_text(branch, widths.branch_width)
	end
	cwd = utils.smart_truncate_path(cwd, widths.cwd_width)

	-- Use centralized formatting to ensure consistency with header
	local formatted_line = utils.format_columns(" ", icon, filename, branch, cwd, widths, config)

	-- Calculate icon highlight position if we have colored icons and icons are enabled
	local highlights = nil
	if config.ui.show_icon and icon_hl then
		-- Icon position calculation based on utils.format_columns structure:
		-- Format: "selector icon filename branch cwd" (spaces between each part)
		-- Icon starts after: selector + space = ICON_POSITION_OFFSET
		local constants = utils.get_layout_constants()
		local icon_start = constants.ICON_POSITION_OFFSET -- 0-based position
		local icon_end = icon_start + vim.fn.strdisplaywidth(icon)
		highlights = { icon_hl, icon_start, icon_end }
	end

	return formatted_line, highlights
end

-- Expose internal functions for testing (following established pattern)
M._get_scratch_filename = get_scratch_filename

return M
