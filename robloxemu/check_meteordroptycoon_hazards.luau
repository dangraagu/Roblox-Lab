-- Meteor Drop Tycoon — hazards through the real client glue: when they may launch, that the red ring drawn is
-- EXACTLY the hit zone, that stepping out of it in any of 8 directions always dodges, and that resting
-- freezes their clock (never resets it).
-- Run:  py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
--       luau check_meteordroptycoon_hazards.luau 2>&1
--
-- Config.Hazards.IntervalMin/Max are set to 8/9 s IN MEMORY for this run only, so a short check sees many
-- hazards (+1 Jump's hazards check does the same). The rules under test are the gates in Sky.client.luau:
-- only on your own plot, grounded, not resting, not during the Falling Star, and nothing in the first band.
-- Nothing renders headless: "a hit" is the knock Sky.client applies (PlatformStand on the local Humanoid).

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/meteor-drop-tycoon"), name = "meteor-drop-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 7777
local store = h.services.DataStoreService:GetDataStore("MeteorDropTycoon_v1")
store:SetAsync("u_" .. UID, { data = { v = 1, stardust = 1e15, lifetime = 1e15, beacon = 0, beaconAt = 1790000000,
	collector = 0, smelter = 60, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Hz = Config.Hazards
Hz.IntervalMin, Hz.IntervalMax = 8, 9 -- in memory, this run only

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Dodger", UID)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0.01, 0, 1) -- steering input: never idles into rest
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Sky.client"))

local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local folder = h.workspace:FindFirstChild("MeteorLocalSky")
local skyGui = plr.PlayerGui:FindFirstChild("MeteorSky")
local probe = skyGui:FindFirstChild("MeteorSkyProbe")
local warning = skyGui.Root:FindFirstChild("WarningPanel")
local remotes = RS:FindFirstChild("MeteorRemotes")
local Buy = remotes:FindFirstChild("Buy")
local pad = plr.RespawnLocation
local plot = pad.Parent
local centre = plot.Smelter.SmelterBody.Position
local home = Vector3.new(centre.X + (pad.Position.X - centre.X) * 0.5, 3.5, centre.Z + (pad.Position.Z - centre.Z) * 0.5) -- 15 studs from the Smelter

local maxModels, maxParts, maxLights = 0, 0, 0
local function hazardKind()
	local kinds = {}
	for _, d in folder:GetChildren() do
		local k = string.match(d.Name, "^Hazard_(%a+)_")
		if k and d:IsA("BasePart") and d.Transparency < 0.99 then kinds[k] = true end
	end
	local n, one = 0, nil
	for k in kinds do n += 1; one = k end
	return one, n
end
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 18), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	local _, n = hazardKind()
	maxModels = math.max(maxModels, n)
	local parts, lights = 0, 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then parts += 1 end
		if d.ClassName == "PointLight" and d.Enabled ~= false then lights += 1 end
	end
	maxParts = math.max(maxParts, parts)
	maxLights = math.max(maxLights, lights)
end
local function stateOf()
	local sent = remotes.State:sentTo(plr)
	return sent[#sent].args[1]
end
local function buyTo(L)
	while stateOf().beacon < L do
		Buy:simulateFireServer(plr, "beacon")
		h:advance(0.2)
	end
end
local function spawnsDuring(seconds)
	local s0 = probe:Invoke().hazardsSpawned
	for _ = 1, math.floor(seconds / 0.05) do frame(0.05) end
	return probe:Invoke().hazardsSpawned - s0
end
local function place(p)
	hrp.CFrame = CFrame.new(p)
end
local function waitForSpawn(maxSeconds)
	local s0 = probe:Invoke().hazardsSpawned
	for _ = 1, math.floor(maxSeconds / 0.05) do
		frame(0.05)
		if probe:Invoke().hazardsSpawned > s0 then return true end
	end
	return false
end
local function waitIdle()
	for _ = 1, 400 do
		if not probe:Invoke().hazardActive then return end
		frame(0.05)
	end
end
local knockedPrev = false
local function knocked()
	return hum.PlatformStand == true
end

--============================================================================ 1. the first band is quiet
place(home)
eq(stateOf().beacon, 0, "set-up: Beacon 0, the Dusk Meadow")
eq(spawnsDuring(40), 0, "the first band sends nothing, 40 s at an 8-9 s interval")

--============================================================================ 2. hazards start in Twilight
buyTo(12) -- the Aurora: satellites and ice chunks
eq(stateOf().beacon, 12, "set-up: Beacon 12")
truthy(waitForSpawn(12), "a hazard band sends a hazard once the interval is up")
waitIdle()

--============================================================================ 3. only on your OWN plot
do
	place(Vector3.new(0, 3.5, 0) + Vector3.new(0, 20, 0) * 0) -- the observatory, on no plot
	hrp.CFrame = CFrame.new(0, 12, 20)
	local c0 = probe:Invoke().hazardClock
	eq(spawnsDuring(30), 0, "off your plot, nothing launches in 30 s")
	eq(probe:Invoke().hazardClock, c0, "and the hazard clock does not run there (it counts time on your own plot)")
	place(home)
	truthy(waitForSpawn(12), "back on your plot, the hazards come again")
	waitIdle()
end

--============================================================================ 4. grounded only
do
	hum.FloorMaterial = Enum.Material.Air
	eq(spawnsDuring(25), 0, "nothing launches at a player in the air, however long it is due")
	hum.FloorMaterial = Enum.Material.Grass
	local landed = nil
	for i = 1, 40 do
		frame(0.05)
		if probe:Invoke().hazardActive then landed = i * 0.05 break end
	end
	truthy(landed ~= nil, "the due hazard launches as soon as they stand on something (" .. tostring(landed) .. " s)")
	waitIdle()
end

--============================================================================ 5. resting freezes the clock, never resets it
do
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local btn = skyGui.Root.StargazeSlot.StargazeButton
	btn.Activated:Fire()
	frame(0.05)
	eq(probe:Invoke().resting, true, "Stargaze rests")
	local c0 = probe:Invoke().hazardClock
	eq(spawnsDuring(40), 0, "nothing launches during 40 s of rest")
	eq(probe:Invoke().hazardClock, c0, "the hazard clock is frozen while resting")
	hum.MoveDirection = Vector3.new(0.01, 0, 1)
	frame(0.5)
	frame(0.05)
	eq(probe:Invoke().resting, false, "moving wakes")
	local c1 = probe:Invoke().hazardClock
	truthy(c1 >= c0 and c1 - c0 < 1, string.format("the clock resumes from where it stopped, not from zero (%.2f -> %.2f)", c0, c1))
	truthy(waitForSpawn(12), "and hazards come again")
	waitIdle()
end

--============================================================================ 6. the red ring is exactly the hit zone; stepping out always dodges
local function nextLocked()
	-- wait for a hazard, standing still at home, until its lane locks ("MOVE!")
	place(home)
	if not waitForSpawn(15) then return nil end
	for _ = 1, 200 do
		frame(0.05)
		if warning.Visible and string.find(warning:FindFirstChild("WarningText").Text, "MOVE", 1, true) then
			return hazardKind()
		end
	end
	return nil
end
do
	-- the ring, at the lock
	local kind = nextLocked()
	truthy(kind ~= nil, "set-up: a hazard locks onto a player standing still")
	if kind then
		local ring = folder:FindFirstChild("HazardZone")
		truthy(ring ~= nil and ring.Transparency < 0.5, "the ring is drawn, solid at the lock")
		local want = Hz.Kinds[kind].hitRadius + Hz.PlayerRadius
		truthy(ring and math.abs(ring.Size.Y / 2 - want) < 1e-6,
			string.format("the ring's radius is the %s's hit zone exactly (%.2f vs %.2f)", kind, ring and ring.Size.Y / 2 or -1, want))
		local dx, dz = ring.Position.X - hrp.Position.X, ring.Position.Z - hrp.Position.Z
		truthy(math.sqrt(dx * dx + dz * dz) < 1e-6, "and it is centred where the player stands")
		local c = ring.Color
		eq(string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)),
			string.format("%d,%d,%d", Hz.RingColor[1], Hz.RingColor[2], Hz.RingColor[3]), "and it is the one red in the game")
		-- CONTROL: stay inside it
		local hit = false
		for _ = 1, 60 do
			frame(0.05)
			if knocked() then hit = true break end
		end
		truthy(hit, "CONTROL: a player who stays in the ring is hit (the knock)")
		for _ = 1, 30 do frame(0.05) end
	end
	-- 8 directions, each stepping out of the ring at WalkSpeed from the moment the lane locks
	local dodged, trials = 0, 0
	for d = 0, 7 do
		local k = nextLocked()
		if k then
			trials += 1
			local a = d * math.pi / 4
			local start = hrp.Position
			local hit = false
			for i = 1, 40 do
				local moved = math.min(8, i * 0.05 * 16)
				hrp.CFrame = CFrame.new(start.X + math.cos(a) * moved, start.Y, start.Z + math.sin(a) * moved)
				frame(0.05)
				if knocked() then hit = true end
			end
			if not hit then dodged += 1 end
			waitIdle()
		end
	end
	eq(trials, 8, "set-up: a locked hazard for each of the 8 directions")
	eq(dodged, trials, string.format("stepping out of the ring at the lock dodges in every direction (%d of %d)", dodged, trials))
end

--============================================================================ 6b. a zone on the arrival pad is drawn ON the pad (REVIEW-1)
-- The zone used to be drawn at the plot disc's height, under the 1-stud pad: a player standing on their pad saw
-- four red slivers. It is now a column from the disc up to the highest low surface it overlaps.
do
	local PlotGeom = h:_require(RS:FindFirstChild("PlotGeom"))
	-- the floors the zone rule assumes are the ones the server built (a drift guard)
	if type(PlotGeom.floors) == "function" then
		for _, f in PlotGeom.floors(Config) do
			local part = plot:FindFirstChild(f.part, true)
			truthy(part ~= nil, "set-up: the built plot has its " .. f.part)
			if part then
				local up = if part:IsA("SpawnLocation") then part.Size.Y else part.Size.X -- cylinders stand on their X axis
				local wide = if part:IsA("SpawnLocation") then part.Size.X / 2 else part.Size.Y / 2
				local top = part.Position.Y + up / 2
				truthy(math.abs(top - f.top) < 1e-6, string.format("PlotGeom's %s top (%.2f) is the built one (%.2f)", f.part, f.top, top))
				truthy(math.abs(wide - (f.half or f.radius)) < 1e-6, string.format("and its size (%.2f vs %.2f)", f.half or f.radius, wide))
			end
		end
	else
		truthy(false, "PlotGeom.floors exists")
	end
	-- a hazard locking onto a player standing on the pad
	waitIdle()
	local padTop = pad.Position.Y + pad.Size.Y / 2
	local onPad = Vector3.new(pad.Position.X, padTop + 3, pad.Position.Z)
	place(onPad)
	local locked = nil
	if waitForSpawn(15) then
		for _ = 1, 200 do
			place(onPad)
			frame(0.05)
			if warning.Visible and string.find(warning:FindFirstChild("WarningText").Text, "MOVE", 1, true) then
				locked = hazardKind()
				break
			end
		end
	end
	truthy(locked ~= nil, "set-up: a hazard locks onto a player standing on the arrival pad")
	local ring = folder:FindFirstChild("HazardZone")
	if locked and ring then
		local topY = ring.Position.Y + ring.Size.X / 2
		local bottomY = ring.Position.Y - ring.Size.X / 2
		print(string.format("  the zone on the pad: y %.2f to %.2f (pad top %.2f, disc top %.2f), radius %.2f",
			bottomY, topY, padTop, Config.World.DiscTopY, ring.Size.Y / 2))
		truthy(topY > padTop + 0.05, string.format("the zone's top is above the pad, so all of it shows (%.2f > %.2f)", topY, padTop))
		truthy(bottomY <= Config.World.DiscTopY + 0.05, "and it still reaches down to the disc, where it is the same circle")
		truthy(math.abs(ring.Size.Y / 2 - (Hz.Kinds[locked].hitRadius + Hz.PlayerRadius)) < 1e-6, "its radius is still exactly the hit zone")
	end
	for _ = 1, 60 do frame(0.05) end
	waitIdle()
	place(home)
end

--============================================================================ 7. never during the Falling Star
do
	waitIdle()
	place(home)
	buyTo(22) -- the Starfall band: the grant is written, the star falls by the arrival pad
	for _ = 1, 20 do frame(0.05) end
	eq(stateOf().star, 1, "set-up: the Falling Star is granted and not yet caught")
	eq(spawnsDuring(40), 0, "no hazard launches between the grant and the catch (the brag moment is never knocked)")
	-- catch it: walk to it
	local m = plot.Meteors:FindFirstChild("FallingStar")
	for _ = 1, 100 do
		m = plot.Meteors:FindFirstChild("FallingStar")
		if m then break end
		frame(0.1)
	end
	if m then
		place(Vector3.new(m.Position.X, 3.5, m.Position.Z))
		for _ = 1, 10 do frame(0.05) end
	end
	eq(stateOf().star, 2, "set-up: caught")
	truthy(waitForSpawn(12), "after the catch the hazards resume")
end

print(string.format("  at most %d hazard model(s) at once; local parts peaked at %d, lights at %d", maxModels, maxParts, maxLights))
eq(maxModels <= 1, true, "never more than one hazard at a time")
truthy(maxParts <= Config.Budget.MaxLocalParts, "the local part budget holds with hazards in the air")
truthy(maxLights <= Config.Budget.MaxLights, "and the light budget")

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("meteordroptycoon hazards: %d passed, %d failed", passed, failed))
if failed > 0 then error("meteordroptycoon hazards check failed", 0) end
