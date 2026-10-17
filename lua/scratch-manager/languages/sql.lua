---SQL language profile: DB pads (see languages/init.lua for the hooks)
---Running goes through a pluggable SQL provider (scratch-manager.sql), never a hard dependency.

local M = {}

M.kind = "db"

---Run and connection keys, when a provider is configured
---@param config table run.sql config
---@return table|nil
function M.keys(config)
	config = config or {}
	if config.enabled == false or config.provider == false then
		return nil
	end
	return require("scratch-manager.sql").keys(config)
end

---Attach the pad's remembered connection (e.g. completion)
---@param bufnr number
---@param config table run.sql config
function M.on_open(bufnr, config)
	require("scratch-manager.sql").attach_pad(bufnr, config)
end

---@param bufnr number
---@param config table run.sql config
---@return table
function M.help_info(bufnr, config)
	local sql = require("scratch-manager.sql")
	local provider = sql.get_provider(config)
	return {
		connection = sql.get_connection_name(vim.api.nvim_buf_get_name(bufnr)),
		provider = provider and provider.name or nil,
	}
end

---@param info ScratchManagerHelpInfo
---@param h table Help helpers (source_name, key)
---@return table[] blocks
function M.help(info, h)
	local blocks = {
		{ title = "DB scratch pad (SQL) · " .. h.source_name(info) },
		{ p = ("SQL for **%s**, run through **%s**."):format(h.source_name(info), info.provider or "no SQL provider") },
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

---@param report { ok: function, warn: function, info: function }
---@param config table run.sql config
function M.health(report, config)
	config = config or { provider = "enhance" }
	if config.enabled == false or config.provider == false then
		report.info("DB pads - running disabled (run.sql)")
		return
	end
	local provider, err = require("scratch-manager.sql").get_provider(config)
	if provider then
		report.ok("DB pads - SQL provider " .. provider.name .. " (" .. #(provider.connections() or {}) .. " connections)")
	else
		report.info("DB pads - " .. err .. " (optional: install enhance.nvim or set run.sql.provider)")
	end
end

return M
