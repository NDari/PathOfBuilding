-- cspell:words LÖVE luasec luaopen
-- lcurl.safe compatibility shim for LÖVE
-- Implements the lcurl easy API by shelling out to the system curl binary.
-- This avoids any dependency on lua-https or luasec and works on all Linux systems.
--
-- To use the real lcurl C library instead: place lcurl.so in love/lib/

-- Try to load the real C library first
local ok, real_lcurl = pcall(function()
	local saved = package.loaded["lcurl.safe"]
	package.loaded["lcurl.safe"] = nil
	local path = package.searchpath("lcurl.safe", package.cpath)
	if path then
		local loader = package.loadlib(path, "luaopen_lcurl_safe")
		if loader then
			local result = loader()
			package.loaded["lcurl.safe"] = saved
			return result
		end
	end
	package.loaded["lcurl.safe"] = saved
	return nil
end)

if ok and real_lcurl then
	return real_lcurl
end

-- Platform detection
local isWindows = (jit.os == "Windows")
local devNull = isWindows and "NUL" or "/dev/null"

-- Verify system curl is available
local curlCheck = io.popen("curl --version 2>" .. devNull, "r")
if curlCheck then
	local ver = curlCheck:read("*l")
	curlCheck:close()
	if ver and ver:match("^curl") then
		print("[LÖVE shim] Using system curl for HTTP: " .. ver:match("^curl%s+%S+"))
	else
		print("[LÖVE shim] WARNING: system curl not found — HTTP requests will fail")
	end
else
	print("[LÖVE shim] WARNING: could not check for system curl")
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function shellQuote(s)
	if isWindows then
		-- Double-quote the string, escaping embedded double quotes
		return '"' .. s:gsub('"', '""') .. '"'
	else
		-- Single-quote the string, escaping any embedded single quotes
		return "'" .. s:gsub("'", "'\\''") .. "'"
	end
end

-- os.tmpname() on Windows may return a bare \sXXXXX without a directory prefix.
-- Prepend %TEMP% if no drive letter / absolute path is present.
local function safeTmpName()
	local name = os.tmpname()
	if isWindows and not name:match("^%a:") and not name:match("^\\\\") then
		local tmp = os.getenv("TEMP") or os.getenv("TMP") or "."
		name = tmp .. name
	end
	return name
end

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then return "" end
	local data = f:read("*a")
	f:close()
	return data or ""
end

