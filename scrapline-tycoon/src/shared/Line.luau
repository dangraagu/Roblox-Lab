--!strict
-- Line.luau — the production line's steady flow. PURE: cfg + plain tables in, numbers out.
--
-- DESIGN.md section 4.2. Junk pours out of the chute and rides past six stations in belt order to the dock,
-- which sells whatever arrives. Station t turns state t-1 into state t; it handles only so many items a
-- second (its CAPACITY: working machines x BaseSpeed x SpeedGrowth^(level - 1)), and whatever it cannot
-- take rides past unchanged and sells as what it already is. The chute feeds the Shredder exactly as fast
-- as it can shred, never below the trickle (so a jammed Shredder still lets 0.5 junk/s through).
--
--   intake  = ChuteTrickle before the Shredder exists, else max(ChuteTrickle, Shredder capacity)
--   r[1] = intake (junk); for t = 1..6: moved = min(r[t], cap(t)); r[t] -= moved; r[t+1] += moved
--   income  = sum r[s] x Values[s] x multiplier
--
-- A station state is { n = machines built 0..2, L = level, jam = { a, b } } with jam 0 = running,
-- 1 = sputtering (STILL WORKING), 2 = jammed (not working). Product arrays are indexed state + 1 (junk = 1).
-- The server computes income from this every tick; the HUD and the clients draw from it; tests/LineModel
-- plays it. Requires nothing (a bare require("./X") is invalid in Roblox). Spec: tests/Line.spec.luau.

local Line = {}

function Line.speed(cfg: any, t: number, L: number): number
	local S = cfg.Stations
	return S.BaseSpeed[t] * S.SpeedGrowth ^ (L - 1)
end

-- Working machines at station state `st`: jammed ones do not count unless ignoreJams.
function Line.working(st: any, ignoreJams: boolean?): number
	local w = 0
	for i = 1, math.min(st.n, 2) do
		if ignoreJams or st.jam == nil or st.jam[i] ~= 2 then w += 1 end
	end
	return w
end

function Line.capacity(cfg: any, st: any, t: number, ignoreJams: boolean?): number
	return Line.working(st, ignoreJams) * Line.speed(cfg, t, st.L)
end

-- Junk per second the chute puts on the belt.
function Line.intake(cfg: any, S: { any }, ignoreJams: boolean?): number
	local trickle = cfg.Line.ChuteTrickle
	if S[1].n == 0 then return trickle end
	return math.max(trickle, Line.capacity(cfg, S[1], 1, ignoreJams))
end

-- Items per second leaving the dock in each state: an array of 7 (index = state + 1).
function Line.flow(cfg: any, S: { any }, ignoreJams: boolean?): { number }
	local r = { Line.intake(cfg, S, ignoreJams), 0, 0, 0, 0, 0, 0 }
	for t = 1, 6 do
		local moved = math.min(r[t], Line.capacity(cfg, S[t], t, ignoreJams))
		r[t] -= moved
		r[t + 1] += moved
	end
	return r
end

-- What reaches each station (items/s in the state it takes) and what it can take, jams counted.
function Line.reach(cfg: any, S: { any }, ignoreJams: boolean?): ({ number }, { number })
	local r = { Line.intake(cfg, S, ignoreJams), 0, 0, 0, 0, 0, 0 }
	local reach, cap = {}, {}
	for t = 1, 6 do
		reach[t] = r[t]
		cap[t] = Line.capacity(cfg, S[t], t, ignoreJams)
		local moved = math.min(r[t], cap[t])
		r[t] -= moved
		r[t + 1] += moved
	end
	return reach, cap
end

-- Each built station's load (what reaches it / what it can take, jams counted). Above 1 means items ride past
-- unchanged; math.huge for a station whose every machine is jammed. 0 for an unbuilt station.
function Line.loads(cfg: any, S: { any }): { number }
	local reach, cap = Line.reach(cfg, S)
	local out = {}
	for t = 1, 6 do
		if S[t].n == 0 then
			out[t] = 0
		elseif cap[t] <= 0 then
			out[t] = math.huge
		else
			out[t] = reach[t] / cap[t]
		end
	end
	return out
end

function Line.mult(cfg: any, bolts: number): number
	return 1 + cfg.Recycle.BoltValue * bolts
end

-- (income per second, flow) at value multiplier `mult`.
function Line.income(cfg: any, S: { any }, mult: number, ignoreJams: boolean?): (number, { number })
	local r = Line.flow(cfg, S, ignoreJams)
	local v = cfg.Products.Values
	local sum = 0
	for s = 1, 7 do
		sum += r[s] * v[s]
	end
	return sum * mult, r
end

-- The built station whose capacity is lowest against what reaches it, jams IGNORED (it names the slowest
-- station, not a broken one; ties go to the earlier station). Returns (t, ratio) or nil.
function Line.bottleneck(cfg: any, S: { any }): (number?, number)
	local r = Line.intake(cfg, S, true)
	local worst, worstRatio = nil, math.huge
	for t = 1, 6 do
		local st = S[t]
		if st.n == 0 then break end
		local cap = Line.capacity(cfg, st, t, true)
		local ratio = cap / math.max(r, 1e-9)
		if ratio < worstRatio - 1e-12 then
			worst, worstRatio = t, ratio
		end
		r = math.min(r, cap)
	end
	return worst, worstRatio
end

-- The persisted map { [stationId] = state } in belt order (the same tables, not copies).
function Line.ordered(cfg: any, stations: { [string]: any }): { any }
	local out = {}
	for t, id in cfg.Stations.Order do
		out[t] = stations[id]
	end
	return out
end

function Line.indexOf(cfg: any, id: any): number?
	if type(id) ~= "string" then return nil end
	for t, sid in cfg.Stations.Order do
		if sid == id then return t end
	end
	return nil
end

return Line
