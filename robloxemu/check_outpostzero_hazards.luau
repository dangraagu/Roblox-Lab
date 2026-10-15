-- Outpost Zero — hazards through the real client glue: when they may launch, that the red ring drawn is EXACTLY the
-- hit zone and lies on what the player stands on, that stepping out of it in any of 8 directions always dodges, that
-- a break freezes their clock (never resets it), and that the Grand Airship's arrival is never interrupted.
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_hazards.luau 2>&1
--
-- Config.Hazards.IntervalMin/Max are set to 8/9 s IN MEMORY for this run only, so a short check sees many hazards
-- (+1 Jump's and meteor-drop-tycoon's hazards checks do the same). The rules under test are the gates in
-- Sky.client.luau: only on your own shelf, grounded, not resting, not during the airship, nothing in the first band.
-- Nothing renders headless: "a hit" is the knock Sky.client applies (PlatformStand on the local Humanoid).
-- (adapted from check_meteordroptycoon_hazards.luau)

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 7777
local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
store:SetAsync("u_" .. UID, { data = { v = 1, seed = 777, credits = 1e15, lifetime = 1e15, lots = {}, savedAt = os.time(),
	ordersUntil = os.time() + 600, popAt = 0, airshipSeen = false, tutorial = 3 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Hz = Config.Hazards
Hz.IntervalMin, Hz.IntervalMax = 8, 9 -- in memory, this run only

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Dodger", UID)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
-- an R15 character's real proportions (robloxemu's root is a default Part): HipHeight 2, a 2 x 2 x 1 root, so the
-- root stands 3 studs above the floor and Sky.client's floor (root - HipHeight - half the root) is that floor
hrp.Size = Vector3.new(2, 2, 1)
hum.HipHeight = 2
hum.FloorMaterial = Enum.Material.Rock
hum.MoveDirection = Vector3.new(0.01, 0, 1) -- steering input: never idles into rest
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Sky.client"))

local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local folder = h.workspace:FindFirstChild("OutpostLocalSky")
local skyGui = plr.PlayerGui:FindFirstChild("OutpostSky")
local probe = skyGui:FindFirstChild("OutpostSkyProbe")
local warning = skyGui.Root:FindFirstChild("WarningPanel")
local remotes = RS:FindFirstChild("CityRemotes")
local pad = plr.RespawnLocation
local shelf = pad.Parent
local rock = shelf:FindFirstChild("Rock")
local centre = rock.Position
-- home: on the open plaza, halfway between the pad and the shelf's centre's far side (no lot, no building)
local home = Vector3.new(pad.Position.X + (centre.X - pad.Position.X) * 0.5, 3.0, pad.Position.Z + (centre.Z - pad.Position.Z) * 0.5)
local ROOT_ABOVE_FLOOR = 3 -- the emulator's character: HipHeight 2 + half the 2-stud root

-- Sizes Roblox draws as written (round 2, finding B1): a Ball is forced uniform, a Cylinder round (Y = Z), and every
-- axis is clamped to 2048 studs. robloxemu keeps any size, so this is asserted on every part shown
-- (anomaly-observatory EYECANDY "Sizes the engine draws as written"). Returns nil, or why not.
local function engineDraws(d)
	local s = d.Size
	local shape = if d.ClassName == "Part" then d.Shape else nil
	if shape == Enum.PartType.Ball and (math.abs(s.X - s.Y) > 1e-6 or math.abs(s.Y - s.Z) > 1e-6) then return "a non-uniform Ball" end
	if shape == Enum.PartType.Cylinder and math.abs(s.Y - s.Z) > 1e-6 then return "an oval Cylinder" end
	if s.X > 2048 or s.Y > 2048 or s.Z > 2048 then return "an axis over 2048" end
	return nil
end
local engineBad, engineBadN = {}, 0
local function engineScan(root, where)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local why = engineDraws(d)
			if why and engineBad[d.Name] == nil then
				engineBad[d.Name] = string.format("%s is %s (%.1f x %.1f x %.1f, %s)", d.Name, why, d.Size.X, d.Size.Y, d.Size.Z, where)
				engineBadN += 1
			end
		end
	end
end
local function engineReport()
	local list = {}
	for _, v in engineBad do table.insert(list, v) end
	table.sort(list)
	return list
end

local maxModels, maxParts, maxLights = 0, 0, 0
local kindsSeen = {}
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
	local k1, n = hazardKind()
	if k1 then kindsSeen[k1] = true end
	maxModels = math.max(maxModels, n)
	engineScan(folder, "a hazard")
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
-- press the ★ lot's prompt (stood at its post) until the population reaches `target`, then come home
local function buyTo(target)
	for _ = 1, 5000 do
		local st = stateOf()
		if st.population >= target or st.star == nil then break end
		local post = shelf.Lots:FindFirstChild("Lot_" .. st.star.key).Post
		place(post.Position + Vector3.new(0, 1.5, 0))
		post.BuildPrompt.Triggered:Fire(plr)
		h:advance(0.13)
	end
	place(home)
	return stateOf().population
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

--============================================================================ 1. the first band is quiet
place(home)
eq(stateOf().population, 0, "set-up: population 0, Fogbound Dawn")
eq(spawnsDuring(40), 0, "the first band sends nothing, 40 s at an 8-9 s interval")

--============================================================================ 2. hazards start in Clear Morning
local p = buyTo(900) -- Trade Winds: crates and sandbags
truthy(p >= 900, "set-up: population " .. p .. " (Trade Winds)")
truthy(waitForSpawn(12), "a hazard band sends a hazard once the interval is up")
waitIdle()

--============================================================================ 3. only on your OWN shelf
do
	-- over the open sky at the ring's centre, on nobody's shelf (standing on air the emulator calls ground)
	place(Vector3.new(0, 12, 0))
	local c0 = probe:Invoke().hazardClock
	eq(spawnsDuring(30), 0, "off your shelf, nothing launches in 30 s")
	eq(probe:Invoke().hazardClock, c0, "and the hazard clock does not run there (it counts time on your own shelf)")
	place(home)
	truthy(waitForSpawn(12), "back on your shelf, the hazards come again")
	waitIdle()
end

--============================================================================ 4. grounded only
do
	hum.FloorMaterial = Enum.Material.Air
	eq(spawnsDuring(25), 0, "nothing launches at a player in the air, however long it is due")
	hum.FloorMaterial = Enum.Material.Rock
	local landed = nil
	for i = 1, 40 do
		frame(0.05)
		if probe:Invoke().hazardActive then landed = i * 0.05 break end
	end
	truthy(landed ~= nil, "the due hazard launches as soon as they stand on something (" .. tostring(landed) .. " s)")
	waitIdle()
end

--============================================================================ 5. a break freezes the clock, never resets it
do
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local btn = skyGui.Root.BreakSlot.BreakButton
	btn.Activated:Fire()
	frame(0.05)
	eq(probe:Invoke().resting, true, "☕ Break rests")
	local c0 = probe:Invoke().hazardClock
	eq(spawnsDuring(40), 0, "nothing launches during 40 s of break")
	eq(probe:Invoke().hazardClock, c0, "the hazard clock is frozen during the break")
	hum.MoveDirection = Vector3.new(0.01, 0, 1)
	frame(0.5)
	frame(0.05)
	eq(probe:Invoke().resting, false, "moving ends the break")
	local c1 = probe:Invoke().hazardClock
	truthy(c1 >= c0 and c1 - c0 < 1, string.format("the clock resumes from where it stopped, not from zero (%.2f -> %.2f)", c0, c1))
	truthy(waitForSpawn(12), "and hazards come again")
	waitIdle()
	-- toggling the break does not thin hazards out: the clock only ever pauses
	local s0 = probe:Invoke().hazardsSpawned
	local played = 0
	for _ = 1, 12 do
		btn.Activated:Fire() -- on
		for _ = 1, 20 do frame(0.05) end
		hum.MoveDirection = Vector3.new(0.01, 0, 1)
		for _ = 1, 100 do frame(0.05) end
		played += 5
		hum.MoveDirection = Vector3.new(0, 0, 0)
	end
	hum.MoveDirection = Vector3.new(0.01, 0, 1)
	local n = probe:Invoke().hazardsSpawned - s0
	print(string.format("  toggling the break every 6 s for 72 s (60 s of play): %d hazards (one per 8-9 s of play: %d-%d)", n, math.floor(played / 9), math.ceil(played / 8) + 1))
	truthy(n >= math.floor(played / 9) - 1, "toggling the break never thins hazards out below the play-time rate")
	waitIdle()
end

--============================================================================ 6. the red ring is exactly the hit zone; stepping out always dodges
local function nextLocked(at)
	place(at or home)
	if not waitForSpawn(15) then return nil end
	for _ = 1, 200 do
		if at then place(at) end
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
		truthy(math.sqrt(dx * dx + dz * dz) < 1e-6, "and it is centred where the player stands")
		local floorY = hrp.Position.Y - ROOT_ABOVE_FLOOR
		truthy(math.abs(ring.Position.Y - floorY) < 0.3, string.format("and it lies at the player's feet (ring y %.2f, floor %.2f)", ring.Position.Y, floorY))
		local c = ring.Color
		eq(string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)),
			string.format("%d,%d,%d", Hz.RingColor[1], Hz.RingColor[2], Hz.RingColor[3]), "and it is the one red in the game")
		local hit = false
		for _ = 1, 60 do
			frame(0.05)
			if knocked() then hit = true break end
		end
		truthy(hit, "CONTROL: a player who stays in the ring is hit (the knock)")
		local lift = hrp.AssemblyLinearVelocity.Y
		truthy(lift <= 15 + 1e-6, string.format("the knock lifts at %.1f studs/s, never a launch (cap 15)", lift))
		for _ = 1, 30 do frame(0.05) end
		eq(knocked(), false, "and the stumble ends")
	end
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

