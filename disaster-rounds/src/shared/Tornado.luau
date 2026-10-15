--!strict
-- Tornado.luau - "Stay off the red path." (DESIGN.md §2.5). Pure; randomness injected.
--
-- One funnel. It touches down TouchdownAt seconds after the name, at an edge point at least MinStartStuds from every
-- player on the island, and moves at Speed studs/s (walking is 16). Its path is DECIDED StepSeconds at a time at the
-- HorizonSeconds horizon: the server calls extend(now + 4) every tick, and a point past that horizon does not exist
-- anywhere, so the red path a client draws (the next 4 s) is all there is to know. It steers toward a target with at
-- most TurnDegPerSecond of turn: a random player on the island (ChaseChance) or a random point, re-chosen every
-- RetargetSeconds or when reached, and it reflects off the island's edge.
-- A hit: the root within HitRadius + PlayerRadius of the funnel's centre for Hits.LagGrace in a row (Zones.dwell).

local Tornado = {}

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function inner(cfg: any): number
	return cfg.Island.Grid * cfg.Island.CellStuds / 2 - cfg.Tornado.EdgeInset
end

-- players = { { x, z } } on the island now.
function Tornado.start(cfg: any, players: { any }, rand: () -> number): any
	local tc = cfg.Tornado
	local lim = inner(cfg)
	local best, bestD = nil, -1
	for _ = 1, 60 do
		local side = math.min(3, math.floor(rand() * 4))
		local u = (rand() * 2 - 1) * lim * 0.8
		local x, z
		if side == 0 then x, z = -lim, u
		elseif side == 1 then x, z = lim, u
		elseif side == 2 then x, z = u, -lim
		else x, z = u, lim end
		local dmin = math.huge
		for _, p in players do
			local d = math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2)
			if d == d and d < dmin then dmin = d end -- a NaN position is ignored, never poisons the choice
		end
		if best == nil or dmin > bestD then best, bestD = { x = x, z = z }, dmin end
		if dmin >= tc.MinStartStuds then break end
	end
	local p0 = best :: any
	return {
		points = { { t = tc.TouchdownAt, x = p0.x, z = p0.z, reflected = false } },
		heading = math.atan2(-p0.z, -p0.x) + (rand() * 2 - 1) * 0.4,
		target = nil,
		nextRetarget = -math.huge,
		chases = 0,
		retargets = 0,
	}
end

