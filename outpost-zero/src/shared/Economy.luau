--!strict
-- Economy.luau — the city's numbers. PURE: no Roblox, no require; the game's Config arrives as `cfg`.
--
-- Rules (DESIGN.md section 4):
--   * a Home storey adds settlers, a Workshop storey adds jobs, Cap(d) = 4 x 5^(d-1) per storey in district d;
--   * population = min(settlers, jobs); income = Wage x population, paid while the Orders run;
--   * storey s of a lot in district d costs Base(d) x Growth^(s-1); a building tops out at MaxStoreys;
--   * district d opens when the population reaches Districts[d].open (population never falls);
--   * Orders: every purchase sets them to OrdersSeconds; the city earns while they run, and (the safety net) also
--     while no storey in an open district is affordable, until one is. A complete city gets no net.
--   * a city with nobody in it (population 0) has no income, so the net cannot reach it: canBuy refuses a purchase
--     that would leave too few credits to build the other side (startNeed; REVIEW-1 F5).
--   * the HUD's ★ (bestNext): the short side (both when balanced), candidates affordable within the Orders,
--     score = wait + payback (2 x price / (Wage x Cap)), ties to the nearer lot; with no candidate in budget the
--     cheapest storey on that side.
--
-- A state is { layout, lots = { [key] = storeys }, credits, settlers, jobs, pop, income }. `layout` is
-- City.layout's result ({ lots = list, byKey = map }; each lot has key, d, zone "H"/"W", x, z).
-- Spec: tests/Economy.spec.luau. The pacing model (tests/CityModel.luau) plays these same functions.

local Economy = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Economy.cap(cfg: any, d: number): number
	return cfg.Economy.Cap[d] or 0
end

-- The price of storey `s` (1 = the build). nil outside 1..MaxStoreys.
function Economy.price(cfg: any, d: number, s: number): number?
	local E = cfg.Economy
	if s < 1 or s > E.MaxStoreys or E.Base[d] == nil then return nil end
	return E.Base[d] * E.Growth ^ (s - 1)
end

function Economy.maxPopulation(cfg: any): number
	local per = 0
	for d = 1, #cfg.Districts do
		per += Economy.cap(cfg, d)
	end
	-- each district has 3 Homes and 3 Workshops: the full city is 3 x MaxStoreys x sum(Cap) on each side
	return 3 * cfg.Economy.MaxStoreys * per
end

function Economy.districtsOpen(cfg: any, pop: number): number
	local n = 1
	for d = 2, #cfg.Districts do
		if pop >= cfg.Districts[d].open then n = d else break end
	end
	return n
end

-- The next district to open, and the population it opens at (nil after the last).
function Economy.nextDistrict(cfg: any, pop: number): (number?, number?)
	local n = Economy.districtsOpen(cfg, pop)
	if n >= #cfg.Districts then return nil, nil end
	return n + 1, cfg.Districts[n + 1].open
end

function Economy.income(cfg: any, pop: number): number
	return cfg.Economy.Wage * pop
end

-- Recompute settlers, jobs, population and income from the lots and the layout's zones.
function Economy.tally(cfg: any, st: any)
	local settlers, jobs = 0, 0
	local byKey = st.layout.byKey
	for key, s in st.lots do
		local l = byKey[key]
		if l and type(s) == "number" and s > 0 then
			local people = s * Economy.cap(cfg, l.d)
			if l.zone == "H" then settlers += people else jobs += people end
		end
	end
	st.settlers = settlers
	st.jobs = jobs
	st.pop = math.min(settlers, jobs)
	st.income = Economy.income(cfg, st.pop)
end

function Economy.newState(cfg: any, layout: any, lots: { [string]: number }, credits: number): any
	local st = { layout = layout, lots = lots, credits = credits, settlers = 0, jobs = 0, pop = 0, income = 0 }
	Economy.tally(cfg, st)
	return st
end

function Economy.storeys(st: any, key: string): number
	return st.lots[key] or 0
end

-- The cheapest next storey among the open districts' lots; nil when none is left (a complete city).
function Economy.cheapest(cfg: any, st: any): number?
	local open = Economy.districtsOpen(cfg, st.pop)
	local best: number? = nil
	for _, l in st.layout.lots do
		if l.d <= open then
			local p = Economy.price(cfg, l.d, (st.lots[l.key] or 0) + 1)
			if p and (best == nil or p < best) then best = p end
		end
	end
	return best
end

-- Credits over [t0, t1] (any one clock: tick() online, os.time() offline). The city works while t < ordersUntil;
-- after that, only while credits < cheapest (the safety net), and never past it. Returns credits, the seconds
-- worked under the Orders and the seconds worked under the net. A negative window pays nothing.
function Economy.earn(cfg: any, credits: number, income: number, t0: number, t1: number, ordersUntil: number, cheapest: number?): (number, number, number)
	if not (finite(t0) and finite(t1)) or t1 <= t0 or not finite(income) or income <= 0 then return credits, 0, 0 end
	local ou = if finite(ordersUntil) then ordersUntil else -math.huge
	local worked = math.max(0, math.min(t1, ou) - t0)
	credits += income * worked
	local net = 0
	local after = t1 - math.max(t0, ou)
	if after > 0 and cheapest ~= nil and finite(cheapest) and credits < cheapest then
		net = math.min(after, (cheapest - credits) / income)
		credits += income * net
	end
	return credits, worked, net
