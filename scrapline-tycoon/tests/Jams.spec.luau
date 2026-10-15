-- Jams — the one active job: one sputter at a time, its target, sputter -> jam, the fix, and what a recycle does.
-- Run: luau tests/Jams.spec.luau
--
-- DESIGN.md section 5. The jam clock counts LINE time (only while a machine is built), and only while no
-- sputter is live. When it runs out, one random WORKING machine starts to sputter for 15 s (it still works);
-- a Fix in that time saves it, otherwise it jams (it stops) and the clock runs again. A brand-new profile's
-- first sputter comes after 240 s; after that every 150-210 s. Draws come from an injected rand(), so this
-- spec supplies its own deterministic LCG; the game uses the server's Random.new().

local Config = require("../src/shared/Config")
local Jams = require("../src/shared/Jams")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local C = Config
local J = C.Jams

local seed = 7
local function rand()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function line(spec)
	local S = {}
	for t = 1, 6 do
		local s = spec and spec[t]
		S[t] = { n = s and s.n or 0, L = 1, jam = { s and s.jam and s.jam[1] or 0, s and s.jam and s.jam[2] or 0 } }
	end
	return S
end
-- run until an event (or the limit), dt at a time; returns the event and the seconds it took
local function runUntil(js, S, dt, limit)
	local t = 0
	while t < limit do
		local ev = Jams.step(C, js, S, dt, rand)
		t += dt
		if ev then return ev, t end
	end
	return nil, t
end

--============================================================================ the first sputter of a new profile
do
	local js = Jams.new(C)
	eq(js.jamIn, 240, "a brand-new profile's first sputter is 240 s of line time away")
	eq(js.sputter, nil, "nothing is sputtering")
	-- an empty line: the clock does not run (nothing could jam)
	local empty = line()
	for _ = 1, 1000 do Jams.step(C, js, empty, 0.5, rand) end
	eq(js.jamIn, 240, "with no machine built the clock stands still (500 s passed)")
	local S = line({ { n = 1 } })
	local ev, took = runUntil(js, S, 0.5, 1000)
	truthy(ev ~= nil and ev.kind == "sputter", "with a Shredder built, a sputter comes")
	near(took, 240, 1e-9, "after exactly 240 s")
	eq(ev and ev.t, 1, "on the only machine there is: the Shredder")
	eq(ev and ev.m, 1, "...machine a")
	eq(S[1].jam[1], 1, "it is SPUTTERING (still working)")
	truthy(js.sputter ~= nil and js.sputter.t == 1 and js.sputter.m == 1, "the scheduler knows which")
	near(js.sputter.left, J.SputterSeconds, 1e-9, "with 15 s to fix it")
	truthy(js.jamIn >= J.JamMin and js.jamIn <= J.JamMax, string.format("the next one is drawn at once: %.1f s, in 150-210", js.jamIn))
	-- the clock does not run while it is live
	local nextIn = js.jamIn
	Jams.step(C, js, S, 10, rand)
	eq(js.jamIn, nextIn, "the clock stands still while a sputter is live")
	truthy(Jams.trouble(js, S), "a live sputter is trouble (hazards hold)")
end

--============================================================================ sputter -> jam after exactly 15 s
do
	local js = Jams.new(C, 1)
	local S = line({ { n = 1 } })
	local ev = runUntil(js, S, 0.5, 10)
	eq(ev and ev.kind, "sputter", "set-up: a sputter")
	local ev2, took = runUntil(js, S, 0.5, 100)
	eq(ev2 and ev2.kind, "jammed", "left alone, it jams")
	near(took, 15, 1e-9, "after exactly 15 s")
	eq(S[1].jam[1], 2, "the machine is JAMMED (stopped)")
	eq(js.sputter, nil, "no sputter is live any more: the clock runs again")
	truthy(Jams.trouble(js, S), "a jam is trouble too")
	-- the clock runs while the jam stays
	local before = js.jamIn
	Jams.step(C, js, S, 5, rand)
	near(js.jamIn, before - 5, 1e-9, "the jam clock moves on while the jam stays (an untended line degrades)")
end

--============================================================================ fixing
do
	local js = Jams.new(C, 1)
	local S = line({ { n = 1 } })
	runUntil(js, S, 0.5, 10)
	eq(Jams.fix(C, js, S, 1, 2), nil, "fixing the unbuilt twin does nothing")
	eq(Jams.fix(C, js, S, 2, 1), nil, "fixing an unbuilt station does nothing")
	Jams.step(C, js, S, 6, rand)
	eq(Jams.fix(C, js, S, 1, 1), "saved", "a fix inside the 15 s SAVES it")
	eq(S[1].jam[1], 0, "the machine runs")
	eq(js.sputter, nil, "the sputter is over")
	truthy(not Jams.trouble(js, S), "no trouble left")
	eq(Jams.fix(C, js, S, 1, 1), nil, "fixing a machine that runs fine does nothing")
	-- a jam fixed later
	js.jamIn = 1
	runUntil(js, S, 0.5, 10)
	runUntil(js, S, 0.5, 100)
	eq(S[1].jam[1], 2, "set-up: jammed")
	eq(Jams.fix(C, js, S, 1, 1), "fixed", "fixing a jammed machine")
	eq(S[1].jam[1], 0, "it runs again")
