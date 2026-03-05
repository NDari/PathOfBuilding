-- cspell:words LÖVE
-- LOVE entry point for Path of Building
-- Custom love.run() that mirrors SimpleGraphic's callback model

-- Resolve paths:
-- Dev mode (love .): loveSource is the love/ directory, sibling of src/
-- Distribution (love-runtime/love love): loveSource is the love/ game directory, sibling of src/
-- Both cases: love/ is alongside src/, so baseDir is always one level up.
local loveSource = love.filesystem.getSource()
local baseDir = loveSource .. "/.."
local srcPath = baseDir .. "/src"

-- Initialize the shim layer (injects all SimpleGraphic globals into _G)
local shimPath = loveSource .. "/shim"
package.path = shimPath .. "/?.lua;" .. package.path

local shim = require("shim")
shim.init(loveSource, srcPath, baseDir)

function love.run()
	-- Change working directory to src/ so PoB's relative paths work
	love.filesystem.setIdentity("PathOfBuilding")
	local ok, err = pcall(function()
		-- Use os-level chdir so loadfile/dofile/io.open work with relative paths
		local lfs = love.filesystem
		-- We need the real filesystem, not LÖVE's virtual one
		require("shim.compat").chdir(srcPath)
	end)
	if not ok then
		print("Warning: could not chdir to src/: " .. tostring(err))
	end

	love.timer.step()

	-- Load PoB's entry point
	local launchOk, launchErr = pcall(function()
		LoadModule("Launch")
	end)
	if not launchOk then
		print("Error loading Launch.lua: " .. tostring(launchErr))
		love.window.showMessageBox("Error", "Failed to load Launch.lua:\n" .. tostring(launchErr), "error")
		return function() return 1 end
	end

	-- Trigger PoB initialization
	shim.runCallback("OnInit")

	-- Main loop
	return function()
		-- Process LÖVE events
		love.event.pump()
		for name, a, b, c, d, e, f in love.event.poll() do
			if name == "quit" then
				local canExit = shim.runCallback("CanExit")
				if canExit ~= false then
					shim.runCallback("OnExit")
					return a or 0
				end
			end
			shim.handleEvent(name, a, b, c, d, e, f)
		end

		-- Poll sub-script channels
		shim.pollSubScripts()

		-- Update timer
		love.timer.step()

		-- Call PoB's frame handler
		shim.runCallback("OnFrame")

		-- Render: execute the collected draw commands
		love.graphics.origin()
		love.graphics.clear(shim.getClearColor())
		shim.executeDrawCommands()
		love.graphics.present()

		-- Yield to avoid pegging the CPU
		love.timer.sleep(0.001)
	end
end
