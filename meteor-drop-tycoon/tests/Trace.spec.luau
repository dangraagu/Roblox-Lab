-- Trace — the server's own position for the collector. Run: luau tests/Trace.spec.luau
--
-- ADAPTED from vault-runners/tests/Trace.spec.luau (28 passed there). The horizontal cases are kept; only
-- the config fixture is rewritten (this game's Config.Trace instead of vault-runners' Movement / Run /
-- Vault blocks), the climb cases are replaced by the one vertical rule this game has (y follows the
-- claim both ways: a flat plot has no staircase to derive a climb rate from, and pickups are
-- horizontal), and the tolerance block is restated in this game's units (a pickup radius, a plot).
--
-- In Roblox the client owns its character's physics, so the server's `hrp.Position` is a CLAIM. Meteor
-- Drop Tycoon's whole economy is ore picked up by walking, and the Star Chart ranks the Beacon level that
-- ore buys: a pickup tested against the raw claim would let a teleporting client sweep a plot instantly.
-- Trace does not detect cheating; it removes what cheating was worth. NOTHING HAPPENS FASTER THAN A
-- PLAYER COULD MAKE IT HAPPEN, and an honest player is never slowed down by it.

local Config = require("../src/shared/Config")
local Trace = require("../src/shared/Trace")

local passed, failed = 0, 0
local function ok(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-6) then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end

local C = Config
local H = Trace.speeds(C)
local DT = C.Meteors.PollSeconds

local function at(x, y, z) return { x = x, y = y, z = z } end
local function flat(a, b)
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

--============================================================================ the speed

do
	near(H, C.Trace.WalkSpeed * C.Trace.TrustedSpeedFactor, 1e-9,
		"the horizontal allowance is the game's own WalkSpeed plus tolerance")
	ok(H > C.Trace.WalkSpeed, "and it is STRICTLY faster than a player walks, or honest play is throttled")
	near(H, 21.6, 1e-9, "21.6 studs/s, the number DESIGN.md section 12 states")
end

--============================================================================ an honest player

do
	local t = Trace.new(C, at(0, 3, -30))
	local pos = at(0, 3, -30)
	for _ = 1, math.floor(60 / DT) do
		pos.x += C.Trace.WalkSpeed * DT
		Trace.step(t, pos, DT)
	end
	ok(t.throttled == 0, "a player at exactly WalkSpeed is never throttled (" .. t.throttled .. ")")
	near(t.x, pos.x, 1e-6, "and the trusted position is exactly where they are")
end

-- REPLICATION JITTER. A second of movement arriving in one tick is not a teleport, it is a network.
do
	local t = Trace.new(C, at(0, 3, 0))
	local pos = at(0, 3, 0)
	Trace.step(t, pos, 1.0)
	pos.x += C.Trace.WalkSpeed * 1.0
	Trace.step(t, pos, DT)
	ok(t.throttled == 0, "a second of movement delivered in one tick is absorbed, not throttled")
	near(t.x, pos.x, 1e-6, "and the player is credited with all of it")
end

--============================================================================ a claim nobody could make

-- THE EXPLOIT: the root appears on the far rim of the plot, 60 studs away, one tick after spawning.
do
	local t = Trace.new(C, at(0, 3, -30))
	local far = at(0, 3, 30)
	local got = Trace.step(t, far, DT)
	ok(t.throttled > 0, "the teleport is throttled")
	ok(flat(got, far) > C.Meteors.PickupRadius, string.format(
		"and the trusted position is still %.0f studs from the claim, outside any pickup there", flat(got, far)))
	local elapsed = 0
	for _ = 1, math.floor(10 / DT) do
		Trace.step(t, at(1000, 3, 1000), DT)
		elapsed += DT
	end
	local travelled = flat(t, at(0, 3, -30))
	ok(travelled <= H * (elapsed + DT) + 1e-6, string.format(
		"holding a teleport for %.0fs moved the trusted position %.0f studs, no more than the %.0f allowed",
		elapsed, travelled, H * (elapsed + DT)))
end

