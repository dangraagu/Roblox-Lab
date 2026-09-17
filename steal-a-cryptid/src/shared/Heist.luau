--!strict
-- Heist.luau - laser timing, the server's continuous catch test, and the raid solver.
--
-- Pure. cfg, Layout and the layout object come in as arguments; this file requires NOTHING.
--
-- THE CATCH RULE (DESIGN.md section 5, "Catch rules"). Everything is on the XZ plane - height is
-- ignored, so jumping and flying change nothing. A raider is caught when the trusted segment of a
-- tick passes through a trap's danger area:
--   * a snare, at any time;
--   * a laser, at any instant of that passage that falls in an ON window, with time interpolated
--     linearly along the segment. The first LatencyGraceSeconds of every ON window count as OFF,
--     because the client sees the switch about one round trip late.
-- A continuous segment test, not a point sample, so the poll rate cannot let anyone slip between
-- two samples.
--
-- THE SOLVER is the design's camps.py, ported: earliest arrival over grid cells, moving centre to
-- centre, waiting allowed on any non-trap cell. Lasers are never 4-adjacent and a gap has fence on
-- both sides, so a laser cell is only ever CROSSED, never loitered in; waiting inside a net is
-- dominated by waiting beside it and crossing later, so each crossing is one timed macro-move and
-- plain Dijkstra on earliest arrival is exact. Crossing times are solved analytically, not on a
-- 0.05 s grid.

local Heist = {}

--============================================================================ laser time

function Heist.laserState(cfg: any, trap: any, t: number): string
	if trap.kind ~= "laser" then return "on" end
	local period = trap.on + trap.off
	local lt = (t + trap.phase) % period
	if lt >= trap.off then return "on" end
	if lt >= trap.off - cfg.Raid.WarnSeconds then return "warn" end
	return "off"
end

function Heist.dangerousAt(cfg: any, trap: any, t: number): boolean
	if trap.kind ~= "laser" then return true end
	local period = trap.on + trap.off
	local lt = (t + trap.phase) % period
	return lt >= trap.off + cfg.Raid.LatencyGraceSeconds
end

-- The first ON window (shifted by startOff/endOff) that overlaps [a, b] with positive measure.
-- Window k is [k*P - phase + off + startOff, k*P - phase + P + endOff]. Returns the overlap's
-- start time, or nil.
local function windowOverlap(trap: any, a: number, b: number, startOff: number, endOff: number): (number?, number?)
	local P = trap.on + trap.off
	local base = -trap.phase
	local E = base + P + endOff
	local k = math.floor((a - E) / P) + 1
	local ws = k * P + base + trap.off + startOff
	local we = k * P + E
	if ws < b and we > a then
		return math.max(a, ws), we
	end
	return nil, nil
end

--============================================================================ geometry

-- Liang-Barsky against a closed rectangle: the parameter interval [s0, s1] of the segment
-- A->B inside it, or nil.
local function clip(r: any, ax: number, az: number, bx: number, bz: number): (number?, number?)
	local dx, dz = bx - ax, bz - az
	local s0, s1 = 0, 1
	local ps = { -dx, dx, -dz, dz }
	local qs = { ax - r.x0, r.x1 - ax, az - r.z0, r.z1 - az }
	for i = 1, 4 do
		local p, q = ps[i], qs[i]
		if p == 0 then
			if q < 0 then return nil, nil end
		else
			local u = q / p
			if p < 0 then
				if u > s1 then return nil, nil end
				if u > s0 then s0 = u end
			else
				if u < s0 then return nil, nil end
				if u < s1 then s1 = u end
			end
		end
	end
	if s0 > s1 then return nil, nil end
	return s0, s1
end
Heist.clip = clip

