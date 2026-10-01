-- Economy — prices, rates, the dish, the hopper, the HUD's star. Run: luau tests/Economy.spec.luau
--
-- Every expected number below is written out by hand from DESIGN.md (sections 4.1-4.4) or worked in the
-- comment next to it. None is recomputed with the module's own formula: a price checked against the
-- function that computes it checks nothing.

local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local EnvBands = require("../src/shared/EnvBands")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local C = Config

--============================================================================ spawn rate and ore
near(Economy.spawnInterval(C, 0), 3.0, 1e-9, "a new plot gets a meteor every 3.0 s")
near(Economy.spawnInterval(C, 30), 3.0 * 0.97 ^ 30, 1e-9, "L30 is still above the floor (1.203 s)")
near(Economy.spawnInterval(C, 31), 1.2, 1e-9, "the floor, 1.2 s, is reached at L31 (DESIGN [M2])")
near(Economy.spawnInterval(C, 200), 1.2, 1e-9, "and never goes below it")
near(Economy.baseOre(C, 0), 1, 1e-12, "ore per meteor at L0 is 1")
near(Economy.baseOre(C, 22), 1.14 ^ 22, 1e-9, "ore grows 1.14x per Beacon level")
near(Economy.oreOf(C, 22, "legendary"), 1786.10, 0.01, "a legendary at Beacon 22 is 1 786 ore (DESIGN 4.3)")
near(Economy.oreOf(C, 0, "epic"), 25, 1e-9, "an epic at L0 is 25 ore")

--============================================================================ prices
eq(Economy.beaconPrice(C, 0), 12, "the first Beacon level costs 12")
eq(Economy.beaconPrice(C, 9), 96, "Beacon 9 -> 10 costs 96 (clip 3's arithmetic)")
eq(Economy.beaconPrice(C, 10), 121, "Beacon 10 -> 11 costs 121")
eq(Economy.beaconPrice(C, 11), 152, "Beacon 11 -> 12 costs 152")
eq(Economy.beaconPrice(C, 21), 1538, "Beacon 21 -> 22 (the Falling Star) costs 1 538 (clip 2)")
eq(Economy.beaconPrice(C, 22), 1938, "Beacon 22 -> 23 costs 1 938 (DESIGN [M2])")
do
	local want = { 60, 132, 290, 639, 1406, 3092, 6803, 14966 }
	for c = 0, 7 do
		eq(Economy.collectorPrice(C, c), want[c + 1], "Collector " .. c .. " -> " .. (c + 1) .. " costs " .. want[c + 1])
	end
	eq(Economy.collectorPrice(C, 8), nil, "a Collector at 8 has no next level")
end
eq(Economy.smelterPrice(C, 0), 20, "the first Smelter level costs 20")
eq(Economy.smelterPrice(C, 1), 28, "the second costs round(27.6) = 28")
eq(Economy.price(C, "beacon", { beacon = 3, collector = 0, smelter = 0 }), Economy.beaconPrice(C, 3), "price() routes beacon")
eq(Economy.price(C, "nonsense", { beacon = 3, collector = 0, smelter = 0 }), nil, "price() of an unknown kind is nil")

--============================================================================ the dish
do
	local radius = { [0] = 0, 10, 12, 14, 16, 18, 20, 22, 24 }
	for c = 0, 8 do
		eq(Economy.dishRadius(C, c), radius[c], "dish radius at Collector " .. c)
	end
	near(Economy.dishShare(C, 0), 0, 1e-12, "no Collector catches nothing")
	near(Economy.dishShare(C, 1), (100 - 64) / 960, 1e-12, "Collector 1 covers 3.75% of landings")
	near(Economy.dishShare(C, 8), (576 - 64) / 960, 1e-12, "Collector 8 covers 53.3%, and the rest is walking territory")
end

--============================================================================ the smelter and the hopper
near(Economy.smeltRate(C, 0), 0.6, 1e-12, "s0 melts 0.6 ore/s")
near(Economy.smeltRate(C, 17), 0.6 * 1.28 ^ 17, 1e-9, "s17 melts 39.9 ore/s")
near(Economy.hopperCap(C, 0), 12, 1e-9, "the s0 hopper holds 20 s of melting = 12 ore")
near(Economy.hopperCap(C, 17), 797.5, 0.05, "the s17 hopper holds 797.5 ore (DESIGN [M7])")

