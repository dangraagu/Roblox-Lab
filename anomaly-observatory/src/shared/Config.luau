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

return Config
