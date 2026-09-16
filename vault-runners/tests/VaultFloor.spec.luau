-- VaultFloor — the vault itself, as exact arithmetic.
-- Run: luau tests/VaultFloor.spec.luau
--
-- VaultFloor.build is PURE: cfg + a spec + the MazeGen and Rng modules in, plain tables out. It
-- touches no Roblox global (not even Vector3), so every invariant below is measured with no
-- engine present — and the server is left owning nothing but Instance.new.
--
-- The maze itself is labyrint-spill's shipped generator, copied verbatim. This file re-skins its
-- output as a STACK of vault storeys: one maze per storey, a hole in the floor above the storey
-- you climb out of, a spiral of steps up through it, and a rising kill plane underneath the lot.
-- Nothing in the generator was edited to make that work, which is the whole point — MazeGen only
-- ever gets asked for a grid, and `Rng:NextInteger` is what lets the CLI ask.
--
-- Structure: every invariant is a NAMED check. The bottom of the file mutates the model and
-- asserts, by name, which check notices — including one CONTROL mutation that no check may
-- notice at all.

local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")
local VaultFloor = require("../src/shared/VaultFloor")
local VaultPath = require("../src/shared/VaultPath")
local MazeGen = require("../src/shared/MazeGen")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want ~", tostring(b))
	end
end

local C = Config
local EPS = 1e-6

--============================================================================ build helpers

local function specFor(tier, floor)
	local d = Progression.difficulty(C, tier, floor)
	d.seed = Progression.seedFor(C, tier, floor)
	return d
end

local function build(tier, floor)
	local spec = specFor(tier, floor)
	return VaultFloor.build(C, spec, MazeGen, Rng), spec
end

local function aabb(p)
	return {
		minX = p.position.x - p.size.x / 2, maxX = p.position.x + p.size.x / 2,
		minY = p.position.y - p.size.y / 2, maxY = p.position.y + p.size.y / 2,
		minZ = p.position.z - p.size.z / 2, maxZ = p.position.z + p.size.z / 2,
	}
end

local function contains(p, x, y, z)
	local b = aabb(p)
	return x > b.minX + EPS and x < b.maxX - EPS
		and z > b.minZ + EPS and z < b.maxZ - EPS
		and (y == nil or (y >= b.minY - EPS and y <= b.maxY + EPS))
end

local function partsOf(m, group, storey)
	local out = {}
	for _, p in ipairs(m.parts) do
		if p.group == group and (storey == nil or p.storey == storey) then out[#out + 1] = p end
	end
	return out
end

-- Fine-grid cell centre in vault-local coordinates. Mirrors MazeGen.gridToWorld with a zero
-- origin, which is the ONE piece of that module's arithmetic this game reimplements — MazeGen's
-- own version returns a Vector3, and Vector3 does not exist in the luau CLI.
local function fineCentre(m, fx, fy)
	return (fx - (m.gCols - 1) / 2) * m.cellSize, (fy - (m.gRows - 1) / 2) * m.cellSize
end

local function cellFine(cx, cy) return 2 * cx + 1, 2 * cy + 1 end

--============================================================================ named checks

-- Each returns (ok, detail). A mutation "kills" a check when the check returns false for the
-- mutated model.
local CHECK = {}

CHECK.everyStoreyHasFloor = function(m)
	for s = 0, m.storeys - 1 do
		if #partsOf(m, "floor", s) == 0 then return false, "storey " .. s .. " has no floor" end
	end
	return true
end

-- The floor slabs of a storey must tile the whole footprint EXCEPT the climb hole: no gap you
-- could fall through, no overlap, and the hole actually open.
CHECK.floorTiling = function(m)
	local S = m.cellSize
	local full = (m.gCols * S) * (m.gRows * S)
	for s = 0, m.storeys - 1 do
		local slabs = partsOf(m, "floor", s)
		local area = 0
		for _, p in ipairs(slabs) do area += p.size.x * p.size.z end
		-- storey 0 stands on solid ground; every storey above it is entered through a hole
		local holeArea = (s == 0) and 0 or (S * S)
		if math.abs(area - (full - holeArea)) > 1e-6 then
			return false, string.format("storey %d floor area %.1f, wanted %.1f", s, area, full - holeArea)
		end
		for i = 1, #slabs do
			for j = i + 1, #slabs do
				local a, b = aabb(slabs[i]), aabb(slabs[j])
				local ox = math.min(a.maxX, b.maxX) - math.max(a.minX, b.minX)
				local oz = math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ)
				if ox > EPS and oz > EPS then
					return false, "storey " .. s .. " floor slabs overlap"
				end
			end
		end
	end
	return true
