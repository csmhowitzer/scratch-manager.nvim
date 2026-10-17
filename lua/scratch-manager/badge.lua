---Floating scratch pad badges for scratch-manager.nvim
---Small bordered windows in the top-right corner, one per pad kind ("notes" for markdown
---pads, "code" for language pads, "db" for SQL pads), that open their pad when clicked

local M = {}

---@alias ScratchManagerBadgeKind "notes"|"code"|"db"

---@type table<string, { buf: number|nil, win: number|nil }>
local badges = {}

local state = {
	animating = false,
}

local ns = vim.api.nvim_create_namespace("scratch-manager-badge")

local GROW_FRAMES = 10
local GROW_INTERVAL_MS = 15

---Rows taken by the tabline (bufferline etc.), so badges sit just below it
---@return number
function M.tabline_height()
	local stal = vim.o.showtabline
	if stal == 2 or (stal == 1 and #vim.api.nvim_list_tabpages() > 1) then
		return 1
	end
	return 0
end

---Get a badge window id if it is shown
---@param kind ScratchManagerBadgeKind|nil Badge kind; nil returns the first shown ("notes", "code", "db")
---@return number|nil
function M.get_win(kind)
	if kind == nil then
		return M.get_win("notes") or M.get_win("code") or M.get_win("db")
	end
	local badge = badges[kind]
	if badge and badge.win and vim.api.nvim_win_is_valid(badge.win) then
		return badge.win
	end
	return nil
end

---Is the given (or current) window one of the badge windows?
---@param win number|nil Window id (defaults to the current window)
---@return boolean
function M.is_badge_win(win)
	win = win or vim.api.nvim_get_current_win()
	for _, badge in pairs(badges) do
		if badge.win == win then
			return true
		end
	end
	return false
end

---Close a badge window (its buffer is kept for reuse)
---@param kind ScratchManagerBadgeKind|nil Badge kind; nil hides all badges
function M.hide(kind)
	if kind == nil then
		for k in pairs(badges) do
			M.hide(k)
		end
		return
	end
	local badge = badges[kind]
	if badge and badge.win and vim.api.nvim_win_is_valid(badge.win) then
		pcall(vim.api.nvim_win_close, badge.win, true)
	end
	if badge then
		badge.win = nil
	end
end

---Create a badge buffer once, with click/<CR> mappings
---@param kind ScratchManagerBadgeKind
---@param on_click function Called when the badge is clicked or <CR> is pressed in it
---@return number buf
local function ensure_buf(kind, on_click)
	badges[kind] = badges[kind] or {}
	local badge = badges[kind]
	if badge.buf and vim.api.nvim_buf_is_valid(badge.buf) then
		return badge.buf
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].filetype = "scratch_manager_badge"

	local opts = { buffer = buf, nowait = true, silent = true, desc = "Open " .. kind .. " scratch pad" }
	-- <LeftMouse> focuses the badge, so the release is handled with the badge buffer current
	vim.keymap.set("n", "<LeftRelease>", on_click, opts)
	vim.keymap.set("n", "<CR>", on_click, opts)
	vim.keymap.set("n", "q", function()
		vim.cmd("wincmd p")
	end, { buffer = buf, nowait = true, silent = true, desc = "Leave scratch pad badge" })

	badge.buf = buf
	return buf
end

---Width a badge needs for the given text, including padding (excluding borders)
---@param text string
---@return number
function M.width(text)
	return vim.api.nvim_strwidth(text) + 2
end

