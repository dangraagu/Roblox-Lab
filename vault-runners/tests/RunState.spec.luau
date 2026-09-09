-- RunState — the rule the whole game is built on: GEMS ONLY BANK IF YOU GET OUT BEFORE THE SEAL.
-- Run: luau tests/RunState.spec.luau
--
-- RunState is pure: it takes cfg + a run spec + a clock reading and returns plain tables. It
-- touches no Roblox global, so every rule below is exact arithmetic in the luau CLI with no
-- engine present, and the server is left owning nothing but "where is the player standing".
--
-- The defect this file exists to prevent: an escape handler that pays out whenever the player
-- reaches the exit pad. That version is playable, feels fine, and quietly removes the only risk
-- in the game — the collapse becomes decoration. Assertions 5-8 are the ones that kill it.

local Config = require("../src/shared/Config")
local RunState = require("../src/shared/RunState")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want ~", tostring(b))
	end
end

local SPEC = { tier = 1, floor = 1, collapseSeconds = 70, gemValue = 4, gemCount = 12 }
local GEOM = { killPlane = { startY = -10, endY = 50 } }

local function fresh(now)
	return RunState.start(Config, SPEC, now or 0)
end

--============================================================================ 1. a fresh run

do
	local run = fresh(100)
	eq(run.carried, 0, "a fresh run carries nothing")
	eq(run.banked, 0, "a fresh run has banked nothing")
	eq(run.lost, 0, "a fresh run has lost nothing")
	truthy(run.alive, "a fresh run is alive")
	falsy(run.escaped, "a fresh run has not escaped")
	eq(run.startedAt, 100, "the run remembers when it started")
	eq(run.sealAt, 170, "the seal lands collapseSeconds after the start")
	eq(RunState.status(run, 100), "running", "status is running")
	near(RunState.timeLeft(run, 130), 40, 1e-9, "time left counts down")
	near(RunState.timeLeft(run, 999), 0, 1e-9, "time left never goes negative")
end

--============================================================================ 2. collecting

do
	local run = fresh(0)
	local ok = RunState.collect(run, 3, 4, 1)
	truthy(ok, "collecting a gem succeeds")
	eq(run.carried, 4, "carried went up by the gem's value")

	local ok2, why = RunState.collect(run, 3, 4, 2)
	falsy(ok2, "the same gem cannot be collected twice")
	eq(why, "already", "and it says why")
	eq(run.carried, 4, "a duplicate collect does not pay")

	RunState.collect(run, 4, 4, 3)
	RunState.collect(run, 5, 4, 4)
	eq(run.carried, 12, "three distinct gems carry 12")
	eq(RunState.collectedCount(run), 3, "and the run counts three of them")
end

--============================================================================ 3-4. escaping in time

do
	local run = fresh(0)
	for id = 1, 5 do RunState.collect(run, id, 4, id) end
	eq(run.carried, 20, "carrying 20 into the exit")

	local res = RunState.tryEscape(run, 1, 60)   -- 10 seconds to spare
	truthy(res.ok, "escaping before the seal works")
	eq(res.banked, 20, "and banks every gem carried")
	eq(res.reason, "escaped", "with the escape reason")
	eq(run.carried, 0, "the run is no longer carrying them")
	eq(run.banked, 20, "the run's banked total holds them")
	truthy(run.escaped, "the run is marked escaped")
	eq(RunState.status(run, 60), "escaped", "status is escaped")
end

do -- pet multiplier applies at the BANK, not at pickup: a pet is worth what you escape with
	local run = fresh(0)
	for id = 1, 7 do RunState.collect(run, id, 1, id) end
	local res = RunState.tryEscape(run, 1.65, 10)
	eq(res.banked, 11, "a 1.65x pet turns 7 carried into 11 banked (floor)")
	eq(res.carried, 7, "the result reports what was carried in")
end

--============================================================================ 5. THE RULE — sealed

do
	local run = fresh(0)
	for id = 1, 6 do RunState.collect(run, id, 4, id) end
	eq(run.carried, 24, "carrying 24 when the vault seals")

	local res = RunState.tryEscape(run, 1, 70.5)  -- half a second too slow
	falsy(res.ok, "reaching the exit AFTER the seal does not bank")
	eq(res.banked, 0, "nothing is banked")
	eq(res.reason, "sealed", "and the reason is the seal")
	eq(run.banked, 0, "the run's banked total stays at zero")
	eq(run.lost, 24, "every carried gem is LOST")
	eq(run.carried, 0, "and no longer carried")
	falsy(run.alive, "the runner is sealed in")
	eq(RunState.status(run, 70.5), "sealed", "status is sealed")
end

--============================================================================ 6. the boundary

do -- now == sealAt is TOO LATE. A boundary that pays out is a boundary a player will farm.
	local run = fresh(0)
	RunState.collect(run, 1, 4, 1)
	local res = RunState.tryEscape(run, 1, 70)
	falsy(res.ok, "arriving exactly ON the seal is too late")
	eq(res.reason, "sealed", "exactly on the seal reads as sealed")
end

do -- one tick before is fine
	local run = fresh(0)
	RunState.collect(run, 1, 4, 1)
	local res = RunState.tryEscape(run, 1, 69.999)
	truthy(res.ok, "arriving one millisecond before the seal banks")
	eq(res.banked, 4, "and pays the gem")
