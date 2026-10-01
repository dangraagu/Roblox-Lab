-- Labyrinth Mariozo — "walk out now, it's free, nothing is lost" holds in a shared run too (second review, 30.09).
-- Run: luau check_labyrintspill_friends.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- The free-break sign on every level's 🚪 Lobby door (RestClient, BreakRoom) promises that walking out in the first
-- seconds costs nothing. The review found one player it lied to: the HOST of a Friends run. The server lets a
-- player into a Friends run only when plr:IsFriendsWith(inst.hostUserId) is true, and Roblox never counts you as
-- your own friend, so a host who walked out could not get back: the Friends door opened a picker to host a NEW
-- run, and the friends were left alone in the old maze.
--
-- The stock emulator's IsFriendsWith always answers false. This file models Roblox's answer instead (the Player
-- class is redefined HERE, not in robloxemu/emu): A and B are friends, nobody is their own friend, and C and E are
-- strangers to everyone. Then, through the real server (and A's real clients, for the sign):
--   §1 the host's walk-out: A hosts a Friends run at L31, the sign is up, B joins through the Friends door; A walks
--      out 1.5 s in; the Friends door puts A back in the same maze with B, without a picker; so does the picker's
--      own route (StartRun "friends");
--   §2 nobody else gets in: a stranger taking the Friends door gets a picker, never A's maze, and hosts their own;
--   §3 a Group run keeps the same promise: a walker who comes back through the Group door is back in the same maze.

local Lib = require("./check_labyrintspill_lib")
local Harness = require("./emu/harness")
local T = Lib.counter("labyrintspill friends")
local truthy, eq = T.truthy, T.eq

local bundle = require("./build/labyrint-spill")
local h = Harness.new({ bundle = bundle, name = "labyrint-spill", viewport = { 1280, 720 } })

-- Roblox's friendship, as far as this file needs it. Everything else about the Player class is the emulator's
-- (instance.luau's definition, copied), so the only difference a game can see is IsFriendsWith.
local FRIENDS = { ["1001:1002"] = true, ["1002:1001"] = true }
h.instance.defineClass("Player", {
	parent = "Instance",
	events = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Idled", "Chatted" },
	defaults = { UserId = 0, Character = nil, RespawnLocation = nil, AccountAge = 0, MembershipType = "None" },
	methods = {
		IsFriendsWith = function(self, userId)
			return FRIENDS[tostring(self.UserId) .. ":" .. tostring(userId)] == true
		end,
		GetMouse = function() return nil end,
		Kick = function(self, reason) rawset(self, "__kicked", reason or true) end,
		LoadCharacter = function() error("robloxemu: Player:LoadCharacter() is not implemented", 2) end,
	},
})

local store = h.services.DataStoreService:GetDataStore("LabyrintSpill_v1")
for uid, acc in { [1001] = 40, [1002] = 0, [1003] = 40, [1004] = 40 } do
	store:SetAsync("p_" .. uid, { accepted = acc, coins = 50, gems = 1, level = 1, bestByLevel = {}, rewardDay = 1e9 })
end
local ok, err = h:tryRun("server/MazeGame.server")
assert(ok, "server failed to load: " .. tostring(err))
local RS = h.ReplicatedStorage
local Players = h.Players

-- join order: B, C, E first; A last, so A is the LocalPlayer whose clients run
local B = h:join("Bea", 1002)
local C = h:join("Cato", 1003)
local E = h:join("Eli", 1004)
local A = h:join("Ada", 1001)
h:advance(0.5)
for _, p in { B, C, E, A } do
	local ch = Players:simulateSpawn(p, h.workspace)
	local hum = ch:FindFirstChildOfClass("Humanoid")
	hum.FloorMaterial = Enum.Material.Plastic
end
h:advance(0.5)
eq(A:IsFriendsWith(1002), true, "(model) A and B are friends")
eq(A:IsFriendsWith(1001), false, "(model) nobody is their own friend, as in Roblox")
eq(C:IsFriendsWith(1001), false, "(model) C is a stranger to A")

local rsvc = h.game:GetService("RunService")
rsvc:setIsServer(false)
local loadErrors = {}
for _, c in Lib.CLIENTS_NO_SOUND do
	local okc, errc = h:tryRun("client/" .. c .. ".client")
	if not okc then table.insert(loadErrors, c .. ": " .. tostring(errc)) end
end
eq(#loadErrors, 0, "A's clients load (" .. table.concat(loadErrors, "; ") .. ")")
local function frames(seconds)
	local dt = 1 / 30
	for _ = 1, math.max(1, math.floor(seconds / dt + 0.5)) do
		rsvc.RenderStepped:Fire(dt)
		h:advance(dt)
	end
end
frames(0.5)

local lobby = h.workspace.Lobby
local function door(name) return lobby:FindFirstChild(name):FindFirstChildOfClass("ProximityPrompt") end
local picker = RS.LobbyRemotes.OpenPicker
local startRun = RS.LobbyRemotes.StartRun
local function maze(p) return p:GetAttribute("MazeFolder") end
local function pickersTo(p) return #picker:sentTo(p) end
local function walkOut(p)
	local f = h.workspace:FindFirstChild(maze(p) or "")
	local pr = f and f:FindFirstChild("LobbyDoor") and f.LobbyDoor:FindFirstChildOfClass("ProximityPrompt")
	truthy(pr ~= nil, p.Name .. " has a Lobby door to walk out through")
	if pr then pr.Triggered:Fire(p) end
	frames(0.2)
end

--================================================================ §1 the host walks out, and comes back

do
	door("FriendsDoor").Triggered:Fire(A)
	eq(pickersTo(A), 1, "§1 no friend is hosting: the Friends door opens A's picker (A will host)")
	startRun:simulateFireServer(A, 31, "friends")
	local hostMaze = maze(A)
	truthy(hostMaze ~= nil, "§1 A hosts a Friends run at L31 (" .. tostring(hostMaze) .. ")")
	frames(1.0)
	local sign = h.workspace:FindFirstChild("LabyrintBreakRoom") and h.workspace.LabyrintBreakRoom:FindFirstChild("BreakSign")
	local label = sign and sign:FindFirstChild("Text")
	truthy(label ~= nil and string.find(label.Text, "nothing is lost", 1, true) ~= nil,
		"§1 1.0 s in, the host's sign says the walk-out is free and nothing is lost")
	door("FriendsDoor").Triggered:Fire(B)
	eq(maze(B), hostMaze, "§1 B, A's friend, joins A's run through the Friends door")
	frames(0.5)
	walkOut(A)
	eq(maze(A), nil, "§1 A walks out 1.5 s in (under the sign)")
	eq(maze(B), hostMaze, "§1 B is still in the maze")
	local before = pickersTo(A)
	door("FriendsDoor").Triggered:Fire(A)
	frames(0.2)
	eq(maze(A), hostMaze, "§1 the Friends door puts the host back in the same run as their friend")
	eq(pickersTo(A) - before, 0, "§1 without opening a picker to host a new run")
	-- the picker's own route: a StartRun("friends") from the lobby joins the own run too, not a new one
	walkOut(A)
	eq(maze(A), nil, "§1 A walks out again")
	startRun:simulateFireServer(A, 31, "friends")
	frames(0.2)
	eq(maze(A), hostMaze, "§1 StartRun(friends) also puts the host back in their own run")
	eq(maze(B), hostMaze, "§1 and B never left it")
end

--================================================================ §2 nobody else gets in

do
	local hostMaze = maze(A)
	local before = pickersTo(C)
	door("FriendsDoor").Triggered:Fire(C)
	frames(0.2)
	eq(maze(C), nil, "§2 a stranger taking the Friends door is not put in A's run")
	eq(pickersTo(C) - before, 1, "§2 they get the picker to host their own")
	startRun:simulateFireServer(C, 12, "friends")
	frames(0.2)
	truthy(maze(C) ~= nil and maze(C) ~= hostMaze, "§2 and host their own run (" .. tostring(maze(C)) .. "), never A's")
	walkOut(C)
end

--================================================================ §3 a Group run keeps the promise too

do
	door("GroupDoor").Triggered:Fire(C)
	local groupMaze = maze(C)
	truthy(groupMaze ~= nil, "§3 C opens a Group run at L41")
	door("GroupDoor").Triggered:Fire(E)
	eq(maze(E), groupMaze, "§3 E, at the same level, is matched into it")
	frames(1.5)
	walkOut(C)
	eq(maze(C), nil, "§3 C walks out 1.5 s in")
	door("GroupDoor").Triggered:Fire(C)
	eq(maze(C), groupMaze, "§3 the Group door puts C back in the same run with E")
end

T.finish(h)
