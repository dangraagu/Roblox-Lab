-- Spec for PACING: when a player reaches each wing, and how often a hazard comes close.
-- Run: luau tests/Pacing.spec.luau
--
-- Minutes to a wing come from the game's own design model, not from a guess: Config.Pacing.Career is
-- design/model.luau PART 9's running total per career shift (the model's source and method are in
-- Config.lua above the table), plus an ASSUMED BetweenShiftsSeconds of human overhead per shift, since
-- the model's durations are lower bounds. The owner's brief: the brag wing (space) in 30-45 minutes for a
-- normal player; the last wing the long-term goal.
--
-- Hazard rarity is measured with tests/SortModel.luau: the game's own Hazards + Wings code on a sorter
-- walking the real bay (Layout). The brief: about one near-hit per 2-3 minutes, easy to see and avoid.
local Config = require("../src/shared/Config")
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Wings = require("../src/shared/Wings")
local Layout = require("../src/shared/Layout")
local SortModel = require("./SortModel")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local P = Config.Pacing
local bands = Config.Env.Bands

--================================================================ minutes to each wing

local function minutesTo(profile: string, shifts: number): number
	if shifts <= 0 then return 0 end
	local career = P.Career[profile]
	return career[shifts] + shifts * P.BetweenShiftsSeconds / 60
end

