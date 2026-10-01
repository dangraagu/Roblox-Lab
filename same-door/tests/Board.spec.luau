-- Spec for Board: the public + friends highscore board's pure rules. Run: luau tests/Board.spec.luau
--
-- docs/complete-game-standard.md §3: rank on a server-measured metric a script cannot inflate, ties
-- to whoever reached it FIRST, an OrderedDataStore under `u_<userId>` with the value
-- `metric * 2e9 + (2e9 - reachedAtUnix)`, written only when the metric improves. The metric here is
-- lower-is-better (a time), so metric = CapMs - timeMs (DESIGN §10).
local Board = require("../src/shared/Board")
local Config = require("../src/shared/Config")
local Medals = require("../src/shared/Medals")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local bc = Config.Board
eq(bc.CapMs, Config.RunCapSeconds * 1000, "the cap the encoding assumes is the run cap")

--================================================================ encoding
eq(Board.encode(27340, 1790730000, bc), (900000 - 27340) * 2e9 + (2e9 - 1790730000), "the standard's formula, lower time = bigger metric")
eq(Board.encode(27340, 1790730000, bc), 1745320209270000, "written out: 872660 * 2e9 + 209270000")

do
	local allInt, allExact = true, true
	for _, t in { 1, 999, 27340, 450000, 899999 } do
		for _, at in { 1600000000, 1790730000, 1999999999 } do
			local v = Board.encode(t, at, bc)
			if v == nil or v % 1 ~= 0 then allInt = false end
			if v == nil or v >= 2 ^ 53 or v + 1 == v then allExact = false end
		end
	end
	truthy(allInt, "every encoded value is an integer (an OrderedDataStore refuses anything else)")
	truthy(allExact, "and exact in a double: the largest is 1.800002e15 < 2^53")
end
truthy(Board.encode(1, 1, bc) < 2 ^ 53, "the largest possible value is below 2^53")

do
	local ok = true
	for _, t in { 1, 27340, 30074, 899999 } do
		for _, at in { 1600000000, 1790730000, 1999999999 } do
			local dt, dat = Board.decode(Board.encode(t, at, bc), bc)
			if dt ~= t or dat ~= at then ok = false end
		end
	end
	truthy(ok, "decode(encode(t, at)) == (t, at)")
end

-- fail closed on anything that is not a real, capped finish
eq(Board.encode(0, 1790730000, bc), nil, "a zero time is refused")
eq(Board.encode(900000, 1790730000, bc), nil, "a time at the cap is refused (a run at the cap is voided)")
eq(Board.encode(27340.5, 1790730000, bc), nil, "a fractional time is refused")
eq(Board.encode(0 / 0, 1790730000, bc), nil, "NaN is refused")
eq(Board.encode(27340, 2000000000, bc), nil, "reachedAt at 2e9 (2033-05-18) is refused: the encoding needs a new version by then")
eq(Board.encode(27340, 0, bc), nil, "reachedAt 0 is refused")

--================================================================ ordering: faster first, ties to the FIRST
truthy(Board.encode(27000, 1790730000, bc) > Board.encode(27001, 1790700000, bc),
	"a faster time ranks above a slower one even if the slower one came first")
truthy(Board.encode(27000, 1790700000, bc) > Board.encode(27000, 1790730000, bc),
	"on an equal time, whoever reached it first ranks above")

--================================================================ writes only improve
do
	local keep = Board.improve(Board.encode(27000, 1790700000, bc))
	eq(keep(nil), Board.encode(27000, 1790700000, bc), "an empty slot takes the value")
	eq(keep(Board.encode(28000, 1790600000, bc)), Board.encode(27000, 1790700000, bc), "a better time replaces a worse one")
	eq(keep(Board.encode(26000, 1790800000, bc)), nil, "a worse time aborts the write (nil)")
	eq(keep(Board.encode(27000, 1790700000, bc)), nil, "an identical value aborts the write")
	eq(keep(Board.encode(27000, 1790600000, bc)), nil, "the same time reached EARLIER is kept: the tie stays with the first")
	eq(keep("junk"), Board.encode(27000, 1790700000, bc), "a junk stored value is replaced")
end

--================================================================ rows
do
	local P = 27340
	local entries = {
		{ key = "u_11", value = Board.encode(29000, 1790710000, bc) },
		{ key = "u_22", value = Board.encode(33000, 1790700000, bc) },
		{ key = "u_bad", value = 5 },
		{ key = "u_33", value = Board.encode(50000, 1790720000, bc) },
	}
	local rows = Board.rows(entries, function(uid) return "Name" .. uid end, function(t) return Medals.grade(t, P, Config) end, bc)
	eq(#rows, 3, "a row whose key is not u_<userId> is dropped")
	eq(rows[1].rank, 1, "rank 1 first")
	eq(rows[1].name, "Name11", "the name comes from the resolver")
	eq(rows[1].time, "29.00", "the time in hundredths")
	eq(rows[1].medal, "Sealer", "29.00 on a 27.34 day is Sealer")
	eq(rows[1].sealed, true, "a Sealer row carries the SEALED plate")
	eq(rows[2].medal, "Gold", "33.00 is Gold")
	eq(rows[2].sealed, false, "no plate below Sealer")
	eq(rows[3].rank, 3, "ranks stay dense after a dropped row")
	eq(rows[3].medal, "Bronze", "50.00 is Bronze")
	eq(Board.userIdOf("u_123"), 123, "the key decodes to a user id")
	eq(Board.userIdOf("x_123"), nil, "a foreign key does not")
	eq(Board.key(123), "u_123", "the key form")
end

--================================================================ friends: capped, budgeted, sorted
do
	local ids = {}
	for i = 1, 250 do ids[i] = 1000 + i end
	eq(#Board.capFriends(ids, bc), 200, "at most 200 friends are looked up")
	truthy(Board.mayRead(21, bc), "a GetAsync budget above the reserve may read a friend")
	truthy(not Board.mayRead(20, bc), "at the reserve it may not: saves and the day record come first")
	truthy(not Board.mayRead(nil, bc), "an unknown budget does not read (fails closed)")

	local found = {
		{ userId = 5, value = Board.encode(40000, 1790700000, bc) },
		{ userId = 6, value = Board.encode(30000, 1790710000, bc) },
		{ userId = 7, value = Board.encode(30000, 1790705000, bc) },
	}
	local sorted = Board.sortFound(found)
	eq(sorted[1].userId, 7, "friends sort by value: the earlier of two equal times first")
	eq(sorted[2].userId, 6, "then the later one")
	eq(sorted[3].userId, 5, "then the slower friend")
end

--================================================================ caches
truthy(Board.fresh(100, 159, 60), "a public cache 59 s old is fresh")
truthy(not Board.fresh(100, 160, 60), "at 60 s it is stale")
truthy(not Board.fresh(nil, 160, 60), "an empty cache is stale")
do
	local cache = Board.newNameCache()
	for i = 1, 600 do Board.rememberName(cache, i, "n" .. i, bc) end
	eq(Board.nameCount(cache), 500, "the name cache holds at most 500 entries")
	eq(Board.cachedName(cache, 600), "n600", "the newest name is kept")
	eq(Board.cachedName(cache, 1), nil, "the oldest was evicted")
end
truthy(#bc.EmptyFriends > 20 and string.find(bc.EmptyFriends, "same dungeon") ~= nil,
	"an empty friends board says something useful")

print(string.format("Board: %d passed, %d failed", passed, failed))
if failed > 0 then error("Board spec failed", 0) end
