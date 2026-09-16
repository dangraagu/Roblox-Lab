-- Section.luau — one themed obby section, as a PURE function.
--
-- The geometry half of Fork Tower's first promise. Fork.luau decides which door is the trap;
-- this decides what is behind each of them, and it is where "no floor is unwinnable" stops being
-- a sentence and becomes arithmetic.
--
-- Returns plain tables of numbers. No Roblox global, no engine datatype, no service — the server
-- turns these into Parts and is the only place that knows what a Part is. Dependencies are
-- ARGUMENTS: a bare require("./Rng") resolves in the luau CLI and is INVALID in Roblox.
--
-- COORDINATES ARE SECTION-LOCAL, origin (0,0,0) at the fork platform you left. `dy` is the height
-- of a platform's WALKABLE TOP above that origin, not its centre — the server subtracts half the
-- thickness when it places the part. Every jump in this file is measured top-to-top, which is
-- what a player actually jumps between.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- THE PUNISHMENT IS LENGTH, NEVER HEIGHT
--
-- A trapped door builds the same section with `penalty = true`: more platforms and more hazards,
-- and byte-for-byte the same step and the same gap. That is the whole shape of the trap. A
-- penalty section that raised the step would be a trap that can strand a player who chose it,
-- and the tower would have a floor that some builds cannot finish. Section.spec asserts the
-- penalty section is longer, busier, and never steeper or wider, at every level out to 200.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- WHY THE REACH IS DERIVED AND NOT GUESSED
--
-- A Humanoid that rises h studs under gravity g is airborne for 2*sqrt(2h/g) seconds and travels
-- WalkSpeed times that. With Roblox's defaults — 7.2 studs of jump, 196.2 gravity, 16 studs/s —
-- that is 8.67 studs of ground covered, and Config.Tower.GapMax has to fit inside Safety times
-- it. Measured against the BARE Humanoid: every floor grants a trait, so a real player is jumping
-- higher than this by floor two, and an invariant that assumed the traits they picked would
-- depend on the choices it exists to protect.

local Section = {}

-- Forward-biased, and it can never immediately reverse. That second rule is doing real work: with
-- reversals allowed, right-then-left returns to the same XZ cell two steps up, putting a platform
-- directly over a jump — perfectly reachable in isolation, invisible to any per-jump check, and a
-- ceiling to bounce off in the actual game. Forbidding the reversal makes an XZ cell
-- mathematically unrepeatable: you can only leave a run of lefts by going forward, so coming back
-- to an earlier x always costs a step in z. Section.spec asserts the consequence.
local DIRS = {
	{ name = "fwd", dx = 0, dz = 1, opposite = "back" },
	{ name = "fwd", dx = 0, dz = 1, opposite = "back" },
	{ name = "fwd", dx = 0, dz = 1, opposite = "back" },
	{ name = "right", dx = 1, dz = 0, opposite = "left" },
	{ name = "left", dx = -1, dz = 0, opposite = "right" },
}

local HAZARD_KINDS = { "spike", "saw", "brand", "shard" }

local SEED_MIX = 7919
local RUN_MIX = 6151
local LEVEL_MIX = 3571
local PENALTY_MIX = 1299721
local RUN_SPAN = 1048576
local UINT32 = 4294967296

-- Same avalanche seeding as Fork, and for the same reason: an LCG seeded with an affine function
-- of (run, level) produces sections that march in a repeating pattern from floor to floor. See
-- the long note in Fork.luau — that mistake cost three red runs there and is not worth repeating
-- here for the sake of four fewer lines.
local function mul32(a: number, b: number): number
	local ah, al = math.floor(a / 65536), a % 65536
	local bh, bl = math.floor(b / 65536), b % 65536
	return ((ah * bl + al * bh) % 65536 * 65536 + al * bl) % UINT32
end

local function mix32(x: number): number
	x = math.floor(x) % UINT32
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 2246822507)
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = mul32(x, 3266489909)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x
end

local function clamp(n: number, lo: number, hi: number): number
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- How far a running jump carries, in studs, for a player with NO traits.
function Section.maxJumpRun(cfg): number
	local air = 2 * math.sqrt(2 * cfg.Jump.BaseJump / cfg.Physics.Gravity)
	return cfg.WalkSpeed * air
