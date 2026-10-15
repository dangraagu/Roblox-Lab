-- Garden.spec: the garden simulation the server runs (DESIGN.md §3, §12). Run: luau tests/Garden.spec.luau
--
-- Garden.luau is the balance model's sim (tests/GardenModel.luau measured every number with it) split into
-- server-sized calls: plant / upgrade / sell / ready, one fixed step, the end of a wave, the build timer.
-- Every refusal returns the sentence the player is shown.

local Garden = require("../src/shared/Garden")
local PathGen = require("../src/shared/PathGen")
local Waves = require("../src/shared/Waves")
local Rng = require("../src/shared/Rng")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function approx(a, b, msg, tol)
	tol = tol or 1e-9
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local cfg = Config
local DT = cfg.Dt
-- Dependencies are arguments (a bare require("./X") is invalid in Roblox); a garden keeps them.
local DEPS = { Waves = Waves, PathGen = PathGen }

local function bed(seed) return PathGen.genPath(cfg, Rng.new(seed)) end
-- a straight test lane along row 4: cells (0,4) .. (11,4); the path runs x = 0 .. 96 at z = 36
local function lane()
	local cells = {}
	for x = 0, 11 do table.insert(cells, { x = x, y = 4 }) end
	return PathGen.pathFromCells(cfg, cells)
end
local function padAt(g, x, y)
	for i, p in g.pads do
		if p.x == x and p.y == y then return i end
	end
	error("no pad at " .. x .. "," .. y)
end
-- play the bed's next wave to its end the way the server does (READY, fixed steps, finishWave): after it the
-- garden is in its build phase, which is where a sale pays SellRefund (REVIEW-1: the reveal refunds in full)
local function toBuild(g)
	assert(Garden.ready(cfg, g))
	local steps = 0
	while g.phase == "wave" and not g.waveDone do
		Garden.step(cfg, g, DT)
		steps += 1
		assert(steps < 100000, "a wave that never ends")
	end
	assert(g.waveDone, "toBuild: the wave was lost")
	Garden.finishWave(cfg, g)
	assert(g.phase == "build", "toBuild: not in the build phase")
end

