-- anomaly-observatory — the sky's MOVING things, measured frame by frame through the REAL client.
-- Run: luau check_anomalyobservatory_events.luau 2>&1
-- Regenerate the bundle first:
--     py -3 wrap.py --game ../anomaly-observatory --out build/anomaly-observatory.luau
--
-- check_anomalyobservatory_sky.luau proves where every sky part is when a Day has SETTLED, once per
-- Day. The things that move — meteors, the silent lightning bolt, the turning stars of The Other
-- Sky — are re-placed every frame by SkyArt, and a settled snapshot only catches them by luck (a
-- 0.14 s flash every few seconds). This file watches every frame instead, at real Days reached by
-- answering real passes through the server's own prompts:
--
--   1. on EVERY frame, every visible moving part has all eight corners beyond the hall's entrance
--      plane + Clearance (so none of it can ever be inside a hall or in the capture rig's crop);
--   2. the event rates are what Config.Sky says, per band: none at all on the first night, a meteor
--      every few seconds in the Meteor Shower, silent lightning only in the Storm Front, and the
--      storm's lightning stops once the storm band is behind you. This is the game's "rarity"
--      table: there are NO hazards in this game (nothing chases you is the premise); these are the
--      only things that ever move in the sky, and they never touch the player;
--   3. one meteor and one bolt at most at a time; each lasts no longer than its Duration; a meteor
--      draws its trail while it flies and never leaves it on after;
--   4. the player's character is never moved or pushed by any of it.

local Harness = require("./emu/harness")
local Config = require("../anomaly-observatory/src/shared/Config")
local NightSky = require("../anomaly-observatory/src/shared/NightSky")
local EnvBands = require("../anomaly-observatory/src/shared/EnvBands")

local Sky = Config.Sky
local bands = Sky.Bands

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

assert(h:tryRun("server/Main.server"))
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)

local plr = h:join("MeteorWatch", 16180)
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
	local clean = infoOf():GetAttribute("Clean")
	local advance = (clean == true) == right
	local pad = zone:FindFirstChild(if advance then "AdvancePad" else "BackPad")
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	realWait(0.8) -- MIN_PASS_SECONDS is wall-clock
	local co = coroutine.create(function() prompt.Triggered:Fire(plr) end)
	local ok, err = coroutine.resume(co)
	assert(ok, "prompt handler errored: " .. tostring(err))
end

-- ------------------------------------------------------------------ the frame watcher
local LIVE = { "^Meteor%d+$", "^Bolt%d+$", "^Turning%d+$" }
local function liveKind(name: string): string?
	for _, pat in LIVE do
		if string.match(name, pat) then return string.sub(pat, 2, -5) end
	end
	return nil
end

local folder: any = nil
local DT = 1 / 30
local frames = 0
local nearHall = {} -- visible moving part too close to the hall, first few
local nearCount = 0
local worstZ = math.huge
local wasVisible: { [any]: boolean } = {}
local visibleFor: { [any]: number } = {}
local counts = { Meteor = 0, Bolt = 0 }
local longest = { Meteor = 0, Bolt = 0 }
local maxMeteorsAtOnce, maxBoltsAtOnce = 0, 0
local turningFrames = 0
local meteorFrames, trailOnInFlight, trailLeftOn = 0, 0, 0
local charMoved = 0
local hrp0 = hrp.CFrame
local tracking = false -- the character is only watched while nothing but the sky runs

local function watch()
	frames += 1
	if folder == nil then folder = h.workspace:FindFirstChild("ObservatorySky") end
	if tracking and hrp.CFrame ~= hrp0 then charMoved += 1 end
	if folder == nil then return end
	local meteorsNow, boltsNow = 0, 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			local kind = liveKind(d.Name)
			if kind then
				-- only parts actually in the world (a band you left is unparented)
				local visible = d.Transparency < 1 and d:IsDescendantOf(h.workspace)
				if visible then
					local half = d.Size / 2
					local minZ = math.huge
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local wpt = d.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
								if wpt.Z < minZ then minZ = wpt.Z end
							end
						end
					end
					local rel = minZ - origin.z
					if rel < worstZ then worstZ = rel end
					if rel <= Sky.Hall.Front + Sky.Clearance then
						nearCount += 1
						if #nearHall < 5 then
							table.insert(nearHall, string.format("%s z %.1f (frame %d, Day %d)", d.Name, rel, frames, day()))
						end
					end
					if kind == "Meteor" then
						meteorsNow += 1
						meteorFrames += 1
						local trail = d:FindFirstChildOfClass("Trail")
						if trail and trail.Enabled then trailOnInFlight += 1 end
					end
					if kind == "Bolt" and d.Name == "Bolt1" then boltsNow += 1 end
					if kind == "Turning" and d.Name == "Turning1" then turningFrames += 1 end
				end
				if kind == "Meteor" and not visible then
					local trail = d:FindFirstChildOfClass("Trail")
					if trail and trail.Enabled then trailLeftOn += 1 end
				end
				-- event counting: a Meteor part or Bolt1 turning visible is one event
				local counted = kind == "Meteor" or d.Name == "Bolt1"
				if counted then
					if visible and not wasVisible[d] then
						counts[kind] += 1
						visibleFor[d] = 0
					end
					if visible then
						visibleFor[d] = (visibleFor[d] or 0) + 1
						if visibleFor[d] > longest[kind] then longest[kind] = visibleFor[d] end
					end
					wasVisible[d] = visible
				end
			end
		end
	end
	if meteorsNow > maxMeteorsAtOnce then maxMeteorsAtOnce = meteorsNow end
	if boltsNow > maxBoltsAtOnce then maxBoltsAtOnce = boltsNow end
