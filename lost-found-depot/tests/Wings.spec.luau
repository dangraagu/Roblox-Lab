-- Spec for Wings: the depot's progress value, its hazard lanes inside a walled bay, and what a BREAK is.
-- Run: luau tests/Wings.spec.luau
--
-- Lost & Found Depot is a timed sorting job, so three things differ from the +1 Jump template:
--   * PROGRESS is the career: shifts completed, plus the share of the RUNNING shift already cleared.
--     It comes from the server's State payload (never a timer), so a wing fades in while the player
--     sorts the last items of the shift before it;
--   * a hazard LANE must stay on the sorting floor: a lane that started behind a wall would fly
--     through it. Its start is pulled in along the lane and its speed scaled so the ARRIVAL TIME (the
--     warning) never shortens; after it passes the player it ends where it meets a wall;
--   * REST is a BREAK. The shift clock is the game, so a break may only START while the clock is not
--     running. Pressed mid-shift it is booked for the end of the shift; the first pickup ends a break.
--     Hazards run only while the clock runs, and a break freezes (never resets) the hazard clock.
local Wings = require("../src/shared/Wings")
local Rest = require("../src/shared/Rest")
local Hazards = require("../src/shared/Hazards")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b), "+/-", tol)
	end
end

--================================================================ progress

do
	eq(Wings.progress(nil), 0, "no state yet: progress 0")
	eq(Wings.progress({ loaded = false }), 0, "a state that has not loaded: progress 0")
	eq(Wings.progress({ loaded = true, shifts = 4 }), 4, "between shifts: the completed shifts")
	eq(Wings.progress({ loaded = true, shifts = 4, shift = { state = "ARMED", cleared = 0, total = 30 } }), 4,
		"a tray that is armed but not started adds nothing")
	near(Wings.progress({ loaded = true, shifts = 4, shift = { state = "RUNNING", cleared = 15, total = 30 } }), 4.5, 1e-9,
		"half of the running shift cleared: +0.5")
	eq(Wings.progress({ loaded = true, shifts = 5, shift = { state = "SUMMARY", cleared = 30, total = 30 } }), 5,
		"a finished shift is already counted in `shifts` (the server adds it at the summary): not twice")
	truthy(Wings.progress({ loaded = true, shifts = 4, shift = { state = "RUNNING", cleared = 30, total = 30 } }) <= 5,
		"a running shift can never read past the next whole shift")
	eq(Wings.progress({ loaded = true, shifts = 0 / 0 }), 0, "NaN shifts read as 0")
	eq(Wings.progress({ loaded = true, shifts = -3 }), 0, "negative shifts read as 0")
	eq(Wings.progress({ loaded = true, shifts = "7" }), 0, "a non-number reads as 0")
	eq(Wings.progress({ loaded = true, shifts = 2, shift = { state = "RUNNING", cleared = 5, total = 0 } }), 2,
		"a zero total cannot divide by zero")
	eq(Wings.completedShifts({ loaded = true, shifts = 12.9 }), 12, "the NAMED wing counts whole completed shifts")
	eq(Wings.completedShifts({ loaded = true, shifts = 12, shift = { state = "RUNNING", cleared = 29, total = 30 } }), 12,
		"sorting the last item of a shift does not rename the wing before the shift ends")
	eq(Wings.completedShifts(nil), 0, "no state: 0 completed shifts")
end

--================================================================ the sorting floor

local cfg = {
	Bay = { MinX = -36, MaxX = 36, MinZ = -36, MaxZ = 20 },
}
local OX = 180
local rect = Wings.bayRect(cfg, OX)
eq(rect.minX, OX - 36, "the floor starts at the left wall")
eq(rect.maxX, OX + 36, "and ends at the right wall")
eq(rect.minZ, -36, "back wall")
eq(rect.maxZ, 20, "front wall")
truthy(Wings.inRect(rect, { x = OX, y = 3, z = 0 }, 1), "the pick point is on the floor")
truthy(not Wings.inRect(rect, { x = OX, y = 3, z = -40 }, 1), "the Back Room corridor is not the sorting floor")
truthy(not Wings.inRect(rect, { x = OX + 35.5, y = 3, z = 0 }, 1), "a margin keeps a point off the wall")
truthy(not Wings.inRect(rect, { x = 0 / 0, y = 3, z = 0 }, 1), "NaN is nowhere")

-- room: the shortest lane the view window allows (the lane must be able to start on screen)
do
	local fromCentre = { x = OX, y = 3.5, z = -8 }
	-- facing -Z (yaw = pi: forward = (sin yaw, 0, cos yaw) = (0, 0, -1)), the back wall is 28 studs away
	local r = Wings.room(rect, fromCentre, math.pi, 0, 2)
	near(r, 26, 1e-6, "straight at the back wall: 28 studs to the wall less the 2-stud margin")
	local r35 = Wings.room(rect, fromCentre, math.pi, 35, 2)
	truthy(r35 <= r, "a wider window can only shorten the least room")
	near(r35, 26, 1e-6, "±35 degrees toward the back wall from the middle: the straight line is still the shortest")
	local nearWall = { x = OX, y = 3.5, z = -30 }
	truthy(Wings.room(rect, nearWall, math.pi, 35, 2) < 5, "a player 6 studs from the wall facing it has no room")
	eq(Wings.room(rect, { x = OX, y = 3.5, z = -40 }, math.pi, 35, 2), 0, "a player off the floor has no room at all")
end

-- clipLane: the start is pulled in along the lane, the arrival time is kept
do
	local HzCfg = {
		IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5, MaxRetargetSpeed = 1.5,
		ViewPitchDegrees = 20, SpreadDegrees = 35, KnockLift = 10, AimJitter = 0,
		Kinds = { trolley = { speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, knock = 26, pitch = 0 } },
	}
	local aim = { x = OX, y = 3.5, z = -20 }
	local plan = Hazards.plan(HzCfg, "trolley", aim, math.pi, function() return 0.5 end, -0.3)
	local rawLen = Hazards.distance(plan.start, plan.target)
	near(rawLen, 14 * 3.2, 1e-6, "the unclipped lane is speed x telegraph long")
	truthy(not Wings.inRect(rect, plan.start, 2), "CONTROL: this lane starts behind the back wall")
	local len = Wings.clipLane(plan, rect, 2)
	truthy(Wings.inRect(rect, plan.start, 2 - 1e-6), "after clipping the lane starts on the floor")
	near(len, Hazards.distance(plan.start, plan.target), 1e-6, "clipLane returns the new lane length")
	near(len, 14, 1e-6, "pulled in to 2 studs off the back wall (z -34): 14 studs from the aim")
	local arrive = Hazards.positionAt(plan, plan.arriveAt)
	near(Hazards.distance(arrive, plan.target), 0, 1e-6, "it still reaches the aim point at the SAME arrival time")
	eq(plan.arriveAt, 3.2, "the warning is not shortened")
	local speed = math.sqrt(plan.velocity.x ^ 2 + plan.velocity.y ^ 2 + plan.velocity.z ^ 2)
	near(speed, 14 / 3.2, 1e-6, "it rolls slower instead")
	truthy(speed <= plan.baseSpeed + 1e-9, "never faster than the kind's own speed")

	local plan2 = Hazards.plan(HzCfg, "trolley", { x = OX, y = 3.5, z = 12 }, math.pi, function() return 0.5 end, -0.3)
	local before = { x = plan2.start.x, y = plan2.start.y, z = plan2.start.z }
	local len2 = Wings.clipLane(plan2, rect, 2)
	near(len2, 14 * 3.2, 1e-6, "a lane that already starts on the floor is left alone")
	eq(plan2.start.z, before.z, "... its start does not move")

	-- endAtWall: after arrival, a hazard that leaves the floor ends its flight there
	local p3 = Hazards.plan(HzCfg, "trolley", { x = OX, y = 3.5, z = -20 }, 0, function() return 0.5 end, -0.3)
	-- yaw 0 faces +Z, so the lane starts toward the front and flies toward the back wall
	Wings.clipLane(p3, rect, 2)
	p3.t = p3.arriveAt - 0.1
	eq(Wings.endAtWall(p3, rect), false, "before arrival nothing ends")
	p3.t = p3.arriveAt + 0.5
	local pos = Hazards.positionAt(p3, p3.t)
	truthy(Wings.inRect(rect, pos, 0), "CONTROL: half a second after arrival it is still on the floor")
	eq(Wings.endAtWall(p3, rect), false, "so it keeps flying")
	p3.t = p3.arriveAt + 2.4
	truthy(not Wings.inRect(rect, Hazards.positionAt(p3, p3.t), 0), "CONTROL: 2.4 s after arrival it is past the back wall")
	eq(Wings.endAtWall(p3, rect), true, "a hazard past the wall ends")
	eq(p3.duration, p3.t, "... by ending its flight now (Hazards.step returns done next frame)")
