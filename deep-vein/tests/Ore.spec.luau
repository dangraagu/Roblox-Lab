-- Rene tester for Ore. Kjør: luau tests/Ore.spec.luau
--
-- Ore is the rarity table of Deep Vein: given a DEPTH and one uniform number, which ore is in
-- this block? Everything here is arithmetic on Config.Ores, so it is fully determined and the
-- numbers below are written out by hand rather than recomputed from the module (a test that
-- recomputes the formula it is testing grades the formula against itself).

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

local oc = Config.Ores
local MAXO = Config.MaxOre

--========================================================================== weights by depth

near(Ore.weight(Config, 1, 1), 0.150, "copper is at full weight on layer 1")
near(Ore.weight(Config, 1, 11), 0.128, "copper thins out with depth")
near(Ore.weight(Config, 1, 100), 0, "copper is gone by layer 100")
truthy(Ore.weight(Config, 1, 100) >= 0, "a weight is never negative")

eq(Ore.weight(Config, 2, 2), 0, "iron cannot appear above its MinLayer")
near(Ore.weight(Config, 2, 3), 0.100, "iron starts at its BaseWeight on its MinLayer")
near(Ore.weight(Config, 2, 14), 0.100 + 0.0013 * 11, "iron gets richer with depth")
near(Ore.weight(Config, 2, 400), 0.150, "iron is clamped to MaxWeight")

eq(Ore.weight(Config, 3, 5), 0, "gold cannot appear on layer 5")
near(Ore.weight(Config, 3, 6), 0.060, "gold starts on layer 6")
eq(Ore.weight(Config, 4, 9), 0, "diamond cannot appear on layer 9")
near(Ore.weight(Config, 4, 10), 0.036, "diamond starts on layer 10")
-- Obsidian is the tier that shipped stranded below the rebirth-0 depth wall (MinLayer 26 against
-- a wall of 24). It then spent one round at layer 19, which was legal but produced FOUR cells in
-- the whole rebirth-0 shaft — 46% of the shaft's value in four blocks. It starts at 14 now, and
-- both the reachability gate below and the census in Mine.spec fail if that drifts back.
eq(Ore.weight(Config, 5, 13), 0, "obsidian cannot appear on layer 13")
near(Ore.weight(Config, 5, 14), 0.018, "obsidian starts on layer 14")
near(Ore.weight(Config, 5, 40), 0.018 + 0.0012 * 26, "obsidian gets richer with depth")

eq(Ore.weight(Config, 0, 50), 0, "tier 0 is stone, not an ore, and has no weight")
eq(Ore.weight(Config, 99, 50), 0, "an unknown tier weighs nothing rather than raising")

--=========================================================================== tierAt: the roll

-- Layer 1: copper is the only ore in the table, holding [0, 0.150).
eq(Ore.tierAt(Config, 1, 0.0), 1, "u=0 on layer 1 is copper")
eq(Ore.tierAt(Config, 1, 0.149), 1, "just inside copper's band")
eq(Ore.tierAt(Config, 1, 0.150), 0, "just outside copper's band is plain stone")
eq(Ore.tierAt(Config, 1, 0.9), 0, "most of layer 1 is plain stone")

-- Layer 30, every tier live. Bands, rarest first:
--   obsidian [0, 0.0372)  diamond [0.0372, 0.1052)  gold [0.1052, 0.2084)
--   iron     [0.2084, 0.3435)  copper [0.3435, 0.4297)  stone [0.4297, 1)
eq(Ore.tierAt(Config, 30, 0.001), 5, "the rarest band on layer 30 is obsidian")
eq(Ore.tierAt(Config, 30, 0.037), 5, "just inside obsidian's band")
eq(Ore.tierAt(Config, 30, 0.04), 4, "diamond band on layer 30")
eq(Ore.tierAt(Config, 30, 0.15), 3, "gold band on layer 30")
eq(Ore.tierAt(Config, 30, 0.25), 2, "iron band on layer 30")
eq(Ore.tierAt(Config, 30, 0.40), 1, "copper band on layer 30")
eq(Ore.tierAt(Config, 30, 0.5), 0, "and the rest of layer 30 is stone")

-- The gate has to hold for EVERY roll, not just the ones spelled out above: an ore that leaks
-- one layer early is a progression bug nobody would ever see in play.
for tier = 1, MAXO do
	local above = oc.MinLayer[tier] - 1
	if above >= 1 then
		local leaked = 0
		for i = 0, 999 do
			if Ore.tierAt(Config, above, i / 1000) == tier then leaked += 1 end
		end
		eq(leaked, 0, "tier " .. tier .. " never appears on layer " .. above)
	end
end

