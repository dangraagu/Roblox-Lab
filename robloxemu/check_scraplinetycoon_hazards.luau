-- Scrapline Tycoon — hazards through the real client glue: when the crane may drop something, that the red ring
-- drawn is EXACTLY the hit zone, that stepping out of it in any of 8 directions always dodges, that resting freezes
-- their clock (never resets it), and that a due hazard is HELD while a machine sputters (not while a jam merely
-- stands: REVIEW-2 R5), while the first Rocket lifts off and while the recycle sequence plays (one thing at a time).
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon_hazards.luau 2>&1
--
-- Config.Hazards.IntervalMin/Max are set to 8/9 s IN MEMORY for this run only, so a short check sees many hazards
-- (+1 Jump's and meteor-drop-tycoon's hazards checks do the same). Nothing renders headless: "a hit" is the knock
-- Yard.client applies (PlatformStand on the local Humanoid).

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/scrapline-tycoon"), name = "scrapline-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 7777
local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")
store:SetAsync("u_" .. UID, { data = { v = 1, cash = 1e12, stations = { shredder = { n = 1, L = 1, j = 0 } }, jamIn = 240, tier = 1,
	bolts = 0, boltsAt = 0, tutorial = 4 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local PlotGeom = h:_require(RS:FindFirstChild("PlotGeom"))
local Hz = Config.Hazards
Hz.IntervalMin, Hz.IntervalMax = 8, 9 -- in memory, this run only

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Dodger", UID)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Concrete
hum.MoveDirection = Vector3.new(0.01, 0, 1) -- steering input: never idles into rest
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Yard.client"))

local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local folder = h.workspace:FindFirstChild("ScraplineLocalYard")
local yardGui = plr.PlayerGui:FindFirstChild("ScraplineYard")
local probe = yardGui:FindFirstChild("YardProbe")
local warning = yardGui.Root:FindFirstChild("WarningPanel")
local remotes = RS:FindFirstChild("ScraplineRemotes")
local Buy, Fix, Recycle = remotes.Buy, remotes.Fix, remotes.Recycle
local pad = plr.RespawnLocation
local plot = pad.Parent
local k = tonumber(string.match(plot.Name, "%d+"))
local function at(lx, lz, y)
	local x, z = PlotGeom.toWorld(Config, k, lx, lz)
	return Vector3.new(x, y or (Config.World.FloorTopY + 3), z)
end
local home = at(0, -2) -- the middle of the U: open floor

local maxModels, maxParts, maxLights = 0, 0, 0
local function hazardKind()
	local kinds = {}
	for _, d in folder:GetChildren() do
		local kk = string.match(d.Name, "^Hazard_(%a+)_")
		if kk and d:IsA("BasePart") and d.Transparency < 0.99 then kinds[kk] = true end
	end
	local n, one = 0, nil
	for kk in kinds do n += 1; one = kk end
	return one, n
end
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, -18), hrp.Position)
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
local function place(p)
	hrp.CFrame = CFrame.new(p)
end
-- a player who keeps their line running: any sputter or jam is walked to and fixed (the trusted position must
-- catch up, so the Fix waits for it), the way the real player path does
local function tend()
	for _ = 1, 3 do
		local st = stateOf()
		local target = nil
		if st.sputter then
			target = { t = st.sputter.t, m = st.sputter.m }
		else
			for t = 1, 6 do
				local row = st.stations[t]
				if row.n >= 1 and row.jamA ~= 0 then target = { t = t, m = 1 } break end
				if row.n >= 2 and row.jamB ~= 0 then target = { t = t, m = 2 } break end
			end
		end
		if target == nil then return end
		local mx, mz = PlotGeom.machinePos(Config, target.t, target.m)
		local back = hrp.Position
		place(at(if target.t <= 3 then -9.5 else 9.5, mz))
		for _ = 1, 60 do frame(0.05) end
		Fix:simulateFireServer(plr, Config.Stations.Order[target.t], if target.m == 1 then "a" else "b")
		frame(0.05)
		place(back)
	end
end
local function spawnsDuring(seconds)
	local s0 = probe:Invoke().hazardsSpawned
	for _ = 1, math.floor(seconds / 0.05) do frame(0.05) end
	return probe:Invoke().hazardsSpawned - s0
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
local function knocked()
	return hum.PlatformStand == true
end
local function buildTo(tier)
	while stateOf().tier < tier do
		local nextT = nil
		for t = 1, 6 do if stateOf().stations[t].n == 0 then nextT = t break end end
		if nextT then Buy:simulateFireServer(plr, "build", Config.Stations.Order[nextT]) end
		for _ = 1, 40 do frame(0.05) end
	end
end

--============================================================================ 1. the Junkyard is quiet
place(home)
eq(stateOf().tier, 1, "set-up: tier 1, the Junkyard")
eq(spawnsDuring(40), 0, "the Junkyard sends nothing, 40 s at an 8-9 s interval")

--============================================================================ 2. hazards start in the Foundry
buildTo(2)
eq(stateOf().tier, 2, "set-up: the first Ingot shipped (the Foundry)")
truthy(waitForSpawn(12), "the Foundry sends a hazard once the interval is up")
waitIdle()

--============================================================================ 3. only on your OWN plot
do
	place(Vector3.new(0, 12, 40)) -- the Scrap Market, on no plot
	local c0 = probe:Invoke().hazardClock
	eq(spawnsDuring(30), 0, "off your plot, nothing launches in 30 s")
	eq(probe:Invoke().hazardClock, c0, "and the hazard clock does not run there (it counts time on your own plot)")
	place(home)
	tend()
	truthy(waitForSpawn(12), "back on your plot, the crane drops things again")
	waitIdle()
end

--============================================================================ 4. grounded only
do
	tend()
	hum.FloorMaterial = Enum.Material.Air
	eq(spawnsDuring(25), 0, "nothing launches at a player in the air, however long it is due")
	hum.FloorMaterial = Enum.Material.Concrete
	tend()
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
	tend()
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local btn = yardGui.Root.BreakSlot.BreakButton
	btn.Activated:Fire()
	frame(0.05)
	eq(probe:Invoke().resting, true, "☕ Break rests")
	local c0 = probe:Invoke().hazardClock
	eq(spawnsDuring(40), 0, "nothing launches during 40 s of rest")
	eq(probe:Invoke().hazardClock, c0, "the hazard clock is frozen while resting")
	hum.MoveDirection = Vector3.new(0.01, 0, 1)
	frame(0.5)
	frame(0.05)
	eq(probe:Invoke().resting, false, "moving wakes")
	local c1 = probe:Invoke().hazardClock
	truthy(c1 >= c0 and c1 - c0 < 1, string.format("the clock resumes from where it stopped, not from zero (%.2f -> %.2f)", c0, c1))
	tend()
	truthy(waitForSpawn(12), "and hazards come again")
	waitIdle()
end

--============================================================================ 6. the red ring is exactly the hit zone; stepping out always dodges
local function nextLocked(spot)
	-- a standing jam no longer holds the crane (REVIEW-2 R5), so one may have launched while tend() walked to a jam:
	-- let it finish, then wait for the next one to come for `spot`. A sputter that starts during the wait holds the
	-- crane (section 7), so fix it and wait again (at most three times).
	local spawned = false
	for _ = 1, 3 do
		place(spot or home)
		tend()
		waitIdle()
		place(spot or home)
		if waitForSpawn(15) then spawned = true break end
	end
	if not spawned then return nil end
	for _ = 1, 200 do
		if spot then place(spot) end
		frame(0.05)
		if warning.Visible and string.find(warning:FindFirstChild("WarningText").Text, "MOVE", 1, true) then
			return hazardKind()
		end
	end
	return nil
end
do
	local kind = nextLocked()
	truthy(kind ~= nil, "set-up: a hazard locks onto a player standing still")
	if kind then
		local ring = folder:FindFirstChild("HazardZone")
		truthy(ring ~= nil and ring.Transparency < 0.5, "the ring is drawn, solid at the lock")
		local want = Hz.Kinds[kind].hitRadius + Hz.PlayerRadius
		truthy(ring and math.abs(ring.Size.Y / 2 - want) < 1e-6,
			string.format("the ring's radius is the %s's hit zone exactly (%.2f vs %.2f)", kind, ring and ring.Size.Y / 2 or -1, want))
		local dx, dz = ring.Position.X - hrp.Position.X, ring.Position.Z - hrp.Position.Z
		truthy(math.sqrt(dx * dx + dz * dz) <= Hz.AimJitter + 1e-6, "and it is centred where the player stands (within the aim jitter)")
		local c = ring.Color
		eq(string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)),
			string.format("%d,%d,%d", Hz.RingColor[1], Hz.RingColor[2], Hz.RingColor[3]), "and it is the one red in the game")
		local trolley = folder:FindFirstChild("CraneTrolley")
		truthy(trolley ~= nil and math.abs(trolley.Position.X - ring.Position.X) < 1e-6 and trolley.Position.Y > 20,
			"the crane's trolley rides overhead, right above the ring")
		-- CONTROL: stay inside it
		local hit = false
		for _ = 1, 60 do
			frame(0.05)
			if knocked() then hit = true break end
		end
		truthy(hit, "CONTROL: a player who stays in the ring is hit (the knock)")
		for _ = 1, 30 do frame(0.05) end
	end
	local dodged, trials = 0, 0
	for d = 0, 7 do
		local kk = nextLocked()
		if kk then
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
			place(home)
			waitIdle()
		end
	end
	eq(trials, 8, "set-up: a locked hazard for each of the 8 directions")
	eq(dodged, trials, string.format("stepping out of the ring at the lock dodges in every direction (%d of %d)", dodged, trials))
