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

  describe("nerd font vs unicode fallback logic", function()
    it("should use nerd font icons when available", function()
      -- Mock nerd font availability
      vim.g.have_nerd_font = true

      local icon = icons.get_icon_for_filetype("lua")
      assert.is_string(icon)
      assert.truthy(#icon > 0)
      -- Nerd font icons are typically multi-byte
      assert.truthy(#icon >= 3) -- UTF-8 nerd font icons are usually 3+ bytes
    end)

    it("should fall back to unicode when nerd font unavailable", function()
      -- Mock no nerd font
      vim.g.have_nerd_font = false

      local icon = icons.get_icon_for_filetype("lua")
      assert.is_string(icon)
      assert.truthy(#icon > 0)
      -- Should still provide some icon (unicode fallback)
    end)
  end)

  describe("auto-detection of nerd font support", function()
    it("should detect nerd font availability", function()
      -- Test the detection logic exists
      local has_detection = type(icons.get_icon_for_filetype) == "function"
      assert.is_true(has_detection)

      -- Should handle both cases gracefully
      vim.g.have_nerd_font = true
      local icon_with_nerd = icons.get_icon_for_filetype("lua")

      vim.g.have_nerd_font = false
      local icon_without_nerd = icons.get_icon_for_filetype("lua")

      -- Both should return valid icons
      assert.is_string(icon_with_nerd)
      assert.is_string(icon_without_nerd)
    end)
  end)

  describe("icon width validation", function()
    it("should return consistent icon widths", function()
      local test_filetypes = {"lua", "javascript", "python", "markdown", "unknown"}

      for _, ft in ipairs(test_filetypes) do
        local icon = icons.get_icon_for_filetype(ft)
        assert.is_string(icon)
        assert.truthy(#icon > 0, "Icon should not be empty for filetype: " .. ft)

        -- Icon should have reasonable display width (1-2 characters visually)
        local display_width = vim.fn.strdisplaywidth and vim.fn.strdisplaywidth(icon) or #icon
        assert.truthy(display_width >= 1 and display_width <= 3,
                     "Icon display width should be 1-3 for filetype: " .. ft)
      end
    end)

    it("should handle edge cases gracefully", function()
      -- Test with nil, empty string, and unusual inputs
      local edge_cases = {nil, "", "   ", "unknown_extension", "file.with.many.dots.ext"}

      for _, case in ipairs(edge_cases) do
        local icon = icons.get_icon_for_filetype(case)
        assert.is_string(icon)
        assert.truthy(#icon > 0, "Should provide fallback icon for edge case: " .. tostring(case))
      end
    end)
  end)
end)
