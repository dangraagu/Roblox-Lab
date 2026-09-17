-- Economy.spec — pay, Perfect Shifts, upgrades, and the save sanitizer. Run: luau tests/Economy.spec.luau
--
-- DESIGN.md §6.4 and §8.1. The sanitizer is fed hostile records on purpose: every load runs it,
-- and a save is the one input a client never touched but a bug (or an old version) might have.
local Economy = require("../src/shared/Economy")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

--============================================================ pay

do
	local run = Economy.newRun()
	local pays, total = {}, 0
	for _ = 1, 30 do
		local nextRun, pay, backlog = Economy.deposit(Config, run, true, true)
		table.insert(pays, pay)
		total += pay
		eq(backlog, 1, "a first-try sort takes one item off the backlog")
		run = nextRun
	end
	eq(table.concat(pays, ",", 1, 11), "11,12,13,14,15,16,17,18,19,20,20", "pay runs 11..20 then holds at 20")
	eq(pays[30], 20, "the 30th first-try sort still pays 20")
	eq(total, 555, "30 first-try sorts pay 555")
	eq(run.combo, 30, "the combo counted all 30")
	eq(run.sorted, 30, "30 sorted")
	eq(run.firstTry, 30, "30 first tries")
	eq(run.pay, 555, "the run banks 555")
end

do
	local run = Economy.newRun()
	run = (Economy.deposit(Config, run, true, true))
	run = (Economy.deposit(Config, run, true, true))
	eq(run.combo, 2, "two first tries: combo 2")
	local before = run
	local afterMiss, missPay, missBacklog = Economy.deposit(Config, run, false, true)
	eq(missPay, 0, "a misfile pays nothing")
	eq(missBacklog, 0, "a misfile adds no backlog")
	eq(afterMiss.combo, 0, "a misfile resets the combo")
	eq(afterMiss.misfiles, 1, "a misfile is counted")
	eq(afterMiss.sorted, 2, "a misfile sorts nothing")
	eq(before.combo, 2, "deposit never mutates its input run")

	local afterResort, resortPay, resortBacklog = Economy.deposit(Config, afterMiss, true, false)
	eq(resortPay, 5, "a correct re-sort after a misfile pays 5")
	eq(resortBacklog, 0, "a re-sort adds no backlog")
	eq(afterResort.combo, 0, "a re-sort does not grow the combo")
	eq(afterResort.sorted, 3, "a re-sort is still sorted")
	eq(afterResort.firstTry, 2, "a re-sort is not a first try")

	-- a re-sort in the middle of a streak leaves the streak where it was
	local streak = Economy.newRun()
	for _ = 1, 4 do streak = (Economy.deposit(Config, streak, true, true)) end
	local mid = (Economy.deposit(Config, streak, true, false))
	eq(mid.combo, 4, "a re-sort leaves an unbroken combo untouched")
	local _, nextPay = Economy.deposit(Config, mid, true, true)
	eq(nextPay, 15, "... so the next first try pays 10 + 5")
end

--============================================================ Perfect Shift

eq(Economy.isPerfect(Config, 30, 30, 3, false), true, "30/30 with 3 misfiles is Perfect")
eq(Economy.isPerfect(Config, 30, 30, 4, false), false, "30/30 with 4 misfiles is not")
eq(Economy.isPerfect(Config, 29, 30, 0, false), false, "29/30 is not Perfect")
eq(Economy.isPerfect(Config, 30, 30, 0, true), false, "a shift the clock ended is never Perfect")
eq(Economy.shiftPay(Config, 555, true), 655, "the Perfect bonus is 100 on top (max 655)")
eq(Economy.shiftPay(Config, 555, false), 555, "no bonus without Perfect")

--============================================================ upgrades

eq(Economy.price(Config, 0), 250, "level 1 costs 250")
eq(Economy.price(Config, 1), 800, "level 2 costs 800")
eq(Economy.price(Config, 2), 2000, "level 3 costs 2000")
eq(Economy.price(Config, 3), nil, "nothing past level 3")
eq(Economy.carry(Config, 0), 2, "carry 2 at cart level 0")
eq(Economy.carry(Config, 3), 5, "carry 5 at cart level 3")
eq(Economy.walkSpeed(Config, 0), 16, "walk 16 at shoes level 0")
eq(Economy.walkSpeed(Config, 3), 22, "walk 22 at shoes level 3")
eq(Economy.carry(Config, 99), 5, "carry clamps a bad level")
eq(Economy.walkSpeed(Config, -4), 16, "walk speed clamps a bad level")

