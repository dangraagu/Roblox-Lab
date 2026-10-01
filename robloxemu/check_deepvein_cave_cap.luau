-- Deep Vein — the client's budgets are CAPPED IN CODE, not only measured. Review 2026-09-30, finding 7.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_cave_cap.luau
--
-- Config.Budget was read at runtime only for the weather (CaveArt caps its emitters and their rate). Nothing
-- stopped a config change from blowing the phone budget: more wall decor per layer, more critters, more
-- weather. complete-game-standard §2: budgets "measured and capped in code". So this file breaks the config
-- ON PURPOSE, in memory and for this run only (ten times the decor, ten times the critters, five times the
-- weather, the weather allowed every emitter there is, one light), and asserts Config.Budget on every frame of 150 fast
-- elevator rides with a hazard every 6-7 s. The things the budget is FOR must still be drawn inside it: the
-- hazard model, its ring and the rest lantern are never crowded out, and some decor and critters still show.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/deep-vein"),
	name = "deep-vein",
	viewport = { 800, 360 },
	touch = true,
})

local UID = 5858
do
	local Config = require("../deep-vein/src/shared/Config")
	local Mine = require("../deep-vein/src/shared/Mine")
	local w = Mine.world(Config, 24, Mine.legacyKey(Config, 24))
	local c = Mine.center(Config)
	local dug = {}
	for y = 1, w.maxLayer do
		dug[Mine.key(c, y, c)] = true
		dug[Mine.key(c + 1, y, c)] = true
	end
	local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
	store:SetAsync("u_" .. UID, { data = {
		cash = 0, totalCash = 0, inventory = {}, pickTier = 5, backpackLevel = 12, lampLevel = 8,
		rebirths = 24, depthLayer = w.maxLayer, bestLayer = w.maxLayer,
		openedBits = Mine.packOpened(Config, w, dug),
		caveKey = Mine.legacyKey(Config, w.rebirths),
	} })
end

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Mine = mod("Mine")
local Budget = Config.Budget

-- THE BROKEN CONFIG (in memory, this run only)
for _, b in Config.Env.Bands do
	if b.decor then b.decor.perLayer = (b.decor.perLayer or 0) * 10 end
	for _, a in b.ambient or {} do a.count *= 10 end
	if b.weather then b.weather.rate *= 5 end
end
Config.Env.DecorLayers = 12
Config.Env.DecorBuildPerFrame = 6
Budget.MaxWeatherEmitters = Budget.MaxEmitters -- the weather may take every emitter there is
Budget.MaxLights = 1 -- a phone that affords one light: a set piece may not take the one the lantern needs
Config.Hazards.IntervalMin = 6
Config.Hazards.IntervalMax = 7

local plr = h:join("Greedy", UID)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(2)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
local shaft = nil
for _, f in h.workspace.Shafts:GetChildren() do
	if f:FindFirstChild("SellPad_" .. UID, true) then shaft = f end
end
local origin = shaft:FindFirstChild("DepthWall_" .. UID).Position

h.game:GetService("RunService"):setIsServer(false)
assert(h:tryRun("client/Hud.client"))
local okCave, errCave = h:tryRun("client/Cave.client")
truthy(okCave, "Cave.client loads with the broken config (" .. tostring(errCave) .. ")")
local folder = h.workspace:FindFirstChild("DeepVeinLocalCave")
local rest = plr.PlayerGui:FindFirstChild("DeepVeinCave").Root:FindFirstChild("RestButton")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")
local UIS = h.game:GetService("UserInputService")

local limits = { parts = Budget.MaxLocalParts, emitters = Budget.MaxEmitters, rate = Budget.MaxEmitterRate,
	lights = Budget.MaxLights, beams = Budget.MaxBeams, trails = Budget.MaxTrails, hazards = Budget.MaxHazards }
local peak = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0, trails = 0, hazards = 0 }
local over = {}
local seenDecor, seenCritters, hazardFrames, hazardDrawn = 0, 0, 0, 0
local function measure(cycle)
	local m = { parts = 0, emitters = 0, rate = 0, lights = 0, beams = 0, trails = 0, hazards = 0 }
	local kinds, decor, critters, ring = {}, 0, 0, false
	for _, d in folder:GetDescendants() do
		local cls = d.ClassName
		if d:IsA("BasePart") then
			m.parts += 1
			local k = string.match(d.Name, "^Hazard_(%a+)$")
			if k then kinds[k] = true end
			if string.match(d.Name, "^Decor_") then decor += 1 end
			if string.match(d.Name, "^Critter_") then critters += 1 end
			if d.Name == "HazardShadow" then ring = true end
		elseif cls == "ParticleEmitter" and d.Enabled then
			m.emitters += 1
			m.rate += d.Rate
		elseif (cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight") and d.Enabled then
			m.lights += 1
		elseif cls == "Beam" and d.Enabled then
			m.beams += 1
		elseif cls == "Trail" and d.Enabled then
			m.trails += 1
		end
	end
	for _ in kinds do m.hazards += 1 end
	seenDecor = math.max(seenDecor, decor)
	seenCritters = math.max(seenCritters, critters)
	if ring then
		hazardFrames += 1
		if next(kinds) ~= nil then hazardDrawn += 1 end
	end
	for k, v in m do
		if v > peak[k] then peak[k] = v end
		-- (1e-6: particles/s are summed floats; 44 + 16 can come to 60.00000000000001)
		if v > limits[k] + 1e-6 and over[k] == nil then over[k] = string.format("%s = %s at cycle %d", k, tostring(v), cycle) end
	end
end

local swingAcc = 0
local function frame(dt, cycle)
	swingAcc += dt
	if swingAcc >= 1 then
		swingAcc = 0
		UIS.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
	end
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 8, 14), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	if hum.PlatformStand then hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
	measure(cycle)
