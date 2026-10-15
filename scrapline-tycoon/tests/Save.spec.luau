-- Save — the profile's defaults, the normaliser for whatever the DataStore hands back, and exactly what is
-- written. Run: luau tests/Save.spec.luau
--
-- DESIGN.md section 11.1. A loaded record is untrusted input: an older version, a hand edit, a JSON round trip
-- (which turns sparse integer keys into strings), a NaN. normalise() makes any of it safe: numbers clamped and
-- floored, the unlock rule repaired (a station whose predecessor is unbuilt is unbuilt), jams clamped to the
-- machines that exist. pack() writes string keys only, and a live sputter as a jam.

local Config = require("../src/shared/Config")
local Save = require("../src/shared/Save")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local C = Config
local IDS = C.Stations.Order

--============================================================================ defaults
do
	local d = Save.defaults(C)
	eq(d.v, 1, "version 1")
	eq(d.cash, 0, "no cash")
	eq(d.tier, 0, "tier 0 (the Junkyard)")
	eq(d.bolts, 0, "no Gold Bolts")
	eq(d.boltsAt, 0, "never reached a bolt")
	eq(d.tutorial, 0, "the first hint")
	eq(d.jams.jamIn, 240, "the first sputter is 240 s of line time away")
	eq(d.jams.sputter, nil, "nothing sputtering")
	for _, id in IDS do
		local s = d.stations[id]
		truthy(s ~= nil and s.n == 0 and s.L == 1 and s.jam[1] == 0 and s.jam[2] == 0, id .. " starts unbuilt at level 1")
	end
	local d2 = Save.defaults(C)
	d2.stations.shredder.n = 1
	eq(Save.defaults(C).stations.shredder.n, 0, "defaults() hands out a fresh table every time")
end

--============================================================================ normalise
do
	eq(Save.normalise(C, nil).cash, 0, "nil loads as a new profile")
	eq(Save.normalise(C, "garbage" :: any).bolts, 0, "a string loads as a new profile")
	local n = Save.normalise(C, {
		cash = -50, tier = 9.7, bolts = 3.9, boltsAt = 1790000000.4, tutorial = 11, jamIn = 0 / 0, junk = { 1, 2 }, v = 99,
		stations = {
			shredder = { n = 5, L = 0, j = 9 },
			furnace = { n = 1.6, L = 12.9, j = -1 },
			press = { n = 2, L = math.huge, j = 1 },
			cutter = "nope",
			assembler = { n = 2, L = 3 }, -- its predecessor (the Cutter) is unbuilt: the unlock rule repairs it
			rocketbay = { n = 1, L = 1, j = 0 },
		},
	})
	eq(n.cash, 0, "negative cash loads as 0")
	eq(n.tier, 6, "the tier is clamped to 6 and floored")
	eq(n.bolts, 3, "bolts are floored")
	eq(n.boltsAt, 1790000000, "boltsAt is floored")
	eq(n.tutorial, 4, "the tutorial is clamped to 4")
	eq(n.jams.jamIn, 240, "a NaN jam clock loads as a new profile's")
	eq(n.junk, nil, "unknown fields are dropped")
	eq(n.v, 1, "the version is the current one")
	eq(n.stations.shredder.n, 2, "n is clamped to 2")
	eq(n.stations.shredder.L, 1, "a level below 1 loads as 1")
	eq(n.stations.shredder.jam[1] + n.stations.shredder.jam[2], 4, "j is clamped to n (both machines jammed)")
	eq(n.stations.furnace.n, 1, "n is floored")
	eq(n.stations.furnace.L, 12, "L is floored")
	eq(n.stations.furnace.jam[1], 0, "a negative jam count loads as 0")
	eq(n.stations.press.L, 1, "an infinite level loads as the default")
	eq(n.stations.press.jam[1], 2, "one jammed machine: machine a")
	eq(n.stations.press.jam[2], 0, "...machine b runs")
	eq(n.stations.cutter.n, 0, "a non-table station loads unbuilt")
	eq(n.stations.assembler.n, 0, "the unlock rule holds for any record: an Assembler without a Cutter loads unbuilt")
	eq(n.stations.rocketbay.n, 0, "...and so does everything after it")
	local capped = Save.normalise(C, { stations = { shredder = { n = 1, L = 5000 } } })
	eq(capped.stations.shredder.L, C.Stations.MaxLevel, "a level past the cap loads at the cap")
	eq(Save.normalise(C, { jamIn = 999 }).jams.jamIn, 240, "a jam clock past the longest gap is clamped (to the first-sputter 240)")
	eq(Save.normalise(C, { jamIn = 33.5 }).jams.jamIn, 33.5, "a sane jam clock is kept, fractions too")
	eq(Save.normalise(C, { jamIn = -4 }).jams.jamIn, 0, "never negative")
	local fine = Save.normalise(C, { cash = 1234.5, tier = 3, bolts = 2, boltsAt = 1790000000, tutorial = 4, jamIn = 120,
		stations = { shredder = { n = 2, L = 14, j = 0 }, furnace = { n = 2, L = 10, j = 1 }, press = { n = 1, L = 3, j = 0 } } })
	eq(fine.cash, 1234.5, "a sane record keeps its cash")
	eq(fine.stations.furnace.L, 10, "and its levels")
	eq(fine.stations.furnace.jam[1], 2, "and its jams")
	eq(fine.stations.press.n, 1, "and its machines")
	eq(fine.jams.sputter, nil, "a load never starts with a live sputter (a saved sputter is a jam)")