end

-- The offline earnings at a join: the same rule from the saved profile's savedAt to `now` (both os.time()).
function Economy.offline(cfg: any, prof: any, income: number, now: number, cheapest: number?): (number, any)
	local credits = if finite(prof.credits) then prof.credits else 0
	local savedAt = prof.savedAt
	if not finite(savedAt) or not finite(now) or now <= savedAt then
		return credits, { worked = 0, net = 0 }
	end
	local c, worked, net = Economy.earn(cfg, credits, income, savedAt, now, prof.ordersUntil or 0, cheapest)
	return c, { worked = worked, net = net }
end

-- "H" when settlers are short, "W" when jobs are short, nil when balanced (both sides count).
function Economy.side(st: any): string?
	if st.settlers < st.jobs then return "H" end
	if st.jobs < st.settlers then return "W" end
	return nil
end

-- The HUD's ★. px, pz: the player's position in the layout's coordinates (ties go to the nearer lot).
function Economy.bestNext(cfg: any, st: any, px: number?, pz: number?): any
	local E = cfg.Economy
	local open = Economy.districtsOpen(cfg, st.pop)
	local side = Economy.side(st)
	local budget = st.credits + st.income * E.OrdersSeconds
	local x0, z0 = px or 0, pz or 0
	local best, bestScore, bestD = nil, math.huge, math.huge
	local cheap, cheapP = nil, math.huge
	local anyLot, anyP = nil, math.huge
	for _, l in st.layout.lots do
		if l.d <= open then
			local s = st.lots[l.key] or 0
			local p = Economy.price(cfg, l.d, s + 1)
			if p then
				if p < anyP then anyLot, anyP = l, p end
				if side == nil or l.zone == side then
					if p < cheapP then cheap, cheapP = l, p end
					if p <= budget then
						local wait: number? = nil
						if st.credits >= p then wait = 0
						elseif st.income > 0 then wait = (p - st.credits) / st.income end
						if wait ~= nil then
							local score = wait + 2 * p / (E.Wage * Economy.cap(cfg, l.d))
							local dd = math.sqrt((x0 - l.x) ^ 2 + (z0 - l.z) ^ 2)
							if score < bestScore * (1 - 1e-9) or (math.abs(score - bestScore) <= bestScore * 1e-9 and dd < bestD) then
								best, bestScore, bestD = l, score, dd
							end
						end
					end
				end
			end
		end
	end
	local pick = best or cheap or anyLot
	if pick == nil then return nil end
	local s = (st.lots[pick.key] or 0) + 1
	local price = Economy.price(cfg, pick.d, s) :: number
	local wait = if st.credits >= price then 0 elseif st.income > 0 then (price - st.credits) / st.income else math.huge
	return {
		key = pick.key,
		d = pick.d,
		zone = pick.zone,
		storey = s,
		price = price,
		wait = wait,
		score = if best then bestScore else math.huge,
		x = pick.x,
		z = pick.z,
	}
end

-- The cheapest next storey on one side ("H" or "W") among the open districts' lots; nil when that side is full.
local function cheapestOn(cfg: any, st: any, zone: string): number?
	local open = Economy.districtsOpen(cfg, st.pop)
	local best: number? = nil
	for _, l in st.layout.lots do
		if l.d <= open and l.zone == zone then
			local p = Economy.price(cfg, l.d, (st.lots[l.key] or 0) + 1)
			if p and (best == nil or p < best) then best = p end
		end
	end
	return best
end

-- What a city with nobody in it needs to get its first citizens: the cheapest storey on each side that has nobody
-- yet. 0 once the population is above 0 (it never falls, and the Orders and the safety net then carry the city).
-- REVIEW-1 F5: with no citizens there is no income and the safety net cannot help, so a city that spent its
-- credits on one side was dead for good. canBuy keeps every city at or above this; the server lifts a record that
-- is below it (saved before this rule) once, at the join.
function Economy.startNeed(cfg: any, st: any): number
	if st.pop > 0 then return 0 end
	local need = 0
	if st.settlers <= 0 then need += cheapestOn(cfg, st, "H") or 0 end
	if st.jobs <= 0 then need += cheapestOn(cfg, st, "W") or 0 end
	return need
end

