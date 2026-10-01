-- Spec for Weather: the global weather clock. Run: luau tests/Weather.spec.luau
--
-- The clock is the game's differentiator: every server shows the same event at the same Unix second, so
-- server hopping gains nothing and players can tell each other "rainbow at :30". These are the rules the
-- server's strike loop, the HUD's forecast and the client's sky all rely on (DESIGN.md §2.1).
local Weather = require("../src/shared/Weather")
local Config = require("../src/shared/Config")
local W = Config.Weather

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, msg, tol)
	tol = tol or 1e-9
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

-- A Unix second that is exactly on the hour (2026-09-21 14:00:00 UTC): 1790002800 % 3600 == 0.
local HOUR = 1790002800
eq(HOUR % 3600, 0, "set-up: the reference second is on the hour")

do
	local ok, err = Weather.validate(W)
	truthy(ok, "Config.Weather validates (" .. tostring(err) .. ")")
	local bad = table.clone(W)
	bad.Events = table.clone(W.Events)
	bad.Events.frost = { from = 60, len = 90, every = 600 }
	eq((Weather.validate(bad)), false, "an event overlapping the storm is rejected")
	local bad2 = table.clone(W)
	bad2.Events = table.clone(W.Events)
	bad2.Events.storm = { from = 0, len = 92, every = 600 }
	eq((Weather.validate(bad2)), false, "an event whose length is not a whole number of ticks is rejected")
end

--================================================================ the schedule, second by second

eq((Weather.at(HOUR, W)), "storm", ":00:00 is a storm")
eq((Weather.at(HOUR + 89, W)), "storm", ":01:29 is still the storm")
eq((Weather.at(HOUR + 90, W)), "rainbow", ":01:30 the rainbow follows the :00 storm")
eq((Weather.at(HOUR + 149, W)), "rainbow", ":02:29 still the rainbow")
eq((Weather.at(HOUR + 150, W)), "clear", ":02:30 clear")
eq((Weather.at(HOUR + 300, W)), "frost", ":05:00 frost")
eq((Weather.at(HOUR + 389, W)), "frost", ":06:29 frost")
eq((Weather.at(HOUR + 390, W)), "clear", ":06:30 clear")
eq((Weather.at(HOUR + 600, W)), "storm", ":10:00 storm")
eq((Weather.at(HOUR + 690, W)), "clear", ":11:30 NO rainbow after the :10 storm")
eq((Weather.at(HOUR + 1800 + 90, W)), "rainbow", ":31:30 rainbow after the :30 storm")
eq((Weather.at(HOUR + 1200 + 90, W)), "clear", ":21:30 no rainbow after the :20 storm")
eq((Weather.at(HOUR + 3000 + 90, W)), "clear", ":51:30 no rainbow after the :50 storm")

do
	local k, from, to = Weather.at(HOUR + 1800 + 100.5, W)
	eq(k, "rainbow", "a fractional second inside the :31:30 rainbow")
	eq(from, HOUR + 1890, "its window starts at :31:30")
	eq(to, HOUR + 1950, "and ends at :32:30")
end

do
	-- Every second of 24 hours is classified, and the counts per hour are what the design promises.
	local counts = { storm = 0, frost = 0, rainbow = 0, clear = 0 }
	local starts = { storm = 0, frost = 0, rainbow = 0 }
	local rainbowAfterStorm, rainbowOther = 0, 0
	local prev = "clear"
	local gapStart, longestGap = HOUR, 0
	for t = HOUR, HOUR + 86400 - 1 do
		local k = Weather.at(t, W)
		counts[k] += 1
		if k ~= prev and k ~= "clear" then
			starts[k] += 1
			if k == "rainbow" then
				if prev == "storm" then rainbowAfterStorm += 1 else rainbowOther += 1 end
			end
		end
		if k == "clear" and prev ~= "clear" then gapStart = t end
		if k ~= "clear" and prev == "clear" then longestGap = math.max(longestGap, t - gapStart) end
		prev = k
	end
	eq(counts.storm + counts.frost + counts.rainbow + counts.clear, 86400, "every second of 24 h is classified")
	eq(starts.storm, 144, "6 storms an hour")
	eq(starts.frost, 144, "6 frosts an hour")
	eq(starts.rainbow, 48, "2 rainbows an hour")
	eq(rainbowOther, 0, "a rainbow only ever begins the second a storm ends")
	eq(rainbowAfterStorm, 48, "and every rainbow does")
	eq(counts.storm, 144 * 90, "storms last 90 s")
	eq(counts.rainbow, 48 * 60, "rainbows last 60 s")
	eq(longestGap, 210, "the longest wait for any event is 210 s (a new player sees weather inside 3.5 min)")
end

--================================================================ the forecast

