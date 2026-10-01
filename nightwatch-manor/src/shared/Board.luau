--!strict
-- Board.luau — the public + friends board of nights survived: its pure rules. No Roblox dependency: the server does
-- the DataStore and Players calls and passes values in, so every rule here runs under the luau CLI
-- (tests/Board.spec.luau).
--
-- The owner's design (docs/complete-game-standard.md §3, 2026-09-16):
--   * rank on a server-measured metric: here the best night the SERVER credited you with surviving (Night.resolve on
--     an EXTRACTED outcome, which the Servants' Exit grants only through the crossing guard, Crossing.luau);
--   * ties go to whoever reached that night FIRST;
--   * OrderedDataStore, key `u_<userId>`, value `night * 2e9 + (2e9 - reachedAtUnix)`, written only when the night
--     improves;
--   * public top 10 cached ~60 s; friends fetched only on demand, capped, cached, throttle-safe;
--   * an empty friends board says something useful.
-- `cfg` is Config.Board.

local Board = {}

local SCALE = 2e9
Board.SCALE = SCALE

-- The stored value. The night is a whole number in [0, MaxMetric] (MaxMetric = Config.Night.MaxNight, 500), so every
-- value is an integer far under 2^53: exact in a double, and an OrderedDataStore takes it. `2e9 - reachedAt` goes
-- negative after 2033-05-18 (unix 2e9); the order still holds, because two reaches of the same night are never 2e9
-- seconds (63 years) apart, and decode rounds rather than floors.
function Board.encode(night: number, reachedAtUnix: number, cfg: any): number
	local m = tonumber(night) or 0
	if m ~= m then m = 0 end
	m = math.floor(math.clamp(m, 0, cfg.MaxMetric))
	local t = math.floor(tonumber(reachedAtUnix) or 0)
	return m * SCALE + (SCALE - t)
end

-- -> night, reachedAtUnix. Exact for reach times in (1e9, 3e9): 2001-09 to 2065-01.
function Board.decode(value: number): (number, number)
	local v = tonumber(value) or 0
	local m = math.floor(v / SCALE + 0.5)
	return m, SCALE - (v - m * SCALE)
end

function Board.nightOf(value: any): number
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

-- The OrderedDataStore:UpdateAsync transform. It keeps the stored value unless the new NIGHT is higher: returning nil
-- aborts the write, so a same-night reach that came later never replaces the first one, and nothing ever lowers the
-- board (a stale server, a lost profile write).
function Board.keepHigher(stored: any, new: number): number?
	if type(stored) ~= "number" then return new end
	if Board.nightOf(new) > Board.nightOf(stored) then return new end
	return nil
end

-- entries { { userId, value } } -> a sorted copy, top n: the value first (night, then the earlier reach), then the
-- lower id. The input is never changed.
function Board.rank(entries: { any }, n: number): { any }
	local out = table.clone(entries)
	table.sort(out, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.userId < b.userId
	end)
	while #out > n do table.remove(out) end
	return out
end

-- The public view, from a GetSortedAsync page (already sorted). Rows carry the decoded night, never the stored value.
-- A player on night 0 (never got out) is not a row.
function Board.publicView(sorted: { any }, cfg: any): any
	local rows = {}
	for _, e in sorted do
		local m = Board.nightOf(e.value)
		if m > 0 then
			table.insert(rows, { rank = #rows + 1, userId = e.userId, night = m })
		end
	end
	return { rows = rows, note = if #rows == 0 then cfg.Text.EmptyPublic else nil }
end

-- The friends view. `values` maps userId -> stored value (the viewer's own included); `status` = { friendCount,
-- checked, failed }. The viewer always sees their own row: when they rank below the rows shown, the last row is
-- theirs, with their real rank.
function Board.friendsView(viewerId: number, values: { [number]: number }, status: any, cfg: any): any
	local all = {}
	local friendScored = false
	for id, value in values do
		if Board.nightOf(value) > 0 then
			table.insert(all, { userId = id, value = value })
			if id ~= viewerId then friendScored = true end
		end
	end
	all = Board.rank(all, #all)
	local rows = {}
	local mine = nil
	for i, e in all do
		local row = { rank = i, userId = e.userId, night = Board.nightOf(e.value), you = e.userId == viewerId }
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

-- One line of the physical board.
function Board.rowText(row: any, cfg: any): string
	local name = if type(row.name) == "string" and row.name ~= "" then row.name else "?"
	return string.format("%d. %s%s   night %d", row.rank or 0, name, if row.you then " (you)" else "", row.night or 0)
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
