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

-- rebirthHighlighted: when the HUD makes REBIRTH stand out. Rebirth sends the climber back to the pad and,
-- with the jump capped and every tier reachable without it, never shortens the climb, so a HUD that lights
-- it at 10, 18, 26, ... walks a normal player away from space (46-227 min instead of 34).
-- Review round 1 (finding 2) dimmed every rebirth after the first. Review round 2 (finding 2) put it back to
-- every rebirth lit, as before the sky, because that changed an existing mechanic's HUD without the owner.
-- OWNER DECISION 2026-09-24 (Gustav: "ca 38 min er bra"): first only. The DEFAULT now lights the first
-- rebirth, then again once the best tier reaches the last sky band. "Every rebirth lit" stays available
-- as Config.Rebirth.HighlightFirstRebirths = math.huge; its behaviour is pinned below with that setting.
do
	truthy(type(rb.HighlightFirstRebirths) == "number" and type(rb.HighlightAgainAtBestTier) == "number",
		"Config.Rebirth says which rebirths the HUD highlights")
	eq(rb.HighlightFirstRebirths, 1, "owner decision 2026-09-24: by default only the first rebirth is lit")

	local everyLit = table.clone(rb)
	everyLit.HighlightFirstRebirths = math.huge
	local every, firstMismatch = true, nil
	for rebirths = 0, 12 do
		for tier = 0, 300 do
			if P.rebirthHighlighted(tier, tier, rebirths, everyLit) ~= P.canRebirth(tier, rebirths, everyLit) then
				every = false
				firstMismatch = firstMismatch or string.format("tier %d, %d rebirths", tier, rebirths)
			end
		end
	end
	truthy(every, "every-lit option: the HUD lights REBIRTH exactly when the server allows one, as before the sky"
		.. (if firstMismatch then "; differs at " .. firstMismatch else ""))

	local again = rb.HighlightAgainAtBestTier
	eq(P.rebirthHighlighted(9, 9, 0, rb), false, "default: not highlighted when rebirth is not possible")
	eq(P.rebirthHighlighted(10, 10, 0, rb), true, "default: the first rebirth is highlighted the moment it is possible")
	eq(P.rebirthHighlighted(18, 30, 1, rb), false, "default: a later rebirth is possible but NOT highlighted on the way to space")
	eq(P.rebirthHighlighted(26, 90, 1, rb), false, "default: nor after reaching space, on the way to the galaxy")
	eq(P.rebirthHighlighted(again, again, 1, rb), true, "default: highlighted again once the best tier reaches the last band")
	eq(P.rebirthHighlighted(17, again + 5, 1, rb), false, "default: and even then only when it is actually possible")
	eq(P.rebirthHighlighted(40, again + 5, 3, rb), true, "default: every later rebirth past the galaxy is highlighted")
	eq(again, Config.Env.Bands[#Config.Env.Bands].from, "HighlightAgainAtBestTier follows the last sky band")
end

--======================================================================= the climb guard (2026-09-30)
-- docs/complete-game-standard.md §3: the board ranks a server-measured metric a script cannot inflate. The
-- server credits a platform only when the root is at it and the rise since the last credit is physically
-- possible. Physics: a jump of height h reaches h after sqrt(2h/g) s, so no chain of jumps rises faster than
-- sqrt(g*h/2) studs per second. The guard is a bucket of BurstJumps * h studs that refills at that rate.
do
	local gc = Config.Guard
	local g = Config.Pacing.Gravity
	truthy(type(gc) == "table" and gc.Enabled == true, "Config.Guard exists and is on")
	approx(P.riseRate(60, 196.2), math.sqrt(196.2 * 60 / 2), "riseRate = sqrt(g*h/2)")

	-- a teleport past the buffer is refused, and the refusal changes nothing it should not
	local gd = P.newGuard(8, 0, 7.2, gc)
	eq(P.allowRise(gd, 8 + gc.BurstJumps * 7.2 + 1, 0, 7.2, g, gc), false, "a fresh climber cannot be credited 1 stud past the buffer at once")
	eq(gd.y, 8, "a refusal leaves the last credited height alone")
	eq(P.allowRise(gd, 8 + gc.BurstJumps * 7.2 - 1, 0, 7.2, g, gc), true, "but inside the buffer at once is fine (lag burst)")
	eq(gd.y, 8 + gc.BurstJumps * 7.2 - 1, "a credit moves the last credited height")
	eq(P.allowRise(gd, gd.y + 2, 0, 7.2, g, gc), false, "the buffer is spent: 2 more studs in the same instant are refused")
	eq(P.allowRise(gd, gd.y + 2, 2 / P.riseRate(7.2, g) + 1e-6, 7.2, g, gc), true, "and allowed once it has refilled 2 studs")
	eq(P.allowRise(gd, gd.y - 50, 1e6, 7.2, g, gc), true, "a lower height costs nothing")

	-- every physically possible climb is credited, at every jump height and step, jumping back to back with
	-- no pause at all (airtime only, the fastest a human can go), 2000 jumps each
	local worstRefusals, worstCase = 0, nil
	for _, h in { 7.2, 10, 20, 35, 50, 60 } do
		for _, frac in { 0.1, 0.35, 0.7, 0.9, 1.0 } do
			local s = h * frac
			local air = math.sqrt(2 * h / g) + math.sqrt(2 * math.max(h - s, 0) / g)
			local gd2 = P.newGuard(0, 0, h, gc)
			local y, t, refused = 0, 0, 0
			for _ = 1, 2000 do
				t += air
				y += s
				if not P.allowRise(gd2, y, t, h, g, gc) then refused += 1; y = gd2.y end
			end
			if refused > worstRefusals then worstRefusals, worstCase = refused, string.format("h %.1f step %.1f", h, s) end
		end
	end
	eq(worstRefusals, 0, "no physically possible back-to-back climb is ever refused (h 7.2-60, steps 10-100 % of h)"
		.. (if worstCase then "; worst " .. worstCase else ""))

	-- lag: up to BurstJumps full-height platforms arrive in one burst after the time they took; all credited
	do
		local h = 60
		local air = math.sqrt(2 * h / g)
		local gd3 = P.newGuard(0, 0, h, gc)
		local ok = true
		local y = 0
		for _ = 1, gc.BurstJumps do
			y += h
			if not P.allowRise(gd3, y, gc.BurstJumps * air, h, g, gc) then ok = false end
		end
		truthy(ok, "a lag burst of " .. gc.BurstJumps .. " full-height jumps, delivered at once, is all credited")
	end

	-- a script that climbs twice as fast as physics allows, for five minutes: credited no faster than a
	-- perfect jumper plus the buffer, and most of its touches are refused
	do
		local h = 60
		local rate = P.riseRate(h, g)
		local gd4 = P.newGuard(0, 0, h, gc)
		local credited, refused, t = 0, 0, 0
		for _ = 1, 3000 do
			t += 0.1
			local want = gd4.y + 2 * rate * 0.1 * 5 -- tries to skip ahead five steps' worth each time
			if P.allowRise(gd4, want, t, h, g, gc) then credited += 1 else refused += 1 end
		end
		truthy(gd4.y <= gc.BurstJumps * h + gc.RateFactor * rate * t + 1e-6,
			string.format("a script rising 10x too fast gets at most buffer + rate * t (%.0f of %.0f studs)", gd4.y,
				gc.BurstJumps * h + gc.RateFactor * rate * t))
		truthy(refused > credited, "and most of its touches are refused (" .. refused .. " refused, " .. credited .. " credited)")
	end

	-- where the root must be: within ReachStuds of the platform's box
	local r = gc.ReachStuds
	eq(P.nearBox(0, 0, 0, 0, 0, 0, 4, 0.5, 4, r), true, "a root inside the platform box is at it")
	eq(P.nearBox(0, 3.5, 0, 0, 0, 0, 4, 0.5, 4, r), true, "a root standing on it (3.5 above the centre) is at it")
	eq(P.nearBox(4 + r - 0.01, 0, 0, 0, 0, 0, 4, 0.5, 4, r), true, "just inside the reach, beside it")
	eq(P.nearBox(4 + r + 0.01, 0, 0, 0, 0, 0, 4, 0.5, 4, r), false, "just outside the reach, beside it")
	eq(P.nearBox(0, 0.5 + r + 0.01, 0, 0, 0, 0, 4, 0.5, 4, r), false, "just outside the reach, above it")
	eq(P.nearBox(4 + r * 0.8, 0.5 + r * 0.8, 0, 0, 0, 0, 4, 0.5, 4, r), false, "outside diagonally (distance, not per axis)")
	eq(P.nearBox(0, 8 - 1000, 0, 0, 8, 0, 4, 0.5, 4, r), false, "a script touching from the ground far below is not at it")
end

print(string.format("Progression: %d passed, %d failed", passed, failed))
assert(failed == 0, "Progression tests failed")
