-- Pure tests for Economy. Run from the game directory: luau tests/Economy.spec.luau
--
-- Every expected number here is written out by hand from DESIGN.md section 4/5/6/8, never
-- recomputed from Config: a price checked against the formula that produced it is not a check.
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

--============================================================================ species + prices

local PRICES = {
	jackalope = 30, hodag = 60, chupacabra = 90,
	dogman = 3600, jerseydevil = 5400,
	mothman = 168000, nessie = 240000,
	-- 2026-10-01: the Mythic payback is 3 600 s (was DESIGN.md's 14 400), so the first Mythic lands in 30-45 minutes
	-- of normal play (tests/Pacing.spec.luau measures it; CLAUDE.md Deviations)
	bigfoot = 1620000,
}
local TIER = { jackalope = 1, hodag = 1, chupacabra = 1, dogman = 2, jerseydevil = 2, mothman = 3, nessie = 3, bigfoot = 4 }
local count = 0
for id, price in PRICES do
	count += 1
	eq(Economy.price(Config, id), price, "price of " .. id)
	eq(Economy.tierOf(Config, id), TIER[id], "tier of " .. id)
	truthy(Economy.species(Config, id) ~= nil, "species record exists for " .. id)
end
eq(count, 8, "eight species")
eq(#Config.Species, 8, "Config lists exactly eight species")
eq(Economy.species(Config, "skinwalker"), nil, "no Skinwalker (DESIGN.md section 2)")
eq(Economy.price(Config, "nope"), nil, "an unknown species has no price")

-- the best of a tier always earns less than the worst of the next
for tier = 1, 3 do
	local maxHere, minNext = -math.huge, math.huge
	for _, s in Config.Species do
		if s.tier == tier and s.rate > maxHere then maxHere = s.rate end
		if s.tier == tier + 1 and s.rate < minNext then minNext = s.rate end
	end
	truthy(maxHere < minNext, string.format("tier %d best rate %d < tier %d worst rate %d", tier, maxHere, tier + 1, minNext))
end

eq(#Economy.speciesOfTier(Config, 1), 3, "three Commons")
eq(#Economy.speciesOfTier(Config, 2), 2, "two Rares")
eq(#Economy.speciesOfTier(Config, 3), 2, "two Legendaries")
eq(#Economy.speciesOfTier(Config, 4), 1, "one Mythic")
eq(Economy.speciesOfTier(Config, 1)[1], "jackalope", "tier lists keep Config order")

--============================================================================ jars

eq(Economy.jarCap(Config, "jackalope"), 28800, "a Jackalope jar holds 8 h at 1/s")
eq(Economy.jarCap(Config, "bigfoot"), 450 * 8 * 3600, "a Bigfoot jar holds 8 h at 450/s")

eq(Economy.accrue(Config, "hodag", 10, 100), 210, "accrue: 10 + 2/s * 100 s")
eq(Economy.accrue(Config, "hodag", 57590, 100), 57600, "accrue stops at the cap")
eq(Economy.accrue(Config, "hodag", 10, -50), 10, "accrue never goes backwards")
eq(Economy.accrue(Config, "", 10, 100), 0, "an empty cage accrues nothing and holds nothing")

-- offline: jar = min(cap, jar + rate * clamp(now - savedAt, 0, 8 h))
local NOW = 1789000000
eq(Economy.offlineJar(Config, "hodag", 12.5, NOW - 100, NOW), 212.5, "offline: 100 s at 2/s")
eq(Economy.offlineJar(Config, "hodag", 12.5, NOW + 5000, NOW), 12.5, "offline: a savedAt in the FUTURE adds nothing")
eq(Economy.offlineJar(Config, "hodag", 0, NOW - 10 * 86400, NOW), 57600, "offline: ten days mints one jar, no more")
eq(Economy.offlineJar(Config, "hodag", 57000, NOW - 8 * 3600, NOW), 57600, "offline: a nearly full jar tops out at the cap")
eq(Economy.offlineJar(Config, "jackalope", 5, "garbage", NOW), 5, "offline: a non-number savedAt adds nothing")
eq(Economy.offlineJar(Config, "jackalope", 5, nil, NOW), 5, "offline: a missing savedAt adds nothing")

--============================================================================ selling, cages, heat, permits

for id, price in PRICES do
	truthy(Economy.sellValue(Config, id) < price, "releasing " .. id .. " never profits")
	eq(Economy.sellValue(Config, id), math.floor(price / 2), "release returns half of " .. id)
end

eq(Economy.expansionPrice(Config, 3), 150, "cage 4 costs 150")
eq(Economy.expansionPrice(Config, 4), 1500, "cage 5 costs 1 500")
eq(Economy.expansionPrice(Config, 5), 15000, "cage 6 costs 15 000")
eq(Economy.expansionPrice(Config, 6), 150000, "cage 7 costs 150 000")
eq(Economy.expansionPrice(Config, 7), 1500000, "cage 8 costs 1 500 000")
eq(Economy.expansionPrice(Config, 8), 6000000, "cage 9 costs 6 000 000")
eq(Economy.expansionPrice(Config, 9), nil, "nothing past nine cages")

eq(Economy.heatSeconds(Config, 1), 30, "tier 1 heat")
eq(Economy.heatSeconds(Config, 2), 300, "tier 2 heat")
eq(Economy.heatSeconds(Config, 3), 2400, "tier 3 heat")
eq(Economy.heatSeconds(Config, 4), 3600, "tier 4 heat (one hour)")

eq(Economy.permit(Config, 1), 0, "tier 1 permit is free")
eq(Economy.permit(Config, 2), 360, "tier 2 permit 360")
eq(Economy.permit(Config, 3), 16800, "tier 3 permit 16 800")
eq(Economy.permit(Config, 4), 162000, "tier 4 permit 162 000")

-- the anti-farm bound: stealing then releasing earns less than half the species' own rate,
-- even with a 1-second raid (far below any camp's measured optimum)
for id in PRICES do
	local s = Economy.species(Config, id)
	local perSecond = (Economy.sellValue(Config, id) - Economy.permit(Config, s.tier))
		/ (Economy.heatSeconds(Config, s.tier) + 1)
	truthy(perSecond < s.rate / 2, string.format("steal-then-release %s earns %.2f/s < %.1f/s", id, perSecond, s.rate / 2))
	-- and a steal kept is worth at most the rate itself per second of heat
	truthy(Economy.price(Config, id) / (Economy.heatSeconds(Config, s.tier) + 1) < s.rate,
		"a kept steal of " .. id .. " is worth less than its own rate per second of heat")
end

--============================================================================ journal: rank + unlocks

eq(Economy.rank(Config, {}), 0, "rank 0 before the first cryptid")
eq(Economy.rank(Config, { "jackalope" }), 1, "rank 1 with a Common")
eq(Economy.rank(Config, { "hodag", "mothman" }), 3, "rank is the highest tier ever owned")
eq(Economy.rank(Config, { "nope", "dogman" }), 2, "unknown ids are ignored")

truthy(Economy.campUnlocked(Config, 1, {}), "camp 1 is always open")
truthy(not Economy.campUnlocked(Config, 2, {}), "camp 2 locked with an empty journal")
truthy(Economy.campUnlocked(Config, 2, { "jackalope" }), "camp 2 opens with a Common")
truthy(not Economy.campUnlocked(Config, 3, { "jackalope" }), "camp 3 needs a Rare, not a Common")
truthy(Economy.campUnlocked(Config, 3, { "jackalope", "jerseydevil" }), "camp 3 opens with a Rare")
truthy(Economy.campUnlocked(Config, 4, { "nessie" }), "camp 4 opens with a Legendary")
truthy(not Economy.campUnlocked(Config, 5, { "bigfoot" }), "there is no camp 5")
truthy(not Economy.campUnlocked(Config, 0, { "bigfoot" }), "there is no camp 0")

--============================================================================ poachers

eq(Economy.bounty(Config, 0), 10, "bounty minimum 10 on an empty lair")
eq(Economy.bounty(Config, 1), 30, "bounty = 30 s of a 1/s lair")
eq(Economy.bounty(Config, 0.2), 10, "bounty minimum wins below 1/3 per second")
eq(Economy.bounty(Config, 100), 3000, "bounty = 30 s of a 100/s lair")
eq(Economy.theft(Config, 300), 150, "theft takes half a jar")
eq(Economy.theft(Config, 0), 0, "an empty jar loses nothing")

--============================================================================ the profile

do
	local p = Economy.defaultProfile(Config)
	eq(p.v, 1, "default profile version 1")
	eq(p.essence, 30, "start with exactly one Jackalope's worth")
	eq(p.cagesUnlocked, 3, "three cages to start")
	eq(#p.cages, 9, "cages is ALWAYS nine dense entries")
	for i = 1, 9 do
		eq(p.cages[i].sp, "", "default cage " .. i .. " is empty")
		eq(p.cages[i].jar, 0, "default cage " .. i .. " jar is 0")
	end
	eq(#p.traps, 0, "no traps")
	eq(#p.journal, 0, "empty journal")
	eq(p.tutorial, 0, "tutorial step 0")
	eq(p.heat.t1, 0, "no heat t1")
	eq(p.heat.t4, 0, "no heat t4")
	eq(p.stats.steals, 0, "no steals")
	eq(p.stats.caught, 0, "not caught")
	eq(p.stats.poachersCaught, 0, "no poachers caught")
	for k in p do
		truthy(type(k) == "string", "top-level profile key is a string: " .. tostring(k))
	end
	for k in p.heat do
		truthy(type(k) == "string", "heat key is a string (no integer keys to lose in JSON): " .. tostring(k))
	end
end

do
	-- a saved profile, shaped like JSON gave it back
	local raw = {
		v = 1, essence = 812.5, savedAt = NOW - 100, cagesUnlocked = 4,
		cages = {
			{ sp = "", jar = 0 }, { sp = "", jar = 0 }, { sp = "", jar = 0 }, { sp = "hodag", jar = 20 },
			{ sp = "jackalope", jar = 28790 }, { sp = "", jar = 0 }, { sp = "", jar = 0 }, { sp = "", jar = 0 },
			{ sp = "", jar = 0 },
		},
		traps = { "L:4:3", "S:2:3", 7, "junk" },
		heat = { t1 = NOW + 20, t2 = "x" },
		journal = { "jackalope", "hodag", "hodag", "skinwalker" },
		tutorial = 3,
		stats = { steals = 2, caught = 1 },
	}
	local p = Economy.normalizeProfile(Config, raw, NOW)
	eq(p.essence, 812.5, "essence survives")
	eq(p.cagesUnlocked, 4, "unlocked cages survive")
	eq(p.cages[4].sp, "hodag", "the Hodag is still in cage 4")
	eq(p.cages[4].jar, 220, "...and its jar grew 100 s at 2/s while offline")
	eq(p.cages[5].jar, 28800, "...and the Jackalope's jar stopped at its cap")
	eq(#p.traps, 2, "only well-formed trap strings survive")
	eq(p.traps[1], "L:4:3", "trap strings keep their order")
	eq(p.heat.t1, NOW + 20, "heat t1 survives")
	eq(p.heat.t2, 0, "a garbage heat value becomes 0")
	eq(#p.journal, 2, "journal is deduplicated and unknown species dropped")
	eq(p.tutorial, 3, "tutorial step survives")
	eq(p.stats.steals, 2, "stats survive")
	eq(p.stats.poachersCaught, 0, "a missing stat defaults to 0")

	local wild = Economy.normalizeProfile(Config, {
		essence = -5, cagesUnlocked = 40, cages = { { sp = "bigfoot", jar = -9 } }, tutorial = 99,
	}, NOW)
	eq(wild.essence, 0, "negative essence clamps to 0")
	eq(wild.cagesUnlocked, 9, "unlocked cages clamp to 9")
	eq(#wild.cages, 9, "a short cage list is padded to nine")
	eq(wild.cages[1].sp, "bigfoot", "a real species in cage 1 survives")
	eq(wild.cages[1].jar, 0, "a negative jar clamps to 0 (no savedAt: no offline growth)")
	eq(wild.tutorial, 4, "tutorial clamps to 4")

	local fromNil = Economy.normalizeProfile(Config, nil, NOW)
	eq(fromNil.essence, 30, "no saved data is a brand new profile")
	eq(#fromNil.cages, 9, "...with nine cages")
	-- a cage past the unlocked count cannot hold anything
	local locked = Economy.normalizeProfile(Config, {
		cagesUnlocked = 3,
		cages = { { sp = "hodag", jar = 0 }, { sp = "", jar = 0 }, { sp = "", jar = 0 }, { sp = "", jar = 0 },
			{ sp = "", jar = 0 }, { sp = "", jar = 0 }, { sp = "", jar = 0 }, { sp = "", jar = 0 }, { sp = "", jar = 0 } },
	}, NOW)
	-- cage 1 is column 1, the EIGHTH in centre-out order: locked while only three are unlocked
	eq(locked.cages[1].sp, "", "a cryptid saved in a locked cage is not kept there")
	eq(locked.essence, 30 + 30, "...it is released for half its price instead of vanishing")
end

--============================================================================ the best lair (the Top Lairs board's metric)
-- docs/complete-game-standard.md section 3: rank on a server-measured metric, ties to whoever reached it FIRST. The
-- metric is the best lair income the player has ever had (Essence/s), measured from the server's own profile.

do
	local p = Economy.defaultProfile(Config)
	eq(p.bestRate, 0, "a new profile's best lair income is 0")
	eq(p.bestRateAt, 0, "...reached at no time")
	p.cages[5] = { sp = "hodag", jar = 0 }
	eq(Economy.noteBest(Config, p, 1790000000), true, "a lair earning 2/s beats a best of 0")
	eq(p.bestRate, 2, "the best is now 2")
	eq(p.bestRateAt, 1790000000, "stamped when it was reached")
	eq(Economy.noteBest(Config, p, 1790000100), false, "the same income later is not a new best")
	eq(p.bestRateAt, 1790000000, "...and the first stamp stands (a tie goes to whoever was first)")
	p.cages[5] = { sp = "jackalope", jar = 0 }
	eq(Economy.noteBest(Config, p, 1790000200), false, "a lower income (a cryptid released) is not a new best")
	eq(p.bestRate, 2, "...and never lowers it")
	p.cages[4] = { sp = "bigfoot", jar = 0 }
	eq(Economy.noteBest(Config, p, 1790000300), true, "a Bigfoot moving in is a new best")
	eq(p.bestRate, 451, "1 + 450")
	eq(p.bestRateAt, 1790000300, "stamped at the Bigfoot")
end

do
	local function cagesWith(fill)
		local out = {}
		for i = 1, 9 do out[i] = { sp = "", jar = 0 } end
		for col, sp in fill do out[col] = { sp = sp, jar = 0 } end
		return out
	end
	local saved = Economy.normalizeProfile(Config, { cagesUnlocked = 3, cages = cagesWith({ [5] = "hodag" }),
		bestRate = 30, bestRateAt = 1780000000 }, NOW)
	eq(saved.bestRate, 30, "a saved best survives, even above the income the lair loads with (it released some)")
	eq(saved.bestRateAt, 1780000000, "...with its own stamp")
	local legacy = Economy.normalizeProfile(Config, { cagesUnlocked = 3, cages = cagesWith({ [5] = "hodag", [4] = "dogman" }) }, NOW)
	eq(legacy.bestRate, 14, "a profile saved before the board existed: the best is the income it loads with")
	eq(legacy.bestRateAt, NOW, "...stamped at this load (it ranks behind everyone who reached it earlier)")
	local behind = Economy.normalizeProfile(Config, { cagesUnlocked = 3, cages = cagesWith({ [5] = "dogman" }),
		bestRate = 3, bestRateAt = 1780000000 }, NOW)
	eq(behind.bestRate, 12, "a saved best below the loaded lair's income is raised to it")
	eq(behind.bestRateAt, NOW, "...and stamped now, not with the old stamp")
	local junk = Economy.normalizeProfile(Config, { cagesUnlocked = 3, cages = cagesWith({}), bestRate = "lots", bestRateAt = {} }, NOW)
	eq(junk.bestRate, 0, "a garbage best is 0")
	eq(junk.bestRateAt, 0, "...with no stamp")
	local frac = Economy.normalizeProfile(Config, { cagesUnlocked = 3, cages = cagesWith({}), bestRate = 12.7, bestRateAt = 1780000000.9 }, NOW)
	eq(frac.bestRate, 12, "a fractional best is floored")
	eq(frac.bestRateAt, 1780000000, "...and so is its stamp")
	local noStamp = Economy.normalizeProfile(Config, { cagesUnlocked = 3, cages = cagesWith({}), bestRate = 12 }, NOW)
	eq(noStamp.bestRateAt, NOW, "a best with no stamp is stamped at this load")
	local huge = Economy.normalizeProfile(Config, { cagesUnlocked = 3, cages = cagesWith({}), bestRate = 1e12, bestRateAt = 1780000000 }, NOW)
	eq(huge.bestRate, 9 * 450, "a best above any reachable lair (nine Bigfoots, 4 050/s) is capped there")
end

--============================================================================ cages in play

do
	local p = Economy.defaultProfile(Config)
	eq(Economy.firstEmptyCage(Config, p), 5, "the first cage is the centre column")
	p.cages[5].sp = "jackalope"
	eq(Economy.firstEmptyCage(Config, p), 4, "then column 4")
	p.cages[4].sp = "hodag"
	eq(Economy.firstEmptyCage(Config, p), 6, "then column 6")
	p.cages[6].sp = "hodag"
	eq(Economy.firstEmptyCage(Config, p), nil, "three unlocked cages full")
	p.cagesUnlocked = 4
	eq(Economy.firstEmptyCage(Config, p), 3, "the fourth cage is column 3")
	truthy(Economy.isUnlockedCage(Config, p, 3), "column 3 unlocked at four cages")
	truthy(not Economy.isUnlockedCage(Config, p, 7), "column 7 still locked at four cages")
	eq(Economy.cryptidCount(Config, p), 3, "three cryptids owned")
	eq(Economy.lairRate(Config, p), 5, "lair rate 1 + 2 + 2")

	p.cages[5].jar = 7.5
	p.cages[4].jar = 20
	eq(Economy.collect(Config, p), 27.5, "collect sums every jar")
	eq(p.cages[5].jar, 0, "...and empties them")
	eq(p.cages[4].jar, 0, "...all of them")

	p.cages[4].jar = 100
	p.cages[6].jar = 300
	eq(Economy.fullestCage(Config, p), 6, "fullest jar is column 6")
end

print(string.format("Economy: %d passed, %d failed", passed, failed))
if failed > 0 then error("Economy tests failed") end
