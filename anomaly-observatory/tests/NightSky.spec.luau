-- Spec for NightSky: the pure half of "the night sky outside progresses with the Day".
-- Run: luau tests/NightSky.spec.luau
--
-- NightSky knows nothing about Roblox. It answers, from plain numbers:
--   * where the hall is and whether a piece of sky is safely BEYOND its entrance. The hall is a sealed
--     box open only at +Z, so anything beyond the entrance plane can never be seen from inside the hall,
--     in its mirror, or in the marketing rig's crop, which looks down the hall toward -Z;
--   * the moon's phase for a Day, and how far to slide a dark disc across it to draw that phase;
--   * which band a Day is in, when a new band has been reached, and what the chip should say;
--   * a deterministic schedule for meteors and silent lightning, driven by the sky's own clock;
--   * the telescope-break camera pose, and a proof that no ray from it can enter any hall;
--   * whether a colour is "reddish", because two anomalies are a red wall panel and a red window,
--     and the sky must never teach the player that red is normal.
-- It takes its dependencies (EnvBands, Rest) as arguments: `require("./X")` is invalid in Roblox.
local NightSky = require("../src/shared/NightSky")
local EnvBands = require("../src/shared/EnvBands")
local Rest = require("../src/shared/Rest")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, msg, tol)
	tol = tol or 1e-6
	if type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

-- ------------------------------------------------------------------ geometry
local hall = { Spacing = 1000, OriginY = 100, HalfWidth = 10.5, Bottom = -0.5, Top = 16.5, Back = -90, Front = 10, EyeHeight = 6 }
do
	local o = NightSky.hallOrigin(hall, 3)
	eq(o.x, 3000, "hallOrigin x = index * Spacing")
	eq(o.y, 100, "hallOrigin y = OriginY")
	eq(o.z, 0, "hallOrigin z = 0")
	local e = NightSky.eye(hall, o)
	eq(e.y, 106, "the eye is EyeHeight above the floor")

	local eye = { x = 0, y = 6, z = 0 }
	local p = NightSky.skyPoint(eye, 0, 0, 100)
	approx(p.x, 0, "az 0 el 0 points straight out of the entrance (+Z): x")
	approx(p.y, 6, "az 0 el 0: y")
	approx(p.z, 100, "az 0 el 0: z")
	p = NightSky.skyPoint(eye, 90, 0, 100)
	approx(p.x, 100, "az 90 turns toward +X")
	approx(p.z, 0, "az 90: z", 1e-9)
	p = NightSky.skyPoint(eye, 0, 90, 100)
	approx(p.y, 106, "el 90 is straight up")
	approx(p.z, 0, "el 90: z", 1e-9)
	p = NightSky.skyPoint(eye, -30, 20, 500)
	approx(math.sqrt(p.x ^ 2 + (p.y - 6) ^ 2 + p.z ^ 2), 500, "skyPoint keeps the distance")
	truthy(p.x < 0, "negative azimuth is toward -X")

	local origin = { x = 0, y = 100, z = 0 }
	truthy(NightSky.clearOfHall(hall, origin, { x = 0, y = 100, z = 20 }, 5, 4), "a sphere whose near side is 15 studs out clears a 4-stud margin")
	truthy(not NightSky.clearOfHall(hall, origin, { x = 0, y = 100, z = 20 }, 7, 4), "13 studs out does not clear 14")
	truthy(not NightSky.clearOfHall(hall, origin, { x = 500, y = 100, z = -300 }, 1, 4), "anything behind the entrance plane fails, however far to the side")
	truthy(NightSky.clearOfHall(hall, { x = 7000, y = 100, z = 0 }, { x = 7000, y = 300, z = 400 }, 50, 6), "the test is relative to the hall's own origin")
end

