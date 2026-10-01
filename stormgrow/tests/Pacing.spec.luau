-- The brag moment and the long-term goal, measured on the REAL modules. Run: luau tests/Pacing.spec.luau
--
-- The owner's standard §2: "a brag moment within about 30-45 minutes of normal play, and a long-term goal
-- beyond it. Measure the minutes with a pacing model in tests/." The model (tests/FarmModel.luau) plays
-- only the player; every rule of the game comes from src/shared. It replaces design/pacing-model.luau,
-- which carried its own copy of the numbers.
--
-- What is asserted (DESIGN.md §13): the normal player's brag (entering the Eye of the Storm) inside 30-45
-- min; the fast and slow players inside it too; the player who ignores the forecast slower than the one
-- who follows it; every band lasts at least 2 minutes; band 7 under 3 hours; the planner completes the
-- 56-entry Almanac in under 8 hours. Runtime: about a minute.
local FarmModel = require("./FarmModel")
local EnvBands = require("../src/shared/EnvBands")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local bands = Config.Env.Bands
local brag = EnvBands.indexOf(bands, Config.Env.BragBandId) :: number
local lo, hi = Config.Pacing.BragMinutes[1], Config.Pacing.BragMinutes[2]
local pct = FarmModel.pct

local function m(sec: number): string
	if sec == math.huge then return "   never" end
	return string.format("%6.1f", sec / 60)
end
local function row(list, label)
	print(string.format("  %-26s %s %s %s", label, m(pct(list, 0.1)), m(pct(list, 0.5)), m(pct(list, 0.9))))
end

local samples = {}
local plan = {
	{ "normal", 200, 150 * 60 },
	{ "fast", 100, 60 * 60 },
	{ "slow", 100, 60 * 60 },
	{ "nohold", 100, 60 * 60 },
	{ "combo", 100, 60 * 60 },
}
local t0 = os.clock()
for _, pl in plan do
	local name, runs, secs = pl[1], pl[2], pl[3]
	local s = FarmModel.sample(name, runs, secs)
	samples[name] = s
	print(string.format("== %s (%d runs x %d min; minutes p10 / median / p90)", name, runs, secs // 60))
	for b = 2, #bands do
		if secs >= 150 * 60 or b <= brag then
			row(s.band[b], string.format("band %d %s", b, bands[b].name))
		end
	end
	row(s.firstMark, "first mark")
	row(s.firstTempest, "first Tempest")
	print(string.format("  Almanac entries @30 / 60 min (median): %d / %d", pct(s.almanac[30], 0.5), pct(s.almanac[60], 0.5)))
end

do
	local s = samples.normal
	local order = { "carrot", "corn", "field 2", "tomato", "field 3", "sunflower", "pumpkin", "field 4", "watermelon", "stormfruit", "field 5", "field 6" }
	local parts = {}
	for _, k in order do
		local list = s.bought[k] or {}
		for _ = #list + 1, s.runs do table.insert(list, math.huge) end
		table.insert(parts, k .. " " .. string.gsub(m(pct(list, 0.5)), "^%s+", ""))
	end
	print("  normal, median minute of each purchase: " .. table.concat(parts, " · "))
	local w = {}
	for _, minute in { 3, 10, 20, 30, 37, 45, 60, 120 } do
		if s.worth[minute] then table.insert(w, minute .. " -> " .. math.floor(pct(s.worth[minute], 0.5))) end
	end
	print("  normal, median lifetime harvest by minute: " .. table.concat(w, ", "))
end

--================================================================ the brag

local function median(list) return pct(list, 0.5) / 60 end
local nb = median(samples.normal.band[brag])
truthy(nb >= lo and nb <= hi, string.format("the normal player's brag (Eye of the Storm) is inside %d-%d min (%.1f)", lo, hi, nb))
for _, name in { "fast", "slow" } do
	local x = median(samples[name].band[brag])
	truthy(x >= lo and x <= hi, string.format("the %s player's brag is inside %d-%d min too (%.1f)", name, lo, hi, x))
end
do
	local nh = median(samples.nohold.band[brag])
	truthy(nh > nb, string.format("ignoring the forecast is SLOWER than following it (%.1f vs %.1f): the core mechanic pays", nh, nb))
	local cb = median(samples.combo.band[brag])
	truthy(cb <= hi, string.format("keeping marked crops for the next event still reaches the brag inside the window (%.1f)", cb))
end

--================================================================ the bands and the long term

do
	local s = samples.normal
	local shortest, which = math.huge, "-"
	for b = 1, #bands - 1 do
		local d = pct(s.band[b + 1], 0.5) - pct(s.band[b], 0.5)
		if d < shortest then shortest, which = d, bands[b].name end
	end
	truthy(shortest >= 120, string.format("every band lasts at least 2 minutes for the normal player (shortest: %s, %.1f min)", which, shortest / 60))
	local b7 = median(s.band[#bands])
	truthy(b7 < 180, string.format("band 7 (Starfall Summit) comes in under 3 hours (%.1f min)", b7))
	truthy(b7 > nb * 2, "and well past the brag: a long-term goal, not a second brag")
	local fm = median(s.firstMark)
	truthy(fm < 5, string.format("the first mark comes in the first 5 minutes (%.1f)", fm))
end

do
	-- the long-term goal: all 56 Almanac entries, for the player who follows the "📖 N to find" hint
	local s = FarmModel.sample("planner", 20, 8 * 3600, 5000)
	local all = s.all56
	print(string.format("== planner (20 runs x 8 h): all 56 Almanac entries at p10 %.1f / median %.1f / p90 %.1f h",
		pct(all, 0.1) / 3600, pct(all, 0.5) / 3600, pct(all, 0.9) / 3600))
	truthy(pct(all, 0.5) < 8 * 3600, "the planner completes the Almanac (56/56) in under 8 hours (median)")
end

print(string.format("  (model runtime %.0f s)", os.clock() - t0))
print(string.format("Pacing: %d passed, %d failed", passed, failed))
assert(failed == 0, "Pacing tests failed")
