-- Rene logikk-tester for Progression. Kjør med luau CLI:  luau tests/Progression.spec.luau
-- (Ingen Roblox-API brukt. Roblox har ingen headless-runtime her, så disse
--  kjøres på en dev-boks / CI med luau; koden er verifisert mot casene ved review.)

local Progression = require("../src/shared/Progression")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

-- seedAccepted: lengste sammenhengende rekke fra 1
eq(Progression.seedAccepted({}), 0, "empty -> 0")
eq(Progression.seedAccepted({ ["1"] = 5, ["2"] = 6, ["3"] = 7 }), 3, "1..3 contiguous -> 3")
eq(Progression.seedAccepted({ ["1"] = 5, ["3"] = 7 }), 1, "gap at 2 -> 1")
eq(Progression.seedAccepted({ ["2"] = 6 }), 0, "no level 1 -> 0")

-- resolveClear: ren fullføring av neste nivå
local r = Progression.resolveClear({ level = 51, accepted = 50, bestWithGod = 50, hadGod = false })
eq(r.acceptedGained, true, "clean next -> gained")
eq(r.newAccepted, 51, "accepted -> 51")
eq(r.leaderboardEligible, true, "clean -> leaderboard eligible")
eq(r.recordEligible, true, "clean -> record eligible")

-- resolveClear: carry (nivå langt over accepted+1) -> ingen accepted
local c = Progression.resolveClear({ level = 200, accepted = 50, bestWithGod = 50, hadGod = false })
eq(c.acceptedGained, false, "carry -> no gain")
eq(c.newAccepted, 50, "carry -> accepted unchanged")
eq(c.newBestWithGod, 200, "carry -> bestWithGod tracks reached")

-- resolveClear: gud aktiv -> ingenting teller (men bestWithGod oppdateres)
local g = Progression.resolveClear({ level = 51, accepted = 50, bestWithGod = 50, hadGod = true })
eq(g.acceptedGained, false, "god -> no accepted")
eq(g.leaderboardEligible, false, "god -> not leaderboard eligible")
eq(g.recordEligible, false, "god -> no record")
eq(g.newBestWithGod, 51, "god -> bestWithGod still updates")

-- resolveClear: replay av allerede-eid nivå (level <= accepted) -> ingen ny accepted
local rp = Progression.resolveClear({ level = 40, accepted = 50, bestWithGod = 50, hadGod = false })
eq(rp.acceptedGained, false, "replay -> no gain")
eq(rp.newAccepted, 50, "replay -> accepted unchanged")
eq(rp.recordEligible, true, "replay -> record still eligible (better time)")

--============  RUTE-GUIDEN ("Hjelp meg", se Assist)  =============--
-- Kjernen: guiden viser veien, den HOPPER IKKE over noe. Derfor mister kjøringen
-- retten til tid/rekord, men accepted teller — spilleren gikk faktisk ut selv.

eq(Progression.recordEligible(false, false), true, "clean run -> record eligible")
eq(Progression.recordEligible(true, false), false, "god -> no record")
eq(Progression.recordEligible(false, true), false, "guide -> no record")
eq(Progression.recordEligible(true, true), false, "god + guide -> no record")
eq(Progression.recordEligible(nil, nil), true, "nil-safe -> eligible")

-- guide på nøyaktig accepted+1: accepted teller, rekorden gjør ikke
local a = Progression.resolveClear({ level = 7, accepted = 6, bestWithGod = 6,
	hadGod = false, usedAssist = true })
eq(a.acceptedGained, true, "guide -> accepted STILL gained (you walked it)")
eq(a.newAccepted, 7, "guide -> accepted 7")
eq(a.recordEligible, false, "guide -> record NOT eligible (board cannot be bought)")
eq(a.leaderboardEligible, true, "guide -> still on the progression board")

-- guiden kan ikke brukes til å hoppe: carry er fortsatt carry
local ac = Progression.resolveClear({ level = 200, accepted = 6, bestWithGod = 6,
	hadGod = false, usedAssist = true })
eq(ac.acceptedGained, false, "guide + carry -> still no gain")
eq(ac.newAccepted, 6, "guide cannot inflate accepted")

-- guiden vasker ikke bort gudemodus
local ag = Progression.resolveClear({ level = 7, accepted = 6, bestWithGod = 6,
	hadGod = true, usedAssist = true })
eq(ag.acceptedGained, false, "god still zeroes accepted even with a guide")
eq(ag.recordEligible, false, "god + guide -> no record")

-- uten flagget oppfører alt seg nøyaktig som før (bakover-kompatibelt)
local an = Progression.resolveClear({ level = 7, accepted = 6, bestWithGod = 6, hadGod = false })
eq(an.acceptedGained, true, "no usedAssist field -> unchanged behaviour")
eq(an.recordEligible, true, "no usedAssist field -> record eligible")

