-- +1 Jump Every Step — the highscore board, public + friends. Run: luau check_plus1jump_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot
-- inflate (check_plus1jump_walk.luau covers the guard), ties to whoever reached it FIRST; OrderedDataStore key
-- u_<userId>, value metric * 2e9 + (2e9 - reachedAtUnix), written only when the metric improves; the public
-- top 10 cached ~60 s; friends via Players:GetFriendsAsync, capped at 200, fetched only on demand, cached,
-- pcall'd and throttle-safe; a physical board near spawn with a ProximityPrompt that toggles Public/Friends;
-- names resolved and cached, never stored; an empty friends board says something useful.
-- Everything is driven through the REAL server and the real Board.client. The emulator has no
-- Players:GetFriendsAsync, so this file supplies one (FriendPages-shaped: GetCurrentPage / IsFinished /
-- AdvanceToNextPageAsync) and counts the calls.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/plus1-jump"), name = "plus1-jump", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players

-- saved profiles, before the server starts (the board's store is filled from them on the first autosave)
local profilesStore = DSS:GetDataStore("Plus1Jump_v1")
local function seed(uid, d)
	d.redeemed = d.redeemed or {}
	d.passes = d.passes or {}
	profilesStore:SetAsync("u_" .. uid, { data = d })
end
seed(501, { frontierTier = 12, frontierIdx = 6, jumpPower = 72, rebirths = 0, bestTier = 12, bestTierAt = 1780000000 })
seed(502, { frontierTier = 12, frontierIdx = 3, jumpPower = 69, rebirths = 0, bestTier = 12, bestTierAt = 1770000000 })
seed(503, { frontierTier = 30, frontierIdx = 1, jumpPower = 175, rebirths = 0, bestTier = 30, bestTierAt = 1785000000 })
seed(504, { frontierTier = 9, frontierIdx = 2, jumpPower = 50, rebirths = 0, bestTier = 9 }) -- saved before 2026-09-30: no bestTierAt
-- Ned: the board already holds 25 for him (a session whose profile write was lost), his profile says 15
seed(509, { frontierTier = 15, frontierIdx = 1, jumpPower = 85, rebirths = 0, bestTier = 15, bestTierAt = 1775000000 })

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Board = h:_require(RS:FindFirstChild("Board"))
local bc = Config.Board
truthy(type(bc) == "table" and type(Board) == "table", "Config.Board and the Board module exist")
bc = bc or { Text = {}, PublicRows = 10, FriendsRows = 10, ReadsBurst = 40, ReadsPerSecond = 1, FriendsCap = 200 }

local lb = DSS:GetOrderedDataStore(Config.Save.Leaderboard)
-- offline climbers already on the board
lb:SetAsync("u_505", Board and Board.encode(50, 1760000000, bc) or 50)
lb:SetAsync("u_508", Board and Board.encode(20, 1765000000, bc) or 20)
lb:SetAsync("u_509", Board and Board.encode(25, 1750000000, bc) or 25)

-- count what the server does to the board's store
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

local board = h.workspace:FindFirstChild("TopClimbersBoard")
truthy(board ~= nil and board:IsA("BasePart"), "a physical board stands in the world (workspace.TopClimbersBoard)")
local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt", true)
truthy(prompt ~= nil, "with a ProximityPrompt")
local spawnPad = h.workspace:FindFirstChild("Tower") and h.workspace.Tower:FindFirstChild("TempleSpawn")
if board and spawnPad then
	local d = (board.Position - spawnPad.Position)
	local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
	truthy(flat <= 16, string.format("near spawn (%.1f studs from the spawn pad)", flat))
	local look = board.CFrame.LookVector
	local toSpawn = Vector3.new(spawnPad.Position.X - board.Position.X, 0, spawnPad.Position.Z - board.Position.Z)
	local cos = (look.X * toSpawn.X + look.Z * toSpawn.Z) / math.max(toSpawn.Magnitude, 1e-6)
	truthy(cos > 0.95, string.format("its front face (where the board is drawn) faces the spawn (cos %.2f)", cos))
	-- the climb never passes through it: tiers 1-12, every platform box grown by 4 studs
	local TowerGen = h:_require(RS:FindFirstChild("TowerGen"))
	local cs = TowerGen.platformCentres({ Tower = Config.Tower, Jump = Config.Jump, WorldSeed = Config.WorldSeed }, 1, 12)
	local hx, hy, hz = board.Size.X / 2, board.Size.Y / 2, board.Size.Z / 2
	local clash = nil
	for _, c in cs do
		local half = Config.Tower.TileSize / 2 + 4
		if math.abs(c.x - board.Position.X) < hx + half and math.abs(c.y - board.Position.Y) < hy + 4
			and math.abs(c.z - board.Position.Z) < hz + half then -- faces +Z: Size.X runs along world X, Size.Z along Z
			clash = clash or string.format("P_%d_%d", c.tier, c.idx)
		end
	end
	truthy(clash == nil, "and no platform of tiers 1-12 comes within 4 studs of it" .. (if clash then " (" .. clash .. ")" else ""))
end
if prompt then
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
	truthy(#prompt.ActionText > 0, "and it says what it does (" .. prompt.ActionText .. ")")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
end

--======================================================================= 2. the stored value, and ties

h.game:GetService("RunService"):setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	h.Players:simulateSpawn(p, h.workspace)
	return p
end
local B = joinAs("Bo", 502)
local C = joinAs("Cy", 503)
local D = joinAs("Dee", 504)
local N = joinAs("Ned", 509)
local joinedAt = os.time()
local A = joinAs("Ava", 501) -- last: the client scripts below are Ava's
assert(h:tryRun("client/Hud.client"))
local okClient, errClient = h:tryRun("client/Board.client")
truthy(okClient, "Board.client loads (" .. tostring(errClient) .. ")")
h:advance(Config.Save.AutosaveSeconds + 1)

-- read the store directly (not through the counted GetAsync)
local function stored(uid) return lb.__data["u_" .. uid] end
local function decode(v) if Board and type(v) == "number" then return Board.decode(v) end return nil, nil end
table.clear(reads)
eq(stored(501), Board and Board.encode(12, 1780000000, bc), "Ava's saved best (12, reached 1780000000) is stored encoded")
eq(stored(502), Board and Board.encode(12, 1770000000, bc), "Bo's too (12, reached EARLIER)")
eq(stored(503), Board and Board.encode(30, 1785000000, bc), "and Cy's (30)")
eq(stored(509), Board and Board.encode(25, 1750000000, bc), "Ned's 25 on the board is never lowered to his profile's 15")
do
	local m, t = decode(stored(504))
	eq(m, 9, "a save from before bestTierAt existed still gets on the board (Dee, 9)")
	truthy(t ~= nil and math.abs(t - joinedAt) <= 5, "stamped with the session it came back in (" .. tostring(t) .. " vs " .. joinedAt .. ")")
end

-- the public view the server sends, and the HUD's top list
local boardRemote = RS:FindFirstChild("Plus1Remotes"):FindFirstChild("Board")
truthy(boardRemote ~= nil, "a Board remote exists")
local function lastView(plr)
	if not boardRemote then return nil end
	local sent = boardRemote:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
h:advance(bc.PublicCacheSeconds + 1) -- the next public refresh sees the new values
local pub = lastView(A)
truthy(pub ~= nil and pub.mode == "public", "Ava's board starts on the PUBLIC view")
if pub then
	local order = {}
	for _, r in pub.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier) .. ":" .. tostring(r.name)) end
	eq(table.concat(order, " "), "505:50:User_505 503:30:Cy 509:25:Ned 508:20:User_508 502:12:Bo 501:12:Ava 504:9:Dee",
		"public view: highest first, Bo above Ava on the same tier (he got there first), names resolved")
