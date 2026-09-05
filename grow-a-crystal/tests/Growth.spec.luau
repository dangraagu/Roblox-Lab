-- Rene tester for Growth (offline timestamp-diff). Kjør: luau tests/Growth.spec.luau
local Growth = require("../src/shared/Growth")
local Config = require("../src/shared/Config")

local gc = Config.Growth

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, msg)
	if math.abs(a - b) < 1e-6 then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

-- growthMult / secondsPerStage
approx(Growth.growthMult(0, Config.Boosters), 1, "growthMult level0")
approx(Growth.growthMult(5, Config.Boosters), 1.5, "growthMult level5")
approx(Growth.secondsPerStage(1, gc, 1), 15, "tier1 perStage")
approx(Growth.secondsPerStage(1, gc, 2), 7.5, "growthMult halves perStage")

-- stagesElapsed (tier1: perStage 15, StageCount 4, total 60)
eq(Growth.stagesElapsed(0, 0, 1, gc, 1), 0, "dt=0 -> 0 stages")
eq(Growth.stagesElapsed(100, 50, 1, gc, 1), 0, "negative dt -> 0")
eq(Growth.stagesElapsed(0, 15, 1, gc, 1), 1, "dt=15 -> 1 stage")
eq(Growth.stagesElapsed(0, 45, 1, gc, 1), 3, "dt=45 -> 3 stages")
eq(Growth.stagesElapsed(0, 60, 1, gc, 1), 4, "dt=60 -> 4 stages (full)")
eq(Growth.stagesElapsed(0, 100000, 1, gc, 1), gc.StageCount, "huge dt clamped to StageCount")

-- isMature boundary
truthy(not Growth.isMature(0, 59, 1, gc, 1), "dt=59 not mature")
truthy(Growth.isMature(0, 60, 1, gc, 1), "dt=60 mature")
truthy(Growth.isMature(0, 30, 1, gc, 2), "growthMult2: mature at dt=30")

-- progress 0..1
approx(Growth.progress(0, 0, 1, gc, 1), 0, "progress dt=0")
approx(Growth.progress(0, 30, 1, gc, 1), 0.5, "progress half")
approx(Growth.progress(0, 120, 1, gc, 1), 1, "progress clamped to 1")

-- secondsToMature
approx(Growth.secondsToMature(0, 0, 1, gc, 1), 60, "toMature at plant = total")
approx(Growth.secondsToMature(0, 60, 1, gc, 1), 0, "toMature at maturity = 0")
approx(Growth.secondsToMature(0, 90, 1, gc, 1), 0, "toMature past maturity = 0")

-- rarer seed grows slower
truthy(Growth.secondsPerStage(6, gc, 1) > Growth.secondsPerStage(1, gc, 1), "mythic seed slower than shard")

print(string.format("Growth: %d passed, %d failed", passed, failed))
assert(failed == 0, "Growth tests failed")
