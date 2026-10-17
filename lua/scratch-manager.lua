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

---@class ScratchManagerSelectionConfig
---@field max_items number Maximum items to show in selection UI (default: 20)

---@class ScratchManagerUIConfig
---@field show_git_branch boolean Whether to show git branch column (default: true)
---@field show_path boolean Whether to show path column (default: true)
---@field show_icon boolean Whether to show icon column (default: true)
---@field filename_width number Fixed width for filename column (default: 25)
---@field branch_width number Fixed width for branch column (default: 15)
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
---@field run { cs: ScratchManagerRunConfig, sql: ScratchManagerSqlConfig } Runners for pads by filetype (Lua pads use snacks' own <CR>)
---@field indicator ScratchManagerIndicatorConfig Scratch pad indicator options

---@class ScratchManagerKeymaps
---@field toggle string Toggle scratch buffer (markdown)
---@field toggle_lang string Toggle scratch buffer (language-aware)
---@field toggle_db string Toggle DB (SQL) scratch buffer
---@field pad_help string|false Help for the current pad (inside pads only)
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
	},
	keymaps = {
		toggle = "==", -- Markdown scratch buffer toggle
		toggle_lang = "=c", -- Language-aware scratch buffer toggle
		toggle_db = "=q", -- DB (SQL) scratch buffer toggle
		pad_help = "=h", -- Help inside a pad (language-specific)
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
	run = {
		cs = {
			enabled = true,
			-- .NET 10+ file-based apps: no .sln/.csproj needed. PublishAot=false: file-based apps
			-- default to AOT, which disables reflection (e.g. JsonSerializer.Serialize throws)
			cmd = { "dotnet", "run", "-p:PublishAot=false" },
			max_height = 15,
			show_warnings = false, -- hide compiler/NuGet build warnings from the output
			project = true, -- reference the source file's nearest .csproj (#:project)
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
	if ft == nil or ft == "markdown" then
		return "notes"
	elseif ft == "sql" then
		return "db"
	end
	return "code"
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

---Snacks window keys for a pad filetype: wrap toggle everywhere, run keys for runnable filetypes
---@param ft string|nil
---@return table
local function pad_keys(ft)
	local run = get_config().run or {}
	local keys = {}
	if ft == "cs" and run.cs and run.cs.enabled ~= false then
		keys.run = runner.csharp_key(run.cs)
	elseif ft == "sql" and run.sql and run.sql.enabled ~= false and run.sql.provider ~= false then
		keys = sql.keys(run.sql)
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
local function get_window_options(width, height, ft)
	local config = get_config()
	width = width or config.width or math.min(math.floor(vim.o.columns / 3), 100)
	height = height or config.height or default_window_height()

	return {
		row = 1,
		col = vim.o.columns - width,
		width = width,
		height = height,
		wo = {
			winhighlight = "FloatBorder:" .. border_hl(pad_kind(ft)) .. ",FloatTitle:ScratchManagerTitle,",
			-- Set explicitly: otherwise the window inherits the global 'wrap' (often off)
			wrap = wraps(pad_kind(ft)),
			linebreak = wraps(pad_kind(ft)),
		},
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
local function custom_scratch_select()
	local buffers = get_snacks().scratch.list()

	if #buffers == 0 then
		vim.notify("No scratch buffers found", vim.log.levels.INFO)
		return
	end

	selection.create_custom_selection(buffers, { prompt = "Select Scratch Buffer" }, function(selected_item)
		if selected_item then
			-- Open the selected scratch buffer using our enhanced open_scratch function
			M.open_scratch(selected_item)
		end
	end, get_config())
end

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

	-- Floating badge icon - configurable
	vim.api.nvim_set_hl(0, "ScratchManagerBadge", hl.badge or { fg = "#74c7ec", bold = true })

	-- Pad help (=h): `default` links, so colorschemes or users can override them
	vim.api.nvim_set_hl(0, "ScratchManagerHelpTitle", { link = "ScratchManagerTitle", default = true })
	vim.api.nvim_set_hl(0, "ScratchManagerHelpHeading", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "ScratchManagerHelpRule", { link = "FloatBorder", default = true })
	vim.api.nvim_set_hl(0, "ScratchManagerHelpCode", { link = "String", default = true })
	vim.api.nvim_set_hl(0, "ScratchManagerHelpBold", { bold = true, default = true })

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
local function remove_pad(item)
	-- Wipe the buffer first so snacks' save-on-hide can't recreate the file afterwards
	local bufnr = vim.fn.bufnr(item.file)
	if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	end
	if vim.fn.filereadable(item.file) == 1 and vim.fn.delete(item.file) ~= 0 then
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

	-- Toggling from inside a pad closes it instead of creating a pad for the pad
	local own_pad = pad_for_buffer(buffers, bufnr)
	if own_pad then
		M.open_scratch(own_pad)
		return
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

---Pad counts per kind for the current buffer (cached by refresh_indicator)
---@return { notes: number, code: number, db: number }
local function current_kinds()
	local kinds = vim.b.scratch_manager_pad_kinds
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
	local right = vim.o.columns - 1 -- one cell of margin from the editor edge
	for _, kind in ipairs(KINDS) do
		local count = kinds[kind] or 0
		if count > 0 then
			local text = kind_text(kind, count)
			local col = right - (badge.width(text) + 2) -- + 2 border cells
			badge.show(kind, text, col, border_hl(kind), function()
				M.open_pad_from_badge(kind)
			end, { transparent = indicator.transparent })
			right = col - 1 -- one cell gap between badges
		else
			badge.hide(kind)
		end
	end
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
	vim.api.nvim_set_current_win(target)

	local indicator = get_config().indicator or {}
	if indicator.animate then
		local pads = current_pads(kind)
		if #pads == 1 then
			local grow_kind = kind or pad_kind(pads[1].ft)
			local source = vim.api.nvim_get_current_buf()
			badge.grow(grow_kind, get_window_options(), border_hl(pad_kind(pads[1].ft)), function()
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
	end
end

---Make a DB pad connection-aware once (completion from the SQL provider, if it supports it)
---@param bufnr number
---@private
local function attach_db_pad(bufnr)
	if vim.b[bufnr].scratch_manager_db_attached then
		return
	end
	vim.b[bufnr].scratch_manager_db_attached = true
	local run = get_config().run or {}
	pcall(sql.attach_pad, bufnr, run.sql)
end

---Set up pad buffer hooks: autosave (write after every change, so leaving, closing or quitting
---never asks to save a pad) and DB pad attach (completion)
---@private
local function setup_autosave()
	local group = vim.api.nvim_create_augroup("ScratchManagerAutosave", { clear = true })
	-- snacks sets the pad's filetype after BufEnter, so also catch DB pads on FileType
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "sql",
		callback = function(args)
			if vim.startswith(vim.fs.normalize(vim.api.nvim_buf_get_name(args.buf)), scratch_root() .. "/") then
				attach_db_pad(args.buf)
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
			if vim.bo[args.buf].filetype == "sql" then
				attach_db_pad(args.buf)
			end
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
	if ft == "cs" and (run.cs or {}).project ~= false then
		info.project = runner.find_project(bufnr)
	elseif ft == "sql" then
		info.connection = sql.get_connection_name(vim.api.nvim_buf_get_name(bufnr))
		local provider = sql.get_provider(run.sql)
		info.provider = provider and provider.name or nil
	end
	require("scratch-manager.help").open(info)
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
		callback = function()
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

	setup_indicator()
	setup_autosave()

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
	vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = M.config.dashboard_color })
end

return M