end

--============================================================================ targets: working machines only, never two at once
do
	-- a full line, twinned: 12 machines. Over many sputters every machine is hit, and never a jammed one.
	local spec = {}
	for t = 1, 6 do spec[t] = { n = 2 } end
	local S = line(spec)
	local js = Jams.new(C, 1)
	local hit = {}
	local maxLive, sputters = 0, 0
	for _ = 1, 400 do
		local ev = runUntil(js, S, 0.5, 400)
		if ev and ev.kind == "sputter" then
			sputters += 1
			hit[ev.t .. ":" .. ev.m] = true
			local live = 0
			for t = 1, 6 do for m = 1, 2 do if S[t].jam[m] == 1 then live += 1 end end end
			maxLive = math.max(maxLive, live)
			Jams.fix(C, js, S, ev.t, ev.m)
		end
	end
	local n = 0
	for _ in hit do n += 1 end
	eq(n, 12, string.format("over %d sputters every one of the 12 machines was picked at least once", sputters))
	eq(maxLive, 1, "never two sputters at once")
	-- jammed machines are never the target: jam all but one; the next sputter is the one left
	local S2 = line(spec)
	for t = 1, 6 do S2[t].jam = { 2, 2 } end
	S2[4].jam[2] = 0
	local js2 = Jams.new(C, 1)
	local ev = runUntil(js2, S2, 0.5, 10)
	eq(ev and (ev.t .. ":" .. ev.m), "4:2", "with 11 machines jammed, the sputter goes to the one still working")
	-- everything jammed: no sputter, the clock re-draws
	local S3 = line(spec)
	for t = 1, 6 do S3[t].jam = { 2, 2 } end
	local js3 = Jams.new(C, 1)
	local ev3 = runUntil(js3, S3, 0.5, 3)
	eq(ev3, nil, "nothing left working: no sputter")
	truthy(js3.jamIn >= J.JamMin - 3 and js3.jamIn <= J.JamMax, "and the clock simply draws again")
end

--============================================================================ the gaps between sputters
do
	local S = line({ { n = 2 }, { n = 2 } })
	local js = Jams.new(C, 1)
	local gaps = {}
	local last = nil
	local clock = 0
	for _ = 1, 20000 do
		local ev = Jams.step(C, js, S, 0.5, rand)
		clock += 0.5
		if ev and ev.kind == "sputter" then
			if last then table.insert(gaps, clock - last) end
			last = clock
			Jams.fix(C, js, S, ev.t, ev.m) -- fixed at once: the gap is pure clock
		end
	end
	local lo, hi = math.huge, 0
	for _, g in gaps do lo = math.min(lo, g); hi = math.max(hi, g) end
	print(string.format("  %d sputters fixed at once: gaps %.1f-%.1f s", #gaps, lo, hi))
	truthy(lo >= J.JamMin - 0.5 and hi <= J.JamMax + 0.5, "every gap between sputters is 150-210 s of line time")
end

--============================================================================ a recycle clears jams and keeps the clock
do
	local S = line({ { n = 2, jam = { 2, 0 } }, { n = 1 } })
	local js = Jams.new(C, 1)
	runUntil(js, S, 0.5, 10) -- a sputter on one of the working machines
	local clockBefore = js.jamIn
	Jams.clearForRecycle(js, S)
	eq(js.sputter, nil, "a recycle ends the live sputter (the machines are new)")
	eq(S[1].jam[1] + S[1].jam[2] + S[2].jam[1], 0, "and every jam")
	eq(js.jamIn, clockBefore, "but the jam clock keeps counting: a recycle is never a way to dodge it")
end

--============================================================================ what is saved: a live sputter counts as a jam
do
	local S = line({ { n = 2 }, { n = 1, jam = { 2, 0 } } })
	local js = Jams.new(C, 1)
	local ev = runUntil(js, S, 0.5, 10)
	truthy(ev ~= nil, "set-up: a sputter")
	local counts = Jams.jammedCounts(S)
	local live = (ev :: any).t
	eq(counts[2], if live == 2 then 2 else 1, "the jammed Furnace machine counts")
	eq(counts[live] >= 1, true, "and the sputtering machine counts as jammed too (a live sputter saves as a jam)")
	-- loading a saved count jams the first machines of the station
	local back = Jams.fromCount(2, 1)
	eq(back[1], 2, "a saved count of 1 on a twinned station: machine a loads jammed")
	eq(back[2], 0, "machine b runs")
	local none = Jams.fromCount(2, 0)
	eq(none[1] + none[2], 0, "a count of 0: both run")
	local both = Jams.fromCount(2, 5)
	eq(both[1] + both[2], 4, "a count above n is clamped: both jammed")
	local one = Jams.fromCount(1, 2)
	eq(one[2], 0, "a twin that does not exist never loads jammed")
end

print(string.format("Jams: %d passed, %d failed", passed, failed))
if failed > 0 then error("Jams spec failed", 0) end
