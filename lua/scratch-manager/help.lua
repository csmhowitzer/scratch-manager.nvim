---Per-language help for scratch pads (`=h` inside a pad)
---
---Content is written as simple blocks (heading, paragraph, table, list, code) and rendered to
---formatted text with highlights, so it reads well without a markdown plugin. Inline `code` and
---**bold** are highlighted with their markers removed. Content includes the pad's own details
---(source file, project, connection) so it answers "what will <CR> do here?"

local M = {}

local state = { buf = nil, win = nil }
local ns = vim.api.nvim_create_namespace("scratch-manager-help")

---@class ScratchManagerHelpInfo
---@field ft string Pad filetype
---@field kind "notes"|"code"|"db"
---@field name string|nil Pad name, e.g. "StringExtensions.cs"
---@field source string|nil File the pad belongs to
---@field project string|nil .csproj a C# pad will reference
---@field connection string|nil Remembered DB connection
---@field provider string|nil SQL provider name (nil when none is available)
---@field keymaps table Configured global keymaps
---@field help_key string Key that opens this help
---@field border_hl string

---@param key string|false|nil
---@return string
local function k(key)
	return key and ("`" .. key .. "`") or "(disabled)"
end

---@param info ScratchManagerHelpInfo
---@return string
local function source_name(info)
	return info.name or (info.source and vim.fn.fnamemodify(info.source, ":t")) or "its file"
end

---@param info ScratchManagerHelpInfo
---@return table[] blocks
local function common(info)
	local km = info.keymaps
	return {
		{ h = "All pads" },
		{
			t = {
				{ "Key", "Action" },
				{ k(km.toggle), "Notes pad (markdown) for the current file" },
				{ k(km.toggle_lang), "Code pad in the file's language" },
				{ k(km.toggle_db), "DB pad (SQL)" },
				{ k(km.select), "Browse every pad" },
				{ k(km.delete), "Delete a pad (asks first)" },
				{ "`<M-z>`", "Toggle word wrap in this pad" },
				{ k(info.help_key), "This help (`q` closes)" },
			},
		},
		{
			ul = {
				"The same key closes a pad you're in; the badges in the top-right corner open them.",
				"Pads save themselves after every change; there is nothing to `:w`.",
				"A pad belongs to the file name, Neovim's working directory (`:pwd`), the git branch and the pad's filetype.",
			},
		},
	}
end

