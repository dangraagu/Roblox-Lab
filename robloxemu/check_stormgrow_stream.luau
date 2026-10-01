-- StormGrow — tiles that arrive or leave after the client started (REVIEW-1 B4).
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_stream.luau 2>&1
--
-- The place pins Workspace.StreamingEnabled = false (default.project.json; tests/project_spec.py checks it). This
-- file is the second line: if a published place streams anyway (a Studio default, a later edit), a farm that
-- streams in after Farm.client started must still get its crops and be tappable, and a tile that streams out
-- must not leave its crop floating in the air. robloxemu does not stream, so streaming is played by hand: a farm
-- model is taken out of the workspace before the client starts and put back later, and one tile part is taken
-- out and put back (Roblox streams a part back in as a NEW instance; the check does that too, with a clone).

local Harness = require("./emu/harness")
local Aim = require("../stormgrow/tests/Aim")
local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-stream", viewport = { 800, 360 }, touch = true })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
mod("Config").Weather.ClockOffsetSeconds = (1000 - os.time() % 3600) % 3600 -- :16:40, clear for 200 s

local store = h.services.DataStoreService:GetDataStore("StormGrow_v1")
local T0 = os.time()
-- two farmers with field 1 planted (ripe Corn) so there is something to draw
for _, uid in { 7101, 7102 } do
	local tiles = {}
	for t = 1, 9 do tiles["1_" .. t] = { c = "corn", at = T0 - 5000, m = 0 } end
	store:SetAsync("u_" .. uid, { v = 1, coins = 100, harvested = 900, fields = 1, unlocked = 3, selected = "corn",
		tiles = tiles, almanac = {}, almanacCount = 0, almanacAt = 0, harvests = 40 })
end

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
h.game:GetService("RunService"):setIsServer(false)
local Config, Farm = mod("Config"), mod("Farm")
local far = h:join("FarAway", 7101) -- slot 1: the farm that streams in late
h:advance(0.3)
local me = h:join("Viewer", 7102) -- slot 2, the LocalPlayer
local char = h.Players:simulateSpawn(me, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Grass
local S = far:GetAttribute("Slot")
local farms = h.workspace.Farms
local farFarm = farms["Farm_" .. S]

-- the far farm is NOT streamed in when the client starts
farFarm.Parent = nil
for _, key in { "client/Hud.client", "client/Farm.client", "client/Sky.client" } do
	assert(h:tryRun(key))
end
local RunService = h.game:GetService("RunService")
local function frames(n)
	for _ = 1, n do
		RunService.RenderStepped:Fire(0.1)
		h:advance(0.1)
	end
end
frames(10)
local crops = h.workspace.StormCrops
local function cropFolders(slot)
	local n = 0
	for _, f in crops:GetChildren() do
		if string.match(f.Name, "^Crop_" .. slot .. "_") then n += 1 end
	end
	return n
end
eq(cropFolders(S), 0, "set-up: the far farm is not in the workspace, so nothing is drawn on it")
eq(cropFolders(me:GetAttribute("Slot")), 9, "set-up: your own farm's nine Corn are drawn")

--============================================================ 1. a farm that streams in later gets its crops

farFarm.Parent = farms
frames(5)
eq(cropFolders(S), 9, "the far farm's nine Corn are drawn once it streams in")

--============================================================ 2. and its tiles answer taps

local aim = Aim.new(h, { touch = true })
local answered = {}
RS.StormRemotes.Tap.OnServerEvent:Connect(function(_p, slot, key) table.insert(answered, { slot = slot, key = key }) end)
do
	local pos, facing = aim:standFor(Farm, Config.Farm, S, 1)
	hrp.CFrame = CFrame.new(pos)
	local ok = aim:tapTile(S, "1_5", pos, facing)
	h:advance(0.05)
	truthy(ok, "set-up: the streamed-in tile 1_5 is on screen")
	eq(#answered == 1 and answered[1].slot == S and answered[1].key == "1_5", true, "a tap on a streamed-in tile reaches the server as that tile")
end

--============================================================ 3. a tile that streams out takes its crop with it

local tilePart = farFarm.Tiles.Tile_1_5
tilePart.Parent = nil
frames(3)
eq(crops:FindFirstChild("Crop_" .. S .. "_1_5"), nil, "a tile streamed out leaves no crop floating in the air")
eq(cropFolders(S), 8, "the other eight stay")

--============================================================ 4. streamed back in as a new instance: drawn once, tappable

local again = tilePart:Clone()
again.Parent = farFarm.Tiles
frames(3)
eq(cropFolders(S), 9, "streamed back in (a new instance), its Corn is drawn again, once")
do
	table.clear(answered)
	local pos, facing = aim:standFor(Farm, Config.Farm, S, 1)
	local ok = aim:tapTile(S, "1_5", pos, facing)
	h:advance(0.05)
	truthy(ok and #answered == 1 and answered[1].key == "1_5", "and its tap reaches the server once")
end

--============================================================ 5. a replanted tile keeps ONE crop folder

-- (found while writing this file: every replant built a new Crop_<slot>_<key> folder and left the old one behind,
-- empty, so a long session piled up one empty Folder per harvest, and a lookup by name could find a stale one)
do
	local mySlot = me:GetAttribute("Slot")
	local hb = farms["Farm_" .. mySlot].Tiles.Tile_1_1
	local at0 = hb:GetAttribute("PlantedAt")
	hrp.CFrame = CFrame.new(aim:standFor(Farm, Config.Farm, mySlot, 1)) -- back home, within reach
	h:advance(0.3)
	RS.StormRemotes.Tap:simulateFireServer(me, mySlot, "1_1") -- ripe Corn: harvested and replanted by the server
	frames(3)
	truthy(hb:GetAttribute("PlantedAt") ~= at0, "set-up: the server harvested and replanted the tile")
	-- two more replants, written by hand as the server writes them (a new PlantedAt is what the client redraws on)
	for i = 1, 2 do
		hb:SetAttribute("PlantedAt", hb:GetAttribute("PlantedAt") + i)
		frames(3)
	end
	local named = 0
	for _, f in crops:GetChildren() do
		if f.Name == "Crop_" .. mySlot .. "_1_1" then named += 1 end
	end
	eq(named, 1, "after three replants the tile has exactly one crop folder")
end

print("")
for _, w in h.warnings do
	print("warning: " .. w)
	if string.find(w, "frame error", 1, true) then failed += 1 end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow stream: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow stream check failed", 0) end