local function urlEncode(str)
	return str:gsub("([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

local errMT = { __index = { msg = function(self) return self._msg end } }
local function makeError(msg)
	return setmetatable({ _msg = msg }, errMT)
end

---------------------------------------------------------------------------
-- Module table + OPT / INFO constants
---------------------------------------------------------------------------
local M = {}

M.OPT_HTTPHEADER      = 1
M.OPT_USERAGENT       = 2
M.OPT_ACCEPT_ENCODING = 3
M.OPT_FOLLOWLOCATION  = 4
M.OPT_POST            = 5
M.OPT_POSTFIELDS      = 6
M.OPT_IPRESOLVE       = 7
M.OPT_PROXY           = 8
M.OPT_SSL_VERIFYPEER  = 9
M.OPT_SSL_VERIFYHOST  = 10
M.INFO_RESPONSE_CODE  = 11
M.INFO_REDIRECT_URL   = 12
M.INFO_SIZE_DOWNLOAD  = 13

---------------------------------------------------------------------------
-- Easy handle
---------------------------------------------------------------------------
local easyMT = {}
easyMT.__index = easyMT

function easyMT:setopt(opt, val)
	if opt == M.OPT_HTTPHEADER then
		self._httpheader = val
	elseif opt == M.OPT_USERAGENT then
		self._useragent = val
	elseif opt == M.OPT_ACCEPT_ENCODING then
		self._acceptEncoding = val
	elseif opt == M.OPT_FOLLOWLOCATION then
		self._followLocation = (val and val ~= 0)
	elseif opt == M.OPT_POST then
		self._post = val and true or false
	elseif opt == M.OPT_POSTFIELDS then
		self._postfields = val
	elseif opt == M.OPT_IPRESOLVE then
		self._ipresolve = val
	elseif opt == M.OPT_PROXY then
		self._proxy = val
	elseif opt == M.OPT_SSL_VERIFYPEER then
		self._sslVerifyPeer = val
	elseif opt == M.OPT_SSL_VERIFYHOST then
		self._sslVerifyHost = val
	end
	return self
end

function easyMT:setopt_url(url)
	self._url = url
	return self
end

function easyMT:setopt_headerfunction(fn)
	self._headerfunction = fn
	return self
end

function easyMT:setopt_writefunction(fn)
	self._writefunction = fn
	return self
end

function easyMT:escape(str)
	return urlEncode(str)
end

function easyMT:getinfo(info)
	if info == M.INFO_RESPONSE_CODE then
		return self._responseCode or 0
	elseif info == M.INFO_REDIRECT_URL then
		return self._redirectUrl
	elseif info == M.INFO_SIZE_DOWNLOAD then
		return self._downloadSize or 0
	end
	return 0
end

function easyMT:getinfo_response_code()
	return self._responseCode or 0
end

function easyMT:close()
	-- Nothing to clean up
end

---------------------------------------------------------------------------
-- perform() — executes the request via system curl
--
-- Uses temp files to cleanly separate body, headers, and metadata:
--   -o bodyFile      → response body
--   -D headerFile    → response headers
--   -w "..."         → status code + redirect URL on stdout
---------------------------------------------------------------------------
function easyMT:perform()
	local url = self._url
	if not url or url == "" then
		return nil, makeError("No URL set")
	end

	-- Temp files for body and headers
	local bodyFile = safeTmpName()
	local headerFile = safeTmpName()

	-- Build curl command
	local parts = { "curl", "-sS" }

	-- Follow redirects
	if self._followLocation then
		parts[#parts + 1] = "-L"
	end

	-- Proxy
	if self._proxy and self._proxy ~= "" then
		parts[#parts + 1] = "--proxy"
		parts[#parts + 1] = shellQuote(self._proxy)
	end

	-- SSL verification
	if self._sslVerifyPeer == 0 then
		parts[#parts + 1] = "--insecure"
	end

	-- IP resolve preference
	if self._ipresolve then
		-- curl values: 1 = IPv4, 2 = IPv6 (matching CURL_IPRESOLVE_V4/V6)
		if self._ipresolve == 1 then
			parts[#parts + 1] = "-4"
		elseif self._ipresolve == 2 then
			parts[#parts + 1] = "-6"
		end
	end

	-- Request headers
	if self._useragent then
		parts[#parts + 1] = "-A"
		parts[#parts + 1] = shellQuote(self._useragent)
	end
	if self._acceptEncoding then
		parts[#parts + 1] = "--compressed"
	end
	if self._httpheader then
		for _, h in ipairs(self._httpheader) do
			parts[#parts + 1] = "-H"
			parts[#parts + 1] = shellQuote(h)
		end
	end

	-- POST data
	local postTmpFile
	if self._post and self._postfields then
		parts[#parts + 1] = "-X"
		parts[#parts + 1] = "POST"
		-- Write POST body to temp file to avoid shell quoting issues
		postTmpFile = safeTmpName()
		local f = io.open(postTmpFile, "wb")
		if f then
			f:write(self._postfields)
			f:close()
			parts[#parts + 1] = "--data-binary"
			parts[#parts + 1] = "@" .. shellQuote(postTmpFile)
		end
	end

	-- Output: body to file, headers to file, metadata to stdout
	parts[#parts + 1] = "-o"
	parts[#parts + 1] = shellQuote(bodyFile)
	parts[#parts + 1] = "-D"
	parts[#parts + 1] = shellQuote(headerFile)
	-- -w format: http_code<TAB>redirect_url
	parts[#parts + 1] = "-w"
	if isWindows then
		parts[#parts + 1] = '"%{http_code}\\t%{redirect_url}"'
	else
		parts[#parts + 1] = "'%{http_code}\\t%{redirect_url}'"
	end

	-- URL (last)
	parts[#parts + 1] = shellQuote(url)

	local cmd = table.concat(parts, " ") .. " 2>" .. devNull
	local handle = io.popen(cmd, "r")
	local meta = ""
	if handle then
		meta = handle:read("*a") or ""
		handle:close()
	end

	-- Read body and headers from temp files
	local respBody = readFile(bodyFile)
	local rawHeaders = readFile(headerFile)

	-- Clean up temp files
	os.remove(bodyFile)
	os.remove(headerFile)
	if postTmpFile then os.remove(postTmpFile) end

	-- Parse metadata: "200\thttps://..."
	local codeStr, redirectUrl = meta:match("^(%d+)\t(.*)$")
	local code = tonumber(codeStr) or 0
	if redirectUrl == "" then redirectUrl = nil end

	-- Store results
	self._responseCode = code
	self._downloadSize = #respBody
	self._redirectUrl = redirectUrl

	-- Parse response headers and call header callback
	if rawHeaders ~= "" then
		-- With -L, headerFile contains headers for all responses in the chain.
		-- Find the last response block (starts with "HTTP/")
		local lastBlock = rawHeaders
		-- Find position of last "HTTP/" line
		local lastPos = 1
		local searchPos = 1
		while true do
			local found = rawHeaders:find("\nHTTP/", searchPos)
			if not found then break end
			lastPos = found + 1
			searchPos = found + 1
		end
		lastBlock = rawHeaders:sub(lastPos)

		if self._headerfunction then
			for line in lastBlock:gmatch("[^\r\n]+") do
				self._headerfunction(line .. "\r\n")
			end
		end
	end

	-- Call body callback (may be a function or a file handle)
	if self._writefunction and #respBody > 0 then
		if type(self._writefunction) == "function" then
			self._writefunction(respBody)
		else
			-- File handle passed directly (real lcurl writes to CURLOPT_WRITEDATA)
			self._writefunction:write(respBody)
		end
	end

	if code > 0 then
		return true
	else
		return nil, makeError("curl request failed")
	end
end

---------------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------------
function M.easy()
	return setmetatable({
		_url            = "",
		_responseCode   = 0,
		_downloadSize   = 0,
		_followLocation = false,
		_post           = false,
	}, easyMT)
end

return M
