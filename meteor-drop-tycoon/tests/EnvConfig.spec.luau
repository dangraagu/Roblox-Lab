-- Meteor Drop Tycoon's environment config, checked against the rules the generic modules and the standard
-- set. Run: luau tests/EnvConfig.spec.luau
--
-- The generic modules validate SHAPE. This file checks this game's specifics: six bands, every band
-- blending every lighting field, ClockTime rising and never wrapping past midnight, a hazard-free first
-- band, vertical kinds only (a flat plot), a ring you can leave in under 0.3 s, a queued rest that
-- outlives the longest flight, the brag band agreeing with the Falling Star's level, the weather under
-- budget, and red belonging to the hazard ring alone.

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
do
	local want = { 0, 5, 12, 22, 32, 44 }
	local fades = { 0, 2, 3, 4, 4, 6 }
	for i, b in ipairs(bands) do
		eq(b.from, want[i], b.id .. " starts at Beacon " .. want[i])
		eq(b.fade, fades[i], b.id .. " fades in over " .. fades[i] .. " levels")
		if i > 1 then
			truthy(b.fade <= b.from - bands[i - 1].from, b.id .. ": the fade never reaches back past the band before")
		end
	end
end

--================================================================ the brag band and the Falling Star
do
	local idx = EnvBands.indexOf(bands, Env.BragBandId)
	truthy(idx ~= nil, "the brag band exists")
	eq(bands[idx or 1].from, Env.StarBeacon, "the Falling Star's Beacon level is the brag band's start")
	eq(bands[idx or 1].celebrate, true, "the brag band celebrates")
	local celebrating = 0
	for _, b in ipairs(bands) do if b.celebrate then celebrating += 1 end end
	eq(celebrating, 1, "and it is the only one")
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
	-- each band's weather is its own
	local seen, dup = {}, nil
	for _, b in ipairs(bands) do
		if seen[b.weather.kind] then dup = b.weather.kind end
		seen[b.weather.kind] = true
	end
	eq(dup, nil, "each band has its own weather")
end

do
	-- ClockTime only rises and never reaches midnight: EnvBands.lerp is linear, so 23.5 -> 0.0 would sweep
	-- the sky backwards through the whole day
	local prev, ok = -1, true
	for _, b in ipairs(bands) do
		if b.lighting.ClockTime <= prev or b.lighting.ClockTime >= 24 then ok = false end
		prev = b.lighting.ClockTime
	end
	truthy(ok, "ClockTime strictly rises band to band (17.8 -> 23.9) and stays below 24")
	eq(bands[1].lighting.ClockTime, 17.8, "the meadow starts at golden hour")
	eq(bands[6].atmosphere.Density, 0, "the Core has no atmosphere haze")
	truthy(bands[6].sky.StarCount >= 4000, "and a sky full of stars")
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
	eq(peak, 20, "the snow's 20/s is the peak (DESIGN 5.2)")
	eq(pairPeak, 32, "snow + embers is the busiest seam, 32/s")
	eq(Config.Budget.MaxHazards, 1, "never more than one hazard at a time")
end

--================================================================ hazards
eq(#(bands[1].hazards or {}), 0, "the first band (a brand-new player's first minutes) has no hazards")
truthy(#(bands[Hz.FirstBand].hazards or {}) > 0, "hazards start in band " .. Hz.FirstBand .. " (Twilight, Beacon 5)")
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
eq(Hz.IntervalMin, 120, "no more than one hazard per 2 minutes on your plot")
eq(Hz.IntervalMax, 180, "and at least one per 3 minutes in a hazard band")
truthy(Hz.MinTelegraphSeconds >= 3, "every hazard gives at least 3 s of warning")
do
	local longest = 0
	for name, k in Hz.Kinds do
		eq(k.drop, "above", name .. " falls from above (a sideways lane would start underground on a flat plot)")
		truthy(k.fall <= k.commit, string.format("%s: it falls (%.1f s) only after its lane locks (%.1f s before)", name, k.fall, k.commit))
		local ring = k.hitRadius + Hz.PlayerRadius
		truthy(ring / Config.Trace.WalkSpeed <= 0.3,
			string.format("%s: the %.1f-stud ring can be left from its centre in %.2f s (<= 0.3 s) at WalkSpeed", name, ring, ring / Config.Trace.WalkSpeed))
		truthy(k.commit - ring / Config.Trace.WalkSpeed >= 1.2,
			string.format("%s: with %.1f s to spare after the lock", name, k.commit - ring / Config.Trace.WalkSpeed))
		truthy(k.visualRadius >= k.hitRadius, name .. ": the hitbox is never bigger than what the player sees")
		truthy(k.knock >= 26 and k.knock <= 58, name .. ": a knock inside +1 Jump's measured 26-58 studs/s")
		truthy(type(k.label) == "string" and #k.label > 0, name .. " has a banner label")
		longest = math.max(longest, k.telegraph + k.pass)
	end
	truthy(Config.Rest.PendingSeconds >= longest + 2,
		string.format("a queued rest (%.1f s) outlives the longest hazard flight (%.1f s) by at least 2 s", Config.Rest.PendingSeconds, longest))
	truthy(Hz.KnockLift <= Hazards.MAX_KNOCK_LIFT, "the knock's lift is under the module's cap")
end

--================================================================ red is the hazard ring's alone
local function isReddish(c)
	return c[1] >= 180 and c[2] <= 110 and c[3] <= 110
end
do
	truthy(isReddish(Hz.RingColor), "CONTROL: the predicate does call the hazard ring red")
	truthy(not isReddish(Hz.TrackColor), "the tracking ring (before the lock) is not red")
	local bad = {}
	local function check(what, c)
		if isReddish(c) then table.insert(bad, what) end
	end
	for name, def in Config.Rarities.Defs do check("rarity " .. name, def.color) end
	check("the Falling Star", Config.Rarities.StarColor)
	for _, b in ipairs(bands) do
		check(b.id .. " beam", b.beam)
		check(b.id .. " tint", b.colorCorrection.TintColor)
		check(b.id .. " atmosphere", b.atmosphere.Color)
	end
	for kind, w in Env.Weather do check("weather " .. kind, w.color) end
	for name, c in Config.Palette do check("palette " .. name, c) end
	eq(#bad, 0, "no rarity, glow, beam, weather or server colour is reddish (" .. table.concat(bad, ", ") .. ")")
end

--================================================================ ambient life stays in its lane
do
	for kind, spec in Env.Critters do
		truthy(spec.rMin > 0 and spec.rMax > spec.rMin and spec.speedMax >= spec.speedMin, kind .. " has a sane spawn ring")
	end
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
if failed > 0 then error("EnvConfig spec failed", 0) end