for name, career in P.Career do
	eq(#career, 40, "the " .. name .. " career covers 40 shifts")
	local mono = true
	for i = 2, #career do
		if career[i] <= career[i - 1] then mono = false end
	end
	truthy(mono, "the " .. name .. " career only moves forward")
	truthy(#career >= bands[#bands].from, "and reaches the last wing")
end

local N, SL = P.NormalProfile, P.SlowProfile
print("  wing                 from  normal (" .. N .. ")  slow (" .. SL .. ")")
local spaceIdx = EnvBands.indexOf(bands, Config.Env.SpaceBandId) :: number
for i, b in bands do
	print(string.format("  %-20s %4d  %6.1f min          %6.1f min", b.name, b.from, minutesTo(N, b.from), minutesTo(SL, b.from)))
end
local space = minutesTo(N, bands[spaceIdx].from)
local lo, hi = P.SpaceMinutes[1], P.SpaceMinutes[2]
truthy(space >= lo and space <= hi, string.format("a normal player reaches %s in %d-%d minutes (%.1f)", bands[spaceIdx].name, lo, hi, space))
truthy(math.abs(space - (lo + hi) / 2) <= 5, string.format("... within 5 minutes of the window's centre (%.1f vs %.1f): a retune that drifts fails loudly", space, (lo + hi) / 2))
local slowSpace = minutesTo(SL, bands[spaceIdx].from)
truthy(slowSpace <= 60, string.format("a slow reader still reaches it inside an hour (%.1f)", slowSpace))
local last = minutesTo(N, bands[#bands].from)
truthy(last >= 2 * space, string.format("the last wing is a long-term goal: at least twice the time to space (%.1f vs %.1f)", last, space))
truthy(last <= 180 and minutesTo(SL, bands[#bands].from) <= 180, "and still under 3 hours, even for a slow reader")
truthy(minutesTo(N, bands[2].from) <= 10, string.format("a normal player's first session sees a new wing within 10 minutes (%.1f)", minutesTo(N, bands[2].from)))
truthy(minutesTo(SL, bands[2].from) <= 15, string.format("a slow reader's within 15 (%.1f)", minutesTo(SL, bands[2].from)))
for i = 1, spaceIdx - 1 do
	local stay = minutesTo(N, bands[i + 1].from) - minutesTo(N, bands[i].from)
	truthy(stay >= 5, string.format("%s lasts at least 5 minutes before the next wing (%.1f)", bands[i].name, stay))
	truthy(stay <= 15, string.format("%s lasts at most 15 minutes: never monotonous (%.1f)", bands[i].name, stay))
end
do
	-- the Back Room (backlog 500) lands after 18 shifts for the regular (DESIGN.md §6.4, [M 9])
	local ending = minutesTo(N, 18)
	local w = bands[EnvBands.indexAt(bands, 18)].name
	print(string.format("  the Back Room ending (18 shifts for a regular): %.1f min, in the %s wing", ending, w))
	truthy(EnvBands.indexAt(bands, 18) >= spaceIdx, "a regular opens the Back Room after reaching space")
end

--================================================================ hazard rarity on the real bay

local HzCfg = Config.Hazards
local MIN = 180 -- minutes of running shift clock per wing and mode
-- THE PROMISE (EYECANDY.md §3), as literals: a knock never comes sooner than 2 s after its warning appeared
-- nor sooner than 1 s after its ring turned red, WHATEVER the player does (walking into it included). These
-- are the owner-facing numbers; they are deliberately not read from Config, so a retune of Config cannot
-- quietly lower them and still pass (REVIEW-2 finding 6).
local PROMISE_WARN, PROMISE_RED = 2.0, 1.0
local FRAME = 1 / 30
local totals = {
	ignores = { minutes = 0, hazards = 0, hits = 0, near = 0, lost = 0 },
	reacts = { minutes = 0, hazards = 0, hits = 0, near = 0, lost = 0 },
	stands = { minutes = 0, hazards = 0, hits = 0, near = 0, lost = 0 },
}
print(string.format("  hazards on a regular sorter's shift clock (%d min per wing and sorter; Config.Pacing.Sorter, reacting %.1f s after the ring turns red)",
	MIN, P.Sorter.reactSeconds))
for i, b in bands do
	if #(b.hazards or {}) > 0 then
		for _, mode in { "ignores", "reacts", "stands" } do
			local st = SortModel.run({ Config = Config, Hazards = Hazards, Wings = Wings, Layout = Layout,
				kinds = b.hazards, minutes = MIN, mode = mode, seed = 1000 + i })
			local t = totals[mode]
			t.minutes += st.minutes
			t.hazards += st.hazards
			t.hits += st.hits
			t.near += st.near
			t.lost += st.lostSeconds
			print(string.format("    %-18s %-7s %3d hazards (%.3f/min)  near-hits %.3f/min  hits %.3f/min  lanes %.1f-%.1f studs  waited for room %.0f s  spared by the promise %d",
				b.name, mode, st.hazards, st.hazards / st.minutes, st.near / st.minutes, st.hits / st.minutes, st.minLane, st.maxLane, st.deferredSeconds, st.spared or 0))
			eq(st.badStarts, 0, b.name .. " (" .. mode .. "): every lane starts on the floor, off the walls")
			eq(st.shortWarnings, 0, b.name .. " (" .. mode .. "): no warning is shortened by fitting the lane to the floor")
			truthy(st.minLane >= HzCfg.MinLaneStuds - 1e-6, b.name .. " (" .. mode .. "): every lane is at least MinLaneStuds long")
			truthy(st.hazards / st.minutes >= 1 / 3 - 0.02 and st.hazards / st.minutes <= 1 / 2,
				string.format("%s: one hazard per 2-3 minutes of shift clock (%.3f/min)", b.name, st.hazards / st.minutes))
			if st.hits > 0 then
				-- every sorter, the walking ones included: how long did each warning give them?
				print(string.format("      knocked %d times: each at least %.2f s after its warning appeared and %.2f s after its ring turned red",
					st.hits, st.minWarnToHit or -1, st.minLockToHit or -1))
				truthy(st.minWarnToHit >= PROMISE_WARN - 1e-6,
					string.format("%s (%s): every knock comes at least %.1f s after its warning appeared (%.2f)", b.name, mode, PROMISE_WARN, st.minWarnToHit))
				truthy(st.minLockToHit >= PROMISE_RED - FRAME - 1e-6,
					string.format("%s (%s): ... and at least %.1f s (less a frame) after its ring turned red (%.2f)", b.name, mode, PROMISE_RED, st.minLockToHit))
			end
			if mode == "reacts" then
				eq(st.hits, 0, string.format("%s: a sorter who reacts to everything %.1f s late (and walks the whole time) is never hit",
					b.name, P.Sorter.reactSeconds))
			elseif mode == "stands" then
				truthy(st.hits > 0, b.name .. ": CONTROL: a player who stays put is knocked (the promise above is not vacuous)")
			end
		end
	end
end
do
	local r, g = totals.reacts, totals.ignores
	local rNear, gHits, gNear = r.near / r.minutes, g.hits / g.minutes, g.near / g.minutes
	print(string.format("  all wings: reacting sorter %.3f near-hits/min (one per %.1f min), %d hits; ignoring sorter %.3f near-hits/min, %.3f hits/min (one per %.1f min), %.2f%% of shift time lost to stumbles",
		rNear, 1 / rNear, r.hits, gNear, gHits, 1 / math.max(gHits, 1e-9), 100 * g.lost / (g.minutes * 60)))
	truthy(rNear >= 1 / 3 - 0.03 and rNear <= 1 / 2,
		string.format("a sorter who reacts meets about one near-hit per 2-3 minutes (%.3f/min)", rNear))
	truthy(gHits <= 0.2, string.format("a sorter who ignores every warning is knocked at most once per 5 minutes (%.3f/min)", gHits))
	truthy(g.lost / (g.minutes * 60) <= 0.02, "stumbles cost an ignoring sorter at most 2% of the shift clock")
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
