-- Steal a Cryptid - the night's band title card never lands on an open panel or on the HUD's lines.
-- Through the REAL server, the REAL HUD and the REAL night client, on a landscape phone (800x360, touch).
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_card.luau 2>&1
--
-- Second review of the night, 2026-09-30, finding 4. The card is a TextLabel in the night's own ScreenGui, so
-- hudcheck's overlap rule (depth-2 Frames of one gui) never saw it. The reviewer's reachable flow: open the Hunt
-- panel with the top-right toggle, walk to P3, buy a Rare: MOONRISE was drawn over the open Hunt panel for 129
-- of 150 frames (up to 10 598 screen px^2 on this phone). Now:
--   C1 a band reached while a panel is open waits: the card never shows while the Hunt panel is open;
--   C2 it shows once the panel is closed (the band is still named, not lost);
--   C3 while it shows, it overlaps nothing the HUD draws;
--   C4 a panel opened while the card shows hides the card at once.
-- check_stealacryptid_nighthud.luau holds the card's PLACE to the same overlap rule in all ten viewports.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-card", viewport = { 800, 360 }, touch = true })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local W = Config.World
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 7707
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "jackalope", jar = 0 }
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 1000000, savedAt = os.time(), cagesUnlocked = 3, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope" }, stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end
assert(h:tryRun("server/Main.server"))
h:advance(1)
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("Buyer", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Grass
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Night.client"))
local remState = h.ReplicatedStorage:FindFirstChild("CryptidRemotes"):FindFirstChild("State")
local function st()
	local sent = remState:sentTo(plr)
	return sent[#sent].args[1]
end
local function frames(s)
	for _ = 1, math.max(1, math.floor(s * 30 + 0.5)) do
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
	end
end
local hud = plr.PlayerGui.CryptidHud.Root
local nroot = plr.PlayerGui.CryptidNight.Root
local cam = h.workspace.CurrentCamera

local function overlapsHud()
	local w, hh = cam.ViewportSize.X, cam.ViewportSize.Y
	local cards = {}
	for _, r in h:guiRects(plr.PlayerGui.CryptidNight, w, hh) do
		if r.shown and (r.name == "Card" or r.name == "CardSub") and tostring(r.obj.Text or "") ~= "" then table.insert(cards, r) end
	end
	local worst, what = 0, nil
	for _, r in h:guiRects(plr.PlayerGui.CryptidHud, w, hh) do
		local draws = false
		if r.shown and r.sw > 0 and r.sh > 0 then
			if r.class == "TextLabel" or r.class == "TextButton" then
				draws = tostring(r.obj.Text or "") ~= "" or (r.obj.BackgroundTransparency or 1) < 1
			elseif r.class == "Frame" or r.class == "ScrollingFrame" then
				draws = (r.obj.BackgroundTransparency or 1) < 1
			end
		end
		if draws then
			for _, c in cards do
				local ox = math.min(c.sx + c.sw, r.sx + r.sw) - math.max(c.sx, r.sx)
				local oy = math.min(c.sy + c.sh, r.sy + r.sh) - math.max(c.sy, r.sy)
				if ox > 1 and oy > 1 and ox * oy > worst then worst, what = ox * oy, c.name .. " over " .. r.name end
			end
		end
	end
	return worst, what
end

frames(6) -- the join card (DUSK) comes and goes
eq(nroot.Card.Visible, false, "the join card has gone after 6 s")
hud.Toggles.HuntToggle.Activated:Fire() -- open the Hunt panel from the top-right row
frames(0.2)
eq(hud.HuntPanel.Visible, true, "the Hunt panel is open")
local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. st().plot)
local ped = plot.Lair.Pedestals.Pedestal_3
hrp.CFrame = CFrame.new(ped.Position + Vector3.new(0, 1.5, -4)) -- in front of P3, inside its prompt reach
frames(0.2)
ped.Buy.Triggered:Fire(plr)
local shownOverPanel = 0
for _ = 1, 150 do
	frames(1 / 30)
	if hud.HuntPanel.Visible and nroot.Card.Visible then shownOverPanel += 1 end
end
eq(st().rank, 2, "the Rare raised the Journal's rank to 2 (Moonrise)")
eq(hud.HuntPanel.Visible, true, "the Hunt panel stayed open through the purchase")
eq(shownOverPanel, 0, "C1: the band card never showed over the open Hunt panel (150 frames)")

hud.Toggles.HuntToggle.Activated:Fire() -- close it
local appeared = nil
for i = 1, 30 do
	frames(1 / 30)
	if nroot.Card.Visible and nroot.Card.Text ~= "" then appeared = i; break end
end
eq(hud.HuntPanel.Visible, false, "the Hunt panel is closed")
truthy(appeared ~= nil, "C2: the band card showed once the panel closed (frame " .. tostring(appeared) .. ")")
eq(nroot.Card.Text, "MOONRISE", "C2: naming the band reached while the panel was open")
local worst, what = 0, nil
for _ = 1, 30 do
	frames(1 / 30)
	if nroot.Card.Visible then
		local a, w = overlapsHud()
		if a > worst then worst, what = a, w end
	end
end
eq(worst, 0, "C3: while it shows, the card overlaps nothing the HUD draws (" .. tostring(what) .. ")")
truthy(nroot.Card.Visible, "the card is still up 1 s later (it stays about 4 s)")
hud.Toggles.HuntToggle.Activated:Fire() -- open the panel over the card
frames(1 / 30)
eq(hud.HuntPanel.Visible, true, "the Hunt panel opened again")
eq(nroot.Card.Visible, false, "C4: opening a panel hides the card at once")
local again = 0
for _ = 1, 150 do
	frames(1 / 30)
	if nroot.Card.Visible then again += 1 end
end
eq(again, 0, "C4: and it does not come back over the panel")

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end
print(string.format("\nsteal a cryptid card: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid card check failed", 0) end
