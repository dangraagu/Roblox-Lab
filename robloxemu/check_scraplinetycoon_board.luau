-- Scrapline Tycoon — the Top Recyclers board: public + friends highscores, through the real server and the real HUD.
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon_board.luau 2>&1
--
-- The standard (docs/complete-game-standard.md §3): an OrderedDataStore keyed u_<userId>, value
-- bolts * 2e9 + (2e9 - boltsAt), written only when the metric improves, ties to whoever reached it FIRST; a public
-- top 10 cached ~60 s; a friends view from GetFriendsAsync, capped, fetched on demand, throttle-safe, with a useful
-- empty text; a physical board by the spawn with a ProximityPrompt (created by the OWNER's client on their own
-- board); names resolved and cached, never stored. The rows render on a SurfaceGui in the OWNER's PlayerGui, so a
-- friends list reaches nobody else. The server code is meteor-drop-tycoon's after its REVIEW-1 (round-robin friend
-- reads); section 6 re-runs that review's fairness case here.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/scrapline-tycoon"), name = "scrapline-tycoon", viewport = { 1280, 720 }, touch = false })

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
local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")
local board = h.services.DataStoreService:GetOrderedDataStore("ScraplineTycoon_Board_v1")
board:SetAsync("u_1", enc(6, T - 1000))
board:SetAsync("u_2", enc(2, T - 500))
board:SetAsync("u_3", enc(2, T - 900)) -- the same count as u_2, reached 400 s earlier: ranks above it
board:SetAsync("u_" .. ME, enc(1, T - 100))
store:SetAsync("u_" .. ME, { data = { v = 1, cash = 10, stations = { shredder = { n = 1, L = 3, j = 0 } }, jamIn = 200, tier = 1,
	bolts = 1, boltsAt = T - 100, tutorial = 4 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local remotes = RS:FindFirstChild("ScraplineRemotes")
local BoardR, BoardView = remotes.Board, remotes.BoardView

h.game:GetService("RunService"):setIsServer(false)
local me = h:join("Nova", ME)
h.Players:simulateSpawn(me, h.workspace)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
h:advance(31) -- the first send went out at load, before this HUD listened; it re-sends every 30 s

local plot = me.RespawnLocation.Parent
local face = plot.Board.BoardFace
local prompt = face:FindFirstChildOfClass("ProximityPrompt")
truthy(prompt ~= nil, "the owner's client created the board prompt on its own board")

--============================================================================ 1. the public board renders, on the owner's own board
local function surface()
	local f = me.PlayerGui:FindFirstChild("BoardGuis")
	return f and f:FindFirstChild("TopRecyclers")
end
local function rowTexts()
	local sg = surface()
	local out = {}
	if sg == nil then return out end
	for i = 1, 10 do
		local r = sg.Background.Rows:FindFirstChild("Row_" .. i)
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
	truthy(sg ~= nil, "the board's SurfaceGui lives in the owner's PlayerGui (BoardGuis)")
	eq(sg and sg.Adornee, face, "...adorned to their OWN board face")
	local rows = rowTexts()
	print("  public rows: " .. table.concat(rows, " | "))
	eq(#rows, 4, "four factories on the public board")
	truthy(rows[1] and string.find(rows[1], "1. User_1", 1, true) and string.find(rows[1], "🥇 6", 1, true), "6 bolts (gold) is first: " .. tostring(rows[1]))
	truthy(rows[2] and string.find(rows[2], "User_3", 1, true), "at 2 bolts, the one who reached it FIRST ranks higher: " .. tostring(rows[2]))
	truthy(rows[3] and string.find(rows[3], "User_2", 1, true), "...then the later one: " .. tostring(rows[3]))
	truthy(rows[4] and string.find(rows[4], "Nova", 1, true) and string.find(rows[4], "1", 1, true), "and the viewer's own row: " .. tostring(rows[4]))
	local nameInStore = false
	for _, v in board.__data do
		if type(v) ~= "number" then nameInStore = true end
	end
	eq(nameInStore, false, "the board store holds only integers: names are resolved at read time and never stored")
	eq(board:GetAsync("u_" .. ME), enc(1, T - 100), "a join with no improvement writes nothing")
end

--============================================================================ 2. friends: unavailable, then real, then empty
local function lastPayload()
	local sent = BoardR:sentTo(me)
	return sent[#sent].args[1]
end
do
	prompt.Triggered:Fire(me)
	h:advance(0.3)
	eq(lastPayload().mode, "friends", "the prompt switches the owner's board to Friends")
	eq(status(), "Friends list unavailable right now. Showing your own row.", "without a friends list (robloxemu has none) it says so")
	local rows = rowTexts()
	eq(#rows, 1, "...and shows one row")
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
	-- (REVIEW-1 A2) a failed friend-list fetch is retried no sooner than FriendListRetrySeconds: the friends list
	-- that now exists is fetched once that has passed
	h:advance(Config.Board.FriendListRetrySeconds + 0.5)
	-- robloxemu attributes a client's FireServer to Players.LocalPlayer, which h:join just moved to Orion: the HUD
	-- running here is Nova's, so give it back. (Its FireClient also reaches every listener, so the rows below are
	-- read from what the server sent NOVA, not from the shared SurfaceGui.)
	h.Players.LocalPlayer = me
	local calls0 = board.__calls
	prompt.Triggered:Fire(me)
	h:advance(0.1)
	truthy(string.find(status(), "Loading friends", 1, true) ~= nil, "friends fill in as their scores arrive: " .. status())
	h:advance(1.2)
	local midCalls = board.__calls - calls0
	h:advance(6)
	local calls = board.__calls - calls0
	print(string.format("  friend score reads: %d in the first 1.3 s, %d in total (3 friends not in this server)", midCalls, calls))
	truthy(midCalls <= 2, "reads are paced at 1 per second per server")
	eq(calls, 3, "one read per friend not in this server; the online friend is read from memory")
	local p = lastPayload()
	local rows = {}
	for _, r in p.rows do table.insert(rows, string.format("%d. %s %s %d", r.rank, r.name, r.emoji, r.bolts)) end
	print("  friends rows (sent to Nova): " .. table.concat(rows, " | "))
	eq(p.mode, "friends", "Nova's view is Friends")
	truthy(#rows >= 3, "friends on the board are listed with you")
	truthy(rows[1] and string.find(rows[1], "User_1", 1, true), "ranked: 6 bolts first")
	local hasMe = false
	for _, r in p.rows do if r.you then hasMe = true end end
	truthy(hasMe, "your own row is always there")
	eq(status(), "", "no status once everything has loaded and friends are on the board")
	local leaked = 0
	for _, rec in BoardR:sentTo(visitor) do
		if rec.player == visitor and rec.args[1].mode == "friends" then leaked += 1 end
	end
	eq(leaked, 0, "nobody else is sent this player's friends view")
	-- a visitor has no prompt on Nova's board (prompts are created by each owner's client, on its own board), and a
	-- BoardView the visitor sends only ever switches the visitor's own view
	BoardView:simulateFireServer(visitor, "friends")
	h:advance(0.5)
	eq(lastPayload().mode, "friends", "a visitor's BoardView does not touch Nova's view")
	-- empty: friends that nobody has on the board. (REVIEW-1 A2) the list is cached for FriendListSeconds, so the
	-- changed list is read once that has passed
	pages = { { { Id = 777 }, { Id = 778 } } }
	h:advance(Config.Board.FriendListSeconds + 1)
	prompt.Triggered:Fire(me)
	h:advance(0.1)
	prompt.Triggered:Fire(me)
	h:advance(4)
	truthy(string.find(status(), "None of your friends has a Gold Bolt yet", 1, true) ~= nil, "an empty friends board says something useful: " .. status())
	truthy(string.find(status(), "six factories", 1, true) ~= nil, "...and invites someone")
	h:leave(visitor)
	h:advance(1)
end

--============================================================================ 3. the tie-break is when the count was REACHED
do
	-- a player whose last session saved 3 bolts (reached 3 000 s ago) but whose board write never landed
	board:SetAsync("u_" .. LAGGED, enc(2, T - 4000))
	store:SetAsync("u_" .. LAGGED, { data = { v = 1, cash = 0, stations = { shredder = { n = 1, L = 1, j = 0 } }, jamIn = 200, tier = 0,
		bolts = 3, boltsAt = T - 3000, tutorial = 4 } })
	local lag = h:join("Lagged", LAGGED)
	h.Players:simulateSpawn(lag, h.workspace)
	h:advance(3)
	eq(board:GetAsync("u_" .. LAGGED), enc(3, T - 3000),
		"bolts saved in an earlier session are ranked with the time they were first REACHED, not when the board catches up")
	h:leave(lag)
	h:advance(1)
end

--============================================================================ 4. a rejoin never writes a lower or equal value
do
	local before = board:GetAsync("u_" .. ME)
	h:leave(me)
	h:advance(1)
	eq(board:GetAsync("u_" .. ME), before, "leaving with no new bolt writes nothing")
	local me2 = h:join("Nova", ME)
	h.Players:simulateSpawn(me2, h.workspace)
	h:advance(70)
	eq(board:GetAsync("u_" .. ME), before, "a rejoin at the same count writes nothing new")
	h:leave(me2)
	h:advance(1)
end

--============================================================================ 5. one big friends list never starves anyone else's view (REVIEW-1)
do
	local BIG, HONEST = 960, 961
	local friendsOf = { [BIG] = {}, [HONEST] = { 50001, 50002, 50003 } }
	for i = 1, 200 do table.insert(friendsOf[BIG], 100000 + i) end
	for _, id in friendsOf[HONEST] do board:SetAsync("u_" .. id, enc(1, T - (id - 50000))) end
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
	local big = h:join("Big", BIG); h.Players:simulateSpawn(big, h.workspace)
	local honest = h:join("Honest", HONEST); h.Players:simulateSpawn(honest, h.workspace)
	h:advance(2)
	BoardView:simulateFireServer(big, "friends")
	h:advance(1)
	BoardView:simulateFireServer(honest, "friends")
	local t0 = h.scheduler:now()
	local took = math.huge
	while h.scheduler:now() - t0 < 120 do
		h:advance(1)
		local sent = BoardR:sentTo(honest)
		local p = sent[#sent] and sent[#sent].args[1]
		if p and p.mode == "friends" and not string.find(p.status or "", "Loading", 1, true) and #p.rows >= 3 then
			took = h.scheduler:now() - t0
			break
		end
	end
	print(string.format("  friends: the honest 3-friend view loaded %s s after a 200-friend view was opened", tostring(took)))
	truthy(took <= 10, "an honest 3-friend view loads within 10 s while a 200-friend view is reading")
	h:leave(big); h:leave(honest)
	h:advance(1)
end

--============================================================================ 6. a client spamming BoardView never multiplies the server's web calls (REVIEW-1 A2)
-- One client fires BoardView at the remote limit (8 a second) for 60 s. Each handler runs on its own thread, as on
-- Roblox. Measured: name lookups (GetNameFromUserIdAsync) while they FAIL (a 429), and friend-list fetches.
do
	for i = 1, 10 do board:SetAsync("u_" .. (300000 + i), enc(10 + i, T - i)) end -- ten strangers on top
	local mt = getmetatable(h.Players)
	local oldIndex = mt.__index
	local lookups, failing = 0, true
	local function nameHook(_self, id)
		lookups += 1
		task.wait(0.05)
		if failing then error("HTTP 429 (Too Many Requests)") end
		return "User_" .. tostring(id)
	end
	mt.__index = function(self, key)
		if rawequal(self, h.Players) and key == "GetNameFromUserIdAsync" then return nameHook end
		return oldIndex(self, key)
	end
	local spam = h:join("Spammer", 4444)
	h.Players:simulateSpawn(spam, h.workspace)
	h:advance(65) -- the public cache (60 s) re-reads: the ten strangers are on it
	local c0 = lookups
	for _ = 1, 60 * 8 do
		task.spawn(function() BoardView:simulateFireServer(spam, "public") end)
		h:advance(0.125)
	end
	local spamLookups = lookups - c0
	local sent = BoardR:sentTo(spam)
	local last = sent[#sent].args[1]
	print(string.format("  names failing: %d lookups during 60 s of public-view spam (one honest view: 10); rows %d, first %s",
		spamLookups, #last.rows, tostring(last.rows[1] and last.rows[1].name)))
	truthy(spamLookups <= 20, "a client spamming its public view while name lookups fail costs at most two lookups per stranger a minute")
	eq(#last.rows, 10, "...and the board still shows its ten rows")
	-- the web comes back: names resolve again within a minute
	failing = false
	h:advance(65)
	task.spawn(function() BoardView:simulateFireServer(spam, "public") end)
	h:advance(2)
	sent = BoardR:sentTo(spam)
	last = sent[#sent].args[1]
	truthy(last.rows[1] and last.rows[1].name == "User_300010", "once lookups work again the names come back: " .. tostring(last.rows[1] and last.rows[1].name))
	local c1 = lookups
	for _ = 1, 60 * 8 do
		task.spawn(function() BoardView:simulateFireServer(spam, "public") end)
		h:advance(0.125)
	end
	eq(lookups - c1, 0, "while lookups work, spamming the view costs no lookup at all (names are cached)")
	mt.__index = oldIndex
	h:leave(spam)
	h:advance(1)
end

--============================================================================ 7. toggling Friends at the limit fetches the friend list once (REVIEW-1 A2)
do
	local list = {}
	for i = 1, 200 do table.insert(list, 200000 + i) end
	local getCalls, pageCalls = 0, 0
	h.Players.GetFriendsAsync = function(_self, userId)
		getCalls += 1
		task.wait(0.3)
		local page = 1
		local pages = { IsFinished = false }
		function pages:GetCurrentPage()
			local out = {}
			for i = (page - 1) * 50 + 1, math.min(#list, page * 50) do table.insert(out, { Id = list[i] }) end
			return out
		end
		function pages:AdvanceToNextPageAsync()
			pageCalls += 1
			task.wait(0.3)
			page += 1
			pages.IsFinished = page * 50 >= #list
		end
		return pages
	end
	local tog = h:join("Toggler", 4545)
	h.Players:simulateSpawn(tog, h.workspace)
	h:advance(2)
	for _ = 1, 60 * 8 do
		task.spawn(function() BoardView:simulateFireServer(tog, "friends") end)
		h:advance(0.125)
	end
	print(string.format("  friends spam for 60 s: GetFriendsAsync %d, AdvanceToNextPageAsync %d (one honest toggle: 1 + 3)", getCalls, pageCalls))
	eq(getCalls, 1, "a client toggling Friends 8 times a second for 60 s costs ONE friend-list fetch")
	eq(pageCalls, 3, "...of its four pages")
	local sent = BoardR:sentTo(tog)
	local last = sent[#sent].args[1]
	eq(last.mode, "friends", "...and still gets its friends view")
	h:leave(tog)
	h:advance(1)
	-- the friends endpoint failing: spamming the toggle does not keep hammering it
	local failCalls = 0
	h.Players.GetFriendsAsync = function(_self, userId)
		failCalls += 1
		task.wait(0.3)
		error("HTTP 429 (Too Many Requests)")
	end
	local tog2 = h:join("Toggler2", 4546)
	h.Players:simulateSpawn(tog2, h.workspace)
	h:advance(2)
	for _ = 1, 60 * 8 do
		task.spawn(function() BoardView:simulateFireServer(tog2, "friends") end)
		h:advance(0.125)
	end
	sent = BoardR:sentTo(tog2)
	last = sent[#sent].args[1]
	print(string.format("  friends spam for 60 s with the endpoint failing: GetFriendsAsync %d", failCalls))
	truthy(failCalls <= 2, "while the friend list fails, toggling at the limit for 60 s tries it at most twice (" .. failCalls .. ")")
	truthy(string.find(last.status or "", "unavailable", 1, true) ~= nil, "...and the view says the list is unavailable: " .. tostring(last.status))
	h:leave(tog2)
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
print(string.format("scraplinetycoon board: %d passed, %d failed", passed, failed))
if failed > 0 then error("scraplinetycoon board check failed", 0) end
