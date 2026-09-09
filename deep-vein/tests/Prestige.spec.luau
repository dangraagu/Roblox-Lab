-- Rene tester for Prestige. Kjør: luau tests/Prestige.spec.luau
--
-- Rebirth is the only irreversible button in the game, so the two things that matter most here
-- are (a) it refuses cleanly rather than half-applying, and (b) it does NOT wipe the two figures
-- the leaderboard is built on. A rebirth that resets your best depth would delete a player's
-- entire ranking as a reward for progressing.

local Prestige = require("../src/shared/Prestige")
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
		cash = 0, totalCash = 0, inventory = {},
		pickTier = 1, backpackLevel = 0, lampLevel = 0,
		rebirths = 0, depthLayer = 0, bestLayer = 0,
	}
end

--============================================================================ the curves

eq(Prestige.requirement(Config, 0), 30000, "the first rebirth costs 30000")
eq(Prestige.requirement(Config, 1), math.floor(30000 * 3.2), "the second costs 3.2x that")
eq(Prestige.requirement(Config, 2), math.floor(30000 * 3.2 ^ 2), "…and so on")
for r = 0, 10 do
	truthy(Prestige.requirement(Config, r + 1) > Prestige.requirement(Config, r),
		"rebirth " .. (r + 1) .. " costs more than rebirth " .. r)
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
	near(Prestige.progress(p, Config), 0, "no cash is no progress")
	p.cash = 15000
	near(Prestige.progress(p, Config), 0.5, "half the requirement is half the bar")
	p.cash = 99999999
	near(Prestige.progress(p, Config), 1, "the bar is clamped at full")
	p.rebirths = pc.MaxRebirths
	near(Prestige.progress(p, Config), 1, "a maxed miner's bar is full, not a divide by zero")
end

--============================================================================ the gate

do
	local p = newProfile()
	local ok, reason = Prestige.canRebirth(p, Config)
	eq(ok, false, "you cannot rebirth broke"); eq(reason, "poor", "…and it says why")

	p.cash = 29999
	eq(Prestige.canRebirth(p, Config), false, "one short is still short")
	p.cash = 30000
	local ok2, r2 = Prestige.canRebirth(p, Config)
	eq(ok2, true, "exactly the requirement is enough"); eq(r2, "ok", "ok reason")

	p.rebirths = pc.MaxRebirths
	p.cash = 1e12
	local ok3, r3 = Prestige.canRebirth(p, Config)
	eq(ok3, false, "there is a ceiling"); eq(r3, "max", "max reason")
end

--============================================================================ applying it

do
	local p = newProfile()
	p.cash = 55000
	p.totalCash = 120000
	p.inventory = { [3] = 7 }
	p.pickTier = 4
	p.backpackLevel = 5
	p.lampLevel = 3
	p.depthLayer = 24
	p.bestLayer = 25

	local ok, reason = Prestige.apply(p, Config)
	eq(ok, true, "rebirth applies"); eq(reason, "ok", "ok reason")

	eq(p.rebirths, 1, "the rebirth counter went up")
	eq(p.cash, Config.Economy.StartCash, "cash is wiped")
	eq(next(p.inventory), nil, "the haul is wiped")
	eq(p.pickTier, 1, "the pickaxe goes back to rusty")
	eq(p.backpackLevel, 0, "the backpack goes back to base")
	eq(p.lampLevel, 0, "the lamp goes back to base")
	eq(p.depthLayer, 0, "this run's depth is wiped — the cave is new, the old depth means nothing")

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
	p.pickTier = 3
	p.backpackLevel = 2
	p.inventory = { [1] = 4 }
	p.depthLayer = 60
	local ok, reason = Prestige.apply(p, Config)
	eq(ok, false, "a rebirth you cannot afford is refused"); eq(reason, "poor", "poor reason")
	eq(p.rebirths, 0, "the counter did not move")
	eq(p.cash, 100, "the cash did not move")
	eq(p.pickTier, 3, "the pickaxe did not move")
	eq(p.backpackLevel, 2, "the backpack did not move")
	eq(p.inventory[1], 4, "the haul did not move")
	eq(p.depthLayer, 60, "the depth did not move")

	local pm = newProfile()
	pm.rebirths = pc.MaxRebirths
	pm.cash = 1e12
	pm.pickTier = 5
	eq(Prestige.apply(pm, Config), false, "a maxed miner cannot rebirth again")
	eq(pm.rebirths, pc.MaxRebirths, "and nothing is reset for their trouble")
	eq(pm.pickTier, 5, "…including their pickaxe")
end

--============================================================================ THE CONTROL
-- Rebirth is arithmetic on the Prestige block alone. Rewriting the cave and every ore price
-- must not move the requirement, the multiplier or the bar — otherwise a balance pass on ore
-- values would silently reprice the one irreversible decision in the game.

do
	local shadow = table.clone(Config)
	shadow.WorldSeed = 42
	shadow.Mine = table.clone(Config.Mine)
	shadow.Mine.BaseMaxLayer = 500
	shadow.Mine.AirThreshold = 0.05
	shadow.Ores = table.clone(Config.Ores)
	shadow.Ores.Value = { [0] = 0, 1, 1, 1, 1, 1 }
	shadow.Economy = table.clone(Config.Economy)
	shadow.Economy.StartCash = 0

	for r = 0, 12 do
		eq(Prestige.requirement(shadow, r), Prestige.requirement(Config, r),
			"CONTROL: requirement " .. r .. " unchanged by the cave and the ore prices")
		eq(Prestige.multiplier(shadow, r), Prestige.multiplier(Config, r),
			"CONTROL: multiplier " .. r .. " unchanged")
	end

	-- And the same comparison DOES notice a real change, so the loop above is not vacuous.
	local real = table.clone(Config)
	real.Prestige = table.clone(Config.Prestige)
	real.Prestige.RequirementGrowth = 2.0
	truthy(Prestige.requirement(real, 3) ~= Prestige.requirement(Config, 3),
		"the same comparison DOES notice a real change to the growth curve")
end

print(string.format("Prestige: %d passed, %d failed", passed, failed))
assert(failed == 0, "Prestige tests failed")
