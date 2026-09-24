-- +1 Jump Every Step — the sky, hazards and rest, driven through the REAL client script.
-- Run: luau check_plus1_sky.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- The pure modules (EnvBands, Hazards, Rest) are unit-tested in plus1-jump/tests. This file checks
-- the GLUE that no unit test can see: that src/client/Sky.client.luau actually feeds the player's
-- altitude into the bands, writes the blended values into Lighting, builds and hides scenery within
-- the mobile budget, runs hazards on the band's kinds at the measured rarity, knocks the character
-- so the SERVER's fall rescue returns it to its earned platform, and that rest freezes hazards
-- without resetting their clock. It also measures the budgets EYECANDY.md reports.
--
-- Headless limits, stated: nothing renders and there is no physics. Frames are driven by firing
-- RunService.RenderStepped; the character does not move unless this file moves it; a knock is
-- observed as the velocity and PlatformStand the client writes, and the fall that follows is
-- simulated by moving the root part. Whether any of it LOOKS right is on the Studio list.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if a ~= nil and b ~= nil and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local h = Harness.new({
	bundle = require("./build/plus1-jump"),
	name = "plus1-jump",
	viewport = { 1280, 720 },
	touch = false,
})

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end

assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local Progression = mod("Progression")
local bands = Config.Env.Bands
local Tower = Config.Tower

-- the server's lighting BEFORE any client runs (Fx.applyLighting(Temple))
local Lighting = h.Lighting
local serverClock = Lighting.ClockTime
local serverBright = Lighting.Brightness
local serverAtmos = Lighting:FindFirstChild("FxAtmosphere")
local serverDensity = serverAtmos and serverAtmos.Density

-- the server's replicated surface, recorded before the client exists
local remotes = RS:FindFirstChild("Plus1Remotes")
local remoteNames = {}
for _, r in remotes:GetChildren() do table.insert(remoteNames, r.Name) end
table.sort(remoteNames)
local serverCalls = 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverCalls += 1 end)
	end
end
do
	local redeem = remotes:FindFirstChild("Redeem")
	local inner = redeem.OnServerInvoke
	redeem.OnServerInvoke = function(...)
		serverCalls += 1
		return inner(...)
	end
end

local RunServiceEarly = h.game:GetService("RunService")
RunServiceEarly:setIsServer(false) -- the scripts run from here on are client scripts (FxClient acts)

