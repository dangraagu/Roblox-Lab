-- Shift.spec — procedural generation of one shift. Run: luau tests/Shift.spec.luau
--
-- DESIGN.md §7.2 (generation order) and §7.3 (what is never generated). The statistical
-- tolerances are sized in §7.3 so correct code does not flake: 40,000 samples per tray position
-- put a 1% tolerance 5.4 standard deviations out on each of the 48 (position, bin) comparisons.
local Shift = require("../src/shared/Shift")
local Rules = require("../src/shared/Rules")
local Rng = require("../src/shared/Rng")
local Seed = require("../src/shared/Seed")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local S = Config.Shift
local function gen(seed, stage, career)
	return Shift.generate(Config, Rng, Rules, seed, stage, career)
end

--============================================================ stages

eq(Shift.stageFor(Config, 1), 1, "career shift 1 is stage 1")
eq(Shift.stageFor(Config, 2), 2, "career shift 2 is stage 2")
eq(Shift.stageFor(Config, 3), 3, "career shift 3 is stage 3")
eq(Shift.stageFor(Config, 250), 3, "every later shift is stage 3")

--============================================================ shape, determinism

do
	local a = gen(12345, 3, 7)
	local b = gen(12345, 3, 7)
	eq(#a.items, S.Items, "30 items")
	eq(#a.cart, S.Items - S.TraySlots, "22 in the cart")
	local trayCount = 0
	for slot = 1, S.TraySlots do
		if a.tray[slot] ~= nil then trayCount += 1 end
	end
	eq(trayCount, S.TraySlots, "8 on the tray")

	local same = a.memo == b.memo
	for i = 1, S.Items do
		local x, y = a.items[i], b.items[i]
		if x.archetype ~= y.archetype or x.variant ~= y.variant or x.bin ~= y.bin
			or x.tag.letter ~= y.tag.letter or x.tag.cond ~= y.tag.cond or x.tag.route ~= y.tag.route then
			same = false
		end
	end
	for slot = 1, 6 do
		if a.binSlots[slot] ~= b.binSlots[slot] then same = false end
	end
	truthy(same, "the same seed gives the same shift")

	local c = gen(12346, 3, 7)
	local differs = false
	for i = 1, S.Items do
		if a.items[i].archetype ~= c.items[i].archetype or a.items[i].bin ~= c.items[i].bin then differs = true end
	end
	truthy(differs, "a different seed gives a different shift")

	-- every tray slot and cart entry is a distinct item, and together they are all 30
	local seen, dupes = {}, 0
	for slot = 1, S.TraySlots do
		local n = a.tray[slot]
		if seen[n] then dupes += 1 end
		seen[n] = true
	end
	for _, n in a.cart do
		if seen[n] then dupes += 1 end
		seen[n] = true
	end
	local count = 0
	for _ in seen do count += 1 end
	eq(dupes, 0, "no item is in two places")
	eq(count, S.Items, "tray + cart hold every item")

	-- the six bins occupy the six arc slots exactly once
	local bins = {}
	for slot = 1, 6 do bins[a.binSlots[slot]] = (bins[a.binSlots[slot]] or 0) + 1 end
	local ok = true
	for _, bin in Config.Rules.Bins do
		if bins[bin] ~= 1 then ok = false end
		if a.binSlots[a.slotOfBin[bin]] ~= bin then ok = false end
	end
	truthy(ok, "binSlots is a permutation of the six bins, and slotOfBin inverts it")
end

--============================================================ the answer is the manual's answer

do
	local wrong, torn, tornWrongShape, extraKeys = 0, 0, 0, 0
	local ALLOWED = { n = true, archetype = true, id = true, name = true, own = true, variant = true,
		tag = true, torn = true, bin = true, tutorial = true }
	for s = 1, 400 do
		local stage = (s % 3) + 1
		local sh = gen(Seed.forShift(Config, 42, s, 7), stage, s + 1)
		for _, it in sh.items do
			if Rules.resolve(Config, it.tag, it.own, sh.rules) ~= it.bin then wrong += 1 end
			for k in it do
				if not ALLOWED[k] then extraKeys += 1 end
			end
			local present = 0
			for k in it.tag do
				if k == "letter" or k == "cond" or k == "route" then present += 1 else extraKeys += 1 end
			end
			if it.torn then
				torn += 1
				-- "A torn part is nil": the value is deleted, not hidden.
				if it.tag[it.torn] ~= nil or present ~= 2 then tornWrongShape += 1 end
			elseif present ~= 3 then
				tornWrongShape += 1
			end
		end
		if sh.rules.memo ~= sh.memo then wrong += 1 end
	end
	eq(wrong, 0, "every item's bin is Rules.resolve of its own tag under the shift's rules (which carry its memo)")
	truthy(torn > 0, "torn tags were generated (" .. torn .. ")")
	eq(tornWrongShape, 0, "a torn part is nil and exactly one part is missing")
	eq(extraKeys, 0, "no item carries a field outside the known set (no hidden torn value)")
end

--============================================================ stage gating

do
	local tornAt, memoAt = { 0, 0, 0 }, { 0, 0, 0 }
	local wrongStage = 0
	for s = 1, 300 do
		for stage = 1, 3 do
			local sh = gen(Seed.forShift(Config, 9, s, 11), stage, 5)
			if sh.memo then memoAt[stage] += 1 end
			for _, it in sh.items do
				if it.torn then tornAt[stage] += 1 end
			end
			if sh.stage ~= stage then wrongStage += 1 end
		end
	end
	eq(wrongStage, 0, "every shift reports the stage it was generated at")
	eq(tornAt[1], 0, "no torn tags at stage 1")
	truthy(tornAt[2] > 0, "torn tags appear at stage 2 (" .. tornAt[2] .. ")")
	truthy(tornAt[3] > 0, "torn tags continue at stage 3")
	eq(memoAt[1], 0, "no memo at stage 1")
	eq(memoAt[2], 0, "no memo at stage 2")
	eq(memoAt[3], 300, "a memo on every stage-3 shift")
	-- TornChance 0.25 over 9,000 stage-2 items: 2,250 expected, one sd ~41
	truthy(math.abs(tornAt[2] / 9000 - 0.25) < 0.02, string.format("torn share at stage 2 is ~25%% (%.1f%%)", tornAt[2] / 90))
end

--============================================================ tutorial

do
	local first = gen(Seed.forShift(Config, 1001, 0, 5), 1, 1)
	local teddy, phone = first.items[1], first.items[2]
	eq(teddy.id, "teddy", "career shift 1: item 1 is the Teddy Bear")
	eq(Rules.tagText(Config, teddy.tag), "T \u{B7} 2 \u{B7} GREEN", "... tagged T . 2 . GREEN")
	eq(teddy.bin, "TOYS", "... which goes to TOYS, matching its look")
	eq(phone.id, "phone", "item 2 is the Phone")
	eq(Rules.tagText(Config, phone.tag), "K \u{B7} 1 \u{B7} BLUE", "... tagged K . 1 . BLUE")
	eq(phone.bin, "KEYS", "... which goes to KEYS & WALLETS, contradicting its look")
	eq(teddy.torn, nil, "the teddy is not torn")
	eq(phone.torn, nil, "the phone is not torn")
	truthy(teddy.tutorial and phone.tutorial, "both are marked tutorial")
	eq(first.tray[6], 1, "the teddy sits in back-row slot 6 (x = -2)")
	eq(first.tray[7], 2, "the phone sits in back-row slot 7 (x = +2)")
	-- items 3-8 fill the other six slots in slot order
	local order = {}
	for _, slot in { 1, 2, 3, 4, 5, 8 } do table.insert(order, first.tray[slot]) end
	eq(table.concat(order, ","), "3,4,5,6,7,8", "items 3-8 fill slots 1-5 and 8 in slot order")
	eq(first.cart[1], 9, "the cart starts at item 9")

	local tutorialLater = 0
	for s = 1, 200 do
		local sh = gen(Seed.forShift(Config, 1001, s, 5), Shift.stageFor(Config, s + 1), s + 1)
		for _, it in sh.items do
			if it.tutorial then tutorialLater += 1 end
		end
		if sh.tray[1] ~= 1 then tutorialLater += 1 end
	end
	eq(tutorialLater, 0, "the tutorial never appears after career shift 1, and items 1-8 fill slots 1-8")
end

do
	-- REVIEW-1 pass 3, player-path finding 1. The tutorial says "Tap the Phone" and "Now the Phone. Read
	-- its TAG ...: K means KEYS & WALLETS". A random Phone on the same tray (32.0% of first shifts) or
	-- rolling in later was taken for it: a second -8 s and "T goes to TOYS", against what the hint just
	-- taught. On career shift 1 no other item is a Teddy Bear or a Phone, on the tray or in the cart.
	local tutorialIds = {}
	for _, t in S.Tutorial do tutorialIds[t.archetype] = true end
	local lookalikes, items, seen = 0, 0, {}
	for s = 1, 2000 do
		local keys = if s % 2 == 0 then Seed.cartSeeds(Config, s, s * 3 + 1) else nil
		local sh = Shift.generate(Config, Rng, Rules, Seed.forShift(Config, 5000 + s, 0, s), 1, 1, keys)
		for _, it in sh.items do
			if not it.tutorial then
				items += 1
				seen[it.id] = (seen[it.id] or 0) + 1
				if tutorialIds[it.id] then lookalikes += 1 end
			end
		end
	end
	eq(lookalikes, 0, "U1: no item on career shift 1 but the tutorial's own is a Teddy Bear or a Phone (" .. lookalikes .. " of " .. items .. ")")
	local others, worst = 0, 0
	for _, it in Config.Catalog do
		if not tutorialIds[it.id] then others += 1 end
	end
	for _, it in Config.Catalog do
		if not tutorialIds[it.id] then
			worst = math.max(worst, math.abs((seen[it.id] or 0) / items - 1 / others))
		end
	end
	truthy(worst <= 0.01, string.format("... and the other %d archetypes are equally likely (worst deviation %.2f pp)", others, worst * 100))
	local later = 0
	for s = 1, 400 do
		local sh = gen(Seed.forShift(Config, 7000 + s, s, s), 2, 2)
		for _, it in sh.items do
			if tutorialIds[it.id] then later += 1 end
		end
	end
	truthy(later > 0, "CONTROL: Teddy Bears and Phones still turn up after career shift 1 (" .. later .. ")")
end

--============================================================ §7.3 independence and uniformity

do
	-- Own letter vs tag letter: agree 25% +- 1% over 40,000 items (letter not torn).
	local agree, n = 0, 0
	local s = 0
	while n < 40000 do
		s += 1
		local sh = gen(Seed.forShift(Config, 77, s, 3), 3, s + 1)
		for _, it in sh.items do
			if it.tag.letter ~= nil and n < 40000 then
				n += 1
				if it.tag.letter == it.own then agree += 1 end
			end
		end
	end
	local rate = agree / n
	print(string.format("  tag letter = own letter on %.2f%% of %d items", rate * 100, n))
	truthy(math.abs(rate - 0.25) <= 0.01, "tag letter and own letter agree 25% +- 1%")
end

do
	-- Answer uniformity per tray position, over 40,000 stage-1 shifts that are not career shift 1,
	-- and the bin permutation uniform over the six arc slots from the same run.
	local N = 40000
	local pos = {}
	for slot = 1, S.TraySlots do pos[slot] = {} end
	local arc = {}
	for slot = 1, 6 do arc[slot] = {} end
	for s = 1, N do
		local sh = gen(Seed.forShift(Config, 31337, s, 99), 1, s + 1)
		for slot = 1, S.TraySlots do
			local bin = sh.items[sh.tray[slot]].bin
			pos[slot][bin] = (pos[slot][bin] or 0) + 1
		end
		for slot = 1, 6 do
			local bin = sh.binSlots[slot]
			arc[slot][bin] = (arc[slot][bin] or 0) + 1
		end
	end
	local worstPos, worstArc = 0, 0
	for slot = 1, S.TraySlots do
		for _, bin in Config.Rules.Bins do
			worstPos = math.max(worstPos, math.abs((pos[slot][bin] or 0) / N - 1 / 6))
		end
	end
	for slot = 1, 6 do
		for _, bin in Config.Rules.Bins do
			worstArc = math.max(worstArc, math.abs((arc[slot][bin] or 0) / N - 1 / 6))
		end
	end
	print(string.format("  worst (tray position, bin) deviation %.3f pp; worst (arc slot, bin) %.3f pp",
		worstPos * 100, worstArc * 100))
	truthy(worstPos <= 0.01, "each bin is 1/6 +- 1% of answers in every one of the 8 tray positions")
	truthy(worstArc <= 0.01, "each bin lands in each arc slot 1/6 +- 1% of the time")
end

--============================================================ the cart does not follow from the tray

-- REVIEW-1 pass 3, exploit finding 3. With one seed for the whole shift, the 8 visible tray items and
-- the 6 bin signs pinned the seed down, and the seed generated the 22 cart items. With `cartSeeds`
-- (Seed.cartSeeds of two keys the tray never sees), each cart item comes from its own stream.
do
	local function key(it)
		return string.format("%d/%d/%s/%s/%s", it.archetype, it.variant, tostring(it.tag.letter), tostring(it.tag.cond),
			tostring(it.tag.route))
	end
	local seed = Seed.forShift(Config, 424242, 5, 777)
	local ka = Seed.cartSeeds(Config, 11, 22)
	local kb = Seed.cartSeeds(Config, 11, 23)
	local a = Shift.generate(Config, Rng, Rules, seed, 3, 6, ka)
	local b = Shift.generate(Config, Rng, Rules, seed, 3, 6, kb)
	local plain = gen(seed, 3, 6)
	local trayEqual, binsEqual = true, true
	for slot = 1, S.TraySlots do
		if key(a.items[a.tray[slot]]) ~= key(plain.items[plain.tray[slot]]) then trayEqual = false end
		if key(a.items[a.tray[slot]]) ~= key(b.items[b.tray[slot]]) then trayEqual = false end
	end
	for arc = 1, 6 do
		if a.binSlots[arc] ~= plain.binSlots[arc] or a.binSlots[arc] ~= b.binSlots[arc] then binsEqual = false end
	end
	truthy(trayEqual, "the tray still comes from the seed alone (the keys do not change it)")
	truthy(binsEqual, "... and so do the bins")
	eq(a.memo and a.memo.id, plain.memo and plain.memo.id, "... and the memo")
	eq(#a.cart, S.Items - S.TraySlots, "22 in the cart with cart seeds too")
	local sameAsPlain, sameAsB = 0, 0
	for _, n in a.cart do
		if key(a.items[n]) == key(plain.items[n]) then sameAsPlain += 1 end
		if key(a.items[n]) == key(b.items[n]) then sameAsB += 1 end
	end
	truthy(sameAsPlain <= 1, "E3: the seed that generated the tray does not generate the cart (" .. sameAsPlain .. " of 22 equal)")
	truthy(sameAsB <= 1, "E3: one different key gives a different cart (" .. sameAsB .. " of 22 equal)")
	local again = Shift.generate(Config, Rng, Rules, seed, 3, 6, ka)
	local replay = true
	for n = 1, S.Items do
		if key(again.items[n]) ~= key(a.items[n]) or again.items[n].bin ~= a.items[n].bin then replay = false end
	end
	truthy(replay, "the same seed and keys replay the same shift")

	-- over many shifts: the cart matches the seed-only cart at chance, and is as uniform as before
	local N, match, positions = 2000, 0, 0
	local arch, torn, stage2Items = {}, 0, 0
	for i = 1, N do
		local sd = Seed.forShift(Config, 99, i, 5)
		local keys = Seed.cartSeeds(Config, Seed.fmix(i * 7 + 1), Seed.fmix(i * 13 + 5))
		local with = Shift.generate(Config, Rng, Rules, sd, 2, 2, keys)
		local without = gen(sd, 2, 2)
		for _, n in with.cart do
			positions += 1
			if key(with.items[n]) == key(without.items[n]) then match += 1 end
			local it = with.items[n]
			arch[it.archetype] = (arch[it.archetype] or 0) + 1
			stage2Items += 1
			if it.torn then torn += 1 end
		end
	end
	local worst = 0
	for k = 1, #Config.Catalog do
		worst = math.max(worst, math.abs((arch[k] or 0) / positions - 1 / #Config.Catalog))
	end
	print(string.format("  cart with its own seeds: %d of %d items equal the seed-only cart; worst archetype deviation %.2f pp; torn %.2f%%",
		match, positions, worst * 100, 100 * torn / stage2Items))
	truthy(match <= 20, "E3: over 2000 shifts the cart equals the seed-only cart at chance (" .. match .. " of " .. positions .. ")")
	truthy(worst <= 0.01, "each archetype is 1/16 +- 1% of cart items")
	truthy(math.abs(torn / stage2Items - Config.Rules.TornChance) <= 0.01, "a stage-2 cart item is torn 25% +- 1% of the time")
end

--============================================================ startup guard

do
	local builders = {}
	for _, it in Config.Catalog do builders[it.builder] = true end
	eq(#Shift.missingBuilders(Config, builders), 0, "every archetype has a builder")
	builders.duck = nil
	local missing = Shift.missingBuilders(Config, builders)
	eq(#missing, 1, "a missing builder is reported")
	eq(missing[1], "duck", "... by archetype id")
end

do
	eq(#Config.Catalog, 16, "16 archetypes")
	local perLetter, names = {}, {}
	local dupName = 0
	for _, it in Config.Catalog do
		perLetter[it.letter] = (perLetter[it.letter] or 0) + 1
		if names[it.name] then dupName += 1 end
		names[it.name] = true
		eq(#it.colors, 2, it.name .. " has 2 colour variants")
	end
	for _, l in Config.Rules.Letters do eq(perLetter[l], 4, "4 items with letter " .. l) end
	eq(dupName, 0, "item names are unique")
end

print(string.format("Shift: %d passed, %d failed", passed, failed))
if failed > 0 then error("Shift tests failed") end
