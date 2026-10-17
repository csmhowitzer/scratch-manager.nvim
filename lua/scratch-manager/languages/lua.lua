---Lua language profile (see languages/init.lua for the hooks)
---Lua pads run with snacks.nvim's own <CR> (inline results), so there is no run spec here.

local M = {}

---@param info ScratchManagerHelpInfo
---@param h table Help helpers (source_name, key)
---@return table[] blocks
function M.help(info, h)
	return {
		{ title = "Lua scratch pad · " .. h.source_name(info) },
		{ p = ("Lua for **%s**, run by snacks.nvim inside this Neovim."):format(h.source_name(info)) },
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

return M
