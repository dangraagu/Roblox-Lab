-- Pacing.spec — the brag moment's minutes, measured on the REAL game's generator and numbers (DESIGN.md §7, §19).
-- Run: luau tests/Pacing.spec.luau   (about a minute)
--
-- The standard (docs/complete-game-standard.md §2): a brag moment within about 30-45 minutes of normal play, with a
-- long-term goal beyond it, measured by a pacing model in tests/. The brag is relay 30, the Main Array. The model is
-- tests/PacingModel.luau: DESIGN.md's campaign model on the real Station / Config / Economy, three proxy profiles.
local Config = require("../src/shared/Config")
local Model = require("./PacingModel")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local RUNS = 200
local BRAG = Config.Brag.Sector
local bands = Config.Env.Bands

local results = {}
for _, name in { "fast", "medium", "slow" } do
	local prof = Model.PROFILES[name]
	local brag, starts, deaths, firstBuy, income = {}, {}, {}, {}, {}
	for b = 1, #bands do starts[b] = {} end
	for s = 1, RUNS do
		local c = Model.campaign(prof, Config.Brag.EchoSector, 240 * 60, s)
		if c.reachAt[BRAG + 1] then
			table.insert(brag, (c.reachAt[BRAG + 1] - Model.OVERHEAD.transit) / 60)
		end
		for b, band in bands do
			if c.reachAt[band.first] then table.insert(starts[b], c.reachAt[band.first] / 60) end
		end
		table.insert(deaths, c.deaths)
		if c.buys[1] then table.insert(firstBuy, c.buys[1].t / 60) end
		table.insert(income, c.earned / (c.t / 60))
	end
	local bandP50 = {}
	for b = 1, #bands do bandP50[b] = if #starts[b] >= RUNS / 2 then Model.pct(starts[b], 0.5) else nil end
	results[name] = { brag = brag, bandP50 = bandP50 }
	local line = {}
	for b = 2, #bands do
		table.insert(line, string.format("%s %s", bands[b].id, if bandP50[b] then string.format("%.1f", bandP50[b]) else "--"))
	end
	print(string.format("%-6s relay %d spliced at minute p10/p50/p90 %.1f / %.1f / %.1f (%d of %d campaigns); blackouts p50 %d; first purchase %.1f; income %.1f/min",
		name, BRAG, Model.pct(brag, 0.1), Model.pct(brag, 0.5), Model.pct(brag, 0.9), #brag, RUNS, Model.pct(deaths, 0.5),
		Model.pct(firstBuy, 0.5), Model.pct(income, 0.5)))
	print("       band entered at minute p50: " .. table.concat(line, "  "))
end

--================================================================ the brag lands in 30-45 minutes of normal play
do
	local med = results.medium.brag
	local p50 = Model.pct(med, 0.5)
	truthy(#med == RUNS, "every medium campaign reaches the Main Array within 4 hours (" .. #med .. "/" .. RUNS .. ")")
	truthy(p50 >= 30 and p50 <= 45, string.format("the medium proxy splices relay %d at p50 %.1f min: inside 30-45", BRAG, p50))
	truthy(Model.pct(med, 0.1) >= 25 and Model.pct(med, 0.9) <= 50, string.format("and its 10-90 %% range is near the window (%.1f - %.1f)",
		Model.pct(med, 0.1), Model.pct(med, 0.9)))
	truthy(Model.pct(results.fast.brag, 0.5) < p50 and p50 < Model.pct(results.slow.brag, 0.5), "fast < medium < slow")
end

--================================================================ every band after the first lasts at least 3 minutes
do
	for _, name in { "fast", "medium", "slow" } do
		local p = results[name].bandP50
		for b = 2, #bands - 1 do
			if p[b] and p[b + 1] then
				truthy(p[b + 1] - p[b] >= 3, string.format("%s: %s lasts %.1f min (>= 3)", name, bands[b].name, p[b + 1] - p[b]))
			elseif p[b] and not p[b + 1] then
				passed += 1 -- the next band is never reached inside 4 hours at this proxy: this one lasts past the cap
			end
		end
		truthy(p[2] ~= nil and p[2] <= 5, string.format("%s: the first new band (HYDROPONICS) arrives within 5 minutes (%s)", name, tostring(p[2])))
	end
end

--================================================================ the endless curve keeps falling, even with every upgrade (M4)
do
	local prof = Model.PROFILES.medium
	local ks = { 30, 40, 60, 80, 100, 150 }
	local ps = {}
	for _, k in ks do
		local ok = 0
		local N = 800
		for i = 1, N do
			local p = Model.plan(k, { layout = 1000003 * i + 17 + k, air = 7919 * i + 104729 + k * 3,
				loot = 15485863 * i + 32452843 + k * 5, relay = 49979687 * i + 86028121 + k * 7 })
			local r = Model.run(p, prof, { tank = 4, boots = 4 }, Model.lcg01(9001 * i + k))
			if r.ok then ok += 1 end
		end
		table.insert(ps, ok / N)
	end
	local line = {}
	for j, k in ks do table.insert(line, string.format("k%d %.3f", k, ps[j])) end
	print("       medium, all 8 ranks, P(splice) per attempt: " .. table.concat(line, "  "))
	local falling = true
	for j = 2, #ps do if ps[j] >= ps[j - 1] then falling = false end end
	truthy(falling, "the medium proxy's chance to splice falls strictly from sector 30 to 150 with every upgrade bought")
	truthy(ps[#ps] > 0.3, string.format("and the deep end is a ranking, not a wall (%.3f at 150)", ps[#ps]))
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
assert(failed == 0, "Pacing tests failed")
