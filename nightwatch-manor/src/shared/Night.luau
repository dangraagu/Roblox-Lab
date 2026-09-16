--!strict
-- Night.luau — how a night ends and what it pays. PURE LOGIC, config and the aggregated
-- upgrade effects passed in as arguments.
--
-- Three ways out of the manor, and only one of them is good:
--   EXTRACTED — you reached the servants' exit. The bag banks in full, the night advances,
--               and the night you just survived becomes your record if it beats the old one.
--   CAUGHT    — the Nightwatcher reached you. You keep only what a Lockbox saves.
--   EVICTED   — dread filled before you got out. Same economics as CAUGHT, different words,
--               because "it caught you" and "you ran out of night" are different lessons.
-- Neither failure rolls the night BACK. Losing a haul is the punishment; losing the tycoon
-- progress on top of it would make every upgrade feel unsafe to earn.
--
-- No `require` here — dependencies come in as arguments (see the note in Manor.luau).
export type State = { night: number, stash: number, best: number, carried: { string } }
export type Result = {
	outcome: string,
	gained: number,
	lost: number,
	night: number, -- the night that was just played
	nextNight: number,
	newBest: boolean,
}

local Night = {}

Night.EXTRACTED = "EXTRACTED"
Night.CAUGHT = "CAUGHT"
Night.EVICTED = "EVICTED"

function Night.tierById(cfg: any, id: string): any
	for _, t in cfg.Relics.Tiers do
		if t.id == id then
			return t
		end
	end
	return nil
end

-- Worth of one relic. An id the catalog does not know is worth 0, never nil: this feeds
-- arithmetic, and a nil here would take the whole payout down with it.
function Night.relicWorth(cfg: any, id: string): number
	local t = Night.tierById(cfg, id)
	return t and t.worth or 0
end

function Night.carriedWorth(cfg: any, carried: { string }): number
	local total = 0
	for _, id in carried do
		total += Night.relicWorth(cfg, id)
	end
	return total
end

-- What the bag banks for, after the Relic Vault multiplier. Floored: relics are whole things.
function Night.payout(cfg: any, carried: { string }, effects: any): number
	return math.floor(Night.carriedWorth(cfg, carried) * (1 + (effects.relicValue or 0)))
end

-- How long this night lasts before dread hits 1. Shrinks with the night number down to
-- DreadMin, then grows again with Floodlights (flat seconds) and Wardstones (a slow factor).
-- Both upgrade effects are capped upstream, so this can never return infinity.
function Night.dreadSeconds(cfg: any, night: number, effects: any): number
	local N = cfg.Night
	local base = math.max(N.DreadSeconds + (math.max(night, 1) - 1) * N.DreadPerNight, N.DreadMin)
	local slow = math.min(effects.dreadSlow or 0, 0.9)
	return (base + (effects.extractSeconds or 0)) / (1 - slow)
end

-- Build the run state from a persisted profile. Every field is defended: a corrupt or
-- hand-edited save must not be able to put anybody on night 0, night -12 or night 10^9.
function Night.startState(cfg: any, profile: any): State
	local N = cfg.Night
	local night = tonumber(profile and profile.night) or N.StartNight
	night = math.floor(night)
	if night < N.StartNight then
		night = N.StartNight
	elseif night > N.MaxNight then
		night = N.MaxNight
	end
	local stash = tonumber(profile and profile.stash) or N.StartStash
	local best = tonumber(profile and profile.best) or 0
	return {
		night = night,
		stash = math.max(math.floor(stash), 0),
		best = math.max(math.floor(best), 0),
		carried = {},
	}
end

function Night.bestAfter(best: number, night: number): number
	return math.max(best, night)
end

-- Resolve a finished night. Returns a NEW state plus a result the HUD can narrate; the state
-- handed in is never mutated, because the server resolves first and persists afterwards.
--
-- An outcome nobody defined RAISES. Guessing would be worse in both directions: treated as a
-- survival it hands out free nights forever, treated as a death it eats hauls for nothing.
function Night.resolve(state: State, outcome: string, cfg: any, effects: any): (State, Result)
	local total = Night.payout(cfg, state.carried, effects)
	local gained, nextNight, best

	if outcome == Night.EXTRACTED then
		gained = total
		nextNight = math.min(state.night + 1, cfg.Night.MaxNight)
		best = Night.bestAfter(state.best, state.night)
	elseif outcome == Night.CAUGHT or outcome == Night.EVICTED then
		gained = math.floor(total * math.min(effects.keepOnCaught or 0, 1))
		nextNight = state.night -- you retry the same night; the tycoon progress survives
		best = state.best
	else
		error("Night.resolve: unknown outcome '" .. tostring(outcome) .. "'", 0)
	end

	local newState: State = {
		night = nextNight,
		stash = state.stash + gained,
		best = best,
		carried = {},
	}
	local result: Result = {
		outcome = outcome,
		gained = gained,
		lost = total - gained,
		night = state.night,
		nextNight = nextNight,
		newBest = best > state.best,
	}
	return newState, result
end

return Night
