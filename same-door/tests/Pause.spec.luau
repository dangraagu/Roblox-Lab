-- Spec for Pause: where rest is allowed, and why it can never be an exploit. Run: luau tests/Pause.spec.luau
--
-- The run clock never stops: it is the medal and the record (DESIGN §9). Rest.luau (verbatim from
-- +1 Jump) says the same in its header. So rest lives BETWEEN runs, in the hub:
--   * mayRest is true only in the hub and outside a run, and fails closed on anything else;
--   * the in-run pause button opens a sheet whose only way to rest is to LEAVE the run (nothing is
--     posted, the clock is never paused); "Keep running" closes it and the clock never stopped;
--   * the shipped Rest config validates (WakeOnMove, BlockWhileThreat), so any move wakes you.
local Pause = require("../src/shared/Pause")
local Rest = require("../src/shared/Rest")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

do
	local ok, err = Rest.validate(Config.Rest)
	truthy(ok, "the shipped Rest config validates (" .. tostring(err) .. ")")
end

eq(Pause.mayRest({ inHub = true, inRun = false }), true, "in the hub, not in a run: may rest")
eq(Pause.mayRest({ inHub = true, inRun = true }), false, "in a run: no rest (the clock never stops)")
eq(Pause.mayRest({ inHub = false, inRun = false }), false, "outside the hub (the Sanctum, the antechamber): no rest")
eq(Pause.mayRest({ inHub = false, inRun = true }), false, "in the maze: no rest")
eq(Pause.mayRest({}), false, "an unknown state fails closed")
eq(Pause.mayRest(nil), false, "nil fails closed")
eq(Pause.mayRest({ inHub = "yes", inRun = false }), false, "a non-boolean fails closed")

-- the pause sheet in a run
do
	local s = Pause.sheet()
	truthy(string.find(s.text, "never stops") ~= nil, "the sheet says the clock never stops")
	eq(s.leave, "Leave run", "one button leaves the run")
	eq(s.stay, "Keep running", "the other keeps running")
	eq(Pause.pausesClock(), false, "opening the sheet pauses nothing")
end

-- a rest in the hub earns nothing: the Rest state machine never grants, and any move wakes you
do
	local s = Rest.new()
	eq(Rest.request(s, Config.Rest, { moving = false, grounded = true, threat = false }), "resting", "standing still in the hub starts a rest")
	eq(Rest.update(s, Config.Rest, 0.5, { moving = true, grounded = true, threat = false }), "woke", "moving wakes you after the grace")
	eq(Rest.isResting(s), false, "and you are awake")
	-- in the hub the idle rest is off (IdleSeconds 0): standing still never starts one by itself
	local s2 = Rest.new()
	local started = nil
	for _ = 1, 600 do
		started = started or Rest.update(s2, Config.Rest, 0.1, { moving = false, grounded = true, threat = false })
	end
	eq(started, nil, "a minute of standing still does not start a rest on its own (IdleSeconds 0)")
end

print(string.format("Pause: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pause spec failed", 0) end
