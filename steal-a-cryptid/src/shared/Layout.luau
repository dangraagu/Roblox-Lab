--!strict
-- Layout.luau - the yard grid: lair and Rival Camp generation, reachability, trap placement.
--
-- Pure. `cfg` and `Rng` come in as arguments; this file requires NOTHING (a bare
-- `require("./X")` resolves in the luau CLI and is INVALID in Roblox).
--
-- The grid (DESIGN.md section 3), plot-local:
--   row 0      the front fence; only the gate cell (GateCol) is floor
--   rows 1..8  the yard; fence lines are full rows of fence with gaps, rocks sit in free rows
--   row 8      the cage walk: never a trap, rock or fence
--   row 9      the cage row: never walkable
-- A trap (laser or snare) sits ON a floor cell and never blocks walking. Rocks and fences do.
-- Snares block the ROUTE a raider or poacher may plan (stepping on one is a catch), lasers do not.

local Layout = {}

local function key(col: number, row: number): number
	return (row + 2) * 32 + (col + 2)
end
Layout.key = key

--============================================================================ geometry

function Layout.cellRect(cfg: any, col: number, row: number): any
	local s = cfg.World.CellSize
	local x0 = s * (col - 1)
	local z0 = cfg.World.ApronDepth + s * row
	return { x0 = x0, x1 = x0 + s, z0 = z0, z1 = z0 + s }
end