do
	-- accept while BELOW the cap, even when the meteor overfills it (an epic is 1.91 hoppers in band 2)
	local st = { hopper = 11.9, stardust = 0, lifetime = 0, smelter = 0 }
	eq(Economy.collect(C, st, "epic", 25), "hopper", "a hopper below its cap accepts an epic that overfills it")
	near(st.hopper, 36.9, 1e-9, "...and holds all of it")
	eq(Economy.collect(C, st, "common", 1), "refused", "a hopper at or over its cap refuses a hand pickup")
	near(st.hopper, 36.9, 1e-9, "...and takes nothing")
	eq(Economy.dishCatch(C, st, 3), "bounced", "a dish catch bounces off a full hopper")
	near(st.hopper, 36.9, 1e-9, "...and is lost")
	-- the legendary bypass: never refused, never in the hopper, paid at once
	eq(Economy.collect(C, st, "legendary", 1786), "instant", "a legendary is paid out the moment it is caught, full hopper or not")
	near(st.stardust, 1786, 1e-9, "...straight into Stardust")
	near(st.lifetime, 1786, 1e-9, "...and into lifetime")
	near(st.hopper, 36.9, 1e-9, "...without touching the hopper")
	local st2 = { hopper = 0, stardust = 0, lifetime = 0, smelter = 0 }
	eq(Economy.dishCatch(C, st2, 3), "hopper", "an empty hopper takes a dish catch")
end

do
	-- melting: hopper -> Stardust 1:1 at the Smelter's rate, never more than the hopper holds
	local st = { hopper = 1.0, stardust = 5, lifetime = 5, smelter = 0 }
	near(Economy.melt(C, st, 1.0), 0.6, 1e-12, "one second of s0 melts 0.6")
	near(st.hopper, 0.4, 1e-12, "...out of the hopper")
	near(st.stardust, 5.6, 1e-12, "...into Stardust")
	near(st.lifetime, 5.6, 1e-12, "...and lifetime")
	near(Economy.melt(C, st, 10), 0.4, 1e-12, "it never melts more than the hopper holds")
	near(st.hopper, 0, 1e-12, "the hopper is then empty")
	near(Economy.melt(C, st, 0 / 0), 0, 1e-12, "a NaN dt melts nothing")
	near(Economy.melt(C, st, -3), 0, 1e-12, "and so does a negative one")
end

--============================================================================ bands and the income model
do
	local bands = C.Env.Bands
	local agree = 0
	for L = -3, 120 do
		if Economy.bandIndex(C, L) == EnvBands.indexAt(bands, L) then agree += 1 end
	end
	eq(agree, 124, "Economy.bandIndex agrees with EnvBands.indexAt at every level from -3 to 120 (so the meteor mix, "
		.. "the chip and the board always name the same band)")
end
near(Economy.avgMult(C, 1), 1.290, 1e-9, "Dusk's average multiplier is 1.290 (DESIGN [M2])")
near(Economy.avgMult(C, 4), 3.340, 1e-9, "Starfall's is 3.340")
near(Economy.avgMult(C, 6), 6.100, 1e-9, "the Core's is 6.100")
near(Economy.inflow(C, 0), 0.43, 1e-9, "the starting inflow is 0.43 ore/s")

do
	-- the HUD's star at the very start: Beacon (DESIGN [M8]: the first purchase is a Beacon for every seed)
	local kind, price = Economy.bestNext(C, 0, 0, 0)
	eq(kind, "beacon", "the star starts on the Beacon")
	eq(price, 12, "...at 12")
	-- a Smelter that cannot keep up is starred: L10 (band 2) inflow 1.668*1.14^10/(3*0.97^10) is about 2.80 ore/s,
	-- far above s0's 0.6, so a Smelter level adds the most income per Stardust
	local k2 = Economy.bestNext(C, 10, 0, 0)
	eq(k2, "smelter", "a starved Smelter is starred")
	-- nothing adds income: the star never goes dark, it falls back to the cheaper of Beacon and Smelter
	local k3, p3 = Economy.bestNext(C, 0, 8, 200)
	truthy(k3 == "beacon" or k3 == "smelter", "the star never goes dark (" .. tostring(k3) .. ")")
	truthy(type(p3) == "number" and p3 > 0, "and always has a price")
	-- the star never points at a maxed Collector
	for L = 0, 60, 3 do
		for s = 0, 40, 4 do
			local k = Economy.bestNext(C, L, 8, s)
			if k == "collector" then
				failed += 1
				print("FAIL: the star pointed at a Collector at its maximum (L" .. L .. " s" .. s .. ")")
			end
		end
	end
	passed += 1
