-- Economy.spec — salvage, the splice, leaving, the upgrade ladder and the saved profile (DESIGN.md §9, §11).
-- Run: luau tests/Economy.spec.luau
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

--================================================================ value, bonus, keep
eq(Economy.value(Config, 1), 5, "value(1) = 5")
eq(Economy.value(Config, 23), 27, "value(23) = 27")
eq(Economy.bonus(Config, 1), 10, "bonus(1) = 10")
eq(Economy.bonus(Config, 30), 68, "bonus(30) = 68")
eq(Economy.keep(Config, 35), 17, "keep(35) = 17: floor(35 / 2)")
eq(Economy.keep(Config, 0), 0, "keep(0) = 0")
eq(Economy.keep(Config, 1), 0, "keep(1) = 0")
eq(Economy.keep(Config, 2), 1, "keep(2) = 1")
do
	local exact = true
	for c = 0, 5000 do
		if Economy.keep(Config, c) ~= math.floor(c / 2) or Economy.keep(Config, c) % 1 ~= 0 then exact = false end
	end
	truthy(exact, "keep is exact integer arithmetic for 0..5000")
end

--================================================================ the ladder
eq(Economy.price(Config, "tank", 0), 120, "tank rank 1 costs 120")
eq(Economy.price(Config, "boots", 3), 1000, "boots rank 4 costs 1000")
eq(Economy.price(Config, "tank", 4), nil, "no price past the max")
eq(Economy.price(Config, "receiver", 0), nil, "an upgrade that does not exist has no price (the RECEIVER was cut)")
eq(Economy.price(Config, 5, 0), nil, "a non-string id has no price")
do
	local fx = Economy.effects(Config, { tank = 2, boots = 3 })
	eq(fx.tank, 30, "Air Tank rank 2: a 30 s tank")
	eq(fx.vacSpeed, 15, "Mag-Boots rank 3: 15 studs/s in vacuum")
	local zero = Economy.effects(Config, {})
	eq(zero.tank, 20, "no upgrades: 20 s")
	eq(zero.vacSpeed, 12, "no upgrades: 12 studs/s")
end

--================================================================ the profile
do
	local p = Economy.newProfile(Config)
	eq(p.v, 1, "schema version 1")
	eq(p.salvage, 0, "a new wallet is empty")
	eq(p.best, 0, "no relays yet")
	eq(p.up.tank, 0, "tank rank 0")
	eq(p.up.boots, 0, "boots rank 0")
	eq(p.open, nil, "no open sector")
	eq(p.arrayAt, nil, "the Main Array not yet restored")
end

-- A stand-in for the DataStore's JSON round trip: sparse integer keys come back as STRINGS (the checklist trap).
local function jsonTrip(v)
	if type(v) ~= "table" then return v end
	local n = #v
	local sparse = false
	for k in v do
		if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then sparse = true end
	end
	local out = {}
	for k, x in v do
		out[if sparse then tostring(k) else k] = jsonTrip(x)
	end
	return out
