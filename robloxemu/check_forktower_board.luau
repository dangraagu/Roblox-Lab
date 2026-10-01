-- Fork Tower — the highscore board (public + friends), the spawn, and the whole player path. Run:
--   luau check_forktower_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../fork-tower --out build/fork-tower.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot
-- inflate, ties to whoever reached it FIRST; OrderedDataStore key u_<userId>, value metric * 2e9 + (2e9 -
-- reachedAtUnix), written only when the metric improves; the public top 10 cached ~60 s; friends via
-- Players:GetFriendsAsync, capped at 200, fetched only on demand, cached, pcall'd and throttle-safe; a physical
-- board near spawn with a ProximityPrompt that toggles Public/Friends; names resolved and cached, never stored;
-- an empty friends board says something useful. Fork Tower's metric is the best Build Reveal score a summit
-- banked: the server computes it from the run's picks (Build.reveal) and no client sends a number; the exit
-- rule (check_forktower_exit) is what makes a summit a climb.
--
-- Before pass 2 (2026-10-01) the game had a public top 10 only, in a HUD drawer, storing the raw score with
-- SetAsync (no tie-break), no friends view, no board in the world, and every HUD resolved every name on every
-- refresh. This file is modelled on check_plus1jump_board.luau (the template the board module comes from).
--
-- It also holds two things from §1 of the standard:
--   * SPAWN: plr.RespawnLocation points at a real, enabled SpawnLocation (robloxemu/SPAWN-ORDER.md): the
--     player's own LaneSpawn, and the WaitingSpawn for a player the server has no tower for;
--   * THE PLAYER PATH, walked headless through the real server and clients: join and spawn on your own tower,
--     earn a skip with a public code, spend it on a trap door, climb all ten floors, the Build Reveal banks a
--     score, the board shows it, leave, rejoin with everything back, rebirth onto a new tower.
-- Everything is driven through the REAL server, HUD and Board.client. The emulator has no
-- Players:GetFriendsAsync, so this file supplies one (FriendPages-shaped) and counts the calls.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/fork-tower"), name = "fork-tower-board", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players

-- saved profiles, before the server starts
local profilesStore = DSS:GetDataStore("ForkTower_v1")
local function seed(uid, d)
	local rec = {
		runSeed = 2, level = 1, stage = "fork", picks = {}, slots = {}, readFloors = {}, skipped = {},
		skips = 0, rebirths = 1, bestScore = 0, bestTitle = "", redeemed = {}, summits = 1,
	}
	for k, v in d do rec[k] = v end
	profilesStore:SetAsync("u_" .. uid, { data = rec })
end
seed(502, { bestScore = 40, bestScoreAt = 1770000000 })
seed(503, { bestScore = 52, bestScoreAt = 1785000000 })
seed(504, { bestScore = 33 }) -- saved before 2026-10-01: no bestScoreAt
seed(506, { bestScore = 40, bestScoreAt = 1780000000 }) -- Eli: the same 40 as Bo, reached LATER
seed(509, { bestScore = 30, bestScoreAt = 1775000000 }) -- Ned: the board already holds 45 for him

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Board = h:_require(RS:FindFirstChild("Board"))
local bc = Config.Board
truthy(type(bc) == "table" and type(Board) == "table", "Config.Board and the Board module exist")
bc = bc or { Text = {}, PublicRows = 10, FriendsRows = 10, ReadsBurst = 40, ReadsPerSecond = 1, FriendsCap = 200,
	PublicCacheSeconds = 60, PromptDistance = 8 }
truthy(Config.Save.Leaderboard ~= "ForkTower_LB_v1",
	"the encoded board lives in a new store (" .. tostring(Config.Save.Leaderboard) .. "): v1 held raw scores")

local lb = DSS:GetOrderedDataStore(Config.Save.Leaderboard)
local function enc(m, t) return if Board then Board.encode(m, t, bc) else m end
-- offline climbers already on the board
lb:SetAsync("u_505", enc(55, 1760000000))
lb:SetAsync("u_508", enc(25, 1765000000))
lb:SetAsync("u_509", enc(45, 1750000000))

-- count what the server does to the board's store
local writes, sets, sorted, reads = 0, 0, 0, {}
do
	local oUpdate, oSet, oSorted, oGet = lb.UpdateAsync, lb.SetAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; sets += 1; return oSet(self, ...) end
	lb.GetSortedAsync = function(self, ...) sorted += 1; return oSorted(self, ...) end
	lb.GetAsync = function(self, key, ...) table.insert(reads, key); return oGet(self, key, ...) end
