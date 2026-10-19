---@diagnostic disable: missing-fields

-- Professional scratch buffer management for Neovim
-- Enhances folke/snacks.nvim with intelligent buffer persistence and customization

-- Lazy load snacks to allow for mocking in tests
local Snacks

-- Load extracted modules
local icons = require("scratch-manager.icons")
local ui = require("scratch-manager.ui")
local utils = require("scratch-manager.utils")
local selection = require("scratch-manager.selection")
local badge = require("scratch-manager.badge")
local runner = require("scratch-manager.runner")
local sql = require("scratch-manager.sql")
local languages = require("scratch-manager.languages")
local pad_lsp = require("scratch-manager.lsp")
local store = require("scratch-manager.store")

---@class ScratchManagerHighlights
---@field border table|nil Select list floating window border highlight
---@field separator table|nil Header separator line highlight (defaults to border if not set)
---@field header table|nil Header text color highlight
---@field file_counter table|nil File counter text highlight (default: gray, italic)
---@field window_title table|nil Window title highlight (default: no italic, uses default color)
---@field footer table|nil Select list footer highlight (default: blue, bold, italic)
---@field scratch_border table|nil Notes (markdown) pad border highlight (default: gold)
---@field code_border table|nil Code pad border highlight (default: purple)
---@field db_border table|nil DB (SQL) pad border highlight (default: green)
---@field scratch_title table|nil Scratch buffer title highlight (default: blue, bold, italic)
---@field badge table|nil Floating badge icon highlight (default: blue, bold)
---@field dump table|nil Inline .Dump() values in C# pads (default: orange, italic)

---@class ScratchManagerSelectionConfig
---@field max_items number Maximum items to show in selection UI (default: 20)

---@class ScratchManagerUIConfig
---@field show_git_branch boolean Whether to show git branch column (default: true)
---@field show_path boolean Whether to show path column (default: true)
---@field show_icon boolean Whether to show icon column (default: true)
---@field filename_width number Maximum width of the filename column; longer names are truncated (default: 25)
---@field branch_width number Maximum width of the branch column; longer names are truncated (default: 15)
---@field icon_width number Fixed width for icon column (default: 3)
---@field file_counter boolean Whether to show file counter in header (default: true)

---@class ScratchManagerIndicatorConfig
---@field enabled boolean Track whether buffers have scratch pads (default: true)
---@field icon string Notes (markdown) pad icon (default: nerd font pencil, "✎" without nerd font)
---@field code_icon string Code pad icon (default: nerd font code, "<>" without nerd font)
---@field db_icon string DB (SQL) pad icon (default: nerd font database, "DB" without nerd font)
---@field show_count boolean Append the pad count when a buffer has more than one (default: true)
---@field notify boolean Notify once per buffer when it has a scratch pad (default: false)
---@field float boolean Show clickable floating badges (notes, code, db) in the top-right corner (default: false)
---@field animate boolean Grow the pad out of the badge when it is clicked (default: false)
---@field transparent boolean Badges use the editor background like the pads; false: float background (default: true)
---@field layout "row"|"column" Badges side by side in the top-right corner, or stacked down the right edge;
---  "column" also keeps pads clear of the badges (shifted left) and shows them while a pad is open (default: "row")

