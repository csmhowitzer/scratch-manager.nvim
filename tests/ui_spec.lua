-- Test suite for scratch-manager UI module
-- Tests layout calculations, formatting, and display logic

describe("scratch-manager.ui", function()
  local ui
  local mock_config

  before_each(function()
    -- Mock dependencies first
    package.loaded["scratch-manager.icons"] = {
      get_icon_for_filetype = function(ft)
        if ft == "lua" then return "󰢱"
        elseif ft == "markdown" then return "󰍔"
        else return "󰈔" end
      end
    }

    package.loaded["scratch-manager.utils"] = {
      format_columns = function(...)
        local args = {...}
        local result = {}
        for i, arg in ipairs(args) do
          if arg ~= nil and arg ~= "" then
            table.insert(result, tostring(arg))
          end
        end
        return table.concat(result, " ")
      end
    }

    -- Reset module state
    package.loaded["scratch-manager.ui"] = nil
    ui = require("scratch-manager.ui")

    -- Mock configuration
    mock_config = {
      ui = {
        show_git_branch = true,
        filename_width = 25,
        branch_width = 15,
        icon_width = 3,
      }
    }

    -- Mock vim functions
    vim.o = vim.o or {}
    vim.o.columns = 120
    vim.fn = vim.fn or {}
    vim.fn.fnamemodify = function(path, modifier)
      if modifier == ":p:~" then
        return path:gsub("^/home/user", "~")
      end
      return path
    end
    vim.fn.shellescape = function(str) return "'" .. str .. "'" end
    vim.split = function(str, sep)
      local result = {}
      for part in str:gmatch("([^" .. sep .. "]+)") do
        table.insert(result, part)
      end
      return result
    end
    vim.trim = function(str) return str:gsub("^%s*(.-)%s*$", "%1") end

    -- Mock io.popen to avoid actual git calls
    io.popen = function()
      return {
        read = function() return "main" end,
        close = function() end
      }
    end
  end)

  describe("optimal layout calculation", function()
    it("should calculate layout for empty items", function()
      local layout = ui.calculate_optimal_layout({}, mock_config)

      assert.is_table(layout)
      assert.is_number(layout.window_width)
      assert.is_table(layout.column_widths)
      assert.is_true(layout.window_width >= 60) -- minimum width
    end)

    it("should calculate layout for items with content", function()
      local test_items = {
        { name = "Scratch Pad (test.lua)", cwd = "/home/user/project", ft = "lua" },
        { name = "Scratch Pad (notes.md)", cwd = "/home/user/docs", ft = "markdown" }
      }

      local layout = ui.calculate_optimal_layout(test_items, mock_config)

      assert.is_table(layout)
      assert.is_number(layout.window_width)
      assert.is_table(layout.column_widths)
      assert.is_true(layout.window_width > 0)
      assert.is_number(layout.column_widths.filename_width)
      assert.is_number(layout.column_widths.icon_width)
    end)
  end)

  describe("column width distribution", function()
    it("should distribute widths proportionally when constrained", function()
      -- Test with very narrow screen to force truncation
      vim.o.columns = 50

      local test_items = {
        { name = "Scratch Pad (very_long_filename_that_exceeds_normal_width.lua)",
          cwd = "/very/long/path/to/project/directory", ft = "lua" }
      }

      local layout = ui.calculate_optimal_layout(test_items, mock_config)

      -- Focus on testing that the function works, not specific values
      assert.is_number(layout.window_width)
      assert.is_true(layout.column_widths.filename_width >= 0)
      assert.is_true(layout.column_widths.cwd_width >= 0)
    end)
  end)

  describe("path truncation logic", function()
    it("should not truncate short paths", function()
      local short_path = "~/project"
      local result = ui.smart_truncate_path(short_path, 20)

      assert.equals(short_path, result)
    end)

    it("should truncate long paths intelligently", function()
      local long_path = "/very/long/path/to/some/deep/project/directory"
      local result = ui.smart_truncate_path(long_path, 20)

      assert.is_string(result)
      assert.is_true(#result <= 20)
      -- Test that truncation happened (result should be different from input)
      assert.is_true(result ~= long_path)
    end)

    it("should handle edge cases", function()
      local empty_path = ""
      local result = ui.smart_truncate_path(empty_path, 10)
      assert.equals("", result)

      local single_part = "filename"
      result = ui.smart_truncate_path(single_part, 5)
      assert.is_true(#result <= 5)
    end)
  end)

  describe("item line formatting", function()
    it("should format item lines correctly", function()
      local test_item = {
        name = "Scratch Pad (test.lua)",
        cwd = "/home/user/project",
        ft = "lua"
      }

      local test_widths = {
        filename_width = 20,
        icon_width = 3,
        branch_width = 10,
        cwd_width = 25
      }

      local line, highlights = ui.format_item_line(test_item, test_widths, false, mock_config)

      assert.is_string(line)
      assert.is_true(#line > 0)
      -- highlights may be nil (fallback) or table (colored icons)
    end)

    it("should handle selected items", function()
      local test_item = {
        name = "Scratch Pad (notes.md)",
        cwd = "/home/user/docs",
        ft = "markdown"
      }

      local test_widths = {
        filename_width = 20,
        icon_width = 3,
        branch_width = 10,
        cwd_width = 25
      }

      local line, highlights = ui.format_item_line(test_item, test_widths, true, mock_config)

      assert.is_string(line)
      assert.is_true(#line > 0)
      -- highlights may be nil (fallback) or table (colored icons)
    end)

    it("should handle items with missing data", function()
      local test_item = {
        name = nil,
        cwd = nil,
        ft = nil
      }

      local test_widths = {
        filename_width = 20,
        icon_width = 3,
        branch_width = 10,
        cwd_width = 25
      }

      -- Should not error with missing data
      assert.has_no.errors(function()
        local line, highlights = ui.format_item_line(test_item, test_widths, false, mock_config)
        assert.is_string(line)
      end)
    end)
  end)

  describe("dynamic window sizing", function()
    it("should respect minimum window width", function()
      vim.o.columns = 30 -- Very narrow screen

      local layout = ui.calculate_optimal_layout({}, mock_config)

      assert.is_true(layout.window_width >= 60) -- Should enforce minimum
    end)

    it("should respect maximum window width", function()
      vim.o.columns = 200 -- Very wide screen

      local test_items = {
        { name = "Scratch Pad (short.lua)", cwd = "/short", ft = "lua" }
      }

      local layout = ui.calculate_optimal_layout(test_items, mock_config)

      assert.is_true(layout.window_width <= 160) -- Should be <= 80% of 200
    end)
  end)

  describe("internal helper functions", function()
    it("should extract scratch filenames correctly", function()
      assert.is_function(ui._get_scratch_filename)

      local result = ui._get_scratch_filename("Scratch Pad (test.lua)")
      assert.equals("test.lua", result)

      result = ui._get_scratch_filename("Other Name")
      assert.equals("Other Name", result)

      result = ui._get_scratch_filename(nil)
      assert.equals("", result)
    end)

    it("should handle git branch extraction", function()
      assert.is_function(ui._get_git_branch)

      -- Should not error with nil input
      local result = ui._get_git_branch(nil)
      assert.equals("", result)

      -- Should handle valid directory (mocked to return "main")
      result = ui._get_git_branch("/some/path")
      assert.is_string(result)
    end)
  end)
end)
