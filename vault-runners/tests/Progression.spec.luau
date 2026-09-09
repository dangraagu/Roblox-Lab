-- Progression — which vault you are allowed into, and how mean the floor is.
-- Run: luau tests/Progression.spec.luau
--
-- Pure: cfg in, plain tables out. The two things it must never get wrong:
--   1. a vault is unlocked by gems you have BANKED IN TOTAL, never by gems you currently hold —
--      otherwise buying a pet takes a vault away from you, which is the worst possible
--      punishment for engaging with the shop;
--   2. the per-floor seed has to stay a small, exactly reproducible integer, because "Bronze
--      floor 7" being the same maze for everyone is the only reason a time is comparable.

local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Progression")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want ~", tostring(b))
	end
end

local C = Config

--============================================================================ the three vaults

do
	eq(Progression.tierCount(C), 3, "v1 ships exactly three vaults")
	eq(Progression.tier(C, 1).id, "bronze", "tier 1 is the Bronze Vault")
	eq(Progression.tier(C, 2).id, "silver", "tier 2 is the Silver Vault")
	eq(Progression.tier(C, 3).id, "gold", "tier 3 is the Gold Vault")
	eq(Progression.tier(C, 4), nil, "and there is no fourth")
	eq(Progression.tier(C, 0), nil, "nor a zeroth")
end

--============================================================================ unlocking

do
	truthy(Progression.isUnlocked(C, 1, 0), "a brand-new player can enter the Bronze Vault")
	falsy(Progression.isUnlocked(C, 2, 0), "but not Silver")
	falsy(Progression.isUnlocked(C, 3, 0), "and not Gold")

	falsy(Progression.isUnlocked(C, 2, 1199), "one gem short of Silver is still short")
	truthy(Progression.isUnlocked(C, 2, 1200), "hitting the threshold EXACTLY unlocks it")
	truthy(Progression.isUnlocked(C, 2, 1201), "and past it")

	falsy(Progression.isUnlocked(C, 3, 5999), "one short of Gold")
	truthy(Progression.isUnlocked(C, 3, 6000), "exactly Gold")

	eq(Progression.unlockedCount(C, 0), 1, "0 banked -> one vault")
	eq(Progression.unlockedCount(C, 1200), 2, "1200 banked -> two")
	eq(Progression.unlockedCount(C, 6000), 3, "6000 banked -> all three")
	eq(Progression.unlockedCount(C, 10 ^ 9), 3, "and it never exceeds three")

	local last = 0
	local monotone = true
	for g = 0, 7000, 25 do
		local n = Progression.unlockedCount(C, g)
		if n < last then monotone = false end
		last = n
	end
	truthy(monotone, "banking more gems never takes a vault away")
end

do -- the rule that protects the shop: unlocks read TOTAL banked, not the wallet
	local profile = { gems = 5, totalBanked = 6000 }
	truthy(Progression.isUnlocked(C, 3, profile.totalBanked),
		"a player who spent their gems on pets keeps the Gold Vault")
end

do
	local nxt = Progression.nextUnlock(C, 0)
	eq(nxt.index, 2, "the next unlock from zero is Silver")
	eq(nxt.need, 1200, "which needs 1200 total")
	eq(nxt.remaining, 1200, "all of it still to go")

	nxt = Progression.nextUnlock(C, 900)
	eq(nxt.remaining, 300, "remaining counts down")

	nxt = Progression.nextUnlock(C, 1200)
	eq(nxt.index, 3, "at 1200 the next one is Gold")
	eq(nxt.remaining, 4800, "4800 to go")

	eq(Progression.nextUnlock(C, 6000), nil, "with everything unlocked there is no next")
end

--============================================================================ the floor curve

do
	local d = Progression.difficulty(C, 1, 1)
	eq(d.cells, 4, "Bronze floor 1 is a 4x4 maze")
	eq(d.storeys, 3, "three storeys")
	eq(d.gemsPerStorey, 4, "four gems a storey")
	eq(d.gemValue, 4, "worth four each")
	eq(d.gemCount, 12, "twelve gems on the floor in total")
	near(d.slack, C.Collapse.Slack, 1e-9, "and the runner is owed the full slack on floor 1")
	eq(d.collapseSeconds, nil, "difficulty does NOT decide the countdown — it cannot, the maze "
		.. "does not exist yet. VaultPath.countdown measures the built vault.")
end

do -- growth, capped
	eq(Progression.difficulty(C, 1, 6).cells, 4, "floor 6 is still 4 cells")
	eq(Progression.difficulty(C, 1, 7).cells, 5, "floor 7 grows to 5")
	eq(Progression.difficulty(C, 1, 13).cells, 6, "floor 13 to 6")
	eq(Progression.difficulty(C, 1, 500).cells, C.Curve.MaxCells, "and it caps at MaxCells")
	eq(Progression.difficulty(C, 3, 500).cells, C.Curve.MaxCells, "Gold caps at the same wall")

	eq(Progression.difficulty(C, 1, 10).storeys, 3, "storeys hold to floor 10")
	eq(Progression.difficulty(C, 1, 11).storeys, 4, "and step up on 11")
	eq(Progression.difficulty(C, 1, 900).storeys, C.Curve.MaxStoreys, "capped at MaxStoreys")

	eq(Progression.difficulty(C, 1, 5).gemsPerStorey, 4, "gems hold to floor 5")
	eq(Progression.difficulty(C, 1, 6).gemsPerStorey, 5, "and step up on 6")
	eq(Progression.difficulty(C, 1, 900).gemsPerStorey, C.Curve.MaxGemsPerStorey, "capped")
