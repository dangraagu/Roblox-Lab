-- CityModel — the pacing model, ported line by line from design/model.py (its simulate, macros and helpers), but
-- playing the GAME's own modules: City.layout (the seeded layout), Economy.bestNext (the HUD's ★),
-- Economy.price / apply / earn / cheapest (prices, purchases, the Orders and their safety net). So when Config or
-- the rules change, tests/Pacing.spec.luau re-measures the game itself, not a copy of it.
-- Test-only (CLI): it uses string requires, which are invalid in Roblox; nothing in src/ requires it.
--
-- What it models: a player who does what the HUD tells them (+1 Jump's lesson): look at the ★ (react), walk to
-- 6 studs from the starred lot at WalkSpeed x efficiency, wait for the credits, notice they are there, press the
-- prompt (buy). Hazards come every IntervalMin-IntervalMax s of play from band 2 on and cost HazardHitCost s on a
-- hit. The profiles are ASSUMPTIONS (Config.Pacing). Deterministic: the repo's LCG (Rng), seeded per run.

local Economy = require("../src/shared/Economy")
local City = require("../src/shared/City")
local Rng = require("../src/shared/Rng")

local CityModel = {}

CityModel.NET = { engaged = 0, checked = 0 } -- the safety net: the city also works while no storey is affordable

function CityModel.fmt(x: number, d: number?): string
	return string.format("%." .. tostring(d or 1) .. "f", x)
end

function CityModel.median(t: { number }): number
	local c = table.clone(t)
	table.sort(c)
	local n = #c
	if n == 0 then return 0 / 0 end
	if n % 2 == 1 then return c[(n + 1) // 2] end
	return (c[n // 2] + c[n // 2 + 1]) / 2
end

function CityModel.pct(t: { number }, p: number): number
	local c = table.clone(t)
	table.sort(c)
	local idx = math.min(math.max(math.floor(p * (#c - 1) + 0.5) + 1, 1), #c)
	return c[idx]
end

function CityModel.compact(x: number): string
	local fmt = CityModel.fmt
	if x >= 1e9 then return fmt(x / 1e9, 2) .. "B" end
	if x >= 1e6 then return fmt(x / 1e6, 2) .. "M" end
	if x >= 1e3 then return fmt(x / 1e3, 2) .. "K" end
	return fmt(x, 1)
end

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

function CityModel.newState(cfg: any, seed: number): any
	local layout = City.layout(cfg, seed, Rng)
	local st = Economy.newState(cfg, layout, {}, cfg.Economy.StartCredits)
	st.buys = 0
	return st
end

function CityModel.cloneState(st: any): any
	local c = table.clone(st)
	c.lots = table.clone(st.lots)
	return c
end

function CityModel.cheapestOpen(cfg: any, st: any): number?
	return Economy.cheapest(cfg, st)
end

function CityModel.complete(cfg: any, st: any): boolean
	for _, l in st.layout.lots do
		if (st.lots[l.key] or 0) < cfg.Economy.MaxStoreys then return false end
	end
	return true
end

local function buy(cfg: any, st: any, key: string): number
	local p = Economy.apply(cfg, st, key)
	st.buys = (st.buys or 0) + 1
	return p
end

-- One session: profile `profName`, layout seed `seed`, `minutes` long. opts.stopAtBand: stop when that band opens;
-- opts.log(t, st, pick): called after every purchase; opts.pick(cfg, st, px, pz): what this player buys next
-- instead of the ★ (CityModel.Strategies; round 2, B3). Any pick waits for its credits, as the ★ does.
function CityModel.simulate(cfg: any, profName: string, seed: number, minutes: number, opts: any?): any
	local o = opts or {}
	local prof = cfg.Pacing.Profiles[profName]
	local E, Hz, P = cfg.Economy, cfg.Hazards, cfg.Pacing
	local r = Rng.new(seed * 104729 + 3)
	local function rand(): number return Rng.next(r) end
	local st = CityModel.newState(cfg, seed)
	local S = { t = 0, hazardClock = 0, hazards = 0, hits = 0, ordersUntil = E.OrdersSeconds, nextHaz = 0 }
	local px, pz = cfg.Shelf.Arrival.x, cfg.Shelf.Arrival.z
	local bandAt = { [1] = 0 }
	local lastBuy, maxGap, lapses = 0, 0, 0
	S.nextHaz = Hz.IntervalMin + (Hz.IntervalMax - Hz.IntervalMin) * rand()
	local first = {}
	local spans, span = {}, 0
	local T = minutes * 60

	local function advance(dt: number)
		if dt <= 0 then return end
		local t = S.t
		-- the game's own earning rule (Orders, then the safety net)
		st.credits = (Economy.earn(cfg, st.credits, st.income, t, t + dt, S.ordersUntil, Economy.cheapest(cfg, st)))
		S.hazardClock += dt
		while S.hazardClock >= S.nextHaz do
			local band = Economy.districtsOpen(cfg, st.pop)
			if band >= Hz.FirstBand then
				S.hazards += 1
				if rand() < prof.hit then
					S.hits += 1
					S.t += P.HazardHitCost
					local w2 = math.max(0, math.min(S.t, S.ordersUntil) - (S.t - P.HazardHitCost))
					st.credits += st.income * w2
				end
			end
			S.nextHaz += Hz.IntervalMin + (Hz.IntervalMax - Hz.IntervalMin) * rand()
		end
		S.t += dt
	end

	while S.t < T do
		local pick = if o.pick then o.pick(cfg, st, px, pz) else Economy.bestNext(cfg, st, px, pz)
		if pick == nil then break end
		local t0 = S.t
		advance(prof.react)
		span += S.t - t0
		local d = dist(px, pz, pick.x, pick.z)
		local walk = math.max(0, d - cfg.Lots.PromptReach)
		if prof.eff ~= math.huge and walk > 0 then
			table.insert(spans, span)
			span = 0
			advance(walk / (P.WalkSpeed * prof.eff))
			local f = (d - cfg.Lots.PromptReach) / d
			px, pz = px + (pick.x - px) * f, pz + (pick.z - pz) * f
		end
		local p = Economy.price(cfg, pick.d, (st.lots[pick.key] or 0) + 1) :: number
		if st.credits < p then
			if st.income <= 0 then break end
			local need = (p - st.credits) / st.income
			if S.t + need > S.ordersUntil then
				lapses += 1
				break
			end
			local t1 = S.t
			advance(need)
			advance(prof.notice * rand())
			span += S.t - t1
		end
		local t2 = S.t
		advance(prof.buy)
		span += S.t - t2
		if st.credits < p - 1e-6 then st.credits = p end
		local before = Economy.districtsOpen(cfg, st.pop)
		buy(cfg, st, pick.key)
		S.ordersUntil = S.t + E.OrdersSeconds
		maxGap = math.max(maxGap, S.t - lastBuy)
		lastBuy = S.t
		if #first < 8 then
			table.insert(first, { t = S.t, what = string.format("%s d%d storey %d", if pick.zone == "H" then "Home" else "Workshop",
				pick.d, st.lots[pick.key]), pop = st.pop })
		end
		local after = Economy.districtsOpen(cfg, st.pop)
		for b = before + 1, after do bandAt[b] = S.t end
		if o.log then o.log(S.t, st, pick) end
		if o.stopAtBand and after >= o.stopAtBand then break end
	end
	return { st = st, t = S.t, bandAt = bandAt, maxGap = maxGap, lapses = lapses, hazards = S.hazards, hits = S.hits,
		first = first, px = px, pz = pz, ordersUntil = S.ordersUntil, spans = spans, buys = st.buys }
end

-- Players who do NOT follow the ★ (round 2, B3; the reviewer's rv/strat.luau). Each returns the lot it buys next.
local function openStoreys(cfg: any, st: any): { any }
	local open = Economy.districtsOpen(cfg, st.pop)
	local out = {}
	for _, l in st.layout.lots do
		if l.d <= open then
			local p = Economy.price(cfg, l.d, (st.lots[l.key] or 0) + 1)
			if p then table.insert(out, { l = l, p = p, v = Economy.cap(cfg, l.d) / p }) end
		end
	end
	return out
end
local function onSide(st: any, l: any): boolean
	local side = Economy.side(st)
	return side == nil or l.zone == side
end
CityModel.Strategies = {
	-- reads the prompts' "+N settlers" / "+N jobs" and price, and waits for the most people per credit on the short side
	value = function(cfg, st)
		local best, bv = nil, -1
		for _, c in openStoreys(cfg, st) do
			if onSide(st, c.l) and c.v > bv then best, bv = c.l, c.v end
		end
		return best
	end,
	-- the same, but impatient: the most people per credit among what is affordable NOW (else the cheapest)
	valueNow = function(cfg, st)
		local best, bv, cheap, cp = nil, -1, nil, math.huge
		for _, c in openStoreys(cfg, st) do
			if onSide(st, c.l) then
				if c.p <= st.credits and c.v > bv then best, bv = c.l, c.v end
				if c.p < cp then cheap, cp = c.l, c.p end
			end
		end
		return best or cheap
	end,
	-- the cheapest storey on the side the balance line names
	cheapest = function(cfg, st)
		local best, bp = nil, math.huge
		for _, c in openStoreys(cfg, st) do
			if onSide(st, c.l) and c.p < bp then best, bp = c.l, c.p end
		end
		return best
	end,
	-- the cheapest storey anywhere (ignores the balance line too)
	cheapestAny = function(cfg, st)
		local best, bp = nil, math.huge
		for _, c in openStoreys(cfg, st) do
			if c.p < bp then best, bp = c.l, c.p end
		end
		return best
	end,
	-- tall towers: the dearest storey affordable now on the short side (else the cheapest)
	tallest = function(cfg, st)
		local best, bp, cheap, cp = nil, -1, nil, math.huge
		for _, c in openStoreys(cfg, st) do
			if onSide(st, c.l) then
				if c.p <= st.credits and c.p > bp then best, bp = c.l, c.p end
				if c.p < cp then cheap, cp = c.l, c.p end
			end
		end
		return best or cheap
	end,
}
CityModel.StrategyOrder = { "value", "valueNow", "cheapest", "cheapestAny", "tallest" }

-- AFK (or an anti-AFK jiggle) for `hours`: nothing is bought; the city earns by the game's rule.
function CityModel.afk(cfg: any, st: any, t: number, ordersUntil: number, hours: number): any
	local credits, worked, net = Economy.earn(cfg, st.credits, st.income, t, t + hours * 3600, ordersUntil, Economy.cheapest(cfg, st))
	return { credits = credits, worked = worked, net = net, pop = st.pop }
end

-- A macro pressing ONE lot's prompt at the rate limit (0.125 s), from st0, for `hours`.
function CityModel.macroOneLot(cfg: any, st0: any, li: number, hours: number): (number, number, number)
	local E = cfg.Economy
	local st = CityModel.cloneState(st0)
	local l = st.layout.lots[li]
	if l.d > Economy.districtsOpen(cfg, st.pop) then return 0, 0, 0 end
	local t, ordersUntil, T = 0, E.OrdersSeconds, hours * 3600
	local pop0, earned = st.pop, 0
	while t < T and (st.lots[l.key] or 0) < E.MaxStoreys do
		local p = Economy.price(cfg, l.d, (st.lots[l.key] or 0) + 1) :: number
		if st.credits < p then
			if st.income <= 0 then break end
			local need = (p - st.credits) / st.income
			if t + need > ordersUntil then
				earned += st.income * math.max(0, ordersUntil - t)
				st.credits += st.income * math.max(0, ordersUntil - t)
				CityModel.NET.checked += 1
				if st.credits < (Economy.cheapest(cfg, st) or math.huge) then CityModel.NET.engaged += 1 end
				break
			end
			t += need
			earned += st.income * need
			st.credits = p
		end
		t += 0.125
		buy(cfg, st, l.key)
		ordersUntil = t + E.OrdersSeconds
	end
	return st.pop - pop0, st.lots[l.key] or 0, earned
end

-- A route macro walking between one Home lot and one Workshop lot, pressing each in turn.
function CityModel.macroTwoLots(cfg: any, st0: any, hi: number, wi: number, hours: number): number
	local E = cfg.Economy
	local st = CityModel.cloneState(st0)
	local h, w = st.layout.lots[hi], st.layout.lots[wi]
	local walk = math.max(0, dist(h.x, h.z, w.x, w.z) - 2 * cfg.Lots.PromptReach) / cfg.Pacing.WalkSpeed
	local t, ordersUntil, T = 0, E.OrdersSeconds, hours * 3600
	local pop0 = st.pop
	local turn = if st.settlers <= st.jobs then h else w
	while t < T do
		if (st.lots[turn.key] or 0) >= E.MaxStoreys or turn.d > Economy.districtsOpen(cfg, st.pop) then break end
		local p = Economy.price(cfg, turn.d, (st.lots[turn.key] or 0) + 1) :: number
		if st.credits < p then
			if st.income <= 0 then break end
			local need = (p - st.credits) / st.income
			if t + need > ordersUntil then
				st.credits += st.income * math.max(0, ordersUntil - t)
				CityModel.NET.checked += 1
				if st.credits < (Economy.cheapest(cfg, st) or math.huge) then CityModel.NET.engaged += 1 end
				break
			end
			t += need
			st.credits = p
		end
		t += 0.125
		buy(cfg, st, turn.key)
		ordersUntil = t + E.OrdersSeconds
		turn = if turn == h then w else h
		t += walk
	end
	return st.pop - pop0
end

return CityModel