end

-- friends, per user id: a list of { Id, Username } (or "error")
local friendsOf = {
	[501] = { { 502, "Bo" }, { 505, "Eve" }, { 507, "Finn" }, { 508, "Gus" } },
	[510] = {},
	[511] = { { 507, "Finn" } },
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

local remotes = RS:FindFirstChild("ForkRemotes")
local towers = h.workspace:FindFirstChild("Towers")
local function laneOf(plr)
	for _, f in towers:GetChildren() do
		if f:GetAttribute("Owner") == plr.UserId then return f end
	end
	return nil
end
local function boardOf(plr)
	local lane = laneOf(plr)
	return lane and lane:FindFirstChild("TopBoard")
end
local waitingSpawn = h.workspace:FindFirstChild("Waiting") and h.workspace.Waiting:FindFirstChild("WaitingSpawn")
local function inWorkspace(inst)
	local p = inst
	while p ~= nil do
		if p == h.workspace then return true end
		p = p.Parent
	end
	return false
end
-- §1: plr.RespawnLocation is a real, enabled SpawnLocation (SPAWN-ORDER.md), and which one
local function spawnOf(plr)
	local rl = plr.RespawnLocation
	if rl == nil then return nil, "nil" end
	if not rl:IsA("SpawnLocation") then return nil, "not a SpawnLocation" end
	if rl.Enabled ~= true then return nil, "disabled " .. rl.Name end
	if not inWorkspace(rl) then return nil, "not in the workspace" end
	return rl, rl.Name
end

h.game:GetService("RunService"):setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	h:advance(0.5)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(0.5)
	return p
end
local B = joinAs("Bo", 502)
local C = joinAs("Cy", 503)
local D = joinAs("Dee", 504)
local E = joinAs("Eli", 506)
local N = joinAs("Ned", 509)
local joinedAt = os.time()
local A = joinAs("Ava", 501) -- last: the client scripts below are Ava's
assert(h:tryRun("client/Hud.client"))
local okClient, errClient = h:tryRun("client/Board.client")
truthy(okClient, "Board.client loads (" .. tostring(errClient) .. ")")
h:advance(1)

--======================================================================= 1. spawn: RespawnLocation

do
	for _, p in { A, B, C, D, E, N } do
		local rl, why = spawnOf(p)
		truthy(rl ~= nil, p.Name .. ": RespawnLocation is a real, enabled SpawnLocation in the workspace (" .. why .. ")")
		truthy(rl ~= nil and rl.Parent == laneOf(p), p.Name .. ": and it is the LaneSpawn of their OWN tower ("
			.. (if rl then rl:GetFullName() else "none") .. ")")
	end
	truthy(waitingSpawn ~= nil and waitingSpawn.Enabled == true, "set-up: the WaitingSpawn exists and is enabled")
	-- the engine would put a respawn in the player's own tower: the LaneSpawn is on their lobby, inside their lane
	local rl = spawnOf(A)
	local lane = laneOf(A)
	local lobby = lane and lane:FindFirstChild("LobbyPad")
	if rl and lobby then
		local dx, dz = math.abs(rl.Position.X - lobby.Position.X), math.abs(rl.Position.Z - lobby.Position.Z)
		truthy(dx <= lobby.Size.X / 2 and dz <= lobby.Size.Z / 2, string.format(
			"Ava's spawn stands on her own lobby pad (%.1f, %.1f studs from its centre)", dx, dz))
	end
	-- and the game still puts her on her checkpoint (floor 1's fork pad) after the engine's step
	local hrp = A.Character and A.Character:FindFirstChild("HumanoidRootPart")
	local pad = lane and lane:FindFirstChild("Fork_1") and lane.Fork_1:FindFirstChild("ForkPad_1")
	if hrp and pad then
		local d = Vector3.new(hrp.Position.X - pad.Position.X, 0, hrp.Position.Z - pad.Position.Z).Magnitude
		truthy(d < 1, string.format("after spawning, Ava stands on floor 1's fork pad (%.2f studs off its centre)", d))
	end
end

--======================================================================= 2. the board in the world

local board = boardOf(A)
truthy(board ~= nil and board:IsA("BasePart"), "Ava's tower has a physical board (Lane_n.TopBoard)")
local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt", true)
truthy(prompt ~= nil, "with a ProximityPrompt")
do
	local n, all = 0, 0
	for _, f in towers:GetChildren() do
		all += 1
		if f:FindFirstChild("TopBoard") then n += 1 end
	end
	eq(n, all, "every tower has its board (" .. n .. " of " .. all .. ")")
end
if board then
	local hrp = A.Character:FindFirstChild("HumanoidRootPart")
	local at = hrp.Position
	local flat = Vector3.new(board.Position.X - at.X, 0, board.Position.Z - at.Z).Magnitude
	truthy(flat <= 32, string.format("near spawn: %.1f studs from where Ava spawned", flat))
	local look = board.CFrame.LookVector
	local toSpawn = Vector3.new(at.X - board.Position.X, 0, at.Z - board.Position.Z)
	local cos = (look.X * toSpawn.X + look.Z * toSpawn.Z) / math.max(toSpawn.Magnitude, 1e-6)
	truthy(cos > 0.95, string.format("its front face (where the board is drawn) faces the spawn (cos %.2f)", cos))
	truthy(math.abs(look.Y) < 0.01, "and stands upright")
	local lane = laneOf(A)
	local lobby = lane:FindFirstChild("LobbyPad")
	local top = lobby.Position.Y + lobby.Size.Y / 2
	local bottom = board.Position.Y - board.Size.Y / 2
	truthy(math.abs(bottom - top) < 0.6, string.format("standing on the lobby pad (bottom %.2f, pad top %.2f)", bottom, top))
	truthy(math.abs(board.Position.X - lobby.Position.X) + board.Size.X / 2 <= lobby.Size.X / 2 + 0.5
		and math.abs(board.Position.Z - lobby.Position.Z) <= lobby.Size.Z / 2,
		"and inside the lobby pad's footprint, so it sits in nobody's corridor")
	-- it never stands where a fork or a section is, and the fork's own prompt never meets its prompt
	local pad = lane.Fork_1.ForkPad_1
	truthy(board.Position.Z + board.Size.Z < pad.Position.Z - pad.Size.Z / 2 - 4,
		string.format("behind floor 1's fork pad, clear of it by more than 4 studs (board z %.1f, pad from z %.1f)",
			board.Position.Z, pad.Position.Z - pad.Size.Z / 2))
	if prompt then
		eq(prompt.Enabled, true, "the prompt is enabled")
		eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
		truthy(#(prompt.ActionText or "") > 0, "and it says what it does (" .. tostring(prompt.ActionText) .. ")")
		eq(prompt.HoldDuration, 0, "a tap, not a hold")
		local promptAt = prompt.Parent:IsA("Attachment") and prompt.Parent.WorldPosition or board.Position
		local fromSpawn = (promptAt - at).Magnitude
		truthy(fromSpawn > bc.PromptDistance + 4, string.format(
			"out of reach where Ava spawns (%.1f studs): it appears when she walks to the board, never over the read", fromSpawn))
		local les = pad:FindFirstChildOfClass("ProximityPrompt")
		if les then
			local d = (promptAt - pad.Position).Magnitude
			truthy(d > bc.PromptDistance + les.MaxActivationDistance, string.format(
				"and no spot is in reach of both the board's prompt and floor 1's read (%.1f > %.0f + %.0f)",
				d, bc.PromptDistance, les.MaxActivationDistance))
		end
	end
end

--======================================================================= 3. the stored value, and ties

h:advance(Config.Save.AutosaveSeconds + 1)
local function stored(uid) return lb.__data["u_" .. uid] end
local function decode(v) if Board and type(v) == "number" then return Board.decode(v) end return nil, nil end
eq(stored(502), enc(40, 1770000000), "Bo's saved best (40, reached 1770000000) is stored encoded")
eq(stored(506), enc(40, 1780000000), "Eli's too (the same 40, reached LATER)")
eq(stored(503), enc(52, 1785000000), "and Cy's (52)")
eq(stored(509), enc(45, 1750000000), "Ned's 45 on the board is never lowered to his profile's 30")
eq(sets, 0, "the board is never written with SetAsync (it would overwrite a higher value)")
do
	local m, t = decode(stored(504))
	eq(m, 33, "a save from before bestScoreAt existed still gets on the board (Dee, 33)")
	truthy(t ~= nil and math.abs(t - joinedAt) <= 10, "stamped with the session it came back in (" .. tostring(t) .. " vs " .. joinedAt .. ")")
end
eq(stored(501), nil, "Ava has not summited: she is not on the board")

local boardRemote = remotes:FindFirstChild("Board")
truthy(boardRemote ~= nil, "a Board remote exists")
local function lastView(plr)
	if not boardRemote then return nil end
	local sent = boardRemote:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
h:advance(bc.PublicCacheSeconds + 1) -- the next public refresh sees the new values
do
	local pub = lastView(A)
	truthy(pub ~= nil and pub.mode == "public", "Ava's board starts on the PUBLIC view")
	if pub then
		local order = {}
		for _, r in pub.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier) .. ":" .. tostring(r.name)) end
		eq(table.concat(order, " "), "505:55:User_505 503:52:Cy 509:45:Ned 502:40:Bo 506:40:Eli 504:33:Dee 508:25:User_508",
			"public view: highest first, Bo above Eli on the same 40 (he got there first), names resolved")
	end
end

--======================================================================= 4. the player path: earn, spend, climb, summit

local stateEvent = remotes:FindFirstChild("State")
local function stateOf(plr)
	local sent = stateEvent:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
local function standOn(plr, part)
	local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0))
	hrp.AssemblyLinearVelocity = Vector3.zero