end

do -- the SLACK tightens, and that is the whole difficulty curve now
	-- This block used to assert seconds: "floor 2 sheds 1.5s", "floor 11 sheds 15s". Those
	-- assertions were all true and the game was still unwinnable from Silver floor 1 onwards,
	-- because a countdown decided here cannot know how big the maze it is timing is. What the
	-- curve controls now is how much room over the BFS-optimal route the runner is owed;
	-- tests/Collapse.spec.luau is what checks the resulting run is survivable.
	near(Progression.difficulty(C, 1, 2).slack, C.Collapse.Slack - C.Collapse.TightenPerFloor,
		1e-9, "floor 2 sheds one step of slack")
	near(Progression.difficulty(C, 1, 11).slack, C.Collapse.Slack - 10 * C.Collapse.TightenPerFloor,
		1e-9, "floor 11 has shed ten")
	near(Progression.difficulty(C, 1, 900).slack, C.Collapse.MinSlack, 1e-9,
		"and it bottoms out at MinSlack rather than running to zero")

	local prev = math.huge
	local shrinking = true
	for f = 1, 200 do
		local s = Progression.difficulty(C, 1, f).slack
		if s > prev + 1e-9 then shrinking = false end
		prev = s
	end
	truthy(shrinking, "the slack never grows as you go deeper")

	local minSeen = math.huge
	for t = 1, 3 do
		for f = 1, 300 do
			minSeen = math.min(minSeen, Progression.difficulty(C, t, f).slack)
		end
	end
	truthy(minSeen > 1, "no floor is ever given LESS time than the optimal route takes")
end

do -- a floor below 1 is a bug upstream; it must not produce a bigger maze than floor 1
	eq(Progression.difficulty(C, 1, 0).cells, 4, "floor 0 is treated as floor 1")
	eq(Progression.difficulty(C, 1, -5).cells, 4, "and so is a negative floor")
	near(Progression.difficulty(C, 1, 0).slack, C.Collapse.Slack, 1e-9, "with floor 1's slack")
end

do -- an out-of-range tier is a programming error and must be loud, not silently Bronze
	local ok = pcall(function() return Progression.difficulty(C, 9, 1) end)
	falsy(ok, "difficulty on a tier that does not exist raises")
end

--============================================================================ the seed

do
	eq(Progression.seedFor(C, 1, 7), Progression.seedFor(C, 1, 7),
		"the same tier and floor give the same seed, always")
	truthy(Progression.seedFor(C, 1, 7) ~= Progression.seedFor(C, 1, 8),
		"a different floor is a different vault")
	truthy(Progression.seedFor(C, 1, 7) ~= Progression.seedFor(C, 2, 7),
		"a different tier is a different vault")

	-- Overflow is the silent killer here: past 2^53 the low bits are gone and whole runs of
	-- floors start generating the identical maze.
	local biggest = Progression.seedFor(C, 3, 100000)
	truthy(biggest < 2 ^ 53, "even floor 100000 of Gold stays inside exact integer range")
	eq(biggest, math.floor(biggest), "and the seed is an integer")

	local seen, distinct = {}, 0
	for f = 1, 400 do
		local s = Progression.seedFor(C, 1, f)
		if not seen[s] then seen[s] = true; distinct += 1 end
	end
	eq(distinct, 400, "400 consecutive floors produce 400 distinct seeds")
end

--============================================================================ CONTROL

-- A change the suite must NOT notice: the cosmetic fields on a tier. Colours and the emoji on
-- the portal are art direction, and nothing about which vault is open or how hard it is may
-- depend on them. If this fails, some rule above has started reading the paint.
do
	local painted = {
		Tiers = {}, Curve = C.Curve, Collapse = C.Collapse, Seed = C.Seed, WorldSeed = C.WorldSeed,
	}
	for i, t in ipairs(C.Tiers) do
		local copy = {}
		for k, v in pairs(t) do copy[k] = v end
		copy.wallColor = { r = 255, g = 0, b = 255 }
		copy.floorColor = { r = 0, g = 255, b = 0 }
		copy.gemColor = { r = 0, g = 0, b = 0 }
		copy.emoji = "🟪"
		copy.name = "Repainted Vault " .. i
		painted.Tiers[i] = copy
	end

	eq(Progression.unlockedCount(painted, 1200), Progression.unlockedCount(C, 1200),
		"CONTROL: repainting the vaults does not change what is unlocked")
	eq(Progression.difficulty(painted, 2, 9).cells, Progression.difficulty(C, 2, 9).cells,
		"CONTROL: nor the maze size")
	near(Progression.difficulty(painted, 2, 9).slack,
		Progression.difficulty(C, 2, 9).slack, 1e-9,
		"CONTROL: nor how much slack the runner is owed")
	eq(Progression.seedFor(painted, 2, 9), Progression.seedFor(C, 2, 9),
		"CONTROL: nor the seed")
end

print(string.format("Progression: %d passed, %d failed", passed, failed))
if failed > 0 then error("Progression tests failed", 0) end
