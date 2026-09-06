-- plus1-jump — headless HUD fit check. Run: luau check_plus1.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
require("./emu/hudcheck").run({
	game = "plus1-jump",
	bundle = require("./build/plus1-jump"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
})
