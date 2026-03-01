-- shim/text.lua
-- Text rendering: DrawString, DrawStringWidth, DrawStringCursorIndex, StripEscapes
-- Handles font caching, color escape codes (^0-^9, ^xRRGGBB), and alignment modes.

local M = {}

-- Font file mapping: SimpleGraphic font name → TTF file path
-- These TTF files must be placed in love/fonts/
local fontFileMap = {
	["VAR"]            = "fonts/FontinSmallCaps.ttf",
	["VAR BOLD"]       = "fonts/FontinSmallCaps.ttf",  -- No separate bold; same face
	["VAR ITALIC"]     = "fonts/FontinSmallCaps.ttf",  -- No separate italic TTF available
	["FIXED"]          = "fonts/BitstreamVeraSansMono.ttf",
}

-- Cache: fontCache[fontName][height] = love.graphics.Font
local fontCache = {}

-- Default color codes matching PoB's ^0 through ^9
-- These correspond to SimpleGraphic's built-in color palette
local colorCodes = {
	[0] = { 1.000, 1.000, 1.000 },  -- ^0 white
	[1] = { 1.000, 0.000, 0.000 },  -- ^1 red
	[2] = { 0.000, 1.000, 0.000 },  -- ^2 green
	[3] = { 0.000, 0.000, 1.000 },  -- ^3 blue
	[4] = { 1.000, 1.000, 0.000 },  -- ^4 yellow
	[5] = { 0.502, 0.000, 0.502 },  -- ^5 purple
	[6] = { 0.000, 1.000, 1.000 },  -- ^6 cyan
	[7] = { 0.750, 0.750, 0.750 },  -- ^7 light gray (default)
	[8] = { 0.600, 0.600, 0.600 },  -- ^8 gray
	[9] = { 0.400, 0.400, 0.400 },  -- ^9 dark gray
}

-- Base path for fonts on real filesystem (set during init)
local fontBasePath = ""

-- Load a font at the given size.
-- Tries the real filesystem first (dev mode), then LÖVE's VFS (fused mode
-- where fonts are embedded inside the .love archive).
local function loadFont(relPath, fullPath, size)
	-- Try real filesystem (works in dev mode)
	local f = io.open(fullPath, "rb")
	if f then
		local data = f:read("*a")
		f:close()
		if data and #data > 0 then
			local ok, fileData = pcall(love.filesystem.newFileData, data, fullPath)
			if ok then
				local ok2, font = pcall(love.graphics.newFont, fileData, size)
				if ok2 then return font end
			end
		end
	end

	-- Try LÖVE VFS (works in fused mode — fonts are in the .love archive)
	local ok, font = pcall(love.graphics.newFont, relPath, size)
	if ok then return font end

	return nil
end

-- Get or create a font at a given size
-- SimpleGraphic treats height as exact pixel height, but LÖVE's font size
-- produces a getHeight() larger than the requested size (due to line spacing).
-- We compensate by scaling down the creation size so the actual rendered
-- height matches what PoB expects.
local function getFont(fontName, height)
	if not fontCache[fontName] then
		fontCache[fontName] = {}
	end
	if not fontCache[fontName][height] then
		local relPath = fontFileMap[fontName] or fontFileMap["VAR"]
		local fullPath = fontBasePath .. "/" .. relPath
		local font = loadFont(relPath, fullPath, height)
		if not font then
			font = love.graphics.newFont(height)
		end
		-- Adjust size so font:getHeight() matches the requested pixel height
		local actualHeight = font:getHeight()
		if actualHeight > 0 and math.abs(actualHeight - height) > 1 then
			local adjusted = math.max(1, math.floor(height * height / actualHeight + 0.5))
			local adjFont = loadFont(relPath, fullPath, adjusted)
			if adjFont then
				font = adjFont
			end
		end
		fontCache[fontName][height] = font
	end
	return fontCache[fontName][height]
end

