-- Steal a Cryptid - a hazard can land AFTER its arrival time: the warning must still be up when it does.
-- Through the REAL server and the REAL client scripts.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_latehit.luau 2>&1
--
-- Second review of the night, 2026-09-30, finding 1. Hazards.checkHit runs until the flight's end, and a lane
-- is aimed at a point up to AimJitter from the ring's centre, so a player who stops on the FAR side of the ring
-- is reached after the arrival time. The client hid the ring and the chip warning at arrival, and the drawing
-- swooped away (a meteorite vanished): the reviewer's probe measured 18 of 120 knocks (rank 2) and 23 of 115
-- (rank 4) landing 1-5 frames after the ring and the chip had gone. Now the ring and the warning stay up while
-- Hazards.threatLive holds, and the drawing keeps the lane's line until then (Night.drawPosition, liveUntil).
-- The reviewer's set-up, as a gate, at rank 2 (bat, crow) and rank 4 (meteorite, wisp), rapid hazards:
-- stand still, wait for the lock, react 0.5 s later by walking to 0.99 x the ring's radius on its far side
-- (along the lane, and 30 degrees either side of it), stop, and watch at 60 fps:
--   L1 no knock lands after the ring has gone;
--   L2 no knock lands after the chip's warning has gone;
--   L3 on the knock's frame the hazard is drawn, within the ring's radius (+ 2 studs of model) of the root;
--   L4 (set-up) some knocks land after the lane line went (the arrival): the case is really exercised;
--   L5 while the ring lingers after arrival, no hazard part is under the floor and the chip still says Move!;
--   L6 after a knock the ring goes on the next frame (it does not linger to the flight's end).
-- Headless limits: no physics (the knock is observed as what the client writes), nothing renders.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-latehit", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local W = Config.World
local Hz = Config.Night.Hazards
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 9301
do
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = "", jar = 0 } end
	cages[5] = { sp = "dogman", jar = 0 }
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 10000000, savedAt = NOW, cagesUnlocked = 9, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = { "jackalope", "dogman" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local GameConfig = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
GameConfig.Poacher.FirstAfterSeconds = 1e6 -- no poacher walks in (it closes the hazard gate); rank 4 owns 3 cryptids
GameConfig.Night.Hazards.IntervalMin, GameConfig.Night.Hazards.IntervalMax = 0.05, 0.05
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Farside", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Night.client"))
local bus = plr.PlayerGui.CryptidHud.NightBus
local folder = h.workspace:FindFirstChild("CryptidNight")
local cam = h.workspace.CurrentCamera
local remState = h.ReplicatedStorage:FindFirstChild("CryptidRemotes"):FindFirstChild("State")
local function st()
	local sent = remState:sentTo(plr)
	return sent[#sent].args[1]
end

local function frame(dt)
	local p = hrp.Position
	cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds, until_)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		frame(1 / 30)
		if until_ and until_() then return true end
	end
	return false
end
local function shown(name)
	for _, d in folder:GetChildren() do
		if d.Name == name and d:IsA("BasePart") then return d end
	end
	return nil
end
local function hazardParts()
	local out = {}
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and string.find(d.Name, "^Hazard_%a+_") then table.insert(out, d) end
	end
	return out
end
local function inFlight() return #hazardParts() > 0 end
local function kindNow()
	local p = hazardParts()[1]
	return p and string.match(p.Name, "^Hazard_(%a+)_")
end

run(1)
local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. st().plot)
local lair = plot:FindFirstChild("Lair")
local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
local function apron(x, z) return frameCF:PointToWorldSpace(Vector3.new(x, W.RootHeight, z)) end

