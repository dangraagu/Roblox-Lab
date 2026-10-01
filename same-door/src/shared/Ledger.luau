--!strict
-- Ledger.luau — the profile's pure bookkeeping (DESIGN §6.4, §12). No Roblox.
--
-- Profile data:
--   { v = 1,
--     today = { day, bestMs, bestAt, medal, runs, finishes, postedMs },
--     life  = { doors, silverDays, goldDays, sealerDays, streak, bestStreak, lastDay, runs, firstDay },
--     seenIntro }
--
-- `applyFinish` is the ONLY place a medal day, a Door day, the streak or a rank moves. The server
-- calls it inside one atomic UpdateAsync on the stored copy (the transform may run more than once,
-- so it depends only on the table it is handed), and copies the committed result back into memory.
-- Only string keys and plain numbers: nothing for JSON to turn into a string key.

local Ledger = {}

local MAX_COUNT = 100000

local function count(x: any): number
	local n = tonumber(x)
	if n == nil or n ~= n then return 0 end
	return math.clamp(math.floor(n), 0, MAX_COUNT)
end

local function posInt(x: any): number?
	local n = tonumber(x)
	if n == nil or n ~= n or n <= 0 or n == math.huge then return nil end
	return math.floor(n)
end

local MEDALS = { Bronze = true, Silver = true, Gold = true, Sealer = true }

local function emptyToday(day: number): any
	return { day = day, bestMs = nil, bestAt = nil, medal = nil, runs = 0, finishes = 0, postedMs = nil }
end

function Ledger.new(cfg: any): any
	return {
		v = cfg.Save.ProfileVersion,
		today = emptyToday(0),
		life = { doors = 0, silverDays = 0, goldDays = 0, sealerDays = 0, streak = 0, bestStreak = 0,
			lastDay = 0, runs = 0, firstDay = nil },
		seenIntro = false,
	}
end

-- A clean COPY of whatever the store handed back. Never mutates its input.
function Ledger.normalize(saved: any, cfg: any): any
	local p = Ledger.new(cfg)
	if type(saved) ~= "table" then return p end
	local t = if type(saved.today) == "table" then saved.today else {}
	local l = if type(saved.life) == "table" then saved.life else {}
	p.today.day = count(t.day)
	p.today.bestMs = posInt(t.bestMs)
	p.today.bestAt = posInt(t.bestAt)
	p.today.medal = if MEDALS[t.medal] then t.medal else nil
	p.today.runs = count(t.runs)
	p.today.finishes = count(t.finishes)
	p.today.postedMs = posInt(t.postedMs)
	p.life.doors = count(l.doors)
	p.life.silverDays = count(l.silverDays)
	p.life.goldDays = count(l.goldDays)
	p.life.sealerDays = count(l.sealerDays)
	p.life.streak = count(l.streak)
	p.life.bestStreak = math.max(count(l.bestStreak), p.life.streak)
	p.life.lastDay = count(l.lastDay)
	p.life.runs = count(l.runs)
	p.life.firstDay = posInt(l.firstDay)
	p.seenIntro = saved.seenIntro == true
	return p
end

-- today belongs to `day` from here on (a new UTC day resets it).
function Ledger.rollDay(p: any, day: number)
	if p.today.day ~= day then
		p.today = emptyToday(day)
	end
end

function Ledger.noteRunStart(p: any, day: number)
	if p.today.day < day then Ledger.rollDay(p, day) end
	if p.today.day == day then p.today.runs += 1 end
	p.life.runs = math.min(p.life.runs + 1, MAX_COUNT)
end

-- run = { day, timeMs, medal, at }. Mutates p; returns what happened.
function Ledger.applyFinish(p: any, run: any, cfg: any, Medals: any): any
	local res = { improved = false, late = false, firstSealer = false, rankUp = false,
		rankBefore = Medals.rank(p.life, cfg), rankAfter = 0, newDoorDay = false }
	if p.today.day > run.day then
		-- A run that started before midnight and finished after this profile already has a finish on
		-- the new day. The board of its own day still gets it (the server posts it); the ledger has no
		-- per-day history to credit it to, so it grants nothing.
		res.late = true
		res.rankAfter = res.rankBefore
		return res
	end
	Ledger.rollDay(p, run.day)
	local today, life = p.today, p.life
	today.finishes = math.min(today.finishes + 1, MAX_COUNT)

	if today.finishes == 1 then
		res.newDoorDay = true
		life.doors = math.min(life.doors + 1, MAX_COUNT)
		if life.lastDay == run.day - 1 then
			life.streak = math.min(life.streak + 1, MAX_COUNT)
		elseif life.lastDay ~= run.day then
			life.streak = 1
		end
		life.lastDay = run.day
		life.bestStreak = math.max(life.bestStreak, life.streak)
		if life.firstDay == nil then life.firstDay = run.day end
	end

	if today.bestMs == nil or run.timeMs < today.bestMs then
		today.bestMs = run.timeMs
		today.bestAt = run.at
		res.improved = true
	end

	local before = Medals.tier(today.medal)
	local after = Medals.tier(run.medal)
	if after > before then
		local sealerBefore = life.sealerDays
		for k = before + 1, after do
			if k == 2 then life.silverDays = math.min(life.silverDays + 1, MAX_COUNT) end
			if k == 3 then life.goldDays = math.min(life.goldDays + 1, MAX_COUNT) end
			if k == 4 then life.sealerDays = math.min(life.sealerDays + 1, MAX_COUNT) end
		end
		today.medal = run.medal
		res.firstSealer = sealerBefore == 0 and life.sealerDays >= 1
	end

	res.rankAfter = Medals.rank(life, cfg)
	res.rankUp = res.rankAfter > res.rankBefore
	return res
end

-- The Door streak as of `today` (for display): the stored streak only moves at the next finish, so
-- once a whole day has passed without one it is broken and shows 0 (REVIEW-1). Ranks keep using
-- bestStreak, which never drops.
function Ledger.liveStreak(life: any, today: number): number
	if life.lastDay >= today - 1 then return life.streak end
	return 0
end

-- Does today's best still have to reach the board? (a throttled write, a crash: re-post on join)
function Ledger.needsPost(p: any, day: number): boolean
	local t = p.today
	if t.day ~= day or t.bestMs == nil then return false end
	return t.postedMs == nil or t.postedMs > t.bestMs
end

function Ledger.markPosted(p: any, day: number, ms: number)
	if p.today.day == day then
		p.today.postedMs = ms
	end
end

return Ledger
