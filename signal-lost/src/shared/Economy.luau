--!strict
-- Economy.luau — salvage, the splice, leaving a sector, the upgrade ladder and the saved profile
-- (DESIGN.md §2.7, §9, §11). PURE, requires nothing.
--
-- The rule everything leans on: an unspliced sector is paid EXACTLY ONCE. `open` is set when a sector attempt
-- begins and cleared by `splice` or `settle` in the same step that pays it; the server writes the whole
-- profile as one record, so the store holds either the paid profile or the unpaid open sector, never both.
-- Every way out of an unspliced sector (blackout, return, reset, left, shutdown, crashed) banks
-- floor(carried / 2) in integer arithmetic.
--
-- Keys are STRINGS only. JSON round-trips sparse integer keys into strings (the checklist trap), so
-- `sanitize` rebuilds the upgrade table from Config's own ids and drops anything else.

local Economy = {}

--============================================================================ pay

function Economy.value(cfg: any, k: number): number
	return cfg.Economy.ValueBase + cfg.Economy.ValuePerSector * (k - 1)
end

function Economy.bonus(cfg: any, k: number): number
	return cfg.Economy.BonusBase + cfg.Economy.BonusPerSector * (k - 1)
end

-- floor(carried x KeepNumerator / KeepDenominator), exactly.
function Economy.keep(cfg: any, carried: number): number
	local scaled = math.floor(carried) * cfg.Economy.KeepNumerator
	return (scaled - scaled % cfg.Economy.KeepDenominator) / cfg.Economy.KeepDenominator
end

--============================================================================ upgrades

local function rankOf(cfg: any, up: any, id: string): number
	local u = cfg.Upgrades.Catalog[id]
	local r = up and up[id]
	if type(r) ~= "number" or r ~= r then return 0 end
	return math.clamp(math.floor(r), 0, u.max)
end
Economy.rankOf = rankOf

-- The price of the NEXT rank for a player at `rank`; nil when maxed or unknown.
function Economy.price(cfg: any, id: any, rank: number): number?
	local u = if type(id) == "string" then cfg.Upgrades.Catalog[id] else nil
	if u == nil or type(rank) ~= "number" or rank < 0 or rank >= u.max then
		return nil
	end
	return u.prices[math.floor(rank) + 1]
end

-- What a sector is played with.
function Economy.effects(cfg: any, up: any): any
	local C = cfg.Upgrades.Catalog
	return {
		tank = cfg.Air.TankBase + C.tank.per * rankOf(cfg, up, "tank"),
		vacSpeed = cfg.Move.VacWalkSpeed + C.boots.per * rankOf(cfg, up, "boots"),
	}
end

-- The HUD's RECOMMENDED tag: the cheapest next rank, ties to Config.Upgrades.Recommended (the Air Tank buys
-- the most survival per rank, M5). nil when everything is maxed.
function Economy.recommended(cfg: any, p: any): string?
	local best, bestPrice = nil, math.huge
	for _, id in cfg.Upgrades.Order do
		local price = Economy.price(cfg, id, rankOf(cfg, p.up, id))
		if price and (price < bestPrice or (price == bestPrice and id == cfg.Upgrades.Recommended)) then
			best, bestPrice = id, price
		end
	end
	return best
end

--============================================================================ the profile

function Economy.newProfile(cfg: any): any
	local up = {}
	for _, id in cfg.Upgrades.Order do up[id] = 0 end
	return {
		v = cfg.Data.Version,
		salvage = 0,
		salvageEarned = 0,
		best = 0,
		bestAt = 0,
		arrayAt = nil,
		up = up,
		blackouts = 0,
		attempts = 0,
		open = nil,
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
	for _, field in { "salvage", "salvageEarned", "best", "bestAt", "blackouts", "attempts" } do
		local v = count(raw[field])
		if v ~= nil then p[field] = v end
	end
	local at = count(raw.arrayAt)
	if at ~= nil and at > 0 then p.arrayAt = at end
	if type(raw.up) == "table" then
		for _, id in cfg.Upgrades.Order do
			p.up[id] = rankOf(cfg, raw.up, id)
		end
	end
	local o = raw.open
	if type(o) == "table" and type(o.id) == "string" and count(o.k) ~= nil and count(o.carried) ~= nil then
		p.open = { id = o.id, k = count(o.k), carried = count(o.carried) }
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

--============================================================================ sectors

function Economy.beginSector(p: any, id: string, k: number)
	p.open = { id = id, k = k, carried = 0 }
	p.attempts += 1
end

-- A salvage piece picked up in the open sector: carried, not banked.
function Economy.carry(cfg: any, p: any, k: number): number
	local o = p.open
	if o == nil then return 0 end
	local v = Economy.value(cfg, k)
	o.carried += v
	return v
end

-- The relay spliced: bank carried + bonus(k), raise the best (stamped with `now` only when it rises, so a
-- tie goes to whoever reached it first), stamp the Main Array once, close the sector.
function Economy.splice(cfg: any, p: any, k: number, now: number): any
	local o = p.open
	local carried = if o then o.carried else 0
	local bonus = Economy.bonus(cfg, k)
	local paid = carried + bonus
	p.open = nil
	p.salvage += paid
	p.salvageEarned += paid
	local record = k > p.best
	if record then
		p.best = k
		p.bestAt = math.floor(now)
	end
	local array = false
	if k >= cfg.Brag.Sector and p.arrayAt == nil then
		p.arrayAt = math.floor(now)
		array = true
	end
	return { paid = paid, carried = carried, bonus = bonus, record = record, array = array }
end

-- An unspliced sector ends. Idempotent: with no open sector it pays 0 and changes nothing.
-- reason: "blackout" | "return" | "reset" | "left" | "shutdown" | "crashed" — all pay the same.
function Economy.settle(cfg: any, p: any, reason: string): number
	local o = p.open
	if o == nil then
		return 0
	end
	local paid = Economy.keep(cfg, o.carried)
	p.open = nil
	p.salvage += paid
	p.salvageEarned += paid
	if reason == "blackout" then
		p.blackouts += 1
	end
	return paid
end

--============================================================================ purchases

function Economy.canBuy(cfg: any, p: any, id: any): (boolean, string?)
	if type(id) ~= "string" or cfg.Upgrades.Catalog[id] == nil then
		return false, "That upgrade does not exist."
	end
	if p.open ~= nil then
		return false, "Splice this sector's relay first."
	end
	local u = cfg.Upgrades.Catalog[id]
	local rank = rankOf(cfg, p.up, id)
	local price = Economy.price(cfg, id, rank)
	if price == nil then
		return false, u.name .. " is already maxed."
	end
	if p.salvage < price then
		return false, string.format("%s rank %d costs %d salvage — you have %d.", u.name, rank + 1, price, tonumber(p.salvage) or 0)
	end
	return true, nil
end

-- Applies a purchase in memory and returns the price, or nil if canBuy refuses. The server snapshots first
-- and restores if the flush does not persist.
function Economy.buy(cfg: any, p: any, id: any): number?
	if not Economy.canBuy(cfg, p, id) then
		return nil
	end
	local rank = rankOf(cfg, p.up, id)
	local price = Economy.price(cfg, id, rank) :: number
	p.salvage -= price
	p.up[id] = rank + 1
	return price
end

return Economy
