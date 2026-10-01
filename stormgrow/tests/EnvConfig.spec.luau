-- StormGrow's environment config, checked against the rules the generic modules and the standard set.
-- Run: luau tests/EnvConfig.spec.luau
--
-- Adapted from plus1-jump/tests/EnvConfig.spec.luau (the template). The generic modules validate SHAPE;
-- this file checks the StormGrow specifics: seven bands on the lifetime harvest, the first band hazard-free,
-- every hazard dodgeable by stepping out of a ring under 5 studs, a knock that lifts nobody anywhere, the
-- ring kept up while a hit is still possible (Hazards.threatLive), no lane that starts underground on flat
-- ground, every band blending every lighting field, and the budgets.
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Weather = require("../src/shared/Weather")
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
do
	local ok, err = Weather.validate(Config.Weather)
	truthy(ok, "Config.Weather validates (" .. tostring(err) .. ")")
end
eq(Config.Weather.ClockOffsetSeconds, 0, "the shots-place clock offset is 0 in src/ (DESIGN.md §2.1)")

--================================================================ the bands

truthy(#bands >= 5, "at least 5 bands (the standard): " .. #bands)
eq(#bands, 7, "seven bands, Sunny Meadow to Starfall Summit")
do
	local want = { 0, 150, 1200, 9000, 55000, 300000, 11000000 }
	local ok = true
	for i, b in bands do
		if b.from ~= want[i] then ok = false end
		-- "a third", rounded as DESIGN.md §3.2 rounds it (18,000 for 55,000; 3.6 M for 11 M): within 2 %
		if i > 1 and math.abs(b.fade - b.from / 3) > b.from / 3 * 0.02 then ok = false end
	end
	truthy(ok, "the thresholds are DESIGN.md §3.2's and every fade is a third of its threshold (within 2 %)")
end
do
	local brag = bands[EnvBands.indexOf(bands, Env.BragBandId) or 0]
	truthy(brag ~= nil, "the brag band exists")
	eq(brag and brag.celebrate, true, "and celebrates")
	eq(brag and brag.from, 300000, "at 300,000 harvested")
	eq(Config.Crops[#Config.Crops].needHarvested, 300000, "the Stormfruit gate is the brag band's own threshold")
end
for _, b in bands do
	truthy(type(b.name) == "string" and #b.name > 0 and type(b.emoji) == "string",
		b.id .. " has a display name and emoji for the chip and the card")
	truthy(type(b.pieces) == "table" and #b.pieces > 0, b.id .. " has its own scenery")
	truthy(type(b.ambient) == "table" and #b.ambient > 0, b.id .. " has critters")
	truthy(type(b.weather) == "table" and b.weather.rate > 0, b.id .. " has ambient weather")
	truthy(type(b.ground) == "table" and #b.ground == 3, b.id .. " tints the valley floor")
	for _, a in b.ambient do
		truthy(Env.Critters[a.kind] ~= nil, b.id .. ": critter " .. a.kind .. " is defined")
	end
end
do
	-- every band's scenery is its own: no two bands share their whole set
	local sigs, dup = {}, 0
	for _, b in bands do
		local s = table.concat(b.pieces, ",")
		if sigs[s] then dup += 1 end
		sigs[s] = true
	end
	eq(dup, 0, "no two bands show the same scenery")
end

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
	local function range(where, t, field, lo, hi)
		local v = t and t[field]
		if v == nil then return end
		if type(v) ~= "number" or v < lo or v > hi then
			table.insert(bad, string.format("%s.%s=%s", where, field, tostring(v)))
		end
	end
	local function check(where, set)
		range(where .. ".lighting", set.lighting, "ClockTime", 0, 24)
		range(where .. ".lighting", set.lighting, "Brightness", 0, 10)
		range(where .. ".lighting", set.lighting, "ExposureCompensation", -3, 3)
		range(where .. ".atmosphere", set.atmosphere, "Density", 0, 1)
		range(where .. ".atmosphere", set.atmosphere, "Offset", 0, 1)
		range(where .. ".atmosphere", set.atmosphere, "Glare", 0, 10)
		range(where .. ".atmosphere", set.atmosphere, "Haze", 0, 10)
		range(where .. ".sky", set.sky, "StarCount", 0, 5000)
		range(where .. ".colorCorrection", set.colorCorrection, "Brightness", -1, 1)
		range(where .. ".colorCorrection", set.colorCorrection, "Contrast", -1, 1)
		range(where .. ".colorCorrection", set.colorCorrection, "Saturation", -1, 1)
		range(where .. ".sunRays", set.sunRays, "Intensity", 0, 1)
		range(where .. ".sunRays", set.sunRays, "Spread", 0, 1)
		for _, g in GROUPS do
			for field, v in set[g] or {} do
				if type(v) == "table" and not isColor(v) then
					table.insert(bad, where .. "." .. g .. "." .. field .. " is not an {r,g,b} colour")
				end
			end
		end
	end
	for _, b in bands do check(b.id, b) end
	for kind, o in Env.Overlays do check("overlay." .. kind, o.set) end
	eq(#bad, 0, "every value is inside the range Roblox accepts (" .. table.concat(bad, "; ") .. ")")
end

do
	-- every overlay field exists in the bands, so the overlay blends instead of inventing a field
	local bad = {}
	for kind, o in Env.Overlays do
		truthy(Config.Weather.Events[kind] ~= nil, "overlay " .. kind .. " is a weather event")
		for _, part in { "set", "mul" } do
			for g, fields in o[part] or {} do
				for field in fields do
					if bands[1][g] == nil or bands[1][g][field] == nil then
						table.insert(bad, kind .. "." .. part .. "." .. g .. "." .. field)
					end
				end
			end
		end
		truthy(o.weather and o.weather.rate > 0, "overlay " .. kind .. " brings its own weather")
	end
	eq(#bad, 0, "every overlay field is a band field (" .. table.concat(bad, ", ") .. ")")
	for kind in Config.Weather.Events do
		truthy(Env.Overlays[kind] ~= nil, "every weather event has an overlay: " .. kind)
	end
end

--================================================================ hazards per band

eq(#(bands[1].hazards or {}), 0, "the first band (a brand-new player's first ~3 minutes) has no hazards")
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
	for k in Hz.Kinds do
		if not used[k] then table.insert(unused, k) end
		truthy(type(Hz.Names[k]) == "string", k .. " has a banner name")
	end
	eq(#unused, 0, "every hazard kind appears in some band (" .. table.concat(unused, ", ") .. ")")
end

eq(Hz.MinTelegraphSeconds >= 3, true, "every hazard gives at least 3 s of warning")
eq(Hz.IntervalMin, 120, "no more than one hazard per 2 minutes of play")
eq(Hz.IntervalMax, 180, "and at least one per 3 minutes in a hazard band")
for name, k in Hz.Kinds do
	local ring = k.hitRadius + Hz.PlayerRadius
	truthy(ring < 5, string.format("%s: the ring (%.1f studs) is under 5 studs, a step or two out of it", name, ring))
	truthy(k.visualRadius == nil or k.visualRadius >= k.hitRadius,
		name .. ": the hitbox is never bigger than what the player sees")
	truthy(k.speed * k.telegraph <= 72, string.format("%s: the lane is short (%.0f studs) so it starts near the view on flat ground", name, k.speed * k.telegraph))
end
do
	-- a knock's lift, as a height: v^2 / 2g with Roblox's default gravity. There is nothing to reach.
	local lift = Hz.KnockLift * Hz.KnockLift / (2 * 196.2)
	truthy(lift < 0.5, string.format("a knock lifts at most %.2f studs", lift))
	truthy(Hz.KnockLift <= Hazards.MAX_KNOCK_LIFT, "and is within the template's cap")
end
do
	local longest = 0
	for _, k in Hz.Kinds do longest = math.max(longest, k.telegraph + k.pass) end
	eq(longest, 6, "the longest hazard flight is 6.0 s (the dust devil)")
	truthy(Config.Rest.PendingSeconds >= longest + 2,
		string.format("a queued rest (%.1f s) outlives the longest hazard flight (%.1f s) by 2 s", Config.Rest.PendingSeconds, longest))
end

-- The ring stays up while the rest of the flight can still hit someone inside it (plus1-jump's second
-- review, 2026-09-27). Measured with StormGrow's own kinds: 400 players per kind step to a random point
-- inside the ring at the lock and stay; no hit may come while the ring is hidden.
do
	local s = 20260930 % 4294967296
	local function r()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
	local names = {}
	for name in Hz.Kinds do table.insert(names, name) end
	table.sort(names)
	local dt = 1 / 60
	local hidden, stuck, hits = 0, 0, 0
	for _, name in names do
		local k = Hz.Kinds[name]
		local R = k.hitRadius + Hz.PlayerRadius
		for _ = 1, 400 do
			local aim = { x = 0, y = 3, z = 0 }
			local plan = Hazards.plan(Hz, name, aim, r() * 6.283, r, math.rad(-25 + 25 * r()))
			while plan.t < plan.commitAt do
				plan.t += dt
				Hazards.retarget(Hz, plan, aim)
			end
			Hazards.retarget(Hz, plan, aim)
			local rr, ra = R * math.sqrt(r()), r() * 6.283
			local pos = { x = aim.x + rr * math.cos(ra), y = aim.y, z = aim.z + rr * math.sin(ra) }
			local goneAt = nil
			while plan.t < plan.duration do
				local t0 = plan.t
				plan.t += dt
				local live = Hazards.threatLive(plan, Hz.PlayerRadius, t0)
				if goneAt == nil and not live then goneAt = t0 end
				if Hazards.checkHit(plan, t0, plan.t, pos, Hz.PlayerRadius) then
					plan.hit = true
					hits += 1
					if not live then hidden += 1 end
				end
			end
			if goneAt == nil then stuck += 1 end
		end
	end
	print(string.format("  ring rule: 2000 players standing inside the ring, %d hit, %d of them while the ring was hidden", hits, hidden))
	truthy(hits > 1500, "set-up: most players who stay inside the ring are hit (" .. hits .. "/2000)")
	eq(hidden, 0, "no hit ever comes while the ring and banner are hidden")
	eq(stuck, 0, "and the ring goes before the end of every flight")
end

-- No lane starts underground. The glue passes the camera pitch clamped to GroundPitchFloor (-25), so the
-- view window's upper edge is never below 0 degrees and every StormGrow kind (natural pitch 0-10) starts
-- at or above the player's root. Swept at camera pitches -60..+20, every kind, every band.
--
-- FINDING, 2026-09-30 (this spec, first run): DESIGN.md §4 promised "no lane point is ever below ground + 1
-- stud", and the TRUE flight breaks it: a descending lane (crow 6 +- 4 degrees, ball lightning 4 +- 3) flies
-- on past the player for `pass` seconds and reaches 3.21 studs BELOW the ground. The start is fine; the
-- overshoot is not. Fixed in the glue (HazardGlue.drawnY): the hazard is DRAWN no lower than ground + 1, and
-- hits keep using the true (lower) flight, so the clamp can only make a hit less likely than it looks.
local HazardGlue = require("../src/shared/HazardGlue")
do
	eq(Hz.GroundPitchFloor, -25, "the glue's pitch floor is -25 degrees")
	eq(-Hz.GroundPitchFloor, Hz.ViewPitchDegrees, "equal to the view half-window, so the window's top is exactly level")
	local s = 777
	local function r()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
	local lowest, lowestDrawn, lowestStart, total = math.huge, math.huge, math.huge, 0
	for _, b in ipairs(bands) do
		if #(b.hazards or {}) > 0 then
			for camPitch = -60, 20, 10 do
				for _ = 1, 40 do
					local sch = Hazards.newScheduler(Hz, r)
					sch.clock = sch.nextAt
					local aim = { x = 0, y = 3, z = 0 } -- a root 3 studs over ground at y = 0
					local ctx = { resting = false, grounded = true, kinds = b.hazards, aim = aim,
						yaw = r() * 6.283, pitch = HazardGlue.ctxPitch(math.rad(camPitch), Hz) }
					local ev = Hazards.step(sch, Hz, 0.05, ctx, r)
					local plan = ev and ev.plan
					if plan then
						total += 1
						lowestStart = math.min(lowestStart, plan.start.y)
						while plan.t < plan.duration do
							local p = Hazards.positionAt(plan, plan.t)
							lowest = math.min(lowest, p.y)
							lowestDrawn = math.min(lowestDrawn, HazardGlue.drawnY(p.y, 0))
							Hazards.step(sch, Hz, 0.05, ctx, r)
						end
					end
				end
			end
		end
	end
	print(string.format("  %d lanes launched at camera pitches -60..+20: lowest start %.2f, lowest TRUE point %.2f, lowest DRAWN point %.2f studs over the ground",
		total, lowestStart, lowest, lowestDrawn))
	truthy(total > 1000, "set-up: lanes were launched")
	truthy(lowestStart >= 3 - 1e-6, "no lane STARTS below the player's root (the pitch floor works)")
	truthy(lowest < 1, "set-up for the clamp: the true flight does dip below ground + 1 (the finding)")
	truthy(lowestDrawn >= 1, "no DRAWN lane point is ever below ground + 1 stud (HazardGlue.drawnY)")
	eq(HazardGlue.ctxPitch(math.rad(-60), Hz), math.rad(-25), "ctxPitch lifts a steep downward camera to -25")
	eq(HazardGlue.ctxPitch(math.rad(10), Hz), math.rad(10), "and leaves an upward camera alone")
end

-- REVIEW-1: the red ring was drawn 0.05-0.25 studs over the GROUND, inside the porch, the pads and the soil plates, so
-- it was hidden wherever a farmer stands (check_stormgrow_hazards part G measures it from the camera). The glue now
-- knows what a farmer stands on and draws the ring on the highest top under it.
do
	local Farm = require("../src/shared/Farm")
	local F = Config.Farm
	local function at(k, lx, lz) return Farm.toWorld(k, lx, lz, F) end
	local x, z = at(1, 0, F.PadLocalZ)
	eq(HazardGlue.surfaceY(x, z, F, Farm), F.GroundY + 1, "on a farm pad: its top (1 stud)")
	x, z = at(2, -20, F.PorchDepth / 2)
	eq(HazardGlue.surfaceY(x, z, F, Farm), F.GroundY + 0.4, "on a porch: 0.4")
	local tx, tz = Farm.tileLocal(4, 7, F)
	x, z = at(5, tx, tz)
	eq(HazardGlue.surfaceY(x, z, F, Farm), F.GroundY + F.SoilHeight * 0.6, "on a soil plate: 0.6")
	x, z = at(3, F.FieldSize / 2 + F.PathWidth / 2, tz)
	eq(HazardGlue.surfaceY(x, z, F, Farm), F.GroundY + 0.2, "on the bed between fields: 0.2")
	eq(HazardGlue.surfaceY(10, 10, F, Farm), F.GroundY + 0.4, "on the market square: 0.4")
	eq(HazardGlue.surfaceY(0, -14, F, Farm), F.GroundY + 1, "on the market pad: 1")
	eq(HazardGlue.surfaceY(0, 70, F, Farm), F.GroundY, "on the grass between: the ground")
	-- a ring half on the pad, half on the porch, is drawn on the pad's top (else the pad hides its half)
	local px, pz = at(1, F.PadSize / 2 + 1, F.PadLocalZ)
	eq(HazardGlue.ringY(px, pz, 3.5, F, Farm), F.GroundY + 1, "a ring reaching onto the pad is drawn on the pad's top")
	eq(HazardGlue.ringY(0, 70, 3.5, F, Farm), F.GroundY, "a ring on open grass stays on the grass")
end

--================================================================ budgets

local B = Config.Budget
eq(B.MaxHazards, 1, "one hazard at a time")
truthy(B.MaxServerParts <= 1400, "server parts capped at 1,400")
eq(B.MaxCropParts, 6 * 54 * B.MaxPartsPerCrop, "crop parts: six farms x 54 tiles x at most 5 parts")
truthy(B.MaxWeatherEmitters <= 4, "at most 4 weather emitters")
truthy(B.MaxLights <= 12, "at most 12 client lights")
do
	local worst = 0
	for _, b in bands do worst = math.max(worst, b.weather.rate) end
	for _, o in Env.Overlays do worst = math.max(worst, o.weather.rate) end
	truthy(worst <= B.MaxEmitterRate, "no band or event asks for more particles than the budget (" .. worst .. ")")
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
assert(failed == 0, "EnvConfig tests failed")
