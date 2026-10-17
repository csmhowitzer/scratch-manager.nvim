---Markdown language profile: notes pads (see languages/init.lua for the hooks)

local M = {}

M.kind = "notes"

---@param info ScratchManagerHelpInfo
---@param h table Help helpers (source_name, key)
---@return table[] blocks
function M.help(info, h)
	return {
		{ title = "Notes scratch pad · " .. h.source_name(info) },
		{ p = ("Markdown notes for **%s**. Long lines wrap (`<M-z>` toggles)."):format(h.source_name(info)) },
	}
end

return M
