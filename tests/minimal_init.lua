-- Minimal init for testing scratch-manager.nvim
-- Works with `nvt` (nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests")

local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

-- Plenary runs every spec in a child nvim. Without a minimal_init option those children would
-- load the user's full config, so point them back at this file via $VIMINIT (used when no -u is given).
vim.env.VIMINIT = "luafile " .. vim.fn.fnameescape(plugin_dir .. "/tests/minimal_init.lua")

-- Find plugins before redirecting XDG dirs below; children inherit LAZY_DIR
vim.env.LAZY_DIR = vim.env.LAZY_DIR or (vim.fn.stdpath("data") .. "/lazy")

-- Keep test artifacts (C# runner work dirs, scratch pad files) out of the user's real cache and
-- data dirs. stdpath() is fixed at startup, so this applies to the per-spec child processes,
-- which inherit the env.
if not vim.env.SCRATCH_MANAGER_TEST_HOME then
  vim.env.SCRATCH_MANAGER_TEST_HOME = vim.fn.tempname()
  vim.env.XDG_CACHE_HOME = vim.env.SCRATCH_MANAGER_TEST_HOME .. "/cache"
  vim.env.XDG_DATA_HOME = vim.env.SCRATCH_MANAGER_TEST_HOME .. "/data"
  vim.env.XDG_STATE_HOME = vim.env.SCRATCH_MANAGER_TEST_HOME .. "/state"
end

-- Keep the user's own config (plugin/, after/plugin/) out of the test processes
local config_dir = vim.fn.stdpath("config")
vim.opt.rtp:remove(config_dir)
vim.opt.rtp:remove(config_dir .. "/after")

-- Add the plugin and its test dependencies (installed via lazy.nvim) to the runtimepath
local lazy_dir = vim.env.LAZY_DIR
vim.opt.rtp:prepend(plugin_dir)
for _, dep in ipairs({ "plenary.nvim", "snacks.nvim" }) do
  local path = lazy_dir .. "/" .. dep
  if vim.fn.isdirectory(path) == 0 then
    error(dep .. " is required for testing (looked in " .. lazy_dir .. "; set $LAZY_DIR to override)")
  end
  vim.opt.rtp:append(path)
end
vim.cmd("runtime plugin/plenary.vim")

vim.opt.swapfile = false
