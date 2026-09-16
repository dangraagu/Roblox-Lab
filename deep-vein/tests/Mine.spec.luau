-- Rene tester for Mine. Kjør: luau tests/Mine.spec.luau
--
-- Mine is the one genuinely new mechanic in this game, and it is a GRID OF PARTS rather than
-- voxel Terrain for exactly this reason: a grid can be asked "what is at this cell and what
-- does breaking it yield" as a pure function, with no engine in the room. Terrain can only be
-- asked at runtime, by an engine the luau CLI does not have, so a Terrain cave would ship
-- untested by construction.
--
-- What is asserted here, roughly in order:
--   1. the hash is a real hash (deterministic, uniform, uncorrelated between neighbours)
--   2. the noise is coherent (neighbours are CLOSE, which is what makes caves and not speckle)
--   3. the shaft is a sealed box: bedrock ring, bedrock floor, open only at the mouth
--   4. the cave is a CAVE: a defensible fraction of it is void, and no single void is so large
--      that breaking into it would spawn an unbounded number of parts at once
--   5. reveal() exposes exactly the faces a player could see and nothing they could not
--   6. a CONTROL: cosmetic config must not move a single cell

local Mine = require("../src/shared/Mine")
local Ore = require("../src/shared/Ore")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function near(a, b, msg, tol)
	tol = tol or 1e-9
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want ~", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function inRange(v, lo, hi, msg)
	if type(v) == "number" and v >= lo and v <= hi then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(v), "want in [" .. lo .. ", " .. hi .. "]")
	end
end

local M = Config.Mine
local W = M.GridW
local w0 = Mine.world(Config, 0)

--============================================================================ 1. the hash

eq(Mine.maxLayer(Config, 0), 24, "the depth wall at rebirth 0")
eq(Mine.maxLayer(Config, 3), 24 + 36, "each rebirth moves the wall 12 layers deeper")
eq(w0.maxLayer, 24, "the world descriptor carries the wall")
truthy(Mine.seedFor(Config, 0) ~= Mine.seedFor(Config, 1), "a rebirth is a different cave seed")
eq(Mine.seedFor(Config, 0), Mine.seedFor(Config, 0), "the same rebirth is the same seed, always")

do
	-- Determinism first: everything below is worthless if the same cell can answer twice.
	local a = Mine.unit(w0.seed, 3, 7, 5, 11)
	local b = Mine.unit(w0.seed, 3, 7, 5, 11)
	eq(a, b, "the same cell hashes to the same number")
	truthy(Mine.unit(w0.seed, 3, 7, 5, 11) ~= Mine.unit(w0.seed, 3, 7, 5, 12),
		"a different salt is a different stream")
	truthy(Mine.unit(w0.seed, 3, 7, 5, 11) ~= Mine.unit(w0.seed, 4, 7, 5, 11),
		"a neighbouring cell is a different number")
	truthy(Mine.unit(w0.seed, 0, 0, 0, 0) ~= Mine.unit(w0.seed + 1, 0, 0, 0, 0),
		"a different seed is a different cave")
end

do
	-- Range and uniformity. An LCG stream would be wrong here: cell contents must not depend on
	-- the ORDER cells are generated in, because a player uncovers them in whatever order they
	-- dig. So this is a stateless mixer, and a stateless mixer has to be checked for bias.
	local BUCKETS, N = 10, 24000
	local hist = table.create(BUCKETS, 0)
	local outOfRange = 0
	local i = 0
	for x = 1, 30 do
		for y = 1, 40 do
			for z = 1, 20 do
				i += 1
				if i > N then break end
				local u = Mine.unit(w0.seed, x, y, z, 5)
				if u < 0 or u >= 1 then outOfRange += 1 end
				local b = math.min(BUCKETS, 1 + math.floor(u * BUCKETS))
				hist[b] += 1
			end
		end
	end
	eq(outOfRange, 0, "every hash lands in [0, 1)")
	local expected = i / BUCKETS
	local worst = 0
	for b = 1, BUCKETS do
		worst = math.max(worst, math.abs(hist[b] - expected) / expected)
	end
	truthy(worst < 0.08, string.format("the hash is flat across 10 buckets (worst bucket off by %.1f%%)", worst * 100))

	-- Independence between neighbouring cells. For two independent uniforms E|a-b| = 1/3; a
	-- hash that leaks its input (say, low bits of x) collapses this toward 0.
	local sum, n = 0, 0
	for x = 1, 40 do
		for y = 1, 40 do
			sum += math.abs(Mine.unit(w0.seed, x, y, 3, 5) - Mine.unit(w0.seed, x + 1, y, 3, 5))
			n += 1
		end
	end
	inRange(sum / n, 0.28, 0.39, "neighbouring cells are uncorrelated (mean |a-b| ~ 1/3)")
end

--============================================================================ 2. the noise

do
	local nBad, nRough, samples = 0, 0, 0
	local maxJump = 0
	for x = 0, 20 do
		for y = 0, 20 do
			local a = Mine.noise(w0.seed, x / 3, y / 3, 1.5, 7)
			local b = Mine.noise(w0.seed, (x + 1) / 3, y / 3, 1.5, 7)
			if a < 0 or a >= 1 then nBad += 1 end
			local jump = math.abs(a - b)
			maxJump = math.max(maxJump, jump)
			if jump > 0.5 then nRough += 1 end
			samples += 1
		end
	end
	eq(nBad, 0, "noise stays in [0, 1)")
	-- Coherence is the whole point. White noise would put ~11% of adjacent pairs over 0.5 apart;
	-- a value-noise field sampled every 1/3 of a lattice cell must be far smoother than that.
	eq(nRough, 0, string.format("the noise field is coherent, not speckle (largest step %.3f)", maxJump))
	eq(Mine.noise(w0.seed, 2, 3, 4, 7), Mine.noise(w0.seed, 2, 3, 4, 7), "noise is deterministic")
end

--============================================================================ 3. a sealed box

do
	local ringBad, floorBad, mouthBad, topBad, outsideBad = 0, 0, 0, 0, 0
	for y = 0, w0.maxLayer + 1 do
		for x = 1, W do
			for z = 1, W do
				local ring = (x == 1 or x == W or z == 1 or z == W)
				local k = Mine.kindAt(Config, w0, x, y, z)
				if ring and k ~= "bedrock" then ringBad += 1 end
				if not ring then
					if y == w0.maxLayer + 1 and k ~= "bedrock" then floorBad += 1 end
					if y == 0 and k ~= "air" then mouthBad += 1 end
					if y >= 1 and y <= M.SolidTopLayers and k ~= "rock" then topBad += 1 end
				end
			end
		end
	end
	eq(ringBad, 0, "the bedrock ring seals the shaft on all four sides, at every layer")
	eq(floorBad, 0, "the layer below the depth wall is solid bedrock — that IS the wall")
	eq(mouthBad, 0, "layer 0 is the open mouth you drop into")
	eq(topBad, 0, "layer 1 is always rock, so a new player always lands on a floor")

	for _, c in { { 0, 5, 5 }, { W + 1, 5, 5 }, { 5, 5, 0 }, { 5, 5, W + 1 }, { 5, -1, 5 }, { 5, w0.maxLayer + 2, 5 } } do
		if Mine.inWorld(Config, w0, c[1], c[2], c[3]) then outsideBad += 1 end
	end
	eq(outsideBad, 0, "nothing outside the box is part of the world")
	truthy(Mine.inWorld(Config, w0, 5, 0, 5), "the centre of the mouth is in the world")
	truthy(Mine.inWorld(Config, w0, 1, 0, 1), "the ring is in the world (it has to be built)")
	truthy(Mine.inWorld(Config, w0, 5, w0.maxLayer + 1, 5), "so is the bedrock floor")
	eq(Mine.kindAt(Config, w0, 5, 99, 5), "void", "a cell outside the world is void, not air")
	truthy(Mine.isSolid(Config, w0, 5, 99, 5), "and void is never something you can walk into")
