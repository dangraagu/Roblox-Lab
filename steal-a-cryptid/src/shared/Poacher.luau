--!strict
-- Poacher.luau - the NPC that walks your yard toward your fullest jar. Pure logic.
--
-- DESIGN.md section 6. A poacher appears on the gate approach, follows the cheapest route to the
-- grab cell in front of its target cage (floor costs 1, a laser cell PathLaserCost, snares and
-- walls are never entered), holds for HoldSeconds, and leaves the same way. Before each laser it
-- rolls Caution: under it, it waits beside the net until a crossing is safe; over it, it walks
-- straight in. Every stretch it moves - and every second it stands still - goes through the same
-- continuous catch test the raid uses (Heist.caught, the server rule with grace), so a snare
-- dropped on its next cell, or under its feet while it waits, catches it.
--
-- The step function is exact for any step size: legs and waits are resolved in continuous time,
-- so the server can tick it at 0.1 s for smooth motion and a spec can jump five seconds at once.
--
-- Pure: cfg, Layout, Heist and the layout come in as arguments; this file requires NOTHING.

local Poacher = {}

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Cheapest route from the gate approach to (targetCol, row 8), as a list of {col, row}, or nil.
function Poacher.path(cfg: any, Layout: any, L: any, targetCol: number): { { number } }?
	local key = Layout.key
	local cells = {}
	for row = 0, L.rows do
		for col = 1, L.cols do
			if Layout.cellKind(L, col, row) == "floor" then
				table.insert(cells, { col, row })
			end
		end
	end
	local dist: { [number]: number } = {}
	local prev: { [number]: { number } } = {}
	local done: { [number]: boolean } = {}
	local start = { L.gate, 0 }
	local goalKey = key(targetCol, L.rows)
	dist[key(start[1], start[2])] = 0

	while true do
		local u, ud = nil, math.huge
		for _, c in cells do
			local k = key(c[1], c[2])
			local d = dist[k]
			if d ~= nil and not done[k] and d < ud then u, ud = c, d end
		end
		if u == nil then return nil end
		local uk = key(u[1], u[2])
		if uk == goalKey then break end
		done[uk] = true
		for _, d in DIRS do
			local nc, nr = u[1] + d[1], u[2] + d[2]
			if Layout.cellKind(L, nc, nr) == "floor" then
				local trap = Layout.trapAt(L, nc, nr)
				if not (trap and trap.kind == "snare") then
					local cost = if trap and trap.kind == "laser" then cfg.Poacher.PathLaserCost else 1
					local nk = key(nc, nr)
					if dist[nk] == nil or ud + cost < dist[nk] then
						dist[nk] = ud + cost
						prev[nk] = u
					end
				end
			end
		end
	end

	local path = { { targetCol, L.rows } }
	local k = goalKey
	while prev[k] do
		local p = prev[k]
		table.insert(path, 1, p)
		k = key(p[1], p[2])
	end
	return path
end

function Poacher.new(cfg: any, Layout: any, L: any, targetCol: number, rng: any, now: number): any
	local path = Poacher.path(cfg, Layout, L, targetCol)
	if path == nil then return nil end
	return {
		state = "in", -- in | grab | out | caught | gone
		path = path,
		leg = 1, -- walking from path[leg] to path[leg + 1]
		d = 0, -- studs along the current leg
		t = now,
		targetCol = targetCol,
		rng = rng,
		decided = {},
		waitUntil = nil,
		holdUntil = nil,
		loot = 0,
		waited = 0,
		caughtOn = nil,
		finishedAt = nil,
	}
end

-- Plot-local x, z.
function Poacher.position(cfg: any, Layout: any, p: any): (number, number)
	local n = #p.path
	if p.leg >= n then
		return Layout.cellCenter(cfg, p.path[n][1], p.path[n][2])
	end
	local a, b = p.path[p.leg], p.path[p.leg + 1]
	local ax, az = Layout.cellCenter(cfg, a[1], a[2])
	local bx, bz = Layout.cellCenter(cfg, b[1], b[2])
	local f = p.d / cfg.World.CellSize
	return ax + (bx - ax) * f, az + (bz - az) * f
