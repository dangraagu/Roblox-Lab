--!strict
-- Config.luau — every tunable for "Anomaly: Night Shift at the Observatory".
-- One data block so a fresh session (or a reviewer) can retune the whole game here.
--
-- Game loop: you walk a looping observatory concourse. Each pass, a procedural roll
-- either leaves the hall NORMAL or injects exactly ONE anomaly. At the hall's end you
-- ADVANCE (if it looked normal) or TURN BACK (if you spotted something wrong). Correct
-- call -> your Day counter ticks up. Wrong call -> the night resets to Day 1. There is
-- NO chase / pathfinding AI — the tension is pure observation.

local Config = {}

-- ------------------------------------------------------------------ Anomalies
-- The catalog is ORDER-SENSITIVE: the first `StartPool` entries are the most obvious
-- anomalies available on Day 1; deeper days unlock more (and subtler) entries. Each id
-- is a STRING (avoids the DataStore integer-key -> string JSON round-trip trap that bit
-- the sibling games).
--
-- `kind` is a LABEL FOR HUMANS AND NOTHING ELSE. It used to say "kind tells the server which
-- visual mutation to apply", which is false and cost real time: the server dispatches on `id`
-- through the APPLIERS table, and greps for a kind therefore find only this file and look like
-- a missing feature. Adding an entry here does NOT make it happen - it needs an APPLIERS entry
-- under the same id, and the server refuses to start without one.
--
-- `hint` is the text the player is shown after a miss, so it is a promise about what they were
-- supposed to see. Five of them used to describe something other than what the applier did -
-- a strobe that never strobed, a clock with no face, a sign flip that was geometrically a
-- no-op, a reflection that was never rendered, and a moon behind a dome that does not exist.
-- In a spot-the-difference game that is not a wording problem: it teaches the player a tell
-- that is not there. Keep hint and applier honest with each other.
Config.Anomaly = {
	-- Present-probability curve: P(an anomaly is injected this pass).
	BaseChance = 0.5, -- Day 1
	ChancePerDay = 0.004, -- creeps up with depth
	MaxChance = 0.62, -- hard ceiling so it never feels rigged
	-- How many catalog entries are "in play" at a given day.
	StartPool = 8, -- Day 1 draws from the first 8 (obvious) anomalies
	PoolPerDay = 0.5, -- +1 new anomaly type every 2 days
	Catalog = {
		-- obvious (Day 1 pool)
		{ id = "figure_end", name = "The Watcher", kind = "FIGURE", hint = "a figure standing at the end of the hall" },
		{ id = "door_extra", name = "The Extra Door", kind = "ADD", hint = "a door that isn't usually there" },
		{ id = "scope_gone", name = "Missing Telescope", kind = "REMOVE", hint = "the main telescope is missing" },
		{ id = "lights_out", name = "Blackout", kind = "LIGHTS", hint = "the concourse lights are off" },
		{ id = "chart_flip", name = "Inverted Sky", kind = "ROTATE", hint = "a star chart hung upside-down" },
		{ id = "poster_red", name = "Red Shift", kind = "RECOLOR", hint = "a wall panel glowing the wrong colour" },
		{ id = "chair_moved", name = "Displaced", kind = "MOVE", hint = "a chair moved from its usual spot" },
		{ id = "clock_stop", name = "Stopped Clock", kind = "SWAP", hint = "the wall clock reads the wrong time" },
		-- subtler (unlock with depth)
		{ id = "twin_scope", name = "The Twin", kind = "DUPLICATE", hint = "a duplicated telescope" },
		-- Was "Wrong Reflection / your reflection is a beat behind". Roblox never rendered an
		-- avatar reflection in a Reflectance surface, so a delayed one was unbuildable; what the
		-- applier actually does is kill the reflectance and darken the glass. Named for that.
		{ id = "reflection_off", name = "Dead Glass", kind = "MIRROR", hint = "the mirror has stopped reflecting" },
		{ id = "flicker_hall", name = "The Flicker", kind = "FLICKER", hint = "a light strobing that shouldn't" },
		{ id = "scale_bench", name = "Too Big", kind = "SCALE", hint = "a bench scaled larger than normal" },
		{ id = "figure_window", name = "The Onlooker", kind = "FIGURE", hint = "a face in the observation window" },
		{ id = "plant_gone", name = "Barren", kind = "REMOVE", hint = "the lobby plant is gone" },
		{ id = "sign_swap", name = "Misdirection", kind = "SWAP", hint = "an exit sign pointing the wrong way" },
		{ id = "floor_tilt", name = "The Lean", kind = "ROTATE", hint = "the floor tiles tilted a few degrees" },
		{ id = "dupe_door", name = "Hall of Doors", kind = "DUPLICATE", hint = "a duplicated doorway" },
		-- The hall has no dome and no moon; the applier recolours the part named `Window`. The
		-- old hint sent the player looking for scenery that was never built.
		{ id = "moon_recolor", name = "Blood Moon", kind = "RECOLOR", hint = "the sky through the observation window has gone red" },
		{ id = "static_screen", name = "Dead Channel", kind = "TOGGLE", hint = "a monitor showing static" },
		{ id = "figure_ceiling", name = "The Climber", kind = "FIGURE", hint = "something on the ceiling" },
		{ id = "mirror_extra", name = "One Too Many", kind = "ADD", hint = "an extra mirror on the wall" },
		{ id = "scope_tilt", name = "Skewed", kind = "MOVE", hint = "the telescope aimed at the floor" },
		{ id = "cold_breath", name = "The Chill", kind = "FLICKER", hint = "fog / breath in a warm hall" },
		{ id = "count_off", name = "Miscount", kind = "SWAP", hint = "the wrong number of chairs" },
	},
}

