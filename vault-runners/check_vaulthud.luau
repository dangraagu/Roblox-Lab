-- Vault Runners — headless HUD fit check across six viewports, 414x800 phone to 1920x1080.
-- Run: luau check_vaulthud.luau   (regenerate the bundle first, see check_vaultrunners.luau)
--
-- Most Roblox players are on a phone. A HUD authored in fixed pixels against a desktop window is
-- unusable there, and that is not a small blemish — a player told this repo that Grow a Crystal's
-- UI "covers the entire screen and it's impossible to move or do anything". This asserts, per
-- viewport, that nothing visible hangs off the screen, nothing tappable sits under Roblox's own
-- thumbstick or jump button, every ScrollingFrame's canvas reaches its content, and the panels
-- cover at most half a phone.
require("../robloxemu/emu/hudcheck").run({
	game = "vault-runners",
	bundle = require("../robloxemu/build/vault-runners"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
})
