-- StormGrow — the Almanac highscore board: public + friends, written only upward, cached, failure-safe.
-- Run:  py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow_board.luau 2>&1
--
-- DESIGN.md §7 / the standard §3, through the real server and HUD:
--   1. the public view: the top 10 of GetSortedAsync(false, 100), rendered on the physical board;
--   2. reads are cached: at most one public read per 60 s while nobody asks for friends;
--   3. a write goes out only when the count went up, at most once per 30 s, and never lowers a higher
--      stored value (a stale server, or a count normalised down on load);
--   4. the friends view: on demand, GetFriendsAsync capped at 200, friends in this server from memory and
--      friends in the top 500 from the cache, an empty state that says something useful;
--   5. an OrderedDataStore that fails: nothing crashes, the board says it is resting, and recovers;
--   6. both boards are readable on a phone, and the porch board stands near spawn without hiding field 1 (REVIEW-1 B5);
--   7. a flood of prompt presses costs the server almost nothing, and a name that fails to resolve is not
--      looked up again on every press (REVIEW-1 A6);
--   8. the board never runs ahead of the saved profile: while the profile store is down, a new entry does not
--      reach the board; it does once the save lands (REVIEW-1 A5).
-- Set by hand (this process only): Config.Weather.Chance.storm = 1 (strikes for sure, so the count goes
-- up on the real strike loop), Config.Save.AutosaveSeconds = 100000 (no autosave: every profile save here is the
-- one a new entry asks for, so "the board follows the save" cannot pass by a lucky autosave), an injected
-- Players:GetFriendsAsync (the emulator has none), and a Players
-- subclass whose GetNameFromUserIdAsync fails for user 5 (a deleted account on the top 10).

local Harness = require("./emu/harness")
local Aim = require("../stormgrow/tests/Aim")
local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow-board", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
-- REVIEW-1: a tile is tapped by the client's pick (Farm.client + Pick.luau), which sends Tap(slot, key). Where this
-- check exercises the SERVER's rules it sends exactly that; check_stormgrow_aim and tests/walk.luau tap the screen.
local function tapTile(plr, hb)
	h.ReplicatedStorage.StormRemotes.Tap:simulateFireServer(plr, hb:GetAttribute("Farm"), hb:GetAttribute("Key"))
end

local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Weather = h:_require(RS:FindFirstChild("Weather"))
Config.Weather.Chance.storm = 1
Config.Save.AutosaveSeconds = 100000
-- Boot at :01:40 past the hour, a known phase: a sweep over ten boot phases (2026-10-01) failed one, where
-- an earlier storm had already found the entry part 3 counts on. With this phase, parts 1-2 (~244 s) see the
-- :01:30 rainbow and the :05 frost with no crops planted; part 3 plants at ~:05:44 (the frost may find
-- Frosted Radish), replants at :09:25, and the :10 storm finds Charged Radish, done by :11:07.
Config.Weather.ClockOffsetSeconds = (100 - os.time() % 3600) % 3600

local ods = h.services.DataStoreService:GetOrderedDataStore("StormGrowAlmanac_v1")
local profiles = h.services.DataStoreService:GetDataStore("StormGrow_v1")
-- user 5 (rank 6 on the board) is a deleted account: GetNameFromUserIdAsync raises for it. The emulator's own
-- lookup is otherwise reproduced: a player in the server by name, anyone else "User_<id>".
local nameCalls = {}
h.instance.defineClass("PlayersNameFail", { parent = "Players", methods = {
	GetNameFromUserIdAsync = function(self, userId)
		nameCalls[userId] = (nameCalls[userId] or 0) + 1
		if userId == 5 then error("HTTP 400 (user not found)", 0) end
		for _, plr in self:GetPlayers() do
			if plr.UserId == userId then return plr.Name end
		end
		return "User_" .. tostring(userId)
	end,
} })
h.instance.stateOf(h.Players).className = "PlayersNameFail"
local T = os.time()
-- twelve other farmers on the board (u_1 .. u_12, counts 30 down to 8) and one who is a friend (u_77)
for i = 1, 12 do
	ods:SetAsync("u_" .. i, (32 - 2 * i) * 2e9 + (2e9 - (T - 10000 + i)))
