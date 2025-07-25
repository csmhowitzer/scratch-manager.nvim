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
  local icon_width = config.ui.icon_width
  local filename_width = max_filename
  local branch_width = config.ui.show_git_branch and max_branch or 0
  local cwd_width = max_cwd
  local padding = 4 -- spaces between columns
  
  local ideal_width = selector_width + icon_width + filename_width + branch_width + cwd_width + padding
  
  -- Apply constraints
  local max_width = math.floor(vim.o.columns * 0.8)
  local min_width = 60
  local window_width = math.max(min_width, math.min(ideal_width, max_width))
  
  -- If we hit max width, we need to truncate proportionally
  if ideal_width > max_width then
    local available_width = max_width - selector_width - icon_width - padding
    local content_ratio = available_width / (filename_width + branch_width + cwd_width)
    
    filename_width = math.floor(filename_width * content_ratio)
    branch_width = config.ui.show_git_branch and math.floor(branch_width * content_ratio) or 0
    cwd_width = available_width - filename_width - branch_width
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
---@return string Formatted display line
function M.format_item_line(item, widths, is_selected, config)
  -- Extract components from item

  -- Extract components
  local filename = get_scratch_filename(item.name or "")
  local cwd = item.cwd and vim.fn.fnamemodify(item.cwd, ":p:~") or ""
  local branch = config.ui.show_git_branch and get_git_branch(item.cwd) or ""

  -- Get icon based on actual scratch buffer filetype (not filename)
  -- This ensures correct icons: markdown scratch buffers get markdown icons,
  -- even if the filename suggests a different type (e.g., "Project.cs" with markdown content)
  local icon = icons.get_icon_for_filetype(item.ft or "")
  -- Ensure icon is NEVER nil or empty for consistent spacing
  -- Every row must have an icon to maintain column alignment
  if not icon or icon == "" then
    icon = "󰈔"  -- Professional fallback icon for unknown file types
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
  return utils.format_columns(" ", icon, filename, branch, cwd, widths, config)
end

-- Expose internal functions for testing (following established pattern)
M._get_scratch_filename = get_scratch_filename
M._get_git_branch = get_git_branch

return M
