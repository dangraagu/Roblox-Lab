-- Spec for WHEN a player sees each look of the cavern. Run: luau tests/Pacing.spec.luau
--
-- The bands are keyed to chambers owned (Config.Env.Bands[*].from). This spec runs the game's own
-- rules (tests/IdleModel.luau: Economy, Growth, Rarity, Codex, Rng, Config) for many seeded sessions
-- per profile in Config.Pacing.Profiles and reports the minutes of play to each chamber, hence to
-- each look. It asserts what EYECANDY.md §2 claims, so a retune that moves them fails loudly.
--
-- It used to pin a FINDING: at luck level 0 every seed was worth LESS, on average, than it cost, so a
-- player who did not type the advertised codes ran out of Gem Dust (a dead end: nothing growing, no seed,
-- too little dust for one) and never bought chamber 2. The owner decided on 2026-09-30 (EYECANDY.md §11):
-- the Shard seed costs 7 instead of 10, so it pays back on average, and a player at a dead end gets a free
-- Shard (Economy.needsFreeSeed). Those two FINDING assertions are now requirements: the Shard pays back,
-- a code-less player owns chamber 2 in the median session, and no session of any profile reaches a dead end.
local IdleModel = require("./IdleModel")
local EnvBands = require("../src/shared/EnvBands")
local Config = require("../src/shared/Config")
local Board = require("../src/shared/Board")

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b)) end
end

local bands = Config.Env.Bands
local MAXC = Config.Economy.MaxChambers
local RUNS = 40
local SECONDS = Config.Pacing.SessionHours * 3600

local function fmt(s)
	if s == math.huge then return "never" end
	return string.format("%.0f", s / 60)
end

--=========================================================================== the economy finding
do
	print("  expected Gem Dust per seed at luck 0:")
	for t = 1, Config.MaxTier - 1 do
		local ev = IdleModel.expectedDust(Config, t, 1)
		local cost = Config.Economy.SeedCost[t]
		print(string.format("    %-9s costs %6d, returns %9.2f on average (%.0f %%)", Config.Tiers[t], cost, ev, 100 * ev / cost))
	end
	local shardEv = IdleModel.expectedDust(Config, 1, 1)
	truthy(shardEv >= Config.Economy.SeedCost[1], string.format("at luck 0 a Shard seed pays back its price on average (%.2f for %d)", shardEv, Config.Economy.SeedCost[1]))
end

--=========================================================================== when each chamber, and so each look, arrives
-- A band first SHOWS at the first whole chamber count where its weight is above 0, and is FULL at `from`.
local function firstShows(i)
	if i == 1 then return 1 end
	for k = 1, MAXC do
		local w = EnvBands.weights(bands, k)
		if (w[i] or 0) > 0.001 then return k end
	end
	return math.huge
end

local sweeps = {}
for name, prof in Config.Pacing.Profiles do
	sweeps[name] = IdleModel.sweep(Config, prof, RUNS, SECONDS)
end

do
	print("")
	print(string.format("  minutes of play to own each chamber (%d sessions of %d h per profile; p10 / median / p90)", RUNS, Config.Pacing.SessionHours))
	for _, name in { "normal", "slow", "nocodes" } do
		local s = sweeps[name]
		local row = {}
		for k = 2, MAXC do
			local list = s.chambers[k]
			table.insert(row, string.format("ch%d %s/%s/%s", k, fmt(IdleModel.quantile(list, 0.1)), fmt(IdleModel.quantile(list, 0.5)), fmt(IdleModel.quantile(list, 0.9))))
		end
		print(string.format("    %-8s %s", name, table.concat(row, "  ")))
	end
	print("")
	print("  the looks (median minutes of play; first shows -> full)")
	for i, b in bands do
		local k0, k1 = firstShows(i), math.max(1, b.from)
		local n = sweeps.normal.chambers
		local sl = sweeps.slow.chambers
		print(string.format("    %d %-20s ch%d -> ch%d   normal %4s -> %4s   slow %4s -> %4s", i, b.name, k0, k1,
			fmt(IdleModel.quantile(n[k0], 0.5)), fmt(IdleModel.quantile(n[k1], 0.5)),
			fmt(IdleModel.quantile(sl[k0], 0.5)), fmt(IdleModel.quantile(sl[k1], 0.5))))
	end
	print("")
	local codexRow = {}
	for t = 1, Config.MaxTier do
		table.insert(codexRow, string.format("%s %s", Config.Tiers[t], fmt(IdleModel.quantile(sweeps.normal.codex[t], 0.5))))
	end
	print("  normal player's first sight of each tier (median min): " .. table.concat(codexRow, "  "))
end

