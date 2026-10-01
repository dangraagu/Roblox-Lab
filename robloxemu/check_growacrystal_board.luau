-- Grow a Crystal — the highscore board, public + friends. Run: luau check_growacrystal_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot inflate,
-- ties to whoever reached it FIRST; OrderedDataStore key u_<userId>, value metric * 2e9 + (2e9 - reachedAtUnix),
-- written only when the metric improves; the public top 10 cached ~60 s; friends via Players:GetFriendsAsync,
-- capped at 200, fetched only on demand, cached, pcall'd and throttle-safe; a physical board near spawn with a
-- ProximityPrompt that toggles Public/Friends; names resolved and cached, never stored; an empty friends board
-- says something useful.
--
-- What the game had before (review of 2026-09-30): a top-10 HUD panel on RAW totalDust, SetAsync on every
-- autosave (30 writes in 10 idle minutes with the metric unchanged), names looked up again by the client on every
-- 30-s refresh, no friends view, no physical board, no tie-break.
--
-- Driven through the REAL server (and the real HUD for the panel). The emulator has no Players:GetFriendsAsync,
-- so this file supplies one (FriendPages-shaped: GetCurrentPage / IsFinished / AdvanceToNextPageAsync) and counts
-- the calls; it also counts every call the server makes to the board's store and to GetNameFromUserIdAsync.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players

-- saved profiles, before the server starts
local profiles = DSS:GetDataStore("GrowCrystal_v1")
local function seed(uid, d)
	local data = { dust = 50, seeds = { [1] = 3 }, chambers = 1, luckLevel = 0, growthLevel = 0,
		plants = {}, codex = {}, redeemed = {}, lastGeodeWeek = -1, totalDust = 0, passes = {} }
	for k, v in d do data[k] = v end
	profiles:SetAsync("u_" .. uid, { data = data })
end
local T_ADA, T_BO = 1780000000, 1770000000
seed(601, { totalDust = 250000, boardAt = T_ADA, plants = { ["1"] = { tier = 6, at = 1 } } }) -- Ada, a ripe Mythic waiting
seed(602, { totalDust = 250050, boardAt = T_BO })   -- Bo: the SAME 2500 points, reached earlier
seed(603, { totalDust = 90000 })                     -- saved before 2026-09-30: no boardAt

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Board = h:_require(RS:FindFirstChild("Board"))
local bc = Config.Board
truthy(type(bc) == "table" and type(Board) == "table", "Config.Board and the Board module exist")
if type(bc) ~= "table" or type(Board) ~= "table" then
	print(string.format("growacrystal board: %d passed, %d failed", passed, failed))
	error("no board to check", 0)
end

local lb = DSS:GetOrderedDataStore(Config.Save.Leaderboard)
eq(Config.Save.Leaderboard, "GrowCrystal_LB_v2", "the board's own store (v1 held raw totalDust)")
-- miners who are not on this server
local T_OLD = 1760000000
lb:SetAsync("u_605", Board.encode(5000, T_OLD, bc))
lb:SetAsync("u_604", Board.encode(40, T_OLD, bc))
lb:SetAsync("u_608", Board.encode(3, T_OLD, bc))

-- count what the server does to the board's store
local writes, sorted, reads = 0, 0, {}
do
	local oUpdate, oSet, oSorted, oGet = lb.UpdateAsync, lb.SetAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; return oSet(self, ...) end
	lb.GetSortedAsync = function(self, ...) sorted += 1; return oSorted(self, ...) end
	lb.GetAsync = function(self, key, ...) table.insert(reads, key); return oGet(self, key, ...) end
end
local nameCalls = {}
do
	-- a method of Players, so the emulator refuses a plain assignment; rawset shadows it for this run only
	local oName = Players.GetNameFromUserIdAsync
	rawset(Players, "GetNameFromUserIdAsync", function(self, uid, ...)
		nameCalls[uid] = (nameCalls[uid] or 0) + 1
		return oName(self, uid, ...)
	end)
end

