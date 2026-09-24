-- anomaly-observatory — the particle budget is enforced IN CODE, not only by the shipped numbers.
-- Run: luau check_anomalyobservatory_cap.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- SkyArt:setWeights switches its emitters on through EnvBands.capRates (the template's cap: at most
-- Budget.MaxEmitters on, the strongest first, summed rate scaled under Budget.MaxEmitterRate). With
-- the numbers this game ships (two emitter kinds: stars 10/s and rain 40/s against a budget of 2
-- emitters and 60/s) the cap can never bind, so check_anomalyobservatory_sky measures a budget the
-- config keeps by itself, and a mutation that bypassed the cap survived the first sweep. This file
-- makes the cap bind — a budget of ONE emitter at 30/s, in memory, this run only — and plays the
-- real client through the Storm Front, where both the stars and the rain want to be on:
--
--   1. on every frame, at most one emitter is on and the summed rate is at most 30/s;
--   2. the one kept is the strongest (the rain), scaled down to the budget, and the stars are off;
--   3. once the storm is over (a wrong call resets the night) the stars come back on.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/anomaly-observatory"), name = "anomaly-observatory", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
-- the game's own Config module, the instance the client will require
local Config = h:_require(RS:FindFirstChild("Config"))
local B = Config.Sky.Budget
local MAX_ON, MAX_RATE = 1, 30
B.MaxEmitters, B.MaxEmitterRate = MAX_ON, MAX_RATE

local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local plr = h:join("CapWatch", 11235)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads with the tighter budget (" .. tostring(errSky) .. ")")

local zone = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
local function infoOf()
	return h.game:GetService("ServerStorage").PassInfo:FindFirstChild(tostring(plr.UserId))
end
local function day(): number
	return plr.leaderstats.Day.Value
end
local function realWait(seconds: number)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do end
end
local function answer(right: boolean)
	local clean = infoOf():GetAttribute("Clean")
	local advance = (clean == true) == right
	local pad = zone:FindFirstChild(if advance then "AdvancePad" else "BackPad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8)
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	assert(coroutine.resume(co))
end

local folder: any = nil
local frames, overOn, overRate = 0, 0, 0
local peakOn, peakRate = 0, 0
-- Emitters keyed by the sky piece that hosts them (NightSky.layout's keys: StarField, RainHost), not
-- by the emitter's own name, which is SkyArt's business (sweep 3: keying by it made a harmless
-- rename fail this check).
local function emitters(): { [string]: any }
	local out = {}
	if folder == nil then return out end
	for _, d in folder:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Parent then out[d.Parent.Name] = d end
	end
	return out
end
local DT = 1 / 30
local function run(seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do
		RunService.RenderStepped:Fire(DT)
		h:advance(DT)
		frames += 1
		if folder == nil then folder = h.workspace:FindFirstChild("ObservatorySky") end
		local on, rate = 0, 0
		for _, e in emitters() do
			if e.Enabled then
				on += 1
				rate += e.Rate
			end
		end
		if on > MAX_ON then overOn += 1 end
		if rate > MAX_RATE + 1e-6 then overRate += 1 end
		peakOn, peakRate = math.max(peakOn, on), math.max(peakRate, rate)
	end
end

run(14)
local e0 = emitters()
truthy(e0.StarField ~= nil and e0.StarField.Enabled, "on the first night the stars are on")

-- into the Storm Front, through the seam where the comet's stars and the storm's rain overlap
while day() < 24 do
	answer(true)
	run(0.5)
end
eq(day(), 24, "Day 24, the Storm Front, reached through the server's prompts")
run(15)
local e = emitters()
truthy(e.RainHost ~= nil and e.RainHost.Enabled, "in the storm the one emitter kept is the rain (the strongest)")
truthy(e.RainHost ~= nil and math.abs(e.RainHost.Rate - MAX_RATE) < 0.06,
	string.format("scaled down to the budget: %.2f/s (it wants %d/s)", e.RainHost and e.RainHost.Rate or -1, Config.Sky.Rain.Rate))
truthy(e.StarField ~= nil and not e.StarField.Enabled, "and the stars are switched off to make room")

-- a wrong call: back to the first night, the storm glides away and the stars return
answer(false)
run(25)
eq(day(), 1, "the wrong call reset the night")
local e2 = emitters()
truthy(e2.StarField ~= nil and e2.StarField.Enabled, "with the storm gone the stars are back")
truthy(e2.RainHost == nil or not e2.RainHost.Enabled, "and the rain is off")

print(string.format("   %d frames; peak %d emitter(s) on, peak %.2f particles/s (budget %d, %d/s)", frames, peakOn, peakRate, MAX_ON, MAX_RATE))
eq(overOn, 0, "on every frame at most " .. MAX_ON .. " emitter is on")
eq(overRate, 0, "on every frame the summed rate is within " .. MAX_RATE .. "/s")
truthy(not h:hadErrors(), "no script errors")
for _, err in h:errors() do print("   error: " .. tostring(err)) end

print(string.format("\ncheck_anomalyobservatory_cap: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory emitter cap check failed", 0)
end
