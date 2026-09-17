--!strict
-- Rules.luau — the Depot Manual as pure functions (DESIGN.md §3).
--
--   resolve(tag, ownLetter, rules):
--     if tag.route ~= nil and rules.claim[tag.route]  -> CLAIMS
--     if tag.cond == nil                              -> REPAIR     -- torn condition
--     if rules.broken[tag.cond]                       -> REPAIR
--     letter = tag.letter or ownLetter                               -- torn letter
--     -> rules.letterMap[letter]
--
-- A tag is { letter, cond, route }. A TORN part is simply absent (nil) — on the server too — so
-- there is no hidden value anywhere to leak, scan or post (§7.3).
--
-- A memo never changes the ORDER of the manual; it changes what counts at one step. `withMemo`
-- builds a fresh rule set and never touches the base.
--
-- Every string this module produces for a player is ASCII except the tag separator U+00B7
-- (Latin-1, not in question — §13.4). Pure, requires nothing.

local Rules = {}

export type Tag = { letter: string?, cond: number?, route: string? }
export type Memo = { id: string, family: string, route: string?, cond: number?, a: string?, b: string? }
export type RuleSet = {
	claim: { [string]: boolean },
	broken: { [number]: boolean },
	letterMap: { [string]: string },
	memo: Memo?,
}

local SEP = " \u{B7} "

function Rules.base(cfg: any): RuleSet
	local lm = {}
	for k, v in cfg.Rules.LetterBin do
		lm[k] = v
	end
	return {
		claim = { [cfg.Rules.ClaimedRoute] = true },
		broken = { [cfg.Rules.BrokenCondition] = true },
		letterMap = lm,
		memo = nil,
	}
end

-- The twelve memos, in a fixed order (the generator indexes this list with Rng.below(12)):
-- 5 EXTRA_CLAIM (every route but RED), 1 EXTRA_BROKEN (condition 4), 6 SWAP (every letter pair).
local memoCache: { [any]: { Memo } } = {}
function Rules.memos(cfg: any): { Memo }
	local cached = memoCache[cfg]
	if cached then
		return cached
	end
	local list: { Memo } = {}
	for _, route in cfg.Rules.Routes do
		if route ~= cfg.Rules.ClaimedRoute then
			table.insert(list, { id = "CLAIM_" .. route, family = "EXTRA_CLAIM", route = route })
		end
	end
	local extraBroken = cfg.Rules.BrokenCondition - 1
	table.insert(list, { id = "BROKEN_" .. extraBroken, family = "EXTRA_BROKEN", cond = extraBroken })
	local L = cfg.Rules.Letters
	for i = 1, #L do
		for j = i + 1, #L do
			table.insert(list, { id = "SWAP_" .. L[i] .. L[j], family = "SWAP", a = L[i], b = L[j] })
		end
	end
	memoCache[cfg] = list
	return list
end

function Rules.memoById(cfg: any, id: string): Memo?
	for _, m in Rules.memos(cfg) do
		if m.id == id then
			return m
		end
	end
	return nil
end

function Rules.withMemo(cfg: any, memo: Memo?): RuleSet
	local r = Rules.base(cfg)
	if memo == nil then
		return r
	end
	r.memo = memo
	if memo.family == "EXTRA_CLAIM" then
		r.claim[memo.route :: string] = true
	elseif memo.family == "EXTRA_BROKEN" then
		r.broken[memo.cond :: number] = true
	elseif memo.family == "SWAP" then
		local a, b = memo.a :: string, memo.b :: string
		r.letterMap[a], r.letterMap[b] = r.letterMap[b], r.letterMap[a]
	end
	return r
end

-- -> bin id, and which clause decided it: "route" | "torn-cond" | "cond" | "letter" | "torn-letter"
function Rules.resolve(_cfg: any, tag: Tag, ownLetter: string, rules: RuleSet): (string, string)
	if tag.route ~= nil and rules.claim[tag.route] then
		return "CLAIMS", "route"
	end
	if tag.cond == nil then
		return "REPAIR", "torn-cond"
	end
	if rules.broken[tag.cond] then
		return "REPAIR", "cond"
	end
	if tag.letter == nil then
		return rules.letterMap[ownLetter], "torn-letter"
	end
	return rules.letterMap[tag.letter], "letter"
end

-- The toast after a misfile: names the rule that decided the answer, and names the memo exactly
-- when the memo is what changed it. `itemName` is the item's catalog name (for a torn letter).
function Rules.explain(cfg: any, tag: Tag, ownLetter: string, rules: RuleSet, itemName: string?): string
	local bin, why = Rules.resolve(cfg, tag, ownLetter, rules)
	local name = cfg.Rules.BinNames[bin]
	local memoDecided = Rules.resolve(cfg, tag, ownLetter, Rules.base(cfg)) ~= bin
	if why == "route" then
		if memoDecided then
			return "Today's memo: " .. tostring(tag.route) .. " route goes to " .. name .. "."
		end
		return tostring(tag.route) .. " route goes to " .. name .. "."
	elseif why == "torn-cond" then
		return "Condition torn off goes to " .. name .. "."
	elseif why == "cond" then
		if memoDecided then
			return "Today's memo: condition " .. tostring(tag.cond) .. " goes to " .. name .. "."
		end
		return "Condition " .. tostring(tag.cond) .. " goes to " .. name .. "."
	elseif why == "torn-letter" then
		local what = itemName or "this item"
		if memoDecided then
			return "Letter torn off: a " .. what .. " is " .. ownLetter .. ", and today's memo sends "
				.. ownLetter .. " to " .. name .. "."
		end
		return "Letter torn off: a " .. what .. " is " .. ownLetter .. ", so " .. name .. "."
	end
	if memoDecided then
		return "Today's memo: " .. tostring(tag.letter) .. " goes to " .. name .. "."
	end
	return tostring(tag.letter) .. " goes to " .. name .. "."