function Layout.cellCenter(cfg: any, col: number, row: number): (number, number)
	local r = Layout.cellRect(cfg, col, row)
	return (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
end

-- The cell a plot-local point lies in. A point on a boundary belongs to the higher cell.
function Layout.cellAt(cfg: any, x: number, z: number): (number, number)
	local s = cfg.World.CellSize
	return math.floor(x / s) + 1, math.floor((z - cfg.World.ApronDepth) / s)
end

-- The grab prompt's anchor for the cage in `col`: over the CENTRE of its grab cell (row 8).
-- REVIEW-1 R2-3: DESIGN.md hung it on the cage front (z 88) with a 10-stud reach, which shows the
-- prompt over 2.9x the grab cell's area; 64 % of the points where a raider saw it were on no grab
-- cell, so a full hold ended in a refusal. The grab spot is now a disc round this anchor that the
-- prompt draws exactly (Layout.inGrabReach, REVIEW-1.md B2).
function Layout.grabAnchor(cfg: any, col: number): (number, number)
	return Layout.cellCenter(cfg, col, cfg.World.CageWalkRow)
end

-- May a trusted position at (x, z) grab the cage in `col`? Within Raid.GrabReach of the anchor on the
-- flat: the same region the prompt shows in (REVIEW-1.md B2). A disc, not the grab cell: row 8 is open
-- along x, so the cell was a region the prompt could not match (it missed the ends of the cage front
-- and spilled past the cell's edge, where a full hold was refused).
function Layout.inGrabReach(cfg: any, col: number, x: number, z: number): boolean
	local ax, az = Layout.grabAnchor(cfg, col)
	return (x - ax) ^ 2 + (z - az) ^ 2 <= cfg.Raid.GrabReach ^ 2
end

--============================================================================ gap columns

local comboCache: { [number]: { { number } } } = {}

-- Every way to put `n` gaps in the yard's columns at least 2 apart, in lexicographic order.
-- Drawing an index uniformly from this list is uniform over legal gap sets, with one draw.
function Layout.gapCombos(cfg: any, n: number): { { number } }
	local cols = cfg.World.YardCols
	local ck = cols * 100 + n
	local cached = comboCache[ck]
	if cached then return cached end
	local out = {}
	local cur = {}
	local function rec(start: number)
		if #cur == n then
			table.insert(out, table.clone(cur))
			return
		end
		for c = start, cols do
			table.insert(cur, c)
			rec(c + 2)
			table.remove(cur)
		end
	end
	rec(1)
	comboCache[ck] = out
	return out
end

--============================================================================ seeds

-- A player's own home: the same every session. userId is reduced FIRST, so the largest
-- intermediate is 20260916 * 7919 + 999982 * 104729, far under 2^53.
function Layout.lairSeed(cfg: any, userId: number): number
	return (cfg.WorldSeed * 7919 + (math.floor(userId) % 999983) * 104729) % 2147483647
end

-- A reproducible camp seed for the SPECS: Layout.spec and Heist.spec enumerate their camp sets with it,
-- and the numbers in CLAUDE.md are measured over those sets. THE SERVER DOES NOT USE IT (REVIEW-1.md
-- A2): as DESIGN.md wrote it, each raid's seed was the last one plus a constant, so one camp's seed,
-- recovered from its sign and layout, predicted every later camp on the server. The server draws each
-- camp's seed from a server-only Random stream instead.
function Layout.campSeed(cfg: any, salt: number, raidSerial: number, tier: number): number
	return (cfg.WorldSeed * 31 + salt * 7 + (raidSerial % 1000000) * 2654435761 + tier * 104729) % 2147483647
end

-- 8 x 8 names, a pure function of the camp seed.
function Layout.campName(cfg: any, seed: number): string
	local first = cfg.Camp.NameFirst[(seed % #cfg.Camp.NameFirst) + 1]
	local last = cfg.Camp.NameLast[(math.floor(seed / #cfg.Camp.NameFirst) % #cfg.Camp.NameLast) + 1]
	local possessive = if string.sub(last, -1) == "s" then last .. "'" else last .. "'s"
	return first .. " " .. possessive .. " Camp"
end

--============================================================================ the layout object

local function blank(cfg: any, kind: string): any
	return {
		kind = kind,
		cols = cfg.World.YardCols,
		rows = cfg.World.YardRows,
		gate = cfg.World.GateCol,
		cageRow = cfg.World.CageRow,
		entryCol = cfg.World.EntryCol,
		entryRow = cfg.World.EntryRow,
		cells = {},
		lines = {},
		rocks = {},
		trapsByKey = {},
		trapOrder = {},
		cages = {},
		attempts = 0,
		fallback = false,
	}
end

function Layout.cellKind(L: any, col: number, row: number): string
	if col < 1 or col > L.cols then return "void" end
	if row == 0 then
		return if col == L.gate then "floor" else "fence"
	end
	if row == L.cageRow then return "cage" end
	if row < 0 or row > L.rows then return "void" end
	return L.cells[key(col, row)] or "floor"
end

function Layout.trapAt(L: any, col: number, row: number): any
	return L.trapsByKey[key(col, row)]
end

function Layout.traps(L: any): { any }
	local out = {}
	for _, k in L.trapOrder do
		local t = L.trapsByKey[k]
		if t then table.insert(out, t) end
	end
	return out
end

function Layout.count(L: any, kind: string): number
	local n = 0
	for _, t in L.trapsByKey do
		if t.kind == kind then n += 1 end
	end
	return n
end

local function addTrap(L: any, trap: any)
	local k = key(trap.col, trap.row)
	if L.trapsByKey[k] == nil then
		table.insert(L.trapOrder, k)
	end
	L.trapsByKey[k] = trap
end

local function removeTrap(L: any, col: number, row: number): any
	local k = key(col, row)
	local t = L.trapsByKey[k]
	if t == nil then return nil end
	L.trapsByKey[k] = nil
	local i = table.find(L.trapOrder, k)
	if i then table.remove(L.trapOrder, i) end
	return t
end

local function setLines(L: any, lines: { any })
	for _, line in lines do
		table.insert(L.lines, { row = line.row, cols = table.clone(line.cols) })
		for c = 1, L.cols do
			if not table.find(line.cols, c) then
				L.cells[key(c, line.row)] = "fence"
			end
		end
	end
end

local function setRock(L: any, col: number, row: number)
	L.cells[key(col, row)] = "rock"
	table.insert(L.rocks, { col, row })
end

-- A layout from explicit data (a spec, or a future player lair loaded as a raid target).
function Layout.fromSpec(cfg: any, spec: any): any
	local L = blank(cfg, spec.kind or "lair")
	setLines(L, spec.lines or {})
	for _, r in spec.rocks or {} do
		setRock(L, r[1], r[2])
	end
	return L
end

--============================================================================ reachability

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Every floor cell 4-connected to (col, row) without stepping on a snare. Lasers are passable:
-- they are timed, not walls. Returns a set keyed by Layout.key.
function Layout.reachableFrom(L: any, col: number, row: number): { [number]: boolean }
	local seen = {}
	if Layout.cellKind(L, col, row) ~= "floor" then return seen end
	local t0 = Layout.trapAt(L, col, row)
	if t0 and t0.kind == "snare" then return seen end
	local queue = { { col, row } }
	seen[key(col, row)] = true
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, d in DIRS do
			local nc, nr = cur[1] + d[1], cur[2] + d[2]
			local k = key(nc, nr)
			if not seen[k] and Layout.cellKind(L, nc, nr) == "floor" then
				local t = L.trapsByKey[k]
				if not (t and t.kind == "snare") then
					seen[k] = true
					table.insert(queue, { nc, nr })
				end
			end
		end
	end
	return seen
end

-- Row 8 is one free connected row, so reaching any of it reaches every cage.
function Layout.row8Reachable(L: any): boolean
	local reach = Layout.reachableFrom(L, L.entryCol, L.entryRow)
	for c = 1, L.cols do
		if reach[key(c, L.rows)] then return true end
	end
	return false
end

--============================================================================ generation

-- The cells a rock or a generated snare may use: free rows 1..7, not the entry, not directly
-- above or below a gap (so every gap always has a safe cell on both sides).
local function bandCells(L: any): { { number } }
	local lineRows = {}
	for _, line in L.lines do
		lineRows[line.row] = line
	end
	local out = {}
	for r = 1, L.rows - 1 do
		if not lineRows[r] then
			for c = 1, L.cols do
				local protected = (c == L.entryCol and r == L.entryRow)
				for _, line in L.lines do
					if math.abs(r - line.row) == 1 and table.find(line.cols, c) then protected = true end
				end
				if not protected and L.cells[key(c, r)] == nil then
					table.insert(out, { c, r })
				end
			end
		end
	end
	return out
end

-- k distinct items from `list` by a partial Fisher-Yates using the high-bit Rng.below.
local function pickK(rng: any, list: { any }, k: number): { any }
	local pool = table.clone(list)
	local out = {}
	for i = 1, math.min(k, #pool) do
		local j = i - 1 + rng:below(#pool - i + 1)
		pool[i], pool[j] = pool[j], pool[i]
		table.insert(out, pool[i])
	end
	return out
end

local function drawLines(cfg: any, rng: any, rows: { number }, gaps: { number }): { any }
	local lines = {}
	for i, row in rows do
		local combos = Layout.gapCombos(cfg, gaps[i])
		table.insert(lines, { row = row, cols = combos[rng:below(#combos)] })
	end
	return lines
end

-- A player's lair: two fence lines of three gaps, six rocks, resampled until the cage walk is
-- reachable (DESIGN.md sections 6-7). The layout is never saved; it is a function of the seed.
function Layout.generateLair(cfg: any, Rng: any, seed: number): any
	local rng = Rng.new(seed)
	local rows = cfg.World.LairFenceRows
	local gaps = {}
	for i = 1, #rows do gaps[i] = cfg.World.LairGapsPerLine end
	local maxAttempts = cfg.Camp.MaxLayoutAttempts
	local last = nil
	for attempt = 1, maxAttempts do
		local L = blank(cfg, "lair")
		L.seed = seed
		setLines(L, drawLines(cfg, rng, rows, gaps))
		for _, cell in pickK(rng, bandCells(L), cfg.World.LairRocks) do
			setRock(L, cell[1], cell[2])
		end
		L.attempts = attempt
		if Layout.row8Reachable(L) then return L end
		last = L
	end
	local F = blank(cfg, "lair")
	F.seed = seed
	setLines(F, if last then last.lines else drawLines(cfg, rng, rows, gaps))
	F.attempts = maxAttempts
	F.fallback = true
	return F
end

-- A Rival Camp of `tier`. Generator order, so a test can replay it (DESIGN.md section 7):
-- fence lines and gap columns; rocks; snares; cage columns; prize column; reachability (resample
-- up to MaxLayoutAttempts, then no rocks and no snares); lasers into gaps; phases; species.
function Layout.generateCamp(cfg: any, Rng: any, seed: number, tier: number): any
	local P = cfg.Camps[tier]
	local rng = Rng.new(seed)
	local maxAttempts = cfg.Camp.MaxLayoutAttempts
	local built: any, last: any = nil, nil
	local allCols = {}
	for c = 1, cfg.World.YardCols do allCols[c] = c end

	local function cagesFor(L: any)
		local cols = pickK(rng, allCols, cfg.Camp.Cages)
		table.sort(cols)
		local prize = cols[1]
		for _, c in cols do
			local d, dp = math.abs(c - L.gate), math.abs(prize - L.gate)
			if d > dp then prize = c end -- sorted ascending, so a tie keeps the lower column
		end
		L.cages = {}
		for _, c in cols do
			table.insert(L.cages, { col = c, prize = (c == prize), sp = "" })
		end
	end

	for attempt = 1, maxAttempts do
		local L = blank(cfg, "camp")
		L.seed = seed
		L.tier = tier
		setLines(L, drawLines(cfg, rng, P.lines, P.gaps))
		local band = bandCells(L)
		local chosen = pickK(rng, band, P.rocks + P.snares)
		for i, cell in chosen do
			if i <= P.rocks then
				setRock(L, cell[1], cell[2])
			else
				addTrap(L, { kind = "snare", col = cell[1], row = cell[2] })
			end
		end
		cagesFor(L)
		L.attempts = attempt
		if Layout.row8Reachable(L) then
			built = L
			break
		end
		last = L
	end

	if not built then
		local F = blank(cfg, "camp")
		F.seed = seed
		F.tier = tier
		if last then
			setLines(F, last.lines)
			F.cages = last.cages
		else
			setLines(F, drawLines(cfg, rng, P.lines, P.gaps))
			cagesFor(F)
		end
		F.attempts = maxAttempts
		F.fallback = true
		built = F
	end
	local L = built :: any

	for i, line in L.lines do
		for _, c in pickK(rng, line.cols, P.armed[i]) do
			addTrap(L, { kind = "laser", col = c, row = line.row, on = P.on, off = P.off, phase = 0 })
		end
	end
	for _, t in Layout.traps(L) do
		if t.kind == "laser" then
			t.phase = rng:next() * (t.on + t.off)
		end
	end
	for _, cage in L.cages do
		local want = if cage.prize then tier else math.max(1, tier - 1)
		local list = {}
		for _, s in cfg.Species do
			if s.tier == want then table.insert(list, s.id) end
		end
		cage.sp = list[rng:below(#list)]
	end
	return L
end

-- A stable string for "is this the same layout", used by the determinism checks.
function Layout.signature(L: any): string
	local parts = {}
	for _, line in L.lines do
		table.insert(parts, "l" .. line.row .. ":" .. table.concat(line.cols, ","))
	end
	for _, r in L.rocks do
		table.insert(parts, "r" .. r[1] .. "," .. r[2])
	end
	for _, t in Layout.traps(L) do
		table.insert(parts, string.format("%s%d,%d@%.6f", t.kind, t.col, t.row, t.phase or 0))
	end
	for _, c in L.cages do
		table.insert(parts, "c" .. c.col .. (if c.prize then "*" else "") .. c.sp)
	end
	return table.concat(parts, "|")
end

--============================================================================ traps in a player's lair

function Layout.trapString(kind: string, col: number, row: number): string
	return (if kind == "laser" then "L" else "S") .. ":" .. col .. ":" .. row
end

function Layout.parseTrap(s: any): (string?, number?, number?)
	if type(s) ~= "string" then return nil, nil, nil end
	local k, c, r = string.match(s, "^([LS]):(%d):(%d)$")
	if not k then return nil, nil, nil end
	return (if k == "L" then "laser" else "snare"), tonumber(c), tonumber(r)
end

-- Every refusal names its reason: the server toasts it verbatim (no silent no-ops).
function Layout.validatePlacement(cfg: any, L: any, col: any, row: any, kind: any): (boolean, string?)
	if kind ~= "laser" and kind ~= "snare" then return false, "Unknown trap" end
	if type(col) ~= "number" or type(row) ~= "number" or col % 1 ~= 0 or row % 1 ~= 0
		or col < 1 or col > L.cols or row < 1 or row > L.rows - 1 then
		return false, "Traps go in yard rows 1 to 7"
	end
	local cell = Layout.cellKind(L, col, row)
	if cell == "fence" then return false, "That is a fence" end
	if cell == "rock" then return false, "A rock is in the way" end
	if cell ~= "floor" then return false, "Traps go in yard rows 1 to 7" end
	if col == L.entryCol and row == L.entryRow then return false, "Keep the entrance clear" end
	if Layout.trapAt(L, col, row) then return false, "There is already a trap there" end
	if kind == "laser" and Layout.count(L, "laser") >= cfg.Traps.MaxLasers then
		return false, "Your lair already has " .. cfg.Traps.MaxLasers .. " laser nets"
	end
	if kind == "snare" and Layout.count(L, "snare") >= cfg.Traps.MaxSnares then
		return false, "Your lair already has " .. cfg.Traps.MaxSnares .. " snares"
	end
	if kind == "laser" then
		for _, d in DIRS do
			local n = Layout.trapAt(L, col + d[1], row + d[2])
			if n and n.kind == "laser" then return false, "Lasers need a safe cell between them" end
		end
	end
	if not Layout.reachableFrom(L, L.entryCol, L.entryRow)[key(col, row)] then
		return false, "Nothing can ever walk there"
	end
	if kind == "snare" then
		addTrap(L, { kind = "snare", col = col, row = row })
		local ok = Layout.row8Reachable(L)
		removeTrap(L, col, row)
		if not ok then
			return false, "That would wall off your cages - poachers and raiders must have a way in"
		end
	end
	return true, nil
end

-- Place a trap if the rules allow it. Returns ok, reason, the trap record.
function Layout.place(cfg: any, L: any, col: any, row: any, kind: any): (boolean, string?, any)
	local ok, why = Layout.validatePlacement(cfg, L, col, row, kind)
	if not ok then return false, why, nil end
	local trap: any = { kind = kind, col = col, row = row }
	if kind == "laser" then
		trap.on = cfg.Traps.LairLaserOn
		trap.off = cfg.Traps.LairLaserOff
		trap.phase = 0
	end
	addTrap(L, trap)
	return true, nil, trap
end

-- A cell a trap may ever occupy: integer column 1..cols, integer row 1..rows-1. Every entry point
-- that takes a cell from a client goes through this. REVIEW-1 R1-1: Layout.key(col, row) is
-- (row + 2) * 32 + (col + 2), so (col + 32, row - 1) names the SAME key as (col, row); a "clear" that
-- only checked type(number) refunded a trap through its alias and left the saved string behind,
-- and every rejoin refunded that string again (measured: +10 000 Essence from 40 cycles).
function Layout.isBuildCell(L: any, col: any, row: any): boolean
	return type(col) == "number" and type(row) == "number" and col % 1 == 0 and row % 1 == 0
		and col >= 1 and col <= L.cols and row >= 1 and row <= L.rows - 1
end

-- A carried cryptid is out of the camp only through the GATE. REVIEW-1 R1-5: every row-1 cell's
-- trusted rect reaches 1 stud into the front fence, which cellAt calls row 0, so "row <= 0" let a
-- carrier out of any row-1 cell. The gate cell's trusted rect is its cell plus the wall margin.
function Layout.escaped(cfg: any, x: number, z: number): boolean
	local _, row = Layout.cellAt(cfg, x, z)
	if row > 0 then return false end
	local r = Layout.cellRect(cfg, cfg.World.GateCol, 0)
	local g = cfg.Raid.WallShrinkStuds
	return x >= r.x0 - g and x <= r.x1 + g
end

-- Remove a trap; returns its kind (for the refund) or nil when the cell held none, or is not a cell.
function Layout.clear(L: any, col: number, row: number): string?
	if not Layout.isBuildCell(L, col, row) then return nil end
	local t = removeTrap(L, col, row)
	return t and t.kind or nil
end

-- Replay saved trap strings, in order, through the CURRENT rules. What the rules reject is
-- removed, so a Config change can never leave a lair invalid. Returns the kept strings, the
-- removed ones, and the subset of removed ones that earn a refund: only the FIRST string naming
-- a cell. A second string for a cell can only come from a desync (REVIEW-1 R1-1's alias), and
-- refunding it would pay out for a trap that was never bought twice. Malformed strings name no
-- cell and no price, so they are removed without a refund.
function Layout.reconcile(cfg: any, L: any, saved: { any }): ({ string }, { string }, { string })
	local kept, removed, refundable = {}, {}, {}
	local seen: { [number]: boolean } = {}
	for _, s in saved do
		local kind, col, row = Layout.parseTrap(s)
		if not kind then
			table.insert(removed, tostring(s))
		else
			local k = key(col :: number, row :: number)
			local first = not seen[k]
			seen[k] = true
			if first and Layout.place(cfg, L, col, row, kind) then
				table.insert(kept, s)
			else
				table.insert(removed, s)
				if first then table.insert(refundable, s) end
			end
		end
	end
	return kept, removed, refundable
end

--============================================================================ catch areas and the trusted-position map

-- A trap's danger area. DESIGN.md says "the cell inset by 1 stud"; that is kept towards OPEN
-- floor, where a root 1 stud in means the body is visibly on the trap. Two sides differ, and
-- both close a hole the plain inset leaves:
--   * towards a WALL (fence, rock, cage, void) the area reaches WallShrinkStuds INTO the wall,
--     because the trusted wall test lets a position get that close. A plain inset left a 2-stud
--     lane along each side of a gap laser that a noclipper could walk through untouched.
--   * towards ANOTHER TRAP the area reaches the shared edge, so nobody slips between two.
function Layout.dangerRect(cfg: any, L: any, col: number, row: number): any
	local r = Layout.cellRect(cfg, col, row)
	local inset, shrink = cfg.Raid.TrapInset, cfg.Raid.WallShrinkStuds
	local function side(nc: number, nr: number): number
		if Layout.cellKind(L, nc, nr) ~= "floor" then return -shrink end
		if Layout.trapAt(L, nc, nr) then return 0 end
		return inset
	end
	return {
		x0 = r.x0 + side(col - 1, row),
		x1 = r.x1 - side(col + 1, row),
		z0 = r.z0 + side(col, row - 1),
		z1 = r.z1 - side(col, row + 1),
	}
end

-- The region a trusted position may occupy: every floor cell (rows 0..8) grown by
-- WallShrinkStuds on every side. Growing the floor is the same as shrinking the walls, without
-- the slits that shrinking each wall rectangle separately would open between neighbours.
--
-- The second value is the BARRIERS (REVIEW-1.md A6). Where two wall cells touch only at a corner
-- (a checkerboard 2 x 2 of wall, floor / floor, wall), the two floor cells' grown rects overlap in
-- the 2 x 2-stud square round that corner, and a trusted position walked diagonally through it
-- although the two rock Parts leave 0.57 studs between them (measured on the 2026-09-17 build: a
-- squeeze in 931 / 638 / 681 / 0 of 2 000 camps per tier). No standable point lies in that square
-- (every point of it is within 1 stud of one of the walls), so a segment across the square from one
-- floor cell's side to the other's is a barrier no trusted leg may cross; it reaches 0.1 studs past
-- the square, into the walls, so no leg can round its ends. Only rocks make such corners: a rock is
-- never beside a gap, and a fence line is a full row.
function Layout.freeRects(cfg: any, L: any): ({ any }, { any })
	local out = {}
	local g = cfg.Raid.WallShrinkStuds
	for row = 0, L.rows do
		for col = 1, L.cols do
			if Layout.cellKind(L, col, row) == "floor" then
				local r = Layout.cellRect(cfg, col, row)
				table.insert(out, { x0 = r.x0 - g, x1 = r.x1 + g, z0 = r.z0 - g, z1 = r.z1 + g, col = col, row = row })
			end
		end
	end
	local barriers = {}
	local e = g + 0.1
	local function floor(col: number, row: number): boolean
		return row >= 0 and row <= L.rows and Layout.cellKind(L, col, row) == "floor"
	end
	for row = 0, L.rows - 1 do
		for col = 0, L.cols do
			-- the grid vertex shared by (col, row), (col + 1, row), (col, row + 1), (col + 1, row + 1)
			local vx = cfg.World.CellSize * col
			local vz = cfg.World.ApronDepth + cfg.World.CellSize * (row + 1)
			local a, b = floor(col, row), floor(col + 1, row)
			local c, d = floor(col, row + 1), floor(col + 1, row + 1)
			if a and d and not b and not c then
				-- floor on the rising diagonal: the barrier runs along the falling one
				table.insert(barriers, { ax = vx - e, az = vz + e, bx = vx + e, bz = vz - e, col = col, row = row })
			elseif b and c and not a and not d then
				table.insert(barriers, { ax = vx - e, az = vz - e, bx = vx + e, bz = vz + e, col = col, row = row })
			end
		end
	end
	return out, barriers
end

return Layout
