-- Outpost Zero — the Census: public + friends highscores, through the real server and the real HUD.
-- Run:  py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau
--       luau check_outpostzero_board.luau 2>&1
--
-- The standard (docs/complete-game-standard.md §3): an OrderedDataStore keyed u_<userId>, value
-- population * 2e9 + (2e9 - popAt), written only when the metric improves (at most once a minute here, plus once on
-- leaving, and only what a save has landed), ties to whoever reached it FIRST; a public top 10 cached ~60 s; a
-- friends view from GetFriendsAsync, capped, fetched on demand, throttle-safe, with a useful empty text; a physical
-- board by the spawn with a ProximityPrompt; names resolved and cached, never stored. The rows render on a SurfaceGui
-- in the OWNER's PlayerGui, so a friends list reaches nobody else. (adapted from check_meteordroptycoon_board.luau)

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/outpost-zero"), name = "outpost-zero", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local S = 2e9
local function enc(p, t) return p * S + (S - t) end
local T = os.time()
local ME, VISITOR, LAGGED = 900, 901, 902
local store = h.services.DataStoreService:GetDataStore("OutpostZero_v1")
local board = h.services.DataStoreService:GetOrderedDataStore("OutpostZero_Census_v1")
board:SetAsync("u_1", enc(6400, T - 1000))
board:SetAsync("u_2", enc(900, T - 500))
board:SetAsync("u_3", enc(900, T - 900)) -- the same population as u_2, reached 400 s earlier: ranks above it
board:SetAsync("u_" .. ME, enc(36, T - 100))
-- every Landing Field lot at 3 storeys: 3 Homes and 3 Workshops whatever the seed: 36 settlers, 36 jobs
local function d1(storeys)
	local lots = {}
	for i = 1, 6 do lots["1_" .. i] = storeys end
	return lots