-- ------------------------------------------------------------------ oriented pieces
-- SkyArt builds each Part with CFrame.fromMatrix(pos, X, Y, Z) from pieceAxes, and the clearance
-- proof uses pieceCorners of the SAME axes, so the two cannot disagree. The axes must be a proper
-- rotation (unit, orthogonal, right-handed) or fromMatrix would shear the part.
do
	local eye = { x = 0, y = 6, z = 0 }
	local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
	local function cross(a, b)
		return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
	end
	local shapes = {
		{ shape = "Block", face = true, pos = NightSky.skyPoint(eye, 20, 30, 500), size = { x = 100, y = 40, z = 2 } },
		{ shape = "Block", face = true, roll = 28, pos = NightSky.skyPoint(eye, -10, 45, 900), size = { x = 2200, y = 140, z = 4 } },
		{ shape = "Cylinder", face = true, pos = NightSky.skyPoint(eye, -34, 40, 800), size = { x = 2, y = 76, z = 76 } },
		{ shape = "Cylinder", face = true, tilt = 72, pos = NightSky.skyPoint(eye, 30, 28, 760), size = { x = 0.6, y = 46, z = 46 } },
		{ shape = "Wedge", pos = NightSky.skyPoint(eye, -50, 0, 640), size = { x = 60, y = 150, z = 200 } },
		{ shape = "Wedge", mirror = true, pos = NightSky.skyPoint(eye, 50, 0, 640), size = { x = 60, y = 150, z = 200 } },
		{ shape = "Ball", pos = { x = 0, y = 50, z = 300 }, size = { x = 10, y = 10, z = 10 } },
	}
	local proper = true
	for i, p in shapes do
		local a = NightSky.pieceAxes(p, eye)
		local okUnit = math.abs(dot(a.X, a.X) - 1) < 1e-9 and math.abs(dot(a.Y, a.Y) - 1) < 1e-9 and math.abs(dot(a.Z, a.Z) - 1) < 1e-9
		local okOrtho = math.abs(dot(a.X, a.Y)) < 1e-9 and math.abs(dot(a.Y, a.Z)) < 1e-9 and math.abs(dot(a.X, a.Z)) < 1e-9
		local c = cross(a.X, a.Y)
		local okHand = dot(c, a.Z) > 0.999999
		if not (okUnit and okOrtho and okHand) then
			proper = false
			print("   piece " .. i .. " (" .. p.shape .. ") axes are not a proper rotation")
		end
	end
	truthy(proper, "every piece's axes are a proper rotation (unit, orthogonal, right-handed)")

	-- a slab facing the eye has its thin axis (Z) pointing at the eye
	local slab = shapes[1]
	local a = NightSky.pieceAxes(slab, eye)
	local toEye = { x = eye.x - slab.pos.x, y = eye.y - slab.pos.y, z = eye.z - slab.pos.z }
	local l = math.sqrt(dot(toEye, toEye))
	approx(dot(a.Z, toEye) / l, 1, "a faced slab's Z axis points at the eye")
	-- a disc facing the eye has its axis (X) pointing at the eye
	local disc = shapes[3]
	local ad = NightSky.pieceAxes(disc, eye)
	local toEye2 = { x = eye.x - disc.pos.x, y = eye.y - disc.pos.y, z = eye.z - disc.pos.z }
	approx(dot(ad.X, toEye2) / math.sqrt(dot(toEye2, toEye2)), 1, "a faced disc's axis points at the eye")
	-- a ridge stands upright and shows its triangle to the eye
	local ar = NightSky.pieceAxes(shapes[5], eye)
	approx(ar.Y.y, 1, "a ridge is upright")
	truthy(ar.X.z < 0, "a ridge's profile axis points back toward the eye (it is out at +Z)")
	local am = NightSky.pieceAxes(shapes[6], eye)
	truthy(am.X.z > 0, "a mirrored ridge faces the other way")

	-- corners: a world-aligned ball's box, exactly
	local corners = NightSky.pieceCorners(shapes[7], eye)
	eq(#corners, 8, "a box has eight corners")
	approx(NightSky.pieceMinZ(shapes[7], eye), 295, "a world-aligned 10-stud ball's nearest corner is 5 studs in front of it")
	-- a huge slab facing the eye from high up reaches far less toward the hall than its bounding
	-- sphere would claim (the star field is 1500 studs wide and still hundreds of studs out)
	local big = { shape = "Block", face = true, pos = NightSky.skyPoint(eye, 0, 38, 820), size = { x = 1500, y = 700, z = 20 } }
	truthy(NightSky.pieceMinZ(big, eye) > 300, string.format("a sky-sized slab facing the eye stays far out (nearest corner z %.0f)", NightSky.pieceMinZ(big, eye)))
	truthy(big.pos.z - NightSky.pieceRadius(big) < 0, "where its bounding sphere would have reached behind the hall")

	truthy(NightSky.pieceContains(shapes[7], eye, { x = 0, y = 50, z = 300 }, 0), "a ball contains its centre")
	truthy(not NightSky.pieceContains(shapes[7], eye, { x = 0, y = 50, z = 312 }, 0), "and not a point 12 studs off")
	truthy(NightSky.pieceContains(shapes[7], eye, { x = 0, y = 50, z = 312 }, 8), "unless padded")
	truthy(not NightSky.pieceContains(shapes[2], eye, { x = 0, y = 28, z = 64 }, 5),
		"the break camera's spot is NOT inside the Milky Way slab, although inside its bounding sphere")
end

-- ------------------------------------------------------------------ moon
local moon = { SynodicDays = 29.5, PhaseAtDay1 = 0.07 }
do
	approx(NightSky.moonPhase(moon, 1), 0.07, "day 1 is PhaseAtDay1")
	approx(NightSky.moonPhase(moon, 1 + 29.5), 0.07, "one synodic month later the phase repeats", 1e-9)
	approx(NightSky.moonPhase(moon, 2), 0.07 + 1 / 29.5, "the phase advances by 1/SynodicDays per Day")
	local total = true
	for d = -5, 600 do
		local p = NightSky.moonPhase(moon, d)
		if not (p >= 0 and p < 1) then total = false end
	end
	truthy(total, "moonPhase is in [0, 1) for every Day, including nonsense ones")
	approx(NightSky.moonPhase(moon, 0 / 0), 0.07, "NaN is treated as Day 1")
	approx(NightSky.moonPhase(moon, -3), 0.07, "a Day below 1 is treated as Day 1")

	approx(NightSky.litFraction(0), 0, "new moon: nothing lit")
	approx(NightSky.litFraction(0.5), 1, "full moon: all lit")
	approx(NightSky.litFraction(0.25), 0.5, "first quarter: half lit")
	approx(NightSky.litFraction(0.8), NightSky.litFraction(0.2), "waning mirrors waxing")

	approx(NightSky.litAreaFraction(0), 0, "shadow disc exactly over the moon: nothing lit")
	approx(NightSky.litAreaFraction(2), 1, "shadow disc a diameter away: everything lit")
	approx(NightSky.litAreaFraction(5), 1, "further away is still everything")
	approx(NightSky.litAreaFraction(1), (math.pi - (2 * math.pi / 3 - math.sqrt(3) / 2)) / math.pi, "offset of one radius: the textbook lens area", 1e-9)
	local mono = true
	local prev = -1
	for i = 0, 200 do
		local v = NightSky.litAreaFraction(i / 100)
		if v < prev - 1e-12 then mono = false end
		prev = v
	end
	truthy(mono, "sliding the shadow away never un-lights the moon")

	local inverse, monoOff, prevOff = true, true, -1
	for i = 0, 100 do
		local k = i / 100
		local d = NightSky.luneOffset(k)
		if math.abs(NightSky.litAreaFraction(d) - k) > 1e-4 then
			inverse = false
			print("   luneOffset(" .. k .. ") = " .. d .. " lights " .. NightSky.litAreaFraction(d))
		end
		if d < prevOff - 1e-9 then monoOff = false end
		prevOff = d
	end
	truthy(inverse, "luneOffset is the inverse of litAreaFraction: the drawn phase shows the lit fraction")
	truthy(monoOff, "a fuller moon never needs a smaller offset")
	approx(NightSky.luneOffset(0), 0, "new moon: offset 0")
	approx(NightSky.luneOffset(1), 2, "full moon: offset 2 radii")
	approx(NightSky.luneOffset(-1), 0, "k below 0 clamps")
	approx(NightSky.luneOffset(3), 2, "k above 1 clamps")

	local off, side = NightSky.moonShadow(moon, 1)
	eq(side, 1, "a waxing moon (Day 1) is lit on the right")
	approx(off, NightSky.luneOffset(NightSky.litFraction(0.07)), "the offset draws the phase's lit fraction")
	-- phase 0.6 lands at day 1 + 0.53 * 29.5
	local _, side2 = NightSky.moonShadow(moon, 1 + 0.53 * 29.5)
	eq(side2, -1, "a waning moon is lit on the left")

	-- The phase GLIDES on the circle, the short way round. Gliding the shade's offset instead would,
	-- across a full moon (+2 radii -> -2 radii), sweep the dark disc over the whole moon mid-glide.
	approx(NightSky.phaseApproach(0.49, 0.52, 1e9, 1.2), 0.52, "a long glide arrives", 1e-9)
	approx(NightSky.phaseApproach(0.95, 0.05, 1e9, 1.2), 0.05, "and arrives across the wrap", 1e-9)
	local p = NightSky.phaseApproach(0.95, 0.05, 1.2, 1.2)
	truthy(p > 0.95 or p < 0.05, string.format("0.95 -> 0.05 goes forward through new moon, not back through full (%.3f)", p))
	approx(NightSky.phaseApproach(0.2, 0.3, 1.2, 1.2), 0.25, "one half-life covers half the gap", 1e-9)
	local worstLit = 1
	local cur = 0.49
	for _ = 1, 600 do
		cur = NightSky.phaseApproach(cur, 0.52, 1 / 60, 1.2)
		worstLit = math.min(worstLit, NightSky.litFraction(cur))
	end
	truthy(worstLit > 0.99, string.format("gliding across full moon the moon never darkens (lowest lit %.4f)", worstLit))
	approx(NightSky.phaseApproach(0.3, 0.6, 0, 1.2), 0.3, "dt 0 moves nothing", 1e-12)
	approx(NightSky.phaseApproach(0.3, 0.6, 1, 0), 0.6, "half-life 0 snaps")
	-- A speed limit, so a long swing (the reset from a late Day back to Day 1) crosses new moon
	-- slowly enough that the crescent fades out and back in over seconds, not in half a second.
	-- The headless sky check measured 0.106 of transparency in one frame without it.
	approx(NightSky.phaseApproach(0.2, 0.4, 0.5, 1.2, 0.012), 0.206, "capped: 0.5 s moves at most 0.006 of a cycle", 1e-9)
	approx(NightSky.phaseApproach(0.2, 0.2005, 1, 1.2, 0.012), 0.2005 - 0.0005 * 0.5 ^ (1 / 1.2), "under the cap the half-life glide is unchanged", 1e-9)
	approx(NightSky.phaseApproach(0.95, 0.05, 1, 1.2, 0.012), 0.962, "the cap applies across the wrap too", 1e-9)
	do
		local cur, fastest, t = 0.799, 0, 0
		while t < 60 do
			local nxt = NightSky.phaseApproach(cur, 0.07, 1 / 30, 1.2, 0.012)
			local step = math.abs(((nxt - cur + 0.5) % 1) - 0.5)
			fastest = math.max(fastest, step * 30)
			cur = nxt
			t += 1 / 30
		end
		truthy(fastest <= 0.012 + 1e-9, string.format("a Day-52 -> Day-1 reset never turns the moon faster than the cap (%.4f / s)", fastest))
		approx(cur, 0.07, "and still arrives within a minute", 1e-6)
	end

	-- What to draw for a phase
	local full = NightSky.moonDraw(0.5)
	eq(full.showMoon, true, "full moon: the moon shows")
	eq(full.showShade, false, "full moon: no dark disc hanging beside it")
	local new = NightSky.moonDraw(0.0)
	eq(new.showMoon, false, "new moon: nothing is drawn (no dark disc on the sky)")
	eq(new.showShade, false, "new moon: no shade either")
	local cres = NightSky.moonDraw(0.1)
	eq(cres.showMoon and cres.showShade, true, "a crescent is the moon with the shade across it")
	eq(cres.side, 1, "waxing crescent lit on the right")
	approx(cres.offset, NightSky.luneOffset(NightSky.litFraction(0.1)), "its offset draws its lit fraction")
	approx(cres.lit, NightSky.litFraction(0.1), "and it reports the lit fraction")
	eq(NightSky.moonDraw(0.9).side, -1, "waning crescent lit on the left")
	-- The shade and the moon FADE at those thresholds instead of switching: the headless sky check
	-- caught the shade vanishing in one frame as a gliding phase crossed full moon (Day 42 -> 43).
	approx(full.shadeAlpha, 0, "full moon: the shade is fully faded out")
	approx(full.moonAlpha, 1, "full moon: the moon is fully there")
	approx(new.moonAlpha, 0, "new moon: the moon is fully faded out")
	approx(cres.moonAlpha, 1, "a crescent is fully drawn")
	approx(cres.shadeAlpha, 1, "with its shade fully there")
	local worstStep, prevM, prevS = 0, nil, nil
	for i = 0, 20000 do
		local d = NightSky.moonDraw(i / 20000)
		if prevM then
			worstStep = math.max(worstStep, math.abs(d.moonAlpha - prevM), math.abs(d.shadeAlpha - prevS))
		end
		prevM, prevS = d.moonAlpha, d.shadeAlpha
		if (d.moonAlpha > 0) ~= d.showMoon or (d.shadeAlpha > 0 and d.moonAlpha > 0) ~= d.showShade then
			worstStep = math.huge
		end
	end
	truthy(worstStep < 0.02, string.format("over the whole cycle in 1/20000 steps neither fades faster than 0.02 per step (%.4f); show flags agree", worstStep))
end

-- ------------------------------------------------------------------ bands
local F = NightSky.FEATURES
truthy(type(F) == "table" and #F >= 6, "NightSky lists its features")
local function feats(over)
	local t = {}
	for _, k in F do t[k] = 0 end
	for k, v in over do t[k] = v end
	return t
end
local bands = {
	{ id = "a", name = "Alpha", emoji = "A", from = 0, fade = 0, features = feats({ stars = 0.5, moon = 1 }) },
	{ id = "b", name = "Beta", emoji = "B", from = 4, fade = 1, features = feats({ stars = 0.7, moon = 1, meteors = 1 }) },
	{ id = "c", name = "Gamma", emoji = "C", from = 10, fade = 4, features = feats({ stars = 1, moon = 0.5, aurora = 1 }) },
}
do
	local f = NightSky.features(bands, EnvBands, 1)
	approx(f.stars, 0.5, "day 1 is band a")
	approx(f.meteors, 0, "band a has no meteors")
	local all = true
	for _, k in F do if type(f[k]) ~= "number" then all = false end end
	truthy(all, "features() returns every feature as a number")
	f = NightSky.features(bands, EnvBands, 4)
	approx(f.meteors, 1, "day 4 is fully band b (fade 1 starts at 3)")
	f = NightSky.features(bands, EnvBands, 8)
	approx(f.aurora, 0.5, "day 8 is half way through c's 4-day fade (smoothstep 0.5 = 0.5)")
	approx(f.meteors, 0.5, "and b is half faded out")
	f = NightSky.features(bands, EnvBands, 7)
	truthy(f.aurora > 0 and f.aurora < 0.5, "c is already showing faintly two days before it begins")
	f = NightSky.features(bands, EnvBands, 0 / 0)
	approx(f.stars, 0.5, "NaN lands in the first band")
	f = NightSky.features(bands, EnvBands, 10)
	f.aurora = 42
	approx(NightSky.features(bands, EnvBands, 10).aurora, 1, "features() hands out a copy: writing to it cannot change the config")

	eq(NightSky.bandUp(bands, EnvBands, 3, 4), 2, "3 -> 4 enters band b")
	eq(NightSky.bandUp(bands, EnvBands, 4, 5), nil, "4 -> 5 stays in b")
	eq(NightSky.bandUp(bands, EnvBands, 12, 1), nil, "a reset to Day 1 is not announced as a new band")
	eq(NightSky.bandUp(bands, EnvBands, 1, 30), 3, "a jump across several bands names the band you land in")
	eq(NightSky.bandUp(bands, EnvBands, 9, 10), 3, "9 -> 10 enters c even though c was fading in already")
	eq(NightSky.bandUp(bands, EnvBands, 0 / 0, 4), 2, "a NaN previous Day counts as Day 1")
	eq(NightSky.bandUp(bands, EnvBands, 3, 0 / 0), nil, "a NaN new Day says nothing")

	local d = NightSky.describe(bands, EnvBands, 2)
	eq(d.index, 1, "describe: index")
	eq(d.name, "Alpha", "describe: name")
	eq(d.emoji, "A", "describe: emoji")
	eq(d.nextIndex, 2, "describe: next band")
	eq(d.nextIn, 2, "describe: two Days to band b")
	d = NightSky.describe(bands, EnvBands, 11)
	eq(d.id, "c", "describe: the last band")
	eq(d.nextIndex, nil, "the last band has no next")
	eq(d.nextIn, nil, "and no countdown")
end

-- ------------------------------------------------------------------ events
local meteorSpec = { SlotSeconds = 2, Chance = 0.4, Duration = 0.8, AzRange = { -40, 40 }, ElRange = { 18, 55 }, Length = 14, Salt = 11 }
do
	eq(NightSky.slotOf(meteorSpec, 0), 0, "slot 0 starts at t = 0")
	eq(NightSky.slotOf(meteorSpec, 3.99), 1, "t 3.99 is slot 1")
	eq(NightSky.slotOf(meteorSpec, 4), 2, "t 4 is slot 2")

	local a = NightSky.slotEvent(meteorSpec, 17, 99, EnvBands)
	local b = NightSky.slotEvent(meteorSpec, 17, 99, EnvBands)
	eq(a.start, b.start, "slotEvent is deterministic: start")
	eq(a.roll, b.roll, "slotEvent is deterministic: roll")
	local c = NightSky.slotEvent(meteorSpec, 17, 100, EnvBands)
	truthy(c.roll ~= a.roll or c.start ~= a.start, "a different seed gives a different sky")

	local inside, rollOk, hits, n = true, true, 0, 20000
	for s = 0, n - 1 do
		local ev = NightSky.slotEvent(meteorSpec, s, 7, EnvBands)
		if ev.start < s * 2 - 1e-9 or ev.start + ev.duration > (s + 1) * 2 + 1e-9 then inside = false end
		if not (ev.roll >= 0 and ev.roll < 1) then rollOk = false end
		if ev.roll < meteorSpec.Chance then hits += 1 end
	end
	truthy(inside, "every event starts and ENDS inside its own slot, so two never overlap and one pooled part is enough")
	truthy(rollOk, "rolls are in [0, 1)")
	approx(hits / n, 0.4, "at full weight about Chance of the slots carry an event", 0.02)

	local win, down, lengthOk = true, true, true
	for s = 0, 4999 do
		local ev = NightSky.slotEvent(meteorSpec, s, 3, EnvBands)
		local path = NightSky.meteorPath(meteorSpec, ev)
		for _, pt in { path.from, path.to } do
			if pt.az < -40 - 1e-9 or pt.az > 40 + 1e-9 or pt.el < 18 - 1e-9 or pt.el > 55 + 1e-9 then win = false end
		end
		if path.to.el >= path.from.el then down = false end
		local len = math.sqrt((path.to.az - path.from.az) ^ 2 + (path.to.el - path.from.el) ^ 2)
		if math.abs(len - 14) > 1e-6 then lengthOk = false end
	end
	truthy(win, "a meteor starts and ends inside its window of sky")
	truthy(down, "meteors fall")
	truthy(lengthOk, "every meteor streak is Length degrees long")

	local boltSpec = { SlotSeconds = 1.3, Chance = 0.25, Duration = 0.14, AzRange = { -50, 20 }, ElRange = { 2, 12 }, Salt = 23 }
	local boltWin, boltDown, boltN = true, true, true
	for s = 0, 2999 do
		local ev = NightSky.slotEvent(boltSpec, s, 5, EnvBands)
		local pts = NightSky.boltPath(boltSpec, ev)
		if #pts ~= 4 then boltN = false end
		for i, pt in pts do
			if pt.az < -50 - 1e-9 or pt.az > 20 + 1e-9 or pt.el < 2 - 1e-9 or pt.el > 12 + 1e-9 then boltWin = false end
			if i > 1 and pt.el > pts[i - 1].el + 1e-9 then boltDown = false end
		end
	end
	truthy(boltN, "a bolt is three segments (four points)")
	truthy(boltWin, "a bolt stays inside the storm's sector")
	truthy(boltDown, "a bolt runs downward")
end

-- ------------------------------------------------------------------ critters (standard §2, 2026-10-01)
-- docs/complete-game-standard.md §2 asks every band for its own critters, and a genre with no place for
-- hazards (nothing chases you is this game's premise) for harmless RARE events instead. Both are one
-- thing here: wildlife crossing the night outside the entrance, AT MOST ONE flight at a time, about one
-- every 2-3 minutes, the kind following the band. Deterministic from the sky's own clock, like meteors.
local critterSpec = {
	SlotSeconds = 45, Chance = 0.3, Duration = 12, Salt = 37,
	Kinds = {
		fireflies = { Count = 6, Duration = 12, Distance = 180, AzRange = { -30, 30 }, ElRange = { -2, 3 }, Travel = 8,
			Spread = { 5, 1.5 }, Size = { 1.6, 1.6, 1.6 }, Shape = "Ball", Color = "moon", Style = "swarm", BlinkSeconds = 1.3 },
		bats = { Count = 3, Duration = 5, Distance = 240, AzRange = { -44, -4 }, ElRange = { 24, 31 }, Travel = 34,
			Spread = { 1.8, 0.8 }, Size = { 2.6, 0.4, 1.2 }, Shape = "Block", Color = "shade", Style = "flutter" },
		owl = { Count = 1, Duration = 9, Distance = 150, AzRange = { -45, 45 }, ElRange = { 3, 8 }, Travel = 50,
			Spread = { 0, 0.6 }, Size = { 4, 0.5, 1.6 }, Shape = "Block", Color = "moon", Style = "glide" },
		geese = { Count = 5, Duration = 12, Distance = 320, AzRange = { -45, 45 }, ElRange = { 30, 40 }, Travel = 60,
			Spread = { 1.4, 0.8 }, Size = { 3, 0.4, 1.4 }, Shape = "Block", Color = "shade", Style = "vee" },
		wisps = { Count = 4, Duration = 10, Distance = 160, AzRange = { -30, 30 }, ElRange = { 8, 16 }, Travel = 20,
			Spread = { 4, 3 }, Size = { 1.8, 1.8, 1.8 }, Shape = "Ball", Color = "moon", Style = "circle" },
	},
}
do
	local C = NightSky.CRITTERS
	truthy(type(C) == "table" and #C == 5, "NightSky lists five critter kinds")
	local inFeatures = {}
	for _, k in NightSky.FEATURES do inFeatures[k] = true end
	local allIn = true
	for _, k in (C or {}) do
		if not inFeatures[k] then allIn = false end
		truthy(critterSpec.Kinds[k] ~= nil, "the spec's config covers kind " .. tostring(k))
	end
	truthy(allIn, "every critter kind is a band FEATURE, so it glides in and out with its band like everything else")
	truthy(type(NightSky.critterPick) == "function" and type(NightSky.critterPath) == "function"
		and type(NightSky.critterMember) == "function" and type(NightSky.critterReach) == "function"
		and type(NightSky.critterKey) == "function", "the critter functions exist")
end
if type(NightSky.critterPick) == "function" then
	local sky = { Critters = critterSpec, Hall = hall }
	local function rate(weights, n): (number, { [string]: number })
		local hits, by = 0, {}
		for slot = 0, n - 1 do
			local ev = NightSky.slotEvent(critterSpec, slot, 4242, EnvBands)
			local k = NightSky.critterPick(sky, weights, ev)
			if k then
				hits += 1
				by[k] = (by[k] or 0) + 1
			end
		end
		return hits / n, by
	end
	local n = 20000
	local r0 = rate({}, n)
	eq(r0, 0, "no critter weight, no flights (the Storm Front)")
	local r1, by1 = rate({ bats = 1 }, n)
	print(string.format("   critters: %d of %d slots carry a flight at full weight (%.3f; %.2f a minute)", math.floor(r1 * n + 0.5), n, r1,
		r1 * 60 / critterSpec.SlotSeconds))
	approx(r1, 0.3, "one kind at full weight: Chance of the slots carry a flight", 0.02)
	eq(by1.bats, math.floor(r1 * n + 0.5), "and every one of them is that kind")
	local r2, by2 = rate({ bats = 0.5, owl = 0.5 }, n)
	approx(r2, 0.3, "two kinds sharing a band (0.5 + 0.5) fly as often as one", 0.02)
	approx((by2.bats or 0) / (r2 * n), 0.5, "and split the flights between them", 0.03)
	local r3 = rate({ bats = 0.25 }, n)
	approx(r3, 0.075, "a kind fading in (weight 0.25) flies a quarter as often", 0.01)
	local r4 = rate({ bats = 1, owl = 1 }, n)
	approx(r4, 0.3, "two full kinds (a transition) never fly more than Chance allows", 0.02)
	approx(60 / critterSpec.SlotSeconds * critterSpec.Chance, 0.4, "so, at full weight, 0.4 flights a minute: one every 2.5 min")

	-- one at a time: every flight, of every kind, starts and ends inside its own slot
	local inside = true
	for _, k in NightSky.CRITTERS do
		local K = critterSpec.Kinds[k]
		for slot = 0, 1999 do
			local ev = NightSky.slotEvent(critterSpec, slot, 99, EnvBands)
			if ev.start < slot * 45 - 1e-9 or ev.start + K.Duration > (slot + 1) * 45 + 1e-9 then inside = false end
		end
	end
	truthy(inside, "every flight starts and ends inside its slot: never two at once")

	-- paths: the centre of the flock stays in its window and travels Travel degrees, either way
	local winOk, travelOk, bothWays = true, true, { [-1] = false, [1] = false }
	for _, k in NightSky.CRITTERS do
		local K = critterSpec.Kinds[k]
		for slot = 0, 2999 do
			local ev = NightSky.slotEvent(critterSpec, slot, 7, EnvBands)
			local path = NightSky.critterPath(critterSpec, K, ev)
			for _, pt in { path.from, path.to } do
				if pt.az < K.AzRange[1] - 1e-9 or pt.az > K.AzRange[2] + 1e-9 or pt.el < K.ElRange[1] - 1e-9 or pt.el > K.ElRange[2] + 1e-9 then
					winOk = false
				end
			end
			if math.abs(math.abs(path.to.az - path.from.az) - K.Travel) > 1e-6 then travelOk = false end
			bothWays[if path.to.az > path.from.az then 1 else -1] = true
		end
	end
	truthy(winOk, "a flight's centre starts and ends inside its kind's window of sky")
	truthy(travelOk, "and crosses exactly Travel degrees")
	truthy(bothWays[1] and bothWays[-1], "flights go both ways")

	-- members: fade in and out (no pop), stay within critterReach of the centre, keep their formation
	local fadeOk, midOk, reachOk, veeOk = true, true, true, true
	for _, k in NightSky.CRITTERS do
		local K = critterSpec.Kinds[k]
		local rAz, rEl = NightSky.critterReach(K)
		for slot = 0, 199 do
			local ev = NightSky.slotEvent(critterSpec, slot, 11, EnvBands)
			local path = NightSky.critterPath(critterSpec, K, ev)
			local dir = if path.to.az > path.from.az then 1 else -1
			for i = 1, K.Count do
				if NightSky.critterMember(K, path, i, 0, 0).alpha ~= 0 or NightSky.critterMember(K, path, i, 1, K.Duration).alpha ~= 0 then
					fadeOk = false
				end
				for step = 0, 40 do
					local f = step / 40
					local m = NightSky.critterMember(K, path, i, f, f * K.Duration)
					local cAz = path.from.az + (path.to.az - path.from.az) * f
					local cEl = path.from.el + (path.to.el - path.from.el) * f
					if math.abs(m.az - cAz) > rAz + 1e-9 or math.abs(m.el - cEl) > rEl + 1e-9 then reachOk = false end
					if not (m.alpha >= 0 and m.alpha <= 1) then fadeOk = false end
					if math.abs(m.dist - K.Distance) > 1e-9 then reachOk = false end
				end
				local mid = NightSky.critterMember(K, path, i, 0.5, 0.5 * K.Duration)
				if mid.alpha < (if K.Style == "swarm" then 0.3 else 0.99) then midOk = false end
				if K.Style == "vee" and i > 1 then
					local lead = NightSky.critterMember(K, path, 1, 0.5, 0.5 * K.Duration)
					if (mid.az - lead.az) * dir >= 0 then veeOk = false end -- behind the leader
				end
			end
			if K.Style == "vee" and K.Count >= 3 then
				local a = NightSky.critterMember(K, path, 2, 0.5, 0.5 * K.Duration)
				local b = NightSky.critterMember(K, path, 3, 0.5, 0.5 * K.Duration)
				local lead = NightSky.critterMember(K, path, 1, 0.5, 0.5 * K.Duration)
				if math.abs((a.el - lead.el) + (b.el - lead.el)) > 1e-9 or math.abs(a.az - b.az) > 1e-9 then veeOk = false end
			end
		end
	end
	truthy(fadeOk, "every member is invisible at the first and last instant of its flight (it fades, never pops)")
	truthy(midOk, "and shown mid-flight (fireflies blink, but never out)")
	truthy(reachOk, "every member stays within critterReach of the flock's centre, at the kind's Distance")
	truthy(veeOk, "geese fly a V: the leader in front, the others in mirrored pairs behind it")

	-- a flight fades with its band: when the band's weight glides to nothing mid-flight, SkyArt drops the
	-- kind's folder at weight 0.003, so the flight must be (nearly) invisible by then, not cut off mid-air
	truthy(type(NightSky.critterAlpha) == "function", "NightSky.critterAlpha exists")
	if type(NightSky.critterAlpha) == "function" then
		approx(NightSky.critterAlpha(1, 1), 1, "a kind at full weight flies fully visible")
		approx(NightSky.critterAlpha(0.8, 0.5), 0.8, "and at half weight too (two kinds sharing a band are not dimmed)")
		approx(NightSky.critterAlpha(0.6, 0.25), 0.3, "a kind fading out dims with its weight")
		truthy(NightSky.critterAlpha(1, 0.003) <= 0.01, "at the weight where its folder is dropped it is all but gone: "
			.. tostring(NightSky.critterAlpha(1, 0.003)))
		approx(NightSky.critterAlpha(1, 0), 0, "and at weight 0, gone")
	end

	-- the pool: one live part per member, invisible until it flies
	local lay = NightSky.layout(sky, NightSky.hallOrigin(hall, 1))
	local per, okPiece = {}, true
	for _, p in lay do
		if p.role == "critter" then
			per[p.feature] = (per[p.feature] or 0) + 1
			if not p.live or p.transparency ~= 1 or p.key ~= NightSky.critterKey(p.feature, per[p.feature]) then okPiece = false end
		end
	end
	for _, k in NightSky.CRITTERS do
		eq(per[k], critterSpec.Kinds[k].Count, "the layout pools one part per " .. k .. " member")
	end
	truthy(okPiece, "each is live, invisible at rest, and named by critterKey")
	eq(NightSky.budgetOf(sky, lay).parts, 19, "budgetOf counts the critter pool (6 + 3 + 1 + 5 + 4 parts)")
	local env = {}
	for _, e in NightSky.envelopes(sky, NightSky.hallOrigin(hall, 1)) do env[e.key] = e end
	for _, k in NightSky.CRITTERS do
		truthy(env["Critters_" .. k] ~= nil, "an envelope bounds every " .. k .. " flight")
	end
end

-- ------------------------------------------------------------------ the telescope break
local view = { Offset = { 0, 22, 64 }, PitchDegrees = 17, PitchSwayDegrees = 3, YawSwayDegrees = 6, SwayPeriod = 80, FovDegrees = 70, MaxAspect = 3.6 }
do
	local p0 = NightSky.restPose(view, 0)
	eq(p0.pos.x, 0, "the break camera sits at Offset: x")
	eq(p0.pos.y, 22, "y")
	eq(p0.pos.z, 64, "z")
	approx(math.sqrt(p0.look.x ^ 2 + p0.look.y ^ 2 + p0.look.z ^ 2), 1, "look is a unit vector")
	approx(math.deg(math.asin(p0.look.y)), 17, "t = 0 looks up PitchDegrees", 1e-6)
	approx(p0.look.x, 0, "t = 0 looks straight out (yaw 0)", 1e-9)

	local yawOk, pitchOk = true, true
	local maxYaw, maxPitch, minPitch = 0, -90, 90
	for i = 0, 4000 do
		local t = i * 0.25
		local pose = NightSky.restPose(view, t)
		local yaw = math.deg(math.atan2(pose.look.x, pose.look.z))
		local pitch = math.deg(math.asin(pose.look.y))
		maxYaw = math.max(maxYaw, math.abs(yaw))
		maxPitch = math.max(maxPitch, pitch)
		minPitch = math.min(minPitch, pitch)
		if math.abs(yaw) > 6 + 1e-6 then yawOk = false end
		if pitch > 20 + 1e-6 or pitch < 14 - 1e-6 then pitchOk = false end
	end
	truthy(yawOk, "the slow drift never swings more than YawSwayDegrees")
	truthy(pitchOk, "and pitch stays within PitchDegrees +- PitchSwayDegrees")
	truthy(maxYaw > 5, "the drift is real (it pans), max yaw " .. string.format("%.2f", maxYaw))

	-- minRayZ: the smallest +Z component of any ray the camera can draw
	local straight = { x = 0, y = 0, z = 1 }
	local tv = math.tan(math.rad(35))
	local th = tv * 16 / 9
	approx(NightSky.minRayZ(straight, 70, 16 / 9), 1 / math.sqrt(1 + tv * tv + th * th), "looking straight out, the corner ray is the least outward")
	truthy(NightSky.minRayZ({ x = 1, y = 0, z = 0 }, 70, 16 / 9) < 0, "looking sideways, some rays point back toward the hall")
	truthy(NightSky.minRayZ(straight, 70, 32 / 9) < NightSky.minRayZ(straight, 70, 16 / 9), "a wider screen has a less outward corner")
	local up80 = { x = 0, y = math.sin(math.rad(80)), z = math.cos(math.rad(80)) }
	truthy(NightSky.minRayZ(up80, 70, 16 / 9) < 0, "looking nearly straight up, the top edge of the frame leans back over the hall")

	local worst = math.huge
	for i = 0, 1600 do
		local pose = NightSky.restPose(view, i * 0.5)
		for _, aspect in { 4 / 3, 16 / 9, 19.5 / 9, 21 / 9, 3.6 } do
			worst = math.min(worst, NightSky.minRayZ(pose.look, view.FovDegrees, aspect))
		end
	end
	truthy(worst > 0.1, string.format("for every drift pose and every screen up to 32:9, every ray leaves toward +Z (worst %.3f)", worst))
end

-- ------------------------------------------------------------------ colour
do
	truthy(NightSky.isReddish({ 220, 40, 40 }), "the Blood Moon red is reddish")
	truthy(NightSky.isReddish({ 200, 40, 40 }), "the Red Shift panel red is reddish")
	truthy(NightSky.isReddish({ 230, 120, 120 }), "a pink wash still reads as red")
	truthy(NightSky.isReddish({ 200, 60, 90 }), "a crimson with a little blue is red")
	truthy(not NightSky.isReddish({ 240, 180, 90 }), "amber is not red")
	truthy(not NightSky.isReddish({ 205, 140, 85 }), "ochre is not red")
	truthy(not NightSky.isReddish({ 90, 220, 235 }), "cyan is not red")
	truthy(not NightSky.isReddish({ 20, 20, 30 }), "near-black is not red, whatever its hue")
	truthy(not NightSky.isReddish({ 128, 128, 128 }), "grey is not red")
	truthy(not NightSky.isReddish({ 190, 120, 230 }), "violet is not red")
	truthy(not NightSky.isReddish({ 60, 40, 40 }), "a very dark brown is too dark to read as red")
end

-- ------------------------------------------------------------------ validate
local function goodSky()
	return {
		Hall = hall,
		Clearance = 6,
		GlideHalfLife = 1.2,
		Bands = bands,
		Moon = { SynodicDays = 29.5, PhaseAtDay1 = 0.07, MaxTurnPerSecond = 0.012, Azimuth = -22, Elevation = 26, Distance = 700, Radius = 20, Color = "moon", ShadowColor = "shade" },
		Palette = { moon = { 228, 232, 240 }, shade = { 22, 26, 36 } },
		Rest = { WakeOnMove = true, BlockWhileThreat = true, IdleSeconds = 0, PendingSeconds = 4, WakeGraceSeconds = 0.3, RequireGrounded = false },
		DeathBeatSeconds = 3,
		RestView = view,
		Budget = { MaxParts = 170, MaxEmitters = 2, MaxEmitterRate = 60, MaxBeams = 8, MaxTrails = 4, MaxLights = 0 },
		IdleKickMinutes = 20,
	}
end
do
	local ok, err = NightSky.validate(goodSky(), EnvBands, Rest)
	truthy(ok, "a sane sky validates (" .. tostring(err) .. ")")

	local function rejects(mut, why)
		local s = goodSky()
		mut(s)
		local ok2, err2 = NightSky.validate(s, EnvBands, Rest)
		truthy(not ok2, why .. " (err: " .. tostring(err2) .. ")")
	end
	rejects(function(s) s.Bands = { bands[1], bands[2], { id = "c", name = "G", emoji = "C", from = 10, fade = 0, features = bands[3].features } } end,
		"a band with fade 0 would hard-cut")
	rejects(function(s) s.Bands = { bands[1], { id = "b", name = "B", emoji = "B", from = 4.5, fade = 1, features = bands[2].features } } end,
		"a band must start on a whole Day")
	rejects(function(s)
		local f = table.clone(bands[2].features); f.aurora = nil
		s.Bands = { bands[1], { id = "b", name = "B", emoji = "B", from = 4, fade = 1, features = f } }
	end, "every band defines every feature")
	rejects(function(s)
		local f = table.clone(bands[2].features); f.aurora = 1.5
		s.Bands = { bands[1], { id = "b", name = "B", emoji = "B", from = 4, fade = 1, features = f } }
	end, "a feature weight above 1")
	rejects(function(s) s.Bands = { bands[1], { id = "b", emoji = "B", from = 4, fade = 1, features = bands[2].features } } end,
		"a band needs a name")
	rejects(function(s) s.Palette.moon = { 220, 40, 40 } end, "a red colour anywhere in the palette")
	rejects(function(s) s.Palette.moon = { 300, 40, 40 } end, "a colour channel out of 0..255")
	rejects(function(s) s.Moon.Color = "nope" end, "a colour key the palette does not have")
	rejects(function(s) s.Moon.Distance = 20 end, "a moon that reaches back to the entrance")
	rejects(function(s) s.Moon.Azimuth = 170 end, "a moon behind the hall")
	rejects(function(s) s.Moon.MaxTurnPerSecond = nil end, "a moon whose phase glide has no speed limit")
	rejects(function(s) s.RestView = table.clone(view); s.RestView.Offset = { 0, 22, 5 } end, "a break camera inside the entrance plane")
	rejects(function(s) s.RestView = table.clone(view); s.RestView.YawSwayDegrees = 80 end, "a break camera that can swing round to face the hall")
	rejects(function(s) s.RestView = table.clone(view); s.RestView.PitchDegrees = 70 end, "a break camera tilted so far up its frame leans back over the hall")
	rejects(function(s) s.Rest = table.clone(s.Rest); s.Rest.WakeOnMove = false end, "rest that does not wake on movement")
	rejects(function(s) s.Rest = table.clone(s.Rest); s.Rest.IdleSeconds = 20 end,
		"idle rest: nothing here needs pausing, so an idle timer would only take the camera away from a player who stopped to look")
	rejects(function(s) s.Rest = table.clone(s.Rest); s.Rest.PendingSeconds = 2 end, "a queued break that expires before the death beat ends")
	rejects(function(s) s.Budget = table.clone(s.Budget); s.Budget.MaxLights = 1 end, "a sky allowed to cast light (it would light the hall)")
	rejects(function(s) s.Budget = nil end, "no budget")
	rejects(function(s) s.GlideHalfLife = 0 end, "a glide of 0 is a hard cut")

	-- (review 2026-09-24) sizes the engine cannot draw. A config rejected for some OTHER reason would
	-- pass a plain `rejects`, so these also require the reason.
	local function rejectsFor(mut, needle, why)
		local s = goodSky()
		mut(s)
		local ok2, err2 = NightSky.validate(s, EnvBands, Rest)
		truthy(not ok2 and string.find(tostring(err2), needle, 1, true) ~= nil, why .. " (err: " .. tostring(err2) .. ")")
	end
	rejectsFor(function(s)
		s.Stars = { Distance = 820, Azimuth = 0, Elevation = 38, Size = { 2200, 700, 20 }, Rate = 10, Lifetime = { 5, 9 }, ParticleSize = 2.2, Color = "moon" }
	end, "2048", "a piece longer than Roblox's 2048-stud Part limit (it would be drawn clamped)")
	rejectsFor(function(s) s.IdleKickMinutes = nil end, "IdleKickMinutes", "no idle-disconnect minutes for the break caption to state")

	-- (review 2026-09-30, finding 5) the part, beam and trail budgets are enforced IN CODE: validate
	-- counts what the layout would build with every feature on at once and refuses a config over
	-- budget (the sky is then off, with a warning), instead of leaving it to a test nobody ran.
	truthy(type(NightSky.budgetOf) == "function", "NightSky.budgetOf exists")
	if type(NightSky.budgetOf) == "function" then
		local s = goodSky()
		s.Meteors = { SlotSeconds = 2, Chance = 0.45, Duration = 0.8, AzRange = { -40, 40 }, ElRange = { 20, 55 }, Length = 16,
			Distance = 680, Pool = 2, Size = { 1.2, 1.2, 9 }, TrailSeconds = 0.45, Color = "moon", Salt = 11 }
		s.Aurora = { Count = 4, AzRange = { -60, 55 }, ElRange = { 7, 16 }, Distance = 700, Width = { 90, 150 }, SwaySeconds = 23,
			SwayStuds = 60, Colors = { "moon" }, Transparency = { 0.35, 0.85 } }
		s.Comet = { Azimuth = 20, Elevation = 31, Distance = 740, HeadRadius = 4, ComaRadius = 11, ComaTransparency = 0.7, TailAzimuth = 40,
			TailElevation = 22, TailLength = 300, TailWidth = { 16, 90 }, Color = "moon", ComaColor = "moon", TailColor = "moon" }
		local b = NightSky.budgetOf(s, NightSky.layout(s, NightSky.hallOrigin(hall, 1)))
		eq(b.beams, 6, "budgetOf: 4 aurora curtains + the comet's 2 tail beams")
		eq(b.trails, 2, "budgetOf: one trail per pooled meteor")
		truthy(b.parts >= 2 + 2 + 2, "budgetOf counts every piece the layout builds (" .. tostring(b.parts) .. ")")
		local okAll = NightSky.validate(s, EnvBands, Rest)
		truthy(okAll, "that sky fits the goodSky budget")
		rejectsFor(function(t)
			for k, v in s do t[k] = v end
			t.Budget = table.clone(s.Budget); t.Budget.MaxParts = b.parts - 1
		end, "MaxParts", "a layout with more parts than the budget is refused")
		rejectsFor(function(t)
			for k, v in s do t[k] = v end
			t.Budget = table.clone(s.Budget); t.Budget.MaxBeams = 5
		end, "MaxBeams", "a layout with more beams than the budget is refused")
		rejectsFor(function(t)
			for k, v in s do t[k] = v end
			t.Budget = table.clone(s.Budget); t.Budget.MaxTrails = 1
		end, "MaxTrails", "a layout with more meteor trails than the budget is refused")
	end
end

-- (standard §2, 2026-10-01) critters: once a sky has them, every band flies its own or says why not, and
-- no flight can reach the entrance or outlast its slot
do
	local function critterSky()
		local s = goodSky()
		s.Critters = table.clone(critterSpec)
		s.Critters.Kinds = table.clone(critterSpec.Kinds)
		local cb = {}
		for i, b in bands do
			local nb = table.clone(b)
			nb.features = table.clone(b.features)
			nb.features[({ "fireflies", "bats", "owl" })[i]] = 1
			cb[i] = nb
		end
		s.Bands = cb
		return s
	end
	local okC, errC = NightSky.validate(critterSky(), EnvBands, Rest)
	truthy(okC, "a sky whose every band has critters validates (" .. tostring(errC) .. ")")
	local function critterRejects(mut, needle, why)
		local s = critterSky()
		mut(s)
		local ok2, err2 = NightSky.validate(s, EnvBands, Rest)
		truthy(not ok2 and string.find(string.lower(tostring(err2)), string.lower(needle), 1, true) ~= nil, why .. " (err: " .. tostring(err2) .. ")")
	end
	critterRejects(function(s) s.Bands[2].features.bats = 0 end, "critter", "a band with no critters and no reason is refused")
	do
		local s = critterSky()
		s.Bands[2].features.bats = 0
		s.Bands[2].critterless = "every animal shelters from a storm"
		local okR, errR = NightSky.validate(s, EnvBands, Rest)
		truthy(okR, "a band without critters validates when it says why (" .. tostring(errR) .. ")")
	end
	critterRejects(function(s) s.Bands[2].features.bats = 0; s.Bands[2].critterless = "" end, "critter", "an empty reason is no reason")
	critterRejects(function(s)
		s.Critters.Kinds.bats = table.clone(critterSpec.Kinds.bats); s.Critters.Kinds.bats.Duration = 20
	end, "Duration", "a flight longer than the slot's Duration could overlap the next one")
	critterRejects(function(s) s.Critters.Duration = 50 end, "Duration", "a Duration longer than the slot")
	critterRejects(function(s)
		s.Critters.Kinds.owl = table.clone(critterSpec.Kinds.owl); s.Critters.Kinds.owl.Distance = 8
	end, "owl", "an owl that could fly back to the entrance is refused")
	critterRejects(function(s)
		s.Critters.Kinds.wisps = table.clone(critterSpec.Kinds.wisps); s.Critters.Kinds.wisps.Style = "dive"
	end, "Style", "an unknown flight style")
	critterRejects(function(s) s.Critters.Kinds.geese = nil end, "geese", "a missing kind")
	critterRejects(function(s)
		s.Critters.Kinds.bats = table.clone(critterSpec.Kinds.bats); s.Critters.Kinds.bats.Color = "nope"
	end, "nope", "a critter colour the palette does not have")
	critterRejects(function(s) s.Critters.Chance = 1.5 end, "Chance", "a Chance above 1")
end

-- ------------------------------------------------------------------ engine size rules (review 2026-09-24)
-- Roblox forces a Ball to a uniform size and a Cylinder to a round cross-section (Y = Z), and clamps
-- every Part axis to 2048 studs. robloxemu keeps whatever is written, so a sky that breaks these
-- measures fine headless and draws differently in the engine. An ellipsoid is a Block with a Sphere
-- SpecialMesh (the mesh fills the box), which is the one way to draw a flattened sphere.
do
	local function piece(shape, x, y, z)
		return { key = "P", shape = shape, size = { x = x, y = y, z = z } }
	end
	local ok, why = NightSky.engineSizeOk(piece("Ball", 40, 40, 40))
	truthy(ok, "a uniform Ball is drawable (" .. tostring(why) .. ")")
	truthy(not (NightSky.engineSizeOk(piece("Ball", 177, 115, 177))), "a non-uniform Ball is not (Roblox forces it uniform)")
	truthy(NightSky.engineSizeOk(piece("Ellipsoid", 177, 115, 177)), "a flattened sphere is drawable as an Ellipsoid (Block + Sphere mesh)")
	truthy(NightSky.engineSizeOk(piece("Cylinder", 2, 76, 76)), "a round Cylinder is drawable")
	truthy(not (NightSky.engineSizeOk(piece("Cylinder", 2, 76, 40))), "an oval Cylinder is not (Roblox draws Y = Z)")
	truthy(NightSky.engineSizeOk(piece("Block", 2048, 140, 4)), "a Block of exactly 2048 studs is drawable")
	truthy(not (NightSky.engineSizeOk(piece("Block", 2200, 140, 4))), "a Block longer than 2048 studs is not")
	truthy(not (NightSky.engineSizeOk(piece("Ellipsoid", 10, 3000, 10))), "the limit holds for every shape and every axis")
	truthy(not (NightSky.engineSizeOk(piece("Wedge", 60, 0.01, 200))), "a paper-thin piece is not (below the engine's minimum)")
	truthy(not (NightSky.engineSizeOk(piece("Ball", 0 / 0, 1, 1))), "a NaN size is not")
end

-- ------------------------------------------------------------------ the brag (owner decision 2026-09-30)
-- The HUD shows, next to Best, the emoji of the highest sky band that Best Day has fully reached (the
-- first night, which everyone has, shows nothing). Pure: it reads only `from` and `emoji`.
do
	truthy(type(NightSky.bragEmoji) == "function", "NightSky.bragEmoji exists")
	if type(NightSky.bragEmoji) == "function" then
		eq(NightSky.bragEmoji(bands, 0), "", "Best Day 0: nothing to brag about")
		eq(NightSky.bragEmoji(bands, 3), "", "Best Day 3: still the first night")
		eq(NightSky.bragEmoji(bands, bands[2].from), bands[2].emoji, "the Day a band is full, its emoji")
		eq(NightSky.bragEmoji(bands, bands[3].from - 1), bands[2].emoji, "the Day before the next band: still the one before")
		eq(NightSky.bragEmoji(bands, 1e6), bands[#bands].emoji, "past the last band: the last")
		eq(NightSky.bragEmoji(bands, 0 / 0), "", "a nonsense Best Day brags about nothing")
	end
end

-- ------------------------------------------------------------------ the break caption
-- (review 2026-09-24) The break never calls the Day "safe". (Owner decision 2026-09-30) The run is now
-- SAVED while the session holds the save lock, with its live pass, and restored on a rejoin
-- (robloxemu/check_anomaly_rejoin.luau proves it). So once Roblox reports the player idle, the caption
-- states the 20-minute disconnect and then EITHER that this Day and this hall are saved (only when the
-- session saves: `saved`) OR that saving is off and the Day would be lost.
-- (review 2026-09-30, finding 2) The old guard was the one word "safe": "your streak is kept while you
-- rest, nothing is lost" passed every gate. Now:
--   * outside the idle warning a caption promises NOTHING about keeping progress (a wide deny-list);
--   * an unsaved session's captions never claim anything is saved, kept or safe;
--   * every template is pinned below WORD FOR WORD. A wording edit must come through this file, where
--     its reader is told what the words may and may not promise.
do
	local band = { id = "meteors", emoji = "🌠", name = "Meteor Shower" }
	truthy(type(NightSky.breakCaption) == "function" and type(NightSky.bandNews) == "function", "breakCaption and bandNews exist")
	local newsDesk, newsPhone = NightSky.bandNews(band, false), NightSky.bandNews(band, true)
	truthy(string.find(newsDesk, "Meteor Shower", 1, true) ~= nil and string.find(newsDesk, "🌠", 1, true) ~= nil, "band news names the band: " .. newsDesk)
	truthy(string.find(newsPhone, "Meteor Shower", 1, true) ~= nil and string.find(newsPhone, "🌠", 1, true) ~= nil, "on a phone too: " .. newsPhone)
	local intro = NightSky.introNews(true)
	truthy(type(intro) == "string" and #intro > 0, "there is an intro line for the first break on a phone")

	-- the pinned templates (Day 7, 20-minute kick)
	local function cap(t)
		t.day = t.day or 7
		t.kickMinutes = 20
		local ok, text = pcall(NightSky.breakCaption, t)
		return if ok then text else "(error: " .. tostring(text) .. ")"
	end
	local GOLDEN = {
		{ { compact = false, idle = false }, "☕ On a break: your hall is waiting, exactly as you left it. Move or press ▶ to go back." },
		{ { compact = true, idle = false }, "☕ Break · your hall waits. Move to go back." },
		{ { compact = false, idle = false, news = "🌠 Meteor Shower tonight." },
			"🌠 Meteor Shower tonight. ☕ On a break: your hall is waiting, exactly as you left it. Move or press ▶ to go back." },
		{ { compact = true, idle = false, news = "🌠 Meteor Shower" }, "🌠 Meteor Shower · Move to go back." },
		{ { compact = false, idle = true, saved = true },
			"☕ Still there? Roblox disconnects players idle for 20 minutes. Day 7 and this hall are saved: rejoin to carry on. Move or press ▶ to go back." },
		{ { compact = false, idle = true, saved = false },
			"☕ Still there? Roblox disconnects players idle for 20 minutes, and saving is off right now: Day 7 would be lost. Move or press ▶ to go back." },
		{ { compact = true, idle = true, saved = true }, "☕ Idle 20 min = disconnect. Day 7 is saved. Move!" },
		{ { compact = true, idle = true, saved = false }, "☕ Idle 20 min = disconnect; saving is off. Move!" },
	}
	for i, g in GOLDEN do
		local args = table.clone(g[1])
		eq(cap(args), g[2], "pinned caption " .. i)
	end

	-- the rules, over every combination
	local PROMISE = { "safe", "saved", "kept", "nothing is lost", "not lost", "won't lose", "will not lose", "protect", "surviv", "guarantee", "secure" }
	local function promises(text: string): string?
		local low = string.lower(text)
		for _, w in PROMISE do
			if string.find(low, w, 1, true) then return w end
		end
		return nil
	end
	local restPromise, unsavedPromise, tooLong, noKick, savedNoPromise, unsavedNoLoss, noDay, alarm, lostNews, bad = {}, {}, {}, {}, {}, {}, {}, {}, {}, 0
	for _, d in { 1, 7, 31, 52, 500 } do
		for _, compact in { false, true } do
			for _, idle in { false, true } do
				for _, saved in { false, true } do
					for _, news in { "", NightSky.bandNews(band, compact), NightSky.introNews(compact) } do
						local ok, text = pcall(NightSky.breakCaption, {
							day = d, compact = compact, idle = idle, saved = saved, kickMinutes = 20, news = if news == "" then nil else news,
						})
						if not ok or type(text) ~= "string" or text == "" then
							bad += 1
							continue
						end
						local tag = string.format("[day %d %s%s%s] %s", d, if compact then "phone" else "desk", if idle then " idle" else "",
							if saved then " saved" else "", text)
						local low = string.lower(text)
						local n = utf8.len(text) or #text
						if n > (if compact then 56 else 170) then table.insert(tooLong, tag .. " (" .. n .. ")") end
						if not idle then
							if promises(text) then table.insert(restPromise, tag) end
							if string.find(low, "disconnect", 1, true) then table.insert(alarm, tag) end
							if news ~= "" and not string.find(text, news, 1, true) then table.insert(lostNews, tag) end
						else
							if not string.find(text, "20", 1, true) then table.insert(noKick, tag) end
							if not saved and promises(text) then table.insert(unsavedPromise, tag) end
							if saved and not (string.find(low, "saved", 1, true) and string.find(text, "Day " .. d, 1, true)) then
								table.insert(savedNoPromise, tag)
							end
							if not saved and not string.find(low, "saving is off", 1, true) then table.insert(unsavedNoLoss, tag) end
							if not compact and not string.find(text, "Day " .. d, 1, true) then table.insert(noDay, tag) end
						end
					end
				end
			end
		end
	end
	eq(bad, 0, "breakCaption returns text for every combination")
	eq(#restPromise, 0, "outside the idle warning a break promises nothing about keeping progress: " .. table.concat(restPromise, " | "))
	eq(#unsavedPromise, 0, "a session that does not save never claims anything is saved, kept or safe: " .. table.concat(unsavedPromise, " | "))
	eq(#tooLong, 0, "every caption fits its box (phone <= 56 chars, desktop <= 170): " .. table.concat(tooLong, " | "))
	eq(#noKick, 0, "an idle player is told the disconnect minutes: " .. table.concat(noKick, " | "))
	eq(#savedNoPromise, 0, "a saving session's idle warning says this Day is saved: " .. table.concat(savedNoPromise, " | "))
	eq(#unsavedNoLoss, 0, "an unsaved session's idle warning says saving is off: " .. table.concat(unsavedNoLoss, " | "))
	eq(#noDay, 0, "and, on a desktop, names the Day: " .. table.concat(noDay, " | "))
	eq(#alarm, 0, "a player who is not idle is not warned (the warning is kept for when it matters): " .. table.concat(alarm, " | "))
	eq(#lostNews, 0, "news (a new band, the intro) is shown on the break: " .. table.concat(lostNews, " | "))
	-- CONTROL for the deny-list: the reviewer's mutant sentence is caught by it
	truthy(promises("☕ On a break: your streak is kept while you rest, nothing is lost.") ~= nil,
		"CONTROL: the deny-list catches the reviewer's reworded promise")
	local k15 = NightSky.breakCaption({ day = 4, compact = false, idle = true, saved = true, kickMinutes = 15 })
	truthy(string.find(k15, "15", 1, true) ~= nil, "the minutes come from the argument: " .. k15)
	local okNaN, tNaN = pcall(NightSky.breakCaption, { day = 0 / 0, compact = false, idle = true, saved = true, kickMinutes = 20 })
	truthy(okNaN and string.find(tNaN, "Day 1", 1, true) ~= nil, "a nonsense Day reads as Day 1: " .. tostring(tNaN))
	local unset = NightSky.breakCaption({ day = 4, compact = true, idle = true, kickMinutes = 20 })
	truthy(string.find(string.lower(unset), "saving is off", 1, true) ~= nil, "not knowing whether the session saves reads as unsaved: " .. unset)
end

-- ------------------------------------------------------------------ weather (standard §2, 2026-10-01 pass 2)
-- docs/complete-game-standard.md §2: every band has its own light, colour, scenery, critters AND weather. The
-- weather is one ParticleEmitter per kind on an invisible host out in front of the entrance (where the storm's
-- rain already fell). Each kind is a FEATURE, so it glides in and out with its band like everything else; the
-- storm's rain (`Rain`, driven by the `storm` feature) counts as weather too. A band whose sky is clear says
-- why (`clearSky`), and validate refuses a band with neither. `emitterRates` is what SkyArt asks of the
-- emitters before EnvBands.capRates holds them to the budget.
local weatherSpec = {
	Kinds = {
		thistledown = { Offset = { 0, 36, 64 }, Size = { 80, 2, 50 }, Rate = 5, Speed = { 1.5, 3 }, Lifetime = { 10, 14 },
			SpreadDegrees = 20, Direction = "Bottom", Wind = 0.4, ParticleSize = 0.35, Transparency = 0.3, Color = "moon" },
		snow = { Offset = { 0, 36, 64 }, Size = { 80, 2, 50 }, Rate = 20, Speed = { 3, 5 }, Lifetime = { 8, 10 },
			SpreadDegrees = 12, Direction = "Bottom", Wind = 0.3, ParticleSize = 0.45, Transparency = 0.2, Color = "moon" },
		frost = { Offset = { 0, 30, 64 }, Size = { 80, 20, 50 }, Rate = 12, Speed = { 0.5, 1.5 }, Lifetime = { 6, 9 },
			SpreadDegrees = 45, Direction = "Bottom", Wind = 0, ParticleSize = 0.18, Transparency = 0.1, Color = "moon" },
		leaves = { Offset = { 0, 36, 64 }, Size = { 80, 2, 50 }, Rate = 4, Speed = { 2, 4 }, Lifetime = { 8, 10 },
			SpreadDegrees = 15, Direction = "Bottom", Wind = 1.5, ParticleSize = 0.6, Transparency = 0, Color = "shade" },
		motes = { Offset = { 0, 8, 64 }, Size = { 80, 2, 50 }, Rate = 8, Speed = { 1, 2 }, Lifetime = { 10, 14 },
			SpreadDegrees = 25, Direction = "Top", Wind = 0, ParticleSize = 0.3, Transparency = 0.25, Color = "moon" },
	},
}
local rainSpec = { Offset = { 0, 40, 60 }, Size = { 70, 2, 60 }, Rate = 40, Speed = 70, Lifetime = 1.2, SpreadDegrees = 2, Color = "moon" }
do
	local W = NightSky.WEATHER
	truthy(type(W) == "table" and #W == 5, "NightSky lists five weather kinds")
	local inFeatures = {}
	for _, k in NightSky.FEATURES do inFeatures[k] = true end
	local allIn = true
	for _, k in (W or {}) do
		if not inFeatures[k] then allIn = false end
		truthy(weatherSpec.Kinds[k] ~= nil, "the spec's config covers weather kind " .. tostring(k))
	end
	truthy(allIn, "every weather kind is a band FEATURE, so it glides in and out with its band")
	truthy(type(NightSky.bandWeather) == "function" and type(NightSky.emitterRates) == "function",
		"bandWeather and emitterRates exist")
	truthy(NightSky.WEATHER_DIRECTIONS ~= nil and NightSky.WEATHER_DIRECTIONS.Bottom and NightSky.WEATHER_DIRECTIONS.Top
		and not NightSky.WEATHER_DIRECTIONS.Front, "weather falls (Bottom) or rises (Top), never toward the hall")
end
if type(NightSky.bandWeather) == "function" and type(NightSky.emitterRates) == "function" then
	local sky = { Weather = weatherSpec, Rain = rainSpec, Stars = { Rate = 10 } }
	local function list(t) return table.concat(t, ",") end
	eq(list(NightSky.bandWeather(sky, { features = feats({ snow = 1 }) })), "snow", "a snowy band's weather is snow")
	eq(list(NightSky.bandWeather(sky, { features = feats({ storm = 1 }) })), "rain", "a stormy band's weather is the rain")
	eq(list(NightSky.bandWeather({ Weather = weatherSpec }, { features = feats({ storm = 1 }) })), "",
		"the storm feature is only rain when the sky has Rain")
	eq(list(NightSky.bandWeather(sky, { features = feats({ stars = 1, moon = 1, meteors = 1 }) })), "",
		"stars, the moon and meteors are not weather")
	eq(list(NightSky.bandWeather(sky, { features = feats({ snow = 0.5, frost = 0.25, storm = 0.1 }) })), "frost,rain,snow",
		"a blended band lists every weather it shows, sorted")
	eq(list(NightSky.bandWeather(sky, { features = feats({ snow = 0 }) })), "", "weight 0 is no weather")

	local r = NightSky.emitterRates(sky, { stars = 0.5, storm = 0.25, snow = 1, frost = 0.5 })
	approx(r.stars, 5, "stars: Stars.Rate x the stars weight")
	approx(r.rain, 10, "rain: Rain.Rate x the storm weight")
	approx(r.snow, 20, "snow: its Rate x its weight")
	approx(r.frost, 6, "frost at half weight: half its Rate")
	approx(r.thistledown, 0, "a weather kind with no weight asks for nothing")
	approx(r.motes, 0, "nor does a missing one")
	local odd = NightSky.emitterRates(sky, { stars = 0 / 0, snow = 3, frost = -1 })
	approx(odd.stars, 0, "a NaN weight asks for nothing")
	approx(odd.snow, 20, "a weight above 1 counts as 1")
	approx(odd.frost, 0, "a negative weight counts as 0")
	local bare = NightSky.emitterRates({}, { stars = 1, storm = 1, snow = 1 })
	approx(bare.stars or 0, 0, "a sky without Stars, Rain or Weather wants no emitters (stars)")
	approx(bare.rain or 0, 0, "(rain)")
	approx(bare.snow or 0, 0, "(snow)")

	-- envelopes: every kind's host box, grown by what its particles can travel
	local origin = NightSky.hallOrigin(hall, 2)
	local env = {}
	for _, e in NightSky.envelopes({ Hall = hall, Weather = weatherSpec }, origin) do env[e.key] = e end
	for _, k in (NightSky.WEATHER or {}) do
		truthy(env["Weather_" .. k] ~= nil, "weather " .. k .. " declares an envelope")
	end
	local sn = env.Weather_snow
	if sn then
		local K = weatherSpec.Kinds.snow
		local reach = K.Speed[2] * K.Lifetime[2]
		local drift = reach * math.sin(math.rad(K.SpreadDegrees))
		approx(sn.min.z - origin.z, K.Offset[3] - K.Size[3] / 2 - drift - K.ParticleSize, "snow's box reaches back by its drift + a flake", 1e-6)
		approx(sn.min.y - origin.y, K.Offset[2] - K.Size[2] / 2 - reach - K.ParticleSize, "snow falls its full reach", 1e-6)
		approx(sn.max.y - origin.y, K.Offset[2] + K.Size[2] / 2 + drift + K.ParticleSize, "and rises only by its drift", 1e-6)
		local wind = 0.5 * K.Wind * K.Lifetime[2] ^ 2
		approx(sn.max.x - origin.x, K.Offset[1] + K.Size[1] / 2 + drift + wind + K.ParticleSize, "the wind carries it sideways (x)", 1e-6)
	end
	local mo = env.Weather_motes
	if mo then
		local K = weatherSpec.Kinds.motes
		local reach = K.Speed[2] * K.Lifetime[2]
		approx(mo.max.y - origin.y, K.Offset[2] + K.Size[2] / 2 + reach + K.ParticleSize, "motes rise their full reach", 1e-6)
	end

	-- validate: a sky with weather; every band has its own or says why its sky is clear
	local function weatherSky()
		local s = goodSky()
		s.Weather = weatherSpec
		s.Rain = rainSpec
		s.Bands = {
			{ id = "a", name = "Alpha", emoji = "A", from = 0, fade = 0, features = feats({ stars = 0.5, moon = 1, thistledown = 1 }) },
			{ id = "b", name = "Beta", emoji = "B", from = 4, fade = 1, features = feats({ stars = 0.7, moon = 1, meteors = 1 }),
				clearSky = "a shower is watched on a clear night" },
			{ id = "c", name = "Gamma", emoji = "C", from = 10, fade = 4, features = feats({ stars = 1, moon = 0.5, aurora = 1, snow = 1 }) },
		}
		return s
	end
	local okW, errW = NightSky.validate(weatherSky(), EnvBands, Rest)
	truthy(okW, "a sky whose every band has weather or a reason validates (" .. tostring(errW) .. ")")
	local function rejectsW(mut, why)
		local s = weatherSky()
		mut(s)
		local ok2, err2 = NightSky.validate(s, EnvBands, Rest)
		truthy(not ok2, why .. " (err: " .. tostring(err2) .. ")")
	end
	local function kind(s, k)
		s.Weather = { Kinds = table.clone(s.Weather.Kinds) }
		s.Weather.Kinds[k] = table.clone(s.Weather.Kinds[k])
		return s.Weather.Kinds[k]
	end
	rejectsW(function(s) s.Bands[2].clearSky = nil end, "a band with no weather and no clearSky reason")
	rejectsW(function(s) s.Bands[2].clearSky = "" end, "an empty clearSky reason")
	rejectsW(function(s) s.Weather = { Kinds = table.clone(s.Weather.Kinds) }; s.Weather.Kinds.frost = nil end, "a weather kind missing from Weather.Kinds")
	rejectsW(function(s) kind(s, "snow").Offset = { 0, 36, 30 } end, "snow whose drift reaches back to the entrance")
	rejectsW(function(s) kind(s, "snow").SpreadDegrees = 80 end, "snow spread so wide it drifts back to the entrance")
	rejectsW(function(s) kind(s, "motes").Direction = "Front" end, "weather blown toward the hall")
	rejectsW(function(s) kind(s, "snow").Rate = 61 end, "one kind over the particle budget on its own")
	rejectsW(function(s) kind(s, "snow").Rate = 0 end, "a kind that never emits")
	rejectsW(function(s) kind(s, "snow").Speed = { 5, 3 } end, "a speed range upside down")
	rejectsW(function(s) kind(s, "snow").Lifetime = { 0, 0 } end, "a lifetime of 0")
	rejectsW(function(s) kind(s, "snow").ParticleSize = 0 end, "a particle of size 0")
	rejectsW(function(s) kind(s, "snow").Color = "nope" end, "a weather colour the palette does not have")
	rejectsW(function(s) kind(s, "leaves").Wind = 0 / 0 end, "a NaN wind")
	rejectsW(function(s) s.Bands[1].features = feats({ stars = 0.5, moon = 1, thistledown = 1.5 }) end, "a weather weight above 1")
end
-- ------------------------------------------------------------------ each band's own light (standard §2, 2026-10-01 pass 2)
-- The hall must never change, so the sky casts no light and writes no Lighting while a pass can be seen. A
-- band's own light is the telescope break's colour grade: the only time the sky writes Lighting, with the
-- camera out and the hall out of view. breakLight blends it by Day like any band value; a band without one
-- uses the fallback (RestView.Grade, no tint), and validate refuses half-lit bands, red tints and wild grades.
do
	truthy(type(NightSky.breakLight) == "function", "breakLight exists")
end
if type(NightSky.breakLight) == "function" then
	local fallback = { Saturation = 0.3, Brightness = 0.03, Contrast = 0.05 }
	local lit = {
		{ id = "a", name = "Alpha", emoji = "A", from = 0, fade = 0, features = feats({ stars = 0.5, moon = 1 }),
			light = { tint = { 200, 220, 255 }, brightness = 0.02, contrast = 0.1, saturation = 0.3 } },
		{ id = "b", name = "Beta", emoji = "B", from = 4, fade = 2, features = feats({ stars = 0.7, moon = 1, meteors = 1 }),
			light = { tint = { 255, 255, 255 }, brightness = -0.02, contrast = 0, saturation = -0.2 } },
	}
	local function same(l, tint, b, c, s, msg)
		local ok = type(l) == "table" and type(l.tint) == "table" and math.abs(l.tint[1] - tint[1]) < 1e-6
			and math.abs(l.tint[2] - tint[2]) < 1e-6 and math.abs(l.tint[3] - tint[3]) < 1e-6
			and math.abs(l.brightness - b) < 1e-6 and math.abs(l.contrast - c) < 1e-6 and math.abs(l.saturation - s) < 1e-6
		truthy(ok, msg .. string.format(" (got tint %s, %s, %s, %s)", if l and l.tint then table.concat(l.tint, ",") else "nil",
			tostring(l and l.brightness), tostring(l and l.contrast), tostring(l and l.saturation)))
	end
	same(NightSky.breakLight(lit, EnvBands, 1, fallback), { 200, 220, 255 }, 0.02, 0.1, 0.3, "Day 1 is band a's light")
	same(NightSky.breakLight(lit, EnvBands, 3, fallback), { 227.5, 237.5, 255 }, 0, 0.05, 0.05, "Day 3 is half way into b's (smoothstep 0.5)")
	same(NightSky.breakLight(lit, EnvBands, 9, fallback), { 255, 255, 255 }, -0.02, 0, -0.2, "Day 9 is b's light")
	same(NightSky.breakLight(lit, EnvBands, 0 / 0, fallback), { 200, 220, 255 }, 0.02, 0.1, 0.3, "a NaN Day is the first band's light")
	local l = NightSky.breakLight(lit, EnvBands, 1, fallback)
	l.tint[1] = 0
	l.brightness = 9
	same(NightSky.breakLight(lit, EnvBands, 1, fallback), { 200, 220, 255 }, 0.02, 0.1, 0.3, "breakLight hands out a copy")
	same(NightSky.breakLight(bands, EnvBands, 5, fallback), { 255, 255, 255 }, 0.03, 0.05, 0.3,
		"bands without a light of their own get the fallback grade, untinted")

	local function litSky()
		local s = goodSky()
		s.Bands = {
			{ id = "a", name = "Alpha", emoji = "A", from = 0, fade = 0, features = lit[1].features, light = table.clone(lit[1].light) },
			{ id = "b", name = "Beta", emoji = "B", from = 4, fade = 2, features = lit[2].features, light = table.clone(lit[2].light) },
		}
		return s
	end
	local okL, errL = NightSky.validate(litSky(), EnvBands, Rest)
	truthy(okL, "a sky whose every band has its own light validates (" .. tostring(errL) .. ")")
	local function rejectsL(mut, why)
		local s = litSky()
		mut(s)
		local ok2, err2 = NightSky.validate(s, EnvBands, Rest)
		truthy(not ok2, why .. " (err: " .. tostring(err2) .. ")")
	end
	rejectsL(function(s) s.Bands[2].light = nil end, "one band lit and the next not (half the bands would use the fallback)")
	rejectsL(function(s) s.Bands[2].light.tint = { 255, 120, 120 } end, "a red tint (red is how two anomalies read)")
	rejectsL(function(s) s.Bands[2].light.tint = { 255, 255 } end, "a tint that is not {r, g, b}")
	rejectsL(function(s) s.Bands[2].light.tint = { 255, 255, 300 } end, "a tint channel over 255")
	rejectsL(function(s) s.Bands[2].light.brightness = 0.5 end, "a grade so bright it washes the sky out")
	rejectsL(function(s) s.Bands[2].light.contrast = -0.6 end, "a contrast out of range")
	rejectsL(function(s) s.Bands[2].light.saturation = 0 / 0 end, "a NaN saturation")
end
print(string.format("NightSky: %d passed, %d failed", passed, failed))
assert(failed == 0, "NightSky tests failed")
