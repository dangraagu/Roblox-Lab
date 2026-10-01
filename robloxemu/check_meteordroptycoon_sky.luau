-- Meteor Drop Tycoon — the eye-candy glue: bands, seams, budgets, glide, streaks, Stargaze, and a client
-- that fires nothing and writes nothing the server built.
-- Run:  py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
--       luau check_meteordroptycoon_sky.luau 2>&1
--
-- The Beacon level is raised the way a player raises it: Buy("beacon") over the real remote, paid with
-- Stardust from a seeded profile, so every sky change here comes from the server's own State payload.
-- Every frame the local sky folder is counted against Config.Budget (parts, emitters, beams, trails, lights,
-- weather). Nothing renders headless: "a band shows" means its Parts are parented and opaque enough.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/meteor-drop-tycoon"), name = "meteor-drop-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 4242
local store = h.services.DataStoreService:GetDataStore("MeteorDropTycoon_v1")
store:SetAsync("u_" .. UID, { data = { v = 1, stardust = 1e15, lifetime = 1e15, beacon = 0, beaconAt = 1790000000,
	collector = 0, smelter = 60, hopper = 0, star = 2, starCores = 1, tutorial = 3 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Fx = mod("Fx")
local B = Config.Budget
local bands = Config.Env.Bands

--============================================================================ Fx.Presets.Dusk = band 1
do
	local d, b1 = Fx.Presets.Dusk, bands[1]
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
	eq(#mismatches, 0, "the server's starting light (Fx.Presets.Dusk) equals band 1 on every field band 1 defines (" .. table.concat(mismatches, ", ") .. ")")
end

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Gazer", UID)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local remotes = RS:FindFirstChild("MeteorRemotes")
local Buy = remotes:FindFirstChild("Buy")
local myBuys, serverEvents = 0, 0
for _, r in remotes:GetChildren() do
	if r.ClassName == "RemoteEvent" then
		r.OnServerEvent:Connect(function() serverEvents += 1 end)
	end
end
local folder = h.workspace:FindFirstChild("MeteorLocalSky")
truthy(folder ~= nil, "the client builds its local sky folder")
local RunService = h.game:GetService("RunService")
local cam = h.workspace.CurrentCamera
local Lighting = h.Lighting
local skyGui = plr.PlayerGui:FindFirstChild("MeteorSky")
local card = skyGui.Root:FindFirstChild("BandCard")

-- the budget, every frame
local worst = { parts = 0, emitters = 0, beams = 0, trails = 0, lights = 0, weather = 0, rate = 0 }
local overBudget = {}
local function measure(where)
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
	end
	local now = { parts = parts, emitters = emitters, beams = beams, trails = trails, lights = lights, weather = weatherOn, rate = rate }
	for k, v in now do worst[k] = math.max(worst[k], v) end
	local caps = { parts = B.MaxLocalParts, emitters = B.MaxEmitters, beams = B.MaxBeams, trails = B.MaxTrails, lights = B.MaxLights,
		weather = B.MaxWeatherEmitters, rate = B.MaxEmitterRate + 1e-6 }
	for k, cap in caps do
		if now[k] > cap and #overBudget < 10 then table.insert(overBudget, string.format("%s: %s %s > %s", where, k, tostring(now[k]), tostring(cap))) end
	end
end

local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 16), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
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
local function buyTo(L)
	while stateOf().beacon < L do
		Buy:simulateFireServer(plr, "beacon")
		myBuys += 1
		h:advance(0.2)
	end
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

local PIECE_PART = { hills = "Hill", birches = "BirchTrunk", lowSun = "Sun", moon = "Moon", lighthouse = "LighthouseTower",
	aurora = "AuroraHost", peaks = "Peak", comet = "CometHead", nebula = "NebulaCloud", ringedPlanet = "Planet", galaxy = "GalaxyCore" }
-- a piece is up when its marker part is parented and visible; the aurora is three Beams on an invisible host
local function pieceUp(id)
	if id == "aurora" then
		local host = folder:FindFirstChild("AuroraHost")
		if host == nil then return false end
		for _, d in host:GetChildren() do
			if d.ClassName == "Beam" and d.Enabled then return true end
		end
		return false
	end
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

run(3, "join")
eq(card.Visible, false, "a player who joins already in a band gets a quiet chip, not a title card")
checkBand(1, "at join (Beacon 0)")

--============================================================================ a purchase glides; a new band gets a title card
do
	-- Twilight starts at Beacon 5 and fades in over 2 levels: at Beacon 4 it is half in (smoothstep 0.5), so
	-- ClockTime settles at 17.8 + 0.5 x (19.0 - 17.8) = 18.4; one purchase to 5 moves the target to 19.0.
	buyTo(4)
	run(8, "Beacon 4")
	truthy(math.abs(Lighting.ClockTime - 18.4) < 0.02, string.format("at Beacon 4 the sky is half-way into Twilight (ClockTime %.3f, want 18.4)", Lighting.ClockTime))
	eq(card.Visible, false, "set-up: no card yet (Twilight is not entered at 4)")
	local before = Lighting.ClockTime
	buyTo(5)
	run(0.15, "Beacon 5, first frames")
	local early = Lighting.ClockTime - before
	run(8, "Beacon 5")
	local total = Lighting.ClockTime - before
	print(string.format("  a purchase at the seam: ClockTime +%.3f in the first 0.35 s, +%.3f after 8 s (target +0.6)", early, total))
	truthy(early > 0 and early < 0.2 * 0.6, "the purchase GLIDES: in its first 0.35 s the sky moves under a fifth of the way")
	truthy(math.abs(total - 0.6) < 0.02, "and arrives: ClockTime 19.0 after 8 s")
	truthy(card.Visible or string.find(card.Text, "TWILIGHT", 1, true) ~= nil, "entering Twilight by a purchase shows its title card: " .. card.Text)
end

--============================================================================ every band, every seam
for i = 2, #bands do
	local b = bands[i]
	-- the middle of the band, before the next one starts to fade in (the Core: 6 levels in)
	local mid = if i < #bands then math.floor((b.from + bands[i + 1].from - bands[i + 1].fade) / 2) else b.from + 6
	mid = math.max(mid, b.from)
	buyTo(mid)
	run(12, b.id .. " (Beacon " .. mid .. ")")
	checkBand(i, "at Beacon " .. mid)
	-- the previous band's pieces that this band does not share are gone
	for _, id in bands[i - 1].pieces do
		if not table.find(b.pieces, id) then
			truthy(not pieceUp(id), b.id .. ": the previous band's " .. id .. " has faded out")
		end
	end
end
print(string.format("  worst frame over all bands and seams: %d parts, %d emitters, %d beams, %d trails, %d lights, %d weather at %.1f/s",
	worst.parts, worst.emitters, worst.beams, worst.trails, worst.lights, worst.weather, worst.rate))
eq(#overBudget, 0, "every frame of every band and seam stays within Config.Budget (" .. table.concat(overBudget, "; ") .. ")")

--============================================================================ the Lighting write cap
do
	local probe = skyGui:FindFirstChild("MeteorSkyProbe")
	truthy(probe ~= nil, "the sky exposes its read-only probe to headless checks")
	-- a seam in motion: every field changing at once can write at most (fields x LightingHz) values a second
	local p0 = probe:Invoke()
	run(1, "idle")
	local p1 = probe:Invoke()
	print(string.format("  Lighting writes in 1 s at rest in the Core: %d", p1.lightingWrites - p0.lightingWrites))
	truthy(p1.lightingWrites - p0.lightingWrites <= 40 * Config.Env.LightingHz, "Lighting is written at most LightingHz times a second")
end

--============================================================================ the client fires nothing and writes nothing the server built
do
	eq(serverEvents, myBuys, "every client -> server event in this run was one of this check's own purchases: the sky and the HUD fired none")
	-- snapshot every server-built part, then run ONLY client frames (the server's threads stay parked)
	local snap = {}
	for _, d in h.workspace:FindFirstChild("Plots"):GetDescendants() do
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
		if d:IsA("BasePart") and d.Name ~= "Baseplate" then strays += 1 end
	end
	eq(strays, 0, "every client-built part lives in the local sky folder")
	local attrs = 0
	for _, d in folder:GetDescendants() do
		for _ in d:GetAttributes() do attrs += 1 end
	end
	eq(attrs, 0, "and carries no attributes")
end

--============================================================================ streaks for meteors on your own plot
do
	-- nobody collects in this check, so the plot is full (20 lying) and new meteors burn up; buy the biggest
	-- dish, whose catches are announced with a glow like any meteor
	for _ = 1, 8 do
		Buy:simulateFireServer(plr, "collector")
		myBuys += 1
		h:advance(0.2)
	end
	eq(stateOf().collector, 8, "set-up: the biggest Collector")
	local maxStreaks, maxTrails, seen = 0, 0, 0
	for _ = 1, 200 do
		frame(0.05)
		local n, t = 0, 0
		for _, d in folder:GetChildren() do
			if string.sub(d.Name, 1, 9) == "Fx_streak" and d.Transparency < 0.95 then
				n += 1
				local tr = d:FindFirstChildOfClass("Trail")
				if tr and tr.Enabled then t += 1 end
			end
		end
		if n > 0 then seen += 1 end
		maxStreaks = math.max(maxStreaks, n)
		maxTrails = math.max(maxTrails, t)
	end
	truthy(seen > 0, "a falling streak is drawn for meteors announced on the player's own plot")
	truthy(maxTrails <= Config.Meteors.MaxStreakTrails, string.format("at most %d streaks carry a trail at once (%d)", Config.Meteors.MaxStreakTrails, maxTrails))
	print(string.format("  streaks: up to %d at once, %d with trails, over 10 s at Beacon 50", maxStreaks, maxTrails))
end

--============================================================================ Stargaze
do
	local btn = skyGui.Root:FindFirstChild("StargazeSlot"):FindFirstChild("StargazeButton")
	local probe0 = skyGui:FindFirstChild("MeteorSkyProbe")
	for _ = 1, 400 do
		if not probe0:Invoke().hazardActive then break end
		frame(0.05)
	end
	eq(probe0:Invoke().hazardActive, false, "set-up: no hazard in the air")
	btn.Activated:Fire()
	run(0.5, "stargaze")
	local probe = skyGui:FindFirstChild("MeteorSkyProbe")
	eq(probe:Invoke().resting, true, "Stargaze starts a rest on the ground")
	eq(hum.Sit, true, "the player sits")
	eq(cam.CameraType, Enum.CameraType.Scriptable, "and the camera takes over to tilt up to the sky")
	local chip = skyGui.Root:FindFirstChild("BandChip"):FindFirstChild("ChipText")
	truthy(string.find(chip.Text, "Stargazing", 1, true) ~= nil, "the chip says so: " .. chip.Text)
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.6, "wake")
	eq(probe:Invoke().resting, false, "moving wakes the player")
	eq(cam.CameraType, Enum.CameraType.Custom, "and gives the camera back")
	hum.MoveDirection = Vector3.new(0, 0, 0)
end

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("meteordroptycoon sky: %d passed, %d failed", passed, failed))
if failed > 0 then error("meteordroptycoon sky check failed", 0) end
