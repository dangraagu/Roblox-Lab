-- The path guard, MEASURED on the game's own mazes. Run: luau tests/PathGuard.spec.luau
--
-- The HIGH this closes (EYECANDY.md "Night shift 2026-10-09", finding 1): the walk guard only refused an exit
-- reached SOONER than Progression.minClearSeconds. A script could stand at the spawn for that long and then
-- teleport onto the exit pad. src/shared/PathGuard.luau is the server's path evidence: it samples each runner's
-- root position, keeps a VALIDATED position, and moves it only to a sample a walker could have reached
-- through the maze (every planned secret door open) on a capped allowance. The exit counts only when the
-- validated cell is at the exit.
--
-- Two things are asserted here, in this order of importance:
--   1. AN HONEST PLAYER IS NEVER REFUSED. The fastest honest player there can be (top speed with the speed
--      perk, the geometrically shortest corner-cutting line, through open secret doors, with network jitter,
--      server hiccups and multi-second lag gaps, and after a respawn) has every sample accepted. The margins
--      and the limits are printed, and the limit of what is tolerated is asserted too, so the number in the
--      docs is a measurement and not a hope.
--   2. THE EXPLOIT IS CLOSED: waiting any time and teleporting, in either order, is refused; a hop through a
--      wall is refused; and a real walk afterwards still counts.
-- What is NOT closed is measured and printed as well (a script that hops along the real route).
local MazeGen = require("../src/shared/MazeGen")
local Medals = require("../src/shared/Medals")
local Progression = require("../src/shared/Progression")
local W = require("./MazeWalker")
local PG = require("../src/shared/PathGuard")

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local S = 9                 -- CONFIG.CellSize
local WALK, TOP = 16, 19    -- CONFIG.PlayerWalkSpeed, and with the speed perk (PerkDefs speedBonus 3)
local CFG = table.clone(PG.Config)
CFG.MaxSpeed = TOP
local RATE = TOP * CFG.SpeedSlack
local CAP = RATE * CFG.BankSeconds
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

--================================================================ helpers (test side)