---@param info ScratchManagerHelpInfo
---@return table[] blocks
local function csharp(info)
	local project = info.project and ("`" .. vim.fn.fnamemodify(info.project, ":t") .. "`")
		or "no project yet (open the pad from a file inside a project)"
	return {
		{ title = "C# scratch pad · " .. source_name(info) },
		{
			p = ("Throwaway C# for **%s**. It runs with `dotnet run` on a single file (.NET 10), so no `.sln` or `.csproj` is needed."):format(source_name(info)),
		},
		{
			t = {
				{ "Key", "Action" },
				{ "`<CR>`", "Run the whole pad" },
				{ "`V` … `<CR>`", "Run only the selected lines" },
				{ "`K`", "Full value of a `.Dump()` on the cursor line" },
				{ "`q`", "Close the output (from inside it)" },
			},
		},
		{ h = "Inline values: .Dump()" },
		{
			p = "Add `.Dump()` to any expression and its value shows at the end of that line when you run, instead of writing `Console.WriteLine` everywhere. Objects show as JSON; `K` opens the full, formatted value. `.Dump()` returns its value, so it works in the middle of a chain:",
		},
		{
			code = {
				'info.Dump();                                   // → {"JobId":"6f1c…","ExternalId":"HOVER-1182",…}',
				'var digits = phones.Select(p => p.ToPhoneDigits()).Dump("digits")  // → digits: ["5551234567",…]',
				"    .Select(d => d!.ToPhone()).Dump(\"formatted\");",
			},
		},
		{ p = "A `.Dump()` in a loop shows every value: `(3×) 14 │ 11 │ 12`. Editing the pad clears the values until the next run." },
		{ h = "Using your project" },
		{
			p = ("Runs with a reference to %s, so you can use its types directly (`using YourProject.Namespace;`). The first run builds the project; later runs are fast."):format(project),
		},
		{
			p = "Build warnings are hidden and counted in the output title. Errors always show, with pad line numbers, for example `pad(7,9): error CS0029`.",
		},
		{ h = "Running a selection" },
		{
			p = "Only the selected lines run, **plus** the `using` lines at the top of the pad and any `#:` lines, so a selected block still finds its namespaces. The output title says exactly what ran, for example `lines 6–7 + 1 using line`.",
		},
		{ h = "#: directives" },
		{ p = "Single-file apps have no `.csproj`; these lines at the top of the file replace it:" },
		{
			t = {
				{ "Directive", "Replaces (in a .csproj)", "Example" },
				{ "`#:package`", "`<PackageReference>`", "`#:package Humanizer@2.14.1`" },
				{ "`#:project`", "`<ProjectReference>`", "`#:project ../Billing/Billing.csproj`" },
				{ "`#:property`", "a `<PropertyGroup>` setting", "`#:property LangVersion=preview`" },
				{ "`#:sdk`", "`<Project Sdk=\"...\">`", "`#:sdk Microsoft.NET.Sdk.Web`" },
			},
		},
		{
			p = "The project reference above is added for you, and reflection-based JSON works (`PublishAot=false` is passed for you).",
		},
		{ h = "Tips" },
		{
			ul = {
				"Statements come first; `record` / `class` declarations go at the bottom.",
				"Good fits: pure functions, mappers, parsing a pasted webhook payload, checking what `JsonSerializer` produces.",
				"Code that needs DI, a database or Kafka fits a real test better.",
			},
		},
		{
			code = {
				"using System.Text.Json;",
				"",
				'var payload = JsonDocument.Parse("""{ "JobInfo": { "Id": 42 } }""").RootElement;',
				'Console.WriteLine(payload.GetProperty("JobInfo").GetProperty("Id").GetInt32());',
			},
		},
	}
end

---@param info ScratchManagerHelpInfo
---@return table[] blocks
local function sql(info)
	local blocks = {
		{ title = "DB scratch pad (SQL) · " .. source_name(info) },
		{ p = ("SQL for **%s**, run through **%s**."):format(source_name(info), info.provider or "no SQL provider") },
		{
			t = {
				{ "Key", "Action" },
				{ "`<CR>`", "Run the whole pad" },
				{ "`V` … `<CR>`", "Run only the selected statements" },
				{ "`<leader>dc`", "Choose the connection" },
			},
		},
		{ h = "Connection" },
		{
			p = info.connection and ("This pad runs on **%s** (remembered per pad)."):format(info.connection)
				or "No connection yet: the first run asks, then the pad remembers it.",
		},
		{ h = "Completion" },
		{
			p = "On SQL Server connections, table and column names are suggested as you type (vim-dadbod-completion). `Ctrl-x Ctrl-o` asks for suggestions manually.",
		},
		{ h = "Results" },
		{
			p = "Results open in enhance.nvim's results window. The pad closes when you run so the results get the full width; reopen it with the DB pad key or its badge.",
		},
	}
	if not info.provider then
		vim.list_extend(blocks, {
			{ h = "No provider" },
			{
				p = "Running needs enhance.nvim (or a custom provider in `run.sql.provider`). Without one this is still a saved SQL scratch pad.",
			},
		})
	end
	return blocks
end

---@param info ScratchManagerHelpInfo
---@return table[] blocks
local function lua(info)
	return {
		{ title = "Lua scratch pad · " .. source_name(info) },
		{ p = ("Lua for **%s**, run by snacks.nvim inside this Neovim."):format(source_name(info)) },
		{
			t = {
				{ "Key", "Action" },
				{ "`<CR>`", "Run the whole pad; results show next to the lines" },
				{ "`V` … `<CR>`", "Run only the selection" },
			},
		},
		{
			p = "It runs in your live editor, so `vim.api` and your plugins are available: handy for trying config snippets. It can also change your current session.",
		},
	}
