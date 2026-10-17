---Language profiles for scratch-manager.nvim
---
---Everything language-specific lives in small profiles (lua/scratch-manager/languages/<ft>.lua, or
---registered from config with `register`), so features stay generic: running a pad, sending code to
---it (`=p`), help, health checks. Every field is optional; missing ones fall back to the defaults.
---
---Code pads
---  imports(source_lines) -> string[]   lines a snippet from this file needs (C#: using + namespace)
---  is_import(line) -> boolean          is this a header/import line (also directives such as #:)
---  sort_imports(lines) -> lines        order import lines after `=p` adds some (C#: System first)
---  adapt(lines, node_type) -> lines, note|nil
---                                      make sent code work on its own (C#: method -> local function)
---  insert_at(pad_lines) -> index       0-based line to insert new code at (C#: before type declarations)
---  treesitter                          parser language when it differs from the filetype (C#: c_sharp)
---  comment                             comment format when 'commentstring' isn't wanted (C#: "// %s")
---Pads
---  kind                                "notes" | "code" | "db" (badge, border color); default "code"
---  run                                 run spec for the generic runner (ScratchManagerRunSpec)
---  keys(config) -> table|nil           extra snacks window keys for the pad (DB pads: run/connection)
---  on_open(bufnr, config)              called once when a pad of this filetype opens
---Help and health
---  help(info, helpers) -> blocks       `=h` content (see help.lua for blocks and helpers)
---  help_info(bufnr, config) -> table   pad details merged into the help info (C#: project)
---  health(report, config)              `:checkhealth` lines (report.ok / warn / info)
---
---`config` is the language's `run.<ft>` table from the setup options.

local M = {}

---@class ScratchManagerRunSpec
---@field cmd fun(config: table): string[] Command; the work file path is appended
---@field file string Work file name, e.g. "scratch.py"
---@field title? string Output title, e.g. "dotnet run" (default: the command name)
---@field desc? string Key description in the pad footer (default: "Run")
---@field inline? boolean Output may contain inline value markers ("\30<line>\31<text>")
---@field missing? fun(cmd: string[]): string Message when the command isn't installed
---@field prepare? fun(ctx: table): string[], string[]|nil, string|nil Build the work file lines,
---  details shown in the output, and a placeholder while running. ctx: bufnr, pad_lines, range,
---  config, scope(extra). Default: the pad (or selected) lines as they are.
---@field hide_line? fun(line: string): boolean Output noise to hide (counted as "warnings hidden")

---@class ScratchManagerLanguage
---@field imports? fun(source_lines: string[]): string[]
---@field is_import? fun(line: string): boolean
---@field sort_imports? fun(lines: string[]): string[]
---@field adapt? fun(lines: string[], node_type: string|nil): string[], string|nil
---@field insert_at? fun(pad_lines: string[]): number
---@field treesitter? string
---@field comment? string
---@field kind? "notes"|"code"|"db"
---@field run? ScratchManagerRunSpec
---@field keys? fun(config: table): table|nil
---@field on_open? fun(bufnr: number, config: table)
---@field help? fun(info: table, helpers: table): table[]
---@field help_info? fun(bufnr: number, config: table): table
---@field health? fun(report: table, config: table)

-- Profiles that ship with the plugin (also the order of health check sections)
local BUILTIN = { "cs", "sql", "lua", "markdown" }

---@type ScratchManagerLanguage
local defaults = {
	kind = "code",
	imports = function()
		return {}
	end,
	is_import = function()
		return false
	end,
	adapt = function(lines)
		return lines, nil
	end,
	insert_at = function(pad_lines)
		return #pad_lines
	end,
}

local registered, cache = {}, {}

---Profile for a filetype, with defaults for the fields it doesn't define
---@param ft string
---@return ScratchManagerLanguage
function M.get(ft)
	ft = ft or ""
	if cache[ft] == nil then
		local profile = registered[ft]
		if not profile and ft ~= "" then
			local ok, mod = pcall(require, "scratch-manager.languages." .. ft)
			profile = ok and type(mod) == "table" and mod or nil
		end
		cache[ft] = setmetatable(profile or {}, { __index = defaults })
	end
	return cache[ft]
end

---Add or override a language profile, e.g. from your config:
---`require("scratch-manager.languages").register("python", { run = { cmd = ..., file = "scratch.py" } })`
---@param ft string
---@param profile ScratchManagerLanguage
function M.register(ft, profile)
	registered[ft] = profile
	cache[ft] = nil
end

---Filetypes with a profile (built-in and registered)
---@return string[]
function M.known()
	local out, seen = {}, {}
	for _, ft in ipairs(BUILTIN) do
		table.insert(out, ft)
		seen[ft] = true
	end
	for ft in pairs(registered) do
		if not seen[ft] then
			table.insert(out, ft)
		end
	end
	return out
end

return M