do
	local p = Economy.defaultProfile(Config)
	p.cash = 1000
	local ok, res, price = Economy.buy(Config, p, "cart")
	eq(ok, true, "buying the cart with 1000")
	eq(price, 250, "... costs 250")
	eq(res.cash, 750, "... leaves 750")
	eq(res.cartLevel, 1, "... and raises the cart to level 1")
	eq(p.cash, 1000, "buy never mutates its input (cash)")
	eq(p.cartLevel, 0, "buy never mutates its input (level)")

	local ok2, reason2, price2 = Economy.buy(Config, res, "cart")
	eq(ok2, false, "level 2 at 750 cash is refused")
	eq(reason2, "cash", "... for cash")
	eq(price2, 800, "... and reports the price")

	local maxed = Economy.defaultProfile(Config)
	maxed.cash = 1e6
	maxed.shoesLevel = 3
	local ok3, reason3 = Economy.buy(Config, maxed, "shoes")
	eq(ok3, false, "shoes past level 3 are refused")
	eq(reason3, "max", "... as max")
	eq(maxed.cash, 1e6, "... and cost nothing")

	local ok4, reason4 = Economy.buy(Config, p, "rocket")
	eq(ok4, false, "an unknown track is refused")
	eq(reason4, "track", "... as an unknown track")

	-- exactly affordable
	local exact = Economy.defaultProfile(Config)
	exact.cash = 250
	local ok5, res5 = Economy.buy(Config, exact, "shoes")
	eq(ok5, true, "exactly 250 buys shoes level 1")
	eq(res5.cash, 0, "... leaving 0")
end

--============================================================ sanitize

