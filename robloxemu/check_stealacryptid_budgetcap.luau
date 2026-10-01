-- Steal a Cryptid - the night's budget is CAPPED IN CODE, not only measured. Real server, HUD and night client.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--       luau check_stealacryptid_budgetcap.luau 2>&1
--
-- Second review of the night, 2026-09-30, finding 5: nothing in src/ read MaxLocalParts, MaxEmitters,
-- MaxEmitterRate, MaxBeams, MaxTrails, MaxLights or MaxHazards; only the weather and the habitats' particles were
-- capped, and beams sat at 8 of 8. check_stealacryptid_budget proves the SHIPPED scene fits. This file proves the
-- game itself holds any budget: it lowers Config.Night.Budget in memory (the bundle's own module, before the
-- client starts) far below what the heaviest scene asks for, drives that scene (nine habitats, rapid hazards,
-- the strange -> mythic seam, the campfire, a camp and home), and on EVERY frame:
--   B1 every count stays within the lowered budget (parts, beams, trails, lights, emitters, particles/s, hazards);
--   B2 the telegraph is never what gives way: while the chip warns, the hazard and its red ring are drawn;
--   B3 nor the rest campfire: while resting by the button, it burns;
--   B4 the cap trims, it does not wipe: the seam still shows most of its part budget and some beams;
--   B5 the always-shown pieces (a hazard, its lane and ring, the campfire, the weather host) fit the
--      Budget.Reserve the cap keeps for them.
--   B6 the gate's books balance: after a road that arrives late (setHome rebuilds the home pieces) what the gate
--      counts as used is exactly the cost of what is shown (a destroyed piece gives its budget back).

local Harness = require("./emu/harness")
local Config = require("../steal-a-cryptid/src/shared/Config")
local bundle = require("./build/steal-a-cryptid")

