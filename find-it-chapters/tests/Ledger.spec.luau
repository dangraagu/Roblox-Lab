-- Spec for Ledger: the profile, first clears, the Daily credit and streaks, Cases Solved (DESIGN.md §5, §11, §12.1).
-- Run: luau tests/Ledger.spec.luau 2>&1
local Ledger = require("../src/shared/Ledger")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local NOW = 1791331200 -- 2026-10-07 00:00 UTC (dayIndex 20733)

--============================================================ days, case numbers, themes
eq(Ledger.dayIndex(NOW), 20733, "2026-10-07 is dayIndex 20733 (floor(unix / 86400))")
eq(Ledger.dayIndex(NOW - 1), 20732, "one second before midnight UTC is the day before")
eq(Ledger.dayIndex(NOW + 86399), 20733, "the last second of the day")
eq(Ledger.caseNumber(20733, Config), 1, "2026-10-07 is Case #1")
eq(Ledger.caseNumber(20740, Config), 8, "a week later Case #8")
eq(Ledger.dailyBand(20733, Config), 1, "Case #1 is in band 1 (cottage)")
eq(Ledger.dailyBand(20737, Config), 5, "Case #5 is in band 5 (observatory)")
eq(Ledger.dailyBand(20738, Config), 1, "the theme rotates")
eq(Ledger.dailyBand(20000, Config) >= 1 and Ledger.dailyBand(20000, Config) <= 5, true, "a day before the first case still maps to a band")

--============================================================ a fresh profile
local p = Ledger.new(NOW)
eq(p.v, 1, "version 1")
eq(p.book.cleared, 0, "nothing cleared")
eq(p.solved, 0, "0 Cases Solved")
eq(p.daily.lastDay, 0, "no Daily yet")
eq(Ledger.canOpen(p, 1), true, "chapter 1 is open")
local ok2, why2 = Ledger.canOpen(p, 2)
eq(ok2, false, "chapter 2 is locked")
eq(why2, 1, "... until chapter 1 is cleared")
eq(Ledger.dailyOpen(p, Config), false, "the Daily is locked for a new player")
eq(Ledger.continueChapter(p, Config), 1, "Continue is chapter 1")

--============================================================ first clears
local info = Ledger.applyClear(p, { kind = "book", chapter = 1, stars = { f = true, w = false, s = true } }, NOW + 50, Config)
eq(info.first, true, "a first clear")
eq(info.solvedBefore, 0, "Cases Solved before")
eq(info.solvedAfter, 1, "and after: +1")
eq(p.book.cleared, 1, "cleared 1")
eq(p.solvedAt, NOW, "solvedAt is the UTC day the count rose (the board's tie-break; REVIEW-1 round 2 C2)")
eq(p.book.stars.c1.f, true, "Found stored under the STRING key c1")
eq(p.book.stars.c1.s, true, "Sharp Eye stored")
eq(p.book.stars[1], nil, "never an integer key (JSON would turn sparse integer keys into strings)")
local again = Ledger.applyClear(p, { kind = "book", chapter = 1, stars = { f = true, w = true, s = false } }, NOW + 90, Config)
eq(again.first, false, "a replay is not a first clear")
eq(p.solved, 1, "a replay adds no Cases Solved")
eq(p.solvedAt, NOW, "and does not move solvedAt")
truthy(p.book.stars.c1.w and p.book.stars.c1.s, "a replay can add a star; stars once earned are kept")
local skip = Ledger.applyClear(p, { kind = "book", chapter = 5, stars = { f = true } }, NOW + 99, Config)
eq(skip.rejected, true, "a clear of a locked chapter is rejected")
eq(p.book.cleared, 1, "and changes nothing")

--============================================================ the Daily opens after chapter 3
for ch = 2, 3 do Ledger.applyClear(p, { kind = "book", chapter = ch, stars = { f = true } }, NOW + 100 * ch, Config) end
eq(Ledger.dailyOpen(p, Config), true, "the Daily opens after chapter 3")
eq(p.solved, 3, "3 chapters: 3 Cases Solved")