end

-- THE way up. Storey s+1's floor must be OPEN exactly where storey s's stair arrives, or the
-- vault is a sealed box with gems in it: playable-looking, completely uncompletable.
CHECK.climbHoleOpen = function(m)
	local S = m.cellSize
	for s = 1, m.storeys - 1 do
		local entry = m.entryCells[s + 1]
		local fx, fy = cellFine(entry.cx, entry.cy)
		local cx, cz = fineCentre(m, fx, fy)
		for _, p in ipairs(partsOf(m, "floor", s)) do
			if contains(p, cx, nil, cz) then
				return false, "storey " .. s .. " floor covers its own entry hole"
			end
		end
		-- and the hole must be no wider than the cell, or you fall back down the stairwell
		local open = 0
		for _, dx in ipairs({ -S / 2 - 1, S / 2 + 1 }) do
			local blocked = false
			for _, p in ipairs(partsOf(m, "floor", s)) do
				if contains(p, cx + dx, nil, cz) then blocked = true end
			end
			if not blocked then open += 1 end
		end
		if open > 0 then return false, "storey " .. s .. "'s hole is wider than one cell" end
	end
	return true
end

-- Wall parts are RUN-LENGTH MERGED along X. The merge must cover exactly the generator's wall
-- cells: one wall over every wall cell, and no wall over any open cell.
CHECK.wallsMatchMaze = function(m)
	-- A fine cell's edges sit at (k - (g-1)/2 - 0.5) * cellSize for integer k. Sampling cell
	-- CENTRES alone cannot see a wall that grew half a cell at each end, and the mutation gate
	-- proved it: growing a run's size.x by one cell was not noticed until this ran.
	local function onGrid(v, g)
		local t = v / m.cellSize + (g - 1) / 2 + 0.5
		return math.abs(t - math.floor(t + 0.5)) < 1e-6
	end
	for s = 0, m.storeys - 1 do
		local grid = m.grids[s + 1]
		local walls = partsOf(m, "wall", s)
		for _, p in ipairs(walls) do
			local b = aabb(p)
			if not (onGrid(b.minX, m.gCols) and onGrid(b.maxX, m.gCols)
				and onGrid(b.minZ, m.gRows) and onGrid(b.maxZ, m.gRows)) then
				return false, p.name .. " does not line up with the maze grid"
			end
		end
		for fy = 0, m.gRows - 1 do
			for fx = 0, m.gCols - 1 do
				local cx, cz = fineCentre(m, fx, fy)
				local n = 0
				for _, p in ipairs(walls) do
					if contains(p, cx, nil, cz) then n += 1 end
				end
				if grid[fy][fx] then
					if n ~= 1 then
						return false, string.format("storey %d wall cell (%d,%d) covered %d times", s, fx, fy, n)
					end
				elseif n ~= 0 then
					return false, string.format("storey %d OPEN cell (%d,%d) is walled", s, fx, fy)
				end
			end
		end
	end
	return true
end

-- The outer ring is what stops a runner walking off the vault entirely.
CHECK.perimeterSealed = function(m)
	for s = 0, m.storeys - 1 do
		local walls = partsOf(m, "wall", s)
		local function walled(fx, fy)
			local cx, cz = fineCentre(m, fx, fy)
			for _, p in ipairs(walls) do
				if contains(p, cx, nil, cz) then return true end
			end
			return false
		end
		for fx = 0, m.gCols - 1 do
			if not walled(fx, 0) or not walled(fx, m.gRows - 1) then
				return false, "storey " .. s .. " has a gap in its north/south wall"
			end
		end
		for fy = 0, m.gRows - 1 do
			if not walled(0, fy) or not walled(m.gCols - 1, fy) then
				return false, "storey " .. s .. " has a gap in its east/west wall"
			end
		end
	end
	return true
end

-- Wall tops must meet the underside of the floor above. A gap band is a place a player can see
-- through into the next storey and, on a good jump, land in.
CHECK.wallsMeetCeiling = function(m)
	for s = 0, m.storeys - 2 do
		local walls = partsOf(m, "wall", s)
		local topY = -math.huge
		for _, p in ipairs(walls) do topY = math.max(topY, aabb(p).maxY) end
		local floorBottom = math.huge
		for _, p in ipairs(partsOf(m, "floor", s + 1)) do
			floorBottom = math.min(floorBottom, aabb(p).minY)
		end
		if math.abs(topY - floorBottom) > EPS then
			return false, string.format("storey %d walls top at %.2f, floor above starts at %.2f",
				s, topY, floorBottom)
		end
	end
	return true
