---Small persistent key/value stores for scratch-manager.nvim
---Each store is a JSON file in stdpath("data")/scratch-manager/<name>.json

local M = {}

---@param name string Store name
---@return string
function M.path(name)
	return vim.fn.stdpath("data") .. "/scratch-manager/" .. name .. ".json"
end

---Read a whole store
---@param name string
---@return table<string, any>
function M.read(name)
	local ok, lines = pcall(vim.fn.readfile, M.path(name))
	if not ok or #lines == 0 then
		return {}
	end
	local decoded_ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	return decoded_ok and type(data) == "table" and data or {}
end

---@param name string
---@param key string
---@return any
function M.get(name, key)
	return M.read(name)[key]
end

---Set (or with nil, remove) one key
---@param name string
---@param key string
---@param value any
function M.set(name, key, value)
	local data = M.read(name)
	data[key] = value
	local dir = vim.fn.fnamemodify(M.path(name), ":h")
	pcall(vim.fn.mkdir, dir, "p") -- tolerate another process creating it at the same time
	vim.fn.writefile({ vim.json.encode(data) }, M.path(name))
end

return M
