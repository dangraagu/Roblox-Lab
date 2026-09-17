-- Pure tests for Offers: the three Sighting pedestals. Run: luau tests/Offers.spec.luau
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Offers = require("../src/shared/Offers")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local TIER = { jackalope = 1, hodag = 1, chupacabra = 1, dogman = 2, jerseydevil = 2, mothman = 3, nessie = 3, bigfoot = 4 }

--============================================================================ the tier rule, every rank

-- P1 Common; P2 max(1, rank); P3 min(4, rank + 1). Written out by hand for ranks 0-4.
local WANT = {
	[0] = { 1, 1, 1 },
	[1] = { 1, 1, 2 },
	[2] = { 1, 2, 3 },
	[3] = { 1, 3, 4 },
	[4] = { 1, 4, 4 },
}
for rank = 0, 4 do
	for slot = 1, 3 do
		eq(Offers.tierFor(Config, slot, rank), WANT[rank][slot], string.format("rank %d pedestal %d tier", rank, slot))
	end
end

do
	local rng = Rng.new(99)
	local bad = 0
	for rank = 0, 4 do
		for _ = 1, 200 do
			local o = Offers.initial(Config, rng, rank, 1)
			for slot = 1, 3 do
				if TIER[o[slot]] ~= WANT[rank][slot] then bad += 1 end
			end
		end
	end
	eq(bad, 0, "1 000 offer sets per the tier rule, every species on its pedestal's tier")
end

--============================================================================ the tutorial Jackalope

do
	local rng = Rng.new(5)
	local notJack = 0
	for _ = 1, 1000 do
		if Offers.draw(Config, rng, 1, 0, 0) ~= "jackalope" then notJack += 1 end
	end
	eq(notJack, 0, "while the tutorial step is 0, P1 is always a Jackalope")
	eq(Offers.initial(Config, rng, 0, 0)[1], "jackalope", "a new player's first P1 is the Jackalope")

	local counts = { jackalope = 0, hodag = 0, chupacabra = 0 }
	for _ = 1, 3000 do
		local sp = Offers.draw(Config, rng, 1, 1, 1)
		counts[sp] += 1
	end
	for id, n in counts do
		truthy(n > 850 and n < 1150, string.format("after the tutorial P1 draws %s uniformly (%d of 3000)", id, n))
	end
end

--============================================================================ re-roll

do
	eq((Offers.canReroll(Config, nil, 1000)), true, "never re-rolled: allowed")
	local ok, left = Offers.canReroll(Config, 1000, 1029.5)
	eq(ok, false, "29.5 s after a re-roll: refused")
	eq(left, 1, "...with 1 s left, rounded up")
	eq((Offers.canReroll(Config, 1000, 1030)), true, "30 s later: allowed")

	local rng = Rng.new(11)
	local o = Offers.initial(Config, rng, 0, 0)
	local changedP1 = 0
	for _ = 1, 50 do
		o = Offers.reroll(Config, rng, o, 0, 0)
		if o[1] ~= "jackalope" then changedP1 += 1 end
	end
	eq(changedP1, 0, "re-rolling never takes the tutorial Jackalope off P1")

	local seenP2 = {}
	o = Offers.initial(Config, rng, 3, 2)
	for _ = 1, 60 do
		o = Offers.reroll(Config, rng, o, 3, 2)
		seenP2[o[2]] = true
	end
	truthy(seenP2.mothman and seenP2.nessie, "re-rolling a rank-3 P2 shows both Legendaries")
end

--============================================================================ rank changes

do
	local rng = Rng.new(3)
	local o = Offers.initial(Config, rng, 1, 1)
	local same = Offers.onRankChange(Config, rng, o, 1, 1, 1)
	eq(same[1], o[1], "no rank change: P1 unchanged")
	eq(same[2], o[2], "no rank change: P2 unchanged")
	eq(same[3], o[3], "no rank change: P3 unchanged")
	local up = Offers.onRankChange(Config, rng, o, 1, 2, 1)
	eq(up[1], o[1], "a rank-up keeps P1")
	eq(TIER[up[2]], 2, "a rank-up redraws P2 at the new rank")
	eq(TIER[up[3]], 3, "...and P3 one tier up, at once")
	-- an empty pedestal (mid-delivery) stays empty rather than being refilled early
	local mid = { "", o[2], o[3] }
	eq(Offers.onRankChange(Config, rng, mid, 1, 2, 1)[1], "", "an empty P1 is not refilled by a rank change")
end

--============================================================================ seeds

do
	local s = Offers.seed(Config, 2147483646, 9007199254740)
	truthy(s % 1 == 0 and s >= 0 and s < 2147483647, "the offer seed is an integer in range for a huge userId")
	truthy(Offers.seed(Config, 5, 100) ~= Offers.seed(Config, 6, 100), "the session salt changes the stream")
end

print(string.format("Offers: %d passed, %d failed", passed, failed))
if failed > 0 then error("Offers tests failed") end
