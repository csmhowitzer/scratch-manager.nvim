-- Demo script to test custom selection UI
-- Run this in Neovim with: :luafile demo_selection.lua

print("🚀 Testing Custom Selection UI for scratch-manager.nvim")
print("=" .. string.rep("=", 50))

-- Load the scratch manager
local scratch_manager = require('scratch-manager')

-- Setup with default config
scratch_manager.setup()

print("✅ Scratch manager loaded successfully!")
print("📋 Available keymaps:")
print("   == : Toggle scratch buffer (markdown)")
print("   =c : Toggle scratch buffer (language-aware)")
print("   =s : Select scratch buffer (CUSTOM UI)")
print("   =d : Delete current scratch buffer")
print("")
print("🎯 To test the custom selection UI:")
print("   1. Create a few scratch buffers with '==' or '=c'")
print("   2. Press '=s' to see the new custom selection interface")
print("   3. Use j/k to navigate, Enter to select, Esc to cancel")
print("")
print("🌟 Features of the custom UI:")
print("   • Full column display (no truncation)")
print("   • Proper spacing and alignment")
print("   • Keyboard navigation")
print("   • No external dependencies")
print("   • Consistent experience across all environments")
