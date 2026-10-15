-- Disaster Rounds - the real server, booted, and the core loop walked. Run: luau check_disasterrounds.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--
-- docs/complete-game-standard.md §1: "The core loop is reachable from join. Walk the real player path headless."
-- This repo once shipped 166 green tests with an unreachable core loop (a Part never parented), so this file asks the
-- WORLD, not the modules:
--   1. the world is BUILT and PARENTED: the Lookout, its one enabled SpawnLocation, the walls, the board; the next
--      island exists, but under ServerStorage, not in the workspace (nothing about a round is visible early);
--   2. a joining character LANDS on LookoutSpawn under the engine's spawn order (robloxemu/SPAWN-ORDER.md), facing
--      the island, and lands there again on a respawn; eight joins all land there;
--   3. every prompt is reachable: the board's ProximityPrompt can be triggered from a spot on the deck;
--   4. the highscore board exists and RENDERS: Board.client draws the stored best streaks on the board's SurfaceGui,
--      and the prompt toggles Public/Friends;
--   5. the loop: drop onto the island (on your own cell), the name, a player who steps out of the red survives,
--      streak 1, Heat 1 after two in a row, standing still is swept out (streak 0, best kept), a practice drop-in
--      counts for nothing, leaving mid-round costs the streak and the rejoin says so.

local SEED = 424242
local Datatypes = require("./emu/datatypes")
do
	local realNew = Datatypes.Random.new
	local n = SEED
	Datatypes.Random.new = function(seed)
		if seed == nil then
			n += 1
			return realNew(n * 7919)
		end
		return realNew(seed)
	end
end
local Harness = require("./emu/harness")
local Bot = require("./check_disasterrounds_bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/disaster-rounds"), name = "disaster-rounds", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local SS = h.game:GetService("ServerStorage")
local lb = h.services.DataStoreService:GetOrderedDataStore("DisasterRounds_Streak_v1")
-- three streaks already on the board
lb:SetAsync("u_9001", 9 * 2e9 + (2e9 - 1780000000))
lb:SetAsync("u_9002", 14 * 2e9 + (2e9 - 1781000000))
lb:SetAsync("u_9003", 9 * 2e9 + (2e9 - 1770000000))

local okServer, errServer = h:tryRun("server/Main.server")
truthy(okServer, "the server loads (" .. tostring(errServer) .. ")")
local Config = h:_require(RS:FindFirstChild("Config"))
local MapGen = h:_require(RS:FindFirstChild("MapGen"))
local LC, IC = Config.Lookout, Config.Island
local ws = h.workspace

--======================================================================= 1. the world, built and parented

local lookout = ws:FindFirstChild("Lookout")
truthy(lookout ~= nil and lookout.Parent == ws, "the Lookout is in the workspace")
local deck = lookout and lookout:FindFirstChild("Deck")
truthy(deck ~= nil, "with a deck")
if deck then
	eq(deck.Position.Y + deck.Size.Y / 2, LC.FloorY, "its floor is at y = FloorY (28), 12 studs over the island's highest top")
end
local spawns = {}
for _, root in { ws, RS, h.game:GetService("ServerStorage"), h.game:GetService("Lighting") } do
	for _, d in root:GetDescendants() do
		if d.ClassName == "SpawnLocation" then table.insert(spawns, d) end
	end
