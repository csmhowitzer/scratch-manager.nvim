-- Simple test script for icon provider functionality
-- Run with: nvim --headless -l test_icons.lua

-- Add plugin to path
local plugin_dir = vim.fn.getcwd()
package.path = plugin_dir .. "/lua/?.lua;" .. plugin_dir .. "/lua/?/init.lua;" .. package.path

-- Set up basic vim environment
vim.g.have_nerd_font = true

print("=== Icon Provider Test ===")

-- Test 1: Load icon provider
local ok, icon_provider = pcall(require, "scratch-manager.icon_provider")
if not ok then
  print("❌ Failed to load icon_provider:", icon_provider)
  return
end
print("✅ Icon provider loaded successfully")

-- Test 2: Check provider detection
local provider_name = icon_provider.get_provider_name()
print("📦 Provider detected:", provider_name)

-- Test 3: Test icon with color
local result = icon_provider.get_icon_with_color("test.lua", "lua")
print("🎨 Icon result:")
print("  - Icon:", result.icon)
print("  - Highlight:", result.hl or "none")

-- Test 4: Test different file types
local test_files = {
  {"test.lua", "lua"},
  {"README.md", "markdown"},
  {"script.py", "python"},
  {"style.css", "css"},
  {"unknown.xyz", nil}
}

print("\n🧪 Testing different file types:")
for _, test in ipairs(test_files) do
  local filename, filetype = test[1], test[2]
  local result = icon_provider.get_icon_with_color(filename, filetype)
  print(string.format("  %s -> %s (hl: %s)", filename, result.icon, result.hl or "none"))
end

-- Test 5: Check if colored icons are available
local has_colored = icon_provider.has_colored_icons()
print("\n🌈 Has colored icons:", has_colored)

-- Test 6: Test UI formatting with highlights
print("\n🎨 Testing UI formatting with highlights:")
local ok_ui, ui = pcall(require, "scratch-manager.ui")
if ok_ui then
  local test_item = {
    name = "Scratch Pad (test.lua)",
    ft = "lua",
    cwd = "/test/path"
  }
  local test_widths = {
    filename_width = 20,
    icon_width = 3,
    branch_width = 10,
    cwd_width = 25
  }
  local test_config = {
    ui = { show_git_branch = true }
  }

  local line, highlights = ui.format_item_line(test_item, test_widths, false, test_config)
  print("  Formatted line:", line)
  if highlights then
    local hl_group, col_start, col_end = unpack(highlights)
    print(string.format("  Highlight: %s at positions %d-%d", hl_group, col_start, col_end))
    -- Show what character is at that position
    local highlighted_char = line:sub(col_start + 1, col_end)
    print("  Highlighted text:", highlighted_char)
  else
    print("  No highlights (fallback mode)")
  end
else
  print("❌ Failed to load UI module:", ui)
end

print("\n=== Test Complete ===")