---@class ScratchManagerConfig
---@field width number|nil Window width (defaults to 1/3 of screen, max 100)
---@field height number|nil Window height (defaults to screen height - 3)
---@field border_color string Border highlight color
---@field dashboard_color string Dashboard highlight color
---@field default_filetype string Default filetype for new scratch buffers
---@field border_highlight string Deprecated, no longer used
---@field highlights ScratchManagerHighlights|nil Highlight group overrides
---@field keymaps ScratchManagerKeymaps Keymap configuration
---@field ui ScratchManagerUIConfig UI configuration options
---@field selection ScratchManagerSelectionConfig Selection UI configuration options
---@field enable_keymaps boolean Whether to set up default keymaps
---@field wrap boolean|{ notes: boolean, code: boolean, db: boolean } Soft-wrap long lines per pad kind, or for all (default: notes only)
---@field autosave boolean Save pads after every change so they never prompt to save (default: true)
---@field smart_persistence boolean Delete a pad when it's closed with nothing in it (blank, or only the
---  language's import lines such as C# `using` / `#:` lines), so `=s` and the badges only show real pads (default: true)
---@field lsp { detach: boolean, allow: string[], mirror: boolean } Language servers on pads: keep them off except `allow`;
---  `mirror` lets the servers a language profile names (C#: roslyn) run in pads through a clean mirror file (default: true)
---@field run { cs: ScratchManagerRunConfig, sql: ScratchManagerSqlConfig } Runners for pads by filetype (Lua pads use snacks' own <CR>)
---@field indicator ScratchManagerIndicatorConfig Scratch pad indicator options

---@class ScratchManagerKeymaps
---@field toggle string Toggle scratch buffer (markdown)
---@field toggle_lang string Toggle scratch buffer (language-aware)
---@field toggle_db string Toggle DB (SQL) scratch buffer
---@field send string|false Send the selection / function under the cursor to the file's code pad
---@field pad_help string|false Help for the current pad (inside pads only)
---@field pad_size string|false Cycle the pad size: ⅓ → ⅔ → nearly full (inside pads only)
---@field pad_watch string|false Watch mode on/off: rerun after edits (C# pads with a `.Dump()`; inside pads only)
---@field select string Select from existing scratch buffers
---@field delete string Delete current scratch buffer

---@class ScratchPadConfig
---@field width number Calculated window width
---@field height number Calculated window height
---@field path string Working directory path
---@field name string Buffer name
---@field fmtName string Formatted buffer name for display
---@field ft string File type
---@field icon string File type icon
---@field file string|nil Scratch file path
---@field branch string|nil Git branch the pad is keyed on (snacks filekey)
---@field match_ft boolean|nil Only match pads with the same filetype

---@class ScratchManager
---@field config ScratchManagerConfig
local M = {}

-- Default configuration
---@type ScratchManagerConfig
local default_config = {
	width = nil, -- Auto-calculated: 1/3 screen width, max 100
	height = nil, -- Auto-calculated: screen height - 3
	border_color = "#F7DC6F",
	dashboard_color = "#a6d189",
	default_filetype = "markdown",
	border_highlight = "SnacksInputBorder", -- Deprecated: no longer applied
	highlights = {
		border = { fg = "#89b4fa", bold = true }, -- Blue for selection list border
		separator = { fg = "#89b4fa", bold = true }, -- Blue for separator line (matches border by default)
		header = { fg = "#a6d189", bold = true }, -- Green for selection list header
		file_counter = { fg = "#313244", italic = true, bold = false }, -- Gray italic file counter
		window_title = { fg = "#74c7ec", italic = false, bold = false }, -- Window title (uses default color, no italic)
		footer = { fg = "#74c7ec", bold = true, italic = true }, -- Blue selection list footer
		scratch_border = { fg = "#F7DC6F", bold = true }, -- Gold notes (markdown) pad border
		code_border = { fg = "#cba6f7", bold = true }, -- Purple code pad border
		db_border = { fg = "#a6d189", bold = true }, -- Green DB (SQL) pad border
		scratch_title = { fg = "#74c7ec", bold = true, italic = true }, -- Blue scratch buffer title
		badge = { fg = "#74c7ec", bold = true }, -- Blue floating badge icon
		dump = { fg = "#fab387", italic = true }, -- Orange inline .Dump() values (distinct from diagnostics)
	},
	keymaps = {
		toggle = "==", -- Markdown scratch buffer toggle
		toggle_lang = "=c", -- Language-aware scratch buffer toggle
		toggle_db = "=q", -- DB (SQL) scratch buffer toggle
		send = "=p", -- Send the selection (or the function under the cursor) to the code pad
		pad_help = "=h", -- Help inside a pad (language-specific)
		pad_size = "=w", -- Inside a pad: cycle its size (⅓ → ⅔ → nearly full)
		pad_watch = "=l", -- Inside a pad: watch mode (live rerun after edits while it has a .Dump())
		select = "=s", -- Select from existing scratch buffers
		delete = "=d", -- Delete current scratch buffer
	},
	ui = {
		show_git_branch = true,
		show_path = true,
		show_icon = true,
		filename_width = 25,
		branch_width = 15,
		icon_width = 3,
		file_counter = true,
	},
	selection = {
		max_items = 20,
	},
	enable_keymaps = true,
	wrap = { notes = true, code = false, db = false }, -- or true/false for every kind; <M-z> toggles
	autosave = true,
	smart_persistence = true,
	-- Pads are throwaway files outside any project, with encoded file names servers can't handle
	-- (Roslyn crashes on them). Detach language servers from pads, except the ones listed in allow.
	lsp = {
		detach = true,
		allow = { "lua_ls" },
		mirror = true, -- language servers that support it (C#: Roslyn) run in pads via a clean mirror file
	},
	run = {
		cs = {
			enabled = true,
			-- .NET 10+ file-based apps: no .sln/.csproj needed. PublishAot=false: file-based apps
			-- default to AOT, which disables reflection (e.g. JsonSerializer.Serialize throws)
			cmd = { "dotnet", "run", "-p:PublishAot=false" },
			max_height = 15,
			show_warnings = false, -- hide compiler/NuGet build warnings from the output
			inline = true, -- .Dump(): show values at the end of the line that produced them
			project = true, -- reference the source file's nearest .csproj (#:project)
			watch_delay = 500, -- watch mode: ms after the last edit before rerunning
		},
		sql = {
			enabled = true,
			provider = "enhance", -- built-in adapter, loaded only on use; false or a custom provider table
			close_pad = true, -- close the pad on run so results get the full width
		},
	},
	indicator = {
		enabled = true,
		icon = "", -- nf-fa-pencil (notes pads)
		code_icon = "", -- nf-fa-code (code pads)
		db_icon = "", -- nf-fa-database (DB pads)
		show_count = true,
		notify = false,
		float = false,
		animate = false,
		transparent = true, -- badges blend in like the pads; false for the regular float background
		layout = "row", -- "row": side by side in the top-right corner; "column": stacked down the right edge
	},
}

---Get current config with fallback to defaults
---@return ScratchManagerConfig
local function get_config()
	return M.config or default_config
end

-- Private helper functions

---Get Snacks module (lazy loaded to allow mocking in tests)
---@return table Snacks module
---@private
local function get_snacks()
	if not Snacks then
		Snacks = require("snacks")
	end
	return Snacks
end

---Get scratch filename from buffer name
---@param name string Buffer name
---@return string filename Formatted filename
---@private
local function get_scratch_filename(name)
	if not name then
		return ""
	end
	local match = name:match("Scratch Pad %((.+)%)")
	return match or name
end

---Default scratch window height: fill the editor from row 1 down to the statusline
---@return number height Inner window height (excluding borders)
---@private
local function default_window_height()
	local statusline = vim.o.laststatus > 0 and 1 or 0
	-- 1 for the row offset, 2 for the top and bottom borders
	return math.max(1, vim.o.lines - vim.o.cmdheight - statusline - 3)
end

---Pad kinds, in badge order (corner first): notes are markdown (`==`), DB pads are SQL (`=q`),
---every other filetype is a code pad (`=c`)
local KINDS = { "notes", "code", "db" }

---@param ft string|nil Pad filetype
---@return "notes"|"code"|"db"
local function pad_kind(ft)
	if ft == nil or ft == "" then
		return "notes"
	end
	return languages.get(ft).kind
end

---Border highlight group for a pad kind
---@param kind "notes"|"code"|"db"
---@return string
local function border_hl(kind)
	return ({ code = "ScratchManagerCodeBorder", db = "ScratchManagerDbBorder" })[kind] or "ScratchManagerBorder"
end

---Should pads of this kind soft-wrap? (`wrap` is a boolean for all kinds or a per-kind table)
---@param kind "notes"|"code"|"db"
---@return boolean
local function wraps(kind)
	local wrap = get_config().wrap
	if type(wrap) == "table" then
		local value = wrap[kind]
		if value == nil then
			value = default_config.wrap[kind]
		end
		return value ~= false
	end
	return wrap ~= false
end

-- Pad size for this session, cycled with `=w`: 1 = default width on the right, 2 = two thirds of
-- the screen on the right, 3 = nearly the full width (centered, with margins so it still reads as a popup)
local pad_size = 1

-- Defined below (needs the pad matching helpers): pad counts per kind for a source file
local count_pad_kinds

---How many badges there will be with this pad open: the source file's pad kinds, plus the kind
---being opened. From inside a pad (`=w`), the pad's source file counts. Counted from the scratch
---directory, not the per-buffer cache, which may not be filled yet (e.g. right after startup)
---@param ft string|nil Filetype of the pad being opened or resized
---@return number
local function badge_count(ft)
	local bufnr = vim.api.nvim_get_current_buf()
	local source = vim.api.nvim_buf_get_name(bufnr)
	if vim.b[bufnr].scratch_manager_pad and vim.b[bufnr].scratch_manager_source then
		source = vim.b[bufnr].scratch_manager_source
		ft = ft or vim.bo[bufnr].filetype
	end
	local kinds = count_pad_kinds(source)
	if ft then
		local kind = pad_kind(ft)
		kinds[kind] = math.max(kinds[kind] or 0, 1)
	end
	local count = 0
	for _, n in pairs(kinds) do
		count = count + ((n or 0) > 0 and 1 or 0)
	end
	return count
end

---Columns kept free on the right for stacked badges (indicator.layout = "column"), so pads don't
---cover them: the widest badge (icon + a one-digit count, padding, borders) plus a margin and a gap.
---None with a single badge: there is nothing to switch to, so the pad takes the space.
---@param ft string|nil Filetype of the pad being opened or resized
---@return number
local function badge_gutter(ft)
	local indicator = get_config().indicator or {}
	if not indicator.float or indicator.enabled == false or indicator.layout ~= "column" then
		return 0
	end
	if badge_count(ft) < 2 then
		return 0
	end
	local widest = 0
	for _, key in ipairs({ "icon", "code_icon", "db_icon" }) do
		local icon = indicator[key] or default_config.indicator[key] or ""
		widest = math.max(widest, vim.api.nvim_strwidth(icon) + (indicator.show_count ~= false and 2 or 0))
	end
	return widest + 2 + 2 + 2 -- padding, borders, margin + gap
end

---Width and column for the current pad size
---@param width number Default width
---@param ft string|nil Pad filetype (stacked badges may need room)
---@return number width
---@return number col
local function sized(width, ft)
	local gutter = badge_gutter(ft)
	local columns = vim.o.columns - gutter
	if pad_size == 2 then
		local w = math.floor(columns * 2 / 3)
		return w, columns - w
	elseif pad_size == 3 then
		local margin = math.max(2, math.floor(vim.o.columns * 0.05))
		-- the right margin also leaves room for stacked badges
		return vim.o.columns - margin - math.max(margin, gutter) - 2, margin -- 2 for the borders
	end
	return width, columns - width
end

-- Defined below; pad keys (=w) need it
local get_window_options

---Snacks window keys for a pad filetype: wrap toggle everywhere, run keys for runnable filetypes
---@param ft string|nil
---@return table
local function pad_keys(ft)
	local lang = languages.get(ft)
	local config = (get_config().run or {})[ft] or {}
	local keys = {}
	if lang.run and config.enabled ~= false then
		keys.run = runner.run_key(ft, config)
		if lang.run.inline and config.inline ~= false then
			keys.value = runner.dump_detail_key()
		end
	end
	local extra = lang.keys and lang.keys(config)
	if extra then
		keys = vim.tbl_extend("force", keys, extra)
	end
	local watch_key = (get_config().keymaps or {}).pad_watch
	if watch_key and lang.run and lang.run.watchable and config.enabled ~= false then
		keys.watch = {
			watch_key,
			function(self)
				M.toggle_watch(self.buf)
			end,
			desc = "Watch",
		}
	end
	local help_key = (get_config().keymaps or {}).pad_help
	if help_key then
		keys.help = {
			help_key,
			function(self)
				M.show_help(self.buf)
			end,
			desc = "Help",
		}
	end
	local size_key = (get_config().keymaps or {}).pad_size
	if size_key then
		keys.size = {
			size_key,
			function(self)
				pad_size = pad_size % 3 + 1
				local opts = get_window_options(nil, nil, vim.bo[self.buf].filetype)
				vim.api.nvim_win_set_config(self.win, {
					relative = "editor",
					row = opts.row,
					col = opts.col,
					width = opts.width,
					height = opts.height,
				})
				runner.relayout(self.win)
				pcall(M.refresh_indicator) -- the badge connector follows the pad's edge
			end,
			desc = "Size",
		}
	end
	keys.wrap = {
		"<M-z>",
		function(self)
			local win = self.win
			local on = not vim.wo[win].wrap
			vim.wo[win].wrap = on
			vim.wo[win].linebreak = on
		end,
		desc = "Wrap",
		mode = { "n", "i" },
	}
	return keys
end

---Get window options for scratch buffer positioning
---@param width number|nil Window width
---@param height number|nil Window height
---@param ft string|nil Pad filetype (adds run keys for runnable filetypes)
---@return table Window configuration for snacks.nvim
---@private
function get_window_options(width, height, ft)
	local config = get_config()
	width = width or config.width or math.min(math.floor(vim.o.columns / 3), 100)
	height = height or config.height or default_window_height()
	local col
	width, col = sized(width, ft)

	local wo = {
		winhighlight = "FloatBorder:" .. border_hl(pad_kind(ft)) .. ",FloatTitle:ScratchManagerTitle,",
		-- Set explicitly: otherwise the window inherits the global 'wrap' (often off)
		wrap = wraps(pad_kind(ft)),
		linebreak = wraps(pad_kind(ft)),
	}
	if ft then
		wo = vim.tbl_extend("force", wo, languages.get(ft).wo or {})
	end

	return {
		row = 1,
		col = col,
		width = width,
		height = height,
		wo = wo,
		keys = pad_keys(ft),
	}
end

---Format buffer name for display
---@param name string Base buffer name
---@return string Formatted name with "Scratch Pad" prefix
---@private
local function format_buffer_name(name)
	return "Scratch Pad (" .. name .. ")"
end

---Get buffer configuration based on current buffer
---
---Pads are keyed the same way snacks.nvim keys its scratch files: by name, Neovim's
---working directory (not the buffer's directory), git branch, and filetype.
---@param bufnr number Buffer number
---@param file_type string|nil Filetype override (defaults to the buffer's detected filetype)
---@return ScratchPadConfig Configuration for scratch buffer
---@private
local function get_buffer_config(bufnr, file_type)
	local config = get_config()
	local slice_width = math.floor(vim.o.columns / 3)
	local max_width = config.width or 100
	local calculated_width = slice_width < max_width and slice_width or max_width

	local cwd = vim.fs.normalize((vim.uv or vim.loop).cwd())
	local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
	local ft = file_type or vim.filetype.match({ filename = name }) or config.default_filetype
	local icon = get_snacks().util.icon(ft, "filetype")

	return {
		width = config.width or calculated_width,
		height = config.height,
		path = vim.fn.fnamemodify(cwd, ":p:~"),
		branch = utils.get_git_branch(cwd),
		name = name,
		fmtName = format_buffer_name(name),
		ft = ft,
		icon = icon,
		file = nil,
	}
end

---Check whether a snacks scratch item belongs to the given buffer context
---@param item table Scratch item from snacks.scratch.list()
---@param config ScratchPadConfig Buffer configuration
---@return boolean
---@private
local function item_matches(item, config)
	local wd = item.cwd and vim.fn.fnamemodify(item.cwd, ":p:~") or ""
	if get_scratch_filename(item.name) ~= config.name or wd ~= config.path then
		return false
	end
	-- branch/ft are optional so callers (and the public API) can match more loosely
	if config.branch ~= nil and (item.branch or "") ~= config.branch then
		return false
	end
	if config.match_ft and item.ft ~= config.ft then
		return false
	end
	return true
end

---Directory where snacks.nvim stores scratch files
---@return string root Normalized scratch root directory
---@private
local function scratch_root()
	local default_root = vim.fn.stdpath("data") .. "/scratch"
	local ok, scratch_config = pcall(function()
		return get_snacks().config.get("scratch", { root = default_root })
	end)
	local root = ok and type(scratch_config) == "table" and scratch_config.root or default_root
	return vim.fs.normalize(root)
end

---Remember which file the (now current) pad was opened from, e.g. so C# pads can reference its
---project. Kept in `b:scratch_manager_source` and persisted per pad file.
---@param source_bufnr number Buffer the pad was opened from
---@private
local function remember_source(source_bufnr)
	local pad = vim.api.nvim_get_current_buf()
	if pad == source_bufnr or not vim.api.nvim_buf_is_valid(source_bufnr) then
		return
	end
	local source = vim.api.nvim_buf_get_name(source_bufnr)
	local pad_file = vim.fs.normalize(vim.api.nvim_buf_get_name(pad))
	if source == "" or not vim.startswith(pad_file, scratch_root() .. "/") then
		return
	end
	vim.b[pad].scratch_manager_source = source
	if store.get("pad_sources", pad_file) ~= source then
		store.set("pad_sources", pad_file, source)
	end
	-- Now that the source is known, a mirrored pad can get its project reference (C#)
	local mirror = require("scratch-manager.lsp").mirror(pad)
	local lang = languages.get(vim.bo[pad].filetype)
	if mirror and lang.prepare_pad then
		pcall(lang.prepare_pad, pad, (get_config().run or {})[vim.bo[pad].filetype] or {})
		require("scratch-manager.lsp").sync(pad)
	end
end

---Find the scratch item whose file is shown in the given buffer
---
---A pad that has not been written yet is not in the list, so anything under the scratch
---root is treated as a pad too.
---@param buffers table List of scratch items from snacks.scratch.list()
---@param bufnr number Buffer number
---@return table|nil item The scratch item, or nil if the buffer is not a scratch pad
---@private
local function pad_for_buffer(buffers, bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if bufname == "" then
		return nil
	end
	bufname = vim.fs.normalize(bufname)
	for _, item in ipairs(buffers) do
		if item.file and vim.fs.normalize(item.file) == bufname then
			return item
		end
	end
	if vim.startswith(bufname, scratch_root() .. "/") then
		return { file = bufname, ft = vim.bo[bufnr].filetype, name = format_buffer_name("unsaved") }
	end
	return nil
end

---Custom scratch buffer selection (replaces snacks.scratch.select)
---@private
-- Defined below (needs the pad helpers): the =s list
local custom_scratch_select

---Define highlight groups for scratch manager UI
---@private
local function define_highlights()
	local config = get_config()
	local hl = config.highlights or {}

	-- Scratch buffer title - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerTitle", hl.scratch_title or { fg = "#74c7ec", bold = true, italic = false })

	-- Scratch Buffer Border - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerBorder", hl.scratch_border or { fg = "#F7DC6F", bold = true })

	-- Code pad border - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerCodeBorder", hl.code_border or { fg = "#cba6f7", bold = true })

	-- DB pad border - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerDbBorder", hl.db_border or { fg = "#a6d189", bold = true })

	-- Select list Border - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerSelectBorder", hl.border or { fg = "#89b4fa", bold = true })

	-- Select list Separator - configurable (defaults to border if not set)
	vim.api.nvim_set_hl(0, "ScratchManagerSeparator", hl.separator or hl.border or { fg = "#89b4fa", bold = true })

	-- Select list Header - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerSelectHeader", hl.header or { fg = "#a6d189", bold = true })

	-- Select list Footer - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerSelectFooter", hl.footer or { fg = "#74c7ec", bold = true, italic = true })

	-- snacks dashboard header (legacy option, kept for compatibility)
	if config.dashboard_color then
		vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = config.dashboard_color })
	end

	-- Floating badge icon - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerBadge", hl.badge or { fg = "#74c7ec", bold = true })

	-- Pad help (=h): `default` links, so colorschemes or users can override them
	vim.api.nvim_set_hl(0, "ScratchManagerHelpTitle", { link = "ScratchManagerTitle", default = true })
	vim.api.nvim_set_hl(0, "ScratchManagerHelpHeading", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "ScratchManagerHelpRule", { link = "FloatBorder", default = true })
	vim.api.nvim_set_hl(0, "ScratchManagerHelpCode", { link = "String", default = true })
	vim.api.nvim_set_hl(0, "ScratchManagerHelpBold", { bold = true, default = true })

	-- Inline .Dump() values in C# pads - configurable (orange, so they don't look like diagnostics)
	vim.api.nvim_set_hl(0, "ScratchManagerDump", hl.dump or { fg = "#fab387", italic = true })

	-- Selection highlight for active item (not configurable)
	vim.api.nvim_set_hl(0, "ScratchManagerSelected", {
		bg = "#45475a", -- Subtle background highlight
		bold = true,
	})
end

-- Public API functions

---Open a new scratch buffer
---@param config ScratchPadConfig Buffer configuration
function M.open_new_scratch_pad(config)
	get_snacks().scratch({
		ft = config.ft,
		name = config.fmtName,
		win = get_window_options(config.width, config.height, config.ft),
	})
end

---Open an existing scratch buffer
---@param config ScratchPadConfig Buffer configuration with file information
function M.open_scratch(config)
	-- Handle both our config objects and snacks.nvim buffer items
	get_snacks().scratch.open({
		icon = config.icon,
		file = config.file,
		name = config.fmtName or config.name, -- snacks items use 'name', our config uses 'fmtName'
		ft = config.ft,
		win = get_window_options(config.width, config.height, config.ft),
	})
end

---Find all scratch pads matching the current context, most recently modified first
---@param buffers table List of existing scratch buffers from snacks.nvim
---@param config ScratchPadConfig Current buffer configuration (`branch` and `match_ft` narrow the match)
---@return table[] pads Matching scratch items
function M.find_scratch_pads(buffers, config)
	assert(config.path, "no path provided")
	assert(config.name, "no filename provided")

	local pads = {}
	for _, item in ipairs(buffers) do
		if item_matches(item, config) then
			table.insert(pads, item)
		end
	end
	return pads
end

---Find existing scratch buffer matching current context
---@param buffers table List of existing scratch buffers from snacks.nvim
---@param config ScratchPadConfig Current buffer configuration
---@return table|nil Existing scratch buffer info or nil if not found
---Pad counts per kind for a source file, from the scratch directory
---@param source string|nil Source file path
---@return { notes: number, code: number, db: number }
count_pad_kinds = function(source)
	local kinds = { notes = 0, code = 0, db = 0 }
	if not source or source == "" or vim.startswith(vim.fs.normalize(source), scratch_root() .. "/") then
		return kinds
	end
	local ok, buffers = pcall(function()
		return get_snacks().scratch.list()
	end)
	if not ok or type(buffers) ~= "table" then
		return kinds
	end
	local cwd = vim.fs.normalize((vim.uv or vim.loop).cwd())
	local config = {
		name = vim.fn.fnamemodify(source, ":t"),
		path = vim.fn.fnamemodify(cwd, ":p:~"),
		branch = utils.get_git_branch(cwd),
	}
	for _, item in ipairs(M.find_scratch_pads(buffers, config)) do
		local kind = pad_kind(item.ft)
		kinds[kind] = kinds[kind] + 1
	end
	return kinds
end

---Pads that belong with an open pad (same source file name, directory and branch as recorded when
---the pad was created), so a later `:cd` doesn't separate them. nil when the pad isn't listed yet.
---@param bufnr number Pad buffer
---@return table[]|nil items
local function pad_siblings(bufnr)
	local ok, buffers = pcall(function()
		return get_snacks().scratch.list()
	end)
	if not ok or type(buffers) ~= "table" then
		return nil
	end
	local own = pad_for_buffer(buffers, bufnr)
	if not (own and own.cwd) then
		return nil
	end
	return vim.tbl_filter(function(item)
		return item.name == own.name and item.cwd == own.cwd and (item.branch or "") == (own.branch or "")
	end, buffers)
end

---Pad counts per kind for an open pad's siblings (itself included, even before its first save)
---@param bufnr number Pad buffer
---@param source string|nil Its source file, used when the pad isn't listed yet
---@return { notes: number, code: number, db: number }
local function count_sibling_kinds(bufnr, source)
	local siblings = pad_siblings(bufnr)
	local kinds = siblings and { notes = 0, code = 0, db = 0 } or count_pad_kinds(source)
	for _, item in ipairs(siblings or {}) do
		local kind = pad_kind(item.ft)
		kinds[kind] = kinds[kind] + 1
	end
	local own = pad_kind(vim.bo[bufnr].filetype)
	kinds[own] = math.max(kinds[own] or 0, 1)
	return kinds
end

-- The editor (non-floating) window used last: the "current source" behind any open pad
local last_editor_win

---The editor window behind the pads: the last one used in this tab, else the first one
---@return number|nil win
local function context_window()
	if last_editor_win and vim.api.nvim_win_is_valid(last_editor_win)
		and vim.api.nvim_win_get_config(last_editor_win).relative == ""
		and vim.api.nvim_win_get_tabpage(last_editor_win) == vim.api.nvim_get_current_tabpage() then
		return last_editor_win
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_config(win).relative == "" then
			return win
		end
	end
	return nil
end

---The current source: the file in the editor window behind the pads (nil when that isn't a file)
---@return number|nil bufnr
---@return string|nil name
local function context_source()
	local win = context_window()
	if not win then
		return nil, nil
	end
	local buf = vim.api.nvim_win_get_buf(win)
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" or vim.bo[buf].buftype ~= "" or vim.startswith(vim.fs.normalize(name), scratch_root() .. "/") then
		return nil, nil
	end
	return buf, name
end

---Does this pad belong to the current source, or is it another file's pad (opened from the `=s`
---list)? Without a current source, every pad counts as its own.
---@param pad_buf number
---@param source_name string|nil Current source file
---@return boolean
local function is_own_pad(pad_buf, source_name)
	if not source_name then
		return true
	end
	local recorded = vim.b[pad_buf].scratch_manager_source
		or store.get("pad_sources", vim.fs.normalize(vim.api.nvim_buf_get_name(pad_buf)))
	if recorded and recorded ~= "" then
		return vim.fs.normalize(recorded) == vim.fs.normalize(source_name)
	end
	-- Pads from before sources were recorded: by file name
	local ok, buffers = pcall(function()
		return get_snacks().scratch.list()
	end)
	local item = ok and type(buffers) == "table" and pad_for_buffer(buffers, pad_buf) or nil
	return item ~= nil and get_scratch_filename(item.name) == vim.fn.fnamemodify(source_name, ":t")
end

function M.find_existing_scratch_pad(buffers, config)
	local item = M.find_scratch_pads(buffers, config)[1]
	if not item then
		return nil
	end
	return {
		name = item.name,
		icon = item.icon or get_snacks().util.icon(item.ft, "filetype"),
		file = item.file,
		ft = item.ft,
	}
end

---Remove a scratch pad: wipe its buffer (closing any windows) and delete the file
---@param item table Scratch item from snacks.scratch.list()
---@private
---Delete a pad and everything kept for it: its buffer (wiped first, so snacks' save-on-hide or
---autosave can't write the file back), the file, its remembered source and DB connection, its run
---directory and its language server mirror
---@param file string Pad file
---@param ft string|nil Pad filetype
---@return boolean deleted
local function delete_pad_file(file, ft)
	file = vim.fs.normalize(file)
	local bufnr = vim.fn.bufnr(file)
	local mirror = bufnr > 0 and pad_lsp.mirror(bufnr) or nil
	if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	end
	if vim.fn.filereadable(file) == 1 and vim.fn.delete(file) ~= 0 then
		return false
	end
	for _, name in ipairs({ "pad_sources", "sql_connections" }) do
		if store.get(name, file) ~= nil then
			store.set(name, file, nil)
		end
	end
	vim.fn.delete(runner.work_dir(file, ft), "rf")
	if mirror then
		vim.fn.delete(vim.fs.dirname(mirror), "rf")
	end
	return true
end

local function remove_pad(item)
	if not delete_pad_file(item.file, item.ft) then
		vim.notify("Failed to delete scratch pad: " .. item.file, vim.log.levels.ERROR)
		return
	end
	vim.notify(("Deleted scratch pad %s (%s)"):format(get_scratch_filename(item.name), item.ft), vim.log.levels.INFO)
end

---Delete the current scratch buffer file
---
---Works from inside a scratch pad (deletes that pad) or from its source buffer (deletes
---the pad for this file on the current branch; asks which one if there are several).
function M.delete_current_scratch_pad()
	local buffers = get_snacks().scratch.list()
	local bufnr = vim.api.nvim_get_current_buf()

	local pads
	local own_pad = pad_for_buffer(buffers, bufnr)
	if own_pad then
		pads = { own_pad }
	else
		pads = M.find_scratch_pads(buffers, get_buffer_config(bufnr))
	end

	if #pads == 0 then
		vim.notify("No scratch pad found for this buffer", vim.log.levels.INFO)
		return
	end

	local function confirm_and_remove(item)
		if not item then
			return
		end
		local prompt = ("Delete scratch pad %s (%s)?"):format(get_scratch_filename(item.name), item.ft)
		if vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1 then
			remove_pad(item)
			M.refresh_indicator()
		end
	end

	if #pads == 1 then
		confirm_and_remove(pads[1])
	else
		vim.ui.select(pads, {
			prompt = "Delete which scratch pad?",
			format_item = function(item)
				return ("%s (%s)"):format(get_scratch_filename(item.name), item.ft)
			end,
		}, confirm_and_remove)
	end
end

---Toggle scratch buffer with optional filetype
---@param file_type string|nil Optional filetype to use for new scratch buffer
function M.toggle_scratch_pad(file_type)
	local buffers = get_snacks().scratch.list()
	local bufnr = vim.api.nvim_get_current_buf()

	-- From inside a pad: the key of its own kind closes it; another kind's key flips to that pad
	-- (opening or creating it) for the same source file
	local own_pad = pad_for_buffer(buffers, bufnr)
	if own_pad then
		-- Visiting another file's pad (from the =s list): every key means the current source's pad
		-- of that kind, opened or created for the current source
		local context_buf, context_name = context_source()
		local context_win = context_window()
		if context_name and context_win and context_buf ~= bufnr and not is_own_pad(bufnr, context_name) then
			M.open_scratch(own_pad) -- closes it
			vim.api.nvim_set_current_win(context_win)
			return M.toggle_scratch_pad(file_type)
		end
		local wanted = file_type and pad_kind(file_type) or "code"
		local source = vim.b[bufnr].scratch_manager_source
			or store.get("pad_sources", vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)))
		local siblings = pad_siblings(bufnr)
		M.open_scratch(own_pad) -- closes it
		if wanted == pad_kind(own_pad.ft) or not source or source == "" then
			return
		end
		-- Back to the source file: its window if one shows it, else the first regular window
		local source_buf = vim.fn.bufnr(source)
		local target
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_config(win).relative == "" then
				if vim.api.nvim_win_get_buf(win) == source_buf then
					target = win
					break
				end
				target = target or win
			end
		end
		if not target then
			return
		end
		vim.api.nvim_set_current_win(target)
		if vim.api.nvim_win_get_buf(target) ~= source_buf then
			vim.cmd.edit(vim.fn.fnameescape(source))
		end
		source_buf = vim.api.nvim_get_current_buf()
		-- The other pad belongs with this one: same name, directory and branch as recorded for this pad,
		-- whatever `:pwd` is now
		if siblings and own_pad.cwd then
			local ft = file_type or vim.filetype.match({ filename = source }) or get_config().default_filetype
			for _, item in ipairs(siblings) do
				if item.ft == ft then
					M.open_scratch(item)
					remember_source(source_buf)
					return
				end
			end
			-- Not there yet: create it under the same key snacks would use (count|icon|name|cwd|branch)
			local key = table.concat({ "1", "", (own_pad.name:gsub("|", " ")), vim.fs.normalize(own_pad.cwd), own_pad.branch or "" }, "|")
			M.open_scratch({
				file = scratch_root() .. "/" .. get_snacks().util.file_encode(key .. "." .. ft),
				fmtName = own_pad.name,
				ft = ft,
			})
			remember_source(source_buf)
			return
		end
		return M.toggle_scratch_pad(file_type)
	end

	local config = get_buffer_config(bufnr, file_type)
	config.match_ft = true

	local existing_pad = M.find_existing_scratch_pad(buffers, config)
	if existing_pad then
		config.fmtName = existing_pad.name
		config.file = existing_pad.file
		config.icon = existing_pad.icon
		M.open_scratch(config)
	else
		M.open_new_scratch_pad(config)
	end
	remember_source(bufnr)
end

---Badge/statusline text for one pad kind: its icon, plus the count when there are several
---@param kind "notes"|"code"|"db"
---@param count number
---@return string
local function kind_text(kind, count)
	local indicator = get_config().indicator or {}
	local key = ({ code = "code_icon", db = "db_icon" })[kind] or "icon"
	local icon = indicator[key] or default_config.indicator[key]
	if count > 1 and indicator.show_count ~= false then
		return icon .. " " .. count
	end
	return icon
end

---Short age: "now", "5m", "3h", "2d", "4w", "8mo", "1y"
---@param mtime number|nil Seconds since the epoch
---@return string
local function age_text(mtime)
	if not mtime then
		return ""
	end
	local seconds = math.max(0, os.time() - mtime)
	for _, step in ipairs({ { 31536000, "y" }, { 2592000, "mo" }, { 604800, "w" }, { 86400, "d" }, { 3600, "h" }, { 60, "m" } }) do
		if seconds >= step[1] then
			return math.floor(seconds / step[1]) .. step[2]
		end
	end
	return "now"
end

---The =s list: every pad with its type, age and state, ordered this file → this project → the rest
---(newest first in each). Pads from another branch (than their project is on now) are left out
---unless show_all; pads whose source file is gone are kept, dimmed and tagged.
---@param show_all boolean|nil Include pads from other branches
---@return table[] items
---@return number hidden Pads left out (other branches)
local function pad_list(show_all)
	local ok, buffers = pcall(function()
		return get_snacks().scratch.list()
	end)
	if not ok or type(buffers) ~= "table" then
		return {}, 0
	end
	local context_buf = context_source()
	local mine = {}
	if context_buf then
		for _, item in ipairs(M.find_scratch_pads(buffers, get_buffer_config(context_buf))) do
			mine[item.file] = true
		end
	end
	local cwd = vim.fs.normalize((vim.uv or vim.loop).cwd())
	local sources = store.read("pad_sources")
	local branches = {}
	local items, hidden = {}, 0
	for _, item in ipairs(buffers) do
		local entry = vim.tbl_extend("force", {}, item)
		local kind = pad_kind(item.ft)
		local item_cwd = item.cwd and vim.fs.normalize(item.cwd) or ""
		entry.kind_icon = kind_text(kind, 1)
		entry.kind_hl = border_hl(kind)
		entry.mtime = item.stat and item.stat.mtime and item.stat.mtime.sec or 0
		entry.age = age_text(entry.mtime > 0 and entry.mtime or nil)
		entry.group = mine[item.file] and 1 or (item_cwd == cwd and 2 or 3)
		entry.source = sources[vim.fs.normalize(item.file)]
		if entry.source and vim.fn.filereadable(entry.source) == 0 then
			entry.state = "missing"
			entry.display_name = get_scratch_filename(item.name) .. " (missing)"
		elseif (item.branch or "") ~= "" and item_cwd ~= "" then
			if branches[item_cwd] == nil then
				branches[item_cwd] = utils.get_git_branch(item_cwd)
			end
			if branches[item_cwd] ~= item.branch then
				entry.state = "branch"
			end
		end
		entry.dim = entry.state ~= nil
		if entry.state == "branch" and not show_all then
			hidden = hidden + 1
		else
			table.insert(items, entry)
		end
	end
	table.sort(items, function(a, b)
		if a.group ~= b.group then
			return a.group < b.group
		end
		return a.mtime > b.mtime
	end)
	return items, hidden
end

---Show the =s list
---@param state { show_all: boolean|nil, index: number|nil }|nil
custom_scratch_select = function(state)
	state = state or {}
	local items, hidden = pad_list(state.show_all)
	if #items == 0 and hidden > 0 then
		state.show_all = true
		items, hidden = pad_list(true)
	end
	if #items == 0 then
		vim.notify("No scratch pads yet", vim.log.levels.INFO)
		return
	end
	local counter = ("%d pad%s"):format(#items, #items == 1 and "" or "s")
	if hidden > 0 then
		counter = counter .. (" · %d on other branches (b)"):format(hidden)
	elseif state.show_all then
		counter = counter .. " · all branches (b)"
	end
	local function reopen(index)
		vim.schedule(function()
			custom_scratch_select({ show_all = state.show_all, index = index })
		end)
	end
	selection.create_custom_selection(items, {
		prompt = " Scratch Pads ",
		counter_text = counter,
		start_idx = state.index,
		hints = " <CR> open · o source · d delete · b branches · q quit ",
		actions = {
			d = {
				desc = "Delete pads",
				modes = { "n", "x" },
				fn = function(chosen, index)
					local names = vim.tbl_map(function(item)
						return ("  %s (%s)"):format(get_scratch_filename(item.name), item.ft)
					end, chosen)
					local question = (#chosen == 1 and "Delete scratch pad?" or ("Delete %d scratch pads?"):format(#chosen))
						.. "\n" .. table.concat(names, "\n")
					if vim.fn.confirm(question, "&Yes\n&No", 2) ~= 1 then
						return
					end
					local deleted = 0
					for _, item in ipairs(chosen) do
						if delete_pad_file(item.file, item.ft) then
							deleted = deleted + 1
						end
					end
					vim.notify(("Deleted %d scratch pad%s"):format(deleted, deleted == 1 and "" or "s"), vim.log.levels.INFO)
					selection.close()
					pcall(M.refresh_indicator)
					if #items > deleted then
						reopen(index)
					end
				end,
			},
			o = {
				desc = "Open the pad's source file",
				fn = function(chosen)
					local item = chosen[1]
					if not item.source then
						vim.notify("This pad's source file isn't known", vim.log.levels.INFO)
						return
					end
					if vim.fn.filereadable(item.source) == 0 then
						vim.notify("Source file is gone: " .. item.source, vim.log.levels.WARN)
						return
					end
					selection.close()
					local win = context_window()
					if win then
						vim.api.nvim_set_current_win(win)
					end
					vim.cmd.edit(vim.fn.fnameescape(item.source))
				end,
			},
			b = {
				desc = "Show or hide pads from other branches",
				fn = function(_, index)
					selection.close()
					state.show_all = not state.show_all
					vim.schedule(function()
						custom_scratch_select({ show_all = state.show_all, index = index })
					end)
				end,
			},
		},
	}, function(selected_item)
		if selected_item then
			M.open_scratch(selected_item)
		end
	end, get_config())
end

---Pad counts per kind for the current buffer (cached by refresh_indicator)
---@return { notes: number, code: number, db: number }
local function current_kinds()
	local kinds = vim.b.scratch_manager_pad_kinds
	-- Stacked badges stay visible next to an open pad: inside a pad, show its source file's pads
	if (get_config().indicator or {}).layout == "column" then
		local name = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
		if name ~= "" and vim.startswith(name, scratch_root() .. "/") then
			local current = vim.api.nvim_get_current_buf()
			local _, context_name = context_source()
			if context_name and not is_own_pad(current, context_name) then
				kinds = count_pad_kinds(context_name) -- visiting another file's pad: the current source's pads
			else
				local source = vim.b.scratch_manager_source or store.get("pad_sources", name)
				kinds = count_sibling_kinds(current, source)
			end
		end
	end
	return type(kinds) == "table" and kinds or { notes = 0, code = 0, db = 0 }
end

---Show, move or hide the floating badges for the current buffer
---Notes sits in the corner, then code, then db to the left; each only when that kind of pad exists
---@private
local function update_badge()
	local indicator = get_config().indicator or {}
	if not indicator.float or indicator.enabled == false then
		badge.hide()
		return
	end
	-- Entering a badge itself (a click) must not hide it before the click is handled,
	-- and badges must not reappear while one is growing into its pad
	if badge.is_badge_win() or badge.is_animating() then
		return
	end
	local kinds = current_kinds()
	local column = indicator.layout == "column"
	local right = vim.o.columns - 1 -- one cell of margin from the editor edge
	-- Stacked badges start level with the pads' top border
	local row = column and math.max(badge.tabline_height(), get_window_options().row) or badge.tabline_height()
	for _, kind in ipairs(KINDS) do
		local count = kinds[kind] or 0
		if count > 0 then
			local text = kind_text(kind, count)
			local col = right - (badge.width(text) + 2) -- + 2 border cells
			badge.show(kind, text, col, border_hl(kind), function()
				M.open_pad_from_badge(kind)
			end, { transparent = indicator.transparent, row = row })
			if column then
				row = row + 3 -- stacked: next badge below this one (1 line + 2 borders)
			else
				right = col - 1 -- one cell gap between badges
			end
		else
			badge.hide(kind)
		end
	end
	-- Stacked badges: join the open pad's border to its badge, marking it as the selected one
	-- (the connector window is moved, not reopened)
	if column then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local buf = vim.api.nvim_win_get_buf(win)
			local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
			if vim.api.nvim_win_get_config(win).relative ~= "" and name ~= ""
				and vim.startswith(name, scratch_root() .. "/") then
				local _, context_name = context_source()
				if not is_own_pad(buf, context_name) then
					break -- another file's pad: none of these badges is its own
				end
				local kind = pad_kind(vim.bo[buf].filetype)
				return badge.connect(kind, win, border_hl(kind))
			end
		end
	end
	badge.disconnect()
end

---Recompute whether a buffer has scratch pads and cache it in `vim.b.scratch_manager_pads`
---@param bufnr number|nil Buffer number (defaults to the current buffer)
function M.refresh_indicator(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local kinds = { notes = 0, code = 0, db = 0 }
	if vim.bo[bufnr].buftype == "" and vim.api.nvim_buf_get_name(bufnr) ~= "" then
		local buffers = get_snacks().scratch.list()
		if not pad_for_buffer(buffers, bufnr) then
			for _, item in ipairs(M.find_scratch_pads(buffers, get_buffer_config(bufnr))) do
				local kind = pad_kind(item.ft)
				kinds[kind] = kinds[kind] + 1
			end
		end
	end
	local count = kinds.notes + kinds.code + kinds.db
	vim.b[bufnr].scratch_manager_pads = count
	vim.b[bufnr].scratch_manager_pad_kinds = kinds
	update_badge()

	local indicator = get_config().indicator or {}
	if indicator.notify and count > 0 and not vim.b[bufnr].scratch_manager_notified then
		vim.b[bufnr].scratch_manager_notified = true
		local keys = get_config().keymaps or {}
		vim.notify(
			("Scratch pad available (%s to open)"):format(keys.toggle_lang or "toggle"),
			vim.log.levels.INFO,
			{ title = "scratch-manager" }
		)
	end
end

---Pads of the current buffer, optionally only one kind
---@param kind "notes"|"code"|"db"|nil
---@return table[]
local function current_pads(kind)
	local buffers = get_snacks().scratch.list()
	local pads = M.find_scratch_pads(buffers, get_buffer_config(vim.api.nvim_get_current_buf()))
	if kind then
		pads = vim.tbl_filter(function(item)
			return pad_kind(item.ft) == kind
		end, pads)
	end
	return pads
end

---Open the existing scratch pad for the current buffer, asking which one if there are several
---@param kind "notes"|"code"|"db"|nil Only consider one kind of pad
function M.open_pad(kind)
	local source = vim.api.nvim_get_current_buf()
	local pads = current_pads(kind)
	if #pads == 0 then
		vim.notify("No scratch pad found for this buffer", vim.log.levels.INFO)
	elseif #pads == 1 then
		M.open_scratch(pads[1])
		remember_source(source)
	else
		vim.ui.select(pads, {
			prompt = "Open which scratch pad?",
			format_item = function(item)
				return ("%s (%s)"):format(get_scratch_filename(item.name), item.ft)
			end,
		}, function(item)
			if item then
				M.open_scratch(item)
				remember_source(source)
			end
		end)
	end
end

---Click handler for a floating badge: return to the source window and open that kind of pad
---@param kind "notes"|"code"|"db"|nil
---@private
function M.open_pad_from_badge(kind)
	local target = vim.fn.win_getid(vim.fn.winnr("#"))
	if target == 0 or badge.is_badge_win(target) or not vim.api.nvim_win_is_valid(target) then
		-- Fall back to the first normal (non-floating) window
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_config(win).relative == "" then
				target = win
				break
			end
		end
	end
	-- Clicked while a pad is open (stacked badges stay visible): close it; its own badge just
	-- closes it, another kind's badge opens that pad for the same source file instead
	local shown_buf = vim.api.nvim_win_get_buf(target)
	local shown = vim.fs.normalize(vim.api.nvim_buf_get_name(shown_buf))
	if shown ~= "" and vim.startswith(shown, scratch_root() .. "/") then
		local open_kind = pad_kind(vim.bo[shown_buf].filetype)
		local _, context_name = context_source()
		local own = is_own_pad(shown_buf, context_name)
		pcall(vim.api.nvim_win_close, target, false)
		target = context_window()
		-- Its own badge closes the current source's pad; from another file's pad, every badge opens
		-- the current source's pad of that kind
		if not target or (open_kind == kind and own) then
			if target then
				vim.api.nvim_set_current_win(target)
			end
			return
		end
	end
	vim.api.nvim_set_current_win(target)

	local indicator = get_config().indicator or {}
	if indicator.animate then
		local pads = current_pads(kind)
		if #pads == 1 then
			local grow_kind = kind or pad_kind(pads[1].ft)
			local source = vim.api.nvim_get_current_buf()
			-- Same geometry the pad opens with (its filetype decides whether badges need room)
			badge.grow(grow_kind, get_window_options(nil, nil, pads[1].ft), border_hl(pad_kind(pads[1].ft)), function()
				M.open_scratch(pads[1])
				remember_source(source)
			end)
			return
		end
	end
	M.open_pad(kind)
end

---Save a pad buffer if it has unsaved changes. noautocmd: no format-on-save or other write hooks
---for scratch content (and no "written" messages)
---@param bufnr number
---@private
local function autosave_pad(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified and vim.bo[bufnr].buftype == "" then
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("silent! noautocmd write")
		end)
		-- Servers that read files see the same text as the pad
		require("scratch-manager.lsp").sync(bufnr)
	end
end

---Run the pad language's on_open hook once (DB pads: attach the remembered connection)
---@param bufnr number
---@private
local function on_pad_open(bufnr)
	-- snacks loads the pad and sets its filetype before the pad has a window, so BufEnter/FileType
	-- run in Neovim's hidden autocmd window (top-left, no border). Anything slow or redrawing in
	-- on_open (DB pads: loading the SQL provider and its connections, its notification) would show
	-- that window with the pad's text; run it once the pad is in its own window
	if vim.fn.win_gettype() == "autocmd" then
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				on_pad_open(bufnr)
			end
		end)
		return
	end
	local ft = vim.bo[bufnr].filetype
	local lang = languages.get(ft)
	if ft == "" or not lang.on_open or vim.b[bufnr].scratch_manager_opened == ft then
		return
	end
	vim.b[bufnr].scratch_manager_opened = ft
	pcall(lang.on_open, bufnr, (get_config().run or {})[ft] or {})
end

---Is this buffer a scratch pad (its file lives under the snacks scratch root)?
---@param bufnr number
---@return boolean
local function is_pad_buffer(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr)
		and vim.startswith(vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)), scratch_root() .. "/")
end

---Pad name (e.g. "StringExtensions.cs") from a pad buffer's encoded snacks file name
---@param bufnr number
---@return string|nil
local function pad_name_of(bufnr)
	local ok, decoded = pcall(function()
		return get_snacks().util.file_decode(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t"))
	end)
	return ok and type(decoded) == "string" and decoded:match("Scratch Pad %((.-)%)") or nil
end

---Mirror a pad for language servers (when its language supports it) and let its profile prepare it
---@param bufnr number
---@return boolean mirrored
local function mirror_pad(bufnr)
	if pad_lsp.mirror(bufnr) then
		return true
	end
	if not pad_lsp.enable(bufnr, pad_name_of(bufnr)) then
		return false
	end
	local ft = vim.bo[bufnr].filetype
	local lang = languages.get(ft)
	if lang.prepare_pad then
		pcall(lang.prepare_pad, bufnr, (get_config().run or {})[ft] or {})
		pad_lsp.sync(bufnr)
	end
	return true
end

-- Language servers on pads (see the `lsp` option). Detaching after attach is too late: the server
-- has already been sent the pad (and Roslyn crashes on the next change to it), so attaching is
-- declined up front. vim.lsp.start attaches every buffer through vim.lsp.buf_attach_client, for
-- new and reused clients, so that's where pads are turned away.
local lsp_block, lsp_allow, lsp_mirror = false, {}, true

---Should this server be kept off this buffer?
---@param bufnr number
---@param client_id number
---@return boolean
local function block_lsp(bufnr, client_id)
	if not lsp_block then
		return false
	end
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	if not is_pad_buffer(bufnr) then
		return false
	end
	local client = vim.lsp.get_client_by_id(client_id)
	if client and lsp_allow[client.name] then
		return false
	end
	vim.b[bufnr].scratch_manager_pad = true
	-- Servers the pad's language supports run through a clean mirror file (set up right here, so it
	-- doesn't matter which plugin's FileType autocmd ran first)
	if client and lsp_mirror and mirror_pad(bufnr) and pad_lsp.allows(bufnr, client.name) then
		pad_lsp.watch_client(client)
		pad_lsp.refresh_diagnostics(bufnr, client.id)
		return false
	end
	return true
end

---Wrap vim.lsp.buf_attach_client once per Neovim session so pads can decline servers before
---they're sent anything. The wrapper asks the current `block` function, so reloading the plugin
---or turning the option off takes effect without stacking wrappers.
---@param enabled boolean
---@private
local function install_lsp_guard(enabled)
	local guard = rawget(_G, "__scratch_manager_lsp_guard")
	if not guard then
		if not enabled then
			return
		end
		guard = { original = vim.lsp.buf_attach_client }
		rawset(_G, "__scratch_manager_lsp_guard", guard)
		vim.lsp.buf_attach_client = function(bufnr, client_id)
			if guard.block and guard.block(bufnr, client_id) then
				return false
			end
			return guard.original(bufnr, client_id)
		end
	end
	guard.block = enabled and block_lsp or nil
end

---Set up pad buffer hooks: autosave (write after every change, so leaving, closing or quitting
---never asks to save a pad), language on_open hooks, keeping language servers off pads, and the
---`b:scratch_manager_pad` marker other configs can use to recognize pads
---@private
local function setup_autosave()
	local group = vim.api.nvim_create_augroup("ScratchManagerAutosave", { clear = true })

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
		group = group,
		pattern = scratch_root() .. "/*",
		callback = function(args)
			vim.b[args.buf].scratch_manager_pad = true
		end,
	})

	local lsp = get_config().lsp or {}
	lsp_allow = {}
	for _, name in ipairs(lsp.allow or {}) do
		lsp_allow[name] = true
	end
	lsp_block = lsp.detach ~= false
	lsp_mirror = lsp.mirror ~= false
	install_lsp_guard(lsp_block)
	if lsp_block then
		-- Fallback for servers attached some other way: detach as soon as they attach
		vim.api.nvim_create_autocmd("LspAttach", {
			group = group,
			callback = function(args)
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				local mirrored = client and lsp_mirror and pad_lsp.allows(args.buf, client.name)
				if client and not lsp_allow[client.name] and not mirrored and is_pad_buffer(args.buf) then
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(args.buf) and vim.lsp.buf_is_attached(args.buf, client.id) then
							vim.lsp.buf_detach_client(args.buf, client.id)
						end
					end)
				end
			end,
		})
	end

	-- Servers allowed on pads map their own `K` (hover) when they attach; keep the pad's value key,
	-- which falls back to hover
	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(args)
			local ft = vim.bo[args.buf].filetype
			local lang = languages.get(ft)
			local run = (get_config().run or {})[ft] or {}
			if is_pad_buffer(args.buf) and lang.run and lang.run.inline and run.enabled ~= false and run.inline ~= false then
				vim.schedule(function()
					runner.map_value_key(args.buf)
				end)
			end
		end,
	})

	-- Language on_open hooks (DB pads: attach the connection). snacks sets the pad's filetype
	-- after BufEnter, so also catch pads on FileType
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(args)
			if vim.startswith(vim.fs.normalize(vim.api.nvim_buf_get_name(args.buf)), scratch_root() .. "/") then
				on_pad_open(args.buf)
			end
		end,
	})
	if get_config().autosave == false then
		return
	end
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		pattern = scratch_root() .. "/*",
		callback = function(args)
			on_pad_open(args.buf)
			if vim.b[args.buf].scratch_manager_autosave then
				return
			end
			vim.b[args.buf].scratch_manager_autosave = true
			vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufLeave" }, {
				group = group,
				buffer = args.buf,
				callback = function()
					autosave_pad(args.buf)
				end,
			})
			-- Also save shortly after typing pauses in insert mode, so a pad is almost never
			-- unsaved when something else reloads it (e.g. an LSP crash handler running :edit)
			local timer
			vim.api.nvim_create_autocmd("TextChangedI", {
				group = group,
				buffer = args.buf,
				callback = function()
					if timer then
						timer:stop()
					else
						timer = (vim.uv or vim.loop).new_timer()
					end
					timer:start(400, 0, vim.schedule_wrap(function()
						autosave_pad(args.buf)
					end))
				end,
			})
		end,
	})
