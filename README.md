# scratch-manager.nvim

*Professional scratch buffer management for Neovim*

[![Tests](https://img.shields.io/badge/tests-16%20passing-brightgreen)](tests/)
[![Health Check](https://img.shields.io/badge/health%20check-comprehensive-blue)](#health-check)
[![Documentation](https://img.shields.io/badge/docs-complete-success)](#documentation)

A powerful scratch buffer management plugin that enhances [folke/snacks.nvim](https://github.com/folke/snacks.nvim) with intelligent buffer persistence, customizable styling, and seamless workflow integration.

> **Status**: ✅ **Production Ready** - Extracted from mature, battle-tested implementation

## ✨ Features

- 🎯 **Smart Buffer Management**: Automatic persistence and reload of scratch buffers based on current context
- 🎨 **Customizable Styling**: Configurable borders, colors, positioning, and window dimensions
- ⚡ **Multiple File Types**: Support for markdown, code, and any filetype with language-aware detection
- 🔄 **Session Persistence**: Scratch buffers survive across Neovim sessions and reload intelligently
- ⌨️ **Intuitive Keymaps**: Quick access with customizable key bindings that fit your workflow
- 🏥 **Health Check Integration**: Comprehensive diagnostics and validation system
- 🧪 **Professional Test Suite**: 16 comprehensive test cases ensuring reliability
- 📚 **Complete Documentation**: Professional help docs with 40+ searchable tags

## 📋 Requirements

- **Neovim 0.9.0+** (for modern health check API)
- **[folke/snacks.nvim](https://github.com/folke/snacks.nvim)** (required dependency)
- **[nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim)** (optional, required for testing)

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  dir = "~/plugins/scratch-manager.nvim",
  name = "scratch-manager",
  dependencies = { "folke/snacks.nvim" },
  build = ":helptags doc",
  config = function()
    require("scratch-manager").setup()
  end,
}
```

### Using other plugin managers

Ensure `folke/snacks.nvim` is installed and loaded before `scratch-manager.nvim`.

### Manual installation

1. Clone or copy the plugin to your Neovim configuration
2. Add the plugin directory to your `runtimepath`
3. Call `require("scratch-manager").setup()` in your configuration
4. Run `:helptags doc/` to generate help tags

## ⚙️ Configuration

scratch-manager.nvim works out of the box with sensible defaults, but can be fully customized:

### Basic setup

```lua
require("scratch-manager").setup()
```

### Full configuration with defaults

```lua
require("scratch-manager").setup({
  width = nil,                    -- Auto-calculated: 1/3 screen width, max 100
  height = nil,                   -- Auto-calculated: screen height - 3
  border_color = "#F7DC6F",       -- Border highlight color
  dashboard_color = "#a6d189",    -- Dashboard highlight color
  default_filetype = "markdown",  -- Default filetype for new scratch buffers
  border_highlight = "SnacksInputBorder", -- Highlight group for borders
  enable_keymaps = true,          -- Whether to set up default keymaps
  keymaps = {
    toggle = "==",                -- Toggle scratch buffer (markdown)
    toggle_lang = "=c",           -- Toggle scratch buffer (language-aware)
    select = "=s",                -- Select from existing scratch buffers
    delete = "=d",                -- Delete current scratch buffer
  }
})
```

### Custom styling

```lua
require("scratch-manager").setup({
  border_color = "#FF6B6B",
  dashboard_color = "#4ECDC4",
  default_filetype = "python",
  width = 120,
  height = 40,
})
```

### Custom keymaps

```lua
require("scratch-manager").setup({
  enable_keymaps = false,  -- Disable defaults
})

-- Define your own keymaps
local sm = require("scratch-manager")
vim.keymap.set("n", "<leader>st", sm.toggle_scratch_pad, { desc = "Toggle Scratch" })
vim.keymap.set("n", "<leader>sl", function() sm.toggle_scratch_pad("lua") end, { desc = "Lua Scratch" })
```

## 🚀 Usage

### Default Keymaps

| Key | Action | Description |
|-----|--------|-------------|
| `==` | Toggle Scratch (Markdown) | Opens/focuses markdown scratch buffer |
| `=c` | Toggle Scratch (Language-aware) | Opens scratch buffer with detected filetype |
| `=s` | Select Scratch | Choose from existing scratch buffers |
| `=d` | Delete Scratch | Permanently delete current scratch buffer |

### Commands

- `:ScratchPadDisplay` - Toggle scratch buffer for current context

### Smart Buffer Management

scratch-manager intelligently manages your scratch space:

- **Context-aware**: Creates separate scratch buffers for different directories/files
- **Persistent**: Scratch buffers survive Neovim restarts and reload automatically
- **Language-aware**: Detects appropriate filetype based on current buffer
- **Non-intrusive**: Opens on the right side without disrupting your workflow

## 🏥 Health Check

scratch-manager includes a comprehensive health check system:

```vim
:checkhealth scratch-manager
```

The health check validates:
- Neovim version compatibility
- Required and optional dependencies
- Plugin configuration status
- Available commands and keymaps
- Core functionality
- Test suite availability
- Documentation completeness

## 🧪 Testing

Run the comprehensive test suite:

```vim
:PlenaryBustedFile tests/basic_spec.lua
```

**Test Coverage:**
- ✅ 16 test cases covering all functionality
- ✅ Setup and configuration validation
- ✅ Core buffer management operations
- ✅ Error handling and edge cases
- ✅ Integration with snacks.nvim

## 📚 Documentation

Complete documentation is available:

```vim
:help scratch-manager
```

**Documentation includes:**
- Complete API reference with examples
- Configuration options with descriptions
- Usage patterns and workflows
- Troubleshooting guide
- 40+ searchable help tags

## 🔧 API Reference

### Core Functions

```lua
-- Toggle scratch buffer (main function)
require("scratch-manager").toggle_scratch_pad(file_type)

-- Setup with configuration
require("scratch-manager").setup(opts)

-- Lower-level functions for advanced usage
require("scratch-manager").open_new_scratch_pad(config)
require("scratch-manager").open_scratch(config)
require("scratch-manager").find_existing_scratch_pad(buffers, config)
require("scratch-manager").delete_current_scratch_pad()
```

See `:help scratch-manager-functions` for complete API documentation.

## 🎯 Examples

### Integration with which-key.nvim

```lua
require("which-key").register({
  ["<leader>s"] = {
    name = "Scratch",
    t = { function() require("scratch-manager").toggle_scratch_pad() end, "Toggle Scratch" },
    l = { function() require("scratch-manager").toggle_scratch_pad("lua") end, "Lua Scratch" },
    m = { function() require("scratch-manager").toggle_scratch_pad("markdown") end, "Markdown Scratch" },
  }
})
```

### Custom workflow integration

```lua
-- Quick notes for current project
vim.keymap.set("n", "<leader>n", function()
  require("scratch-manager").toggle_scratch_pad("markdown")
end, { desc = "Project Notes" })

-- Language-specific scratch space
vim.keymap.set("n", "<leader>ts", function()
  require("scratch-manager").toggle_scratch_pad()
end, { desc = "Language Scratch" })
```

## 🛠️ Troubleshooting

### Common Issues

**Q: Scratch buffers don't persist across sessions**
A: Ensure snacks.nvim is properly configured. Check `:checkhealth scratch-manager` for issues.

**Q: Keymaps don't work**
A: Verify `enable_keymaps = true` in your config, or define custom keymaps if disabled.

**Q: "module 'snacks' not found" error**
A: Install `folke/snacks.nvim` as a dependency.

See `:help scratch-manager-troubleshooting` for complete troubleshooting guide.

## 🏗️ Architecture

This plugin enhances `folke/snacks.nvim` with:
- **Intelligent context detection** based on current buffer/directory
- **Persistent storage** with automatic reload capabilities
- **Professional configuration system** with comprehensive validation
- **Robust error handling** and user feedback
- **Comprehensive testing** ensuring reliability

## 📄 License

MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **[folke/snacks.nvim](https://github.com/folke/snacks.nvim)** - Excellent foundation for scratch buffer functionality
- **6-AC Quality Standards** - Professional plugin development methodology
- **Battle-tested implementation** - Extracted from mature, daily-use codebase

---

*Built with ❤️ following professional plugin development standards*
