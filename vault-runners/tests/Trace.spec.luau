-- Trace — the server's own position for the runner. Run: luau tests/Trace.spec.luau
--
-- In Roblox the client owns its character's physics, so the server's `hrp.Position` is a CLAIM.
-- Vault Runners' whole economy is gems banked, and v1 decided both the pickup and the escape by
-- a plain distance test against that claim: writing the root part onto the exit pad banked a
-- full vault instantly, with no traversal at all.
--
-- Trace does not detect cheating; it removes what cheating was worth. Everything below is about
-- one property: NOTHING HAPPENS FASTER THAN A RUNNER COULD MAKE IT HAPPEN — and its mirror,
-- which matters just as much, that an honest runner is never slowed down by it.

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
local H, UP = Trace.speeds(C)
local DT = C.Run.TickSeconds

local function at(x, y, z) return { x = x, y = y, z = z } end
local function flat(a, b)
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

--============================================================================ the speeds

do
	near(H, C.Movement.WalkSpeed * C.Run.TrustedSpeedFactor, 1e-9,
		"the horizontal allowance is the game's own WalkSpeed plus tolerance")
	ok(H > C.Movement.WalkSpeed,
		"and it is STRICTLY faster than a runner walks, or honest play is throttled")

	-- The upward allowance has to beat the climb the countdown is derived from, or a runner who
	-- climbs the stair the vault gave them arrives above their own trusted position.
	local steps = math.floor(C.Vault.StoreyHeight / C.Vault.StepRise)
	local honest = C.Vault.StoreyHeight / (steps * C.Movement.ClimbSecondsPerStep)
	ok(UP > honest, string.format(
		"the upward allowance (%.2f studs/s) beats the modelled climb (%.2f studs/s)", UP, honest))
end

--============================================================================ an honest runner

-- Walking flat out, tick after tick, for a whole minute. Not one tick may be throttled, and the
-- trusted position must not fall behind: a guard that quietly costs the honest player a stud a
-- second is a guard that costs them the run.
do
	local t = Trace.new(C, at(0, 3, 0))
	local pos = at(0, 3, 0)
	for _ = 1, math.floor(60 / DT) do
		pos.x += C.Movement.WalkSpeed * DT
		Trace.step(t, pos, DT)
	end
	ok(t.throttled == 0, "a runner at exactly WalkSpeed is never throttled (" .. t.throttled .. ")")
	near(t.x, pos.x, 1e-6, "and the trusted position is exactly where they are")
end

-- The same, climbing the stair at the rate the vault's own geometry implies.
do
	local t = Trace.new(C, at(0, 3, 0))
	local pos = at(0, 3, 0)
	local steps = math.floor(C.Vault.StoreyHeight / C.Vault.StepRise)
	local rate = C.Vault.StoreyHeight / (steps * C.Movement.ClimbSecondsPerStep)
	for _ = 1, math.floor(30 / DT) do
		pos.y += rate * DT
		Trace.step(t, pos, DT)
	end
	ok(t.throttled == 0, "a runner climbing the stair is never throttled")
	near(t.y, pos.y, 1e-6, "and arrives on the storey they are actually standing on")
end

-- REPLICATION JITTER. A second of movement arriving in one tick is not a teleport, it is a
-- network. The banked allowance is what pays for it, and an honest player must not notice.
do
	local t = Trace.new(C, at(0, 3, 0))
	local pos = at(0, 3, 0)
	Trace.step(t, pos, 1.0)               -- a quiet second: the allowance banks
	pos.x += C.Movement.WalkSpeed * 1.0   -- ...then a second's worth of movement lands at once
	Trace.step(t, pos, DT)
	ok(t.throttled == 0, "a second of movement delivered in one tick is absorbed, not throttled")
	near(t.x, pos.x, 1e-6, "and the runner is credited with all of it")
end

--============================================================================ a claim nobody could make

-- THE EXPLOIT, as an assertion: the root part appears on the exit pad, five storeys up and a
-- vault away, one tick into the run.
do
	local t = Trace.new(C, at(0, 3, 0))
	local exit = at(100, 75, 60)
	local got = Trace.step(t, exit, DT)
	ok(t.throttled > 0, "the teleport is throttled")
	ok(flat(got, exit) > 100, string.format(
		"and the trusted position is still %.0f studs from the claim", flat(got, exit)))
	ok(got.y < 10, "still on the storey the runner was actually dropped into")

	-- ...and it never becomes free by repetition. Holding the claim for a whole minute of ticks
	-- moves the trusted position at the allowance and not one stud faster.
	local elapsed = 0
	for _ = 1, math.floor(60 / DT) do
		Trace.step(t, exit, DT)
		elapsed += DT
	end
	local travelled = math.sqrt((t.x) ^ 2 + (t.z) ^ 2)
	ok(travelled <= H * (elapsed + DT) + 1e-6, string.format(
		"holding a teleport for %.0fs moved the trusted position %.0f studs, no more than the %.0f allowed",
		elapsed, travelled, H * (elapsed + DT)))
end

-- ...and it does eventually ARRIVE. A guard that simply never lets anybody reach the exit would
-- pass every assertion above and would also be a broken game.
do
	local t = Trace.new(C, at(0, 3, 0))
	local exit = at(60, 3, 0)
	local ticks = 0
	while flat(t, exit) > 0.5 and ticks < 10000 do
		Trace.step(t, exit, DT)
		ticks += 1
	end
	ok(flat(t, exit) <= 0.5, "the trusted position does reach the claim in the end")
	local seconds = ticks * DT
	ok(seconds >= 60 / H - DT, string.format(
		"and took %.1fs to cover 60 studs — a walk, not a jump", seconds))
end

--============================================================================ falling is free

-- Losing height costs the runner and gains them nothing, and the collapse under them reads the
-- same number. A trusted position that lagged a fall would have runners killed by a plane that
-- is nowhere near them, and survivors standing in one that is.
do
	local t = Trace.new(C, at(0, 75, 0))
	local got = Trace.step(t, at(0, 3, 0), DT)
	near(got.y, 3, 1e-9, "a fall of 72 studs in one tick is followed exactly")
	ok(t.throttled == 0, "and is not throttled")
end

--============================================================================ degenerate input

-- `dt` comes from task.wait, which is virtual time under the emulator and wall time in Roblox.
-- Neither is guaranteed to hand back a sane number, and a NaN here would poison the trusted
-- position for the rest of the run — every comparison against it false, every rule silently off.
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

--============================================================================ CONTROL

-- A change the module must NOT notice. The trusted position is about distance and time; nothing
-- in it may depend on which vault the runner is in or what colour it is painted.
do
	local painted = {}
	for k, v in pairs(C) do painted[k] = v end
	painted.Hud = { AccentColor = { r = 255, g = 0, b = 255 },
		DangerColor = { r = 0, g = 255, b = 0 }, PanelColor = { r = 0, g = 0, b = 0 } }
	local a, b = Trace.speeds(C)
	local c, d = Trace.speeds(painted)
	near(c, a, 1e-12, "CONTROL: repainting the HUD does not change the horizontal allowance")
	near(d, b, 1e-12, "CONTROL: nor the upward one")
end

print(string.format("Trace: %d passed, %d failed", passed, failed))
if failed > 0 then error("Trace spec failed", 0) end
