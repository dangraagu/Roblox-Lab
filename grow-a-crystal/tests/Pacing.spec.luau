-- Spec for WHEN a player sees each look of the cavern. Run: luau tests/Pacing.spec.luau
--
-- The bands are keyed to chambers owned (Config.Env.Bands[*].from). This spec runs the game's own
-- rules (tests/IdleModel.luau: Economy, Growth, Rarity, Codex, Rng, Config) for many seeded sessions
-- per profile in Config.Pacing.Profiles and reports the minutes of play to each chamber, hence to
-- each look. It asserts what EYECANDY.md §2 claims, so a retune that moves them fails loudly.
--
-- It also pins a FINDING that is not a requirement: at luck level 0 every seed is worth LESS, on
-- average, than it costs, so a player who does not type the advertised codes slowly runs out of Gem
-- Dust and never buys chamber 2. That is an economy decision for the owner (EYECANDY.md §11), not
-- something the cavern's looks can fix. The assertions marked FINDING are here so the note stays
-- true: when the economy is retuned they fail, and EYECANDY.md §2/§11 must be updated with them.
local IdleModel = require("./IdleModel")
local EnvBands = require("../src/shared/EnvBands")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
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
	print("  expected Gem Dust per seed at luck 0 (FINDING):")
	local allNegative = true
	for t = 1, Config.MaxTier - 1 do
		local ev = IdleModel.expectedDust(Config, t, 1)
		local cost = Config.Economy.SeedCost[t]
		print(string.format("    %-9s costs %6d, returns %9.2f on average (%.0f %%)", Config.Tiers[t], cost, ev, 100 * ev / cost))
		if ev >= cost then allNegative = false end
	end
	truthy(allNegative, "FINDING: at luck 0 no seed tier below Mythic pays back its price on average")
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

	-- FINDING: without the codes the cavern never changes, because the economy runs dry (see the top)
	local nc = sweeps.nocodes.chambers
	truthy(IdleModel.quantile(nc[2], 0.9) == math.huge, "FINDING: a player who never types a code does not own chamber 2 after 8 h")
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing spec failed", 0) end
