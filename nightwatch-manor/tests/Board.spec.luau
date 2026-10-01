-- Board: the public + friends board of nights survived, its pure rules. Run from the game directory:
--   luau tests/Board.spec.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16). The metric is the best night the SERVER credited you with
-- surviving (Night.resolve on an EXTRACTED outcome, behind the crossing guard in Crossing.luau). Ties go to whoever
-- reached it FIRST. Stored in an OrderedDataStore under `u_<userId>` as `night * 2e9 + (2e9 - reachedAtUnix)`,
-- written only when the night improves. Public top 10 cached ~60 s; friends only on demand, capped, cached and
-- throttle-safe; an empty friends board says something useful. The server does the DataStore calls; every rule
-- they follow is here, pure.
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
eq(bc.MaxMetric, Config.Night.MaxNight, "the board's cap is the last night there is (Config.Night.MaxNight)")

--======================================================================= the stored value

eq(Board.encode(3, 1790000000, bc), 3 * 2e9 + (2e9 - 1790000000), "encode is night * 2e9 + (2e9 - reachedAt)")
eq(Board.encode(20, 1790000000, bc), 40210000000, "night 20 reached at 1790000000: 40 000 000 000 + 210 000 000")

-- an OrderedDataStore takes integers only, and the value has to be exact in a double
do
	local allInt, allExact = true, true
	for _, m in { 0, 1, 2, 19, 20, 40, 499, bc.MaxMetric } do
		for _, t in { 1600000000, 1790000000, 1999999999, 2200000000, 2800000000 } do
			local v = Board.encode(m, t, bc)
			if v % 1 ~= 0 then allInt = false end
			if v >= 2 ^ 53 or v + 1 == v then allExact = false end
		end
	end
	truthy(allInt, "every encoded value is an integer")
	truthy(allExact, "and exact in a double, up to the last night (" .. tostring(bc.MaxMetric) .. ")")
end

-- round trip, including past unix 2e9 (2033-05-18), where (2e9 - t) goes negative
do
	local ok, bad = true, nil
	for _, m in { 0, 1, 7, 20, 40, 333, bc.MaxMetric } do
		for _, t in { 1600000000, 1790000000, 1999999999, 2000000000, 2000000001, 2500000000, 2900000000 } do
			local dm, dt = Board.decode(Board.encode(m, t, bc))
			if dm ~= m or dt ~= t then ok = false; bad = bad or string.format("%d@%d -> %s@%s", m, t, tostring(dm), tostring(dt)) end
		end
	end
	truthy(ok, "decode(encode(night, t)) gives both back, 2020-2061" .. (if bad then " (" .. bad .. ")" else ""))
end

-- a later night always ranks higher, whenever it was reached; the same night goes to whoever got there first
do
	local times = { 1600000000, 1790000000, 1999999999, 2000000001, 2600000000 }
	local higherWins, firstWins = true, true
	for _, m in { 1, 2, 19, 20, 39, 40, 498 } do
		for _, a in times do
			for _, b in times do
				if not (Board.encode(m + 1, a, bc) > Board.encode(m, b, bc)) then higherWins = false end
				if a < b and not (Board.encode(m, a, bc) > Board.encode(m, b, bc)) then firstWins = false end
				if a > b and not (Board.encode(m, a, bc) < Board.encode(m, b, bc)) then firstWins = false end
			end
		end
	end
	truthy(higherWins, "a later night ranks above an earlier one, reached decades apart either way")
	truthy(firstWins, "the same night: the one reached EARLIER ranks first, the later one second")
end

eq(Board.encode(-5, 1790000000, bc), Board.encode(0, 1790000000, bc), "a negative night stores as 0")
eq(Board.encode(12.9, 1790000000, bc), Board.encode(12, 1790000000, bc), "a fractional night is floored")
eq(Board.encode(bc.MaxMetric + 50, 1790000000, bc), Board.encode(bc.MaxMetric, 1790000000, bc), "a night past the last is capped")
eq(Board.encode(0 / 0, 1790000000, bc), Board.encode(0, 1790000000, bc), "NaN stores as 0")
eq(Board.nightOf(nil), 0, "no stored value is night 0")
eq(Board.nightOf("12"), 0, "a stored value that is not a number is night 0")
eq(Board.nightOf(Board.encode(33, 1790000000, bc)), 33, "nightOf reads the night back")

--======================================================================= keys

eq(Board.key(4242), "u_4242", "the key is u_<userId> (a string: DataStore keys must be)")
eq(Board.userIdOf("u_4242"), 4242, "and reads back")
eq(Board.userIdOf("4242"), nil, "a key without the prefix is not a player")
eq(Board.userIdOf("u_12x"), nil, "nor is anything that is not a whole id")

