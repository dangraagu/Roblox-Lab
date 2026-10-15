-- Progress: streak, Heat, survivals, the Codex, and the profile a DataStore holds (DESIGN.md §2.6, §8.1).
-- Run: luau tests/Progress.spec.luau
local Progress = require("../src/shared/Progress")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

--======================================================================= a new profile

local p = Progress.default()
eq(p.survived, 0, "a new player has survived nothing")
eq(p.streak, 0, "streak 0")
eq(p.best, 0, "best 0")
eq(p.played, 0, "played 0")
eq(Progress.codexString(p), "-1,-1,-1,-1", "an empty Codex reads -1,-1,-1,-1 (meteor, flood, tornado, quake)")
eq(Progress.codexCount(p), 0, "0 of 24 Codex entries")
eq(Progress.heat(Config, p.streak), 0, "Heat 0")

--======================================================================= surviving and being swept out

do
	local ev = Progress.survive(p, Config, "flood", 0, 1000)
	eq(p.survived, 1, "a survival counts")
	eq(p.streak, 1, "streak 1")
	eq(p.best, 1, "best 1")
	eq(p.bestAt, 1000, "reached at the round's end time")
	eq(p.played, 1, "played 1")
	eq(p.codex.flood, 0, "the flood row is filled up to Heat 0")
	truthy(ev.newBest, "a new best is reported")
	Progress.survive(p, Config, "meteor", 0, 1100)
	eq(Progress.heat(Config, p.streak), 1, "two in a row: Heat 1")
	Progress.survive(p, Config, "quake", 1, 1200)
	eq(p.codex.quake, 1, "surviving a quake at Heat 1 fills its row to 1 ...")
	eq(Progress.codexCount(p), 1 + 1 + 2, "... which counts as two entries (0 and 1)")
	local before = p.best
	local bestAt = p.bestAt
	Progress.eliminate(p, "meteor")
	eq(p.streak, 0, "one hit: the streak is gone")
	eq(p.best, before, "best never goes down")
	eq(p.bestAt, bestAt, "and keeps when it was reached")
	eq(p.survived, 3, "survived never goes down")
	eq(p.codex.quake, 1, "the Codex never goes down")
	eq(p.played, 4, "an elimination is a played round")
	eq(p.lastEnd, nil, "a hit in a round is not a 'left' to tell on rejoin")
	Progress.survive(p, Config, "flood", 0, 1300)
	eq(p.best, 3, "a new streak of 1 does not touch best 3")
	eq(p.bestAt, 1200, "nor its time (ties go to whoever reached it first)")
	Progress.eliminate(p, "left")
	eq(p.lastEnd and p.lastEnd.reason, "left", "leaving during a round is remembered for the rejoin toast")
	eq(p.lastEnd and p.lastEnd.streak, 1, "with the streak it ended")
	eq(Progress.takeLastEnd(p) ~= nil, true, "the rejoin reads it once ...")
	eq(Progress.takeLastEnd(p), nil, "... and only once")
end

--======================================================================= the Codex rows are cumulative

do
	local q = Progress.default()
	Progress.survive(q, Config, "tornado", 5, 1)
	eq(q.codex.tornado, 5, "a Heat 5 tornado fills the whole tornado row")
	eq(Progress.codexCount(q), 6, "6 entries at once")
	Progress.survive(q, Config, "tornado", 2, 2)
	eq(q.codex.tornado, 5, "a later cooler survival never lowers it")
	for _, k in Config.Disasters.Kinds do Progress.survive(q, Config, k, 5, 3) end
	eq(Progress.codexCount(q), 24, "24 of 24")
end

--======================================================================= the brags

do
	local q = Progress.default()
	q.survived = 20
	local ev = Progress.survive(q, Config, "meteor", 0, 5)
	truthy(ev.brag, "the 21st survival is the brag (Falling Sky)")
	local ev2 = Progress.survive(q, Config, "meteor", 0, 6)
	eq(ev2.brag, false, "the 22nd is not")
	local r = Progress.default()
	r.streak = 9
	local ev3 = Progress.survive(r, Config, "flood", 4, 7)
	truthy(ev3.maxHeat, "a streak reaching 10 is MAX HEAT")
	r.streak = 0
	r.streak = 9
	local ev4 = Progress.survive(r, Config, "flood", 4, 8)
	eq(ev4.maxHeat, false, "MAX HEAT is told once per profile")
end

--======================================================================= normalise: whatever a DataStore hands back