end

-- You have to be able to get from the entry of a storey to its exit. The generator is a perfect
-- maze so this is always true of the grid — this check exists because a re-skin can still put a
-- gem, a step or a hole somewhere that changes which cells are actually open.
CHECK.storeysConnected = function(m)
	for s = 0, m.storeys - 1 do
		local grid = m.grids[s + 1]
		local entry, exit = m.entryCells[s + 1], m.exitCells[s + 1]
		local ex, ey = cellFine(entry.cx, entry.cy)
		local tx, ty = cellFine(exit.cx, exit.cy)
		local seen = { [ey * 1000 + ex] = true }
		local stack = { { ex, ey } }
		local found = (ex == tx and ey == ty)
		while #stack > 0 and not found do
			local cur = table.remove(stack)
			for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local nx, ny = cur[1] + d[1], cur[2] + d[2]
				if nx >= 0 and nx < m.gCols and ny >= 0 and ny < m.gRows
					and not grid[ny][nx] and not seen[ny * 1000 + nx] then
					seen[ny * 1000 + nx] = true
					if nx == tx and ny == ty then found = true end
					stack[#stack + 1] = { nx, ny }
				end
			end
		end
		if not found then return false, "storey " .. s .. " exit is walled off from its entry" end
	end
	return true
end

-- Storey s's exit IS storey s+1's entry: you climb where you finished, not somewhere else.
CHECK.stairsLineUp = function(m)
	for s = 0, m.storeys - 2 do
		local exit, entry = m.exitCells[s + 1], m.entryCells[s + 2]
		if exit.cx ~= entry.cx or exit.cy ~= entry.cy then
			return false, "storey " .. s .. " exits somewhere storey " .. (s + 1) .. " does not begin"
		end
		local steps = partsOf(m, "step", s)
		if #steps == 0 then return false, "storey " .. s .. " has no steps up" end
		local fx, fy = cellFine(exit.cx, exit.cy)
		local cx, cz = fineCentre(m, fx, fy)
		local half = m.cellSize / 2
		local lowest, highest = math.huge, -math.huge
		local tops = {}
		for _, p in ipairs(steps) do
			local b = aabb(p)
			if b.minX < cx - half - EPS or b.maxX > cx + half + EPS
				or b.minZ < cz - half - EPS or b.maxZ > cz + half + EPS then
				return false, "a step on storey " .. s .. " sticks out of the stairwell cell"
			end
			lowest = math.min(lowest, b.maxY)
			highest = math.max(highest, b.maxY)
			tops[#tops + 1] = b.maxY
		end
		table.sort(tops)
		local floorY = s * m.storeyHeight
		if math.abs(tops[#tops] - (floorY + m.storeyHeight)) > EPS then
			return false, "the top step on storey " .. s .. " does not reach the floor above"
		end
		local prev = floorY
		for _, t in ipairs(tops) do
			if t - prev > m.stepRise + EPS then
				return false, string.format("storey %d has a %.1f-stud rise between steps", s, t - prev)
			end
			prev = t
		end
	end
	return true
end

-- THE CLIMB HAS TO BE A CLIMB YOU CAN FAIL. REVIEW.md's finding 7, as arithmetic.
--
-- stairsLineUp above proves the shaft REACHES the floor above and that no rise is taller than a
-- jump. Both were true of v1's staircase, and v1's staircase was six 5x5 treads one stud apart in
-- a 12-stud cell: there was no jump in the entire game a player could miss, while the store copy
-- and the thumbnail led with "ROBLOX RAGE OBBY". A vertical check alone cannot see that, because
-- the thing that was missing is HORIZONTAL.
--
-- So, for every consecutive pair of pads in every shaft:
--
--   1. the open air between them is wider than the runner (Movement.RunnerWidth) — otherwise a
--      miss lands on the next pad anyway and the gap is a seam, not a hazard;
--   2. the hop is inside what the jump can actually do — VaultPath.jumpReach solves Roblox's own
--      JumpPower against its own Gravity at the game's own WalkSpeed, so this is the engine's
--      number and not a designer's hope;
--   3. ...and it uses enough of that reach to be a jump rather than a formality;
--   4. the pad is at least as wide as the runner, so there is something to land on.
--
-- (1) and (3) are the two v1 fails. (2) and (4) are what stop the fix overshooting into a vault
-- nobody can climb, which is the same failure mode in the other direction.
local REACH_CEILING = 0.9   -- of the jump's own maximum: past this the hop is pixel-perfect
local REACH_FLOOR = 0.6     -- ...and under this it is a staircase with extra steps
CHECK.climbIsFailable = function(m)
	for s = 0, m.storeys - 2 do
		local pads = partsOf(m, "step", s)
		if #pads < 2 then return false, "storey " .. s .. " has no shaft to climb" end
		table.sort(pads, function(a, b) return a.position.y < b.position.y end)
		for k = 2, #pads do
			local a, b = pads[k - 1], pads[k]
			local dx, dz = b.position.x - a.position.x, b.position.z - a.position.z
			local d = math.sqrt(dx * dx + dz * dz)
			local rise = (b.position.y + b.size.y / 2) - (a.position.y + a.size.y / 2)
			local reach = VaultPath.jumpReach(C, rise)

			if math.min(a.size.x, a.size.z) < C.Movement.RunnerWidth then
				return false, string.format(
					"storey %d pad %d is %.1f studs across, narrower than the %.1f-stud runner",
					s, k - 1, math.min(a.size.x, a.size.z), C.Movement.RunnerWidth)
			end
			if d < 1e-9 then
				return false, string.format("storey %d hop %d is straight up — nothing to miss", s, k)
			end

			-- The free air between the two pads, along the line the runner crosses. For an
			-- axis-aligned box that is the support function in that direction, NOT half the side:
			-- a diagonal hop between two 3x3 pads has 4.2 studs of pad in the way, not 3.
			local ux, uz = dx / d, dz / d
			local extent = (a.size.x / 2) * math.abs(ux) + (a.size.z / 2) * math.abs(uz)
				+ (b.size.x / 2) * math.abs(ux) + (b.size.z / 2) * math.abs(uz)
			local gap = d - extent
			if gap <= C.Movement.RunnerWidth then
				return false, string.format(
					"storey %d hop %d clears only %.1f studs of open air, which a %.1f-stud runner "
						.. "cannot fall through — the hop cannot be missed",
					s, k, gap, C.Movement.RunnerWidth)
			end
			if reach <= 0 or d > REACH_CEILING * reach then
				return false, string.format(
					"storey %d hop %d asks for %.1f studs at a %.1f-stud rise, against a jump that "
						.. "carries %.1f — %.0f%% of the maximum is not a jump, it is a coin flip",
					s, k, d, rise, reach, 100 * d / math.max(reach, 1e-9))
			end
			if d < REACH_FLOOR * reach then
				return false, string.format(
					"storey %d hop %d asks for %.1f studs of a %.1f-stud jump (%.0f%%) — that is a "
						.. "staircase, not an obby",
					s, k, d, reach, 100 * d / reach)
			end
		end
	end
	return true
end

-- The spawn point has to be somewhere a player can actually stand.
CHECK.spawnClear = function(m)
	local sp = m.spawn.position
	for _, p in ipairs(m.parts) do
		if p.collide and contains(p, sp.x, sp.y, sp.z) then
			return false, "the spawn point is inside " .. p.name
		end
	end
	local entry = m.entryCells[1]
	local fx, fy = cellFine(entry.cx, entry.cy)
	local cx, cz = fineCentre(m, fx, fy)
	if math.abs(sp.x - cx) > EPS or math.abs(sp.z - cz) > EPS then
		return false, "the spawn is not on storey 0's entry cell"
	end
	if sp.y <= 0 then return false, "the spawn is not above storey 0's floor" end
	return true
end

-- Gems: in open corridor, never inside a wall, never free on the entry or exit cell, unique ids,
-- and there are as many of them as the difficulty curve promised.
CHECK.gemsPlaced = function(m, spec)
	if #m.gems ~= spec.gemCount then
		return false, string.format("%d gems, curve said %d", #m.gems, spec.gemCount)
	end
	local ids = {}
	for _, g in ipairs(m.gems) do
		if ids[g.id] then return false, "two gems share id " .. tostring(g.id) end
		ids[g.id] = true
		if g.value ~= spec.gemValue then return false, "a gem is worth the wrong amount" end

		local s = g.storey
		if s < 0 or s >= m.storeys then return false, "a gem is on a storey that does not exist" end
		for _, p in ipairs(partsOf(m, "wall", s)) do
			if contains(p, g.position.x, g.position.y, g.position.z) then
				return false, "gem " .. g.id .. " is inside a wall"
			end
		end
		local floorY = s * m.storeyHeight
		if g.position.y <= floorY or g.position.y >= floorY + m.wallHeight then
			return false, "gem " .. g.id .. " is not between its floor and its ceiling"
		end

		for _, key in ipairs({ "entryCells", "exitCells" }) do
			local cell = m[key][s + 1]
			local fx, fy = cellFine(cell.cx, cell.cy)
			local cx, cz = fineCentre(m, fx, fy)
			if math.abs(g.position.x - cx) < EPS and math.abs(g.position.z - cz) < EPS then
				return false, "gem " .. g.id .. " sits on the " .. key .. " cell, free to grab"
			end
		end
	end
	return true
end

-- Gems are spread over the whole tower, not piled on one storey — the climb is the game.
CHECK.gemsPerStorey = function(m, spec)
	local count = {}
	for _, g in ipairs(m.gems) do count[g.storey] = (count[g.storey] or 0) + 1 end
	for s = 0, m.storeys - 1 do
		if (count[s] or 0) ~= spec.gemsPerStorey then
			return false, string.format("storey %d holds %d gems, wanted %d",
				s, count[s] or 0, spec.gemsPerStorey)
		end
	end
	return true
end

-- The exit is on the TOP storey, at that storey's exit cell. An exit anywhere else means the
-- climb is optional, and the whole tower is decoration.
CHECK.exitOnTop = function(m)
	local top = m.storeys - 1
	if m.exit.storey ~= top then return false, "the exit is on storey " .. m.exit.storey end
	local cell = m.exitCells[top + 1]
	local fx, fy = cellFine(cell.cx, cell.cy)
	local cx, cz = fineCentre(m, fx, fy)
	if math.abs(m.exit.position.x - cx) > EPS or math.abs(m.exit.position.z - cz) > EPS then
		return false, "the exit is not on the top storey's exit cell"
	end
	if #partsOf(m, "exitpad", top) == 0 then return false, "the exit has no pad to stand on" end
	return true
end

-- The collapse must sweep the ENTIRE tower — start under storey 0, consume the top storey's
-- floor — and then STOP THERE. Both halves matter:
--   * stopping short leaves a safe shelf and the countdown stops meaning anything;
--   * climbing past the top floor makes the plane kill a runner standing at the exit BEFORE the
--     countdown expires, so the seal never fires in a real run and the game's own name becomes
--     decoration. Below the top storey the collapse is lethal; on the top storey the seal ends
--     it. The two must not race.
CHECK.collapseSweepsVault = function(m)
	local k = m.killPlane
	if k.startY >= 0 then return false, "the collapse starts at or above storey 0's floor" end
	local topFloor = (m.storeys - 1) * m.storeyHeight
	if k.endY < topFloor then return false, "the collapse never reaches the top storey" end
	if k.endY > topFloor + m.killMargin then
		return false, string.format("the collapse ends %.1f studs over the top floor and would "
			.. "kill a runner at the exit before the seal could", k.endY - topFloor)
	end
	if k.size.x < m.gCols * m.cellSize - EPS or k.size.z < m.gRows * m.cellSize - EPS then
		return false, "the collapse is narrower than the vault"
	end
	if m.seal.endY > m.exit.position.y + EPS then return false, "the seal never closes on the exit" end
	if m.seal.startY <= m.seal.endY then return false, "the seal does not descend" end
	return true
end

CHECK.partsSane = function(m)
	if #m.parts == 0 then return false, "the vault has no parts at all" end
	for _, p in ipairs(m.parts) do
		if p.size.x <= 0 or p.size.y <= 0 or p.size.z <= 0 then
			return false, p.name .. " has a non-positive size"
		end
		if type(p.name) ~= "string" or #p.name == 0 then return false, "a part has no name" end
		if p.color == nil or p.material == nil then return false, p.name .. " has no material or colour" end
		if p.castShadow ~= p.collide then
			return false, p.name .. " casts a shadow it does not collide with (or the reverse)"
		end
	end
	return true
end

local ORDER = {
	"everyStoreyHasFloor", "floorTiling", "climbHoleOpen", "wallsMatchMaze", "perimeterSealed",
	"wallsMeetCeiling", "storeysConnected", "stairsLineUp", "climbIsFailable", "spawnClear", "gemsPlaced",
	"gemsPerStorey", "exitOnTop", "collapseSweepsVault", "partsSane",
}

local function runChecks(m, spec, label)
	for _, name in ipairs(ORDER) do
		local ok, detail = CHECK[name](m, spec)
		if ok then passed += 1 else
			failed += 1
			print("FAIL:", label .. " / " .. name, "->", tostring(detail))
		end
	end
end

--============================================================================ the vaults we ship

for tier = 1, 3 do
	for _, floor in ipairs({ 1, 7, 13, 31 }) do
		local m, spec = build(tier, floor)
		runChecks(m, spec, string.format("tier %d floor %d", tier, floor))
	end
end

--============================================================================ determinism

-- Same seed, same vault — the only reason "Bronze floor 7 in 41 seconds" compares to anybody.
local function digest(m)
	local acc = {}
	for _, p in ipairs(m.parts) do
		acc[#acc + 1] = string.format("%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f",
			p.name, p.size.x, p.size.y, p.size.z, p.position.x, p.position.y, p.position.z)
	end
	for _, g in ipairs(m.gems) do
		acc[#acc + 1] = string.format("g%d|%.3f,%.3f,%.3f", g.id, g.position.x, g.position.y, g.position.z)
	end
	return table.concat(acc, ";")
end

do
	local a = build(1, 7)
	local b = build(1, 7)
	eq(digest(a), digest(b), "the same tier and floor build the identical vault, twice")

	local c = build(1, 8)
	truthy(digest(a) ~= digest(c), "the next floor is a different vault")

	local d = build(2, 7)
	truthy(digest(a) ~= digest(d), "the same floor number in another tier is a different vault")
end

do -- and the grid the model reports is the grid the walls were built from
	local m, spec = build(3, 5)
	for s = 0, m.storeys - 1 do
		local rng = Rng.new(VaultFloor.storeySeed(spec, s))
		local grid = MazeGen.generate(spec.cells, spec.cells, rng)
		local same = true
		for fy = 0, m.gRows - 1 do
			for fx = 0, m.gCols - 1 do
				if grid[fy][fx] ~= m.grids[s + 1][fy][fx] then same = false end
			end
		end
		truthy(same, "storey " .. s .. "'s reported grid is the one MazeGen produced for its seed")
	end
end

do -- each storey is its own maze, or a five-storey vault is one maze climbed five times
	local m = build(1, 1)
	local d0, d1 = "", ""
	for fy = 0, m.gRows - 1 do
		for fx = 0, m.gCols - 1 do
			d0 ..= m.grids[1][fy][fx] and "1" or "0"
			d1 ..= m.grids[2][fy][fx] and "1" or "0"
		end
	end
	truthy(d0 ~= d1, "storey 0 and storey 1 are different mazes")
end

--============================================================================ scale

do
	local small = build(1, 1)
	local big = build(3, 31)
	truthy(#big.parts > #small.parts, "a deeper Gold floor is a bigger build than Bronze floor 1")
	truthy(#big.gems > #small.gems, "and holds more gems")

	-- A vault nobody can render is a vault nobody plays. This is a budget, not a law of nature;
	-- if it ever trips, look at the wall merge before raising it.
	--
	-- THE WORST FLOOR IS FOUND, NOT GUESSED. This used to build `build(3, 900)`, call it "the
	-- very worst floor in the game", and print gold floor 31 at 620 parts on the very next line —
	-- larger than the 618 it had just called the maximum. Both floors sit on the Config.Curve
	-- caps, so they are the same SIZE; what differs is the maze, and a run-length-merged wall
	-- count depends on which cells the generator happened to join up. "Floor 900" was never
	-- extremal, only late. README.md and CLAUDE.md both quoted the number as if it were a bound.
	local worstParts, worstAt, sampled = 0, "", 0
	local cappedCounts = {}
	for tier = 1, #C.Tiers do
		for floor = 1, 120 do
			local m, spec = build(tier, floor)
			sampled += 1
			if #m.parts > worstParts then
				worstParts, worstAt = #m.parts, C.Tiers[tier].name .. " floor " .. floor
			end
			if spec.cells == C.Curve.MaxCells and spec.storeys == C.Curve.MaxStoreys then
				cappedCounts[#m.parts] = true
			end
		end
	end
	truthy(worstParts < 1500, string.format(
		"the worst floor found anywhere in %d floors is %s at %d parts, under the 1500 budget",
		sampled, worstAt, worstParts))
	truthy(sampled >= 360, string.format(
		"the budget was measured over %d floors — a sweep, not a sample", sampled))

	-- WHY THE SWEEP IS NOT OPTIONAL, as an assertion rather than a comment. Two floors that are
	-- both pinned to the Config.Curve caps are the same SIZE and still produce different part
	-- counts, because the walls are run-length merged along X and the merge depends on which
	-- cells that floor's maze happened to join up. If this ever reports one distinct count, the
	-- generator has stopped varying and the sweep above could safely become a sample again —
	-- until then, any single "the worst floor in the game is N parts" claim is a guess.
	local distinct = 0
	for _ in pairs(cappedCounts) do distinct += 1 end
	truthy(distinct > 1, string.format(
		"floors at the caps produce %d distinct part counts, so one sample cannot be the maximum",
		distinct))
	print(string.format("  parts: bronze f1 = %d, gold f31 = %d, worst of 360 floors = %d (%s)",
		#small.parts, #big.parts, worstParts, worstAt))
end

--============================================================================ mutation gate

-- Every check above is only worth what it catches. Break the model on purpose and name the check
-- that must notice. (Cavern.spec in grow-a-crystal is the template; the lesson it encodes is that
-- a geometry suite that has never been shown a broken model proves nothing.)

local function clone(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = clone(x) end
	return out
end

local function mutate(fn)
	local m, spec = build(1, 7)
	local copy = clone(m)
	fn(copy, spec)
	return copy, spec
end

local function byName(m, n)
	for _, p in ipairs(m.parts) do if p.name == n then return p end end
	return nil
end

-- killed(check, why, mutation): apply the mutation, then assert the NAMED check notices.
-- The mutation function is the LAST argument on purpose — a `mutate(fn)` call followed by
-- another argument would be truncated to its first return value by Lua's call semantics, and
-- the spec table would silently arrive as a string.
local function killed(name, why, fn)
	local m, spec = mutate(fn)
	local ok, detail = CHECK[name](m, spec)
	if not ok then
		passed += 1
		local _ = detail
	else
		failed += 1
		print("FAIL: check '" .. name .. "' did NOT notice: " .. why)
	end
end

killed("climbHoleOpen", "storey 1's floor was rebuilt as one solid slab", function(m)
	-- The bug this whole check exists for. The vault looks perfect and cannot be climbed.
	local S, keep = m.cellSize, {}
	for _, p in ipairs(m.parts) do
		if not (p.group == "floor" and p.storey == 1) then keep[#keep + 1] = p end
	end
	keep[#keep + 1] = {
		name = "Floor_1_solid", group = "floor", storey = 1,
		size = { x = m.gCols * S, y = 2, z = m.gRows * S },
		position = { x = 0, y = m.storeyHeight - 1, z = 0 },
		orientation = { x = 0, y = 0, z = 0 }, material = "Slate",
		color = { r = 1, g = 1, b = 1 }, transparency = 0, reflectance = 0,
		collide = true, query = true, castShadow = true,
	}
	m.parts = keep
end)

killed("wallsMatchMaze", "a wall run grew one cell longer than the maze says", function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "wall" then p.size.x += m.cellSize; break end
	end
end)

killed("perimeterSealed", "a chunk of the outer wall was deleted", function(m)
	for i, p in ipairs(m.parts) do
		if p.group == "wall" and p.storey == 0
			and math.abs(p.position.z + (m.gRows - 1) / 2 * m.cellSize) < 1e-6 then
			table.remove(m.parts, i); break
		end
	end
end)

killed("wallsMeetCeiling", "storey 0's walls were shortened, opening a band under the ceiling", function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "wall" and p.storey == 0 then p.size.y -= 3; p.position.y -= 1.5 end
	end
end)

killed("storeysConnected", "storey 0's entry cell was bricked in", function(m)
	local entry = m.entryCells[1]
	local fx, fy = 2 * entry.cx + 1, 2 * entry.cy + 1
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		m.grids[1][fy + d[2]][fx + d[1]] = true
	end
end)

killed("stairsLineUp", "a step was dropped out of the ladder, leaving a rise nobody can jump", function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "step" and p.storey == 0 then p.position.y -= 5; break end
	end
end)

-- FINDING 7, AS A MUTATION. Put v1's staircase back — five-stud treads at a six-stud reach —
-- and the check that must notice is the new one, not stairsLineUp: the rises are untouched, the
-- top pad still meets the floor above, every pad is still inside the stairwell cell. That is
-- exactly why the vault shipped with no jump in it that anybody could miss.
killed("climbIsFailable", "the shaft was packed back into v1's unmissable staircase", function(m)
	local S = m.cellSize
	local OFF = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
	for _, p in ipairs(m.parts) do
		if p.group == "step" then
			local k = tonumber(string.match(p.name, "_(%d+)$"))
			local o = OFF[((k - 1) % 4) + 1]
			local cx = m.shafts[p.storey + 1].x
			local cz = m.shafts[p.storey + 1].z
			p.size.x, p.size.z = 5, 5
			p.position.x, p.position.z = cx + o[1] * S / 4, cz + o[2] * S / 4
		end
	end
end)

-- ...and the other direction. A shaft nobody can climb is the same defect with the sign flipped,
-- and a check that only ever refused "too easy" would wave this through.
killed("climbIsFailable", "the pads were flung to opposite corners of a jump nobody can make", function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "step" then
			local k = tonumber(string.match(p.name, "_(%d+)$"))
			local sh = m.shafts[p.storey + 1]
			local sign = (k % 2 == 0) and 1 or -1
			p.position.x = sh.x + sign * 5.5
			p.position.z = sh.z + sign * 5.5
		end
	end
end)

killed("spawnClear", "the spawn was moved under the floor", function(m)
	m.spawn.position.y = -20
end)

killed("gemsPlaced", "a gem was dropped on the spawn cell where it costs nothing to take", function(m)
	local entry = m.entryCells[1]
	local cx = (2 * entry.cx + 1 - (m.gCols - 1) / 2) * m.cellSize
	local cz = (2 * entry.cy + 1 - (m.gRows - 1) / 2) * m.cellSize
	m.gems[1].storey = 0
	m.gems[1].position = { x = cx, y = 3, z = cz }
end)

killed("gemsPlaced", "a gem was buried inside a wall", function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "wall" and p.storey == m.gems[1].storey then
			m.gems[1].position = { x = p.position.x, y = p.position.y, z = p.position.z }
			break
		end
	end
end)

killed("gemsPerStorey", "every gem was piled onto storey 0", function(m)
	for _, g in ipairs(m.gems) do g.storey = 0 end
end)

killed("exitOnTop", "the exit was moved to the ground floor", function(m)
	m.exit.storey = 0
end)

killed("collapseSweepsVault", "the collapse was capped below the top storey", function(m)
	m.killPlane.endY = 1
end)

killed("collapseSweepsVault", "the collapse was raised over the exit, racing the seal", function(m)
	m.killPlane.endY = (m.storeys - 1) * m.storeyHeight + 20
end)

killed("collapseSweepsVault", "the seal was made to rise instead of close", function(m)
	m.seal.endY = m.seal.startY + 1
end)

killed("partsSane", "a part was flattened to nothing", function(m)
	m.parts[1].size.y = 0
end)

killed("floorTiling", "a quarter of storey 2's floor was deleted, leaving a hole to fall through", function(m)
	for i, p in ipairs(m.parts) do
		if p.group == "floor" and p.storey == 2 then table.remove(m.parts, i); break end
	end
end)

killed("everyStoreyHasFloor", "storey 2 lost its floor entirely", function(m)
	local keep = {}
	for _, p in ipairs(m.parts) do
		if not (p.group == "floor" and p.storey == 2) then keep[#keep + 1] = p end
	end
	m.parts = keep
end)

--============================================================================ CONTROL

-- A change every check must IGNORE. Colour and material are art direction; the vault's geometry,
-- its gems and its collapse are not allowed to depend on them. Without this line a suite that
-- reported "14/14 mutations killed" could simply be a suite that fails on any input at all.
do
	local m, spec = mutate(function(mm)
		for _, p in ipairs(mm.parts) do
			p.color = { r = 255, g = 0, b = 255 }
			p.transparency = 0.5
			p.reflectance = 0.9
		end
		for _, g in ipairs(mm.gems) do
			g.color = { r = 0, g = 0, b = 0 }
		end
	end)
	local noticed = {}
	for _, name in ipairs(ORDER) do
		local ok = CHECK[name](m, spec)
		if not ok then noticed[#noticed + 1] = name end
	end
	eq(#noticed, 0, "CONTROL: repainting every part in the vault breaks no check ("
		.. table.concat(noticed, ", ") .. ")")
end

do
	-- Second control, on the other side: deleting a line the sweep above cannot kill. Renaming
	-- every part is invisible to geometry — but it WOULD break the server's own lookups, which is
	-- why this is a control here and an assertion in check_vaultrunners.luau instead.
	local m, spec = mutate(function(mm)
		for i, p in ipairs(mm.parts) do p.name = "Part_" .. i end
	end)
	local noticed = 0
	for _, name in ipairs(ORDER) do
		if not CHECK[name](m, spec) then noticed += 1 end
	end
	eq(noticed, 0, "CONTROL: renaming every part breaks no geometry check")
end

print(string.format("VaultFloor: %d passed, %d failed", passed, failed))
if failed > 0 then error("VaultFloor tests failed", 0) end
