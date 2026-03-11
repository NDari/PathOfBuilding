-- cspell:words LÖVE cext cdef
-- shim/subscript.lua
-- LaunchSubScript implementation using love.thread
-- Sub-scripts run in separate Lua states (threads) with IPC via channels.

local M = {}

local nextScriptId = 1
local activeScripts = {}  -- id → { thread, resultChannel, logChannel, running }

-- Thread wrapper code template
-- This gets prepended to each sub-script's scriptText.
-- It sets up the environment and runs the script.
local THREAD_WRAPPER = [==[
-- Sub-script thread wrapper
local SCRIPT_ID = ...
local args = { select(2, ...) }

-- Set up channels
local resultChannel = love.thread.getChannel("result_" .. SCRIPT_ID)
local logChannel = love.thread.getChannel("log_" .. SCRIPT_ID)

-- Inject funcList globals (static values pre-computed by main thread)
%s

-- Inject subList functions (send messages back to main thread via log channel)
%s

-- Set up package paths to find C modules and pure Lua libs
local loveSource = love.filesystem.getSource()
local _ffi = require("ffi")
if _ffi.os == "Windows" then
	pcall(_ffi.cdef, [[char *_fullpath(char *absPath, const char *relPath, size_t maxLength);]])
else
	pcall(_ffi.cdef, [[char *realpath(const char *path, char *resolved_path);]])
end
local function _resolvePath(path)
	if _ffi.os == "Windows" then
		local buf = _ffi.new("char[?]", 1024)
		local result = _ffi.C._fullpath(buf, path, 1024)
		if result ~= nil then return _ffi.string(buf):gsub("\\", "/") end
	else
		local buf = _ffi.new("char[?]", 4096)
		local result = _ffi.C.realpath(path, buf)
		if result ~= nil then return _ffi.string(buf) end
	end
	return path
end
local baseDir = _resolvePath(loveSource .. "/..")
local srcPath = baseDir .. "/src"
local libPath = loveSource .. "/lib"
local runtimeLuaPath = baseDir .. "/runtime/lua"

package.path = libPath .. "/?.lua;"
	.. libPath .. "/?/init.lua;"
	.. runtimeLuaPath .. "/?.lua;"
	.. runtimeLuaPath .. "/?/init.lua;"
	.. srcPath .. "/?.lua;"
	.. package.path

-- Ensure require can find C modules (lcurl, etc.)
local _cext = (jit.os == "Windows") and "dll" or "so"
package.cpath = libPath .. "/?." .. _cext .. ";"
	.. libPath .. "/?/?." .. _cext .. ";"
	.. package.cpath

-- Provide a real MakeDir implementation (funcList captures a no-op since MakeDir returns nil)
local _isWindows = (jit.os == "Windows")
MakeDir = function(path)
	if _isWindows then
		-- Use CreateDirectoryA via FFI to avoid console window popup
		pcall(_ffi.cdef, 'int CreateDirectoryA(const char*, void*); unsigned long GetFileAttributesA(const char*);')
		local winPath = path:gsub("/", "\\")
		-- Create parent directories if needed
		local parent = winPath:match("^(.+)\\[^\\]+\\?$")
		if parent and _ffi.C.GetFileAttributesA(parent) == 0xFFFFFFFF then
			MakeDir(parent)
		end
		_ffi.C.CreateDirectoryA(winPath, nil)
	else
		os.execute('mkdir -p "' .. path .. '"')
	end
end

-- Run the actual script
local scriptFunc, loadErr = loadstring(%q)
if not scriptFunc then
	resultChannel:push({ ok = false, err = "Failed to load sub-script: " .. tostring(loadErr) })
	return
end

local results = { pcall(scriptFunc, unpack(args)) }
if results[1] then
	table.remove(results, 1)
	resultChannel:push({ ok = true, results = results })
else
	resultChannel:push({ ok = false, err = results[2] })
end
]==]