end
local function read(plr, lane, level)
	local pad = lane:FindFirstChild("Fork_" .. level):FindFirstChild("ForkPad_" .. level)
	standOn(plr, pad)
	local p = pad:FindFirstChildOfClass("ProximityPrompt")
	p.PromptButtonHoldBegan:Fire(plr)
	h:advance(Config.Fork.ReadSeconds + 0.05)
	p.Triggered:Fire(plr)
	h:advance(0.1)
	local fork = lane:FindFirstChild("Fork_" .. level)
	local m1 = fork:FindFirstChild("Door_" .. level .. "_1"):GetAttribute("Marked")
	if m1 == nil then return nil end
	local marked = if m1 == true then 1 else 2
	return if pad:GetAttribute("RuleInverted") == true then 3 - marked else marked
end
local function climbFloor(plr, lane, level, door)
	local fork = lane:FindFirstChild("Fork_" .. level)
	fork:FindFirstChild("Door_" .. level .. "_" .. door):FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	h:advance(0.2)
	for _, c in lane:FindFirstChild("Section_" .. level):GetChildren() do
		if c:GetAttribute("Exit") == true then standOn(plr, c) end
	end
	for _ = 1, 100 do
		if lane:FindFirstChild("Fork_" .. (level + 1)) ~= nil or lane:FindFirstChild("Summit") ~= nil then break end
		h:advance(0.1)
	end