end
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, x in a do if not same(x, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end

do
	local p = Economy.newProfile(Config)
	p.salvage, p.salvageEarned, p.best, p.bestAt, p.arrayAt = 740, 3100, 31, 1790000000, 1789990000
	p.up.tank, p.up.boots = 3, 2
	p.blackouts, p.attempts = 4, 40
	p.open = { id = "abc-123", k = 32, carried = 70 }
	local back = Economy.sanitize(Config, jsonTrip(p))
	truthy(same(back, p), "a profile survives the JSON round trip unchanged")
end
do
	local raw = { salvage = -5, best = "31", bestAt = 0 / 0, up = { tank = 9, boots = -1, receiver = 4, [1] = 2 },
		open = { id = 7, k = 3, carried = 10 }, junk = true, blackouts = 2.7 }
	local p = Economy.sanitize(Config, raw)
	eq(p.salvage, 0, "a negative wallet is clamped to 0")
	eq(p.best, 0, "a non-number best is dropped")
	eq(p.bestAt, 0, "a NaN bestAt is dropped")
	eq(p.up.tank, 4, "a rank past the max is clamped")
	eq(p.up.boots, 0, "a negative rank is clamped")
	eq(p.up.receiver, nil, "unknown upgrade keys are dropped")
	eq(p.up[1], nil, "integer keys are dropped")
	eq(p.open, nil, "a malformed open sector (non-string id) is dropped")
	eq(p.junk, nil, "unknown fields are dropped")
	eq(p.blackouts, 2, "counts are floored")
	local keys = {}
	for k in p.up do table.insert(keys, type(k)) end
	eq(table.concat(keys, ","), "string,string", "the upgrade table has string keys only")
	eq(Economy.sanitize(Config, "nonsense").salvage, 0, "a non-table record gives a new profile")
end

--================================================================ a sector: begin, carry, splice
do
	local p = Economy.newProfile(Config)
	Economy.beginSector(p, "g1", 1)
	eq(p.attempts, 1, "a sector attempt is counted")
	eq(p.open.k, 1, "the open sector is k = 1")
	Economy.carry(Config, p, 1)
	Economy.carry(Config, p, 1)
	eq(p.open.carried, 10, "two sector-1 pieces: 10 carried")
	local r = Economy.splice(Config, p, 1, 1790000100)
	eq(r.paid, 20, "the splice banks carried + bonus(1) = 10 + 10")
	eq(p.salvage, 20, "into the wallet")
	eq(p.salvageEarned, 20, "and the lifetime count")
	eq(p.best, 1, "best = 1")
	eq(p.bestAt, 1790000100, "reached at the server's time")
	eq(r.record, true, "a new record")
	eq(p.open, nil, "the open sector is cleared IN THE SAME STEP that pays it")
	eq(Economy.settle(Config, p, "left"), 0, "leaving after the splice pays nothing more")
	eq(p.salvage, 20, "the wallet is unchanged")
end
do
	-- a replayed sector below the best does not move bestAt; the Main Array is stamped once
	local p = Economy.newProfile(Config)
	p.best, p.bestAt = 29, 100
	Economy.beginSector(p, "g2", 30)
	local r = Economy.splice(Config, p, 30, 200)
	eq(r.array, true, "splicing relay 30 restores the Main Array")
	eq(p.arrayAt, 200, "arrayAt is written")
	Economy.beginSector(p, "g3", 30)
	local r2 = Economy.splice(Config, p, 30, 300)
	eq(r2.array, false, "a second relay 30 is not a second Main Array")
	eq(p.arrayAt, 200, "arrayAt is written once")
	eq(p.bestAt, 200, "the same best reached later does not move bestAt (ties go to the first)")
	eq(r2.record, false, "and is not a record")
	Economy.beginSector(p, "g4", 31)
	Economy.splice(Config, p, 31, 400)
	eq(p.best, 31, "best rises")
	eq(p.bestAt, 400, "and bestAt with it")
end

--================================================================ every way out pays the same, once
for _, reason in { "blackout", "return", "reset", "left", "shutdown", "crashed" } do
	local p = Economy.newProfile(Config)
	Economy.beginSector(p, "g-" .. reason, 10)
	for _ = 1, 3 do Economy.carry(Config, p, 10) end
	eq(p.open.carried, 42, reason .. ": set-up, 3 x value(10) = 42 carried")
	local paid = Economy.settle(Config, p, reason)
	eq(paid, 21, reason .. ": banks floor(42 / 2) = 21")
	eq(p.salvage, 21, reason .. ": into the wallet")
	eq(p.open, nil, reason .. ": the open sector is cleared in the paying step")
	eq(Economy.settle(Config, p, reason), 0, reason .. ": a second settle pays nothing (idempotent)")
	eq(p.salvage, 21, reason .. ": still 21")
	eq(p.blackouts, if reason == "blackout" then 1 else 0, reason .. ": blackouts counted only for a blackout")
end
do
	-- a crash: the next load finds `open` and settles it before anything else, exactly once
	local p = Economy.newProfile(Config)
	Economy.beginSector(p, "g-crash", 5)
	Economy.carry(Config, p, 5)
	Economy.carry(Config, p, 5)
	local saved = jsonTrip(Economy.snapshot(p))
	local loaded = Economy.sanitize(Config, saved)
	eq(loaded.open ~= nil, true, "the autosaved record still holds the open sector")
	eq(Economy.settle(Config, loaded, "crashed"), 9, "the load banks floor(18 / 2) = 9")
	eq(Economy.settle(Config, loaded, "crashed"), 0, "and only once")
end

--================================================================ purchases
do
	local p = Economy.newProfile(Config)
	local ok, why = Economy.canBuy(Config, p, "tank")
	eq(ok, false, "an empty wallet cannot buy")
	truthy(type(why) == "string" and string.find(why, "120", 1, true) ~= nil, "and says the price (" .. tostring(why) .. ")")
	p.salvage = 125
	eq(Economy.buy(Config, p, "tank"), 120, "the Air Tank rank 1 is bought for 120")
	eq(p.salvage, 5, "the wallet pays")
	eq(p.up.tank, 1, "rank 1")
	local _, why2 = Economy.canBuy(Config, p, "nonsense")
	truthy(type(why2) == "string", "an unknown upgrade is refused with a reason")
	p.up.boots = 4
	local ok3, why3 = Economy.canBuy(Config, p, "boots")
	eq(ok3, false, "a maxed upgrade is refused")
	truthy(type(why3) == "string" and string.find(why3, "max", 1, true) ~= nil, "saying it is maxed (" .. tostring(why3) .. ")")
	p.salvage = 1e6
	Economy.beginSector(p, "g-open", 3)
	local ok4, why4 = Economy.canBuy(Config, p, "tank")
	eq(ok4, false, "nothing is bought while a sector is open (between splice and transit it is closed)")
	truthy(type(why4) == "string", "with a reason")
end
do
	-- snapshot / restore: a failed flush puts back exactly what was there
	local p = Economy.newProfile(Config)
	p.salvage = 400
	local snap = Economy.snapshot(p)
	Economy.buy(Config, p, "boots")
	eq(p.salvage, 280, "set-up: bought")
	local ref = p
	Economy.restore(p, snap)
	eq(ref, p, "restore writes into the same table the server holds")
	eq(p.salvage, 400, "the wallet is restored")
	eq(p.up.boots, 0, "and the rank")
end
do
	-- the recommended upgrade: the Air Tank when both next ranks cost the same
	local p = Economy.newProfile(Config)
	eq(Economy.recommended(Config, p), "tank", "both at rank 0: the Air Tank is recommended")
	p.up.tank = 1
	eq(Economy.recommended(Config, p), "boots", "the tank dearer: the boots")
	p.up.tank, p.up.boots = 4, 4
	eq(Economy.recommended(Config, p), nil, "everything maxed: nothing")
end

print(string.format("Economy: %d passed, %d failed", passed, failed))
assert(failed == 0, "Economy tests failed")
