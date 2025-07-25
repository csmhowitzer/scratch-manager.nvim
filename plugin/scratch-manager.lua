-- scratch-manager.nvim plugin loader
-- This file is automatically loaded by Neovim when the plugin is installed

if vim.g.loaded_scratch_manager then
  return
end
vim.g.loaded_scratch_manager = 1

-- Plugin will be loaded via require('scratch-manager').setup() in user config
-- Commands and keymaps will be set up during setup() call
