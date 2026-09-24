-- Spec for the depot's environment CONFIG: the wings, their hazards, the break and the budgets.
-- Run: luau tests/EnvConfig.spec.luau
--
-- The template modules are tested with their own configs (EnvBands/Hazards/Rest specs). This file
-- checks THIS game's numbers: that the wings blend (no field only some wings set), that transitions
-- happen inside a shift and never cut, that the first shifts are hazard-free, that every hazard can be
-- stepped out of, that the break can never be a panic button, that every id the config names exists in
-- WingArt, that no lighting value strays where the tags and signs would get hard to read, and that
-- every string a player sees uses only the glyphs this game has photographed (CLAUDE.md, Traps).
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Config = require("../src/shared/Config")
local WingArt = require("../src/shared/WingArt")

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
truthy(type(Env) == "table" and type(Hz) == "table" and type(RestCfg) == "table" and type(Budget) == "table",
	"Config has Env, Hazards, Rest and Budget")
if failed > 0 then
	print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
	return
end
local bands = Env.Bands

-- glyphs: ASCII, Latin-1 and the five photographed code points (CLAUDE.md "Glyphs")
local ALLOWED = { [0x2014] = true, [0x2026] = true, [0x2605] = true, [0x1F512] = true, [0xFE0F] = true }
local function glyphsOk(s: string): boolean
	local ok, good = pcall(function()
		for _, cp in utf8.codes(s) do
			if cp >= 0x100 and not ALLOWED[cp] then return false end
		end
		return true
	end)
	return ok and good
end

--================================================================ the wings

