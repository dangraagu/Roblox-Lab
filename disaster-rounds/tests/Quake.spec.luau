-- Quake: red cracked cells that drop 3 s later; the island breaks but every red cell has a way off
-- (DESIGN.md §2.5). Run: luau tests/Quake.spec.luau
local Quake = require("../src/shared/Quake")
local MapGen = require("../src/shared/MapGen")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local QC = Config.Quake
local IC = Config.Island
local N = IC.Grid
local seed = 4242
local function rand(): number
	seed = (1664525 * seed + 1013904223) % 4294967296
	return seed / 4294967296
end

do
	local times = Quake.batchTimes(Config)
	eq(#times, 9, "nine batches a round")
	eq(times[1], 3, "the first cracks at 3 s")
	eq(times[9], 51, "the last at 51 s ...")
	eq(times[9] + QC.CrackSeconds, 54, "... and drops at 54 s")
	eq(Quake.cap(Config), 76, "never more than 76 of 169 cells (45 %)")
end

--======================================================================= 500 rounds with 1 or 8 players

local shares = {}
local stranded, overBatch, overCap, aloneCracked, dropOk = 0, 0, 0, 0, true
local ownChances, ownCracked = 0, 0
for round = 1, 500 do
	local map = MapGen.generate(IC, rand)
	local levels = map.levels
	local q = Quake.new()
	local players = {}
	for _, c in MapGen.dropCells(IC, levels, if round % 2 == 0 then 8 else 1, rand) do
		table.insert(players, { i = c.i, j = c.j })
	end
	for _, t in Quake.batchTimes(Config) do
		-- whatever cracked last batch has dropped by now
		local dropped = Quake.update(q, t)
		for _, c in dropped do
			if not Quake.isDropped(q, c.i, c.j) then dropOk = false end
		end
		-- the players who stand on intact ground
		local standing = {}
		for _, p in players do
			if not Quake.isDropped(q, p.i, p.j) then table.insert(standing, p) end
		end
		local batch = Quake.pickBatch(Config, levels, q, standing, rand)
		if #batch > QC.BatchMax then overBatch += 1 end
		Quake.crack(q, batch, t, QC.CrackSeconds)
		-- every red cell has a safe neighbour at most one level away
		for _, c in batch do
			if not Quake.hasSafeNeighbour(levels, q, c.i, c.j) then stranded += 1 end
		end
		for _, p in standing do
			ownChances += 1
			if Quake.isCracking(q, p.i, p.j) then
				ownCracked += 1
				-- the player steps to the safe neighbour
				local s = Quake.safeNeighbour(levels, q, p.i, p.j)
				if s then p.i, p.j = s.i, s.j end
			end
		end
		if Quake.brokenCount(q) > Quake.cap(Config) then overCap += 1 end
	end
	Quake.update(q, 60)
	table.insert(shares, Quake.brokenCount(q) / (N * N))
	-- a cell whose neighbours are all gone can never crack
	for i = 1, N do
		for j = 1, N do
			if not Quake.isDropped(q, i, j) and not Quake.hasSafeNeighbour(levels, q, i, j) then
				if Quake.eligible(levels, q, i, j, {}) then aloneCracked += 1 end
			end
		end
	end
end
table.sort(shares)
eq(stranded, 0, "500 rounds: every red cell had a safe neighbour (intact, not red, at most one level away) when it cracked")
eq(overBatch, 0, "no batch is bigger than 10 cells")
eq(overCap, 0, "the island never loses more than 45 %")
eq(aloneCracked, 0, "a cell whose neighbours are all gone is never eligible (an isolated pocket is safe)")
truthy(dropOk, "every cracked cell drops when its 3 s are up")
truthy(shares[250] >= 0.40 and shares[500] <= 0.45 + 1e-9,
	string.format("broken share at round end: p50 %.3f, max %.3f (DESIGN.md: p50 0.45, max 0.45)", shares[250], shares[500]))
local ownShare = ownCracked / math.max(1, ownChances)
truthy(ownShare > 0.45 and ownShare <= 0.75, string.format("it comes for you: a player's own cell cracks in %.2f of batches (60 %% chance, less when ineligible)", ownShare))
print(string.format("  quake: broken share p50 %.3f max %.3f; own cell cracked in %.3f of %d player-batches", shares[250], shares[500], ownShare, ownChances))

--======================================================================= eligibility by hand

do
	local flat = {}
	for i = 1, N do
		flat[i] = {}
		for j = 1, N do flat[i][j] = 1 end
	end
	local q = Quake.new()
	-- a cell whose four neighbours are all cracking cannot be added
	Quake.crack(q, { { i = 6, j = 7 }, { i = 8, j = 7 }, { i = 7, j = 6 }, { i = 7, j = 8 } }, 0, 3)
	eq(Quake.eligible(flat, q, 7, 7, {}), false, "a cell ringed by red cells cannot crack")
	-- adding a cell that would strand an already-chosen cell is refused
	local q2 = Quake.new()
	local chosen = { [MapGen.key(1, 1)] = true }
	-- (1,1)'s neighbours are (2,1) and (1,2); choose (1,2) first, then (2,1) would strand (1,1)
	chosen[MapGen.key(1, 2)] = true
	eq(Quake.eligible(flat, q2, 2, 1, chosen), false, "a crack that would leave a chosen red cell with no way off is refused")
	-- a neighbour under a ring is not a way off either (the ring may land while the player steps onto it)
	local q3 = Quake.new()
	local blocked = { [MapGen.key(6, 7)] = true, [MapGen.key(8, 7)] = true, [MapGen.key(7, 6)] = true, [MapGen.key(7, 8)] = true }
	eq(Quake.eligible(flat, q3, 7, 7, {}, blocked), false, "a cell whose neighbours are all under rings cannot crack")
	eq(Quake.eligible(flat, q3, 7, 7, {}, nil), true, "the same cell with no rings can")
	-- a cliff: a neighbour two levels away is not a way off
	local cliff = {}
	for i = 1, N do
		cliff[i] = {}
		for j = 1, N do cliff[i][j] = 0 end
	end
	cliff[7][7] = 2
	for _, d in MapGen.DIRS do cliff[7 + d[1]][7 + d[2]] = 0 end
	eq(Quake.eligible(cliff, Quake.new(), 7, 7, {}), false, "a cell whose only neighbours are two levels down cannot crack")
end

print(string.format("Quake: %d passed, %d failed", passed, failed))
assert(failed == 0, "Quake tests failed")
