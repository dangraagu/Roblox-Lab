-- NightModel.luau — the test-side model of a NIGHT and of a SESSION of nights. Never shipped.
--
-- Why it exists: the owner's brief sets targets in MINUTES OF PLAY ("the big milestone in about
-- 30-45 minutes", "about one near-hit per 2-3 minutes"), and the only honest way to put a night
-- number on a minute is to play the game's own rules forward. This file does that with the REAL
-- modules and the REAL Config:
--
--   * `simulate` is Chase.spec's night simulation, copied line for line (walls modelled exactly as
--     Main.server's buildWall builds them, a player with a 2-stud body, the watcher stepped in
--     stepNight's order). Pacing.spec first proves the copy still reproduces Chase.spec's printed
--     numbers, so the two cannot drift apart silently.
--   * It adds ONE policy, "normal": loot greedily, run when seen, leave when dread says so; plus
--     the human costs written down in Config.Pacing instead of hidden in a number.
--   * It adds the client's cosmetic hazards (Hazards + Nightfall.hazardClock, the same modules the
--     client runs), so the rarity the owner asked for is measured in minutes of PLAY, and so the
--     chase can be run with and without them.
--   * `session` plays nights back to back from a fresh profile: day overhead, upgrades bought
--     greedily, Night.resolve for the outcome, a caught night replayed more carefully.
--
-- Headless limits, stated: this is a bot, not a person (the same caveat Chase.spec prints). Its
-- numbers are a model's; when real session data exists, retune Config.Pacing first.

local Config = require("../src/shared/Config")
local Manor = require("../src/shared/Manor")
local Watcher = require("../src/shared/Watcher")
local Upgrades = require("../src/shared/Upgrades")
local Night = require("../src/shared/Night")
local Rng = require("../src/shared/Rng")
local Hazards = require("../src/shared/Hazards")
local Nightfall = require("../src/shared/Nightfall")

local NightModel = {}

local P = Config.Player
local WALK = (type(P) == "table" and tonumber(P.WalkSpeed)) or 16
local PLAYER_RADIUS = 2
NightModel.PLAYER_RADIUS = PLAYER_RADIUS
NightModel.WALK = WALK

local function centreOf(plan: any, id: number): (number?, number?)
	local r = Manor.roomById(plan, id)
	if not r then
		return nil, nil
	end
	local x, z = Manor.roomCenter(Config, r)
	return x, z
end

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

-- Chase.spec's wall model, verbatim: 1-stud walls on every cell edge, a DoorWidth gap in the middle
-- of a linked edge, everything else solid.
function NightModel.wallModel(plan: any)
	local M = Config.Manor
	local size, half = M.RoomSize, M.RoomSize / 2
	local cell: { [string]: number } = {}
	for _, r in plan.rooms do
		cell[r.gx .. "," .. r.gz] = r.id
	end
	return function(x: number, z: number, rad: number): boolean
		local gx = math.floor(x / size + 0.5)
		local gz = math.floor(z / size + 0.5)
		for k = gx - 1, gx do
			if math.abs(x - (k * size + half)) <= 0.5 + rad then
				local a, b = cell[k .. "," .. gz], cell[(k + 1) .. "," .. gz]
				if a ~= nil or b ~= nil then
					if not (a ~= nil and b ~= nil and Manor.linked(plan, a, b)) then
						return true
					end
					if math.abs(z - gz * size) > M.DoorWidth / 2 - rad then
						return true
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
			break
		end
		moved += s
	end
	return px, pz
end

-- A small deterministic generator (the model never uses the game's own Rng stream for hazards, so a
-- hazard never changes which manor gets built).
local function lcg(seed: number): () -> number
	local s = seed % 4294967296
	return function()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end
NightModel.lcg = lcg

