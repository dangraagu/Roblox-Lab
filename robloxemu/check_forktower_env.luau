-- Fork Tower — the environment bands, hazards and rest, driven through the REAL client script.
-- Run: luau check_forktower_env.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- The pure modules (EnvBands, Hazards, Rest, Climb) are specced in fork-tower/tests, and the rarity
-- is measured there (Pacing.spec). This file checks the GLUE no unit test can see: that
-- src/client/Ambience.client.luau reads the player's floor from their own lane and turns it into the
-- band the HUD's floor number names, writes the blended values into Lighting and never hard-cuts
-- (not at a join, not across a seam, not on a rebirth from the night summit to the dungeon), keeps
-- inside the mobile budget at every band and every seam, runs hazards only while the player climbs a
-- section (never on a fork pad, where they read), knocks the character so the SERVER's fall rescue
-- returns it to its checkpoint with nothing lost, and that rest freezes hazards without resetting
-- their clock. It measures the budgets EYECANDY.md reports.
--
-- Headless limits: nothing renders and there is no physics. Frames are driven by firing
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

local h = Harness.new({ bundle = require("./build/fork-tower"), name = "fork-tower", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local Config = mod("Config")
local EnvBands = mod("EnvBands")
local Climb = mod("Climb")
local bands = Config.Env.Bands
local Hz = Config.Hazards
local Budget = Config.Budget
local FLOORS = Config.Tower.Floors
local Lighting = h.Lighting

-- Config.Env names what TowerArt builds. Ambience.client guards every lookup (a broken config costs the
-- polish, never the game), so a piece, critter, weather or hazard kind TowerArt does not know is
-- skipped SILENTLY: a typo in "planets" deletes the observatory's planets and nothing says so.
-- EnvConfig.spec cannot see it (TowerArt needs Roblox's Enum to load); this can.
do
	local TowerArt = mod("TowerArt")
	local models = TowerArt.hazardKinds()
	local unknown = {}
	for _, b in bands do
		for _, id in b.pieces or {} do
			if not TowerArt.hasPiece(id) then table.insert(unknown, b.id .. " piece " .. id) end
		end
		for _, a in b.ambient or {} do
			if not TowerArt.hasCritter(a.kind) then table.insert(unknown, b.id .. " critter " .. a.kind) end
		end
		if b.weather and not TowerArt.hasWeather(b.weather.kind) then table.insert(unknown, b.id .. " weather " .. b.weather.kind) end
		for _, k in b.hazards or {} do
			if not models[k] then table.insert(unknown, b.id .. " hazard " .. k) end
		end
	end
	eq(#unknown, 0, "every piece, critter, weather and hazard kind Config.Env names is one TowerArt can build ("
		.. table.concat(unknown, ", ") .. ")")
end

-- the server's lighting BEFORE any client runs (Fx.applyLighting(Fx.Presets.Fork))
local serverClock = Lighting.ClockTime
local serverAtmos = Lighting:FindFirstChild("FxAtmosphere")
local serverDensity = serverAtmos and serverAtmos.Density

-- every call into the server, counted, so the client's share can be shown to be zero
local remotes = RS:FindFirstChild("ForkRemotes")
local serverCalls, ourCalls = 0, 0
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
local remoteNames = {}
for _, r in remotes:GetChildren() do table.insert(remoteNames, r.Name) end
table.sort(remoteNames)

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("Climber", 5151)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0) -- climbing input: never idles into rest unless we say so

-- the world's own objects before the client exists (everything the server and the engine made)
local before = {}
for _, d in h.workspace:GetDescendants() do before[d] = true end

local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local okAmb, errAmb = h:tryRun("client/Ambience.client")
truthy(okAmb, "Ambience.client loads (" .. tostring(errAmb) .. ")")

local folder = h.workspace:FindFirstChild("ForkLocalEnv")
truthy(folder ~= nil, "the client made its local folder")
local hudRoot = plr.PlayerGui:FindFirstChild("ForkHud"):FindFirstChild("Root")
local row = hudRoot:FindFirstChild("AmbienceRow")
truthy(row ~= nil, "the HUD reserves the ambience row")
local chip = row and row:FindFirstChild("ChipSlot") and row.ChipSlot:FindFirstChild("BandChip")
local restBtn = row and row:FindFirstChild("RestSlot") and row.RestSlot:FindFirstChild("RestButton")
local card = row and row:FindFirstChild("BandCard", true) -- in the HUD's card slot (under the row)
truthy(chip ~= nil and restBtn ~= nil and card ~= nil, "the chip, the rest button and the title card sit in the HUD's slots")

local cam = h.workspace.CurrentCamera
local towers = h.workspace:FindFirstChild("Towers")
local function laneOf()
	for _, f in towers:GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then return f end
	end
	return nil
end
local lane = laneOf()
truthy(lane ~= nil, "the player has a lane")

--======================================================================= the frame driver

local simTime = 0
local announced = {} -- every distinct title card text, in order
local lastCard = ""
local lastT = {} -- part -> transparency last frame (the no-hard-cut watch)
local cutViolations, cutExample = 0, nil
local popIns, popExample = 0, nil
local watchCuts = true
local camOffset = Vector3.new(0, 9, -22)
local function isTransient(p)
	local n = p.Name
	-- a hazard with its warning lane and ring, a lightning bolt, the weather host: meant to appear at once
	return string.sub(n, 1, 7) == "Hazard_" or n == "HazardLane" or n == "HazardZone" or n == "Bolt" or n == "WeatherHost"
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
	local lantern = hrp:FindFirstChild("ForkLantern")
	if lantern and lantern.Brightness > 0 then lights += 1 end
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
local measureWhere = "join"
-- A frame in which the CAMERA itself jumps more than 8 studs is a teleport, a camera cut: nothing in
-- real play moves it that far in 1/30 s (a full-speed fall to the rescue line is ~5.5 studs a frame);
-- only a teleport does (the door choice onto the section, the server's fall rescue, a rebirth, a join,
-- and this file's standOn). The wall grid then re-places the rows it left at once, and a row whose fade
-- still lags the jump vanishes in that frame. Measured 2026-09-24 over what follows the first rebirth:
-- 124-134 wall parts on the simulated knock-and-fall (90 studs down and back) and up to 60 more on this
-- file's BACKWARD teleports (back to platform 2 after a knock), each at the far edge of the grid
-- (EYECANDY.md §13). The first run, whose teleports only go forward as climbing does, has none, and its
-- watch keeps no exemption. From the first rebirth on, teleport frames are left out of the no-cut rule
-- (never out of the pop-in rule), counted, and required to be a tiny share of the frames watched.
local exemptCameraCuts = false
local cameraCutFrames, watchedFrames = 0, 0
local lastCamPos = nil
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + camOffset, hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt
	if card and card.Visible and card.Text ~= lastCard then
		lastCard = card.Text
		table.insert(announced, card.Text)
	end
	local camPos = cam.CFrame.Position
	local cameraCut = lastCamPos ~= nil and (camPos - lastCamPos).Magnitude > 8
	lastCamPos = camPos
	if exemptCameraCuts and watchCuts then
		watchedFrames += 1
		if cameraCut then cameraCutFrames += 1 end
	end
	-- never a hard cut: a part that stays in the scene changes transparency gradually, and a part
	-- that enters the scene enters invisible (it fades in). Hazards, bolts and the weather host are
	-- meant to appear at once (a hazard with its warning, a flash).
	local now = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and not isTransient(d) then
			local t = d.Transparency
			now[d] = t
			if watchCuts then
				local prev = lastT[d]
				if prev == nil then
					if t < 0.9 then
						popIns += 1
						popExample = popExample or (d.Name .. string.format(" entered at %.2f", t))
					end
				elseif math.abs(t - prev) > 0.1 and not (t >= 0.9 and prev >= 0.9)
					and not (cameraCut and exemptCameraCuts) then
					cutViolations += 1
					cutExample = cutExample or (d.Name .. string.format(" %.2f -> %.2f", prev, t))
				end
			end
		end
	end
	lastT = now
	measure(measureWhere)
end
local function run(seconds, each)
	local n = math.floor(seconds * 30 + 0.5)
	for i = 1, n do
		frame(1 / 30)
		if each and each(i) == false then return end
	end
end

--======================================================================= lane helpers

local function forkOf(level) return lane:FindFirstChild("Fork_" .. level) end
local function padOf(level)
	local f = forkOf(level)
	return f and f:FindFirstChild("ForkPad_" .. level)
end
local function doorOf(level, slot)
	local f = forkOf(level)
	return f and f:FindFirstChild("Door_" .. level .. "_" .. slot)
end
local function standOn(part, lift)
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + (lift or 3), 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
end
local function platformsOf(level)
	local sec = lane:FindFirstChild("Section_" .. level)
	local list = {}
	if sec == nil then return list end
	for _, c in sec:GetChildren() do
		local i = tonumber(string.match(c.Name, "^Plat_%d+_(%d+)$"))
		if i then list[i] = c end
	end
	return list
end
local function exitOf(level)
	local sec = lane:FindFirstChild("Section_" .. level)
	if sec == nil then return nil end
	for _, c in sec:GetChildren() do
		if c:GetAttribute("Exit") == true then return c end
	end
	return nil
end
-- the honest read: begin the hold, hold ReadSeconds, release; then the door the inscription says is safe
local function readSafe(level)
	local pad = padOf(level)
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	prompt.PromptButtonHoldBegan:Fire(plr)
	run(Config.Fork.ReadSeconds + 0.02)
	prompt.Triggered:Fire(plr)
	run(0.2)
	local m1 = doorOf(level, 1):GetAttribute("Marked") == true
	local inv = pad:GetAttribute("RuleInverted") == true
	local marked = if m1 then 1 else 2
	local trap = if inv then 3 - marked else marked
	return 3 - trap
end
local function choose(level, slot)
	doorOf(level, slot):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	run(0.3)
end
local function reachExit(level)
	local exit = exitOf(level)
	standOn(exit)
	exit.Touched:Fire(hrp)
	run(0.3)
end
local function bandAtFloor(n) return bands[EnvBands.indexAt(bands, n - 1)] end
-- The floor clears the moment the player lands on the exit: the server builds the next fork (or the
-- summit) at once, and from then on that fork's LES prompt can be in reach (review 2026-09-24: it
-- reaches 16 studs and the pad sits 2 studs past the exit, so the exit's front 3.5 studs are in reach
-- and OFF the pad). So the ambience must see the cleared floor in the first frame after the new fork
-- exists, not at its next 4 Hz lane scan: that is the frame a hazard still in flight is dismissed
-- (Climb.gate) and the chip moves on. The chip is what is observable here, and it changes at every
-- floor clear (the count to the next band drops, or the band changes). Frames are counted from the
-- first frame at whose end the new fork exists.
local floorClearLag = {}
local function reachExitWatched(level)
	local exit = exitOf(level)
	standOn(exit)
	local before = chip.Text
	exit.Touched:Fire(hrp)
	local builtAt, movedAt = nil, nil
	for i = 1, 9 do -- 0.3 s, as reachExit
		frame(1 / 30)
		if builtAt == nil and (forkOf(level + 1) ~= nil or lane:FindFirstChild("Summit") ~= nil) then builtAt = i end
		if movedAt == nil and chip.Text ~= before then movedAt = i end
	end
	table.insert(floorClearLag, if builtAt and movedAt then movedAt - builtAt else 99)
end

--======================================================================= 1. the takeover glides

do
	frame(1 / 30)
	local c = Lighting.ClockTime
	local arc = math.abs(Climb.nearestClock(c, serverClock) - serverClock)
	truthy(arc <= 0.6, string.format("the first client frame moves ClockTime at most 0.6 h from the server's %.2f (moved %.2f): a join glides", serverClock, arc))
	near(Lighting:FindFirstChild("FxAtmosphere").Density, serverDensity, 0.05, "and the atmosphere barely moves on the first frame")
	eq(Lighting:FindFirstChild("FxAtmosphere"), serverAtmos, "the client reused the server's Atmosphere instead of stacking a second one")
	local daytime = 0
	run(4, function()
		local ct = Lighting.ClockTime
		if ct > 6 and ct < 17.5 then daytime += 1 end
	end)
	eq(daytime, 0, "the join glide from the server's dusk to the dungeon's night goes forward through the evening, never back through the day")
end

--======================================================================= 2. a whole run, floor by floor

-- critters in range of the camera (visible, within 130 studs): the parts of every pooled critter kind
local CRITTER_PARTS = { WingL = true, WingR = true, Firefly = true, Leaf = true, ShootingStar = true }
local function lifeNearCamera(): number
	local n = 0
	local cp = cam.CFrame.Position
	for _, d in folder:GetChildren() do
		if d:IsA("BasePart") and CRITTER_PARTS[d.Name] and d.Transparency < 0.5 then
			local range = if d.Name == "ShootingStar" then 600 else 130
			if (d.Position - cp).Magnitude <= range then
				n += if d.Name == "WingL" or d.Name == "WingR" then 0.5 else 1
			end
		end
	end
	return math.floor(n)
end

local bandTable = {} -- band id -> { parts, emitters, rate } at mid-section
local floorPeak = {}
local slotsChosen = {}
for level = 1, FLOORS do
	local pad = padOf(level)
	standOn(pad)
	measureWhere = "fork " .. level
	run(6)
	local b = bandAtFloor(level)
	local where = string.format("fork %d (%s)", level, b.id)
	truthy(string.find(chip.Text, b.name, 1, true) ~= nil, where .. ": the chip names the floor's band (" .. chip.Text .. ")")
	-- at a fork, progress is exactly floor - 1: the lighting sits at that band sample
	local target = EnvBands.sample(bands, level - 1, "lighting")
	near(Lighting.ClockTime, target.ClockTime, 0.05, where .. ": ClockTime settled on the band's value")
	near(Lighting.Brightness, target.Brightness, 0.02, where .. ": Brightness settled")
	near(Lighting:FindFirstChild("FxAtmosphere").Density, EnvBands.sample(bands, level - 1, "atmosphere").Density, 0.01, where .. ": atmosphere density settled")
	local sky = Lighting:FindFirstChild("ForkSky")
	near(sky and sky.StarCount, EnvBands.sample(bands, level - 1, "sky").StarCount, 1, where .. ": StarCount settled")
	-- the chip counts floors to the next band
	local nextIdx, remaining = EnvBands.nextBand(bands, level - 1)
	if nextIdx then
		local n = math.ceil(remaining)
		truthy(string.find(chip.Text, bands[nextIdx].emoji .. " om " .. n, 1, true) ~= nil,
			where .. ": the chip says the next band is " .. n .. " floor(s) away (" .. chip.Text .. ")")
	end
	-- life: the band's critters are out around the camera (pooled, recycled, never all gone)
	do
		local wanted = 0
		for _, a in b.ambient do wanted += a.count end
		-- over two seconds, not one frame: shooting stars cross the sky in a few seconds and fade in
		-- when they respawn, so a single frame can catch one between lives
		local best = 0
		run(2, function() best = math.max(best, lifeNearCamera()) end)
		truthy(best >= math.min(3, wanted), where .. ": the band's life is out around the camera (" .. best .. " critters in range)")
	end
	-- the climber's lantern: lit in the dark bands (the dungeon, the storm, the night), off in daylight
	do
		local lantern = hrp:FindFirstChild("ForkLantern")
		local ct = b.lighting.ClockTime
		local dark = ct >= 18.5 or ct <= 5
		if dark then
			truthy(lantern ~= nil and lantern.Brightness >= 1, where .. ": the lantern is lit in the dark (" .. tostring(lantern and lantern.Brightness) .. ")")
		else
			truthy(lantern ~= nil and lantern.Brightness <= 0.05, where .. ": the lantern is off in daylight (" .. tostring(lantern and lantern.Brightness) .. ")")
		end
	end
	-- nothing flies at a fork: no hazard model, no warning
	local hz = 0
	for _, d in folder:GetChildren() do if string.sub(d.Name, 1, 7) == "Hazard_" then hz += 1 end end
	eq(hz, 0, where .. ": no hazard in the scene at a fork")
	truthy(string.find(chip.Text, "⚠️", 1, true) == nil, where .. ": no warning on the chip")

	local safe = readSafe(level)
	slotsChosen[level] = safe
	choose(level, safe)
	local plats = platformsOf(level)
	truthy(#plats >= 5, where .. ": the section was built (" .. #plats .. " platforms)")
	local mid = math.max(1, math.floor(#plats / 2))
	for i = 1, #plats do
		standOn(plats[i])
		measureWhere = string.format("floor %d climb", level)
		run(1)
		if i == mid then
			local m = measure(where)
			bandTable[#bandTable + 1] = string.format("%-26s parts %3d  emitters %d (%2d/s)  beams %d  trails %d  lights %d",
				string.format("floor %d (%s) mid-climb", level, b.id), m.parts, m.emitters, m.rate, m.beams, m.trails, m.lights)
		end
	end
	reachExitWatched(level)
end
do
	local worst = 0
	for _, lag in floorClearLag do worst = math.max(worst, lag) end
	eq(#floorClearLag, FLOORS, "set-up: every floor of the run was cleared through the exit")
	truthy(worst <= 1, "at every floor clear the ambience saw the new floor within one frame of the next fork existing, not at its next lane scan (lags in frames: "
		.. table.concat(floorClearLag, ",") .. ")")
end

-- the summit
local summitPad = lane:FindFirstChild("Summit") and lane.Summit:FindFirstChild("SummitPad")
truthy(summitPad ~= nil, "the summit was built")
standOn(summitPad)
measureWhere = "summit"
run(8)
do
	local b = bands[#bands]
	truthy(string.find(chip.Text, b.name, 1, true) ~= nil, "summit: the chip names " .. b.name .. " (" .. chip.Text .. ")")
	near(Lighting.ClockTime, b.lighting.ClockTime, 0.05, "summit: the crown's night")
	local sky = Lighting:FindFirstChild("ForkSky")
	near(sky and sky.StarCount, b.sky.StarCount, 1, "summit: every star out")
	-- the crown of stars circles the climber, not the camera
	local stars, farthest = 0, 0
	for _, d in folder:GetChildren() do
		if d.Name == "CrownStar" and d.Transparency < 0.2 then
			stars += 1
			farthest = math.max(farthest, (d.Position - hrp.Position).Magnitude)
		end
	end
	eq(stars, 10, "summit: ten crown stars are out")
	truthy(farthest <= 6, string.format("summit: the crown circles the climber (every star within 6 studs of the root; farthest %.1f)", farthest))
	local reveal = hudRoot:FindFirstChild("Reveal")
	truthy(reveal ~= nil and reveal.Visible, "summit: the HUD's Build Reveal card is up")
	truthy(not (reveal.Visible and card.Visible), "summit: a band card never sits on top of the Build Reveal card")
	local m = measure("summit")
	bandTable[#bandTable + 1] = string.format("%-26s parts %3d  emitters %d (%2d/s)  beams %d  trails %d  lights %d",
		"summit (crown)", m.parts, m.emitters, m.rate, m.beams, m.trails, m.lights)
end
-- every band was announced, once, in order
do
	local order = {}
	for _, t in announced do
		for bi, b in bands do
			if string.find(t, string.upper(b.name), 1, true) then order[#order + 1] = bi end
		end
	end
	local ok = #order >= #bands - 1
	for i = 2, #order do if order[i] <= order[i - 1] then ok = false end end
	truthy(ok, "each band's title card played once, in climbing order (" .. table.concat(order, ",") .. ")")
	local sawAll = true
	for bi = 1, #bands - 1 do
		local seen = false
		for _, v in order do if v == bi then seen = true end end
		if not seen then sawAll = false end
	end
	truthy(sawAll, "every band below the summit got its title card")
end

--======================================================================= 3. the rebirth glides through midnight

do
	local rebirthEv = remotes:FindFirstChild("Rebirth")
	local maxStep, daytime, lastClock = 0, 0, Lighting.ClockTime
	ourCalls += 1
	rebirthEv:simulateFireServer(plr)
	h:advance(0.2)
	lane = laneOf()
	measureWhere = "rebirth glide"
	run(8, function()
		local c = Lighting.ClockTime
		local step = math.abs(Climb.nearestClock(c, lastClock) - lastClock)
		if step > maxStep then maxStep = step end
		lastClock = c
		if c > 6 and c < 17.5 then daytime += 1 end
	end)
	eq(daytime, 0, "rebirth: the clock glides from the summit's night to the dungeon through midnight, never through the day")
	truthy(maxStep <= 0.12, string.format("rebirth: no frame moves the clock more than 0.12 h (max %.3f)", maxStep))
	truthy(string.find(chip.Text, bands[1].name, 1, true) ~= nil, "rebirth: back in " .. bands[1].name .. " (" .. chip.Text .. ")")
	-- the Build Reveal card was still open: the dungeon's card waits for it, then plays
	local reveal = hudRoot:FindFirstChild("Reveal")
	truthy(reveal.Visible and not card.Visible, "rebirth with the Build Reveal card open: the band card waits behind it")
	reveal:FindFirstChild("CardClose").Activated:Fire()
	run(0.5)
	truthy(string.find(announced[#announced] or "", string.upper(bands[1].name), 1, true) ~= nil,
		"rebirth: once the card is closed, the run's title cards start again (" .. tostring(announced[#announced]) .. ")")
end
eq(cutViolations, 0, "no scenery part ever changed transparency by more than 0.1 in one 1/30 s frame (a glide, never a cut)"
	.. (if cutExample then "; e.g. " .. cutExample else ""))
eq(popIns, 0, "every scenery part entered the scene invisible and faded in" .. (if popExample then "; e.g. " .. popExample else ""))
-- the watch stays on for the rest of the file (the second run: bands seen again, hazards, a knock and
-- a fall, rest, a third run) and is asserted again at the end of part 6, with camera cuts exempt from
-- the no-cut rule (not from the pop-in rule)
cutViolations, cutExample, popIns, popExample = 0, nil, 0, nil
exemptCameraCuts = true

-- TowerArt's own rule, which the integrated run cannot reach: Ambience smooths every band weight, so a
-- piece is always nearly transparent when it is hidden. But TowerArt hides by UNPARENTING and a part
-- keeps its Transparency while it is out of the scene, so a piece hidden while visible (a weight that
-- drops at once) and shown again at a small weight would come back at its old opacity: +1 Jump's SkyArt
-- does exactly that (EYECANDY.md §12). TowerArt writes Transparency = 1 on hide. Held here directly.
do
	local TowerArt = mod("TowerArt")
	local scratch = h.instance.Instance.new("Folder")
	scratch.Name = "TowerArtProbe"
	local r = 0
	local art = TowerArt.new(scratch, function() r = (r * 7 + 3) % 11; return r / 11 end, Config, EnvBands)
	local camAt = Vector3.new(0, 200, 0)
	art:updatePiece("farBlooms", 1, camAt, 1, 0, camAt)
	local shown = 0
	for _, p in scratch:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 0.5 then shown += 1 end
	end
	art:updatePiece("farBlooms", 0, camAt, 2, 0, camAt) -- hidden at once, from fully shown
	art:updatePiece("farBlooms", 0.015, camAt, 3, 0, camAt) -- and shown again, barely
	local worst = 0
	for _, p in scratch:GetChildren() do
		if p:IsA("BasePart") then worst = math.max(worst, 1 - p.Transparency) end
	end
	truthy(shown >= 6, "TowerArt probe: the far blooms were drawn (" .. shown .. " parts visible at weight 1)")
	truthy(worst <= 0.05, string.format("a piece hidden while visible comes back invisible when shown again at a small weight (most opaque part %.2f)", worst))
	-- The weather budget is enforced IN TowerArt (EnvBands.capRates), not left to the config: in this game
	-- at most two bands overlap, so the run above never asks for more than two kinds or 40/s, and a
	-- TowerArt that ignored the cap would pass it. Asked for all five kinds at full rate at once, it must
	-- still switch on at most MaxWeatherEmitters and stay under MaxEmitterRate.
	art:updateWeather({ embers = 6, pollen = 8, sparks = 10, rain = 40, stardust = 10 }, camAt)
	local on, rate = 0, 0
	for _, d in scratch:GetDescendants() do
		if d.ClassName == "ParticleEmitter" and d.Enabled then
			on += 1
			rate += d.Rate
		end
	end
	truthy(on >= 1 and on <= Budget.MaxWeatherEmitters, string.format("TowerArt switches on at most %d weather emitters however many are asked for (%d on)", Budget.MaxWeatherEmitters, on))
	truthy(rate <= Budget.MaxEmitterRate + 0.5, string.format("and keeps their summed rate within %d/s (%.1f)", Budget.MaxEmitterRate, rate))
	scratch:Destroy()
end

--======================================================================= 4. a band you are not in costs nothing

-- a band the player is not in costs nothing: in the dungeon again, no other band's pieces are parented
do
	local foreign = 0
	for _, d in folder:GetChildren() do
		local n = d.Name
		if n == "Foliage" or n == "Bloom" or n == "Gear" or n == "Teeth" or n == "StormPuff" or n == "Lantern"
			or n == "GalaxyCore" or n == "CrownStar" or n == "RingedPlanet" or n == "ClockDial" or n == "StormDeckPuff" then
			foreign += 1
		end
	end
	eq(foreign, 0, "back in the dungeon, no other band's scenery is parented (it costs no draw calls)")
end

--======================================================================= 5. hazards: only while climbing

Hz.IntervalMin, Hz.IntervalMax = 8, 9 -- in memory, this run only: many hazards in a short check
measureWhere = "hazards (8-9 s interval)"
local function hazardModel()
	local kind, sum, n = nil, Vector3.zero, 0
	for _, c in folder:GetChildren() do
		local k = string.match(c.Name, "^Hazard_([%a]+)_")
		if k and c:IsA("BasePart") then
			kind = k
			sum += c.Position
			n += 1
		end
	end
	if n == 0 then return nil, nil end
	return sum / n, kind
end
local function ringOf()
	return folder:FindFirstChild("HazardZone")
end
-- play floors 1..2 of the new run (the dungeon: no hazards, however long it takes)
--
-- 14 s on each dungeon platform, 140 s of climbing in all, and not for the look of it. The hazard
-- clock carries over from the first run (it is never reset), and the first run climbs ~72.5 s of
-- sections against a first interval rolled at 70-110 s: about one run in sixteen, a hazard came due
-- INSIDE the first run and the next was rolled 70-110 s further on, so the garden below waited for it
-- and "a hazard launched within IntervalMax + 1 s" failed (measured 2026-09-24: 1 of 16 runs on an
-- unchanged tree, and 3 of 3 with the first roll forced to 60 s; 0 of 3 with this fix). A hazard that comes due in a QUIET
-- band is re-rolled on the current (8-9 s) interval, so 140 s here outlasts any interval still pending
-- from the first run (at most ~72.5 + 110 = 182.5 on the clock) and the garden always starts fresh.
do
	local launches = 0
	for level = 1, 2 do
		standOn(padOf(level))
		run(20, function() if hazardModel() then launches += 1 end end)
		choose(level, readSafe(level))
		for _, p in platformsOf(level) do
			standOn(p)
			run(14, function() if hazardModel() then launches += 1 end end)
		end
		reachExit(level)
	end
	eq(launches, 0, "the dungeon (floors 1-2) is hazard-free, even with hazards due every 8-9 s (140 s of climbing)")
end
-- floor 3: 40 s on the unread fork pad: the sanctuary (and 40 s in which the garden's life has to
-- keep coming back around a player who does not move: pooled critters recycle)
do
	standOn(padOf(3))
	local lowest = math.huge
	local seen, warned = 0, 0
	run(40, function(i)
		if hazardModel() then seen += 1 end
		if string.find(chip.Text, "⚠️", 1, true) then warned += 1 end
		if i > 150 then lowest = math.min(lowest, lifeNearCamera()) end
	end)
	truthy(lowest >= 3, "40 s standing in the garden: the butterflies and fireflies kept coming back (never fewer than 3 in range; lowest " .. lowest .. ")")
	eq(seen, 0, "40 s on a fork pad with hazards due every 8-9 s: nothing launched (the pad is a sanctuary)")
	eq(warned, 0, "and the chip never warned")
end
local gardenKinds = {}
for _, k in bands[EnvBands.indexOf(bands, "garden")].hazards do gardenKinds[k] = true end
local gardenPlats
do
	choose(3, readSafe(3))
	gardenPlats = platformsOf(3)
	standOn(gardenPlats[2])
	local firstAt = nil
	run(14, function(i)
		local _, kind = hazardModel()
		if kind and firstAt == nil then
			firstAt = i / 30
			truthy(gardenKinds[kind] == true, "the first hazard in the garden is a garden kind (" .. tostring(kind) .. ")")
			return false
		end
	end)
	truthy(firstAt ~= nil and firstAt <= Hz.IntervalMax + 1,
		string.format("climbing the garden, a hazard launched within IntervalMax + 1 s (%s s)", tostring(firstAt)))
	-- the warning, then the lock
	local sawIncoming, sawLock = false, false
	run(6, function()
		if string.find(chip.Text, "KOMMER", 1, true) then sawIncoming = true end
		if string.find(chip.Text, "FLYTT DEG", 1, true) then sawLock = true end
		if hum.PlatformStand then return false end
	end)
	truthy(sawIncoming, "the chip warned '… KOMMER' while the hazard tracked the player")
	truthy(sawLock, "and '⚠️ FLYTT DEG!' once its lane locked")
end
-- the knock: standing still in the ring gets you knocked off; the SERVER's rescue brings you back
do
	local hit = hum.PlatformStand
	if not hit then
		run(10, function() if hum.PlatformStand then return false end end)
		hit = hum.PlatformStand
	end
	truthy(hit, "standing still in the red ring, the player was knocked (PlatformStand)")
	local v = hrp.AssemblyLinearVelocity
	truthy(Vector3.new(v.X, 0, v.Z).Magnitude >= 20, string.format("the knock pushes sideways at >= 20 studs/s (%.1f)", Vector3.new(v.X, 0, v.Z).Magnitude))
	truthy(v.Y <= 15, string.format("the knock's lift is capped (%.1f <= 15)", v.Y))
	local floorBefore = plr.leaderstats.Floor.Value
	-- the fall, simulated: below the server's rescue line
	hrp.CFrame = CFrame.new(hrp.Position.X + 10, hrp.Position.Y - Config.World.FallGrace - 20, hrp.Position.Z)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hum.FloorMaterial = Enum.Material.Air
	run(0.6)
	hum.FloorMaterial = Enum.Material.Plastic
	local best = math.huge
	for _, p in gardenPlats do
		local top = p.Position + Vector3.new(0, p.Size.Y / 2, 0)
		best = math.min(best, (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(top.X, 0, top.Z)).Magnitude)
	end
	truthy(best <= Config.Tower.TileSize / 2 + 1, string.format("the server's fall rescue put the player back on a platform of their section (%.1f studs off a centre)", best))
	eq(plr.leaderstats.Floor.Value, floorBefore, "a knock costs no floor")
	run(1)
	truthy(not hum.PlatformStand, "the knock wore off (PlatformStand released)")
end
-- the dodge: walk out of the ring when it locks, and nothing happens
do
	standOn(gardenPlats[3])
	local dodged, knocked, launched = false, false, false
	run(30, function()
		if hazardModel() then launched = true end
		local ring = ringOf()
		if not dodged and string.find(chip.Text, "FLYTT DEG", 1, true) and ring and ring.Parent then
			-- step out of the ring, sideways, as far as its radius and a stud more
			local r = ring.Size.Y / 2
			hrp.CFrame = hrp.CFrame + Vector3.new(r + 1, 0, 0)
			dodged = true
		end
		if hum.PlatformStand then knocked = true end
		if dodged and hazardModel() == nil then return false end
	end)
	truthy(launched and dodged, "a hazard came and the player walked out of its red ring when it locked")
	truthy(not knocked, "walking out of the ring dodges it: no knock")
end
-- a hazard in flight when the player steps onto a fork pad fizzles out, even while they are still
-- climbing: their own, answered fork's pad lies under the section and a fall can land on it
do
	standOn(gardenPlats[2])
	local launched = false
	run(12, function()
		if hazardModel() then launched = true; return false end
	end)
	truthy(launched, "a hazard launched at the player climbing the garden")
	standOn(padOf(3))
	frame(1 / 30)
	frame(1 / 30)
	truthy(exitOf(3) ~= nil and forkOf(4) == nil, "set-up: the player is still climbing floor 3 (its section exists, fork 4 does not)")
	eq(hazardModel(), nil, "stepping onto a fork pad while climbing, the hazard in flight was dismissed at once")
end
-- The floor is cleared with a hazard in flight, and the player reads from the EXIT's edge (review
-- 2026-09-24, low): the next fork's LES prompt reaches 16 studs and its pad sits 2 studs past the exit,
-- so the front 3.5 studs of every exit platform are in reach of the prompt and off the pad. A hazard
-- launched in the last seconds of the climb knocked a player there 0.97 s into the 1.1 s hold,
-- measured through this client: a fall, the rescue, and the read to pay again, which only readers pay.
-- Clearing the floor ends the climb and what it launched: the hazard is gone in the first frame after
-- fork 4 exists, and a read begun on the exit's edge is the read's own price and nothing more.
do
	local exit = exitOf(3)
	standOn(exit)
	local launched = false
	run(12, function()
		if hazardModel() then launched = true; return false end
	end)
	truthy(launched, "a hazard launched at the player on the section's exit")
	exit.Touched:Fire(hrp) -- the server clears floor 3 and builds fork 4
	local builtAt, goneAt = nil, nil
	for i = 1, 9 do
		frame(1 / 30)
		if builtAt == nil and forkOf(4) ~= nil then builtAt = i end
		if goneAt == nil and hazardModel() == nil then goneAt = i end
	end
	local pad4 = padOf(4)
	truthy(pad4 ~= nil, "fork 4 was built")
	truthy(builtAt ~= nil and goneAt ~= nil and goneAt <= builtAt + 1, string.format(
		"the floor cleared: the hazard in flight was dismissed within a frame of fork 4 existing, off any pad (built at frame %s, gone at %s)",
		tostring(builtAt), tostring(goneAt)))
	-- the reviewer's spot: the exit's front edge, toward the pad
	local d = pad4.Position - exit.Position
	d = Vector3.new(d.X, 0, d.Z)
	hrp.CFrame = CFrame.new(exit.Position + d.Unit * (exit.Size.Z / 2 - 0.6) + Vector3.new(0, exit.Size.Y / 2 + 3, 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
	local prompt = pad4:FindFirstChildOfClass("ProximityPrompt")
	local padTop = { x = pad4.Position.X, y = pad4.Position.Y + pad4.Size.Y / 2, z = pad4.Position.Z, sx = pad4.Size.X, sz = pad4.Size.Z }
	local rootAt = { x = hrp.Position.X, y = hrp.Position.Y, z = hrp.Position.Z }
	truthy((hrp.Position - pad4.Position).Magnitude <= prompt.MaxActivationDistance
		and not Climb.inSanctuary(rootAt, { padTop }, Config.Env.Sanctuary.Radius, Config.Env.Sanctuary.Ceiling),
		string.format("set-up: the exit's front edge is in the LES prompt's reach (%.1f <= %s studs) and off the pad",
			(hrp.Position - pad4.Position).Magnitude, tostring(prompt.MaxActivationDistance)))
	local knocked, flying = false, false
	local t0 = h.scheduler:now()
	prompt.PromptButtonHoldBegan:Fire(plr)
	run(Config.Fork.ReadSeconds + 0.02, function()
		if hum.PlatformStand then knocked = true end
		if hazardModel() then flying = true end
	end)
	prompt.Triggered:Fire(plr)
	run(0.1)
	truthy(not knocked and not flying, "a read begun on the exit's edge: nothing flew and nothing knocked the reader during the hold")
	eq(forkOf(4):GetAttribute("Read"), true, "the read completed")
	near(h.scheduler:now() - t0, Config.Fork.ReadSeconds + 0.12, 0.05, "in the read's own time on the server clock (nothing added)")
	standOn(pad4)
	run(0.1)
end
-- the kinds each band flies are that band's kinds
local offPadLaunches = 0
do
	local wrongKinds, sampled = {}, {}
	for level = 4, FLOORS do
		if level > 4 then
			standOn(padOf(level))
			run(0.5)
			choose(level, readSafe(level))
		else
			choose(level, readSafe(level))
		end
		local b = bandAtFloor(level)
		local allowed = {}
		for _, k in b.hazards do allowed[k] = true end
		local plats = platformsOf(level)
		standOn(plats[2])
		local wasShown = false
		run(22, function()
			local _, kind = hazardModel()
			if kind and not wasShown then
				sampled[b.id] = (sampled[b.id] or 0) + 1
				if not allowed[kind] then table.insert(wrongKinds, b.id .. ":" .. kind) end
			end
			wasShown = kind ~= nil
			hrp.AssemblyLinearVelocity = Vector3.zero
			if hum.PlatformStand then
				standOn(plats[2]) -- a knock: put the climber back (the rescue is tested above)
			end
		end)
		reachExit(level)
		-- the floor is cleared and the next fork is not yet answered: still standing on the exit
		-- platform (off the new pad), nothing new launches, because nobody is climbing a section
		local fresh, had = 0, hazardModel() ~= nil
		run(12, function()
			local now = hazardModel() ~= nil
			if now and not had then fresh += 1 end
			had = now
			if hum.PlatformStand then standOn(exitOf(level)) end
		end)
		if fresh > 0 then offPadLaunches += fresh end
	end
	eq(offPadLaunches, 0, "after clearing a floor, 12 s on the exit platform (off the pad, next fork unanswered): no new hazard")
	eq(#wrongKinds, 0, "every hazard flown on floors 4-10 was one of its band's kinds (" .. table.concat(wrongKinds, ", ") .. ")")
	for _, id in { "garden", "clockwork", "storm", "observatory" } do
		if id ~= "garden" then
			truthy((sampled[id] or 0) >= 1, id .. ": hazards flew there (" .. tostring(sampled[id]) .. ")")
		end
	end
end
-- the summit: a sanctuary
do
	local pad = lane:FindFirstChild("Summit") and lane.Summit:FindFirstChild("SummitPad")
	standOn(pad)
	local seen = 0
	run(30, function() if hazardModel() then seen += 1 end end)
	eq(seen, 0, "30 s on the summit with hazards due every 8-9 s: nothing launched")
end

--======================================================================= 6. rest

-- a fresh run, up to the garden, to rest where hazards fly
ourCalls += 1
remotes:FindFirstChild("Rebirth"):simulateFireServer(plr)
h:advance(0.5)
lane = laneOf()
for level = 1, 2 do
	standOn(padOf(level))
	run(0.3)
	choose(level, readSafe(level))
	reachExit(level)
end
standOn(padOf(3))
run(0.3)
choose(3, readSafe(3))
local restPlats = platformsOf(3)
do
	standOn(restPlats[2])
	run(0.5)
	-- rest with a clear sky: sit, soften, pause
	local wasThreat = hazardModel() ~= nil
	if wasThreat then run(12, function() if hazardModel() == nil then return false end end) end
	hum.MoveDirection = Vector3.zero
	restBtn.Activated:Fire()
	run(0.2)
	eq(hum.Sit, true, "the Rest button sits the player down")
	truthy(string.find(chip.Text, "Hviler", 1, true) ~= nil, "the chip says they are resting (" .. chip.Text .. ")")
	eq(restBtn.Text, "▶ Klatre", "the button offers to climb on")
	local dof = Lighting:FindFirstChild("ForkRestFocus")
	truthy(dof ~= nil and dof.Enabled, "the view softens (depth of field)")
	local seen = 0
	run(40, function() if hazardModel() then seen += 1 end end)
	eq(seen, 0, "40 s resting with hazards due every 8-9 s: nothing launched (the clock is frozen)")
	-- any movement wakes, and the clock carries on from where it stopped (never reset, never rushed)
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.5)
	eq(hum.Sit, false, "moving wakes the player (they are stood up)")
	local firstAt = nil
	run(Hz.IntervalMax + 2, function(i)
		if hazardModel() and firstAt == nil then firstAt = i / 30; return false end
	end)
	truthy(firstAt ~= nil and firstAt <= Hz.IntervalMax + 1,
		string.format("after waking, the next hazard came within one interval of climbing (%s s): rest froze the clock, it did not reset it", tostring(firstAt)))
end
-- rest requested under a threat is queued, never a panic button
do
	if hazardModel() == nil then
		run(Hz.IntervalMax + 2, function() if hazardModel() then return false end end)
	end
	truthy(hazardModel() ~= nil, "a hazard is on its way")
	restBtn.Activated:Fire()
	run(0.1)
	truthy(not hum.Sit, "rest under a threat does not sit the player down")
	eq(restBtn.Text, "☕ …", "the request is queued (☕ …)")
	local ring = ringOf()
	local stillThere = hazardModel() ~= nil
	truthy(stillThere, "the hazard is still coming: rest never removes one in flight")
	-- dodge it, then stand still: the rest begins once the sky is clear
	local stepped = false
	hum.MoveDirection = Vector3.zero
	run(10, function()
		if not stepped and string.find(chip.Text, "FLYTT DEG", 1, true) and ringOf() and ringOf().Parent then
			hrp.CFrame = hrp.CFrame + Vector3.new(ringOf().Size.Y / 2 + 1, 0, 0)
			stepped = true
		end
		if hum.Sit then return false end
	end)
	truthy(hum.Sit, "once the hazard had passed and the player stood still, the queued rest began")
	restBtn.Activated:Fire()
	run(0.2)
	truthy(not hum.Sit, "pressing again stands the player up")
	local _ = ring
end
-- idle rest: stand still for Config.Rest.IdleSeconds. Any threat resets the idle count (a hazard
-- inbound is exactly when idling must not begin), so this part runs at a real interval: the hazard
-- already scheduled (8-9 s) is let past, and the next one is 100 s of climbing away.
do
	Hz.IntervalMin, Hz.IntervalMax = 100, 101
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(Hz.IntervalMax, function() if hazardModel() then return false end end)
	run(12, function() if hazardModel() == nil and not hum.PlatformStand then return false end end)
	if hum.PlatformStand then run(1) end
	standOn(restPlats[2])
	hum.MoveDirection = Vector3.zero
	run(Config.Rest.IdleSeconds + 2, function()
		if string.find(chip.Text, "Pause", 1, true) then return false end
	end)
	truthy(string.find(chip.Text, "Pause", 1, true) ~= nil, "standing still for " .. Config.Rest.IdleSeconds .. " s rests (💤 Pause) (" .. chip.Text .. ")")
	truthy(not hum.Sit, "idle rest does not sit the player down")
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.5)
	truthy(string.find(chip.Text, "Pause", 1, true) == nil, "and moving ends it")
end
-- A band card never hides a hazard warning (review 2026-09-24, the title card): where there is no room
-- for the card between the HUD and the player's character (this 1280x720 window, every landscape phone,
-- a laptop), it sits ON the chip, and the chip is where the warning is written. So a warning ends the
-- card. Staged so they meet: the hazard clock is made DUE while floor 4 is climbed in the air (a hazard
-- never launches at a player off the ground, so it waits), the floor clear on 4's exit brings the
-- clockwork and its card, and the first frame climbing floor 5 launches the waiting hazard.
do
	Hz.IntervalMin, Hz.IntervalMax = 8, 9
	-- the second summit (part 5) left the Build Reveal card up, and band cards wait behind it: close it,
	-- and let the card that was waiting play out
	local reveal = hudRoot:FindFirstChild("Reveal")
	if reveal.Visible then reveal:FindFirstChild("CardClose").Activated:Fire() end
	run(5)
	reachExit(3)
	standOn(padOf(4))
	run(0.3)
	choose(4, readSafe(4))
	standOn(platformsOf(4)[2])
	hum.MoveDirection = Vector3.new(1, 0, 0)
	hum.FloorMaterial = Enum.Material.Air -- climbing, never grounded: whatever comes due waits
	local flew = false
	run(115, function()
		hrp.AssemblyLinearVelocity = Vector3.zero
		if hazardModel() then flew = true end
	end)
	truthy(not flew, "set-up: nothing launched at a climber who never touched the ground (115 s)")
	hum.FloorMaterial = Enum.Material.Plastic
	reachExit(4) -- the clockwork: its title card
	local clockwork = string.upper(bands[EnvBands.indexOf(bands, "clockwork")].name)
	truthy(card.Visible and string.find(card.Text, clockwork, 1, true) ~= nil,
		"set-up: the clockwork's title card is up after the floor clear (" .. tostring(card.Text) .. ")")
	standOn(padOf(5))
	frame(1 / 30)
	local cardBefore = card.Visible
	doorOf(5, 1):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr) -- a guess: no time to read
	local warnedAt, cardAtWarning, both = nil, nil, 0
	run(3, function(i)
		local warning = string.find(chip.Text, "⚠️", 1, true) ~= nil
		if warning and card.Visible then both += 1 end
		if warning and warnedAt == nil then
			warnedAt = i
			cardAtWarning = card.Visible
		end
	end)
	truthy(warnedAt ~= nil and cardBefore, string.format(
		"set-up: the card was up when door 5 was chosen, and the waiting hazard launched on floor 5 (warned at frame %s)", tostring(warnedAt)))
	eq(cardAtWarning, false, "the frame the chip warns, the band card is gone: a card never hides a hazard warning")
	eq(both, 0, "and never in any frame after")
	run(8, function() if hum.PlatformStand then standOn(platformsOf(5)[1]) end end)
end
-- the same no-cut watch over everything since the first rebirth: the second run (every band seen AGAIN,
-- so every piece is shown a second time), hazards, a knock and a simulated fall, rest, a third run
print(string.format("  after the rebirth: %d of %d frames were camera teleports (> 8 studs) and left out of the no-cut rule",
	cameraCutFrames, watchedFrames))
truthy(cameraCutFrames >= 3 and cameraCutFrames <= 0.02 * watchedFrames, string.format(
	"set-up: the exemption covers only teleports, at most 2%% of the frames watched (%d of %d)", cameraCutFrames, watchedFrames))
eq(cutViolations, 0, "after the rebirth (bands shown again, hazards, a knock and a fall, rest): no scenery part changed transparency by more than 0.1 in one frame"
	.. (if cutExample then "; e.g. " .. cutExample else ""))
eq(popIns, 0, "after the rebirth: every scenery part shown again entered invisible and faded in" .. (if popExample then "; e.g. " .. popExample else ""))
watchCuts = false

--======================================================================= 7. what the client touched

eq(serverCalls, ourCalls, "the client fired no remote of its own (" .. (serverCalls - ourCalls) .. " extra calls)")
do
	local names = {}
	for _, r in remotes:GetChildren() do table.insert(names, r.Name) end
	table.sort(names)
	eq(table.concat(names, ","), table.concat(remoteNames, ","), "the client added no remote")
end
do
	local bad, total = 0, 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			total += 1
			if not d.Anchored or d.CanCollide or d.CanQuery or d.CanTouch or d.CastShadow then bad += 1 end
		end
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") then
			bad += 1
		end
	end
	truthy(total > 0, "the client built scenery (" .. total .. " parts pooled)")
	eq(bad, 0, "every local part is anchored and not collidable, queryable, touchable or shadow-casting; no scripts or remotes")
end
do
	-- everything new in the workspace is the client's folder, the character's lantern, or the server's own work
	local strays = {}
	for _, d in h.workspace:GetDescendants() do
		if not before[d] and not d:IsDescendantOf(folder) and d ~= folder and not d:IsDescendantOf(towers)
			and not d:IsDescendantOf(char) then
			table.insert(strays, d.Name)
		end
	end
	eq(#strays, 0, "the client made nothing in the workspace outside its own folder (" .. table.concat(strays, ", ") .. ")")
	local lantern = hrp:FindFirstChild("ForkLantern")
	truthy(lantern ~= nil and lantern:IsA("PointLight") and not lantern.Shadows, "the climber's lantern is a shadowless light on their own root part")
end

--======================================================================= 8. the budgets, over everything above

print("  measured budgets (every frame of the whole check: 6 s at each fork, every climbing frame, the summit,")
print("  the rebirth glide, every hazard flight, the knock, rest):")
for _, line in bandTable do print("    " .. line) end
for k, v in budget do
	print(string.format("    peak %-8s %4d  at %s", k, v, tostring(budgetWhere[k])))
end
truthy(budget.parts <= Budget.MaxLocalParts, string.format("local parts peak %d <= %d", budget.parts, Budget.MaxLocalParts))
truthy(budget.emitters <= Budget.MaxEmitters, string.format("emitters peak %d <= %d", budget.emitters, Budget.MaxEmitters))
truthy(budget.rate <= Budget.MaxEmitterRate + 0.5, string.format("particles per second peak %d <= %d", budget.rate, Budget.MaxEmitterRate))
truthy(budget.beams <= Budget.MaxBeams, string.format("beams peak %d <= %d", budget.beams, Budget.MaxBeams))
truthy(budget.trails <= Budget.MaxTrails, string.format("trails peak %d <= %d", budget.trails, Budget.MaxTrails))
truthy(budget.lights <= Budget.MaxLights, string.format("lights peak %d <= %d", budget.lights, Budget.MaxLights))
truthy(budget.hazards <= Budget.MaxHazards, "never more than one hazard model in the scene")

eq(#h:errors(), 0, "no script errors (" .. table.concat(h:errors(), " | ") .. ")")
print(string.format("fork tower env: %d passed, %d failed", passed, failed))
if failed > 0 then error("fork tower env check failed", 0) end
