---Run C# scratch pads with `dotnet run <file>.cs` (file-based apps, .NET 10+)
---No .sln or .csproj needed; output is shown in a float over the bottom of the pad

local M = {}

---@class ScratchManagerRunConfig
---@field enabled boolean Bind <CR> in C# pads to run them (default: true)
---@field cmd string[] Command to run; the source file path is appended
---                    (default: { "dotnet", "run", "-p:PublishAot=false" })
---@field max_height number Maximum height of the output window (default: 15)

local output = {
	buf = nil,
	win = nil,
}

---Stable per-pad working directory, so dotnet can reuse its build cache between runs
---@param pad_file string Path of the scratch pad file
---@return string dir
function M.work_dir(pad_file)
	local key = vim.fn.sha256(pad_file):sub(1, 16)
	return vim.fn.stdpath("cache") .. "/scratch-manager/cs/" .. key
end

---Lines to run: the visual selection when called from visual mode, otherwise the whole buffer
---@param bufnr number
---@return string[]
local function source_lines(bufnr)
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		local first, last = vim.fn.line("v"), vim.fn.line(".")
		if first > last then
			first, last = last, first
		end
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
		return vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
	end
	return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
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
	vim.fn.writefile(source_lines(bufnr), file)
	table.insert(cmd, file)

	M.show_output({ "Running…" }, table.concat(cmd, " "):gsub(vim.pesc(file), "scratch.cs"), pad_win, max_height)
	local started = vim.uv.hrtime()
	vim.system(cmd, { cwd = dir, text = true }, function(result)
		vim.schedule(function()
			local text = (result.stdout or "") .. (result.stderr or "")
			local lines = vim.split(vim.trim(text), "\n", { plain = true })
			if #lines == 1 and lines[1] == "" then
				lines = {}
			end
			local ms = math.floor((vim.uv.hrtime() - started) / 1e6)
			local status = result.code == 0 and "ok" or ("exit " .. result.code)
			M.show_output(lines, ("dotnet run · %s · %dms"):format(status, ms), pad_win, max_height)
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

-- Expose internal state for testing
M._output = output

return M
