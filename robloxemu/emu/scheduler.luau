-- scheduler.luau — a VIRTUAL clock for the headless run.
--
-- Our servers are full of `task.spawn(function() while true do task.wait(20) ... end end)`
-- (the autosave loop) and `task.wait(2.5)` (the death beat). Sleeping for real would make a
-- test run take minutes and would make the lock/autosave logic untestable. Instead time is a
-- number we advance on demand: `advance(60)` runs a simulated minute in microseconds.
--
-- Semantics matched to Roblox where it matters:
--   * task.spawn(fn, ...)  runs fn IMMEDIATELY, synchronously, until its first yield.
--   * task.wait(t)         yields the current coroutine; it resumes once the clock passes t.
--   * task.defer(fn)       runs fn after the current resumption point, at the same clock time.
--   * task.delay(t, fn)    like spawn but scheduled t seconds out.
-- A coroutine that errors is reported (never silently swallowed) — a dead server thread is
-- exactly the class of bug we are hunting.

local Scheduler = {}
Scheduler.__index = Scheduler

export type Scheduler = typeof(setmetatable(
	{} :: {
		clock: number,
		sleepers: { { co: thread, wake: number, args: { any } } },
		deferred: { { co: thread, args: { any } } },
		errors: { string },
		spawned: number,
	},
	Scheduler
))

function Scheduler.new(): Scheduler
	return setmetatable({
		clock = 0,
		sleepers = {},
		deferred = {},
		errors = {},
		spawned = 0,
	}, Scheduler)
end

-- Resume a coroutine and capture (never swallow) any error it raises.
local function resume(self: Scheduler, co: thread, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		local msg = tostring(err)
		table.insert(self.errors, msg)
		-- surface immediately too: a silent dead thread is the worst failure mode here
		print("[scheduler] coroutine error: " .. msg)
	end
end

function Scheduler.now(self: Scheduler): number
	return self.clock
end

function Scheduler.spawn(self: Scheduler, fn, ...): thread
	self.spawned += 1
	local co = coroutine.create(fn)
	resume(self, co, ...)
	return co
end

function Scheduler.defer(self: Scheduler, fn, ...): thread
	local co = coroutine.create(fn)
	table.insert(self.deferred, { co = co, args = table.pack(...) })
	return co
end

function Scheduler.delay(self: Scheduler, seconds: number, fn, ...): thread
	local co = coroutine.create(fn)
	table.insert(self.sleepers, {
		co = co,
		wake = self.clock + math.max(seconds or 0, 0),
		args = table.pack(...),
	})
	return co
end

-- Yields the CURRENT coroutine. Returns the elapsed (virtual) time, like Roblox.
function Scheduler.wait(self: Scheduler, seconds: number?): number
	local co = coroutine.running()
	if co == nil then
		-- called from the main thread: nothing to yield, just move the clock
		self.clock += math.max(seconds or 0, 0)
		return seconds or 0
	end
	local dt = math.max(seconds or 0, 0)
	table.insert(self.sleepers, { co = co, wake = self.clock + dt, args = table.pack() })
	local before = self.clock
	coroutine.yield()
	return self.clock - before
end

-- Run everything queued with task.defer at the current clock time.
local function drainDeferred(self: Scheduler)
	local guard = 0
	while #self.deferred > 0 do
		guard += 1
		if guard > 10000 then
			table.insert(self.errors, "deferred queue never drained (runaway task.defer)")
			return
		end
		local batch = self.deferred
		self.deferred = {}
		for _, item in batch do
			resume(self, item.co, table.unpack(item.args, 1, item.args.n))
		end
	end
end

-- Advance the virtual clock by `dt`, waking every coroutine whose deadline passes. Wakes are
-- processed in deadline order so a task.wait(1) inside a task.wait(5) still lands correctly.
function Scheduler.advance(self: Scheduler, dt: number)
	local target = self.clock + math.max(dt or 0, 0)
	drainDeferred(self)
	local guard = 0
	while true do
		guard += 1
		if guard > 100000 then
			table.insert(self.errors, "advance() did not converge (runaway task.wait loop)")
			return
		end
		-- find the earliest sleeper still due before `target`
		local nextIdx, nextWake = nil, math.huge
		for i, s in self.sleepers do
			if s.wake <= target and s.wake < nextWake then
				nextIdx, nextWake = i, s.wake
			end
		end
		if not nextIdx then
			break
		end
		local s = table.remove(self.sleepers, nextIdx)
		self.clock = math.max(self.clock, s.wake)
		resume(self, s.co, table.unpack(s.args, 1, s.args.n))
		drainDeferred(self)
	end
	self.clock = target
	drainDeferred(self)
end

-- How many coroutines are still parked (useful to assert a loop is actually running).
function Scheduler.pending(self: Scheduler): number
	return #self.sleepers + #self.deferred
end

function Scheduler.hadErrors(self: Scheduler): boolean
	return #self.errors > 0
end

-- Build the `task` table (and legacy `wait`/`delay`/`spawn` globals) bound to this scheduler.
function Scheduler.globals(self: Scheduler)
	local task = {
		spawn = function(fn, ...) return Scheduler.spawn(self, fn, ...) end,
		defer = function(fn, ...) return Scheduler.defer(self, fn, ...) end,
		delay = function(t, fn, ...) return Scheduler.delay(self, t, fn, ...) end,
		wait = function(t) return Scheduler.wait(self, t) end,
		cancel = function(_co) end, -- no-op: nothing in our games relies on cancellation
	}
	return {
		task = task,
		wait = function(t) return Scheduler.wait(self, t) end,
		delay = function(t, fn, ...) return Scheduler.delay(self, t, fn, ...) end,
		spawn = function(fn, ...) return Scheduler.spawn(self, fn, ...) end,
	}
end

return Scheduler