end

--============================================================================ 4. it is a cave

local function interiorStats(w, fromY, toY)
	local air, total = 0, 0
	for y = fromY, toY do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				total += 1
				if Mine.kindAt(Config, w, x, y, z) == "air" then air += 1 end
			end
		end
	end
	return air / total, total
end

do
	local frac = interiorStats(w0, 2, w0.maxLayer)
	print(string.format("  air fraction, layers 2-%d: %.3f", w0.maxLayer, frac))
	-- The design requirement, not a measurement written down after the fact: below 0.12 the
	-- shaft is a solid block with no caves worth finding, above 0.35 it stops being rock you
	-- have to dig through. AirThreshold in Config is tuned until this holds.
	inRange(frac, 0.12, 0.35, "the interior is a cave: part void, mostly rock")

	for _, band in { { 2, 8 }, { 9, 16 }, { 17, 24 } } do
		local f = interiorStats(w0, band[1], band[2])
		inRange(f, 0.06, 0.45, string.format("layers %d-%d are a cave too", band[1], band[2]))
	end
end

do
	-- A different rebirth must be a genuinely different cave, or "regenerates a fresh seed" is
	-- a line in the description that the code does not do.
	local w1 = Mine.world(Config, 1)
	local diff, total = 0, 0
	for y = 2, 24 do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				total += 1
				if Mine.kindAt(Config, w0, x, y, z) ~= Mine.kindAt(Config, w1, x, y, z) then diff += 1 end
			end
		end
	end
	local ratio = diff / total
	print(string.format("  rebirth 0 vs 1 differ in %.1f%% of cells", ratio * 100))
	truthy(ratio > 0.12, "a rebirth really does regenerate the cave")
end

