---Health check for scratch-manager.nvim
---Provides comprehensive diagnostics and validation for the plugin
---Following established patterns from m_augment and wsl2_roslyn health checks

local M = {}

---Check if a module can be loaded
---@param module_name string Name of the module to check
---@return boolean success True if module loads successfully
---@return string|nil error_msg Error message if loading fails
local function check_module_loadable(module_name)
  local success, result = pcall(require, module_name)
  if success then
    return true, nil
  else
    return false, tostring(result)
  end
end

---Check if a file exists and is readable
---@param filepath string Path to the file
---@return boolean exists True if file exists and is readable
local function check_file_exists(filepath)
  local expanded_path = vim.fn.expand(filepath)
  return vim.fn.filereadable(expanded_path) == 1
end

---Check if a directory exists
---@param dirpath string Path to the directory
---@return boolean exists True if directory exists
local function check_directory_exists(dirpath)
  local expanded_path = vim.fn.expand(dirpath)
  local stat = vim.loop.fs_stat(expanded_path)
  return stat and stat.type == "directory"
end

---Check Neovim version compatibility
local function check_neovim_version()
  vim.health.start("scratch-manager Neovim Compatibility")
  
  local version = vim.version()
  local version_str = string.format('%s.%s.%s', version.major, version.minor, version.patch)
  
  -- Require Neovim 0.9.0+ for modern health check API
  if vim.version.cmp(version, { 0, 9, 0 }) >= 0 then
    vim.health.ok("Neovim version: " .. version_str .. " (compatible)")
  else
    vim.health.error("Neovim version: " .. version_str .. " (requires 0.9.0+)",
      "Upgrade to Neovim 0.9.0 or later")
  end
end

---Check core dependencies
local function check_dependencies()
  vim.health.start("scratch-manager Dependencies")
  
  local dependencies = {
    { name = "folke/snacks.nvim", module = "snacks", required = true },
    { name = "nvim-lua/plenary.nvim", module = "plenary", required = false, note = "Required for testing" },
  }
  
  for _, dep in ipairs(dependencies) do
    local success, error_msg = check_module_loadable(dep.module)
    if success then
      vim.health.ok(dep.name .. " - available")
      
      -- Additional checks for snacks.nvim
      if dep.module == "snacks" then
        local snacks = require("snacks")
        if snacks.scratch then
          vim.health.ok("snacks.scratch module - available")
        else
          vim.health.error("snacks.scratch module - missing",
            "Update snacks.nvim to a version that includes scratch functionality")
        end
        
        if snacks.util and snacks.util.icon then
          vim.health.ok("snacks.util.icon function - available")
        else
          vim.health.warn("snacks.util.icon function - missing",
            "Icon display may not work properly")
        end
      end
    else
      if dep.required then
        vim.health.error(dep.name .. " - missing (required)", 
          "Install with your plugin manager: " .. dep.name)
      else
        vim.health.warn(dep.name .. " - missing (optional)", 
          dep.note or "Some features may not be available")
      end
    end
  end
end

---Check nerd font availability
local function check_nerd_font()
  vim.health.start("scratch-manager Icon Support")

  -- Test Nerd Font character rendering (same icons as used in plugin)
  local test_chars = {
    { char = "󰢱", name = "lua icon", ext = "lua" },
    { char = "󰍔", name = "markdown icon", ext = "md" },
    { char = "󰘦", name = "json icon", ext = "json" },
    { char = "󰌛", name = "C# icon", ext = "cs" },
  }

  local passing_tests = 0
  for _, test in ipairs(test_chars) do
    local width = vim.fn.strdisplaywidth(test.char)
    if width == 1 then
      passing_tests = passing_tests + 1
      vim.health.ok(string.format("%s renders correctly (width: %d)", test.name, width))
    else
      vim.health.warn(string.format("%s renders incorrectly (width: %d, expected: 1)", test.name, width))
    end
  end

  local detected_nerd_font = passing_tests >= 2

  -- Primary assessment based on character width test
  if detected_nerd_font then
    vim.health.ok("Nerd Font support - detected and working")
    vim.health.info("Icons will display correctly")
  else
    vim.health.warn("Nerd Font support - not detected")
    vim.health.info("Icons will use unicode fallbacks")
    vim.health.info("Install a Nerd Font and set vim.g.have_nerd_font = true")
    vim.health.info("See :help scratch-manager-troubleshooting for details")
  end

  -- Show user configuration status
  if vim.g.have_nerd_font ~= nil then
    local status = vim.g.have_nerd_font and "enabled" or "disabled"
    vim.health.info(string.format("User setting: vim.g.have_nerd_font = %s", tostring(vim.g.have_nerd_font)))
  else
    vim.health.info("User setting: vim.g.have_nerd_font not set (will auto-detect)")
  end

  -- Show sample icons
  local lua_icon = vim.g.have_nerd_font and "󰢱" or "🌙"
  local md_icon = vim.g.have_nerd_font and "󰍔" or "📝"
  local cs_icon = vim.g.have_nerd_font and "󰌛" or "🔷"
  local json_icon = vim.g.have_nerd_font and "󰘦" or "📋"
  vim.health.info(string.format("Sample icons: %s lua, %s markdown, %s C#, %s json", lua_icon, md_icon, cs_icon, json_icon))
