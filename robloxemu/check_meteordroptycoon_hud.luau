-- Meteor Drop Tycoon — the phone-first HUD fits, with the panel-overlap rule ON.
-- Run:  py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
--       luau check_meteordroptycoon_hud.luau 2>&1
--
-- hudcheck boots the real server and both client scripts (Hud.client draws the wallet, hopper, toast, hint,
-- Upgrades and the upgrade panel; Sky.client the band chip, Stargaze and the hazard warning) and measures
-- every piece at hudcheck's ten viewports, touch and mouse: nothing off screen, nothing tappable under the
-- thumbstick or the jump button, tap targets of 44 screen px, a canvas that reaches its last row, panels
-- covering at most half a phone, and (overlap = true) no two visible panels on top of each other.
--
-- The ten viewports run twice. The second pass puts the HUD in its busiest state first, through the real
-- paths: the Upgrades button opens the panel (and the column moves to its left edge), a Toast comes over the
-- real remote, the hint is the new player's first one, and the hazard warning is up. A sweep that only sees
-- the idle HUD scores every other mode as a pass (vault-runners' collapse timer sat on its wallet that way).
-- One frame is rendered (RenderStepped) after opening the panel, as Roblox would: Sky.client re-lays out on
-- the frame it sees the panel open.

local HudCheck = require("./emu/hudcheck")

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	table.insert(viewports, table.clone(v))
end

local function busy(h, plr)
	local pg = plr:FindFirstChild("PlayerGui")
	local hud = pg:FindFirstChild("MeteorHud"):FindFirstChild("Root")
	local sky = pg:FindFirstChild("MeteorSky"):FindFirstChild("Root")
	if not hud:FindFirstChild("UpgradePanel").Visible then
		hud:FindFirstChild("UpgradeSlot"):FindFirstChild("UpgradeButton").Activated:Fire()
	end
	h.game:GetService("RunService").RenderStepped:Fire(1 / 60)
	local remotes = h.ReplicatedStorage:FindFirstChild("MeteorRemotes")
	remotes:FindFirstChild("Toast"):FireClient(plr, "Hopper full! ★ Upgrade the Smelter, or wait a moment for it to melt.") -- the longest refusal (Economy.fullText)
	-- the warning as the frame shows it during a hazard (Sky.client hides it again on the next frame without one)
	local warning = sky:FindFirstChild("WarningPanel")
	warning:FindFirstChild("WarningText").Text = "⚠️ BOLIDE INCOMING: step out of the red ring"
	warning.Visible = true
	assert(hud:FindFirstChild("UpgradePanel").Visible, "the Upgrades button opened the panel")
	assert(hud:FindFirstChild("ToastPanel").Visible, "the toast is up")
	assert(hud:FindFirstChild("HintPanel").Visible, "the first hint is up")
end
for _, v in HudCheck.VIEWPORTS do
	local b = table.clone(v)
	b.name = v.name .. " +panel/toast/hint/warning"
	b.before = busy
	table.insert(viewports, b)
end

HudCheck.run({
	overlap = true,
	game = "meteor-drop-tycoon",
	bundle = require("./build/meteor-drop-tycoon"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Sky.client" },
	viewports = viewports,
})
