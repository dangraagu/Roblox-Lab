-- Deep Vein — the highscore board, public + friends, on a physical board in every miner's mouth.
-- Run:  py -3 wrap.py --game ../deep-vein --out build/deep-vein.luau
--       luau check_deepvein_board.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot
-- inflate, ties to whoever reached it FIRST; OrderedDataStore key u_<userId>, value
-- metric * 2e9 + (2e9 - reachedAtUnix), written only when the metric improves; the public top 10 cached ~60 s;
-- friends via Players:GetFriendsAsync, capped at 200, fetched only on demand, cached, pcall'd and throttle-safe;
-- a physical board near spawn with a ProximityPrompt that toggles Public/Friends; names resolved and cached,
-- never stored; an empty friends board says something useful.
--
-- Deep Vein's metric is the deepest LAYER a miner has opened (bestLayer). Each miner spawns in their own mouth,
-- 160 studs from the next, inside bedrock walls they cannot climb, so "near spawn" is a board of their own on
-- the mouth's south wall, the wall they face when they spawn. Built after +1 Jump's check_plus1jump_board.luau;
-- everything is driven through the REAL server and the real Board.client. The emulator has no
-- Players:GetFriendsAsync, so this file supplies one (FriendPages-shaped) and counts the calls.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/deep-vein"), name = "deep-vein", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players
local SrcConfig = require("../deep-vein/src/shared/Config")
local Mine = require("../deep-vein/src/shared/Mine")

-- saved profiles, before the server starts
local profilesStore = DSS:GetDataStore(SrcConfig.Save.Store)
local function seed(uid, d)
	local full = { cash = 0, totalCash = 0, inventory = {}, pickTier = 1, backpackLevel = 0, lampLevel = 0,
		rebirths = 0, depthLayer = 0, bestLayer = 0 }
	for k, v in d do full[k] = v end
	profilesStore:SetAsync("u_" .. uid, { data = full })
end
seed(501, { bestLayer = 12, bestAt = 1780000000 }) -- Ava
seed(502, { bestLayer = 12, bestAt = 1770000000 }) -- Bo: the same depth, reached EARLIER
seed(503, { bestLayer = 30, bestAt = 1785000000 }) -- Cy
seed(504, { bestLayer = 9 }) -- Dee: saved before 2026-10-01, no bestAt
seed(509, { bestLayer = 15, bestAt = 1775000000 }) -- Ned: the board already holds 25 for him
-- Gil digs during this check: the known (old public) rebirth-0 cave, so the dig is the same every run
seed(507, { bestLayer = 1, bestAt = 1760000000, caveKey = Mine.legacyKey(SrcConfig, 0) })

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local boardModule = RS:FindFirstChild("Board")
local Board = boardModule and h:_require(boardModule)
local bc = Config.Board
truthy(type(bc) == "table" and type(Board) == "table", "Config.Board and the Board module exist")
bc = bc or { Text = {}, PublicRows = 10, FriendsRows = 10, ReadsBurst = 40, ReadsPerSecond = 1, FriendsCap = 200,
	PublicCacheSeconds = 60, PromptDistance = 16 }
local S = Config.Mine.CellSize

local lb = DSS:GetOrderedDataStore(Config.Save.Leaderboard)
-- offline miners already on the board
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

local remotes = RS:FindFirstChild("VeinRemotes")
local ToastEvent = remotes:FindFirstChild("Toast")
local boardRemote = remotes:FindFirstChild("Board")
truthy(boardRemote ~= nil, "a Board remote exists")
local function lastView(plr)
	if not boardRemote then return nil end
	local sent = boardRemote:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
