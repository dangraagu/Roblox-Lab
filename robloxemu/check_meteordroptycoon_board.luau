-- Meteor Drop Tycoon — the Star Chart: public + friends highscores, through the real server and the real HUD.
-- Run:  py -3 wrap.py --game ../meteor-drop-tycoon --out build/meteor-drop-tycoon.luau
--       luau check_meteordroptycoon_board.luau 2>&1
--
-- The standard (docs/complete-game-standard.md §3): an OrderedDataStore keyed u_<userId>, value
-- beacon * 2e9 + (2e9 - beaconAt), written only when the metric improves (and at most once a minute here),
-- ties to whoever reached it FIRST; a public top 10 cached ~60 s; a friends view from GetFriendsAsync,
-- capped, fetched on demand, throttle-safe, with a useful empty text; a physical board by the spawn with a
-- ProximityPrompt; names resolved and cached, never stored. The rows render on a SurfaceGui in the OWNER's
-- PlayerGui, so a friends list reaches nobody else.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/meteor-drop-tycoon"), name = "meteor-drop-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local S = 2e9
local function enc(b, t) return b * S + (S - t) end
local T = os.time()
local ME, VISITOR, LAGGED = 900, 901, 902
local store = h.services.DataStoreService:GetDataStore("MeteorDropTycoon_v1")
local board = h.services.DataStoreService:GetOrderedDataStore("MeteorDropTycoon_Board_v1")
board:SetAsync("u_1", enc(30, T - 1000))
board:SetAsync("u_2", enc(12, T - 500))
board:SetAsync("u_3", enc(12, T - 900)) -- the same level as u_2, reached 400 s earlier: ranks above it
board:SetAsync("u_" .. ME, enc(9, T - 100))
store:SetAsync("u_" .. ME, { data = { v = 1, stardust = 1e9, lifetime = 1e9, beacon = 9, beaconAt = T - 100,
	collector = 0, smelter = 40, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local remotes = RS:FindFirstChild("MeteorRemotes")
local Buy, BoardR, Toast = remotes.Buy, remotes.Board, remotes.Toast

h.game:GetService("RunService"):setIsServer(false)
local me = h:join("Nova", ME)
h.Players:simulateSpawn(me, h.workspace)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
-- the server's first board send went out on load, before this HUD listened; it re-sends every 30 s
h:advance(31)

local plot = me.RespawnLocation.Parent
local face = plot.Board.BoardFace
local prompt = face:FindFirstChildOfClass("ProximityPrompt")

--============================================================================ 1. the public board renders, on the owner's own board
local function surface()
	local f = me.PlayerGui:FindFirstChild("BoardGuis")
	return f and f:FindFirstChild("StarChart")
end
local function rowTexts()
	local sg = surface()
	local out = {}
	if sg == nil then return out end
	local rows = sg.Background.Rows
	for i = 1, 10 do
		local r = rows:FindFirstChild("Row_" .. i)
		if r then table.insert(out, r.Text) end
	end
	return out
end
local function status()
	local sg = surface()
	return sg and sg.Background.StatusText.Text or ""
end
do
	-- the view that renders here is the server's 30 s re-send (the one on load went out before the HUD listened)
	local sg = surface()
	truthy(sg ~= nil, "the Star Chart SurfaceGui lives in the owner's PlayerGui (BoardGuis)")
	eq(sg and sg.Adornee, face, "...adorned to their OWN board face")
	local inWorld = 0
	for _, d in h.workspace:GetDescendants() do
		if d.Name == "StarChart" then inWorld += 1 end
	end
	eq(inWorld, 0, "and nothing named StarChart is in the workspace: other players cannot see the rows")
	local rows = rowTexts()
	print("  public rows: " .. table.concat(rows, " | "))
	eq(#rows, 4, "four players on the public board")
	truthy(rows[1] and string.find(rows[1], "1. User_1", 1, true) and string.find(rows[1], "30", 1, true), "Beacon 30 is first: " .. tostring(rows[1]))
	truthy(rows[2] and string.find(rows[2], "User_3", 1, true), "at Beacon 12, the one who reached it FIRST ranks higher: " .. tostring(rows[2]))
	truthy(rows[3] and string.find(rows[3], "User_2", 1, true), "...then the later one: " .. tostring(rows[3]))
	truthy(rows[4] and string.find(rows[4], "Nova", 1, true) and string.find(rows[4], "9", 1, true), "and the viewer's own row: " .. tostring(rows[4]))
	truthy(rows[1] and string.find(rows[1], "🌠", 1, true), "each level wears its band's emoji (Beacon 30 is Starfall)")
	local nameInStore = false
	for _, v in board.__data do
		if type(v) ~= "number" then nameInStore = true end
	end
	eq(nameInStore, false, "the board store holds only integers: names are resolved at read time and never stored")
end

--============================================================================ 2. written only when it improves, at most once a minute
do
	eq(board:GetAsync("u_" .. ME), enc(9, T - 100), "set-up: the joining player's value is untouched on join (no improvement)")
	Buy:simulateFireServer(me, "beacon")
	h:advance(9) -- one profile flush (7 s) and a board tick
	local v = board:GetAsync("u_" .. ME)
	local saved = store:GetAsync("u_" .. ME).data
	eq(v, enc(10, saved.beaconAt), "Beacon 10 is written with the time it was REACHED (the profile's beaconAt), not the write time")
	eq(v % 1, 0, "as an integer")
	local t0 = h.scheduler:now()
	for _ = 1, 3 do
		Buy:simulateFireServer(me, "beacon")
		h:advance(0.3)
	end
	h:advance(20)
	eq(board:GetAsync("u_" .. ME), v, "three more levels inside the minute: still one write (Beacon 10 stands)")
	h:advance(60 - (h.scheduler:now() - t0) + 10)
	local v2 = board:GetAsync("u_" .. ME)
	eq(math.floor((v2 - 1) / S), 13, "after the minute the coalesced write brings it to Beacon 13")
end

--============================================================================ 3. friends: unavailable, then real, then empty
local function lastPayload()
	local sent = BoardR:sentTo(me)
	return sent[#sent].args[1]
end
do
	prompt.Triggered:Fire(me)
	h:advance(0.3)
	eq(lastPayload().mode, "friends", "the prompt switches the owner's board to Friends")
	-- robloxemu has no Players:GetFriendsAsync, which is exactly the failure path
	eq(status(), "Friends list unavailable right now. Showing your own row.", "without a friends list it says so, and shows your own row")
	local rows = rowTexts()
	eq(#rows, 1, "one row")
	truthy(rows[1] and string.find(rows[1], "Nova", 1, true), "your own: " .. tostring(rows[1]))
	prompt.Triggered:Fire(me)
	h:advance(0.3)
	eq(lastPayload().mode, "public", "pressed again: back to Public")
end
do
	-- a friends list: two pages, 4 friends, two of them on the chart, one of them online in this server
	local pages = { { { Id = 1 }, { Id = 2 } }, { { Id = 55 }, { Id = VISITOR } } }
	local reads0 = 0
	h.Players.GetFriendsAsync = function(_self, userId)
		local i = 1
		return {
			IsFinished = false,
			GetCurrentPage = function(self2) return pages[i] end,
			AdvanceToNextPageAsync = function(self2)
				i += 1
				self2.IsFinished = i >= #pages
			end,
		}
	end
	local visitor = h:join("Orion", VISITOR)
	h.Players:simulateSpawn(visitor, h.workspace)
	h:advance(0.5)
	local calls0 = board.__calls
	prompt.Triggered:Fire(me)
	h:advance(0.1)
	local st = status()
	truthy(string.find(st, "Loading friends", 1, true) ~= nil, "friends fill in as their scores arrive: " .. st)
	h:advance(1.2)
	local midCalls = board.__calls - calls0
	h:advance(6)
	local calls = board.__calls - calls0
	print(string.format("  friend score reads: %d in the first 1.3 s, %d in total (3 friends not in this server)", midCalls, calls))
	truthy(midCalls <= 2, "reads are paced at 1 per second per server")
	eq(calls, 3, "one read per friend not in this server; the online friend is read from memory")
	local rows = rowTexts()
	print("  friends rows: " .. table.concat(rows, " | ") .. " | status: " .. status())
	truthy(#rows >= 3, "friends on the chart are listed with you")
	truthy(rows[1] and string.find(rows[1], "User_1", 1, true), "ranked: Beacon 30 first")
	eq(status(), "", "no status once everything has loaded and friends are on the chart")
	-- the visitor sees none of it
	local leaked = 0
	for _, rec in BoardR:sentTo(visitor) do
		if rec.player == visitor and rec.args[1].mode == "friends" then leaked += 1 end
	end
	eq(leaked, 0, "nobody else is sent this player's friends view")
	-- another player's prompt
	local n0 = #Toast:sentTo(visitor)
	prompt.Triggered:Fire(visitor)
	h:advance(0.1)
	local t = Toast:sentTo(visitor)
	truthy(#t > n0 and string.find(t[#t].args[1], "This is Nova's Star Chart", 1, true) ~= nil,
		"a visitor pressing someone else's board is told whose it is")
	-- empty: friends that nobody has on the chart
	pages = { { { Id = 777 }, { Id = 778 } } }
	prompt.Triggered:Fire(me)
	h:advance(0.1)
	prompt.Triggered:Fire(me)
	h:advance(4)
	truthy(string.find(status(), "None of your friends is on the Star Chart yet", 1, true) ~= nil, "an empty friends board says something useful: " .. status())
end

--============================================================================ 3b. the tie-break is when the level was REACHED
do
	-- os.time() in robloxemu is the wall clock, so a write-time stamp and a reached-time stamp taken in the same
	-- run can be the same second; this level was reached 3 000 s before the run, in an earlier session.
	-- a player whose last session saved Beacon 15 (reached 3 000 s ago) but whose board write never landed (the
	-- server went down between the two): the board still says 14
	board:SetAsync("u_" .. LAGGED, enc(14, T - 4000))
	store:SetAsync("u_" .. LAGGED, { data = { v = 1, stardust = 0, lifetime = 5e5, beacon = 15, beaconAt = T - 3000,
		collector = 0, smelter = 20, hopper = 0, star = 0, starCores = 0, tutorial = 3 } })
	local lag = h:join("Lagged", LAGGED)
	h.Players:simulateSpawn(lag, h.workspace)
	h:advance(3)
	eq(board:GetAsync("u_" .. LAGGED), enc(15, T - 3000),
		"a level saved in an earlier session is ranked with the time it was first REACHED, not when the board catches up")
	h:leave(lag)
	h:advance(1)
end

--============================================================================ 4. a rejoin never writes a lower or equal value
do
	local before = board:GetAsync("u_" .. ME)
	h:leave(me)
	h:advance(1)
	local atLeave = board:GetAsync("u_" .. ME)
	truthy(atLeave >= before, "leaving writes the board at most up, never down")
	local me2 = h:join("Nova", ME)
	h.Players:simulateSpawn(me2, h.workspace)
	h:advance(70)
	eq(board:GetAsync("u_" .. ME), atLeave, "a rejoin at the same level writes nothing new")
end

--============================================================================ 5. one big friends list never starves anyone else's view (REVIEW-1)
-- GetFriendsAsync is stubbed with a 0.3 s web latency per page of 50. A player with 200 friends opens Friends
-- (and, in the second run, toggles the prompt 33 times in 4 s, inside the 8/s limit); an honest player with 3
-- friends opens Friends a second later. REVIEW-1 measured 203 s and 1001 s for the honest view, and each of the
-- same 200 keys read about 5 times.
do
	local BIG, HONEST, SPAM, HONEST2 = 960, 961, 962, 963
	local friendsOf = { [BIG] = {}, [SPAM] = {}, [HONEST] = { 50001, 50002, 50003 }, [HONEST2] = { 50011, 50012, 50013 } }
	for i = 1, 200 do
		table.insert(friendsOf[BIG], 100000 + i)
		table.insert(friendsOf[SPAM], 100200 + i) -- 200 keys nobody has read yet
	end
	for _, id in friendsOf[HONEST] do board:SetAsync("u_" .. id, enc(5, T - (id - 50000))) end
	for _, id in friendsOf[HONEST2] do board:SetAsync("u_" .. id, enc(6, T - (id - 50000))) end
	h.Players.GetFriendsAsync = function(_self, userId)
		task.wait(0.3)
		local list = friendsOf[userId] or {}
		local page = 1
		local pages = {}
		pages.IsFinished = #list <= 50
		function pages:GetCurrentPage()
			local out = {}
			for i = (page - 1) * 50 + 1, math.min(#list, page * 50) do table.insert(out, { Id = list[i] }) end
			return out
		end
		function pages:AdvanceToNextPageAsync()
			task.wait(0.3)
			page += 1
			pages.IsFinished = page * 50 >= #list
		end
		return pages
	end
	local reads = {}
	local origGet = board.GetAsync
	board.GetAsync = function(self, k)
		reads[k] = (reads[k] or 0) + 1
		return origGet(self, k)
	end
	local function promptOf(plr) return plr.RespawnLocation.Parent.Board.BoardFace:FindFirstChildOfClass("ProximityPrompt") end
	local function loadedAfter(plr, limit)
		local t0 = h.scheduler:now()
		while h.scheduler:now() - t0 < limit do
			h:advance(1)
			local sent = BoardR:sentTo(plr)
			local p = sent[#sent] and sent[#sent].args[1]
			if p and p.mode == "friends" and not string.find(p.status or "", "Loading", 1, true) and #p.rows >= 3 then
				return h.scheduler:now() - t0
			end
		end
		return math.huge
	end
	local big = h:join("Big", BIG); h.Players:simulateSpawn(big, h.workspace)
	local spam = h:join("Spam", SPAM); h.Players:simulateSpawn(spam, h.workspace)
	local honest = h:join("Honest", HONEST); h.Players:simulateSpawn(honest, h.workspace)
	h:advance(2)
	-- run 1: one toggle by the big list, then the honest player
	promptOf(big).Triggered:Fire(big)
	h:advance(1)
	promptOf(honest).Triggered:Fire(honest)
	local t1 = loadedAfter(honest, 400)
	print(string.format("  friends: the honest 3-friend view loaded %s s after a 200-friend view was opened", tostring(t1)))
	truthy(t1 <= 10, string.format("an honest 3-friend view loads within 10 s while a 200-friend view is reading (%s s)", tostring(t1)))
	promptOf(honest).Triggered:Fire(honest) -- back to Public
	h:advance(1)
	-- run 2: the spammer toggles 33 times in 4 s (ends on Friends), then a second honest player (friends not
	-- cached yet) opens Friends
	local honest2 = h:join("Honest2", HONEST2); h.Players:simulateSpawn(honest2, h.workspace)
	h:advance(1)
	for k in reads do reads[k] = 0 end
	for _ = 1, 32 do promptOf(spam).Triggered:Fire(spam); h:advance(0.125) end
	promptOf(spam).Triggered:Fire(spam)
	h:advance(1)
	promptOf(honest2).Triggered:Fire(honest2)
	local t2 = loadedAfter(honest2, 1500)
	print(string.format("  friends: with a prompt-spammer ahead it loaded in %s s", tostring(t2)))
	truthy(t2 <= 12, string.format("...and within 12 s with a prompt-spammer ahead: three viewers reading, one read a second in turn (%s s)", tostring(t2)))
	h:advance(400) -- let both big views finish
	local dup, total = 0, 0
	for _, n in reads do
		total += n
		if n > 1 then dup += 1 end
	end
	print(string.format("  friends: %d board reads from the spam on, %d keys read more than once", total, dup))
	eq(dup, 0, "no friend's score is read twice inside its 300 s cache, whoever asks and however often the prompt is pressed")
	local sv = BoardR:sentTo(spam)
	local last = sv[#sv] and sv[#sv].args[1]
	truthy(last ~= nil and last.mode == "friends" and not string.find(last.status or "", "Loading", 1, true),
		"and the spammer's own view still finishes loading: " .. tostring(last and last.status))
	h:leave(big); h:leave(spam); h:leave(honest); h:leave(honest2)
	h:advance(1)
	-- run 3: two players whose friends are the same 50 people (nobody read yet) open Friends together. The score
	-- cache must be checked when a read is DUE, not only when it is queued: both queue all 50 before any is read.
	local SA, SB = 964, 965
	friendsOf[SA], friendsOf[SB] = {}, {}
	for i = 1, 50 do
		table.insert(friendsOf[SA], 100500 + i)
		table.insert(friendsOf[SB], 100500 + i)
	end
	local pa = h:join("SharedA", SA); h.Players:simulateSpawn(pa, h.workspace)
	local pb = h:join("SharedB", SB); h.Players:simulateSpawn(pb, h.workspace)
	h:advance(2)
	for k in reads do reads[k] = 0 end
	promptOf(pa).Triggered:Fire(pa)
	promptOf(pb).Triggered:Fire(pb)
	h:advance(120)
	local shared, twice = 0, 0
	for i = 1, 50 do
		local n = reads["u_" .. (100500 + i)] or 0
		shared += n
		if n > 1 then twice += 1 end
	end
	print(string.format("  friends: two viewers sharing 50 friends: %d reads, %d keys read twice", shared, twice))
	eq(twice, 0, "two viewers who share friends read each shared friend once (the cache is checked when the read is due)")
	eq(shared, 50, "...50 reads for 50 friends")
	local function loaded(plr)
		local sent = BoardR:sentTo(plr)
		local p = sent[#sent] and sent[#sent].args[1]
		return p ~= nil and p.mode == "friends" and not string.find(p.status or "", "Loading", 1, true)
	end
	truthy(loaded(pa) and loaded(pb), "and both views finish loading")
	board.GetAsync = origGet
	h:leave(pa); h:leave(pb)
	h:advance(1)
end

print("")
local stray = {}
for _, w in h.warnings do table.insert(stray, w) end
eq(#stray, 0, "no warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("meteordroptycoon board: %d passed, %d failed", passed, failed))
if failed > 0 then error("meteordroptycoon board check failed", 0) end
