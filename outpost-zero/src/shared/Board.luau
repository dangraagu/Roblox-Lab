--!strict
-- Board.luau — the Census: encoding, the write rule, friend ids, ranking and texts. PURE.
--
-- The metric is the population, which only the server computes (min(settlers, jobs) from the saved storeys);
-- a storey is added only by the server's prompt handler after it checked ownership, district, storey cap, rate
-- and price against the server's own credits, and credits are minted only by the server's clock x population x
-- wage while the server's Orders run (DESIGN 9.1). Value = pop * Scale + (Scale - popAt): a higher population
-- always ranks higher, and at the same population whoever reached it FIRST ranks higher (popAt is the profile's
-- own time of first reaching it, not the write time). The full city (1 031 184) encodes to 2.06e15 < 2^53.
-- Adapted from meteor-drop-tycoon's Board.luau (the metric, the clamp and the texts). Spec: tests/Board.spec.luau.

local Board = {}

Board.UNAVAILABLE = "Friends list unavailable right now. Showing your own row."

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function group(n: number): string
	local s = tostring(math.floor(math.max(0, n)))
	local out = ""
	while #s > 3 do
		out = " " .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return s .. out
end

function Board.encode(cfg: any, pop: number, reachedAt: number): number
	local S = cfg.Board.Scale
	local p = if finite(pop) then math.clamp(math.floor(pop), 0, cfg.Board.MaxPopulation) else 0
	-- reachedAt must stay inside (0, Scale) or it would spill into the neighbouring population
	local t = if finite(reachedAt) then math.clamp(math.floor(reachedAt), 1, S - 1) else S - 1
	return p * S + (S - t)
end

function Board.decode(cfg: any, value: number): (number, number)
	local S = cfg.Board.Scale
	if not finite(value) or value <= 0 then return 0, 0 end
	local p = math.floor((value - 1) / S)
	local rem = value - p * S
	return p, S - rem
end

-- Write only when the population improves on the last value this server wrote or read for the player.
function Board.shouldWrite(cfg: any, lastValue: number?, pop: number): boolean
	if not finite(pop) or pop < 1 then return false end
	if lastValue == nil then return true end
	local lastPop = Board.decode(cfg, lastValue)
	return math.floor(pop) > lastPop
end

-- The first FriendsCap friend ids. `nextPage()` returns the next page's items ({ Id = number, ... }) or nil;
-- it is not called again once the cap is reached.
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

-- rows = { { userId, value, ... } } -> a NEW list, best first, each with .rank and the decoded .pop and .at.
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
		r.pop, r.at = Board.decode(cfg, r.value)
	end
	return out
end

-- At most `size` of the payload rows (already ranked; the viewer's own row has `you = true`), and the viewer's own row
-- always among them: past the size, the top size - 1 and then the viewer's row (REVIEW-1 F6: with 10 players above
-- them, the viewer's row was the 11th and the 10-row face never drew it). A NEW list; the input is not changed.
function Board.window(rows: { any }, size: number): { any }
	local out = {}
	if #rows <= size then
		for _, r in rows do table.insert(out, r) end
		return out
	end
	local mine = nil
	for i, r in rows do
		if r.you then mine = i break end
	end
	local keep = if mine ~= nil and mine > size then size - 1 else size
	for i = 1, keep do table.insert(out, rows[i]) end
	if keep < size then table.insert(out, rows[mine :: number]) end
	return out
end

-- rank() with the standard's 2e9 scale, for callers without a cfg (the spec).
function Board.sortRows(rows: { any }): { any }
	return Board.rank({ Board = { Scale = 2e9, MaxPopulation = 1031184 } }, rows)
end

function Board.emojiFor(cfg: any, pop: number): string
	local bands = cfg.Env.Bands
	local idx = 1
	for i = 2, #bands do
		if pop >= bands[i].from then idx = i else break end
	end
	return bands[idx].emoji
end

function Board.rowText(rank: number, name: string, pop: number, emoji: string): string
	return string.format("%d. %s  %s %s", rank, name, emoji, group(pop))
end

function Board.emptyFriendsText(cfg: any, pop: number): string
	return string.format("None of your friends is on the Census yet. Your population: %s %s. Invite someone: the sky has room for six cities.",
		Board.emojiFor(cfg, pop), group(pop))
end

function Board.loadingText(done: number, total: number): string
	return string.format("Loading friends… %d / %d", done, total)
end

-- The friends-read gate: at most FriendReadsPerSecond per server, and only while the GetAsync budget stays
-- above the reserve kept for saving and everything else.
function Board.canRead(cfg: any, now: number, lastReadAt: number, budget: number): boolean
	if not finite(budget) or budget <= cfg.Board.BudgetReserve then return false end
	return now - lastReadAt >= 1 / cfg.Board.FriendReadsPerSecond - 1e-9
end

return Board