-- Parse text with color escapes into segments: { {r,g,b}, "text" } pairs
local function parseColoredText(text)
	local segments = {}
	local pos = 1
	local len = #text
	local currentColor = nil  -- nil = use SetDrawColor's current color

	while pos <= len do
		-- Look for ^ escape
		local escStart = text:find("%^", pos)
		if not escStart then
			-- Rest of string has no escapes
			if pos <= len then
				segments[#segments + 1] = { color = currentColor, text = text:sub(pos) }
			end
			break
		end

		-- Add text before the escape
		if escStart > pos then
			segments[#segments + 1] = { color = currentColor, text = text:sub(pos, escStart - 1) }
		end

		-- Check what follows ^
		local nextChar = text:sub(escStart + 1, escStart + 1)
		if nextChar:match("%d") then
			-- ^0 through ^9 color code
			currentColor = colorCodes[tonumber(nextChar)]
			pos = escStart + 2
		elseif nextChar == "x" and escStart + 7 <= len then
			-- ^xRRGGBB hex color
			local hex = text:sub(escStart + 2, escStart + 7)
			if hex:match("^%x%x%x%x%x%x$") then
				local r = tonumber(hex:sub(1, 2), 16) / 255
				local g = tonumber(hex:sub(3, 4), 16) / 255
				local b = tonumber(hex:sub(5, 6), 16) / 255
				currentColor = { r, g, b }
				pos = escStart + 8
			else
				-- Invalid hex, treat ^ as literal
				segments[#segments + 1] = { color = currentColor, text = "^" }
				pos = escStart + 1
			end
		else
			-- Unknown escape, treat ^ as literal
			segments[#segments + 1] = { color = currentColor, text = "^" }
			pos = escStart + 1
		end
	end

	return segments
end

-- Reference render module to record commands
local render

function M.init(renderModule, loveSource)
	render = renderModule
	fontBasePath = loveSource or "."
end

function M.inject()
	-- StripEscapes: remove ^0-^9 and ^xRRGGBB from text
	-- Copied from HeadlessWrapper.lua for exact compatibility
	function StripEscapes(text)
		return text:gsub("%^%d", ""):gsub("%^x%x%x%x%x%x%x", "")
	end

	function DrawString(left, top, align, height, fontName, text)
		if not text or text == "" then return end
		local font = getFont(fontName, height)
		local stripped = StripEscapes(text)
		local screenW = love.graphics.getWidth()

		-- Use widest line for alignment when text contains newlines
		local maxW = 0
		for line in stripped:gmatch("[^\n]*") do
			local w = font:getWidth(line)
			if w > maxW then maxW = w end
		end

		-- Calculate x position based on alignment
		local x = left
		if align == "CENTER" then
			x = (screenW - maxW) / 2
		elseif align == "CENTER_X" then
			x = left - maxW / 2
		elseif align == "RIGHT_X" then
			x = left - maxW
		elseif align == "RIGHT" then
			x = screenW - maxW
		end
		-- "LEFT" or default: x = left

		-- Parse color escapes and record as a draw command in the layer system.
		-- Capture the current SetDrawColor as the base color for segments
		-- that have no escape color (color = nil).
		local segments = parseColoredText(text)
		local cr, cg, cb, ca = render.getCurrentColor()
		render.addCommand(render.CMD_TEXT, font, segments, x, top, cr, cg, cb, ca)
	end

	function DrawStringWidth(height, fontName, text)
		if not text or text == "" then return 0 end
		local font = getFont(fontName, height)
		local stripped = StripEscapes(text)
		-- Return the width of the widest line
		local maxW = 0
		for line in stripped:gmatch("[^\n]*") do
			local w = font:getWidth(line)
			if w > maxW then maxW = w end
		end
		return maxW
	end

	function DrawStringCursorIndex(height, fontName, text, cursorX, cursorY)
		if not text or text == "" then return 0 end
		local font = getFont(fontName, height)
		local stripped = StripEscapes(text)
		local len = #stripped

		-- Binary search for closest character index
		local bestIdx = 0
		local bestDist = math.abs(cursorX)
		for i = 1, len do
			local w = font:getWidth(stripped:sub(1, i))
			local dist = math.abs(cursorX - w)
			if dist < bestDist then
				bestDist = dist
				bestIdx = i
			end
		end

		-- Need to map back from stripped index to original text index
		-- Count escape characters before the stripped index
		local origIdx = 0
		local strippedCount = 0
		local pos = 1
		while pos <= #text and strippedCount < bestIdx do
			if text:sub(pos, pos) == "^" then
				local next = text:sub(pos + 1, pos + 1)
				if next:match("%d") then
					pos = pos + 2
				elseif next == "x" and text:sub(pos + 2, pos + 7):match("^%x%x%x%x%x%x$") then
					pos = pos + 8
				else
					strippedCount = strippedCount + 1
					pos = pos + 1
				end
			else
				strippedCount = strippedCount + 1
				pos = pos + 1
			end
		end
		origIdx = pos - 1

		return origIdx
	end
end

return M