local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
truthy(hrp ~= nil and hum ~= nil, "the climber has a root part and a humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)

local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local folder = h.workspace:FindFirstChild("Plus1LocalSky")
truthy(folder ~= nil, "the client made its local sky folder")
local skyGui = plr.PlayerGui:FindFirstChild("Plus1Sky")
truthy(skyGui ~= nil, "and its ScreenGui")
local root = skyGui and skyGui:FindFirstChild("Root")
local chip = root and root:FindFirstChild("BandChip")
local restBtn = root and root:FindFirstChild("RestButton")
local warningLabel = root and root:FindFirstChild("HazardWarning")
local card = root and root:FindFirstChild("BandCard")
truthy(chip and restBtn and warningLabel and card, "chip, rest button, warning and title card exist")

local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local simTime = 0
local announced = {} -- every distinct title card text, polled per frame
local lastCard = ""
-- Climbing seconds as the CLIENT counts them: every frame the client is not resting. Read from the
-- chip, which the client writes from the same rest state it hands the hazard scheduler that frame.
local climbClock = 0
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt
	if chip and not (string.find(chip.Text, "Resting", 1, true) or string.find(chip.Text, "Idle", 1, true)) then
		climbClock += dt
	end
	if card and card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(announced, card.Text)
	end
	for _, g in plr.PlayerGui:GetChildren() do
		if g.Name == "FxFlash" and not g:GetAttribute("__counted") then
			g:SetAttribute("__counted", true)
			table.insert(announced, "<flash>")
		end
	end
end
local function run(seconds, dt, each)
	local n = math.floor(seconds / dt + 0.5)
	for i = 1, n do
		frame(dt)
		if each then
			if each(i) == false then return end
		end
	end
end
local function moveToProgress(p)
	local y = Progression.yAtProgress(p, Tower)
	hrp.CFrame = CFrame.new(hrp.Position.X, y + 3.5, hrp.Position.Z)
end

--======================================================================= 1. altitude == the real tower

do
	local tower = h.workspace:FindFirstChild("Tower")
	local checked, worst = 0, 0
	for _, part in tower:GetChildren() do
		local t, i = string.match(part.Name, "^P_(%d+)_(%d+)$")
		if t then
			t, i = tonumber(t), tonumber(i)
			local d = math.abs(Progression.tierProgressAtY(part.Position.Y, Tower) - ((t - 1) + i / Tower.TilesPerTier))
			if d > worst then worst = d end
			checked += 1
		end
	end
	truthy(checked >= 30, "the server built platforms to compare against (" .. checked .. ")")
	truthy(worst < 1e-6, "every server-built platform reads as (t-1)+i/6 tiers climbed (worst " .. worst .. ")")
end

--======================================================================= 2. the takeover does not jump

run(1.0, 1 / 30)
near(Lighting.ClockTime, serverClock, 0.01, "at the start pad the client keeps the server's ClockTime (no jump at join)")
near(Lighting.Brightness, serverBright, 0.01, "and its Brightness")
near(serverAtmos and serverAtmos.Density, serverDensity, 0.005, "and the atmosphere density")
eq(Lighting:FindFirstChild("FxAtmosphere") == serverAtmos, true, "the client reused the server's Atmosphere, not a second one")

--======================================================================= 3. every band, and every seam

local PIECE_PART = {
	templeIsland = "IslandGrass", canopy = "CanopyPuff", cloudDeck = "CloudDeckPuff", stormDeck = "StormDeckPuff",
	aurora = "AuroraHost", horizonGlow = "SunsetDisc", earth = "AirGlow", station = "Hub",
	ringedPlanet = "RingShade", nebula = "Nebula", galaxy = "Core",
}
local function shownParts(name)
	local n = 0
	for _, c in folder:GetChildren() do
		if c.Name == name then n += 1 end
	end
	return n
end

local budget = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0, hazards = 0 }
local budgetWhere = {}
local function measure(where)
	local parts, emitters, rate, beams, trails, lights = 0, 0, 0, 0, 0, 0
	local hazardKinds = {}
	for _, d in folder:GetDescendants() do
		local cls = d.ClassName
		if cls == "Part" or cls == "WedgePart" then
			parts += 1
			local kind = string.match(d.Name, "^Hazard_([%a]+)_")
			if kind then hazardKinds[kind] = true end
		elseif cls == "ParticleEmitter" and d.Enabled then
			emitters += 1
			rate += d.Rate or 0
		elseif cls == "Beam" and d.Enabled then
			beams += 1
		elseif cls == "Trail" and d.Enabled then
			trails += 1
		elseif cls == "PointLight" and d.Enabled then
			lights += 1
		end
	end
	local suit = hrp:FindFirstChild("Plus1SuitLight")
	if suit and suit.Brightness > 0 then lights += 1 end
	local hz = 0
	for _ in hazardKinds do hz += 1 end
	local m = { parts = parts, emitters = emitters, rate = rate, beams = beams, trails = trails, lights = lights, hazards = hz }
	for k, v in m do
		if v > budget[k] then
			budget[k] = v
			budgetWhere[k] = where
		end
	end
	return m
end

-- a climber on the move (input held), so standing in place for 8 s is not mistaken for idling
hum.MoveDirection = Vector3.new(1, 0, 0)
local function layerAt(p)
	for _, layer in Config.Env.Layers do
		if EnvBands.layerWeight(layer, p) > 0 then return true end
	end
	return false
end

