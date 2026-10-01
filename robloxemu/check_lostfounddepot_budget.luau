-- Lost & Found Depot — the phone budget is capped IN CODE, not only measured. Run:
--   py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--   luau check_lostfounddepot_budget.luau 2>&1
--
-- REVIEW-3 finding 5: outside Config nothing in src/ read MaxLocalParts, MaxLights, MaxBeams, MaxTrails,
-- MaxEmitters or MaxHazards; only check_lostfounddepot_wings noticed a retune that broke them (the train wing's
-- pigeons 8 -> 40 built 228 local parts against a budget of 220). docs/complete-game-standard.md §2 asks for
-- budgets "measured and capped in code".
--
-- This check loads the REAL client with a config that asks for far more than the budget (IN MEMORY, before the
-- client loads; src/ is untouched): 40 gulls over the city, 40 pigeons over the train station, 60 balloons over the park,
-- 20 satellites over the station, 12 comets and 20 satellites beyond the galaxy, weather at 50 particles/s,
-- and a hazard every 3-4 s of running clock. It then holds every wing (a hazard wing until both its kinds have
-- flown) and every seam, and makes 160 random career jumps, and on EVERY frame counts what the wings have in
-- workspace.DepotWings: parts, enabled emitters and their summed rate, beams, trails, lights and hazards, and
-- the hazard's own parts and lights against Budget.HazardReserve. Every count must stay inside
-- Config.Budget; the hazards must keep coming (their room is reserved); and every wing must still show its own
-- roof and landmark (life gives way, never the wing).
--
-- Headless limits: nothing renders; the census is of Instances, not frame time.

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-budget", viewport = { 1280, 720 }, touch = false })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") and h.modules[key] == nil then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
local realRandom = Random
local unseeded = 0
Random = { new = function(seed)
	if seed == nil then unseeded += 1; return realRandom.new(4242 + unseeded * 7919) end
	return realRandom.new(seed)
end }

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local UID = 7103
h.services.DataStoreService:GetDataStore("LostFoundDepot_v1"):SetAsync("u_" .. UID, {
	data = { v = 1, cash = 900, cartLevel = 3, shoesLevel = 3, shifts = 12, perfects = 6, backlog = 350,
		bestPerfectSeconds = 80, endingSeen = false, redeemed = {} },
})
assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Budget = Config.Budget
local bands = Config.Env.Bands

-- The over-budget config, in memory, before the client loads.
local function band(id)
	for _, b in bands do if b.id == id then return b end end
	error("no band " .. id)
end
local function ambient(id, kind, count)
	for _, a in band(id).ambient do
		if a.kind == kind then a.count = count; return end
	end
	error("no " .. kind .. " in " .. id)
end
ambient("city", "gull", 40)
ambient("train", "pigeon", 40)
ambient("park", "balloon", 60)
ambient("station", "satellite", 20)
ambient("galaxy", "comet", 12)
ambient("galaxy", "satellite", 20)
band("park").weather.rate = 50
band("station").weather.rate = 50
Config.Hazards.IntervalMin = 3
Config.Hazards.IntervalMax = 4