end

local seed = 777
local function rnd()
	seed = (1103515245 * seed + 12345) % 2147483648
	return seed / 2147483648
end
local c = Mine.center(Config)
for cycle = 1, 150 do
	local y = math.floor(rnd() * 313)
	local lp = Mine.localPos(Config, c, math.max(y, 0), c)
	hrp.CFrame = CFrame.new(origin.X + lp.x, Mine.floorY(Config, y) + Config.Env.RootAboveFloor, origin.Z + lp.z)
	local stay = if rnd() < 0.4 then 0.3 else 5
	for _ = 1, math.floor(stay * 30 + 0.5) do frame(1 / 30, cycle) end
end
-- …and the rest lantern, in the busiest place there is: the core, everything at its cap
do
	local lp = Mine.localPos(Config, c, 305, c)
	hrp.CFrame = CFrame.new(origin.X + lp.x, Mine.floorY(Config, 305) + Config.Env.RootAboveFloor, origin.Z + lp.z)
	Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 600, 700
	for _ = 1, 30 * 8 do frame(1 / 30, 151) end
	swingAcc = -1e9 -- stop swinging
	for _ = 1, 30 * 3 do frame(1 / 30, 151) end
	rest.Activated:Fire()
	for _ = 1, 30 do frame(1 / 30, 151) end
	truthy(folder:FindFirstChild("RestLantern") ~= nil, "at the busiest place, everything at its cap, the rest lantern is still set down")
end

--======================================================================= the hazard cap is in CaveArt, not in its caller
-- Budget.MaxHazards is 1. Cave.client hides every plan's model when the plan ends, so the rides above never show two
-- at once whatever CaveArt does: mutation sweep 6's P4 (showHazard no longer puts another kind away) survived every
-- gate. So this asks CaveArt itself, through a caller that NEVER hides: each new kind shown puts the last one away.
local probeShown = {}
do
	local CaveArtM, HazardsM, EnvBandsM, StrataM = mod("CaveArt"), mod("Hazards"), mod("EnvBands"), mod("Strata")
	local probeFolder = Instance.new("Folder")
	probeFolder.Name = "HazardCapProbe"
	probeFolder.Parent = h.workspace
	local pr = 4242
	local function prand()
		pr = (1103515245 * pr + 12345) % 2147483648
		return pr / 2147483648
	end
	local probe = CaveArtM.new(probeFolder, prand, Config, EnvBandsM, StrataM, Mine)
	probe:setShaft(origin, origin.Y - 400)
	local function kindsInFolder()
		local seen, n = {}, 0
		for _, d in probeFolder:GetDescendants() do
			local k = if d:IsA("BasePart") then string.match(d.Name, "^Hazard_(%a+)$") else nil
			if k and not seen[k] then
				seen[k] = true
				n += 1
			end
		end
		return n
	end
	local aim = { x = origin.X, y = origin.Y - 60, z = origin.Z }
	for i, kind in { "rock", "crystal", "steam", "shard", "magma" } do
		local plan = HazardsM.plan(Config.Hazards, kind, aim, 0, prand)
		plan.t = 0.5
		probe:showHazard(plan, HazardsM.positionAt(plan, plan.t), i, HazardsM.zone(plan, Config.Hazards.PlayerRadius), aim.y - 3)
		probeShown[i] = kindsInFolder()
	end
	probeFolder:Destroy()
end
print("  a caller that never hides, five kinds in turn: hazard models in the folder after each = " .. table.concat(probeShown, ", "))
eq(probeShown[1], 1, "CONTROL: one hazard shown is one hazard model in the folder")
eq(math.max(probeShown[2], probeShown[3], probeShown[4], probeShown[5]), 1,
	"a second kind shown while the first was never hidden still leaves one model: CaveArt caps MaxHazards itself")

print(string.format("  150 rides on a config broken on purpose: peak parts %d, emitters %d, particles/s %.1f, lights %d, beams %d, trails %d, hazards %d",
	peak.parts, peak.emitters, peak.rate, peak.lights, peak.beams, peak.trails, peak.hazards))
print(string.format("  most decor parts at once %d, most critter parts %d; a hazard's ring on %d frames, its model drawn on %d",
	seenDecor, seenCritters, hazardFrames, hazardDrawn))
for _, k in { "parts", "emitters", "rate", "lights", "beams", "trails", "hazards" } do
	eq(over[k], nil, "the " .. k .. " budget held on every frame, whatever the config asks for")
end
truthy(hazardFrames >= 100, "set-up: hazards came during the run (" .. hazardFrames .. " frames with a ring)")
eq(hazardDrawn, hazardFrames, "the budget never crowds out a hazard's model: every frame with a ring shows the thing it warns of")
truthy(seenDecor >= 20 and seenCritters >= 10, "the capped config still dresses the cave (decor and critters are cut to fit, not switched off)")

print("")
for _, wn in h.warnings do print("  [warn] " .. wn) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("deep vein cave cap: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein cave cap check failed", 0)
end
