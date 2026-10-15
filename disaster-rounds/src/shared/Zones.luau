--!strict
-- Zones.luau - the red rule (DESIGN.md §2.3). Pure. Every hit test the server runs goes through here, and every red
-- zone a client draws is drawn from the same numbers, so what is red is exactly what hits.
--
--   * disks (rings, the funnel) are 2-D: X and Z of the root, edge inclusive. Jumping or flying over red never helps;
--   * the flood and the quake are decided by the cell under the root, never its height;
--   * a timed hit (a ring's impact, a cell's drop) needs the root inside at EVERY server sample in [T, T + grace]:
--     one sample outside in that window is a dodge, so ties go to the dodger;
--   * a standing hazard (flood water, a hole, the funnel) needs the root inside continuously for `need` seconds.

local Zones = {}

function Zones.ringRadius(cfg: any): number
	return cfg.Strikes.HitRadius + cfg.Hits.PlayerRadius
end

function Zones.funnelRadius(cfg: any): number
	return cfg.Tornado.HitRadius + cfg.Hits.PlayerRadius
end

function Zones.inDisk(cx: number, cz: number, r: number, x: number, z: number): boolean
	local dx, dz = x - cx, z - cz
	return dx * dx + dz * dz <= r * r + 1e-9
end

-- Is the water above this level's top? Level with the top is dry (ties go to the dodger).
function Zones.flooded(islandCfg: any, level: number, waterY: number): boolean
	return waterY > level * islandCfg.LevelStuds + 1e-9
end

-- Is the point over cell (i, j)'s square? The SAME arithmetic as MapGen.cellAt, to the last bit: with a different
-- formula a root at x = 3.999999999999999 was in cell 8 for cellAt (and every client) and over cell 7 for the drop
-- judge (fairness check 2026-10-07). Whatever a client shows as the cell under you is the cell that decides.
function Zones.overCell(islandCfg: any, i: number, j: number, x: number, z: number): boolean
	if x ~= x or z ~= z then return false end
	local n = islandCfg.Grid
	local ci = math.floor(x / islandCfg.CellStuds + n / 2) + 1
	local cj = math.floor(z / islandCfg.CellStuds + n / 2) + 1
	return ci == i and cj == j
end

--======================================================================= red you can see on terraced ground

-- The hit tests are 2-D, the island is terraced (REVIEW-1 F7): a flat red disc drawn at one cell's top is buried inside
-- a higher neighbour's column, so a player who stepped up out of the red they could see was hit by red they could not.
-- Every red piece (a ring, a stretch of the tornado's path, the funnel's own disc) is therefore drawn as a red volume
-- from RED_LIFT over the LOWEST top it reaches to RED_LIFT + RED_THICK over the HIGHEST, so the ground of every cell
-- it reaches shows red. Over flat ground that is the old flat piece, 0.2 studs thick, 0.05 over the top.
Zones.RED_LIFT = 0.05
Zones.RED_THICK = 0.2

-- the square of cell (i, j): MapGen.cellAt's arithmetic, i spans [(i - 1 - n / 2) * cs, (i - n / 2) * cs)
local function square(islandCfg: any, i: number, j: number): (number, number, number, number)
	local n, cs = islandCfg.Grid, islandCfg.CellStuds
	local lx, lz = (i - 1 - n / 2) * cs, (j - 1 - n / 2) * cs
	return lx, lx + cs, lz, lz + cs
end

-- the cells whose squares a span [lo, hi] can touch. A span that ends exactly on a boundary (x = 28.0) touches the
-- square on its far side too: cellAt puts x = 28.0 in the next cell, but the hit tests are edge-inclusive, so a root a
-- hair the other side of 28.0 is inside the red as well. Hence the 1e-6 of slack.
local function cellRange(islandCfg: any, lo: number, hi: number): (number, number)
	local n, cs = islandCfg.Grid, islandCfg.CellStuds
	return math.max(1, math.floor((lo - 1e-6) / cs + n / 2) + 1), math.min(n, math.floor((hi + 1e-6) / cs + n / 2) + 1)
end

-- The island cells whose square meets the disc (edge inclusive). -> { { i, j } }
function Zones.cellsUnderDisk(islandCfg: any, cx: number, cz: number, r: number): { any }
	local out = {}
	local i0, i1 = cellRange(islandCfg, cx - r, cx + r)
	local j0, j1 = cellRange(islandCfg, cz - r, cz + r)
	for i = i0, i1 do
		for j = j0, j1 do
			local lx, hx, lz, hz = square(islandCfg, i, j)
			local dx = math.max(lx - cx, 0, cx - hx)
			local dz = math.max(lz - cz, 0, cz - hz)
			if dx * dx + dz * dz <= r * r + 1e-9 then table.insert(out, { i = i, j = j }) end
		end
	end
	return out
end