end

do
	-- steady income is capped by the Smelter and by what is caught
	near(Economy.steadyIncome(C, 0, 0, 0), 0.43, 1e-9, "at the start everything that falls is walked to: 0.43 ore/s")
	-- REVIEW-1: the cap is StarHeadroom x the melt rate, not the melt rate (it was 0.6 here before)
	near(Economy.steadyIncome(C, 20, 0, 0), 0.6 * (C.Smelter.StarHeadroom or 1), 1e-9, "a starved Smelter caps income at StarHeadroom x its melt rate")
end

--============================================================================ REVIEW-1: the star keeps the Smelter ahead of the rain
-- Rares and epics arrive in bursts that overfill a hopper whose Smelter only just matches the average inflow:
-- with the star buying to exactly that point, the normal player's hopper was full 19.5% of the time to the
-- star and the dish lost 16% of its catches (tests/Pacing.spec.luau measures both now). The star treats the
-- Smelter as full at StarHeadroom of its rated melt.
do
	local H = C.Smelter.StarHeadroom
	truthy(type(H) == "number" and H > 0.5 and H <= 0.9, "the star keeps headroom on the Smelter (StarHeadroom " .. tostring(H) .. ")")
	H = H or 1
	-- a build whose supply is 90-98% of the melt rate: the old rule saw room to spare and starred a machine that
	-- only adds meteors; a star with headroom (StarHeadroom <= 0.9) puts it on the Smelter
	local cases, starred = 0, 0
	for L = 0, 50 do
		for sm = 0, 50 do
			local supply = Economy.steadyIncome(C, L, 0, 400) -- a Smelter that never caps: the supply itself
			local melt = Economy.smeltRate(C, sm)
			if supply > 0.9 * melt and supply < 0.98 * melt then
				cases += 1
				if Economy.bestNext(C, L, 0, sm) == "smelter" then starred += 1 end
			end
		end
	end
	truthy(cases >= 10, string.format("set-up: %d builds whose supply sits in the Smelter's headroom", cases))
	eq(starred, cases, string.format("the star is on the Smelter in every one of them (%d of %d)", starred, cases))
end
do
	-- ...and it listens to the hopper itself: the steady rule assumes a pace (HudHandRate), and a player who
	-- collects faster than that still fills the hopper. The server keeps a moving share of the time the hopper
	-- was full (Economy.fullEma); at StarFullShare or more the star is on the Smelter, whatever the rule says.
	if type(Economy.fullEma) ~= "function" or C.Smelter.StarFullShare == nil then
		failed += 1
		print("FAIL: the star does not measure the hopper (Economy.fullEma / Smelter.StarFullShare missing)")
	else
		local hl = C.Smelter.FullHalfLife
		near(Economy.fullEma(C, 1, false, hl), 0.5, 1e-9, "the full-share halves in FullHalfLife seconds of an unblocked hopper")
		near(Economy.fullEma(C, 0, true, hl), 0.5, 1e-9, "and climbs as fast while it is full")
		near(Economy.fullEma(C, 0.3, true, 0), 0.3, 1e-12, "dt = 0 changes nothing")
		near(Economy.fullEma(C, 0.3, true, -1), 0.3, 1e-12, "neither does a negative dt")
		-- L0 with a big Smelter: the steady rule says Beacon (the Smelter has room to spare on paper)
		eq(Economy.bestNext(C, 0, 0, 10, 0), "beacon", "set-up: on paper the star is on the Beacon")
		local k, p = Economy.bestNext(C, 0, 0, 10, C.Smelter.StarFullShare)
		eq(k, "smelter", "a hopper that has been full StarFullShare of the time puts the star on the Smelter")
		eq(p, Economy.smelterPrice(C, 10), "at the Smelter's price")
		eq(Economy.bestNext(C, 0, 0, 10, C.Smelter.StarFullShare * 0.99), "beacon", "just under it, the steady rule decides")
		eq(Economy.bestNext(C, 0, 0, 10), "beacon", "and no measurement at all is the steady rule (the old call)")
	end
