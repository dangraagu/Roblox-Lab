-- Rene tester for Economy. Kjør: luau tests/Economy.spec.luau
--
-- Server-authoritative shop and backpack, modelled on grow-a-crystal's Economy: every buy
-- function validates first and mutates the profile ONLY on success, and every rejection has a
-- named reason so the server can tell the player why instead of returning silently.

local Economy = require("../src/shared/Economy")
local Ore = require("../src/shared/Ore")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local ec = Config.Economy

local function newProfile()
	return {
		cash = 0, totalCash = 0, runEarned = 0,
		inventory = {},
		pickTier = 1, backpackLevel = 0, lampLevel = 0,
		rebirths = 0, depth = 0, bestDepth = 0,
	}
end

--============================================================================ swings

eq(Economy.swingPower(Config, 1), 5, "the rusty pick hits for 5")
eq(Economy.swingPower(Config, 5), 170, "the singularity bore hits for 170")
eq(Economy.swingPower(Config, 0), 5, "an impossible tier falls back to tier 1 rather than 0 damage")
eq(Economy.swingPower(Config, 99), 170, "…and a too-high tier is clamped to the top")
eq(Economy.pickaxeName(Config, 3), "Carbide Drill", "pickaxes are named")

eq(Economy.hitsToBreak(10, 5), 2, "10 hp at 5 power is two swings")
eq(Economy.hitsToBreak(11, 5), 3, "a remainder costs a whole extra swing")
eq(Economy.hitsToBreak(3, 170), 1, "an overkill swing is still one swing")
eq(Economy.hitsToBreak(10, 0), math.huge, "a zero-power pick can never break anything")

--============================================================================ pickaxe upgrades

eq(Economy.nextPickaxeCost(Config, 1), 260, "tier 2 costs 260")
eq(Economy.nextPickaxeCost(Config, 4), 140000, "tier 5 costs 140000")
eq(Economy.nextPickaxeCost(Config, 5), nil, "there is nothing past the top tier")

do
	local p = newProfile()
	local ok, reason = Economy.buyPickaxe(p, Config)
	eq(ok, false, "you cannot buy a pickaxe with no cash"); eq(reason, "poor", "…and it says why")
	eq(p.pickTier, 1, "a failed buy does not upgrade")

	p.cash = 260
	ok, reason = Economy.buyPickaxe(p, Config)
	eq(ok, true, "260 buys the steel pick"); eq(reason, "ok", "…with an ok reason")
	eq(p.pickTier, 2, "the tier went up"); eq(p.cash, 0, "the cash went down")
	eq(Economy.swingPower(Config, p.pickTier), 12, "and the swing got stronger")

	p.pickTier = ec.Pickaxe.MaxTier
	p.cash = 1e9
	ok, reason = Economy.buyPickaxe(p, Config)
	eq(ok, false, "the top tier cannot be bought again"); eq(reason, "max", "…max reason")
	eq(p.cash, 1e9, "and a maxed buy costs nothing")
end

--============================================================================ backpack

eq(Economy.backpackCapacity(Config, 0), 12, "a fresh backpack holds 12")
eq(Economy.backpackCapacity(Config, 1), 18, "each level adds 6")
eq(Economy.backpackCapacity(Config, ec.Backpack.MaxLevel), 84, "a maxed backpack holds 84")
eq(Economy.backpackCost(Config, 0), 130, "the first backpack level costs 130")
eq(Economy.backpackCost(Config, 1), math.floor(130 * 1.55), "backpack cost grows")
eq(Economy.backpackCost(Config, 2), math.floor(130 * 1.55 ^ 2), "…geometrically")

do
	local p = newProfile()
	local ok, reason = Economy.buyBackpack(p, Config)
	eq(ok, false, "no cash, no backpack"); eq(reason, "poor", "poor reason")
	p.cash = 130
	eq(Economy.buyBackpack(p, Config), true, "130 buys a backpack level")
	eq(p.backpackLevel, 1, "level up"); eq(p.cash, 0, "cash spent")
	p.backpackLevel = ec.Backpack.MaxLevel; p.cash = 1e9
	ok, reason = Economy.buyBackpack(p, Config)
	eq(ok, false, "a maxed backpack is refused"); eq(reason, "max", "max reason")
end

--============================================================================ lamp

eq(Economy.lampRadius(Config, 0), 26, "a fresh lamp reaches 26 studs")
eq(Economy.lampRadius(Config, 8), 74, "a maxed lamp reaches 74")
eq(Economy.lampCost(Config, 0), 160, "the first lamp level costs 160")
eq(Economy.lampCost(Config, 1), math.floor(160 * 1.6), "lamp cost grows")

