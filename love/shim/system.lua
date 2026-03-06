-- cspell:words LÖVE
-- shim/system.lua
-- System-level SimpleGraphic API functions: paths, time, clipboard, compression,
-- window management, module loading, console output, process management

local M = {}

local srcPath
local lovePath
local userPath
local isWindows = (jit.os == "Windows")

function M.init(loveSource, srcDir)
	lovePath = loveSource
	srcPath = srcDir

	if isWindows then
		-- Use APPDATA on Windows (e.g. C:/Users/Foo/AppData/Roaming)
		local appdata = os.getenv("APPDATA")
		if appdata then
			userPath = appdata:gsub("\\", "/")
		else
			userPath = lovePath
		end
	else
		-- Determine user data path (XDG on Linux, fallback to home)
		local xdgData = os.getenv("XDG_DATA_HOME")
		if xdgData then
			userPath = xdgData
		else
			local home = os.getenv("HOME")
			if home then
				userPath = home .. "/.local/share"
			else
				userPath = lovePath
			end
		end
	end
end

function M.inject()
	-- Time
	function GetTime()
		return love.timer.getTime() * 1000
	end

	-- Screen
	function GetScreenSize()
		return love.graphics.getDimensions()
	end

	function GetScreenScale()
		if love.window.getDPIScale then
			return love.window.getDPIScale()
		end
		return 1
	end

	function GetDPIScaleOverridePercent()
		return 0
	end

	function SetDPIScaleOverridePercent(scale)
		-- No-op on LÖVE; DPI handled by the window system
	end

	-- Window
	function SetWindowTitle(title)
		love.window.setTitle(title)
	end

	function SetClearColor(r, g, b, a)
		M._clearColor = { r or 0, g or 0, b or 0, a or 1 }
	end

	function RenderInit(...)
		-- No-op: LÖVE handles renderer init in conf.lua
	end

	-- Clipboard
	function Copy(text)
		love.system.setClipboardText(text)
	end

	function Paste()
		return love.system.getClipboardText()
	end

	-- Compression
	function Deflate(data)
		local ok, result = pcall(love.data.compress, "string", "zlib", data)
		if ok then return result end
		return ""
	end

	function Inflate(data)
		local ok, result = pcall(love.data.decompress, "string", "zlib", data)
		if ok then return result end
		return ""
	end

	-- URLs and processes
	function OpenURL(url)
		love.system.openURL(url)
	end

	function Restart()
		love.event.quit("restart")
	end

	function Exit()
		love.event.quit()
	end

	function TakeScreenshot()
		local filename = os.date("screenshot_%Y%m%d_%H%M%S.png")
		love.graphics.captureScreenshot(filename)
	end

	function SpawnProcess(cmd, args)
		if isWindows then
			local full = cmd or ""
			if args then full = full .. " " .. args end
			os.execute('start "" "' .. full .. '"')
		else
			if cmd and args then
				os.execute(cmd .. " " .. args .. " &")
			elseif cmd then
				os.execute(cmd .. " &")
			end
		end
	end

	-- Cursor
	function ShowCursor(doShow)
		love.mouse.setVisible(doShow)
	end

	function SetCursorPos(x, y)
		love.mouse.setPosition(x, y)
	end

	-- Paths
	function GetScriptPath()
		return srcPath
	end

	function GetRuntimePath()
		return lovePath
	end

	function GetUserPath()
		return userPath
	end

	function GetWorkDir()
		return srcPath
	end

	function SetWorkDir(path)
		-- No-op: we manage working directory at startup
	end

	function MakeDir(path)
		if isWindows then
			os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>NUL')
		else
			os.execute('mkdir -p "' .. path .. '"')
		end
	end

	function RemoveDir(path, recursive)
		if isWindows then
			local winPath = path:gsub("/", "\\")
			if recursive then
				os.execute('rmdir /s /q "' .. winPath .. '" 2>NUL')
			else
				os.execute('rmdir "' .. winPath .. '" 2>NUL')
			end
			-- Check if removal succeeded using dir
			local checkHandle = io.popen('dir "' .. winPath .. '" 2>NUL')
			if checkHandle then
				local result = checkHandle:read("*l")
				checkHandle:close()
				if result then
					return false, "Failed to remove: " .. path
				end
			end
			return true
		else
			if recursive then
				os.execute('rm -rf "' .. path .. '" 2>/dev/null')
			else
				os.execute('rmdir "' .. path .. '" 2>/dev/null')
			end
			-- Check if removal succeeded using stat (works for directories unlike io.open)
			local checkHandle = io.popen('stat "' .. path .. '" 2>/dev/null')
			if checkHandle then
				local result = checkHandle:read("*l")
				checkHandle:close()
				if result then
					return false, "Failed to remove: " .. path
				end
			end
			return true
		end
	end

	-- Platform detection
	function GetPlatform()
		local os_name = love.system.getOS()
		if os_name == "Linux" then return "linux"
		elseif os_name == "OS X" then return "macos"
		elseif os_name == "Windows" then return "windows"
		else return os_name:lower()
		end
	end

	-- Module loading
	function LoadModule(name, ...)
		local path = name
		if not path:match("%.lua$") then
			path = path .. ".lua"
		end
		local func, err = loadfile(path)
		if func then
			return func(...)
		else
			error("LoadModule() error loading '" .. path .. "': " .. err)
		end
	end

	function PLoadModule(name, ...)
		local path = name
		if not path:match("%.lua$") then
			path = path .. ".lua"
		end
		local func, err = loadfile(path)
		if func then
			return PCall(func, ...)
		else
			error("PLoadModule() error loading '" .. path .. "': " .. err)
		end
	end

	function PCall(func, ...)
		local ret = { pcall(func, ...) }
		if ret[1] then
			table.remove(ret, 1)
			return nil, unpack(ret)
		else
			return ret[2]
		end
	end

	-- Console
	function ConPrintf(fmt, ...)
		if select("#", ...) > 0 then
			print(string.format(fmt, ...))
		else
			print(fmt)
		end
	end

	function ConPrintTable(tbl, noRecurse)
		if type(tbl) ~= "table" then
			print(tostring(tbl))
			return
		end
		local function printTable(t, indent)
			for k, v in pairs(t) do
				if type(v) == "table" and not noRecurse then
					print(indent .. tostring(k) .. " = {")
					printTable(v, indent .. "  ")
					print(indent .. "}")
				else
					print(indent .. tostring(k) .. " = " .. tostring(v))
				end
			end
		end
		printTable(tbl, "")
	end

	function ConExecute(cmd)
		-- No-op: vid_mode/vid_resizable are handled in conf.lua
	end

	function ConClear()
		-- No-op
	end

	-- Profiling
	function SetProfiling(isEnabled)
		-- No-op or wire to lua-profiler if available
	end

	-- Cloud
	function GetCloudProvider(fullPath)
		return nil, nil, nil
	end

	-- Async loading count
	function GetAsyncCount()
		return 0
	end
end

function M.getClearColor()
	local c = M._clearColor
	if c then
		return c[1], c[2], c[3], c[4]
	end
	return 0, 0, 0, 1
end

M._clearColor = { 0, 0, 0, 1 }

return M
