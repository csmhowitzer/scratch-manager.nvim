# scratch-manager.nvim

*Professional scratch buffer management for Neovim*

[![Tests](https://img.shields.io/badge/tests-92%20passing-brightgreen)](tests/)
[![Health Check](https://img.shields.io/badge/health%20check-comprehensive-blue)](#health-check)
[![Documentation](https://img.shields.io/badge/docs-complete-success)](#documentation)

A powerful scratch buffer management plugin that enhances [folke/snacks.nvim](https://github.com/folke/snacks.nvim) with intelligent buffer persistence, customizable styling, and seamless workflow integration.

> **Status**:  **Production Ready** - Extracted from mature, battle-tested implementation

## ✨ Features

- **Smart Buffer Management**: Automatic persistence and reload of scratch buffers based on current context
- **Customizable Styling**: Configurable borders, colors, positioning, and window dimensions
- **Multiple File Types**: Support for markdown, code, and any filetype with language-aware detection
- **Session Persistence**: Scratch buffers survive across Neovim sessions and reload intelligently
- **Intuitive Keymaps**: Quick access with customizable key bindings that fit your workflow
- **Health Check Integration**: Comprehensive diagnostics and validation system
- **Scratch Pad Indicator**: Statusline component that shows when the current buffer has a scratch pad
- **Professional Test Suite**: 109 comprehensive test cases ensuring reliability
- **Complete Documentation**: Professional help docs with 40+ searchable tags

## Requirements

**Required**
- **Neovim 0.10.0+** (floating window footers)
- **[folke/snacks.nvim](https://github.com/folke/snacks.nvim)** (scratch file storage and windows)

**Optional**
- **[.NET 10+ SDK](https://dotnet.microsoft.com/download)**: running C# pads with `<CR>` (`dotnet run` on a single file, no project needed)
- **[echasnovski/mini.icons](https://github.com/echasnovski/mini.icons)** or **[nvim-tree/nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)**: colored file icons in the select list (built-in icons otherwise)
- **A [Nerd Font](https://www.nerdfonts.com/)**: icons in the indicator, badges and select list (plain-text fallbacks otherwise; set `vim.g.have_nerd_font`)
- **[enhance.nvim](https://github.com/csmhowitzer/enhance.nvim)** (or a custom provider): running DB pads against your database connections
- **A statusline** such as [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim): to show `status()` (see [Scratch pad indicator](#scratch-pad-indicator))
- **[nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim)**: only for running the test suite

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

## Configuration

scratch-manager.nvim works out of the box with sensible defaults, but can be fully customized:

### Basic setup

```lua
require("scratch-manager").setup()
```

### Full configuration with defaults

```lua
require("scratch-manager").setup({
  width = nil,                    -- Auto-calculated: 1/3 screen width, max 100
  height = nil,                   -- Auto-calculated: editor height minus statusline/cmdline
  border_color = "#F7DC6F",       -- Scratch window border color (same as highlights.scratch_border)
  dashboard_color = "#a6d189",    -- Dashboard highlight color
  default_filetype = "markdown",  -- Default filetype for new scratch buffers
  enable_keymaps = true,          -- Whether to set up default keymaps
  wrap = { notes = true, code = false, db = false }, -- Soft-wrap per pad kind (or true/false); <M-z> toggles
  autosave = true,                -- Save pads after every change (never prompts to save)
  smart_persistence = true,       -- Delete pads closed with nothing in them (blank, or only using/#: lines)
  lsp = {
    detach = true,                -- Keep language servers off pads (they can't resolve pad files)
    allow = { "lua_ls" },         -- ...except these
    mirror = true,                -- ...and servers a language supports (C#: Roslyn) via a clean mirror file
  },
  keymaps = {
    toggle = "==",                -- Toggle scratch buffer (markdown)
    toggle_lang = "=c",           -- Toggle scratch buffer (language-aware)
    toggle_db = "=q",             -- Toggle DB (SQL) scratch buffer
    send = "=p",                  -- Send the selection / function under the cursor to the code pad
    pad_help = "=h",              -- Inside a pad: language-specific help (false to disable)
    pad_size = "=w",              -- Inside a pad: cycle its size, ⅓ → ⅔ → nearly full (false to disable)
    pad_watch = "=l",             -- Inside a C# pad: watch mode, rerun after edits (false to disable)
    select = "=s",                -- Select from existing scratch buffers
    delete = "=d",                -- Delete current scratch buffer
  },
  indicator = {
    enabled = true,               -- Track which buffers have scratch pads
    icon = "",                    -- Notes (markdown) pad icon ("✎" without a Nerd Font)
    code_icon = "",               -- Code pad icon ("<>" without a Nerd Font)
    db_icon = "",                 -- DB pad icon ("DB" without a Nerd Font)
    show_count = true,            -- Append the count when a buffer has several pads
    notify = false,               -- Also notify once when entering a buffer with a pad
    float = false,                -- Clickable notes/code badges in the top-right corner
    animate = false,              -- Grow the pad out of the badge when clicked
    transparent = true,           -- Badges use the editor background like the pads (false: float background)
  },
  run = {
    cs = {
      enabled = true,             -- <CR> in a C# pad runs it with `dotnet run`
      cmd = { "dotnet", "run", "-p:PublishAot=false" }, -- .NET 10+ file-based apps
      max_height = 15,            -- Max height of the output window
      project = true,             -- reference the source file's nearest .csproj
      show_warnings = false,      -- show compiler/NuGet build warnings in the output
      inline = true,              -- .Dump(): show values at the end of their lines
    },
    sql = {
      enabled = true,             -- <CR> in a DB pad runs it through the provider
      provider = "enhance",       -- built-in enhance.nvim adapter, a custom table, or false
      close_pad = true,           -- close the pad on run so results get the full width
    },
  },
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

## Usage

### Default Keymaps

| Key | Action | Description |
|-----|--------|-------------|
| `==` | Toggle Scratch (Markdown) | Opens/focuses markdown scratch buffer |
| `=c` | Toggle Scratch (Language-aware) | Opens scratch buffer with detected filetype |
| `=q` | Toggle Scratch (DB) | Opens a SQL scratch buffer for this file |
| `=p` | Send to Code Pad | Sends the selection (visual) or the function under the cursor to this file's code pad |
| `=h` | Pad help | Inside a pad: what `<CR>` does there, keys, tips (C#, SQL, Lua, notes) |
| `=w` | Pad size | Inside a pad: ⅓ of the screen → ⅔ → nearly full (centered); stays for the session |
| `=l` | Watch mode | Inside a C# pad: rerun ~0.5s after each edit while it has a `.Dump()`, quietly (output only for errors/prints); remembered per pad |
| `=s` | Select Scratch | Choose from existing scratch buffers |
| `=d` | Delete Scratch | Delete the scratch pad (asks for confirmation; works from the pad or its source buffer) |

### Pad size

Pads open on the right third of the screen. `=w` inside a pad cycles it to two thirds (still on
the right) and to nearly the full width (centered, with margins), then back. The size stays for
the rest of the session, and the output window follows it. Handy for long `.Dump()` values.

### Language servers in pads

Pads are throwaway files outside any project, stored under encoded file names that language
servers can't make sense of (Roslyn crashes on them). So servers are kept off pads by default,
with two exceptions:

- **Servers a language supports** (C#: Roslyn) run in pads through a clean mirror file: the pad
  is shown to the server as e.g. `StringExtensionsPad.cs`, so you get completion, errors as you
  type, hover and go-to-definition, including your project's types. For that, C# pads get a
  visible `#:project …` line for the source file's project (added for you; on screen the path is
  shortened to `…/Project.csproj` except on the cursor line). `#:` lines are shown in your comment
  color and skipped by Treesitter, whose C# grammar doesn't know them yet (otherwise the parse
  error can break the highlighting of the code below). `.Dump()` calls aren't flagged, since
  the helper only exists when the pad runs, and neither are unused `using` lines (`=p` brings all of
  a file's usings on purpose). `lsp.mirror = false` turns this off.
- **`lsp.allow`** lists other servers to keep (`lua_ls` by default, for Lua pads).

Set `lsp.detach = false` to leave every server attached as-is. Pad buffers carry
`b:scratch_manager_pad`, so your own config (format-on-save, crash handlers, …) can skip them.

### Wrapping

Notes pads soft-wrap long lines; code and DB pads don't (`wrap` sets this per kind, or
`true`/`false` for all). `<M-z>` (Alt+z) toggles wrapping in the current pad.

### How pads are matched

A pad belongs to a file by its name, Neovim's working directory (`:pwd`), the git
branch, and the pad's filetype, the same key snacks.nvim uses for scratch files. So
`==` (markdown) and `=c` (code) keep two separate pads for the same file, and pads
created on one branch don't show up on another.

### Scratch pad indicator

Pads come in three kinds: **notes** (markdown, `==`, gold border), **code** (the file's
language, `=c`, purple border) and **DB** (SQL, `=q`, green border). `status()` returns the
icon of each kind the current buffer has (each with a count if there are several), or `""`. It only reads a cached buffer variable, so it is
safe to call on every statusline redraw.

```lua
-- lualine
require("lualine").setup({
  sections = { lualine_x = { require("scratch-manager").status } },
})

-- plain statusline
vim.o.statusline = "%f %{v:lua.require'scratch-manager'.status()} %=%l:%c"
```

Set `indicator.notify = true` for a one-time notification instead of (or as well as)
the icon.

Set `indicator.float = true` for small bordered badges in the top-right corner (below
the tabline): the notes badge in the corner, then code, then DB to the left, each only when
that kind of pad exists. Click one, or focus it and press `<CR>`, to open that pad (you're
asked which one if there are several of that kind). They hide while you're inside a pad.
Icon color: `highlights.badge`; borders: `highlights.scratch_border` / `highlights.code_border` /
`highlights.db_border`. With `indicator.animate = true`
an empty box grows from the badge to the pad's size (~150ms) before the pad opens.

### Running code in a pad

- **Lua**: snacks.nvim's own `<CR>` runs the pad (or the visual selection) and shows the
  results inline.
- **C#**: `<CR>` runs the pad (or the visual selection) with `dotnet run`, using .NET 10's
  file-based apps, so no `.sln` or `.csproj` is needed. Output (stdout and stderr) appears in
  a float at the bottom of the pad with the exit status and time; `q` closes it. The first
  run builds and takes a few seconds; later runs of the same pad reuse the build cache.
  Requires the .NET 10+ SDK on your `PATH`. Disable with `run = { cs = { enabled = false } }`.
  The default command passes `-p:PublishAot=false`: file-based apps otherwise default to
  native AOT, which disables reflection (e.g. `JsonSerializer.Serialize` throws).
- **Running a selection** (visual mode + `<CR>`) runs only the selected lines. For C#, the
  `using` lines at the top of the pad and any `#:` lines are included automatically, so a
  selected block still compiles; the output title says what ran (`lines 6–7 + 1 using line`).
  `=h` in any pad explains this and the rest of that language's features.
- **Inline values with `.Dump()`** (LINQPad style): add `.Dump()` to any expression and its
  value appears at the end of that line when you run, instead of writing `Console.WriteLine`
  everywhere. Objects show as JSON, a `.Dump()` in a loop shows every value (`(3×) 14 │ 11 │ 12`),
  and `K` on the line opens the full value, formatted. `.Dump()` returns its value, so it can
  sit in the middle of a chain. Values clear when you edit the pad. They're orange and italic
  so they don't look like diagnostics; change it with
  `highlights = { dump = { fg = "#94e2d5", italic = true } }`.

  ```csharp
  payload.TryGetFinishJobInfo(out var info).Dump("found");  // → found: True
  info.ExternalId.Dump();                                    // → "HOVER-1182"
  var phones = raw.Select(p => p.ToPhoneDigits()).Dump("digits")  // → digits: ["5551234567",…]
      .Select(d => d!.ToPhone()).Dump("formatted");               // → formatted: ["(555) 123-4567",…]
  ```
- **C# with your project**: a C# pad remembers the file it was opened from, and runs with a
  reference to the nearest `.csproj` above that file, so the pad can use the project's own
  types. The reference is added only to the compiled copy (your pad stays clean), line
  numbers in errors still match the pad (`pad(3,9): error ...`), and the output title
  shows the project. Build warnings (often from the project itself) are hidden and counted
  in the title (`· 9 warnings hidden`); errors always show. `show_warnings = true` keeps them.
  A pad with its own `#:project` line is left alone; turn it off with
  `run = { cs = { project = false } }`. The first run builds the project, so large projects
  take a while; later runs are incremental.

  ```csharp
  // pad opened with =c from src/Billing/InvoiceCalculator.cs
  using Billing;

  var items = new[] { new LineItem("SHINGLE", 30, 42.10m), new LineItem("NAILS", 4, 9.99m) };
  Console.WriteLine(InvoiceCalculator.Total(items, 0.055m));   // 1374.62
  ```

### DB pads (SQL)

`=q` opens a SQL pad attached to the current file, handy for research queries next to
the code that uses the data. `<CR>` runs the pad (or the visual selection): the first
run asks which connection to use and remembers it for that pad; `<leader>dc` in the pad
switches it. By default the pad closes on run so the results get the full width
(`run.sql.close_pad = false` keeps it open).

Running goes through a **provider**, so no database plugin is required. The built-in
provider is a thin adapter for [enhance.nvim](https://github.com/csmhowitzer/enhance.nvim),
loaded only when a DB pad is used; results appear in enhance's results window. With an
enhance version that has its public API (`enhance.api`), DB pads also get **table and
column completion** for their connection (SQL Server, via vim-dadbod-completion), from the
first pick on and whenever the pad is reopened. Without a
provider, DB pads are still regular SQL scratch pads. Use your own provider with:

```lua
run = {
  sql = {
    provider = {
      name = "my-db",
      available = function() return true end,
      connections = function() return { { name = "local" } } end,
      execute = function(connection, query, bufnr)
        -- run `query` against `connection` and show the results
      end,
      -- optional: make the pad connection-aware, e.g. set up completion
      attach = function(connection, bufnr) end,
    },
  },
},
```

### Sending code to a pad

`=p` in a source file sends code to that file's code pad (the `=c` pad), opening it with the
cursor on the new code: in visual mode the selected lines, in normal mode the function or method
under the cursor (Treesitter), or the current line. The code goes in under a
`// from File.cs:12–18` comment with its indentation cleaned up, so you can try variations
without touching the real file.

For C#, the file's `using` lines and its namespace are added to the top of the pad if they're
missing (never twice; the pad's usings are then sorted the .NET way: `System` first, then the rest,
then `using static` and aliases), and a method becomes a local function (access modifiers dropped; an extension method's
`this` parameter becomes a plain one, with a note on how to call it). It goes above any
`record`/`class` declarations in the pad, since C# needs statements first.

### Commands

- `:ScratchPadDisplay` - Toggle scratch buffer for current context

### Smart Buffer Management

scratch-manager intelligently manages your scratch space:

- **Context-aware**: Creates separate scratch buffers for different directories/files
- **Persistent**: Scratch buffers survive Neovim restarts and reload automatically
- **Language-aware**: Detects appropriate filetype based on current buffer
- **Non-intrusive**: Opens on the right side without disrupting your workflow

## Health Check

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

## Testing

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

## Documentation

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

## API Reference

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
require("scratch-manager").find_scratch_pads(buffers, config)

-- Indicator
require("scratch-manager").status()            -- statusline component
require("scratch-manager").refresh_indicator() -- recompute for a buffer
require("scratch-manager").open_pad()          -- open the current buffer's pad
```

See `:help scratch-manager-functions` for complete API documentation.

## Adding a language

Language-specific behavior lives in small profiles (`lua/scratch-manager/languages/<filetype>.lua`),
so running pads, `=p`, `=h` help and health checks stay generic. A profile can also be registered
from your config; every field is optional. For example, a minimal Python runner:

```lua
require("scratch-manager.languages").register("python", {
  run = {
    title = "python",
    file = "scratch.py",
    cmd = function(config) return config.cmd or { "python3" } end, -- the file path is appended
  },
  imports = function(lines) -- what `=p` should bring along from the source file
    return vim.tbl_filter(function(l) return l:match("^import ") or l:match("^from .+ import ") end, lines)
  end,
  is_import = function(line) return line:match("^import ") or line:match("^from .+ import ") end,
})
```

`<CR>` then runs Python pads (selections too) with the same output window. Programs can print
`\x1e<line>\x1f<text>` lines to show values inline, the way C#'s `.Dump()` does. See
`lua/scratch-manager/languages/init.lua` for every hook (`run`, `imports`, `adapt`, `insert_at`,
`kind`, `keys`, `on_open`, `help`, `health`, …) and `languages/cs.lua` for a complete example.

## Examples

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

## Troubleshooting

### Common Issues

**Q: Scratch buffers don't persist across sessions**
A: Ensure snacks.nvim is properly configured. Check `:checkhealth scratch-manager` for issues.

**Q: Keymaps don't work**
A: Verify `enable_keymaps = true` in your config, or define custom keymaps if disabled.

**Q: "module 'snacks' not found" error**
A: Install `folke/snacks.nvim` as a dependency.

See `:help scratch-manager-troubleshooting` for complete troubleshooting guide.

## Architecture

This plugin enhances `folke/snacks.nvim` with:
- **Intelligent context detection** based on current buffer/directory
- **Persistent storage** with automatic reload capabilities
- **Professional configuration system** with comprehensive validation
- **Robust error handling** and user feedback
- **Comprehensive testing** ensuring reliability

## License

MIT License - see the LICENSE file for details.

## Acknowledgments

- **[folke/snacks.nvim](https://github.com/folke/snacks.nvim)** - Excellent foundation for scratch buffer functionality
- **6-AC Quality Standards** - Professional plugin development methodology
- **Battle-tested implementation** - Extracted from mature, daily-use codebase

---

*Built with ❤️ following professional plugin development standards*