local plr = h:join("Budgeter", UID)
h:advance(0.2)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
assert(h:tryRun("client/Hud.client"))
local okW, errW = h:tryRun("client/Wings.client")
truthy(okW, "Wings.client loads (" .. tostring(errW) .. ")")
local StateEvent = RS:FindFirstChild("DepotRemotes"):FindFirstChild("State")
local function state() local s = StateEvent:sentTo(plr); return s[#s] and s[#s].args[1] or nil end
StateEvent:FireClient(plr, state())
local folder = h.workspace:FindFirstChild("DepotWings")
local bay = plr.RespawnLocation.Parent
local OX = bay:FindFirstChild("BayPad").Position.X
local cam = h.workspace.CurrentCamera

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in t do o[k] = copy(v) end
	return o
end
local base = copy(state())
local function payload(shifts, running, cleared)
	local p = copy(base)
	p.shifts = shifts
	p.shift = copy(base.shift)
	p.shift.state = if running then "RUNNING" else "ARMED"
	p.shift.cleared = cleared or 0
	p.shift.total = 30
	p.shift.carried = {}
	p.shift.summary = nil
	return p
end

local LIMIT = { parts = Budget.MaxLocalParts, emitters = Budget.MaxEmitters, rate = Budget.MaxEmitterRate,
	beams = Budget.MaxBeams, trails = Budget.MaxTrails, lights = Budget.MaxLights, hazards = Budget.MaxHazards }
local peak = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0, hazards = 0 }
local over = {}
local frames, hazardsSeen, wasHz, hazardFrames = 0, 0, false, 0
local warnedUndrawn = 0 -- frames with the hazard warning on screen but no hazard model drawn
local warnPanel = plr.PlayerGui:FindFirstChild("DepotWings"):FindFirstChild("Root"):FindFirstChild("WarningPanel")
local critterParts = 0
local hazardPeak = { parts = 0, lights = 0 } -- the hazard's own model, lane and ring, against Budget.HazardReserve
local kindsSeen = {}
local CRITTER = { Pigeon = true, Gull = true, Balloon = true, Satellite = true, Astronaut = true, Comet = true, Airliner = true }
local function census(label)
	local m = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0, hazards = 0 }
	local kinds, names = {}, {}
	local crit = 0
	local hz = { parts = 0, lights = 0 }
	for _, d in folder:GetDescendants() do
		local cls = d.ClassName
		if d:IsA("BasePart") then
			m.parts += 1
			names[d.Name] = true
			if CRITTER[d.Name] then crit += 1 end
			local k = string.match(d.Name, "^Hazard_(%a+)$")
			if k then kinds[k] = true; kindsSeen[k] = true end
			if k or d.Name == "Lane" or d.Name == "Ring" then hz.parts += 1 end
		elseif cls == "PointLight" and d.Parent and string.match(d.Parent.Name, "^Hazard_") then
			hz.lights += 1
			if d.Enabled then m.lights += 1 end
		elseif cls == "ParticleEmitter" and d.Enabled then
			m.emitters += 1
			m.rate += d.Rate
		elseif cls == "Beam" and d.Enabled then
			m.beams += 1
		elseif cls == "Trail" and d.Enabled then
			m.trails += 1
		elseif cls == "PointLight" and d.Enabled then
			m.lights += 1
		end
	end
	for _ in kinds do m.hazards += 1 end
	for k, v in m do
		if v > peak[k] then peak[k] = v end
		if v > LIMIT[k] + 1e-6 and over[k] == nil then over[k] = string.format("%s = %s (%s)", k, tostring(v), label) end
	end
	critterParts = math.max(critterParts, crit)
	hazardPeak.parts = math.max(hazardPeak.parts, hz.parts)
	hazardPeak.lights = math.max(hazardPeak.lights, hz.lights)
	return m, names
end

local pinned = nil
local simTime = 0
local function frame(dt, label)
	local p = hrp.Position
	local look = Vector3.new(math.sin(simTime * 0.7), 0, -math.cos(simTime * 0.7))
	cam.CFrame = CFrame.new(p - look * 14 + Vector3.new(0, 8, 0), p)
	hum.MoveDirection = if math.floor(simTime) % 7 == 0 then Vector3.new(0.3, 0, 0) else Vector3.new(0, 0, 0)
	if pinned then StateEvent:FireClient(plr, pinned) end
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	simTime += dt
	frames += 1
	local m, names = census(label)
	local hz = m.hazards > 0
	if hz then hazardFrames += 1 end
	if warnPanel.Visible and not hz then warnedUndrawn += 1 end
	if hz and not wasHz then hazardsSeen += 1 end
	wasHz = hz
	return m, names
end

hrp.CFrame = CFrame.new(OX, 3, 0)

--======================================================================= every wing, held: the wing itself still shows

