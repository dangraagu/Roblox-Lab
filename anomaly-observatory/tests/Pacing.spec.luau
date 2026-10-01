-- Spec for pacing: how long a player takes to FIRST see each night sky. Run: luau tests/Pacing.spec.luau
--
-- The owner's brief asks for a steady rise "at a level people can actually reach and brag about",
-- with a far goal for the long haul. In this game the progress value is the Day streak, which a
-- single wrong call resets to 1, so time-to-Day grows geometrically with the Day: every extra Day
-- has to survive one more pass. The band thresholds in Config.Sky.Bands are placed on that curve.
--
-- tests/NightModel.luau is the model (assumptions written out there and in
-- Config.Sky.Pacing.Profiles). It is a model of an average player, not telemetry: it has no
-- learning and no fatigue. When real session data exists, retune `Profiles.normal` first, then the
-- `from` Days, and this spec says where the headline band lands.
local NightModel = require("./NightModel")
local Anomaly = require("../src/shared/Anomaly")
local Rng = require("../src/shared/Rng")
local EnvBands = require("../src/shared/EnvBands")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local Sky = Config.Sky
local P = Sky.Pacing
local bands = Sky.Bands
local profiles = P.Profiles

-- The profiles are plausible humans: they get most passes right and a pass takes seconds.
for name, pr in profiles do
	truthy(pr.passSeconds >= 8 and pr.passSeconds <= 40, name .. ": a pass takes 8-40 s (the hall is ~80 studs at WalkSpeed 16)")
	truthy(pr.deathSeconds >= 2.5, name .. ": a wrong call costs at least the server's 2.5 s death beat")
	truthy(pr.falseAlarm >= 0 and pr.falseAlarm < 0.2, name .. ": false alarms are rare")
	truthy(pr.spotSubtle <= pr.spotObvious, name .. ": subtle anomalies are no easier than obvious ones")
end
truthy(profiles.fast.spotSubtle > profiles.normal.spotSubtle and profiles.normal.spotSubtle > profiles.slow.spotSubtle,
	"fast spots more than normal spots more than slow")

-- ------------------------------------------------------------------ the closed form is right
-- NightModel.expectedSeconds is exact for the model; a Monte Carlo of the same model must agree.
do
	local rng = Rng.new(20260923)
	for _, target in { 6, 12 } do
		local exact = NightModel.expectedSeconds(Config, Anomaly, profiles.normal, target)
		local sim = NightModel.simulate(Config, Anomaly, profiles.normal, target, 4000, rng)
		truthy(math.abs(sim - exact) / exact < 0.06,
			string.format("Day %d: closed form %.1f s vs %d-run simulation %.1f s (within 6%%)", target, exact, 4000, sim))
	end
	-- and it responds to the game: a harder catalog (everything subtle) makes every Day slower
	local harder = table.clone(profiles.normal)
	harder.spotObvious = harder.spotSubtle
	truthy(NightModel.expectedSeconds(Config, Anomaly, harder, 20) > NightModel.expectedSeconds(Config, Anomaly, profiles.normal, 20),
		"a harder catalog pushes Day 20 later")
end

-- ------------------------------------------------------------------ minutes to each band
local function bandMinutes(profile)
	local out = {}
	for i, b in bands do
		local firstDay = math.max(1, b.from)
		out[i] = NightModel.expectedMinutes(Config, Anomaly, profile, firstDay)
	end
	return out
end

local mins = {}
for name, pr in profiles do mins[name] = bandMinutes(pr) end

print("   band                         Day    fast    normal      slow   (expected minutes to first reach)")
for i, b in bands do
	print(string.format("   %-3s %-24s %4d  %6.1f  %8.1f  %8.1f", b.emoji, b.name, math.max(1, b.from),
		mins.fast[i], mins.normal[i], mins.slow[i]))
end

local headline
for i, b in bands do
	if b.id == P.Headline then headline = i end
end
truthy(headline ~= nil, "the headline band is one of the bands")
headline = headline or #bands