-- ...and it does eventually ARRIVE. A guard that never lets anybody reach a meteor would pass every
-- assertion above and would also be a broken game.
do
	local t = Trace.new(C, at(0, 3, -30))
	local dest = at(0, 3, 30)
	local ticks = 0
	while flat(t, dest) > 0.5 and ticks < 10000 do
		Trace.step(t, dest, DT)
		ticks += 1
	end
	ok(flat(t, dest) <= 0.5, "the trusted position does reach the claim in the end")
	ok(ticks * DT >= 60 / H - DT, string.format("and took %.1fs to cover 60 studs: a walk, not a jump", ticks * DT))
end

--============================================================================ y follows the claim both ways

-- METEOR DROP TYCOON ADAPTATION. vault-runners limits the CLIMB (its storeys are the economy); here the
-- plot is flat, a knock lifts at most 15 studs/s, and every pickup test is horizontal, so height buys
-- nothing and the trusted height simply follows the claim, up and down.
do
	local t = Trace.new(C, at(0, 3, 0))
	local up = Trace.step(t, at(0, 40, 0), DT)
	near(up.y, 40, 1e-9, "a claim 37 studs up is followed exactly (height buys nothing here)")
	local down = Trace.step(t, at(0, 3, 0), DT)
	near(down.y, 3, 1e-9, "and so is one back down")
	ok(t.throttled == 0, "neither is a throttle")
end

--============================================================================ degenerate input

do
	local t = Trace.new(C, at(5, 3, 5))
	Trace.step(t, at(500, 300, 500), 0 / 0)
	ok(t.x == t.x and t.y == t.y and t.z == t.z, "a NaN dt does not poison the trusted position")
	near(t.x, 5, 1e-9, "and buys the claim no ground")
	Trace.step(t, at(500, 300, 500), -10)
	near(t.x, 5, 1e-9, "nor does a negative dt")
	Trace.step(t, at(500, 300, 500), "nonsense" :: any)
	near(t.x, 5, 1e-9, "nor a dt that is not a number at all")
end

--============================================================================ the tolerance is TIGHT, in this game's units

do
	-- The mean walk between two landing points is 29.90 studs (DESIGN.md [M1]). A teleport claim must
	-- still cost at least a walk's worth of trusted time: at most 1/1.35 of the honest walk is saved.
	local WALK = 29.9
	local t = Trace.new(C, at(0, 0, 0))
	local elapsed = 0
	while t.x < WALK and elapsed < 20 do
		Trace.step(t, at(WALK, 0, 0), 0.05)
		elapsed += 0.05
	end
	ok(elapsed >= (WALK / C.Trace.WalkSpeed) / 1.4, string.format(
		"a teleport claim crosses a mean meteor walk in %.2fs of trusted time, against %.2fs walking",
		elapsed, WALK / C.Trace.WalkSpeed))

	-- THE BANKED BURST, spent all at once after standing still. It is the largest instant displacement
	-- anybody can buy; bound it against the plot it happens on (72 studs across).
	local b = Trace.new(C, at(0, 0, 0))
	for _ = 1, 200 do Trace.step(b, at(0, 0, 0), 1) end
	Trace.step(b, at(100000, 0, 0), 0.05)
	ok(b.x <= 2 * C.World.PlotRadius, string.format(
		"standing still and then teleporting moves the TRUSTED position %.0f studs in one tick, at most one plot width",
		b.x))
	print(string.format("  tolerance: mean walk %.2fs (honest %.2fs), banked burst %.0f studs", elapsed,
		WALK / C.Trace.WalkSpeed, b.x))
end

--============================================================================ CONTROL

-- A change the module must NOT notice: the trusted position is distance and time; a repainted rarity
-- colour or a different store name is neither.
do
	local painted = {}
	for k, v in pairs(C) do painted[k] = v end
	painted.Save = { Store = "somewhere else" }
	painted.Rarities = { Order = {}, Defs = {} }
	near(Trace.speeds(painted), Trace.speeds(C), 1e-12, "CONTROL: repainting the rarities does not change the allowance")
end

print(string.format("Trace: %d passed, %d failed", passed, failed))
if failed > 0 then error("Trace spec failed", 0) end
