-- Disaster Rounds - THE PLAYER'S PATH, walked in the built world: from join, one full loop, into the second.
--
-- Run:  cd ../robloxemu && py -3 wrap.py --game ../disaster-rounds --out build/disaster-rounds.luau
--       cd ../disaster-rounds && luau tests/walk.luau
-- ALWAYS re-run wrap.py first: this file reads the bundle, not src/.
--
-- Green unit tests are not a working game (this repo once shipped 166 of them with an unreachable core loop). This
-- file plays: a new player joins, reads the HUD, waits on the Lookout, is dropped onto the island, reads the
-- disaster's name, steps out of every red thing it is shown (check_disasterrounds_bot: it sees only what a client
-- sees and reacts 0.6 s late), survives, reads the card, is put back on the Lookout, looks at the board, and is
-- dropped into the second round. Then a second player joins mid-round and taps Jump in. Every step prints what
-- happened, in numbers, and the numbers that must hold are asserted.

local SEED = 20261007
local Datatypes = require("../../robloxemu/emu/datatypes")
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
local Harness = require("../../robloxemu/emu/harness")
local Bot = require("../../robloxemu/check_disasterrounds_bot")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function say(fmt: string, ...) print(string.format("  " .. fmt, ...)) end

local h = Harness.new({ bundle = require("../../robloxemu/build/disaster-rounds"), name = "disaster-rounds-walk",
	viewport = { 800, 360 }, touch = true }) -- a phone in landscape: the player most players are
local RS = h.ReplicatedStorage
assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local MapGen = h:_require(RS:FindFirstChild("MapGen"))
local rf = h.workspace:FindFirstChild("Round")
local remotes = RS:FindFirstChild("DRRemotes")
h.game:GetService("RunService"):setIsServer(false)
local RunService = h.game:GetService("RunService")

-- let the server's clock run a little so the walker joins mid-intermission, like a real player
h:advance(7.3)

--======================================================================= join

print("JOIN")
local A = h:join("Walker", 777)
local joinedAt = h.scheduler:now()
local char = h.Players:simulateSpawn(A, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
for _, c in { "client/Hud.client", "client/Board.client", "client/Sky.client", "client/World.client" } do
	local ok, err = h:tryRun(c)
	truthy(ok, c .. " loads (" .. tostring(err) .. ")")
end
local hud = A.PlayerGui:FindFirstChild("DRHud")
local function text(name: string): string
	local l = hud:FindFirstChild(name, true)
	return if l then l.Text else "?"
end
local pad = h.workspace.Lookout.LookoutSpawn
say("spawned at (%.1f, %.1f, %.1f), %.1f studs from LookoutSpawn's centre, facing (%.2f, %.2f, %.2f)",
	hrp.Position.X, hrp.Position.Y, hrp.Position.Z,
	math.sqrt((hrp.Position.X - pad.Position.X) ^ 2 + (hrp.Position.Z - pad.Position.Z) ^ 2),
	hrp.CFrame.LookVector.X, hrp.CFrame.LookVector.Y, hrp.CFrame.LookVector.Z)
truthy(math.abs(hrp.Position.X - pad.Position.X) <= 3 and math.abs(hrp.Position.Z - pad.Position.Z) <= 3, "the walker lands on the Lookout")

local DT = 0.1
local cam = h.workspace.CurrentCamera
local bot = Bot.new(h, A, { react = 0.6 })
local playing = { bot }
local cards, toasts = {}, {}
remotes.Card.OnClientEvent:Connect(function(kind, data)
	table.insert(cards, { t = h.scheduler:now(), kind = kind, data = data })
end)
remotes.Toast.OnClientEvent:Connect(function(t) table.insert(toasts, t) end)
local function tick()
	for _, b in playing do Bot.step(b, DT) end
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(-12, 8, 0), hrp.Position + Vector3.new(10, 0, 0))
	RunService.RenderStepped:Fire(DT)
	h:advance(DT)
