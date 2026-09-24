-- fork-tower — headless HUD fit check, with the ambience row. Run: luau check_forktower_hud.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- Measured before the environment work (2026-09-23, Hud.client alone, overlap on): PASS at all ten
-- viewports. Ambience.client puts the band chip and the ☕ Hvil button (tappable) into the row the
-- HUD reserves under the toast (Hud.client.luau `AmbienceRow`), so both scripts are loaded and every
-- control is measured: tap size, the thumbstick and jump corners, off-screen, and panel overlap.
--
-- This pass measures the drawers CLOSED. A phone then shows no side panel, and on every wider screen
-- the side panels stand at the edges, clear of the centred row, so the row can never meet one here.
-- The drawers OPEN are check_forktower_hud_menu.luau and check_forktower_hud_top.luau (one Harness
-- per process, so one file each).
require("./emu/hudcheck").run({
	overlap = true,
	game = "fork-tower",
	bundle = require("./build/fork-tower"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Ambience.client" },
})