do
	local k, s = Weather.nextEvent(HOUR - 10, W)
	eq(k, "storm", "10 s before the hour the next event is the storm")
	eq(s, HOUR, "starting on the hour")
	k, s = Weather.nextEvent(HOUR, W)
	eq(k, "rainbow", "AT :00:00 the next event is the one after (strictly later)")
	eq(s, HOUR + 90, "the rainbow at :01:30")
	k, s = Weather.nextEvent(HOUR + 700, W)
	eq(k, "frost", "at :11:40 the next is the :15 frost")
	eq(s, HOUR + 900, "at :15:00")
	-- exhaustive: nextEvent agrees with a brute-force scan
	local bad = 0
	for t = HOUR, HOUR + 3600, 7 do
		local nk, ns = Weather.nextEvent(t, W)
		local scan = math.floor(t) + 1
		while true do
			local ak, af = Weather.at(scan, W)
			if ak ~= "clear" and af == scan then break end
			scan += 1
		end
		local ak = Weather.at(scan, W)
		if nk ~= ak or ns ~= scan then bad += 1 end
	end
	eq(bad, 0, "nextEvent matches a second-by-second scan over an hour")
end

do
	local list = Weather.timeline(HOUR + 30, W, 1800)
	eq(list[1].kind, "storm", "the timeline starts with the running storm")
	eq(list[1].from, HOUR, "which began on the hour")
	eq(list[2].kind, "rainbow", "then the rainbow")
	local last = list[#list]
	truthy(last.from <= HOUR + 30 + 1800, "the timeline stops at its horizon")
	eq(#list, 8, "the 30 minutes after :00:30 hold 8 events (storm, rainbow, 3 frosts, 3 more storms)")
end

--================================================================ strike ticks and the odds

eq(Weather.ticks("storm", W), 18, "a storm has 18 strike ticks")
eq(Weather.ticks("frost", W), 18, "a frost has 18")
eq(Weather.ticks("rainbow", W), 12, "a rainbow has 12")
approx(Weather.perTick("storm", W), 1 - 0.5 ^ (1 / 18), "storm per-tick chance")
approx(Weather.perTick("rainbow", W), 1 - 0.65 ^ (1 / 12), "rainbow per-tick chance")
approx(Weather.perTick("storm", W), 0.03778, "storm per tick is 0.03778 to 5 places (DESIGN.md)", 5e-6)
approx(Weather.perTick("rainbow", W), 0.03526, "rainbow per tick is 0.03526 to 5 places (DESIGN.md)", 5e-6)
for _, kind in W.Kinds do
	local q = Weather.perTick(kind, W)
	approx(1 - (1 - q) ^ Weather.ticks(kind, W), W.Chance[kind], kind .. ": a crop ripe for the whole event gets exactly P")
end

do
	eq(Weather.isTick(HOUR, W), "storm", "the first second of a storm is a tick")
	eq(Weather.isTick(HOUR + 85, W), "storm", ":01:25 is the last storm tick")
	eq(Weather.isTick(HOUR + 3, W), nil, "a second that is not a multiple of 5 is no tick")
	eq(Weather.isTick(HOUR + 200, W), nil, "clear weather has no ticks")
	local n = 0
	for t = HOUR, HOUR + 3599 do
		if Weather.isTick(t, W) then n += 1 end
	end
	eq(n, 6 * 18 + 6 * 18 + 2 * 12, "an hour has 240 strike ticks")
	local first, last = Weather.tickWindow("storm", HOUR, W)
	eq(first, HOUR, "a storm's first tick is its start")
	eq(last, HOUR + 85, "its last tick is 5 s before its end")
end

--================================================================ the overlay weight

do
	local k, w = Weather.weight(HOUR, W)
	eq(k, "storm", "weight names the running event")
	approx(w, 0, "and starts at 0")
	_, w = Weather.weight(HOUR + 2, W)
	approx(w, 0.5, "half-way through the 4 s fade in")
	_, w = Weather.weight(HOUR + 45, W)
	approx(w, 1, "full in the middle")
	_, w = Weather.weight(HOUR + 88, W)
	approx(w, 0.5, "fading out 2 s before the end")
	k, w = Weather.weight(HOUR + 200, W)
	eq(k, "clear", "clear weather")
	approx(w, 0, "has no weight")
end

--================================================================ which event a seed planted now will catch

do
	-- Radish (30 s) planted at :59:50 is ripe at :00:20, inside the :00 storm.
	local k, s = Weather.catchesEvent(HOUR - 10, 30, W)
	eq(k, "storm", "a Radish planted 10 s before the hour catches the storm")
	eq(s, HOUR, "the :00 storm")
	-- Pumpkin (360 s) planted at :00:00 ripens at :06:00: the :05 frost's last tick is :06:25.
	k, s = Weather.catchesEvent(HOUR, 360, W)
	eq(k, "frost", "a Pumpkin planted on the hour catches the :05 frost")
	eq(s, HOUR + 300, "at :05")
	-- ripe after the frost's last tick (:06:25): the next event is the :10 storm
	k, s = Weather.catchesEvent(HOUR + 30, 360, W)
	eq(k, "storm", "planted at :00:30 it ripens at :06:30, after the frost: it catches the :10 storm")
	eq(s, HOUR + 600, "at :10")
	-- a crop that ripens exactly on an event's last tick still catches it
	k = Weather.catchesEvent(HOUR + 25, 360, W)
	eq(k, "frost", "ripe exactly on the frost's last tick (:06:25) still catches it")
end

--================================================================ the clock label

eq(Weather.minuteLabel(HOUR + 1200, W), ":20", "an event on a whole minute reads :20")
eq(Weather.minuteLabel(HOUR + 90, W), ":01:30", "the rainbow reads :01:30")

print(string.format("Weather: %d passed, %d failed", passed, failed))
assert(failed == 0, "Weather tests failed")
