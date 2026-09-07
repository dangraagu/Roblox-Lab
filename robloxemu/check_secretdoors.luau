-- Labyrinth Mariozo — every secret door must have a button that opens it.
-- Run: luau check_secretdoors.luau   (regenerate the bundle first, see check_labyrint.luau)
--
-- A player reported this and I did not believe it was possible until I counted:
--     "It was a dead end as far as I could tell. There were 2 doors but only for one of
--      them there was a switch."
--
-- A SecretWall is drawn in a different colour from a normal wall, so a player can see it and
-- goes looking for its button. If no button exists, they hunt an opening that cannot be opened
-- and conclude the level is a dead end. The door never blocks the real route — the maze is
-- perfect and a secret door only ever sits on a wall BETWEEN two open cells, so it is a
-- shortcut, not the path. That makes this a cruelty bug rather than an unwinnable one, which is
-- exactly why it survived: nothing fails, the player just wastes their run.
--
-- The counts come from two different expressions in buildInstance, and nothing tied them:
--     doors   = math.min(diff.buttons, #doorCandidates)
--     buttons = take(math.min(diff.buttons, 4))     -- hard cap of 4, and `take` silently
--                                                   -- returns fewer when the cell pool is dry
-- diff.buttons is 3 + floor(level / 170), so from level 340 the cap alone guarantees an
-- orphaned door on every single maze, forever.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/labyrint-spill"),
	name = "labyrint-spill",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

-- Levels chosen to straddle every step in `3 + floor(level / 170)`.
local LEVELS = { 1, 5, 50, 169, 170, 200, 339, 340, 400, 511 }

local USER_ID = 4242

-- Seed the profile BEFORE the server loads: startSolo clamps the requested level to
-- accepted + 1, so without this every run would be level 1 and the interesting range would
-- never be built.
local store = h.services.DataStoreService:GetDataStore("LabyrintSpill_v1")
store:SetAsync("p_" .. USER_ID, {
	accepted = 600,
	coins = 0,
	gems = 0,
	level = 1,
	bestByLevel = {},
})

assert(h:tryRun("server/MazeGame.server"))

local plr = h:join("DoorTester", USER_ID)
h:advance(1)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(1)

local lobby = h.ReplicatedStorage:WaitForChild("LobbyRemotes")
local startRun = lobby:WaitForChild("StartRun")

-- Count every SecretWall and SecretButton anywhere in the workspace. Exactly one instance is
-- alive at a time, so a plain descendant sweep is unambiguous.
local function countParts()
	local doors, buttons, marks = 0, 0, 0
	local function walk(node)
		for _, child in node:GetChildren() do
			local n = child.Name
			if n == "SecretWall" then
				doors += 1
			elseif n == "SecretButton" then
				buttons += 1
			elseif n == "SecretMark" then
				marks += 1
			end
			walk(child)
		end
	end
	walk(h.workspace)
	return doors, buttons, marks
end

print("  level   doors  buttons  marks")
for _, level in LEVELS do
	-- Leaving an instance tears it down, so each level starts from a clean workspace.
	char = h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)

	startRun:FireServer(level)
	h:advance(2)

	local doors, buttons, marks = countParts()
	print(string.format("  %5d   %5d  %7d  %5d", level, doors, buttons, marks))
	eq(doors, buttons, string.format("level %d: every secret door has a button", level))
	-- The mark is what tells the player WHICH button opens this door; a door without one is
	-- back to the original complaint even though the button exists somewhere.
	eq(marks, doors, string.format("level %d: every secret door carries its pair mark", level))

	-- Equality alone is a vacuous pass: 0 == 0 == 0 satisfies it, so deleting the feature
	-- outright, or a buildInstance that raises, both scored green. Pin the absolute count.
	-- diff.buttons is 3 + floor(level / 170), capped at 4 by the button loop.
	local expected = math.min(3 + math.floor(level / 170), 4)
	eq(doors, expected, string.format("level %d: %d doors actually exist", level, expected))

	-- createInstance pcalls the build and downgrades a failure to warn(), which the harness
	-- collects but h:errors() does not report — so a level that failed to build was scored as a
	-- pass, and so was a game where every level failed.
	eq(#h.warnings, 0, string.format("level %d: the instance built without warnings", level))

	-- And the pair has to actually work. Counting parts says nothing about whether pressing a
	-- button opens anything, which is the behaviour the player actually complained about.
	local buttonList, wallYBefore = {}, {}
	local function collect(node)
		for _, c in node:GetChildren() do
			if c.Name == "SecretButton" then
				table.insert(buttonList, c)
			elseif c.Name == "SecretWall" then
				wallYBefore[c] = c.Position.Y
			end
			collect(c)
		end
	end
	collect(h.workspace)

	if #buttonList == 0 then
		failed += 1
		print("FAIL: level " .. level .. ": no button to press")
	else
		local hrp = char:FindFirstChild("HumanoidRootPart")
		buttonList[1].Touched:Fire(hrp)
		h:advance(1.5)
		local droppedCount = 0
		for wall, y0 in wallYBefore do
			if wall.Position.Y < y0 - 1 then
				droppedCount += 1
			end
		end
		eq(droppedCount, 1, string.format("level %d: pressing one button opens exactly one door", level))
	end
end

print("")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("secretdoors: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("secret-door check failed", 0)
end