local LANDMARKS = {
	city = { "CityRoof", "CitySkyline" }, airport = { "AirportRoof", "Airfield" }, train = { "TrainShed", "Viaduct" },
	park = { "ParkLights", "ParkRides" }, station = { "StationDome", "EarthView" }, galaxy = { "StationDome", "GalaxyView" },
}
local missing = {}
for _, b in bands do
	pinned = payload(b.from, true, 10)
	local names
	local function allFlown()
		for _, k in b.hazards or {} do
			if not kindsSeen[k] then return false end
		end
		return true
	end
	-- 10 s, and a hazard wing until each of its two kinds has flown (at most 180 s)
	for f = 1, 180 * 30 do
		local _, n = frame(1 / 30, b.id)
		names = n
		if f >= 10 * 30 and allFlown() then break end
	end
	for _, part in LANDMARKS[b.id] do
		if not names[part] then table.insert(missing, b.id .. ":" .. part) end
	end
end
print(string.format("  every wing held 10 s (a hazard wing until both its kinds flew) with the over-budget config: peak %d parts, %d critter parts, %d hazards seen",
	peak.parts, critterParts, hazardsSeen))
eq(#missing, 0, "every wing still shows its own roof and landmark with the over-budget life (" .. table.concat(missing, ", ") .. ")")

--======================================================================= every seam, both wings live

for i = 2, #bands do
	pinned = payload(bands[i].from - 1, true, 25) -- the last third of the shift before the wing: both blend
	for _ = 1, 8 * 30 do frame(1 / 30, "seam " .. bands[i - 1].id .. ">" .. bands[i].id) end
end

--======================================================================= 160 random career jumps

do
	local seed = 20260930
	local function rnd()
		seed = (1103515245 * seed + 12345) % 2147483648
		return seed / 2147483648
	end
	for cycle = 1, 160 do
		local shifts = math.floor(rnd() * 40)
		local running = rnd() < 0.8
		pinned = payload(shifts, running, if running then math.floor(rnd() * 30) else 0)
		local stay = if rnd() < 0.5 then 0.2 else 4
		for _ = 1, math.floor(stay * 30 + 0.5) do frame(1 / 30, "jump " .. cycle) end
	end
end

print(string.format("  %d frames: peak parts %d / %d, emitters %d / %d (%.1f / %d particles/s), beams %d / %d, trails %d / %d, lights %d / %d, hazards %d / %d",
	frames, peak.parts, LIMIT.parts, peak.emitters, LIMIT.emitters, peak.rate, LIMIT.rate, peak.beams, LIMIT.beams,
	peak.trails, LIMIT.trails, peak.lights, LIMIT.lights, peak.hazards, LIMIT.hazards))
print(string.format("  hazards: %d launched, drawn on %d frames", hazardsSeen, hazardFrames))
for _, k in { "parts", "emitters", "rate", "beams", "trails", "lights", "hazards" } do
	eq(over[k], nil, "the " .. k .. " budget held on every frame, capped by the client itself")
end
do
	local seen = {}
	for k in kindsSeen do table.insert(seen, k) end
	table.sort(seen)
	local all = 0
	for _ in Config.Hazards.Kinds do all += 1 end
	print(string.format("  the hazard's own parts at most %d (reserve %d), lights %d (reserve %d); kinds drawn: %s",
		hazardPeak.parts, Budget.HazardReserve.parts, hazardPeak.lights, Budget.HazardReserve.lights, table.concat(seen, " ")))
	eq(#seen, all, "every hazard kind was drawn at least once")
	truthy(hazardPeak.parts <= Budget.HazardReserve.parts, "every hazard (model, lane and ring) fits the parts it has reserved")
	truthy(hazardPeak.lights <= Budget.HazardReserve.lights, "and the lights it has reserved")
end
truthy(critterParts >= 60, "set-up: the over-budget life really crowded in (" .. critterParts .. " critter parts at once)")
eq(warnedUndrawn, 0, "a hazard that is warned of is always drawn, however full the budget (frames warned but not drawn)")
truthy(hazardsSeen >= 30, "hazards keep coming under a full budget: their room is reserved (" .. hazardsSeen .. ")")

print("")
local wingWarnings = 0
for _, w in h.warnings do
	print("warning: " .. w)
	wingWarnings += 1
end
eq(wingWarnings, 0, "no warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("lost-found-depot budget: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("lost-found-depot budget check failed", 0)
end