end
ods:SetAsync("u_77", 3 * 2e9 + (2e9 - (T - 5000)))
-- this player already has a HIGHER stored score than their record will say (a stale write elsewhere)
ods:SetAsync("u_502", 40 * 2e9 + (2e9 - (T - 9000)))

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
h.game:GetService("RunService"):setIsServer(false)
local me = h:join("Boarder", 501)
h:advance(0.5)
h.Players:simulateSpawn(me, h.workspace)
h:advance(0.3)
local stale = h:join("Stale", 502)
h:advance(0.5)
h.Players:simulateSpawn(stale, h.workspace)
h:advance(0.3)
h.Players.LocalPlayer = me
assert(h:tryRun("client/Hud.client"))
local RunService = h.game:GetService("RunService")
local function frames(s) for _ = 1, math.floor(s / 0.1 + 0.5) do RunService.RenderStepped:Fire(0.1); h:advance(0.1) end end
local board = h.workspace.Valley.AlmanacBoard
local prompt = board.BoardPrompt
local bg = board:FindFirstChild("BoardView"):FindFirstChild("Background")
local function rowText(i) return bg:FindFirstChild("Row_" .. i).Text end
local function note() return bg.Note.Text end

--============================================================ 1. the public view

h:advance(61) -- the first public push (a minute's board upkeep)
frames(0.3)
truthy(string.find(bg.Title.Text, "everyone", 1, true) ~= nil, "the board shows everyone (" .. bg.Title.Text .. ")")
truthy(string.find(rowText(1), "1.", 1, true) == 1 and string.find(rowText(1), "40", 1, true) ~= nil, "rank 1 is the 40-entry farmer (" .. rowText(1) .. ")")
truthy(string.find(rowText(2), "30", 1, true) ~= nil, "rank 2 has 30 (" .. rowText(2) .. ")")
truthy(rowText(10) ~= "", "ten rows are shown")
truthy(string.find(bg.You.Text, "You:", 1, true) ~= nil, "your own line is pinned (" .. bg.You.Text .. ")")

--============================================================ 2. cached reads

do
	local calls0 = ods.__calls
	h:advance(180)
	local reads = ods.__calls - calls0
	print(string.format("  OrderedDataStore calls in 180 s with nobody on the friends view: %d", reads))
	truthy(reads <= 4, "at most one public read a minute (plus nothing else: no one's count went up)")
end

--============================================================ 3. writes: only upward, coalesced, never lower

do
	local tiles = h.workspace.Farms["Farm_" .. me:GetAttribute("Slot")].Tiles
	for _, plr in { me, stale } do
		local tl = h.workspace.Farms["Farm_" .. plr:GetAttribute("Slot")].Tiles
		for t = 1, 9 do
			tapTile(plr, tl["Tile_1_" .. t])
			h:advance(0.15)
		end
	end
	eq(ods:GetAsync("u_501"), nil, "set-up: nothing written for a count of 0")
	local now = h.workspace:GetAttribute("ServerNow")
	local k, s = Weather.nextEvent(now, Config.Weather)
	while k ~= "storm" do k, s = Weather.nextEvent(s, Config.Weather) end
	-- replant 35 s before the storm so the crops are ripe for its first tick
	h:advance(s - now - 35)
	for t = 1, 9 do
		tapTile(me, tiles["Tile_1_" .. t])
		h:advance(0.15)
	end
	-- The wait above can pass a :x5 frost (the clock's phase at boot is the real time's), which may already
	-- have found Frosted Radish; so this part counts from here, and checks the storm's own entry by its bit.
	local countBefore = me:GetAttribute("AlmanacCount")
	local calls0 = ods.__calls
	h:advance(35 + 1)
	eq(me:GetAttribute("AlmanacCount"), countBefore + 1, "the storm's first tick found a new entry")
	eq(string.sub(me:GetAttribute("AlmanacBits"), 1, 1), "1", "Charged Radish")
	h:advance(11)
	local rec = profiles:GetAsync("u_501")
	eq(rec and rec.almanacCount, countBefore + 1, "a new entry is saved to the profile within ~10 s (no autosave runs here)")
	h:advance(31)
	local v = ods:GetAsync("u_501")
	local count = me:GetAttribute("AlmanacCount")
	truthy(type(v) == "number" and math.floor(v / 2e9) == count, "within 30 s the count (" .. count .. ") reached the board store (" .. tostring(v) .. ")")
	eq(v % 1, 0, "as an integer")
	local _, at = math.floor(v / 2e9), 2e9 - (v - math.floor(v / 2e9) * 2e9)
	truthy(math.abs(at - s) < 1, "tie-broken by the SERVER's time of the strike that raised the count")
	-- the stale farmer's session: its count (1) is far below its stored 40, and the write never lowers it
	local sv = ods:GetAsync("u_502")
	eq(math.floor(sv / 2e9), 40, "a higher stored score is never lowered by a session with fewer entries")
	-- writes are coalesced: count the write calls over the next 2 minutes (a harvest now and a frost later
	-- can add entries; at most one write per 30 s)
	local w0 = ods.__calls
	h:advance(120)
	local w = ods.__calls - w0
	print(string.format("  OrderedDataStore calls over the next 120 s: %d (reads + coalesced writes)", w))
	truthy(w <= 2 + 4 + 2, "at most 2 public reads + 4 coalesced writes per player in 2 minutes")
	local _ = calls0
end

--============================================================ 4. the friends view

do
	-- 250 friends over three pages of 100/100/50; u_77 (in the top 500) and u_502 (in this server) among them
	local advances = 0
	h.Players.GetFriendsAsync = function(_self, _userId)
		local pages = { {}, {}, {} }
		for i = 1, 250 do
			local id = if i == 1 then 77 elseif i == 2 then 502 else 100000 + i
			table.insert(pages[(i - 1) // 100 + 1], { Id = id, Username = "F" .. i })
		end
		local p = { page = 1, IsFinished = false }
		function p:GetCurrentPage() return pages[self.page] end
		function p:AdvanceToNextPageAsync()
			advances += 1
			self.page += 1
			self.IsFinished = self.page >= 3
		end
		return p
	end
	-- The emulator has ONE client per process and its FireClient reaches it whatever the target player,
	-- so what the board renders can be another player's push. Content is read from the payloads the server
	-- addressed to `me` (Board:sentTo), and the rendering from part 1.
	local boardRemote = h.ReplicatedStorage.StormRemotes.Board
	local function lastFor(plr)
		local sent = boardRemote:sentTo(plr)
		return sent[#sent] and sent[#sent].args[1]
	end
	prompt.Triggered:Fire(me)
	h:advance(0.3)
	frames(0.3)
	local view = lastFor(me)
	truthy(view and string.find(view.title, "friends", 1, true) ~= nil, "the prompt switches to the friends view (" .. tostring(view and view.title) .. ")")
	eq(advances, 1, "GetFriendsAsync stops at 200 friends: two pages read, the third never fetched")
	local all = {}
	for _, r in view.rows do table.insert(all, string.format("%d. %s %d", r.rank, r.name, r.count)) end
	local joined = table.concat(all, " | ")
	print("  friends view: " .. joined)
	truthy(string.find(joined, "User_77", 1, true) ~= nil, "a friend in the top 500 is listed (" .. joined .. ")")
	-- (names: the emulator's GetNameFromUserIdAsync answers "User_<id>" for anyone not in the server at the
	-- first lookup, and the server caches names for its lifetime, as designed; Roblox returns the real name)
	truthy(string.find(joined, "User_502 40", 1, true) ~= nil or string.find(joined, "Stale 40", 1, true) ~= nil,
		"a friend in this server is listed with the BEST of their session value (1) and their stored value (40)")
	truthy(string.find(joined, "User_1 ", 1, true) == nil, "strangers are not")
	truthy(string.find(joined, "Boarder", 1, true) ~= nil, "and you are in your own friends view")
	-- a player with friends but none on the board: the empty state
	h.Players.GetFriendsAsync = function()
		return { IsFinished = true, GetCurrentPage = function() return { { Id = 123456789, Username = "Nobody" } } end, AdvanceToNextPageAsync = function() end }
	end
	local lonely = h:join("Lonely", 601)
	h:advance(0.5)
	h.Players.LocalPlayer = me
	prompt.Triggered:Fire(lonely)
	h:advance(0.3)
	local sent = h.ReplicatedStorage.StormRemotes.Board:sentTo(lonely)
	local last = sent[#sent].args[1]
	eq(last.mode, "friends", "the lonely farmer gets a friends view")
	truthy(type(last.note) == "string" and string.find(last.note, "Invite one", 1, true) ~= nil, "which says something useful (" .. tostring(last.note) .. ")")
	eq(#last.rows, 1, "with their own row")
	h:leave(lonely)
	prompt.Triggered:Fire(me) -- back to everyone
	h:advance(0.3)
	eq(lastFor(me).mode, "public", "and the prompt switches back to everyone")
end

--============================================================ 5. a failing OrderedDataStore

do
	ods.__failAll = true
	h:advance(61)
	frames(0.3)
	truthy(string.find(note(), "resting", 1, true) ~= nil, "a failing board read says the board is resting (" .. note() .. ")")
	truthy(rowText(1) ~= "", "and keeps showing the last good rows")
	ods.__failAll = false
	h:advance(61)
	frames(0.3)
	truthy(string.find(note(), "resting", 1, true) == nil, "and recovers on the next refresh (" .. note() .. ")")
end

--============================================================ 6. readable on a phone; the porch board near spawn (B5)

do
	-- A row's height on an 800 x 360 landscape phone (FOV 70), seen square-on from the board prompt's reach (the
	-- distance a farmer reads it from to press it). TextScaled text fills its row.
	local function rowPt(boardPart, view, d)
		local smallest = math.huge
		for _, r in view.Background:GetChildren() do
			if string.match(r.Name, "^Row_%d+$") then
				local studs = r.Size.Y.Scale * boardPart.Size.Y
				smallest = math.min(smallest, studs * 360 / (2 * d * math.tan(math.rad(35))))
			end
		end
		return smallest
	end
	local slot = me:GetAttribute("Slot")
	local farm = h.workspace.Farms["Farm_" .. slot]
	local porch = farm:FindFirstChild("FarmBoard_" .. slot)
	local pad = farm:FindFirstChild("FarmPad_" .. slot)
	local porchView = porch:FindFirstChild("BoardView")
	truthy(porchView ~= nil, "set-up: your porch board draws your view")
	local porchPrompt = porch:FindFirstChildOfClass("ProximityPrompt")
	local pPorch = rowPt(porch, porchView, porchPrompt.MaxActivationDistance)
	local pMarket = rowPt(board, board.BoardView, prompt.MaxActivationDistance)
	print(string.format("  smallest row on a 360-pt phone at the prompt's reach: porch %.1f pt (%d studs), market %.1f pt (%d studs)",
		pPorch, porchPrompt.MaxActivationDistance, pMarket, prompt.MaxActivationDistance))
	truthy(pPorch >= 12, string.format("the porch board's rows are at least 12 pt tall where you press its prompt (%.1f)", pPorch))
	truthy(pMarket >= 12, string.format("the market board's rows too (%.1f)", pMarket))
	local flat = Vector3.new(porch.Position.X - pad.Position.X, 0, porch.Position.Z - pad.Position.Z).Magnitude
	truthy(flat <= 18, string.format("the porch board stands within 18 studs of the spawn pad (%.1f)", flat))
	-- seen from the spawn: it faces the camera, and it hides no tile of field 1
	local aim = Aim.new(h, { touch = true })
	local Farm = h:_require(RS:FindFirstChild("Farm"))
	local root, facing = aim:standFor(Farm, Config.Farm, slot, 1)
	local visible = Aim.within(aim:parts("visible"), root, 120)
	local hidden, faced = 0, math.huge
	for _, pose in { { 20, 12.5 }, { 30, 12.5 }, { 45, 12.5 }, { 30, 20 } } do
		aim:pose(root, facing, pose[1], pose[2])
		local camPos = h.workspace.CurrentCamera.CFrame.Position
		faced = math.min(faced, porch.CFrame.LookVector:Dot((camPos - porch.Position).Unit))
		for t = 1, 9 do
			local soil = farm.Tiles["Soil_1_" .. t]
			local hit = aim:firstVisible(camPos, soil.Position + Vector3.new(0, soil.Size.Y / 2, 0), visible)
			if hit == porch then hidden += 1 end
		end
	end
	eq(hidden, 0, "from the spawn camera (4 poses) the porch board hides no tile of field 1")
	truthy(faced >= 0.5, string.format("and its face turns to the spawn camera (cos %.2f >= 0.5, within 60 degrees)", faced))
end

--============================================================ 7. a flood of prompt presses (A6)

do
	local boardRemote = h.ReplicatedStorage.StormRemotes.Board
	local toastRemote = h.ReplicatedStorage.StormRemotes.Toast
	h:advance(2)
	local b0, t0, n0, o0 = #boardRemote:sentTo(me), #toastRemote:sentTo(me), nameCalls[5] or 0, ods.__calls
	for _ = 1, 200 do
		prompt.Triggered:Fire(me)
		h:advance(0.005)
	end
	h:advance(1)
	local payloads, toasts, lookups = #boardRemote:sentTo(me) - b0, #toastRemote:sentTo(me) - t0, (nameCalls[5] or 0) - n0
	print(string.format("  200 prompt presses in 1 s: %d board payloads, %d toasts, %d lookups of the failing name, %d OrderedDataStore calls",
		payloads, toasts, lookups, ods.__calls - o0))
	truthy(payloads <= 3, string.format("the server answers at most a few of them (%d payloads)", payloads))
	truthy(toasts >= 1 and toasts <= 4, string.format("and says so without a toast per press (%d)", toasts))
	truthy(lookups <= 1, string.format("a name that failed to resolve is not looked up again on every press (%d)", lookups))
	-- the cooldown is not a lockout: a press a moment later is served
	h:advance(2)
	local before = #boardRemote:sentTo(me)
	prompt.Triggered:Fire(me)
	h:advance(0.5)
	eq(#boardRemote:sentTo(me) - before, 1, "a press two seconds later is served")
	local sentNow = boardRemote:sentTo(me)
	local last = sentNow[#sentNow].args[1]
	local names = {}
	for _, r in last.rows do table.insert(names, r.name) end
	truthy(table.find(names, "Farmer 5") ~= nil, "the unresolved name shows as Farmer 5 (" .. table.concat(names, ", ") .. ")")
	if last.mode ~= "public" then
		h:advance(2)
		prompt.Triggered:Fire(me)
		h:advance(0.5)
	end
	-- presses at a human pace (past the cooldown): five switches, three of them to the public view, each naming the
	-- top 10. The name that failed a moment ago is not asked for again.
	local n1 = nameCalls[5] or 0
	local views = 0
	for _ = 1, 5 do
		h:advance(1.2)
		prompt.Triggered:Fire(me)
		h:advance(0.1)
		local sent = boardRemote:sentTo(me)
		if sent[#sent].args[1].mode == "public" then views += 1 end
	end
	truthy(views >= 2, "set-up: the presses showed the public view " .. views .. " times")
	eq((nameCalls[5] or 0) - n1, 0, "the name that failed is not looked up again within a minute")
	if boardRemote:sentTo(me)[#boardRemote:sentTo(me)].args[1].mode ~= "public" then
		h:advance(1.2)
		prompt.Triggered:Fire(me)
		h:advance(0.5)
	end
end

--============================================================ 8. the board never runs ahead of the save (A5)

do
	-- a farmer with Carrots, field 1 planted 70 s before a storm; then the PROFILE store goes down
	profiles:SetAsync("u_503", { v = 1, coins = 500, harvested = 900, fields = 1, unlocked = 2, selected = "carrot",
		tiles = {}, almanac = {}, almanacCount = 0, almanacAt = 0, harvests = 40 })
	local crash = h:join("Crashy", 503)
	h:advance(0.5)
	h.Players:simulateSpawn(crash, h.workspace)
	h:advance(0.3)
	h.Players.LocalPlayer = me
	eq(crash:GetAttribute("CanSave"), true, "set-up: the farmer loaded and can save")
	local now = h.workspace:GetAttribute("ServerNow")
	local k, sAt = Weather.nextEvent(now, Config.Weather)
	while k ~= "storm" or sAt - now < 80 do k, sAt = Weather.nextEvent(sAt, Config.Weather) end
	h:advance(sAt - now - 70)
	local tl = h.workspace.Farms["Farm_" .. crash:GetAttribute("Slot")].Tiles
	for t = 1, 9 do
		tapTile(crash, tl["Tile_1_" .. t])
		h:advance(0.15)
	end
	eq(tl.Tile_1_9:GetAttribute("Crop"), "carrot", "set-up: nine Carrots planted, ripe before the storm")
	profiles.__failAll = true
	h:advance(70 + 6) -- the storm's first ticks
	eq(crash:GetAttribute("AlmanacCount"), 1, "set-up: the storm found Charged Carrot (in memory)")
	h:advance(70) -- an autosave, the board's 5 s loop many times over
	eq(ods:GetAsync("u_503"), nil, "while no save lands, the entry does not reach the board")
	profiles.__failAll = false
	h:advance(80)
	local v = ods:GetAsync("u_503")
	eq(v and math.floor(v / 2e9), 1, "once a save lands, the board follows")
	local saved = profiles:GetAsync("u_503")
	eq(saved and saved.almanacCount, 1, "(and the profile holds the entry)")
end

print("")
for _, w in h.warnings do
	if not string.find(w, "injected", 1, true) then print("warning: " .. w) end
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow board: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow board check failed", 0) end
