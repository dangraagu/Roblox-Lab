--!strict
-- Quake.luau - "Get off the red ground." (DESIGN.md §2.5). Pure; randomness injected.
--
-- Every EverySeconds from FirstAt, a batch of at most BatchMax cells cracks red for CrackSeconds and then drops into
-- the sea. For each player on the island (random order) there is an OwnCellChance chance to crack their own cell
-- plus one neighbour; the rest of the batch is random. The rule that keeps it fair: a cell may crack only if a
-- 4-neighbour is intact, not cracking (or chosen) and at most one level away, and adding it never strands a cell
-- already chosen. So every red cell has a safe step at most one cell away (escape <= 10 studs), and a cell whose
-- neighbours are all gone can never crack: an isolated pocket is safe. Never more than CapShare of the island breaks.
-- A hit: the root over a dropping cell at every sample in [drop, drop + LagGrace] (Zones.newJudge), later over a hole
-- for GroundGrace in a row, or below FallOutY.

local Quake = {}

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function key(i: number, j: number): number
	return i * 1000 + j
end

function Quake.new(): any
	return { cracking = {}, dropped = {}, nCracking = 0, nDropped = 0 }
end

function Quake.batchTimes(cfg: any): { number }
	local qc = cfg.Quake
	local out = {}
	local t = qc.FirstAt
	while t + qc.CrackSeconds <= cfg.Round.DisasterSeconds - 3 + 1e-9 do
		table.insert(out, t)
		t += qc.EverySeconds
	end
	return out
end

function Quake.cap(cfg: any): number
	return math.floor(cfg.Quake.CapShare * cfg.Island.Grid * cfg.Island.Grid)
end

function Quake.isDropped(q: any, i: number, j: number): boolean
	return q.dropped[key(i, j)] == true
end

function Quake.isCracking(q: any, i: number, j: number): boolean
	return q.cracking[key(i, j)] ~= nil
end

-- When cell (i, j) drops (nil when it is not cracking).
function Quake.dropAt(q: any, i: number, j: number): number?
	local c = q.cracking[key(i, j)]
	return if c then c.dropAt else nil
end

function Quake.brokenCount(q: any): number
	return q.nCracking + q.nDropped
end

local function inGrid(levels: { { number } }, i: number, j: number): boolean
	return i >= 1 and i <= #levels and j >= 1 and j <= #levels
end

-- A neighbour of (i, j) a player can step to: intact, not cracking, not in `chosen`, not `blocked` (under a ring), at
-- most one level away.
local function safeOf(levels: { { number } }, q: any, i: number, j: number, chosen: { [number]: boolean }?,
	blocked: { [number]: boolean }?): { i: number, j: number }?
	for _, d in DIRS do
		local a, b = i + d[1], j + d[2]
		if inGrid(levels, a, b) and not q.dropped[key(a, b)] and q.cracking[key(a, b)] == nil
			and not (chosen and chosen[key(a, b)]) and not (blocked and blocked[key(a, b)])
			and math.abs(levels[a][b] - levels[i][j]) <= 1 then
			return { i = a, j = b }
		end
	end
	return nil
end

function Quake.safeNeighbour(levels: { { number } }, q: any, i: number, j: number): { i: number, j: number }?
	return safeOf(levels, q, i, j, nil)
end

function Quake.hasSafeNeighbour(levels: { { number } }, q: any, i: number, j: number): boolean
	return safeOf(levels, q, i, j, nil) ~= nil
end

-- May (i, j) crack, given the cells already chosen for this batch? It needs a safe neighbour of its own, and adding
-- it must leave every chosen cell a safe neighbour too. `blocked` (optional): cells a live ring overlaps, which are
-- not a safe way off (the ring may land while the player steps onto it).
function Quake.eligible(levels: { { number } }, q: any, i: number, j: number, chosen: { [number]: boolean },
	blocked: { [number]: boolean }?): boolean
	if not inGrid(levels, i, j) then return false end
	local k = key(i, j)
	if q.dropped[k] or q.cracking[k] ~= nil or chosen[k] then return false end
	if safeOf(levels, q, i, j, chosen, blocked) == nil then return false end
	chosen[k] = true
	local ok = true
	for ck in chosen do
		if ck ~= k and safeOf(levels, q, math.floor(ck / 1000), ck % 1000, chosen, blocked) == nil then
			ok = false
			break
		end
	end
	chosen[k] = nil
	return ok
end

-- players = { { i, j } } standing on intact cells; blocked = cells under live rings (optional). -> the batch.
function Quake.pickBatch(cfg: any, levels: { { number } }, q: any, players: { any }, rand: () -> number,
	blocked: { [number]: boolean }?): { any }
	local qc = cfg.Quake
	local cap = Quake.cap(cfg)
	local chosen: { [number]: boolean } = {}
	local batch = {}
	local function add(i: number, j: number): boolean
		if #batch >= qc.BatchMax or Quake.brokenCount(q) + #batch >= cap then return false end
		if not Quake.eligible(levels, q, i, j, chosen, blocked) then return false end
		chosen[key(i, j)] = true
		table.insert(batch, { i = i, j = j })
		return true
	end
	local order = table.clone(players)
	for k = #order, 2, -1 do
		local r = 1 + math.min(k - 1, math.floor(rand() * k))
		order[k], order[r] = order[r], order[k]
	end
	for _, p in order do
		if rand() < qc.OwnCellChance and add(p.i, p.j) then
			local nb = {}
			for _, d in DIRS do table.insert(nb, { p.i + d[1], p.j + d[2] }) end
			for k = #nb, 2, -1 do
				local r = 1 + math.min(k - 1, math.floor(rand() * k))
				nb[k], nb[r] = nb[r], nb[k]
			end
			for _, c in nb do
				if add(c[1], c[2]) then break end
			end
		end
	end
	local n = #levels
	local pool = {}
	for i = 1, n do
		for j = 1, n do table.insert(pool, { i, j }) end
	end
	for k = #pool, 2, -1 do
		local r = 1 + math.min(k - 1, math.floor(rand() * k))
		pool[k], pool[r] = pool[r], pool[k]
	end
	for _, c in pool do
		if #batch >= qc.BatchMax then break end
		add(c[1], c[2])
	end
	return batch
end

function Quake.crack(q: any, cells: { any }, now: number, crackSeconds: number)
	for _, c in cells do
		local k = key(c.i, c.j)
		if q.cracking[k] == nil and not q.dropped[k] then
			q.cracking[k] = { i = c.i, j = c.j, crackAt = now, dropAt = now + crackSeconds }
			q.nCracking += 1
		end
	end
end

-- Cells whose time is up drop now. -> { { i, j, dropAt } }
function Quake.update(q: any, now: number): { any }
	local out = {}
	for k, c in q.cracking do
		if now >= c.dropAt - 1e-9 then table.insert(out, c) end
	end
	table.sort(out, function(a, b) return key(a.i, a.j) < key(b.i, b.j) end)
	for _, c in out do
		local k = key(c.i, c.j)
		q.cracking[k] = nil
		q.nCracking -= 1
		q.dropped[k] = true
		q.nDropped += 1
	end
	return out
end

return Quake