end

-- groundLane: a trolley rolls on the floor, whatever the camera pitch bent the lane to
do
	local HzCfg = {
		IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5, MaxRetargetSpeed = 1.5,
		ViewPitchDegrees = 20, SpreadDegrees = 35, KnockLift = 10, AimJitter = 0,
		Kinds = { trolley = { speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, knock = 26, pitch = 0 } },
	}
	-- a camera looking UP 30 degrees: the view window [10, 50] bends the level trolley up to 10 degrees
	local plan = Hazards.plan(HzCfg, "trolley", { x = OX, y = 3, z = 0 }, math.pi, function() return 0.5 end, math.rad(30))
	truthy(plan.start.y > plan.target.y + 1, "CONTROL: looking up bends a level lane upward")
	Wings.groundLane(plan)
	eq(plan.start.y, plan.target.y, "groundLane puts the start on the target's height")
	eq(plan.velocity.y, 0, "and it rolls level")
	near(Hazards.distance(Hazards.positionAt(plan, plan.arriveAt), plan.target), 0, 1e-6, "arriving at the same place ...")
	eq(plan.arriveAt, 3.2, "... at the same time")
	local sp = math.sqrt(plan.velocity.x ^ 2 + plan.velocity.z ^ 2)
	truthy(sp <= plan.baseSpeed + 1e-9, "never faster than the kind")
end

--================================================================ fixtures are obstacles