do
	local p = newProfile()
	p.cash = 160
	eq(Economy.buyLamp(p, Config), true, "160 buys a lamp level")
	eq(p.lampLevel, 1, "lamp level up")
	eq(Economy.lampRadius(Config, p.lampLevel), 32, "and the light actually got bigger")
	p.lampLevel = ec.Lamp.MaxLevel; p.cash = 1e9
	local ok, reason = Economy.buyLamp(p, Config)
	eq(ok, false, "a maxed lamp is refused"); eq(reason, "max", "max reason")
end

--============================================================================ the backpack fills

do
	local p = newProfile()
	eq(Economy.carried(p), 0, "an empty backpack carries nothing")
	eq(Economy.spaceLeft(p, Config), 12, "…and has all its room")

	eq(Economy.addOre(p, Config, 1, 3), 3, "three copper fit")
	eq(Economy.carried(p), 3, "and they are in there")
	eq(p.inventory[1], 3, "under their own tier")

	eq(Economy.addOre(p, Config, 3, 4), 4, "four gold fit alongside")
	eq(Economy.carried(p), 7, "seven units carried")
	eq(Economy.spaceLeft(p, Config), 5, "five to go")

	-- The case that decides whether a full backpack is a bug or a mechanic: a partial accept,
	-- reported honestly, so the server can say "backpack full" rather than silently eating ore.
	eq(Economy.addOre(p, Config, 2, 9), 5, "only what fits is accepted")
	eq(Economy.carried(p), 12, "the backpack is now exactly full")
	eq(Economy.spaceLeft(p, Config), 0, "with no room left")
	eq(Economy.addOre(p, Config, 2, 1), 0, "a full backpack accepts nothing")
	eq(Economy.carried(p), 12, "and does not overfill")
	eq(Economy.addOre(p, Config, 1, 0), 0, "adding zero is a no-op")
	eq(Economy.addOre(p, Config, 0, 5), 0, "plain stone is never picked up")
	eq(Economy.carried(p), 12, "…and does not take a slot")
end

--============================================================================ selling the haul

do
	local p = newProfile()
	Economy.addOre(p, Config, 1, 3) -- 3 copper  = 18
	Economy.addOre(p, Config, 3, 2) -- 2 gold    = 140
	eq(Economy.haulValue(Config, Ore, p.inventory, 1), 158, "a haul is worth the sum of its ore")
	eq(Economy.haulValue(Config, Ore, p.inventory, 1.8), math.floor(158 * 1.8), "the multiplier applies to the whole haul")
	eq(Economy.haulValue(Config, Ore, {}, 5), 0, "an empty haul is worth nothing")
	eq(Economy.haulValue(Config, Ore, { [0] = 99 }, 1), 0, "stone is worth nothing however much of it you carry")

	local got = Economy.sell(p, Config, Ore, 1)
	eq(got, 158, "selling pays out the haul value")
	eq(p.cash, 158, "into the wallet")
	eq(p.totalCash, 158, "and onto the lifetime total")
	eq(p.runEarned, 158, "…and onto THIS RUN's earnings, which is what the rebirth gate reads")
	eq(Economy.carried(p), 0, "the backpack is emptied")
	eq(next(p.inventory), nil, "…completely")
	eq(Economy.sell(p, Config, Ore, 1), 0, "selling an empty backpack pays nothing")
	eq(p.cash, 158, "and does not touch the wallet")
	eq(p.runEarned, 158, "…nor this run's earnings")
end

