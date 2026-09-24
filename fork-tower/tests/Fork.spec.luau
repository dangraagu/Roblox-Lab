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
-- The 2026-09-17 Fork.luau, byte-for-byte (sha256 0c840300…5b07). Its whole plan was a function of
-- WorldSeed and the run seed, both replicated, so every trap was computable on the client. Kept
-- ONLY as the reference the migration path must reproduce and the leak the witnesses re-create.
local Legacy = require("./fixtures/Fork_20260917")

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
--
-- SERVER-SHAPED SECRETS. The hidden half of every floor — which door is the trap, the liar line,
-- the tell, the traits — is decided by a 32-bit secret the SERVER draws per floor per run
-- (mintSecret in Main.server.luau) and never replicates. The CLI has no Roblox Random, so the sweep
-- draws the same shape, one uniform 32-bit integer per floor, from Luau's own math.random: a
-- generator that shares no arithmetic with Fork's mixer or Rng's LCG, so nothing below can pass
-- because the test's randomness and the module's are secretly the same function. Seeded, so the
-- numbers this file prints are reproducible.
math.randomseed(20260917)
local function draw32(): number
	return math.random(0, 65535) * 65536 + math.random(0, 65535)
end
local function freshSecrets()
	local out = {}
	for l = 1, FLOORS do out[l] = draw32() end
	return out
end
local secretsOf = {}
local function secretsFor(s)
	if secretsOf[s] == nil then secretsOf[s] = freshSecrets() end
	return secretsOf[s]
end

local plans = {}
for s = 1, SWEEP do
	plans[s] = Fork.plan(Config, s, Rng, secretsFor(s))
end

-- Which door VISIBLY bears the sign the inscription names — read off the door's own sign list,
-- which is exactly what the server carves onto the door and what a player standing on the pad can
-- see. Returns nil when the fork is unreadable: nought or both doors bearing it, either of which
-- turns the floor into a coin flip. Nothing here consults markedDoor, and that is the whole point
-- (see FINDING 6 below).
local function bearerOfTell(floor): number?
	local bearer, count = nil, 0
	for slot = 1, 2 do
		local has = false
		for _, kind in ipairs(floor.doors[slot].signs) do
			if kind == floor.tellKind then
				has = true
			end
		end
		if has then
			count += 1
			bearer = slot
		end
	end
	if count ~= 1 then
		return nil
	end
	return bearer
end

local function eachFloor(fn)
	for s = 1, SWEEP do
		for _, floor in ipairs(plans[s].floors) do
			fn(floor, s)
		end
	end
end

--============================================================================ determinism

local function signsOf(floor)
	return table.concat(floor.doors[1].signs, "+") .. "|" .. table.concat(floor.doors[2].signs, "+")
end

-- The fields a read BUYS, and which nothing a client holds may compute. tellKind is left out on
-- purpose: it is chosen among the signs the marked door carries alone, and those carvings are
-- public, so it legitimately moves with them.
local function hiddenOf(floor)
	return string.format("%d/%d/%s/%s/%s", floor.trapDoor, floor.markedDoor, tostring(floor.ruleInverted),
		floor.doors[1].traitId, floor.doors[2].traitId)
end

