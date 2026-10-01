--!strict
-- Weather.luau — the global weather clock (DESIGN.md §2.1). Pure: no Roblox, no requires.
--
-- Time is Unix seconds (fractional allowed). An event of kind k runs while (t - from) % every lies in
-- [0, len). Because the schedule depends only on t, every server shows the same weather at the same
-- second, and so does every client: the server publishes its clock (workspace ServerNow) and the HUD,
-- the sky and the strike loop all ask this module.
--
-- W is Config.Weather: { Events = { [kind] = { from, len, every } }, Kinds = { ... }, TickSeconds,
-- Chance = { [kind] = P }, FadeSeconds }.

local Weather = {}

local function inWindow(t: number, e: any): (boolean, number)
	local phase = (t - e.from) % e.every
	if phase < e.len then
		return true, t - phase
	end
	return false, 0
end

-- (ok, err). The schedule must never overlap and every event must be a whole number of strike ticks.
function Weather.validate(W: any): (boolean, string?)
	if type(W) ~= "table" or type(W.Events) ~= "table" or type(W.Kinds) ~= "table" then
		return false, "no weather config"
	end
	if type(W.TickSeconds) ~= "number" or W.TickSeconds <= 0 then
		return false, "TickSeconds must be > 0"
	end
	local period = 1
	for _, kind in W.Kinds do
		local e = W.Events[kind]
		if e == nil then return false, "no event " .. tostring(kind) end
		if e.len <= 0 or e.len > e.every then return false, kind .. ": len must be within (0, every]" end
		if e.len % W.TickSeconds ~= 0 or e.from % W.TickSeconds ~= 0 then
			return false, kind .. ": len and from must be whole strike ticks"
		end
		local p = W.Chance and W.Chance[kind]
		if type(p) ~= "number" or p < 0 or p > 1 then return false, kind .. ": chance must be within 0..1" end
		-- least common multiple of the periods, so the overlap scan below covers every phase
		local a, b = period, e.every
		while b ~= 0 do a, b = b, a % b end
		period = period // a * e.every
	end
	for t = 0, period - 1, W.TickSeconds do
		local n = 0
		for _, kind in W.Kinds do
			if (inWindow(t, W.Events[kind])) then n += 1 end
		end
		if n > 1 then return false, "two events overlap at phase " .. t end
	end
	return true, nil
end

-- (kind, startedAt, endsAt) for second t; kind "clear" has no window (0, 0).
function Weather.at(t: number, W: any): (string, number, number)
	for _, kind in W.Kinds do
		local e = W.Events[kind]
		local ok, start = inWindow(t, e)
		if ok then
			return kind, start, start + e.len
		end
	end
	return "clear", 0, 0
end

-- (kind, startsAt) of the first event starting STRICTLY after t.
function Weather.nextEvent(t: number, W: any): (string, number)
	local best, bestAt = "clear", math.huge
	for _, kind in W.Kinds do
		local e = W.Events[kind]
		local n = math.floor((t - e.from) / e.every) + 1
		local s = e.from + n * e.every
		if s <= t then s += e.every end
		if s < bestAt then
			best, bestAt = kind, s
		end
	end
	return best, bestAt
end

-- The running event (if any) and every event starting within `horizon` seconds after t, in order:
-- { { kind, from, to } }.
function Weather.timeline(t: number, W: any, horizon: number): { any }
	local out = {}
	local k, from, to = Weather.at(t, W)
	if k ~= "clear" then
		table.insert(out, { kind = k, from = from, to = to })
	end
	local cursor = t
	while true do
		local nk, ns = Weather.nextEvent(cursor, W)
		if ns > t + horizon then break end
		table.insert(out, { kind = nk, from = ns, to = ns + W.Events[nk].len })
		cursor = ns
	end
	return out
end

function Weather.ticks(kind: string, W: any): number
	return W.Events[kind].len / W.TickSeconds
end

-- Per-tick chance q, so that a crop ripe for all of an event's ticks gets exactly its chance P:
-- 1 - (1 - q)^ticks = P.
function Weather.perTick(kind: string, W: any): number
	local P = W.Chance[kind]
	if P >= 1 then return 1 end
	return 1 - (1 - P) ^ (1 / Weather.ticks(kind, W))
end

-- The event kind when t is a strike tick (a whole multiple of TickSeconds inside an event), else nil.
function Weather.isTick(t: number, W: any): string?
	if t % W.TickSeconds ~= 0 then return nil end
	local k = Weather.at(t, W)
	if k == "clear" then return nil end
	return k
end

-- (first, last) strike tick of the event of `kind` that starts at `start`.
function Weather.tickWindow(kind: string, start: number, W: any): (number, number)
	return start, start + W.Events[kind].len - W.TickSeconds
end

-- (kind, w): the running event and its overlay weight, 0 -> 1 over FadeSeconds after the start and
-- 1 -> 0 over FadeSeconds before the end. Clear weather is ("clear", 0).
function Weather.weight(t: number, W: any): (string, number)
	local k, from, to = Weather.at(t, W)
	if k == "clear" then return "clear", 0 end
	local fade = W.FadeSeconds or 0
	if fade <= 0 then return k, 1 end
	return k, math.clamp(math.min(t - from, to - t) / fade, 0, 1)
end

-- (kind, startsAt) of the first event a seed planted at `now` will be ripe for: the first event (the
-- running one included) whose LAST strike tick comes at or after the crop ripens (now + grow).
function Weather.catchesEvent(now: number, grow: number, W: any): (string, number)
	local ripe = now + grow
	local k, from = Weather.at(now, W)
	if k ~= "clear" then
		local _, last = Weather.tickWindow(k, from, W)
		if last >= ripe then return k, from end
	end
	local cursor = now
	for _ = 1, 64 do
		local nk, ns = Weather.nextEvent(cursor, W)
		local _, last = Weather.tickWindow(nk, ns, W)
		if last >= ripe then return nk, ns end
		cursor = ns
	end
	return "clear", 0
end

-- ":20" for an event that starts on a whole minute, ":01:30" otherwise (minutes past the hour).
function Weather.minuteLabel(t: number, _W: any?): string
	local s = math.floor(t) % 3600
	local m, sec = s // 60, s % 60
	if sec == 0 then return string.format(":%02d", m) end
	return string.format(":%02d:%02d", m, sec)
end

return Weather
