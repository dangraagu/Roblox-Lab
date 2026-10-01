--!strict
-- Economy.luau — pay, the perk ladder, the saved profile and run settlement. PURE.
--
-- The one rule that everything else leans on: a run is paid EXACTLY ONCE. `openRun` is set when a
-- run starts, updated at every elevator powering (the checkpoint), and cleared by `settle` in the
-- same step that pays it. The server writes the whole profile as one record, so the store can hold
-- either the paid profile or the unpaid checkpoint, never both (DESIGN.md §7.1).
--
-- Payouts are integer arithmetic on an integer percent. `0.55 * 100` is 55.00000000000001 in a
-- double and `floor` of a value a hair under an integer loses a whole point of Essence; percent
-- integers make that impossible.
--
-- Perk and profile keys are STRINGS only. JSON round-trips sparse integer keys into strings
-- (checklist), so `sanitize` rebuilds the perk table from Config's own ids and drops anything else.
--
-- Requires nothing.

local Economy = {}

--============================================================================ pay

function Economy.floorPay(cfg: any, k: number): number
	return cfg.Economy.PayBase + cfg.Economy.PayPerSublevel * (k - 1)
end

function Economy.cumulativePay(cfg: any, K: number): number
	local total = 0
	for k = 1, K do
		total += Economy.floorPay(cfg, k)
	end
	return total
end

-- floor(runEssence * keepPercent / 100), exactly.
function Economy.deathPayout(runEssence: number, keepPercent: number): number
	local scaled = math.floor(runEssence) * math.floor(keepPercent)
	return (scaled - scaled % 100) / 100
end

--============================================================================ perks

local function rankOf(cfg: any, perks: any, id: string): number
	local p = cfg.Perks.Catalog[id]
	local r = perks and perks[id]
	if type(r) ~= "number" or r ~= r then return 0 end
	return math.clamp(math.floor(r), 0, p.max)
end

-- The price of the NEXT rank for a player currently at `rank`; nil when maxed or unknown.
function Economy.price(cfg: any, perkId: any, rank: number): number?
	local p = type(perkId) == "string" and cfg.Perks.Catalog[perkId] or nil
	if p == nil or type(rank) ~= "number" or rank < 0 or rank >= p.max then
		return nil
	end
	return p.prices[math.floor(rank) + 1]
end

-- What a run is played with. Snapshotted when the run starts, so buying mid-run is impossible
-- and pointless.
function Economy.effects(cfg: any, perks: any): any
	local C = cfg.Perks.Catalog
	return {
		batteryCap = cfg.Battery.CapSeconds + C.deepCell.per * rankOf(cfg, perks, "deepCell"),
		grace = cfg.Exposure.GraceSeconds + C.nightEyes.per * rankOf(cfg, perks, "nightEyes"),
		staminaCap = cfg.Movement.StaminaSeconds + C.marathon.per * rankOf(cfg, perks, "marathon"),
		keepPercent = cfg.Economy.DeathKeepPercent + C.soulAnchor.per * rankOf(cfg, perks, "soulAnchor"),
		secondWinds = C.secondWind.per * rankOf(cfg, perks, "secondWind"),
	}
end

--============================================================================ the profile

function Economy.newProfile(cfg: any): any
	local perks = {}
	for _, id in cfg.Perks.Order do
		perks[id] = 0
	end
	return {
		v = cfg.Data.Version,
		essence = 0,
		essenceEarned = 0,
		perks = perks,
		bestSublevel = 0,
		bestAt = 0, -- unix second the record was set: the TOP DIVERS board's tiebreak (earliest first)
		boardBest = 0, -- the record last written to the board (it is written only when it improves)
		runs = 0,
		extractions = 0,
		openRun = nil,
	}
end

local function count(v: any): number?
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return math.max(0, math.floor(v))
end

