-- Minimal init for testing scratch-manager.nvim
-- This sets up the Lua path so tests can find the plugin modules

-- Add the plugin's lua directory to the package path
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local lua_dir = plugin_dir .. "/lua"

-- Add to package.path if not already there
if not package.path:find(lua_dir, 1, true) then
  package.path = lua_dir .. "/?.lua;" .. lua_dir .. "/?/init.lua;" .. package.path
end

-- Ensure plenary is available
local ok, plenary = pcall(require, "plenary")
if not ok then
  error("plenary.nvim is required for testing")
end

-- Ensure snacks.nvim is available (dependency for scratch-manager)
local snacks_ok, snacks = pcall(require, "snacks")
if not snacks_ok then
  error("snacks.nvim is required for scratch-manager.nvim")
end

-- Set minimal vim options for testing
vim.opt.runtimepath:append(plugin_dir)