end

-- Advance to `now`. Returns what happened in this step:
--   grabbed/grabbedAt  the hold finished (the caller takes the loot and sets p.loot)
--   escaped            it reached the gate on the way out (the caller keeps nothing back)
--   caught             the trap that caught it
--   returned           loot it was carrying when caught on the way out (the caller puts it back)
function Poacher.step(cfg: any, Layout: any, Heist: any, L: any, p: any, now: number): any
	local ev: any = {}
	local speed = cfg.Poacher.Speed
	local cellSize = cfg.World.CellSize

	local function catch(trap: any, at: number)
		ev.caught = trap
		p.caughtOn = if p.state == "out" then "out" else "in"
		if p.caughtOn == "out" and p.loot > 0 then
			ev.returned = p.loot
		end
		p.state = "caught"
		p.finishedAt = at
		p.t = at
	end

	local guard = 0
	while p.t < now and (p.state == "in" or p.state == "out" or p.state == "grab") do
		guard += 1
		if guard > 10000 then break end

		if p.state == "grab" then
			local tEnd = math.min(now, p.holdUntil)
			local x, z = Poacher.position(cfg, Layout, p)
			local trap = Heist.caught(cfg, Layout, L, x, z, p.t, x, z, tEnd)
			if trap then
				catch(trap, tEnd)
				break
			end
			p.t = tEnd
			if p.t >= p.holdUntil then
				ev.grabbed = true
				ev.grabbedAt = p.holdUntil
				p.state = "out"
				local rev = {}
				for i = #p.path, 1, -1 do table.insert(rev, p.path[i]) end
				p.path = rev
				p.leg, p.d = 1, 0
				p.decided = {}
			end
		elseif p.leg >= #p.path then
			if p.state == "in" then
				p.state = "grab"
				p.holdUntil = p.t + cfg.Poacher.HoldSeconds
			else
				p.state = "gone"
				p.finishedAt = p.t
				ev.escaped = true
			end
		elseif p.d == 0 and not p.decided[p.leg] then
			p.decided[p.leg] = true
			local nxt = p.path[p.leg + 1]
			local after = p.path[p.leg + 2]
			local trap = Layout.trapAt(L, nxt[1], nxt[2])
			if trap and trap.kind == "laser" and after then
				if p.rng:next() < cfg.Poacher.Caution then
					local a, b = Heist.crossingInterval(cfg, Layout, L, trap, p.path[p.leg], after, speed)
					if a then
						local depart = Heist.earliestCrossing(trap, p.t, a, b, 0)
						if depart and depart > p.t then p.waitUntil = depart end
					end
				end
			end
		elseif p.d == 0 and p.waitUntil ~= nil and p.t < p.waitUntil then
			local tEnd = math.min(now, p.waitUntil)
			local x, z = Poacher.position(cfg, Layout, p)
			local trap = Heist.caught(cfg, Layout, L, x, z, p.t, x, z, tEnd)
			if trap then
				catch(trap, tEnd)
				break
			end
			p.waited += tEnd - p.t
			p.t = tEnd
			if p.t >= p.waitUntil then p.waitUntil = nil end
		else
			p.waitUntil = nil
			local tEnd = math.min(now, p.t + (cellSize - p.d) / speed)
			local x0, z0 = Poacher.position(cfg, Layout, p)
			local oldD = p.d
			p.d = math.min(cellSize, oldD + (tEnd - p.t) * speed)
			local x1, z1 = Poacher.position(cfg, Layout, p)
			local trap = Heist.caught(cfg, Layout, L, x0, z0, p.t, x1, z1, tEnd)
			if trap then
				p.d = oldD
				catch(trap, tEnd)
				break
			end
			p.t = tEnd
			if p.d >= cellSize - 1e-9 then
				p.leg += 1
				p.d = 0
			end
		end
	end
	return ev
end

return Poacher
