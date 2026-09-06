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

-- CASE (a) — SEED-SHAPE REGRESSION, INDEPENDENT OF ANY passSeed FORMULA.
-- Seeds whose LOW BITS ARE ZERO (i * 2048). This is the exact shape the OLD overflowing
-- passSeed produced, and under the old Rng.int path it yielded ONE id (scope_gone) forever.
-- The server no longer generates seeds like this, but the draw must never again depend on
-- the low bits, so this case is kept DELIBERATELY as a permanent property guard. Do not
-- delete it just because the caller changed.
do
	local d = distinctIds(function(i) return i * 2048 end, 3000, 1)
	truthy(d >= 6, "day1 index varies on low-bits-zero seeds (i*2048), got " .. d)
end

-- CASE (b) — THE OLD, OVERFLOWING passSeed, kept verbatim as a historical regression.
-- `userId * 2654435761` exceeds 2^53 for every modern UserId, so the product was rounded and
-- the low bits became a constant. This is NOT what the server computes any more (see case c);
-- it is here so the low-bit-collapse property is still exercised against the exact arithmetic
-- that shipped the bug.
do
	local WS = Config.WorldSeed
	local d = distinctIds(function(i)
		return WS + 1234567890 * 2654435761 + i * 40503
	end, 3000, 1)
	truthy(d >= 6, "day1 index varies across LEGACY overflowing passSeed serials, got " .. d)

	-- a second realistic UserId, so the guard isn't tuned to one magic number
	local d2 = distinctIds(function(i)
		return WS + 987654321 * 2654435761 + i * 40503
	end, 3000, 1)
	truthy(d2 >= 6, "day1 index varies for a second big userId (legacy formula), got " .. d2)
end

-- CASE (c) — THE CURRENT SERVER FORMULA, mirrored from src/server/Main.server.luau.
-- passSeed reduces the UserId FIRST (mod a prime) and folds a per-session salt, so no
-- intermediate reaches 2^53, then avalanche-mixes the result. Keep this block in step with
-- the server: if passSeed changes there and not here, this test stops testing the real thing
-- (which is precisely the rot this case replaces).
local SEED_MOD = 4294967296 -- 2^32, matches Rng's state space
local UID_MOD = 1000003 -- prime; keeps UserId small before it is multiplied

local function mixSeed(x: number): number
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = (x * 2038073) % SEED_MOD
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = (x * 1832993) % SEED_MOD
	return bit32.bxor(x, bit32.rshift(x, 16))
end

local function passSeed(userId: number, salt: number, serial: number): number
	local uid = userId % UID_MOD -- <= 1e6
	local sum = (Config.WorldSeed % SEED_MOD) -- < 4.3e9
		+ (salt % SEED_MOD) -- < 4.3e9
		+ uid * 40503 -- < 4.1e10
		+ (serial % UID_MOD) * 2654435 -- < 2.7e12  (total stays ~3 orders under 2^53)
	return mixSeed(sum % SEED_MOD)
end

do
	-- the seed stays inside Rng's state space and is a whole number (no float rounding)
	local inRange, whole = true, true
	for i = 1, 500 do
		local s = passSeed(1234567890, 987654321, i)
		if s < 0 or s >= SEED_MOD then inRange = false end
		if s ~= math.floor(s) then whole = false end
	end
	truthy(inRange, "current passSeed stays within [0, 2^32)")
	truthy(whole, "current passSeed is an exact integer (no 2^53 rounding)")

	-- consecutive serials must not collapse onto one another
	do
		local seen, distinct = {}, 0
		for i = 1, 1000 do
			local s = passSeed(1234567890, 987654321, i)
			if not seen[s] then seen[s] = true; distinct += 1 end
		end
		truthy(distinct >= 990, "current passSeed gives ~unique seeds per serial, got " .. distinct)
	end

	-- and the day-1 draw spreads across the pool for real players
	local d = distinctIds(function(i) return passSeed(1234567890, 987654321, i) end, 3000, 1)
	truthy(d >= 6, "day1 index varies across CURRENT passSeed serials (big userId), got " .. d)

	local d2 = distinctIds(function(i) return passSeed(987654321, 4242, i) end, 3000, 1)
	truthy(d2 >= 6, "day1 index varies for a second big userId (current formula), got " .. d2)

	-- a small/legacy UserId must behave too (the reduction must not special-case big ids)
	local d3 = distinctIds(function(i) return passSeed(261, 7, i) end, 3000, 1)
	truthy(d3 >= 6, "day1 index varies for a small userId (current formula), got " .. d3)

	-- different sessions (different salts) must not walk the same anomaly sequence
	do
		local a, b, same = {}, {}, 0
		for i = 1, 200 do
			a[i] = Anomaly.rollPass(Rng.new(passSeed(1234567890, 11111, i)), Config, 1).anomalyId
			b[i] = Anomaly.rollPass(Rng.new(passSeed(1234567890, 22222, i)), Config, 1).anomalyId
			if a[i] == b[i] then same += 1 end
		end
		truthy(same < 160, "a different session salt gives a different sequence, matched " .. same .. "/200")
	end
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
