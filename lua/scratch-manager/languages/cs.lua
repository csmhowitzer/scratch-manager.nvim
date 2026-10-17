---C# language profile (see languages/init.lua for the hooks)
---Runs pads with `dotnet run <file>.cs` (.NET 10 file-based apps: no .sln or .csproj needed)

local M = {}

M.treesitter = "c_sharp" -- the filetype is "cs"
M.comment = "// %s" -- Neovim's default 'commentstring' for C# is /*%s*/

-- Imports and adapting sent code ---------------------------------------------------------------

---Is this a using directive (not a `using var x = ...;` / `using (...)` statement)?
---@param line string
---@return boolean
function M.is_using(line)
	return line:match("^%s*global%s+using%s") ~= nil
		or line:match("^%s*using%s+static%s+[%w_.<>,%s]+;%s*$") ~= nil
		or line:match("^%s*using%s+[%w_.]+%s*;%s*$") ~= nil
		or line:match("^%s*using%s+[%w_]+%s*=%s*[%w_.<>,%s]+;%s*$") ~= nil
end

---Header lines: using directives and single-file app directives (#:, #!)
---@param line string
---@return boolean
function M.is_import(line)
	return M.is_using(line) or line:match("^%s*#[:!]") ~= nil
end

---Using directives of a source file plus a using for its own namespace (so its types resolve)
---@param source_lines string[]
---@return string[]
function M.imports(source_lines)
	local out, seen = {}, {}
	local function add(line)
		line = vim.trim(line)
		if not seen[line] then
			seen[line] = true
			table.insert(out, line)
		end
	end
	for _, line in ipairs(source_lines) do
		if M.is_using(line) and not line:match("^%s*global%s") then
			add(line)
		else
			local ns = line:match("^%s*namespace%s+([%w_.]+)")
			if ns then
				add("using " .. ns .. ";")
			end
		end
	end
	return out
end

---Order using directives the usual .NET way (as `dotnet format` does): global usings, System and
---System.*, the rest alphabetically, then `using static`, then aliases
---@param lines string[] Using directive lines
---@return string[]
function M.sort_imports(lines)
	local function key(line)
		local l = vim.trim(line)
		local group, name
		if l:match("^global%s") then
			group, name = 0, l
		elseif l:match("^using%s+static%s") then
			group, name = 3, l:match("^using%s+static%s+(.-)%s*;")
		elseif l:match("^using%s+[%w_]+%s*=") then
			group, name = 4, l:match("^using%s+(.-)%s*;")
		else
			name = l:match("^using%s+(.-)%s*;") or l
			group = (name == "System" or name:match("^System%.")) and 1 or 2
		end
		return group, (name or l):lower()
	end
	local sorted = vim.deepcopy(lines)
	table.sort(sorted, function(a, b)
		local ga, na = key(a)
		local gb, nb = key(b)
		if ga ~= gb then
			return ga < gb
		end
		return na < nb
	end)
	return sorted
end

local MODIFIERS = {
	public = true, private = true, protected = true, internal = true, static = true, override = true,
	virtual = true, sealed = true, new = true, extern = true, abstract = true, partial = true, readonly = true,
}

---Make a sent method a local function a pad can call: drop access modifiers, and turn an extension
---method's `this` parameter into a plain parameter (with a note on how to call it)
---@param lines string[] Dedented lines, signature first
---@param node_type string|nil Treesitter node type (nil for a selection)
---@return string[] lines
---@return string|nil note
function M.adapt(lines, node_type)
	if node_type and node_type ~= "method_declaration" then
		return lines, nil
	end
	local signature = lines[1]
	if not signature or not signature:find("(", 1, true) then
		return lines, nil
	end
	local rest, dropped = signature, 0
	while true do
		local word, after = rest:match("^%s*([%a_]+)%s+(.*)$")
		if not (word and MODIFIERS[word]) then
			break
		end
		rest, dropped = after, dropped + 1
	end
	if dropped == 0 then
		return lines, nil
	end
	local note
	if rest:find("%(%s*this%s+") then
		local name = rest:match("([%w_]+)%s*[<(]")
		rest = rest:gsub("%(%s*this%s+", "(", 1)
		note = name and ("was an extension method: call it as %s(value, ...)"):format(name) or nil
	end
	local out = vim.deepcopy(lines)
	out[1] = rest
	return out, note
end

---Insert before the first top-level type declaration: C# top-level statements (and local
---functions) must come before types
---@param pad_lines string[]
---@return number index 0-based
function M.insert_at(pad_lines)
	for i, line in ipairs(pad_lines) do
		if not line:match("^%s") then
			for _, kw in ipairs({ "record", "class", "struct", "interface", "enum" }) do
				if line:match("^[%w%s]*%f[%w]" .. kw .. "%s+[%w_]") then
					return i - 1
				end
			end
		end
	end
	return #pad_lines
end

-- Running ----------------------------------------------------------------------------------------

