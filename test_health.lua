-- Simple test script to verify health check works
-- Run with: nvim --headless -l test_health.lua

-- Add current directory to package path
package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path

-- Load and run health check
local health = require('scratch-manager.health')
print("Health check module loaded successfully!")

-- Run the health check
health.check()
print("Health check completed!")