end

--============================================================================ 6b. the floors the zone is drawn up to are the ones the server built
do
	for _, f in PlotGeom.floors(Config) do
		local part = plot:FindFirstChild(f.part, true)
		truthy(part ~= nil, "set-up: the built plot has its " .. f.part)
		if part then
			local isCyl = part.Shape == Enum.PartType.Cylinder
			local up = if isCyl then part.Size.X else part.Size.Y
			local top = part.Position.Y + up / 2
			truthy(math.abs(top - f.top) < 1e-6, string.format("PlotGeom's %s top (%.2f) is the built one (%.2f)", f.part, f.top, top))
			if f.shape == "disc" then
				truthy(math.abs(part.Size.Y / 2 - f.radius) < 1e-6, string.format("and its radius (%.2f vs %.2f)", f.radius, part.Size.Y / 2))
			else
				truthy(math.abs(part.Size.X / 2 - f.hx) < 1e-6 and math.abs(part.Size.Z / 2 - f.hz) < 1e-6,
					string.format("and its size (%.2f x %.2f vs %.2f x %.2f)", f.hx, f.hz, part.Size.X / 2, part.Size.Z / 2))
			end
		end
	end
	-- a hazard locking onto a player standing on the arrival pad is drawn on top of the pad
	waitIdle()
	local padTop = pad.Position.Y + pad.Size.Y / 2
	local onPad = Vector3.new(pad.Position.X, padTop + 3, pad.Position.Z)
	local locked = nextLocked(onPad)
	truthy(locked ~= nil, "set-up: a hazard locks onto a player standing on the arrival pad")
	local ring = folder:FindFirstChild("HazardZone")
	if locked and ring then
		local topY = ring.Position.Y + ring.Size.X / 2
		print(string.format("  the zone on the pad: top at %.2f (pad top %.2f), radius %.2f", topY, padTop, ring.Size.Y / 2))
		truthy(topY > padTop + 0.05, "the zone's top is above the pad, so all of it shows")
	end
	for _ = 1, 60 do frame(0.05) end
	waitIdle()
	place(home)
