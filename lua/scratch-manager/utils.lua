---Utility functions for scratch-manager.nvim
---Shared formatting and helper functions

local M = {}

-- Git branch cache for session-level persistence
-- Key: directory path, Value: { branch: string, timestamp: number }
local git_branch_cache = {}

-- Layout calculation constants
local LAYOUT_CONSTANTS = {
  -- Window sizing
  SCREEN_WIDTH_RATIO = 0.8,     -- Maximum window width as ratio of screen width
  MIN_WINDOW_WIDTH = 60,        -- Minimum window width in characters
  SCREEN_HEIGHT_RATIO = 0.8,    -- Maximum window height as ratio of screen height

  -- Column spacing and positioning
  SELECTOR_WIDTH = 2,           -- Width reserved for selection indicator
  ICON_POSITION_OFFSET = 2,     -- 0-based position where icons start (after selector + space)
  COLUMN_PADDING_SPACES = 1,    -- Number of spaces between each column

  -- Border and padding
  BORDER_PADDING = 4,           -- Total padding for window borders
  WINDOW_VERTICAL_OFFSET = 3,   -- Vertical offset for window positioning
}

---Format columns into a consistent layout
---This ensures header and content rows use identical formatting
---@param selector string Selector column content (space or arrow)
---@param icon string Icon column content
---@param filename string Filename column content
---@param branch string|nil Branch column content (optional)
---@param cwd string Working directory column content
---@param widths table Column width configuration
---@param config table Configuration object
---@param counter_text string|nil File counter text (header only)
---@param win_width number|nil Window width for right-alignment (header only)
---@return string Formatted line
---@return table|nil Highlight information for counter (header only)
function M.format_columns(selector, icon, filename, branch, cwd, widths, config, counter_text, win_width)
  -- Detect if this is a header row (filename is "Filename")
  local is_header = filename == "Filename"

  local parts = {}

  if is_header then
    -- Header: calculate left padding based on visible columns
    local left_padding = ""
    if config.ui.show_icon then
      left_padding = string.rep(" ", 1 + widths.icon_width) -- selector + icon width + space
    else
      left_padding = "  " -- selector + space (no icon column)
    end
    table.insert(parts, left_padding .. string.format("%-" .. widths.filename_width .. "s", filename))
  else
    -- Content: include selector
    table.insert(parts, selector)

    -- Include icon column if enabled
    if config.ui.show_icon then
      table.insert(parts, string.format("%-" .. widths.icon_width .. "s", icon))
    end

    -- Always include filename
    table.insert(parts, string.format("%-" .. widths.filename_width .. "s", filename))
  end

  -- Include branch column if enabled and branch provided
  if config.ui.show_git_branch and branch then
    table.insert(parts, string.format("%-" .. widths.branch_width .. "s", branch))
  end

  -- Include path column if enabled
  if config.ui.show_path then
    table.insert(parts, cwd)
  end

  local line = table.concat(parts, " ")
  local counter_highlight = nil

  -- Add file counter for header rows
  if is_header and counter_text and win_width then
    local base_line_length = #line
    local counter_length = #counter_text
    local available_space = win_width - base_line_length - counter_length - 4 -- 4 for border padding

    if available_space > 0 then
      local padding = string.rep(" ", available_space)
      line = line .. padding .. counter_text

      -- Calculate highlight position for the counter
      local counter_start = base_line_length + available_space
      local counter_end = counter_start + counter_length
      counter_highlight = {
        group = "ScratchManagerFileCount",
        start_col = counter_start,
        end_col = counter_end
      }
    end
  end

  return line, counter_highlight
end