end

---Turn watch mode on or off for a pad (rerun after edits). Off by default: it's turned on per pad
---and stays on only while the pad is on screen (closing or leaving the pad turns it off; nothing is saved)
---@param bufnr number|nil Pad buffer (defaults to the current buffer)
---@return boolean on
function M.toggle_watch(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ft = vim.bo[bufnr].filetype
	if not (languages.get(ft).run or {}).watchable then
		vim.notify("Watch mode isn't available for " .. (ft ~= "" and ft or "this") .. " pads", vim.log.levels.WARN)
		return false
	end
	local on = runner.watch(bufnr, ft, (get_config().run or {})[ft] or {})
	vim.notify(on and "Watch on: the pad reruns after each edit while it has a value to show (.Dump())"
		or "Watch off", vim.log.levels.INFO)
	return on
end

---Forget a pad left empty: wipe its buffer, delete its file and what was stored for it
---(source file, DB connection, run and mirror directories). Only when no window shows it anymore.
---@param bufnr number
---@private
local function forget_empty_pad(bufnr)
	if not (vim.api.nvim_buf_is_valid(bufnr) and is_pad_buffer(bufnr)) or #vim.fn.win_findbuf(bufnr) > 0 then
		return
	end
	local ft = vim.bo[bufnr].filetype
	if not languages.is_empty(ft, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) then
		return
	end
	delete_pad_file(vim.api.nvim_buf_get_name(bufnr), ft)
	pcall(M.refresh_indicator)
end

---Set up smart persistence: a pad closed with nothing in it is deleted (see `smart_persistence`)
---@private
local function setup_persistence()
	local group = vim.api.nvim_create_augroup("ScratchManagerPersistence", { clear = true })
	if get_config().smart_persistence == false then
		return
	end
	vim.api.nvim_create_autocmd("BufHidden", {
		group = group,
		pattern = scratch_root() .. "/*",
		callback = function(args)
			-- After the window has closed (and snacks' own BufHidden handling)
			vim.schedule(function()
				forget_empty_pad(args.buf)
			end)
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(bufnr) and is_pad_buffer(bufnr) then
					local file = vim.api.nvim_buf_get_name(bufnr)
					if languages.is_empty(vim.bo[bufnr].filetype, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) then
						vim.fn.delete(file)
						store.set("pad_sources", vim.fs.normalize(file), nil)
					end
				end
			end
		end,
	})
end

---Show language-specific help for a pad (what <CR> does here, keys, tips)
---@param bufnr number|nil Pad buffer (defaults to the current buffer)
function M.show_help(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ft = vim.bo[bufnr].filetype
	local pad_file = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
	local config = get_config()
	local run = config.run or {}
	local item = pad_for_buffer(get_snacks().scratch.list(), bufnr)
	local name = item and item.name and get_scratch_filename(item.name)
	local info = {
		ft = ft,
		kind = pad_kind(ft),
		name = (name and name ~= "unsaved") and name or nil,
		source = vim.b[bufnr].scratch_manager_source or store.get("pad_sources", pad_file),
		keymaps = config.keymaps or {},
		help_key = (config.keymaps or {}).pad_help or "=h",
		border_hl = border_hl(pad_kind(ft)),
	}
	local lang = languages.get(ft)
	if lang.help_info then
		info = vim.tbl_extend("force", info, lang.help_info(bufnr, run[ft] or {}) or {})
	end
	require("scratch-manager.help").open(info)
end

---Current pad size step (1 = default, 2 = two thirds, 3 = nearly full); for tests
---@return number
---The =s list items (for tests)
---@param show_all boolean|nil
function M._pad_list(show_all)
	return pad_list(show_all)
end

function M._pad_size()
	return pad_size
end

---Send code to the current file's code pad: the given lines, else the function/method under the
---cursor, else the current line. Opens (or focuses) the code pad and puts the cursor on the code.
---@param range { first: number, last: number }|nil Lines to send (1-based, inclusive)
function M.send_to_pad(range)
	local send = require("scratch-manager.send")
	local src = vim.api.nvim_get_current_buf()
	if pad_for_buffer(get_snacks().scratch.list(), src) then
		vim.notify("Already in a scratch pad", vim.log.levels.INFO)
		return
	end
	if vim.api.nvim_buf_get_name(src) == "" then
		vim.notify("Save the file first: pads belong to a file", vim.log.levels.INFO)
		return
	end
	local target = send.target_range(src, range)
	local config = get_buffer_config(src)
	config.match_ft = true
	local block, imports = send.build(src, target, config.ft)

	-- Focus the code pad if it's already on screen, otherwise open it
	local existing = M.find_existing_scratch_pad(get_snacks().scratch.list(), config)
	local pad_win = existing and vim.fn.bufwinid(vim.fn.bufnr(existing.file)) or -1
	if pad_win ~= -1 then
		vim.api.nvim_set_current_win(pad_win)
		remember_source(src)
	else
		M.toggle_scratch_pad()
	end
	local pad = vim.api.nvim_get_current_buf()
	if pad == src then
		return
	end

	local lnum, added = send.insert(pad, block, imports, config.ft)
	pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
	autosave_pad(pad)

	local count = target.last - target.first + 1
	local extra = added > 0 and (" (+%d import line%s)"):format(added, added == 1 and "" or "s") or ""
	vim.notify(("Sent %d line%s to the code pad%s"):format(count, count == 1 and "" or "s", extra), vim.log.levels.INFO)
end

---Statusline component: the notes, code and/or db icon when the current buffer has those pads,
---otherwise ""
---
---Only reads a cached buffer variable, so it is cheap enough to call on every redraw.
---lualine: `lualine_x = { require("scratch-manager").status }`
---@return string
function M.status()
	local kinds = current_kinds()
	local parts = {}
	for _, kind in ipairs(KINDS) do
		if (kinds[kind] or 0) > 0 then
			table.insert(parts, kind_text(kind, kinds[kind]))
		end
	end
	return table.concat(parts, " ")
end

---Set up autocmds that keep the scratch pad indicator up to date
---@private
local function setup_indicator()
	local group = vim.api.nvim_create_augroup("ScratchManagerIndicator", { clear = true })
	local indicator = get_config().indicator or {}
	if indicator.enabled == false then
		badge.hide()
		return
	end
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			pcall(update_badge)
		end,
	})
	-- WinClosed: snacks closes a toggled pad inside nvim_win_call, so landing back in the
	-- source buffer fires no BufEnter.
	vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged", "TabEnter", "WinClosed" }, {
		group = group,
		callback = function(args)
			-- The badges' own windows closing (moved or hidden by an update) must not start another update
			if args.event == "WinClosed" and badge.is_own_win(tonumber(args.match) or -1) then
				return
			end
			-- Deferred: when a pad window closes, snacks writes the pad after these events (its
			-- autowrite runs without nested autocmds, so BufWritePost below doesn't see it either).
			-- pcall: never let a broken snacks install break buffer switching.
			vim.schedule(function()
				pcall(M.refresh_indicator)
			end)
		end,
	})
	-- Manual writes (:w) inside a pad
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = scratch_root() .. "/*",
		callback = function()
			vim.schedule(function()
				pcall(M.refresh_indicator)
			end)
		end,
	})
