-- Board: the public + friends highscore board's pure rules. Run: luau tests/Board.spec.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric, ties broken by who
-- reached it FIRST, stored in an OrderedDataStore under `u_<userId>` as `metric * 2e9 + (2e9 - reachedAtUnix)`,
-- written only when the metric improves; public top 10 cached ~60 s; friends fetched on demand, capped,
-- cached and throttle-safe; an empty friends board says something useful.
--
-- The rules are plus1-jump's Board (tests/Board.spec.luau there), adapted: rows carry `metric` (a "tier" is a
-- crystal rarity in this game), and the metric is Gem Dust EARNED FROM HARVESTS in whole hundreds
-- (Board.metricOfDust), because a normal player earns about 1.1 million in an 8-hour session and the encoded
-- value is only exact up to Config.Board.MaxMetric (tests/Pacing.spec.luau measures how far that cap is).
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
eq(Config.Save.Leaderboard, "GrowCrystal_LB_v2",
	"the board has its own store: v1 held RAW totalDust, which would sort below every encoded value")

--======================================================================= the metric

eq(Board.metricOfDust(0, bc), 0, "no dust earned: metric 0")
eq(Board.metricOfDust(bc.DustPerPoint - 1, bc), 0, "less than one point of dust: still 0")
eq(Board.metricOfDust(bc.DustPerPoint, bc), 1, "one point")
eq(Board.metricOfDust(1125295, bc), math.floor(1125295 / bc.DustPerPoint), "whole points, rounded DOWN")
eq(Board.metricOfDust(-5, bc), 0, "negative dust is 0")
eq(Board.metricOfDust(0 / 0, bc), 0, "NaN is 0")
eq(Board.metricOfDust(bc.MaxMetric * bc.DustPerPoint * 10, bc), bc.MaxMetric, "capped at MaxMetric")
eq(bc.DustPerPoint, 100, "a point is 100 Gem Dust")

-- the score a player reads: dust, rounded DOWN, never overstated
eq(Board.formatScore(0, bc), "0", "0 points reads 0")
eq(Board.formatScore(3, bc), "300", "3 points reads 300")
eq(Board.formatScore(99, bc), "9900", "under 10 000 the whole number")
eq(Board.formatScore(100, bc), "10.0K", "10 000 reads 10.0K")
eq(Board.formatScore(9999, bc), "999.9K", "999 900 reads 999.9K (truncated, not rounded up to 1000.0K)")
eq(Board.formatScore(11252, bc), "1.12M", "1 125 200 reads 1.12M")
eq(Board.formatScore(12399, bc), "1.23M", "1 239 900 reads 1.23M (truncated, never 1.24M)")
eq(Board.formatScore(bc.MaxMetric, bc), "400.00M", "the cap reads 400.00M")
-- with 100 dust per point the K form is always exact; with a finer point it must truncate too
eq(Board.formatScore(123456, { DustPerPoint = 1 }), "123.4K", "a finer point: 123 456 reads 123.4K, never rounded up to 123.5K")

--======================================================================= the stored value

-- the owner's formula, verbatim
eq(Board.encode(3, 1790000000, bc), 3 * 2e9 + (2e9 - 1790000000), "encode is metric * 2e9 + (2e9 - reachedAt)")
eq(Board.encode(85, 1790000000, bc), 170210000000, "metric 85 reached at 1790000000: 170 000 000 000 + 210 000 000")

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
	for _, m in { 1, 2, 84, 85, 239, 240, bc.MaxMetric - 1 } do
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

