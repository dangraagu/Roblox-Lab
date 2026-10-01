-- Board — the Star Chart's encoding, write rule, friend rows and texts. Run: luau tests/Board.spec.luau
--
-- The standard (docs/complete-game-standard.md §3): an OrderedDataStore keyed u_<userId>, value
-- metric * 2e9 + (2e9 - reachedAtUnix), written only when the metric improves, ties to whoever reached
-- it FIRST. The metric here is the Beacon level; reachedAt is the profile's own `beaconAt`.

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
	local v = Board.encode(C, 22, t)
	eq(v, 22 * 2e9 + (2e9 - t), "the standard's encoding, exactly")
	eq(v % 1, 0, "an integer (an OrderedDataStore silently refuses anything else)")
	local b, at = Board.decode(C, v)
	eq(b, 22, "decode gives the Beacon back")
	eq(at, t, "and the moment it was reached")
	-- ties: same level, the EARLIER reacher ranks higher
	truthy(Board.encode(C, 22, t - 60) > Board.encode(C, 22, t), "reaching Beacon 22 a minute earlier ranks higher")
	truthy(Board.encode(C, 23, t + 1e6) > Board.encode(C, 22, t - 1e6), "a higher level always beats an earlier lower one")
	-- the edges of reachedAt
	local b1, at1 = Board.decode(C, Board.encode(C, 5, 1))
	eq(b1, 5, "reachedAt 1 decodes to the right level")
	eq(at1, 1, "...and time")
	local b2 = Board.decode(C, Board.encode(C, 5, 0))
	eq(b2, 5, "reachedAt 0 (clamped) cannot spill into the next level")
	local b3 = Board.decode(C, Board.encode(C, 5, 3e9))
	eq(b3, 5, "reachedAt past 2e9 (clamped) cannot borrow from the level below")
	-- exact under 2^53 for any level a person can reach: Beacon 100 is ~2e11
	local big = Board.encode(C, 100000, t)
	local bb, bt = Board.decode(C, big)
	eq(bb, 100000, "Beacon 100 000 still decodes exactly")
	eq(bt, t, "...with its time")
	truthy(big < 2 ^ 53, "and stays under 2^53")
	eq(Board.encode(C, -3, t), Board.encode(C, 0, t), "a negative level is stored as 0")
	eq(Board.encode(C, 7.9, t), Board.encode(C, 7, t), "a fractional level is floored")
end

--============================================================================ write only when it improves
do
	local t = 1790000000
	eq(Board.shouldWrite(C, nil, 0), false, "Beacon 0 is not on the chart")
	eq(Board.shouldWrite(C, nil, 1), true, "a first level is written")
	local v = Board.encode(C, 12, t)
	eq(Board.shouldWrite(C, v, 12), false, "the same level is not written again (a rejoin never rewrites)")
	eq(Board.shouldWrite(C, v, 11), false, "a lower level is never written")
	eq(Board.shouldWrite(C, v, 13), true, "a higher level is")
end

--============================================================================ friend ids, capped
do
	local pages = {}
	for p = 1, 5 do
		local page = {}
		for i = 1, 60 do table.insert(page, { Id = p * 1000 + i, Username = "f" .. i }) end
		table.insert(pages, page)
	end
	local idx = 0
	local calls = 0
	local ids = Board.collectFriendIds(C, function()
		calls += 1
		idx += 1
		return pages[idx]
	end)
	eq(#ids, 200, "at most 200 friend ids are collected (300 offered)")
	eq(calls, 4, "and no page past the one that reached the cap is fetched")
	eq(ids[1], 1001, "in the order Roblox gave them")
	local few = Board.collectFriendIds(C, function() return nil end)
	eq(#few, 0, "no pages: no friends, no error")
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
		{ userId = 5, value = Board.encode(C, 10, 100) },
		{ userId = 3, value = Board.encode(C, 22, 200) },
		{ userId = 9, value = Board.encode(C, 22, 150) },
		{ userId = 1, value = Board.encode(C, 4, 50) },
	}
	local sorted = Board.sortRows(rows)
	eq(sorted[1].userId, 9, "Beacon 22 reached first is first")
	eq(sorted[2].userId, 3, "Beacon 22 reached later is second")
	eq(sorted[3].userId, 5, "then 10")
	eq(sorted[4].userId, 1, "then 4")
	eq(sorted[1].beacon, 22, "rows carry the decoded level")
	eq(sorted[1].rank, 1, "and their rank")
	eq(rows[1].userId, 5, "the input is not reordered")
	local tie = Board.sortRows({ { userId = 8, value = 5 }, { userId = 2, value = 5 } })
	eq(tie[1].userId, 2, "identical values fall back to the lower user id, so the order never flickers")
end
do
	eq(Board.emptyFriendsText(C, 22),
		"None of your friends is on the Star Chart yet. Your best: 🌠 Beacon 22. Invite someone: the sky is big enough.",
		"the empty friends view says something useful (DESIGN 9.3)")
	eq(Board.UNAVAILABLE, "Friends list unavailable right now. Showing your own row.", "the failure text")
	eq(Board.loadingText(34, 120), "Loading friends… 34 / 120", "the progress text")
	eq(Board.emojiFor(C, 0), "🌅", "band emoji for Beacon 0")
	eq(Board.emojiFor(C, 22), "🌠", "band emoji for Beacon 22")
	eq(Board.emojiFor(C, 44), "✨", "band emoji for Beacon 44")
	eq(Board.rowText(1, "Nova", 22, "🌠"), "1. Nova  🌠 22", "a row reads rank, name, band emoji, level")
end

--============================================================================ the friends read gate
do
	-- at most 1 read per second per server, only while the budget stays above the reserve
	eq(Board.canRead(C, 10, 9.5, 50), false, "0.5 s after the last read: wait")
	eq(Board.canRead(C, 10, 9, 50), true, "1 s after: read")
	eq(Board.canRead(C, 10, 0, 10), false, "budget at the reserve (10): do not read")
	eq(Board.canRead(C, 10, 0, 11), true, "above the reserve: read")
	eq(Board.canRead(C, 10, -math.huge, 0 / 0), false, "an unknown budget: do not read")
end

print(string.format("Board: %d passed, %d failed", passed, failed))
if failed > 0 then error("Board spec failed", 0) end
