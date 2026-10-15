-- Spec for Board: the Cases Solved board's pure rules (DESIGN.md §11, docs/complete-game-standard.md §3).
-- Run: luau tests/Board.spec.luau 2>&1
--
-- Rank on Cases Solved, ties to whoever reached it FIRST. OrderedDataStore key `u_<userId>`, value
-- `solved * 2e9 + (2e9 - reachedAtUnix)`, written only when the count rises, through an UpdateAsync transform
-- that keeps max(old, new). Adapted from escape-room-lab/tests/Board.spec.luau (itself plus1-jump's, plus the
-- review fixes: 0 stores as 0, the reach time is clamped, friend reads are paced by the request budget):
-- the metric here is Cases Solved (capped at Config.Board.MaxMetric), and rows carry `solved`.
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")

local bc = Config.Board

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local NOW = 1790726400 -- 2026-09-30 00:00 UTC

eq(bc.MaxMetric, 100000, "the metric is capped at 100000 Cases Solved (273 years of Daily Cases)")
truthy(Board.encode(bc.MaxMetric, NOW, bc) < 2 ^ 53, "the largest possible value is under 2^53 (" .. Board.encode(bc.MaxMetric, NOW, bc) .. ")")
-- [M 6]: after ten years of Daily Cases (15 + 3653 = 3668) the value is 7.336e12
eq(Board.encode(3668, 1791331200, bc), 3668 * 2e9 + (2e9 - 1791331200), "ten years of Daily Cases encodes exactly")

--============================================================ the value, at the extremes of [M 6]
eq(Board.encode(45, NOW, bc), 90209273600, "45 * 2e9 + (2e9 - now) = 90 209 273 600")
truthy(Board.encode(45, NOW, bc) < 2 ^ 53, "under 2^53")
eq(Board.encode(45, NOW, bc) % 1, 0, "an integer (an OrderedDataStore refuses anything else)")
eq(Board.encode(3, 1790000000, bc), 3 * 2e9 + (2e9 - 1790000000), "encode is the owner's formula")
do
	local ok = true
	-- 0 stars is never on the board and stores as 0 with no reach time (see below), so the round trip
	-- of the reach time is for 1..45 stars
	for _, s in { 1, 2, 17, 44, 45 } do
		for _, t in { Board.EPOCH, NOW, NOW + 1, 1999999999, 2000000001, Board.EPOCH + 2e9 - 1 } do
			local m, at = Board.decode(Board.encode(s, t, bc))
			if m ~= s or at ~= t then ok = false end
		end
	end
	truthy(ok, "decode(encode(solved, t)) round-trips for every reach from 2026-09-21 to 2090-01")
	truthy(Board.EPOCH <= NOW, "the decode window starts before the game's first reach")
	local order = true
	local last = NOW + 2e9 - 1
	for s = 0, 200 do
		if not (Board.encode(s + 1, last, bc) > Board.encode(s, NOW, bc)) then order = false end
	end
	truthy(order, "one more case always ranks higher, even reached 63 years later")
	truthy(Board.encode(45, NOW, bc) > Board.encode(45, NOW + 1, bc), "the same count: the EARLIER reach ranks higher")
end
eq(Board.encode(bc.MaxMetric + 5, NOW, bc), Board.encode(bc.MaxMetric, NOW, bc), "a count above MaxMetric is capped")
eq(Board.encode(-1, NOW, bc), Board.encode(0, NOW, bc), "a negative total stores as 0")
-- review 2026-10-01: a fresh profile (starsAt = 0) encoded to 2e9, which decodes as ONE star; every
-- 0-star viewer showed on their own friends board with a star they never earned
eq(Board.encode(0, 0, bc), 0, "no cases stores as 0, whatever the reach time")
eq(Board.metricOf(Board.encode(0, 0, bc)), 0, "a fresh profile (solvedAt 0) reads as 0 cases, not 1")
do
	local bad = nil
	for m = 0, 45 do
		for _, at in { 0, 1, 1e9, Board.EPOCH - 1, Board.EPOCH, NOW, Board.EPOCH + 2e9 - 1, Board.EPOCH + 2e9, 2 ^ 31 } do
			if Board.metricOf(Board.encode(m, at, bc)) ~= m then bad = bad or string.format("%d cases at %d", m, at) end
		end
	end
	eq(bad, nil, "the metric survives ANY reach time, inside the exact range or not (the time part is clamped)")
	truthy(Board.encode(10, Board.EPOCH - 50, bc) >= Board.encode(10, Board.EPOCH, bc), "a reach before the range ranks as the range's first moment, never lower")
end
eq(Board.encode(0 / 0, NOW, bc), Board.encode(0, NOW, bc), "NaN stores as 0")
eq(Board.encode(12.7, NOW, bc), Board.encode(12, NOW, bc), "a fraction is floored")