for i, b in bands do
	local nextFrom = if bands[i + 1] then bands[i + 1].from - (bands[i + 1].fade or 0) else b.from + 40
	local mid = (b.from + nextFrom) / 2
	while layerAt(mid) do mid += 1.5 end -- probe the band itself, not a cloud deck inside it
	moveToProgress(mid)
	run(8, 1 / 30)
	local where = string.format("%s (p=%.1f)", b.id, mid)
	near(Lighting.ClockTime, b.lighting.ClockTime, 0.05, where .. ": Lighting.ClockTime reached the band's value")
	local atm = Lighting:FindFirstChild("FxAtmosphere")
	near(atm.Density, b.atmosphere.Density, 0.01, where .. ": Atmosphere.Density reached the band's value")
	local sky = Lighting:FindFirstChild("Plus1Sky")
	near(sky and sky.StarCount, b.sky.StarCount, 1, where .. ": Sky.StarCount reached the band's value")
	truthy(string.find(chip.Text, b.name, 1, true) ~= nil, where .. ": the chip names the band (" .. chip.Text .. ")")
	local sawCard = false
	for _, t in announced do
		if string.find(string.upper(t), string.upper(b.name), 1, true) or (b.celebrate and string.find(t, "SPACE", 1, true)) then
			sawCard = true
		end
	end
	truthy(sawCard, where .. ": a title card announced it")
	if b.celebrate then
		local flashAfterSpace = false
		local seenSpace = false
		for _, t in announced do
			if string.find(t, "YOU REACHED SPACE", 1, true) then seenSpace = true end
			if seenSpace and t == "<flash>" then flashAfterSpace = true end
		end
		truthy(flashAfterSpace, where .. ": reaching space during play is CELEBRATED (flash)")
	end
	for _, id in b.pieces do
		truthy(shownParts(PIECE_PART[id]) > 0, where .. ": scenery `" .. id .. "` is shown")
	end
	-- scenery of bands that are not blending here must be gone (unparented, costing nothing)
	local mine = {}
	for _, id in b.pieces do mine[id] = true end
	for id, partName in PIECE_PART do
		if not mine[id] then
			eq(shownParts(partName), 0, where .. ": scenery `" .. id .. "` from another band is hidden")
		end
	end
	local anyCritter = false
	for _, a in b.ambient do
		for _, c in folder:GetChildren() do
			if c.Name == a.kind or string.find(c.Name, "^" .. a.kind) then anyCritter = true end
		end
	end
	local critterParts = 0
	for _, c in folder:GetChildren() do
		if not string.find(c.Name, "Puff$") and not string.find(c.Name, "^Island") then critterParts += 1 end
	end
	truthy(critterParts > 0, where .. ": something is alive in the sky")
	local host = folder:FindFirstChild("WeatherHost")
	local pe = host and host:FindFirstChild("Weather_" .. b.weather.kind)
	truthy(pe ~= nil and pe.Enabled, where .. ": its weather (" .. b.weather.kind .. ") is on")
	near(pe and pe.Rate, b.weather.rate, 0.5, where .. ": at the configured rate")
	local m = measure(where)
	print(string.format("  %-22s parts %3d  emitters %d (%.0f/s)  beams %d  trails %d  lights %d  chip: %s",
		where, m.parts, m.emitters, m.rate, m.beams, m.trails, m.lights, chip.Text))

	-- the seam into the next band: both bands' content is live, measured for the budget
	if bands[i + 1] then
		local nb = bands[i + 1]
		local seam = nb.from - (nb.fade or 0) / 2
		moveToProgress(seam)
		run(8, 1 / 30)
		local sm = measure(string.format("%s>%s seam (p=%.1f)", b.id, nb.id, seam))
		print(string.format("  %-22s parts %3d  emitters %d (%.0f/s)  beams %d  trails %d  lights %d",
			b.id .. ">" .. nb.id, sm.parts, sm.emitters, sm.rate, sm.beams, sm.trails, sm.lights))
		if (nb.fade or 0) > 0 then
			for _, id in nb.pieces do
				if not table.find(b.pieces, id) then
					truthy(shownParts(PIECE_PART[id]) > 0, b.id .. ">" .. nb.id .. " seam: the next band's `" .. id .. "` is already fading in")
				end
			end
		end
	end
end

--======================================================================= 4. never a hard cut

do
	moveToProgress(1)
	run(10, 1 / 30)
	local from = Lighting.ClockTime
	local orbit = bands[EnvBands.indexOf(bands, "orbit")]
	moveToProgress(orbit.from + 20) -- a teleport: temple -> space in one frame
	local prev, worstStep, overshoot = from, 0, false
	local target = orbit.lighting.ClockTime
	run(8, 1 / 30, function()
		local v = Lighting.ClockTime
		local stepSize = math.abs(v - prev)
		if stepSize > worstStep then worstStep = stepSize end
		if v > target + 1e-6 then overshoot = true end
		prev = v
	end)
	local total = math.abs(target - from)
	print(string.format("  teleport temple->orbit: ClockTime %.2f -> %.2f, largest single write %.3f (%.0f%% of the change)",
		from, Lighting.ClockTime, worstStep, worstStep / total * 100))
	truthy(worstStep <= total * 0.15, "a teleport glides: no single write moves ClockTime more than 15% of the way")
	eq(overshoot, false, "and it never overshoots")
	near(Lighting.ClockTime, target, 0.05, "and it arrives")
