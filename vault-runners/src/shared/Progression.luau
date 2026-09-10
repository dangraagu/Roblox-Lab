--!strict
-- Progression.luau — hvilket hvelv du slipper inn i, og hvor slemt gulvet er. REN logikk.
--
-- Two rules carry this file:
--
--   1. UNLOCKS READ TOTAL GEMS BANKED, NEVER THE WALLET. Spending on a pet must not take a
--      vault away — a shop that can lock content is a shop nobody uses. The server passes
--      `profile.totalBanked`, which only ever goes up.
--
--   2. The threshold is INCLUSIVE. The first cut of this file used `totalBanked > unlockGems`,
--      which reads fine until you notice Bronze unlocks at 0: a brand-new player could not
--      enter the only vault in the game. The spec caught it on the first run.
--
-- Pure: cfg in, plain tables out, no Roblox global anywhere.

local Progression = {}

function Progression.tierCount(cfg: any): number
	return #cfg.Tiers
end

function Progression.tier(cfg: any, index: number): any
	return cfg.Tiers[index]
end

function Progression.isUnlocked(cfg: any, index: number, totalBanked: number): boolean
	local t = cfg.Tiers[index]
	if not t then return false end
	return totalBanked >= t.unlockGems
end

function Progression.unlockedCount(cfg: any, totalBanked: number): number
	local n = 0
	for i = 1, #cfg.Tiers do
		if Progression.isUnlocked(cfg, i, totalBanked) then n += 1 end
	end
	return n
end

function Progression.nextUnlock(cfg: any, totalBanked: number): any
	for i = 1, #cfg.Tiers do
		if not Progression.isUnlocked(cfg, i, totalBanked) then
			local t = cfg.Tiers[i]
			return { index = i, name = t.name, need = t.unlockGems,
				remaining = math.max(0, t.unlockGems - totalBanked) }
		end
	end
	return nil
end

function Progression.difficulty(cfg: any, tierIndex: number, floor: number): any
	local t = cfg.Tiers[tierIndex]
	assert(t ~= nil, "Progression.difficulty: no tier " .. tostring(tierIndex))
	local c = cfg.Curve
	local f = math.max(1, math.floor(floor))

	local cells = math.min(t.cells + math.floor((f - 1) / c.CellsEveryNFloors), c.MaxCells)
	local storeys = math.min(t.storeys + math.floor((f - 1) / c.StoreysEveryNFloors), c.MaxStoreys)
	local gemsPerStorey = math.min(
		t.gemsPerStorey + math.floor((f - 1) / c.GemsEveryNFloors), c.MaxGemsPerStorey)

	-- SLACK, NOT SECONDS. This used to return `collapseSeconds`, shaved 1.5s per floor off a
	-- number typed into the tier. It could not possibly be right: the difficulty curve above
	-- makes the maze BIGGER on exactly the floors this made the timer SHORTER, and nothing
	-- anywhere measured how long the maze took to walk. Silver and Gold were unwinnable on floor
	-- 1 and Bronze died around floor 7.
	--
	-- Now the vault is built first and VaultPath.countdown measures it. What the curve controls
	-- is how much slack over the demand the runner is owed — so a deeper floor is a tighter run
	-- through a maze of the same size, and never an impossible one.
	--
	-- IT DECAYS TOWARD MinSlack AND NEVER ARRIVES. The first cut shed a flat 0.02 a floor down to
	-- a hard 1.5, and since the size caps are also reached by floor 26, Gold floor 26 and Gold
	-- floor 2000 were byte-identical difficulty specs — the whole late game was one floor with
	-- different seeds. A power law has no such floor: there is no depth at which the next floor
	-- is not measurably tighter than this one.
	local k = cfg.Collapse
	local slack = k.MinSlack
		+ (k.Slack - k.MinSlack) * (1 + (f - 1) / k.TightenFloors) ^ (-k.TightenExponent)

	return {
		tier = tierIndex, floor = f,
		cells = cells, storeys = storeys,
		gemsPerStorey = gemsPerStorey, gemValue = t.gemValue,
		gemCount = storeys * gemsPerStorey,
		slack = slack,
	}
end

function Progression.seedFor(cfg: any, tierIndex: number, floor: number): number
	local s = cfg.Seed
	local f = math.max(1, math.floor(floor))
	return cfg.WorldSeed * s.World + tierIndex * s.Tier + f * s.Floor
end

return Progression
