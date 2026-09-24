-- Grow a Crystal — headless HUD fit check. Run: luau check_crystal.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
require("./emu/hudcheck").run({
	-- Panel-overlap rule 4b: forced on 2026-09-17, zero overlaps at every viewport, so it is asserted.
	overlap = true,
	game = "grow-a-crystal",
	bundle = require("./build/grow-a-crystal"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
})
