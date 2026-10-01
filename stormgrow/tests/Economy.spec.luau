-- Spec for Economy: plant, harvest, unlock, select, buy a field. Run: luau tests/Economy.spec.luau
--
-- One tap on a tile does everything a farm action can: harvest a ripe crop (it sells on the spot, x its
-- marks) and replant the selected seed. The server runs these functions on its own profile table and
-- trusts nothing from the client; every refusal comes back with the words the player sees
-- (checklist: no silent no-ops). DESIGN.md §2.3, §2.4, §12.3.
local Economy = require("../src/shared/Economy")
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
local function has(text, needle, msg)
	truthy(type(text) == "string" and string.find(text, needle, 1, true) ~= nil, msg .. " (" .. tostring(text) .. ")")
end

local function fresh()
	return {
		coins = Config.StartCoins, harvested = 0, fields = 1, unlocked = 1, selected = "radish",
		tiles = {}, almanac = {}, almanacCount = 0, almanacAt = 0, harvests = 0,
	}
end

local T = 1790002800

--================================================================ planting on an empty tile

do
	local p = fresh()
	local r = Economy.tap(p, Config, "1_1", T)
	truthy(r.ok, "a tap on an empty owned tile plants")
	eq(r.planted, "radish", "the selected seed (Radish)")
	eq(r.harvest, nil, "nothing was harvested")
	eq(p.tiles["1_1"].c, "radish", "the tile holds a Radish")
	eq(p.tiles["1_1"].at, T, "planted now, on the server clock")
	eq(p.tiles["1_1"].m, 0, "with no marks")
	eq(p.coins, 20, "Radish seeds are free")
	-- with 0 coins you can still plant
	local broke = fresh()
	broke.coins = 0
	truthy(Economy.tap(broke, Config, "1_2", T).ok, "a player with 0 coins can always plant a Radish")
end

--================================================================ the planting time survives a save

do
	-- The server clock is fractional (Unix seconds + tick() differences). A DataStore stores JSON, and the
	-- emulator's encoder keeps 14 significant digits (Roblox's precision is not documented): 1790002800.123456
	-- would come back as 1790002800.1235 and a rejoin would see every crop planted at a different time
	-- (tests/walk.luau found this: 0 of 18 tiles came back identical). So the planting time is kept to the
	-- millisecond: 10 + 3 = 13 significant digits, exact through a 14-digit round trip.
	local p = fresh()
	Economy.tap(p, Config, "1_1", T + 0.123456)
	local at = p.tiles["1_1"].at
	eq(at, T + 0.123, "the planting time is stored to the millisecond")
	eq(tonumber(string.format("%.14g", at)), at, "and survives a 14-significant-digit JSON round trip unchanged")
end

--================================================================ a growing crop refuses, with the time left

do
	local p = fresh()
	Economy.tap(p, Config, "1_1", T)
	local r = Economy.tap(p, Config, "1_1", T + 18)
	eq(r.ok, false, "a growing crop cannot be harvested")
	eq(r.reason, "growing", "the reason is 'growing'")
	has(r.text, "Ripe in 0:12", "and the player is told when")
	eq(p.tiles["1_1"].at, T, "the crop is untouched")
	eq(Economy.tap(p, Config, "1_1", T + 29.99).ok, false, "not a moment early")
end

--================================================================ harvest + replant in one tap

do
	local p = fresh()
	Economy.tap(p, Config, "1_1", T)
	local r = Economy.tap(p, Config, "1_1", T + 30)
	truthy(r.ok, "a ripe crop is harvested exactly at at + grow")
	eq(r.harvest.value, 5, "a plain Radish sells for 5")
	eq(p.coins, 25, "coins went up by 5")
	eq(p.harvested, 5, "lifetime harvest went up by 5")
	eq(p.harvests, 1, "one harvest counted")
	eq(r.planted, "radish", "and the same tap replanted")
	eq(p.tiles["1_1"].at, T + 30, "the new crop is planted now")
end
do
	-- marks multiply the sale
	local p = fresh()
	p.tiles["1_1"] = { c = "pumpkin", at = T - 1000, m = 7 }
	p.unlocked = 6
	p.selected = "pumpkin"
	p.coins = 0
	local r = Economy.tap(p, Config, "1_1", T)
	eq(r.harvest.value, 2400 * 200, "a Tempest Pumpkin sells for 2,400 x 200")
	eq(r.harvest.marks, 7, "the harvest reports its marks")
	eq(p.harvested, 480000, "all of it counts toward the bands")
	eq(p.tiles["1_1"].c, "pumpkin", "and a fresh Pumpkin goes in (the sale paid for the seed)")
	eq(p.tiles["1_1"].m, 0, "with no marks: marks belong to the crop, not the tile")
end

--================================================================ can't afford the selected seed: the best you can

do
	local p = fresh()
	p.unlocked = 3
	p.selected = "corn"
	p.coins = 12
	local r = Economy.tap(p, Config, "1_1", T)
	truthy(r.ok, "a tap you cannot afford still plants")
	eq(r.planted, "carrot", "the best crop you can afford (Carrot, 5)")
	eq(r.fallback and r.fallback.wanted, "corn", "and says what you wanted")
	has(r.text, "Corn costs 20, you have 12", "the player is told why")
	has(r.text, "planted a Carrot (5) instead", "and what happened instead")
	eq(p.coins, 7, "the Carrot seed was paid")
	eq(p.selected, "corn", "the selection is kept for the next tap")
