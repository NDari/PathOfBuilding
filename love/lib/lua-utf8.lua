-- cspell:words LÖVE luautf
-- lua-utf8 compatibility shim for LÖVE
-- Maps lua-utf8 API to LÖVE's built-in utf8 module + LuaJIT string ops
-- The lua-utf8 C library provides: sub, len, reverse, gsub, find, match, next, etc.
-- LÖVE's utf8 module provides: len, offset, codepoint, char, codes
-- We supplement with pattern-based implementations for the string ops.

local M = {}

-- Start with LÖVE's utf8 module if available
local love_utf8 = require("utf8")
if love_utf8 then
	for k, v in pairs(love_utf8) do
		M[k] = v
	end
end

-- UTF-8 aware string operations using Lua patterns
-- These match the luautf8 C library API

-- utf8.sub(s, i [, j])
-- Extract substring by character (not byte) positions
function M.sub(s, i, j)
	if not s then return "" end
	local len = love_utf8.len(s) or #s
	if not j then j = len end
	if i < 0 then i = len + i + 1 end
	if j < 0 then j = len + j + 1 end
	if i < 1 then i = 1 end
	if j > len then j = len end
	if i > j then return "" end

	local startByte = love_utf8.offset(s, i) or 1
	local endByte
	if j >= len then
		endByte = #s
	else
		endByte = (love_utf8.offset(s, j + 1) or (#s + 1)) - 1
	end
	return s:sub(startByte, endByte)
end

-- utf8.reverse(s)
-- Reverse a UTF-8 string by codepoints
function M.reverse(s)
	if not s or s == "" then return "" end
	local chars = {}
	for _, code in love_utf8.codes(s) do
		chars[#chars + 1] = love_utf8.char(code)
	end
	local result = {}
	for i = #chars, 1, -1 do
		result[#result + 1] = chars[i]
	end
	return table.concat(result)
end

-- utf8.gsub, utf8.find, utf8.match — delegate to string library
-- The lua-utf8 C library extends these for UTF-8 character classes,
-- but in practice PoB uses them with ASCII patterns only.
M.gsub = string.gsub
M.find = string.find
M.match = string.match

-- utf8.next(s, pos, step)
-- Move by 'step' codepoints from byte position 'pos'
-- Returns the new byte position
function M.next(s, pos, step)
	if not s or s == "" then return nil end
	step = step or 1
	if step > 0 then
		local current = pos
		for _ = 1, step do
			if current > #s then return nil end
			-- Find the start of the next codepoint
			current = current + 1
			while current <= #s do
				local byte = s:byte(current)
				if byte < 0x80 or byte >= 0xC0 then break end
				current = current + 1
			end
		end
		if current > #s + 1 then return nil end
		return current
	elseif step < 0 then
		local current = pos
		for _ = 1, -step do
			if current <= 0 then return nil end
			current = current - 1
			while current > 0 do
				local byte = s:byte(current)
				if byte < 0x80 or byte >= 0xC0 then break end
				current = current - 1
			end
		end
		if current < 0 then return nil end
		return current
	end
	return pos
end

return M