-- A level as the server builds it, plus secret doors planned the way buildInstance plans them: a wall between two
-- rooms, 3 + floor(L / 170) of them. `open` is the guard's grid (every planned door open).
local function level(L: number, seed: number): any
	local lv = W.level(MazeGen, W.CURVE, L, seed)
	local cands = {}
	for cy = 0, lv.rows - 1 do
		for cx = 0, lv.cols - 1 do
			local gx, gy = 2 * cx + 1, 2 * cy + 1
			if cx + 1 < lv.cols and lv.grid[gy][gx + 1] then table.insert(cands, { gx + 1, gy }) end
			if cy + 1 < lv.rows and lv.grid[gy + 1][gx] then table.insert(cands, { gx, gy + 1 }) end
		end
	end
	local rng = W.rng(seed * 31 + L)
	lv.doorKeys = {}
	lv.doors = {}
	for _ = 1, math.min(3 + L // 170, #cands) do
		local c = table.remove(cands, rng:NextInteger(1, #cands))
		table.insert(lv.doorKeys, c[1] .. "," .. c[2])
		table.insert(lv.doors, c)
	end
	lv.open = PG.openGrid(lv.grid, lv.gRows, lv.doorKeys)
	lv.exit = { lv.gCols - 2, lv.gRows - 2 }
	lv.maze = PG.maze(lv.open, lv.gCols, lv.gRows, S, 0, 0, lv.exit[1], lv.exit[2])
	lv.closedMaze = PG.maze(lv.grid, lv.gCols, lv.gRows, S, 0, 0, lv.exit[1], lv.exit[2])
	return lv
end

local function world(lv: any, fx: number, fy: number): (number, number)
	return W.fineToWorld(lv, fx, fy, S)
end

-- the shortest route between two fine cells of `grid`, as a list of cells (BFS with parents)
local function routeCells(grid: any, gCols: number, gRows: number, from: { number }, to: { number }): { { number } }?
	local prev = { [from[2] * gCols + from[1]] = -1 }
	local q, head = { from }, 1
	while head <= #q do
		local cur = q[head]; head += 1
		if cur[1] == to[1] and cur[2] == to[2] then break end
		for _, d in DIRS do
			local nx, ny = cur[1] + d[1], cur[2] + d[2]
			if nx >= 0 and ny >= 0 and nx < gCols and ny < gRows and grid[ny][nx] == false and prev[ny * gCols + nx] == nil then
				prev[ny * gCols + nx] = cur[2] * gCols + cur[1]
				table.insert(q, { nx, ny })
			end
		end
	end
	if prev[to[2] * gCols + to[1]] == nil then return nil end
	local out, k = {}, to[2] * gCols + to[1]
	while k ~= -1 do
		table.insert(out, 1, { k % gCols, k // gCols })
		k = prev[k]
	end
	return out
end

-- a polyline { {x, z}, ... } with cumulative length; `at(s)` is the point `s` studs along it
local function poly(points: { { number } }): any
	local cum = { 0 }
	for i = 2, #points do
		local dx, dz = points[i][1] - points[i - 1][1], points[i][2] - points[i - 1][2]
		cum[i] = cum[i - 1] + math.sqrt(dx * dx + dz * dz)
	end
	local p = { points = points, cum = cum, length = cum[#cum] }
	local idx = 1
	function p.at(s: number): (number, number)
		if s <= 0 then return points[1][1], points[1][2] end
		if s >= p.length then return points[#points][1], points[#points][2] end
		if cum[idx] > s then idx = 1 end
		while cum[idx + 1] < s do idx += 1 end
		local a, b = points[idx], points[idx + 1]
		local seg = cum[idx + 1] - cum[idx]
		local f = if seg > 0 then (s - cum[idx]) / seg else 0
		return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
	end
	return p
end

local function centrePoly(lv: any, cells: { { number } }): any
	local pts = {}
	for _, c in cells do
		local x, z = world(lv, c[1], c[2])
		table.insert(pts, { x, z })
	end
	return poly(pts)
end

-- THE FASTEST HONEST LINE: the shortest walkable polyline along a route, for a character whose root keeps only
-- CLEAR studs from every wall (a real character's root part is 2 studs wide and cannot get that close, so this is
-- shorter than any player can walk). Dynamic programming over a 3x3 lattice in every route cell (the cell centre,
-- its edge midpoints and its corners, CLEAR from the cell's edge), joined wherever the straight line between two
-- lattice points up to WIN cells apart stays in open cells.
local CLEAR = 0.5
local OFFS = { -(S / 2 - CLEAR), 0, S / 2 - CLEAR }
local WIN = 6
local function walkable(maze: any, x: number, z: number): boolean
	local c = CLEAR - 0.05
	for _, o in { { -c, -c }, { c, -c }, { -c, c }, { c, c } } do
		local fx, fy = PG.cellOf(maze, x + o[1], z + o[2])
		if not PG.isOpen(maze, fx, fy) then return false end
	end
	return true
end
local function sight(maze: any, x1: number, z1: number, x2: number, z2: number): boolean
	local dx, dz = x2 - x1, z2 - z1
	local n = math.max(1, math.ceil(math.sqrt(dx * dx + dz * dz)))
	for i = 1, n - 1 do
		if not walkable(maze, x1 + dx * i / n, z1 + dz * i / n) then return false end
	end
	return true
end
local function tautPoly(lv: any, maze: any, cells: { { number } }): any
	local m = #cells
	local px, pz, dist, prev = {}, {}, {}, {}
	for i, c in cells do
		local cx, cz = world(lv, c[1], c[2])
		for a = 1, 3 do
			for b = 1, 3 do
				local k = (i - 1) * 9 + (a - 1) * 3 + b
				px[k], pz[k] = cx + OFFS[a], cz + OFFS[b]
				dist[k] = math.huge
			end
		end
	end
	dist[5] = 0 -- the centre of the first cell
	for i = 2, m do
		for n = 1, 9 do
			local k = (i - 1) * 9 + n
			local best, bestFrom = math.huge, nil
			for j = math.max(1, i - WIN), i - 1 do
				for n2 = 1, 9 do
					local k2 = (j - 1) * 9 + n2
					if dist[k2] < math.huge then
						local dx, dz = px[k] - px[k2], pz[k] - pz[k2]
						local d = dist[k2] + math.sqrt(dx * dx + dz * dz)
						if d < best and sight(maze, px[k2], pz[k2], px[k], pz[k]) then best, bestFrom = d, k2 end
					end
				end
			end
			dist[k], prev[k] = best, bestFrom
		end
	end
	local pts, k = {}, (m - 1) * 9 + 5
	while k do
		table.insert(pts, 1, { px[k], pz[k] })
		k = prev[k]
	end
	return poly(pts)
end

-- What the SERVER sees of a client that is at `pos(tau)` at client time tau. The server samples every
-- dtMin..dtMax seconds (and now and then stalls for `hiccup` seconds); what it reads is the client's position
-- `latency` seconds ago, and during a lag gap { at, len } it reads nothing new at all and then catches up at once.
-- Returns the guard state and what happened to every sample.
local function serverView(maze: any, pos: (number) -> (number, number), duration: number, o: any): any
	local rng = W.rng(o.seed or 1)
	local x0, z0 = pos(0)
	local st = PG.seed(maze, x0, z0, 0, CFG)
	local out = { st = st, samples = 0, rejects = 0, minBank = math.huge, firstReject = nil, reasons = {} }
	local s, tau = 0, 0
	local gaps = o.gaps or {}
	while true do
		local dt = (o.dtMin or 0.25) + rng:NextNumber() * ((o.dtMax or 0.25) - (o.dtMin or 0.25))
		if o.hiccup and rng:NextNumber() < 0.02 then dt += o.hiccup end
		s += dt
		local lat = (o.latMin or 0) + rng:NextNumber() * ((o.latMax or 0) - (o.latMin or 0))
		local seen = s - lat
		for _, g in gaps do
			if s >= g.at and s < g.at + g.len then seen = math.min(seen, g.at - lat) end
		end
		tau = math.max(tau, seen)
		local done = tau >= duration
		local x, z = pos(math.min(tau, duration))
		local ok, why = PG.sample(st, maze, x, z, s, CFG)
		out.samples += 1
		if ok then
			out.minBank = math.min(out.minBank, st.bank)
		else
			out.rejects += 1
			out.firstReject = out.firstReject or s
			out.reasons[why] = (out.reasons[why] or 0) + 1
		end
		if done then break end
	end
	out.tEnd = s
	out.atExit = PG.atExit(st, maze, CFG)
	return out
end

local function walker(p: any, speed: number): ((number) -> (number, number), number)
	return function(tau: number) return p.at(tau * speed) end, p.length / speed
end

--================================================================ 1. the pieces

print("== 1. the pieces ==")
do
	truthy(CFG.SpeedSlack > 1, "the allowance grows faster than anyone walks (SpeedSlack > 1)")
	truthy(CFG.BankSeconds >= 2 and CFG.BankSeconds <= 5, "the bank is capped at a few seconds (" .. CFG.BankSeconds .. ")")
	truthy(CFG.StartBankSeconds > 0 and CFG.StartBankSeconds <= CFG.BankSeconds, "a small bank at the start")
	truthy(CFG.StepPad >= 2, "StepPad covers the two cell borders a corner can cross at once (see section 3)")
	truthy(CFG.SampleSeconds > 0 and CFG.SampleSeconds <= 0.5, "sampled several times a second")
	truthy(CFG.ExitReach >= 1 and CFG.ExitReach <= 2, "the exit pad is touched from the exit cell or the passage beside it")

	-- a 5x5 fine grid: rooms (1,1) (3,1) (1,3) (3,3); open (1,1)-(3,1) and (3,1)-(3,3) and (3,3)-(1,3); wall (1,2)
	local g = {}
	for y = 0, 4 do g[y] = {}; for x = 0, 4 do g[y][x] = true end end
	for _, c in { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 3, 2 }, { 3, 3 }, { 2, 3 }, { 1, 3 } } do g[c[2]][c[1]] = false end
	local mz = PG.maze(g, 5, 5, S, 100, -50, 1, 3)
	local function at(fx, fy) return 100 + (fx - 2) * S, -50 + (fy - 2) * S end

	-- openGrid
	local og = PG.openGrid(g, 5, { "1,2", "junk", "99,99", "0,0x" })
	eq(og[2][1], false, "openGrid opens a planned door")
	eq(g[2][1], true, "and leaves the real grid alone")
	eq(og[0][0], true, "a key that is not a cell changes nothing")
	eq(og[1][1], false, "open cells stay open")
	og[1][1] = true
	eq(g[1][1], false, "the rows are copies")

	-- cellOf / isOpen
	for _, c in { { 1, 1 }, { 3, 2 }, { 0, 4 }, { 4, 0 } } do
		local x, z = at(c[1], c[2])
		local fx, fy = PG.cellOf(mz, x, z)
		truthy(fx == c[1] and fy == c[2], string.format("cellOf the centre of (%d,%d)", c[1], c[2]))
		fx, fy = PG.cellOf(mz, x + 4.4, z - 4.4)
		truthy(fx == c[1] and fy == c[2], string.format("and of a point 0.1 from its corner (%d,%d)", c[1], c[2]))
	end
	eq(PG.isOpen(mz, 1, 1), true, "isOpen: a room")
	eq(PG.isOpen(mz, 1, 2), false, "isOpen: a wall")
	eq(PG.isOpen(mz, -1, 1), false, "isOpen: left of the grid")
	eq(PG.isOpen(mz, 1, 5), false, "isOpen: below the grid")
	eq(PG.isOpen(mz, 0 / 0, 1), false, "isOpen: NaN")

	-- steps
	eq(PG.steps(mz, 1, 1, 1, 1, 0), 0, "steps: the same cell is 0")
	eq(PG.steps(mz, 1, 1, 2, 1, 5), 1, "steps: the next cell is 1")
	eq(PG.steps(mz, 1, 1, 1, 3, 20), 6, "steps: (1,1) to (1,3) is 6, round the wall between them")
	eq(PG.steps(mz, 1, 1, 1, 3, 6), 6, "steps: found exactly at the limit")
	eq(PG.steps(mz, 1, 1, 1, 3, 5), nil, "steps: nil one under the limit")
	eq(PG.steps(mz, 1, 1, 1, 2, 20), nil, "steps: nil into a wall")
	eq(PG.steps(mz, 1, 2, 1, 1, 20), nil, "steps: nil out of a wall")
	eq(PG.steps(mz, 1, 1, 9, 9, 20), nil, "steps: nil off the grid")

	-- seed + sample
	local x1, z1 = at(1, 1)
	local st = PG.seed(mz, x1, z1, 10, CFG)
	truthy(st.fx == 1 and st.fy == 1, "seed: the validated cell is where the server put the player")
	truthy(math.abs(st.bank - RATE * CFG.StartBankSeconds) < 1e-9, "seed: the start bank")
	eq((PG.sample(st, mz, x1, z1, 10.25, CFG)), true, "standing still is accepted")
	truthy(math.abs(st.bank - RATE * (CFG.StartBankSeconds + 0.25)) < 1e-9, "and the bank grew by a quarter second")
	PG.sample(st, mz, x1, z1, 5000, CFG)
	truthy(math.abs(st.bank - CAP) < 1e-9, string.format("waiting an hour banks no more than the cap (%.1f studs)", st.bank))
	PG.sample(st, mz, x1, z1, 4000, CFG)
	truthy(math.abs(st.bank - CAP) < 1e-9, "a clock that steps backwards adds nothing (the bank only fills again once the clock has passed where it was)")
	local x2, z2 = at(2, 1)
	local ok = PG.sample(st, mz, x2, z2, 5000.25, CFG)
	eq(ok, true, "one cell on is accepted")
	truthy(st.fx == 2 and st.fy == 1 and st.x == x2 and st.z == z2, "and the validated position moves there")
	truthy(math.abs(st.bank - (CAP - S)) < 1e-9, "for the 9 studs it cost (the cap holds: no accrual on top)")

	-- junk positions: never accepted, never thrown, never move the validated position
	for _, p in { { 0 / 0, 0 }, { 0, 0 / 0 }, { math.huge, 0 }, { -math.huge, -math.huge }, { 1e9, 1e9 }, { at(1, 2) }, { at(0, 0) } } do
		local okc, r = pcall(PG.sample, st, mz, p[1], p[2], 5001, CFG)
		truthy(okc and r == false, "a position off the grid or in a wall is not accepted (" .. tostring(p[1]) .. ", " .. tostring(p[2]) .. ")")
	end
	truthy(st.fx == 2 and st.fy == 1 and st.x == x2, "and the validated position has not moved")
	truthy(st.bank == st.bank and st.bank <= CAP + 1e-9, "and the bank is still a number under the cap")

	-- lostFor: since when every sample in the maze has been refused; a hiccup that heals never shows
	do
		local a1, b1 = at(1, 1)
		local a3, b3 = at(1, 3) -- the room behind the wall, 6 steps round
		local s2 = PG.seed(mz, a1, b1, 0, CFG)
		s2.bank = 0
		eq(PG.lostFor(s2, 0), 0, "lostFor: 0 for a fresh seed")
		eq((PG.sample(s2, mz, a3, b3, 0, CFG)), false, "(an empty bank cannot pay for the room behind the wall)")
		eq(PG.lostFor(s2, 0), 0, "lostFor: 0 at the instant of the first refusal")
		PG.sample(s2, mz, 0 / 0, 0, 0, CFG)
		truthy(math.abs(PG.lostFor(s2, 0.25) - 0.25) < 1e-9, "lostFor: counts from the first refusal; a junk position does not end it")
		s2.t = 2
		PG.sample(s2, mz, a3, b3, 2, CFG)
		truthy(math.abs(PG.lostFor(s2, 2) - 2) < 1e-9, "lostFor: a second refusal does not restart it")
		eq((PG.sample(s2, mz, a1, b1, 2.1, CFG)), true, "(back where it was validated: accepted)")
		eq(PG.lostFor(s2, 99), 0, "lostFor: 0 again once a sample is accepted")
		PG.sample(s2, mz, 1e9, 1e9, 3, CFG)
		eq(PG.lostFor(s2, 99), 0, "lostFor: a position off the grid does not start it")
		truthy(CFG.LostNoticeSeconds >= 1 and CFG.LostNoticeSeconds <= 3, "the player is told within a few seconds, but not for a one-tick hiccup")
	end

	-- atExit: BFS distance to the exit cell (1,3), never straight through a wall
	local function stAt(fx, fy)
		local x, z = at(fx, fy)
		return PG.seed(mz, x, z, 0, CFG)
	end
	eq(PG.atExit(stAt(1, 3), mz, CFG), true, "atExit: on the exit cell")
	eq(PG.atExit(stAt(2, 3), mz, CFG), true, "atExit: in the passage beside it")
	eq(PG.atExit(stAt(1, 1), mz, CFG), false, "atExit: the room on the other side of the wall is NOT at the exit")
	eq(PG.atExit(stAt(3, 1), mz, CFG), false, "atExit: four cells away is not")
end

--================================================================ 2. the exploit

print("== 2. the exploit: wait, then teleport (in either order) ==")
local LEVELS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 30, 50, 80, 120, 200, 350, 500 }
local SEEDS = { 911, 1213 }
do
	local worstRouteOverCap = math.huge
	for _, L in LEVELS do
		for _, seed in SEEDS do
			local lv = level(L, seed)
			local mz = lv.maze
			local sx, sz = world(lv, 1, 1)
			local ex, ez = world(lv, lv.exit[1], lv.exit[2])
			local openSteps = Medals.solveRoute(lv.open, lv.gCols, lv.gRows, { 1, 1 }, lv.exit, {})
			local floor = Progression.minClearSeconds(openSteps, S, TOP, 0.85)
			local tag = string.format("L%d seed %d", L, seed)

			-- (a) the reviewer's script: stand at the spawn for the time floor and a bit, then teleport onto the pad
			local st = PG.seed(mz, sx, sz, 0, CFG)
			local t = 0
			while t < floor + 0.5 do
				t += 0.25
				PG.sample(st, mz, sx, sz, t, CFG)
			end
			eq((PG.sample(st, mz, ex, ez, t + 0.01, CFG)), false, tag .. ": wait the time floor, teleport to the exit: the sample is refused")
			eq(PG.atExit(st, mz, CFG), false, tag .. ": and the exit does not count")
			truthy(st.fx == 1 and st.fy == 1, tag .. ": the validated cell is still the spawn")
			-- ... and waiting an HOUR buys nothing more
			for i = 1, 3600 do PG.sample(st, mz, sx, sz, t + i, CFG) end
			t += 3600
			eq((PG.sample(st, mz, ex, ez, t + 0.01, CFG)), false, tag .. ": wait an hour, teleport: refused")
			eq(PG.atExit(st, mz, CFG), false, tag .. ": the exit still does not count")

			-- (b) the other order: teleport first, then stand on the exit for an hour
			st = PG.seed(mz, sx, sz, 0, CFG)
			local any = false
			for i = 1, 3600 do
				if PG.sample(st, mz, ex, ez, i, CFG) then any = true end
			end
			eq(any, false, tag .. ": teleport first and wait an hour on the pad: never accepted")
			eq(PG.atExit(st, mz, CFG), false, tag .. ": and it never counts")

			-- (c) nothing is permanent: back at the start the same run is tracked again, and a real walk counts
			eq((PG.sample(st, mz, sx, sz, 3601, CFG)), true, tag .. ": back at the start: accepted again")
			local cells = routeCells(lv.open, lv.gCols, lv.gRows, { 1, 1 }, lv.exit) :: { { number } }
			local p = centrePoly(lv, cells)
			local tt = 3601
			local d = 0
			local refused = 0
			while d < p.length do
				tt += 0.25
				d = math.min(p.length, d + WALK * 0.25)
				local x, z = p.at(d)
				if not PG.sample(st, mz, x, z, tt, CFG) then refused += 1 end
			end
			eq(refused, 0, tag .. ": then walking the route: every sample accepted")
			eq(PG.atExit(st, mz, CFG), true, tag .. ": and the exit counts")

			-- how many full banks the route is: a single teleport can never span it
			local n = #cells - 1
			local routeCost = math.max(math.sqrt((ex - sx) ^ 2 + (ez - sz) ^ 2) - CFG.ExitReach * S, (n - CFG.ExitReach - CFG.StepPad) * S / 2)
			worstRouteOverCap = math.min(worstRouteOverCap, routeCost / CAP)
		end
	end
	print(string.format("  the cheapest spawn-to-exit hop costs >= %.2f full banks on every sampled level (cap %.1f studs = %.1f s at %.1f studs/s)",
		worstRouteOverCap, CAP, CFG.BankSeconds, RATE))
	truthy(worstRouteOverCap > 1.1, string.format("no level is short enough to cross on one full bank (worst %.2f banks)", worstRouteOverCap))
end

print("== 2b. a hop through a wall ==")
do
	local tried, minAround = 0, math.huge
	for _, L in { 1, 5, 12, 30, 100, 300 } do
		local lv = level(L, 77)
		local mz = lv.maze
		for fy = 1, lv.gRows - 2 do
			for fx = 1, lv.gCols - 2 do
				if not PG.isOpen(mz, fx, fy) then
					for _, d in { { 1, 0 }, { 0, 1 } } do
						local ax, ay, bx, by = fx - d[1], fy - d[2], fx + d[1], fy + d[2]
						if PG.isOpen(mz, ax, ay) and PG.isOpen(mz, bx, by) then
							local around = PG.steps(mz, ax, ay, bx, by, 100000)
							local x1, z1 = world(lv, ax, ay)
							local x2, z2 = world(lv, bx, by)
							if around and around >= 12 then
								-- a walker's pace: a quarter second after standing on one side, they are on the other
								local st = PG.seed(mz, x1, z1, 0, CFG)
								local ok = PG.sample(st, mz, x2, z2, 0.25, CFG)
								tried += 1
								if ok then failed += 1; print(string.format("FAIL: L%d through the wall at (%d,%d), %d cells round: accepted", L, fx, fy, around)) end
							end
							if around and around > math.floor(CAP * 2 / S) + CFG.StepPad then
								-- even on a full bank
								local st = PG.seed(mz, x1, z1, 0, CFG)
								PG.sample(st, mz, x1, z1, 600, CFG)
								local ok = PG.sample(st, mz, x2, z2, 600.25, CFG)
								tried += 1
								if ok then failed += 1; print(string.format("FAIL: L%d full bank through the wall at (%d,%d), %d cells round: accepted", L, fx, fy, around)) end
							elseif around then
								minAround = math.min(minAround, around)
							end
						end
					end
				end
			end
		end
	end
	passed += 1
	print(string.format("  %d wall hops tried, all refused. (A wall whose way round is <= %d cells CAN be hopped on a full bank: it costs the walk round it.)",
		tried, math.floor(CAP * 2 / S) + CFG.StepPad))
	truthy(tried > 200, "enough walls were tried (" .. tried .. ")")
end

--================================================================ 3. an honest player is never refused

print("== 3. the cost never exceeds what was really walked (the fastest honest line, CLEAR = " .. CLEAR .. ") ==")
local lines = {} -- [L .. ":" .. seed] = { lv, cells, centre, taut }
local HONEST_LEVELS = { 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 30, 50, 80, 120, 200, 350, 500 }
do
	local worstPad, worstDiag, worstEucl, pairs_, worstShort = -math.huge, -math.huge, 0, 0, 1
	local worstCost, worstStepCost = -math.huge, -math.huge
	for _, L in HONEST_LEVELS do
		for _, seed in SEEDS do
			local lv = level(L, seed)
			local cells = routeCells(lv.open, lv.gCols, lv.gRows, { 1, 1 }, lv.exit) :: { { number } }
			local centre = centrePoly(lv, cells)
			local taut = tautPoly(lv, lv.maze, cells)
			lines[L .. ":" .. seed] = { lv = lv, cells = cells, centre = centre, taut = taut }
			truthy(taut.length < math.huge and taut.length <= centre.length + 1e-6,
				string.format("L%d seed %d: the corner-cutting line exists and is no longer than the centre line (%.0f <= %.0f studs)", L, seed, taut.length, centre.length))
			worstShort = math.min(worstShort, taut.length / centre.length)
			-- every pair of points on the line up to 2 banks apart: what the guard would charge against what was walked
			local step = 1.5
			local n = math.floor(taut.length / step)
			local rng = W.rng(L * 7 + seed)
			for i = 0, n do
				local x1, z1 = taut.at(i * step)
				local a1, b1 = PG.cellOf(lv.maze, x1, z1)
				for _ = 1, 6 do
					local j = math.min(n, i + rng:NextInteger(1, math.ceil(2 * CAP / step)))
					local x2, z2 = taut.at(j * step)
					local a2, b2 = PG.cellOf(lv.maze, x2, z2)
					local walked = (j - i) * step
					local steps = PG.steps(lv.maze, a1, b1, a2, b2, 1000)
					if steps == nil then
						failed += 1; print(string.format("FAIL: L%d: two points of the honest line are not connected in the guard's grid", L))
					else
						worstPad = math.max(worstPad, steps - walked * 2 / S)
						worstDiag = math.max(worstDiag, steps - walked * math.sqrt(2) / S)
						local straight = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
						worstEucl = math.max(worstEucl, straight - walked)
						-- the module's own charge for this move, against what was walked
						worstCost = math.max(worstCost, PG.cost(lv.maze, straight, steps, CFG) - walked)
						if steps > CFG.StepPad then worstStepCost = math.max(worstStepCost, PG.cost(lv.maze, 0, steps, CFG) - walked) end
						pairs_ += 1
					end
				end
			end
		end
	end
	print(string.format("  %d pairs: cell steps - 2 * walked / S is at most %.2f (StepPad = %d); the line is down to %.3f of the centre line",
		pairs_, worstPad, CFG.StepPad, worstShort))
	print(string.format("  (charging S / sqrt2 a step, the diagonal staircase, would need a pad of %.2f on these mazes: hairpins. It is not a bound.)", worstDiag))
	truthy(worstDiag > CFG.StepPad, "the measurement can tell a wrong step charge from a right one (S / sqrt2 fails it)")
	truthy(worstPad <= CFG.StepPad - 0.5, string.format("the step charge is under what was walked with half a cell to spare (needs %.2f, has %d)", worstPad, CFG.StepPad))
	truthy(worstEucl <= 1e-6, "the straight-line charge never exceeds what was walked")
	truthy(worstCost <= 1e-6, string.format("PathGuard.cost never charges more than was walked (worst %.4f studs over)", worstCost))
	truthy(worstStepCost <= -S / 2, string.format("and its step term stays at least half a cell under it (%.1f studs)", worstStepCost))
	eq(PG.cost(lines["1:" .. SEEDS[1]].lv.maze, 7, 0, CFG), 7, "cost: a move inside one cell costs its straight line")
	eq(PG.cost(lines["1:" .. SEEDS[1]].lv.maze, 1, CFG.StepPad + 10, CFG), 10 * S / 2, "cost: ten steps past the pad cost ten half cells")
end

print("== 3b. honest runs through the guard: top speed 19, the fastest line, jitter, hiccups ==")
local NET = { dtMin = 0.25, dtMax = 0.4, hiccup = 1.0, latMin = 0.05, latMax = 0.35 }
do
	local runs, rejects, minBank = 0, 0, math.huge
	for _, L in HONEST_LEVELS do
		for _, seed in SEEDS do
			local e = lines[L .. ":" .. seed]
			for _, variant in {
				{ "fastest line at 19", e.taut, TOP, e.lv.maze },
				{ "centre line at 19", e.centre, TOP, e.lv.maze },
				{ "fastest line at 16", e.taut, WALK, e.lv.maze },
			} do
				for k = 1, 3 do
					local pos, dur = walker(variant[2], variant[3])
					local o = table.clone(NET); o.seed = L * 100 + seed + k
					local r = serverView(variant[4], pos, dur, o)
					runs += 1
					rejects += r.rejects
					minBank = math.min(minBank, r.minBank)
					if r.rejects > 0 or not r.atExit then
						failed += 1
						print(string.format("FAIL: L%d seed %d %s: %d of %d samples refused (first at %.1f s), atExit %s", L, seed, variant[1], r.rejects, r.samples,
							r.firstReject or -1, tostring(r.atExit)))
					end
				end
			end
		end
	end
	passed += 1
	print(string.format("  %d honest runs, %d samples refused; the bank never fell under %.1f studs (it starts at %.1f)", runs, rejects, minBank, RATE * CFG.StartBankSeconds))
	eq(rejects, 0, "no sample of an honest run is refused")
	truthy(minBank >= 8, string.format("with at least 8 studs of allowance to spare at the worst moment (%.1f)", minBank))
end

print("== 3c. the model's players: exploring, dead ends, U-turns, pauses (at 19 studs/s) ==")
do
	local runs, rejects = 0, 0
	for _, L in { 1, 3, 6, 10, 20, 50, 120, 300 } do
		for _, name in { "fast", "normal" } do
			local lv = level(L, 4242)
			local prof = table.clone(W.PROFILES[name]); prof.speed = TOP
			local walk = W.explore(lv, W.rng(L * 17 + 3), prof)
			local pts = walk.points
			local i = 1
			local function pos(tau: number): (number, number)
				if tau <= 0 then return pts[1].x, pts[1].z end
				if tau >= pts[#pts].t then return pts[#pts].x, pts[#pts].z end
				if pts[i].t > tau then i = 1 end
				while pts[i + 1].t < tau do i += 1 end
				local a, b = pts[i], pts[i + 1]
				local f = if b.t > a.t then (tau - a.t) / (b.t - a.t) else 0
				return a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
			end
			local o = table.clone(NET); o.seed = L + 5
			-- the explorer does not know the doors: it walks the CLOSED maze, the guard judges on the open one
			local r = serverView(lv.maze, pos, walk.duration, o)
			runs += 1
			rejects += r.rejects
			if r.rejects > 0 or not r.atExit then
				failed += 1
				print(string.format("FAIL: L%d %s explorer: %d samples refused, atExit %s", L, name, r.rejects, tostring(r.atExit)))
			end
		end
	end
	passed += 1
	print(string.format("  %d exploring runs, %d samples refused", runs, rejects))
	eq(rejects, 0, "no sample of an exploring run is refused")
end

print("== 3d. through opened secret doors, and with every door still shut ==")
do
	local through, shorter = 0, 0
	for _, L in HONEST_LEVELS do
		for _, seed in SEEDS do
			local e = lines[L .. ":" .. seed]
			local lv = e.lv
			-- does the open route use a door? (then the walk above already went through it)
			local uses = false
			for _, c in e.cells do
				for _, d in lv.doors do if c[1] == d[1] and c[2] == d[2] then uses = true end end
			end
			if uses then through += 1 end
			local closedCells = routeCells(lv.grid, lv.gCols, lv.gRows, { 1, 1 }, lv.exit) :: { { number } }
			if #closedCells > #e.cells then shorter += 1 end
			-- doors shut: the player walks the long way; the guard (open grid) must not mind
			local p = tautPoly(lv, lv.closedMaze, closedCells)
			local pos, dur = walker(p, TOP)
			local o = table.clone(NET); o.seed = L + seed
			local r = serverView(lv.maze, pos, dur, o)
			if r.rejects > 0 or not r.atExit then
				failed += 1
				print(string.format("FAIL: L%d seed %d doors shut: %d samples refused, atExit %s", L, seed, r.rejects, tostring(r.atExit)))
			end
			-- a door on the way: walk to it, through it, and on, on the grid where ONLY that door is open
			-- (on the big mazes one door of one seed: the fastest line is expensive to compute there)
			for di, d in lv.doors do
				if L > 50 and (seed ~= SEEDS[1] or di > 1) then continue end
				local only = PG.openGrid(lv.grid, lv.gRows, { lv.doorKeys[di] })
				local c1 = routeCells(only, lv.gCols, lv.gRows, { 1, 1 }, d) :: { { number } }
				local c2 = routeCells(only, lv.gCols, lv.gRows, d, lv.exit) :: { { number } }
				local all = table.clone(c1)
				for i = 2, #c2 do table.insert(all, c2[i]) end
				local onlyMaze = PG.maze(only, lv.gCols, lv.gRows, S, 0, 0, lv.exit[1], lv.exit[2])
				local pd = tautPoly(lv, onlyMaze, all)
				local posd, durd = walker(pd, TOP)
				local od = table.clone(NET); od.seed = L + seed + di
				local rd = serverView(lv.maze, posd, durd, od)
				through += 1
				if rd.rejects > 0 or not rd.atExit then
					failed += 1
					print(string.format("FAIL: L%d seed %d through door %d: %d samples refused, atExit %s", L, seed, di, rd.rejects, tostring(rd.atExit)))
				end
			end
		end
	end
	passed += 1
	print(string.format("  %d walks went through a secret door; on %d of %d mazes the doors make the route shorter", through, shorter, #HONEST_LEVELS * #SEEDS))
	truthy(through >= 60, "plenty of walks through a door (" .. through .. ")")
	truthy(shorter >= 5, "and the doors really are shortcuts on some mazes (" .. shorter .. ")")
	-- THE GUARD'S GRID MUST HAVE THE DOORS OPEN. On the closed grid the same honest walk through a door is refused:
	-- this is what a server that forgot the doors (or opened only the ones without a button) would do to a player.
	local refusedOnClosed = 0
	for _, L in HONEST_LEVELS do
		local e = lines[L .. ":" .. SEEDS[1]]
		local closedCells = routeCells(e.lv.grid, e.lv.gCols, e.lv.gRows, { 1, 1 }, e.lv.exit) :: { { number } }
		if #closedCells > #e.cells + 30 then
			local pos, dur = walker(e.taut, TOP)
			local r = serverView(e.lv.closedMaze, pos, dur, { seed = L })
			if not r.atExit then refusedOnClosed += 1 end
		end
	end
	truthy(refusedOnClosed >= 1, "a guard WITHOUT the doors would refuse honest shortcut runs (" .. refusedOnClosed .. " mazes): the server must pass every planned door")
end

print("== 3e. lag gaps: the server sees nothing for G seconds, then everything at once ==")
local function gapRuns(G: number, speed: number, which: string): (number, number)
	local refusedRuns, runs = 0, 0
	for _, L in { 1, 3, 6, 10, 20, 50, 120, 300 } do
		for _, seed in SEEDS do
			local e = lines[L .. ":" .. seed] or nil
			if e == nil then
				local lv = level(L, seed)
				local cells = routeCells(lv.open, lv.gCols, lv.gRows, { 1, 1 }, lv.exit) :: { { number } }
				e = { lv = lv, cells = cells, centre = centrePoly(lv, cells), taut = tautPoly(lv, lv.maze, cells) }
				lines[L .. ":" .. seed] = e
			end
			local p = if which == "taut" then e.taut else e.centre
			local pos, dur = walker(p, speed)
			-- gaps at several moments of the run, one per run, plus one right at the start (the smallest bank)
			for k = 0, 4 do
				local at = if k == 0 then 0.3 else dur * k / 5
				if at + G < dur then
					local r = serverView(e.lv.maze, pos, dur, { seed = L + k, gaps = { { at = at, len = G } }, latMin = 0.05, latMax = 0.2 })
					runs += 1
					if r.rejects > 0 or not r.atExit then refusedRuns += 1 end
				end
			end
		end
	end
	return refusedRuns, runs
end
do
	local okUpTo = { [TOP] = 0, [WALK] = 0 }
	for _, speed in { TOP, WALK } do
		local unbroken = true
		for _, G in { 1, 2, 3, 4, 4.5, 5, 5.5, 6, 7, 8, 10 } do
			local bad1, n1 = gapRuns(G, speed, "taut")
			local bad2, n2 = gapRuns(G, speed, "centre")
			print(string.format("  %2d studs/s, gap %4.1f s: %3d of %3d runs had a refused sample", speed, G, bad1 + bad2, n1 + n2))
			if bad1 + bad2 == 0 and unbroken then okUpTo[speed] = G else unbroken = false end
			if G <= 4 then eq(bad1 + bad2, 0, string.format("a %.1f s lag gap at %d studs/s never refuses anyone", G, speed)) end
		end
	end
	truthy(okUpTo[TOP] >= 4.5, string.format("at top speed with the perk a gap of %.1f s is tolerated", okUpTo[TOP]))
	truthy(okUpTo[WALK] >= 5.5, string.format("at the normal 16 studs/s a gap of %.1f s is tolerated", okUpTo[WALK]))
	-- the limit is real and stated: a player who keeps running blind for 10 s IS lost track of...
	local bad10 = gapRuns(10, TOP, "centre")
	truthy(bad10 > 0, "a 10 s gap at full speed is beyond the bank (the documented limit)")
	-- ... and is found again by walking back towards where the lag began. Nothing is permanent.
	local e = lines["20:" .. SEEDS[1]]
	local mz = e.lv.maze
	local p = e.centre
	local st = PG.seed(mz, p.points[1][1], p.points[1][2], 0, CFG)
	local t, d = 0, 0
	while d < 60 do t += 0.25; d += TOP * 0.25; PG.sample(st, mz, (p.at(d)), select(2, p.at(d)), t, CFG) end
	local lostAt = d
	d += TOP * 10; t += 10 -- ten seconds unseen
	eq((PG.sample(st, mz, (p.at(d)), select(2, p.at(d)), t, CFG)), false, "after 10 s unseen the next sample is refused")
	-- walking ON does not help (stated, not hidden): two more seconds forward, still refused, and lostFor says so
	local fwd, anyFwd = d, false
	for k = 1, 8 do
		fwd += TOP * 0.25
		if PG.sample(st, mz, (p.at(fwd)), select(2, p.at(fwd)), t + k * 0.25, CFG) then anyFwd = true end
	end
	eq(anyFwd, false, "walking on does not find the path again")
	t += 2
	truthy(PG.lostFor(st, t) >= CFG.LostNoticeSeconds, string.format("lostFor has passed LostNoticeSeconds (%.2f s): the server tells the player now", PG.lostFor(st, t)))
	local walkedBack = 0
	local found = false
	while d > lostAt and not found do
		t += 0.25; d -= TOP * 0.25; walkedBack += TOP * 0.25
		found = PG.sample(st, mz, (p.at(d)), select(2, p.at(d)), t, CFG)
	end
	truthy(found, string.format("walking back finds the path again (after %.0f of the %.0f studs run blind)", walkedBack, TOP * 10))
	truthy(walkedBack <= TOP * 10 - CAP + 2 * S, string.format("and only the part beyond one bank has to be walked back (%.0f <= %.0f studs)", walkedBack, TOP * 10 - CAP + 2 * S))
	truthy(PG.lostFor(st, t) == 0, "lostFor is 0 again")
	local refused = 0
	while d < p.length do
		t += 0.25; d = math.min(p.length, d + TOP * 0.25)
		if not PG.sample(st, mz, (p.at(d)), select(2, p.at(d)), t, CFG) then refused += 1 end
	end
	eq(refused, 0, "and from there the walk to the exit is accepted")
	eq(PG.atExit(st, mz, CFG), true, "and the exit counts")
end

print("== 3f. after a death: the next run starts from a fresh seed ==")
do
	local e = lines["120:" .. SEEDS[1]]
	local mz = e.lv.maze
	local p = e.taut
	local st = PG.seed(mz, p.points[1][1], p.points[1][2], 0, CFG)
	local t, d = 0, 0
	truthy(p.length * 0.6 > CAP * 3, "set-up: they died well over a bank away from the start")
	while d < p.length * 0.6 do t += 0.25; d += TOP * 0.25; PG.sample(st, mz, (p.at(d)), select(2, p.at(d)), t, CFG) end
	-- died there; the engine respawns them in the lobby, they walk back to the door and are placed on the start.
	-- WITHOUT a new seed the old validated cell is far behind the bank, and the honest second run is refused:
	local stale = table.clone(st)
	t += 12
	local pos, dur = walker(p, TOP)
	local staleRefused = 0
	for k = 1, math.ceil(dur / 0.25) do
		local x, z = pos(k * 0.25)
		if not PG.sample(stale, mz, x, z, t + k * 0.25, CFG) then staleRefused += 1 end
	end
	truthy(staleRefused > 0, "(without a re-seed the second run would be refused: the server must seed on every placement)")
	-- WITH the seed the server writes in placeInInstance / advanceInstance:
	local fresh = PG.seed(mz, p.points[1][1], p.points[1][2], t, CFG)
	local refused = 0
	for k = 1, math.ceil(dur / 0.25) do
		local x, z = pos(math.min(dur, k * 0.25))
		if not PG.sample(fresh, mz, x, z, t + k * 0.25, CFG) then refused += 1 end
	end
	eq(refused, 0, "seeded at the start again, the second run is accepted from its first step at top speed")
	eq(PG.atExit(fresh, mz, CFG), true, "and its exit counts")
end

--================================================================ 4. what is NOT closed, measured

print("== 4. residual: a script that hops along the real route as far as the guard lets it ==")
do
	local worst = math.huge
	local worstVsFloor = math.huge
	for _, L in { 1, 3, 6, 12, 30, 120 } do
		local e = lines[L .. ":" .. SEEDS[1]]
		local mz, p = e.lv.maze, e.taut
		local perfect = p.length / TOP
		local openSteps = #e.cells - 1
		local floor = Progression.minClearSeconds(openSteps, S, TOP, 0.85)
		local best = math.huge
		for _, strategy in { "every sample", "full bank" } do
			local st = PG.seed(mz, p.points[1][1], p.points[1][2], 0, CFG)
			local t, d = 0, 0
			while not PG.atExit(st, mz, CFG) and t < 10000 do
				t += CFG.SampleSeconds
				-- peek at the allowance the way the module computes it
				local allowance = math.min(CAP, st.bank + RATE * (t - st.t))
				if strategy == "every sample" or allowance >= CAP - 1e-9 then
					local far = math.min(p.length, d + allowance * 1.5)
					local moved = false
					while far > d + 0.5 do
						local trial = table.clone(st)
						local x, z = p.at(far)
						if PG.sample(trial, mz, x, z, t, CFG) then
							PG.sample(st, mz, x, z, t, CFG)
							d = far
							moved = true
							break
						end
						far -= 1.5
					end
					if not moved then PG.sample(st, mz, (p.at(d)), select(2, p.at(d)), t, CFG) end
				else
					PG.sample(st, mz, (p.at(d)), select(2, p.at(d)), t, CFG)
				end
			end
			best = math.min(best, t)
		end
		print(string.format("  L%-3d fastest honest run %.1f s | time floor %.1f s | best hop script %.1f s (%.2f of honest)", L, perfect, floor, best, best / perfect))
		worst = math.min(worst, best / perfect)
		worstVsFloor = math.min(worstVsFloor, math.max(best, floor) / perfect)
	end
	print(string.format("  a route-hopping script finishes in >= %.2f of the fastest honest time; with the time floor on top, >= %.2f", worst, worstVsFloor))
	truthy(worstVsFloor >= 0.55, string.format("with the time floor kept, a hop script needs at least 0.55 of the fastest honest time (%.2f)", worstVsFloor))
	truthy(worst < 1, "and this residual is real and stated: the path guard does not make a record script-proof")
end

print(string.format("PathGuard: %d passed, %d failed", passed, failed))
if failed > 0 then error("PathGuard spec failed", 0) end