end
do
	-- climbing through the cloud deck and on into the storm, at a climber's pace
	moveToProgress(20)
	run(4, 1 / 30)
	local atm = Lighting:FindFirstChild("FxAtmosphere")
	local prev, worst, peak = atm.Density, 0, 0
	local p = 20
	run(90, 1 / 30, function()
		p += 17 / (90 * 30)
		moveToProgress(p)
		local v = atm.Density
		if math.abs(v - prev) > worst then worst = math.abs(v - prev) end
		if v > peak then peak = v end
		prev = v
	end)
	print(string.format("  climbing p 20->37 (cloud deck at 22, into the storm): density peak %.2f, worst per-frame change %.4f", peak, worst))
	truthy(peak > 0.45, "climbing through the cloud deck fogs you in (density peak " .. string.format("%.2f", peak) .. ")")
	truthy(worst <= 0.02, "and every change is gradual (worst " .. string.format("%.4f", worst) .. " per frame)")
end

--======================================================================= 5. hazards through the glue

-- earn a couple of platforms the honest way, so the rescue has something better than the pad
local function touch(name)
	local part = h.workspace:FindFirstChild("Tower"):FindFirstChild(name)
	part.Touched:Fire(hrp)
end
for i = 1, 6 do touch("P_1_" .. i) end
touch("P_2_1")
local earned = h.workspace:FindFirstChild("Tower"):FindFirstChild("P_2_1")

local cloud = bands[EnvBands.indexOf(bands, "cloudsea")]
local climbP = 26
moveToProgress(climbP)
hum.MoveDirection = Vector3.new(1, 0, 0) -- "moving" input without physics: never idles into rest
hrp.AssemblyLinearVelocity = Vector3.zero
run(2, 0.1)

local function hazardShown()
	local kind = nil
	local count = 0
	local seen = {}
	for _, c in folder:GetChildren() do
		local k = string.match(c.Name, "^Hazard_([%a]+)_")
		if k and not seen[k] then
			seen[k] = true
			count += 1
			kind = k
		end
	end
	return kind, count
end

local spawns, hits, maxAtOnce = 0, 0, 0
local appearedAt, wasShown = nil, false
local telegraphs = {}
local kindsSeen = {}
local sawIncoming, sawMove = false, false
local spawnClimbTimes = {}
local completed = 0
local knockSample = nil
local platformStandAtHit = nil
local rescued = nil

local function hazardTick(dt, climbing)
	local kind, count = hazardShown()
	if count > maxAtOnce then maxAtOnce = count end
	if kind then measure("hazard in flight (" .. kind .. ", p=" .. string.format("%.1f", Progression.tierProgressAtY(hrp.Position.Y - 3.5, Tower)) .. ")") end
	if kind and not wasShown then
		spawns += 1
		appearedAt = simTime
		kindsSeen[kind] = true
		table.insert(spawnClimbTimes, climbClock)
	end
	if wasShown and kind == nil then completed += 1 end
	wasShown = kind ~= nil
	if warningLabel.Visible then
		if string.find(warningLabel.Text, "INCOMING", 1, true) then sawIncoming = true end
		if string.find(warningLabel.Text, "MOVE!", 1, true) then sawMove = true end
	end
	local v = hrp.AssemblyLinearVelocity
	if v.Magnitude > 1 then
		hits += 1
		if appearedAt then table.insert(telegraphs, simTime - appearedAt) end
		if knockSample == nil then
			knockSample = v
			platformStandAtHit = hum.PlatformStand
		end
		hrp.AssemblyLinearVelocity = Vector3.zero
		return "hit"
	end
	return nil
end