do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "the wings validate as bands (" .. tostring(err) .. ")")
	truthy(#bands >= 5, "at least five wings (" .. #bands .. ")")
	eq(bands[1].from, 0, "the first wing is where every career starts")
	eq(#(bands[1].hazards or {}), 0, "no hazards in the first wing: the tutorial and the first layers stay calm")
	truthy(bands[2].from >= Config.Rules.MemoUnlockShift,
		"the first hazard wing opens only after the tutorial, the torn tags and the memo have each had their own shift")
end

local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
for _, g in GROUPS do
	local keys = {}
	for k in bands[1][g] or {} do keys[k] = true end
	truthy(next(keys) ~= nil, "wing 1 sets " .. g)
	for i, b in bands do
		local seen = {}
		for k, v in b[g] or {} do
			seen[k] = true
			if not keys[k] then
				failed += 1
				print("FAIL: wing " .. i .. " sets " .. g .. "." .. k .. " that wing 1 does not (it would never blend back)")
			end
			if type(v) == "table" then
				truthy(#v == 3 and v[1] >= 0 and v[1] <= 255 and v[2] >= 0 and v[2] <= 255 and v[3] >= 0 and v[3] <= 255,
					"wing " .. b.id .. " " .. g .. "." .. k .. " is an {r, g, b} colour")
			end
		end
		for k in keys do
			if not seen[k] then
				failed += 1
				print("FAIL: wing " .. i .. " does not set " .. g .. "." .. k)
			end
		end
	end
end

local ids = {}
for i, b in bands do
	ids[b.id] = true
	eq(b.from, math.floor(b.from), "wing " .. b.id .. " starts at a WHOLE number of completed shifts (it is named by them)")
	if i > 1 then
		truthy(type(b.fade) == "number" and b.fade > 0 and b.fade < 1,
			"wing " .. b.id .. " fades in over part of the shift before it (0 < fade < 1: never a cut, never a shift early)")
	end
	truthy(type(b.name) == "string" and #b.name > 0 and glyphsOk(b.name), "wing " .. b.id .. " has a printable name")
	truthy(type(b.sub) == "string" and glyphsOk(b.sub), "wing " .. b.id .. " has a printable subtitle")
	for _, id in b.pieces or {} do
		truthy(WingArt.hasPiece(id), "wing " .. b.id .. " piece '" .. id .. "' is built by WingArt")
	end
	for _, a in b.ambient or {} do
		truthy(WingArt.hasCritter(a.kind), "wing " .. b.id .. " critter '" .. a.kind .. "' is built by WingArt")
		truthy(Env.Critters[a.kind] ~= nil, "... and has a spawn spec in Config.Env.Critters")
	end
	if b.weather then
		truthy(WingArt.hasWeather(b.weather.kind), "wing " .. b.id .. " weather '" .. b.weather.kind .. "' is built by WingArt")
		truthy(b.weather.rate > 0 and b.weather.rate <= Budget.MaxEmitterRate, "wing " .. b.id .. " weather rate is inside the budget")
	end
	for _, k in b.hazards or {} do
		truthy(Hz.Kinds[k] ~= nil, "wing " .. b.id .. " hazard '" .. k .. "' is a configured kind")
		truthy(WingArt.hasHazardModel(k), "wing " .. b.id .. " hazard '" .. k .. "' has a model")
	end
	-- readability: the tags and signs are read at 5-40 studs; these guard what a renderer would show
	local bl, cc, at, li = b.bloom, b.colorCorrection, b.atmosphere, b.lighting
	truthy(bl.Threshold >= 0.75 and bl.Intensity <= 1.5, "wing " .. b.id .. " bloom leaves white tag text alone (threshold >= 0.75, intensity <= 1.5)")
	truthy(math.min(cc.TintColor[1], cc.TintColor[2], cc.TintColor[3]) >= 200, "wing " .. b.id .. " tint stays near white (every channel >= 200)")
	truthy(math.abs(cc.Brightness) <= 0.08 and cc.Contrast <= 0.25 and cc.Saturation >= -0.2 and cc.Saturation <= 0.35,
		"wing " .. b.id .. " colour correction is mild")
	truthy(at.Density <= 0.35, "wing " .. b.id .. " atmosphere is no hazier than the server's own preset (0.32) allows the bins at 28 studs")
	truthy(li.ExposureCompensation >= -0.2 and li.ExposureCompensation <= 0.7, "wing " .. b.id .. " exposure is sane")
	-- a night wing keeps the bay lit: Ambient carries the tray and bins when the sun is down
	if li.ClockTime >= 19 or li.ClockTime < 5 then
		truthy(math.min(li.Ambient[1], li.Ambient[2], li.Ambient[3]) >= 100, "night wing " .. b.id .. " keeps an ambient of at least 100 per channel")
	end
end
truthy(ids[Env.SpaceBandId] == true, "the brag wing (" .. tostring(Env.SpaceBandId) .. ") is a wing")
do
	local i = EnvBands.indexOf(bands, Env.SpaceBandId)
	truthy(i ~= nil and bands[i :: number].celebrate == true, "reaching the brag wing is celebrated")
end
truthy(Env.HalfLife > 0 and Env.HalfLife <= 1, "values glide (half-life " .. tostring(Env.HalfLife) .. " s)")
do
	-- the roof fades as the camera rises: gone by the wall tops (every overhead part sits above them, which
	-- robloxemu/check_lostfounddepot_wings.luau measures), in full well below them
	local f = Env.OverheadFade
	truthy(type(f) == "table" and type(f.Full) == "number" and type(f.Gone) == "number", "Config.Env.OverheadFade is set")
	truthy(f.Gone <= Config.Bay.WallHeight, string.format("the roof is gone by the time the camera reaches the wall tops (Gone %.1f <= %d)", f.Gone, Config.Bay.WallHeight))
	truthy(f.Full < f.Gone and f.Gone - f.Full >= 2, "and fades over at least 2 studs of camera height (never a cut when the zoom moves)")
	truthy(f.Full >= 12, "a sorting camera (8-16 studs back, up to ~12 studs high) sees the whole roof")
end
truthy(Env.LightingHz > 0 and Env.LightingHz <= 15, "Lighting is written at most 15 times a second")

-- continuity across every transition, sampled the way the client samples (progress in 1/30 steps = one sort)
do
	local worst = 0
	for p = 0, (bands[#bands].from + 2) * 30 do
		local a = EnvBands.weights(bands, p / 30)
		local b = EnvBands.weights(bands, (p + 1) / 30)
		for i = 1, #bands do
			worst = math.max(worst, math.abs((a[i] or 0) - (b[i] or 0)))
		end
	end
	truthy(worst <= 0.35, string.format("one sort never moves a wing's weight by more than 0.35 (worst %.3f; the half-life glides the rest)", worst))
end

-- The client shows the scenery, critters and weather of the two strongest wings only (Wings.keepStrongest),
-- and a wing has one weather kind at most (the schema has one `weather` field). So at most two weather
-- emitters are ever wanted, and two wings' weather at full rate must fit the particle budget: then
-- EnvBands.capRates in WingArt is defence in depth that never has to bind with this config.
do
	local topRate, top2 = 0, 0
	for _, b in bands do
		local r = if b.weather then b.weather.rate else 0
		if r > topRate then top2 = topRate; topRate = r elseif r > top2 then top2 = r end
	end
	truthy(topRate + top2 <= Budget.MaxEmitterRate, string.format("the two heaviest wings' weather together fits the particle budget (%d + %d <= %d)",
		topRate, top2, Budget.MaxEmitterRate))
	truthy(Budget.MaxWeatherEmitters >= 2, "two weather emitters are allowed (two wings blend at a seam)")
end

--================================================================ critters stay out of the bay

for kind, spec in Env.Critters do
	truthy(spec.rMin >= 60, "critter " .. kind .. " spawns at least 60 studs out (outside the 72 x 56 bay)")
	truthy(spec.yMin >= 25, "critter " .. kind .. " flies at least 25 studs above the camera (over the 16-stud walls)")
	truthy(spec.rMax > spec.rMin and spec.yMax > spec.yMin and spec.speedMax >= spec.speedMin, "critter " .. kind .. " ranges are ordered")
	truthy(WingArt.hasCritter(kind), "critter spec " .. kind .. " has a model")
end

--================================================================ hazards

do
	local ok, err = Hazards.validate(Hz)
	truthy(ok, "Config.Hazards validates (" .. tostring(err) .. ")")
	eq(Hz.IntervalMin, 120, "at most one hazard per 2 minutes of running shift clock")
	eq(Hz.IntervalMax, 180, "at least one per 3 minutes")
	truthy(Hz.FloorMargin >= 1 and Hz.MinLaneStuds >= 8, "lanes start off the walls and at least 8 studs out")
	local used = {}
	for _, b in bands do
		for _, k in b.hazards or {} do used[k] = true end
	end
	local longest = 0
	for name, k in Hz.Kinds do
		truthy(used[name] == true, "hazard kind " .. name .. " is used by a wing")
		truthy(type(k.label) == "string" and #k.label > 0 and glyphsOk(k.label), "hazard kind " .. name .. " has a printable label")
		local ring = k.hitRadius + Hz.PlayerRadius
		-- stepping out of the ring from its centre at the slowest walk speed must take well under the lock time
		local out = ring / Config.Economy.WalkSpeed[1]
		truthy(out <= k.commit / 3, string.format("hazard %s: walking out of the %.1f-stud ring takes %.2f s, a third of its %.1f s lock at most", name, 2 * ring, out, k.commit))
		truthy(2 * ring <= 8, "hazard " .. name .. " ring fits between two tray columns and the arc (<= 8 studs across)")
		truthy(k.knock <= 30, "hazard " .. name .. " is a stumble, not a launch (knock <= 30 studs/s)")
		longest = math.max(longest, k.telegraph + k.pass)
	end
	truthy(Hz.KnockLift <= 8, "a knock lifts at most 8 studs/s (0.16 studs: never onto the tray step)")
	truthy(Hz.KnockSeconds <= 0.8, "the stumble lasts at most 0.8 s")
	-- THE PROMISE (EYECANDY.md §3), pinned to literals (REVIEW-2 finding 6: MinReactSeconds = 0 once passed every
	-- gate, because every gate compared the measured time against the same Config value). The hit rule
	-- (Wings.checkHit) enforces whatever these say, so they may be raised, never lowered below the promise.
	truthy(type(Hz.MinReactSeconds) == "number" and Hz.MinReactSeconds >= 1.0,
		string.format("a knock needs at least 1 s inside the red ring: MinReactSeconds >= 1.0 (%s)", tostring(Hz.MinReactSeconds)))
	truthy(type(Hz.MinWarnSeconds) == "number" and Hz.MinWarnSeconds >= 2.0,
		string.format("and at least 2 s of warning: MinWarnSeconds >= 2.0 (%s)", tostring(Hz.MinWarnSeconds)))
	truthy(Hz.MinWarnSeconds <= Hz.MinTelegraphSeconds,
		"the warning floor is inside every kind's telegraph (a still player is reached at arrival)")
	truthy(RestCfg.PendingSeconds >= longest + 2,
		string.format("a booked break outlives the longest hazard flight (%.1f s) by 2 s (%.1f)", longest, RestCfg.PendingSeconds))
end

--================================================================ the break

do
	local ok, err = Rest.validate(RestCfg)
	truthy(ok, "Config.Rest validates (" .. tostring(err) .. ")")
	eq(RestCfg.WakeOnMove, true, "moving always ends a rest")
	eq(RestCfg.BlockWhileThreat, true, "a rest never starts with a hazard in the air")
end

--================================================================ budgets

do
	for _, k in { "MaxLocalParts", "MaxEmitters", "MaxWeatherEmitters", "MaxEmitterRate", "MaxBeams", "MaxTrails", "MaxLights", "MaxHazards" } do
		truthy(type(Budget[k]) == "number" and Budget[k] > 0, "Budget." .. k .. " is set")
	end
	truthy(Budget.MaxWeatherEmitters <= Budget.MaxEmitters, "weather emitters fit inside the emitter budget")
	eq(Budget.MaxHazards, 1, "one hazard at a time")
	truthy(Budget.MaxLocalParts <= 220, "at most 220 local parts (the +1 Jump phone budget)")
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
