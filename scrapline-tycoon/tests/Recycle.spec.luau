-- Recycle — the prestige: its requirement, the checks (in order), the new run it writes (all or nothing), and the
-- factory grade a bolt count paints. Run: luau tests/Recycle.spec.luau
--
-- DESIGN.md section 9.2: recycle k (k = bolts + 1) needs the line to ship 1500 x 1.35^(k-1) rockets per second,
-- jams counted. It pays exactly one Gold Bolt (+50 % value forever). It wipes cash, every station (the Shredder
-- comes back free at level 1), every jam and the tier; it keeps the bolts, boltsAt, the jam clock and the tutorial.
-- nextRun() builds the new run as a NEW table: the server writes it in one owner-checked UpdateAsync and only
-- then swaps it in, so a failed write changes nothing.

local Config = require("../src/shared/Config")
local Line = require("../src/shared/Line")
local Recycle = require("../src/shared/Recycle")

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
local IDS = C.Stations.Order

local function profile(level, bolts)
	local stations = {}
	for _, id in IDS do stations[id] = { n = 2, L = level, jam = { 0, 0 } } end
	return { v = 1, cash = 123456, stations = stations, jams = { jamIn = 77.5, sputter = nil }, tier = 6, bolts = bolts or 0,
		boltsAt = 1790000000, tutorial = 4 }
end
local function dump(v)
	if type(v) ~= "table" then return tostring(v) end
	local keys = {}
	for k in v do table.insert(keys, tostring(k)) end
	table.sort(keys)
	local out = {}
	for _, k in keys do
		local val = v[k]
		if val == nil then val = v[tonumber(k)] end
		table.insert(out, k .. "=" .. dump(val))
	end
	return "{" .. table.concat(out, ",") .. "}"
end
local OK = { loaded = true, saving = true, busy = false }

--============================================================================ the requirement
near(Recycle.requirement(C, 0), 1500, 1e-9, "recycle 1 needs 1500 rockets/s")
near(Recycle.requirement(C, 1), 2025, 1e-9, "recycle 2: 1500 x 1.35 = 2025")
near(Recycle.requirement(C, 4), 1500 * 1.35 ^ 4, 1e-6, "recycle 5: 1500 x 1.35^4 = 4982")
do
	-- the level cap bounds the bolts: a twinned level-100 line ships 2 x 1.25^99 = 7.85e9 rockets/s
	local top = profile(100)
	local rate = Recycle.rocketRate(C, Line, Line.ordered(C, top.stations))
	local most = 0
	while Recycle.requirement(C, most) <= rate do most += 1 end
	eq(most, 52, "no line can ever ask for more than 52 recycles (DESIGN 10.2)")
	truthy(52 * 2e9 + 2e9 < 2 ^ 53, "and 52 bolts encode exactly on the board")
end

