-- cspell:words alphamultiply PREALPHA
-- shim/render.lua
-- Retained-mode layer rendering system that mirrors SimpleGraphic's draw model.
-- Draw calls are collected into layer-sorted command buckets and executed at frame end.
--
-- Performance notes:
-- - Command tables are pooled and reused across frames (zero per-frame allocation)
-- - Color is embedded in each draw command (no separate CMD_COLOR commands)
-- - During execution, setColor is only called when color actually changes
-- - Bucket tables and layer key arrays are reused, not reallocated
-- - Mesh vertex tables are pre-allocated and mutated in place

local M = {}

-- Command types
local CMD_RECT = 2
local CMD_IMAGE = 3
local CMD_MESH = 5
local CMD_SCISSOR = 6
local CMD_SCISSOR_RESET = 7
local CMD_BLEND = 8
local CMD_TEXT = 9
local CMD_POLYGON = 10

-- Current draw color as 4 separate locals (no table allocation on SetDrawColor)
local currentR, currentG, currentB, currentA = 1, 1, 1, 1
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

-- Command buffers: layerBuckets[layerKey] = array of command tables
-- layerKey encodes (major * 10000 + sub + 5000) for stable sorting
local layerBuckets = {}
local layerKeys = {}
local layerKeyCount = 0
local layerKeySet = {}
local layerKeysDirty = false

