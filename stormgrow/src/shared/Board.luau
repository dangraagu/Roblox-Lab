--!strict
-- Board.luau — the Almanac highscore board, public and friends (DESIGN.md §7). Pure, no requires.
--
-- Metric: Almanac entries (0-56), granted only by the server's strike loop. Ties go to whoever reached
-- the count FIRST. OrderedDataStore value = count * Epoch + (Epoch - reachedAtUnix), key "u_<userId>":
-- an integer, at most 56 * 2e9 + 2e9 = 1.14e11, far under 2^53. The tie-break holds until Unix 2e9
-- (2033-05-18). Writes only go up (transform), at most one per player per WriteCoalesceSeconds.
-- B is Config.Board.

local Board = {}

-- Config.Board.Epoch; Board.spec asserts the two agree (the row builders decode with this one)
local EPOCH = 2e9

Board.TEXT = {
	friendsEmpty = "None of your friends has an Almanac entry in the top 500 yet. Invite one: there are six farms in this valley.",
	friendsFailed = "Couldn't load your friends right now. Showing everyone.",
	publicEmpty = "No farmer has found an Almanac entry yet. Be the first: leave a ripe crop out in the storm.",
	publicFailed = "The board is resting. It will try again in a minute.",
	loading = "Loading the board…",
}

function Board.encode(count: number, reachedAt: number, B: any): number
	if count <= 0 then return 0 end
	return math.floor(count) * B.Epoch + (B.Epoch - math.floor(reachedAt))
end

function Board.decode(value: number, B: any): (number, number)
	if type(value) ~= "number" or value <= 0 then return 0, 0 end
	local count = math.floor(value / B.Epoch)
	local rest = value - count * B.Epoch
	if rest == 0 then
		-- reachedAt == Epoch exactly would need count - 1; never happens before 2033
		return count, B.Epoch
	end
	return count, B.Epoch - rest
end

-- The UpdateAsync transform: write `value` only over a lower (or missing, or junk) stored value.
function Board.transform(value: number): (any) -> number?
	return function(old: any): number?
		if type(old) == "number" and old >= value then return nil end
		return value
	end
end

-- per-player write state: { written = last value written, lastAt = when }
function Board.newWriter(): any
	return { written = 0, lastAt = -math.huge }
end

-- Is a write of `value` due now? Only an improvement, only WriteCoalesceSeconds after the last write,
-- unless `flush` (leaving). A zero value is never written.
function Board.due(st: any, value: number, now: number, B: any, flush: boolean?): boolean
	if value <= 0 or value <= st.written then return false end
	if flush then return true end
	return now - st.lastAt >= B.WriteCoalesceSeconds
end

function Board.wrote(st: any, value: number, now: number)
	st.written = math.max(st.written, value)
	st.lastAt = now
end

function Board.keyOf(userId: number): string
	return "u_" .. tostring(math.floor(userId))
end

function Board.userIdOf(key: any): number?
	if type(key) ~= "string" then return nil end
	local id = string.match(key, "^u_(%d+)$")
	return if id then tonumber(id) else nil
end

-- A GetSortedAsync page ({ { key, value } }, highest first) -> the first `shown` rows
-- { rank, userId, count }. Keys that are not u_<id> are skipped.
function Board.publicRows(page: { any }, shown: number): { any }
	local rows = {}
	for _, e in page do
		local id = Board.userIdOf(e.key)
		if id ~= nil and type(e.value) == "number" and e.value > 0 then
			local count = math.floor(e.value / EPOCH)
			table.insert(rows, { rank = #rows + 1, userId = id, count = count, value = e.value })
			if #rows >= shown then break end
		end
	end
	return rows
end

-- The first `cap` friend ids, in the order Roblox returns them -> (set, n)
function Board.capFriends(ids: { number }, cap: number): ({ [number]: boolean }, number)
	local set, n = {}, 0
	for _, id in ids do
		if n >= cap then break end
		if not set[id] then
			set[id] = true
			n += 1
		end
	end
	return set, n
end

-- The friends view: me plus every friend with a value in `sources` (players in this server from memory,
-- and the top-500 cache), best value per user, highest first, at most `shown` rows. I am always in it.
-- -> { rows = { { rank, userId, count, value, you? } }, empty = no friend has an entry }
function Board.friendsView(me: number, friends: { [number]: boolean }, sources: { any }, shown: number): any
	local best: { [number]: number } = {}
	for _, s in sources do
		if (s.userId == me or friends[s.userId]) and type(s.value) == "number" then
			if best[s.userId] == nil or s.value > best[s.userId] then
				best[s.userId] = s.value
			end
		end
	end
	if best[me] == nil then best[me] = 0 end
	local list = {}
	local friendsFound = 0
	for id, v in best do
		table.insert(list, { userId = id, value = v })
		if id ~= me and v > 0 then friendsFound += 1 end
	end
	table.sort(list, function(a: any, b: any): boolean
		if a.value ~= b.value then return a.value > b.value end
		return a.userId < b.userId
	end)
	local rows = {}
	for i, e in list do
		if #rows >= shown and e.userId ~= me then continue end
		table.insert(rows, {
			rank = i, userId = e.userId, count = math.floor(e.value / EPOCH), value = e.value,
			you = if e.userId == me then true else nil,
		})
	end
	return { rows = rows, empty = friendsFound == 0 }
end

-- The line pinned under the rows.
function Board.youLine(rows: { any }, me: number, count: number): string
	for _, r in rows do
		if r.userId == me then
			return string.format("You: #%d · 📖 %d", r.rank, count)
		end
	end
	return string.format("You: 📖 %d (not in this list)", count)
end

return Board
