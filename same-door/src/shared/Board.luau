--!strict
-- Board.luau — the public + friends highscore board's pure rules (DESIGN §10). No Roblox.
--
-- Metric: today's best VERIFIED run time in ms, measured by the server (lower is better). Stored in
-- an OrderedDataStore (scope d<dayIndex>, key u_<userId>) as
--     value = (CapMs - timeMs) * 2e9 + (2e9 - reachedAtUnix)
-- so a faster time ranks first and an equal time goes to whoever reached it first. The largest value
-- is 1.800002e15 < 2^53: every intermediate is an exact integer. The tie term stays positive until
-- unix 2e9 (2033-05-18); encode refuses from then on, so the version must change before that.
--
-- Nothing here reads a time from a client. The server is the only writer (src/server/Main).

local Board = {}

local function isInt(x: any): boolean
	return type(x) == "number" and x == x and x % 1 == 0 and x ~= math.huge and x ~= -math.huge
end

function Board.encode(timeMs: number, reachedAt: number, bc: any): number?
	if not isInt(timeMs) or not isInt(reachedAt) then return nil end
	if timeMs < 1 or timeMs >= bc.CapMs then return nil end
	if reachedAt < 1 or reachedAt >= bc.TieBase then return nil end
	return (bc.CapMs - timeMs) * bc.TieBase + (bc.TieBase - reachedAt)
end

function Board.decode(value: number, bc: any): (number?, number?)
	if not isInt(value) or value <= 0 then return nil, nil end
	local metric = value // bc.TieBase
	local tie = value - metric * bc.TieBase
	local timeMs = bc.CapMs - metric
	local reachedAt = bc.TieBase - tie
	if timeMs < 1 or timeMs >= bc.CapMs then return nil, nil end
	return timeMs, reachedAt
end

-- The UpdateAsync transform for a board write: keep the old value unless the new one is better.
-- Returning nil aborts the write (Roblox and the emulator both leave the stored value untouched).
function Board.improve(newValue: number): (any) -> number?
	return function(old: any): number?
		if isInt(old) and old >= newValue then
			return nil
		end
		return newValue
	end
end

function Board.key(userId: number): string
	return "u_" .. tostring(math.floor(userId))
end

function Board.userIdOf(key: string): number?
	local id = string.match(tostring(key), "^u_(%d+)$")
	return if id then tonumber(id) else nil
end

-- entries: { { key, value } } in board order. nameOf(userId) -> string; gradeOf(timeMs) -> medal?.
function Board.rows(entries: { any }, nameOf: (number) -> string, gradeOf: (number) -> string?, bc: any): { any }
	local out = {}
	for _, e in entries do
		local uid = Board.userIdOf(e.key)
		local t = if uid then (Board.decode(e.value, bc)) else nil
		if uid and t then
			local medal = gradeOf(t)
			-- the same text as Medals.formatTime (truncated hundredths); kept local so this module
			-- takes no dependency
			local cs = t // 10
			local secs = cs // 100
			local text = if secs < 60 then string.format("%d.%02d", secs, cs % 100)
				else string.format("%d:%02d.%02d", secs // 60, secs % 60, cs % 100)
			table.insert(out, {
				rank = #out + 1,
				userId = uid,
				name = nameOf(uid),
				timeMs = t,
				time = text,
				medal = medal,
				sealed = medal == "Sealer",
			})
		end
	end
	return out
end

function Board.capFriends(ids: { number }, bc: any): { number }
	local out = {}
	for i = 1, math.min(#ids, bc.FriendsCap) do
		out[i] = ids[i]
	end
	return out
end

-- May the friends reader spend one more GetAsync? Only while the budget stays above the reserve.
function Board.mayRead(budget: number?, bc: any): boolean
	return type(budget) == "number" and budget > bc.FriendsBudgetReserve
end

-- { { userId, value } } -> sorted best first (value descending; ties by userId for a stable order).
function Board.sortFound(found: { any }): { any }
	local out = table.clone(found)
	table.sort(out, function(a: any, b: any): boolean
		if a.value ~= b.value then return a.value > b.value end
		return a.userId < b.userId
	end)
	return out
end

function Board.fresh(at: number?, now: number, ttl: number): boolean
	return type(at) == "number" and now - at < ttl
end

-- A bounded name cache (names are never stored, only cached per server).
function Board.newNameCache(): any
	return { names = {}, order = {}, head = 1, tail = 0 }
end

function Board.rememberName(cache: any, userId: number, name: string, bc: any)
	if cache.names[userId] == nil then
		cache.tail += 1
		cache.order[cache.tail] = userId
	end
	cache.names[userId] = name
	while cache.tail - cache.head + 1 > bc.NameCacheMax do
		local old = cache.order[cache.head]
		cache.order[cache.head] = nil
		cache.head += 1
		cache.names[old] = nil
	end
end

function Board.cachedName(cache: any, userId: number): string?
	return cache.names[userId]
end

function Board.nameCount(cache: any): number
	return cache.tail - cache.head + 1
end

return Board
