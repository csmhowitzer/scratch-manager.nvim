---Utility functions for scratch-manager.nvim
---Shared formatting and helper functions

local M = {}

---Format columns into a consistent layout
---This ensures header and content rows use identical formatting
---@param selector string Selector column content (space or arrow)
---@param icon string Icon column content
---@param filename string Filename column content
---@param branch string|nil Branch column content (optional)
---@param cwd string Working directory column content
---@param widths table Column width configuration
---@param config table Configuration object
---@return string Formatted line
function M.format_columns(selector, icon, filename, branch, cwd, widths, config)
  -- Detect if this is a header row (filename is "Filename")
  local is_header = filename == "Filename"

  local parts = {}

  if is_header then
    -- Header: add left padding to align with content rows (selector + icon)
    local left_padding = string.rep(" ", 1 + widths.icon_width) -- selector + icon (no extra space)
    table.insert(parts, left_padding .. string.format("%-" .. widths.filename_width .. "s", filename))
  else
    -- Content: include selector and icon with proper spacing
    table.insert(parts, selector)
    table.insert(parts, string.format("%-" .. widths.icon_width .. "s", icon))
    table.insert(parts, string.format("%-" .. widths.filename_width .. "s", filename))
  end

  if config.ui.show_git_branch and branch then
    table.insert(parts, string.format("%-" .. widths.branch_width .. "s", branch))
  end

  table.insert(parts, cwd)
  return table.concat(parts, " ")
end

return M