--============================================================================ 6b. on a roof, the ring lies on the roof
do
	waitIdle()
	local body = nil
	for _, lot in shelf.Lots:GetChildren() do
		local b = lot:FindFirstChild("Body")
		if b and (body == nil or b.Size.Y > body.Size.Y) then body = b end
	end
	truthy(body ~= nil, "set-up: a building to stand on")
	if body then
		local roofTop = body.Position.Y + body.Size.Y / 2
		local onRoof = Vector3.new(body.Position.X, roofTop + ROOT_ABOVE_FLOOR, body.Position.Z)
		local kind = nextLocked(onRoof)
		truthy(kind ~= nil, "set-up: a hazard locks onto a player on a roof (a roof is ground)")
		local ring = folder:FindFirstChild("HazardZone")
		if kind and ring then
			print(string.format("  a ring on a %.0f-stud roof: drawn at y %.2f", roofTop, ring.Position.Y))
			truthy(math.abs(ring.Position.Y - roofTop) < 0.3, string.format("the ring is drawn on the roof (y %.2f, roof %.2f), not on the ground below", ring.Position.Y, roofTop))
		end
		for _ = 1, 60 do frame(0.05) end
		waitIdle()
		place(home)
	end
end

--============================================================================ 7. never during the Grand Airship's arrival
do
	waitIdle()
	place(home)
	local before = probe:Invoke().hazardsSpawned
	buyTo(6400) -- the Skyport: the airship flies in for 12 s, the server moors it, then a 3 s hold
	local seenHold, spawnedInHold = false, 0
	for _ = 1, math.floor(20 / 0.05) do
		local s0 = probe:Invoke().hazardsSpawned
		frame(0.05)
		local pr = probe:Invoke()
		if pr.hold then
			seenHold = true
			spawnedInHold += pr.hazardsSpawned - s0
		end
	end
	truthy(seenHold, "set-up: the airship's hold was on")
	eq(spawnedInHold, 0, "no hazard launches while the Grand Airship arrives (the brag is never knocked)")
	eq(stateOf().airship, "moored", "set-up: the airship moored")
	eq(probe:Invoke().hold, false, "the hold ends 3 s after the mooring")
	truthy(waitForSpawn(15), "and the hazards resume")
