-- Labyrinth Mariozo — the wall themes and the minimap must find THIS player's maze.
-- Run: luau check_themes.luau   (regenerate the bundle first, see check_labyrint.luau)
--
-- Both were dead in the live game. ShopClient and MinimapClient looked for `workspace.MazeGame`,
-- but the live builder `buildInstance` names its folder `Maze_<id>` — only the unused
-- `buildLevel` ever creates a `MazeGame`. So `recolorAll` returned on its first line every single
-- time and the minimap never found anything to draw. Seventeen wall themes at 500-2000 coins or
-- 25-75 gems, and an 800-coin minimap perk, took payment for nothing.
--
-- Renaming is not enough, and that is what this file is really for: with per-player instances
-- there are MANY `Maze_<id>` folders in the workspace at once, one per active player. A client
-- that grabbed the first would repaint, or draw a map of, somebody ELSE's maze.
--
-- An earlier version of this check was reviewed and found much weaker than it looked. Both holes
-- are now pinned by assertions rather than left to luck:
--   * The minimap half only asserted `mapFrame.Visible`, which ANY folder satisfies — a minimap
--     drawing the neighbour's maze passed it. It now compares what was drawn against both mazes.
--   * The shop half only discriminated because the neighbour happened to start first and take the
--     lower folder number. Swapping two lines silently disarmed it. That is asserted outright now.
-- The payloads are no longer invented either: the server's own sendShopData / sendPerkData output
-- is captured from the remote and replayed, so a change to either payload shape fails here
-- instead of passing against a fixture that drifted.

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

local THEME_ID = "lava"
local THEME_WALL = "210,80,28"   -- Themes.luau: the lava wall colour
local CLASSIC_WALL = "90,94,105" -- the server's own wall colour

-- Deliberately different levels: the curve grows the maze every 20 levels, so the two players get
-- different wall counts. That difference is what lets the minimap assertion answer "whose maze".
local MY_LEVEL, OTHER_LEVEL = 1, 61

local ME, OTHER = 4242, 5353
local store = h.services.DataStoreService:GetDataStore("LabyrintSpill_v1")
-- Seeded so the SERVER's own payload carries the theme and the perk. Nothing is faked client-side.
store:SetAsync("p_" .. ME, {
	accepted = 200, coins = 99999, gems = 999, level = 1, bestByLevel = {},
	owned = { classic = true, lava = true }, theme = THEME_ID, perks = { minimap = true },
})
store:SetAsync("p_" .. OTHER, {
	accepted = 200, coins = 99999, gems = 999, level = 1, bestByLevel = {},
	owned = { classic = true }, theme = "classic", perks = {},
})

assert(h:tryRun("server/MazeGame.server"))

local me = h:join("ThemeTester", ME)
h:advance(1)
h.Players:simulateSpawn(me, h.workspace)
h:advance(1)

local other = h.Players:simulateJoin("Neighbour", OTHER)
h:advance(0.5)
h.Players:simulateSpawn(other, h.workspace)
h:advance(0.5)

local startRun = h.ReplicatedStorage:WaitForChild("LobbyRemotes"):WaitForChild("StartRun")
-- ORDER MATTERS. The neighbour starts FIRST so they take the lower instance id; a client that
-- naively grabs the first `Maze_` folder then lands on them, which is the failure this file exists
-- to catch. Asserted below, so reordering these two lines fails loudly instead of silently
-- disarming the check.
startRun.OnServerEvent:Fire(other, OTHER_LEVEL)
h:advance(2)
startRun:FireServer(MY_LEVEL)
h:advance(2)

--=================================================================== the folders exist and differ

local myFolderName = me:GetAttribute("MazeFolder")
local otherFolderName = other:GetAttribute("MazeFolder")
print("  my folder    : " .. tostring(myFolderName))
print("  their folder : " .. tostring(otherFolderName))

truthy(type(myFolderName) == "string", "the server marked me with my own maze folder")
truthy(type(otherFolderName) == "string", "the server marked the other player too")
truthy(myFolderName ~= otherFolderName, "the two players are in DIFFERENT folders")

local function instanceNumber(name)
	return tonumber(string.match(tostring(name), "^Maze_(%d+)$")) or -1
end
truthy(instanceNumber(myFolderName) > instanceNumber(otherFolderName),
	"the neighbour holds the LOWER instance id, so a naive first-folder lookup would pick theirs")

local myFolder = h.workspace:FindFirstChild(myFolderName or "")
local otherFolder = h.workspace:FindFirstChild(otherFolderName or "")
truthy(myFolder ~= nil, "my folder is in the workspace")
truthy(otherFolder ~= nil, "their folder is in the workspace")
eq(h.workspace:FindFirstChild("MazeGame"), nil, "there is no folder called MazeGame in the live path")

