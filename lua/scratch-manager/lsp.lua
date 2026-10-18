---Language servers in pads, through clean mirror files
---
---Pad files have encoded names (snacks keys them by name, cwd, branch and filetype), which language
---servers mis-decode; Roslyn crashes on them. For languages whose profile declares
---`lsp = { servers = { ... } }`, a pad is shown to servers under a clean mirror path instead:
---vim.uri_from_bufnr / vim.uri_to_bufnr map the pad buffer to that path and back, so requests,
---edits and replies (diagnostics, completion edits) all line up with the pad. The mirror file on
---disk is kept in sync with the pad for servers that read files. Other servers stay off pads (see
---the `lsp` option and the attach guard in scratch-manager.lua).

local languages = require("scratch-manager.languages")

local M = {}

-- Shared across plugin reloads: the URI functions are wrapped once per Neovim session
local function registry()
	local reg = rawget(_G, "__scratch_manager_lsp_mirror")
	if not reg then
		reg = { pads = {}, by_path = {} }
		rawset(_G, "__scratch_manager_lsp_mirror", reg)
	end
	return reg
end

---Install the URI mapping (once per session)
function M.install()
	local reg = registry()
	if reg.original_from then
		return
	end
	reg.original_from, reg.original_to = vim.uri_from_bufnr, vim.uri_to_bufnr
	vim.uri_from_bufnr = function(bufnr)
		bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
		local mirror = reg.pads[bufnr]
		if mirror then
			return vim.uri_from_fname(mirror)
		end
		return reg.original_from(bufnr)
	end
	vim.uri_to_bufnr = function(uri)
		local ok, fname = pcall(vim.uri_to_fname, uri)
		local bufnr = ok and reg.by_path[fname]
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			return bufnr
		end
		return reg.original_to(uri)
	end
end

---Mirror path for a pad: <cache>/scratch-manager/lsp/<hash>/<Name>Pad.<ext>
---@param pad_file string
---@param name string|nil Pad name, e.g. "StringExtensions.cs"
---@param ext string
---@return string
function M.mirror_path(pad_file, name, ext)
	local key = vim.fn.sha256(pad_file):sub(1, 16)
	local base = name and vim.fn.fnamemodify(name, ":t:r"):gsub("[^%w_]", "") or ""
	base = (base ~= "" and base or "Scratch") .. "Pad." .. ext
	return vim.fn.stdpath("cache") .. "/scratch-manager/lsp/" .. key .. "/" .. base
end

---Write the pad's current text to its mirror file
---@param bufnr number
function M.sync(bufnr)
	local mirror = registry().pads[bufnr]
	if mirror and vim.api.nvim_buf_is_valid(bufnr) then
		vim.fn.writefile(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), mirror)
	end
end

---Start mirroring a pad (before servers attach). No-op for languages without lsp servers.
---@param bufnr number
---@param name string|nil Pad name (for a readable mirror file name)
---@return boolean mirrored
function M.enable(bufnr, name)
	local lang = languages.get(vim.bo[bufnr].filetype)
	if not (lang.lsp and lang.lsp.servers and #lang.lsp.servers > 0) then
		return false
	end
	local reg = registry()
	if reg.pads[bufnr] then
		return true
	end
	M.install()
	local mirror = M.mirror_path(vim.api.nvim_buf_get_name(bufnr), name, lang.lsp.ext or vim.bo[bufnr].filetype)
	pcall(vim.fn.mkdir, vim.fs.dirname(mirror), "p")
	reg.pads[bufnr] = mirror
	reg.by_path[mirror] = bufnr
	M.sync(bufnr)
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		buffer = bufnr,
		once = true,
		callback = function()
			M.disable(bufnr)
		end,
	})
	return true
end

---Stop mirroring a pad
---@param bufnr number
function M.disable(bufnr)
	local reg = registry()
	local mirror = reg.pads[bufnr]
	if mirror then
		reg.pads[bufnr] = nil
		reg.by_path[mirror] = nil
	end
end

---Is this pad mirrored?
---@param bufnr number
---@return string|nil mirror path
function M.mirror(bufnr)
	return registry().pads[bufnr]
end

---May this server attach to this (mirrored) pad?
---@param bufnr number
---@param client_name string
---@return boolean
function M.allows(bufnr, client_name)
	if not registry().pads[bufnr] then
		return false
	end
	local lang = languages.get(vim.bo[bufnr].filetype)
	return vim.tbl_contains(lang.lsp and lang.lsp.servers or {}, client_name)
end