-- ------------------------------------------------------------------ Progression
Config.Progression = {
	StartDay = 1,
	MaxDay = 500, -- streak cap
}

-- ------------------------------------------------------------------ Hints
-- A hint reveals whether the CURRENT hall is clean, consuming one token. New players
-- start with a small stock; codes grant more. Purely a safety net, never required.
Config.Hint = {
	StartTokens = 1,
}

-- ------------------------------------------------------------------ Codes (one-time)
-- Rewards: hintTokens (integer) and/or tint (a flashlight colour id from Config.Tints).
Config.Codes = {
	WELCOME = { hintTokens = 3 },
	OBSERVE = { hintTokens = 5 },
	MIDNIGHT = { hintTokens = 10 },
	ECLIPSE = { tint = "gold" },
}

-- Cosmetic flashlight tints. "white" is the free default; others unlock via codes/ranks.
Config.Tints = { "white", "amber", "gold", "cyan", "crimson" }
Config.DefaultTint = "white"

-- Colour of each tint id, as a plain {R, G, B} 0-255 triple. Deliberately NOT Color3 values:
-- this module is also required by the pure luau-CLI tests, where the Roblox `Color3` global
-- does not exist, so a Color3 literal here would break every test run. The client converts
-- these (picker swatch + the carried flashlight light). Keep one entry per Config.Tints id.
local TintRGB: { [string]: { number } } = {
	white = { 235, 235, 245 },
	amber = { 240, 180, 90 },
	gold = { 245, 205, 70 },
	cyan = { 90, 220, 235 },
	crimson = { 225, 70, 80 },
}
Config.TintRGB = TintRGB

-- Field-Guide / streak rank milestones (also Roblox Badge award points server-side).
Config.Milestones = { 10, 25, 50, 100, 250 }

-- ------------------------------------------------------------------ Persistence
Config.Save = {
	Store = "AnomalyObs_v1", -- per-player profile
	LeaderStore = "AnomalyObsBest_v1", -- OrderedDataStore for best-day leaderboard
	AutosaveSeconds = 20,
	SessionLockSeconds = 45, -- soft session-lock TTL, renewed by autosave
}

-- Base seed folded into the per-player, per-pass Rng seed (kept for reproducibility).
Config.WorldSeed = 20260906

-- ------------------------------------------------------------------ The night sky (client only)
-- The sky outside the observatory progresses with the Day. Read by src/client/Sky.client.luau
-- through the pure src/shared/NightSky.luau; the server never reads any of this. EYECANDY.md has
-- the whole design, the measured budgets and the Studio shot list.
--
-- THE HALL NEVER CHANGES. Spot-the-difference is the game: any variation inside the hall reads as
-- an anomaly. So the sky lives only BEYOND the hall's open entrance (+Z, behind the spawn and
-- behind the marketing rig's camera), casts no light, never writes Lighting outside a break, reads
-- nothing about the pass, and uses no reddish colour (two anomalies are "red"). NightSky.validate
-- refuses a config that breaks any of that; tests/SkyConfig.spec.luau pins these numbers.
--
-- Colours are {R, G, B} 0-255 (no Color3 here: this module also runs in the luau CLI).
-- Azimuth is degrees from straight out of the entrance (+Z) toward +X; elevation is up from level.
local function features(t: { [string]: number }): { [string]: number }
	local out = { stars = 0, moon = 0, meteors = 0, aurora = 0, comet = 0, storm = 0, nebula = 0, planets = 0, othersky = 0 }
	for k, v in t do
		out[k] = v
	end
	return out
