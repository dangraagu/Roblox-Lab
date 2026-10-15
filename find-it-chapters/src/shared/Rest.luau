--!strict
-- Rest.luau — what "pause" means when the server cannot pause. Game-agnostic, pure.
--
-- Rest is a per-player STATE, not a frozen world:
--   * enter it by asking (manual) or by standing still for IdleSeconds (idle — AFK safety);
--   * it cannot START in the air or with a threat inbound. The request is queued and taken the
--     first safe moment the player stands still, and expires after PendingSeconds — so rest is
--     never a panic button against a hazard already on its way. Dodging (moving while the threat
--     is live) keeps the request; walking on under a clear sky past WakeGraceSeconds drops it;
--   * any movement wakes the player, so nothing that needs movement can happen while resting;
--   * `hazardsMayRun` is false while resting. Callers FREEZE their hazard clocks on it and never
--     reset them, so toggling rest cannot thin out hazards (tests/Hazards.spec.luau measures it).
--
-- Games whose design depends on a clock (a timed round, a raid) must not map rest onto that clock:
-- rest here only ever pauses things that exist to bother the player, never a thing they race.
--
-- update() and request() take ctx = { moving: boolean, grounded: boolean, threat: boolean }.

local Rest = {}

function Rest.validate(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no rest config" end
	if cfg.WakeOnMove ~= true then
		return false, "WakeOnMove must be true: a player who can move while resting can progress while resting"
	end
	if cfg.BlockWhileThreat ~= true then
		return false, "BlockWhileThreat must be true: otherwise rest cancels an inbound hazard (a panic button)"
	end
	if type(cfg.IdleSeconds) ~= "number" or cfg.IdleSeconds < 0 then
		return false, "IdleSeconds must be >= 0 (0 disables idle rest)"
	end
	if type(cfg.PendingSeconds) ~= "number" or cfg.PendingSeconds <= 0 then
		return false, "PendingSeconds must be > 0"
	end
	if type(cfg.WakeGraceSeconds) ~= "number" or cfg.WakeGraceSeconds < 0 then
		return false, "WakeGraceSeconds must be >= 0"
	end
	return true, nil
end

function Rest.new(): any
	return { resting = false, source = nil, pending = false, pendingFor = 0, idle = 0, restedFor = 0 }
end

function Rest.isResting(s: any): boolean
	return s.resting
end

function Rest.hazardsMayRun(s: any): boolean
	return not s.resting
end

local function safeToStart(cfg: any, ctx: any): boolean
	if cfg.RequireGrounded and not ctx.grounded then return false end
	if ctx.threat then return false end
	return true
end

local function start(s: any, source: string)
	s.resting = true
	s.source = source
	s.pending = false
	s.pendingFor = 0
	s.idle = 0
	s.restedFor = 0
end

-- "resting" | "queued" | "already"
function Rest.request(s: any, cfg: any, ctx: any): string
	if s.resting then return "already" end
	if safeToStart(cfg, ctx) then
		start(s, "manual")
		return "resting"
	end
	s.pending = true
	s.pendingFor = 0
	s.clearFor = 0
	return "queued"
end

-- "stopped" | "cancelled" | "idle"
function Rest.stop(s: any): string
	if s.resting then
		s.resting = false
		s.source = nil
		s.idle = 0
		return "stopped"
	end
	if s.pending then
		s.pending = false
		s.pendingFor = 0
		return "cancelled"
	end
	return "idle"
end

-- nil | "started" | "woke" | "dropped" | "expired"
function Rest.update(s: any, cfg: any, dt: number, ctx: any): string?
	if s.resting then
		s.restedFor += dt
		if not ctx.grounded then
			Rest.stop(s)
			return "woke"
		end
		if ctx.moving and s.restedFor >= cfg.WakeGraceSeconds then
			Rest.stop(s)
			return "woke"
		end
		return nil
	end

	if s.pending then
		s.pendingFor += dt
		-- Seconds the sky has been clear since the request. Moving while a threat is inbound is what
		-- the warning asks for (step off the lane), so it never drops the request; walking on under a
		-- clear sky past the wake grace does (the player chose to keep climbing).
		s.clearFor = if ctx.threat then 0 else (s.clearFor or 0) + dt
		if ctx.grounded and ctx.moving and not ctx.threat and s.clearFor >= cfg.WakeGraceSeconds - 1e-9 then
			s.pending = false
			s.pendingFor = 0
			return "dropped"
		end
		if safeToStart(cfg, ctx) and not ctx.moving then
			start(s, "manual")
			return "started"
		end
		if s.pendingFor >= cfg.PendingSeconds then
			s.pending = false
			s.pendingFor = 0
			return "expired"
		end
		return nil
	end

	if ctx.moving or not ctx.grounded or ctx.threat then
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
