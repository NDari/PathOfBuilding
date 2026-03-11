-- cspell:words cdef STARTUPINFOA PROCESSINFO lpReserved lpDesktop lpTitle dwFlags
-- cspell:words wShowWindow hStdInput hStdOutput hStdError hProcess hThread
-- win32.lua
-- Windows-specific utilities to avoid console window popups.
-- On Windows, os.execute() and io.popen() spawn cmd.exe which briefly shows
-- a visible console window. This module uses CreateProcessA with the
-- CREATE_NO_WINDOW flag to run commands invisibly.
--
-- On non-Windows systems, this module is a thin wrapper around standard Lua.

local ffi = require("ffi")

local M = {}

if ffi.os ~= "Windows" then
	function M.executeNoWindow(cmd)
		os.execute(cmd)
	end

	function M.spawnNoWindow(cmd)
		os.execute(cmd .. " &")
	end

	function M.createDir(path)
		os.execute('mkdir -p "' .. path .. '"')
	end

	return M
end

-- Windows: use CreateProcessA with CREATE_NO_WINDOW
pcall(ffi.cdef, [[
	typedef struct {
		unsigned long cb;
		char* lpReserved;
		char* lpDesktop;
		char* lpTitle;
		unsigned long dwX, dwY, dwXSize, dwYSize;
		unsigned long dwXCountChars, dwYCountChars;
		unsigned long dwFillAttribute;
		unsigned long dwFlags;
		unsigned short wShowWindow;
		unsigned short cbReserved2;
		void* lpReserved2;
		void* hStdInput;
		void* hStdOutput;
		void* hStdError;
	} POB_STARTUPINFOA;

	typedef struct {
		void* hProcess;
		void* hThread;
		unsigned long dwProcessId;
		unsigned long dwThreadId;
	} POB_PROCESSINFO;

	int CreateProcessA(
		const char* lpApplicationName,
		char* lpCommandLine,
		void* lpProcessAttributes,
		void* lpThreadAttributes,
		int bInheritHandles,
		unsigned long dwCreationFlags,
		void* lpEnvironment,
		const char* lpCurrentDirectory,
		POB_STARTUPINFOA* lpStartupInfo,
		POB_PROCESSINFO* lpProcessInformation
	);
	unsigned long WaitForSingleObject(void* hHandle, unsigned long dwMilliseconds);
	int CloseHandle(void* hObject);
	int CreateDirectoryA(const char* lpPathName, void* lpSecurityAttributes);
	unsigned long GetFileAttributesA(const char* lpFileName);
]])

local CREATE_NO_WINDOW = 0x08000000
local INFINITE = 0xFFFFFFFF

--- Run a shell command without showing a console window, waiting for completion.
function M.executeNoWindow(cmd)
	local si = ffi.new("POB_STARTUPINFOA")
	si.cb = ffi.sizeof("POB_STARTUPINFOA")
	local pi = ffi.new("POB_PROCESSINFO")

	local cmdLine = 'cmd.exe /c ' .. cmd
	local buf = ffi.new("char[?]", #cmdLine + 1, cmdLine)

	local ok = ffi.C.CreateProcessA(nil, buf, nil, nil, 0, CREATE_NO_WINDOW, nil, nil, si, pi)
	if ok ~= 0 then
		ffi.C.WaitForSingleObject(pi.hProcess, INFINITE)
		ffi.C.CloseHandle(pi.hProcess)
		ffi.C.CloseHandle(pi.hThread)
	end
end

--- Launch a command without showing a console window, without waiting.
function M.spawnNoWindow(cmd)
	local si = ffi.new("POB_STARTUPINFOA")
	si.cb = ffi.sizeof("POB_STARTUPINFOA")
	local pi = ffi.new("POB_PROCESSINFO")

	local cmdLine = 'cmd.exe /c ' .. cmd
	local buf = ffi.new("char[?]", #cmdLine + 1, cmdLine)

	local ok = ffi.C.CreateProcessA(nil, buf, nil, nil, 0, CREATE_NO_WINDOW, nil, nil, si, pi)
	if ok ~= 0 then
		ffi.C.CloseHandle(pi.hProcess)
		ffi.C.CloseHandle(pi.hThread)
	end
end

--- Create a directory (and parent directories if needed).
function M.createDir(path)
	local winPath = path:gsub("/", "\\")
	-- Recursively create parent directories (like cmd's mkdir)
	local parent = winPath:match("^(.+)\\[^\\]+\\?$")
	if parent then
		local attrs = ffi.C.GetFileAttributesA(parent)
		if attrs == 0xFFFFFFFF then -- INVALID_FILE_ATTRIBUTES
			M.createDir(parent)
		end
	end
	ffi.C.CreateDirectoryA(winPath, nil)
end

return M