local MINUTES = 20
run(MINUTES * 60, 0.1, function()
	local r = hazardTick(0.1, true)
	if r == "hit" and rescued == nil then
		-- the fall a knock causes, simulated: then the SERVER's rescue must bring the climber back
		local standBack = hum.PlatformStand
		hrp.CFrame = CFrame.new(hrp.Position.X, -6000, hrp.Position.Z)
		for _ = 1, 10 do frame(0.1) end
		rescued = { pos = hrp.Position, standAfterKnock = nil }
		local want = earned.Position + Vector3.new(0, 4, 0)
		rescued.distance = (hrp.Position - want).Magnitude
		for _ = 1, 10 do frame(0.1) end
		rescued.standAfterKnock = hum.PlatformStand
		moveToProgress(climbP)
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end)

-- let a hazard launched in the last seconds finish its flight before anything is counted
run(10, 0.1, function() hazardTick(0.1, true); return hazardShown() ~= nil end)
print(string.format("  hazards over %d simulated minutes of climbing: %d launched, %d flew their whole flight, %d hits, most at once %d", MINUTES, spawns, completed, hits, maxAtOnce))
truthy(spawns >= 6 and spawns <= 10, "one hazard per 2-3 minutes of climbing through the real client (" .. spawns .. " in " .. MINUTES .. " min)")
eq(maxAtOnce, 1, "never more than one hazard at a time")
local okKinds = true
for k in kindsSeen do
	if not table.find(cloud.hazards, k) then okKinds = false; print("  unexpected hazard kind in the cloud band: " .. k) end
end
truthy(okKinds and next(kindsSeen) ~= nil, "only the band's own hazard kinds appear (birds and planes in the cloud sea)")
eq(completed, spawns, "every launched hazard finished its flight")
eq(hits, completed, "a climber who stands still in the lane is hit by every hazard (they are aimed, not random)")
local shortest = math.huge
for _, t in telegraphs do if t < shortest then shortest = t end end
truthy(shortest >= Config.Hazards.MinTelegraphSeconds - 0.15,
	string.format("every hazard was visible at least %.1f s before it hit (shortest %.2f s)", Config.Hazards.MinTelegraphSeconds, shortest))
truthy(sawIncoming, "the warning says it is coming")
truthy(sawMove, "and says MOVE once the lane locks")
do
	local minGap, maxGap = math.huge, 0
	for i = 2, #spawnClimbTimes do
		local g = spawnClimbTimes[i] - spawnClimbTimes[i - 1]
		if g < minGap then minGap = g end
		if g > maxGap then maxGap = g end
	end
	-- the rescue interlude in this loop adds ~2 s of frames to one gap
	truthy(minGap >= Config.Hazards.IntervalMin - 0.2, string.format("gaps between hazards are never under IntervalMin (%.1f s)", minGap))
	truthy(maxGap <= Config.Hazards.IntervalMax + 3, string.format("nor much over IntervalMax (%.1f s)", maxGap))
end

truthy(knockSample ~= nil, "a hit knocked the character")
if knockSample then
	local horiz = Vector3.new(knockSample.X, 0, knockSample.Z).Magnitude
	truthy(horiz >= 20, string.format("the knock pushes the climber sideways off the platform (%.0f studs/s)", horiz))
	truthy(knockSample.Y <= 15, string.format("and never launches them upward (%.1f studs/s up)", knockSample.Y))
	eq(platformStandAtHit, true, "the humanoid is platform-standing so the push actually carries")
end
truthy(rescued ~= nil, "a knocked climber fell")
if rescued then
	truthy(rescued.distance <= 0.5, string.format("and the SERVER's rescue put them back on the platform they last earned (%.2f studs off)", rescued.distance))
	eq(rescued.standAfterKnock, false, "and the knock wore off (PlatformStand released)")
end

-- the worst budget case: a hazard in flight at the densest seam of the whole sky
do
	local densest = tonumber(string.match(tostring(budgetWhere.parts), "p=([%d%.]+)"))
	truthy(densest ~= nil, "the sweep found a densest point to re-measure with a hazard (" .. tostring(budgetWhere.parts) .. ")")
	if densest then
		moveToProgress(densest)
		hum.MoveDirection = Vector3.new(1, 0, 0)
		local bandHere = bands[EnvBands.indexAt(bands, densest)]
		run(Config.Hazards.IntervalMax + 10, 0.1, function()
			hazardTick(0.1, true)
			return hazardShown() == nil
		end)
		truthy(#bandHere.hazards == 0 or hazardShown() ~= nil,
			"a hazard flew at the densest seam (" .. bandHere.id .. ") and was measured")
		run(8, 0.1, function() hazardTick(0.1, true) end)
		moveToProgress(climbP)
		hrp.AssemblyLinearVelocity = Vector3.zero
		run(2, 0.1)
	end
