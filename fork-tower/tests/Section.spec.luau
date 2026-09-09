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
