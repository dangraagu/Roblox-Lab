-- Pure tests for Anomaly (the clean/anomaly roll). Run: luau tests/Anomaly.spec.luau
local Anomaly = require("../src/shared/Anomaly")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, tol, msg)
	if math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local A = Config.Anomaly

-- count / byId
eq(Anomaly.count(Config), #A.Catalog, "count == catalog size")
truthy(Anomaly.count(Config) >= A.StartPool, "catalog >= StartPool")
truthy(Anomaly.byId(Config, "figure_end") ~= nil, "byId known")
eq(Anomaly.byId(Config, "does_not_exist"), nil, "byId unknown -> nil")

-- every catalog id is unique
do
	local seen, dupe = {}, false
	for _, e in A.Catalog do
		if seen[e.id] then dupe = true end
		seen[e.id] = true
	end
	truthy(not dupe, "catalog ids unique")
end

-- poolSize curve
eq(Anomaly.poolSize(Config, 1), A.StartPool, "day1 pool == StartPool")
truthy(Anomaly.poolSize(Config, 5) >= Anomaly.poolSize(Config, 1), "pool grows with day")
eq(Anomaly.poolSize(Config, 100000), #A.Catalog, "pool clamps to catalog size")
truthy(Anomaly.poolSize(Config, 0) >= 1, "pool >= 1 at day 0")
truthy(Anomaly.poolSize(Config, -3) >= 1, "pool >= 1 at negative day")

-- chance curve
approx(Anomaly.chance(Config, 1), A.BaseChance, 1e-9, "day1 chance == BaseChance")
truthy(Anomaly.chance(Config, 20) > Anomaly.chance(Config, 1), "chance rises with day")
eq(Anomaly.chance(Config, 100000), A.MaxChance, "chance clamps at MaxChance")
truthy(Anomaly.chance(Config, 1) >= 0, "chance non-negative")

-- rollPass determinism
do
	local r1 = Anomaly.rollPass(Rng.new(123), Config, 1)
	local r2 = Anomaly.rollPass(Rng.new(123), Config, 1)
	eq(r1.clean, r2.clean, "rollPass deterministic (clean)")
	eq(r1.anomalyId, r2.anomalyId, "rollPass deterministic (id)")
end

-- clean passes carry no id; anomalous passes carry a valid id
do
	local cleanNoId, anomalyHasValidId = true, true
	for s = 1, 3000 do
		local p = Anomaly.rollPass(Rng.new(s), Config, 1)
		if p.clean then
			if p.anomalyId ~= nil then cleanNoId = false end
		else
			if p.anomalyId == nil or Anomaly.byId(Config, p.anomalyId) == nil then
				anomalyHasValidId = false
			end
		end
	end
	truthy(cleanNoId, "clean pass has no anomalyId")
	truthy(anomalyHasValidId, "anomaly pass has a valid catalog id")
end

-- at day 1, anomaly ids only come from the first StartPool entries
do
	local allowed = {}
	for i = 1, A.StartPool do allowed[A.Catalog[i].id] = true end
	local inPool = true
	for s = 1, 3000 do
		local p = Anomaly.rollPass(Rng.new(s * 7 + 1), Config, 1)
		if not p.clean and not allowed[p.anomalyId] then inPool = false end
	end
	truthy(inPool, "day1 anomalies drawn from StartPool only")
end

-- empirical clean-rate ~= 1 - chance(day1) = 0.5 (loose band)
do
	local clean = 0
	local N = 4000
	for s = 1, N do
		if Anomaly.rollPass(Rng.new(s * 2654435761 % 4294967296), Config, 1).clean then
			clean += 1
		end
	end
	local rate = clean / N
	approx(rate, 1 - A.BaseChance, 0.06, "day1 clean-rate ~= 1 - BaseChance")
end

-- ------------------------------------------------------- REGRESSION: index collapse
-- The day-1 pool is 8 — a POWER OF TWO. The old index draw used Rng.int (state % span),
-- i.e. the LCG's low-order bits, so the choice was a pure function of the seed's lowest 3
-- bits. Every real passSeed loses its low bits (userId * 2654435761 overflows 2^53 and
-- rounds), so every player got the SAME anomaly on every pass, forever.

-- how many DISTINCT day-1 anomaly ids appear over a seed sweep
local function distinctIds(seedOf: (number) -> number, n: number, day: number): number
	local seen, distinct = {}, 0
	for i = 1, n do
		local p = Anomaly.rollPass(Rng.new(seedOf(i)), Config, day)
		if not p.clean and p.anomalyId ~= nil and not seen[p.anomalyId] then
			seen[p.anomalyId] = true
			distinct += 1
		end
	end
	return distinct
end

-- plain seeds: must not be constant, must cover most of the day-1 pool
do
	local d = distinctIds(function(i) return i end, 3000, 1)
	truthy(d >= 6, "day1 index spreads over >= 6 of the 8 pool ids (plain seeds), got " .. d)
end

-- THE SHIPPED BUG (a): seeds whose LOW BITS ARE ZERO — exactly what the overflowing
-- passSeed produced. Under the old Rng.int path this yielded ONE id (scope_gone) forever.
do
	local d = distinctIds(function(i) return i * 2048 end, 3000, 1)
	truthy(d >= 6, "day1 index varies on low-bits-zero seeds (i*2048), got " .. d)
end

-- THE SHIPPED BUG (b): the REAL passSeed formula from the server, for a realistic UserId.
do
	local WS = Config.WorldSeed
	local d = distinctIds(function(i)
		return WS + 1234567890 * 2654435761 + i * 40503
	end, 3000, 1)
	truthy(d >= 6, "day1 index varies across real passSeed serials (big userId), got " .. d)

	-- a second realistic UserId, so the guard isn't tuned to one magic number
	local d2 = distinctIds(function(i)
		return WS + 987654321 * 2654435761 + i * 40503
	end, 3000, 1)
	truthy(d2 >= 6, "day1 index varies for a second big userId, got " .. d2)
end

-- spread at a DEEPER power-of-two pool size too (day 17 -> pool 16)
do
	eq(Anomaly.poolSize(Config, 17), 16, "day17 pool == 16 (power of two)")
	local d = distinctIds(function(i) return i * 2048 end, 4000, 17)
	truthy(d >= 12, "day17 index spreads over >= 12 of the 16 pool ids, got " .. d)
end

-- roughly uniform (not merely non-constant): no day-1 id may take a wild share
do
	local counts, anomalous = {}, 0
	for i = 1, A.StartPool do counts[A.Catalog[i].id] = 0 end
	for i = 1, 8000 do
		local p = Anomaly.rollPass(Rng.new(i * 2048), Config, 1)
		if not p.clean and p.anomalyId ~= nil then
			anomalous += 1
			counts[p.anomalyId] = (counts[p.anomalyId] or 0) + 1
		end
	end
	local expected = anomalous / A.StartPool
	local balanced = anomalous > 0
	for _, c in counts do
		if c < expected * 0.6 or c > expected * 1.4 then balanced = false end
	end
	truthy(balanced, "day1 anomaly ids are roughly uniform over the pool")
end

-- draw budget unchanged: exactly TWO draws on an anomalous pass, ONE on a clean pass
do
	local budgetOk = true
	for s = 1, 400 do
		local live = Rng.new(s * 977 + 5)
		local p = Anomaly.rollPass(live, Config, 1)
		local ref = Rng.new(s * 977 + 5)
		local steps = if p.clean then 1 else 2
		for _ = 1, steps do Rng.step(ref) end
		if live.state ~= ref.state then budgetOk = false end
	end
	truthy(budgetOk, "rollPass consumes 1 draw when clean, 2 when anomalous")
end

-- determinism survives the switch to the high-bit draw
do
	local same = true
	for s = 1, 200 do
		local a = Anomaly.rollPass(Rng.new(s * 2048), Config, 3)
		local b = Anomaly.rollPass(Rng.new(s * 2048), Config, 3)
		if a.clean ~= b.clean or a.anomalyId ~= b.anomalyId then same = false end
	end
	truthy(same, "rollPass still fully deterministic per seed")
end

print(string.format("Anomaly: %d passed, %d failed", passed, failed))
if failed > 0 then error("Anomaly tests failed") end
