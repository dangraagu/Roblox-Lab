-- Pure tests for Trace2D: the server's trusted position inside a raid pocket.
-- Run from the game directory: luau tests/Trace2D.spec.luau
local Config = require("../src/shared/Config")
local Layout = require("../src/shared/Layout")
local Heist = require("../src/shared/Heist")
local Trace2D = require("../src/shared/Trace2D")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function le(a, b, msg)
	if type(a) == "number" and a <= b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want <= " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b) .. " +- " .. tol)
	end
end

local DT = Config.Raid.TickSeconds
local WALK, CARRY = Config.Raid.WalkSpeed, Config.Raid.CarrySpeed

-- written out by hand: 16 * 1.35, and 16 * 1.35 * 0.5 for the longest server hitch credited
eq(WALK * Config.Raid.TrustedSpeedFactor, 21.6, "trusted walking cap 21.6 studs/s")
eq(WALK * Config.Raid.TrustedSpeedFactor * Config.Raid.MaxTrustedTickSeconds, 10.8, "a hitch credits at most 10.8 studs")

local function openPocket()
	local L = Layout.fromSpec(Config, { kind = "camp", lines = {}, rocks = {} })
	return L, Layout.freeRects(Config, L)
end

-- a pocket with one fence line on row 3 and a single gap at column 5 (x 32..40, z 40..48)
local function fencedPocket()
	local L = Layout.fromSpec(Config, { kind = "camp", lines = { { row = 3, cols = { 5 } } }, rocks = {} })
	return L, Layout.freeRects(Config, L)
end

local function idle(t, rects, seconds, speed)
	for _ = 1, math.floor(seconds / DT + 0.5) do
		Trace2D.step(Config, t, rects, t.x, t.z, DT, speed)
	end
end

--============================================================================ speed + burst

do
	local _, rects = openPocket()
	local t = Trace2D.new(Config, 36, 30)
	for _ = 1, 10 do
		Trace2D.step(Config, t, rects, 36, 84, DT, WALK)
	end
	near(t.z, 30 + 21.6, 1e-6, "one second of chasing a far claim moves exactly 21.6 studs")
	truthy(t.throttled >= 10, "every one of those ticks was throttled")
end

do
	-- REVIEW-1 R1-4 CHANGED THIS CONTRACT. There used to be a 0.5 s bank: standing still saved up
	-- 10.8 studs that one tick could spend. Heist.caught times each tick's segment over that tick,
	-- so a banked 10.8-stud jump spent 0.056 s inside a 6-stud net - inside the 0.2 s latency grace
	-- - and crossed a net already painted ON. Now no tick's segment is faster than the cap.
	local _, rects = openPocket()
	local t = Trace2D.new(Config, 36, 30)
	idle(t, rects, 2, WALK)
	Trace2D.step(Config, t, rects, 36, 70, DT, WALK)
	near(t.z, 30 + 2.16, 1e-6, "after two idle seconds a 40-stud teleport claim moves the trusted position 2.16 studs")
	Trace2D.step(Config, t, rects, 36, 70, DT, WALK)
	near(t.z, 30 + 4.32, 1e-6, "...and 2.16 studs the tick after")
	-- a server hitch: the tick's segment spans the whole hitch, so its speed stays under the cap
	Trace2D.step(Config, t, rects, 36, 70, 3, WALK)
	near(t.z, 30 + 4.32 + 10.8, 1e-6, "a 3 s server hitch credits at most 0.5 s = 10.8 studs")
end

do
	local _, rects = openPocket()
	local t = Trace2D.new(Config, 36, 30)
	idle(t, rects, 2, CARRY)
	for _ = 1, 10 do
		Trace2D.step(Config, t, rects, 36, 84, DT, CARRY)
	end
	near(t.z, 30 + 16.2, 1e-6, "carrying: 12 * 1.35 = 16.2 studs/s, idle or not")
end

