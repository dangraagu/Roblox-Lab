-- Steal a Cryptid - the night's BUDGETS at the worst case, asserted on every frame, and its pools bounded.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_budget.luau 2>&1
--
-- check_stealacryptid_night.luau measures each band and camp as a player finds them. This file builds the
-- heaviest scene the client can reach and holds it to Config.Night.Budget on EVERY frame:
--   * a full lair (nine occupied cages: nine habitats), hazards made rapid (Config.Night.Hazards
--     IntervalMin/Max 0.05, in memory) so one is almost always flying, a player walking so it never rests;
--   * a purchase that raises the rank strange -> mythic with a hazard in the air (the seam with the most
--     beams), nine habitats for 20 s; then two cages freed and two more Bigfoots bought, the second with a
--     hazard in the air: the mythic -> gathering seam (the most parts: the gathering's legends and moths join
--     while mythic night's set fades), nine habitats at the gathering for 20 s with every one of its pieces
--     drawn (the budget is capped in code, so a refused piece would hide here, not overflow); one released (a
--     hunt needs a free cage), then a rest by the campfire, then all four camps and home again, three times over;
--   * and the pools: after the first cycle, the next two must build (almost) nothing new. A client that
--     rebuilt a piece, a habitat or a hazard model on every visit would grow here without bound.
-- The same budget numbers are printed for EYECANDY.md.

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Night = require("../steal-a-cryptid/src/shared/Night")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-budget", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local N = Config.Night
local B = N.Budget
local W = Config.World
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 6606
do
	local fill = { "jackalope", "hodag", "chupacabra", "dogman", "mothman", "nessie", "jerseydevil", "dogman" }
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = fill[i] or "", jar = 0 } end
	-- rank 3 (a Legendary, no Mythic yet), eight occupied cages, and enough Essence for the Mythic at P3
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 11000000, savedAt = NOW, cagesUnlocked = 9, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 },
		journal = { "jackalope", "hodag", "chupacabra", "dogman", "jerseydevil", "mothman", "nessie" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local GameHz = h:_require(h.ReplicatedStorage:FindFirstChild("Config")).Night.Hazards
GameHz.IntervalMin, GameHz.IntervalMax = 0.05, 0.05
local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Heavy", ME)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Grass
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Night.client"))
local folder = h.workspace:FindFirstChild("CryptidNight")
local hudRoot = plr.PlayerGui.CryptidHud.Root
local bus = plr.PlayerGui.CryptidHud.NightBus
local remState = remotes:FindFirstChild("State")
local function st()
	local sent = remState:sentTo(plr)
	return sent[#sent].args[1]
end

local cam = h.workspace.CurrentCamera
local peak = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0, hazards = 0 }
local peakWhere = {}
local over = {}
local seen = {}
local seenCount = 0
local where = "?"
local walker = nil
local flyingFrames, campfireFrames = 0, 0

local function measure()
	local parts, emitters, rate, beams, trails, lights = 0, 0, 0, 0, 0, 0
	local kinds, nk = {}, 0
	for _, d in folder:GetDescendants() do
		if not seen[d] then seen[d] = true; seenCount += 1 end
		local cls = d.ClassName
		if cls == "Part" or cls == "WedgePart" then
			parts += 1
			local k = string.match(d.Name, "^Hazard_(%a+)_")
			if k and not kinds[k] then kinds[k] = true; nk += 1 end
		elseif cls == "ParticleEmitter" and d.Enabled then
			emitters += 1
			rate += d.Rate or 0
		elseif cls == "Beam" and d.Enabled then
			beams += 1
		elseif cls == "Trail" and d.Enabled then
			trails += 1
		elseif (cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight") and d.Enabled then
			lights += 1
		end
	end
	local m = { parts = parts, emitters = emitters, rate = rate, beams = beams, trails = trails, lights = lights, hazards = nk }
	local limits = { parts = B.MaxLocalParts, emitters = B.MaxEmitters, rate = B.MaxEmitterRate, beams = B.MaxBeams,
		trails = B.MaxTrails, lights = B.MaxLights, hazards = B.MaxHazards }
	for k, v in m do
		if v > peak[k] then peak[k] = v; peakWhere[k] = where end
		if v > limits[k] + 1e-6 and over[k] == nil then over[k] = string.format("%s %s > %s at %s", k, tostring(v), tostring(limits[k]), where) end
	end
	if nk > 0 then flyingFrames += 1 end
	for _, d in folder:GetChildren() do
		if string.sub(d.Name, 1, 9) == "Campfire_" then campfireFrames += 1; break end
	end
	return m
end

local function frame(dt)
	if walker then
		walker.phase += dt
		hrp.CFrame = CFrame.new(walker.centre + Vector3.new(math.cos(walker.phase) * 6, 0, math.sin(walker.phase) * 6))
		hum.MoveDirection = Vector3.new(-math.sin(walker.phase), 0, math.cos(walker.phase))
	end
	local p = hrp.Position
	cam.CFrame = CFrame.new(p + Vector3.new(0, 9, -22), p)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	measure()
end
local function run(seconds, until_)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		frame(1 / 30)
		if until_ and until_() then return true end
	end
	return false
end
local function flying()
	for _, d in folder:GetChildren() do
		if string.find(d.Name, "^Hazard_%a+_") then return true end
	end
	return false
end

run(1)
local plot = h.workspace.Lairs:FindFirstChild("Plot_" .. st().plot)
local lair = plot.Lair
local frameCF = plot.Floor.CFrame * CFrame.new(-36, 0.5, -48)
local function apron(x, z) return frameCF:PointToWorldSpace(Vector3.new(x, W.RootHeight, z)) end
local function walkAt(x, z) walker = { centre = apron(x, z), phase = 0 } end

-- 1. rank 3 with eight habitats and hazards flying
where = "strange, eight habitats, hazards"
walkAt(36, 4)
run(30)
-- 2. the Mythic from P3 with a hazard in the air: the strange -> mythic seam
where = "seam strange>mythic, hazards"
walker = nil
hrp.CFrame = CFrame.new(apron(W.Apron.P3.x, W.Apron.P3.z - 4))
run(12, flying)
truthy(flying(), "2: a hazard is flying when the rank rises")
lair.Pedestals.Pedestal_3.Buy.Triggered:Fire(plr)
run(0.1)
eq(st().rank, 4, "2: the Mythic raised the rank to 4")
walkAt(W.Apron.P3.x, W.Apron.P3.z - 6)
run(6)
where = "mythic, nine habitats, hazards"
walkAt(36, 4)
run(20)
local nine = 0
for col = 1, 9 do if st().cages[col].sp ~= "" then nine += 1 end end
eq(nine, 9, "2: nine occupied cages")

local function release(col)
	walker = nil
	hrp.CFrame = CFrame.new(apron(36, 80))
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local rel = lair.Cages:FindFirstChild("Cage_" .. col):FindFirstChild("Release")
	rel.PromptButtonHoldBegan:Fire(plr)
	h:advance(Config.Economy.ReleaseHoldSeconds + 0.05)
	rel.Triggered:Fire(plr)
	run(1.5)
	return st().cages[col].sp == ""
end

-- 2b. past the Mythic: the gathering (Night.level), reached when the best lair income ever passes GatheringRate.
-- Free the Jackalope's and the Hodag's cages, then two Bigfoots from P3, the second (the crossing) with a hazard flying.
do
	truthy(release(1) and release(2), "2b: cages 1 and 2 released through their prompts")
	where = "seam mythic>gathering, hazards"
	hrp.CFrame = CFrame.new(apron(W.Apron.P3.x, W.Apron.P3.z - 4))
	for k = 1, 2 do
		run(12, flying)
		if k == 2 then truthy(flying(), "2b: a hazard is flying when the best lair income crosses GatheringRate") end
		lair.Pedestals.Pedestal_3.Buy.Triggered:Fire(plr)
		run(0.1)
		if k == 1 then
			truthy((st().best or 0) < N.GatheringRate, string.format("2b: one more Bigfoot (%s/s) is not yet the gathering", tostring(st().best)))
			run(2.5) -- the pedestal refills
		end
	end
	truthy((st().best or 0) >= N.GatheringRate, string.format("2b: the second took the best lair income to %s/s (>= %d)", tostring(st().best), N.GatheringRate))
	walkAt(W.Apron.P3.x, W.Apron.P3.z - 6)
	run(6)
	where = "gathering, nine habitats, hazards"
	walkAt(36, 4)
	run(20)
	nine = 0
	for col = 1, 9 do if st().cages[col].sp ~= "" then nine += 1 end end
	eq(nine, 9, "2b: nine occupied cages again")
	-- every piece the band shows is drawn: the budget's cap refused nothing at the heaviest home band
	local FIRST = { farGround = "FarGround", ridges = "Ridge", farPines = "FarPine", owls = "Owl", auroraGreen = "AuroraGreenHost",
		auroraGold = "AuroraGoldHost", ufos = "Ufo", bigfoot = "Bigfoot_", bloodMoon = "BloodMoon", gathering = "Legend_" }
	local band = N.Home[#N.Home]
	for _, id in band.pieces do
		local n = 0
		for _, d in folder:GetDescendants() do
			if (d.ClassName == "Part" or d.ClassName == "WedgePart") and FIRST[id] and string.sub(d.Name, 1, #FIRST[id]) == FIRST[id] then n += 1 end
		end
		truthy(FIRST[id] ~= nil and n > 0, "2b: at the gathering with nine habitats and hazards flying, piece " .. id .. " is drawn (nothing refused)")
	end
	local habitats = 0
	for _, d in folder:GetDescendants() do
		if (d.ClassName == "Part" or d.ClassName == "WedgePart") and string.match(d.Name, "^Habitat_%d+_Patch$") then habitats += 1 end
	end
	eq(habitats, 9, "2b: and all nine habitats are drawn")
end

-- A hunt needs a free cage for the prize ("Free a cage first"): release one through the real prompt
-- (the server's hold), as a player would. Eight habitats stay for the camp cycles below.
do
	walker = nil
	hrp.CFrame = CFrame.new(apron(36, 80))
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local rel = lair.Cages:FindFirstChild("Cage_5"):FindFirstChild("Release")
	rel.PromptButtonHoldBegan:Fire(plr)
	h:advance(Config.Economy.ReleaseHoldSeconds + 0.05)
	rel.Triggered:Fire(plr)
	run(1.5)
	eq(st().cages[5].sp, "", "2: cage 5 released through its prompt (a hunt needs a free cage)")
end

local function restByTheFire()
	-- press Rest; if a hazard is inbound it queues: step out of its ring at the lock, then stand still
	walker = nil
	hum.MoveDirection = Vector3.new(0, 0, 0)
	hudRoot.Toggles.RestToggle.Activated:Fire()
	run(0.1)
	if bus.RestLabel.Value ~= N.Text.RestingButton then
		run(6, function() return string.sub(bus.Status.Value, 1, 5) == "Move!" or bus.RestLabel.Value == N.Text.RestingButton end)
		if bus.RestLabel.Value ~= N.Text.RestingButton then
			run(0.4)
			for _ = 1, 12 do
				hrp.CFrame = CFrame.new(hrp.Position + Vector3.new(16 / 30, 0, 0))
				hum.MoveDirection = Vector3.new(1, 0, 0)
				frame(1 / 30)
			end
			hum.MoveDirection = Vector3.new(0, 0, 0)
			run(8, function() return bus.RestLabel.Value == N.Text.RestingButton end)
		end
	end
	return bus.RestLabel.Value == N.Text.RestingButton
end

local cycleSeen = {}
for cycle = 1, 3 do
	where = "cycle " .. cycle .. ": resting by the campfire"
	hrp.CFrame = CFrame.new(apron(36, 4))
	truthy(restByTheFire(), "cycle " .. cycle .. ": resting by the campfire")
	run(10)
	for tier = 1, #Config.Camps do
		where = "cycle " .. cycle .. ": to camp " .. tier
		walker = nil
		hrp.CFrame = CFrame.new(apron(W.Apron.Board.x, W.Apron.Board.z - 4))
		hum.MoveDirection = Vector3.new(1, 0, 0)
		run(0.5)
		remotes.Hunt:simulateFireServer(plr, tier)
		h:advance(0.05)
		truthy(Night.pocketSlot(Config, hrp.Position.X) ~= nil, "cycle " .. cycle .. ": in camp " .. tier)
		where = "cycle " .. cycle .. ": camp " .. tier
		run(8)
		remotes.LeaveCamp:simulateFireServer(plr)
		h:advance(0.05)
		where = "cycle " .. cycle .. ": home after camp " .. tier .. ", hazards"
		walkAt(36, 4)
		run(Config.Night.Hazards.SettleSeconds + 6)
	end
	cycleSeen[cycle] = seenCount
end

print("\n  budget peaks, every frame (a full lair, hazards flying, the gathering, the campfire, four camps, three cycles):")
local limits = { parts = B.MaxLocalParts, emitters = B.MaxEmitters, rate = B.MaxEmitterRate, beams = B.MaxBeams,
	trails = B.MaxTrails, lights = B.MaxLights, hazards = B.MaxHazards }
for _, k in { "parts", "emitters", "rate", "beams", "trails", "lights", "hazards" } do
	print(string.format("    %-9s %6.1f of %-4s at %s", k, peak[k], tostring(limits[k]), tostring(peakWhere[k])))
end
print(string.format("  unique instances ever built: %d after cycle 1, %d after cycle 2, %d after cycle 3", cycleSeen[1], cycleSeen[2], cycleSeen[3]))
print(string.format("  frames with a hazard flying: %d; frames with the campfire: %d", flyingFrames, campfireFrames))
for k, v in over do truthy(false, "over budget: " .. v) end
truthy(next(over) == nil, "every frame of the worst case is within Config.Night.Budget")
-- and the shipped art never NEEDS the cap: scenery, critters and habitats are admitted against the budget minus the
-- Reserve, so a worst case at or under that line means no item was ever refused (none popped in late)
truthy(peak.parts <= B.MaxLocalParts - B.Reserve.parts, string.format("the worst case's %d parts fit under the budget minus its Reserve (%d): the cap never had to refuse a part",
	peak.parts, B.MaxLocalParts - B.Reserve.parts))
truthy(flyingFrames > 30 * 30, "hazards were flying for more than 30 s of it")
truthy(campfireFrames > 30 * 20, "the campfire burned for more than 20 s of it")
truthy(cycleSeen[3] - cycleSeen[2] <= 12, string.format("the pools are bounded: the third cycle built %d new instances (<= 12: critters of a flock not yet all out at once)", cycleSeen[3] - cycleSeen[2]))
truthy(cycleSeen[2] - cycleSeen[1] <= 30, string.format("and the second built %d", cycleSeen[2] - cycleSeen[1]))
-- The weather cap, driven directly. Normal play blends at most two weather kinds, so nothing above ever
-- asks for more; a teleport home from a camp during a rank glide could ask for three. The game's own
-- NightArt (the bundle's module, on a scratch folder) is asked for every kind at a rate far over budget.
do
	local RS = h.ReplicatedStorage
	local NightArt = h:_require(RS:FindFirstChild("NightArt"))
	local GameConfig = h:_require(RS:FindFirstChild("Config"))
	local scratch = Instance.new("Folder")
	scratch.Name = "WeatherCapProbe"
	scratch.Parent = h.workspace
	local k = 0
	local art = NightArt.new(scratch, function() k += 1; return (k % 97) / 97 end, GameConfig,
		h:_require(RS:FindFirstChild("EnvBands")), h:_require(RS:FindFirstChild("Night")))
	local ask = { fireflies = 30, mist = 30, wisplights = 30, stardust = 30, embers = 30, sand = 30, spores = 30 }
	local function count()
		local on, rate = 0, 0
		for _, d in scratch:GetDescendants() do
			if d.ClassName == "ParticleEmitter" and d.Enabled then on += 1; rate += d.Rate end
		end
		return on, rate
	end
	art:updateWeather(ask, Vector3.new(0, 20, 0), "camera")
	local on, rate = count()
	print(string.format("  weather cap probe: 7 kinds asked at 30/s each -> %d emitters on, %.1f particles/s", on, rate))
	truthy(on >= 1 and on <= B.MaxWeatherEmitters, string.format("weather cap: %d emitters on for 7 kinds asked (<= %d)", on, B.MaxWeatherEmitters))
	truthy(rate <= B.MaxWeatherRate + 1e-6, string.format("weather cap: %.1f particles/s (<= %d)", rate, B.MaxWeatherRate))
	-- in a camp, the weather hangs behind the back fence, never over the yard
	local ox = Night.pocketOriginX(Config, 3)
	art:setPocket(ox)
	art:updateWeather({ mist = 4 }, Vector3.new(ox + 36, 10, -20), "campBack")
	local host = scratch:FindFirstChild("WeatherHost")
	local zBack = W.ApronDepth + W.CellSize * (W.CageRow + 1)
	truthy(host ~= nil and host.Position.Z - host.Size.Z / 2 > zBack + N.CampMargin,
		string.format("camp weather: its host starts %.1f studs behind the back fence (> the %d-stud margin)",
			host and (host.Position.Z - host.Size.Z / 2 - zBack) or -1, N.CampMargin))
	truthy(host ~= nil and Night.boxClearOfCamp(Config, host.Position.X - ox - host.Size.X / 2, host.Position.X - ox + host.Size.X / 2,
		host.Position.Z - host.Size.Z / 2, host.Position.Z + host.Size.Z / 2), "camp weather: its whole volume is clear of the camp and the camera corridor")
	-- capEmitters (the per-frame emitter cap) knows every weather kind Config names: build one emitter of each, switch
	-- them all on, and with an emitter budget of 0 every one must be switched off (sweep round 1: the Badlands' sand left
	-- out of its list survived, because with the shipped numbers nothing is ever capped)
	local kinds, seen = {}, {}
	for _, list in { N.Home, N.Camp } do
		for _, b in list do
			if b.weather and not seen[b.weather.kind] then seen[b.weather.kind] = true; table.insert(kinds, b.weather.kind) end
		end
	end
	table.sort(kinds)
	for i = 1, #kinds, 2 do
		art:updateWeather({ [kinds[i]] = 5, [kinds[i + 1] or kinds[1]] = 5 }, Vector3.new(0, 20, 0), "camera")
	end
	local made = 0
	for _, d in scratch:GetDescendants() do
		if d.ClassName == "ParticleEmitter" then made += 1; d.Enabled = true; d.Rate = 5 end
	end
	eq(made, #kinds, "the probe built one emitter for each of the " .. #kinds .. " weather kinds Config names")
	local maxBefore = GameConfig.Night.Budget.MaxEmitters
	GameConfig.Night.Budget.MaxEmitters = 0
	art:capEmitters()
	GameConfig.Night.Budget.MaxEmitters = maxBefore
	local still = {}
	for _, d in scratch:GetDescendants() do
		if d.ClassName == "ParticleEmitter" and d.Enabled then table.insert(still, d.Name) end
	end
	eq(#still, 0, "with an emitter budget of 0 the cap switches every weather kind off (" .. table.concat(still, ",") .. ")")
	scratch:Destroy()
end

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end

print(string.format("\nsteal a cryptid budget: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid budget check failed", 0) end
