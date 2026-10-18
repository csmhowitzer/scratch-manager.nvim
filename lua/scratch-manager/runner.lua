---Run scratch pads: a language-neutral runner driven by the `run` spec of a language profile
---(see scratch-manager.languages). The profile turns the pad into a file and names the command;
---this module handles selections, the per-pad work directory, the output window, hiding noise,
---and inline values (`\x1e<line>\x1f<text>` markers printed by the program, e.g. C#'s .Dump()).

local languages = require("scratch-manager.languages")

local M = {}

---Per-language run settings (`run.<ft>` in the config); profiles may read extra fields
---@class ScratchManagerRunConfig
---@field enabled boolean Bind <CR> in the pad to run it (default: true)
---@field cmd string[]|nil Command to run; the work file path is appended (profile default otherwise)
---@field max_height number Maximum height of the output window (default: 15)
---@field show_warnings boolean Show lines the profile considers noise, e.g. build warnings (default: false)
---@field inline boolean Show inline values (`.Dump()`) next to their lines (default: true)
---@field project boolean C#: reference the source file's nearest .csproj via #:project (default: true)

local output = {
	buf = nil,
	win = nil,
}

local dump_ns = vim.api.nvim_create_namespace("scratch-manager-dump")
local dump_values = {} -- pad bufnr -> { [pad line] = { full values } }
local detail = { buf = nil, win = nil }

---Clear inline `.Dump()` values from a pad
---@param bufnr number
function M.clear_inline(bufnr)
	dump_values[bufnr] = nil
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_clear_namespace(bufnr, dump_ns, 0, -1)
	end
end

---Indent compact JSON for reading (other text is returned as-is)
---@param text string
---@return string[]
function M.pretty(text)
	local label, body = text:match("^([^\"{%[]-: )([{%[].*)$")
	body = body or text
	if not body:match("^[{%[]") then
		return { text }
	end
	local out, line, depth, in_string, escaped = {}, label or "", 0, false, false
	local function newline()
		table.insert(out, line)
		line = string.rep("  ", depth)
	end
	for i = 1, #body do
		local c = body:sub(i, i)
		if in_string then
			line = line .. c
			if escaped then
				escaped = false
			elseif c == "\\" then
				escaped = true
			elseif c == '"' then
				in_string = false
			end
		elseif c == '"' then
			in_string = true
			line = line .. c
		elseif c == "{" or c == "[" then
			local close = c == "{" and "}" or "]"
			if body:sub(i + 1, i + 1) == close then
				line = line .. c -- empty {} / []
			else
				line = line .. c
				depth = depth + 1
				newline()
			end
		elseif c == "}" or c == "]" then
			if body:sub(i - 1, i - 1) == (c == "}" and "{" or "[") then
				line = line .. c
			else
				depth = depth - 1
				newline()
				line = line .. c
			end
		elseif c == "," then
			line = line .. c
			newline()
		elseif c == ":" then
			line = line .. ": "
		else
			line = line .. c
		end
	end
	table.insert(out, line)
	return out
end

---Show the full `.Dump()` values of the cursor line in a popup (falls back to normal `K`)
---@param bufnr number Pad buffer
function M.show_dump_detail(bufnr)
	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	local values = dump_values[bufnr] and dump_values[bufnr][lnum]
	if not values then
		if #vim.lsp.get_clients({ bufnr = bufnr }) > 0 then
			vim.lsp.buf.hover()
		else
			vim.cmd("normal! K")
		end
		return
	end
	local lines = {}
	for n, value in ipairs(values) do
		if #values > 1 then
			table.insert(lines, ("── %d of %d ──"):format(n, #values))
		end
		vim.list_extend(lines, M.pretty(value))
	end
	if not (detail.buf and vim.api.nvim_buf_is_valid(detail.buf)) then
		detail.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[detail.buf].bufhidden = "hide"
		vim.bo[detail.buf].filetype = "json"
		local opts = { buffer = detail.buf, nowait = true, silent = true, desc = "Close" }
		vim.keymap.set("n", "q", function() pcall(vim.api.nvim_win_close, detail.win, true) end, opts)
		vim.keymap.set("n", "<Esc>", function() pcall(vim.api.nvim_win_close, detail.win, true) end, opts)
	end
	vim.bo[detail.buf].modifiable = true
	vim.api.nvim_buf_set_lines(detail.buf, 0, -1, false, lines)
	vim.bo[detail.buf].modifiable = false
	local width = 20
	for _, l in ipairs(lines) do
		width = math.max(width, vim.api.nvim_strwidth(l))
	end
	width = math.min(width + 2, vim.o.columns - 8)
	local height = math.min(#lines, math.floor(vim.o.lines * 0.6))
	if detail.win and vim.api.nvim_win_is_valid(detail.win) then
		vim.api.nvim_win_close(detail.win, true)
	end
	detail.win = vim.api.nvim_open_win(detail.buf, true, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = (" line %d "):format(lnum),
		title_pos = "center",
		footer = " q close ",
		footer_pos = "center",
		zindex = 65,
	})
	vim.wo[detail.win].winhighlight = "NormalFloat:Normal,FloatBorder:ScratchManagerCodeBorder,FloatTitle:ScratchManagerTitle"
end

---Map `K` on a pad to the value popup (buffer-local). Language servers attaching to the pad (e.g.
---LazyVim's hover mapping) take `K` over; the popup falls back to hover on lines without values.
---@param bufnr number Pad buffer
function M.map_value_key(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.keymap.set("n", "K", function()
			M.show_dump_detail(bufnr)
		end, { buffer = bufnr, silent = true, desc = "Value (or hover)" })
	end
end

---Show `.Dump()` values at the end of the pad lines that produced them
---@param bufnr number Pad buffer
---@param dumps table<number, string[]> Pad line -> values (in order)
function M.show_inline(bufnr, dumps)
	M.clear_inline(bufnr)
	dump_values[bufnr] = dumps
	M.map_value_key(bufnr)
	local count = vim.api.nvim_buf_line_count(bufnr)
	for lnum, values in pairs(dumps) do
		if lnum >= 1 and lnum <= count then
			local text = table.concat(values, " │ ")
			if #values > 1 then
				text = ("(%d×) %s"):format(#values, text)
			end
			if vim.fn.strchars(text) > 200 then
				text = vim.fn.strcharpart(text, 0, 199) .. "…"
			end
			vim.api.nvim_buf_set_extmark(bufnr, dump_ns, lnum - 1, 0, {
				virt_text = { { "  → " .. text, "ScratchManagerDump" } },
				virt_text_pos = "eol",
			})
		end
	end
	-- Values describe the code as it ran; drop them as soon as the pad changes
	if not vim.b[bufnr].scratch_manager_dump_watch then
		vim.b[bufnr].scratch_manager_dump_watch = true
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			buffer = bufnr,
			callback = function()
				M.clear_inline(bufnr)
			end,
		})
	end
end

---Split `.Dump()` markers out of program output
---@param lines string[]
---@return string[] rest Output without markers
---@return table<number, string[]> dumps Pad line -> values
---@return number count Number of values
function M.extract_dumps(lines)
	local rest, dumps, count = {}, {}, 0
	for _, line in ipairs(lines) do
		local lnum, text = line:match("^\30(%d+)\31(.*)$")
		if lnum then
			lnum = tonumber(lnum)
			dumps[lnum] = dumps[lnum] or {}
			table.insert(dumps[lnum], text)
			count = count + 1
		else
			table.insert(rest, line)
		end
	end
	return rest, dumps, count
end

---Stable per-pad working directory, so tools can reuse their build caches between runs
---@param pad_file string Path of the scratch pad file
---@param ft string|nil Pad filetype (default "cs")
---@return string dir
function M.work_dir(pad_file, ft)
	local key = vim.fn.sha256(pad_file):sub(1, 16)
	return vim.fn.stdpath("cache") .. "/scratch-manager/" .. (ft or "cs") .. "/" .. key
end

---Selected line range when called from visual mode (and leave visual mode), otherwise nil
---@return { first: number, last: number }|nil
local function selection_range()
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		local first, last = vim.fn.line("v"), vim.fn.line(".")
		if first > last then
			first, last = last, first
		end
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
		return { first = first, last = last }
	end
	return nil
end

---Close the output window if it is open
function M.close_output()
	if output.win and vim.api.nvim_win_is_valid(output.win) then
		vim.api.nvim_win_close(output.win, true)
	end
	output.win = nil
end

local detail_ns = vim.api.nvim_create_namespace("scratch-manager-output-detail")

---Show run output in a float anchored to the bottom of the pad window
---@param lines string[] Output lines
---@param title string Window title (keep it short; it doesn't wrap)
---@param pad_win number|nil Pad window to anchor to (falls back to the editor)
---@param max_height number
---@param details string|nil Dimmed first line (project, what ran, hidden warnings); wraps
function M.show_output(lines, title, pad_win, max_height, details)
	output.last = { lines = lines, title = title, pad_win = pad_win, max_height = max_height, details = details }
	if #lines == 0 then
		lines = { "(no output)" }
	end
	if details then
		lines = vim.list_extend({ details }, lines)
	end
	if not (output.buf and vim.api.nvim_buf_is_valid(output.buf)) then
		output.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[output.buf].bufhidden = "hide"
		local opts = { buffer = output.buf, nowait = true, silent = true, desc = "Close output" }
		vim.keymap.set("n", "q", M.close_output, opts)
		vim.keymap.set("n", "<Esc>", M.close_output, opts)
	end
	vim.bo[output.buf].modifiable = true
	vim.api.nvim_buf_set_lines(output.buf, 0, -1, false, lines)
	vim.bo[output.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(output.buf, detail_ns, 0, -1)
	if details then
		vim.api.nvim_buf_set_extmark(output.buf, detail_ns, 0, 0, { end_col = #details, hl_group = "Comment" })
	end

	local win_config
	if pad_win and vim.api.nvim_win_is_valid(pad_win) then
		local pad_height = vim.api.nvim_win_get_height(pad_win)
		local height = math.max(1, math.min(#lines, max_height, pad_height - 4))
		win_config = {
			relative = "win",
			win = pad_win,
			row = pad_height - height - 2, -- inside the pad, above its bottom border
			col = 0,
			width = math.max(10, vim.api.nvim_win_get_width(pad_win) - 2),
			height = height,
		}
	else
		local width = math.floor(vim.o.columns * 0.6)
		local height = math.max(1, math.min(#lines, max_height))
		win_config = {
			relative = "editor",
			row = math.floor((vim.o.lines - height) / 2),
			col = math.floor((vim.o.columns - width) / 2),
			width = width,
			height = height,
		}
	end
	win_config = vim.tbl_extend("force", win_config, {
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
		footer = " q close ",
		footer_pos = "center",
		zindex = 60,
	})

	M.close_output()
	output.win = vim.api.nvim_open_win(output.buf, false, win_config)
	vim.wo[output.win].wrap = true
	vim.wo[output.win].scrolloff = 0

	-- Size to the wrapped text (a single long error line can take several rows)
	local limit = max_height
	if pad_win and vim.api.nvim_win_is_valid(pad_win) then
		limit = math.min(limit, vim.api.nvim_win_get_height(pad_win) - 4)
	end
	local wanted = math.max(1, math.min(vim.api.nvim_win_text_height(output.win, {}).all, limit))
	if wanted ~= win_config.height then
		if win_config.relative == "win" then
			win_config.row = win_config.row + win_config.height - wanted -- keep the bottom edge in place
		end
		win_config.height = wanted
		vim.api.nvim_win_set_config(output.win, win_config)
	end
	-- Results and exceptions come last (after any build output), so show the end
	vim.api.nvim_win_set_cursor(output.win, { #lines, 0 })
	vim.api.nvim_win_call(output.win, function()
		vim.cmd("normal! zb")
	end)
	vim.wo[output.win].winhighlight = "NormalFloat:Normal,FloatBorder:ScratchManagerBorder,FloatTitle:ScratchManagerTitle"

	-- The output belongs to the pad: close it when the pad closes
	if pad_win then
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(pad_win),
			once = true,
			callback = function()
				vim.schedule(M.close_output)
			end,
		})
	end
end

---@param ms number
---@return string
local function duration(ms)
	return ms < 1000 and (ms .. "ms") or ("%.1fs"):format(ms / 1000)
end

---Create a directory, tolerating another process creating it (or a parent) at the same time
---(`mkdir -p` can fail with E739 "file already exists" in that race)
---@param dir string
function M.ensure_dir(dir)
	for _ = 1, 3 do
		pcall(vim.fn.mkdir, dir, "p")
		if vim.fn.isdirectory(dir) == 1 then
			return
		end
	end
	error("Could not create " .. dir)
end

---"lines a–b" for a selection, with an optional extra ("+ 1 using line")
---@param range { first: number, last: number }
---@param extra string|nil
---@return string
local function scope_text(range, extra)
	local text = ("lines %d–%d"):format(range.first, range.last)
	return extra and (text .. " + " .. extra) or text
end

---Run a pad with its language's run spec
---@param bufnr number Pad buffer
---@param ft string Pad filetype (selects the language profile)
---@param config ScratchManagerRunConfig|nil
function M.run(bufnr, ft, config)
	config = config or {}
	local spec = languages.get(ft).run
	if not spec then
		vim.notify("No runner for " .. ft .. " pads", vim.log.levels.WARN)
		return
	end
	local cmd = spec.cmd(config)
	local max_height = config.max_height or 15
	if vim.fn.executable(cmd[1]) ~= 1 then
		vim.notify(spec.missing and spec.missing(cmd) or (cmd[1] .. " not found on PATH"), vim.log.levels.ERROR)
		return
	end

	local pad_win = vim.fn.bufwinid(bufnr)
	pad_win = pad_win ~= -1 and pad_win or nil
	local dir = M.work_dir(vim.api.nvim_buf_get_name(bufnr), ft)
	M.ensure_dir(dir)
	local file = dir .. "/" .. spec.file
	local range = selection_range()
	local pad_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local compiled, details, placeholder
	if spec.prepare then
		compiled, details, placeholder = spec.prepare({
			bufnr = bufnr,
			pad_lines = pad_lines,
			range = range,
			config = config,
			scope = function(extra)
				return scope_text(range, extra)
			end,
		})
	else
		compiled = range and vim.list_slice(pad_lines, range.first, range.last) or pad_lines
	end
	details = details or {}
	if range and not spec.prepare then
		table.insert(details, scope_text(range))
	end
	M.clear_inline(bufnr)
	vim.fn.writefile(compiled, file)
	table.insert(cmd, file)

	local title = spec.title or table.concat(cmd, " ", 1, 1)
	M.show_output({ placeholder or "Running…" }, title .. "…", pad_win, max_height,
		#details > 0 and table.concat(details, " · ") or nil)
	local started = vim.uv.hrtime()
	vim.system(cmd, { cwd = dir, text = true }, function(result)
		vim.schedule(function()
			local text = (result.stdout or "") .. (result.stderr or "")
			-- Point messages at the pad instead of the hidden work file
			text = text:gsub(vim.pesc(file), "pad")
			local lines = vim.split(vim.trim(text), "\n", { plain = true })
			if #lines == 1 and lines[1] == "" then
				lines = {}
			end
			-- Inline values go next to their lines instead of into the output window
			local dumped = 0
			if spec.inline and config.inline ~= false then
				local dumps
				lines, dumps, dumped = M.extract_dumps(lines)
				if dumped > 0 and vim.api.nvim_buf_is_valid(bufnr) then
					M.show_inline(bufnr, dumps)
				end
			end
			-- Noise the profile recognizes (e.g. build warnings), unless asked to show it
			local hidden = 0
			if spec.hide_line and not config.show_warnings then
				lines = vim.tbl_filter(function(line)
					if spec.hide_line(line) then
						hidden = hidden + 1
						return false
					end
					return true
				end, lines)
			end
			local ms = math.floor((vim.uv.hrtime() - started) / 1e6)
			local status = result.code == 0 and "✓ ok" or ("✗ exit " .. result.code)
			if #lines == 0 and dumped > 0 then
				lines = { ("%d value%s shown inline (K on its line for the full value)"):format(dumped, dumped == 1 and "" or "s") }
			end
			if hidden > 0 then
				table.insert(details, ("%d warning%s hidden"):format(hidden, hidden == 1 and "" or "s"))
			end
			M.show_output(lines, ("%s · %s · %s"):format(title, status, duration(ms)), pad_win, max_height,
				#details > 0 and table.concat(details, " · ") or nil)
		end)
	end)
end

---Redraw the output window after its pad was resized
---@param pad_win number
function M.relayout(pad_win)
	local last = output.last
	if last and last.pad_win == pad_win and output.win and vim.api.nvim_win_is_valid(output.win) then
		M.show_output(last.lines, last.title, last.pad_win, last.max_height, last.details)
	end
end

---Snacks window key spec that runs a pad (added to the pad window's keys)
---@param ft string
---@param config ScratchManagerRunConfig|nil
---@return table key
function M.run_key(ft, config)
	local spec = languages.get(ft).run or {}
	return {
		"<cr>",
		function(self)
			M.run(self.buf, ft, config)
		end,
		desc = spec.desc or "Run",
		mode = { "n", "x" },
	}
end

---Snacks window key spec: full `.Dump()` value of the cursor line
---@return table key
function M.dump_detail_key()
	return {
		"K",
		function(self)
			M.show_dump_detail(self.buf)
		end,
		desc = "Value",
	}
end

-- C# conveniences (the C# specifics live in scratch-manager.languages.cs)
function M.run_csharp(bufnr, config)
	M.run(bufnr, "cs", config)
end
function M.csharp_key(config)
	return M.run_key("cs", config)
end
M.compose = function(...)
	return languages.get("cs").compose(...)
end
M.find_project = function(...)
	return languages.get("cs").find_project(...)
end

-- Expose internal state for testing
M._output = output

return M
