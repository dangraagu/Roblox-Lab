-- PlayModel.luau — plays Fork Tower in the luau CLI to MEASURE pacing and hazard rarity.
-- Test-side only; never shipped. Used by tests/Pacing.spec.luau; numbers in EYECANDY.md.
--
-- Built from the game's own modules, the same way the server builds the tower:
--   * geometry: Section.build per floor, chained exactly as Main.server buildSection chains it
--     (fork origin -> section base 17 studs on -> exit -> next fork 16.5 studs past the exit);
--   * plans: Fork.plan with Fork.legacySecrets, which is what tests/readcost.measure.luau plays
--     (the trap SIDE only matters to the guesser, and its distribution is the same);
--   * hazards: the real Hazards scheduler and Config.Hazards, behind the real Climb.gate (the clock
--     runs only while climbing, never on a pad; a hazard in flight is dismissed on a pad);
--   * bands: named by Climb.namedFloor, exactly as the client names them.
-- Stated assumptions, not in the game:
--   * Roblox physics: Config.Physics.Gravity for airtime and falls;
--   * a human: Config.Pacing.Profiles (seconds lining up each hop, share of hops missed, seconds
--     to recover after the rescue, seconds spent at a fork besides the read, seconds on the summit);
--   * a hop takes max(horizontal reach / speed, ballistic airtime) — the readcost model's ground
--     speed rule, with the jump's own airtime as a floor;
--   * a miss or a hazard hit falls the whole way to the server's rescue line (checkpoint - FallGrace)
--     and waits half a rescue poll on average: the worst case (a real fall often lands on a lower
--     platform of the same section sooner);
--   * the server's own red hazard cubes are left out: this measures the NEW hazards.
-- The camera sits behind the climber looking along the direction of travel at `cameraPitch`.

local Hazards = require("../src/shared/Hazards")
local EnvBands = require("../src/shared/EnvBands")
local Climb = require("../src/shared/Climb")
local Section = require("../src/shared/Section")
local Fork = require("../src/shared/Fork")
local Rng = require("../src/shared/Rng")

local PlayModel = {}

local function lcg(seed: number)
	local s = seed % 4294967296
	return function(): number
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end
PlayModel.lcg = lcg

local function v(x, y, z) return { x = x, y = y, z = z } end

-- The server's traitTotals (speed and jump), clamped upward exactly as it is.
local function totals(cfg, picks)
	local byId = {}
	for _, t in ipairs(cfg.Traits) do byId[t.id] = t end
	local jump, speed = cfg.Jump.BaseJump, cfg.WalkSpeed
	for _, id in ipairs(picks) do
		local t = byId[id]
		if t then
			jump += t.jump or 0
			speed += t.speed or 0
		end
	end
	return math.min(math.max(jump, cfg.Jump.BaseJump), cfg.Jump.MaxJumpHeight), math.max(speed, cfg.WalkSpeed)
end

function PlayModel.airtime(cfg, jump: number, step: number, reach: number, speed: number): number
	local g = cfg.Physics.Gravity
	local ballistic = math.sqrt(2 * jump / g) + math.sqrt(2 * math.max(jump - step, 0) / g)
	return math.max(reach / speed, ballistic)
end

-- Seconds a fall costs: to the rescue line, half a poll, then the player's own recovery.
function PlayModel.fallSeconds(cfg, profile): number
	local drop = cfg.World.FallGrace + cfg.World.RespawnLift
	return math.sqrt(2 * drop / cfg.Physics.Gravity) + cfg.Pacing.RescuePollSeconds / 2 + profile.recover
end

