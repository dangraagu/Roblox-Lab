-- Spec for Profile: the saved document, and what a load repairs. Run: luau tests/Profile.spec.luau
--
-- DESIGN.md §8.1. One document per player under "u_<userId>". String keys everywhere (the emulator's
-- DataStore does the same JSON round trip Roblox does, so an integer key would come back a string). A load
-- repairs what it cannot trust and logs each fix; it never invents progress.
local Profile = require("../src/shared/Profile")
local Mutation = require("../src/shared/Mutation")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local NOW = 1790002800

--================================================================ the default

do
	local p = Profile.default(Config)
	eq(p.v, 1, "version 1")
	eq(p.coins, 20, "20 start coins")
	eq(p.harvested, 0, "nothing harvested")
	eq(p.fields, 1, "one field")
	eq(p.unlocked, 1, "one crop owned")
	eq(p.selected, "radish", "Radish selected")
	eq(next(p.tiles), nil, "no tiles")
	eq(next(p.almanac), nil, "an empty Almanac")
	eq(p.almanacCount, 0, "count 0")
	eq(p.session, nil, "the default carries no session: the load's own transform writes that")
	-- every key in the profile is a string, at every depth
	local function allStringKeys(t)
		for k, v in t do
			if type(k) ~= "string" then return false end
			if type(v) == "table" and not allStringKeys(v) then return false end
		end
		return true
	end
	truthy(allStringKeys(p), "only string keys")
	local full = Profile.default(Config)
	full.tiles["1_1"] = { c = "radish", at = NOW, m = 3 }
	full.almanac["radish:3"] = NOW
	truthy(allStringKeys(full), "a used profile still has only string keys")
end

--================================================================ normalize

do
	local p, fixes = Profile.normalize(nil, Config, NOW)
	eq(p.coins, 20, "nil loads as the default")
	eq(#fixes, 0, "with nothing to fix")
end

do
	local raw = {
		v = 1, coins = 500.7, harvested = 1234, fields = 2, unlocked = 3, selected = "corn",
		tiles = {
			["1_1"] = { c = "radish", at = NOW - 100, m = 1 }, -- fine
			["1_2"] = { c = "banana", at = NOW - 100, m = 0 }, -- unknown crop: cleared
			["1_3"] = { c = "carrot", at = NOW - 100, m = 9 }, -- marks out of range: marks cleared
			["1_4"] = { c = "corn", at = NOW + 5000, m = 0 }, -- planted in the future: clamped to now
			["3_1"] = { c = "radish", at = NOW - 100, m = 0 }, -- field 3 is not owned: dropped
			["x_y"] = { c = "radish", at = NOW, m = 0 }, -- junk key: dropped
			["1_5"] = "junk", -- junk record: dropped
		},
		almanac = { ["radish:1"] = NOW - 50, ["banana:1"] = NOW, ["radish:0"] = NOW, ["corn:8"] = NOW },
		almanacCount = 44, almanacAt = NOW - 50, harvests = 12,
		session = { token = "abc", lockUntil = NOW + 100 },
	}
	local p, fixes = Profile.normalize(raw, Config, NOW)
	eq(p.coins, 500, "coins are whole")
	eq(p.tiles["1_1"].m, 1, "a good tile is kept with its marks")
	eq(p.tiles["1_2"], nil, "an unknown crop is cleared")
	eq(p.tiles["1_3"].m, 0, "out-of-range marks are cleared")
	eq(p.tiles["1_3"].c, "carrot", "but the crop stays")
	eq(p.tiles["1_4"].at, NOW, "a planting time in the future is clamped to now")
	eq(p.tiles["3_1"], nil, "a tile beyond the owned fields is dropped")
	eq(p.tiles["x_y"], nil, "a junk key is dropped")
	eq(p.tiles["1_5"], nil, "a junk record is dropped")
	eq(p.almanac["radish:1"], NOW - 50, "a valid Almanac entry is kept")
	eq(p.almanac["banana:1"], nil, "an entry naming no crop is dropped")
	eq(p.almanac["radish:0"], nil, "plain is never an entry")
	eq(p.almanac["corn:8"], nil, "marks above 7 are no entry")
	eq(p.almanacCount, 1, "the count is recounted from what remains (it said 44)")
	eq(p.session, nil, "the stored session is not part of the in-memory profile")
	truthy(#fixes >= 7, "each fix is reported (" .. #fixes .. ")")
end

do
	-- a selection above what is owned falls back to the newest owned crop; out-of-range counts clamp
	local p = Profile.normalize({ coins = -5, harvested = "x", fields = 99, unlocked = 0, selected = "stormfruit" }, Config, NOW)
	eq(p.coins, 0, "negative coins become 0")
	eq(p.harvested, 0, "a junk harvested becomes 0")
	eq(p.fields, 6, "fields clamp to 6")
	eq(p.unlocked, 1, "unlocked clamps to at least 1")
	eq(p.selected, "radish", "the selection falls back to the newest owned crop")
	local q = Profile.normalize({ unlocked = 4, selected = "stormfruit" }, Config, NOW)
	eq(q.selected, "tomato", "with 4 owned, a stormfruit selection falls back to Tomato")
	local r = Profile.normalize("garbage", Config, NOW)
	eq(r.coins, 20, "a non-table record loads as the default")
end

do
	-- integer-keyed almanac/tiles from an old or hand-edited record normalise to strings
	local p = Profile.normalize({ tiles = { [1] = { c = "radish", at = NOW, m = 0 } }, almanac = { [5] = NOW } }, Config, NOW)
	eq(next(p.tiles), nil, "an integer tile key is not a tile key")
	eq(next(p.almanac), nil, "an integer almanac key is not an entry")
end

--================================================================ serialize

do
	local p = Profile.default(Config)
	p.tiles["1_1"] = { c = "radish", at = NOW, m = 1 }
	Mutation.grant(p, "radish", 1, NOW)
	p.runtimeOnly = function() end
	local doc = Profile.serialize(p)
	eq(doc.runtimeOnly, nil, "serialize keeps only the saved fields")
	eq(doc.tiles["1_1"].m, 1, "tiles are saved")
	eq(doc.almanac["radish:1"], NOW, "the Almanac is saved")
	truthy(doc.tiles ~= p.tiles, "a copy, so a later tap cannot change a write in flight")
	-- round trip
	local back = Profile.normalize(doc, Config, NOW)
	eq(back.almanacCount, 1, "round trip keeps the count")
	eq(back.tiles["1_1"].c, "radish", "and the tiles")
end

-- a record from a NEWER version of the game (REVIEW-1 A4): this version must recognise it and never write it, or a
-- player who hops from an updated server to an old one loses what the update added (normalize drops what it does
-- not know, and the load would write that back)
do
	eq(Profile.VERSION, 1, "this version writes v = 1")
	eq(Profile.default(Config).v, Profile.VERSION, "and a new profile carries it")
	eq(Profile.isNewer({ v = 2 }), true, "a v = 2 record is newer")
	eq(Profile.isNewer({ v = "2" }), true, "however the number was stored")
	eq(Profile.isNewer({ v = 1 }), false, "a v = 1 record is not")
	eq(Profile.isNewer({ coins = 5 }), false, "a record without v is the first version")
	eq(Profile.isNewer(nil), false, "no record is not newer")
	eq(Profile.isNewer("junk"), false, "junk is not newer (normalize repairs it)")
end

print(string.format("Profile: %d passed, %d failed", passed, failed))
assert(failed == 0, "Profile tests failed")
