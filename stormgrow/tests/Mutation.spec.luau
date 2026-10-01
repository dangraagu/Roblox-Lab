-- Spec for Mutation: marks, variants, the strike tick and the Almanac. Run: luau tests/Mutation.spec.luau
--
-- The strike tick is the only place a mark or an Almanac entry is ever made (DESIGN.md §2.2, §10): the
-- server calls it at its own tick, on its own clock, with its own randomness. So these rules are the
-- whole anti-exploit story for the leaderboard: only ripe crops, only a mark the crop lacks, only the
-- event's own mark, and exactly the published odds.
local Mutation = require("../src/shared/Mutation")
local Weather = require("../src/shared/Weather")
local Config = require("../src/shared/Config")
local W, M = Config.Weather, Config.Marks

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local function lcg(seed)
	local s = seed % 4294967296
	return function()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end

local byId = {}
for _, c in Config.Crops do byId[c.id] = c end

--================================================================ values multiply

eq(Mutation.mult(0, M), 1, "a plain crop is x1")
eq(Mutation.mult(1, M), 5, "Charged x5")
eq(Mutation.mult(2, M), 5, "Frosted x5")
eq(Mutation.mult(4, M), 8, "Prismatic x8")
eq(Mutation.mult(3, M), 25, "Stormglass = 5 x 5")
eq(Mutation.mult(5, M), 40, "Radiant = 5 x 8")
eq(Mutation.mult(6, M), 40, "Aurora = 5 x 8")
eq(Mutation.mult(7, M), 200, "Tempest = 5 x 5 x 8")
eq(Mutation.variant(0, Config.Variants), nil, "plain has no variant name")
eq(Mutation.variant(7, Config.Variants), "Tempest", "7 is the Tempest")
eq(Mutation.variant(3, Config.Variants), "Stormglass", "3 is Stormglass")
eq(Mutation.emoji(7, M), "⚡❄️🌈", "the Tempest wears all three marks, in bit order")
eq(Mutation.emoji(0, M), "", "a plain crop wears none")
eq(Mutation.bitOf("storm", M), 1, "a storm gives bit 1")
eq(Mutation.bitOf("rainbow", M), 4, "a rainbow gives bit 4")

--================================================================ the Almanac