-- Bucket command counts (avoids #bucket which scans the array)
local bucketCounts = {}

-- Command table pool: reused across frames to eliminate per-frame allocation
local cmdPool = {}
local cmdPoolIdx = 0

-- Mesh pool for DrawImageQuad
local meshPool = {}
local meshPoolIdx = 0

-- Reusable vertex tables for mesh:setVertices() (mutated in place each call)
local meshVerts = {
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
}

-- Quad pool for DrawImage UV sub-regions (avoids allocating new Quads every frame)
local quadPool = {}
local quadPoolIdx = 0

-- Allocate (or reuse) a command table and insert it into the current layer bucket.
-- Returns the command table for the caller to fill in.
local function allocCmd()
	cmdPoolIdx = cmdPoolIdx + 1
	local cmd = cmdPool[cmdPoolIdx]
	if not cmd then
		cmd = {}
		cmdPool[cmdPoolIdx] = cmd
	end
	local key = currentLayer * 10000 + currentSubLayer + 5000
	if not layerKeySet[key] then
		layerKeySet[key] = true
		layerKeyCount = layerKeyCount + 1
		layerKeys[layerKeyCount] = key
		layerKeysDirty = true
		if not layerBuckets[key] then
			layerBuckets[key] = {}
		end
		bucketCounts[key] = 0
	end
	local count = bucketCounts[key] + 1
	bucketCounts[key] = count
	layerBuckets[key][count] = cmd
	return cmd
end

-- Expose for text module to record text draw commands into the layer system
M.CMD_TEXT = CMD_TEXT

-- Public addCommand for the text module (CMD_TEXT with 8 args after type)
function M.addCommand(cmdType, a, b, c, d, e, f, g, h)
	local cmd = allocCmd()
	cmd[1] = cmdType
	cmd[2] = a; cmd[3] = b; cmd[4] = c; cmd[5] = d
	cmd[6] = e; cmd[7] = f; cmd[8] = g; cmd[9] = h
end

-- Return the current draw color (for text module to capture per-command)
function M.getCurrentColor()
	return currentR, currentG, currentB, currentA
end

function M.init()
	-- Pre-create mesh template for DrawImageQuad (4 vertices, fan mode)
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
			currentR, currentG, currentB = parseColorString(r)
			currentA = 1
		elseif type(r) == "table" then
			-- Handle table form: SetDrawColor({r, g, b, a})
			currentR = r[1] or 1
			currentG = r[2] or 1
			currentB = r[3] or 1
			currentA = r[4] or 1
		else
			currentR = r or 1
			currentG = g or 1
			currentB = b or 1
			currentA = a or 1
		end
	end

	function DrawImage(imgHandle, left, top, width, height, tcLeft, tcTop, tcRight, tcBottom)
		if imgHandle == nil then
			-- Solid color rectangle: embed color at [2..5], geometry at [6..9]
			local cmd = allocCmd()
			cmd[1] = CMD_RECT
			cmd[2] = currentR; cmd[3] = currentG; cmd[4] = currentB; cmd[5] = currentA
			cmd[6] = left; cmd[7] = top; cmd[8] = width; cmd[9] = height
		elseif type(imgHandle) == "table" and imgHandle._image then
			-- Image draw: embed color at [2..5], handle at [6], geometry at [7..10], UV at [11..14]
			local cmd = allocCmd()
			cmd[1] = CMD_IMAGE
			cmd[2] = currentR; cmd[3] = currentG; cmd[4] = currentB; cmd[5] = currentA
			cmd[6] = imgHandle; cmd[7] = left; cmd[8] = top; cmd[9] = width; cmd[10] = height
			-- Explicitly set UV fields (nil clears stale data from pooled table reuse)
			cmd[11] = tcLeft; cmd[12] = tcTop; cmd[13] = tcRight; cmd[14] = tcBottom
		end
	end

	function DrawImageQuad(imgHandle, x1, y1, x2, y2, x3, y3, x4, y4, s1, t1, s2, t2, s3, t3, s4, t4)
		if imgHandle and type(imgHandle) == "table" and imgHandle._image then
			-- Textured quad: embed color at [2..5], handle at [6], coords at [7..22]
			local cmd = allocCmd()
			cmd[1] = CMD_MESH
			cmd[2] = currentR; cmd[3] = currentG; cmd[4] = currentB; cmd[5] = currentA
			cmd[6] = imgHandle
			cmd[7] = x1; cmd[8] = y1; cmd[9] = x2; cmd[10] = y2
			cmd[11] = x3; cmd[12] = y3; cmd[13] = x4; cmd[14] = y4
			cmd[15] = s1 or 0; cmd[16] = t1 or 0; cmd[17] = s2 or 1; cmd[18] = t2 or 0
			cmd[19] = s3 or 1; cmd[20] = t3 or 1; cmd[21] = s4 or 0; cmd[22] = t4 or 1
		elseif not imgHandle then
			-- Solid colored quad (no texture): embed color at [2..5], coords at [6..13]
			local cmd = allocCmd()
			cmd[1] = CMD_POLYGON
			cmd[2] = currentR; cmd[3] = currentG; cmd[4] = currentB; cmd[5] = currentA
			cmd[6] = x1; cmd[7] = y1; cmd[8] = x2; cmd[9] = y2
			cmd[10] = x3; cmd[11] = y3; cmd[12] = x4; cmd[13] = y4
		end
	end

	function SetViewport(x, y, width, height)
		if x then
			-- SimpleGraphic's SetViewport sets both a clip rectangle AND
			-- translates the coordinate origin to (x, y).
			local cmd = allocCmd()
			cmd[1] = CMD_SCISSOR
			cmd[2] = x; cmd[3] = y; cmd[4] = width; cmd[5] = height
		else
			local cmd = allocCmd()
			cmd[1] = CMD_SCISSOR_RESET
		end
	end

	-- Note: SimpleGraphic doesn't have a SetBlendMode in the Lua API,
	-- but we provide support in case it's needed by the draw pipeline
	function SetBlendMode(mode)
		if mode == "ALPHA" then
			local cmd = allocCmd()
			cmd[1] = CMD_BLEND; cmd[2] = "alpha"; cmd[3] = "alphamultiply"
		elseif mode == "PREALPHA" then
			local cmd = allocCmd()
			cmd[1] = CMD_BLEND; cmd[2] = "alpha"; cmd[3] = "premultiplied"
		elseif mode == "ADDITIVE" then
			local cmd = allocCmd()
			cmd[1] = CMD_BLEND; cmd[2] = "add"; cmd[3] = "alphamultiply"
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

-- Get or create a mesh for DrawImageQuad, reusing pre-allocated vertex tables
local function getMesh(image, x1, y1, x2, y2, x3, y3, x4, y4, s1, t1, s2, t2, s3, t3, s4, t4)
	meshPoolIdx = meshPoolIdx + 1
	local mesh = meshPool[meshPoolIdx]
	if not mesh then
		mesh = love.graphics.newMesh(4, "fan", "stream")
		meshPool[meshPoolIdx] = mesh
	end
	-- Mutate pre-allocated vertex tables in place (no allocation)
	local v1, v2, v3, v4 = meshVerts[1], meshVerts[2], meshVerts[3], meshVerts[4]
	v1[1] = x1; v1[2] = y1; v1[3] = s1; v1[4] = t1
	v2[1] = x2; v2[2] = y2; v2[3] = s2; v2[4] = t2
	v3[1] = x3; v3[2] = y3; v3[3] = s3; v3[4] = t3
	v4[1] = x4; v4[2] = y4; v4[3] = s4; v4[4] = t4
	mesh:setVertices(meshVerts)
	mesh:setTexture(image)
	return mesh
end

function M.executeDrawCommands()
	-- Sort layer keys only if new keys were added since last sort
	if layerKeysDirty then
		-- Trim layerKeys to actual count (remove stale entries from previous frames)
		for i = layerKeyCount + 1, #layerKeys do
			layerKeys[i] = nil
		end
		table.sort(layerKeys)
		layerKeysDirty = false
	end

	-- Track last-set color to avoid redundant love.graphics.setColor calls
	local lastR, lastG, lastB, lastA = -1, -1, -1, -1

	-- Execute commands in layer order
	for i = 1, layerKeyCount do
		local key = layerKeys[i]
		local bucket = layerBuckets[key]
		local count = bucketCounts[key]
		for j = 1, count do
			local cmd = bucket[j]
			local cmdType = cmd[1]

			if cmdType == CMD_RECT then
				local cr, cg, cb, ca = cmd[2], cmd[3], cmd[4], cmd[5]
				if cr ~= lastR or cg ~= lastG or cb ~= lastB or ca ~= lastA then
					love.graphics.setColor(cr, cg, cb, ca)
					lastR, lastG, lastB, lastA = cr, cg, cb, ca
				end
				love.graphics.rectangle("fill", cmd[6], cmd[7], cmd[8], cmd[9])

			elseif cmdType == CMD_IMAGE then
				local cr, cg, cb, ca = cmd[2], cmd[3], cmd[4], cmd[5]
				if cr ~= lastR or cg ~= lastG or cb ~= lastB or ca ~= lastA then
					love.graphics.setColor(cr, cg, cb, ca)
					lastR, lastG, lastB, lastA = cr, cg, cb, ca
				end
				local handle = cmd[6]
				local img = handle._image
				if img then
					local left, top, width, height = cmd[7], cmd[8], cmd[9], cmd[10]
					local tcLeft = cmd[11]
					if tcLeft then
						-- UV sub-region
						local tcTop, tcRight, tcBottom = cmd[12], cmd[13], cmd[14]
						local imgW = handle._width or img:getWidth()
						local imgH = handle._height or img:getHeight()
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
						local imgW = handle._width or img:getWidth()
						local imgH = handle._height or img:getHeight()
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
				local cr, cg, cb, ca = cmd[2], cmd[3], cmd[4], cmd[5]
				if cr ~= lastR or cg ~= lastG or cb ~= lastB or ca ~= lastA then
					love.graphics.setColor(cr, cg, cb, ca)
					lastR, lastG, lastB, lastA = cr, cg, cb, ca
				end
				local handle = cmd[6]
				local img = handle._image
				if img then
					local mesh = getMesh(img,
						cmd[7], cmd[8], cmd[9], cmd[10],
						cmd[11], cmd[12], cmd[13], cmd[14],
						cmd[15], cmd[16], cmd[17], cmd[18],
						cmd[19], cmd[20], cmd[21], cmd[22])
					love.graphics.draw(mesh)
				end

			elseif cmdType == CMD_POLYGON then
				local cr, cg, cb, ca = cmd[2], cmd[3], cmd[4], cmd[5]
				if cr ~= lastR or cg ~= lastG or cb ~= lastB or ca ~= lastA then
					love.graphics.setColor(cr, cg, cb, ca)
					lastR, lastG, lastB, lastA = cr, cg, cb, ca
				end
				love.graphics.polygon("fill", cmd[6], cmd[7], cmd[8], cmd[9], cmd[10], cmd[11], cmd[12], cmd[13])

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
				-- Invalidate tracked color (CMD_TEXT calls setColor internally)
				lastR, lastG, lastB, lastA = -1, -1, -1, -1

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
	-- Reset bucket counts and layer key set (reuse the table allocations)
	for i = 1, layerKeyCount do
		local key = layerKeys[i]
		bucketCounts[key] = 0
		layerKeySet[key] = nil
	end
	layerKeyCount = 0
	layerKeysDirty = false
	cmdPoolIdx = 0
	meshPoolIdx = 0
	quadPoolIdx = 0

	-- Reset state for new frame
	currentLayer = 0
	currentSubLayer = 0
	currentR, currentG, currentB, currentA = 1, 1, 1, 1
end

return M
