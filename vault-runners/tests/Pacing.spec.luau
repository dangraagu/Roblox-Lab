-- Pacing — how long until each environment band, how often a ceiling drop comes, and what a drop
-- costs a run. Run: luau tests/Pacing.spec.luau
--
-- Everything here is MEASURED by playing the real vaults with tests/VaultModel.luau (real seeds, real
-- countdowns, the real kill rule, the real hazard scheduler and eligibility). The human part is the
-- profile in Config.Pacing, written down rather than hidden. There is no telemetry yet: every minute
-- below is a model, and the spec's job is to say loudly when a retune moves it.
--
-- What the owner's brief asks, and what is asserted:
--   * the world changes as you progress and never feels monotonous: a new band early (the tomb within
--     10 minutes), the Frozen Vault as the thing a normal player reaches and brags about (45-90 min),
--     the Volcano Temple as the long-term goal (at least twice as far, inside 5 hours); no band flashes
--     past in under 4 minutes; unlocking a tier never sends a player back to an earlier band;
--   * hazards are RARE — one per 120-180 s of run time — and easy to avoid: a player who reacts to the
--     ring is never hit, a player who stands still in it always is (the ring is the rule);
--   * THE TIME BUDGET DOES NOT CHANGE. The countdown is VaultPath's, byte for byte (Collapse.spec and
--     Curve.spec still pass untouched). What a drop does to a run is measured here: nothing for a
--     player who moves, and at most a point or so of completion for one who ignores every warning.
--     That last number is measured on the `reader` profile (3 s at every new junction), because the
--     normal player never stands still long enough to be hit even when they ignore every warning —
--     a cost measured on a player who is never hit would be zero by construction, not by design.
local deps = {
	Config = require("../src/shared/Config"),
	Progression = require("../src/shared/Progression"),
	VaultFloor = require("../src/shared/VaultFloor"),
	VaultPath = require("../src/shared/VaultPath"),
	MazeGen = require("../src/shared/MazeGen"),
	Rng = require("../src/shared/Rng"),
	RunState = require("../src/shared/RunState"),
	Hazards = require("../src/shared/Hazards"),
	VaultEnv = require("../src/shared/VaultEnv"),
	EnvBands = require("../src/shared/EnvBands"),
}
local VaultModel = require("./VaultModel")
local M = VaultModel.new(deps)
local C = deps.Config
local EnvBands = deps.EnvBands
local bands = C.Env.Bands

