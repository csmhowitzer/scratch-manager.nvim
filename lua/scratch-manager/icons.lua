---Icon management for scratch-manager.nvim
---Handles nerd font detection, icon mapping, and fallback behavior

local M = {}

---Auto-detect Nerd Font support by testing character rendering
---@return boolean has_nerd_font True if Nerd Font appears to be supported
function M.detect_nerd_font()
  -- Test if Nerd Font characters render as single-width
  local test_chars = { "󰢱", "󰍔", "󰘦" } -- lua, markdown, json icons
  for _, char in ipairs(test_chars) do
    if vim.fn.strdisplaywidth(char) == 1 then
      return true
    end
  end
  return false
end

---Get icon for file based on extension
---@param filename string The filename to get icon for
---@return string icon The appropriate icon character
function M.get_icon_for_file(filename)
  local ext = filename:match("%.([^%.]+)$")

  -- Debug: uncomment to see what's happening
  -- print("Icon for '" .. filename .. "' (ext: '" .. (ext or "nil") .. "')")

  if vim.g.have_nerd_font then
    -- Nerd Font icons (copied from nerdfonts.com/cheat-sheet)
    if ext == "lua" then
      return "󰢱" -- nf-seti-lua
    elseif ext == "py" then
      return "󰌠" -- nf-dev-python
    elseif ext == "js" then
      return "󰌞" -- nf-dev-javascript
    elseif ext == "ts" then
      return "󰛦" -- nf-seti-typescript
    elseif ext == "md" then
      return "󰍔" -- nf-dev-markdown
    elseif ext == "json" then
      return "󰘦" -- nf-seti-json
    elseif ext == "cs" then
      return "󰌛" -- nf-dev-dotnet
    elseif ext == "html" then
      return "󰌝" -- nf-dev-html5
    elseif ext == "css" then
      return "" -- nf-dev-css3
    elseif ext == "vim" then
      return "" -- nf-dev-vim
    elseif ext == "sh" or ext == "bash" then
      return "" -- nf-dev-terminal
    elseif ext == "txt" then
      return "" -- nf-fa-file_text_o
    elseif not ext or ext == "" then
      return "-" -- fallback for no extension or empty extension
    else
      return "-" -- fallback for unknown extension
    end
  else
    -- Unicode fallbacks
    if ext == "lua" then
      return "🌙"
    elseif ext == "py" then
      return "🐍"
    elseif ext == "js" or ext == "ts" then
      return "📜"
    elseif ext == "md" then
      return "📝"
    elseif ext == "json" then
      return "📋"
    elseif ext == "cs" then
      return "🔷"
    elseif ext == "html" then
      return "🌐"
    elseif ext == "css" then
      return "🎨"
    elseif ext == "vim" then
      return "📝"
    elseif ext == "sh" or ext == "bash" then
      return "💻"
    elseif ext == "txt" then
      return "📄"
    elseif not ext or ext == "" then
      return "📄" -- no extension or empty extension
    else
      return "📄" -- unknown extension
    end
  end
end

---Get icon for filetype (used for scratch buffers with actual filetype)
---@param filetype string The filetype to get icon for
---@return string icon The appropriate icon character
function M.get_icon_for_filetype(filetype)
  if vim.g.have_nerd_font then
    -- Nerd Font icons based on filetype
    if filetype == "lua" then
      return "󰢱" -- nf-seti-lua
    elseif filetype == "python" then
      return "󰌠" -- nf-dev-python
    elseif filetype == "javascript" then
      return "󰌞" -- nf-dev-javascript
    elseif filetype == "typescript" then
      return "󰛦" -- nf-seti-typescript
    elseif filetype == "markdown" then
      return "󰍔" -- nf-dev-markdown
    elseif filetype == "json" then
      return "󰘦" -- nf-seti-json
    elseif filetype == "cs" then
      return "󰌛" -- nf-dev-dotnet
    elseif filetype == "c" then
      return "󰙱" -- nf-seti-c
    elseif filetype == "cpp" then
      return "󰙲" -- nf-seti-cpp
    elseif filetype == "go" then
      return "󰟓" -- nf-seti-go
    elseif filetype == "rs" then
      return "󱘗" -- nf-dev-rust
    elseif filetype == "html" then
      return "󰌝" -- nf-dev-html5
    elseif filetype == "css" then
      return "" -- nf-dev-css3
    elseif filetype == "vim" then
      return "" -- nf-dev-vim
    elseif filetype == "sh" or filetype == "bash" then
      return "" -- nf-dev-terminal
    elseif filetype == "text" or filetype == "txt" then
      return "" -- nf-fa-file_text_o
    else
      return "-" -- fallback for unknown filetype
    end
  else
    -- Unicode fallbacks based on filetype
    if filetype == "lua" then
      return "🌙"
    elseif filetype == "python" then
      return "🐍"
    elseif filetype == "javascript" or filetype == "typescript" then
      return "📜"
    elseif filetype == "markdown" then
      return "📝"
    elseif filetype == "json" then
      return "📋"
    elseif filetype == "cs" then
      return "🔷"
    elseif filetype == "html" then
      return "🌐"
    elseif filetype == "css" then
      return "🎨"
    elseif filetype == "vim" then
      return "📝"
    elseif filetype == "sh" or filetype == "bash" then
      return "💻"
    elseif filetype == "text" or filetype == "txt" then
      return "📄"
    else
      return "📄" -- unknown filetype
    end
  end
end

---Initialize nerd font support if not already configured
function M.setup_nerd_font()
  if vim.g.have_nerd_font == nil then
    -- Try to auto-detect, fallback to detected value
    vim.g.have_nerd_font = M.detect_nerd_font()
  end
end

return M
