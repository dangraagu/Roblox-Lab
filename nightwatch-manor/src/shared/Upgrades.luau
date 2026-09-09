--!strict
-- Upgrades.luau — the safehouse tycoon side: what an upgrade costs, whether it can be bought,
-- and what the aggregated stack does to the next night's numbers. PURE LOGIC, config passed in.
--
-- The night reads ONLY the table `effects` returns. That is the whole contract between the two
-- halves of the game, which is why the spec asserts in both directions: every `per` key in the
-- catalog is a key this file reads, and every key this file can produce is granted by something.
-- A misspelling in either direction is an upgrade the player pays for and never receives.
--
-- No `require` here — dependencies come in as arguments (see the note in Manor.luau).
export type Levels = { [string]: number }
export type Effects = {
	lampRadius: number,
	dreadSlow: number,
	watcherSlow: number,
	warnRange: number,
	relicValue: number,
	keepOnCaught: number,
	extractSeconds: number,
}

local Upgrades = {}

-- The complete set of effects an upgrade may grant. Used as a gate in both directions.
Upgrades.EFFECT_KEYS = {
	lampRadius = true, -- studs of extra light on the lantern you carry
	dreadSlow = true, -- fraction: the manor wakes this much slower
	watcherSlow = true, -- fraction: the Nightwatcher walks this much slower
	warnRange = true, -- studs: how far away the HUD warns you it has seen you
	relicValue = true, -- fraction: every banked relic is worth this much more
	keepOnCaught = true, -- fraction of your haul kept when it catches you
	extractSeconds = true, -- extra seconds before the manor is fully awake
}

local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

function Upgrades.byId(cfg: any, id: string): any
	for _, e in cfg.Upgrades.Catalog do
		if e.id == id then
			return e
		end
	end
	return nil
end

function Upgrades.level(levels: Levels, id: string): number
	local v = levels[id]
	if type(v) ~= "number" then
		return 0
	end
	return v
end

-- Sum of every level. Gates manor size (see Manor.roomCount) and is the number the HUD shows.
function Upgrades.hubLevel(levels: Levels): number
	local n = 0
	for _, v in levels do
		if type(v) == "number" and v > 0 then
			n += math.floor(v)
		end
	end
	return n
end

-- Cost of going from `level` to `level + 1`, in relics. Nil when the id is unknown or the
-- upgrade is already at its cap — nil means "there is nothing to buy", never "it is free".
function Upgrades.cost(cfg: any, id: string, level: number): number?
	local e = Upgrades.byId(cfg, id)
	if not e then
		return nil
	end
	local lv = math.max(math.floor(level), 0)
	if lv >= e.max then
		return nil
	end
	return math.floor(e.baseCost * e.costMul ^ lv + 0.5)
end

-- (canBuy, reason). The reason exists so the server can TELL the player why nothing happened:
-- a silent return is the exact failure that had a player posting "i cant even place a seed"
-- about a sibling game.
function Upgrades.canBuy(cfg: any, levels: Levels, stash: number, id: string): (boolean, string)
	local e = Upgrades.byId(cfg, id)
	if not e then
		return false, "unknown"
	end
	local cost = Upgrades.cost(cfg, id, Upgrades.level(levels, id))
	if cost == nil then
		return false, "maxed"
	end
	if stash < cost then
		return false, "poor"
	end
	return true, "ok"
end

-- Buy one level. Returns (ok, levels, stash, reason) and NEVER mutates the table it was given:
-- the server applies the result only once the DataStore write has actually landed, and a
-- mutated input would have spent the relics before that.
function Upgrades.buy(cfg: any, levels: Levels, stash: number, id: string): (boolean, Levels, number, string)
	local copy: Levels = {}
	for k, v in levels do
		copy[k] = v
	end
	local ok, reason = Upgrades.canBuy(cfg, levels, stash, id)
	if not ok then
		return false, copy, stash, reason
	end
	local cost = Upgrades.cost(cfg, id, Upgrades.level(levels, id)) :: number
	copy[id] = Upgrades.level(levels, id) + 1
	return true, copy, stash - cost, "ok"
end

-- Aggregate the whole safehouse into the numbers the night reads. Every level is clamped to
-- its own cap first (a hand-edited save must not pay out), then the three effects that could
-- END the game if they reached 1 are clamped again against the config ceilings.
function Upgrades.effects(cfg: any, levels: Levels): Effects
	local out: any = {}
	for key in Upgrades.EFFECT_KEYS do
		out[key] = 0
	end

	for _, e in cfg.Upgrades.Catalog do
		local raw = levels[e.id]
		if type(raw) == "number" then
			local lv = clamp(math.floor(raw), 0, e.max)
			if lv > 0 then
				for key, per in e.per do
					if Upgrades.EFFECT_KEYS[key] then
						out[key] += per * lv
					end
				end
			end
		end
	end

	local U = cfg.Upgrades
	out.dreadSlow = clamp(out.dreadSlow, 0, U.MaxDreadSlow)
	out.watcherSlow = clamp(out.watcherSlow, 0, U.MaxWatcherSlow)
	out.keepOnCaught = clamp(out.keepOnCaught, 0, U.MaxKeepOnCaught)
	return out
end

-- Normalise whatever came back out of the DataStore. Unknown ids are dropped, levels are
-- floored and clamped to their cap, anything non-numeric or below 1 disappears.
function Upgrades.sanitize(cfg: any, raw: any): Levels
	local out: Levels = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, e in cfg.Upgrades.Catalog do
		local v = raw[e.id]
		if type(v) == "number" then
			local lv = math.floor(v)
			if lv >= 1 then
				out[e.id] = math.min(lv, e.max)
			end
		end
	end
	return out
end

return Upgrades