--============================================================ the Daily credit: once per UTC day, by the START day
local d = Ledger.applyClear(p, { kind = "daily", day = 20733, stars = { f = true } }, NOW + 400, Config)
eq(d.credited, true, "today's first solve credits")
eq(p.solved, 4, "Cases Solved +1")
eq(p.daily.solved, 1, "Daily solved 1")
eq(p.daily.streak, 1, "streak 1")
local d2 = Ledger.applyClear(p, { kind = "daily", day = 20733, stars = { f = true } }, NOW + 900, Config)
eq(d2.credited, false, "a second solve the same day credits nothing")
eq(p.solved, 4, "Cases Solved unchanged")
-- an attempt that STARTED yesterday and finished after midnight credits yesterday
local p2 = Ledger.new(NOW)
for ch = 1, 3 do Ledger.applyClear(p2, { kind = "book", chapter = ch, stars = { f = true } }, NOW, Config) end
local y = Ledger.applyClear(p2, { kind = "daily", day = 20732, stars = { f = true } }, NOW + 30, Config)
eq(y.credited, true, "an attempt started on day 20732 credits day 20732, even after midnight")
local t = Ledger.applyClear(p2, { kind = "daily", day = 20733, stars = { f = true } }, NOW + 60, Config)
eq(t.credited, true, "and the new day can still be credited")
eq(p2.daily.streak, 2, "two consecutive days: streak 2")
local stale = Ledger.applyClear(p2, { kind = "daily", day = 20730, stars = { f = true } }, NOW + 90, Config)
eq(stale.credited, false, "a stale day (before the last credited) credits nothing")
-- streaks restart after a gap
Ledger.applyClear(p2, { kind = "daily", day = 20736, stars = { f = true } }, NOW + 3 * 86400, Config)
eq(p2.daily.streak, 1, "a missed day restarts the streak at 1")
eq(p2.daily.bestStreak, 2, "the best streak is kept")
eq(p2.solved, 3 + 3, "Cases Solved = 3 chapters + 3 Daily Cases")

