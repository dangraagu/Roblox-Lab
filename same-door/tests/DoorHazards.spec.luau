-- Spec for DoorHazards: the day's three fork hazards. Run: luau tests/DoorHazards.spec.luau
--
-- Adapted from labyrint-spill/src/shared/CellHazards.luau (and its spec), not from +1 Jump's
-- Hazards.luau: that one launches a lane at the player from wherever the camera looks, on a random
-- clock, which would put luck into a ranked time on a shared layout (DESIGN §8). Four changes, each
-- pinned here or in Dungeon.spec:
--   1. WHERE comes from the day record (Dungeon.pickHazards), never from a hash of a public number;
--   2. forks only (Dungeon.spec asserts it for every minted day);
--   3. staggered slots: slot k impacts at First + Slot * (k - 1) + Cycle * n on the run clock, and a
--      hazard's warning + debris fit inside its slot, so NEVER two at once;
--   4. the ring is red and IS the hit zone: inside it you are hit, one hair outside you are not.
local DoorHazards = require("../src/shared/DoorHazards")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, msg, tol)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local cfg = Config.Hazards

--================================================================ validate
do
	local ok, err = DoorHazards.validate(cfg)
	truthy(ok, "the shipped hazard config validates (" .. tostring(err) .. ")")
end
local function mutated(key, value)
	local c = table.clone(cfg)
	c[key] = value
	return (DoorHazards.validate(c))
end
eq(mutated("WarnSeconds", 1.5), false, "a warning under 2 s is rejected (easy to see coming)")
eq(mutated("MinWarnSeconds", 1), false, "MinWarnSeconds itself cannot drop below 2 s")
eq(mutated("DebrisSeconds", 1.5), false, "warning + debris longer than a slot is rejected (two at once)")
eq(mutated("Cycle", 10), false, "a cycle shorter than Count slots is rejected (slots would overlap)")
eq(mutated("First", 2), false, "a first warning before the line is rejected")
eq(mutated("StrikeRadius", 3.5), false, "a ring that leaves no 1.5-stud lane beside it is rejected")
eq(mutated("KnockPush", 8), false, "a knock that carries more than MaxKnockDisplacement is rejected")
eq(mutated("MaxHitHeight", 8), false, "a hit height a jump could clear is rejected")
eq(mutated("CellSize", 9), false, "the cell size must be the game's 16")
eq(mutated("Count", nil), false, "a config without Count is rejected")

eq(DoorHazards.ringRadius(cfg), 4, "the ring (and the hit zone) is 2.5 + 1.5 = 4 studs")

--================================================================ timing on the run clock
approx(DoorHazards.impactTime(1, 0, cfg), 6, "slot 1 first impact 6 s after the line")
approx(DoorHazards.impactTime(2, 0, cfg), 10, "slot 2 at 10 s")
approx(DoorHazards.impactTime(3, 0, cfg), 14, "slot 3 at 14 s")
approx(DoorHazards.impactTime(1, 1, cfg), 18, "slot 1 again at 18 s (a 12 s cycle)")
approx(DoorHazards.nextImpact(2, 10.01, cfg), 22, "after an impact the next is a cycle later")
do
	local s, p = DoorHazards.stateAt(1, 2.99, cfg)
	eq(s, "idle", "before the first warning: idle")
	s, p = DoorHazards.stateAt(1, 3.0, cfg)
	eq(s, "warn", "the warning starts 3 s before the impact")
	approx(p, 0, "…at progress 0")
	s, p = DoorHazards.stateAt(1, 5.5, cfg)
	eq(s, "warn", "still warning half a second before")
	s, p = DoorHazards.stateAt(1, 6.4, cfg)
	eq(s, "debris", "debris right after the impact")
	s, p = DoorHazards.stateAt(1, 6.81, cfg)
	eq(s, "idle", "quiet after 0.8 s of debris")
	eq((DoorHazards.stateAt(1, 0 / 0, cfg)), "idle", "NaN time is idle")
end

