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

--================================================================ the world is never still for long

-- Second review, 2026-09-30 (finding 5): "never more than 150 s for a slow climber" was asserted only on
-- the 80-run MEAN of band entry times, for readers. One run at a time (200 per row), a slow reader stayed
-- in one band for more than 150 s in 31 of 1000 band stays and a slow guesser in 198 of 1000, up to
-- 234 s: a band spans two floors, and a guesser's trapped section is four platforms longer. The world
-- changes only when the climb moves a band's weight or a layer's weight (the client blends both by the
-- player's progress), so this measures, per run, the longest stretch from a run's first fork to its
-- summit in which neither moves (PlayModel: stats.stillMax), for every profile and both strategies. A band
-- still spans two floors; its second floor is its own phase (Config.Env.Layers), so every floor's climb
-- changes the world.
do
	local STILL_MAX = 90
	for _, name in { "fast", "normal", "slow" } do
		for _, strat in { "read", "guess" } do
			local worst, over, sum = 0, 0, 0
			for seed = 1, 200 do
				local s = PlayModel.play({ cfg = Config, profile = Config.Pacing.Profiles[name], runs = 1, seed = seed * 17 + 3,
					firstRunSeed = seed, strategy = strat, behavior = "dodge", cameraPitch = -15, dt = 0.05 })
				local m = s.stillMax[1] or math.huge
				worst = math.max(worst, m)
				sum += m
				if m > STILL_MAX then over += 1 end
			end
			print(string.format("  %-6s %-5s: the world stood still at most %.0f s in a run (mean of the run maxima %.0f s, 200 runs)", name, strat, worst, sum / 200))
			eq(over, 0, string.format("%s/%s: in no run does the world stand still for more than %d s (worst %.0f s)", name, strat, STILL_MAX, worst))
		end
	end
end

--================================================================ the long-term goal: a rarer crown

-- OWNER DECISION, 2026-09-30 ("take the recommended option for all"; EYECANDY.md §12 "No progress across
-- runs", which offered one more star per rebirth or a rarer crown at 5 / 10 / 25 rebirths and left it to
-- the owner). Taken: a rarer crown of stars at the summit at 5, 10 and 25, counted in SUMMITS reached
-- (Config.Env.CrownTiers), not rebirths: Rebirth works from any floor every Config.Limits.RebirthCooldown
-- (3 s), so 25 "rebirths" are 75 s of button presses, and a goal a button can buy is not a goal. Pass 2
-- (2026-10-01) moved the ice crown from 10 to 8 summits so that it is the brag (below). Measured here in
-- minutes of normal play (a reader who reacts, the Pacing profile).
do
	local tiers = Config.Env.CrownTiers
	truthy(type(tiers) == "table" and #tiers >= 3, "Config.Env.CrownTiers exists, with at least three crowns (the gold one and two rarer)")
	if type(tiers) == "table" and #tiers >= 3 then
		local n = play("normal", "read", "dodge")
		eq(tiers[1].summits, 0, "the first crown is the one every summit has")
		local increasing, mins = true, {}
		for i, t in tiers do
			if i > 1 and t.summits <= tiers[i - 1].summits then increasing = false end
			mins[i] = t.summits * n.minutesPerRun
		end
		truthy(increasing, "each rarer crown needs more summits than the one before")
		local parts = {}
		for i, t in tiers do parts[#parts + 1] = string.format("%s %d summits = %.0f min", t.id, t.summits, mins[i]) end
		print("  crowns, in minutes of normal play: " .. table.concat(parts, ", "))
		truthy(mins[2] >= 15 and mins[2] <= 45, string.format("the first rarer crown comes within 15-45 min of normal play (%.0f min)", mins[2]))
		truthy(mins[#tiers] >= 60, string.format("and the rarest is a long-term goal, over an hour of normal play (%.0f min)", mins[#tiers]))
		truthy(tiers[#tiers].summits * Config.Limits.RebirthCooldown < mins[#tiers] * 60,
			"a crown counted in rebirths would have been 3 s of button presses per step; counted in summits it is a climb")

		-- THE BRAG MOMENT (docs/complete-game-standard.md §2: "a brag moment within about 30-45 minutes of
		-- normal play, and a long-term goal beyond it"; +1 Jump's is reaching space, held the same way in its
		-- Pacing.spec). Pass 2, 2026-10-01: the summit's Build Reveal card comes after 4.5 min and the crowns
		-- were measured at 23, 45.4 and 114 min, so no crown landed inside the window (the ice crown at 10
		-- summits was 0.4 min past it, at the edge, not in it). Config.Env.BragCrown names the crown that is the
		-- brag; it must land in the window and near its MIDDLE (as +1 Jump's space band must), so a retune
		-- that drifts a few minutes cannot silently leave it. The rarest crown is the long-term goal: at least
		-- twice the brag's time, and reachable in a few sessions (under 3 h), as +1 Jump's galaxy.
		local bragIdx = nil
		for i, t in tiers do
			if t.id == Config.Env.BragCrown then bragIdx = i end
		end
		truthy(bragIdx ~= nil and bragIdx > 1, "Config.Env.BragCrown names one of the rarer crowns (" .. tostring(Config.Env.BragCrown) .. ")")
		if bragIdx then
			local brag = mins[bragIdx]
			print(string.format("  the brag (%s, %d summits): %.1f min of normal play; the long-term goal (%s, %d summits): %.1f min",
				tiers[bragIdx].id, tiers[bragIdx].summits, brag, tiers[#tiers].id, tiers[#tiers].summits, mins[#tiers]))
			truthy(brag >= 30 and brag <= 45, string.format("a normal player wins the brag crown in 30-45 min of play (%.1f)", brag))
			truthy(math.abs(brag - 37.5) <= 5, string.format("near the MIDDLE of the window, not an edge (%.1f min)", brag))
			truthy(bragIdx < #tiers and mins[#tiers] >= 2 * brag, string.format(
				"the rarest crown is a long-term goal beyond the brag: at least twice its time (%.1f vs %.1f min)", mins[#tiers], brag))
			truthy(mins[#tiers] <= 180, string.format("but reachable in a few sessions, under 3 h of play (%.1f min)", mins[#tiers]))
		end
	end
end

--================================================================ the exit's clock never refuses an honest climber

-- Queued job I (2026-09-30): the server clears a floor only once Section.minClimbSeconds has passed since
-- the door dropped the player on the section (a teleport to the exit used to clear it at once). It must
-- never refuse an honest climber. Measured on the climb model, section by section, with each climber's
-- own speed and jump (their traits so far): the three human profiles, and a "bunny-hopper" who never
-- lines up a hop and never misses, jumping again the instant they land: every hop is only its airtime.
-- That climber is faster than any profile in Config.Pacing; the rule must leave room even for them.
do
	local Section = require("../src/shared/Section")
	local hopper = { lineUp = 0, miss = 0, recover = 0, fork = 0, summit = 0 }
	-- the hopper is the tight case, so it is timed on a finer step (a coarse step only ever lengthens a hop)
	local rows = { { "fast", P.fast, 0.05 }, { "normal", P.normal, 0.05 }, { "slow", P.slow, 0.05 }, { "bunny-hopper", hopper, 0.01 } }
	for _, row in rows do
		local refused, n, tightest = 0, 0, math.huge
		for _, strat in { "read", "guess" } do
			for seed = 1, 30 do
				PlayModel.play({ cfg = Config, profile = row[2], runs = 1, seed = seed * 31 + 5, firstRunSeed = seed,
					strategy = strat, behavior = "dodge", cameraPitch = -15, dt = row[3],
					onClimb = function(_, seconds, geo, speed)
						local need = if type(Section.minClimbSeconds) == "function" then Section.minClimbSeconds(Config, geo.sec, speed) else math.huge
						n += 1
						if seconds < need then refused += 1 end
						tightest = math.min(tightest, seconds / math.max(need, 1e-9))
					end })
			end
		end
		print(string.format("  exit clock: %-12s %d climbs, the quickest took %.2fx the least time the exit asks for", row[1], n, tightest))
		eq(refused, 0, string.format("%s: no honest climb reaches the exit before the section could have been climbed (%d climbs)", row[1], n))
	end
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
