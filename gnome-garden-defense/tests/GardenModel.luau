--!nonstrict
-- GardenModel.luau: the TEST-SIDE pacing model for Gnome Garden Defense (DESIGN.md §4-§6).
--
-- What it is: three player PROFILES (weak, normal, strong) whose decisions and reaction times are written
-- down here, playing THE GAME'S OWN RULES: src/shared/Garden.luau (the sim the server steps), PathGen.luau
-- (the beds) and Waves.luau (the waves), with the numbers in src/shared/Config.luau. Until the build the sim
-- lived in this file; it moved to src/shared verbatim (Garden.spec, PathGen.spec and Waves.spec pin it), so
-- every minute and win rate tests/Pacing.spec.luau prints is measured on the code the server runs.
--
-- What it adds on top of the game: when a player acts (think), the build phases they let run, the time on
-- the reveal and result screens, and the hazard clock (a hit dazes the player: no action for DazeSeconds).

local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")
local PathGen = require("../src/shared/PathGen")
local Waves = require("../src/shared/Waves")
local Garden = require("../src/shared/Garden")

local M = {}
M.Config = Config
local DEPS = { Waves = Waves, PathGen = PathGen }
M.DEPS = DEPS

--=================================================================================== thin wrappers (the spec's API)
function M.newRng(seed: number): any
	return Rng.new(seed)
end
function M.genPath(cfg: any, rand: any): any
	return PathGen.genPath(cfg, rand)
end
function M.pads(cfg: any, path: any): { any }
	return PathGen.pads(cfg, path)
end
function M.rangeMask(path: any, cx: number, cz: number, range: number): ({ boolean }, number)
	return PathGen.rangeMask(path, cx, cz, range)
end
function M.wave(cfg: any, n: number): any
	return Waves.wave(cfg, n)
end
function M.bounty(cfg: any, kind: string, n: number): number
	return Waves.bounty(cfg, kind, n)
end
function M.chapterStart(cfg: any, chapter: number): any
	local ch = cfg.Chapters[chapter]
	return { seeds = ch.seeds, carrots = cfg.Carrots, chapter = chapter, firstWave = Waves.chapterFirstWave(cfg, chapter) }
end

--=================================================================================== the player

-- The "value" policy (the strong profile): plant or upgrade whatever adds the most damage per second
-- over covered path, per seed. A splash counts double, armour-piercing 1.2x. A sprinkler is worth its
-- own pulse damage plus (1/slow - 1) of the damage of the gnomes whose coverage it overlaps, counting
-- only path no other sprinkler already slows (slows do not stack). A heuristic of a good player, not an
-- optimum: tuning rounds 2-3 showed a plain "dps x cover" (and a slow bonus without the overlap rule)
-- builds sprinkler farms that lose to the first boss.
local function dpsOf(cfg: any, kind: string, level: number): number
	local def = cfg.Gnomes[kind]
	local lv = def.levels[level]
	local d = lv.dmg / lv.cd
	if def.splash then d *= 2 end
	if def.pierce then d *= 1.2 end
	return d
end

local function overlap(a: { boolean }, b: { boolean }): number
	local n = 0
	for i = 1, #a do
		if a[i] and b[i] then n += 1 end
	end
	return n
end

local function worth(cfg: any, st: any, kind: string, level: number, mask: { boolean }, cover: number, self: any): number
	local def = cfg.Gnomes[kind]
	local lv = def.levels[level]
	if def.target == "pulse" then
		local fresh = table.clone(mask)
		for _, g in st.gnomes do
			if g ~= self and cfg.Gnomes[g.kind].target == "pulse" then
				for i = 1, #fresh do
					if g.mask[i] then fresh[i] = false end
				end
			end
		end
		local boost = 0
		for _, g in st.gnomes do
			if g ~= self and cfg.Gnomes[g.kind].target ~= "pulse" then
				boost += dpsOf(cfg, g.kind, g.level) * overlap(g.mask, fresh) * st.path.step
			end
		end
		return (lv.dmg / lv.cd) * 2 * cover + (1 / lv.slow - 1) * boost
	end
	return dpsOf(cfg, kind, level) * cover
end

local function valuePlan(cfg: any, st: any): any
	local unlocked = Garden.unlocked(cfg, st.chapter)
	local best, bestRatio = nil, -math.huge
	if #st.gnomes < cfg.MaxGnomes then
		local names = {}
		for k in unlocked do table.insert(names, k) end
		table.sort(names, function(a, b) return cfg.Gnomes[a].order < cfg.Gnomes[b].order end)
		for _, k in names do
			local lv1 = cfg.Gnomes[k].levels[1]
			local bestPad, bestV = nil, -1
			for i, p in st.pads do
				if not st.padUsed[i] then
					local mask, cover = PathGen.rangeMask(st.path, p.cx, p.cz, lv1.range)
					local v = worth(cfg, st, k, 1, mask, cover, nil)
					if v > bestV then bestPad, bestV = i, v end
				end
			end
			if bestPad then
				local ratio = bestV / lv1.cost
				if ratio > bestRatio then best, bestRatio = { op = "plant", kind = k, pad = bestPad }, ratio end
			end
		end
	end
	for _, g in st.gnomes do
		local nxt = cfg.Gnomes[g.kind].levels[g.level + 1]
		if nxt then
			local m0, c0 = PathGen.rangeMask(st.path, g.pad.cx, g.pad.cz, cfg.Gnomes[g.kind].levels[g.level].range)
			local m1, c1 = PathGen.rangeMask(st.path, g.pad.cx, g.pad.cz, nxt.range)
			local ratio = (worth(cfg, st, g.kind, g.level + 1, m1, c1, g) - worth(cfg, st, g.kind, g.level, m0, c0, g)) / nxt.cost
			if ratio > bestRatio then best, bestRatio = { op = "up", g = g }, ratio end
		end
	end
	return best
end

-- The next thing this profile wants to do, or nil. A plan is { op = "plant", kind, pad } or { op = "up", g }.
local function nextPlan(cfg: any, st: any, prof: any, rand: any): any
	if prof.policy == "value" then return valuePlan(cfg, st) end
	local unlocked = Garden.unlocked(cfg, st.chapter)
	local want = prof.grow[st.chapter] or prof.grow[#prof.grow]
	local function plantPlan(): any
		if #st.gnomes >= cfg.MaxGnomes then return nil end
		-- a player who follows the game: the gnome the sheet stars, on one of the pads that glow for it (Garden.
		-- suggestKind, PathGen.bestPads: what Hud.client and Garden.client show all game). REVIEW-2: the normal
		-- profile planted on the best pads for each gnome's range, which the screen never showed
		if prof.glow then
			local standing = {}
			for _, g in st.gnomes do table.insert(standing, { pad = g.padIndex, kind = g.kind }) end
			local kind, lit = PathGen.glow(cfg, st.path, st.pads, standing, st.chapter, Garden.suggestKind)
			if #lit == 0 then return nil end
			return { op = "plant", kind = kind, pad = lit[rand:below(#lit)] }
		end
		-- the unlocked kind furthest below its share of the mix
		local have, total = {}, 0
		for _, g in st.gnomes do have[g.kind] = (have[g.kind] or 0) + 1; total += 1 end
		local names = {}
		for k in unlocked do table.insert(names, k) end
		table.sort(names, function(a, b) return cfg.Gnomes[a].order < cfg.Gnomes[b].order end)
		local wsum = 0
		for _, k in names do wsum += prof.mix[k] or 0 end
		local best, bestGap = nil, -math.huge
		for _, k in names do
			local share = (prof.mix[k] or 0) / wsum
			local gap = share * (total + 1) - (have[k] or 0)
			if gap > bestGap + 1e-9 then best, bestGap = k, gap end
		end
		-- pads ranked by how much path this gnome would cover
		local range = cfg.Gnomes[best].levels[1].range
		local ranked = {}
		for i, p in st.pads do
			if not st.padUsed[i] then
				local _, cover = PathGen.rangeMask(st.path, p.cx, p.cz, range)
				table.insert(ranked, { i = i, cover = cover })
			end
		end
		table.sort(ranked, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.i < b.i end)
		if #ranked == 0 then return nil end
		local pick = ranked[rand:below(math.min(prof.padTop, #ranked))]
		return { op = "plant", kind = best, pad = pick.i }
	end
	if #st.gnomes < want then return plantPlan() end
	-- upgrade: the lowest-level gnome, best coverage first
	local best = nil
	for _, g in st.gnomes do
		if cfg.Gnomes[g.kind].levels[g.level + 1] then
			if best == nil or g.level < best.level
				or (g.level == best.level and (g.cover or 0) > (best.cover or 0)) then
				best = g
			end
		end
	end
	if best then return { op = "up", g = best } end
	return plantPlan()
end

local function act(cfg: any, st: any, plan: any): boolean
	if plan == nil then return false end
	if plan.op == "plant" then
		local ok, g = Garden.plant(cfg, st, plan.kind, plan.pad)
		if ok then
			local _, cover = PathGen.rangeMask(st.path, g.pad.cx, g.pad.cz, cfg.Gnomes[g.kind].levels[1].range)
			g.cover = cover
		end
		return ok
	end
	return (Garden.upgrade(cfg, st, plan.g.padIndex))
end

-- A decision-maker for one attempt: call it with elapsed seconds; it acts once per `think`.
local function newThinker(cfg: any, st: any, prof: any, rand: any): (number) -> ()
	local acc = 0
	local plan = nil
	return function(dt: number)
		-- dazed by a hazard: no garden action until the daze wears off (the decision clock waits too)
		if (st.dazed or 0) > 0 then
			local use = math.min(dt, st.dazed)
			st.dazed -= use
			dt -= use
			if dt <= 0 then return end
		end
		acc += dt
		while acc >= prof.think do
			acc -= prof.think
			if plan == nil then plan = nextPlan(cfg, st, prof, rand) end
			if plan and act(cfg, st, plan) then plan = nil end
		end
	end
end

-- Hazards on the garden clock: returns a ticker that dazes the player when `hitAll` is set.
local function newHazardClock(cfg: any, st: any, rand: any, hitAll: boolean): (number, number) -> ()
	local h = cfg.Hazards
	local clock = 0
	local nextAt = h.IntervalMin + (h.IntervalMax - h.IntervalMin) * rand:next()
	return function(dt: number, wave: number)
		if wave < h.QuietBeforeWave then return end
		clock += dt
		if clock >= nextAt then
			nextAt = clock + h.IntervalMin + (h.IntervalMax - h.IntervalMin) * rand:next()
			st.hazards = (st.hazards or 0) + 1
			if hitAll then
				if h.DazeSeconds then st.dazed = h.DazeSeconds end
				local spill = math.min(math.ceil(st.seeds * (h.SpillShare or 0)), h.SpillCap or 0)
				st.seeds -= spill
				st.hazardSpilled += spill
			end
		end
	end
end

-- One wave on the bed, as the server steps it, with the player thinking between steps.
-- Returns { seconds, carrotsLost, lost }.
local function runWave(cfg: any, st: any, onStep: (number) -> ()): any
	local carrots0 = st.carrots
	Garden.startWave(cfg, st)
	local dt = cfg.Dt
	while true do
		Garden.step(cfg, st, dt)
		if st.phase == "lost" then
			return { seconds = st.waveT, carrotsLost = carrots0 - st.carrots, lost = true }
		end
		onStep(dt)
		if st.waveDone then break end
	end
	local seconds = st.waveT
	Garden.finishWave(cfg, st)
	return { seconds = seconds, carrotsLost = carrots0 - st.carrots, lost = false }
end

-- One attempt at a chapter on a bed. Returns { won, lastCleared, seconds, perWave = {...} }.
-- opts.hitByEveryHazard: the player never dodges. opts.endless: play until lost (cap opts.maxWave).
function M.playChapter(cfg: any, chapter: number, path: any, prof: any, rand: any, opts: any?): any
	local o = opts or {}
	local st = Garden.new(cfg, chapter, path, DEPS)
	st.hazardSpilled = 0
	local think = newThinker(cfg, st, prof, rand)
	local hazard = newHazardClock(cfg, st, rand, o.hitByEveryHazard == true)
	local seconds = 0
	-- The first wave of an attempt waits for READY: the player plants until their next plan is
	-- unaffordable (one decision per think), and takes at least introSeconds over the reveal.
	-- (Tuning round 10: with a fixed 25 s a normal player had spent 1000 of the endless 2600 seeds when
	-- wave 41 arrived, and lost it on 21 of 40 beds. The game must not auto-start a first wave.)
	local intro = 0
	for _ = 1, 200 do
		local before = st.seeds
		think(prof.think)
		intro += prof.think
		if st.seeds == before and intro >= prof.introSeconds then break end
	end
	seconds += intro
	local first = st.firstWave
	local last = if cfg.Chapters[chapter].endless then (o.maxWave or 300) else first + cfg.WavesPerChapter - 1
	local perWave = {}
	local lastCleared = first - 1
	for n = first, last do
		if n > first then
			local build = math.min(prof.buildSeconds, cfg.BuildSeconds)
			think(build)
			hazard(build, n)
			seconds += build
		end
		local r = runWave(cfg, st, function(dt)
			think(dt)
			hazard(dt, n)
		end)
		seconds += r.seconds
		local levels = 0
		for _, g in st.gnomes do levels += g.level end
		table.insert(perWave, { wave = n, seconds = r.seconds, carrotsLost = r.carrotsLost, carrots = st.carrots,
			gnomes = #st.gnomes, seeds = st.seeds, lost = r.lost, levels = levels })
		if r.lost then
			return { won = false, lastCleared = lastCleared, seconds = seconds, perWave = perWave, st = st, intro = intro }
		end
		lastCleared = n
	end
	return { won = true, lastCleared = lastCleared, seconds = seconds, perWave = perWave, st = st, intro = intro }
end

-- Endless (the last chapter) on a bed: the highest wave survived.
function M.endless(cfg: any, path: any, prof: any, rand: any): number
	local r = M.playChapter(cfg, #cfg.Chapters, path, prof, rand, { maxWave = 300 })
	return r.lastCleared
end

-- A whole campaign from chapter 1 to the end of chapter 4. EVERY attempt is a fresh bed (tuning round 6:
-- retrying the same bed left a deterministic player stuck on a bad layout; p90 to the brag was 64 min).
-- Returns { minuteAtWave = { [n] = minutes of play when wave n was first survived }, attempts, minutes, hazards }.
function M.campaign(cfg: any, prof: any, seed: number, opts: any?): any
	local o = opts or {}
	local rand = M.newRng(seed)
	local minuteAtWave, attempts = {}, {}
	local total, hazards = 0, 0
	local stopAt = o.stopAfterWave or (#cfg.Chapters - 1) * cfg.WavesPerChapter
	for chapter = 1, #cfg.Chapters - 1 do
		local tries = 0
		local done = false
		while not done and tries < 12 do
			tries += 1
			local path = M.genPath(cfg, rand) -- every attempt is a fresh bed
			local r = M.playChapter(cfg, chapter, path, prof, rand, o)
			-- the running clock, with the same accounting as playChapter (intro, build phases, waves)
			local clock = total + r.intro
			for i, pw in r.perWave do
				if i > 1 then clock += math.min(prof.buildSeconds, cfg.BuildSeconds) end
				clock += pw.seconds
				if not pw.lost and minuteAtWave[pw.wave] == nil then minuteAtWave[pw.wave] = clock / 60 end
			end
			total += r.seconds
			hazards += r.st.hazards or 0
			if r.won then
				total += prof.outroSeconds
				done = true
			else
				total += prof.retrySeconds
			end
		end
		attempts[chapter] = tries
		if not done then break end
		if chapter * cfg.WavesPerChapter >= stopAt then break end
	end
	return { minuteAtWave = minuteAtWave, attempts = attempts, minutes = total / 60, hazards = hazards }
end

return M