local function lastToast(plr)
	local sent = ToastEvent:sentTo(plr)
	local rec = sent[#sent]
	return rec and tostring(rec.args[1]) or ""
end

h.game:GetService("RunService"):setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	h:advance(1)
	h.Players:simulateSpawn(p, h.workspace)
	h:advance(1)
	return p
end
local B = joinAs("Bo", 502)
local C = joinAs("Cy", 503)
local D = joinAs("Dee", 504)
local joinedAt = os.time()
local N = joinAs("Ned", 509)
local G = joinAs("Gil", 507)
local A = joinAs("Ava", 501) -- last: the client scripts below are Ava's
assert(h:tryRun("client/Hud.client"))
local okClient, errClient = h:tryRun("client/Board.client")
truthy(okClient, "Board.client loads (" .. tostring(errClient) .. ")")
h:advance(1)

--======================================================================= 1. the board in every miner's mouth

local boards = h.workspace:FindFirstChild("DeepBoards")
truthy(boards ~= nil, "workspace.DeepBoards holds the miners' boards")
local function boardOf(plr)
	return boards and boards:FindFirstChild("DeepestBoard_" .. plr.UserId)
end
local function deckOf(plr)
	return h.workspace:FindFirstChild("SurfaceDeck_" .. plr.UserId, true)
end
local function promptOf(plr)
	local b = boardOf(plr)
	return b and b:FindFirstChildWhichIsA("ProximityPrompt", true)
end
for _, plr in { A, B, C, D, N, G } do
	local b = boardOf(plr)
	truthy(b ~= nil and b:IsA("BasePart"), plr.Name .. " has a board of their own")
end
local board = boardOf(A)
local prompt = promptOf(A)
truthy(prompt ~= nil, "Ava's board carries a ProximityPrompt")
do
	local deck = deckOf(A)
	local hrp = A.Character and A.Character:FindFirstChild("HumanoidRootPart")
	if board and deck and hrp then
		-- the spawn is where `place` puts the miner: over the deck, facing south (+Z)
		local spawnAt = Vector3.new(deck.Position.X, hrp.Position.Y, deck.Position.Z)
		local rel = board.Position - spawnAt
		local inner = (Config.Mine.GridW - 2) * S / 2 -- 21: the walls' inner faces
		local centreX = deck.Position.X -- the deck sits on the mouth's centre line
		truthy(math.abs(board.Position.X - centreX) + board.Size.X / 2 <= inner,
			string.format("inside Ava's own mouth on X (%.1f +- %.1f, walls at +-%.0f)", board.Position.X - centreX, board.Size.X / 2, inner))
		truthy(board.Position.Z + board.Size.Z / 2 < inner and board.Position.Z > inner - 2,
			string.format("hung on the south wall, in front of its face (z %.2f..%.2f, the face at %.0f)",
				board.Position.Z - board.Size.Z / 2, board.Position.Z + board.Size.Z / 2, inner))
		truthy(board.Position.Y - board.Size.Y / 2 >= 0, "above the mouth floor (bottom at " .. (board.Position.Y - board.Size.Y / 2) .. ")")
		truthy(board.Position.Y + board.Size.Y / 2 < (Config.Mine.RimCells - 1) * S + S / 2,
			"below the rim top, under the pithead (top at " .. (board.Position.Y + board.Size.Y / 2) .. ")")
		local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
		print(string.format("  Ava's board: centre %.2f, %.2f, %.2f (mouth-local), %.2f studs ahead of the spawn",
			board.Position.X - deck.Position.X, board.Position.Y, board.Position.Z, flat))
		truthy(flat <= 2 * inner + 2, string.format("near spawn: across the room the miner spawns in (%.1f studs)", flat))
		local look = board.CFrame.LookVector
		local cos = -(look.X * rel.X + look.Z * rel.Z) / math.max(flat, 1e-6)
		truthy(cos > 0.95, string.format("its front face (where the board is drawn) faces the spawn (cos %.2f)", cos))
		local spawnLook = hrp.CFrame.LookVector
		local inView = (spawnLook.X * rel.X + spawnLook.Z * rel.Z) / math.max(flat, 1e-6)
		truthy(inView > 0.95, string.format("and it is straight ahead of a freshly spawned miner (cos %.2f)", inView))
		eq(board.CanQuery, false, "it never takes a click meant for the rock (CanQuery false)")
		-- it overlaps no cell, pad or deck of the mine: nothing the game builds shares its space
		local clash = nil
		for _, d in h.workspace:FindFirstChild("Shafts"):GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Shell") == nil then
				local p, s = d.Position, d.Size
				if math.abs(p.X - board.Position.X) < (s.X + board.Size.X) / 2
					and math.abs(p.Y - board.Position.Y) < (s.Y + board.Size.Y) / 2
					and math.abs(p.Z - board.Position.Z) < (s.Z + board.Size.Z) / 2 then
					clash = clash or tostring(d.Name)
				end
			end
		end
		eq(clash, nil, "and it overlaps no block, pad or deck of the mine")
	end
	-- every miner's board is in their own mouth, not a neighbour's
	local wrong = nil
	for _, plr in { A, B, C, D, N, G } do
		local b, dk = boardOf(plr), deckOf(plr)
		if b and dk and math.abs(b.Position.X - dk.Position.X) > 0.01 then wrong = wrong or plr.Name end
	end
	eq(wrong, nil, "every board hangs over its own miner's mouth")
end
if prompt then
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
	truthy(#prompt.ActionText > 0, "it says what it does (" .. prompt.ActionText .. ")")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
	local at = prompt.Parent
	local deck = deckOf(A)
	if at and at:IsA("Attachment") and deck and board then
		local where = board.CFrame:PointToWorldSpace(at.Position)
		-- a miner standing in the mouth's south row, and one a cell below it (that floor dug out)
		local southRow = Vector3.new(deck.Position.X, 4, (8 - Mine.center(Config)) * S)
		local dugBelow = southRow - Vector3.new(0, S, 0)
		local midRoom = Vector3.new(deck.Position.X, 4, (6 - Mine.center(Config)) * S)
		print(string.format("  the prompt: %.1f studs from the south row, %.1f from the cell dug below it, %.1f from mid south half, %.1f from the spawn",
			(where - southRow).Magnitude, (where - dugBelow).Magnitude, (where - midRoom).Magnitude,
			(where - Vector3.new(deck.Position.X, 4, deck.Position.Z)).Magnitude))
		truthy((where - southRow).Magnitude <= bc.PromptDistance, string.format("reachable from the mouth's south row (%.1f studs)", (where - southRow).Magnitude))
		truthy((where - dugBelow).Magnitude <= bc.PromptDistance, string.format("and from the cell dug out below it (%.1f)", (where - dugBelow).Magnitude))
		truthy((where - midRoom).Magnitude <= bc.PromptDistance, string.format("and from the middle of the south half (%.1f)", (where - midRoom).Magnitude))
	end
end

--======================================================================= 2. the stored value, and ties

h:advance(Config.Save.AutosaveSeconds + 1)
local function stored(uid) return lb.__data["u_" .. uid] end
local function decode(v) if Board and type(v) == "number" then return Board.decode(v) end return nil, nil end
table.clear(reads)
eq(stored(501), Board and Board.encode(12, 1780000000, bc), "Ava's saved best (layer 12, reached 1780000000) is stored encoded")
eq(stored(502), Board and Board.encode(12, 1770000000, bc), "Bo's too (12, reached EARLIER)")
eq(stored(503), Board and Board.encode(30, 1785000000, bc), "and Cy's (30)")
eq(stored(509), Board and Board.encode(25, 1750000000, bc), "Ned's 25 on the board is never lowered to his profile's 15")
do
	local m, t = decode(stored(504))
	eq(m, 9, "a save from before bestAt existed still gets on the board (Dee, 9)")
	truthy(t ~= nil and math.abs(t - joinedAt) <= 5, "stamped with the session it came back in (" .. tostring(t) .. " vs " .. joinedAt .. ")")
end

h:advance(bc.PublicCacheSeconds + 1) -- the next public refresh sees the new values
local pub = lastView(A)
truthy(pub ~= nil and pub.mode == "public", "Ava's board starts on the PUBLIC view")
if pub then
	local order = {}
	for _, r in pub.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier) .. ":" .. tostring(r.name)) end
	eq(table.concat(order, " "), "505:50:User_505 503:30:Cy 509:25:Ned 508:20:User_508 502:12:Bo 501:12:Ava 504:9:Dee 507:1:Gil",
		"public view: deepest first, Bo above Ava on the same layer (he got there first), names resolved")