end

--============================================================================ 7. one thing at a time: held during a sputter, NOT during a standing jam
-- A sputter has a 15 s clock: the player must walk to it, so the crane waits. A JAM has no clock (it costs income
-- until fixed), and holding the crane for it froze hazards for good for anyone who left one jammed twin or rejoined
-- with a saved jam (REVIEW-2 R5: 1 drop in 10 min, the hold on in 3626 of 6000 frames).
do
	-- wait for the next sputter. The next hazard is due 8-9 s after the last LAUNCH (Hazards.step), so it always comes
	-- due inside the 15 s sputter; one already in the air when the sputter began launched before it and is not counted
	local live, spT = false, nil
	for _ = 1, 6000 do
		frame(0.05)
		if stateOf().sputter then live = true; spT = stateOf().sputter.t break end
	end
	truthy(live, "set-up: a machine sputters")
	if live then
		-- a hazard comes due while the sputter is live: it must not launch. Counted only while the State says the
		-- sputter is live (afterwards it is a jam, which does not hold the crane)
		local s0 = probe:Invoke().hazardsSpawned
		local liveFor = 0
		while stateOf().sputter ~= nil and liveFor < 20 do
			frame(0.05)
			liveFor += 0.05
		end
		local launched = probe:Invoke().hazardsSpawned - s0
		eq(launched, 0, string.format("no hazard launches while a machine sputters (%.1f s, a hazard due every 8-9 s)", liveFor))
		local p2 = probe:Invoke()
		truthy(p2.hazardClock >= p2.hazardNextAt, "set-up: a hazard was due the whole time (held, not skipped)")
		-- nobody fixes it: the sputter becomes a jam, and the jam stands
		local jammed = false
		for _ = 1, 200 do
			frame(0.05)
			if stateOf().sputter == nil and (stateOf().jammed[spT] or 0) >= 1 then jammed = true break end
		end
		truthy(jammed, "set-up: the sputter became a jam")
		local resumed = false
		for _ = 1, 40 do
			frame(0.05)
			if probe:Invoke().hazardActive then resumed = true break end
		end
		truthy(resumed, "REVIEW-2 R5: once the sputter is over, the held hazard launches at once, though a jam stands")
		waitIdle()
		local n = spawnsDuring(60)
		print(string.format("  a jam left standing for 60 s (a hazard every 8-9 s of clock): %d hazards", n))
		truthy(n >= 4, "REVIEW-2 R5: a standing jam does not stop the crane (" .. n .. " drops in 60 s)")
		truthy((stateOf().jammed[spT] or 0) >= 1, "set-up: the jam stood the whole time")
		tend()
		waitIdle()
	end