--============================================================ gå-vakta (the walk guard, 2026-10-01)
-- docs/complete-game-standard.md §3: the board ranks on a metric "a script cannot inflate". `accepted` rises when the
-- server sees you at the exit, and movement is the client's, so a teleport script could touch every exit at once.
-- The server now refuses an exit reached faster than anyone can walk there: Progression.minClearSeconds(steps,
-- cellSize, maxSpeed, slack), where `steps` is the shortest route from start to exit in the fine grid with every
-- secret door open. A runner who cuts every corner on the diagonal still covers at least steps * cellSize / sqrt(2)
-- studs (the staircase through the corners is the shortest a 4-connected route can be); one cell comes off each end.
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
truthy(type(Progression.minClearSeconds) == "function", "Progression.minClearSeconds exists")
if type(Progression.minClearSeconds) == "function" then
	local mc = Progression.minClearSeconds
	local near = function(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end
	truthy(near(mc(20, 9, 19, 1), (20 * 9 / math.sqrt(2) - 2 * 9) / 19), "20 steps, 9-stud cells, 19 studs/s: (20*9/sqrt2 - 18) / 19")
	truthy(near(mc(20, 9, 19, 0.85), 0.85 * (20 * 9 / math.sqrt(2) - 2 * 9) / 19), "the slack multiplies")
	eq(mc(2, 9, 19, 1), 0, "a route shorter than its two end cells: no floor (never negative)")
	eq(mc(0, 9, 19, 1), 0, "zero steps: 0")
	truthy(mc(40, 9, 16, 1) > mc(40, 9, 19, 1), "a faster top speed lowers the floor")
	truthy(mc(80, 9, 19, 1) > mc(40, 9, 19, 1), "a longer route raises it")

	-- On the game's OWN mazes (MazeGen at the live curve, tests/MazeWalker): the floor never refuses a real walk, and it
	-- still bites. `steps` here ignores secret doors; the server opens them, which only lowers its floor further.
	local MazeGen = require("../src/shared/MazeGen")
	local Medals = require("../src/shared/Medals")
	local W = require("./MazeWalker")
	local S, WALK, TOP, SLACK = 9, 16, 19, 0.85 -- CONFIG.CellSize, PlayerWalkSpeed, + the speed perk's 3; the server's slack
	local worstRatio, worstFast, minFloor1 = 0, math.huge, math.huge
	local levels = {}
	for L = 1, 60 do table.insert(levels, L) end
	for L = 80, 500, 20 do table.insert(levels, L) end
	for _, L in levels do
		for seed = 1, 3 do
			local lv = W.level(MazeGen, W.CURVE, L, 900 + seed * 37)
			local steps = Medals.solveRoute(lv.grid, lv.gCols, lv.gRows, { 1, 1 }, { lv.gCols - 2, lv.gRows - 2 }, {})
			local floor = mc(steps, S, TOP, SLACK)
			-- the fastest honest run: the shortest route at top speed, corners cut on the diagonal wherever it turns
			local perfect = steps * S / math.sqrt(2) / TOP
			worstRatio = math.max(worstRatio, floor / perfect)
			-- the model's fast player (no deaths), who walks at the normal 16 studs/s
			local fast = W.explore(lv, W.rng(L * 17 + seed), W.PROFILES.fast).duration
			worstFast = math.min(worstFast, fast / math.max(floor, 1e-9))
			if L == 1 then minFloor1 = math.min(minFloor1, floor) end
			-- it bites: a script must wait at least a fifth of par (par = steps * S / 16) on every level
			if floor < 0.2 * steps * S / WALK then
				failed += 1
				print(string.format("FAIL: L%d seed %d: floor %.1f s is under a fifth of par %.1f s", L, seed, floor, steps * S / WALK))
			end
		end
	end
	print(string.format("  walk guard: floor / perfect diagonal run <= %.3f; the fast model walks >= %.1fx the floor; L1 floor >= %.1f s",
		worstRatio, worstFast, minFloor1))
	truthy(worstRatio < 1, string.format("the floor stays under the perfect corner-cutting run at top speed on every sampled maze (worst %.3f)", worstRatio))
	truthy(worstFast > 1.5, string.format("the model's fast player needs more than 1.5x the floor everywhere (worst %.1fx)", worstFast))
	truthy(minFloor1 >= 3, string.format("even level 1 makes a teleport wait (%.1f s)", minFloor1))
end

print(string.format("Progression: %d passed, %d failed", passed, failed))
assert(failed == 0, "Progression tests failed")
