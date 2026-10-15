--!strict
-- MapGen.luau - the 13 x 13 terraced island (DESIGN.md §2.2). Pure: no Roblox, randomness injected as
-- rand(): number in [0, 1). The server builds Parts from what this returns (Main.server.luau: buildIsland).
--
-- Shape: the max of 1-3 cones (peak 4-6 levels, slope 0.55-0.95 levels per cell, peaks in the inner 5 x 5), clipped
-- to 0..MaxLevel and to the cell's distance from the edge. `max` and `min` of 1-Lipschitz functions are 1-Lipschitz,
-- so neighbouring cells never differ by more than one level; validate() checks it anyway, with the flood rules:
--   * >= MinHighCells cells at level >= HighLevel (dry after the last flood rise);
--   * no flood traps: every level-k cell (k < HighLevel) reaches a level >= k+1 cell without stepping below k;
--   * the longest such escape is at most MaxEscapeStuds of cell-centre path.
-- A candidate that fails is re-rolled. Every accepted map supports every disaster: nothing here knows which
-- disaster comes next (the server draws that from a different Random, after the map is built).
--
-- Grid: levels[i][j], i along x and j along z, both 1..Grid. Cell (i, j)'s centre is at
-- x = (i - (Grid + 1) / 2) * CellStuds, so the island is centred on the world origin.

local MapGen = {}

function MapGen.key(i: number, j: number): number
	return i * 1000 + j
end

function MapGen.halfSize(cfg: any): number
	return cfg.Grid * cfg.CellStuds / 2
end

function MapGen.cellCenter(cfg: any, i: number, j: number): (number, number)
	local mid = (cfg.Grid + 1) / 2
	return (i - mid) * cfg.CellStuds, (j - mid) * cfg.CellStuds
end

-- (i, j) of the cell containing the point, or nil off the island.
function MapGen.cellAt(cfg: any, x: number, z: number): (number?, number?)
	if x ~= x or z ~= z then return nil, nil end
	local n = cfg.Grid
	local i = math.floor(x / cfg.CellStuds + n / 2) + 1
	local j = math.floor(z / cfg.CellStuds + n / 2) + 1
	if i < 1 or i > n or j < 1 or j > n then return nil, nil end
	return i, j
end

function MapGen.topY(cfg: any, level: number): number
	return level * cfg.LevelStuds
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
MapGen.DIRS = DIRS

function MapGen.highCount(cfg: any, levels: { { number } }): number
	local n = 0
	for i = 1, #levels do
		for j = 1, #levels[i] do
			if levels[i][j] >= cfg.HighLevel then n += 1 end
		end
	end
	return n
end

-- For rise r (the water covers level r - 1): BFS distance in cells from every level == r-1 cell to the nearest
-- level >= r cell, walking only on cells of level >= r-1 with steps of at most one level. -> { [key] = cells },
-- with no entry for an unreachable cell (a flood trap), and the distance grid.
function MapGen.floodEscape(levels: { { number } }, rise: number): ({ [number]: number }, { { number } })
	local n = #levels
	local INF = math.huge
	local dist: { { number } } = {}
	local queue: { { number } } = {}
	for i = 1, n do
		dist[i] = {}
		for j = 1, n do
			if levels[i][j] >= rise then
				dist[i][j] = 0
				table.insert(queue, { i, j })
			else
				dist[i][j] = INF
			end
		end
	end
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		local i, j = c[1], c[2]
		for _, d in DIRS do
			local a, b = i + d[1], j + d[2]
			if a >= 1 and a <= n and b >= 1 and b <= n and dist[a][b] == INF
				and levels[a][b] >= rise - 1 and math.abs(levels[a][b] - levels[i][j]) <= 1 then
				dist[a][b] = dist[i][j] + 1
				table.insert(queue, { a, b })
			end
		end
	end
	local out: { [number]: number } = {}
	for i = 1, n do
		for j = 1, n do
			if levels[i][j] == rise - 1 and dist[i][j] ~= INF then
				out[MapGen.key(i, j)] = dist[i][j]
			end
		end
	end
	return out, dist
end

local function escapeStuds(cfg: any, cells: number): number
	return cells * cfg.CellStuds + cfg.CellStuds / 2
end

-- The longest flood escape on the map, in studs of cell-centre path (0 when nothing ever floods).
function MapGen.worstEscape(cfg: any, levels: { { number } }): number
	local worst = 0
	for rise = 1, cfg.HighLevel do
		local esc = MapGen.floodEscape(levels, rise)
		for _, d in esc do
			worst = math.max(worst, escapeStuds(cfg, d))
		end
	end
	return worst
end

-- (ok, why). Every rule of DESIGN.md §2.2.
function MapGen.validate(cfg: any, levels: { { number } }): (boolean, string?)
	local n = cfg.Grid
	if #levels ~= n then return false, "grid is not " .. n .. " wide" end
	for i = 1, n do
		if #levels[i] ~= n then return false, "grid row " .. i .. " is not " .. n .. " long" end
		for j = 1, n do
			local l = levels[i][j]
			if type(l) ~= "number" or l < 0 or l > cfg.MaxLevel or l % 1 ~= 0 then
				return false, string.format("cell (%d, %d) has level %s", i, j, tostring(l))
			end
			for _, d in DIRS do
				local a, b = i + d[1], j + d[2]
				if a >= 1 and a <= n and b >= 1 and b <= n and math.abs(levels[a][b] - l) > 1 then
					return false, string.format("step of more than one level at (%d, %d)", i, j)
				end
			end
		end
	end
	local high = MapGen.highCount(cfg, levels)
	if high < cfg.MinHighCells then
		return false, string.format("only %d high cells (need %d)", high, cfg.MinHighCells)
	end
	for rise = 1, cfg.HighLevel do
		local esc = MapGen.floodEscape(levels, rise)
		for i = 1, n do
			for j = 1, n do
				if levels[i][j] == rise - 1 then
					local d = esc[MapGen.key(i, j)]
					if d == nil then
						return false, string.format("flood trap at (%d, %d) for rise %d", i, j, rise)
					end
					if escapeStuds(cfg, d) > cfg.MaxEscapeStuds then
						return false, string.format("flood escape of %d studs at (%d, %d)", escapeStuds(cfg, d), i, j)
					end
				end
			end
		end
	end
	return true, nil