end
do
	-- the "Hopper full!" refusal never contradicts the star (REVIEW-1: it said "Upgrade the Smelter" while the
	-- star was on the Beacon or the Collector in 46-49% of the full moments)
	if type(Economy.fullText) ~= "function" then
		failed += 1
		print("FAIL: Economy.fullText (the refusal that follows the star) does not exist")
	else
		local st = { hopper = 13, smelter = 0, beacon = 0, collector = 0, stardust = 0 } -- cap 12, melts 0.6/s
		local onSmelter = Economy.fullText(C, st, "smelter")
		truthy(string.find(onSmelter, "Smelter", 1, true) ~= nil, "starred: the refusal names the Smelter: " .. onSmelter)
		for _, other in { "beacon", "collector" } do
			local t = Economy.fullText(C, st, other)
			eq(string.find(t, "Smelter", 1, true), nil, "star on the " .. other .. ": the refusal does not send you to the Smelter: " .. t)
			truthy(string.find(t, "2 s", 1, true) ~= nil, "...it says when the hopper takes meteors again ((13 - 12) / 0.6 = 1.7 -> 2 s): " .. t)
		end
		st.hopper = 12 -- exactly at the cap: the next melt tick frees it
		truthy(string.find(Economy.fullText(C, st, "beacon"), "1 s", 1, true) ~= nil, "at the cap exactly it says 1 s, never 0")
	end
end

--============================================================================ buying
do
	local st = { beacon = 0, collector = 0, smelter = 0, stardust = 11 }
	local ok, why, price = Economy.check(C, st, "beacon")
	eq(ok, false, "11 Stardust cannot buy a 12 Beacon")
	eq(why, "afford", "...because it is not affordable")
	eq(price, 12, "...and the price is reported")
	eq(Economy.refusalText(C, why, price, st.stardust), "Need 12 Stardust, you have 11", "the refusal says exactly why")
	st.stardust = 12
	eq((Economy.buy(C, st, "beacon")), true, "12 buys it")
	eq(st.beacon, 1, "the level moves")
	eq(st.stardust, 0, "and the price is paid")
	local ok2, why2 = Economy.check(C, st, "teleport")
	eq(ok2, false, "an unknown kind is refused")
	eq(why2, "unknown", "...as unknown")
	truthy(type(Economy.refusalText(C, why2, nil, 0)) == "string", "...with a text")
	st.collector = 8
	st.stardust = 1e9
	local ok3, why3 = Economy.check(C, st, "collector")
	eq(ok3, false, "a Collector at 8 cannot be bought again")
	eq(why3, "max", "...because it is at its maximum")
	eq(Economy.refusalText(C, why3, nil, st.stardust), "Your Collector is at its biggest", "...and says so")
	local before = st.stardust
	eq((Economy.buy(C, st, "collector")), false, "buy() refuses it too")
	eq(st.stardust, before, "...and takes nothing")
	local ok4 = Economy.check(C, { beacon = 0, collector = 0, smelter = 0, stardust = 0 / 0 }, "beacon")
	eq(ok4, false, "NaN Stardust buys nothing")
end

--============================================================================ formatting
eq(Economy.short(0), "0", "0")
eq(Economy.short(999.7), "999", "below 1000 a whole number, rounded down (never shows more than you have)")
eq(Economy.short(1234), "1.2K", "1.2K")
eq(Economy.short(12345), "12.3K", "12.3K")
eq(Economy.short(123456), "123K", "123K")
eq(Economy.short(3.4e6), "3.4M", "3.4M")
eq(Economy.short(1.2e9), "1.2B", "1.2B")
eq(Economy.short(-5), "0", "never negative")
eq(Economy.short(0 / 0), "0", "never NaN")
eq(Economy.refusalText(C, "afford", 1900, 1200), "Need 1.9K Stardust, you have 1.2K", "DESIGN 10.5's refusal text")

print(string.format("Economy: %d passed, %d failed", passed, failed))
if failed > 0 then error("Economy spec failed", 0) end
