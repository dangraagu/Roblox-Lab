-- Outpost Zero's environment config, checked against the rules the generic modules and the standard set.
-- Run: luau tests/EnvConfig.spec.luau  (adapted from meteor-drop-tycoon's EnvConfig.spec)
--
-- The generic modules validate SHAPE. This file checks this game's specifics (DESIGN 5-7, 16): six bands that
-- open with the six districts, every band blending every lighting field, ClockTime rising and never wrapping past
-- midnight, a hazard-free first band, vertical kinds only (a flat shelf), a ring you can leave in under 0.3 s, a
-- queued rest that outlives the longest flight, the weather under budget, and red belonging to the hazard ring.

local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
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
	local okH, errH = Hazards.validate(Hz)
	truthy(okH, "Config.Hazards validates (" .. tostring(errH) .. ")")
	local okR, errR = Rest.validate(Config.Rest)
	truthy(okR, "Config.Rest validates (" .. tostring(errR) .. ")")
end

eq(#bands, 6, "six bands (the standard asks for at least 5)")
eq(#Config.Districts, 6, "six districts")
do
	local want = { 0, 80, 900, 6400, 35000, 185000 }
	local fades = { 0, 30, 300, 2000, 10000, 50000 }
	for i, b in ipairs(bands) do
		eq(b.from, want[i], b.id .. " starts at population " .. want[i])
		eq(b.from, Config.Districts[i].open, b.id .. " opens with district " .. i .. " (" .. Config.Districts[i].name .. ")")
		eq(b.fade, fades[i], b.id .. " fades in over " .. fades[i] .. " population")
		if i > 1 then
			truthy(b.fade <= b.from - bands[i - 1].from, b.id .. ": the fade never reaches back past the band before")
		end
	end
end

--================================================================ the brag band and the Skyport
do
	local idx = EnvBands.indexOf(bands, Env.BragBandId)
	truthy(idx ~= nil, "the brag band exists")
	eq(idx, Config.SkyportDistrict, "the brag band is the Skyport's band (the Grand Airship)")
	eq(bands[idx or 1].celebrate, true, "the brag band celebrates")
	local celebrating = 0
	for _, b in ipairs(bands) do if b.celebrate then celebrating += 1 end end
	eq(celebrating, 1, "and it is the only one")
	truthy(Config.Airship.HullBottomY > Config.Economy.MaxStoreys * Config.Lots.StoreyHeight + Config.Lots.RoofHeight,
		"the moored airship's hull (y = 120) clears the tallest roof (22 x 4 + 2 = 90)")
end

--================================================================ every band is its own place
do
	local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
	for _, g in GROUPS do
		local sig0, okAll = nil, true
		for _, b in ipairs(bands) do
			local t = b[g]
			if type(t) ~= "table" then okAll = false else
				local names = {}
				for k in t do table.insert(names, k) end
				table.sort(names)
				local sig = table.concat(names, ",")
				if sig0 == nil then sig0 = sig elseif sig ~= sig0 then okAll = false end
			end
		end
		truthy(okAll, "every band defines the same `" .. g .. "` fields, so no blend falls back to one side")
	end
	local sigs = {}
	local distinct = true
	for _, b in ipairs(bands) do
		truthy(type(b.name) == "string" and #b.name > 0 and type(b.emoji) == "string", b.id .. " has a name and an emoji")
		truthy(#(b.pieces or {}) >= 1, b.id .. " has scenery")
		truthy(#(b.ambient or {}) >= 1, b.id .. " has critters")
		truthy(b.weather ~= nil and Env.Weather[b.weather.kind] ~= nil, b.id .. " has weather that exists")
		local key = table.concat(b.lighting.Ambient, ",") .. "|" .. table.concat(b.colorCorrection.TintColor, ",")
			.. "|" .. tostring(b.lighting.ClockTime) .. "|" .. b.weather.kind .. "|" .. table.concat(b.pieces, ",")
		if sigs[key] then distinct = false end
		sigs[key] = true
		for _, a in ipairs(b.ambient) do
			truthy(Env.Critters[a.kind] ~= nil, b.id .. ": critter " .. a.kind .. " has a spawn spec")
		end
	end
	truthy(distinct, "no two bands share their light, grade, time, weather and scenery")
	local seen, dup = {}, nil
	for _, b in ipairs(bands) do
		if seen[b.weather.kind] then dup = b.weather.kind end
		seen[b.weather.kind] = true
	end
	eq(dup, nil, "each band has its own weather")
	-- the DESIGN 5.2 table, row by row
	local T = {
		{ 1.6, { 110, 105, 115 }, { 150, 140, 155 }, 0.45, { 215, 200, 210 }, { 240, 232, 240 }, 0.8 },
		{ 2.6, { 120, 125, 135 }, { 160, 170, 185 }, 0.30, { 200, 220, 245 }, { 250, 250, 255 }, 0.9 },
		{ 3.0, { 125, 125, 130 }, { 170, 175, 185 }, 0.25, { 205, 225, 250 }, { 255, 250, 240 }, 1.0 },
		{ 2.2, { 120, 100, 95 }, { 170, 135, 120 }, 0.30, { 255, 190, 150 }, { 255, 232, 210 }, 1.5 },
		{ 1.1, { 85, 85, 110 }, { 105, 105, 140 }, 0.40, { 110, 105, 150 }, { 215, 215, 245 }, 1.2 },
		{ 1.0, { 90, 105, 120 }, { 110, 135, 160 }, 0.10, { 60, 90, 120 }, { 220, 245, 240 }, 1.6 },
	}
	for i, row in T do
		local b = bands[i]
		eq(b.lighting.Brightness, row[1], b.id .. ": Brightness as DESIGN 5.2")
		eq(table.concat(b.lighting.Ambient, ","), table.concat(row[2], ","), b.id .. ": Ambient")
		eq(table.concat(b.lighting.OutdoorAmbient, ","), table.concat(row[3], ","), b.id .. ": OutdoorAmbient")
		eq(b.atmosphere.Density, row[4], b.id .. ": Atmosphere density")
		eq(table.concat(b.atmosphere.Color, ","), table.concat(row[5], ","), b.id .. ": Atmosphere colour")
		eq(table.concat(b.colorCorrection.TintColor, ","), table.concat(row[6], ","), b.id .. ": the grade's tint")
		eq(b.bloom.Intensity, row[7], b.id .. ": Bloom")
	end
	eq(bands[6].sky.StarCount, 3000, "Aurora Crown has 3 000 stars")
end

do
	-- ClockTime only rises and never reaches midnight: EnvBands.lerp is linear, so 23.5 -> 0.0 would sweep
	-- the sky backwards through the whole day
	local prev, ok = -1, true
	for _, b in ipairs(bands) do
		if b.lighting.ClockTime <= prev or b.lighting.ClockTime >= 24 then ok = false end
		prev = b.lighting.ClockTime
	end
	truthy(ok, "ClockTime strictly rises band to band (6.4 -> 23.0) and stays below 24")
	eq(bands[1].lighting.ClockTime, 6.4, "the fog starts at dawn")
	eq(bands[6].lighting.ClockTime, 23.0, "the aurora is a clear night")
end

do
	local function range(b, g, field, lo, hi, bad)
		local v = b[g] and b[g][field]
		if v ~= nil and (type(v) ~= "number" or v < lo or v > hi) then
			table.insert(bad, string.format("%s.%s.%s=%s", b.id, g, field, tostring(v)))
		end
	end
	local bad = {}
	for _, b in ipairs(bands) do
		range(b, "lighting", "Brightness", 0, 10, bad)
		range(b, "lighting", "ExposureCompensation", -3, 3, bad)
		range(b, "atmosphere", "Density", 0, 1, bad)
		range(b, "atmosphere", "Offset", 0, 1, bad)
		range(b, "atmosphere", "Glare", 0, 10, bad)
		range(b, "atmosphere", "Haze", 0, 10, bad)
		range(b, "sky", "StarCount", 0, 5000, bad)
		range(b, "colorCorrection", "Brightness", -1, 1, bad)
		range(b, "colorCorrection", "Contrast", -1, 1, bad)
		range(b, "colorCorrection", "Saturation", -1, 1, bad)
		range(b, "sunRays", "Intensity", 0, 1, bad)
		range(b, "sunRays", "Spread", 0, 1, bad)
	end
	eq(#bad, 0, "every value is inside the range Roblox accepts (" .. table.concat(bad, "; ") .. ")")
end

--================================================================ the weather budget
do
	local peak, pairPeak = 0, 0
	for i, b in ipairs(bands) do
		peak = math.max(peak, b.weather.rate)
		if i > 1 then pairPeak = math.max(pairPeak, b.weather.rate + bands[i - 1].weather.rate) end
	end
	truthy(peak <= Config.Budget.MaxEmitterRate, string.format("the busiest weather alone is %d/s, under %d/s", peak, Config.Budget.MaxEmitterRate))
	truthy(pairPeak <= Config.Budget.MaxEmitterRate, string.format("two blended bands peak at %d/s, under %d/s", pairPeak, Config.Budget.MaxEmitterRate))
	eq(peak, 40, "the rain's 40/s is the peak (DESIGN 5.2)")
	eq(pairPeak, 55, "rain + glitter is the busiest seam, 55/s")
	eq(Config.Budget.MaxHazards, 1, "never more than one hazard at a time")
	truthy(Env.LightningMinGap >= 1 / 3, "Storm Front's lightning flashes at most 3 times a second (photosensitivity)")
	eq(Env.LightningMinGap, 3, "in fact at most once per 3 s")
end

--================================================================ hazards
eq(#(bands[1].hazards or {}), 0, "the first band (a brand-new player's first minutes) has no hazards")
truthy(#(bands[Hz.FirstBand].hazards or {}) > 0, "hazards start in band " .. Hz.FirstBand .. " (Clear Morning, population 80)")
do
	local used, unknown = {}, {}
	for _, b in ipairs(bands) do
		for _, k in ipairs(b.hazards or {}) do
			used[k] = true
			if Hz.Kinds[k] == nil then table.insert(unknown, b.id .. ":" .. k) end
		end
	end
	eq(#unknown, 0, "every hazard a band names exists (" .. table.concat(unknown, ", ") .. ")")
	local unused = {}
	for k in Hz.Kinds do if not used[k] then table.insert(unused, k) end end
	eq(#unused, 0, "every hazard kind appears in some band (" .. table.concat(unused, ", ") .. ")")
end
eq(Hz.IntervalMin, 120, "no more than one hazard per 2 minutes on your shelf")
eq(Hz.IntervalMax, 180, "and at least one per 3 minutes in a hazard band")
truthy(Hz.MinTelegraphSeconds >= 3, "every hazard gives at least 3 s of warning")
do
	local longest, biggest = 0, 0
	for name, k in Hz.Kinds do
		eq(k.drop, "above", name .. " falls from above (a sideways lane would start underground on a flat shelf)")
		truthy(k.fall <= k.commit, string.format("%s: it falls (%.1f s) only after its lane locks (%.1f s before)", name, k.fall, k.commit))
		local ring = k.hitRadius + Hz.PlayerRadius
		biggest = math.max(biggest, ring)
		truthy(ring / Hz.WalkSpeed <= 0.3,
			string.format("%s: the %.1f-stud ring can be left from its centre in %.2f s (<= 0.3 s) at WalkSpeed", name, ring, ring / Hz.WalkSpeed))
		truthy(k.commit - ring / Hz.WalkSpeed >= 1.2,
			string.format("%s: with %.1f s to spare after the lock", name, k.commit - ring / Hz.WalkSpeed))
		truthy(k.visualRadius >= k.hitRadius, name .. ": the hitbox is never bigger than what the player sees")
		truthy(k.knock >= 26 and k.knock <= 58, name .. ": a knock inside +1 Jump's measured 26-58 studs/s")
		truthy(type(k.label) == "string" and #k.label > 0, name .. " has a banner label")
		longest = math.max(longest, k.telegraph + k.pass)
	end
	eq(biggest, 4.1, "the biggest ring is 4.1 studs (lightning: 2.6 + 1.5)")
	truthy(Config.Rest.PendingSeconds >= longest + 2,
		string.format("a queued rest (%.1f s) outlives the longest hazard flight (%.1f s) by at least 2 s", Config.Rest.PendingSeconds, longest))
	truthy(Hz.KnockLift <= Hazards.MAX_KNOCK_LIFT, "the knock's lift is under the module's cap")
	local peak = Hz.KnockLift ^ 2 / (2 * 196.2)
	truthy(peak < 0.2 and peak < Config.World.GlassHeight, string.format("the knock lifts at most %.2f studs, far under the 12-stud glass", peak))
end
eq(Config.Rest.IdleSeconds, 60, "idle rest after 60 s standing still: 0.5 % of the first hour [M10]")

--================================================================ red is the hazard ring's alone
local function isReddish(c)
	return c[1] >= 180 and c[2] <= 110 and c[3] <= 110
end
do
	truthy(isReddish(Hz.RingColor), "CONTROL: the predicate does call the hazard ring red")
	truthy(not isReddish(Hz.TrackColor), "the tracking pillar (before the lock) is not red")
	local bad = {}
	local function check(what, c)
		if isReddish(c) then table.insert(bad, what) end
	end
	for d, dist in ipairs(Config.Districts) do
		for i, c in dist.palette do check("district " .. d .. " facade " .. i, c) end
		check("district " .. d .. " paving", dist.paving)
		check("district " .. d .. " window", dist.window)
		check("district " .. d .. " roof", dist.roofColor)
	end
	for _, b in ipairs(bands) do
		check(b.id .. " tint", b.colorCorrection.TintColor)
		check(b.id .. " atmosphere", b.atmosphere.Color)
		check(b.id .. " decay", b.atmosphere.Decay)
		check(b.id .. " fog", b.lighting.FogColor)
		check(b.id .. " ambient", b.lighting.Ambient)
		check(b.id .. " outdoor", b.lighting.OutdoorAmbient)
	end
	for kind, w in Env.Weather do check("weather " .. kind, w.color) end
	for name, c in Config.Palette do check("palette " .. name, c) end
	eq(#bad, 0, "no district, band, weather or server colour is reddish (" .. table.concat(bad, ", ") .. ")")
	truthy(not isReddish(Config.Districts[3].palette[1]), "the Sky-Rail brick (150, 80, 60) is not red: r < 180")
end

--================================================================ ambient life stays in its lane
do
	for kind, spec in Env.Critters do
		truthy(spec.rMin > 0 and spec.rMax > spec.rMin and spec.speedMax >= spec.speedMin, kind .. " has a sane spawn ring")
	end
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
if failed > 0 then error("EnvConfig spec failed", 0) end
