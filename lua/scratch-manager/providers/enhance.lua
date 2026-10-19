---enhance.nvim SQL provider for DB scratch pads
---Loaded only when a DB pad is used; scratch-manager works without enhance.nvim installed.
---Prefers enhance's public API (`enhance.api`, which adds completion via attach) and falls back
---to the connection list and executor of older enhance versions. Pads are never registered as
---enhance query buffers, so they don't appear in enhance's explorer.

---@type ScratchManagerSqlProvider
local M = {
	name = "enhance.nvim",
}

---enhance's public API, when this enhance version has it
---@return table|nil
local function public_api()
	local ok, api = pcall(require, "enhance.api")
	if ok and type(api) == "table" and (api.version or 0) >= 1 then
		return api
	end
	return nil
end

function M.available()
	if public_api() then
		return true
	end
	local ok_conn, connections = pcall(require, "enhance.connections")
	local ok_exec, executor = pcall(require, "enhance.executor")
	return ok_conn and ok_exec and type(connections.get_connections) == "function"
		and type(executor.execute) == "function"
end

function M.connections()
	local api = public_api()
	if api then
		return api.connections()
	end
	return require("enhance.connections").get_connections() or {}
end

function M.execute(connection, query, bufnr)
	local api = public_api()
	if api then
		local ok, err = api.execute(query, { connection = connection, bufnr = bufnr })
		if not ok then
			vim.notify("enhance: " .. tostring(err), vim.log.levels.WARN)
		end
		return
	end
	require("enhance.executor").execute(connection, query, bufnr)
end

---Fill vim-dadbod-completion's table cache for the pad's connection now, while the pad is on screen.
---Otherwise its FileType handler fetches the tables (synchronously) the next time the pad is shown,
---and snacks sets the filetype before the pad has a window: the fetch then runs in Neovim's hidden
---autocmd window, which shows up borderless at the top-left with the pad's text until it's done.
---@param bufnr number
local function warm_completion(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].db and vim.fn.exists("*vim_dadbod_completion#fetch") == 1 then
		pcall(vim.fn["vim_dadbod_completion#fetch"], bufnr)
	end
end

---Table/column completion for the pad (SQL Server, via vim-dadbod-completion)
function M.attach(connection, bufnr)
	local api = public_api()
	if api and api.attach then
		api.attach(bufnr, connection)
		warm_completion(bufnr)
		return
	end
	-- Older enhance (e.g. the published version): same completion setup, without the public API
	local ok, completion = pcall(require, "enhance.completion")
	if ok and type(completion.setup) == "function" then
		completion.setup(bufnr, connection)
		warm_completion(bufnr)
	end
end

return M
