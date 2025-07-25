-- Test suite for scratch-manager icons module
-- Tests icon detection, nerd font support, and fallback behavior

describe("scratch-manager.icons", function()
  local icons = require("scratch-manager.icons")

  describe("get_icon_for_file", function()
    before_each(function()
      -- Ensure consistent test environment
      vim.g.have_nerd_font = true
    end)

    it("handles files with no extension", function()
      local icon = icons.get_icon_for_file("Profiler Picker Options")
      assert.is_not_nil(icon)
      assert.is_string(icon)
      assert.is_true(#icon > 0) -- Should have some icon, not empty
    end)

    it("handles files with empty extension", function()
      local icon = icons.get_icon_for_file("filename.")
      assert.is_not_nil(icon)
      assert.is_string(icon)
      assert.is_true(#icon > 0) -- Should have some icon, not empty
    end)

    it("handles files with spaces in name and no extension", function()
      local icon = icons.get_icon_for_file("My File Name")
      assert.is_not_nil(icon)
      assert.is_string(icon)
      assert.is_true(#icon > 0) -- Should have some icon, not empty
    end)

    it("handles known extensions", function()
      local icon = icons.get_icon_for_file("test.lua")
      assert.equals("󰢱", icon) -- lua icon
    end)
  end)

  pending("nerd font vs unicode fallback logic")
  pending("auto-detection of nerd font support")
  pending("icon width validation")
end)