do
	-- never two at once: sweep two minutes of run clock at 10 ms
	local worst = 0
	for k = 0, 12000 do
		local t = k / 100
		worst = math.max(worst, #DoorHazards.activeSlots(t, cfg))
	end
	eq(worst, 1, "over 120 s of run clock at most ONE hazard is ever warning or falling")
end

do
	local list = DoorHazards.impactsBetween(1, 0, 41, cfg)
	eq(#list, 3, "slot 1 impacts 3 times in (0, 41] (6, 18, 30)")
	eq(#DoorHazards.impactsBetween(1, 6, 18, cfg), 1, "(t0, t1] excludes t0, includes t1")
	eq(#DoorHazards.impactsBetween(1, 18, 6, cfg), 0, "a backwards window is empty")
end

--================================================================ the ring IS the hit zone
do
	local centre = { x = 100, y = 0, z = 100 }
	local function at(dx, dz, y) return { x = 100 + dx, y = y or 3, z = 100 + dz } end
	truthy(DoorHazards.checkHit(1, centre, 5.99, 6.01, at(3.99, 0), cfg), "3.99 studs from the centre, at the impact: hit")
	truthy(not DoorHazards.checkHit(1, centre, 5.99, 6.01, at(4.01, 0), cfg), "4.01 studs: stepping out of the ring dodged it")
	truthy(not DoorHazards.checkHit(1, centre, 5.0, 5.9, at(0, 0), cfg), "dead centre but not at an impact instant: no hit")
	truthy(DoorHazards.checkHit(1, centre, 5.99, 6.01, at(0, 0, 11.9), cfg), "a jump peak (11.9 over the floor) is still hit: a jump is no dodge")
	truthy(not DoorHazards.checkHit(1, centre, 5.99, 6.01, at(0, 0, 12.5), cfg), "above the height cap: no hit")
	-- a sweep around the ring: inside always hits, outside never does
	local wrong = 0
	for a = 0, 359, 3 do
		local r = math.rad(a)
		if not DoorHazards.checkHit(2, centre, 9.99, 10.01, at(math.cos(r) * 3.9, math.sin(r) * 3.9), cfg) then wrong += 1 end
		if DoorHazards.checkHit(2, centre, 9.99, 10.01, at(math.cos(r) * 4.1, math.sin(r) * 4.1), cfg) then wrong += 1 end
	end
	eq(wrong, 0, "all the way round, 3.9 hits and 4.1 does not")
	-- near-miss: an impact within 12 studs that did not hit
	truthy(DoorHazards.nearMiss(1, centre, 5.99, 6.01, at(8, 0), cfg), "an impact 8 studs away is a near-miss")
	truthy(not DoorHazards.nearMiss(1, centre, 5.99, 6.01, at(13, 0), cfg), "13 studs away is not")
	truthy(not DoorHazards.nearMiss(1, centre, 5.99, 6.01, at(2, 0), cfg), "a hit is not a near-miss")
end

--================================================================ a hit costs a little, never a run
do
	local vel, secs = DoorHazards.knock({ x = 0, y = 0, z = 0 }, { x = 3, y = 3, z = 0 }, cfg)
	approx(vel.x, 5, "pushed away from the impact at KnockPush")
	approx(vel.y, 0, "never up")
	approx(vel.z, 0, "horizontal")
	approx(secs, 0.8, "knocked down for 0.8 s")
	local v2 = DoorHazards.knock({ x = 0, y = 0, z = 0 }, { x = 0, y = 3, z = 0 }, cfg)
	approx(math.sqrt(v2.x * v2.x + v2.z * v2.z), 5, "dead centre still pushes somewhere, at KnockPush")
	truthy(cfg.KnockPush * cfg.KnockSeconds <= cfg.MaxKnockDisplacement, "the knock moves at most 4 studs")
end

eq(DoorHazards.kindFor(1, cfg), "stalactite", "the Cold Cellar drops stalactites")
eq(DoorHazards.kindFor(4, cfg), "ember bomb", "the Ember Vault drops ember bombs")
eq(DoorHazards.kindFor(99, cfg), "stalactite", "an unknown band falls back to the first kind")

print(string.format("DoorHazards: %d passed, %d failed", passed, failed))
if failed > 0 then error("DoorHazards spec failed", 0) end
