-- Rene tester for Progression. Kjør: luau tests/Progression.spec.luau
local P = require("../src/shared/Progression")
local Config = require("../src/shared/Config")

local jc = Config.Jump
local tw = Config.Tower
local rb = Config.Rebirth

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, msg)
	if math.abs(a - b) < 1e-6 then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

-- jumpHeight
approx(P.jumpHeight(0, 1, jc), jc.BaseJump, "jumpHeight at jp=0 == BaseJump")
truthy(P.jumpHeight(10, 1, jc) > P.jumpHeight(5, 1, jc), "jumpHeight grows with jp")
truthy(P.jumpHeight(10, 2, jc) > P.jumpHeight(10, 1, jc), "multiplier raises jumpHeight (unsaturated)")
-- ved høy jp metter begge til MaxJumpHeight (fysikk-tak) — forventet, ikke en bug
eq(P.jumpHeight(100, 2, jc), P.jumpHeight(100, 1, jc), "both saturate at MaxJumpHeight")
eq(P.jumpHeight(1e9, 1, jc), jc.MaxJumpHeight, "jumpHeight clamped at MaxJumpHeight")

-- jumpPowerAtTierStart
eq(P.jumpPowerAtTierStart(1, tw), 0, "tier1 start jp = 0")
eq(P.jumpPowerAtTierStart(2, tw), tw.TilesPerTier, "tier2 start jp = TilesPerTier")
eq(P.jumpPowerAtTierStart(3, tw), 2 * tw.TilesPerTier, "tier3 start jp = 2*TilesPerTier")

-- stepHeight monotont ikke-avtakende + clampet
local prevStep = -1
local stepMonotonic, stepClamped = true, true
for t = 1, 3000 do
	local s = P.stepHeight(t, tw)
	if s < prevStep then stepMonotonic = false end
	if s > tw.StepMax + 1e-9 then stepClamped = false end
	prevStep = s
end
truthy(stepMonotonic, "stepHeight non-decreasing")
truthy(stepClamped, "stepHeight <= StepMax")
eq(P.stepHeight(1, tw), tw.StepMin, "stepHeight tier1 = StepMin")

-- gap clampet
truthy(P.gap(100000, tw) <= tw.GapMax + 1e-9, "gap <= GapMax")
eq(P.gap(1, tw), tw.GapMin, "gap tier1 = GapMin")

-- ★ REACHABILITY-INVARIANT: hver etasje klarerbar UTEN rebirth, t=1..2000
local allReachable = true
local firstBad = nil
for t = 1, 2000 do
	if not P.isTierReachable(t, tw, jc) then
		allReachable = false
		if firstBad == nil then firstBad = t end
	end
end
truthy(allReachable, "every tier reachable without rebirth (firstBad=" .. tostring(firstBad) .. ")")

-- Konkret margin-sjekk på et par etasjer
truthy(P.stepHeight(1, tw) <= P.maxSafeStep(1, tw, jc), "tier1 within safe step")
truthy(P.stepHeight(50, tw) <= P.maxSafeStep(50, tw, jc), "tier50 within safe step")

-- hazardCount
eq(P.hazardCount(tw.HazardStartTier - 1, tw), 0, "no hazards before start")
truthy(P.hazardCount(tw.HazardStartTier, tw) >= 1, "hazards at start tier")
truthy(P.hazardCount(100000, tw) <= tw.HazardMax, "hazardCount <= HazardMax")

-- rebirthMultiplier
eq(P.rebirthMultiplier(0, rb), 1, "0 rebirths -> 1x")
eq(P.rebirthMultiplier(1, rb), rb.Multipliers[1], "1 rebirth -> first multiplier")
eq(P.rebirthMultiplier(#rb.Multipliers, rb), rb.Multipliers[#rb.Multipliers], "last table multiplier")
eq(P.rebirthMultiplier(#rb.Multipliers + 1, rb), rb.Multipliers[#rb.Multipliers] * 2, "beyond table doubles last")
truthy(P.rebirthMultiplier(3, rb) > P.rebirthMultiplier(2, rb), "multiplier increasing")

-- rebirthTierRequired + canRebirth
eq(P.rebirthTierRequired(0, rb), rb.FirstTierRequired, "first rebirth req = FirstTierRequired")
eq(P.rebirthTierRequired(1, rb), rb.FirstTierRequired + rb.TierRequiredPerRebirth, "second req grows")
eq(P.canRebirth(rb.FirstTierRequired, 0, rb), true, "can rebirth at exact req")
eq(P.canRebirth(rb.FirstTierRequired - 1, 0, rb), false, "cannot rebirth below req")

print(string.format("Progression: %d passed, %d failed", passed, failed))
assert(failed == 0, "Progression tests failed")
