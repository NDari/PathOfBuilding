-- cspell:words cdef
-- shim/compat.lua
-- OS-level compatibility utilities (chdir, etc.)

local M = {}

local ffi = require("ffi")

if ffi.os == "Windows" then
	ffi.cdef[[
		int _chdir(const char *path);
	]]
	function M.chdir(path)
		local ret = ffi.C._chdir(path)
		if ret ~= 0 then
			error("chdir failed for path: " .. tostring(path))
		end
	end
else
	ffi.cdef[[
		int chdir(const char *path);
	]]
	function M.chdir(path)
		local ret = ffi.C.chdir(path)
		if ret ~= 0 then
			error("chdir failed for path: " .. tostring(path))
		end
	end
end

return M