-- When (if at all) the segment A@t0 -> B@t1 is caught by one trap whose danger area is `rect`.
-- `model` nil = the server's rule (grace, no pad); a number = the solver's human model (raw ON
-- windows padded by that much on both sides, no grace).
local function catchTime(cfg: any, trap: any, rect: any, ax: number, az: number, t0: number, bx: number, bz: number, t1: number, model: number?): number?
	local s0, s1 = clip(rect, ax, az, bx, bz)
	if s0 == nil then return nil end
	local moved = (ax ~= bx or az ~= bz)
	if moved and (s1 :: number) <= (s0 :: number) then return nil end -- grazed a boundary: zero length inside
	local tIn = t0 + (s0 :: number) * (t1 - t0)
	local tOut = t0 + (s1 :: number) * (t1 - t0)
	if trap.kind ~= "laser" then
		if not moved and t1 <= t0 then return nil end
		return tIn
	end
	local startOff, endOff = cfg.Raid.LatencyGraceSeconds, 0
	if model ~= nil then
		startOff, endOff = -model, model
	end
	if tOut <= tIn then
		if not moved then return nil end
		-- a zero-duration passage: judge the instant
		local hit = windowOverlap(trap, tIn - 1e-9, tIn + 1e-9, startOff, endOff)
		return if hit then tIn else nil
	end
	local hit = windowOverlap(trap, tIn, tOut, startOff, endOff)
	return hit
end

-- The server's rule: the trap that catches the segment A@t0 -> B@t1 first, or nil.
function Heist.caught(cfg: any, Layout: any, L: any, ax: number, az: number, t0: number, bx: number, bz: number, t1: number): any
	local best, bestT = nil, math.huge
	local minX, maxX = math.min(ax, bx), math.max(ax, bx)
	local minZ, maxZ = math.min(az, bz), math.max(az, bz)
	for _, trap in Layout.traps(L) do
		local rect = Layout.dangerRect(cfg, L, trap.col, trap.row)
		if rect.x0 <= maxX and rect.x1 >= minX and rect.z0 <= maxZ and rect.z1 >= minZ then
			local t = catchTime(cfg, trap, rect, ax, az, t0, bx, bz, t1, nil)
			if t and t < bestT then
				best, bestT = trap, t
			end
		end
	end
	return best
end