end

function Section.maxRise(cfg): number
	return cfg.Tower.Safety * cfg.Jump.BaseJump
end

function Section.maxGap(cfg): number
	return cfg.Tower.Safety * Section.maxJumpRun(cfg)
end

-- The difficulty curve, in one place so the spec and the server read the same numbers.
function Section.shape(cfg, level: number, penalty: boolean)
	local tw = cfg.Tower
	local step = clamp(tw.StepMin + (level - 1) * tw.StepPerFloor, tw.StepMin, tw.StepMax)
	local gap = clamp(tw.GapMin + (level - 1) * tw.GapPerFloor, tw.GapMin, tw.GapMax)
	local count = clamp(
		tw.PlatformsMin + math.floor((level - 1) * tw.PlatformsPerFloor),
		tw.PlatformsMin, tw.PlatformsMax)
	-- The penalty is added AFTER the clamp, so a trapped door is felt at every level, including
	-- the ones where the base length has already topped out.
	if penalty then
		count += tw.PenaltyExtraPlatforms
	end

	local hazards = 0
	if level >= tw.HazardFromFloor then
		hazards = clamp(
			1 + math.floor((level - tw.HazardFromFloor) / tw.HazardEveryNFloors), 1, tw.HazardMax)
		if penalty then
			hazards += tw.PenaltyExtraHazards
		end
	end
	-- Only the interior platforms can carry one: the platform you arrive on and the platform you
	-- leave from are always clear, so entering and exiting a section is never a hazard check.
	hazards = math.min(hazards, math.max(count - 2, 0))

	return step, gap, count, hazards
end

