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

--============================================================================ the tolerance is TIGHT

-- REVIEW-2: "The anti-cheat's own tuning constants have NO test floor. Three mutations to
-- Config.Run's trusted-movement block survive the entire suite." TrustedSpeedFactor 1.35 -> 3.0,
-- TrustedClimbFactor 2.5 -> 10 and TrustedBurstSeconds 3 -> 60 were all green everywhere.
--
-- Everything above this line proves the throttle EXISTS. This block is what makes it TIGHT, and
-- it does so in the units the VAULT is built in — one maze cell step, one storey, one vault
-- footprint — rather than by restating the constants, so a legitimate re-tune inside these bounds
-- is free and a re-tune that hands the vault away is not.
do
	local CELL_STEP = C.Vault.CellSize * 2                       -- one maze move, wall to wall
	local STOREY = C.Vault.StoreyHeight
	local FOOTPRINT = (2 * C.Curve.MaxCells + 1) * C.Vault.CellSize

	-- How long the TRUSTED position takes to cross one cell step, when the claim is already
	-- there. Driven through Trace.step, so this measures the throttle rather than Trace.speeds.
	local t = Trace.new(C, at(0, 0, 0))
	local elapsed = 0
	while t.x < CELL_STEP and elapsed < 10 do
		Trace.step(t, at(CELL_STEP, 0, 0), 0.05)
		elapsed += 0.05
	end
	ok(elapsed >= 0.65, string.format(
		"a teleport claim crosses a maze cell in %.2fs of trusted time — a corridor is meant to "
			.. "cost about %.2fs at WalkSpeed, and the tolerance may not hand back a third of it",
		elapsed, CELL_STEP / C.Movement.WalkSpeed))

	-- ...and one storey of height. The honest climb is the spiral: 6 treads at ClimbSecondsPerStep.
	local u = Trace.new(C, at(0, 0, 0))
	local upTime = 0
	while u.y < STOREY and upTime < 20 do
		Trace.step(u, at(0, STOREY, 0), 0.05)
		upTime += 0.05
	end
	ok(upTime >= 1.8, string.format(
		"a teleport claim gains a whole storey in %.2fs of trusted time, against an honest climb "
			.. "of %.1fs — at that rate the collapse cannot catch anybody",
		upTime, math.floor(STOREY / C.Vault.StepRise) * C.Movement.ClimbSecondsPerStep))

	-- THE BANKED BURST IS THE ONE THAT IS SPENT ALL AT ONCE. A runner who stands still banks
	-- allowance, and the first claim after that is paid out of savings in a single tick. That is
	-- deliberate — it is what stops a replication stall reading as a teleport — but it is also the
	-- largest instant displacement anybody can buy, so it is bounded against the vault it happens
	-- inside rather than left to whatever TrustedBurstSeconds happens to be.
	local b = Trace.new(C, at(0, 0, 0))
	for _ = 1, 200 do Trace.step(b, at(0, 0, 0), 1) end       -- stand still, bank the lot
	Trace.step(b, at(100000, 0, 0), 0.05)
	ok(b.x <= 0.75 * FOOTPRINT, string.format(
		"standing still and then teleporting moves the TRUSTED position %.0f studs in one tick — "
			.. "%.0f%% of a %d-stud vault, bought without walking", b.x, 100 * b.x / FOOTPRINT, FOOTPRINT))

	local bu = Trace.new(C, at(0, 0, 0))
	for _ = 1, 200 do Trace.step(bu, at(0, 0, 0), 1) end
	Trace.step(bu, at(0, 100000, 0), 0.05)
	ok(bu.y <= 2 * STOREY, string.format(
		"...and %.0f studs upward, which is %.1f storeys of the climb skipped in one tick",
		bu.y, bu.y / STOREY))

	-- ...AND IN THE UNITS THE OBBY IS BUILT IN, because that is where somebody will reach for this
	-- module next. The climb shaft is one storey of crumbling pads; the banked burst above is
	-- MORE than one whole shaft of height, bought by standing still. So a client that lies about
	-- its position can skip a shaft, and the obby's difficulty must never have been resting on
	-- this file — it rests on the geometry (five studs of open air per hop) and on physics the
	-- server does not own. What is bounded here is only how much a liar gains, and the bound that
	-- matters is that they cannot buy the WHOLE climb in one go: they still have to keep lying,
	-- at a rate, for the length of the vault.
	local shaft = C.Vault.StoreyHeight
	local wholeVault = (C.Curve.MaxStoreys - 1) * shaft
	ok(bu.y < wholeVault, string.format(
		"one banked burst gains %.0f studs, the entire %.0f-stud climb of a full-size vault — the "
			.. "collapse would never see a cheating runner at all", bu.y, wholeVault))
	print(string.format("  tolerance: cell step %.2fs, storey %.2fs, banked burst %.0f studs flat / %.0f up",
		elapsed, upTime, b.x, bu.y))
	print(string.format("  DISCLOSED: that burst is %.2f climb shafts. A lying client skips one; an "
		.. "honest one hops six crumbling pads.", bu.y / shaft))
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