end

local function frame()
	cam.CFrame = hallCam
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
	watch()
end
local function run(seconds: number)
	for _ = 1, math.floor(seconds / DT + 0.5) do frame() end
end

-- Reach Day `target` by answering every pass right, the way a player does.
local function goToDay(target: number)
	while day() < target do
		-- a fresh pass teleports the character to the start pad: that is the server, not the sky
		answer(true)
		run(0.3)
	end
	eq(day(), target, "reached Day " .. target .. " through the server's prompts")
end

-- Watch `minutes` of sky at the current (settled) Day; returns events per minute.
local function measure(minutes: number): (number, number, number)
	run(15) -- let the glide into this Day's sky arrive
	hrp0 = hrp.CFrame
	tracking = true
	local m0, b0, t0 = counts.Meteor, counts.Bolt, turningFrames
	run(minutes * 60)
	tracking = false
	return (counts.Meteor - m0) / minutes, (counts.Bolt - b0) / minutes, turningFrames - t0
end

local function expected(spec: any, weight: number): number
	return 60 / spec.SlotSeconds * spec.Chance * weight
end

print("   Day  band                  meteors/min (expected)   flashes/min (expected)")
local rows = {}
local function row(d: number, minutes: number)
	local f = NightSky.features(bands, EnvBands, d)
	local m, b, turning = measure(minutes)
	local em, eb = expected(Sky.Meteors, f.meteors), expected(Sky.Lightning, f.storm)
	local desc = NightSky.describe(bands, EnvBands, d)
	print(string.format("   %3d  %-20s %8.1f (%5.1f)          %8.1f (%5.1f)", d, desc.id, m, em, b, eb))
	rows[d] = { m = m, b = b, em = em, eb = eb, turning = turning, othersky = f.othersky }
	return rows[d]
end

local MIN = 5
-- the first night: nothing moves
do
	local r = row(1, MIN)
	eq(r.m, 0, "the first night has no meteors")
	eq(r.b, 0, "and no lightning")
	eq(r.turning, 0, "and The Other Sky's stars are not there")
end
-- the meteor shower
goToDay(6)
do
	local r = row(6, MIN)
	truthy(r.em > 0 and math.abs(r.m - r.em) <= 0.3 * r.em,
		string.format("the Meteor Shower shows %.1f meteors a minute, within 30%% of Config.Sky's %.1f", r.m, r.em))
	eq(r.b, 0, "no lightning in the Meteor Shower")
end
-- the storm
goToDay(25)
do
	local r = row(25, MIN)
	truthy(r.eb > 0 and math.abs(r.b - r.eb) <= 0.3 * r.eb,
		string.format("the Storm Front flashes %.1f times a minute, within 30%% of Config.Sky's %.1f", r.b, r.eb))
	eq(r.m, 0, "the storm hides the meteors")
end
-- the other sky: the storm is behind you, the stars turn
goToDay(52)
do
	local r = row(52, MIN)
	eq(r.b, 0, "the lightning stops once the Storm Front is behind you")
	truthy(r.em > 0 and math.abs(r.m - r.em) <= 0.4 * r.em,
		string.format("a few meteors still fall in The Other Sky: %.1f a minute (Config.Sky %.1f)", r.m, r.em))
	eq(r.turning, math.floor(MIN * 60 / DT + 0.5), "The Other Sky's turning stars are there on every frame")
end

-- ------------------------------------------------------------------ verdicts
local maxMeteorFrames = math.ceil(Sky.Meteors.Duration / DT) + 1
local maxBoltFrames = math.ceil(Sky.Lightning.Duration / DT) + 1
print(string.format("   %d frames watched; %d meteors, %d flashes; nearest visible moving part %.1f studs beyond the hall origin (entrance %d + clearance %d)",
	frames, counts.Meteor, counts.Bolt, worstZ, Sky.Hall.Front, Sky.Clearance))
print(string.format("   longest meteor %d frames (limit %d), longest flash %d frames (limit %d), at most %d meteor / %d bolt at once",
	longest.Meteor, maxMeteorFrames, longest.Bolt, maxBoltFrames, maxMeteorsAtOnce, maxBoltsAtOnce))
eq(nearCount, 0, "on EVERY frame every visible moving part is beyond the entrance plane + Clearance: " .. table.concat(nearHall, "; "))
truthy(counts.Meteor >= 20 and counts.Bolt >= 20, "enough events were watched to matter")
truthy(maxMeteorsAtOnce <= 1, "never more than one meteor at a time (" .. maxMeteorsAtOnce .. ")")
truthy(maxBoltsAtOnce <= 1, "never more than one bolt at a time (" .. maxBoltsAtOnce .. ")")
truthy(longest.Meteor <= maxMeteorFrames, string.format("a meteor lasts at most its %.2f s (%d frames, longest %d)", Sky.Meteors.Duration, maxMeteorFrames, longest.Meteor))
truthy(longest.Bolt <= maxBoltFrames, string.format("a flash lasts at most its %.2f s (%d frames, longest %d)", Sky.Lightning.Duration, maxBoltFrames, longest.Bolt))
eq(trailOnInFlight, meteorFrames, string.format("every meteor draws its trail on every frame it flies (%d of %d frames)", trailOnInFlight, meteorFrames))
eq(trailLeftOn, 0, "and no trail is left switched on once its meteor has landed")
eq(charMoved, 0, "nothing in the sky ever moves the player's character")
truthy(not h:hadErrors(), "no script errors")
for _, e in h:errors() do print("   error: " .. tostring(e)) end

print(string.format("\ncheck_anomalyobservatory_events: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("anomaly-observatory events check failed", 0)
end
