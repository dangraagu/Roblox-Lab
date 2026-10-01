--!strict
-- Save.luau — the persisted profile: defaults, the normaliser for whatever the DataStore hands back,
-- the Falling Star's one-way states, and what exactly gets written. PURE.
--
-- DataStore `MeteorDropTycoon_v1`, key u_<userId>, record { session, jobId, lockUntil, data = <this> }.
-- The session lock and the owner token live in Main.server.luau; this file only shapes `data`.
-- No integer keys anywhere (JSON turns sparse integer keys into strings). Spec: tests/Save.spec.luau.

local Save = {}

Save.VERSION = 1

-- field -> kind. "int" floors, "num" keeps fractions (ore and Stardust melt continuously).
local FIELDS = {
	stardust = "num", -- spendable
	lifetime = "num", -- every Stardust ever minted (the Star Chart footer)
	beacon = "int",
	beaconAt = "int", -- os.time() when `beacon` was first reached (the board's tie-break)
	collector = "int",
	smelter = "int",
	hopper = "num", -- ore waiting in the hopper; melts again next session, never offline
	star = "int", -- the Falling Star: 0 not granted / 1 granted, not caught / 2 caught
	starCores = "int", -- legendaries caught by hand, the Falling Star included
	tutorial = "int", -- the first-minutes hint step, 0..3
	-- seconds the Collector had left awake when this was saved (REVIEW-1: a session used to start awake, so
	-- an auto-rejoin every 10 min re-armed a sleeping dish). A record without it starts awake; 0..IdleSeconds.
	awake = "num",
}

function Save.defaults(): any
	return {
		v = Save.VERSION,
		stardust = 0,
		lifetime = 0,
		beacon = 0,
		beaconAt = 0,
		collector = 0,
		smelter = 0,
		hopper = 0,
		star = 0,
		starCores = 0,
		tutorial = 0,
		awake = 0,
	}
end

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Any loaded value -> a safe profile. A non-number or a NaN / infinity gives the default, a negative
-- gives 0, integers are floored, the Collector is clamped to its maximum, the star to its three states,
-- the tutorial to 0..3, the Collector's awake time to 0..IdleSeconds (missing: IdleSeconds, awake).
-- Unknown fields are dropped.
function Save.normalise(cfg: any, raw: any): any
	local out = Save.defaults()
	if type(raw) ~= "table" then return out end
	for field, kind in FIELDS do
		local v = raw[field]
		if finite(v) then
			v = math.max(0, v)
			if kind == "int" then v = math.floor(v) end
			out[field] = v
		end
	end
	out.collector = math.min(out.collector, cfg.Collector.Max)
	-- a record saved before the Collector's clock was (or a new player's first save): it starts awake
	out.awake = if finite(raw.awake) then math.clamp(raw.awake, 0, cfg.Collector.IdleSeconds) else cfg.Collector.IdleSeconds
	if out.star > 2 then out.star = 0 end
	out.tutorial = math.min(out.tutorial, 3)
	out.lifetime = math.max(out.lifetime, out.stardust)
	return out
end

-- 0 -> 1. Only the server calls it, inside the atomic write that grants the star (Main.server.luau).
function Save.grantStar(d: any): boolean
	if d.star ~= 0 then return false end
	d.star = 1
	return true
end

-- 1 -> 2, in the same pending save as the Stardust it pays.
function Save.catchStar(d: any): boolean
	if d.star ~= 1 then return false end
	d.star = 2
	return true
end

-- What is written: exactly the documented fields, as a copy.
function Save.pack(d: any): any
	local out = { v = Save.VERSION }
	for field in FIELDS do
		out[field] = d[field]
	end
	return out
end

return Save
