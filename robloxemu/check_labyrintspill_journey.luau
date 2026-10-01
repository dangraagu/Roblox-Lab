-- Labyrinth Mariozo — the whole player path, walked. Run: luau check_labyrintspill_journey.luau 2>&1
-- Rebuild the bundle first: py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau
--
-- docs/complete-game-standard.md §1: "The core loop is reachable from join. Walk the real player path headless:
-- spawn, first objective, one full loop, earn, spend, rejoin. Green unit tests are not a working game."
-- The other checks start runs through the StartRun remote and finish them by firing Exit.Touched on the spot. This
-- one does what a player does: joins (into a server whose script had not even started yet, as in a Studio play),
-- is spawned by the engine on the lobby pad, WALKS to the Solo door at 16 studs/s and uses its prompt, picks a level
-- in the real LobbyClient picker, WALKS the maze cell by cell to every coin and then to the exit (a coin or the exit
-- counts only when the character is standing on it), goes on to level 2, tries to teleport to its exit (refused by
-- the walk guard, and told why), walks it instead, walks back out through the Lobby door, spends the coins it
-- earned, leaves, and rejoins to find everything where it left it. Headless limits: no physics, so walking is the
-- check moving the root part in straight segments between cell centres at walking speed, one frame at a time.

local Harness = require("./emu/harness")
local Lib = require("./check_labyrintspill_lib")
local c = Lib.counter("labyrintspill journey")
local eq, truthy = c.eq, c.truthy

local h = Harness.new({ bundle = require("./build/labyrint-spill"), name = "labyrint-spill", viewport = { 800, 360 }, touch = true })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local today = math.floor(os.time() / 86400)
local UID = 9001
local SEED_COINS = 299 -- one coin short of the Longer torch (300): only what the walk earns can buy it

-- a returning player (saved yesterday-or-earlier data; today's daily reward already taken, so every coin below is earned)
DSS:GetDataStore("LabyrintSpill_v1"):SetAsync("p_" .. UID, { coins = SEED_COINS, gems = 0, accepted = 0, level = 1, rewardDay = today })

--========================================================================= 1. join, before the server has started

print("== 1. join ==")
local plr = h:join("Mira", UID) -- in the server before its script runs (a Studio play does this)
local okServer, errServer = h:tryRun("server/MazeGame.server")
truthy(okServer, "the server runs: " .. tostring(errServer))
local lobby = h.workspace:FindFirstChild("Lobby")
local pad = lobby and lobby:FindFirstChild("LobbySpawn")
eq(plr.RespawnLocation, pad, "a player who was here before the lobby existed still gets RespawnLocation = the lobby pad")
local char = h.Players:simulateSpawn(plr, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Plastic
truthy(pad ~= nil and math.abs(hrp.Position.X - pad.Position.X) <= 4 and math.abs(hrp.Position.Z - pad.Position.Z) <= 4,
	"the engine spawned them on the lobby pad (" .. tostring(hrp.Position) .. ")")
local RunS = h.game:GetService("RunService")
RunS:setIsServer(false)
local clients = Lib.CLIENTS_NO_SOUND
for _, name in clients do
	local ok, err = h:tryRun("client/" .. name .. ".client")
	truthy(ok, name .. " loads (" .. tostring(err) .. ")")
end
local cam = h.workspace.CurrentCamera
local function frame(dt)
	cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 10, 14), hrp.Position)
	RunS.RenderStepped:Fire(dt)
	h:advance(dt)
end
local function run(seconds)
	for _ = 1, math.max(1, math.floor(seconds * 30 + 0.5)) do frame(1 / 30) end
end
run(1)
local function coins() return plr.leaderstats.Coins.Value end
eq(coins(), SEED_COINS, "their saved coins are loaded")

-- the character walks: straight segments at 16 studs/s, one frame at a time, the camera following
local WALK = 16
local onStep -- called after every frame of a walk (pickups)
local function walkTo(target)
	local from = hrp.Position
	local flat = Vector3.new(target.X, from.Y, target.Z)
	local dist = (flat - from).Magnitude
	local n = math.max(1, math.ceil(dist / WALK * 30))
	for i = 1, n do
		hrp.CFrame = CFrame.new(from:Lerp(flat, i / n))
		hum.MoveDirection = (flat - from).Unit
		frame(1 / 30)
		if onStep then onStep() end
	end
	hum.MoveDirection = Vector3.new(0, 0, 0)
end

