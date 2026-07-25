-- Rene logikk-tester for Progression. Kjør med luau CLI:  luau tests/Progression.spec.luau
-- (Ingen Roblox-API brukt. Roblox har ingen headless-runtime her, så disse
--  kjøres på en dev-boks / CI med luau; koden er verifisert mot casene ved review.)

local Progression = require("../src/shared/Progression.luau")

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

print(string.format("Progression: %d passed, %d failed", passed, failed))
assert(failed == 0, "Progression tests failed")
