-- shim/render.lua
-- Retained-mode layer rendering system that mirrors SimpleGraphic's draw model.
-- Draw calls are collected into layer-sorted command buckets and executed at frame end.

local M = {}

-- Command types
local CMD_COLOR = 1
local CMD_RECT = 2
local CMD_IMAGE = 3
local CMD_IMAGE_QUAD = 4
local CMD_MESH = 5
local CMD_SCISSOR = 6
local CMD_SCISSOR_RESET = 7
local CMD_BLEND = 8
local CMD_TEXT = 9
local CMD_POLYGON = 10

-- Current state
local currentColor = { 1, 1, 1, 1 }
local currentLayer = 0
local currentSubLayer = 0

-- Numeric color codes matching SimpleGraphic's ^0 through ^9 palette
local numericColorCodes = {
	[0] = { 0, 0, 0 },          -- ^0 black
	[1] = { 1, 0, 0 },          -- ^1 red
	[2] = { 0, 1, 0 },          -- ^2 green
	[3] = { 0, 0, 1 },          -- ^3 blue
	[4] = { 1, 1, 0 },          -- ^4 yellow
	[5] = { 0.502, 0, 0.502 },  -- ^5 purple
	[6] = { 0, 1, 1 },          -- ^6 cyan
	[7] = { 0.750, 0.750, 0.750 }, -- ^7 light gray (default)
	[8] = { 0.600, 0.600, 0.600 }, -- ^8 gray
	[9] = { 0.400, 0.400, 0.400 }, -- ^9 dark gray
}

-- Parse a SimpleGraphic color string ("^0"-"^9" or "^xRRGGBB") into r, g, b
local function parseColorString(s)
	if not s or #s < 2 then return 1, 1, 1 end
	local digit = s:match("^%^(%d)")
	if digit then
		local c = numericColorCodes[tonumber(digit)]
		if c then return c[1], c[2], c[3] end
	end
	local hex = s:match("^%^x(%x%x%x%x%x%x)")
	if hex then
		local r = tonumber(hex:sub(1, 2), 16) / 255
		local g = tonumber(hex:sub(3, 4), 16) / 255
		local b = tonumber(hex:sub(5, 6), 16) / 255
		return r, g, b
	end
	return 1, 1, 1
end

-- Command buffers: layerBuckets[layerKey] = { commands... }
-- layerKey encodes (major * 10000 + sub + 5000) for stable sorting
local layerBuckets = {}
local layerKeys = {}
local layerKeySet = {}

-- Mesh pool for DrawImageQuad
local meshPool = {}
local meshPoolIdx = 0

-- Quad pool for DrawImage UV sub-regions (avoids allocating new Quads every frame)
local quadPool = {}
local quadPoolIdx = 0

local function getLayerKey()
	return currentLayer * 10000 + currentSubLayer + 5000
end

