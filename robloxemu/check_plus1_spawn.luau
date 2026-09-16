-- +1 Jump Every Step — the character must survive the ENGINE'S spawn order.
-- Run: luau check_plus1_spawn.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../plus1-jump --out build/plus1-jump.luau
--
-- WHY THIS FILE EXISTS, and why check_plus1_rejoin.luau does not cover it.
--
-- Measured in Roblox Studio on 2026-09-10 (fork-tower/STUDIO.md): Player.CharacterAdded fires
-- while the character Model is still UNPARENTED with its HumanoidRootPart at the world origin,
-- and ONE FRAME LATER the engine parents the model AND places it on a spawn — silently throwing
-- away any CFrame the game wrote in between. robloxemu now models that order.
--
-- check_plus1_rejoin.luau calls simulateSpawn BEFORE running the server, so the placement it
-- measures comes from onPlayerAdded's direct `if plr.Character then onCharacter(...) end` call,
-- where the character is already parented. The racing path — a player who joins a server that is
-- ALREADY RUNNING, which is every real join — was exercised by no check in this repo. This file
-- joins after `h:tryRun`, so every placement below goes through CharacterAdded.
--
-- Three things it pins, all of which were measurably broken before:
--   1. a returning climber's placement survives the engine step (it was discarded: the tier-12
--      climber stood on the base pad at 0.00, 10.51, 0.00 — 1352.17 studs from their platform);
--   2. the fall-rescue loop actually STARTS. `while char.Parent and hum.Health > 0` is evaluated
--      the instant task.spawn runs it, and inside CharacterAdded char.Parent is nil, so the loop
--      exited before its first iteration and no character spawned in a live server ever had a
--      rescue at all. SPAWN-ORDER.md called this loop the mask that made plus1-jump's naive
--      placement survivable; measured, the mask does not exist;
--   3. there is a real enabled SpawnLocation and plr.RespawnLocation points at it, so the
--      engine's placement is a decision instead of a lottery. With no SpawnLocation the engine
--      drops the character above the HIGHEST collidable ground over the world origin, and
--      TowerGen puts a tier-1 platform there for 410 of 5000 sampled WorldSeeds (8.2%) — the
--      shipped seed 20260905 is not one of them, so this was correct by luck. Landing on
--      platform 2 is not cosmetic: isBeyondFrontier is monotonic, so P_1_1's +1 would be
--      unearnable for the life of the save.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if a ~= nil and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

local h = Harness.new({
	bundle = require("./build/plus1-jump"),
	name = "plus1-jump",
	viewport = { 1280, 720 },
	touch = false,
})

local function findPart(name)
	local found = nil
	local function walk(node)
		for _, c in node:GetChildren() do
			if c.Name == name then found = c; return end
			walk(c)
			if found then return end
		end
	end
	walk(h.workspace)
	return found
end

local function findFirstOfClass(className)
	local found = nil
	local function walk(node)
		for _, c in node:GetChildren() do
			if c.ClassName == className then found = c; return end
			walk(c)
			if found then return end
		end
	end
	walk(h.workspace)
	return found
end

