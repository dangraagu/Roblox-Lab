-- Labyrinth Mariozo — the highscore board, public + friends. Run: luau check_labyrintspill_board.luau 2>&1
-- Rebuild the bundle first: py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot inflate
-- (here `accepted`, the highest level cleared in sequence; check_labyrintspill_journey covers the walk guard), ties
-- to whoever reached it FIRST; OrderedDataStore key u_<userId>, value metric * 2e9 + (2e9 - reachedAtUnix), written
-- only when the metric improves; the public top 10 cached ~60 s; friends via Players:GetFriendsAsync, capped at 200,
-- fetched only on demand, cached, pcall'd and throttle-safe; a physical board near spawn with a ProximityPrompt that
-- toggles Public/Friends; names resolved and cached, never stored; an empty friends board says something useful.
-- The game had a public top 10 before (LabyrintTopp_v2: key tostring(userId), the raw level, a HUD panel only);
-- that panel keeps working and the old board's entries are carried over.
-- Everything runs through the REAL server and the real BoardClient. The emulator has no Players:GetFriendsAsync,
-- so this file supplies one (FriendPages-shaped: GetCurrentPage / IsFinished / AdvanceToNextPageAsync) and counts
-- the calls. This file is adapted from check_plus1jump_board.luau (+1 Jump's board is the template).

local Harness = require("./emu/harness")
local Lib = require("./check_labyrintspill_lib")
local c = Lib.counter("labyrintspill board")
local eq, truthy = c.eq, c.truthy

local h = Harness.new({ bundle = require("./build/labyrint-spill"), name = "labyrint-spill", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players
local today = math.floor(os.time() / 86400)

-- saved profiles (flat, the live game's shape), before the server starts
local profiles = DSS:GetDataStore("LabyrintSpill_v1")
local function seed(uid, d)
	d.rewardDay = today -- no daily reward popups in this check
	d.coins = d.coins or 50
	profiles:SetAsync("p_" .. uid, d)
end
seed(501, { accepted = 12, level = 13, acceptedAt = 1780000000 })
seed(502, { accepted = 12, level = 13, acceptedAt = 1770000000 })
seed(503, { accepted = 30, level = 31, acceptedAt = 1785000000 })
seed(504, { accepted = 9, level = 10 }) -- saved before 2026-10-01: no acceptedAt
-- Ned: the board already holds 25 for him (a session whose profile write was lost), his profile says 15
seed(509, { accepted = 15, level = 16, acceptedAt = 1775000000 })
-- Lou plays in another server right now: this server loads him read-only and must not write his board entry
seed(530, { accepted = 60, level = 61, acceptedAt = 1771000000, session = "tok-other", jobId = "other-server", lockUntil = os.time() + 600 })

-- offline players already on the new board (the owner's formula, written here by hand so the check does not
-- trust the game's own encode for its input)
local function enc(m, t) return m * 2e9 + (2e9 - t) end
local v3 = DSS:GetOrderedDataStore("LabyrintTopp_v3")
v3:SetAsync("u_505", enc(50, 1760000000))
v3:SetAsync("u_508", enc(20, 1765000000))
v3:SetAsync("u_509", enc(25, 1750000000))

-- the old board (v2: key tostring(userId), raw level)
local legacy = DSS:GetOrderedDataStore("LabyrintTopp_v2")
legacy:SetAsync("520", 40)
legacy:SetAsync("521", 7)
legacy:SetAsync("505", 45) -- lower than what the new board already holds for 505: never lowers it

local okServer, errServer = h:tryRun("server/MazeGame.server")
truthy(okServer, "the server runs: " .. tostring(errServer))
local BC = h:_require(RS:FindFirstChild("BoardConfig"))
local Board = h:_require(RS:FindFirstChild("Board"))
truthy(type(BC) == "table" and type(Board) == "table", "ReplicatedStorage has BoardConfig and the Board template")
local lb = DSS:GetOrderedDataStore(BC.Store)
eq(BC.Store, "LabyrintTopp_v3", "the board's store")
eq(Board.encode(50, 1760000000, BC), enc(50, 1760000000), "the game's encode is the owner's formula")


-- count what the server does to the board's store from here on
local writes, sorted, reads = 0, 0, {}
do
	local oUpdate, oSet, oSorted, oGet = lb.UpdateAsync, lb.SetAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; return oSet(self, ...) end
	lb.GetSortedAsync = function(self, ...) sorted += 1; return oSorted(self, ...) end
	lb.GetAsync = function(self, key, ...) table.insert(reads, key); return oGet(self, key, ...) end
end

-- friends, per user id: a list of { Id, Username } (or "error")
local friendsOf = {
	[501] = { { 502, "Bo" }, { 505, "Eve" }, { 506, "Finn" }, { 508, "Gus" } },
	[510] = {},
	[511] = { { 506, "Finn" } },
	[512] = "error",
}
do
	local big = {}
	for i = 1, 450 do table.insert(big, { 20000 + i, "Pal" .. i }) end
	friendsOf[513] = big
end
local friendCalls, pagesAdvanced = {}, 0
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
		pagesAdvanced += 1
		pageNo += 1
		self.IsFinished = pageNo * 50 >= #list
	end
	return pages
end

--======================================================================= 1. the board in the world

local lobby = h.workspace:FindFirstChild("Lobby")
local board = lobby and lobby:FindFirstChild("TopBoard")
truthy(board ~= nil and board:IsA("BasePart"), "a physical board stands in the lobby (workspace.Lobby.TopBoard)")
local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt", true)
truthy(prompt ~= nil, "with a ProximityPrompt")
local spawnPad = lobby and lobby:FindFirstChild("LobbySpawn")
if board and spawnPad then
	local d = (board.Position - spawnPad.Position)
	local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
	truthy(flat <= 16, string.format("near spawn (%.1f studs from the spawn pad)", flat))
	local look = board.CFrame.LookVector
	local toSpawn = Vector3.new(spawnPad.Position.X - board.Position.X, 0, spawnPad.Position.Z - board.Position.Z)
	local cos = (look.X * toSpawn.X + look.Z * toSpawn.Z) / math.max(toSpawn.Magnitude, 1e-6)
	truthy(cos > 0.9, string.format("its front face (where the board is drawn) faces the spawn (cos %.2f)", cos))
	-- nothing else in the lobby stands inside it or right in front of it (doors, poles, the statue's pedestal, the
	-- spawn pad): the board's footprint grown by 3 studs, in the board's own frame
	local clash = nil
	for _, p in lobby:GetDescendants() do
		if p:IsA("BasePart") and p ~= board and not p:IsDescendantOf(board) and p.Name ~= "LobbyFloor" then
			local rel = board.CFrame:PointToObjectSpace(p.Position)
			local reach = math.max(p.Size.X, p.Size.Z) / 2
			if math.abs(rel.X) < board.Size.X / 2 + 3 + reach and math.abs(rel.Z) < board.Size.Z / 2 + 3 + reach
				and math.abs(rel.Y) < board.Size.Y / 2 + p.Size.Y / 2 then
				clash = clash or p.Name
			end
		end
	end
	truthy(clash == nil, "nothing else in the lobby stands within 3 studs of it" .. (if clash then " (" .. clash .. ")" else ""))
	-- the break room's campfire (RestClient builds it at Biomes.Rest.Campfire) is on the other side of the lobby
	local Biomes = h:_require(RS:FindFirstChild("Biomes"))
	local cf = Biomes.Rest.Campfire
	local dc = math.sqrt((board.Position.X - cf.x) ^ 2 + (board.Position.Z - cf.z) ^ 2)
	truthy(dc > 20, string.format("and it is far from the campfire corner (%.0f studs)", dc))
end
if prompt then
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.MaxActivationDistance, BC.PromptDistance, "its reach is BoardConfig.PromptDistance")
	eq(prompt.ActionText, BC.Text.Prompt, "and it says what it does (" .. tostring(prompt.ActionText) .. ")")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
end

--======================================================================= 2. the stored value, ties, the old board

h.game:GetService("RunService"):setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	h:advance(0.2)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.2)
	return p
end
local B = joinAs("Bo", 502)
local C = joinAs("Cy", 503)
local D = joinAs("Dee", 504)
local N = joinAs("Ned", 509)
local L = joinAs("Lou", 530)
local joinedAt = os.time()
local A = joinAs("Ava", 501) -- last: the client scripts below are Ava's
local okClient, errClient = h:tryRun("client/BoardClient.client")
truthy(okClient, "BoardClient loads (" .. tostring(errClient) .. ")")
local okHud = h:tryRun("client/LeaderboardClient.client")
truthy(okHud, "the HUD's LeaderboardClient loads")
h:advance(2)

local function stored(uid) return lb.__data["u_" .. uid] end
local function decode(v) if type(v) == "number" then return Board.decode(v) end return nil, nil end
eq(stored(501), Board.encode(12, 1780000000, BC), "Ava's saved best (level 12, reached 1780000000) is stored encoded")
eq(stored(502), Board.encode(12, 1770000000, BC), "Bo's too (12, reached EARLIER)")
eq(stored(503), Board.encode(30, 1785000000, BC), "and Cy's (30)")
eq(stored(509), Board.encode(25, 1750000000, BC), "Ned's 25 on the board is never lowered to his profile's 15")
eq(stored(530), nil, "a read-only session (the player is in another server) writes nothing to the board")
do
	local m, t = decode(stored(504))
	eq(m, 9, "a save from before acceptedAt existed still gets on the board (Dee, 9)")
	truthy(t ~= nil and math.abs(t - joinedAt) <= 5, "stamped with the session it came back in (" .. tostring(t) .. " vs " .. joinedAt .. ")")
end
eq(stored(520), Board.encode(40, BC.LegacyReachedAt, BC), "the old board's entries are carried over (520, level 40)")
eq(stored(521), Board.encode(7, BC.LegacyReachedAt, BC), "(521, level 7)")
eq(stored(505), Board.encode(50, 1760000000, BC), "an old entry lower than the new board's never lowers it (505 stays 50)")

-- the public view the server sends, and the HUD's top list
local boardRemote = RS:FindFirstChild("HudRemotes") and RS.HudRemotes:FindFirstChild("Board")
truthy(boardRemote ~= nil, "a HudRemotes.Board remote exists")
local function lastView(plr)
	if not boardRemote then return nil end
	local sent = boardRemote:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
h:advance(BC.PublicCacheSeconds + 1) -- the next public refresh sees the new values
local pub = lastView(A)
truthy(pub ~= nil and pub.mode == "public", "Ava's board starts on the PUBLIC view")
if pub then
	local order = {}
	for _, r in pub.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier) .. ":" .. tostring(r.name)) end
	eq(table.concat(order, " "), "505:50:User_505 520:40:User_520 503:30:Cy 509:25:Ned 508:20:User_508 502:12:Bo 501:12:Ava 504:9:Dee 521:7:User_521",
		"public view: highest first, Bo above Ava on the same level (he got there first), names resolved")
end

--======================================================================= 3. written only when it improves

local writesBefore = writes
h:advance(130) -- two autosaves
eq(writes, writesBefore, "two autosaves with no new level cleared write nothing to the board")
do
	local sr = RS:FindFirstChild("LobbyRemotes"):FindFirstChild("StartRun")
	sr:simulateFireServer(A, 13, "solo")
	h:advance(0.5)
	local folder = h.workspace:FindFirstChild(A:GetAttribute("MazeFolder") or "")
	local exit = folder and folder:FindFirstChild("Exit")
	truthy(exit ~= nil, "set-up: Ava is in level 13")
	-- walk time: more than any maze this size can be crossed in (the walk guard, check_labyrintspill_journey)
	h:advance(60)
	local hrp = A.Character:FindFirstChild("HumanoidRootPart")
	if exit then
		hrp.CFrame = CFrame.new(exit.Position + Vector3.new(0, 3, 0))
		exit.Touched:Fire(hrp)
	end
	local clearedAt = os.time()
	h:advance(1)
	eq(writes, writesBefore + 1, "a new level cleared: exactly one write")
	local m, t = decode(stored(501))
	eq(m, 13, "the board now holds 13 for Ava")
	truthy(t ~= nil and math.abs(t - clearedAt) <= 5, "stamped when she reached it (" .. tostring(t) .. " vs " .. clearedAt .. ")")
	h:advance(130)
	eq(writes, writesBefore + 1, "and nothing more after that")
end

-- (2026-10-01, pass 2 resumed: a rule no assertion held, found by the mutation sweep) a god-mode user (GodUsers: Mio)
-- never stands on the board, whatever the profile says: not at join, not on an autosave's retry
do
	seed(777, { accepted = 40, level = 41, acceptedAt = 1760000000 })
	local w0 = writes
	local M = joinAs("MioSpille", 777)
	h:advance(130) -- the join-time write and two autosaves (each retries a write that is owed)
	eq(stored(777), nil, "a god-mode user is never written to the board (accepted 40 in the profile)")
	eq(writes, w0, "not one board write for them")
	truthy(M.Parent ~= nil, "set-up: MioSpille is still in the server")
end

--======================================================================= 4. the public list is cached ~60 s

do
	local s0 = sorted
	h:advance(180)
	local n = sorted - s0
	print(string.format("  public top 10: %d GetSortedAsync calls in 180 s", n))
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 180 s (one per " .. BC.PublicCacheSeconds .. " s)")
	-- the HUD's top list gets decoded levels and names, never the stored value
	local lbRemote = RS.HudRemotes:FindFirstChild("Leaderboard")
	local sent = lbRemote:sentTo(A)
	local top = sent[#sent] and sent[#sent].args[1]
	truthy(type(top) == "table" and top[1] ~= nil, "the HUD's top list is sent")
	if top and top[1] then
		eq(top[1].level, 50, "HUD row 1 is level 50, decoded")
		eq(top[1].name, "User_505", "with its name")
		local maxLevel = 0
		for _, e in top do maxLevel = math.max(maxLevel, e.level or 0) end
		truthy(maxLevel < 1000, "no HUD row carries a raw stored value (max " .. maxLevel .. ")")
	end
end

--======================================================================= 5. the physical board, drawn by Ava's client

local function boardTexts()
	local gui = board and board:FindFirstChildWhichIsA("SurfaceGui", true)
	local texts = {}
	if gui then
		for _, d in gui:GetDescendants() do
			if d:IsA("TextLabel") and d.Visible ~= false and (d.Text or "") ~= "" then table.insert(texts, d.Text) end
		end
	end
	return texts, gui
end
local function has(texts, needle)
	for _, t in texts do if string.find(t, needle, 1, true) then return t end end
	return nil
end
do
	local texts, gui = boardTexts()
	truthy(gui ~= nil, "Ava's client draws a SurfaceGui on the board")
	truthy(gui == nil or gui.Face == Enum.NormalId.Front, "on its front face")
	truthy(A.PlayerGui:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "not in PlayerGui (the HUD fit check measures everything there as screen)")
	truthy(has(texts, "PUBLIC") ~= nil, "the board says PUBLIC")
	local row1 = has(texts, "User_505")
	truthy(row1 ~= nil and string.find(row1, "50", 1, true) ~= nil, "row 1: User_505, level 50 (" .. tostring(row1) .. ")")
	local mine = has(texts, "Ava")
	truthy(mine ~= nil and string.find(mine, "13", 1, true) ~= nil, "Ava's own row shows 13 (" .. tostring(mine) .. ")")
	truthy(has(texts, BC.Text.Prompt) ~= nil, "and says how to switch (" .. tostring(has(texts, BC.Text.Prompt)) .. ")")
end

--======================================================================= 6. friends: on demand, cached, per player

eq(friendCalls[501], nil, "no friends were fetched before anyone asked")
local readsBefore = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(2)
eq(friendCalls[501], 1, "the prompt fetches Ava's friends once")
local fv = lastView(A)
truthy(fv ~= nil and fv.mode == "friends", "Ava's board is now FRIENDS")
if fv then
	local order = {}
	for _, r in fv.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier) .. (if r.you then "*" else "")) end
	eq(table.concat(order, " "), "505:50 508:20 501:13* 502:12", "friends view: Eve 50, Gus 20, Ava 13 (you), Bo 12; Finn never cleared a level")
	eq(fv.note, nil, "all four friends checked: no note")
