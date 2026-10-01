-- SIGNAL LOST — the RELAYS RESTORED board (public + friends) and the Main Array brag. Run: luau check_signallost_board.luau
-- Regenerate the bundle first: py -3 wrap.py --game ../signal-lost --out build/signal-lost.luau
--
-- docs/complete-game-standard.md §3 and DESIGN.md §10: the metric is relays restored (a server-measured splice a
-- script cannot fake: check_signallost.luau covers the trust); ties go to whoever reached it FIRST; OrderedDataStore
-- key u_<userId>, value best * 2e9 + (2e9 - bestAt), written only when it improves, at most once per 60 s per player
-- plus on leaving; the public top 10 cached ~60 s; friends via Players:GetFriendsAsync, capped at 200, fetched only on
-- demand, cached, budget-gated and throttled; a physical board by the spawn whose prompt toggles Public / Friends;
-- names resolved and cached, never stored; an empty friends board says something useful; a star beside every name
-- that restored the Main Array (relay 30), and the brag itself: the server-wide announcement, arrayAt written once.
-- The emulator has no Players:GetFriendsAsync, so this file supplies one (FriendPages-shaped) and counts the calls.

local Harness = require("./emu/harness")
local Bot = require("../signal-lost/tests/Bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local h = Harness.new({ bundle = require("./build/signal-lost"), name = "signal-lost-board", viewport = { 1280, 720 }, touch = false })
local RSx = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players
local W = h.workspace
local RS = h.game:GetService("RunService")

local profiles = DSS:GetDataStore("SignalLost_v1")
local function seed(uid, d)
	d.v = 1
	d.up = d.up or { tank = 0, boots = 0 }
	profiles:SetAsync("u_" .. uid, { data = d })
end
seed(501, { salvage = 50, best = 12, bestAt = 1780000000 })
seed(502, { salvage = 50, best = 12, bestAt = 1770000000 }) -- reached 12 EARLIER
seed(503, { salvage = 50, best = 29, bestAt = 1785000000, up = { tank = 4, boots = 4 } }) -- one relay from the Main Array
seed(504, { salvage = 0, best = 3, bestAt = 1786000000 })

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RSx:FindFirstChild("Config"))
local Board = h:_require(RSx:FindFirstChild("Board"))
local bc = Config.Board
local lb = DSS:GetOrderedDataStore(bc.Store)
lb:SetAsync("u_505", Board.encode(40, 1760000000, bc)) -- offline players already on the board
lb:SetAsync("u_508", Board.encode(20, 1765000000, bc))

local writes, sorted, reads = 0, 0, {}
do
	local oUpdate, oSet, oSorted, oGet = lb.UpdateAsync, lb.SetAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; return oSet(self, ...) end
	lb.GetSortedAsync = function(self, ...) sorted += 1; return oSorted(self, ...) end
	lb.GetAsync = function(self, key, ...) table.insert(reads, key); return oGet(self, key, ...) end
end
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

--=========================================================================== 1. the board in the world
section("1. the board in the world")
local board = W.Lifeboat:FindFirstChild("RelayBoard")
truthy(board ~= nil and board:IsA("BasePart"), "a physical board (workspace.Lifeboat.RelayBoard)")
local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt", true)
truthy(prompt ~= nil, "with a ProximityPrompt")
if prompt then
	eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
	eq(prompt.HoldDuration, 0, "a tap")
	eq(prompt.ActionText, "Public / Friends", "it says what it does")
	-- never reachable from the LIFT pad (pressing it there would also board you)
	local at = board.CFrame * Vector3.new(0, -3.5, -0.6)
	local pad = W.Lifeboat.Lift.LiftPad
	local nearest = Vector3.new(math.clamp(at.X, pad.Position.X - 4, pad.Position.X + 4), at.Y, math.clamp(at.Z, -4, 4))
	truthy((nearest - at).Magnitude > prompt.MaxActivationDistance, string.format("its prompt cannot be reached from the LIFT pad (%.1f studs)", (nearest - at).Magnitude))
end

--=========================================================================== 2. the stored value, ties
section("2. the stored value, and ties to whoever was first")
RS:setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	Players:simulateSpawn(p, W)
	return p