end

function Rules.memoLine(cfg: any, memo: Memo): string
	local names = cfg.Rules.BinNames
	if memo.family == "EXTRA_CLAIM" then
		return tostring(memo.route) .. " route counts as claimed today -> " .. names.CLAIMS
	elseif memo.family == "EXTRA_BROKEN" then
		return "Condition " .. tostring(memo.cond) .. " counts as broken today -> " .. names.REPAIR
	end
	local a, b = memo.a :: string, memo.b :: string
	return a .. " and " .. b .. " swap bins today: " .. a .. " -> " .. names[cfg.Rules.LetterBin[b]]
		.. ", " .. b .. " -> " .. names[cfg.Rules.LetterBin[a]]
end

-- The manual, layer by layer. Stage 1 is the base; stage 2 adds torn tags; stage 3 adds the memo
-- box. Each section knows its layer, which is how the HUD marks the lines a new stage added NEW.
function Rules.manualSections(cfg: any, stage: number, memo: Memo?): { { layer: number, lines: { string } } }
	local R = cfg.Rules
	local names = R.BinNames
	local function pad(s: string, width: number): string
		return s .. string.rep(" ", math.max(0, width - #s))
	end
	local letters = {}
	for _, l in R.Letters do
		table.insert(letters, l .. " = " .. names[R.LetterBin[l]])
	end
	local lettersLine = "   " .. table.concat(letters, "    ")
	local out = {
		{
			layer = 1,
			lines = {
				"DEPOT MANUAL - check in this order",
				pad("1. " .. R.ClaimedRoute .. " route?", 27) .. "-> " .. names.CLAIMS,
				pad("2. Condition " .. R.BrokenCondition .. "?", 27) .. "-> " .. names.REPAIR,
				"3. Otherwise the LETTER picks the bin:",
				lettersLine,
				"Trust the TAG, not the item.",
			},
		},
	}
	if stage >= 2 then
		table.insert(out, {
			layer = 2,
			lines = {
				"TORN TAGS",
				pad("- Route torn off?", 27) .. "It is not claimed. Keep going.",
				pad("- Condition torn off?", 27) .. "-> " .. names.REPAIR .. " (unless step 1 already sent it to "
					.. names.CLAIMS .. ")",
				pad("- Letter torn off?", 27) .. "Use the item's own letter (see the catalog).",
				-- The catalog the line above points at, built from Config.Catalog (REVIEW-1 R2-7:
				-- it used to point at nothing). Only from stage 2: before letters can be torn, an
				-- item-to-letter table would contradict "Trust the TAG, not the item".
				"CATALOG - each item's own letter",
			},
		})
		local catalogSection = out[#out].lines
		for _, letter in R.Letters do
			local itemNames = {}
			for _, item in cfg.Catalog do
				if item.letter == letter then
					table.insert(itemNames, item.name)
				end
			end
			table.insert(catalogSection, letter .. ": " .. table.concat(itemNames, ", "))
		end
	end
	if stage >= 3 then
		table.insert(out, {
			layer = 3,
			lines = {
				"TODAY'S MEMO: " .. (if memo then Rules.memoLine(cfg, memo) else "(none)"),
			},
		})
	end
	return out
end

function Rules.manualLines(cfg: any, stage: number, memo: Memo?): { string }
	local lines = {}
	for _, section in Rules.manualSections(cfg, stage, memo) do
		for _, l in section.lines do
			table.insert(lines, l)
		end
	end
	return lines
end

-- "T · 3 · RED", with "?" for a torn part.
function Rules.tagText(_cfg: any, tag: Tag): string
	return (tag.letter or "?") .. SEP .. (if tag.cond then tostring(tag.cond) else "?") .. SEP .. (tag.route or "?")
end

local function hex(rgb: { number }): string
	return string.format("#%02X%02X%02X", rgb[1], rgb[2], rgb[3])
end

-- The same text for a RichText TextLabel: the route WORD in its colour, a torn part as a grey "?".
-- The route is always spelled out, so no rule depends on seeing colour (§13.2).
function Rules.tagRich(cfg: any, tag: Tag): string
	local torn = '<font color="' .. hex(cfg.Colors.Torn) .. '">?</font>'
	local letter = tag.letter or torn
	local cond = if tag.cond then tostring(tag.cond) else torn
	local route = torn
	if tag.route then
		route = '<font color="' .. hex(cfg.Colors.Route[tag.route]) .. '">' .. tag.route .. "</font>"
	end
	return letter .. SEP .. cond .. SEP .. route
end

-- Read a plain tag string back into a tag, or nil if the text is not a tag at all. This is what a
-- player's eye does, and what the headless check uses to derive every answer from the world.
function Rules.parseTag(cfg: any, text: string): Tag?
	if type(text) ~= "string" then
		return nil
	end
	local parts = string.split(text, SEP)
	if #parts ~= 3 then
		return nil
	end
	local tag: Tag = {}
	local l, c, r = parts[1], parts[2], parts[3]
	if l ~= "?" then
		if not table.find(cfg.Rules.Letters, l) then
			return nil
		end
		tag.letter = l
	end
	if c ~= "?" then
		local n = tonumber(c)
		if n == nil or n % 1 ~= 0 or n < 1 or n > cfg.Rules.Conditions then
			return nil
		end
		tag.cond = n
	end
	if r ~= "?" then
		if not table.find(cfg.Rules.Routes, r) then
			return nil
		end
		tag.route = r
	end
	return tag
end

return Rules