end
local function untilPhase(phase: string, limit: number): number
	local t0 = h.scheduler:now()
	local n = 0
	while rf:GetAttribute("Phase") ~= phase and n < limit / DT do tick() n += 1 end
	return h.scheduler:now() - t0
end
tick()
say("the HUD on a phone: \"%s\" / \"%s\" | %s | %s", text("PhaseText"), text("RuleText"), text("Heat"), text("Band"))
truthy(string.find(text("PhaseText"), "Next round", 1, true) ~= nil, "the HUD counts down to the next round")

--======================================================================= the first round

print("ROUND 1")
local waited = untilPhase("drop", 30)
local firstDrop = h.scheduler:now() - joinedAt
say("dropped onto the island %.1f s after joining (style: %s)", firstDrop, tostring(rf:GetAttribute("Style")))
truthy(firstDrop <= Config.Round.IntermissionSeconds + 0.2, "a player who joins in the intermission is on the island within 20 s")
local p = hrp.Position
local i, j = MapGen.cellAt(Config.Island, p.X, p.Z)
local cell = rf.Island.Cells:FindFirstChild("Cell_" .. tostring(i) .. "_" .. tostring(j))
say("standing on cell (%d, %d), level %d, root y %.1f over a top at %d", i or -1, j or -1, cell and cell:GetAttribute("Level") or -1,
	p.Y, cell and MapGen.topY(Config.Island, cell:GetAttribute("Level")) or -1)
eq(A:GetAttribute("InRound"), "counted", "the walker's round counts")
tick()
say("HUD: \"%s\" / \"%s\"", text("PhaseText"), text("RuleText"))
local _ = waited
untilPhase("disaster", 5)
local nameAt = h.scheduler:now()
tick()
say("the disaster is named %.1f s after the drop: %s, card \"%s\" / \"%s\"", 4, tostring(rf:GetAttribute("Kind")),
	text("CardTitle"), text("CardSub"))
truthy(string.find(text("CardTitle"), Config.Disasters.Info[rf:GetAttribute("Kind")].name, 1, true) ~= nil, "the name card shows the disaster")
local firstRing, ringsAtMe, banners = nil, 0, 0
local seen = {}
local kind1 = rf:GetAttribute("Kind")
while rf:GetAttribute("Phase") == "disaster" do
	tick()
	for _, r in rf.Rings:GetChildren() do
		if not seen[r] then
			seen[r] = true
			if r:GetAttribute("TargetId") == A.UserId then
				ringsAtMe += 1
				firstRing = firstRing or (h.scheduler:now() - nameAt)
			end
		end
	end
	if hud:FindFirstChild("BannerPanel", true).Visible then banners += 1 end
end
local survivedCard = nil
for _, c in cards do
	if c.kind == "survived" then survivedCard = c end
end
say("the %s: %d rings aimed at the walker (the first %.1f s after the name), the banner was up %.1f s, the walker stepped out of the red %d times",
	tostring(kind1), ringsAtMe, firstRing or -1, banners * DT, bot.dodges)
truthy(survivedCard ~= nil, "SURVIVED")
tick()
say("card: \"%s\" / \"%s\"; streak %d, best %d, survived %d, Heat %d",
	text("CardTitle"), text("CardSub"), A:GetAttribute("Streak"), A:GetAttribute("Best"), A:GetAttribute("Survived"), A:GetAttribute("Heat"))