--============================================================ keys
eq(Board.key(4242), "u_4242", "the key is u_<userId>")
eq(Board.userIdOf("u_4242"), 4242, "and reads back")
eq(Board.userIdOf("x_1"), nil, "another shape is not a user")

--============================================================ writes: only on improvement, keep max
eq(Board.improves(nil, 1), true, "nothing stored: 1 case improves")
eq(Board.improves(nil, 0), false, "0 cases is not worth a write")
eq(Board.improves(Board.encode(12, NOW, bc), 12), false, "the same total: no write")
eq(Board.improves(Board.encode(12, NOW, bc), 11), false, "a lower total: no write")
eq(Board.improves(Board.encode(12, NOW, bc), 13), true, "a higher total: write")
do
	local stored = Board.encode(20, NOW, bc)
	eq(Board.keepHigher(nil, Board.encode(5, NOW, bc)), Board.encode(5, NOW, bc), "empty: take the new value")
	eq(Board.keepHigher(stored, Board.encode(19, NOW - 99, bc)), nil, "a lower total (reached earlier) aborts")
	eq(Board.keepHigher(stored, Board.encode(20, NOW + 5, bc)), nil, "the same total reached LATER aborts: the first reach stands")
	eq(Board.keepHigher(stored, Board.encode(21, NOW + 5, bc)), Board.encode(21, NOW + 5, bc), "a higher total is written")
	eq(Board.keepHigher("junk", Board.encode(3, NOW, bc)), Board.encode(3, NOW, bc), "a non-number stored value is replaced")
end

