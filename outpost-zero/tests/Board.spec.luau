-- Board — the Census's encoding, write rule, friend rows and texts. Run: luau tests/Board.spec.luau
--
-- The standard (docs/complete-game-standard.md §3): an OrderedDataStore keyed u_<userId>, value
-- metric * 2e9 + (2e9 - reachedAtUnix), written only when the metric improves, ties to whoever reached it FIRST.
-- The metric here is the population; reachedAt is the profile's own `popAt` (when that population was first
-- reached, not the write time). Adapted from meteor-drop-tycoon's Board.spec (the metric and the texts changed).

local Config = require("../src/shared/Config")
local Board = require("../src/shared/Board")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local C = Config

--============================================================================ encoding
do
	local t = 1790000000 -- a real os.time() (Sept 2026)
	local v = Board.encode(C, 6400, t)
	eq(v, 6400 * 2e9 + (2e9 - t), "the standard's encoding, exactly")
	eq(v % 1, 0, "an integer (an OrderedDataStore silently refuses anything else)")
	local p, at = Board.decode(C, v)
	eq(p, 6400, "decode gives the population back")
	eq(at, t, "and the moment it was reached")
	truthy(Board.encode(C, 6400, t - 60) > Board.encode(C, 6400, t), "reaching 6 400 a minute earlier ranks higher")
	truthy(Board.encode(C, 6401, t + 1e6) > Board.encode(C, 6400, t - 1e6), "a higher population always beats an earlier lower one")
	local p1, at1 = Board.decode(C, Board.encode(C, 5, 1))
	eq(p1, 5, "reachedAt 1 decodes to the right population")
	eq(at1, 1, "...and time")
	eq((Board.decode(C, Board.encode(C, 5, 0))), 5, "reachedAt 0 (clamped) cannot spill into the next population")
	eq((Board.decode(C, Board.encode(C, 5, 3e9))), 5, "reachedAt past 2e9 (clamped) cannot borrow from the one below")
	-- exact at the largest population the game allows (36 lots x 22 storeys)
	local top = Board.encode(C, C.Board.MaxPopulation, t)
	local tp, tt = Board.decode(C, top)
	eq(tp, 1031184, "the full city (1 031 184) decodes exactly")
	eq(tt, t, "...with its time")
	truthy(top < 2 ^ 53, string.format("and stays under 2^53 (%.4e)", top))
	eq(Board.encode(C, C.Board.MaxPopulation + 5, t), top, "a population over the full city is clamped to it")
	eq(Board.encode(C, -3, t), Board.encode(C, 0, t), "a negative population is stored as 0")
	eq(Board.encode(C, 7.9, t), Board.encode(C, 7, t), "a fractional population is floored")
end

--============================================================================ write only when it improves
do
	local t = 1790000000
	eq(Board.shouldWrite(C, nil, 0), false, "population 0 is not on the Census")
	eq(Board.shouldWrite(C, nil, 4), true, "a first population is written")
	local v = Board.encode(C, 900, t)
	eq(Board.shouldWrite(C, v, 900), false, "the same population is not written again (a rejoin never rewrites)")
	eq(Board.shouldWrite(C, v, 899), false, "a lower population is never written")
	eq(Board.shouldWrite(C, v, 901), true, "a higher one is")
end

