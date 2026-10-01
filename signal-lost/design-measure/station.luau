--!nocheck
-- DESIGN MEASUREMENT RIG for signal-lost/DESIGN.md. NOT GAME CODE.
-- A prototype sector planner, an oxygen-limited model explorer and a campaign (progression) model,
-- written only to derive the spec's numbers. Do not copy it into src/. The real
-- src/shared/Station.luau must reproduce DESIGN.md Appendix A's M1 table (same MazeGen, same draw
-- order per stream) or the spec's numbers must be re-measured against the real module.
-- Rng.luau and MazeGen.luau here are verbatim copies of vault-runners/src/shared (md5 217e5d06...
-- and c269d302...), present only so `require("./X")` resolves in the luau CLI.
-- Run from this directory:  <luau>/luau.exe m1_sector.luau 2>&1
local Rng = require("./Rng")
local MazeGen = require("./MazeGen")

local S = {}

S.CFG = {
	CellSize = 32,          -- studs, one module
	AirSpeed = 16,          -- studs/s in a pressurized module (Roblox default WalkSpeed)
	VacSpeed = 12,          -- studs/s in a breached module, before Mag-Boots
	HatchSeconds = 0.5,     -- first entry into a module: the hatch cycles
	SalvageDetour = 1.2,    -- seconds to grab a salvage piece (some float: a low-g hop)
	CanisterDetour = 0.9,   -- seconds to grab an O2 canister
	CanisterSeconds = 10,   -- O2 a canister adds (capped at the tank)
	RefillSeconds = 2,      -- an empty tank fills in this long inside air
	GraceSeconds = 5,       -- hypoxia: seconds at 0 O2 before blackout
	SpliceSeconds = 2,
	ExtraDoorChance = 0.2,
	RelayDepthFrac = 0.75,  -- relay candidates: air modules with d >= ceil(frac * maxD)
	TankBase = 20,
	TankStep = 5,           -- per Air Tank rank (20 -> 40 at rank 4)
	BootsStep = 1,          -- studs/s per Boots rank (12 -> 16 at rank 4)
	RecvBase = 4,           -- the meter shows 2-5 bars within 4 modules (straight line), 1 bar beyond
	RecvStep = 0,           -- no Receiver upgrade in v1 (M5: it bought no survival)
	LowO2Seconds = 10,      -- hazards never start below this much air
	ArrivalGraceSeconds = 6,-- hazards never start in a sector's first seconds
}

-- Environment bands (DESIGN.md §4) and the difficulty schedule aligned with them (§3).
S.BANDS = {
	{ id = "docking", from = 1 }, { id = "hydro", from = 5 }, { id = "cargo", from = 10 },
	{ id = "reactor", from = 16 }, { id = "array", from = 23 }, { id = "deep", from = 31 }, { id = "echo", from = 60 },
}
S.BRAG = 30 -- the Main Array is sector 30's relay
function S.bandOf(k)
	local idx = 1
	for i, b in S.BANDS do if k >= b.from then idx = i end end
	return idx
