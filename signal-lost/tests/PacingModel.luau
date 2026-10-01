--!nocheck
-- PacingModel.luau — TEST-ONLY. DESIGN.md's campaign model (design-measure/station.luau S.run / S.campaign), ported
-- onto the REAL game: every sector is the real src/shared/Station.luau plan, every number comes from the real
-- Config, the pay from the real Economy. Used by tests/Pacing.spec.luau (the brag's minutes) and tests/m1_real.luau.
--
-- What it models (DESIGN.md §0): a careful explorer that walks each sector blind, remembers every module it has
-- seen, knows air or vacuum behind every hatch it has seen (the hatch lamp), keeps exact track of its air, retreats
-- to air when a step would leave it unable to get back, and uses the signal meter when it is in range. Human play
-- is stood in for by three PROFILES (speed factor, share of decisions that ignore the meter, share that skip the
-- air check, safety margin). They are proxies, not measured people: the model's blackouts are a floor.
-- Not modelled: hazards' time cost, the hop as physics, collision, replication, the trust throttle, the lifeboat.
local Config = require("../src/shared/Config")
local MazeGen = require("../src/shared/MazeGen")
local Station = require("../src/shared/Station")
local Economy = require("../src/shared/Economy")
local Streams = require("./Streams")

local M = {}

-- The model's own constants (not game numbers): the rig's, DESIGN.md §0 and §8.3.
M.SALVAGE_DETOUR = 1.2 -- seconds to take a salvage piece (some float: a low-g hop)
M.CANISTER_DETOUR = 0.9
M.OVERHEAD = { start = 5, transit = 3, blackout = 4.5, buy = 4 }

M.PROFILES = {
	fast = { speed = 1.0, pNearest = 0.0, pErr = 0.02, margin = 2 },
	medium = { speed = 0.8, pNearest = 0.3, pErr = 0.05, margin = 3 },
	slow = { speed = 0.65, pNearest = 0.6, pErr = 0.10, margin = 4 },
}

function M.bandOf(k)
	local idx = 1
	for i, b in Config.Env.Bands do
		if k >= b.first then idx = i end
	end
	return idx
end

function M.plan(k, seeds)
	local p = Station.plan(Config, k, Streams.fromSeeds(seeds), MazeGen)
	-- the explorer reads the rig's field names
	local item = {}
	for m, it in p.items do item[m] = it.kind end
	p.entry = p.dock
	p.item = item
	return p
end

local function xy(p, i) return (i - 1) % p.n, (i - 1) // p.n end
local function straight(p, a, b)
	local ax, ay = xy(p, a)
	local bx, by = xy(p, b)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- One sector attempt. prof = a profile, up = { tank, boots } ranks, rand: () -> [0, 1).
function M.run(p, prof, up, rand)
	local St, Mv, Ai = Config.Station, Config.Move, Config.Air
	local fx = Economy.effects(Config, up)
	local tank = fx.tank
	local vAir = Mv.AirWalkSpeed * prof.speed
	local vVac = fx.vacSpeed * prof.speed
	local range = Config.Signal.MaxBars - 1 -- the meter is informative within 4 modules (§2.4)
	local half = { air = St.CellSize / 2 / vAir, vac = St.CellSize / 2 / vVac }
	local rate = tank / Ai.RefillSeconds
	local grace = Ai.GraceSeconds
	local lowO2, arrival = Config.Hazards.LowO2Seconds, Config.Hazards.ArrivalGraceSeconds

	local pos = p.entry
	local visited = { [p.entry] = true }
	local nVisited = 1
	local O2 = tank
	local hyp = 0
	local t, vacT, airT = 0, 0, 0
	local carried = 0
	local dead = false
	local minO2 = tank
	local firstSalvT = nil
	local retreats, gambles = 0, 0
	local firstVacT = nil
	local eligible = 0
	local signalSeen = {}

	local function halfT(c) return if p.vac[c] then half.vac else half.air end

	local function spend(c, dur)
		if dead or dur <= 0 then return end
		t += dur
		if p.vac[c] then
			if not firstVacT then firstVacT = t - dur end
			vacT += dur
			local from = math.max(t - dur, arrival)
			local span = math.max(0, t - from)
			eligible += math.max(0, math.min(span, O2 - lowO2))
			O2 -= dur
			if O2 < 0 then
				hyp += -O2
				O2 = 0
				if hyp >= grace then dead = true end
			end
			minO2 = math.min(minO2, O2)
		else
			airT += dur
			hyp = 0
			O2 = math.min(tank, O2 + rate * dur)
		end
	end

	local function enter(c)
		if visited[c] then return end
		visited[c] = true
		nVisited += 1
		local it = p.item[c]
		if it == "salvage" then
			spend(c, M.SALVAGE_DETOUR)
			carried += 1
			if not firstSalvT then firstSalvT = t end
		elseif it == "canister" then
			if O2 < tank or hyp > 0 then
				spend(c, M.CANISTER_DETOUR)
				hyp = 0
				O2 = math.min(tank, O2 + Ai.CanisterSeconds)
			end
		end
		if straight(p, c, p.relay) <= range then signalSeen[c] = true end
	end
	enter(p.entry)
	if straight(p, p.entry, p.relay) <= range then signalSeen[p.entry] = true end

	local function move(a, b)
		spend(a, halfT(a))
		if not visited[b] then spend(b, St.HatchSeconds) end
		spend(b, halfT(b))
		pos = b
		enter(b)
	end

	local function known()
		local dist, par, done = { [pos] = 0 }, {}, {}
		while true do
			local best, bd = nil, math.huge
			for c, dc in dist do if not done[c] and dc < bd then best = c; bd = dc end end
			if not best then break end
			done[best] = true
			for _, b in p.adj[best] do
				if visited[b] then
					local nd = bd + halfT(best) + halfT(b)
					if dist[b] == nil or nd < dist[b] then dist[b] = nd; par[b] = best end
				end
			end
		end
		return dist, par
	end
	local function pathTo(par, target)
		local path, c = {}, target
		while c ~= pos do table.insert(path, 1, c); c = par[c] end
		return path
	end
	local function simO2(path, startO2)
		local o, a = startO2, pos
		local lowest = startO2
		for _, b in path do
			for _, seg in { { a, halfT(a) }, { b, (if visited[b] then 0 else St.HatchSeconds) + halfT(b) } } do
				local c, dur = seg[1], seg[2]
				if p.vac[c] then o -= dur; lowest = math.min(lowest, o)
				else o = math.min(tank, o + rate * dur) end
			end
			a = b
		end
		return o, lowest
	end
	local function returnCost(f)
		if not p.vac[f] then return 0 end
		local dist, done = { [f] = 0 }, {}
		while true do
			local best, bd = nil, math.huge
			for c, dc in dist do if not done[c] and dc < bd then best = c; bd = dc end end
			if not best then return math.huge end
			if not p.vac[best] then return bd end
			done[best] = true
			for _, b in p.adj[best] do
				if visited[b] or b == f then
					local nd = bd + (if p.vac[best] then halfT(best) else 0) + (if p.vac[b] then halfT(b) else 0)
					if dist[b] == nil or nd < dist[b] then dist[b] = nd end
				end
			end
		end
	end

	local guard = 0
	while not dead do
		guard += 1
		if guard > 2000 then error("explorer loop") end
		if pos == p.relay then
			spend(pos, Config.Run.SpliceSeconds)
			return { ok = true, t = t, vacT = vacT, airT = airT, carried = carried, visited = nVisited, minO2 = minO2,
				firstSalvT = firstSalvT, retreats = retreats, gambles = gambles, tank = tank, eligible = eligible, firstVacT = firstVacT }
		end
		local dist, par = known()
		local front = {}
		for a, da in dist do
			for _, b in p.adj[a] do
				if not visited[b] then
					local cost = da + halfT(a) + St.HatchSeconds + halfT(b)
					if front[b] == nil or cost < front[b].cost then front[b] = { cost = cost, via = a } end
				end
			end
		end
		local useSignal = rand() >= prof.pNearest
		local scored = {}
		for b, f in front do
			local h = 0
			if useSignal and signalSeen[f.via] then
				h = straight(p, b, p.relay) * St.CellSize / vAir
			end
			table.insert(scored, { b = b, via = f.via, score = f.cost + h })
		end
		table.sort(scored, function(x, y)
			if x.score ~= y.score then return x.score < y.score end
			return x.b < y.b
		end)
		if #scored == 0 then error("no frontier and no relay") end
		local ignoreSafety = rand() < prof.pErr
		local choice = nil
		for _, sc in scored do
			local path = pathTo(par, sc.via)
			table.insert(path, sc.b)
			local o, lowest = simO2(path, O2)
			local okPath = lowest >= 0
			local back = returnCost(sc.b)
			if ignoreSafety or (okPath and (not p.vac[sc.b] or o - back >= prof.margin)) then
				choice = path
				break
			end
		end
		if not choice then
			local inAirFull = (not p.vac[pos]) and O2 >= tank - 1e-6
			if inAirFull then
				gambles += 1
				local sc = scored[1]
				choice = pathTo(par, sc.via)
				table.insert(choice, sc.b)
			else
				retreats += 1
				local bestAir, bd = nil, math.huge
				for c, dc in dist do
					if not p.vac[c] and dc < bd then bestAir = c; bd = dc end
				end
				if bestAir == pos then
					spend(pos, (tank - O2) / rate)
				else
					for _, c in pathTo(par, bestAir) do
						move(pos, c)
						if dead then break end
					end
					if not dead then spend(pos, (tank - O2) / rate) end
				end
				continue
			end
		end
		for _, c in choice do
			move(pos, c)
			if dead or pos == p.relay then break end
		end
	end
	return { ok = false, t = t, vacT = vacT, airT = airT, carried = carried, visited = nVisited, minO2 = minO2,
		firstSalvT = firstSalvT, retreats = retreats, gambles = gambles, tank = tank, eligible = eligible, firstVacT = firstVacT }
end

function M.lcg01(seed)
	local Rng = require("../src/shared/Rng")
	local r = Rng.new(seed)
	return function() return r:next() end
end

function M.pct(list, q)
	local c = table.clone(list)
	table.sort(c)
	if #c == 0 then return 0 / 0 end
	local k = math.max(1, math.min(#c, math.floor(q * #c + 0.5)))
	return c[k]
end

-- A whole campaign: sectors 1, 2, 3, ... with a greedy buyer (the cheapest affordable next rank after each
-- splice, ties to the Air Tank: Economy.recommended). Returns the seconds each sector was entered, purchases,
-- blackouts, earnings.
function M.campaign(prof, maxSector, maxSeconds, seed)
	local oh = M.OVERHEAD
	local rand = M.lcg01(seed * 7 + 3)
	local profile = Economy.newProfile(Config)
	local t = oh.start
	local k = 1
	local reachAt = { [1] = t }
	local deaths, attempts = 0, 0
	local buys = {}
	local log = {}
	local i = 0
	while k <= maxSector and t < maxSeconds do
		i += 1
		attempts += 1
		local p = M.plan(k, Streams.seedsFor(seed * 100003 + i, k))
		local r = M.run(p, prof, profile.up, rand)
		table.insert(log, { k = k, t0 = t, dur = r.t, eligible = r.eligible, ok = r.ok })
		t += r.t
		Economy.beginSector(profile, "m" .. i, k)
		for _ = 1, r.carried do Economy.carry(Config, profile, k) end
		if r.ok then
			Economy.splice(Config, profile, k, t)
			t += oh.transit
			k += 1
			reachAt[k] = t
			while true do
				local id = Economy.recommended(Config, profile)
				if not id or not Economy.canBuy(Config, profile, id) then break end
				Economy.buy(Config, profile, id)
				t += oh.buy
				table.insert(buys, { t = t, id = id, k = k })
			end
		else
			Economy.settle(Config, profile, "blackout")
			deaths += 1
			t += oh.blackout
		end
	end
	return { reachAt = reachAt, deaths = deaths, attempts = attempts, buys = buys, earned = profile.salvageEarned,
		t = t, log = log, up = profile.up }
end

return M
