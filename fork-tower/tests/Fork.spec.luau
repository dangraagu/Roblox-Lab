-- Fork.spec.luau — the fairness spec for Fork Tower.
-- Run: luau tests/Fork.spec.luau
--
-- Fork Tower IS this module. Everything else — the doors, the obby sections, the reveal card —
-- is presentation on top of one pure question: given a seed and a floor, which of the two doors
-- is the trap? So the two promises the game makes to a player belong here, asserted, not assumed:
--
--   FAIRNESS 1 — NO FLOOR IS UNWINNABLE.
--       Both doors always hand you their trait. The trap costs you a longer, busier climb; it
--       never takes progress away and never closes a route. Whichever door you walk through,
--       the floor is finishable.
--
--   FAIRNESS 2 — NO RUN IS A COIN FLIP ALL THE WAY DOWN.
--       Every fork is READABLE. The inscription on the fork platform names one sign, exactly one
--       door carries that sign, and the inscription says outright whether it marks the trap or
--       the safe door. A player who reads it clears every floor of every seed with zero traps.
--       A player who flips a coin eats one half the time. That gap is the game.
--
-- Everything below exists to keep those two true, plus the structural invariants that stop a
-- second, unintended tell from leaking in — because the moment sign COUNT, or trait POWER, or
-- door POSITION predicts the trap, the inscription becomes decoration and the fork becomes a
-- lookup. Each of those is checked against a deliberately broken twin at the bottom of the file,
-- so a check that has quietly stopped biting fails here rather than shipping.

local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Fork = require("../src/shared/Fork")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b), "+/-", tostring(tol))
	end
end

local FLOORS = Config.Tower.Floors
local SWEEP = 4000 -- runs; x FLOORS floors = 40 000 forks measured below

-- Every plan in the sweep, built once. Four thousand runs of ten floors is 40 000 forks, which is
-- enough for a 0.03 tolerance on a 50/50 split to mean something (a fair coin's standard error
-- here is 0.0025, so a real bias of 3 points is ~12 sigma and a fair generator practically never
-- trips it).
local plans = {}
for s = 1, SWEEP do
	plans[s] = Fork.plan(Config, s, Rng)
end

local function eachFloor(fn)
	for s = 1, SWEEP do
		for _, floor in ipairs(plans[s].floors) do
			fn(floor, s)
		end
	end
end

--============================================================================ determinism

do
	local a = Fork.plan(Config, 12345, Rng)
	local b = Fork.plan(Config, 12345, Rng)
	local same = true
	for l = 1, FLOORS do
		local x, y = a.floors[l], b.floors[l]
		if x.trapDoor ~= y.trapDoor or x.markedDoor ~= y.markedDoor
			or x.tellKind ~= y.tellKind or x.ruleInverted ~= y.ruleInverted
			or x.doors[1].traitId ~= y.doors[1].traitId
			or x.doors[2].traitId ~= y.doors[2].traitId then
			same = false
		end
	end
	truthy(same, "the same runSeed rebuilds a byte-identical plan")

	-- A leaderboard time only means something if the tower is the same tower for everyone, and a
	-- rebirth is only worth doing if it is a DIFFERENT tower. Both halves are load-bearing.
	local differs = 0
	for s = 1, 200 do
		local p, q = Fork.plan(Config, s, Rng), Fork.plan(Config, s + 1, Rng)
		for l = 1, FLOORS do
			if p.floors[l].trapDoor ~= q.floors[l].trapDoor
				or p.floors[l].doors[1].traitId ~= q.floors[l].doors[1].traitId then
				differs += 1
				break
			end
		end
	end
	eq(differs, 200, "every neighbouring runSeed produces a different run (rebirth rerolls)")

	-- Fork.floor is just plan().floors[level]; if the two ever disagree, the server and the
	-- tests are looking at different games.
	local plan = Fork.plan(Config, 777, Rng)
	local agree = true
	for l = 1, FLOORS do
		local one = Fork.floor(Config, 777, l, Rng)
		if one.trapDoor ~= plan.floors[l].trapDoor or one.tellKind ~= plan.floors[l].tellKind then
			agree = false
		end
	end
	truthy(agree, "Fork.floor agrees with Fork.plan on every floor")

	-- The WorldSeed has to reach the fork. Change it and the whole tower must move.
	local other = {}
	for k, v in pairs(Config) do other[k] = v end
	other.WorldSeed = Config.WorldSeed + 1
	local moved = false
	for l = 1, FLOORS do
		if Fork.floor(other, 777, l, Rng).trapDoor ~= plan.floors[l].trapDoor then moved = true end
	end
	truthy(moved, "changing WorldSeed changes the trap layout")