end
local B = joinAs("Bo", 502)
local D = joinAs("Dee", 504)
local C = joinAs("Cy", 503)
local A = joinAs("Ava", 501) -- last: the client scripts below are Ava's
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Board.client"))
h:advance(2)
local function stored(uid) return lb.__data["u_" .. uid] end
eq(stored(501), Board.encode(12, 1780000000, bc), "Ava's saved best (12 at 1780000000) is on the board, encoded")
eq(stored(502), Board.encode(12, 1770000000, bc), "Bo's (12, reached earlier)")
eq(stored(503), Board.encode(29, 1785000000, bc), "Cy's (29)")
truthy(stored(501) % 1 == 0 and stored(501) < 2 ^ 53, "an integer under 2^53")
local boardRemote = RSx.SignalRemotes.Board
local function lastView(plr)
	local sent = boardRemote:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
h:advance(bc.PublicCacheSeconds + 1)
local pub = lastView(A)
truthy(pub ~= nil and pub.mode == "public", "Ava's board starts PUBLIC")
if pub then
	local order = {}
	for _, r in pub.rows do table.insert(order, r.userId .. ":" .. r.tier .. ":" .. tostring(r.name) .. (if r.star then "*" else "")) end
	eq(table.concat(order, " "), "505:40:User_505* 503:29:Cy 508:20:User_508 502:12:Bo 501:12:Ava 504:3:Dee",
		"public: highest first, Bo above Ava on a tie (first), names resolved, a star at 40 (>= 30)")
end

--=========================================================================== 3. written only when it improves, at most once a minute
section("3. written only when it improves, at most once per 60 s, and on leaving")
do
	local w0 = writes
	h:advance(3 * Config.Data.AutosaveSeconds)
	eq(writes, w0, "a minute of autosaves with no new best writes nothing to the board")
	-- Dee plays: sectors 4, 5, 6 fast, each splice improving her best
	local dbot = Bot.new(h, D, {})
	truthy(dbot:board(), "Dee boards")
	dbot:waitPhase("sector", 5)
	local tStart = h.scheduler:now()
	local splices = 0
	for _ = 1, 3 do
		local r = dbot:playSector(400)
		if r == "blackout" then dbot:waitPhase("sector", 6); r = dbot:playSector(400) end
		if r == "spliced" then splices += 1 end
		dbot:toRelayPiece("FloorHatch")
		dbot:waitPhase("sector", 6)
	end
	local minutes = (h.scheduler:now() - tStart) / 60
	local dWrites = writes - w0
	print(string.format("   Dee: %d splices in %.2f min -> %d ordered writes", splices, minutes, dWrites))
	truthy(splices >= 2, "Dee spliced at least two sectors (" .. splices .. ")")
	truthy(dWrites >= 1 and dWrites <= math.ceil(minutes) + 1, "at most one ordered write a minute (" .. dWrites .. " in " .. string.format("%.2f", minutes) .. " min)")
	local best = dbot:state().best
	h:leave(D)
	h:advance(1)
	local m = Board.decode(stored(504))
	eq(m, best, "leaving writes the latest best at once (" .. best .. ")")
end

--=========================================================================== 4. public cached ~60 s
section("4. the public list is cached ~60 s")
do
	local s0 = sorted
	h:advance(180)
	local n = sorted - s0
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 180 s")
end

--=========================================================================== 5. drawn by Ava's client
section("5. the physical board, drawn by Ava's client")
local function boardTexts()
	local gui = board:FindFirstChildWhichIsA("SurfaceGui", true)
	local texts = {}
	if gui then for _, d in gui:GetDescendants() do if d.ClassName == "TextLabel" and d.Visible ~= false and (d.Text or "") ~= "" then table.insert(texts, d.Text) end end end
	return texts, gui
end
local function has(texts, needle)
	for _, t in texts do if string.find(t, needle, 1, true) then return t end end
	return nil
end
do
	local texts, gui = boardTexts()
	truthy(gui ~= nil and gui.Face == Enum.NormalId.Front, "a SurfaceGui on the board's front face")
	truthy(has(texts, "PUBLIC") ~= nil, "it says PUBLIC")
	local r1 = has(texts, "User_505")
	truthy(r1 ~= nil and string.find(r1, "40 relays", 1, true) ~= nil and string.find(r1, "★", 1, true) ~= nil, "row 1: the star, User_505, 40 relays (" .. tostring(r1) .. ")")
	local mine = has(texts, "Ava")
	truthy(mine ~= nil and string.find(mine, "(you)", 1, true) ~= nil, "Ava's own row is marked (" .. tostring(mine) .. ")")