end

--======================================================================= 3. written only when it deepens

local writesBefore = writes
h:advance(2 * Config.Save.AutosaveSeconds + 1)
eq(writes, writesBefore, "two autosaves with no new best depth write nothing to the board")
do
	-- Gil digs, honestly: stand on the deepest block in his shaft and swing until his best passes layer 1
	local gShaft = nil
	for _, f in h.workspace:FindFirstChild("Shafts"):GetChildren() do
		if f:FindFirstChild("SellPad_" .. G.UserId, true) then gShaft = f end
	end
	local hrp = G.Character:FindFirstChild("HumanoidRootPart")
	local deepenedAt, swings = nil, 0
	while deepenedAt == nil and swings < 400 do
		local best, bestLayer = nil, -1
		for _, d in gShaft:GetChildren() do
			if d:IsA("BasePart") and d:GetAttribute("CellKey") ~= nil and d:FindFirstChildOfClass("ClickDetector") then
				local L = d:GetAttribute("Layer") or 0
				if L > bestLayer then best, bestLayer = d, L end
			end
		end
		if best == nil then break end
		hrp.CFrame = CFrame.new(best.Position + Vector3.new(0, S, 0))
		best:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(G)
		swings += 1
		h:advance(Config.Mine.SwingCooldown + 0.02)
		if G.leaderstats.Depth.Value > 1 * S then deepenedAt = os.time() end
	end
	local gBest = G.leaderstats.Depth.Value / S
	truthy(deepenedAt ~= nil, string.format("set-up: Gil dug past layer 1 (best layer %d after %d swings)", gBest, swings))
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(writes, writesBefore + 1, "a new best depth: exactly one write at the next save")
	local m, t = decode(stored(507))
	eq(m, gBest, "the board now holds Gil's new best layer (" .. tostring(m) .. ")")
	truthy(t ~= nil and deepenedAt ~= nil and math.abs(t - deepenedAt) <= 2,
		"stamped when he reached it (" .. tostring(t) .. " vs " .. tostring(deepenedAt) .. ")")
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(writes, writesBefore + 1, "and nothing more after that")
end

