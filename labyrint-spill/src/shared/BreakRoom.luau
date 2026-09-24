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
--     the run holds a "Hjelp meg" guide bought for it, which a walk-out loses (review fix);
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
-- `run` (optional) = what this run holds that a walk-out would lose: `guideActive` = a "Hjelp meg" guide
-- was bought for this run. The guide belongs to the run (the server builds it into the run's maze and a
-- walk-out tears that down, no refund), so with one active the walk-out is not free, whatever the clock.
function BreakRoom.freeBreak(elapsed: number, cfg: any, run: any?): boolean
	if type(elapsed) ~= "number" or elapsed ~= elapsed or elapsed < 0 then return false end
	if type(run) == "table" and run.guideActive == true then return false end
	return elapsed < cfg.FreeBreakSeconds
end

-- The door sign's opacity: 1, fading out over SignFadeSeconds, gone exactly when the free window ends
-- (or at once, while the run holds something a walk-out would lose: see freeBreak).
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