end
function S.schedule(k)
	if k == 1 then return { n = 3, breach = 0.35, reach = 1, salvage = 2, canisters = 1, onboard = true } end
	if k <= 2 then return { n = 3, breach = 0.35, reach = 1, salvage = 2, canisters = 1 } end
	if k <= 4 then return { n = 4, breach = 0.45, reach = 2, salvage = 3, canisters = 1 } end
	if k <= 9 then return { n = 4, breach = 0.55, reach = 2, salvage = 3, canisters = 1 } end
	if k <= 15 then return { n = 5, breach = 0.6, reach = 3, salvage = 4, canisters = 2 } end
	if k <= 22 then return { n = 5, breach = 0.65, reach = 3, salvage = 4, canisters = 2 } end
	-- array spine and beyond: air pockets thin out forever toward 0.95, vacuum stretches grow to reach 10
	return { n = 6, breach = 0.95 - 0.30 * 0.97 ^ (k - 23), reach = math.min(10, 4 + (k - 23) // 8), salvage = 5,
		canisters = if k <= 30 then 2 else 1 }
end
S.defaultSchedule = S.schedule

S.ECON = {
	value = function(k) return 5 + (k - 1) end,   -- salvage per piece in sector k
	bonus = function(k) return 10 + 2 * (k - 1) end, -- paid on the splice
	keep = 0.5,                                    -- share of carried salvage banked when a sector is left unspliced
	prices = {
		tank = { 120, 300, 600, 1000 },
		boots = { 120, 300, 600, 1000 },
	},
}
S.OVERHEAD = { start = 5, transit = 3, blackout = 4.5, buy = 4 }

local function bfs(adj, n2, srcs)
	local d = {}
	for i = 1, n2 do d[i] = -1 end
	local q = {}
	for _, s in srcs do d[s] = 0; table.insert(q, s) end
	local h = 1
	while h <= #q do
		local a = q[h]; h += 1
		for _, b in adj[a] do
			if d[b] < 0 then d[b] = d[a] + 1; table.insert(q, b) end
		end
	end
	return d
end
S.bfs = bfs

-- seeds = { layout, air, loot, relay }: four independent integer seeds.
function S.plan(k, seeds, sched, cfg)
	cfg = cfg or S.CFG
	sched = sched or S.defaultSchedule(k)
	local n = sched.n
	local lay = Rng.new(seeds.layout)
	local grid = MazeGen.generate(n, n, lay)
	local n2 = n * n
	local function id(x, y) return y * n + x + 1 end
	local adj = {}
	for i = 1, n2 do adj[i] = {} end
	local doors = 0
	local function link(a, b) table.insert(adj[a], b); table.insert(adj[b], a); doors += 1 end
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x < n - 1 then
				local open = grid[2 * y + 1][2 * x + 2] == false
				if not open and lay:next() < cfg.ExtraDoorChance then open = true end
				if open then link(id(x, y), id(x + 1, y)) end
			end
			if y < n - 1 then
				local open = grid[2 * y + 2][2 * x + 1] == false
				if not open and lay:next() < cfg.ExtraDoorChance then open = true end
				if open then link(id(x, y), id(x, y + 1)) end
			end
		end
	end
	local perim = {}
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			if x == 0 or y == 0 or x == n - 1 or y == n - 1 then table.insert(perim, id(x, y)) end
		end
	end
	local entry = perim[lay:below(#perim)]
	local d = bfs(adj, n2, { entry })
	local maxD = 0
	for i = 1, n2 do if d[i] > maxD then maxD = d[i] end end

	-- air map (air stream): entry always air; others breached with probability sched.breach
	local ar = Rng.new(seeds.air)
	local vac = {}
	for i = 1, n2 do
		local roll = ar:next()
		vac[i] = (i ~= entry) and roll < sched.breach
	end
	-- onboarding (sector 1 only): every module next to the entry is breached, so the first hatch
	-- teaches the air gauge. Relay-independent: it reads the entry and the walls only.
	if sched.onboard then
		for _, b in adj[entry] do vac[b] = true end
	end
	-- reach rule: every breached module within `reach` doorways of an air module.
	-- Fix: flip the violating module farthest from air (ties: lowest id). Relay-independent.
	local flips = 0
	while true do
		local airs = {}
		for i = 1, n2 do if not vac[i] then table.insert(airs, i) end end
		local da = bfs(adj, n2, airs)
		local worst, worstD = nil, sched.reach
		for i = 1, n2 do
			if vac[i] and da[i] > worstD then worst = i; worstD = da[i] end
		end
		if not worst then break end
		vac[worst] = false
		flips += 1
	end
	-- relay (relay stream): uniform among air modules far from the entry
	local rr = Rng.new(seeds.relay)
	local thr = math.ceil(cfg.RelayDepthFrac * maxD)
	local cand = {}
	while thr >= 1 do
		cand = {}
		for i = 1, n2 do
			if i ~= entry and not vac[i] and d[i] >= thr then table.insert(cand, i) end
		end
		if #cand > 0 then break end
		thr -= 1
	end
	local forced = false
	if #cand == 0 then
		-- no air module besides the entry: make the farthest (lowest id) one air
		local far, fd = nil, -1
		for i = 1, n2 do if d[i] > fd then far = i; fd = d[i] end end
		vac[far] = false
		cand = { far }
		forced = true
	end
	local relay = cand[rr:below(#cand)]
	local nCand = #cand

	-- loot (loot stream): salvage and canisters in distinct breached modules (not entry/relay);
	-- if breached modules run out, air modules take the rest.
	local lr = Rng.new(seeds.loot)
	local pool = {}
	for i = 1, n2 do if vac[i] and i ~= entry and i ~= relay then table.insert(pool, i) end end
	local pool2 = {}
	for i = 1, n2 do if not vac[i] and i ~= entry and i ~= relay then table.insert(pool2, i) end end
	local item = {}
	local function take()
		local list = if #pool > 0 then pool else pool2
		if #list == 0 then return nil end
		local j = lr:below(#list)
		local r = list[j]
		table.remove(list, j)
		return r
	end
	local nSalv, nCan = 0, 0
	local salvageLeft = sched.salvage
	if sched.onboard then
		-- the first salvage floats in a module next to the entry (loot stream picks which)
		local near = {}
		for _, b in adj[entry] do if b ~= relay then table.insert(near, b) end end
		table.sort(near)
		if #near > 0 then
			local r = near[lr:below(#near)]
			item[r] = "salvage"; nSalv += 1; salvageLeft -= 1
			for j, c in pool do if c == r then table.remove(pool, j) break end end
			for j, c in pool2 do if c == r then table.remove(pool2, j) break end end
		end
	end
	for _ = 1, salvageLeft do
		local r = take(); if r then item[r] = "salvage"; nSalv += 1 end
	end
	for _ = 1, sched.canisters do
		local r = take(); if r then item[r] = "canister"; nCan += 1 end
	end
	local nVac = 0
	for i = 1, n2 do if vac[i] then nVac += 1 end end
	return {
		k = k, n = n, n2 = n2, adj = adj, entry = entry, relay = relay, d = d, maxD = maxD, vac = vac,
		item = item, doors = doors, flips = flips, forced = forced, nVac = nVac, nSalv = nSalv, nCan = nCan,
		sched = sched, nCand = nCand, relayThr = thr,
	}
end

local function xy(p, i) return (i - 1) % p.n, (i - 1) // p.n end
function S.straight(p, a, b)
	local ax, ay = xy(p, a)
	local bx, by = xy(p, b)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- prof = { speed (factor), pNearest, pErr, margin }, up = { tank, boots, recv } ranks.
-- rand: () -> [0,1) for the human noise.
-- Returns { ok, t, vacT, airT, carried, visited, minO2, hyp, firstSalvT, deathT }
function S.run(p, prof, up, rand, cfg)
	cfg = cfg or S.CFG
	local tank = cfg.TankBase + cfg.TankStep * (up.tank or 0)
	local vAir = cfg.AirSpeed * prof.speed
	local vVac = (cfg.VacSpeed + cfg.BootsStep * (up.boots or 0)) * prof.speed
	local range = cfg.RecvBase + cfg.RecvStep * (up.recv or 0)
	local half = { air = cfg.CellSize / 2 / vAir, vac = cfg.CellSize / 2 / vVac }
	local rate = tank / cfg.RefillSeconds

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
	local hypEvents = 0
	local retreats = 0
	local gambles = 0
	local firstVacT = nil
	local eligible = 0 -- vacuum seconds with O2 >= LowO2Seconds, after the arrival grace
	local signalSeen = {} -- visited modules where the meter read the relay (within range)

	local function halfT(c) return if p.vac[c] then half.vac else half.air end

	local function spend(c, dur)
		if dead or dur <= 0 then return end
		t += dur
		if p.vac[c] then
			if not firstVacT then firstVacT = t - dur end
			vacT += dur
			local from = math.max(t - dur, cfg.ArrivalGraceSeconds)
			local span = math.max(0, t - from)
			eligible += math.max(0, math.min(span, O2 - cfg.LowO2Seconds))
			O2 -= dur
			if O2 < 0 then
				if hyp == 0 then hypEvents += 1 end
				hyp += -O2
				O2 = 0
				if hyp >= cfg.GraceSeconds then dead = true end
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
			spend(c, cfg.SalvageDetour)
			carried += 1
			if not firstSalvT then firstSalvT = t end
		elseif it == "canister" then
			if O2 < tank or hyp > 0 then
				spend(c, cfg.CanisterDetour)
				hyp = 0
				O2 = math.min(tank, O2 + cfg.CanisterSeconds)
			end
		end
		if S.straight(p, c, p.relay) <= range then signalSeen[c] = true end
	end
	enter(p.entry)
	if S.straight(p, p.entry, p.relay) <= range then signalSeen[p.entry] = true end

	local function move(a, b)
		spend(a, halfT(a))
		if not visited[b] then spend(b, cfg.HatchSeconds) end
		spend(b, halfT(b))
		pos = b
		enter(b)
	end

	-- Dijkstra over KNOWN modules (visited) from pos, cost = travel seconds.
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
	-- O2 left after walking `path` from pos (nil if hypoxia would exceed grace, false-y check uses margin)
	local function simO2(path, startO2)
		local o, a = startO2, pos
		local lowest = startO2
		for _, b in path do
			for _, seg in { { a, halfT(a) }, { b, (if visited[b] then 0 else cfg.HatchSeconds) + halfT(b) } } do
				local c, dur = seg[1], seg[2]
				if p.vac[c] then o -= dur; lowest = math.min(lowest, o)
				else o = math.min(tank, o + rate * dur) end
			end
			a = b
		end
		return o, lowest
	end
	-- seconds from module f back to the nearest known air module, through known modules + f
	local function returnCost(f)
		if not p.vac[f] then return 0 end
		-- BFS by time from f over visited modules
		local dist, done = { [f] = 0 }, {}
		while true do
			local best, bd = nil, math.huge
			for c, dc in dist do if not done[c] and dc < bd then best = c; bd = dc end end
			if not best then return math.huge end
			if not p.vac[best] then
				-- drain counted only in breached modules: approximate with time spent in vac modules
				return bd
			end
			done[best] = true
			for _, b in p.adj[best] do
				if visited[b] or b == f then
					-- only the vac part of the crossing drains; air half refills
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
			spend(pos, cfg.SpliceSeconds)
			return { ok = true, t = t, vacT = vacT, airT = airT, carried = carried, visited = nVisited,
				minO2 = minO2, hypEvents = hypEvents, firstSalvT = firstSalvT, retreats = retreats, gambles = gambles,
				tank = tank, eligible = eligible, firstVacT = firstVacT }
		end
		local dist, par = known()
		-- frontier: unvisited modules adjacent to known ones; the hatch light tells air or vacuum
		local front = {}
		for a, da in dist do
			for _, b in p.adj[a] do
				if not visited[b] then
					local cost = da + halfT(a) + cfg.HatchSeconds + halfT(b)
					if front[b] == nil or cost < front[b].cost then front[b] = { cost = cost, via = a } end
				end
			end
		end
		local useSignal = rand() >= prof.pNearest
		local scored = {}
		for b, f in front do
			local h = 0
			if useSignal and signalSeen[f.via] then
				h = S.straight(p, b, p.relay) * cfg.CellSize / vAir
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
		for _, s in scored do
			local path = pathTo(par, s.via)
			table.insert(path, s.b)
			local o, lowest = simO2(path, O2)
			local okPath = lowest >= 0
			local back = returnCost(s.b)
			if ignoreSafety or (okPath and (not p.vac[s.b] or o - back >= prof.margin)) then
				choice = path
				break
			end
		end
		if not choice then
			-- nothing safe: refill first (nearest known air), unless already full in air
			local inAirFull = (not p.vac[pos]) and O2 >= tank - 1e-6
			if inAirFull then
				-- forced gamble: best-scoring frontier regardless
				gambles += 1
				local s = scored[1]
				choice = pathTo(par, s.via)
				table.insert(choice, s.b)
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
	return { ok = false, t = t, vacT = vacT, airT = airT, carried = carried, visited = nVisited,
		minO2 = minO2, hypEvents = hypEvents, firstSalvT = firstSalvT, retreats = retreats, gambles = gambles,
		tank = tank, eligible = eligible, firstVacT = firstVacT }
end

-- Speed proxies for humans (see DESIGN.md §0): speed factor, share of decisions that ignore the
-- signal, share that ignore the O2 safety check, safety margin in seconds.
S.PROFILES = {
	fast = { speed = 1.0, pNearest = 0.0, pErr = 0.02, margin = 2 },
	medium = { speed = 0.8, pNearest = 0.3, pErr = 0.05, margin = 3 },
	slow = { speed = 0.65, pNearest = 0.6, pErr = 0.10, margin = 4 },
}

function S.lcg01(seed)
	local r = Rng.new(seed)
	return function() return r:next() end
end

function S.pct(list, q)
	local c = table.clone(list)
	table.sort(c)
	if #c == 0 then return 0 / 0 end
	local k = math.max(1, math.min(#c, math.floor(q * #c + 0.5)))
	return c[k]
end
function S.mean(list)
	if #list == 0 then return 0 / 0 end
	local s = 0
	for _, v in list do s += v end
	return s / #list
end

function S.seedsFor(i, salt)
	salt = salt or 0
	return {
		layout = 1000003 * i + 17 + salt,
		air = 7919 * i + 104729 + salt * 3,
		loot = 15485863 * i + 32452843 + salt * 5,
		relay = 49979687 * i + 86028121 + salt * 7,
	}
end


-- ── Campaign (progression) model ─────────────────────────────────────────────────────────────
-- econ = { value(k) -> salvage per piece, bonus(k) -> splice bonus, keep = share kept on blackout,
--          prices = { tank = {...}, boots = {...}, recv = {...} } }
-- opts = { maxSector, maxSeconds, schedule(k), cfg, overhead = { start, transit, blackout, buy } }
-- Returns { reachAt = { [k] = seconds when sector k was entered }, deaths, buys = { {t, id, rank} },
--           wallet, earned, attempts, perSector = { [k] = { attempts, seconds } } }
function S.campaign(prof, econ, opts, seed)
	local cfg = opts.cfg or S.CFG
	local sch = opts.schedule or S.defaultSchedule
	local oh = opts.overhead
	local rand = S.lcg01(seed * 7 + 3)
	local up = { tank = 0, boots = 0, recv = 0 }
	local t = oh.start
	local wallet, earned = 0, 0
	local k = 1
	local reachAt = { [1] = t }
	local deaths, attempts = 0, 0
	local buys = {}
	local perSector = {}
	local vacTotal, airTotal = 0, 0
	local log = {} -- per attempt: { k, t0, dur, eligible, ok, lowO2 }
	local i = 0
	while k <= opts.maxSector and t < opts.maxSeconds do
		i += 1
		attempts += 1
		local p = S.plan(k, S.seedsFor(seed * 100003 + i, k), sch(k), cfg)
		local r = S.run(p, prof, up, rand, cfg)
		table.insert(log, { k = k, t0 = t, dur = r.t, eligible = r.eligible, ok = r.ok, lowO2 = r.minO2 < 0.25 * r.tank,
			carried = r.carried })
		t += r.t
		vacTotal += r.vacT
		airTotal += r.airT
		perSector[k] = perSector[k] or { attempts = 0, seconds = 0 }
		perSector[k].attempts += 1
		perSector[k].seconds += r.t
		local pay
		if r.ok then
			pay = r.carried * econ.value(k) + econ.bonus(k)
			t += oh.transit
			k += 1
			reachAt[k] = t
		else
			pay = math.floor(r.carried * econ.value(k) * econ.keep)
			deaths += 1
			t += oh.blackout
		end
		wallet += pay
		earned += pay
		if r.ok then
			-- greedy: cheapest affordable next rank, repeatedly
			while true do
				local bestId, bestPrice = nil, math.huge
				for id, ladder in econ.prices do
					local nextRank = up[id] + 1
					local price = ladder[nextRank]
					-- ties go to the Air Tank (the HUD recommends it: it buys the most survival per rank, M5)
					local better = price and price <= wallet and (price < bestPrice or (price == bestPrice and id == "tank"))
					if better then
						bestId, bestPrice = id, price
					end
				end
				if not bestId then break end
				wallet -= bestPrice
				up[bestId] += 1
				t += oh.buy
				table.insert(buys, { t = t, id = bestId, rank = up[bestId], k = k })
			end
		end
	end
	return { reachAt = reachAt, deaths = deaths, attempts = attempts, buys = buys, wallet = wallet,
		earned = earned, up = up, perSector = perSector, t = t, vacTotal = vacTotal, airTotal = airTotal, log = log }
end

return S