--======================================================================= 3b. a script cannot inflate it

do
	-- A client owns its character's physics and can fire every remote with anything. None of that opens a cell:
	-- the depth only grows when the server breaks a block a player could reach from the space they dug.
	local cheat = joinAs("Rex", 514)
	local hrp = cheat.Character:FindFirstChild("HumanoidRootPart")
	local wall = Mine.maxLayer(Config, 0)
	hrp.CFrame = CFrame.new(hrp.Position.X, Mine.floorY(Config, wall) + 4, 0) -- "standing" on the depth wall
	h:advance(2) -- the stream sweep follows the character down
	local elevator = remotes:FindFirstChild("Elevator")
	for _, args in { { "down" }, { "down", 999 }, { "up" } } do
		elevator:simulateFireServer(cheat, table.unpack(args))
		h:advance(0.5)
	end
	for _, junk in { "pickaxe", "depth", 1e9, { layer = 999 } } do
		remotes:FindFirstChild("Buy"):simulateFireServer(cheat, junk)
	end
	remotes:FindFirstChild("Rebirth"):simulateFireServer(cheat, 999)
	h:advance(1)
	-- and there is nothing deep to click: no Part of the cave exists below the mouth's floor
	local deepest = 0
	for _, d in h.workspace:FindFirstChild("Shafts"):GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Owner") == cheat.UserId and d:GetAttribute("CellKey") then
			deepest = math.max(deepest, d:GetAttribute("Layer") or 0)
		end
	end
	eq(cheat.leaderstats.Depth.Value, 0, "a teleported character and forged remotes open no depth (Rex's best stays 0 m)")
	eq(deepest, 1, "and leave nothing below the mouth's floor to swing at (deepest block layer " .. deepest .. ")")
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(stored(514), nil, "so nothing reaches the board for Rex")
end