-- A trolley must not roll through the tray or a bin crate. Wings.obstacles lists the bay's collidable
-- fixtures (tray, the six crates, the locker) as world boxes (oriented: the crates face the pick point)
-- grown by a margin; room, clipLane and endAtWall take the list, so a lane starts clear of them and a
-- flight ends where it meets one. The margin is 1.5 studs: a bin stand is 2 studs in front of its crate.
do
	local Layout = require("../src/shared/Layout")
	local Config = require("../src/shared/Config")
	local boxes = Wings.obstacles(Config, Layout, OX, 1.5)
	eq(#boxes, 8, "the tray, six crates and the locker")
	local function inAny(x, z)
		for _, b in boxes do if Wings.inObstacle(b, x, z) then return true end end
		return false
	end
	truthy(Wings.inObstacle(boxes[1], OX, 6.5), "box 1 covers the tray's centre")
	truthy(Wings.inObstacle(boxes[1], OX + 9.4, 6.5) and not Wings.inObstacle(boxes[1], OX + 9.6, 6.5), "the tray's box is its 16-stud width grown by 1.5")
	truthy(not inAny(OX, 0), "the pick point is clear of every obstacle")
	for arc = 1, 6 do
		local sx, sz = Layout.binStand(Config, arc)
		local cx, cz = Layout.binCentre(Config, arc)
		truthy(inAny(OX + cx, cz), "crate " .. arc .. " is an obstacle")
		truthy(not inAny(OX + sx, sz), "bin stand " .. arc .. " is clear of every obstacle (the grown crate stops 0.5 short of it)")
		-- the crate's corners are inside its (oriented) box, its stand side is not
		for _, c in Layout.binCorners(Config, arc) do
			truthy(inAny(OX + c[1] * 0.99 + cx * 0.01, c[2] * 0.99 + cz * 0.01), "crate " .. arc .. " corner is covered")
		end
	end
	truthy(not inAny(OX, 14), "the spawn pad is not an obstacle (1 stud tall: a hazard at root height passes over it)")

	-- room: from the pick point facing the tray (+Z, yaw 0) there is no room; facing the bins there is
	local P = { x = OX, y = 3, z = 0 }
	truthy(Wings.room(rect, P, 0, 35, 2, boxes) < 5, "facing the tray from the pick point: no room for a lane")
	truthy(Wings.room(rect, P, math.pi, 35, 2, boxes) >= 10, "facing the bins: room")
	truthy(Wings.room(rect, P, math.pi, 35, 2, boxes) <= Wings.room(rect, P, math.pi, 35, 2), "obstacles only ever shorten the room")

	-- clipLane with obstacles: a lane aimed at the pick point from behind the tray starts in front of it
	local HzCfg = {
		IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5, MaxRetargetSpeed = 1.5,
		ViewPitchDegrees = 20, SpreadDegrees = 35, KnockLift = 10, AimJitter = 0,
		Kinds = { trolley = { speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, knock = 26, pitch = 0 } },
	}
	local plan = Hazards.plan(HzCfg, "trolley", P, 0, function() return 0.5 end, -0.3)
	truthy(inAny(OX, 6.5) and plan.start.z > 9.5, "CONTROL: the raw lane starts beyond the tray")
	local len = Wings.clipLane(plan, rect, 2, boxes)
	truthy(math.abs(len - 2) < 1e-6, "clipped to the tray's grown near side (z 2): a 2-stud lane (" .. string.format("%.2f", len) .. ")")
	truthy(not inAny(plan.start.x, plan.start.z - 1e-6), "its start is not inside the tray")
	eq(plan.arriveAt, 3.2, "and its arrival time is kept")

	-- endAtWall with obstacles: a flight that reaches a crate after arrival ends there
	local sx, sz = Layout.binStand(Config, 3)
	local cx, cz = Layout.binCentre(Config, 3)
	local aim = { x = OX + sx, y = 3, z = sz }
	local yawToCrate = math.atan2(-(cx - sx), -(cz - sz)) -- the lane STARTS on the far side from the crate
	local p4 = Hazards.plan(HzCfg, "trolley", aim, yawToCrate, function() return 0.5 end, -0.3)
	Wings.clipLane(p4, rect, 2, boxes)
	local ended = false
	for k = 1, 60 do
		p4.t = p4.arriveAt + k * 0.05
		if p4.t > p4.duration then break end
		if Wings.endAtWall(p4, rect, boxes) then ended = true; break end
	end
	truthy(ended, "flying on past the player into crate 3 ends the flight at the crate")
	local hp = Hazards.positionAt(p4, p4.t)
	truthy(inAny(hp.x, hp.z), "... at the moment it enters the crate's box")

	-- REVIEW-2 finding 3: a player standing inside a fixture's margin (up against the tray to read its small
	-- tags, or against a crate) used to have that fixture ignored altogether (a ray that started inside a grown
	-- box skipped it), so 1384 of 1395 lanes launched at z 2.5 rolled straight through the tray and its items.
	-- A ray from inside the margin is stopped at once when it would enter the fixture itself; it is free only
	-- where it leads away from it. Swept like the reviewer: player x -7..7, z 2.0-3.4, camera yaw within 30
	-- degrees of the tray, the game's lanes (plan, groundLane, clipLane); a lane long enough to launch must
	-- never cross the fixture's own (ungrown) box.
	local core = Wings.obstacles(Config, Layout, OX, 0)
	local function crossesCore(plan)
		local s, t = plan.start, plan.target
		local n = math.max(2, math.ceil(Hazards.distance(s, t) / 0.25))
		for k = 0, n do
			local x, z = s.x + (t.x - s.x) * k / n, s.z + (t.z - s.z) * k / n
			for _, b in core do
				if Wings.inObstacle(b, x, z) then return true end
			end
		end
		return false
	end
	local seedT = 31
	local function randT() seedT = (seedT * 1103515245 + 12345) % 2147483648; return seedT / 2147483648 end
	local launches, through = 0, 0
	local HzReal = Config.Hazards
	for _, z in { 2.0, 2.5, 3.0, 3.4 } do
		for x = -7, 7, 0.5 do
			for yawDeg = -30, 30, 5 do
				local p = { x = OX + x, y = 3, z = z }
				local yaw = math.rad(yawDeg)
				if Wings.room(rect, p, yaw, HzReal.SpreadDegrees, HzReal.FloorMargin, boxes) >= HzReal.MinLaneStuds then
					local plan = Hazards.plan(HzReal, "trolley", p, yaw, randT, -0.3)
					Wings.groundLane(plan)
					if Wings.clipLane(plan, rect, HzReal.FloorMargin, boxes) >= HzReal.MinLaneStuds then
						launches += 1
						if crossesCore(plan) then through += 1 end
					end
				end
			end
		end
	end
	print(string.format("  a reader up against the tray, camera over it: %d launches, %d of them through the tray", launches, through))
	eq(through, 0, "no lane launched at a player up against the tray rolls through the tray")
	-- the same readers with the camera turned along the tray or away from it: lanes launch, none through it
	local launches2, through2 = 0, 0
	for _, z in { 2.0, 2.5, 3.0, 3.4 } do
		for x = -7, 7, 0.5 do
			for yawDeg = 60, 300, 15 do
				local p = { x = OX + x, y = 3, z = z }
				local yaw = math.rad(yawDeg)
				if Wings.room(rect, p, yaw, HzReal.SpreadDegrees, HzReal.FloorMargin, boxes) >= HzReal.MinLaneStuds then
					local plan = Hazards.plan(HzReal, "trolley", p, yaw, randT, -0.3)
					Wings.groundLane(plan)
					if Wings.clipLane(plan, rect, HzReal.FloorMargin, boxes) >= HzReal.MinLaneStuds then
						launches2 += 1
						if crossesCore(plan) then through2 += 1 end
					end
				end
			end
		end
	end
	print(string.format("  ... camera turned along or away from the tray: %d launches, %d through the tray", launches2, through2))
	truthy(launches2 >= 100, "CONTROL: a reader at the tray still gets hazards from the open floor (" .. launches2 .. ")")
	eq(through2, 0, "... and none of them rolls through the tray")
	local P25 = { x = OX + 1, y = 3, z = 2.8 }
	truthy(Wings.room(rect, P25, 0, 35, 2, boxes) < 1e-6, "0.7 studs from the tray, facing it: no room at all")
	truthy(Wings.room(rect, P25, math.pi, 35, 2, boxes) >= 10, "... facing away from it: room as before (the tray is behind)")
	local pl = Hazards.plan(HzReal, "trolley", P25, 0, function() return 0.5 end, -0.3)
	Wings.groundLane(pl)
	truthy(Wings.clipLane(pl, rect, 2, boxes) < 1e-6, "a lane from beyond the tray to that player is clipped to nothing (withdrawn)")
	-- the same up against a crate, and the locker
	for arc = 1, 6 do
		local sx, sz = Layout.binStand(Config, arc)
		local cx, cz = Layout.binCentre(Config, arc)
		local ux, uz = cx - sx, cz - sz
		local ul = math.sqrt(ux * ux + uz * uz)
		ux, uz = ux / ul, uz / ul
		-- the crate's near face is BinSize[3] / 2 from its centre along u: stand 0.7 studs from it
		local d = ul - Config.Bay.BinSize[3] / 2 - 0.7
		local q = { x = OX + sx + ux * d, y = 3, z = sz + uz * d }
		truthy(Wings.room(rect, q, math.atan2(ux, uz), 20, 2, boxes) < 1e-6, "0.7 studs from crate " .. arc .. ", facing it: no room")
	end
	local lk = { x = OX + Config.Bay.LockerCentre[1], y = 3, z = Config.Bay.LockerCentre[3] - Config.Bay.LockerSize[3] / 2 - 0.7 }
	truthy(Wings.room(rect, lk, 0, 20, 2, boxes) < 1e-6, "0.7 studs from the locker, facing it: no room")
	-- a player standing ON a fixture (the tray top): nothing launches at them
	truthy(Wings.room(rect, { x = OX, y = 6, z = 6.5 }, math.pi, 35, 2, boxes) < 1e-6, "a player standing on the tray: no room in any direction")
end

--================================================================ a lane locks before it can touch you

-- On a small floor a homing hazard can reach a player before its planned lock (a sorter walking toward
-- where it starts). lockNear locks the lane the moment the hazard comes within its reach plus `extra` of
-- the player: the ring turns red and stops following them, so the hazard can only ever hit a player who
-- stays inside a RED ring. With extra above the most a frame can close (a 22-stud/s walker and a hazard at
-- 1.5x its speed, 1/30 s), no hit can happen while the lane still follows the player.
do
	local HzCfg = {
		IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5, MaxRetargetSpeed = 1.5,
		ViewPitchDegrees = 20, SpreadDegrees = 35, KnockLift = 10, AimJitter = 0,
		Kinds = { trolley = { speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, knock = 26, pitch = 0 } },
	}
	local player = { x = OX, y = 3, z = 0 }
	local plan = Hazards.plan(HzCfg, "trolley", player, math.pi, function() return 0.5 end, -0.3)
	Wings.clipLane(plan, rect, 2)
	plan.t = 0.2
	eq(Wings.lockNear(plan, player, 1.5, 3), false, "far away: the lane keeps following")
	eq(plan.locked, false, "... unlocked")
	-- the player walks up to it: 7 studs from where it is now
	local hp = Hazards.positionAt(plan, plan.t)
	local close = { x = hp.x, y = 3, z = hp.z + 7 }
	eq(Wings.lockNear(plan, close, 1.5, 3), false, "7 studs is outside 1.8 + 1.5 + 3 = 6.3")
	local closer = { x = hp.x, y = 3, z = hp.z + 6 }
	eq(Wings.lockNear(plan, closer, 1.5, 3), true, "6 studs: it locks")
	eq(plan.locked, true, "the lane is locked (red)")
	eq(Hazards.retarget(HzCfg, plan, { x = OX + 10, y = 3, z = 5 }), false, "and no longer follows anyone")
	eq(Wings.lockNear(plan, closer, 1.5, 3), false, "locking twice reports nothing new")
	truthy(3 > (22 + 14 * 1.5) / 30, "extra 3 studs is more than one frame can close ((22 + 21) / 30 = 1.43)")
end

--================================================================ time to step out, even from a slow hazard

