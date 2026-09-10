-- Pure tests for whether the game can be PLAYED. Run: luau tests/Chase.spec.luau
--
-- Why this file exists. Every other spec in this directory asserts STRUCTURE — is it parented,
-- does the arithmetic round correctly, is the tree connected — and the headless check asserts
-- that the world arrived in the workspace. Neither can see whether a player who does a
-- reasonable thing survives, and an adversarial review proved it: `HuntSpeedMul 1.45 -> 5.0`
-- (a Nightwatcher moving at 55-100 studs/s against a player fixed at 16, i.e. an unavoidable
-- death every night) SURVIVED all 390 spec assertions and all 84 headless ones, and so did
-- `SightRange 55 -> 2000`. The builder's own report even listed retuning HuntSpeedMul as a
-- CONTROL — a change the suite was designed not to notice — which is exactly why an
-- un-outrunnable hunter shipped green.
--
-- So this file asserts OUTCOMES:
--   * the Nightwatcher can never move faster than the player, at any dread, with any upgrades,
--     and that stays true no matter how the speed constants are retuned;
--   * there is somewhere in the next room the watcher cannot see, so "break line of sight" is
--     a thing you can actually do;
--   * a player who is seen and runs away is not caught;
--   * the night is long enough to cross the manor it generates.
--
-- The simulation below drives the REAL modules with the REAL Config in the same order
-- src/server/Main.server.luau's stepNight drives them.
local Config = require("../src/shared/Config")
local Manor = require("../src/shared/Manor")
local Watcher = require("../src/shared/Watcher")
local Upgrades = require("../src/shared/Upgrades")
local Night = require("../src/shared/Night")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end

--=================================================== the player is part of the model, or nothing

-- The whole finding above exists because the player's speed was NOT in the model: the server
-- never set WalkSpeed, so the number the Nightwatcher was implicitly racing was Roblox's default
-- of 16 — a value no config knew, no test asserted and no retune could see.
local P = Config.Player
truthy(type(P) == "table", "Config declares a Player block, so the player's speed is data the game owns")
truthy(type(P) == "table" and type(P.WalkSpeed) == "number", "...including the walk speed the server sets on the Humanoid")

-- Roblox's own default, which is precisely what the player moves at while nothing sets it. Used
-- only so the assertions below still RUN (and still fail honestly) if the block above is gone.
local WALK = (type(P) == "table" and tonumber(P.WalkSpeed)) or 16

--=========================================== the Nightwatcher may never be faster than the player

-- Being seen has to be survivable. If the hunt speed ever reaches the player's speed then
-- "Break line of sight and keep moving" — the game's own on-screen advice — is a lie, because
-- breaking sight requires putting distance between you and something you cannot outpace.
do
	local U = Config.Upgrades
	local slows = { 0, U.MaxWatcherSlow } -- no Bear Traps at all is the worst case, and is free
	local worst, worstAt = -1, ""
	for _, slow in slows do
		for i = 0, 100 do
			local dread = i / 100
			for _, hunting in { false, true } do
				local s = Watcher.speed(Config, dread, slow, hunting)
				if s > worst then
					worst = s
					worstAt = string.format("dread %.2f, slow %.2f, hunting %s", dread, slow, tostring(hunting))
				end
			end
		end
	end
	print(string.format("  fastest the Nightwatcher ever moves: %.2f studs/s (%s) vs the player's %.2f", worst, worstAt, WALK))
	truthy(worst < WALK, string.format(
		"the Nightwatcher is never faster than the player (fastest %.2f at %s vs walk %.2f)", worst, worstAt, WALK))

	-- ...and by a margin big enough to be counterplay rather than arithmetic. A player who turns
	-- and runs has to gain a whole room's width over the hunt window, or the escape exists only
	-- on paper.
	local margin = WALK - worst
	local gainOverHunt = margin * Config.Watcher.HuntSeconds
	print(string.format("  a fleeing player gains %.2f studs/s -> %.1f studs over a %.0fs hunt", margin, gainOverHunt, Config.Watcher.HuntSeconds))
	truthy(gainOverHunt >= Config.Manor.RoomSize, string.format(
		"a fleeing player gains at least a room's width (%.1f studs) over one hunt", gainOverHunt))
