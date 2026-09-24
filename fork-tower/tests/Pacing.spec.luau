-- Pacing and hazard rarity, MEASURED on the game's own tower. Run: luau tests/Pacing.spec.luau
--
-- tests/PlayModel.luau plays whole runs of Fork Tower (real Section.build towers, the real Hazards
-- scheduler behind the real Climb gate) with the human profiles in Config.Pacing, and this spec
-- holds the numbers EYECANDY.md reports to the owner's brief (2026-09-17):
--   * hazards are RARE: about one near-hit per 2-3 minutes of play, for a player who reacts to the
--     warning, and that player is never hit;
--   * the fork pad is a sanctuary: nothing launches there and nothing hits there, and the hazard
--     clock runs only while climbing, so reading and deciding never brings a hazard closer;
--   * resting freezes the clock without resetting it, so toggling rest does not thin hazards;
--   * hazards do not make the read's price meaningless: they only ever make a trap a little costlier
--     for a climber who ignores warnings, and the measured shift of the read's break-even is small;
--   * the environment changes every band within one run, never lingering.
local PlayModel = require("./PlayModel")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local P = Config.Pacing.Profiles
local Hz = Config.Hazards
local FLOORS = Config.Tower.Floors
local RUNS = 80
local DT = 0.05

local results = {}
local function play(profileName, strategy, behavior, extra)
	local key = profileName .. "/" .. strategy .. "/" .. behavior .. (if extra then "/x" else "")
	if results[key] then return results[key] end
	local opts = { cfg = Config, profile = P[profileName], runs = RUNS, seed = 7, strategy = strategy, behavior = behavior, dt = DT }
	for k, v in extra or {} do opts[k] = v end
	local s = PlayModel.play(opts)
	results[key] = s
	return s
end

print("Fork Tower pacing — measured (" .. RUNS .. " runs per row, camera pitch -15, dt " .. DT .. ")")
print("  profile strategy behavior | min/run | hazards/min | near-hits/min | hits/min | hit share | climb share")
for _, name in { "fast", "normal", "slow" } do
	for _, strategy in { "read", "guess" } do
		for _, behavior in { "dodge", "ignore" } do
			local s = play(name, strategy, behavior)
			print(string.format("  %-7s %-8s %-8s |  %5.2f  |    %.3f    |     %.3f     |  %.3f   |   %.2f    |   %.2f",
				name, strategy, behavior, s.minutesPerRun, s.perMinute, s.nearPerMinute, s.hitsPerMinute, s.hitShare,
				s.climbSeconds / s.seconds))
		end
	end
end

--================================================================ rarity

-- "About one near-hit per 2-3 minutes", for the player the warning is for: one who reacts.
do
	local s = play("normal", "read", "dodge")
	truthy(s.nearPerMinute >= 1 / 3 and s.nearPerMinute <= 1 / 2,
		string.format("normal reader who reacts: one near-hit per 2-3 min of play (%.3f/min = one per %.1f min)", s.nearPerMinute, 1 / s.nearPerMinute))
	truthy(s.perMinute >= 1 / 3 and s.perMinute <= 1 / 2,
		string.format("normal reader: one hazard per 2-3 min of play (%.3f/min)", s.perMinute))
	eq(s.hits, 0, "a player who walks out of the red ring when the lane locks is never hit")
end
for _, name in { "fast", "slow" } do
	local s = play(name, "read", "dodge")
	truthy(s.perMinute >= 0.25 and s.perMinute <= 0.6,
		string.format("%s reader: still rare (%.3f hazards/min, one per %.1f min)", name, s.perMinute, 1 / s.perMinute))
	eq(s.hits, 0, name .. ": reacting always dodges")
end
-- a climber who ignores every warning: knocked off now and then, never often
do
	local n = play("normal", "read", "ignore")
	truthy(n.hitsPerMinute <= 0.1, string.format("normal, ignoring every warning: at most one knock per 10 min (%.3f/min)", n.hitsPerMinute))
	local s = play("slow", "read", "ignore")
	truthy(s.hitsPerMinute <= 0.25, string.format("slow, ignoring every warning: at most one knock per 4 min (%.3f/min)", s.hitsPerMinute))
end

--================================================================ the sanctuary and the clock

do
	local launched, hitOnPad, maxActive, clockOk, gapOk = 0, 0, 0, true, true
	local minGap = math.huge
	for key, s in results do
		launched += s.launchedOnPad
		hitOnPad += s.hitOnPad
		maxActive = math.max(maxActive, s.maxActive)
		-- the scheduler's clock advances exactly on the frames Climb.gate says it runs (Hazards.step
		-- skips the clock on the one frame a hazard finishes: at most one DT per hazard)
		if math.abs(s.clock - s.climbSeconds) > DT * (s.spawns + 2) then
			clockOk = false
			print("  clock drift in " .. key .. ": " .. s.clock .. " vs " .. s.climbSeconds)
		end
		for _, g in s.spawnGaps do minGap = math.min(minGap, g) end
	end
	eq(launched, 0, "no hazard ever launched while the player stood on a fork, lobby or summit pad")
	eq(hitOnPad, 0, "no hazard ever hit a player on a pad")
	eq(maxActive, 1, "never more than one hazard at a time")
	truthy(clockOk, "the hazard clock ran exactly while climbing (not at forks, not on the summit, not resting)")
	truthy(minGap >= Hz.IntervalMin - 2 * DT, string.format("two hazards are always at least IntervalMin climbing seconds apart (min gap %.1f)", minGap))
