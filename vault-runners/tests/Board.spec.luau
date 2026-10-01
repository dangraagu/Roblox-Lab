-- Spec for Board: the rules of the public + friends highscore board. Run: luau tests/Board.spec.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script
-- cannot inflate; ties go to whoever reached it FIRST. OrderedDataStore, key `u_<userId>`, value
-- `metric * 2e9 + (2e9 - reachedAtUnix)`, written only when the metric improves. Public top 10 cached
-- about 60 s; friends fetched on demand, capped, cached and throttle-safe; an empty friends board says
-- something useful.
--
-- Vault Runners' metric is the DEEPEST VAULT ESCAPED, as a depth (VaultEnv.deepestCleared: the tier's
-- buried depth plus the last floor cleared in it). It only moves when the server's own RunState banks
-- an escape, and it is the number the strata are drawn from, so the brag (the Frozen Vault) is a row
-- on this board. The pure rules live in src/shared/Board.luau; the server does the DataStore calls.
local Config = require("../src/shared/Config")
local Board = require("../src/shared/Board")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local BC = Config.Board
truthy(type(BC) == "table", "Config.Board exists")
BC = BC or { MaxMetric = 4000000, PublicRows = 10, FriendsRows = 10, Text = {} }

--============================================================================ the config

eq(BC.PublicRows, 10, "the public board is the top 10 (GetSortedAsync(false, 10))")
truthy(type(BC.PublicCacheSeconds) == "number" and BC.PublicCacheSeconds >= 45 and BC.PublicCacheSeconds <= 90,
	"the public top 10 is cached about 60 s (" .. tostring(BC.PublicCacheSeconds) .. ")")
truthy(type(BC.FriendsCap) == "number" and BC.FriendsCap >= 50 and BC.FriendsCap <= 200,
	"GetFriendsAsync is read to a cap of at most 200 (" .. tostring(BC.FriendsCap) .. ")")
truthy(type(BC.ReadsPerSecond) == "number" and BC.ReadsPerSecond > 0 and BC.ReadsPerSecond <= 2,
	"friend score reads are throttled to a sustainable rate (" .. tostring(BC.ReadsPerSecond) .. "/s)")
-- Roblox's GetAsync budget is 60 + 10 per player per minute. A lone player asking for friends must
-- never be allowed to spend it all: burst + a minute at the rate stays under the one-player budget.
truthy(type(BC.ReadsBurst) == "number" and BC.ReadsBurst + BC.ReadsPerSecond * 60 <= 60 + 10 + 40,
	"a burst plus a minute of friend reads fits the server's budget with one player in it")
truthy(type(BC.MaxMetric) == "number" and BC.MaxMetric * Board.SCALE + Board.SCALE < 2 ^ 53,
	"MaxMetric keeps every stored value exact in a double (under 2^53)")
