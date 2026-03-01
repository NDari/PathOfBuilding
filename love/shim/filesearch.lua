-- shim/filesearch.lua
-- NewFileSearch implementation using OS-level directory listing.
-- Returns an iterator object matching SimpleGraphic's file search handle API.

local M = {}

local ffi = require("ffi")
local isWindows = (ffi.os == "Windows")

if isWindows then
	ffi.cdef[[
		typedef unsigned long DWORD;
		typedef int BOOL;
		typedef void* HANDLE;
		typedef struct {
			DWORD dwFileAttributes;
			uint64_t ftCreationTime;
			uint64_t ftLastAccessTime;
			uint64_t ftLastWriteTime;
			DWORD nFileSizeHigh;
			DWORD nFileSizeLow;
			DWORD dwReserved0;
			DWORD dwReserved1;
			char cFileName[260];
			char cAlternateFileName[14];
		} WIN32_FIND_DATAA;

		HANDLE FindFirstFileA(const char* lpFileName, WIN32_FIND_DATAA* lpFindFileData);
		BOOL FindNextFileA(HANDLE hFindFile, WIN32_FIND_DATAA* lpFindFileData);
		BOOL FindClose(HANDLE hFindFile);
	]]
end

local INVALID_HANDLE_VALUE = ffi.cast("void*", -1)
local FILE_ATTRIBUTE_DIRECTORY = 0x10

-- Simple glob matching (supports * and ? wildcards)
local function globMatch(pattern, str)
	-- Escape lua pattern special chars except * and ?
	local luaPat = pattern:gsub("([%.%+%-%^%$%(%)%%])", "%%%1")
	luaPat = luaPat:gsub("%*", ".*")
	luaPat = luaPat:gsub("%?", ".")
	return str:match("^" .. luaPat .. "$") ~= nil
end

-- Split a path pattern into directory and glob parts
-- e.g. "builds/subfolder/*.xml" → "builds/subfolder/", "*.xml"
-- e.g. "Scripts/*.lua" → "Scripts/", "*.lua"
local function splitPattern(pattern)
	local dir, glob = pattern:match("^(.*/)(.*)")
	if not dir then
		-- No directory separator — pattern is just a glob in current dir
		return ".", pattern
	end
	return dir, glob
end

-- File search handle class
local FileSearchHandle = {}
FileSearchHandle.__index = FileSearchHandle

function FileSearchHandle:GetFileName()
	if self._entries and self._idx <= #self._entries then
		return self._entries[self._idx].name
	end
	return nil
end

function FileSearchHandle:GetFileSize()
	if self._entries and self._idx <= #self._entries then
		return self._entries[self._idx].size or 0
	end
	return 0
end

function FileSearchHandle:GetFileModifiedTime()
	if self._entries and self._idx <= #self._entries then
		return self._entries[self._idx].modtime or 0
	end
	return 0
end

function FileSearchHandle:NextFile()
	self._idx = self._idx + 1
	if self._entries and self._idx <= #self._entries then
		return true
	end
	return nil
end

-- List directory entries — platform-specific implementations
local listDirectory

if isWindows then
	-- Windows: use Win32 FindFirstFileA/FindNextFileA via FFI
	-- FILETIME epoch: 1601-01-01, Unix epoch: 1970-01-01
	-- Difference in 100-nanosecond intervals
	local EPOCH_DIFF = 116444736000000000ULL

	listDirectory = function(dir)
		local entries = {}
		local winDir = dir:gsub("/", "\\")
		-- Append \* to list all entries
		if winDir:sub(-1) ~= "\\" then
			winDir = winDir .. "\\"
		end
		winDir = winDir .. "*"

		local findData = ffi.new("WIN32_FIND_DATAA")
		local hFind = ffi.C.FindFirstFileA(winDir, findData)
		if hFind == INVALID_HANDLE_VALUE then
			return entries
		end

		repeat
			local name = ffi.string(findData.cFileName)
			if name ~= "." and name ~= ".." then
				local attrs = findData.dwFileAttributes
				local size = tonumber(findData.nFileSizeHigh) * 4294967296 + tonumber(findData.nFileSizeLow)

				-- Convert FILETIME to Unix timestamp
				local ft = findData.ftLastWriteTime
				local modtime = 0
				if ft > EPOCH_DIFF then
					modtime = tonumber((ft - EPOCH_DIFF) / 10000000ULL)
				end

				entries[#entries + 1] = {
					name = name,
					size = size,
					modtime = modtime,
					isDir = (bit.band(attrs, FILE_ATTRIBUTE_DIRECTORY) ~= 0),
				}
			end
		until ffi.C.FindNextFileA(hFind, findData) == 0

		ffi.C.FindClose(hFind)
		return entries
	end
else
	-- Linux/macOS: use ls + stat via io.popen
	listDirectory = function(dir)
		local entries = {}

		local handle = io.popen('ls -1a "' .. dir .. '" 2>/dev/null')
		if not handle then return entries end

		for name in handle:lines() do
			if name ~= "." and name ~= ".." then
				local fullPath = dir .. "/" .. name
				fullPath = fullPath:gsub("//", "/")

				local entry = { name = name }

				local statHandle = io.popen('stat -c "%s %Y %F" "' .. fullPath .. '" 2>/dev/null')
				if statHandle then
					local statLine = statHandle:read("*l")
					statHandle:close()
					if statLine then
						local size, modtime, ftype = statLine:match("^(%d+) (%d+) (.+)")
						entry.size = tonumber(size) or 0
						entry.modtime = tonumber(modtime) or 0
						entry.isDir = (ftype == "directory")
					end
				end

				entries[#entries + 1] = entry
			end
		end
		handle:close()

		return entries
	end
end

function M.inject()
	function NewFileSearch(pattern, dirsOnly)
		if not pattern then return nil end

		local dir, glob = splitPattern(pattern)

		-- Get directory listing
		local allEntries = listDirectory(dir)

		-- Filter by glob pattern and dirsOnly flag
		local filtered = {}
		for _, entry in ipairs(allEntries) do
			local matchesGlob = globMatch(glob, entry.name)
			local matchesType = true
			if dirsOnly then
				matchesType = entry.isDir == true
			else
				matchesType = entry.isDir ~= true
			end

			if matchesGlob and matchesType then
				filtered[#filtered + 1] = entry
			end
		end

		if #filtered == 0 then
			return nil
		end

		-- Return a handle pointing to the first result
		local handle = setmetatable({
			_entries = filtered,
			_idx = 1,
		}, FileSearchHandle)

		return handle
	end
end

return M
