-- FACILITY: Endless Nightmare — the TOP DIVERS highscore board, public + friends. Run: luau check_facilitynightmare_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot inflate,
-- ties to whoever reached it FIRST; OrderedDataStore key u_<userId>, value metric * 2e9 + (2e9 - reachedAtUnix),
-- written only when the metric improves; the public top 10 cached ~60 s; friends via Players:GetFriendsAsync, capped
-- at 200, fetched only on demand, cached, pcall'd and throttle-safe; a physical board near spawn with a
-- ProximityPrompt that toggles Public/Friends; names resolved and cached, never stored; an empty friends board says
-- something useful.
--
-- FACILITY's metric is the profile's bestSublevel: the deepest sublevel whose freight elevator the SERVER powered,
-- behind the trusted position (Trust.luau; Trust.spec fuzzes it). Everything is driven through the REAL server, the
-- real Board.client and Env.client, and a real bot (tests/Bot.luau) that powers real lifts. The emulator has no
-- Players:GetFriendsAsync, so this file supplies one (FriendPages-shaped) and counts the calls. Adapted from
-- check_plus1jump_board.luau.

local Harness = require("./emu/harness")
local Bot = require("../facility-nightmare/tests/Bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local h = Harness.new({ bundle = require("./build/facility-nightmare"), name = "facility-nightmare", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local Vector3 = h.instance.datatypes.Vector3 -- the emulator's, so it mixes with Instance positions
local Enum = h.Enum or Enum
local DSS = h.services.DataStoreService
local Players = h.Players

-- Written out, not read from Config: a number checked against itself is not a check.
local STORE, BOARD_STORE = "FacilityNightmare_v1", "FacilityNightmare_TopDivers_v1"
local AUTOSAVE, PUBLIC_TTL, BURST, RATE, CAP = 20, 60, 40, 1, 200

-- saved profiles, before the server starts (the board is filled from them at the first save)
local profilesStore = DSS:GetDataStore(STORE)
local function seed(uid, extra)
	local p = { v = 1, essence = 0, essenceEarned = 0, bestSublevel = 0, runs = 1, extractions = 0,
		perks = { deepCell = 0, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } }
	for k, v in extra do p[k] = v end
	profilesStore:SetAsync("u_" .. uid, { data = p })
end
local AVA, BO, CY, DEE, EVE, FINN, GUS, NED, NEW, HAL, IDA, JON, KIM = 8101, 8102, 8103, 8104, 8105, 8106, 8108, 8109, 8110, 8111, 8112, 8113, 8114
seed(AVA, { bestSublevel = 4, bestAt = 1780000000, runs = 5 })
seed(BO, { bestSublevel = 4, bestAt = 1770000000, runs = 5 }) -- the same depth, reached EARLIER
seed(CY, { bestSublevel = 9, bestAt = 1785000000, runs = 9 })
seed(DEE, { bestSublevel = 3, runs = 3 }) -- saved before the board existed: no bestAt
seed(NED, { bestSublevel = 5, bestAt = 1775000000, runs = 6 }) -- the board already holds 8 for him (a lost profile write)
-- NEW's first-ever run (the dark waits for the first fuse), with every perk so the bot's later runs cannot die
seed(NEW, { runs = 0, perks = { deepCell = 3, nightEyes = 3, marathon = 3, soulAnchor = 3, secondWind = 1 } })

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "server/Main.server loads (" .. tostring(bootErr) .. ")")
if not okBoot then
	print(string.format("check_facilitynightmare_board: %d passed, %d failed", passed, failed))
	error("boot failed", 0)
end
local Config = h:_require(RS:FindFirstChild("Config"))
local okMod, Board = pcall(function() return h:_require(RS:FindFirstChild("Board")) end)
Board = if okMod then Board else nil
local bc = Config.Board
truthy(type(bc) == "table" and type(Board) == "table", "Config.Board and the Board module exist")
bc = bc or { Text = {}, PublicRows = 10, FriendsRows = 10, ReadsBurst = BURST, ReadsPerSecond = RATE, FriendsCap = CAP, MaxMetric = 4e6 }
eq(bc.Store, BOARD_STORE, "the board's OrderedDataStore is " .. BOARD_STORE)
eq(bc.PublicCacheSeconds, PUBLIC_TTL, "the public top 10 is cached 60 s")
eq(bc.FriendsCap, CAP, "friends are capped at 200")
eq(Config.Data.AutosaveSeconds, AUTOSAVE, "set-up: profiles autosave every 20 s")

