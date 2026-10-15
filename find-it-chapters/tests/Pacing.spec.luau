-- Pacing spec: the brag moment, the clocks and the hazard rate, measured on the real rules (DESIGN.md §4, §5, §8, §10).
-- Run: luau tests/Pacing.spec.luau 2>&1     (a few minutes; deterministic seeds)
--
-- Every clock in Config.Chapters / Config.Daily is the normal profile's UNCAPPED clear time (hint off, no
-- hazards, unlimited looks) at p97 for chapters 1-3, p90 for 4-15 and p98 for the Daily, rounded up to 5 s, on
-- rooms from the real Dressing. This spec fails if Config disagrees with that derivation.
-- DESIGN.md §10.1's assertions: the normal p50 BOOK ONE SOLVED within [30, 45] minutes; fast <= normal <= slow;
-- every band's normal p50 at least 2.5 minutes; the normal first-try Found at least 0.90 in every chapter; and the
-- near-miss interval within [2, 3] minutes of play. The hazard clock runs only on a legal spot, as the game's
-- (FinderModel.legal; REVIEW-1 round 2 D5: with every second counted, the model measured a rule the game does not use).
local FM = require("./FinderModel")
local Dressing = require("../src/shared/Dressing")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local POOL = 400
local specs = {}
for ch = 1, 15 do specs[ch] = Dressing.spec("book", ch, Config) end
local daily = Dressing.spec("daily", 20733, Config)
local pools = {}
for ch = 1, 15 do pools[ch] = FM.pool(specs[ch], POOL, 9000 + ch, Config) end
local dailyPool = FM.pool(daily, POOL, 9100, Config)
print(string.format("  rooms: %d per spec from Dressing.build", POOL))

local P = FM.PROFILES

--============================================================ the clocks, derived
print("== the clocks: normal uncapped clear time (hint off, no hazards, unlimited looks)")
local derived = {}
for ch = 1, 15 do
	local r = FM.rng(100 + ch)
	local ts = {}
	for _ = 1, 4000 do
		local room = pools[ch][r.below(POOL)]
		local res = FM.playHuman(room, specs[ch], P.normal, r, Config, { clock = 1e9, looks = false, hint = false })
		table.insert(ts, res.t)
	end
	local qt = if ch <= 3 then 0.97 else 0.90
	derived[ch] = FM.ceil5(FM.q(ts, qt))
	print(string.format("  ch%2d  p50 %6.1f s  p%d %6.1f s -> %3d s  (Config %3d)", ch, FM.median(ts), math.floor(qt * 100 + 0.5), FM.q(ts, qt), derived[ch], Config.Chapters[ch].clock))
	eq(Config.Chapters[ch].clock, derived[ch], "chapter " .. ch .. "'s clock equals the derivation")
end
do
	local r = FM.rng(900)
	local ts = {}
	for _ = 1, 4000 do
		local room = dailyPool[r.below(POOL)]
		table.insert(ts, FM.playHuman(room, daily, P.normal, r, Config, { clock = 1e9, looks = false, hint = false }).t)
	end
	local c = FM.ceil5(FM.q(ts, 0.98))
	print(string.format("  daily p50 %6.1f s  p98 %6.1f s -> %3d s  (Config %3d)", FM.median(ts), FM.q(ts, 0.98), c, Config.Daily.clock))
	eq(Config.Daily.clock, c, "the Daily's clock equals the derivation (p98)")
end

