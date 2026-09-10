-- Rene tester for Prestige. Kjør: luau tests/Prestige.spec.luau
--
-- Rebirth is the only irreversible button in the game, so the three things that matter most here
-- are (a) it refuses cleanly rather than half-applying, (b) it does NOT wipe the two figures the
-- leaderboard is built on, and (c) THE PRICE IS PAYABLE OUT OF THE CAVE IT IS CHARGED AGAINST,
-- at every one of the 25 levels, without being so cheap that the cave stops mattering.

local Prestige = require("../src/shared/Prestige")
local Ore = require("../src/shared/Ore")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function near(a, b, msg, tol)
	tol = tol or 1e-9
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want ~", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local pc = Config.Prestige

local function newProfile()
	return {
		cash = 0, totalCash = 0, runEarned = 0, inventory = {},
		pickTier = 1, backpackLevel = 0, lampLevel = 0,
		rebirths = 0, depthLayer = 0, bestLayer = 0,
	}
end

--============================================================================ the curves

-- The price is PriceFraction of what the whole shaft holds, in ore, re-quoted by the same
-- multiplier that inflates every sale. The figures below are the recorded output of that
-- arithmetic, written out by hand: recomputing the formula from the module would grade it
-- against itself.
eq(Prestige.requirement(Config, Ore, 0), 6473, "the first rebirth costs 6473")
eq(Prestige.requirement(Config, Ore, 1), 26187, "the second is 26187 — a bigger cave AND a 1.8x multiplier")
eq(Prestige.requirement(Config, Ore, 2), 64233, "…and the third 64233")
near(Prestige.shaftOre(Config, Ore, 0), 26971.0112, "a whole rebirth-0 shaft holds 26971 of ore, in expectation", 1e-3)
for r = 0, 23 do
	truthy(Prestige.requirement(Config, Ore, r + 1) > Prestige.requirement(Config, Ore, r),
		"rebirth " .. (r + 1) .. " costs more than rebirth " .. r)
end

-- THE PRICE IS A CONSTANT FRACTION OF THE CAVE, BY CONSTRUCTION. This is the property the whole
-- design rests on: not "the curve was fitted to the world" but "the curve IS the world". Any r at
-- which it drifts means Prestige.requirement stopped reading the ore table.
for r = 0, pc.MaxRebirths - 1 do
	local frac = Prestige.requirement(Config, Ore, r)
		/ (Prestige.shaftOre(Config, Ore, r) * Prestige.multiplier(Config, r))
	-- 1e-4 rather than 1e-9: the requirement is floored to whole cash, which is worth up to one
	-- part in 6473 of the fraction at the cheapest rebirth in the game.
	near(frac, pc.PriceFraction, "rebirth " .. r .. " costs exactly PriceFraction of its own shaft", 1e-4)
end

-- ANTI-DRIFT: Prestige duplicates Mine.maxLayer's arithmetic so it can depend on Ore alone.
-- If the two ever disagree the price is integrating a different world from the one being dug.
do
	local Mine = require("../src/shared/Mine")
	for r = 0, pc.MaxRebirths do
		local viaMine = Mine.maxLayer(Config, r)
		local viaPrestige = Config.Mine.BaseMaxLayer + r * Config.Mine.LayersPerRebirth
		eq(viaPrestige, viaMine, "the wall Prestige prices at rebirth " .. r .. " is the wall Mine builds")
	end
end

near(Prestige.multiplier(Config, 0), 1, "a fresh miner has no multiplier")
near(Prestige.multiplier(Config, 1), 1.8, "one rebirth is 1.8x")
near(Prestige.multiplier(Config, 4), 1 + 4 * 0.8, "four rebirths is 4.2x")
for r = 0, 10 do
	truthy(Prestige.multiplier(Config, r + 1) > Prestige.multiplier(Config, r),
		"the multiplier always goes up")
end

do
	local p = newProfile()
	near(Prestige.progress(p, Config, Ore), 0, "no earnings is no progress")
	p.runEarned = Prestige.requirement(Config, Ore, 0) / 2
	near(Prestige.progress(p, Config, Ore), 0.5, "half the requirement is half the bar")
	-- THE BAR READS EARNINGS, NOT THE WALLET, or a player watches it fall every time they shop.
	p.cash = 0
	near(Prestige.progress(p, Config, Ore), 0.5, "…and spending the cash does not empty the bar")
	p.runEarned = 99999999999
	near(Prestige.progress(p, Config, Ore), 1, "the bar is clamped at full")
	p.rebirths = pc.MaxRebirths
	near(Prestige.progress(p, Config, Ore), 1, "a maxed miner's bar is full, not a divide by zero")
