-- +1 Jump Every Step — the client's particle and part budgets hold under fast altitude changes, and the
-- pools stay bounded over a long session. Run: luau check_plus1jump_budget.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- Review 2026-09-17, round 2 (finding 4, low): check_plus1_sky measures the budgets at the middle of every
-- band and every seam after the sky has settled. Nothing enforced the emitter budget in code: weather rates
-- blend by band weight on a half-life, so rapid teleports between far bands (every 3 s, 400 times, with a
-- hazard every 6-7 s) left 5 weather emitters switched on at once against Config.Budget.MaxEmitters = 4,
-- and EYECANDY.md said "at most 2". Normal play crosses at most two bands at a time (rebirth, rescue, join),
-- but a dev teleport or the shot list's PivotTo hops can do this.
--
-- This file is the reviewer's stress run with the budgets asserted on EVERY frame, not only at the end:
-- enabled weather emitters <= Config.Budget.MaxWeatherEmitters (<= MaxEmitters), summed rate <=
-- MaxEmitterRate, parts, beams, trails and lights within budget. The teleports come from a seeded generator;
-- the hazards from the emulator's unseeded Random, so hazard timing, and which kind a band launches, vary run
-- to run. So "the pools are bounded" is not "no new instance after cycle N" (a kind can be launched for the
-- first time late, and its one model is built then): every instance first built after cycle 200 must belong
-- to a hazard model whose kind had never flown before, and each kind's model is built exactly once.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
assert(h:tryRun("server/Main.server"))
local Config = mod("Config")
local Progression = mod("Progression")
local B = Config.Budget
Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = 6, 7 -- in-memory, this run only
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Climber", 4242)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(1, 0, 0)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")
local folder = h.workspace:FindFirstChild("Plus1LocalSky")
local cam = h.workspace.CurrentCamera
local RunService = h.game:GetService("RunService")

local seen = setmetatable({}, { __mode = "k" })
local unique = 0
local cycleNow = 0
local lateNames = {} -- folder-child name of every instance first built after cycle 200
local kindFirstCycle = {} -- hazard kind -> the cycle its model was first seen
local kindInstances = {} -- hazard kind -> unique instances ever seen in its model
local kindInstancesAtFirst = {} -- hazard kind -> the same, at the end of the cycle it first appeared
local function topName(d)
	local x = d
	while x.Parent ~= nil and x.Parent ~= folder do x = x.Parent end
	return x.Name
end
local peak = { parts = 0, emit = 0, rate = 0, beams = 0, trails = 0, lights = 0 }
local where = {}
local label = ""
local function census()
	local parts, emit, rate, beams, trails, lights = 0, 0, 0, 0, 0, 0
	for _, d in folder:GetDescendants() do
		if not seen[d] then
			seen[d] = true
			unique += 1
			local top = topName(d)
			local kind = string.match(top, "^Hazard_(%a+)_")
			if kind then
				kindFirstCycle[kind] = kindFirstCycle[kind] or cycleNow
				kindInstances[kind] = (kindInstances[kind] or 0) + 1
			end
			if cycleNow > 200 then table.insert(lateNames, { name = top, kind = kind }) end
		end
		local c = d.ClassName
		if c == "Part" or c == "WedgePart" then parts += 1
		elseif c == "ParticleEmitter" and d.Enabled then emit += 1; rate += d.Rate or 0
		elseif c == "Beam" and d.Enabled then beams += 1
		elseif c == "Trail" and d.Enabled then trails += 1
		elseif c == "PointLight" and d.Enabled then lights += 1 end
	end
	-- the suit light lives on the character, not in the folder
	for _, d in char:GetDescendants() do
		if d.ClassName == "PointLight" and d.Enabled and d.Brightness > 0 then lights += 1 end
	end
	for k, v in { parts = parts, emit = emit, rate = rate, beams = beams, trails = trails, lights = lights } do
		if v > peak[k] then
			peak[k] = v
			where[k] = label
		end
	end
end

local s = 4242
local function rand() s = (1664525 * s + 1013904223) % 4294967296; return s / 4294967296 end
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 24), hrp.Position)
	RunService.RenderStepped:Fire(dt)
	h:advance(dt)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hum.PlatformStand = false
	census()
