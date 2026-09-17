-- Economy.spec — DESIGN.md §14 Economy invariants, written before the module.
-- Run: luau tests/Economy.spec.luau
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
-- The emulator's JSON is the one that reproduces Roblox's DataStore coercions (sparse integer
-- keys come back as STRINGS). Used here only to round-trip a profile.
local Services = require("../../robloxemu/emu/services")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
-- Structural equality: JSON key order is not stable, so two encodings are not compared as strings.
local function deepEq(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in a do if not deepEq(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end

--============================================================ 1. pay

eq(Economy.floorPay(Config, 1), 10, "sublevel 1 pays 10")
eq(Economy.floorPay(Config, 2), 15, "sublevel 2 pays 15")
eq(Economy.floorPay(Config, 11), 60, "sublevel 11 pays 60")
do -- §5.4: clearing 1..K pays 10, 25, 45, 70, 100
	local got = {}
	for K = 1, 5 do table.insert(got, Economy.cumulativePay(Config, K)) end
	eq(table.concat(got, ","), "10,25,45,70,100", "cumulative pay for K = 1..5")
	local ok = true
	for K = 1, 60 do
		if Economy.cumulativePay(Config, K) ~= 10 * K + 2.5 * K * (K - 1) then ok = false end
	end
	truthy(ok, "cumulativePay = 10K + 2.5K(K-1) for K = 1..60")
end

eq(Economy.deathPayout(100, 25), 25, "25% of 100")
eq(Economy.deathPayout(10, 25), 2, "the smallest death payout (dying on sublevel 2) is floor(2.5) = 2")
eq(Economy.deathPayout(45, 55), 24, "floor(24.75) = 24")
eq(Economy.deathPayout(0, 25), 0, "nothing earned, nothing kept")
do -- integer percent: no 0.55 * 100 = 55.000000000000007 drift, ever
	local ok = true
	for e = 0, 2000, 5 do
		for _, pct in { 25, 35, 45, 55 } do
			local want = (e * pct - (e * pct) % 100) / 100
			if Economy.deathPayout(e, pct) ~= want then ok = false end
		end
	end
	truthy(ok, "deathPayout is exact integer arithmetic for 0..2000 at every Soul Anchor rank")
end

--============================================================ 2. prices, ranks, effects

eq(Economy.price(Config, "deepCell", 0), 25, "Deep Cell rank 1 = 25")
eq(Economy.price(Config, "deepCell", 1), 60, "rank 2 = 60")
eq(Economy.price(Config, "deepCell", 2), 120, "rank 3 = 120")
eq(Economy.price(Config, "deepCell", 3), nil, "no rank 4")
eq(Economy.price(Config, "secondWind", 0), 150, "Second Wind = 150")
eq(Economy.price(Config, "secondWind", 1), nil, "Second Wind has one rank")
eq(Economy.price(Config, "scavenger", 0), nil, "an unknown perk has no price")
eq(Economy.price(Config, "deepCell", -1), nil, "a negative rank has no price")

do
	local e0 = Economy.effects(Config, {})
	eq(string.format("%d/%d/%d/%d/%d", e0.batteryCap, e0.grace, e0.staminaCap, e0.keepPercent, e0.secondWinds),
		"45/4/4/25/0", "no perks: battery 45, grace 4, stamina 4, keep 25%, no Second Wind")
	local e3 = Economy.effects(Config, { deepCell = 3, nightEyes = 3, marathon = 3, soulAnchor = 3, secondWind = 1 })
	eq(string.format("%d/%d/%d/%d/%d", e3.batteryCap, e3.grace, e3.staminaCap, e3.keepPercent, e3.secondWinds),
		"75/7/7/55/1", "everything maxed: 75 / 7 / 7 / 55% / one Second Wind")
	local clamped = Economy.effects(Config, { deepCell = 99, soulAnchor = -4, secondWind = 5 })
	eq(string.format("%d/%d/%d", clamped.batteryCap, clamped.keepPercent, clamped.secondWinds), "75/25/1",
		"effects clamp out-of-range ranks")
end

--============================================================ 3. profile sanitise and JSON

do
	local p = Economy.sanitize(Config, nil)
	eq(p.essence .. "/" .. p.runs .. "/" .. p.bestSublevel, "0/0/0", "a missing record is a fresh profile")
	eq(p.openRun, nil, "…with no open run")
	eq(p.perks.deepCell, 0, "…and every perk at rank 0")
	eq(p.v, 1, "schema version 1")

	local raw = {
		v = 1, essence = 250.7, essenceEarned = -3, runs = "7", extractions = 2, bestSublevel = 0 / 0,
		perks = { deepCell = 2, nightEyes = 9, marathon = -1, soulAnchor = "x", secondWind = 1, scavenger = 3, [1] = 4 },
		openRun = { id = "abc", sublevel = 4, runEssence = 70, keepPercent = 35 },
		junk = true,
	}
	local s = Economy.sanitize(Config, raw)
	eq(s.essence, 250, "fractional essence floors")
	eq(s.essenceEarned, 0, "negative clamps to 0")
	eq(s.runs, 0, "a string where a number belongs is dropped to the default")
	eq(s.bestSublevel, 0, "NaN is not a number")
	eq(s.perks.deepCell, 2, "a valid rank survives")
	eq(s.perks.nightEyes, 3, "an over-max rank clamps to max")
	eq(s.perks.marathon, 0, "a negative rank clamps to 0")
	eq(s.perks.soulAnchor, 0, "a non-number rank is 0")
	eq(s.perks.scavenger, nil, "unknown perk keys are dropped")
	eq(s.perks[1], nil, "integer perk keys are dropped")
	eq(s.junk, nil, "unknown top-level keys are dropped")
	eq(s.openRun and s.openRun.runEssence, 70, "a well-formed open run survives")
	local keys = 0
	for k in s.perks do
		keys += 1
		truthy(type(k) == "string", "perk key " .. tostring(k) .. " is a string")
	end
	eq(keys, 5, "exactly the five perks")

	local bad = Economy.sanitize(Config, { openRun = { id = 5, runEssence = "lots" } })
	eq(bad.openRun, nil, "a malformed open run is dropped")

	local rt = Economy.sanitize(Config, Services.jsonDecode(Services.jsonEncode(s)))
	truthy(deepEq(rt, s), "a JSON round-trip gives an identical profile")
	local fresh = Economy.newProfile(Config)
	local rt2 = Economy.sanitize(Config, Services.jsonDecode(Services.jsonEncode(fresh)))
	truthy(deepEq(rt2, fresh), "…and so does a fresh profile")
end

--============================================================ 4. runs and settlement

do
	local p = Economy.newProfile(Config)
	Economy.beginRun(p, "run-1", 25)
	eq(p.openRun.id, "run-1", "a run is open")
	eq(Economy.power(Config, p, 1), 10, "powering sublevel 1 pays 10")
	eq(Economy.power(Config, p, 2), 15, "…sublevel 2 pays 15")
	eq(p.openRun.runEssence, 25, "run essence is the sum")
	eq(p.openRun.sublevel, 2, "the checkpoint records the sublevel")
	eq(p.bestSublevel, 2, "bestSublevel rises")
	eq(p.essence, 0, "nothing is banked until the run settles")

	eq(Economy.settle(p, "extract"), 25, "EXTRACT pays the whole run")
	eq(p.essence .. "/" .. p.essenceEarned .. "/" .. p.runs .. "/" .. p.extractions, "25/25/1/1", "banked, counted")
	eq(p.openRun, nil, "the open run is cleared in the same step that pays it")
	eq(Economy.settle(p, "extract"), 0, "a second settle pays nothing")
	eq(Economy.settle(p, "dark"), 0, "…whatever the reason")
	eq(p.essence .. "/" .. p.runs, "25/1", "…and changes nothing")
end

do
	for _, reason in { "dark", "reset", "left", "shutdown", "load" } do
		local p = Economy.newProfile(Config)
		Economy.beginRun(p, "r", 35)
		for k = 1, 4 do Economy.power(Config, p, k) end -- 70
		eq(Economy.settle(p, reason), 24, reason .. " pays floor(35% of 70) = 24")
		eq(p.extractions, 0, reason .. " is not an extraction")
		eq(p.runs, 1, reason .. " counts the run")
	end
	local p = Economy.newProfile(Config)
	Economy.beginRun(p, "r", 25)
	Economy.power(Config, p, 3)
	eq(p.bestSublevel, 3, "bestSublevel follows the deepest powered elevator")
	Economy.settle(p, "dark")
	Economy.beginRun(p, "r2", 25)
	Economy.power(Config, p, 1)
	eq(p.bestSublevel, 3, "…and never falls")
end

do -- a death with nothing earned still ends the run (runs == 0 is the first-run hold)
	local p = Economy.newProfile(Config)
	Economy.beginRun(p, "r", 25)
	eq(Economy.settle(p, "dark"), 0, "dying on sublevel 1 pays 0")
	eq(p.runs, 1, "…and the first-ever run is over")
end

--============================================================ purchases

do
	local p = Economy.newProfile(Config)
	p.essence = 100
	local ok, why = Economy.canBuy(Config, p, "deepCell")
	truthy(ok, "100 Essence can buy Deep Cell rank 1 (" .. tostring(why) .. ")")
	eq(Economy.buy(Config, p, "deepCell"), 25, "…for 25")
	eq(p.essence .. "/" .. p.perks.deepCell, "75/1", "…spent and ranked")
	local ok2, why2 = Economy.canBuy(Config, p, "secondWind")
	eq(ok2, false, "75 cannot buy Second Wind")
	truthy(type(why2) == "string" and #why2 > 0, "…and says why: " .. tostring(why2))
	eq(Economy.buy(Config, p, "secondWind"), nil, "buy refuses what canBuy refuses")
	eq(p.essence, 75, "…and spends nothing")
	p.perks.nightEyes = 3
	p.essence = 1000
	local ok3, why3 = Economy.canBuy(Config, p, "nightEyes")
	eq(ok3, false, "a maxed perk cannot be bought")
	truthy(type(why3) == "string", "…with a reason")
	local ok4 = Economy.canBuy(Config, p, "scavenger")
	eq(ok4, false, "an unknown perk cannot be bought")
	local ok5 = Economy.canBuy(Config, p, 12)
	eq(ok5, false, "a non-string perk id cannot be bought")
	Economy.beginRun(p, "x", 25)
	local ok6, why6 = Economy.canBuy(Config, p, "deepCell")
	eq(ok6, false, "no purchases while a run is open")
	truthy(type(why6) == "string", "…with a reason")
end

do -- snapshot / restore is a deep copy
	local p = Economy.newProfile(Config)
	p.essence = 60
	local snap = Economy.snapshot(p)
	Economy.buy(Config, p, "marathon")
	Economy.restore(p, snap)
	eq(p.essence .. "/" .. p.perks.marathon, "60/0", "restore rolls a purchase back completely")
	Economy.buy(Config, p, "marathon")
	eq(snap.perks.marathon, 0, "the snapshot is not aliased to the live profile")
end

print(string.format("Economy: %d passed, %d failed", passed, failed))
