-- Outpost Zero — the phone-first HUD fits, with the panel-overlap rule ON.
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_hud.luau 2>&1
--
-- hudcheck boots the real server and both client scripts (Hud.client draws credits, the balance bar, the Orders
-- chip, the ★ line, toasts, the hint and ★ Show me; Sky.client the band chip, ☕ Break, the hazard warning and the
-- title card) and measures every piece at hudcheck's ten viewports, touch and mouse: nothing off screen, nothing
-- tappable under the thumbstick or the jump button, tap targets of 44 screen px, panels covering at most half a
-- phone, and (overlap = true) no two visible panels on top of each other.
--
-- The ten viewports run twice. The second pass puts the HUD in its busiest state first, through the real paths:
-- a Toast over the real remote with the longest sentence the server sends, the new player's first hint, the
-- hazard warning up and a title card showing. A sweep that only sees the idle HUD scores every other mode as a pass.
-- (adapted from check_meteordroptycoon_hud.luau)

local HudCheck = require("./emu/hudcheck")

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	table.insert(viewports, table.clone(v))
end

local function busy(h, plr)
	local pg = plr:FindFirstChild("PlayerGui")
	local hud = pg:FindFirstChild("OutpostHud"):FindFirstChild("Root")
	local sky = pg:FindFirstChild("OutpostSky"):FindFirstChild("Root")
	local remotes = h.ReplicatedStorage:FindFirstChild("CityRemotes")
	-- the longest sentence the server toasts (the foreign-lot refusal with a long display name)
	remotes:FindFirstChild("Toast"):FireClient(plr, "This is Maximilian_Overbuilder's city. Yours is the shelf with your name on it.")
	-- the warning as the frame shows it during a hazard (Sky.client hides it again on the next frame without one)
	local warning = sky:FindFirstChild("WarningPanel")
	warning:FindFirstChild("WarningText").Text = "⚠️ SPENT LANTERN INCOMING: step out of the red ring"
	warning.Visible = true
	local card = sky:FindFirstChild("BandCard")
	card.Text = "🏮 LANTERN DUSK · ⚓ SKYPORT OPEN!"
	card.Visible = true
	sky:FindFirstChild("BandCardSub").Visible = true
	assert(hud:FindFirstChild("ToastPanel").Visible, "the toast is up")
	assert(hud:FindFirstChild("HintPanel").Visible, "the first hint is up (a new player's tutorial step 0)")
	assert(hud:FindFirstChild("StarPanel").Visible ~= false, "the ★ line is up")
end
for _, v in HudCheck.VIEWPORTS do
	local b = table.clone(v)
	b.name = v.name .. " +toast/hint/warning/card"
	b.before = busy
	table.insert(viewports, b)
end

HudCheck.run({
	overlap = true,
	game = "outpost-zero",
	bundle = require("./build/outpost-zero"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Sky.client" },
	viewports = viewports,
})