-- A lane fitted to the floor is SLOW, and a slow hazard touches a player well before it "arrives" at the
-- aim point (it only has to come within reach). The template's commit time (lock 1.5-2 s before arrival)
-- then leaves a player standing in the ring as little as 0.1 s between the ring turning red and the knock.
-- lockNear takes a reaction time: it also locks the moment the hazard is within reach + speed x react of
-- the player, so a player standing still always gets at least `react` seconds of red ring.
-- Property, sampled over every kind, fitted lanes, positions and view directions: for a player standing
-- still, (first hit) - (lock) >= react - one frame.
do
	local Config = require("../src/shared/Config")
	local Layout = require("../src/shared/Layout")
	local HzCfg = Config.Hazards
	local boxes = Wings.obstacles(Config, Layout, OX, HzCfg.ObstacleMargin)
	local seed = 4711
	local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
	local REACT = 1.0
	local DT = 1 / 30
	local worstRed, worstWarn, hitsSeen, locksSeen = math.huge, math.huge, 0, 0
	local kinds = {}
	for k in HzCfg.Kinds do table.insert(kinds, k) end
	table.sort(kinds)
	for trial = 1, 600 do
		local kind = kinds[1 + (trial % #kinds)]
		local player = { x = OX + (rand() - 0.5) * 50, y = 3, z = -30 + rand() * 45 }
		local yaw = rand() * 2 * math.pi
		local ok = Wings.inRect(rect, player, HzCfg.FloorMargin)
		for _, b in boxes do if ok and Wings.inObstacle(b, player.x, player.z) then ok = false end end
		if ok and Wings.room(rect, player, yaw, HzCfg.SpreadDegrees, HzCfg.FloorMargin, boxes) >= HzCfg.MinLaneStuds then
			local plan = Hazards.plan(HzCfg, kind, player, yaw, rand, math.rad(-20))
			if HzCfg.Kinds[kind].ground then Wings.groundLane(plan) end
			if Wings.clipLane(plan, rect, HzCfg.FloorMargin, boxes) >= HzCfg.MinLaneStuds then
				local lockedAt = nil
				local t = 0
				while t < plan.duration do
					local before = plan.t
					plan.t += DT
					t = plan.t
					Hazards.retarget(HzCfg, plan, player)
					Wings.lockNear(plan, player, HzCfg.PlayerRadius, HzCfg.LockExtraStuds, REACT)
					if plan.locked and lockedAt == nil then lockedAt = plan.t; locksSeen += 1 end
					if Hazards.checkHit(plan, before, plan.t, player, HzCfg.PlayerRadius) then
						plan.hit = true
						hitsSeen += 1
						worstRed = math.min(worstRed, plan.t - (lockedAt or plan.t))
						worstWarn = math.min(worstWarn, plan.t)
						break
					end
				end
			end
		end
	end
	print(string.format("  standing player: %d hits sampled; red ring at least %.2f s before the knock, warning at least %.2f s", hitsSeen, worstRed, worstWarn))
	truthy(hitsSeen >= 150, "CONTROL: most sampled hazards reach the player who stands still (" .. hitsSeen .. ")")
	truthy(worstRed >= REACT - DT - 1e-9, string.format("a player standing in the ring always gets %.1f s of red ring before the knock (worst %.2f)", REACT, worstRed))
	truthy(worstWarn >= 2.0 - 1e-9, string.format("and the warning comes at least 2 s before it, the promise (worst %.2f)", worstWarn))
	-- lockNear without a reaction time keeps the old rule (reach + extra)
	local p = Hazards.plan(HzCfg, "trolley", { x = OX, y = 3, z = 0 }, math.pi, function() return 0.5 end, -0.3)
	p.t = 0
	local hp = Hazards.positionAt(p, 0)
	local d = math.sqrt((hp.x - OX) ^ 2 + (hp.z - 0) ^ 2)
	local speed = math.sqrt(p.velocity.x ^ 2 + p.velocity.y ^ 2 + p.velocity.z ^ 2)
	local at = { x = hp.x, y = 3, z = hp.z + (p.hitRadius + 1.5 + math.max(3, speed * REACT) - 0.01) }
	eq(Wings.lockNear(p, at, 1.5, 3, nil), false, "no reaction time: a player reach + speed studs away does not lock the lane")
	eq(Wings.lockNear(p, at, 1.5, 3, REACT), true, "with 1 s of reaction time it does (reach + max(extra, speed x react))")
	truthy(d > 0, "CONTROL: the hazard is somewhere")
end

--================================================================ ... and for a player who MOVES: the hit rule

-- REVIEW-2 finding 1: a lane starts ahead of the camera, which for a walking sorter is where they are going.
-- A walker closes on a hazard at up to 36 studs/s, so with the plain ring rule they were knocked as little as
-- 0.13 s after the ring turned red and 0.40 s after the warning appeared. Wings.checkHit IS the knock:
-- Hazards.checkHit's ring rule (inside the ring AND within reach), and only once the player has been INSIDE
-- THE RED RING for minReact seconds without leaving it (counted from the ring turning red or from stepping
-- into it, whichever is later) and the warning has been up minWarn seconds. By construction, whatever the
-- player does. It is called every frame; `drive` below plays a hand-built lane frame by frame.
do
	local Config = require("../src/shared/Config")
	local HzCfg = Config.Hazards
	local REACT, WARN, DT, PR = 1.0, 2.0, 1 / 30, 1.5
	local player = { x = OX, y = 3, z = 0 }
	local off = { x = OX + 4, y = 3, z = 0 } -- 4 studs from the ring's centre: outside its 3.3 radius
	-- a lane straight down -Z through the player at 10 studs/s: start z = z0, within reach 3.3 of the player
	-- for t in [(z0 - 3.3) / 10, (z0 + 3.3) / 10]
	local function lane(z0, speed)
		speed = speed or 10
		return { kind = "trolley", start = { x = OX, y = 3, z = z0 }, velocity = { x = 0, y = 0, z = -speed },
			target = { x = OX, y = 3, z = 0 }, jitter = { x = 0, y = 0, z = 0 }, arriveAt = z0 / speed, duration = 8,
			hitRadius = 1.8, knock = 20, t = 0, hit = false, locked = false }
	end
	-- frame by frame from 0 to `upTo`; the lane locks at lockAt; inside(t) says where the player is; returns
	-- the knock's time or nil
	local function drive(plan, lockAt, inside, upTo)
		while plan.t < upTo - 1e-9 do
			local before = plan.t
			plan.t = math.min(upTo, plan.t + DT)
			if plan.t >= lockAt - 1e-9 then plan.locked = true end
			local at = if inside(plan.t) then player else off
			if Wings.checkHit(Hazards, plan, before, plan.t, at, PR, WARN, REACT) then
				plan.hit = true -- the caller marks it (Wings.client, SortModel)
				return plan.t
			end
		end
		return nil
	end
	local always = function() return true end

	local l1 = lane(30) -- within reach for t in [2.67, 3.33]
	eq(drive(l1, math.huge, always, 6), nil, "a lane that never turns red never knocks, however close it comes")
	local c1 = lane(30)
	c1.t = 2.9
	truthy(Hazards.checkHit(c1, 2.8, 2.9, player, PR), "CONTROL: the plain ring rule would have knocked that player")

	local l2 = lane(30)
	local k2 = drive(l2, 1.6, always, 6)
	truthy(k2 ~= nil and k2 >= 2.6 - 1e-6 and k2 <= 2.7 + 1e-6,
		"red at 1.6 s, standing in the ring throughout: knocked as the hazard arrives within reach at 2.67 s (" .. tostring(k2) .. ")")
	eq(Wings.checkHit(Hazards, l2, l2.t, l2.t + DT, player, PR, WARN, REACT), false, "a hazard knocks once")
	eq(l2.lockedAt ~= nil and math.abs(l2.lockedAt - 1.6) < DT, true, "noteLock recorded when the ring turned red")

	local l3 = lane(30)
	eq(drive(l3, 2.5, always, 6), nil,
		"red only at 2.5 s: by 3.5 s the hazard has passed (within reach until 3.33 s): a near-miss, never a late knock")

	local l4 = lane(30)
	eq(drive(l4, 0.5, function(t) return t >= 2.4 end, 6), nil,
		"red since 0.5 s, but the player only walked into the ring at 2.4 s: they get their full second, and it passes")
	local l5 = lane(30)
	local k5 = drive(l5, 0.5, function(t) return t >= 1.2 end, 6)
	truthy(k5 ~= nil and k5 >= 2.6 - 1e-9, "walked into it at 1.2 s and stayed: knocked, a second or more later (" .. tostring(k5) .. ")")
	local l6 = lane(35) -- within reach for t in [3.17, 3.83]
	local k6 = drive(l6, 0.5, function(t) return t < 2.0 or t >= 2.3 end, 8)
	truthy(k6 ~= nil and k6 >= 3.3 - DT - 1e-6 and k6 <= 3.4 + 1e-6, "out of the ring at 2.0 s, back in at 2.3 s: the second starts again (" .. tostring(k6) .. ")")
	local l6b = lane(35) -- within reach for t in [3.17, 3.83]
	local k6b = drive(l6b, 0.5, function(t) return t < 2.8 or t >= 3.0 end, 8)
	eq(k6b, nil, "... and stepping out and back just before it arrives dodges it: a second in the ring is what knocks")

	local l7 = lane(15) -- within reach for t in [1.17, 1.83]
	eq(drive(l7, 0.1, always, 6), nil, "red from 0.1 s, standing in it, but the hazard passes 1.83 s after the warning: never before 2 s")
	local l8 = lane(25) -- within reach for t in [2.17, 2.83]
	local k8 = drive(l8, 0.1, always, 6)
	truthy(k8 ~= nil and k8 >= 2.17 - 1e-6 and k8 <= 2.2 + 1e-6, "red from 0.1 s: knocked at 2.17 s, past both floors (" .. tostring(k8) .. ")")

	-- one long frame: only its part from the allowed moment counts
	local l9 = lane(25)
	l9.locked, l9.t = true, 1.0
	eq(Wings.checkHit(Hazards, l9, 0.9, 1.0, player, PR, WARN, REACT), false, "CONTROL: in the red ring at 1.0 s")
	l9.t = 2.4
	eq(Wings.checkHit(Hazards, l9, 1.0, 2.4, player, PR, WARN, REACT), true,
		"a long frame [1.0, 2.4]: from 2.0 on counts, and the hazard is within reach then")
	local l10 = lane(16) -- within reach for t in [1.27, 1.93]
	l10.locked, l10.t = true, 0.5
	Wings.checkHit(Hazards, l10, 0.4, 0.5, player, PR, WARN, REACT)
	l10.t = 2.2
	eq(Wings.checkHit(Hazards, l10, 0.5, 2.2, player, PR, WARN, REACT), false,
		"a long frame [0.5, 2.2] whose touch is all before 2.0: no knock (the early part is not counted)")
	local l11 = lane(30)
	eq(drive(l11, 0.5, function() return false end, 6), nil, "outside the ring the whole time: never (the ring rule still holds)")

	-- Property: players who move, on the game's own lanes. At a random moment in the first 3 s of the flight
	-- (from the launch frame on) the player walks at 16-22 studs/s straight AT the hazard (the worst case), away
	-- from it or across it, and half of them stop again 0.2-1.5 s later (at a bin stand, say) wherever that
	-- leaves them, often inside the ring. The lane is the game's (plan, groundLane, clipLane, retarget,
	-- lockNear). Every knock: >= WARN after the warning, >= REACT after red, and >= REACT after the player last
	-- stepped into the ring. CONTROL: the plain ring rule on the same lanes knocks some far sooner.
	local Layout = require("../src/shared/Layout")
	local boxes = Wings.obstacles(Config, Layout, OX, HzCfg.ObstacleMargin)
	local seed = 8080
	local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
	local kinds = {}
	for k in HzCfg.Kinds do table.insert(kinds, k) end
	table.sort(kinds)
	local function simulate(plan, spot, walkAt, speed, dirMode, stopAfter, plain)
		local pl = { x = spot.x, y = 3, z = spot.z }
		local vel, walkedAt, lockedAt, enteredAt, wasIn = nil, nil, nil, nil, false
		while plan.t < plan.duration do
			local before = plan.t
			plan.t += DT
			if vel == nil and plan.t >= walkAt then
				local h = Hazards.positionAt(plan, plan.t)
				local dx, dz = h.x - pl.x, h.z - pl.z
				local dl = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
				local ux, uz = dx / dl, dz / dl
				if dirMode == 2 then ux, uz = -ux, -uz elseif dirMode == 3 then ux, uz = -uz, ux end
				vel = { x = ux * speed, z = uz * speed }
				walkedAt = plan.t
			end
			if vel and stopAfter and plan.t >= walkedAt + stopAfter then vel = { x = 0, z = 0 } end
			if vel then pl = { x = pl.x + vel.x * DT, y = 3, z = pl.z + vel.z * DT } end
			Hazards.retarget(HzCfg, plan, pl)
			Wings.lockNear(plan, pl, PR, HzCfg.LockExtraStuds, REACT)
			if plan.locked and lockedAt == nil then lockedAt = plan.t end
			local isIn = plan.locked and Hazards.inZone(plan, pl, PR)
			if isIn and not wasIn then enteredAt = plan.t end
			wasIn = isIn
			local hit = if plain then Hazards.checkHit(plan, before, plan.t, pl, PR)
				else Wings.checkHit(Hazards, plan, before, plan.t, pl, PR, WARN, REACT)
			if hit then
				plan.hit = true
				return { warn = plan.t, red = plan.t - (lockedAt or plan.t), inRing = plan.t - (enteredAt or plan.t) }
			end
		end
		return nil
	end
	local hits, worstWarn, worstRed, worstIn, plainHits, plainWorstRed = 0, math.huge, math.huge, math.huge, 0, math.huge
	for trial = 1, 1200 do
		local kind = kinds[1 + (trial % #kinds)]
		local spot = { x = OX + (rand() - 0.5) * 50, y = 3, z = -30 + rand() * 45 }
		local yaw = rand() * 2 * math.pi
		local okSpot = Wings.inRect(rect, spot, HzCfg.FloorMargin)
		for _, b in boxes do if okSpot and Wings.inObstacle(b, spot.x, spot.z) then okSpot = false end end
		if okSpot and Wings.room(rect, spot, yaw, HzCfg.SpreadDegrees, HzCfg.FloorMargin, boxes) >= HzCfg.MinLaneStuds then
			local proto = Hazards.plan(HzCfg, kind, spot, yaw, rand, math.rad(-20))
			if HzCfg.Kinds[kind].ground then Wings.groundLane(proto) end
			if Wings.clipLane(proto, rect, HzCfg.FloorMargin, boxes) >= HzCfg.MinLaneStuds then
				local walkAt, speed, dirMode = 3 * rand(), 16 + 6 * rand(), 1 + math.floor(rand() * 3)
				local stopAfter = if rand() < 0.5 then 0.2 + 1.3 * rand() else nil
				local r = simulate(table.clone(proto), spot, walkAt, speed, dirMode, stopAfter, false)
				if r then
					hits += 1
					worstWarn, worstRed, worstIn = math.min(worstWarn, r.warn), math.min(worstRed, r.red), math.min(worstIn, r.inRing)
				end
				local rp = simulate(table.clone(proto), spot, walkAt, speed, dirMode, stopAfter, true)
				if rp then
					plainHits += 1
					plainWorstRed = math.min(plainWorstRed, rp.red)
				end
			end
		end
	end
	print(string.format("  players who move after the launch: %d knocks, each >= %.2f s after the warning, >= %.2f s after red, >= %.2f s after stepping into the ring (the plain ring rule: %d knocks, red as little as %.2f s)",
		hits, worstWarn, worstRed, worstIn, plainHits, plainWorstRed))
	truthy(hits >= 40, "CONTROL: players who stop in the ring are still knocked (" .. hits .. ")")
	truthy(plainWorstRed < 0.5, string.format("CONTROL: the plain ring rule knocks a moving player %.2f s after red", plainWorstRed))
	truthy(worstWarn >= WARN - 1e-9, string.format("every knock comes at least %.1f s after its warning (worst %.2f)", WARN, worstWarn))
	truthy(worstRed >= REACT - 1e-9, string.format("... at least %.1f s after its ring turned red (worst %.2f)", REACT, worstRed))
	truthy(worstIn >= REACT - DT - 1e-9, string.format("... and at least %.1f s (less a frame) after the player stepped into it (worst %.2f)", REACT, worstIn))
end

--================================================================ when a due hazard may launch

-- REVIEW-2 finding 2: on a phone an open HUD drawer or card covers the middle of the screen, exactly where
-- the warning banner and the hazard's marker would be. A DUE hazard waits while the screen is covered, and
-- (as before) while the player is off their own floor or the view has no room for a lane. Waiting keeps it
-- due with its clock running (Hazards.step with `grounded` false): a launch is delayed, never skipped.
do
	local function ctx(over)
		local c = { onFloor = true, roomy = true, covered = false }
		for k, v in over do c[k] = v end
		return c
	end
	eq(Wings.mayLaunch(ctx({})), true, "on the floor, room in view, nothing covering the screen: it may launch")
	eq(Wings.mayLaunch(ctx({ onFloor = false })), false, "off their own floor: no")
	eq(Wings.mayLaunch(ctx({ roomy = false })), false, "no room for a lane in view: no")
	eq(Wings.mayLaunch(ctx({ covered = true })), false, "a drawer or card over the middle of a phone screen: not while it is up")
	eq(Wings.mayLaunch({ onFloor = true, roomy = true }), true, "covered not reported: nothing covers the screen")
	eq(Wings.mayLaunch({ roomy = true }), false, "onFloor not reported: no")
end

--================================================================ a lane that cannot fit is withdrawn

-- Wings.room samples the view window; a lane's own heading and aim jitter can still clip it on a crate
-- corner. A launch whose fitted lane is shorter than MinLaneStuds is WITHDRAWN in the same frame, before
-- anything is drawn: the hazard stays due (it is not skipped, so the rarity does not change) and is tried
-- again when there is room.
do
	local HzCfg = {
		IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5, MaxRetargetSpeed = 1.5,
		ViewPitchDegrees = 20, SpreadDegrees = 35, KnockLift = 10, AimJitter = 0,
		Kinds = { trolley = { speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, knock = 26, pitch = 0 } },
	}
	local seed = 7
	local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
	local sch = Hazards.newScheduler(HzCfg, rand)
	sch.clock = sch.nextAt - 0.01
	local ctx = { resting = false, grounded = true, kinds = { "trolley" }, aim = { x = OX, y = 3, z = 0 }, yaw = math.pi, pitch = -0.3 }
	local ev = Hazards.step(sch, HzCfg, 0.1, ctx, rand)
	eq(ev and ev.type, "spawn", "CONTROL: a hazard launches")
	eq(sch.spawned, 1, "CONTROL: counted")
	Wings.withdraw(sch)
	eq(sch.active, nil, "withdrawn: nothing in the air")
	eq(sch.spawned, 0, "not counted")
	truthy(sch.clock >= sch.nextAt, "still due")
	local again = Hazards.step(sch, HzCfg, 0.1, ctx, rand)
	eq(again and again.type, "spawn", "the next frame with room launches it")
	eq(Wings.withdraw(sch), true, "withdraw reports it withdrew")
	eq(Wings.withdraw(sch), false, "and there is nothing left to withdraw")
end

--================================================================ no hazard outlives the shift

-- When the shift clock stops (the summary, the next tray armed), a hazard still in the air is taken away at
-- once: nothing can knock a player who has finished, and a break booked for the end of the shift starts
-- under a clear sky. It stays counted (it did launch), so it does not come back: the rarity is unchanged.
-- While the clock runs, nothing is taken away (rest never removes a hazard in flight either).
do
	local HzCfg = {
		IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5, MaxRetargetSpeed = 1.5,
		ViewPitchDegrees = 20, SpreadDegrees = 35, KnockLift = 10, AimJitter = 0,
		Kinds = { trolley = { speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, knock = 26, pitch = 0 } },
	}
	local seed = 5
	local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
	local sch = Hazards.newScheduler(HzCfg, rand)
	sch.clock = sch.nextAt - 0.01
	local ctx = { resting = false, grounded = true, kinds = { "trolley" }, aim = { x = OX, y = 3, z = 0 }, yaw = math.pi, pitch = -0.3 }
	local ev = Hazards.step(sch, HzCfg, 0.1, ctx, rand)
	eq(ev and ev.type, "spawn", "CONTROL: a hazard is in the air")
	local nextAt = sch.nextAt
	eq(Wings.endWithShift(sch, "RUNNING"), nil, "while the clock runs nothing is taken away")
	truthy(sch.active ~= nil, "... it is still in the air")
	local gone = Wings.endWithShift(sch, "SUMMARY")
	truthy(gone ~= nil and gone.kind == "trolley", "the shift ended: the hazard in the air is handed back to be hidden")
	eq(sch.active, nil, "... and nothing is in the air")
	eq(sch.spawned, 1, "it stays counted: it launched")
	eq(sch.nextAt, nextAt, "the next one is due exactly when it was")
	eq(Wings.endWithShift(sch, "ARMED"), nil, "nothing left to take away")
	eq(Wings.endWithShift(sch, nil), nil, "no state yet: nothing")
end

--================================================================ at most two wings' scenery at once

-- Normal play only ever blends two wings (a seam, or one jump: a join or a shift that ends). The scenery
-- budget assumes that, so the client keeps the weights of the two strongest wings and drops the rest: a
-- flurry of career jumps (dev teleports, the stress run) can never stack three wings of roofs and landmarks.
do
	local w = Wings.keepStrongest({ 0.6, 0.3, 0.1, 0, 0.005 }, 2)
	eq(w[1], 0.6, "the strongest stays")
	eq(w[2], 0.3, "the second stays")
	eq(w[3], 0, "the third goes")
	eq(w[4], 0, "zero stays zero")
	eq(w[5], 0, "a sliver goes")
	local same = Wings.keepStrongest({ 0.5, 0.5 }, 2)
	eq(same[1] + same[2], 1, "two wings are never touched")
	local tie = Wings.keepStrongest({ 0.2, 0.4, 0.4 }, 2)
	eq(tie[1], 0, "{0.2, 0.4, 0.4}: the weakest goes")
	eq(tie[2] + tie[3], 0.8, "... and the two strongest stay")
	local tie2 = Wings.keepStrongest({ 0.4, 0.4, 0.4 }, 2)
	local kept = 0
	for i = 1, 3 do if tie2[i] > 0 then kept += 1 end end
	eq(kept, 2, "a three-way tie keeps exactly two")
	local orig = { 0.1, 0.2, 0.3 }
	Wings.keepStrongest(orig, 2)
	eq(orig[1], 0.1, "the input is not changed")
end

--================================================================ the ring is shown as long as it can hit

-- A lane fitted to a small floor is slow, so a hazard can still be near its ring after it arrives. The ring
-- must stay on screen for as long as a hit inside it is possible: zoneLive is true before arrival, and after
-- it while the hazard is within ring radius + hitRadius + playerRadius of the ring's centre (past that it
-- flies straight away and can never touch anyone inside the ring again). Property, sampled: whenever
-- checkHit could be true for SOME player inside the zone, zoneLive is true.
do
	local HzCfg = {
		IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5, MaxRetargetSpeed = 1.5,
		ViewPitchDegrees = 20, SpreadDegrees = 35, KnockLift = 10, AimJitter = 0.8,
		Kinds = { trolley = { speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, knock = 26, pitch = 0 } },
	}
	local seed = 99
	local function rand() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
	local PR = 1.5
	local plan = Hazards.plan(HzCfg, "trolley", { x = OX, y = 3, z = -10 }, math.pi, rand, -0.3)
	Wings.clipLane(plan, rect, 2)
	plan.locked = true
	local zone = Hazards.zone(plan, PR)
	plan.t = plan.arriveAt - 0.2
	eq(Wings.zoneLive(plan, zone, PR), true, "before arrival: live")
	plan.t = plan.arriveAt + 0.05
	eq(Wings.zoneLive(plan, zone, PR), true, "just after arrival (the hazard is still in the ring): live")
	plan.t = plan.duration
	local far = Hazards.positionAt(plan, plan.t)
	truthy(math.sqrt((far.x - zone.x) ^ 2 + (far.z - zone.z) ^ 2) > zone.radius + plan.hitRadius + PR, "CONTROL: at the end of its flight it is far away")
	eq(Wings.zoneLive(plan, zone, PR), false, "... and the ring can go")

	local missed, samples = 0, 0
	for trial = 1, 300 do
		local p = Hazards.plan(HzCfg, "trolley", { x = OX + (rand() - 0.5) * 40, y = 3, z = -20 + rand() * 30 }, rand() * 6.28, rand, -0.3)
		Wings.clipLane(p, rect, 2)
		p.locked = true
		local z = Hazards.zone(p, PR)
		for k = 0, 60 do
			p.t = p.duration * k / 60
			-- 12 players spread over the zone
			for j = 0, 11 do
				local a = j * math.pi / 6
				local r = z.radius * (0.2 + 0.8 * ((j % 3) / 2))
				local pl = { x = z.x + math.cos(a) * r, y = 3, z = z.z + math.sin(a) * r }
				p.hit = false
				samples += 1
				if Hazards.checkHit(p, math.max(0, p.t - 1 / 30), p.t, pl, PR) and not Wings.zoneLive(p, z, PR) then
					missed += 1
				end
			end
		end
	end
	eq(missed, 0, string.format("a hidden ring never hides a hit (%d samples)", samples))
end

--================================================================ the roof never hides the job

-- The roofs, lamps and string lights hang over the bay at y >= 18 (two studs over the 16-stud walls).
-- A follow camera below the wall tops looks UP at them; a player who zooms out above the walls would
-- look DOWN through them at the tags, and a CanCollide = false roof never pulls the camera in. So the
-- overhead pieces fade with the CAMERA's height: fully shown at or below `Full`, gone at or above `Gone`,
-- eased between (never a cut when the zoom moves). Gone must sit below the lowest overhead part.
do
	local spec = { Full = 14.5, Gone = 17 }
	eq(Wings.overheadFade(4, spec), 1, "a camera at head height sees the whole roof")
	eq(Wings.overheadFade(14.5, spec), 1, "... up to Full")
	eq(Wings.overheadFade(17, spec), 0, "at Gone the roof is gone")
	eq(Wings.overheadFade(60, spec), 0, "a camera zoomed out far above the walls sees no roof")
	local mid = Wings.overheadFade(15.75, spec)
	truthy(mid > 0 and mid < 1, "between the two it is partly shown (" .. tostring(mid) .. ")")
	local worst, last, grew = 0, 1, 0
	for k = 0, 400 do
		local f = Wings.overheadFade(12 + k * 0.025, spec)
		if f > last + 1e-12 then grew += 1 end
		worst = math.max(worst, math.abs(f - last))
		last = f
	end
	eq(grew, 0, "it never grows as the camera rises (401 heights, 12 to 22 studs)")
	truthy(worst <= 0.05, string.format("a 0.025-stud zoom step never moves it by more than 0.05 (%.3f): no cut", worst))
	eq(Wings.overheadFade(0 / 0, spec), 0, "a NaN camera height shows no roof (never a roof in the way by accident)")
	eq(Wings.overheadFade(20, nil), 0, "no spec: above 17 nothing overhead")
	eq(Wings.overheadFade(4, nil), 1, "no spec: a low camera sees it")
	eq(Wings.overheadFade(16, { Full = 17, Gone = 14.5 }), 0, "a reversed spec fails safe: nothing overhead")
end

--================================================================ the break

local restCfg = { IdleSeconds = 20, RequireGrounded = true, BlockWhileThreat = true, WakeOnMove = true,
	WakeGraceSeconds = 0.4, PendingSeconds = 10 }
local STILL = { moving = false, grounded = true, threat = false }
local MOVING = { moving = true, grounded = true, threat = false }
local THREAT = { moving = false, grounded = true, threat = true }

eq(Wings.clockRunning("RUNNING"), true, "RUNNING is the only state whose clock runs")
for _, s in { "ARMED", "SUMMARY", "LOADING", "FREE", nil } do
	eq(Wings.clockRunning(s), false, "the clock does not run in " .. tostring(s))
end

-- between shifts: a break starts at once
do
	local b, r = Wings.newBreak(), Rest.new()
	eq(Wings.pressBreak(b, r, Rest, restCfg, "ARMED", STILL), "resting", "BREAK on an armed tray: resting at once")
	truthy(Rest.isResting(r) and r.source == "manual", "a manual rest")
	eq(Wings.hazardsMayRun(r, Rest, "ARMED"), false, "no hazards on a break")
	eq(Wings.pressBreak(b, r, Rest, restCfg, "ARMED", STILL), "stopped", "BREAK again ends it")
	truthy(not Rest.isResting(r), "... and it is over")
end

-- the first pickup ends a break: the clock is never held
do
	local b, r = Wings.newBreak(), Rest.new()
	Wings.pressBreak(b, r, Rest, restCfg, "SUMMARY", STILL)
	truthy(Rest.isResting(r), "CONTROL: on a break during the summary")
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.1, "ARMED", STILL), nil, "the next tray arming does not end it")
	truthy(Rest.isResting(r), "... still on the break")
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.1, "RUNNING", STILL), "clock",
		"a pickup (the server's clock is RUNNING) ends the break in the same frame, even standing still")
	truthy(not Rest.isResting(r), "... and it is over")
	eq(Wings.hazardsMayRun(r, Rest, "RUNNING"), true, "hazards run again with the clock")
