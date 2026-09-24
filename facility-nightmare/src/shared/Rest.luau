--!strict
-- Rest.luau — what "pause" means in FACILITY. Pure.
--
-- Adapted from plus1-jump/src/shared/Rest.luau, where rest is a per-player STATE (a server cannot
-- stop the world for one player). What changed, and why: in +1 Jump nothing races the player, so rest
-- could happen anywhere. In FACILITY a run IS a race against the blackout front, a clock that every
-- number in DESIGN.md was measured against. Freezing it for one player is exactly the exploit the
-- owner ruled out (rest just before a room dies, walk out when you please). So rest exists only
-- BETWEEN runs, in the break room, where there is no front, no hazard, no penalty and nothing to lose:
--   * `Phases` lists where rest may happen; validate() refuses a list naming any phase of a run
--     ("ride", "floor", "dying") and anything it does not know (a typo must not open a hole);
--   * you rest by sitting on a break-room bench (at once) or by standing still there IdleSeconds;
--   * standing up, moving, stepping into the elevator car or the run starting ends it;
--   * Rest.PAUSES_RUN_CLOCK is false: nothing here has, or will get, a hook into the run.
-- update() takes ctx = { phase: string?, seated: boolean, moving: boolean, boarding: boolean }.

local Rest = {}

Rest.PAUSES_RUN_CLOCK = false

-- Every phase the server's State can report, and whether rest may EVER be allowed in it.
local KNOWN = { hub = true, ride = false, floor = false, dying = false }

function Rest.validate(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no rest config" end
	if type(cfg.Phases) ~= "table" then return false, "no Phases" end
	local any = false
	for phase, on in cfg.Phases do
		if on ~= true then
			return false, "Phases." .. tostring(phase) .. " must be true or absent"
		end
		if KNOWN[phase] == nil then
			return false, "unknown phase '" .. tostring(phase) .. "'"
		end
		if KNOWN[phase] == false then
			return false, "rest in '" .. tostring(phase) .. "' would pause part of a run: the blackout front is the game's clock"
		end
		any = true
	end
	if not any then return false, "Phases is empty: rest would never happen" end
	if type(cfg.IdleSeconds) ~= "number" or cfg.IdleSeconds ~= cfg.IdleSeconds or cfg.IdleSeconds < 0 then
		return false, "IdleSeconds must be >= 0 (0 switches idle rest off)"
	end
	return true, nil
end

function Rest.new(): any
	return { resting = false, source = nil, idle = 0, restedFor = 0 }
end

function Rest.allowed(cfg: any, phase: string?): boolean
	if phase == nil then return false end
	return cfg.Phases[phase] == true and KNOWN[phase] == true
end

function Rest.isResting(s: any): boolean
	return s.resting
end

-- The template's contract: callers freeze their hazard clocks on this. In FACILITY it is belt and
-- braces, since hazards only exist on a sublevel and rest only in the break room.
function Rest.hazardsMayRun(s: any): boolean
	return not s.resting
end

local function start(s: any, source: string)
	s.resting = true
	s.source = source
	s.idle = 0
	s.restedFor = 0
end

local function stop(s: any)
	s.resting = false
	s.source = nil
	s.idle = 0
end

-- nil | "started" | "woke"
function Rest.update(s: any, cfg: any, dt: number, ctx: any): string?
	if not Rest.allowed(cfg, ctx.phase) or ctx.boarding then
		s.idle = 0
		if s.resting then
			stop(s)
			return "woke"
		end
		return nil
	end
	if s.resting then
		s.restedFor += dt
		if ctx.seated then
			s.source = "bench"
			return nil
		end
		if s.source == "bench" or ctx.moving then
			stop(s)
			return "woke"
		end
		return nil
	end
	if ctx.seated then
		start(s, "bench")
		return "started"
	end
	if ctx.moving then
		s.idle = 0
		return nil
	end
	s.idle += dt
	if cfg.IdleSeconds > 0 and s.idle >= cfg.IdleSeconds - 1e-9 then
		start(s, "idle")
		return "started"
	end
	return nil
end

return Rest
