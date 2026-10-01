-- anomaly-observatory — the weather and the light: every band's own, out in front of the entrance.
-- Run: luau check_anomalyobservatory_weather.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- docs/complete-game-standard.md §2: each band has its own light, colour, scenery, critters AND weather. Here
-- the weather is one ParticleEmitter per kind on an invisible host out in front of the entrance, where the
-- storm's rain always fell: thistledown on the breeze (Clear Night), snow (Aurora), glittering frost (the
-- Comet), the rain (Storm Front), dry leaves (the Alignment), pale motes rising (The Other Sky); the Meteor
-- Shower and Deep Sky are clear skies and say why (`clearSky`). Measured through the REAL server and the real
-- sky client, at Days reached by answering real passes:
--
--   1. at each band's Day, once the glide has settled, exactly the emitters NightSky.emitterRates names for
--      that Day are on (the band's own weather and the stars), each at its rate; no other band's weather;
--   2. on EVERY frame, every enabled weather emitter is measured from the REAL instance: its host's corners,
--      grown by how far its particles can travel (Speed max x Lifetime max x sin(SpreadAngle), the
--      Acceleration's push over a Lifetime, a particle's size), stay beyond the hall's entrance plane +
--      Clearance; it falls or rises (EmissionDirection Bottom/Top), never toward the hall; no colour is
--      reddish; the sky owns no Light; nothing moves the character;
--   3. on every frame at most Budget.MaxEmitters emitters are on, at most Budget.MaxEmitterRate particles a
--      second, through every band change, and after the hardest reset (from the Comet's glide into the storm,
--      four kinds wanted at once, back to Day 1), where the cap in code has to bind;
--   4. a wrong call's reset glides the weather back to the first night's, and every weather emitter that fell
--      was built as its Config says (falls or rises, speed, lifetime, spread, the breeze, size, colour);
--   5. each band's own LIGHT: the hall must never change, so the sky casts no light and writes no Lighting while
--      a pass can be seen; a band's light is the telescope break's colour grade. At each band's Day a break
--      (the B key) takes the camera out, and the grade on it is exactly NightSky.breakLight for that Day (tint,
--      brightness, contrast, saturation); a second B brings the camera back and the grade is off again. A Day
--      that changes DURING a break changes the light with it (the sky glides on, so the grade follows).

local Harness = require("./emu/harness")
local Config = require("../anomaly-observatory/src/shared/Config")
local NightSky = require("../anomaly-observatory/src/shared/NightSky")
local EnvBands = require("../anomaly-observatory/src/shared/EnvBands")

local Sky = Config.Sky
local bands = Sky.Bands
local B = Sky.Budget

local h = Harness.new({
	bundle = require("./build/anomaly-observatory"),
	name = "anomaly-observatory",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

truthy(type(Sky.Weather) == "table" and type(NightSky.emitterRates) == "function" and type(NightSky.bandWeather) == "function",
	"Config.Sky.Weather, NightSky.emitterRates and NightSky.bandWeather exist")
assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("Weatherwatcher", 31415)
local char = h.Players:simulateSpawn(plr, h.workspace)
local hum = char:FindFirstChildOfClass("Humanoid")
local hrp = char:FindFirstChild("HumanoidRootPart")
hum.FloorMaterial = Enum.Material.Plastic
hum.MoveDirection = Vector3.new(0, 0, 0)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
local okSky, errSky = h:tryRun("client/Sky.client")
truthy(okSky, "Sky.client loads (" .. tostring(errSky) .. ")")

local zone = h.workspace:FindFirstChild("Concourse_" .. plr.UserId)
local origin = NightSky.hallOrigin(Sky.Hall, tonumber(zone:GetAttribute("Index")))
local cam = h.workspace.CurrentCamera
local UIS = h.game:GetService("UserInputService")
local function pressB()
	UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.B, UserInputType = Enum.UserInputType.Keyboard }, false)
end
local function camOut(): boolean
	return cam.CFrame.Position.Z - origin.z > Sky.Hall.Front + Sky.Clearance
end
local function grade(): any
	return cam:FindFirstChild("ObservatoryBreakGrade")
end
local hallCam = CFrame.lookAt(Vector3.new(origin.x, origin.y + 8, origin.z + 6), Vector3.new(origin.x, origin.y + 6, origin.z - 80))

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
	local clean = infoOf():GetAttribute("Clean") == true
	local advance = if right then clean else not clean
	local pad = zone:FindFirstChild(if advance then "AdvancePad" else "BackPad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8) -- MIN_PASS_SECONDS is wall-clock
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	local ok, err = coroutine.resume(co)
	assert(ok, "prompt handler errored: " .. tostring(err))
end

-- the emitter's kind, from its name: StarTwinkle -> stars, Rain -> rain, Weather_<kind> -> <kind>
local function kindOf(e: any): string
	if e.Name == "StarTwinkle" then return "stars" end
	if e.Name == "Rain" then return "rain" end
	return string.match(e.Name, "^Weather_(%a+)$") or ("?" .. e.Name)
end
local isWeather = { rain = true }
for _, k in (NightSky.WEATHER or {}) do isWeather[k] = true end

-- ------------------------------------------------------------------ the frame watcher
local DT = 1 / 15
local folder: any = nil
local frames = 0
local peakOn, peakRate, peakAt = 0, 0, ""
local overOn, overRate = 0, 0
local near, nearCount, worstZ = {}, 0, math.huge
local badDir, reddish = {}, {}
local lights = 0
local charMoved, tracking, hrp0 = 0, false, hrp.CFrame
local seenWeather: { [string]: boolean } = {}
local builtWrong: { [string]: string } = {} -- kind -> the first way its emitter differs from Config
-- the instance against Config.Sky.Weather.Kinds[kind] (the rain is Config.Sky.Rain, older and checked elsewhere)
local function mismatch(kind: string, e: any): string?
	local K = Sky.Weather and Sky.Weather.Kinds and Sky.Weather.Kinds[kind]
	if K == nil then return nil end
	local function near(a: any, b: number): boolean return type(a) == "number" and math.abs(a - b) < 1e-6 end
	local wantDir = if K.Direction == "Top" then Enum.NormalId.Top else Enum.NormalId.Bottom
	if e.EmissionDirection ~= wantDir then return "direction " .. tostring(e.EmissionDirection) end
	if not (e.Speed and near(e.Speed.Min, K.Speed[1]) and near(e.Speed.Max, K.Speed[2])) then return "speed" end
	if not (e.Lifetime and near(e.Lifetime.Min, K.Lifetime[1]) and near(e.Lifetime.Max, K.Lifetime[2])) then return "lifetime" end
	if not (e.SpreadAngle and near(e.SpreadAngle.X, K.SpreadDegrees) and near(e.SpreadAngle.Y, K.SpreadDegrees)) then return "spread" end
	local a = e.Acceleration or Vector3.new(0, 0, 0)
	if not (near(a.X, K.Wind) and near(a.Y, 0) and near(a.Z, 0)) then return "breeze " .. tostring(a) end
	if not (e.Size and near(e.Size.Keypoints[1].Value, K.ParticleSize)) then return "size" end
	local c = Sky.Palette[K.Color]
	local got = e.Color and e.Color.Keypoints[1].Value
	if not (got and math.abs(got.R * 255 - c[1]) < 0.6 and math.abs(got.G * 255 - c[2]) < 0.6 and math.abs(got.B * 255 - c[3]) < 0.6) then
		return "colour"
	end
	return nil
end

local function emittersOn(): { [string]: any }
	local out = {}
	if folder == nil then return out end
	for _, d in folder:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Enabled and d:IsDescendantOf(h.workspace) then
			out[kindOf(d)] = d
		end
	end
	return out
end

local function watch()
	frames += 1
	if tracking and hrp.CFrame ~= hrp0 then charMoved += 1 end
	if folder == nil then folder = h.workspace:FindFirstChild("ObservatorySky") end
	if folder == nil then return end
	local on, rate = 0, 0
	for kind, e in emittersOn() do
		on += 1
		rate += e.Rate
		if isWeather[kind] then
			seenWeather[kind] = true
			if builtWrong[kind] == nil then builtWrong[kind] = mismatch(kind, e) end
			local host = e.Parent
			-- how far a particle can get from where it is born, measured from the instance
			-- (an unset property is Roblox's default: Speed 5, Lifetime 5-10, no spread, no acceleration, size 1, Top)
			local L = (e.Lifetime or NumberRange.new(5, 10)).Max
			local reach = (e.Speed or NumberRange.new(5)).Max * L
			local sa = e.SpreadAngle or Vector2.new(0, 0)
			local spread = math.rad(math.max(sa.X, sa.Y))
			local drift = reach * math.sin(math.min(spread, math.pi / 2))
			local acc = e.Acceleration or Vector3.new(0, 0, 0)
			local push = 0.5 * math.abs(acc.Z) * L * L
			local size = 1
			if e.Size then
				size = 0
				for _, kp in e.Size.Keypoints do size = math.max(size, kp.Value + kp.Envelope) end
			end
			local ed = e.EmissionDirection or Enum.NormalId.Top
			local dir = if ed == Enum.NormalId.Top then host.CFrame.UpVector
				elseif ed == Enum.NormalId.Bottom then -host.CFrame.UpVector else nil
			if dir == nil or math.abs(dir.Z) > 1e-6 then
				if #badDir < 5 then table.insert(badDir, e.Name .. " " .. tostring(e.EmissionDirection)) end
			end
			local half = host.Size / 2
			local minZ = math.huge
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local w = host.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						if w.Z < minZ then minZ = w.Z end
					end
				end
			end
			local rel = minZ - drift - push - size - origin.z
			if rel < worstZ then worstZ = rel end
			if rel <= Sky.Hall.Front + Sky.Clearance then
				nearCount += 1
				if #near < 5 then table.insert(near, string.format("%s z %.1f (Day %d)", e.Name, rel, day())) end
			end
			for _, kp in e.Color.Keypoints do
				local c = kp.Value
				if NightSky.isReddish({ c.R * 255, c.G * 255, c.B * 255 }) and #reddish < 5 then table.insert(reddish, e.Name) end
			end
		end
	end
	if on > peakOn or (on == peakOn and rate > peakRate) then
		peakOn, peakRate, peakAt = on, rate, string.format("Day %d, frame %d", day(), frames)
	end
	if on > B.MaxEmitters then overOn += 1 end
	if rate > B.MaxEmitterRate + 1e-6 then overRate += 1 end
	for _, d in folder:GetDescendants() do
		if d:IsA("Light") then lights += 1 end
	end
end

local function frame()
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = hallCam
	end
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
	watch()
end
local function run(seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do frame() end
end

local function goToDay(target: number)
	while day() < target do
		answer(true)
		run(0.3)
	end
	eq(day(), target, "reached Day " .. target .. " through the server's prompts")
end

-- What the settled sky of Day `d` must have on: emitterRates, held to the budget the way SkyArt holds it.
local function expected(d: number): { [string]: number }
	return EnvBands.capRates(NightSky.emitterRates(Sky, NightSky.features(bands, EnvBands, d)), B.MaxEmitters, B.MaxEmitterRate, 0.05)
end
local function describe(t: { [string]: number }): string
	local list = {}
	for k, v in t do table.insert(list, string.format("%s %.1f", k, v)) end
	table.sort(list)
	return table.concat(list, ", ")
end

local plan = {
	{ day = 1, label = "Clear Night" },
	{ day = 6, label = "Meteor Shower" },
	{ day = 12, label = "Aurora" },
	{ day = 18, label = "Great Comet" },
	{ day = 25, label = "Storm Front" },
	{ day = 34, label = "Deep Sky" },
	{ day = 44, label = "Alignment" },
	{ day = 55, label = "Other Sky" },
}
print("   Day  band           weather on (particles/s)")
local lightsSeen: { [string]: boolean } = {}
for _, step in plan do
	goToDay(step.day)
	hrp0 = hrp.CFrame
	tracking = true
	run(20) -- the glide arrives and settles
	tracking = false
	local want = expected(day())
	local got = {}
	for kind, e in emittersOn() do got[kind] = e.Rate end
	print(string.format("   %3d  %-14s %s", day(), step.label, describe(got)))
	eq(describe(got), describe(want), step.label .. ": exactly the emitters emitterRates names for Day " .. day() .. ", at their rates")
	local own = NightSky.bandWeather(Sky, bands[EnvBands.indexAt(bands, day())])
	if #own == 0 then
		truthy(type(bands[EnvBands.indexAt(bands, day())].clearSky) == "string", step.label .. " is a clear sky, and its band says why")
		for kind in got do
			truthy(not isWeather[kind], step.label .. ": no weather falls under a clear sky (" .. kind .. ")")
		end
	else
		for _, kind in own do
			truthy(got[kind] ~= nil and got[kind] > 0, step.label .. ": its own " .. kind .. " is falling")
		end
	end
	-- the band's own light: a break, and the grade on the camera
	pressB()
	run(1.5)
	local g = grade()
	local L = if NightSky.breakLight then NightSky.breakLight(bands, EnvBands, day(), Sky.RestView.Grade) else nil
	truthy(camOut() and g ~= nil and g.Enabled, step.label .. ": a break takes the camera out with its grade on")
	truthy(L ~= nil, step.label .. ": NightSky.breakLight names the band's light")
	if g and L then
		local t = g.TintColor or Color3.new(1, 1, 1)
		local tint = { math.floor(t.R * 255 + 0.5), math.floor(t.G * 255 + 0.5), math.floor(t.B * 255 + 0.5) }
		local want = { math.floor(L.tint[1] + 0.5), math.floor(L.tint[2] + 0.5), math.floor(L.tint[3] + 0.5) }
		print(string.format("        light on the break: tint %d,%d,%d  brightness %.3f  contrast %.3f  saturation %.3f",
			tint[1], tint[2], tint[3], g.Brightness or 0, g.Contrast or 0, g.Saturation or 0))
		eq(table.concat(tint, ","), table.concat(want, ","), step.label .. ": the break wears the band's own tint")
		truthy(math.abs((g.Brightness or 0) - L.brightness) < 1e-3 and math.abs((g.Contrast or 0) - L.contrast) < 1e-3
			and math.abs((g.Saturation or 0) - L.saturation) < 1e-3,
			string.format("%s: and its brightness, contrast and saturation (%.3f, %.3f, %.3f; want %.3f, %.3f, %.3f)", step.label,
				g.Brightness or 0, g.Contrast or 0, g.Saturation or 0, L.brightness, L.contrast, L.saturation))
		lightsSeen[table.concat(tint, ",") .. string.format("|%.3f|%.3f|%.3f", g.Brightness or 0, g.Contrast or 0, g.Saturation or 0)] = true
	end
	pressB()
	run(1.5)
	truthy(not camOut() and (grade() == nil or not grade().Enabled), step.label .. ": a second B brings the camera back, grade off")
end
local nLights = 0
for _ in lightsSeen do nLights += 1 end
eq(nLights, #plan, "eight bands, eight different lights on the break")

-- the light follows a Day that changes while the camera is out (the Day the client reads, as in the critters check)
do
	local dayValue = plr.leaderstats.Day
	local was = dayValue.Value
	pressB()
	run(1.5)
	truthy(camOut(), "out on a break at Day " .. was)
	dayValue.Value = 34
	run(1)
	local g = grade()
	local L = NightSky.breakLight(bands, EnvBands, 34, Sky.RestView.Grade)
	local t = g and g.TintColor
	local tint = if t then string.format("%d,%d,%d", math.floor(t.R * 255 + 0.5), math.floor(t.G * 255 + 0.5), math.floor(t.B * 255 + 0.5)) else "none"
	local want = string.format("%d,%d,%d", math.floor(L.tint[1] + 0.5), math.floor(L.tint[2] + 0.5), math.floor(L.tint[3] + 0.5))
	truthy(camOut() and g ~= nil and g.Enabled, "still out on the break after the Day changed")
	eq(tint, want, "a Day that changes during a break changes the break's light with it (Deep Sky's tint)")
	truthy(g ~= nil and math.abs((g.Contrast or 0) - L.contrast) < 1e-3, "and its contrast")
	dayValue.Value = was
	run(1)
	pressB()
	run(1.5)
	truthy(not camOut(), "back from that break")
end
for _, k in (NightSky.WEATHER or {}) do
	truthy(seenWeather[k], "the " .. k .. " fell at least once on the climb")
	eq(builtWrong[k], nil, "the " .. k .. " emitter is built as Config.Sky.Weather says")
end

-- ------------------------------------------------------------------ the reset: a wrong call
do
	answer(false)
	run(25)
	eq(day(), 1, "a wrong call resets the night to Day 1")
	local want = expected(1)
	local got = {}
	for kind, e in emittersOn() do got[kind] = e.Rate end
	eq(describe(got), describe(want), "and the weather glides back to the first night's (" .. describe(got) .. ")")
end

-- ------------------------------------------------------------------ the hardest reset: the cap must bind
-- Day 21 is the Comet gliding into the Storm Front (frost and rain and the stars all wanted); a reset from
-- there to Day 1 also wants the thistledown: four kinds at once on the way down. The pure glide (the same
-- EnvBands.approachTable the client uses) says how many are WANTED; the instances say how many are ON.
do
	local dayValue = plr.leaderstats.Day
	dayValue.Value = 21
	run(25)
	local wantedPeak = 0
	local shown = NightSky.features(bands, EnvBands, 21)
	local target = NightSky.features(bands, EnvBands, 1)
	for _ = 1, 300 do
		shown = EnvBands.approachTable(shown, target, DT, Sky.GlideHalfLife)
		local n = 0
		for _, v in NightSky.emitterRates(Sky, shown) do if v > 0.05 then n += 1 end end
		if n > wantedPeak then wantedPeak = n end
	end
	local overBefore, peakBefore = overOn, peakOn
	peakOn = 0
	dayValue.Value = 1
	run(25)
	print(string.format("   reset from Day 21: up to %d emitters wanted at once, at most %d on (budget %d)", wantedPeak, peakOn, B.MaxEmitters))
	truthy(wantedPeak > B.MaxEmitters, string.format("the reset wants more emitters than the budget (%d > %d), so the cap has to bind", wantedPeak, B.MaxEmitters))
	eq(overOn - overBefore, 0, "and on every frame of it at most " .. B.MaxEmitters .. " are on")
	peakOn = math.max(peakOn, peakBefore)
end

-- ------------------------------------------------------------------ verdicts
print(string.format("   %d frames watched; nearest reach of any falling weather %.1f studs beyond the hall origin (entrance %d + clearance %d)",
	frames, worstZ, Sky.Hall.Front, Sky.Clearance))
print(string.format("   peak %d emitters on, %.1f particles/s (%s); budget %d, %d/s", peakOn, peakRate, peakAt, B.MaxEmitters, B.MaxEmitterRate))
eq(nearCount, 0, "on EVERY frame all the weather stays beyond the entrance plane + Clearance: " .. table.concat(near, "; "))
eq(#badDir, 0, "weather only falls or rises, never toward the hall: " .. table.concat(badDir, ", "))
eq(#reddish, 0, "no weather is reddish: " .. table.concat(reddish, ", "))
eq(overOn, 0, "on every frame at most Budget.MaxEmitters emitters are on")
eq(overRate, 0, "on every frame at most Budget.MaxEmitterRate particles a second")
eq(lights, 0, "the sky owns no Light")
eq(charMoved, 0, "nothing in the sky ever moves the player's character")
truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomalyobservatory_weather: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory weather check failed", 0)
end