end

-- mid-shift: a break can never start; it is booked for the end of the shift
do
	local b, r = Wings.newBreak(), Rest.new()
	for _, ctx in { STILL, MOVING, THREAT, { moving = false, grounded = false, threat = false } } do
		local res = Wings.pressBreak(b, r, Rest, restCfg, "RUNNING", ctx)
		truthy(res == "after_shift" or res == "cancelled", "BREAK mid-shift only books or un-books (" .. res .. ")")
		truthy(not Rest.isResting(r) and not r.pending, "... it never starts a rest or a Rest request")
	end
	-- four presses: booked, cancelled, booked, cancelled
	eq(b.afterShift, false, "an even number of presses leaves nothing booked")
	eq(Wings.pressBreak(b, r, Rest, restCfg, "RUNNING", STILL), "after_shift", "one more press books it")
	local events = 0
	for _ = 1, 600 do
		if Wings.updateBreak(b, r, Rest, restCfg, 1 / 60, "RUNNING", STILL) ~= nil then events += 1 end
	end
	eq(events, 0, "a booked break waits for the shift to end: 10 s mid-shift, no event")
	truthy(not Rest.isResting(r), "10 s of standing still mid-shift with a booked break: no manual rest")
	eq(Wings.hazardsMayRun(r, Rest, "RUNNING"), true, "and the hazards keep running")
	eq(Wings.updateBreak(b, r, Rest, restCfg, 1 / 60, "SUMMARY", STILL), "started", "the shift ends: the break starts")
	truthy(Rest.isResting(r) and r.source == "manual", "... a manual break")
	eq(b.afterShift, false, "and the booking is used up")
