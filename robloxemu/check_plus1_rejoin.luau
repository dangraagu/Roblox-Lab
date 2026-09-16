-- +1 Jump Every Step — a returning climber must come back to their own platform.
-- Run: luau check_plus1_rejoin.luau   (regenerate the bundle first, see check_plus1.luau)
--
-- The game's whole promise is that the tower remembers you: "fall and you get put back on the
-- exact platform you last earned". It does not. onPlayerAdded places the character BEFORE it
-- builds the tower up to that player's frontier:
--
--     plr.CharacterAdded:Connect(function(char) onCharacter(plr, char) end)
--     if plr.Character then onCharacter(plr, plr.Character) end        -- places the character
--     if p.frontierTier + Config.Tower.StreamAhead > highestBuilt then -- builds the tower
--         for tt = highestBuilt + 1, p.frontierTier + StreamAhead do buildTier(tt) end
--     end
--
-- so `builtTiers[p.frontierTier]` is still nil inside onCharacter, the guard on line 383 falls
-- through, and the player is dropped on BASE_POS. Only tier 1 survives, because buildTier(1)
-- runs at startup. Everyone above tier 1 loses their climb on every rejoin.
--
-- WHAT THIS REPRODUCES, precisely. In a live server the character exists by the time
-- onPlayerAdded resumes, because loadProfile yields on DataStore:UpdateAsync. This harness runs
-- scripts on the main thread, so its DataStore cannot yield, and a plain join-then-spawn would
-- run onPlayerAdded to completion first and hide the bug. So the test uses the OTHER entry into
-- the same lines: `for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end` at the
-- bottom of the script, which is what runs for players already present when the server script
-- starts. Same function, same two lines, same fix. It is a narrower door into the defect than a
-- real rejoin, and worth knowing that.
--
-- AND HOW BAD IT ACTUALLY IS. Less bad than it looks, which is worth stating because the first
-- version of this file measured the wrong moment and passed. The fall-rescue loop notices the
-- player is below their frontier platform and teleports them up, so the climb is never lost.
-- Measured: y=12 (the pad) immediately after placement, still y=12 at 0.05s, y=1264.5 (their own
-- platform) by 0.55s. The player sees a jolt, not a loss. So this check asserts the position AT
-- PLACEMENT, before any frame runs - the rescue must not be what makes it right, or the test
-- passes while the defect stands.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/plus1-jump"),
	name = "plus1-jump",
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
local function near(a, b, tol, msg)
	if a ~= nil and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print(string.format("FAIL: %s -> got %s, want %s +/- %s", msg, tostring(a), tostring(b), tostring(tol)))
	end
end

-- Deliberately far above the six tiers the server streams ahead at boot, so "did it build the
-- tower before placing me" is an answerable question rather than a coincidence.
local ME, TIER, IDX = 777, 12, 3
local BASE_Y = 8 -- Main.server.luau: BASE_POS = Vector3.new(0, 8, 0)

local store = h.services.DataStoreService:GetDataStore("Plus1Jump_v1")
store:SetAsync("u_" .. ME, {
	data = {
		frontierTier = TIER, frontierIdx = IDX,
		jumpPower = 66, rebirths = 0, bestTier = TIER,
		redeemed = {}, passes = {},
	},
})

-- The player is present WITH a character before the server script runs. That is the state
-- onPlayerAdded's startup loop sees, and the state a real rejoin reaches by a different road.
local me = h.Players:simulateJoin("Returning", ME)
local char = h.Players:simulateSpawn(me, h.workspace)
local hrp = char:FindFirstChild("HumanoidRootPart")
truthy(hrp ~= nil, "the test character has a HumanoidRootPart to be moved")

assert(h:tryRun("server/Main.server"))

-- Read the position NOW, with no frame in between. Everything below judges this snapshot.
-- Calling h:advance() first would let the fall-rescue correct the placement and hand back a
-- green run over a live defect.
local landedX, landedY, landedZ
if hrp ~= nil then
	landedX, landedY, landedZ = hrp.Position.X, hrp.Position.Y, hrp.Position.Z
end

h:advance(1)

--======================================================= the tower was built up to my frontier

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

local myPlatform = findPart("P_" .. TIER .. "_" .. IDX)
truthy(myPlatform ~= nil,
	"tier " .. TIER .. " was built, so there is a platform to be placed on at all")

-- Without this the whole check could pass vacuously on a server that built nothing: a missing
-- platform and a player on the pad would agree with each other.
local tier1 = findPart("P_1_1")
truthy(tier1 ~= nil, "the base tier exists (the tower builder ran)")

--============================================================ and I was placed on MY platform

if landedY ~= nil then
	print(string.format("  my platform    : %s", myPlatform and tostring(myPlatform.Position) or "MISSING"))
	print(string.format("  placed at      : %.2f, %.2f, %.2f", landedX, landedY, landedZ))
	print(string.format("  one second on  : %s", tostring(hrp.Position)))
	print(string.format("  the pad is at y=%d", BASE_Y))

	if myPlatform ~= nil then
		near(landedY, myPlatform.Position.Y + 4, 0.5,
			"I was PLACED on my own platform, not rescued onto it afterwards")
		near(landedX, myPlatform.Position.X, 0.5, "and at its X")
		near(landedZ, myPlatform.Position.Z, 0.5, "and at its Z")
	end

	-- Stated separately and absolutely: whatever else is true, the pad is the wrong answer.
	truthy(landedY > BASE_Y + 20,
		"I was nowhere near the starting pad (tier " .. TIER .. " is far above y=" .. BASE_Y .. ")")
end

--=========================================================================================== done

print("")
eq(#h.warnings, 0, "the server started without warnings")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("plus1 rejoin: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plus1 rejoin check failed", 0)
end