-- One night.
--   policy: "flee" | "loot" | "exit" | "ambush" (Chase.spec's four, unchanged) | "normal"
--   opts (all optional):
--     seconds, ignoreCatch     -- as in Chase.spec
--     human = Config.Pacing.Profiles.<x>   -- only read by "normal"
--     wantRelics = n            -- "normal": relics to take before heading out (default: all)
--     hazards = { cfg = Config.Hazards, gate = Config.Env.HazardGate, bands = Config.Env.Bands,
--                 react = true|false, seed = n }
--       react = true : the player reads the ring and walks out of it (what the warning asks)
--       react = false: the player ignores every warning
-- Returns { caught, out, at, spotted, spottedTicks, cleared, outside, plan, hz = {...} }.
function NightModel.simulate(night: number, levels: any, policy: string, opts: any?)
	opts = opts or {}
	local seconds, ignoreCatch = opts.seconds, opts.ignoreCatch
	local effects = Upgrades.effects(Config, levels)
	local plan = Manor.plan(Rng.new(Manor.seedFor(Config, night)), Config, night)
	local blocked = NightModel.wallModel(plan)
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
	local px, pz = ex :: number, (ez :: number) + 12
	local ambushed = false
	local normal = policy == "normal"
	if policy == "ambush" then
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

	-- "normal": what a person does that the bots do not
	local human = opts.human or (Config.Pacing and Config.Pacing.Profiles and Config.Pacing.Profiles.normal) or {}
	local wantRelics = opts.wantRelics or #plan.relics
	local fleeUntil = -1 -- "normal" runs until this time after it was last seen
	-- a person does not start every attempt on the same frame; opts.startDelay varies it (session)
	local pauseLeft = (if normal then (human.startSeconds or 0) else 0) + (opts.startDelay or 0)
	local leaving = false
	local spotEvents = 0 -- times it has seen you this night (a new sighting after it lost you)
	local waited = 0 -- seconds spent waiting for the patrol to move on (bounded by patienceSeconds)

	-- hazards (the client's rules, driven the way Haunt.client drives them)
	local hz = opts.hazards
	local hzState, hzRand, hzGate, hzBands
	local hzStats = { spawned = 0, hits = 0, near = 0, cancelled = 0, knockedFor = 0, huntFree = 0, minDist = {},
		hitsInChase = 0, knockedWhileSeen = 0, pushedStuds = 0 }
	local knockLeft = 0
	-- a knock is a PUSH (Haunt.client sets the root's velocity to Hazards.knockVelocity with PlatformStand on):
	-- modelled at full speed for the whole KnockSeconds, through the same walls, the worst case (friction in
	-- Roblox can only shorten it)
	local knockVx, knockVz = 0, 0
	local lastSpotted = -math.huge
	if hz then
		-- the client's scheduler lives for the whole session (its clock freezes in the day and is never
		-- reset), so a session passes ONE state and rand in; a lone night gets its own
		hzRand = hz.rand or lcg(hz.seed or (night * 7919 + 17))
		hzState = hz.state or Hazards.newScheduler(hz.cfg, hzRand)
		hzGate = hz.gate
		hzBands = hz.bands
		-- a new night: the client calls off anything still in flight when the phase changes
		if hzState.active then Hazards.cancel(hzState) end
	end
	local prevPx, prevPz = px, pz

	local t, everSpotted, spottedTicks = 0, false, 0
	local goal: number? = nil
	local dest: number? = nil
	local taken: { [number]: boolean } = {}
	local outside = 0
	local spottedNow = false
	while t < limit do
		local myRoom = Manor.roomAtWorld(plan, Config, px, pz)
		local wRoom = Manor.roomAtWorld(plan, Config, w.x, w.z)
		if myRoom == nil then
			outside += 1
		end

		if myRoom then
			local cx, cz = centreOf(plan, myRoom)
			if (px - (cx :: number)) ^ 2 + (pz - (cz :: number)) ^ 2 < 400 then
				local got = 0
				for _ in taken do got += 1 end
				for i, r in plan.relics do
					if r.roomId == myRoom and not taken[i] and (not normal or (got < wantRelics and not leaving)) then
						taken[i] = true
						got += 1
						if normal then
							pauseLeft += human.promptSeconds or 0 -- stop, face the pedestal, press E
						end
					end
				end
				if myRoom == plan.exitId and policy ~= "flee" then
					local all = true
					for i in plan.relics do
						if not taken[i] then all = false end
					end
					if policy == "exit" or all or (normal and leaving) then
						return { caught = false, out = true, at = t, spotted = everSpotted,
							spottedTicks = spottedTicks, cleared = got, outside = outside, plan = plan, hz = hzStats }
					end
				end
			end
		end

		-- "normal": decide whether to head out (enough relics, or the manor is waking)
		if normal and not leaving then
			local got = 0
			for _ in taken do got += 1 end
			local dread = Watcher.dread(t, dreadTotal)
			if got >= math.min(wantRelics, #plan.relics) or dread >= (human.leaveAtDread or 1)
				or spotEvents >= (human.leaveAfterSpotted or math.huge) then
				leaving = true
				dest = nil
			end
		end

		-- which policy is steering this tick
		local steer = policy
		if normal then
			steer = if t < fleeUntil then "flee" elseif leaving then "exit" else "loot"
			if leaving then dest = plan.exitId end
			-- late in the night a person stops hiding and runs for the exit whatever is in the way
			if Watcher.dread(t, dreadTotal) >= (human.dashAtDread or math.huge) then
				leaving, dest, steer = true, plan.exitId, "exit"
			end
		end

		local tx: number?, tz: number? = nil, nil
		if myRoom and steer ~= "flee" then
			if dest == nil or dest == myRoom then
				if steer == "exit" then
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
			-- "normal": a person who knows where it is does not walk into it. If the Nightwatcher stands
			-- in the next room or the one after on the way, wait in the far corner of this one until its
			-- patrol moves on (the bots never do this, which is why they measure the game's edges).
			local waitHere = false
			local blockedBy = false
			if normal and wRoom and dest ~= myRoom then
				local path = Manor.pathBetween(plan, myRoom, dest :: number)
				blockedBy = path ~= nil and path[2] == wRoom
			end
			if not blockedBy then
				waited = 0 -- patience is per encounter
			end
			if blockedBy and waited < (human.patienceSeconds or 0) then
				do
					waited += dt
					waitHere = true
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
			if waitHere then
				-- hiding; tx/tz already set
			elseif dest == myRoom then
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
			local clearOf = math.min(Config.Watcher.CatchRadius + 3, here)
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
			-- "normal" runs TOWARD where it was going when it can (around the Nightwatcher, not away from
			-- the exit): the next room on its way, if that room is not the watcher's and the dash there
			-- does not pass within arm's length of it
			if not keep and normal and dest ~= nil and dest ~= myRoom then
				local path = Manor.pathBetween(plan, myRoom, dest :: number)
				local nxt = path and path[2]
				if nxt and nxt ~= wRoom then
					local ax, az = aimAt(nxt)
					if ax then
						goal, tx, tz, keep = nxt, ax, az, true
					end
				end
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
					if tx == nil then
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

		-- a hazard's locked ring overrides the goal for a player who reads it: walk straight out of it
		local dodging = false
		if hz and hz.react and hzState.active and hzState.active.locked and not hzState.active.hit then
			local zone = Hazards.zone(hzState.active, PLAYER_RADIUS)
			local ox, oz = px - zone.x, pz - zone.z
			local d = math.sqrt(ox * ox + oz * oz)
			-- inside, or about to walk into it before it has passed: step out, directly away from its centre
			local tLeft = hzState.active.duration - hzState.active.t
			local ahead = false
			if tx then
				local hx, hz2 = (tx :: number) - px, (tz :: number) - pz
				local hl = math.sqrt(hx * hx + hz2 * hz2)
				if hl > 1e-6 then
					local reach = math.min(hl, WALK * math.max(tLeft, 0))
					local fx, fz = px + hx / hl * reach, pz + hz2 / hl * reach
					ahead = segDist(zone.x, zone.z, px, pz, fx, fz) <= zone.radius + 0.5
				end
			end
			-- a person walks on toward the ring and stops at its edge; only inside it do they step out
			if d <= zone.radius + 0.5 or (ahead and d <= zone.radius + 2.5) then
				dodging = true
				if d < 1e-3 then ox, oz, d = 1, 0, 1 end
				local out = zone.radius + 1.5
				if d > zone.radius + 0.5 then
					tx, tz = px, pz -- at the ring's edge, heading in: stop and let it pass
				else
					-- inside: step out the way that is open (straight away from the centre first; a wall
					-- there means turning, the way a person would)
					local base = math.atan2(oz, ox)
					tx, tz = zone.x + ox / d * out, zone.z + oz / d * out
					for k = 0, 7 do
						local a = base + (if k % 2 == 0 then 1 else -1) * math.ceil(k / 2) * math.pi / 4
						local qx, qz = zone.x + math.cos(a) * out, zone.z + math.sin(a) * out
						if not blocked(qx, qz, PLAYER_RADIUS) and not blocked((px + qx) / 2, (pz + qz) / 2, PLAYER_RADIUS) then
							tx, tz = qx, qz
							break
						end
					end
				end
			end
		end

		if opts.trace and math.floor(t * 10 + 0.5) % 20 == 0 then
			print(string.format("t=%.1f me=%s w=%s steer=%s leaving=%s dest=%s goal=%s pos=%.1f,%.1f tgt=%s,%s pause=%.1f", t,
				tostring(myRoom), tostring(wRoom), steer, tostring(leaving), tostring(dest), tostring(goal), px, pz, tostring(tx), tostring(tz), pauseLeft))
		end
		if knockLeft > 0 then
			knockLeft -= dt
			hzStats.knockedFor += dt
			local ks = math.sqrt(knockVx * knockVx + knockVz * knockVz)
			if ks > 1e-6 then
				local bx, bz = px, pz
				px, pz = walk(blocked, px, pz, px + knockVx / ks * 1000, pz + knockVz / ks * 1000, ks * dt)
				hzStats.pushedStuds += math.sqrt((px - bx) ^ 2 + (pz - bz) ^ 2)
			end
		elseif pauseLeft > 0 and not dodging and (normal or not spottedNow) then
			pauseLeft -= dt
		elseif tx then
			px, pz = walk(blocked, px, pz, tx :: number, tz :: number, WALK * dt)
		end

		t += dt
		local dread = Watcher.dread(t, dreadTotal)
		myRoom = Manor.roomAtWorld(plan, Config, px, pz)
		wRoom = Manor.roomAtWorld(plan, Config, w.x, w.z)
		local roomOk = myRoom ~= nil and wRoom ~= nil
			and (myRoom == wRoom or Manor.linked(plan, wRoom :: number, myRoom :: number))
		local spotted = Watcher.spots(Config, w.x, w.z, w.fx, w.fz, px, pz, roomOk)
		spottedNow = spotted

		local target
		if spotted and myRoom and wRoom then
			if myRoom == wRoom then
				target = { x = px, z = pz }
			else
				local nx, nz = Manor.chaseStep(Config, plan, wRoom :: number, w.x, w.z, myRoom :: number)
				if nx then
					target = { x = nx, z = nz }
				else
					target = { x = px, z = pz }
				end
			end
		end
		if spotted then
			if t - lastSpotted > dt * 1.5 then spotEvents += 1 end
			everSpotted = true
			spottedTicks += 1
			lastSpotted = t
			if normal then
				fleeUntil = t + (human.fleeSeconds or Config.Watcher.HuntSeconds)
				pauseLeft = 0 -- nobody finishes pressing E with that thing in the doorway
				goal = nil
			end
		end

		Watcher.step(w, dt, {
			cfg = Config,
			points = points,
			dread = dread,
			watcherSlow = effects.watcherSlow,
			spotted = spotted,
			target = target,
		})

		-- hazards, after the server's tick (the client runs on its own frames; the order inside one
		-- 0.1 s tick does not matter at these speeds)
		if hz then
			local vx, vz = (px - prevPx) / dt, (pz - prevPz) / dt
			-- the client's rule, the same call Haunt.client makes: at night the clock is "run" or "hold", never "freeze"
			local clock = Nightfall.hazardClock(hzGate, { phase = "NIGHT", spotted = spotted, sinceSpotted = t - lastSpotted })
			if spotted and hzState.active then
				-- called off the moment it sees you: a knock never lands during a chase (Haunt.client does the same)
				Hazards.cancel(hzState)
				hzStats.cancelled += 1
			end
			if spotted and knockLeft > 0 then
				knockLeft = 0 -- a knock ends the moment it sees you
			end
			if clock == "run" then hzStats.huntFree += dt end
			local band = hzBands[Nightfall.bandIndex(hzBands, night)]
			local lead = Nightfall.leadAim(
				{ x = px, y = 3, z = pz }, { x = vx, y = 0, z = vz },
				if hzState.active then hzState.active.arriveAt - hzState.active.t else 0,
				hz.cfg.LeadSeconds or 0)
			local before = if hzState.active then hzState.active.t else nil
			-- at night the clock always runs; while it hunts you the launch is HELD, the clock never frozen (review 4).
			-- The day is not stepped here at all: that is the freeze.
			local ev = Hazards.step(hzState, hz.cfg, dt, {
				resting = false,
				paused = clock == "freeze",
				held = clock == "hold",
				grounded = knockLeft <= 0,
				kinds = band.hazards or {},
				aim = lead,
				yaw = if math.abs(vx) + math.abs(vz) > 0.01 then math.atan2(vx, vz) else 0,
				pitch = math.rad(-12),
			}, hzRand)
			if ev and ev.type == "spawn" then
				hzStats.spawned += 1
				hzStats.minDist[hzStats.spawned] = math.huge
			end
			local plan2 = hzState.active
			if plan2 then
				local me = { x = px, y = 3, z = pz }
				local hp = Hazards.positionAt(plan2, plan2.t)
				local d = math.sqrt((hp.x - px) ^ 2 + (hp.z - pz) ^ 2)
				local k = math.max(hzStats.spawned, 1)
				if d < (hzStats.minDist[k] or math.huge) then hzStats.minDist[k] = d end
				if Hazards.checkHit(plan2, before or 0, plan2.t, me, PLAYER_RADIUS) then
					plan2.hit = true
					hzStats.hits += 1
					knockLeft = hz.cfg.KnockSeconds
					local kv = Hazards.knockVelocity(hz.cfg, plan2, me)
					knockVx, knockVz = kv.x, kv.z
					if t - lastSpotted < (hz.cfg.QuietAfterSpottedSeconds or 0) then
						hzStats.hitsInChase += 1 -- must stay 0: a knock never lands during a chase
					end
				end
			end
			if spotted and knockLeft > 0 then
				hzStats.knockedWhileSeen += 1 -- must stay 0: a knock ends the moment it sees you
			end
		end
		prevPx, prevPz = px, pz

		if Watcher.caught(Config, w.x, w.z, px, pz) and not ignoreCatch then
			local got = 0
			for _ in taken do got += 1 end
			return { caught = true, at = t, spotted = everSpotted, spottedTicks = spottedTicks,
				ambushed = ambushed, room = myRoom, outside = outside, plan = plan, hz = hzStats, cleared = got }
		end
	end
	local got = 0
	for _ in taken do got += 1 end
	local _ = spottedNow
	return { caught = false, at = limit, spotted = everSpotted, spottedTicks = spottedTicks,
		cleared = got, outside = outside, plan = plan, hz = hzStats, evicted = true }
end

-- Near-hits in a finished night: hazards whose closest pass came within `studs` of the player.
function NightModel.nearCount(hzStats: any, studs: number): number
	local n = 0
	for i = 1, hzStats.spawned do
		if (hzStats.minDist[i] or math.huge) <= studs then n += 1 end
	end
	return n
end

-- Plays nights back to back from a fresh profile for `minutes` of play.
--   opts = { human = profile, hazards = {...} or nil, minutes = n, nightCap = n }
-- Returns { reachedAt = { [night] = minutes }, nights = n, attempts = n, caught = n, evicted = n,
--           hz = { spawned, hits, near, cancelled }, manorSeconds, daySeconds }
function NightModel.session(opts: any)
	local human = opts.human or Config.Pacing.Profiles.normal
	local pc = Config.Pacing
	local state = Night.startState(Config, nil)
	local levels: { [string]: number } = {}
	local tSec = 0
	local reachedAt = { [state.night] = 0 }
	local attempts, caught, evicted, dashes = 0, 0, 0, 0
	local careful = 0 -- relics fewer than all, after a failure on this night
	local manorSeconds, daySeconds = 0, 0
	local hzTot = { spawned = 0, hits = 0, near = 0, cancelled = 0, knockedFor = 0, huntFree = 0 }
	local hzRand = opts.hazards and lcg(opts.hazards.seed or 104729) or nil
	local hzState = opts.hazards and Hazards.newScheduler(opts.hazards.cfg, hzRand) or nil
	local limit = (opts.minutes or 120) * 60
	while tSec < limit and state.night < (opts.nightCap or Config.Night.MaxNight) do
		-- DAY: walk to the door, look around, buy what can be bought (cheapest first)
		local day = human.daySeconds or 0
		while true do
			local bestId, bestCost
			for _, e in Config.Upgrades.Catalog do
				local c = Upgrades.cost(Config, e.id, Upgrades.level(levels, e.id))
				if c and c <= state.stash and (bestCost == nil or c < bestCost) then
					bestId, bestCost = e.id, c
				end
			end
			if not bestId then break end
			local ok, nl, ns = Upgrades.buy(Config, levels, state.stash, bestId)
			if not ok then break end
			levels, state.stash = nl, ns
			day += human.buySeconds or 0
		end
		tSec += day
		daySeconds += day

		attempts += 1
		local plan = Manor.plan(Rng.new(Manor.seedFor(Config, state.night)), Config, state.night)
		local want = math.max(1, math.min(human.relicsPerNight or #plan.relics, #plan.relics) - careful)
		-- after a few failures on the same night a person stops being careful and makes a dash for the
		-- Servants' Exit, grabbing only what is on the way (Chase.spec's "exit" walker; 25 of 30 get out)
		local dash = careful >= (human.retriesBeforeDash or math.huge)
		if dash then dashes += 1 end
		local r = NightModel.simulate(state.night, levels, if dash then "exit" else "normal", {
			human = human,
			wantRelics = want,
			-- a retry starts at a different moment of the patrol, the way a person's retry does
			startDelay = (careful * 1.7) % 6,
			hazards = opts.hazards and {
				cfg = opts.hazards.cfg, gate = opts.hazards.gate, bands = opts.hazards.bands,
				react = opts.hazards.react, state = hzState, rand = hzRand,
			} or nil,
		})
		tSec += r.at + Config.BeatSeconds
		manorSeconds += r.at
		if r.hz then
			hzTot.spawned += r.hz.spawned
			hzTot.hits += r.hz.hits
			hzTot.cancelled += r.hz.cancelled
			hzTot.knockedFor += r.hz.knockedFor
			hzTot.huntFree += r.hz.huntFree
			hzTot.near += NightModel.nearCount(r.hz, pc.NearHitStuds)
		end

		-- what was carried: the bot does not record WHICH relics it took, so it is valued as the
		-- plan's first `cleared` relics (deep relics are worth more, so this slightly undervalues a
		-- full clear; the upgrade pace it feeds is therefore on the slow side)
		local carried = {}
		for i = 1, (r.cleared or 0) do
			local rel = plan.relics[i]
			if rel then table.insert(carried, rel.tier) end
		end
		local outcome = if r.out then Night.EXTRACTED elseif r.caught then Night.CAUGHT else Night.EVICTED
		if r.caught then caught += 1 end
		if not r.out and not r.caught then evicted += 1 end
		state.carried = carried
		local newState = Night.resolve(state, outcome, Config, Upgrades.effects(Config, levels))
		if newState.night > state.night then
			careful = 0
			reachedAt[newState.night] = tSec / 60
		else
			careful += 1 -- caught or evicted: the same night again, taking one relic fewer
		end
		state = { night = newState.night, stash = newState.stash, best = newState.best, carried = {} }
	end
	return {
		reachedAt = reachedAt, nights = state.night, attempts = attempts, caught = caught, evicted = evicted, dashes = dashes,
		hz = hzTot, manorSeconds = manorSeconds, daySeconds = daySeconds, totalSeconds = tSec, levels = levels,
	}
end

return NightModel
