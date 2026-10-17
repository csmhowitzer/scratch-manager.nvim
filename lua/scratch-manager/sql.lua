---Run SQL (DB) scratch pads through a pluggable provider
---
---scratch-manager never depends on a database plugin. A provider is a table:
---  name         string                                    shown in messages
---  available()  -> boolean                                is the backing plugin installed/set up?
---  connections() -> { name: string, ... }[]               connections to pick from
---  execute(connection, query, bufnr)                      run the query and show results
---  attach(connection, bufnr)   (optional)                 e.g. enable completion in the pad
---Built-in providers live in scratch-manager.providers.<name> and are only loaded on use.

local M = {}

---@class ScratchManagerSqlProvider
---@field name string
---@field available fun(): boolean
---@field connections fun(): table[]
---@field execute fun(connection: table, query: string, bufnr: number)
---@field attach? fun(connection: table, bufnr: number) Optional: connection-aware features (completion)

---@class ScratchManagerSqlConfig
---@field enabled boolean Bind <CR> in SQL pads to run them (default: true)
---@field provider string|ScratchManagerSqlProvider|false Built-in provider name or a provider table (default: "enhance")
---@field close_pad boolean Close the pad when running so results get the full width (default: true)

---Resolve the configured provider (built-in name or custom table)
---@param config ScratchManagerSqlConfig|nil
---@return ScratchManagerSqlProvider|nil provider
---@return string|nil err Why there is no provider
function M.get_provider(config)
	config = config or {}
	local provider = config.provider
	if provider == nil then
		provider = "enhance"
	end
	if provider == false then
		return nil, "SQL provider disabled (run.sql.provider = false)"
	end
	if type(provider) == "string" then
		local ok, mod = pcall(require, "scratch-manager.providers." .. provider)
		if not ok then
			if tostring(mod):find("module 'scratch%-manager%.providers%." .. vim.pesc(provider) .. "' not found") then
				return nil, "Unknown SQL provider: " .. provider
			end
			return nil, "Failed to load SQL provider " .. provider .. ": " .. tostring(mod)
		end
		provider = mod
	end
	if type(provider) ~= "table" or type(provider.execute) ~= "function" then
		return nil, "Invalid SQL provider (needs available/connections/execute)"
	end
	if provider.available and not provider.available() then
		return nil, (provider.name or "SQL provider") .. " is not available (is the plugin installed and set up?)"
	end
	return provider
end

-- Remembered connection per pad: pad file -> connection name
local store = require("scratch-manager.store")
local STORE = "sql_connections"

---Connection name remembered for a pad file
---@param pad_file string
---@return string|nil
function M.get_connection_name(pad_file)
	return store.get(STORE, pad_file)
end

---Remember the connection for a pad file
---@param pad_file string
---@param name string|nil nil forgets it
function M.set_connection_name(pad_file, name)
	store.set(STORE, pad_file, name)
end

---Let the provider make the pad connection-aware (completion), if it supports that
---@param provider ScratchManagerSqlProvider
---@param connection table
---@param bufnr number
local function attach(provider, connection, bufnr)
	if provider.attach and vim.api.nvim_buf_is_valid(bufnr) then
		local ok, err = pcall(provider.attach, connection, bufnr)
		if not ok then
			vim.notify((provider.name or "SQL provider") .. ": attach failed: " .. tostring(err), vim.log.levels.WARN)
		end
	end
end

---Ask for a connection and remember it for the pad
---@param provider ScratchManagerSqlProvider
---@param pad_file string
---@param on_choice fun(connection: table|nil)
function M.pick_connection(provider, pad_file, on_choice)
	local connections = provider.connections and provider.connections() or {}
	if #connections == 0 then
		vim.notify(provider.name .. ": no connections configured", vim.log.levels.WARN)
		on_choice(nil)
		return
	end
	vim.ui.select(connections, {
		prompt = "Run DB pad on which connection?",
		format_item = function(conn)
			return conn.name .. (conn.type and (" (" .. conn.type .. ")") or "")
		end,
	}, function(conn)
		if conn then
			M.set_connection_name(pad_file, conn.name)
		end
		on_choice(conn)
	end)
