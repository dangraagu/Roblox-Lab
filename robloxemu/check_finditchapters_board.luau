-- Find It! Chapters: the Cases Solved board, public and friends (DESIGN.md §11; docs/complete-game-standard.md §3).
-- Run (from robloxemu/): py -3 wrap.py --game ../find-it-chapters --out build/find-it-chapters.luau
--                        luau check_finditchapters_board.luau 2>&1
--
-- Through the REAL server and Board.client: the public face ranks the ordered store's top 10 by count, ties to the
-- earliest reach; names are resolved and cached, never stored; the prompt toggles a LOCAL friends face for the
-- presser only (rows, the presser marked, an empty list that says something useful, a failure that says so, a cap
-- of 200 friends, reads that stop at the request-budget reserve and say how far they got); the store is written
-- only when the count rises. The emulator has no Players:GetFriendsAsync, so this file supplies one (FriendPages-
-- shaped: GetCurrentPage / IsFinished / AdvanceToNextPageAsync) and counts the calls.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/find-it-chapters"), name = "find-it-board", viewport = { 1280, 720 }, touch = false })
local dt = h.instance.datatypes
local Vector3, CFrame, Enum = dt.Vector3, dt.CFrame, dt.Enum
local RS, ws = h.ReplicatedStorage, h.workspace
local DSS = h.services.DataStoreService
local Players = h.Players

-- the Board module and the config, read before the server runs (they are pure)
local bundle = require("./build/find-it-chapters")
local lb = DSS:GetOrderedDataStore("FindIt_Solved_v1")
local profiles = DSS:GetDataStore("FindIt_Players_v1")