end

-- The ceiling has to be a PROPERTY of the model, not an accident of today's constants. This is
-- the exact mutation that survived the whole suite; with the speed bound expressed against the
-- player it cannot come back at another value.
do
	local hostile = {}
	for k, v in Config do hostile[k] = v end
	local w = {}
	for k, v in Config.Watcher do w[k] = v end
	w.BaseSpeed = 55
	w.SpeedPerDread = 40
	w.HuntSpeedMul = 5.0
	hostile.Watcher = w

	local worst = -1
	for i = 0, 100 do
		local s = Watcher.speed(hostile, i / 100, 0, true)
		if s > worst then worst = s end
	end
	truthy(worst < WALK, string.format(
		"a hostile retune (BaseSpeed 55, SpeedPerDread 40, HuntSpeedMul 5.0) still cannot outrun the player (got %.2f)", worst))
end

--================================================================= there is somewhere to hide

-- Sight is the cone AND the room rule. The room rule alone bounds the watcher to its own room
-- and the ones next door; if SightRange covers that whole envelope then every linked room is a
-- death sentence and there is nowhere to break contact. `SightRange 55 -> 2000` survived the
-- entire suite for exactly this reason, so the property is asserted directly: standing in the
-- FAR corner of the room next door, with the watcher looking straight at you, must be unseen.
do
	local size = Config.Manor.RoomSize
	local half = size / 2
	local wx, wz = 0, 0 -- watcher at its room's centre, facing +X
	local nearX = size - half + 3 -- just inside the next room, right behind the doorway
	local farX = size + half - 3 -- the far wall of the next room
	local farZ = half - 3 -- and off to one side of it

	truthy(Watcher.sees(Config, wx, wz, 1, 0, nearX, 0), "the watcher sees you when you step into the room in front of it")
	falsy(Watcher.sees(Config, wx, wz, 1, 0, farX, farZ), "but NOT in the far corner of that room — that corner is the hiding place")

	-- Same statement as a number, so a retune of RoomSize is caught too.
	local farCorner = math.sqrt((size + half - 3) ^ 2 + (half - 3) ^ 2)
	truthy(Config.Watcher.SightRange < farCorner, string.format(
		"SightRange (%.0f) is shorter than the far corner of a linked room (%.1f)", Config.Watcher.SightRange, farCorner))
end

--=========================================================== a night, driven the way the server does

local function centreOf(plan: any, id: number): (number?, number?)
	local r = Manor.roomById(plan, id)
	if not r then
		return nil, nil
	end
	local x, z = Manor.roomCenter(Config, r)
	return x, z
end