end

--================================================================ fields

do
	local p = fresh()
	local r = Economy.tap(p, Config, "2_1", T)
	eq(r.ok, false, "a tile on a field you do not own refuses")
	eq(r.reason, "locked", "reason: locked")
	has(r.text, "Field 2", "names the field")
	has(r.text, "400", "and its price")
	eq(p.tiles["2_1"], nil, "and plants nothing")
	local r5 = Economy.tap(p, Config, "5_1", T)
	has(r5.text, "Field 5", "a field further out names itself")
	eq(Economy.tap(p, Config, "7_1", T).reason, "badKey", "a field that does not exist is refused")
	eq(Economy.tap(p, Config, "1_10", T).reason, "badKey", "a tile that does not exist is refused")
	eq(Economy.tap(p, Config, "x", T).reason, "badKey", "junk is refused")

	eq(Economy.nextFieldPrice(p, Config), 400, "field 2 costs 400")
	local ok, text = Economy.buyField(p, Config)
	eq(ok, false, "20 coins cannot buy field 2")
	has(text, "Next field: 400", "and says the price")
	has(text, "you have 20", "and what you have")
	p.coins = 400
	ok = Economy.buyField(p, Config)
	eq(ok, true, "400 coins buy field 2")
	eq(p.fields, 2, "fields = 2")
	eq(p.coins, 0, "paid in full")
	truthy(Economy.tap(p, Config, "2_1", T).ok, "and its tiles plant")
	p.fields, p.coins = 6, 1e12
	local ok6, text6 = Economy.buyField(p, Config)
	eq(ok6, false, "there is no seventh field")
	has(text6, "All six fields", "and it says so")
end

--================================================================ unlocking crops, strictly in order

do
	local p = fresh()
	local ok, text = Economy.unlock(p, Config)
	eq(ok, false, "20 coins cannot unlock the Carrot")
	has(text, "Unlock Carrot for 50", "names the next crop and its price")
	has(text, "you have 20", "and what you have")
	p.coins = 50
	ok = Economy.unlock(p, Config)
	eq(ok, true, "50 coins unlock the Carrot")
	eq(p.unlocked, 2, "two crops owned (the owned set is a count)")
	eq(p.selected, "carrot", "a new crop becomes the selected seed")
	eq(p.coins, 0, "paid")
	-- Stormfruit is gated on the Eye of the Storm
	p.unlocked, p.coins, p.harvested = 7, 1e9, 299999
	ok, text = Economy.unlock(p, Config)
	eq(ok, false, "Stormfruit is refused below the brag threshold, however rich you are")
	has(text, "Eye of the Storm", "and says where it grows")
	has(text, "300,000", "and the number to reach")
	p.harvested = 300000
	ok = Economy.unlock(p, Config)
	eq(ok, true, "at 300,000 harvested it unlocks")
	ok, text = Economy.unlock(p, Config)
	eq(ok, false, "nothing after the Stormfruit")
	has(text, "Every crop", "and it says so")
end

--================================================================ selecting a seed

do
	local p = fresh()
	p.unlocked = 3
	eq((Economy.select(p, Config, "carrot")), true, "an owned crop can be selected")
	eq(p.selected, "carrot", "selected")
	local ok, text = Economy.select(p, Config, "tomato")
	eq(ok, false, "a locked crop cannot be selected")
	has(text, "Unlock Tomato first", "and it says so")
	eq(p.selected, "carrot", "the selection is unchanged")
	eq((Economy.select(p, Config, "nope")), false, "an unknown id is refused")
	eq((Economy.select(p, Config, 7)), false, "a non-string is refused")
	-- ownership is NEVER inferred from the selection: planting reads `unlocked`
	p.selected = "stormfruit" -- a corrupted selection
	p.coins = 1e9
	local r = Economy.tap(p, Config, "1_1", T)
	eq(r.planted, "corn", "a selection above what you own plants the newest crop you own")
end

--================================================================ invariants over random play

do
	local s = 12345
	local function r()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
	local p = fresh()
	local now = T
	local negative, drops, overUnlock = 0, 0, 0
	for _ = 1, 20000 do
		now += r() * 20
		local before = p.harvested
		local x = r()
		if x < 0.7 then
			Economy.tap(p, Config, math.floor(1 + r() * 6) .. "_" .. math.floor(1 + r() * 9), now)
		elseif x < 0.8 then
			Economy.unlock(p, Config)
		elseif x < 0.9 then
			Economy.buyField(p, Config)
		else
			Economy.select(p, Config, Config.Crops[math.floor(1 + r() * 8)].id)
		end
		if p.coins < 0 then negative += 1 end
		if p.harvested < before then drops += 1 end
		if Economy.cropIndex(Config.Crops, p.selected) > p.unlocked then overUnlock += 1 end
	end
	eq(negative, 0, "coins never go negative over 20,000 random actions")
	eq(drops, 0, "lifetime harvest never goes down")
	eq(overUnlock, 0, "the selection never exceeds what is owned")
	truthy(p.harvests > 100, "set-up: the random walk actually harvested (" .. p.harvests .. ")")
end

print(string.format("Economy: %d passed, %d failed", passed, failed))
assert(failed == 0, "Economy tests failed")
