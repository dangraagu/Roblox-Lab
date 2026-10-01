-- Salt: the server-only randomness behind every manor the server builds. Run from the game directory:
--   luau tests/Salt.spec.luau
--
-- docs/complete-game-standard.md §1: "A seed a player could memorise gets a server-only salt, and a salt on a 32-bit
-- seed that also drives visible geometry is not enough (fork-tower REVIEW-4)." Before this, night N's manor was
-- Manor.plan(Rng.new(WorldSeed * A + N * B)): Config and Manor live in ReplicatedStorage, so any client could compute
-- every night's rooms, relics, exit and patrol ahead of time, and a guide could list them. Now the server draws two
-- fresh 32-bit halves for every attempt at a night (a retry is a new manor too) and plans from Salt.new(a, b). The
-- manor IS visible geometry, so the generator's hidden state has to be far over 32 bits: a script that sees the foyer
-- must not be able to try every seed offline and read off where the exit is. Two independent 32-bit streams, mixed:
-- 2^64 states.
local Salt = require("../src/shared/Salt")
local Manor = require("../src/shared/Manor")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

--======================================================================= the halves

truthy(Salt.valid(0, 0), "0, 0 is a valid salt")
truthy(Salt.valid(4294967295, 123), "2^32 - 1 is the largest half")
truthy(not Salt.valid(4294967296, 1), "2^32 is out of range")
truthy(not Salt.valid(-1, 1), "negative is out of range")
truthy(not Salt.valid(1.5, 1), "a fraction is not a salt")
truthy(not Salt.valid(nil :: any, 1), "nil is not a salt")
eq(Salt.HALF, 4294967296, "each half is 32 bits")

--======================================================================= a generator Manor.plan can use

do
	local r = Salt.new(12345, 67890)
	local okRange, okBelow = true, true
	for _ = 1, 5000 do
		local x = r:next()
		if not (x >= 0 and x < 1) then okRange = false end
		local b = r:below(7)
		if b < 1 or b > 7 or b % 1 ~= 0 then okBelow = false end
	end
	truthy(okRange, "next() is in [0, 1)")
	truthy(okBelow, "below(7) is a whole number in [1, 7]")
	-- same halves, same stream: the server can rebuild the plan it built
	local x, y = Salt.new(99, 7), Salt.new(99, 7)
	local same = true
	for _ = 1, 200 do if x:next() ~= y:next() then same = false end end
	truthy(same, "the same halves give the same stream")
end

