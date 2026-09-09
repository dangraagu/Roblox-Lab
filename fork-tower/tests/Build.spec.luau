-- Build.spec.luau — the summit card.
-- Run: luau tests/Build.spec.luau
--
-- The Build Reveal is the whole reason a run ends rather than just stopping: a title and a
-- rarity generated purely from the choices you made, saved and shown off. So the properties that
-- matter are that it is a pure function of the pick list, that a better run never produces a
-- worse card, and — the one that is easy to ship broken — that every rarity tier in Config is
-- actually REACHABLE by a real ten-floor run. A "Legendary" nobody can earn is a lie printed on
-- a card, and no unit test that feeds the module hand-written pick lists would ever notice: the
-- picks a player can actually make come from Fork, two at a time, never twice the same theme.
-- So this file asks Fork for real runs and plays them.

local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Fork = require("../src/shared/Fork")
local Build = require("../src/shared/Build")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local power = {}
local themeOf = {}
for _, t in ipairs(Config.Traits) do
	power[t.id] = t.power
	themeOf[t.id] = t.theme
end

--============================================================================ purity

do
	local picks = { "emberboots", "voidstep", "midastouch" }
	local a = Build.reveal(Config, picks)
	local b = Build.reveal(Config, picks)
	eq(a.title, b.title, "the same picks produce the same title")
	eq(a.score, b.score, "...the same score")
	eq(a.rarityName, b.rarityName, "...and the same rarity")
	eq(#picks, 3, "reveal does not mutate the pick list it was handed")
	eq(picks[1], "emberboots", "...at all")

	-- The card holds copies, not references into Config. A HUD that sorted `card.traits` in place
	-- would otherwise reorder Config.Traits for the whole server.
	--
	-- The expected label is READ from Config rather than written out here. The first version
	-- spelled the string in the assertion, and a mutation sweep's control — "rename every trait"
	-- — turned this file red for a pure cosmetic edit. A suite that reports a renamed label as a
	-- scoring defect sends the next person hunting a bug that is not there.
	local originalLabel = Config.Traits[1].label
	a.traits[1].label = "vandalised"
	eq(Config.Traits[1].label, originalLabel, "the card carries copies of the traits, not Config's own rows")
end

do
	local empty = Build.reveal(Config, {})
	eq(empty.title, Config.Build.EmptyTitle, "an empty run still produces a card")
	eq(empty.score, 0, "...worth nothing")
	eq(empty.rarityIndex, 1, "...at the lowest rarity")
	eq(#empty.traits, 0, "...with no traits on it")

	local junk = Build.reveal(Config, { "emberboots", "not_a_trait", "voidstep" })
	eq(#junk.traits, 2, "an unknown id is skipped rather than crashing")
	eq(junk.unknown, 1, "...and counted, so a bad save file is visible instead of silent")
	eq(junk.score, power.emberboots + power.voidstep, "...and contributes nothing to the score")
end

--============================================================================ scoring

do
	local plain = Build.reveal(Config, { "emberboots", "frostgrapple", "windstep" })
	eq(plain.score, power.emberboots + power.frostgrapple + power.windstep,
		"with no synergy the score is just the sum of the traits' power")
	eq(plain.synergies, 0, "...and no synergy is claimed")

	-- The synergy threshold has to fire AT SynergyMin and not one short of it. An off-by-one here
	-- is invisible in play and changes every card in the game.
	local short = {}
	for _ = 1, Config.Build.SynergyMin - 1 do table.insert(short, "voidstep") end
	local exact = {}
	for _ = 1, Config.Build.SynergyMin do table.insert(exact, "voidstep") end
	eq(Build.reveal(Config, short).synergies, 0,
		"one short of SynergyMin is not a synergy")
	eq(Build.reveal(Config, exact).synergies, 1,
		"exactly SynergyMin of a theme is")
	eq(Build.reveal(Config, exact).score,
		Config.Build.SynergyMin * power.voidstep + Config.Build.SynergyBonus,
		"...and it is worth exactly SynergyBonus")
end

do
	-- Monotonicity. Swapping any pick for a strictly stronger one of the SAME theme must never
	-- lower the score, and adding a pick must never lower it either. A player who climbs further
	-- and picks better must never be handed a worse card.
	local drops = 0
	local base = { "emberboots", "glacierskin", "windstep", "bananacurse" }
	local better = { "cindercrown", "frostgrapple", "blurcloak", "jestermark" }
	for i = 1, #base do
		local mixed = table.clone(base)
		mixed[i] = better[i]
		if Build.reveal(Config, mixed).score < Build.reveal(Config, base).score then drops += 1 end
	end
	eq(drops, 0, "upgrading any single pick never lowers the score")

	local grown = table.clone(base)
	table.insert(grown, "midastouch")
	truthy(Build.reveal(Config, grown).score >= Build.reveal(Config, base).score,
		"climbing one more floor never lowers the score")

	-- Rarity has to follow score, not be assigned some other way.
	local badTier = 0
	for s = 0, 60 do
		local idx = Build.rarityFor(Config, s)
		local prev = Build.rarityFor(Config, s - 1)
		if idx < prev then badTier += 1 end
	end
	eq(badTier, 0, "rarity never goes down as score goes up")
	eq(Build.rarityFor(Config, -5), 1, "a negative score still lands in the lowest tier")
end

--============================================================================ titles

do
	-- The title must name the run, not a random trait: the adjective comes from the theme the
	-- player leaned into and the noun from their strongest pick.
	local card = Build.reveal(Config, { "voidstep", "nullsigil", "voidstep", "emberboots" })
	eq(card.dominantTheme, "void", "the dominant theme is the one picked most")
	truthy(string.find(card.title, Config.Build.Adjectives.void, 1, true) ~= nil,
		"the title carries the dominant theme's adjective")

	-- A tie on count is broken by which theme showed up FIRST, so the card is stable rather than
	-- depending on table order.
	local tie = Build.reveal(Config, { "emberboots", "voidstep" })
	eq(tie.dominantTheme, "fire", "a tie on count goes to the theme that appeared first")
	local tieOther = Build.reveal(Config, { "voidstep", "emberboots" })
	eq(tieOther.dominantTheme, "void", "...which really does depend on the order picked")

	local noTitleGap = 0
	for _, t in ipairs(Config.Traits) do
		if Config.Build.Adjectives[t.theme] == nil or Config.Build.Nouns[t.theme] == nil then
			noTitleGap += 1
		end
	end
	eq(noTitleGap, 0, "every trait's theme has an adjective and a noun to build a title from")
end

--============================================================================ every tier is earnable

do
	-- Played, not invented. Each seed's fork plan is walked three ways — always take the stronger
	-- trait, always the weaker, always the left door — and the cards those runs produce are what
	-- the rarity ladder is measured against. If a tier never appears here, no player can ever get
	-- it however they play.
	local seenTier = {}
	local best, worst = -1, 1e9
	for s = 1, 400 do
		local plan = Fork.plan(Config, s, Rng)
		local strong, weak, left = {}, {}, {}
		for _, floor in ipairs(plan.floors) do
			local a, b = floor.doors[1], floor.doors[2]
			local hi = if power[a.traitId] >= power[b.traitId] then a else b
			local lo = if hi == a then b else a
			table.insert(strong, hi.traitId)
			table.insert(weak, lo.traitId)
			table.insert(left, a.traitId)
		end
		for _, picks in ipairs({ strong, weak, left }) do
			local card = Build.reveal(Config, picks)
			seenTier[card.rarityName] = (seenTier[card.rarityName] or 0) + 1
			if card.score > best then best = card.score end
			if card.score < worst then worst = card.score end
		end
	end

	local missing = {}
	for _, r in ipairs(Config.Build.Rarities) do
		if (seenTier[r.name] or 0) == 0 then missing[#missing + 1] = r.name end
	end
	eq(#missing, 0, string.format(
		"every rarity tier is earnable by a real ten-floor run (scores %d..%d; missing: %s)",
		worst, best, table.concat(missing, ", ")))

	-- ...and the top tier must not be the DEFAULT either. A ladder everybody clears is not a
	-- ladder; a greedy run should reach it and a careless one should not.
	local topName = Config.Build.Rarities[#Config.Build.Rarities].name
	local topShare = (seenTier[topName] or 0) / (400 * 3)
	truthy(topShare > 0.02 and topShare < 0.6,
		string.format("the top tier is earned by some runs and not most (%.1f%% of them)", topShare * 100))
end

--============================================================================ CONTROL

do
	-- The change the suite must not notice: a trait's colour is a swatch on a card. Repaint every
	-- one of them and not a single score, tier or title may move. Without this, any palette tweak
	-- would read as a scoring regression to the next person who ran the tests.
	local repainted = {}
	for k, v in pairs(Config) do repainted[k] = v end
	local traits = {}
	for i, t in ipairs(Config.Traits) do
		local copy = {}
		for k, v in pairs(t) do copy[k] = v end
		copy.color = { (i * 37) % 256, (i * 91) % 256, (i * 13) % 256 }
		traits[i] = copy
	end
	repainted.Traits = traits

	local drift = 0
	for s = 1, 200 do
		local plan = Fork.plan(Config, s, Rng)
		local picks = {}
		for _, floor in ipairs(plan.floors) do
			table.insert(picks, floor.doors[1].traitId)
		end
		local a = Build.reveal(Config, picks)
		local b = Build.reveal(repainted, picks)
		if a.title ~= b.title or a.score ~= b.score or a.rarityName ~= b.rarityName
			or a.dominantTheme ~= b.dominantTheme or a.synergies ~= b.synergies then
			drift += 1
		end
	end
	eq(drift, 0, "CONTROL: repainting every trait changes no score, tier or title")

	-- ...and the repaint really did reach the module.
	local one = Build.reveal(repainted, { "emberboots" })
	truthy(one.traits[1].color[1] ~= Config.Traits[1].color[1],
		"CONTROL: the repainted config genuinely reaches the card (the control is not a no-op)")
end

--============================================================================ done

print(string.format("Build: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Build.spec failed", 0)
end