do
	-- RUN EARNINGS ARE MONOTONE, AND THAT IS THE WHOLE POINT OF THEM. The rebirth gate used to
	-- read the wallet, and the shop offers more than a whole shaft's worth of upgrades, so a
	-- player could buy themselves permanently out of a rebirth in a cave that does not refill.
	-- Every sale adds to this figure and NOTHING subtracts from it.
	local p = newProfile()
	Economy.addOre(p, Config, 4, 3) -- 3 diamond
	local first = Economy.sell(p, Config, Ore, 1)
	Economy.addOre(p, Config, 2, 5) -- 5 iron
	local second = Economy.sell(p, Config, Ore, 1)
	eq(p.runEarned, first + second, "earnings accumulate across sales")
	local before = p.runEarned
	local cashBefore = p.cash
	Economy.buyPickaxe(p, Config)
	Economy.buyBackpack(p, Config)
	Economy.buyLamp(p, Config)
	truthy(p.cash < cashBefore, "CONTROL: the shopping really did take cash out of the wallet ("
		.. cashBefore .. " -> " .. p.cash .. ")")
	eq(p.runEarned, before, "spending every upgrade track does not move this run's earnings")
	-- CASH CAN NEVER EXCEED EARNINGS. The server leans on exactly this to migrate a profile
	-- written before runEarned existed (it credits the cash in hand rather than zero), and it is
	-- also what makes "earned" a strictly weaker gate than "held" rather than a different one.
	do
		local m = newProfile()
		local violations = 0
		for step = 1, 60 do
			Economy.addOre(m, Config, (step % 5) + 1, 2)
			if step % 3 == 0 then Economy.sell(m, Config, Ore, 1 + (step % 4) * 0.8) end
			if step % 4 == 0 then Economy.buyPickaxe(m, Config) end
			if step % 5 == 0 then Economy.buyBackpack(m, Config) end
			if step % 7 == 0 then Economy.buyLamp(m, Config) end
			if m.cash > m.runEarned then violations += 1 end
		end
		eq(violations, 0, "cash never exceeds this run's earnings, over 60 mixed sells and buys")
		truthy(m.runEarned > 0, "CONTROL: that walk really did earn something ($" .. m.runEarned .. ")")
	end

	-- …and the multiplier is inside the figure, because the price is too.
	local q = newProfile()
	Economy.addOre(q, Config, 4, 1)
	eq(Economy.sell(q, Config, Ore, 2.5), math.floor(Ore.value(Config, 4) * 2.5), "a x2.5 sale pays x2.5")
	eq(q.runEarned, math.floor(Ore.value(Config, 4) * 2.5), "…and banks x2.5 of earnings")
end

do
	-- totalCash is the lifetime figure. Spending must never reduce it, or every leaderboard and
	-- rebirth threshold built on it is farmable by buying something and selling nothing.
	local p = newProfile()
	Economy.addOre(p, Config, 5, 1)
	Economy.sell(p, Config, Ore, 1)
	eq(p.cash, 800, "one obsidian is 800")
	eq(p.totalCash, 800, "lifetime 800")
	Economy.buyPickaxe(p, Config)
	eq(p.cash, 800 - 260, "the pickaxe came out of the wallet")
	eq(p.totalCash, 800, "but the lifetime total is untouched by spending")
end

--============================================================================ THE CONTROL
-- The cave has nothing to do with the shop. Rewriting the entire cave generator's config —
-- a different seed, a different grid, a different carving threshold, a different depth wall —
-- must not move one price, one capacity or one swing. If it does, the two are coupled through
-- something neither of them declares, and tuning the cave would silently reprice the game.

do
	local shadow = table.clone(Config)
	shadow.WorldSeed = 1
	shadow.Mine = table.clone(Config.Mine)
	shadow.Mine.AirThreshold = 0.1
	shadow.Mine.GridW = 31
	shadow.Mine.BaseMaxLayer = 4
	shadow.Mine.CellSize = 99
	shadow.Mine.HardnessPerLayer = 5

	for t = 1, ec.Pickaxe.MaxTier do
		eq(Economy.swingPower(shadow, t), Economy.swingPower(Config, t), "CONTROL: swing power " .. t .. " unchanged")
		eq(Economy.nextPickaxeCost(shadow, t), Economy.nextPickaxeCost(Config, t), "CONTROL: pickaxe cost " .. t .. " unchanged")
	end
	for l = 0, ec.Backpack.MaxLevel do
		eq(Economy.backpackCapacity(shadow, l), Economy.backpackCapacity(Config, l), "CONTROL: capacity " .. l .. " unchanged")
		eq(Economy.backpackCost(shadow, l), Economy.backpackCost(Config, l), "CONTROL: backpack cost " .. l .. " unchanged")
	end
	for l = 0, ec.Lamp.MaxLevel do
		eq(Economy.lampRadius(shadow, l), Economy.lampRadius(Config, l), "CONTROL: lamp radius " .. l .. " unchanged")
	end
	eq(Economy.haulValue(shadow, Ore, { [2] = 4 }, 1), Economy.haulValue(Config, Ore, { [2] = 4 }, 1),
		"CONTROL: a haul is worth the same in a completely different cave")
end

print(string.format("Economy: %d passed, %d failed", passed, failed))
assert(failed == 0, "Economy tests failed")
