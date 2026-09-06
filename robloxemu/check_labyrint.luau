-- Labyrinth Mariozo — headless HUD fit check. Run: luau check_labyrint.luau
-- Regenerate the bundle first:
--   py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau
--
-- This game has eleven client scripts, each with its own ScreenGui, so the check has to load
-- all of them: the panels only fight for the screen when they are all on it at once.
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
	},
})
