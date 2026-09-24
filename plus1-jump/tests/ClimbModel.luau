-- ClimbModel.luau — measures time-to-altitude for +1 Jump. Test-side only; never shipped.
--
-- Built entirely from the game's own climb model (Progression, TowerGen, Config) plus two things
-- that are not in the game and are stated as assumptions:
--   * Roblox physics: Workspace gravity 196.2 (Config.Pacing.Gravity) for jump airtime;
--   * a human: Config.Pacing.Profiles — seconds lining up a jump, share of jumps missed, seconds to
--     recover after the server's fall rescue puts you back on your platform.
-- See tests/Pacing.spec.luau for what is asserted and EYECANDY.md for the resulting table.

local Progression = require("../src/shared/Progression")
local TowerGen = require("../src/shared/TowerGen")
local Hazards = require("../src/shared/Hazards")
local EnvBands = require("../src/shared/EnvBands")

local ClimbModel = {}

function ClimbModel.airtime(jumpHeight: number, step: number, g: number): number
	local down = math.max(jumpHeight - step, 0)
	return math.sqrt(2 * jumpHeight / g) + math.sqrt(2 * down / g)
end

-- Seconds lost to one fall: from an average platform of tier t down to the rescue line, the
-- rescue poll, and the player's own recovery.
function ClimbModel.fallPenalty(t: number, profile: any, cfg: any): number
	local tw, pc = cfg.Tower, cfg.Pacing
	local avgHeight = (tw.TilesPerTier + 1) / 2 * Progression.stepHeight(t, tw)
	local fall = math.sqrt(2 * (avgHeight + pc.RescueDropStuds) / pc.Gravity)
	return fall + pc.RescuePollSeconds / 2 + profile.recoverSeconds
end

-- Expected seconds to earn one platform of tier t with rebirth multiplier `mult`.
function ClimbModel.secondsPerPlatform(t: number, profile: any, mult: number, cfg: any): number
	local tw = cfg.Tower
	local jp = Progression.jumpPowerAtTierStart(t, tw)
	local h = Progression.jumpHeight(jp, mult, cfg.Jump)
	local s = Progression.stepHeight(t, tw)
	local attempt = profile.setupSeconds + ClimbModel.airtime(h, s, cfg.Pacing.Gravity)
	local p = profile.missChance
	return attempt / (1 - p) + p / (1 - p) * ClimbModel.fallPenalty(t, profile, cfg)
end

local function climbSeconds(fromTiers: number, toTiers: number, profile: any, mult: number, cfg: any, hitShare: number): number
	local hz = cfg.Hazards
	local rate = 2 / (hz.IntervalMin + hz.IntervalMax) -- hazards per climbing second
	local total = 0
	local t = math.floor(fromTiers) + 1
	while t - 1 < toTiers do
		local share = math.min(1, toTiers - (t - 1))
		local secs = cfg.Tower.TilesPerTier * ClimbModel.secondsPerPlatform(t, profile, mult, cfg) * share
		secs += secs * rate * hitShare * ClimbModel.fallPenalty(t, profile, cfg)
		total += secs
		t += 1
	end
	return total
end

-- Minutes of play (rest excluded) to have climbed `target` tiers.
--   opts.rebirthAt = { tier, ... }: rebirth on completing each of these, in order, first.
function ClimbModel.minutesToProgress(target: number, profile: any, cfg: any, opts: any?, hitShare: number?): number
	opts = opts or {}
	hitShare = hitShare or 0
	local rebirths = 0
	local seconds = 0
	for _, r in ipairs(opts.rebirthAt or {}) do
		if not Progression.canRebirth(r, rebirths, cfg.Rebirth) then
			error(string.format("ClimbModel: rebirth #%d at tier %d is not allowed (needs %d)", rebirths + 1, r,
				Progression.rebirthTierRequired(rebirths, cfg.Rebirth)))
		end
		seconds += climbSeconds(0, r, profile, Progression.rebirthMultiplier(rebirths, cfg.Rebirth), cfg, hitShare)
		rebirths += 1
	end
	seconds += climbSeconds(0, target, profile, Progression.rebirthMultiplier(rebirths, cfg.Rebirth), cfg, hitShare)
	return seconds / 60
end