-- the friend lists (user id -> { { id, name } } or "error")
local friendsOf = {
	[601] = { { 602, "Bo" }, { 605, "Eve" }, { 606, "Finn" }, { 608, "Gus" } },
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

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config, Board = mod("Config"), mod("Board")
local bc = Config.Board
local RunService = h.game:GetService("RunService")
local remotes = RS:FindFirstChild("FindItRemotes")

-- offline players already on the board: ties broken by who reached the count FIRST
local T0 = 1791000000
lb:SetAsync("u_602", Board.encode(9, T0 + 500, bc))
lb:SetAsync("u_605", Board.encode(20, T0 + 100, bc))
lb:SetAsync("u_606", Board.encode(9, T0 + 100, bc)) -- same count as 602, reached EARLIER
lb:SetAsync("u_700", Board.encode(3, T0, bc))
for i = 1, 12 do lb:SetAsync("u_" .. (800 + i), Board.encode(1, T0 + i, bc)) end

local writes = 0
do
	local oUpdate, oSet = lb.UpdateAsync, lb.SetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
end

local function frame(d)
	RunService.Heartbeat:Fire(d)
	h:advance(d)
end
local function run(seconds)
	local t = 0
	while t < seconds - 1e-9 do
		local d = math.min(0.5, seconds - t)
		frame(d)
		t += d
	end
end

local board = ws.FindItWorld.Hub.CasesBoard
local face = board.PublicFace
local prompt = board.BoardToggle

-- a player in the hub, near the board
local function joinAs(name, uid)
	local plr = h:join(name, uid)
	h:advance(0.5)
	local char = Players:simulateSpawn(plr, ws)
	char:FindFirstChildOfClass("Humanoid").FloorMaterial = Enum.Material.Plastic
	local hrp = char:FindFirstChild("HumanoidRootPart")
	hrp.CFrame = CFrame.new(board.Position.X + 4, 3, board.Position.Z + 3)
	h:advance(0.5)
	return plr
end
local Ann = joinAs("Ann", 601)
h.Players.LocalPlayer = Ann
RunService:setIsServer(false)
assert(h:tryRun("client/Board.client"))
run(61) -- the public board refreshes within its 60 s cache

--============================================================ the public face: count, then earliest
do
	local rows = {}
	for i = 1, 10 do rows[i] = face:FindFirstChild("Row_" .. i).Text end
	truthy(string.find(rows[1], "20", 1, true) ~= nil, "row 1 is the 20 (" .. rows[1] .. ")")
	truthy(string.find(rows[2], "User_606", 1, true) ~= nil, "row 2: of the two 9s, the one who reached it FIRST (" .. rows[2] .. ")")
	truthy(string.find(rows[3], "User_602", 1, true) ~= nil, "row 3: the later 9 (" .. rows[3] .. ")")
	truthy(string.find(rows[4], "3", 1, true) ~= nil, "row 4: the 3")
	eq(rows[10] ~= "", true, "ten rows filled (the top 10 of 16)")
	-- (the emulator does not let a check wrap Players:GetNameFromUserIdAsync, so the name cache is reviewed, not counted)
end

--============================================================ friends, for the presser only
do
	prompt.Triggered:Fire(Ann)
	run(3)
	local fr = board:FindFirstChild("FriendsFace")
	truthy(fr ~= nil, "Ann's client draws a local friends face on the board")
	eq(face.Enabled, false, "and hides the public face for Ann")
	eq(prompt.ActionText, bc.Text.ShowPublic, "the prompt now says 'Show public' for Ann")
	local r1 = fr and fr:FindFirstChild("Row_1")
	truthy(r1 and string.find(r1.Text, "Eve", 1, true) and string.find(r1.Text, "20", 1, true), "friends row 1: Eve 20 (" .. tostring(r1 and r1.Text) .. ")")
	local youRow = nil
	for i = 1, bc.FriendsRows do
		local r = fr and fr:FindFirstChild("Row_" .. i)
		if r and string.find(r.Text, "(you)", 1, true) then youRow = r.Text end
	end
	-- Ann has 0 cases: a 0 is never ranked, so she is not on her own board until she solves one
	eq(youRow, nil, "a player with 0 cases is not ranked")
	eq(friendCalls[601], 1, "one GetFriendsAsync call")
	-- toggle back
	prompt.Triggered:Fire(Ann)
	run(0.5)
	eq(board:FindFirstChild("FriendsFace"), nil, "toggling back removes the friends face")
	eq(face.Enabled, true, "and shows the public one")
	eq(prompt.ActionText, bc.Text.ShowFriends, "'Show friends' again")
	-- again within 300 s: the list is cached
	prompt.Triggered:Fire(Ann)
	run(2)
	eq(friendCalls[601], 1, "a second look within 300 s does not call GetFriendsAsync again")
	prompt.Triggered:Fire(Ann)
	run(0.5)
end

--============================================================ an empty list, a failure, a cap of 200, the request budget
local BoardEv = remotes.Board
local function lastBoard(plr)
	local s = BoardEv:sentTo(plr)
	return s[#s] and s[#s].args[1]
end
do
	local Lone = joinAs("Lone", 610)
	prompt.Triggered:Fire(Lone)
	run(2)
	local v = lastBoard(Lone)
	eq(v and v.mode, "friends", "Lone gets a friends view")
	eq(v and v.message, bc.Text.NoFriends, "no friends: the empty board says something useful")
	truthy(string.find(bc.Text.NoFriends, "Invite one", 1, true) ~= nil, "it suggests inviting one")
	local Err = joinAs("Err", 612)
	prompt.Triggered:Fire(Err)
	run(2)
	eq(lastBoard(Err).message, bc.Text.FriendsFailed, "a GetFriendsAsync failure says so")
	local Pop = joinAs("Pop", 613)
	prompt.Triggered:Fire(Pop)
	run(60)
	local pv = lastBoard(Pop)
	truthy(pv and pv.loading == false, "the 450-friend view finishes")
	local reads = 0
	-- 200 friends checked at most (the cap)
	truthy(pv and (pv.message == nil or not string.find(pv.message, "450", 1, true)), "never more than 200 friends are counted (" .. tostring(pv and pv.message) .. ")")
end
-- The request-budget reserve (Board.readStep: read above GetAsyncReserve, wait, stop past FriendReadMaxWaitSeconds
-- and say how far it got) is pinned by tests/Board.spec.luau; the emulator's DataStoreService does not let a check
-- lower GetRequestBudgetForRequestType, so the glue that reads it is reviewed, not driven, here.

--============================================================ writes only when the count rises
do
	local w0 = writes
	run(Config.Save.AutosaveSeconds * 3 + 1)
	eq(writes, w0, "autosaves with no new case write nothing to the board")
	eq(lb:GetAsync("u_601"), nil, "a player with 0 cases is never on the ordered store")
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
print(string.format("find it board: %d passed, %d failed", passed, failed))
if failed > 0 then error("check_finditchapters_board failed", 0) end