end

Config.Sky = {
	-- The hall as the server builds it (Main.server.luau: zoneOrigin, buildClean, HALL_LEN = 80).
	-- Relative to the zone origin: the shell spans x -10.5..10.5, y -0.5..16.5, z -90..10, and is
	-- open only at z = +10. check_anomalyobservatory_sky.luau measures these against the real zone.
	Hall = { Spacing = 1000, OriginY = 100, HalfWidth = 10.5, Bottom = -0.5, Top = 16.5, Back = -90, Front = 10, EyeHeight = 6 },
	-- Every piece of sky keeps at least this far beyond the entrance plane.
	Clearance = 6,
	-- Seconds for a changed sky to get half way to its new look. A Day that changes the band is a
	-- glide of several seconds, never a cut; so is the reset to Day 1 after a wrong call.
	GlideHalfLife = 1.2,
	Seed = 20260923,

	-- ---------------------------------------------------------------- bands (by Day)
	-- `from` is the Day a band is fully up; it starts showing `fade` Days earlier. Placed on the
	-- pacing curve (tests/Pacing.spec.luau): each band takes ~2.5x as long to first reach as the one
	-- before; Deep Sky is the headline a normal player reaches in 30-45 min.
	Bands = {
		{ id = "clear", name = "Clear Night", emoji = "🌙", from = 0, fade = 0,
			features = features({ stars = 0.55, moon = 1 }) },
		{ id = "meteors", name = "Meteor Shower", emoji = "🌠", from = 4, fade = 2,
			features = features({ stars = 0.7, moon = 1, meteors = 1 }) },
		{ id = "aurora", name = "Aurora", emoji = "🌌", from = 9, fade = 2,
			features = features({ stars = 0.7, moon = 0.9, meteors = 0.3, aurora = 1 }) },
		{ id = "comet", name = "The Great Comet", emoji = "☄️", from = 15, fade = 3,
			features = features({ stars = 0.8, moon = 1, meteors = 0.2, aurora = 0.35, comet = 1 }) },
		{ id = "storm", name = "Storm Front", emoji = "⛈️", from = 22, fade = 3,
			features = features({ stars = 0.25, moon = 0.35, comet = 0.3, storm = 1 }) },
		{ id = "deepsky", name = "Deep Sky", emoji = "🔭", from = 31, fade = 3,
			features = features({ stars = 1, moon = 0.6, meteors = 0.15, nebula = 1 }) },
		{ id = "alignment", name = "The Alignment", emoji = "🪐", from = 40, fade = 4,
			features = features({ stars = 1, moon = 1, meteors = 0.15, aurora = 0.2, nebula = 0.4, planets = 1 }) },
		{ id = "othersky", name = "The Other Sky", emoji = "👁️", from = 50, fade = 5,
			features = features({ stars = 1, moon = 1, meteors = 0.3, aurora = 0.3, nebula = 0.5, planets = 0.3, othersky = 1 }) },
	},

	-- ---------------------------------------------------------------- the pieces
	-- The moon waxes as the streak grows: a thin crescent on Day 1, full around Day 14, new again
	-- near Day 30 (a dark sky for the Deep Sky band). The phase is drawn by sliding a dark disc.
	Moon = { SynodicDays = 29.5, PhaseAtDay1 = 0.07, MaxTurnPerSecond = 0.012, Azimuth = -24, Elevation = 27, Distance = 720, Radius = 20,
		Color = "moon", ShadowColor = "moonShade" },
	Horizon = { Count = 11, AzRange = { -62, 62 }, Distance = 640, BelowEye = 150, Heights = { 110, 210 },
		Widths = { 170, 280 }, Depth = 60, Color = "ridge" },
	Valley = { MistCount = 2, MistDistance = 420, MistBelowEye = 120, MistSize = { 700, 6, 260 }, MistColor = "mist",
		MistTransparency = 0.82, LightCount = 10, LightDistance = { 380, 560 }, LightAzRange = { -45, 45 },
		LightBelowEye = 150, LightSize = 3, LightColor = "valleyLight" },
	Stars = { Distance = 820, Azimuth = 0, Elevation = 38, Size = { 1500, 700, 20 }, Rate = 10,
		Lifetime = { 5, 9 }, ParticleSize = 2.2, Color = "star" },
	Meteors = { SlotSeconds = 2, Chance = 0.45, Duration = 0.8, AzRange = { -40, 40 }, ElRange = { 20, 55 },
		Length = 16, Distance = 680, Pool = 2, Size = { 1.2, 1.2, 9 }, TrailSeconds = 0.45, Color = "meteor", Salt = 11 },
	Aurora = { Count = 4, AzRange = { -60, 55 }, ElRange = { 7, 16 }, Distance = 700, Width = { 90, 150 },
		SwaySeconds = 23, SwayStuds = 60, Colors = { "auroraGreen", "auroraTeal", "auroraViolet" }, Transparency = { 0.35, 0.85 } },
	Comet = { Azimuth = 20, Elevation = 31, Distance = 740, HeadRadius = 4, ComaRadius = 11, ComaTransparency = 0.7,
		TailAzimuth = 40, TailElevation = 22, TailLength = 300, TailWidth = { 16, 90 },
		Color = "cometHead", ComaColor = "cometComa", TailColor = "cometTail" },
	Storm = { CloudCount = 9, AzRange = { -55, 25 }, ElRange = { 1, 9 }, Distance = 610, Radius = { 55, 110 },
		Color = "stormCloud", Transparency = 0.12 },
	-- Silent lightning: bright Neon segments inside the cloud bank. Neon lights nothing, and the sky
	-- owns no Light, so a flash can never flicker the hall (that would be "The Flicker" anomaly).
	Lightning = { SlotSeconds = 1.3, Chance = 0.25, Duration = 0.14, AzRange = { -50, 20 }, ElRange = { 2, 12 },
		Distance = 590, Thickness = 1.6, Color = "lightning", Salt = 23 },
	-- Rain falls straight down from a host ABOVE and IN FRONT OF the entrance (z 30..90), far enough
	-- out that its sideways drift (Speed x Lifetime x sin(Spread) = 2.9 studs) never reaches it.
	Rain = { Offset = { 0, 40, 60 }, Size = { 70, 2, 60 }, Rate = 40, Speed = 70, Lifetime = 1.2, SpreadDegrees = 2,
		Color = "rain" },
	Nebula = { Count = 6, Azimuth = 22, Elevation = 33, Distance = 820, Spread = { 30, 16 }, Radius = { 55, 120 },
		Colors = { "nebulaViolet", "nebulaBlue", "nebulaTeal" }, Transparency = { 0.86, 0.93 },
		-- 2000 long: Roblox clamps every Part axis at 2048 studs (NightSky.engineSizeOk)
		MilkyWay = { Azimuth = -10, Elevation = 45, Distance = 900, Size = { 2000, 140, 4 }, Tilt = 28,
			Color = "milkyWay", Transparency = 0.9 },
		Galaxy = { Azimuth = -34, Elevation = 40, Distance = 800, Radius = 38, Color = "galaxy", CoreColor = "galaxyCore",
			Transparency = 0.55 } },
	Planets = { Distance = 760, List = {
		{ key = "Mercury", az = -40, el = 11, r = 3, color = "mercury" },
		{ key = "Venus", az = -24, el = 15, r = 6, color = "venus" },
		{ key = "Mars", az = -8, el = 19, r = 5, color = "mars" },
		{ key = "Jupiter", az = 10, el = 24, r = 13, color = "jupiter" },
		{ key = "Saturn", az = 30, el = 28, r = 10, color = "saturn", ring = 23, ringColor = "saturnRing" },
	} },
	OtherSky = {
		Moon2 = { Azimuth = 26, Elevation = 40, Distance = 760, Radius = 14, Color = "moon2" },
		Ring = { Azimuth = 0, Elevation = 58, Distance = 950, Radius = 420, Segments = 18, SegmentSize = { 150, 5, 5 },
			Color = "ring", Transparency = 0.55 },
		Spiral = { Azimuth = -18, Elevation = 44, Distance = 860, Count = 24, Radius = 150, Turns = 1.6, StarRadius = 2.2,
			PeriodSeconds = 180, Color = "spiral" },
	},

	-- No reddish colour anywhere (NightSky.isReddish): "Red Shift" and "Blood Moon" are anomalies.
	Palette = {
		moon = { 228, 232, 240 }, moonShade = { 22, 26, 36 }, ridge = { 12, 14, 22 }, mist = { 150, 165, 190 },
		valleyLight = { 245, 200, 120 }, star = { 235, 240, 255 }, meteor = { 220, 235, 255 },
		auroraGreen = { 90, 235, 150 }, auroraTeal = { 70, 210, 210 }, auroraViolet = { 160, 120, 235 },
		cometHead = { 235, 245, 255 }, cometComa = { 170, 220, 240 }, cometTail = { 150, 205, 245 },
		stormCloud = { 38, 42, 56 }, lightning = { 215, 228, 255 }, rain = { 170, 185, 210 },
		nebulaViolet = { 150, 105, 220 }, nebulaBlue = { 90, 135, 235 }, nebulaTeal = { 80, 200, 195 },
		milkyWay = { 195, 205, 235 }, galaxy = { 185, 195, 235 }, galaxyCore = { 250, 240, 215 },
		mercury = { 170, 168, 160 }, venus = { 250, 244, 220 }, mars = { 210, 150, 95 }, jupiter = { 215, 185, 145 },
		saturn = { 228, 208, 155 }, saturnRing = { 210, 195, 160 }, moon2 = { 200, 232, 215 }, ring = { 205, 215, 240 },
		spiral = { 220, 230, 255 },
	},

	-- ---------------------------------------------------------------- the telescope break (rest)
	-- A Roblox server cannot pause, and this game has nothing to pause: no clock inside a pass, no
	-- chaser, no hazard. A break is the player stepping out to the telescope: the local camera fades
	-- to a view beyond the entrance, looking up and away from every hall, and fades back when they
	-- move. The server is never told; the pass, the Day and the roll are untouched.
	-- The template's Rest rules, with nothing to pause: no idle timer (IdleSeconds 0), move to wake,
	-- and a break asked for during the death beat (the "threat") waits for the beat to end.
	Rest = { WakeOnMove = true, BlockWhileThreat = true, IdleSeconds = 0, PendingSeconds = 4, WakeGraceSeconds = 0.3,
		RequireGrounded = true },
	DeathBeatSeconds = 3.0, -- the server pauses 2.5 s after a wrong call before the next pass
	-- Roblox disconnects a player idle for about 20 minutes, and the Day streak lives only for the
	-- session (Best Day is what is saved). A break is a player not touching anything, so its caption
	-- never calls the Day "safe" and, once Player.Idled fires, says what idling costs (NightSky.breakCaption).
	IdleKickMinutes = 20,
	RestView = {
		Offset = { 0, 22, 64 }, -- 54 studs out past the entrance, above the roof line
		PitchDegrees = 17, PitchSwayDegrees = 3, YawSwayDegrees = 6, SwayPeriod = 80,
		FovDegrees = 70, MaxAspect = 3.6, FadeSeconds = 0.3,
		-- only while the camera is out at the telescope, restored before it comes back
		Atmosphere = { Density = 0.2, Haze = 0.6 },
		Grade = { Saturation = 0.3, Brightness = 0.03, Contrast = 0.05 },
	},

	Budget = { MaxParts = 140, MaxEmitters = 2, MaxEmitterRate = 60, MaxBeams = 8, MaxTrails = 4, MaxLights = 0 },

	-- ---------------------------------------------------------------- pacing model (tests only)
	-- Assumptions of tests/NightModel.luau. Not telemetry: retune `normal` first when data exists.
	Pacing = {
		Headline = "deepsky",
		HeadlineMinutes = { 30, 45 },
		Profiles = {
			normal = { passSeconds = 16, deathSeconds = 3.5, falseAlarm = 0.03, spotObvious = 0.96, spotSubtle = 0.82 },
			fast = { passSeconds = 11, deathSeconds = 3, falseAlarm = 0.015, spotObvious = 0.99, spotSubtle = 0.93 },
			slow = { passSeconds = 24, deathSeconds = 4.5, falseAlarm = 0.06, spotObvious = 0.9, spotSubtle = 0.68 },
		},
	},
}

return Config
