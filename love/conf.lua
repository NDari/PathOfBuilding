-- cspell:words usedpiscale
function love.conf(t)
	t.identity = "PathOfBuilding"
	t.window.title = "Path of Building"
	t.window.width = 1280
	t.window.height = 720
	t.window.resizable = true
	t.window.usedpiscale = true
	t.modules.audio = false
	t.modules.joystick = false
	t.modules.physics = false
	t.modules.video = false
end