-- Stone must always be reachable, or a block of pure ore fills the whole mine.
for layer = 1, 200 do
	local total = 0
	for tier = 1, MAXO do total += Ore.weight(Config, tier, layer) end
	truthy(total < 1, "ore weights on layer " .. layer .. " leave room for stone (" .. total .. ")")
end

-- And the answer is always a tier that exists.
local seen = {}
for i = 0, 999 do
	local t = Ore.tierAt(Config, 40, i / 1000)
	truthy(t >= 0 and t <= MAXO and t == math.floor(t), "tierAt returns a real tier for u=" .. (i / 1000))
	seen[t] = (seen[t] or 0) + 1
end
truthy(seen[0] ~= nil, "layer 40 still produces plain stone")
truthy(seen[5] ~= nil, "layer 40 does produce obsidian")

-- Monotone in u within a layer: raising the roll can only ever move you toward stone. This is
-- what makes the band arithmetic above a real partition rather than a set of lucky samples.
do
	local bad = 0
	local prev = Ore.tierAt(Config, 30, 0)
	for i = 1, 999 do
		local t = Ore.tierAt(Config, 30, i / 1000)
		-- the bands run rarest -> commonest -> stone, so the tier INDEX must never rise as u grows
		if t ~= 0 and prev ~= 0 and t > prev then bad += 1 end
		if prev == 0 and t ~= 0 then bad += 1 end
		prev = t
	end
	eq(bad, 0, "the bands partition [0,1) in one direction, with stone last")
end

--=========================================================================== lookups

eq(Ore.name(Config, 0), "Stone", "tier 0 is named")
eq(Ore.name(Config, 3), "Gold", "tier 3 is Gold")
eq(Ore.name(Config, 77), "Stone", "an unknown tier falls back to Stone rather than nil")
eq(Ore.value(Config, 0), 0, "stone is worth nothing")
eq(Ore.value(Config, 5), 800, "obsidian is worth 800")
eq(Ore.value(Config, 77), 0, "an unknown tier is worth nothing")
eq(Ore.hardness(Config, 0), 10, "stone hardness")
eq(Ore.hardness(Config, 5), 165, "obsidian hardness")
eq(Ore.yieldOf(Config, 0), 0, "breaking stone yields no ore unit")
eq(Ore.yieldOf(Config, 2), 1, "breaking iron yields one ore unit")
truthy(Ore.isOre(Config, 1), "copper is an ore")
truthy(not Ore.isOre(Config, 0), "stone is not an ore")
truthy(not Ore.isOre(Config, 77), "an unknown tier is not an ore")

do
	local c = Ore.color(Config, 4)
	eq(c[1], 128, "diamond colour r"); eq(c[2], 232, "diamond colour g"); eq(c[3], 246, "diamond colour b")
	local s = Ore.color(Config, 77)
	truthy(type(s) == "table" and #s == 3, "an unknown tier still gets a colour rather than nil")
end

-- Value has to rise with tier or the whole depth incentive inverts.
for t = 1, MAXO do
	truthy(Ore.value(Config, t) > Ore.value(Config, t - 1), "tier " .. t .. " is worth more than tier " .. (t - 1))
	truthy(Ore.hardness(Config, t) > Ore.hardness(Config, t - 1), "tier " .. t .. " is harder than tier " .. (t - 1))
end

--============================================================ every tier has to be REACHABLE

-- MinLayer is written in absolute layers and the depth wall is a separate constant, and nothing
-- in the config relates the two. Obsidian shipped with MinLayer 26 against a rebirth-0 wall of
-- 24: Ore.weight returned 0 for it at every layer a player could ever stand on, so an entire
-- advertised tier could not spawn until after the first rebirth — and the first rebirth is the
-- thing the deepest ore is supposed to pay for. This is the assertion that ties the two numbers
-- together, so moving either one can never quietly strand a tier again.
do
	local wall = Config.Mine.BaseMaxLayer
	for t = 1, MAXO do
		local best, bestAt = 0, -1
		for layer = 1, wall do
			local w = Ore.weight(Config, t, layer)
			if w > best then best, bestAt = w, layer end
		end
		truthy(best > 0, Ore.name(Config, t) .. " can spawn somewhere above the rebirth-0 depth wall"
			.. " (MinLayer " .. tostring(oc.MinLayer[t]) .. " vs wall " .. wall
			.. ", best weight " .. string.format("%.4f", best) .. " at layer " .. bestAt .. ")")
		truthy(oc.MinLayer[t] <= wall, Ore.name(Config, t)
			.. " starts at or above the rebirth-0 depth wall (MinLayer " .. tostring(oc.MinLayer[t])
			.. ", wall " .. wall .. ")")
	end
end

print(string.format("Ore: %d passed, %d failed", passed, failed))
assert(failed == 0, "Ore tests failed")
