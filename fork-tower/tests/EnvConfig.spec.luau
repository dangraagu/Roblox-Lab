-- Spec for Fork Tower's environment numbers in Config: Env (bands), Hazards, Rest, Budget, Pacing.
-- Run: luau tests/EnvConfig.spec.luau
--
-- The pure modules (EnvBands, Hazards, Rest, Climb) are specced on their own. This file checks the
-- GAME's numbers against the promises in EYECANDY.md and the owner's brief (2026-09-17):
--   * every run of ten floors walks through at least five distinct environments, a change at least
--     every three floors, never a hard cut;
--   * hazards are rare and telegraphed, start on screen, and a step out of the red ring on a Fork
--     Tower tile (9 studs) dodges every kind without walking off the tile;
--   * the first floors (a new player's first minute) and the summit are hazard-free;
--   * rest can never be a panic button and never outlives nothing;
--   * the budgets exist and every band fits inside them.
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Climb = require("../src/shared/Climb")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local Env, Hz, RestCfg, Budget = Config.Env, Config.Hazards, Config.Rest, Config.Budget
local FLOORS = Config.Tower.Floors
truthy(type(Env) == "table" and type(Env.Bands) == "table", "Config.Env.Bands exists")
truthy(type(Hz) == "table", "Config.Hazards exists")
truthy(type(RestCfg) == "table", "Config.Rest exists")
truthy(type(Budget) == "table", "Config.Budget exists")
if type(Env) ~= "table" or type(Env.Bands) ~= "table" or type(Hz) ~= "table" or type(RestCfg) ~= "table"
	or type(Budget) ~= "table" then
	print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
	return
end
local bands = Env.Bands

--================================================================ the bands

do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "Config.Env.Bands validates (" .. tostring(err) .. ")")
end

-- Bands are NAMED by the floor number (Climb.namedFloor - 1), so every band starts exactly at a
-- fork: an integer number of floors climbed.
for _, b in ipairs(bands) do
	truthy(b.from == math.floor(b.from), b.id .. " starts at a whole floor (it is named by the floor number)")
	truthy(b.from <= FLOORS, b.id .. " is reachable in one run (from <= " .. FLOORS .. ")")
	truthy(type(b.name) == "string" and #b.name > 0 and type(b.emoji) == "string" and #b.emoji > 0,
		b.id .. " has a name and an emoji for the chip and the title card")
