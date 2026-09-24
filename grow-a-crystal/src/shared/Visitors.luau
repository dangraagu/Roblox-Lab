--!strict
-- Visitors.luau — the rare, HARMLESS ambient events of the cavern (a moth swirl, a bat swoop). Pure.
--
-- Grow a Crystal has no knock-down hazards: it is an idle game with no failure state, and a hazard
-- could only interrupt a player who is waiting for crystals to grow (EYECANDY.md §3). What it keeps
-- from +1 Jump's Hazards scheduler is the CLOCK, because "something rare happens now and then" is
-- what stops a waiting game feeling monotonous:
--   * one visitor every IntervalMin..IntervalMax seconds of PLAY, never two at once;
--   * the clock counts only while the player is not resting and nothing is in flight. Resting
--     FREEZES it and never resets it, so toggling rest cannot change how many visitors an hour of
--     play brings;
--   * a visitor already in flight finishes during rest: rest never deletes something on screen;
--   * a visitor that falls due in a band with no visitor kinds is re-rolled, so a band that opens
--     later does not release a stored-up backlog.
--
-- A visitor never touches the character, never collides and never grants or removes anything; the
-- client just flies a few pooled parts along a route (Grotto.routePoint). Randomness is an injected
-- rand(): [0, 1), so this runs in the luau CLI. It requires nothing.

local Visitors = {}

function Visitors.validate(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no visitor config" end
	if type(cfg.IntervalMin) ~= "number" or cfg.IntervalMin <= 0 then
		return false, "IntervalMin must be > 0"
	end
	if type(cfg.IntervalMax) ~= "number" or cfg.IntervalMax < cfg.IntervalMin then
		return false, "IntervalMax must be >= IntervalMin"
	end
	if type(cfg.Kinds) ~= "table" then return false, "no Kinds" end
	for kind, k in cfg.Kinds do
		if type(k) ~= "table" or type(k.seconds) ~= "number" or k.seconds <= 0 then
			return false, "visitor " .. tostring(kind) .. " needs seconds > 0"
		end
		if k.seconds >= cfg.IntervalMin then
			return false, "visitor " .. tostring(kind) .. " lasts longer than IntervalMin"
		end
	end
	return true, nil
end

local function interval(cfg: any, rand: () -> number): number
	return cfg.IntervalMin + (cfg.IntervalMax - cfg.IntervalMin) * rand()
end

function Visitors.newClock(cfg: any, rand: () -> number): any
	return { dueIn = interval(cfg, rand), active = nil, launched = 0 }
end

-- ctx = { resting: boolean, kinds: { string } } (the kinds the player's current band allows).
-- Returns nil, { type = "launch", kind, seconds, id } or { type = "done", kind, id }.
function Visitors.step(clock: any, cfg: any, dt: number, ctx: any, rand: () -> number): any
	-- The clock measures play time from one LAUNCH to the next, so it keeps counting while a visitor
	-- flies (IntervalMin > the longest flight, so it can never come due mid-flight). Counting only
	-- between flights made rest worth ~2 % more visitors per hour of play: a flight that ended during
	-- a rest cost no play time (the spec's toggle probe measured 471 against 461).
	if not ctx.resting then
		clock.dueIn -= dt -- frozen while resting, never reset
	end
	local a = clock.active
	if a then
		-- in flight: always finishes on its own time, resting or not
		a.t += dt
		if a.t >= a.seconds - 1e-9 then
			clock.active = nil
			return { type = "done", kind = a.kind, id = a.id }
		end
		return nil
	end
	if ctx.resting or clock.dueIn > 0 then
		return nil
	end
	local kinds = ctx.kinds or {}
	if #kinds == 0 then
		-- a quiet band: re-roll instead of storing the visitor up for the next band
		clock.dueIn = interval(cfg, rand)
		return nil
	end
	local kind = kinds[math.min(#kinds, 1 + math.floor(rand() * #kinds))]
	local spec = cfg.Kinds[kind]
	if spec == nil then
		clock.dueIn = interval(cfg, rand)
		return nil
	end
	clock.launched += 1
	clock.active = { kind = kind, t = 0, seconds = spec.seconds, id = clock.launched }
	clock.dueIn = interval(cfg, rand)
	return { type = "launch", kind = kind, seconds = spec.seconds, id = clock.launched }
end

return Visitors
