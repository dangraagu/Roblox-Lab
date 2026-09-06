-- Pure tests for Progression (Day/streak rules). Run: luau tests/Progression.spec.luau
local Progression = require("../src/shared/Progression")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local ADV, TB = Progression.ADVANCE, Progression.TURN_BACK
local clean = { clean = true }
local anom = { clean = false, anomalyId = "figure_end" }

-- isCorrect truth table
eq(Progression.isCorrect(ADV, clean), true, "advance on clean = correct")
eq(Progression.isCorrect(ADV, anom), false, "advance on anomaly = wrong")
eq(Progression.isCorrect(TB, anom), true, "turn back on anomaly = correct")
eq(Progression.isCorrect(TB, clean), false, "turn back on clean = wrong")
eq(Progression.isCorrect("garbage", clean), false, "unknown choice = wrong")

-- newRun
eq(Progression.newRun(Config).day, Config.Progression.StartDay, "newRun at StartDay")

-- resolve correct: day advances, no reset, source state untouched
do
	local s0 = { day = 1 }
	local s1, res = Progression.resolve(s0, ADV, clean, Config)
	eq(res.correct, true, "resolve correct=true")
	eq(res.reset, false, "resolve reset=false on correct")
	eq(s1.day, 2, "day 1 -> 2 on correct")
	eq(res.day, 2, "resolution.day == 2")
	eq(s0.day, 1, "resolve does not mutate input state")
end

-- resolve wrong: reset to StartDay
do
	local s0 = { day = 37 }
	local s1, res = Progression.resolve(s0, ADV, anom, Config)
	eq(res.correct, false, "resolve correct=false on wrong")
	eq(res.reset, true, "resolve reset=true on wrong")
	eq(s1.day, Config.Progression.StartDay, "wrong -> reset to StartDay")
	eq(s0.day, 37, "resolve does not mutate input on wrong")
end

-- resolve caps at MaxDay
do
	local s0 = { day = Config.Progression.MaxDay }
	local s1 = Progression.resolve(s0, ADV, clean, Config)
	eq(s1.day, Config.Progression.MaxDay, "day capped at MaxDay")
end

-- bestAfter monotonic
eq(Progression.bestAfter(10, 4), 10, "bestAfter keeps higher best")
eq(Progression.bestAfter(10, 25), 25, "bestAfter takes new higher day")

-- caughtAnomalyId
eq(Progression.caughtAnomalyId(TB, anom), "figure_end", "caught on correct turn-back")
eq(Progression.caughtAnomalyId(ADV, anom), nil, "not caught if advanced past anomaly")
eq(Progression.caughtAnomalyId(TB, clean), nil, "nothing caught on a clean hall")
eq(Progression.caughtAnomalyId(ADV, clean), nil, "nothing caught on correct advance")

print(string.format("Progression: %d passed, %d failed", passed, failed))
if failed > 0 then error("Progression tests failed") end
