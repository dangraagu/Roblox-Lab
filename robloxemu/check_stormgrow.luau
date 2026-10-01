-- StormGrow: Mutation Farm — the valley has to be IN THE WORLD, a joining farmer has to LAND on their own
-- porch, every prompt has to be reachable, the board has to render, and the core loop has to turn.
--
-- Run:  cd D:/Claude/Roblox/robloxemu
--       py -3 wrap.py --game ../stormgrow --out build/stormgrow.luau
--       luau check_stormgrow.luau 2>&1
--
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Why this file asks the workspace instead of trusting unit tests: Grow a Crystal shipped a core loop
-- that was unreachable (a Part never parented) behind 166 green tests. Nothing here recomputes a count
-- from the game's own modules to grade the game against itself: counts are written out by hand, and the
-- game's modules are used only to ADDRESS things (where is field 1, which tick is next).
--
-- In-memory changes this run makes to the game (this process only, never src/):
--   * Config.Weather.Chance.storm = 1 in part E, so "a ripe crop is struck" is deterministic. The real odds
--     are measured in tests/Mutation.spec.luau (100 000 events) and played in tests/walk.luau.
--   * Config.Weather.ClockOffsetSeconds, so the server boots at :16:40 past the hour (clear: the :15 frost has
--     ended, the :20 storm is 200 s away and is not followed by a rainbow). A phase sweep of this file over ten
--     boot phases (2026-10-01) failed in four of them, all in part E's set-up: joining during an event marks
--     the first Radishes, and "the next storm" can be seconds away. The weather schedule itself is
--     covered phase by phase in tests/Weather.spec.luau; this file needs one known phase.

local Harness = require("./emu/harness")

local h = Harness.new({ bundle = require("./build/stormgrow"), name = "stormgrow", viewport = { 1280, 720 }, touch = false })

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
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b) .. " +- " .. tol)
	end
end

local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local ws = h.workspace
do
	local t = os.time()
	mod("Config").Weather.ClockOffsetSeconds = (1000 - t % 3600) % 3600 -- boot at :16:40 (see the header)
end

-- A returning farmer with 500 coins (a real saved record, JSON round-tripped by the emulator's DataStore),
-- so "buy field 2" can be exercised without waiting 7 minutes. Written before the server boots.
local store = h.services.DataStoreService:GetDataStore("StormGrow_v1")
store:SetAsync("u_2002", { v = 1, coins = 500, harvested = 900, fields = 1, unlocked = 2, selected = "carrot",
	tiles = { ["1_1"] = { c = "carrot", at = 1, m = 2 } }, almanac = { ["carrot:2"] = 1 }, almanacCount = 1, almanacAt = 1, harvests = 40 })

assert(h:tryRun("server/Main.server"))
h:advance(0.5)
local Config, Farm, Weather = mod("Config"), mod("Farm"), mod("Weather")
local F = Config.Farm

--============================================================ A. the valley is built and parented

local farms = ws:FindFirstChild("Farms")
truthy(farms ~= nil, "workspace.Farms exists (control: the builder ran at all)")
local valley = ws:FindFirstChild("Valley")
truthy(valley ~= nil, "workspace.Valley exists")

local function isIn(inst, ancestor)
	local node = inst
	while node ~= nil do
		if node == ancestor then return true end
		node = node.Parent
	end
	return false
end

local totalParts = 0
for _, d in ws:GetDescendants() do
	if d:IsA("BasePart") then totalParts += 1 end
end
print(string.format("  server-built BaseParts in workspace: %d (cap %d)", totalParts, Config.Budget.MaxServerParts))
truthy(totalParts > 700, "the valley is actually in the workspace (" .. totalParts .. " parts)")
truthy(totalParts <= Config.Budget.MaxServerParts, "and under the server part budget")

local hitboxCount, detectorCount, soilCount, badPlace = 0, 0, 0, 0
for k = 1, 6 do
	local model = farms and farms:FindFirstChild("Farm_" .. k)
	truthy(model ~= nil and isIn(model, ws), "Farm_" .. k .. " is parented into the workspace")
	local tiles = model and model:FindFirstChild("Tiles")
	for f = 1, 6 do
		for t = 1, 9 do
			local key = f .. "_" .. t
			local hb = tiles and tiles:FindFirstChild("Tile_" .. key)
			local soil = tiles and tiles:FindFirstChild("Soil_" .. key)
			if hb then
				hitboxCount += 1
				local x, z = Farm.tileCentre(k, f, t, F)
				if math.abs(hb.Position.X - x) > 0.01 or math.abs(hb.Position.Z - z) > 0.01 then badPlace += 1 end
				-- the soil plate's invisible twin: never a click target (REVIEW-1 B1: an invisible queryable part takes
				-- the click ray before the tile behind it)
				if hb.CanCollide ~= false or hb.CanQuery ~= false or hb.Transparency ~= 1 then badPlace += 1 end
				if soil and (math.abs(hb.Size.Y - soil.Size.Y) > 0.01 or (hb.Position - soil.Position).Magnitude > 0.01) then badPlace += 1 end
				if hb:FindFirstChildOfClass("ClickDetector") then detectorCount += 1 end
			end
			if soil and soil.CanCollide ~= false then soilCount += 1 end
		end
	end
