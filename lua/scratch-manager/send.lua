---Send code from a source file into its code pad (`=p`)
---
---Visual mode sends the selected lines; normal mode sends the function/method under the cursor
---(Treesitter), or the current line. The code is added to the file's code pad under a
---"from file:lines" comment, with indentation cleaned up. Language-specific steps (bringing the
---file's imports along, adapting a method so it runs standalone, where code may go) come from the
---language profiles in scratch-manager.languages, so this module stays language-neutral.

local languages = require("scratch-manager.languages")

local M = {}

---Is a Treesitter node a function/method definition (not a call)?
---@param type string
---@return boolean
local function is_function_node(type)
	if type:match("call") or type:match("invocation") then
		return false
	end
	return (type:match("function") or type:match("method"))
			and (type:match("_declaration$") or type:match("_definition$") or type:match("_statement$")
				or type:match("_item$") or type:match("^function$"))
		~= nil
end

---Range to send: the visual selection, else the function under the cursor, else the current line
---@param bufnr number Source buffer
---@param range { first: number, last: number }|nil Visual selection (1-based, inclusive)
---@return { first: number, last: number, node_type: string|nil }
function M.target_range(bufnr, range)
	if range then
		return { first = range.first, last = range.last }
	end
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local lang = languages.get(vim.bo[bufnr].filetype).treesitter
	local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row - 1, vim.fn.col(".") - 1 }, lang = lang })
	while ok and node do
		if is_function_node(node:type()) then
			local start_row, _, end_row = node:range()
			return { first = start_row + 1, last = end_row + 1, node_type = node:type() }
		end
		node = node:parent()
	end
	return { first = row, last = row }
end

---Remove the indentation the lines have in common
---@param lines string[]
---@return string[]
function M.dedent(lines)
	local indent
	for _, line in ipairs(lines) do
		if line:match("%S") then
			local this = #line:match("^%s*")
			indent = indent and math.min(indent, this) or this
		end
	end
	if not indent or indent == 0 then
		return lines
	end
	return vim.tbl_map(function(line)
		return line:sub(indent + 1)
	end, lines)
end

---Comment line in a filetype ('commentstring'; `// %s` when unknown)
---@param ft string
---@param text string
---@return string
function M.comment(ft, text)
	local cs = languages.get(ft).comment
	if not cs then
		local ok, option = pcall(vim.filetype.get_option, ft, "commentstring")
		cs = ok and type(option) == "string" and option:find("%s", 1, true) and option or "// %s"
	end
	return vim.trim((cs:gsub("%%s", text, 1)))
end

---Build the lines to add to a pad, and the import lines they need
---@param source_bufnr number
---@param range { first: number, last: number, node_type: string|nil }
---@param ft string Pad filetype
---@return string[] block
---@return string[] imports
function M.build(source_bufnr, range, ft)
	local lang = languages.get(ft)
	local source_lines = vim.api.nvim_buf_get_lines(source_bufnr, 0, -1, false)
	local code = M.dedent(vim.list_slice(source_lines, range.first, range.last))
	local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(source_bufnr), ":t")
	local where = range.first == range.last and ("%s:%d"):format(name, range.first)
		or ("%s:%d–%d"):format(name, range.first, range.last)
	local block = { M.comment(ft, "from " .. where) }
	local note
	code, note = lang.adapt(code, range.node_type)
	if note then
		table.insert(block, M.comment(ft, note))
	end
	return vim.list_extend(block, code), lang.imports(source_lines)
end

---Add a block (and the imports the pad is missing) to a pad buffer
---@param pad_bufnr number
---@param block string[]
---@param imports string[]
---@param ft string
---@return number lnum 1-based line of the block's first line
---@return number added Number of import lines added
function M.insert(pad_bufnr, block, imports, ft)
	local lang = languages.get(ft)
	local lines = vim.api.nvim_buf_get_lines(pad_bufnr, 0, -1, false)
	local empty = #lines == 0 or (#lines == 1 and lines[1] == "")

	local present, missing = {}, {}
	for _, line in ipairs(lines) do
		present[vim.trim(line)] = true
	end
	for _, line in ipairs(imports) do
		if not present[line] then
			table.insert(missing, line)
		end
	end

	if empty then
		if lang.sort_imports then
			missing = lang.sort_imports(missing)
		end
		local new = vim.list_extend(vim.deepcopy(missing), #missing > 0 and { "" } or {})
		vim.list_extend(new, block)
		vim.api.nvim_buf_set_lines(pad_bufnr, 0, -1, false, new)
		return #missing > 0 and #missing + 2 or 1, #missing
	end

	-- Missing imports join the pad's import header; with a sort_imports hook the header's imports
	-- are put in order (directives such as #: stay first)
	if #missing > 0 then
		local header_end = 0
		for i, line in ipairs(lines) do
			if lang.is_import(line) then
				header_end = i
			elseif line:match("%S") then
				break
			end
		end
		local header = vim.list_slice(lines, 1, header_end)
		vim.list_extend(header, missing)
		if lang.sort_imports then
			local directives, imports = {}, {}
			for _, line in ipairs(header) do
				if line:match("^%s*#[:!]") then
					table.insert(directives, line)
				elseif line:match("%S") then
					table.insert(imports, line)
				end
			end
			header = vim.list_extend(directives, lang.sort_imports(imports))
		end
		vim.api.nvim_buf_set_lines(pad_bufnr, 0, header_end, false, header)
		lines = vim.api.nvim_buf_get_lines(pad_bufnr, 0, -1, false)
	end

	local at = lang.insert_at(lines)
	local chunk = vim.deepcopy(block)
	if at > 0 and lines[at] and lines[at]:match("%S") then
		table.insert(chunk, 1, "")
	end
	if lines[at + 1] and lines[at + 1]:match("%S") then
		table.insert(chunk, "")
	end
	vim.api.nvim_buf_set_lines(pad_bufnr, at, at, false, chunk)
	return at + (chunk[1] == "" and 2 or 1), #missing
end

-- Expose internals for testing
M._is_function_node = is_function_node

return M