local h = Harness.new({ bundle = bundle, name = "steal-a-cryptid-budgetcap", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local N = Config.Night
local W = Config.World
local NOW = os.time()
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local ME = 6607
do
	local fill = { "jackalope", "hodag", "chupacabra", "dogman", "mothman", "nessie", "jerseydevil", "dogman" }
	local cages = {}
	for i = 1, 9 do cages[i] = { sp = fill[i] or "", jar = 0 } end
	store:SetAsync("u_" .. ME, { data = { v = 1, essence = 11000000, savedAt = NOW, cagesUnlocked = 9, tutorial = 4, cages = cages,
		traps = {}, heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 },
		journal = { "jackalope", "hodag", "chupacabra", "dogman", "jerseydevil", "mothman", "nessie" },
		stats = { steals = 0, caught = 0, poachersCaught = 0 } } })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local GameConfig = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
GameConfig.Night.Hazards.IntervalMin, GameConfig.Night.Hazards.IntervalMax = 0.05, 0.05
GameConfig.Poacher.FirstAfterSeconds = 1e6
-- the lowered budget, in memory only: well under what the shipped scene draws (parts 146-150, beams 8,
-- trails 4, emitters 3, particles 17.9/s), and still above what the always-shown pieces reserve
local LOW = { MaxLocalParts = 90, MaxBeams = 5, MaxTrails = 2, MaxLights = 2, MaxEmitters = 2, MaxEmitterRate = 12, MaxHazards = 1 }
local GB = GameConfig.Night.Budget
for k, v in LOW do GB[k] = v end
local RES = N.Budget.Reserve
truthy(type(RES) == "table", "Config.Night.Budget.Reserve exists (what the cap keeps for the always-shown pieces)")
RES = RES or {}

local remotes = h.ReplicatedStorage:FindFirstChild("CryptidRemotes")
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("Capped", ME)
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
local over = {}
local where = "?"
local walker = nil
local warnFrames, telegraphMissing, restFrames, fireMissing = 0, 0, 0, 0
local seamParts, seamBeams = 0, 0
local maxHazardParts, maxLaneParts, maxFireParts, maxHostParts = 0, 0, 0, 0

local function measure()
	local parts, emitters, rate, beams, trails, lights = 0, 0, 0, 0, 0, 0
	local kinds, nk = {}, 0
	local hz, lane, fire, host, ring = 0, 0, 0, 0, false
	for _, d in folder:GetDescendants() do
		local cls = d.ClassName
		if cls == "Part" or cls == "WedgePart" then
			parts += 1
			local k = string.match(d.Name, "^Hazard_(%a+)_")
			if k then
				hz += 1
				if not kinds[k] then kinds[k] = true; nk += 1 end
			end
			if d.Name == "HazardLane" or d.Name == "HazardRing" then lane += 1 end
			if d.Name == "HazardRing" then ring = true end
			if string.sub(d.Name, 1, 9) == "Campfire_" then fire += 1 end
			if d.Name == "WeatherHost" then host += 1 end
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
	local limits = { parts = LOW.MaxLocalParts, emitters = LOW.MaxEmitters, rate = LOW.MaxEmitterRate, beams = LOW.MaxBeams,
		trails = LOW.MaxTrails, lights = LOW.MaxLights, hazards = LOW.MaxHazards }
	for k, v in m do
		if v > peak[k] then peak[k] = v end
		if v > limits[k] + 1e-6 and over[k] == nil then over[k] = string.format("%s %s > %s at %s", k, tostring(v), tostring(limits[k]), where) end
	end
	maxHazardParts = math.max(maxHazardParts, hz)
	maxLaneParts = math.max(maxLaneParts, lane)
	maxFireParts = math.max(maxFireParts, fire)
	maxHostParts = math.max(maxHostParts, host)
	if bus.StatusKind.Value == "danger" then
		warnFrames += 1
		if hz == 0 or not ring then telegraphMissing += 1 end
	end
	if bus.RestLabel.Value == N.Text.RestingButton and bus.Status.Value == N.Text.Resting then
		restFrames += 1
		local flameOn = false
		for _, d in folder:GetDescendants() do
			if d.Name == "CampfireFx" and d.Enabled then flameOn = true end
		end
		if fire < 3 or not flameOn then fireMissing += 1 end
	end
	if string.find(where, "seam", 1, true) then
		seamParts = math.max(seamParts, parts)
		seamBeams = math.max(seamBeams, beams)
	end
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

where = "strange, eight habitats, hazards"
walkAt(36, 4)
run(25)
where = "seam strange>mythic, hazards"
walker = nil
hrp.CFrame = CFrame.new(apron(W.Apron.P3.x, W.Apron.P3.z - 4))
run(12, flying)
lair.Pedestals.Pedestal_3.Buy.Triggered:Fire(plr)
run(0.1)
eq(st().rank, 4, "the Mythic raised the rank to 4 (the seam with the most beams)")
walkAt(W.Apron.P3.x, W.Apron.P3.z - 6)
run(6)
where = "mythic, nine habitats, hazards"
walkAt(36, 4)
run(20)

-- rest by the campfire (queued if a hazard is inbound: step out of its ring, then stand still). The steps can
-- wake a rest that began during them (the sky cleared mid-dodge), so press again until it holds.
do
	where = "resting by the campfire"
	walker = nil
	hrp.CFrame = CFrame.new(apron(36, 4))
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local function resting() return bus.RestLabel.Value == N.Text.RestingButton end
	for _ = 1, 6 do
		if resting() then break end
		if bus.RestLabel.Value == N.Text.RestButton then
			hudRoot.Toggles.RestToggle.Activated:Fire()
			run(0.1)
		end
		if not resting() then
			run(6, function() return string.sub(bus.Status.Value, 1, 5) == "Move!" or resting() end)
			if not resting() and string.sub(bus.Status.Value, 1, 5) == "Move!" then
				run(0.4)
				for _ = 1, 12 do
					if resting() then break end
					hrp.CFrame = CFrame.new(hrp.Position + Vector3.new(16 / 30, 0, 0))
					hum.MoveDirection = Vector3.new(1, 0, 0)
					frame(1 / 30)
				end
				hum.MoveDirection = Vector3.new(0, 0, 0)
			end
			run(8, resting)
		end
	end
	eq(bus.RestLabel.Value, N.Text.RestingButton, "resting by the campfire")
	run(10)
	hudRoot.Toggles.RestToggle.Activated:Fire()
	run(0.2)
end

-- a camp (a hunt needs a free cage: release one through the real prompt) and home again
do
	walker = nil
	hrp.CFrame = CFrame.new(apron(36, 80))
	hum.MoveDirection = Vector3.new(0, 0, 0)
	local rel = lair.Cages:FindFirstChild("Cage_5"):FindFirstChild("Release")
	rel.PromptButtonHoldBegan:Fire(plr)
	h:advance(Config.Economy.ReleaseHoldSeconds + 0.05)
	rel.Triggered:Fire(plr)
	run(1.5)
	where = "to camp 4"
	hrp.CFrame = CFrame.new(apron(W.Apron.Board.x, W.Apron.Board.z - 4))
	hum.MoveDirection = Vector3.new(1, 0, 0)
	run(0.5)
	remotes.Hunt:simulateFireServer(plr, 4)
	h:advance(0.05)
	where = "camp 4"
	run(8)
	remotes.LeaveCamp:simulateFireServer(plr)
	h:advance(0.05)
	where = "home after camp 4, hazards"
	walkAt(36, 4)
	run(N.Hazards.SettleSeconds + 8)
end

print("  peaks under the LOWERED budget, every frame:")
for _, k in { "parts", "emitters", "rate", "beams", "trails", "lights", "hazards" } do
	local lim = ({ parts = LOW.MaxLocalParts, emitters = LOW.MaxEmitters, rate = LOW.MaxEmitterRate, beams = LOW.MaxBeams, trails = LOW.MaxTrails, lights = LOW.MaxLights, hazards = LOW.MaxHazards })[k]
	print(string.format("    %-9s %6.1f of %s", k, peak[k], tostring(lim)))
end
print(string.format("  warning frames %d (telegraph missing on %d); resting frames %d (campfire missing on %d); the seam showed %d parts and %d beams",
	warnFrames, telegraphMissing, restFrames, fireMissing, seamParts, seamBeams))
print(string.format("  always-shown pieces at their largest: a hazard %d parts, its lane and ring %d, the campfire %d, the weather host %d (Reserve.parts %s)",
	maxHazardParts, maxLaneParts, maxFireParts, maxHostParts, tostring(RES.parts)))
for k, v in over do truthy(false, "B1: over the lowered budget: " .. v) end
truthy(next(over) == nil, "B1: every frame within the lowered budget (parts, beams, trails, lights, emitters, particles/s, hazards)")
truthy(warnFrames > 30 * 20, "B2: hazards warned for more than 20 s of it (" .. warnFrames .. " frames)")
eq(telegraphMissing, 0, "B2: while the chip warns, the hazard and its red ring are always drawn")
truthy(restFrames > 30 * 8, "B3: rested by the campfire for more than 8 s (" .. restFrames .. " frames)")
eq(fireMissing, 0, "B3: while resting by the button, the campfire and its flames are always there")
truthy(seamParts >= math.floor(0.75 * LOW.MaxLocalParts), string.format("B4: the cap trims, it does not wipe: the seam still drew %d of %d parts", seamParts, LOW.MaxLocalParts))
truthy(seamBeams >= 1, "B4: and some of its beams (" .. seamBeams .. ")")
truthy(type(RES.parts) == "number" and maxHazardParts + maxLaneParts + maxFireParts + maxHostParts <= RES.parts,
	"B5: the always-shown pieces fit Budget.Reserve.parts")

-- B6: the gate's books balance. The game's own NightArt (the bundle's module) on a scratch folder, as a client
-- that starts before the road replicates: every Mythic Night home piece shown round the origin, then the road
-- arrives (setHome destroys and rebuilds the home pieces), then shown again. What the gate counts as used must be
-- exactly the cost of what is shown: a destroyed piece that kept its budget would starve the sky for the session.
do
	local RS = h.ReplicatedStorage
	local NightArt = h:_require(RS:FindFirstChild("NightArt"))
	local scratch = Instance.new("Folder")
	scratch.Name = "GateBooksProbe"
	scratch.Parent = h.workspace
	local k = 0
	local art = NightArt.new(scratch, function() k += 1; return (k % 89) / 89 end, GameConfig,
		h:_require(RS:FindFirstChild("EnvBands")), h:_require(RS:FindFirstChild("Night")))
	local ids = {}
	for _, b in N.Home do for _, id in b.pieces do ids[id] = true end end
	local cam0 = Vector3.new(0, 20, -40)
	for id in ids do art:updatePiece(id, 1, cam0, 0) end
	local ground = h.workspace.Road.Ground
	art:setHome({ cx = ground.Position.X, cz = ground.Position.Z, sx = ground.Size.X, sz = ground.Size.Z }, {})
	for t = 1, 3 do
		for id in ids do art:updatePiece(id, 1, cam0, t / 30) end
	end
	local shown = { parts = 0, beams = 0, trails = 0, lights = 0 }
	for _, item in art.pieces do
		if item.shown and item.gate then
			shown.parts += #item.entries
			shown.beams += #item.beams
			shown.trails += #item.trails
			shown.lights += #item.lights
		end
	end
	local used = art.gate and art.gate.state and art.gate.state.used or {}
	print(string.format("  B6: after a late road the gate counts %s parts, %s beams used; the shown pieces cost %d parts, %d beams",
		tostring(used.parts), tostring(used.beams), shown.parts, shown.beams))
	truthy(used.parts == shown.parts and used.beams == shown.beams and used.trails == shown.trails and used.lights == shown.lights,
		"B6: the gate's books balance after the road arrives late (used = the cost of what is shown)")
	scratch:Destroy()
end

for _, e in h:errors() do truthy(false, "scheduler error: " .. tostring(e)) end
for _, w in h.warnings do
	if string.find(w, "Night", 1, true) then truthy(false, "the client warned: " .. w) end
end
print(string.format("\nsteal a cryptid budgetcap: %d passed, %d failed", passed, failed))
if failed > 0 then error("steal a cryptid budgetcap check failed", 0) end
