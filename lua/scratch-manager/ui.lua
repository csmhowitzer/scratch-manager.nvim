---UI and layout management for scratch-manager.nvim
---Handles window sizing, column layout, and item formatting

local M = {}

-- Load icons module for icon handling
local icons = require("scratch-manager.icons")
-- Load icon provider for colored icons (v2.0 enhancement)
local icon_provider = require("scratch-manager.icon_provider")
-- Load utils module for shared formatting
local utils = require("scratch-manager.utils")

---Get formatted filename from scratch buffer name
---@param name string Buffer name
---@return string filename Formatted filename
local function get_scratch_filename(name)
  if not name then return "" end
  local match = name:match("Scratch Pad %((.+)%)")
  return match or name
end

---Get git branch for directory
---@param cwd string|nil Working directory
---@return string branch Git branch name or empty string
local function get_git_branch(cwd)
  if not cwd then return "" end

  local handle = io.popen("cd " .. vim.fn.shellescape(cwd) .. " && git branch --show-current 2>/dev/null")
  if not handle then return "" end

  local result = handle:read("*a")
  handle:close()

  local branch = result and vim.trim(result) or ""
  -- Debug: uncomment to see what's happening
  -- print("Git branch for " .. cwd .. ": '" .. branch .. "'")
  return branch
end

---Calculate optimal window width and column widths based on content
---@param items table List of scratch buffer items
---@param config table Configuration object
---@return table {window_width: number, column_widths: table}
function M.calculate_optimal_layout(items, config)
  local max_filename = 0
  local max_branch = 0
  local max_cwd = 0
  
  -- Find the longest content in each column
  for _, item in ipairs(items) do
    local filename = get_scratch_filename(item.name or "")
    local branch = config.ui.show_git_branch and get_git_branch(item.cwd) or ""
    local cwd = item.cwd and vim.fn.fnamemodify(item.cwd, ":p:~") or ""
    
    max_filename = math.max(max_filename, #filename)
    max_branch = math.max(max_branch, #branch)
    max_cwd = math.max(max_cwd, #cwd)
  end
  
  -- Start with actual content widths (no truncation)
  local selector_width = 2
  local icon_width = config.ui.show_icon and config.ui.icon_width or 0
  local filename_width = max_filename
  local branch_width = config.ui.show_git_branch and max_branch or 0
  local cwd_width = config.ui.show_path and max_cwd or 0

  -- Calculate padding based on visible columns (spaces between columns)
  local visible_columns = 1 -- selector always visible
  if config.ui.show_icon then visible_columns = visible_columns + 1 end
  visible_columns = visible_columns + 1 -- filename always visible
  if config.ui.show_git_branch then visible_columns = visible_columns + 1 end
  if config.ui.show_path then visible_columns = visible_columns + 1 end
  local padding = (visible_columns - 1) -- one space between each visible column

  local ideal_width = selector_width + icon_width + filename_width + branch_width + cwd_width + padding
  
  -- Apply constraints
  local max_width = math.floor(vim.o.columns * 0.8)
  local min_width = 60
  local window_width = math.max(min_width, math.min(ideal_width, max_width))
  
  -- If we hit max width, we need to truncate proportionally
  if ideal_width > max_width then
    local available_width = max_width - selector_width - icon_width - padding
    local total_content_width = filename_width + branch_width + cwd_width

    if total_content_width > 0 then
      local content_ratio = available_width / total_content_width

      filename_width = math.floor(filename_width * content_ratio)
      branch_width = config.ui.show_git_branch and math.floor(branch_width * content_ratio) or 0
      cwd_width = config.ui.show_path and (available_width - filename_width - branch_width) or 0
    end
  end
  
  return {
    window_width = window_width,
    column_widths = {
      selector_width = selector_width,
      icon_width = icon_width,
      filename_width = filename_width,
      branch_width = branch_width,
      cwd_width = cwd_width,
    }
  }
end

---Smart truncate path to show most relevant parts
---@param path string Full path
---@param max_width number Maximum width allowed
---@return string Truncated path
function M.smart_truncate_path(path, max_width)
  if #path <= max_width then
    return path
  end

  -- Try to show the last few directories
  local parts = vim.split(path, "/")
  if #parts <= 2 then
    -- Simple truncation for short paths
    return "..." .. path:sub(-(max_width - 3))
  end

  -- Build from the end, keeping as many directories as possible
  local result = parts[#parts] -- always keep the last part
  for i = #parts - 1, 1, -1 do
    local candidate = parts[i] .. "/" .. result
    if #candidate + 3 > max_width then -- +3 for "..."
      break
    end
    result = candidate
  end

  return "..." .. result
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
  local branch = config.ui.show_git_branch and get_git_branch(item.cwd) or nil

  -- Get icon with color support (v2.0 enhancement) - only if icons are enabled
  local icon = ""
  local icon_hl = nil

  if config.ui.show_icon then
    -- Use filename for better icon detection, with filetype as hint
    -- This ensures correct icons: markdown scratch buffers get markdown icons,
    -- even if the filename suggests a different type (e.g., "Project.cs" with markdown content)
    local icon_result = icon_provider.get_icon_with_color(filename, item.ft or "")
    icon = icon_result.icon
    icon_hl = icon_result.hl

    -- Ensure icon is NEVER nil or empty for consistent spacing
    -- Every row must have an icon to maintain column alignment
    if not icon or icon == "" then
      icon = "󰈔"  -- Professional fallback icon for unknown file types
      icon_hl = nil  -- No highlight for fallback
    end
  end

  -- Truncate filename if necessary
  if #filename > widths.filename_width then
    filename = filename:sub(1, widths.filename_width - 3) .. "..."
  end

  -- Truncate branch if necessary
  if config.ui.show_git_branch and #branch > widths.branch_width then
    branch = branch:sub(1, widths.branch_width - 3) .. "..."
  end

  -- Smart truncate path
  if #cwd > widths.cwd_width then
    cwd = M.smart_truncate_path(cwd, widths.cwd_width)
  end

  -- Use centralized formatting to ensure consistency with header
  local formatted_line = utils.format_columns(" ", icon, filename, branch, cwd, widths, config)

  -- Calculate icon highlight position if we have colored icons and icons are enabled
  local highlights = nil
  if config.ui.show_icon and icon_hl then
    -- Icon position calculation based on utils.format_columns structure:
    -- Format: "selector icon filename branch cwd" (spaces between each part)
    -- Icon starts after: selector (1 char) + space (1 char) = position 2
    local icon_start = 2  -- 0-based position
    local icon_end = icon_start + vim.fn.strdisplaywidth(icon)
    highlights = { icon_hl, icon_start, icon_end }
  end

  return formatted_line, highlights
end

-- Expose internal functions for testing (following established pattern)
M._get_scratch_filename = get_scratch_filename
M._get_git_branch = get_git_branch

return M