end
eq(hitboxCount, 324, "6 farms x 54 tile hitboxes are in the world")
eq(detectorCount, 0, "none carries a ClickDetector: taps are picked on the client against what is drawn")
eq(soilCount, 324, "and sits on a collidable soil plate")
eq(badPlace, 0, "every tile part is where Farm.tileCentre says: the soil plate's invisible, walk-through, unqueryable twin")

do
	-- MarketPad is the first enabled SpawnLocation in a depth-first walk; farm pads start disabled
	local firstSpawn = nil
	local function walk(node)
		for _, c in node:GetChildren() do
			if firstSpawn == nil and c.ClassName == "SpawnLocation" and c.Enabled then firstSpawn = c end
			walk(c)
		end
	end
	walk(ws)
	eq(firstSpawn and firstSpawn.Name, "MarketPad", "MarketPad is the engine's fallback spawn")
	local enabledPads = 0
	for k = 1, 6 do
		local pad = farms:FindFirstChild("Farm_" .. k):FindFirstChild("FarmPad_" .. k)
		if pad and pad.Enabled then enabledPads += 1 end
	end
	eq(enabledPads, 0, "no farm pad is enabled before anyone claims it")
end

local board = valley and valley:FindFirstChild("AlmanacBoard")
truthy(board ~= nil and isIn(board, ws), "the Almanac board stands in the world")
local prompt = board and board:FindFirstChildOfClass("ProximityPrompt")
truthy(prompt ~= nil, "with a ProximityPrompt")
truthy(type(ws:GetAttribute("ServerNow")) == "number", "workspace ServerNow is published")

--============================================================ B. joining farmers land on their own porch

local function landed(plr, char, k, label)
	local root = char:FindFirstChild("HumanoidRootPart")
	local pad = farms:FindFirstChild("Farm_" .. k):FindFirstChild("FarmPad_" .. k)
	local dxz = math.sqrt((root.Position.X - pad.Position.X) ^ 2 + (root.Position.Z - pad.Position.Z) ^ 2)
	truthy(dxz <= 3, string.format("%s lands on FarmPad_%d (XZ %.2f studs off)", label, k, dxz))
	truthy(root.Position.Y > pad.Position.Y + pad.Size.Y / 2, label .. " stands above the pad, not in it")
	local fx, fz = Farm.fieldCentre(k, 1, F)
	local to = Vector3.new(fx - root.Position.X, 0, fz - root.Position.Z).Unit
	local look = root.CFrame.LookVector
	local dot = look.X * to.X + look.Z * to.Z
	truthy(dot > 0.9, string.format("%s faces field 1 (dot %.2f)", label, dot))