end

--============================================================================ the gate

do
	local need = Prestige.requirement(Config, Ore, 0)
	local p = newProfile()
	local ok, reason = Prestige.canRebirth(p, Config, Ore)
	eq(ok, false, "you cannot rebirth having earned nothing"); eq(reason, "poor", "…and it says why")

	p.runEarned = need - 1
	eq(Prestige.canRebirth(p, Config, Ore), false, "one short is still short")
	p.runEarned = need
	local ok2, r2 = Prestige.canRebirth(p, Config, Ore)
	eq(ok2, true, "exactly the requirement is enough"); eq(r2, "ok", "ok reason")

	-- A WALLET FULL OF CASH YOU DID NOT EARN THIS RUN IS NOT A REBIRTH. (It cannot happen in the
	-- shipped game — the only source of cash is a sale, and a sale banks earnings — but the gate
	-- must be on the monotone figure, not on the spendable one, and this is what says so.)
	local rich = newProfile()
	rich.cash = need * 1000
	eq(Prestige.canRebirth(rich, Config, Ore), false, "the gate reads earnings, not the wallet")

	p.rebirths = pc.MaxRebirths
	p.runEarned = 1e12
	local ok3, r3 = Prestige.canRebirth(p, Config, Ore)
	eq(ok3, false, "there is a ceiling"); eq(r3, "max", "max reason")
end

--============================== YOU CANNOT SPEND YOURSELF OUT OF A REBIRTH (REVIEW-2, finding 2)

-- The exact reachable sequence the review ran: mine the whole rebirth-0 shaft, then walk into the
-- shop and buy everything you can afford. Against a gate on the WALLET that ended at $2,172 in
-- hand versus a $3,500 price, with an empty cave, no refill and no way back — a permanent dead
-- end reached by playing the game as it presents itself. Against a gate on EARNINGS the same
-- shopping spree cannot touch the rebirth at all.
do
	local Economy = require("../src/shared/Economy")
	local Mine = require("../src/shared/Mine")
	local W = Config.Mine.GridW

	-- Sell the entire rebirth-0 shaft, one cell at a time, through the real economy.
	local p = newProfile()
	local w0 = Mine.world(Config, 0)
	local cells = 0
	for y = 1, w0.maxLayer do
		for x = 2, W - 1 do
			for z = 2, W - 1 do
				local c = Mine.cell(Config, Ore, w0, x, y, z)
				if c.kind == "rock" and Ore.isOre(Config, c.ore) then
					p.inventory[c.ore] = (p.inventory[c.ore] or 0) + Ore.yieldOf(Config, c.ore)
					cells += 1
				end
			end
		end
	end
	Economy.sell(p, Config, Ore, Prestige.multiplier(Config, 0))
	local wholeShaft = p.runEarned
	truthy(cells > 100, "CONTROL: the whole rebirth-0 shaft really was harvested (" .. cells .. " ore cells)")
	truthy(Prestige.canRebirth(p, Config, Ore), "a player who mined out their whole cave can rebirth ($"
		.. wholeShaft .. " earned vs $" .. Prestige.requirement(Config, Ore, 0) .. ")")

	-- Now the shopping spree: buy anything affordable, in the order the HUD offers it, until
	-- nothing is affordable any more.
	local bought = 0
	local spinning = true
	while spinning do
		spinning = false
		for _, buy in { Economy.buyPickaxe, Economy.buyBackpack, Economy.buyLamp } do
			if buy(p, Config) then bought += 1; spinning = true end
		end
	end
	truthy(bought >= 10, "CONTROL: the shop really did take " .. bought .. " purchases")
	truthy(p.cash < Prestige.requirement(Config, Ore, 0),
		"CONTROL: and it left the WALLET short of the rebirth ($" .. math.floor(p.cash)
			.. " vs $" .. Prestige.requirement(Config, Ore, 0) .. ") — the old gate's dead end")
	local ok, reason = Prestige.canRebirth(p, Config, Ore)
	eq(ok, true, "…and the rebirth is still available, because earnings cannot be spent")
	eq(reason, "ok", "…with no reason to refuse")
	eq(p.runEarned, wholeShaft, "the spree did not move this run's earnings by one cash")
end