do
	-- A REJOIN IS THE SAME TOWER: the same run seed with the same SAVED secrets rebuilds it exactly.
	local secrets = secretsFor(12345)
	local a = Fork.plan(Config, 12345, Rng, secrets)
	local b = Fork.plan(Config, 12345, Rng, table.clone(secrets))
	local same = true
	for l = 1, FLOORS do
		local x, y = a.floors[l], b.floors[l]
		if hiddenOf(x) ~= hiddenOf(y) or x.tellKind ~= y.tellKind or signsOf(x) ~= signsOf(y) then
			same = false
		end
	end
	truthy(same, "the same runSeed and the same saved secrets rebuild a byte-identical plan (a rejoin is the same tower)")

	-- A rebirth is only worth doing if it is a DIFFERENT tower. It is a new run seed AND a fresh
	-- draw of secrets, which is what the server does.
	--
	-- What this file used to claim alongside it — "a leaderboard time only means something if the
	-- tower is the same tower for everyone" — is given up for the HIDDEN half on purpose, and it is
	-- the whole fix: a trap that is the same for everyone on a run seed is a trap anyone can compute
	-- from that run seed. The visible half (signs, and the geometry behind a door) is still shared.
	local differs = 0
	for s = 1, 200 do
		local p = Fork.plan(Config, s, Rng, secretsFor(s))
		local q = Fork.plan(Config, s + 1, Rng, secretsFor(s + 1))
		for l = 1, FLOORS do
			if hiddenOf(p.floors[l]) ~= hiddenOf(q.floors[l]) then
				differs += 1
				break
			end
		end
	end
	eq(differs, 200, "every rebirth (next run seed, freshly drawn secrets) produces a different run")

	-- Fork.floor is just plan().floors[level]; if the two ever disagree, the server and the
	-- tests are looking at different games.
	local plan = Fork.plan(Config, 777, Rng, secretsFor(777))
	local agree = true
	for l = 1, FLOORS do
		local one = Fork.floor(Config, 777, l, Rng, secretsFor(777))
		if one.trapDoor ~= plan.floors[l].trapDoor or one.tellKind ~= plan.floors[l].tellKind then
			agree = false
		end
	end
	truthy(agree, "Fork.floor agrees with Fork.plan on every floor")

	-- The WorldSeed still has to reach the tower — the part of it everybody SEES. Change it and the
	-- carvings move. (It must no longer move the trap; the plan-secret block below asserts that.)
	local other = {}
	for k, v in pairs(Config) do other[k] = v end
	other.WorldSeed = Config.WorldSeed + 1
	local moved = false
	for l = 1, FLOORS do
		if signsOf(Fork.floor(other, 777, l, Rng, secretsFor(777))) ~= signsOf(plan.floors[l]) then moved = true end
	end
	truthy(moved, "changing WorldSeed changes the sign carvings (the visible tower is still the world's)")
end

--============================================================================ the plan secret
--
-- MEASURED 2026-09-17: the whole plan was computable on the client. Fork.luau is in
-- ReplicatedStorage and derived every floor from Config.WorldSeed and the run seed, and the run seed
-- is leaderstats.Rebirths + 1. A probe compared 30 honestly-read forks with
-- Fork.plan(Config, Rebirths + 1, Rng) computed from replicated modules alone: 30 of 30. Every
-- read an honest player paid for was free to a script.
--
-- A salt mixed into that seed would NOT have fixed it, and the claims below are the reasons:
--
--   * the seed is 32 bits. If the salted seed still drove anything a client sees before reading —
--     the sign carvings, the geometry — a script tries all 2^32 seeds offline against floor 1's
--     carvings and then knows every floor. So the VISIBLE HALF must not depend on the secret.
--   * every honest read reveals the trap side, the liar line and two traits. If the whole run hung
--     off one 32-bit secret, a handful of paid reads would pin it and the rest of the run would be
--     free. So each floor has its OWN secret, drawn independently by the server, and re-drawing one
--     floor's secret must move nothing on any other floor.
--   * the HIDDEN HALF must not depend on anything public at all, or it is back to being computable.
--
-- And a profile saved before the secret existed must migrate without moving anything its player
-- already saw: Fork.legacySecrets reproduces the 2026-09-17 plan exactly, and is ONLY for floors
-- that player has already seen.

-- Each of these takes a generator gen(runSeed, level, secrets) -> floor, so the witnesses at the
-- bottom of the file can hand them a deliberately broken one.
local function realGen(s, l, secrets) return Fork.floor(Config, s, l, Rng, secrets) end

-- How many sign carvings move when the secrets are re-drawn and nothing else changes.
local function signsMovedBySecrets(gen, seeds: number, draws: number): (number, number)
	local moved, compared = 0, 0
	for s = 1, seeds do
		local base = {}
		for l = 1, FLOORS do base[l] = signsOf(gen(s, l, secretsFor(s))) end
		for _ = 1, draws do
			local alt = freshSecrets()
			for l = 1, FLOORS do
				compared += 1
				if signsOf(gen(s, l, alt)) ~= base[l] then moved += 1 end
			end
		end
	end
	return moved, compared
