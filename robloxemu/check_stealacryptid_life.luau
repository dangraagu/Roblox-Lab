-- Steal a Cryptid - the night stays ALIVE: pooled critters keep coming back around the player.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_life.luau 2>&1
--
-- Critters (crows, bats, wisps, tumbleweeds...) are pooled: a critter that leaves its ring around the
-- camera is recycled and a new one spawns on the ring. Part counts cannot see a pool that never recycles
-- (the mutation sweep switched recycling off and every other suite stayed green: the critters simply
-- flew away and the sky went empty, at the same part count). This file counts the critters actually IN
-- RANGE of the camera (inside the pool's own ring, 1.35 x rMax: where a critter is recycled), once a
-- second, for a player who stays put:
--   1. at home at moonrise (six bats) for 90 s;
--   2. in the Badlands camp (three tumbleweeds, two bats) for 25 s;
--   3. at home at mythic night (meteors streak far overhead) for 60 s.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-life", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local W = Config.World
local C = Config.Night.Critters
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 3303
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "dogman", jar = 0 }
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 20000000, savedAt = NOW, cagesUnlocked = 3, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
-- no hazards in this file: nothing may knock the watcher about
local GameHz = h:_require(h.ReplicatedStorage:FindFirstChild("Config")).Night.Hazards
GameHz.IntervalMin, GameHz.IntervalMax = 100000, 100001
local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Watcher", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Night.client"))
local folder = h.workspace:FindFirstChild("CryptidNight")
local cam = h.workspace.CurrentCamera
local function st()
	local sent = remotes.State:sentTo(plr)
	return sent[#sent].args[1]
end

local function inRange(partName, spec)
	local n = 0
	local c = cam.CFrame.Position
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and d.Name == partName then
			local dx, dz = d.Position.X - c.X, d.Position.Z - c.Z
			if math.sqrt(dx * dx + dz * dz) <= spec.rMax * 1.35 then n += 1 end
		end
	end
	return n
end
-- run `seconds`; sample `partName` in range once a second after `warm` seconds; return the minimum
local function watch(seconds, warm, partName, spec)
	local lo, hi, samples = math.huge, 0, {}
	for i = 1, math.floor(seconds * 30 + 0.5) do
		local p = hrp.Position
		cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p)
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
		if i % 30 == 0 and i / 30 > warm then
			local n = inRange(partName, spec)
			lo, hi = math.min(lo, n), math.max(hi, n)
			table.insert(samples, n)
		end
	end
	return lo, hi, samples
end

-- 1. home, moonrise: six bats around a player who stands still (idle rest does not stop critters)
do
	local lo, hi = watch(90, 6, "BatBody", C.bat)
	print(string.format("  home, moonrise, 90 s standing still: bats in range %d..%d of 6", lo, hi))
	truthy(lo >= 3, "1: bats keep coming back around the player for 90 s (never fewer than 3 of 6 in range; " .. lo .. ")")
end

-- 2. the Badlands camp: tumbleweeds roll past outside its fences for the whole raid
do
	local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. st().plot)
	local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
	hrp.CFrame = CFrame.new(frameCF:PointToWorldSpace(Vector3.new(W.Apron.Board.x, W.RootHeight, W.Apron.Board.z - 4)))
	watch(0.2, 99, "x", C.bat)
	remotes.Hunt:simulateFireServer(plr, 1)
	h:advance(0.05)
	local lo, hi = watch(25, 6, "Tumbleweed", C.tumbleweed)
	print(string.format("  Badlands camp, 25 s at the gate: tumbleweeds in range %d..%d of 3", lo, hi))
	truthy(lo >= 2, "2: tumbleweeds keep rolling past the camp for the whole visit (never fewer than 2 of 3; " .. lo .. ")")
	remotes.LeaveCamp:simulateFireServer(plr)
	h:advance(0.05)
	watch(Config.Raid.RestartCooldownSeconds + 0.5, 99, "x", C.bat)
end

-- 3. home, mythic night: meteors streak across far overhead, again and again
do
	local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. st().plot)
	local lair = plot.Lair
	local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
	local ranks = 0
	for _ = 1, 2 do -- P3 twice: Legendary, then Mythic
		hrp.CFrame = CFrame.new(frameCF:PointToWorldSpace(Vector3.new(W.Apron.P3.x, W.RootHeight, W.Apron.P3.z - 4)))
		lair.Pedestals.Pedestal_3.Buy.Triggered:Fire(plr)
		watch(3, 99, "x", C.bat)
		ranks = st().rank
	end
	truthy(ranks == 4, "3: bought up to the Mythic (rank " .. tostring(ranks) .. ")")
	hrp.CFrame = CFrame.new(frameCF:PointToWorldSpace(Vector3.new(36, W.RootHeight, 4)))
	local lo, hi, samples = watch(60, 8, "Meteor", C.meteor)
	local seen = 0
	for _, n in samples do if n > 0 then seen += 1 end end
	print(string.format("  home, mythic night, 60 s: meteors in range %d..%d of 3; seconds with a meteor up: %d of %d", lo, hi, seen, #samples))
	truthy(seen >= #samples * 0.8, "3: meteors keep streaking overhead (one up in " .. seen .. " of " .. #samples .. " seconds)")
end

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid life: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid life check failed", 0) end
