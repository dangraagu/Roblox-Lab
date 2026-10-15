-- Pacing + balance: can a normal player win the first chapter, and when does the brag land?
-- Run: luau tests/Pacing.spec.luau     (from gnome-garden-defense/; about a minute of CPU)
--
-- docs/complete-game-standard.md §2: "A brag moment within about 30-45 minutes of normal play, and a
-- long-term goal beyond it. Measure the minutes with a pacing model in tests/." And the task note:
-- "Tower-defense balance is the hard part: measure every wave with a model in tests/ so that a normal
-- player can win the first chapter and the brag moment lands in about 30-45 min."
--
-- The model is tests/GardenModel.luau: the garden simulation (fixed 0.1 s step, the same rules the
-- server will run), the procedural bed generator, the wave formula, and three player PROFILES (weak,
-- normal, strong) whose decisions and reaction times are written down there, not hidden in a number.
-- Every bed is drawn from a seed, so every number this file prints is reproducible. DESIGN.md quotes
-- the printed lines; tests/WaveTable.luau prints the per-wave table.
--
-- BUILD NOTE (2026-10-07): the model now plays the game's own modules (src/shared/Garden.luau, PathGen.luau,
-- Waves.luau, Config.luau); only the profiles live in GardenModel.luau. Every number below is measured on the
-- code the server runs.