end

-- How often the 2026-09-17 derivation — everything a client can compute — names the real trap.
local legacyPlanOf = {}
local function publicMatch(gen, seeds: number): number
	local hit, n = 0, 0
	for s = 1, seeds do
		if legacyPlanOf[s] == nil then legacyPlanOf[s] = Legacy.plan(Config, s, Rng) end
		for l = 1, FLOORS do
			n += 1
			if gen(s, l, secretsFor(s)).trapDoor == legacyPlanOf[s].floors[l].trapDoor then hit += 1 end
		end
	end
	return hit / n
end

do
	-- FAIL CLOSED. A server that forgot to pass its secrets must not quietly get a public plan.
	truthy(not pcall(Fork.plan, Config, 1, Rng),
		"Fork.plan REFUSES to plan without secrets — there is no public fallback to fall back to")
	truthy(not pcall(Fork.plan, Config, 1, Rng, { 1, 2, 3 }),
		"...and refuses a secret list that does not cover every floor")
	local bad = freshSecrets()
	bad[4] = 4294967296
	truthy(not pcall(Fork.plan, Config, 1, Rng, bad), "...or holds a value outside 32 bits")
	bad[4] = 12.5
	truthy(not pcall(Fork.plan, Config, 1, Rng, bad), "...or holds a value that is not an integer")
	truthy(Fork.isSecret(0) and Fork.isSecret(4294967295) and not Fork.isSecret(-1)
		and not Fork.isSecret("7") and not Fork.isSecret(nil),
		"Fork.isSecret accepts exactly the integers in [0, 2^32)")

	-- THE VISIBLE HALF IS PUBLIC.
	local moved, compared = signsMovedBySecrets(realGen, 200, 3)
	eq(moved, 0, string.format(
		"THE VISIBLE HALF IS PUBLIC: re-drawing the secrets moved %d of %d sign carvings — nothing a client sees before a read is derived from the secret, so there is nothing to brute-force a secret against",
		moved, compared))

	-- THE HIDDEN HALF IS SECRET, and ONLY secret.
	local otherWorld = {}
	for k, v in pairs(Config) do otherWorld[k] = v end
	otherWorld.WorldSeed = Config.WorldSeed + 104729
	local hiddenMoved, followed, n = 0, 0, 0
	for s = 1, 400 do
		local secrets = secretsFor(s)
		local a = Fork.plan(Config, s, Rng, secrets)
		local b = Fork.plan(Config, s + 7919, Rng, secrets)
		local c = Fork.plan(otherWorld, s, Rng, secrets)
		local d = Fork.plan(Config, s, Rng, freshSecrets())
		for l = 1, FLOORS do
			n += 1
			if hiddenOf(a.floors[l]) ~= hiddenOf(b.floors[l]) or hiddenOf(a.floors[l]) ~= hiddenOf(c.floors[l]) then
				hiddenMoved += 1
			end
			if a.floors[l].trapDoor ~= d.floors[l].trapDoor then followed += 1 end
		end
	end
	eq(hiddenMoved, 0, string.format(
		"THE HIDDEN HALF IS SECRET: with the secrets held fixed, a different run seed or WorldSeed moved no trap, no marked door, no liar line and no trait on any of %d floors",
		n))
	near(followed / n, 0.5, Config.Fairness.SideBalanceTolerance, string.format(
		"...and it really is the secret that decides it: a fresh draw moves the trap on %.3f of floors, a coin's half",
		followed / n))

	-- ONE READ BUYS ONE FLOOR.
	local crossMoved, crossCompared = 0, 0
	for s = 1, 150 do
		local secrets = secretsFor(s)
		local base = Fork.plan(Config, s, Rng, secrets)
		for changed = 1, FLOORS do
			local alt = table.clone(secrets)
			alt[changed] = draw32()
			local p = Fork.plan(Config, s, Rng, alt)
			for l = 1, FLOORS do
				if l ~= changed then
					crossCompared += 1
					local x, y = base.floors[l], p.floors[l]
					if hiddenOf(x) ~= hiddenOf(y) or x.tellKind ~= y.tellKind or signsOf(x) ~= signsOf(y) then
						crossMoved += 1
					end
				end
			end
		end
	end
	eq(crossMoved, 0, string.format(
		"ONE READ BUYS ONE FLOOR: re-drawing one floor's secret moved %d of %d OTHER floors — so a read, even one that pins its floor's 32-bit secret exactly, says nothing about the next floor",
		crossMoved, crossCompared))

	-- The client's best computation, scored: the 2026-09-17 derivation against the real trap.
	local match = publicMatch(function(s, l) return plans[s].floors[l] end, SWEEP)
	near(match, 0.5, Config.Fairness.SideBalanceTolerance, string.format(
		"everything a client can compute (the 2026-09-17 public derivation) names the trap on %.4f of %d forks — a coin",
		match, SWEEP * FLOORS))

	-- MIGRATION: the legacy secrets reproduce the 2026-09-17 plan, field for field.
	local fieldsDiffer, floorsCompared, legacyValid = 0, 0, true
	for s = 1, 500 do
		local secrets = Fork.legacySecrets(Config, s)
		for l = 1, FLOORS do
			if not Fork.isSecret(secrets[l]) then legacyValid = false end
		end
		local new = Fork.plan(Config, s, Rng, secrets)
		local old = Legacy.plan(Config, s, Rng)
		for l = 1, FLOORS do
			floorsCompared += 1
			local x, y = new.floors[l], old.floors[l]
			local same = x.level == y.level and x.trapDoor == y.trapDoor and x.markedDoor == y.markedDoor
				and x.tellKind == y.tellKind and x.ruleInverted == y.ruleInverted
				and x.ruleText == y.ruleText and x.ruleSign == y.ruleSign
			for i = 1, 2 do
				local dx, dy = x.doors[i], y.doors[i]
				if dx.slot ~= dy.slot or dx.traitId ~= dy.traitId or dx.theme ~= dy.theme or dx.label ~= dy.label
					or table.concat(dx.signs, ",") ~= table.concat(dy.signs, ",") then
					same = false
				end
			end
			if not same then fieldsDiffer += 1 end
		end
	end
	truthy(legacyValid, "Fork.legacySecrets returns a valid 32-bit secret for every floor")
	eq(fieldsDiffer, 0, string.format(
		"MIGRATION: Fork.plan with Fork.legacySecrets reproduces the 2026-09-17 Fork.plan field for field on %d floors — a floor a player already saw is exactly the floor they saw",
		floorsCompared))

	print(string.format("  plan secret: carvings moved by a re-draw %d/%d; hidden half moved by run seed or WorldSeed %d/%d;"
		.. " trap moved by a re-draw %.4f; other floors moved by one floor's re-draw %d/%d;"
		.. " public derivation names the trap %.4f of %d; legacy migration differs on %d/%d floors",
		moved, compared, hiddenMoved, n, followed / n, crossMoved, crossCompared,
		match, SWEEP * FLOORS, fieldsDiffer, floorsCompared))
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

	-- ...and the same player, reading the same fork off the DOORS instead of off the plan.
	local unreadable, doorTrapped, markedDisagrees = 0, 0, 0

	eachFloor(function(floor)
		if Fork.readTrap(floor) ~= floor.trapDoor then readerTrapped += 1 end
		if floor.markedDoor ~= floor.trapDoor then naiveTrapped += 1 end
		if floor.ruleInverted then inverted += 1 end
		if floor.trapDoor == 1 then blindTrapped += 1 end

		local bearer = bearerOfTell(floor)
		if bearer == nil then
			unreadable += 1
		else
			if bearer ~= floor.markedDoor then markedDisagrees += 1 end
			local said = if floor.ruleInverted then 3 - bearer else bearer
			if said ~= floor.trapDoor then doorTrapped += 1 end
		end
	end)

	local total = SWEEP * FLOORS
	eq(readerTrapped, 0,
		"FAIRNESS 2: a player who reads the inscription hits ZERO traps across every seed and floor")

	-- REVIEW FINDING 6. The line above is weaker than it looks, and it took an adversarial review
	-- to say so: Fork.readTrap reads the markedDoor FIELD, and markedDoor is computed FROM trapDoor
	-- eight lines up in Fork.plan. So it compares a field against the field it is derived from, and
	-- it is true by construction on any generator — including one where the tell is on both doors
	-- and the fork is a genuine coin flip. That exact mutation left this file at 47 passed, 0
	-- failed; only the end-to-end world check, which derives the marked door from the doors the way
	-- a player does, went red.
	--
	-- These three assert the property promise 2 actually is: exactly one door BEARS the named sign,
	-- it is the door the plan calls marked (so the server's `Marked` attribute is not a second,
	-- independent claim), and reading it names the trap.
	eq(unreadable, 0, string.format(
		"FAIRNESS 2: exactly one of the two doors bears the sign the inscription names, on all %d forks", total))
	eq(markedDisagrees, 0,
		"FAIRNESS 2: ...and that door is the one the plan calls marked, so the doors and the plan agree")
	eq(doorTrapped, 0,
		"FAIRNESS 2: ...so a player reading the SIGNS, not the plan, still walks past every trap")

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

