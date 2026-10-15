--!strict
-- PathGen.luau: the procedural garden bed (DESIGN.md §3.6). Pure, no Roblox globals.
--
-- A bed is a path of exactly cfg.PathCells cells from the hedge gap (column 0) to the carrot patch
-- (column GridW - 1): 3-5 vertical runs in columns at least 2 apart (so no two path cells that are not
-- neighbours on the path ever touch side by side), rows drawn at random, rejection-sampled until the length
-- is exact. The pads are every lawn cell touching the path (8-neighbourhood).
--
-- The same code as tests/GardenModel.luau's bed, so the game draws exactly the beds the balance was measured
-- on (tests/PathGen.spec.luau pins five of them). `rand` is an Rng (fork-tower's): `below` uses the HIGH bits.
--
-- The bed seed drives ONLY the visible bed. Recovering it (fork-tower REVIEW-4) yields the bed you can see.

local PathGen = {}

-- -> path { cells, length, step, px, pz, n, onPath }
function PathGen.genPath(cfg: any, rand: any): any
	local W, H, L = cfg.GridW, cfg.GridH, cfg.PathCells
	local need = L - W -- vertical cells beyond the W horizontal ones
	for _ = 1, 100000 do
		local k = 3 + rand:below(3) - 1 -- 3..5 vertical runs
		local cols = {}
		local c = 0
		local ok = true
		for i = 1, k do
			local lo = c + 2
			if i == 1 then lo = 1 end
			local hi = (W - 2) - 2 * (k - i)
			if lo > hi then ok = false; break end
			c = lo + rand:below(hi - lo + 1) - 1
			table.insert(cols, c)
		end
		if ok then
			local rows = { rand:below(H) - 1 }
			local total = 0
			for i = 1, k do
				local r
				repeat r = rand:below(H) - 1 until r ~= rows[i]
				table.insert(rows, r)
				total += math.abs(r - rows[i])
			end
			if total == need then
				local cells = {}
				local x, y = 0, rows[1]
				table.insert(cells, { x = x, y = y })
				for i = 1, k do
					while x < cols[i] do x += 1; table.insert(cells, { x = x, y = y }) end
					local ty = rows[i + 1]
					local dy = if ty > y then 1 else -1
					while y ~= ty do y += dy; table.insert(cells, { x = x, y = y }) end
				end
				while x < W - 1 do x += 1; table.insert(cells, { x = x, y = y }) end
				return PathGen.pathFromCells(cfg, cells)
			end
		end
	end
	error("PathGen.genPath: no path found")
end

-- Polyline through the cell centres, from the hedge edge to the patch edge, sampled every 0.5 stud.
function PathGen.pathFromCells(cfg: any, cells: { any }): any
	local T = cfg.Tile
	local pts = {}
	local first, last = cells[1], cells[#cells]
	table.insert(pts, { x = first.x * T, z = (first.y + 0.5) * T })
	for _, c in cells do table.insert(pts, { x = (c.x + 0.5) * T, z = (c.y + 0.5) * T }) end
	table.insert(pts, { x = (last.x + 1) * T, z = (last.y + 0.5) * T })
	local seg = {}
	local len = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		table.insert(seg, { a = a, b = b, s0 = len, len = d })
		len += d
	end
	local step = 0.5
	local n = math.floor(len / step) + 1
	local px, pz = table.create(n + 1, 0), table.create(n + 1, 0)
	local si = 1
	for i = 0, n do
		local s = math.min(i * step, len)
		while si < #seg and s > seg[si].s0 + seg[si].len do si += 1 end
		local g = seg[si]
		local f = if g.len > 0 then (s - g.s0) / g.len else 0
		px[i + 1] = g.a.x + (g.b.x - g.a.x) * f
		pz[i + 1] = g.a.z + (g.b.z - g.a.z) * f
	end
	local onPath = {}
	for _, c in cells do onPath[c.x .. "," .. c.y] = true end
	return { cells = cells, length = len, step = step, px = px, pz = pz, n = n, onPath = onPath }
end

-- (x, z) in bed studs, `s` studs along the path. Clamped to the path's two ends.
function PathGen.posAt(path: any, s: number): (number, number)
	local i = math.clamp(math.floor(s / path.step + 0.5), 0, path.n) + 1
	return path.px[i], path.pz[i]
end

-- Pads: every non-path cell touching the path (8-neighbourhood), sorted by row, then column. A pad's index
-- in this list is its id on the wire (Plant(padId, kind)).
function PathGen.pads(cfg: any, path: any): { any }
	local out, seen = {}, {}
	for _, c in path.cells do
		for dx = -1, 1 do
			for dy = -1, 1 do
				local x, y = c.x + dx, c.y + dy
				local key = x .. "," .. y
				if x >= 0 and x < cfg.GridW and y >= 0 and y < cfg.GridH and not path.onPath[key] and not seen[key] then
					seen[key] = true
					table.insert(out, { x = x, y = y, cx = (x + 0.5) * cfg.Tile, cz = (y + 0.5) * cfg.Tile })
				end
			end
		end
	end
	table.sort(out, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.x < b.x end)
	return out
end

-- (mask, studs covered): one boolean per path sample, inside `range` of the point (cx, cz).
function PathGen.rangeMask(path: any, cx: number, cz: number, range: number): ({ boolean }, number)
	local mask = table.create(path.n + 1, false)
	local cover = 0
	local r2 = range * range
	for i = 1, path.n + 1 do
		local dx, dz = path.px[i] - cx, path.pz[i] - cz
		if dx * dx + dz * dz <= r2 then
			mask[i] = true
			cover += path.step
		end
	end
	return mask, cover
end

-- The pads that glow (Garden.client) and that the pacing model's NORMAL player plants on (tests/GardenModel.luau):
-- the `n` FREE pads (not in `taken`, a set of pad ids) that see the most path for a level-1 `kind` gnome (the one
-- the game suggests; cfg.Glow.Kind when none is given), best first, ties to the lower pad id. REVIEW-2: the game
-- showed the best pads only until the first gnome stood, while the brag's minutes assumed a player who always
-- plants on one of the best pads for the gnome they plant.
function PathGen.bestPads(cfg: any, path: any, pads: { any }, taken: { [number]: boolean }, n: number, kind: string?): { number }
	local range = cfg.Gnomes[kind or cfg.Glow.Kind].levels[1].range
	local ranked = {}
	for id, pd in pads do
		if not taken[id] then
			local _, cover = PathGen.rangeMask(path, pd.cx, pd.cz, range)
			table.insert(ranked, { id = id, cover = cover })
		end
	end
	table.sort(ranked, function(a, b)
		if a.cover ~= b.cover then return a.cover > b.cover end
		return a.id < b.id
	end)
	local out = {}
	for k = 1, math.min(n, #ranked) do out[k] = ranked[k].id end
	return out
end

-- What glows and what is starred, as ONE rule for Garden.client (the pads), Hud.client (the star) and the pacing
-- model's normal player (tests/GardenModel.luau): the gnome `suggestKind` (Garden.suggestKind, passed in: a shared
-- module never requires by string) names for the standing `gnomes` ({ pad, kind } each), and the best free pads
-- FOR THAT GNOME. -> kind, { padId }
function PathGen.glow(cfg: any, path: any, pads: { any }, gnomes: { any }, chapter: number, suggestKind: any): (string, { number })
	local taken, have = {}, {}
	for _, gn in gnomes do
		taken[gn.pad] = true
		have[gn.kind] = (have[gn.kind] or 0) + 1
	end
	local kind = suggestKind(cfg, chapter, have)
	return kind, PathGen.bestPads(cfg, path, pads, taken, cfg.Glow.Count, kind)
end

-- The path on the wire: "x,y;x,y;..." (public: the bed is drawn for everyone anyway).
function PathGen.encodeCells(cells: { any }): string
	local parts = table.create(#cells)
	for i, c in cells do parts[i] = c.x .. "," .. c.y end
	return table.concat(parts, ";")
end

-- The client's copy of the path from the replicated text, or nil when the text is not a path.
function PathGen.fromText(cfg: any, text: any): any
	if type(text) ~= "string" or text == "" then return nil end
	local cells = {}
	for pair in string.gmatch(text, "[^;]+") do
		local x, y = string.match(pair, "^(%d+),(%d+)$")
		if not x then return nil end
		table.insert(cells, { x = tonumber(x) :: number, y = tonumber(y) :: number })
	end
	if #cells < 2 then return nil end
	for i = 2, #cells do
		local a, b = cells[i - 1], cells[i]
		if math.abs(a.x - b.x) + math.abs(a.y - b.y) ~= 1 then return nil end
	end
	return PathGen.pathFromCells(cfg, cells)
end

return PathGen
