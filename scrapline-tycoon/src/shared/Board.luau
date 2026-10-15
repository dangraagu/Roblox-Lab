--!strict
-- Board.luau — the Top Recyclers board: encoding, the write rule, friend ids, ranking and texts. PURE.
--
-- meteor-drop-tycoon's Board.luau (after its REVIEW-1), with the metric renamed from the Beacon level to Gold
-- Bolts and the emoji from the sky band to the factory grade. Nothing else changed.
--
-- The metric is Gold Bolts, which only the server mints, inside a recycle's one owner-checked write, and only
-- when the server's own flow model of the line ships the required rocket rate (DESIGN.md section 10.1).
-- Value = bolts * Scale + (Scale - boltsAt): more bolts always rank higher, and at the same count the player who
-- reached it FIRST ranks higher (boltsAt is the profile's own time of reaching that count, not the write time).
-- Exact under 2^53 while bolts < 4.5e6; the level cap bounds bolts at 52 (tests/Recycle.spec.luau).
-- Requires nothing; takes the game's Config as `cfg`. Spec: tests/Board.spec.luau.

local Board = {}

Board.UNAVAILABLE = "Friends list unavailable right now. Showing your own row."

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Board.encode(cfg: any, bolts: number, reachedAt: number): number
	local S = cfg.Board.Scale
	local b = if finite(bolts) then math.max(0, math.floor(bolts)) else 0
	-- reachedAt must stay inside (0, Scale) or it would spill into the neighbouring count
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

-- Write only when the count improves on the last value this server wrote or read for the player.
function Board.shouldWrite(cfg: any, lastValue: number?, bolts: number): boolean
	if not finite(bolts) or bolts < 1 then return false end
	if lastValue == nil then return true end
	local lastBolts = Board.decode(cfg, lastValue)
	return math.floor(bolts) > lastBolts
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

-- rows = { { userId, value, ... } } -> a NEW list, best first, each with .rank and the decoded .bolts and .at.
-- Identical values fall back to the lower user id, so the order never flickers between refreshes.
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
		r.bolts, r.at = Board.decode(cfg, r.value)
	end
	return out
end

-- rank() with the standard's 2e9 scale, for callers without a cfg (the spec).
function Board.sortRows(rows: { any }): { any }
	return Board.rank({ Board = { Scale = 2e9 } }, rows)
end

-- The factory grade's emoji for a bolt count (0 rusty ... GoldenBolts and more gold).
function Board.emojiFor(cfg: any, bolts: number): string
	local b = if finite(bolts) then math.floor(bolts) else 0
	local i = math.clamp(b + 1, 1, #cfg.Grades)
	return cfg.Grades[i].emoji
end

function Board.rowText(rank: number, name: string, bolts: number, emoji: string): string
	return string.format("%d. %s  %s %d", rank, name, emoji, bolts)
end

function Board.emptyFriendsText(cfg: any, bestBolts: number): string
	return string.format("None of your friends has a Gold Bolt yet. Your best: %s %d. Invite someone: there are six factories on every server.",
		Board.emojiFor(cfg, bestBolts), bestBolts)
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
