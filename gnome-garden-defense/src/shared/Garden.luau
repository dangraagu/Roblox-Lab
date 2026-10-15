--!strict
-- Garden.luau: one garden bed's simulation, as the server runs it (DESIGN.md §3, §12). Pure, no Roblox.
--
-- The balance model's sim (tests/GardenModel.luau measured every number in DESIGN.md with it), cut into the
-- calls a server makes: plant / upgrade / sell / ready, one fixed step of a wave, the end of a wave, the build
-- timer. tests/GardenModel.luau now plays THIS module, so the game and the measured model are one code path.
--
-- Rules (Garden.spec pins each): combat has no randomness; a hit loses the bug's armour but never below
-- ArmorFloor of the hit, and the lantern pierces; slows never stack (the strongest applies), snails ignore
-- them and bosses take half; a bug that reaches the patch bites its carrots, a boss bites all 20; a kill pays
-- the wave's bounty; surviving a wave pays its clear bonus. Every refusal returns the sentence the player
-- sees. Phases: reveal (a new bed; the first wave waits for READY) -> wave -> build (BuildSeconds, READY skips)
-- -> wave ... -> won (the chapter's tenth wave survived) | lost (the carrots are gone). An absent gardener's
-- build timer runs out into "held" instead of a wave.
--
-- Dependencies are arguments (a bare require("./X") resolves in the luau CLI and is invalid in Roblox):
-- Garden.new takes deps = { Waves, PathGen } and the garden keeps them.

local Garden = {}

local ACTIVE = { reveal = true, build = true, wave = true, held = true }

function Garden.unlocked(cfg: any, chapter: number): { [string]: boolean }
	local out = {}
	for c = 1, math.min(chapter, #cfg.Chapters) do
		for _, k in cfg.Chapters[c].unlock do out[k] = true end
	end
	return out
end

-- The gnome the game suggests next (the sheet stars it; the pads glow for it): the unlocked kind furthest below
-- its share of cfg.Suggest given `have` ({ [kind] = planted }), ties to the earlier kind in the sheet's order.
-- The pacing model's NORMAL player plants exactly this, on one of the glowing pads (REVIEW-2: the brag's minutes
-- assumed a player who knew the best pads for each gnome, which the screen did not show).
function Garden.suggestKind(cfg: any, chapter: number, have: { [string]: number }): string
	local unlocked = Garden.unlocked(cfg, chapter)
	local names = {}
	for k in unlocked do table.insert(names, k) end
	table.sort(names, function(a, b) return cfg.Gnomes[a].order < cfg.Gnomes[b].order end)
	local wsum, total = 0, 0
	for _, k in names do wsum += cfg.Suggest[k] or 0 end
	for k, n in have do
		if unlocked[k] then total += n end
	end
	local best, bestGap = names[1], -math.huge
	for _, k in names do
		local gap = (cfg.Suggest[k] or 0) / wsum * (total + 1) - (have[k] or 0)
		if gap > bestGap + 1e-9 then best, bestGap = k, gap end
	end
	return best
end

-- The chapter whose win unlocks `kind`'s season (its name, for "Lantern unlocks in Autumn").
local function unlockChapter(cfg: any, kind: string): number?
	for c, ch in cfg.Chapters do
		for _, k in ch.unlock do
			if k == kind then return c end
		end
	end
	return nil
end

function Garden.new(cfg: any, chapter: number, path: any, deps: any): any
	local Waves, PathGen = deps.Waves, deps.PathGen
	local ch = cfg.Chapters[chapter]
	local first = Waves.chapterFirstWave(cfg, chapter)
	return {
		deps = deps,
		chapter = chapter,
		endless = ch.endless == true,
		firstWave = first,
		lastWave = if ch.endless then nil else first + cfg.WavesPerChapter - 1,
		wave = first,                -- the wave being played, or the next one
		lastCleared = first - 1,     -- the highest wave survived on this bed
		seeds = ch.seeds,
		carrots = cfg.Carrots,
		path = path,
		pads = PathGen.pads(cfg, path),
		padUsed = {},                -- [padIndex] = gnome
		gnomes = {},                 -- { id, kind, level, pad, padIndex, cool, invested, mask }
		nextId = 1,
		bugs = {},                   -- { id, kind, hp, maxHp, s, speed, slowUntil, slow }
		nextBug = 1,
		queue = nil,
		qi = 1,
		waveT = 0,                   -- seconds into the current wave
		t = 0,                       -- garden seconds of waves on this bed
		phase = "reveal",
		buildLeft = 0,
		waveDone = false,
		killed = 0,
		leaked = 0,
		earned = 0,
		peak = 0,
	}
end

local function phaseRefusal(cfg: any, g: any): string?
	if g.phase == "won" then return cfg.Text.SeasonOver end
	if g.phase == "lost" then return cfg.Text.PatchLost end
	if not ACTIVE[g.phase] then return cfg.Text.SeasonOver end
	return nil
end

-- A pad id from the wire: a whole number naming one of THIS bed's pads, or nil.
local function padIndexOf(g: any, padIndex: any): number?
	if type(padIndex) ~= "number" or padIndex ~= padIndex or padIndex % 1 ~= 0 then return nil end
	if padIndex < 1 or padIndex > #g.pads then return nil end
	return padIndex
end

local function setMask(cfg: any, g: any, gn: any)
	local lv = cfg.Gnomes[gn.kind].levels[gn.level]
	gn.mask = g.deps.PathGen.rangeMask(g.path, gn.pad.cx, gn.pad.cz, lv.range)
end

-- (true, gnome) or (false, why)
function Garden.plant(cfg: any, g: any, kind: any, padIndex: any): (boolean, any)
	local refusal = phaseRefusal(cfg, g)
	if refusal then return false, refusal end
	local def = if type(kind) == "string" then cfg.Gnomes[kind] else nil
	if not def then return false, cfg.Text.UnknownGnome end
	if not Garden.unlocked(cfg, g.chapter)[kind] then
		local c = unlockChapter(cfg, kind)
		local season = if c then cfg.Chapters[c].name else "a later season"
		return false, string.format(cfg.Text.Locked, def.name, season)
	end
	local idx = padIndexOf(g, padIndex)
	if not idx then return false, cfg.Text.NoPad end
	if g.padUsed[idx] then return false, cfg.Text.PadTaken end
	if #g.gnomes >= cfg.MaxGnomes then return false, string.format(cfg.Text.GardenFull, cfg.MaxGnomes) end
	local cost = def.levels[1].cost
	if g.seeds < cost then return false, string.format(cfg.Text.NotEnoughSeeds, cost, g.seeds) end
	g.seeds -= cost
	local gn = { id = g.nextId, kind = kind, level = 1, pad = g.pads[idx], padIndex = idx, cool = 0, invested = cost }
	g.nextId += 1
	setMask(cfg, g, gn)
	g.padUsed[idx] = gn
	table.insert(g.gnomes, gn)
	return true, gn
end

-- (true, gnome) or (false, why)
function Garden.upgrade(cfg: any, g: any, padIndex: any): (boolean, any)
	local refusal = phaseRefusal(cfg, g)
	if refusal then return false, refusal end
	local idx = padIndexOf(g, padIndex)
	if not idx then return false, cfg.Text.NoPad end
	local gn = g.padUsed[idx]
	if not gn then return false, cfg.Text.NoGnome end
	local lv = cfg.Gnomes[gn.kind].levels[gn.level + 1]
	if not lv then return false, cfg.Text.MaxLevel end
	if g.seeds < lv.cost then return false, string.format(cfg.Text.NotEnoughSeeds, lv.cost, g.seeds) end
	g.seeds -= lv.cost
	gn.level += 1
	gn.invested += lv.cost
	setMask(cfg, g, gn)
	return true, gn
end

-- The share of what was paid in that a sale gives back now: everything on the reveal (no bug has walked yet, so
-- moving a gnome is free and a bare bed can never sell itself below one gnome), SellRefund after that.
function Garden.refundShare(cfg: any, g: any): number
	return if g.phase == "reveal" then cfg.RevealRefund else cfg.SellRefund
end

-- (true, refund) or (false, why). After the reveal a refund is SellRefund of everything paid in: a buy/sell loop
-- always loses.
function Garden.sell(cfg: any, g: any, padIndex: any): (boolean, any)
	local refusal = phaseRefusal(cfg, g)
	if refusal then return false, refusal end
	local idx = padIndexOf(g, padIndex)
	if not idx then return false, cfg.Text.NoPad end
	local gn = g.padUsed[idx]
	if not gn then return false, cfg.Text.NoGnome end
	local back = math.floor(gn.invested * Garden.refundShare(cfg, g))
	g.seeds += back
	g.padUsed[idx] = nil
	for i, x in g.gnomes do
		if x == gn then table.remove(g.gnomes, i) break end
	end
	return true, back
end

function Garden.startWave(cfg: any, g: any)
	local w = g.deps.Waves.wave(cfg, g.wave)
	g.queue = w.bugs
	g.qi = 1
	g.waveT = 0
	g.bugs = {}
	g.killed = 0
	g.leaked = 0
	g.waveDone = false
	g.phase = "wave"
end

-- (true) or (false, why). The first wave of a bed waits for this; later ones skip the build timer with it.
function Garden.ready(cfg: any, g: any): (boolean, string?)
	if g.phase == "wave" then return false, cfg.Text.AlreadyComing end
	local refusal = phaseRefusal(cfg, g)
	if refusal then return false, refusal end
	if g.phase == "reveal" and #g.gnomes == 0 then return false, cfg.Text.PlantFirst end
	Garden.startWave(cfg, g)
	return true, nil
end

-- A bug on the path (tests and the wave queue both use it).
function Garden.addBug(cfg: any, g: any, kind: string, hp: number, s: number?): any
	local b = { id = g.nextBug, kind = kind, hp = hp, maxHp = hp, s = s or 0, speed = cfg.Bugs[kind].speed,
		slowUntil = -1, slow = 1 }
	g.nextBug += 1
	table.insert(g.bugs, b)
	return b
end

local function hit(cfg: any, b: any, dmg: number, pierce: boolean?)
	local armor = if pierce then 0 else (cfg.Bugs[b.kind].armor or 0)
	b.hp -= math.max(dmg - armor, dmg * cfg.ArmorFloor)
end

local function inMask(g: any, mask: { boolean }, s: number): boolean
	local i = math.floor(s / g.path.step + 0.5) + 1
	return mask[i] == true
end

-- One fixed step of a wave. Returns nothing; with `ev` = { kills = {}, leaks = {} } it also lists what
-- happened ({ id, kind, bounty, s } per kill, { id, kind, bite } per leak). Sets g.waveDone when every bug of
-- the wave is gone (call Garden.finishWave), or g.phase = "lost" when the carrots run out.
-- The order inside a step is the model's: spawn, move and bite, gnomes fire, the dead pay.
function Garden.step(cfg: any, g: any, dt: number, ev: any?)
	if g.phase ~= "wave" or g.waveDone then return end
	local queue, bugs = g.queue, g.bugs
	local t = g.waveT
	-- spawn
	while g.qi <= #queue and queue[g.qi].at <= t + 1e-9 do
		local q = queue[g.qi]
		Garden.addBug(cfg, g, q.kind, q.hp, 0)
		g.qi += 1
	end
	-- move + bite
	local L = g.path.length
	for i = #bugs, 1, -1 do
		local b = bugs[i]
		local f = if b.slowUntil > t then b.slow else 1
		b.s += b.speed * f * dt
		if b.s >= L then
			local bite = cfg.Bugs[b.kind].bite
			g.carrots -= bite
			g.leaked += 1
			if ev then table.insert(ev.leaks, { id = b.id, kind = b.kind, bite = bite }) end
			table.remove(bugs, i)
		end
	end
	if g.carrots <= 0 then
		g.phase = "lost"
		g.t += t
		return
	end
	-- gnomes
	for _, gn in g.gnomes do
		gn.cool -= dt
		if gn.cool <= 0 then
			local def = cfg.Gnomes[gn.kind]
			local lv = def.levels[gn.level]
			if def.target == "pulse" then
				local fired = false
				for _, b in bugs do
					if b.hp > 0 and inMask(g, gn.mask, b.s) then
						fired = true
						hit(cfg, b, lv.dmg, false)
						local bd = cfg.Bugs[b.kind]
						if not bd.slowImmune then
							local f = lv.slow
							if bd.slowHalf then f = 1 - (1 - f) / 2 end
							if b.slowUntil <= t or f < b.slow then b.slow = f end
							b.slowUntil = t + lv.slowFor
						end
					end
				end
				if fired then
					gn.cool = lv.cd
					if ev and ev.shots then table.insert(ev.shots, { gnome = gn.id, pad = gn.padIndex }) end
				end
			else
				local target = nil
				for _, b in bugs do
					if b.hp > 0 and inMask(g, gn.mask, b.s) then
						if target == nil then
							target = b
						elseif def.target == "toughest" then
							if b.hp > target.hp then target = b end
						elseif b.s > target.s then
							target = b
						end
					end
				end
				if target then
					gn.cool = lv.cd
					if ev and ev.shots then table.insert(ev.shots, { gnome = gn.id, pad = gn.padIndex, bug = target.id }) end
					if def.splash then
						local PathGen = g.deps.PathGen
						local tx, tz = PathGen.posAt(g.path, target.s)
						local r2 = def.splash * def.splash
						for _, b in bugs do
							if b.hp > 0 then
								local bx, bz = PathGen.posAt(g.path, b.s)
								if (bx - tx) ^ 2 + (bz - tz) ^ 2 <= r2 then hit(cfg, b, lv.dmg, def.pierce) end
							end
						end
					else
						hit(cfg, target, lv.dmg, def.pierce)
					end
				end
			end
		end
	end
	-- the dead pay
	for i = #bugs, 1, -1 do
		local b = bugs[i]
		if b.hp <= 0 then
			local got = g.deps.Waves.bounty(cfg, b.kind, g.wave)
			g.seeds += got
			g.earned += got
			g.killed += 1
			if ev then table.insert(ev.kills, { id = b.id, kind = b.kind, bounty = got, s = b.s }) end
			table.remove(bugs, i)
		end
	end
	if #bugs > g.peak then g.peak = #bugs end
	g.waveT = t + dt
	if g.qi > #queue and #bugs == 0 then g.waveDone = true end
end

-- After g.waveDone: pay the clear bonus and move on. Returns the bonus. The chapter's last wave wins it;
-- the endless chapter never ends this way.
function Garden.finishWave(cfg: any, g: any): number
	if not g.waveDone then return 0 end
	local Waves = g.deps.Waves
	local bonus = Waves.clearBonus(cfg, g.wave)
	g.seeds += bonus
	g.earned += bonus
	g.t += g.waveT
	g.lastCleared = g.wave
	g.waveDone = false
	g.queue = nil
	if g.lastWave and g.wave >= g.lastWave then
		g.phase = "won"
	else
		g.wave += 1
		g.phase = "build"
		g.buildLeft = cfg.BuildSeconds
	end
	return bonus
end

-- The build timer, in garden seconds. `active` = the server saw this gardener act within AfkHoldSeconds.
-- Returns "started" when it starts the next wave, "held" when it runs out on an absent gardener.
function Garden.tickBuild(cfg: any, g: any, dt: number, active: boolean): string?
	if g.phase ~= "build" then return nil end
	g.buildLeft -= dt
	if g.buildLeft > 1e-9 then return nil end
	g.buildLeft = 0
	if active then
		Garden.startWave(cfg, g)
		return "started"
	end
	g.phase = "held"
	return "held"
end

-- Progress for the environment bands: waves survived + the share of this wave's bugs already STOPPED (a boss
-- counts its lost health while it lives, so the season turns as the boss gives ground). A bug that reaches the
-- patch is not progress: counting it put a lost boss wave on the next band's boundary, and losing to the Slug
-- Queen played the HARVEST MOON (REVIEW-1). So a lost wave always stays below its boundary, and a wave with
-- leaks reaches it when it is survived (finishWave).
function Garden.progress(cfg: any, g: any): number
	if (g.phase == "wave" or g.phase == "lost") and g.queue ~= nil and #g.queue > 0 then
		local gone = g.killed
		for _, b in g.bugs do
			if cfg.Bugs[b.kind].boss and b.maxHp > 0 then
				gone += math.clamp(1 - b.hp / b.maxHp, 0, 1)
			end
		end
		-- an unfinished wave never reaches its boundary: a boss with a sliver of health left rounded up onto it in
		-- the 3 decimals the server publishes, and named the next band while it still walked (the build's
		-- check_gnomegardendefense_frost). A wave counts only when every bug is gone and carrots remain.
		return (g.wave - 1) + math.min(cfg.ProgressInWaveMax, gone / #g.queue)
	end
	return g.lastCleared
end

return Garden