--======================================================================= 4. the public list is cached ~60 s

do
	local s0 = sorted
	h:advance(180)
	local n = sorted - s0
	print(string.format("  public top 10: %d GetSortedAsync calls in 180 s", n))
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 180 s (one per " .. bc.PublicCacheSeconds .. " s)")
	-- the HUD's top list gets decoded depths (in m) and names, never the stored value
	local lbRemote = remotes:FindFirstChild("Leaderboard")
	local sent = lbRemote:sentTo(A)
	local top = sent[#sent] and sent[#sent].args[1]
	truthy(type(top) == "table" and top[1] ~= nil, "the HUD's top list is sent")
	if top and top[1] then
		eq(top[1].depth, 50 * S, "HUD row 1 is 300 m (layer 50), decoded")
		eq(top[1].name, "User_505", "with its name")
		local maxDepth = 0
		for _, e in top do maxDepth = math.max(maxDepth, e.depth or 0) end
		truthy(maxDepth < 1e6, "no HUD row carries a raw stored value (max " .. maxDepth .. ")")
	end
	-- and the HUD shows the server's name, without looking one up itself
	local hudRoot = A.PlayerGui:FindFirstChild("DeepVeinHud")
	local row1 = nil
	for _, d in hudRoot:GetDescendants() do
		if d:IsA("TextLabel") and string.match(d.Text or "", "^1%. ") then row1 = d.Text end
	end
	truthy(row1 ~= nil and string.find(row1, "User_505", 1, true) ~= nil and string.find(row1, "300m", 1, true) ~= nil,
		"the HUD's top-10 row 1 reads User_505, 300m (" .. tostring(row1) .. ")")
end

--======================================================================= 5. the physical board, drawn by Ava's client

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
	local texts, gui = boardTexts(board)
	truthy(gui ~= nil, "Ava's client draws a SurfaceGui on her board")
	truthy(gui == nil or gui.Face == Enum.NormalId.Front, "on its front face")
	truthy(A.PlayerGui:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "not in PlayerGui (the HUD fit check measures everything there as screen)")
	truthy(has(texts, "PUBLIC") ~= nil, "the board says PUBLIC")
	local row1 = has(texts, "User_505")
	truthy(row1 ~= nil and string.find(row1, "300 m", 1, true) ~= nil, "row 1: User_505, 300 m (" .. tostring(row1) .. ")")
	local mine = has(texts, "Ava")
	truthy(mine ~= nil and string.find(mine, "72 m", 1, true) ~= nil and string.find(mine, "you", 1, true) ~= nil,
		"Ava's own row shows 72 m and that it is hers (" .. tostring(mine) .. ")")
	local _, bosGui = boardTexts(boardOf(B))
	eq(bosGui, nil, "Ava's client draws only on her own board, not on Bo's")
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
	eq(table.concat(order, " "), "505:50 508:20 502:12 501:12*", "friends view: Eve 50, Gus 20, Bo 12 (first there), Ava 12 (you); Finn never dug")
	eq(fv.note, nil, "all four friends checked: no note")
end
do
	local newReads = {}
	for i = readsBefore + 1, #reads do table.insert(newReads, reads[i]) end
	table.sort(newReads)
	eq(table.concat(newReads, ","), "u_505,u_506,u_508", "the scores read are the three friends NOT in this server (Bo's comes from memory)")
end
do
	local texts = boardTexts(board)
	truthy(has(texts, "FRIENDS") ~= nil, "the board says FRIENDS")
	truthy(has(texts, "Eve") ~= nil, "and names Eve (from the friends list, not a stored name)")
end
eq(lastView(B).mode, "public", "Bo's board is still PUBLIC: the toggle is per player")
-- Bo cannot flip Ava's board (her mine is walled off from his, but the server checks anyway)
do
	local toastsBefore = #ToastEvent:sentTo(B)
	if prompt then prompt.Triggered:Fire(B) end
	h:advance(1)
	eq(lastView(A).mode, "friends", "a prompt on Ava's board triggered by Bo does not change Ava's view")
	eq(lastView(B).mode, "public", "nor Bo's")
	eq(friendCalls[502], nil, "and fetches nobody's friends")
	truthy(#ToastEvent:sentTo(B) > toastsBefore and string.find(lastToast(B), "board", 1, true) ~= nil,
		"Bo is told whose board it is (" .. lastToast(B) .. ")")
end
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
	local pr = promptOf(p)
	if pr then pr.Triggered:Fire(p) end
	h:advance(3)
	local v = lastView(p)
	return v and v.note, v, p
end
local hal
do
	local noFriends, _, hp = friendsNoteFor("Hal", 510)
	hal = hp
	eq(noFriends, bc.Text.NoFriends, "no friends: says friends you add show up here")
	local noScores = friendsNoteFor("Ida", 511)
	eq(noScores, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 1), "friends who never dug: says so, and invites")
	local failedNote, fview = friendsNoteFor("Jon", 512)
	eq(failedNote, bc.Text.FriendsFailed, "the friends call fails: says try again, no crash")
	eq(fview and fview.mode, "friends", "and still shows the friends view")
