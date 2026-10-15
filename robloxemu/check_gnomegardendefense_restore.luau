-- Gnome Garden Defense: a saved garden that comes back LATE celebrates nothing (REVIEW-2, reach finding 4).
-- Run:  py -3 wrap.py --game ../gnome-garden-defense --out build/gnome-garden-defense.luau
--       luau check_gnomegardendefense_restore.luau
--
-- B1 (REVIEW-1's build pass) made a Frost gardener's JOIN quiet: the first published Progress of the session only
-- names the band. REVIEW-2 reached the same brag through the retry path: when the first profile read fails, the
-- garden starts on a Spring bed (Progress 0), the retry 2 s later restores chapter 4 and re-digs the bed at
-- Progress 30, and the client took that jump as reaching the HARVEST MOON: the golden flash, the 4.5 s card and the
-- 4.6 s look up at the moon, for a win from an earlier session. A new bed is never a reach: only progress played
-- within one attempt is. The real server and the real client scripts, on an 844x390 touch phone.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/gnome-garden-defense"), name = "gnome-garden-restore", viewport = { 844, 390 }, touch = true })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 9801
local store = h.game:GetService("DataStoreService"):GetDataStore("GnomeGarden_v1")
store:SetAsync("u_" .. UID, { data = { chapter = 4, bestWave = 30, bestAt = 1700000000, published = 30, tutorialDone = true } })
store.__failNext = true -- one DataStore blip: the join's read fails, the retry 2 s later gets the record
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
local me = h:join("Frosty", UID)
local char = h.Players:simulateSpawn(me, h.workspace)
RunService:setIsServer(false)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.WoodPlanks
hum.MoveDirection = Vector3.new(0, 0, 0)
local flashes, pending = 0, {}
me.PlayerGui.ChildAdded:Connect(function(c) if c.Name == "FxFlash" then table.insert(pending, c) end end)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Garden.client"))
assert(h:tryRun("client/View.client"))
local garden
for _, g in h.workspace.Gardens:GetChildren() do
	if g:GetAttribute("Owner") == UID then garden = g end
end
assert(garden, "the garden")
local state = me.PlayerGui:FindFirstChild("GardenClientState")
local sky = me.PlayerGui.GardenSky.Root
local cards, skyFrames, cardFrames, lastCard = {}, 0, 0, ""
local function frames(sec)
	for _ = 1, math.floor(sec / 0.1 + 0.5) do
		RunService.RenderStepped:Fire(0.1)
		h:advance(0.1)
		for _, gui in pending do
			local f = gui:FindFirstChildOfClass("Frame")
			local c = f and f.BackgroundColor3
			if c and math.floor(c.R * 255 + 0.5) == 255 and math.floor(c.G * 255 + 0.5) == 236 and math.floor(c.B * 255 + 0.5) == 170 then
				flashes += 1
			end
		end
		table.clear(pending)
		if sky.BandCard.Visible then
			cardFrames += 1
			if sky.BandCard.Text ~= lastCard then
				lastCard = sky.BandCard.Text
				table.insert(cards, lastCard)
			end
		end
		if state:GetAttribute("ViewMode") == "sky" then skyFrames += 1 end
	end
end

frames(1)
eq(garden:GetAttribute("Chapter"), 1, "(precondition) the failed read put the gardener on a Spring bed first")
eq(garden:GetAttribute("Progress"), 0, "(at Progress 0)")
frames(10)
eq(garden:GetAttribute("Chapter"), 4, "the retry restored the save: the garden is Frost now")
eq(garden:GetAttribute("Progress"), 30, "on Progress 30, the HARVEST MOON's band")
eq(state:GetAttribute("Band"), "moon", "and the client is in that band")
local said = {}
for _, rec in h.ReplicatedStorage.GardenRemotes.Toast:sentTo(me) do said[tostring(rec.args[1])] = true end
truthy(said["Your saved garden is back: Frost."], "the gardener is told their garden is back")
eq(flashes, 0, "but the restore celebrates nothing: no golden flash")
eq(skyFrames, 0, "and the view does not look up at the moon")
truthy(cardFrames <= 39, string.format("the band's card is a quiet one, 3.8 s at most (%.1f s)", cardFrames * 0.1))
print("  cards: " .. table.concat(cards, " | "))

for _, e in h:errors() do print("SCHEDULER ERROR: " .. e) end
eq(#h:errors(), 0, "no thread died")
print(("gnome garden restore: %d passed, %d failed"):format(passed, failed))