end

local writesAtClimb = writes -- the other players' boards were all written in section 3
local skipsBefore = (stateOf(A) or {}).skips or 0
local redeemed = remotes:FindFirstChild("Redeem"):simulateInvokeServer(A, "FORK")
truthy(type(redeemed) == "table" and redeemed.ok == true, "earn: Ava redeems the public code FORK")
h:advance(0.5)
eq((stateOf(A) or {}).skips, math.min(skipsBefore + Config.Codes.FORK.skips, Config.Skips.MaxSkips),
	"and has one more skip (" .. skipsBefore .. " -> " .. tostring((stateOf(A) or {}).skips) .. ")")

local laneA = laneOf(A)
local summitAt = nil
do
	local trap1 = read(A, laneA, 1)
	truthy(trap1 ~= nil, "set-up: floor 1 read, the trap door known")
	remotes:FindFirstChild("ArmSkip"):simulateFireServer(A, true)
	h:advance(0.5)
	climbFloor(A, laneA, 1, trap1 or 1) -- spend: straight into the trap with the skip armed
	local sec = laneA:FindFirstChild("Section_1")
	eq(sec and sec:GetAttribute("Penalty"), false, "spend: the armed skip turned floor 1's trap into a normal section")
	eq((stateOf(A) or {}).skips, math.min(skipsBefore + Config.Codes.FORK.skips, Config.Skips.MaxSkips) - 1, "and the skip is spent")
	for level = 2, Config.Tower.Floors do
		local trap = read(A, laneA, level)
		climbFloor(A, laneA, level, 3 - (trap or 2))
	end
	summitAt = os.time()
	truthy(laneA:FindFirstChild("Summit") ~= nil, "Ava climbed all ten floors to the summit through the real prompts and exits")
