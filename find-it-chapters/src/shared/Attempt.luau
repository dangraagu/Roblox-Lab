--!strict
-- Attempt.luau: one attempt's state machine, run by the server from its own memory (DESIGN.md §3.4-3.7, §9).
-- Pure: no Roblox, no clock of its own. The server calls `tick(a, dt)` from Heartbeat with the frame's dt, so
-- the attempt clock is the sum of live, unpaused frame time (never os.clock, which barely moves headless).
--
-- The secret is `a.hidden[i]`, the prop id hiding item i, drawn by `hide` uniformly among clue i's candidates
-- AFTER the room's payload was built. It never leaves this table except in a hit's Result (after the find) or
-- a hint (the player spent the hint on exactly that).
--
-- States: intro -> live <-> paused -> done. Refusal reasons (the server turns each into words, nothing is
-- silent): intro, pending, paused, time, looks, break, done, unknown, already, pick, used, found. A break longer
-- than Pause.MaxBreakSeconds in all closes the room (reason "break", REVIEW-1 round 2 C2).

local Attempt = {}

local function matches(p: any, clue: any, cfg: any): boolean
	for _, a in cfg.Forms[clue.form] do
		if p[a] ~= clue[a] then return false end
	end
	return true
end

local function pick(rand: () -> number, n: number): number
	local v = math.floor(rand() * n) + 1
	if v > n then v = n elseif v < 1 then v = 1 end
	return v
end

local function index(room: any): { [number]: any }
	local byId = {}
	for _, p in room.props do byId[p.id] = p end
	return byId
end

