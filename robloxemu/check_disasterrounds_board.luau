-- Disaster Rounds - the public + friends board, through the real server. Run: luau check_disasterrounds_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- docs/complete-game-standard.md §3: rank on a server-measured metric a script cannot inflate (best streak), ties to
-- whoever reached it first; OrderedDataStore key u_<userId>, value best * 2e9 + (2e9 - reachedAt); written only when
-- the metric improves, only from values a profile save has already landed, max-merged; public top 10 cached ~60 s;
-- friends on demand, capped, cached, throttle-safe; an empty friends board says something useful.

local SEED = 31
local Datatypes = require("./emu/datatypes")
do
	local realNew = Datatypes.Random.new
	local n = SEED
	Datatypes.Random.new = function(seed)
		if seed == nil then
			n += 1
			return realNew(n * 7919)
		end
		return realNew(seed)
	end
end
local Harness = require("./emu/harness")
local Bot = require("./check_disasterrounds_bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local Players = h.Players
local store = h.services.DataStoreService:GetDataStore("DisasterRounds_v1")
local lb = h.services.DataStoreService:GetOrderedDataStore("DisasterRounds_Streak_v1")
-- a friend with a stored best of 6; Ned's board value (8) is higher than his profile says (5): another server's write
lb:SetAsync("u_502", 6 * 2e9 + (2e9 - 1770000000))
lb:SetAsync("u_509", 8 * 2e9 + (2e9 - 1760000000))
store:SetAsync("u_509", { v = 1, data = { survived = 20, streak = 5, best = 5, bestAt = 1790000000, boardBest = 0 }, session = { token = "x", expires = 0 } })

-- count the board store's traffic
local writes, sorted, reads = 0, 0, 0
do
	local oUpdate, oSorted, oGet = lb.UpdateAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.GetSortedAsync = function(self, ...) sorted += 1; return oSorted(self, ...) end
	lb.GetAsync = function(self, ...) reads += 1; return oGet(self, ...) end
end
local friendsOf = {
	[501] = { { 502, "Bo" }, { 503, "Cy" } },
	[510] = {},
	[512] = "error",
}
do
	local big = {}
	for i = 1, 450 do table.insert(big, { 20000 + i, "Pal" .. i }) end
	friendsOf[513] = big
end
local friendCalls = {}
Players.GetFriendsAsync = function(_self, userId)
	friendCalls[userId] = (friendCalls[userId] or 0) + 1
	local list = friendsOf[userId]
	if list == "error" then error("HTTP 500 (Internal Server Error)", 0) end
	list = list or {}
	local pageNo = 1
	local pages = { IsFinished = #list <= 50 }
	function pages:GetCurrentPage()
		local out = {}
		for i = (pageNo - 1) * 50 + 1, math.min(pageNo * 50, #list) do
			table.insert(out, { Id = list[i][1], Username = list[i][2], DisplayName = list[i][2], IsOnline = false })
		end
		return out
	end
	function pages:AdvanceToNextPageAsync()
		pageNo += 1
		self.IsFinished = pageNo * 50 >= #list
	end
	return pages
end

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Board = h:_require(RS:FindFirstChild("Board"))
local BC = Config.Board
local rf = h.workspace:FindFirstChild("Round")
local boardR = RS:FindFirstChild("DRRemotes"):FindFirstChild("Board")
local toastR = RS:FindFirstChild("DRRemotes"):FindFirstChild("Toast")
local prompt = h.workspace.Lookout.StreakBoard:FindFirstChildWhichIsA("ProximityPrompt", true)
h.game:GetService("RunService"):setIsServer(false)
Config.Shots.ForceKind = "meteor"

local function lastView(plr)
	local sent = boardR:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
local DT = 0.1
local bots = {}
local function tick()
	for _, b in bots do Bot.step(b, DT) end
	h:advance(DT)
end
local function untilPhase(phase: string, limit: number)
	local n = 0
	while rf:GetAttribute("Phase") ~= phase and n < limit / DT do tick() n += 1 end
end

local A = Players:simulateJoin("Ava", 501)
Instance.new("PlayerGui").Parent = A
h.Players:simulateSpawn(A, h.workspace)
local Ned = Players:simulateJoin("Ned", 509)
h.Players:simulateSpawn(Ned, h.workspace)
bots = { Bot.new(h, A, { react = 0.6 }), Bot.new(h, Ned, { react = 0.6 }) }
h:advance(1)

--======================================================================= written only when it improves, from saved values

local writes0 = writes
untilPhase("outro", 120)
untilPhase("intermission", 10)
h:advance(0.5)
eq(A:GetAttribute("Best"), 1, "Ava survives: best streak 1")
do
	local v = lb.__data["u_501"]
	local m, t = Board.decode(v or 0)
	eq(m, 1, "her best (1) is on the board after the round's save landed")
	truthy(t ~= nil and math.abs(t - os.time()) <= 5, "with the time it was reached")
end
eq(writes - writes0, 2, "one board UpdateAsync per player whose best rose: Ava (0 -> 1, written) and Ned (5 -> 6, aborted below)")
local v509 = lb.__data["u_509"]
eq(Board.decode(v509), 8, "Ned's board value (8, from another server) is never lowered to his profile's best (6)")
-- a round that does not raise the best writes nothing to the board
bots[2] = Bot.new(h, Ned, { idle = true })
untilPhase("disaster", 30)
writes0 = writes
-- Ava stands still this round: swept out, best stays 1
bots[1] = Bot.new(h, A, { idle = true })
untilPhase("intermission", 100)
h:advance(0.5)
eq(A:GetAttribute("Streak"), 0, "Ava is swept out")
eq(writes - writes0, 0, "a round with no new best writes nothing to the board")
-- a failed profile write means no board write either: only saved values reach the board
bots = { Bot.new(h, A, { react = 0.6 }) }
store.__failAll = true
writes0 = writes
untilPhase("outro", 120)
untilPhase("intermission", 10)
h:advance(0.5)
eq(A:GetAttribute("Best"), 1, "Ava survives again: streak 1, best still 1")
store.__failAll = false
bots = { Bot.new(h, A, { react = 0.6 }) }
untilPhase("outro", 120)
untilPhase("intermission", 10)
h:advance(0.5)
eq(A:GetAttribute("Best"), 2, "and again: best 2")
eq(Board.decode(lb.__data["u_501"]), 2, "best 2 reaches the board once a profile write carrying it lands")
bots = {}

--======================================================================= the public view, cached

do
	local s0 = sorted
	h:advance(BC.PublicCacheSeconds * 3 + 1)
	truthy(sorted - s0 <= 4, string.format("the public top 10 is read at most once a minute (%d reads in 181 s)", sorted - s0))
	local pub = lastView(A)
	truthy(pub ~= nil and pub.mode == "public", "Ava's board shows the public view")
	if pub then
		local order = {}
		for _, r in pub.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier)) end
		eq(table.concat(order, " "), "509:8 502:6 501:2", "highest streak first")
		local named = true
		for _, r in pub.rows do if type(r.name) ~= "string" or r.name == "" then named = false end end
		truthy(named, "every row carries a resolved name (never stored)")
	end
end

--======================================================================= friends, on demand

do
	local reads0 = reads
	prompt.Triggered:Fire(A)
	h:advance(2)
	local f = lastView(A)
	truthy(f ~= nil and f.mode == "friends", "the prompt switches Ava's board to Friends")
	if f then
		local order = {}
		for _, r in f.rows do table.insert(order, tostring(r.name) .. ":" .. tostring(r.tier)) end
		eq(table.concat(order, " "), "Bo:6 Ava:2", "her friends ranked against her (Cy has no streak yet)")
	end
	truthy(reads - reads0 <= 2, "friends' scores are read on demand (" .. (reads - reads0) .. " reads)")
	eq(friendCalls[501], 1, "the friends list is fetched once")
	h:advance(1.1)
	toastR:clearSent()
	prompt.Triggered:Fire(A)
	prompt.Triggered:Fire(A)
	h:advance(0.2)
	local said = false
	for _, r in toastR:sentTo(A) do
		if string.find(tostring(r.args[1]), "One switch a second", 1, true) then said = true end
	end
	truthy(said, "switching again within a second is refused, and says so")
	h:advance(1.1)
	prompt.Triggered:Fire(A)
	h:advance(0.5)
	prompt.Triggered:Fire(A)
	h:advance(2)
	eq(friendCalls[501], 1, "the second look at Friends uses the cached list")
end

local function friendsNote(name: string, uid: number): string?
	local p = Players:simulateJoin(name, uid)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	prompt.Triggered:Fire(p)
	h:advance(3)
	local v = lastView(p)
	return v and v.note
end
do
	local n = friendsNote("Nofriends", 510)
	eq(n, BC.Text.NoFriends, "no Roblox friends: the board says friends you add show up here")
	local e = friendsNote("Erry", 512)
	eq(e, BC.Text.FriendsFailed, "a failed friends fetch: the board says to try again in a minute")
	local p = Players:simulateJoin("Popular", 513)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	prompt.Triggered:Fire(p)
	h:advance(400)
	local v = lastView(p)
	truthy(v ~= nil and type(v.note) == "string" and string.find(v.note, "200", 1, true) ~= nil,
		"450 friends: the list stops at FriendsCap (" .. tostring(v and v.note) .. ")")
end

--======================================================================= the cap (REVIEW-1 F5)

-- A script that reads the replicated red never misses: the board counts a best streak up to Config.Board.StreakCap,
-- with the time it was FIRST reached, so a script reaches what a person can and nothing more
do
	store:SetAsync("u_520", { v = 1, data = { survived = 60, played = 70, streak = 24, best = 24, bestAt = 1790000000,
		boardBest = 24 }, session = { token = "x", expires = 0 } })
	lb:SetAsync("u_520", Board.encode(24, 1790000000, BC))
	local Z = Players:simulateJoin("Zed", 520)
	h.Players:simulateSpawn(Z, h.workspace)
	h:advance(1)
	eq(Z:GetAttribute("Streak"), 24, "Zed has a streak of 24")
	bots = { Bot.new(h, Z, { react = 0.6 }) }
	untilPhase("intermission", 100)
	untilPhase("outro", 120)
	local reachedAt = os.time()
	untilPhase("intermission", 10)
	h:advance(0.5)
	eq(Z:GetAttribute("Best"), 25, "Zed survives: best 25")
	local m1, t1 = Board.decode(lb.__data["u_520"] or 0)
	eq(m1, BC.StreakCap, "25 on the board")
	truthy(t1 ~= nil and math.abs(t1 - reachedAt) <= 5, "reached now")
	local w0 = writes
	untilPhase("outro", 120)
	untilPhase("intermission", 10)
	h:advance(0.5)
	eq(Z:GetAttribute("Best"), 26, "and again: his own best is 26 (Heat and the Codex go on as before)")
	local m2, t2 = Board.decode(lb.__data["u_520"] or 0)
	eq(m2, BC.StreakCap, "the board still counts 25: it never counts past the cap")
	eq(t2, t1, "with the time 25 was first reached")
	eq(writes - w0, 0, "and nothing was written to the board for it")
	bots = {}
	h:advance(BC.PublicCacheSeconds + 1)
	local pub = lastView(Z)
	local mine = nil
	for _, r in (pub and pub.rows or {}) do
		if r.userId == 520 then mine = r.tier end
	end
	eq(mine, BC.StreakCap, "his row on the public board shows 25")
	-- his own row on the friends board is his live value (nothing stored is read for a player in this server)
	h:advance(1.1)
	prompt.Triggered:Fire(Z)
	h:advance(3)
	local fv = lastView(Z)
	local own = nil
	for _, r in (fv and fv.rows or {}) do
		if r.userId == 520 then own = r.tier end
	end
	eq(fv and fv.mode, "friends", "Zed switches to Friends")
	eq(own, BC.StreakCap, "where his own row shows 25 too")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("disasterrounds board: %d passed, %d failed", passed, failed))