---Show (or update) a badge
---@param kind ScratchManagerBadgeKind
---@param text string Text to show (icon, optionally with a count)
---@param col number Editor column of the badge's left border
---@param border_hl string Highlight group for the border
---@param on_click function Called when the badge is clicked
---@param opts? { transparent?: boolean } transparent (default): editor background like the pads;
---  false: the regular floating-window background
function M.show(kind, text, col, border_hl, on_click, opts)
	opts = opts or {}
	local buf = ensure_buf(kind, on_click)
	local badge = badges[kind]
	local line = " " .. text .. " " -- one cell of padding on each side

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
	vim.bo[buf].modifiable = false
	-- The icon gets its color from an extmark, so the window background can follow the pads
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #line, hl_group = "ScratchManagerBadge" })

	local win_config = {
		relative = "editor",
		row = M.tabline_height(),
		col = math.max(0, col),
		width = M.width(text),
		height = 1,
		style = "minimal",
		border = "rounded",
		focusable = true, -- needed for mouse clicks
		zindex = 45, -- above normal floats, below notifications
	}

	-- Floats belong to a tabpage, so reopen the badge after switching tabs
	if badge.win and vim.api.nvim_win_is_valid(badge.win)
		and vim.api.nvim_win_get_tabpage(badge.win) ~= vim.api.nvim_get_current_tabpage() then
		M.hide(kind)
	end

	if badge.win and vim.api.nvim_win_is_valid(badge.win) then
		vim.api.nvim_win_set_config(badge.win, win_config)
	else
		win_config.noautocmd = true
		badge.win = vim.api.nvim_open_win(buf, false, win_config)
		-- A global 'sidescrolloff' (LazyVim: 8) would scroll this tiny window sideways once the
		-- cursor has moved onto the icon (e.g. after a click), pushing the icon off center
		vim.wo[badge.win].sidescrolloff = 0
		vim.wo[badge.win].scrolloff = 0
		vim.wo[badge.win].wrap = false
	end
	-- Same as the pad windows (NormalFloat:Normal), or the regular float background
	local background = opts.transparent == false and "NormalFloat:NormalFloat" or "NormalFloat:Normal"
	vim.wo[badge.win].winhighlight = background .. ",FloatBorder:" .. border_hl
	vim.api.nvim_win_call(badge.win, function()
		vim.fn.winrestview({ lnum = 1, col = 0, topline = 1, leftcol = 0 })
	end)
end

---Is the grow animation running?
---@return boolean
function M.is_animating()
	return state.animating
end

---Animate an empty bordered box growing from a badge to the target geometry, then call
---on_done. Calls on_done immediately when that badge is not shown.
---@param kind ScratchManagerBadgeKind Badge to grow from
---@param target table Float geometry { row, col, width, height } of the window about to open
---@param border_hl string Highlight group for the growing box's border
---@param on_done function Called after the animation (opens the real window)
function M.grow(kind, target, border_hl, on_done)
	local from_win = M.get_win(kind)
	if not from_win then
		on_done()
		return
	end
	local from = vim.api.nvim_win_get_config(from_win)
	local function num(v)
		return type(v) == "table" and v[false] or v -- older nvim returned { [false] = n }
	end
	local start = { row = num(from.row), col = num(from.col), width = from.width, height = from.height }

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = start.row,
		col = start.col,
		width = start.width,
		height = start.height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 50,
		noautocmd = true,
	})
	vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:" .. border_hl
	state.animating = true
	M.hide()

	local frame = 0
	local timer = (vim.uv or vim.loop).new_timer()
	local function finish()
		timer:stop()
		timer:close()
		state.animating = false
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		on_done()
	end
	timer:start(0, GROW_INTERVAL_MS, vim.schedule_wrap(function()
		if timer:is_closing() then
			return
		end
		frame = frame + 1
		local t = frame / GROW_FRAMES
		local e = 1 - (1 - t) ^ 3 -- ease-out cubic
		local function lerp(a, b)
			return math.floor(a + (b - a) * e + 0.5)
		end
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_set_config, win, {
				relative = "editor",
				row = lerp(start.row, target.row),
				col = lerp(start.col, target.col),
				width = math.max(1, lerp(start.width, target.width)),
				height = math.max(1, lerp(start.height, target.height)),
			})
		end
		if frame >= GROW_FRAMES then
			finish()
		end
	end))
end

-- Expose internal state for testing
M._badges = badges

return M
