--!strict
-- BreakRoom.luau — what "rest" means in a timed maze. Pure, no Roblox; Rest is passed in.
--
-- The run clock is the medal and the record, the traps pulse on the server, the monsters hunt on
-- the server, and Roblox cannot stop the world for one player. A pause INSIDE a run would either
-- freeze nothing that matters (and tell the player they are safe when they are not) or freeze the
-- clock (and hand out free medal time). So rest lives BETWEEN runs:
--   * the lobby is the break room: bright, no monsters, no traps, no hazards, no clock. A campfire
--     there lets you sit down; the sit is the template's Rest state (any move wakes you);
--   * every level starts beside the 🚪 Lobby door. The server does not count a voluntary return
--     shorter than CONFIG.Assist.MinRunSeconds as a failed attempt, so for the first seconds of a
--     level walking out costs nothing at all. A sign on the door says so while, and only while, it
--     is true — with a margin for the payload's network delay, since the client's clock starts
--     when the level's payload ARRIVES and the server's started before it was sent — and never while
--     the run has a "Hjelp meg" guide active (review fix, 24.09: a walk-out then lost it; since the owner's
--     decision of 30.09 the buyer keeps it until the level is cleared, but a guided run is no plain fresh
--     start, and in a shared run the guide may be someone else's, so the sign keeps out of it);
--   * rest is never available inside a run (mayRest fails closed).
-- Leaving a run ends it: the run's clock is thrown away, no time is recorded, and the next attempt
-- starts a fresh clock. Nothing is dodged, because nothing is paused.

local BreakRoom = {}

function BreakRoom.validate(cfg: any, Rest: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no rest config" end
	local ok, err = Rest.validate(cfg)
	if not ok then return false, err end
	for _, k in { "ServerMinRunSeconds", "FreeBreakSeconds", "LatencyMarginSeconds", "SignFadeSeconds" } do
		if type(cfg[k]) ~= "number" or cfg[k] ~= cfg[k] then return false, k .. " must be a number" end
	end
	if cfg.ServerMinRunSeconds <= 0 then return false, "ServerMinRunSeconds must mirror the server's rule (> 0)" end
	if cfg.FreeBreakSeconds <= 0 then return false, "FreeBreakSeconds must be > 0" end
	if cfg.LatencyMarginSeconds < 1 then return false, "LatencyMarginSeconds must be >= 1" end
	if cfg.FreeBreakSeconds + cfg.LatencyMarginSeconds > cfg.ServerMinRunSeconds then
		return false, "the sign would promise a free break after the server stops treating it as free"
	end
	if cfg.SignFadeSeconds < 0 or cfg.SignFadeSeconds > cfg.FreeBreakSeconds then
		return false, "SignFadeSeconds must be within 0..FreeBreakSeconds"
	end
	return true, nil
end

-- Is walking out through the Lobby door free, `elapsed` seconds after this level's payload arrived?
-- `run` (optional): `guideActive` = a "Hjelp meg" guide is active in this run. The sign then says nothing, whatever
-- the clock: the sign only speaks for a plain fresh run (see the header; a buyer keeps the guide since 30.09).
function BreakRoom.freeBreak(elapsed: number, cfg: any, run: any?): boolean
	if type(elapsed) ~= "number" or elapsed ~= elapsed or elapsed < 0 then return false end
	if type(run) == "table" and run.guideActive == true then return false end
	return elapsed < cfg.FreeBreakSeconds
end

-- The door sign's opacity: 1, fading out over SignFadeSeconds, gone exactly when the free window ends
-- (or at once, while a guide is active: see freeBreak).
function BreakRoom.signAlpha(elapsed: number, cfg: any, run: any?): number
	if not BreakRoom.freeBreak(elapsed, cfg, run) then return 0 end
	local fadeStart = cfg.FreeBreakSeconds - cfg.SignFadeSeconds
	if elapsed <= fadeStart or cfg.SignFadeSeconds <= 0 then return 1 end
	return math.clamp((cfg.FreeBreakSeconds - elapsed) / cfg.SignFadeSeconds, 0, 1)
end

-- Rest (sitting down by the campfire) only in the lobby. Unknown whereabouts: no.
function BreakRoom.mayRest(ctx: any): boolean
	return type(ctx) == "table" and ctx.inLobby == true and ctx.dead ~= true
end

return BreakRoom