end
local reveal = remotes:FindFirstChild("Reveal"):sentTo(A)
local card = reveal[#reveal] and reveal[#reveal].args[1]
truthy(card ~= nil and card.banked == true and type(card.score) == "number" and card.score > 0,
	"the summit's Build Reveal card is banked (score " .. tostring(card and card.score) .. ")")
local score = card and card.score or 0
-- Eve (offline, 55, reached in 2025) is row 1 unless Ava's run beat 55 (real runs score 19-57, Build.spec; a tie
-- stays Eve's: she reached it first)
local eveRank = if score > 55 then 2 else 1
eq(A.leaderstats.Best.Value, score, "the public leaderstat Best shows it")

--======================================================================= 5. written only when it improves

do
	-- the summit saves at once unless a save landed in the last SaveMinInterval, so the write lands at the summit
	-- or at the next autosave: counted from before the climb
	h:advance(Config.Save.AutosaveSeconds + 1)
	local writesBefore = writesAtClimb
	eq(writes, writesBefore + 1, "a new best score: exactly one board write, at the summit's save or the next autosave")
	local m, t = decode(stored(501))
	eq(m, score, "the board now holds Ava's score")
	truthy(t ~= nil and summitAt ~= nil and math.abs(t - summitAt) <= 10,
		"stamped when she reached it (" .. tostring(t) .. " vs " .. tostring(summitAt) .. ")")
	h:advance(2 * Config.Save.AutosaveSeconds + 1)
	eq(writes, writesBefore + 1, "and two more autosaves write nothing more")
end

--======================================================================= 6. the public list is cached ~60 s

do
	local s0 = sorted
	h:advance(180)
	local n = sorted - s0
	print(string.format("  public top 10: %d GetSortedAsync calls in 180 s", n))
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 180 s (one per " .. bc.PublicCacheSeconds .. " s)")
	local lbRemote = remotes:FindFirstChild("Leaderboard")
	local sent = lbRemote:sentTo(A)
	local top = sent[#sent] and sent[#sent].args[1]
	truthy(type(top) == "table" and top[1] ~= nil, "the HUD's top list is sent")
	if top and top[1] then
		eq(top[eveRank] and top[eveRank].score, 55, "HUD row " .. eveRank .. " is Eve's 55, decoded")
		eq(top[eveRank] and top[eveRank].name, "User_505", "with its name, from the server")
		local maxScore, mine = 0, nil
		for _, e in top do
			maxScore = math.max(maxScore, e.score or 0)
			if e.userId == 501 then mine = e end
		end
		truthy(maxScore < 1000, "no HUD row carries a raw stored value (max " .. maxScore .. ")")
		truthy(mine ~= nil and mine.score == score and mine.name == "Ava", "Ava's own row is on the HUD's list with her score")
	end
end

-- Names are looked up by the SERVER, once per user per server, and sent with the rows. The emulator will not
-- let a check wrap a Players method, so the count is read off the shipped sources: no client looks a name up
-- (the HUD used to call GetNameFromUserIdAsync for every row on every refresh), and the server calls it in one
-- place, behind its cache. The behaviour half is section 11: the HUD shows a name only the server could know.
do
	local bundle = require("./build/fork-tower")
	local function count(key, needle)
		local entry = bundle[key]
		if not entry then return -1 end
		local n = 0
		for line in string.gmatch(entry.source .. "\n", "([^\n]*)\n") do
			local code = string.gsub(line, "%-%-.*$", "") -- comments may name it; code may not
			for _ in string.gmatch(code, needle) do n += 1 end
		end
		return n
	end
	eq(count("client/Hud.client", "GetNameFromUserIdAsync"), 0, "the HUD never looks a name up itself")
	eq(count("client/Board.client", "GetNameFromUserIdAsync"), 0, "nor does the board's client")
	eq(count("server/Main.server", "GetNameFromUserIdAsync"), 1, "the server does, in one place")
	local main = bundle["server/Main.server"] and bundle["server/Main.server"].source or ""
	truthy(string.find(main, "nameCache%[userId%] = res") ~= nil, "and remembers what it got (nameCache)")
end

--======================================================================= 7. the physical board, drawn by Ava's client

local function boardTexts(b)
	local gui = b and b:FindFirstChildWhichIsA("SurfaceGui", true)
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
	local texts, gui = boardTexts(boardOf(A))
	truthy(gui ~= nil, "Ava's client draws a SurfaceGui on her board")
	truthy(gui == nil or gui.Face == Enum.NormalId.Front, "on its front face")
	truthy(A.PlayerGui:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "not in PlayerGui (the HUD fit check measures everything there as screen)")
	truthy(has(texts, "OFFENTLIG") ~= nil, "the board says OFFENTLIG (public)")
	local row1 = has(texts, eveRank .. ". User_505")
	truthy(row1 ~= nil and string.find(row1, "55", 1, true) ~= nil, "row " .. eveRank .. ": User_505, 55 (" .. tostring(row1) .. ")")
	local mine = has(texts, "Ava")
	truthy(mine ~= nil and string.find(mine, tostring(score), 1, true) ~= nil, "Ava's own row shows her score (" .. tostring(mine) .. ")")
	local rarity = Config.Build.Rarities[1].name
	for i, r in Config.Build.Rarities do if score >= r.threshold then rarity = Config.Build.Rarities[i].name end end
	truthy(mine ~= nil and string.find(mine, rarity, 1, true) ~= nil, "and its rarity (" .. rarity .. ")")
	local other = boardOf(B)
	local otherTexts, otherGui = boardTexts(other)
	truthy(otherGui == nil or #otherTexts == 0, "Ava's client draws on her own board only, not on Bo's")
end

--======================================================================= 8. friends: on demand, cached, per player

eq(friendCalls[501], nil, "no friends were fetched before anyone asked")
local readsBefore = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(2)
eq(friendCalls[501], 1, "the prompt fetches Ava's friends once")
do
	local fv = lastView(A)
	truthy(fv ~= nil and fv.mode == "friends", "Ava's board is now FRIENDS")
	if fv then
		-- Eve 55, Bo 40, Gus 25, Finn never summited; Ava's own row ranked among them by her score and time
		local expect = Board and Board.rank({
			{ userId = 505, value = enc(55, 1760000000) }, { userId = 502, value = enc(40, 1770000000) },
			{ userId = 508, value = enc(25, 1765000000) }, { userId = 501, value = stored(501) or 0 },
		}, 10) or {}
		local want, got = {}, {}
		for _, e in expect do table.insert(want, tostring(e.userId) .. (if e.userId == 501 then "*" else "")) end
		for _, r in fv.rows do table.insert(got, tostring(r.userId) .. (if r.you then "*" else "")) end
		eq(table.concat(got, " "), table.concat(want, " "), "friends view: Eve, Bo, Gus and Ava (marked), by score, earliest on a tie; Finn never summited")
		eq(fv.note, nil, "all four friends checked: no note")
	end
end
do
	local newReads = {}
	for i = readsBefore + 1, #reads do table.insert(newReads, reads[i]) end
	table.sort(newReads)
	eq(table.concat(newReads, ","), "u_505,u_507,u_508", "the scores read are the three friends NOT in this server (Bo's comes from memory)")
end
do
	local texts = boardTexts(boardOf(A))
	truthy(has(texts, "VENNER") ~= nil, "the board says VENNER (friends)")
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

--======================================================================= 9. empty friends boards say something useful

local function friendsNoteFor(name, uid)
	local p = joinAs(name, uid)
	local pr = boardOf(p) and boardOf(p):FindFirstChildWhichIsA("ProximityPrompt", true)
	if pr then pr.Triggered:Fire(p) end
	h:advance(3)
	local v = lastView(p)
	return v and v.note, v
end
do
	local noFriends = friendsNoteFor("Hal", 510)
	eq(noFriends, bc.Text.NoFriends, "no friends: says friends you add show up here")
	local noScores = friendsNoteFor("Ida", 511)
	eq(noScores, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 1), "friends who never summited: says so, and invites")
	local failedNote, fview = friendsNoteFor("Jon", 512)
	eq(failedNote, bc.Text.FriendsFailed, "the friends call fails: says try again, no crash")
	eq(fview and fview.mode, "friends", "and still shows the friends view")
end

--======================================================================= 10. capped at 200 and throttled

do
	local readsAt = #reads
	local advancedAt = pagesAdvanced
	local p = joinAs("Kim", 513)
	local pr = boardOf(p) and boardOf(p):FindFirstChildWhichIsA("ProximityPrompt", true)
	if pr then pr.Triggered:Fire(p) end
	h:advance(1)
	local early = #reads - readsAt
	truthy(early <= bc.ReadsBurst + 2, "450 friends: at most the burst is read at once (" .. early .. " in the first second)")
	local mid = lastView(p)
	truthy(mid and mid.note and string.find(mid.note, "av 200", 1, true) ~= nil, "the board says how far it has got (" .. tostring(mid and mid.note) .. ")")
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
	eq(done and done.note, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 200), "then the note says none of the 200 has summited")
end

--======================================================================= 11. Ava's board stayed Ava's; the HUD uses the server's names

do
	local texts = boardTexts(boardOf(A))
	truthy(has(texts, "VENNER") ~= nil and has(texts, "Eve") ~= nil and has(texts, "Pal") == nil,
		"Ava's board still shows Ava's friends, not the views sent to other players")
	h:advance(bc.PublicCacheSeconds + 1)
	local hudRoot = A.PlayerGui:FindFirstChild("ForkHud")
	local drawer = hudRoot and hudRoot:FindFirstChild("Leaderboard", true)
	truthy(drawer ~= nil, "set-up: the HUD's top-list drawer (ForkHud ... Leaderboard)")
	local row1 = nil
	for _, d in (if drawer then drawer:GetDescendants() else {}) do
		if d:IsA("TextLabel") and string.match(d.Text or "", "^" .. eveRank .. "%. ") then row1 = d.Text end
	end
	truthy(row1 ~= nil and string.find(row1, "Eve", 1, true) ~= nil and string.find(row1, "55", 1, true) ~= nil,
		"the HUD's top list shows the server's name and the decoded score for Eve's row (" .. tostring(row1) .. ")")
end

--======================================================================= 12. leave, rejoin, rebirth

do
	h:leave(A)
	h:advance(2)
	local back = joinAs("Ava", 501)
	h:advance(1)
	local s = stateOf(back)
	eq(s and s.stage, "summit", "rejoin: Ava is back at the summit")
	eq(s and s.bestScore, score, "with her best score")
	eq(back.leaderstats.Topper.Value, 1, "and her summit counted")
	local rl = spawnOf(back)
	truthy(rl ~= nil and rl.Parent == laneOf(back), "and her RespawnLocation is her new tower's own LaneSpawn")
	local m = decode(stored(501))
	eq(m, score, "the board still holds her score after the rejoin")
	local writesBefore = writes
	h:advance(2 * Config.Save.AutosaveSeconds + 1)
	eq(writes, writesBefore, "and the rejoin does not write it again (the last written score is saved with the profile)")
	h:advance(1)
	local texts = boardTexts(boardOf(back))
	truthy(#texts > 0, "her client draws on her new tower's board after the rejoin")
	-- rebirth: the lane is torn down and rebuilt, the board with it
	local oldBoard = boardOf(back)
	remotes:FindFirstChild("Rebirth"):simulateFireServer(back)
	h:advance(1)
	local newBoard = boardOf(back)
	truthy(newBoard ~= nil and newBoard ~= oldBoard, "after a rebirth her new tower has a new board")
	local rl2 = spawnOf(back)
	truthy(rl2 ~= nil and rl2.Parent == laneOf(back), "and her RespawnLocation follows her to the new tower")
	local texts2 = boardTexts(newBoard)
	truthy(#texts2 > 0 and has(texts2, "Ava") ~= nil, "her client redraws the board on the new tower (" .. #texts2 .. " lines)")
	A = back
end

--======================================================================= 13. a full server: the waiting spawn

do
	local fillers, waiting = {}, nil
	for i = 1, 40 do
		local p = h:join("Fill" .. i, 30000 + i)
		h:advance(0.2)
		if laneOf(p) == nil then waiting = p; break end
		table.insert(fillers, p)
	end
	truthy(waiting ~= nil, "set-up: a server with every tower taken leaves the next player waiting")
	if waiting then
		local rl, why = spawnOf(waiting)
		truthy(rl ~= nil and rl == waitingSpawn, "a waiting player's RespawnLocation is the enabled WaitingSpawn (" .. why .. ")")
		h:leave(fillers[1])
		h:advance(1)
		local rl2 = spawnOf(waiting)
		truthy(laneOf(waiting) ~= nil and rl2 ~= nil and rl2.Parent == laneOf(waiting),
			"when a tower frees up and they are seated, it becomes their own LaneSpawn")
	end
end

--======================================================================= 14. names are never stored

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
for _, w in h.warnings do
	if not string.find(w, "ingen ledig bane", 1, true) then
		print("warning: " .. w)
		failed += 1
	end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("fork tower board: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("fork tower board check failed", 0)
end