-- friends, per user id: a list of { Id, Username } (or "error")
local friendsOf = {
	[601] = { { 602, "Bo" }, { 604, "Cy" }, { 605, "Dee" }, { 606, "Eve" } },
	[610] = {},
	[612] = "error",
}
do
	local big = {}
	for i = 1, 450 do table.insert(big, { 20000 + i, "Pal" .. i }) end
	friendsOf[613] = big
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

local R = RS:FindFirstChild("CrystalRemotes")
local Toast, LB = R:FindFirstChild("Toast"), R:FindFirstChild("Leaderboard")

local function boardOf(uid)
	local pad = h.workspace:FindFirstChild("Spawn_" .. uid, true)
	local folder = pad and pad.Parent
	return folder and folder:FindFirstChild("Leaderboard"), pad
end
local function textOf(board)
	local out = {}
	local gui = board and board:FindFirstChild("BoardGui")
	if not gui then return out end
	for _, d in gui:GetDescendants() do
		if d:IsA("TextLabel") then out[d.Name] = d.Text end
	end
	return out
end
local function rowsText(board)
	local t = textOf(board)
	local rows = {}
	for i = 1, bc.PublicRows do
		local s = t["Row" .. i]
		if s and s ~= "" then table.insert(rows, s) end
	end
	return rows, t
end
local function has(s, needle) return s ~= nil and string.find(s, needle, 1, true) ~= nil end

--======================================================================= 1. the board in the world, near spawn

h.game:GetService("RunService"):setIsServer(false)
local ada = h:join("Ada", 601)
assert(h:tryRun("client/Hud.client")) -- Ada's HUD: its panel draws what the server sends
h:advance(1)
local board, pad = boardOf(601)
truthy(board ~= nil and board:IsA("BasePart"), "Ada's cavern has a physical board (Plot_*.Leaderboard)")
local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt")
truthy(prompt ~= nil, "with a ProximityPrompt")
if board and pad then
	local root = pad.Position + Vector3.new(0, 4, 0) -- where the engine stands a spawning player (check_crystal_spawn)
	local d = (board.Position - root).Magnitude
	truthy(prompt ~= nil and d <= prompt.MaxActivationDistance - 1, string.format(
		"near spawn: %.1f studs from where the player spawns, inside the prompt's %s", d, prompt and tostring(prompt.MaxActivationDistance) or "?"))
	local gui = board:FindFirstChild("BoardGui")
	truthy(gui ~= nil and gui:IsA("SurfaceGui"), "the board is drawn on a SurfaceGui")
	-- the drawn face points at the spawn: Back is the part's +Z face, and the spawn is at +Z of the board
	local look, right = board.CFrame.LookVector, board.CFrame.RightVector
	truthy(math.abs(look.Z + 1) < 1e-6 and math.abs(right.X - 1) < 1e-6, "the board is not rotated")
	eq(gui and gui.Face, Enum.NormalId.Back, "so its drawn face is +Z")
	truthy(root.Z > board.Position.Z + board.Size.Z / 2, "and the spawn is in front of that face")
	eq(board.Anchored, true, "the board is anchored")
end
if prompt then
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
	eq(prompt.ActionText, bc.Text.ShowFriends, "it offers the friends view first")
end
eq(friendCalls[601], nil, "friends are fetched ON DEMAND: not at join")

--======================================================================= 2. stored value, ties, legacy, write only when it improves

local bo = h:join("Bo", 602)
local legacy = h:join("Legacy", 603)
h:advance(1)
local tJoin = os.time()
h:advance(Config.Save.AutosaveSeconds + 1) -- one autosave
local function stored(uid) return lb:GetAsync("u_" .. uid) end
eq(stored(601), Board.encode(2500, T_ADA, bc), "Ada's value: 2500 points, reached at her saved time")
eq(stored(602), Board.encode(2500, T_BO, bc), "Bo's value: the same 2500 points, reached earlier")
truthy((stored(602) or 0) > (stored(601) or 0), "so Bo, who got there first, ranks above Ada")
do
	local m, t = Board.decode(stored(603) or 0)
	eq(m, 900, "a profile from before the board is written at its next save (900 points)")
	truthy(math.abs(t - tJoin) <= 5, "stamped with that session as the time reached (" .. tostring(t - tJoin) .. " s off)")
