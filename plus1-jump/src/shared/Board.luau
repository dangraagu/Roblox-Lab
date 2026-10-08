--!strict
-- Board — the pure rules of a public + friends highscore board. No Roblox dependencies: the server does the
-- DataStore calls and passes values in, so every rule here runs under the luau CLI (tests/Board.spec.luau).
--
-- The owner's design (docs/complete-game-standard.md §3, 2026-09-16):
--   * rank on a server-measured metric; ties go to whoever reached it FIRST;
--   * OrderedDataStore, key `u_<userId>`, value `metric * 2e9 + (2e9 - reachedAtUnix)`, written only when the
--     metric improves;
--   * public top 10 cached ~60 s; friends fetched on demand, capped, cached, throttle-safe;
--   * an empty friends board says something useful.
-- `cfg` is the game's Config.Board (MaxMetric, FriendsRows, Text).

local Board = {}

local SCALE = 2e9
Board.SCALE = SCALE

-- The stored value. The metric is a whole number in [0, MaxMetric]; below MaxMetric (4e6) every value is an
-- integer under 2^53, so it is exact in a double and an OrderedDataStore takes it. `2e9 - reachedAt` goes
-- negative after 2033-05-18 (unix 2e9); the order still holds, because two reaches of the same metric are
-- never 2e9 seconds (63 years) apart, and decode rounds rather than floors (tests/Board.spec.luau).
function Board.encode(metric: number, reachedAtUnix: number, cfg: any): number
	local m = tonumber(metric) or 0
	if m ~= m then m = 0 end
	m = math.floor(math.clamp(m, 0, cfg.MaxMetric))
	local t = math.floor(tonumber(reachedAtUnix) or 0)
	return m * SCALE + (SCALE - t)
end

-- -> metric, reachedAtUnix. Exact for reach times in (1e9, 3e9): 2001-09 to 2065-01.
function Board.decode(value: number): (number, number)
	local v = tonumber(value) or 0
	local m = math.floor(v / SCALE + 0.5)
	return m, SCALE - (v - m * SCALE)
end

function Board.metricOf(value: number?): number
	if type(value) ~= "number" then return 0 end
	return (Board.decode(value))
end

function Board.key(userId: number): string
	return "u_" .. tostring(userId)
end

function Board.userIdOf(key: string): number?
	local id = string.match(key, "^u_(%d+)$")
	return if id then tonumber(id) else nil
end

-- Written only when the metric improves: the server writes only when its best tier has passed the last one it
-- wrote, and this OrderedDataStore:UpdateAsync transform keeps the stored value unless the new one is HIGHER.
-- Returning nil aborts the write, so a same-metric reach that came later never replaces the first one and an
-- unchanged value costs no write.
function Board.keepHigher(stored: any, new: number): number?
	if type(stored) ~= "number" then return new end
	if Board.metricOf(new) > Board.metricOf(stored) then return new end
	return nil
end

-- entries { { userId, value } } -> a sorted copy, top n: value first (metric, then earliest), then the lower id.
function Board.rank(entries: { any }, n: number): { any }
	local out = table.clone(entries)
	table.sort(out, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.userId < b.userId
	end)
	while #out > n do table.remove(out) end
	return out
end

-- Public view from a GetSortedAsync page (already sorted). Rows carry the decoded metric, never the stored value.
function Board.publicView(sorted: { any }, cfg: any): any
	local rows = {}
	for _, e in sorted do
		local m = Board.metricOf(e.value)
		if m > 0 then
			table.insert(rows, { rank = #rows + 1, userId = e.userId, tier = m })
		end
	end
	return { rows = rows, note = if #rows == 0 then cfg.Text.EmptyPublic else nil }
end

-- The HUD's small top-10 panel: a short note when there are no rows to show (Studio 2026-10-09: it was a blank box).
function Board.hudNote(rows: { any }, cfg: any): string?
	return if #rows == 0 then cfg.Text.EmptyHud else nil
end

-- Friends view. `values` maps userId -> stored value (the viewer's own included); `status` = { friendCount,
-- checked, failed }. The viewer always sees their own row: when they rank below the shown rows, the last row
-- is theirs, with their real rank.
function Board.friendsView(viewerId: number, values: { [number]: number }, status: any, cfg: any): any
	local all = {}
	local friendScored = false
	for id, value in values do
		if Board.metricOf(value) > 0 then
			table.insert(all, { userId = id, value = value })
			if id ~= viewerId then friendScored = true end
		end
	end
	all = Board.rank(all, #all)
	local rows = {}
	local mine = nil
	for i, e in all do
		local row = { rank = i, userId = e.userId, tier = Board.metricOf(e.value), you = e.userId == viewerId }
		if row.you then mine = row end
		if i <= cfg.FriendsRows then table.insert(rows, row) end
	end
	if mine and mine.rank > cfg.FriendsRows then
		rows[#rows] = mine
	end
	local note = nil
	local text = cfg.Text
	if status.failed then
		note = text.FriendsFailed
	elseif (status.friendCount or 0) == 0 then
		note = text.NoFriends
	elseif (status.checked or 0) < status.friendCount then
		note = string.format(text.FriendsChecking, status.checked or 0, status.friendCount)
	elseif not friendScored then
		note = string.format(text.FriendsNoScores, status.friendCount)
	end
	return { rows = rows, note = note }
end

--============================================================================ a TTL cache

function Board.newCache(ttl: number): any
	return { ttl = ttl, entries = {} }
end

function Board.cacheHas(c: any, key: any, now: number): boolean
	local e = c.entries[key]
	return e ~= nil and now - e.at < c.ttl
end

function Board.cacheGet(c: any, key: any, now: number): any
	if Board.cacheHas(c, key, now) then return c.entries[key].value end
	return nil
end

function Board.cachePut(c: any, key: any, value: any, now: number)
	c.entries[key] = { value = value, at = now }
end

--============================================================================ a token bucket

-- At most `capacity` at once, refilling `perSecond`. Over any window of T seconds it grants no more than
-- capacity + perSecond * T.
function Board.newLimiter(capacity: number, perSecond: number, now: number): any
	return { tokens = capacity, cap = capacity, rate = perSecond, t = now }
end

function Board.take(l: any, now: number): boolean
	l.tokens = math.min(l.cap, l.tokens + l.rate * math.max(0, now - l.t))
	l.t = now
	if l.tokens >= 1 then
		l.tokens -= 1
		return true
	end
	return false
end

return Board
