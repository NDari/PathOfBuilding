-- cspell:words LÖVE clampzero
-- shim/image.lua
-- NewImageHandle wrapper around love.graphics.newImage
-- Mimics the SimpleGraphic ImageHandle userdata interface.
-- Loads images from the real filesystem (not LÖVE's VFS) since PoB uses
-- relative paths from src/.

local M = {}

-- Load image data from real filesystem, return a love.Image or nil
local function loadImageFromPath(path)
	-- Read raw file data from the real filesystem
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	if not data or #data == 0 then return nil end

	-- Create a LÖVE FileData from the raw bytes, then an ImageData, then an Image
	local ok, fileData = pcall(love.filesystem.newFileData, data, path)
	if not ok then return nil end

	local ok2, imageData = pcall(love.image.newImageData, fileData)
	if not ok2 then return nil end

	local ok3, img = pcall(love.graphics.newImage, imageData)
	if not ok3 then return nil end

	return img
end

local imageHandleClass = {}
imageHandleClass.__index = imageHandleClass

function imageHandleClass:Load(fileName, ...)
	local flags = { ... }
	local path = fileName

	-- Try loading the image
	local img = loadImageFromPath(path)

	-- Fallback: try .png if .webp was requested (post-conversion)
	if not img and path:match("%.webp$") then
		local pngPath = path:gsub("%.webp$", ".png")
		img = loadImageFromPath(pngPath)
	end

	if img then
		self._image = img
		self._width, self._height = img:getDimensions()
		-- Handle flags
		for _, flag in ipairs(flags) do
			if flag == "CLAMP" then
				img:setWrap("clampzero", "clampzero")
			end
		end
	else
		self._image = nil
		self._width, self._height = nil, nil
	end
end

function imageHandleClass:Unload()
	self._image = nil
	self._width, self._height = nil, nil
end

function imageHandleClass:IsValid()
	return self._image ~= nil
end

function imageHandleClass:IsLoading()
	return false
end

function imageHandleClass:SetLoadingPriority(pri)
	-- No-op: LÖVE loads synchronously
end

function imageHandleClass:ImageSize()
	if self._image then
		return self._width, self._height
	end
	return 1, 1
end

function M.inject()
	function NewImageHandle()
		return setmetatable({ _image = nil }, imageHandleClass)
	end
end

return M