end

local p = 0
local uniqueAt = {}
for cycle = 1, 400 do
	cycleNow = cycle
	-- the reviewer's sequence exactly: a target drawn first, then the coin
	local target = rand() * 300
	if rand() < 0.5 then
		local from = p
		p = target
		label = string.format("cycle %d: teleport tiers climbed %.0f -> %.0f", cycle, from, p)
		hrp.CFrame = CFrame.new(rand() * 200 - 100, Progression.yAtProgress(p, Config.Tower) + 3.5, rand() * 3000)
		for _ = 1, 30 do frame(0.1) end
	else
		label = string.format("cycle %d: climbing from %.0f", cycle, p)
		for _ = 1, 60 do
			p += 0.05
			hrp.CFrame = CFrame.new(hrp.Position.X + 3, Progression.yAtProgress(p, Config.Tower) + 3.5, hrp.Position.Z + 5)
			frame(0.1)
		end
	end
	if cycle % 100 == 0 then uniqueAt[cycle] = unique end
	for kind, first in kindFirstCycle do
		if first == cycle then kindInstancesAtFirst[kind] = kindInstances[kind] end
	end
end

print(string.format("  peaks over 400 cycles: parts %d (%s)", peak.parts, tostring(where.parts)))
print(string.format("                         emitters %d (%s)", peak.emit, tostring(where.emit)))
print(string.format("                         rate %.0f/s, beams %d, trails %d, lights %d", peak.rate, peak.beams, peak.trails, peak.lights))
print(string.format("  unique instances ever built: %d at cycle 100, %d at 200, %d at 300, %d at 400",
	uniqueAt[100] or -1, uniqueAt[200] or -1, uniqueAt[300] or -1, uniqueAt[400] or -1))

truthy(type(B.MaxWeatherEmitters) == "number", "Config.Budget.MaxWeatherEmitters is set")
-- EYECANDY.md promises at most 2 weather emitters; the config field, once it exists, must agree
local maxWeather = math.min(B.MaxWeatherEmitters or 2, B.MaxEmitters)
truthy(peak.emit <= maxWeather, string.format("enabled particle emitters never exceed %d on any frame (peak %d at %s)", maxWeather, peak.emit, tostring(where.emit)))
truthy(peak.rate <= B.MaxEmitterRate + 1e-6, string.format("summed particle rate never exceeds %d/s (peak %.1f)", B.MaxEmitterRate, peak.rate))
truthy(peak.parts <= B.MaxLocalParts, string.format("local parts never exceed %d (peak %d at %s)", B.MaxLocalParts, peak.parts, tostring(where.parts)))
truthy(peak.beams <= B.MaxBeams, string.format("beams never exceed %d (peak %d)", B.MaxBeams, peak.beams))
truthy(peak.trails <= B.MaxTrails, string.format("trails never exceed %d (peak %d)", B.MaxTrails, peak.trails))
truthy(peak.lights <= B.MaxLights, string.format("point lights never exceed %d (peak %d)", B.MaxLights, peak.lights))
do
	local stray, strayExample = 0, nil
	for _, e in lateNames do
		if not (e.kind and kindFirstCycle[e.kind] > 200) then
			stray += 1
			strayExample = strayExample or e.name
		end
	end
	eq(stray, 0, "the pools are bounded: nothing is built after cycle 200 except the one model of a hazard kind flying for the first time"
		.. (if strayExample then " (e.g. " .. strayExample .. ")" else ""))
	local regrown, kinds = nil, {}
	for kind, n in kindInstances do
		table.insert(kinds, kind)
		if n ~= kindInstancesAtFirst[kind] then regrown = regrown or string.format("%s: %d -> %d", kind, kindInstancesAtFirst[kind] or -1, n) end
	end
	table.sort(kinds)
	print(string.format("  hazard models built: %s", table.concat(kinds, ",")))
	eq(regrown, nil, "each hazard kind's model is built once and reused")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump budget: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump budget check failed", 0)
end
