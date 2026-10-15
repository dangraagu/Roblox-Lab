-- Guard: the movement check that sweeps out teleports and speed hacks (DESIGN.md §2.7, §10).
-- Run: luau tests/Guard.spec.luau
local Guard = require("../src/shared/Guard")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local GC = Config.Guard
local box = 52
local seed = 99
local function rand(): number
	seed = (1664525 * seed + 1013904223) % 4294967296
	return seed / 4294967296
end

eq(GC.MaxStuds, 28, "28 studs in any trailing 1.0 s (16 x 1.5 + 4)")

--======================================================================= honest walking never trips

do
	local trips = 0
	local worst = 0
	for run = 1, 300 do
		local g = Guard.new()
		Guard.reset(g, Config, 0)
		local x, z, heading = 0, 0, rand() * math.pi * 2
		local t = 0
		local stall = 0
		while t < 60 do
			-- server ticks at 10 Hz with +-30 ms jitter; positions arrive with +-0.5 stud noise
			local dt = 0.1 + (rand() * 2 - 1) * 0.03
			t += dt
			heading += (rand() * 2 - 1) * 0.6
			x = math.clamp(x + math.cos(heading) * 16 * dt, -50, 50)
			z = math.clamp(z + math.sin(heading) * 16 * dt, -50, 50)
			-- network bunching: now and then the server sees nothing new for up to 0.5 s, then all of it at once
			if stall <= 0 and rand() < 0.02 then stall = 0.2 + rand() * 0.3 end
			if stall > 0 then
				stall -= dt
			else
				local nx, nz = x + (rand() * 2 - 1) * 0.5, z + (rand() * 2 - 1) * 0.5
				local r = Guard.sample(g, Config, t, nx, nz, box)
				if r ~= "ok" then trips += 1 end
				worst = math.max(worst, Guard.lastSpan(g))
			end
		end
	end
	eq(trips, 0, "300 minutes of honest walking at 16 studs/s with jitter, noise and lag bunching: no trip")
	truthy(worst < GC.MaxStuds, string.format("the most an honest walker covered in any 1.0 s window: %.1f studs (limit 28)", worst))
	print(string.format("  300 honest minutes: 0 trips; the most covered in any 1.0 s window was %.1f studs (limit %d)", worst, GC.MaxStuds))
end

--======================================================================= cheats

do
	local g = Guard.new()
	Guard.reset(g, Config, 0)
	eq(Guard.sample(g, Config, 1.0, 0, 0, box), "ok", "standing still is fine")
	eq(Guard.sample(g, Config, 1.1, 30, 0, box), "speed", "a 30-stud teleport trips the guard")
	local g2 = Guard.new()
	Guard.reset(g2, Config, 0)
	local verdict = "ok"
	for k = 1, 30 do
		local r = Guard.sample(g2, Config, 1 + k * 0.1, k * 0.1 * 32, 0, box)
		if r ~= "ok" then verdict = r break end
	end
	eq(verdict, "speed", "a 32 studs/s speed hack trips it within a second")
	local g3 = Guard.new()
	Guard.reset(g3, Config, 0)
	eq(Guard.sample(g3, Config, 2, 56.5, 0, box), "box", "leaving the island box by more than 4 studs trips it")
	eq(Guard.sample(Guard.new(), Config, 2, 55.9, 0, box), "ok", "3.9 studs outside the box is not (a knock off the edge, a jump)")
	eq(Guard.sample(Guard.new(), Config, 2, 1000, 0, nil), "ok", "off the island (on the Lookout) there is no box")
end

--======================================================================= server moves are not the player's

do
	local g = Guard.new()
	Guard.reset(g, Config, 0)
	Guard.sample(g, Config, 0.5, -74, 0, nil)
	Guard.reset(g, Config, 1.0) -- the server drops the player on the island
	eq(Guard.sample(g, Config, 1.05, 20, 20, box), "ok", "a server drop of 100 studs is never a trip")
	eq(Guard.sample(g, Config, 1.5, 21, 20, box), "ok", "and the guard is quiet for 1 s after it")
	eq(Guard.sample(g, Config, 2.2, 22, 20, box), "ok", "walking after that is fine")
	eq(Guard.sample(g, Config, 2.3, 60, 20, box), "box", "and a cheat after that is caught")
end

--======================================================================= a stale position inside the quiet second (REVIEW-1 F10)

-- The drop is a server PivotTo of a client-owned character. If the server sees the OLD spot (the deck) for one
-- sample shortly after it, that is replication lag, not the player: nothing seen inside the quiet second may trip
-- the guard once the second is over. The guard judges movement from the first sample after the quiet second.
do
	for _, lag in { 0.05, 0.15, 0.25, 0.45, 0.75, 0.9 } do
		local g = Guard.new()
		Guard.reset(g, Config, 0)
		Guard.sample(g, Config, 0.5, -74, 0, nil) -- on the deck
		Guard.reset(g, Config, 1.0) -- the server drops the player at (20, 20)
		-- 10 Hz samples on the island for 3 s, and ONE stale deck position at 1.0 + lag, inside the quiet second
		local times = {}
		for k = 1, 30 do table.insert(times, { t = 1.0 + k * 0.1, x = 20, z = 20 }) end
		table.insert(times, { t = 1.0 + lag, x = -74, z = 0 })
		table.sort(times, function(a, b) return a.t < b.t end)
		local verdict = "ok"
		for _, s in times do
			local r = Guard.sample(g, Config, s.t, s.x, s.z, box)
			if r ~= "ok" then verdict = r break end
		end
		eq(verdict, "ok", string.format("one stale deck position %.2f s after the drop never trips the guard after its quiet second", lag))
	end
	-- and it is still a guard: a 30-stud teleport right after the quiet second is caught
	local g = Guard.new()
	Guard.reset(g, Config, 1.0)
	Guard.sample(g, Config, 1.5, -74, 0, box) -- stale, inside the quiet second: forgotten
	eq(Guard.sample(g, Config, 2.05, 20, 20, box), "ok", "the first sample after the quiet second is where the guard starts from")
	eq(Guard.sample(g, Config, 2.15, 50, 20, box), "speed", "a 30-stud teleport 0.1 s later is caught")
end

print(string.format("Guard: %d passed, %d failed", passed, failed))
assert(failed == 0, "Guard tests failed")