local function enc(m, t) return if Board then Board.encode(m, t, bc) else m end
local lb = DSS:GetOrderedDataStore(BOARD_STORE)
-- offline divers already on the board
lb:SetAsync("u_" .. EVE, enc(12, 1760000000))
lb:SetAsync("u_" .. GUS, enc(6, 1765000000))
lb:SetAsync("u_" .. NED, enc(8, 1750000000))

-- count what the server does to the board's store
local writes, sorted, reads = 0, 0, {}
local failSorted = false -- the next GetSortedAsync raises, as a throttled or failing store does
do
	local oUpdate, oSet, oSorted, oGet = lb.UpdateAsync, lb.SetAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; return oSet(self, ...) end
	lb.GetSortedAsync = function(self, ...)
		sorted += 1
		if failSorted then
			failSorted = false
			error("502: API Services rejected request", 0)
		end
		return oSorted(self, ...)
	end
	lb.GetAsync = function(self, key, ...) table.insert(reads, key); return oGet(self, key, ...) end
end

-- friends, per user id: a list of { Id, Username } (or "error")
local friendsOf = {
	[AVA] = { { BO, "Bo" }, { EVE, "Eve" }, { FINN, "Finn" }, { GUS, "Gus" } },
	[HAL] = {},
	[IDA] = { { FINN, "Finn" } },
	[JON] = "error",
}
do
	local big = {}
	for i = 1, 450 do table.insert(big, { 20000 + i, "Pal" .. i }) end
	friendsOf[KIM] = big
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
section("1. the board stands in the break room, near the spawn, facing it")

local hub = h.workspace:FindFirstChild("Hub")
local board = hub and hub:FindFirstChild("TopDiversBoard")
truthy(board ~= nil and board:IsA("BasePart"), "a physical board stands in the break room (workspace.Hub.TopDiversBoard)")
local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt", true)
truthy(prompt ~= nil, "with a ProximityPrompt")
local spawnPad = hub and hub:FindFirstChild("HubSpawn")
if board and spawnPad then
	local d = board.Position - spawnPad.Position
	local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
	-- the break room is 60 x 40; its long walls are 20 studs either side of the spawn row, as the DEPTH RECORD's is
	print(string.format("  board centre %.1f studs from HubSpawn (flat)", flat))
	truthy(flat <= 22, string.format("near the spawn (%.1f studs from HubSpawn)", flat))
	local look = board.CFrame.LookVector
	local toSpawn = Vector3.new(spawnPad.Position.X - board.Position.X, 0, spawnPad.Position.Z - board.Position.Z)
	local cos = (look.X * toSpawn.X + look.Z * toSpawn.Z) / math.max(toSpawn.Magnitude, 1e-6)
	truthy(cos > 0.95, string.format("its front face (where the board is drawn) faces the spawn (cos %.2f)", cos))
	-- inside the room, against a wall, and off everything a player walks to
	local hx, hz = board.Size.X / 2, board.Size.Z / 2
	truthy(math.abs(board.Position.X) + hx <= 30 and math.abs(board.Position.Z) + hz <= 20, "inside the break room's walls")
	truthy(math.abs(board.Position.Z) + hz >= 19.5, "against a wall (not standing in the room)")
	local function clear(name, part, grow)
		if not part then return end
		local dx = math.abs(part.Position.X - board.Position.X) - (part.Size.X / 2 + hx + grow)
		local dz = math.abs(part.Position.Z - board.Position.Z) - (part.Size.Z / 2 + hz + grow)
		truthy(dx > 0 or dz > 0, "clear of " .. name)
	end
	clear("the perk terminal", hub:FindFirstChild("PerkTerminal"), 3)
	clear("the elevator car", hub:FindFirstChild("HubCar") and hub.HubCar:FindFirstChild("CarFloor"), 3)
	clear("the arrival pad", hub:FindFirstChild("HubArrival"), 3)
	clear("the spawn", spawnPad, 3)
	local benches = hub:FindFirstChild("Benches")
	for _, b in (benches and benches:GetChildren() or {}) do clear(b.Name, b, 1) end
	truthy(math.abs(board.Position.Z) - hz > 6, "off the spawn -> car -> arrival row (z = 0)")