end
do
	local newReads = {}
	for i = readsBefore + 1, #reads do table.insert(newReads, reads[i]) end
	table.sort(newReads)
	eq(table.concat(newReads, ","), "u_505,u_506,u_508", "the scores read are the three friends NOT in this server (Bo's comes from memory)")
end
do
	local texts = boardTexts()
	truthy(has(texts, "FRIENDS") ~= nil, "the board says FRIENDS")
	truthy(has(texts, "Eve") ~= nil, "and names Eve (from the friends list, not a stored name)")
end
eq(lastView(B) and lastView(B).mode, "public", "Bo's board is still PUBLIC: the toggle is per player")
if prompt then prompt.Triggered:Fire(A) end
h:advance(1)
eq(lastView(A) and lastView(A).mode, "public", "the prompt again: back to PUBLIC")
local readsMid = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(1)
eq(lastView(A) and lastView(A).mode, "friends", "and FRIENDS again")
eq(friendCalls[501], 1, "the friends list came from the cache (still 1 fetch)")
eq(#reads, readsMid, "and so did every score (no new reads)")

--======================================================================= 7. empty friends boards say something useful

local function friendsNoteFor(name, uid)
	seed(uid, { accepted = 0, level = 1 })
	local p = joinAs(name, uid)
	h:advance(1)
	if prompt then prompt.Triggered:Fire(p) end
	h:advance(3)
	local v = lastView(p)
	return v and v.note, v
end
do
	local noFriends = friendsNoteFor("Hal", 510)
	eq(noFriends, BC.Text.NoFriends, "no friends: says friends you add show up here")
	local noScores = friendsNoteFor("Ida", 511)
	eq(noScores, string.format(BC.Text.FriendsNoScores, 1), "friends who never cleared a level: says so, and invites")
	local failedNote, fview = friendsNoteFor("Jon", 512)
	eq(failedNote, BC.Text.FriendsFailed, "the friends call fails: says try again, no crash")
	eq(fview and fview.mode, "friends", "and still shows the friends view")
end

--======================================================================= 8. capped at 200 and throttled

do
	local readsAt = #reads
	local advancedAt = pagesAdvanced
	seed(513, { accepted = 0, level = 1 })
	local p = joinAs("Kim", 513)
	h:advance(1)
	if prompt then prompt.Triggered:Fire(p) end
	h:advance(1)
	local early = #reads - readsAt
	truthy(early <= BC.ReadsBurst + 2, "450 friends: at most the burst is read at once (" .. early .. " in the first second)")
	local mid = lastView(p)
	truthy(mid and mid.note and string.find(mid.note, "of 200", 1, true) ~= nil, "the board says how far it has got (" .. tostring(mid and mid.note) .. ")")
	h:advance(59)
	local minute = #reads - readsAt
	truthy(minute <= BC.ReadsBurst + BC.ReadsPerSecond * 60 + 1, "a minute in: " .. minute .. " reads, never more than burst + rate * 60")
	h:advance(240)
	local total = #reads - readsAt
	print(string.format("  450 friends: %d reads in the first second, %d in the first minute, %d in all; %d pages turned",
		early, minute, total, pagesAdvanced - advancedAt))
	eq(total, 200, "in the end exactly the first 200 friends are read, not 450")
	truthy(pagesAdvanced - advancedAt <= 4, "and no page past the 200th friend is fetched (" .. (pagesAdvanced - advancedAt) .. " pages turned)")
	local done = lastView(p)
	eq(done and done.note, string.format(BC.Text.FriendsNoScores, 200), "then the note says none of the 200 has cleared a level")
end

--======================================================================= 8b. Ava's board stayed Ava's

do
	local texts = boardTexts()
	truthy(has(texts, "FRIENDS") ~= nil and has(texts, "Eve") ~= nil and has(texts, "Pal") == nil,
		"Ava's board still shows Ava's friends, not the views sent to other players")
end

--======================================================================= 9. names are never stored

do
	local HttpService = h.game:GetService("HttpService")
	local leaked = nil
	for uid, name in { [501] = "Ava", [502] = "Bo", [503] = "Cy", [504] = "Dee" } do
		local rec = profiles:GetAsync("p_" .. uid)
		local json = HttpService:JSONEncode(rec)
		if string.find(json, '"' .. name .. '"', 1, true) then leaked = leaked or name end
	end
	truthy(leaked == nil, "no saved profile holds a player's name" .. (if leaked then " (" .. leaked .. ")" else ""))
	local allNumbers = true
	for k, v in lb.__data do
		if type(v) ~= "number" or not string.match(k, "^u_%d+$") then allNumbers = false end
	end
	truthy(allNumbers, "the board's store holds only numbers, under u_<userId> keys")
end

print("")
for _, w in h.warnings do print("warning: " .. w) end
local unexpected = 0
for _, w in h.warnings do
	if not string.find(w, "Lou er låst", 1, true) then unexpected += 1 end
end
eq(unexpected, 0, "no warnings except Lou's read-only load")
c.finish(h)