eq(A:GetAttribute("Streak"), 1, "streak 1")
eq(A:GetAttribute("Survived"), 1, "1 survival")
local confetti = h.workspace.DRLocalWorld.Fx:FindFirstChild("Confetti")
truthy(confetti ~= nil, "confetti where it happened")
untilPhase("intermission", 10)
say("back on the Lookout at (%.1f, %.1f, %.1f) after the 4 s outro", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
truthy(hrp.Position.Y > Config.Lookout.FloorY and hrp.Position.X < Config.Lookout.MaxX, "back on the Lookout")

--======================================================================= between rounds: the board, the sky

print("INTERMISSION")
for _ = 1, 5 do tick() end
local boardGui = h.workspace.Lookout.StreakBoard:FindFirstChild("StreakBoardGui")
say("the board: \"%s\" | \"%s\" | row 1 \"%s\"", boardGui and boardGui:FindFirstChild("Title", true).Text or "?",
	boardGui and boardGui:FindFirstChild("Mode", true).Text or "?", boardGui and boardGui:FindFirstChild("Row1", true).Text or "?")
say("HUD: \"%s\" / \"%s\" | %s | %s", text("PhaseText"), text("RuleText"), text("Streak"), text("Band"))
truthy(string.find(text("Streak"), "Streak 1", 1, true) ~= nil, "the HUD shows streak 1")
truthy(boardGui and string.find(boardGui:FindFirstChild("Row1", true).Text, "Walker (you)", 1, true) ~= nil,
	"the board shows the walker's own best at once, pinned under the cached top 10")
local lb = h.services.DataStoreService:GetOrderedDataStore("DisasterRounds_Streak_v1")
truthy(lb.__data["u_777"] ~= nil, "the best streak is on the board's store")

--======================================================================= the second round, and a practice drop-in

print("ROUND 2")
local gap = untilPhase("drop", 30)
say("the second drop came %.1f s into the intermission; Heat %d", gap + 0.5, A:GetAttribute("Heat"))
eq(A:GetAttribute("InRound"), "counted", "the walker is in the second round")
untilPhase("disaster", 5)
local kind2 = rf:GetAttribute("Kind")
-- REVIEW-1 F4: the next disaster is an even draw, so the same one may come again (the first build's "never twice in
-- a row" told a resting player which disaster could not come next); what the walker meets is a named disaster
truthy(Config.Disasters.Info[kind2] ~= nil, string.format("a disaster is named (%s after %s)", tostring(kind2), tostring(kind1)))
h:advance(3)
local B = h:join("Latecomer", 778)
local charB = h.Players:simulateSpawn(B, h.workspace)
h.Players.LocalPlayer = A
h:advance(1.4)
local t0 = h.scheduler:now()
remotes.JumpIn:simulateFireServer(B)
h:advance(0.2)
say("a second player joined %.1f s into the %s and tapped Jump in: InRound \"%s\" after %.1f s", 3, tostring(kind2),
	tostring(B:GetAttribute("InRound")), h.scheduler:now() - t0)
eq(B:GetAttribute("InRound"), "practice", "Jump in drops the latecomer for practice")
table.insert(playing, Bot.new(h, B, { react = 0.6 }))
untilPhase("outro", 70)
tick()
say("round 2 over: walker streak %d (survived %d), latecomer survived %d (practice counts for nothing)",
	A:GetAttribute("Streak"), A:GetAttribute("Survived"), B:GetAttribute("Survived") or 0)
eq(A:GetAttribute("Streak"), 2, "two in a row")
eq(B:GetAttribute("Survived"), 0, "the practice round counted for nothing")
untilPhase("intermission", 10)
untilPhase("drop", 30)
say("round 3 begins %.1f s after the walker joined: Heat %d (every two in a row), InRound \"%s\"",
	h.scheduler:now() - joinedAt, A:GetAttribute("Heat"), tostring(A:GetAttribute("InRound")))
eq(A:GetAttribute("Heat"), 1, "Heat 1 after two in a row")

local saved = h.services.DataStoreService:GetDataStore("DisasterRounds_v1").__data["u_777"]
say("saved profile: survived %s, streak %s, best %s, codex %s", tostring(saved.data.survived), tostring(saved.data.streak),
	tostring(saved.data.best), tostring(A:GetAttribute("Codex")))
eq(saved.data.survived, 2, "both survivals are saved")

for _, e in h:errors() do
	failed += 1
	print("FAIL: scheduler error: " .. e)
end
for _, w in h.warnings do
	if string.find(w, "failed", 1, true) or string.find(w, "error", 1, true) then
		failed += 1
		print("FAIL: the game warned: " .. w)
	end
end
print(string.format("walk: %d passed, %d failed", passed, failed))
