-- Test suite for scratch-manager icon provider module
-- Tests provider detection, colored icons, and fallback behavior following oil.nvim patterns

describe("scratch-manager.icon_provider", function()
  local icon_provider
  local original_require = require
  local original_global_MiniIcons

  before_each(function()
    -- Reset module state
    package.loaded["scratch-manager.icon_provider"] = nil
    package.loaded["mini.icons"] = nil
    package.loaded["nvim-web-devicons"] = nil
    
    -- Store original global state
    original_global_MiniIcons = _G.MiniIcons
    _G.MiniIcons = nil
    
    icon_provider = require("scratch-manager.icon_provider")
  end)

  after_each(function()
    -- Restore original state
    _G.require = original_require
    _G.MiniIcons = original_global_MiniIcons
    package.loaded["mini.icons"] = nil
    package.loaded["nvim-web-devicons"] = nil
  end)

  describe("provider detection", function()
    it("detects mini.icons when available and setup", function()
      -- Mock mini.icons with global setup indicator
      _G.MiniIcons = { setup = true }
      local mock_mini_icons = {
        get = function(type, name)
          return "󰢱", "MiniIconsLua"
        end
      }
      package.loaded["mini.icons"] = mock_mini_icons
      
      local provider = icon_provider._get_icon_provider()
      assert.is_not_nil(provider)
      
      local icon, hl = provider("file", "test.lua")
      assert.equals("󰢱", icon)
      assert.equals("MiniIconsLua", hl)
    end)

    it("falls back to nvim-web-devicons when mini.icons not available", function()
      -- Ensure mini.icons is not available
      _G.MiniIcons = nil
      
      -- Mock nvim-web-devicons
      local mock_devicons = {
        get_icon = function(name)
          if name:match("%.lua$") then
            return "󰢱", "DevIconLua"
          end
          return "", nil
        end
      }
      package.loaded["nvim-web-devicons"] = mock_devicons
      
      local provider = icon_provider._get_icon_provider()
      assert.is_not_nil(provider)
      
      local icon, hl = provider("file", "test.lua")
      assert.equals("󰢱", icon)
      assert.equals("DevIconLua", hl)
    end)

    it("returns nil when no providers available", function()
      -- Ensure no providers are available
      _G.MiniIcons = nil
      package.loaded["mini.icons"] = nil
      package.loaded["nvim-web-devicons"] = nil
      
      local provider = icon_provider._get_icon_provider()
      assert.is_nil(provider)
    end)

    it("handles directory type correctly with devicons", function()
      _G.MiniIcons = nil
      local mock_devicons = {
        get_icon = function(name)
          return "📄", "DevIconDefault"
        end
      }
      package.loaded["nvim-web-devicons"] = mock_devicons
      
      local provider = icon_provider._get_icon_provider()
      local icon, hl = provider("directory", "test_dir")
      assert.equals("", icon) -- Default empty for directory
      assert.equals("OilDirIcon", hl)
    end)
  end)

  describe("get_icon_with_color", function()
    it("returns colored icon when provider available", function()
      -- Mock mini.icons
      _G.MiniIcons = { setup = true }
      local mock_mini_icons = {
        get = function(type, name)
          return "󰢱", "MiniIconsLua"
        end
      }
      package.loaded["mini.icons"] = mock_mini_icons
      
      local result = icon_provider.get_icon_with_color("test.lua", "lua")
      assert.equals("󰢱", result.icon)
      assert.equals("MiniIconsLua", result.hl)
    end)

    it("falls back to current icons when no provider", function()
      -- Ensure no providers available
      _G.MiniIcons = nil
      package.loaded["mini.icons"] = nil
      package.loaded["nvim-web-devicons"] = nil
      
      -- Mock vim.g.have_nerd_font for fallback
      vim.g.have_nerd_font = true
      
      local result = icon_provider.get_icon_with_color("test.lua", "lua")
      assert.equals("󰢱", result.icon) -- From current icons.lua
      assert.is_nil(result.hl) -- No color in fallback
    end)

    it("handles empty icon gracefully", function()
      _G.MiniIcons = nil
      local mock_devicons = {
        get_icon = function(name)
          return nil, nil -- No icon found
        end
      }
      package.loaded["nvim-web-devicons"] = mock_devicons
      
      local result = icon_provider.get_icon_with_color("unknown.xyz", nil)
      assert.equals("", result.icon) -- Empty icon from provider
      assert.is_nil(result.hl)
    end)
  end)

  describe("utility functions", function()
    it("has_colored_icons returns true when provider available", function()
      _G.MiniIcons = { setup = true }
      package.loaded["mini.icons"] = { get = function() return "", "" end }
      
      assert.is_true(icon_provider.has_colored_icons())
    end)

    it("has_colored_icons returns false when no provider", function()
      _G.MiniIcons = nil
      package.loaded["mini.icons"] = nil
      package.loaded["nvim-web-devicons"] = nil
      
      assert.is_false(icon_provider.has_colored_icons())
    end)

    it("get_provider_name returns correct provider", function()
      -- Test mini.icons
      _G.MiniIcons = { setup = true }
      package.loaded["mini.icons"] = { get = function() return "", "" end }
      assert.equals("mini.icons", icon_provider.get_provider_name())
      
      -- Test devicons fallback
      _G.MiniIcons = nil
      package.loaded["mini.icons"] = nil
      package.loaded["nvim-web-devicons"] = { get_icon = function() return "", "" end }
      assert.equals("nvim-web-devicons", icon_provider.get_provider_name())
      
      -- Test fallback
      package.loaded["nvim-web-devicons"] = nil
      assert.equals("fallback", icon_provider.get_provider_name())
    end)
  end)

  describe("fallback behavior", function()
    it("preserves existing icon logic", function()
      vim.g.have_nerd_font = true
      
      local result = icon_provider._get_fallback_icon("test.lua", "lua")
      assert.equals("󰢱", result.icon) -- From current icons.lua
      assert.is_nil(result.hl) -- No color in fallback
    end)

    it("handles filetype preference correctly", function()
      vim.g.have_nerd_font = true
      
      -- Test with filetype (should use get_icon_for_filetype)
      local result1 = icon_provider._get_fallback_icon("project.cs", "markdown")
      assert.equals("󰍔", result1.icon) -- Markdown icon, not C# icon
      
      -- Test without filetype (should use get_icon_for_file)
      local result2 = icon_provider._get_fallback_icon("project.cs", nil)
      assert.equals("󰌛", result2.icon) -- C# icon from filename
    end)
  end)
end)