end

local players = {}
for i = 1, 6 do
	local plr = h:join("Farmer" .. i, i * 1001) -- 1001, 2002, ...
	players[i] = plr
	h:advance(0.1)
	eq(plr:GetAttribute("Slot"), i, "farmer " .. i .. " claims slot " .. i .. " on join")
	local pad = farms:FindFirstChild("Farm_" .. i):FindFirstChild("FarmPad_" .. i)
	eq(plr.RespawnLocation, pad, "RespawnLocation points at FarmPad_" .. i .. " (set before any yield)")
	eq(pad.Enabled, true, "and that pad is enabled")
	local char = h.Players:simulateSpawn(plr, ws)
	h:advance(0.2)
	landed(plr, char, i, "farmer " .. i)
end
local p1 = players[1]
eq(p1.UserId, 1001, "set-up: farmer 1 is user 1001")
eq(players[2].UserId, 2002, "set-up: farmer 2 is the returning farmer with 500 coins")
h:advance(1)
eq(p1:GetAttribute("Loaded"), true, "farmer 1's profile loaded")
eq(p1:GetAttribute("Coins"), 20, "a new farmer starts with 20 coins")
eq(players[2]:GetAttribute("Coins"), 500, "the returning farmer's coins came back")

do
	-- a respawn lands in the same place
	local char = h.Players:simulateSpawn(players[4], ws)
	h:advance(0.2)
	landed(players[4], char, 4, "farmer 4 after a respawn")
	-- a seventh player gets no farm: the market pad, and a toast that says so
	local toasts = {}
	local remotes = RS:FindFirstChild("StormRemotes")
	local seventh = h:join("Late", 9999)
	h:advance(0.2)
	for _, rec in remotes.Toast:sentTo(seventh) do table.insert(toasts, tostring(rec.args[1])) end
	eq(seventh:GetAttribute("Slot"), 0, "a seventh player gets no farm slot")
	truthy(string.find(table.concat(toasts, "|"), "taken", 1, true) ~= nil, "and is told the farms are taken")
	local char7 = h.Players:simulateSpawn(seventh, ws)
	h:advance(0.2)
	local mp = ws:FindFirstChild("MarketPad")
	local r7 = char7:FindFirstChild("HumanoidRootPart")
	truthy(math.abs(r7.Position.X - mp.Position.X) < 3 and math.abs(r7.Position.Z - mp.Position.Z) < 3,
		"the seventh player lands on the MarketPad")
	h:leave(seventh)
	-- leave then join reuses the slot (the unbounded-coordinates trap)
	h:leave(players[3])
	h:advance(0.5)
	eq(farms.Farm_3.FarmPad_3.Enabled, false, "a leaving farmer's pad is disabled")
	eq(farms.Farm_3.Tiles.Tile_1_1:GetAttribute("Owner"), 0, "and their tiles are cleared")
	local newcomer = h:join("Newcomer", 7007)
	h:advance(0.5)
	eq(newcomer:GetAttribute("Slot"), 3, "the next farmer reuses slot 3")
	local charN = h.Players:simulateSpawn(newcomer, ws)
	h:advance(0.2)
	landed(newcomer, charN, 3, "the newcomer")
	players[3] = newcomer
	local enabled = {}
	for _, d in ws:GetDescendants() do
		if d.ClassName == "SpawnLocation" and d.Enabled then table.insert(enabled, d.Name) end
	end
	table.sort(enabled)
	eq(table.concat(enabled, ","), "FarmPad_1,FarmPad_2,FarmPad_3,FarmPad_4,FarmPad_5,FarmPad_6,MarketPad",
		"the only enabled spawns are the market pad and the claimed farm pads")
end

--============================================================ C. every prompt is reachable