-- Section.build(cfg, runSeed, level, theme, penalty, Rng, originX) -> section
--
-- `originX` is where this section's origin sits relative to its LANE'S CENTRE LINE, and it is the
-- argument that keeps a tower inside its own lane. The server chains sections — each exit becomes
-- the next floor's fork origin — so without it the tower's X is a free random walk over the whole
-- run: 364 studs of drift in ten floors against a 220-stud lane, 2942 over five hundred, which is
-- a player's tower standing inside a stranger's. Every step below is refused if it would leave
-- +/- cfg.World.CorridorHalfWidth, and since the fallback is FORWARD (dx = 0), the exit is inside
-- the corridor too — so the next floor starts inside it, and the bound holds by induction for any
-- number of floors. Section.check re-derives it rather than trusting this loop.
--
-- section = {
--   level, theme, penalty, step, gap, tileSize, thickness, originX,
--   platforms = { { index, dx, dy, dz, size, safeDx, safeDz }, ... },  -- dy = walkable TOP
--   hazards   = { { platform, dx, dy, dz, size, kind, axis } , ... }, -- dy = hazard CENTRE
--   exit = { dx, dy, dz },                              -- where the next fork platform goes
-- }
function Section.build(cfg, runSeed: number, level: number, theme: string, penalty: boolean, Rng, originX: number?)
	assert(level >= 1, "Section.build: level must be >= 1")
	local tw = cfg.Tower
	local ox = originX or 0
	local corridor = cfg.World.CorridorHalfWidth

	local s = math.floor(runSeed)
	if s < 0 then s = -s end
	local raw = cfg.WorldSeed * SEED_MIX + (s % RUN_SPAN) * RUN_MIX + level * LEVEL_MIX
		+ (if penalty then PENALTY_MIX else 0)
	local rng = Rng.new(mix32(raw))

	local step, gap, count, hazardCount = Section.shape(cfg, level, penalty)
	local reach = tw.TileSize + gap -- centre to centre; the hole to clear is `gap`

	--------------------------------------------------------------------- the walk
	local platforms = {}
	local cx, cz = 0, 0
	local lastName = "none"
	-- A direction is refused for either reason, and for the SAME reason: the walk has to stay
	-- somewhere. Reversing puts a platform over a jump; leaving the corridor puts the tower in the
	-- neighbour's lane. Forward breaks neither, which is why it is the fallback for both.
	local function refused(d): boolean
		if d.opposite == lastName then
			return true
		end
		return math.abs(ox + cx + d.dx * reach) > corridor + 1e-9
	end
	for i = 1, count do
		-- Redraw rather than filter, so the forward bias in DIRS is preserved: filtering would
		-- quietly reweight the remaining directions every time a reversal was excluded.
		local d = DIRS[rng:below(#DIRS)]
		local tries = 0
		while refused(d) and tries < 8 do
			d = DIRS[rng:below(#DIRS)]
			tries += 1
		end
		if refused(d) then
			d = DIRS[1] -- forward: never the reverse of anything here, and dx = 0, so never outside
		end
		lastName = d.name
		cx += d.dx * reach
		cz += d.dz * reach
		platforms[i] = {
			index = i, dx = cx, dy = i * step, dz = cz, size = tw.TileSize,
			-- Overwritten below for any platform that ends up carrying a hazard.
			safeDx = cx, safeDz = cz,
		}
	end

	--------------------------------------------------------------------- hazards
	-- Interior platforms only, sampled WITHOUT replacement, so a platform never carries two.
	-- Two hazards on one platform is how a "40% covered" rule turns into a blocked platform.
	local eligible = {}
	for i = 2, count - 1 do
		eligible[#eligible + 1] = i
	end
	for i = #eligible, 2, -1 do
		local j = rng:below(i)
		eligible[i], eligible[j] = eligible[j], eligible[i]
	end

	-- The hazard intrudes `HazardBite` studs over the platform top from ONE edge, so what is left
	-- is a full-depth band of (TileSize - HazardBite) studs. That band is the landing area, and
	-- Section.check refuses to let it fall under Config.Fairness.MinLandingStuds.
	local offset = tw.TileSize / 2 + tw.HazardSize / 2 - tw.HazardBite
	local hazards = {}
	for n = 1, math.min(hazardCount, #eligible) do
		local idx = eligible[n]
		local p = platforms[idx]
		local axis = if rng:next() < 0.5 then "x" else "z"
		local sign = if rng:next() < 0.5 then -1 else 1
		hazards[n] = {
			platform = idx,
			dx = p.dx + (if axis == "x" then sign * offset else 0),
			dy = p.dy + cfg.Tower.PlatformThickness / 2 + tw.HazardSize / 2,
			dz = p.dz + (if axis == "z" then sign * offset else 0),
			size = tw.HazardSize,
			axis = axis,
			kind = HAZARD_KINDS[rng:below(#HAZARD_KINDS)],
		}

		-- WHERE IT IS SAFE TO STAND. The checkpoint used to be the platform's centre, and a hazard
		-- sits `offset` studs from that centre with its near face only TileSize/2 - HazardBite =
		-- 1.50 studs away — closer than a character is wide. So touching a hazard returned the
		-- player onto the hazard, which fired it again.
		--
		-- The clear band is on the far side, and it is an INTERVAL, not a point. Retreating `t`
		-- studs from the centre, away from a hazard whose centre is `d` studs off it:
		--     t <= p.size/2 - ch            (the whole character stays on the platform)
		--     t >= ch + hz.size/2 - |d|     (the whole character clears the hazard)
		-- and hazard clearance + platform-edge margin equals the WIDTH of that interval for every
		-- t inside it — one stud of clearance costs exactly one stud of edge. So the point that
		-- maximises the smaller of the two is the MIDDLE, and nothing else is.
		--
		-- The first fix took t = p.size/2 - ch, the far END: 2.00 studs from the hazard and 0.00
		-- from the drop, sitting exactly on Section.check's own boundary, with the player dropped
		-- onto it from RespawnLift studs up. The midpoint buys 1.00 and 1.00. Section.spec asserts
		-- the midpoint over every hazard it sweeps and Section.check refuses a section that leaves
		-- it, so neither end of the band can come back by a tuning change.
		local ch = cfg.World.CharacterHalfWidth
		local h = hazards[n]
		local d: number = if axis == "x" then h.dx - p.dx else h.dz - p.dz
		local tMin = ch + h.size / 2 - math.abs(d)
		local tMax = p.size / 2 - ch
		local t = (tMin + tMax) / 2
		-- Away from the hazard, always. A hazard sitting exactly on the centre line cannot happen
		-- for any config Section.check accepts, but retreating in a defined direction beats a
		-- coin flip if one ever did.
		local away = if d >= 0 then -1 else 1
		if axis == "x" then
			p.safeDx = p.dx + away * t
		else
			p.safeDz = p.dz + away * t
		end
	end

	local last = platforms[count]
	return {
		level = level,
		theme = theme,
		penalty = penalty,
		step = step,
		gap = gap,
		tileSize = tw.TileSize,
		thickness = tw.PlatformThickness,
		originX = ox,
		platforms = platforms,
		hazards = hazards,
		exit = { dx = last.dx, dy = last.dy, dz = last.dz },
	}
end

-- Where the server puts a player it is returning to platform `index`: a point on that platform
-- clear of whatever is standing on it, with `dy` the walkable TOP so the caller adds its own lift.
-- Callers must not reach for platform.dx/dz for this — that is the centre, and the centre is
-- exactly where the hazard is.
function Section.respawn(section, index: number)
	local p = section.platforms[index]
	if p == nil then
		return nil
	end
	return { dx = p.safeDx, dy = p.dy, dz = p.safeDz }
end

-- The runtime guard. The server calls this at startup for a spread of levels and warns loudly
-- rather than shipping a tower somebody cannot climb; Section.spec calls it on a real section and
-- on two deliberately broken ones, because a checker that passes everything is worse than none.
function Section.check(section, cfg): (boolean, { string })
	local problems = {}
	local maxRise, maxGap = Section.maxRise(cfg), Section.maxGap(cfg)

	local corridor = cfg.World.CorridorHalfWidth
	local laneOrigin = section.originX or 0

	local prev = nil
	for _, p in ipairs(section.platforms) do
		if p.size <= 0 then
			problems[#problems + 1] = string.format("platform %d has size %.2f", p.index, p.size)
		end
		-- Re-derived from the platform's own x, not trusted from the walk that placed it: this is
		-- the assertion that a tower cannot reach into the lane beside it.
		if math.abs(laneOrigin + p.dx) > corridor + 1e-9 then
			problems[#problems + 1] = string.format(
				"platform %d sits %.2f studs off the lane centre, past the %.2f corridor",
				p.index, laneOrigin + p.dx, corridor)
		end
		if prev then
			local rise = p.dy - prev.dy
			if rise > maxRise + 1e-9 then
				problems[#problems + 1] = string.format(
					"platform %d rises %.2f studs, past the %.2f a traitless jump clears", p.index, rise, maxRise)
			end
			local dist = math.max(math.abs(p.dx - prev.dx), math.abs(p.dz - prev.dz))
			local hole = dist - p.size
			if hole > maxGap + 1e-9 then
				problems[#problems + 1] = string.format(
					"platform %d is %.2f studs across the gap, past the %.2f a running jump clears",
					p.index, hole, maxGap)
			end
		end
		prev = p
	end

	local used = {}
	for _, hz in ipairs(section.hazards) do
		local p = section.platforms[hz.platform]
		if p == nil then
			problems[#problems + 1] = "a hazard is attached to a platform that does not exist"
		else
			if used[hz.platform] then
				problems[#problems + 1] = string.format("platform %d carries two hazards", hz.platform)
			end
			used[hz.platform] = true
			if hz.platform == 1 or hz.platform == #section.platforms then
				problems[#problems + 1] = string.format(
					"platform %d is an entry/exit platform and must stay clear", hz.platform)
			end

			local pxmin, pxmax = p.dx - p.size / 2, p.dx + p.size / 2
			local pzmin, pzmax = p.dz - p.size / 2, p.dz + p.size / 2
			local hxmin, hxmax = hz.dx - hz.size / 2, hz.dx + hz.size / 2
			local hzmin, hzmax = hz.dz - hz.size / 2, hz.dz + hz.size / 2
			local ox = math.max(0, math.min(pxmax, hxmax) - math.max(pxmin, hxmin))
			local oz = math.max(0, math.min(pzmax, hzmax) - math.max(pzmin, hzmin))
			local cover = (ox * oz) / (p.size * p.size)
			if cover > cfg.Fairness.MaxHazardCoverage then
				problems[#problems + 1] = string.format(
					"a hazard covers %.0f%% of platform %d", cover * 100, hz.platform)
			end
			-- The widest untouched full-depth band, not `size - overlap`: a hazard in the middle
			-- of a platform leaves two narrow bands and the subtraction would call that roomy.
			local band = 0
			band = math.max(band, math.min(hxmin, pxmax) - pxmin)
			band = math.max(band, pxmax - math.max(hxmax, pxmin))
			band = math.max(band, math.min(hzmin, pzmax) - pzmin)
			band = math.max(band, pzmax - math.max(hzmax, pzmin))
			band = math.min(band, p.size)
			if band < cfg.Fairness.MinLandingStuds then
				problems[#problems + 1] = string.format(
					"platform %d is left with a %.2f-stud landing band", hz.platform, band)
			end

			-- And the point the server actually returns a player to. A landing band nobody is
			-- placed in is a band that proves nothing: this is the assertion that says the
			-- checkpoint is IN it. Two AABBs — the standing character and the hazard cube — must
			-- be disjoint on at least one horizontal axis, and the character must be wholly on
			-- the platform rather than clear of the hazard in mid-air.
			local ch = cfg.World.CharacterHalfWidth
			local rp = Section.respawn(section, hz.platform)
			if rp == nil then
				problems[#problems + 1] = string.format("platform %d has no respawn point", hz.platform)
			else
				local gx = math.abs(hz.dx - rp.dx) - (hz.size / 2 + ch)
				local gz = math.abs(hz.dz - rp.dz) - (hz.size / 2 + ch)
				if gx < -1e-9 and gz < -1e-9 then
					problems[#problems + 1] = string.format(
						"platform %d's checkpoint is inside its own hazard (%.2f x %.2f studs of overlap)",
						hz.platform, -gx, -gz)
				end
				if math.abs(rp.dx - p.dx) + ch > p.size / 2 + 1e-9
					or math.abs(rp.dz - p.dz) + ch > p.size / 2 + 1e-9 then
					problems[#problems + 1] = string.format(
						"platform %d's checkpoint hangs the player off the edge", hz.platform)
				end

				-- AND IT MUST NOT SIT AT EITHER END OF THE BAND. Non-overlap alone is satisfied by
				-- 0.001 studs of clearance, which is how REVIEW-2's mutation M2 (the respawn offset
				-- halved) left all 337 assertions in this repo green while the real clearance fell
				-- from 2.00 studs to 0.75 — under the CharacterHalfWidth the whole model is built
				-- on. Hazard clearance and edge margin always sum to the width of the feasible
				-- band, so the midpoint is the only point where the smaller of the two is as large
				-- as it can be; anything else has spent one to buy the other.
				local hazOff: number = if hz.axis == "x" then hz.dx - p.dx else hz.dz - p.dz
				local rpOff: number = if hz.axis == "x" then rp.dx - p.dx else rp.dz - p.dz
				-- Named `clearBand` rather than `band`: the LANDING band above is a different
				-- measurement of a different thing, and shadowing it here would put two meanings
				-- of one word inside one loop body.
				local clearBand = (p.size / 2 - ch) - (ch + hz.size / 2 - math.abs(hazOff))
				if clearBand > 1e-9 then
					local clear = math.abs(hazOff - rpOff) - (hz.size / 2 + ch)
					local edge = p.size / 2 - (math.abs(rpOff) + ch)
					if math.min(clear, edge) < clearBand / 2 - 1e-6 then
						problems[#problems + 1] = string.format(
							"platform %d's checkpoint sits at the end of its clear band "
								.. "(%.2f studs of hazard clearance, %.2f of edge, band %.2f)",
							hz.platform, clear, edge, clearBand)
					end
				end
			end
		end
	end

	local last = section.platforms[#section.platforms]
	if last == nil then
		problems[#problems + 1] = "the section has no platforms"
	elseif section.exit.dx ~= last.dx or section.exit.dy ~= last.dy or section.exit.dz ~= last.dz then
		problems[#problems + 1] = "the exit is not the last platform"
	end

	return #problems == 0, problems
end

return Section