do
	-- honest movement, including a half-second replication stall, is never throttled
	local _, rects = openPocket()
	local t = Trace2D.new(Config, 36, 20)
	local x, z = 36, 20
	local path = {}
	for i = 1, 40 do -- 4 s north along column 5 at 16 studs/s
		z = math.min(84, z + WALK * DT)
		table.insert(path, { x, z })
	end
	for i, p in path do
		if i >= 11 and i <= 15 then
			-- replication stall: the server keeps reading the position from tick 10
			Trace2D.step(Config, t, rects, path[10][1], path[10][2], DT, WALK)
		else
			Trace2D.step(Config, t, rects, p[1], p[2], DT, WALK)
		end
	end
	-- REVIEW-1 R1-4: without a bank the stall's 8-stud backlog is followed at the cap, 5.6 studs/s
	-- faster than walking: throttled for 14 ticks (1.4 s), never clamped, and it arrives.
	print(string.format("   0.5 s replication stall: throttled on %d ticks", t.throttled))
	le(t.throttled, 15, "an honest walker with a 0.5 s stall is throttled for at most 1.5 s of catch-up")
	near(t.z, 84, 1e-6, "...and ends where it walked")
	eq(t.clamped, 0, "...and never touched a wall")
end

--============================================================================ walls

do
	local _, rects = fencedPocket()
	local t = Trace2D.new(Config, 20, 36) -- cell (3,2)
	idle(t, rects, 1, WALK)
	for _ = 1, 20 do
		Trace2D.step(Config, t, rects, 20, 60, DT, WALK) -- straight through the fence at (3,3)
	end
	near(t.z, 41, 1e-6, "a noclip claim through a fence stops 1 stud into the fence (z 41)")
	truthy(t.clamped > 0, "...and counts as clamped")
	eq(t.x, 20, "...with no rerouting sideways towards the gap")

	-- no slit between two neighbouring fence cells: x = 16 is the seam of (2,3) and (3,3)
	local s = Trace2D.new(Config, 16, 36)
	idle(s, rects, 1, WALK)
	for _ = 1, 20 do Trace2D.step(Config, s, rects, 16, 60, DT, WALK) end
	near(s.z, 41, 1e-6, "the seam between two fence cells is not a way through")

	-- through the gap is fine, even hugging its edge 1 stud from the fence
	local g = Trace2D.new(Config, 33, 36)
	for _ = 1, 20 do Trace2D.step(Config, g, rects, 33, 60, DT, WALK) end
	near(g.z, 60, 1e-6, "an honest walker hugging the gap's edge passes")
	eq(g.clamped, 0, "...without a single clamp")

	-- along the fence face, 1 stud off it, end to end
	local w = Trace2D.new(Config, 1, 39)
	for _ = 1, 60 do Trace2D.step(Config, w, rects, 71, 39, DT, WALK) end
	near(w.x, 71, 1e-6, "walking the length of a fence 1 stud off its face")
	eq(w.clamped, 0, "...is never clamped")

	-- the pocket's own edge
	local e = Trace2D.new(Config, 4, 60)
	idle(e, rects, 1, WALK)
	for _ = 1, 10 do Trace2D.step(Config, e, rects, -30, 60, DT, WALK) end
	near(e.x, -1, 1e-6, "claims off the pocket floor stop 1 stud past its edge")

	-- the antechamber: row 0 is only the gate cell
	local a = Trace2D.new(Config, 36, 20)
	idle(a, rects, 1, WALK)
	for _ = 1, 10 do Trace2D.step(Config, a, rects, 10, 20, DT, WALK) end
	near(a.x, 31, 1e-6, "the antechamber's side walls hold at x 31")

	-- a garbage claim changes nothing
	local before = a.x
	Trace2D.step(Config, a, rects, 0 / 0, 20, DT, WALK)
	eq(a.x, before, "a NaN claim is ignored")
	Trace2D.step(Config, a, rects, nil, nil, DT, WALK)
	eq(a.x, before, "a missing claim is ignored")
	truthy(Trace2D.inside(rects, 36, 20), "the gate cell centre is inside the trusted map")
	truthy(not Trace2D.inside(rects, 20, 44), "a fence cell centre is not")
end

--============================================================================ teleport through an ON net