do
	-- The bound that keeps one pickaxe swing from spawning an unbounded number of Parts: no
	-- connected void inside the shaft may be bigger than RevealBudget, or reveal() truncates
	-- and leaves a hole in the world with nothing behind it.
	local visited = {}
	local biggest = 0
	local function key(x, y, z) return x .. ":" .. y .. ":" .. z end
	for y = 0, w0.maxLayer do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				local k = key(x, y, z)
				if not visited[k] and Mine.kindAt(Config, w0, x, y, z) == "air" then
					local n = 0
					local q = { { x, y, z } }
					visited[k] = true
					local head = 1
					while head <= #q do
						local c = q[head]; head += 1
						n += 1
						for _, d in { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } } do
							local nx, ny, nz = c[1] + d[1], c[2] + d[2], c[3] + d[3]
							local nk = key(nx, ny, nz)
							if not visited[nk] and Mine.inWorld(Config, w0, nx, ny, nz)
								and Mine.kindAt(Config, w0, nx, ny, nz) == "air" then
								visited[nk] = true
								q[#q + 1] = { nx, ny, nz }
							end
						end
					end
					biggest = math.max(biggest, n)
				end
			end
		end
	end
	print(string.format("  largest connected void: %d cells (budget %d)", biggest, M.RevealBudget))
	truthy(biggest <= M.RevealBudget, "no void is larger than one reveal may flood through")
end

do
	-- CENSUS OF THE SHAFT A NEW PLAYER ACTUALLY GETS. Ore.spec proves the weight table lets each
	-- tier spawn above the depth wall; this proves the cave built from it CONTAINS some. A tier
	-- can be legal and still absent — the rebirth-0 shaft is only 24 layers of a 9x9 grid, so a
	-- tier that only becomes likely below the wall is a tier a pre-rebirth player will hunt for,
	-- fail to find, and conclude is broken. Obsidian shipped at exactly zero cells.
	local counts = { [0] = 0, 0, 0, 0, 0, 0 }
	local rock = 0
	for y = 1, w0.maxLayer do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				local c = Mine.cell(Config, Ore, w0, x, y, z)
				if c.kind == "rock" then
					rock += 1
					counts[c.ore] += 1
				end
			end
		end
	end
	local line = ""
	for t = 0, Config.MaxOre do line ..= " " .. Ore.name(Config, t) .. "=" .. counts[t] end
	print(string.format("  rebirth-0 shaft: %d rock cells;%s", rock, line))
	-- The bar is 10, not 3. At 3 the census is one tuning nudge from red — the shipped table
	-- produced exactly 4 obsidian cells against a floor of 3, which is a margin of one cell in a
	-- 7x7x24 box. A tier a player can only find by luck is a tier they will conclude is broken.
	for t = 1, Config.MaxOre do
		truthy(counts[t] >= 10, Ore.name(Config, t) .. " occurs often enough in the rebirth-0 shaft"
			.. " to be findable (" .. counts[t] .. " cells in " .. rock .. " rock, floor 10)")
	end
	-- CONTROL: the census can tell tiers apart, so "every tier >= 10" cannot pass by counting
	-- everything as one tier.
	truthy(counts[1] > counts[5], "CONTROL: the census still ranks common above rare")
	truthy(counts[0] > 0, "CONTROL: plain stone is still the bulk of the shaft")

	-- AND NO HANDFUL OF CELLS MAY BE THE SHAFT. 46% of the rebirth-0 shaft's value was once four
	-- obsidian cells, which makes the first rebirth "find 3 of 4 needles in a 7x7x24 box" rather
	-- than "mine your cave" — and makes the balance figure the whole ladder rests on a lottery.
	local values = {}
	local total = 0
	for y = 1, w0.maxLayer do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				local c = Mine.cell(Config, Ore, w0, x, y, z)
				if c.kind == "rock" then
					local v = Ore.value(Config, c.ore) * Ore.yieldOf(Config, c.ore)
					total += v
					if v > 0 then values[#values + 1] = v end
				end
			end
		end
	end
	table.sort(values, function(a, b) return a > b end)
	local top4 = 0
	for i = 1, math.min(4, #values) do top4 += values[i] end
	local share = top4 / math.max(1, total)
	print(string.format("  rebirth-0 shaft value: %d, richest 4 cells %d (%.1f%%)", total, top4, 100 * share))
	truthy(share <= 0.25, "no four cells hold more than a quarter of the rebirth-0 shaft's value ("
		.. string.format("%.1f%%", 100 * share) .. " of $" .. total .. ")")
	-- CONTROL: the same measurement DOES notice a lottery shaft.
	do
		local spike = table.clone(Config)
		spike.Ores = table.clone(Config.Ores)
		spike.Ores.Value = { [0] = 0, 0, 0, 0, 0, Config.Ores.Value[5] }
		local sv, st = {}, 0
		for y = 1, w0.maxLayer do
			for x = 2, W - 1 do
				for z = 2, W - 1 do
					local c = Mine.cell(spike, Ore, w0, x, y, z)
					if c.kind == "rock" then
						local v = Ore.value(spike, c.ore) * Ore.yieldOf(spike, c.ore)
						st += v
						if v > 0 then sv[#sv + 1] = v end
					end
				end
			end
		end
		table.sort(sv, function(a, b) return a > b end)
		local s4 = 0
		for i = 1, math.min(4, #sv) do s4 += sv[i] end
		truthy(s4 / math.max(1, st) > 0.25,
			"CONTROL: a shaft whose whole value is one rare tier IS caught by that measurement")
	end
end

--=================================================== 4b. DEEPER MUST NEVER PAY LESS PER SWING

-- THE ONE PROMISE THE WHOLE REBIRTH LADDER RESTS ON. A rebirth buys a deeper wall, and a deeper
-- wall is only a reward if the rock down there pays better. Block hit points grew by
-- HardnessPerLayer FOR EVER while the ore weights clamp at MaxWeight a few dozen layers down, so
-- past that point every extra layer was strictly worse: measured on the shipped numbers, the
-- expected ore value per hit point peaked at 1.2065 on layer 40 and fell to 0.3085 by layer 312,
-- a 3.9x DECLINE across exactly the range the last twenty rebirths open up. README and CLAUDE.md
-- both claimed the opposite ("deeper always pays more per swing") and nothing measured it.
do
	local function perHp(y: number): number
		local ev, ehp, acc = 0, 0, 0
		for t = Config.MaxOre, 1, -1 do
			local wt = Ore.weight(Config, t, y)
			acc += wt
			ev += wt * Ore.value(Config, t) * Ore.yieldOf(Config, t)
			ehp += wt * Mine.hardnessAt(Config, Ore, t, y)
		end
		ehp += (1 - acc) * Mine.hardnessAt(Config, Ore, 0, y)
		return ev / ehp
	end

	local deepest = Mine.maxLayer(Config, Config.Prestige.MaxRebirths - 1)
	local run, worst, worstAt = 0, math.huge, -1
	for y = 1, deepest do
		local v = perHp(y)
		if v > run then run = v end
		if v / run < worst then worst, worstAt = v / run, y end
	end
	print(string.format("  reward gradient: worst layer pays %.1f%% of the best layer above it (layer %d);"
		.. " layer 1 %.4f, layer %d %.4f", 100 * worst, worstAt, perHp(1), deepest, perHp(deepest)))
	-- 0.85 rather than 1.0 because hardness is floored to whole hit points, which makes a small
	-- sawtooth inside each depth band; what must never happen is a sustained DECLINE.
	truthy(worst >= 0.85, "no layer pays less than 85% of the best layer above it (worst "
		.. string.format("%.3f", worst) .. " at layer " .. worstAt .. ")")
	truthy(perHp(deepest) >= 0.95 * run,
		"the deepest layer in the game still pays within 5% of the best layer anywhere ("
			.. string.format("%.4f vs a best of %.4f", perHp(deepest), run) .. ")")
	truthy(perHp(deepest) > perHp(1) * 4,
		"…and far better than the surface (" .. string.format("%.4f vs %.4f", perHp(deepest), perHp(1)) .. ")")

	-- CONTROL: the measurement must be able to FAIL. An unbounded hardness ramp is exactly the
	-- defect it exists to catch.
	do
		local runaway = table.clone(Config)
		runaway.Mine = table.clone(Config.Mine)
		runaway.Mine.HardnessCapLayer = math.huge
		local function perHp2(y: number): number
			local ev, ehp, acc = 0, 0, 0
			for t = runaway.MaxOre, 1, -1 do
				local wt = Ore.weight(runaway, t, y)
				acc += wt
				ev += wt * Ore.value(runaway, t) * Ore.yieldOf(runaway, t)
				ehp += wt * Mine.hardnessAt(runaway, Ore, t, y)
			end
			ehp += (1 - acc) * Mine.hardnessAt(runaway, Ore, 0, y)
			return ev / ehp
		end
		local r2, w2 = 0, math.huge
		for y = 1, deepest do
			local v = perHp2(y)
			if v > r2 then r2 = v end
			if v / r2 < w2 then w2 = v / r2 end
		end
		truthy(w2 < 0.85, "CONTROL: an uncapped hardness ramp IS caught by that measurement ("
			.. string.format("%.3f", w2) .. ")")
	end
end

--============================================================================ 5. cells and yields

do
	local c = Mine.cell(Config, Ore, w0, 5, 1, 5)
	eq(c.kind, "rock", "layer 1 centre is rock")
	truthy(c.breakable, "rock is breakable")
	truthy(c.hp >= 1, "a rock block has hit points")
	eq(c.x, 5, "a cell knows where it is (x)"); eq(c.y, 1, "…(y)"); eq(c.z, 5, "…(z)")

	local b = Mine.cell(Config, Ore, w0, 1, 4, 5)
	eq(b.kind, "bedrock", "the ring is bedrock")
	truthy(not b.breakable, "bedrock is not breakable")
	eq(b.ore, 0, "bedrock holds no ore")
	eq(b.hp, 0, "bedrock has no hit points to grind down")

	local a = Mine.cell(Config, Ore, w0, 5, 0, 5)
	eq(a.kind, "air", "the mouth is air")
	truthy(not a.breakable, "you cannot mine air")

	-- Depth makes a block harder. Same ore, deeper layer, more hit points.
	local shallow = Mine.hardnessAt(Config, Ore, 0, 1)
	local deep = Mine.hardnessAt(Config, Ore, 0, 24)
	truthy(deep > shallow, "the same stone is harder deeper down (" .. shallow .. " -> " .. deep .. ")")
	eq(Mine.hardnessAt(Config, Ore, 0, 0), 10, "stone at layer 0 is its base hardness")
	eq(Mine.hardnessAt(Config, Ore, 5, 0), 165, "obsidian at layer 0 is its base hardness")
	truthy(Mine.hardnessAt(Config, Ore, 0, 200) >= 1, "hardness never collapses to zero")

	-- And the ore in a rock cell is exactly what Ore.tierAt says for that cell's own roll:
	-- the two modules must agree, or the depth gating is decorative.
	local mismatch, oreFound = 0, 0
	for y = 1, 30 do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				local cell = Mine.cell(Config, Ore, w0, x, y, z)
				if cell.kind == "rock" then
					local want = Ore.tierAt(Config, y, Mine.oreRoll(Config, w0, x, y, z))
					if cell.ore ~= want then mismatch += 1 end
					if cell.ore > 0 then oreFound += 1 end
					if cell.ore > 0 and y < Config.Ores.MinLayer[cell.ore] then mismatch += 1 end
				end
			end
		end
	end
	eq(mismatch, 0, "every rock cell holds exactly the ore its own roll says, and never above its MinLayer")
	truthy(oreFound > 100, "there is actually ore in the shaft (" .. oreFound .. " veins in the first 30 layers)")
end

--============================================================================ 6. geometry mapping

do
	eq(Mine.center(Config), 5, "the centre column of a 9-wide grid")
	local p = Mine.localPos(Config, 5, 1, 5)
	near(p.x, 0, "the centre column sits on the shaft's x axis")
	near(p.z, 0, "…and on its z axis")
	near(p.y, -3, "layer 1's centre is 3 studs below the surface (a 6-stud cell)")
	near(Mine.localPos(Config, 5, 0, 5).y, 3, "layer 0 sits above the surface line")
	near(Mine.localPos(Config, 6, 1, 5).x, 6, "one cell across is one CellSize across")
	eq(Mine.depthStuds(Config, 0), 0, "the surface is zero depth")
	eq(Mine.depthStuds(Config, 24), 144, "layer 24 is 144 studs down")
	near(Mine.floorY(Config, 3), -18, "standing in cell 3 means standing on the top of cell 4")
end

--============================================================================ 7. reveal

local function keysOf(list)
	local out = {}
	for _, c in list do out[c.key or Mine.key(c.x, c.y, c.z)] = c end
	return out
end

do
	-- The opening move: the server opens the mouth and asks what a player standing in it can see.
	local opened = {}
	local r = Mine.reveal(Config, Ore, w0, opened, 5, 0, 5)
	truthy(not r.truncated, "opening the mouth does not exhaust the reveal budget")
	eq(#r.air, 48, "the mouth is 7x7 cells and the start cell is not re-reported")

	local solids = keysOf(r.solids)
	local nSolid = #r.solids
	truthy(nSolid > 0, "the mouth exposes rock faces")
	-- Every cell reported as solid IS solid and IS in the world; every cell reported as air is
	-- neither. This is the invariant the server leans on when it turns these into Parts.
	local bad = 0
	for _, c in r.solids do
		if not Mine.isSolid(Config, w0, c.x, c.y, c.z) then bad += 1 end
		if not Mine.inWorld(Config, w0, c.x, c.y, c.z) then bad += 1 end
	end
	for _, c in r.air do
		if Mine.isSolid(Config, w0, c.x, c.y, c.z) then bad += 1 end
		if not Mine.inWorld(Config, w0, c.x, c.y, c.z) then bad += 1 end
	end
	eq(bad, 0, "reveal never lies about what a cell is")

	-- The corners matter. A flood that walks AND collects with 6-neighbours leaves the four
	-- corner columns of the ring unbuilt — a diagonal gap you can see straight through, at the
	-- most visible place in the game. Collection is 26-connected for exactly this reason.
	truthy(solids[Mine.key(1, 0, 1)] ~= nil, "the mouth's corner posts are built, not left as a hole")
	truthy(solids[Mine.key(W, 0, W)] ~= nil, "…all four of them")
	truthy(solids[Mine.key(1, 0, W)] ~= nil, "…")
	truthy(solids[Mine.key(W, 0, 1)] ~= nil, "…")
	truthy(solids[Mine.key(5, 1, 5)] ~= nil, "the floor under the mouth is built")

	-- No duplicates: the server builds one Part per returned cell and would otherwise stack two
	-- in the same place.
	local seen, dupes = {}, 0
	for _, c in r.solids do
		local k = Mine.key(c.x, c.y, c.z)
		if seen[k] then dupes += 1 end
		seen[k] = true
	end
	eq(dupes, 0, "reveal reports each solid cell exactly once")

	-- Nothing above the mouth: layer -1 does not exist, and a flood that walked up into it would
	-- climb out of the world forever.
	local aboveGround = 0
	for _, c in r.air do if c.y < 0 then aboveGround += 1 end end
	for _, c in r.solids do if c.y < 0 then aboveGround += 1 end end
	eq(aboveGround, 0, "the flood cannot escape upward out of the shaft")

	-- Re-asking, with everything already open, must return nothing new. Otherwise every swing
	-- rebuilds the whole mine.
	opened[Mine.key(5, 0, 5)] = true
	for _, c in r.air do opened[c.key] = true end
	local again = Mine.reveal(Config, Ore, w0, opened, 5, 0, 5)
	eq(#again.air, 0, "a second reveal of an already-open region finds no new air")
end

do
	-- Breaking one block: only that block's own faces become visible.
	local opened = {}
	opened[Mine.key(5, 0, 5)] = true
	local first = Mine.reveal(Config, Ore, w0, opened, 5, 0, 5)
	for _, c in first.air do opened[c.key] = true end

	-- pick a rock cell on layer 1 and break it
	local bx, by, bz = 5, 1, 5
	eq(Mine.kindAt(Config, w0, bx, by, bz), "rock", "the block under the spawn is rock to begin with")
	opened[Mine.key(bx, by, bz)] = true
	local r = Mine.reveal(Config, Ore, w0, opened, bx, by, bz)
	local solids = keysOf(r.solids)
	truthy(solids[Mine.key(bx, by + 1, bz)] ~= nil, "breaking a block exposes the one beneath it")
	truthy(solids[Mine.key(bx + 1, by, bz)] ~= nil, "…and its side neighbour")
	local reAir = 0
	for _, c in r.air do if opened[c.key] then reAir += 1 end end
	eq(reAir, 0, "reveal never re-reports a cell the caller already has open")
end

do
	-- MINED BLOCKS MUST NOT GROW BACK, and this is the assertion that says so.
	--
	-- The generator is STATELESS on purpose: kindAt calls a mined cell "rock" forever, because a
	-- cell's contents must not depend on when it was first looked at. That makes `opened` the
	-- ONLY record that a block has been dug out — and the solids half of reveal has to consult it
	-- exactly like the air half already does (see the reAir assertion above). Without that, the
	-- moment a player breaks any of the 26 neighbours of a cell they already mined, the mined cell
	-- is collected as a visible solid again; the server has no Part for it any more, so it builds
	-- a fresh one at full hit points with a fresh ore payload. That is an unbounded currency
	-- printer on the first block of the game, and a ceiling that reseals over a player digging
	-- down.
	local opened = {}
	opened[Mine.key(5, 0, 5)] = true
	local mouth = Mine.reveal(Config, Ore, w0, opened, 5, 0, 5)
	for _, c in mouth.air do opened[c.key] = true end

	eq(Mine.kindAt(Config, w0, 5, 1, 5), "rock", "the block under the spawn is rock to begin with")
	eq(Mine.kindAt(Config, w0, 4, 1, 5), "rock", "…and so is its neighbour")

	opened[Mine.key(5, 1, 5)] = true -- mine it
	local afterFirst = Mine.reveal(Config, Ore, w0, opened, 5, 1, 5)
	for _, c in afterFirst.air do opened[c.key] = true end

	opened[Mine.key(4, 1, 5)] = true -- now mine the neighbour
	local r = Mine.reveal(Config, Ore, w0, opened, 4, 1, 5)

	local resurrected = {}
	for _, c in r.solids do
		if opened[c.key] then resurrected[#resurrected + 1] = c.key end
	end
	eq(#resurrected, 0, "reveal never reports an already-mined cell as a solid face again (got "
		.. table.concat(resurrected, ",") .. ")")

	-- CONTROL: the assertion above must not be satisfiable by returning nothing at all.
	local solids = keysOf(r.solids)
	truthy(#r.solids > 0, "CONTROL: the faces that were never mined are still reported")
	truthy(solids[Mine.key(3, 1, 5)] ~= nil, "CONTROL: the untouched neighbour behind the break is exposed")
	truthy(solids[Mine.key(4, 2, 5)] ~= nil, "CONTROL: …and the one beneath it")
end

do
	-- The same rule stated as the thing a player actually does: dig straight down. Six layers in
	-- they must be standing at the bottom of a six-cell shaft, not in a one-cell pocket with five
	-- full-strength blocks stacked back over their head.
	local opened = { [Mine.key(5, 0, 5)] = true }
	local mouth = Mine.reveal(Config, Ore, w0, opened, 5, 0, 5)
	for _, c in mouth.air do opened[c.key] = true end

	local resealed = {}
	for y = 1, 6 do
		opened[Mine.key(5, y, 5)] = true
		local r = Mine.reveal(Config, Ore, w0, opened, 5, y, 5)
		for _, c in r.air do opened[c.key] = true end
		for _, c in r.solids do
			if opened[c.key] then resealed[#resealed + 1] = c.key end
		end
	end
	eq(#resealed, 0, "digging six layers straight down reseals nothing overhead (got "
		.. table.concat(resealed, ",") .. ")")
end

do
	-- The budget really does bite, and says so rather than silently stopping. A budget of 3
	-- cannot possibly cover the 48-cell mouth.
	local tiny = table.clone(Config)
	tiny.Mine = table.clone(Config.Mine)
	tiny.Mine.RevealBudget = 3
	local r = Mine.reveal(tiny, Ore, w0, {}, 5, 0, 5)
	truthy(r.truncated, "an exhausted reveal budget is reported, not swallowed")
	truthy(#r.air <= 8, "and the flood actually stopped (" .. #r.air .. " air cells)")
end

do
	-- The elevator shaft that a rejoining player gets back. It has to be the centre column, all
	-- of it, and never past the depth wall.
	local col = Mine.column(Config, w0, 5)
	eq(#col, 5, "a 5-layer column is 5 cells")
	local badCol = 0
	for i, c in col do
		if c.x ~= Mine.center(Config) or c.z ~= Mine.center(Config) or c.y ~= i then badCol += 1 end
		if not Mine.inWorld(Config, w0, c.x, c.y, c.z) then badCol += 1 end
	end
	eq(badCol, 0, "the restored column is the centre column, top to bottom")
	eq(#Mine.column(Config, w0, 0), 0, "a player who never dug gets no column")
	eq(#Mine.column(Config, w0, 9999), w0.maxLayer, "a column can never be dug past the depth wall")
end

--=================================================== 7b. THE CAVE HAS TO SURVIVE A REJOIN

-- THE CURRENCY PRINTER. `opened` is the only record that a block has been dug out — the generator
-- is stateless and calls a mined cell "rock" for ever — so when `opened` lived only in server
-- memory, every cell of the cave except the centre elevator column was standing again the moment
-- a player rejoined, ore and all. Measured end to end against the real server: mine the eight ore
-- cells exposed in the mouth, sell for $48, leave, come back, and all eight are back; sell them
-- again for another $48; repeat at will. The rebirth price is charged against a finite shaft, so
-- an income a player resets by leaving and coming back is not a balance problem, it is the whole
-- economy having no bottom.
--
-- So the set has to be SAVED, which means it has to fit in a DataStore. One bit per cell of the
-- box, six bits per character: at the deepest wall in the game that is 9x9x314 = 25 434 cells =
-- 4 239 characters, and a brand new miner's mouth is under 60.

do
	local BOX = W * W * (w0.maxLayer + 2)

	-- 1. the index is a BIJECTION over the box. Two cells sharing an index is two cells sharing a
	--    mined/not-mined bit, which is a block that vanishes when its neighbour is dug.
	local seenIdx, dupes, outOfRange = {}, 0, 0
	for y = 0, w0.maxLayer + 1 do
		for x = 1, W do
			for z = 1, W do
				local i = Mine.cellIndex(Config, w0, x, y, z)
				if i == nil or i < 0 or i >= BOX then outOfRange += 1
				elseif seenIdx[i] then dupes += 1
				else seenIdx[i] = true end
			end
		end
	end
	eq(dupes, 0, "no two cells of the shaft share a saved-state bit")
	eq(outOfRange, 0, "every cell of the shaft has a bit inside the box")
	eq(Mine.cellIndex(Config, w0, 0, 1, 1), nil, "a cell outside the world has no bit")
	eq(Mine.cellIndex(Config, w0, 5, w0.maxLayer + 9, 5), nil, "…including one below the floor")

	-- 2. round trip. Hand-built set, exact keys back, nothing invented and nothing dropped.
	local set = {}
	for _, k in { Mine.key(5, 1, 5), Mine.key(2, 7, 8), Mine.key(9, 0, 1), Mine.key(4, 24, 6) } do
		set[k] = true
	end
	local packed = Mine.packOpened(Config, w0, set)
	truthy(type(packed) == "string" and #packed > 0, "a set of opened cells packs to a string")
	local back = Mine.unpackOpened(Config, w0, packed)
	local missing, invented = 0, 0
	for k in pairs(set) do if not back[k] then missing += 1 end end
	for k in pairs(back) do if not set[k] then invented += 1 end end
	eq(missing, 0, "every opened cell comes back")
	eq(invented, 0, "…and nothing else does")

	-- 3. the empty and the corrupt cases, because a save can be either.
	eq(Mine.packOpened(Config, w0, {}), "", "a miner who has dug nothing saves nothing")
	eq(next(Mine.unpackOpened(Config, w0, "")), nil, "…and gets nothing back")
	eq(next(Mine.unpackOpened(Config, w0, nil)), nil, "a missing save unpacks to an empty cave, not a crash")
	eq(next(Mine.unpackOpened(Config, w0, "!!!***!!!")), nil,
		"a save with not one usable character unpacks to an empty cave, not a crash")
	-- …and one that IS made of usable characters still cannot describe a cell that does not exist.
	-- (The alphabet is 64 of the printable characters, so most junk decodes to SOMETHING; what
	-- matters is that everything it decodes to is a real cell of this world.)
	local junk = Mine.unpackOpened(Config, w0, string.rep("_z-9Qk", 900))
	local outside, junkCells = 0, 0
	for k in pairs(junk) do
		junkCells += 1
		local jx, jy, jz = Mine.parseKey(k)
		if not Mine.inWorld(Config, w0, jx, jy, jz) then outside += 1 end
	end
	truthy(junkCells > 0, "CONTROL: that junk really did decode to cells (" .. junkCells .. ")")
	eq(outside, 0, "a corrupt save can never name a cell outside the world")

	-- 4. it has to FIT. Mine every diggable cell of a rebirth-0 shaft and pack the lot.
	local everything = {}
	local cells = 0
	for y = 0, w0.maxLayer do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				everything[Mine.key(x, y, z)] = true
				cells += 1
			end
		end
	end
	local full = Mine.packOpened(Config, w0, everything)
	print(string.format("  a rebirth-0 shaft dug out completely (%d cells) saves as %d characters",
		cells, #full))
	truthy(#full <= 400, "a completely excavated rebirth-0 shaft fits in " .. #full .. " characters")
	local fullBack = Mine.unpackOpened(Config, w0, full)
	local n = 0
	for _ in pairs(fullBack) do n += 1 end
	eq(n, cells, "…and every one of them comes back")

	-- 5. THE ORE DOES NOT COME BACK WITH THE SAVE. This is the pure half of the printer: the faces
	--    a restored cave rebuilds must never include a cell the player already mined out.
	local dug = {}
	local minedOre = {}
	for y = 1, 6 do
		local k = Mine.key(5, y, 5)
		dug[k] = true
		local c = Mine.cell(Config, Ore, w0, 5, y, 5)
		if c.ore > 0 then minedOre[k] = true end
	end
	-- take a couple of side cells too, so the set is not a bare column
	for _, c in { { 4, 3, 5 }, { 6, 3, 5 }, { 5, 3, 4 } } do
		dug[Mine.key(c[1], c[2], c[3])] = true
		local cell = Mine.cell(Config, Ore, w0, c[1], c[2], c[3])
		if cell.ore > 0 then minedOre[Mine.key(c[1], c[2], c[3])] = true end
	end
	local restored = Mine.unpackOpened(Config, w0, Mine.packOpened(Config, w0, dug))
	local faces = Mine.faces(Config, Ore, w0, restored)
	local resurrected, notSolid, notAdjacent = 0, 0, 0
	local haveFace = {}
	for _, f in faces do
		haveFace[f.key] = true
		if restored[f.key] then resurrected += 1 end
		if not Mine.isSolid(Config, w0, f.x, f.y, f.z) then notSolid += 1 end
		local touches = false
		for dx = -1, 1 do for dy = -1, 1 do for dz = -1, 1 do
			if restored[Mine.key(f.x + dx, f.y + dy, f.z + dz)] then touches = true end
		end end end
		if not touches then notAdjacent += 1 end
	end
	eq(resurrected, 0, "a restored cave rebuilds no cell the player had already dug out")
	eq(notSolid, 0, "…and nothing that is not solid rock or bedrock")
	eq(notAdjacent, 0, "…and nothing the player could not see from the space they opened")

	-- CONTROL: it is not empty, and it is COMPLETE — every solid the player can see is there, or
	-- the restored cave is a hole looking out of the world.
	truthy(#faces > 20, "CONTROL: a restored cave does rebuild the walls around the dig ("
		.. #faces .. " faces)")
	local uncovered = 0
	for k in pairs(restored) do
		local x, y, z = Mine.parseKey(k)
		for dx = -1, 1 do for dy = -1, 1 do for dz = -1, 1 do
			local nx, ny, nz = x + dx, y + dy, z + dz
			if Mine.inWorld(Config, w0, nx, ny, nz) and Mine.isSolid(Config, w0, nx, ny, nz) then
				local nk = Mine.key(nx, ny, nz)
				if not restored[nk] and not haveFace[nk] then uncovered += 1 end
			end
		end end end
	end
	eq(uncovered, 0, "every solid cell visible from the restored dig has a face to build")
	eq(next(Mine.faces(Config, Ore, w0, {})), nil, "CONTROL: a cave nobody has dug rebuilds nothing")

	-- 6. and the deepest cell, which is where DESCEND has to aim after a rejoin.
	local d = Mine.deepestOpened(dug)
	eq(d.y, 6, "the restored cave knows how deep it goes")
	eq(d.x, 5, "…and where"); eq(d.z, 5, "…exactly")
	eq(Mine.deepestOpened({}), nil, "a cave nobody has dug has no bottom to aim at")

	-- 6b. THE WORST CASE IN THE GAME, MEASURED. Saving the cave bought a bounded lifetime cost:
	--     a player who excavates their whole shaft at the deepest wall has that many Parts
	--     rebuilt for them on every join, for ever, because nothing unloads. The bound is the
	--     box, and this is the box — asserted so it cannot grow quietly.
	do
		local deep = Mine.world(Config, Config.Prestige.MaxRebirths - 1)
		local everything = {}
		local cells = 0
		for y = 0, deep.maxLayer do
			for x = 2, W - 1 do
				for z = 2, W - 1 do
					everything[Mine.key(x, y, z)] = true
					cells += 1
				end
			end
		end
		local bits = Mine.packOpened(Config, deep, everything)
		local faces = Mine.faces(Config, Ore, deep, everything)
		print(string.format("  worst case in the game: rebirth %d, %d cells dug, %d characters saved,"
			.. " %d faces rebuilt on join (%d frames at %d per frame)",
			Config.Prestige.MaxRebirths - 1, cells, #bits, #faces,
			math.ceil(#faces / Config.Mine.PartsPerFrame), Config.Mine.PartsPerFrame))
		truthy(#bits <= 6000, "the biggest save this game can produce is " .. #bits
			.. " characters, well inside a DataStore value")
		-- The SAVE is bounded by the box and always was. The RESTORE is not bounded by this
		-- number, and the old assertion here (`#faces <= 12000`) said it was: the excavated shaft
		-- is not the state that exposes the most faces, so 12 000 was a bound measured off a
		-- non-maximum and a lattice dig walks straight through it at 19 115. What is actually
		-- bounded now is the WINDOW — see 7c/7d — so the restore is asserted there, against the
		-- band, and this only keeps the historical figure honest.
		eq(#faces, 10097, "REVIEW-3's figure for the excavated shaft, unchanged: " .. #faces
			.. " faces — see 7c for why that is not the worst case and not what is built")
	end

	-- 7. parseKey is the inverse of key, for every cell of the box.
	local badParse = 0
	for y = 0, 26 do
		for x = 1, W do
			for z = 1, W do
				local px, py, pz = Mine.parseKey(Mine.key(x, y, z))
				if px ~= x or py ~= y or pz ~= z then badParse += 1 end
			end
		end
	end
	eq(badParse, 0, "parseKey is the exact inverse of key")
end

--============================================== 7c. NOTHING UNLOADS — the shaft has to be bounded
--
-- REVIEW-3 left this open and measured: a fully excavated shaft at the deepest wall is 10 097
-- Parts, rebuilt on every join, for ever. Two measurements settle what to do about it, and both
-- are asserted here so neither can drift:
--
--   1. THAT 10 097 IS 100% BEDROCK. Excavate a shaft completely and every rock face is gone; what
--      is left is the bedrock ring (32 cells per layer x 314 layers) plus the 7x7 floor. Culling
--      "the interior of solid rock" therefore saves exactly nothing in the worst case, because
--      there is no interior left. The ring is a rectangular tube and the floor is a flat slab, so
--      the answer to that number is GEOMETRY, not policy: Mine.shell describes them as five slabs.
--   2. AND 10 097 IS NOT THE WORST CASE. A shaft dug in a lattice — every other cell on each axis,
--      which is what a strip mine is — puts an opened cell within reach of every solid cell in the
--      box and exposes all of them: 19 115 Parts at rebirth 24, of which 9 018 are rock and ore
--      that no bedrock trick touches. Even the ordinary "dig straight down to the wall" play
--      reaches 11 960. So the rock faces need a bound of their own, and that is the depth band:
--      Mine.faces takes a layer window and answers for it alone.

local function excavated(w)
	local o = {}
	for y = 0, w.maxLayer do
		for x = 2, W - 1 do for z = 2, W - 1 do o[Mine.key(x, y, z)] = true end end
	end
	return o
end

local function lattice(w)
	local o = {}
	for y = 0, w.maxLayer, 2 do
		for x = 2, W - 1, 2 do for z = 2, W - 1, 2 do o[Mine.key(x, y, z)] = true end end
	end
	return o
end

do
	local deep = Mine.world(Config, Config.Prestige.MaxRebirths - 1)

	-- 1. the shape of the 10 097.
	do
		local all = Mine.faces(Config, Ore, deep, excavated(deep))
		local bed, ring, floor = 0, 0, 0
		for _, f in all do
			if f.kind == "bedrock" then
				bed += 1
				if f.x == 1 or f.x == W or f.z == 1 or f.z == W then ring += 1 else floor += 1 end
			end
		end
		eq(#all, 10097, "a fully excavated rebirth-24 shaft is 10097 faces — REVIEW-3's number")
		eq(bed, 10097, "…and every last one of them is BEDROCK, so culling rock saves nothing here")
		eq(ring, 10048, "…10048 of it the ring, which is a rectangular tube")
		eq(floor, 49, "…and 49 the floor, which is a slab")
	end

	-- 2. …and it is not the worst case. The bound REVIEW-3 asserted (<= 12000) was measured
	--    against a state that is not the maximum.
	do
		local lat = #Mine.faces(Config, Ore, deep, lattice(deep))
		truthy(lat > 12000, "a lattice dig exposes MORE than the fully excavated shaft ("
			.. lat .. " vs 10097) — the old bound was measured off a non-maximum")
		print(string.format("  worst case is not the excavated shaft: lattice dig = %d faces", lat))
	end
end

--============================================================== 7d. the depth band (Mine.faces)

do
	local w = Mine.world(Config, 0)
	local dug = excavated(w)

	-- Everything, then a window: the window must be a strict subset, and must contain exactly the
	-- faces whose own layer is inside it.
	local all = Mine.faces(Config, Ore, w, dug)
	local band = Mine.faces(Config, Ore, w, dug, 4, 9)
	local outside, inBandTotal = 0, 0
	for _, f in band do
		if f.y < 4 or f.y > 9 then outside += 1 end
	end
	for _, f in all do
		if f.y >= 4 and f.y <= 9 then inBandTotal += 1 end
	end
	eq(outside, 0, "a banded faces() returns nothing outside the band")
	eq(#band, inBandTotal, "…and everything inside it (" .. #band .. " of " .. #all .. ")")
	truthy(#band < #all, "CONTROL: the band really is smaller than the whole shaft")
	truthy(#band > 0, "CONTROL: …and not empty")

	-- The band is clamped, not wrapped: a window past the ends of the world is the ends of it.
	eq(#Mine.faces(Config, Ore, w, dug, -50, 500), #all, "a band wider than the world IS the world")
	eq(#Mine.faces(Config, Ore, w, dug, 900, 950), 0, "…and one past the bottom of it is empty")

	-- No band at all is still the whole shaft: every existing caller passes four arguments.
	eq(#Mine.faces(Config, Ore, w, dug), #all, "faces() with no band is unchanged")
end

do
	-- THE POINT OF THE BAND, MEASURED AT THE WORST WINDOW IN THE GAME. Not the average window: the
	-- band is a per-player budget, and what matters is the most expensive place a player can stand.
	local deep = Mine.world(Config, Config.Prestige.MaxRebirths - 1)
	local k = Config.Mine.StreamLayers
	for _, dig in { { "excavated", excavated(deep) }, { "lattice", lattice(deep) } } do
		local worst, worstAt = 0, 0
		-- step 8 layers: the window is 2k+1 = 33 layers wide, so an 8-layer step cannot skip a peak
		for at = 0, deep.maxLayer, 8 do
			local n = 0
			for _, f in Mine.faces(Config, Ore, deep, dig[2], at - k, at + k) do
				if f.kind ~= "bedrock" then n += 1 end
			end
			if n > worst then worst, worstAt = n, at end
		end
		print(string.format("  band +-%d layers, %s dig: worst window %d rock+ore faces (layer %d)",
			k, dig[1], worst, worstAt))
		truthy(worst <= 1600, "the worst " .. dig[1] .. " window holds " .. worst
			.. " rock+ore faces, inside the 1600 budget")
	end

	-- AND THE PART OF IT THAT IS BUILT SYNCHRONOUSLY. A teleport (DESCEND, SURFACE, a respawn)
	-- has to have ground under it the instant it lands, so the server builds the landing before it
	-- sets the CFrame — inside the frame, with no yield. That has to stay inside one frame's
	-- budget, or the elevator hitches every press. It is the 3x3 column under the miner and NOT
	-- the whole two-layer band, which measures at 202 and would be three frames.
	local r = Config.Mine.StreamLandingLayers
	local worstCol = 0
	for at = 0, deep.maxLayer, 5 do
		local per = {}
		for _, f in Mine.faces(Config, Ore, deep, lattice(deep), at - r, at + r) do
			if f.kind ~= "bedrock" then
				for dx = -1, 1 do for dz = -1, 1 do
					local k2 = (f.x + dx) .. ":" .. (f.z + dz)
					per[k2] = (per[k2] or 0) + 1
				end end
			end
		end
		for _, n in pairs(per) do if n > worstCol then worstCol = n end end
	end
	print(string.format("  landing build: worst 3x3 column over +-%d layers = %d parts (budget %d/frame)",
		r, worstCol, Config.Mine.PartsPerFrame))
	truthy(worstCol > 0, "CONTROL: the landing build is not empty")
	truthy(worstCol <= Config.Mine.PartsPerFrame,
		"the synchronous landing build is " .. worstCol .. " parts, inside one frame's "
			.. Config.Mine.PartsPerFrame)
end

--=========================================================== 7e. the shell: the box, as five slabs
--
-- The bedrock ring and the bedrock floor never change, are never breakable, and are never even
-- clickable except for the floor. Built cell by cell they are 10 048 + 49 Parts at the deepest
-- wall — the whole of REVIEW-3's 10 097. Built as geometry they are five: four walls and a floor.
-- What they have to keep is exactly what the cell grid gave them: a SEALED box (the rim comment in
-- Mine says why — one cell is 6 studs and a Roblox jump clears 7.2), and no intrusion into a cell
-- a player is supposed to be able to dig.

do
	local S = Config.Mine.CellSize
	for _, r in { 0, 1, 24 } do
		local w = Mine.world(Config, r)
		local shell = Mine.shell(Config, w)
		eq(#shell, 5, "r" .. r .. ": the box is five slabs, not " .. (4 * (W - 1) * (w.maxLayer + 2))
			.. " cubes")

		local function inside(s, px, py, pz)
			return math.abs(px - s.x) <= s.sx / 2 + 1e-9
				and math.abs(py - s.y) <= s.sy / 2 + 1e-9
				and math.abs(pz - s.z) <= s.sz / 2 + 1e-9
		end
		local function covered(px, py, pz)
			for _, s in shell do if inside(s, px, py, pz) then return true end end
			return false
		end

		-- EVERY bedrock cell of the box is inside a slab. Sampled at the cell centre AND at the
		-- eight corners inset a hair, so a slab that is one stud short somewhere is caught.
		local missed = 0
		for y = 0, w.maxLayer + 1 do
			for x = 1, W do
				for z = 1, W do
					if Mine.kindAt(Config, w, x, y, z) == "bedrock" then
						local p = Mine.localPos(Config, x, y, z)
						for _, d in { { 0, 0, 0 }, { 1, 1, 1 }, { -1, -1, -1 }, { 1, -1, 1 }, { -1, 1, -1 } } do
							local e = S / 2 - 0.01
							if not covered(p.x + d[1] * e, p.y + d[2] * e, p.z + d[3] * e) then
								missed += 1
							end
						end
					end
				end
			end
		end
		eq(missed, 0, "r" .. r .. ": every bedrock cell of the box is sealed inside a slab")

		-- …and NOTHING the player is meant to dig is. A slab poking into a diggable cell is a
		-- block that cannot be mined standing in the middle of the mine.
		local intruded = 0
		for y = 0, w.maxLayer do
			for x = 2, W - 1 do
				for z = 2, W - 1 do
					local p = Mine.localPos(Config, x, y, z)
					if covered(p.x, p.y, p.z) then intruded += 1 end
				end
			end
		end
		eq(intruded, 0, "r" .. r .. ": and no slab intrudes into a cell a player can dig")

		-- The rim. One cell is 6 studs, a Roblox jump clears about 7.2, so the wall has to stand
		-- proud of the surface or a player hops out of the mine and onto the roof of the world.
		local top = -math.huge
		for _, s in shell do
			if s.kind == "wall" then top = math.max(top, s.y + s.sy / 2) end
		end
		truthy(top >= S * (Config.Mine.RimCells - 1) - 1e-9,
			"r" .. r .. ": the wall stands " .. top .. " studs above the mouth — nobody jumps out")

		-- exactly one of the five is the floor, and it is the thing the depth wall toast comes off
		local walls, floors = 0, 0
		for _, s in shell do
			if s.kind == "wall" then walls += 1 elseif s.kind == "floor" then floors += 1 end
		end
		eq(walls, 4, "r" .. r .. ": four walls")
		eq(floors, 1, "r" .. r .. ": one floor")
	end

	-- CONTROL: the shell has to MOVE when the wall does, or it is a constant pretending to be a
	-- measurement — a floor that stayed at rebirth 0's depth would seal every deeper cave shut.
	local f0, f24 = nil, nil
	for _, s in Mine.shell(Config, Mine.world(Config, 0)) do
		if s.kind == "floor" then f0 = s.y end
	end
	for _, s in Mine.shell(Config, Mine.world(Config, 24)) do
		if s.kind == "floor" then f24 = s.y end
	end
	truthy(f24 < f0 - 100, "CONTROL: the floor slab follows the depth wall down (" .. tostring(f0)
		.. " -> " .. tostring(f24) .. ")")
end

--=================================================== 7f. which layer a stud height is standing in

do
	local S = Config.Mine.CellSize
	-- The streamer centres the band on the player, so it has to be able to turn "the miner's root
	-- part is at y = -134" back into a layer. Checked against the two mappings that already exist,
	-- because a third opinion about where the floor is is exactly how an elevator and a spawn end
	-- up disagreeing.
	local bad = 0
	for y = 0, 40 do
		-- a character standing IN layer y has its feet on the top face of cell y+1
		if Mine.layerOfY(Config, Mine.floorY(Config, y) + 4) ~= y then bad += 1 end
		-- and the centre of cell y is inside cell y
		if Mine.layerOfY(Config, Mine.localPos(Config, 5, y, 5).y) ~= y then bad += 1 end
	end
	eq(bad, 0, "layerOfY inverts both the floor mapping and the cell mapping")
	eq(Mine.layerOfY(Config, 4), 0, "standing at the mouth is layer 0")
	eq(Mine.layerOfY(Config, 100), 0, "…and so is standing well above it: there is no layer -16")
	eq(Mine.layerOfY(Config, -S * 24 + 4), 24, "and 144 studs down is layer 24")
end

--============================================================================ 8. THE CONTROL
-- A change the tests must NOT notice. Names, colours, prices, save keys and the entire economy
-- are cosmetic or downstream as far as the cave is concerned: changing every one of them must
-- not move a single cell, or the generator is reading something it has no business reading and
-- the "same seed = same cave for everyone" promise behind the leaderboard is not real.
--
-- Without a control, a harness that is quietly broken reports every mutation as caught and every
-- one of these assertions as passing. This is the assertion that says the suite can still tell
-- the difference between a change and no change.

do
	local shadow = table.clone(Config)
	shadow.Ores = table.clone(Config.Ores)
	shadow.Ores.Names = { [0] = "Gravel", "Rust", "Tin", "Brass", "Ice", "Void" }
	shadow.Ores.Color = { [0] = { 1, 2, 3 }, { 9, 9, 9 }, { 8, 8, 8 }, { 7, 7, 7 }, { 6, 6, 6 }, { 5, 5, 5 } }
	shadow.Ores.Value = { [0] = 0, 1, 2, 3, 4, 5 }
	shadow.Economy = { StartCash = 999999, Pickaxe = { Power = { 1 }, Cost = { 0 }, Names = { "x" }, MaxTier = 1 },
		Backpack = { BaseCapacity = 1, PerLevel = 1, MaxLevel = 1, BaseCost = 1, CostGrowth = 1 },
		Lamp = { BaseRadius = 1, PerLevel = 1, MaxLevel = 1, BaseCost = 1, CostGrowth = 1 } }
	shadow.Prestige = table.clone(Config.Prestige)
	shadow.Prestige.MultiplierPerRebirth = 77
	shadow.Save = { Enabled = false, Store = "somewhere_else", Leaderboard = "nope",
		AutosaveSeconds = 1, SessionLockSeconds = 2 }

	local sw = Mine.world(shadow, 0)
	eq(sw.seed, w0.seed, "CONTROL: cosmetic config does not change the cave seed")
	eq(sw.maxLayer, w0.maxLayer, "CONTROL: cosmetic config does not move the depth wall")

	local moved, reOred, reHp = 0, 0, 0
	for y = 0, 26 do
		for x = 1, W do
			for z = 1, W do
				local a = Mine.cell(Config, Ore, w0, x, y, z)
				local b = Mine.cell(shadow, Ore, sw, x, y, z)
				if a.kind ~= b.kind then moved += 1 end
				if a.ore ~= b.ore then reOred += 1 end
				if a.hp ~= b.hp then reHp += 1 end
			end
		end
	end
	eq(moved, 0, "CONTROL: not one cell changed kind")
	eq(reOred, 0, "CONTROL: not one vein moved")
	eq(reHp, 0, "CONTROL: not one block changed hardness")

	-- And the same control run the other way: a change the suite MUST notice, proving the loop
	-- above can actually see a difference at all.
	local realChange = table.clone(Config)
	realChange.Mine = table.clone(Config.Mine)
	realChange.Mine.AirThreshold = Config.Mine.AirThreshold - 0.10
	local rw = Mine.world(realChange, 0)
	local noticed = 0
	for y = 2, 26 do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				if Mine.kindAt(Config, w0, x, y, z) ~= Mine.kindAt(realChange, rw, x, y, z) then noticed += 1 end
			end
		end
	end
	truthy(noticed > 50, "the same comparison DOES notice a real change to the carving threshold")
end

print(string.format("Mine: %d passed, %d failed", passed, failed))
assert(failed == 0, "Mine tests failed")
