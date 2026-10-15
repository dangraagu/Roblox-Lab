-- Economy — prices, what can be bought, the purchase itself (every check before the first assignment), the
-- HUD's ★, refusal texts and number formatting. Run: luau tests/Economy.spec.luau
--
-- Prices are DESIGN.md section 4.1's table, printed by design/model.py part 1 [M1]. The ★ is section 4.5's
-- three rules; the cases below are worked by hand in the comments.

local Config = require("../src/shared/Config")
local Line = require("../src/shared/Line")
local Economy = require("../src/shared/Economy")

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
local IDS = C.Stations.Order

local function profile(spec: { any }?, cash: number?)
	local stations = {}
	for t, id in IDS do
		local s = spec and spec[t]
		stations[id] = { n = s and s.n or 0, L = s and s.L or 1, jam = { s and s.jam and s.jam[1] or 0, s and s.jam and s.jam[2] or 0 } }
	end
	return { cash = cash or 0, stations = stations, bolts = 0 }
end
local function snapshot(d)
	local parts = { tostring(d.cash) }
	for _, id in IDS do
		local s = d.stations[id]
		table.insert(parts, string.format("%s:%d:%d:%d:%d", id, s.n, s.L, s.jam[1], s.jam[2]))
	end
	return table.concat(parts, "|")
end

--============================================================================ prices (M1)
do
	local build = { 0, 650, 13000, 130000, 1100000, 9500000 }
	local twin = { 240, 1140, 4380, 17700, 71400, 315000 }
	local up1 = { 8, 38, 146, 590, 2380, 10500 }
	for t = 1, 6 do
		eq(Economy.buildPrice(C, t), build[t], C.Stations.Names[t] .. " builds for " .. build[t])
		eq(Economy.twinPrice(C, t), twin[t], C.Stations.Names[t] .. "'s twin costs " .. twin[t] .. " (30 x its first upgrade)")
		eq(Economy.upPrice(C, t, 1), up1[t], C.Stations.Names[t] .. " level 1 -> 2 costs " .. up1[t])
	end
	-- the M1 table's later levels
	eq(Economy.upPrice(C, 1, 10), 308, "Shredder 10 -> 11: 8 x 1.5^9 = 307.5 -> 308")
	eq(Economy.upPrice(C, 2, 10), 1461, "Furnace 10 -> 11: 1461")
	eq(Economy.upPrice(C, 3, 20), 323658, "Press 20 -> 21: 323 658")
	eq(Economy.upPrice(C, 4, 20), 1307934, "Cutter 20 -> 21: 1 307 934")
	eq(Economy.upPrice(C, 5, 30), 304245014, "Assembler 30 -> 31: 304 245 014")
	eq(Economy.upPrice(C, 6, 30), 1342257415, "Rocket Bay 30 -> 31: 1 342 257 415")
	-- exact halves round to even, as design/model.py's Python round() does
	eq(Economy.upPrice(C, 1, 5), 40, "Shredder 5 -> 6: 8 x 1.5^4 = 40.5 rounds to the even 40 (Python's round)")
	eq(Economy.upPrice(C, 2, 3), 86, "Furnace 3 -> 4: 38 x 2.25 = 85.5 rounds to the even 86")
	truthy(Economy.upPrice(C, 6, 99) < 2e21 and Economy.upPrice(C, 6, 99) > 1e21, "level 99 -> 100 of the Rocket Bay is finite (~1.8e21)")
end

