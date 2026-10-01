--!strict
-- Rest.luau — what "pause" means when the server cannot pause. Pure.
--
-- COPIED from plus1-jump/src/shared/Rest.luau (md5 19226cb6...) with its spec. Everything is the template verbatim
-- EXCEPT one adaptation (DESIGN.md §6): in SIGNAL LOST the tank drains only in vacuum and nothing in the world runs
-- out, so rest is allowed wherever there is AIR (the lifeboat, any air module) and nowhere else.
--   * ctx.where = "hub" | "air" | "vacuum" | nil. When it is given, rest may start or continue only where
--     cfg.AllowedIn says; a request elsewhere is REFUSED (with Rest.refusal's reason), never queued, because you
--     cannot rest without moving to air and moving drops a queued request; a resting player found elsewhere wakes.
--   * validateStation() adds to validate(): AllowedIn names only known places, allows at least one, and NEVER
--     vacuum, where AIR drains. Rest.PAUSES_AIR is false: AIR is the server's arithmetic, rest is presentation.
-- Without ctx.where the template behaves exactly as before (its spec still runs unchanged).
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

Rest.PAUSES_AIR = false

-- Every place the client can report, and whether rest may EVER be allowed there.
local KNOWN = { hub = true, air = true, vacuum = false }

-- Is `where` a place rest may happen? nil (a ride, a blackout, not in the world) never is.
function Rest.allowedIn(cfg: any, where: string?): boolean
	if where == nil then return false end
	return KNOWN[where] == true and type(cfg.AllowedIn) == "table" and cfg.AllowedIn[where] == true
end

-- The line the HUD shows when rest is refused somewhere.
function Rest.refusal(cfg: any, where: string?): string
	local T = cfg.Text or {}
	if where == "vacuum" then return T.NoAir or "No air here." end
	return T.NotHere or "You can't rest here."
end

function Rest.validateStation(cfg: any): (boolean, string?)
	local ok, err = Rest.validate(cfg)
	if not ok then return false, err end
	if type(cfg.AllowedIn) ~= "table" then return false, "no AllowedIn" end
	local any = false
	for where, on in cfg.AllowedIn do
		if on ~= true then return false, "AllowedIn." .. tostring(where) .. " must be true or absent" end
		if KNOWN[where] == nil then return false, "unknown place '" .. tostring(where) .. "'" end
		if KNOWN[where] == false then
			return false, "rest in '" .. tostring(where) .. "' would pause nothing and hide a draining tank: never vacuum"
		end
		any = true
	end
	if not any then return false, "AllowedIn is empty: rest would never happen" end
	return true, nil
end

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

-- "resting" | "queued" | "already" | "refused" (Signal Lost: not where there is air)
function Rest.request(s: any, cfg: any, ctx: any): string
	if s.resting then return "already" end
	if ctx.where ~= nil or cfg.AllowedIn ~= nil then
		-- Signal Lost: only where there is air; refused, never queued
		if not Rest.allowedIn(cfg, ctx.where) then
			s.pending = false
			s.pendingFor = 0
			return "refused"
		end
	end
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
	-- Signal Lost: nothing of rest survives outside the air
	local here = true
	if ctx.where ~= nil or cfg.AllowedIn ~= nil then
		here = Rest.allowedIn(cfg, ctx.where)
	end
	if not here then
		s.idle = 0
		if s.resting then
			Rest.stop(s)
			return "woke"
		end
		if s.pending then
			s.pending = false
			s.pendingFor = 0
			return "dropped"
		end
		return nil
	end
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
