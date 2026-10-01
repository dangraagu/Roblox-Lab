-- Spec for Dungeon: the daily generator, placement, the perfect line, the stored record.
-- Run: luau tests/Dungeon.spec.luau
--
-- src/server/Dungeon.luau lives in ServerScriptService, so it never replicates. It takes its random
-- source as an argument: on the server that is two Roblox Randoms XORed (DESIGN §3.1); here it is the
-- repo's deterministic Rng, read through its high bits (checklist: never `state % span`).
--
-- What is pinned:
--   * the maze is one connected piece: a spanning tree plus exactly Loops extra openings;
--   * placement: seal A 3..6 steps in, B and C >= 6, seals pairwise >= 6, the Door far and clear;
--   * the funnel is the string-pulled route (checked against an analytic L-turn);
--   * P is the shortest line in the whole-run check's own geometry: a 16 studs/s walk of it finishes in
--     P and is ranked, the same walk at 1.03x is voided, an independent sampled search finds nothing
--     shorter, and every accepted day has MinSeconds <= P <= MaxSeconds;
--   * hazards: 3 fork cells, >= 3 from the entrance, never a seal / the Door, pairwise >= 4;
--   * the record round-trips, and validation FAILS CLOSED on every corruption tried;
--   * the mint depends only on the draws it is given (no hidden global randomness).
local Dungeon = require("../src/server/Dungeon")
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, msg, tol)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-3) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local cfg = Config
local W, H = cfg.Grid.W, cfg.Grid.H
local function drawOf(seed)
	local r = Rng.new(seed)
	return function(n) return r:below(n) end
end