local notices = RS.HudRemotes:WaitForChild("Broadcast")
local function lastNotice()
	local sent = notices:sentTo(plr)
	local r = sent[#sent]
	return r and not r.all and r.args[2] or nil
end
local levelInfo = RS.HudRemotes:WaitForChild("LevelInfo")
local function lastInfo()
	local sent = levelInfo:sentTo(plr)
	return sent[#sent] and sent[#sent].args[1]
end
local completes = RS.HudRemotes:WaitForChild("LevelComplete")

--========================================================================= 2. the door

print("== 2. walk to the Solo door, use it, pick a level ==")
local door = lobby:FindFirstChild("SoloDoor")
local doorPrompt = door and door:FindFirstChildOfClass("ProximityPrompt")
truthy(doorPrompt ~= nil, "the Solo door has a prompt")
walkTo(door.Position + Vector3.new(0, 0, 6))
local d = (hrp.Position - door.Position)
truthy(Vector3.new(d.X, 0, d.Z).Magnitude <= doorPrompt.MaxActivationDistance,
	string.format("walked to within the prompt's reach (%.1f of %d studs)", Vector3.new(d.X, 0, d.Z).Magnitude, doorPrompt.MaxActivationDistance))
doorPrompt.Triggered:Fire(plr)
run(0.5)
local picker = plr.PlayerGui:FindFirstChild("LobbyPicker")
truthy(picker ~= nil and picker.Enabled == true, "the level picker opens")
local continueBtn = nil
if picker then
	for _, b in picker:GetDescendants() do
		if b:IsA("TextButton") and b.Visible ~= false and string.find(string.lower(b.Text or ""), "continue", 1, true) then continueBtn = b end
	end
end
truthy(continueBtn ~= nil, "with a Continue button")
if continueBtn then continueBtn.Activated:Fire() end
run(0.5)
local folderName = plr:GetAttribute("MazeFolder")
local folder = folderName and h.workspace:FindFirstChild(folderName)
truthy(folder ~= nil, "Continue started a run (" .. tostring(folderName) .. ")")
eq(lastInfo() and lastInfo().level, 1, "on level 1 (accepted 0 + 1)")

--========================================================================= 3. the maze, walked

-- a route through the fine grid (walls as the client sees them; secret doors closed), by BFS with parents
local function route(g, from, to)
	local key = function(x, y) return x .. "," .. y end
	local prev, q, head = { [key(from[1], from[2])] = false }, { from }, 1
	while head <= #q do
		local cur = q[head]; head += 1
		if cur[1] == to[1] and cur[2] == to[2] then break end
		for _, dd in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nx, ny = cur[1] + dd[1], cur[2] + dd[2]
			if nx >= 0 and ny >= 0 and nx < g.gCols and ny < g.gRows and not g.walls[key(nx, ny)] and prev[key(nx, ny)] == nil then
				prev[key(nx, ny)] = cur
				table.insert(q, { nx, ny })
			end
		end
	end
	local path, cur = {}, to
	while cur do
		table.insert(path, 1, cur)
		cur = prev[key(cur[1], cur[2])]
	end
	return path
end

local function standingOn(part, reach)
	local dx, dz = hrp.Position.X - part.Position.X, hrp.Position.Z - part.Position.Z
	return math.abs(dx) <= part.Size.X / 2 + reach and math.abs(dz) <= part.Size.Z / 2 + reach
end

-- walk a level: every coin first (nearest by route), then the exit; returns the seconds walked
local function walkLevel(f)
	local g = Lib.grid(f)
	local here = { g.fine(hrp.Position) }
	local picked = 0
	onStep = function()
		for _, part in f:GetChildren() do
			if (part.Name == "Coin" or part.Name == "Gem") and part.Parent and standingOn(part, 1) then
				part.Touched:Fire(hrp)
				picked += 1
			end
		end
	end
	local walked = 0
	local function go(target)
		for i, cell in route(g, here, target) do
			if i > 1 then
				walkTo(g.world(cell[1], cell[2]))
				walked += g.S / WALK
			end
		end
		here = target
	end
	local left = {}
	for _, part in f:GetChildren() do
		if part.Name == "Coin" then table.insert(left, { g.fine(part.Position) }) end
	end
	while #left > 0 do
		local best, bestLen = 1, math.huge
		for i, cell in left do
			local len = #route(g, here, cell)
			if len < bestLen then best, bestLen = i, len end
		end
		go(table.remove(left, best))
	end
	local exit = f:FindFirstChild("Exit")
	go({ g.fine(exit.Position) })
	onStep = nil
	return walked, picked, exit
end

print("== 3. level 1, walked: every coin, then the exit ==")
do
	local coins0 = coins()
	local n0 = #completes:sentTo(plr)
	local walked, picked, exit = walkLevel(folder)
	print(string.format("  walked %.1f s, picked up %d coins/gems", walked, picked))
	truthy(coins() > coins0, string.format("walking over coins earned them (%d -> %d)", coins0, coins()))
	truthy(standingOn(exit, 0), "the character stands on the exit pad")
	exit.Touched:Fire(hrp)
	run(0.5)
	eq(#completes:sentTo(plr) - n0, 1, "the exit counts: the level-complete card")
	eq(lastInfo() and lastInfo().accepted, 1, "accepted is now 1")
	eq(lastInfo() and lastInfo().level, 2, "and the run goes on to level 2")
	eq(plr.leaderstats.Trophies.Value, 1, "a trophy")
end

--========================================================================= 4. the walk guard

print("== 4. level 2: a teleport to the exit is refused ==")
do
	folder = h.workspace:FindFirstChild(plr:GetAttribute("MazeFolder") or "")
	local exit = folder and folder:FindFirstChild("Exit")
	local start = hrp.Position
	local n0 = #completes:sentTo(plr)
	hrp.CFrame = CFrame.new(exit.Position + Vector3.new(0, 3, 0))
	exit.Touched:Fire(hrp)
	run(0.3)
	eq(#completes:sentTo(plr) - n0, 0, "an exit reached by teleport does not count")
	eq(lastInfo() and lastInfo().accepted, 1, "accepted is still 1")
	local note = lastNotice()
	truthy(note ~= nil and string.find(string.lower(note), "walk", 1, true) ~= nil, "and the player is told why: " .. tostring(note))
	exit.Touched:Fire(hrp)
	run(0.3)
	eq(#completes:sentTo(plr) - n0, 0, "touching it again straight away does not count either")
	-- back to the start, and walk it
	hrp.CFrame = CFrame.new(start)
	run(0.2)
	folder = h.workspace:FindFirstChild(plr:GetAttribute("MazeFolder") or "") -- the same maze, unless the teleport counted
	local walked, _, exit2 = walkLevel(folder)
	exit = exit2
	print(string.format("  level 2 walked in %.1f s", walked))
	exit.Touched:Fire(hrp)
	run(0.5)
	eq(#completes:sentTo(plr) - n0, 1, "walked, the same exit counts")
	eq(lastInfo() and lastInfo().accepted, 2, "accepted is now 2")
end

--========================================================================= 5. back to the lobby, spend

print("== 5. out through the Lobby door, then spend ==")
do
	folder = h.workspace:FindFirstChild(plr:GetAttribute("MazeFolder") or "")
	local ldoor = folder and folder:FindFirstChild("LobbyDoor")
	local lprompt = ldoor and ldoor:FindFirstChildOfClass("ProximityPrompt")
	truthy(lprompt ~= nil, "level 3 has a Lobby door by the start")
	walkTo(ldoor.Position + Vector3.new(0, 0, 3))
	local dd = hrp.Position - ldoor.Position
	truthy(Vector3.new(dd.X, 0, dd.Z).Magnitude <= lprompt.MaxActivationDistance, "walked up to it")
	lprompt.Triggered:Fire(plr)
	run(1)
	eq(plr:GetAttribute("MazeFolder"), nil, "back in the lobby")
	eq(lastInfo() and lastInfo().inLobby, true, "the HUD knows it")
	truthy(hrp.Position.Magnitude < 40, "standing in the lobby (" .. tostring(hrp.Position) .. ")")
	local before = coins()
	truthy(before >= 300, "the walk earned enough for the Longer torch (" .. before .. " coins)")
	local res = RS.PerkRemotes.BuyPerk:simulateInvokeServer(plr, "torch")
	eq(res and res.ok, true, "buying it works")
	eq(coins(), before - 300, "and costs 300 coins")
	run(1)
end

--========================================================================= 6. leave and rejoin

print("== 6. leave, rejoin ==")
local coinsLeft = coins()
local store = DSS:GetDataStore("LabyrintSpill_v1")
h:leave(plr)
run(1)
local rec = store.__data["p_" .. UID]
eq(rec and rec.lockUntil, 0, "leaving saved and released the record")
local plr2 = h:join("Mira", UID)
run(0.5)
eq(plr2.RespawnLocation, pad, "the rejoin points at the lobby pad too")
local char2 = h.Players:simulateSpawn(plr2, h.workspace)
hrp = char2:FindFirstChild("HumanoidRootPart")
plr = plr2
run(3)
eq(plr2.leaderstats.Coins.Value, coinsLeft, "the coins are where they were left (" .. coinsLeft .. ")")
eq(plr2.leaderstats.Trophies.Value, 2, "and the two trophies")
local perkData = RS.PerkRemotes.PerkData:sentTo(plr2)
local pd = perkData[#perkData] and perkData[#perkData].args[1]
eq(pd and pd.perks and pd.perks.torch, true, "and the perk they bought")
eq(lastInfo() and lastInfo().accepted, 2, "and the levels they cleared (accepted 2)")
truthy(pad ~= nil and math.abs(hrp.Position.X - pad.Position.X) <= 4 and math.abs(hrp.Position.Z - pad.Position.Z) <= 4,
	"spawned back on the lobby pad")
local lb = DSS:GetOrderedDataStore("LabyrintTopp_v3")
local v = lb.__data["u_" .. UID]
eq(type(v) == "number" and math.floor(v / 2e9 + 0.5), 2, "and the highscore board holds level 2 for them")

for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "no warnings")
c.finish(h)