end

---Setup keymaps for scratch manager
---@private
local function setup_keymaps()
	if not M.config.enable_keymaps then
		return
	end

	local keymaps = M.config.keymaps

	-- Toggle scratch buffer (markdown) - create or open existing
	vim.keymap.set("n", keymaps.toggle, function()
		M.toggle_scratch_pad("markdown")
	end, { desc = "Toggle Scratch Buffer (Markdown)" })

	-- Toggle scratch buffer (language-aware)
	vim.keymap.set("n", keymaps.toggle_lang, function()
		M.toggle_scratch_pad()
	end, { desc = "Toggle Scratch Buffer (Language-aware)" })

	-- Toggle DB (SQL) scratch buffer
	if keymaps.toggle_db then
		vim.keymap.set("n", keymaps.toggle_db, function()
			M.toggle_scratch_pad("sql")
		end, { desc = "Toggle Scratch Buffer (DB / SQL)" })
	end

	-- Send code to the file's code pad
	if keymaps.send then
		vim.keymap.set({ "n", "x" }, keymaps.send, function()
			local range
			local mode = vim.fn.mode()
			if mode == "v" or mode == "V" or mode == "\22" then
				local first, last = vim.fn.line("v"), vim.fn.line(".")
				range = { first = math.min(first, last), last = math.max(first, last) }
				vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
			end
			M.send_to_pad(range)
		end, { desc = "Send to Code Pad" })
	end

	-- Select from existing scratch buffers
	vim.keymap.set("n", keymaps.select, function()
		custom_scratch_select()
	end, { desc = "Select Scratch Buffer" })

	-- Delete current scratch buffer
	vim.keymap.set("n", keymaps.delete, function()
		M.delete_current_scratch_pad()
	end, { desc = "Delete Scratch Buffer" })
