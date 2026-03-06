-- cspell:words LÖVE lctrl rctrl lalt ralt kpenter numlock NUMLOCK scrolllock SCROLLLOCK capslock CAPSLOCK keypressed isrepeat keyreleased textinput mousepressed istouch mousereleased wheelmoved WHEELRIGHT WHEELLEFT
-- shim/input.lua
-- Key name translation between LÖVE and SimpleGraphic, IsKeyDown, GetCursorPos,
-- and mouse-as-keyboard event injection.

local M = {}

-- LÖVE key name → SimpleGraphic key name
local keyMap = {
	["lctrl"]      = "CTRL",
	["rctrl"]      = "CTRL",
	["lshift"]     = "SHIFT",
	["rshift"]     = "SHIFT",
	["lalt"]       = "ALT",
	["ralt"]       = "ALT",
	["return"]     = "RETURN",
	["kpenter"]    = "RETURN",
	["escape"]     = "ESCAPE",
	["backspace"]  = "BACK",
	["delete"]     = "DELETE",
	["tab"]        = "TAB",
	["space"]      = " ",
	["left"]       = "LEFT",
	["right"]      = "RIGHT",
	["up"]         = "UP",
	["down"]       = "DOWN",
	["home"]       = "HOME",
	["end"]        = "END",
	["pageup"]     = "PAGEUP",
	["pagedown"]   = "PAGEDOWN",
	["insert"]     = "INSERT",
	["f1"]         = "F1",
	["f2"]         = "F2",
	["f3"]         = "F3",
	["f4"]         = "F4",
	["f5"]         = "F5",
	["f6"]         = "F6",
	["f7"]         = "F7",
	["f8"]         = "F8",
	["f9"]         = "F9",
	["f10"]        = "F10",
	["f11"]        = "F11",
	["f12"]        = "F12",
	["f13"]        = "F13",
	["f14"]        = "F14",
	["f15"]        = "F15",
	["printscreen"] = "PRINTSCREEN",
	["pause"]      = "PAUSE",
	["numlock"]    = "NUMLOCK",
	["scrolllock"] = "SCROLLLOCK",
	["capslock"]   = "CAPSLOCK",
}

-- SimpleGraphic key name → list of LÖVE key names (for IsKeyDown reverse lookup)
local reverseKeyMap = {
	["CTRL"]   = { "lctrl", "rctrl" },
	["SHIFT"]  = { "lshift", "rshift" },
	["ALT"]    = { "lalt", "ralt" },
	["RETURN"] = { "return", "kpenter" },
	["ESCAPE"] = { "escape" },
	["BACK"]   = { "backspace" },
	["DELETE"]  = { "delete" },
	["TAB"]    = { "tab" },
	[" "]      = { "space" },
	["LEFT"]   = { "left" },
	["RIGHT"]  = { "right" },
	["UP"]     = { "up" },
	["DOWN"]   = { "down" },
	["HOME"]   = { "home" },
	["END"]    = { "end" },
	["PAGEUP"] = { "pageup" },
	["PAGEDOWN"] = { "pagedown" },
	["INSERT"] = { "insert" },
	["PRINTSCREEN"] = { "printscreen" },
	["PAUSE"]  = { "pause" },
}
-- Add F keys
for i = 1, 15 do
	reverseKeyMap["F" .. i] = { "f" .. i }
end

-- Mouse button name → love button index
local mouseButtonMap = {
	["LEFTBUTTON"]   = 1,
	["RIGHTBUTTON"]  = 2,
	["MIDDLEBUTTON"] = 3,
	["MOUSE4"]       = 4,
	["MOUSE5"]       = 5,
}

-- Translate a LÖVE key name to SimpleGraphic key name
function M.translateKey(loveKey)
	if keyMap[loveKey] then
		return keyMap[loveKey]
	end
	-- Single characters (letters, digits, punctuation) pass through
	-- SimpleGraphic uses lowercase for letter keys
	if #loveKey == 1 then
		return loveKey
	end
	return loveKey:upper()
end

-- Double-click detection
local lastClickTime = 0
local lastClickX = 0
local lastClickY = 0
local DOUBLE_CLICK_TIME = 0.4   -- seconds
local DOUBLE_CLICK_DIST = 4     -- pixels

function M.init()
end

function M.inject(runCallback)
	function IsKeyDown(name)
		-- Check mouse buttons
		local mouseBtn = mouseButtonMap[name]
		if mouseBtn then
			return love.mouse.isDown(mouseBtn)
		end

		-- Check keyboard via reverse map
		local keys = reverseKeyMap[name]
		if keys then
			return love.keyboard.isDown(unpack(keys))
		end

		-- Try as a direct LÖVE key name (lowercase)
		local loveKey = name:lower()
		local ok, result = pcall(love.keyboard.isDown, loveKey)
		if ok then
			return result
		end

		return false
	end

	function GetCursorPos()
		return love.mouse.getPosition()
	end
end

-- Handle LÖVE events and translate to SimpleGraphic callbacks
function M.handleEvent(runCallback, name, a, b, c, d, e, f)
	if name == "keypressed" then
		-- a = key, b = scancode, c = isrepeat
		local sgKey = M.translateKey(a)
		runCallback("OnKeyDown", sgKey, false)

	elseif name == "keyreleased" then
		local sgKey = M.translateKey(a)
		runCallback("OnKeyUp", sgKey)

	elseif name == "textinput" then
		-- a = text
		runCallback("OnChar", a)

	elseif name == "mousepressed" then
		-- a = x, b = y, c = button, d = istouch, e = presses
		local now = love.timer.getTime()
		local doubleClick = false
		if c == 1 then
			-- Check for double-click
			local dt = now - lastClickTime
			local dx = math.abs(a - lastClickX)
			local dy = math.abs(b - lastClickY)
			if dt < DOUBLE_CLICK_TIME and dx < DOUBLE_CLICK_DIST and dy < DOUBLE_CLICK_DIST then
				doubleClick = true
			end
			lastClickTime = now
			lastClickX = a
			lastClickY = b
			runCallback("OnKeyDown", "LEFTBUTTON", doubleClick)
		elseif c == 2 then
			runCallback("OnKeyDown", "RIGHTBUTTON", false)
		elseif c == 3 then
			runCallback("OnKeyDown", "MIDDLEBUTTON", false)
		elseif c == 4 then
			runCallback("OnKeyDown", "MOUSE4", false)
		elseif c == 5 then
			runCallback("OnKeyDown", "MOUSE5", false)
		end

	elseif name == "mousereleased" then
		-- a = x, b = y, c = button
		if c == 1 then
			runCallback("OnKeyUp", "LEFTBUTTON")
		elseif c == 2 then
			runCallback("OnKeyUp", "RIGHTBUTTON")
		elseif c == 3 then
			runCallback("OnKeyUp", "MIDDLEBUTTON")
		elseif c == 4 then
			runCallback("OnKeyUp", "MOUSE4")
		elseif c == 5 then
			runCallback("OnKeyUp", "MOUSE5")
		end

	elseif name == "wheelmoved" then
		-- a = x, b = y
		if b > 0 then
			runCallback("OnKeyUp", "WHEELUP")
		elseif b < 0 then
			runCallback("OnKeyUp", "WHEELDOWN")
		end
		if a > 0 then
			runCallback("OnKeyUp", "WHEELRIGHT")
		elseif a < 0 then
			runCallback("OnKeyUp", "WHEELLEFT")
		end
	end
end

return M