-- Minutes of play to STAND in tier `tier` (its first platform): when the HUD shows "Tier <tier>" and the
-- sky names that tier's band.
function ClimbModel.minutesToTier(tier: number, profile: any, cfg: any, opts: any?, hitShare: number?): number
	if tier <= 0 then return 0 end
	return ClimbModel.minutesToProgress(tier - 1 + 1 / cfg.Tower.TilesPerTier, profile, cfg, opts, hitShare)
end

-- The rebirths taken by a player who presses REBIRTH every time `isHighlighted(tier, bestTier, rebirths)`
-- says the HUD highlights it, on the way to standing in `targetTier`. A rebirth sends the climber back to
-- the pad (the server resets the frontier), the best tier survives. Returns { tier, ... }.
function ClimbModel.followHighlights(targetTier: number, cfg: any, isHighlighted: (number, number, number) -> boolean): { number }
	local taken, best, rebirths = {}, 0, 0
	while true do
		local rebirthed = false
		for t = 1, targetTier - 1 do
			best = math.max(best, t)
			if isHighlighted(t, best, rebirths) then
				assert(Progression.canRebirth(t, rebirths, cfg.Rebirth), "the HUD highlighted a rebirth the server would refuse")
				table.insert(taken, t)
				rebirths += 1
				rebirthed = true
				break
			end
		end
		if not rebirthed then return taken end
		assert(#taken < 10000, "ClimbModel.followHighlights: the player never reaches the target")
	end
end

--======================================================================= hazards on the real tower

-- Fly Config.Hazards at a climber who follows the real TowerGen path at the profile's rhythm.
-- The climber stands on each platform for the model's non-airborne time, then moves in a straight
-- line to the next platform over the jump's airtime. opts.behavior picks how they treat a warning:
--   "ignore" (default): never reacts, keeps climbing on rhythm;
--   "stop": stops on the platform they are on (or land on) when a hazard launches, and when its lane
--           LOCKS walks 4 studs (half a tile) over 0.25 s; resumes climbing when it has passed.
--           opts.dodgeDegrees picks the direction, measured from the lane's horizontal travel:
--           0 = straight back, away from the hazard; 90 / 270 = to either side; 180 = toward it.
--           Without it: at right angles to the lane, on the side away from it (the step every earlier
--           measurement used). Review round 2 added the other directions: a player backs away as
--           often as they step aside.
function ClimbModel.measureHazards(profile: any, cfg: any, opts: any): any
	local tw = cfg.Tower
	local genCfg = { Tower = tw, Jump = cfg.Jump, WorldSeed = cfg.WorldSeed }
	local hours = opts.hours or 1
	local startTier = opts.startTier or 1
	local dt = opts.dt or 0.05

	local seed = opts.seed or 1
	local s = seed % 4294967296
	local function rand()
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end

	-- platform torso positions, tier by tier (tier t starts on the top platform of tier t-1)
	local originX, originZ = 0, 0
	local builtTo = 0
	local torsos = {} -- [tier] = { {x,y,z}, ... }
	local function ensure(t)
		while builtTo < t do
			local n = builtTo + 1
			local gen = TowerGen.tier(n, genCfg)
			local baseY = tw.BaseY + Progression.climbHeight(n - 1, tw)
			local list = {}
			for i, p in ipairs(gen.platforms) do
				list[i] = { x = originX + p.dx, y = baseY + p.dy + 3.5, z = originZ + p.dz }
			end
			torsos[n] = list
			originX += gen.exitDx
			originZ += gen.exitDz
			builtTo = n
		end
	end

	local sched = Hazards.newScheduler(cfg.Hazards, rand)
	local tier, idx = startTier, 1
	ensure(tier + 1)
	local phase, phaseLeft = "dwell", 0
	local function platformTimes(t)
		local jp = Progression.jumpPowerAtTierStart(t, tw)
		local h = Progression.jumpHeight(jp, 1, cfg.Jump)
		local air = ClimbModel.airtime(h, Progression.stepHeight(t, tw), cfg.Pacing.Gravity)
		local total = ClimbModel.secondsPerPlatform(t, profile, 1, cfg)
		return total - air, air
	end
	local dwell, air = platformTimes(tier)
	phaseLeft = dwell

	local function nextOf(t, i)
		if i < tw.TilesPerTier then return t, i + 1 end
		return t + 1, 1
	end

	local behavior = opts.behavior or "ignore"
	-- the camera looks up at the next platform (hazards start inside the view, Hazards.viewWindow)
	local cameraPitch = math.rad(opts.cameraPitch or 20)
	local waiting = false
	local sidestep = nil -- { x, z, progress } once the lane has locked
	local spawns, hits, nears = 0, 0, 0
	local closest = math.huge
	local elapsed, limit = 0, hours * 3600
	while elapsed < limit do
		elapsed += dt
		-- where is the climber now
		local nt, ni = nextOf(tier, idx)
		ensure(nt)
		local here = torsos[tier][idx]
		local there = torsos[nt][ni]
		local pos, grounded
		if phase == "dwell" then
			pos, grounded = here, true
			if sidestep then
				local k = math.min(sidestep.progress / 0.25, 1)
				pos = { x = here.x + sidestep.x * 4 * k, y = here.y, z = here.z + sidestep.z * 4 * k }
			end
		else
			local k = 1 - math.max(phaseLeft, 0) / air
			pos = { x = here.x + (there.x - here.x) * k, y = here.y + (there.y - here.y) * k, z = here.z + (there.z - here.z) * k }
			grounded = false
		end
		-- the game names the band (and picks its hazards) by the tier number the climber stands in
		local tierHere = Progression.tierAtY(pos.y - 3.5, tw)
		local band = cfg.Env.Bands[EnvBands.indexAt(cfg.Env.Bands, tierHere)]
		local yaw = math.atan2(there.x - here.x, there.z - here.z)

		local before = sched.active and sched.active.t or nil
		local ev = Hazards.step(sched, cfg.Hazards, dt, {
			resting = false, grounded = grounded, kinds = band.hazards or {}, aim = pos, yaw = yaw, pitch = cameraPitch,
		}, rand)
		if ev and ev.type == "spawn" then
			spawns += 1
			closest = math.huge
			if behavior == "stop" then waiting = true end
		end
		local plan = sched.active
		if plan and waiting and phase == "dwell" then
			if plan.locked and sidestep == nil then
				-- away from the locked lane, horizontally
				local vx, vz = plan.velocity.x, plan.velocity.z
				local hl = math.sqrt(vx * vx + vz * vz)
				local px, pz = 1, 0
				if opts.dodgeDegrees ~= nil then
					local ux, uz = 1, 0
					if hl > 1e-6 then ux, uz = vx / hl, vz / hl end
					local a = math.rad(opts.dodgeDegrees)
					px, pz = ux * math.cos(a) - uz * math.sin(a), uz * math.cos(a) + ux * math.sin(a)
				else
					if hl > 1e-6 then px, pz = -vz / hl, vx / hl end
					local here0 = Hazards.positionAt(plan, plan.t)
					local along = ((pos.x - here0.x) * vx + (pos.z - here0.z) * vz) / math.max(hl * hl, 1e-9)
					local cx, cz = here0.x + vx * along, here0.z + vz * along
					if (pos.x - cx) * px + (pos.z - cz) * pz < 0 then px, pz = -px, -pz end
				end
				sidestep = { x = px, z = pz, progress = 0 }
			elseif sidestep then
				sidestep.progress += dt
			end
		end
		if plan then
			local t0 = before or 0
			if Hazards.checkHit(plan, t0, plan.t, pos, cfg.Hazards.PlayerRadius) then
				plan.hit = true
				hits += 1
			end
			local d = Hazards.distance(Hazards.positionAt(plan, plan.t), pos)
			if d < closest then closest = d end
		end
		if ev and ev.type == "done" then
			local d = Hazards.distance(Hazards.positionAt(ev.plan, ev.plan.duration), pos)
			if d < closest then closest = d end
			if closest <= cfg.Hazards.NearMissStuds then nears += 1 end
			waiting = false
			sidestep = nil
		end

		-- advance the climber (a waiting climber stays put once on a platform)
		if not (waiting and phase == "dwell") then
			phaseLeft -= dt
		end
		if phaseLeft <= 0 then
			if phase == "dwell" then
				phase, phaseLeft = "air", air
			else
				tier, idx = nt, ni
				dwell, air = platformTimes(tier)
				phase, phaseLeft = "dwell", dwell
			end
		end
	end
	local minutes = limit / 60
	return {
		spawns = spawns,
		hits = hits,
		nears = nears,
		perMinute = spawns / minutes,
		nearPerMinute = nears / minutes,
		hitsPerMinute = hits / minutes,
		hitShare = if spawns > 0 then hits / spawns else 0,
		endTier = tier,
	}
end

return ClimbModel
