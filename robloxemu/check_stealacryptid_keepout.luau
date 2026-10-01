-- Steal a Cryptid - the camp KEEP-OUT guard, forced to work.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_keepout.luau 2>&1
--
-- Camp scenery must never hide a net or a snare: NightArt checks every part of a camp piece against
-- Night.keepOut (the camp grown by CampMargin, and the corridor behind the gate where the raider's camera
-- sits) when it is placed and on every animated frame, and leaves out any part that would reach in.
-- With the shipped numbers no piece ever reaches that close, so check_stealacryptid_night.luau only
-- proves the result, never the guard: the mutation sweep switched the guard off and every suite stayed
-- green. This file widens the keep-out IN MEMORY (the bundle's own Config: CampMargin 60, corridor 60
-- studs each side, 140 deep) so that static pieces (mesas, cacti, pines, redwoods) and the ANIMATED
-- Bigfoot glimpse in the redwood camp reach into it, and checks, on every frame of every camp:
--   * no parented local part's footprint enters the widened keep-out;
--   * the guard really did leave parts out (so this is not a vacuous pass);
--   * a part left out comes back when the keep-out shrinks again (the pieces are not simply lost).

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Night = require("../steal-a-cryptid/src/shared/Night")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-keepout", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local W = Config.World
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 4404
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "bigfoot", jar = 0 }
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 10000000, savedAt = NOW, cagesUnlocked = 3, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman", "nessie", "bigfoot" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local GameConfig = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
local shipped = { m = GameConfig.Night.CampMargin, w = GameConfig.Night.CameraCorridorHalfWidth, d = GameConfig.Night.CameraCorridorDepth }
local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Keeper", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(1, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Night.client"))
local folder = h.workspace:FindFirstChild("CryptidNight")
local cam = h.workspace.CurrentCamera

local CAMP_PARTS = { "Mesa", "MesaCap", "Cactus", "CactusArm", "RingPine", "RingPineTrunk", "Redwood", "RedwoodCrown", "Castle", "Glimpse", "Nessie" }
local function isCampPart(name)
	for _, pre in CAMP_PARTS do
		if string.sub(name, 1, #pre) == pre then return true end
	end
	return false
end

-- every parented part's world-aligned footprint (the same measure as check_stealacryptid_night.luau)
local inside, firstInside, framesChecked = 0, nil, 0
local function check(where)
	local slot = Night.pocketSlot(GameConfig, hrp.Position.X)
	if slot == nil then return end
	framesChecked += 1
	local ox = Night.pocketOriginX(GameConfig, slot)
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			local ex = math.abs(cf.RightVector.X) * s.X / 2 + math.abs(cf.UpVector.X) * s.Y / 2 + math.abs(cf.LookVector.X) * s.Z / 2
			local ey = math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
			local ez = math.abs(cf.RightVector.Z) * s.X / 2 + math.abs(cf.UpVector.Z) * s.Y / 2 + math.abs(cf.LookVector.Z) * s.Z / 2
			local lx = d.Position.X - ox
			if d.Position.Y + ey > -1.0 and not Night.boxClearOfCamp(GameConfig, lx - ex, lx + ex, d.Position.Z - ez, d.Position.Z + ez) then
				inside += 1
				firstInside = firstInside or string.format("%s at pocket-local (%.1f, %.1f) (%s)", d.Name, lx, d.Position.Z, where)
			end
		end
	end
end
local function count()
	local n = 0
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and isCampPart(d.Name) then n += 1 end
	end
	return n
end
local function run(seconds, where)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		local p = hrp.Position
		cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p)
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
		check(where)
	end
end

