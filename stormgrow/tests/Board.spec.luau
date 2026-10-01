-- Spec for Board: the Almanac highscore board, public and friends. Run: luau tests/Board.spec.luau
--
-- DESIGN.md §7 and the owner's standard §3: rank on a server-measured metric (Almanac entries, 0-56),
-- ties broken by who reached the count FIRST, stored as count * 2e9 + (2e9 - reachedAtUnix) in an
-- OrderedDataStore under "u_<userId>", written only upward. The emulator has no GetFriendsAsync, so the
-- friends view is assembled here, from plain lists, where it can be tested.
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local B = Config.Board

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

--================================================================ the value

eq(B.Epoch, 2e9, "Config.Board.Epoch is 2e9 (publicRows and friendsView decode with it)")

do
	local v = Board.encode(12, 1790002800, B)
	eq(v, 12 * 2e9 + (2e9 - 1790002800), "value = count * 2e9 + (2e9 - reachedAt)")
	eq(v % 1, 0, "an integer (OrderedDataStore takes integers only)")
	local c, at = Board.decode(v, B)
	eq(c, 12, "decode: count")
	eq(at, 1790002800, "decode: reachedAt")
	truthy(Board.encode(13, 1790009999, B) > Board.encode(12, 1790000000, B), "more entries always rank higher")
	truthy(Board.encode(12, 1790000000, B) > Board.encode(12, 1790000001, B), "equal counts: whoever got there FIRST ranks higher")
	local top = Board.encode(56, 0, B)
	truthy(top < 2 ^ 53, "the largest value (" .. top .. ") is far under 2^53")
	eq(top, 1.14e11, "and is 1.14e11 as DESIGN.md says")
	eq(Board.encode(0, 1790000000, B), 0, "a count of 0 is never written (value 0)")
	-- the horizon: 2e9 - reachedAt stays positive until Unix 2e9
	truthy(Board.encode(1, 1999999999, B) > Board.encode(0, 0, B), "tie-break still valid in 2033")
	-- fractional times are floored (a strike tick's clock is fractional)
	eq(Board.encode(3, 1790000000.9, B) % 1, 0, "a fractional reachedAt still encodes an integer")
end

--================================================================ writes only go up

do
	local tf = Board.transform(Board.encode(5, 100, B))
	eq(tf(nil), Board.encode(5, 100, B), "no stored value: write ours")
	eq(tf(Board.encode(4, 50, B)), Board.encode(5, 100, B), "a lower stored value is replaced")
	eq(tf(Board.encode(6, 50, B)), nil, "a higher stored value aborts the write (a stale server never lowers a score)")
	eq(tf(Board.encode(5, 100, B)), nil, "an equal value aborts too (nothing to write)")
	eq(tf("junk"), Board.encode(5, 100, B), "a junk stored value is replaced")
end

do
	-- coalescing: at most one write per player per 30 s, and only when the count went up
	local st = Board.newWriter()
	eq(Board.due(st, Board.encode(1, 10, B), 1000, B), true, "the first improvement is due at once")
	Board.wrote(st, Board.encode(1, 10, B), 1000)
	eq(Board.due(st, Board.encode(1, 10, B), 1100, B), false, "the same value is never written twice")
	eq(Board.due(st, Board.encode(2, 20, B), 1010, B), false, "an improvement 10 s later waits")
	eq(Board.due(st, Board.encode(2, 20, B), 1030, B), true, "30 s after the last write it is due")
	eq(Board.due(st, Board.encode(2, 20, B), 1010, B, true), true, "a flush on leave ignores the 30 s")
	eq(Board.due(st, 0, 1010, B, true), false, "a zero count is never written, even on flush")
end

--================================================================ keys

eq(Board.keyOf(123), "u_123", "the key is u_<userId>, a string")
eq(Board.userIdOf("u_123"), 123, "and parses back")
eq(Board.userIdOf("x_1"), nil, "a foreign key parses to nil")
eq(Board.userIdOf("u_"), nil, "an empty id parses to nil")

--================================================================ the public view

do
	local page = {
		{ key = "u_1", value = Board.encode(30, 100, B) },
		{ key = "u_2", value = Board.encode(29, 100, B) },
		{ key = "junk", value = Board.encode(28, 100, B) },
		{ key = "u_3", value = Board.encode(10, 100, B) },
	}
	local rows = Board.publicRows(page, 2)
	eq(#rows, 2, "shows at most the requested number of rows")
	eq(rows[1].userId, 1, "rank 1 first")
	eq(rows[1].rank, 1, "numbered")
	eq(rows[1].count, 30, "with the count decoded")
	eq(rows[2].userId, 2, "rank 2 second")
	local all = Board.publicRows(page, 10)
	eq(#all, 3, "junk keys are skipped")
	eq(all[3].rank, 3, "and ranks stay consecutive")
	eq(#Board.publicRows({}, 10), 0, "an empty store gives no rows")
end

--================================================================ the friends view

do
	local me = 100
	local friends = { [201] = true, [202] = true, [203] = true }
	-- sources: players in this server (from memory) and the top-500 cache; duplicates and strangers mixed in
	local sources = {
		{ userId = 100, value = Board.encode(7, 50, B) }, -- me, from memory
		{ userId = 201, value = Board.encode(9, 40, B) }, -- a friend in this server
		{ userId = 201, value = Board.encode(8, 30, B) }, -- the same friend, stale, from the top cache
		{ userId = 202, value = Board.encode(12, 10, B) }, -- a friend in the top 500
		{ userId = 999, value = Board.encode(40, 10, B) }, -- a stranger: never shown
	}
	local view = Board.friendsView(me, friends, sources, 10)
	eq(#view.rows, 3, "me and my two friends with entries")
	eq(view.rows[1].userId, 202, "sorted by value: the friend with 12 first")
	eq(view.rows[2].userId, 201, "then 201 with their BEST value (9, not the stale 8)")
	eq(view.rows[2].count, 9, "the higher of duplicate values wins")
	eq(view.rows[3].userId, 100, "then me")
	eq(view.rows[3].you, true, "and my row is marked")
	eq(view.empty, false, "friends were found")
	-- nobody but me
	local lonely = Board.friendsView(me, friends, { { userId = 100, value = Board.encode(2, 5, B) }, { userId = 999, value = 5 } }, 10)
	eq(lonely.empty, true, "no friend with an entry: the view is 'empty'")
	eq(#lonely.rows, 1, "but I am always in my own friends view")
	truthy(string.find(Board.TEXT.friendsEmpty, "top 500", 1, true) ~= nil, "the empty text says the view covers the top 500")
	truthy(string.find(Board.TEXT.friendsEmpty, "Invite", 1, true) ~= nil, "and says something useful to do")
	truthy(string.find(Board.TEXT.friendsFailed, "Showing everyone", 1, true) ~= nil, "the failure text says what is shown instead")
	-- zero entries: I show with 0
	local zero = Board.friendsView(me, friends, {}, 10)
	eq(#zero.rows, 1, "with no score at all I still see my own row")
	eq(zero.rows[1].count, 0, "at 0")
end

do
	-- the friends cap: at most FriendsCap friend ids are ever looked at
	local ids = {}
	for i = 1, 500 do table.insert(ids, i) end
	local set, n = Board.capFriends(ids, B.FriendsCap)
	eq(n, 200, "a friend list is capped at 200")
	truthy(set[200] and not set[201], "the first 200, in the order Roblox returns them")
end

--================================================================ "You" pinned at the bottom

do
	local rows = { { rank = 1, userId = 5, count = 20 }, { rank = 2, userId = 6, count = 19 } }
	eq(Board.youLine(rows, 7, 12), "You: 📖 12 (not in this list)", "outside the list, the pinned line says so")
	eq(Board.youLine(rows, 6, 19), "You: #2 · 📖 19", "inside it, the pinned line gives your rank")
end

print(string.format("Board: %d passed, %d failed", passed, failed))
assert(failed == 0, "Board tests failed")