end

---Check plugin configuration and setup
local function check_plugin_setup()
  vim.health.start("scratch-manager Configuration")

  -- Check if scratch-manager is loaded
  local success, scratch_manager = pcall(require, "scratch-manager")
  if success then
    vim.health.ok("scratch-manager module - loaded")

    -- Check if setup has been called
    if scratch_manager.config then
      vim.health.ok("Plugin setup - completed")

      -- Validate configuration
      local config = scratch_manager.config
      vim.health.info("Default filetype: " .. (config.default_filetype or "not set"))
      vim.health.info("Border color: " .. (config.border_color or "not set"))
      vim.health.info("Keymaps enabled: " .. tostring(config.enable_keymaps))

      -- Check keymap configuration
      if config.keymaps then
        local keymap_count = 0
        for _ in pairs(config.keymaps) do keymap_count = keymap_count + 1 end
        vim.health.ok("Keymap configuration - " .. keymap_count .. " keymaps defined")
      else
        vim.health.warn("Keymap configuration - missing")
      end
    else
      vim.health.warn("Plugin setup - not completed",
        "Call require('scratch-manager').setup() in your configuration")
    end
  else
    vim.health.error("scratch-manager module - failed to load",
      "Check plugin installation and configuration")
  end
end

---Check commands and keymaps
local function check_commands_keymaps()
  vim.health.start("scratch-manager Commands & Keymaps")

  -- Check user commands
  local commands = {
    { cmd = "ScratchPadDisplay", desc = "Toggle scratch buffer" },
  }

  for _, cmd_info in ipairs(commands) do
    if vim.fn.exists(":" .. cmd_info.cmd) == 2 then
      vim.health.ok("Command :" .. cmd_info.cmd .. " - available")
    else
      vim.health.warn("Command :" .. cmd_info.cmd .. " - not found",
        "Ensure plugin setup() has been called")
    end
  end

  -- Check if keymaps are enabled and working
  local success, scratch_manager = pcall(require, "scratch-manager")
  if success and scratch_manager.config then
    if scratch_manager.config.enable_keymaps then
      vim.health.ok("Keymaps - enabled in configuration")

      local keymaps = scratch_manager.config.keymaps
      if keymaps then
        vim.health.info("Toggle keymap: " .. (keymaps.toggle or "not set"))
        vim.health.info("Language-aware toggle: " .. (keymaps.toggle_lang or "not set"))
        vim.health.info("Select keymap: " .. (keymaps.select or "not set"))
        vim.health.info("Delete keymap: " .. (keymaps.delete or "not set"))
      end
    else
      vim.health.info("Keymaps - disabled in configuration")
    end
  end
end

