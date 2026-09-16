-- Labyrinth Mariozo — where the ENGINE puts a character, at every moment this game has one.
-- Run: luau check_labyrint_spawn.luau   (regenerate the bundle first, see check_labyrint.luau)
--
-- WHY THIS FILE EXISTS. `Player.CharacterAdded` fires while the character model is still
-- UNPARENTED with its root at the world origin; one frame later the engine parents it AND
-- places it on the enabled SpawnLocation, silently discarding any CFrame the game wrote in
-- between (measured in Studio, written up in fork-tower/STUDIO.md and robloxemu/SPAWN-ORDER.md).
-- Fork Tower shipped a spawn 174 studs off because of it. Deep Vein has the same shape.
--
-- Labyrinth does NOT write a CFrame inside CharacterAdded, so it is right — but until this file
-- existed, "right" was not a measurement. No check in this repo spawned a labyrint character at
-- all: the game's four headless checks boot the server and inspect the WORLD, never a player.
-- Green therefore meant "nobody looked". Measured, with the maze start marker turned into a real
-- SpawnLocation (the exact regression buildInstance's own comment warns against), all twelve of
-- this game's suites stayed green: check_labyrint PASS, lighting 19/0, secretdoors 50/0,
-- themes 23/0, and 347 unit assertions across tests/. This file is the thing that looks.
--
-- WHAT IT PINS, and why each one rather than a position alone:
--
--   1. The world offers the engine exactly ONE answer. Labyrinth never sets
--      Player.RespawnLocation, so the engine falls to rule 2 — pick among the enabled
--      SpawnLocations in the Workspace. There is exactly one, the lobby pad, and every maze
--      instance deliberately marks its start with a plain Part instead ("Vanlig Part, ikke
--      SpawnLocation ... en ekte SpawnLocation ville blandet seg inn i hvor Roblox respawner
--      folk", buildInstance). That comment is load-bearing and nothing enforced it.
--      This is a STRUCTURAL assertion on purpose: the emulator resolves a tie by tree order,
--      while Roblox picks at RANDOM among the eligible spawns (SPAWN-ORDER.md §7). So a second
--      enabled spawn does not reliably move the measured position here — it would move it in
--      the live game, for a random half of deaths, into a stranger's maze 6000 studs away.
--      Counting the spawns is the only honest way to catch that from a headless run.
--
--   2. Where the character ACTUALLY ends up, read after the engine's step, at each of the three
--      moments this game has: the first spawn, entering a run, and dying inside a run.
--
--   3. That the game's own state agrees with the position — a player standing in the lobby must
--      not still be attributed to a maze, and vice versa. A position that is right while the HUD
--      says otherwise is the fork-tower failure with extra steps.
--
--   4. That nothing moves the character afterwards. plus1-jump survives its naive spawn only
--      because a fall-rescue loop yanks the climber back within 0.4 s; that is a mask, not a fix,
--      and a check that reads the position a second later cannot tell the two apart. Every
--      placement here is read immediately AND one second on, and both must agree.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/labyrint-spill"),
	name = "labyrint-spill",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1
		print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end
local function between(v, lo, hi, msg)
	if type(v) == "number" and v >= lo and v <= hi then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s..%s", msg, tostring(v), tostring(lo), tostring(hi)))
	end
end

--=================================================================================== world tools

local function walk(node, fn)
	for _, c in node:GetChildren() do
		fn(c)
		walk(c, fn)
	end
end

local function allSpawns()
	local out = {}
	walk(h.workspace, function(c) if c:IsA("SpawnLocation") then table.insert(out, c) end end)
	return out
end

local function topFace(part) return part.Position.Y + part.Size.Y / 2 end

-- Is this part one of a character's / monster's own limbs? Those are collidable and would
-- otherwise answer "what is the ground under me" with the asker's own root part.
local function isBodyPart(c)
	local n = c.Parent
	while n ~= nil and n ~= h.workspace do
		if n:IsA("Model") and n:FindFirstChildOfClass("Humanoid") ~= nil then return true end
		n = n.Parent
	end
	return false
end

-- The highest collidable top face under (x, z) that is at or below `y`: what the character is
-- standing on. Axis-aligned boxes, same approximation the emulator's own ground scan makes.
-- `ignore` drops one part from the scan, which is how "is the pad itself standing on anything"
-- gets asked without the pad answering it.
local function groundUnder(x, y, z, ignore)
	local best, who = nil, nil
	walk(h.workspace, function(c)
		if c == ignore then return end
		if not c:IsA("BasePart") or c.CanCollide == false or isBodyPart(c) then return end
		local p, s = c.Position, c.Size
		if math.abs(p.X - x) <= s.X / 2 and math.abs(p.Z - z) <= s.Z / 2 then
			local top = p.Y + s.Y / 2
			if top <= y + 0.001 and (best == nil or top > best) then best, who = top, c end
		end
	end)
	return best, who
end

local function rootOf(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function fmt(hrp)
	if hrp == nil then return "nil" end
	local p = hrp.Position
	return string.format("%.2f, %.2f, %.2f", p.X, p.Y, p.Z)
end
local function snapshot(hrp)
	local p = hrp.Position
	return { X = p.X, Y = p.Y, Z = p.Z }
end
local function samePlace(a, hrp)
	local p = hrp.Position
	return math.abs(a.X - p.X) < 0.01 and math.abs(a.Y - p.Y) < 0.01 and math.abs(a.Z - p.Z) < 0.01
end

--============================================================================= boot: the lobby

print("== the world the engine gets to choose from ==")
local ok, err = h:tryRun("server/MazeGame.server")
truthy(ok, "the server script runs: " .. tostring(err))

local spawns = allSpawns()
for _, s in spawns do
	print(string.format("  %-38s pos=%-16s size=%-10s enabled=%s",
		s:GetFullName(), tostring(s.Position), tostring(s.Size), tostring(s.Enabled)))
end

eq(#spawns, 1, "the lobby world contains exactly one SpawnLocation")
local pad = spawns[1]
if pad ~= nil then
	eq(pad.Name, "LobbySpawn", "and it is the lobby pad")
	eq(pad.Parent and pad.Parent.Name, "Lobby", "parented under the Lobby folder")
	-- Enabled is what makes the engine USE it. Disabled, Roblox falls back to dropping the
	-- character over the highest ground at the world origin — the sealed-shell roof trap that
	-- has bitten this repo twice. The lobby sits at the origin today, which is the only reason
	-- that fallback would be survivable here; it is not a thing to rely on.
	truthy(pad.Enabled ~= false, "the lobby pad is ENABLED, so the engine actually spawns people on it")

	-- The pad is where the engine will put everybody, so the pad had better be part of the
	-- lobby rather than an 8x8 island next to it. Ask what is under the pad with the pad itself
	-- excluded — a SpawnLocation is collidable and would otherwise answer its own question. The
	-- same shape as deep-vein's "the spawn point has ground under it".
	local under, underPart = groundUnder(pad.Position.X, pad.Position.Y - pad.Size.Y / 2 + 0.001, pad.Position.Z, pad)
	print(string.format("  under the pad    : %s (%s)", tostring(under), underPart and underPart:GetFullName() or "NOTHING"))
	truthy(underPart ~= nil, "the pad itself is standing on lobby floor, not floating beside it")
end

--=============================================================== the first spawn: the lobby pad

print("")
print("== a player joins and the engine places them ==")
local me = h:join("Kari", 4242)
local char = h.Players:simulateSpawn(me, h.workspace)
local hrp = rootOf(char)
truthy(hrp ~= nil, "the character has a HumanoidRootPart")

if hrp ~= nil and pad ~= nil then
	local placed = snapshot(hrp)
	print("  placed at        : " .. fmt(hrp))
	print(string.format("  the pad          : %s  (top face y=%.2f)", tostring(pad.Position), topFace(pad)))

	near(placed.X, pad.Position.X, pad.Size.X / 2, "placed within the pad's footprint (X)")
	near(placed.Z, pad.Position.Z, pad.Size.Z / 2, "placed within the pad's footprint (Z)")
	-- "above the pad", not a centimetre-exact Y: the 2.51 stand-off is fitted from ONE Studio
	-- sample and SPAWN-ORDER.md says not to pin it (§7).
	between(placed.Y - topFace(pad), 0, 4, "standing ON the pad, not under it and not in the sky")

	local g, gpart = groundUnder(placed.X, placed.Y, placed.Z)
	print(string.format("  ground under them: %s (%s)", tostring(g), gpart and gpart:GetFullName() or "NOTHING"))
	truthy(gpart ~= nil, "there is collidable ground under the spawn — they are not over a hole")
	truthy(gpart ~= nil and gpart:IsDescendantOf(h.workspace:FindFirstChild("Lobby")),
		"and that ground belongs to the Lobby, not to some maze 6000 studs away")

	h:advance(1)
	print("  one second later : " .. fmt(hrp))
	truthy(samePlace(placed, hrp),
		"nothing moved them afterwards — the placement is right, not rescued")
end

eq(me:GetAttribute("MazeFolder"), nil, "a player in the lobby is not attributed to any maze")

--============================================================== entering a run: their own maze

print("")
print("== the player picks Solo, level 1 ==")
local startRun = h.services.ReplicatedStorage:FindFirstChild("LobbyRemotes")
startRun = startRun and startRun:FindFirstChild("StartRun")
truthy(startRun ~= nil, "the StartRun remote exists")

if startRun ~= nil and hrp ~= nil then
	startRun:simulateFireServer(me, 1, "solo")
	local placed = snapshot(hrp)
	local folderName = me:GetAttribute("MazeFolder")
	print("  MazeFolder attr  : " .. tostring(folderName))
	print("  placed at        : " .. fmt(hrp))

	truthy(typeof(folderName) == "string", "the player is attributed to a maze folder")
	local folder = typeof(folderName) == "string" and h.workspace:FindFirstChild(folderName) or nil
	truthy(folder ~= nil, "and that folder is in the Workspace")

	-- The maze's start marker. It must exist (so the assertion below is not vacuous) and it must
	-- NOT be a SpawnLocation — a second enabled spawn is what would scatter dead players into
	-- other people's mazes.
	local marker = folder and folder:FindFirstChild("MazeSpawn")
	truthy(marker ~= nil, "their maze has a start marker")
	truthy(marker ~= nil and not marker:IsA("SpawnLocation"),
		"the maze start marker is a plain Part, NOT a SpawnLocation")
	eq(#allSpawns(), 1, "building a maze added no SpawnLocation — the engine still has one answer")

	if marker ~= nil then
		print(string.format("  start marker     : %s (top face y=%.2f)", tostring(marker.Position), topFace(marker)))
		near(placed.X, marker.Position.X, marker.Size.X / 2, "placed on their own maze's start cell (X)")
		near(placed.Z, marker.Position.Z, marker.Size.Z / 2, "placed on their own maze's start cell (Z)")
		between(placed.Y - topFace(marker), 0, 6, "placed above the start marker, not below the floor")
	end

	local g, gpart = groundUnder(placed.X, placed.Y, placed.Z)
	print(string.format("  ground under them: %s (%s)", tostring(g), gpart and gpart:GetFullName() or "NOTHING"))
	truthy(gpart ~= nil and folder ~= nil and gpart:IsDescendantOf(folder),
		"the ground under them belongs to THEIR OWN maze")

	h:advance(1)
	print("  one second later : " .. fmt(hrp))
	truthy(samePlace(placed, hrp), "and nothing moved them out of it")
end

--============================================================ dying in the maze: back to the pad

print("")
print("== the player dies in the maze; the engine respawns them ==")
local mazeBefore = me:GetAttribute("MazeFolder")
local char2 = h.Players:simulateSpawn(me, h.workspace)
local hrp2 = rootOf(char2)
truthy(hrp2 ~= nil, "the respawned character has a HumanoidRootPart")

if hrp2 ~= nil and pad ~= nil then
	local placed = snapshot(hrp2)
	print("  respawned at     : " .. fmt(hrp2))
	near(placed.X, pad.Position.X, pad.Size.X / 2, "the engine put them back on the lobby pad (X)")
	near(placed.Z, pad.Position.Z, pad.Size.Z / 2, "the engine put them back on the lobby pad (Z)")
	between(placed.Y - topFace(pad), 0, 4, "standing on the pad")

	h:advance(1)
	print("  one second later : " .. fmt(hrp2))
	truthy(samePlace(placed, hrp2), "and stayed there")
end

-- The game's state has to follow the body. handleLobbySpawn is the only thing that does this,
-- and it runs from CharacterAdded — the same handler the engine's order made unsafe for CFrames.
-- It is safe for STATE, and this is the assertion that says so out loud.
print("  MazeFolder attr  : " .. tostring(me:GetAttribute("MazeFolder")) .. "  (was " .. tostring(mazeBefore) .. ")")
truthy(mazeBefore ~= nil, "they really were in a maze before dying (the check above was not vacuous)")
eq(me:GetAttribute("MazeFolder"), nil, "dying in a maze takes the player OUT of it")
if typeof(mazeBefore) == "string" then
	eq(h.workspace:FindFirstChild(mazeBefore), nil, "and the empty solo maze was torn down")
end

--=========================================================================================== done

print("")
eq(#h.warnings, 0, "the server produced no warnings")
for _, w in h.warnings do print("  warn: " .. tostring(w)) end
for _, e in h:errors() do
	print("  scheduler error: " .. e)
	failed += 1
end
print(string.format("labyrint spawn: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("labyrint spawn check failed", 0)
end
