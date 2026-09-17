--!strict
-- Shift.luau — generate one shift (DESIGN.md §7.2), pure.
--
-- One Rng, every small range through Rng.below (the high bits; `state % span` collapses for even
-- spans — the "LCG low bits" trap). The draw order is fixed, because the order IS the generator:
--
--   1. the memo (stage 3 only)                           below(12)
--   2. the bin arrangement: Fisher-Yates over 6 slots    below(i), i = 6..2
--   3. 30 items, each:  archetype below(16), variant below(2), letter below(4), condition below(5),
--      route below(6), then from stage 2 a torn roll next() < TornChance and, if torn, which part
--      below(3). THE TORN PART IS DELETED. Nothing about it survives, on the server either.
--   4. career shift 1 only: item 1 becomes the Teddy Bear (T . 2 . GREEN, back-row slot 6) and
--      item 2 the Phone (K . 1 . BLUE, slot 7); items 3-8 fill the other slots in slot order.
--   5. items 1-8 are the tray, 9-30 the cart.
--
-- Two exceptions, both from REVIEW-1 pass 3: with `cartSeeds`, each cart item (9-30) draws step 3
-- from its own stream instead of the shift's; and on career shift 1 the archetype draw is over the
-- catalog WITHOUT the tutorial's archetypes, so nothing else on that shift looks like the tutorial's
-- Teddy Bear or Phone.
--
-- The tag letter is drawn WITHOUT looking at the item, so it agrees with the item's own letter one
-- time in four — the "trust the tag, not the item" hook. Nothing about an item's look (archetype,
-- variant) depends on its answer.
--
-- Dependencies come in as arguments (Rng, Rules); a `require("./X")` would resolve in the luau CLI
-- and fail in Roblox.

local Shift = {}

local TORN_PARTS = { "letter", "cond", "route" }

function Shift.stageFor(cfg: any, careerShift: number): number
	if careerShift >= cfg.Rules.MemoUnlockShift then
		return 3
	elseif careerShift >= cfg.Rules.TornUnlockShift then
		return 2
	end
	return 1
end

local function catalogIndex(cfg: any, id: string): number
	for i, it in cfg.Catalog do
		if it.id == id then
			return i
		end
	end
	error("Shift: no catalog entry '" .. tostring(id) .. "'")
end

local function makeItem(cfg: any, n: number, archetype: number, variant: number, tag, torn: string?)
	local entry = cfg.Catalog[archetype]
	return {
		n = n,
		archetype = archetype,
		id = entry.id,
		name = entry.name,
		own = entry.letter,
		variant = variant,
		tag = tag,
		torn = torn,
		bin = "",
		tutorial = false,
	}
end

-- `seed` from Seed.forShift; `stage` 1..3; `careerShift` is 1 for a player's very first shift.
-- `cartSeeds` (Seed.cartSeeds) gives every cart item (n > TraySlots) its own stream, drawn in the
-- same per-item order; without it the whole shift comes from `seed`, as in DESIGN.md §7.2. The server
-- always passes it: with one seed, the visible tray predicts the cart (REVIEW-1 pass 3, exploit 3).
function Shift.generate(cfg: any, Rng: any, Rules: any, seed: number, stage: number, careerShift: number,
	cartSeeds: { [number]: number }?)
	local R = cfg.Rules
	local S = cfg.Shift
	local rng = Rng.new(seed)

	-- 1. the memo
	local memo = nil
	if stage >= 3 then
		local memos = Rules.memos(cfg)
		memo = memos[Rng.below(rng, #memos)]
	end
	local rules = Rules.withMemo(cfg, memo)

	-- 2. the bin arrangement
	local perm = { 1, 2, 3, 4, 5, 6 }
	for i = #perm, 2, -1 do
		local j = Rng.below(rng, i)
		perm[i], perm[j] = perm[j], perm[i]
	end
	local binSlots, slotOfBin = {}, {}
	for i, bin in R.Bins do
		binSlots[perm[i]] = bin
		slotOfBin[bin] = perm[i]
	end

	-- 3. the items. On career shift 1 the archetype is drawn from the catalog WITHOUT the tutorial's
	-- own archetypes (one draw, over the 14 others): a second Phone on that tray was taken for the
	-- tutorial's Phone and misfiled against the hint (REVIEW-1 pass 3, player-path finding 1).
	local pool = nil
	if careerShift == 1 then
		pool = {}
		local tutorialArchetype = {}
		for _, t in S.Tutorial do
			tutorialArchetype[catalogIndex(cfg, t.archetype)] = true
		end
		for i = 1, #cfg.Catalog do
			if not tutorialArchetype[i] then
				table.insert(pool, i)
			end
		end
	end
	local items = {}
	for n = 1, S.Items do
		local stream = if cartSeeds and n > S.TraySlots then Rng.new(cartSeeds[n]) else rng
		local archetype = if pool then pool[Rng.below(stream, #pool)] else Rng.below(stream, #cfg.Catalog)
		local variant = Rng.below(stream, 2)
		local tag = {
			letter = R.Letters[Rng.below(stream, #R.Letters)],
			cond = Rng.below(stream, R.Conditions),
			route = R.Routes[Rng.below(stream, #R.Routes)],
		}
		local torn = nil
		if stage >= 2 and Rng.next(stream) < R.TornChance then
			torn = TORN_PARTS[Rng.below(stream, 3)]
			tag[torn] = nil
		end
		items[n] = makeItem(cfg, n, archetype, variant, tag, torn)
	end

	-- 4. the tutorial
	local tray = {}
	if careerShift == 1 then
		for k, t in S.Tutorial do
			local it = makeItem(cfg, k, catalogIndex(cfg, t.archetype), t.variant,
				{ letter = t.letter, cond = t.cond, route = t.route }, nil)
			it.tutorial = true
			items[k] = it
			tray[t.slot] = k
		end
	end

	for _, it in items do
		it.bin = (Rules.resolve(cfg, it.tag, it.own, rules))
	end

	-- 5. tray fill in generation order, then the cart
	local nextItem = 1
	local placed = {}
	for _, n in tray do
		placed[n] = true
	end
	for slot = 1, S.TraySlots do
		if tray[slot] == nil then
			while placed[nextItem] do
				nextItem += 1
			end
			tray[slot] = nextItem
			placed[nextItem] = true
		end
	end
	local cart = {}
	for n = 1, S.Items do
		if not placed[n] then
			table.insert(cart, n)
		end
	end

	return {
		stage = stage,
		memo = memo,
		rules = rules,
		binSlots = binSlots,
		slotOfBin = slotOfBin,
		items = items,
		tray = tray,
		cart = cart,
	}
end

-- The startup guard: every archetype must have a Part recipe, or an item would render as nothing
-- at all. Returns the archetype ids that have none.
function Shift.missingBuilders(cfg: any, builders: { [string]: any }): { string }
	local out = {}
	for _, it in cfg.Catalog do
		if builders[it.builder] == nil then
			table.insert(out, it.id)
		end
	end
	return out
end

return Shift