end
eq(#spawns, 1, "there is exactly one SpawnLocation in the place")
local spawnPad = lookout and lookout:FindFirstChild("LookoutSpawn")
truthy(spawnPad ~= nil and spawnPad.ClassName == "SpawnLocation", "it is LookoutSpawn, on the Lookout")
if spawnPad then
	eq(spawnPad.Enabled, true, "and it is enabled")
	local look = spawnPad.CFrame.LookVector
	truthy(look.X > 0.99, string.format("it faces +X, toward the island (look %.2f, %.2f, %.2f)", look.X, look.Y, look.Z))
end
local rf = ws:FindFirstChild("Round")
truthy(rf ~= nil, "workspace.Round exists")
local walls = rf and rf:FindFirstChild("Walls")
eq(walls and #walls:GetChildren(), 4, "four invisible walls ring the island")
truthy(ws:FindFirstChild("Sea") ~= nil, "the sea is there")
eq(rf and rf:FindFirstChild("Island"), nil, "no island in the workspace before the first drop")
local hidden = SS:FindFirstChild("NextIsland")
truthy(hidden ~= nil, "the next island is built under ServerStorage")
if hidden then
	eq(#hidden.Cells:GetChildren(), IC.Grid * IC.Grid, "with all 169 cells")
	local props = #hidden.Props:GetChildren()
	truthy(props > 0 and props <= IC.MaxProps, "and its props (" .. props .. " Parts, cap " .. IC.MaxProps .. ")")
	local collide = 0
	for _, p in hidden.Props:GetChildren() do
		if p.CanCollide or p.CanQuery or p.CanTouch then collide += 1 end
	end
	eq(collide, 0, "no prop collides, blocks a query or touches: decor never changes a path")
end
eq(rf and rf:GetAttribute("Phase"), "intermission", "the server starts in the intermission")
eq(rf and rf:GetAttribute("Kind"), nil, "with no disaster named")

--======================================================================= 2. spawning, the engine's way

h.game:GetService("RunService"):setIsServer(false)
local A = h:join("Ava", 501)
eq(A.RespawnLocation, spawnPad, "PlayerAdded points RespawnLocation at LookoutSpawn before anything yields")
local charA = h.Players:simulateSpawn(A, ws)
local hrpA = charA:FindFirstChild("HumanoidRootPart")
h:advance(0.1)
local function onPad(hrp): boolean
	local p = hrp.Position
	return spawnPad ~= nil and math.abs(p.X - spawnPad.Position.X) <= 3 and math.abs(p.Z - spawnPad.Position.Z) <= 3
		and p.Y > spawnPad.Position.Y + spawnPad.Size.Y / 2
end
truthy(onPad(hrpA), string.format("Ava lands on LookoutSpawn (%.1f, %.1f, %.1f)", hrpA.Position.X, hrpA.Position.Y, hrpA.Position.Z))
truthy(hrpA.CFrame.LookVector.X > 0.95, "facing the island")
do
	local others = {}
	for k = 1, 7 do
		local p = h:join("Joiner" .. k, 600 + k)
		local c = h.Players:simulateSpawn(p, ws)
		table.insert(others, { p, c })
	end
	h:advance(0.1)
	local landed = 0
	for _, e in others do
		if onPad(e[2]:FindFirstChild("HumanoidRootPart")) then landed += 1 end
	end
	eq(landed, 7, "seven more joins all land on LookoutSpawn")
	for _, e in others do h:leave(e[1]) end
	h:advance(0.5)
end
-- a respawn lands on the pad again
charA = h.Players:simulateSpawn(A, ws)
hrpA = charA:FindFirstChild("HumanoidRootPart")
h:advance(0.1)
truthy(onPad(hrpA), "a respawn lands Ava on LookoutSpawn again")

--======================================================================= 3 + 4. the board: reachable, and it renders

h.Players.LocalPlayer = A
for _, c in { "client/Hud.client", "client/Board.client", "client/Sky.client", "client/World.client" } do
	local ok, err = h:tryRun(c)
	truthy(ok, c .. " loads (" .. tostring(err) .. ")")
end
local board = lookout and lookout:FindFirstChild("StreakBoard")
truthy(board ~= nil, "the board stands on the Lookout")
local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt", true)
truthy(prompt ~= nil, "with a ProximityPrompt")
if board and prompt and spawnPad then
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
	eq(prompt.MaxActivationDistance, Config.Board.PromptDistance, "its reach is Config.Board.PromptDistance")
	local at = prompt.Parent
	local pw = (board.CFrame * CFrame.new(at.Position.X, at.Position.Y, at.Position.Z)).Position
	-- a spot on the deck, in front of the board, where a player can stand
	local stand = Vector3.new(pw.X, LC.FloorY + 3, pw.Z + 4)
	local onDeck = stand.X > LC.MinX and stand.X < LC.MaxX and stand.Z > LC.MinZ and stand.Z < LC.MaxZ
	truthy(onDeck, string.format("there is deck in front of it (%.1f, %.1f)", stand.X, stand.Z))
	local d = (stand - pw).Magnitude
	truthy(d <= prompt.MaxActivationDistance, string.format("from there the prompt is %.1f studs away: reachable", d))
	local flat = Vector3.new(board.Position.X - spawnPad.Position.X, 0, board.Position.Z - spawnPad.Position.Z).Magnitude
	truthy(flat <= 17, string.format("the board stands %.1f studs from the spawn", flat))
	local look = board.CFrame.LookVector
	truthy(look.Z > 0.95, "and faces the deck (its front looks +Z, toward the spawn)")
end
h:advance(Config.Board.PublicCacheSeconds + 1) -- the next public refresh reads the stored streaks
local sg = board and board:FindFirstChild("StreakBoardGui")
truthy(sg ~= nil, "Board.client put a SurfaceGui on the board")
local function boardText(name: string): string
	local l = sg and sg:FindFirstChild(name, true)
	return if l then l.Text else ""
end
truthy(string.find(boardText("Title"), "LONGEST STREAKS", 1, true) ~= nil, "titled LONGEST STREAKS (" .. boardText("Title") .. ")")
truthy(string.find(boardText("Mode"), "PUBLIC", 1, true) ~= nil, "showing the public view (" .. boardText("Mode") .. ")")
truthy(string.find(boardText("Mode"), "up to " .. tostring(Config.Board.StreakCap), 1, true) ~= nil,
	"and saying it counts a streak up to the cap (REVIEW-1 F5): " .. boardText("Mode"))
truthy(string.find(boardText("Row1"), "User_9002", 1, true) ~= nil and string.find(boardText("Row1"), "14", 1, true) ~= nil,
	"row 1 is the longest streak, 14 (" .. boardText("Row1") .. ")")
truthy(string.find(boardText("Row2"), "User_9003", 1, true) ~= nil, "a tie on 9 goes to whoever got there first (" .. boardText("Row2") .. ")")
truthy(string.find(boardText("Row3"), "User_9001", 1, true) ~= nil, "(" .. boardText("Row3") .. ")")
if prompt then
	prompt.Triggered:Fire(A)
	h:advance(0.5)
	truthy(string.find(boardText("Mode"), "FRIENDS", 1, true) ~= nil, "the prompt switches Ava's board to Friends (" .. boardText("Mode") .. ")")
	truthy(#boardText("Note") > 10, "and an empty friends board says something useful (" .. boardText("Note") .. ")")
	h:advance(1.1)
	prompt.Triggered:Fire(A)
	h:advance(0.5)
	truthy(string.find(boardText("Mode"), "PUBLIC", 1, true) ~= nil, "and back to Public")
end

--======================================================================= 5. the loop

local hum = charA:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
local bot = Bot.new(h, A, { react = 0.6 })
local card = RS:FindFirstChild("DRRemotes"):FindFirstChild("Card")
local toastR = RS:FindFirstChild("DRRemotes"):FindFirstChild("Toast")
local RunService = h.game:GetService("RunService")
local DT = 0.1
local active = { bot }
local function tick()
	for _, b in active do Bot.step(b, DT) end
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
end
local function untilPhase(phase: string, limit: number): boolean
	local n = 0
	while rf:GetAttribute("Phase") ~= phase and n < limit / DT do
		tick()
		n += 1
	end
	return rf:GetAttribute("Phase") == phase
end
local function cardsTo(plr, kind: string): number
	local n = 0
	for _, rec in card:sentTo(plr) do
		if rec.args[1] == kind then n += 1 end
	end
	return n
end

Config.Shots.ForceKind = "meteor"
-- the board section above let rounds run while Ava stood still; whatever round is on now (which one depends on which
-- disasters came, an even draw since REVIEW-1 F4), she sits it out standing still, and the loop starts at the next drop
do
	local keep = active
	active = {}
	untilPhase("intermission", 100)
	active = keep
end
truthy(untilPhase("drop", 30), "a drop comes within an intermission")
do
	eq(A:GetAttribute("InRound"), "counted", "Ava is in the round (counted)")
	local island = rf:FindFirstChild("Island")
	truthy(island ~= nil, "the island is in the workspace now")
	eq(SS:FindFirstChild("NextIsland"), nil, "and it is the one that was hidden: ServerStorage holds no island during the round")
	local p = hrpA.Position
	local i, j = MapGen.cellAt(IC, p.X, p.Z)
	local cx, cz = MapGen.cellCenter(IC, i or 7, j or 7)
	local cell = island and i and island.Cells:FindFirstChild("Cell_" .. i .. "_" .. j)
	truthy(cell ~= nil and math.abs(p.X - cx) <= 2 and math.abs(p.Z - cz) <= 2,
		string.format("Ava stands on her own cell (%.1f, %.1f), its centre (%d, %d)", p.X, p.Z, cx, cz))
	if cell then
		truthy(p.Y > MapGen.topY(IC, cell:GetAttribute("Level")), "above its top")
		truthy(cell:GetAttribute("Level") >= 1, "a cell above the beach")
	end
	eq(rf:GetAttribute("Kind"), nil, "the disaster is not named during the drop")
end
card:clearSent()
truthy(untilPhase("disaster", 5), "4 s later the disaster is named")
eq(rf:GetAttribute("Kind"), "meteor", "a Meteor Shower")
truthy(cardsTo(A, "name") >= 1, "the name card is sent")
untilPhase("outro", 70)
eq(cardsTo(A, "swept"), 0, "a player who steps out of every red ring is never hit")
eq(cardsTo(A, "survived"), 1, "SURVIVED")
eq(A:GetAttribute("Survived"), 1, "1 survival")
eq(A:GetAttribute("Streak"), 1, "streak 1")
eq(A:GetAttribute("Best"), 1, "best 1")
truthy(bot.dodges > 0, "Ava stepped out of the red " .. bot.dodges .. " times")
local ls = A:FindFirstChild("leaderstats")
eq(ls and ls.Streak.Value, 1, "leaderstats Streak 1")
untilPhase("intermission", 10)
truthy(hrpA.Position.X < LC.MaxX and hrpA.Position.X > LC.MinX and hrpA.Position.Y > LC.FloorY, "after the outro Ava is back on the Lookout")

-- a second round in a row: Heat 1 at the next drop
Config.Shots.ForceKind = "quake"
untilPhase("drop", 30)
untilPhase("intermission", 100)
eq(A:GetAttribute("Streak"), 2, "two in a row (a quake this time)")
untilPhase("drop", 30)
eq(A:GetAttribute("Heat"), 1, "Heat 1 at the next drop")
-- standing still: swept out
active = {}
card:clearSent()
untilPhase("intermission", 100)
eq(cardsTo(A, "swept"), 1, "standing still, Ava is swept out")
eq(A:GetAttribute("Streak"), 0, "her streak is gone")
eq(A:GetAttribute("Best"), 2, "her best (2) is not")
eq(A:GetAttribute("Survived"), 2, "nor her survivals")
local codex = A:GetAttribute("Codex")
truthy(codex == "0,-1,-1,1" or codex == "0,-1,-1,0", "the Codex keeps what she survived (" .. tostring(codex) .. ")")

--======================================================================= practice drop-in

local B = h:join("Bo", 502)
local charB = h.Players:simulateSpawn(B, ws)
h.Players.LocalPlayer = A
h:advance(0.5)
active = { bot }
untilPhase("disaster", 40)
-- Bo joined during the intermission and is in this round's roster: he waits for the next one
eq(B:GetAttribute("InRound"), "counted", "Bo, who joined in the intermission, is in the roster")
untilPhase("intermission", 100)
local C = h:join("Cy", 503)
local charC = h.Players:simulateSpawn(C, ws)
h.Players.LocalPlayer = A
untilPhase("disaster", 40)
-- Cy is in the roster too; make a fourth player join mid-round
local D = h:join("Dee", 504)
local charD = h.Players:simulateSpawn(D, ws)
h.Players.LocalPlayer = A
h:advance(1)
eq(D:GetAttribute("InRound"), "", "Dee, who joined mid-round, is on the Lookout")
local jump = RS:FindFirstChild("DRRemotes"):FindFirstChild("JumpIn")
toastR:clearSent()
jump:simulateFireServer(D)
h:advance(0.2)
eq(D:GetAttribute("InRound"), "practice", "Jump in: Dee drops in for practice")
jump:simulateFireServer(D)
h:advance(0.2)
truthy(#toastR:sentTo(D) >= 1, "a second tap is refused with a reason")
local dSurvivedBefore = D:GetAttribute("Survived")
local botD = Bot.new(h, D, { react = 0.6 })
table.insert(active, botD)
untilPhase("intermission", 100)
eq(D:GetAttribute("Survived"), dSurvivedBefore, "a practice round counts for nothing (Survived unchanged)")
eq(D:GetAttribute("Streak"), 0, "and no streak")

--======================================================================= leaving mid-round

active = { bot }
untilPhase("disaster", 40)
local streakBefore = A:GetAttribute("Streak")
local survivedBefore, bestBefore = A:GetAttribute("Survived"), A:GetAttribute("Best")
h:advance(2)
eq(A:GetAttribute("InRound"), "counted", "Ava is in a round")
h:leave(A)
h:advance(1)
toastR:clearSent()
local A2 = h:join("Ava", 501)
h.Players:simulateSpawn(A2, ws)
h:advance(1)
eq(A2:GetAttribute("Streak"), 0, "after leaving mid-round her streak is 0")
eq(A2:GetAttribute("Survived"), survivedBefore, "her survivals are kept")
eq(A2:GetAttribute("Best"), bestBefore, "and her best")
local told = false
for _, rec in toastR:sentTo(A2) do
	if string.find(tostring(rec.args[1]), "You left during a round", 1, true) then told = true end
end
truthy(told, string.format("the rejoin says why: \"You left during a round, so your streak ended at %d.\"", streakBefore))

--======================================================================= 6. the brag (21 survivals) and MAX HEAT (10 in a row)

do
	local store = h.services.DataStoreService:GetDataStore("DisasterRounds_v1")
	store:SetAsync("u_520", { v = 1, data = { survived = 20, played = 30, streak = 9, best = 9, bestAt = 1780000000 },
		session = { token = "old", expires = 0 } })
	local Z = h:join("Zed", 520)
	h.Players:simulateSpawn(Z, ws)
	h.Players.LocalPlayer = A2
	h:advance(0.5)
	eq(Z:GetAttribute("Survived"), 20, "Zed has survived 20 disasters")
	active = { Bot.new(h, Z, { react = 0.6 }) }
	untilPhase("intermission", 100)
	toastR:clearSent()
	card:clearSent()
	untilPhase("outro", 120)
	eq(Z:GetAttribute("Survived"), 21, "the 21st survival")
	eq(cardsTo(Z, "brag"), 1, "the brag card plays for Zed: THE SKY IS FALLING")
	local skyToast, heatToast = false, false
	for _, r in toastR:getSent() do
		local t = tostring(r.args[1])
		if r.all and string.find(t, "Their sky is falling", 1, true) then skyToast = true end
		if r.all and string.find(t, "MAX HEAT", 1, true) then heatToast = true end
	end
	truthy(skyToast, "and the whole server hears: \"☄️ Zed has survived 21 disasters. Their sky is falling.\"")
	truthy(heatToast, "the same survival is his 10th in a row: \"🔥 Zed hit MAX HEAT\" to the whole server")
	untilPhase("intermission", 10)
	untilPhase("outro", 120)
	eq(cardsTo(Z, "brag"), 1, "the brag plays once (the 22nd survival is not a brag)")
	active = {}
end

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	if string.find(w, "failed", 1, true) or string.find(w, "error", 1, true) then
		failed += 1
		print("FAIL: warning: " .. w)
	end
end
print(string.format("disasterrounds: %d passed, %d failed", passed, failed))
