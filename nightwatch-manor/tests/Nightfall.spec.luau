-- Spec for Nightfall: Nightwatch Manor's own rules for how the night LOOKS, written before the module.
-- Run: luau tests/Nightfall.spec.luau
--
-- EnvBands, Hazards and Rest are the game-agnostic template (their specs are copies). This file pins
-- what is particular to a haunted manor with a hunter in it:
--   * progress is the NIGHT NUMBER the server credits, nudged forward by DREAD inside a night, never time;
--   * windows go only on OUTER walls, never on the exit's wall or over a room's own feature;
--   * the fairness rules that keep the eye candy from hiding the Nightwatcher, revealing it, or
--     changing the chase: a visibility envelope around the tuned preset, no global red tint, no
--     cosmetic light in the watcher's own colours, flicker that never dims a room below its floor;
--   * hazards run only at night and never while (or just after) the Nightwatcher has seen you;
--   * rest is a DAY thing: a config that allows it during the night (the timed round) is rejected.
local Nightfall = require("../src/shared/Nightfall")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, msg, tol)
	tol = tol or 1e-6
	if type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

--================================================================ progress: the night, nudged by dread

do
	local env = { DreadLookahead = 0.9 }
	approx(Nightfall.progress(env, "DAY", 7, 0), 7, "in the safehouse, progress is the night you are on")
	approx(Nightfall.progress(env, "DAY", 7, 0.8), 7, "dread means nothing in the day (the server reports 0; a stale value is ignored)")
	approx(Nightfall.progress(env, "NIGHT", 7, 0), 7, "a night starts at its own number")
	approx(Nightfall.progress(env, "NIGHT", 7, 0.5), 7.45, "half-way to dread 1 it has moved 0.45 toward the next night")
	approx(Nightfall.progress(env, "NIGHT", 7, 1), 7.9, "at full dread it stops short of the next night: only surviving gets you there")
	approx(Nightfall.progress(env, "NIGHT", 7, 3), 7.9, "dread above 1 is clamped")
	approx(Nightfall.progress(env, "NIGHT", 7, -2), 7, "dread below 0 is clamped")
	approx(Nightfall.progress(env, "NIGHT", 0 / 0, 0.5), 1.45, "a NaN night reads as night 1, never NaN")
	approx(Nightfall.progress(env, "NIGHT", 7, 0 / 0), 7, "a NaN dread reads as 0")
	truthy(Nightfall.progress(env, "NIGHT", 7, 1) < Nightfall.progress(env, "DAY", 8, 0),
		"the whole of night 7 sits below the day after it: surviving is always a step up")
	-- lookahead is bounded: 1 or more would let dread alone reach the next night's band
	approx(Nightfall.progress({ DreadLookahead = 5 }, "NIGHT", 7, 1), 7.99, "a lookahead of 1 or more is capped below 1")
	approx(Nightfall.progress({}, "NIGHT", 7, 1), 7, "no lookahead configured: dread does not move the bands")
end

do
	local bands = { { from = 0 }, { from = 3 }, { from = 6 }, { from = 10 } }
	eq(Nightfall.bandIndex(bands, 1), 1, "night 1 is band 1")
	eq(Nightfall.bandIndex(bands, 2), 1, "night 2 is still band 1")
	eq(Nightfall.bandIndex(bands, 3), 2, "night 3 names band 2 (its from)")
	eq(Nightfall.bandIndex(bands, 9), 3, "night 9 is band 3")
	eq(Nightfall.bandIndex(bands, 10), 4, "night 10 is band 4")
	eq(Nightfall.bandIndex(bands, 500), 4, "the last band is open-ended")
	eq(Nightfall.bandIndex(bands, 0 / 0), 1, "NaN lands in band 1")
	eq(Nightfall.bandIndex(bands, -5), 1, "a negative night lands in band 1")
	eq(Nightfall.bandIndex(bands, 9.95), 3, "the NAME goes by whole nights: 9.95 is still night 9's band")
