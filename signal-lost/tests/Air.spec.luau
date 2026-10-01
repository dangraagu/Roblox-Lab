-- Air.spec — the suit's AIR, hypoxia and the blackout (DESIGN.md §2.3, §2.6), plus the hazard-eligibility
-- helper (§5.1 adaptation 1). The server owns all of this and ticks it every 0.1 s; the client only draws it.
-- Run: luau tests/Air.spec.luau
local Config = require("../src/shared/Config")
local Air = require("../src/shared/Air")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function approx(a, b, msg, tol)
	tol = tol or 1e-6
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function has(events, e)
	for _, x in events do if x == e then return true end end
	return false
end

local A = Config.Air

-- tank size from the Air Tank rank
eq(Air.tankFor(Config, 0), 20, "rank 0: 20 s")
eq(Air.tankFor(Config, 4), 40, "rank 4: 40 s")
eq(Air.tankFor(Config, 9), 40, "a rank past the max is clamped")
eq(Air.tankFor(Config, -2), 20, "a negative rank is clamped")

--================================================================ drain only in vacuum
do
	local s = Air.new(Config, 20)
	eq(s.air, 20, "a new suit is full")
	for _ = 1, 50 do Air.step(Config, s, 0.1, false) end
	eq(s.air, 20, "five seconds in air: still full")
	for _ = 1, 30 do Air.step(Config, s, 0.1, true) end
	approx(s.air, 17, "three seconds in vacuum drain three seconds of air")
	eq(s.hypoxia, 0, "and no hypoxia")
end

--================================================================ refill to full in RefillSeconds, any tank
for _, tank in { 20, 40 } do
	local s = Air.new(Config, tank)
	s.air = 0
	local t = 0
	while s.air < tank - 1e-9 and t < 10 do
		Air.step(Config, s, 0.1, false)
		t += 0.1
	end
	approx(t, A.RefillSeconds, "an empty " .. tank .. " s tank refills in RefillSeconds in air", 1e-6)
end