-- One floor's world geometry. `forkTop` is fork L's pad top-centre; returns the platforms' root
-- positions (top + FloorBelowRoot), the next fork's top-centre, and the exit top.
function PlayModel.floorGeometry(cfg, runSeed: number, level: number, theme: string, penalty: boolean, forkTop)
	local base = v(forkTop.x, forkTop.y, forkTop.z + cfg.World.DoorDepth + cfg.Tower.TileSize)
	local sec = Section.build(cfg, runSeed, level, theme, penalty, Rng, forkTop.x)
	local lift = cfg.Env.FloorBelowRoot
	local roots = {}
	for i, pf in ipairs(sec.platforms) do
		roots[i] = v(base.x + pf.dx, base.y + pf.dy + lift, base.z + pf.dz)
	end
	local nextFork = v(base.x + sec.exit.dx, base.y + sec.exit.dy, base.z + sec.exit.dz + cfg.Tower.TileSize / 2 + 12)
	return {
		roots = roots,
		step = sec.step,
		reach = cfg.Tower.TileSize + sec.gap,
		nextFork = nextFork,
		exitTop = base.y + sec.platforms[#sec.platforms].dy,
		count = #sec.platforms,
	}
end

-- opts: { cfg, profile, runs, seed, strategy = "read" | "guess", behavior = "ignore" | "dodge",
--         cameraPitch (degrees, default -15), dt (default 0.05), rest = { every, length }? }
function PlayModel.play(opts)
	local cfg = opts.cfg
	local Hz = cfg.Hazards
	local bands = cfg.Env.Bands
	local profile = opts.profile
	local dt = opts.dt or 0.05
	local rand = lcg(opts.seed or 1)
	local coin = lcg((opts.seed or 1) * 7919 + 13)
	local camPitch = math.rad(opts.cameraPitch or -15)
	local FLOORS = cfg.Tower.Floors
	local sched = Hazards.newScheduler(Hz, rand)

	local stats = {
		seconds = 0, climbSeconds = 0, restSeconds = 0,
		spawns = 0, nears = 0, hits = 0, dismissed = 0,
		launchedOnPad = 0, hitOnPad = 0, maxActive = 0,
		hazardLossSeconds = 0, runs = 0, traps = 0,
		bandEntry = {}, -- [bandIndex] = sum of seconds into a run at which the band was first stood in
		bandEntryRuns = {},
		runSeconds = 0,
		spawnGaps = {}, -- climbing seconds between consecutive spawns
		readSeconds = 0,
	}
	local lastSpawnClock = nil

	-- the hazard clock and rest, advanced one tick at a time by `tick`
	local restState = { resting = false, nextToggle = opts.rest and opts.rest.every or math.huge, until_ = 0 }
	local closest = math.huge

	-- the current situation, read by tick()
	local level, summit, climbing, sanctuary = 1, false, false, true
	local pos, grounded, yaw = v(0, 3, 14), true, 0
	local runStart = 0

	local function band(): any
		return bands[EnvBands.indexAt(bands, Climb.namedFloor(level, summit, FLOORS) - 1)]
	end

	-- returns true when a hazard hit this tick
	local function tick(): boolean
		stats.seconds += dt
		-- the rest probe: a climber who rests `length` seconds every `every` seconds of play, taken only
		-- when Rest would allow it (grounded, no threat)
		if opts.rest then
			if restState.resting and stats.seconds >= restState.until_ then
				restState.resting = false
				restState.nextToggle = stats.seconds + opts.rest.every
			elseif not restState.resting and stats.seconds >= restState.nextToggle and grounded and sched.active == nil then
				restState.resting = true
				restState.until_ = stats.seconds + opts.rest.length
			end
		end
		local resting = restState.resting
		if resting then stats.restSeconds += dt end
		local gate = Climb.gate({ climbing = climbing, sanctuary = sanctuary, resting = resting })
		if gate.clock then stats.climbSeconds += dt end
		if gate.dismiss and sched.active then
			if closest <= Hz.NearMissStuds then stats.nears += 1 end
			sched.active = nil
			stats.dismissed += 1
		end
		local before = sched.active and sched.active.t or nil
		local ev = Hazards.step(sched, Hz, dt, {
			resting = not gate.clock, grounded = grounded, kinds = band().hazards, aim = pos, yaw = yaw, pitch = camPitch,
		}, rand)
		if ev and ev.type == "spawn" then
			stats.spawns += 1
			if sanctuary then stats.launchedOnPad += 1 end
			if lastSpawnClock then table.insert(stats.spawnGaps, sched.clock - lastSpawnClock) end
			lastSpawnClock = sched.clock
			closest = math.huge
		end
		local hit = false
		local plan = sched.active
		if plan then
			stats.maxActive = math.max(stats.maxActive, 1)
			local d = Hazards.distance(Hazards.positionAt(plan, plan.t), pos)
			if d < closest then closest = d end
			if gate.hit and Hazards.checkHit(plan, before or 0, plan.t, pos, Hz.PlayerRadius) then
				plan.hit = true
				stats.hits += 1
				if sanctuary then stats.hitOnPad += 1 end
				hit = true
			end
		end
		if ev and ev.type == "done" then
			local d = Hazards.distance(Hazards.positionAt(ev.plan, ev.plan.duration), pos)
			if d < closest then closest = d end
			if closest <= Hz.NearMissStuds then stats.nears += 1 end
			closest = math.huge
		end
		return hit
	end

	-- spend `seconds` in place (grounded unless told otherwise); returns true if hit
	local function wait(seconds: number, isGrounded: boolean?): boolean
		local g0 = grounded
		grounded = if isGrounded == nil then true else isGrounded
		local t = 0
		while t < seconds - 1e-9 do
			t += dt
			if tick() then
				grounded = g0
				return true
			end
		end
		grounded = g0
		return false
	end

	-- a knock or a miss: fall to the rescue line, wait for the poll, recover on `home`
	local function fall(home)
		local secs = PlayModel.fallSeconds(cfg, profile) - profile.recover
		local t = 0
		local start = pos
		grounded = false
		while t < secs - 1e-9 do
			t += dt
			local k = math.min(t / secs, 1)
			pos = v(start.x, start.y - (cfg.World.FallGrace + cfg.World.RespawnLift) * k, start.z)
			tick()
		end
		pos = home
		grounded = true
		wait(profile.recover)
	end

	-- the dodge: stop, and when the lane locks walk out of the ring, sideways away from the lane
	local function dodgeIfNeeded(home): boolean
		local plan = sched.active
		if opts.behavior ~= "dodge" or plan == nil then return false end
		-- wait for the lock
		while sched.active == plan and not plan.locked do
			if tick() then fall(home); return true end
		end
		if sched.active ~= plan then return true end
		if Hazards.inZone(plan, pos, Hz.PlayerRadius) then
			local z = Hazards.zone(plan, Hz.PlayerRadius)
			local vx, vz = plan.velocity.x, plan.velocity.z
			local hl = math.sqrt(vx * vx + vz * vz)
			local px, pz = 1, 0
			if hl > 1e-6 then px, pz = -vz / hl, vx / hl end
			local dist = z.radius + 0.5
			local from = pos
			local to = v(z.x + px * dist, pos.y, z.z + pz * dist)
			local walk = math.sqrt((to.x - from.x) ^ 2 + (to.z - from.z) ^ 2) / cfg.WalkSpeed
			local t = 0
			while t < walk - 1e-9 do
				t += dt
				local k = math.min(t / walk, 1)
				pos = v(from.x + (to.x - from.x) * k, from.y, from.z + (to.z - from.z) * k)
				if tick() then fall(home); return true end
			end
		end
		while sched.active == plan do
			if tick() then fall(home); return true end
		end
		-- walk back
		pos = home
		return true
	end

	local seconds = opts.hours and opts.hours * 3600 or math.huge
	local runSeed = opts.firstRunSeed or 1
	local runsLeft = opts.runs or math.huge
	while runsLeft > 0 and stats.seconds < seconds do
		runsLeft -= 1
		stats.runs += 1
		runStart = stats.seconds
		local plan = Fork.plan(cfg, runSeed, Rng, Fork.legacySecrets(cfg, runSeed))
		local picks = {}
		local forkTop = v(0, 0, 14)
		local enteredBand = {}
		level, summit = 1, false
		for L = 1, FLOORS do
			level = L
			-- AT THE FORK: a sanctuary. Walk on, (read), think, choose.
			climbing, sanctuary = false, true
			pos, grounded, yaw = v(forkTop.x, forkTop.y + cfg.Env.FloorBelowRoot, forkTop.z), true, 0
			local bi = EnvBands.indexAt(bands, Climb.namedFloor(L, false, FLOORS) - 1)
			if not enteredBand[bi] then
				enteredBand[bi] = true
				stats.bandEntry[bi] = (stats.bandEntry[bi] or 0) + (stats.seconds - runStart)
				stats.bandEntryRuns[bi] = (stats.bandEntryRuns[bi] or 0) + 1
			end
			local forkTime = profile.fork
			if opts.strategy ~= "guess" then
				forkTime += cfg.Fork.ReadSeconds
				stats.readSeconds += cfg.Fork.ReadSeconds
			end
			wait(forkTime)
			local floor = plan.floors[L]
			local slot = if opts.strategy == "guess" then (if coin() < 0.5 then 1 else 2) else 3 - floor.trapDoor
			local penalty = Fork.isTrap(floor, slot)
			if penalty then stats.traps += 1 end
			picks[#picks + 1] = floor.doors[slot].traitId
			local jump, speed = totals(cfg, picks)
			local geo = PlayModel.floorGeometry(cfg, runSeed, L, floor.doors[slot].theme, penalty, forkTop)

			-- CLIMBING: teleported onto platform 1, then hop by hop to the exit
			climbing, sanctuary = true, false
			local i = 1
			pos = geo.roots[1]
			while i < geo.count do
				local here, there = geo.roots[i], geo.roots[i + 1]
				yaw = math.atan2(there.x - here.x, there.z - here.z)
				-- line up (grounded); a hazard in flight makes a dodger stop and deal with it
				local t = 0
				while t < profile.lineUp - 1e-9 do
					if sched.active and opts.behavior == "dodge" then
						dodgeIfNeeded(here)
						t = 0
					end
					t += dt
					pos = here
					if tick() then fall(here); t = 0 end
				end
				-- the hop
				local air = PlayModel.airtime(cfg, jump, geo.step, geo.reach, speed)
				local missed = rand() < profile.miss
				local hitMidAir = false
				t = 0
				while t < air - 1e-9 do
					t += dt
					local k = math.min(t / air, 1)
					pos = v(here.x + (there.x - here.x) * k, here.y + (there.y - here.y) * k, here.z + (there.z - here.z) * k)
					grounded = false
					if tick() then hitMidAir = true; break end
				end
				grounded = true
				if hitMidAir then
					fall(here)
				elseif missed then
					fall(here)
				else
					i += 1
					pos = there
				end
			end
			-- on the exit: the server moves the player to the next floor at once
			forkTop = geo.nextFork
		end
		-- THE SUMMIT: a sanctuary; look at the card, then rebirth
		summit, climbing, sanctuary = true, false, true
		level = FLOORS + 1
		pos = v(forkTop.x, forkTop.y + cfg.Env.FloorBelowRoot, forkTop.z)
		local bi = EnvBands.indexAt(bands, Climb.namedFloor(level, true, FLOORS) - 1)
		if not enteredBand[bi] then
			enteredBand[bi] = true
			stats.bandEntry[bi] = (stats.bandEntry[bi] or 0) + (stats.seconds - runStart)
			stats.bandEntryRuns[bi] = (stats.bandEntryRuns[bi] or 0) + 1
		end
		wait(profile.summit)
		stats.runSeconds += stats.seconds - runStart
		runSeed += 1
	end
	stats.clock = sched.clock
	stats.hazardLossSeconds = stats.hits * PlayModel.fallSeconds(cfg, profile)
	local minutes = stats.seconds / 60
	stats.minutes = minutes
	stats.perMinute = stats.spawns / minutes
	stats.nearPerMinute = stats.nears / minutes
	stats.hitsPerMinute = stats.hits / minutes
	stats.hitShare = if stats.spawns > 0 then stats.hits / stats.spawns else 0
	stats.minutesPerRun = stats.runSeconds / 60 / math.max(stats.runs, 1)
	stats.bandMinutes = {}
	for bi, sum in stats.bandEntry do
		stats.bandMinutes[bi] = sum / stats.bandEntryRuns[bi] / 60
	end
	return stats
end

return PlayModel