---Get git branch for directory with session-level caching
---@param cwd string|nil Working directory
---@return string branch Git branch name or empty string
function M.get_git_branch(cwd)
  if not cwd then return "" end

  -- Check cache first
  local cached = git_branch_cache[cwd]
  if cached then
    return cached.branch
  end

  -- Execute git command
  local handle = io.popen("cd " .. vim.fn.shellescape(cwd) .. " && git branch --show-current 2>/dev/null")
  if not handle then
    -- Cache empty result to avoid repeated failures
    git_branch_cache[cwd] = { branch = "", timestamp = vim.loop.hrtime() }
    return ""
  end

  local result = handle:read("*a")
  handle:close()

  local branch = result and vim.trim(result) or ""

  -- Cache the result
  git_branch_cache[cwd] = { branch = branch, timestamp = vim.loop.hrtime() }

  return branch
end

---Clear git branch cache (useful for testing or manual refresh)
function M.clear_git_cache()
  git_branch_cache = {}
end

---Get git branch cache stats (for debugging/testing)
---@return table stats { total_entries: number, directories: string[] }
function M.get_git_cache_stats()
  local directories = {}
  for dir, _ in pairs(git_branch_cache) do
    table.insert(directories, dir)
  end
  return {
    total_entries = #directories,
    directories = directories
  }
end

---Get layout constants for UI calculations
---@return table constants Layout calculation constants
function M.get_layout_constants()
  return vim.deepcopy(LAYOUT_CONSTANTS)
end

---Update layout constants (for configuration or testing)
---@param new_constants table Partial or complete constants table
function M.update_layout_constants(new_constants)
  LAYOUT_CONSTANTS = vim.tbl_deep_extend("force", LAYOUT_CONSTANTS, new_constants)
end

---Get icon with proper fallback handling for UI consistency
---@param filename string The filename to get icon for
---@param filetype string|nil Optional filetype hint
---@param show_icon boolean Whether icons are enabled in config
---@return string icon The icon character (guaranteed non-empty if show_icon is true)
---@return string|nil icon_hl Highlight group for the icon (nil if no color)
function M.get_display_icon(filename, filetype, show_icon)
  if not show_icon then
    return "", nil
  end

  -- Load icon provider for colored icons
  local icon_provider = require("scratch-manager.icon_provider")

  -- Get icon with color support
  local icon_result = icon_provider.get_icon_with_color(filename, filetype or "")
  local icon = icon_result.icon
  local icon_hl = icon_result.hl

  -- Ensure icon is NEVER nil or empty for consistent spacing
  -- Every row must have an icon to maintain column alignment
  if not icon or icon == "" then
    icon = "󰈔"  -- Professional fallback icon for unknown file types
    icon_hl = nil  -- No highlight for fallback
  end

  return icon, icon_hl
end

---Truncate text with ellipsis if it exceeds max width
---@param text string Text to potentially truncate
---@param max_width number Maximum allowed width
---@param ellipsis string|nil Ellipsis string (defaults to "...")
---@return string truncated_text The text, truncated if necessary
function M.truncate_text(text, max_width, ellipsis)
  if not text or #text <= max_width then
    return text or ""
  end

  ellipsis = ellipsis or "..."
  local ellipsis_len = #ellipsis

  if max_width <= ellipsis_len then
    return ellipsis:sub(1, max_width)
  end

  return text:sub(1, max_width - ellipsis_len) .. ellipsis
end

---Smart truncate path to show most relevant parts (preserves existing logic)
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