end
store:SetAsync("u_" .. ME, { data = { v = 1, seed = 900, credits = 1e9, lifetime = 1e9, lots = d1(3), savedAt = T,
	ordersUntil = T + 600, popAt = T - 100, airshipSeen = false, tutorial = 3 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local remotes = RS:FindFirstChild("CityRemotes")
local BoardR, Toast, State = remotes.Board, remotes.Toast, remotes.State
local Config = h:_require(RS:FindFirstChild("Config"))

h.game:GetService("RunService"):setIsServer(false)
local me = h:join("Nova", ME)
local cme = h.Players:simulateSpawn(me, h.workspace)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
-- the server's first board send went out on load, before this HUD listened; it re-sends every 30 s
h:advance(31)

local shelf = me.RespawnLocation.Parent
local face = shelf.Board.BoardFace
local prompt = face:FindFirstChildOfClass("ProximityPrompt")
local hrp = cme:FindFirstChild("HumanoidRootPart")
local function stateOf(plr)
	local sent = State:sentTo(plr)
	return sent[#sent].args[1]
end
-- press the ★ until the population rises once
local function raisePop(plr, root)
	local p0 = stateOf(plr).population
	for _ = 1, 20 do
		local st = stateOf(plr)
		if st.population > p0 then return st.population end
		local post = plr.RespawnLocation.Parent.Lots:FindFirstChild("Lot_" .. st.star.key).Post
		root.CFrame = CFrame.new(post.Position + Vector3.new(0, 1.5, 0))
		post.BuildPrompt.Triggered:Fire(plr)
		h:advance(0.2)
	end
	return stateOf(plr).population
end

--============================================================================ 1. the public board renders, on the owner's own board
local function surface()
	local f = me.PlayerGui:FindFirstChild("BoardGuis")
	return f and f:FindFirstChild("Census")
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
	local sg = surface()
	truthy(sg ~= nil, "the Census SurfaceGui lives in the owner's PlayerGui (BoardGuis)")
	eq(sg and sg.Adornee, face, "...adorned to their OWN board face")
	local inWorld = 0
	for _, d in h.workspace:GetDescendants() do
		if d.Name == "Census" then inWorld += 1 end
	end
	eq(inWorld, 0, "and nothing named Census is in the workspace: other players cannot see the rows")
	local rows = rowTexts()
	print("  public rows: " .. table.concat(rows, " | "))
	eq(#rows, 4, "four players on the public board")
	truthy(rows[1] and string.find(rows[1], "1. User_1", 1, true) and string.find(rows[1], "6 400", 1, true), "population 6 400 is first: " .. tostring(rows[1]))
	truthy(rows[2] and string.find(rows[2], "User_3", 1, true), "at 900, the one who reached it FIRST ranks higher: " .. tostring(rows[2]))
	truthy(rows[3] and string.find(rows[3], "User_2", 1, true), "...then the later one: " .. tostring(rows[3]))
	truthy(rows[4] and string.find(rows[4], "Nova", 1, true) and string.find(rows[4], "36", 1, true), "and the viewer's own row: " .. tostring(rows[4]))
	truthy(rows[1] and string.find(rows[1], "🏮", 1, true), "each population wears its band's emoji (6 400 is Lantern Dusk)")
	local nameInStore = false
	for _, v in board.__data do
		if type(v) ~= "number" then nameInStore = true end
	end
	eq(nameInStore, false, "the board store holds only integers: names are resolved at read time and never stored")
end

--============================================================================ 2. written only when it improves, at most once a minute
do
	eq(board:GetAsync("u_" .. ME), enc(36, T - 100), "set-up: the joining player's value is untouched on join (no improvement)")
	local p1 = raisePop(me, hrp)
	truthy(p1 > 36, "set-up: the population rises to " .. p1)
	h:advance(9) -- one profile flush (7 s) and a board tick
	local v = board:GetAsync("u_" .. ME)
	local saved = store:GetAsync("u_" .. ME).data
	eq(v, enc(p1, saved.popAt), "the new population is written with the time it was REACHED (the profile's popAt), not the write time")
	eq(v % 1, 0, "as an integer")
	local t0 = h.scheduler:now()
	local p4 = p1
	for _ = 1, 3 do p4 = raisePop(me, hrp) end
	h:advance(20)
	eq(board:GetAsync("u_" .. ME), v, "three more rises inside the minute: still one write")
	h:advance(60 - (h.scheduler:now() - t0) + 10)
	local v2 = board:GetAsync("u_" .. ME)
	eq(math.floor((v2 - 1) / S), p4, "after the minute the coalesced write brings it to " .. p4)
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
	eq(status(), "Friends list unavailable right now. Showing your own row.", "without a friends list (robloxemu has none) it says so, and shows your own row")
	local rows = rowTexts()
	eq(#rows, 1, "one row")
	truthy(rows[1] and string.find(rows[1], "Nova", 1, true), "your own: " .. tostring(rows[1]))
	prompt.Triggered:Fire(me)
	h:advance(0.3)
	eq(lastPayload().mode, "public", "pressed again: back to Public")
end
do
	local pages = { { { Id = 1 }, { Id = 2 } }, { { Id = 55 }, { Id = VISITOR } } }
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
	-- the failed fetch above is remembered for FriendListRetrySeconds (round 2, A3): the friends service that now
	-- exists is asked once that has passed
	h:advance(Config.Board.FriendListRetrySeconds)
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
	truthy(#rows >= 3, "friends on the Census are listed with you")
	truthy(rows[1] and string.find(rows[1], "User_1", 1, true), "ranked: 6 400 first")
	eq(status(), "", "no status once everything has loaded and friends are on the Census")
	local leaked = 0
	for _, rec in BoardR:sentTo(visitor) do
		if rec.player == visitor and rec.args[1].mode == "friends" then leaked += 1 end
	end
	eq(leaked, 0, "nobody else is sent this player's friends view")
	local n0 = #Toast:sentTo(visitor)
	prompt.Triggered:Fire(visitor)
	h:advance(0.1)
	local t = Toast:sentTo(visitor)
	truthy(#t > n0 and string.find(t[#t].args[1], "This is Nova's Census board", 1, true) ~= nil,
		"a visitor pressing someone else's board is told whose it is")
	pages = { { { Id = 777 }, { Id = 778 } } }
	h:advance(Config.Board.FriendListCacheSeconds) -- the list is cached (A3): a changed list shows once that expires
	prompt.Triggered:Fire(me)
	h:advance(0.1)
	prompt.Triggered:Fire(me)
	h:advance(4)
	truthy(string.find(status(), "None of your friends is on the Census yet", 1, true) ~= nil, "an empty friends board says something useful: " .. status())
	truthy(string.find(status(), "the sky has room for six cities", 1, true) ~= nil, "and invites someone")
	h:leave(visitor)
	h:advance(1)
end

--============================================================================ 3b. the tie-break is when the population was REACHED
do
	-- a city whose last session saved population 48 (reached 3 000 s ago) but whose board write never landed: the
	-- board still says 44
	board:SetAsync("u_" .. LAGGED, enc(44, T - 4000))
	store:SetAsync("u_" .. LAGGED, { data = { v = 1, seed = 902, credits = 0, lifetime = 5e5, lots = d1(4), savedAt = T,
		ordersUntil = T, popAt = T - 3000, airshipSeen = false, tutorial = 3 } })
	local lag = h:join("Lagged", LAGGED)
	h.Players:simulateSpawn(lag, h.workspace)
	h:advance(3)
	eq(board:GetAsync("u_" .. LAGGED), enc(48, T - 3000),
		"a population saved in an earlier session is ranked with the time it was first REACHED, not when the board catches up")
	h:leave(lag)
	h:advance(1)
end

--============================================================================ 3c. the viewer always finds their own row (REVIEW-1 F6)
-- The face has 10 row slots. With 10 or more players above them, the viewer's own row used to be the 11th, and the
-- HUD drew 10: nobody mid-table could find themselves. Twelve cities above Nova, in both views.
do
	local above = {}
	for i = 1, 12 do
		local id = 60000 + i
		board:SetAsync("u_" .. id, enc(5000 + i, T - 2000))
		table.insert(above, { Id = id })
	end
	h.Players.GetFriendsAsync = function(_self, userId)
		return { IsFinished = true, GetCurrentPage = function() return above end, AdvanceToNextPageAsync = function() end }
	end
	local function findRow(name)
		local rows = rowTexts()
		for i, r in rows do
			if string.find(r, name, 1, true) then return i, r end
		end
		return nil, nil
	end
	-- friends (Nova's board is on Friends after section 3): switch away and back to re-read, once the cached list
	-- (round 2, A3) has expired
	if lastPayload().mode == "friends" then prompt.Triggered:Fire(me); h:advance(0.3) end
	h:advance(Config.Board.FriendListCacheSeconds)
	prompt.Triggered:Fire(me)
	h:advance(16) -- 12 friends at one read a second
	eq(lastPayload().mode, "friends", "set-up: Friends, with 12 friends above Nova")
	local i, r = findRow("Nova")
	eq(#rowTexts(), 10, "the friends view draws 10 rows")
	eq(i, 10, "...and Nova's own row is one of them, the last: " .. tostring(r))
	truthy(r and string.find(r, "13.", 1, true) == 1, "...with Nova's real rank, 13th")
	prompt.Triggered:Fire(me)
	h:advance(0.3)
	eq(lastPayload().mode, "public", "set-up: back to Public")
	h:advance(61) -- the 60 s public cache expires and the 30 s re-send shows the new top ten
	i, r = findRow("Nova")
	eq(#rowTexts(), 10, "the public view draws 10 rows")
	eq(i, 10, "...and Nova's own row is one of them, the last: " .. tostring(r))
	local rows = rowTexts()
	truthy(rows[1] and string.find(rows[1], "1. User_1", 1, true) == 1, "...under the top of the board: " .. tostring(rows[1]))
	truthy(rows[9] and string.find(rows[9], "9.", 1, true) == 1, "...the top nine: " .. tostring(rows[9]))
end

--============================================================================ 3d. someone else's board: one toast, not one per press (REVIEW-1 F3)
do
	local visitor = h:join("Vega", 904)
	h.Players:simulateSpawn(visitor, h.workspace)
	h:advance(1)
	local n0 = #Toast:sentTo(visitor)
	for _ = 1, 40 do prompt.Triggered:Fire(visitor) end
	h:advance(0.1)
	local t = Toast:sentTo(visitor)
	local n = #t - n0
	print(string.format("  40 presses on Nova's board by a visitor: %d toasts", n))
	truthy(n >= 1 and string.find(t[n0 + 1].args[1], "This is Nova's Census board", 1, true) ~= nil, "the first press on someone else's board says whose it is")
	truthy(n <= 2, string.format("...and 40 presses at once toast at most twice (the reason, then 'Slow down'), as a lot does (%d)", n))
	h:leave(visitor)
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
	eq(board:GetAsync("u_" .. ME), atLeave, "a rejoin at the same population writes nothing new")
	h:leave(me2)
	h:advance(1)
end

--============================================================================ 5. one big friends list never starves anyone else's view
do
	local BIG, HONEST, SPAM, HONEST2 = 960, 961, 962, 963
	local friendsOf = { [BIG] = {}, [SPAM] = {}, [HONEST] = { 50001, 50002, 50003 }, [HONEST2] = { 50011, 50012, 50013 } }
	for i = 1, 200 do
		table.insert(friendsOf[BIG], 100000 + i)
		table.insert(friendsOf[SPAM], 100200 + i)
	end
	for _, id in friendsOf[HONEST] do board:SetAsync("u_" .. id, enc(500, T - (id - 50000))) end
	for _, id in friendsOf[HONEST2] do board:SetAsync("u_" .. id, enc(600, T - (id - 50000))) end
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
	promptOf(big).Triggered:Fire(big)
	h:advance(1)
	promptOf(honest).Triggered:Fire(honest)
	local t1 = loadedAfter(honest, 400)
	print(string.format("  friends: the honest 3-friend view loaded %s s after a 200-friend view was opened", tostring(t1)))
	truthy(t1 <= 10, string.format("an honest 3-friend view loads within 10 s while a 200-friend view is reading (%s s)", tostring(t1)))
	promptOf(honest).Triggered:Fire(honest)
	h:advance(1)
	local honest2 = h:join("Honest2", HONEST2); h.Players:simulateSpawn(honest2, h.workspace)
	h:advance(1)
	for k in reads do reads[k] = 0 end
	for _ = 1, 32 do promptOf(spam).Triggered:Fire(spam); h:advance(0.125) end
	promptOf(spam).Triggered:Fire(spam)
	h:advance(1)
	promptOf(honest2).Triggered:Fire(honest2)
	local t2 = loadedAfter(honest2, 1500)
	print(string.format("  friends: with a prompt-spammer ahead it loaded in %s s", tostring(t2)))
	truthy(t2 <= 12, string.format("...and within 12 s with a prompt-spammer ahead (%s s)", tostring(t2)))
	h:advance(400)
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
	board.GetAsync = origGet
	h:leave(big); h:leave(spam); h:leave(honest); h:leave(honest2)
	h:advance(1)
end

--============================================================================ 6. the leave's Census write survives one transient error
-- (round 2, finding A2) After the leave nothing else writes this key until the player returns, so a write that fails
-- once at the leave kept a finished city below its saved population (and below a later finisher) indefinitely.
local expectedWarnings = {}
do
	local FIN = 970
	store:SetAsync("u_" .. FIN, { data = { v = 1, seed = 970, credits = 1e9, lifetime = 1e9, lots = d1(3), savedAt = os.time(),
		ordersUntil = os.time() + 600, popAt = os.time() - 100, airshipSeen = false, tutorial = 3 } })
	local fin = h:join("Finisher", FIN)
	local froot = h.Players:simulateSpawn(fin, h.workspace):FindFirstChild("HumanoidRootPart")
	h:advance(3)
	local pop = raisePop(fin, froot)
	h:advance(10) -- the flush with the new population lands
	local saved = store.__data["u_" .. FIN].data
	local savedPop = 0
	for k, v in saved.lots do savedPop += v end
	truthy(pop > 36, "set-up: the population rose to " .. pop .. " and a flush saved it")
	board.__failNext = true -- the Census write at the leave fails once
	h:leave(fin)
	h:advance(5)
	local bp = math.floor(board:GetAsync("u_" .. FIN) / S)
	print(string.format("  leave: population %d saved; one Census write failed; the Census says %d", pop, bp))
	eq(bp, pop, "one failed Census write at the leave is retried: the board holds the saved population")
	h:advance(3600)
	eq(math.floor(board:GetAsync("u_" .. FIN) / S), pop, "...and still does an hour later")
	-- a store that keeps failing: the leave still ends, after a bounded number of tries, and says so in the log
	local FIN2 = 971
	store:SetAsync("u_" .. FIN2, { data = { v = 1, seed = 971, credits = 1e9, lifetime = 1e9, lots = d1(3), savedAt = os.time(),
		ordersUntil = os.time() + 600, popAt = os.time() - 100, airshipSeen = false, tutorial = 3 } })
	local fin2 = h:join("Finisher2", FIN2)
	local f2root = h.Players:simulateSpawn(fin2, h.workspace):FindFirstChild("HumanoidRootPart")
	h:advance(3)
	raisePop(fin2, f2root)
	h:advance(10)
	local calls0 = board.__calls
	board.__failAll = true
	local w0 = #h.warnings
	h:leave(fin2)
	h:advance(30)
	board.__failAll = false
	local tries = board.__calls - calls0
	print(string.format("  leave: a Census store that keeps failing was tried %d times", tries))
	truthy(tries >= 2 and tries <= 5, "a failing Census store is retried a bounded number of times at the leave (" .. tries .. ")")
	local logged = 0
	for i = w0 + 1, #h.warnings do
		if string.find(h.warnings[i], "Census write failed", 1, true) then
			logged += 1
			expectedWarnings[h.warnings[i]] = true
		end
	end
	eq(logged, 1, "...and the give-up is logged once")
end

--============================================================================ 7. the friends LIST is cached, not only the friends' scores
-- (round 2, finding A3; standard §3 "cached") Every switch to Friends called GetFriendsAsync again: one owner pressing
-- at the 8/s prompt limit made 240 friends-list calls and 960 page requests a minute.
do
	local OWNER = 980
	local LIST_CACHE = Config.Board.FriendListCacheSeconds or 300 -- (the fallbacks: the values before the fix had none)
	local LIST_RETRY = Config.Board.FriendListRetrySeconds or 30
	local calls, pageReqs, failNow = 0, 0, false
	local list = {}
	for i = 1, 200 do table.insert(list, 300000 + i) end
	h.Players.GetFriendsAsync = function(_self, userId)
		calls += 1
		task.wait(0.05)
		if failNow then error("HTTP 429 (Too Many Requests)", 0) end
		pageReqs += 1
		local page = 1
		local pages = {}
		pages.IsFinished = false
		function pages:GetCurrentPage()
			local out = {}
			for i = (page - 1) * 50 + 1, math.min(#list, page * 50) do table.insert(out, { Id = list[i] }) end
			return out
		end
		function pages:AdvanceToNextPageAsync()
			task.wait(0.05)
			pageReqs += 1
			page += 1
			pages.IsFinished = page * 50 >= #list
		end
		return pages
	end
	local owner = h:join("Presser", OWNER)
	h.Players:simulateSpawn(owner, h.workspace)
	h:advance(3)
	local p = owner.RespawnLocation.Parent.Board.BoardFace:FindFirstChildOfClass("ProximityPrompt")
	for _ = 1, 60 * 8 do
		p.Triggered:Fire(owner)
		h:advance(0.125)
	end
	h:advance(2)
	print(string.format("  friends list: 480 presses in 60 s gave %d GetFriendsAsync calls and %d page requests", calls, pageReqs))
	eq(calls, 1, "the friends list is fetched once per cache period, however often the board is switched")
	eq(pageReqs, 4, "...which is 4 page requests for 200 friends")
	-- the cache expires: the next switch to Friends fetches the list again (new friends show up)
	h:advance(LIST_CACHE)
	p.Triggered:Fire(owner)
	h:advance(0.2)
	local sent = BoardR:sentTo(owner)
	if sent[#sent].args[1].mode ~= "friends" then p.Triggered:Fire(owner); h:advance(0.2) end
	h:advance(2)
	eq(calls, 2, "after the cache period the list is fetched again")
	-- a failing friends service: pressed at 8/s for 60 s, it is asked at most once per retry period
	h:advance(LIST_CACHE)
	failNow = true
	local c0 = calls
	for _ = 1, 60 * 8 do
		p.Triggered:Fire(owner)
		h:advance(0.125)
	end
	h:advance(2)
	local failing = calls - c0
	print(string.format("  friends list: a failing service, 480 presses in 60 s: %d calls", failing))
	truthy(failing <= math.ceil(60 / LIST_RETRY) + 1,
		"a failing friends service is asked at most once per " .. LIST_RETRY .. " s (" .. failing .. " calls)")
	local last = BoardR:sentTo(owner)
	local lp = last[#last].args[1]
	if lp.mode ~= "friends" then p.Triggered:Fire(owner); h:advance(0.2); last = BoardR:sentTo(owner); lp = last[#last].args[1] end
	eq(lp.status, "Friends list unavailable right now. Showing your own row.", "...and says so at once while it waits")
	failNow = false
	h:leave(owner)
	h:advance(1)
end

print("")
local stray = {}
for _, w in h.warnings do
	if not expectedWarnings[w] then table.insert(stray, w) end
end
eq(#stray, 0, "no other warnings (" .. table.concat(stray, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("outpostzero board: %d passed, %d failed", passed, failed))
if failed > 0 then error("outpostzero board check failed", 0) end