do
	-- every tile detector: its hitbox is walk-through, stands on collidable ground, and no collidable part
	-- (a fence, the sign) covers the spot a farmer stands on to tap it
	local blockers = {}
	for _, d in ws:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and d.Size.Y > 1 and d.Size.X < 200 then table.insert(blockers, d) end
	end
	local blocked, noGround = 0, 0
	for _, byK in farms:GetChildren() do
		for _, hb in byK.Tiles:GetChildren() do
			if hb:GetAttribute("Key") ~= nil then
				local p = hb.Position
				for _, b in blockers do
					local rel = b.CFrame:PointToObjectSpace(p)
					if math.abs(rel.X) < b.Size.X / 2 and math.abs(rel.Z) < b.Size.Z / 2 and math.abs(rel.Y) < b.Size.Y / 2 + 3 then
						blocked += 1
					end
				end
				local soil = byK.Tiles:FindFirstChild("Soil_" .. hb:GetAttribute("Key"))
				if soil == nil or soil.Position.Y + soil.Size.Y / 2 > 1 or not soil.CanCollide then noGround += 1 end
			end
		end
	end
	eq(blocked, 0, "no collidable part stands where a farmer taps a tile")
	eq(noGround, 0, "every tile has walkable soil under it, at most 1 stud up")
	-- field 1 can be worked from the pad without walking (the first 5 seconds)
	local root = p1.Character.HumanoidRootPart
	local farthest = 0
	for t = 1, 9 do
		local hb = farms.Farm_1.Tiles:FindFirstChild("Tile_1_" .. t)
		farthest = math.max(farthest, (hb.Position - root.Position).Magnitude)
	end
	truthy(farthest < 32, string.format("every field-1 tile is inside the detector's reach from where farmer 1 landed (%.1f < 32)", farthest))
	-- the board prompt: a farmer standing on the market square can reach it
	local square = valley.MarketSquare
	local standAt = Vector3.new(0, square.Position.Y + square.Size.Y / 2 + 3, board.Position.Z - 8)
	local sq = square.CFrame:PointToObjectSpace(standAt)
	truthy(math.abs(sq.X) < square.Size.X / 2 and math.abs(sq.Z) < square.Size.Z / 2, "set-up: that spot is on the market square")
	local d = (board.Position - standAt).Magnitude
	truthy(prompt.Enabled ~= false and d <= prompt.MaxActivationDistance,
		string.format("the board prompt is reachable from the square (%.1f <= %d)", d, prompt.MaxActivationDistance))
	-- the market pad faces the board: a new player sees it
	local mp = ws.MarketPad
	truthy((board.Position - mp.Position).Magnitude < 40, "the board is within 40 studs of the market pad")
end

--============================================================ D. the board exists and renders

h.game:GetService("RunService"):setIsServer(false)
h.Players.LocalPlayer = p1
local okHud, errHud = h:tryRun("client/Hud.client")
truthy(okHud, "Hud.client loads (" .. tostring(errHud) .. ")")
local RunService = h.game:GetService("RunService")
local function frames(seconds, dt)
	dt = dt or 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do
		RunService.RenderStepped:Fire(dt)
		h:advance(dt)
	end
end
frames(0.5)

local boardView = board:FindFirstChild("BoardView")
truthy(boardView ~= nil, "the client built its own SurfaceGui on the board")
local bg = boardView and boardView:FindFirstChild("Background")
local function boardText()
	local parts = {}
	for _, c in bg:GetChildren() do
		if c.ClassName == "TextLabel" and c.Text ~= "" then table.insert(parts, c.Name .. "=" .. c.Text) end
	end
	table.sort(parts)
	return table.concat(parts, " | ")
end
eq(boardView and boardView.Adornee, board, "adorned to the board part")
eq(boardView and boardView.Face, Enum.NormalId.Front, "on its front face")
do
	-- the front face points at the market pad (the spawn side)
	local toPad = (ws.MarketPad.Position - board.Position).Unit
	truthy(board.CFrame.LookVector:Dot(toPad) > 0.9, "the board's front faces the spawn side")
