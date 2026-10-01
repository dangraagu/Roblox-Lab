-- Pacing: minutes of PLAY to each band, the hazards' measured rarity, and the chase with and without them.
-- Run: luau tests/Pacing.spec.luau
--
-- Everything here is measured with tests/NightModel.luau, which plays the game's REAL rules forward
-- (Manor, Watcher, Night, Upgrades, the client's Hazards + Nightfall gate). The human parts are written
-- down in Config.Pacing. The owner's brief, as numbers:
--   * the big milestone (the Blood Moon) in about 30-45 minutes of play for a normal player; the last
--     band is the long-term goal;
--   * hazards: about one near-miss per 2-3 minutes, easy to see coming and avoid (docs/complete-game-standard.md §2).
--     Counted per minute IN THE MANOR (hazards never run in the safehouse), for every profile and for a player who
--     is rarely seen, pooled over three hazard seeds (second review, 2026-09-30: a single session's count is one
--     chaotic trajectory). A near-miss is a pass within NearHitStuds of a player who reads the ring; the hazards
--     SHOWN (near-misses, wide passes, and those called off by a sighting) must stay rare: never more often than one
--     per 1.5 manor-minutes;
--   * the chase was tuned carefully (ambushed runner caught 0/40, ignoring it caught 19/30) and the eye
--     candy must not change it.
local NightModel = require("./NightModel")
local Config = require("../src/shared/Config")
local EnvBands = require("../src/shared/EnvBands")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local bands = Config.Env.Bands
local HZ = { cfg = Config.Hazards, gate = Config.Hazards, bands = bands }

--================================================================ the model is Chase.spec's, still

-- NightModel.simulate is a copy of Chase.spec's simulation with hooks added. If the copy drifts, every
-- minute below is a different game's. So it must reproduce Chase.spec's printed numbers exactly.
do
	local c, seen = 0, 0
	for n = 1, 20 do
		local r = NightModel.simulate(n, {}, "ambush")
		if r.caught then c += 1 end
		if r.spotted then seen += 1 end
	end
	eq(c, 0, "CONTROL: the model's ambushed runner is caught on 0 of nights 1-20, as in Chase.spec")
	eq(seen, 20, "CONTROL: ...and seen on all 20")
	local lc, lo = 0, 0
	for n = 1, 30 do
		local r = NightModel.simulate(n, {}, "loot")
		if r.caught then lc += 1 elseif r.out then lo += 1 end
	end
	eq(lc, 19, "CONTROL: the model's greedy looter is caught on 19 of 30, as in Chase.spec")
	eq(lo, 11, "CONTROL: ...and clears 11")
	local eo, ec = 0, 0
	for n = 1, 30 do
		local r = NightModel.simulate(n, {}, "exit")
		if r.out then eo += 1 elseif r.caught then ec += 1 end
	end
	eq(eo, 25, "CONTROL: the exit walker gets out on 25 of 30, as in Chase.spec")
	eq(ec, 5, "CONTROL: ...and is caught on 5")
end

--================================================================ minutes of play to each band

local function session(profile: string, react: boolean?)
	return NightModel.session({
		human = Config.Pacing.Profiles[profile], minutes = 200,
		hazards = { cfg = HZ.cfg, gate = HZ.gate, bands = HZ.bands, react = if react == nil then true else react },
	})
end

local runs = {}
for _, prof in { "normal", "fast", "slow" } do
	runs[prof] = session(prof)
end

local function minutesTo(s: any, night: number): number?
	if night <= 1 then return 0 end
	return s.reachedAt[night]
end

print("  minutes of play to the first night of each band (hazards on, a player who reacts to them):")
print("  band                       night   normal    fast    slow")
for _, b in bands do
	local n = math.max(b.from, 1)
	local function f(x: number?): string
		return if x then string.format("%7.1f", x) else "    n/a"
	end
	print(string.format("  %-26s %5d  %s %s %s", b.emoji .. " " .. b.name, n,
		f(minutesTo(runs.normal, n)), f(minutesTo(runs.fast, n)), f(minutesTo(runs.slow, n))))
end
for prof, s in runs do
	print(string.format("  %-6s: %d nights in %.0f min; %d attempts, %d caught, %d evicted, %d dashes; manor %.0f%% of play, safehouse %.0f%%",
		prof, s.nights, s.totalSeconds / 60, s.attempts, s.caught, s.evicted, s.dashes,
		100 * s.manorSeconds / s.totalSeconds, 100 * s.daySeconds / s.totalSeconds))
end

do
	local flagIdx = EnvBands.indexOf(bands, Config.Env.FlagshipBandId)
	truthy(flagIdx ~= nil, "the flagship band exists")
	local flag = flagIdx and bands[flagIdx]
	local at = flag and minutesTo(runs.normal, flag.from)
	print(string.format("  the single normal session above reaches the %s at %s min", flag and flag.name or "?", tostring(at and string.format("%.1f", at))))

	-- The brag moment, measured on a POPULATION, not one trajectory (second review, 2026-09-30: the old gate asserted
	-- one session, and moving the model's start-of-night pause by 0-30 s put the Blood Moon anywhere from 26.7 to
	-- 47.5 min, 12 of 31 outside 30-45). 31 normal players, each 0-30 s slower to get their bearings every night,
	-- both as the model always played (it knows every manor's layout) and as a FIRST-TIME player, who knows only the
	-- rooms they have entered or seen through a doorway and explores until they find the relics and the exit (a
	-- retry of the same night remembers what it walked). The median must land in 30-45 minutes, and so must at
	-- least half of the players.
	local function population(search: boolean): { number }
		local out = {}
		for k = 0, 30 do
			local human = table.clone(Config.Pacing.Profiles.normal)
			human.startSeconds += k
			local s = NightModel.session({ human = human, minutes = 90, nightCap = flag.from, search = search,
				hazards = { cfg = HZ.cfg, gate = HZ.gate, bands = HZ.bands, react = true } })
			table.insert(out, s.reachedAt[flag.from] or math.huge)
		end
		return out
	end
	-- CONTROL: the first-time player really searches. On nights 1-12, the nights both players get out of take the
	-- searcher longer in all (it has to find the relics and the exit), and it does not walk every room every night.
	do
		local knowT, searchT, partial = 0, 0, 0
		for n = 1, 12 do
			local o = NightModel.simulate(n, {}, "normal", { human = Config.Pacing.Profiles.normal })
			local s = NightModel.simulate(n, {}, "normal", { human = Config.Pacing.Profiles.normal, search = true })
			if o.out and s.out then
				knowT += o.at
				searchT += s.at
			end
			local v = 0
			for _ in s.visited or {} do v += 1 end
			if v > 0 and v < #s.plan.rooms then partial += 1 end
		end
		print(string.format("  a first-time player on nights 1-12: %.0f s to get out where the one who knows the layout takes %.0f s; it walked only part of the manor on %d nights",
			searchT, knowT, partial))
		truthy(searchT > knowT, string.format("CONTROL: a first-time player takes longer to find its way out (%.0f vs %.0f s)", searchT, knowT))
		truthy(partial >= 6, string.format("CONTROL: ...and explores rooms one by one, rarely all of them (%d of 12 nights partial)", partial))
	end
	for _, search in { false, true } do
		local mins = population(search)
		local sorted = table.clone(mins)
		table.sort(sorted)
		local inside = 0
		for _, m in mins do
			if m >= 30 and m <= 45 then inside += 1 end
		end
		local median = sorted[16]
		local who = if search then "first-time players (they search each manor)" else "players who know each manor's layout"
		print(string.format("  %s, 31 normal players: the %s at %.1f-%.1f min, median %.1f, quartiles %.1f / %.1f; %d of 31 inside 30-45",
			who, flag.name, sorted[1], sorted[31], median, sorted[8], sorted[24], inside))
		truthy(median >= 30 and median <= 45, string.format("%s: the median normal player first sees the %s in 30-45 minutes of play (%.1f)",
			who, flag.name, median))
		truthy(inside >= 16, string.format("%s: ...and at least half of them do (%d of 31)", who, inside))
	end

	-- THE GAME AS IT SHIPS (2026-10-01): every manor is planned from a server-only salt, one per player per night per
	-- session (Main.server, check_nightwatchmanor_guard). Nobody knows a manor before entering it, and a retry after
	-- being caught is the same manor, remembered: the first-time player above, on salted manors. 31 normal players,
	-- each with salts of their own (NightModel.session's `salted`), each 0-30 s slower to get their bearings every night.
	-- The brag moment is asserted on THEM. The long-term goal too: the median of the same 31 players reaches the last
	-- band well after the flagship, inside three hours.
	do
		local mins, lasts, played, worst, worstWho = {}, {}, 0, 0, ""
		local lastBand = bands[#bands].from
		for k = 0, 30 do
			local human = table.clone(Config.Pacing.Profiles.normal)
			human.startSeconds += k
			local s = NightModel.session({ human = human, minutes = 200, nightCap = lastBand, search = true, salted = 7919 * (k + 1),
				hazards = { cfg = HZ.cfg, gate = HZ.gate, bands = HZ.bands, react = true } })
			table.insert(mins, s.reachedAt[flag.from] or math.huge)
			table.insert(lasts, s.reachedAt[lastBand] or math.huge)
			if (s.saltedNights or 0) >= flag.from and s.saltedPlays == s.attempts then played += 1 end
			if (s.worstNightAttempts or 0) > worst then
				worst, worstWho = s.worstNightAttempts, string.format("player %d, night %d", k, s.worstNight or -1)
			end
		end
		eq(played, 31, "CONTROL: all 31 salted sessions drew a salt for every night they entered and played every attempt on it")
		-- A salted manor can be one this player keeps getting caught in (pass 2 measured 2 of 31 sessions stuck on one
		-- night for the rest of the 200 minutes, 418 attempts at night 36 for one, when a retry was always the same
		-- manor). After
		-- Config.Manor.ShiftAfterFails failures in a row the manor shifts: new halves, same night.
		print(string.format("  the most attempts any of them needed for one night: %d (%s)", worst, worstWho))
		truthy(worst <= 12, string.format("SALTED manors: nobody is stuck on a manor: at most 12 attempts at any one night (%d, %s)", worst, worstWho))
		local sorted = table.clone(mins)
		table.sort(sorted)
		local inside = 0
		for _, m in mins do
			if m >= 30 and m <= 45 then inside += 1 end
		end
		local sl = table.clone(lasts)
		table.sort(sl)
		print(string.format("  SALTED manors, first-time players, 31 normal players: the %s at %.1f-%.1f min, median %.1f, quartiles %.1f / %.1f; %d of 31 inside 30-45",
			flag.name, sorted[1], sorted[31], sorted[16], sorted[8], sorted[24], inside))
		print(string.format("  ...and %s (night %d) at %.1f-%.1f min, median %.1f, quartiles %.1f / %.1f",
			bands[#bands].name, lastBand, sl[1], sl[31], sl[16], sl[8], sl[24]))
		truthy(sorted[16] >= 30 and sorted[16] <= 45, string.format(
			"SALTED manors: the median normal player first sees the %s in 30-45 minutes of play (%.1f)", flag.name, sorted[16]))
		truthy(inside >= 16, string.format("SALTED manors: ...and at least half of them do (%d of 31)", inside))
		truthy(sl[16] >= 1.6 * sorted[16], string.format("SALTED manors: %s is a long-term goal, at least 1.6x the flagship's median time (%.1f vs %.1f)",
			bands[#bands].name, sl[16], sorted[16]))
		truthy(sl[16] <= 180, string.format("SALTED manors: ...but reachable inside 3 hours (median %.1f)", sl[16]))
		truthy(sl[31] < math.huge, string.format("SALTED manors: every one of the 31 reaches %s inside 200 minutes (slowest %.1f)", bands[#bands].name, sl[31]))
	end

	-- every band lasts long enough to be a place, not a flicker
	local prev = 0
	for i = 2, #bands do
		local m = minutesTo(runs.normal, bands[i].from)
		truthy(m ~= nil, "a normal player reaches " .. bands[i].name .. " inside 200 minutes")
		if m then
			local need = if i == 2 then 1 else 3
			truthy(m - prev >= need, string.format("%s lasts at least %d min for a normal player (%.1f)",
				bands[i - 1].name, need, m - prev))
			prev = m
		end
	end
	-- the last band is the long-term goal: well past the flagship, but not out of reach
	local last = minutesTo(runs.normal, bands[#bands].from)
	truthy(last ~= nil and at ~= nil and last >= 1.6 * at, string.format(
		"%s is a long-term goal: at least 1.6x the flagship's time (%.1f vs %.1f)", bands[#bands].name, last or -1, at or -1))
	truthy(last ~= nil and last <= 180, string.format("...but reachable inside 3 hours (%.1f)", last or -1))

	-- DECIDED 2026-09-30 (owner: take recommended): the bands, like the night counter, reward leaving early, and that
	-- stays. A night is a full crossing to the deepest room whatever you carry, so leaving early is a strategy, not an
	-- exploit, and it has a price: the cautious player reaches the Blood Moon sooner but POORER (fewer upgrades, a
	-- barer safehouse). Measured on 11 players of each kind (0-10 s slower to get their bearings every night), by median.
	local Upgrades = require("../src/shared/Upgrades")
	local function atFlag(profile: string): (number, number)
		local mins, hubs = {}, {}
		for k = 0, 10 do
			local human = table.clone(Config.Pacing.Profiles[profile])
			human.startSeconds += k
			local s = NightModel.session({ human = human, minutes = 90, nightCap = flag.from,
				hazards = { cfg = HZ.cfg, gate = HZ.gate, bands = HZ.bands, react = true } })
			table.insert(mins, s.reachedAt[flag.from] or math.huge)
			table.insert(hubs, Upgrades.hubLevel(s.levels))
		end
		table.sort(mins)
		table.sort(hubs)
		return mins[6], hubs[6]
	end
	local nMin, nHub = atFlag("normal")
	local sMin, sHub = atFlag("slow")
	print(string.format("  leaving early: the cautious player reaches the %s at %.1f min with hub level %d; the greedy one at %.1f min with hub level %d (medians of 11)",
		flag.name, sMin, sHub, nMin, nHub))
	-- (how much sooner moves with the trajectory: 29.4 vs 37.3 min in the single sessions above, 29.8 vs 31.2 by these
	-- medians; the price does not: it is asserted)
	truthy(sHub + 5 <= nHub, string.format("leaving early costs the upgrades: the cautious player reaches the %s with a hub level at least 5 lower (%d vs %d)",
		flag.name, sHub, nHub))
end

--================================================================ hazards: the measured rarity

-- Review 4 (2026-09-24) found the old count flattering: it divided by ALL of play (hazards never run in the
-- safehouse, which is 10-34% of it) and measured one profile. The second review (2026-09-30) found the opposite gap:
-- with every hazard SHOWN held to one per 2-3 manor-minutes, the near-misses the owner asked for came one per 4.5-6.5
-- (a third of the shown hazards are called off when the Nightwatcher sees you, and the ring was aimed a whole second
-- ahead of a walking player, so a player who turned passed it wide), and nothing asserted a floor. The owner's
-- standard (docs/complete-game-standard.md §2) names the near-miss, so now:
--   * a NEAR-MISS (a pass within NearHitStuds of a player who reads the ring) comes one per 2-3 minutes in the manor;
--   * every hazard SHOWN stays rare: never more often than one per 1.5 manor-minutes;
--   * for every profile, and for a player who is rarely seen, and the shown rate must not depend on how often you are
--     seen; each pooled over three hazard seeds.
local SEEDS = { 104729, 7919, 31337 } -- 104729 is the seed of the sessions above
local function pooled(profile: string, react: boolean, first: any?): any
	local agg = { manorSeconds = 0, totalSeconds = 0, caught = 0, spawned = 0, near = 0, cancelled = 0, hits = 0, huntFree = 0, knockedFor = 0, each = {} }
	for i, seed in SEEDS do
		local s = if i == 1 and first then first else NightModel.session({
			human = Config.Pacing.Profiles[profile], minutes = 200,
			hazards = { cfg = HZ.cfg, gate = HZ.gate, bands = HZ.bands, react = react, seed = seed },
		})
		agg.manorSeconds += s.manorSeconds
		agg.totalSeconds += s.totalSeconds
		agg.caught += s.caught
		agg.spawned += s.hz.spawned
		agg.near += s.hz.near
		agg.cancelled += s.hz.cancelled
		agg.hits += s.hz.hits
		agg.huntFree += s.hz.huntFree
		agg.knockedFor += s.hz.knockedFor
		table.insert(agg.each, string.format("%.2f", (s.manorSeconds / 60) / math.max(s.hz.near, 1)))
	end
	return agg
end
local function hazardRate(label: string, a: any): number
	local manorMin = a.manorSeconds / 60
	local per = manorMin / math.max(a.spawned, 1)
	local perNear = manorMin / math.max(a.near, 1)
	local hunted = 1 - a.huntFree / math.max(a.manorSeconds, 1)
	print(string.format("  %-9s %d hazards shown in %.0f min in the manor (%.0f min of play, %d seeds): one per %.2f manor-min; "
		.. "%d near-misses within %d studs: one per %.2f manor-min (per seed %s); %d called off by a sighting; hunted %.0f%% of manor time; caught %d",
		label, a.spawned, manorMin, a.totalSeconds / 60, #SEEDS, per, a.near, Config.Pacing.NearHitStuds, perNear,
		table.concat(a.each, " / "), a.cancelled, 100 * hunted, a.caught))
	truthy(perNear >= 2 and perNear <= 3, string.format("%s: one near-miss per 2-3 minutes in the manor (one per %.2f)", label, perNear))
	truthy(per >= 1.5 and per <= 3, string.format("%s: hazards shown stay rare, one per 1.5-3 manor-minutes (one per %.2f)", label, per))
	return per
end

do
	local rates, all = {}, {}
	for _, prof in { "normal", "fast", "slow" } do
		all[prof] = pooled(prof, true, runs[prof])
		rates[prof] = hazardRate(prof, all[prof])
	end
	local s = all.normal
	-- a player who is rarely seen: the reviewer's stand-in, the Nightwatcher's sight cut to 30 studs, IN MEMORY
	local keep = Config.Watcher.SightRange
	Config.Watcher.SightRange = 30
	local ok, stealthy = pcall(pooled, "normal", true)
	Config.Watcher.SightRange = keep
	assert(ok, tostring(stealthy))
	truthy(stealthy.caught * 2 < s.caught, string.format("CONTROL: the stand-in really is seen less (caught %d vs %d)", stealthy.caught, s.caught))
	local huntedN = 1 - s.huntFree / s.manorSeconds
	local huntedS = 1 - stealthy.huntFree / stealthy.manorSeconds
	truthy(huntedS < huntedN - 0.2, string.format("CONTROL: ...and hunted for much less of its manor time (%.0f%% vs %.0f%%)", 100 * huntedS, 100 * huntedN))
	local rs = hazardRate("stealthy", stealthy)
	truthy(math.abs(rs - rates.normal) <= 0.15 * rates.normal, string.format(
		"the rate does not depend on how often the Nightwatcher sees you: stealthy one per %.2f vs normal one per %.2f manor-min", rs, rates.normal))
	local reactHits = s.hits + all.fast.hits + all.slow.hits + stealthy.hits
	eq(reactHits, 0, "a player who reads the ring and steps out of it is never hit (every profile, every seed)")

	local ig = session("normal", false)
	local im = ig.manorSeconds / 60
	print(string.format("  normal, ignoring every warning: %d hazards, %d near-hits, %d hits in %.0f min in the manor (one hit per %.1f manor-min), knocked down %.1f s in all",
		ig.hz.spawned, ig.hz.near, ig.hz.hits, im, im / math.max(ig.hz.hits, 1), ig.hz.knockedFor))
	truthy(ig.hz.hits > 0, "CONTROL: a player who ignores every warning IS hit sometimes (else the ring is decoration)")
	truthy(im / math.max(ig.hz.hits, 1) >= 5, string.format(
		"...but rarely: at most one hit per 5 minutes in the manor (one per %.1f)", im / math.max(ig.hz.hits, 1)))
end

--================================================================ the chase is untouched

-- Three mechanisms keep hazards out of the chase (Nightfall.hazardClock + the client): nothing launches while
-- the Nightwatcher sees you or for the quiet window after (the launch is held), a hazard in flight is called off
-- the moment it sees you, and a knock ends at that moment. Measured here on the shipped config and on a STRESS
-- config that launches a hazard every 3-5 s of night, with a player who ignores every warning (the worst case).
-- With the held clock, a hazard that fell due during a chase launches the moment the quiet window closes, so the
-- stress case is also the "hazard right after every escape" case.
do
	local stress = table.clone(Config.Hazards)
	stress.IntervalMin, stress.IntervalMax = 3, 5
	local function run(policy: string, nights: number, levels: any, cfg: any?)
		local caught, out, hits, inChase, whileSeen, spawned, pushed = 0, 0, 0, 0, 0, 0, 0
		local rand = NightModel.lcg(4242)
		local state = cfg and require("../src/shared/Hazards").newScheduler(cfg, rand) or nil
		for n = 1, nights do
			local r = NightModel.simulate(n, levels, policy, {
				hazards = cfg and { cfg = cfg, gate = Config.Hazards, bands = bands, react = false, state = state, rand = rand } or nil,
			})
			if r.caught then caught += 1 elseif r.out then out += 1 end
			if r.hz then
				hits += r.hz.hits
				inChase += r.hz.hitsInChase
				whileSeen += r.hz.knockedWhileSeen
				spawned += r.hz.spawned
				pushed += r.hz.pushedStuds
			end
		end
		return { caught = caught, out = out, hits = hits, inChase = inChase, whileSeen = whileSeen, spawned = spawned, pushed = pushed }
	end
	local cases = {
		{ "ambush", 20, {}, "ambushed runner" },
		{ "ambush", 20, { beartraps = 5 }, "ambushed runner, full Bear Traps" },
		{ "flee", 20, {}, "wandering runner" },
		{ "loot", 30, {}, "greedy looter ignoring the watcher" },
		{ "exit", 30, {}, "exit walker ignoring the watcher" },
	}
	local totalInChase, totalWhileSeen, totalHits, totalPushed = 0, 0, 0, 0
	for _, c in cases do
		local off = run(c[1], c[2], c[3], nil)
		local shipped = run(c[1], c[2], c[3], Config.Hazards)
		local hard = run(c[1], c[2], c[3], stress)
		totalPushed += shipped.pushed + hard.pushed
		print(string.format("  %-36s nights 1-%d: caught %2d without hazards | %2d shipped (%d hazards, %d hits) | %2d stress (%d hazards, %d hits)",
			c[4], c[2], off.caught, shipped.caught, shipped.spawned, shipped.hits, hard.caught, hard.spawned, hard.hits))
		totalInChase += shipped.inChase + hard.inChase
		totalWhileSeen += shipped.whileSeen + hard.whileSeen
		totalHits += shipped.hits + hard.hits
		if c[1] == "ambush" or c[1] == "flee" then
			eq(shipped.caught, 0, c[4] .. ": still caught on 0 nights with the shipped hazards")
			eq(hard.caught, 0, c[4] .. ": still caught on 0 nights with a hazard every 3-5 s")
		else
			truthy(math.abs(shipped.caught - off.caught) <= 1, string.format(
				"%s: the shipped hazards move the catch count by at most 1 of %d (%d -> %d)", c[4], c[2], off.caught, shipped.caught))
			truthy(math.abs(hard.caught - off.caught) <= 2, string.format(
				"%s: even a hazard every 3-5 s moves it by at most 2 of %d (%d -> %d)", c[4], c[2], off.caught, hard.caught))
		end
	end
	truthy(totalHits > 0, "CONTROL: the stress runs really did knock players down (" .. totalHits .. " hits)")
	-- A knock is a PUSH, not a pause: the client sets the character sliding sideways at the kind's `knock`
	-- speed for KnockSeconds. The model pushes the whole way at full speed (friction would only shorten it),
	-- through Chase.spec's walls, so the catch counts above are measured with the worst a knock can do.
	local maxKnock = 0
	for _, k in Config.Hazards.Kinds do maxKnock = math.max(maxKnock, k.knock) end
	local perHit = totalPushed / math.max(totalHits, 1)
	print(string.format("  knocks pushed players %.0f studs in all, %.1f studs per hit (at most %.1f: the fastest knock for KnockSeconds)",
		totalPushed, perHit, maxKnock * Config.Hazards.KnockSeconds))
	truthy(perHit >= 3, string.format("a knock in the model shoves the player (%.1f studs per hit), it does not just stop them", perHit))
	truthy(perHit <= maxKnock * Config.Hazards.KnockSeconds + 1e-6, "...and never further than the fastest knock can carry them")
	eq(totalInChase, 0, "no hit ever lands while it is hunting you (seen, or within the quiet window after)")
	eq(totalWhileSeen, 0, "and no player is ever still knocked down on a tick it sees them")
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("Pacing spec failed", 0)
end