--================================================================ the funnel against geometry
do
	-- a 3x3 maze with every passage open: the funnel only sees the cells it is handed
	local m = Dungeon.newMaze(3, 3)
	for i = 0, 8 do m.openE[i] = (i % 3) < 2; m.openN[i] = (i // 3) < 2 end
	local function C(x, y) return y * 3 + x end
	local function len(cells)
		local s = { x = (cells[1] % 3 + 0.5) * 16, y = (cells[1] // 3 + 0.5) * 16 }
		local e = { x = (cells[#cells] % 3 + 0.5) * 16, y = (cells[#cells] // 3 + 0.5) * 16 }
		return (Dungeon.funnel(m, cells, s, e, 16, 2.5))
	end
	approx(len({ C(0, 0), C(1, 0), C(2, 0) }), 32, "a straight run of 3 cells is 32 studs centre to centre")
	approx(len({ C(0, 0), C(0, 1), C(1, 1) }), 22.952, "an L-turn with a 2.5 margin is 22.952 (analytic)")
	approx(len({ C(0, 0), C(1, 0), C(1, 1) }), 22.952, "the mirrored L-turn is the same")
end

--================================================================ the perfect line is the SHORTEST line
-- Found by tests/walk.luau (2026-10-01): a player who planned over only the halls it had SEEN walked
-- 501.6 studs where the day's "perfect" line measured 517.6, because P was the funnel along ONE
-- min-step cell path (BFS order). Equal-step paths, and paths a step or two longer, can string-pull
-- shorter. Measured over 200 days (design/measure/pgap.luau): a shorter line existed on 54 % of days,
-- p10 3.7 % and worst 8.3 % shorter. P must be the minimum over orders AND over cell paths.
do
	-- a staircase and an L with the SAME step count: the BFS takes the L, the staircase is shorter
	local m = Dungeon.newMaze(3, 3)
	local function C(x, y) return y * 3 + x end
	m.openE[C(0, 0)] = true -- (0,0)-(1,0)
	m.openE[C(1, 0)] = true -- (1,0)-(2,0)      the L: east, east, north, north
	m.openN[C(2, 0)] = true -- (2,0)-(2,1)
	m.openN[C(2, 1)] = true -- (2,1)-(2,2)
	m.openN[C(1, 0)] = true -- (1,0)-(1,1)      the staircase: east, north, east, north
	m.openE[C(1, 1)] = true -- (1,1)-(2,1)
	local s = { x = 8, y = 8 }
	local e = { x = 40, y = 40 }
	local lenL = (Dungeon.funnel(m, { C(0, 0), C(1, 0), C(2, 0), C(2, 1), C(2, 2) }, s, e, 16, 2.5))
	local lenS = (Dungeon.funnel(m, { C(0, 0), C(1, 0), C(1, 1), C(2, 1), C(2, 2) }, s, e, 16, 2.5))
	truthy(lenS < lenL - 1, string.format("the staircase (%.2f) is shorter than the L (%.2f) with the same 4 steps", lenS, lenL))
	local len, pts, cells = Dungeon.shortestLeg(m, C(0, 0), C(2, 2), s, e, 16, 2.5, 4, 100000)
	approx(len, lenS, "shortestLeg finds the staircase's length")
	eq(cells and cells[3], C(1, 1), "…through the staircase's cells")
	eq(pts and #pts >= 2, true, "…and returns its pulled points")
	-- a longer-in-steps path that is shorter in studs is found too: a U-bend vs a straight corridor
	local u = Dungeon.newMaze(3, 3)
	u.openE[C(0, 0)] = true; u.openE[C(1, 0)] = true -- straight row 0: 2 steps (0,0)->(2,0)
	local ls = Dungeon.shortestLeg(u, C(0, 0), C(2, 0), { x = 8, y = 8 }, { x = 40, y = 8 }, 16, 2.5, 4, 100000)
	approx(ls, 32, "a straight corridor is 32 studs")
	eq(select(1, Dungeon.shortestLeg(u, C(0, 0), C(2, 2), { x = 8, y = 8 }, { x = 40, y = 40 }, 16, 2.5, 4, 100000)), math.huge,
		"an unreachable cell has no leg")
end

--================================================================ P is the server's own lower bound
-- REVIEW-1 findings 2 and 5 (2026-10-01). The whole-run check (RunCheck.finishCheck) holds a run to
-- the TAUT line through the halls it took, at 16 x 1.02: Check.TautMargin off every jamb, each seal
-- taken where the walk first comes within Pickup.Radius of it, the clock from the line crossing to the
-- first point within Pickup.Radius of the Door. The first build's P ran centre to centre at a 2.5
-- margin from a fixed start point, so the server's own taut line of a walk of P was 0.915-0.973 of P:
-- a script walking the published line at 1.05-1.11x passed the check and beat every honest player
-- who walked it, every honest walk of P beat "perfect" (0.989-0.993 P), and the medal slack varied by
-- day. P is now the shortest line in the server's own geometry (Dungeon.tightLine): the start
-- anywhere on the line, each seal touched PickupInset inside its pickup circle (so a 60 Hz walk of the
-- published line surely takes it), the end on the Door's pickup circle, TautMargin off the jambs.
local DUNGEON_PERMS = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
do
	local RunState = require("../src/server/RunState")
	local RunCheck = require("../src/server/RunCheck")
	local Grid = require("../src/shared/Grid")
	local DEPS = { RunCheck = RunCheck, Grid = Grid, Dungeon = Dungeon }
	local CELL = cfg.Grid.Cell
	local margin = cfg.Check.TautMargin
	local inset = cfg.Perfect.PickupInset or 0.25
	local Rs, Rd = cfg.Pickup.Radius - inset, cfg.Pickup.Radius

	-- walk P's published polyline from the antechamber at 16 * factor studs/s, 60 Hz, through the
	-- real RunState / RunCheck. ("finish", ms) | ("void", reason) | ("none")
	local function walkP(w: any, factor: number): (string, any)
		local _, pts = Dungeon.perfectPath(cfg, w)
		local list = { { x = 72, z = -8 } }
		for _, p in pts do table.insert(list, p) end
		-- and keep walking 2 studs on into the Door's circle, as a player does: a walker that stops
		-- dead on the line's last point is seen one frame late (the server interpolates the entry
		-- along the last sample step as if the walk had moved all of it)
		local a, b = list[#list - 1], list[#list]
		local L = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		table.insert(list, { x = b.x + (b.x - a.x) / L * 2, z = b.z + (b.z - a.z) / L * 2 })
		local run = RunState.new(cfg, w, DEPS)
		RunState.arrive(run)
		local seg, x, z, dt = 1, 72, -8, 1 / 60
		local idle = 0
		for _ = 1, 60 * 120 do
			local remaining = 16 * factor * dt
			while remaining > 0 and seg < #list do
				local b = list[seg + 1]
				local dx, dz = b.x - x, b.z - z
				local d = math.sqrt(dx * dx + dz * dz)
				if d <= remaining then x, z = b.x, b.z; remaining -= d; seg += 1 else x += dx / d * remaining; z += dz / d * remaining; remaining = 0 end
			end
			for _, e in RunState.step(run, dt, x, 3, z) do
				if e.type == "finish" then return "finish", e.timeMs end
				if e.type == "void" then return "void", e.reason end
			end
			if seg >= #list then
				idle += 1
				if idle > 30 then break end
			end
		end
		return "none", nil
	end

	local days, ranked, under, over, caught, worstUnder, worstOver = 40, 0, 0, 0, 0, 0, 0
	local firstBad = nil
	for sd = 1, days do
		local rec = Dungeon.mint(cfg, drawOf(sd * 7919 + 5), 20726, 1790730000)
		local w = Dungeon.fromRecord(cfg, rec)
		local how, v = walkP(w, 1.00)
		if how == "finish" then
			ranked += 1
			if v < rec.perfectMs - 1 then under += 1; worstUnder = math.max(worstUnder, rec.perfectMs - v) end
			if v > rec.perfectMs + 2 then over += 1; worstOver = math.max(worstOver, v - rec.perfectMs) end
		else
			firstBad = firstBad or (how .. ": " .. tostring(v))
		end
		local how3 = walkP(w, 1.03)
		if how3 == "void" then caught += 1 end
	end
	eq(ranked, days, string.format("a 16 studs/s walk of the published P finishes ranked on every one of %d days%s", days,
		if firstBad then " (" .. firstBad .. ")" else ""))
	eq(under, 0, string.format("…and never beats P by more than a millisecond (worst %d ms under)", worstUnder))
	eq(over, 0, string.format("…and P is reachable: the walk's official time is P within 2 ms (worst %d ms over)", worstOver))
	eq(caught, days, string.format("a script walking the published P at 1.03x is voided on every day (%d of %d)", caught, days))

	-- An independent search: every seal order, every simple cell path up to 6 steps over the BFS
	-- distance (enumerated HERE), the start sampled every stud along the line and each pickup circle at
	-- 24 points, best line by dynamic programming. Sampling makes it an upper bound on the true
	-- minimum, so it can only ever show P too LONG: it must not find a line shorter than P.
	local function centre(i) return { x = (i % W + 0.5) * CELL, y = (i // W + 0.5) * CELL } end
	local function paths(m, a, b, sRef, eRef, reach)
		local dist = Dungeon.bfs(m, b)
		local limit = dist[a] + 6
		local all, best = {}, math.huge
		local path, on = { a }, { [a] = true }
		local function dfs(c, depth)
			if c == b then
				local l = Dungeon.funnel(m, path, sRef, eRef, CELL, margin)
				table.insert(all, { l = l, cells = table.clone(path) })
				if l < best then best = l end
				return
			end
			for _, n in Dungeon.neighbours(m, c) do
				if not on[n] and depth + 1 + dist[n] <= limit then
					on[n] = true; table.insert(path, n); dfs(n, depth + 1); table.remove(path); on[n] = nil
				end
			end
		end
		dfs(a, 0)
		-- moving an end by d changes a corridor's line by at most d (1-Lipschitz), so only corridors
		-- within 2 x (both ends' reach) of the best at the reference ends can win
		local keep = {}
		for _, p in all do if p.l <= best + 2 * reach + 0.5 then table.insert(keep, p.cells) end end
		return keep
	end
	local K = 24
	local function ring(c, r)
		local out = {}
		for k = 0, K - 1 do
			local a = 2 * math.pi * k / K
			table.insert(out, { x = c.x + r * math.cos(a), y = c.y + r * math.sin(a) })
		end
		return out
	end
	local searchDays, shorter, worstGap = 8, 0, 0
	local lo, hi = cfg.Grid.EntranceX * CELL + margin, (cfg.Grid.EntranceX + 1) * CELL - margin
	for sd = 1, searchDays do
		local rec = Dungeon.mint(cfg, drawOf(sd * 104729 + 11), 20726, 1790730000)
		local w = Dungeon.fromRecord(cfg, rec)
		local m = w.maze
		local e = w.entrance
		local starts = {}
		for x = lo, hi do table.insert(starts, { x = x, y = 0 }) end
		local best = math.huge
		for _, o in DUNGEON_PERMS do
			local seq = { e, w.seals[o[1]], w.seals[o[2]], w.seals[o[3]], w.door }
			local stages = { starts }
			for k = 2, 4 do table.insert(stages, ring(centre(seq[k]), Rs)) end
			table.insert(stages, ring(centre(seq[5]), Rd))
			local cost = {}
			for j in stages[1] do cost[j] = 0 end
			for k = 1, 4 do
				local sRef = if k == 1 then { x = (lo + hi) / 2, y = 0 } else centre(seq[k])
				local reachA = if k == 1 then (hi - lo) / 2 else Rs
				local reachB = if k == 4 then Rd else Rs
				local cands = paths(m, seq[k], seq[k + 1], sRef, centre(seq[k + 1]), reachA + reachB)
				local nextCost = {}
				for j, q in stages[k + 1] do
					local bestJ = math.huge
					for i, p in stages[k] do
						for _, c in cands do
							local l = cost[i] + Dungeon.funnel(m, c, p, q, CELL, margin)
							if l < bestJ then bestJ = l end
						end
					end
					nextCost[j] = bestJ
				end
				cost = nextCost
			end
			for _, c in cost do best = math.min(best, c) end
		end
		local P = rec.perfectMs / 1000 * cfg.Walk.Speed
		if best < P - 0.05 then shorter += 1; worstGap = math.max(worstGap, P - best) end
	end
	eq(shorter, 0, string.format("an independent sampled search finds no line shorter than P on any of %d days (worst %.2f studs)",
		searchDays, worstGap))
end

do -- a corridor switch the descent alone missed. RECORDED (not invented) from tests/walk.luau -a 8 on
	-- 2026-10-01, this pass: the day's maze, its placement and the passages the walker had seen. Over
	-- those passages its own tight line was 367.52 studs and the day's P 369.37: P's descent had settled
	-- on one corridor for the leg between the seals at (6, 4) and (2, 4), and the shorter corridor only
	-- pays once both touch points move to suit it. P must never be longer than a line over a subset of
	-- its own passages.
	local m = Dungeon.decodeOpen("e9a75f369571d67585c66556678a7db7549daaa80", 9, 9)
	local km = Dungeon.newMaze(9, 9)
	local seen = "E:0,7;E:0,8;E:1,1;E:1,6;E:1,8;E:2,1;E:2,3;E:2,5;E:2,8;E:3,2;E:3,4;E:3,6;E:3,8;E:4,0;E:4,5;E:4,6;E:4,8;E:5,0;E:5,4;E:5,7;"
		.. "E:5,8;E:6,1;E:6,5;E:6,6;E:6,8;E:7,0;E:7,1;E:7,5;E:7,6;E:7,7;N:0,7;N:1,7;N:2,1;N:2,2;N:2,3;N:2,4;N:2,6;N:2,7;N:3,2;N:3,3;"
		.. "N:3,5;N:3,6;N:3,7;N:4,1;N:4,3;N:4,4;N:4,6;N:5,5;N:5,6;N:6,0;N:6,4;N:6,5;N:6,7;N:7,0;N:7,2;N:7,3;N:7,4;N:7,6;N:7,7;N:8,0;"
		.. "N:8,1;N:8,2;N:8,3;N:8,4;N:8,6;N:8,7"
	local subset = true
	for key in string.gmatch(seen, "[^;]+") do
		local k, x, y = string.match(key, "^([EN]):(%d+),(%d+)$")
		local i = tonumber(y) * 9 + tonumber(x)
		if k == "E" then km.openE[i] = true; subset = subset and m.openE[i] else km.openN[i] = true; subset = subset and m.openN[i] end
	end
	truthy(m ~= nil and subset, "the recorded passages are a subset of the recorded maze")
	local full = Dungeon.tightLine(cfg, m, { entrance = 4, seals = { 8, 38, 42 }, door = 74 })
	local own = Dungeon.tightLine(cfg, km, { entrance = 4, seals = { 8, 42, 38 }, door = 74 })
	truthy(full <= own + 1e-6, string.format("P over every passage (%.2f) is no longer than the line over the walker's passages (%.2f)", full, own))
end

do -- perfectPath is exactly the stored P
	local off = 0
	for sd = 1, 30 do
		local rec = Dungeon.mint(cfg, drawOf(sd * 104729 + 11), 20726, 1790730000)
		local w = Dungeon.fromRecord(cfg, rec)
		local lineLen, pts = Dungeon.perfectPath(cfg, w)
		local walked = 0
		for k = 2, #pts do walked += math.sqrt((pts[k].x - pts[k - 1].x) ^ 2 + (pts[k].z - pts[k - 1].z) ^ 2) end
		if math.abs(lineLen / cfg.Walk.Speed * 1000 - rec.perfectMs) > 1 or math.abs(walked - lineLen) > 1e-6 then off += 1 end
	end
	eq(off, 0, "perfectPath's points measure exactly the stored P on every day")
end

--================================================================ many mints
local N = 300
local lens, attemptsTotal, accepted = {}, 0, 0
local bad = { conn = 0, edges = 0, perim = 0, sealA = 0, sealB = 0, sealSep = 0, door = 0, hz = 0, band = 0, valid = 0, rt = 0 }
local firstErr = nil
for s = 1, N do
	local rec, attempts = Dungeon.mint(cfg, drawOf(s * 7907 + 3), 20726, 1790730000)
	if rec == nil then
		bad.valid += 1
		continue
	end
	accepted += 1
	attemptsTotal += attempts
	local world = Dungeon.fromRecord(cfg, rec)
	local m = world.maze
	-- connectivity and edge count
	local dist = Dungeon.bfs(m, world.entrance)
	local reach, openEdges = 0, 0
	for i = 0, W * H - 1 do
		if dist[i] then reach += 1 end
		if m.openE[i] then openEdges += 1 end
		if m.openN[i] then openEdges += 1 end
		local x, y = i % W, i // W
		if (x == W - 1 and m.openE[i]) or (y == H - 1 and m.openN[i]) then bad.perim += 1 end
	end
	if reach ~= W * H then bad.conn += 1 end
	if openEdges ~= W * H - 1 + cfg.Grid.Loops then bad.edges += 1 end
	-- placement
	local sA, sB, sC = world.seals[1], world.seals[2], world.seals[3]
	if not (dist[sA] >= 3 and dist[sA] <= 6) then bad.sealA += 1 end
	if dist[sB] < 6 or dist[sC] < 6 then bad.sealB += 1 end
	local dA, dB, dC = Dungeon.bfs(m, sA), Dungeon.bfs(m, sB), Dungeon.bfs(m, sC)
	if dA[sB] < 6 or dA[sC] < 6 or dB[sC] < 6 then bad.sealSep += 1 end
	local maxE = 0
	for _, d in dist do maxE = math.max(maxE, d) end
	local door = world.door
	if dist[door] < 0.6 * maxE or dA[door] < 4 or dB[door] < 4 or dC[door] < 4 then bad.door += 1 end
	-- hazards
	if #world.hazards ~= 3 then bad.hz += 1 end
	for k, hz in world.hazards do
		if hz.slot ~= k then bad.hz += 1 end
		if #Dungeon.neighbours(m, hz.cell) < 3 then bad.hz += 1 end
		if dist[hz.cell] < 3 then bad.hz += 1 end
		if hz.cell == sA or hz.cell == sB or hz.cell == sC or hz.cell == door then bad.hz += 1 end
		local dh = Dungeon.bfs(m, hz.cell)
		for j = k + 1, #world.hazards do
			if dh[world.hazards[j].cell] < 4 then bad.hz += 1 end
		end
	end
	-- the band
	if rec.perfectMs < cfg.Perfect.MinSeconds * 1000 or rec.perfectMs > cfg.Perfect.MaxSeconds * 1000 then bad.band += 1 end
	table.insert(lens, rec.perfectMs)
	-- validation and a JSON-like round trip (string keys, dense arrays, as the DataStore stores it)
	local ok, err = Dungeon.validate(cfg, rec, 20726)
	if not ok then bad.valid += 1; firstErr = firstErr or err end
	local copy = {}
	for k, v in rec do copy[k] = v end
	local ok2 = Dungeon.validate(cfg, copy, 20726)
	if not ok2 then bad.rt += 1 end
end
eq(accepted, N, "every one of " .. N .. " mints produced a record within the attempt cap")
eq(bad.conn, 0, "every maze is one connected piece")
eq(bad.edges, 0, "every maze has exactly W*H - 1 + Loops = 88 open passages (56 interior walls)")
eq(bad.perim, 0, "no passage opens through the perimeter")
eq(bad.sealA, 0, "seal A is always 3..6 steps from the entrance")
eq(bad.sealB, 0, "seals B and C are always >= 6 from the entrance")
eq(bad.sealSep, 0, "the seals are always pairwise >= 6 apart")
eq(bad.door, 0, "the Door is always far (>= 0.6 max) and >= 4 from every seal")
eq(bad.hz, 0, "every day has 3 fork hazards, >= 3 in, never on a seal or the Door, pairwise >= 4, slots 1..3")
eq(bad.band, 0, string.format("every accepted day has %d s <= P <= %d s", cfg.Perfect.MinSeconds, cfg.Perfect.MaxSeconds))
eq(bad.valid, 0, "every minted record validates" .. (firstErr and (" (" .. firstErr .. ")") or ""))
eq(bad.rt, 0, "a field-by-field copy validates too")
table.sort(lens)
local meanAttempts = attemptsTotal / math.max(accepted, 1)
print(string.format("  %d mints: P p10 %.1f s, p50 %.1f s, p90 %.1f s; mean attempts %.2f (acceptance %.1f%%)",
	accepted, lens[math.floor(#lens * 0.1)] / 1000, lens[math.floor(#lens * 0.5)] / 1000, lens[math.floor(#lens * 0.9)] / 1000,
	meanAttempts, 100 / meanAttempts))
truthy(meanAttempts >= 1 and meanAttempts <= 2, "a mint takes 1..2 attempts on average (the design measured 1.36)")

--================================================================ determinism: only the draws decide
do
	local a = Dungeon.mint(cfg, drawOf(42), 20726, 1790730000)
	local b = Dungeon.mint(cfg, drawOf(42), 20726, 1790730000)
	local c = Dungeon.mint(cfg, drawOf(43), 20726, 1790730000)
	eq(a.open, b.open, "the same draws make the same maze")
	eq(a.perfectMs, b.perfectMs, "…and the same perfect line")
	truthy(a.open ~= c.open, "different draws make a different maze")
	eq(a.day, 20726, "the record carries its day")
	eq(a.v, cfg.Day.RecordVersion, "the record carries its version")
	eq(a.studio, nil, "a minted record is not a Studio door")
	eq(#a.open, 41, "the open string is 41 hex digits (162 bits)")
end

--================================================================ the open string round trip
do
	local rec = Dungeon.mint(cfg, drawOf(7), 20726, 1790730000)
	local m = Dungeon.decodeOpen(rec.open, W, H)
	truthy(m ~= nil, "the open string decodes")
	eq(Dungeon.encodeOpen(m :: any), rec.open, "encode(decode(open)) == open")
	eq(Dungeon.decodeOpen(string.sub(rec.open, 1, 40), W, H), nil, "a short string does not decode")
	eq(Dungeon.decodeOpen(string.sub(rec.open, 1, 40) .. "g", W, H), nil, "a non-hex digit does not decode")
end

--================================================================ validation fails closed
do
	local base = Dungeon.mint(cfg, drawOf(99), 20726, 1790730000)
	local function variant(f)
		local r = table.clone(base)
		r.seals = { table.clone(base.seals[1]), table.clone(base.seals[2]), table.clone(base.seals[3]) }
		r.hazards = { table.clone(base.hazards[1]), table.clone(base.hazards[2]), table.clone(base.hazards[3]) }
		r.door = table.clone(base.door)
		r.entrance = table.clone(base.entrance)
		f(r)
		return Dungeon.validate(cfg, r, 20726)
	end
	truthy((Dungeon.validate(cfg, base, 20726)), "the base record validates")
	eq((variant(function(r) r.v = cfg.Day.RecordVersion + 1 end)), false, "an unknown version is refused")
	eq((variant(function(r) r.v = 1 end)), false, "a version-1 record (the first build's P) is refused")
	eq((variant(function(r) r.w = 11 end)), false, "a wrong width is refused")
	eq((variant(function(r) r.perfectMs += 2 end)), false, "a perfectMs 2 ms off is refused (this server builds a different dungeon)")
	eq((variant(function(r) r.perfectMs += 1 end)), true, "a perfectMs 1 ms off is within the rounding tolerance")
	eq((variant(function(r) r.seals[2] = table.clone(r.seals[1]) end)), false, "two seals on one cell are refused")
	eq((variant(function(r) r.door = table.clone(r.entrance) end)), false, "the Door on the entrance is refused")
	eq((variant(function(r) r.entrance = { x = 0, y = 0 } end)), false, "a moved entrance is refused")
	eq((variant(function(r) r.hazards[1].slot = 2 end)), false, "a duplicated hazard slot is refused")
	eq((variant(function(r) r.hazards[1] = { x = r.seals[1].x, y = r.seals[1].y, slot = 1 } end)), false, "a hazard on a seal is refused")
	eq((variant(function(r) r.day = 20725 end)), false, "a record for another day is refused")
	eq((variant(function(r) r.seals[1] = { x = 99, y = 0 } end)), false, "a seal off the grid is refused")
	eq((variant(function(r) r.seals[1] = { x = 1.5, y = 0 } end)), false, "a fractional coordinate is refused")
	eq((variant(function(r)
		-- flip the first set bit of the open string: a different maze under the same placement
		local s = r.open
		for i = 1, #s do
			local d = tonumber(string.sub(s, i, i), 16)
			if d and d > 0 then
				r.open = string.sub(s, 1, i - 1) .. string.format("%x", d - 1) .. string.sub(s, i + 1)
				break
			end
		end
	end)), false, "a single flipped passage bit is refused")
	eq((Dungeon.validate(cfg, nil, 20726)), false, "nil is refused")
	eq((Dungeon.validate(cfg, "junk", 20726)), false, "a string is refused")
end

--================================================================ fails closed after the attempt cap
do
	local strict = table.clone(cfg)
	strict.Perfect = table.clone(cfg.Perfect)
	strict.Perfect.MinSeconds = 1000
	strict.Perfect.MaxSeconds = 1001
	local rec, attempts = Dungeon.mint(strict, drawOf(5), 20726, 1790730000)
	eq(rec, nil, "an impossible band yields no record")
	eq(attempts, cfg.Perfect.MaxAttempts, "after exactly MaxAttempts attempts")
end

--================================================================ the Studio door
do
	local a = Dungeon.studioDoor(cfg, Rng, 20726, 1790730000)
	local b = Dungeon.studioDoor(cfg, Rng, 20726, 1790730000)
	eq(a.open, b.open, "the Studio door is the same every time (for the night shift's shots)")
	eq(a.studio, true, "and it is marked studio (never ranked)")
	truthy((Dungeon.validate(cfg, a, 20726)), "and it is a valid dungeon")
end

--================================================================ payloads and reveal
do
	local rec = Dungeon.mint(cfg, drawOf(11), 20726, 1790730000)
	local world = Dungeon.fromRecord(cfg, rec)
	local m = world.maze
	local mismatch = 0
	for i = 0, W * H - 1 do
		local p = Dungeon.cellPayload(world, i)
		local x, y = i % W, i // W
		if p.x ~= x or p.y ~= y then mismatch += 1 end
		local open = {}
		for _, n in Dungeon.neighbours(m, i) do open[n] = true end
		local want = 0
		if open[i + W] then want += 1 end
		if x + 1 < W and open[i + 1] then want += 2 end
		if open[i - W] then want += 4 end
		if x > 0 and open[i - 1] then want += 8 end
		if i == world.entrance then want += 4 end -- the entrance opens south onto the start line
		if p.sides ~= want then mismatch += 1 end
	end
	eq(mismatch, 0, "every cell payload carries its position and exactly its open sides")
	eq(Dungeon.cellPayload(world, world.seals[2]).kind, "seal", "a seal cell says seal")
	eq(Dungeon.cellPayload(world, world.door).kind, "door", "the Door cell says door")
	eq(Dungeon.cellPayload(world, world.hazards[3].cell).kind, "hazard", "a hazard cell says hazard")
	eq(Dungeon.cellPayload(world, world.hazards[3].cell).slot, 3, "…with its slot")
	-- reveal: exactly the cells within 2 open steps
	local set = Dungeon.revealFrom(world, { world.entrance }, 2)
	local dist = Dungeon.bfs(m, world.entrance)
	local wrong = 0
	for i = 0, W * H - 1 do
		if (set[i] == true) ~= (dist[i] <= 2) then wrong += 1 end
	end
	eq(wrong, 0, "revealFrom returns exactly the cells within 2 open-passage steps")
end

print(string.format("Dungeon: %d passed, %d failed", passed, failed))
if failed > 0 then error("Dungeon spec failed", 0) end