do
	local d = Economy.defaultProfile(Config)
	eq(d.v, 1, "default profile version 1")
	eq(d.cash, 0, "starts with 0 cash")
	eq(d.shifts, 0, "starts with 0 shifts")
	eq(d.endingSeen, false, "ending not seen")
	eq(type(d.redeemed), "table", "an empty redeemed set")

	local nan = 0 / 0
	local s = Economy.sanitize(Config, {
		v = 99,
		cash = nan,
		cartLevel = 7,
		shoesLevel = -2,
		shifts = 12.9,
		perfects = 50,
		backlog = 9999,
		bestPerfectSeconds = "fast",
		endingSeen = "yes",
		redeemed = { SORTED = true, [5] = true, BAD = "true", [string.rep("X", 40)] = true },
		hacked = true,
		cart = { 1, 2, 3 },
	})
	eq(s.v, 1, "version is forced to 1")
	eq(s.cash, 0, "NaN cash becomes 0")
	eq(s.cartLevel, 3, "cart level clamps to 3")
	eq(s.shoesLevel, 0, "a negative shoes level becomes 0")
	eq(s.shifts, 12, "shifts are floored")
	eq(s.perfects, 12, "perfects cannot exceed shifts")
	eq(s.backlog, 500, "backlog clamps to the backlog size")
	eq(s.bestPerfectSeconds, 0, "a string best becomes 0")
	eq(s.endingSeen, false, "a non-boolean endingSeen is false")
	eq(s.redeemed.SORTED, true, "a real redeemed code survives")
	eq(s.redeemed[5], nil, "an integer key in redeemed is dropped")
	eq(s.redeemed["5"], nil, "... and does not come back as a string")
	eq(s.redeemed.BAD, nil, "a non-true redeemed value is dropped")
	eq(s.redeemed[string.rep("X", 40)], nil, "an over-long code key is dropped")
	eq(s.hacked, nil, "unknown keys are dropped")
	eq(s.cart, nil, "no shift state survives a load")

	local neg = Economy.sanitize(Config, { cash = -50, shifts = -3, perfects = -1, backlog = -8 })
	eq(neg.cash, 0, "negative cash becomes 0")
	eq(neg.shifts, 0, "negative shifts become 0")
	eq(neg.perfects, 0, "negative perfects become 0")
	eq(neg.backlog, 0, "negative backlog becomes 0")

	local inf = Economy.sanitize(Config, { cash = math.huge, shifts = "12" })
	eq(inf.cash, 0, "infinite cash becomes 0")
	eq(inf.shifts, 0, "a string shift count becomes 0")

	eq(Economy.sanitize(Config, nil).cash, 0, "a nil record sanitizes to defaults")
	eq(Economy.sanitize(Config, "garbage").shifts, 0, "a string record sanitizes to defaults")

	local good = Economy.sanitize(Config, { cash = 1234, cartLevel = 2, shoesLevel = 1, shifts = 20, perfects = 9,
		backlog = 312, bestPerfectSeconds = 141.5, endingSeen = true, redeemed = { SORTED = true } })
	eq(good.cash, 1234, "a sane record keeps its cash")
	eq(good.cartLevel, 2, "... cart level")
	eq(good.shoesLevel, 1, "... shoes level")
	eq(good.perfects, 9, "... perfects")
	eq(good.backlog, 312, "... backlog")
	eq(good.bestPerfectSeconds, 141, "... best (floored)")
	eq(good.endingSeen, true, "... ending")

	-- Every key a sanitized profile carries is a string, so the DataStore JSON round-trip has
	-- nothing to turn from an integer into a string (the checklist's integer-key trap).
	local nonString = 0
	local function walk(t)
		for k, v in t do
			if type(k) ~= "string" then nonString += 1 end
			if type(v) == "table" then walk(v) end
		end
	end
	walk(good)
	eq(nonString, 0, "a sanitized profile has only string keys, all the way down")
end

--============================================================ merge: a read-only session's progress, applied on top of the store

-- REVIEW-1 R1-3 and R2-6. A session that could not take the save lock at join (another server's
-- lock had not expired yet, or the load itself failed) used to stay read-only for the whole
-- session, and everything it earned was lost. When the lock frees up, the session writes its OWN
-- DELTA (what it earned and spent since it loaded) on top of whatever the store holds now, never
-- its whole profile: the store may hold progress this session never saw.
do
	local defaults = Economy.defaultProfile(Config)
	local veteran = { v = 1, cash = 1000, cartLevel = 1, shoesLevel = 1, shifts = 7, perfects = 2, backlog = 120,
		bestPerfectSeconds = 90, endingSeen = false, redeemed = { SORTED = true } }

	-- the load failed: the session started from defaults and played two shifts as a new player
	local played = { v = 1, cash = 190, cartLevel = 0, shoesLevel = 0, shifts = 2, perfects = 1, backlog = 55,
		bestPerfectSeconds = 80, endingSeen = false, redeemed = {} }
	local vetCopy = table.clone(veteran)
	local m = Economy.merge(Config, veteran, defaults, played)
	eq(m.cash, 1190, "merge adds the session's cash delta to the stored cash")
	eq(m.shifts, 9, "... its shifts")
	eq(m.perfects, 3, "... its perfects")
	eq(m.backlog, 175, "... its backlog")
	eq(m.cartLevel, 1, "... and keeps the stored cart level the session never lowered")
	eq(m.shoesLevel, 1, "... and shoes level")
	eq(m.bestPerfectSeconds, 80, "the faster personal best wins")
	eq(m.redeemed.SORTED, true, "stored redemptions survive")
	eq(veteran.cash, vetCopy.cash, "merge does not mutate the stored record")
	eq(played.cash, 190, "... or the session profile")

	-- nothing changed elsewhere: the session's profile is the answer
	local base = table.clone(veteran)
	base.redeemed = { SORTED = true }
	local spent = table.clone(veteran)
	spent.redeemed = { SORTED = true }
	spent.cash = 750
	spent.cartLevel = 2
	spent.shifts = 8
	local same = Economy.merge(Config, veteran, base, spent)
	eq(same.cash, 750, "with the store unchanged since the load, merge is the session's cash")
	eq(same.cartLevel, 2, "... and its purchase")
	eq(same.shifts, 8, "... and its shifts")

	-- clamps
	local nearEnd = table.clone(veteran)
	nearEnd.backlog = 490
	nearEnd.redeemed = {}
	local c = Economy.merge(Config, nearEnd, defaults, { v = 1, cash = 0, cartLevel = 3, shoesLevel = 0, shifts = 3,
		perfects = 3, backlog = 30, bestPerfectSeconds = 0, endingSeen = true, redeemed = {} })
	eq(c.backlog, 500, "the merged backlog is clamped to BacklogSize")
	eq(c.cartLevel, 3, "the merged cart level is clamped to MaxLevel")
	eq(c.endingSeen, true, "endingSeen from either side survives")
	eq(c.bestPerfectSeconds, 90, "a session with no Perfect best keeps the stored best")
	local poor = Economy.merge(Config, { v = 1, cash = 100, shifts = 1, redeemed = {} },
		{ v = 1, cash = 1000, shifts = 0, redeemed = {} }, { v = 1, cash = 750, shifts = 0, redeemed = {} })
	eq(poor.cash, 0, "a merged cash never goes negative")
	truthy(poor.perfects <= poor.shifts, "merged perfects never exceed merged shifts")

	-- a garbage store record is a default one
	local g = Economy.merge(Config, "garbage", defaults, played)
	eq(g.cash, 190, "a garbage stored record merges as defaults")
	eq(g.shifts, 2, "... shifts too")
end

--============================================================ merge: purchases made on a stale balance

-- REVIEW-1 pass 3, exploit finding 2. A server hop: the old session bought the cart twice (1050 ->
-- 0, unsaved); the new session loaded the stale 1050 read-only and bought the shoes twice; the old
-- session's release landed (cash 0, cart 2). The merge added the new session's -1050 to 0, floored
-- it at 0, and KEPT the shoes: 1050 cash bought 2100 of upgrades. A purchase is re-priced at the
-- level it lands on in the store, and one the stored cash cannot cover is undone.
local function worth(p)
	local w = 0
	for _, field in { "cartLevel", "shoesLevel" } do
		for l = 1, p[field] or 0 do w += Config.Economy.Prices[l] end
	end
	return w
end
do
	local stale = { v = 1, cash = 1050, cartLevel = 0, shoesLevel = 0, shifts = 7, perfects = 2, backlog = 120,
		bestPerfectSeconds = 90, endingSeen = false, redeemed = {} }
	local released = table.clone(stale) -- what the old session's release wrote
	released.cash, released.cartLevel, released.redeemed = 0, 2, {}
	local spent = table.clone(stale) -- the new session bought the shoes twice on the stale 1050
	spent.cash, spent.shoesLevel, spent.redeemed = 0, 2, {}
	local m = Economy.merge(Config, released, stale, spent)
	eq(m.shoesLevel, 0, "E2: shoes bought on a balance the store no longer has are undone")
	eq(m.cartLevel, 2, "E2: ... the store's own purchases stay")
	eq(m.cash, 0, "E2: ... and the cash is what the store holds")
	truthy(worth(m) <= 1050, "E2: the merged upgrades are worth no more than the 1050 cash ever earned (worth " .. worth(m) .. ")")

	-- the store holds 300: one level of shoes (250) is covered, the second (800) is not
	local some = table.clone(released)
	some.cash, some.redeemed = 300, {}
	local m2 = Economy.merge(Config, some, stale, spent)
	eq(m2.shoesLevel, 1, "E2: the purchase the stored cash covers stays")
	eq(m2.cash, 50, "E2: ... paid for at its price (300 - 250)")

	-- earnings still count: the session also earned 400 after buying
	local earned = table.clone(spent)
	earned.cash, earned.redeemed = 400, {}
	local m3 = Economy.merge(Config, released, stale, earned)
	eq(m3.shoesLevel, 1, "E2: ... the 400 earned covers the first shoes level, not the second")
	eq(m3.cash, 150, "E2: ... leaving 150")

	-- re-priced at the level it lands on: the store already has cart 2 and 5000 cash; the session
	-- bought cart 0 -> 2 for 1050. Only one level fits (3), and level 3 costs 2000.
	local rich = table.clone(released)
	rich.cash, rich.redeemed = 5000, {}
	local cartTwice = table.clone(stale)
	cartTwice.cash, cartTwice.cartLevel, cartTwice.redeemed = 0, 2, {}
	local m4 = Economy.merge(Config, rich, stale, cartTwice)
	eq(m4.cartLevel, 3, "E2: a purchase past MaxLevel is dropped")
	eq(m4.cash, 3000, "E2: ... the level that fits costs its own price (5000 - 2000), and the one that did not is refunded")

	-- CONTROL: the store unchanged since the load, a purchase is simply the session's
	local calm = Economy.merge(Config, stale, stale, spent)
	eq(calm.shoesLevel, 2, "CONTROL: with the store unchanged, both shoes purchases stand")
	eq(calm.cash, 0, "CONTROL: ... and the cash is the session's")
	eq(stale.cash, 1050, "CONTROL: merge mutates none of its inputs")
end

--============================================================ personal best

eq(Economy.betterBest(0, 150), 150, "the first Perfect sets the best")
eq(Economy.betterBest(150, 140), 140, "a faster Perfect replaces it")
eq(Economy.betterBest(140, 160), 140, "a slower Perfect does not")

print(string.format("Economy: %d passed, %d failed", passed, failed))
if failed > 0 then error("Economy tests failed") end