end

--======================================================================= 3. written only when it improves

local writesBefore = writes
h:advance(2 * Config.Save.AutosaveSeconds + 1)
eq(writes, writesBefore, "two autosaves with no new best tier write nothing to the board")
-- Ava climbs one honest platform: P_12_6 -> P_13_1 (her character stands on P_12_6 since she joined)
do
	local hrp = A.Character:FindFirstChild("HumanoidRootPart")
	local nextPart = h.workspace.Tower:FindFirstChild("P_13_1")
	hrp.CFrame = CFrame.new(nextPart.Position + Vector3.new(0, 3.5, 0))
	h:advance(1)
	nextPart.Touched:Fire(hrp)
	eq(A.leaderstats.Tier.Value, 13, "set-up: Ava is credited tier 13")
	local climbedAt = os.time()
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(writes, writesBefore + 1, "a new best tier: exactly one write at the next save")
	local m, t = decode(stored(501))
	eq(m, 13, "the board now holds 13 for Ava")
	truthy(t ~= nil and math.abs(t - climbedAt) <= 5, "stamped when she reached it (" .. tostring(t) .. " vs " .. climbedAt .. ")")
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(writes, writesBefore + 1, "and nothing more after that")
end

--======================================================================= 4. the public list is cached ~60 s

do
	local s0 = sorted
	h:advance(180)
	local n = sorted - s0
	print(string.format("  public top 10: %d GetSortedAsync calls in 180 s", n))
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 180 s (one per " .. bc.PublicCacheSeconds .. " s)")
	-- the HUD's top list gets decoded tiers and names, never the stored value
	local lbRemote = RS:FindFirstChild("Plus1Remotes"):FindFirstChild("Leaderboard")
	local sent = lbRemote:sentTo(A)
	local top = sent[#sent] and sent[#sent].args[1]
	truthy(type(top) == "table" and top[1] ~= nil, "the HUD's top list is sent")
	if top and top[1] then
		eq(top[1].tier, 50, "HUD row 1 is tier 50, decoded")
		eq(top[1].name, "User_505", "with its name")
		local maxTier = 0
		for _, e in top do maxTier = math.max(maxTier, e.tier or 0) end
		truthy(maxTier < 1000, "no HUD row carries a raw stored value (max " .. maxTier .. ")")
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
	truthy(row1 ~= nil and string.find(row1, "50", 1, true) ~= nil, "row 1: User_505, 50 (" .. tostring(row1) .. ")")
	local mine = has(texts, "Ava")
	truthy(mine ~= nil and string.find(mine, "13", 1, true) ~= nil, "Ava's own row shows 13 (" .. tostring(mine) .. ")")
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
	eq(table.concat(order, " "), "505:50 508:20 501:13* 502:12", "friends view: Eve 50, Gus 20, Ava 13 (you), Bo 12; Finn never climbed")
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
eq(lastView(B).mode, "public", "Bo's board is still PUBLIC: the toggle is per player")
if prompt then prompt.Triggered:Fire(A) end
h:advance(1)
eq(lastView(A).mode, "public", "the prompt again: back to PUBLIC")
local readsMid = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(1)
eq(lastView(A).mode, "friends", "and FRIENDS again")
eq(friendCalls[501], 1, "the friends list came from the cache (still 1 fetch)")
eq(#reads, readsMid, "and so did every score (no new reads)")

--======================================================================= 7. empty friends boards say something useful

local function friendsNoteFor(name, uid)
	local p = joinAs(name, uid)
	h:advance(1)
	if prompt then prompt.Triggered:Fire(p) end
	h:advance(3)
	local v = lastView(p)
	return v and v.note, v
end
do
	local noFriends = friendsNoteFor("Hal", 510)
	eq(noFriends, bc.Text.NoFriends, "no friends: says friends you add show up here")
	local noScores = friendsNoteFor("Ida", 511)
	eq(noScores, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 1), "friends who never climbed: says so, and invites")
	local failedNote, fview = friendsNoteFor("Jon", 512)
	eq(failedNote, bc.Text.FriendsFailed, "the friends call fails: says try again, no crash")
	eq(fview and fview.mode, "friends", "and still shows the friends view")
end

--======================================================================= 8. capped at 200 and throttled

do
	local readsAt = #reads
	local advancedAt = pagesAdvanced
	local p = joinAs("Kim", 513)
	h:advance(1)
	if prompt then prompt.Triggered:Fire(p) end
	h:advance(1)
	local early = #reads - readsAt
	truthy(early <= bc.ReadsBurst + 2, "450 friends: at most the burst is read at once (" .. early .. " in the first second)")
	local mid = lastView(p)
	truthy(mid and mid.note and string.find(mid.note, "of 200", 1, true) ~= nil, "the board says how far it has got (" .. tostring(mid and mid.note) .. ")")
	h:advance(59)
	local minute = #reads - readsAt
	truthy(minute <= bc.ReadsBurst + bc.ReadsPerSecond * 60 + 1, "a minute in: " .. minute .. " reads, never more than burst + rate * 60")
	h:advance(240)
	local total = #reads - readsAt
	print(string.format("  450 friends: %d reads in the first second, %d in the first minute, %d in all; %d pages turned",
		early, minute, total, pagesAdvanced - advancedAt))
	eq(total, 200, "in the end exactly the first 200 friends are read, not 450")
	truthy(pagesAdvanced - advancedAt <= 4, "and no page past the 200th friend is fetched (" .. (pagesAdvanced - advancedAt) .. " pages turned)")
	local done = lastView(p)
	eq(done and done.note, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 200), "then the note says none of the 200 has climbed")