---Drop diagnostics a profile says are expected in pads (C#: .Dump(), which only exists at run time)
---@param uri string
---@param diagnostics table[] LSP diagnostics
---@return table[]
function M.filter_diagnostics(uri, diagnostics)
	local ok, fname = pcall(vim.uri_to_fname, uri)
	local bufnr = ok and registry().by_path[fname]
	if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
		return diagnostics
	end
	local lang = languages.get(vim.bo[bufnr].filetype)
	local ignore = lang.lsp and lang.lsp.ignore_diagnostic
	if not ignore then
		return diagnostics
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	-- The source text a diagnostic points at (single-line ranges; LSP columns are UTF-16)
	local function flagged(d)
		local s, e = d.range and d.range.start, d.range and d.range["end"]
		local line = s and lines[s.line + 1]
		if not line or e.line ~= s.line then
			return ""
		end
		local ok1, from = pcall(vim.str_byteindex, line, s.character, true)
		local ok2, to = pcall(vim.str_byteindex, line, e.character, true)
		return (ok1 and ok2) and line:sub(from + 1, to) or ""
	end
	return vim.tbl_filter(function(d)
		return not ignore(d, flagged(d))
	end, diagnostics)
end

---Pad buffer for a mirror URI, if it is one
---@param uri string|nil
---@return number|nil
local function pad_for_uri(uri)
	if not uri then
		return nil
	end
	local ok, fname = pcall(vim.uri_to_fname, uri)
	local bufnr = ok and registry().by_path[fname]
	return bufnr and vim.api.nvim_buf_is_valid(bufnr) and bufnr or nil
end

---Put LSP diagnostics on a pad. Neovim's own handler resolves the URI with bufadd(path), which
---would put them on a hidden buffer named after the mirror file, so mirrored pads are handled here
---(same namespace Neovim uses, so they display and clear as usual).
---@param client_id number
---@param bufnr number
---@param items table[] LSP diagnostics
---@param is_pull boolean
local function set_pad_diagnostics(client_id, bufnr, items, is_pull)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local function col(line, character)
		local text = lines[line + 1]
		if not text then
			return character
		end
		local ok, byte = pcall(vim.str_byteindex, text, character, true) -- LSP columns are UTF-16
		return ok and byte or character
	end
	local out = {}
	for _, d in ipairs(items) do
		local s, e = d.range.start, d.range["end"]
		table.insert(out, {
			lnum = s.line,
			col = col(s.line, s.character),
			end_lnum = e.line,
			end_col = col(e.line, e.character),
			severity = d.severity or vim.diagnostic.severity.ERROR,
			message = d.message,
			source = d.source,
			code = d.code,
			user_data = { lsp = d },
		})
	end
	vim.diagnostic.set(vim.lsp.diagnostic.get_namespace(client_id, is_pull), bufnr, out)
end

---Route a client's diagnostics for mirrored pads to the pad (push and pull), dropping the ones the
---profile expects; other buffers go through the normal handlers. Once per client.
---@param client vim.lsp.Client
function M.watch_client(client)
	if client._scratch_manager_filtered then
		return
	end
	client._scratch_manager_filtered = true
	local function wrap(method, is_pull)
		local handler = client.handlers[method] or vim.lsp.handlers[method]
		client.handlers[method] = function(err, result, ctx, config)
			local uri = result and (is_pull and ctx and ctx.params and ctx.params.textDocument and ctx.params.textDocument.uri
				or result.uri)
			local bufnr = pad_for_uri(uri)
			if bufnr then
				if not err and result and (not is_pull or result.kind ~= "unchanged") then
					local items = is_pull and (result.items or {}) or (result.diagnostics or {})
					set_pad_diagnostics(ctx.client_id or client.id, bufnr, M.filter_diagnostics(uri, items), is_pull)
				end
				return
			end
			if handler then
				return handler(err, result, ctx, config)
			end
		end
	end
	wrap("textDocument/publishDiagnostics", false)
	wrap("textDocument/diagnostic", true)
end

-- Seconds after a server attaches to re-ask for a pad's diagnostics
M.refresh_delays = { 5, 15, 30, 60, 120, 240 }

---Re-ask a server for a pad's diagnostics a few times after it attaches. A pad is a single-file
---project the server loads on its own, after the solution (Roslyn: a cold load with a restore can
---take minutes); its first diagnostics come from before that and would stay until the next edit
---(e.g. a `using` from a project reference flagged CS0234). Servers only refresh at solution load.
---@param bufnr number
---@param client_id number
function M.refresh_diagnostics(bufnr, client_id)
	for _, seconds in ipairs(M.refresh_delays) do
		vim.defer_fn(function()
			if vim.api.nvim_buf_is_valid(bufnr) and registry().pads[bufnr] and vim.lsp.buf_is_attached(bufnr, client_id) then
				pcall(vim.lsp.util._refresh, "textDocument/diagnostic", { bufnr = bufnr, client_id = client_id })
			end
		end, seconds * 1000)
	end
end

-- Expose state for testing
M._registry = registry

return M
