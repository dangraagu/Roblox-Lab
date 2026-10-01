-- deep-vein — headless HUD fit check, with the strata row (Cave.client) on top of the HUD.
-- Run: luau check_deepvein_cave_hud.luau   (regenerate the bundle first: py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau)
--
-- Cave.client adds the band chip, the Rest button (tappable) and the hazard warning under the HUD's readout.
-- Measured here like every other control, at the ten viewports, with the panel-overlap rule ON. The
-- chip/button-against-the-HUD's-own-labels rule is in check_deepvein_cave.luau section 9.
-- Review 2026-09-30, finding 5: the gate's ten viewports missed the phones where this row is tightest, so the
-- reviewer's phones are measured too.
local HudCheck = require("./emu/hudcheck")
local viewports = table.clone(HudCheck.VIEWPORTS)
for _, v in {
	{ name = "iPhone SE landscape", w = 568, h = 320, touch = true },
	{ name = "iPhone 8 landscape", w = 667, h = 375, touch = true },
	{ name = "Android 740x360", w = 740, h = 360, touch = true },
	{ name = "iPhone 12 landscape", w = 844, h = 390, touch = true },
	{ name = "iPhone 14 Pro Max landscape", w = 932, h = 430, touch = true },
	{ name = "iPhone 8 portrait", w = 375, h = 667, touch = true },
	{ name = "iPhone 12 portrait", w = 390, h = 844, touch = true },
	{ name = "Android portrait", w = 360, h = 800, touch = true },
} do
	table.insert(viewports, v)
end
HudCheck.run({
	viewports = viewports,
	overlap = true,
	game = "deep-vein",
	bundle = require("./build/deep-vein"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Cave.client" },
})
