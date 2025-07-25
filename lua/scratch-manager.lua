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

---@class ScratchManagerUIConfig
---@field show_git_branch boolean Whether to show git branch column (default: true)
---@field filename_width number Fixed width for filename column (default: 25)
---@field branch_width number Fixed width for branch column (default: 15)
---@field icon_width number Fixed width for icon column (default: 3)

---@class ScratchManagerConfig
---@field width number|nil Window width (defaults to 1/3 of screen, max 100)
---@field height number|nil Window height (defaults to screen height - 3)
---@field border_color string Border highlight color
---@field dashboard_color string Dashboard highlight color
---@field default_filetype string Default filetype for new scratch buffers
---@field border_highlight string Highlight group for borders
---@field keymaps ScratchManagerKeymaps Keymap configuration
---@field ui ScratchManagerUIConfig UI configuration options
---@field enable_keymaps boolean Whether to set up default keymaps

---@class ScratchManagerKeymaps
---@field toggle string Toggle scratch buffer (markdown)
---@field toggle_lang string Toggle scratch buffer (language-aware)
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
  border_highlight = "SnacksInputBorder",
  keymaps = {
    toggle = "==",        -- Markdown scratch buffer toggle
    toggle_lang = "=c",   -- Language-aware scratch buffer toggle
    select = "=s",        -- Select from existing scratch buffers
    delete = "=d",        -- Delete current scratch buffer
  },
  ui = {
    show_git_branch = true,
    filename_width = 25,
    branch_width = 15,
    icon_width = 3,
  },
  enable_keymaps = true,
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
	if not name then return "" end
	local match = name:match("Scratch Pad %((.+)%)")
	return match or name
end