end

--=========================================================================== 6. friends: on demand, cached, per player
section("6. friends: on demand, cached, per player")
eq(friendCalls[501], nil, "no friends fetched before anyone asked")
local readsBefore = #reads
prompt.Triggered:Fire(A)
h:advance(2)
eq(friendCalls[501], 1, "the prompt fetches Ava's friends once")
local fv = lastView(A)
truthy(fv ~= nil and fv.mode == "friends", "Ava's board is FRIENDS")
if fv then
	local order = {}
	for _, r in fv.rows do table.insert(order, r.userId .. ":" .. r.tier .. (if r.you then "*" else "")) end
	eq(table.concat(order, " "), "505:40 508:20 502:12 501:12*", "friends: Eve 40, Gus 20, Bo 12 (first), Ava 12 (you); Finn never spliced")
	eq(fv.note, nil, "all four checked: no note")
end
do
	local newReads = {}
	for i = readsBefore + 1, #reads do table.insert(newReads, reads[i]) end
	table.sort(newReads)
	eq(table.concat(newReads, ","), "u_505,u_506,u_508", "only the friends NOT in this server are read (Bo's comes from memory)")
end
truthy(has(boardTexts(), "FRIENDS") ~= nil, "the board says FRIENDS")
eq(lastView(B).mode, "public", "Bo's board is still PUBLIC: the toggle is per player")
prompt.Triggered:Fire(A)
h:advance(0.5)
eq(lastView(A).mode, "public", "the prompt again: back to PUBLIC")
prompt.Triggered:Fire(A) -- 0.5 s after the last toggle
h:advance(0.5)
local toasts = {}
for _, rec in RSx.SignalRemotes.Notice:sentTo(A) do if rec.args[1] == "toast" then table.insert(toasts, rec.args[2]) end end
eq(toasts[#toasts], "One moment…", "a toggle inside 2 s of the last is refused, and says so")
eq(lastView(A).mode, "public", "and changes nothing")
h:advance(2)
local readsMid = #reads
prompt.Triggered:Fire(A)
h:advance(1)
eq(lastView(A).mode, "friends", "and FRIENDS again")
eq(friendCalls[501], 1, "from the cache (still 1 fetch)")
eq(#reads, readsMid, "and every score from the cache")

--=========================================================================== 7. empty friends boards say something useful
section("7. empty friends boards say something useful")
local function friendsNoteFor(name, uid)
	local p = joinAs(name, uid)
	h:advance(1)
	prompt.Triggered:Fire(p)
	h:advance(3)
	local v = lastView(p)
	return v and v.note, v
end
eq(friendsNoteFor("Hal", 510), bc.Text.NoFriends, "no friends: says friends you add show up here")
eq(friendsNoteFor("Ida", 511), string.format(bc.Text.FriendsNoScores, 1), "friends who never spliced: says so, and invites")
local failedNote, fview = friendsNoteFor("Jon", 512)
eq(failedNote, bc.Text.FriendsFailed, "the friends call fails: says try again, no crash")
eq(fview and fview.mode, "friends", "and still shows the friends view")

--=========================================================================== 8. capped at 200, throttled, budget-gated
section("8. capped at 200, throttled, and never below the budget reserve")
do
	-- an instance method cannot be assigned through the emulator's property machinery; a raw field shadows it
	rawset(DSS, "GetRequestBudgetForRequestType", function() return bc.BudgetReserve - 1 end)
	local readsAt = #reads
	local p = joinAs("Kim", 513)
	h:advance(1)
	prompt.Triggered:Fire(p)
	h:advance(5)
	eq(#reads - readsAt, 0, "with the GetAsync budget under the reserve (" .. bc.BudgetReserve .. "), no friend's score is read")
	local mid = lastView(p)
	truthy(mid and mid.note and string.find(mid.note, "of 200", 1, true) ~= nil, "the board says it is still checking (" .. tostring(mid and mid.note) .. ")")
	rawset(DSS, "GetRequestBudgetForRequestType", nil)
	h:advance(1)
	local early = #reads - readsAt
	truthy(early <= bc.ReadsBurst + 2, "budget back: at most the burst at once (" .. early .. ")")
	h:advance(59)
	local minute = #reads - readsAt
	truthy(minute <= bc.ReadsBurst + bc.ReadsPerSecond * 60 + 1, "a minute in: " .. minute .. " reads, never more than burst + rate * 60")
	h:advance(240)
	eq(#reads - readsAt, 200, "in the end exactly the first 200 friends are read, not 450")
	truthy(pagesAdvanced <= 4, "and no page past the 200th friend is fetched (" .. pagesAdvanced .. " pages turned)")
end

--=========================================================================== 9. the Main Array: the brag
section("9. the Main Array: relay 30 announced to everyone, arrayAt written once, the star")
do
	local cbot = Bot.new(h, C, {})
	truthy(cbot:board(), "Cy (29 relays, every upgrade) boards")
	cbot:waitPhase("sector", 5)
	eq(cbot:state().k, 30, "sector 30: the Main Array")
	local announced = {}
	local annBefore = #RSx.SignalRemotes.Announce:getSent()
	local r = cbot:playSector(900)
	if r == "blackout" then cbot:waitPhase("sector", 6); r = cbot:playSector(900) end
	eq(r, "spliced", "Cy splices relay 30")
	for i = annBefore + 1, #RSx.SignalRemotes.Announce:getSent() do table.insert(announced, RSx.SignalRemotes.Announce:getSent()[i]) end
	eq(#announced, 1, "one server-wide announcement")
	if announced[1] then
		eq(announced[1].all, true, "to every player")
		eq(announced[1].args[1].name, C.DisplayName, "naming Cy by display name")
	end
	truthy(cbot:saw("brag") ~= nil, "Cy's own client gets the brag sequence")
	local hud = A.PlayerGui:FindFirstChild("SignalHud")
	h:advance(0.2)
	truthy(hud and string.find(hud.Root.Toast.Text, "restored the MAIN ARRAY", 1, true) ~= nil, "Ava's HUD shows it (" .. tostring(hud and hud.Root.Toast.Text) .. ")")
	local rec = profiles:GetAsync("u_503")
	local at = rec and rec.data.arrayAt
	truthy(type(at) == "number" and at > 0, "arrayAt is written in the splice's write")
	-- the next sector's relay 31 does not rewrite it, and a second relay-30 is impossible (best + 1)
	cbot:toRelayPiece("FloorHatch")
	cbot:waitPhase("sector", 6)
	local r2 = cbot:playSector(900)
	if r2 == "spliced" then
		local rec2 = profiles:GetAsync("u_503")
		eq(rec2.data.arrayAt, at, "relay 31 leaves arrayAt as it was (written once)")
		eq(#RSx.SignalRemotes.Announce:getSent(), annBefore + 1, "and announces nothing")
	end
	h:leave(C)
	h:advance(bc.PublicCacheSeconds + 1)
	local v = lastView(B)
	local cyRow
	for _, row in v.rows do if row.userId == 503 then cyRow = row end end
	truthy(cyRow and cyRow.tier >= 30 and cyRow.star == true, "the public board marks Cy with the star")
end

--=========================================================================== 10. names are never stored
section("10. names are never stored")
do
	local HttpService = h.game:GetService("HttpService")
	local leaked = nil
	for uid, name in { [501] = "Ava", [502] = "Bo", [503] = "Cy", [504] = "Dee" } do
		local json = HttpService:JSONEncode(profiles:GetAsync("u_" .. uid))
		if string.find(json, '"' .. name .. '"', 1, true) then leaked = leaked or name end
	end
	truthy(leaked == nil, "no saved profile holds a player's name" .. (if leaked then " (" .. leaked .. ")" else ""))
	local allNumbers = true
	for _, v in lb.__data do if type(v) ~= "number" then allNumbers = false end end
	truthy(allNumbers, "the board's store holds only numbers")
end

print("")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "no warnings")
print(string.format("signal-lost board: %d passed, %d failed", passed, failed))
if failed > 0 then error("signal-lost board check failed", 0) end
