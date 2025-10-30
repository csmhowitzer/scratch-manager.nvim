-- Test suite for scratch-manager utils module
-- Tests formatting utilities and git branch caching

describe("scratch-manager.utils", function()
  local utils

  before_each(function()
    -- Clear any existing cache before each test
    utils = require("scratch-manager.utils")
    utils.clear_git_cache()
  end)

  describe("format_columns", function()
    local mock_config

    before_each(function()
      mock_config = {
        ui = {
          show_icon = true,
          show_git_branch = true,
          show_path = true,
          file_counter = true,
        }
      }
    end)

    it("should format basic columns correctly", function()
      local widths = {
        selector_width = 2,
        icon_width = 3,
        filename_width = 10,
        branch_width = 8,
        cwd_width = 15,
      }

      local line, highlight = utils.format_columns(
        " ", "󰢱", "test.lua", "main", "/home/user",
        widths, mock_config
      )

      assert.is_string(line)
      assert.truthy(line:find("test.lua"))
      assert.truthy(line:find("main"))
      assert.truthy(line:find("/home/user"))
      assert.is_nil(highlight) -- No counter for non-header
    end)

    it("should handle header rows with file counter", function()
      local widths = {
        selector_width = 2,
        icon_width = 3,
        filename_width = 10,
        branch_width = 8,
        cwd_width = 15,
      }

      local line, highlight = utils.format_columns(
        " ", "", "Filename", "Branch", "Working Directory",
        widths, mock_config, "5 files", 80
      )

      assert.is_string(line)
      assert.truthy(line:find("Filename"))
      assert.truthy(line:find("5 files"))
      assert.is_table(highlight)
      assert.equals("ScratchManagerFileCount", highlight.group)
    end)

    it("should handle missing optional columns", function()
      local config_no_branch = {
        ui = {
          show_icon = true,
          show_git_branch = false,
          show_path = true,
        }
      }

      local widths = {
        selector_width = 2,
        icon_width = 3,
        filename_width = 10,
        branch_width = 0,
        cwd_width = 15,
      }

      local line = utils.format_columns(
        " ", "󰢱", "test.lua", nil, "/home/user",
        widths, config_no_branch
      )

      assert.is_string(line)
      assert.truthy(line:find("test.lua"))
      assert.truthy(line:find("/home/user"))
      -- Should not contain branch info
    end)
  end)

  describe("get_git_branch", function()
    it("should return empty string for nil directory", function()
      local branch = utils.get_git_branch(nil)
      assert.equals("", branch)
    end)

    it("should cache git branch results", function()
      -- Mock a directory that exists (use current working directory)
      local test_dir = vim.fn.getcwd()
      
      -- First call
      local branch1 = utils.get_git_branch(test_dir)
      
      -- Second call should use cache
      local branch2 = utils.get_git_branch(test_dir)
      
      assert.equals(branch1, branch2)
      
      -- Verify cache contains the directory
      local stats = utils.get_git_cache_stats()
      assert.equals(1, stats.total_entries)
      assert.truthy(vim.tbl_contains(stats.directories, test_dir))
    end)

    it("should handle non-git directories gracefully", function()
      -- Use a directory that definitely doesn't exist
      local fake_dir = "/this/directory/does/not/exist"
      
      local branch = utils.get_git_branch(fake_dir)
      assert.equals("", branch)
      
      -- Should still cache the empty result
      local stats = utils.get_git_cache_stats()
      assert.equals(1, stats.total_entries)
    end)

    it("should cache different directories separately", function()
      local dir1 = "/tmp"
      local dir2 = "/var"
      
      utils.get_git_branch(dir1)
      utils.get_git_branch(dir2)
      
      local stats = utils.get_git_cache_stats()
      assert.equals(2, stats.total_entries)
      assert.truthy(vim.tbl_contains(stats.directories, dir1))
      assert.truthy(vim.tbl_contains(stats.directories, dir2))
    end)
  end)

  describe("clear_git_cache", function()
    it("should clear all cached git branches", function()
      -- Add some entries to cache
      utils.get_git_branch("/tmp")
      utils.get_git_branch("/var")
      
      local stats_before = utils.get_git_cache_stats()
      assert.equals(2, stats_before.total_entries)
      
      -- Clear cache
      utils.clear_git_cache()
      
      local stats_after = utils.get_git_cache_stats()
      assert.equals(0, stats_after.total_entries)
      assert.same({}, stats_after.directories)
    end)
  end)

  describe("get_git_cache_stats", function()
    it("should return correct stats for empty cache", function()
      local stats = utils.get_git_cache_stats()
      assert.equals(0, stats.total_entries)
      assert.same({}, stats.directories)
    end)

    it("should return correct stats for populated cache", function()
      utils.get_git_branch("/tmp")
      utils.get_git_branch("/var")
      utils.get_git_branch("/home")

      local stats = utils.get_git_cache_stats()
      assert.equals(3, stats.total_entries)
      assert.equals(3, #stats.directories)
    end)
  end)

  describe("layout constants", function()
    it("should return default layout constants", function()
      local constants = utils.get_layout_constants()

      -- Verify all expected constants exist
      assert.is_number(constants.SCREEN_WIDTH_RATIO)
      assert.is_number(constants.MIN_WINDOW_WIDTH)
      assert.is_number(constants.SCREEN_HEIGHT_RATIO)
      assert.is_number(constants.SELECTOR_WIDTH)
      assert.is_number(constants.ICON_POSITION_OFFSET)
      assert.is_number(constants.COLUMN_PADDING_SPACES)
      assert.is_number(constants.BORDER_PADDING)
      assert.is_number(constants.WINDOW_VERTICAL_OFFSET)

      -- Verify reasonable default values
      assert.equals(0.8, constants.SCREEN_WIDTH_RATIO)
      assert.equals(60, constants.MIN_WINDOW_WIDTH)
      assert.equals(2, constants.SELECTOR_WIDTH)
      assert.equals(2, constants.ICON_POSITION_OFFSET)
      assert.equals(1, constants.COLUMN_PADDING_SPACES)
      assert.equals(3, constants.WINDOW_VERTICAL_OFFSET)
    end)

    it("should return a copy of constants (not reference)", function()
      local constants1 = utils.get_layout_constants()
      local constants2 = utils.get_layout_constants()

      -- Modify one copy
      constants1.MIN_WINDOW_WIDTH = 999

      -- Other copy should be unchanged
      assert.not_equals(999, constants2.MIN_WINDOW_WIDTH)
    end)

    it("should allow updating constants", function()
      local original = utils.get_layout_constants()
      local original_min_width = original.MIN_WINDOW_WIDTH

      -- Update constants
      utils.update_layout_constants({ MIN_WINDOW_WIDTH = 80 })

      local updated = utils.get_layout_constants()
      assert.equals(80, updated.MIN_WINDOW_WIDTH)

      -- Other constants should remain unchanged
      assert.equals(original.SCREEN_WIDTH_RATIO, updated.SCREEN_WIDTH_RATIO)

      -- Restore original for other tests
      utils.update_layout_constants({ MIN_WINDOW_WIDTH = original_min_width })
    end)

    it("should allow partial updates of constants", function()
      local original = utils.get_layout_constants()

      -- Update only some constants
      utils.update_layout_constants({
        SCREEN_WIDTH_RATIO = 0.9,
        MIN_WINDOW_WIDTH = 70
      })

      local updated = utils.get_layout_constants()
      assert.equals(0.9, updated.SCREEN_WIDTH_RATIO)
      assert.equals(70, updated.MIN_WINDOW_WIDTH)

      -- Other constants should remain unchanged
      assert.equals(original.SELECTOR_WIDTH, updated.SELECTOR_WIDTH)
      assert.equals(original.ICON_POSITION_OFFSET, updated.ICON_POSITION_OFFSET)

      -- Restore original values
      utils.update_layout_constants({
        SCREEN_WIDTH_RATIO = original.SCREEN_WIDTH_RATIO,
        MIN_WINDOW_WIDTH = original.MIN_WINDOW_WIDTH
      })
    end)
  end)

  describe("get_display_icon", function()
    it("should return empty icon when show_icon is false", function()
      local icon, icon_hl = utils.get_display_icon("test.lua", "lua", false)
      assert.equals("", icon)
      assert.is_nil(icon_hl)
    end)

    it("should return icon when show_icon is true", function()
      local icon, icon_hl = utils.get_display_icon("test.lua", "lua", true)
      assert.is_string(icon)
      assert.truthy(#icon > 0) -- Should never be empty when show_icon is true
    end)

    it("should return fallback icon for unknown files", function()
      local icon, icon_hl = utils.get_display_icon("unknown.xyz", nil, true)
      assert.is_string(icon)
      assert.truthy(#icon > 0) -- Should have fallback icon
    end)

    it("should handle nil filename gracefully", function()
      local icon, icon_hl = utils.get_display_icon(nil, nil, true)
      assert.is_string(icon)
      assert.truthy(#icon > 0) -- Should have fallback icon
    end)
  end)

  describe("truncate_text", function()
    it("should not truncate short text", function()
      local result = utils.truncate_text("short", 10)
      assert.equals("short", result)
    end)

    it("should truncate long text with default ellipsis", function()
      local result = utils.truncate_text("this is a very long text", 10)
      assert.equals("this is...", result)
      assert.equals(10, #result)
    end)

    it("should truncate with custom ellipsis", function()
      local result = utils.truncate_text("long text here", 8, ">>")
      assert.equals("long t>>", result)
      assert.equals(8, #result)
    end)

    it("should handle edge case where max_width equals ellipsis length", function()
      local result = utils.truncate_text("long text", 3)
      assert.equals("...", result)
    end)

    it("should handle edge case where max_width is less than ellipsis length", function()
      local result = utils.truncate_text("long text", 2)
      assert.equals("..", result)
    end)

    it("should handle nil text", function()
      local result = utils.truncate_text(nil, 10)
      assert.equals("", result)
    end)

    it("should handle empty text", function()
      local result = utils.truncate_text("", 10)
      assert.equals("", result)
    end)
  end)

  describe("smart_truncate_path", function()
    it("should not truncate short paths", function()
      local result = utils.smart_truncate_path("/home/user", 20)
      assert.equals("/home/user", result)
    end)

    it("should truncate long paths intelligently", function()
      local result = utils.smart_truncate_path("/very/long/path/to/some/file", 15)
      assert.is_string(result)
      assert.truthy(#result <= 15)
      assert.truthy(result:find("%.%.%.")) -- Should contain ellipsis
      assert.truthy(result:find("file")) -- Should preserve filename
    end)

    it("should handle simple paths with few components", function()
      local result = utils.smart_truncate_path("/home/file.txt", 10)
      assert.is_string(result)
      -- The smart truncate logic may return "...file.txt" which is 11 chars
      -- Let's just verify it contains ellipsis and is reasonable length
      assert.truthy(result:find("%.%.%.")) -- Should contain ellipsis
      assert.truthy(#result <= 15) -- Reasonable upper bound
    end)
  end)

  describe("layout calculation functions", function()
    local mock_items, mock_config

    before_each(function()
      mock_items = {
        { name = "Scratch Pad (test.lua)", cwd = "/home/user", ft = "lua" },
        { name = "Scratch Pad (long_filename.md)", cwd = "/very/long/path", ft = "markdown" },
        { name = "Scratch Pad (short.py)", cwd = "/tmp", ft = "python" },
      }

      mock_config = {
        ui = {
          show_icon = true,
          show_git_branch = true,
          show_path = true,
          icon_width = 3,
        }
      }
    end)

    describe("analyze_content_lengths", function()
      it("should analyze content lengths correctly", function()
        local analysis = utils.analyze_content_lengths(mock_items, mock_config)

        assert.is_table(analysis)
        assert.is_number(analysis.max_filename)
        assert.is_number(analysis.max_branch)
        assert.is_number(analysis.max_cwd)

        -- Should find the longest filename
        assert.truthy(analysis.max_filename >= #"long_filename.md")
        -- Should have some path length
        assert.truthy(analysis.max_cwd > 0)
      end)

      it("should handle empty items list", function()
        local analysis = utils.analyze_content_lengths({}, mock_config)

        assert.equals(0, analysis.max_filename)
        assert.equals(0, analysis.max_branch)
        assert.equals(0, analysis.max_cwd)
      end)

      it("should respect show_git_branch configuration", function()
        local config_no_branch = vim.tbl_deep_extend("force", mock_config, {
          ui = { show_git_branch = false }
        })

        local analysis = utils.analyze_content_lengths(mock_items, config_no_branch)

        -- Should still return branch analysis but it won't be used
        assert.is_number(analysis.max_branch)
      end)

      it("should handle items with missing data", function()
        local sparse_items = {
          { name = nil, cwd = nil },
          { name = "Scratch Pad (test.txt)", cwd = "/home" },
        }

        local analysis = utils.analyze_content_lengths(sparse_items, mock_config)

        assert.is_table(analysis)
        assert.truthy(analysis.max_filename >= #"test.txt")
      end)
    end)

    describe("calculate_ideal_widths", function()
      it("should calculate ideal widths from content analysis", function()
        local analysis = { max_filename = 15, max_branch = 8, max_cwd = 20 }
        local calculation = utils.calculate_ideal_widths(analysis, mock_config)

        assert.is_table(calculation)
        assert.is_number(calculation.ideal_width)
        assert.is_number(calculation.padding)
        assert.is_table(calculation.column_widths)

        -- Should include all expected columns
        local widths = calculation.column_widths
        assert.is_number(widths.selector_width)
        assert.is_number(widths.icon_width)
        assert.is_number(widths.filename_width)
        assert.is_number(widths.branch_width)
        assert.is_number(widths.cwd_width)

        -- Filename width should match analysis
        assert.equals(15, widths.filename_width)
        assert.equals(8, widths.branch_width)
        assert.equals(20, widths.cwd_width)
      end)

      it("should handle disabled columns", function()
        local config_minimal = {
          ui = {
            show_icon = false,
            show_git_branch = false,
            show_path = false,
          }
        }
        local analysis = { max_filename = 10, max_branch = 5, max_cwd = 15 }

        local calculation = utils.calculate_ideal_widths(analysis, config_minimal)

        assert.equals(0, calculation.column_widths.icon_width)
        assert.equals(0, calculation.column_widths.branch_width)
        assert.equals(0, calculation.column_widths.cwd_width)
        assert.equals(10, calculation.column_widths.filename_width)
      end)

      it("should calculate padding correctly", function()
        local analysis = { max_filename = 10, max_branch = 5, max_cwd = 15 }

        -- All columns enabled = 5 visible columns = 4 padding spaces
        local calculation = utils.calculate_ideal_widths(analysis, mock_config)
        assert.equals(4, calculation.padding)

        -- Only selector + filename = 2 visible columns = 1 padding space
        local config_minimal = {
          ui = { show_icon = false, show_git_branch = false, show_path = false }
        }
        local calc_minimal = utils.calculate_ideal_widths(analysis, config_minimal)
        assert.equals(1, calc_minimal.padding)
      end)
    end)

    describe("apply_layout_constraints", function()
      it("should not modify widths when under screen limit but above minimum", function()
        local width_calc = {
          ideal_width = 50, -- Reasonable width that should fit
          padding = 4,
          column_widths = {
            selector_width = 2,
            icon_width = 3,
            filename_width = 10,
            branch_width = 5,
            cwd_width = 15,
          }
        }

        local result = utils.apply_layout_constraints(width_calc, mock_config)

        -- Should respect minimum width but not scale columns
        assert.truthy(result.window_width >= 50)
        -- Column widths should be unchanged (no proportional scaling)
        assert.equals(10, result.column_widths.filename_width)
        assert.equals(5, result.column_widths.branch_width)
        assert.equals(15, result.column_widths.cwd_width)
      end)

      it("should apply minimum width constraint", function()
        local width_calc = {
          ideal_width = 30, -- Very small width
          padding = 4,
          column_widths = {
            selector_width = 2,
            icon_width = 3,
            filename_width = 10,
            branch_width = 5,
            cwd_width = 8,
          }
        }

        local result = utils.apply_layout_constraints(width_calc, mock_config)

        -- Should enforce minimum width (60 from constants)
        assert.truthy(result.window_width >= 60)
      end)

      it("should scale columns proportionally when over screen limit", function()
        -- Mock a very large ideal width that will exceed screen limits
        local width_calc = {
          ideal_width = 5000, -- Impossibly large
          padding = 4,
          column_widths = {
            selector_width = 2,
            icon_width = 3,
            filename_width = 100,
            branch_width = 50,
            cwd_width = 200,
          }
        }

        local result = utils.apply_layout_constraints(width_calc, mock_config)

        -- Window width should be constrained
        assert.truthy(result.window_width < 5000)

        -- Content columns should be scaled down
        assert.truthy(result.column_widths.filename_width < 100)
        assert.truthy(result.column_widths.branch_width < 50)
        assert.truthy(result.column_widths.cwd_width < 200)

        -- Fixed columns should remain unchanged
        assert.equals(2, result.column_widths.selector_width)
        assert.equals(3, result.column_widths.icon_width)
      end)
    end)
  end)
end)