--============================================================================ candidates
do
	local c = Economy.candidates(C, Line.ordered(C, profile().stations))
	eq(#c, 1, "a new line offers one thing")
	eq(c[1].kind, "build", "...building")
	eq(c[1].t, 1, "...the Shredder")
	eq(c[1].price, 0, "...for free")
	local d = profile({ { n = 1 } })
	c = Economy.candidates(C, Line.ordered(C, d.stations))
	eq(#c, 3, "with a Shredder: its twin, its upgrade, and the Furnace")
	eq(c[1].kind .. c[1].t, "twin1", "twin first (belt order, then twin, then up)")
	eq(c[2].kind .. c[2].t, "up1", "then the upgrade")
	eq(c[3].kind .. c[3].t, "build2", "then the next station")
	local full = profile({ { n = 2, L = 100 }, { n = 2, L = 100 }, { n = 2, L = 100 }, { n = 2, L = 100 }, { n = 2, L = 100 }, { n = 2, L = 100 } })
	eq(#Economy.candidates(C, Line.ordered(C, full.stations)), 0, "a finished line (every station twinned at the cap) offers nothing")
end

--============================================================================ buying: every check before the first assignment
do
	local d = profile()
	local ok, why = Economy.buy(C, d, "build", "shredder")
	eq(ok, true, "the free Shredder can be built with no cash")
	eq(d.stations.shredder.n, 1, "it is built")
	eq(d.cash, 0, "for nothing")
	local function refused(kind, id, wantWhy, msg)
		local before = snapshot(d)
		local okR, whyR = Economy.buy(C, d, kind, id)
		eq(okR, false, msg .. ": refused")
		eq(whyR, wantWhy, msg .. ": because " .. wantWhy)
		eq(snapshot(d), before, msg .. ": and nothing changed")
	end
	refused("build", "shredder", "built", "building the Shredder twice")
	refused("build", "press", "locked", "a Press before a Furnace")
	refused("twin", "furnace", "unbuilt", "a twin of an unbuilt Furnace")
	refused("up", "furnace", "unbuilt", "upgrading an unbuilt Furnace")
	refused("build", "furnace", "cash", "a Furnace with no cash")
	refused("teleport", "shredder", "unknown", "an unknown kind")
	refused("up", "spaceship", "unknown", "an unknown station")
	refused(7 :: any, "shredder", "unknown", "a number for a kind")
	refused("up", nil :: any, "unknown", "no station")
	d.cash = 1000
	ok, why = Economy.buy(C, d, "up", "shredder")
	eq(ok, true, "an affordable upgrade goes through (" .. tostring(why) .. ")")
	eq(d.stations.shredder.L, 2, "level 2")
	eq(d.cash, 992, "for 8")
	ok = Economy.buy(C, d, "twin", "shredder")
	eq(ok, true, "the twin")
	eq(d.stations.shredder.n, 2, "two machines")
	eq(d.cash, 752, "for 240")
	refused("twin", "shredder", "twinned", "a third machine")
	ok = Economy.buy(C, d, "build", "furnace")
	eq(ok, true, "the Furnace once the Shredder exists")
	eq(d.cash, 102, "for 650")
	d.stations.furnace.L = 100
	d.cash = 1e300
	refused("up", "furnace", "maxlevel", "an upgrade past level 100")
	-- the price is checked against what the player HAS, to the unit
	local e = profile({ { n = 1 } }, 7.999)
	local okE, whyE, price = Economy.buy(C, e, "up", "shredder")
	eq(okE, false, "7.999 cash cannot buy an 8 upgrade")
	eq(whyE, "cash", "...not enough cash")
	eq(price, 8, "...and the refusal carries the price")
	-- NaN cash never buys
	local n = profile({ { n = 1 } }, 0 / 0)
	eq((Economy.buy(C, n, "up", "shredder")), false, "NaN cash buys nothing")
end

--============================================================================ refusal texts (DESIGN 11.5)
do
	eq(Economy.refusalText(C, "unknown"), "That isn't a machine", "unknown")
	eq(Economy.refusalText(C, "locked", nil, nil, 3), "Build a Furnace first", "locked: names the station before it")
	eq(Economy.refusalText(C, "unbuilt", nil, nil, 3), "Build the Press first", "unbuilt: names the station itself")
	eq(Economy.refusalText(C, "built", nil, nil, 2), "Your Furnace is already built", "built")
	eq(Economy.refusalText(C, "twinned"), "This station already has its twin", "twinned")
	eq(Economy.refusalText(C, "maxlevel", nil, nil, 4), "The Cutter is at its top level", "maxlevel")
	eq(Economy.refusalText(C, "cash", 1.2e6, 8e5), "Need 1.2M, you have 800K", "cash: both numbers, compact")
	eq(Economy.refusalText(C, "loading"), "Loading your factory…", "loading")
	eq(Economy.refusalText(C, "recycling"), "Recycling… one moment", "recycling")
end

--============================================================================ the ★ (DESIGN 4.5)
local function starOf(d)
	return Economy.star(C, Line, Line.ordered(C, d.stations), d.cash, Line.mult(C, d.bolts))
end
do
	local s = starOf(profile())
	eq(s.kind .. s.t, "build1", "a new line: the ★ is the free Shredder")
	eq(s.rule, 0, "...rule 0 (the next station, affordable)")
	eq(s.saving, false, "...nothing to save for")
	-- Shredder L1, income $2/s, no cash. Rule 0: the Furnace is 650 / 2 = 325 s away (> 60): no.
	-- Rule 1 scores (wait + payback): Shredder up (8): preview 2.5/s, gain 0.5, payback 16, wait 4 -> 20;
	-- twin (240): gain 2, payback 120, wait 120 -> 240; Furnace (650): gain 3, payback 216.7, wait 325 -> 541.7.
	s = starOf(profile({ { n = 1 } }, 0))
	eq(s.kind .. s.t, "up1", "Shredder alone, broke: the ★ is its 8-cash upgrade (score 20 against 240 and 541.7)")
	eq(s.rule, 1, "...rule 1")
	s = starOf(profile({ { n = 1 } }, 600))
	eq(s.kind .. s.t, "build2", "600 cash at $2/s: the Furnace is 25 s away (inside the 60 s window): save for it")
	eq(s.rule, 0, "...rule 0")
	eq(s.saving, true, "...and the HUD says it is saving")
	near(Economy.saveSeconds(C, Line, Line.ordered(C, profile({ { n = 1 } }, 600).stations), 600, 1, s), 25, 1e-9, "the countdown: (650 - 600) / 2 = 25 s")
	s = starOf(profile({ { n = 1 } }, 700))
	eq(s.kind .. s.t, "build2", "700 cash: the Furnace, affordable")
	eq(s.saving, false, "...no longer saving")
	-- 1 cash short of the 60 s window: 650 - 120 = 530 cash at $2/s is exactly 60 s (in); 529 is 60.5 s (out)
	eq(starOf(profile({ { n = 1 } }, 530)).kind, "build", "exactly 60 s of income away: saving")
	eq(starOf(profile({ { n = 1 } }, 529)).kind, "up", "60.5 s away: not yet")
	-- a finished line: nothing to star
	local full = profile({ { n = 2, L = 100 }, { n = 2, L = 100 }, { n = 2, L = 100 }, { n = 2, L = 100 }, { n = 2, L = 100 }, { n = 2, L = 100 } })
	eq(starOf(full), nil, "a finished line has no ★")
	-- the ★ plans for a WORKING line: a jam does not move it
	local jammed = profile({ { n = 1, L = 10 }, { n = 1, jam = { 2, 0 } } }, 50)
	local working = profile({ { n = 1, L = 10 }, { n = 1 } }, 50)
	local a, b = starOf(jammed), starOf(working)
	eq(a.kind .. a.t, b.kind .. b.t, "a jammed Furnace does not move the ★ (it plans for a working line)")
end

-- Rule 2 ("a filler only if its payback beats the wait"), as a property: whatever the line, the ★ never sits on
-- an unaffordable target while an affordable purchase that adds income would pay for itself before that target
-- is affordable. (Worked out while writing this: rule 1's score already guarantees it, since such a filler scores
-- payback < wait <= the target's score. The rule is kept, as the model has it, and this checks the outcome.)
do
	local seed = 12345
	local function rnd()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local violations, unaffordable, trials = 0, 0, 0
	for _ = 1, 3000 do
		local spec = {}
		local built = 1 + math.floor(rnd() * 6)
		for t = 1, built do spec[t] = { n = 1 + math.floor(rnd() * 2), L = 1 + math.floor(rnd() * 25) } end
		local d = profile(spec, rnd() * 10 ^ (rnd() * 7))
		local S = Line.ordered(C, d.stations)
		local s = Economy.star(C, Line, S, d.cash, 1)
		if s then
			trials += 1
			if s.price > d.cash and s.rule ~= 0 then
				unaffordable += 1
				local now = Line.income(C, S, 1, true)
				local wait = (s.price - d.cash) / now
				for _, a in Economy.candidates(C, S) do
					local gain = Economy.preview(C, Line, S, a, 1) - now
					if a.price <= d.cash and gain > 1e-12 and a.price / gain < wait - 1e-9 then
						violations += 1
						break
					end
				end
			end
		end
	end
	print(string.format("  the ★ on 3000 random lines: %d starred, %d on an unaffordable target (saving), %d skipped a faster filler", trials, unaffordable, violations))
	truthy(unaffordable > 100, "set-up: many random lines put the ★ on something to save for")
	eq(violations, 0, "the ★ never saves for a target while an affordable purchase would pay back before it")
end

--============================================================================ green: what the panel paints as worth buying (REVIEW-2 R3)
-- A player who taps whatever is green, not the gold ★, reached the first Rocket at 53 min (the reviewer's model): every
-- affordable button was green, useful or not. Economy.worth is the set the HUD paints green: the next station, and a
-- purchase that adds income and pays for itself within Star.GreenPayback x the best payback on the list; and nothing
-- while the ★ saves for the next station (rule 0). Keys are "kind:t".
do
	local M = 1
	local function paybacks(S)
		local now = Line.income(C, S, M, true)
		local out, best = {}, math.huge
		for _, a in Economy.candidates(C, S) do
			local gain = Economy.preview(C, Line, S, a, M) - now
			local pb = if gain > 1e-12 then a.price / gain else math.huge
			out[a.kind .. ":" .. a.t] = { a = a, pb = pb }
			best = math.min(best, pb)
		end
		return out, best
	end
	truthy(type(C.Star.GreenPayback) == "number" and C.Star.GreenPayback >= 1, "Star.GreenPayback is a factor of at least 1 (" .. tostring(C.Star.GreenPayback) .. ")")
	local k = C.Star.GreenPayback or 2
	local cases = {
		{ "a fresh Shredder, no cash", { { n = 1, L = 1 } }, 0 },
		{ "a Shredder L6 and a Furnace L1", { { n = 1, L = 6 }, { n = 1, L = 1 } }, 40 },
		{ "a twinned line to the Press", { { n = 2, L = 12 }, { n = 2, L = 9 }, { n = 1, L = 3 } }, 500 },
		{ "a slow Shredder feeding a Furnace L10 (upgrading the Furnace adds nothing)", { { n = 1, L = 1 }, { n = 1, L = 10 } }, 5 },
		{ "a line to the Rocket Bay", { { n = 2, L = 40 }, { n = 2, L = 34 }, { n = 2, L = 28 }, { n = 2, L = 22 }, { n = 2, L = 16 }, { n = 1, L = 3 } }, 1e7 },
	}
	for _, c in cases do
		local d = profile(c[2], c[3])
		local S = Line.ordered(C, d.stations)
		local w = Economy.worth(C, Line, S, d.cash, M)
		local star = Economy.star(C, Line, S, d.cash, M)
		if star and star.saving then
			eq(next(w), nil, c[1] .. ": while the ★ saves for the next station, nothing else is green")
		else
			local pb, best = paybacks(S)
			local wrong = {}
			for key, e in pb do
				local want = e.a.kind == "build" or (e.pb < math.huge and e.pb <= k * best + 1e-9)
				if (w[key] == true) ~= want then table.insert(wrong, key) end
			end
			eq(#wrong, 0, c[1] .. ": green = the next station, or a payback within " .. k .. "x the best (" .. table.concat(wrong, ", ") .. ")")
			local bestKey = nil
			for key, e in pb do if e.pb == best then bestKey = key end end
			truthy(bestKey ~= nil and w[bestKey] == true, c[1] .. ": the best payback on the list is always green")
		end
	end
	-- a purchase that adds no income is never green
	do
		local d = profile({ { n = 1, L = 1 }, { n = 1, L = 10 } }, 1e6)
		local S = Line.ordered(C, d.stations)
		local w = Economy.worth(C, Line, S, d.cash, M)
		eq(w["up:2"], nil, "upgrading a Furnace that already handles more than the Shredder sends it is never green")
	end
	-- the ★ saving for the next station: a cheap upgrade the player can afford is NOT green
	do
		-- Shredder L6 x2 earns enough that the Furnace (650) is under a minute away; cash 600 affords every Shredder buy
		local d = profile({ { n = 2, L = 6 } }, 600)
		local S = Line.ordered(C, d.stations)
		local star = Economy.star(C, Line, S, d.cash, M)
		truthy(star and star.saving and star.kind == "build" and star.t == 2, "set-up: the ★ saves for the Furnace")
		local w = Economy.worth(C, Line, S, d.cash, M)
		eq(w["up:1"], nil, "...so the affordable Shredder upgrade is not green")
	end
end

--============================================================================ formatting
eq(Economy.short(0), "0", "0")
eq(Economy.short(999.7), "999", "below 1000 a whole number, rounded down (never more than you have)")
eq(Economy.short(1234), "1.2K", "1.2K")
eq(Economy.short(12345), "12.3K", "12.3K")
eq(Economy.short(123456), "123K", "123K")
eq(Economy.short(3.4e6), "3.4M", "3.4M")
eq(Economy.short(1.2e9), "1.2B", "1.2B")
eq(Economy.short(9.5e12), "9.5T", "9.5T")
eq(Economy.short(-5), "0", "never negative")
eq(Economy.short(0 / 0), "0", "never NaN")
eq(Economy.money(1234), "$1.2K", "money is short with a $")
eq(Economy.rate(3.12), "3.1", "a rate under 10 keeps one decimal")
eq(Economy.rate(1234), "1.2K", "a big rate is compact")
eq(Economy.clock(42), "0:42", "a countdown: 0:42")
eq(Economy.clock(125.2), "2:06", "rounded up: 2:06")
eq(Economy.clock(-3), "0:00", "never negative")

print(string.format("Economy: %d passed, %d failed", passed, failed))
if failed > 0 then error("Economy spec failed", 0) end