local real = function(s, l) return Fork.floor(Config, s, l, Rng, secretsFor(s)) end

-- WITNESS A — a generator that always traps the left door. The reader check cannot see it (the
-- mark moves with the trap, so reading still works); only the position check can.
local biased = function(s, l)
	local f = Fork.floor(Config, s, l, Rng, secretsFor(s))
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
	local f = Fork.floor(Config, s, l, Rng, secretsFor(s))
	local coin = Rng.new(s * 7919 + l * 104729)
	f.markedDoor = if coin:next() < 0.5 then 1 else 2
	return f
end
eq(readerMisses(real), 0, "witness B: the real fork is readable")
truthy(readerMisses(silent) > 400,
	"witness B: the reader check KILLS a generator whose mark does not follow the trap")
truthy(sideBalanceOff(silent) <= Config.Fairness.SideBalanceTolerance,
	"witness B: ...and that generator is still position-balanced, which is why one check is not enough")

-- WITNESS E — the fork the review actually broke: the tell is no longer restricted to signs the
-- marked door holds EXCLUSIVELY, so both doors may bear it and the inscription points at nothing.
-- Every floor is then a genuine coin flip, which is the one thing this game promises it is not.
--
-- The old reader check cannot see it — it reads the markedDoor FIELD, which the mutation leaves
-- perfectly consistent — and that is exactly how the mutation survived all six suites at 47/0.
-- Only reading the doors catches it. This witness is here so the finding cannot come back.
local function doorMisses(gen)
	local miss = 0
	for s = 1, 400 do
		for l = 1, FLOORS do
			local f = gen(s, l)
			if bearerOfTell(f) == nil then
				miss += 1
			else
				local said = if f.ruleInverted then 3 - bearerOfTell(f) else bearerOfTell(f)
				if said ~= f.trapDoor then miss += 1 end
			end
		end
	end
	return miss