do
	-- REVIEW-1 R1-4, the reviewer's rev_bank as a pure test: stand 0.5 studs short of a net's
	-- danger area until the net turns ON, then claim a 10.7-stud jump across it. The net (5,3)
	-- danger area is z 41..47; ON starts at t 2.2 and the grace runs to 2.4.
	local L, rects = fencedPocket()
	Layout.place(Config, L, 5, 3, "laser")
	local trap = Layout.trapAt(L, 5, 3)
	trap.on, trap.off, trap.phase = 1.0, 2.2, 0
	local d = Layout.dangerRect(Config, L, 5, 3)
	eq(d.z0, 41, "the net's danger area starts at z 41")
	local t = Trace2D.new(Config, 36, d.z0 - 0.5)
	local clock = 0
	while clock < trap.off + 0.05 do -- the first tick after the net turns ON
		Trace2D.step(Config, t, rects, t.x, t.z, DT, WALK)
		clock += DT
	end
	local caught = nil
	for _ = 1, 10 do
		local px, pz, pt = t.x, t.z, clock
		Trace2D.step(Config, t, rects, 36, d.z0 - 0.5 + 10.7, DT, WALK)
		clock += DT
		caught = caught or Heist.caught(Config, Layout, L, px, pz, pt, t.x, t.z, clock)
		if caught then break end
	end
	eq(caught, trap, "a jump claimed the tick after the net turns ON is caught")
	-- the same crossing at the cap while the net is OFF is not
	eq(Heist.caught(Config, Layout, L, 36, 40.5, 0.5, 36, 47.5, 0.5 + 7 / 21.6), nil, "the same crossing while OFF is not")
end

--============================================================================ REVIEW-1.md B1: a freeze at a corner

