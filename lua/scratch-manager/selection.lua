---Custom selection UI for scratch-manager.nvim
---Provides telescope-like interface for selecting scratch buffers

local M = {}

-- Load extracted modules
local ui = require("scratch-manager.ui")
local utils = require("scratch-manager.utils")

-- Selection UI state
local selection_ui = {
  buf = nil,
  win = nil,
  items = {},
  callback = nil,
  selected_idx = 1,
}

---Close the selection UI
---@private
local function close_selection_ui()
  if selection_ui.win and vim.api.nvim_win_is_valid(selection_ui.win) then
    vim.api.nvim_win_close(selection_ui.win, true)
  end
  if selection_ui.buf and vim.api.nvim_buf_is_valid(selection_ui.buf) then
    vim.api.nvim_buf_delete(selection_ui.buf, { force = true })
  end
  selection_ui.buf = nil
  selection_ui.win = nil
  selection_ui.items = {}
  selection_ui.callback = nil
  selection_ui.selected_idx = 1
end

---Update the selection display
---@param config table Configuration object
---@private
local function update_selection_display(config)
  if not selection_ui.buf or not vim.api.nvim_buf_is_valid(selection_ui.buf) then
    return
  end

  -- Calculate optimal layout for current items
  local layout = ui.calculate_optimal_layout(selection_ui.items, config)
  local widths = layout.column_widths
  local win_width = layout.window_width
  local lines = {}

  -- Add header using centralized formatting with intelligent header detection
  local header = utils.format_columns(" ", "", "Filename",
    config.ui.show_git_branch and "Branch" or nil,
    "Working Directory", widths, config)
  table.insert(lines, header)

  -- Add separator line
  local separator_width = win_width - 2 -- Account for window borders
  table.insert(lines, string.rep("─", separator_width))

  -- Add items
  for i, item in ipairs(selection_ui.items) do
    local line = ui.format_item_line(item, widths, i == selection_ui.selected_idx, config)
    table.insert(lines, line)
  end

  -- Update buffer content
  vim.api.nvim_set_option_value("modifiable", true, { buf = selection_ui.buf })
  vim.api.nvim_buf_set_lines(selection_ui.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = selection_ui.buf })
  vim.api.nvim_set_option_value("readonly", true, { buf = selection_ui.buf })

  -- Add highlighting
  local ns_id = vim.api.nvim_create_namespace("scratch-manager-select")
  vim.api.nvim_buf_clear_namespace(selection_ui.buf, ns_id, 0, -1)

  -- Highlight header with select-specific header highlight group
  vim.api.nvim_buf_add_highlight(selection_ui.buf, ns_id, "ScratchManagerSelectHeader", 0, 0, -1)
  -- Highlight separator with select-specific border highlight group
  vim.api.nvim_buf_add_highlight(selection_ui.buf, ns_id, "ScratchManagerSelectBorder", 1, 0, -1)

  -- Highlight selected item
  if selection_ui.selected_idx > 0 and selection_ui.selected_idx <= #selection_ui.items then
    local line_idx = selection_ui.selected_idx + 1 -- +2 for header, -1 for 0-based indexing
    vim.api.nvim_buf_add_highlight(selection_ui.buf, ns_id, "Visual", line_idx, 0, -1)
  end

  -- Set cursor position (accounting for header)
  if selection_ui.win and vim.api.nvim_win_is_valid(selection_ui.win) then
    vim.api.nvim_win_set_cursor(selection_ui.win, { selection_ui.selected_idx + 2, 0 })
  end
end

---Update only the selection highlighting (fast)
---@private
local function update_selection_highlighting()
  if not selection_ui.buf or not vim.api.nvim_buf_is_valid(selection_ui.buf) then
    return
  end

  local ns_id = vim.api.nvim_create_namespace("scratch-manager-select")
  vim.api.nvim_buf_clear_namespace(selection_ui.buf, ns_id, 0, -1)

  -- Re-highlight header and separator (these don't change)
  vim.api.nvim_buf_add_highlight(selection_ui.buf, ns_id, "ScratchManagerHeader", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(selection_ui.buf, ns_id, "ScratchManagerSeparator", 1, 0, -1)

  -- Highlight selected item
  if selection_ui.selected_idx > 0 and selection_ui.selected_idx <= #selection_ui.items then
    local line_idx = selection_ui.selected_idx + 1 -- +2 for header, -1 for 0-based indexing
    vim.api.nvim_buf_add_highlight(selection_ui.buf, ns_id, "Visual", line_idx, 0, -1)
  end

  -- Set cursor position (accounting for header)
  if selection_ui.win and vim.api.nvim_win_is_valid(selection_ui.win) then
    vim.api.nvim_win_set_cursor(selection_ui.win, { selection_ui.selected_idx + 2, 0 })
  end
end

---Handle key press in selection UI
---@param key string The pressed key
---@param config table Configuration object
---@private
local function handle_selection_key(key, config)
  if key == "j" or key == "<Down>" then
    selection_ui.selected_idx = math.min(selection_ui.selected_idx + 1, #selection_ui.items)
    update_selection_highlighting() -- Fast update, no rebuilding
  elseif key == "k" or key == "<Up>" then
    selection_ui.selected_idx = math.max(selection_ui.selected_idx - 1, 1)
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
  selection_ui.selected_idx = 1

  -- Calculate optimal window size and column widths
  local layout = ui.calculate_optimal_layout(items, config)
  local width = layout.window_width
  local widths = layout.column_widths
  local height = math.min(#items + 3, math.floor(vim.o.lines * 0.8)) -- +3 for header

  -- Create buffer
  selection_ui.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(selection_ui.buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(selection_ui.buf, "filetype", "scratch-manager-select")
  -- Start as modifiable, update_selection_display will set readonly after content is added

  -- Create window
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = opts.prompt or "Select Scratch Buffer",
    title_pos = "center",
  }

  selection_ui.win = vim.api.nvim_open_win(selection_ui.buf, true, win_opts)

  -- Apply custom highlight groups for selection window
  vim.api.nvim_set_option_value("winhighlight",
    "FloatBorder:ScratchManagerSelectBorder,FloatTitle:ScratchManagerTitle",
    { win = selection_ui.win })

  -- Set up keymaps
  local keymap_opts = { buffer = selection_ui.buf, nowait = true, silent = true }
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

  -- Close on buffer leave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = selection_ui.buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if selection_ui.callback then
          selection_ui.callback(nil)
        end
        close_selection_ui()
      end)
    end,
  })

  -- Initial display
  update_selection_display(config)
end

-- Expose internal functions for testing (following established pattern)
M._close_selection_ui = close_selection_ui
M._update_selection_display = update_selection_display
M._handle_selection_key = handle_selection_key

return M
