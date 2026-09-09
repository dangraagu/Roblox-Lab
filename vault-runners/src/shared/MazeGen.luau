--!strict
-- Ren, origin-bevisst labyrint-generator + plasserings-hjelpere. Ingen globaler,
-- ingen CONFIG-lesing (alt sendes inn), så den kan brukes til FLERE samtidige
-- labyrint-instanser (hver på sin egen `origin` i verden) — grunnlaget for lobby-
-- modusen. Samme logikk som det gamle enkelt-maze-oppsettet, bare parameterisert.

local MazeGen = {}

local function halfOf(n: number): number
	return (n - 1) / 2
end

-- Verdens-posisjon for en fin-rute-celle (x,y i 0..gCols-1 / 0..gRows-1), sentrert
-- om `origin` (default midten av verden). cellSize = studs pr celle.
function MazeGen.gridToWorld(x: number, y: number, gCols: number, gRows: number, cellSize: number, origin: Vector3?): Vector3
	local o = origin or Vector3.zero
	return Vector3.new(o.X + (x - halfOf(gCols)) * cellSize, o.Y, o.Z + (y - halfOf(gRows)) * cellSize)
end

-- Senter av en LABYRINT-celle (cx,cy i 0..cols-1) -> fin-rute (2c+1) -> verden.
function MazeGen.cellCenterWorld(cx: number, cy: number, gCols: number, gRows: number, cellSize: number, origin: Vector3?): Vector3
	return MazeGen.gridToWorld(2 * cx + 1, 2 * cy + 1, gCols, gRows, cellSize, origin)
end

-- Vanskelighet for et nivå ut fra kurven (CONFIG.Curve sendes inn som `c`).
-- Identisk med den gamle getDifficulty; ren funksjon.
function MazeGen.getDifficulty(L: number, c: any): any
	local size = math.clamp(c.StartSize + math.floor((L - 1) / c.SizeEveryNLevels), c.StartSize, c.MaxSize)
	local cells = size * size

	local traps = 0
	if L >= c.FirstTrapLevel then
		traps = math.clamp(1 + math.floor((L - c.FirstTrapLevel) / c.TrapEveryNLevels), 0, c.MaxTraps)
	end

	local monsters = 0
	if L >= c.FirstMonsterLevel then
		monsters = math.clamp(1 + math.floor((L - c.FirstMonsterLevel) / c.MonsterEveryNLevels), 0, c.MaxMonsters)
	end

	local speed = math.clamp(c.MonsterSpeedStart + (L - 1) * c.MonsterSpeedPerLevel, c.MonsterSpeedStart, c.MonsterSpeedMax)
	local coins = math.max(c.MinCoins, math.floor(cells * c.CoinDensity))
	local gems = c.StartGems + math.floor(L / c.GemsPerLevels)
	local buttons = c.StartButtons + math.floor(L / c.ButtonsPerLevels)
	local sight = math.clamp(c.StartSight - (L - 1) * c.SightTightenPerLevel, c.MinSight, c.StartSight)

	return {
		size = size, coins = coins, gems = gems, buttons = buttons,
		traps = traps, monsters = monsters, monsterSpeed = speed, sight = sight,
	}
end

-- Recursive backtracker (iterativ). grid[y][x] = true betyr vegg. Deterministisk
-- gitt `rng`. Returnerer grid, gCols, gRows.
function MazeGen.generate(cols: number, rows: number, rng: any): (any, number, number)
	local gCols, gRows = 2 * cols + 1, 2 * rows + 1
	local grid = {}
	for y = 0, gRows - 1 do
		grid[y] = {}
		for x = 0, gCols - 1 do grid[y][x] = true end
	end

	local visited = {}
	local function key(cx, cy) return cx .. "," .. cy end

	local stack = { { 0, 0 } }
	visited[key(0, 0)] = true
	grid[1][1] = false
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

	while #stack > 0 do
		local cur = stack[#stack]
		local cx, cy = cur[1], cur[2]
		local nbrs = {}
		for _, d in ipairs(dirs) do
			local nx, ny = cx + d[1], cy + d[2]
			if nx >= 0 and nx < cols and ny >= 0 and ny < rows and not visited[key(nx, ny)] then
				table.insert(nbrs, { nx, ny, d[1], d[2] })
			end
		end
		if #nbrs > 0 then
			local pick = nbrs[rng:NextInteger(1, #nbrs)]
			local nx, ny, dx, dy = pick[1], pick[2], pick[3], pick[4]
			visited[key(nx, ny)] = true
			grid[2 * cy + 1 + dy][2 * cx + 1 + dx] = false
			grid[2 * ny + 1][2 * nx + 1] = false
			table.insert(stack, { nx, ny })
		else
			table.remove(stack)
		end
	end
	return grid, gCols, gRows
end

return MazeGen