---Get window options for scratch buffer positioning
---@param width number|nil Window width
---@param height number|nil Window height
---@return table Window configuration for snacks.nvim
---@private
local function get_window_options(width, height)
	-- Calculate defaults if width/height are nil
	if not width then
		width = M.config.width or math.min(math.floor(vim.o.columns / 3), 100)
	end
	if not height then
		height = M.config.height or (vim.o.lines - 3)
	end

	return {
		row = 1,
		col = vim.o.columns - width,
		width = width,
		height = height - 3, -- Additional -3 for window chrome
		wo = { winhighlight = "FloatBorder:ScratchManagerBorder,FloatTitle:ScratchManagerTitle," },
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
---@param bufnr number Buffer number
---@return ScratchPadConfig Configuration for scratch buffer
---@private
local function get_buffer_config(bufnr)
	local slice_width = math.floor(vim.o.columns / 3)
	local max_width = M.config.width or 100
	local calculated_width = slice_width < max_width and slice_width or max_width

	local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h")
	local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
	local ft = vim.filetype.match({ filename = name }) or M.config.default_filetype
	local icon = get_snacks().util.icon(ft, "filetype")

	path = path and vim.fn.fnamemodify(path, ":p:~")

	return {
		width = M.config.width or calculated_width,
		height = M.config.height or (vim.api.nvim_win_get_height(0) - 3),
		path = path,
		name = name,
		fmtName = format_buffer_name(name),
		ft = ft,
		icon = icon,
		file = nil,
	}
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
  -- Window titles - matches m_augment footer color
  vim.api.nvim_set_hl(0, "ScratchManagerTitle", {
    fg = "#74c7ec", -- Same as m_augment AugmentChatFooter
    bold = true
  })

  -- Scratch Buffer Border - preserve existing default
  vim.api.nvim_set_hl(0, "ScratchManagerBorder", {
    fg = "#F7DC6F", -- Current scratch buffer border color
    bold = true
  })

  -- Select list Border - distinct blue color
  vim.api.nvim_set_hl(0, "ScratchManagerSelectBorder", {
    fg = "#89b4fa", -- Blue for selection list border
    bold = true
  })

  -- Select list Header - green color
  vim.api.nvim_set_hl(0, "ScratchManagerSelectHeader", {
    fg = "#a6d189", -- Green for selection list header
    bold = true
  })

  -- Selection highlight for active item
  vim.api.nvim_set_hl(0, "ScratchManagerSelected", {
    bg = "#45475a", -- Subtle background highlight
    bold = true
  })
end

-- Public API functions

---Open a new scratch buffer
---@param config ScratchPadConfig Buffer configuration
function M.open_new_scratch_pad(config)
	get_snacks().scratch({
		ft = config.ft,
		name = config.fmtName,
		win = get_window_options(config.width, config.height),
	})
	local config = get_config()
	vim.api.nvim_set_hl(0, config.border_highlight, { fg = config.border_color })
end

---Open an existing scratch buffer
---@param config ScratchPadConfig Buffer configuration with file information
function M.open_scratch(config)
	-- Handle both our config objects and snacks.nvim buffer items
	-- Let get_window_options handle the auto-calculation
	local width = config.width or M.config.width
	local height = config.height or M.config.height

	get_snacks().scratch.open({
		icon = config.icon,
		file = config.file,
		name = config.fmtName or config.name, -- snacks items use 'name', our config uses 'fmtName'
		ft = config.ft,
		win = get_window_options(width, height),
	})

	local config = get_config()
	vim.api.nvim_set_hl(0, config.border_highlight, { fg = config.border_color })
end

---Find existing scratch buffer matching current context
---@param buffers table List of existing scratch buffers from snacks.nvim
---@param config ScratchPadConfig Current buffer configuration
---@return table|nil Existing scratch buffer info or nil if not found
function M.find_existing_scratch_pad(buffers, config)
	assert(config.path, "no path provided")
	assert(config.name, "no filename provided")

	for _, item in ipairs(buffers) do
		local wd = item.cwd and vim.fn.fnamemodify(item.cwd, ":p:~") or ""
		local fileName = get_scratch_filename(item.name)

		if fileName == config.name and wd == config.path then
			return {
				name = item.name,
				icon = item.icon or get_snacks().util.icon(item.ft, "filetype"),
				file = item.file,
				ft = item.ft,
			}
		end
	end
	return nil
end

---Delete the current scratch buffer file
function M.delete_current_scratch_pad()
	local buffers = get_snacks().scratch.list()
	local config = get_buffer_config(vim.api.nvim_get_current_buf())

	for _, item in ipairs(buffers) do
		local wd = item.cwd and vim.fn.fnamemodify(item.cwd, ":p:~") or ""
		local fileName = get_scratch_filename(item.name)

		if fileName == config.name and wd == config.path and item.file and vim.fn.filereadable(item.file) == 1 then
			vim.fn.delete(item.file)
			break
		end
	end
end

---Toggle scratch buffer with optional filetype
---@param file_type string|nil Optional filetype to use for new scratch buffer
function M.toggle_scratch_pad(file_type)
	local buffers = get_snacks().scratch.list()
	local config = get_buffer_config(vim.api.nvim_get_current_buf())

	local existing_pad = #buffers > 0 and M.find_existing_scratch_pad(buffers, config)
	if existing_pad then
		if file_type then
			existing_pad.ft = file_type
			existing_pad.icon = get_snacks().util.icon(file_type, "filetype")
		end
		config.fmtName = existing_pad.name
		config.ft = existing_pad.ft
		config.file = existing_pad.file
		config.icon = existing_pad.icon
		M.open_scratch(config)
	else
		if file_type then
			config.ft = file_type
		end
		M.open_new_scratch_pad(config)
	end
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
---Auto-detect Nerd Font support by testing character rendering
---@return boolean has_nerd_font True if Nerd Font appears to be supported
local function detect_nerd_font()
	-- Test if Nerd Font characters render as single-width
	local test_chars = { "", "", "" } -- lua, folder, file icons
	for _, char in ipairs(test_chars) do
		if vim.fn.strdisplaywidth(char) == 1 then
			return true
		end
	end
	return false
end

function M.setup(opts)
	-- Set nerd font availability if not already defined
	if vim.g.have_nerd_font == nil then
		-- Try to auto-detect, fallback to true for common setups
		vim.g.have_nerd_font = icons.detect_nerd_font()
	end

	-- Merge user config with defaults
	M.config = vim.tbl_deep_extend("force", default_config, opts or {})

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