end

--======================================================================= 8b. Ava's board stayed Ava's

do
	-- Hal, Ida, Jon and Kim were sent friends views since; this client (Ava's) draws only views addressed to Ava
	local texts = boardTexts()
	truthy(has(texts, "FRIENDS") ~= nil and has(texts, "Eve") ~= nil and has(texts, "Pal") == nil,
		"Ava's board still shows Ava's friends, not the views sent to other players")
	-- the HUD's top list uses the names the server sends (Eve, learnt from Ava's friends list)
	h:advance(bc.PublicCacheSeconds + 1)
	local hudRoot = A.PlayerGui:FindFirstChild("Plus1Hud")
	local row1 = nil
	for _, d in hudRoot:GetDescendants() do
		if d:IsA("TextLabel") and string.match(d.Text or "", "^1%. ") then row1 = d.Text end
	end
	truthy(row1 ~= nil and string.find(row1, "Eve", 1, true) ~= nil, "the HUD's top list shows the server's name for row 1 (" .. tostring(row1) .. ")")
end

--======================================================================= 9. names are never stored

do
	local HttpService = h.game:GetService("HttpService")
	local leaked = nil
	for uid, name in { [501] = "Ava", [502] = "Bo", [503] = "Cy", [504] = "Dee" } do
		local rec = profilesStore:GetAsync("u_" .. uid)
		local json = HttpService:JSONEncode(rec)
		if string.find(json, '"' .. name .. '"', 1, true) then leaked = leaked or name end
	end
	truthy(leaked == nil, "no saved profile holds a player's name" .. (if leaked then " (" .. leaked .. ")" else ""))
	local allNumbers = true
	for _, uid in { 501, 502, 503, 504, 505, 508 } do
		if type(stored(uid)) ~= "number" then allNumbers = false end
	end
	truthy(allNumbers, "the board's store holds only numbers")
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1jump board: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1jump board check failed", 0)
end
