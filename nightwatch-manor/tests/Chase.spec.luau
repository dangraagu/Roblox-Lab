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

-- The manor is generated in its own local coordinates; the server adds the zone offset to both
-- the player and the watcher, and every test here is a difference of the two, so working at the
-- origin is exactly equivalent and much easier to read.
--
-- Tick order matches stepNight: the player has already moved by the time the server reads the
-- position, THEN sight is computed, THEN the watcher steps, THEN the catch test runs.
--
-- The simulated player is deliberately DIM: no pathfinding, no memory, no idea where the exit is
-- under the "flee" policy. Each tick it looks at the rooms next door and the corners of the one
-- it is in, throws away anything it would have to walk past the Nightwatcher to reach, and heads
-- for whatever is left that is furthest from it. That is roughly the least a real player does,
-- so anything it survives, a person survives.
local function simulate(night: number, levels: any, policy: string, seconds: number?)
	local effects = Upgrades.effects(Config, levels)
	local plan = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)

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
	if policy == "ambush" then
		-- Walk straight into it: standing in its room, in its face, half a room away — the
		-- worst honest reading of "it has seen you", short of it already having you. Every
		-- night is then a real chase from tick one, rather than a run the patrol happened
		-- never to notice. (The closest possible case — turning and running from one stud
		-- outside the catch radius — is measured separately, in clean corridor geometry.)
		px = w.x + w.fx * (Config.Manor.RoomSize / 2)
		pz = w.z + w.fz * (Config.Manor.RoomSize / 2)
		policy = "flee"
	end
	local dreadTotal = Night.dreadSeconds(Config, night, effects)
	local limit = math.min(seconds or dreadTotal, dreadTotal)
	local dt = Config.TickSeconds

	local t, everSpotted, spottedTicks = 0, false, 0
	while t < limit do
		local myRoom = Manor.roomAtWorld(plan, Config, px, pz)
		local wRoom = Manor.roomAtWorld(plan, Config, w.x, w.z)

		-- The player. FLEE: head for whichever reachable spot is furthest from the watcher, never
		-- into the room it is standing in and never along a line that passes close to it. EXIT:
		-- head along the shortest path to the way out.
		local tx, tz
		if myRoom then
			if policy == "exit" then
				local path = Manor.pathBetween(plan, myRoom, plan.exitId)
				local nextId = path and (path[2] or path[1])
				if nextId then
					tx, tz = centreOf(plan, nextId)
				end
			else
				local cands = {}
				for _, nb in Manor.neighbours(plan, myRoom) do
					if nb ~= wRoom then
						local nx, nz = centreOf(plan, nb)
						table.insert(cands, { nx :: number, nz :: number })
					end
				end
				local cx, cz = centreOf(plan, myRoom)
				local h = Config.Manor.RoomSize / 2 - 6 -- backing into a corner of this room
				for _, o in { { -h, -h }, { h, -h }, { -h, h }, { h, h } } do
					table.insert(cands, { (cx :: number) + o[1], (cz :: number) + o[2] })
				end

				-- Never move closer to it than you already are, and never closer than arm's
				-- length. Starting inside that radius (an ambush) therefore relaxes the rule to
				-- "do not close the gap" rather than rejecting every direction there is.
				local here = math.sqrt((px - w.x) ^ 2 + (pz - w.z) ^ 2)
				local clear = math.min(Config.Watcher.CatchRadius + 3, here)
				local bestD
				for _, c in cands do
					if segDist(w.x, w.z, px, pz, c[1], c[2]) >= clear - 1e-6 then
						local d = (c[1] - w.x) ^ 2 + (c[2] - w.z) ^ 2
						if bestD == nil or d > bestD then
							bestD, tx, tz = d, c[1], c[2]
						end
					end
				end
				if tx == nil then -- boxed in: take the furthest thing there is and hope
					for _, c in cands do
						local d = (c[1] - w.x) ^ 2 + (c[2] - w.z) ^ 2
						if bestD == nil or d > bestD then
							bestD, tx, tz = d, c[1], c[2]
						end
					end
				end
			end
		end
		if tx then
			local dx, dz = (tx :: number) - px, (tz :: number) - pz
			local d = math.sqrt(dx * dx + dz * dz)
			local stepD = WALK * dt
			if d > 1e-9 then
				if stepD >= d then
					px, pz = tx :: number, tz :: number
				else
					px += dx / d * stepD
					pz += dz / d * stepD
				end
			end
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
				local path = Manor.pathBetween(plan, wRoom :: number, myRoom :: number)
				local nextRoom = path and path[2] and Manor.roomById(plan, path[2])
				if nextRoom then
					local nx, nz = Manor.roomCenter(Config, nextRoom)
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

		if Watcher.caught(Config, w.x, w.z, px, pz) then
			return { caught = true, at = t, spotted = everSpotted, spottedTicks = spottedTicks, plan = plan }
		end
		if policy == "exit" and myRoom == plan.exitId then
			return { caught = false, out = true, at = t, spotted = everSpotted, spottedTicks = spottedTicks, plan = plan }
		end
	end
	return { caught = false, at = limit, spotted = everSpotted, spottedTicks = spottedTicks, plan = plan }
end

--============================================== being seen has to be survivable, on every night

do
	local caughtOn, seenOn = {}, 0
	for night = 1, 20 do
		local r = simulate(night, {}, "ambush")
		if r.spotted then seenOn += 1 end
		if r.caught then
			table.insert(caughtOn, string.format("night %d at %.1fs", night, r.at))
		end
	end
	print(string.format("  ambushed player, nights 1-20, no upgrades: seen on %d, caught on %d", seenOn, #caughtOn))
	-- A run nothing ever sees proves nothing, so the sight itself is the control.
	eq(seenOn, 20, "CONTROL: walking into its face is seen on every one of the 20 nights (else this proves nothing)")
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
	for night = 1, 60 do
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
	print(string.format("  nights 1-60: %.2f doorways per room, %d dead ends of %d rooms (%.1f%%), %d nights with no circuit at all",
		links / rooms, deadEnds, rooms, frac * 100, treeNights))
	truthy(links > rooms, "the manor is a graph with circuits in it, not a tree of dead ends")
	truthy(frac < 0.05, string.format("dead ends are the exception, not the rule (%.1f%% of rooms)", frac * 100))
	eq(treeNights, 0, "no night is generated as a pure tree")
end

--=============================================== the night is long enough to cross the manor it built

-- The exit is always the DEEPEST room, so every night is a full crossing. If the crossing alone
-- eats the night, the tycoon half is a trap: you buy upgrades and the walk gets longer.
do
	local worstFrac, worstNight = 0, 0
	for night = 1, 60 do
		local plan = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
		local path = Manor.pathBetween(plan, plan.entranceId, plan.exitId)
		truthy(path ~= nil, "night " .. night .. ": the exit is reachable from the foyer")
		if path then
			local walk = (#path - 1) * Config.Manor.RoomSize
			local budget = Night.dreadSeconds(Config, night, Upgrades.effects(Config, {}))
			local frac = (walk / WALK) / budget
			if frac > worstFrac then
				worstFrac, worstNight = frac, night
			end
		end
	end
	print(string.format("  worst crossing: night %d spends %.1f%% of the night just walking to the exit", worstNight, worstFrac * 100))
	truthy(worstFrac < 0.4, string.format(
		"crossing the manor never eats more than 40%% of the night (worst: night %d at %.1f%%)", worstNight, worstFrac * 100))
end

--=========================================================================================== done

print(string.format("Chase: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Chase spec failed", 0)
end
