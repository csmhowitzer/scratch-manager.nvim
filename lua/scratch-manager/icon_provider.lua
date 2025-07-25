---Icon provider for scratch-manager.nvim
---Follows oil.nvim's proven icon provider pattern with mini.icons → nvim-web-devicons → fallback
---Provides colored icons with highlight groups for enhanced visual experience

local M = {}

---@alias IconProvider fun(type: "file"|"directory", name: string, conf?: table): string, string?

---@class IconResult
---@field icon string The icon character
---@field hl string|nil Highlight group for coloring (nil for no color)

---Check for an icon provider and return a common icon provider API
---Follows oil.nvim's exact implementation pattern
---@return IconProvider|nil provider The icon provider function or nil if none available
function M.get_icon_provider()
  -- prefer mini.icons (oil.nvim's preferred choice)
  local _, mini_icons = pcall(require, "mini.icons")
  ---@diagnostic disable-next-line: undefined-field
  if _G.MiniIcons then -- `_G.MiniIcons` is a better check to see if the module is setup
    return function(type, name)
      return mini_icons.get(type == "directory" and "directory" or "file", name)
    end
  end

  -- fallback to `nvim-web-devicons` (oil.nvim's fallback)
  local has_devicons, devicons = pcall(require, "nvim-web-devicons")
  if has_devicons then
    return function(type, name, conf)
      if type == "directory" then
        return conf and conf.directory or "", "OilDirIcon"
      else
        local icon, hl = devicons.get_icon(name)
        icon = icon or (conf and conf.default_file or "")
        return icon, hl
      end
    end
  end

  -- No external provider available
  return nil
end

---Get icon with color support for a file
---@param filename string The filename to get icon for
---@param filetype string|nil Optional filetype hint
---@return IconResult result Icon and highlight group
function M.get_icon_with_color(filename, filetype)
  local provider = M.get_icon_provider()
  
  if provider then
    -- Use external provider (with colors)
    local icon, hl = provider("file", filename)
    return { icon = icon or "", hl = hl }
  else
    -- Fallback to current logic (no colors)
    return M.get_fallback_icon(filename, filetype)
  end
end

---Fallback to current simple icon logic
---Preserves existing behavior when no external providers available
---@param filename string The filename
---@param filetype string|nil Optional filetype
---@return IconResult result Simple icon with no color
function M.get_fallback_icon(filename, filetype)
  -- Import current icons.lua logic
  local current_icons = require("scratch-manager.icons")
  
  local icon
  if filetype then
    icon = current_icons.get_icon_for_filetype(filetype)
  else
    icon = current_icons.get_icon_for_file(filename)
  end
  
  return { icon = icon, hl = nil }
end

---Check if colored icons are available
---@return boolean has_colored_icons True if external icon provider with colors is available
function M.has_colored_icons()
  return M.get_icon_provider() ~= nil
end

---Get icon provider name for diagnostics
---@return string provider_name Name of the active provider or "fallback"
function M.get_provider_name()
  local _, mini_icons = pcall(require, "mini.icons")
  ---@diagnostic disable-next-line: undefined-field
  if _G.MiniIcons then
    return "mini.icons"
  end
  
  local has_devicons = pcall(require, "nvim-web-devicons")
  if has_devicons then
    return "nvim-web-devicons"
  end
  
  return "fallback"
end

-- Expose internal functions for testing (following established pattern)
M._get_icon_provider = M.get_icon_provider
M._get_fallback_icon = M.get_fallback_icon

return M