end

--============================================================================ 8. a title card and a hazard never share the screen (REVIEW-1 F7)
-- On a landscape phone the title card sits below the HUD stack, over the lower middle of the screen: where the
-- avatar's feet and the red ring are (800 x 360: card y 216-249, centre 180). So a card holds a due hazard until it
-- has gone, and a card that arrives while a hazard is live waits until the hazard has passed.
local card = skyGui.Root:FindFirstChild("BandCard")
do
	waitIdle()
	place(home)
	-- (a) a hazard comes due while the player is in the air (held), then a band change puts a card up
	hum.FloorMaterial = Enum.Material.Air
	eq(spawnsDuring(12), 0, "set-up: in the air for 12 s, a hazard is due and held")
	buyTo(35000) -- Storm Front: its card
	truthy(card.Visible, "set-up: Storm Front's title card is up")
	hum.FloorMaterial = Enum.Material.Rock
	local both, spawned, cardGoneAt = 0, nil, nil
	for i = 1, math.floor(12 / 0.05) do
		frame(0.05)
		local pr = probe:Invoke()
		if card.Visible and pr.hazardActive then both += 1 end
		if not card.Visible and cardGoneAt == nil then cardGoneAt = i * 0.05 end
		if pr.hazardActive and spawned == nil then spawned = i * 0.05 end
	end
	print(string.format("  a hazard due under a card: the card went at %.2f s, the hazard came at %.2f s", cardGoneAt or -1, spawned or -1))
	eq(both, 0, "a due hazard waits while a title card is up (frames with both: " .. both .. ")")
	truthy(spawned ~= nil and cardGoneAt ~= nil and spawned >= cardGoneAt and spawned - cardGoneAt < 0.5,
		"...and comes as soon as the card has gone")
	waitIdle()
	-- (b) a band change while a hazard is live: its card waits for the hazard to pass
	truthy(waitForSpawn(15), "set-up: a hazard is live")
	buyTo(185000) -- Aurora Crown: its card
	both = 0
	local shownAt, endedAt = nil, nil
	for i = 1, math.floor(15 / 0.05) do
		frame(0.05)
		local pr = probe:Invoke()
		if card.Visible and pr.hazardActive then both += 1 end
		if not pr.hazardActive and endedAt == nil then endedAt = i * 0.05 end
		if card.Visible and shownAt == nil then shownAt = i * 0.05 end
	end
	print(string.format("  a card due during a hazard: the hazard passed at %.2f s, the card came at %.2f s", endedAt or -1, shownAt or -1))
	eq(both, 0, "a card that arrives during a hazard is not drawn over it (frames with both: " .. both .. ")")
	truthy(shownAt ~= nil and endedAt ~= nil and shownAt >= endedAt and shownAt - endedAt < 0.5,
		"...and shows as soon as the hazard has passed")
	truthy(string.find(card.Text, "AURORA", 1, true) ~= nil, "...and it is Aurora Crown's card: " .. card.Text)
end

print(string.format("  at most %d hazard model(s) at once; local parts peaked at %d, lights at %d", maxModels, maxParts, maxLights))
eq(maxModels <= 1, true, "never more than one hazard at a time")
truthy(maxParts <= Config.Budget.MaxLocalParts, "the local part budget holds with hazards in the air")
truthy(maxLights <= Config.Budget.MaxLights, "and the light budget")
do
	local kinds = {}
	for k in kindsSeen do table.insert(kinds, k) end
	table.sort(kinds)
	print("  hazard kinds met: " .. table.concat(kinds, ", "))
	local list = engineReport()
	for _, line in list do print("  engine: " .. line) end
	eq(#list, 0, "every hazard part shown has a size Roblox draws as written")
end

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero hazards: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero hazards check failed", 0) end