---Check test suite availability
local function check_test_suite()
  vim.health.start("scratch-manager Test Suite")

  -- Find the plugin root by looking for where scratch-manager.nvim is in runtimepath
  local plugin_root = nil
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if path:match("scratch%-manager%.nvim/?$") then
      plugin_root = path
      break
    end
  end

  if not plugin_root then
    vim.health.warn("Could not locate scratch-manager.nvim plugin directory")
    return
  end

  local test_dir = plugin_root .. "/tests"

  if check_directory_exists(test_dir) then
    vim.health.ok("Test directory found: " .. test_dir)

    -- Check for test files
    local test_files = vim.fn.glob(test_dir .. "/*_spec.lua", false, true)
    if #test_files > 0 then
      vim.health.ok("Found " .. #test_files .. " test files")
      for _, file in ipairs(test_files) do
        local filename = vim.fn.fnamemodify(file, ":t")
        vim.health.info("  - " .. filename)
      end

      -- Check if plenary is available for running tests
      local plenary_ok = check_module_loadable("plenary.busted")
      if plenary_ok then
        vim.health.ok("Plenary test runner available")
        vim.health.info("Run tests with: :PlenaryBustedFile tests/basic_spec.lua")
      else
        vim.health.warn("Plenary test runner not available",
          "Install plenary.nvim to run tests")
      end

      -- Check minimal_init.lua
      if check_file_exists(test_dir .. "/minimal_init.lua") then
        vim.health.ok("Minimal test init file found")
      else
        vim.health.warn("Minimal test init file missing")
      end
    else
      vim.health.warn("No test files found in " .. test_dir)
      vim.health.info("Searched pattern: " .. test_dir .. "/*_spec.lua")
    end
  else
    vim.health.warn("Test directory not found: " .. test_dir,
      "Tests may not be available")
  end
end

---Check scratch buffer functionality
local function check_scratch_functionality()
  vim.health.start("scratch-manager Functionality")

  local success, scratch_manager = pcall(require, "scratch-manager")
  if not success then
    vim.health.error("Cannot load scratch-manager for functionality test")
    return
  end

  -- Test basic function availability
  local functions_to_check = {
    "setup",
    "toggle_scratch_pad",
    "open_new_scratch_pad",
    "open_scratch",
    "find_existing_scratch_pad",
    "delete_current_scratch_pad"
  }

  for _, func_name in ipairs(functions_to_check) do
    if type(scratch_manager[func_name]) == "function" then
      vim.health.ok("Function " .. func_name .. " - available")
    else
      vim.health.error("Function " .. func_name .. " - missing")
    end
  end

  -- Test snacks integration (without actually creating buffers)
  local snacks_ok, snacks = pcall(require, "snacks")
  if snacks_ok and snacks.scratch then
    -- Test that we can call snacks.scratch.list without errors
    local list_ok, buffers = pcall(snacks.scratch.list)
    if list_ok then
      vim.health.ok("Snacks scratch integration - working")
      vim.health.info("Current scratch buffers: " .. #buffers)
    else
      vim.health.warn("Snacks scratch integration - error calling list()")
    end
  end
end

---Check documentation availability
local function check_documentation()
  vim.health.start("scratch-manager Documentation")

  -- Find the plugin root by looking for where scratch-manager.nvim is in runtimepath
  local plugin_root = nil
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if path:match("scratch%-manager%.nvim/?$") then
      plugin_root = path
      break
    end
  end

  if not plugin_root then
    vim.health.warn("Could not locate scratch-manager.nvim plugin directory")
    return
  end

  -- Check README
  if check_file_exists(plugin_root .. "/README.md") then
    vim.health.ok("README.md - found")
  else
    vim.health.warn("README.md - missing")
  end

  -- Check help documentation
  if check_file_exists(plugin_root .. "/doc/scratch-manager.txt") then
    vim.health.ok("Help documentation - found")
    vim.health.info("Access with: :help scratch-manager")
  else
    vim.health.warn("Help documentation - missing")
  end

  -- Check if help tags are generated
  if check_file_exists(plugin_root .. "/doc/tags") then
    vim.health.ok("Help tags - generated")
  else
    vim.health.info("Help tags - not generated (run :helptags doc/)")
  end
end

---Main health check function
function M.check()
  vim.health.start("scratch-manager.nvim Health Check")
  vim.health.info("Professional scratch buffer management for Neovim")
  vim.health.info("Version: Plugin extraction from mature implementation")
  vim.health.info("")

  -- Run all health checks
  local success, error_msg = pcall(function()
    check_neovim_version()
    check_dependencies()
    check_nerd_font()
    check_plugin_setup()
    check_commands_keymaps()
    check_scratch_functionality()
    check_test_suite()
    check_documentation()

    -- Final summary
    vim.health.start("scratch-manager Summary")
    vim.health.info("Health check completed successfully")
    vim.health.info("🎯 Quick start: require('scratch-manager').setup()")
    vim.health.info("📚 Help: :help scratch-manager")
    vim.health.info("🧪 Tests: :PlenaryBustedFile tests/basic_spec.lua")
    vim.health.info("🔄 Re-check: :checkhealth scratch-manager")
  end)

  if not success then
    vim.health.start("scratch-manager Error")
    vim.health.error("Health check failed with error: " .. tostring(error_msg))
    vim.health.info("Please report this issue if it persists")
  end
end

return M
