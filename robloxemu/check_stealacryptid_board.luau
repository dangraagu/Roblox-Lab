-- Steal a Cryptid - the Top Lairs board, public + friends. Run: luau check_stealacryptid_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../steal-a-cryptid --out build/steal-a-cryptid.luau
--
-- docs/complete-game-standard.md section 3 (owner, 2026-09-16): rank on a server-measured metric a script cannot
-- inflate, ties to whoever reached it FIRST; OrderedDataStore key u_<userId>, value metric * 2e9 + (2e9 -
-- reachedAtUnix), written only when the metric improves; the public top 10 cached ~60 s; friends via
-- Players:GetFriendsAsync, capped at 200, fetched only on demand, cached, pcall'd and throttle-safe; a physical
-- board near spawn with a ProximityPrompt that toggles Public/Friends; names resolved and cached, never stored; an
-- empty friends board says something useful.
--
-- Steal a Cryptid's metric is the BEST LAIR INCOME a player has ever had (Essence/s), from the server's own profile
-- (Economy.noteBest after a purchase or a steal the server granted). Every player spawns on their own lair's
-- arrival marker, so "near spawn" is a board on every plot, on the front fence beside the gate, behind the Collect
-- Pad. Everything runs through the REAL server and the real Board.client. Built after +1 Jump's
-- check_plus1jump_board.luau. The emulator has no Players:GetFriendsAsync, so this file supplies one
-- (FriendPages-shaped) and counts the calls.

local Harness = require("./emu/harness")
local Datatypes = require("./emu/datatypes")
local Config = require("../steal-a-cryptid/src/shared/Config")
local Economy = require("../steal-a-cryptid/src/shared/Economy")

local h = Harness.new({ bundle = require("./build/steal-a-cryptid"), name = "steal-a-cryptid", viewport = { 1280, 720 }, touch = false })
local inst, sched = h.instance, h.scheduler
local CF, V3 = Datatypes.CFrame, Datatypes.Vector3
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local bc = Config.Board
truthy(type(bc) == "table", "Config.Board exists")
bc = bc or { Text = {}, PublicRows = 10, FriendsRows = 10, ReadsBurst = 40, ReadsPerSecond = 1, FriendsCap = 200,
	PublicCacheSeconds = 60, PromptDistance = 10, MaxMetric = 4000000 }
truthy(type(Config.Save.Board) == "string", "Config.Save.Board names the board's OrderedDataStore")

local NOW = os.time()
local store = DSS:GetDataStore(Config.Save.Store)
local lb = DSS:GetOrderedDataStore(Config.Save.Board or "missing-board-store")

-- the template's formula, written out here so the check does not trust the module it checks
local function encode(metric, at) return metric * 2e9 + (2e9 - at) end
local function decode(v)
	if type(v) ~= "number" then return nil, nil end
	local m = math.floor(v / 2e9 + 0.5)
	return m, 2e9 - (v - m * 2e9)
end

local function cages(fill)
	local out = {}
	for i = 1, 9 do out[i] = { sp = "", jar = 0 } end
	for col, sp in fill do out[col] = { sp = sp, jar = 0 } end
	return out
end
local function seed(uid, d, extra)
	local data = { v = 1, essence = d.essence or 100, savedAt = NOW, cagesUnlocked = 3, tutorial = 4, traps = {},
		heat = { t1 = 0, t2 = 0, t3 = 0, t4 = 0 }, journal = d.journal or {}, cages = cages(d.cages or {}),
		stats = { steals = 0, caught = 0, poachersCaught = 0 }, bestRate = d.bestRate, bestRateAt = d.bestRateAt }
	local rec = { data = data }
	for k, v in extra or {} do rec[k] = v end
	store:SetAsync("u_" .. uid, rec)
