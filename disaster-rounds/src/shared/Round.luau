--!strict
-- Round.luau - the server's phase clock (DESIGN.md §2.1). Pure: the server passes in its own clock (tick()) and
-- two counts it measures; this module says which phase comes next. One clock for the whole server: a player's
-- break never pauses it (DESIGN.md §5).
--
--   intermission (20 s, on the Lookout) -> drop (4 s, on the new island) -> disaster (60 s) -> outro (4 s) -> ...
--
--   * the roster freezes at the drop: an intermission that ends with nobody eligible repeats ("idle");
--   * the disaster ends early the moment nobody (counted or practice) is left on the island ("empty");
--   * a practice drop-in is allowed from the drop until PracticeUntilSeconds into the disaster.

local Round = {}

local ORDER = { intermission = "drop", drop = "disaster", disaster = "outro", outro = "intermission" }

function Round.duration(cfg: any, phase: string): number
	if phase == "intermission" then return cfg.IntermissionSeconds end
	if phase == "drop" then return cfg.DropSeconds end
	if phase == "disaster" then return cfg.DisasterSeconds end
	if phase == "outro" then return cfg.OutroSeconds end
	error("Round.duration: unknown phase " .. tostring(phase))
end

function Round.cycleSeconds(cfg: any): number
	return cfg.IntermissionSeconds + cfg.DropSeconds + cfg.DisasterSeconds + cfg.OutroSeconds
end

function Round.new(cfg: any, now: number): any
	return { phase = "intermission", started = now, ends = now + cfg.IntermissionSeconds, roundId = 0 }
end

local function enter(s: any, cfg: any, phase: string, now: number)
	s.phase = phase
	s.started = now
	s.ends = now + Round.duration(cfg, phase)
end

-- One tick. ctx = { eligible = players who would make the roster now, onIsland = players still on the island }.
-- Returns nil or the event that just happened: "drop" | "idle" | "name" | "survive" | "empty" | "return".
function Round.step(s: any, cfg: any, now: number, ctx: any): string?
	if s.phase == "disaster" and (ctx.onIsland or 0) <= 0 and now < s.ends then
		enter(s, cfg, "intermission", now)
		return "empty"
	end
	if now < s.ends then return nil end
	if s.phase == "intermission" then
		if (ctx.eligible or 0) <= 0 then
			enter(s, cfg, "intermission", now)
			return "idle"
		end
		s.roundId += 1
		enter(s, cfg, "drop", now)
		return "drop"
	end
	local nextPhase = ORDER[s.phase]
	local event = if s.phase == "drop" then "name" elseif s.phase == "disaster" then "survive" else "return"
	enter(s, cfg, nextPhase, now)
	return event
end

function Round.timeLeft(s: any, now: number): number
	return math.max(0, s.ends - now)
end

function Round.disasterElapsed(s: any, now: number): number
	if s.phase ~= "disaster" then return 0 end
	return now - s.started
end

-- Seconds until the next drop begins.
function Round.secondsToNextDrop(cfg: any, s: any, now: number): number
	local left = Round.timeLeft(s, now)
	if s.phase == "intermission" then return left end
	local phase = ORDER[s.phase]
	while phase ~= "drop" do
		left += Round.duration(cfg, phase)
		phase = ORDER[phase]
	end
	return left
end

-- (ok, code). who = { inRound = "" | "counted" | "practice", swept = boolean, resting = boolean }.
function Round.jumpInCheck(cfg: any, s: any, now: number, who: any): (boolean, string?)
	if who.resting then return false, "resting" end
	if who.inRound ~= nil and who.inRound ~= "" then return false, "island" end
	if s.phase == "intermission" then return false, "next" end
	if s.phase == "outro" then return false, "late" end
	if who.swept then return false, "swept" end
	if s.phase == "disaster" and now - s.started >= cfg.PracticeUntilSeconds then return false, "late" end
	return true, nil
end

-- "m:ss", rounding a partial second up and never below 0:00.
function Round.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds - 1e-9))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- What the player is told when a request is refused (DESIGN.md §12.3: no silent no-ops).
function Round.refusalText(code: string, secondsToNext: number): string
	local nextIn = Round.clock(secondsToNext)
	if code == "next" then return "You're in the next round — it starts in " .. nextIn .. "." end
	if code == "late" then return "Too late to jump in — next round in " .. nextIn .. "." end
	if code == "island" then return "You're already on the island." end
	if code == "swept" then return "You were swept away this round — next round in " .. nextIn .. "." end
	if code == "resting" then return "You're on a break — tap ☕ to come back." end
	if code == "rate" then return "One tap is enough." end
	if code == "nospot" then return "No safe spot to land right now — try again in a second." end
	return "Can't do that right now."
end

-- The next disaster: an even draw from every kind, every round, owing nothing to the rounds before it. `force`
-- (Config.Shots.ForceKind, nil in src/) wins when it names a real kind; anything else is ignored.
-- REVIEW-1 F4: the first build never repeated the last disaster. The last disaster is public (Kind replicates during
-- the round) and a break pressed in the intermission chooses which rounds you play, so a player who rested except
-- after a flood never met a flood. With an even draw, nothing a client has seen says anything about the next round.
function Round.pickKind(kinds: { string }, rand: () -> number, force: string?): string
	if force ~= nil then
		for _, k in kinds do
			if k == force then return k end
		end
	end
	return kinds[math.min(#kinds, 1 + math.floor(rand() * #kinds))]
end

return Round
