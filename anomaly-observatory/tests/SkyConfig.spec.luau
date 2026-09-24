-- Spec for the game's own sky configuration (Config.Sky). Run: luau tests/SkyConfig.spec.luau
--
-- NightSky.spec proves the functions. This file proves the NUMBERS this game ships with, against
-- the rules that keep the sky from ever touching the game it decorates:
--   * every piece of sky, and everything that moves through it, stays BEYOND the hall's entrance
--     plane with Clearance to spare. The hall is sealed except that entrance (+Z, behind the spawn and
--     behind the marketing rig's camera), so nothing beyond it can be seen from inside the hall, in its
--     mirror, or in the rig's crop, whatever the Day;
--   * no colour in the sky is reddish (two anomalies are "a red panel" and "a red window");
--   * the sky casts no light, so it cannot change how the hall is lit;
--   * the telescope break looks away from every hall for every drift pose and every screen shape;
--   * rest is the template's Rest with nothing to pause: no idle timer, wake on move, and a queued
--     break outlives the death beat;
--   * bands start on whole Days, fade in (never cut), and every band defines every feature.
local NightSky = require("../src/shared/NightSky")
local EnvBands = require("../src/shared/EnvBands")
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

local Sky = Config.Sky
truthy(type(Sky) == "table", "Config.Sky exists")

do
	local ok, err = NightSky.validate(Sky, EnvBands, Rest)
	truthy(ok, "Config.Sky validates (" .. tostring(err) .. ")")
end

-- ------------------------------------------------------------------ the hall
-- These mirror the server's zoneOrigin / buildClean (Main.server.luau). The server is not edited by
-- this work; robloxemu/check_anomalyobservatory_sky.luau measures them against the zone it builds.
eq(Sky.Hall.Spacing, 1000, "halls are 1000 studs apart on X (zoneOrigin)")
eq(Sky.Hall.OriginY, 100, "halls sit at y = 100 (zoneOrigin)")
eq(Sky.Hall.Front, 10, "the floor, walls and ceiling end at z = +10: the open entrance")
truthy(Sky.Clearance >= 4, "the sky keeps at least 4 studs beyond the entrance plane")

-- ------------------------------------------------------------------ bands
local bands = Sky.Bands
eq(#bands, 8, "eight bands")
local ids = {}
for i, b in bands do
	ids[b.id] = i
	truthy(type(b.name) == "string" and #b.name > 0 and type(b.emoji) == "string" and #b.emoji > 0,
		"band " .. tostring(b.id) .. " has a name and an emoji")
end
eq(bands[1].from, 0, "the first band covers Day 1")
eq(EnvBands.indexAt(bands, Config.Progression.StartDay), 1, "a fresh night (StartDay) is in the first band")
truthy(ids[Sky.Pacing.Headline] ~= nil, "the headline band exists (" .. tostring(Sky.Pacing.Headline) .. ")")
for i = 2, #bands do
	truthy(bands[i].from - bands[i - 1].from >= 3,
		string.format("band %s starts at least 3 Days after %s, so every band is on screen for several passes", bands[i].id, bands[i - 1].id))
	truthy(bands[i].fade >= 1, "band " .. bands[i].id .. " fades in over at least a Day")
end
-- The last band is reachable (MaxDay is the streak cap).
truthy(bands[#bands].from < Config.Progression.MaxDay, "the last band starts below MaxDay")
-- The first band is quiet: nothing moves in it but the stars and the moon's phase.
eq(bands[1].features.meteors, 0, "no meteors on the first night")
eq(bands[1].features.storm, 0, "no storm on the first night")

-- continuity: no feature weight moves more than 0.6 between consecutive Days, so even the Day that
-- completes a fade is a partial step, and a reset back to Day 1 is a glide (client) not a cut.
do
	local worst, at = 0, ""
	for d = 1, 120 do
		local a = NightSky.features(bands, EnvBands, d)
		local b = NightSky.features(bands, EnvBands, d + 1)
		for k, v in a do
			local dv = math.abs(b[k] - v)
			if dv > worst then worst, at = dv, string.format("%s at Day %d -> %d", k, d, d + 1) end
		end
	end
	truthy(worst <= 0.6 + 1e-9, string.format("the biggest one-Day step in any feature is %.2f (%s)", worst, at))
end

-- The moon turns at a capped speed: a reset from any Day back to Day 1, played at 30 frames a second,
-- never fades the moon or its shade by more than 0.03 in a frame (the sky check's "no hard cut").
do
	truthy(type(Sky.Moon.MaxTurnPerSecond) == "number" and Sky.Moon.MaxTurnPerSecond > 0, "Moon.MaxTurnPerSecond is set")
	local worst, worstFrom = 0, 0
	for from = 2, 80 do
		local p = NightSky.moonPhase(Sky.Moon, from)
		local goal = NightSky.moonPhase(Sky.Moon, 1)
		local last = NightSky.moonDraw(p)
		for _ = 1, 30 * 90 do
			p = NightSky.phaseApproach(p, goal, 1 / 30, Sky.GlideHalfLife, Sky.Moon.MaxTurnPerSecond)
			local d = NightSky.moonDraw(p)
			local step = math.max(math.abs(d.moonAlpha - last.moonAlpha), math.abs(d.shadeAlpha - last.shadeAlpha))
			if step > worst then worst, worstFrom = step, from end
			last = d
		end
	end
	truthy(worst <= 0.03, string.format("a reset from any Day 2..80 back to Day 1 fades the moon at most %.4f per frame (worst from Day %d)", worst, worstFrom))
end

-- ------------------------------------------------------------------ geometry: beyond the entrance
local origin = NightSky.hallOrigin(Sky.Hall, 7)
local eye = NightSky.eye(Sky.Hall, origin)
local pieces = NightSky.layout(Sky, origin)
local envelopes = NightSky.envelopes(Sky, origin)
truthy(#pieces >= 40, "the layout builds the scenery (" .. #pieces .. " pieces)")
do
	local keys, dup = {}, nil
	local tooNear, badColour, reddish, badTrans = {}, {}, {}, {}
	local byFeature = {}
	for _, p in pieces do
		if keys[p.key] then dup = p.key end
		keys[p.key] = true
		byFeature[p.feature] = (byFeature[p.feature] or 0) + 1
		-- the exact oriented box SkyArt builds (NightSky.pieceAxes), not a bounding sphere
		local nearZ = NightSky.pieceMinZ(p, eye) - origin.z
		if nearZ <= Sky.Hall.Front + Sky.Clearance then
			table.insert(tooNear, string.format("%s (nearest corner z %.1f)", p.key, nearZ))
		end
		local c = Sky.Palette[p.color]
		if c == nil then
			table.insert(badColour, p.key .. " -> " .. tostring(p.color))
		elseif NightSky.isReddish(c) then
			table.insert(reddish, p.key)
		end
		if not (p.transparency >= 0 and p.transparency <= 1) then table.insert(badTrans, p.key) end
	end
	eq(dup, nil, "every piece has a unique key")
	eq(#tooNear, 0, "every piece stays beyond the entrance plane + Clearance: " .. table.concat(tooNear, ", "))
	eq(#badColour, 0, "every piece's colour is in the palette: " .. table.concat(badColour, ", "))
	eq(#reddish, 0, "no piece is reddish: " .. table.concat(reddish, ", "))
	eq(#badTrans, 0, "every transparency is in [0, 1]")
	for _, f in NightSky.FEATURES do
		truthy((byFeature[f] or 0) >= 1, "feature " .. f .. " has at least one piece")
	end
	truthy((byFeature.land or 0) >= 10, "the land (ridge, mist, valley lights) is there on every night")
end
do
	local near = {}
	for _, e in envelopes do
		if e.min.z - origin.z <= Sky.Hall.Front + Sky.Clearance then
			table.insert(near, string.format("%s (min z %.1f)", e.key, e.min.z - origin.z))
		end
	end
	truthy(#envelopes >= 6, "every moving thing declares an envelope (" .. #envelopes .. ")")
	eq(#near, 0, "everything that moves (meteors, lightning, aurora sway, comet tail, rain, turning stars) stays beyond the entrance: " .. table.concat(near, ", "))
	local names = {}
	for _, e in envelopes do names[e.key] = true end
	for _, k in { "Meteors", "Lightning", "Aurora", "CometTail", "Rain", "Spiral", "Stars" } do
		truthy(names[k], "envelope " .. k .. " is declared")
	end
end
-- The same holds for a hall far out on the X axis: every test is relative to the hall's own origin.
do
	local far = NightSky.hallOrigin(Sky.Hall, 40)
	local farEye = NightSky.eye(Sky.Hall, far)
	local ok = true
	for _, p in NightSky.layout(Sky, far) do
		if NightSky.pieceMinZ(p, farEye) - far.z <= Sky.Hall.Front + Sky.Clearance then ok = false end
	end
	truthy(ok, "hall 40 (x = 40 000) is just as clear")
end
-- Every palette colour, used or not, is not reddish (a later edit must not add one quietly).
do
	local red = {}
	for name, c in Sky.Palette do
		if NightSky.isReddish(c) then table.insert(red, name) end
	end
	eq(#red, 0, "no palette colour is reddish: " .. table.concat(red, ", "))
end

-- ------------------------------------------------------------------ the telescope break
do
	local view = Sky.RestView
	local worst = math.huge
	local zOk, roofOk = true, true
	for i = 0, 2400 do
		local pose = NightSky.restPose(view, i * 0.5)
		if pose.pos.z <= Sky.Hall.Front + Sky.Clearance then zOk = false end
		if pose.pos.y <= Sky.Hall.Top then roofOk = false end
		for _, aspect in { 4 / 3, 16 / 9, 19.5 / 9, 21 / 9, view.MaxAspect } do
			worst = math.min(worst, NightSky.minRayZ(pose.look, view.FovDegrees, aspect))
		end
	end
	truthy(zOk, "the break camera is beyond the entrance plane + Clearance")
	truthy(roofOk, "and above the roof, belt and braces")
	truthy(worst > 0.1, string.format("every ray it can draw heads away from the halls (worst +Z component %.3f)", worst))
	truthy(view.MaxAspect >= 32 / 9 - 1e-9, "the proof covers screens up to 32:9")
	truthy(view.FovDegrees >= 70, "and a field of view at least Roblox's default 70")
	-- the camera is not inside any piece of sky
	local inside = {}
	local cam = { x = origin.x + view.Offset[1], y = origin.y + view.Offset[2], z = origin.z + view.Offset[3] }
	for _, p in pieces do
		if p.transparency < 1 and NightSky.pieceContains(p, eye, cam, 5) then
			table.insert(inside, p.key)
		end
	end
	eq(#inside, 0, "the break camera is not inside a visible piece: " .. table.concat(inside, ", "))
	truthy(view.FadeSeconds > 0 and view.FadeSeconds <= 0.6, "the break fades through black, briefly")
end

-- ------------------------------------------------------------------ rest
do
	local ok, err = Rest.validate(Sky.Rest)
	truthy(ok, "Sky.Rest passes the template's Rest.validate (" .. tostring(err) .. ")")
	eq(Sky.Rest.IdleSeconds, 0, "no idle rest: nothing in this game needs pausing")
	eq(Sky.Rest.WakeOnMove, true, "moving ends a break")
	truthy(Sky.DeathBeatSeconds >= 2.5, "the death beat covers the server's 2.5 s pause")
	truthy(Sky.Rest.PendingSeconds > Sky.DeathBeatSeconds, "a break asked for during the death beat outlives it")
end

-- ------------------------------------------------------------------ engine sizes (review 2026-09-24)
-- Roblox forces a Ball uniform, draws a Cylinder round (Y = Z) and clamps every Part axis to 2048
-- studs; the emulator keeps whatever is written. The storm's clouds were Balls sized (2r, 1.3r, 2r)
-- and the Milky Way a 2200-stud Block: both measured fine headless and would draw differently.
do
	local bad = {}
	for _, p in pieces do
		local ok, why = NightSky.engineSizeOk(p)
		if not ok then table.insert(bad, p.key .. " (" .. tostring(why) .. ")") end
	end
	eq(#bad, 0, "every piece has a size the engine draws as designed: " .. table.concat(bad, "; "))
	-- the cloud bank keeps its designed shape: flattened, so it must be an Ellipsoid, not a Ball
	local clouds, flat = 0, 0
	for _, p in pieces do
		if string.match(p.key, "^StormCloud%d") then
			clouds += 1
			if p.shape == "Ellipsoid" and p.size.y < p.size.x and p.size.y < p.size.z then flat += 1 end
		end
	end
	eq(clouds, Sky.Storm.CloudCount, "every storm cloud is laid out")
	eq(flat, clouds, "every storm cloud is a flattened Ellipsoid (a low cloud bank, as designed)")
	eq(Sky.IdleKickMinutes, 20, "the break caption states Roblox's 20-minute idle disconnect")
end

-- ------------------------------------------------------------------ budget
do
	local B = Sky.Budget
	eq(B.MaxLights, 0, "the sky casts no light")
	truthy(B.MaxParts <= 160, "part budget sized for a phone (" .. tostring(B.MaxParts) .. ")")
	truthy(B.MaxEmitters >= 1 and B.MaxEmitters <= 3, "at most three emitters")
	truthy(B.MaxEmitterRate <= 60, "at most 60 particles per second")
	truthy(B.MaxBeams <= 8 and B.MaxTrails <= 4, "beams and trails capped")
	-- everything the layout could ever build at once (pools included) still fits the part budget
	local live = 0
	for _, p in pieces do if p.live then live += 1 end end
	truthy(live >= Sky.Meteors.Pool + 3, "the layout includes the meteor pool and the three bolt segments (" .. live .. " live)")
	truthy(#pieces <= B.MaxParts,
		string.format("even with every feature built at once, %d pieces (%d of them live) <= %d", #pieces, live, B.MaxParts))
	-- no feature's own emitter asks for more than the whole budget
	truthy(Sky.Rain.Rate <= B.MaxEmitterRate and Sky.Stars.Rate <= B.MaxEmitterRate, "no single emitter exceeds the rate budget")
end

print(string.format("SkyConfig: %d passed, %d failed", passed, failed))
assert(failed == 0, "SkyConfig tests failed")
