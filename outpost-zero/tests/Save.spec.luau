-- Save — the profile's defaults, the normaliser for whatever the DataStore hands back, and what gets written.
-- Run: luau tests/Save.spec.luau
--
-- A loaded record is untrusted input: an older or newer version, a hand edit, a JSON round trip (which turns sparse
-- integer keys into strings), a NaN. normalise() makes any of it safe (DESIGN 10.1): a non-number gives the
-- default, a negative gives 0, storeys are floored and clamped to 0..22, NaN or infinity gives the default, a
-- seed outside its range is flagged for a redraw, and a record newer than v1 is flagged so it is never written.

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

--============================================================================ defaults
do
	local d = Save.defaults(C)
	eq(d.v, 1, "version 1")
	eq(d.seed, 0, "no seed yet (the server draws one)")
	eq(d.credits, 30, "30 starting credits: the first Home and the first Workshop")
	eq(d.lifetime, 0, "nothing earned yet")
	eq(next(d.lots), nil, "no lots built")
	eq(d.savedAt, 0, "never saved")
	eq(d.ordersUntil, 0, "no Orders")
	eq(d.popAt, 0, "never reached a population")
	eq(d.airshipSeen, false, "the airship not seen")
	eq(d.tutorial, 0, "the first hint")
	local d2 = Save.defaults(C)
	d2.lots["1_1"] = 3
	eq(Save.defaults(C).lots["1_1"], nil, "defaults() hands out a fresh table every time")
end

--============================================================================ normalise
do
	local d, info = Save.normalise(C, nil)
	eq(info.fresh, true, "nil is a fresh profile")
	eq(info.reseed, true, "which needs a seed")
	eq(d.credits, 30, "with the starting credits")
	d, info = Save.normalise(C, "garbage")
	eq(info.fresh, true, "a non-table is a fresh profile too")

	local raw = {
		v = 1, seed = 4242, credits = 1234.5, lifetime = 99999, savedAt = 1790000000, ordersUntil = 1790000300,
		popAt = 1789999000, airshipSeen = true, tutorial = 3,
		lots = { ["1_1"] = 7, ["1_2"] = 6.9, ["2_3"] = 40, ["3_4"] = -2, ["6_6"] = 22, ["7_1"] = 5, ["1_0"] = 3,
			["x"] = 1, ["4_4"] = 0 / 0, ["5_5"] = "9" },
	}
	d, info = Save.normalise(C, raw)
	eq(info.fresh, false, "a real record is not fresh")
	eq(info.reseed, false, "a valid seed is kept")
	eq(info.future, false, "v1 is not from the future")
	eq(d.seed, 4242, "the seed")
	eq(d.credits, 1234.5, "fractional credits are kept")
	eq(d.lifetime, 99999, "lifetime")
	eq(d.savedAt, 1790000000, "savedAt")
	eq(d.ordersUntil, 1790000300, "ordersUntil")
	eq(d.popAt, 1789999000, "popAt")
	eq(d.airshipSeen, true, "airshipSeen")
	eq(d.tutorial, 3, "tutorial")
	eq(d.lots["1_1"], 7, "storeys")
	eq(d.lots["1_2"], 6, "fractional storeys are floored")
	eq(d.lots["2_3"], 22, "storeys are clamped to 22")
	eq(d.lots["3_4"], nil, "a negative storey count is 0 (absent)")
	eq(d.lots["6_6"], 22, "a topped-out lot")
	eq(d.lots["7_1"], nil, "district 7 does not exist")
	eq(d.lots["1_0"], nil, "lot 0 does not exist")
	eq(d.lots["x"], nil, "a junk key is dropped")
	eq(d.lots["4_4"], nil, "NaN storeys are dropped")
	eq(d.lots["5_5"], nil, "a string storey count is dropped")
	-- garbage scalars
	d = Save.normalise(C, { v = 1, seed = 4242, credits = -5, lifetime = 0 / 0, tutorial = 9, savedAt = math.huge, airshipSeen = "yes", lots = 5 })
	eq(d.credits, 0, "negative credits become 0")
	eq(d.lifetime, 0, "NaN lifetime becomes the default")
	eq(d.tutorial, 3, "the tutorial step is clamped to 3")
	eq(d.savedAt, 0, "an infinite savedAt becomes the default")
	eq(d.airshipSeen, false, "airshipSeen must be a real boolean")
	eq(next(d.lots), nil, "a non-table lots field is an empty city")
	d = Save.normalise(C, { v = 1, seed = 4242, credits = "lots" })
	eq(d.credits, 30, "non-number credits give the default")
	-- integer keys from an old JSON round trip are refused (string keys only)
	d = Save.normalise(C, { v = 1, seed = 4242, lots = { [1] = 5 } })
	eq(next(d.lots), nil, "an integer lot key is dropped")
	-- the seed
	local _, i1 = Save.normalise(C, { v = 1, seed = 0 })
	eq(i1.reseed, true, "seed 0 is redrawn")
	local _, i2 = Save.normalise(C, { v = 1, seed = 2147483647 })
	eq(i2.reseed, true, "a seed over SeedMax is redrawn")
	local _, i3 = Save.normalise(C, { v = 1, seed = 12.5 })
	eq(i3.reseed, true, "a fractional seed is redrawn")
	local _, i4 = Save.normalise(C, { v = 1, seed = 2147483646 })
	eq(i4.reseed, false, "SeedMax itself is valid")
	-- the version guard
	local d5, i5 = Save.normalise(C, { v = 2, seed = 4242, credits = 50 })
	eq(i5.future, true, "a v2 record is flagged: it is never written by this version")
	eq(d5.credits, 50, "but it can still be played in memory")
	-- lifetime never below the credits on hand
	d = Save.normalise(C, { v = 1, seed = 4242, credits = 500, lifetime = 100 })
	eq(d.lifetime, 500, "lifetime is at least the credits on hand")
end

--============================================================================ pack: exactly the documented fields, string keys
do
	local d = Save.normalise(C, { v = 1, seed = 4242, credits = 10, lots = { ["1_1"] = 3, ["2_2"] = 1 } })
	d.junk = "x"
	local p = Save.pack(d)
	eq(p.v, 1, "pack writes the version")
	eq(p.seed, 4242, "the seed")
	eq(p.credits, 10, "the credits")
	eq(p.junk, nil, "nothing undocumented")
	eq(p.lots["1_1"], 3, "lots")
	truthy(p.lots ~= d.lots, "a copy of the lots, not the live table")
	local intKeys = 0
	for k in p.lots do if type(k) ~= "string" then intKeys += 1 end end
	eq(intKeys, 0, "every lot key is a string")
	local fields = 0
	for _ in p do fields += 1 end
	eq(fields, 10, "ten fields: v, seed, credits, lifetime, lots, savedAt, ordersUntil, popAt, airshipSeen, tutorial")
end

print(string.format("Save: %d passed, %d failed", passed, failed))
if failed > 0 then error("Save spec failed", 0) end
