-- Lost & Found Depot — the highscore board, public + friends. Run: luau check_lostfounddepot_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot
-- inflate, ties to whoever reached it FIRST; OrderedDataStore key u_<userId>, value metric * 2e9 +
-- (2e9 - reachedAtUnix), written only when the metric improves; the public top 10 cached ~60 s; friends via
-- Players:GetFriendsAsync, capped at 200, fetched only on demand, cached, pcall'd and throttle-safe; a
-- physical board near spawn with a ProximityPrompt that toggles Public/Friends; names resolved and cached,
-- never stored; an empty friends board says something useful.
--
-- The metric is PERFECT SHIFTS that the server's travel ledger (Ledger.luau, DESIGN.md §10.3) found
-- physically possible. So this file plays real shifts through the real server, the way a player does (the
-- rendered tags, the memo board, the bin signs, the public manual; see check_lostfounddepot.luau): one walked
-- at the character's WalkSpeed, which must count, and one that teleports between the tray and the bins, which
-- is still a Perfect Shift for the player but must not count on the board, and must say so.
--
-- The emulator has no Players:GetFriendsAsync, so this file supplies one (FriendPages-shaped: GetCurrentPage /
-- IsFinished / AdvanceToNextPageAsync) and counts the calls; it also counts every call the server makes to the
-- board's store and to GetNameFromUserIdAsync (after grow-a-crystal's check_growacrystal_board.luau).

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function has(s, needle) return s ~= nil and string.find(s, needle, 1, true) ~= nil end

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-board", viewport = { 800, 360 }, touch = true })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") and h.modules[key] == nil then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
-- the salt, pinned per call (CLAUDE.md traps): the same depot every run, consecutive shifts independent
local realRandom = Random
local unseeded = 0
Random = { new = function(seed)
	if seed == nil then unseeded += 1; return realRandom.new(8100 + unseeded * 7919) end
	return realRandom.new(seed)
end }

local DSS = h.services.DataStoreService
local Players = h.Players
local profiles = DSS:GetDataStore("LostFoundDepot_v1")
local function seed(uid, d)
	local data = { v = 1, cash = 500, cartLevel = 3, shoesLevel = 3, shifts = 5, perfects = 3, backlog = 150,
		bestPerfectSeconds = 80, endingSeen = false, redeemed = {} }
	for k, v in d do data[k] = v end
	profiles:SetAsync("u_" .. uid, { data = data })
end
local TELE, ADA, BO, NEWBIE = 8104, 8101, 8102, 8108
local T_ADA, T_BO = 1780000000, 1770000000
seed(TELE, { perfects = 0 })                                  -- a veteran with no counted Perfect Shift yet
seed(ADA, { boardPerfects = 3, boardAt = T_ADA })             -- 3 counted
seed(BO, { shifts = 6, boardPerfects = 3, boardAt = T_BO })   -- the SAME 3, reached earlier

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Rules = h:_require(RS:FindFirstChild("Rules"))
local Board = RS:FindFirstChild("Board") and h:_require(RS:FindFirstChild("Board"))
local bc = Config.Board
truthy(type(bc) == "table" and type(Board) == "table", "Config.Board and the Board module exist")
if type(bc) ~= "table" or type(Board) ~= "table" then
	print(string.format("lost-found-depot board: %d passed, %d failed", passed, failed))
	error("no board to check", 0)
end

local lb = DSS:GetOrderedDataStore(bc.Store)
-- sorters who are not on this server
local T_OLD = 1760000000
lb:SetAsync("u_8105", Board.encode(50, T_OLD, bc))
lb:SetAsync("u_8106", Board.encode(2, T_OLD, bc))
lb:SetAsync("u_8107", Board.encode(1, T_OLD, bc))

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
	[ADA] = { { BO, "Bo" }, { 8106, "Cy" }, { 8105, "Dee" }, { 8109, "Eve" } },
	[8110] = {},
	[8112] = "error",
}
do
	local big = {}
	for i = 1, 450 do table.insert(big, { 20000 + i, "Pal" .. i }) end
	friendsOf[8113] = big
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

local remotes = RS:FindFirstChild("DepotRemotes")
local StateEvent, NoticeEvent = remotes.State, remotes.Notice
local function state(plr)
	local s = StateEvent:sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local function toasts(plr)
	local out = {}
	for _, r in NoticeEvent:sentTo(plr) do table.insert(out, r.args[1]) end
	return out