end

local function pick(list: { any }, rand: () -> number): any
	return list[math.min(#list, 1 + math.floor(rand() * #list))]
end

local function candidate(cfg: any, rand: () -> number): { { number } }
	local n = cfg.Grid
	local peaks = {}
	for _ = 1, pick(cfg.Peaks, rand) do
		local span = cfg.CoreMax - cfg.CoreMin + 1
		table.insert(peaks, {
			i = cfg.CoreMin + math.min(span - 1, math.floor(rand() * span)),
			j = cfg.CoreMin + math.min(span - 1, math.floor(rand() * span)),
			h = pick(cfg.PeakHeights, rand),
			s = cfg.SlopeMin + (cfg.SlopeMax - cfg.SlopeMin) * rand(),
		})
	end
	local levels: { { number } } = {}
	for i = 1, n do
		levels[i] = {}
		for j = 1, n do
			local best = 0
			for _, p in peaks do
				local v = p.h - math.floor(p.s * math.sqrt((i - p.i) ^ 2 + (j - p.j) ^ 2))
				if v > best then best = v end
			end
			local edge = math.min(i - 1, j - 1, n - i, n - j)
			levels[i][j] = math.max(0, math.min(cfg.MaxLevel, best, edge))
		end
	end
	return levels
end

-- The island used when no candidate passes within MaxTries (never measured to happen): one broad hill.
local function fallback(cfg: any): { { number } }
	local n = cfg.Grid
	local mid = (n + 1) / 2
	local levels: { { number } } = {}
	for i = 1, n do
		levels[i] = {}
		for j = 1, n do
			local d = math.max(math.abs(i - mid), math.abs(j - mid))
			levels[i][j] = math.max(0, math.min(cfg.MaxLevel, math.floor(mid - 1 - d + 0.5)))
		end
	end
	return levels
end

-- Decor: never collidable, never queryable, never touchable (the server makes them so). Kinds come from the style.
function MapGen.props(cfg: any, levels: { { number } }, styleIndex: number, rand: () -> number): { any }
	local style = cfg.Styles[styleIndex]
	local n = cfg.Grid
	local count = math.min(cfg.MaxProps, 30 + math.floor(rand() * 31))
	local out = {}
	for _ = 1, count do
		local i = 1 + math.min(n - 1, math.floor(rand() * n))
		local j = 1 + math.min(n - 1, math.floor(rand() * n))
		local kind = if rand() < 0.6 then style.props[1] else style.props[2]
		table.insert(out, {
			i = i,
			j = j,
			kind = kind,
			ox = (rand() * 2 - 1) * cfg.CellStuds * 0.3,
			oz = (rand() * 2 - 1) * cfg.CellStuds * 0.3,
			rot = rand() * 360,
			scale = 0.8 + rand() * 0.5,
		})
	end
	return out
end

-- -> map { levels, style, props }, tries. Never errors: after MaxTries failures it returns the fallback hill.
function MapGen.generate(cfg: any, rand: () -> number): (any, number)
	local levels = nil
	local tries = 0
	while tries < cfg.MaxTries do
		tries += 1
		local c = candidate(cfg, rand)
		if MapGen.validate(cfg, c) then
			levels = c
			break
		end
	end
	if levels == nil then
		levels = fallback(cfg)
	end
	local style = 1 + math.min(#cfg.Styles - 1, math.floor(rand() * #cfg.Styles))
	return { levels = levels, style = style, props = MapGen.props(cfg, levels, style, rand) }, tries
end

-- Where `count` roster players land: distinct level >= 1 cells, DropSpacingCells (Chebyshev) from each other while
-- that is possible, then any free level >= 1 cell, then any free cell.
function MapGen.dropCells(cfg: any, levels: { { number } }, count: number, rand: () -> number): { { i: number, j: number } }
	local n = #levels
	local pool = {}
	for i = 1, n do
		for j = 1, n do
			if levels[i][j] >= 1 then table.insert(pool, { i = i, j = j }) end
		end
	end
	for k = #pool, 2, -1 do
		local r = 1 + math.min(k - 1, math.floor(rand() * k))
		pool[k], pool[r] = pool[r], pool[k]
	end
	local out = {}
	local used = {}
	for _, c in pool do
		if #out >= count then break end
		local ok = true
		for _, o in out do
			if math.max(math.abs(c.i - o.i), math.abs(c.j - o.j)) < cfg.DropSpacingCells then
				ok = false
				break
			end
		end
		if ok then
			table.insert(out, c)
			used[MapGen.key(c.i, c.j)] = true
		end
	end
	for _, c in pool do
		if #out >= count then break end
		if not used[MapGen.key(c.i, c.j)] then
			table.insert(out, c)
			used[MapGen.key(c.i, c.j)] = true
		end
	end
	for i = 1, n do
		for j = 1, n do
			if #out >= count then break end
			if not used[MapGen.key(i, j)] then
				table.insert(out, { i = i, j = j })
				used[MapGen.key(i, j)] = true
			end
		end
	end
	return out
end

return MapGen
