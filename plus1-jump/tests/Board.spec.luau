-- Board: the public + friends highscore board's pure rules. Run: luau tests/Board.spec.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric, ties broken by who
-- reached it FIRST, stored in an OrderedDataStore under `u_<userId>` as `metric * 2e9 + (2e9 - reachedAtUnix)`,
-- written only when the metric improves; public top 10 cached ~60 s; friends fetched on demand, capped,
-- cached and throttle-safe; an empty friends board says something useful.
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")

local bc = Config.Board

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

truthy(type(bc) == "table", "Config.Board exists")

--======================================================================= the stored value

-- the owner's formula, verbatim
eq(Board.encode(3, 1790000000, bc), 3 * 2e9 + (2e9 - 1790000000), "encode is metric * 2e9 + (2e9 - reachedAt)")
eq(Board.encode(85, 1790000000, bc), 170210000000, "tier 85 reached at 1790000000: 170 000 000 000 + 210 000 000")

-- every stored value is an integer (an OrderedDataStore refuses anything else) and exact in a double
do
	local allInt, allExact = true, true
	for _, m in { 0, 1, 2, 85, 240, 1000, bc.MaxMetric } do
		for _, t in { 1600000000, 1790000000, 1999999999, 2200000000, 2800000000 } do
			local v = Board.encode(m, t, bc)
			if v % 1 ~= 0 then allInt = false end
			if v >= 2 ^ 53 or v + 1 == v then allExact = false end
		end
	end
	truthy(allInt, "every encoded value is an integer")
	truthy(allExact, "and exact in a double, up to Config.Board.MaxMetric (" .. tostring(bc.MaxMetric) .. ")")
end

-- round trip, including after the 32-bit rollover of 2e9 (2033-05-18)
do
	local ok, bad = true, nil
	for _, m in { 0, 1, 7, 85, 240, 12345, bc.MaxMetric } do
		for _, t in { 1600000000, 1790000000, 1999999999, 2000000000, 2000000001, 2500000000, 2900000000 } do
			local dm, dt = Board.decode(Board.encode(m, t, bc))
			if dm ~= m or dt ~= t then ok = false; bad = bad or string.format("%d@%d -> %s@%s", m, t, tostring(dm), tostring(dt)) end
		end
	end
	truthy(ok, "decode(encode(metric, t)) gives both back, 2020-2061" .. (if bad then " (" .. bad .. ")" else ""))
end

-- ordering: a higher metric always wins, whenever it was reached; the same metric goes to whoever was first
do
	local times = { 1600000000, 1790000000, 1999999999, 2000000001, 2600000000 }
	local higherWins, firstWins = true, true
	for _, m in { 1, 2, 84, 85, 239, 240 } do
		for _, a in times do
			for _, b in times do
				if not (Board.encode(m + 1, a, bc) > Board.encode(m, b, bc)) then higherWins = false end
				if a < b and not (Board.encode(m, a, bc) > Board.encode(m, b, bc)) then firstWins = false end
			end
		end
	end
	truthy(higherWins, "a higher metric ranks above a lower one, reached decades apart either way")
	truthy(firstWins, "the same metric: the one reached EARLIER ranks first")
end

-- a metric is a whole, non-negative number, capped where the value stays exact
eq(Board.encode(-5, 1790000000, bc), Board.encode(0, 1790000000, bc), "a negative metric stores as 0")
eq(Board.encode(12.9, 1790000000, bc), Board.encode(12, 1790000000, bc), "a fractional metric is floored")
eq(Board.encode(bc.MaxMetric + 50, 1790000000, bc), Board.encode(bc.MaxMetric, 1790000000, bc), "a huge metric is capped")
eq(Board.encode(0 / 0, 1790000000, bc), Board.encode(0, 1790000000, bc), "NaN stores as 0")

--======================================================================= keys

eq(Board.key(4242), "u_4242", "the key is u_<userId> (a string: DataStore keys must be)")
eq(Board.userIdOf("u_4242"), 4242, "and reads back")
eq(Board.userIdOf("x_4242"), nil, "a key of another shape is not a user")

--======================================================================= write only when the metric improves

-- the UpdateAsync transform never lowers what is stored, and aborts (nil) rather than rewriting the same value
do
	local stored = Board.encode(20, 1780000000, bc)
	eq(Board.keepHigher(nil, Board.encode(5, 1790000000, bc)), Board.encode(5, 1790000000, bc), "empty: take the new value")
	eq(Board.keepHigher(stored, Board.encode(19, 1700000000, bc)), nil, "a lower metric (even reached earlier) aborts")
	eq(Board.keepHigher(stored, stored), nil, "the same value aborts (no write)")
	eq(Board.keepHigher(stored, Board.encode(20, 1790000000, bc)), nil, "the same metric reached LATER aborts: the first reach stands")
	eq(Board.keepHigher(stored, Board.encode(21, 1790000000, bc)), Board.encode(21, 1790000000, bc), "a higher metric is written")
	eq(Board.keepHigher("junk", Board.encode(3, 1790000000, bc)), Board.encode(3, 1790000000, bc), "a non-number stored value is replaced")