-- Decide the path up to `upto` (seconds after the name). Never further.
function Tornado.extend(cfg: any, s: any, upto: number, players: { any }, rand: () -> number)
	local tc = cfg.Tornado
	local lim = inner(cfg)
	local step = tc.StepSeconds
	local maxTurn = math.rad(tc.TurnDegPerSecond) * step
	local dist = tc.Speed * step
	local guard = 0
	while s.points[#s.points].t < upto - 1e-9 and guard < 10000 do
		guard += 1
		local last = s.points[#s.points]
		local x0, z0 = last.x, last.z
		local tgt = s.target
		if tgt == nil or last.t >= s.nextRetarget - 1e-9 or math.sqrt((tgt.x - x0) ^ 2 + (tgt.z - z0) ^ 2) < tc.ReachedStuds then
			if #players > 0 and rand() < tc.ChaseChance then
				local q = players[math.min(#players, 1 + math.floor(rand() * #players))]
				tgt = { x = q.x, z = q.z }
				s.chases += 1
			else
				tgt = { x = (rand() * 2 - 1) * (lim - 6), z = (rand() * 2 - 1) * (lim - 6) }
			end
			s.target = tgt
			s.retargets += 1
			s.nextRetarget = last.t + tc.RetargetSeconds
		end
		local t = tgt :: any
		local want = math.atan2(t.z - z0, t.x - x0)
		s.heading += math.clamp(wrap(want - s.heading), -maxTurn, maxTurn)
		local nx, nz = x0 + math.cos(s.heading) * dist, z0 + math.sin(s.heading) * dist
		local reflected = false
		if math.abs(nx) > lim then
			s.heading = math.pi - s.heading
			reflected = true
		end
		if math.abs(nz) > lim then
			s.heading = -s.heading
			reflected = true
		end
		if reflected then
			nx, nz = x0 + math.cos(s.heading) * dist, z0 + math.sin(s.heading) * dist
			if math.abs(nx) > lim or math.abs(nz) > lim then
				s.heading = math.atan2(-z0, -x0)
				nx, nz = x0 + math.cos(s.heading) * dist, z0 + math.sin(s.heading) * dist
			end
		end
		s.heading = wrap(s.heading)
		table.insert(s.points, { t = last.t + step, x = nx, z = nz, reflected = reflected })
	end
end

-- The funnel's centre at time t (interpolated), or nil before touchdown.
function Tornado.positionAt(s: any, t: number): (number?, number?)
	local pts = s.points
	local p1 = pts[1]
	if t < p1.t - 1e-9 then return nil, nil end
	local step = if #pts >= 2 then pts[2].t - p1.t else 0.25
	local k = math.floor((t - p1.t) / step + 1e-9) + 1
	if k >= #pts then
		local l = pts[#pts]
		return l.x, l.z
	end
	local a, b = pts[k], pts[k + 1]
	local f = math.clamp((t - a.t) / (b.t - a.t), 0, 1)
	return a.x + (b.x - a.x) * f, a.z + (b.z - a.z) * f
end

function Tornado.window(s: any, from: number, to: number): { any }
	local out = {}
	for _, p in s.points do
		if p.t >= from - 1e-9 and p.t <= to + 1e-9 then table.insert(out, p) end
	end
	return out
end

-- "t0;x,z;x,z;..." for the points in [from, to], 2 decimals: the workspace.Round attribute `Path`. `offset` (the
-- server time of the name) turns t0 into a server time a client can compare with workspace.ServerNow.
function Tornado.encode(s: any, from: number, to: number, offset: number?): string
	local pts = Tornado.window(s, from, to)
	if #pts == 0 then return "" end
	local parts = { string.format("%.2f", pts[1].t + (offset or 0)) }
	for _, p in pts do
		table.insert(parts, string.format("%.2f,%.2f", p.x, p.z))
	end
	return table.concat(parts, ";")
end

-- -> t0, { { x, z } } or nil for anything malformed.
function Tornado.decode(str: any): (number?, { any }?)
	if type(str) ~= "string" or str == "" then return nil, nil end
	local t0 = nil
	local pts = {}
	for chunk in string.gmatch(str, "[^;]+") do
		if t0 == nil then
			t0 = tonumber(chunk)
			if t0 == nil then return nil, nil end
		else
			local x, z = string.match(chunk, "^(%-?[%d%.]+),(%-?[%d%.]+)$")
			local nx, nz = tonumber(x), tonumber(z)
			if nx == nil or nz == nil then return nil, nil end
			table.insert(pts, { x = nx, z = nz })
		end
	end
	if t0 == nil or #pts == 0 then return nil, nil end
	return t0, pts
end

local function segDist(ax: number, az: number, bx: number, bz: number, px: number, pz: number): number
	local abx, abz = bx - ax, bz - az
	local len2 = abx * abx + abz * abz
	local f = 0
	if len2 > 0 then f = math.clamp(((px - ax) * abx + (pz - az) * abz) / len2, 0, 1) end
	local dx, dz = ax + abx * f - px, az + abz * f - pz
	return math.sqrt(dx * dx + dz * dz)
end

-- Is (x, z) on the red path drawn for [from, to] (within `radius` of the funnel's track)?
function Tornado.onPath(s: any, from: number, to: number, radius: number, x: number, z: number): boolean
	local pts = Tornado.window(s, from, to)
	if #pts == 1 then return segDist(pts[1].x, pts[1].z, pts[1].x, pts[1].z, x, z) <= radius end
	for k = 2, #pts do
		if segDist(pts[k - 1].x, pts[k - 1].z, pts[k].x, pts[k].z, x, z) <= radius + 1e-9 then return true end
	end
	return false
end

return Tornado