end
eq(bands[#bands].from, FLOORS, "the last band starts exactly at the summit (floors climbed = " .. FLOORS .. ")")

-- One run passes through every band, and the world changes at least every three floors.
do
	local seen, longest, run, last = {}, 0, 0, nil
	local distinct = 0
	for n = 1, FLOORS + 1 do
		local idx = EnvBands.indexAt(bands, Climb.namedFloor(n, n > FLOORS, FLOORS) - 1)
		if not seen[idx] then seen[idx] = true; distinct += 1 end
		if idx == last then run += 1 else run = 1 end
		last = idx
		if run > longest then longest = run end
	end
	truthy(distinct >= 5, "one ten-floor run walks through at least five distinct environments (" .. distinct .. ")")
	eq(distinct, #bands, "every band is reached in one run")
	truthy(longest <= 3, "no environment lasts longer than three floors (longest " .. longest .. ")")
end

-- Never a hard cut: every band after the first fades in over part of the section below its first
-- fork, and never reaches back past the previous fork.
for i = 2, #bands do
	local f = bands[i].fade or 0
	truthy(f > 0 and f <= 1, bands[i].id .. " fades in over (0, 1] floor (" .. tostring(f) .. ")")
end

-- Every band defines exactly the same lighting fields as the first (a field missing in one band
-- would snap instead of blend), with sane values.
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
for _, g in GROUPS do
	local keys = {}
	for k in bands[1][g] or {} do keys[k] = true end
	truthy(next(keys) ~= nil, "band 1 defines " .. g)
	for _, b in ipairs(bands) do
		local grp = b[g] or {}
		local same = true
		for k in keys do if grp[k] == nil then same = false end end
		for k in grp do if not keys[k] then same = false end end
		truthy(same, b.id .. "." .. g .. " defines exactly band 1's fields")
		for k, v in grp do
			if type(v) == "table" then
				truthy(#v == 3 and v[1] >= 0 and v[1] <= 255 and v[2] >= 0 and v[2] <= 255 and v[3] >= 0 and v[3] <= 255,
					b.id .. "." .. g .. "." .. k .. " is an {r,g,b} in 0..255")
			else
				truthy(type(v) == "number" and v == v, b.id .. "." .. g .. "." .. k .. " is a number")
			end
		end
	end
end
-- The sun only ever moves forward as you climb: a seam blends ClockTime linearly (EnvBands.lerp),
-- so a band set EARLIER in the day than the one below it would run the sun backwards through the
-- seam (measured in the first headless run: storm 18.7 -> observatory 0.2 passed 13.87, midday,
-- half-way up floor 8). Night-to-night across a rebirth is the glue's job (Climb.nearestClock).
for i = 2, #bands do
	truthy(bands[i].lighting.ClockTime >= bands[i - 1].lighting.ClockTime,
		string.format("%s's ClockTime (%.2f) is not earlier than %s's (%.2f): the sun never runs backwards up the tower",
			bands[i].id, bands[i].lighting.ClockTime, bands[i - 1].id, bands[i - 1].lighting.ClockTime))
end
for _, b in ipairs(bands) do
	local L = b.lighting
	truthy(L.ClockTime >= 0 and L.ClockTime < 24, b.id .. ": ClockTime in [0, 24)")
	truthy(b.atmosphere.Density >= 0 and b.atmosphere.Density <= 0.8, b.id .. ": atmosphere density leaves the tower visible (<= 0.8)")
	truthy(b.sky.StarCount >= 0 and b.sky.StarCount <= 5000, b.id .. ": StarCount within Roblox's 0..5000")
end

-- pieces, life and weather name things the art can build, and weather fits the emitter budget
for _, b in ipairs(bands) do
	truthy(type(b.pieces) == "table", b.id .. " lists its scenery pieces")
	truthy(type(b.ambient) == "table", b.id .. " lists its ambient life")
	for _, a in ipairs(b.ambient) do
		truthy(Env.Critters[a.kind] ~= nil, b.id .. ": ambient kind " .. tostring(a.kind) .. " has a spawn spec in Env.Critters")
		truthy(a.count >= 0 and a.count <= 12, b.id .. ": at most 12 of one ambient kind")
	end
	truthy(type(b.weather) == "table" and type(b.weather.kind) == "string", b.id .. " names its weather")
	truthy(b.weather.rate > 0 and b.weather.rate <= Budget.MaxEmitterRate,
		b.id .. ": weather rate within the emitter budget (" .. tostring(b.weather.rate) .. " <= " .. Budget.MaxEmitterRate .. ")")
	truthy(type(b.hazards) == "table", b.id .. " lists its hazards (possibly none)")
	for _, k in ipairs(b.hazards) do
		truthy(Hz.Kinds[k] ~= nil, b.id .. ": hazard kind " .. tostring(k) .. " exists in Config.Hazards.Kinds")
	end
end
-- the first environment (a new player's first floors) and the summit have no hazards
eq(#bands[1].hazards, 0, "the first environment is hazard-free (onboarding)")
eq(#bands[#bands].hazards, 0, "the summit environment is hazard-free")
do
	local withHazards = 0
	for _, b in ipairs(bands) do if #b.hazards > 0 then withHazards += 1 end end
	truthy(withHazards >= 3, "at least three environments have their own hazards (" .. withHazards .. ")")
end
-- every kind is used by some band (no dead config)
for name in Hz.Kinds do
	local used = false
	for _, b in ipairs(bands) do
		for _, k in ipairs(b.hazards) do if k == name then used = true end end
	end
	truthy(used, "hazard kind " .. name .. " is flown by some band")
end

--================================================================ hazards

do
	local ok, err = Hazards.validate(Hz)
	truthy(ok, "Config.Hazards validates (" .. tostring(err) .. ")")
end
truthy(Hz.MinTelegraphSeconds >= 3, "every hazard warns for at least 3 s (easy to see coming)")
truthy(Hz.IntervalMin >= 60, "at least a minute of climbing between two hazards (rare)")

-- The red ring is the rule (Hazards.zone). A player at a tile's centre walks out of it in any
-- direction and still stands on the tile with a stud to spare: Fork Tower's tiles are
-- Config.Tower.TileSize (9) studs, not +1 Jump's 8.
local TILE = Config.Tower.TileSize
for name, k in Hz.Kinds do
	local radius = k.hitRadius + Hz.PlayerRadius
	truthy(radius <= TILE / 2 - 1, string.format("%s: the ring (radius %.1f) is left with a stud of tile to spare (half tile %.1f)",
		name, radius, TILE / 2))
	truthy(k.knock >= 20, name .. ": a hit pushes hard enough to leave the platform (knock >= 20)")
end
truthy(Hz.KnockLift <= Hazards.MAX_KNOCK_LIFT, "the knock's lift is capped (it can never carry a player UP to anything)")
-- the lift cannot reach the next step: a knock is a push down, never a free platform
do
	local g = Config.Physics.Gravity
	local rise = Hz.KnockLift * Hz.KnockLift / (2 * g)
	truthy(rise < Config.Tower.StepMin, string.format("the knock's lift rises %.2f studs, below the smallest step %.1f", rise, Config.Tower.StepMin))
end
truthy(Hz.KnockSeconds > 0 and Hz.KnockSeconds <= 1.5, "the knock releases the character within 1.5 s")
truthy(Hz.NearMissStuds == 8, "a near-hit is a pass within 8 studs (the template's definition)")

-- every band's hazards start on screen and stay there until the lane locks (the template's
-- measurement, on this game's kinds): camera pitches -60..60, 16:9 and 4:3, 4-degree margin
do
	local function lcg(seed)
		local st = seed % 4294967296
		return function()
			st = (1664525 * st + 1013904223) % 4294967296
			return st / 4294967296
		end
	end
	local function onScreen(camPos, look, p, aspect, margin)
		local fx, fy, fz = look.x, look.y, look.z
		local rx, rz = fz, -fx
		local rl = math.sqrt(rx * rx + rz * rz)
		rx, rz = rx / rl, rz / rl
		local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
		local dx, dy, dz = p.x - camPos.x, p.y - camPos.y, p.z - camPos.z
		local depth = dx * fx + dy * fy + dz * fz
		if depth <= 0 then return false end
		local tv = math.tan(math.rad(35 - margin))
		local th = math.tan(math.rad(math.deg(math.atan(math.tan(math.rad(35)) * aspect)) - margin))
		return math.abs((dx * rx + dz * rz) / depth) <= th and math.abs((dx * ux + dy * uy + dz * uz) / depth) <= tv
	end
	local r = lcg(8080)
	local total, bad, example = 0, 0, nil
	for _, b in ipairs(bands) do
		if #b.hazards > 0 then
			for _, camPitch in { -60, -40, -20, 0, 20, 40, 60 } do
				for _, aspect in { 16 / 9, 4 / 3 } do
					for _ = 1, 60 do
						local yaw = r() * math.pi * 2
						local cp = math.rad(camPitch)
						local look = { x = math.sin(yaw) * math.cos(cp), y = math.sin(cp), z = math.cos(yaw) * math.cos(cp) }
						local aim = { x = 0, y = 200, z = 0 }
						local camPos = { x = -look.x * 14, y = 200 - look.y * 14, z = -look.z * 14 }
						local s = Hazards.newScheduler(Hz, r)
						s.clock = s.nextAt
						local ctx = { resting = false, grounded = true, kinds = b.hazards, aim = aim, yaw = yaw, pitch = cp }
						local ev = Hazards.step(s, Hz, 0.05, ctx, r)
						local plan = ev and ev.plan
						local ok = plan ~= nil
						while ok and plan.t < plan.commitAt do
							if not onScreen(camPos, look, Hazards.positionAt(plan, plan.t), aspect, 4) then ok = false end
							Hazards.step(s, Hz, 0.05, ctx, r)
						end
						total += 1
						if not ok then
							bad += 1
							example = string.format("%s:%s at pitch %d", b.id, plan and plan.kind or "?", camPitch)
						end
					end
				end
			end
		end
	end
	print(string.format("  on-screen launches: %d of %d on screen from launch until the lane locks", total - bad, total))
	eq(bad, 0, "every band's hazards start on screen and stay there until the lane locks (" .. (total - bad) .. "/" .. total
		.. (if example then "; e.g. " .. example else "") .. ")")
end

--================================================================ rest

do
	local ok, err = Rest.validate(RestCfg)
	truthy(ok, "Config.Rest validates (" .. tostring(err) .. ")")
end
truthy(RestCfg.RequireGrounded == true, "rest cannot start in the air")
do
	local longest = 0
	for _, k in Hz.Kinds do
		longest = math.max(longest, k.telegraph + k.pass)
	end
	truthy(RestCfg.PendingSeconds >= longest + 1,
		string.format("a queued rest outlives the longest hazard flight (%.1f s) by at least 1 s (PendingSeconds %.1f)", longest, RestCfg.PendingSeconds))
end
truthy(RestCfg.IdleSeconds > 0, "idle rest is on (AFK-safe)")

--================================================================ the sanctuary

truthy(type(Env.Sanctuary) == "table", "Config.Env.Sanctuary exists")
eq(Env.Sanctuary.Radius, Hz.PlayerRadius, "the sanctuary grows each pad by exactly the player radius the ring uses")
truthy(Env.Sanctuary.Ceiling >= Config.Jump.MaxJumpHeight + Env.FloorBelowRoot,
	"a hop on the pad (up to MaxJumpHeight) never leaves the sanctuary")

--================================================================ budgets

for _, k in { "MaxLocalParts", "MaxEmitters", "MaxWeatherEmitters", "MaxEmitterRate", "MaxBeams", "MaxTrails", "MaxLights", "MaxHazards" } do
	truthy(type(Budget[k]) == "number" and Budget[k] > 0, "Config.Budget." .. k .. " is set")
end
truthy(Budget.MaxWeatherEmitters <= Budget.MaxEmitters, "weather never takes more emitters than the whole budget")
eq(Budget.MaxHazards, 1, "one hazard at a time")
truthy(Budget.MaxLocalParts <= 220, "the local part budget is no bigger than +1 Jump's (mobile)")
truthy(Budget.MaxLights <= 3, "at most three local lights")

--================================================================ scenery placement

-- Walls of scenery stand either side of the lane, outside the tower's corridor (so nothing local
-- ever sits on or beside a door) and inside half the gap to the neighbouring lane's corridor.
do
	local W = Config.World
	local towerReach = W.CorridorHalfWidth + 30 / 2 -- widest pad (the summit) half-width
	truthy(Env.WallOffset - Env.WallDepth / 2 >= towerReach + 10,
		string.format("the scenery walls start %d studs out, at least 10 past the tower's reach (%d)", Env.WallOffset - Env.WallDepth / 2, towerReach))
	truthy(Env.WallOffset + Env.WallDepth / 2 <= W.LaneSpacing - towerReach - 10,
		"and end at least 10 studs short of the neighbouring tower's reach")
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
