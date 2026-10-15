--!strict
-- Board.luau: the Cases Solved board's pure rules. No Roblox: the server does the DataStore calls and passes
-- values in, so every rule runs under the luau CLI (tests/Board.spec.luau).
--
-- Copied from escape-room-lab/src/shared/Board.luau, which is plus1-jump's Board plus three review fixes this
-- game needs as much (0 stores as 0, the reach time is clamped into the exact range, friend reads are paced by
-- the server's own GetAsync request budget with a reserve). Changes here: the metric is Cases Solved and rows
-- carry `solved` (escape-room-lab's carried `stars`); exact ties share a rank (REVIEW-1 A5, `rankOf`).
--
-- The owner's design (docs/complete-game-standard.md §3): OrderedDataStore, key `u_<userId>`, value
-- `solved * 2e9 + (2e9 - reachedAtUnix)`, written only when the count rises, ties to the first to reach it.
-- MaxMetric (1e5) * 2e9 + 2e9 is 2.0e14, under 2^53, so every value is an exact integer.

local Board = {}

local SCALE = 2e9
Board.SCALE = SCALE

-- No cases stores as 0. The reach time is clamped into the exact range below (EPOCH .. EPOCH + SCALE - 1),
-- so no time, however odd, can move a value into the next star (escape-room-lab review 2026-10-01: a fresh profile's
-- reach time 0 encoded to 2e9, which reads as ONE).
function Board.encode(metric: number, reachedAtUnix: number, cfg: any): number
	local m = tonumber(metric) or 0
	if m ~= m then m = 0 end
	m = math.floor(math.clamp(m, 0, cfg.MaxMetric))
	if m == 0 then return 0 end
	local t = tonumber(reachedAtUnix) or 0
	if t ~= t then t = 0 end
	t = math.floor(math.clamp(t, Board.EPOCH, Board.EPOCH + SCALE - 1))
	return m * SCALE + (SCALE - t)
end

-- Every reach time this game can store is after its first build (2026-09-21, unix 1.79e9), so the
-- time part 2e9 - t lies in (-EPOCH, 2e9 - EPOCH] and the split below is exact for reach times from
-- 2026-09-21 to 2090-01 (EPOCH + 2e9). plus1-jump's rounding split is exact only to 2065; the ORDER of
-- stored values holds either way (tests/Board.spec.luau measures both).
local EPOCH = 1.79e9
Board.EPOCH = EPOCH

-- -> metric, reachedAtUnix
function Board.decode(value: number): (number, number)
	local v = math.floor(tonumber(value) or 0)
	local m = math.floor((v + EPOCH - 1) / SCALE)
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

function Board.improves(stored: number?, metric: number): boolean
	return metric > 0 and metric > Board.metricOf(stored)
end

-- The OrderedDataStore UpdateAsync transform: max(old, new) by metric. nil aborts the write, so a later
-- reach of the same total never replaces the first one and a stale write never lowers a rank.
function Board.keepHigher(stored: any, new: number): number?
	if type(stored) ~= "number" then return new end
	if Board.metricOf(new) > Board.metricOf(stored) then return new end
	return nil
end

function Board.rank(entries: { any }, n: number): { any }
	local out = table.clone(entries)
	table.sort(out, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.userId < b.userId
	end)
	while #out > n do table.remove(out) end
	return out
end

-- Competition ranking (1, 1, 3): an exact tie (the same count reached at the same moment, e.g. the same Daily on
-- its day: Ledger.applyClear) shares its rank. REVIEW-1 A5; the ONE other change from escape-room-lab's Board.
local function rankOf(rows: { any }, value: number): number
	local prev = rows[#rows]
	if prev and prev.value == value then return prev.rank end
	return #rows + 1
end

function Board.publicView(sorted: { any }, cfg: any): any
	local rows = {}
	for _, e in sorted do
		local m = Board.metricOf(e.value)
		if m > 0 then
			table.insert(rows, { rank = rankOf(rows, e.value), userId = e.userId, solved = m, value = e.value })
		end
	end
	return { rows = rows, note = if #rows == 0 then cfg.Text.EmptyPublic else nil }
end

-- values: userId -> stored value (the viewer's own included); status = { friendCount, checked, failed }.
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
	local ranked = {}
	local mine = nil
	for i, e in all do
		local row = { rank = rankOf(ranked, e.value), userId = e.userId, solved = Board.metricOf(e.value), you = e.userId == viewerId, value = e.value }
		table.insert(ranked, row)
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
	elseif status.partial and (status.checked or 0) < status.friendCount then
		note = string.format(text.FriendsPartial, status.checked or 0, status.friendCount)
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

--============================================================================ the read pacer

-- May a friend's score be read now? Only while the server's GetAsync budget is above the reserve.
function Board.mayRead(budget: any, reserve: number): boolean
	if type(budget) ~= "number" or budget ~= budget then return false end
	return budget > reserve
end

-- One friend-score read: "read" above the reserve; at or under it "wait" (a second at a time) until the
-- wait has lasted `maxWait`, then "stop": the view ends there and says how far it got. The server runs
-- one read at a time, so this check before each read is exact (review 2026-10-01).
function Board.readStep(budget: any, reserve: number, waited: number, maxWait: number): string
	if Board.mayRead(budget, reserve) then return "read" end
	if waited < maxWait then return "wait" end
	return "stop"
end

return Board
