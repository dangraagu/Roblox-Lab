-- deep-vein — headless HUD fit check, with the strata row (Cave.client) on top of the HUD.
-- Run: luau check_deepvein_cave_hud.luau   (regenerate the bundle first: py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau)
--
-- Cave.client adds the band chip, the Rest button (tappable) and the hazard warning under the HUD's readout.
-- Measured here like every other control, at the ten viewports, with the panel-overlap rule ON. The
-- chip/button-against-the-HUD's-own-labels rule is in check_deepvein_cave.luau section 9.
require("./emu/hudcheck").run({
	overlap = true,
	game = "deep-vein",
	bundle = require("./build/deep-vein"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Cave.client" },
})
