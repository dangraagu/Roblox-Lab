-- Pacing: minutes of PLAY to each band, the hazards' measured rarity, and the chase with and without them.
-- Run: luau tests/Pacing.spec.luau
--
-- Everything here is measured with tests/NightModel.luau, which plays the game's REAL rules forward
-- (Manor, Watcher, Night, Upgrades, the client's Hazards + Nightfall gate). The human parts are written
-- down in Config.Pacing. The owner's brief, as numbers:
--   * the big milestone (the Blood Moon) in about 30-45 minutes of play for a normal player; the last
--     band is the long-term goal;
--   * hazards: about one near-hit per 2-3 minutes, easy to see coming and avoid (counted strictly since review 4:
--     every hazard SHOWN, per minute IN THE MANOR, for every profile and for a player who is rarely seen);
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
	truthy(at ~= nil and at >= 30 and at <= 45, string.format(
		"a normal player first sees the %s in 30-45 minutes of play (got %s)", flag and flag.name or "?", tostring(at and string.format("%.1f", at))))

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
end

--================================================================ hazards: the measured rarity

-- Review 4 (2026-09-24) found the old count flattering, three ways: it divided by ALL of play (hazards never run in
-- the safehouse, which is 10-34% of it), it counted only hazards that passed within 8 studs (every hazard homes on
-- you with a banner and a ring at your feet, whether it then passes close, is dodged wide or is called off), and it
-- measured one profile. With the clock frozen during chases, a player who hid well got a hazard every 33 s of
-- unhunted time: 1.2 per manor-minute for the normal profile, 1.35 for a stealthier one. So now:
--   * the unit is every hazard SHOWN, per minute IN THE MANOR, and it must be one per 2-3 minutes (the brief);
--   * for every profile, and for a player who is rarely seen, and the rate must not depend on how often you are seen;
--   * near-hits (within NearHitStuds) are a subset and are reported, never more often than one per 2 manor-minutes.
local function hazardRate(label: string, s: any): number
	local manorMin = s.manorSeconds / 60
	local per = manorMin / math.max(s.hz.spawned, 1)
	local perNear = manorMin / math.max(s.hz.near, 1)
	local hunted = 1 - s.hz.huntFree / math.max(s.manorSeconds, 1)
	print(string.format("  %-9s %d hazards shown in %.0f min in the manor (%.0f min of play): one per %.2f manor-min (%.2f play-min); "
		.. "%d near-hits within %d studs (one per %.1f manor-min); %d called off by a sighting; hunted %.0f%% of manor time; caught %d",
		label, s.hz.spawned, manorMin, s.totalSeconds / 60, per, s.totalSeconds / 60 / math.max(s.hz.spawned, 1),
		s.hz.near, Config.Pacing.NearHitStuds, perNear, s.hz.cancelled, 100 * hunted, s.caught))
	truthy(per >= 2 and per <= 3, string.format("%s: one hazard shown per 2-3 minutes in the manor (one per %.2f)", label, per))
	truthy(perNear >= 2, string.format("%s: a near-hit never more often than one per 2 minutes in the manor (one per %.1f)", label, perNear))
	return per
end

do
	local s = runs.normal
	local rates = {}
	for _, prof in { "normal", "fast", "slow" } do
		rates[prof] = hazardRate(prof, runs[prof])
	end
	-- a player who is rarely seen: the reviewer's stand-in, the Nightwatcher's sight cut to 30 studs, IN MEMORY
	local keep = Config.Watcher.SightRange
	Config.Watcher.SightRange = 30
	local ok, stealthy = pcall(session, "normal")
	Config.Watcher.SightRange = keep
	assert(ok, tostring(stealthy))
	truthy(stealthy.caught * 2 < s.caught, string.format("CONTROL: the stand-in really is seen less (caught %d vs %d)", stealthy.caught, s.caught))
	local huntedN = 1 - s.hz.huntFree / s.manorSeconds
	local huntedS = 1 - stealthy.hz.huntFree / stealthy.manorSeconds
	truthy(huntedS < huntedN - 0.2, string.format("CONTROL: ...and hunted for much less of its manor time (%.0f%% vs %.0f%%)", 100 * huntedS, 100 * huntedN))
	local rs = hazardRate("stealthy", stealthy)
	truthy(math.abs(rs - rates.normal) <= 0.15 * rates.normal, string.format(
		"the rate does not depend on how often the Nightwatcher sees you: stealthy one per %.2f vs normal one per %.2f manor-min", rs, rates.normal))
	eq(s.hz.hits, 0, "a player who reads the ring and steps out of it is never hit")

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