--=========================================================================== assertions
do
	local n = sweeps.normal.chambers
	local med = function(k) return IdleModel.quantile(n[k], 0.5) end
	truthy(med(firstShows(2)) <= 5 * 60, "a normal player sees the cavern change within 5 minutes (" .. fmt(med(firstShows(2))) .. " min)")
	local last = MAXC
	truthy(med(last) <= SECONDS, "a normal player reaches the Heart of the Geode inside one 8-hour session (" .. fmt(med(last)) .. " min)")
	truthy(med(last) >= 2 * 3600, "and it is a long-term goal, not an afternoon (" .. fmt(med(last)) .. " min)")
	-- the looks keep coming: every chamber from 3 on arrives after the one before it, so the cavern
	-- changes across the session instead of all at once
	for k = 4, MAXC do
		truthy(med(k) > med(k - 1), "chamber " .. k .. " comes after chamber " .. (k - 1) .. " (" .. fmt(med(k - 1)) .. " -> " .. fmt(med(k)) .. " min)")
	end
	-- no long drought: the median gap between two looks changing is under 90 minutes of play
	local worstGap = 0
	for k = 3, MAXC do
		worstGap = math.max(worstGap, med(k) - med(k - 1))
	end
	truthy(worstGap <= 90 * 60, "a normal player never waits more than 90 min of play for the cavern to change (" .. fmt(worstGap) .. ")")

	local slow = sweeps.slow.chambers
	truthy(IdleModel.quantile(slow[MAXC], 0.5) > med(MAXC), "a slower player gets there later (the model is sensitive to the human part)")

	-- without the codes the cavern still changes: the Shard pays back and a dead end hands out a free Shard
	local nc = sweeps.nocodes.chambers
	truthy(IdleModel.quantile(nc[2], 0.5) <= SECONDS, "a player who never types a code owns chamber 2 in the median 8-hour session ("
		.. fmt(IdleModel.quantile(nc[2], 0.5)) .. " min)")
	for _, name in { "normal", "slow", "nocodes" } do
		local sw = sweeps[name]
		truthy(sw.deadEnds == 0, string.format("%s: no session ever has nothing growing and nothing to plant (%d of %d did; %d free Shards handed out)",
			name, sw.deadEnds, sw.runs, sw.freeSeeds))
	end
end

--=========================================================================== the brag moment and the long-term goal
-- docs/complete-game-standard.md §2: "A brag moment within about 30-45 minutes of normal play (+1 Jump: reaching
-- space), and a long-term goal beyond it. Measure the minutes with a pacing model in tests/." Grow a Crystal's is
-- Config.Pacing.Brag: the first crystal that refracts all the way to its tier, Mythic, which gets the game's
-- biggest celebration (magenta flash, beam of light, title card; check_growacrystal_flash) and puts a jump of
-- 1500 Gem Dust on the highscore board. The long-term goals are the Heart of the Geode (chamber 8) and the board.
do
	local brag = Config.Pacing.Brag
	truthy(type(brag) == "table", "Config.Pacing.Brag names the brag moment")
	brag = brag or { tier = Config.MaxTier, fromMinutes = 20, byMinutes = 45, name = "?" }
	local n = sweeps.normal.codex[brag.tier]
	local p10, med, p90 = IdleModel.quantile(n, 0.1), IdleModel.quantile(n, 0.5), IdleModel.quantile(n, 0.9)
	print(string.format("  the brag moment, %s (%s): normal p10 %s / median %s / p90 %s min; slow median %s; no codes median %s",
		brag.name, Config.Tiers[brag.tier], fmt(p10), fmt(med), fmt(p90),
		fmt(IdleModel.quantile(sweeps.slow.codex[brag.tier], 0.5)), fmt(IdleModel.quantile(sweeps.nocodes.codex[brag.tier], 0.5))))
	eq(brag.tier, Config.MaxTier, "the brag moment is the top tier, Mythic")
	truthy(med >= brag.fromMinutes * 60 and med <= brag.byMinutes * 60, string.format(
		"a normal player's first Mythic comes in %d-%d min of play (median %s min)", brag.fromMinutes, brag.byMinutes, fmt(med)))
	truthy(brag.fromMinutes >= 20 and brag.byMinutes <= 45, "and that window is the standard's 'about 30-45 minutes'")
	truthy(p90 <= 2 * brag.byMinutes * 60, "nine in ten normal players have it within " .. (2 * brag.byMinutes) .. " min (p90 " .. fmt(p90) .. ")")
	local slowMed = IdleModel.quantile(sweeps.slow.codex[brag.tier], 0.5)
	truthy(slowMed <= SECONDS, "a slower player gets there in the session too (median " .. fmt(slowMed) .. " min)")
	-- the long-term goal lies well beyond it
	local heart = IdleModel.quantile(sweeps.normal.chambers[MAXC], 0.5)
	truthy(heart >= med + 2 * 3600, string.format("the Heart of the Geode comes at least 2 h of play after the brag (%s vs %s min)", fmt(heart), fmt(med)))

	-- the highscore board never runs out of room: hours of normal end-game play to its cap (Config.Board.MaxMetric)
	local B = Config.Board
	local run8 = IdleModel.run(Config, Config.Pacing.Profiles.normal, 1031, 8 * 3600)
	local run24 = IdleModel.run(Config, Config.Pacing.Profiles.normal, 1031, 24 * 3600)
	local perHour = (run24.final.totalDust - run8.final.totalDust) / 16
	local hoursToCap = (B.MaxMetric * B.DustPerPoint - run24.final.totalDust) / perHour + 24
	print(string.format("  board: a normal player earns %.0f dust in 8 h, then %.0f per hour at the end game; the cap (%s) takes %.0f h of play",
		run8.final.totalDust, perHour, Board.formatScore(B.MaxMetric, B), hoursToCap))
	truthy(hoursToCap >= 1000, string.format("the board's cap is over 1000 hours of end-game play away (%.0f h)", hoursToCap))
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing spec failed", 0) end
