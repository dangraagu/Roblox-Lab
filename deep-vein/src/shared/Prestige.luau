--!strict
-- Prestige.luau — the rebirth loop, pure. No Roblox dependency; cfg arrives as an argument.
--
-- UNITS: `depthLayer` and `bestLayer` are counted in LAYERS, not studs. Studs are display only
-- (Mine.depthStuds converts). Two units for one quantity is how a HUD ends up six times off.
--
-- Rebirth is the only irreversible action in Deep Vein, so `apply` is written so that it either
-- does the whole thing or does nothing at all: every check happens before the first assignment.
--
-- What it wipes: cash, the haul, all three upgrade tracks, and this run's depth (the cave is
-- regenerated from a new seed, so an old depth number would be about a mine that no longer
-- exists). What it KEEPS: `rebirths`, `totalCash` and `bestLayer` — the last two are what the
-- leaderboard and the lifetime figures are built on, and a reward that deletes your ranking is
-- not a reward.

local Prestige = {}

-- Cash needed to buy the NEXT rebirth when you already have `rebirths`.
--
-- QUOTED IN ORE, NOT IN CASH. Every sale a player makes is already multiplied by
-- `Prestige.multiplier`, so a price that ignores that multiplier is measured in a unit that
-- shrinks by 0.8 of itself every rebirth — the reward would be paying for its own successor. The
-- multiplier factor below cancels it out, which leaves `RequirementGrowth` free to track the one
-- thing that actually limits a player: how much ore their cave contains. See the note in
-- Config.Prestige for the measurement, and Prestige.spec for the assertion that keeps the two in
-- step.
function Prestige.requirement(cfg: any, rebirths: number): number
	local pc = cfg.Prestige
	local r = math.max(0, rebirths or 0)
	return math.floor(pc.BaseRequirement * Prestige.multiplier(cfg, r) * (pc.RequirementGrowth ^ r))
end

-- Permanent cash multiplier granted by `rebirths` rebirths. Applied to the whole haul at sale.
function Prestige.multiplier(cfg: any, rebirths: number): number
	return 1 + math.max(0, rebirths or 0) * cfg.Prestige.MultiplierPerRebirth
end

-- 0..1, for the HUD bar. A maxed miner reads full rather than dividing by a requirement they
-- can never meet.
function Prestige.progress(profile: any, cfg: any): number
	if (profile.rebirths or 0) >= cfg.Prestige.MaxRebirths then return 1 end
	local need = Prestige.requirement(cfg, profile.rebirths or 0)
	if need <= 0 then return 1 end
	return math.min(1, (profile.cash or 0) / need)
end

-- reasons: "ok" | "max" | "poor"
function Prestige.canRebirth(profile: any, cfg: any): (boolean, string)
	local r = profile.rebirths or 0
	if r >= cfg.Prestige.MaxRebirths then return false, "max" end
	if (profile.cash or 0) < Prestige.requirement(cfg, r) then return false, "poor" end
	return true, "ok"
end

-- Every check first, every mutation after: a refused rebirth leaves the profile byte-identical.
function Prestige.apply(profile: any, cfg: any): (boolean, string)
	local ok, reason = Prestige.canRebirth(profile, cfg)
	if not ok then return false, reason end

	profile.rebirths = (profile.rebirths or 0) + 1
	profile.cash = cfg.Economy.StartCash
	profile.inventory = {}
	profile.pickTier = 1
	profile.backpackLevel = 0
	profile.lampLevel = 0
	profile.depthLayer = 0
	-- totalCash and bestLayer are deliberately NOT touched.
	return true, "ok"
end

return Prestige
