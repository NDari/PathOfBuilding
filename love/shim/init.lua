-- cspell:words LÖVE filesearch cext
-- shim/init.lua
-- Master shim module: loads all sub-modules and injects SimpleGraphic API into _G.
-- This is the bridge between LÖVE and the SimpleGraphic API that PoB expects.

local M = {}

local system = require("shim.system")
local render = require("shim.render")
local text = require("shim.text")
local input = require("shim.input")
local image = require("shim.image")
local filesearch = require("shim.filesearch")
local subscript = require("shim.subscript")

-- Callback system (mirrors SimpleGraphic's callback model)
local callbackTable = {}
local mainObject = nil

function M.runCallback(name, ...)
	if callbackTable[name] then
		return callbackTable[name](...)
	elseif mainObject and mainObject[name] then
		return mainObject[name](mainObject, ...)
	end
end

function M.init(loveSource, srcPath, baseDir)
	-- loveSource: love/ game directory (both dev and distribution)
	-- srcPath:    path to src/ directory
	-- baseDir:    parent of src/, runtime/, love/

	-- Initialize sub-modules
	system.init(loveSource, srcPath)
	render.init()
	text.init(render, loveSource)
	input.init()

	-- Set up package paths for PoB's Lua modules and pure Lua libraries
	-- lib/ is always inside the love/ game directory (both dev and distribution)
	local libPath = loveSource .. "/lib"
	local runtimeLuaPath = baseDir .. "/runtime/lua"

	package.path = libPath .. "/?.lua;"
		.. libPath .. "/?/init.lua;"
		.. srcPath .. "/?.lua;"
		.. srcPath .. "/?/init.lua;"
		.. runtimeLuaPath .. "/?.lua;"
		.. runtimeLuaPath .. "/?/init.lua;"
		.. package.path

	-- Set up C library paths (lcurl.so/.dll, etc.)
	local cext = (jit.os == "Windows") and "dll" or "so"
	package.cpath = libPath .. "/?." .. cext .. ";"
		.. libPath .. "/?/?." .. cext .. ";"
		.. package.cpath

	-- Inject all SimpleGraphic globals into _G
	system.inject()
	render.inject()
	text.inject()
	input.inject(M.runCallback)
	image.inject()
	filesearch.inject()
	subscript.inject(M.runCallback)

	-- Inject callback system globals
	function SetCallback(name, func)
		callbackTable[name] = func
	end

	function GetCallback(name)
		return callbackTable[name]
	end

	function SetMainObject(obj)
		mainObject = obj
		-- Also store a reference for sub-scripts to access
		_G.mainObject_ref = obj
	end

	-- LÖVE frontend version tag (displayed in the main UI)
	_G.LOVE_VERSION_TAG = "love-v0.1.12"

	-- arg table expected by PoB (command line arguments)
	-- LÖVE strips its own args, pass through any remaining
	if not _G.arg then
		_G.arg = {}
	end
end

function M.handleEvent(name, a, b, c, d, e, f)
	input.handleEvent(M.runCallback, name, a, b, c, d, e, f)
end

function M.pollSubScripts()
	subscript.pollSubScripts()
end

function M.executeDrawCommands()
	render.executeDrawCommands()
end

function M.getClearColor()
	return system.getClearColor()
end

return M
