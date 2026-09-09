--!strict
-- Economy.luau — the shop, the backpack and the sale, as pure functions over a profile table.
-- No Roblox dependency; `Ore` arrives as an argument where a price is needed.
--
-- Every buy function follows the same contract as grow-a-crystal's Economy: validate first,
-- mutate the profile ONLY on success, and return (ok, reason) so the caller can tell the player
-- what went wrong. A silent `return` is how "i cant even place a seed" happened in the last game.
--
-- Profile fields used here:
--   cash, totalCash, inventory ({[oreTier] = count}), pickTier, backpackLevel, lampLevel

local Economy = {}

local function clampTier(cfg: any, tier: number): number
	local maxT = cfg.Economy.Pickaxe.MaxTier
	if type(tier) ~= "number" or tier < 1 then return 1 end
	if tier > maxT then return maxT end
	return math.floor(tier)
end

--============================================================================ the pickaxe

function Economy.swingPower(cfg: any, pickTier: number): number
	return cfg.Economy.Pickaxe.Power[clampTier(cfg, pickTier)]
end

function Economy.pickaxeName(cfg: any, pickTier: number): string
	return cfg.Economy.Pickaxe.Names[clampTier(cfg, pickTier)]
end

-- Cash to go from `tier` to `tier + 1`; nil when there is no next tier.
function Economy.nextPickaxeCost(cfg: any, tier: number): number?
	local pc = cfg.Economy.Pickaxe
	if tier >= pc.MaxTier then return nil end
	return pc.Cost[tier + 1]
end

-- How many swings a block of `hp` takes. Infinity rather than a divide-by-zero when the pick
-- has no power at all: the caller then reports "you cannot break this" instead of crashing.
function Economy.hitsToBreak(hp: number, power: number): number
	if power <= 0 then return math.huge end
	return math.max(1, math.ceil(hp / power))
end

function Economy.buyPickaxe(profile: any, cfg: any): (boolean, string)
	local cost = Economy.nextPickaxeCost(cfg, profile.pickTier)
	if cost == nil then return false, "max" end
	if profile.cash < cost then return false, "poor" end
	profile.cash -= cost
	profile.pickTier += 1
	return true, "ok"
end

--============================================================================ the backpack

function Economy.backpackCapacity(cfg: any, level: number): number
	local bp = cfg.Economy.Backpack
	return bp.BaseCapacity + math.max(0, level or 0) * bp.PerLevel
end

function Economy.backpackCost(cfg: any, level: number): number
	local bp = cfg.Economy.Backpack
	return math.floor(bp.BaseCost * (bp.CostGrowth ^ (level or 0)))
end

function Economy.buyBackpack(profile: any, cfg: any): (boolean, string)
	local bp = cfg.Economy.Backpack
	local level = profile.backpackLevel or 0
	if level >= bp.MaxLevel then return false, "max" end
	local cost = Economy.backpackCost(cfg, level)
	if profile.cash < cost then return false, "poor" end
	profile.cash -= cost
	profile.backpackLevel = level + 1
	return true, "ok"
end

--============================================================================ the lamp

function Economy.lampRadius(cfg: any, level: number): number
	local lp = cfg.Economy.Lamp
	return lp.BaseRadius + math.max(0, level or 0) * lp.PerLevel
end

function Economy.lampCost(cfg: any, level: number): number
	local lp = cfg.Economy.Lamp
	return math.floor(lp.BaseCost * (lp.CostGrowth ^ (level or 0)))
end

function Economy.buyLamp(profile: any, cfg: any): (boolean, string)
	local lp = cfg.Economy.Lamp
	local level = profile.lampLevel or 0
	if level >= lp.MaxLevel then return false, "max" end
	local cost = Economy.lampCost(cfg, level)
	if profile.cash < cost then return false, "poor" end
	profile.cash -= cost
	profile.lampLevel = level + 1
	return true, "ok"
end

--============================================================================ carrying ore

function Economy.carried(profile: any): number
	local n = 0
	-- The type guard is not decoration. This table is round-tripped through a DataStore, and a
	-- non-number that came back from one would otherwise raise inside the arithmetic — in the
	-- middle of a swing, on the server, for every future swing that player makes.
	for _, count in pairs(profile.inventory or {}) do
		if type(count) == "number" then n += count end
	end
	return n
end

function Economy.spaceLeft(profile: any, cfg: any): number
	return math.max(0, Economy.backpackCapacity(cfg, profile.backpackLevel or 0) - Economy.carried(profile))
end

-- Add up to `n` units of `tier`. Returns HOW MANY WERE ACCEPTED, which may be fewer than asked
-- for, or zero. The caller compares the two and tells the player their backpack is full —
-- quietly discarding the difference is exactly the class of silent no-op this repo keeps
-- getting bitten by.
function Economy.addOre(profile: any, cfg: any, tier: number, n: number): number
	if type(tier) ~= "number" or tier < 1 then return 0 end -- tier 0 is plain stone
	if n == nil or n <= 0 then return 0 end
	local room = Economy.spaceLeft(profile, cfg)
	local take = math.min(n, room)
	if take <= 0 then return 0 end
	profile.inventory[tier] = (profile.inventory[tier] or 0) + take
	return take
end

--============================================================================ selling

-- Whole-haul value at the given rebirth multiplier, floored once at the end (per-item flooring
-- would quietly erase the multiplier on cheap ore).
function Economy.haulValue(cfg: any, Ore: any, inventory: any, mult: number): number
	local total = 0
	for tier, count in pairs(inventory or {}) do
		if type(count) == "number" then
			total += Ore.value(cfg, tier) * count
		end
	end
	return math.floor(total * (mult or 1))
end

-- Empty the backpack into the wallet. `totalCash` is the LIFETIME figure and only ever grows:
-- the rebirth threshold and the leaderboard are both built on it, so spending must not move it.
function Economy.sell(profile: any, cfg: any, Ore: any, mult: number): number
	local value = Economy.haulValue(cfg, Ore, profile.inventory, mult)
	profile.inventory = {}
	if value <= 0 then return 0 end
	profile.cash += value
	profile.totalCash = (profile.totalCash or 0) + value
	return value
end

return Economy