end
-- Ava: 5/s now, but her best is 30 (she released her Rares), reached at 1780000000
seed(701, { cages = { [5] = "hodag", [4] = "chupacabra" }, journal = { "hodag", "chupacabra", "dogman" }, bestRate = 30, bestRateAt = 1780000000 })
-- Bo: 30 too, reached EARLIER
seed(702, { cages = { [5] = "dogman", [4] = "jerseydevil" }, journal = { "dogman", "jerseydevil" }, bestRate = 30, bestRateAt = 1770000000 })
-- Cy: a Bigfoot
seed(703, { cages = { [5] = "bigfoot" }, journal = { "bigfoot" }, bestRate = 450, bestRateAt = 1785000000 })
-- Dee: saved before the board existed (no bestRate): a Dogman, 12/s
seed(704, { cages = { [5] = "dogman" }, journal = { "dogman" } })
-- Ned: his profile says 15, the board already holds 25 for him (a session whose profile write was lost)
seed(709, { cages = { [5] = "chupacabra" }, journal = { "chupacabra" }, bestRate = 15, bestRateAt = 1775000000 })
-- Eli: rich and empty-handed, a Common in his Journal so the third pedestal shows a Rare
seed(710, { essence = 100000, journal = { "jackalope" } })
-- Fay: another server holds her record; this server will play her unsaved
seed(711, { cages = { [5] = "dogman" }, journal = { "dogman" }, bestRate = 99, bestRateAt = 1781000000 },
	{ jobId = "some-other-server", lockUntil = NOW + 100 })

-- count what the server does to the board's store
local writes, sorted, reads = 0, 0, {}
do
	local oUpdate, oSet, oSorted, oGet = lb.UpdateAsync, lb.SetAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; return oSet(self, ...) end
	lb.GetSortedAsync = function(self, ...) sorted += 1; return oSorted(self, ...) end
	lb.GetAsync = function(self, key, ...) table.insert(reads, key); return oGet(self, key, ...) end
end
local function stored(uid) return lb.__data["u_" .. uid] end

-- friends, per user id: a list of { Id, Username } (or "error")
local friendsOf = {
	[701] = { { 702, "Bo" }, { 705, "Eve" }, { 706, "Finn" }, { 708, "Gus" } },
	[712] = {},
	[713] = { { 706, "Finn" } },
	[714] = "error",
}
do
	local big = {}
	for i = 1, 450 do table.insert(big, { 20000 + i, "Pal" .. i }) end
	friendsOf[715] = big
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
-- lairs only on the board: Eve 600, Gus 20, and Ned's 25. Written after the boot: the boot's first public refresh
-- would otherwise look Ned's name up before he joins, and this emulator answers User_709 for anyone not in the
-- server (Roblox answers the real name), which the name cache would then keep
lb:SetAsync("u_705", encode(600, 1760000000))
lb:SetAsync("u_708", encode(20, 1765000000))
lb:SetAsync("u_709", encode(25, 1750000000))
local okBoard, Board = pcall(function() return h:_require(RS:FindFirstChild("Board")) end)
truthy(okBoard and type(Board) == "table", "the Board module is in ReplicatedStorage")
h:advance(1)

--======================================================================= 1. a board on every plot, near spawn