end

local ambiguous = function(s, l)
	local f = Fork.floor(Config, s, l, Rng, secretsFor(s))
	local other = f.doors[3 - f.markedDoor]
	if not other.signSet[f.tellKind] then
		other.signs[#other.signs + 1] = f.tellKind
		other.signSet[f.tellKind] = true
	end
	return f
end
eq(doorMisses(real), 0, "witness E: the real fork reads correctly off the doors themselves")
truthy(doorMisses(ambiguous) > 400,
	"witness E: the door-reading check KILLS a fork where BOTH doors bear the named sign")
eq(readerMisses(ambiguous), 0,
	"witness E: ...and the field-reading check cannot see it at all, which is why it was not enough")

-- WITNESS C — a generator that hands the trap door the better prize. Perfectly readable,
-- perfectly balanced, and solvable without ever reading a sign.
local coupled = function(s, l)
	local f = Fork.floor(Config, s, l, Rng, secretsFor(s))
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
	local f = Fork.floor(Config, s, l, Rng, secretsFor(s))
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

-- WITNESS F — the defect measured on 2026-09-17, re-created: the trap side re-derived from the
-- public seed. Perfectly readable, perfectly balanced, prize-neutral — every fairness check above
-- this block passed it for months — and every trap is computable by anyone holding Config and
-- leaderstats.
local leaky = function(s, l)
	local f = Fork.floor(Config, s, l, Rng, secretsFor(s))
	if legacyPlanOf[s] == nil then legacyPlanOf[s] = Legacy.plan(Config, s, Rng) end
	f.trapDoor = legacyPlanOf[s].floors[l].trapDoor
	f.markedDoor = if f.ruleInverted then 3 - f.trapDoor else f.trapDoor
	return f
end
truthy(math.abs(publicMatch(function(s, l) return real(s, l) end, 400) - 0.5) <= Config.Fairness.SideBalanceTolerance,
	"witness F: the real fork's trap is not what the public derivation says")
truthy(math.abs(publicMatch(function(s, l) return leaky(s, l) end, 400) - 0.5) > Config.Fairness.SideBalanceTolerance,
	"witness F: the public-predictor check KILLS a generator whose trap is re-derived from the public seed")
truthy(readerMisses(leaky) == 0 and sideBalanceOff(leaky) <= Config.Fairness.SideBalanceTolerance,
	"witness F: ...and that generator is still readable and balanced, which is why no fairness check could see the leak")

-- WITNESS G — the NAIVE fix: a server-only salt mixed into the one 32-bit seed that drives the
-- whole floor, carvings included. The trap is now unpredictable from Config and leaderstats — it
-- passes the public-predictor check — and it is still broken: the sign carvings a client sees
-- before reading are a function of the secret, so a script tries all 2^32 values against floor
-- 1's carvings and reads the rest of the tower for free. Built here by planning the floor with the
-- secret standing in for the run seed.
local salted = function(s, l, secrets)
	local f = Fork.floor(Config, s, l, Rng, secrets)
	local v = Fork.floor(Config, secrets[l] % 1048576, l, Rng, secrets)
	for i = 1, 2 do
		f.doors[i].signs = v.doors[i].signs
		f.doors[i].signSet = v.doors[i].signSet
	end
	return f
end
do
	local realMoved = signsMovedBySecrets(realGen, 40, 2)
	local saltedMoved, saltedCompared = signsMovedBySecrets(salted, 40, 2)
	print(string.format("  witness G: salted carvings moved %d of %d under a re-draw (real: %d)",
		saltedMoved, saltedCompared, realMoved))
	eq(realMoved, 0, "witness G: the real fork's carvings do not move with the secret")
	truthy(saltedMoved > saltedCompared / 2, string.format(
		"witness G: the visible-half check KILLS a generator whose carvings are salted with the secret (%d of %d moved)",
		saltedMoved, saltedCompared))
	truthy(math.abs(publicMatch(function(s, l) return salted(s, l, secretsFor(s)) end, 400) - 0.5)
		<= Config.Fairness.SideBalanceTolerance,
		"witness G: ...and that generator PASSES the public-predictor check, which is why that check alone is not the fix")
end

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
		local a = Fork.plan(Config, s, Rng, secretsFor(s))
		local b = Fork.plan(cosmetic, s, Rng, secretsFor(s))
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
	truthy(Fork.floor(cosmetic, 1, 1, Rng, secretsFor(1)).ruleText ~= Fork.floor(Config, 1, 1, Rng, secretsFor(1)).ruleText,
		"CONTROL: the renamed config genuinely reaches the inscription (the control is not a no-op)")
end

--============================================================================ done

print(string.format("Fork: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Fork.spec failed", 0)
end