for _, k in { "Title", "EmptyPublic", "FriendsFailed", "NoFriends", "FriendsNoScores", "FriendsChecking",
	"Loading", "Prompt", "Offline" } do
	truthy(type(BC.Text[k]) == "string" and #BC.Text[k] > 0, "Config.Board.Text." .. k .. " is set")
end
truthy(string.find(BC.Text.FriendsNoScores or "", "%d", 1, true) ~= nil, "FriendsNoScores names how many friends")
truthy(select(2, string.gsub(BC.Text.FriendsChecking or "", "%%d", "")) == 2, "FriendsChecking names both counts")

--============================================================================ the stored value

local T0 = 1780000000 -- 2026-05-28, an ordinary reach time
eq(Board.encode(19, T0, BC), 19 * 2e9 + (2e9 - T0), "the value is metric * 2e9 + (2e9 - reachedAt), exactly")
do
	local v = Board.encode(19, T0, BC)
	eq(v % 1, 0, "and a whole number (an OrderedDataStore only takes integers)")
	local m, t = Board.decode(v)
	eq(m, 19, "decode gives the metric back")
	eq(t, T0, "and the reach time")
end
do
	-- a sweep: every metric and time decodes exactly
	local bad = nil
	for _, m in { 0, 1, 2, 18, 19, 55, 56, 999, 123456, BC.MaxMetric } do
		for _, t in { 1000000001, T0, 1999999999, 2000000000, 2100000000, 2999999999 } do
			local mm, tt = Board.decode(Board.encode(m, t, BC))
			if mm ~= m or tt ~= t then bad = bad or string.format("(%d, %d) -> (%s, %s)", m, t, tostring(mm), tostring(tt)) end
		end
	end
	truthy(bad == nil, "encode/decode round-trips every (metric, time) from 2001 to 2065: " .. tostring(bad))
end
-- TIES GO TO WHOEVER GOT THERE FIRST
truthy(Board.encode(19, T0 - 60, BC) > Board.encode(19, T0, BC), "same depth: a minute earlier ranks higher")
truthy(Board.encode(19, T0 - 1, BC) > Board.encode(19, T0, BC), "same depth: one second earlier ranks higher")
truthy(Board.encode(19, 2100000000, BC) > Board.encode(19, 2100000001, BC), "and still after 2033 (2e9 - t goes negative)")
-- ...and depth always beats time
truthy(Board.encode(20, 2999999999, BC) > Board.encode(19, 1000000001, BC),
	"one depth more beats any reach time (a 2065 reach of 20 over a 2001 reach of 19)")
-- clamps: nothing a bad input can do overflows the double or goes negative
eq(Board.metricOf(Board.encode(BC.MaxMetric * 10, T0, BC)), BC.MaxMetric, "a metric over MaxMetric is clamped to it")
eq(Board.metricOf(Board.encode(-5, T0, BC)), 0, "a negative metric reads as 0")
eq(Board.metricOf(Board.encode(0 / 0, T0, BC)), 0, "NaN reads as 0")
eq(Board.metricOf(Board.encode(19.7, T0, BC)), 19, "a fractional metric is floored, never rounded up")
eq(Board.metricOf(nil), 0, "no stored value is metric 0")
eq(Board.metricOf("19"), 0, "a non-number stored value is metric 0")

eq(Board.key(4242), "u_4242", "the key is u_<userId> (a STRING key)")
eq(Board.userIdOf("u_4242"), 4242, "and reads back")
eq(Board.userIdOf("x_4242"), nil, "a key of another shape is not a player")
eq(Board.userIdOf("u_42a"), nil, "nor is a key with junk in it")

--============================================================================ written only when it improves

do
	local first = Board.encode(19, T0, BC)
	eq(Board.keepHigher(nil, first), first, "nothing stored: write")
	eq(Board.keepHigher(first, Board.encode(19, T0 + 600, BC)), nil,
		"the same depth reached LATER does not replace the first reach (abort, no write)")
	eq(Board.keepHigher(first, Board.encode(19, T0 - 600, BC)), nil,
		"nor does the same depth with an earlier stamp: the board only moves when the DEPTH improves")
	eq(Board.keepHigher(first, Board.encode(18, T0 - 99999, BC)), nil, "a shallower depth never lowers the board")
	local deeper = Board.encode(20, T0 + 600, BC)
	eq(Board.keepHigher(first, deeper), deeper, "a deeper escape is written")
	eq(Board.keepHigher("junk", deeper), deeper, "a corrupt stored value is replaced")
end

--============================================================================ ranking and the views

do
	local rows = Board.rank({
		{ userId = 3, value = Board.encode(19, T0, BC) },
		{ userId = 1, value = Board.encode(26, T0, BC) },
		{ userId = 2, value = Board.encode(19, T0 - 5, BC) },
		{ userId = 9, value = Board.encode(19, T0, BC) },
	}, 3)
	local order = {}
	for _, r in rows do table.insert(order, tostring(r.userId)) end
	eq(table.concat(order, " "), "1 2 3", "rank: deepest first, then earliest, then the lower id; cut to n")
end

do
	local v = Board.publicView({
		{ userId = 11, value = Board.encode(56, T0, BC) },
		{ userId = 12, value = Board.encode(19, T0, BC) },
		{ userId = 13, value = 0 },
	}, BC)
	eq(#v.rows, 2, "public view: a stored 0 is not a row")
	eq(v.rows[1].rank, 1, "rows are ranked")
	eq(v.rows[1].depth, 56, "and carry the decoded DEPTH")
	eq(v.rows[1].value, nil, "never the raw stored value")
	eq(v.note, nil, "a board with rows has no note")
	local empty = Board.publicView({}, BC)
	eq(#empty.rows, 0, "an empty board has no rows")
	eq(empty.note, BC.Text.EmptyPublic, "and says something useful")
end

do
	local function ids(view)
		local out = {}
		for _, r in view.rows do table.insert(out, tostring(r.userId) .. ":" .. tostring(r.depth) .. (if r.you then "*" else "")) end
		return table.concat(out, " ")
	end
	local values = {
		[1] = Board.encode(12, T0, BC),
		[2] = Board.encode(30, T0, BC),
		[3] = 0,
		[4] = Board.encode(12, T0 - 1, BC),
	}
	local v = Board.friendsView(1, values, { friendCount = 3, checked = 3 }, BC)
	eq(ids(v), "2:30 4:12 1:12*", "friends view: deepest first, the tie to the earlier reach, you marked")
	eq(v.note, nil, "everyone checked and someone escaped: no note")

	local cfg2 = table.clone(BC)
	cfg2.FriendsRows = 2
	local many = Board.friendsView(1, values, { friendCount = 3, checked = 3 }, cfg2)
	eq(ids(many), "2:30 1:12*", "when you rank below the shown rows, the last row is YOURS")
	eq(many.rows[2].rank, 3, "with your real rank")

	eq(Board.friendsView(1, { [1] = 0 }, { friendCount = 0, checked = 0 }, BC).note, BC.Text.NoFriends,
		"no Roblox friends: says friends you add show up here")
	eq(Board.friendsView(1, { [1] = 0, [5] = 0 }, { friendCount = 1, checked = 1 }, BC).note,
		string.format(BC.Text.FriendsNoScores, 1), "friends who never escaped: says so, and invites them")
	eq(Board.friendsView(1, { [1] = Board.encode(3, T0, BC) }, { friendCount = 4, checked = 4 }, BC).note,
		string.format(BC.Text.FriendsNoScores, 4), "only YOU on the board is still 'none of your friends'")
	eq(Board.friendsView(1, {}, { friendCount = 0, checked = 0, failed = true }, BC).note, BC.Text.FriendsFailed,
		"the friends call failed: says try again")
	eq(Board.friendsView(1, { [1] = 0 }, { friendCount = 200, checked = 40 }, BC).note,
		string.format(BC.Text.FriendsChecking, 40, 200), "still reading: says how far it has got")
end

--============================================================================ cache and limiter

do
	local c = Board.newCache(60)
	Board.cachePut(c, 7, "x", 100)
	eq(Board.cacheGet(c, 7, 159.9), "x", "a cache entry lives for its TTL")
	eq(Board.cacheGet(c, 7, 160), nil, "and not a moment longer")
	eq(Board.cacheHas(c, 8, 100), false, "an unknown key is a miss")
	Board.cachePut(c, 9, false, 100)
	eq(Board.cacheHas(c, 9, 101), true, "a cached FALSE is still a hit (a friend who never escaped)")
end

do
	local cap, rate = 40, 1
	local l = Board.newLimiter(cap, rate, 0)
	local granted, t = 0, 0
	while t <= 120 do
		for _ = 1, 50 do if Board.take(l, t) then granted += 1 end end
		t += 0.5
	end
	truthy(granted <= cap + rate * 120 + 1, string.format("the limiter never grants more than burst + rate * T (%d in 120 s)", granted))
	truthy(granted >= cap + rate * 120 - 2, string.format("and does grant what it promises (%d)", granted))
	local l2 = Board.newLimiter(2, 1, 0)
	truthy(Board.take(l2, 0) and Board.take(l2, 0), "a burst is granted at once")
	eq(Board.take(l2, 0), false, "and refused past it")
	eq(Board.take(l2, 1), true, "then refills at the rate")
end

print(string.format("Board.spec: %d passed, %d failed", passed, failed))
if failed > 0 then error("Board.spec failed", 0) end