end
do
	local rec = profiles:GetAsync("u_602")
	eq(rec and rec.data and rec.data.boardAt, T_BO, "the profile keeps WHEN the points were reached (the tie-break survives a rejoin)")
end
local writesAfterFirst = writes
eq(writesAfterFirst, 3, "the first autosave wrote each of the three players once")

-- ten idle minutes: the reviewer measured 30 writes here with the metric unchanged
for _ = 1, 30 do h:advance(20) end
eq(writes - writesAfterFirst, 0, "10 idle minutes, points unchanged: no board write at all")
do
	-- the board is written only AFTER a profile save lands (a session that lost its record writes nothing), so the
	-- profile learns the written points one save later
	local rec = profiles:GetAsync("u_602")
	eq(rec and rec.data and rec.data.boardMetric, 2500, "the profile keeps the points last written to the board (no rewrite after a rejoin)")
end
truthy(sorted >= 9 and sorted <= math.ceil(600 / bc.PublicCacheSeconds) + 2, string.format(
	"the public top 10 is read about once a minute (%d GetSortedAsync in %d s)", sorted, 600 + Config.Save.AutosaveSeconds + 3))

-- a harvest that earns points is written, once, stamped with its own time
do
	local sock = h.workspace:FindFirstChild("Socket_601_1", true)
	local crystal = sock and sock:FindFirstChild("Crystal")
	truthy(crystal ~= nil, "Ada's ripe Mythic is on socket 1")
	local before = writes
	local tHarvest = os.time()
	if crystal then crystal:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(ada) end
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(writes - before, 1, "the harvest raised Ada's points: exactly one write")
	local m, t = Board.decode(stored(601) or 0)
	truthy(m >= 2515, "her stored points rose by at least a Mythic's 1500 dust (" .. m .. ")")
	truthy(math.abs(t - tHarvest) <= 5, "reached at the harvest (" .. tostring(t - tHarvest) .. " s off), not at the old time")
end

-- dust from a code is not dust EARNED: the board does not move
do
	local s0 = stored(601)
	local before = writes
	local res = R:FindFirstChild("Redeem"):simulateInvokeServer(ada, "CRYSTAL")
	truthy(res and res.ok, "the CRYSTAL code redeems (+500 dust)")
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(stored(601), s0, "a code's 500 dust does not raise the board (it ranks dust earned from harvests)")
	eq(writes - before, 0, "and costs no board write")
end

--======================================================================= 3. the public board, drawn

