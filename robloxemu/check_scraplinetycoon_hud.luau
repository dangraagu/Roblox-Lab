-- Scrapline Tycoon — the phone-first HUD fits, with the panel-overlap rule ON.
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon_hud.luau 2>&1
--
-- hudcheck boots the real server and both client scripts (Hud.client draws the wallet, alert, toast, hint, column
-- slots 1 and 3 and the line panel; Yard.client the band chip, ☕ Break (slot 2) and the hazard warning) and
-- measures every piece at hudcheck's ten viewports, touch and mouse: nothing off screen, nothing tappable under the
-- thumbstick or the jump button, tap targets of 44 screen px, panels covering at most half a phone, and
-- (overlap = true) no two visible panels on top of each other.
--
-- The ten viewports run THREE times, each time in a different mode reached through the real paths:
--   1. idle, right after the join (the one-tap Build Shredder button and the first hint);
--   2. busy: the Shredder built through the Build button, the line panel opened by its own button (the column moves
--      to its left edge; one RenderStepped frame lets Yard.client follow), a Toast over the real remote, the alert
--      line up (a sputter is reported in the State), the hint, and the hazard warning;
--   3. the recycle confirmation: a line that ships rockets, ♻ tapped, so slots 1 and 3 ask again.
-- A sweep that only sees the idle HUD scores every other mode as a pass (vault-runners' collapse timer sat on its
-- wallet that way).

local HudCheck = require("./emu/hudcheck")

local function hudRoot(plr)
	return plr:FindFirstChild("PlayerGui"):FindFirstChild("ScraplineHud"):FindFirstChild("Root")
end
local function yardRoot(plr)
	return plr:FindFirstChild("PlayerGui"):FindFirstChild("ScraplineYard"):FindFirstChild("Root")
end

local seeded = false
local function seedReadyLine(h)
	-- a returning player whose line already ships rockets above the recycle bar, for the confirm mode
	if seeded then return end
	seeded = true
	local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")
	local full = {}
	for _, id in { "shredder", "furnace", "press", "cutter", "assembler", "rocketbay" } do full[id] = { n = 2, L = 31, j = 0 } end
	store:SetAsync("u_5551212", { data = { v = 1, cash = 1e9, stations = full, jamIn = 200, tier = 6, bolts = 0, boltsAt = 0, tutorial = 4 } })
end

local function busy(h, plr)
	local hud = hudRoot(plr)
	local yard = yardRoot(plr)
	local remotes = h.ReplicatedStorage:FindFirstChild("ScraplineRemotes")
	-- leave the confirm mode if a previous viewport left it on
	if hud:FindFirstChild("ConfirmCard").Visible then hud.RecycleSlot.RecycleButton.Activated:Fire() end
	if not hud:FindFirstChild("LinePanel").Visible then
		hud:FindFirstChild("LineSlot"):FindFirstChild("LineButton").Activated:Fire()
	end
	h.game:GetService("RunService").RenderStepped:Fire(1 / 60)
	remotes:FindFirstChild("Toast"):FireClient(plr, "Recycling needs your save, and it is not being saved this session. Rejoin to recycle.") -- the longest refusal
	-- the alert and the warning as the client shows them during a sputter and a hazard
	local alert = hud:FindFirstChild("AlertPanel")
	alert:FindFirstChild("AlertText").Text = "⚠ Rocket Bay sputtering: Fix 0:12"
	alert.Visible = true
	local warning = yard:FindFirstChild("WarningPanel")
	warning:FindFirstChild("WarningText").Text = "⚠️ CRANE DROP: DROPPED PARCEL. Step out of the red ring"
	warning.Visible = true
	assert(hud:FindFirstChild("LinePanel").Visible, "the Line button opened the panel")
	assert(hud:FindFirstChild("ToastPanel").Visible, "the toast is up")
	local rows = 0
	for _, r in hud.LinePanel:GetChildren() do
		if string.sub(r.Name, 1, 4) == "Row_" and r.Visible then rows += 1 end
	end
	assert(rows >= 1, "the panel shows its station rows")
end

local function confirm(h, plr)
	local hud = hudRoot(plr)
	if hud:FindFirstChild("LinePanel").Visible then hud.LineSlot.LineButton.Activated:Fire() end
	if not hud:FindFirstChild("ConfirmCard").Visible then hud.RecycleSlot.RecycleButton.Activated:Fire() end
	h.game:GetService("RunService").RenderStepped:Fire(1 / 60)
	assert(hud:FindFirstChild("ConfirmCard").Visible, "the ♻ button asks again (the line ships enough rockets)")
	assert(hud.LineSlot.LineButton.Text == "✓ Recycle!", "slot 1 is the confirm")
	assert(hud.RecycleSlot.RecycleButton.Text == "✕ Not yet", "slot 3 is the way out")
end

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	table.insert(viewports, table.clone(v))
end
for _, v in HudCheck.VIEWPORTS do
	local b = table.clone(v)
	b.name = v.name .. " +panel/toast/alert/hint/warning"
	b.before = busy
	table.insert(viewports, b)
end
for _, v in HudCheck.VIEWPORTS do
	local b = table.clone(v)
	b.name = v.name .. " +recycle confirm"
	b.before = confirm
	table.insert(viewports, b)
end

-- hudcheck joins its own player (5551212) after the server loads, with a fresh profile. The warmup makes that same
-- player leave, writes a returning profile whose line already ships rockets past the recycle bar, and brings the
-- SAME Player object back (PlayerAdded again, as a rejoin), so the client scripts that hold it keep running and the
-- ♻ slot is measured in every mode.
HudCheck.run({
	overlap = true,
	game = "scrapline-tycoon",
	bundle = require("./build/scrapline-tycoon"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Yard.client" },
	viewports = viewports,
	warmup = function(h, plr)
		h:leave(plr)
		h:advance(1)
		seedReadyLine(h)
		plr.Parent = h.Players
		h.Players.PlayerAdded:Fire(plr)
		h:advance(1)
		local hud = hudRoot(plr)
		assert(hud.RecycleSlot.Visible, "the returning line has a Rocket Bay: the ♻ slot shows")
		assert(string.find(hud.RecycleSlot.RecycleButton.Text, "★", 1, true) ~= nil, "and its rocket rate clears the bar: " .. hud.RecycleSlot.RecycleButton.Text)
	end,
})
