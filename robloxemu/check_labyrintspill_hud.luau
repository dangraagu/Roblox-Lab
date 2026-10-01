-- Labyrinth Mariozo — the stock HUD fit gate (emu/hudcheck) with the eye-candy clients loaded too.
-- Run: luau check_labyrintspill_hud.luau   (rebuild the bundle first, see check_labyrint.luau)
--
-- check_labyrint.luau is the game's own gate and lists the eleven client scripts the game had before
-- the biomes. This runs the SAME gate, same options, with all thirteen: the two new ScreenGuis
-- (LabyrintBiome, LabyrintBreak) must fit every viewport the gate knows, and adding them must not push
-- anything else out. Their text labels start hidden, so check_labyrintspill_layout.luau measures them
-- again with each one shown.
-- NOT opted in to panel-overlap rule 4b here, for the reason check_labyrint.luau gives (emu/hudcheck counts a
-- ScreenGui with Enabled = false as shown and ignores UISizeConstraint; measured 2026-10-01 with overlap = true: 13
-- reported overlaps, every one of them one of those two artifacts). The rule IS asserted for this game, with both
-- corrected, by check_labyrintspill_overlap.luau (the lobby, a run, the minimap, the Hjelp meg offer; ten viewports).
-- The transient cards are held apart by check_labyrintspill_cards and _popups.
require("./emu/hudcheck").run({
	game = "labyrint-spill",
	bundle = require("./build/labyrint-spill"),
	server = "server/MazeGame.server",
	clients = {
		"client/HudClient.client",
		"client/MinimapClient.client",
		"client/LeaderboardClient.client",
		"client/AssistClient.client",
		"client/AdminBroadcastClient.client",
		"client/ShopClient.client",
		"client/PerkClient.client",
		"client/LobbyClient.client",
		"client/GodModeClient.client",
		"client/LightingClient.client",
		"client/SoundClient.client",
		"client/Biome.client",
		"client/RestClient.client",
		"client/BoardClient.client",
	},
})