end

--============================================================================ pack: what is written
local function keysAllStrings(v, path, bad)
	if type(v) ~= "table" then return end
	for k, x in v do
		if type(k) ~= "string" then table.insert(bad, path .. "[" .. tostring(k) .. "]") end
		keysAllStrings(x, path .. "." .. tostring(k), bad)
	end
end
do
	local d = Save.normalise(C, { cash = 7, bolts = 1, boltsAt = 1790000000, jamIn = 50, tier = 2,
		stations = { shredder = { n = 2, L = 5, j = 0 }, furnace = { n = 1, L = 2, j = 0 } } })
	-- a live sputter on the Shredder's twin
	d.stations.shredder.jam[2] = 1
	d.jams.sputter = { t = 1, m = 2, left = 9 }
	local p = Save.pack(C, d)
	local bad = {}
	keysAllStrings(p, "data", bad)
	eq(#bad, 0, "no integer keys anywhere in a written profile (" .. table.concat(bad, ", ") .. ")")
	local fields = {}
	for k in p do table.insert(fields, k) end
	table.sort(fields)
	eq(table.concat(fields, ","), "bolts,boltsAt,cash,jamIn,stations,tier,tutorial,v", "exactly the documented fields are written")
	eq(p.stations.shredder.j, 1, "a live sputter is written as a jam (a rejoin never clears it)")
	eq(p.stations.shredder.n, 2, "n carried over")
	eq(p.stations.shredder.L, 5, "L carried over")
	eq(p.stations.furnace.j, 0, "a running station writes j = 0")
	eq(p.jamIn, 50, "the jam clock is written")
	eq(p.cash, 7, "cash")
	p.cash = 999
	p.stations.shredder.n = 0
	eq(d.cash, 7, "pack() writes a copy, not the live profile")
	eq(d.stations.shredder.n, 2, "...all the way down")
	local back = Save.normalise(C, Save.pack(C, d))
	eq(back.stations.shredder.jam[1], 2, "pack -> normalise: the sputter came back as a jam (on machine a: machines are identical)")
	eq(back.stations.shredder.jam[1] + back.stations.shredder.jam[2], 2, "...exactly one machine")
	eq(back.bolts, 1, "pack -> normalise is a round trip for the rest")
	eq(back.stations.furnace.L, 2, "levels too")
end

print(string.format("Save: %d passed, %d failed", passed, failed))
if failed > 0 then error("Save spec failed", 0) end