end
do
	-- a guesser climbs more than a reader, so meets more hazards per RUN, but not per climbing second:
	-- the clock is the same clock
	local r = play("normal", "read", "dodge")
	local g = play("normal", "guess", "dodge")
	local rr = r.spawns / r.climbSeconds
	local gr = g.spawns / g.climbSeconds
	print(string.format("  hazards per climbing second: reader %.5f, guesser %.5f (normal, dodge)", rr, gr))
	truthy(math.abs(rr - gr) / rr <= 0.1, string.format("hazards per climbing second are the same for readers and guessers (%.4f vs %.4f)", rr, gr))
end

--================================================================ rest cannot thin hazards

do
	local base = PlayModel.play({ cfg = Config, profile = P.normal, runs = 120, seed = 5, strategy = "read", behavior = "dodge", dt = DT })
	local rested = PlayModel.play({ cfg = Config, profile = P.normal, runs = 120, seed = 5, strategy = "read", behavior = "dodge", dt = DT,
		rest = { every = 45, length = 30 } })
	local a = base.spawns / base.climbSeconds * 3600
	local b = rested.spawns / rested.climbSeconds * 3600
	print(string.format("  rest probe: %.1f hazards per climbing hour, %.1f when resting 30 s of every 75 (%.0f min rested)",
		a, b, rested.restSeconds / 60))
	truthy(rested.restSeconds > 3600, "the probe really rested (over an hour in total)")
	truthy(math.abs(a - b) / a <= 0.05, "toggling rest leaves hazards per climbing hour unchanged (within 5%)")
	truthy(rested.spawns / rested.minutes < base.spawns / base.minutes,
		"per minute of PLAY a resting player meets fewer hazards: rest is rest")
end

--================================================================ the read's price

-- The read costs Config.Fork.ReadSeconds, measured as the break-even against never reading
-- (tests/readcost.measure.luau). Hazards never run at a fork, so the read itself is never
-- disturbed. What they can do is make a TRAP (a longer climb) a little costlier, for a climber who
-- ignores warnings and gets knocked off; that moves the break-even UP (reading is worth a little
-- more), never down. The shift per read = the guesser's extra climbing per run x the measured
-- knocks per climbing second x the seconds one knock costs / floors.
print("  read break-even shift from hazards (per read, seconds):")
for _, name in { "fast", "normal", "slow" } do
	for _, behavior in { "dodge", "ignore" } do
		local r = play(name, "read", behavior)
		local g = play(name, "guess", behavior)
		local extraClimb = g.climbSeconds / g.runs - r.climbSeconds / r.runs
		local knockRate = (r.hits + g.hits) / (r.climbSeconds + g.climbSeconds)
		local shift = extraClimb * knockRate * PlayModel.fallSeconds(Config, P[name]) / FLOORS
		print(string.format("    %-6s %-6s guesser climbs %5.1f s more per run, %.4f knocks/climbing s -> %+.3f s per read",
			name, behavior, extraClimb, knockRate, shift))
		truthy(extraClimb > 0, name .. "/" .. behavior .. ": the guesser climbs more (the trap is longer)")
		truthy(shift >= 0, name .. "/" .. behavior .. ": hazards never make guessing better")
		if behavior == "dodge" then
			eq(shift, 0, name .. ": for a climber who reacts, the read's price is untouched by hazards")
		else
			truthy(shift <= 0.2 * Config.Fork.ReadSeconds,
				string.format("%s ignoring warnings: the break-even moves by at most 20%% of the read (%.3f s)", name, shift))
		end
		if name == "normal" then
			truthy(shift <= 0.05, string.format("normal/%s: the shift is under 0.05 s (%.3f)", behavior, shift))
		end
	end
end

--================================================================ the environment changes

do
	local bands = Config.Env.Bands
	for _, name in { "fast", "normal", "slow" } do
		local s = play(name, "read", "dodge")
		local parts = {}
		for bi = 1, #bands do
			parts[#parts + 1] = string.format("%s %.2f", bands[bi].id, s.bandMinutes[bi] or -1)
			truthy(s.bandMinutes[bi] ~= nil, name .. ": every run reaches " .. bands[bi].id)
		end
		print(string.format("  %-6s minutes into a run when each band is first stood in: %s  (run %.2f min)", name, table.concat(parts, ", "), s.minutesPerRun))
		-- a band is a place, not a flicker: even a fast climber spends 20 s in each
		for bi = 1, #bands - 1 do
			local stay = ((s.bandMinutes[bi + 1] or 0) - (s.bandMinutes[bi] or 0)) * 60
			truthy(stay >= 20, string.format("%s: %s lasts at least 20 s (%.0f s)", name, bands[bi].id, stay))
			-- never monotonous: a change at least every two and a half minutes even for a slow climber
			truthy(stay <= 150, string.format("%s: %s changes within 150 s (%.0f s)", name, bands[bi].id, stay))
		end
	end
	local n = play("normal", "read", "dodge")
	truthy(n.minutesPerRun >= 3 and n.minutesPerRun <= 7, string.format("a normal ten-floor run takes 3-7 min (%.2f)", n.minutesPerRun))
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
