-- cspell:words cdef eocd EOCD
-- Pure Lua/LuaJIT ZIP file reader
-- Uses LuaJIT FFI to call zlib for raw deflate decompression
-- API compatible with the lzip C module used by Path of Building

local ffi = require("ffi")

-- Byte-level readers for little-endian integers
local function readU16LE(data, offset)
	local b0, b1 = data:byte(offset + 1, offset + 2)
	return b0 + b1 * 256
end

local function readU32LE(data, offset)
	local b0, b1, b2, b3 = data:byte(offset + 1, offset + 4)
	return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

-- zlib FFI declarations
ffi.cdef[[
typedef struct z_stream_s {
	const unsigned char *next_in;
	unsigned int avail_in;
	unsigned long total_in;
	unsigned char *next_out;
	unsigned int avail_out;
	unsigned long total_out;
	const char *msg;
	void *state;
	void *zalloc;
	void *zfree;
	void *opaque;
	int data_type;
	unsigned long adler;
	unsigned long reserved;
} z_stream;

int inflateInit2_(z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(z_stream *strm, int flush);
int inflateEnd(z_stream *strm);
]]

local Z_OK = 0
local Z_STREAM_END = 1
local Z_FINISH = 4

-- Load zlib shared library
local zlib
do
	local names = ffi.os == "Windows"
		and { "zlib1", "zlib", "z" }
		or  { "z", "libz.so.1", "zlib" }
	for _, name in ipairs(names) do
		local ok, lib = pcall(ffi.load, name)
		if ok then
			zlib = lib
			break
		end
	end
	if not zlib then
		-- Try process symbols (works if zlib is statically linked into the host)
		local ok = pcall(function() return ffi.C.inflate end)
		if ok then
			zlib = ffi.C
		end
	end
end

local function rawInflate(compressedData, uncompressedSize)
	if not zlib then
		error("lzip: could not load zlib library")
	end

	local stream = ffi.new("z_stream")
	stream.next_in = ffi.cast("const unsigned char *", compressedData)
	stream.avail_in = #compressedData

	-- Use known uncompressed size from central directory, with safety margin
	local outSize = uncompressedSize > 0 and (uncompressedSize + 64) or (#compressedData * 8)
	local outBuf = ffi.new("unsigned char[?]", outSize)
	stream.next_out = outBuf
	stream.avail_out = outSize

	-- windowBits = -15 for raw deflate (no zlib/gzip header)
	local ret = zlib.inflateInit2_(stream, -15, "1.2.11", ffi.sizeof("z_stream"))
	if ret ~= Z_OK then
		error("lzip: inflateInit2 failed with code " .. ret)
	end

	ret = zlib.inflate(stream, Z_FINISH)
	if ret ~= Z_STREAM_END then
		local msg = stream.msg ~= nil and ffi.string(stream.msg) or ("code " .. ret)
		zlib.inflateEnd(stream)
		error("lzip: inflate failed: " .. msg)
	end

	local result = ffi.string(outBuf, stream.total_out)
	zlib.inflateEnd(stream)
	return result
end

---------------------------------------------------------------------------
-- ZipFile: represents a single file entry opened for reading
---------------------------------------------------------------------------
local ZipFile = {}
ZipFile.__index = ZipFile

function ZipFile:Read(mode)
	if mode == "*a" or mode == "*all" then
		return self._data
	end
	error("lzip: unsupported read mode: " .. tostring(mode))
end

function ZipFile:Close()
	self._data = nil
end

---------------------------------------------------------------------------
-- Zip: represents an open ZIP archive
---------------------------------------------------------------------------
local Zip = {}
Zip.__index = Zip

function Zip:OpenFile(nameOrIndex)
	local entry
	if type(nameOrIndex) == "number" then
		entry = self._fileList[nameOrIndex]
	else
		-- Normalize path separators for lookup
		local key = nameOrIndex:gsub("\\", "/")
		entry = self._entries[key]
		if not entry then
			-- Try original name as-is
			entry = self._entries[nameOrIndex]
		end
	end
	if not entry then
		return nil
	end

	-- Read the local file header to find the actual data start
	-- (local header extra field may differ in size from the central directory entry)
	local pos = entry.localHeaderOffset

	-- Verify local file header signature (0x04034b50)
	if readU32LE(self._raw, pos) ~= 0x04034b50 then
		return nil
	end

	local localNameLen = readU16LE(self._raw, pos + 26)
	local localExtraLen = readU16LE(self._raw, pos + 28)
	local dataStart = pos + 30 + localNameLen + localExtraLen

	local compressedData = self._raw:sub(dataStart + 1, dataStart + entry.compressedSize)

	local data
	if entry.compressionMethod == 0 then
		-- Stored (no compression)
		data = compressedData
	elseif entry.compressionMethod == 8 then
		-- Deflate
		data = rawInflate(compressedData, entry.uncompressedSize)
	else
		error("lzip: unsupported compression method " .. entry.compressionMethod)
	end

	return setmetatable({ _data = data }, ZipFile)
end

function Zip:GetFileName(index)
	local entry = self._fileList[index]
	return entry and entry.name or nil
end

function Zip:GetFileSize(index)
	local entry = self._fileList[index]
	return entry and entry.uncompressedSize or nil
end

function Zip:GetNumFiles()
	return #self._fileList
end

function Zip:Close()
	self._raw = nil
	self._entries = nil
	self._fileList = nil
end

---------------------------------------------------------------------------
-- Module: lzip.open(fileName) -> Zip handle or nil
---------------------------------------------------------------------------
local lzip = {}

function lzip.open(fileName)
	local file = io.open(fileName, "rb")
	if not file then
		return nil
	end
	local raw = file:read("*a")
	file:close()

	if #raw < 22 then
		return nil
	end

	-- Find End of Central Directory record (signature 0x06054b50)
	-- Search backwards; EOCD comment can be up to 65535 bytes
	local eocdPos
	for i = #raw - 22, math.max(0, #raw - 65557), -1 do
		if readU32LE(raw, i) == 0x06054b50 then
			eocdPos = i
			break
		end
	end
	if not eocdPos then
		return nil
	end

	local cdCount = readU16LE(raw, eocdPos + 10)
	local cdOffset = readU32LE(raw, eocdPos + 16)

	-- Parse Central Directory entries
	local entries = {}
	local fileList = {}
	local pos = cdOffset

	for i = 1, cdCount do
		if readU32LE(raw, pos) ~= 0x02014b50 then
			break
		end

		local compressionMethod = readU16LE(raw, pos + 10)
		local compressedSize    = readU32LE(raw, pos + 20)
		local uncompressedSize  = readU32LE(raw, pos + 24)
		local nameLen           = readU16LE(raw, pos + 28)
		local extraLen          = readU16LE(raw, pos + 30)
		local commentLen        = readU16LE(raw, pos + 32)
		local localHeaderOffset = readU32LE(raw, pos + 42)

		local name = raw:sub(pos + 46 + 1, pos + 46 + nameLen)
		local key = name:gsub("\\", "/")

		local entry = {
			name              = key,
			compressionMethod = compressionMethod,
			compressedSize    = compressedSize,
			uncompressedSize  = uncompressedSize,
			localHeaderOffset = localHeaderOffset,
		}

		entries[key] = entry
		fileList[i] = entry

		pos = pos + 46 + nameLen + extraLen + commentLen
	end

	return setmetatable({
		_raw      = raw,
		_entries  = entries,
		_fileList = fileList,
	}, Zip)
end

return lzip