end
if prompt then
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
	truthy(#prompt.ActionText > 0, "and it says what it does (" .. prompt.ActionText .. ")")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
	eq(prompt.RequiresLineOfSight, false, "and no line of sight is needed (the board face is a wall)")
	local at = prompt.Parent
	-- (the emulator has no Attachment.WorldPosition: the board's CFrame places the attachment)
	local wp = if at and at:IsA("Attachment") then board.CFrame:PointToWorldSpace(at.Position) else board.Position
	-- a player standing on the floor 3 studs in front of the board is within reach
	local stand = Vector3.new(board.Position.X, 3, board.Position.Z - 3 * math.sign(board.Position.Z))
	truthy((wp - stand).Magnitude <= bc.PromptDistance, string.format("reachable from the floor in front of it (%.1f studs)", (wp - stand).Magnitude))
end

--======================================================================= 2. the stored value, and ties
section("2. what is stored: the owner's formula, ties to the first")

h.game:GetService("RunService"):setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	h.Players:simulateSpawn(p, h.workspace)
	return p
end
local B = joinAs("Bo", BO)
local C = joinAs("Cy", CY)
local D = joinAs("Dee", DEE)
local N = joinAs("Ned", NED)
local joinedAt = os.time()
local A = joinAs("Ava", AVA) -- last: the client scripts below are Ava's
local okBoardClient, errBoardClient = h:tryRun("client/Board.client")
truthy(okBoardClient, "Board.client loads (" .. tostring(errBoardClient) .. ")")
local okEnv, errEnv = h:tryRun("client/Env.client")
truthy(okEnv, "Env.client loads beside it (" .. tostring(errEnv) .. ")")
h:advance(AUTOSAVE + 1)

-- read the store directly (not through the counted GetAsync)
local function stored(uid) return lb.__data["u_" .. uid] end
local function decode(v) if Board and type(v) == "number" then return Board.decode(v) end return nil, nil end
table.clear(reads)
eq(stored(AVA), enc(4, 1780000000), "Ava's saved record (sublevel 4, reached 1780000000) is stored encoded")
eq(stored(BO), enc(4, 1770000000), "Bo's too (sublevel 4, reached EARLIER)")
eq(stored(CY), enc(9, 1785000000), "and Cy's (9)")
eq(stored(NED), enc(8, 1750000000), "Ned's 8 on the board is never lowered to his profile's 5")
do
	local m, t = decode(stored(DEE))
	eq(m, 3, "a save from before the board existed still gets on it (Dee, 3)")
	truthy(t ~= nil and math.abs(t - joinedAt) <= 5, "stamped with the session it came back in (" .. tostring(t) .. " vs " .. joinedAt .. ")")
	local rec = profilesStore:GetAsync("u_" .. DEE)
	eq(rec and rec.data and rec.data.bestAt, t, "and that stamp is saved in Dee's profile, so it never moves again")
end

local remotes = RS:FindFirstChild("FacilityRemotes")
local boardRemote = remotes and remotes:FindFirstChild("Board")
truthy(boardRemote ~= nil and boardRemote.ClassName == "RemoteEvent", "a Board remote exists")
local function lastView(plr)
	if not boardRemote then return nil end
	local sent = boardRemote:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
h:advance(PUBLIC_TTL + 1) -- the next public refresh sees the new values
local pub = lastView(A)
truthy(pub ~= nil and pub.mode == "public", "Ava's board starts on the PUBLIC view")
eq(pub and pub.viewer, AVA, "addressed to Ava")
if pub then
	local order = {}
	for _, r in pub.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier) .. ":" .. tostring(r.name)) end
	eq(table.concat(order, " "), "8105:12:User_8105 8103:9:Cy 8109:8:Ned 8108:6:User_8108 8102:4:Bo 8101:4:Ava 8104:3:Dee",
		"public view: deepest first, Bo above Ava on the same sublevel (he got there first), names resolved")
	local maxTier = 0
	for _, r in pub.rows do maxTier = math.max(maxTier, tonumber(r.tier) or 0) end
	truthy(maxTier < 1000, "no row carries a raw stored value (max " .. maxTier .. ")")