local function p3(hrp)
	if hrp == nil then return "nil" end
	return string.format("%.2f, %.2f, %.2f", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
end

-- Far above the six tiers the server streams at boot, so "was the tower built before I was
-- placed" stays an answerable question rather than a coincidence.
local TIER, IDX = 12, 3

local store = h.services.DataStoreService:GetDataStore("Plus1Jump_v1")
store:SetAsync("u_777", {
	data = { frontierTier = TIER, frontierIdx = IDX, jumpPower = 66, rebirths = 0,
		bestTier = TIER, redeemed = {}, passes = {} },
})

-- The server is ALREADY RUNNING before anybody joins. That single ordering is the whole point of
-- this file: every character below is created by simulateSpawn firing CharacterAdded at a live
-- server, which is the path a real player takes and the path the engine races.
assert(h:tryRun("server/Main.server"))

local basePad = findPart("BasePad")
truthy(basePad ~= nil, "the base pad exists (the world builder ran)")
truthy(findPart("P_1_1") ~= nil, "the base tier exists (the tower builder ran)")
local padTop = basePad and (basePad.Position.Y + basePad.Size.Y / 2) or 8

--=================================================== 3. the engine is aimed, not left to guess

local spawn = findFirstOfClass("SpawnLocation")
truthy(spawn ~= nil,
	"the game builds a real SpawnLocation, so the engine does not fall back to 'highest ground "
		.. "over the world origin' (8.2% of WorldSeeds put a tower platform there)")
if spawn ~= nil then
	eq(spawn.Enabled, true, "and it is enabled, so the engine will actually use it")
	near(spawn.Position.X, 0, 0.5, "and it stands over the base pad in X")
	near(spawn.Position.Z, 0, 0.5, "and in Z")
	near(spawn.Position.Y + spawn.Size.Y / 2, padTop, 1.0,
		"and its top face is the pad's top face, so nobody spawns inside the pad or above it")
end

--============================================================= 1a. a FRESH player, joining live

local fresh = h.Players:simulateJoin("Fresh", 4242)
local freshChar = h.Players:simulateSpawn(fresh, h.workspace)
local freshHrp = freshChar:FindFirstChild("HumanoidRootPart")
truthy(freshHrp ~= nil, "the fresh character has a HumanoidRootPart")

-- Stated WITHOUT an `if spawn ~= nil` guard on purpose. Every assertion above is conditional on
-- the SpawnLocation existing, so deleting it turns five of them into no-ops rather than failures,
-- and a check that never looks cannot fail. These three always run and always look.
local rl = fresh.RespawnLocation
truthy(rl ~= nil, "a joining player has a RespawnLocation at all")
eq(rl and rl.ClassName or "nil", "SpawnLocation",
	"and it is a real SpawnLocation, which is the only thing the engine will honour")
eq(rl and rl.Enabled or false, true, "and that spawn is enabled")

if freshHrp ~= nil then
	print("  fresh player    : " .. p3(freshHrp) .. "   (pad top y=" .. tostring(padTop) .. ")")
	near(freshHrp.Position.Y, padTop + 4, 0.6,
		"a fresh player stands on the base pad where the GAME put them, not where the engine "
			.. "guessed")
	near(freshHrp.Position.X, 0, 0.6, "and over the pad in X")
	near(freshHrp.Position.Z, 0, 0.6, "and in Z")
end

--=========================================================== 1b. a RETURNING climber, joining live

local me = h.Players:simulateJoin("Returning", 777)
local char = h.Players:simulateSpawn(me, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
truthy(hrp ~= nil, "the returning character has a HumanoidRootPart")

-- Read with no h:advance() in between. simulateSpawn already runs the engine step and one frame,
-- so a handler that correctly waits for char.Parent has finished; anything that lands later is
-- the fall-rescue covering for a bad placement, and that would turn this check green over a live
-- defect exactly the way SPAWN-ORDER.md warns.
local landedX, landedY, landedZ
if hrp ~= nil then
	landedX, landedY, landedZ = hrp.Position.X, hrp.Position.Y, hrp.Position.Z
end

local myPlatform = findPart("P_" .. TIER .. "_" .. IDX)
truthy(myPlatform ~= nil, "tier " .. TIER .. " was built, so there is a platform to be placed on")

if myPlatform ~= nil and landedY ~= nil then
	print(string.format("  my platform     : %s", tostring(myPlatform.Position)))
	print(string.format("  placed at       : %.2f, %.2f, %.2f", landedX, landedY, landedZ))
	near(landedY, myPlatform.Position.Y + 4, 0.5,
		"a returning climber is PLACED on their own platform, and the engine does not take it back")
	near(landedX, myPlatform.Position.X, 0.5, "and at its X")
	near(landedZ, myPlatform.Position.Z, 0.5, "and at its Z")
	truthy(landedY > padTop + 20,
		"and is nowhere near the starting pad (tier " .. TIER .. " is far above y=" .. tostring(padTop) .. ")")
end

--============================================================ 2. the fall-rescue is alive at all

-- Shove the climber into the void. The loop in onCharacter is supposed to notice and put them
-- back on their frontier platform within ~0.4 s. Before this fix the loop had already exited
-- before its first iteration, because char.Parent was nil when task.spawn evaluated its
-- condition, so the shoved player simply stayed in the void forever.
if hrp ~= nil and myPlatform ~= nil then
	hrp.CFrame = CFrame.new(0, -5000, 0)
	h:advance(3)
	print("  after the shove : " .. p3(hrp))
	near(hrp.Position.Y, myPlatform.Position.Y + 4, 0.5,
		"a climber who falls into the void is rescued back onto their platform (the loop RAN)")
	near(hrp.Position.X, myPlatform.Position.X, 0.5, "and back to its X")
	near(hrp.Position.Z, myPlatform.Position.Z, 0.5, "and to its Z")
end

-- And the fresh player has one too, on the pad.
if freshHrp ~= nil then
	freshHrp.CFrame = CFrame.new(0, -5000, 0)
	h:advance(3)
	near(freshHrp.Position.Y, padTop + 4, 0.6,
		"a fresh player who falls into the void is rescued back onto the pad")
end

--=========================================================================================== done

print("")
eq(#h.warnings, 0, "the server started without warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1 spawn order: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1 spawn-order check failed", 0)
end
