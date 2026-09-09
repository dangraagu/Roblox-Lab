-- Pure tests for Upgrades (the safehouse tycoon side: costs, levels, aggregated effects).
-- Run from the game directory: luau tests/Upgrades.spec.luau
--
-- This is where the player's whole grind lands, so the expensive failures are economic:
-- an upgrade that can be bought without paying, one that can be bought past its cap, one whose
-- effect key is misspelled and therefore does nothing at all, and a stack that becomes so
-- strong the night can no longer be lost.
local Upgrades = require("../src/shared/Upgrades")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local U = Config.Upgrades

--============================================================================ catalog sanity

do
	local seen, dupe = {}, false
	for _, e in U.Catalog do
		if seen[e.id] then dupe = true end
		seen[e.id] = true
		truthy(e.max >= 1, e.id .. " can be bought at least once")
		truthy(e.baseCost > 0, e.id .. " costs something")
		truthy(e.costMul > 1, e.id .. " gets more expensive each level")
	end
	truthy(not dupe, "upgrade ids are unique")
	eq(Upgrades.byId(Config, "lockbox").name, "Lockbox", "byId finds an upgrade")
	eq(Upgrades.byId(Config, "not_an_upgrade"), nil, "byId on an unknown id -> nil")
end

-- THE TYPO TRAP. `per` keys are read by NAME in Upgrades.effects. A misspelled key would parse,
-- save, cost the player relics and do absolutely nothing, and nothing else in the game would
-- ever mention it. So every key in the catalog has to be one the aggregator actually knows.
do
	local unknown = {}
	for _, e in U.Catalog do
		for key in e.per do
			if not Upgrades.EFFECT_KEYS[key] then
				table.insert(unknown, e.id .. "." .. key)
			end
		end
	end
	eq(#unknown, 0, "every `per` key is an effect the aggregator reads (" .. table.concat(unknown, ", ") .. ")")
end

-- ...and the mirror of it: every effect the aggregator can produce is granted by SOMETHING.
-- A key nothing grants is dead weight the server still reads.
do
	local granted = {}
	for _, e in U.Catalog do
		for key in e.per do
			granted[key] = true
		end
	end
	local orphan = {}
	for key in Upgrades.EFFECT_KEYS do
		if not granted[key] then
			table.insert(orphan, key)
		end
	end
	eq(#orphan, 0, "every effect key is granted by at least one upgrade (" .. table.concat(orphan, ", ") .. ")")
end

--=================================================================================== costs

do
	local e = Upgrades.byId(Config, "lanterns")
	eq(Upgrades.cost(Config, "lanterns", 0), e.baseCost, "the first level costs baseCost")
	truthy(Upgrades.cost(Config, "lanterns", 1) > Upgrades.cost(Config, "lanterns", 0), "level 2 costs more")
	truthy(Upgrades.cost(Config, "lanterns", 3) > Upgrades.cost(Config, "lanterns", 2), "and it keeps rising")
	eq(Upgrades.cost(Config, "lanterns", 0), math.floor(Upgrades.cost(Config, "lanterns", 0)),
		"costs are whole relics — you cannot pay 40.7")
	eq(Upgrades.cost(Config, "lanterns", e.max), nil, "a maxed upgrade has no next cost")
	eq(Upgrades.cost(Config, "nope", 0), nil, "an unknown upgrade has no cost")
end

--============================================================================ levels + buying

do
	eq(Upgrades.level({}, "lanterns"), 0, "an unowned upgrade is level 0")
	eq(Upgrades.level({ lanterns = 3 }, "lanterns"), 3, "a stored level reads back")
	eq(Upgrades.level({ lanterns = 3 }, "wardstones"), 0, "...and does not leak to its neighbours")

	eq(Upgrades.hubLevel({}), 0, "an empty safehouse is hub level 0")
	eq(Upgrades.hubLevel({ lanterns = 2, lockbox = 1 }), 3, "hub level is the sum of every level")
end

do
	local levels = { lanterns = 0 }
	local cost = Upgrades.cost(Config, "lanterns", 0)

	truthy(Upgrades.canBuy(Config, levels, cost, "lanterns"), "exactly enough relics is enough")
	falsy(Upgrades.canBuy(Config, levels, cost - 1, "lanterns"), "one relic short is not")
	falsy(Upgrades.canBuy(Config, levels, 99999, "nope"), "an unknown upgrade can never be bought")

	local maxed = { lanterns = Upgrades.byId(Config, "lanterns").max }
	falsy(Upgrades.canBuy(Config, maxed, 99999, "lanterns"), "a maxed upgrade cannot be bought again")
	local _, reason = Upgrades.canBuy(Config, maxed, 99999, "lanterns")
	eq(reason, "maxed", "and it says WHY (a silent no-op is the bug this repo keeps shipping)")
	local _, poor = Upgrades.canBuy(Config, levels, 0, "lanterns")
	eq(poor, "poor", "being broke says so too")
end

do
	-- buy() must not mutate what it was given: the server writes the result into the profile
	-- only after the DataStore flush succeeds, and a mutated input would have already spent it.
	local levels = { lanterns = 1 }
	local cost = Upgrades.cost(Config, "lanterns", 1)
	local ok, newLevels, newStash = Upgrades.buy(Config, levels, cost + 25, "lanterns")
	truthy(ok, "a buy the player can afford succeeds")
	eq(newLevels.lanterns, 2, "the level went up by exactly one")
	eq(newStash, 25, "and the cost came out of the stash")
	eq(levels.lanterns, 1, "the ORIGINAL levels table is untouched")
	truthy(newLevels ~= levels, "buy returns a new table rather than the one it was handed")

	local bad, sameLevels, sameStash, why = Upgrades.buy(Config, levels, 0, "lanterns")
	falsy(bad, "a buy the player cannot afford fails")
	eq(sameLevels.lanterns, 1, "a failed buy changes no level")
	eq(sameStash, 0, "a failed buy spends nothing")
	eq(why, "poor", "a failed buy explains itself")
end

do
	-- Buy one upgrade all the way up and check the total spend is the sum of its own costs.
	local levels, stash = {}, 100000
	local e = Upgrades.byId(Config, "lockbox")
	local expected = 0
	for lv = 0, e.max - 1 do
		expected += Upgrades.cost(Config, "lockbox", lv)
	end
	for _ = 1, e.max do
		local ok, nl, ns = Upgrades.buy(Config, levels, stash, "lockbox")
		truthy(ok, "buying lockbox level up to max keeps working")
		levels, stash = nl, ns
	end
	eq(levels.lockbox, e.max, "the upgrade reaches its cap")
	eq(100000 - stash, expected, "the total spent equals the sum of the per-level costs")
	local over = Upgrades.buy(Config, levels, stash, "lockbox")
	falsy(over, "and it cannot be pushed past the cap even with relics to burn")
end

--================================================================================== effects

do
	local zero = Upgrades.effects(Config, {})
	for key in Upgrades.EFFECT_KEYS do
		eq(zero[key], 0, "an empty safehouse grants no " .. key)
	end

	local one = Upgrades.effects(Config, { lanterns = 1 })
	approx(one.lampRadius, Upgrades.byId(Config, "lanterns").per.lampRadius, 1e-9,
		"one level grants exactly one level's worth")
	local three = Upgrades.effects(Config, { lanterns = 3 })
	approx(three.lampRadius, one.lampRadius * 3, 1e-9, "effects are linear in level")

	-- Levels the player cannot legitimately have must not pay out: a corrupt or hand-edited
	-- save is exactly how "keep 400% of your loot" gets into a live game.
	local cheat = Upgrades.effects(Config, { lanterns = 9999 })
	local cap = Upgrades.byId(Config, "lanterns").max
	approx(cheat.lampRadius, one.lampRadius * cap, 1e-9, "a level above the cap is clamped to the cap")
	local negative = Upgrades.effects(Config, { lanterns = -5 })
	eq(negative.lampRadius, 0, "a negative level grants nothing rather than subtracting")
	local junk = Upgrades.effects(Config, { lanterns = "lots", not_an_upgrade = 3 })
	eq(junk.lampRadius, 0, "a non-numeric level is ignored")
end

do
	-- The ceilings. Without them a long enough grind ends the game: dread that never fills,
	-- a watcher that cannot move, a death that costs nothing.
	local everything = {}
	for _, e in U.Catalog do
		everything[e.id] = e.max
	end
	local eff = Upgrades.effects(Config, everything)
	truthy(eff.dreadSlow <= U.MaxDreadSlow + 1e-9, "dreadSlow is capped")
	truthy(eff.watcherSlow <= U.MaxWatcherSlow + 1e-9, "watcherSlow is capped")
	truthy(eff.keepOnCaught <= U.MaxKeepOnCaught + 1e-9, "keepOnCaught is capped")
	truthy(eff.keepOnCaught < 1, "you can NEVER keep everything when caught")
	truthy(eff.watcherSlow < 1, "the watcher can never be frozen solid")
	truthy(eff.relicValue > 0, "a fully built safehouse does actually pay more per relic")
end

do
	-- THE CEILINGS ARE NOT CURRENTLY BINDING, AND THAT IS THE POINT OF THIS BLOCK.
	-- With today's catalog the natural maxima (lockbox 3 * 0.2 = 0.60, wardstones 5 * 0.07 =
	-- 0.35, beartraps 5 * 0.05 = 0.25) sit at or below the config ceilings, so `effects` returns
	-- the same numbers whether the aggregate clamps are there or not — a verified mutation that
	-- deleted the keepOnCaught clamp entirely passed the whole suite.
	--
	-- The clamps exist for the retune that WILL happen (raise a `max`, add a second upgrade that
	-- grants the same key), and that is what is exercised here: push the caps up, and the ceiling
	-- still has to hold. Without this the safety net is untested code that only matters on the
	-- day somebody changes a number, which is the day nobody is looking.
	local raised = {}
	local saved = {}
	for _, e in U.Catalog do
		saved[e.id] = e.max
		e.max = e.max * 20
		raised[e.id] = e.max
	end
	local eff = Upgrades.effects(Config, raised)
	for _, e in U.Catalog do
		e.max = saved[e.id]
	end

	approx(eff.keepOnCaught, U.MaxKeepOnCaught, 1e-9, "keepOnCaught is held at its ceiling by a retune")
	approx(eff.dreadSlow, U.MaxDreadSlow, 1e-9, "dreadSlow is held at its ceiling by a retune")
	approx(eff.watcherSlow, U.MaxWatcherSlow, 1e-9, "watcherSlow is held at its ceiling by a retune")
	truthy(eff.keepOnCaught < 1, "no retune can make a death free")
	truthy(eff.watcherSlow < 1, "no retune can freeze the Nightwatcher")
	truthy(eff.dreadSlow < 1, "no retune can stop the manor waking up")
	-- The unbounded effects are unbounded ON PURPOSE (more light, more warning, more time, more
	-- value are all fine at any size), so they must NOT have been clamped to anything here.
	truthy(eff.lampRadius > Upgrades.byId(Config, "lanterns").per.lampRadius * 5,
		"the uncapped effects really are uncapped")
end

--============================================================================== sanitize

do
	-- What comes back out of a DataStore. JSON turns sparse integer keys into strings and a
	-- hand-edited save can hold anything at all.
	local clean = Upgrades.sanitize(Config, { lanterns = 2, lockbox = 99, ghost_upgrade = 4, lanterns_typo = 1 })
	eq(clean.lanterns, 2, "a valid level survives the round trip")
	eq(clean.lockbox, Upgrades.byId(Config, "lockbox").max, "an impossible level is clamped, not trusted")
	eq(clean.ghost_upgrade, nil, "an upgrade that does not exist is dropped")
	eq(clean.lanterns_typo, nil, "and so is a near-miss id")
	eq(Upgrades.sanitize(Config, nil).lanterns, nil, "a missing save sanitizes to an empty safehouse")
	eq(Upgrades.sanitize(Config, "not a table").lanterns, nil, "so does a corrupt one")
	local neg = Upgrades.sanitize(Config, { lanterns = -3, wardstones = 2.7 })
	eq(neg.lanterns, nil, "a negative level is dropped rather than stored")
	eq(neg.wardstones, 2, "a fractional level is floored to something buyable")
end

--============================================================================== CONTROL
-- A change the suite must NOT notice: `blurb` is shop copy. If rewording a description turns
-- this red, the suite is pinned to marketing text and no one will dare edit it.
do
	local e = Upgrades.byId(Config, "wardstones")
	local before = e.blurb
	e.blurb = "Old stones. They remember."
	local eff = Upgrades.effects(Config, { wardstones = 2 })
	local ok = Upgrades.cost(Config, "wardstones", 0) == e.baseCost
		and eff.dreadSlow > 0
		and Upgrades.canBuy(Config, {}, e.baseCost, "wardstones")
	e.blurb = before
	truthy(ok, "CONTROL: rewriting an upgrade's blurb changes nothing mechanical")
end

print(string.format("Upgrades: %d passed, %d failed", passed, failed))
if failed > 0 then error("Upgrades tests failed") end