end

--======================================================================= 8. capped at 200 and throttled

do
	local readsAt = #reads
	local advancedAt = pagesAdvanced
	local p = joinAs("Kim", 513)
	local pr = promptOf(p)
	if pr then pr.Triggered:Fire(p) end
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
	eq(done and done.note, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 200), "then the note says none of the 200 has dug")
end

--======================================================================= 8b. Ava's board stayed Ava's; a leaver's board goes

do
	local texts = boardTexts(board)
	truthy(has(texts, "FRIENDS") ~= nil and has(texts, "Eve") ~= nil and has(texts, "Pal") == nil,
		"Ava's board still shows Ava's friends, not the views sent to other players")
	-- the HUD's top list uses the names the SERVER sends: Eve, learnt from Ava's friends list (Board.client and the
	-- HUD never look a name up; a lookup here would say User_505)
	h:advance(bc.PublicCacheSeconds + 1)
	local hudRoot = A.PlayerGui:FindFirstChild("DeepVeinHud")
	local row1 = nil
	for _, d in hudRoot:GetDescendants() do
		if d:IsA("TextLabel") and string.match(d.Text or "", "^1%. ") then row1 = d.Text end
	end
	truthy(row1 ~= nil and string.find(row1, "Eve", 1, true) ~= nil, "the HUD's top list shows the server's name for row 1 (" .. tostring(row1) .. ")")
	local n0 = #boards:GetChildren()
	h:leave(hal)
	h:advance(1)
	eq(boards:FindFirstChild("DeepestBoard_510"), nil, "Hal leaves: his board goes with him")
	truthy(#boards:GetChildren() < n0 and boardOf(A) ~= nil, "and nobody else's does")
end

--======================================================================= 9. names are never stored

do
	local HttpService = h.game:GetService("HttpService")
	local leaked = nil
	for uid, name in { [501] = "Ava", [502] = "Bo", [503] = "Cy", [504] = "Dee", [507] = "Gil" } do
		local rec = profilesStore:GetAsync("u_" .. uid)
		local json = HttpService:JSONEncode(rec)
		if string.find(json, '"' .. name .. '"', 1, true) then leaked = leaked or name end
	end
	truthy(leaked == nil, "no saved profile holds a player's name" .. (if leaked then " (" .. leaked .. ")" else ""))
	local allNumbers = true
	for _, uid in { 501, 502, 503, 504, 505, 507, 508 } do
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
print(string.format("deep vein board: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("deep vein board check failed", 0)
end