-- uniform, including the small power-of-two ranges that break an LCG's low bits (docs/new-game-checklist.md §3)
do
	local r = Salt.new(2718281828, 3141592653)
	for _, n in { 2, 4, 6, 8 } do
		local counts = {}
		for i = 1, n do counts[i] = 0 end
		local draws = 12000
		for _ = 1, draws do
			local v = r:below(n)
			counts[v] += 1
		end
		local worst = 0
		for i = 1, n do worst = math.max(worst, math.abs(counts[i] / (draws / n) - 1)) end
		truthy(worst < 0.08, string.format("below(%d) over %d draws: every value within 8%% of its share (worst %.3f)", n, draws, worst))
	end
	-- no alternation: consecutive below(2) draws agree about half the time (an LCG's lowest bit alternates)
	local same, prev = 0, r:below(2)
	for _ = 1, 10000 do
		local v = r:below(2)
		if v == prev then same += 1 end
		prev = v
	end
	truthy(math.abs(same / 10000 - 0.5) < 0.03, string.format("consecutive coin flips agree %.3f of the time (0.5 +- 0.03)", same / 10000))
end

--======================================================================= 64 bits, both halves load-bearing

do
	-- change one half, keep the other: the stream changes either way
	local function head(a, b)
		local r = Salt.new(a, b)
		local t = {}
		for i = 1, 6 do t[i] = string.format("%.6f", r:next()) end
		return table.concat(t, ",")
	end
	local seenA, seenB = {}, {}
	local distinctA, distinctB = 0, 0
	for i = 0, 999 do
		local ha = head(i * 4099 + 17, 424242)
		if not seenA[ha] then seenA[ha] = true; distinctA += 1 end
		local hb = head(424242, i * 4099 + 17)
		if not seenB[hb] then seenB[hb] = true; distinctB += 1 end
	end
	eq(distinctA, 1000, "1000 different first halves (second fixed): 1000 different streams")
	eq(distinctB, 1000, "1000 different second halves (first fixed): 1000 different streams")
	-- (a, b) and (b, a) are different salts
	truthy(head(1, 2) ~= head(2, 1), "the halves are not interchangeable")
	-- the second half is not just added to the first: (a + 1, b) and (a, b + 1) differ
	truthy(head(1000, 2000) ~= head(1001, 1999), "the halves are not simply summed")
end

--======================================================================= salted manors are still good manors

-- The same invariants Manor.spec asserts over the public seeds, over salted plans: every room reachable, the exit the
-- deepest room, no dead end the repair pass could close, relics as promised.
local function depths(plan)
	local d = { [plan.entranceId] = 0 }
	local q, head = { plan.entranceId }, 1
	while head <= #q do
		local id = q[head]; head += 1
		for _, nb in Manor.neighbours(plan, id) do
			if d[nb] == nil then d[nb] = d[id] + 1; table.insert(q, nb) end
		end
	end
	return d
end

do
	local src = Rng.new(777)
	local plans, connected, deepest, relicsOk, sizeOk, deadEnds, roomsTotal = 0, 0, 0, 0, 0, 0, 0
	for night = 1, 60, 3 do
		for _ = 1, 15 do
			local a = math.floor(src:next() * Salt.HALF)
			local b = math.floor(src:next() * Salt.HALF)
			local plan = Manor.plan(Salt.new(a, b), Config, night)
			plans += 1
			local d = depths(plan)
			local reach, maxD = 0, 0
			for _, r in plan.rooms do
				if d[r.id] ~= nil then reach += 1; maxD = math.max(maxD, d[r.id]) end
			end
			if reach == #plan.rooms then connected += 1 end
			if d[plan.exitId] == maxD then deepest += 1 end
			if #plan.relics == Manor.relicCount(Config, night) then relicsOk += 1 end
			local target = Manor.roomCount(Config, night)
			if #plan.rooms >= target and #plan.rooms <= Config.Manor.MaxRooms then sizeOk += 1 end
			for _, r in plan.rooms do
				roomsTotal += 1
				if #Manor.neighbours(plan, r.id) == 1 then deadEnds += 1 end
			end
		end
	end
	eq(connected, plans, string.format("all %d salted manors: every room reachable from the foyer", plans))
	eq(deepest, plans, "the exit is the deepest room in every one")
	eq(relicsOk, plans, "every one places the relics Manor.relicCount promises")
	eq(sizeOk, plans, "every one is inside its night's room band")
	truthy(deadEnds / roomsTotal < 0.02, string.format("dead ends stay rare (%d of %d rooms)", deadEnds, roomsTotal))
end

--======================================================================= the public numbers predict nothing

-- What a client can compute (the public plan for this night) says nothing about the manor the server builds: the exit
-- lands in the public plan's exit cell only about as often as it lands in any cell a manor that size could use, and
-- over 200 salts the exit is found in many different cells.
do
	local src = Rng.new(4242)
	for _, night in { 1, 10, 25 } do
		local pub = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
		local pubExit = Manor.roomById(pub, pub.exitId) :: any
		local hits, cells, distinct = 0, {}, 0
		local N = 200
		for _ = 1, N do
			local plan = Manor.plan(Salt.new(math.floor(src:next() * Salt.HALF), math.floor(src:next() * Salt.HALF)), Config, night)
			local ex = Manor.roomById(plan, plan.exitId) :: any
			if ex.gx == pubExit.gx and ex.gz == pubExit.gz then hits += 1 end
			local k = ex.gx .. "," .. ex.gz
			if not cells[k] then cells[k] = true; distinct += 1 end
		end
		print(string.format("  night %d: the salted exit sat in the public plan's exit cell %d of %d times; %d different cells", night, hits, N, distinct))
		truthy(hits / N < 0.2, string.format("night %d: the public plan names the exit's cell on %d of %d salted manors (under 20%%)", night, hits, N))
		truthy(distinct >= 8, string.format("night %d: the exit turns up in %d different cells (at least 8)", night, distinct))
	end
end

--======================================================================= CONTROL

-- Renaming a room kind moves nothing in a salted plan.
do
	local kind = Config.Manor.Kinds[3]
	local before = kind.name
	local p1 = Manor.plan(Salt.new(5, 6), Config, 12)
	kind.name = "Hall of Mirrors"
	local p2 = Manor.plan(Salt.new(5, 6), Config, 12)
	kind.name = before
	local same = #p1.rooms == #p2.rooms and p1.exitId == p2.exitId
	for i, r in p1.rooms do
		local q = p2.rooms[i]
		if q.gx ~= r.gx or q.gz ~= r.gz or q.kind ~= r.kind then same = false end
	end
	truthy(same, "CONTROL: renaming a room kind moves nothing in a salted manor")
end

print(string.format("Salt: %d passed, %d failed", passed, failed))
if failed > 0 then error("Salt tests failed") end