-- Whatever came out of the DataStore (or nothing) -> a profile this game can trust.
function Economy.sanitize(cfg: any, raw: any): any
	local p = Economy.newProfile(cfg)
	if type(raw) ~= "table" then
		return p
	end
	for _, field in { "essence", "essenceEarned", "bestSublevel", "bestAt", "boardBest", "runs", "extractions" } do
		local v = count(raw[field])
		if v ~= nil then p[field] = v end
	end
	if type(raw.perks) == "table" then
		for _, id in cfg.Perks.Order do
			p.perks[id] = rankOf(cfg, raw.perks, id)
		end
	end
	local r = raw.openRun
	if type(r) == "table" and type(r.id) == "string" and count(r.runEssence) ~= nil
		and count(r.sublevel) ~= nil and count(r.keepPercent) ~= nil then
		p.openRun = {
			id = r.id,
			sublevel = count(r.sublevel),
			runEssence = count(r.runEssence),
			keepPercent = math.clamp(count(r.keepPercent) :: number, 0, 100),
		}
	end
	return p
end

function Economy.snapshot(p: any): any
	local function copy(v: any): any
		if type(v) ~= "table" then return v end
		local out = {}
		for k, x in v do out[k] = copy(x) end
		return out
	end
	return copy(p)
end

-- Put a snapshot's contents back into the SAME table (the server holds references to it).
function Economy.restore(p: any, snap: any)
	for k in table.clone(p) do
		p[k] = nil
	end
	for k, v in Economy.snapshot(snap) do
		p[k] = v
	end
end

--============================================================================ runs

function Economy.beginRun(p: any, id: string, keepPercent: number)
	p.openRun = { id = id, sublevel = 0, runEssence = 0, keepPercent = keepPercent }
end

-- An elevator powered on sublevel k: pay into the run, write the checkpoint fields, raise the best.
-- `now` (unix seconds) stamps a NEW record's reach time, the board's tiebreak; the same depth again keeps the first.
function Economy.power(cfg: any, p: any, k: number, now: number?): number
	local r = p.openRun
	if r == nil then return 0 end
	local pay = Economy.floorPay(cfg, k)
	r.runEssence += pay
	r.sublevel = k
	if k > p.bestSublevel then
		p.bestSublevel = k
		p.bestAt = math.max(0, math.floor(tonumber(now) or 0))
	end
	return pay
end

-- A record saved before the board existed has no reach time. It is stamped once, with the session it came back in
-- (it then ranks behind everyone who reached the same depth before). Returns whether it stamped.
function Economy.stampBest(p: any, now: number): boolean
	if p.bestSublevel > 0 and p.bestAt <= 0 then
		p.bestAt = math.max(0, math.floor(now))
		return true
	end
	return false
end

-- Pay the open run and close it. Idempotent: with no open run it pays 0 and changes nothing.
-- reason: "extract" pays everything; "dark", "reset", "left", "shutdown" and "load" (a checkpoint
-- found on the next join) pay the death share.
function Economy.settle(p: any, reason: string): number
	local r = p.openRun
	if r == nil then
		return 0
	end
	local payout = if reason == "extract" then r.runEssence else Economy.deathPayout(r.runEssence, r.keepPercent)
	p.openRun = nil
	p.essence += payout
	p.essenceEarned += payout
	p.runs += 1
	if reason == "extract" then
		p.extractions += 1
	end
	return payout
end

--============================================================================ purchases

function Economy.canBuy(cfg: any, p: any, perkId: any): (boolean, string?)
	if type(perkId) ~= "string" or cfg.Perks.Catalog[perkId] == nil then
		return false, "That perk does not exist."
	end
	if p.openRun ~= nil then
		return false, "Finish your run first."
	end
	local perk = cfg.Perks.Catalog[perkId]
	local rank = rankOf(cfg, p.perks, perkId)
	local price = Economy.price(cfg, perkId, rank)
	if price == nil then
		return false, perk.name .. " is already maxed."
	end
	if p.essence < price then
		return false, string.format("%s costs %d Essence — you have %d.", perk.name, price, tonumber(p.essence) or 0)
	end
	return true, nil
end

-- Applies a purchase in memory and returns the price, or nil if `canBuy` refuses. The server
-- snapshots before calling this and restores if the flush does not persist.
function Economy.buy(cfg: any, p: any, perkId: any): number?
	local ok = Economy.canBuy(cfg, p, perkId)
	if not ok then
		return nil
	end
	local rank = rankOf(cfg, p.perks, perkId)
	local price = Economy.price(cfg, perkId, rank) :: number
	p.essence -= price
	p.perks[perkId] = rank + 1
	return price
end

return Economy