-- Appended to the compiled copy when the pad uses `.Dump(`. Writes each value as
-- "\x1e<line>\x1f<text>" (line via [CallerLineNumber], which honors the #line mapping, so it is the
-- pad line); the generic runner turns those into virtual text. Fully qualified names: using
-- directives can't follow the pad's code.
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
	local directives = {}
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
			if (not blank and not M.is_using(line)) or lnum >= first then
				break
			end
			if M.is_using(line) then
				vim.list_extend(compiled, { "#line " .. lnum, line })
				usings = usings + 1
			end
		end
	end

	table.insert(compiled, "#line " .. first)
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

---@type ScratchManagerRunSpec
M.run = {
	title = "dotnet run",
	desc = "Run (dotnet run)",
	file = "scratch.cs",
	inline = true,
	cmd = function(config)
		return vim.deepcopy(config.cmd or { "dotnet", "run", "-p:PublishAot=false" })
	end,
	missing = function(cmd)
		return cmd[1] .. " not found on PATH (C# pads need the .NET 10+ SDK)"
	end,
	prepare = function(ctx)
		local config = ctx.config
		local project = config.project ~= false and not has_project_directive(ctx.pad_lines) and M.find_project(ctx.bufnr)
			or nil
		local compiled, usings = M.compose(ctx.pad_lines, ctx.range, project, { inline = config.inline })
		local label = project and vim.fn.fnamemodify(project, ":t") or nil
		local details = {}
		if label then
			table.insert(details, label)
		end
		if ctx.range then
			local extra = usings > 0 and ("%d using line%s"):format(usings, usings == 1 and "" or "s") or nil
			table.insert(details, ctx.scope(extra))
		end
		return compiled, details, label and ("Building with " .. label .. "…") or nil
	end,
	-- Build warnings (CS/NU/IL codes, often from the referenced project) are noise in a pad
	hide_line = function(line)
		return line:match(": warning %u+%d+:") ~= nil
	end,
}

-- Help and health --------------------------------------------------------------------------------

---@param bufnr number
---@param config table run.cs config
---@return table
function M.help_info(bufnr, config)
	return { project = (config or {}).project ~= false and M.find_project(bufnr) or nil }
end

---@param info ScratchManagerHelpInfo
---@param h table Help helpers (source_name, key)
---@return table[] blocks
function M.help(info, h)
	local project = info.project and ("`" .. vim.fn.fnamemodify(info.project, ":t") .. "`")
		or "no project yet (open the pad from a file inside a project)"
	local km = info.keymaps
	return {
		{ title = "C# scratch pad · " .. h.source_name(info) },
		{
			p = ("Throwaway C# for **%s**. It runs with `dotnet run` on a single file (.NET 10), so no `.sln` or `.csproj` is needed."):format(h.source_name(info)),
		},
		{
			t = {
				{ "Key", "Action" },
				{ "`<CR>`", "Run the whole pad" },
				{ "`V` … `<CR>`", "Run only the selected lines" },
				{ "`K`", "Full value of a `.Dump()` on the cursor line (or make the pad wider with " .. h.key(km.pad_size) .. ")" },
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
				'    .Select(d => d!.ToPhone()).Dump("formatted");',
			},
		},
		{ p = "A `.Dump()` in a loop shows every value: `(3×) 14 │ 11 │ 12`. Editing the pad clears the values until the next run." },
		{ h = "Using your project" },
		{
			p = ("Runs with a reference to %s, so you can use its types directly (`using YourProject.Namespace;`). The first run builds the project; later runs are fast."):format(project),
		},
		{
			p = "Build warnings are hidden and counted in the output. Errors always show, with pad line numbers, for example `pad(7,9): error CS0029`.",
		},
		{ h = "Sending code here" },
		{
			p = ("In a C# file, " .. h.key(km.send) .. " sends the selection, or the method under the cursor, to this pad. Methods become local functions (access modifiers dropped), and the file's `using` lines and namespace are added at the top if they're missing."),
		},
		{ h = "Running a selection" },
		{
			p = "Only the selected lines run, **plus** the `using` lines at the top of the pad and any `#:` lines, so a selected block still finds its namespaces. The output says exactly what ran, for example `lines 6–7 + 1 using line`.",
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
	}
end

---`dotnet run file.cs` needs the .NET 10+ SDK
---@param report { ok: function, warn: function, info: function }
function M.health(report)
	if vim.fn.executable("dotnet") ~= 1 then
		report.info("dotnet - not found (optional: needed to run C# pads)")
		return
	end
	local newest = 0
	for _, line in ipairs(vim.fn.systemlist({ "dotnet", "--list-sdks" })) do
		local major = tonumber(line:match("^(%d+)%."))
		if major and major > newest then
			newest = major
		end
	end
	if newest >= 10 then
		report.ok(".NET SDK " .. newest .. " - C# pads can run (dotnet run file.cs)")
	else
		report.warn(".NET SDK " .. (newest > 0 and newest or "?") .. " - C# pads need .NET 10+ to run",
			"Install the .NET 10 SDK, or disable with run = { cs = { enabled = false } }")
	end
end

return M
