--!strict
-- Pause.luau — where rest is allowed in The Same Door (DESIGN §9). Pure.
--
-- The run clock never stops: it is the medal and the record, and Rest.luau's own header says rest
-- only pauses things that exist to bother the player, never a thing they race. So rest lives between
-- runs, in the hub (labyrint-spill's BreakRoom precedent):
--   * mayRest(ctx) is true only in the hub and outside a run, and fails closed on anything else;
--   * the pause button in a run opens a sheet; its only way to rest is to LEAVE the run. Nothing is
--     paused while it is open, so there is no free thinking time.
-- Hazards exist only inside a run, on the run clock, so there is no hazard clock to freeze outside
-- one: rest sends no remote and earns nothing.

local Pause = {}

function Pause.mayRest(ctx: any): boolean
	if type(ctx) ~= "table" then return false end
	return ctx.inHub == true and ctx.inRun == false
end

function Pause.sheet(): { text: string, leave: string, stay: string }
	return {
		text = "The clock never stops. Leave this run and rest by the fire?",
		leave = "Leave run",
		stay = "Keep running",
	}
end

function Pause.pausesClock(): boolean
	return false
end

return Pause