end

--================================================================ windows: outer walls only

do
	-- an L: (0,0) (1,0) (1,1)
	local cells = { { gx = 0, gz = 0, kind = "foyer" }, { gx = 1, gz = 0, kind = "hall" }, { gx = 1, gz = 1, kind = "vestibule" } }
	local faces = Nightfall.outerFaces(cells, nil, nil)
	local set = {}
	for _, f in faces do set[f.gx .. "," .. f.gz .. "," .. f.dx .. "," .. f.dz] = f end
	eq(#faces, 8, "an L of three rooms has 8 outer faces (12 edges minus 2 shared, counted from both sides)")
	truthy(set["0,0,1,0"] == nil, "the shared wall between (0,0) and (1,0) is NOT outer")
	truthy(set["1,0,-1,0"] == nil, "...from either side")
	truthy(set["1,0,0,1"] == nil and set["1,1,0,-1"] == nil, "nor the one between (1,0) and (1,1)")
	truthy(set["0,0,0,1"] ~= nil, "(0,0)'s +Z face has no room behind it: outer")
	truthy(set["1,1,1,0"] ~= nil, "(1,1)'s +X face: outer")
	-- deterministic order (the client pools windows by index)
	local again = Nightfall.outerFaces(cells, nil, nil)
	local same = #again == #faces
	for i = 1, #faces do
		local a, b = faces[i], again[i]
		if not b or a.gx ~= b.gx or a.gz ~= b.gz or a.dx ~= b.dx or a.dz ~= b.dz then same = false end
	end
	truthy(same, "the same cells give the same faces in the same order")

	-- the exit's wall is excluded: the Servants' Exit door stands there and must read as THE way out
	local noExit = Nightfall.outerFaces(cells, { gx = 1, gz = 1, dx = 1, dz = 0 }, nil)
	eq(#noExit, 7, "excluding the exit face leaves 7")
	local found = false
	for _, f in noExit do
		if f.gx == 1 and f.gz == 1 and f.dx == 1 and f.dz == 0 then found = true end
	end
	truthy(not found, "and the exit face is not among them")

	-- a room kind's own feature wall is skipped (the chapel's stained glass IS its window)
	local skip = { hall = { { 0, -1 } } }
	local skipped = Nightfall.outerFaces(cells, nil, skip)
	local hallSouth = false
	for _, f in skipped do
		if f.gx == 1 and f.gz == 0 and f.dx == 0 and f.dz == -1 then hallSouth = true end
	end
	truthy(not hallSouth, "a face listed in the kind's skip list gets no window")
	eq(#skipped, 7, "and only that one is dropped")
end

do
	-- where a window sits on its face, relative to the room centre; normal points INTO the room
	local win = { Along = 6, CentreY = 7.5, Inset = 0.55 }
	local w = Nightfall.windowPlacement(40, win, { dx = 1, dz = 0 })
	approx(w.x, 20 - 0.55, "on the +X face the window is just inside the wall's inner face... x")
	approx(w.z, 6, "slid along the wall by Along, clear of a portrait centred at z = -6")
	approx(w.y, 7.5, "at CentreY")
	eq(w.nx, -1, "facing into the room (-X)")
	eq(w.nz, 0, "and not sideways")
	local s = Nightfall.windowPlacement(40, win, { dx = 0, dz = -1 })
	approx(s.z, -(20 - 0.55), "on the -Z face: z")
	approx(s.x, 6, "slid along X")
	eq(s.nz, 1, "facing +Z, into the room")
end

--================================================================ flicker: bounded, and never a blackout

do
	local lo, hi, meanSum, n = math.huge, -math.huge, 0, 0
	for i = 0, 20000 do
		local f = Nightfall.flicker(i * 0.013, 7, 0.25, 0.8, 1.2)
		lo = math.min(lo, f)
		hi = math.max(hi, f)
		meanSum += f
		n += 1
	end
	truthy(lo >= 0.8 - 1e-9, string.format("flicker never dims below its floor (min %.3f)", lo))
	truthy(hi <= 1.2 + 1e-9, string.format("nor flares past its ceiling (max %.3f)", hi))
	truthy(hi - lo > 0.2, string.format("and it actually flickers (range %.3f)", hi - lo))
	local mean = meanSum / n
	truthy(mean >= 0.98, string.format("on average a flickering room is NOT darker than the server lit it (mean %.3f)", mean))
	approx(Nightfall.flicker(3.3, 7, 0, 0.8, 1.2), 1, "amplitude 0 is steady light")
	truthy(Nightfall.flicker(3.3, 7, 0.25, 0.8, 1.2) ~= Nightfall.flicker(3.3, 8, 0.25, 0.8, 1.2),
		"different lights flicker differently (the seed matters)")
	-- smooth: no frame-to-frame jumps a player would read as a strobe
	local worst = 0
	for i = 0, 5000 do
		local a = Nightfall.flicker(i / 60, 3, 0.25, 0.8, 1.2)
		local b = Nightfall.flicker((i + 1) / 60, 3, 0.25, 0.8, 1.2)
		worst = math.max(worst, math.abs(a - b))
	end
	truthy(worst < 0.06, string.format("no step between two 60 Hz frames is bigger than 0.06 (worst %.4f)", worst))
	-- the HARD floor holds even against a caller that asks for less: a deep flicker with a floor of 0.2 is still
	-- never darker than Nightfall.HARD.FlickerMin of the server's light
	local deep = math.huge
	for i = 0, 20000 do
		deep = math.min(deep, Nightfall.flicker(i * 0.013, 5, 0.9, 0.2, 1.9))
	end
	truthy(deep >= Nightfall.HARD.FlickerMin - 1e-9, string.format(
		"a caller asking for a 0.2 floor still gets the hard floor %.2f (min %.3f)", Nightfall.HARD.FlickerMin, deep))
	truthy(deep <= Nightfall.HARD.FlickerMin + 0.01, "CONTROL: ...and that flicker really is deep enough to reach it")
end

--================================================================ fairness: the hunter stays exactly as visible

local function fairCfg()
	return {
		Env = {
			Fairness = {
				AtmosphereDensityMax = 0.45, HazeMax = 2.0, ExposureMin = -0.25, AmbientLumaMin = 18,
				CCBrightnessMin = -0.05, ContrastMax = 0.3, TintRedOverGreenMax = 1.12, TintChannelMin = 170,
				FlickerMin = 0.8, FlickerMax = 1.25, FlashBoostMax = 0.15, SignatureDistanceMin = 60,
			},
			WatcherSignature = { { 255, 70, 70 }, { 150, 200, 210 } },
			ExitSignature = { { 120, 220, 140 } },
			FlickerAmp = 0.2,
			FlashBoost = 0.1,
			Bands = {
				{
					id = "a", from = 0,
					lighting = { Ambient = { 20, 22, 30 }, ExposureCompensation = -0.15 },
					atmosphere = { Density = 0.42, Haze = 1.6 },
					colorCorrection = { Brightness = -0.02, Contrast = 0.18, TintColor = { 200, 210, 235 } },
					glow = { moon = { 220, 225, 235 }, eyes = { 230, 200, 90 } },
				},
			},
			Glow = { hazardBlink = { 255, 170, 40 }, ghost = { 170, 140, 255 } },
		},
	}
end

do
	local ok, err = Nightfall.fairness(fairCfg())
	truthy(ok, "the reference config is fair (" .. tostring(err) .. ")")

	local function breaks(mutate: (any) -> (), word: string, msg: string)
		local c = fairCfg()
		mutate(c)
		local ok2, err2 = Nightfall.fairness(c)
		eq(ok2, false, msg)
		truthy(type(err2) == "string" and string.find(string.lower(err2), string.lower(word), 1, true) ~= nil,
			"...and the reason names " .. word .. " (" .. tostring(err2) .. ")")
	end
	breaks(function(c) c.Env.Bands[1].atmosphere.Density = 0.6 end, "Density",
		"a thicker fog than the envelope would hide the Nightwatcher at sight range: rejected")
	breaks(function(c) c.Env.Bands[1].atmosphere.Haze = 3 end, "Haze", "a heavier haze: rejected")
	breaks(function(c) c.Env.Bands[1].lighting.ExposureCompensation = -0.6 end, "Exposure", "a darker exposure: rejected")
	breaks(function(c) c.Env.Bands[1].lighting.Ambient = { 5, 5, 8 } end, "Ambient", "a blacker ambient: rejected")
	breaks(function(c) c.Env.Bands[1].colorCorrection.Brightness = -0.2 end, "Brightness", "a darker grade: rejected")
	breaks(function(c) c.Env.Bands[1].colorCorrection.Contrast = 0.6 end, "Contrast", "crushed shadows: rejected")
	breaks(function(c) c.Env.Bands[1].colorCorrection.TintColor = { 255, 190, 190 } end, "Tint",
		"a red tint over the whole screen would drown the watcher's red eyes: rejected")
	breaks(function(c) c.Env.Bands[1].colorCorrection.TintColor = { 120, 200, 200 } end, "Tint",
		"a tint that crushes a channel: rejected")
	breaks(function(c) c.Env.Bands[1].glow.eyes = { 250, 75, 72 } end, "eyes",
		"portrait eyes glowing the watcher's red would be a decoy: rejected")
	breaks(function(c) c.Env.Glow.hazardBlink = { 150, 205, 205 } end, "hazardBlink",
		"a hazard light in the colour of the watcher's lamp: rejected")
	-- Review 4: the Servants' Exit's green light is the one cue a player hunts for under dread. A ghost in (nearly)
	-- that green, coming through a wall, is a decoy for the way out, the mirror image of a decoy for the hunter.
	breaks(function(c) c.Env.Glow.ghost = { 120, 255, 140 } end, "exit",
		"a ghost glowing the Servants' Exit's green (35 from it) would be a decoy for the way out: rejected")
	breaks(function(c) c.Env.Bands[1].glow.eyes = { 130, 230, 150 } end, "exit",
		"portrait eyes in the exit's green: rejected too (every glow is checked against both signatures)")
	breaks(function(c) c.Env.ExitSignature = nil end, "ExitSignature",
		"a fairness check that does not know the exit's colour cannot protect it: rejected")
	breaks(function(c) c.Env.FlickerAmp = 0.5 end, "Flicker", "flicker deep enough to black a room out: rejected")
	breaks(function(c) c.Env.Fairness.FlickerMin = 0.3 end, "Flicker", "a flicker floor below the envelope: rejected")
	breaks(function(c) c.Env.FlashBoost = 0.5 end, "Flash", "a lightning flash bright enough to light the house like day: rejected")
	breaks(function(c) c.Env.Bands[1].atmosphere.Density = nil end, "Density", "a band that leaves a visibility field unset: rejected")

	-- a band that leaves out a whole group is not "unset = fine": the client would keep the last band's value
	local c = fairCfg()
	c.Env.Bands[1].colorCorrection = nil
	eq((Nightfall.fairness(c)), false, "a band with no colour grade at all is rejected, not skipped")

	approx(Nightfall.colorDistance({ 0, 0, 0 }, { 3, 4, 0 }), 5, "colour distance is Euclidean in RGB")
end

--================================================================ lightning: never a strobe
-- Review 4: the config said "at least 4 s between flashes" and a spec checked the config, but the client ran its
-- countdown at (1 + dread) x real time, so late in a Witching Hour night the room flashed every 2.7 s. The gap is
-- now decided here, in REAL seconds, and the floor holds whatever the band or the dread asks for.

do
	local H = Nightfall.HARD
	truthy(type(H.FlashGapMin) == "number" and H.FlashGapMin >= 4, "the hard floor between two flashes is at least 4 s (" .. tostring(H.FlashGapMin) .. ")")
	local spec = { everyMin = 6, everyMax = 14 }
	approx(Nightfall.boltGap(spec, 0, 0), 6, "at dread 0 the gap is the band's own: everyMin at u = 0")
	approx(Nightfall.boltGap(spec, 0, 1), 14, "...everyMax at u = 1")
	approx(Nightfall.boltGap(spec, 0.5, 1), 14 / 1.5, "dread shortens the gap: 1 + dread times as often")
	approx(Nightfall.boltGap(spec, 1, 0), H.FlashGapMin, "but at full dread the shortest gap is held at the floor, not 3 s")
	-- every dread, every roll, every band the game could be given: never under the floor
	local worst = math.huge
	for _, sp in { { everyMin = 5, everyMax = 11 }, { everyMin = 6, everyMax = 14 }, { everyMin = 18, everyMax = 34 }, { everyMin = 0.3, everyMax = 0.5 }, { everyMin = 0, everyMax = 0 } } do
		for di = 0, 20 do
			for ui = 0, 20 do
				worst = math.min(worst, Nightfall.boltGap(sp, di / 20, ui / 20))
			end
		end
	end
	truthy(worst >= H.FlashGapMin - 1e-9, string.format("no band, dread or roll ever gives a gap under %.1f s (shortest %.2f)", H.FlashGapMin, worst))
	approx(Nightfall.boltGap({ everyMin = 0.3, everyMax = 0.5 }, 0, 0.5), H.FlashGapMin, "a config asking for a strobe gets the floor")
	-- more dread never means a LONGER gap
	local mono = true
	for ui = 0, 10 do
		local prev = math.huge
		for di = 0, 20 do
			local g = Nightfall.boltGap(spec, di / 20, ui / 10)
			if g > prev + 1e-9 then mono = false end
			prev = g
		end
	end
	truthy(mono, "the gap only ever shrinks as dread rises (down to the floor)")
	approx(Nightfall.boltGap(spec, 0 / 0, 0), 6, "a NaN dread reads as 0")
	approx(Nightfall.boltGap(spec, 7, 1), 7, "dread above 1 is clamped to 1 (14 / 2)")
	approx(Nightfall.boltGap(spec, 0, 0 / 0), 6, "a NaN roll reads as 0")
	truthy(Nightfall.boltGap({}, 0, 0.5) >= H.FlashGapMin, "a spec with no numbers never strobes either")
end

-- A blinking warning (the hazard's amber light, its locked marker) blinks at most BlinkHzMax times a second. The
-- locked marker used to blink 3 times a second, the edge of the WCAG three-flashes rule.
do
	local H = Nightfall.HARD
	truthy(type(H.BlinkHzMax) == "number" and H.BlinkHzMax <= 2, "blinking is capped at 2 a second (" .. tostring(H.BlinkHzMax) .. ")")
	local function mostOnsInASecond(hz: number): (number, number)
		local ons = {}
		local prev = Nightfall.blink(0, hz)
		local offs = 0
		for i = 1, 240 * 10 do
			local t = i / 240
			local on = Nightfall.blink(t, hz)
			if on and not prev then table.insert(ons, t) end
			if not on then offs += 1 end
			prev = on
		end
		local most = 0
		for i = 1, #ons do
			local n = 0
			for j = i, #ons do
				if ons[j] - ons[i] < 1 - 1e-9 then n += 1 end
			end
			most = math.max(most, n)
		end
		return most, offs
	end
	eq((mostOnsInASecond(2)), 2, "asked for 2 Hz: two flashes in any second")
	eq((mostOnsInASecond(3)), 2, "asked for 3 Hz: held to two")
	eq((mostOnsInASecond(12)), 2, "asked for 12 Hz: held to two")
	eq((mostOnsInASecond(1)), 1, "asked for 1 Hz: one")
	local _, offs = mostOnsInASecond(0)
	eq(offs, 0, "0 Hz is a steady light, never off")
end

--================================================================ hazards: night only, never in a chase

do
	local hz = { QuietAfterSpottedSeconds = 10 }
	eq(Nightfall.hazardGate(hz, { phase = "NIGHT", spotted = false, sinceSpotted = math.huge }), true,
		"at night, unseen for ages: hazards may run")
	eq(Nightfall.hazardGate(hz, { phase = "DAY", spotted = false, sinceSpotted = math.huge }), false,
		"never in the safehouse")
	eq(Nightfall.hazardGate(hz, { phase = "NIGHT", spotted = true, sinceSpotted = 0 }), false,
		"never while the Nightwatcher sees you")
	eq(Nightfall.hazardGate(hz, { phase = "NIGHT", spotted = false, sinceSpotted = 4 }), false,
		"nor for QuietAfterSpottedSeconds after (it is still hunting you)")
	eq(Nightfall.hazardGate(hz, { phase = "NIGHT", spotted = false, sinceSpotted = 10 }), true,
		"and again once that has passed")
	eq(Nightfall.hazardGate(hz, { phase = nil, spotted = false, sinceSpotted = math.huge }), false,
		"no phase yet (the profile has not loaded): nothing runs")

	-- Review 4: WHICH way the clock is stopped matters. Frozen while hunted, the clock made hazards come more often
	-- per minute in the manor the better a player hid. So the clock is FROZEN only outside the night (the day, the
	-- 2.5 s beat after a night ends, before the profile loads) and HELD while the Nightwatcher sees you and for the
	-- quiet window after: it runs, but nothing launches until you are free.
	local cases = {
		{ { phase = "NIGHT", spotted = false, sinceSpotted = math.huge }, "run", "at night, unseen: the clock runs and a hazard may launch" },
		{ { phase = "DAY", spotted = false, sinceSpotted = math.huge }, "freeze", "in the safehouse: frozen (rest there changes nothing)" },
		{ { phase = "ENDED", spotted = false, sinceSpotted = math.huge }, "freeze", "in the beat after a night ends: frozen" },
		{ { phase = nil, spotted = false, sinceSpotted = math.huge }, "freeze", "before the profile loads: frozen" },
		{ { phase = "DAY", spotted = true, sinceSpotted = 0 }, "freeze", "a stale 'spotted' in the day is still the day: frozen" },
		{ { phase = "NIGHT", spotted = true, sinceSpotted = 0 }, "hold", "while it sees you: the clock runs, the launch is HELD" },
		{ { phase = "NIGHT", spotted = false, sinceSpotted = 4 }, "hold", "in the quiet window after: held" },
		{ { phase = "NIGHT", spotted = false, sinceSpotted = 10 }, "run", "after the quiet window: runs again" },
		{ { phase = "NIGHT", spotted = false, sinceSpotted = 0 / 0 }, "run", "a NaN 'since' reads as long ago, never as a hold forever" },
	}
	for _, c in cases do
		eq(Nightfall.hazardClock(hz, c[1]), c[2], c[3])
		eq(Nightfall.hazardGate(hz, c[1]), c[2] == "run", "...and hazardGate (may a hazard launch now?) agrees: " .. c[3])
	end

	local ok, err = Nightfall.validateHazards({
		Player = { WalkSpeed = 20 }, Watcher = { HuntSeconds = 7 },
		Hazards = { QuietAfterSpottedSeconds = 10, KnockSpeedFractionMax = 0.8, KnockLift = 0, MinTelegraphSeconds = 3,
			Kinds = { bats = { knock = 14, telegraph = 3.2 } } },
	})
	truthy(ok, "a hazard config that respects the chase validates (" .. tostring(err) .. ")")
	local function hbreaks(mut: (any) -> (), word: string, msg: string)
		local c = {
			Player = { WalkSpeed = 20 }, Watcher = { HuntSeconds = 7 },
			Hazards = { QuietAfterSpottedSeconds = 10, KnockSpeedFractionMax = 0.8, KnockLift = 0, MinTelegraphSeconds = 3,
				Kinds = { bats = { knock = 14, telegraph = 3.2 } } },
		}
		mut(c)
		local ok2, err2 = Nightfall.validateHazards(c)
		eq(ok2, false, msg)
		truthy(type(err2) == "string" and string.find(err2, word, 1, true) ~= nil, "...naming " .. word .. " (" .. tostring(err2) .. ")")
	end
	hbreaks(function(c) c.Hazards.Kinds.bats.knock = 19 end, "knock",
		"a knock nearly as fast as walking would be a free speed boost (or, pointed at the watcher, a death): rejected")
	hbreaks(function(c) c.Hazards.QuietAfterSpottedSeconds = 5 end, "QuietAfterSpottedSeconds",
		"a quiet window shorter than the hunt lets a hazard fire into a live chase: rejected")
	hbreaks(function(c) c.Hazards.KnockLift = 6 end, "KnockLift", "a knock that lifts: rejected (there is nothing to fall off in a manor)")
	hbreaks(function(c) c.Hazards.MinTelegraphSeconds = 2 end, "MinTelegraphSeconds", "less than 3 s of warning: rejected")
	-- A hit lands when the hazard's REACH (hitRadius + PlayerRadius) touches you, a little before its centre
	-- arrives. The headless check measured a crockery hit 2.87 s after its 3.0 s warning began. The rule is
	-- therefore on the earliest possible HIT, not on the arrival: telegraph - reach / speed >= 3 s.
	hbreaks(function(c)
		c.Hazards.PlayerRadius = 2
		c.Hazards.Kinds.bats = { knock = 14, telegraph = 3.0, speed = 22, hitRadius = 1.7 }
	end, "earliest hit", "a hazard whose reach touches you before 3 s of warning have passed: rejected")
	do
		local c = {
			Player = { WalkSpeed = 20 }, Watcher = { HuntSeconds = 7 },
			Hazards = { QuietAfterSpottedSeconds = 10, KnockSpeedFractionMax = 0.8, KnockLift = 0, MinTelegraphSeconds = 3, PlayerRadius = 2,
				Kinds = { bats = { knock = 14, telegraph = 3.2, speed = 22, hitRadius = 1.7 } } },
		}
		truthy((Nightfall.validateHazards(c)), "CONTROL: the same kind with 3.2 s of warning (earliest hit at 3.03 s) is accepted")
	end
end

do
	-- leading the aim: the ring goes where you are walking, so a moving player has something to avoid
	local a = Nightfall.leadAim({ x = 0, y = 3, z = 0 }, { x = 20, y = 0, z = 0 }, 1.0, 1.2)
	approx(a.x, 20, "one second out, a walker at 20 studs/s is aimed 20 studs ahead")
	approx(a.y, 3, "at the same height")
	local b = Nightfall.leadAim({ x = 0, y = 3, z = 0 }, { x = 20, y = 0, z = 0 }, 3.0, 1.2)
	approx(b.x, 24, "never more than LeadSeconds ahead (1.2 s -> 24 studs)")
	local c = Nightfall.leadAim({ x = 5, y = 3, z = 5 }, { x = 20, y = 50, z = 0 }, 1.0, 1.2)
	approx(c.y, 3, "vertical speed is ignored (a jump does not throw the ring into the air)")
	local d = Nightfall.leadAim({ x = 5, y = 3, z = 5 }, { x = 0, y = 0, z = 0 }, 1.0, 1.2)
	approx(d.x, 5, "a player standing still is aimed at where they stand")
	local e = Nightfall.leadAim({ x = 5, y = 3, z = 5 }, { x = 400, y = 0, z = 0 }, 1.0, 1.2, 20)
	approx(e.x, 25, "a speed above the walk cap (a teleport, a knock) is clamped to it")
	local f = Nightfall.leadAim({ x = 5, y = 3, z = 5 }, { x = 20, y = 0, z = 0 }, -1, 1.2)
	approx(f.x, 5, "no time left: no lead")
end

--================================================================ rest: between rounds, never inside one

do
	local good = { Phases = { DAY = true } }
	truthy((Nightfall.validateRest(good)), "rest in the safehouse only: valid")
	eq(Nightfall.restAllowed(good, "DAY"), true, "resting is allowed in the day")
	eq(Nightfall.restAllowed(good, "NIGHT"), false, "and not at night")
	eq(Nightfall.restAllowed(good, nil), false, "and not before the profile has loaded (no phase)")
	local bad = { Phases = { DAY = true, NIGHT = true } }
	local ok, err = Nightfall.validateRest(bad)
	eq(ok, false, "a config that allows rest DURING the night is rejected: it would pause nothing the server runs")
	truthy(type(err) == "string" and string.find(err, "NIGHT", 1, true) ~= nil, "...and says why (" .. tostring(err) .. ")")
	eq((Nightfall.validateRest({})), false, "a rest config with no phases is rejected")
end

--================================================================ the safehouse grows cosier

do
	local tiers = { { minLevel = 0 }, { minLevel = 2 }, { minLevel = 6 }, { minLevel = 12 }, { minLevel = 20 } }
	eq(Nightfall.cosyTier(tiers, 0), 1, "hub level 0: the bare shelter")
	eq(Nightfall.cosyTier(tiers, 1), 1, "1: still bare")
	eq(Nightfall.cosyTier(tiers, 2), 2, "2: the fire is lit")
	eq(Nightfall.cosyTier(tiers, 11), 3, "11")
	eq(Nightfall.cosyTier(tiers, 30), 5, "30: the whole haven")
	eq(Nightfall.cosyTier(tiers, 0 / 0), 1, "NaN: bare, never an error")
	eq(Nightfall.cosyTier(tiers, -3), 1, "negative: bare")
end

--================================================================ portraits' eyes follow YOU

do
	-- a portrait on the +X wall facing -X; its eye at (19, 8, 0)
	local home = { x = 19, y = 8, z = 0 }
	local normal = { x = -1, y = 0, z = 0 }
	local o = Nightfall.pupil(home, normal, { x = 0, y = 8, z = 10 }, 0.12)
	approx(o.x, 0, "the pupil slides IN the canvas (no component along the normal)")
	truthy(o.z > 0, "toward a target on the +Z side")
	truthy(math.sqrt(o.x ^ 2 + o.y ^ 2 + o.z ^ 2) <= 0.12 + 1e-9, "and never further than maxShift")
	local centred = Nightfall.pupil(home, normal, { x = 0, y = 8, z = 0 }, 0.12)
	approx(math.sqrt(centred.x ^ 2 + centred.y ^ 2 + centred.z ^ 2), 0, "straight in front: centred")
	local above = Nightfall.pupil(home, normal, { x = 10, y = 20, z = 0 }, 0.12)
	truthy(above.y > 0, "a target above: the pupil looks up")
end

--================================================================ the chip names the band and the next one

do
	local bands = {
		{ id = "quiet", name = "Quiet Night", emoji = "🌙", from = 0 },
		{ id = "mist", name = "The Mist", emoji = "🌫️", from = 3 },
		{ id = "blood", name = "Blood Moon", emoji = "🩸", from = 20 },
	}
	eq(Nightfall.chipText(bands, 1), "🌙 Quiet Night · Night 1 · 🌫️ in 2", "night 1: the next band is 2 nights away")
	eq(Nightfall.chipText(bands, 2), "🌙 Quiet Night · Night 2 · 🌫️ in 1", "night 2: 1 away")
	eq(Nightfall.chipText(bands, 3), "🌫️ The Mist · Night 3 · 🩸 in 17", "night 3")
	eq(Nightfall.chipText(bands, 25), "🩸 Blood Moon · Night 25", "the last band has no next")
end

print(string.format("Nightfall: %d passed, %d failed", passed, failed))
assert(failed == 0, "Nightfall tests failed")