h:advance(bc.PublicCacheSeconds + 1)
do
	local rows, t = rowsText(board)
	truthy(has(t.Title, bc.Text.Title), "the board says what it is (" .. tostring(t.Title) .. ")")
	truthy(has(t.Mode, bc.Text.Everyone), "and which view it shows (" .. tostring(t.Mode) .. ")")
	eq(#rows, 6, "six miners on the board (605, Ada, Bo, Legacy, 604, 608)")
	truthy(has(rows[1], "1.") and has(rows[1], "User_605") and has(rows[1], Board.formatScore(5000, bc)),
		"row 1: the offline miner with 5000 points, by name, as dust (" .. tostring(rows[1]) .. ")")
	truthy(has(rows[2], "Ada"), "row 2: Ada, whose harvest put her ahead (" .. tostring(rows[2]) .. ")")
	truthy(has(rows[3], "Bo") and has(rows[3], Board.formatScore(2500, bc)), "row 3: Bo (" .. tostring(rows[3]) .. ")")
	truthy(has(rows[4], "Legacy"), "row 4: Legacy (" .. tostring(rows[4]) .. ")")
end
-- the tie itself, drawn: Bo's board shows Bo above... Ada is ahead now, so check the tie on a fresh pair below
do
	-- two offline miners on the same points: the one who got there first is drawn first
	lb:SetAsync("u_620", Board.encode(2000, T_OLD + 100, bc))
	lb:SetAsync("u_621", Board.encode(2000, T_OLD, bc))
	h:advance(bc.PublicCacheSeconds + 1)
	local rows = rowsText(board)
	local at620, at621 = 0, 0
	for i, r in rows do
		if has(r, "User_620") then at620 = i end
		if has(r, "User_621") then at621 = i end
	end
	truthy(at621 > 0 and at620 > 0 and at621 < at620, string.format(
		"a tie on points is drawn earliest-first (the first to 2000 is row %d, the later one row %d)", at621, at620))
end

-- the HUD panel gets the same rows, names included, and never looks a name up itself
do
	local sent = LB:sentTo(ada)
	local last = sent[#sent] and sent[#sent].args[1]
	truthy(type(last) == "table" and #last >= 6, "the HUD panel is sent the public rows")
	local first = last and last[1]
	truthy(first ~= nil and first.name == "User_605" and first.score == Board.formatScore(5000, bc) and first.rank == 1,
		"each row carries its rank, name and score (" .. tostring(first and first.name) .. " " .. tostring(first and first.score) .. ")")
	local drawn = nil
	for _, d in ada.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "^1%. ") then drawn = d.Text end
	end
	truthy(has(drawn, "User_605") and has(drawn, Board.formatScore(5000, bc)), "Ada's HUD panel draws row 1 by name (" .. tostring(drawn) .. ")")
	local hud = h.bundle["client/Hud.client"]
	truthy(hud ~= nil and string.find(hud.source, "GetNameFromUserIdAsync", 1, true) == nil,
		"the HUD no longer looks names up (it did, every 30 s, with no cache)")
end
-- names are cached: a dozen public refreshes cost one lookup per unknown miner
eq(nameCalls[605], 1, "the offline miner's name was looked up once, not on every refresh")
eq(nameCalls[601], nil, "a player on this server needs no lookup at all")

--======================================================================= 4. the friends view

do
	local readsBefore = #reads
	local lookupsBefore = 0
	for _, n in nameCalls do lookupsBefore += n end
	local t0 = #Toast:sentTo(bo)
	prompt.Triggered:Fire(bo)
	h:advance(0.5)
	local toasts = Toast:sentTo(bo)
	truthy(#toasts > t0 and has(tostring(toasts[#toasts].args[1]), "another miner"),
		"someone else's prompt is refused with a reason, not silently")
	eq(prompt.ActionText, bc.Text.ShowFriends, "and it changed nothing")

	prompt.Triggered:Fire(ada)
	h:advance(3)
	eq(friendCalls[601], 1, "Ada's friends are fetched once, when she asks")
	eq(prompt.ActionText, bc.Text.ShowEveryone, "the prompt now offers the public view back")
	local rows, t = rowsText(board)
	truthy(has(t.Mode, bc.Text.Friends), "the board says FRIENDS (" .. tostring(t.Mode) .. ")")
	eq(#rows, 4, "Ada and the three friends who have points (Eve has none)")
	truthy(has(rows[1], "Dee") and has(rows[1], Board.formatScore(5000, bc)), "row 1: Dee, named from the friends list (" .. tostring(rows[1]) .. ")")
	truthy(has(rows[2], "Ada") and has(string.lower(rows[2]), "you"), "row 2: Ada herself, marked (" .. tostring(rows[2]) .. ")")
	truthy(has(rows[3], "Bo"), "row 3: Bo, who is on this server (" .. tostring(rows[3]) .. ")")
	truthy(has(rows[4], "Cy"), "row 4: Cy (" .. tostring(rows[4]) .. ")")
	eq(t.Note or "", "", "every friend checked and some have points: no note")
	local keys = {}
	for i = readsBefore + 1, #reads do keys[reads[i]] = true end
	truthy(keys.u_604 and keys.u_605 and keys.u_606, "the offline friends' values were read from the store")
	truthy(not keys.u_602 and not keys.u_601, "Bo (on this server) and Ada herself were not: their live points are used")
	local lookupsAfter = 0
	for _, n in nameCalls do lookupsAfter += n end
	eq(lookupsAfter - lookupsBefore, 0, "no name lookups for the friends view: the friends list carries their names")

	-- back to public and to friends again: the list and the scores are cached
	local readsMid = #reads
	prompt.Triggered:Fire(ada)
	h:advance(0.5)
	truthy(has(textOf(board).Mode, bc.Text.Everyone), "tapped again: back to everyone")
	prompt.Triggered:Fire(ada)
	h:advance(2)
	eq(friendCalls[601], 1, "friends again within the cache: no second GetFriendsAsync")
	eq(#reads - readsMid, 0, "and no second read of their scores")
	eq(#rowsText(board), 4, "the same four rows")
end

-- the empty and failing cases each say something useful
local function friendsBoard(name, uid, wait)
	local plr = h:join(name, uid)
	h:advance(1)
	local b = boardOf(uid)
	local p = b and b:FindFirstChildWhichIsA("ProximityPrompt")
	if p then p.Triggered:Fire(plr) end
	h:advance(wait or 3)
	return plr, b, p
end
do
	local _, b = friendsBoard("Loner", 610)
	local rows, t = rowsText(b)
	eq(t.Note, bc.Text.NoFriends, "no friends: the board says how friends show up")
	eq(#rows, 0, "and a player with no points yet has no row of their own")

	local _, b2, p2 = friendsBoard("Unlucky", 612)
	eq(textOf(b2).Note, bc.Text.FriendsFailed, "GetFriendsAsync failing: the board says so, and to try again")
	eq(friendCalls[612], 1, "one call")
	if p2 then
		p2.Triggered:Fire(h.Players:GetPlayerByUserId(612)); h:advance(0.5)
		p2.Triggered:Fire(h.Players:GetPlayerByUserId(612)); h:advance(1)
	end
	eq(friendCalls[612], 1, "tapping again at once does not hammer GetFriendsAsync")
	h:advance(bc.FriendsRetrySeconds + 1)
	if p2 then
		p2.Triggered:Fire(h.Players:GetPlayerByUserId(612)); h:advance(0.5)
		p2.Triggered:Fire(h.Players:GetPlayerByUserId(612)); h:advance(1)
	end
	eq(friendCalls[612], 2, "after Config.Board.FriendsRetrySeconds it tries again")
	truthy(#h:errors() == 0, "a failing GetFriendsAsync raises nothing on the server")
end
do
	local readsBefore = #reads
	local _, b = friendsBoard("Popular", 613, 10)
	local t = textOf(b)
	eq(pagesAdvanced, 3, "450 friends: pages are read only until 200 (4 pages of 50, 3 advances)")
	truthy(has(t.Note, "of 200"), "the board counts to the cap of 200 (" .. tostring(t.Note) .. ")")
	local n = #reads - readsBefore
	truthy(n <= bc.ReadsBurst + bc.ReadsPerSecond * 11 + 1, string.format(
		"reads are throttled: %d in the first ~11 s (burst %d + %g/s)", n, bc.ReadsBurst, bc.ReadsPerSecond))
	truthy(n >= bc.ReadsBurst, "and not stalled (" .. n .. ")")
	h:advance(200)
	local t2 = textOf(b)
	eq(t2.Note, string.format(bc.Text.FriendsNoScores, 200), "all 200 checked, none has points: the board says so")
end

--======================================================================= 5. failures and what is never stored

do
	lb.__failNext = true
	h:advance(bc.PublicCacheSeconds + 1)
	truthy(#h:errors() == 0, "a failing GetSortedAsync raises nothing")
	truthy(#rowsText(boardOf(602)) >= 6, "and the board keeps the rows it had")
end
do
	local ok = true
	for k in lb.__data do
		if not string.match(k, "^u_%d+$") then ok = false end
	end
	truthy(ok, "every board key is u_<userId>")
	local rec = profiles:GetAsync("u_601")
	local blob = ""
	local function walk(v)
		if type(v) == "string" then blob ..= v .. "|" elseif type(v) == "table" then for kk, vv in v do walk(kk); walk(vv) end end
	end
	walk(rec)
	truthy(not has(blob, "Ada") and not has(blob, "Dee") and not has(blob, "Bo|"), "no name is stored in a profile")
end

truthy(#h:errors() == 0, "no server errors in the whole run" .. (if #h:errors() > 0 then " (" .. tostring(h:errors()[1]) .. ")" else ""))

print(string.format("growacrystal board: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal board failed", 0) end