local lairs = h.workspace:FindFirstChild("Lairs")
local plotCount = math.max(Config.World.Plots, Players.MaxPlayers)
local function plotFrame(i) return lairs:FindFirstChild("Plot_" .. i).Floor.CFrame * CF.new(-36, 0.5, -48) end
local boards = {}
do
	local missing, far, facing, prompts, badPrompt, blocking, unlit = {}, nil, nil, 0, {}, {}, {}
	for i = 0, plotCount - 1 do
		local plot = lairs:FindFirstChild("Plot_" .. i)
		local board = plot and plot:FindFirstChild("TopLairsBoard")
		if not (board and board:IsA("BasePart") and board:IsDescendantOf(h.workspace)) then
			table.insert(missing, "Plot_" .. i)
		else
			boards[i] = board
			local frame = plotFrame(i)
			local arrival = frame:PointToWorldSpace(V3.new(Config.World.Apron.Arrival.x, 0, Config.World.Apron.Arrival.z))
			local pad = frame:PointToWorldSpace(V3.new(Config.World.Apron.Pad.x, 0, Config.World.Apron.Pad.z))
			local d = math.sqrt((board.Position.X - arrival.X) ^ 2 + (board.Position.Z - arrival.Z) ^ 2)
			if d > 20 then far = far or string.format("Plot_%d %.1f", i, d) end
			-- the drawn face (Front, the part's -Z) looks over the apron: at the Collect Pad, and the arrival marker is in front of it
			local look = board.CFrame.LookVector
			local function cosTo(p)
				local v = V3.new(p.X - board.Position.X, 0, p.Z - board.Position.Z)
				return (look.X * v.X + look.Z * v.Z) / math.max(v.Magnitude, 1e-6)
			end
			if cosTo(pad) < 0.8 or cosTo(arrival) <= 0 then facing = facing or string.format("Plot_%d (pad %.2f, arrival %.2f)", i, cosTo(pad), cosTo(arrival)) end
			-- it stands flush against the front fence, clear of the gate, so it is in nobody's way
			local loc = frame:PointToObjectSpace(board.Position)
			local hz = board.Size.Z / 2
			local hx = board.Size.X / 2
			local gateX0 = Config.World.CellSize * (Config.World.GateCol - 1)
			if loc.Z - hz < Config.World.ApronDepth - 1 or loc.Z + hz > Config.World.ApronDepth + 0.01
				or (loc.X + hx > gateX0 - 1 and loc.X - hx < gateX0 + Config.World.CellSize + 1) then
				table.insert(blocking, string.format("Plot_%d local x %.1f..%.1f z %.1f..%.1f", i, loc.X - hx, loc.X + hx, loc.Z - hz, loc.Z + hz))
			end
			local trim = plot:FindFirstChild("TopLairsTrim")
			if not (trim and trim.Material == Enum.Material.Neon) then table.insert(unlit, "Plot_" .. i) end
			local found = {}
			for _, dd in board:GetDescendants() do if dd.ClassName == "ProximityPrompt" then table.insert(found, dd) end end
			prompts += #found
			local pp = found[1]
			if #found ~= 1 or not (pp.Enabled ~= false and pp.HoldDuration == 0 and pp.MaxActivationDistance == bc.PromptDistance
				and #(pp.ActionText or "") > 0 and pp.RequiresLineOfSight == false) then
				table.insert(badPrompt, "Plot_" .. i)
			elseif i == 0 then
				-- reach: from a root standing on the Collect Pad the prompt is in reach; on the arrival marker it is not,
				-- so the first thing in reach after landing is still P1's Buy (check_stealacryptid section 3)
				local host = pp.Parent
				local at = if host:IsA("Attachment") then host.WorldPosition else host.Position
				local onPad = pad + V3.new(0, Config.World.RootHeight, 0)
				local onArrival = arrival + V3.new(0, Config.World.RootHeight, 0)
				truthy((onPad - at).Magnitude <= pp.MaxActivationDistance,
					string.format("standing on the Collect Pad, the board's prompt is in reach (%.2f of %d studs)", (onPad - at).Magnitude, pp.MaxActivationDistance))
				truthy((onArrival - at).Magnitude > pp.MaxActivationDistance,
					string.format("standing on the arrival marker it is not (%.2f studs): the first thing in reach stays P1", (onArrival - at).Magnitude))
			end
		end
	end
	eq(#missing, 0, string.format("every one of the %d plots has a TopLairsBoard Part in the workspace %s", plotCount, table.concat(missing, ",")))
	truthy(far == nil, "every board is near spawn: within 20 studs of its plot's arrival marker" .. (if far then " (" .. far .. ")" else ""))
	truthy(facing == nil, "every board's drawn face looks over the apron, at the Collect Pad" .. (if facing then " (" .. facing .. ")" else ""))
	eq(#blocking, 0, "every board stands flush on the front fence, clear of the gate and the apron walk " .. table.concat(blocking, "; "))
	eq(#unlit, 0, "every board has a neon trim, so it reads as something to use " .. table.concat(unlit, ","))
	eq(#badPrompt, 0, "every board carries one enabled tap prompt (no hold, reach Config.Board.PromptDistance, no line-of-sight rule) " .. table.concat(badPrompt, ","))
	eq(prompts, plotCount, "one prompt per board")
end
local function promptOf(i)
	local b = boards[i]
	return b and b:FindFirstChildWhichIsA("ProximityPrompt", true)
end

--======================================================================= 2. the stored value, and ties

h.game:GetService("RunService"):setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	Players:simulateSpawn(p, h.workspace)
	return p
end
local B = joinAs("Bo", 702)
local C = joinAs("Cy", 703)
local D = joinAs("Dee", 704)
local N = joinAs("Ned", 709)
local joinedAt = os.time()
local A = joinAs("Ava", 701) -- last: the client script below is Ava's
local okClient, errClient = h:tryRun("client/Board.client")
truthy(okClient, "Board.client loads (" .. tostring(errClient) .. ")")
h:advance(Config.Save.AutosaveSeconds + 1)

eq(stored(701), encode(30, 1780000000), "Ava's saved best (30/s, reached 1780000000) is on the board, encoded")
eq(stored(702), encode(30, 1770000000), "Bo's too (30/s, reached EARLIER)")
eq(stored(703), encode(450, 1785000000), "and Cy's Bigfoot (450/s)")
eq(stored(709), encode(25, 1750000000), "Ned's 25 on the board is never lowered to his profile's 15")
do
	local m, t = decode(stored(704))
	eq(m, 12, "a save from before the board existed gets on it with the income it loaded with (Dee, 12/s)")
	truthy(t ~= nil and math.abs(t - joinedAt) <= 5, "stamped with the session it came back in (" .. tostring(t) .. " vs " .. joinedAt .. ")")
end

local boardRemote = RS:FindFirstChild("CryptidRemotes") and RS.CryptidRemotes:FindFirstChild("Board")
truthy(boardRemote ~= nil and boardRemote.ClassName == "RemoteEvent", "CryptidRemotes.Board is a RemoteEvent")
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
	eq(table.concat(order, " "), "705:600:User_705 703:450:Cy 702:30:Bo 701:30:Ava 709:25:Ned 708:20:User_708 704:12:Dee",
		"public view: highest first, Bo above Ava at 30/s (he got there first), names resolved")
	local maxTier = 0
	for _, r in pub.rows do maxTier = math.max(maxTier, tonumber(r.tier) or 0) end
	truthy(maxTier <= 9 * 450, "no row carries a raw stored value (max " .. maxTier .. ")")
end

--======================================================================= 3. written only when it improves

local writesBefore = writes
h:advance(2 * Config.Save.AutosaveSeconds + 1)
eq(writes, writesBefore, "two autosaves with no new best write nothing to the board")

local E = joinAs("Eli", 710)
h:advance(Config.Save.AutosaveSeconds + 1)
eq(stored(710), nil, "a player who has never had a cryptid is not on the board")
local function lairOfPlayer(plr)
	for i = 0, plotCount - 1 do
		local plot = lairs:FindFirstChild("Plot_" .. i)
		if plot and string.find(tostring(plot.Sign.Label.Text.Text), plr.Name, 1, true) then return plot:FindFirstChild("Lair"), i end
	end
	return nil
end
local stateRemote = RS.CryptidRemotes:FindFirstChild("State")
local function stateOf(plr)
	local sent = stateRemote:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
local lairE = lairOfPlayer(E)
local commonRate, bothRate, rareCol = nil, nil, nil
do
	local w0 = writes
	local buy1 = os.time()
	lairE.Pedestals.Pedestal_1.Buy.Triggered:Fire(E)
	h:advance(Config.Save.FlushTickSeconds + 1)
	commonRate = stateOf(E).rate
	local m, t = decode(stored(710))
	eq(m, commonRate, string.format("a purchase is a new best: the next save puts Eli's %s/s on the board", tostring(commonRate)))
	truthy(t ~= nil and math.abs(t - buy1) <= 5, "stamped when he bought it (" .. tostring(t) .. " vs " .. buy1 .. ")")
	eq(writes, w0 + 1, "with exactly one write")
	h:advance(1)
	local buy3 = os.time()
	lairE.Pedestals.Pedestal_3.Buy.Triggered:Fire(E)
	h:advance(Config.Save.FlushTickSeconds + 1)
	local s = stateOf(E)
	bothRate = s.rate
	for col, c in s.cages do if Economy.tierOf(Config, c.sp) == 2 then rareCol = col end end
	truthy(rareCol ~= nil and bothRate > commonRate, string.format("set-up: the third pedestal's Rare is in a cage (%s/s now)", tostring(bothRate)))
	m, t = decode(stored(710))
	eq(m, bothRate, "a Rare moving in is a new best on the board")
	truthy(t ~= nil and math.abs(t - buy3) <= 5, "stamped at the Rare (" .. tostring(t) .. " vs " .. buy3 .. ")")
	local w1 = writes
	local cage = rareCol and lairE.Cages:FindFirstChild("Cage_" .. rareCol)
	local release = cage and cage:FindFirstChild("Release", true)
	truthy(release ~= nil, "set-up: the Rare's cage has a Release prompt")
	if release then release.Triggered:Fire(E) end
	h:advance(Config.Economy.ReleaseHoldSeconds + 1)
	eq(stateOf(E).rate, commonRate, "set-up: the Rare is released")
	h:advance(Config.Save.AutosaveSeconds + Config.Save.FlushTickSeconds + 1)
	eq(writes, w1, "releasing it writes nothing to the board")
	eq(decode(stored(710)), bothRate, "and the board keeps the best Eli ever had")
end

--======================================================================= 4. the public list is cached ~60 s

do
	local s0 = sorted
	for _ = 1, 6 do
		local pp = promptOf(0)
		if pp then pp.Triggered:Fire(B) end
		h:advance(1)
	end
	eq(sorted, s0, "toggling the board six times asks the store for nothing new (the public list is cached)")
	h:advance(180)
	local n = sorted - s0
	print(string.format("  public top 10: %d GetSortedAsync calls in 186 s", n))
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 186 s (one per " .. bc.PublicCacheSeconds .. " s)")
end

--======================================================================= 5. the physical board, drawn by Ava's client

local function boardTexts(i)
	local b = boards[i]
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
local function rowWith(texts, name)
	-- a row is drawn as a name label and a number label side by side; join each label with the next one
	for i, t in texts do
		if string.find(t, name, 1, true) then return t .. " | " .. tostring(texts[i + 1]) end
	end
	return nil
end
do
	local _, avaPlot = lairOfPlayer(A)
	local texts, gui = boardTexts(avaPlot)
	truthy(gui ~= nil, "Ava's client draws a SurfaceGui on her own plot's board")
	truthy(gui == nil or gui.Face == Enum.NormalId.Front, "on its front face")
	truthy(A.PlayerGui:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "not in PlayerGui (the HUD fit check measures everything there as screen)")
	truthy(has(texts, "TOP LAIRS") ~= nil, "the board is titled TOP LAIRS")
	truthy(has(texts, "PUBLIC") ~= nil, "the board says PUBLIC")
	local row1 = rowWith(texts, "User_705")
	truthy(row1 ~= nil and string.find(row1, "600", 1, true) ~= nil, "row 1: User_705, 600 (" .. tostring(row1) .. ")")
	local mine = rowWith(texts, "Ava")
	truthy(mine ~= nil and string.find(mine, "30", 1, true) ~= nil, "Ava's own row shows 30 (" .. tostring(mine) .. ")")
	local othersDrawn = 0
	for i = 0, plotCount - 1 do
		local t = boardTexts(i)
		if has(t, "User_705") then othersDrawn += 1 end
	end
	eq(othersDrawn, plotCount, "every plot's board shows Ava her view, so the road never shows a blank board")
end

--======================================================================= 6. friends: on demand, cached, per player

eq(friendCalls[701], nil, "no friends were fetched before anyone asked")
local readsBefore = #reads
local pAva = promptOf(0)
if pAva then pAva.Triggered:Fire(A) end
h:advance(2)
eq(friendCalls[701], 1, "the prompt fetches Ava's friends once")
local fv = lastView(A)
truthy(fv ~= nil and fv.mode == "friends", "Ava's board is now FRIENDS")
if fv then
	local order = {}
	for _, r in fv.rows do table.insert(order, tostring(r.userId) .. ":" .. tostring(r.tier) .. (if r.you then "*" else "")) end
	eq(table.concat(order, " "), "705:600 702:30 701:30* 708:20", "friends view: Eve 600, Bo 30 (first), Ava 30 (you), Gus 20; Finn never had a cryptid")
	eq(fv.note, nil, "all four friends checked: no note")
end
do
	local newReads = {}
	for i = readsBefore + 1, #reads do table.insert(newReads, reads[i]) end
	table.sort(newReads)
	eq(table.concat(newReads, ","), "u_705,u_706,u_708", "the scores read are the three friends NOT in this server (Bo's comes from memory)")
end
do
	local _, avaPlot = lairOfPlayer(A)
	local texts = boardTexts(avaPlot)
	truthy(has(texts, "FRIENDS") ~= nil, "the board says FRIENDS")
	truthy(has(texts, "Eve") ~= nil, "and names Eve (from the friends list, not a stored name)")
end
eq(lastView(B).mode, "public", "Bo's board is still PUBLIC: the toggle is per player")
if pAva then pAva.Triggered:Fire(A) end
h:advance(1)
eq(lastView(A).mode, "public", "the prompt again: back to PUBLIC")
local readsMid = #reads
if pAva then pAva.Triggered:Fire(A) end
h:advance(1)
eq(lastView(A).mode, "friends", "and FRIENDS again")
eq(friendCalls[701], 1, "the friends list came from the cache (still 1 fetch)")
eq(#reads, readsMid, "and so did every score (no new reads)")
do
	-- a neighbour's board toggles the presser's own view: the board is everyone's, not the lair owner's
	local pOther = promptOf(3)
	local before = lastView(C).mode
	if pOther then pOther.Triggered:Fire(C) end
	h:advance(2)
	truthy(before == "public" and lastView(C).mode == "friends", "any plot's board toggles the view of whoever pressed it")
	if pOther then pOther.Triggered:Fire(C) end
	h:advance(1)
end

--======================================================================= 7. empty friends boards say something useful

local function friendsNoteFor(name, uid)
	local p = joinAs(name, uid)
	h:advance(1)
	local pp = promptOf(0)
	if pp then pp.Triggered:Fire(p) end
	h:advance(3)
	local v = lastView(p)
	return v and v.note, v
end
do
	local noFriends = friendsNoteFor("Hal", 712)
	eq(noFriends, bc.Text.NoFriends, "no friends: says friends you add show up here")
	local noScores = friendsNoteFor("Ida", 713)
	eq(noScores, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 1), "friends who never had a cryptid: says so, and invites")
	local failedNote, fview = friendsNoteFor("Jon", 714)
	eq(failedNote, bc.Text.FriendsFailed, "the friends call fails: says try again, no crash")
	eq(fview and fview.mode, "friends", "and still shows the friends view")
end

--======================================================================= 8. capped at 200 and throttled

do
	local readsAt = #reads
	local advancedAt = pagesAdvanced
	local p = joinAs("Kim", 715)
	h:advance(1)
	local pp = promptOf(0)
	if pp then pp.Triggered:Fire(p) end
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
	eq(done and done.note, bc.Text.FriendsNoScores and string.format(bc.Text.FriendsNoScores, 200), "then the note says none of the 200 has a cryptid")
end

do
	-- Hal, Ida, Jon and Kim were sent friends views since; this client (Ava's) draws only views addressed to Ava
	local _, avaPlot = lairOfPlayer(A)
	local texts = boardTexts(avaPlot)
	truthy(has(texts, "FRIENDS") ~= nil and has(texts, "Eve") ~= nil and has(texts, "Pal") == nil,
		"Ava's board still shows Ava's friends, not the views sent to other players")
end

--======================================================================= 9. a session that cannot save writes nothing

do
	-- Fay's record is locked by another server: the join waits, then plays unsaved (check_stealacryptid section 8).
	-- That join yields, so it runs on its own thread, as Roblox runs PlayerAdded.
	local pF = inst.Instance.new("Player")
	pF.Name = "Fay"
	pF.UserId = 711
	local pg = inst.Instance.new("PlayerGui")
	pg.Name = "PlayerGui"
	pg.Parent = pF
	pF.Parent = Players
	inst.stateOf(Players).signals["PlayerAdded"]:FireOnThreads(function(fn, ...) return sched:spawn(fn, ...) end, pF)
	h:advance(Config.Save.LockWaitSeconds + 2)
	local sF = stateOf(pF)
	eq(sF and sF.canSave, false, "set-up: Fay plays unsaved")
	h:advance(Config.Save.AutosaveSeconds + Config.Save.FlushTickSeconds + 1)
	eq(stored(711), nil, "a session that does not hold its save's lock writes nothing to the board")
end

--======================================================================= 10. no client can hand the server a number

do
	local before = stored(701)
	local w0 = writes
	for _, r in RS.CryptidRemotes:GetChildren() do
		if r.ClassName == "RemoteEvent" then
			r:simulateFireServer(A, { rate = 4050, bestRate = 4050, tier = 4050 }, 4050, "bigfoot")
			r:simulateFireServer(A, 4050)
		end
	end
	h:advance(Config.Save.AutosaveSeconds + 1)
	eq(stored(701), before, "every remote fired with a huge number: Ava's board value is unchanged")
	eq(writes, w0, "and nothing was written to the board")
end

--======================================================================= 11. names are never stored

do
	local HttpService = h.game:GetService("HttpService")
	local leaked = nil
	for uid, name in { [701] = "Ava", [702] = "Bo", [703] = "Cy", [704] = "Dee", [710] = "Eli" } do
		local rec = store:GetAsync("u_" .. uid)
		local json = HttpService:JSONEncode(rec)
		if string.find(json, '"' .. name .. '"', 1, true) then leaked = leaked or name end
	end
	truthy(leaked == nil, "no saved profile holds a player's name" .. (if leaked then " (" .. leaked .. ")" else ""))
	local allNumbers = true
	for _, uid in { 701, 702, 703, 704, 705, 708, 709, 710 } do
		if type(stored(uid)) ~= "number" then allNumbers = false end
	end
	truthy(allNumbers, "the board's store holds only numbers")
	local saved = store:GetAsync("u_710")
	eq(saved and saved.data and saved.data.bestRate, bothRate, "Eli's profile keeps his best (it survives a rejoin)")
end

print("")
local unexpected = {}
for _, w in h.warnings do
	-- the one warning this run provokes on purpose: Fay's locked save (section 9)
	if not string.find(w, "Fay is locked by another server", 1, true) then table.insert(unexpected, w) end
end
eq(#unexpected, 0, "no warnings but the locked save's own")
for _, w in unexpected do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("steal a cryptid board: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("steal a cryptid board check failed", 0)
end
