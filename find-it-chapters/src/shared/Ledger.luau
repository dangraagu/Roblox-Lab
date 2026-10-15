--!strict
-- Ledger.luau: the saved profile and the one transform that changes it (DESIGN.md §5, §11, §12.1). Pure.
--
-- What persists is progress only: chapters cleared, stars per chapter, the Daily (last credited day, solves,
-- streaks), Cases Solved and when it last rose. NOTHING about an attempt is ever saved: no room, no secret, no
-- progress inside an unfinished attempt, so no read-only session or crash can be used as an oracle
-- (fork-tower REVIEW-4 §9).
--
-- applyClear runs INSIDE the server's atomic UpdateAsync transform: the first clear of a chapter and the
-- Daily's one credit per UTC day are decided there, against the stored record, by the day the attempt STARTED.
-- Star keys are the strings "c1".."c15" (JSON turns sparse integer keys into strings).

local Ledger = {}

local BOOK = 15

local function num(v: any, lo: number, hi: number, default: number): number
	if type(v) ~= "number" or v ~= v then return default end
	return math.clamp(math.floor(v), lo, hi)
end

function Ledger.new(now: number): any
	return {
		v = 1,
		book = { cleared = 0, stars = {} },
		daily = { lastDay = 0, solved = 0, streak = 0, bestStreak = 0 },
		solved = 0,
		solvedAt = 0,
		boarded = 0,
		bookSolvedAt = nil,
		seenIntro = false,
		firstJoin = now,
	}
end

function Ledger.sanitize(rec: any, now: number): any
	local p = Ledger.new(now)
	if type(rec) ~= "table" then return p end
	local book = if type(rec.book) == "table" then rec.book else {}
	p.book.cleared = num(book.cleared, 0, BOOK, 0)
	if type(book.stars) == "table" then
		for ch = 1, BOOK do
			local s = book.stars["c" .. ch]
			if type(s) == "table" then
				p.book.stars["c" .. ch] = { f = s.f == true, w = s.w == true, s = s.s == true }
			end
		end
	end
	local daily = if type(rec.daily) == "table" then rec.daily else {}
	p.daily.lastDay = num(daily.lastDay, 0, 1e7, 0)
	p.daily.solved = num(daily.solved, 0, 1e6, 0)
	p.daily.streak = math.min(num(daily.streak, 0, 1e6, 0), p.daily.solved)
	p.daily.bestStreak = math.max(math.min(num(daily.bestStreak, 0, 1e6, 0), p.daily.solved), p.daily.streak)
	p.solved = p.book.cleared + p.daily.solved
	p.solvedAt = num(rec.solvedAt, 0, 1e10, 0)
	p.boarded = math.min(num(rec.boarded, 0, 1e7, 0), p.solved)
	if type(rec.bookSolvedAt) == "number" and rec.bookSolvedAt == rec.bookSolvedAt and p.book.cleared >= BOOK then
		p.bookSolvedAt = math.floor(rec.bookSolvedAt)
	end
	p.seenIntro = rec.seenIntro == true
	p.firstJoin = num(rec.firstJoin, 0, 1e10, now)
	if p.firstJoin == 0 then p.firstJoin = now end
	return p
end

function Ledger.dayIndex(unix: number): number
	return math.floor(unix / 86400)
end

function Ledger.caseNumber(day: number, cfg: any): number
	return day - cfg.Daily.FirstDay + 1
end

function Ledger.dailyBand(day: number, cfg: any): number
	local nb = #cfg.Env.Bands
	return ((day - cfg.Daily.FirstDay) % nb) + 1
end

function Ledger.title(dailySolved: number, cfg: any): string?
	local best = nil
	for _, t in cfg.Daily.Titles do
		if dailySolved >= t.at then best = t.name end
	end
	return best
end

-- (true) or (false, the chapter that must be cleared first)
function Ledger.canOpen(p: any, chapter: number): (boolean, number?)
	if chapter <= p.book.cleared + 1 then return true, nil end
	return false, p.book.cleared + 1
end

function Ledger.dailyOpen(p: any, cfg: any): boolean
	return p.book.cleared >= cfg.Daily.OpensAfter
end

function Ledger.continueChapter(p: any, cfg: any): number
	return math.min(p.book.cleared + 1, #cfg.Chapters)
end

function Ledger.totalStars(p: any): number
	local n = 0
	for _, s in p.book.stars do
		if s.f then n += 1 end
		if s.w then n += 1 end
		if s.s then n += 1 end
	end
	return n
end

-- The Gold Book (DESIGN.md §10.3): every chapter at three stars. REVIEW-1 round 2 D6: derived, never stored.
function Ledger.goldBook(p: any, cfg: any): boolean
	return Ledger.totalStars(p) >= 3 * #cfg.Chapters
end

-- When a count rose, for the board's tie-break: the start of the UTC day it rose on, never earlier than the last rise.
-- REVIEW-1 round 2 C2 (superseding round 1's A5, which stamped only a Daily credit, with its START day's 00:00): the
-- same count reached on the same day ties (no race at 00:00:20 UTC), a later day always ranks below an earlier one,
-- and nobody is ever stamped before they reached it.
local function rise(p: any, now: number)
	p.solvedAt = math.max(p.solvedAt, Ledger.dayIndex(now) * 86400)
end

-- clear = { kind = "book", chapter, stars } | { kind = "daily", day (the attempt's START day), stars }
-- Mutates p. Returns { first, credited, bookSolved, goldBook, rejected, solvedBefore, solvedAfter }.
function Ledger.applyClear(p: any, clear: any, now: number, cfg: any): any
	local info = { first = false, credited = false, bookSolved = false, goldBook = false, rejected = false, solvedBefore = p.solved, solvedAfter = p.solved }
	local goldBefore = Ledger.goldBook(p, cfg)
	local st = clear.stars or {}
	if clear.kind == "book" then
		local ch = clear.chapter
		if type(ch) ~= "number" or ch < 1 or ch > #cfg.Chapters or ch % 1 ~= 0 or not Ledger.canOpen(p, ch) then
			info.rejected = true
			return info
		end
		if st.f ~= true then
			info.rejected = true
			return info
		end
		local key = "c" .. ch
		local old = p.book.stars[key] or {}
		p.book.stars[key] = { f = old.f == true or st.f == true, w = old.w == true or st.w == true, s = old.s == true or st.s == true }
		if ch > p.book.cleared then
			p.book.cleared = ch
			p.solved += 1
			rise(p, now)
			info.first = true
			if ch == #cfg.Chapters and p.bookSolvedAt == nil then
				p.bookSolvedAt = now
				info.bookSolved = true
			end
		end
	elseif clear.kind == "daily" then
		local day = clear.day
		if type(day) ~= "number" or day ~= day or not Ledger.dailyOpen(p, cfg) or st.f ~= true then
			info.rejected = true
			return info
		end
		local d = p.daily
		if d.lastDay < day then
			d.streak = if d.lastDay == day - 1 then d.streak + 1 else 1
			d.bestStreak = math.max(d.bestStreak, d.streak)
			d.lastDay = day
			d.solved += 1
			p.solved += 1
			-- stamped with the day it was SOLVED (now), never the day the attempt started (REVIEW-1 round 2 C2)
			rise(p, now)
			info.credited = true
		end
	else
		info.rejected = true
	end
	info.solvedAfter = p.solved
	info.goldBook = not goldBefore and Ledger.goldBook(p, cfg)
	return info
end

return Ledger
