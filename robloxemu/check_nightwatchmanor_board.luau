-- Nightwatch Manor — the NIGHTS SURVIVED board, public + friends. Run: luau check_nightwatchmanor_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot inflate,
-- ties to whoever reached it FIRST; OrderedDataStore key u_<userId>, value metric * 2e9 + (2e9 - reachedAtUnix),
-- written only when the metric improves; the public top 10 cached ~60 s; friends via Players:GetFriendsAsync, capped
-- at 200, fetched only on demand, cached, pcall'd and throttle-safe; a physical board near spawn with a
-- ProximityPrompt that toggles Public/Friends; names resolved and cached, never stored; an empty friends board says
-- something useful.
--
-- Nightwatch Manor's metric is the profile's best night: the highest night the SERVER credited you with surviving, and
-- the only way to survive one is the Servants' Exit behind the crossing guard (check_nightwatchmanor_guard). The board
-- stands in every safehouse and the SERVER draws it (a safehouse is its player's alone; there is no remote for it).
-- Everything here runs the REAL server; nights are survived through the real exit (Kit.extract). The emulator has no
-- Players:GetFriendsAsync, so this file supplies one (FriendPages-shaped) and counts the calls. Adapted from
-- check_facilitynightmare_board.luau.

local Harness = require("./emu/harness")
local Kit = require("./check_nightwatchmanor_kit")
local DT = require("./emu/datatypes")
local Vector3, CFrame = DT.Vector3, DT.CFrame

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function section(name) print("== " .. name) end

local h = Harness.new({ bundle = require("./build/nightwatch-manor"), name = "nwm-board", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players

-- Written out, not read from Config: a number checked against itself is not a check.
local STORE, BOARD_STORE = "NightwatchManor_v1", "NightwatchManorBoard_v1"
local AUTOSAVE, PUBLIC_TTL, BURST, CAP = 20, 60, 40, 200

local profilesStore = DSS:GetDataStore(STORE)
local function seed(uid, extra)
	local p = { night = 1, stash = 0, best = 0, levels = {} }
	for k, v in extra do p[k] = v end
	profilesStore:SetAsync("u_" .. uid, { data = p })
end
local AVA, BO, CY, DEE, EVE, FINN, GUS, NED, NEW, HAL, IDA, JON, KIM, RO = 8101, 8102, 8103, 8104, 8105, 8106, 8108, 8109, 8110, 8111, 8112, 8113, 8114, 8115
seed(AVA, { night = 5, best = 4, bestAt = 1780000000 })
seed(BO, { night = 5, best = 4, bestAt = 1770000000 }) -- the same night, reached EARLIER
seed(CY, { night = 10, best = 9, bestAt = 1785000000 })
seed(DEE, { night = 4, best = 3 }) -- saved before the board existed: no bestAt
seed(NED, { night = 6, best = 5, bestAt = 1775000000 }) -- the board already holds 8 for him (a lost profile write)
seed(NEW, {})
-- RO's record is held by another live session: this one can play, not save, so it must not write the board either
profilesStore:SetAsync("u_" .. RO, { data = { night = 1, stash = 0, best = 0, levels = {} }, lock = { token = "another-server", at = os.time() } })

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "server/Main.server loads (" .. tostring(bootErr) .. ")")
if not okBoot then
	print(string.format("nightwatchmanor board: %d passed, %d failed", passed, failed))
	error("boot failed", 0)
end
local Config = h:_require(RS:FindFirstChild("Config"))
local okMod, Board = pcall(function() return h:_require(RS:FindFirstChild("Board")) end)
Board = if okMod then Board else nil
local bc = Config.Board
truthy(type(bc) == "table" and type(Board) == "table", "Config.Board and the Board module exist")
bc = bc or { Text = {}, PublicRows = 10, FriendsRows = 10, ReadsBurst = BURST, ReadsPerSecond = 1, FriendsCap = CAP, MaxMetric = 500, PromptDistance = 9 }
eq(Config.Save.LeaderStore, BOARD_STORE, "the board's OrderedDataStore is " .. BOARD_STORE)
eq(bc.PublicCacheSeconds, PUBLIC_TTL, "the public top 10 is cached 60 s")
eq(bc.FriendsCap, CAP, "friends are capped at 200")
eq(Config.Save.AutosaveSeconds, AUTOSAVE, "set-up: profiles autosave every 20 s")

local function enc(m, t) return if Board then Board.encode(m, t, bc) else m end
local lb = DSS:GetOrderedDataStore(BOARD_STORE)
-- players who are not on this server, already on the board
lb:SetAsync("u_" .. EVE, enc(12, 1760000000))
lb:SetAsync("u_" .. GUS, enc(6, 1765000000))
lb:SetAsync("u_" .. NED, enc(8, 1750000000))

-- count what the server does to the board's store
local writes, sorted, reads = 0, 0, {}
local sortedArgs = {} -- every GetSortedAsync call's (ascending, pageSize), as "false/10"
local failSorted = false -- the next GetSortedAsync raises, as a throttled or failing store does
do
	local oUpdate, oSet, oSorted, oGet = lb.UpdateAsync, lb.SetAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; return oSet(self, ...) end
	lb.GetSortedAsync = function(self, ...)
		sorted += 1
		local ascending, pageSize = ...
		sortedArgs[tostring(ascending) .. "/" .. tostring(pageSize)] = true
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

local function joinAs(name, uid)
	local p = h:join(name, uid)
	h.Players:simulateSpawn(p, h.workspace)
	return p
end
local function houseOf(plr)
	local z = h.workspace:FindFirstChild("Zone_" .. plr.UserId)
	return z and z:FindFirstChild("Safehouse")
end
local function boardOf(plr)
	local house = houseOf(plr)
	return house and house:FindFirstChild("NightsBoard")
end
local function promptOf(plr)
	local b = boardOf(plr)
	return b and b:FindFirstChildWhichIsA("ProximityPrompt", true)
end
-- what the board in `plr`'s safehouse shows: { title, mode, rows = { text }, note }
local function shown(plr)
	local b = boardOf(plr)
	local gui = b and b:FindFirstChildWhichIsA("SurfaceGui")
	local out = { rows = {}, mode = "", title = "", note = nil, gui = gui }
	if not gui then return out end
	local t, m, n = gui:FindFirstChild("Title"), gui:FindFirstChild("Mode"), gui:FindFirstChild("Note")
	out.title = t and t.Text or ""
	out.mode = m and m.Text or ""
	out.note = if n and n.Visible and n.Text ~= "" then n.Text else nil
	for i = 1, 20 do
		local r = gui:FindFirstChild("Row" .. i)
		if r and r.Visible and r.Text ~= "" then table.insert(out.rows, r.Text) end
	end
	return out
end
local remotes = RS:FindFirstChild("ManorRemotes")
local function noticesOf(plr, kind)
	local n = 0
	for _, s in remotes:FindFirstChild("Notice"):sentTo(plr) do
		local p = s.args[1]
		if type(p) == "table" and p.kind == kind then n += 1 end
	end
	return n
end
local function stateOf(plr)
	local list = remotes:FindFirstChild("State"):sentTo(plr)
	for i = #list, 1, -1 do
		if type(list[i].args[1]) == "table" then return list[i].args[1] end
	end
	return {}
end
-- survive the night `plr` is on, through the real exit (Kit.extract: stand at the door after the shortest walk)
local function surviveNight(plr)
	houseOf(plr).ManorDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	local began = h.scheduler:now()
	h:advance(0.6)
	local ok = Kit.extract(h, plr, plr.UserId, began, function(s) h:advance(s) end)
	h:advance(Config.BeatSeconds + 0.5)
	return ok
end
local function caughtOnce(plr)
	houseOf(plr).ManorDoor:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	h:advance(0.6)
	local z = h.workspace:FindFirstChild("Zone_" .. plr.UserId)
	local w = z and z:FindFirstChild("Manor") and z.Manor:FindFirstChild("Nightwatcher")
	if w then plr.Character:PivotTo(CFrame.new(w:GetPivot().Position)) end
	h:advance(0.5)
	h:advance(Config.BeatSeconds + 0.5)
end

--======================================================================= 1. the board in the world
section("1. a board stands in every safehouse, a few steps from the spawn pad")

local A = joinAs("Ava", AVA)
local joinedAt = os.time()
h:advance(1.5)
local board = boardOf(A)
local prompt = promptOf(A)
truthy(board ~= nil and board:IsA("BasePart"), "a physical board stands in Ava's safehouse (Safehouse.NightsBoard)")
truthy(prompt ~= nil, "with a ProximityPrompt")
local house = houseOf(A)
local spawnPad = house and house:FindFirstChild("SpawnPad")
if board and spawnPad then
	local d = board.Position - spawnPad.Position
	local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
	print(string.format("  board centre %.1f studs from the spawn pad (flat)", flat))
	truthy(flat <= 32, string.format("near the spawn: %.1f studs from the spawn pad, half the safehouse", flat))
	local look = board.CFrame.LookVector
	local toSpawn = Vector3.new(spawnPad.Position.X - board.Position.X, 0, spawnPad.Position.Z - board.Position.Z)
	local cos = (look.X * toSpawn.X + look.Z * toSpawn.Z) / math.max(toSpawn.Magnitude, 1e-6)
	truthy(cos > 0.5, string.format("its front face (where the board is drawn) faces the room and the spawn (cos %.2f)", cos))
	local floor = house:FindFirstChild("Floor")
	local half = Config.Hub.Size / 2
	local hx = math.abs(look.X) * board.Size.Z / 2 + math.abs(look.Z) * board.Size.X / 2
	local hz = math.abs(look.Z) * board.Size.Z / 2 + math.abs(look.X) * board.Size.X / 2
	truthy(math.abs(board.Position.X - floor.Position.X) + hx <= half and math.abs(board.Position.Z - floor.Position.Z) + hz <= half,
		"inside the safehouse walls")
	-- clear of everything a player walks to: the pads (and their props), the spawn pad, the manor door's approach
	local clash = nil
	for _, p in house:GetChildren() do
		local isPad = p:IsA("BasePart") and (string.match(tostring(p.Name), "^Pad_") ~= nil or p.Name == "SpawnPad")
		local isDoor = p.Name == "ManorDoor"
		if isPad or isDoor then
			local px, pz = p.Size.X / 2 + (if isDoor then 0 else 1), p.Size.Z / 2 + (if isDoor then 6 else 1)
			if math.abs(p.Position.X - board.Position.X) < px + hx and math.abs(p.Position.Z - board.Position.Z) < pz + hz then
				clash = clash or p.Name
			end
		end
	end
	eq(clash, nil, "clear of the upgrade pads, the spawn pad and the way to the manor door")
end
if prompt then
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
	truthy(string.find(prompt.ActionText, "Public", 1, true) ~= nil and string.find(prompt.ActionText, "Friends", 1, true) ~= nil,
		"and it says what it does (" .. prompt.ActionText .. ")")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
	eq(prompt.RequiresLineOfSight, false, "no line of sight needed (the board face is a wall)")
	truthy(prompt.KeyboardKeyCode ~= Enum.KeyCode.E, "its key is not E, so it never fights an upgrade pad's prompt")
	local at = prompt.Parent
	local wp = if at and at:IsA("Attachment") then board.CFrame:PointToWorldSpace(at.Position) else board.Position
	local floor = house:FindFirstChild("Floor")
	-- a player standing on the floor 4 studs in front of the board's face
	local front = board.Position + board.CFrame.LookVector * (board.Size.Z / 2 + 4)
	local stand = Vector3.new(front.X, floor.Position.Y + floor.Size.Y / 2 + 3, front.Z)
	truthy((wp - stand).Magnitude <= bc.PromptDistance, string.format("reachable from the floor in front of it (%.1f studs)", (wp - stand).Magnitude))
end
do
	local s = shown(A)
	truthy(s.gui ~= nil, "the server draws a SurfaceGui on the board")
	truthy(s.gui == nil or s.gui.Face == Enum.NormalId.Front, "on its front face, the one looking into the room")
	if s.gui and board then
		local ppS = s.gui.PixelsPerStud
		truthy(s.gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud and ppS >= 30,
			"sized in pixels per stud, so the text keeps the board's proportions (" .. tostring(ppS) .. ")")
	end
	truthy(A.PlayerGui:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "not in PlayerGui (the HUD fit check measures everything there as screen)")
	truthy(string.find(s.title, "NIGHTS SURVIVED", 1, true) ~= nil, "titled NIGHTS SURVIVED (" .. s.title .. ")")
	truthy(string.find(s.mode, "PUBLIC", 1, true) ~= nil, "it starts on PUBLIC (" .. s.mode .. ")")
	-- the first player of a fresh server must not stare at "Loading..." for a minute
	truthy(s.note ~= bc.Text.Loading and #s.rows > 0, string.format(
		"1.5 s after the first player joined, the public list is up, not Loading (%d rows, note %s)", #s.rows, tostring(s.note)))
end

--======================================================================= 2. the stored value, and ties
section("2. what is stored: the owner's formula, ties to the first")

local B = joinAs("Bo", BO)
local C = joinAs("Cy", CY)
local D = joinAs("Dee", DEE)
local N = joinAs("Ned", NED)
local dJoinedAt = os.time()
h:advance(AUTOSAVE + 1)

local function stored(uid) return lb.__data["u_" .. uid] end
local function decode(v) if Board and type(v) == "number" then return Board.decode(v) end return nil, nil end
table.clear(reads)
eq(stored(AVA), enc(4, 1780000000), "Ava's saved best (night 4, reached 1780000000) is stored encoded")
eq(stored(BO), enc(4, 1770000000), "Bo's too (night 4, reached EARLIER)")
eq(stored(CY), enc(9, 1785000000), "and Cy's (9)")
eq(stored(NED), enc(8, 1750000000), "Ned's 8 on the board is never lowered to his profile's 5")
do
	local m, t = decode(stored(DEE))
	eq(m, 3, "a save from before the board existed still gets on it (Dee, 3)")
	truthy(t ~= nil and math.abs(t - dJoinedAt) <= 5, "stamped with the session it came back in (" .. tostring(t) .. " vs " .. dJoinedAt .. ")")
	local rec = profilesStore:GetAsync("u_" .. DEE)
	eq(rec and rec.data and rec.data.bestAt, t, "and that stamp is saved in Dee's profile, so it never moves again")
end
local _ = joinedAt

--======================================================================= 3. the public view on the board
section("3. the public top 10, drawn on the board")

h:advance(PUBLIC_TTL + 1) -- the next public refresh sees the new values
do
	local s = shown(A)
	print("  Ava's board: " .. table.concat(s.rows, " | "))
	local want = {
		"1. User_8105   night 12", "2. Cy   night 9", "3. Ned   night 8", "4. User_8108   night 6",
		"5. Bo   night 4", "6. Ava (you)   night 4", "7. Dee   night 3",
	}
	eq(table.concat(s.rows, " | "), table.concat(want, " | "),
		"public: highest night first; Bo above Ava on the same night (he got there first); names resolved; Ava's row marked")
	eq(s.note, nil, "a board with rows has no note")
	local maxNight = 0
	for _, r in s.rows do
		local n = tonumber(string.match(r, "night (%d+)$")) or 0
		maxNight = math.max(maxNight, n)
	end
	truthy(maxNight < 1000, "no row shows a raw stored value (max " .. maxNight .. ")")
	local sb = shown(B)
	eq(sb.rows[5], "5. Bo (you)   night 4", "Bo's own board marks HIS row")
end

--======================================================================= 4. written only when it improves
section("4. a new best night writes it once; nothing else writes")

do
	local w0 = writes
	h:advance(2 * AUTOSAVE + 1)
	eq(writes, w0, "two autosaves with no new best write nothing to the board")
end
local P = joinAs("Newbie", NEW)
h:advance(1.5)
do
	local w0 = writes
	truthy(surviveNight(P), "set-up: Newbie survives night 1 through the exit")
	local outAt = os.time()
	eq(stateOf(P).best, 1, "set-up: night 1 is Newbie's best")
	eq(writes, w0 + 1, "a new best: exactly one board write, at once")
	local m, t = decode(stored(NEW))
	eq(m, 1, "the board holds night 1 for Newbie")
	truthy(t ~= nil and math.abs(t - outAt) <= 5, "stamped when Newbie got out (" .. tostring(t) .. " vs " .. outAt .. ")")
	caughtOnce(P)
	eq(stateOf(P).night, 2, "set-up: caught on night 2, still on night 2")
	h:advance(AUTOSAVE + 1)
	eq(writes, w0 + 1, "being caught and the autosave after it write nothing")
	truthy(surviveNight(P), "set-up: Newbie survives night 2")
	eq(stateOf(P).best, 2, "set-up: night 2 is the new best")
	h:advance(2 * AUTOSAVE + 1)
	eq(writes, w0 + 2, "a better night: one more write (within two autosaves; at most one write per 30 s)")
	eq((decode(stored(NEW))), 2, "the board now holds night 2")
	local stamp = stored(NEW)
	h:leave(P)
	h:advance(1)
	eq(writes, w0 + 2, "leaving with nothing new writes nothing")
	local P2 = joinAs("Newbie", NEW)
	h:advance(AUTOSAVE + 1)
	eq(writes, w0 + 2, "a rejoin does not write the same best again (the profile remembers what it wrote)")
	eq(stored(NEW), stamp, "and the first reach time stands")
	h:leave(P2)
	h:advance(1)
end
-- a read-only session plays, but its nights are not saved, so they never reach the board
do
	local w0 = writes
	local R = joinAs("Rook", RO)
	h:advance(1.5)
	eq(noticesOf(R, "READONLY"), 1, "set-up: Rook's profile is open in another session: told it is read-only")
	truthy(surviveNight(R), "set-up: Rook survives night 1 anyway")
	eq(stateOf(R).best, 1, "set-up: Rook's best is night 1 in this session")
	h:advance(AUTOSAVE + 1)
	h:leave(R)
	h:advance(1)
	eq(writes, w0, "a read-only session writes nothing to the board (its night is not saved either)")
	eq(stored(RO), nil, "and Rook is not on the board")
end

--======================================================================= 5. the public list is cached ~60 s
section("5. the public top 10 is read at most once a minute")

do
	local s0 = sorted
	h:advance(180)
	local n = sorted - s0
	print(string.format("  public top 10: %d GetSortedAsync calls in 180 s", n))
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 180 s (one per " .. PUBLIC_TTL .. " s)")
	local asked = {}
	for k in sortedArgs do table.insert(asked, k) end
	table.sort(asked)
	eq(table.concat(asked, ","), "false/10", "every public read is GetSortedAsync(false, 10): the highest 10, nothing more")
	local before = table.concat(shown(A).rows, " | ")
	local s1 = sorted
	failSorted = true
	h:advance(PUBLIC_TTL + 1)
	truthy(sorted > s1 and not failSorted, "set-up: a GetSortedAsync failed in that minute")
	eq(table.concat(shown(A).rows, " | "), before, "a failed read keeps the last list on the board")
end

--======================================================================= 6. friends: on demand, cached, per player
section("6. friends: fetched on demand, cached, per player")

eq(friendCalls[AVA], nil, "no friends were fetched before anyone asked")
local readsBefore = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(2)
eq(friendCalls[AVA], 1, "the prompt fetches Ava's friends once")
do
	local s = shown(A)
	truthy(string.find(s.mode, "FRIENDS", 1, true) ~= nil, "Ava's board now says FRIENDS (" .. s.mode .. ")")
	eq(table.concat(s.rows, " | "), "1. Eve   night 12 | 2. Gus   night 6 | 3. Bo   night 4 | 4. Ava (you)   night 4",
		"friends: Eve 12, Gus 6, Bo 4 (first there), Ava 4 (you); Finn never got out; names from the friends list")
	eq(s.note, nil, "all four friends checked: no note")
end
do
	local newReads = {}
	for i = readsBefore + 1, #reads do table.insert(newReads, reads[i]) end
	table.sort(newReads)
	eq(table.concat(newReads, ","), "u_8105,u_8106,u_8108", "the scores read are the three friends NOT on this server (Bo's comes from memory)")
end
truthy(string.find(shown(B).mode, "PUBLIC", 1, true) ~= nil, "Bo's board is still PUBLIC: the toggle is per player")
if prompt then prompt.Triggered:Fire(B) end -- Bo pressing AVA's prompt (he could never reach it: zones are 3000 apart)
h:advance(1)
truthy(string.find(shown(A).mode, "FRIENDS", 1, true) ~= nil, "a stranger pressing Ava's board changes nothing")
eq(friendCalls[BO], nil, "...and fetches nothing")
if prompt then prompt.Triggered:Fire(A) end
h:advance(1)
truthy(string.find(shown(A).mode, "PUBLIC", 1, true) ~= nil, "the prompt again: back to PUBLIC")
local readsMid = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(1)
truthy(string.find(shown(A).mode, "FRIENDS", 1, true) ~= nil, "and FRIENDS again")
eq(friendCalls[AVA], 1, "the friends list came from the cache (still 1 fetch)")
eq(#reads, readsMid, "and so did every score (no new reads)")

--======================================================================= 7. empty friends boards say something useful
section("7. an empty friends board says something useful")

local function friendsNoteFor(name, uid, wait)
	local p = joinAs(name, uid)
	h:advance(1.5)
	local pr = promptOf(p)
	if pr then pr.Triggered:Fire(p) end
	h:advance(wait or 3)
	return shown(p), p
end
do
	local s = friendsNoteFor("Hal", HAL)
	eq(s.note, bc.Text.NoFriends, "no friends: says friends you add show up here")
	local s2 = friendsNoteFor("Ida", IDA)
	eq(s2.note, string.format(bc.Text.FriendsNoScores, 1), "friends who never got out: says so, and invites")
	local s3 = friendsNoteFor("Jon", JON)
	eq(s3.note, bc.Text.FriendsFailed, "the friends call failed: says try again, and nothing broke")
	local pr = promptOf((Players:GetPlayerByUserId(JON)))
	if pr then
		pr.Triggered:Fire(Players:GetPlayerByUserId(JON)) -- back to public
		h:advance(1)
		pr.Triggered:Fire(Players:GetPlayerByUserId(JON)) -- friends again, within the minute
		h:advance(2)
	end
	eq(friendCalls[JON], 1, "a failed fetch is not retried on every press (once a minute at most)")
	for _, t in { s.note, s2.note, s3.note } do
		truthy(type(t) == "string" and #t > 20, "each empty-board note is a real sentence (" .. tostring(t) .. ")")
	end
end

--======================================================================= 8. capped, throttle-safe
section("8. a player with 450 friends: 200 read, never more, at a safe pace")

do
	local r0 = #reads
	local p0 = pagesAdvanced
	local s, K = friendsNoteFor("Kim", KIM, 1)
	local burst = #reads - r0
	print(string.format("  Kim: %d score reads in the first second", burst))
	-- a token bucket grants at most capacity + rate x T in any T seconds: 40 + 1 in the first second
	truthy(burst <= BURST + 1, string.format("the first second reads at most the burst plus one second's refill (%d of %d)", burst, BURST + 1))
	truthy(s.note ~= nil and string.find(s.note, "of 200", 1, true) ~= nil, "while it reads, the board says how far it has got (" .. tostring(s.note) .. ")")
	h:advance(200)
	local total = #reads - r0
	print(string.format("  Kim: %d score reads after 200 s; %d friend pages turned", total, pagesAdvanced - p0))
	eq(total, CAP, "every one of the first 200 friends read once, and not one more")
	truthy(pagesAdvanced - p0 <= 4, "the friends list was never paged past 200 (" .. (pagesAdvanced - p0) .. " page turns)")
	local s2 = shown(K)
	eq(s2.note, string.format(bc.Text.FriendsNoScores, CAP), "and then: none of your 200 friends has survived a night")
end

--======================================================================= 9. names are never stored
section("9. names are looked up, never stored")

do
	local named = 0
	for _, uid in { AVA, BO, CY, DEE, NED, NEW, HAL, IDA, JON, KIM } do
		local rec = profilesStore:GetAsync("u_" .. uid)
		local function scan(v)
			if type(v) == "table" then for k, x in v do scan(k); scan(x) end
			elseif type(v) == "string" then
				for _, nm in { "Ava", "Bo", "Cy", "Dee", "Ned", "Newbie", "Hal", "Ida", "Jon", "Kim", "Eve", "Gus", "Finn" } do
					if v == nm then named += 1 end
				end
			end
		end
		scan(rec)
	end
	eq(named, 0, "no saved profile holds a player's name")
	local nonNumber = 0
	for _, v in lb.__data do
		if type(v) ~= "number" then nonNumber += 1 end
	end
	eq(nonNumber, 0, "the board's store holds numbers only")
end

for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "no warnings from the server")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("nightwatchmanor board: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("nightwatchmanor board failed", 0)
end
