---Run C# scratch pads with `dotnet run <file>.cs` (file-based apps, .NET 10+)
---No .sln or .csproj needed; output is shown in a float over the bottom of the pad

local M = {}

---@class ScratchManagerRunConfig
---@field enabled boolean Bind <CR> in C# pads to run them (default: true)
---@field cmd string[] Command to run; the source file path is appended
---                    (default: { "dotnet", "run", "-p:PublishAot=false" })
---@field max_height number Maximum height of the output window (default: 15)
---@field project boolean Reference the source file's nearest .csproj via #:project (default: true)
---@field show_warnings boolean Show compiler/NuGet build warnings in the output (default: false)
---@field inline boolean Support `.Dump()`: values show at the end of the line that produced them (default: true)

local output = {
	buf = nil,
	win = nil,
}

local dump_ns = vim.api.nvim_create_namespace("scratch-manager-dump")
local dump_values = {} -- pad bufnr -> { [pad line] = { full values } }
local detail = { buf = nil, win = nil }

-- Appended to the compiled copy when the pad uses `.Dump(`. Writes each value as
-- "\x1e<line>\x1f<text>" (line via [CallerLineNumber], which honors the #line mapping, so it is the
-- pad line). The runner turns those into virtual text and keeps them out of the output window.
-- Fully qualified names: using directives can't follow the pad's code.
local DUMP_HELPER = vim.split([==[
#line default
static class ScratchManagerDump
{
    static readonly System.Text.Json.JsonSerializerOptions Options = new()
    {
        ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles,
    };

    public static T Dump<T>(this T value, string? label = null,
        [System.Runtime.CompilerServices.CallerLineNumber] int line = 0)
    {
        string text;
        try
        {
            text = value switch
            {
                null => "null",
                string s => "\"" + s + "\"",
                System.Text.Json.JsonElement e => e.GetRawText(),
                System.Runtime.CompilerServices.ITuple => value.ToString()!,
                System.IFormattable or bool or char => value.ToString()!,
                _ => System.Text.Json.JsonSerializer.Serialize(value, Options),
            };
        }
        catch (System.Exception ex)
        {
            text = value + " (" + ex.GetType().Name + ")";
        }
        text = text.Replace("\r", "").Replace("\n", " ");
        System.Console.Out.WriteLine("\u001e" + line + "\u001f" + (label is null ? "" : label + ": ") + text);
        return value;
    }
}]==], "\n")

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

---Show `.Dump()` values at the end of the pad lines that produced them
---@param bufnr number Pad buffer
---@param dumps table<number, string[]> Pad line -> values (in order)
function M.show_inline(bufnr, dumps)
	M.clear_inline(bufnr)
	dump_values[bufnr] = dumps
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

---Stable per-pad working directory, so dotnet can reuse its build cache between runs
---@param pad_file string Path of the scratch pad file
---@return string dir
function M.work_dir(pad_file)
	local key = vim.fn.sha256(pad_file):sub(1, 16)
	return vim.fn.stdpath("cache") .. "/scratch-manager/cs/" .. key
end

---Nearest .csproj at or above the pad's source file (the file the pad was opened from)
---@param pad_bufnr number
---@return string|nil csproj Absolute path
function M.find_project(pad_bufnr)
	local source = vim.b[pad_bufnr].scratch_manager_source
		or require("scratch-manager.store").get("pad_sources", vim.api.nvim_buf_get_name(pad_bufnr))
	if type(source) ~= "string" or source == "" then
		return nil
	end
	local found = vim.fs.find(function(name)
		return name:match("%.csproj$") ~= nil
	end, { upward = true, path = vim.fs.dirname(source), type = "file", limit = 1 })
	return found[1]
end

---Does the pad already reference a project with its own #: directive?
---@param lines string[]
---@return boolean
local function has_project_directive(lines)
	for _, line in ipairs(lines) do
		if line:match("^%s*#:project%s") then
			return true
		end
	end
	return false
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

---Is this line a using directive (not a `using var x = ...;` / `using (...)` statement)?
---@param line string
---@return boolean
local function is_using_directive(line)
	return line:match("^%s*global%s+using%s") ~= nil
		or line:match("^%s*using%s+static%s+[%w_.<>,%s]+;%s*$") ~= nil
		or line:match("^%s*using%s+[%w_.]+%s*;%s*$") ~= nil
		or line:match("^%s*using%s+[%w_]+%s*=%s*[%w_.<>,%s]+;%s*$") ~= nil
end