end

-- toggle to Friends: the emulator has no GetFriendsAsync, so this is the failure path
prompt.Triggered:Fire(p1)
h:advance(0.2)
local t1 = boardText()
truthy(string.find(t1, "Couldn't load your friends", 1, true) ~= nil, "a friends lookup that fails says so on the board (" .. t1 .. ")")
truthy(string.find(t1, "everyone", 1, true) ~= nil, "and shows everyone instead")
truthy(string.find(t1, "You:", 1, true) ~= nil, "your own line is pinned")

-- now give the emulator a friends list (an injected Players:GetFriendsAsync, one page), back to Everyone
-- and to Friends again after the 60 s retry wait
local friendsCalls = 0
h.Players.GetFriendsAsync = function(_self, _userId)
	friendsCalls += 1
	return {
		IsFinished = true,
		GetCurrentPage = function() return { { Id = 2002, Username = "Farmer2" }, { Id = 424242, Username = "Faraway" } } end,
		AdvanceToNextPageAsync = function() end,
	}
end
h:advance(1.1) -- (one Friends/Everyone switch a second per player, REVIEW-1 A6)
prompt.Triggered:Fire(p1) -- back to everyone
h:advance(61)
prompt.Triggered:Fire(p1) -- friends, retry allowed now
h:advance(0.2)
local t2 = boardText()
eq(friendsCalls, 1, "GetFriendsAsync was called once, on demand")
truthy(string.find(t2, "your friends", 1, true) ~= nil, "the friends view renders (" .. t2 .. ")")
truthy(string.find(t2, "Farmer2", 1, true) ~= nil, "a friend in this server with an entry is listed")
truthy(string.find(t2, "Faraway", 1, true) == nil, "a friend with no entry is not")
h:advance(1.1) -- (one Friends/Everyone switch a second per player, REVIEW-1 A6)
prompt.Triggered:Fire(p1) -- back to everyone for the rest of the run
h:advance(0.2)