local keys = Mutation.allKeys(Config.Crops)
eq(#keys, 56, "8 crops x 7 marked variants = 56 Almanac entries")
eq(keys[1], "radish:1", "crop-major, marks 1..7: the first entry is Charged Radish")
eq(keys[56], "stormfruit:7", "the last is the Tempest Stormfruit")
do
	local seen, dup = {}, 0
	for _, k in keys do
		if seen[k] then dup += 1 end
		seen[k] = true
		eq(type(k), "string", "every key is a string (DataStore trap: never an integer key)")
	end
	eq(dup, 0, "no duplicate keys")
end
do
	local c, m = Mutation.parseKey("pumpkin:5")
	eq(c, "pumpkin", "parseKey reads the crop")
	eq(m, 5, "and the marks")
	eq((Mutation.parseKey("pumpkin:0")), nil, "plain is not an entry")
	eq((Mutation.parseKey("pumpkin:8")), nil, "marks above 7 are not an entry")
	eq((Mutation.parseKey("nope")), nil, "junk is not an entry")
end

do
	local p = { almanac = {}, almanacCount = 0, almanacAt = 0 }
	eq(Mutation.grant(p, "radish", 1, 1000.7), true, "a first Charged Radish is a new entry")
	eq(p.almanacCount, 1, "the count went up")
	eq(p.almanacAt, 1000, "reachedAt is the server's whole second")
	eq(p.almanac["radish:1"], 1000, "keyed by string, first-seen time")
	eq(Mutation.grant(p, "radish", 1, 2000), false, "the same entry again is not new")
	eq(p.almanacCount, 1, "and does not count twice")
	eq(p.almanacAt, 1000, "nor move the tie-break time")
	eq(Mutation.grant(p, "radish", 0, 2000), false, "a plain crop is never an entry")
	Mutation.grant(p, "carrot", 7, 3000)
	local bits = Mutation.bits(p.almanac, Config.Crops)
	eq(#bits, 56, "the bit string has 56 characters")
	eq(string.sub(bits, 1, 1), "1", "Charged Radish is lit")
	eq(string.sub(bits, 14, 14), "1", "Tempest Carrot is lit (crop 2, marks 7 -> position 14)")
	eq(Mutation.count(p.almanac, Config.Crops), 2, "count recounts from the entries")
	eq(Mutation.missing(p.almanac, "radish"), 6, "Radish has 6 entries still to find")
	eq(Mutation.missing(p.almanac, "corn"), 7, "Corn has all 7")
	-- a junk key never counts
	p.almanac["nope:3"] = 5
	p.almanac["radish:9"] = 5
	eq(Mutation.count(p.almanac, Config.Crops), 2, "junk keys do not count")
end

--================================================================ the strike tick

local T = 1790002800 -- on the hour: a storm
local function tilesAt(t)
	return {
		["1_1"] = { c = "radish", at = t - 40, m = 0 }, -- ripe (30 s)
		["1_2"] = { c = "radish", at = t - 10, m = 0 }, -- growing
		["1_3"] = { c = "radish", at = t - 40, m = 1 }, -- ripe, already Charged
		["1_4"] = { c = "radish", at = t - 40, m = 2 }, -- ripe, Frosted
		["1_5"] = { c = "corn", at = t - 120, m = 0 }, -- ripe exactly now (120 s)
	}
end

do
	local always = function() return 0 end
	local tiles = tilesAt(T)
	local struck = Mutation.strikeTick(tiles, "storm", T, always, W, M, byId)
	local got = {}
	for _, s in struck do got[s.key] = s end
	truthy(got["1_1"] ~= nil, "a ripe plain crop is struck")
	eq(tiles["1_1"].m, 1, "and becomes Charged")
	eq(got["1_2"], nil, "a growing crop is never struck")
	eq(tiles["1_2"].m, 0, "and keeps no mark")
	eq(got["1_3"], nil, "a crop that already has the storm's mark is not rolled again")
	truthy(got["1_4"] ~= nil, "a Frosted crop can still become Charged")
	eq(tiles["1_4"].m, 3, "Frosted + Charged = Stormglass (3)")
	truthy(got["1_5"] ~= nil, "a crop that ripened exactly at the tick is ripe (strict >=)")
	eq(#struck, 3, "three strikes")
	eq(got["1_1"].gained, 1, "a strike reports the bit it added")
end
do
	local never = function() return 0.999999 end
	local tiles = tilesAt(T)
	eq(#Mutation.strikeTick(tiles, "storm", T, never, W, M, byId), 0, "rand above q strikes nothing")
end
do
	-- only the EVENT'S mark: a frost tick adds Frosted, never Charged
	local tiles = { ["2_1"] = { c = "radish", at = T - 100, m = 0 } }
	Mutation.strikeTick(tiles, "frost", T, function() return 0 end, W, M, byId)
	eq(tiles["2_1"].m, 2, "a frost tick gives Frosted")
	Mutation.strikeTick(tiles, "rainbow", T, function() return 0 end, W, M, byId)
	eq(tiles["2_1"].m, 6, "a rainbow tick adds Prismatic: Aurora")
	Mutation.strikeTick(tiles, "storm", T, function() return 0 end, W, M, byId)
	eq(tiles["2_1"].m, 7, "a storm tick completes the Tempest")
	eq(#Mutation.strikeTick(tiles, "storm", T, function() return 0 end, W, M, byId), 0, "a Tempest takes nothing more")
end
do
	-- the ONE injected rand is consumed exactly once per eligible crop, in a stable key order, so the
	-- server's order of iteration cannot bias who gets struck
	local calls = 0
	local tiles = tilesAt(T)
	Mutation.strikeTick(tiles, "storm", T, function() calls += 1; return 0.9 end, W, M, byId)
	eq(calls, 3, "one draw per eligible crop (ripe and lacking the mark), none for the others")
	local order = Mutation.sortedKeys({ ["2_1"] = 1, ["10_3"] = 1, ["1_9"] = 1, ["1_10"] = 1 })
	eq(table.concat(order, ","), "1_9,1_10,2_1,10_3", "keys sort by field then tile, numerically")
end
do
	-- an unknown crop id or a bad record is skipped, never an error
	local tiles = { ["1_1"] = { c = "nope", at = T - 999, m = 0 }, ["1_2"] = { c = "radish", at = "x", m = 0 } }
	local ok = pcall(Mutation.strikeTick, tiles, "storm", T, function() return 0 end, W, M, byId)
	truthy(ok, "junk tiles do not raise")
end

--================================================================ the published odds, measured

do
	-- 100 000 simulated events per kind: a crop ripe for the whole event takes the mark with chance P.
	local r = lcg(20260930)
	for _, kind in W.Kinds do
		local runs, hits = 100000, 0
		local e = W.Events[kind]
		local first, last = Weather.tickWindow(kind, e.from, W)
		for _ = 1, runs do
			local tiles = { ["1_1"] = { c = "radish", at = -1000, m = 0 } }
			for t = first, last, W.TickSeconds do
				Mutation.strikeTick(tiles, kind, t, r, W, M, byId)
			end
			if tiles["1_1"].m ~= 0 then hits += 1 end
		end
		local p = hits / runs
		local sd = math.sqrt(W.Chance[kind] * (1 - W.Chance[kind]) / runs)
		print(string.format("  %s: %d of %d whole-event crops marked = %.4f (published %.2f)", kind, hits, runs, p, W.Chance[kind]))
		truthy(math.abs(p - W.Chance[kind]) <= 4 * sd, kind .. ": measured odds within 4 sd of the published chance")
	end
end

print(string.format("Mutation: %d passed, %d failed", passed, failed))
assert(failed == 0, "Mutation tests failed")
