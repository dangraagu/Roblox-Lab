-- plus1-jump — headless HUD fit check. Run: luau check_plus1.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
require("./emu/hudcheck").run({
	-- Panel-overlap rule 4b: forced on 2026-09-17, zero overlaps at every viewport, so it is asserted.
	overlap = true,
	game = "plus1-jump",
	bundle = require("./build/plus1-jump"),
	server = "server/Main.server",
	-- Sky.client adds the band chip, the Rest button (tappable) and the hazard warning to the top row;
	-- measured here like every other control. Its no-overlap-with-the-HUD rule: check_plus1_sky.luau.
	-- Board.client (2026-09-30) draws the Top Climbers board on its part in the world, never in PlayerGui, so it adds
	-- nothing to measure here; it is loaded so a change that puts it on screen is measured like everything else.
	clients = { "client/Hud.client", "client/Sky.client", "client/Board.client" },
})
