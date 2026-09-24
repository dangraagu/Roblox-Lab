-- Pacing + rarity + medal fairness, MEASURED on the game's own mazes. Run: luau tests/Pacing.spec.luau
--
-- Nothing here is assumed: every number EYECANDY.md reports is printed by this file and the
-- bounds that matter are asserted, so a retune that drifts fails loudly. The player is the
-- tests/MazeWalker.luau model (MazeGen at the live curve, the server's trap draw, a depth-first
-- explorer that heads for the exit corner at forks with probability `bias`). What it asserts:
--   * RARITY (owner's brief: about one near-hit every 2-3 minutes, easy to see and avoid): a
--     normal player who reacts to the warning gets 0.33-0.5 near-hits per minute over every
--     hazard band, 0.3-0.55 in each band, and is never hit; a player who ignores every warning is
--     hit, but rarely;
--   * no hazard in the first two biomes, and none before its band starts;
--   * PACING: the first new biome comes within ten minutes; every biome lasts at least five;
--   * MEDAL FAIRNESS: on the par route a speedrunner loses at most a fraction of a second to a
--     hazard it has to let fall first, far inside the 30 % slack between par and Diamond; and it
--     is the same fraction for everyone on that level, because placement and timing are fixed.
local MazeGen = require("../src/shared/MazeGen")
local Medals = require("../src/shared/Medals")
local EnvBands = require("../src/shared/EnvBands")
local Biomes = require("../src/shared/Biomes")
local CellHazards = require("../src/shared/CellHazards")
local W = require("./MazeWalker")

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local CURVE = W.CURVE
local CFG = Biomes.Hazards
local PROFILES = W.PROFILES
local bands = Biomes.Bands

--================================================================ pacing

print("== minutes of play to START each biome (model, no deaths; normal / fast / slow)")
local startMin = { normal = {}, fast = {}, slow = {} }
for _, name in { "normal", "fast", "slow" } do
	local p = PROFILES[name]
	local cum = 0
	local bi = 2
	startMin[name][1] = 0
	for L = 1, bands[#bands].from do
		while bi <= #bands and L == bands[bi].from do
			startMin[name][bi] = cum / 60
			bi += 1
		end
		local lv = W.level(MazeGen, CURVE, L, 1000 + L)
		cum += W.explore(lv, W.rng(L * 31 + 5), p).duration
	end
end
for i, b in bands do
	print(string.format("  %-2s %-16s from L%-4d normal %7.1f  fast %7.1f  slow %7.1f", b.emoji, b.name, math.max(1, b.from),
		startMin.normal[i], startMin.fast[i], startMin.slow[i]))
end
truthy(startMin.normal[2] <= 10, string.format("the first new biome arrives within 10 min for a normal player (%.1f)", startMin.normal[2]))
truthy(startMin.normal[3] <= 25, string.format("the second within 25 min (%.1f)", startMin.normal[3]))
for i = 2, #bands do
	truthy(startMin.normal[i] - startMin.normal[i - 1] >= 5,
		string.format("%s lasts at least 5 minutes for a normal player (%.1f)", bands[i - 1].name, startMin.normal[i] - startMin.normal[i - 1]))
	truthy(startMin.fast[i] <= startMin.normal[i] and startMin.normal[i] <= startMin.slow[i], "fast <= normal <= slow at " .. bands[i].name)
end

--================================================================ rarity

print("== hazards per band (40 levels spread over each hazard band, one normal walk each)")
local SAMPLES = 40
local total = { react = { t = 0, near = 0, hits = 0 }, ignore = { t = 0, near = 0, hits = 0 } }
local cellsTotal, hazardsTotal = 0, 0
for bi, b in bands do
	if b.hazard then
		local res = { react = { t = 0, near = 0, hits = 0 }, ignore = { t = 0, near = 0, hits = 0 } }
		local nextFrom = if bands[bi + 1] then bands[bi + 1].from else b.from + 150
		for s = 0, SAMPLES - 1 do
			local L = b.from + math.floor(s * (nextFrom - b.from) / SAMPLES)
			local lv = W.level(MazeGen, CURVE, L, 4242)
			local walk = W.explore(lv, W.rng(L * 13 + 7), PROFILES.normal)
			local hz = W.hazardsFor(lv, CellHazards, Biomes.Seed, CFG)
			cellsTotal += lv.cols * lv.rows
			hazardsTotal += #hz
			for _, pol in { "react", "ignore" } do
				local r = W.simulate(walk, hz, CFG, pol, CellHazards)
				res[pol].t += r.duration; res[pol].near += r.near; res[pol].hits += r.hits
				total[pol].t += r.duration; total[pol].near += r.near; total[pol].hits += r.hits
			end
		end
		local rn = res.react.near / (res.react.t / 60)
		local rh = res.react.hits / (res.react.t / 60)
		local ih = res.ignore.hits / (res.ignore.t / 60)
		local inr = res.ignore.near / (res.ignore.t / 60)
		print(string.format("  %-2s %-16s react: %.3f near/min (one per %.1f min), %.3f hits/min | ignores: %.3f near/min, %.3f hits/min | %4.0f min walked",
			b.emoji, b.name, rn, 1 / rn, rh, inr, ih, res.react.t / 60))
		truthy(rn >= 0.3 and rn <= 0.55, string.format("%s: a reacting player gets 0.3-0.55 near-hits a minute (%.3f)", b.name, rn))
		eq(res.react.hits, 0, b.name .. ": a player who reacts to the warning is never hit")
	end
end
local rn = total.react.near / (total.react.t / 60)
local ih = total.ignore.hits / (total.ignore.t / 60)
local inr = total.ignore.near / (total.ignore.t / 60)
print(string.format("  ALL react %.3f near/min (one per %.2f min), 0 hits | ignores %.3f near/min, %.3f hits/min (one per %.1f min) | %.0f min walked | %d hazards in %d cells (%.4f)",
	rn, 1 / rn, inr, ih, 1 / ih, total.react.t / 60, hazardsTotal, cellsTotal, hazardsTotal / cellsTotal))
truthy(rn >= 1 / 3 and rn <= 0.5, string.format("over all hazard bands: one near-hit every 2-3 minutes (%.3f/min)", rn))
eq(total.react.hits, 0, "a reacting player is never hit")
truthy(ih > 0, "a player who ignores every warning does get hit (the hazards are real)")
truthy(ih <= 0.12, string.format("but rarely: at most about one hit per 8 minutes (%.3f/min)", ih))

-- no hazards before the ice cellar
for L = 1, bands[3].from - 1 do
	if Biomes.hazardKindAt(EnvBands, L) ~= nil then truthy(false, "no hazard at level " .. L) end
end
passed += 1
eq(Biomes.hazardKindAt(EnvBands, bands[3].from), bands[3].hazard, "the first hazard band starts exactly at its level")

--================================================================ medal fairness

print("== medal fairness: par route, a speedrunner who lets a falling hazard land first")
local worstFrac, worstAbs, worstSingle = 0, 0, 0
local sumDelay, sumPar, levels, affected = 0, 0, 0, 0
local ignoreHits, ignoreLevels = 0, 0
for bi, b in bands do
	if b.hazard then
		local nextFrom = if bands[bi + 1] then bands[bi + 1].from else b.from + 150
		for s = 0, SAMPLES - 1 do
			local L = b.from + math.floor(s * (nextFrom - b.from) / SAMPLES)
			local lv = W.level(MazeGen, CURVE, L, 4242)
			local route = W.parRoute(lv, Medals.dist, PROFILES.normal)
			local hz = W.hazardsFor(lv, CellHazards, Biomes.Seed, CFG)
			local r = W.simulate(route, hz, CFG, "runner", CellHazards)
			local delay = r.duration - route.duration
			levels += 1
			sumDelay += delay
			sumPar += route.duration
			if delay > 0.06 then affected += 1 end
			worstAbs = math.max(worstAbs, delay)
			worstSingle = math.max(worstSingle, r.maxWait)
			worstFrac = math.max(worstFrac, delay / route.duration)
			eq(r.hits, 0, "the runner is never hit on L" .. L)
			local ri = W.simulate(route, hz, CFG, "ignore", CellHazards)
			ignoreHits += ri.hits
			ignoreLevels += 1
		end
	end
end
print(string.format("  %d levels: %d delayed at all; mean delay %.3f s (%.3f %% of par); worst level %.2f s (%.2f %% of par); longest single wait %.2f s; a runner ignoring hazards is hit %d times in %d levels",
	levels, affected, sumDelay / levels, 100 * sumDelay / sumPar, worstAbs, 100 * worstFrac, worstSingle, ignoreHits, ignoreLevels))
local crossing = (CFG.StrikeRadius + CFG.PlayerRadius) * 2 / CFG.WalkSpeed
truthy(worstSingle <= crossing + 0.15,
	string.format("a single wait never exceeds one crossing of the danger zone (%.2f s <= %.2f s)", worstSingle, crossing + 0.15))
truthy(worstAbs <= 2.5, string.format("no level costs a speedrunner more than 2.5 s in all (%.2f s)", worstAbs))
truthy(worstFrac < 0.05, string.format("never more than 5 %% of par, against 30 %% slack to Diamond (%.2f %%)", 100 * worstFrac))
truthy(sumDelay / sumPar < 0.005, string.format("on average under 0.5 %% of par (%.3f %%)", 100 * sumDelay / sumPar))

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing spec failed", 0) end