end

--============================================================================ structure

do
	local badDoors, badSlot, sameTrait, sameTheme, badSignCount, badTrait = 0, 0, 0, 0, 0, 0
	local byId = {}
	for _, t in ipairs(Config.Traits) do byId[t.id] = t end

	eachFloor(function(floor)
		if #floor.doors ~= 2 then badDoors += 1 end
		if floor.trapDoor ~= 1 and floor.trapDoor ~= 2 then badSlot += 1 end
		local d1, d2 = floor.doors[1], floor.doors[2]
		if d1.slot ~= 1 or d2.slot ~= 2 then badSlot += 1 end
		if d1.traitId == d2.traitId then sameTrait += 1 end
		if d1.theme == d2.theme then sameTheme += 1 end
		for _, d in ipairs(floor.doors) do
			if #d.signs ~= Config.Fork.SignsPerDoor then badSignCount += 1 end
			if byId[d.traitId] == nil then badTrait += 1 end
		end
	end)

	eq(badDoors, 0, "every floor offers exactly two doors")
	eq(badSlot, 0, "the trap is always slot 1 or 2, and the doors are slotted 1 and 2")
	eq(sameTrait, 0, "the two doors never offer the same trait")
	eq(sameTheme, 0, "the two doors never offer the same theme (the sections must look different)")
	eq(badTrait, 0, "every offered trait exists in Config.Traits")

	-- Sign COUNT must carry nothing. If the trap door showed the tell PLUS its decoys while the
	-- safe door showed fewer, "take the door with fewer marks" would beat the inscription and the
	-- whole reading mechanic would be dead weight.
	eq(badSignCount, 0, "both doors always show exactly SignsPerDoor signs")
end