local passed, failed = 0, 0
local function ok(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end

local function idx(id: string): number
	return assert(EnvBands.indexOf(bands, id), "no band " .. id)
end
local TOMB, REACTOR, FROZEN, VOLCANO = idx("tomb"), idx("reactor"), idx("frozen"), idx("volcano")

--============================================================================ when each band arrives

local careers = {}
for _, name in { "normal", "fast", "slow" } do
	careers[name] = {}
	for _, seed in { 7, 8 } do
		careers[name][seed] = M:career({
			profile = C.Pacing.Profiles[name], hazards = "reacts", capMinutes = 480, stopWhenAll = true, seed = seed,
		})
	end
end

print("  minutes of play until a normal / fast / slow player first runs a vault in each band (two seeds):")
for i, b in bands do
	local cells = {}
	for _, name in { "normal", "fast", "slow" } do
		for _, seed in { 7, 8 } do
			local m = careers[name][seed].reachedAt[i]
			cells[#cells + 1] = if m then string.format("%6.1f", m) else "     -"
		end
	end
	print(string.format("    %-3s %-15s depth %3d  %s", b.emoji, b.name, b.from, table.concat(cells, " ")))
end
for _, name in { "normal", "fast", "slow" } do
	local c = careers[name][7]
	print(string.format("    (%s: Silver unlocks at %.0f min, Gold at %s)", name, c.tierAt[2] or -1,
		if c.tierAt[3] then string.format("%.0f min", c.tierAt[3]) else "past the run"))
end

for _, seed in { 7, 8 } do
	local r = careers.normal[seed].reachedAt
	ok(r[TOMB] ~= nil and r[TOMB] <= 10, string.format("seed %d: a normal player reaches the tomb within 10 min (%.1f)", seed, r[TOMB] or -1))
	ok(r[REACTOR] ~= nil and r[REACTOR] >= 15 and r[REACTOR] <= 40,
		string.format("seed %d: the reactor arrives at 15-40 min (%.1f)", seed, r[REACTOR] or -1))
	ok(r[FROZEN] ~= nil and r[FROZEN] >= 45 and r[FROZEN] <= 90,
		string.format("seed %d: the Frozen Vault — the one to brag about — at 45-90 min (%.1f)", seed, r[FROZEN] or -1))
	ok(r[VOLCANO] ~= nil and r[VOLCANO] >= 2 * r[FROZEN] and r[VOLCANO] <= 300,
		string.format("seed %d: the Volcano Temple is the long-term goal: at least twice the Frozen Vault and inside 5 h (%.1f)",
			seed, r[VOLCANO] or -1))
	local shortest, at = math.huge, ""
	for i = 1, #bands - 1 do
		local len = (r[i + 1] or math.huge) - (r[i] or 0)
		if len < shortest then shortest, at = len, bands[i].name end
	end
	ok(shortest >= 4, string.format("seed %d: no band flashes past (shortest: %s, %.1f min)", seed, at, shortest))
	-- the slow player gets there too, just later
	local s = careers.slow[seed].reachedAt
	ok(s[FROZEN] ~= nil and s[FROZEN] <= 120, string.format("seed %d: a slow player still reaches the ice within 2 h (%.1f)", seed, s[FROZEN] or -1))
end

-- A new tier must open in the band the player is already in, or deeper: never back to the bank.
do
	local worst = nil
	local VaultEnv = deps.VaultEnv
	for _, name in { "normal", "fast", "slow" } do
		for _, seed in { 7, 8 } do
			local r = M:career({ profile = C.Pacing.Profiles[name], hazards = "off", capMinutes = 480, seed = seed })
			for _, u in r.unlocks or {} do
				local fromBand = EnvBands.indexAt(bands, u.depthBefore)
				local toBand = EnvBands.indexAt(bands, VaultEnv.depth(C, u.tier, 1))
				if toBand < fromBand then
					worst = worst or string.format("%s seed %d: unlocking tier %d at depth %d (%s) opens at %s",
						name, seed, u.tier, u.depthBefore, bands[fromBand].name, bands[toBand].name)
				end
			end
			ok(r.unlocks ~= nil and #r.unlocks >= 1, string.format("(%s seed %d unlocked at least one tier: %d)", name, seed, r.unlocks and #r.unlocks or 0))
		end
	end
	ok(worst == nil, "unlocking a tier never sends a player back to an earlier band: " .. tostring(worst))
end

--============================================================================ how often a drop comes

do
	for _, behaviour in { "reacts", "ignores", "freezes" } do
		local spawned, hits, runSec, landings = 0, 0, 0, {}
		for _, seed in { 7, 8 } do
			local r = M:career({ profile = C.Pacing.Profiles.normal, hazards = behaviour, capMinutes = 240, seed = seed })
			spawned += r.hz.spawned
			hits += r.hz.hits
			runSec += r.hz.runSeconds
			for _, d in r.hz.landings do table.insert(landings, d) end
		end
		table.sort(landings)
		local perMin = spawned / (runSec / 60)
		local function pct(p: number): number return landings[math.max(1, math.floor(#landings * p))] or -1 end
		local within = 0
		for _, d in landings do if d <= C.Pacing.Profiles.normal.NearStuds then within += 1 end end
		print(string.format("  %-7s %d drops in %.0f run-minutes = one per %.2f min; hit %d (%.1f%%); landed a median %.1f studs from the player (p10 %.1f, p90 %.1f); within %d studs: %d",
			behaviour, spawned, runSec / 60, 1 / perMin, hits, 100 * hits / math.max(1, spawned), pct(0.5), pct(0.1), pct(0.9),
			C.Pacing.Profiles.normal.NearStuds, within))
		ok(perMin >= 60 / C.Hazards.IntervalMax * 0.9 and perMin <= 60 / C.Hazards.IntervalMin,
			string.format("%s: one drop per 2-3 minutes of run time (%.2f per min)", behaviour, perMin))
		if behaviour == "reacts" then
			ok(hits == 0, "a player who reacts to the ring is never hit (" .. hits .. ")")
		elseif behaviour == "ignores" then
			ok(hits / math.max(1, spawned) <= 0.1, string.format("a player who ignores every warning is hit by at most 1 drop in 10 (%.1f%%)", 100 * hits / math.max(1, spawned)))
		else
			ok(hits / math.max(1, spawned) >= 0.9, string.format("a player who stands still in the ring is hit (the ring is the rule): %.1f%%", 100 * hits / math.max(1, spawned)))
		end
	end
end

--============================================================================ what a drop does to a run

-- Common random numbers: every mode walks the same mazes with the same explorer choices; only the
-- hazards differ. The countdown is VaultPath's in every mode — the budget is not a variable here.
do
	local FLOORS = { 1, 30, 100, 400 }
	local MAZES, TRIALS = 30, 5
	local rates = {}
	for _, mode in { "off", "reacts", "ignores" } do
		rates[mode] = {}
		for fi, floor in FLOORS do
			local w, n = 0, 0
			for k = 1, MAZES do
				local model, spec = M:vault(3, floor, k * 2654435761 + floor * 7919)
				for j = 1, TRIALS do
					local hzRand = VaultModel.lcg(k * 31 + j * 7 + floor)
					local hs = deps.Hazards.newScheduler(C.Hazards, hzRand)
					hs.clock = hs.nextAt * hzRand() -- steady state: the next drop is anywhere in its interval
					local res = M:play(model, spec, {
						profile = C.Pacing.Profiles.normal, retry = false, rand = VaultModel.lcg(k * 131 + j * 977 + floor),
						hazards = mode, hazardState = hs, hazRand = hzRand,
						kinds = bands[EnvBands.indexAt(bands, deps.VaultEnv.depth(C, 3, floor))].hazards,
					})
					n += 1
					if res.escaped then w += 1 end
				end
			end
			rates[mode][fi] = w / n
		end
	end
	local line = {}
	for fi, floor in FLOORS do
		line[#line + 1] = string.format("f%d %.1f/%.1f/%.1f", floor, 100 * rates.off[fi], 100 * rates.reacts[fi], 100 * rates.ignores[fi])
	end
	print("  Gold completion, first attempt (no hazards / reacts / ignores every warning): " .. table.concat(line, "  "))
	for fi, floor in FLOORS do
		ok(math.abs(rates.reacts[fi] - rates.off[fi]) <= 0.02,
			string.format("floor %d: drops change nothing for a player who reacts (%.1f vs %.1f)", floor, 100 * rates.reacts[fi], 100 * rates.off[fi]))
		ok(rates.off[fi] - rates.ignores[fi] <= 0.03,
			string.format("floor %d: even ignoring every warning costs at most 3 points (%.1f vs %.1f)", floor, 100 * rates.ignores[fi], 100 * rates.off[fi]))
	end
	for fi = 2, #FLOORS do
		ok(rates.ignores[fi] < rates.ignores[fi - 1],
			string.format("with drops, deeper is still harder (floor %d %.1f vs floor %d %.1f)", FLOORS[fi], 100 * rates.ignores[fi],
				FLOORS[fi - 1], 100 * rates.ignores[fi - 1]))
	end
end

--============================================================================ what a HIT costs

-- The reader stops 3 s at every new junction: the player a drop can actually land on. Same common
-- random numbers per mode; only the hazards differ. Floors where a reader still escapes often
-- enough for a difference to show: Bronze 1, Bronze 10, Gold 1.
do
	local R = C.Pacing.Profiles.reader
	local CASES = { { 1, 1 }, { 1, 10 }, { 3, 1 } }
	local MAZES, TRIALS = 30, 5
	local hitsAll, spawnedAll = 0, 0
	local line = {}
	for _, case in CASES do
		local tier, floor = case[1], case[2]
		local kinds = bands[EnvBands.indexAt(bands, deps.VaultEnv.depth(C, tier, floor))].hazards
		local rate = {}
		for _, mode in { "off", "reacts", "ignores" } do
			local w, n, hits, spawned = 0, 0, 0, 0
			for k = 1, MAZES do
				local model, spec = M:vault(tier, floor, k * 2654435761 + floor * 7919 + tier * 104729)
				for j = 1, TRIALS do
					local hzRand = VaultModel.lcg(k * 31 + j * 7 + floor + tier * 1009)
					local hs = deps.Hazards.newScheduler(C.Hazards, hzRand)
					hs.clock = hs.nextAt * hzRand()
					local res = M:play(model, spec, {
						profile = R, retry = false, rand = VaultModel.lcg(k * 131 + j * 977 + floor + tier * 7),
						hazards = mode, hazardState = hs, hazRand = hzRand, kinds = kinds,
					})
					n += 1
					if res.escaped then w += 1 end
					hits += res.hz.hits
					spawned += res.hz.spawned
				end
			end
			rate[mode] = { p = w / n, hits = hits, spawned = spawned }
		end
		local name = string.format("%s %d", C.Tiers[tier].name, floor)
		line[#line + 1] = string.format("%s %.1f/%.1f/%.1f (hit %d of %d)", name, 100 * rate.off.p, 100 * rate.reacts.p, 100 * rate.ignores.p,
			rate.ignores.hits, rate.ignores.spawned)
		ok(rate.reacts.hits == 0, name .. ": a reader who reacts to the ring is never hit (" .. rate.reacts.hits .. ")")
		-- ONE-SIDED on purpose. The first draft of this line was two-sided (|reacts - off| <= 2 points)
		-- and failed the other way: Gold 1 33.3 with drops against 30.0 without. A reader who reacts
		-- cuts their 3 s junction pause short to step on (VaultModel's "reacts"), and in the model a pause
		-- buys nothing (the route choice does not depend on it), so a drop HURRIES a reader and the model
		-- scores that as time saved. What the brief forbids is the other direction: a drop that makes a
		-- reacting player's run harder. Whether real hurrying costs wrong turns is on the playtest list.
		ok(rate.off.p - rate.reacts.p <= 0.02,
			string.format("%s: drops cost a reader who reacts nothing (%.1f vs %.1f)", name, 100 * rate.reacts.p, 100 * rate.off.p))
		ok(rate.off.p - rate.ignores.p <= 0.03,
			string.format("%s: a reader who ignores every warning loses at most 3 points (%.1f vs %.1f)", name, 100 * rate.ignores.p, 100 * rate.off.p))
		hitsAll += rate.ignores.hits
		spawnedAll += rate.ignores.spawned
	end
	print("  reader (3 s per new junction), first attempt (no drops / reacts / ignores every warning): " .. table.concat(line, "  "))
	-- A SAMPLE, not a token: at 0.6 s per junction (the normal player) the same runs see a hit or two, and
	-- a cost measured on one or two hits is not a measurement. The mutation sweep caught ">0" passing that.
	ok(hitsAll >= 20, string.format("the reader who ignores every warning IS hit, often enough to measure what a hit costs (%d of %d drops; want >= 20)",
		hitsAll, spawnedAll))
	-- the same bound +1 Jump's Pacing.spec puts on its climber who ignores every warning: fewer than half
	ok(hitsAll / math.max(1, spawnedAll) < 0.5, string.format("but by fewer than half of them (%.1f%%): standing still is what gets you hit",
		100 * hitsAll / math.max(1, spawnedAll)))
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
