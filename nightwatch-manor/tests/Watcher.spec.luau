-- Pure tests for Watcher (patrol movement, sight cone, hunt state, dread).
-- Run from the game directory: luau tests/Watcher.spec.luau
--
-- The Nightwatcher is the only threat in the game, so every way it can be broken is a way the
-- game has no horror in it: a sight cone that is always true (unplayable), always false (no
-- threat), a patrol that never advances, a hunt that never ends. All of it is plain numbers,
-- so all of it is checked here rather than by walking around a dark room in Studio.
local Watcher = require("../src/shared/Watcher")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local W = Config.Watcher

--=============================================================== the route (ping-pong loop)

do
	local pts = { { x = 0, z = 0 }, { x = 10, z = 0 }, { x = 10, z = 10 } }
	local loop = Watcher.loopPoints(pts)
	eq(#loop, 4, "a 3-point route ping-pongs into a 4-point closed loop")
	eq(loop[1].x, 0, "the loop starts where the route starts")
	eq(loop[4].x, 10, "the loop walks back along the route")
	eq(loop[4].z, 0, "...through the middle waypoint")

	-- Two points cannot ping-pong into anything shorter than there-and-back.
	local two = Watcher.loopPoints({ { x = 0, z = 0 }, { x = 5, z = 0 } })
	eq(#two, 2, "a 2-point route is already its own loop")
	-- A single waypoint is a legal (if dull) patrol and must not blow up.
	eq(#Watcher.loopPoints({ { x = 3, z = 4 } }), 1, "a 1-point route survives")

	approx(Watcher.pathLength(loop), 40, 1e-9, "the closed loop is 10+10+10+10 studs long")
	approx(Watcher.pathLength({ { x = 1, z = 1 } }), 0, 1e-9, "a 1-point loop has no length")
end

do
	local loop = Watcher.loopPoints({ { x = 0, z = 0 }, { x = 20, z = 0 } })
	local x, z, fx, fz = Watcher.positionAt(loop, 5)
	approx(x, 5, 1e-9, "positionAt walks along the first leg (x)")
	approx(z, 0, 1e-9, "positionAt walks along the first leg (z)")
	approx(fx, 1, 1e-9, "and faces the way it is walking")
	approx(fz, 0, 1e-9, "...with no sideways drift")

	local bx = Watcher.positionAt(loop, 25) -- 20 out, 5 back
	approx(bx, 15, 1e-9, "past the far end it walks back")

	local wx, wz = Watcher.positionAt(loop, 45) -- one full 40-stud lap + 5
	approx(wx, 5, 1e-9, "distance wraps at the end of the lap")
	approx(wz, 0, 1e-9, "...still on the route")

	-- Negative wraps too: 5 studs "before" the start is 5 studs short of finishing the lap,
	-- which on the way back is x = 5, not x = 15.
	local nx = Watcher.positionAt(loop, -5)
	approx(nx, 5, 1e-9, "a negative distance wraps instead of running off the end")

	-- Degenerate route: every query has to answer with the one point, not nan.
	local sx, sz = Watcher.positionAt({ { x = 7, z = 9 } }, 123)
	eq(sx, 7, "a 1-point loop always reports that point (x)")
	eq(sz, 9, "a 1-point loop always reports that point (z)")
end

do
	local loop = Watcher.loopPoints({ { x = 0, z = 0 }, { x = 20, z = 0 } })
	approx(Watcher.nearestDist(loop, 6, 3), 6, 1e-6, "nearestDist projects a point onto the route")
	local d = Watcher.nearestDist(loop, 100, 0)
	local px = Watcher.positionAt(loop, d)
	approx(px, 20, 1e-6, "a point past the end snaps to the end of the leg")
end

--================================================================================== dread

approx(Watcher.dread(0, 200), 0, 1e-9, "dread starts at 0")
approx(Watcher.dread(100, 200), 0.5, 1e-9, "dread is linear in elapsed time")
approx(Watcher.dread(200, 200), 1, 1e-9, "dread reaches 1 at the end of the night")
approx(Watcher.dread(9999, 200), 1, 1e-9, "dread clamps at 1")
approx(Watcher.dread(-5, 200), 0, 1e-9, "dread clamps at 0")
-- A zero-length night must read as fully woken, never as a division by zero.
eq(Watcher.dread(10, 0), 1, "a zero-length night is instantly at full dread")

--================================================================================== speed

do
	approx(Watcher.speed(Config, 0, 0, false), W.BaseSpeed, 1e-9, "at dread 0 it walks BaseSpeed")
	approx(Watcher.speed(Config, 1, 0, false), W.BaseSpeed + W.SpeedPerDread, 1e-9,
		"at dread 1 it has picked up the whole SpeedPerDread")
	truthy(Watcher.speed(Config, 0.5, 0, false) > Watcher.speed(Config, 0, 0, false),
		"speed rises with dread")
	truthy(Watcher.speed(Config, 0, 0.4, false) < Watcher.speed(Config, 0, 0, false),
		"bear traps slow it down")
	approx(Watcher.speed(Config, 0, 0, true), W.BaseSpeed * W.HuntSpeedMul, 1e-9,
		"hunting multiplies its speed")
	-- A slow of 1 (or more) must not stop it dead or reverse it: a watcher that cannot move is
	-- an upgrade that deletes the game.
	truthy(Watcher.speed(Config, 0, 1, false) > 0, "even a total slow leaves it moving")
	truthy(Watcher.speed(Config, 0, 5, false) > 0, "an over-large slow cannot reverse it")
end

--============================================================================== the sight cone

do
	-- Facing +X from the origin.
	truthy(Watcher.sees(Config, 0, 0, 1, 0, 20, 0), "it sees straight ahead")
	falsy(Watcher.sees(Config, 0, 0, 1, 0, -20, 0), "it does not see behind itself")
	falsy(Watcher.sees(Config, 0, 0, 1, 0, W.SightRange + 5, 0), "it does not see past SightRange")
	truthy(Watcher.sees(Config, 0, 0, 1, 0, W.SightRange - 1, 0), "it sees right up to SightRange")

	-- Cone edge: half-angle is 50 degrees, so 40 degrees off-axis is in and 60 is out.
	local r = 20
	local function at(deg)
		return r * math.cos(math.rad(deg)), r * math.sin(math.rad(deg))
	end
	local ix, iz = at(W.SightHalfAngleDeg - 10)
	local ox, oz = at(W.SightHalfAngleDeg + 10)
	truthy(Watcher.sees(Config, 0, 0, 1, 0, ix, iz), "inside the cone is seen")
	falsy(Watcher.sees(Config, 0, 0, 1, 0, ox, oz), "outside the cone is not")
	-- Symmetric in both directions, or one side of the hallway is safe and the other is not.
	truthy(Watcher.sees(Config, 0, 0, 1, 0, ix, -iz), "the cone is symmetric")
	falsy(Watcher.sees(Config, 0, 0, 1, 0, ox, -oz), "...on both sides")

	-- Standing on top of it: no facing can make that unseen, and it must not divide by zero.
	truthy(Watcher.sees(Config, 5, 5, 1, 0, 5, 5), "point blank is always seen")
	-- A zero facing vector (it has not moved yet) must not silently see everything.
	falsy(Watcher.sees(Config, 0, 0, 0, 0, 20, 0), "with no facing it sees nothing at range")
end

do
	-- spots() is sight AND the room rule: the server passes whether the player is in the
	-- watcher's room or a linked one, so walls block sight without a single raycast.
	truthy(Watcher.spots(Config, 0, 0, 1, 0, 20, 0, true), "in sight and in a reachable room -> spotted")
	falsy(Watcher.spots(Config, 0, 0, 1, 0, 20, 0, false), "in sight but two rooms away -> not spotted")
	falsy(Watcher.spots(Config, 0, 0, 1, 0, -20, 0, true), "same room but behind it -> not spotted")
end

do
	truthy(Watcher.caught(Config, 0, 0, W.CatchRadius - 1, 0), "inside the catch radius is caught")
	falsy(Watcher.caught(Config, 0, 0, W.CatchRadius + 1, 0), "outside it is not")
	-- Catching must not depend on facing: being grabbed from behind is the whole genre.
	truthy(Watcher.caught(Config, 0, 0, 0, -(W.CatchRadius - 1)), "it catches you from behind too")
end

do
	-- The Alarm Bell. `hears` is deliberately NOT the sight cone: the bell is what tells you
	-- something is close BEFORE it has line of sight, and with no bell bought (warnRange 0) it
	-- must never fire, or the upgrade would be granting an ability the player already had.
	falsy(Watcher.hears(0, 0, 0, 5, 0), "with no alarm bell you hear nothing")
	truthy(Watcher.hears(25, 0, 0, 20, 0), "a bought bell hears it inside its range")
	falsy(Watcher.hears(25, 0, 0, 30, 0), "and not outside it")
	truthy(Watcher.hears(25, 0, 0, 0, -24), "hearing does not care which way anything faces")
	truthy(Watcher.hears(25, 0, 0, 25, 0), "the boundary counts as heard")
	falsy(Watcher.hears(-5, 0, 0, 1, 0), "a negative range hears nothing rather than everything")
end

--============================================================================== the hunt

do
	local loop = Watcher.loopPoints({ { x = 0, z = 0 }, { x = 100, z = 0 } })
	local s = Watcher.newState(loop)
	eq(s.mode, "PATROL", "it starts on patrol")
	eq(s.huntLeft, 0, "with no hunt running")

	-- Patrolling: it advances along the route at its speed.
	Watcher.step(s, 1, { cfg = Config, points = loop, dread = 0, watcherSlow = 0, spotted = false })
	approx(s.x, W.BaseSpeed, 1e-6, "one second of patrol moves it BaseSpeed studs")
	eq(s.mode, "PATROL", "and it is still patrolling")

	-- Spotting flips it into a hunt and points it at the target room.
	Watcher.step(s, 1, { cfg = Config, points = loop, dread = 0, watcherSlow = 0, spotted = true,
		target = { x = s.x, z = 60 } })
	eq(s.mode, "HUNT", "being spotted starts a hunt")
	approx(s.huntLeft, W.HuntSeconds, 1e-6, "the hunt timer is full")
	truthy(s.z > 0, "and it has started moving toward the target")

	-- The hunt runs out on its own — otherwise one glance ends the night forever.
	local guard = 0
	while s.mode == "HUNT" and guard < 100 do
		Watcher.step(s, 1, { cfg = Config, points = loop, dread = 0, watcherSlow = 0, spotted = false })
		guard += 1
	end
	eq(s.mode, "PATROL", "the hunt ends when the timer runs out")
	truthy(guard <= math.ceil(W.HuntSeconds) + 1, "it gives up after about HuntSeconds (took " .. guard .. ")")

	-- ...and it rejoins the route where it actually is, not where it was when it left.
	local rx = Watcher.positionAt(loop, s.dist)
	approx(rx, s.x, 1.0, "it snaps back onto the nearest point of its route")
end

do
	-- Being spotted again refreshes the timer instead of stacking a second hunt.
	local loop = Watcher.loopPoints({ { x = 0, z = 0 }, { x = 100, z = 0 } })
	local s = Watcher.newState(loop)
	Watcher.step(s, 1, { cfg = Config, points = loop, dread = 0, watcherSlow = 0, spotted = true, target = { x = 50, z = 0 } })
	Watcher.step(s, 3, { cfg = Config, points = loop, dread = 0, watcherSlow = 0, spotted = false })
	local mid = s.huntLeft
	Watcher.step(s, 0, { cfg = Config, points = loop, dread = 0, watcherSlow = 0, spotted = true, target = { x = 50, z = 0 } })
	truthy(mid < W.HuntSeconds, "the timer really was ticking down")
	approx(s.huntLeft, W.HuntSeconds, 1e-6, "seeing you again refills it")
end

do
	-- A hunt with no target must not park the watcher forever: it keeps patrolling.
	local loop = Watcher.loopPoints({ { x = 0, z = 0 }, { x = 100, z = 0 } })
	local s = Watcher.newState(loop)
	s.mode, s.huntLeft = "HUNT", 5
	Watcher.step(s, 1, { cfg = Config, points = loop, dread = 0, watcherSlow = 0, spotted = false })
	truthy(s.x > 0, "a targetless hunt still moves")
end

do
	-- It must arrive, not orbit: stepping past the target lands ON it rather than overshooting.
	local loop = Watcher.loopPoints({ { x = 0, z = 0 }, { x = 100, z = 0 } })
	local s = Watcher.newState(loop)
	s.mode, s.huntLeft = "HUNT", 10
	Watcher.step(s, 10, { cfg = Config, points = loop, dread = 0, watcherSlow = 0, spotted = true,
		target = { x = 3, z = 0 } })
	approx(s.x, 3, 1e-6, "a long step toward a near target stops on it")
	approx(s.z, 0, 1e-6, "...exactly")
end

--============================================================================== CONTROL
-- A change the suite must NOT notice: HuntSpeedMul is a feel knob. Nudging it changes how fast
-- a chase closes, and nothing about the patrol geometry, the cone, the timers or the wrap.
-- If this block goes red, the assertions above are pinned to a tuning value instead of to
-- behaviour, and every balance pass will look like a regression.
do
	local before = Config.Watcher.HuntSpeedMul
	Config.Watcher.HuntSpeedMul = 2.5
	local loop = Watcher.loopPoints({ { x = 0, z = 0 }, { x = 20, z = 0 } })
	local x = Watcher.positionAt(loop, 5)
	local ok = math.abs(x - 5) < 1e-9
		and Watcher.sees(Config, 0, 0, 1, 0, 20, 0)
		and not Watcher.sees(Config, 0, 0, 1, 0, -20, 0)
		and math.abs(Watcher.dread(50, 100) - 0.5) < 1e-9
		and math.abs(Watcher.speed(Config, 0, 0, false) - W.BaseSpeed) < 1e-9
	Config.Watcher.HuntSpeedMul = before
	truthy(ok, "CONTROL: retuning HuntSpeedMul moves nothing but the chase speed")
end

print(string.format("Watcher: %d passed, %d failed", passed, failed))
if failed > 0 then error("Watcher tests failed") end
