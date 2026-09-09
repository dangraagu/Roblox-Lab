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
