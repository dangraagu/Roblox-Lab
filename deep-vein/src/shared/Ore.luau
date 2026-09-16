--!strict
-- Ore.luau — the rarity table of Deep Vein, as a PURE function of depth.
--
-- The whole question this module answers is: this block is at layer `y`, the generator drew the
-- uniform number `u` for it — which ore is inside? Nothing here touches a Roblox global, takes a
-- config table as an argument, and is therefore fully unit-testable from the luau CLI.
--
-- Modelled on grow-a-crystal's Rarity: one small table of odds, one function that turns a roll
-- into a tier, and nothing else knows the numbers. The difference is that the odds here are
-- keyed to DEPTH rather than to a luck stat, which is what makes "copper up top, obsidian deep"
-- a rule instead of a comment.
--
-- Tier 0 is plain stone: real, minable, worth nothing. Tiers 1..MaxOre are the ores.

local Ore = {}

-- Chance that a block on `layer` holds tier `tier`. Zero above the tier's MinLayer, then it
-- drifts by DepthGain per layer and is clamped into [0, MaxWeight]. DepthGain may be negative
-- (copper thins out), which is what makes a deep biome read as DIFFERENT and not merely richer.
function Ore.weight(cfg: any, tier: number, layer: number): number
	local oc = cfg.Ores
	local minLayer = oc.MinLayer[tier]
	if minLayer == nil then return 0 end -- tier 0 (stone) and anything out of range
	if layer < minLayer then return 0 end
	local w = oc.BaseWeight[tier] + oc.DepthGain[tier] * (layer - minLayer)
	if w < 0 then return 0 end
	local mx = oc.MaxWeight[tier]
	if mx ~= nil and w > mx then return mx end
	return w
end

-- Turn one uniform draw in [0, 1) into a tier. The bands are laid out RAREST FIRST, so
-- obsidian owns [0, w5), diamond the next slice, and plain stone whatever is left over. Reading
-- it in this order means adding a rarer sixth ore later shifts nobody else's band start.
function Ore.tierAt(cfg: any, layer: number, u: number): number
	local acc = 0
	for tier = cfg.MaxOre, 1, -1 do
		acc += Ore.weight(cfg, tier, layer)
		if u < acc then return tier end
	end
	return 0
end

function Ore.isOre(cfg: any, tier: number): boolean
	return type(tier) == "number" and tier >= 1 and tier <= cfg.MaxOre
end

-- Every lookup below falls back rather than returning nil: a tier that somehow escapes the
-- table must produce a worthless grey rock, not a crash in the middle of a swing.
function Ore.name(cfg: any, tier: number): string
	return cfg.Ores.Names[tier] or cfg.Ores.Names[0]
end

function Ore.value(cfg: any, tier: number): number
	return cfg.Ores.Value[tier] or 0
end

function Ore.hardness(cfg: any, tier: number): number
	return cfg.Ores.Hardness[tier] or cfg.Ores.Hardness[0]
end

function Ore.yieldOf(cfg: any, tier: number): number
	return cfg.Ores.Yield[tier] or 0
end

function Ore.color(cfg: any, tier: number): { number }
	return cfg.Ores.Color[tier] or cfg.Ores.Color[0]
end

return Ore