end

--============================================================================ 7. dying

do
	local run = fresh(0)
	for id = 1, 4 do RunState.collect(run, id, 10, id) end
	local res = RunState.kill(run, 20, "collapse")
	eq(res.lost, 40, "dying loses everything carried")
	eq(res.cause, "collapse", "the cause comes back for the HUD")
	eq(run.banked, 0, "dying banks nothing")
	falsy(run.alive, "and the runner is dead")
	eq(RunState.status(run, 20), "dead", "status is dead")

	local after = RunState.tryEscape(run, 1, 21)
	falsy(after.ok, "a dead runner cannot then escape")
	eq(after.reason, "dead", "and is told they are dead")
	eq(run.banked, 0, "still banks nothing")
end

--============================================================================ 8. no double-bank

do
	local run = fresh(0)
	RunState.collect(run, 1, 25, 1)
	local a = RunState.tryEscape(run, 1, 10)
	local b = RunState.tryEscape(run, 1, 11)
	truthy(a.ok, "the first escape banks")
	falsy(b.ok, "the second does not")
	eq(b.reason, "escaped", "because the run is already out")
	eq(run.banked, 25, "and the total is not paid twice")
end

do -- and you cannot keep collecting once you are out or dead
	local run = fresh(0)
	RunState.tryEscape(run, 1, 5)
	local ok, why = RunState.collect(run, 9, 4, 6)
	falsy(ok, "collecting after escaping is refused")
	eq(why, "escaped", "with the reason")
	eq(run.carried, 0, "and pays nothing")

	local dead = fresh(0)
	RunState.kill(dead, 5, "collapse")
	local ok2, why2 = RunState.collect(dead, 9, 4, 6)
	falsy(ok2, "collecting after dying is refused")
	eq(why2, "dead", "with the reason")
end

--============================================================================ 9. the collapse plane

do
	local run = fresh(0)
	near(RunState.planeY(run, GEOM, 0), -10, 1e-9, "the plane starts below storey 0")
	near(RunState.planeY(run, GEOM, 35), 20, 1e-9, "and is halfway up at half time")
	near(RunState.planeY(run, GEOM, 70), 50, 1e-9, "and reaches the top exactly at the seal")
	near(RunState.planeY(run, GEOM, 200), 50, 1e-9, "and never climbs past the top")
	near(RunState.planeY(run, GEOM, -5), -10, 1e-9, "and never dips below the start")

	local last = -math.huge
	local monotone = true
	for i = 0, 140 do
		local y = RunState.planeY(run, GEOM, i * 0.5)
		if y < last - 1e-9 then monotone = false end
		last = y
	end
	truthy(monotone, "the collapse only ever rises")

	near(RunState.collapseProgress(run, 17.5), 0.25, 1e-9, "progress is a clean 0..1 fraction")
	near(RunState.collapseProgress(run, 700), 1, 1e-9, "clamped at 1")
end

do -- the plane is where the danger reading comes from, so it must be sealed-consistent
	local run = fresh(0)
	falsy(RunState.isSealed(run, 69.9), "not sealed just before")
	truthy(RunState.isSealed(run, 70), "sealed exactly on the second")
	truthy(RunState.isSealed(run, 70.1), "and after")
end

--============================================================================ 10. escaping empty

do
	local run = fresh(0)
	local res = RunState.tryEscape(run, 1.5, 10)
	truthy(res.ok, "escaping with no gems is still an escape")
	eq(res.banked, 0, "it just banks nothing")
	eq(run.banked, 0, "and the multiplier cannot conjure gems from zero")
end

--============================================================================ CONTROL

-- A change the suite must NOT notice. Everything above pins WHEN gems bank; nothing above may
-- accidentally pin the ORDER they were picked up in. If this section ever fails, the rules have
-- grown a dependency on collection order — which would make two identical runs pay differently
-- and would be a real bug, but it would ALSO mean the suite above had started measuring
-- something it was never meant to measure.
do
	local forward = fresh(0)
	for id = 1, 6 do RunState.collect(forward, id, id * 3, id * 0.5) end
	local a = RunState.tryEscape(forward, 1.24, 40)

	local backward = fresh(0)
	for id = 6, 1, -1 do RunState.collect(backward, id, id * 3, (7 - id) * 0.5) end
	local b = RunState.tryEscape(backward, 1.24, 40)

	eq(a.banked, b.banked, "CONTROL: gem pickup order does not change the payout")
	eq(a.carried, b.carried, "CONTROL: nor what was carried")
	eq(forward.banked, backward.banked, "CONTROL: nor the run's banked total")

	-- Same control on the clock: banking cannot depend on WHEN inside the window you escaped,
	-- only on whether you did. A timer bonus would be a feature; it is not in v1's scope, and
	-- if one ever appears this line is what tells us the payout rule changed.
	local early = fresh(0)
	RunState.collect(early, 1, 30, 1)
	local late = fresh(0)
	RunState.collect(late, 1, 30, 1)
	eq(RunState.tryEscape(early, 1, 2).banked, RunState.tryEscape(late, 1, 69).banked,
		"CONTROL: escaping early pays the same as escaping at the last second")
end

print(string.format("RunState: %d passed, %d failed", passed, failed))
if failed > 0 then error("RunState tests failed", 0) end