end

-- a booked break that ends while a hazard is still flying waits for it (Rest's queue)
do
	local b, r = Wings.newBreak(), Rest.new()
	Wings.pressBreak(b, r, Rest, restCfg, "RUNNING", STILL)
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.1, "SUMMARY", THREAT), "queued", "shift over, hazard in the air: queued")
	truthy(not Rest.isResting(r) and r.pending, "... pending in Rest")
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.1, "SUMMARY", STILL), "started", "the sky clears: it starts")
end

-- a pending request made between shifts is dropped when the clock starts
do
	local b, r = Wings.newBreak(), Rest.new()
	eq(Wings.pressBreak(b, r, Rest, restCfg, "ARMED", THREAT), "queued", "BREAK with a hazard still flying: queued")
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.1, "RUNNING", THREAT), "clock", "a pickup drops the pending request")
	truthy(not r.pending and not Rest.isResting(r), "... nothing left")
end

-- moving wakes (Rest's rule, kept)
do
	local b, r = Wings.newBreak(), Rest.new()
	Wings.pressBreak(b, r, Rest, restCfg, "ARMED", STILL)
	Wings.updateBreak(b, r, Rest, restCfg, 0.5, "ARMED", STILL)
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.1, "ARMED", MOVING), "woke", "walking off ends the break")
end

