-- Rules.spec — the Depot Manual as one pure function. Run: luau tests/Rules.spec.luau
--
-- DESIGN.md §3. Every percentage below is quoted from §3.5, where it was printed by
-- design/model.luau Part 1. Asserting them here against Rules.resolve (rather than the model's
-- own copy of the rules) is what ties the shipped function to the numbers the spec was built on.
local Rules = require("../src/shared/Rules")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print(string.format("FAIL: %s -> got %s, want %s +- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local R = Config.Rules
local BASE = Rules.base(Config)
local MEMOS = Rules.memos(Config)

--============================================================ the memo list

eq(#MEMOS, 12, "twelve memos")
do
	local fam = {}
	for _, m in MEMOS do fam[m.family] = (fam[m.family] or 0) + 1 end
	eq(fam.EXTRA_CLAIM, 5, "five EXTRA_CLAIM memos")
	eq(fam.EXTRA_BROKEN, 1, "one EXTRA_BROKEN memo")
	eq(fam.SWAP, 6, "six SWAP memos")
	local ids = {}
	local dup = 0
	for _, m in MEMOS do
		if ids[m.id] then dup += 1 end
		ids[m.id] = true
	end
	eq(dup, 0, "memo ids are unique")
	eq(Rules.memoById(Config, MEMOS[7].id), MEMOS[7], "memoById finds a memo")
	eq(Rules.memoById(Config, "NOPE"), nil, "memoById refuses an unknown id")
end

-- The memo lines, verbatim from §3.3.
eq(Rules.memoLine(Config, Rules.memoById(Config, "CLAIM_GREEN")),
	"GREEN route counts as claimed today -> CLAIMS", "EXTRA_CLAIM memo line")
eq(Rules.memoLine(Config, Rules.memoById(Config, "BROKEN_4")),
	"Condition 4 counts as broken today -> REPAIR", "EXTRA_BROKEN memo line")
eq(Rules.memoLine(Config, Rules.memoById(Config, "SWAP_BT")),
	"B and T swap bins today: B -> TOYS, T -> BAGS & WEAR", "SWAP memo line")

--============================================================ enumeration helper

-- Every (tag, own letter) with its probability under the generator's distribution: letter
-- uniform over 4, condition over 5, route over 6, one part torn with chance `torn` (each part
-- equally), own letter uniform over 4 and independent of the tag.
local function enumerate(torn: number, fn)
	local states = { { nil, 1 - torn }, { "letter", torn / 3 }, { "cond", torn / 3 }, { "route", torn / 3 } }
	for _, letter in R.Letters do
		for cond = 1, R.Conditions do
			for _, route in R.Routes do
				for _, st in states do
					for _, own in R.Letters do
						local p = (1 / 4) * (1 / R.Conditions) * (1 / #R.Routes) * st[2] * (1 / 4)
						local tag = { letter = letter, cond = cond, route = route }
						if st[1] ~= nil then tag[st[1]] = nil end
						fn(tag, own, p, st[1])
					end
				end
			end
		end
	end
end

--============================================================ every combination resolves

do
	local checked, unresolved = 0, 0
	local valid = {}
	for _, b in R.Bins do valid[b] = true end
	local sets = { BASE }
	for _, m in MEMOS do table.insert(sets, Rules.withMemo(Config, m)) end
	for _, rules in sets do
		enumerate(0.25, function(tag, own)
			checked += 1
			local bin = Rules.resolve(Config, tag, own, rules)
			if not valid[bin] then unresolved += 1 end
		end)
	end
	eq(checked, 24960, "24,960 (tag, own letter, rule set) combinations enumerated")
	eq(unresolved, 0, "every one resolves to exactly one of the six bins")
end

--============================================================ §3.5 stage 1: exactly even

do
	local share = {}
	local lookRight, letterRight = 0, 0
	enumerate(0, function(tag, own, p)
		local bin = Rules.resolve(Config, tag, own, BASE)
		share[bin] = (share[bin] or 0) + p
		if BASE.letterMap[own] == bin then lookRight += p end
		if BASE.letterMap[tag.letter] == bin then letterRight += p end
	end)
	for _, b in R.Bins do
		near(share[b], 1 / 6, 1e-12, "stage 1: " .. b .. " is exactly 1/6 of answers")
	end
	near(lookRight, 1 / 6, 1e-12, "stage 1: sorting by LOOK is right 16.7% (chance)")
	near(letterRight, 2 / 3, 1e-12, "stage 1: reading only the LETTER is right 66.7%")
end

--============================================================ §3.5 stage 2: torn tags

local function measure(rules, torn)
	local share, why = {}, {}
	local look, letterOnly, noMemo = 0, 0, 0
	enumerate(torn, function(tag, own, p)
		local bin, reason = Rules.resolve(Config, tag, own, rules)
		share[bin] = (share[bin] or 0) + p
		why[reason] = (why[reason] or 0) + p
		if rules.letterMap[own] == bin then look += p end
		local l = tag.letter or own
		if rules.letterMap[l] == bin then letterOnly += p end
		if Rules.resolve(Config, tag, own, BASE) == bin then noMemo += p end
	end)
	return { share = share, why = why, look = look, letterOnly = letterOnly, noMemo = noMemo }
end

local PP = 0.001 -- 0.1 percentage point
do
	local m = measure(BASE, R.TornChance)
	near(m.share.REPAIR, 0.225, PP, "stage 2: REPAIR 22.5%")
	near(m.share.CLAIMS, 0.153, PP, "stage 2: CLAIMS 15.3%")
	for _, b in { "BAGS", "ELECTRONICS", "KEYS", "TOYS" } do
		near(m.share[b], 0.156, PP, "stage 2: " .. b .. " 15.6%")
	end
	near(m.why["torn-cond"], 0.069, PP, "stage 2: torn condition decides 6.9%")
	near(m.why["torn-letter"], 0.056, PP, "stage 2: torn letter decides 5.6%")
	near(m.look, 0.197, PP, "stage 2: sorting by LOOK is right 19.7%")
	near(m.letterOnly, 0.622, PP, "stage 2: reading only the LETTER is right 62.2%")
end

--============================================================ §3.5 stage 3: memos

do
	local lookLo, lookHi, letLo, letHi, noLo, noHi = 1, 0, 1, 0, 1, 0
	local claimsHi, repairHi = 0, 0
	local changedLo, changedHi = math.huge, 0
	for _, memo in MEMOS do
		local rules = Rules.withMemo(Config, memo)
		local m = measure(rules, R.TornChance)
		lookLo, lookHi = math.min(lookLo, m.look), math.max(lookHi, m.look)
		letLo, letHi = math.min(letLo, m.letterOnly), math.max(letHi, m.letterOnly)
		noLo, noHi = math.min(noLo, m.noMemo), math.max(noHi, m.noMemo)
		if memo.family == "EXTRA_CLAIM" then claimsHi = math.max(claimsHi, m.share.CLAIMS) end
		if memo.family == "EXTRA_BROKEN" then repairHi = math.max(repairHi, m.share.REPAIR) end
		changedLo = math.min(changedLo, (1 - m.noMemo) * 30)
		changedHi = math.max(changedHi, (1 - m.noMemo) * 30)
	end
	near(lookLo, 0.148, PP, "stage 3: sorting by LOOK is right at least 14.8%")
	near(lookHi, 0.197, PP, "stage 3: ... and at most 19.7%")
	near(letLo, 0.467, PP, "stage 3: LETTER only at least 46.7%")
	near(letHi, 0.622, PP, "stage 3: ... and at most 62.2%")
	near(claimsHi, 0.306, PP, "stage 3: CLAIMS up to 30.6% under EXTRA_CLAIM")
	near(repairHi, 0.381, PP, "stage 3: REPAIR up to 38.1% under EXTRA_BROKEN")
	near(noLo, 0.689, PP, "stage 3: ignoring the memo still right at least 68.9%")
	near(noHi, 0.847, PP, "stage 3: ... and at most 84.7%")
	near(changedLo, 4.6, 0.05, "a memo changes the answer for at least 4.6 of 30 items")
	near(changedHi, 9.3, 0.05, "... and at most 9.3")
end

--============================================================ §3.4 clause by clause

do
	local function r(tag, own, rules) return (Rules.resolve(Config, tag, own, rules or BASE)) end
	eq(r({ letter = "T", cond = 3, route = "RED" }, "B"), "CLAIMS", "RED route -> CLAIMS, before everything")
	eq(r({ letter = "T", cond = 5, route = "RED" }, "B"), "CLAIMS", "RED beats condition 5")
	eq(r({ letter = "T", cond = 5, route = "GREEN" }, "B"), "REPAIR", "condition 5 -> REPAIR")
	eq(r({ letter = "T", cond = 4, route = "GREEN" }, "B"), "TOYS", "otherwise the LETTER picks the bin")
	eq(r({ letter = "E", cond = 1, route = "WHITE" }, "T"), "ELECTRONICS", "the tag beats the item's own letter")
	-- torn route: not claimed, keep going
	eq(r({ letter = "K", cond = 2, route = nil }, "B"), "KEYS", "route torn off: not claimed, keep going")
	eq(r({ letter = "K", cond = 5, route = nil }, "B"), "REPAIR", "route torn off, condition 5: REPAIR")
	-- torn condition: REPAIR unless the route already sent it to CLAIMS
	eq(r({ letter = "K", cond = nil, route = "BLUE" }, "B"), "REPAIR", "condition torn off -> REPAIR")
	eq(r({ letter = "K", cond = nil, route = "RED" }, "B"), "CLAIMS", "condition torn off but RED -> CLAIMS first")
	-- torn letter: the item's own letter
	eq(r({ letter = nil, cond = 2, route = "BLUE" }, "E"), "ELECTRONICS", "letter torn off -> the item's own letter")
	eq(r({ letter = nil, cond = 5, route = "BLUE" }, "E"), "REPAIR", "letter torn off, condition 5 still REPAIR")

	-- memos change what counts at one step, never the order
	local claimGreen = Rules.withMemo(Config, Rules.memoById(Config, "CLAIM_GREEN"))
	eq(r({ letter = "T", cond = 5, route = "GREEN" }, "B", claimGreen), "CLAIMS", "EXTRA_CLAIM GREEN: GREEN beats condition 5")
	eq(r({ letter = "T", cond = 5, route = "RED" }, "B", claimGreen), "CLAIMS", "EXTRA_CLAIM keeps RED claimed")
	local broken4 = Rules.withMemo(Config, Rules.memoById(Config, "BROKEN_4"))
	eq(r({ letter = "T", cond = 4, route = "BLUE" }, "B", broken4), "REPAIR", "EXTRA_BROKEN 4: condition 4 -> REPAIR")
	eq(r({ letter = "T", cond = 4, route = "RED" }, "B", broken4), "CLAIMS", "EXTRA_BROKEN never outranks the route")
	local swapBT = Rules.withMemo(Config, Rules.memoById(Config, "SWAP_BT"))
	eq(r({ letter = "B", cond = 1, route = "BLUE" }, "E", swapBT), "TOYS", "SWAP B/T: B -> TOYS")
	eq(r({ letter = "T", cond = 1, route = "BLUE" }, "E", swapBT), "BAGS", "SWAP B/T: T -> BAGS & WEAR")
	eq(r({ letter = "E", cond = 1, route = "BLUE" }, "B", swapBT), "ELECTRONICS", "SWAP B/T leaves E alone")
	-- "A torn letter is resolved to the item's own letter first, and then the swap applies to it."
	eq(r({ letter = nil, cond = 1, route = "BLUE" }, "T", swapBT), "BAGS", "a swap applies to a torn letter AFTER the own-letter step")
	eq(r({ letter = nil, cond = 1, route = "BLUE" }, "B", swapBT), "TOYS", "... in both directions")

	-- withMemo never mutates the base rules
	eq(r({ letter = "B", cond = 1, route = "BLUE" }, "E"), "BAGS", "withMemo left the base rules untouched")
	eq(BASE.claim.GREEN, nil, "withMemo did not add GREEN to the base claim set")
end

--============================================================ explain names the deciding rule

local function isAscii(s: string): boolean
	return string.find(s, "[\128-\255]") == nil
end

do
	local bad, nonAscii, total = 0, 0, 0
	local sample = nil
	local sets = { { BASE, nil } }
	for _, m in MEMOS do table.insert(sets, { Rules.withMemo(Config, m), m }) end
	local names = {}
	for _, it in Config.Catalog do names[it.letter] = names[it.letter] or it.name end
	for _, set in sets do
		local rules = set[1]
		enumerate(0.25, function(tag, own)
			total += 1
			local bin, why = Rules.resolve(Config, tag, own, rules)
			local text = Rules.explain(Config, tag, own, rules, names[own])
			if not isAscii(text) then nonAscii += 1 end
			local binName = R.BinNames[bin]
			local ok = string.find(text, binName, 1, true) ~= nil
			if why == "route" then
				ok = ok and string.find(text, tag.route .. " route", 1, true) ~= nil
			elseif why == "torn-cond" then
				ok = ok and string.find(text, "Condition torn off", 1, true) ~= nil
			elseif why == "cond" then
				ok = ok and string.find(text, "ondition " .. tag.cond, 1, true) ~= nil
			elseif why == "letter" then
				ok = ok and string.find(text, tag.letter .. " goes to", 1, true) ~= nil
			elseif why == "torn-letter" then
				ok = ok and string.find(text, "Letter torn off", 1, true) ~= nil
					and string.find(text, names[own], 1, true) ~= nil
					and string.find(text, "is " .. own, 1, true) ~= nil
			else
				ok = false
			end
			-- The memo is named exactly when the memo is what changed the answer.
			local memoDriven = Rules.resolve(Config, tag, own, BASE) ~= bin
			local mentions = string.find(text, "memo", 1, true) ~= nil
			if memoDriven ~= mentions then ok = false end
			if not ok then
				bad += 1
				sample = sample or string.format("%s/%s/%s own %s -> %s (%s): %q", tostring(tag.letter),
					tostring(tag.cond), tostring(tag.route), own, bin, why, text)
			end
		end)
	end
	eq(total, 24960, "explain checked on every combination")
	eq(bad, 0, "explain names the deciding rule (and the memo exactly when it decided)"
		.. (if sample then " e.g. " .. sample else ""))
	eq(nonAscii, 0, "every explain string is ASCII")
end

eq(Rules.explain(Config, { letter = "T", cond = 5, route = "GREEN" }, "B", BASE, "Backpack"),
	"Condition 5 goes to REPAIR.", "the misfile toast from DESIGN.md 5.1, verbatim")

--============================================================ the manual text

do
	local s1 = table.concat(Rules.manualLines(Config, 1), "\n")
	eq(s1, table.concat({
		"DEPOT MANUAL - check in this order",
		"1. RED route?              -> CLAIMS",
		"2. Condition 5?            -> REPAIR",
		"3. Otherwise the LETTER picks the bin:",
		"   B = BAGS & WEAR    E = ELECTRONICS    K = KEYS & WALLETS    T = TOYS",
		"Trust the TAG, not the item.",
	}, "\n"), "the stage-1 manual is DESIGN.md 3.3 verbatim")

	local s2 = Rules.manualLines(Config, 2)
	local joined2 = table.concat(s2, "\n")
	truthy(string.find(joined2, "TORN TAGS", 1, true) ~= nil, "stage 2 adds TORN TAGS")
	truthy(string.find(joined2, "- Route torn off?          It is not claimed. Keep going.", 1, true) ~= nil, "stage 2 route line verbatim")
	truthy(string.find(joined2, "- Condition torn off?      -> REPAIR (unless step 1 already sent it to CLAIMS)", 1, true) ~= nil, "stage 2 condition line verbatim")
	truthy(string.find(joined2, "- Letter torn off?         Use the item's own letter (see the catalog).", 1, true) ~= nil, "stage 2 letter line verbatim")
	truthy(string.find(table.concat(Rules.manualLines(Config, 1), "\n"), "TORN", 1, true) == nil, "stage 1 has no torn lines")

	local memo = Rules.memoById(Config, "SWAP_EK")
	local joined3 = table.concat(Rules.manualLines(Config, 3, memo), "\n")
	truthy(string.find(joined3, "TODAY'S MEMO: " .. Rules.memoLine(Config, memo), 1, true) ~= nil, "stage 3 adds the memo box")
	truthy(string.find(joined2, "TODAY'S MEMO", 1, true) == nil, "stage 2 has no memo box")

	-- The NEW marks: each line knows the layer that introduced it.
	local sections = Rules.manualSections(Config, 3, memo)
	eq(#sections, 3, "three manual layers at stage 3")
	eq(sections[2].layer, 2, "the second section is layer 2")

	-- THE CATALOG (REVIEW-1 R2-7). "Letter torn off? Use the item's own letter (see the catalog)"
	-- pointed at nothing: no board, drawer or label anywhere said which letter a Padlock is. A torn
	-- letter was only solvable by guessing from the bin names. The catalog is part of layer 2, the
	-- layer that introduces torn letters, and is built from Config.Catalog rather than copied.
	do
		local catalogLines = {}
		for _, line in sections[2].lines do
			if string.match(line, "^[A-Z]: ") then table.insert(catalogLines, line) end
		end
		eq(#catalogLines, #Config.Rules.Letters, "layer 2 carries one catalog line per letter")
		local misplaced, missing = 0, 0
		for _, item in Config.Catalog do
			local found = 0
			for _, line in catalogLines do
				local letter, names = string.match(line, "^([A-Z]): (.+)$")
				for name in string.gmatch(names, "[^,]+") do
					name = string.gsub(name, "^%s+", "")
					if name == item.name then
						found += 1
						if letter ~= item.letter then misplaced += 1 end
					end
				end
			end
			if found ~= 1 then missing += 1 end
		end
		eq(missing, 0, "every catalog item is named exactly once in the manual's catalog")
		eq(misplaced, 0, "... on the line of its own letter")
		truthy(string.find(joined2, "CATALOG", 1, true) ~= nil, "the stage-2 manual shows a CATALOG heading")
		local s1lines = table.concat(Rules.manualLines(Config, 1), "\n")
		eq(string.find(s1lines, "CATALOG", 1, true), nil, "stage 1 shows no catalog: nothing is torn, and the tag beats the look")
		eq(string.find(s1lines, "Padlock", 1, true), nil, "... and names no item")
	end

	local nonAscii = 0
	for stage = 1, 3 do
		for _, line in Rules.manualLines(Config, stage, memo) do
			if not isAscii(line) then nonAscii += 1 end
		end
	end
	for _, m in MEMOS do
		if not isAscii(Rules.memoLine(Config, m)) then nonAscii += 1 end
	end
	eq(nonAscii, 0, "every manual and memo string is ASCII")
end

--============================================================ tag text

eq(Rules.tagText(Config, { letter = "T", cond = 3, route = "RED" }), "T \u{B7} 3 \u{B7} RED", "tag renders as T . 3 . RED")
eq(Rules.tagText(Config, { letter = nil, cond = 3, route = "RED" }), "? \u{B7} 3 \u{B7} RED", "a torn letter renders as ?")
eq(Rules.tagText(Config, { letter = "K", cond = nil, route = "BLUE" }), "K \u{B7} ? \u{B7} BLUE", "a torn condition renders as ?")
eq(Rules.tagText(Config, { letter = "K", cond = 1, route = nil }), "K \u{B7} 1 \u{B7} ?", "a torn route renders as ?")
do
	local rich = Rules.tagRich(Config, { letter = "T", cond = 3, route = "RED" })
	truthy(string.find(rich, '<font color="#FF5A5A">RED</font>', 1, true) ~= nil, "the route word is coloured in RichText: " .. rich)
	local stripped = string.gsub(rich, "<[^>]*>", "")
	eq(stripped, "T \u{B7} 3 \u{B7} RED", "stripping the RichText leaves the plain tag")
	local torn = Rules.tagRich(Config, { letter = "T", cond = 3, route = nil })
	truthy(string.find(torn, '<font color="#9696A0">?</font>', 1, true) ~= nil, "a torn part is a grey ?: " .. torn)
	-- Parsing it back (what a player's eye and the headless check both do)
	local back = Rules.parseTag(Config, stripped)
	eq(back and back.letter, "T", "parseTag reads the letter")
	eq(back and back.cond, 3, "parseTag reads the condition as a number")
	eq(back and back.route, "RED", "parseTag reads the route")
	local backTorn = Rules.parseTag(Config, "? \u{B7} 3 \u{B7} RED")
	truthy(backTorn ~= nil and backTorn.letter == nil and backTorn.cond == 3, "parseTag reads a torn letter as nil")
	eq(Rules.parseTag(Config, "MISFILED - goes to REPAIR"), nil, "parseTag refuses what is not a tag")
end

print(string.format("Rules: %d passed, %d failed", passed, failed))
if failed > 0 then error("Rules tests failed") end