--======================================================================= written only when the night improves

do
	local stored = Board.encode(10, 1790000000, bc)
	eq(Board.keepHigher(nil, stored), stored, "nothing stored: the first value is written")
	eq(Board.keepHigher("junk", stored), stored, "junk stored: it is replaced")
	eq(Board.keepHigher(stored, Board.encode(11, 1795000000, bc)), Board.encode(11, 1795000000, bc), "a later night replaces it")
	eq(Board.keepHigher(stored, Board.encode(10, 1780000000, bc)), nil,
		"the SAME night again, even stamped earlier, is not a write (the night did not improve)")
	eq(Board.keepHigher(stored, Board.encode(10, 1799000000, bc)), nil, "the same night reached later: no write, the first reach stands")
	eq(Board.keepHigher(stored, Board.encode(9, 1700000000, bc)), nil, "an earlier night never lowers the board")
end

--======================================================================= the public view

do
	local page = {
		{ userId = 5, value = Board.encode(40, 1790000000, bc) },
		{ userId = 3, value = Board.encode(12, 1780000000, bc) },
		{ userId = 9, value = Board.encode(12, 1785000000, bc) },
		{ userId = 7, value = Board.encode(0, 1785000000, bc) },
	}
	local v = Board.publicView(page, bc)
	eq(#v.rows, 3, "a player on night 0 (never got out) is not on the board")
	eq(v.rows[1].userId, 5, "row 1: the highest night")
	eq(v.rows[1].night, 40, "carrying the decoded night, never the stored value")
	eq(v.rows[1].rank, 1, "ranked 1")
	eq(v.rows[2].userId, 3, "in the order given (GetSortedAsync already sorted them)")
	eq(v.rows[3].rank, 3, "ranks count up")
	eq(v.note, nil, "a board with rows has no note")
	local empty = Board.publicView({}, bc)
	eq(#empty.rows, 0, "an empty store: no rows")
	eq(empty.note, bc.Text.EmptyPublic, "and it says so, usefully")
	truthy(type(bc.Text.EmptyPublic) == "string" and #bc.Text.EmptyPublic > 10, "the empty-public text is a real sentence")
end

--======================================================================= rank: ties and order

do
	local entries = {
		{ userId = 20, value = Board.encode(5, 1790000000, bc) },
		{ userId = 10, value = Board.encode(5, 1790000000, bc) },
		{ userId = 30, value = Board.encode(5, 1780000000, bc) },
		{ userId = 40, value = Board.encode(6, 1799999999, bc) },
	}
	local r = Board.rank(entries, 10)
	local ids = {}
	for _, e in r do table.insert(ids, tostring(e.userId)) end
	eq(table.concat(ids, ","), "40,30,10,20", "rank: the later night first, then the earlier reach, then (identical) the lower id")
	eq(#Board.rank(entries, 2), 2, "cut to n")
	eq(#entries, 4, "rank never changes its input")
end

--======================================================================= the friends view

do
	local VIEWER = 1
	local vals = {
		[1] = Board.encode(8, 1790000000, bc),
		[2] = Board.encode(20, 1790000000, bc),
		[3] = Board.encode(0, 1790000000, bc),
		[4] = Board.encode(8, 1780000000, bc),
	}
	local v = Board.friendsView(VIEWER, vals, { friendCount = 3, checked = 3 }, bc)
	local s = {}
	for _, r in v.rows do table.insert(s, string.format("%d:%d%s", r.userId, r.night, if r.you then "*" else "")) end
	eq(table.concat(s, " "), "2:20 4:8 1:8*", "friends: 20 first; on 8, the friend who got there first is above you; a friend on 0 is left out")
	eq(v.note, nil, "every friend checked: no note")

	-- the viewer always sees their own row, with their real rank, even below the shown rows
	local many = { [VIEWER] = Board.encode(1, 1790000000, bc) }
	for id = 100, 100 + bc.FriendsRows + 4 do many[id] = Board.encode(50, 1790000000 + id, bc) end
	local mv = Board.friendsView(VIEWER, many, { friendCount = bc.FriendsRows + 5, checked = bc.FriendsRows + 5 }, bc)
	eq(#mv.rows, bc.FriendsRows, "at most FriendsRows rows")
	local last = mv.rows[#mv.rows]
	eq(last.you, true, "the last row is the viewer's own when they rank below the rows shown")
	eq(last.rank, bc.FriendsRows + 6, "with their REAL rank (" .. tostring(bc.FriendsRows + 6) .. ")")

	-- notes: every empty case says something useful, and the order of the checks matters
	eq(Board.friendsView(VIEWER, { [VIEWER] = 0 }, { friendCount = 0, checked = 0 }, bc).note, bc.Text.NoFriends,
		"no friends: says friends you add show up here")
	eq(Board.friendsView(VIEWER, { [VIEWER] = 0, [2] = 0 }, { friendCount = 1, checked = 1 }, bc).note,
		string.format(bc.Text.FriendsNoScores, 1), "friends who never got out: says so, and invites")
	eq(Board.friendsView(VIEWER, { [VIEWER] = Board.encode(3, 1790000000, bc) }, { friendCount = 2, checked = 2 }, bc).note,
		string.format(bc.Text.FriendsNoScores, 2), "only YOU on the board: still 'none of your friends has'")
	eq(Board.friendsView(VIEWER, {}, { friendCount = 0, checked = 0, failed = true }, bc).note, bc.Text.FriendsFailed,
		"the friends call failed: says try again")
	eq(Board.friendsView(VIEWER, {}, { friendCount = 200, checked = 40 }, bc).note, string.format(bc.Text.FriendsChecking, 40, 200),
		"still reading: says how far it has got")
	for _, k in { "NoFriends", "FriendsNoScores", "FriendsFailed", "FriendsChecking", "Loading", "Title", "Prompt" } do
		truthy(type(bc.Text[k]) == "string" and #bc.Text[k] > 0, "Config.Board.Text." .. k .. " is written")
	end
end

--======================================================================= a TTL cache

do
	local c = Board.newCache(60)
	eq(Board.cacheGet(c, "k", 0), nil, "an empty cache has nothing")
	Board.cachePut(c, "k", 42, 100)
	eq(Board.cacheGet(c, "k", 159.9), 42, "fresh inside the TTL")
	eq(Board.cacheHas(c, "k", 160), false, "stale at exactly the TTL")
	eq(Board.cacheGet(c, "k", 200), nil, "and gone after it")
	Board.cachePut(c, "z", false, 0)
	eq(Board.cacheHas(c, "z", 1), true, "a cached false is still a hit (a friend who never got out is not re-read)")
end

--======================================================================= a token bucket (throttle-safe reads)

do
	local l = Board.newLimiter(40, 1, 0)
	local got = 0
	for _ = 1, 100 do if Board.take(l, 0) then got += 1 end end
	eq(got, 40, "the burst: 40 at once, then nothing")
	local more = 0
	for s = 1, 60 do if Board.take(l, s) then more += 1 end end
	eq(more, 60, "then one a second")
	-- over any window of T seconds, no more than capacity + rate * T
	local l2 = Board.newLimiter(bc.ReadsBurst, bc.ReadsPerSecond, 0)
	local taken, t = 0, 0
	while t <= 300 do
		if Board.take(l2, t) then taken += 1 end
		t += 0.05
	end
	truthy(taken <= bc.ReadsBurst + bc.ReadsPerSecond * 300 + 1,
		string.format("300 s of hammering: %d reads, never more than burst + rate x 300 (%d)", taken, bc.ReadsBurst + bc.ReadsPerSecond * 300))
	truthy(bc.ReadsPerSecond * 60 <= 60, "the steady rate stays inside Roblox's 60 + 10/player GetAsync per minute on its own")
	eq(bc.FriendsCap, 200, "friends are read up to 200, never the whole list")
end

--======================================================================= what the physical board prints

do
	eq(Board.rowText({ rank = 1, name = "Ava", night = 20 }, bc), "1. Ava   night 20",
		"a row: rank, name, the night survived")
	eq(Board.rowText({ rank = 4, name = "Bo", night = 7, you = true }, bc), "4. Bo (you)   night 7", "your own row says so")
	eq(Board.rowText({ rank = 2, night = 3 }, bc), "2. ?   night 3", "a name that never arrived prints as ?")
end

--======================================================================= CONTROL

-- Rewording the board's texts changes nothing it ranks or stores.
do
	local before = bc.Text.EmptyPublic
	bc.Text.EmptyPublic = "Nobody yet."
	local v1 = Board.encode(20, 1790000000, bc)
	local ok = v1 == 40210000000 and Board.publicView({}, bc).note == "Nobody yet."
	bc.Text.EmptyPublic = before
	truthy(ok, "CONTROL: rewording a board text changes no stored value")
end

print(string.format("Board: %d passed, %d failed", passed, failed))
if failed > 0 then error("Board tests failed") end