-- Distance from a point to a segment. Used to model a player who will not run THROUGH the
-- Nightwatcher on the way to somewhere safer — without it the simulated player walks into it and
-- the run measures the bot rather than the game.
local function segDist(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 0 then
		t = math.max(0, math.min(1, ((px - ax) * dx + (pz - az) * dz) / len2))
	end
	local cx, cz = ax + dx * t, az + dz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

--=================================================== THE WALLS ARE REAL, AND THE PLAYER IS IN THEM
--
-- The first version of this file moved its player point-to-point with no collision at all: from a
-- room corner straight to the next room's centre, which crosses the WALL rather than the doorway
-- that `buildWall` actually leaves. It reported "a player who is seen and runs is never caught" on
-- 40 of 40 nights. An adversarial review re-ran the identical bot with one change — it may not
-- walk through a wall — and got 5 of 40 CAUGHT, in rooms of degree 2 and 3, at 1.6-2.2 seconds.
-- The claim was a property of the bot, not of the game.
--
-- So the geometry the server builds is modelled here, exactly:
--   * every edge of every occupied cell carries a wall, 1 stud thick, centred on the shared
--     plane (buildWall: `at = centre + dir * half`, segments of thickness 1);
--   * a shared edge between two LINKED rooms has a DoorWidth gap in the MIDDLE of it (two jambs
--     of (RoomSize - DoorWidth)/2 with the hole between them);
--   * everything else is solid.
-- The player is a CAPSULE, not a point: a Roblox character is about four studs across, so it
-- needs half of that clear on each side of it to fit through a doorway. Modelling it as a point
-- (which is what the review did) understates the problem by a factor of four — the same bot goes
-- from 5/40 caught to 19/40 once it has a body.
local PLAYER_RADIUS = 2

local function wallModel(plan: any)
	local M = Config.Manor
	local size, half = M.RoomSize, M.RoomSize / 2
	local cell: { [string]: number } = {}
	for _, r in plan.rooms do
		cell[r.gx .. "," .. r.gz] = r.id
	end
	-- Is a capsule of radius `rad` centred at (x, z) touching a wall?
	return function(x: number, z: number, rad: number): boolean
		local gx = math.floor(x / size + 0.5)
		local gz = math.floor(z / size + 0.5)
		for k = gx - 1, gx do -- the two X-facing planes this point can be near
			if math.abs(x - (k * size + half)) <= 0.5 + rad then
				local a, b = cell[k .. "," .. gz], cell[(k + 1) .. "," .. gz]
				if a ~= nil or b ~= nil then
					if not (a ~= nil and b ~= nil and Manor.linked(plan, a, b)) then
						return true -- solid wall, or the outside of the manor
					end
					if math.abs(z - gz * size) > M.DoorWidth / 2 - rad then
						return true -- a jamb, not the hole
					end
				end
			end
		end
		for m = gz - 1, gz do
			if math.abs(z - (m * size + half)) <= 0.5 + rad then
				local a, b = cell[gx .. "," .. m], cell[gx .. "," .. (m + 1)]
				if a ~= nil or b ~= nil then
					if not (a ~= nil and b ~= nil and Manor.linked(plan, a, b)) then
						return true
					end
					if math.abs(x - gx * size) > M.DoorWidth / 2 - rad then
						return true
					end
				end
			end
		end
		return false
	end
end

-- CONTROL for the collision model itself. A `blocked` that always answered false would silently
-- restore the wall-walking bot and every assertion below would go green again on a game that
-- cannot be played — which is exactly the failure this file exists to stop happening twice.
do
	local plan = Manor.plan(Rng.new(Manor.seedFor(Config, 3)), Config, 3)
	local blocked = wallModel(plan)
	local M = Config.Manor
	local foyer = Manor.roomById(plan, 1)
	local fx, fz = Manor.roomCenter(Config, foyer :: any)
	truthy(not blocked(fx, fz, PLAYER_RADIUS), "CONTROL: the middle of a room is walkable")

	-- Find a linked edge and a solid one on the same manor.
	local nbs = Manor.neighbours(plan, 1)
	truthy(#nbs > 0, "CONTROL: the foyer has a doorway")
	local doorX, doorZ = Manor.doorwayBetween(Config, plan, 1, nbs[1])
	truthy(doorX ~= nil, "CONTROL: that doorway has a position")
	if doorX then
		truthy(not blocked(doorX, doorZ :: number, PLAYER_RADIUS), "CONTROL: the middle of a doorway is walkable")
		-- One DoorWidth to the side of the same doorway is a JAMB, and a jamb is solid.
		local ax, az = doorX, doorZ :: number
		if math.abs(ax - fx) > math.abs(az - fz) then
			az += M.DoorWidth
		else
			ax += M.DoorWidth
		end
		truthy(blocked(ax, az, PLAYER_RADIUS), "CONTROL: the jamb beside that doorway is NOT walkable")
	end

	-- ...and an edge with nothing behind it at all is the outside wall of the manor.
	local outside = false
	for _, r in plan.rooms do
		local cx, cz = Manor.roomCenter(Config, r)
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			if Manor.roomAtWorld(plan, Config, cx + d[1] * M.RoomSize, cz + d[2] * M.RoomSize) == nil then
				if blocked(cx + d[1] * (M.RoomSize / 2), cz + d[2] * (M.RoomSize / 2), PLAYER_RADIUS) then
					outside = true
				end
			end
		end
	end
	truthy(outside, "CONTROL: the outside wall of the manor is NOT walkable")
end

-- Move toward (tx, tz) by at most `dist` studs, sliding on one axis when the other is blocked —
-- which is what a Roblox character does against a wall. Sub-stepped finely enough that a 1-stud
-- wall cannot be tunnelled through at 2 studs per tick.
local function walk(blocked: any, px: number, pz: number, tx: number, tz: number, dist: number): (number, number)
	local dx, dz = tx - px, tz - pz
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= 1e-9 then
		return px, pz
	end
	local ux, uz = dx / d, dz / d
	local want = math.min(dist, d)
	local moved = 0
	while moved < want - 1e-9 do
		local s = math.min(0.2, want - moved)
		if not blocked(px + ux * s, pz + uz * s, PLAYER_RADIUS) then
			px, pz = px + ux * s, pz + uz * s
		elseif not blocked(px + ux * s, pz, PLAYER_RADIUS) then
			px += ux * s
		elseif not blocked(px, pz + uz * s, PLAYER_RADIUS) then
			pz += uz * s
		else
			break -- flat against a wall; a real player would too, until they turn
		end
		moved += s
	end
	return px, pz
end

-- The manor is generated in its own local coordinates; the server adds the zone offset to both
-- the player and the watcher, and every test here is a difference of the two, so working at the
-- origin is exactly equivalent and much easier to read.
--
-- Tick order matches stepNight: the player has already moved by the time the server reads the
-- position, THEN sight is computed, THEN the watcher steps, THEN the catch test runs.
--
-- Three policies, and they measure three different claims:
--   "flee"  — a player who has been seen and is getting away. Picks the room next door that is
--             furthest from the Nightwatcher, walks to it THROUGH ITS DOORWAY, and does not
--             change its mind halfway through the door. It will not cross a line that passes
--             inside arm's length of the watcher. That is roughly the least a person does once
--             they know they are faster, so anything it survives, a person survives.
--   "loot"  — a player who pays the Nightwatcher no attention at all and just walks the greedy
--             full-clear route. This is the CONTROL on the whole retune: if the watcher stops
--             catching this player the game has no threat left in it.
--   "exit"  — straight out. Measures that the loop can be finished at all.
local function simulate(night: number, levels: any, policy: string, seconds: number?, ignoreCatch: boolean?)
	local effects = Upgrades.effects(Config, levels)
	local plan = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
	local blocked = wallModel(plan)
	local half = Config.Manor.RoomSize / 2

	local pts = {}
	for _, id in plan.patrol do
		local x, z = centreOf(plan, id)
		if x then table.insert(pts, { x = x, z = z }) end
	end
	if #pts == 0 then
		pts = { { x = 0, z = 0 } }
	end
	local points = Watcher.loopPoints(pts)
	local w = Watcher.newState(points)

	local ex, ez = centreOf(plan, plan.entranceId)
	local px, pz = ex :: number, (ez :: number) + 12 -- exactly where beginNight puts you
	local ambushed = false
	if policy == "ambush" then
		-- Walk straight into it: standing in its room, in its face, half a room away — the
		-- worst honest reading of "it has seen you", short of it already having you. Every
		-- night is then a real chase from tick one, rather than a run the patrol happened
		-- never to notice. (The closest possible case — turning and running from one stud
		-- outside the catch radius — is measured separately, in clean corridor geometry.)
		px = w.x + w.fx * half
		pz = w.z + w.fz * half
		if blocked(px, pz, PLAYER_RADIUS) then
			px, pz = w.x + w.fx * (half - 6), w.z + w.fz * (half - 6)
		end
		ambushed = true
		policy = "flee"
	end
	local dreadTotal = Night.dreadSeconds(Config, night, effects)
	local limit = math.min(seconds or dreadTotal, dreadTotal)
	local dt = Config.TickSeconds

	local t, everSpotted, spottedTicks = 0, false, 0
	local goal: number? = nil
	local dest: number? = nil
	local taken: { [number]: boolean } = {}
	local outside = 0
	while t < limit do
		local myRoom = Manor.roomAtWorld(plan, Config, px, pz)
		local wRoom = Manor.roomAtWorld(plan, Config, w.x, w.z)
		if myRoom == nil then
			outside += 1
		end

		-- taking whatever relic is standing in the room you are in the middle of
		if myRoom then
			local cx, cz = centreOf(plan, myRoom)
			if (px - (cx :: number)) ^ 2 + (pz - (cz :: number)) ^ 2 < 400 then
				for i, r in plan.relics do
					if r.roomId == myRoom then taken[i] = true end
				end
				if myRoom == plan.exitId and policy ~= "flee" then
					local all = true
					for i in plan.relics do
						if not taken[i] then all = false end
					end
					if policy == "exit" or all then
						local got = 0
						for _ in taken do got += 1 end
						return { caught = false, out = true, at = t, spotted = everSpotted,
							spottedTicks = spottedTicks, cleared = got, outside = outside, plan = plan }
					end
				end
			end
		end

		local tx: number?, tz: number? = nil, nil
		if myRoom and policy ~= "flee" then
			-- Somewhere to BE. Walk the room graph to the next objective, through doorways, and
			-- pay the Nightwatcher no attention whatsoever.
			if dest == nil or dest == myRoom then
				if policy == "exit" then
					dest = plan.exitId
				else
					local best, bestLen
					for i, r in plan.relics do
						if not taken[i] then
							local path = Manor.pathBetween(plan, myRoom, r.roomId)
							if path and (bestLen == nil or #path < bestLen) then best, bestLen = r.roomId, #path end
						end
					end
					dest = best or plan.exitId
				end
			end
			if dest == myRoom then
				tx, tz = centreOf(plan, myRoom)
			else
				local path = Manor.pathBetween(plan, myRoom, dest :: number)
				local nid = path and path[2]
				if nid then
					local dx0, dz0 = Manor.doorwayBetween(Config, plan, myRoom, nid)
					if dx0 and (px - dx0) ^ 2 + (pz - (dz0 :: number)) ^ 2 > 9 then
						tx, tz = dx0, dz0
					else
						tx, tz = centreOf(plan, nid)
					end
				end
			end
		elseif myRoom then
			local here = math.sqrt((px - w.x) ^ 2 + (pz - w.z) ^ 2)
			-- Never move closer to it than you already are, and never closer than arm's length.
			-- Starting inside that radius (an ambush) therefore relaxes the rule to "do not close
			-- the gap" rather than rejecting every direction there is.
			local clearOf = math.min(Config.Watcher.CatchRadius + 3, here)
			-- Where to aim for a given destination room: the DOORWAY until you are standing in it,
			-- then the middle of the room beyond. Without the second half the player parks in the
			-- doorway it is already in and waits to be collected. Nil when the approach would take
			-- it past the Nightwatcher.
			local function aimAt(g: number): (number?, number?)
				local ax: number?, az: number? = nil, nil
				if g == myRoom then
					local cx, cz = centreOf(plan, myRoom)
					local h = half - 8
					local bestD
					for _, o in { { -h, -h }, { h, -h }, { -h, h }, { h, h } } do
						local qx, qz = (cx :: number) + o[1], (cz :: number) + o[2]
						local d = (qx - w.x) ^ 2 + (qz - w.z) ^ 2
						if (bestD == nil or d > bestD) and segDist(w.x, w.z, px, pz, qx, qz) >= clearOf - 1e-6 then
							bestD, ax, az = d, qx, qz
						end
					end
					return ax, az
				end
				local dx0, dz0 = Manor.doorwayBetween(Config, plan, myRoom, g)
				if dx0 == nil then
					return nil, nil
				end
				ax, az = dx0, dz0
				if (px - (dx0 :: number)) ^ 2 + (pz - (dz0 :: number)) ^ 2 <= 9 then
					ax, az = centreOf(plan, g)
				end
				if ax == nil or segDist(w.x, w.z, px, pz, ax, az :: number) < clearOf - 1e-6 then
					return nil, nil
				end
				return ax, az
			end

			local keep = goal ~= nil and goal ~= wRoom
				and (goal == myRoom or Manor.linked(plan, myRoom, goal :: number))
			if keep then
				tx, tz = aimAt(goal :: number)
				keep = tx ~= nil
			end
			if not keep then
				goal = nil
				local bestD
				for _, nb in Manor.neighbours(plan, myRoom) do
					if nb ~= wRoom then
						local ax, az = aimAt(nb)
						if ax then
							local nx, nz = centreOf(plan, nb)
							local d = ((nx :: number) - w.x) ^ 2 + ((nz :: number) - w.z) ^ 2
							if bestD == nil or d > bestD then bestD, goal, tx, tz = d, nb, ax, az end
						end
					end
				end
				if goal == nil then
					goal = myRoom
					tx, tz = aimAt(myRoom)
					if tx == nil then -- boxed in: take the furthest corner there is and hope
						local cx, cz = centreOf(plan, myRoom)
						local h = half - 8
						local bd
						for _, o in { { -h, -h }, { h, -h }, { -h, h }, { h, h } } do
							local qx, qz = (cx :: number) + o[1], (cz :: number) + o[2]
							local d = (qx - w.x) ^ 2 + (qz - w.z) ^ 2
							if bd == nil or d > bd then bd, tx, tz = d, qx, qz end
						end
					end
				end
			end
		end
		if tx then
			px, pz = walk(blocked, px, pz, tx :: number, tz :: number, WALK * dt)
		end

		t += dt
		local dread = Watcher.dread(t, dreadTotal)
		myRoom = Manor.roomAtWorld(plan, Config, px, pz)
		wRoom = Manor.roomAtWorld(plan, Config, w.x, w.z)
		local roomOk = myRoom ~= nil and wRoom ~= nil
			and (myRoom == wRoom or Manor.linked(plan, wRoom :: number, myRoom :: number))
		local spotted = Watcher.spots(Config, w.x, w.z, w.fx, w.fz, px, pz, roomOk)

		local target
		if spotted and myRoom and wRoom then
			if myRoom == wRoom then
				target = { x = px, z = pz }
			else
				-- Exactly what stepNight does, including the doorway steering.
				local nx, nz = Manor.chaseStep(Config, plan, wRoom :: number, w.x, w.z, myRoom :: number)
				if nx then
					target = { x = nx, z = nz }
				else
					target = { x = px, z = pz }
				end
			end
		end
		if spotted then
			everSpotted = true
			spottedTicks += 1
		end

		Watcher.step(w, dt, {
			cfg = Config,
			points = points,
			dread = dread,
			watcherSlow = effects.watcherSlow,
			spotted = spotted,
			target = target,
		})

		if Watcher.caught(Config, w.x, w.z, px, pz) and not ignoreCatch then
			return { caught = true, at = t, spotted = everSpotted, spottedTicks = spottedTicks,
				ambushed = ambushed, room = myRoom, outside = outside, plan = plan }
		end
	end
	local got = 0
	for _ in taken do got += 1 end
	return { caught = false, at = limit, spotted = everSpotted, spottedTicks = spottedTicks,
		cleared = got, outside = outside, plan = plan }
end

--============================================== being seen has to be survivable, on every night

do
	local caughtOn, seenOn, outside = {}, 0, 0
	for night = 1, 20 do
		local r = simulate(night, {}, "ambush")
		if r.spotted then seenOn += 1 end
		outside += r.outside
		if r.caught then
			table.insert(caughtOn, string.format("night %d at %.1fs", night, r.at))
		end
	end
	print(string.format("  ambushed player, walls ON, nights 1-20, no upgrades: seen on %d, caught on %d", seenOn, #caughtOn))
	-- A run nothing ever sees proves nothing, so the sight itself is the control.
	eq(seenOn, 20, "CONTROL: walking into its face is seen on every one of the 20 nights (else this proves nothing)")
	-- ...and a run that leaves the building proves nothing either. A fleeing player that ends up
	-- outside every room in the plan has walked through a wall, which is the exact defect the
	-- collision model above exists to stop.
	eq(outside, 0, "CONTROL: the fleeing player is inside a real room on every tick of all 20 nights")
	eq(#caughtOn, 0, "a player who is seen and runs is never caught: " .. (next(caughtOn) and table.concat(caughtOn, ", ") or "none"))
end

-- The same with the Bear Traps that are supposed to HELP: an upgrade must never make it worse.
do
	local stacked = { beartraps = 5 }
	local caught = 0
	for night = 1, 20 do
		if simulate(night, stacked, "ambush").caught then caught += 1 end
	end
	eq(caught, 0, "and still never caught with a full Bear Trap stack")
end

-- ...and a player who just wanders the manor rather than being shoved into its face.
do
	local caught = 0
	for night = 1, 20 do
		if simulate(night, {}, "flee").caught then caught += 1 end
	end
	eq(caught, 0, "nor on an ordinary night that starts at the foyer")
end

--=============================== THE OTHER HALF: the Nightwatcher still has to be worth running from

-- Every assertion above says the player can get away. On its own that is also what a game with no
-- threat in it looks like, and the retune that made running work could just as easily have made
-- the Nightwatcher decorative. So: a player who walks the greedy full-clear route — legally,
-- through doorways, taking every relic — and pays the watcher NO attention at all has to be
-- caught on a serious fraction of nights. This is the assertion that fails if the hunter is ever
-- nerfed into furniture, and it is measured on the same geometry as the escapes.
do
	local caught, cleared = 0, 0
	for night = 1, 30 do
		local r = simulate(night, {}, "loot")
		if r.caught then caught += 1 elseif r.out then cleared += 1 end
	end
	print(string.format("  greedy full clear, ignoring the watcher: caught on %d of 30, cleared %d", caught, cleared))
	truthy(caught >= 10, string.format(
		"ignoring the Nightwatcher costs you the haul on at least a third of nights (got %d/30)", caught))
	truthy(cleared > 0, string.format("...but a full clear is still possible (got %d/30)", cleared))
end

-- ...and the loop can be FINISHED. The single most expensive defect this repo has shipped is a
-- core loop that was unreachable in the built world while every unit test stayed green, so this
-- asserts reachability the hard way: walk from the foyer to the Servants' Exit on foot, through
-- the real doorways, against the real wall geometry, inside the real night budget — on every
-- night. The catch test is switched OFF for this one, because what is being measured is whether
-- the manor can be WALKED, not whether the walk is safe. (How dangerous it is comes next.)
do
	local out, worst, worstNight = 0, 0, 0
	for night = 1, 30 do
		local r = simulate(night, {}, "exit", nil, true)
		if r.out then
			out += 1
			if r.at > worst then worst, worstNight = r.at, night end
		end
	end
	print(string.format("  walking to the exit through real doorways: reached it on %d of 30 (slowest: night %d, %.0fs)", out, worstNight, worst))
	eq(out, 30, "the Servants' Exit can be reached on foot, through real doorways, on every one of nights 1-30")
end

-- ...and it is not a stroll. The same walk WITH the catch test on: a player who beelines for the
-- exit and never once looks at the Nightwatcher still loses some of those nights, which is the
-- difference between an exit and a corridor.
do
	local out, caught = 0, 0
	for night = 1, 30 do
		local r = simulate(night, {}, "exit")
		if r.out then out += 1 elseif r.caught then caught += 1 end
	end
	print(string.format("  ...the same walk, watching for nothing: out %d of 30, caught %d", out, caught))
	truthy(out >= 20, string.format("most nights that walk still gets you out (got %d/30)", out))
	truthy(caught > 0, "CONTROL: and some of them do not — the exit run is not immune")
end


--=============================================== "break line of sight and keep moving", as a number

-- The advice the HUD gives when it sees you. Straight line, nothing else in the way, the player
-- turning and running from the closest range at which they are not already caught: the hunt has
-- to END before it runs out of hunt timer, or the advice is describing something that cannot
-- happen. Driven through the real Watcher.step so the hunt state machine is what is measured.
do
	local W = Config.Watcher
	local points = { { x = 0, z = 0 }, { x = 4000, z = 0 } } -- a very long corridor, so nothing wraps
	local w = Watcher.newState(Watcher.loopPoints(points))
	w.x, w.z, w.fx, w.fz = 0, 0, 1, 0
	local px = W.CatchRadius + 0.5 -- as close as it gets without having already taken you
	local dt = Config.TickSeconds
	local t, broke = 0, nil
	while t < W.HuntSeconds + 5 do
		px += WALK * dt
		t += dt
		local spotted = Watcher.sees(Config, w.x, w.z, w.fx, w.fz, px, 0)
		Watcher.step(w, dt, { cfg = Config, points = points, dread = 1, watcherSlow = 0, spotted = spotted, target = { x = px, z = 0 } })
		if not spotted and broke == nil then
			broke = t
		end
		if Watcher.caught(Config, w.x, w.z, px, 0) then
			break
		end
	end
	falsy(Watcher.caught(Config, w.x, w.z, px, 0), "running straight away from it at full dread is never caught")
	truthy(broke ~= nil, "and does break line of sight")
	if broke then
		print(string.format("  running straight away at full dread: out of sight after %.1fs", broke))
		truthy(broke <= W.HuntSeconds, string.format(
			"...within the hunt window, so the hunt actually ends (%.1fs vs %ds)", broke, W.HuntSeconds))
	end
end

--=========================================================== the manor has somewhere to run to

-- Speed is only half of it. Attachment-growth alone produced a TREE, every branch of which ends
-- in a one-door room, and a one-door room is a kill regardless of how much faster the player is:
-- measured at 55% of all rooms, and a fleeing player was still cornered on 3 of nights 1-20 after
-- the speeds were fixed. So the layout itself carries an assertion.
do
	local rooms, links, deadEnds, treeNights = 0, 0, 0, 0
	local NIGHTS = Config.Night.MaxNight -- the whole range the game can reach, not a sample of it
	for night = 1, NIGHTS do
		local plan = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
		rooms += #plan.rooms
		links += #plan.links
		if #plan.links <= #plan.rooms - 1 then
			treeNights += 1
		end
		for _, r in plan.rooms do
			if #Manor.neighbours(plan, r.id) <= 1 then
				deadEnds += 1
			end
		end
	end
	local frac = deadEnds / rooms
	print(string.format("  nights 1-%d: %.2f doorways per room, %d dead ends of %d rooms (%.1f%%), %d nights with no circuit at all",
		NIGHTS, links / rooms, deadEnds, rooms, frac * 100, treeNights))
	truthy(links > rooms, "the manor is a graph with circuits in it, not a tree of dead ends")
	truthy(frac < 0.05, string.format("dead ends are the exception, not the rule (%.1f%% of rooms)", frac * 100))
	eq(treeNights, 0, "no night is generated as a pure tree")
end

--=============================================== the night is long enough to cross the manor it built

-- The exit is always the DEEPEST room, so every night is a full crossing. If the crossing alone
-- eats the night, the tycoon half is a trap: you buy upgrades and the walk gets longer.
do
	local worstFrac, worstNight, unreachable = 0, 0, 0
	local NIGHTS = Config.Night.MaxNight
	for night = 1, NIGHTS do
		local plan = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
		local path = Manor.pathBetween(plan, plan.entranceId, plan.exitId)
		if path == nil then unreachable += 1 end
		if path then
			local crossing = (#path - 1) * Config.Manor.RoomSize
			local budget = Night.dreadSeconds(Config, night, Upgrades.effects(Config, {}))
			local frac = (crossing / WALK) / budget
			if frac > worstFrac then
				worstFrac, worstNight = frac, night
			end
		end
	end
	print(string.format("  nights 1-%d: worst crossing is night %d, %.1f%% of the night just walking to the exit",
		NIGHTS, worstNight, worstFrac * 100))
	-- One assertion per night would be 500 green ticks for one property; counted instead, so the
	-- pass total stays honest about how many DISTINCT things this file checks.
	eq(unreachable, 0, string.format("the exit is reachable from the foyer on every one of nights 1-%d", NIGHTS))
	truthy(worstFrac < 0.4, string.format(
		"crossing the manor never eats more than 40%% of the night (worst: night %d at %.1f%%)", worstNight, worstFrac * 100))
end

--=========================================================================================== done

print(string.format("Chase: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Chase spec failed", 0)
end
