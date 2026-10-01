-- Pacing: when a normal player meets the brag, and how far the long-term goal is. Run: luau tests/Pacing.spec.luau
--
-- docs/complete-game-standard.md §2: "A brag moment within about 30-45 minutes of normal play, and a long-term goal
-- beyond it. Measure the minutes with a pacing model in tests/." The model is tests/DigModel.luau: the pace bot's
-- policy played on the pure modules over EIGHT drawn cave sequences (every rebirth digs a cave of its own, from a
-- key, as the server draws them). Its end-to-end twin, ../robloxemu/check_deepvein_pace.luau, plays the same bot
-- through the real server on one sequence; the two are separate measurements of the same rules.
--
-- The brag is the magma (🔥 YOU REACHED THE MAGMA!, the first fanfare). Owner decision (a), 2026-09-30 (EYECANDY.md
-- §12): it stays at layer 40, the bottom of the rebirth-2 shaft, so a player meets it on their THIRD run, within
-- 45 minutes. The long-term goal is the core (🌋, layer 150, the deepest band and the last fanfare), and the board.

local Config = require("../src/shared/Config")
local M = {
	Mine = require("../src/shared/Mine"),
	Ore = require("../src/shared/Ore"),
	Economy = require("../src/shared/Economy"),
	Prestige = require("../src/shared/Prestige"),
	EnvBands = require("../src/shared/EnvBands"),
}
local DigModel = require("./DigModel")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local bands = Config.Env.Bands
local P = Config.Pacing.Profiles
local function bandIndex(id)
	for i, b in bands do if b.id == id then return i end end
	return nil
end
local MAGMA, CORE, RIVER = bandIndex("magma"), bandIndex("core"), bandIndex("river")
truthy(MAGMA ~= nil and CORE ~= nil and RIVER ~= nil, "the river, the magma and the core are strata")

-- the first rebirth whose wall reaches the core's first layer: the model plays that far
local coreRun = 0
while M.Mine.maxLayer(Config, coreRun) < bands[CORE].from do coreRun += 1 end

-- Eight cave sequences to the magma (three runs each, cheap); the first of them on to the core (twelve runs, about
-- 15 s of CPU; the end-to-end check_deepvein_pace plays a second sequence to the core through the real server).
local SAMPLES, CORE_SAMPLES = 8, 1
local function keysFor(s)
	return function(r)
		return { a = M.Mine.hash(20261001, s, r, 7, 1), b = M.Mine.hash(20261001, s, r, 7, 2) }
	end
end

local magmaN, coreN, riverN, firstN, magmaRun = {}, {}, {}, {}, {}
local ordered, everyReached = true, true
local t0 = os.clock()
for s = 1, SAMPLES do
	local res = DigModel.play(Config, M, keysFor(s), if s <= CORE_SAMPLES then coreRun else 2)
	local runs, reached = res.runs, res.reached
	if s <= CORE_SAMPLES then
		for i = 1, #bands do
			if reached[i] == nil then everyReached = false end
		end
	end
	local prev = -1
	for i = 1, #bands do
		local at = reached[i]
		if at then
			local mnt = DigModel.minutes(P.normal, at)
			if mnt < prev then ordered = false end
			prev = mnt
		end
	end
	local cum, before = { swings = 0, blocks = 0, trips = 0 }, {}
	for r, run in runs do
		before[r] = DigModel.minutes(P.normal, cum)
		cum.swings += run.swings
		cum.blocks += run.blocks
		cum.trips += run.trips
	end
	before[#runs + 1] = DigModel.minutes(P.normal, cum)
	firstN[s] = before[2]
	if reached[MAGMA] then
		magmaN[s] = { normal = DigModel.minutes(P.normal, reached[MAGMA]), fast = DigModel.minutes(P.fast, reached[MAGMA]),
			slow = DigModel.minutes(P.slow, reached[MAGMA]) }
		-- which run: the magma's first block broken after `before[k]` and before `before[k+1]`
		for k = 1, #runs do
			if magmaN[s].normal > before[k] and magmaN[s].normal <= before[k + 1] then magmaRun[s] = k end
		end
	end
	if reached[CORE] then coreN[s] = DigModel.minutes(P.normal, reached[CORE]) end
	if reached[RIVER] then riverN[s] = DigModel.minutes(P.normal, reached[RIVER]) end
	print(string.format("  cave sequence %d: river %5.1f, first rebirth %5.1f, MAGMA %5.1f (run %s; fast %4.1f, slow %4.1f), core %6.1f min",
		s, riverN[s] or -1, firstN[s] or -1, magmaN[s] and magmaN[s].normal or -1, tostring(magmaRun[s]),
		magmaN[s] and magmaN[s].fast or -1, magmaN[s] and magmaN[s].slow or -1, coreN[s] or -1))
end
print(string.format("  (%d cave sequences, %d of them to the core, in %.1f s of CPU)", SAMPLES, CORE_SAMPLES, os.clock() - t0))

local lo, hi, cLo = math.huge, -math.huge, math.huge
for s = 1, SAMPLES do
	local m = magmaN[s]
	truthy(m ~= nil, "sequence " .. s .. ": the magma is reached by playing")
	if m then
		lo, hi = math.min(lo, m.normal), math.max(hi, m.normal)
		truthy(magmaRun[s] == 3, string.format("sequence %d: the magma comes in the THIRD run, after two rebirths (run %s)", s, tostring(magmaRun[s])))
		truthy(m.normal >= 20 and m.normal <= 45, string.format(
			"sequence %d: a normal player reaches the magma (the brag) within 45 minutes, not before 20 (%.1f)", s, m.normal))
	end
	truthy(riverN[s] ~= nil and firstN[s] ~= nil and riverN[s] < firstN[s], string.format(
		"sequence %d: the underground river comes before the first rebirth (%.1f < %.1f)", s, riverN[s] or -1, firstN[s] or -1))
	if s <= CORE_SAMPLES then
		truthy(coreN[s] ~= nil and m ~= nil and coreN[s] >= 3 * m.normal, string.format(
			"sequence %d: the core is the long-term goal, at least 3x the magma (%.0f min)", s, coreN[s] or -1))
	end
	if coreN[s] then cLo = math.min(cLo, coreN[s]) end
end
truthy(everyReached, "every stratum is reached by playing, in every sequence played to the core")
truthy(ordered, "and each after the one above it")
print(string.format("  the magma: %.1f-%.1f min of normal play over %d cave sequences; the core from %.0f min", lo, hi, SAMPLES, cLo))

print(string.format("Pacing: %d passed, %d failed", passed, failed))
assert(failed == 0, "Pacing tests failed")
