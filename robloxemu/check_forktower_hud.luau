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
-- The drawers OPEN, and the Build Reveal card, are check_forktower_hud_open.luau; the HUD against the
-- player's own character is check_forktower_hud_play.luau.
--
-- NARROW LANDSCAPE PHONES (second review, 2026-09-30, finding 2). Every landscape viewport this file
-- measured was 640 px wide or more, and the row's move into the header needed about 617 px: below that it
-- stayed in the centred stack, over the avatar, and the ☰ Meny drawer (the only Rebirth button) came out
-- 1 px tall. 568x320 is the iPhone SE (1st gen) and iPod touch; 592x360 is a 360x640 dp Android phone
-- with its navigation bar at the side; 480x270 is the smallest the reviewer measured.
local HudCheck = require("./emu/hudcheck")
local viewports = {}
for _, v in HudCheck.VIEWPORTS do table.insert(viewports, v) end
for _, v in {
	{ name = "narrow landscape 610", w = 610, h = 343, touch = true },
	{ name = "Android landscape, side nav bar", w = 592, h = 360, touch = true },
	{ name = "iPhone SE landscape", w = 568, h = 320, touch = true },
	{ name = "narrow landscape 540", w = 540, h = 304, touch = true },
	{ name = "narrow landscape 520", w = 520, h = 292, touch = true },
	{ name = "narrow landscape 480", w = 480, h = 270, touch = true },
} do table.insert(viewports, v) end
HudCheck.run({
	viewports = viewports,
	overlap = true,
	game = "fork-tower",
	bundle = require("./build/fork-tower"),
	server = "server/Main.server",
	-- Board.client draws on a SurfaceGui under the tower's board, never in PlayerGui; it is loaded so anything it
	-- ever put on the screen would be measured here (check_forktower_board asserts it puts nothing there)
	clients = { "client/Hud.client", "client/Ambience.client", "client/Board.client" },
})