local all = { trials = 0, knocks = 0, afterRing = 0, afterChip = 0, notDrawn = 0, far = 0, afterArrival = 0, under = 0, notMove = 0, lingerAfterKnock = 0 }
local worstDrawn = 0
local examples = {}
local function trials(label, n)
	local t0 = { trials = all.trials, knocks = all.knocks, afterArrival = all.afterArrival }
	for i = 1, n do
		hrp.CFrame = CFrame.new(apron(36, 4))
		hum.MoveDirection = Vector3.new(0, 0, 0)
		run(Hz.SettleSeconds + 12, inFlight)
		if inFlight() then
			local kind = kindNow()
			run(6, function() return string.sub(bus.Status.Value, 1, 5) == "Move!" end)
			local ring = shown("HazardRing")
			if ring and string.sub(bus.Status.Value, 1, 5) == "Move!" then
				all.trials += 1
				local centre, radius = ring.Position, ring.Size.Y / 2
				run(0.5)
				local lane = shown("HazardLane")
				local dir = if lane then lane.CFrame.LookVector else Vector3.new(0, 0, 1)
				local a = math.atan2(dir.X, dir.Z) + math.rad(({ 0, 30, -30 })[i % 3 + 1])
				local u = Vector3.new(math.sin(a), 0, math.cos(a))
				local goal = Vector3.new(centre.X, hrp.Position.Y, centre.Z) + u * (0.99 * radius)
				while (goal - hrp.Position).Magnitude > 0.01 do
					local d = goal - hrp.Position
					hrp.CFrame = CFrame.new(hrp.Position + d.Unit * math.min(d.Magnitude, Config.Raid.WalkSpeed / 30))
					hum.MoveDirection = d.Unit
					frame(1 / 30)
				end
				hum.MoveDirection = Vector3.new(0, 0, 0)
				local ringGone, chipGone, laneGone, hitAt = nil, nil, nil, nil
				local now = 0
				local afterHitFrames = 0
				for _ = 1, 480 do
					frame(1 / 60)
					now += 1 / 60
					local ringUp = shown("HazardRing") ~= nil
					local danger = bus.StatusKind.Value == "danger"
					if not laneGone and shown("HazardLane") == nil then laneGone = now end
					if not ringGone and not ringUp then ringGone = now end
					if not chipGone and not danger then chipGone = now end
					if not hitAt and hum.PlatformStand == true then
						hitAt = now
						all.knocks += 1
						-- the knock's frame: was the ring / the warning already gone on an EARLIER frame?
						if ringGone and ringGone < hitAt then all.afterRing += 1 end
						if chipGone and chipGone < hitAt then all.afterChip += 1 end
						if laneGone and laneGone < hitAt then all.afterArrival += 1 end
						local parts = hazardParts()
						if #parts == 0 then
							all.notDrawn += 1
							if #examples < 4 then table.insert(examples, kind .. ": nothing drawn on the knock's frame") end
						else
							local closest = math.huge
							for _, p in parts do closest = math.min(closest, (p.Position - hrp.Position).Magnitude) end
							worstDrawn = math.max(worstDrawn, closest - radius)
							if closest > radius + 2 then
								all.far += 1
								if #examples < 4 then table.insert(examples, string.format("%s: drawn %.2f studs from the root, ring radius %.2f", kind, closest, radius)) end
							end
						end
					elseif hitAt then
						afterHitFrames += 1
						if afterHitFrames == 2 and ringUp then all.lingerAfterKnock += 1 end
					end
					-- lingering: the lane line went (arrival), the ring is still up, nothing has hit
					if laneGone and ringUp and not hitAt then
						local floorTop = hrp.Position.Y - W.RootHeight
						for _, p in hazardParts() do
							if p.Position.Y < floorTop - 0.05 then all.under += 1 end
						end
						if string.sub(bus.Status.Value, 1, 5) ~= "Move!" then all.notMove += 1 end
					end
					if not inFlight() then break end
				end
				run(Hz.KnockSeconds + 0.3)
			end
		end
	end
	print(string.format("  %s: %d locked hazards, the player stopped at 0.99 R on the ring's far side: %d knocked, %d of them after the lane line (the arrival) had gone",
		label, all.trials - t0.trials, all.knocks - t0.knocks, all.afterArrival - t0.afterArrival))
end

trials("rank 2 (bat, crow)", 60)
for target = 3, 4 do
	local a = W.Apron.P3
	hrp.CFrame = CFrame.new(apron(a.x, a.z - 4))
	lair.Pedestals:FindFirstChild("Pedestal_3"):FindFirstChild("Buy").Triggered:Fire(plr)
	h:advance(0.05)
	run(3)
	eq(st().rank, target, "a purchase at P3 raised the Journal's rank to " .. target)
end
trials("rank 4 (meteorite, wisp)", 60)

for _, e in examples do print("   e.g. " .. e) end
print(string.format("  knocks %d of %d trials; after the ring went %d, after the chip went %d; nothing drawn %d; drawn farther than the ring + 2 studs %d (worst %.2f past the ring's radius)",
	all.knocks, all.trials, all.afterRing, all.afterChip, all.notDrawn, all.far, worstDrawn))
truthy(all.trials >= 100, "hazards locked in the far-side set-up (" .. all.trials .. " of 120)")
truthy(all.knocks >= math.floor(0.8 * all.trials), "the players who stopped in the ring were knocked (" .. all.knocks .. " of " .. all.trials .. ")")
truthy(all.afterArrival >= 3, "L4 (set-up): some knocks landed after the arrival, when the lane line had gone (" .. all.afterArrival .. ")")
eq(all.afterRing, 0, "L1: no knock lands after the red ring has gone")
eq(all.afterChip, 0, "L2: no knock lands after the chip's warning has gone")
eq(all.notDrawn, 0, "L3: on every knock's frame the hazard is drawn (a meteorite has not vanished)")
eq(all.far, 0, "L3: and it is drawn at the player (within the ring's radius + 2 studs of model)")
eq(all.under, 0, "L5: while the ring lingers after arrival, no hazard part is under the floor")
eq(all.notMove, 0, "L5: and the chip still says Move!")
eq(all.lingerAfterKnock, 0, "L6: after a knock the ring goes on the next frame")

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end
print(string.format("\nsteal a cryptid latehit: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid latehit check failed", 0) end
