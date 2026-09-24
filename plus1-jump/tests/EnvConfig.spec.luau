-- +1 Jump's environment config, checked against the rules the generic modules and the brief set.
-- Run: luau tests/EnvConfig.spec.luau
--
-- The generic modules validate SHAPE. This file checks the +1 Jump specifics: that every hazard is
-- dodgeable on this game's 8-stud tiles, that a knock can never lift a player onto a platform, that
-- every band blends every lighting field (so a transition never falls back to one side), that the
-- first minutes are hazard-free, and that the numbers are inside what Roblox accepts.
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Progression = require("../src/shared/Progression")
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

local Env, Hz = Config.Env, Config.Hazards
local bands = Env.Bands

do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "Config.Env.Bands validates (" .. tostring(err) .. ")")
end
do
	local ok, err = Hazards.validate(Hz)
	truthy(ok, "Config.Hazards validates (" .. tostring(err) .. ")")
end
do
	local ok, err = Rest.validate(Config.Rest)
	truthy(ok, "Config.Rest validates (" .. tostring(err) .. ")")
end

--================================================================ hazards per band

eq(#(bands[1].hazards or {}), 0, "the first band (a brand-new player's first minutes) has no hazards")
do
	local used = {}
	local unknown = {}
	for _, b in ipairs(bands) do
		for _, k in ipairs(b.hazards or {}) do
			used[k] = true
			if Hz.Kinds[k] == nil then table.insert(unknown, b.id .. ":" .. k) end
		end
	end
	eq(#unknown, 0, "every hazard a band names exists in Config.Hazards.Kinds (" .. table.concat(unknown, ", ") .. ")")
	local unused = {}
	for k in Hz.Kinds do
		if not used[k] then table.insert(unused, k) end
	end
	eq(#unused, 0, "every hazard kind appears in some band (" .. table.concat(unused, ", ") .. ")")
end
do
	-- the brief: before the clouds, birds and planes; in space, space things
	local cloudIdx = EnvBands.indexOf(bands, "cloudsea")
	truthy(cloudIdx ~= nil, "there is a cloud band")
	for i = 1, (cloudIdx or 1) - 1 do
		for _, k in ipairs(bands[i].hazards or {}) do
			truthy(k == "bird" or k == "plane", "below the clouds only birds/planes (" .. bands[i].id .. ":" .. k .. ")")
		end
	end
end

eq(Hz.MinTelegraphSeconds >= 3, true, "every hazard gives at least 3 s of warning")
eq(Hz.IntervalMin, 120, "no more than one hazard per 2 minutes of climbing")
eq(Hz.IntervalMax, 180, "and at least one per 3 minutes in a hazard band")

do
	local half = Config.Tower.TileSize / 2
	for name, k in Hz.Kinds do
		truthy(k.hitRadius + Hz.PlayerRadius < half,
			string.format("%s: hit radius %.1f + player %.1f is under half a tile (%.1f), so a sidestep on your own platform dodges it",
				name, k.hitRadius, Hz.PlayerRadius, half))
		truthy(k.visualRadius == nil or k.visualRadius >= k.hitRadius,
			name .. ": the hitbox is never bigger than what the player sees (forgiving, never unfair)")
	end
end
do
	-- a knock's lift, as a height: v^2 / 2g. It must be nowhere near the smallest step in the game.
	local lift = Hz.KnockLift * Hz.KnockLift / (2 * Config.Pacing.Gravity)
	truthy(lift < Progression.stepHeight(1, Config.Tower) / 4,
		string.format("a knock lifts at most %.2f studs: it can never carry a player up to a platform", lift))
end
eq(type(Hz.NearMissStuds), "number", "a near-miss distance is defined for measurement")
do
	-- Rest pressed the moment a hazard launches is queued; the player dodges; the rest must still be
	-- waiting when the hazard's flight ends, with time left to stand still (review 2026-09-17).
	local longest = 0
	for _, k in Hz.Kinds do
		longest = math.max(longest, k.telegraph + k.pass)
	end
	truthy(Config.Rest.PendingSeconds >= longest + 2,
		string.format("a queued rest (%.1f s) outlives the longest hazard flight (%.1f s) by at least 2 s",
			Config.Rest.PendingSeconds, longest))
end

--================================================================ the temple island is below the rescue

-- Review 2026-09-17 (finding 5): the island's grass top was at BaseY-70, under the server's rescue line
-- (BaseY-60) but not under where a falling player actually IS when the 0.4 s poll fires: 89% of walk-offs
-- sank into the grass before the teleport. The island must sit below the worst case: the fall to the
-- line, a full poll, and an allowance for the network (the server sees the client's position late and
-- the teleport reaches the client late).
do
	local P = Config.Pacing
	local depth = Env.IslandTopBelowPad
	truthy(type(depth) == "number" and depth > 0, "Config.Env.IslandTopBelowPad is set")
	truthy(type(P.RescueLatencySeconds) == "number" and P.RescueLatencySeconds >= 0.4,
		"a network allowance of at least 0.4 s is assumed (" .. tostring(P.RescueLatencySeconds) .. ")")
	local standingRoot = 3 -- root above the pad top, feet at the pad
	local toLine = standingRoot + P.RescueDropStuds
	local cross = math.sqrt(2 * toLine / P.Gravity)
	local worst = cross + P.RescuePollSeconds + (P.RescueLatencySeconds or 0)
	local feetDrop = 0.5 * P.Gravity * worst * worst
	local grassTop = -(depth or 0)
	print(string.format("  walk off the pad: line crossed at %.2f s, worst rescue at %.2f s, feet %.0f studs down; island grass %.0f down",
		cross, worst, feetDrop, depth or 0))
	truthy(grassTop <= -feetDrop - 10,
		"a player who steps off the pad is always rescued at least 10 studs above the island's grass")
end

--================================================================ every hazard starts on screen

-- Review 2026-09-17 (finding 1): the old rule only kept a lane within SpreadDegrees of the camera's
-- HEADING, so a weather balloon rising from -55 degrees never appeared on the screen of a climber looking
-- up at the next platform. Here every band's own kinds are launched through Hazards.step at camera
-- pitches -60..60 (a climber on a 44-stud step looks well up), from a camera behind the player, on
-- 16:9 and 4:3 screens with Roblox's default 70-degree vertical FOV and a 4-degree margin.
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
		if #(b.hazards or {}) > 0 then
			for _, camPitch in { -60, -40, -20, 0, 20, 40, 60 } do
				for _, aspect in { 16 / 9, 4 / 3 } do
					for _ = 1, 60 do
						local yaw = r() * math.pi * 2
						local cp = math.rad(camPitch)
						local look = { x = math.sin(yaw) * math.cos(cp), y = math.sin(cp), z = math.cos(yaw) * math.cos(cp) }
						local aim = { x = 0, y = 9000, z = 0 }
						local camPos = { x = -look.x * 14, y = 9000 - look.y * 14, z = -look.z * 14 }
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
	eq(bad, 0, "every band's hazards start on screen and stay there until the lane locks (" .. (total - bad) .. "/" .. total
		.. (if example then "; e.g. " .. example else "") .. ")")
end

--================================================================ every band blends every field

local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
for _, g in GROUPS do
	local fields = nil
	local okAll = true
	for _, b in ipairs(bands) do
		local t = b[g]
		if type(t) ~= "table" then
			okAll = false
			print("  missing group", g, "in", b.id)
		else
			local names = {}
			for k in t do table.insert(names, k) end
			table.sort(names)
			local sig = table.concat(names, ",")
			if fields == nil then fields = sig elseif fields ~= sig then
				okAll = false
				print("  field mismatch in", g, b.id, sig, "vs", fields)
			end
		end
	end
	truthy(okAll, "every band defines the same `" .. g .. "` fields, so no blend falls back to one side")
end

local function isColor(c)
	return type(c) == "table" and #c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[2] <= 255
		and c[3] >= 0 and c[3] <= 255
end
do
	local bad = {}
	local function range(b, g, field, lo, hi)
		local v = b[g] and b[g][field]
		if v == nil then return end
		if type(v) ~= "number" or v < lo or v > hi then
			table.insert(bad, string.format("%s.%s.%s=%s", b.id, g, field, tostring(v)))
		end
	end
	for _, b in ipairs(bands) do
		range(b, "lighting", "ClockTime", 0, 24)
		range(b, "lighting", "Brightness", 0, 10)
		range(b, "lighting", "ExposureCompensation", -3, 3)
		range(b, "atmosphere", "Density", 0, 1)
		range(b, "atmosphere", "Offset", 0, 1)
		range(b, "atmosphere", "Glare", 0, 10)
		range(b, "atmosphere", "Haze", 0, 10)
		range(b, "sky", "StarCount", 0, 5000)
		range(b, "colorCorrection", "Brightness", -1, 1)
		range(b, "colorCorrection", "Contrast", -1, 1)
		range(b, "colorCorrection", "Saturation", -1, 1)
		range(b, "sunRays", "Intensity", 0, 1)
		range(b, "sunRays", "Spread", 0, 1)
		for _, g in GROUPS do
			for field, v in b[g] or {} do
				if type(v) == "table" and not isColor(v) then
					table.insert(bad, b.id .. "." .. g .. "." .. field .. " is not an {r,g,b} colour")
				end
			end
		end
	end
	eq(#bad, 0, "every value is inside the range Roblox accepts (" .. table.concat(bad, "; ") .. ")")
end

do
	-- the sky arc: it only gets darker as you climb (ClockTime never runs backwards through a day)
	local prev, ok = -1, true
	for _, b in ipairs(bands) do
		if b.lighting.ClockTime < prev then ok = false end
		prev = b.lighting.ClockTime
	end
	truthy(ok, "ClockTime never decreases band to band (afternoon -> sunset -> night, never back)")
	local space = bands[EnvBands.indexOf(bands, Env.SpaceBandId)]
	eq(space.atmosphere.Density, 0, "space has no atmosphere haze")
	truthy(space.sky.StarCount >= 2000, "and a sky full of stars")
end

--================================================================ presentation + layers + budget

for _, b in ipairs(bands) do
	truthy(type(b.name) == "string" and #b.name > 0 and type(b.emoji) == "string",
		b.id .. " has a display name and emoji for the title card and the leaderboard")
end
for _, layer in ipairs(Env.Layers or {}) do
	truthy(type(layer.center) == "number" and layer.halfWidth >= 0 and layer.feather > 0,
		"layer " .. tostring(layer.id) .. " is well formed")
	local b = bands[EnvBands.indexAt(bands, layer.center)]
	local listed = false
	for _, piece in ipairs(b.pieces or {}) do
		if piece == layer.piece then listed = true end
	end
	truthy(listed, "layer " .. tostring(layer.id) .. " sits inside a band that shows its scenery (" .. b.id .. ")")
end

local B = Config.Budget
truthy(type(B) == "table", "Config.Budget exists (measured by robloxemu/check_plus1_sky.luau)")
if B then
	eq(B.MaxHazards, 1, "one hazard at a time")
	truthy(B.MaxLocalParts > 0 and B.MaxLocalParts <= 300, "a mobile-sized local part budget (<= 300)")
	truthy(B.MaxEmitters <= 4, "at most 4 particle emitters")
	local worstRate = 0
	for _, b in ipairs(bands) do
		if b.weather and b.weather.rate > worstRate then worstRate = b.weather.rate end
	end
	truthy(worstRate <= B.MaxEmitterRate,
		"no band's weather asks for more particles per second than the budget (" .. worstRate .. " <= " .. B.MaxEmitterRate .. ")")
	-- review round 2 (finding 4): the weather cap the client enforces (EnvBands.capRates in SkyArt)
	truthy(type(B.MaxWeatherEmitters) == "number" and B.MaxWeatherEmitters >= 1 and B.MaxWeatherEmitters <= B.MaxEmitters,
		"Config.Budget.MaxWeatherEmitters is set and inside MaxEmitters (" .. tostring(B.MaxWeatherEmitters) .. " <= " .. B.MaxEmitters .. ")")
	eq(B.MaxWeatherEmitters, 2, "two weather emitters at most: a band's own plus the one it fades into")
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
assert(failed == 0, "EnvConfig tests failed")