-- An honest path that hugs a wall at clearance c, turns a right angle round the wall's corner and
-- walks on; `stall` seconds of it are replaced by the last position the server read (a replication
-- freeze), then the walker stands at its goal for 5 s. Returns how many freeze phases leave the
-- trusted position more than 1 stud from the walker, and the worst distance.
local function freezeSweep(rects, barriers, pathFn)
	local stuck, runs, worst, example = 0, 0, 0, nil
	for _, speed in { WALK, CARRY } do
		for _, c in { 1, 1.5, 2, 3, 4 } do
			local pts = pathFn(c, speed)
			for _, stall in { 0.2, 0.3, 0.4, 0.5, 0.7, 1.0 } do
				local ticks = math.floor(stall / DT + 0.5)
				for s = 2, #pts - ticks do
					runs += 1
					local t = Trace2D.new(Config, pts[1][1], pts[1][2])
					for i, p in pts do
						local claim = if i >= s and i < s + ticks then pts[s - 1] else p
						Trace2D.step(Config, t, rects, claim[1], claim[2], DT, speed, barriers)
					end
					local last = pts[#pts]
					for _ = 1, 50 do Trace2D.step(Config, t, rects, last[1], last[2], DT, speed, barriers) end
					local off = math.sqrt((t.x - last[1]) ^ 2 + (t.z - last[2]) ^ 2)
					worst = math.max(worst, off)
					if off > 1 then
						stuck += 1
						example = example or string.format("c %.1f, %.1f s freeze from tick %d: trusted (%.2f, %.2f), walker (%.2f, %.2f)", c, stall, s, t.x, t.z, last[1], last[2])
					end
				end
			end
		end
	end
	return stuck, runs, worst, example
end

-- east along z = z0 - c to x = x1 + c... then north: the corner of the wall block [x0, x1] x [z0, ...]
local function cornerPath(startX, turnX, wallZ0, endZ)
	return function(c, speed)
		local pts = {}
		local x, z = startX, wallZ0 - c
		local tx = turnX + c
		local step = speed * DT
		table.insert(pts, { x, z })
		while x < tx - 1e-9 do
			local nx = math.min(tx, x + step)
			local left = step - (nx - x)
			x = nx
			if left > 1e-9 then z += left end
			table.insert(pts, { x, z })
		end
		while z < endZ - 1e-9 do
			z = math.min(endZ, z + step)
			table.insert(pts, { x, z })
		end
		return pts
	end
end

do
	-- The reviewer's geometry: a fence line on row 4 (z 48..56) with one gap at column 5 (x 32..40).
	-- The walker comes east along row 3 hugging the fence, turns north into the gap. Measured on the
	-- 2026-09-17 build: a 0.5 s freeze left the trusted position at (31.00, 49.00) for good in 7 of
	-- 25 phases at c = 1, and every grab and escape was refused from then on.
	local L = Layout.fromSpec(Config, { kind = "camp", lines = { { row = 4, cols = { 5 } } }, rocks = {} })
	local rects, barriers = Layout.freeRects(Config, L)
	-- x 32 is the fence corner's west face; the path turns at 32 + c
	local stuck, runs, worst, example = freezeSweep(rects, barriers, cornerPath(8, 32, 48, 70))
	print(string.format("   corner into a gap: %d of %d freeze phases leave the trusted position behind (worst %.3f studs) %s", stuck, runs, worst, example or ""))
	eq(stuck, 0, "B1: no freeze while turning into a fence gap leaves the trusted position behind the fence")

	-- the same turn round a lone rock at (5,4): its west face x 32, its south face z 48, turning north at x 40 + c
	local R = Layout.fromSpec(Config, { kind = "camp", lines = {}, rocks = { { 5, 4 } } })
	local rr, rb = Layout.freeRects(Config, R)
	stuck, runs, worst, example = freezeSweep(rr, rb, cornerPath(8, 40, 48, 70))
	print(string.format("   corner round a rock: %d of %d freeze phases leave the trusted position behind (worst %.3f studs) %s", stuck, runs, worst, example or ""))
	eq(stuck, 0, "B1: no freeze while rounding a rock's corner leaves the trusted position behind the rock")
end

do
	-- The slide keeps every promise the straight move made: no tick moves farther than its budget,
	-- every point of the tick's path is on the map, and a noclip claim straight at a wall does not
	-- slide sideways at all.
	local L = Layout.fromSpec(Config, { kind = "camp", lines = { { row = 3, cols = { 2, 5, 8 } }, { row = 6, cols = { 4 } } },
		rocks = { { 3, 1 }, { 7, 4 }, { 6, 5 }, { 2, 7 } } })
	local rects, barriers = Layout.freeRects(Config, L)
	local rng = 12345
	local function rand()
		rng = (rng * 1103515245 + 12345) % 2147483648
		return rng / 2147483648
	end
	local over, off, notPath, n = 0, 0, 0, 0
	local t = Trace2D.new(Config, 36, 20)
	for _ = 1, 4000 do
		local cx, cz = rand() * 90 - 9, rand() * 90 + 10
		local x0, z0 = t.x, t.z
		Trace2D.step(Config, t, rects, cx, cz, DT, WALK, barriers)
		local p = t.path
		if type(p) ~= "table" or #p < 2 or p[1] ~= x0 or p[2] ~= z0 or p[#p - 1] ~= t.x or p[#p] ~= t.z then
			notPath += 1
		else
			local len = 0
			for i = 3, #p, 2 do
				len += math.sqrt((p[i] - p[i - 2]) ^ 2 + (p[i + 1] - p[i - 1]) ^ 2)
				if not Trace2D.inside(rects, p[i], p[i + 1]) then off += 1 end
			end
			if len > WALK * Config.Raid.TrustedSpeedFactor * DT + 1e-6 then over += 1 end
		end
		n += 1
	end
	eq(notPath, 0, "every tick records its path from the old trusted position to the new one")
	eq(over, 0, string.format("no tick's path is longer than the tick's budget (%d random claims)", n))
	eq(off, 0, "...and every point of it is on the map")
end

do
	-- REVIEW-1.md B1, the backstop: a trusted position that makes no progress towards a claim more than
	-- Raid.StuckStuds away counts the time; the server pulls the character back after StuckSeconds.
	-- Honest catch-up after a freeze always makes progress, so it never counts.
	local _, rects = fencedPocket()
	local t = Trace2D.new(Config, 20, 36)
	for _ = 1, 20 do Trace2D.step(Config, t, rects, 20, 60, DT, WALK) end
	truthy(type(t.stuck) == "number" and t.stuck >= Config.Raid.StuckSeconds,
		string.format("a claim held straight through a fence for 2 s counts as stuck (%s s)", tostring(t.stuck)))
	Trace2D.step(Config, t, rects, 20, 38, DT, WALK)
	eq(t.stuck, 0, "...and one tick of progress resets it")
	-- a freeze: the server read (36, 20) while the walker went on 24 studs through the gap; it keeps
	-- walking north at 16 studs/s and the trusted position chases it at 21.6
	local o = Trace2D.new(Config, 36, 20)
	local worstStuck = 0
	for i = 1, 60 do
		Trace2D.step(Config, o, rects, 36, math.min(84, 44 + 1.6 * i), DT, WALK)
		worstStuck = math.max(worstStuck, o.stuck or math.huge)
	end
	eq(worstStuck, 0, "an honest walker 24 studs ahead after a freeze, caught up through the gap, never counts as stuck")
	near(o.z, 84, 1e-6, "...and the trusted position arrives")

	-- where the pulled-back character stands: the trusted position moved into standable space, the
	-- 1-stud wall margin taken back out
	local sx, sz = Trace2D.settle(Config, rects, nil, 20, 41)
	eq(sz, 39, "a trusted position 1 stud into a fence settles 2 studs back from it (z 41 -> 39)")
	eq(sx, 20, "...without moving sideways")
	local ax, az = Trace2D.settle(Config, rects, nil, 36, 30)
	truthy(ax == 36 and az == 30, "a standable position settles where it is")
end

--============================================================================ REVIEW-1.md A6: corner squeezes

do
	-- Two rocks that touch at one corner leave 0.57 studs between their Parts: no body passes. The
	-- trusted map grows each floor cell by 1 stud, so the two floor cells on the other diagonal
	-- overlapped in a 2 x 2 square at the shared corner and the trusted position walked through.
	-- Measured on the 2026-09-17 build: a claim from (4,6) straight to (5,7) put the trusted position
	-- in (5,7) with rocks at (5,6) and (4,7).
	for _, case in {
		{ rocks = { { 5, 6 }, { 4, 7 } }, from = { 4, 6 }, to = { 5, 7 } },
		{ rocks = { { 5, 6 }, { 4, 7 } }, from = { 5, 7 }, to = { 4, 6 } },
		{ rocks = { { 4, 6 }, { 5, 7 } }, from = { 5, 6 }, to = { 4, 7 } },
		{ rocks = { { 4, 6 }, { 5, 7 } }, from = { 4, 7 }, to = { 5, 6 } },
	} do
		local L = Layout.fromSpec(Config, { kind = "camp", lines = {}, rocks = case.rocks })
		local rects, barriers = Layout.freeRects(Config, L)
		local fx, fz = Layout.cellCenter(Config, case.from[1], case.from[2])
		local tx, tz = Layout.cellCenter(Config, case.to[1], case.to[2])
		local label = string.format("rocks (%d,%d)+(%d,%d), (%d,%d) -> (%d,%d)", case.rocks[1][1], case.rocks[1][2],
			case.rocks[2][1], case.rocks[2][2], case.from[1], case.from[2], case.to[1], case.to[2])
		local passedThrough = 0
		-- straight through the shared corner, and a spread of chords a little either side of it
		local len = math.sqrt((tx - fx) ^ 2 + (tz - fz) ^ 2)
		local px, pz = -(tz - fz) / len, (tx - fx) / len
		for _, off in { 0, 0.3, -0.3, 0.7, -0.7, 0.95, -0.95, 1.4, -1.4 } do
			local t = Trace2D.new(Config, fx, fz)
			for _ = 1, 30 do Trace2D.step(Config, t, rects, tx + px * off, tz + pz * off, DT, WALK, barriers) end
			local c, r = Layout.cellAt(Config, t.x, t.z)
			if c == case.to[1] and r == case.to[2] then passedThrough += 1 end
		end
		-- and a walker whose claims step along the diagonal, one of them landing exactly ON the shared
		-- corner (a first version computed that hit at s = 1 + 2e-16, missed it, and stood on the barrier)
		do
			local t = Trace2D.new(Config, fx, fz)
			for j = 1, 12 do
				local f = math.min(1, j / 8)
				Trace2D.step(Config, t, rects, fx + (tx - fx) * f, fz + (tz - fz) * f, DT, WALK, barriers)
			end
			-- which side of the corner it ends on: its distance along the diagonal from the corner
			local vx, vz = (fx + tx) / 2, (fz + tz) / 2
			if (t.x - vx) * (tx - fx) + (t.z - vz) * (tz - fz) >= 0 then passedThrough += 1 end
		end
		eq(passedThrough, 0, "A6: the trusted position never squeezes between corner-touching rocks: " .. label)
		truthy(barriers ~= nil and #barriers >= 1, "A6: the shared corner carries a barrier: " .. label)
	end
	-- the exact-corner walk at EVERY corner of the yard, both diagonals, both directions. Which corners
	-- round s to 1 + 2e-16 depends on the coordinates: a first sweep mutation dropped the tolerance and
	-- the four cases above did not notice (35 of these 192 walks then end on or past the corner)
	do
		local onOrPast, walks = 0, 0
		for col = 1, 8 do
			for row = 1, 6 do
				for _, o in { 1, 2 } do
					local rocks = if o == 1 then { { col + 1, row }, { col, row + 1 } } else { { col, row }, { col + 1, row + 1 } }
					local L = Layout.fromSpec(Config, { kind = "camp", lines = {}, rocks = rocks })
					local rects, barriers = Layout.freeRects(Config, L)
					local cells = if o == 1 then { { col, row }, { col + 1, row + 1 } } else { { col + 1, row }, { col, row + 1 } }
					for _, dir in { { 1, 2 }, { 2, 1 } } do
						local fx, fz = Layout.cellCenter(Config, cells[dir[1]][1], cells[dir[1]][2])
						local tx, tz = Layout.cellCenter(Config, cells[dir[2]][1], cells[dir[2]][2])
						local t = Trace2D.new(Config, fx, fz)
						for j = 1, 12 do
							local f = math.min(1, j / 8)
							Trace2D.step(Config, t, rects, fx + (tx - fx) * f, fz + (tz - fz) * f, DT, WALK, barriers)
						end
						walks += 1
						local vx, vz = (fx + tx) / 2, (fz + tz) / 2
						if (t.x - vx) * (tx - fx) + (t.z - vz) * (tz - fz) >= 0 then onOrPast += 1 end
					end
				end
			end
		end
		eq(onOrPast, 0, string.format("A6: of %d walks whose claims land exactly ON a squeezed corner, none ends on or past it", walks))
	end
	-- the honest detour round a pair: (4,6) -> (4,5) -> (5,5) -> (6,5) -> (6,6) -> (6,7) -> (5,7)
	local L = Layout.fromSpec(Config, { kind = "camp", lines = {}, rocks = { { 5, 6 }, { 4, 7 } } })
	local rects, barriers = Layout.freeRects(Config, L)
	local t = Trace2D.new(Config, Layout.cellCenter(Config, 4, 6))
	for _, cell in { { 4, 5 }, { 5, 5 }, { 6, 5 }, { 6, 6 }, { 6, 7 }, { 5, 7 } } do
		local x, z = Layout.cellCenter(Config, cell[1], cell[2])
		for _ = 1, 10 do Trace2D.step(Config, t, rects, x, z, DT, WALK, barriers) end
	end
	local ex, ez = Layout.cellCenter(Config, 5, 7)
	truthy(t.x == ex and t.z == ez, string.format("A6: the honest way round the pair arrives (%.2f, %.2f)", t.x, t.z))
	eq(t.clamped, 0, "A6: ...without a clamp")
	-- and a wall-hugging honest walker passes along the pinch's outside faces untouched: along row 5
	-- 1 stud off rock (5,6)'s south face, x 20..56
	local w = Trace2D.new(Config, 20, 63)
	for _ = 1, 30 do Trace2D.step(Config, w, rects, 56, 63, DT, WALK, barriers) end
	truthy(w.x == 56 and w.clamped == 0, "A6: hugging the rock's face 1 stud off is never clamped")
end

print(string.format("Trace2D: %d passed, %d failed", passed, failed))
if failed > 0 then error("Trace2D tests failed") end