-- opts = { intro = seconds of the intro card }
function Attempt.new(room: any, spec: any, cfg: any, opts: any?): any
	local o = opts or {}
	return {
		spec = spec, cfg = cfg, room = room, byId = index(room),
		n = spec.n, limit = spec.clock, looks = spec.looks,
		state = if (o.intro or 0) > 0 then "intro" else "live",
		introLeft = o.intro or 0,
		clock = 0,
		found = {}, foundAt = {},
		searched = {}, -- prop id -> true (this room's ids only)
		off = 0,
		hint = nil :: number?, hintProp = nil :: number?,
		pending = nil :: any,
		pausedAt = nil :: number?, pauseQueued = false,
		hidden = {} :: { number },
		reason = nil :: string?, finishClock = nil :: number?,
		searches = 0,
	}
end

-- The secret: one candidate per unfound item, uniformly. `rand` is the server's draw (life xor fresh).
function Attempt.hide(a: any, rand: () -> number)
	for i = 1, a.n do
		if not a.found[i] then
			local c = a.room.cands[i]
			a.hidden[i] = c[pick(rand, #c)]
		end
	end
end

-- The clue index a prop fits among items still unfound, or nil.
function Attempt.fitsNeeded(a: any, prop: any): number?
	for i, c in a.room.clues do
		if not a.found[i] and matches(prop, c, a.cfg) then return i end
	end
	return nil
end

local function finish(a: any, reason: string, events: { any })
	a.state = "done"
	a.reason = reason
	a.finishClock = a.clock
	a.pending = nil
	table.insert(events, { type = "end", reason = reason })
end

local function allFound(a: any): boolean
	for i = 1, a.n do
		if not a.found[i] then return false end
	end
	return true
end

local function resolve(a: any, events: { any })
	local pend = a.pending
	a.pending = nil
	local id = pend.id
	a.searched[id] = true
	local item = nil
	for i = 1, a.n do
		if not a.found[i] and a.hidden[i] == id then item = i end
	end
	if item then
		a.found[item] = true
		a.foundAt[item] = a.clock
	end
	table.insert(events, { type = "result", id = id, hit = item ~= nil, item = item, offClue = pend.offClue, after = pend.after })
	if allFound(a) then
		finish(a, "found", events)
	elseif a.looks <= 0 then
		finish(a, "looks", events)
	elseif a.pauseQueued then
		a.pauseQueued = false
		a.state = "paused"
		a.pausedAt = a.pauseAtQueue
		table.insert(events, { type = "paused" })
	end
end

-- Advance by dt seconds of server frame time. Returns the events that happened, in order.
function Attempt.tick(a: any, dt: number): { any }
	local events = {}
	if a.state == "done" or a.state == "paused" then return events end
	if a.state == "intro" then
		a.introLeft -= dt
		if a.introLeft > 1e-9 then return events end
		dt = -a.introLeft
		a.introLeft = 0
		a.state = "live"
		table.insert(events, { type = "live" })
	end
	if dt <= 0 then return events end
	local pend = a.pending
	if pend then
		local toAnswer = pend.left
		local toEnd = a.limit - a.clock
		if toAnswer <= dt + 1e-9 and toAnswer <= toEnd + 1e-9 then
			-- the answer lands inside this frame and inside the clock
			a.clock += toAnswer
			pend.after += toAnswer
			pend.after = math.floor(pend.after * 1e6 + 0.5) / 1e6
			resolve(a, events)
			if a.state ~= "live" then return events end
			dt -= toAnswer
		else
			pend.left -= dt
			pend.after += dt
		end
	end
	a.clock += dt
	if a.clock >= a.limit - 1e-9 and a.state == "live" then
		a.clock = a.limit
		finish(a, "time", events)
	end
	return events
end

-- (ok, reason). A started search spends one look now; its answer comes Search.Seconds later.
function Attempt.search(a: any, id: any): (boolean, string?)
	if a.state == "done" then return false, if a.reason == "found" then "done" else a.reason end
	if a.state == "intro" then return false, "intro" end
	if a.state == "paused" then return false, "paused" end
	if a.pending then return false, "pending" end
	local prop = a.byId[id]
	if prop == nil then return false, "unknown" end
	if a.searched[id] then return false, "already" end
	if a.looks <= 0 then return false, "looks" end
	a.looks -= 1
	a.searches += 1
	local offClue = Attempt.fitsNeeded(a, prop) == nil
	if offClue then a.off += 1 end
	a.pending = { id = id, left = a.cfg.Search.Seconds, after = 0, offClue = offClue }
	return true, nil
end

-- (propId, nil) or (nil, reason). One per attempt.
function Attempt.hint(a: any, item: any): (number?, string?)
	if a.state == "done" then return nil, "done" end
	if a.state == "intro" then return nil, "intro" end
	if a.state == "paused" then return nil, "paused" end
	if a.hint ~= nil then return nil, "used" end
	if type(item) ~= "number" or item ~= item or item < 1 or item > a.n or item % 1 ~= 0 then return nil, "pick" end
	if a.found[item] then return nil, "found" end
	a.hint = item
	a.hintProp = a.hidden[item]
	return a.hintProp, nil
end

-- Seconds of attempt clock until a pause is accepted again: 0 before the first re-dress, then EverySeconds after
-- each one (REVIEW-1 A4: a resume re-deals the unfound part of the room, so back-to-back pauses were a free re-roll).
function Attempt.pauseIn(a: any): number
	if a.redressClock == nil then return 0 end
	return math.max(0, a.redressClock + (a.cfg.Pause.EverySeconds or 0) - a.clock)
end

-- "paused" | "queued" (a search is in flight: the pause follows its answer) | a refusal reason ("soon": the
-- last re-dress was less than Pause.EverySeconds of clock ago)
function Attempt.pause(a: any, now: number): string
	if a.state == "done" then return "done" end
	if a.state == "intro" then return "intro" end
	if a.state == "paused" then return "already" end
	if Attempt.pauseIn(a) > 1e-9 then return "soon" end
	if a.pending then
		a.pauseQueued = true
		a.pauseAtQueue = now
		return "queued"
	end
	a.state = "paused"
	a.pausedAt = now
	return "paused"
end

-- The candidate count each item keeps through a re-dress: unsearched candidates of its clue; 1 for a hinted
-- unfound item (its hint names the one prop); 0 when found.
function Attempt.counts(a: any): { number }
	local out = {}
	for i = 1, a.n do
		if a.found[i] then
			out[i] = 0
		elseif a.hint == i then
			out[i] = 1
		else
			local c = 0
			for _, id in a.room.cands[i] do
				if not a.searched[id] then c += 1 end
			end
			out[i] = c
		end
	end
	return out
end

-- "wait" (before ResumeMinSeconds) | "redress", counts | a refusal reason. The caller builds the new room
-- with Dressing.redress(a.room, counts, ...) and hands it to applyRedress.
function Attempt.resume(a: any, now: number): (string, { number }?)
	if a.state ~= "paused" then
		if a.pauseQueued then
			a.pauseQueued = false
			return "cancelled", nil
		end
		return "notpaused", nil
	end
	if now - (a.pausedAt or now) < a.cfg.Pause.ResumeMinSeconds - 1e-9 then return "wait", nil end
	a.breakUsed = (a.breakUsed or 0) + math.max(0, now - (a.pausedAt or now))
	return "redress", Attempt.counts(a)
end

-- REVIEW-1 round 2 C2: the break is capped. Seconds of break left (paused time summed over the attempt, on the
-- caller's clock: the server's frame clock), and the close at the cap: "done" with reason "break", nothing earned.
-- An unbounded Pause let a Daily opened at 23:58 be solved the next morning on its start day's credit.
function Attempt.breakLeft(a: any, now: number): number
	local used = a.breakUsed or 0
	if a.state == "paused" then used += math.max(0, now - (a.pausedAt or now)) end
	return math.max(0, (a.cfg.Pause.MaxBreakSeconds or math.huge) - used)
end

function Attempt.closeBreak(a: any, now: number): { any }
	local events = {}
	if a.state == "paused" and Attempt.breakLeft(a, now) <= 1e-9 then
		a.pauseQueued = false
		finish(a, "break", events)
	end
	return events
end

function Attempt.applyRedress(a: any, room: any, rand: () -> number)
	a.room = room
	a.byId = index(room)
	a.searched = {}
	a.hidden = {}
	Attempt.hide(a, rand)
	if a.hint ~= nil and not a.found[a.hint] then
		a.hintProp = a.hidden[a.hint]
	else
		a.hintProp = nil
	end
	a.state = "live"
	a.pausedAt = nil
	a.redressClock = a.clock
end

function Attempt.abandon(a: any)
	if a.state ~= "done" then
		a.state = "done"
		a.reason = "abandon"
		a.finishClock = a.clock
		a.pending = nil
	end
end

function Attempt.stars(a: any): any
	local found = a.state == "done" and a.reason == "found"
	local cfg = a.cfg
	local f = found
	return {
		f = f,
		w = f and (a.finishClock or a.clock) <= cfg.Search.SwiftFraction * a.limit + 1e-9,
		s = f and a.off <= cfg.Search.SharpSlips and a.hint == nil,
	}
end

function Attempt.foundCount(a: any): number
	local c = 0
	for i = 1, a.n do if a.found[i] then c += 1 end end
	return c
end

-- The state the owner's HUD may see: nothing about unsearched props. `now` (the server's frame clock) adds the
-- break left while paused (REVIEW-1 round 2 C2: the paused card counts it down).
function Attempt.public(a: any, now: number?): any
	local found = {}
	for i = 1, a.n do found[i] = a.found[i] == true end
	return {
		state = a.state, reason = a.reason, clock = a.clock, limit = a.limit, looks = a.looks, found = found,
		hintUsed = a.hint ~= nil, searching = a.pending ~= nil, pauseQueued = a.pauseQueued == true,
		pauseIn = Attempt.pauseIn(a),
		breakLeft = if a.state == "paused" and now ~= nil then Attempt.breakLeft(a, now) else nil,
	}
end

-- The server-only copy (ServerStorage rig): the secret and the counters.
function Attempt.snapshot(a: any): any
	local hidden = {}
	for i = 1, a.n do hidden[i] = a.hidden[i] end
	local cands = {}
	for i, c in a.room.cands do cands[i] = table.clone(c) end
	return { hidden = hidden, cands = cands, looks = a.looks, clock = a.clock, state = a.state, off = a.off, hint = a.hint, idBase = a.room.idBase }
end

return Attempt