--====================================================================== a fresh bed
do
	local g = Garden.new(cfg, 1, bed(1001), DEPS)
	eq(g.phase, "reveal", "a new bed waits on the reveal (the first wave waits for READY)")
	eq(g.seeds, 120, "chapter 1 starts with 120 seeds")
	eq(g.carrots, 20, "and 20 carrots")
	eq(g.wave, 1, "the next wave is wave 1")
	eq(#g.pads, 43, "the pads are the bed's pads (seed 1001: 43)")
	eq(Garden.progress(cfg, g), 0, "progress starts at the chapter's start")
	local g3 = Garden.new(cfg, 3, bed(1001), DEPS)
	eq(g3.seeds, 800, "chapter 3 starts with 800 seeds")
	eq(g3.wave, 21, "chapter 3 starts at wave 21")
	eq(Garden.progress(cfg, g3), 20, "progress starts at the chapter's start (20 waves survived)")
	local g5 = Garden.new(cfg, 5, bed(1001), DEPS)
	eq(g5.seeds, 2600, "the endless chapter starts with 2600 seeds")
	eq(g5.wave, 41, "and at wave 41")
end

--====================================================================== planting, and every refusal says why
do
	local g = Garden.new(cfg, 1, bed(1001), DEPS)
	local ok, msg = Garden.plant(cfg, g, "lantern", 1)
	eq(ok, false, "a lantern cannot be planted in spring")
	eq(msg, "Lantern unlocks in Autumn", "and the refusal says when it unlocks")
	ok, msg = Garden.plant(cfg, g, "mushroom", 1)
	eq(msg, "Mushroom unlocks in Summer", "a mushroom unlocks in summer")
	ok, msg = Garden.plant(cfg, g, "dandelion", 1)
	eq(msg, "Unknown gnome", "an unknown kind is refused by name")
	for _, bad in { 0, -1, #g.pads + 1, 1.5, "1", nil, math.huge, 0 / 0 } do
		ok, msg = Garden.plant(cfg, g, "pebble", bad :: any)
		eq(msg, "That is not one of your pads", "pad id " .. tostring(bad) .. " is refused")
	end
	eq(g.seeds, 120, "no refusal costs a seed")
	ok = Garden.plant(cfg, g, "pebble", 1)
	eq(ok, true, "a pebble on pad 1")
	eq(g.seeds, 70, "costs 50 seeds")
	eq(#g.gnomes, 1, "one gnome")
	eq(g.padUsed[1].kind, "pebble", "on pad 1")
	ok, msg = Garden.plant(cfg, g, "sprinkler", 1)
	eq(msg, "That pad is taken", "a taken pad says so")
	ok = Garden.plant(cfg, g, "pebble", 2)
	eq(g.seeds, 20, "a second pebble: 20 seeds left")
	ok, msg = Garden.plant(cfg, g, "pebble", 3)
	eq(ok, false, "a third pebble cannot be afforded")
	eq(msg, "Not enough seeds (need 50, have 20)", "and the refusal names both numbers")

	local g5 = Garden.new(cfg, 5, bed(1001), DEPS)
	for i = 1, cfg.MaxGnomes do
		assert(Garden.plant(cfg, g5, "pebble", i))
	end
	ok, msg = Garden.plant(cfg, g5, "pebble", cfg.MaxGnomes + 1)
	eq(msg, "Garden full: 14 gnomes", "the 15th gnome is refused: the cap, not the bed, limits a player")
end

--====================================================================== upgrading and selling
do
	local g = Garden.new(cfg, 2, bed(1002), DEPS)
	assert(Garden.plant(cfg, g, "pebble", 5))
	local seeds = g.seeds
	local ok, msg = Garden.upgrade(cfg, g, 5)
	eq(ok, true, "a pebble upgrades")
	eq(g.padUsed[5].level, 2, "to level 2")
	eq(seeds - g.seeds, 70, "for 70 seeds")
	ok = Garden.upgrade(cfg, g, 5)
	eq(g.padUsed[5].level, 3, "and to level 3 (130 more)")
	ok, msg = Garden.upgrade(cfg, g, 5)
	eq(ok, false, "level 3 is the top")
	eq(msg, "Max level", "and the refusal says so")
	ok, msg = Garden.upgrade(cfg, g, 6)
	eq(msg, "No gnome there", "upgrading an empty pad says there is no gnome")
	ok, msg = Garden.upgrade(cfg, g, 0)
	eq(msg, "That is not one of your pads", "upgrading a pad that does not exist is refused")
	toBuild(g) -- a sale after the first wave of the bed pays SellRefund
	local before = g.seeds
	local refund
	ok, refund = Garden.sell(cfg, g, 5)
	eq(ok, true, "a gnome sells")
	eq(refund, math.floor((50 + 70 + 130) * 0.7), "for 70% of everything paid into it (175)")
	eq(g.seeds - before, 175, "and the seeds arrive")
	eq(g.padUsed[5], nil, "the pad is free again")
	eq(#g.gnomes, 0, "and the gnome is gone")
	ok, msg = Garden.sell(cfg, g, 5)
	eq(msg, "No gnome there", "selling an empty pad says there is no gnome")
	-- a buy/sell loop always loses seeds
	local start = g.seeds
	for _ = 1, 10 do
		assert(Garden.plant(cfg, g, "sprinkler", 7))
		assert(Garden.sell(cfg, g, 7))
	end
	truthy(g.seeds < start, "ten plant/sell loops lose seeds (" .. start .. " -> " .. g.seeds .. ")")
	local g2 = Garden.new(cfg, 1, bed(1002), DEPS)
	assert(Garden.plant(cfg, g2, "pebble", 1))
	eq(g2.seeds, 70, "70 seeds after one pebble")
	ok = Garden.upgrade(cfg, g2, 1)
	eq(ok, true, "70 seeds buy level 2 exactly")
	ok, msg = Garden.upgrade(cfg, g2, 1)
	eq(msg, "Not enough seeds (need 130, have 0)", "level 3 with nothing left names both numbers")
end

--====================================================================== READY
do
	local g = Garden.new(cfg, 1, bed(1003), DEPS)
	local ok, msg = Garden.ready(cfg, g)
	eq(ok, false, "READY on an empty bed is refused")
	eq(msg, "Plant a gnome first", "and says to plant first")
	eq(g.phase, "reveal", "the bed still waits")
	assert(Garden.plant(cfg, g, "pebble", 1))
	ok = Garden.ready(cfg, g)
	eq(ok, true, "READY with a gnome starts the wave")
	eq(g.phase, "wave", "the bugs are coming")
	eq(#g.queue, 8, "wave 1's eight aphids")
	ok, msg = Garden.ready(cfg, g)
	eq(ok, false, "READY during a wave is refused")
	eq(msg, "The bugs are already coming!", "and says why")
end

--====================================================================== combat rules
local function freshWave(chapter, path)
	local g = Garden.new(cfg, chapter or 5, path or lane(), DEPS)
	g.phase = "wave"
	g.queue = {}
	g.qi = 1
	return g
end

-- targeting: "first" = furthest along, "toughest" = most hit points
do
	local g = freshWave(5)
	assert(Garden.plant(cfg, g, "pebble", padAt(g, 5, 3)))
	local a = Garden.addBug(cfg, g, "aphid", 100, 40) -- both inside the pebble's reach (s 32.5 .. 55.5)
	local b = Garden.addBug(cfg, g, "aphid", 100, 50)
	for _, x in g.bugs do x.speed = 0 end
	Garden.step(cfg, g, DT)
	eq(a.hp, 100, "a pebble leaves the bug further back alone")
	eq(b.hp, 94, "and hits the bug furthest along (6 damage)")
	local h = freshWave(5)
	assert(Garden.plant(cfg, h, "lantern", padAt(h, 5, 3)))
	local weak = Garden.addBug(cfg, h, "aphid", 50, 50)
	local tough = Garden.addBug(cfg, h, "aphid", 200, 30)
	for _, x in h.bugs do x.speed = 0 end
	Garden.step(cfg, h, DT)
	eq(weak.hp, 50, "a lantern ignores the weaker bug in front")
	eq(tough.hp, 155, "and burns the toughest (45 damage)")
end

-- armour, and the floor under it; the lantern pierces
do
	local g = freshWave(5)
	assert(Garden.plant(cfg, g, "sprinkler", padAt(g, 5, 3)))
	local beetle = Garden.addBug(cfg, g, "beetle", 100, 44)
	beetle.speed = 0
	Garden.step(cfg, g, DT)
	approx(beetle.hp, 99.5, "a 2-damage pulse on armour 2 still does its 25% floor (0.5)")
	local h = freshWave(5)
	assert(Garden.plant(cfg, h, "lantern", padAt(h, 5, 3)))
	local mantis = Garden.addBug(cfg, h, "mantis", 1000, 44)
	mantis.speed = 0
	Garden.step(cfg, h, DT)
	approx(mantis.hp, 955, "the lantern ignores armour 3 (45 damage)")
	local k = freshWave(5)
	assert(Garden.plant(cfg, k, "pebble", padAt(k, 5, 3)))
	local m2 = Garden.addBug(cfg, k, "mantis", 1000, 44)
	m2.speed = 0
	Garden.step(cfg, k, DT)
	approx(m2.hp, 997, "a pebble's 6 on armour 3 does 3")
end

-- the splash
do
	local g = freshWave(5)
	assert(Garden.plant(cfg, g, "mushroom", padAt(g, 5, 3)))
	local target = Garden.addBug(cfg, g, "aphid", 100, 50)
	local near = Garden.addBug(cfg, g, "aphid", 100, 44) -- 6 studs behind: inside the 7-stud splash
	local far = Garden.addBug(cfg, g, "aphid", 100, 42) -- 8 studs behind: outside it
	for _, x in g.bugs do x.speed = 0 end
	Garden.step(cfg, g, DT)
	eq(target.hp, 90, "the mushroom's target takes 10")
	eq(near.hp, 90, "a bug 6 studs from it takes the splash")
	eq(far.hp, 100, "a bug 8 studs away does not")
end

-- slows: the strongest applies, they never stack; snails ignore them; bosses take half
do
	local g = freshWave(5)
	assert(Garden.plant(cfg, g, "sprinkler", padAt(g, 5, 3)))
	assert(Garden.plant(cfg, g, "sprinkler", padAt(g, 5, 5)))
	assert(Garden.upgrade(cfg, g, padAt(g, 5, 5)))
	assert(Garden.upgrade(cfg, g, padAt(g, 5, 5)))
	local aphid = Garden.addBug(cfg, g, "aphid", 1000, 44)
	local snail = Garden.addBug(cfg, g, "snail", 1000, 44)
	local baron = Garden.addBug(cfg, g, "baron", 1000, 44)
	Garden.step(cfg, g, DT)
	approx(aphid.slow, 0.40, "two sprinklers: the strongest slow (0.40) applies, not 0.55 x 0.40")
	approx(snail.slow, 1, "a snail is already slow: sprinklers do not slow it")
	approx(baron.slow, 0.70, "a boss takes half of the slow: 1 - (1 - 0.40) / 2")
	local s0 = aphid.s
	Garden.step(cfg, g, DT)
	approx(aphid.s - s0, 6 * 0.40 * DT, "a slowed aphid walks 40% of its 6 studs/s")
end

-- leaks, bites, and the boss that eats the patch
do
	local g = freshWave(1)
	local a = Garden.addBug(cfg, g, "beetle", 100, g.path.length - 0.2)
	local ev = { kills = {}, leaks = {} }
	Garden.step(cfg, g, DT, ev)
	eq(g.carrots, 18, "a beetle that reaches the patch eats 2 carrots")
	eq(#ev.leaks, 1, "and the step reports the leak")
	eq(#g.bugs, 0, "it is gone from the path")
	truthy(g.phase ~= "lost", "18 carrots left: the garden is still standing")
	eq(g.waveDone, true, "the test lane's queue is empty: with the beetle gone the wave is over")
	g.waveDone = false -- put a boss on the same path
	Garden.addBug(cfg, g, "stag", 100, g.path.length - 0.1)
	Garden.step(cfg, g, DT)
	eq(g.phase, "lost", "a boss that reaches the patch eats all of it: the attempt is lost")
	truthy(g.carrots <= 0, "no carrots left")
	local _, msg = Garden.plant(cfg, g, "pebble", 1)
	eq(msg, "Not now: the bugs ate your carrots. Try again!", "a lost bed takes no more orders, and says why")
end

-- a kill pays the wave's bounty
do
	local g = freshWave(1)
	g.wave = 7
	assert(Garden.plant(cfg, g, "pebble", padAt(g, 5, 3)))
	local seeds = g.seeds
	local x = Garden.addBug(cfg, g, "aphid", 1, 44)
	x.speed = 0
	local ev = { kills = {}, leaks = {} }
	Garden.step(cfg, g, DT, ev)
	eq(#ev.kills, 1, "the step reports the kill")
	eq(g.seeds - seeds, Waves.bounty(cfg, "aphid", 7), "and pays the aphid's wave-7 bounty")
	eq(ev.kills[1].bounty, Waves.bounty(cfg, "aphid", 7), "the kill event carries the bounty")
end

--====================================================================== a whole wave, the end of it, and the season
local function playWave(g, plan)
	local steps = 0
	while not g.waveDone and g.phase == "wave" do
		Garden.step(cfg, g, DT)
		if plan then plan(g) end
		steps += 1
		assert(steps < 100000, "a wave that never ends")
	end
	if g.waveDone then return Garden.finishWave(cfg, g) end
	return nil
end
do
	local g = Garden.new(cfg, 1, bed(1001), DEPS)
	assert(Garden.plant(cfg, g, "pebble", 9))
	assert(Garden.plant(cfg, g, "pebble", 20))
	assert(Garden.ready(cfg, g))
	local mid = nil
	while not g.waveDone and g.phase == "wave" do
		Garden.step(cfg, g, DT)
		local p = Garden.progress(cfg, g)
		if mid == nil and p > 0 then mid = p end
	end
	truthy(mid ~= nil and mid > 0 and mid < 1, "progress moves inside wave 1, one bug at a time (" .. tostring(mid) .. ")")
	eq(g.waveDone, true, "wave 1 ends")
	local seeds = g.seeds
	local bonus = Garden.finishWave(cfg, g)
	eq(bonus, 18, "surviving wave 1 pays 18")
	eq(g.seeds - seeds, 18, "into the pouch")
	eq(g.lastCleared, 1, "wave 1 is survived")
	eq(g.wave, 2, "the next wave is 2")
	eq(g.phase, "build", "the build phase follows")
	eq(g.buildLeft, cfg.BuildSeconds, "with a 20 s timer")
	eq(Garden.progress(cfg, g), 1, "progress = waves survived")
	-- the build timer: it starts the next wave for an active gardener, and holds for an absent one
	local started = nil
	for _ = 1, 199 do started = Garden.tickBuild(cfg, g, DT, true) or started end
	eq(g.phase, "build", "19.9 s into the build phase: still building")
	started = Garden.tickBuild(cfg, g, DT, true)
	eq(started, "started", "at 20 s the next wave starts by itself")
	eq(g.phase, "wave", "wave 2 is on")
	local h = Garden.new(cfg, 1, bed(1001), DEPS)
	assert(Garden.plant(cfg, h, "pebble", 9))
	assert(Garden.ready(cfg, h))
	playWave(h)
	local held = nil
	for _ = 1, 200 do held = Garden.tickBuild(cfg, h, DT, false) or held end
	eq(held, "held", "a gardener the server has not seen act is not sent the next wave")
	eq(h.phase, "held", "the garden waits")
	local ok = Garden.ready(cfg, h)
	eq(ok, true, "READY from a held garden starts the wave")
	eq(h.phase, "wave", "and it is on")
end

-- a whole chapter: a rich scripted gardener wins spring, and the season ends there (balance is Pacing.spec's job)
do
	local g = Garden.new(cfg, 1, bed(1001), DEPS)
	g.seeds = 3000
	local ranked = {}
	for i, p in g.pads do
		local _, cover = PathGen.rangeMask(g.path, p.cx, p.cz, 14)
		table.insert(ranked, { i = i, cover = cover })
	end
	table.sort(ranked, function(a, b) if a.cover ~= b.cover then return a.cover > b.cover end return a.i < b.i end)
	local function plan(gg)
		-- pebbles on the 8 pads that see the most path, then upgrade whatever is affordable
		for k = 1, 8 do
			local idx = ranked[k].i
			if gg.padUsed[idx] == nil and gg.seeds >= 50 then Garden.plant(cfg, gg, "pebble", idx) end
		end
		for _, gn in gg.gnomes do
			local nxt = cfg.Gnomes[gn.kind].levels[gn.level + 1]
			if nxt and gg.seeds >= nxt.cost then Garden.upgrade(cfg, gg, gn.padIndex) end
		end
	end
	plan(g)
	assert(Garden.ready(cfg, g))
	local waves = 0
	while g.phase ~= "won" and g.phase ~= "lost" do
		if g.phase == "wave" then
			playWave(g, plan)
			waves += 1
		else
			plan(g)
			assert(Garden.ready(cfg, g))
		end
	end
	eq(g.phase, "won", "the scripted gardener wins spring")
	eq(waves, 10, "after ten waves")
	eq(g.lastCleared, 10, "wave 10 survived")
	local ok, msg = Garden.plant(cfg, g, "pebble", 30)
	eq(msg, "Not now: this season is over", "a won bed takes no more orders, and says why")
	eq(Garden.progress(cfg, g), 10, "progress = 10 once the Stag Beetle falls")
end

-- deterministic: the same bed and the same orders give the same garden, step for step
do
	local function run()
		local g = Garden.new(cfg, 2, bed(4242), DEPS)
		for i, idx in { 3, 9, 14, 20 } do
			Garden.plant(cfg, g, if i % 2 == 0 then "sprinkler" else "pebble", idx)
		end
		Garden.ready(cfg, g)
		local trace = {}
		for _ = 1, 3 do
			while g.phase == "wave" and not g.waveDone do Garden.step(cfg, g, DT) end
			if g.waveDone then Garden.finishWave(cfg, g); Garden.ready(cfg, g) end
			table.insert(trace, g.seeds .. "/" .. g.carrots .. "/" .. string.format("%.1f", g.t))
		end
		return table.concat(trace, " ")
	end
	local a, b = run(), run()
	eq(a, b, "two runs of the same orders on the same bed agree exactly (" .. a .. ")")
end

-- the endless chapter never ends in a win
do
	local g = Garden.new(cfg, 5, bed(1001), DEPS)
	g.wave = 50
	g.phase = "wave"
	g.queue = {}
	g.qi = 1
	g.waveDone = true
	Garden.finishWave(cfg, g)
	eq(g.phase, "build", "after wave 50 of the endless chapter comes wave 51")
	eq(g.wave, 51, "wave 51")
end

-- progress counts the boss's lost health inside its wave
do
	local g = Garden.new(cfg, 3, lane(), DEPS)
	g.wave = 30
	Garden.startWave(cfg, g)
	local total = #g.queue
	-- skip to the boss: every regular bug gone
	g.qi = total
	g.killed = total - 1
	local boss = Garden.addBug(cfg, g, "queen", 1000, 10)
	boss.maxHp = 1000
	approx(Garden.progress(cfg, g), 29 + (total - 1) / total, "with only the Queen left, progress is just under 30")
	boss.hp = 250
	approx(Garden.progress(cfg, g), 29 + (total - 1 + 0.75) / total, "a Queen at 25% health has moved the moon 3/4 of her share")
end

-- Found by the build (check_gnomegardendefense_frost): the server publishes progress rounded to 3 decimals, and a
-- boss with a sliver of health left (the last bug of its wave) rounded up ONTO the boundary. The Frost Mantis named
-- Moonlit Snow while it still walked (4 of 6 runs), and one run then lost that wave; a sliver of the Slug Queen
-- would play the HARVEST MOON before she falls, or for a loss. A wave counts only when every one of its bugs is gone.
do
	local g = Garden.new(cfg, 3, lane(), DEPS)
	g.wave = 30
	Garden.startWave(cfg, g)
	local total = #g.queue
	g.qi = total
	g.killed = total - 1
	local boss = Garden.addBug(cfg, g, "queen", 1000, 10)
	boss.maxHp = 1000
	local rawMost, publishedMost = 0, 0
	for _, hp in { 50, 10, 1, 0.1, 0.001 } do
		boss.hp = hp
		local p = Garden.progress(cfg, g)
		rawMost = math.max(rawMost, p)
		publishedMost = math.max(publishedMost, math.floor(p * 1000 + 0.5) / 1000) -- Main.server's rounding
	end
	truthy(rawMost <= 29.999 + 1e-9, string.format("a Queen with a sliver of health keeps progress at 29.999 or less (%.6f)", rawMost))
	truthy(publishedMost < 30, string.format("so the 3-decimal value the server publishes stays below 30 (%.3f)", publishedMost))
end

-- REVIEW-1 (reach): a bug that reaches the patch is not progress. Counting leaks as "gone" put a LOST boss wave
-- at the next band's boundary, so losing to the Slug Queen played the HARVEST MOON card and spent it.
do
	local g = Garden.new(cfg, 3, lane(), DEPS)
	g.wave = 30
	Garden.startWave(cfg, g)
	local total = #g.queue
	g.qi = total + 1 -- every bug of the wave has walked on
	g.killed = total - 1 -- and all but the Queen were stopped
	local boss = Garden.addBug(cfg, g, "queen", 1000, g.path.length - 0.05)
	boss.maxHp = 1000
	boss.hp = 900 -- she lost a tenth before she got through
	Garden.step(cfg, g, DT)
	eq(g.phase, "lost", "the Queen reaches the patch: the season is lost")
	local p = Garden.progress(cfg, g)
	truthy(p < 30, "a lost boss wave keeps progress below its boundary, so the HARVEST MOON never shows for a loss ("
		.. string.format("%.4f", p) .. ")")
	approx(p, 29 + (total - 1) / total, "it is the bugs actually stopped that count")
end
do
	-- a wave nobody defends: every aphid walks into the patch, and none of that is progress
	local g = Garden.new(cfg, 1, lane(), DEPS)
	Garden.startWave(cfg, g)
	local most = 0
	while g.phase == "wave" and not g.waveDone do
		Garden.step(cfg, g, DT)
		most = math.max(most, Garden.progress(cfg, g))
	end
	eq(g.leaked, 8, "all eight aphids got through")
	eq(most, 0, "and progress never moved while they did")
	Garden.finishWave(cfg, g)
	eq(Garden.progress(cfg, g), 1, "surviving the wave (12 carrots left) is what counts it")
end

-- REVIEW-1 (reach): moving a gnome before the bed's first wave costs nothing. With a 70% refund on the reveal,
-- five plant/sell tries left a spring bed at 0 gnomes and 45 seeds: no gnome affordable, READY refused, no restart.
do
	local g = Garden.new(cfg, 1, bed(1001), DEPS)
	assert(Garden.plant(cfg, g, "pebble", 9))
	local ok, back = Garden.sell(cfg, g, 9)
	eq(ok, true, "a gnome sells on the reveal")
	eq(back, 50, "for everything paid into it: a pebble gives back all 50")
	eq(g.seeds, 120, "so trying a pad before the first wave costs nothing")
	assert(Garden.plant(cfg, g, "pebble", 9))
	assert(Garden.upgrade(cfg, g, 9))
	ok, back = Garden.sell(cfg, g, 9)
	eq(back, 120, "an upgraded one too (50 + 70)")
	for _ = 1, 5 do -- the reviewer's sequence: tap a pad, Pebble, tap the gnome, SELL, five times
		Garden.plant(cfg, g, "pebble", 20)
		Garden.sell(cfg, g, 20)
	end
	eq(g.seeds, 120, "five tries later the bed still has its 120 seeds")
	-- the invariant, over 3000 random orders on the reveal: seeds + everything standing = the season's start
	local r = Rng.new(4711)
	local drift, fewest = 0, math.huge
	local kinds = { "pebble", "sprinkler", "mushroom" }
	for _ = 1, 3000 do
		local pad = Rng.below(r, #g.pads)
		local roll = Rng.next(r)
		if roll < 0.45 then
			Garden.plant(cfg, g, kinds[Rng.below(r, 2)], pad)
		elseif roll < 0.7 then
			Garden.upgrade(cfg, g, pad)
		else
			Garden.sell(cfg, g, pad)
		end
		local standing = 0
		for _, gn in g.gnomes do standing += gn.invested end
		if g.seeds + standing ~= 120 then drift += 1 end
		if #g.gnomes == 0 then fewest = math.min(fewest, g.seeds) end
	end
	eq(drift, 0, "on the reveal, seeds + everything planted is always the season's 120")
	truthy(fewest >= cfg.Gnomes.pebble.levels[1].cost, "so a bare reveal always affords a gnome (fewest seeds with none standing: "
		.. tostring(fewest) .. ")")
	-- after the first wave the refund is SellRefund again (a buy/sell loop loses)
	for _, gn in table.clone(g.gnomes) do Garden.sell(cfg, g, gn.padIndex) end
	local p1 = Garden.plant(cfg, g, "pebble", 9)
	local p2 = Garden.plant(cfg, g, "pebble", 20)
	eq(p1 and p2, true, "two pebbles for the first wave")
	if p1 and p2 then
		toBuild(g)
		local before = g.seeds
		ok, back = Garden.sell(cfg, g, 9)
		eq(back, math.floor(50 * cfg.SellRefund), "after the first wave a pebble sells for 70% again (35)")
		eq(g.seeds - before, 35, "and only that arrives")
	end
end

--====================================================================== the gnome the game suggests (REVIEW-2)
-- The sheet stars one gnome and the glowing pads are the best free ones FOR it: the unlocked kind furthest below
-- its share of Config.Suggest, ties to the earlier kind in the sheet's order. The pacing model's normal player
-- plants exactly that (DESIGN.md §4). The shares spelled out here: pebble 4, sprinkler 1.5, mushroom 2, lantern 1.5.
do
	eq(Garden.suggestKind(cfg, 1, {}), "pebble", "spring, nothing planted: a Pebble")
	eq(Garden.suggestKind(cfg, 1, { pebble = 2 }), "sprinkler", "two Pebbles in spring: a Sprinkler next (4 : 1.5)")
	eq(Garden.suggestKind(cfg, 1, { pebble = 2, sprinkler = 1 }), "pebble", "then a Pebble again")
	eq(Garden.suggestKind(cfg, 2, { pebble = 2, sprinkler = 1 }), "mushroom", "summer unlocks the Mushroom: it comes next")
	eq(Garden.suggestKind(cfg, 3, { pebble = 4, sprinkler = 1, mushroom = 2 }), "lantern", "autumn: the Lantern")
	eq(Garden.suggestKind(cfg, 1, { lantern = 5 }), "pebble", "a kind that is not unlocked is never suggested")
	-- by hand, the rule: share * (planted + 1) - planted of that kind, highest first
	local want = { pebble = 4, sprinkler = 1.5, mushroom = 2, lantern = 1.5 }
	local order = { "pebble", "sprinkler", "mushroom", "lantern" }
	local agree, total = 0, 0
	for p = 0, 5 do for sp = 0, 3 do for mu = 0, 3 do for la = 0, 3 do
		local have = { pebble = p, sprinkler = sp, mushroom = mu, lantern = la }
		local n = p + sp + mu + la
		local best, gap = nil, -math.huge
		for _, k in order do
			local g = want[k] / 9 * (n + 1) - have[k]
			if g > gap + 1e-9 then best, gap = k, g end
		end
		total += 1
		if Garden.suggestKind(cfg, 5, have) == best then agree += 1 end
	end end end end
	eq(agree, total, "the rule, checked by hand over " .. total .. " gardens (all four kinds unlocked)")
end

print(("Garden: %d passed, %d failed"):format(passed, failed))