local G = require("./GardenModel")
local cfg = G.Config

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end
local function fmt(x) return string.format("%.1f", x) end
local function quant(t, p)
	local s = table.clone(t)
	table.sort(s)
	return s[math.min(#s, math.floor(#s * p) + 1)]
end

local SAMPLES = 40 -- beds per measurement; every one is a different procedural path

--=========================================================== the bed generator is what the design says

do
	local okLen, okEdges, okTouch, okPads, okSame = true, true, true, true, true
	local minPads, maxPads = math.huge, 0
	for s = 1, 200 do
		local p = G.genPath(cfg, G.newRng(1000 + s))
		if #p.cells ~= cfg.PathCells then okLen = false end
		if p.cells[1].x ~= 0 or p.cells[#p.cells].x ~= cfg.GridW - 1 then okEdges = false end
		-- no two path cells that are not neighbours on the path touch side by side
		local at = {}
		for i, c in p.cells do at[c.x .. "," .. c.y] = i end
		for i, c in p.cells do
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local j = at[(c.x + d[1]) .. "," .. (c.y + d[2])]
				if j and math.abs(j - i) ~= 1 then okTouch = false end
			end
		end
		local pads = G.pads(cfg, p)
		minPads = math.min(minPads, #pads)
		maxPads = math.max(maxPads, #pads)
		if #pads < cfg.MaxGnomes then okPads = false end
		local q = G.genPath(cfg, G.newRng(1000 + s))
		for i, c in q.cells do
			if c.x ~= p.cells[i].x or c.y ~= p.cells[i].y then okSame = false end
		end
	end
	truthy(okLen, "every bed's path is exactly PathCells long (difficulty must not depend on luck)")
	truthy(okEdges, "every path runs from the hedge gap (x = 0) to the carrot patch (x = GridW - 1)")
	truthy(okTouch, "no path touches itself side by side (a pad never sits ON a path)")
	truthy(okPads, "every bed has at least MaxGnomes pads (the cap, not the bed, limits a player)")
	truthy(okSame, "the same seed draws the same bed")
	print(("beds: %d cells, pads per bed %d..%d over 200 seeds"):format(cfg.PathCells, minPads, maxPads))
end

--=========================================================== every wave exists and escalates

do
	local okAll, okBoss, okGrow = true, true, true
	local prevHp = 0
	for n = 1, 60 do
		local w = G.wave(cfg, n)
		if #w.bugs == 0 then okAll = false end
		if (n % 10 == 0) ~= w.boss then okBoss = false end
		if not w.boss and n > 1 and w.totalHp < prevHp * 0.95 and not G.wave(cfg, n - 1).boss then okGrow = false end
		prevHp = w.totalHp
	end
	truthy(okAll, "waves 1-60 all have bugs")
	truthy(okBoss, "a boss on every tenth wave and only there")
	truthy(okGrow, "a non-boss wave is never easier than the one before it")
	local bossesBite = true
	for _, name in cfg.BossCycle do
		if cfg.Bugs[name].bite < cfg.Carrots then bossesBite = false end
	end
	truthy(bossesBite, "a boss that reaches the patch eats all of it: a chapter is won only by stopping its boss")
end

--=========================================================== the economy cannot be farmed

do
	truthy(cfg.SellRefund < 1, "SellRefund < 1: a buy/sell loop always loses seeds")
	local a = G.chapterStart(cfg, 2)
	local b = G.chapterStart(cfg, 2)
	truthy(a.seeds == b.seeds and a.carrots == cfg.Carrots, "a chapter always starts from the same seeds and carrots")
	-- an upgraded gnome keeps at least 95% of the damage per seed paid that planting gives (tuning round 4:
	-- when upgrades were worse value, the best play was level-1 spam that armour then made useless).
	-- The lowest today is the pebble at level 2: 17.5 dps for 120 seeds = 97% of level 1's 7.5 for 50.
	local ok = true
	for _, def in cfg.Gnomes do
		local paid, first = 0, nil
		for _, lv in def.levels do
			paid += lv.cost
			local perSeed = (lv.dmg / lv.cd) / paid
			first = first or perSeed
			if perSeed < first * 0.95 then ok = false end
		end
	end
	truthy(ok, "no upgrade drops a gnome below 95% of planting's damage per seed")
end

--=========================================================== chapter 1: a normal player wins it

local function winRate(profileName, chapter, opts)
	local wins, results = 0, {}
	for s = 1, SAMPLES do
		local rand = G.newRng(50000 + s * 7 + chapter)
		local path = G.genPath(cfg, rand)
		local r = G.playChapter(cfg, chapter, path, cfg.Pacing.Profiles[profileName], rand, opts)
		if r.won then wins += 1 end
		results[s] = r.won
	end
	return wins / SAMPLES, results
end

local wr = {}
for _, prof in { "weak", "normal", "strong" } do
	wr[prof] = {}
	for ch = 1, 4 do
		wr[prof][ch] = winRate(prof, ch, {})
	end
	print(("first-attempt win rate, %-6s: ch1 %3d%%  ch2 %3d%%  ch3 %3d%%  ch4 %3d%%"):format(prof,
		math.round(wr[prof][1] * 100), math.round(wr[prof][2] * 100), math.round(wr[prof][3] * 100), math.round(wr[prof][4] * 100)))
end
truthy(wr.normal[1] >= 0.95, "a normal player wins chapter 1 on the first try on >= 95% of beds (" .. fmt(wr.normal[1] * 100) .. "%)")
truthy(wr.weak[1] >= 0.75, "even a weak player wins chapter 1 on the first try on >= 75% of beds (" .. fmt(wr.weak[1] * 100) .. "%)")
truthy(wr.strong[1] == 1 and wr.strong[2] == 1 and wr.strong[3] == 1 and wr.strong[4] == 1,
	"a strong player wins every chapter on every bed (the content is beatable)")
truthy(wr.normal[3] >= 0.5 and wr.normal[3] < 1, "chapter 3 (the brag) is a real fight for a normal player: 50-99% first try (" .. fmt(wr.normal[3] * 100) .. "%)")
truthy(wr.normal[4] < wr.normal[3], "chapter 4 is harder than chapter 3 for a normal player (" .. fmt(wr.normal[4] * 100) .. "%)")

--=========================================================== hazards: rare, and a hit never decides a chapter

do
	local flips = 0
	for ch = 1, 4 do
		local _, dodged = winRate("normal", ch, {})
		local _, hitAll = winRate("normal", ch, { hitByEveryHazard = true })
		for s = 1, SAMPLES do
			if dodged[s] ~= hitAll[s] then flips += 1 end
		end
	end
	print(("hit by every hazard: %d of %d chapter outcomes change (normal, chapters 1-4)"):format(flips, 4 * SAMPLES))
	truthy(flips == 0, "a normal player hit by EVERY hazard wins and loses exactly the same chapters (" .. flips .. " changed)")
end

--=========================================================== the normal player plants where the game glows (REVIEW-2)
-- The brag's minutes below are a NORMAL player's. REVIEW-2: that player planted on one of the 3 best pads FOR EACH
-- GNOME'S RANGE, which the game never showed (it lit the 3 best pads only until the first gnome stood). Now the
-- game lights the 3 best FREE pads all game (Garden.client, PathGen.bestPads), and the normal profile plants on one
-- of exactly those. Checked on the model's own plants: every one is on a pad the screen shows glowing.

do
	local Garden = require("../src/shared/Garden")
	local PathGen = require("../src/shared/PathGen")
	local plain = Garden.plant
	local plants, off = 0, 0
	local offKind = 0
	Garden.plant = function(c, g, kind, pad)
		if g.path and g.pads and g.padUsed then
			local taken, have = {}, {}
			for id in g.padUsed do taken[id] = true end
			for _, gn in g.gnomes do have[gn.kind] = (have[gn.kind] or 0) + 1 end
			local suggested = Garden.suggestKind(c, g.chapter, have)
			local lit = PathGen.bestPads(c, g.path, g.pads, taken, c.Glow.Count, suggested)
			local onLit = false
			for _, id in lit do
				if id == pad then onLit = true end
			end
			plants += 1
			if not onLit then off += 1 end
			if kind ~= suggested then offKind += 1 end
		end
		return plain(c, g, kind, pad)
	end
	for s = 1, 4 do G.campaign(cfg, cfg.Pacing.Profiles.normal, 91000 + s, { stopAfterWave = 30 }) end
	Garden.plant = plain
	print(("normal profile, 4 campaigns to the brag: %d plants, %d of them off the glowing pads"):format(plants, off))
	truthy(plants > 0 and off == 0, "the normal player plants only on pads the game shows glowing (" .. off .. " of " .. plants .. " elsewhere)")
	truthy(offKind == 0, "and only the gnome the sheet stars (" .. offKind .. " others)")
end

--=========================================================== the brag lands in 30-45 minutes

local campaigns = {}
do
	local mins, worst = {}, 0
	local bragWave = cfg.Pacing.BragWave
	local hz, played = 0, 0
	for s = 1, SAMPLES do
		local c = G.campaign(cfg, cfg.Pacing.Profiles.normal, 90000 + s, {})
		campaigns[s] = c
		local m = c.minuteAtWave[bragWave] or math.huge
		table.insert(mins, m)
		worst = math.max(worst, m)
		hz += c.hazards
		played += c.minutes
	end
	local median = quant(mins, 0.5)
	local lo, hi = cfg.Pacing.BragMinutes[1], cfg.Pacing.BragMinutes[2]
	print(("brag (wave %d cleared), normal: median %s min, p10 %s, p90 %s, worst %s"):format(bragWave, fmt(median),
		fmt(quant(mins, 0.1)), fmt(quant(mins, 0.9)), fmt(worst)))
	truthy(median >= lo and median <= hi, "the median normal player clears wave " .. bragWave .. " within " .. lo .. "-" .. hi .. " min (" .. fmt(median) .. ")")
	truthy(quant(mins, 0.1) >= lo - 5, "even the luckiest tenth do not reach it far before " .. lo .. " min")
	truthy(worst < 75, "every sampled normal player reaches it in under 75 min (" .. fmt(worst) .. ")")
	local per = played / hz
	print(("hazards, normal: one per %s min of play"):format(string.format("%.2f", per)))
	truthy(per >= 2 and per <= 3, "about one hazard per 2-3 minutes of play (" .. string.format("%.2f", per) .. ")")
end

--=========================================================== the long-term goal and the board

do
	-- after chapter 4, the endless bed: how many normal players reach the Aurora (wave 50)?
	local goal = cfg.Pacing.LongTermWave
	local reached = { normal = 0, strong = 0 }
	for _, prof in { "normal", "strong" } do
		for s = 1, SAMPLES do
			local c = if prof == "normal" then campaigns[s] else G.campaign(cfg, cfg.Pacing.Profiles[prof], 90000 + s, {})
			if c.minuteAtWave[40] then
				local rand = G.newRng(123456 + s)
				local path = G.genPath(cfg, rand)
				local r = G.playChapter(cfg, #cfg.Chapters, path, cfg.Pacing.Profiles[prof], rand, { maxWave = 300 })
				if r.lastCleared >= goal then reached[prof] += 1 end
			end
		end
	end
	print(("wave %d (the Aurora) reached: normal %d/%d, strong %d/%d"):format(goal, reached.normal, SAMPLES, reached.strong, SAMPLES))
	truthy(reached.strong == SAMPLES, "a strong player always reaches the long-term goal")
	truthy(reached.normal > 0 and reached.normal < SAMPLES, "a normal player reaches it sometimes, not always (it is a goal)")

	local best = {}
	for _, prof in { "normal", "strong" } do
		local t = {}
		for s = 1, 12 do
			local rand = G.newRng(70000 + s)
			local path = G.genPath(cfg, rand)
			table.insert(t, G.endless(cfg, path, cfg.Pacing.Profiles[prof], rand))
		end
		table.sort(t)
		best[prof] = t
		print(("endless best wave, %-6s: %d..%d (median %d)"):format(prof, t[1], t[#t], t[7]))
	end
	truthy(best.strong[7] > best.normal[7] + 3, "a strong player gets clearly further than a normal one (the board ranks skill)")
	truthy(best.strong[#best.strong] < 200, "even the strong profile hits a ceiling (the metric is bounded)")
	truthy(best.strong[#best.strong] - best.strong[1] <= 6, "the bed changes the strong ceiling by at most 6 waves")
end

print(("%d passed, %d failed"):format(passed, failed))