--============================================================================ applying it

do
	local p = newProfile()
	p.cash = 55000
	p.runEarned = Prestige.requirement(Config, Ore, 0)
	p.totalCash = 120000
	p.inventory = { [3] = 7 }
	p.pickTier = 4
	p.backpackLevel = 5
	p.lampLevel = 3
	p.depthLayer = 24
	p.bestLayer = 25
	p.openedBits = "AAAAsomethingBBBB"

	local ok, reason = Prestige.apply(p, Config, Ore)
	eq(ok, true, "rebirth applies"); eq(reason, "ok", "ok reason")

	eq(p.rebirths, 1, "the rebirth counter went up")
	eq(p.cash, Config.Economy.StartCash, "cash is wiped")
	eq(p.runEarned, 0, "this run's earnings are wiped — the next price is charged against the NEW cave")
	eq(next(p.inventory), nil, "the haul is wiped")
	eq(p.pickTier, 1, "the pickaxe goes back to rusty")
	eq(p.backpackLevel, 0, "the backpack goes back to base")
	eq(p.lampLevel, 0, "the lamp goes back to base")
	eq(p.depthLayer, 0, "this run's depth is wiped — the cave is new, the old depth means nothing")
	-- The dug-out cells belong to the cave being thrown away. Carrying them into a cave generated
	-- from a different seed would punch holes in it at coordinates that mean nothing there.
	eq(p.openedBits, nil, "…and so is the record of which cells were dug out of the old cave")

	-- The two that must SURVIVE. Everything above is the price; these are the record.
	eq(p.totalCash, 120000, "lifetime cash survives a rebirth")
	eq(p.bestLayer, 25, "best depth survives a rebirth — it is the leaderboard")
	near(Prestige.multiplier(Config, p.rebirths), 1.8, "and the reward is live immediately")
end

do
	-- A refused rebirth must leave the profile completely untouched. A half-applied prestige
	-- (counter up, cash not wiped, or worse the other way round) is unrecoverable for a player.
	local p = newProfile()
	p.cash = 100
	p.runEarned = 100
	p.pickTier = 3
	p.backpackLevel = 2
	p.inventory = { [1] = 4 }
	p.depthLayer = 60
	p.openedBits = "keepme"
	local ok, reason = Prestige.apply(p, Config, Ore)
	eq(ok, false, "a rebirth you cannot afford is refused"); eq(reason, "poor", "poor reason")
	eq(p.rebirths, 0, "the counter did not move")
	eq(p.cash, 100, "the cash did not move")
	eq(p.runEarned, 100, "the earnings did not move")
	eq(p.pickTier, 3, "the pickaxe did not move")
	eq(p.backpackLevel, 2, "the backpack did not move")
	eq(p.inventory[1], 4, "the haul did not move")
	eq(p.depthLayer, 60, "the depth did not move")
	eq(p.openedBits, "keepme", "and the cave it is still standing in was not thrown away")

	local pm = newProfile()
	pm.rebirths = pc.MaxRebirths
	pm.runEarned = 1e12
	pm.pickTier = 5
	eq(Prestige.apply(pm, Config, Ore), false, "a maxed miner cannot rebirth again")
	eq(pm.rebirths, pc.MaxRebirths, "and nothing is reset for their trouble")
	eq(pm.pickTier, 5, "…including their pickaxe")
end

--============================================================================ THE CONTROL
-- The price now DEPENDS on the ore table on purpose — that is the whole design — so the old
-- control ("a balance pass on ore values must not move the requirement") is exactly backwards
-- and has been replaced by its opposite. What must still be independent is the CAVE: the seed and
-- the carving decide where the ore is, not how much of it there is, and pricing a rebirth off the
-- noise field would make the same rebirth cost different amounts on different WorldSeeds.