do
	-- Dead content is a defect: a trait nobody can ever be offered is a trait that was never
	-- built. Twelve traits over 20 000 forks should all appear many times over.
	local seen = {}
	eachFloor(function(floor)
		for _, d in ipairs(floor.doors) do seen[d.traitId] = (seen[d.traitId] or 0) + 1 end
	end)
	local missing = {}
	for _, t in ipairs(Config.Traits) do
		if (seen[t.id] or 0) == 0 then missing[#missing + 1] = t.id end
	end
	eq(#missing, 0, "every trait in the pool is reachable (missing: " .. table.concat(missing, ",") .. ")")
end

--============================================================================ FAIRNESS 1

do
	-- The trap door still hands you its trait. It is a toll, not a wall.
	local blocked, bothTrap, neitherTrap = 0, 0, 0
	eachFloor(function(floor)
		local t1 = Fork.isTrap(floor, 1)
		local t2 = Fork.isTrap(floor, 2)
		if t1 and t2 then bothTrap += 1 end
		if not t1 and not t2 then neitherTrap += 1 end
		for _, d in ipairs(floor.doors) do
			if d.traitId == nil or d.traitId == "" then blocked += 1 end
		end
	end)
	eq(blocked, 0, "FAIRNESS 1: both doors always grant a trait, the trapped one included")
	eq(bothTrap, 0, "FAIRNESS 1: a floor never traps both doors")
	eq(neitherTrap, 0, "FAIRNESS 1: exactly one door is the trap, so a floor is never a free pass")
end

--============================================================================ FAIRNESS 2

do
	-- A player who reads the inscription. Not "usually right" — right on all 20 000.
	local readerTrapped = 0
	-- A player who has learned the sign vocabulary but ignores the "the warden lies" line.
	local naiveTrapped, inverted = 0, 0
	-- A player who always takes the left door.
	local blindTrapped = 0

	eachFloor(function(floor)
		if Fork.readTrap(floor) ~= floor.trapDoor then readerTrapped += 1 end
		if floor.markedDoor ~= floor.trapDoor then naiveTrapped += 1 end
		if floor.ruleInverted then inverted += 1 end
		if floor.trapDoor == 1 then blindTrapped += 1 end
	end)

	local total = SWEEP * FLOORS
	eq(readerTrapped, 0,
		"FAIRNESS 2: a player who reads the inscription hits ZERO traps across every seed and floor")

	-- And the reading has to be worth doing. If the tell were decoration, the blind player would
	-- score the same as the reader; this is the assertion that says it does not.
	near(blindTrapped / total, 0.5, Config.Fairness.SideBalanceTolerance,
		"FAIRNESS 2: always taking the left door is a coin flip, so the tell carries real information")

	-- The liar line is the troll half. It must be exactly as common as configured — and it must
	-- be the ONLY thing that separates the naive reader from the careful one.
	eq(naiveTrapped, inverted,
		"a reader who ignores the liar line is wrong exactly on the inverted floors, never elsewhere")
	truthy(inverted > 0, "the inscription does sometimes lie (otherwise the mechanic is dead)")
end

do
	-- The liar gate: the early floors teach the vocabulary before the tower starts lying.
	local earlyLies, lateFloors, lateLies = 0, 0, 0
	eachFloor(function(floor)
		if floor.level < Config.Fork.LiarFromFloor then
			if floor.ruleInverted then earlyLies += 1 end
		else
			lateFloors += 1
			if floor.ruleInverted then lateLies += 1 end
		end
	end)
	eq(earlyLies, 0, "the inscription never lies before floor " .. Config.Fork.LiarFromFloor)
	near(lateLies / lateFloors, Config.Fork.LiarChance, 0.02,
		"and lies at the configured rate afterwards")
end

--============================================================================ no second tell

do
	-- Position. Measured over the whole sweep AND per floor number: a generator that balanced
	-- overall while always trapping the left door on floor 7 would pass the first and fail the
	-- second, and floor 7 is exactly the kind of thing a player datamines.
	local leftTotal = 0
	local leftPerLevel = table.create(FLOORS, 0)
	eachFloor(function(floor)
		if floor.trapDoor == 1 then
			leftTotal += 1
			leftPerLevel[floor.level] += 1
		end
	end)
	near(leftTotal / (SWEEP * FLOORS), 0.5, Config.Fairness.SideBalanceTolerance,
		"the trap is on the left half the time, overall")
	local worst, worstLevel = 0, 0
	for l = 1, FLOORS do
		local share = leftPerLevel[l] / SWEEP
		if math.abs(share - 0.5) > worst then
			worst = math.abs(share - 0.5)
			worstLevel = l
		end
	end
	truthy(worst <= Config.Fairness.SideBalanceTolerance,
		string.format("...and on every individual floor (worst: floor %d, off by %.4f)", worstLevel, worst))
end

local function signConfig(floor)
	-- What a player SEES before reading the inscription: the two doors' sign sets, in order.
	-- Deliberately NOT canonicalised — left and right are different places on the screen.
	return table.concat(floor.doors[1].signs, "+") .. "|" .. table.concat(floor.doors[2].signs, "+")
end

do
	-- The signs alone must say nothing. This is the whole load-bearing claim of the design: the
	-- inscription is the only thing that resolves a fork, so for EVERY arrangement of signs a
	-- player can see, the trap has to be on the left exactly half the time.
	--
	-- An earlier version of this check asked a narrower question — "restricted to floors where a
	-- non-tell sign shows on exactly one door, is that door the trap half the time?" — and it was
	-- measuring a tautology dressed as an invariant. Four signs, two per door: 80% of forks have
	-- the doors sharing one sign and holding one each, so the marked door's lone sign IS the
	-- tell and the other door's lone sign is, by simple complement, on the other door. The check
	-- would have reported a correct generator as catastrophically unfair (0.00 instead of 0.50)
	-- and forced a real design to be broken to satisfy it. Asking about the whole visible
	-- configuration instead asks the question a player actually faces.
	local seen, left = {}, {}
	eachFloor(function(floor)
		local key = signConfig(floor)
		seen[key] = (seen[key] or 0) + 1
		left[key] = (left[key] or 0) + (if floor.trapDoor == 1 then 1 else 0)
	end)

	local configs, thin, worst, worstKey = 0, 0, 0, ""
	for key, n in pairs(seen) do
		configs += 1
		if n < 200 then
			thin += 1
		else
			local off = math.abs(left[key] / n - 0.5)
			if off > worst then worst = off; worstKey = key end
		end
	end
	truthy(configs >= 12, "the doors show a real variety of sign arrangements (" .. configs .. ")")
	eq(thin, 0, "every arrangement occurs often enough to measure")
	truthy(worst <= Config.Fairness.SignBalanceTolerance,
		string.format("NO SECOND TELL: no arrangement of signs predicts the trap (worst: %s, off by %.4f)",
			worstKey, worst))

	-- The same thing said one sign at a time, which is how a player would actually stumble on it:
	-- "the cracked door is usually the bad one".
	local worstKind, worstKindOff = "", 0
	for _, kind in ipairs(Config.Fork.Signs) do
		local onTrap, onSafe = 0, 0
		eachFloor(function(floor)
			if floor.doors[floor.trapDoor].signSet[kind] then onTrap += 1 end
			if floor.doors[3 - floor.trapDoor].signSet[kind] then onSafe += 1 end
		end)
		local total = onTrap + onSafe
		local off = math.abs(onTrap / math.max(total, 1) - 0.5)
		if off > worstKindOff then worstKindOff = off; worstKind = kind end
	end
	truthy(worstKindOff <= Config.Fairness.SignBalanceTolerance,
		string.format("no single sign is commoner on the trap door (worst: %s, off by %.4f)",
			worstKind, worstKindOff))
end

do
	-- Trait power. If the trap door reliably held the better trait, "always take the boring one"
	-- would be the optimal strategy and the game would be solved without ever looking at a sign.
	local power = {}
	for _, t in ipairs(Config.Traits) do power[t.id] = t.power end
	local trapSum, safeSum, n = 0, 0, 0
	eachFloor(function(floor)
		trapSum += power[floor.doors[floor.trapDoor].traitId]
		safeSum += power[floor.doors[3 - floor.trapDoor].traitId]
		n += 1
	end)
	near(trapSum / n, safeSum / n, Config.Fairness.PowerBalanceTolerance,
		string.format("the trap door is no better and no worse a prize than the safe one (%.3f vs %.3f)",
			trapSum / n, safeSum / n))
end

--============================================================================ no tell across floors

do
	-- The subtlest way to leak the answer is not on a floor, it is BETWEEN floors. The first
	-- draft of this module seeded a fresh LCG per floor as `WorldSeed*a + level*b` and took the
	-- first value. Consecutive seeds differ by a constant, so an LCG's first output moves by a
	-- constant too: the trap side and the tell marched in a short repeating cycle, identical for
	-- every player. Both the balance check and the run-length check above passed happily — the
	-- shares were 50/50 and the streaks were SHORT, because a cycle is regular, not streaky.
	-- Nothing but the transition table sees it, and a player who noticed the cycle would never
	-- have to read another inscription.
	--
	-- The claim asserted here is: knowing floor L tells you nothing about floor L+1.
	local sideCount = { { 0, 0 }, { 0, 0 } }
	local sidePairs = 0
	local signIndex = {}
	for i, k in ipairs(Config.Fork.Signs) do signIndex[k] = i end
	local nSigns = #Config.Fork.Signs
	local tellCount = {}
	for a = 1, nSigns do
		tellCount[a] = table.create(nSigns, 0)
	end
	local tellPairs = 0

	for s = 1, SWEEP do
		local floors = plans[s].floors
		for l = 2, FLOORS do
			sideCount[floors[l - 1].trapDoor][floors[l].trapDoor] += 1
			sidePairs += 1
			tellCount[signIndex[floors[l - 1].tellKind]][signIndex[floors[l].tellKind]] += 1
			tellPairs += 1
		end
	end

	local worstSide = 0
	for a = 1, 2 do
		local rowTotal = sideCount[a][1] + sideCount[a][2]
		for b = 1, 2 do
			worstSide = math.max(worstSide, math.abs(sideCount[a][b] / rowTotal - 0.5))
		end
	end
	truthy(worstSide <= Config.Fairness.SerialTolerance,
		string.format("the previous floor's trap side does not predict the next one (worst cell off by %.4f)",
			worstSide))

	local worstTell = 0
	for a = 1, nSigns do
		for b = 1, nSigns do
			worstTell = math.max(worstTell, math.abs(tellCount[a][b] / tellPairs - 1 / (nSigns * nSigns)))
		end
	end
	truthy(worstTell <= Config.Fairness.SignBalanceTolerance / 2,
		string.format("the previous floor's tell does not predict the next one (worst cell off by %.4f)",
			worstTell))
end

--============================================================================ run shape

do
	-- The order-3 version of the same question, and the one that killed a feature.
	--
	-- The first draft capped identical trap sides at three in a row, on the theory that long
	-- streaks make a fair generator feel rigged. But an anti-streak cap IS a tell: after three
	-- left-traps the fourth floor is guaranteed to be on the right, free, without reading a
	-- single sign. That is a free floor in every eight for a player who counts — in a game whose
	-- entire promise is that the inscription is the only thing that resolves a fork. The cap is
	-- gone and this table is what would notice it coming back: with the cap, P(next = left |
	-- left, left, left) is 0.00 instead of 0.50.
	--
	-- Eight histories, ~1750 samples each; a fair coin's standard error on the conditional is
	-- about 0.012, so the 0.05 tolerance is four sigma.
	local hist, histNext = {}, {}
	for s = 1, SWEEP do
		local floors = plans[s].floors
		for l = 4, FLOORS do
			local key = floors[l - 3].trapDoor .. floors[l - 2].trapDoor .. floors[l - 1].trapDoor
			hist[key] = (hist[key] or 0) + 1
			histNext[key] = (histNext[key] or 0) + (if floors[l].trapDoor == 1 then 1 else 0)
		end
	end
	local seenHistories, thin, worst, worstKey = 0, 0, 0, ""
	for key, n in pairs(hist) do
		seenHistories += 1
		if n < 300 then
			thin += 1
		else
			local off = math.abs(histNext[key] / n - 0.5)
			if off > worst then worst = off; worstKey = key end
		end
	end
	eq(seenHistories, 8, "all eight three-floor histories occur")
	eq(thin, 0, "each of them occurs often enough to measure")
	truthy(worst <= Config.Fairness.SerialTolerance,
		string.format("no three-floor history predicts the next floor (worst: %s, off by %.4f)",
			worstKey, worst))

	-- And the streaks that do occur are a fair coin's streaks, not a sticky generator's. Measured
	-- against the exact distribution of the longest run in ten fair tosses, which is arithmetic,
	-- not another random sample: P(longest run <= k) counts binary strings with no run longer
	-- than k, and the count obeys c(n) = sum of c(n-1..n-k) with the usual seeds.
	local function pAtMost(k, n)
		-- number of binary strings of length n whose longest run is <= k, over 2^n
		local c = {}
		c[0] = 1
		for i = 1, n do
			local total = 0
			for j = 1, math.min(k, i) do
				total += c[i - j] or 0
			end
			c[i] = total
		end
		-- c[n] counts compositions of n into parts <= k; each composition maps to 2 strings
		-- (the first run is either side), except the empty case.
		return (2 * c[n]) / (2 ^ n)
	end

	local longest = {}
	for s = 1, SWEEP do
		local floors = plans[s].floors
		local run, best = 1, 1
		for l = 2, FLOORS do
			if floors[l].trapDoor == floors[l - 1].trapDoor then run += 1 else run = 1 end
			if run > best then best = run end
		end
		longest[#longest + 1] = best
	end
	local worstK, worstOff = 0, 0
	for k = 1, 6 do
		local hits = 0
		for _, v in ipairs(longest) do
			if v <= k then hits += 1 end
		end
		local off = math.abs(hits / SWEEP - pAtMost(k, FLOORS))
		if off > worstOff then worstOff = off; worstK = k end
	end
	truthy(worstOff <= 0.03,
		string.format("the streak lengths are a fair coin's (worst at k=%d, off by %.4f)", worstK, worstOff))
end

--============================================================================ witnesses
-- Each check above is re-run against a generator broken in exactly the way that check exists to
-- catch. A green suite that stays green against these is a suite that has stopped working.

local function sideBalanceOff(gen)
	local left, n = 0, 0
	for s = 1, 400 do
		for l = 1, FLOORS do
			local f = gen(s, l)
			if f.trapDoor == 1 then left += 1 end
			n += 1
		end
	end
	return math.abs(left / n - 0.5)
end

local function readerMisses(gen)
	local miss = 0
	for s = 1, 400 do
		for l = 1, FLOORS do
			local f = gen(s, l)
			if Fork.readTrap(f) ~= f.trapDoor then miss += 1 end
		end
	end
	return miss
end

local function powerGap(gen)
	local power = {}
	for _, t in ipairs(Config.Traits) do power[t.id] = t.power end
	local trapSum, safeSum, n = 0, 0, 0
	for s = 1, 400 do
		for l = 1, FLOORS do
			local f = gen(s, l)
			trapSum += power[f.doors[f.trapDoor].traitId]
			safeSum += power[f.doors[3 - f.trapDoor].traitId]
			n += 1
		end
	end
	return math.abs(trapSum / n - safeSum / n)
end

local real = function(s, l) return Fork.floor(Config, s, l, Rng) end

-- WITNESS A — a generator that always traps the left door. The reader check cannot see it (the
-- mark moves with the trap, so reading still works); only the position check can.
local biased = function(s, l)
	local f = Fork.floor(Config, s, l, Rng)
	f.trapDoor = 1
	f.markedDoor = if f.ruleInverted then 2 else 1
	return f
end
truthy(sideBalanceOff(real) <= Config.Fairness.SideBalanceTolerance, "witness A: the real fork is balanced")
truthy(sideBalanceOff(biased) > Config.Fairness.SideBalanceTolerance,
	"witness A: the position check KILLS a generator that always traps the left door")
eq(readerMisses(biased), 0, "witness A: ...and that generator is still perfectly readable, which is why one check is not enough")

-- WITNESS B — a generator whose mark is drawn independently of the trap. The signs still look
-- right, the counts still balance, and the inscription is now a lie half the time.
local silent = function(s, l)
	local f = Fork.floor(Config, s, l, Rng)
	local coin = Rng.new(s * 7919 + l * 104729)
	f.markedDoor = if coin:next() < 0.5 then 1 else 2
	return f
end
eq(readerMisses(real), 0, "witness B: the real fork is readable")
truthy(readerMisses(silent) > 400,
	"witness B: the reader check KILLS a generator whose mark does not follow the trap")
truthy(sideBalanceOff(silent) <= Config.Fairness.SideBalanceTolerance,
	"witness B: ...and that generator is still position-balanced, which is why one check is not enough")

-- WITNESS C — a generator that hands the trap door the better prize. Perfectly readable,
-- perfectly balanced, and solvable without ever reading a sign.
local coupled = function(s, l)
	local f = Fork.floor(Config, s, l, Rng)
	local power = {}
	for _, t in ipairs(Config.Traits) do power[t.id] = t.power end
	local a, b = f.doors[1], f.doors[2]
	local strong = if power[a.traitId] >= power[b.traitId] then 1 else 2
	if strong ~= f.trapDoor then
		f.doors[1], f.doors[2] = b, a
		f.doors[1].slot, f.doors[2].slot = 1, 2
	end
	return f
end
truthy(powerGap(real) <= Config.Fairness.PowerBalanceTolerance, "witness C: the real fork is prize-neutral")
truthy(powerGap(coupled) > Config.Fairness.PowerBalanceTolerance,
	"witness C: the prize check KILLS a generator that puts the better trait behind the trap")
eq(readerMisses(coupled), 0, "witness C: ...and that generator is still readable and balanced")

-- WITNESS D — a generator that quietly moves the `crack` sign onto the trap door whenever it
-- shows on exactly one of them. Sign counts stay at two per door, the inscription still resolves
-- the fork, the sides stay balanced, the prizes stay neutral — and a player who never reads
-- another word wins every time by avoiding cracked doors.
local function reSign(door, from, to)
	for i, k in ipairs(door.signs) do
		if k == from then door.signs[i] = to end
	end
	door.signSet = {}
	for _, k in ipairs(door.signs) do door.signSet[k] = true end
end

local cracked = function(s, l)
	local f = Fork.floor(Config, s, l, Rng)
	-- Never touch the floor's own tell, so this stays readable and only the sign check can see it.
	if f.tellKind == "crack" then return f end
	local trap, safe = f.doors[f.trapDoor], f.doors[3 - f.trapDoor]
	if safe.signSet.crack and not trap.signSet.crack then
		local give = nil
		for _, k in ipairs(trap.signs) do
			if not safe.signSet[k] and k ~= f.tellKind then give = k end
		end
		if give then
			reSign(trap, give, "crack")
			reSign(safe, "crack", give)
		end
	end
	return f
end

local function crackBias(gen)
	local onTrap, onSafe = 0, 0
	for s = 1, 800 do
		for l = 1, FLOORS do
			local f = gen(s, l)
			if f.doors[f.trapDoor].signSet.crack then onTrap += 1 end
			if f.doors[3 - f.trapDoor].signSet.crack then onSafe += 1 end
		end
	end
	return math.abs(onTrap / math.max(onTrap + onSafe, 1) - 0.5)
end

truthy(crackBias(real) <= Config.Fairness.SignBalanceTolerance, "witness D: the real fork's signs are neutral")
truthy(crackBias(cracked) > Config.Fairness.SignBalanceTolerance,
	"witness D: the sign check KILLS a generator that favours the trap door with one sign")
eq(readerMisses(cracked), 0, "witness D: ...and that generator is still readable and balanced")

--============================================================================ CONTROL
-- One change the suite must NOT notice. Every player-visible string in the config — trait
-- labels, sign names, sign emoji — is rewritten, and not one decision may move. A suite that
-- fails here is reporting cosmetics as breakage, which is as useless as a suite that notices
-- nothing: the next person to reword a label would go hunting for a bug that is not there.

do
	local cosmetic = {}
	for k, v in pairs(Config) do cosmetic[k] = v end

	local traits = {}
	for i, t in ipairs(Config.Traits) do
		local copy = {}
		for k, v in pairs(t) do copy[k] = v end
		copy.label = "Renamed trait #" .. i
		traits[i] = copy
	end
	cosmetic.Traits = traits

	local fork = {}
	for k, v in pairs(Config.Fork) do fork[k] = v end
	local names, emoji = {}, {}
	for _, kind in ipairs(Config.Fork.Signs) do
		names[kind] = "SIGN-" .. string.upper(kind)
		emoji[kind] = "*"
	end
	fork.SignNames = names
	fork.SignEmoji = emoji
	cosmetic.Fork = fork

	local drift = 0
	for s = 1, 300 do
		local a = Fork.plan(Config, s, Rng)
		local b = Fork.plan(cosmetic, s, Rng)
		for l = 1, FLOORS do
			local x, y = a.floors[l], b.floors[l]
			if x.trapDoor ~= y.trapDoor then drift += 1 end
			if x.markedDoor ~= y.markedDoor then drift += 1 end
			if x.tellKind ~= y.tellKind then drift += 1 end
			if x.ruleInverted ~= y.ruleInverted then drift += 1 end
			for i = 1, 2 do
				if x.doors[i].traitId ~= y.doors[i].traitId then drift += 1 end
				if x.doors[i].theme ~= y.doors[i].theme then drift += 1 end
				if table.concat(x.doors[i].signs, ",") ~= table.concat(y.doors[i].signs, ",") then
					drift += 1
				end
			end
		end
	end
	eq(drift, 0, "CONTROL: renaming every label, sign name and emoji moves no decision at all")

	-- ...and the rewrite really did reach the module, or the control proves nothing.
	truthy(Fork.floor(cosmetic, 1, 1, Rng).ruleText ~= Fork.floor(Config, 1, 1, Rng).ruleText,
		"CONTROL: the renamed config genuinely reaches the inscription (the control is not a no-op)")
end

--============================================================================ done

print(string.format("Fork: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Fork.spec failed", 0)
end