end

---Select from existing scratch buffers (public API)
function M.select_scratch()
	custom_scratch_select()
end

---Setup function for scratch-manager.nvim
---@param opts ScratchManagerConfig|nil User configuration options
function M.setup(opts)
	-- Set nerd font availability if not already defined
	if vim.g.have_nerd_font == nil then
		-- Try to auto-detect, fallback to true for common setups
		vim.g.have_nerd_font = icons.detect_nerd_font()
	end

	-- Merge user config with defaults
	M.config = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Backward compatibility: border_color used to recolor the global SnacksInputBorder group.
	-- It now colors the scratch window border unless highlights.scratch_border is set explicitly.
	opts = opts or {}
	if opts.border_color and not (opts.highlights and opts.highlights.scratch_border) then
		M.config.highlights.scratch_border = { fg = opts.border_color, bold = true }
	end

	if not vim.g.have_nerd_font then
		if not (opts.indicator and opts.indicator.icon) then
			M.config.indicator.icon = "✎"
		end
		if not (opts.indicator and opts.indicator.code_icon) then
			M.config.indicator.code_icon = "<>"
		end
		if not (opts.indicator and opts.indicator.db_icon) then
			M.config.indicator.db_icon = "DB"
		end
	end

	-- Track the editor window used last: the current source behind any open pad
	if vim.api.nvim_win_get_config(0).relative == "" then
		last_editor_win = vim.api.nvim_get_current_win()
	end
	vim.api.nvim_create_autocmd("WinEnter", {
		group = vim.api.nvim_create_augroup("ScratchManagerContext", { clear = true }),
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if vim.api.nvim_win_get_config(win).relative == "" then
				last_editor_win = win
			end
		end,
	})

	setup_indicator()
	setup_autosave()
	setup_persistence()

	-- Create user command
	vim.api.nvim_create_user_command("ScratchPadDisplay", function()
		M.toggle_scratch_pad()
	end, { desc = "Toggle Scratch Buffer" })

	-- Setup keymaps if enabled
	setup_keymaps()

	-- Setup highlights following m_augment pattern
	define_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("ScratchManagerHighlights", { clear = true }),
		callback = function()
			define_highlights()
		end,
	})

	-- Legacy highlight for dashboard compatibility
	-- (the dashboard header color is set in define_highlights, so it survives colorscheme changes)
end

return M