--============================================================ REVIEW-1 round 2, C2: EVERY rise is reached on the UTC DAY it happened
-- The board breaks ties by who reached a count first. Round 1 (A5) stamped only a Daily credit with the start of its
-- day, so that a script solving Case #N at 00:00:20 could not out-rank everyone who solved it later that day. That
-- made the board unfair the other way (round 2, C2): a Daily solved at 22:00 was "reached" at 00:00 and out-ranked a
-- chapter clear at 01:00 of the same day, and a Daily credited by the day its attempt STARTED carried yesterday's
-- 00:00 into today. Now every rise, chapter or Daily, is stamped with the start of the UTC day it happened on (never
-- earlier than the last rise): the same count reached on the same day ties (a shared rank, Board.spec), a later day
-- always ranks below an earlier one, and nobody can reach a count before they did.
do
	local Board = require("../src/shared/Board")
	local DAY = 20740
	local D = 86400
	local function prof(cleared, dsolved, at)
		local q = Ledger.new(NOW)
		for ch = 1, cleared do Ledger.applyClear(q, { kind = "book", chapter = ch, stars = { f = true } }, at, Config) end
		for i = 1, dsolved do Ledger.applyClear(q, { kind = "daily", day = DAY - 40 + i, stars = { f = true } }, at, Config) end
		return q
	end
	local function value(q) return Board.encode(q.solved, q.solvedAt, Config.Board) end
	-- the reviewer's case: A reaches 18 at 01:00 by a chapter, B reaches 18 at 22:00 by the Daily, the same day
	local A, B = prof(13, 4, (DAY - 1) * D), prof(14, 3, (DAY - 1) * D)
	Ledger.applyClear(A, { kind = "book", chapter = 14, stars = { f = true } }, DAY * D + 3600, Config)
	Ledger.applyClear(B, { kind = "daily", day = DAY, stars = { f = true } }, DAY * D + 22 * 3600, Config)
	eq(A.solved, 18, "C2: A reached 18 at 01:00 (a chapter)")
	eq(B.solved, 18, "C2: B reached 18 at 22:00 (the Daily)")
	eq(A.solvedAt, DAY * D, "C2: a chapter clear is stamped with its UTC day")
	eq(B.solvedAt, DAY * D, "C2: so is a Daily credit")
	truthy(value(A) >= value(B), "C2: B, later the same day, never out-ranks A (they tie)")
	-- a later DAY always ranks below
	local C = prof(14, 3, (DAY - 1) * D)
	Ledger.applyClear(C, { kind = "daily", day = DAY + 1, stars = { f = true } }, (DAY + 1) * D + 60, Config)
	eq(C.solved, 18, "C2: C reached 18 the next day at 00:01")
	truthy(value(C) < value(A), "C2: ... and ranks below A and B")
	-- round 1's A5 is kept: a script at 00:00:20 and a person at 18:00 solving the same Daily tie
	local bot, human = prof(15, 0, (DAY - 1) * D - 5000), prof(15, 0, (DAY - 1) * D - 9000)
	Ledger.applyClear(bot, { kind = "daily", day = DAY, stars = { f = true } }, DAY * D + 20, Config)
	Ledger.applyClear(human, { kind = "daily", day = DAY, stars = { f = true } }, DAY * D + 18 * 3600, Config)
	eq(value(bot), value(human), "C2/A5: a Daily solved at 00:00:20 and one at 18:00 tie: no race at midnight")
	-- an attempt that STARTED yesterday and was solved after midnight credits yesterday's case (the streak holds),
	-- but it is reached TODAY, the day it was solved
	local y = prof(15, 0, (DAY - 3) * D)
	y.daily.lastDay, y.daily.streak = DAY - 2, 4
	local info = Ledger.applyClear(y, { kind = "daily", day = DAY - 1, stars = { f = true } }, DAY * D + 30, Config)
	eq(info.credited, true, "C2: the attempt started yesterday credits yesterday's case")
	eq(y.daily.streak, 5, "C2: ... and the streak goes on")
	eq(y.solvedAt, DAY * D, "C2: but it is reached on the day it was solved, never on the day it started")
	-- never earlier than the last rise (a clock running backwards changes nothing)
	local z = prof(3, 0, DAY * D + 5 * 3600)
	Ledger.applyClear(z, { kind = "daily", day = DAY - 1, stars = { f = true } }, (DAY - 1) * D, Config)
	eq(z.solvedAt, DAY * D, "C2: a reach time never moves back")
end

--============================================================ REVIEW-1 round 2, D6: the Gold Book (every star) is reported once
do
	local q = Ledger.new(NOW)
	local three = { f = true, w = true, s = true }
	for ch = 1, 15 do
		Ledger.applyClear(q, { kind = "book", chapter = ch, stars = if ch == 15 then { f = true, w = true, s = false } else three }, NOW + ch, Config)
	end
	eq(Ledger.totalStars(q), 44, "D6: 44 of 45 stars")
	eq(Ledger.goldBook(q, Config), false, "D6: not yet the Gold Book")
	local g = Ledger.applyClear(q, { kind = "book", chapter = 15, stars = three }, NOW + 99, Config)
	eq(g.goldBook, true, "D6: the clear that earns the 45th star reports the Gold Book")
	eq(Ledger.goldBook(q, Config), true, "D6: the profile has the Gold Book")
	local again = Ledger.applyClear(q, { kind = "book", chapter = 15, stars = three }, NOW + 199, Config)
	eq(again.goldBook, false, "D6: only the first time")
	local fresh = Ledger.applyClear(Ledger.new(NOW), { kind = "book", chapter = 1, stars = three }, NOW, Config)
	eq(fresh.goldBook, false, "D6: one chapter at three stars is not the Gold Book")