end

--======================================================================= ranking

do
	local t0 = 1790000000
	local entries = {
		{ userId = 30, value = Board.encode(85, t0 + 50, bc) },
		{ userId = 10, value = Board.encode(12, t0, bc) },
		{ userId = 20, value = Board.encode(85, t0 + 10, bc) }, -- reached 85 first
		{ userId = 40, value = Board.encode(240, t0 + 99, bc) },
		{ userId = 5, value = Board.encode(85, t0 + 10, bc) }, -- same second as 20: lower id first, for a stable board
	}
	local r = Board.rank(entries, 10)
	local ids = {}
	for _, e in r do table.insert(ids, e.userId) end
	eq(table.concat(ids, ","), "40,5,20,30,10", "rank: metric first, then earliest, then the lower user id")
	eq(#entries, 5, "rank does not modify its input")
	eq(#Board.rank(entries, 3), 3, "rank keeps the top n")
end

--======================================================================= the two views

do
	local t0 = 1790000000
	local sorted = {
		{ userId = 7, value = Board.encode(240, t0, bc) },
		{ userId = 8, value = Board.encode(85, t0, bc) },
	}
	local v = Board.publicView(sorted, bc)
	eq(#v.rows, 2, "public view: one row per entry")
	eq(v.rows[1].rank, 1, "rows are numbered")
	eq(v.rows[1].tier, 240, "and carry the decoded metric, not the stored value")
	eq(v.rows[2].userId, 8, "in the order given (GetSortedAsync already sorted them)")
	eq(v.note, nil, "a public board with climbers needs no note")
	local empty = Board.publicView({}, bc)
	eq(#empty.rows, 0, "an empty public board has no rows")
	truthy(type(empty.note) == "string" and #empty.note > 10, "and says something useful (" .. tostring(empty.note) .. ")")
	local zero = Board.publicView({ { userId = 9, value = Board.encode(0, t0, bc) } }, bc)
	eq(#zero.rows, 0, "a stored tier 0 is not a climber")
end

do
	local t0 = 1790000000
	local me = 100
	local values = {
		[100] = Board.encode(30, t0 + 5, bc),
		[201] = Board.encode(85, t0, bc),
		[202] = Board.encode(30, t0 + 1, bc), -- same tier as me, reached earlier
		[203] = Board.encode(0, t0, bc),      -- never climbed
	}
	local v = Board.friendsView(me, values, { friendCount = 3, checked = 3, failed = false }, bc)
	local ids = {}
	for _, r in v.rows do table.insert(ids, tostring(r.userId) .. (if r.you then "*" else "")) end
	eq(table.concat(ids, ","), "201,202,100*", "friends view: my friends and me, highest first, earliest on a tie; me marked")
	eq(v.rows[3].rank, 3, "my row has my real rank")
	eq(v.note, nil, "every friend checked, some have climbed: no note")

	-- more friends than rows: I still see where I stand
	local many = { [me] = Board.encode(2, t0, bc) }
	for i = 1, 30 do many[1000 + i] = Board.encode(10 + i, t0, bc) end
	local m = Board.friendsView(me, many, { friendCount = 30, checked = 30, failed = false }, bc)
	eq(#m.rows, bc.FriendsRows, "the friends view shows Config.Board.FriendsRows rows")
	eq(m.rows[#m.rows].you, true, "and when I am outside the top, the last row is me")
	eq(m.rows[#m.rows].rank, 31, "with my real rank (31st of 31)")
	eq(m.rows[1].tier, 40, "the top row is the best friend")

	-- the empty cases each say something useful, and different things
	local failedV = Board.friendsView(me, { [me] = Board.encode(5, t0, bc) }, { friendCount = 0, checked = 0, failed = true }, bc)
	local none = Board.friendsView(me, { [me] = Board.encode(5, t0, bc) }, { friendCount = 0, checked = 0, failed = false }, bc)
	local quiet = Board.friendsView(me, { [me] = Board.encode(5, t0, bc), [301] = Board.encode(0, t0, bc) },
		{ friendCount = 4, checked = 4, failed = false }, bc)
	local busy = Board.friendsView(me, { [me] = Board.encode(5, t0, bc), [301] = Board.encode(9, t0, bc) },
		{ friendCount = 120, checked = 40, failed = false }, bc)
	for name, view in { failed = failedV, nofriends = none, noscores = quiet, checking = busy } do
		truthy(type(view.note) == "string" and #view.note > 10, "friends view, " .. name .. ": says something (" .. tostring(view.note) .. ")")
	end
	truthy(failedV.note ~= none.note and none.note ~= quiet.note and quiet.note ~= busy.note,
		"and the four notes differ (failed / no friends / none climbed / still checking)")
	truthy(string.find(quiet.note, "4", 1, true) ~= nil, "none climbed: names how many friends were checked (" .. quiet.note .. ")")
	truthy(string.find(busy.note, "40", 1, true) ~= nil and string.find(busy.note, "120", 1, true) ~= nil,
		"still checking: says how far (" .. busy.note .. ")")
	eq(#none.rows, 1, "with no friends I still see my own row")
	eq(#Board.friendsView(me, {}, { friendCount = 0, checked = 0, failed = false }, bc).rows, 0,
		"and with nothing climbed at all, no rows (the note speaks)")
end

--======================================================================= the caches

do
	local c = Board.newCache(60)
	eq(Board.cacheGet(c, "a", 0), nil, "an empty cache has nothing")
	Board.cachePut(c, "a", 42, 100)
	eq(Board.cacheGet(c, "a", 100), 42, "a fresh entry is returned")
	eq(Board.cacheGet(c, "a", 159.9), 42, "until its ttl")
	eq(Board.cacheGet(c, "a", 160), nil, "and not after")
	Board.cachePut(c, "b", false, 0)
	eq(Board.cacheGet(c, "b", 1), false, "a cached false is a hit, not a miss")
	eq(Board.cacheHas(c, "b", 1), true, "cacheHas tells a cached false from a miss")
	eq(Board.cacheHas(c, "zz", 1), false, "and a miss from a hit")
end

--======================================================================= the read limiter

do
	local l = Board.newLimiter(3, 0.5, 0)
	eq(Board.take(l, 0), true, "limiter: 1 of a burst of 3")
	eq(Board.take(l, 0), true, "2 of 3")
	eq(Board.take(l, 0), true, "3 of 3")
	eq(Board.take(l, 0), false, "the 4th in the same instant is refused")
	eq(Board.take(l, 1.9), false, "0.5 per second: not yet one back after 1.9 s")
	eq(Board.take(l, 2.0), true, "one back after 2 s")
	eq(Board.take(l, 2.0), false, "and only one")
	eq(Board.take(l, 1000), true, "a long pause refills")
	local burst = 0
	for _ = 1, 10 do if Board.take(l, 1000) then burst += 1 end end
	eq(burst, 2, "but never past the burst size (3 total after the pause)")
	-- over a minute a limiter never gives more than burst + rate * 60
	local l2 = Board.newLimiter(bc.ReadsBurst, bc.ReadsPerSecond, 0)
	local got = 0
	for i = 0, 600 do if Board.take(l2, i * 0.1) then got += 1 end end
	local ceiling = bc.ReadsBurst + bc.ReadsPerSecond * 60
	truthy(got <= ceiling and got >= ceiling - 1,
		"the friends' score reads over 60 s: burst + rate * 60 at most, and not stingier (" .. got .. " of " .. ceiling .. ")")
	truthy(bc.ReadsPerSecond * 60 <= 60, "and the sustained rate stays inside Roblox's base GetAsync budget of 60 per minute")
end

--======================================================================= the HUD panel (Studio 2026-10-09)
-- Real Studio, night shift 2026-10-09: with no climbers stored, the HUD's 🏆 TOP CLIMBERS panel on the right was
-- an empty dark box, while the board on the pad said "No climbers on the board yet...". A new store
-- (Plus1Jump_LB_v2) starts empty on the live game too, so every early player would see the blank box.
do
	local t0 = 1790000000
	local note = Board.hudNote({}, bc)
	truthy(type(note) == "string" and #note > 5, "an empty HUD panel says something (" .. tostring(note) .. ")")
	truthy(type(note) == "string" and #note <= 40, "and short enough for the narrow panel (" .. tostring(note and #note) .. " <= 40)")
	eq(Board.hudNote({ { userId = 7, tier = 3 } }, bc), nil, "a HUD panel with climbers needs no note")
	local rows = Board.publicView({ { userId = 9, value = Board.encode(0, t0, bc) } }, bc).rows
	truthy(Board.hudNote(rows, bc) ~= nil, "a board holding only tier 0 is empty on the HUD too")
end

print(string.format("Board: %d passed, %d failed", passed, failed))
assert(failed == 0, "Board tests failed")
