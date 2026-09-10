-- Section.spec.luau — the geometry half of "no floor is unwinnable".
-- Run: luau tests/Section.spec.luau
--
-- Fork.luau promises that a trap is a toll and not a wall. This file is where that promise stops
-- being a sentence: it measures every platform of every section the tower can generate — both
-- doors, every theme, penalty and normal, far past the ten floors actually shipped — and asserts
-- that a player with NO TRAITS AT ALL can make every single jump.
--
-- Measured against the bare Humanoid, deliberately. Every floor grants a trait, so a real player
-- at floor 9 is carrying eight of them and jumps higher than this. Checking against the traits
-- they are likely to have would make the invariant depend on the choices they made, which is
-- exactly the thing that must never be able to strand anyone.
--
-- The horizontal reach is DERIVED rather than guessed: a Humanoid rises h studs under Roblox's
-- 196.2 gravity, so it is airborne for 2*sqrt(2h/g) seconds and covers WalkSpeed times that.
-- Config.Tower.GapMax has to fit inside Safety * that number, and the spec is what says so.

local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local Section = require("../src/shared/Section")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local THEMES = {}
for name in pairs(Config.Themes) do THEMES[#THEMES + 1] = name end
table.sort(THEMES)

-- Far past Config.Tower.Floors on purpose. The clamps in Config are what make the tower safe at
-- ANY number of floors; sweeping only the ten that ship would let a future `Floors = 40` walk
-- straight past a difficulty curve that has quietly outgrown a jump.
local DEEP = 200

local function eachSection(fn)
	for level = 1, DEEP do
		for _, theme in ipairs(THEMES) do
			for _, penalty in ipairs({ false, true }) do
				fn(Section.build(Config, 4242 + level, level, theme, penalty, Rng), level, theme, penalty)
			end
		end
	end
end

--============================================================================ derived reach

do
	local run = Section.maxJumpRun(Config)
	-- 7.2 studs of jump under 196.2 gravity is 0.5417 s airborne; at 16 studs/s that is 8.67.
	truthy(math.abs(run - 8.6694) < 0.01,
		string.format("a bare running jump covers %.3f studs", run))
	truthy(Config.Tower.GapMax <= Config.Tower.Safety * run,
		string.format("Config.Tower.GapMax (%.2f) fits inside Safety * reach (%.2f)",
			Config.Tower.GapMax, Config.Tower.Safety * run))
	truthy(Config.Tower.StepMax <= Config.Tower.Safety * Config.Jump.BaseJump,
		string.format("Config.Tower.StepMax (%.2f) fits inside Safety * BaseJump (%.2f)",
			Config.Tower.StepMax, Config.Tower.Safety * Config.Jump.BaseJump))

	-- The clearability proof below is measured against a player with NO traits. That is only a
	-- proof for every player if no trait can leave you WORSE than traitless — one "-2 speed"
	-- curse and the whole file stops covering the build that took it. This is the line that ties
	-- the trait table to the proof, and it belongs here rather than in the trait file precisely
	-- because it is a geometry constraint wearing a design costume.
	local negatives = {}
	for _, t in ipairs(Config.Traits) do
		if (t.jump or 0) < 0 or (t.speed or 0) < 0 then
			negatives[#negatives + 1] = t.id
		end
	end
	eq(#negatives, 0,
		"no trait lowers jump or speed, so the traitless proof covers every build ("
			.. table.concat(negatives, ",") .. ")")
end

--============================================================================ determinism

do
	local a = Section.build(Config, 99, 5, "fire", false, Rng)
	local b = Section.build(Config, 99, 5, "fire", false, Rng)
	eq(#a.platforms, #b.platforms, "the same arguments rebuild the same platform count")
	local same = true
	for i, p in ipairs(a.platforms) do
		local q = b.platforms[i]
		if p.dx ~= q.dx or p.dy ~= q.dy or p.dz ~= q.dz then same = false end
	end
	truthy(same, "...and the same platform positions")

	local other = Section.build(Config, 100, 5, "fire", false, Rng)
	local differs = false
	for i, p in ipairs(a.platforms) do
		local q = other.platforms[i]
		if q == nil or p.dx ~= q.dx or p.dz ~= q.dz then differs = true end
	end
	truthy(differs, "a different run seed lays out a different section")
end

--============================================================================ CLEARABILITY

do
	local badStep, badGap, badSize, worstStep, worstGap = 0, 0, 0, 0, 0
	local maxStep = Config.Tower.Safety * Config.Jump.BaseJump
	local maxGap = Config.Tower.Safety * Section.maxJumpRun(Config)

	eachSection(function(sec)
		local prev = nil
		for _, p in ipairs(sec.platforms) do
			if p.size <= 0 then badSize += 1 end
			if prev then
				local rise = p.dy - prev.dy
				if rise > worstStep then worstStep = rise end
				if rise > maxStep + 1e-9 then badStep += 1 end
				-- Edge to edge, not centre to centre: two square platforms of side `size` whose
				-- centres are `d` apart on one axis leave a `d - size` hole to clear.
				local dist = math.max(math.abs(p.dx - prev.dx), math.abs(p.dz - prev.dz))
				local hole = dist - p.size
				if hole > worstGap then worstGap = hole end
				if hole > maxGap + 1e-9 then badGap += 1 end
			end
			prev = p
		end
	end)

	eq(badSize, 0, "every platform has a positive size")
	eq(badStep, 0,
		string.format("NO FLOOR IS UNWINNABLE: every rise clears a traitless jump (worst %.2f of %.2f)",
			worstStep, maxStep))
	eq(badGap, 0,
		string.format("NO FLOOR IS UNWINNABLE: every gap clears a traitless running jump (worst %.2f of %.2f)",
			worstGap, maxGap))
end

do
	-- Two platforms in the same XZ column would put a ceiling over a jump, and the pure test
	-- would never see it because both are perfectly reachable in isolation. The walk forbids
	-- immediate reversals, which makes an XZ cell mathematically unrepeatable: you can only leave
	-- a left-run by going forward, so returning to a previous x always costs you a step in z.
	-- This is the assertion that keeps that property when somebody edits the direction table.
	local collisions = 0
	eachSection(function(sec)
		local seen = {}
		for _, p in ipairs(sec.platforms) do
			local key = string.format("%.4f|%.4f", p.dx, p.dz)
			if seen[key] then collisions += 1 end
			seen[key] = true
		end
	end)
	eq(collisions, 0, "no platform is ever stacked over another (no XZ cell is used twice)")
end

do
	-- The section has to actually go somewhere, and the exit has to be where the server puts the
	-- next fork. If those disagree the tower grows a gap that no jump can close.
	local badExit, tooShort = 0, 0
	eachSection(function(sec)
		local last = sec.platforms[#sec.platforms]
		if sec.exit.dx ~= last.dx or sec.exit.dy ~= last.dy or sec.exit.dz ~= last.dz then
			badExit += 1
		end
		if #sec.platforms < Config.Tower.PlatformsMin then tooShort += 1 end
	end)
	eq(badExit, 0, "the section's exit is its last platform")
	eq(tooShort, 0, "no section is shorter than PlatformsMin")
end

--============================================================================ hazards are fair

do
	local onFirst, onLast, doubled, tooMuch, tooTight = 0, 0, 0, 0, 0
	local worstCover, worstStrip = 0, math.huge

	eachSection(function(sec)
		local byPlatform = {}
		for _, hz in ipairs(sec.hazards) do
			if hz.platform == 1 then onFirst += 1 end
			if hz.platform == #sec.platforms then onLast += 1 end
			if byPlatform[hz.platform] then doubled += 1 end
			byPlatform[hz.platform] = true

			local p = sec.platforms[hz.platform]
			-- Overlap of the hazard's footprint with the platform top, both axis-aligned squares.
			local ox = math.max(0, math.min(p.dx + p.size / 2, hz.dx + hz.size / 2)
				- math.max(p.dx - p.size / 2, hz.dx - hz.size / 2))
			local oz = math.max(0, math.min(p.dz + p.size / 2, hz.dz + hz.size / 2)
				- math.max(p.dz - p.size / 2, hz.dz - hz.size / 2))
			local cover = (ox * oz) / (p.size * p.size)
			if cover > worstCover then worstCover = cover end
			if cover > Config.Fairness.MaxHazardCoverage then tooMuch += 1 end

			-- What is left to land on: the widest full-depth band of the platform top that the
			-- hazard does not touch. Written as the largest of the four bands rather than
			-- "size minus the overlap", because those are not the same number — a hazard parked
			-- in the MIDDLE of a platform leaves two narrow bands, not one wide one, and the
			-- subtraction version scored that as a comfortable 6 studs of landing room.
			local pxmin, pxmax = p.dx - p.size / 2, p.dx + p.size / 2
			local pzmin, pzmax = p.dz - p.size / 2, p.dz + p.size / 2
			local hxmin, hxmax = hz.dx - hz.size / 2, hz.dx + hz.size / 2
			local hzmin, hzmax = hz.dz - hz.size / 2, hz.dz + hz.size / 2
			local strip = 0
			strip = math.max(strip, math.min(hxmin, pxmax) - pxmin)
			strip = math.max(strip, pxmax - math.max(hxmax, pxmin))
			strip = math.max(strip, math.min(hzmin, pzmax) - pzmin)
			strip = math.max(strip, pzmax - math.max(hzmax, pzmin))
			strip = math.min(strip, p.size)
			if strip < worstStrip then worstStrip = strip end
			if strip < Config.Fairness.MinLandingStuds then tooTight += 1 end
		end
	end)

	eq(onFirst, 0, "no hazard sits on the platform you arrive on")
	eq(onLast, 0, "no hazard sits on the platform you leave from")
	eq(doubled, 0, "a platform never carries two hazards")
	eq(tooMuch, 0, string.format("no hazard covers more than %.0f%% of its platform (worst %.1f%%)",
		Config.Fairness.MaxHazardCoverage * 100, worstCover * 100))
	eq(tooTight, 0, string.format("every hazarded platform keeps a %.0f-stud landing strip (worst %.2f)",
		Config.Fairness.MinLandingStuds, worstStrip))
end

do
	-- Hazards have to actually appear, or "the trap section is busier" is a claim about nothing.
	local early, late = 0, 0
	for level = 1, Config.Tower.Floors do
		local sec = Section.build(Config, 7, level, "fire", false, Rng)
		if level < Config.Tower.HazardFromFloor then
			early += #sec.hazards
		else
			late += #sec.hazards
		end
	end
	eq(early, 0, "the first floors carry no hazards at all")
	truthy(late > 0, "the later floors do")
end

--============================================================================ the trap is a toll

do
	-- The whole shape of the punishment: longer and busier, never steeper or wider. A penalty
	-- section that raised the step would be a trap that can strand you, which is the one thing
	-- the game promises it is not.
	local shorter, steeper, wider, sameHazards = 0, 0, 0, 0
	for level = 1, DEEP do
		for _, theme in ipairs(THEMES) do
			local normal = Section.build(Config, 55 + level, level, theme, false, Rng)
			local trap = Section.build(Config, 55 + level, level, theme, true, Rng)
			if #trap.platforms <= #normal.platforms then shorter += 1 end
			if trap.step > normal.step + 1e-9 then steeper += 1 end
			if trap.gap > normal.gap + 1e-9 then wider += 1 end
			if level >= Config.Tower.HazardFromFloor and #trap.hazards <= #normal.hazards then
				sameHazards += 1
			end
		end
	end
	eq(shorter, 0, "the penalty section is always LONGER than the safe one")
	eq(steeper, 0, "...never steeper")
	eq(wider, 0, "...never wider")
	eq(sameHazards, 0, "...and always busier, once hazards exist at all")
end

--============================================================================ the lane corridor

do
	-- REVIEW FINDING 1. The server chains `forkTop[level + 1] = base + sec.exit`, so a section's
	-- exit X is the NEXT floor's fork origin and the tower's X is one long random walk over the
	-- whole run. Nothing bounded it. Chaining the real generator the way the server does measured
	-- 364.0 studs of drift in ten floors against a 220-stud lane (19.1% of runs finish outside
	-- their own slot) and 2942.2 studs over 500 floors — a tower standing inside a stranger's.
	--
	-- The bound belongs in the MODEL, not in a bigger LaneSpacing: a bigger spacing only moves
	-- the value at which the same walk collides again. Section.build takes the section origin's
	-- offset from the lane centre and refuses any step that would leave the corridor.
	local half = Config.World.CorridorHalfWidth

	-- The number has to MEAN something, so it is tied to the widest thing a lane contains.
	-- 30 = the summit pad (Main.server buildSummit); the fork and lobby pads are 26.
	local widestPad = 30
	truthy(half + widestPad / 2 <= Config.World.LaneSpacing / 2,
		string.format("the corridor (%.0f) plus the widest pad's half (%.0f) fits inside half a lane (%.0f)",
			half, widestPad / 2, Config.World.LaneSpacing / 2))

	-- Hundreds of floors, chained exactly as the server chains them.
	local worst, worstSeed, worstLevel = 0, 0, 0
	local exitWorst = 0
	for seed = 1, 60 do
		for _, theme in ipairs({ "fire", "void" }) do
			local laneX = 0
			for level = 1, 500 do
				local sec = Section.build(Config, seed, level, theme, level % 3 == 0, Rng, laneX)
				for _, p in ipairs(sec.platforms) do
					if math.abs(laneX + p.dx) > math.abs(worst) then
						worst, worstSeed, worstLevel = laneX + p.dx, seed, level
					end
				end
				laneX += sec.exit.dx
				exitWorst = math.max(exitWorst, math.abs(laneX))
			end
		end
	end
	truthy(math.abs(worst) <= half + 1e-9, string.format(
		"no platform of 500 chained floors leaves the corridor (worst %.1f at seed %d floor %d, bound %.0f)",
		worst, worstSeed, worstLevel, half))
	truthy(exitWorst <= half + 1e-9, string.format(
		"...and neither does the exit that becomes the next floor's fork origin (worst %.1f)", exitWorst))
	truthy(worstLevel > 0, "...and the sweep really walked the tower (the check is not vacuous)")

	-- The clamp must not buy its bound by breaking the invariant it shares the loop with: a
	-- rejected direction falls back to FORWARD, which is nobody's reverse, so an XZ cell still
	-- cannot repeat and no platform can sit over a jump.
	local repeats = 0
	for seed = 1, 200 do
		local laneX = 0
		for level = 1, 12 do
			local sec = Section.build(Config, seed, level, "ice", true, Rng, laneX)
			local seen = {}
			for _, p in ipairs(sec.platforms) do
				local cell = string.format("%.3f,%.3f", p.dx, p.dz)
				if seen[cell] then repeats += 1 end
				seen[cell] = true
			end
			laneX += sec.exit.dx
		end
	end
	eq(repeats, 0, "a clamped walk still never returns to an XZ cell it already used")
end

--============================================================================ a checkpoint you survive

do
	-- REVIEW FINDING 3. The checkpoint a platform hands the player was the platform's CENTRE, and
	-- a hazard stands 1.50 studs from that centre — inside a character that is 2.0 studs wide from
	-- the middle out. Measured across the built tower: 7200 of 7200 hazards overlapped the
	-- checkpoint their own platform hands you, so touching a hazard teleported you onto it.
	--
	-- Fixing the number (a bigger lift, a nudged offset) leaves the same defect waiting at another
	-- HazardBite. The model now names the point instead: Section.respawn is the platform's clear
	-- band, and Section.check enforces the clearance.
	local ch = Config.World.CharacterHalfWidth
	local inHazard, offPlatform, checked = 0, 0, 0
	-- THE NUMBERS, not just the signs. REVIEW-2's mutation M2 halved the respawn offset and every
	-- one of the 337 assertions in this repo stayed green, because this block only asked whether
	-- the two boxes overlap AT ALL: `if ox > 1e-9 and oz > 1e-9`. Any clearance above zero
	-- satisfies that, so the 2.00-stud number finding 3's fix rested on was defended by nothing,
	-- and a future tune of CharacterHalfWidth / HazardBite / HazardSize / TileSize could have taken
	-- it to 0.001 with the suite green.
	--
	-- What is asserted instead is the whole geometry, re-derived here from the section's own
	-- numbers rather than read out of Section.luau:
	--
	--   the hazard sits `d` studs from the platform centre on its own axis, and the character
	--   stands `t` studs the other way. Two constraints bound t:
	--     t <= p.size/2 - ch                (the whole character stays on the platform)
	--     t >= ch + hz.size/2 - |d|         (the character clears the hazard)
	--   so the feasible interval has width `band` = (p.size/2 - ch) - (ch + hz.size/2 - |d|),
	--   and — this is the part that makes it a real assertion — hazard clearance + edge margin
	--   equals `band` for EVERY t. Spending one buys the other, one stud for one stud. The only
	--   point that maximises the smaller of the two is the MIDPOINT, where both are band/2.
	--
	-- That single inequality kills two findings at once: M2 (clearance 0.75, edge 1.75 -> min 0.75
	-- < 1.00) and REVIEW-2's "the respawn point is FLUSH with the platform edge" (clearance 2.00,
	-- edge 0.00 -> min 0.00 < 1.00).
	local worstMin, worstBand, worstClear, worstEdge = math.huge, math.huge, math.huge, math.huge
	local offCentre = 0
	eachSection(function(sec)
		for _, hz in ipairs(sec.hazards) do
			local rp = Section.respawn(sec, hz.platform)
			local p = sec.platforms[hz.platform]
			checked += 1
			-- Two AABBs: the standing character, and the hazard cube.
			local ox = (hz.size / 2 + ch) - math.abs(hz.dx - rp.dx)
			local oz = (hz.size / 2 + ch) - math.abs(hz.dz - rp.dz)
			if ox > 1e-9 and oz > 1e-9 then
				inHazard += 1
			end
			-- And it is no good standing clear of the hazard in mid-air.
			if math.abs(rp.dx - p.dx) + ch > p.size / 2 + 1e-9
				or math.abs(rp.dz - p.dz) + ch > p.size / 2 + 1e-9 then
				offPlatform += 1
			end
			if rp.dy ~= p.dy then
				offPlatform += 1
			end

			local d = if hz.axis == "x" then hz.dx - p.dx else hz.dz - p.dz
			local r = if hz.axis == "x" then rp.dx - p.dx else rp.dz - p.dz
			local clear = math.abs(d - r) - (hz.size / 2 + ch)
			local edge = p.size / 2 - (math.abs(r) + ch)
			local band = (p.size / 2 - ch) - (ch + hz.size / 2 - math.abs(d))
			-- The character must retreat AWAY from the hazard, never past the platform centre
			-- toward it: r and d have to have opposite signs (or r is 0 on a hazard-free axis).
			if d * r > 1e-9 then
				offCentre += 1
			end
			worstMin = math.min(worstMin, math.min(clear, edge) - band / 2)
			worstBand = math.min(worstBand, band)
			worstClear = math.min(worstClear, clear)
			worstEdge = math.min(worstEdge, edge)
		end
	end)
	eq(inHazard, 0, "no platform's checkpoint puts the player inside the hazard standing on it")
	eq(offPlatform, 0, "...and every checkpoint keeps the whole character on its own platform")
	eq(offCentre, 0, "...and every checkpoint retreats AWAY from its hazard, never past the centre")
	truthy(checked > 0, "...and there were hazards to measure (the check is not vacuous)")
	truthy(worstBand > 0, string.format(
		"there is room to stand at all: the clear band is %.2f studs wide", worstBand))
	truthy(worstMin >= -1e-6, string.format(
		"the checkpoint sits at the MIDDLE of its clear band, not at either end "
			.. "(worst side is %.2f studs short of the %.2f-stud half-band; "
			.. "worst hazard clearance %.2f, worst platform-edge margin %.2f)",
		-worstMin, worstBand / 2, worstClear, worstEdge))
	print(string.format("  respawn band: %.2f studs wide, worst clearance %.2f, worst edge %.2f",
		worstBand, worstClear, worstEdge))

	-- A hazard-free platform hands back its own centre, so nothing moves where nothing is wrong.
	local plain = Section.build(Config, 12, 1, "fire", false, Rng, 0)
	local rp1 = Section.respawn(plain, 1)
	eq(rp1.dx, plain.platforms[1].dx, "a clear platform's checkpoint is its centre in x")
	eq(rp1.dz, plain.platforms[1].dz, "...and in z")
end

--============================================================================ Section.check bites

do
	-- Section.check is the runtime guard the server calls at startup, so it has to reject what
	-- the sweep above proves cannot happen — otherwise a config change ships silently.
	local good = Section.build(Config, 3, 7, "void", true, Rng)
	local ok, problems = Section.check(good, Config)
	truthy(ok, "Section.check passes a real section")
	eq(#problems, 0, "...with nothing to report")

	local broken = Section.build(Config, 3, 7, "void", true, Rng)
	broken.platforms[3].dy = broken.platforms[2].dy + 40
	broken.platforms[4].dy = broken.platforms[3].dy + 1
	local ok2, problems2 = Section.check(broken, Config)
	truthy(not ok2, "Section.check rejects a section with an unjumpable rise")
	truthy(#problems2 > 0, "...and says which platform")

	local wide = Section.build(Config, 3, 7, "void", false, Rng)
	wide.platforms[3].dx = wide.platforms[2].dx + 60
	local ok3 = Section.check(wide, Config)
	truthy(not ok3, "Section.check rejects a section with an unjumpable gap")

	-- The two guards the review's findings put here. A checker that passes everything is worse
	-- than no checker, so each one gets the section it exists to refuse.
	local strayed = Section.build(Config, 3, 7, "void", true, Rng)
	strayed.originX = Config.World.CorridorHalfWidth + 1
	local ok4, problems4 = Section.check(strayed, Config)
	truthy(not ok4, "Section.check rejects a section that has wandered out of its lane corridor")
	truthy(#problems4 > 0, "...and says how far off the centre line it is")

	local pinned = Section.build(Config, 3, 7, "void", true, Rng)
	local victim = pinned.hazards[1]
	truthy(victim ~= nil, "...the twin below has a hazard to move onto (not vacuous)")
	if victim then
		-- Exactly the old behaviour: hand the player back the platform's centre.
		pinned.platforms[victim.platform].safeDx = pinned.platforms[victim.platform].dx
		pinned.platforms[victim.platform].safeDz = pinned.platforms[victim.platform].dz
		local ok5, problems5 = Section.check(pinned, Config)
		truthy(not ok5, "Section.check rejects a checkpoint that sits inside its own hazard")
		truthy(#problems5 > 0, "...and says which platform and by how much")
	end

	-- CONTROL for this file. A theme is a colour and a material; it must not move a single stud.
	-- Without this, any change to Config.Themes would look like a geometry regression.
	local a = Section.build(Config, 31, 6, "fire", false, Rng)
	local b = Section.build(Config, 31, 6, "gold", false, Rng)
	local drift = 0
	eq(#a.platforms, #b.platforms, "CONTROL: the theme does not change the platform count")
	for i, p in ipairs(a.platforms) do
		local q = b.platforms[i]
		if q == nil or p.dx ~= q.dx or p.dy ~= q.dy or p.dz ~= q.dz or p.size ~= q.size then
			drift += 1
		end
	end
	eq(drift, 0, "CONTROL: switching the theme moves no geometry at all")
	truthy(a.theme ~= b.theme, "CONTROL: ...and the theme really did change (the control is not a no-op)")
end

--============================================================================ done

print(string.format("Section: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Section.spec failed", 0)
end