--============================================================ ranking and the two views
do
	local entries = {
		{ userId = 30, value = Board.encode(40, NOW + 50, bc) },
		{ userId = 10, value = Board.encode(12, NOW, bc) },
		{ userId = 20, value = Board.encode(40, NOW + 10, bc) },
		{ userId = 40, value = Board.encode(45, NOW + 99, bc) },
		{ userId = 5, value = Board.encode(40, NOW + 10, bc) },
	}
	local ids = {}
	for _, e in Board.rank(entries, 10) do table.insert(ids, e.userId) end
	eq(table.concat(ids, ","), "40,5,20,30,10", "count, then earliest, then the lower user id")
	eq(#Board.rank(entries, 3), 3, "top n")
end
do
	local v = Board.publicView({ { userId = 7, value = Board.encode(45, NOW, bc) }, { userId = 8, value = Board.encode(9, NOW, bc) } }, bc)
	eq(#v.rows, 2, "public: one row each")
	eq(v.rows[1].solved, 45, "rows carry the decoded Cases Solved, not the stored value")
	eq(v.rows[1].rank, 1, "numbered")
	eq(v.note, nil, "no note when there are rows")
	local empty = Board.publicView({}, bc)
	truthy(type(empty.note) == "string" and #empty.note > 10, "an empty public board says something (" .. tostring(empty.note) .. ")")
end
-- REVIEW-1 A5: an exact tie (the same count reached on the same day) shares its rank, 1, 1, 3
do
	local tie = Board.encode(20, NOW, bc)
	local v = Board.publicView({ { userId = 1, value = tie }, { userId = 2, value = tie }, { userId = 3, value = Board.encode(19, NOW, bc) } }, bc)
	eq(v.rows[1].rank, 1, "A5 public: the first of two tied rows is 1")
	eq(v.rows[2].rank, 1, "A5 public: the second tied row is 1 too")
	eq(v.rows[3].rank, 3, "A5 public: the next row is 3 (competition ranking)")
	local me = 2
	local f = Board.friendsView(me, { [1] = tie, [2] = tie, [3] = Board.encode(19, NOW, bc) }, { friendCount = 2, checked = 2, failed = false }, bc)
	eq(f.rows[1].rank, 1, "A5 friends: tied rows share rank 1")
	eq(f.rows[2].rank, 1, "A5 friends: ...")
	eq(f.rows[3].rank, 3, "A5 friends: then 3")
end
do
	local me = 100
	local values = {
		[100] = Board.encode(30, NOW + 5, bc),
		[201] = Board.encode(44, NOW, bc),
		[202] = Board.encode(30, NOW + 1, bc),
		[203] = Board.encode(0, NOW, bc),
	}
	local v = Board.friendsView(me, values, { friendCount = 3, checked = 3, failed = false }, bc)
	local ids = {}
	for _, r in v.rows do table.insert(ids, tostring(r.userId) .. (if r.you then "*" else "")) end
	eq(table.concat(ids, ","), "201,202,100*", "friends: highest first, earliest on a tie, me marked")
	local many = { [me] = Board.encode(1, NOW, bc) }
	for i = 1, 30 do many[1000 + i] = Board.encode(math.min(45, 2 + i), NOW, bc) end
	local m = Board.friendsView(me, many, { friendCount = 30, checked = 30, failed = false }, bc)
	eq(#m.rows, bc.FriendsRows, "Config.Board.FriendsRows rows")
	eq(m.rows[#m.rows].you, true, "outside the top, the last row is me")
	eq(m.rows[#m.rows].rank, 31, "with my real rank")
	local failedV = Board.friendsView(me, { [me] = Board.encode(5, NOW, bc) }, { friendCount = 0, checked = 0, failed = true }, bc)
	local none = Board.friendsView(me, { [me] = Board.encode(5, NOW, bc) }, { friendCount = 0, checked = 0, failed = false }, bc)
	local quiet = Board.friendsView(me, { [me] = Board.encode(5, NOW, bc) }, { friendCount = 4, checked = 4, failed = false }, bc)
	local busy = Board.friendsView(me, { [me] = Board.encode(5, NOW, bc) }, { friendCount = 120, checked = 40, failed = false }, bc)
	eq(failedV.note, bc.Text.FriendsFailed, "failed: the failure text")
	eq(none.note, bc.Text.NoFriends, "no friends: the empty text")
	truthy(string.find(quiet.note, "4", 1, true) ~= nil, "none of them has solved a case: says how many were checked (" .. quiet.note .. ")")
	truthy(string.find(busy.note, "40 of 120", 1, true) ~= nil, "still loading: Checking your friends: 40 of 120... (" .. busy.note .. ")")
	truthy(string.find(bc.Text.NoFriends, "Invite one", 1, true) ~= nil, "the empty friends board says something useful (" .. bc.Text.NoFriends .. ")")
	truthy(string.find(bc.Text.NoFriends, "every room is different", 1, true) ~= nil, "and why inviting is fair: nobody can tell them where things are")
	-- the request budget ran out before every friend was read: the view is final, and says how far it got
	local partial = Board.friendsView(me, { [me] = Board.encode(5, NOW, bc) }, { friendCount = 120, checked = 40, failed = false, partial = true }, bc)
	eq(partial.note, string.format(bc.Text.FriendsPartial, 40, 120), "partial: the request-limit text, not 'Loading'")
	truthy(string.find(partial.note, "40 of 120", 1, true) ~= nil, "it names how many were checked (" .. partial.note .. ")")
end

--============================================================ caches and the request-budget pacer
do
	local c = Board.newCache(60)
	Board.cachePut(c, "a", 42, 100)
	eq(Board.cacheGet(c, "a", 159.9), 42, "cached until its ttl")
	eq(Board.cacheGet(c, "a", 160), nil, "and not after")
	Board.cachePut(c, "b", false, 0)
	eq(Board.cacheHas(c, "b", 1), true, "a cached false is a hit")
end
eq(Board.mayRead(21, bc.GetAsyncReserve), true, "a budget above the reserve of 20: read")
eq(Board.mayRead(20, bc.GetAsyncReserve), false, "at the reserve: wait (profile loads keep their room)")
eq(Board.mayRead(0, bc.GetAsyncReserve), false, "empty: wait")
eq(Board.mayRead(nil, bc.GetAsyncReserve), false, "unknown budget: wait")
eq(Board.mayRead(0 / 0, bc.GetAsyncReserve), false, "NaN budget: wait")
eq(bc.GetAsyncReserve, 20, "the reserve is 20 [DESIGN §11]")
-- one friend-score read: read above the reserve; at or under it wait, a second at a time, up to the cap;
-- then stop and show what was read (review 2026-10-01: concurrent fetches all passed the check at once)
eq(Board.readStep(21, bc.GetAsyncReserve, 0, bc.FriendReadMaxWaitSeconds), "read", "budget above the reserve: read")
eq(Board.readStep(20, bc.GetAsyncReserve, 0, bc.FriendReadMaxWaitSeconds), "wait", "at the reserve: wait")
eq(Board.readStep(nil, bc.GetAsyncReserve, 5, bc.FriendReadMaxWaitSeconds), "wait", "unknown budget: wait")
eq(Board.readStep(3, bc.GetAsyncReserve, bc.FriendReadMaxWaitSeconds - 1, bc.FriendReadMaxWaitSeconds), "wait", "still under the wait cap: wait")
eq(Board.readStep(3, bc.GetAsyncReserve, bc.FriendReadMaxWaitSeconds, bc.FriendReadMaxWaitSeconds), "stop", "waited the cap: stop (the rest next time)")
eq(Board.readStep(0 / 0, bc.GetAsyncReserve, bc.FriendReadMaxWaitSeconds, bc.FriendReadMaxWaitSeconds), "stop", "NaN budget past the cap: stop")
eq(bc.FriendReadMaxWaitSeconds, 30, "a read waits at most 30 s for budget")
eq(bc.FriendCap, 200, "friends are capped at 200")
eq(bc.PublicRows, 10, "the public view is the top 10")
eq(bc.PublicCacheSeconds, 60, "cached 60 s")
eq(bc.FriendListCacheSeconds, 300, "friend lists cached 300 s")
eq(bc.Store, "FindIt_Solved_v1", "the ordered store")

print(string.format("Board: %d passed, %d failed", passed, failed))
if failed > 0 then error("Board spec failed", 0) end
