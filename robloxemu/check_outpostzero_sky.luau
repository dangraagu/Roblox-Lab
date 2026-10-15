-- Outpost Zero — the eye-candy glue: bands, seams, budgets, the glide, Storm Front's lightning, the Grand Airship's
-- flight, the ☕ Break, and a client that fires nothing and writes nothing the server built.
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_sky.luau 2>&1
--
-- The population is raised the way a player raises it: by pressing the ★ lot's prompt, paid with credits from a
-- seeded profile, so every sky change here comes from the server's own State payload. Every frame the local sky
-- folder is counted against Config.Budget (parts, emitters, beams, trails, lights, weather). Nothing renders
-- headless: "a band shows" means its Parts are parented and opaque enough. (adapted from check_meteordroptycoon_sky)

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 4242
local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
store:SetAsync("u_" .. UID, { data = { v = 1, seed = 4242, credits = 1e15, lifetime = 1e15, lots = {}, savedAt = os.time(),
	ordersUntil = os.time() + 600, popAt = 0, airshipSeen = false, tutorial = 3 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Fx = mod("Fx")
local B = Config.Budget
local bands = Config.Env.Bands

--============================================================================ Fx.Presets.Dawn = band 1
do
	local d, b1 = Fx.Presets.Dawn, bands[1]
	local function rgb(c) return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) } end
	local mismatches = {}
	for group, props in { lighting = d.lighting, atmosphere = d.atmosphere, bloom = d.bloom, colorCorrection = d.colorCorrection, sunRays = d.sunRays } do
		for k, v in b1[group] do
			local pv = props[k]
			if type(v) == "table" then
				local c = pv and rgb(pv)
				if c == nil or c[1] ~= v[1] or c[2] ~= v[2] or c[3] ~= v[3] then table.insert(mismatches, group .. "." .. k) end
			elseif pv ~= v then
				table.insert(mismatches, group .. "." .. k .. " " .. tostring(pv) .. " vs " .. tostring(v))
			end
		end
	end
	eq(#mismatches, 0, "the server's starting light (Fx.Presets.Dawn) equals band 1 on every field band 1 defines (" .. table.concat(mismatches, ", ") .. ")")
	truthy(math.abs(h.Lighting.ClockTime - 6.4) < 1e-9, "and the server applied it: Lighting.ClockTime 6.4 before any client")
end

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Gazer", UID)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Rock
hum.MoveDirection = Vector3.new(0, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local remotes = RS:FindFirstChild("CityRemotes")
local serverEvents = 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverEvents += 1 end)
	end
end
local folder = h.workspace:FindFirstChild("OutpostLocalSky")
truthy(folder ~= nil, "the client builds its local sky folder")
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local Lighting = h.Lighting
local skyGui = plr.PlayerGui:FindFirstChild("OutpostSky")
local card = skyGui.Root:FindFirstChild("BandCard")
local probe = skyGui:FindFirstChild("OutpostSkyProbe")
truthy(probe ~= nil, "the sky exposes its read-only probe to headless checks")
local shelf = plr.RespawnLocation.Parent

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

-- the budget, every frame (the sky folder, the HUD's local folder, and lights on the character)
local hudLocal = plr.PlayerGui:FindFirstChild("HudLocal")
local worst = { parts = 0, emitters = 0, beams = 0, trails = 0, lights = 0, weather = 0, rate = 0 }
local overBudget = {}
local function measure(where)
	engineScan(folder, where)
	engineScan(shelf, where)
	local parts, emitters, beams, trails, lights, weatherOn, rate = 0, 0, 0, 0, 0, 0, 0
	for _, d in folder:GetDescendants() do
		local c = d.ClassName
		if d:IsA("BasePart") then parts += 1
		elseif c == "ParticleEmitter" and d.Enabled ~= false then
			emitters += 1
			if string.sub(d.Name, 1, 8) == "Weather_" then
				weatherOn += 1
				rate += d.Rate
			end
		elseif c == "Beam" and d.Enabled ~= false then beams += 1
		elseif c == "Trail" and d.Enabled ~= false then trails += 1
		elseif (c == "PointLight" or c == "SpotLight") and d.Enabled ~= false then lights += 1
		end
	end
	for _, d in char:GetDescendants() do
		if d.ClassName == "PointLight" and d.Enabled ~= false and (d.Brightness or 1) > 0 then lights += 1 end
		if d.ClassName == "Beam" and d.Enabled ~= false then beams += 1 end
	end
	-- the ★ glow is the HUD's, parented to the starred post on the client
	for _, d in shelf:GetDescendants() do
		if d.Name == "StarGlow" and d.ClassName == "PointLight" then lights += 1 end
	end
	local now = { parts = parts, emitters = emitters, beams = beams, trails = trails, lights = lights, weather = weatherOn, rate = rate }
	for k, v in now do worst[k] = math.max(worst[k], v) end
	local caps = { parts = B.MaxLocalParts, emitters = B.MaxEmitters, beams = B.MaxBeams, trails = B.MaxTrails, lights = B.MaxLights,
		weather = B.MaxWeatherEmitters, rate = B.MaxEmitterRate + 1e-6 }
	for k, cap in caps do
		if now[k] > cap and #overBudget < 10 then table.insert(overBudget, string.format("%s: %s %s > %s", where, k, tostring(now[k]), tostring(cap))) end
	end
end

local flashTimes = {}
local lastFlashes = 0
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 16), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	local p = probe:Invoke()
	if p.flashes > lastFlashes then
		lastFlashes = p.flashes
		table.insert(flashTimes, h.scheduler:now())
	end
end
local function run(seconds, where)
	local n = math.floor(seconds / 0.05)
	for _ = 1, n do
		frame(0.05)
		measure(where)
	end
end
local function stateOf()
	local sent = remotes.State:sentTo(plr)
	return sent[#sent].args[1]
end
-- press the ★ lot's prompt, the way a player does (stood next to its post), until the population reaches `target`
local presses = 0
local function buyTo(target)
	for _ = 1, 5000 do
		local st = stateOf()
		if st.population >= target or st.star == nil then return st.population end
		local post = shelf.Lots:FindFirstChild("Lot_" .. st.star.key).Post
		hrp.CFrame = CFrame.new(post.Position + Vector3.new(0, 1.5, 0))
		post.BuildPrompt.Triggered:Fire(plr)
		presses += 1
		frame(0.13) -- under the 8/s limit
	end
	return stateOf().population
end
local function shown(name)
	for _, d in folder:GetChildren() do
		if d.Name == name and d:IsA("BasePart") and d.Transparency < 0.95 then return true end
	end
	return false
end
local function critterKinds()
	local kinds = {}
	for _, d in folder:GetChildren() do
		local k = string.match(d.Name, "^Critter_(%a+)_")
		if k then kinds[k] = true end
	end
	return kinds
end

local PIECE_PART = { fogBanks = "FogBank", rockSpires = "Spire", cloudSea = "CloudSea", farShelves = "FarRock", farWindows = "FarWindow",
	skyRail = "Rail", stormWall = "StormCloud", cloudLightning = "CloudFlash" }
local function beamsOn(hostName)
	local host = folder:FindFirstChild(hostName)
	if host == nil then return false end
	for _, d in host:GetChildren() do
		if d.ClassName == "Beam" and d.Enabled then return true end
	end
	return false
end
-- a piece is up when its marker part is parented (and, for opaque pieces, visible); the aurora and the pennants are
-- Beams on an invisible host; the cloud flash is parented but transparent between flashes
local function pieceUp(id)
	if id == "aurora" then return beamsOn("AuroraHost") end
	if id == "pennants" then return beamsOn("PennantHost") end
	if id == "cloudLightning" then return folder:FindFirstChild("CloudFlash") ~= nil end
	return shown(PIECE_PART[id])
end
local function checkBand(i, where)
	local b = bands[i]
	for _, id in b.pieces do
		truthy(pieceUp(id), b.id .. ": its scenery piece " .. id .. " is up " .. where)
	end
	local kinds = critterKinds()
	for _, a in b.ambient do
		truthy(kinds[a.kind], b.id .. ": its critter " .. a.kind .. " is out " .. where)
	end
	local host = folder:FindFirstChild("WeatherHost")
	local pe = host and host:FindFirstChild("Weather_" .. b.weather.kind)
	truthy(pe ~= nil and pe.Enabled, b.id .. ": its weather (" .. b.weather.kind .. ") is falling " .. where)
	truthy(math.abs(Lighting.ClockTime - b.lighting.ClockTime) < 0.03,
		string.format("%s: ClockTime reaches the band's %.1f %s (%.3f)", b.id, b.lighting.ClockTime, where, Lighting.ClockTime))
end
local function smooth(x)
	if x <= 0 then return 0 end
	if x >= 1 then return 1 end
	return x * x * (3 - 2 * x)
end

run(3, "join")
eq(card.Visible, false, "a player who joins already in a band gets a quiet chip, not a title card")
checkBand(1, "at join (population 0)")

--============================================================================ a purchase glides; a new band gets a title card
do
	-- Clear Morning starts at 80 and fades in over 30: at population P in 50..80 ClockTime settles at
	-- 6.4 + smoothstep((P - 50) / 30) x (9.0 - 6.4). Buy into the fade, settle, then buy across 80.
	local p = buyTo(64)
	run(10, "population " .. p)
	local want = 6.4 + smooth((p - 50) / 30) * 2.6
	truthy(math.abs(Lighting.ClockTime - want) < 0.02, string.format("at population %d the sky is part-way into Clear Morning (ClockTime %.3f, want %.3f)", p, Lighting.ClockTime, want))
	eq(card.Visible, false, "set-up: no card yet (Clear Morning is not entered below 80)")
	local before = Lighting.ClockTime
	local t0 = h.scheduler:now()
	local p2 = buyTo(80)
	local tEnter = h.scheduler:now()
	local early = Lighting.ClockTime - before
	run(0.5, "population " .. p2 .. ", the card")
	local cardShown, cardText = card.Visible, card.Text
	run(9.5, "population " .. p2)
	local total = Lighting.ClockTime - before
	print(string.format("  a purchase at the seam (%d -> %d): ClockTime +%.3f in the first %.2f s, +%.3f after 10 s (target +%.3f)",
		p, p2, early, tEnter - t0, total, 9.0 - before))
	truthy(early < 0.5 * (9.0 - before), "the purchase GLIDES: right after it the sky has moved under half the way")
	truthy(math.abs(Lighting.ClockTime - 9.0) < 0.02, "and arrives: ClockTime 9.0 after 10 s")
	truthy(cardShown and string.find(cardText, "CLEAR MORNING", 1, true) ~= nil, "entering Clear Morning by a purchase shows its title card: " .. cardText)
	eq(card.Visible, false, "and the card is gone again 10 s later")
end

--============================================================================ every band, every seam (the airship on the way)
for i = 2, #bands do
	local b = bands[i]
	local mid = if i < #bands then math.floor((b.from + bands[i + 1].from - bands[i + 1].fade) / 2) else b.from + 50000
	mid = math.max(mid, b.from)
	local p = buyTo(mid)
	run(14, b.id .. " (population " .. p .. ")")
	checkBand(i, "at population " .. p)
	for _, id in bands[i - 1].pieces do
		if not table.find(b.pieces, id) then
			truthy(not pieceUp(id), b.id .. ": the previous band's " .. id .. " has faded out")
		end
	end
	if b.id == "lantern" then
		-- the Grand Airship: the Skyport purchase flew a copy in on this client, and the server moored it
		local pr = probe:Invoke()
		eq(pr.flights, 1, "the Skyport's purchase flew one Grand Airship in on this client")
		truthy(shelf:FindFirstChild("Airship") ~= nil, "and after 12 s the server moored it over the Town Hall")
		eq(stateOf().airship, "moored", "the State says moored")
		eq(pr.flightActive, false, "the client's flying copy is gone once it moored")
	end
	if b.id == "storm" then
		-- silent lightning: at most one flash per 3 s, ever
		run(60, "storm lightning")
		local tight = math.huge
		for k = 2, #flashTimes do tight = math.min(tight, flashTimes[k] - flashTimes[k - 1]) end
		print(string.format("  Storm Front: %d lightning flashes in %.0f s; the closest two %.2f s apart", #flashTimes, 74, tight))
		truthy(#flashTimes >= 3, "the storm flashes (" .. #flashTimes .. " flashes)")
		truthy(tight >= Config.Env.LightningMinGap - 1e-6, string.format("never two flashes within %d s (closest %.2f s)", Config.Env.LightningMinGap, tight))
	end
end
print(string.format("  %d presses; worst frame over all bands and seams: %d parts, %d emitters, %d beams, %d trails, %d lights, %d weather at %.1f/s",
	presses, worst.parts, worst.emitters, worst.beams, worst.trails, worst.lights, worst.weather, worst.rate))
eq(#overBudget, 0, "every frame of every band and seam stays within Config.Budget (" .. table.concat(overBudget, "; ") .. ")")
truthy(worst.parts > 0 and worst.weather > 0, "CONTROL: the meter does count what the sky builds")
do
	local list = engineReport()
	for _, line in list do print("  engine: " .. line) end
	eq(#list, 0, "every part shown in every band and seam (the local sky, the critters, the flight, the city, the moored airship) has a size Roblox draws as written")
end

--============================================================================ the Lighting write cap
do
	local p0 = probe:Invoke()
	run(1, "idle")
	local p1 = probe:Invoke()
	print(string.format("  Lighting writes in 1 s at rest under the aurora: %d", p1.lightingWrites - p0.lightingWrites))
	truthy(p1.lightingWrites - p0.lightingWrites <= 40 * Config.Env.LightingHz, "Lighting is written at most LightingHz times a second")
end

--============================================================================ the client fires nothing and writes nothing the server built
do
	eq(serverEvents, 0, "no client -> server event in this whole run: there is no remote to fire, and nothing fired one")
	local snap = {}
	for _, d in h.workspace:FindFirstChild("Shelves"):GetDescendants() do
		if d:IsA("BasePart") then
			snap[d] = { d.Color, d.Transparency, d.Size, d.CFrame, d.Parent }
		end
	end
	for _ = 1, 300 do RunService.RenderStepped:Fire(1 / 30) end
	local changed = 0
	for d, s in snap do
		if d.Color ~= s[1] or d.Transparency ~= s[2] or d.Size ~= s[3] or d.CFrame ~= s[4] or d.Parent ~= s[5] then changed += 1 end
	end
	eq(changed, 0, "300 client frames change nothing on any server-built part")
	local strays = 0
	for _, d in h.workspace:GetChildren() do
		if d:IsA("BasePart") then strays += 1 end
	end
	eq(strays, 0, "every client-built part lives in the local sky folder")
	local attrs = 0
	for _, d in folder:GetDescendants() do
		for _ in d:GetAttributes() do attrs += 1 end
	end
	eq(attrs, 0, "and carries no attributes")
end

--============================================================================ ☕ Break
do
	local btn = skyGui.Root:FindFirstChild("BreakSlot"):FindFirstChild("BreakButton")
	for _ = 1, 400 do
		if not probe:Invoke().hazardActive then break end
		frame(0.05)
	end
	eq(probe:Invoke().hazardActive, false, "set-up: no hazard in the air")
	local orders0 = stateOf().ordersLeft
	btn.Activated:Fire()
	run(0.5, "break")
	eq(probe:Invoke().resting, true, "☕ Break starts a rest on the ground")
	eq(hum.Sit, true, "the player sits")
	eq(cam.CameraType, Enum.CameraType.Scriptable, "and the camera takes over to tilt up to the sky")
	local chip = skyGui.Root:FindFirstChild("BandChip"):FindFirstChild("ChipText")
	truthy(string.find(chip.Text, "On a break", 1, true) ~= nil, "the chip says so: " .. chip.Text)
	local clock0 = probe:Invoke().hazardClock
	run(10, "on a break")
	eq(probe:Invoke().hazardClock, clock0, "the hazard clock is frozen during the break (not reset)")
	local orders1 = stateOf().ordersLeft
	truthy(orders1 <= orders0 - 9.5, string.format("the Orders keep counting down during a break (%.1f -> %.1f s): a break never renews them", orders0, orders1))
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.6, "wake")
	eq(probe:Invoke().resting, false, "moving ends the break")
	eq(cam.CameraType, Enum.CameraType.Custom, "and gives the camera back")
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local clock2 = probe:Invoke().hazardClock
	run(2, "after the break")
	truthy(probe:Invoke().hazardClock > clock2, "and the hazard clock runs again")
	-- pressing BUILD ends a break (DESIGN 7), without moving
	btn.Activated:Fire()
	run(0.5, "break again")
	eq(probe:Invoke().resting, true, "set-up: on a break again")
	local st = stateOf()
	local post = shelf.Lots:FindFirstChild("Lot_" .. st.star.key).Post
	post.BuildPrompt.Triggered:Fire(plr)
	run(0.3, "build during a break")
	eq(probe:Invoke().resting, false, "pressing a lot's BUILD ends the break")
	eq(cam.CameraType, Enum.CameraType.Custom, "and gives the camera back")
end

--============================================================================ a break asked for with a hazard inbound is queued, and says so
do
	local btn = skyGui.Root:FindFirstChild("BreakSlot"):FindFirstChild("BreakButton")
	hum.MoveDirection = Vector3.new(0.01, 0, 1) -- playing (never idles into rest), on the own shelf, in a hazard band
	local active = false
	for _ = 1, 4000 do -- up to 200 s: the shipped interval is 120-180 s of play
		frame(0.05)
		if probe:Invoke().hazardActive then active = true break end
	end
	truthy(active, "set-up: a hazard is inbound")
	btn.Activated:Fire()
	run(0.1, "queued break")
	local pr = probe:Invoke()
	eq(pr.resting, false, "a break cannot start with a hazard inbound (it is not a panic button)")
	eq(pr.pending, true, "it is queued")
	local chip = skyGui.Root:FindFirstChild("BandChip"):FindFirstChild("ChipText")
	truthy(string.find(chip.Text, "Break queued: step out of the red ring first", 1, true) ~= nil, "and the chip says why: " .. chip.Text)
	hum.MoveDirection = Vector3.new(0, 0, 0)
end

--============================================================================ a break asked for in mid-air says the real reason
-- (round 2, finding B4) Rest queues a request while the player is airborne too, and the chip used to say "step out
-- of the red ring first" with no ring anywhere: a refused action has to say why (standard §1).
do
	local btn = skyGui.Root:FindFirstChild("BreakSlot"):FindFirstChild("BreakButton")
	local chip = skyGui.Root:FindFirstChild("BandChip"):FindFirstChild("ChipText")
	for _ = 1, 400 do
		if not probe:Invoke().hazardActive then break end
		frame(0.05)
	end
	run(1, "after the hazard")
	local pr0 = probe:Invoke()
	if pr0.resting or pr0.pending then btn.Activated:Fire(); run(0.2, "stop the queued break") end
	pr0 = probe:Invoke()
	eq(pr0.hazardActive or pr0.resting or pr0.pending, false, "set-up: no hazard, no break, nothing queued")
	hum.FloorMaterial = Enum.Material.Air -- mid-jump
	btn.Activated:Fire()
	run(0.1, "a break asked for in mid-air")
	local pr = probe:Invoke()
	eq(pr.pending, true, "a break asked for in mid-air is queued")
	eq(string.find(chip.Text, "red ring", 1, true), nil, "and with no hazard the chip does not talk about a red ring: " .. chip.Text)
	truthy(string.find(chip.Text, "when you land", 1, true) ~= nil, "it says the break starts when you land: " .. chip.Text)
	hum.FloorMaterial = Enum.Material.Rock
	run(0.5, "landed")
	eq(probe:Invoke().resting, true, "landing starts the queued break")
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.6, "wake")
	hum.MoveDirection = Vector3.new(0, 0, 0)
	eq(probe:Invoke().resting, false, "set-up: moving ends it")
end

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero sky: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero sky check failed", 0) end
