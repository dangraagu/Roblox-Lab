-- Tests for the virtual clock. Run: luau tests/scheduler.spec.luau
local Scheduler = require("../emu/scheduler")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

-- spawn runs IMMEDIATELY (Roblox semantics), not on the next step
do
	local s = Scheduler.new()
	local ran = false
	s:spawn(function() ran = true end)
	eq(ran, true, "task.spawn runs synchronously up to the first yield")
	eq(s:now(), 0, "spawn does not move the clock")
end

-- wait parks the coroutine until the clock passes the deadline
do
	local s = Scheduler.new()
	local stage = 0
	s:spawn(function()
		stage = 1
		s:wait(5)
		stage = 2
		s:wait(5)
		stage = 3
	end)
	eq(stage, 1, "runs until the first wait")
	s:advance(4)
	eq(stage, 1, "still parked before the deadline")
	s:advance(1)
	eq(stage, 2, "resumes exactly at the deadline")
	s:advance(5)
	eq(stage, 3, "second wait resumes too")
	eq(s:now(), 10, "clock advanced to 10")
end

-- wait returns the elapsed virtual time
do
	local s = Scheduler.new()
	local elapsed = nil
	s:spawn(function() elapsed = s:wait(3) end)
	s:advance(3)
	eq(elapsed, 3, "wait returns elapsed time")
end

-- a repeating loop (this is the autosave loop shape) fires the expected number of times
do
	local s = Scheduler.new()
	local ticks = 0
	s:spawn(function()
		while true do
			s:wait(20)
			ticks += 1
		end
	end)
	s:advance(60)
	eq(ticks, 3, "a 20s loop ticks 3 times in 60 virtual seconds")
	truthy(s:pending() > 0, "the loop is still parked, not dead")
end

-- delay schedules into the future without blocking
do
	local s = Scheduler.new()
	local fired = false
	s:delay(10, function() fired = true end)
	s:advance(9)
	eq(fired, false, "delay has not fired early")
	s:advance(1)
	eq(fired, true, "delay fired at its deadline")
end

-- defer runs at the same clock time, after the current point
do
	local s = Scheduler.new()
	local order = {}
	s:spawn(function()
		table.insert(order, "spawn")
		s:defer(function() table.insert(order, "deferred") end)
		table.insert(order, "after-defer-call")
	end)
	eq(table.concat(order, ","), "spawn,after-defer-call", "defer does not run inline")
	s:advance(0)
	eq(table.concat(order, ","), "spawn,after-defer-call,deferred", "defer runs on the next drain")
	eq(s:now(), 0, "defer did not move the clock")
end

-- errors are CAPTURED, never silently swallowed (a dead server thread is the bug we hunt)
do
	local s = Scheduler.new()
	s:spawn(function() error("boom") end)
	truthy(s:hadErrors(), "a coroutine error is recorded")
	truthy(string.find(s.errors[1] or "", "boom") ~= nil, "the error message is kept")
end

-- an error inside a waiting loop is caught too, and does not wedge advance()
do
	local s = Scheduler.new()
	s:spawn(function()
		s:wait(1)
		error("late boom")
	end)
	s:advance(2)
	truthy(s:hadErrors(), "error after a wait is recorded")
	eq(s:now(), 2, "advance still completed")
end

-- runaway protection: a wait(0) busy loop must not hang the whole run
do
	local s = Scheduler.new()
	s:spawn(function()
		while true do
			s:wait(0)
		end
	end)
	s:advance(1)
	truthy(s:hadErrors(), "a wait(0) spin loop trips the convergence guard instead of hanging")
end

-- nested waits resume in deadline order, not insertion order
do
	local s = Scheduler.new()
	local order = {}
	s:spawn(function() s:wait(5); table.insert(order, "five") end)
	s:spawn(function() s:wait(1); table.insert(order, "one") end)
	s:spawn(function() s:wait(3); table.insert(order, "three") end)
	s:advance(10)
	eq(table.concat(order, ","), "one,three,five", "sleepers wake in deadline order")
end

print(string.format("scheduler: %d passed, %d failed", passed, failed))
if failed > 0 then error("scheduler tests failed") end