end

--======================================================================= 6. rest

-- wait for a clear sky
run(12, 0.1, function() hazardTick(0.1, true); return hazardShown() ~= nil end)
run(10, 0.1, function() hazardTick(0.1, true); return hazardShown() ~= nil end)
hum.MoveDirection = Vector3.new(0, 0, 0)
local beforeRestSpawns = spawns
restBtn.Activated:Fire()
run(0.5, 0.1)
eq(hum.Sit, true, "pressing Rest on a platform with a clear sky sits the climber down")
truthy(string.find(chip.Text, "Resting", 1, true) ~= nil, "the chip says so (" .. chip.Text .. ")")
eq(Lighting:FindFirstChild("Plus1RestFocus").Enabled, true, "and the view softens")
-- a seated Humanoid may report no floor; sitting still must not count as leaving the ground
hum.FloorMaterial = Enum.Material.Air
run(3, 0.1)
eq(hum.Sit, true, "a seated climber whose Humanoid reports no floor keeps resting (not falling)")
hum.FloorMaterial = Enum.Material.Plastic
local restSeconds = 10 * 60
run(restSeconds, 0.2, function() hazardTick(0.2, false) end)
eq(spawns, beforeRestSpawns, "ten minutes of rest: not a single hazard")
eq(hum.Sit, true, "still resting after ten minutes")
local lastBefore = spawnClimbTimes[#spawnClimbTimes]
hum.MoveDirection = Vector3.new(1, 0, 0)
run(1, 0.1, function() hazardTick(0.1, true) end)
eq(hum.Sit, false, "moving wakes the climber (stands up)")
truthy(string.find(chip.Text, "Resting", 1, true) == nil, "and the chip is back to the band")
local woke = spawns
run(Config.Hazards.IntervalMax + 10, 0.1, function() hazardTick(0.1, true); return spawns == woke end)
truthy(spawns > woke, "hazards resume after rest")
if spawns > woke and lastBefore then
	local gap = spawnClimbTimes[#spawnClimbTimes] - lastBefore
	truthy(gap >= Config.Hazards.IntervalMin - 0.5 and gap <= Config.Hazards.IntervalMax + 3,
		string.format("the next hazard came %.1f CLIMBING seconds after the last one, across a %d-minute rest: the clock froze, it did not reset", gap, restSeconds / 60))
end

-- not a panic button: press Rest while a hazard is inbound
local function nextHazard()
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(Config.Hazards.IntervalMax + 10, 0.1, function() hazardTick(0.1, true); return hazardShown() == nil end)
	truthy(hazardShown() ~= nil, "set-up: a hazard is inbound")
	hum.MoveDirection = Vector3.new(0, 0, 0)
end

-- (a) press Rest, stay in the lane: the hazard is NOT cancelled, it hits, and the hit voids the request
nextHazard()
local hitsBefore = hits
restBtn.Activated:Fire()
run(0.2, 0.1)
eq(hum.Sit, false, "pressing Rest with a hazard inbound does NOT rest")
truthy(string.find(restBtn.Text, "…", 1, true) ~= nil, "the button shows the request is queued (" .. restBtn.Text .. ")")
run(1.5, 0.1, function() hazardTick(0.1, true) end)
truthy(hazardShown() ~= nil, "the hazard is still coming (rest removed nothing)")
run(8, 0.1, function() hazardTick(0.1, true) end)
eq(hits, hitsBefore + 1, "and it still arrives: the climber who stayed put is hit")
run(4, 0.1)
eq(hum.Sit, false, "a hit voids the queued rest (no sitting down mid-fall)")
truthy(string.find(restBtn.Text, "Rest", 1, true) ~= nil, "and the button is back to Rest (" .. restBtn.Text .. ")")

-- (b) press Rest, then step off the locked lane: no hit, and the rest begins once the sky is clear
nextHazard()
local hitsB = hits
restBtn.Activated:Fire()
local stepped = false
run(10, 0.1, function()
	hazardTick(0.1, true)
	if not stepped and warningLabel.Visible and string.find(warningLabel.Text, "MOVE!", 1, true) then
		stepped = true
		-- what a player does: look at the red lane and step half a tile away from it
		local lane = folder:FindFirstChild("HazardLane")
		local dir = lane.CFrame.LookVector
		local flat = Vector3.new(dir.X, 0, dir.Z)
		local perp = if flat.Magnitude > 1e-3 then Vector3.new(-flat.Z, 0, flat.X).Unit else Vector3.new(1, 0, 0)
		if (hrp.Position - lane.Position):Dot(perp) < 0 then perp = -perp end
		hrp.CFrame = CFrame.new(hrp.Position + perp * 4)
	end
	return hazardShown() ~= nil or hum.Sit ~= true
end)
truthy(stepped, "the climber saw MOVE! and stepped aside")
eq(hits, hitsB, "stepping half a tile off the locked lane dodged it")
run(3, 0.1)
eq(hum.Sit, true, "once the sky is clear, the queued rest begins")
restBtn.Activated:Fire()
run(0.3, 0.1)
eq(hum.Sit, false, "pressing the button again ends it")
truthy(string.find(chip.Text, "Resting", 1, true) == nil, "and the chip is back to the band")

-- idle rest (AFK safety): standing still long enough
hum.MoveDirection = Vector3.new(0, 0, 0)
run(Config.Rest.IdleSeconds + 1, 0.1)
truthy(string.find(chip.Text, "Idle", 1, true) ~= nil, "standing still " .. Config.Rest.IdleSeconds .. " s rests automatically (" .. chip.Text .. ")")
eq(hum.Sit, false, "idle rest does not sit anybody down")
local idleSpawns = spawns
run(6 * 60, 0.2, function() hazardTick(0.2, false) end)
eq(spawns, idleSpawns, "an idle climber gets no hazards (six minutes)")

--======================================================================= 7. the brag: bands on the HUD

do
	local hudRoot = plr.PlayerGui:FindFirstChild("Plus1Hud")
	local state = remotes:FindFirstChild("State")
	state:FireClient(plr, { jumpPower = 500, jumpHeight = 60, tier = 90, bestTier = 90, rebirths = 0, multiplier = 1,
		nextRebirthTier = 10, canRebirth = true })
	local best = nil
	for _, d in hudRoot:GetDescendants() do
		if d.ClassName == "TextLabel" and string.find(d.Text or "", "Best", 1, true) then best = d end
	end
	truthy(best ~= nil and string.find(best.Text, "🚀", 1, true) ~= nil, "a best tier in space shows 🚀 on the HUD (" .. tostring(best and best.Text) .. ")")
	local lb = remotes:FindFirstChild("Leaderboard")
	lb:FireClient(plr, { { userId = 1, tier = 250 }, { userId = 2, tier = 90 }, { userId = 3, tier = 20 }, { userId = 4, tier = 3 } })
	local rows = {}
	for _, d in hudRoot:GetDescendants() do
		if d.ClassName == "TextLabel" and string.match(d.Text or "", "^%d+%. ") then rows[tonumber(string.match(d.Text, "^(%d+)"))] = d.Text end
	end
	truthy(rows[1] and string.find(rows[1], "🌌", 1, true), "the board shows the galaxy for tier 250 (" .. tostring(rows[1]) .. ")")
	truthy(rows[2] and string.find(rows[2], "🚀", 1, true), "space for tier 90 (" .. tostring(rows[2]) .. ")")
	truthy(rows[3] and string.find(rows[3], "☁️", 1, true), "the cloud sea for tier 20 (" .. tostring(rows[3]) .. ")")
	truthy(rows[4] and string.find(rows[4], "🏛️", 1, true), "the temple for tier 3 (" .. tostring(rows[4]) .. ")")
end

--======================================================================= 8. the sky row never covers the HUD

do
	local VIEWPORTS = require("./emu/hudcheck").VIEWPORTS
	local hudGui = plr.PlayerGui:FindFirstChild("Plus1Hud")
	local worst = nil
	-- the warning only shows during a hazard; force it on so its box is measured too (no frames run
	-- in this section, so the client does not hide it again)
	warningLabel.Visible = true
	warningLabel.Text = "⚠️ MOVE! WEATHER BALLOON ◀"
	for _, v in VIEWPORTS do
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		h:advance(0.1)
		local hudRects = {}
		for _, r in h:guiRects(hudGui, v.w, v.h) do
			if r.shown and r.depth == 2 then table.insert(hudRects, r) end
		end
		-- open each phone drawer in turn, so a drawer that would open onto the sky row is measured
		local function sky()
			local out = {}
			for _, r in h:guiRects(skyGui, v.w, v.h) do
				if r.shown and (r.name == "BandChip" or r.name == "RestButton" or r.name == "HazardWarning") then
					table.insert(out, r)
				end
			end
			return out
		end
		local function check(rects, label)
			for _, a in sky() do
				for _, b in rects do
					local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
					local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
					if ox > 1 and oy > 1 then
						worst = string.format("%s: %s overlaps HUD %s by %.0fx%.0f px (%s)", v.name, a.name, b.name, ox, oy, label)
					end
				end
			end
		end
		check(hudRects, "closed")
		for _, r in h:guiRects(skyGui, v.w, v.h) do
			if r.shown and (r.name == "BandChip" or r.name == "RestButton" or r.name == "HazardWarning") then
				if r.sx < -1 or r.sy < -1 or r.sx + r.sw > v.w + 1 or r.sy + r.sh > v.h + 1 then
					worst = string.format("%s: %s is off screen", v.name, r.name)
				end
			end
		end
		for _, toggleName in { "MenuToggle", "TopToggle" } do
			local t = hudGui:FindFirstChild("Root"):FindFirstChild(toggleName)
			if t and t.Visible then
				t.Activated:Fire()
				h:advance(0.1)
				local open = {}
				for _, r in h:guiRects(hudGui, v.w, v.h) do
					if r.shown and r.depth == 2 then table.insert(open, r) end
				end
				check(open, toggleName .. " open")
				t.Activated:Fire()
				h:advance(0.1)
			end
		end
	end
	eq(worst, nil, "the band chip, Rest button and warning stay on screen and never overlap any HUD panel, drawer or toggle, at any viewport")
	warningLabel.Visible = false
	h:setTouch(false)
	h:setViewport(1280, 720)
	h:advance(0.1)
end

--======================================================================= 9. nothing leaks, nothing changes on the server

do
	local now = {}
	for _, r in remotes:GetChildren() do table.insert(now, r.Name) end
	table.sort(now)
	eq(table.concat(now, ","), table.concat(remoteNames, ","), "the client added no remotes")
	eq(serverCalls, 0, "the sky, hazards and rest never called the server (no remote fired, no invoke)")
	local extra = 0
	for _, part in h.workspace:FindFirstChild("Tower"):GetChildren() do
		for k in part:GetAttributes() do
			if k ~= "Tier" and k ~= "Idx" then extra += 1 end
		end
	end
	eq(extra, 0, "no server-built part was tagged by the client")
	local stray = 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and (d.CanCollide ~= false or d.CanQuery ~= false or d.CanTouch ~= false) then stray += 1 end
	end
	eq(stray, 0, "every local sky part is non-collidable, non-queryable and non-touchable")
end

--======================================================================= 10. budgets

local B = Config.Budget
print("")
print("  MEASURED PEAKS (client-built, across every band and every seam, hazards included):")
print(string.format("    parts %d (budget %d) at %s", budget.parts, B.MaxLocalParts, tostring(budgetWhere.parts)))
print(string.format("    emitters %d (budget %d), total rate %.0f/s (budget %d) at %s", budget.emitters, B.MaxEmitters, budget.rate, B.MaxEmitterRate, tostring(budgetWhere.rate)))
print(string.format("    beams %d (budget %d), trails %d (budget %d), lights %d (budget %d)", budget.beams, B.MaxBeams, budget.trails, B.MaxTrails, budget.lights, B.MaxLights))
truthy(budget.parts <= B.MaxLocalParts, "local parts within budget")
truthy(budget.emitters <= B.MaxEmitters, "emitters within budget")
truthy(budget.rate <= B.MaxEmitterRate, "emitter rate within budget")
truthy(budget.beams <= B.MaxBeams, "beams within budget")
truthy(budget.trails <= B.MaxTrails, "trails within budget")
truthy(budget.lights <= B.MaxLights, "lights within budget")

--=========================================================================================== done

print("")
eq(#h.warnings, 0, "no warnings (a sky frame error would warn)")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1 sky: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1 sky check failed", 0)
end
