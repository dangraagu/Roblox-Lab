--!strict
-- Board.luau — the Star Chart: encoding, the write rule, friend ids, ranking and texts. PURE.
--
-- The metric is the Beacon level, which only the server raises, by a purchase it validated, paid with
-- Stardust only the server mints from ore only the server spawned on the player's own plot and only
-- a walk the server's trusted position could make picked up (DESIGN 9.1). Value =
-- beacon * Scale + (Scale - beaconAt): a higher level always ranks higher, and at the same level the
-- player who reached it FIRST ranks higher (beaconAt is the profile's own time of first reaching it,
-- not the write time). Exact under 2^53 while beacon < 4.5e6.
-- Requires nothing; takes the game's Config as `cfg`. Spec: tests/Board.spec.luau.

local Board = {}

Board.UNAVAILABLE = "Friends list unavailable right now. Showing your own row."

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Board.encode(cfg: any, beacon: number, reachedAt: number): number
	local S = cfg.Board.Scale
	local b = if finite(beacon) then math.max(0, math.floor(beacon)) else 0
	-- reachedAt must stay inside (0, Scale) or it would spill into the neighbouring level
	local t = if finite(reachedAt) then math.clamp(math.floor(reachedAt), 1, S - 1) else S - 1
	return b * S + (S - t)
end

function Board.decode(cfg: any, value: number): (number, number)
	local S = cfg.Board.Scale
	if not finite(value) or value <= 0 then return 0, 0 end
	local b = math.floor((value - 1) / S)
	local rem = value - b * S
	return b, S - rem
end

-- Write only when the level improves on the last value this server wrote or read for the player.
function Board.shouldWrite(cfg: any, lastValue: number?, beacon: number): boolean
	if not finite(beacon) or beacon < 1 then return false end
	if lastValue == nil then return true end
	local lastBeacon = Board.decode(cfg, lastValue)
	return math.floor(beacon) > lastBeacon
end

-- The first FriendsCap friend ids. `nextPage()` returns the next page's items ({ Id = number, ... })
-- or nil; it is not called again once the cap is reached.
function Board.collectFriendIds(cfg: any, nextPage: () -> { any }?): { number }
	local cap = cfg.Board.FriendsCap
	local ids = {}
	while #ids < cap do
		local page = nextPage()
		if type(page) ~= "table" or #page == 0 then break end
		for _, item in page do
			if type(item) == "table" and type(item.Id) == "number" and item.Id > 0 then
				table.insert(ids, item.Id)
				if #ids >= cap then break end
			end
		end
	end
	return ids
end

-- rows = { { userId, value, ... } } -> a NEW list, best first, each with .rank and the decoded .beacon
-- and .at. Identical values fall back to the lower user id, so the order never flickers between refreshes.
function Board.rank(cfg: any, rows: { any }): { any }
	local out = {}
	for _, r in rows do
		table.insert(out, table.clone(r))
	end
	table.sort(out, function(a, b)
		if a.value == b.value then return a.userId < b.userId end
		return a.value > b.value
	end)
	for i, r in out do
		r.rank = i
		r.beacon, r.at = Board.decode(cfg, r.value)
	end
	return out
end

-- rank() with the standard's 2e9 scale, for callers without a cfg (the spec).
function Board.sortRows(rows: { any }): { any }
	return Board.rank({ Board = { Scale = 2e9 } }, rows)
end

function Board.emojiFor(cfg: any, beacon: number): string
	local bands = cfg.Env.Bands
	local idx = 1
	for i = 2, #bands do
		if beacon >= bands[i].from then idx = i else break end
	end
	return bands[idx].emoji
end

function Board.rowText(rank: number, name: string, beacon: number, emoji: string): string
	return string.format("%d. %s  %s %d", rank, name, emoji, beacon)
end

function Board.emptyFriendsText(cfg: any, bestBeacon: number): string
	return string.format("None of your friends is on the Star Chart yet. Your best: %s Beacon %d. Invite someone: the sky is big enough.",
		Board.emojiFor(cfg, bestBeacon), bestBeacon)
end

function Board.loadingText(done: number, total: number): string
	return string.format("Loading friends… %d / %d", done, total)
end

-- The friends-read gate: at most FriendReadsPerSecond per server, and only while the GetAsync budget
-- stays above the reserve kept for saving and everything else.
function Board.canRead(cfg: any, now: number, lastReadAt: number, budget: number): boolean
	if not finite(budget) or budget <= cfg.Board.BudgetReserve then return false end
	return now - lastReadAt >= 1 / cfg.Board.FriendReadsPerSecond - 1e-9
end

return Board
