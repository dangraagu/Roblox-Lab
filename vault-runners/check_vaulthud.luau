-- Vault Runners — headless HUD fit check, every viewport TWICE: once in the hub, once mid-run.
-- Run: luau check_vaulthud.luau   (regenerate the bundle first, see check_vaultrunners.luau)
--
-- Most Roblox players are on a phone. A HUD authored in fixed pixels against a desktop window is
-- unusable there, and that is not a small blemish — a player told this repo that Grow a Crystal's
-- UI "covers the entire screen and it's impossible to move or do anything". This asserts, per
-- viewport, that nothing visible hangs off the screen, nothing tappable sits under Roblox's own
-- thumbstick or jump button, every ScrollingFrame's canvas reaches its content, no two panels sit
-- on top of each other, and the panels cover at most half a phone.
--
-- WHY EVERY VIEWPORT IS RUN TWICE. This HUD has two states. In the hub it shows a wallet, a vault
-- list and a pet list; mid-run it hides all three and shows a collapse timer instead. The timer
-- is created with `Visible = false` and only a Run "start" remote turns it on — and this gate had
-- never fired one. So the timer was never measured, at any viewport, and the gate printed PASS on
-- a 414x800 phone where the timer covered 109 design px of the wallet: the gem count and pet
-- multiplier, underneath the clock, during the only part of the game that matters. An adversarial
-- review found it by computing the layout by hand from the source.
--
-- The `before` hook on each viewport entry is what puts the HUD into the state that entry is
-- meant to measure. Nothing here reads the game's own layout code: it fires the same remotes the
-- server fires, and then the gate measures whatever the HUD did about it.

local HudCheck = require("../robloxemu/emu/hudcheck")

-- The RemoteEvent payloads below are the server's, copied in shape only — a real run's start
-- event, and the "end" that puts the HUD back in the hub. Firing the remote (rather than poking
-- `timer.Visible`) is the point: it exercises the HUD's own handler, so a HUD that stopped
-- showing its timer altogether would fail here rather than pass by being invisible.
local function enterRun(h, player)
	local remotes = h.services.ReplicatedStorage:FindFirstChild("VaultRemotes")
	remotes:FindFirstChild("Run"):FireClient(player, "start", {
		tier = 3, tierName = "Gold Vault", emoji = "🥇",
		floor = 12, collapseSeconds = 258, gems = 30, storeys = 5, mult = 1.65,
	})
	-- ...and a tick, because the timer's text is what the tick paints. A panel measured before
	-- its widest content arrives is a panel measured too small.
	remotes:FindFirstChild("Run"):FireClient(player, "tick", {
		timeLeft = 258, carried = 660, collected = 30, total = 30, progress = 0.0,
	})
end

local function leaveRun(h, player)
	local remotes = h.services.ReplicatedStorage:FindFirstChild("VaultRemotes")
	remotes:FindFirstChild("Run"):FireClient(player, "end", {
		ok = true, reason = "escaped", banked = 1089, carried = 660,
		time = 120, floor = 12, tier = 3,
	})
end

-- The shared list plus one more, added here rather than to HudCheck.VIEWPORTS so no other game's
-- gate changes: 360x640 is the narrowest phone worth supporting, and it is where this HUD's
-- top-edge collision was WORST — design width 600, so the wallet and the timer had even less
-- room to share than on the 414x800 the review measured.
local EXTRA = { { name = "narrow phone", w = 360, h = 640, touch = true } }

local viewports = {}
for _, v in ipairs(EXTRA) do
	table.insert(viewports, { name = v.name, w = v.w, h = v.h, touch = v.touch, before = leaveRun })
	table.insert(viewports, {
		name = v.name .. ", mid-run", w = v.w, h = v.h, touch = v.touch, before = enterRun,
	})
end
for _, v in ipairs(HudCheck.VIEWPORTS) do
	-- Hub first, then the same viewport mid-run. Order matters for the same reason the
	-- mouse/touch pairs in HudCheck.VIEWPORTS are ordered: the second entry of a pair is
	-- measured against state the first one left behind, which is the direction that fails.
	table.insert(viewports, { name = v.name, w = v.w, h = v.h, touch = v.touch, before = leaveRun })
	table.insert(viewports, {
		name = v.name .. ", mid-run", w = v.w, h = v.h, touch = v.touch, before = enterRun,
	})
end

HudCheck.run({
	game = "vault-runners",
	bundle = require("../robloxemu/build/vault-runners"),
	server = "server/Main.server",
	clients = { "client/Hud.client" },
	viewports = viewports,
	overlap = true,
})