-- NEAR SPAWN (the standard §3: "a physical board in the world near spawn"). A farmer spawns on their own
-- porch, ~105 studs from the market board, facing away from it. So every porch has its own board, turned to
-- the pad and the camera behind it, with the same prompt; the client draws its own view on its own porch board
-- too. (REVIEW-1 B5 moved it from 36 studs to 15 and made it readable: check_stormgrow_board part 6.)
do
	for k = 1, 6 do
		local fb = farms:FindFirstChild("Farm_" .. k):FindFirstChild("FarmBoard_" .. k)
		truthy(fb ~= nil and isIn(fb, ws), "Farm_" .. k .. " has a board on its porch")
		if fb then
			local pad = farms["Farm_" .. k]["FarmPad_" .. k]
			local d = (fb.Position - pad.Position).Magnitude
			truthy(d < 18, string.format("  within 18 studs of the pad (%.1f)", d))
			local toPad = Vector3.new(pad.Position.X - fb.Position.X, 0, pad.Position.Z - fb.Position.Z).Unit
			truthy(fb.CFrame.LookVector:Dot(toPad) > 0.8, "  turned to the pad")
			local fp = fb:FindFirstChildOfClass("ProximityPrompt")
			truthy(fp ~= nil and fp.MaxActivationDistance >= 10, "  with the Friends / Everyone prompt")
			local lx, lz = Farm.toLocal(k, fb.Position.X, fb.Position.Z, F)
			truthy(lz > 0 and lz < F.PorchDepth and math.abs(lx) < F.Width / 2, "  standing on the porch, off the fields")
		end
	end
	local mine = farms.Farm_1:FindFirstChild("FarmBoard_1")
	local view = mine and mine:FindFirstChild("BoardView")
	truthy(view ~= nil, "farmer 1's client draws its board view on its own porch board")
	local title = view and view:FindFirstChild("Background") and view.Background:FindFirstChild("Title")
	truthy(title ~= nil and string.find(title.Text, "Almanac", 1, true) ~= nil, "and it shows the Almanac (" .. tostring(title and title.Text) .. ")")
	eq(farms.Farm_2.FarmBoard_2:FindFirstChild("BoardView"), nil, "but not on anybody else's porch")
	-- the porch board's prompt toggles the view like the market's
	local fp = farms.Farm_1.FarmBoard_1:FindFirstChildOfClass("ProximityPrompt")
	h:advance(1.1) -- (one Friends/Everyone switch a second per player, REVIEW-1 A6)
	fp.Triggered:Fire(p1)
	h:advance(0.2)
	local sent = RS.StormRemotes.Board:sentTo(p1)
	eq(sent[#sent].args[1].mode, "friends", "the porch prompt switches to Friends")
	h:advance(1.1) -- (one Friends/Everyone switch a second per player, REVIEW-1 A6)
	fp.Triggered:Fire(p1)
	h:advance(0.2)
	sent = RS.StormRemotes.Board:sentTo(p1)
	eq(sent[#sent].args[1].mode, "public", "and back to Everyone")
end

--============================================================ E. the core loop turns

local remotes = RS:FindFirstChild("StormRemotes")
local toastsFor = function(plr)
	local out = {}
	for _, rec in remotes.Toast:sentTo(plr) do table.insert(out, tostring(rec.args[1])) end
	return out
end
local function lastToast(plr)
	local t = toastsFor(plr)
	return t[#t] or ""
end
local tiles1 = farms.Farm_1.Tiles
local function tap(plr, key)
	local hb = (farms:FindFirstChild("Farm_" .. plr:GetAttribute("Slot"))).Tiles:FindFirstChild("Tile_" .. key)
	tapTile(plr, hb)
	h:advance(0.15)
end

-- plant all nine of field 1 from the pad
for t = 1, 9 do tap(p1, "1_" .. t) end
local planted = 0
for t = 1, 9 do
	if tiles1:FindFirstChild("Tile_1_" .. t):GetAttribute("Crop") == "radish" then planted += 1 end
end
eq(planted, 9, "nine taps from the pad planted nine Radishes")
eq(p1:GetAttribute("Coins"), 20, "Radish seeds are free")
-- a tap on a growing crop refuses with the time left
tap(p1, "1_1")
truthy(string.find(lastToast(p1), "Ripe in", 1, true) ~= nil, "a growing crop says when it is ripe (" .. lastToast(p1) .. ")")
-- a tap on somebody else's farm refuses
tap(p1, "1_1") -- (rate-limit spacing)
do
	local hb = farms.Farm_2.Tiles.Tile_1_1
	tapTile(p1, hb)
	h:advance(0.15)
	truthy(string.find(lastToast(p1), "Farmer2's farm", 1, true) ~= nil, "a tap on another farm says whose it is (" .. lastToast(p1) .. ")")
end
-- a tap from too far away refuses
do
	local hb = tiles1.Tile_1_1
	local root = p1.Character.HumanoidRootPart
	local home = root.CFrame
	root.CFrame = CFrame.new(hb.Position + Vector3.new(0, 0, 60))
	tapTile(p1, hb)
	h:advance(0.15)
	truthy(string.find(lastToast(p1), "Walk closer", 1, true) ~= nil, "a tap from 60 studs away says walk closer")
	root.CFrame = home
end
-- a locked field says what it costs
tap(p1, "2_1")
truthy(string.find(lastToast(p1), "Field 2", 1, true) ~= nil and string.find(lastToast(p1), "400", 1, true) ~= nil,
	"a tap on locked field 2 names it and its price (" .. lastToast(p1) .. ")")
-- taps faster than a person are refused on the server, and the player hears why (Config.Play.ActionMinSeconds;
-- the 2026-10-01 mutation sweep found nothing here noticed the limit being deleted)
do
	h:advance(0.5)
	local n0 = #toastsFor(p1)
	tapTile(p1, tiles1.Tile_1_2)
	tapTile(p1, tiles1.Tile_1_2) -- the same instant: nobody taps twice in 0 s
	h:advance(0.05)
	local t = toastsFor(p1)
	eq(#t - n0, 2, "two taps in the same instant both get an answer")
	truthy(string.find(t[#t - 1] or "", "Ripe in", 1, true) ~= nil, "the first is served (" .. tostring(t[#t - 1]) .. ")")
	truthy(string.find(t[#t] or "", "one tap at a time", 1, true) ~= nil,
		"the second is refused as too fast, and says so (" .. tostring(t[#t]) .. ")")
	h:advance(0.15)
end

-- harvest + replant
h:advance(31)
local coins0 = p1:GetAttribute("Coins")
for t = 1, 9 do tap(p1, "1_" .. t) end
eq(p1:GetAttribute("Coins") - coins0, 45, "nine ripe Radishes sold for 9 x 5")
eq(p1:GetAttribute("Harvested"), 45, "lifetime harvest 45")
eq(tiles1.Tile_1_5:GetAttribute("Crop"), "radish", "and the same taps replanted")
-- unlock the Carrot from the Seeds panel's remote
remotes.Unlock:simulateFireServer(p1)
h:advance(0.15)
eq(p1:GetAttribute("Unlocked"), 2, "65 coins unlocked the Carrot")
eq(p1:GetAttribute("Selected"), "carrot", "which is now the selected seed")
eq(p1:GetAttribute("Coins"), 15, "for 50")

-- to the next storm, with ripe crops in the ground and one crop still growing
Config.Weather.Chance.storm = 1 -- deterministic strikes for this part (see the header)
remotes.Select:simulateFireServer(p1, "radish")
h:advance(0.15)
eq(p1:GetAttribute("Selected"), "radish", "the Seeds panel's Select remote picks an owned crop")
local now = ws:GetAttribute("ServerNow")
local k, start = Weather.nextEvent(now, Config.Weather)
while k ~= "storm" do k, start = Weather.nextEvent(start, Config.Weather) end
local wait = start - now
print(string.format("  advancing %.0f s to the %s storm", wait, Weather.minuteLabel(start, Config.Weather)))
h:advance(wait - 35)
-- 35 s before the storm: harvest and replant 1_1..1_8 with Radishes (30 s: ripe 5 s before the storm), and
-- 1_9 with a Carrot (60 s: still growing when the first bolts fall, ripe 25 s into the storm)
for t = 1, 8 do tap(p1, "1_" .. t) end
remotes.Select:simulateFireServer(p1, "carrot")
h:advance(0.15)
tap(p1, "1_9")
eq(tiles1.Tile_1_9:GetAttribute("Crop"), "carrot", "set-up: a fresh Carrot 35 s before the storm")
eq(tiles1.Tile_1_4:GetAttribute("Marks"), 0, "set-up: the fresh Radishes carry no marks")
local countBefore = p1:GetAttribute("AlmanacCount")
eq(string.sub(p1:GetAttribute("AlmanacBits"), 1, 1), "0", "set-up: Charged Radish is not in the Almanac yet (no storm since joining)")
h:advance(ws:GetAttribute("ServerNow") and (start - ws:GetAttribute("ServerNow") + 1) or 0)
local charged, growingMarked = 0, 0
for t = 1, 8 do
	if tiles1:FindFirstChild("Tile_1_" .. t):GetAttribute("Marks") == 1 then charged += 1 end
end
if tiles1.Tile_1_9:GetAttribute("Marks") ~= 0 then growingMarked += 1 end
eq(charged, 8, "the first storm tick struck all eight ripe Radishes (chance 1 in this run)")
eq(growingMarked, 0, "and did NOT strike the growing Carrot")
eq(tiles1.Tile_1_1:GetAttribute("LastStrike"), start, "each strike is stamped with the tick's server time")
eq(p1:GetAttribute("AlmanacCount"), countBefore + 1, "Charged Radish is a new Almanac entry")
eq(string.sub(p1:GetAttribute("AlmanacBits"), 1, 1), "1", "at position 1 of the bit string")
truthy(string.find(table.concat(toastsFor(p1), "|"), "NEW in the Almanac: ⚡ Charged Radish", 1, true) ~= nil, "and the farmer is told")
h:advance(31) -- the Carrot (planted ~33.7 s before the storm) ripens ~26.3 s in: struck at the +30 s tick
eq(tiles1.Tile_1_9:GetAttribute("Marks"), 1, "the Carrot is struck once it is ripe, later in the same storm")
local c1 = p1:GetAttribute("Coins")
tap(p1, "1_1")
eq(p1:GetAttribute("Coins") - c1, 25 - 5, "a Charged Radish sells for 25 (x5); the replanted Carrot seed cost 5")
Config.Weather.Chance.storm = 0.5

-- the Almanac board write: the count went up, and at most 30 s later it is in the OrderedDataStore
h:advance(35)
local ods = h.services.DataStoreService:GetOrderedDataStore("StormGrowAlmanac_v1")
local v = ods:GetAsync("u_1001")
truthy(type(v) == "number" and math.floor(v / 2e9) >= 1, "farmer 1's Almanac count reached the board store (" .. tostring(v) .. ")")

-- buy field 2 (the returning farmer has 500 coins)
local p2 = players[2]
remotes.BuyField:simulateFireServer(p2)
h:advance(0.15)
eq(p2:GetAttribute("Fields"), 2, "500 coins bought field 2")
eq(farms.Farm_2.Tiles.Tile_2_1:GetAttribute("Locked"), false, "its tiles unlock")
tap(p2, "2_1")
local p2root = p2.Character.HumanoidRootPart
p2root.CFrame = CFrame.new(farms.Farm_2.Tiles.Tile_2_1.Position + Vector3.new(0, 0, 0))
h:advance(0.2)
tap(p2, "2_1")
eq(farms.Farm_2.Tiles.Tile_2_1:GetAttribute("Crop"), "carrot", "and plant, once the farmer walks there")

--============================================================ F. leave and rejoin keeps everything

local before = {
	coins = p1:GetAttribute("Coins"), harvested = p1:GetAttribute("Harvested"), count = p1:GetAttribute("AlmanacCount"),
	crop = tiles1.Tile_1_2:GetAttribute("Crop"), marks = tiles1.Tile_1_2:GetAttribute("Marks"),
	at = tiles1.Tile_1_2:GetAttribute("PlantedAt"),
}
h:leave(p1)
h:advance(1)
local doc = store:GetAsync("u_1001")
eq(doc and doc.session and doc.session.lockUntil, 0, "leaving released the lock (lockUntil 0), with the owner token")
local back = h:join("Farmer1", 1001)
h:advance(1)
eq(back:GetAttribute("Coins"), before.coins, "rejoin keeps the coins")
eq(back:GetAttribute("Harvested"), before.harvested, "and the lifetime harvest")
eq(back:GetAttribute("AlmanacCount"), before.count, "and the Almanac")
local slot = back:GetAttribute("Slot")
local t2tiles = farms:FindFirstChild("Farm_" .. slot).Tiles
eq(t2tiles.Tile_1_2:GetAttribute("Crop"), before.crop, "and the crop on tile 1_2")
eq(t2tiles.Tile_1_2:GetAttribute("Marks"), before.marks, "with its marks (" .. tostring(before.marks) .. ")")
eq(t2tiles.Tile_1_2:GetAttribute("PlantedAt"), before.at, "planted at the same second (it kept growing offline)")

print("")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("stormgrow: %d passed, %d failed", passed, failed))
if failed > 0 then error("stormgrow check failed", 0) end