-- The island cells whose square meets a box centred at (cx, cz) with unit direction (ux, uz), half-length hl along it
-- and half-width hw across it (separating axes: the square's two and the box's two). -> { { i, j } }
function Zones.cellsUnderBox(islandCfg: any, cx: number, cz: number, ux: number, uz: number, hl: number, hw: number): { any }
	local out = {}
	local ax, az = math.abs(ux), math.abs(uz)
	local ex = ax * hl + az * hw -- the box's half-extent along X
	local ez = az * hl + ax * hw -- ... and along Z
	local i0, i1 = cellRange(islandCfg, cx - ex, cx + ex)
	local j0, j1 = cellRange(islandCfg, cz - ez, cz + ez)
	local s = islandCfg.CellStuds / 2
	local rad = s * (ax + az) -- a square's half-extent along the box's own axes
	for i = i0, i1 do
		for j = j0, j1 do
			local lx, hx, lz, hz = square(islandCfg, i, j)
			if lx <= cx + ex + 1e-9 and hx >= cx - ex - 1e-9 and lz <= cz + ez + 1e-9 and hz >= cz - ez - 1e-9 then
				local dx, dz = (lx + hx) / 2 - cx, (lz + hz) / 2 - cz
				local along = dx * ux + dz * uz
				local across = -dx * uz + dz * ux
				if math.abs(along) <= hl + rad + 1e-9 and math.abs(across) <= hw + rad + 1e-9 then
					table.insert(out, { i = i, j = j })
				end
			end
		end
	end
	return out
end

-- The vertical span of a red volume over `cells`; levelAt(i, j) -> the cell's level, or nil for no ground.
-- -> bottomY, topY, or nil when no listed cell has ground.
function Zones.redSpan(islandCfg: any, cells: { any }, levelAt: (number, number) -> number?): (number?, number?)
	local lo, hi = math.huge, -math.huge
	for _, c in cells do
		local level = levelAt(c.i, c.j)
		if level ~= nil then
			lo = math.min(lo, level)
			hi = math.max(hi, level)
		end
	end
	if lo == math.huge then return nil, nil end
	return lo * islandCfg.LevelStuds + Zones.RED_LIFT, hi * islandCfg.LevelStuds + Zones.RED_LIFT + Zones.RED_THICK
end

--======================================================================= timed hits

function Zones.newJudge(impact: number, grace: number): any
	return { impact = impact, grace = grace, seen = {}, decided = {} }
end

-- One server sample for one player. -> "hit" | "dodge" | nil (pending, or already decided).
-- Inside the window [impact, impact + grace]: one sample outside is a dodge; inside at the window's last sample
-- (and at every one before it) is a hit. A sample past the window decides on what the window saw; if the server
-- took no sample inside the window at all (a stalled tick), it decides on this sample.
function Zones.judgeSample(j: any, key: any, t: number, inside: boolean): string?
	if j.decided[key] then return nil end
	if t < j.impact - 1e-9 then return nil end
	if t <= j.impact + j.grace + 1e-9 then
		if not inside then
			j.decided[key] = true
			return "dodge"
		end
		j.seen[key] = true
		if t >= j.impact + j.grace - 1e-9 then
			j.decided[key] = true
			return "hit"
		end
		return nil
	end
	j.decided[key] = true
	if j.seen[key] or inside then return "hit" end
	return "dodge"
end

function Zones.judgeDone(j: any, now: number): boolean
	return now > j.impact + j.grace + 1e-9
end

--======================================================================= standing hazards

function Zones.newDwell(): any
	return {}
end

-- true once `inside` has held at every sample for at least `need` seconds.
function Zones.dwell(d: any, key: any, inside: boolean, now: number, need: number): boolean
	if not inside then
		d[key] = nil
		return false
	end
	local since = d[key]
	if since == nil then
		d[key] = now
		since = now
	end
	return now - since >= need - 1e-9
end

function Zones.clearDwell(d: any, key: any)
	d[key] = nil
end

--======================================================================= the exit search

-- How far a player at (x, z) must walk to stand outside every disk ({ x, z, r }) by `margin`, on a point where
-- walkable(px, pz) is true. 0 when already out; math.huge when there is no such point within maxStuds.
-- Circles 0.5 studs apart, 32 directions each (DESIGN.md: the model's search).
function Zones.exitDistance(x: number, z: number, disks: { any }, walkable: (number, number) -> boolean,
	margin: number, maxStuds: number): number
	local function free(px: number, pz: number): boolean
		for _, d in disks do
			local dx, dz = px - d.x, pz - d.z
			local rr = d.r + margin
			if dx * dx + dz * dz < rr * rr then return false end
		end
		return true
	end
	if free(x, z) and walkable(x, z) then return 0 end
	local step = 0.5
	local k = 1
	while k * step <= maxStuds + 1e-9 do
		local dist = k * step
		for a = 0, 31 do
			local ang = a * math.pi / 16
			local px, pz = x + math.cos(ang) * dist, z + math.sin(ang) * dist
			if walkable(px, pz) and free(px, pz) then return dist end
		end
		k += 1
	end
	return math.huge
end

return Zones