local function partsNamed(folder, name)
	local out = {}
	local function walk(node)
		for _, c in node:GetChildren() do
			if c.Name == name then table.insert(out, c) end
			walk(c)
		end
	end
	if folder then walk(folder) end
	return out
end

local myWalls, theirWalls = partsNamed(myFolder, "Wall"), partsNamed(otherFolder, "Wall")
print(string.format("  my walls: %d   their walls: %d", #myWalls, #theirWalls))
truthy(#myWalls > 0, "my maze has walls")
truthy(#theirWalls > 0, "their maze has walls")
truthy(#myWalls ~= #theirWalls, "the two mazes differ in size, so 'which one' is answerable")

-- The start marker existed only in the dead builder, so the perk drew two of the three markers it
-- promises.
eq(#partsNamed(myFolder, "MazeSpawn"), 1, "the live builder creates a MazeSpawn for the minimap")

local startedClassic = true
for _, w in myWalls do
	if rgbOf(w.Color) ~= CLASSIC_WALL then startedClassic = false end
end
truthy(startedClassic, "every wall starts at the classic colour")

--=========================================================== the client paints MY maze, not theirs

assert(h:tryRun("client/ShopClient.client"))
h:advance(1)

local function lastPayloadFor(remote, player)
	local sent = remote:getSent()
	for i = #sent, 1, -1 do
		local rec = sent[i]
		if rec.player == player and rec.args and type(rec.args[1]) == "table" then
			return rec.args[1]
		end
	end
	return nil
end

local shopData = h.ReplicatedStorage:WaitForChild("ShopRemotes"):WaitForChild("ShopData")
local realShop = lastPayloadFor(shopData, me)
truthy(realShop ~= nil, "the server sent me a ShopData payload of its own")
if realShop ~= nil then
	eq(realShop.theme, THEME_ID, "the server's own payload carries my selected theme")
	shopData:FireClient(me, realShop)
end
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

eq(mineMissed, 0, "every wall in MY maze took the theme")
truthy(mineRepainted > 0, "the theme actually repainted something")
eq(theirsRepainted, 0, "no wall in the OTHER player's maze was touched")

--=================================================== the minimap draws MY maze, not the neighbour's

assert(h:tryRun("client/MinimapClient.client"))
h:advance(1)

local perkData = h.ReplicatedStorage:WaitForChild("PerkRemotes"):WaitForChild("PerkData")
local realPerks = lastPayloadFor(perkData, me)
truthy(realPerks ~= nil, "the server sent me a PerkData payload of its own")
if realPerks ~= nil then
	truthy(realPerks.perks ~= nil and realPerks.perks.minimap == true,
		"the server's own payload says I own the minimap perk")
	perkData:FireClient(me, realPerks)
end
h:advance(3) -- the minimap debounces its rebuild

local mapFrame = nil
local function findFrame(node)
	for _, c in node:GetChildren() do
		if c.Name == "Kart" then mapFrame = c; return end
		findFrame(c)
	end
end
local pg = me:FindFirstChild("PlayerGui")
if pg then findFrame(pg) end

-- A frame that cannot be found is a FAILURE, not a note. Scoring "I could not check" as a pass is
-- how two defects reached a live game earlier in this project.
if mapFrame == nil then
	failed += 1
	print("FAIL: the minimap frame 'Kart' was never created")
else
	truthy(mapFrame.Visible == true, "the minimap is visible once the perk is owned and a maze found")

	-- `Visible` alone was the old assertion, and ANY maze satisfies it — a minimap drawing the
	-- neighbour's passed. Count what was drawn and match it against the two candidates.
	local dots = 0
	local function countDots(node)
		for _, c in node:GetChildren() do
			if c.ClassName == "Frame" and c ~= mapFrame then dots += 1 end
			countDots(c)
		end
	end
	countDots(mapFrame)
	print(string.format("  map dots: %d   (my walls %d, their walls %d)", dots, #myWalls, #theirWalls))

	truthy(dots > 0, "the minimap drew something")
	truthy(math.abs(dots - #myWalls) < math.abs(dots - #theirWalls),
		"what the minimap drew matches MY maze, not the neighbour's")
end

--=========================================================================================== done

print("")
-- createInstance pcalls the build and downgrades a failure to warn(), which h:errors() does not
-- surface; without this a run where every instance failed to build would score green.
eq(#h.warnings, 0, "the instances built without warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("themes: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("theme check failed", 0)
end