end
local function boardOf(plr)
	local bay = plr.RespawnLocation and plr.RespawnLocation.Parent
	return bay and bay:FindFirstChild("Leaderboard"), bay
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
local function promptOf(board) return board and board:FindFirstChildWhichIsA("ProximityPrompt") end

--======================================================================= playing a shift the way a player does

local BIN_OF_NAME, LETTER_OF_NAME = {}, {}
for id, name in Config.Rules.BinNames do BIN_OF_NAME[name] = id end
for _, it in Config.Catalog do LETTER_OF_NAME[it.name] = it.letter end

-- mode "walk": every leg takes distance / WalkSpeed (a straight line, the fastest an honest player can be);
-- mode "teleport": every action 0.25 s after the last (the action bucket's 5 a second), wherever it is.
local function playShift(plr, mode)
	local bay = plr.RespawnLocation.Parent
	local ox = bay.BayPad.Position.X
	local P = Vector3.new(ox, 3, 0)
	local hrp = plr.Character.HumanoidRootPart
	local function go(pos)
		local d = (hrp.Position - pos).Magnitude
		hrp.CFrame = CFrame.new(pos)
		if mode == "walk" then h:advance(d / plr.Character.Humanoid.WalkSpeed) else h:advance(0.25) end
	end
	local function bins()
		local out = {}
		for k = 1, 6 do
			local m = bay:FindFirstChild("Bin_" .. k)
			out[BIN_OF_NAME[m.Sign.SignGui.Label.Text]] = m
		end
		return out
	end
	local function readRules()
		local text = bay.MemoBoard.SignGui.Label.Text
		for _, memo in Rules.memos(Config) do
			if string.find(text, Rules.memoLine(Config, memo), 1, true) then return Rules.withMemo(Config, memo) end
		end
		return Rules.base(Config)
	end
	local function answerOf(entry)
		local mis = string.match(entry.tag, "^MISFILED %- goes to (.+)$")
		if mis then return BIN_OF_NAME[mis] end
		return (Rules.resolve(Config, Rules.parseTag(Config, entry.tag), LETTER_OF_NAME[entry.name], readRules()))
	end
	for _ = 1, 600 do
		local st = state(plr)
		if st.shift.state == "SUMMARY" then return st end
		if #st.shift.carried == 0 then
			go(P)
			local n = 0
			for s = 1, 8 do
				local slot = bay:FindFirstChild("Slot_" .. s)
				if n < st.carry and slot.Tag.Enabled then
					slot.Item.ClickDetector.MouseClick:Fire(plr)
					n += 1
					if mode == "teleport" then h:advance(0.25) end
				end
			end
			h:advance(0.35)
		else
			local bin = bins()[answerOf(st.shift.carried[1])]
			local base = bin.Base.Position
			local flat = Vector3.new(base.X, 3, base.Z)
			go(flat + (P - flat).Unit * 5)
			bin.Base.Drop.Triggered:Fire(plr)
		end
	end
	return state(plr)
end

--======================================================================= 1. a teleporting Perfect Shift does not count

local function plr_walk(plr) return plr.Character.Humanoid.WalkSpeed end

h.game:GetService("RunService"):setIsServer(false)
local tele = h:join("Tele", TELE)
assert(h:tryRun("client/Hud.client")) -- Tele's HUD, to read the summary card he is shown
h:advance(0.2)
h.Players:simulateSpawn(tele, h.workspace)
h:advance(1)
do
	local before = state(tele)
	local st = playShift(tele, "teleport")
	local s = st.shift.summary
	eq(s and s.perfect, true, "teleporting: the shift is still a Perfect Shift for the player")
	eq(st.perfects, before.perfects + 1, "... it counts among his Perfect Shifts")
	eq(s and s.bonus, Config.Economy.PerfectBonus, "... and pays the Perfect bonus")
	eq(s and s.counted, false, "but it is NOT counted on the board: the ledger saw him outrun his shoes")
	eq(s and s.boardPerfects, 0, "his board count stays 0")
	local card = tele.PlayerGui.DepotHud.Root.SummaryCard
	truthy(card.Visible and has(card.Body.Text, bc.Text.NotCounted),
		"his summary card says why (" .. string.gsub(card.Body.Text, "\n", " | ") .. ")")
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(lb.__data["u_" .. TELE], nil, "and nothing reaches the board store for him")
	eq(writes, 0, "no board write at all")
	local rec = profiles:GetAsync("u_" .. TELE)
	eq(rec and rec.data and rec.data.perfects, 1, "his profile keeps the Perfect Shift")
	eq(rec and rec.data and rec.data.boardPerfects, 0, "and a board count of 0")
end

--======================================================================= 2. the board in the world, near spawn

local ada = h:join("Ada", ADA)
h:advance(0.2)
h.Players:simulateSpawn(ada, h.workspace)
h:advance(1)
local board, bay = boardOf(ada)
local prompt = promptOf(board)
truthy(board ~= nil and board:IsA("BasePart"), "Ada's bay has a physical board (Bay_*.Leaderboard)")
truthy(prompt ~= nil, "with a ProximityPrompt")
if board and bay and prompt then
	local pad = bay:FindFirstChild("BayPad")
	local root = pad.Position + Vector3.new(0, pad.Size.Y / 2 + 2.51, 0) -- where the engine stands a spawning player
	local d = (board.Position - root).Magnitude
	truthy(d <= 20, string.format("near spawn: %.1f studs from where the player spawns", d))
	truthy(d > prompt.MaxActivationDistance, string.format(
		"its prompt is out of reach from the pad (%.1f > %s): nothing pops up over the first tap", d, tostring(prompt.MaxActivationDistance)))
	-- a few steps toward it, standing on the floor in front of the board
	local front = Vector3.new(board.Position.X, 3, board.Position.Z - 4)
	truthy((board.Position - front).Magnitude <= prompt.MaxActivationDistance, "and in reach 4 studs in front of the board")
	local walk = (Vector3.new(front.X, 0, front.Z) - Vector3.new(root.X, 0, root.Z)).Magnitude
	truthy(walk <= 16, string.format("which is a %.1f-stud walk from the spawn", walk))
	local gui = board:FindFirstChild("BoardGui")
	truthy(gui ~= nil and gui:IsA("SurfaceGui"), "the board is drawn on a SurfaceGui")
	local look = board.CFrame.LookVector
	truthy(math.abs(look.Z + 1) < 1e-6, "the board is not rotated")
	eq(gui and gui.Face, Enum.NormalId.Front, "its drawn face is -Z, into the bay")
	truthy(pad.Position.Z < board.Position.Z - board.Size.Z / 2, "and the pad is in front of that face")
	eq(board.Anchored, true, "the board is anchored")
	eq(board.CanCollide, false, "and not collidable: nothing decorative is a ledge (DESIGN.md §4.2)")
	eq(board.Transparency, 1, "one-sided like every board here: an invisible part, the SurfaceGui draws it")
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
	eq(prompt.ActionText, bc.Text.ShowFriends, "it offers the friends view first")
	-- it stays inside the bay, off the other boards on that wall
	local ox = pad.Position.X
	local minX, maxX = board.Position.X - board.Size.X / 2 - ox, board.Position.X + board.Size.X / 2 - ox
	local minY, maxY = board.Position.Y - board.Size.Y / 2, board.Position.Y + board.Size.Y / 2
	truthy(minX >= Config.Bay.MinX and maxX <= Config.Bay.MaxX and minY >= 0 and maxY <= Config.Bay.WallHeight,
		string.format("inside the bay's wall (x %.1f..%.1f, y %.1f..%.1f)", minX, maxX, minY, maxY))
	local name = bay:FindFirstChild("NameSign")
	local nMinX, nMaxX = name.Position.X - name.Size.X / 2 - ox, name.Position.X + name.Size.X / 2 - ox
	local nMinY = name.Position.Y - name.Size.Y / 2
	truthy(maxX <= nMinX or minX >= nMaxX or maxY <= nMinY, "clear of the bay's name sign on the same wall")
	-- the wing's name on this wall (WingArt wingSigns): x 13..31, y 11..14, bay-local
	truthy(maxX <= 13 or minX >= 31 or maxY <= 11, "clear of the wing's name sign on the same wall")
	local lk = bay:FindFirstChild("Locker")
	truthy(math.abs(board.Position.X - lk.Position.X) > (board.Size.X + lk.Size.X) / 2,
		"and not over the locker")
end
eq(friendCalls[ADA], nil, "friends are fetched ON DEMAND: not at join")
do
	local n, blankFree = 0, true
	for _, b in h.workspace:FindFirstChild("Bays"):GetChildren() do
		local lbPart = b:FindFirstChild("Leaderboard")
		if lbPart then
			n += 1
			local owned = false
			for _, p in Players:GetPlayers() do
				if p.RespawnLocation and p.RespawnLocation.Parent == b then owned = true end
			end
			if not owned then
				for _, r in rowsText(lbPart) do if r ~= "" then blankFree = false end end
			end
		end
	end
	eq(n, #h.workspace:FindFirstChild("Bays"):GetChildren(), "every bay has its board")
	truthy(blankFree, "a free bay's board shows no rows")
end

--======================================================================= 3. stored value, ties, write only when it improves

local bo = h:join("Bo", BO)
h:advance(0.2)
h.Players:simulateSpawn(bo, h.workspace)
h:advance(1)
h:advance(Config.Save.AutosaveSeconds + 1) -- one autosave
-- read straight from the emulated store: never through the counted (and failable) GetAsync
local function stored(uid) return lb.__data["u_" .. uid] end
eq(stored(ADA), Board.encode(3, T_ADA, bc), "Ada's value: 3 counted Perfect Shifts, reached at her saved time")
eq(stored(BO), Board.encode(3, T_BO, bc), "Bo's value: the same 3, reached earlier")
truthy((stored(BO) or 0) > (stored(ADA) or 0), "so Bo, who got there first, ranks above Ada")
local writesAfterFirst = writes
eq(writesAfterFirst, 2, "the first autosave wrote each of the two players once")
for _ = 1, 30 do h:advance(20) end
eq(writes - writesAfterFirst, 0, "10 idle minutes, count unchanged: no board write at all")
truthy(sorted >= 9 and sorted <= math.ceil(660 / bc.PublicCacheSeconds) + 2, string.format(
	"the public top 10 is read about once a minute (%d GetSortedAsync in about 11 minutes)", sorted))

--======================================================================= 4. a walked Perfect Shift counts

do
	local before = writes
	local st = playShift(ada, "walk")
	local tEnd = os.time()
	local s = st.shift.summary
	eq(s and s.perfect, true, "walking at her WalkSpeed, Ada sorts a Perfect Shift")
	-- what the board ranks is bounded by walking, not by reading: a script that reads the public manual and walks
	-- straight lines at WalkSpeed is what this is (zero reading time, carry 5, walk 22). Printed for CLAUDE.md.
	print(string.format("   a walked Perfect Shift with zero reading time (carry %d, walk %d): %s s on the server's clock",
		st.carry, plr_walk(ada), tostring(s and s.seconds)))
	eq(s and s.counted, true, "it counts on the board")
	eq(s and s.boardPerfects, 4, "her board count is 4")
	h:advance(1)
	eq(writes - before, 1, "one board write, when the shift-end save landed")
	local m, t = Board.decode(stored(ADA) or 0)
	eq(m, 4, "her stored count is 4")
	truthy(math.abs(t - tEnd) <= 5, "reached at the end of that shift (" .. tostring(t - tEnd) .. " s off), not at the old time")
	local rec = profiles:GetAsync("u_" .. ADA)
	eq(rec and rec.data and rec.data.boardPerfects, 4, "the profile keeps the count")
	truthy(rec and rec.data and math.abs((rec.data.boardAt or 0) - tEnd) <= 5,
		"and WHEN it was reached (the tie-break survives a rejoin)")
	local notCounted = 0
	for _, n in toasts(ada) do if has(n.text, bc.Text.NotCounted) then notCounted += 1 end end
	eq(notCounted, 0, "an honest shift is never told it did not count")
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(writes - before, 1, "and the next autosave writes nothing more")
end

--======================================================================= 5. the public board, drawn

h:advance(bc.PublicCacheSeconds + 1)
do
	local rows, t = rowsText(board)
	truthy(has(t.Title, "TOP SORTERS"), "the board says what it is (" .. tostring(t.Title) .. ")")
	truthy(has(t.Mode, bc.Text.Everyone) and has(t.Mode, bc.Text.Subtitle), "and which view, of what (" .. tostring(t.Mode) .. ")")
	eq(#rows, 5, "five sorters on the board (8105, Ada, Bo, 8106, 8107): Tele has none counted")
	truthy(has(rows[1], "1.") and has(rows[1], "User_8105") and has(rows[1], "50"), "row 1: the offline sorter with 50, by name (" .. tostring(rows[1]) .. ")")
	truthy(has(rows[2], "Ada") and has(rows[2], "4"), "row 2: Ada, whose counted shift put her ahead (" .. tostring(rows[2]) .. ")")
	truthy(has(rows[3], "Bo") and has(rows[3], "3"), "row 3: Bo (" .. tostring(rows[3]) .. ")")
	eq(t.Note or "", "", "a board with rows needs no note")
end
do
	-- two offline sorters on the same count: the one who got there first is drawn first
	lb:SetAsync("u_8120", Board.encode(20, T_OLD + 100, bc))
	lb:SetAsync("u_8121", Board.encode(20, T_OLD, bc))
	h:advance(bc.PublicCacheSeconds + 1)
	local rows = rowsText(board)
	local at20, at21 = 0, 0
	for i, r in rows do
		if has(r, "User_8120") then at20 = i end
		if has(r, "User_8121") then at21 = i end
	end
	truthy(at21 > 0 and at20 > 0 and at21 < at20, string.format(
		"a tie is drawn earliest-first (the first to 20 is row %d, the later one row %d)", at21, at20))
	truthy(has(rowsText(boardOf(bo))[1], "User_8105"), "Bo's board shows the same public rows")
end
eq(nameCalls[8105], 1, "the offline sorter's name was looked up once, not on every refresh")
eq(nameCalls[ADA], nil, "a player on this server needs no lookup at all")

--======================================================================= 6. the friends view

do
	local readsBefore = #reads
	local t0 = #toasts(bo)
	prompt.Triggered:Fire(bo)
	h:advance(0.5)
	local ts = toasts(bo)
	truthy(#ts > t0 and ts[#ts].text == bc.Text.NotYours, "someone else's prompt is refused with a reason, not silently")
	eq(prompt.ActionText, bc.Text.ShowFriends, "and it changed nothing")

	prompt.Triggered:Fire(ada)
	h:advance(3)
	eq(friendCalls[ADA], 1, "Ada's friends are fetched once, when she asks")
	eq(prompt.ActionText, bc.Text.ShowEveryone, "the prompt now offers the public view back")
	local rows, t = rowsText(board)
	truthy(has(t.Mode, bc.Text.Friends), "the board says FRIENDS (" .. tostring(t.Mode) .. ")")
	eq(#rows, 4, "Ada and the three friends with a counted Perfect Shift (Eve has none)")
	truthy(has(rows[1], "Dee") and has(rows[1], "50"), "row 1: Dee, named from the friends list (" .. tostring(rows[1]) .. ")")
	truthy(has(rows[2], "Ada") and has(string.lower(rows[2]), "you"), "row 2: Ada herself, marked (" .. tostring(rows[2]) .. ")")
	truthy(has(rows[3], "Bo"), "row 3: Bo, who is on this server (" .. tostring(rows[3]) .. ")")
	truthy(has(rows[4], "Cy"), "row 4: Cy (" .. tostring(rows[4]) .. ")")
	eq(t.Note or "", "", "every friend checked and some have counted shifts: no note")
	local keys = {}
	for i = readsBefore + 1, #reads do keys[reads[i]] = true end
	truthy(keys.u_8106 and keys.u_8105 and keys.u_8109, "the offline friends' values were read from the store")
	truthy(not keys["u_" .. BO] and not keys["u_" .. ADA], "Bo (on this server) and Ada herself were not: their live counts are used")

	local readsMid = #reads
	prompt.Triggered:Fire(ada)
	h:advance(0.5)
	truthy(has(textOf(board).Mode, bc.Text.Everyone), "tapped again: back to everyone")
	prompt.Triggered:Fire(ada)
	h:advance(2)
	eq(friendCalls[ADA], 1, "friends again within the cache: no second GetFriendsAsync")
	eq(#reads - readsMid, 0, "and no second read of their scores")
	eq(#rowsText(board), 4, "the same four rows")
end

local function friendsBoard(name, uid, wait)
	local plr = h:join(name, uid)
	h:advance(0.2)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(1)
	local b = boardOf(plr)
	local p = promptOf(b)
	if p then p.Triggered:Fire(plr) end
	h:advance(wait or 3)
	return plr, b, p
end
do
	local _, b = friendsBoard("Loner", 8110)
	local rows, t = rowsText(b)
	eq(t.Note, bc.Text.NoFriends, "no friends: the board says how friends show up")
	eq(#rows, 0, "and a new player with no counted Perfect Shift has no row of their own yet")
end
do
	local _, b2, p2 = friendsBoard("Unlucky", 8112)
	eq(textOf(b2).Note, bc.Text.FriendsFailed, "GetFriendsAsync failing: the board says so, and to try again")
	eq(friendCalls[8112], 1, "one call")
	local who = Players:GetPlayerByUserId(8112)
	if p2 then
		p2.Triggered:Fire(who); h:advance(0.5)
		p2.Triggered:Fire(who); h:advance(1)
	end
	eq(friendCalls[8112], 1, "tapping again at once does not hammer GetFriendsAsync")
	h:advance(bc.FriendsRetrySeconds + 1)
	if p2 then
		p2.Triggered:Fire(who); h:advance(0.5)
		p2.Triggered:Fire(who); h:advance(1)
	end
	eq(friendCalls[8112], 2, "after Config.Board.FriendsRetrySeconds it tries again")
	eq(#h:errors(), 0, "a failing GetFriendsAsync raises nothing on the server")
end
do
	local readsBefore = #reads
	local _, b = friendsBoard("Popular", 8113, 10)
	local t = textOf(b)
	eq(pagesAdvanced, 3, "450 friends: pages are read only until 200 (4 pages of 50, 3 advances)")
	truthy(has(t.Note, "of 200"), "the board counts to the cap of 200 (" .. tostring(t.Note) .. ")")
	local n = #reads - readsBefore
	truthy(n <= bc.ReadsBurst + bc.ReadsPerSecond * 11 + 1, string.format(
		"reads are throttled: %d in the first ~11 s (burst %d + %g/s)", n, bc.ReadsBurst, bc.ReadsPerSecond))
	truthy(n >= bc.ReadsBurst, "and not stalled (" .. n .. ")")
	h:advance(200)
	eq(textOf(b).Note, string.format(bc.Text.FriendsNoScores, 200), "all 200 checked, none counted: the board says so")
end

--======================================================================= 7. leaving, failures, and what is never stored

do
	local newbieBay = nil
	local loner = Players:GetPlayerByUserId(8110)
	local lonerBoard, lonerBay = boardOf(loner)
	h:leave(loner)
	h:advance(1)
	eq(#rowsText(lonerBoard), 0, "a player who leaves takes their rows with them: the freed bay's board is blank")
	eq(promptOf(lonerBoard).ActionText, bc.Text.ShowFriends, "and its prompt is reset to the friends offer")
	local newbie = h:join("Newbie", NEWBIE)
	h:advance(0.2)
	h.Players:simulateSpawn(newbie, h.workspace)
	h:advance(1)
	local nb
	nb, newbieBay = boardOf(newbie)
	eq(newbieBay, lonerBay, "the next player gets the freed bay")
	truthy(has(textOf(nb).Mode, bc.Text.Everyone) and #rowsText(nb) >= 5, "and its board opens on everyone's rows")
end
do
	lb.__failNext = true
	h:advance(bc.PublicCacheSeconds + 1)
	eq(#h:errors(), 0, "a failing GetSortedAsync raises nothing")
	truthy(#rowsText(boardOf(bo)) >= 5, "and the board keeps the rows it had")
end
do
	-- a board write that fails is tried again at the next save, not forgotten
	local before = writes
	lb.__failAll = true
	local st = playShift(bo, "walk")
	eq(st.shift.summary and st.shift.summary.counted, true, "Bo's walked Perfect Shift counts")
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(Board.metricOf(stored(BO)), 3, "while the board store fails, his stored count stays 3")
	lb.__failAll = false
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(Board.metricOf(stored(BO)), 4, "the next save after it recovers writes 4")
	truthy(writes - before >= 2, "(tried while failing, then written)")
	eq(#h:errors(), 0, "a failing board write raises nothing")
end
do
	local ok, allInt = true, true
	for k, v in lb.__data do
		if not string.match(k, "^u_%d+$") then ok = false end
		if type(v) ~= "number" or v % 1 ~= 0 then allInt = false end
	end
	truthy(ok, "every board key is u_<userId>")
	truthy(allInt, "every board value is an integer (an OrderedDataStore takes nothing else)")
	local blob = ""
	local function walk(v)
		if type(v) == "string" then blob ..= v .. "|" elseif type(v) == "table" then for kk, vv in v do walk(kk); walk(vv) end end
	end
	for _, uid in { ADA, BO, TELE } do walk(profiles:GetAsync("u_" .. uid)) end
	truthy(not has(blob, "Ada") and not has(blob, "Dee") and not has(blob, "Bo|") and not has(blob, "Tele"),
		"no name is stored in a profile")
	-- the State payload carries nothing new but the summary's own two fields (check_lostfounddepot's allowlist)
end

truthy(#h:errors() == 0, "no server errors in the whole run" .. (if #h:errors() > 0 then " (" .. tostring(h:errors()[1]) .. ")" else ""))

print(string.format("lost-found-depot board: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot board failed", 0) end
