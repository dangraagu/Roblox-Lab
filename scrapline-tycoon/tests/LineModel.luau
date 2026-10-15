-- LineModel.luau — the pacing model: design/model.py's `simulate`, ported to Luau and played on the GAME's own
-- rules. Not game code; tests/Pacing.spec.luau runs it and asserts the targets DESIGN.md quotes.
--
-- What is the game's own: Config (every number), Line (the flow and income), Economy (prices, the purchase, the
-- ★), Jams (the jam scheduler: one sputter at a time, sputter -> jam, the fix) and Recycle (the requirement and
-- the new run). What is the model's: the player. A profile (Config.Pacing.Profiles, ALL ASSUMPTIONS) opens the
-- shop every `shop` s, spends `buy` s per purchase, notices a sputter after `notice` s and walks to its station
-- from the middle of the U at WalkSpeed x `eff` (or `speed`), then holds Fix for FixHold s. Hazards are counted,
-- not walked: the client's rule (one per 120-180 s of play on your own plot, none in the Junkyard, held while
-- a machine sputters). Draws come from a seeded LCG, so a run is reproducible; the game itself
-- draws from Random.new() and is not.
--
-- Differences from design/model.py, stated: the RNG (an LCG here, Python's Mersenne Twister there), so the
-- numbers differ draw by draw but not in distribution; a sputter that jams before its fixer arrives restarts the
-- jam clock at once (Jams.luau, the game's rule) where the Python kept the clock stopped until the fix. No active
-- profile is slow enough for that to matter (the slow player reaches a sputter in 12.3 s of its 15).

local Config = require("../src/shared/Config")
local Line = require("../src/shared/Line")
local Economy = require("../src/shared/Economy")
local Jams = require("../src/shared/Jams")
local Recycle = require("../src/shared/Recycle")
local Save = require("../src/shared/Save")

local C = Config
local LineModel = {}

local function lcg(seed: number)
	local state = (seed * 7919 + 104729) % 2147483648
	local function rand(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	-- burn a few: low seeds start correlated
	for _ = 1, 5 do rand() end
	return rand
end

local function uniform(rand, a, b)
	return a + (b - a) * rand()
end

local function gainOf(S, a, M, now)
	return Economy.preview(C, Line, S, a, M) - now
end

local function cheapest(S, cash, M)
	local now = Line.income(C, S, M, true)
	local best = nil
	for _, a in Economy.candidates(C, S) do
		if a.kind == "build" or gainOf(S, a, M, now) > 1e-9 then
			if best == nil or a.price < best.price then best = a end
		end
	end
	return best
end

local function randomUseful(S, cash, M, rand)
	local now = Line.income(C, S, M, true)
	local cs = {}
	for _, a in Economy.candidates(C, S) do
		if a.price <= cash and (a.kind == "build" or gainOf(S, a, M, now) > 1e-9) then table.insert(cs, a) end
	end
	if #cs == 0 then return cheapest(S, cash, M) end
	return cs[math.min(#cs, 1 + math.floor(rand() * #cs))]
end

local function choose(policy, S, cash, M, rand)
	if policy == "star" then
		return Economy.star(C, Line, S, cash, M)
	elseif policy == "saver" then
		return Economy.starPayback(C, Line, S, cash, M)
	elseif policy == "random" then
		return randomUseful(S, cash, M, rand)
	elseif policy == "mixed" then
		if rand() < 0.75 then return Economy.star(C, Line, S, cash, M) end
		return randomUseful(S, cash, M, rand)
	elseif policy == "green" then
		-- REVIEW-2 R3: taps any button the panel paints gold or green (Economy.worth, the HUD's own rule), at random
		local star = Economy.star(C, Line, S, cash, M)
		local w = Economy.worth(C, Line, S, cash, M)
		local cs = {}
		for _, a in Economy.candidates(C, S) do
			local isStar = star ~= nil and star.kind == a.kind and star.t == a.t
			if a.price <= cash and (isStar or w[a.kind .. ":" .. a.t]) then table.insert(cs, a) end
		end
		if #cs == 0 then return nil end
		return cs[math.min(#cs, 1 + math.floor(rand() * #cs))]
	elseif policy == "anyaffordable" then
		-- the reviewer's: taps any affordable button, whatever its colour, useful or not
		local cs = {}
		for _, a in Economy.candidates(C, S) do
			if a.price <= cash then table.insert(cs, a) end
		end
		if #cs == 0 then return nil end
		return cs[math.min(#cs, 1 + math.floor(rand() * #cs))]
	end
	return cheapest(S, cash, M)
end

LineModel.SNAPS = { 30, 60, 120, 300, 600, 1200, 1800, 2100, 2400, 3600, 5400, 7200, 10800, 14400, 21600, 28800 }

-- opts: recycle (bool), untilRocket (bool), firstPlaceAt (s, default 3), switchAt = { seconds, profileName }
function LineModel.simulate(pname: string, seed: number, seconds: number, opts: any?): any
	local o = opts or {}
	local p = C.Pacing.Profiles[pname]
	assert(p, "no profile " .. pname)
	local rand = lcg(seed)
	local dt = C.Pacing.Dt
	local d = Save.defaults(C)
	local S = Line.ordered(C, d.stations)
	local M = Line.mult(C, d.bolts)
	local shipped = { 0, 0, 0, 0, 0, 0, 0 }
	local out = {
		tierAt = {}, runs = {}, firstRocket = nil, jams = 0, saved = 0, fixed = 0, hazards = 0, hazardsToRocket = nil,
		lostIncome = 0, idealIncome = 0, earned = 0, incAt = {}, boltsAt = {}, purchases = {}, firstBuyAt = nil,
		boltsAtSwitch = nil, recycles = 0, goldenAt = nil,
	}
	local placed = false
	local fixes = {} -- { t, m, at }
	local hazClock, hazNext = 0, uniform(rand, C.Hazards.IntervalMin, C.Hazards.IntervalMax)
	local shopNext = uniform(rand, 0, p.shop)
	local buyBusy = 0
	local runStart = 0
	local walk = p.speed or C.Trace.WalkSpeed * p.eff
	local work = C.Pacing.WorkSpot
	local placeAt = o.firstPlaceAt or 3
	local t = 0
	while t < seconds do
		if o.switchAt and t >= o.switchAt[1] and out.boltsAtSwitch == nil then
			p = C.Pacing.Profiles[o.switchAt[2]]
			walk = p.speed or C.Trace.WalkSpeed * p.eff
			if not p.fixes then table.clear(fixes) end
			out.boltsAtSwitch = d.bolts
		end
		-- the free Shredder, one tap
		if not placed and t >= placeAt then
			Economy.buy(C, d, "build", "shredder")
			placed = true
		end
		-- jams (server rule): fixes that are due land first, then the scheduler steps
		if placed then
			for i = #fixes, 1, -1 do
				local f = fixes[i]
				if t >= f.at then
					table.remove(fixes, i)
					local r = Jams.fix(C, d.jams, S, f.t, f.m)
					if r == "saved" then out.saved += 1 elseif r == "fixed" then out.fixed += 1 end
				end
			end
			local ev = Jams.step(C, d.jams, S, dt, rand)
			if ev and ev.kind == "sputter" then
				out.jams += 1
				if p.fixes then
					local cx, cz = C.Plot.StationCentres[ev.t].x, C.Plot.StationCentres[ev.t].z
					local dist = math.sqrt((cx - work.x) ^ 2 + (cz - work.z) ^ 2)
					table.insert(fixes, { t = ev.t, m = ev.m, at = t + p.notice + dist / walk + C.Jams.FixHold })
				end
			end
		end
		-- hazards (client rule), counted: quiet in the Junkyard, held while a machine sputters (REVIEW-2 R5: not while a
		-- jam merely stands)
		local trouble = d.jams.sputter ~= nil
		if p.fixes then
			hazClock += dt
			if hazClock >= hazNext then
				if d.tier <= 1 then
					hazNext = hazClock + uniform(rand, C.Hazards.IntervalMin, C.Hazards.IntervalMax)
				elseif not trouble then
					out.hazards += 1
					hazNext = hazClock + uniform(rand, C.Hazards.IntervalMin, C.Hazards.IntervalMax)
				end
			end
		end
		-- production: the server's tick
		local inc, r = Line.income(C, S, M)
		local ideal = Line.income(C, S, M, true)
		out.lostIncome += (ideal - inc) * dt
		out.idealIncome += ideal * dt
		d.cash += inc * dt
		out.earned += inc * dt
		for s = 1, 7 do
			shipped[s] += r[s] * dt
			if shipped[s] >= 1 and s - 1 > d.tier then
				d.tier = s - 1
				out.tierAt[out.recycles .. ":" .. d.tier] = t
			end
		end
		if shipped[7] >= 1 and out.firstRocket == nil then
			out.firstRocket = t
			out.hazardsToRocket = out.hazards
			if o.untilRocket then break end
		end
		-- shopping
		if buyBusy > 0 then
			buyBusy -= dt
		elseif placed and t >= shopNext then
			shopNext = t + p.shop
			if o.recycle and Line.flow(C, S)[7] >= Recycle.requirement(C, d.bolts) - 1e-9 then
				table.insert(out.runs, { start = runStart, finish = t, M = M })
				d = Recycle.nextRun(C, d, t)
				S = Line.ordered(C, d.stations)
				M = Line.mult(C, d.bolts)
				shipped = { 0, 0, 0, 0, 0, 0, 0 }
				table.clear(fixes)
				out.recycles += 1
				if out.goldenAt == nil and Recycle.golden(C, d.bolts) then out.goldenAt = t end
				runStart = t
				buyBusy = C.Recycle.SequenceSeconds
			else
				local n = 0
				while n < 60 do
					local a = choose(p.policy, S, d.cash, M, rand)
					if a == nil or a.price > d.cash then break end
					if out.firstBuyAt == nil then out.firstBuyAt = t end
					local ok = Economy.buy(C, d, a.kind, C.Stations.Order[a.t])
					assert(ok, "the model chose a purchase the game refuses")
					table.insert(out.purchases, t)
					n += 1
				end
				buyBusy = n * p.buy
			end
		end
		for _, mark in LineModel.SNAPS do
			if t < mark and mark <= t + dt then
				out.incAt[mark] = inc
				out.boltsAt[mark] = d.bolts
			end
		end
		t += dt
	end
	out.final = d
	out.S = S
	return out
end

-- An untended line: the normal player's line at `atSeconds`, then nobody fixes and nobody buys (DESIGN 5, [M7]).
-- Returns { [minutes] = { now = income now / tended, sofar = earned so far / tended } }.
function LineModel.untended(seed: number, atSeconds: number, marks: { number }): any
	local base = LineModel.simulate("normal", seed, atSeconds)
	local d = base.final
	-- the tended income: the same line, every machine running
	local S = Line.ordered(C, d.stations)
	for t = 1, 6 do S[t].jam = { 0, 0 } end
	d.jams.sputter = nil
	local M = Line.mult(C, d.bolts)
	local ideal = Line.income(C, S, M, true)
	local rand = lcg(seed + 1000)
	local earned, out = 0, {}
	local horizon = 0
	for _, m in marks do horizon = math.max(horizon, m) end
	for sec = 1, horizon * 60 do
		Jams.step(C, d.jams, S, 1, rand)
		earned += Line.income(C, S, M)
		for _, m in marks do
			if sec == m * 60 then
				out[m] = { now = Line.income(C, S, M) / ideal, sofar = earned / (ideal * sec) }
			end
		end
	end
	return out
end

function LineModel.pct(xs: { number }, q: number): number
	local s = table.clone(xs)
	table.sort(s)
	if #s == 0 then return 0 / 0 end
	local k = (#s - 1) * q
	local lo, hi = math.floor(k), math.ceil(k)
	local a, b = s[lo + 1], s[hi + 1]
	if lo == hi or a == b then return a end -- also keeps math.huge ("never") from turning into NaN
	return a + (b - a) * (k - lo)
end

return LineModel