-- Build the funcList injection code
-- funcList functions return static values from the main thread
local function buildFuncListCode(funcList)
	if not funcList or funcList == "" then return "" end
	local lines = {}
	for name in funcList:gmatch("[^,]+") do
		name = name:match("^%s*(.-)%s*$")  -- trim
		if name ~= "" then
			-- Get the current return value and inject it as a constant
			local fn = _G[name]
			if fn then
				local results = { pcall(fn) }
				if results[1] then
					table.remove(results, 1)
					-- Build a function that returns these values
					local valStrs = {}
					for i, v in ipairs(results) do
						if type(v) == "string" then
							valStrs[i] = string.format("%q", v)
						elseif type(v) == "number" then
							valStrs[i] = tostring(v)
						elseif type(v) == "boolean" then
							valStrs[i] = tostring(v)
						elseif v == nil then
							valStrs[i] = "nil"
						else
							valStrs[i] = "nil"
						end
					end
					lines[#lines + 1] = string.format(
						"%s = function() return %s end",
						name, table.concat(valStrs, ", ")
					)
				else
					lines[#lines + 1] = string.format("%s = function() end", name)
				end
			else
				lines[#lines + 1] = string.format("%s = function() end", name)
			end
		end
	end
	return table.concat(lines, "\n")
end

-- Build the subList injection code
-- subList functions send messages back to main thread
local function buildSubListCode(subList, scriptId)
	if not subList or subList == "" then return "" end
	local lines = {}
	for name in subList:gmatch("[^,]+") do
		name = name:match("^%s*(.-)%s*$")  -- trim
		if name ~= "" then
			lines[#lines + 1] = string.format(
				'%s = function(...) logChannel:push({ func = %q, args = {...} }) end',
				name, name
			)
		end
	end
	return table.concat(lines, "\n")
end

function M.inject(runCallback)
	function LaunchSubScript(scriptText, funcList, subList, ...)
		local id = nextScriptId
		nextScriptId = nextScriptId + 1

		local funcCode = buildFuncListCode(funcList)
		local subCode = buildSubListCode(subList, id)

		-- Build the full thread code
		local threadCode = string.format(THREAD_WRAPPER, funcCode, subCode, scriptText)

		-- Create the thread
		local thread = love.thread.newThread(threadCode)
		local resultChannel = love.thread.getChannel("result_" .. id)
		local logChannel = love.thread.getChannel("log_" .. id)

		-- Store script info
		activeScripts[id] = {
			thread = thread,
			resultChannel = resultChannel,
			logChannel = logChannel,
			running = true,
		}

		-- Start the thread with id + varargs
		local extraArgs = { ... }
		thread:start(id, unpack(extraArgs))

		return id
	end

	function AbortSubScript(ssID)
		if activeScripts[ssID] then
			-- LÖVE threads can't be killed; mark as inactive
			activeScripts[ssID].running = false
			activeScripts[ssID] = nil
		end
	end

	function IsSubScriptRunning(ssID)
		if activeScripts[ssID] then
			return activeScripts[ssID].thread:isRunning()
		end
		return false
	end
end

function M.pollSubScripts()
	for id, script in pairs(activeScripts) do
		if not script.running then
			goto continue
		end

		-- Check for log messages (subList function calls)
		while true do
			local msg = script.logChannel:pop()
			if not msg then break end
			if msg.func and msg.args then
				-- Forward to mainObject:OnSubCall
				local mainObject = _G.mainObject_ref
				if mainObject and mainObject.OnSubCall then
					pcall(mainObject.OnSubCall, mainObject, msg.func, unpack(msg.args))
				end
			end
		end

		-- Check for thread completion
		local result = script.resultChannel:pop()
		if result then
			script.running = false
			local mainObject = _G.mainObject_ref
			if mainObject then
				if result.ok then
					if mainObject.OnSubFinished then
						pcall(mainObject.OnSubFinished, mainObject, id, unpack(result.results or {}))
					end
				else
					if mainObject.OnSubError then
						pcall(mainObject.OnSubError, mainObject, id, result.err)
					end
				end
			end
			activeScripts[id] = nil
		elseif not script.thread:isRunning() then
			-- Thread stopped without pushing a result — check for error
			local err = script.thread:getError()
			script.running = false
			local mainObject = _G.mainObject_ref
			if mainObject and mainObject.OnSubError then
				pcall(mainObject.OnSubError, mainObject, id, err or "Sub-script thread stopped unexpectedly")
			end
			activeScripts[id] = nil
		end

		::continue::
	end
end

return M
