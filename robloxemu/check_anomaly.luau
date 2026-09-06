-- anomaly-observatory — headless HUD fit check. Run: luau check_anomaly.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
require("./emu/hudcheck").run({
	game = "anomaly-observatory",
	bundle = require("./build/anomaly-observatory"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
})
