-- Labyrinth Mariozo — the wall themes and the minimap must find THIS player's maze.
-- Run: luau check_themes.luau   (regenerate the bundle first, see check_labyrint.luau)
--
-- Both were dead in the live game. ShopClient and MinimapClient looked for
-- `workspace.MazeGame`, but the live builder `buildInstance` names its folder `Maze_<id>` --
-- only the unused `buildLevel` ever creates a `MazeGame`. So `recolorAll` returned on its first
-- line every single time and the minimap never found anything to draw. Seventeen wall themes at
-- 500-2000 coins or 25-75 gems, and an 800-coin minimap perk, took payment for nothing.
--
-- Swapping the name is not enough, and that is what this check is really for: with per-player
-- instances there are MANY `Maze_<id>` folders in the workspace at once, one per active player.
-- A client that grabbed the first would repaint, or draw a map of, somebody ELSE's maze. So the
-- test builds two instances and asserts the theme lands on exactly one of them.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/labyrint-spill"),
	name = "labyrint-spill",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local function rgbOf(c)
	if c == nil then return "nil" end
	return string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

-- The theme under test. Lava's wall colour is {210, 80, 28} in src/shared/Themes.luau, which is
-- nothing like the classic wall (90, 94, 105), so a repaint is unmistakable.
local THEME_ID = "lava"
local THEME_WALL = "210,80,28"
local CLASSIC_WALL = "90,94,105"

local ME, OTHER = 4242, 5353
for _, id in { ME, OTHER } do
	h.services.DataStoreService:GetDataStore("LabyrintSpill_v1"):SetAsync("p_" .. id, {
		accepted = 20, coins = 99999, gems = 999, level = 1, bestByLevel = {},
		owned = { classic = true, lava = true }, theme = "classic",
	})
end

assert(h:tryRun("server/MazeGame.server"))

-- I am the LocalPlayer: the client scripts run as me.
local me = h:join("ThemeTester", ME)
h:advance(1)
local myChar = h.Players:simulateSpawn(me, h.workspace)
h:advance(1)

-- A second player, in their own instance, so there are two Maze_<id> folders to confuse a
-- client that guesses. simulateJoin does not touch LocalPlayer, so I stay the local one.
local other = h.Players:simulateJoin("Neighbour", OTHER)
h:advance(0.5)
h.Players:simulateSpawn(other, h.workspace)
h:advance(0.5)

local startRun = h.ReplicatedStorage:WaitForChild("LobbyRemotes"):WaitForChild("StartRun")
startRun.OnServerEvent:Fire(other, 3)
h:advance(2)
startRun:FireServer(1)
h:advance(2)

--=================================================================== the folders exist and differ

local myFolderName = me:GetAttribute("MazeFolder")
local otherFolderName = other:GetAttribute("MazeFolder")
print("  my folder    : " .. tostring(myFolderName))
print("  their folder : " .. tostring(otherFolderName))

truthy(type(myFolderName) == "string", "the server marked me with my own maze folder")
truthy(type(otherFolderName) == "string", "the server marked the other player too")
truthy(myFolderName ~= otherFolderName, "the two players are in DIFFERENT folders")

local myFolder = h.workspace:FindFirstChild(myFolderName or "")
local otherFolder = h.workspace:FindFirstChild(otherFolderName or "")
truthy(myFolder ~= nil, "my folder is in the workspace")
truthy(otherFolder ~= nil, "their folder is in the workspace")

-- The old code looked for this name and found nothing, which is the whole bug.
eq(h.workspace:FindFirstChild("MazeGame"), nil, "there is no folder called MazeGame in the live path")

local function wallsIn(folder)
	local out = {}
	local function walk(node)
		for _, c in node:GetChildren() do
			if c.Name == "Wall" then table.insert(out, c) end
			walk(c)
		end
	end
	if folder then walk(folder) end
	return out
end

local myWalls, theirWalls = wallsIn(myFolder), wallsIn(otherFolder)
truthy(#myWalls > 0, "my maze has walls to paint")
truthy(#theirWalls > 0, "their maze has walls too")

for _, w in myWalls do
	if rgbOf(w.Color) ~= CLASSIC_WALL then
		failed += 1
		print("FAIL: a wall did not start at the classic colour -> " .. rgbOf(w.Color))
		break
	end
end
passed += 1

--=========================================================== the client paints MY maze, not theirs

assert(h:tryRun("client/ShopClient.client"))
h:advance(1)

local shopData = h.ReplicatedStorage:WaitForChild("ShopRemotes"):WaitForChild("ShopData")
shopData:FireClient(me, {
	coins = 99999, gems = 999,
	owned = { classic = true, lava = true },
	theme = THEME_ID,
})
h:advance(1)

local mineRepainted, mineMissed = 0, 0
for _, w in myWalls do
	if rgbOf(w.Color) == THEME_WALL then mineRepainted += 1 else mineMissed += 1 end
end
local theirsRepainted = 0
for _, w in theirWalls do
	if rgbOf(w.Color) ~= CLASSIC_WALL then theirsRepainted += 1 end
end

print(string.format("  my walls repainted    : %d of %d", mineRepainted, #myWalls))
print(string.format("  their walls repainted : %d of %d  (must be 0)", theirsRepainted, #theirWalls))

-- This is the assertion the shipped game fails: zero walls were ever repainted, because
-- recolorAll could not find a folder at all.
eq(mineMissed, 0, "every wall in MY maze took the theme")
truthy(mineRepainted > 0, "the theme actually repainted something")
eq(theirsRepainted, 0, "no wall in the OTHER player's maze was touched")

--=================================================== the minimap finds the same folder, or nothing

-- The minimap is the other half of the same defect: it looked for workspace.MazeGame too, so the
-- 800-coin perk drew nothing. Its frame is shown only when it owns the perk AND has found a
-- folder AND measured a floor, so a visible frame is proof that all three happened.
assert(h:tryRun("client/MinimapClient.client"))
h:advance(1)

local perkData = h.ReplicatedStorage:WaitForChild("PerkRemotes"):WaitForChild("PerkData")
perkData:FireClient(me, { coins = 99999, perks = { minimap = true } })
h:advance(2)

local mapFrame = nil
local function findFrame(node)
	for _, c in node:GetChildren() do
		if c.Name == "Kart" then
			mapFrame = c
			return
		end
		findFrame(c)
	end
end
local pg = me:FindFirstChild("PlayerGui")
if pg then findFrame(pg) end

-- A frame that cannot be found is a FAILURE, not a note. Scoring "I could not check" as a pass
-- is how two defects reached a live game earlier in this project.
if mapFrame == nil then
	failed += 1
	print("FAIL: the minimap frame 'Kart' was never created")
else
	truthy(mapFrame.Visible == true, "the minimap is visible once the perk is owned and the maze found")
end

print("")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("themes: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("theme check failed", 0)
end
