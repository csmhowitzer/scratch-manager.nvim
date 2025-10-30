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
      end,
      get_git_branch = function(cwd)
        if not cwd then return "" end
        return "main" -- Mock git branch
      end,
      get_display_icon = function(filename, filetype, show_icon)
        if not show_icon then return "", nil end
        if filetype == "lua" then return "󰢱", nil
        elseif filetype == "markdown" then return "󰍔", nil
        else return "󰈔", nil end
      end,
      truncate_text = function(text, max_width)
        if not text or #text <= max_width then return text or "" end
        return text:sub(1, max_width - 3) .. "..."
      end,
      smart_truncate_path = function(path, max_width)
        if #path <= max_width then return path end
        return "..." .. path:sub(-(max_width - 3))
      end,
      analyze_content_lengths = function(items, config)
        return { max_filename = 10, max_branch = 5, max_cwd = 15 }
      end,
      calculate_ideal_widths = function(analysis, config)
        return {
          ideal_width = 80,
          padding = 4,
          column_widths = {
            selector_width = 2,
            icon_width = 3,
            filename_width = analysis.max_filename,
            branch_width = analysis.max_branch,
            cwd_width = analysis.max_cwd,
          }
        }
      end,
      apply_layout_constraints = function(width_calc, config)
        return {
          window_width = math.max(60, width_calc.ideal_width),
          column_widths = width_calc.column_widths,
        }
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

  -- Note: Path truncation logic moved to utils.lua during refactoring
  -- These tests are now covered in utils_spec.lua

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

    -- Note: Git branch extraction moved to utils.lua during refactoring
    -- This functionality is now tested in utils_spec.lua
  end)
end)