do
	local n, warnings, newer = Progress.normalise(nil, Config)
	eq(n.survived, 0, "nil loads as a fresh profile")
	eq(newer, false, "and is not newer")
	eq(#warnings, 0, "with nothing to warn about")
	local raw = {
		v = 1, survived = -5, played = 3.7, streak = 12, best = 4, bestAt = 1700000000,
		codex = { meteor = 9, flood = -4, tornado = 2.5, quake = "x", bogus = 3 },
		lastEnd = { reason = "left", streak = 4 },
	}
	local m, w = Progress.normalise(raw, Config)
	eq(m.survived, 0, "a negative count is clamped to 0")
	eq(m.played, 3, "a non-integer is floored")
	eq(m.best, 12, "best below streak is raised to streak")
	eq(m.codex.meteor, 5, "a Codex value above 5 is clamped")
	eq(m.codex.flood, -1, "below -1 is clamped")
	eq(m.codex.tornado, 2, "a fraction is floored")
	eq(m.codex.quake, -1, "garbage is -1")
	eq(m.codex.bogus, nil, "an unknown Codex key is dropped")
	truthy(#w >= 5, "and every fix is warned about (" .. #w .. ")")
	eq(m.lastEnd and m.lastEnd.reason, "left", "lastEnd survives a load")
	local _, _, isNewer = Progress.normalise({ v = Config.Version + 1, survived = 3 }, Config)
	eq(isNewer, true, "a record with a higher version is flagged newer (shown read-only, never written)")
	-- integer keys round-trip through JSON as strings: the Codex is four named numbers, never an array
	local o, _ = Progress.normalise({ v = 1, codex = { ["1"] = 3, [2] = 4 } }, Config)
	eq(Progress.codexCount(o), 0, "array-shaped Codex data is not misread")
end

--======================================================================= what is saved: string keys only, small

local function allStringKeys(t: any, path: string): string?
	if type(t) ~= "table" then return nil end
	for k, v in t do
		if type(k) ~= "string" then return path .. "[" .. tostring(k) .. "]" end
		local bad = allStringKeys(v, path .. "." .. k)
		if bad then return bad end
	end
	return nil
end

local function json(v: any): string
	if type(v) == "table" then
		local parts = {}
		for k, x in v do table.insert(parts, string.format("%q:%s", tostring(k), json(x))) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

do
	local q = Progress.default()
	for _, k in Config.Disasters.Kinds do Progress.survive(q, Config, k, 5, 1) end
	q.survived, q.played, q.streak, q.best, q.bestAt = 999999, 999999, 999999, 999999, 2000000000
	q.lastEnd = { reason = "tornado", streak = 999999 }
	local saved = Progress.toSave(q)
	eq(allStringKeys(saved, "data"), nil, "every key in a saved profile is a string")
	local size = #json({ v = 1, data = saved, session = { token = string.rep("x", 36), expires = 2000000000 } })
	truthy(size <= 400, "a worst-case record is " .. size .. " bytes of JSON")
	print("  worst-case record: " .. size .. " bytes of JSON")
	local back = Progress.normalise(saved, Config)
	eq(back.best, 999999, "and it loads back")
	eq(Progress.codexString(back), "5,5,5,5", "Codex included")
end

--======================================================================= the board's metric: best streak, up to a cap (REVIEW-1 F5)

-- A script that reads the replicated red never misses (the review's bot: 40 of 40 rounds, best 40 in 59 minutes), and
-- the round clock alone does not bound it: it gains 40.9 an hour for as long as it runs. The board therefore counts a
-- best streak up to Config.Board.StreakCap, a run a fast human makes (REVIEW-1.md F5 has the model's numbers), so a
-- script can reach what a person can and nothing more. Ties at the cap go to whoever reached it FIRST.
do
	local BC = Config.Board
	eq(BC.StreakCap, 25, "the board counts a best streak up to 25")
	local p = Progress.default()
	local m, at = Progress.boardEntry(p, Config)
	eq(m, 0, "a new profile has nothing on the board")
	eq(at, 0, "and no time")
	for k = 1, 3 do Progress.survive(p, Config, "meteor", 0, 100 * k) end
	m, at = Progress.boardEntry(p, Config)
	eq(m, 3, "three in a row: 3 on the board")
	eq(at, 300, "reached at the third survival")
	for k = 4, 40 do Progress.survive(p, Config, "meteor", 5, 100 * k) end
	eq(p.best, 40, "the streak itself goes on past the cap (best 40, Heat and the Codex as before)")
	m, at = Progress.boardEntry(p, Config)
	eq(m, BC.StreakCap, "the board counts 25")
	eq(at, 2500, "reached when the streak first hit 25: going on to 40 never moves that time")
	Progress.eliminate(p, "meteor")
	for k = 1, 30 do Progress.survive(p, Config, "meteor", 5, 10000 + k) end
	m, at = Progress.boardEntry(p, Config)
	eq(at, 2500, "a second run past 25 keeps the first time")
	local back = Progress.normalise(Progress.toSave(p), Config)
	local m2, at2 = Progress.boardEntry(back, Config)
	eq(m2, BC.StreakCap, "saved and loaded: still 25")
	eq(at2, 2500, "and the time it was first reached")
	local old = Progress.normalise({ v = 1, best = 30, streak = 0, bestAt = 1700000000 }, Config)
	local m3, at3 = Progress.boardEntry(old, Config)
	eq(m3, BC.StreakCap, "a record over the cap with no capAt counts 25")
	eq(at3, 1700000000, "at its bestAt")
end

print(string.format("Progress: %d passed, %d failed", passed, failed))
assert(failed == 0, "Progress tests failed")