---Build the file that gets compiled from the pad lines.
---
---- `#:` directives (the pad's own, plus the project reference) are hoisted to the very top, as
---  dotnet requires; in the body they become blank lines so line numbers don't move.
---- For a selection, the using directives at the top of the pad are included too (each tagged
---  with its pad line number), so a selected block that relies on them still compiles.
---- `#line` keeps compiler line numbers matching the pad.
---@param pad_lines string[] All lines of the pad
---@param range { first: number, last: number }|nil Selected lines, nil for the whole pad
---@param project string|nil .csproj to reference
---@param opts? { inline?: boolean } inline (default true): append the `.Dump()` helper when used
---@return string[] compiled
---@return number usings Number of using lines added for a selection
function M.compose(pad_lines, range, project, opts)
	opts = opts or {}
	local directives, body_start = {}, 1
	if project then
		table.insert(directives, "#:project " .. project)
	end
	for _, line in ipairs(pad_lines) do
		if line:match("^%s*#:") then
			table.insert(directives, vim.trim(line))
		end
	end

	local first, last = 1, #pad_lines
	if range then
		first, last = range.first, range.last
	end

	local compiled = vim.list_extend({}, directives)
	local usings = 0
	if range then
		-- Using directives in the pad's header (before its first line of code), outside the selection
		for lnum, line in ipairs(pad_lines) do
			local blank = line:match("^%s*$") or line:match("^%s*//") or line:match("^%s*#[:!]")
			if not blank and not is_using_directive(line) then
				break
			end
			if lnum >= first then
				break
			end
			if is_using_directive(line) then
				vim.list_extend(compiled, { "#line " .. lnum, line })
				usings = usings + 1
			end
		end
	end
	body_start = first

	table.insert(compiled, "#line " .. body_start)
	local uses_dump = false
	for lnum = first, last do
		local line = pad_lines[lnum]
		table.insert(compiled, line:match("^%s*#:") and "" or line)
		uses_dump = uses_dump or line:find(".Dump(", 1, true) ~= nil
	end
	if uses_dump and opts.inline ~= false then
		vim.list_extend(compiled, DUMP_HELPER)
	end
	return compiled, usings
end

---Close the output window if it is open
function M.close_output()
	if output.win and vim.api.nvim_win_is_valid(output.win) then
		vim.api.nvim_win_close(output.win, true)
	end
	output.win = nil
end

---Show run output in a float anchored to the bottom of the pad window
---@param lines string[] Output lines
---@param title string Window title
---@param pad_win number|nil Pad window to anchor to (falls back to the editor)
---@param max_height number
function M.show_output(lines, title, pad_win, max_height)
	if #lines == 0 then
		lines = { "(no output)" }
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

---Run a C# scratch pad
---@param bufnr number Pad buffer
---@param config ScratchManagerRunConfig|nil
function M.run_csharp(bufnr, config)
	config = config or {}
	local cmd = vim.deepcopy(config.cmd or { "dotnet", "run", "-p:PublishAot=false" })
	local max_height = config.max_height or 15
	if vim.fn.executable(cmd[1]) ~= 1 then
		vim.notify(cmd[1] .. " not found on PATH (C# pads need the .NET 10+ SDK)", vim.log.levels.ERROR)
		return
	end

	local pad_win = vim.fn.bufwinid(bufnr)
	pad_win = pad_win ~= -1 and pad_win or nil
	local dir = M.work_dir(vim.api.nvim_buf_get_name(bufnr))
	vim.fn.mkdir(dir, "p")
	local file = dir .. "/scratch.cs"
	local range = selection_range()
	local pad_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Reference the source file's project so the pad can use its types
	local project = config.project ~= false and not has_project_directive(pad_lines) and M.find_project(bufnr) or nil
	local compiled, usings = M.compose(pad_lines, range, project, { inline = config.inline })
	M.clear_inline(bufnr)
	vim.fn.writefile(compiled, file)
	table.insert(cmd, file)

	-- Say exactly what ran, so a selection that also pulled in using lines isn't a mystery
	local label = project and vim.fn.fnamemodify(project, ":t") or nil
	local scope = ""
	if range then
		scope = (" · lines %d–%d"):format(range.first, range.last)
		if usings > 0 then
			scope = scope .. (" + %d using line%s"):format(usings, usings == 1 and "" or "s")
		end
	end
	local prefix = "dotnet run" .. (label and (" · " .. label) or "") .. scope
	M.show_output({ project and ("Building with " .. label .. "…") or "Running…" }, prefix, pad_win, max_height)
	local started = vim.uv.hrtime()
	vim.system(cmd, { cwd = dir, text = true }, function(result)
		vim.schedule(function()
			local text = (result.stdout or "") .. (result.stderr or "")
			-- Point compiler messages at the pad instead of the hidden work file
			text = text:gsub(vim.pesc(file) .. "%(", "pad(")
			local lines = vim.split(vim.trim(text), "\n", { plain = true })
			if #lines == 1 and lines[1] == "" then
				lines = {}
			end
			-- `.Dump()` values go next to their lines instead of into the output window
			local dumps, dumped
			lines, dumps, dumped = M.extract_dumps(lines)
			if dumped > 0 and vim.api.nvim_buf_is_valid(bufnr) then
				M.show_inline(bufnr, dumps)
			end
			-- Build warnings (CS/NU/IL codes, often from the referenced project) are noise in a pad
			local hidden = 0
			if not config.show_warnings then
				lines = vim.tbl_filter(function(line)
					if line:match(": warning %u+%d+:") then
						hidden = hidden + 1
						return false
					end
					return true
				end, lines)
			end
			local ms = math.floor((vim.uv.hrtime() - started) / 1e6)
			local status = result.code == 0 and "ok" or ("exit " .. result.code)
			if #lines == 0 and dumped > 0 then
				lines = { ("%d value%s shown inline (→, K for the full value)"):format(dumped, dumped == 1 and "" or "s") }
			end
			local note = hidden > 0 and (" · %d warning%s hidden"):format(hidden, hidden == 1 and "" or "s") or ""
			M.show_output(lines, ("%s · %s · %dms%s"):format(prefix, status, ms, note), pad_win, max_height)
		end)
	end)
end

---Snacks window key spec for running C# pads (added to the pad window's keys)
---@param config ScratchManagerRunConfig|nil
---@return table key
function M.csharp_key(config)
	return {
		"<cr>",
		function(self)
			M.run_csharp(self.buf, config)
		end,
		desc = "Run (dotnet run)",
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

-- Expose internal state for testing
M._output = output

return M