-- idle mid-shift freezes hazards only; the clock is the server's and keeps running
do
	local b, r = Wings.newBreak(), Rest.new()
	local ev
	for _ = 1, 21 * 10 do
		ev = Wings.updateBreak(b, r, Rest, restCfg, 0.1, "RUNNING", STILL) or ev
	end
	eq(ev, "started", "standing still 20 s mid-shift: idle rest (AFK safety)")
	eq(r.source, "idle", "... an idle one, not a break")
	eq(Wings.hazardsMayRun(r, Rest, "RUNNING"), false, "hazards leave an idle player alone")
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.1, "RUNNING", STILL), nil, "an idle rest is not ended by the running clock")
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.5, "RUNNING", MOVING), "woke", "moving ends it")
end

-- a booked break when an idle rest is already on: the break replaces it as a manual one
do
	local b, r = Wings.newBreak(), Rest.new()
	for _ = 1, 210 do Wings.updateBreak(b, r, Rest, restCfg, 0.1, "RUNNING", STILL) end
	truthy(Rest.isResting(r) and r.source == "idle", "CONTROL: idle mid-shift")
	eq(Wings.pressBreak(b, r, Rest, restCfg, "RUNNING", STILL), "stopped", "BREAK while idle ends the idle rest (it is a toggle)")
	eq(Wings.pressBreak(b, r, Rest, restCfg, "RUNNING", STILL), "after_shift", "and books the break")
	for _ = 1, 210 do Wings.updateBreak(b, r, Rest, restCfg, 0.1, "RUNNING", STILL) end
	truthy(Rest.isResting(r) and r.source == "idle", "idle again")
	eq(Wings.updateBreak(b, r, Rest, restCfg, 0.1, "SUMMARY", STILL), "started", "the shift ends: the booked break takes over")
	eq(r.source, "manual", "... as a manual break")
