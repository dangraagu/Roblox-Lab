-- NightModel.luau — test-side model of how long a player takes to FIRST reach a given Day.
-- Used by tests/Pacing.spec.luau. Not shipped (tests/ is not in the Rojo tree).
--
-- Why a model: there is no telemetry yet. The human part of the model is written down in
-- Config.Sky.Pacing.Profiles, and the game part is the game's own roll (Anomaly.chance and
-- Anomaly.poolSize from src/shared/Anomaly.luau, with the real Config), so a retune of either the
-- catalog or the profiles moves the numbers here and the spec tells you where the bands land.
--
-- The model, stated:
--   * a pass takes `passSeconds` (walk the ~80-stud hall at WalkSpeed 16 = 5 s, look, decide);
--   * each pass is anomalous with P = Anomaly.chance(day), drawn from the first
--     Anomaly.poolSize(day) catalog entries, uniformly;
--   * a clean pass is answered right with 1 - falseAlarm; an anomalous one with spotObvious if the
--     anomaly is one of the first `ObviousCount` catalog entries (Config calls those "obvious (Day 1
--     pool)"), else spotSubtle;
--   * a wrong call costs `deathSeconds` (the server's 2.5 s death beat plus reading the toast) and
--     sends the player back to Day 1 (Progression.resolve);
--   * passes are independent. Real players learn, get tired and take breaks; none of that is here.
--
-- Expected time to first stand on Day N, exactly for this model (no simulation): let E(d) be the
-- expected seconds to first reach Day d from a fresh Day 1, and s(d) the chance a pass at Day d is
-- answered right. From the first arrival at d, one pass either succeeds (t) or fails (t + death),
-- after which the player needs E(d) again to get back to d and then another try:
--     X(d) = t + (1 - s(d)) * (death + E(d) + X(d))   =>   X(d) = (t + (1 - s(d)) * (death + E(d))) / s(d)
--     E(d + 1) = E(d) + X(d),  E(1) = 0.
-- `simulate` runs the same model with an Rng so the spec can check the closed form against it.

local NightModel = {}

function NightModel.passSuccess(cfg: any, Anomaly: any, profile: any, day: number): number
	local pA = Anomaly.chance(cfg, day)
	local pool = Anomaly.poolSize(cfg, day)
	local obvious = math.min(pool, profile.ObviousCount or cfg.Anomaly.StartPool)
	local subtle = pool - obvious
	local spot = (obvious * profile.spotObvious + subtle * profile.spotSubtle) / pool
	return (1 - pA) * (1 - profile.falseAlarm) + pA * spot
end

-- Expected seconds to first reach Day `target` (target >= 1) from a fresh Day 1.
function NightModel.expectedSeconds(cfg: any, Anomaly: any, profile: any, target: number): number
	local E = 0
	for d = 1, target - 1 do
		local s = NightModel.passSuccess(cfg, Anomaly, profile, d)
		local X = (profile.passSeconds + (1 - s) * (profile.deathSeconds + E)) / s
		E += X
	end
	return E
end

function NightModel.expectedMinutes(cfg: any, Anomaly: any, profile: any, target: number): number
	return NightModel.expectedSeconds(cfg, Anomaly, profile, target) / 60
end

-- Monte Carlo of the same model: mean seconds to first reach `target` over `runs` players.
-- `rng` is the game's Rng (rng:next() in [0, 1)).
function NightModel.simulate(cfg: any, Anomaly: any, profile: any, target: number, runs: number, rng: any): number
	local total = 0
	for _ = 1, runs do
		local day, t = 1, 0
		while day < target do
			t += profile.passSeconds
			if rng:next() < NightModel.passSuccess(cfg, Anomaly, profile, day) then
				day += 1
			else
				t += profile.deathSeconds
				day = 1
			end
		end
		total += t
	end
	return total / runs
end

return NightModel