end

--============================================================================ 7b. nothing launches at a player standing ON a machine (REVIEW-1 B5)
-- The ring is drawn on the highest LOW surface under the zone (PlotGeom.floors: pads, belt, consoles). Machine bodies
-- are collidable and 6-9 studs tall, so a player who climbed one stood 5-8 studs above a ring hidden inside the
-- machine; FloorMaterial = Metal counted as grounded, so the crane still dropped on them.
do
	place(home)
	tend()
	waitIdle()
	local built = {}
	for t = 1, 6 do if stateOf().stations[t].n >= 1 then table.insert(built, t) end end
	truthy(#built >= 1, "set-up: a machine stands on the plot")
	local t = built[1]
	local mx, mz = PlotGeom.machinePos(Config, t, 1)
	local top = Config.World.FloorTopY + Config.Stations.MachineHeight[t]
	local onTop = at(mx, mz, top + 3)
	hum.FloorMaterial = Enum.Material.Metal
	place(onTop)
	local s0 = probe:Invoke().hazardsSpawned
	for _ = 1, math.floor(30 / 0.05) do
		place(onTop)
		frame(0.05)
	end
	local launched = probe:Invoke().hazardsSpawned - s0
	local pr = probe:Invoke()
	eq(launched, 0, string.format("nothing launches at a player standing on the %s (top at y %.1f) in 30 s, a hazard due every 8-9 s", Config.Stations.Names[t], top))
	truthy(pr.hazardClock >= pr.hazardNextAt, "set-up: a hazard was due the whole time (held, not skipped)")
	hum.FloorMaterial = Enum.Material.Concrete
	place(home)
	tend()
	place(home)
	local back = false
	for _ = 1, 20 do
		frame(0.05)
		if probe:Invoke().hazardActive then back = true break end
	end
	truthy(back, "back on the floor, the held hazard launches at once")
	waitIdle()
end

--============================================================================ 7c. a player standing still at the HUD still gets the crane (REVIEW-1 B3)
-- A tycoon is played standing still and tapping the HUD. The first version let the 20 s idle rest freeze the hazard
-- clock, so the model's normal player saw one crane drop per half hour instead of one every 2-3 minutes. The
-- interval is 30-31 s here (longer than the 20 s the idle rest used to need), standing still for 3 minutes.
do
	place(home)
	tend()
	waitIdle()
	Hz.IntervalMin, Hz.IntervalMax = 30, 31
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local s0 = probe:Invoke().hazardsSpawned
	local restedFrames = 0
	for _ = 1, 36 do
		tend()
		place(home)
		for _ = 1, math.floor(5 / 0.05) do
			frame(0.05)
			if probe:Invoke().resting then restedFrames += 1 end
		end
	end
	local n = probe:Invoke().hazardsSpawned - s0
	print(string.format("  standing still for 180 s (a hazard every 30-31 s of clock): %d hazards, resting in %d of 3600 frames", n, restedFrames))
	eq(restedFrames, 0, "standing still (playing through the HUD) is not a rest: only ☕ Break is")
	truthy(n >= 4, "a player standing still gets the crane at its interval (" .. n .. " drops in 180 s)")
	hum.MoveDirection = Vector3.new(0.01, 0, 1)
	Hz.IntervalMin, Hz.IntervalMax = 8, 9
	waitIdle()
end

--============================================================================ 8. held while the first Rocket lifts off
do
	place(home)
	tend()
	local held = 0
	local liftSeen = false
	-- build on to the Rocket Bay; the first Rocket ships and lifts off from this plot's pad
	local t0 = h.scheduler:now()
	while stateOf().tier < 6 and h.scheduler:now() - t0 < 400 do
		local nextT = nil
		for t = 1, 6 do if stateOf().stations[t].n == 0 then nextT = t break end end
		if nextT then Buy:simulateFireServer(plr, "build", Config.Stations.Order[nextT]) end
		tend()
		for _ = 1, 20 do frame(0.05) end
	end
	eq(stateOf().tier, 6, "set-up: the first Rocket shipped")
	local s0 = probe:Invoke().hazardsSpawned
	for _ = 1, 100 do
		frame(0.05)
		local pr = probe:Invoke()
		if pr.liftoff then
			liftSeen = true
			if pr.hazardsSpawned > s0 then held += 1 end
		end
	end
	truthy(liftSeen, "the lift-off plays on this plot's pad")
	eq(held, 0, "no hazard launches during the lift-off")
end

--============================================================================ 9. held while the recycle sequence plays
do
	tend()
	for _ = 1, 600 do
		local st = stateOf()
		if st.recycleReady then break end
		if st.star then Buy:simulateFireServer(plr, st.star.kind, st.star.id) end
		h:advance(0.13)
	end
	tend()
	truthy(stateOf().recycleReady, "set-up: the line ships enough rockets to recycle")
	-- let a hazard come due first, then recycle
	waitIdle()
	for _ = 1, 400 do
		local pr = probe:Invoke()
		if pr.hazardClock >= pr.hazardNextAt - 0.2 then break end
		frame(0.05)
	end
	Recycle:simulateFireServer(plr)
	local s0 = probe:Invoke().hazardsSpawned
	for _ = 1, math.floor(Config.Recycle.SequenceSeconds / 0.05) - 2 do frame(0.05) end
	eq(stateOf().bolts, 1, "set-up: recycled")
	eq(probe:Invoke().hazardsSpawned - s0, 0, "no hazard launches during the recycle sequence")
	-- and the Junkyard after it is quiet again
	eq(spawnsDuring(30), 0, "after a recycle the yard is a Junkyard again: quiet")
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
print(string.format("scraplinetycoon hazards: %d passed, %d failed", passed, failed))
if failed > 0 then error("scraplinetycoon hazards check failed", 0) end