local lo, hi = P.HeadlineMinutes[1], P.HeadlineMinutes[2]
local n = mins.normal
truthy(n[2] <= 2, string.format("a normal player sees the second sky within 2 minutes (%.1f)", n[2]))
truthy(n[headline] >= lo and n[headline] <= hi,
	string.format("a normal player reaches the headline sky (%s) in %.1f min, inside the %d-%d min window",
		bands[headline].name, n[headline], lo, hi))
truthy(math.abs(n[headline] - (lo + hi) / 2) <= 5,
	string.format("and within 5 min of the window's centre, so a retune that drifts fails loudly (%.1f vs %.1f)", n[headline], (lo + hi) / 2))
for i = 2, #bands - 1 do
	local ratio = n[i + 1] / n[i]
	truthy(ratio >= 1.8 and ratio <= 4,
		string.format("a steady rise: %s takes %.2fx as long to reach as %s (1.8-4x)", bands[i + 1].name, ratio, bands[i].name))
end
truthy(n[#bands] >= 2 * n[headline],
	string.format("the last sky is the long-term goal: %.0f min, at least twice the headline", n[#bands]))
truthy(mins.fast[#bands] <= 60,
	string.format("but a skilled player can get there in an evening's session: %.1f min", mins.fast[#bands]))
truthy(mins.fast[headline] < lo, string.format("a fast player reaches the headline sooner (%.1f)", mins.fast[headline]))
for i = 2, #bands do
	truthy(mins.slow[i] > n[i], "a slow player is slower to every sky (" .. bands[i].id .. ")")
end

-- ------------------------------------------------------------------ the Field Guide (standard §2/§3, 2026-10-01)
-- The long-term goal beyond the headline sky, and what the highscore board ranks: anomaly TYPES caught.
-- A type can only be caught once the pool has grown to it (Anomaly.poolSize: all 24 from Day 33), so the
-- last few need a long streak, and a wrong call still resets the streak. Same model, simulated (no closed
-- form: which types are still missing matters), from a fresh profile.
truthy(type(NightModel.simulateGuide) == "function", "NightModel.simulateGuide exists")
if type(NightModel.simulateGuide) == "function" then
	local total = Anomaly.count(Config)
	local marks = { 1, Config.Anomaly.StartPool, 16, total }
	local g = {}
	for name, runs in { fast = 300, normal = 300, slow = 40 } do
		g[name] = NightModel.simulateGuide(Config, Anomaly, profiles[name], marks, runs, Rng.new(20261001))
	end
	print("   Field Guide                        fast    normal      slow   (expected minutes to first reach)")
	for _, m in marks do
		print(string.format("   %2d of %2d types caught          %8.1f  %8.1f  %8.1f", m, total, g.fast[m] / 60, g.normal[m] / 60, g.slow[m] / 60))
	end
	local gn = g.normal
	truthy(gn[1] / 60 <= 2, string.format("a normal player catches a first anomaly within 2 minutes (%.1f)", gn[1] / 60))
	truthy(gn[total] >= 2 * n[headline] * 60,
		string.format("the full Field Guide (%d/%d) is a long-term goal: %.0f min, at least twice the headline sky (%.1f)", total, total,
			gn[total] / 60, n[headline]))
	truthy(g.fast[total] / 60 <= 90, string.format("and a skilled player can finish it in an evening: %.1f min", g.fast[total] / 60))
	for _, m in marks do
		truthy(g.fast[m] < gn[m] and gn[m] < g.slow[m], string.format("%d types: fast < normal < slow", m))
	end
	-- the model responds to the game: with the pool growing half as fast, the last type waits for a longer streak
	local slower = table.clone(Config.Anomaly)
	slower.PoolPerDay = Config.Anomaly.PoolPerDay / 2
	local cfg2 = table.clone(Config)
	cfg2.Anomaly = slower
	local g2 = NightModel.simulateGuide(cfg2, Anomaly, profiles.fast, { total }, 100, Rng.new(20261001))
	truthy(g2[total] > g.fast[total], string.format("a slower-growing pool pushes the full guide later (%.1f > %.1f min, fast)",
		g2[total] / 60, g.fast[total] / 60))
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
assert(failed == 0, "Pacing tests failed")
