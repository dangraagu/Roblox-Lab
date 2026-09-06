--!strict
-- Progression.luau — the Day/streak rules. Pure: no Instances, no DataStore. The server
-- owns persistence (best day, Field Guide) and just calls resolve() each pass.
--
-- Correct call  = ADVANCE on a clean hall, or TURN_BACK on an anomalous hall.
-- Correct       -> Day + 1 (capped at MaxDay).
-- Wrong         -> the run ends; Day resets to StartDay.

-- NOTE: no `require("./Anomaly")`. A bare string require resolves in the luau CLI but is
-- INVALID in Roblox (require takes an Instance) and would break the whole server script.
-- The Pass shape is tiny, so it is declared structurally here instead of imported.
export type Pass = { clean: boolean, anomalyId: string? }

export type State = { day: number }
export type Resolution = { correct: boolean, day: number, reset: boolean }

local Progression = {}

Progression.ADVANCE = "ADVANCE"
Progression.TURN_BACK = "TURN_BACK"

-- Fresh run state.
function Progression.newRun(cfg: any): State
	return { day = cfg.Progression.StartDay }
end

-- Is this the right call for this pass?
function Progression.isCorrect(choice: string, pass: Pass): boolean
	if choice == Progression.ADVANCE then
		return pass.clean == true
	elseif choice == Progression.TURN_BACK then
		return pass.clean == false
	end
	return false -- unknown choice is never correct
end

-- Apply a choice to the state. Returns a NEW state plus what happened. Never mutates the
-- passed-in state (server decides what to persist).
function Progression.resolve(state: State, choice: string, pass: Pass, cfg: any): (State, Resolution)
	local correct = Progression.isCorrect(choice, pass)
	if correct then
		local day = math.min(state.day + 1, cfg.Progression.MaxDay)
		return { day = day }, { correct = true, day = day, reset = false }
	else
		local day = cfg.Progression.StartDay
		return { day = day }, { correct = false, day = day, reset = true }
	end
end

-- New best after finishing a pass at `day` (monotonic).
function Progression.bestAfter(best: number, day: number): number
	return math.max(best, day)
end

-- Was an anomaly successfully CAUGHT (correct + it was an anomaly)? If so its id should
-- be added to the Field Guide. Returns the id or nil.
function Progression.caughtAnomalyId(choice: string, pass: Pass): string?
	if pass.clean == false and choice == Progression.TURN_BACK and pass.anomalyId then
		return pass.anomalyId
	end
	return nil
end

return Progression