run(1, "home")
local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. remotes.State:sentTo(plr)[#remotes.State:sentTo(plr)].args[1].plot)
local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
local boardAt = frameCF:PointToWorldSpace(Vector3.new(W.Apron.Board.x, W.RootHeight, W.Apron.Board.z - 4))

local function camp(tier, secs)
	hrp.CFrame = CFrame.new(boardAt)
	run(0.2, "home")
	remotes.Hunt:simulateFireServer(plr, tier)
	h:advance(0.05)
	truthy(Night.pocketSlot(GameConfig, hrp.Position.X) ~= nil, "camp " .. tier .. ": in the pocket")
	run(secs, "camp " .. tier)
	local n = count()
	remotes.LeaveCamp:simulateFireServer(plr)
	h:advance(0.05)
	run(Config.Raid.RestartCooldownSeconds + 0.5, "home")
	return n
end

-- shipped keep-out: how many camp parts show in each camp (the baseline the widened run is compared to)
local shippedCount = {}
for tier = 1, #Config.Camps do shippedCount[tier] = camp(tier, 4) end
eq(inside, 0, "shipped keep-out: no part inside it (" .. tostring(firstInside) .. ")")

-- widened keep-out, in memory: static and animated pieces now reach into it
GameConfig.Night.CampMargin = 60
GameConfig.Night.CameraCorridorHalfWidth = 60
GameConfig.Night.CameraCorridorDepth = 140
inside, firstInside, framesChecked = 0, nil, 0
local widenedCount = {}
for tier = 1, #Config.Camps do widenedCount[tier] = camp(tier, 25) end
truthy(framesChecked > 30 * 90, "widened: " .. framesChecked .. " camp frames checked")
eq(inside, 0, "widened keep-out: no parented part ever inside it, static or animated (" .. tostring(firstInside) .. ")")
local left = 0
for tier = 1, #Config.Camps do
	left += shippedCount[tier] - widenedCount[tier]
	truthy(widenedCount[tier] <= shippedCount[tier], string.format("camp %d: %d camp parts shown widened, %d shipped", tier, widenedCount[tier], shippedCount[tier]))
end
truthy(left >= 5, "the guard really left parts out when the keep-out grew (" .. left .. " fewer camp parts shown)")
print(string.format("  camp parts shown, shipped vs widened keep-out: %s", (function()
	local t = {}
	for tier = 1, #Config.Camps do table.insert(t, string.format("camp %d %d -> %d", tier, shippedCount[tier], widenedCount[tier])) end
	return table.concat(t, ", ")
end)()))

-- shrink it back: the parts left out come back (nothing was destroyed)
GameConfig.Night.CampMargin = shipped.m
GameConfig.Night.CameraCorridorHalfWidth = shipped.w
GameConfig.Night.CameraCorridorDepth = shipped.d
local back = {}
for tier = 1, #Config.Camps do back[tier] = camp(tier, 4) end
for tier = 1, #Config.Camps do
	eq(back[tier], shippedCount[tier], "camp " .. tier .. ": every part left out came back at the shipped keep-out")
end

-- A critter is kept out by the box it DRAWS: Night.client tests each kind's centre with its own `reach` (3 studs by
-- default; the Jersey Devil's wings reach 6.1, so 7). One devil for a few seconds rarely flies near the keep-out
-- (sweep round 1: testing it by the 3-stud box survived every gate). Fifteen devils over the Pine Barrens for 60 s, in
-- memory, at the shipped keep-out, the camera orbiting: no part of any of them, wing tips included, ever enters it.
do
	local barrens = GameConfig.Night.Camp[2]
	local devil = nil
	for _, a in barrens.ambient do if a.kind == "devil" then devil = a end end
	truthy(devil ~= nil, "the Pine Barrens camp has the Jersey Devil")
	local count0 = devil and devil.count
	if devil then devil.count = 15 end
	inside, firstInside, framesChecked = 0, nil, 0
	local devilFrames = 0
	local function countDevils()
		for _, d in folder:GetChildren() do
			if d.Name == "DevilBody" then devilFrames += 1 end
		end
	end
	hrp.CFrame = CFrame.new(boardAt)
	run(0.2, "home")
	remotes.Hunt:simulateFireServer(plr, 2)
	h:advance(0.05)
	truthy(Night.pocketSlot(GameConfig, hrp.Position.X) ~= nil, "devils: in the Pine Barrens camp")
	-- Critters fly roughly tangent to a ring round the CAMERA (EnvBands.ambientSpawn), so with the camera at the gate a
	-- devil's wings point at the keep-out only near its far corners. The camera orbits the camp instead (radius 120,
	-- 60 up, one lap in 30 s), as a raider's zoomed-out camera may: then devils fly along the keep-out's edges with
	-- their wings toward it. Measured: the 3-stud box let wings in 23-27 times in 60 s; the devil's own reach, never.
	local ox = Night.pocketOriginX(GameConfig, Night.pocketSlot(GameConfig, hrp.Position.X))
	local centre = Vector3.new(ox + 36, 0, 56)
	for f = 1, 60 * 30 do
		local ang = f / (30 * 30) * math.pi * 2
		local camPos = centre + Vector3.new(math.sin(ang) * 120, 60, math.cos(ang) * 120)
		cam.CFrame = CFrame.lookAt(camPos, centre)
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
		check("barrens, 15 devils, the camera orbiting")
		countDevils()
	end
	remotes.LeaveCamp:simulateFireServer(plr)
	h:advance(0.05)
	if devil then devil.count = count0 end
	print(string.format("  15 devils over the Pine Barrens for 60 s: %d devil-frames, %d camp frames checked", devilFrames, framesChecked))
	truthy(devilFrames > 30 * 60 * 3, "devils: at least three were out on average (" .. devilFrames .. " devil-frames)")
	eq(inside, 0, "devils: no part of any devil, wings included, ever entered the keep-out (" .. tostring(firstInside) .. ")")
end

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid keepout: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid keepout check failed", 0) end