--================================================================ hypoxia and the grace
do
	local s = Air.new(Config, 20)
	s.air = 0.5
	local ev = Air.step(Config, s, 1.0, true)
	truthy(has(ev, "hypoxic"), "running out mid-tick enters hypoxia")
	approx(s.hypoxia, 0.5, "the overflow counts toward the grace")
	eq(s.air, 0, "air never goes below zero")
	local blackoutAt = nil
	local t = 1.0
	for _ = 1, 100 do
		t += 0.1
		local e = Air.step(Config, s, 0.1, true)
		if has(e, "blackout") then blackoutAt = t; break end
	end
	truthy(blackoutAt ~= nil, "staying in vacuum blacks out")
	approx(blackoutAt, 0.5 + A.GraceSeconds, "exactly GraceSeconds after the air ran out", 1e-6)
	truthy(s.blackedOut, "and says so")
	local again = Air.step(Config, s, 0.1, true)
	eq(#again, 0, "a blacked-out suit reports nothing more (one blackout, one settlement)")
end
do
	local s = Air.new(Config, 20)
	s.air = 0
	Air.step(Config, s, 3, true)
	approx(s.hypoxia, 3, "three seconds of hypoxia")
	local ev = Air.step(Config, s, 0.1, false)
	truthy(has(ev, "recovered"), "reaching air ends hypoxia at once")
	eq(s.hypoxia, 0, "the grace is reset")
	truthy(s.air > 0, "and the tank starts refilling the same tick")
end

--================================================================ canisters
do
	local s = Air.new(Config, 20)
	eq(Air.canister(Config, s), false, "a canister is NOT taken at a full tank")
	eq(s.air, 20, "and nothing changes")
	s.air = 4
	eq(Air.canister(Config, s), true, "at 4 s it is taken")
	approx(s.air, 14, "adds CanisterSeconds")
	s.air = 15
	Air.canister(Config, s)
	eq(s.air, 20, "capped at the tank")
	s.air = 0
	Air.step(Config, s, 2, true)
	truthy(s.hypoxia > 0, "set-up: hypoxic")
	eq(Air.canister(Config, s), true, "a hypoxic player takes a canister")
	eq(s.hypoxia, 0, "and it ends hypoxia at once")
	approx(s.air, A.CanisterSeconds, "with CanisterSeconds of air")
end

--================================================================ bad dt changes nothing
do
	local s = Air.new(Config, 20)
	s.air = 10
	for _, dt in { 0 / 0, -1, 0, math.huge, -math.huge } do
		local ev = Air.step(Config, s, dt, true)
		eq(#ev, 0, "dt " .. tostring(dt) .. ": no events")
	end
	eq(s.air, 10, "NaN, negative, zero and infinite dt change nothing")
end

--================================================================ fraction and seconds left
do
	local s = Air.new(Config, 40)
	s.air = 10
	approx(Air.fraction(s), 0.25, "fraction = air / tank")
	s.air = 0
	s.hypoxia = 2
	approx(Air.graceLeft(Config, s), 3, "grace left while hypoxic")
end

--================================================================ hazard eligibility (§5.1 adaptation 1)
do
	local function ok(vac, band, secs, air) return Air.hazardEligible(Config, vac, band, secs, air) end
	eq(ok(true, true, 10, 15), true, "vacuum, a hazard band, past the arrival grace, air >= 10: eligible")
	eq(ok(false, true, 10, 15), false, "never in an air module")
	eq(ok(true, false, 10, 15), false, "never in a band without hazards (the Docking Ring)")
	eq(ok(true, true, 5.9, 15), false, "never in the sector's first 6 s")
	eq(ok(true, true, 10, 9.99), false, "never below 10 s of air")
	eq(ok(true, true, 6, 10), true, "exactly at both edges: eligible")
	eq(ok(true, true, nil, 15), false, "not in a sector: not eligible")
end

--================================================================ REVIEW-1 finding 1: vacuum DISTANCE is charged too
-- AIR used to be charged by the module a server tick ENDED in. A client that writes its own position crossed a
-- 32-stud vacuum module between two ticks for 0-0.2 s of AIR instead of 2.7 s. vacuumCharge(s, dt, endsInVacuum,
-- vacStuds, vacSpeed) returns the vacuum seconds one tick costs: its time if it ended in vacuum, or the vacuum
-- distance the trusted path covered at the vacuum walk speed, whichever is more. Time already paid in this vacuum
-- stretch while covering less ground (a replication stall) covers a later burst, up to CreditSeconds.
local V = Config.Move.VacWalkSpeed
do
	local s = Air.new(Config, 20)
	approx(Air.vacuumCharge(Config, s, 0.1, true, V * 0.1, V), 0.1, "an honest tick in vacuum costs its time")
	approx(Air.vacuumCharge(Config, s, 0.1, true, 0, V), 0.1, "standing still in vacuum costs its time")
	approx(Air.vacuumCharge(Config, s, 0.1, false, 0, V), 0, "a tick in air costs nothing")
	local s2 = Air.new(Config, 20)
	approx(Air.vacuumCharge(Config, s2, 0.1, false, 32, V), 32 / V, "32 vacuum studs crossed between two ticks, air to air: what walking them costs (2.67 s)")
	local s3 = Air.new(Config, 20)
	approx(Air.vacuumCharge(Config, s3, 0.1, true, 16, V), 16 / V, "16 vacuum studs in one tick, ending in vacuum: 1.33 s, not 0.1")
	local s4 = Air.new(Config, 20)
	approx(Air.vacuumCharge(Config, s4, 0.1, true, V * 0.1 * 1.35, V), 0.135, "a 1.35x claim pays for its distance")
end
do -- a stall then a catch-up burst is not paid twice (up to CreditSeconds)
	local s = Air.new(Config, 20)
	local paid = 0
	for _ = 1, 5 do paid += Air.vacuumCharge(Config, s, 0.1, true, 0, V) end -- claims frozen 0.5 s in vacuum
	paid += Air.vacuumCharge(Config, s, 0.1, true, V * 0.6, V) -- then 0.6 s of walking arrives in one tick
	approx(paid, 0.6, "a 0.5 s stall plus the burst that catches up costs the 0.6 s actually spent")
	truthy(A.CreditSeconds > 0 and A.CreditSeconds <= 1, "the credit is at most 1 s (" .. tostring(A.CreditSeconds) .. ")")
	local long = Air.new(Config, 20)
	for _ = 1, 200 do Air.vacuumCharge(Config, long, 0.1, true, 0, V) end -- 20 s standing still
	approx(Air.vacuumCharge(Config, long, 0.1, true, 2 * V, V), 2 - A.CreditSeconds, "after a long stand, a 2 s burst still costs 2 s less only the capped credit")
	local out = Air.new(Config, 20)
	for _ = 1, 10 do Air.vacuumCharge(Config, out, 0.1, true, 0, V) end
	Air.vacuumCharge(Config, out, 0.1, false, 0, V) -- the stretch ends in air
	approx(Air.vacuumCharge(Config, out, 0.1, true, 2 * V, V), 2, "credit never outlives the vacuum stretch it was paid in")
end
do -- bad input charges what the tick's own time says, never NaN
	local s = Air.new(Config, 20)
	for _, bad in { 0 / 0, -5, math.huge } do
		approx(Air.vacuumCharge(Config, s, 0.1, true, bad, V), 0.1, "vacStuds " .. tostring(bad) .. ": the tick's time")
	end
	approx(Air.vacuumCharge(Config, s, 0.1, true, 5, 0), 0.1, "a zero speed charges no distance (no divide by zero)")
	approx(Air.vacuumCharge(Config, s, 0 / 0, true, 5, V), 0, "a NaN dt charges nothing")
end

--================================================================ reach: a script that writes its position gains nothing
-- The reviewer's rev_range on the real Trust + Air, the way the server ticks them: a straight corridor, every module
-- vacuum but the first, every hatch open. The honest walker claims V x 0.1 ahead each tick; the script claims
-- 1000 studs ahead each tick (the trust walks it at 1.35 x V, with a 3 s bank). Before the fix: 298.8 vs 452.2.
do
	local Trust = require("../src/shared/Trust")
	local n, S = 40, Config.Station.CellSize
	local function isOpen(a, b) return math.abs(a - b) == 1 and a <= n and b <= n end
	local function isVac(c) return c ~= 1 end
	local function reach(teleport, rank)
		local tank = Air.tankFor(Config, rank)
		local vs = V + (if rank > 0 then Config.Upgrades.Catalog.boots.per * rank else 0)
		local x0 = (0 - (n - 1) / 2) * S
		local t = Trust.new(Config, n, 1, x0, (0 - (n - 1) / 2) * S)
		local s = Air.new(Config, tank)
		for _ = 1, 40 do Trust.step(Config, t, x0, t.z, 0.1, Config.Move.AirWalkSpeed, isOpen, isVac) end -- banked in air
		local x = x0
		for _ = 1, 3000 do
			local inVac = isVac(t.cell)
			local speed = if inVac then vs else Config.Move.AirWalkSpeed
			x = if teleport then t.x + 1000 else x + speed * 0.1
			Trust.step(Config, t, x, t.z, 0.1, speed, isOpen, isVac)
			local endsVac = isVac(t.cell)
			local charge = Air.vacuumCharge(Config, s, 0.1, endsVac, t.vacStuds, vs)
			if charge > 0 then Air.step(Config, s, charge, true) end
			if not endsVac then Air.step(Config, s, 0.1, false) end
			if s.blackedOut then break end
		end
		return t.x - x0, tank, vs
	end
	for _, rank in { 0, 4 } do
		local honest, tank, vs = reach(false, rank)
		local script = reach(true, rank)
		-- the honest walker pays exactly what time-only charging made it pay: (tank + grace) x speed past the air half
		truthy(honest >= (tank + A.GraceSeconds) * vs + S / 2 - vs * 0.1 - 1e-6,
			string.format("rank %d: the honest walker's reach (%.1f) is what time-only charging gave it (%.1f, less one tick)", rank, honest, (tank + A.GraceSeconds) * vs + S / 2))
		truthy(script <= honest * 1.02 + A.CreditSeconds * V,
			string.format("rank %d: the script's vacuum reach (%.1f) is the honest walker's (%.1f), within 2%% and the credit", rank, script, honest))
		print(string.format("  reach before blackout, rank %d: honest %.1f studs, position-writing script %.1f studs", rank, honest, script))
	end
end

print(string.format("Air: %d passed, %d failed", passed, failed))
assert(failed == 0, "Air tests failed")