-- (ok, why, price). why: "unknown" | "locked" | "topped" | "credits" | "needjobs" | "needhomes".
-- "needjobs" / "needhomes" (price = the other side's cheapest storey): with nobody in the city yet, this purchase
-- would leave too few credits to build the other side, and so no way ever to earn (REVIEW-1 F5).
function Economy.canBuy(cfg: any, st: any, key: any): (boolean, string?, number?)
	local l = if type(key) == "string" then st.layout.byKey[key] else nil
	if l == nil then return false, "unknown", nil end
	if l.d > Economy.districtsOpen(cfg, st.pop) then return false, "locked", nil end
	local s = st.lots[key] or 0
	local p = Economy.price(cfg, l.d, s + 1)
	if p == nil then return false, "topped", nil end
	if st.credits < p then return false, "credits", p end
	if st.pop <= 0 then
		local other = if l.zone == "H" then "W" else "H"
		local otherPeople = if other == "H" then st.settlers else st.jobs
		if otherPeople <= 0 then
			local needOther = cheapestOn(cfg, st, other)
			if needOther ~= nil and st.credits - p < needOther then
				return false, if other == "W" then "needjobs" else "needhomes", needOther
			end
		end
	end
	return true, nil, p
end

-- Pay for and add one storey (canBuy must have said yes). Returns the price paid.
function Economy.apply(cfg: any, st: any, key: string): number
	local l = st.layout.byKey[key]
	local s = st.lots[key] or 0
	local p = Economy.price(cfg, l.d, s + 1) :: number
	st.credits -= p
	if st.credits < 0 and st.credits > -1e-6 then st.credits = 0 end
	st.lots[key] = s + 1
	Economy.tally(cfg, st)
	return p
end

--============================================================================ texts
function Economy.short(x: number): string
	if not finite(x) then return "0" end
	local neg = x < 0
	local a = math.abs(x)
	local out
	if a < 1000 then
		out = tostring(math.floor(a))
	else
		local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
		for _, u in units do
			if a >= u[1] then
				local v = a / u[1]
				if v < 100 then
					out = string.format("%.1f", v)
					out = string.gsub(out, "%.0$", "") .. u[2]
				else
					out = tostring(math.floor(v)) .. u[2]
				end
				break
			end
		end
	end
	return (if neg then "-" else "") .. out
end

-- 1031184 -> "1 031 184"
function Economy.group(n: number): string
	local s = tostring(math.floor(math.max(0, n)))
	local out = ""
	while #s > 3 do
		out = " " .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	return s .. out
end

-- seconds -> "m:ss", rounded UP so a promise is never early.
function Economy.clock(seconds: number): string
	local s = if finite(seconds) then math.max(0, math.ceil(seconds - 1e-9)) else 0
	return string.format("%d:%02d", s // 60, s % 60)
end

function Economy.refusalText(cfg: any, why: string?, price: number?, credits: number?, income: number?): string
	if why == "credits" then
		local p, c = price or 0, credits or 0
		local text = string.format("Need %s credits, you have %s", Economy.short(p), Economy.short(c))
		if (income or 0) > 0 then
			text ..= " (ready in " .. Economy.clock((p - c) / (income :: number)) .. ")"
		end
		return text
	elseif why == "locked" then
		return "That district is not open yet."
	elseif why == "topped" then
		return "This building is topped out at " .. tostring(cfg.Economy.MaxStoreys) .. " storeys."
	elseif why == "needjobs" then
		return cfg.Tutorial.NeedJobs
	elseif why == "needhomes" then
		return cfg.Tutorial.NeedHomes
	elseif why == "loading" then
		return cfg.Tutorial.Loading
	end
	return "You can't build there."
end

local function zoneName(zone: string): string
	return if zone == "H" then "Home" else "Workshop"
end

function Economy.actionText(cfg: any, st: any, key: string): string
	local l = st.layout.byKey[key]
	if l == nil then return "" end
	if (st.lots[key] or 0) > 0 then return "Add storey" end
	return "Build " .. zoneName(l.zone)
end

function Economy.objectText(cfg: any, st: any, key: string): string
	local l = st.layout.byKey[key]
	if l == nil then return "" end
	local s = st.lots[key] or 0
	local p = Economy.price(cfg, l.d, s + 1)
	-- the people the storey brings (round 2, B3): the ★ weighs price against them, and a player comparing prompts
	-- can now do the same (a Market Row storey at 90 brings 20; a Landing Field one at 67 brings 4)
	local tail = if p then string.format("%s · +%s %s", Economy.short(p), Economy.short(Economy.cap(cfg, l.d)),
		if l.zone == "H" then "settlers" else "jobs") else "Topped out"
	return string.format("%s %d/%d · %s", zoneName(l.zone), s, cfg.Economy.MaxStoreys, tail)
end

function Economy.balanceText(st: any): string
	local side = Economy.side(st)
	local tail = if side == "H" then "build a Home ★" elseif side == "W" then "build a Workshop ★" else "balanced"
	return string.format("Settlers %s · Jobs %s: %s", Economy.group(st.settlers), Economy.group(st.jobs), tail)
end

return Economy