end

--================================================================ breaks never thin hazards out

-- The hazard scheduler, fed "may run" from Wings, over 6 h of RUNNING clock. A player who presses BREAK
-- all the time mid-shift, or goes idle often, must meet the same number of hazards per minute of
-- WORKING time (running clock, not resting) as one who never rests.
do
	local HzCfg = {
		IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5, MaxRetargetSpeed = 1.5,
		ViewPitchDegrees = 20, SpreadDegrees = 35, KnockLift = 10,
		Kinds = { trolley = { speed = 14, telegraph = 3.2, commit = 1.6, pass = 2.5, hitRadius = 1.8, knock = 26, pitch = 0 } },
	}
	local function run(mode)
		local seed = 12345
		local function rand()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local sch = Hazards.newScheduler(HzCfg, rand)
		local b, r = Wings.newBreak(), Rest.new()
		local working, dt = 0, 0.1
		local badLaunch = 0
		local t = 0
		while working < 6 * 3600 do
			t += dt
			-- a 150 s shift, then 20 s of summary and armed tray
			local cyc = t % 170
			local state = if cyc < 150 then "RUNNING" elseif cyc < 160 then "SUMMARY" else "ARMED"
			local ctx = STILL
			if mode == "toggler" and math.floor(t * 10) % 70 == 0 then
				Wings.pressBreak(b, r, Rest, restCfg, state, ctx)
			end
			if mode == "idler" then
				-- stands still 25 s of every 60 (reading), moves the rest
				ctx = if (t % 60) < 25 then STILL else MOVING
			elseif mode == "reader" then
				-- a phone player who keeps the MANUAL drawer open 25 s of every 60, moving (not idle)
				ctx = MOVING
			elseif mode ~= "toggler" then
				ctx = MOVING
			end
			Wings.updateBreak(b, r, Rest, restCfg, dt, state, ctx)
			local may = Wings.hazardsMayRun(r, Rest, state)
			if may then working += dt end
			local launchOk = Wings.mayLaunch({ onFloor = true, roomy = true, covered = mode == "reader" and (t % 60) < 25 })
			local ev = Hazards.step(sch, HzCfg, dt, { resting = not may, grounded = launchOk, kinds = { "trolley" },
				aim = { x = 0, y = 3, z = 0 }, yaw = 0, pitch = -0.3 }, rand)
			if ev and ev.type == "spawn" and not may then
				badLaunch += 1
			end
		end
		eq(badLaunch, 0, "a hazard only launches while hazards may run (" .. mode .. ")")
		return sch.spawned, working, t
	end
	local base, _, tb = run("never")
	local tog, _, tt = run("toggler")
	local idl, _, ti = run("idler")
	local rdr = run("reader")
	print(string.format("  break probe: never rests %d, presses BREAK every 7 s %d, idles 25 s of every 60 %d (6 h of working clock each; wall %.0f / %.0f / %.0f s)",
		base, tog, idl, tb, tt, ti))
	truthy(math.abs(tog - base) <= 1, "pressing BREAK over and over does not thin hazards per working minute")
	truthy(math.abs(idl - base) <= 1, "idling does not thin hazards per working minute")
	print(string.format("  a phone player with a drawer open 25 s of every 60 (launches wait while it is up): %d", rdr))
	truthy(rdr >= base * 0.95 and rdr <= base, "a covered screen delays a hazard, it does not skip it (within 5%)")
	truthy(base >= 6 * 3600 / 180 and base <= 6 * 3600 / 120 + 1, "and the count is inside the configured interval")
end

print(string.format("Wings: %d passed, %d failed", passed, failed))
