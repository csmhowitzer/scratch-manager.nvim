---Pad context for scratch-manager.nvim: the one place that decides which pads count
---
---Every feature that shows or acts on pads (badges, the room pads leave for them, the connector,
---`==` / `=c` / `=q`, badge clicks, the `=s` list, deleting) asks `resolve()` and acts through
---`switch()` / `close_windows()`, instead of working it out on its own. The rules are in the dev
---notes (PAD_RULES.md); in short:
---
---  source       the file in the editor window used last (not a pad, terminal, help, ...)
---  pad set      pads keyed together by snacks: file name + project directory + branch
---  current set  the source's set on the branch its project is on now. Its project is the source
---               file's git repository (`:pwd` for files outside git), so where Neovim was started
---               doesn't matter. Inside an own pad, the set is that pad's own recorded directory
---               and branch
---  own pad      a pad in the current set; any other pad is "visiting" (e.g. opened from `=s`)

local languages = require("scratch-manager.languages")
local store = require("scratch-manager.store")
local utils = require("scratch-manager.utils")

local M = {}

M.KINDS = { "notes", "code", "db" }

-- The editor (non-floating) window used last
local last_editor_win

---@return table|nil
local function snacks()
	local ok, mod = pcall(require, "snacks")
	return ok and mod or nil
end

---Directory where snacks keeps pads
---@return string
function M.root()
	local default = vim.fn.stdpath("data") .. "/scratch"
	local ok, config = pcall(function()
		return snacks().config.get("scratch", { root = default })
	end)
	return vim.fs.normalize(ok and type(config) == "table" and config.root or default)
end

---Pad kind of a filetype: "notes" (markdown), "db" (SQL), else "code"
---@param ft string|nil
---@return "notes"|"code"|"db"
function M.kind(ft)
	return languages.get(ft).kind or "code"
end

---Filetype for a kind: notes → markdown, db → sql, code → the source's language
---@param kind "notes"|"code"|"db"
---@param source_ft string|nil
---@return string
function M.ft_for(kind, source_ft)
	if kind == "notes" then
		return "markdown"
	elseif kind == "db" then
		return "sql"
	end
	return (source_ft and source_ft ~= "") and source_ft or "markdown"
end

