--!strict
-- Prestige.luau — the rebirth loop, pure. No Roblox dependency; cfg and Ore arrive as arguments.
--
-- UNITS: `depthLayer` and `bestLayer` are counted in LAYERS, not studs. Studs are display only
-- (Mine.depthStuds converts). Two units for one quantity is how a HUD ends up six times off.
--
-- Rebirth is the only irreversible action in Deep Vein, so `apply` is written so that it either
-- does the whole thing or does nothing at all: every check happens before the first assignment.
--
-- What it wipes: cash, this run's EARNINGS, the haul, all three upgrade tracks, this run's depth,
-- and the record of which cells this run's cave has had dug out of it. What it KEEPS: `rebirths`,
-- `totalCash` and `bestLayer` — the last two are what the leaderboard and the lifetime figures
-- are built on, and a reward that deletes your ranking is not a reward.

local Prestige = {}

-- WHAT THE WHOLE SHAFT IS WORTH, ANALYTICALLY: no seed, no noise, no cave — just the ore table
-- integrated over every layer the rebirth-`r` wall exposes, times the diggable cells in a layer.
-- Two decimal places of this number are meaningless (the actual cave is carved by noise and about
-- 71% of its cells are rock); what matters is that it is EXACTLY proportional to what a real
-- rebirth-`r` shaft holds, at every r, which is what makes the price below track the world.
--
-- Cost: MaxRebirths * LayersPerRebirth * MaxOre multiply-adds at the very deepest wall — 1560
-- floating point operations — so it is cheap enough to call from a state push.
function Prestige.shaftOre(cfg: any, Ore: any, rebirths: number): number
	local m = cfg.Mine
	local inner = m.GridW - 2 -- the bedrock ring is not diggable
	-- Mine.maxLayer's arithmetic, deliberately duplicated rather than importing Mine (this module
	-- depends on Ore alone). Prestige.spec asserts the two agree at every rebirth count.
	local maxLayer = m.BaseMaxLayer + math.max(0, rebirths or 0) * m.LayersPerRebirth
	local perLayer = 0
	for y = 1, maxLayer do
		for tier = 1, cfg.MaxOre do
			perLayer += Ore.weight(cfg, tier, y) * Ore.value(cfg, tier) * Ore.yieldOf(cfg, tier)
		end
	end
	return inner * inner * perLayer
end

-- Cash that must have been EARNED this run to buy the NEXT rebirth, when you already have
-- `rebirths`.
--
-- QUOTED AS A FRACTION OF YOUR OWN CAVE. The price is charged against a finite shaft — a player's
-- only income is selling ore out of it, and once mined cells stop growing back there is no second
-- helping — so the only defensible unit for the price is "how much of this cave do I have to
-- mine". A hand-tuned geometric curve cannot hold that: the shipped one asked more than the whole
-- cave at every level, its replacement asked 3.5x at rebirth 0 and then 27x at rebirth 6, because
-- the world's own value curve is not a geometric (it triples between the first two rebirths and
-- then flattens as the ore weights saturate). Measured against the real seeded caves, this form
-- holds every one of the 25 levels inside 2.9x-3.6x, and Prestige.spec fails if any of them
-- leaves the band.
--
-- The rebirth multiplier is applied on top because every sale a player makes is already
-- multiplied by it: a price that ignored it would shrink by 0.8 of itself every rebirth, and the
-- reward would be paying for its own successor.
function Prestige.requirement(cfg: any, Ore: any, rebirths: number): number
	local r = math.max(0, rebirths or 0)
	return math.floor(cfg.Prestige.PriceFraction * Prestige.shaftOre(cfg, Ore, r)
		* Prestige.multiplier(cfg, r))
end

-- Permanent cash multiplier granted by `rebirths` rebirths. Applied to the whole haul at sale.
function Prestige.multiplier(cfg: any, rebirths: number): number
	return 1 + math.max(0, rebirths or 0) * cfg.Prestige.MultiplierPerRebirth
end

-- WHAT THE GATE IS MEASURED ON, AND WHY IT IS NOT `cash`.
--
-- `runEarned` is every cash a sale has paid this run. It only ever goes up, and spending does not
-- move it. A gate on the wallet instead of on earnings is a gate a player can spend themselves
-- out of, permanently: the shop offers $214,756 of upgrades against a rebirth-0 shaft holding
-- about $20,000 of ore, every purchase is affordable at the moment it is offered, nothing warns
-- that it competes with the rebirth, and the cave does not refill. The exact reachable sequence
-- (pickaxe t2, t3, then backpack L1..L8) ends at $2,172 in hand against a $3,500 price with an
-- empty cave and no way back — and rebirth wipes those upgrades anyway. Earnings cannot be spent,
-- so the same sequence now leaves the rebirth exactly as available as it was before the shopping.
function Prestige.earned(profile: any): number
	return math.max(0, profile.runEarned or 0)
end

-- 0..1, for the HUD bar. A maxed miner reads full rather than dividing by a requirement they
-- can never meet.
function Prestige.progress(profile: any, cfg: any, Ore: any): number
	if (profile.rebirths or 0) >= cfg.Prestige.MaxRebirths then return 1 end
	local need = Prestige.requirement(cfg, Ore, profile.rebirths or 0)
	if need <= 0 then return 1 end
	return math.min(1, Prestige.earned(profile) / need)
end

-- reasons: "ok" | "max" | "poor"
function Prestige.canRebirth(profile: any, cfg: any, Ore: any): (boolean, string)
	local r = profile.rebirths or 0
	if r >= cfg.Prestige.MaxRebirths then return false, "max" end
	if Prestige.earned(profile) < Prestige.requirement(cfg, Ore, r) then return false, "poor" end
	return true, "ok"
end

-- Every check first, every mutation after: a refused rebirth leaves the profile byte-identical.
function Prestige.apply(profile: any, cfg: any, Ore: any): (boolean, string)
	local ok, reason = Prestige.canRebirth(profile, cfg, Ore)
	if not ok then return false, reason end

	profile.rebirths = (profile.rebirths or 0) + 1
	profile.cash = cfg.Economy.StartCash
	profile.runEarned = 0
	profile.inventory = {}
	profile.pickTier = 1
	profile.backpackLevel = 0
	profile.lampLevel = 0
	profile.depthLayer = 0
	-- The dug-out cells belong to the cave that is being thrown away. Carrying them into the new
	-- one would punch holes in it at coordinates that mean nothing there.
	profile.openedBits = nil
	-- totalCash and bestLayer are deliberately NOT touched.
	return true, "ok"
end

return Prestige