end

---Find the remembered connection for a pad, if it still exists
---@param provider ScratchManagerSqlProvider
---@param pad_file string
---@return table|nil
local function remembered_connection(provider, pad_file)
	local name = M.get_connection_name(pad_file)
	if not name then
		return nil
	end
	for _, conn in ipairs(provider.connections and provider.connections() or {}) do
		if conn.name == name then
			return conn
		end
	end
	return nil
end

---Called when a DB pad is opened: attach its remembered connection (completion). Quiet when
---there is no provider or no remembered connection yet.
---@param bufnr number Pad buffer
---@param config ScratchManagerSqlConfig|nil
function M.attach_pad(bufnr, config)
	config = config or {}
	if config.enabled == false then
		return
	end
	local provider = M.get_provider(config)
	if not provider then
		return
	end
	local conn = remembered_connection(provider, vim.api.nvim_buf_get_name(bufnr))
	if conn then
		attach(provider, conn, bufnr)
	end
end

---Lines to run: the visual selection when called from visual mode, otherwise the whole buffer
---@param bufnr number
---@return string
local function query_text(bufnr)
	local mode = vim.fn.mode()
	local lines
	if mode == "v" or mode == "V" or mode == "\22" then
		local first, last = vim.fn.line("v"), vim.fn.line(".")
		if first > last then
			first, last = last, first
		end
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
		lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
	else
		lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	end
	return table.concat(lines, "\n")
end

---Run a DB pad: use its remembered connection (or ask), then hand the query to the provider
---@param bufnr number Pad buffer
---@param config ScratchManagerSqlConfig|nil
function M.run(bufnr, config)
	config = config or {}
	local provider, err = M.get_provider(config)
	if not provider then
		vim.notify(err .. ". Set run.sql.provider to run DB pads.", vim.log.levels.WARN)
		return
	end
	local query = query_text(bufnr)
	if vim.trim(query) == "" then
		vim.notify("Nothing to run", vim.log.levels.WARN)
		return
	end
	local pad_file = vim.api.nvim_buf_get_name(bufnr)

	local function execute(conn)
		if not conn then
			return
		end
		attach(provider, conn, bufnr) -- first pick: completion from now on
		local pad_win = vim.fn.bufwinid(bufnr)
		if config.close_pad ~= false and pad_win ~= -1 then
			-- Results usually open in a split; closing the (already saved) pad gives them the width
			pcall(vim.api.nvim_win_close, pad_win, false)
		end
		provider.execute(conn, query, bufnr)
	end

	local conn = remembered_connection(provider, pad_file)
	if conn then
		execute(conn)
	else
		M.pick_connection(provider, pad_file, execute)
	end
end

---Change the connection a DB pad runs on
---@param bufnr number Pad buffer
---@param config ScratchManagerSqlConfig|nil
function M.choose_connection(bufnr, config)
	local provider, err = M.get_provider(config)
	if not provider then
		vim.notify(err, vim.log.levels.WARN)
		return
	end
	M.pick_connection(provider, vim.api.nvim_buf_get_name(bufnr), function(conn)
		if conn then
			attach(provider, conn, bufnr)
			vim.notify("DB pad now runs on " .. conn.name, vim.log.levels.INFO)
		end
	end)
end

---Snacks window key specs for DB pads
---@param config ScratchManagerSqlConfig|nil
---@return table keys
function M.keys(config)
	return {
		run = {
			"<cr>",
			function(self)
				M.run(self.buf, config)
			end,
			desc = "Run query",
			mode = { "n", "x" },
		},
		connection = {
			"<leader>dc",
			function(self)
				M.choose_connection(self.buf, config)
			end,
			desc = "Connection",
		},
	}
end

return M
