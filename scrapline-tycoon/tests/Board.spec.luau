-- Board — the Top Recyclers board's encoding, write rule, friend rows and texts. Run: luau tests/Board.spec.luau
--
-- The standard (docs/complete-game-standard.md §3): an OrderedDataStore keyed u_<userId>, value
-- metric * 2e9 + (2e9 - reachedAtUnix), written only when the metric improves, ties to whoever reached it FIRST.
-- The metric here is Gold Bolts; reachedAt is the profile's own `boltsAt` (DESIGN.md section 10).
-- meteor-drop-tycoon's Board.spec with the metric renamed.

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
	local v = Board.encode(C, 4, t)
	eq(v, 4 * 2e9 + (2e9 - t), "the standard's encoding, exactly")
	eq(v % 1, 0, "an integer (an OrderedDataStore silently refuses anything else)")
	local b, at = Board.decode(C, v)
	eq(b, 4, "decode gives the bolts back")
	eq(at, t, "and the moment that count was reached")
	truthy(Board.encode(C, 4, t - 60) > Board.encode(C, 4, t), "reaching 4 bolts a minute earlier ranks higher")
	truthy(Board.encode(C, 5, t + 1e6) > Board.encode(C, 4, t - 1e6), "more bolts always beat an earlier lower count")
	local b1, at1 = Board.decode(C, Board.encode(C, 5, 1))
	eq(b1, 5, "reachedAt 1 decodes to the right count")
	eq(at1, 1, "...and time")
	eq((Board.decode(C, Board.encode(C, 5, 0))), 5, "reachedAt 0 (clamped) cannot spill into the next count")
	eq((Board.decode(C, Board.encode(C, 5, 3e9))), 5, "reachedAt past 2e9 (clamped) cannot borrow from the count below")
	-- the level cap bounds bolts at 52 (Recycle.spec); 52 encodes exactly under 2^53
	local big = Board.encode(C, 52, t)
	local bb, bt = Board.decode(C, big)
	eq(bb, 52, "52 bolts (the most any line can earn) decode exactly")
	eq(bt, t, "...with the time")
	truthy(big < 2 ^ 53, "and stay under 2^53")
	eq(Board.encode(C, -3, t), Board.encode(C, 0, t), "a negative count is stored as 0")
	eq(Board.encode(C, 7.9, t), Board.encode(C, 7, t), "a fractional count is floored")
end

--============================================================================ write only when it improves
do
	local t = 1790000000
	eq(Board.shouldWrite(C, nil, 0), false, "0 bolts are not on the board")
	eq(Board.shouldWrite(C, nil, 1), true, "a first bolt is written")
	local v = Board.encode(C, 3, t)
	eq(Board.shouldWrite(C, v, 3), false, "the same count is not written again (a rejoin never rewrites)")
	eq(Board.shouldWrite(C, v, 2), false, "a lower count is never written")
	eq(Board.shouldWrite(C, v, 4), true, "a higher one is")
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
		{ userId = 5, value = Board.encode(C, 2, 100) },
		{ userId = 3, value = Board.encode(C, 6, 200) },
		{ userId = 9, value = Board.encode(C, 6, 150) },
		{ userId = 1, value = Board.encode(C, 1, 50) },
	}
	local sorted = Board.sortRows(rows)
	eq(sorted[1].userId, 9, "6 bolts reached first is first")
	eq(sorted[2].userId, 3, "6 bolts reached later is second")
	eq(sorted[3].userId, 5, "then 2")
	eq(sorted[4].userId, 1, "then 1")
	eq(sorted[1].bolts, 6, "rows carry the decoded count")
	eq(sorted[1].rank, 1, "and their rank")
	eq(rows[1].userId, 5, "the input is not reordered")
	local tie = Board.sortRows({ { userId = 8, value = 5 }, { userId = 2, value = 5 } })
	eq(tie[1].userId, 2, "identical values fall back to the lower user id, so the order never flickers")
end
do
	eq(Board.emojiFor(C, 0), "🔧", "0 bolts: a rusty factory")
	eq(Board.emojiFor(C, 1), "🎨", "1: painted")
	eq(Board.emojiFor(C, 4), "🥇", "4: the Golden Factory (DESIGN 10.1: \"🥇 4\")")
	eq(Board.emojiFor(C, 30), "🥇", "and gold from then on")
	eq(Board.rowText(1, "Nova", 4, "🥇"), "1. Nova  🥇 4", "a row reads rank, name, grade emoji, bolts")
	eq(Board.emptyFriendsText(C, 2),
		"None of your friends has a Gold Bolt yet. Your best: 🔩 2. Invite someone: there are six factories on every server.",
		"the empty friends view says something useful (DESIGN 10.3)")
	eq(Board.UNAVAILABLE, "Friends list unavailable right now. Showing your own row.", "the failure text")
	eq(Board.loadingText(34, 120), "Loading friends… 34 / 120", "the progress text")
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