eq(Board.improves(nil, 1), true, "nothing stored yet: metric 1 improves")
eq(Board.improves(nil, 0), false, "but metric 0 is not worth a write")
eq(Board.improves(Board.encode(12, 1790000000, bc), 12), false, "the same metric again: no write")
eq(Board.improves(Board.encode(12, 1790000000, bc), 11), false, "a lower metric: no write")
eq(Board.improves(Board.encode(12, 1790000000, bc), 13), true, "a higher metric: write")

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
	eq(v.rows[1].metric, 240, "and carry the decoded metric, not the stored value")
	eq(v.rows[2].userId, 8, "in the order given (GetSortedAsync already sorted them)")
	eq(v.note, nil, "a public board with miners needs no note")
	local empty = Board.publicView({}, bc)
	eq(#empty.rows, 0, "an empty public board has no rows")
	truthy(type(empty.note) == "string" and #empty.note > 10, "and says something useful (" .. tostring(empty.note) .. ")")
	local zero = Board.publicView({ { userId = 9, value = Board.encode(0, t0, bc) } }, bc)
	eq(#zero.rows, 0, "a stored metric 0 is not a miner")
end

do
	local t0 = 1790000000
	local me = 100
	local values = {
		[100] = Board.encode(30, t0 + 5, bc),
		[201] = Board.encode(85, t0, bc),
		[202] = Board.encode(30, t0 + 1, bc), -- same metric as me, reached earlier
		[203] = Board.encode(0, t0, bc),      -- never harvested
	}
	local v = Board.friendsView(me, values, { friendCount = 3, checked = 3, failed = false }, bc)
	local ids = {}
	for _, r in v.rows do table.insert(ids, tostring(r.userId) .. (if r.you then "*" else "")) end
	eq(table.concat(ids, ","), "201,202,100*", "friends view: my friends and me, highest first, earliest on a tie; me marked")
	eq(v.rows[3].rank, 3, "my row has my real rank")
	eq(v.note, nil, "every friend checked, some have harvested: no note")

	-- more friends than rows: I still see where I stand
	local many = { [me] = Board.encode(2, t0, bc) }
	for i = 1, 30 do many[1000 + i] = Board.encode(10 + i, t0, bc) end
	local m = Board.friendsView(me, many, { friendCount = 30, checked = 30, failed = false }, bc)
	eq(#m.rows, bc.FriendsRows, "the friends view shows Config.Board.FriendsRows rows")
	eq(m.rows[#m.rows].you, true, "and when I am outside the top, the last row is me")
	eq(m.rows[#m.rows].rank, 31, "with my real rank (31st of 31)")
	eq(m.rows[1].metric, 40, "the top row is the best friend")

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
		"and the four notes differ (failed / no friends / none harvested / still checking)")
	truthy(string.find(quiet.note, "4", 1, true) ~= nil, "none harvested: names how many friends were checked (" .. quiet.note .. ")")
	truthy(string.find(busy.note, "40", 1, true) ~= nil and string.find(busy.note, "120", 1, true) ~= nil,
		"still checking: says how far (" .. busy.note .. ")")
	eq(#none.rows, 1, "with no friends I still see my own row")
	eq(#Board.friendsView(me, {}, { friendCount = 0, checked = 0, failed = false }, bc).rows, 0,
		"and with nothing harvested at all, no rows (the note speaks)")
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

--======================================================================= the shipped numbers

eq(bc.PublicRows, 10, "public board: GetSortedAsync(false, 10)")
truthy(bc.PublicCacheSeconds >= 45 and bc.PublicCacheSeconds <= 90, "public board cached about 60 s (" .. tostring(bc.PublicCacheSeconds) .. ")")
truthy(bc.FriendsCap >= 50 and bc.FriendsCap <= 200, "friends list capped (" .. tostring(bc.FriendsCap) .. ")")
truthy(bc.FriendsCacheSeconds >= 60, "a player's friends list is cached")
truthy(bc.FriendsRetrySeconds >= 30, "a failed friends fetch is not retried at once")
truthy(bc.MaxMetric * 2e9 + 2e9 < 2 ^ 53, "MaxMetric keeps every value exact in a double")

--======================================================================= the HUD panel (Studio 2026-10-09)
-- Real Studio, night shift 2026-10-09: with nobody stored, the HUD's 🏆 TOP MINERS panel on the right was an empty
-- dark box (the same defect +1 Jump had). The board store starts empty on the live game for every new board version.
do
	local note = Board.hudNote({}, bc)
	truthy(type(note) == "string" and #note > 5, "an empty HUD panel says something (" .. tostring(note) .. ")")
	truthy(type(note) == "string" and #note <= 40, "and short enough for the narrow panel (" .. tostring(note and #note) .. " <= 40)")
	eq(Board.hudNote({ { rank = 1, userId = 7, name = "a", score = "1" } }, bc), nil, "a HUD panel with miners needs no note")
end

--======================================================================= no Studio writes to the live stores
-- Night shift 2026-10-09 (second reviews of every live game): nothing in code stopped a Studio playtest with "Studio
-- Access to API Services" on from writing to the LIVE profile store and board, including the night shift's own
-- shot sessions with cheat config. Main's tryStore now refuses in Studio unless Config.Save.AllowStudio is true,
-- and that may only ever be set in an open place's Config, never in src/.
eq(Config.Save.AllowStudio, false, "Config.Save.AllowStudio is false in src (set it only in a Studio place)")

print(string.format("Board: %d passed, %d failed", passed, failed))
assert(failed == 0, "Board tests failed")