---Analyze content to determine maximum lengths for each column
---@param items table List of scratch buffer items
---@param config table Configuration object
---@return table content_analysis { max_filename: number, max_branch: number, max_cwd: number }
function M.analyze_content_lengths(items, config)
  local max_filename = 0
  local max_branch = 0
  local max_cwd = 0

  -- Helper function to get scratch filename (matches ui.lua logic)
  local function get_scratch_filename(name)
    if not name then return "" end
    local match = name:match("Scratch Pad %((.+)%)")
    return match or name
  end

  -- Find the longest content in each column
  for _, item in ipairs(items) do
    local filename = get_scratch_filename(item.name or "")
    local branch = config.ui.show_git_branch and M.get_git_branch(item.cwd) or ""
    local cwd = item.cwd and vim.fn.fnamemodify(item.cwd, ":p:~") or ""

    max_filename = math.max(max_filename, #filename)
    max_branch = math.max(max_branch, #branch)
    max_cwd = math.max(max_cwd, #cwd)
  end

  return {
    max_filename = max_filename,
    max_branch = max_branch,
    max_cwd = max_cwd,
  }
end

---Calculate ideal column widths based on content and configuration
---@param content_analysis table Result from analyze_content_lengths
---@param config table Configuration object
---@return table width_calculation { ideal_width: number, column_widths: table, padding: number }
function M.calculate_ideal_widths(content_analysis, config)
  local constants = M.get_layout_constants()

  -- Start with actual content widths (no truncation)
  local selector_width = constants.SELECTOR_WIDTH
  local icon_width = config.ui.show_icon and config.ui.icon_width or 0
  local filename_width = content_analysis.max_filename
  local branch_width = config.ui.show_git_branch and content_analysis.max_branch or 0
  local cwd_width = config.ui.show_path and content_analysis.max_cwd or 0

  -- Calculate padding based on visible columns (spaces between columns)
  local visible_columns = 1 -- selector always visible
  if config.ui.show_icon then visible_columns = visible_columns + 1 end
  visible_columns = visible_columns + 1 -- filename always visible
  if config.ui.show_git_branch then visible_columns = visible_columns + 1 end
  if config.ui.show_path then visible_columns = visible_columns + 1 end
  local padding = (visible_columns - 1) * constants.COLUMN_PADDING_SPACES

  local ideal_width = selector_width + icon_width + filename_width + branch_width + cwd_width + padding

  return {
    ideal_width = ideal_width,
    padding = padding,
    column_widths = {
      selector_width = selector_width,
      icon_width = icon_width,
      filename_width = filename_width,
      branch_width = branch_width,
      cwd_width = cwd_width,
    }
  }
end

---Apply screen constraints and proportional scaling to column widths
---@param width_calculation table Result from calculate_ideal_widths
---@param config table Configuration object
---@return table final_layout { window_width: number, column_widths: table }
function M.apply_layout_constraints(width_calculation, config)
  local constants = M.get_layout_constants()
  local ideal_width = width_calculation.ideal_width
  local column_widths = vim.deepcopy(width_calculation.column_widths)
  local padding = width_calculation.padding

  -- Apply constraints
  local max_width = math.floor(vim.o.columns * constants.SCREEN_WIDTH_RATIO)
  local min_width = constants.MIN_WINDOW_WIDTH
  local window_width = math.max(min_width, math.min(ideal_width, max_width))

  -- If we hit max width, we need to truncate proportionally
  if ideal_width > max_width then
    local available_width = max_width - column_widths.selector_width - column_widths.icon_width - padding
    local total_content_width = column_widths.filename_width + column_widths.branch_width + column_widths.cwd_width

    if total_content_width > 0 then
      local content_ratio = available_width / total_content_width

      column_widths.filename_width = math.floor(column_widths.filename_width * content_ratio)
      column_widths.branch_width = config.ui.show_git_branch and math.floor(column_widths.branch_width * content_ratio) or 0
      column_widths.cwd_width = config.ui.show_path and (available_width - column_widths.filename_width - column_widths.branch_width) or 0
    end
  end

  return {
    window_width = window_width,
    column_widths = column_widths,
  }
end

-- Expose internal functions for testing (following established pattern)
-- Note: These functions were moved from ui.lua during refactoring
M._get_git_branch = M.get_git_branch
M._get_display_icon = M.get_display_icon
M._truncate_text = M.truncate_text
M._smart_truncate_path = M.smart_truncate_path
M._analyze_content_lengths = M.analyze_content_lengths
M._calculate_ideal_widths = M.calculate_ideal_widths
M._apply_layout_constraints = M.apply_layout_constraints

return M