--============================================================================ the checks, in order
do
	-- twinned level 31 everywhere: the Shredder pair shreds 2 x 1.25^30 = 1615.5/s, every later station more
	local d = profile(31)
	local ok, why, rate, need = Recycle.check(C, Line, d, OK)
	eq(ok, true, "a twinned level-31 line ships enough rockets for recycle 1")
	near(rate, 2 * 1.25 ^ 30, 1e-6, "its rocket rate is the twinned Shredder's 1615.5/s")
	near(need, 1500, 1e-9, "against 1500")
	local d30 = profile(30)
	ok, why, rate = Recycle.check(C, Line, d30, OK)
	eq(ok, false, "level 30 (1292.5/s) is not enough")
	eq(why, "rate", "...the rate is short")
	eq(Recycle.text(C, why, rate, need), "Ship 1.5K rockets a second to recycle (now 1.2K/s)", "the toast names both numbers")
	-- jams counted: one jammed Shredder machine halves the line
	local j = profile(31)
	j.stations.shredder.jam = { 2, 0 }
	ok, why, rate = Recycle.check(C, Line, j, OK)
	eq(ok, false, "a jammed Shredder machine drops the rate below the requirement: refused")
	near(rate, 1.25 ^ 30, 1e-6, "...the toast's rate counts the jam (807.8/s)")
	-- a sputtering machine still works
	local sp = profile(31)
	sp.stations.shredder.jam = { 1, 0 }
	eq((Recycle.check(C, Line, sp, OK)), true, "a sputtering machine still works: allowed")
	-- the bolts raise the bar
	eq((Recycle.check(C, Line, profile(31, 1), OK)), false, "with 1 bolt the bar is 2025/s: level 31 is refused")
	eq((Recycle.check(C, Line, profile(33, 1), OK)), true, "level 33 (2 x 1.25^32 = 2524/s) clears it")
	-- the session checks come first, in DESIGN 9.2's order
	local _, w1 = Recycle.check(C, Line, d, { loaded = false, saving = true, busy = false })
	eq(w1, "loading", "a profile still loading is refused first")
	local _, w2 = Recycle.check(C, Line, d, { loaded = true, saving = false, busy = false })
	eq(w2, "notsaving", "then a session that is not saving (a recycle needs its save)")
	local _, w3 = Recycle.check(C, Line, d, { loaded = true, saving = true, busy = true })
	eq(w3, "busy", "then a recycle or write already in flight")
	local _, w4 = Recycle.check(C, Line, d30, { loaded = true, saving = false, busy = false })
	eq(w4, "notsaving", "a non-saving session is refused before the rate is even looked at")
	eq(Recycle.text(C, "notsaving"), "Recycling needs your save, and it is not being saved this session. Rejoin to recycle.", "the not-saving toast")
	eq(Recycle.text(C, "busy"), "Recycling… one moment", "the busy toast")
	eq(Recycle.text(C, "loading"), "Loading your factory…", "the loading toast")
	eq(Recycle.text(C, "failed"), "The recycle didn't save. Nothing changed. Try again in a moment.", "the failed-write toast")
	-- REVIEW-2 X3: after a failed write the recycle is held for RetrySeconds, and the held toast counts it down
	eq(Recycle.text(C, "retry", 7.2), "The save is having trouble. Nothing changed: try again in 8 s.", "the held-retry toast rounds up")
	eq(Recycle.text(C, "retry", 0.01), "The save is having trouble. Nothing changed: try again in 1 s.", "...never to 0 s")
	truthy(type(C.Recycle.RetrySeconds) == "number" and C.Recycle.RetrySeconds >= 5 and C.Recycle.RetrySeconds <= 30,
		"a failed recycle write holds the next try 5-30 s (" .. tostring(C.Recycle.RetrySeconds) .. ")")
end

--============================================================================ the new run: a NEW table, the old one untouched
do
	local d = profile(31, 2)
	d.stations.press.jam = { 2, 1 }
	d.jams.sputter = { t = 3, m = 2, left = 4 }
	local before = dump(d)
	local nd = Recycle.nextRun(C, d, 1795000000)
	eq(dump(d), before, "nextRun changes NOTHING in the current profile (the server swaps in the new one only after its write lands)")
	truthy(nd ~= d and nd.stations ~= d.stations and nd.jams ~= d.jams, "it is a fresh table all the way down")
	eq(nd.bolts, 3, "+1 Gold Bolt")
	eq(nd.boltsAt, 1795000000, "boltsAt is when this count was reached (the board's tie-break)")
	eq(nd.cash, 0, "cash to 0")
	eq(nd.tier, 0, "the tier back to 0 (the Junkyard)")
	eq(nd.stations.shredder.n, 1, "the Shredder comes back built")
	eq(nd.stations.shredder.L, 1, "...at level 1")
	for i = 2, 6 do
		eq(nd.stations[IDS[i]].n, 0, IDS[i] .. " is unbuilt")
		eq(nd.stations[IDS[i]].L, 1, IDS[i] .. " is back at level 1")
	end
	local jammed = 0
	for _, id in IDS do jammed += nd.stations[id].jam[1] + nd.stations[id].jam[2] end
	eq(jammed, 0, "every jam is gone (the machines are new)")
	eq(nd.jams.sputter, nil, "and the live sputter")
	eq(nd.jams.jamIn, 77.5, "the jam clock is KEPT")
	eq(nd.tutorial, 4, "the tutorial is kept")
	eq(nd.v, 1, "the version is kept")
end

--============================================================================ grades
do
	local names = {}
	for b = 0, 7 do table.insert(names, C.Grades[Recycle.grade(C, b)].name) end
	eq(table.concat(names, ","), "Rusty,Painted,Steel,Chrome,Gold,Gold,Gold,Gold", "0 bolts rusty ... 4 and more gold")
	eq(Recycle.grade(C, -1), 1, "a negative count is rusty")
	eq(Recycle.golden(C, 4), true, "4 bolts: the Golden Factory")
	eq(Recycle.golden(C, 3), false, "3: not yet")
end

print(string.format("Recycle: %d passed, %d failed", passed, failed))
if failed > 0 then error("Recycle spec failed", 0) end
