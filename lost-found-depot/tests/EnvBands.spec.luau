-- Spec for EnvBands: progress value -> environment band + blend. Run: luau tests/EnvBands.spec.luau
--
-- EnvBands is the game-agnostic half of "the world changes as you progress". It knows nothing
-- about towers, skies or Roblox: a band is a table with a numeric `from`, and whatever payload
-- the game hangs on it (lighting, pieces, hazards) is blended as plain numbers and number arrays.
-- The properties that matter, and that every copy of this module in another game relies on:
--   * a band lookup is total: any number, including NaN and negatives, lands in a band;
--   * a transition is never a hard cut: weights move continuously and always sum to 1;
--   * the blend is driven by the progress value alone, never by a clock.
local EnvBands = require("../src/shared/EnvBands")

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
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local bands = {
	{ id = "low", from = 0, fade = 0, light = { Brightness = 2, Tint = { 255, 255, 255 }, Label = "day" } },
	{ id = "mid", from = 10, fade = 4, light = { Brightness = 4, Tint = { 155, 55, 255 }, Label = "dusk" } },
	{ id = "high", from = 30, fade = 10, light = { Brightness = 0, Tint = { 55, 155, 0 }, Label = "night" } },
}

--================================================================ validate

truthy(EnvBands.validate(bands), "a well-formed band list validates")
do
	local ok, err = EnvBands.validate({})
	eq(ok, false, "an empty band list is rejected")
	truthy(type(err) == "string" and #err > 0, "and says why")
end
eq((EnvBands.validate({ { id = "a", from = 5 }, { id = "b", from = 5 } })), false,
	"two bands starting at the same progress are rejected (the lookup would be ambiguous)")
eq((EnvBands.validate({ { id = "a", from = 0 }, { id = "b", from = 10 }, { id = "c", from = 8 } })), false,
	"bands out of order are rejected")
eq((EnvBands.validate({ { id = "a", from = 0 }, { id = "b", from = 10, fade = 11 } })), false,
	"a fade that reaches back past the previous band's start is rejected")
eq((EnvBands.validate({ { id = "a", from = 0 }, { id = "b", from = 10, fade = -1 } })), false,
	"a negative fade is rejected")
eq((EnvBands.validate({ { id = "a", from = 0 }, { id = "a", from = 10 } })), false,
	"duplicate ids are rejected")
eq((EnvBands.validate({ { id = "a", from = 3 }, { id = "b", from = 10 } })), false,
	"the first band must start at 0, so progress 0 is never outside the table")
eq((EnvBands.validate({ { id = "a", from = 0 }, { id = "b", from = 10, fade = 10 } })), true,
	"a fade exactly as long as the previous band is allowed")

--================================================================ indexAt

eq(EnvBands.indexAt(bands, 0), 1, "progress 0 is the first band")
eq(EnvBands.indexAt(bands, 9.999), 1, "just below a boundary is still the lower band")
eq(EnvBands.indexAt(bands, 10), 2, "exactly on a boundary is the upper band")
eq(EnvBands.indexAt(bands, 29), 2, "inside the middle band")
eq(EnvBands.indexAt(bands, 30), 3, "the last band starts at its from")
eq(EnvBands.indexAt(bands, 1e9), 3, "the last band is open-ended")
eq(EnvBands.indexAt(bands, -50), 1, "negative progress clamps to the first band")
eq(EnvBands.indexAt(bands, 0 / 0), 1, "NaN progress clamps to the first band instead of erroring")
eq(EnvBands.indexAt(bands, math.huge), 3, "infinite progress is the last band")

--================================================================ locate / weights

do
	local i, j, t = EnvBands.locate(bands, 3)
	eq(i, 1, "outside any fade: current band")
	eq(j, 1, "outside any fade: no next band blending in")
	eq(t, 0, "outside any fade: blend 0")
end
do
	local i, j, t = EnvBands.locate(bands, 6)
	eq(i, 1, "at the START of the fade into band 2 you are still in band 1")
	eq(j, 2, "and band 2 is the one blending in")
	approx(t, 0, "and its weight is still 0 (continuous with the frame before)")
end
do
	local _, _, t = EnvBands.locate(bands, 8)
	approx(t, 0.5, "halfway through a symmetric fade the weight is exactly one half")
end
do
	local i, j, t = EnvBands.locate(bands, 10)
	eq(i, 2, "at the boundary you are in the new band")
	eq(j, 2, "fully")
	eq(t, 0, "with no blend left")
end
do
	-- the fade uses a smoothstep, so the start and end of a transition ease rather than kink
	local _, _, t1 = EnvBands.locate(bands, 6.4)
	truthy(t1 > 0 and t1 < 0.1, "the first tenth of a fade moves slowly (eased, not linear): " .. tostring(t1))
end
do
	local _, j, t = EnvBands.locate(bands, 9.9999)
	eq(j, 2, "the instant before the boundary band 2 is blending")
	truthy(t > 0.999, "and is essentially fully in, so the boundary is not a hard cut: " .. tostring(t))
end
do
	local zeroFade = { { id = "a", from = 0 }, { id = "b", from = 5, fade = 0 } }
	local _, j, t = EnvBands.locate(zeroFade, 4.99)
	eq(j, 1, "a band with fade 0 does not blend in before its start (a deliberate hard cut)")
	eq(t, 0, "and carries no weight")
end

-- Continuity, measured: sweep progress in tiny steps and prove no weight ever jumps.
do
	local worstJump = 0
	local prev = nil
	local sumsOk = true
	local p = -2
	while p <= 60 do
		local w = EnvBands.weights(bands, p)
		local total = 0
		for idx = 1, #bands do
			total += (w[idx] or 0)
		end
		if math.abs(total - 1) > 1e-9 then sumsOk = false end
		if prev then
			for idx = 1, #bands do
				local d = math.abs((w[idx] or 0) - (prev[idx] or 0))
				if d > worstJump then worstJump = d end
			end
		end
		prev = w
		p += 0.01
	end
	truthy(sumsOk, "band weights always sum to 1")
	truthy(worstJump < 0.01, "no band weight jumps by more than 0.01 over a 0.01 progress step (worst "
		.. string.format("%.5f", worstJump) .. ") - transitions are never a hard cut")
end

--================================================================ lerp / sample

approx(EnvBands.lerp(2, 4, 0.25), 2.5, "numbers lerp")
do
	local c = EnvBands.lerp({ 0, 100, 200 }, { 100, 0, 200 }, 0.5)
	eq(type(c), "table", "number arrays lerp component-wise")
	approx(c[1], 50, "component 1")
	approx(c[2], 50, "component 2")
	approx(c[3], 200, "component 3")
end
eq(EnvBands.lerp("day", "night", 0.49), "day", "non-numeric values hold until halfway")
eq(EnvBands.lerp("day", "night", 0.5), "night", "and switch at halfway")
eq(EnvBands.lerp(nil, 7, 0.1), 7, "a value missing on one side falls back to the other")
eq(EnvBands.lerp(7, nil, 0.9), 7, "on either side")

do
	local s = EnvBands.sample(bands, 8, "light")
	approx(s.Brightness, 3, "sample blends numbers between the two active bands")
	approx(s.Tint[1], 205, "and colours")
	eq(s.Label, "dusk", "and switches labels at the halfway point")
end
do
	local s = EnvBands.sample(bands, 45, "light")
	approx(s.Brightness, 0, "sample in the open-ended last band is that band's value")
end
do
	local a = EnvBands.sample(bands, 8, "light")
	a.Tint[1] = -999
	a.Brightness = -999
	eq(bands[2].light.Tint[1], 155, "sample returns a COPY: writing to it never corrupts the config")
	eq(bands[1].light.Brightness, 2, "for numbers either")
	local b = EnvBands.sample(bands, 0, "light")
	a = b
	a.Tint[2] = -1
	eq(bands[1].light.Tint[2], 255, "even when the sample is exactly one band's own table")
end
do
	local s = EnvBands.sample(bands, 3, "nothingHere")
	eq(type(s), "table", "sampling a key no band defines returns an empty table, not nil")
	eq(next(s), nil, "and it is empty")
end

--================================================================ layers (narrow overrides)

local layer = { center = 20, halfWidth = 1, feather = 2 }
eq(EnvBands.layerWeight(layer, 20), 1, "a layer is fully on at its centre")
eq(EnvBands.layerWeight(layer, 21), 1, "and across its half width")
eq(EnvBands.layerWeight(layer, 23), 0, "and fully off past half width + feather")
eq(EnvBands.layerWeight(layer, 17), 0, "on the low side too")
do
	local w = EnvBands.layerWeight(layer, 22)
	approx(w, 0.5, "halfway through the feather it is one half")
end
eq(EnvBands.layerWeight(layer, 0 / 0), 0, "NaN progress is outside every layer")

do
	local base = { Density = 0.3, Color = { 100, 100, 100 }, Haze = 1 }
	local out = EnvBands.overlay(base, { Density = 0.7, Color = { 200, 200, 200 } }, 0.5)
	approx(out.Density, 0.5, "overlay blends the overridden fields by the layer weight")
	approx(out.Color[1], 150, "including colours")
	approx(out.Haze, 1, "and leaves the fields it does not name alone")
	eq(base.Density, 0.3, "without mutating the base")
end

--================================================================ approach (frame smoothing)

approx(EnvBands.approach(0, 10, 1, 1), 5, "after one half-life a value is halfway to its target")
approx(EnvBands.approach(0, 10, 2, 1), 7.5, "after two, three quarters")
eq(EnvBands.approach(0, 10, 0.016, 0), 10, "a half-life of 0 snaps (smoothing off)")
do
	-- frame-rate independence: 60 small steps land where one big step does
	local v = 0
	for _ = 1, 60 do v = EnvBands.approach(v, 10, 1 / 60, 0.5) end
	local once = EnvBands.approach(0, 10, 1, 0.5)
	approx(v, once, "smoothing is frame-rate independent", 1e-6)
end
do
	local c = EnvBands.approach({ 0, 0, 0 }, { 10, 20, 30 }, 1, 1)
	approx(c[3], 15, "arrays approach component-wise")
end
eq(EnvBands.approach("a", "b", 0.1, 1), "b", "non-numeric values simply take the target")
do
	local cur = { Density = 0 }
	local target = { Density = 1, Glare = 0.5 }
	local out = EnvBands.approachTable(cur, target, 1, 1)
	approx(out.Density, 0.5, "approachTable moves every field")
	approx(out.Glare, 0.5, "and adopts a field the current table lacks without jumping past it")
end

--================================================================ nextBand / announcer

do
	local idx, remaining = EnvBands.nextBand(bands, 12)
	eq(idx, 3, "the next band after 12 is band 3")
	approx(remaining, 18, "and it is 18 progress units away")
	local none = EnvBands.nextBand(bands, 31)
	eq(none, nil, "there is no band after the last one")
end
do
	local idx = EnvBands.indexOf(bands, "mid")
	eq(idx, 2, "indexOf finds a band by id")
	eq(EnvBands.indexOf(bands, "nope"), nil, "and returns nil for an unknown id")
end

do
	local a = EnvBands.newAnnouncer()
	eq(EnvBands.announce(a, 1), true, "the first band seen is announced")
	eq(EnvBands.announce(a, 1), false, "but only once")
	eq(EnvBands.announce(a, 2), true, "a higher band is announced")
	eq(EnvBands.announce(a, 1), false, "going back down announces nothing")
	eq(EnvBands.announce(a, 2), false, "and climbing back up to a band already seen announces nothing")
	eq(EnvBands.announce(a, 3), true, "a new highest band is announced")
end

--================================================================ keeping scenery off the play path

-- Review 2026-09-17: a world-fixed storm-deck cloud (radius 121, 92% opaque) sat on the tower, and the
-- next platform could be inside it. keepClear shrinks (or removes) a ball of scenery so its surface stays
-- `clearance` away from the path the player climbs (a polyline through the platforms).
do
	local path = { { x = 0, y = 0, z = 0 }, { x = 0, y = 100, z = 0 }, { x = 50, y = 100, z = 0 } }
	approx(EnvBands.pathDistance({ x = 10, y = 50, z = 0 }, path), 10, "distance to the middle of a segment")
	approx(EnvBands.pathDistance({ x = 0, y = -30, z = 40 }, path), 50, "distance to an end point")
	approx(EnvBands.pathDistance({ x = 25, y = 110, z = 0 }, path), 10, "distance to the second segment")
	approx(EnvBands.pathDistance({ x = 3, y = 4, z = 0 }, { { x = 0, y = 0, z = 0 } }), 5, "a one-point path is a point")
	eq(EnvBands.pathDistance({ x = 3, y = 4, z = 0 }, {}), math.huge, "an empty path is infinitely far")

	approx(EnvBands.keepClear({ x = 300, y = 50, z = 0 }, 80, path, 40, 10), 80, "a ball far from the path keeps its size")
	approx(EnvBands.keepClear({ x = -100, y = 50, z = 0 }, 80, path, 40, 10), 60,
		"a ball whose surface comes too close shrinks until it is `clearance` away (100 - 40)")
	eq(EnvBands.keepClear({ x = 45, y = 50, z = 0 }, 80, path, 40, 10), 0,
		"a ball that would have to shrink below minRadius is removed (0)")
	eq(EnvBands.keepClear({ x = 5, y = 50, z = 0 }, 80, path, 40, 10), 0, "and so is one sitting on the path")
	approx(EnvBands.keepClear({ x = 5, y = 50, z = 0 }, 80, {}, 40, 10), 80, "with no path nothing changes")
	do
		local r = EnvBands.keepClear({ x = 100, y = 50, z = 0 }, 80, path, 40, 10)
		truthy(EnvBands.pathDistance({ x = 100, y = 50, z = 0 }, path) - r >= 40 - 1e-9,
			"after keepClear the surface is at least `clearance` from every point of the path")
	end
end

--================================================================ tiling (world-fixed fields)

do
	local cells = EnvBands.cellsAround(0, 0, 100, 1)
	eq(#cells, 9, "radius 1 is a 3x3 block of cells")
	local seen = {}
	for _, c in cells do seen[c[1] .. "," .. c[2]] = true end
	truthy(seen["0,0"] and seen["-1,-1"] and seen["1,1"], "centred on the camera's own cell")
	local moved = EnvBands.cellsAround(149, -51, 100, 1)
	local seen2 = {}
	for _, c in moved do seen2[c[1] .. "," .. c[2]] = true end
	truthy(seen2["1,-1"] and seen2["2,0"] and seen2["0,-2"], "cells follow the camera across a boundary")
	eq(EnvBands.cellOf(-0.5, 100), -1, "cellOf floors, so negative coordinates do not share cell 0")
end
do
	local a = EnvBands.hash01(3, -7, 2, 99)
	local b = EnvBands.hash01(3, -7, 2, 99)
	eq(a, b, "hash01 is deterministic: a world cell always holds the same content")
	truthy(a >= 0 and a < 1, "and in [0, 1)")
	local distinct, lo, hi = {}, 1, 0
	local n = 0
	for x = -20, 20 do
		for z = -20, 20 do
			local v = EnvBands.hash01(x, z, 1, 7)
			distinct[v] = true
			if v < lo then lo = v end
			if v > hi then hi = v end
			n += 1
		end
	end
	local count = 0
	for _ in distinct do count += 1 end
	truthy(count > n * 0.95, "neighbouring cells get different values (" .. count .. " distinct of " .. n .. ")")
	truthy(lo < 0.05 and hi > 0.95, "and they cover the whole range")
end

--================================================================ ambient life around the camera

do
	local function lcg(seed)
		local s = seed
		return function()
			s = (1664525 * s + 1013904223) % 4294967296
			return s / 4294967296
		end
	end
	local r = lcg(9)
	local spec = { rMin = 100, rMax = 300, yMin = -20, yMax = 40, speedMin = 10, speedMax = 20 }
	local centre = { x = 500, y = 1000, z = -200 }
	local ringOk, heightOk, speedOk, freshOk = true, true, true, true
	for _ = 1, 2000 do
		local c = EnvBands.ambientSpawn(centre, spec, r)
		local dx, dz = c.pos.x - centre.x, c.pos.z - centre.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < spec.rMin - 1e-6 or d > spec.rMax + 1e-6 then ringOk = false end
		local dy = c.pos.y - centre.y
		if dy < spec.yMin - 1e-6 or dy > spec.yMax + 1e-6 then heightOk = false end
		local sp = math.sqrt(c.vel.x ^ 2 + c.vel.y ^ 2 + c.vel.z ^ 2)
		if sp < spec.speedMin - 1e-6 or sp > spec.speedMax + 1e-6 then speedOk = false end
		if EnvBands.ambientExpired(c.pos, centre, spec) then freshOk = false end
	end
	truthy(ringOk, "ambient critters spawn in the ring between rMin and rMax around the camera")
	truthy(heightOk, "within the configured height band")
	truthy(speedOk, "at a speed inside the configured range")
	truthy(freshOk, "and are never born already expired")

	-- every critter eventually leaves (no permanent clutter), and none cuts straight at the camera
	local worstLife, closestPass = 0, math.huge
	for _ = 1, 300 do
		local c = EnvBands.ambientSpawn(centre, spec, r)
		local life = 0
		local p = c.pos
		while not EnvBands.ambientExpired(p, centre, spec) and life < 600 do
			p = { x = p.x + c.vel.x * 0.5, y = p.y + c.vel.y * 0.5, z = p.z + c.vel.z * 0.5 }
			local dx, dz = p.x - centre.x, p.z - centre.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < closestPass then closestPass = d end
			life += 0.5
		end
		if life > worstLife then worstLife = life end
	end
	truthy(worstLife < 600, "every critter flies out of range and is recycled (longest life " .. worstLife .. " s)")
	truthy(closestPass >= spec.rMin * 0.5,
		"critters cross the view, they never fly into the camera (closest " .. string.format("%.0f", closestPass) .. " studs)")

	local rising = { rMin = 100, rMax = 300, yMin = -200, yMax = 0, speedMin = 5, speedMax = 9, rise = true }
	local c = EnvBands.ambientSpawn(centre, rising, r)
	truthy(c.vel.y > 0 and c.vel.y >= math.sqrt(c.vel.x ^ 2 + c.vel.z ^ 2), "a `rise` critter (weather balloon) mostly rises")
	truthy(EnvBands.ambientExpired({ x = centre.x + 150, y = centre.y - 5000, z = centre.z }, centre, spec),
		"a critter left far below (the player respawned or was rescued) is expired at once")
end

--================================================================ capRates: the particle budget, enforced

-- Review 2026-09-17, round 2 (finding 4): weather rates are blended by band weight, and a band's weight
-- fades on a half-life, so a fast altitude change (a teleport between far bands) left the rain of one band,
-- the mist of another and the stardust of a third all switched on at once: 5 emitters against a budget of 4
-- (the docs said at most 2). capRates is what the client switches on: the strongest few, scaled together
-- under a total, nothing at or under a floor.
do
	truthy(type(EnvBands.capRates) == "function", "EnvBands.capRates exists")
	if type(EnvBands.capRates) == "function" then
		local input = { rain = 40, mist = 4, stardust = 5, ice = 10, petals = 0.03 }
		local out = EnvBands.capRates(input, 2, 60, 0.05)
		local n = 0
		for _ in out do n += 1 end
		eq(n, 2, "at most maxOn kinds are switched on")
		eq(out.rain, 40, "the strongest is kept at its rate")
		eq(out.ice, 10, "and the next strongest")
		eq(out.mist, nil, "weaker kinds are off")
		eq(input.rain, 40, "the input table is not modified")
		eq(input.mist, 4, "(any of it)")

		local scaled = EnvBands.capRates({ rain = 40, ice = 40 }, 2, 60, 0.05)
		approx(scaled.rain, 30, "over the total, the kept rates are scaled down together (rain)")
		approx(scaled.ice, 30, "(ice)")

		local floor = EnvBands.capRates({ petals = 0.05, mist = 0.06 }, 4, 60, 0.05)
		eq(floor.petals, nil, "a rate at the floor is off")
		approx(floor.mist, 0.06, "a rate above it is on")

		eq(next(EnvBands.capRates({ rain = 40 }, 0, 60, 0.05)), nil, "maxOn = 0 switches everything off")

		local tieA = EnvBands.capRates({ b = 5, a = 5, c = 5 }, 2, 60, 0.05)
		truthy(tieA.a ~= nil and tieA.b ~= nil and tieA.c == nil, "equal rates are broken by name, so the choice never flickers")

		-- property: random inputs
		local s = 99
		local function r()
			s = (1664525 * s + 1013904223) % 4294967296
			return s / 4294967296
		end
		local ok, why = true, nil
		local kinds = { "petals", "mist", "rain", "ice", "stardust", "snow" }
		for _ = 1, 3000 do
			local rates = {}
			for _, k in kinds do
				if r() < 0.7 then rates[k] = r() * 50 end
			end
			local maxOn = math.floor(r() * 4)
			local maxTotal = 10 + r() * 60
			local got = EnvBands.capRates(rates, maxOn, maxTotal, 0.05)
			local count, sum, minKept = 0, 0, math.huge
			for k, v in got do
				count += 1
				sum += v
				if v > rates[k] + 1e-9 then ok, why = false, "a rate was raised" end
				if rates[k] < minKept then minKept = rates[k] end
			end
			if count > maxOn then ok, why = false, "too many on" end
			if sum > maxTotal + 1e-6 then ok, why = false, "over the total" end
			for k, v in rates do
				if got[k] == nil and v > 0.05 and v > minKept + 1e-9 then ok, why = false, "a stronger kind was dropped" end
			end
		end
		truthy(ok, "3 000 random inputs: never more than maxOn on, never over the total, never raised, never a stronger kind dropped"
			.. (if why then " (" .. why .. ")" else ""))
	end
end

print(string.format("EnvBands: %d passed, %d failed", passed, failed))
assert(failed == 0, "EnvBands tests failed")