-- The server's rule along a tick's whole trusted path (Trace2D's `t.path`: x0, z0, x1, z1, ...),
-- over [t0, t1]. Each leg gets the share of the tick its length is of the path's length, so the
-- path is walked at one speed; the first leg that is caught reports its trap. A one-point path (or
-- one of zero length) is standing still at that point for the tick. REVIEW-1.md B1: a slide bends
-- the path, and the chord from its start to its end can miss a trap the bend runs through.
function Heist.caughtPath(cfg: any, Layout: any, L: any, path: { number }, t0: number, t1: number): any
	local n = math.floor(#path / 2)
	local total = 0
	for i = 2, n do
		total += math.sqrt((path[2 * i - 1] - path[2 * i - 3]) ^ 2 + (path[2 * i] - path[2 * i - 2]) ^ 2)
	end
	if n < 2 or total <= 0 then
		local x, z = path[#path - 1], path[#path]
		return Heist.caught(cfg, Layout, L, x, z, t0, x, z, t1)
	end
	local walked = 0
	for i = 2, n do
		local ax, az, bx, bz = path[2 * i - 3], path[2 * i - 2], path[2 * i - 1], path[2 * i]
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		if len > 0 then
			local ta = t0 + (t1 - t0) * walked / total
			walked += len
			local tb = t0 + (t1 - t0) * walked / total
			local trap = Heist.caught(cfg, Layout, L, ax, az, ta, bx, bz, tb)
			if trap then return trap end
		end
	end
	return nil
end

--============================================================================ crossings

-- Earliest departure >= t for a crossing that is inside the net over [depart + a, depart + b],
-- against raw ON windows padded by `pad` on both sides. nil when no departure is ever safe.
function Heist.earliestCrossing(trap: any, t: number, a: number, b: number, pad: number): number?
	if trap.kind ~= "laser" then return nil end
	local P = trap.on + trap.off
	if trap.on + 2 * pad + (b - a) >= P then return nil end
	local depart = t
	for _ = 1, 8 do
		local hitStart, hitEnd = windowOverlap(trap, depart + a, depart + b, -pad, pad)
		if hitStart == nil then return depart end
		depart = (hitEnd :: number) - a + 1e-12
	end
	return nil
end

-- The inside-the-net interval of a centre-to-centre crossing from cell `from` through the trap's
-- cell to cell `to` at `speed`, relative to departure.
function Heist.crossingInterval(cfg: any, Layout: any, L: any, trap: any, from: { number }, to: { number }, speed: number): (number?, number?)
	local rect = Layout.dangerRect(cfg, L, trap.col, trap.row)
	local ax, az = Layout.cellCenter(cfg, from[1], from[2])
	local mx, mz = Layout.cellCenter(cfg, trap.col, trap.row)
	local bx, bz = Layout.cellCenter(cfg, to[1], to[2])
	local leg = cfg.World.CellSize / speed
	local a, b = math.huge, -math.huge
	local s0, s1 = clip(rect, ax, az, mx, mz)
	if s0 then
		a = math.min(a, s0 * leg)
		b = math.max(b, (s1 :: number) * leg)
	end
	s0, s1 = clip(rect, mx, mz, bx, bz)
	if s0 then
		a = math.min(a, leg + s0 * leg)
		b = math.max(b, leg + (s1 :: number) * leg)
	end
	if a > b then return nil, nil end
	return a, b
end

-- Does a planned crossing get caught? pad nil = the server's rule; a number = the padded model.
function Heist.crossingCaught(cfg: any, Layout: any, L: any, x: any, pad: number?): boolean
	local trap = x.trap
	local rect = Layout.dangerRect(cfg, L, trap.col, trap.row)
	local ax, az = Layout.cellCenter(cfg, x.from[1], x.from[2])
	local mx, mz = Layout.cellCenter(cfg, trap.col, trap.row)
	local bx, bz = Layout.cellCenter(cfg, x.to[1], x.to[2])
	local leg = cfg.World.CellSize / x.speed
	if catchTime(cfg, trap, rect, ax, az, x.depart, mx, mz, x.depart + leg, pad) then return true end
	if catchTime(cfg, trap, rect, mx, mz, x.depart + leg, bx, bz, x.depart + 2 * leg, pad) then return true end
	return false
end

--============================================================================ the solver

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function walkable(Layout: any, L: any, c: number, r: number): boolean
	return Layout.cellKind(L, c, r) == "floor"
end

-- Earliest arrival at `goal` leaving `start` at t0. Returns { time, crossings } or nil.
-- opts.pad: human reaction pad; opts.noLasers: treat every laser as bare floor.
local function earliest(cfg: any, Layout: any, L: any, start: { number }, goal: { number }, t0: number, speed: number, opts: any): any
	local key = Layout.key
	local leg = cfg.World.CellSize / speed
	local pad = opts.pad or 0
	local dist: { [number]: number } = {}
	local prev: { [number]: any } = {}
	local done: { [number]: boolean } = {}
	local cellOf: { [number]: { number } } = {}
	local sk = key(start[1], start[2])
	dist[sk] = t0
	cellOf[sk] = start
	local gk = key(goal[1], goal[2])

	local function relax(fromKey: number, to: { number }, t: number, crossing: any)
		local k = key(to[1], to[2])
		if dist[k] == nil or t < dist[k] then
			dist[k] = t
			prev[k] = { from = fromKey, crossing = crossing }
			cellOf[k] = to
		end
	end

	while true do
		local uk, ut = nil, math.huge
		for k, t in dist do
			if not done[k] and t < ut then uk, ut = k, t end
		end
		if uk == nil then return nil end
		if uk == gk then break end
		done[uk] = true
		local u = cellOf[uk]
		for _, d in DIRS do
			local nc, nr = u[1] + d[1], u[2] + d[2]
			if walkable(Layout, L, nc, nr) then
				local trap = Layout.trapAt(L, nc, nr)
				if trap == nil or (opts.noLasers and trap.kind == "laser") then
					relax(uk, { nc, nr }, ut + leg, nil)
				elseif trap.kind == "laser" then
					for _, d2 in DIRS do
						local bc, br = nc + d2[1], nr + d2[2]
						if not (bc == u[1] and br == u[2]) and walkable(Layout, L, bc, br) and Layout.trapAt(L, bc, br) == nil then
							local a, b = Heist.crossingInterval(cfg, Layout, L, trap, u, { bc, br }, speed)
							if a then
								local depart = Heist.earliestCrossing(trap, ut, a :: number, b :: number, pad)
								if depart then
									relax(uk, { bc, br }, depart + 2 * leg,
										{ trap = trap, depart = depart, speed = speed, from = u, to = { bc, br } })
								end
							end
						end
					end
				end
				-- a snare is never entered
			end
		end
	end

	-- Walk the chain back into crossings and a timed route of cell-centre waypoints.
	local crossings = {}
	local steps = {}
	local k = gk
	while prev[k] do
		table.insert(steps, 1, { key = k, from = prev[k].from, crossing = prev[k].crossing })
		if prev[k].crossing then table.insert(crossings, 1, prev[k].crossing) end
		k = prev[k].from
	end
	local sx, sz = Layout.cellCenter(cfg, start[1], start[2])
	local route = { { x = sx, z = sz, t = t0 } }
	for _, st in steps do
		local fromCell = cellOf[st.from]
		local fx, fz = Layout.cellCenter(cfg, fromCell[1], fromCell[2])
		local to = cellOf[st.key]
		local tx, tz = Layout.cellCenter(cfg, to[1], to[2])
		if st.crossing then
			local x = st.crossing
			if x.depart > dist[st.from] + 1e-12 then
				table.insert(route, { x = fx, z = fz, t = x.depart })
			end
			local mx, mz = Layout.cellCenter(cfg, x.trap.col, x.trap.row)
			table.insert(route, { x = mx, z = mz, t = x.depart + leg })
			table.insert(route, { x = tx, z = tz, t = x.depart + 2 * leg })
		else
			table.insert(route, { x = tx, z = tz, t = dist[st.key] })
		end
	end
	return { time = dist[gk], crossings = crossings, route = route }
end

-- Gate -> prize -> gate for a camp layout: in at WalkSpeed, the tier's grab hold on the grab cell
-- (row 8 carries no trap), out at CarrySpeed. Returns { inTime, total, crossings } or nil.
function Heist.solveRaid(cfg: any, Layout: any, L: any, opts: any): any
	local P = cfg.Camps[L.tier]
	local prizeCol = nil
	for _, c in L.cages do
		if c.prize then prizeCol = c.col end
	end
	if prizeCol == nil then return nil end
	local gate = { L.gate, 0 }
	local grab = { prizeCol, L.rows }
	local inRes = earliest(cfg, Layout, L, gate, grab, 0, cfg.Raid.WalkSpeed, opts)
	if not inRes then return nil end
	local outRes = earliest(cfg, Layout, L, grab, gate, inRes.time + P.hold, cfg.Raid.CarrySpeed, opts)
	if not outRes then return nil end
	local crossings = table.clone(inRes.crossings)
	for _, x in outRes.crossings do table.insert(crossings, x) end
	local route = table.clone(inRes.route)
	local last = route[#route]
	table.insert(route, { x = last.x, z = last.z, t = inRes.time + P.hold, grab = true })
	for i = 2, #outRes.route do table.insert(route, outRes.route[i]) end
	return { inTime = inRes.time, total = outRes.time, crossings = crossings, route = route }
end

return Heist