do
	local shadow = table.clone(Config)
	shadow.WorldSeed = 42
	shadow.Mine = table.clone(Config.Mine)
	shadow.Mine.AirThreshold = 0.05 -- a cave with almost no rock left in it
	shadow.Mine.NoiseScaleXZ = 11
	shadow.Mine.HardnessPerLayer = 0.5

	for r = 0, 12 do
		eq(Prestige.requirement(shadow, Ore, r), Prestige.requirement(Config, Ore, r),
			"CONTROL: requirement " .. r .. " unchanged by the seed, the carving and the hardness")
		eq(Prestige.multiplier(shadow, r), Prestige.multiplier(Config, r),
			"CONTROL: multiplier " .. r .. " unchanged")
	end

	-- …and it DOES move with the ore table, which is what makes it track the world.
	local richer = table.clone(Config)
	richer.Ores = table.clone(Config.Ores)
	richer.Ores.Value = { [0] = 0, 12, 40, 140, 480, 1600 } -- every ore worth double
	near(Prestige.requirement(richer, Ore, 3) / Prestige.requirement(Config, Ore, 3), 2,
		"a cave worth twice as much charges twice as much for the rebirth it pays for", 1e-6)
	local deeper = table.clone(Config)
	deeper.Mine = table.clone(Config.Mine)
	deeper.Mine.LayersPerRebirth = 24
	truthy(Prestige.requirement(deeper, Ore, 3) > Prestige.requirement(Config, Ore, 3),
		"…and a wall that moves twice as fast charges for the extra layers")
end

--=========================================================== the ladder has to be CLIMBABLE
--                                                            …AND HAS TO STAY WORTH CLIMBING

-- THE REQUIREMENT IS CHARGED AGAINST A FINITE SHAFT, so somebody has to check the two against
-- each other — in BOTH directions, which is the half that was missing.
--
-- Too expensive is the obvious failure: if rebirth `r` costs more than everything the rebirth-`r`
-- cave contains, that rebirth is impossible and every rebirth past it is unreachable, the depth
-- wall never moves and the second half of the game is dead. The shipped numbers were like that at
-- all 25 levels.
--
-- Too CHEAP is a failure too, and it is the one that got shipped next: at 27x, a rebirth is
-- bought having touched 4% of the cave, so exploring it, the lamp, the backpack and the whole
-- cave-void payoff have no part in progression at all — the mine becomes scenery you walk past on
-- the way to a button. The band below is two-sided for exactly that reason.
do
	local Mine = require("../src/shared/Mine")
	local W = Config.Mine.GridW

	-- Everything the rebirth-`r` shaft would pay out if a player mined every last cell of it.
	local function shaftIncome(r: number): number
		local w = Mine.world(Config, r)
		local raw = 0
		for y = 1, w.maxLayer do
			for x = 2, W - 1 do
				for z = 2, W - 1 do
					local c = Mine.cell(Config, Ore, w, x, y, z)
					if c.kind == "rock" then raw += Ore.value(Config, c.ore) * Ore.yieldOf(Config, c.ore) end
				end
			end
		end
		return math.floor(raw * Prestige.multiplier(Config, r))
	end

	local worst, worstAt, best, bestAt = math.huge, -1, 0, -1
	for r = 0, pc.MaxRebirths - 1 do
		local income = shaftIncome(r)
		local need = Prestige.requirement(Config, Ore, r)
		local ratio = income / need
		if ratio < worst then worst, worstAt = ratio, r end
		if ratio > best then best, bestAt = ratio, r end
		truthy(ratio >= 2, "rebirth " .. r .. " is payable out of the shaft it is charged against"
			.. " (shaft holds $" .. income .. ", rebirth costs $" .. need
			.. ", " .. string.format("%.2f", ratio) .. "x)")
		truthy(ratio <= 5, "rebirth " .. r .. " still costs enough of its shaft to be worth digging"
			.. " (" .. string.format("%.2f", ratio) .. "x)")
	end
	print(string.format("  rebirth price across all %d levels: %.2fx the shaft (r%d) .. %.2fx (r%d)"
		.. " — spread %.2fx", pc.MaxRebirths, worst, worstAt, best, bestAt, best / worst))

	-- CONTROLS: the comparison must be able to fail in BOTH directions, or the loop is decoration.
	local tight = table.clone(Config)
	tight.Prestige = table.clone(Config.Prestige)
	tight.Prestige.PriceFraction = Config.Prestige.PriceFraction * 1000
	truthy(shaftIncome(0) / Prestige.requirement(tight, Ore, 0) < 2,
		"CONTROL: a requirement 1000x too large is caught by this comparison")
	local loose = table.clone(Config)
	loose.Prestige = table.clone(Config.Prestige)
	loose.Prestige.PriceFraction = Config.Prestige.PriceFraction / 10
	truthy(shaftIncome(0) / Prestige.requirement(loose, Ore, 0) > 5,
		"CONTROL: …and a requirement 10x too small is caught by the other side of it")
end

print(string.format("Prestige: %d passed, %d failed", passed, failed))
assert(failed == 0, "Prestige tests failed")