--============================================================ first try, with the clock, the hint and hazards
print("== first try (clock + hint + hazards mid-career): found / swift / sharp, out of looks")
for ch = 1, 15 do
	local row = {}
	for _, name in { "fast", "normal", "slow" } do
		local r = FM.rng(200 + ch * 7 + #name)
		local N = if name == "normal" then 2000 else 1000
		local f, w, s, ool = 0, 0, 0, 0
		for _ = 1, N do
			local hz = FM.hazardClock(r, Config)
			hz.exposed = r.uniform(0, Config.Hazards.IntervalMin)
			local room = pools[ch][r.below(POOL)]
			local res = FM.playHuman(room, specs[ch], P[name], r, Config, { hz = hz, pHit = P[name].p_hit, looks = true, hint = true })
			if res.stars.f then f += 1 end
			if res.stars.w then w += 1 end
			if res.stars.s then s += 1 end
			if res.outOfLooks then ool += 1 end
		end
		table.insert(row, string.format("%s %.2f/%.2f/%.2f (%d ool)", name, f / N, w / N, s / N, ool))
		if name == "normal" then
			truthy(f / N >= 0.90, string.format("chapter %d: the normal first-try Found %.3f >= 0.90", ch, f / N))
		end
	end
	print(string.format("  ch%2d  %s", ch, table.concat(row, "; ")))
end

--============================================================ the clue rules: a script reads faster, it does not search better
print("== the rules bot, the teleporting bot, tap-everything (looks n*k+2), on-clue searches")
for _, ch in { 1, 5, 8, 12, 15 } do
	local r = FM.rng(400 + ch)
	local bot, tele, brute, bruteSolves, sb, sn = {}, {}, {}, 0, {}, {}
	local N = 300
	for _ = 1, N do
		local room = pools[ch][r.below(POOL)]
		local rb = FM.playBot(room, specs[ch], r, Config)
		table.insert(bot, rb.t)
		table.insert(sb, rb.searches)
		table.insert(tele, FM.playBot(room, specs[ch], r, Config, true).t)
		table.insert(brute, FM.playBrute(room, specs[ch], r, Config, { clock = 1e9, looks = false }).t)
		if FM.playBrute(room, specs[ch], r, Config, { looks = true }).found then bruteSolves += 1 end
		local rn = FM.playHuman(room, specs[ch], P.normal, r, Config, { clock = 1e9, looks = true, hint = false })
		table.insert(sn, rn.searches - rn.off)
	end
	local expect = specs[ch].n * (specs[ch].k + 1) / 2
	print(string.format("  ch%2d  bot %5.1f s, teleport %5.1f s, tap-everything %5.1f s (solves %.2f) | on-clue searches bot %.2f, normal %.2f, N(k+1)/2 = %.1f",
		ch, FM.mean(bot), FM.mean(tele), FM.mean(brute), bruteSolves / N, FM.mean(sb), FM.mean(sn), expect))
	truthy(math.abs(FM.mean(sb) - expect) < 0.12 * expect and math.abs(FM.mean(sn) - expect) < 0.12 * expect,
		"chapter " .. ch .. ": the bot and the normal reader both search about N(k+1)/2 matching props")
	truthy(bruteSolves / N <= 0.40, string.format("chapter %d: tapping everything solves %.2f <= 0.40 (looks)", ch, bruteSolves / N))
end

--============================================================ careers: BOOK ONE SOLVED and the long-term goal
print("== careers from a fresh join (cards, moves, retries, hazards)")
local function careers(name, N, seed, gold, sweep)
	local r = FM.rng(seed)
	local runs = {}
	for _ = 1, N do table.insert(runs, FM.career(pools, specs, P[name], r, Config, gold, 600, sweep)) end
	return runs
end
local bandRanges = { { 1, 3 }, { 4, 6 }, { 7, 9 }, { 10, 12 }, { 13, 15 } }
local brag50 = {}
for _, row in { { "fast", 500, 601, true }, { "normal", 1000, 600, true }, { "slow", 500, 602, false } } do
	local name = row[1]
	FM.exposure.all, FM.exposure.legal = 0, 0
	local runs = careers(name, row[2], row[3], row[4], false)
	-- REVIEW-1 round 2 D5: the hazard clock runs on a legal spot only, as in the game (FinderModel.legal)
	print(string.format("  %-6s hazard exposure: %.3f of the time past the grace is on a legal spot", name, FM.exposure.legal / math.max(1e-9, FM.exposure.all)))
	if name == "normal" then
		local share = FM.exposure.legal / math.max(1e-9, FM.exposure.all)
		truthy(share > 0.5 and share < 0.99, string.format("the model's hazard clock skips the door mat and the walls (legal share %.3f)", share))
	end
	local brag, attempts, bands = {}, {}, {}
	for _, x in runs do
		table.insert(brag, x.clearAt[15])
		table.insert(attempts, x.attempts)
	end
	local bandMins = {}
	for bi, rg in bandRanges do
		local mins = {}
		for _, x in runs do
			table.insert(mins, x.clearAt[rg[2]] - (if rg[1] > 1 then x.clearAt[rg[1] - 1] else 0))
		end
		bandMins[bi] = FM.median(mins)
		table.insert(bands, string.format("%.1f", bandMins[bi]))
	end
	brag50[name] = FM.median(brag)
	print(string.format("  %-6s BOOK ONE SOLVED p10 %.1f / p50 %.1f / p90 %.1f min | attempts p50 %.1f | minutes per band %s",
		name, FM.q(brag, 0.1), brag50[name], FM.q(brag, 0.9), FM.median(attempts), table.concat(bands, " / ")))
	if row[4] then
		local gold, never = {}, 0
		for _, x in runs do
			table.insert(gold, x.goldAt or 600)
			if x.goldAt == nil then never += 1 end
		end
		local ff, c1 = {}, {}
		for _, x in runs do
			if x.firstFind then table.insert(ff, x.firstFind) end
			table.insert(c1, x.ch1Clear)
		end
		print(string.format("         Gold Book p50 %.1f min (p90 %.1f; %d of %d not by 600 min) | first find p50 %.1f s, chapter 1 cleared p50 %.1f s from join",
			FM.median(gold), FM.q(gold, 0.9), never, #runs, FM.median(ff), FM.median(c1)))
	end
	local hz, play = {}, {}
	local hits, total = 0, 0
	for _, x in runs do
		table.insert(hz, x.hazards)
		table.insert(play, x.bragT / 60)
		hits += x.hits
		total += x.hazards
	end
	local perHazard = FM.median(play) / math.max(1, FM.median(hz))
	local nearMiss = {}
	for _, x in runs do table.insert(nearMiss, x.bragT / 60 / math.max(1, x.hazards - x.hits)) end
	print(string.format("         hazards on the way: p50 %.1f, one per %.2f min of play, one near-miss per %.2f min (%d hit of %d)",
		FM.median(hz), perHazard, FM.median(nearMiss), hits, total))
	if name == "normal" then
		truthy(brag50.normal >= 30 and brag50.normal <= 45, string.format("normal BOOK ONE SOLVED p50 %.1f min is within [30, 45]", brag50.normal))
		for bi, m in bandMins do
			truthy(m >= 2.5, string.format("band %d lasts %.1f min (>= 2.5) for the normal profile", bi, m))
		end
		truthy(FM.median(nearMiss) >= 2 and FM.median(nearMiss) <= 3, string.format("one near-miss per %.2f min of play, within [2, 3]", FM.median(nearMiss)))
	end
end
truthy(brag50.fast <= brag50.normal and brag50.normal <= brag50.slow,
	string.format("fast %.1f <= normal %.1f <= slow %.1f", brag50.fast, brag50.normal, brag50.slow))
do
	local runs = careers("normal", 500, 610, false, true)
	local brag = {}
	for _, x in runs do table.insert(brag, x.clearAt[15]) end
	print(string.format("  sweeper BOOK ONE SOLVED p10 %.1f / p50 %.1f / p90 %.1f min (sensitivity: a player who walks the room and checks each prop)",
		FM.q(brag, 0.1), FM.median(brag), FM.q(brag, 0.9)))
end

--============================================================ the Daily Case
print("== the Daily Case")
for _, name in { "fast", "normal", "slow" } do
	local r = FM.rng(910 + #name)
	local f, mins = 0, {}
	local N = 3000
	for _ = 1, N do
		local room = dailyPool[r.below(POOL)]
		local hz = FM.hazardClock(r, Config)
		local res = FM.playHuman(room, daily, P[name], r, Config, { hz = hz, pHit = P[name].p_hit, looks = true, hint = true })
		if res.found then f += 1 end
		table.insert(mins, (res.spent + Config.Cards.IntroFirst + Config.Cards.Move + Config.Cards.Clear) / 60)
	end
	print(string.format("  %-6s solves on the first attempt %.3f; one attempt takes p50 %.1f min", name, f / N, FM.median(mins)))
	if name == "normal" then truthy(f / N >= 0.95, string.format("a normal player solves the Daily first try %.3f >= 0.95", f / N)) end
end
do
	local r = FM.rng(920)
	local br, bt = 0, {}
	for _ = 1, 500 do
		local room = dailyPool[r.below(POOL)]
		if FM.playBrute(room, daily, r, Config, { looks = true }).found then br += 1 end
		table.insert(bt, FM.playBot(room, daily, r, Config).t)
	end
	print(string.format("  tap-everything solves %.3f; the rules bot takes %.1f s mean", br / 500, FM.mean(bt)))
end

--============================================================ the hazard interval, against alternatives
print("== hazard interval (seconds of exposed time) vs near-misses per minute of play, normal, to BOOK ONE SOLVED")
do
	local save = { Config.Hazards.IntervalMin, Config.Hazards.IntervalMax }
	for _, iv in { { 80, 120 }, { 85, 120 }, { 100, 140 }, { 120, 180 } } do
		Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = iv[1], iv[2]
		local runs = careers("normal", 500, 700, false, false)
		local per, nm = {}, {}
		for _, x in runs do
			table.insert(per, x.bragT / 60 / math.max(1, x.hazards))
			table.insert(nm, x.bragT / 60 / math.max(1, x.hazards - x.hits))
		end
		print(string.format("  %3d-%3d s: one hazard per %.2f min (p10 %.2f, p90 %.2f), one near-miss per %.2f min",
			iv[1], iv[2], FM.median(per), FM.q(per, 0.1), FM.q(per, 0.9), FM.median(nm)))
	end
	Config.Hazards.IntervalMin, Config.Hazards.IntervalMax = save[1], save[2]
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing spec failed", 0) end