local function ensureBucket(key)
	if not layerKeySet[key] then
		layerKeySet[key] = true
		layerKeys[#layerKeys + 1] = key
		layerBuckets[key] = {}
	end
	return layerBuckets[key]
end

local function addCommand(...)
	local key = getLayerKey()
	local bucket = ensureBucket(key)
	bucket[#bucket + 1] = { ... }
end

-- Expose for text module to record text draw commands into the layer system
M.CMD_TEXT = CMD_TEXT

function M.addCommand(...)
	addCommand(...)
end

-- Return a copy of the current draw color (for text module to capture per-command)
function M.getCurrentColor()
	return currentColor[1], currentColor[2], currentColor[3], currentColor[4]
end

function M.init()
	-- Pre-create mesh template for DrawImageQuad (4 vertices, fan mode)
	-- Vertices: { x, y, u, v, r, g, b, a }
end

function M.inject()
	function SetDrawLayer(layer, subLayer)
		if layer then
			currentLayer = layer
		end
		currentSubLayer = subLayer or 0
	end

	function SetDrawColor(r, g, b, a)
		if type(r) == "string" then
			-- Handle string color codes: "^0"-"^9" or "^xRRGGBB"
			local pr, pg, pb = parseColorString(r)
			currentColor = { pr, pg, pb, 1 }
		elseif type(r) == "table" then
			-- Handle table form: SetDrawColor({r, g, b, a})
			currentColor = { r[1] or 1, r[2] or 1, r[3] or 1, r[4] or 1 }
		else
			currentColor = { r or 1, g or 1, b or 1, a or 1 }
		end
		-- Don't emit CMD_COLOR here. Each draw command captures the current
		-- color at recording time, ensuring correct color even when draw
		-- commands end up in different layer buckets than the SetDrawColor call.
	end

	-- Emit CMD_COLOR with the current color into the current layer bucket.
	-- Called before each draw command to capture color state per-command.
	local function emitColor()
		addCommand(CMD_COLOR, currentColor[1], currentColor[2], currentColor[3], currentColor[4])
	end

	function DrawImage(imgHandle, left, top, width, height, tcLeft, tcTop, tcRight, tcBottom)
		emitColor()
		if imgHandle == nil then
			-- Solid color rectangle
			addCommand(CMD_RECT, left, top, width, height)
		elseif type(imgHandle) == "table" and imgHandle._image then
			if tcLeft then
				-- Sub-region via UV coordinates
				addCommand(CMD_IMAGE, imgHandle, left, top, width, height, tcLeft, tcTop, tcRight, tcBottom)
			else
				addCommand(CMD_IMAGE, imgHandle, left, top, width, height)
			end
		end
	end

	function DrawImageQuad(imgHandle, x1, y1, x2, y2, x3, y3, x4, y4, s1, t1, s2, t2, s3, t3, s4, t4)
		if imgHandle and type(imgHandle) == "table" and imgHandle._image then
			emitColor()
			addCommand(CMD_MESH, imgHandle,
				x1, y1, x2, y2, x3, y3, x4, y4,
				s1 or 0, t1 or 0, s2 or 1, t2 or 0, s3 or 1, t3 or 1, s4 or 0, t4 or 1)
		elseif not imgHandle then
			-- Solid colored quad (no texture)
			emitColor()
			addCommand(CMD_POLYGON, x1, y1, x2, y2, x3, y3, x4, y4)
		end
	end

	function SetViewport(x, y, width, height)
		if x then
			-- SimpleGraphic's SetViewport sets both a clip rectangle AND
			-- translates the coordinate origin to (x, y).
			addCommand(CMD_SCISSOR, x, y, width, height)
		else
			addCommand(CMD_SCISSOR_RESET)
		end
	end

	-- Note: SimpleGraphic doesn't have a SetBlendMode in the Lua API,
	-- but we provide support in case it's needed by the draw pipeline
	function SetBlendMode(mode)
		if mode == "ALPHA" then
			addCommand(CMD_BLEND, "alpha", "alphamultiply")
		elseif mode == "PREALPHA" then
			addCommand(CMD_BLEND, "alpha", "premultiplied")
		elseif mode == "ADDITIVE" then
			addCommand(CMD_BLEND, "add", "alphamultiply")
		end
	end

	-- GetDrawLayer returns current major, sub (used in some commented-out code)
	function GetDrawLayer()
		return currentLayer, currentSubLayer
	end
end

-- Get or create a quad for DrawImage UV sub-regions
local function getQuad(x, y, w, h, sw, sh)
	quadPoolIdx = quadPoolIdx + 1
	local quad = quadPool[quadPoolIdx]
	if not quad then
		quad = love.graphics.newQuad(x, y, w, h, sw, sh)
		quadPool[quadPoolIdx] = quad
	else
		quad:setViewport(x, y, w, h, sw, sh)
	end
	return quad
end

-- Get or create a mesh for DrawImageQuad
local function getMesh(image, x1, y1, x2, y2, x3, y3, x4, y4, s1, t1, s2, t2, s3, t3, s4, t4)
	meshPoolIdx = meshPoolIdx + 1
	local mesh = meshPool[meshPoolIdx]
	if not mesh then
		mesh = love.graphics.newMesh(4, "fan", "stream")
		meshPool[meshPoolIdx] = mesh
	end
	mesh:setVertices({
		{ x1, y1, s1, t1 },
		{ x2, y2, s2, t2 },
		{ x3, y3, s3, t3 },
		{ x4, y4, s4, t4 },
	})
	mesh:setTexture(image)
	return mesh
end

function M.executeDrawCommands()
	-- Sort layer keys
	table.sort(layerKeys)

	-- Execute commands in layer order
	for i = 1, #layerKeys do
		local key = layerKeys[i]
		local bucket = layerBuckets[key]
		for j = 1, #bucket do
			local cmd = bucket[j]
			local cmdType = cmd[1]

			if cmdType == CMD_COLOR then
				love.graphics.setColor(cmd[2], cmd[3], cmd[4], cmd[5])

			elseif cmdType == CMD_RECT then
				love.graphics.rectangle("fill", cmd[2], cmd[3], cmd[4], cmd[5])

			elseif cmdType == CMD_IMAGE then
				local handle = cmd[2]
				local img = handle._image
				if img then
					local left, top, width, height = cmd[3], cmd[4], cmd[5], cmd[6]
					local tcLeft = cmd[7]
					if tcLeft then
						-- UV sub-region
						local tcTop, tcRight, tcBottom = cmd[8], cmd[9], cmd[10]
						local imgW, imgH = img:getDimensions()
						local quad = getQuad(
							tcLeft * imgW, tcTop * imgH,
							(tcRight - tcLeft) * imgW, (tcBottom - tcTop) * imgH,
							imgW, imgH
						)
						local quadW = (tcRight - tcLeft) * imgW
						local quadH = (tcBottom - tcTop) * imgH
						local sx = width / quadW
						local sy = height / quadH
						love.graphics.draw(img, quad, left, top, 0, sx, sy)
					else
						-- Full image, scaled to fit width x height
						local imgW, imgH = img:getDimensions()
						if width and height then
							local sx = width / imgW
							local sy = height / imgH
							love.graphics.draw(img, left, top, 0, sx, sy)
						else
							love.graphics.draw(img, left, top)
						end
					end
				end

			elseif cmdType == CMD_MESH then
				local handle = cmd[2]
				local img = handle._image
				if img then
					local mesh = getMesh(img,
						cmd[3], cmd[4], cmd[5], cmd[6],
						cmd[7], cmd[8], cmd[9], cmd[10],
						cmd[11], cmd[12], cmd[13], cmd[14],
						cmd[15], cmd[16], cmd[17], cmd[18])
					love.graphics.draw(mesh)
				end

			elseif cmdType == CMD_POLYGON then
				love.graphics.polygon("fill", cmd[2], cmd[3], cmd[4], cmd[5], cmd[6], cmd[7], cmd[8], cmd[9])

			elseif cmdType == CMD_SCISSOR then
				-- SetViewport in SimpleGraphic sets clip rect AND translates origin
				love.graphics.setScissor(cmd[2], cmd[3], cmd[4], cmd[5])
				love.graphics.origin()
				love.graphics.translate(cmd[2], cmd[3])

			elseif cmdType == CMD_SCISSOR_RESET then
				love.graphics.origin()
				love.graphics.setScissor()

			elseif cmdType == CMD_TEXT then
				-- cmd[2] = font, cmd[3] = segments, cmd[4] = x, cmd[5] = y
				-- cmd[6..9] = base color (r,g,b,a) from SetDrawColor at recording time
				local font = cmd[2]
				local segments = cmd[3]
				local startX = cmd[4]
				local y = cmd[5]
				local baseR, baseG, baseB, baseA = cmd[6], cmd[7], cmd[8], cmd[9]
				local lineH = font:getHeight()
				local prevFont = love.graphics.getFont()
				love.graphics.setFont(font)
				local curX = startX
				for _, seg in ipairs(segments) do
					if seg.color then
						love.graphics.setColor(seg.color[1], seg.color[2], seg.color[3], 1)
					else
						love.graphics.setColor(baseR, baseG, baseB, baseA)
					end
					-- Handle newlines within a segment
					local first = true
					for line in (seg.text.."\n"):gmatch("([^\n]*)\n") do
						if not first then
							-- Newline: reset x and advance y
							curX = startX
							y = y + lineH
						end
						if #line > 0 then
							love.graphics.print(line, curX, y)
							curX = curX + font:getWidth(line)
						end
						first = false
					end
				end
				love.graphics.setFont(prevFont)

			elseif cmdType == CMD_BLEND then
				love.graphics.setBlendMode(cmd[2], cmd[3])
			end
		end
	end

	-- Reset graphics state after frame
	love.graphics.origin()
	love.graphics.setScissor()
	love.graphics.setBlendMode("alpha", "alphamultiply")

	-- Clear command buffers for next frame
	M.clearCommands()
end

function M.clearCommands()
	for i = 1, #layerKeys do
		local key = layerKeys[i]
		layerBuckets[key] = nil
	end
	layerKeys = {}
	layerKeySet = {}
	meshPoolIdx = 0
	quadPoolIdx = 0

	-- Reset state for new frame
	currentLayer = 0
	currentSubLayer = 0
	currentColor = { 1, 1, 1, 1 }
end

return M