end

--======================================================================= 3. written only when it improves, by a real powering
section("3. a powered lift that sets a record writes it once; nothing else writes")

local writesBefore = writes
h:advance(2 * AUTOSAVE + 1)
eq(writes, writesBefore, "two autosaves with no new record write nothing to the board")

-- forged remotes from the break room change nothing on the board (the metric is the server's)
do
	local w0 = writes
	remotes:FindFirstChild("Choose"):simulateFireServer(A, "descend")
	remotes:FindFirstChild("Choose"):simulateFireServer(A, "extract")
	remotes:FindFirstChild("BuyPerk"):simulateFireServer(A, "deepCell")
	h:advance(AUTOSAVE + 1)
	eq(writes, w0, "forged CHOOSE / BUY from the break room: no board write")
	eq(stored(AVA), enc(4, 1780000000), "and Ava's entry is unchanged")
end

-- NEW plays: sublevel 1 (a record: one write), DESCEND, sublevel 2 (a record: one more), EXTRACT, then sublevel 1
-- again (not a record: no write).
local newbie = joinAs("Newbie", NEW)
h:advance(1)
local nBot = Bot.new(h, newbie, { maxSeconds = 900 })
local w0 = writes
truthy(nBot:board(hub) and nBot:waitPhase("floor", 6), "set-up: NEW rides down to sublevel 1")
local r1 = nBot:clearFloor()
eq(r1, "powered", "set-up: NEW powers sublevel 1")
local powered1At = os.time()
nBot:waitSeconds(1)
eq(writes, w0 + 1, "a new record: exactly one board write, at the powering's own save")
do
	local m, t = decode(stored(NEW))
	eq(m, 1, "the board holds sublevel 1 for NEW")
	truthy(t ~= nil and math.abs(t - powered1At) <= 5, "stamped when the lift powered (" .. tostring(t) .. " vs " .. powered1At .. ")")
end
nBot:fire("Choose", "descend")
truthy(nBot:waitPhase("floor", 6), "set-up: NEW descends to sublevel 2")
eq(nBot:clearFloor(), "powered", "set-up: NEW powers sublevel 2")
nBot:waitSeconds(1)
eq(writes, w0 + 2, "a deeper record: one more write")
eq((decode(stored(NEW))), 2, "the board now holds sublevel 2")
nBot:fire("Choose", "extract")
truthy(nBot:waitPhase("hub", 8), "set-up: NEW extracts to the break room")
h:advance(AUTOSAVE + 1)
eq(writes, w0 + 2, "extracting and the autosave after it write nothing more")
local stampBefore = stored(NEW)
truthy(nBot:board(hub) and nBot:waitPhase("floor", 6), "set-up: NEW goes down again")
eq(nBot:clearFloor(), "powered", "set-up: NEW powers sublevel 1 again")
nBot:waitSeconds(1)
eq(writes, w0 + 2, "powering a depth already on the board writes nothing")
eq(stored(NEW), stampBefore, "and the first reach time stands")
nBot:fire("Choose", "extract")
nBot:waitPhase("hub", 8)

--======================================================================= 4. the public list is cached ~60 s
section("4. the public top 10 is read at most once a minute")

do
	local s0 = sorted
	h:advance(180)
	local n = sorted - s0
	print(string.format("  public top 10: %d GetSortedAsync calls in 180 s", n))
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 180 s (one per " .. PUBLIC_TTL .. " s)")
	-- a failing read keeps the last list and breaks nothing
	local function listOf(v)
		local out = {}
		for _, r in (v and v.rows or {}) do table.insert(out, tostring(r.userId) .. ":" .. tostring(r.tier)) end
		return table.concat(out, " ")
	end
	local before = listOf(lastView(A))
	local s1 = sorted
	failSorted = true
	h:advance(PUBLIC_TTL + 1)
	local v = lastView(A)
	truthy(sorted > s1 and not failSorted, "set-up: a GetSortedAsync failed in that minute")
	truthy(v ~= nil and v.mode == "public" and listOf(v) == before and #v.rows == 8,
		"a failed GetSortedAsync keeps the last list, all 8 divers (" .. listOf(v) .. ")")
end

--======================================================================= 5. the physical board, drawn by Ava's client
section("5. the board as Ava's client draws it")

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
	-- In Roblox a client receives only its OWN State; the emulator hands every player's FireClient to the one client.
	-- So Ava's last State is handed to her client again, and the band names below are read from HER record.
	local stR = remotes:FindFirstChild("State")
	local mine = stR:sentTo(A)
	truthy(#mine > 0 and mine[#mine].args[1].bestSublevel == 4, "set-up: Ava's own State says her record is 4")
	stR:FireClient(A, mine[#mine].args[1])
	local texts, gui = boardTexts()
	truthy(gui ~= nil, "Ava's client draws a SurfaceGui on the board")
	truthy(gui == nil or gui.Face == Enum.NormalId.Front, "on its front face")
	if gui and board then
		-- trap 14: a canvas takes its face's proportions, or the text is stretched
		local cs = gui.CanvasSize
		local ratio, face = cs.X / cs.Y, board.Size.X / board.Size.Y
		truthy(math.abs(ratio / face - 1) < 0.02, string.format("its canvas has the face's proportions (%.3f vs %.3f)", ratio, face))
	end
	truthy(A.PlayerGui:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "not in PlayerGui (the HUD fit check measures everything there as screen)")
	truthy(has(texts, "TOP DIVERS") ~= nil, "the board is titled TOP DIVERS")
	truthy(has(texts, "PUBLIC") ~= nil, "and says PUBLIC")
	local row1 = has(texts, "User_8105")
	truthy(row1 ~= nil and string.find(row1, "12", 1, true) ~= nil, "row 1: User_8105, sublevel 12 (" .. tostring(row1) .. ")")
	-- no spoilers: a band Ava has not reached (her record is 4: the labs) is not named, as on the DEPTH RECORD board
	truthy(row1 ~= nil and string.find(row1, "BIO-LAB", 1, true) == nil and string.find(row1, "???", 1, true) ~= nil,
		"a band Ava has not reached is ??? on her board, not named (" .. tostring(row1) .. ")")
	local mine = has(texts, "Ava")
	truthy(mine ~= nil and string.find(mine, "4", 1, true) ~= nil and string.find(mine, "LABORATORIES", 1, true) ~= nil,
		"Ava's own row: sublevel 4, LABORATORIES (" .. tostring(mine) .. ")")
end

--======================================================================= 6. friends: on demand, cached, per player
section("6. friends: fetched on demand, cached, per player")

eq(friendCalls[AVA], nil, "no friends were fetched before anyone asked")
local readsBefore = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(2)
eq(friendCalls[AVA], 1, "the prompt fetches Ava's friends once")
local fv = lastView(A)
truthy(fv ~= nil and fv.mode == "friends", "Ava's board is now FRIENDS")
if fv then
	local order = {}
	for _, r in fv.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier) .. (if r.you then "*" else "")) end
	eq(table.concat(order, " "), "8105:12 8108:6 8102:4 8101:4*", "friends view: Eve 12, Gus 6, Bo 4 (first there), Ava 4 (you); Finn never powered a lift")
	eq(fv.note, nil, "all four friends checked: no note")
end
do
	local newReads = {}
	for i = readsBefore + 1, #reads do table.insert(newReads, reads[i]) end
	table.sort(newReads)
	eq(table.concat(newReads, ","), "u_8105,u_8106,u_8108", "the scores read are the three friends NOT on this server (Bo's comes from memory)")
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
eq(friendCalls[AVA], 1, "the friends list came from the cache (still 1 fetch)")
eq(#reads, readsMid, "and so did every score (no new reads)")

--======================================================================= 7. empty friends boards say something useful
section("7. an empty friends board says something useful")

local function friendsNoteFor(name, uid)
	local p = joinAs(name, uid)
	h:advance(1)
	if prompt then prompt.Triggered:Fire(p) end
	h:advance(3)
	local v = lastView(p)
	return v and v.note, v
end
do
	local noFriends = friendsNoteFor("Hal", HAL)
	eq(noFriends, bc.Text.NoFriends, "no friends: says friends you add show up here")
	local noScores = friendsNoteFor("Ida", IDA)
	eq(noScores, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 1), "friends who never powered a lift: says so, and invites")
	local failedNote, fview = friendsNoteFor("Jon", JON)
	eq(failedNote, bc.Text.FriendsFailed, "the friends call fails: says try again, no crash")
	eq(fview and fview.mode, "friends", "and still shows the friends view")
end

--======================================================================= 8. capped at 200 and throttled
section("8. 450 friends: capped at 200, and throttled")

do
	local readsAt = #reads
	local advancedAt = pagesAdvanced
	local p = joinAs("Kim", KIM)
	h:advance(1)
	if prompt then prompt.Triggered:Fire(p) end
	h:advance(1)
	local early = #reads - readsAt
	truthy(early <= BURST + 2, "450 friends: at most the burst is read at once (" .. early .. " in the first second)")
	local mid = lastView(p)
	truthy(mid and mid.note and string.find(mid.note, "of 200", 1, true) ~= nil, "the board says how far it has got (" .. tostring(mid and mid.note) .. ")")
	h:advance(59)
	local minute = #reads - readsAt
	truthy(minute <= BURST + RATE * 60 + 1, "a minute in: " .. minute .. " reads, never more than burst + rate * 60")
	h:advance(240)
	local total = #reads - readsAt
	print(string.format("  450 friends: %d reads in the first second, %d in the first minute, %d in all; %d pages turned",
		early, minute, total, pagesAdvanced - advancedAt))
	eq(total, CAP, "in the end exactly the first 200 friends are read, not 450")
	truthy(pagesAdvanced - advancedAt <= 4, "and no page past the 200th friend is fetched (" .. (pagesAdvanced - advancedAt) .. " pages turned)")
	local done = lastView(p)
	eq(done and done.note, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, CAP), "then the note says none of the 200 has powered a lift")
end

--======================================================================= 8b. Ava's board stayed Ava's
do
	local texts = boardTexts()
	truthy(has(texts, "FRIENDS") ~= nil and has(texts, "Eve") ~= nil and has(texts, "Pal") == nil,
		"Ava's board still shows Ava's friends, not the views sent to other players")
end

--======================================================================= 9. names are never stored; nothing else leaks
section("9. names are never stored, and nothing about the board replicates")

do
	local HttpService = h.game:GetService("HttpService")
	local leaked = nil
	for uid, name in { [AVA] = "Ava", [BO] = "Bo", [CY] = "Cy", [DEE] = "Dee", [NEW] = "Newbie" } do
		local rec = profilesStore:GetAsync("u_" .. uid)
		local json = HttpService:JSONEncode(rec)
		if string.find(json, '"' .. name .. '"', 1, true) then leaked = leaked or name end
	end
	truthy(leaked == nil, "no saved profile holds a player's name" .. (if leaked then " (" .. leaked .. ")" else ""))
	local allNumbers = true
	for _, uid in { AVA, BO, CY, DEE, EVE, GUS, NED, NEW } do
		if type(stored(uid)) ~= "number" then allNumbers = false end
	end
	truthy(allNumbers, "the board's store holds only numbers")
	-- the board part carries no attribute, and the State payload no stored value
	local attrs = 0
	if board then for _ in board:GetAttributes() do attrs += 1 end end
	eq(attrs, 0, "the board part carries no attribute")
end

--======================================================================= 10. the break room's own dressing keeps off it
section("10. the break room's dressing (Env.client) keeps off the board")

do
	h.game:GetService("RunService").RenderStepped:Fire(0.1) -- one client frame: Env.client puts the break room out
	local env = h.workspace:FindFirstChild("FacilityEnvLocal")
	local room = env and env:FindFirstChild("BreakRoom")
	truthy(room ~= nil, "set-up: Ava's break-room dressing is out")
	local hit = nil
	if room and board then
		for _, p in room:GetDescendants() do
			if p:IsA("BasePart") then
				local dx = math.abs(p.Position.X - board.Position.X) - (p.Size.X / 2 + board.Size.X / 2)
				local dz = math.abs(p.Position.Z - board.Position.Z) - (p.Size.Z / 2 + board.Size.Z / 2 + 3) -- and the 3 studs in front
				if dx < 0 and dz < 0 then hit = hit or p.Name end
			end
		end
	end
	truthy(hit == nil, "no dressing stands on the board or in the 3 studs in front of it" .. (if hit then " (" .. hit .. ")" else ""))
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("check_facilitynightmare_board: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("check_facilitynightmare_board failed", 0)
end