end

---@param info ScratchManagerHelpInfo
---@return table[] blocks
local function notes(info)
	return {
		{ title = "Notes scratch pad · " .. source_name(info) },
		{ p = ("Markdown notes for **%s**. Long lines wrap (`<M-z>` toggles)."):format(source_name(info)) },
	}
end

---@param info ScratchManagerHelpInfo
---@return table[] blocks
local function other(info)
	local ft = info.ft ~= "" and info.ft or "code"
	return {
		{ title = ("%s scratch pad · %s"):format(ft, source_name(info)) },
		{
			p = ("Scratch code for **%s**. Running isn't supported for `%s` pads yet; C#, SQL and Lua pads can run."):format(source_name(info), ft),
		},
	}
end

---Help content for a pad, as blocks
---@param info ScratchManagerHelpInfo
---@return table[]
function M.blocks(info)
	local body
	if info.ft == "cs" then
		body = csharp(info)
	elseif info.ft == "sql" then
		body = sql(info)
	elseif info.ft == "lua" then
		body = lua(info)
	elseif info.kind == "notes" then
		body = notes(info)
	else
		body = other(info)
	end
	return vim.list_extend(body, common(info))
end

-- Rendering ----------------------------------------------------------------------------------

---Strip inline `code` / **bold** markers, returning plain text and highlight ranges (byte cols)
---@param text string
---@return string plain
---@return { [1]: number, [2]: number, [3]: string }[] ranges { start_col, end_col, group }
function M.inline(text)
	local out, ranges = {}, {}
	local len = 0
	local i = 1
	while i <= #text do
		local c2 = text:sub(i, i + 1)
		local c = text:sub(i, i)
		local close, group, skip
		if c2 == "**" then
			close, group, skip = text:find("**", i + 2, true), "ScratchManagerHelpBold", 2
		elseif c == "`" then
			close, group, skip = text:find("`", i + 1, true), "ScratchManagerHelpCode", 1
		end
		if close then
			local inner = text:sub(i + skip, close - 1)
			table.insert(ranges, { len, len + #inner, group })
			table.insert(out, inner)
			len = len + #inner
			i = close + skip
		else
			table.insert(out, c)
			len = len + 1
			i = i + 1
		end
	end
	return table.concat(out), ranges
end

---Render blocks to lines and highlights
---@param blocks table[]
---@return string[] lines
---@return { [1]: number, [2]: number, [3]: number, [4]: string }[] highlights { row, start_col, end_col, group } (0-based row)
function M.render(blocks)
	local lines, hls = {}, {}
	local function add(text, ranges, offset)
		table.insert(lines, text)
		local row = #lines - 1
		for _, r in ipairs(ranges or {}) do
			table.insert(hls, { row, r[1] + (offset or 0), r[2] + (offset or 0), r[3] })
		end
	end
	local function blank()
		if #lines > 0 and lines[#lines] ~= "" then
			table.insert(lines, "")
		end
	end

	for _, block in ipairs(blocks) do
		if block.title then
			add(block.title, { { 0, #block.title, "ScratchManagerHelpTitle" } })
			add(string.rep("━", vim.api.nvim_strwidth(block.title)), { { 0, #string.rep("━", vim.api.nvim_strwidth(block.title)), "ScratchManagerHelpTitle" } })
			blank()
		elseif block.h then
			blank()
			add(block.h, { { 0, #block.h, "ScratchManagerHelpHeading" } })
			local rule = string.rep("─", vim.api.nvim_strwidth(block.h))
			add(rule, { { 0, #rule, "ScratchManagerHelpRule" } })
		elseif block.p then
			local text, ranges = M.inline(block.p)
			add(text, ranges)
			blank()
		elseif block.ul then
			for _, item in ipairs(block.ul) do
				local text, ranges = M.inline(item)
				add("  • " .. text, vim.list_extend({ { 2, 2 + #"•", "ScratchManagerHelpRule" } }, vim.tbl_map(function(r)
					return { r[1] + #"  • ", r[2] + #"  • ", r[3] }
				end, ranges)))
			end
			blank()
		elseif block.code then
			for _, line in ipairs(block.code) do
				local text = "    " .. line
				add(text, line ~= "" and { { 0, #text, "ScratchManagerHelpCode" } } or {})
			end
			blank()
		elseif block.t then
			-- Strip markers per cell, then pad by display width so columns line up
			local cells, widths = {}, {}
			for r, row in ipairs(block.t) do
				cells[r] = {}
				for c, cell in ipairs(row) do
					local text, ranges = M.inline(cell)
					cells[r][c] = { text = text, ranges = ranges }
					widths[c] = math.max(widths[c] or 0, vim.api.nvim_strwidth(text))
				end
			end
			local function border(left, mid, right)
				local parts = {}
				for _, w in ipairs(widths) do
					table.insert(parts, string.rep("─", w + 2))
				end
				local text = left .. table.concat(parts, mid) .. right
				add(text, { { 0, #text, "ScratchManagerHelpRule" } })
			end
			border("╭", "┬", "╮")
			for r, row in ipairs(cells) do
				local text, ranges = "│", { { 0, #"│", "ScratchManagerHelpRule" } }
				for c, cell in ipairs(row) do
					local start = #text + 1
					for _, rg in ipairs(cell.ranges) do
						table.insert(ranges, { rg[1] + start, rg[2] + start, rg[3] })
					end
					if r == 1 then
						table.insert(ranges, { start, start + #cell.text, "ScratchManagerHelpHeading" })
					end
					text = text .. " " .. cell.text .. string.rep(" ", widths[c] - vim.api.nvim_strwidth(cell.text)) .. " "
					table.insert(ranges, { #text, #text + #"│", "ScratchManagerHelpRule" })
					text = text .. "│"
				end
				add(text, ranges)
				if r == 1 then
					border("├", "┼", "┤")
				end
			end
			border("╰", "┴", "╯")
			blank()
		end
	end
	while lines[#lines] == "" do
		table.remove(lines)
	end
	return lines, hls
end

---Close the help window
function M.close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
end

---Show help for a pad in a centered float
---@param info ScratchManagerHelpInfo
function M.open(info)
	M.close()
	local lines, hls = M.render(M.blocks(info))
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[state.buf].bufhidden = "hide"
		vim.bo[state.buf].filetype = "scratch_manager_help"
	end
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for _, hl in ipairs(hls) do
		pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, hl[1], hl[2], { end_col = hl[3], hl_group = hl[4] })
	end

	local opts = { buffer = state.buf, nowait = true, silent = true, desc = "Close help" }
	for _, lhs in ipairs({ "q", "<Esc>", info.help_key }) do
		vim.keymap.set("n", lhs, M.close, opts)
	end

	local width = math.min(96, vim.o.columns - 6)
	local height = math.min(#lines, math.floor(vim.o.lines * 0.8))
	local title = info.name and (" Scratch Pad (%s) · help "):format(info.name) or " Scratch pad help "
	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = title,
		title_pos = "center",
		footer = " q close ",
		footer_pos = "center",
		zindex = 70,
	})
	vim.wo[state.win].wrap = true
	vim.wo[state.win].linebreak = true
	vim.wo[state.win].breakindent = true
	vim.wo[state.win].winhighlight = "NormalFloat:Normal,FloatBorder:" .. info.border_hl .. ",FloatTitle:ScratchManagerTitle"
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = state.buf,
		once = true,
		callback = function()
			vim.schedule(M.close)
		end,
	})
end

-- Expose internal state for testing
M._state = state

return M