--============================================================================ friend ids, capped
do
	local pages = {}
	for p = 1, 5 do
		local page = {}
		for i = 1, 60 do table.insert(page, { Id = p * 1000 + i, Username = "f" .. i }) end
		table.insert(pages, page)
	end
	local idx, calls = 0, 0
	local ids = Board.collectFriendIds(C, function()
		calls += 1
		idx += 1
		return pages[idx]
	end)
	eq(#ids, 200, "at most 200 friend ids are collected (300 offered)")
	eq(calls, 4, "and no page past the one that reached the cap is fetched")
	eq(ids[1], 1001, "in the order Roblox gave them")
	eq(#Board.collectFriendIds(C, function() return nil end), 0, "no pages: no friends, no error")
	local served = false
	local bad = Board.collectFriendIds(C, function()
		if served then return nil end
		served = true
		return { { Id = "x" }, { nothing = true }, { Id = 7 } } :: any
	end)
	eq(#bad, 1, "junk entries are skipped")
end

--============================================================================ rows, ranks, texts
do
	local rows = {
		{ userId = 5, value = Board.encode(C, 900, 100) },
		{ userId = 3, value = Board.encode(C, 6400, 200) },
		{ userId = 9, value = Board.encode(C, 6400, 150) },
		{ userId = 1, value = Board.encode(C, 12, 50) },
	}
	local sorted = Board.sortRows(rows)
	eq(sorted[1].userId, 9, "6 400 reached first is first")
	eq(sorted[2].userId, 3, "6 400 reached later is second")
	eq(sorted[3].userId, 5, "then 900")
	eq(sorted[4].userId, 1, "then 12")
	eq(sorted[1].pop, 6400, "rows carry the decoded population")
	eq(sorted[1].rank, 1, "and their rank")
	eq(rows[1].userId, 5, "the input is not reordered")
	local tie = Board.sortRows({ { userId = 8, value = 5 }, { userId = 2, value = 5 } })
	eq(tie[1].userId, 2, "identical values fall back to the lower user id, so the order never flickers")
end
do
	eq(Board.emptyFriendsText(C, 6400),
		"None of your friends is on the Census yet. Your population: 🏮 6 400. Invite someone: the sky has room for six cities.",
		"the empty friends view says something useful (DESIGN 9.3)")
	eq(Board.UNAVAILABLE, "Friends list unavailable right now. Showing your own row.", "the failure text")
	eq(Board.loadingText(34, 120), "Loading friends… 34 / 120", "the progress text")
	eq(Board.emojiFor(C, 0), "🌫️", "band emoji for an empty city")
	eq(Board.emojiFor(C, 79), "🌫️", "79: still Fogbound Dawn")
	eq(Board.emojiFor(C, 80), "☀️", "80: Clear Morning")
	eq(Board.emojiFor(C, 6400), "🏮", "6 400: Lantern Dusk, the Skyport")
	eq(Board.emojiFor(C, 1031184), "🌌", "the full city: Aurora Crown")
	eq(Board.rowText(1, "Nova", 6400, "🏮"), "1. Nova  🏮 6 400", "a row reads rank, name, band emoji, population")
end

--============================================================================ the window: the viewer always sees their own row
-- REVIEW-1 F6: the board face has 10 row slots. The server sent the top 10 plus the viewer's own row (11), the HUD
-- drew the first 10, and once 10 players ranked above someone, they could not find themselves.
do
	local function rows(n, youAt)
		local out = {}
		for i = 1, n do table.insert(out, { rank = i, name = "P" .. i, pop = 1000 - i, you = i == youAt }) end
		return out
	end
	eq(C.Board.Rows, 10, "the board face shows 10 rows")
	local w = Board.window(rows(5, 3), 10)
	eq(#w, 5, "five rows fit unchanged")
	eq(w[3].you, true, "...the viewer where they rank")
	w = Board.window(rows(12, 12), 10)
	eq(#w, 10, "twelve rows become ten")
	eq(w[10].you, true, "the viewer, 12th, takes the last slot")
	eq(w[10].rank, 12, "...with their real rank")
	eq(w[9].rank, 9, "after the top nine")
	w = Board.window(rows(12, 4), 10)
	eq(#w, 10, "a viewer inside the top ten: still ten rows")
	eq(w[4].you, true, "...the viewer where they rank")
	eq(w[10].rank, 10, "...and the tenth is the tenth")
	w = Board.window(rows(12, 0), 10)
	eq(#w, 10, "no viewer row: the top ten")
	eq(w[10].rank, 10, "...in order")
	-- the public view: ten rows from the store, then the viewer's own row (rank 0: not in the cached top ten)
	local pub = rows(10, 0)
	table.insert(pub, { rank = 0, name = "Me", pop = 5, you = true })
	w = Board.window(pub, 10)
	eq(#w, 10, "public: ten from the store plus the viewer's own row become ten")
	eq(w[10].name, "Me", "...the viewer's row last")
	eq(w[9].rank, 9, "...after the top nine")
	eq(#pub, 11, "the input list is not changed")
end

--============================================================================ the friends read gate
do
	eq(Board.canRead(C, 10, 9.5, 50), false, "0.5 s after the last read: wait")
	eq(Board.canRead(C, 10, 9, 50), true, "1 s after: read")
	eq(Board.canRead(C, 10, 0, 10), false, "budget at the reserve (10): do not read")
	eq(Board.canRead(C, 10, 0, 11), true, "above the reserve: read")
	eq(Board.canRead(C, 10, -math.huge, 0 / 0), false, "an unknown budget: do not read")
end

print(string.format("Board: %d passed, %d failed", passed, failed))
if failed > 0 then error("Board spec failed", 0) end