---Every saved pad (snacks' list); empty when snacks isn't there
---@return table[]
function M.list()
	local ok, items = pcall(function()
		return snacks().scratch.list()
	end)
	return ok and type(items) == "table" and items or {}
end

---Is this buffer a pad (its file lives under the scratch root)?
---@param buf number
---@return boolean
function M.is_pad(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	local name = vim.api.nvim_buf_get_name(buf)
	return name ~= "" and vim.startswith(vim.fs.normalize(name), M.root() .. "/")
end

---Does this window show a file pads can belong to (an editor window with a real file, not a pad)?
---@param win number
---@return boolean
local function file_window(win)
	if not (win and vim.api.nvim_win_is_valid(win)) or vim.api.nvim_win_get_config(win).relative ~= "" then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" and not M.is_pad(buf)
end

---Remember the window as the one behind the pads (WinEnter/BufEnter). Only windows showing a file
---count: a sidebar, quickfix list or terminal getting focus doesn't take the source away
---@param win number
function M.track(win)
	if file_window(win) then
		last_editor_win = win
	end
end

---The editor window behind the pads: the last file window used in this tab, else the first file
---window, else the first editor window
---@return number|nil
function M.editor_window()
	if last_editor_win and file_window(last_editor_win)
		and vim.api.nvim_win_get_tabpage(last_editor_win) == vim.api.nvim_get_current_tabpage() then
		return last_editor_win
	end
	local first
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if file_window(win) then
			return win
		end
		if not first and vim.api.nvim_win_get_config(win).relative == "" then
			first = win
		end
	end
	return first
end

---The pad window on screen in this tab, if any
---@return number|nil win
---@return number|nil buf
function M.open_window()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_win_get_config(win).relative ~= "" and M.is_pad(buf) then
			return win, buf
		end
	end
	return nil, nil
end

---The snacks item for a pad buffer (a stand-in for a pad that isn't saved yet)
---@param items table[]
---@param buf number
---@return table|nil
function M.item_for(items, buf)
	local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
	for _, item in ipairs(items) do
		if item.file and vim.fs.normalize(item.file) == name then
			return item
		end
	end
	return nil
end

---Pad name snacks uses for a source file
---@param path string
---@return string
function M.pad_name(path)
	return "Scratch Pad (" .. vim.fn.fnamemodify(path, ":t") .. ")"
end

---The project a source file's pads belong to: its git repository root, else `:pwd`
---@param path string Source file
---@return string
function M.project_dir(path)
	local root = vim.fs.root(path, ".git")
	return vim.fs.normalize(root or (vim.uv or vim.loop).cwd())
end

---@param item table
---@param set { name: string, cwd: string, branch: string }
---@return boolean
local function in_set(item, set)
	return item.name == set.name
		and vim.fs.normalize(item.cwd or "") == set.cwd
		and (item.branch or "") == set.branch
end

---The file a pad was opened for (recorded when it was opened from that file)
---@param buf number
---@return string|nil
local function recorded_source(buf)
	local source = vim.b[buf].scratch_manager_source
		or store.get("pad_sources", vim.fs.normalize(vim.api.nvim_buf_get_name(buf)))
	return (source and source ~= "") and source or nil
end

---@class ScratchManagerContext
---@field source { buf: number, win: number, path: string, ft: string }|nil
---@field set { name: string, cwd: string, branch: string }|nil Current set key
---@field pads table<string, table[]> Current set's pads by kind
---@field kinds { notes: number, code: number, db: number } Current set's pad counts by kind
---@field open { win: number, buf: number, item: table|nil, kind: string, own: boolean }|nil

---Work out the whole pad context from scratch: source, current set, its pads, the open pad
---@return ScratchManagerContext
function M.resolve()
	local ctx = { pads = { notes = {}, code = {}, db = {} }, kinds = { notes = 0, code = 0, db = 0 } }
	local items = M.list()

	-- The source: the file in the editor window behind the pads
	local win = M.editor_window()
	if win then
		local buf = vim.api.nvim_win_get_buf(win)
		local path = vim.api.nvim_buf_get_name(buf)
		if path ~= "" and vim.bo[buf].buftype == "" and not M.is_pad(buf) then
			local ft = vim.bo[buf].filetype
			if ft == "" then
				ft = vim.filetype.match({ filename = path }) or ""
			end
			ctx.source = { buf = buf, win = win, path = path, ft = ft }
		end
	end

	-- The pad on screen
	local open_win, open_buf = M.open_window()
	local open_item = open_buf and M.item_for(items, open_buf) or nil

	-- The current set. Inside an own pad: that pad's recorded directory and branch. Own means: the
	-- same source file, and the branch its project is on now
	if ctx.source then
		local name = M.pad_name(ctx.source.path)
		local cwd = M.project_dir(ctx.source.path)
		ctx.set = { name = name, cwd = cwd, branch = utils.get_git_branch(cwd) }
		if open_item and open_item.name == name and open_item.cwd then
			local recorded = recorded_source(open_buf)
			local same_file = not recorded or vim.fs.normalize(recorded) == vim.fs.normalize(ctx.source.path)
			local pad_cwd = vim.fs.normalize(open_item.cwd)
			if same_file and (open_item.branch or "") == utils.get_git_branch(pad_cwd) then
				ctx.set = { name = name, cwd = pad_cwd, branch = open_item.branch or "" }
			end
		end
		for _, item in ipairs(items) do
			if in_set(item, ctx.set) then
				local kind = M.kind(item.ft)
				table.insert(ctx.pads[kind], item)
				ctx.kinds[kind] = ctx.kinds[kind] + 1
			end
		end
	end

	if open_win then
		local kind = M.kind(vim.bo[open_buf].filetype)
		local own
		if open_item then
			own = ctx.set ~= nil and in_set(open_item, ctx.set)
		else
			-- Not saved yet (not listed): own when it was opened for the source
			local recorded = recorded_source(open_buf)
			own = ctx.source ~= nil and recorded ~= nil and vim.fs.normalize(recorded) == vim.fs.normalize(ctx.source.path)
		end
		ctx.open = { win = open_win, buf = open_buf, item = open_item, kind = kind, own = own }
		-- An own pad counts even before its first save
		if own then
			ctx.kinds[kind] = math.max(ctx.kinds[kind], 1)
		end
	end
	return ctx
end

---The current set's pad of a kind; for code, the one in the requested language first
---@param ctx ScratchManagerContext
---@param kind string
---@param ft string|nil
---@return table|nil
function M.pad_of(ctx, kind, ft)
	local pads = ctx.pads[kind] or {}
	for _, item in ipairs(pads) do
		if not ft or item.ft == ft then
			return item
		end
	end
	return pads[1]
end

---A new pad in the current set: the file snacks would use (count|icon|name|cwd|branch.ft)
---@param ctx ScratchManagerContext
---@param ft string
---@return table item
function M.new_pad(ctx, ft)
	local key = table.concat({ "1", "", (ctx.set.name:gsub("|", " ")), ctx.set.cwd, ctx.set.branch }, "|")
	local encode = snacks() and snacks().util and snacks().util.file_encode
	local fname = encode and encode(key .. "." .. ft) or (key:gsub("[^%w%.%-_]", "_") .. "." .. ft)
	return { file = M.root() .. "/" .. fname, name = ctx.set.name, ft = ft, new = true }
end

---Close every window showing a buffer (pads are deleted, or replaced, only after this)
---@param buf number
function M.close_windows(buf)
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if vim.api.nvim_win_get_config(win).relative ~= "" then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
end

-- How pads are opened (set by scratch-manager.lua: window options, remembering the source, ...)
---@type fun(item: table, ctx: ScratchManagerContext)|nil
M.opener = nil

-- The context a switch is acting on, while it opens the pad: everything asked during the opening
-- (the pad's size and the room it keeps for badges) gets this same answer, not a second resolve
-- made after the previous pad closed
---@type ScratchManagerContext|nil
local acting

---The context to use right now: the one a switch is acting on, else a fresh one
---@return ScratchManagerContext
function M.current()
	return acting or M.resolve()
end

---`==` / `=c` / `=q` and badge clicks: act on the current set (rule 3)
---  in the source:       open that kind's pad, or create it
---  in an own pad:       the same kind closes it; another kind switches to it
---  in a visiting pad:   every kind closes it and opens/creates that kind in the current set
---@param kind "notes"|"code"|"db"
---@param ft string|nil Filetype for the pad (default: by kind; code → the source's language)
---@return "closed"|"opened"|"created"|"none"
function M.switch(kind, ft)
	local ctx = M.resolve()
	if ctx.open then
		local same = ctx.open.own and ctx.open.kind == kind
		vim.api.nvim_win_close(ctx.open.win, false)
		if same or not ctx.source then
			if ctx.source then
				vim.api.nvim_set_current_win(ctx.source.win)
			end
			return "closed"
		end
		-- The set stays the one worked out with the pad open (an own pad's recorded set)
	end
	if not ctx.source then
		return "none"
	end
	vim.api.nvim_set_current_win(ctx.source.win)
	ft = ft or M.ft_for(kind, ctx.source.ft)
	local item = M.pad_of(ctx, kind, kind == "code" and ft or nil)
	local created = item == nil
	item = item or M.new_pad(ctx, ft)
	if M.opener then
		acting = ctx
		local ok, err = pcall(M.opener, item, ctx)
		acting = nil
		if not ok then
			error(err, 0)
		end
	end
	return created and "created" or "opened"
end

-- Exposed for tests
M._reset = function()
	last_editor_win = nil
end

return M