end

--============================================================ titles
eq(Ledger.title(6, Config), nil, "no title before 7 Daily solves")
eq(Ledger.title(7, Config), "Detective", "7: Detective")
eq(Ledger.title(30, Config), "Inspector", "30: Inspector")
eq(Ledger.title(100, Config), "Master Finder", "100: Master Finder")

--============================================================ BOOK ONE SOLVED
do
	local q = Ledger.new(NOW)
	for ch = 1, 14 do Ledger.applyClear(q, { kind = "book", chapter = ch, stars = { f = true } }, NOW + ch, Config) end
	eq(q.bookSolvedAt, nil, "not solved before chapter 15")
	local last = Ledger.applyClear(q, { kind = "book", chapter = 15, stars = { f = true } }, NOW + 999, Config)
	eq(last.bookSolved, true, "the first clear of chapter 15 is BOOK ONE SOLVED")
	eq(q.bookSolvedAt, NOW + 999, "bookSolvedAt stored")
	local re = Ledger.applyClear(q, { kind = "book", chapter = 15, stars = { f = true, w = true } }, NOW + 2000, Config)
	eq(re.bookSolved, false, "a replay of chapter 15 is not a second brag")
	eq(Ledger.continueChapter(q, Config), 15, "Continue stays on chapter 15 when the Book is done")
	eq(q.solved, 15, "15 Cases Solved from the Book, at most")
end

--============================================================ sanitize: a hostile or old record
do
	local s = Ledger.sanitize({
		v = 1, book = { cleared = 99, stars = { c1 = { f = true, w = "yes", s = 1 }, ["2"] = { f = true }, c20 = { f = true }, c3 = "x" } },
		daily = { lastDay = -5, solved = -3, streak = 1e9, bestStreak = 0 / 0 },
		solved = 1e12, solvedAt = "later", boarded = -1, bookSolvedAt = {}, seenIntro = "no", firstJoin = 0 / 0,
	}, NOW)
	eq(s.book.cleared, 15, "cleared clamped to 15")
	eq(s.book.stars.c1.f, true, "a real star survives")
	eq(s.book.stars.c1.w, false, "a non-boolean star is false")
	eq(s.book.stars.c1.s, false, "a number is not a star")
	eq(s.book.stars["2"], nil, "unknown keys dropped")
	eq(s.book.stars.c20, nil, "keys past c15 dropped")
	eq(s.book.stars.c3, nil, "a non-table entry dropped")
	eq(s.daily.lastDay, 0, "a negative day is 0")
	eq(s.daily.solved, 0, "a negative count is 0")
	truthy(s.daily.streak <= s.daily.solved, "a streak can never exceed the solves")
	eq(s.solved, s.book.cleared + s.daily.solved, "Cases Solved is recomputed: cleared + daily solves")
	eq(s.solvedAt, 0, "a non-number time is 0")
	eq(s.boarded, 0, "boarded clamped")
	eq(s.bookSolvedAt, nil, "a non-number bookSolvedAt is dropped")
	eq(s.seenIntro, false, "a non-boolean flag is false")
	eq(s.firstJoin, NOW, "a NaN firstJoin is now")
	local e = Ledger.sanitize(nil, NOW)
	eq(e.book.cleared, 0, "nil: a fresh profile")
	local str = Ledger.sanitize("junk", NOW)
	eq(str.solved, 0, "junk: a fresh profile")
end

--============================================================ the record never carries an attempt
do
	local q = Ledger.new(NOW)
	local keys = {}
	for k in q do table.insert(keys, k) end
	table.sort(keys)
	eq(table.concat(keys, ","), "boarded,book,daily,firstJoin,seenIntro,solved,solvedAt,v",
		"the profile holds progress only: no room, no secret, no attempt state")
end

print(string.format("Ledger: %d passed, %d failed", passed, failed))
if failed > 0 then error("Ledger spec failed", 0) end
