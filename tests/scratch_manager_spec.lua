-- Comprehensive test suite for scratch-manager.nvim
-- Following established testing patterns from other plugins

-- Mock snacks.nvim to avoid dependency in tests
local mock_scratch = setmetatable({
  open = function(opts)
    return { icon = opts.icon, file = opts.file, name = opts.name, ft = opts.ft, win = opts.win }
  end,

  list = function()
    return {} -- Empty list for basic tests
  end,

  select = function()
    return true -- Mock selection
  end
}, {
  __call = function(self, opts)
    return { name = opts.name, ft = opts.ft, win = opts.win }
  end
})

local mock_snacks = {
  scratch = mock_scratch,
  util = {
    icon = function(ft, type)
      return "📄" -- Simple mock icon
    end
  }
}

-- Override require for snacks at package level
local original_require = require
_G.require = function(module)
  if module == "snacks" then
    return mock_snacks
  end
  return original_require(module)
end

-- Also set it in package.loaded to ensure consistency
package.loaded["snacks"] = mock_snacks

describe("scratch-manager", function()
  local scratch_manager

  before_each(function()
    -- Ensure snacks mock is in place
    package.loaded["snacks"] = mock_snacks

    -- Reset module state
    package.loaded["scratch-manager"] = nil
    scratch_manager = require("scratch-manager")

    -- Reset vim state
    vim.api.nvim_clear_autocmds({})

    -- Mock vim functions that might not be available in test environment
    vim.o = vim.o or {}
    vim.o.columns = 120
    vim.api.nvim_win_get_height = vim.api.nvim_win_get_height or function() return 30 end
    vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function() return 1 end
    vim.api.nvim_buf_get_name = vim.api.nvim_buf_get_name or function() return "/test/file.lua" end
    vim.filetype = vim.filetype or { match = function() return "lua" end }
    vim.fn = vim.fn or {}
    -- Ensure vim.fn exists and mock fnamemodify properly
    vim.fn = vim.fn or {}
    vim.fn.fnamemodify = function(path, modifier)
      if modifier == ":h" then return "/test"
      elseif modifier == ":t" then return "file.lua"
      elseif modifier == ":p:~" then
        -- Convert absolute paths to home-relative paths
        if path == "/test" then return "~/test"
        elseif path:match("^/") then return "~" .. path
        else return path
        end
      end
      return path
    end
  end)

  after_each(function()
    -- Restore original require and clean up package.loaded
    _G.require = original_require
    package.loaded["snacks"] = nil
  end)

  describe("setup", function()
    it("should initialize with default config", function()
      scratch_manager.setup()
      assert.is_not_nil(scratch_manager.config)
      assert.equals("markdown", scratch_manager.config.default_filetype)
      assert.equals("#F7DC6F", scratch_manager.config.border_color)
      assert.equals("#a6d189", scratch_manager.config.dashboard_color)
      assert.equals("SnacksInputBorder", scratch_manager.config.border_highlight)
      assert.is_true(scratch_manager.config.enable_keymaps)
    end)

    it("should merge user config with defaults", function()
      scratch_manager.setup({
        default_filetype = "lua",
        border_color = "#FF0000",
        enable_keymaps = false
      })
      assert.equals("lua", scratch_manager.config.default_filetype)
      assert.equals("#FF0000", scratch_manager.config.border_color)
      assert.is_false(scratch_manager.config.enable_keymaps)
      -- Should preserve other defaults
      assert.equals("#a6d189", scratch_manager.config.dashboard_color)
      assert.equals("SnacksInputBorder", scratch_manager.config.border_highlight)
    end)

    it("should merge nested keymap config", function()
      scratch_manager.setup({
        keymaps = {
          toggle = "<leader>st",
          delete = "<leader>sd"
        }
      })
      assert.equals("<leader>st", scratch_manager.config.keymaps.toggle)
      assert.equals("<leader>sd", scratch_manager.config.keymaps.delete)
      -- Should preserve other keymap defaults
      assert.equals("=s", scratch_manager.config.keymaps.select)
      assert.equals("=c", scratch_manager.config.keymaps.toggle_lang)
    end)

    it("should handle nil config gracefully", function()
      scratch_manager.setup(nil)
      assert.is_not_nil(scratch_manager.config)
      assert.equals("markdown", scratch_manager.config.default_filetype)
    end)

    it("should handle empty config gracefully", function()
      scratch_manager.setup({})
      assert.is_not_nil(scratch_manager.config)
      assert.equals("markdown", scratch_manager.config.default_filetype)
    end)
  end)

  describe("core functionality", function()
    before_each(function()
      scratch_manager.setup() -- Initialize with defaults
    end)

    it("should open new scratch pad", function()
      local config = {
        width = 80,
        height = 24,
        ft = "markdown",
        fmtName = "Scratch Pad (test.lua)",
      }

      -- Should not throw error
      assert.has_no.errors(function()
        scratch_manager.open_new_scratch_pad(config)
      end)
    end)

    it("should open existing scratch pad", function()
      local config = {
        width = 80,
        height = 24,
        ft = "lua",
        fmtName = "Scratch Pad (test.lua)",
        icon = "📄",
        file = "/tmp/test_scratch.lua"
      }

      -- Should not throw error
      assert.has_no.errors(function()
        scratch_manager.open_scratch(config)
      end)
    end)

    it("should find existing scratch pad", function()
      local buffers = {
        {
          name = "Scratch Pad (test.lua)",
          cwd = "/test",
          file = "/tmp/scratch.lua",
          ft = "lua",
          icon = "📄"
        }
      }

      local config = {
        path = "~/test",
        name = "test.lua"
      }

      local result = scratch_manager.find_existing_scratch_pad(buffers, config)
      assert.is_not_nil(result)
      assert.equals("Scratch Pad (test.lua)", result.name)
      assert.equals("lua", result.ft)
    end)

    it("should return nil when scratch pad not found", function()
      local buffers = {
        {
          name = "Scratch Pad (other.lua)",
          cwd = "/other",
          file = "/tmp/other.lua",
          ft = "lua"
        }
      }

      local config = {
        path = "~/test",
        name = "test.lua"
      }

      local result = scratch_manager.find_existing_scratch_pad(buffers, config)
      assert.is_nil(result)
    end)
  end)

  describe("error handling", function()
    before_each(function()
      scratch_manager.setup()
    end)

    it("should assert when config missing path", function()
      local buffers = {}
      local config = { name = "test.lua" } -- Missing path

      assert.has_error(function()
        scratch_manager.find_existing_scratch_pad(buffers, config)
      end, "no path provided")
    end)

    it("should assert when config missing name", function()
      local buffers = {}
      local config = { path = "~/test" } -- Missing name

      assert.has_error(function()
        scratch_manager.find_existing_scratch_pad(buffers, config)
      end, "no filename provided")
    end)

    it("should handle empty buffers list", function()
      local buffers = {}
      local config = { path = "~/test", name = "test.lua" }

      local result = scratch_manager.find_existing_scratch_pad(buffers, config)
      assert.is_nil(result)
    end)

    it("should handle buffers with missing cwd", function()
      local buffers = {
        {
          name = "Scratch Pad (test.lua)",
          -- cwd is nil
          file = "/tmp/scratch.lua",
          ft = "lua"
        }
      }

      local config = { path = "", name = "test.lua" }

      local result = scratch_manager.find_existing_scratch_pad(buffers, config)
      assert.is_not_nil(result)
    end)
  end)

  describe("integration", function()
    before_each(function()
      scratch_manager.setup()
    end)

    it("should toggle scratch pad without errors", function()
      -- Mock vim.fn.delete for delete test
      vim.fn.delete = vim.fn.delete or function() return 0 end
      vim.fn.filereadable = vim.fn.filereadable or function() return 1 end

      assert.has_no.errors(function()
        scratch_manager.toggle_scratch_pad()
      end)
    end)

    it("should toggle scratch pad with filetype", function()
      assert.has_no.errors(function()
        scratch_manager.toggle_scratch_pad("lua")
      end)
    end)

    it("should delete current scratch pad without errors", function()
      -- Mock file operations
      vim.fn.delete = vim.fn.delete or function() return 0 end
      vim.fn.filereadable = vim.fn.filereadable or function() return 1 end

      assert.has_no.errors(function()
        scratch_manager.delete_current_scratch_pad()
      end)
    end)
  end)
end)
