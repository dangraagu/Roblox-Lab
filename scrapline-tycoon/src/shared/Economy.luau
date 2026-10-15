--!strict
-- Economy.luau — prices, what can be bought, the purchase (every check before the first assignment), the
-- HUD's ★, refusal texts and number formatting. PURE: cfg + plain tables in.
--
-- DESIGN.md sections 4.1 and 4.5. A purchase is one of three kinds at one station:
--   "build"  the station's first machine (the Shredder is free); allowed once the station before it exists;
--   "twin"   its second machine, which doubles the station (TwinPrice x its first upgrade);
--   "up"     one level for both machines (UpgradeBase x UpgradeGrowth^(L-1)), up to MaxLevel.
-- The ★ (Economy.star):
--   0. the next station, the moment it is affordable, and from SaveWindow seconds of income before that;
--   1. otherwise the TARGET is the purchase that pays for itself soonest, counting the wait to afford it:
--      max(0, price - cash) / income + price / gain, ties to the cheaper;
--   2. while the target is unaffordable, an affordable purchase whose payback is shorter than the wait for
--      the target (rule 1's score already guarantees there is none: tests/Economy.spec.luau checks the outcome).
-- The ★ plans for a WORKING line (jams ignored). design/model.py's `star` is this function, and
-- tests/LineModel.luau plays it. This file requires nothing: the functions that need the line's flow take the
-- Line module as their second argument (a bare require("./Line") is invalid in Roblox).
-- Spec: tests/Economy.spec.luau.

local Economy = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Round half to even, as Python's round() does (design/model.py priced every level with it).
function Economy.round(x: number): number
	local f = math.floor(x)
	local diff = x - f
	if diff > 0.5 then return f + 1 end
	if diff < 0.5 then return f end
	return if f % 2 == 0 then f else f + 1
end

function Economy.buildPrice(cfg: any, t: number): number
	return cfg.Stations.BuildPrice[t]
end

function Economy.twinPrice(cfg: any, t: number): number
	return Economy.round(cfg.Stations.TwinPrice * cfg.Stations.UpgradeBase[t])
end

function Economy.upPrice(cfg: any, t: number, level: number): number
	local S = cfg.Stations
	return Economy.round(S.UpgradeBase[t] * S.UpgradeGrowth ^ (level - 1))
end

-- Every purchase the line panel lists, affordable or not, in belt order (per station: build, or twin then up).
function Economy.candidates(cfg: any, S: { any }): { any }
	local out = {}
	for t = 1, 6 do
		local s = S[t]
		if s.n == 0 then
			if t == 1 or S[t - 1].n > 0 then
				table.insert(out, { kind = "build", t = t, price = Economy.buildPrice(cfg, t) })
			end
			continue
		end
		if s.n == 1 then
			table.insert(out, { kind = "twin", t = t, price = Economy.twinPrice(cfg, t) })
		end
		if s.L < cfg.Stations.MaxLevel then
			table.insert(out, { kind = "up", t = t, price = Economy.upPrice(cfg, t, s.L) })
		end
	end
	return out
end

-- Income after purchase `a`, jams ignored (the ★ plans for a working line).
function Economy.preview(cfg: any, Line: any, S: { any }, a: any, mult: number): number
	local copy = {}
	for t = 1, 6 do
		copy[t] = { n = S[t].n, L = S[t].L, jam = { 0, 0 } }
	end
	if a.kind == "build" or a.kind == "twin" then
		copy[a.t].n += 1
	elseif a.kind == "up" then
		copy[a.t].L += 1
	end
	return (Line.income(cfg, copy, mult, true))
end

-- (ok, why, price, t). Refusals: unknown, locked, built, unbuilt, twinned, maxlevel, cash. Changes nothing.
function Economy.check(cfg: any, d: any, kind: any, id: any): (boolean, string, number?, number?)
	if type(kind) ~= "string" or (kind ~= "build" and kind ~= "twin" and kind ~= "up") then
		return false, "unknown", nil, nil
	end
	local t = nil
	for i, sid in cfg.Stations.Order do
		if sid == id then t = i end
	end
	if t == nil then return false, "unknown", nil, nil end
	local st = d.stations[id]
	if type(st) ~= "table" then return false, "unknown", nil, nil end
	local price: number
	if kind == "build" then
		if st.n > 0 then return false, "built", nil, t end
		if t > 1 and d.stations[cfg.Stations.Order[t - 1]].n == 0 then return false, "locked", nil, t end
		price = Economy.buildPrice(cfg, t)
	elseif kind == "twin" then
		if st.n == 0 then return false, "unbuilt", nil, t end
		if st.n >= 2 then return false, "twinned", nil, t end
		price = Economy.twinPrice(cfg, t)
	else
		if st.n == 0 then return false, "unbuilt", nil, t end
		if st.L >= cfg.Stations.MaxLevel then return false, "maxlevel", nil, t end
		price = Economy.upPrice(cfg, t, st.L)
	end
	if not finite(d.cash) or d.cash < price then return false, "cash", price, t end
	return true, "ok", price, t
end

-- The purchase. Every check happens before the first assignment, so a refusal changes nothing.
function Economy.buy(cfg: any, d: any, kind: any, id: any): (boolean, string, number?, number?)
	local ok, why, price, t = Economy.check(cfg, d, kind, id)
	if not ok then return false, why, price, t end
	local st = d.stations[id]
	d.cash -= price :: number
	if kind == "build" or kind == "twin" then
		st.n += 1
	else
		st.L += 1
	end
	return true, "ok", price, t
end

-- The HUD's ★ (DESIGN 4.5). Returns { kind, t, price, rule, saving } or nil when nothing is left to buy.
function Economy.star(cfg: any, Line: any, S: { any }, cash: number, mult: number): any?
	local cands = Economy.candidates(cfg, S)
	if #cands == 0 then return nil end
	local now = (Line.income(cfg, S, mult, true))
	local c = if finite(cash) then cash else 0
	-- rule 0: the next station
	for _, a in cands do
		if a.kind == "build" then
			if a.price <= c then
				return { kind = a.kind, t = a.t, price = a.price, rule = 0, saving = false }
			end
			if (a.price - c) / math.max(now, 1e-9) <= cfg.Star.SaveWindow then
				return { kind = a.kind, t = a.t, price = a.price, rule = 0, saving = true }
			end
		end
	end
	return Economy.starPayback(cfg, Line, S, c, mult)
end

-- Rules 1 and 2 alone (the ★ without "save for the next station"). The pacing model's `saver` profile plays
-- this to measure what rule 0 is worth (DESIGN 4.5: without it the first Gear came at 43.9 min [M2]).
function Economy.starPayback(cfg: any, Line: any, S: { any }, cash: number, mult: number): any?
	local cands = Economy.candidates(cfg, S)
	if #cands == 0 then return nil end
	local now = (Line.income(cfg, S, mult, true))
	local c = if finite(cash) then cash else 0
	-- rule 1: the target with the best wait + payback
	local best, bestScore = nil, math.huge
	local scored = {}
	for _, a in cands do
		local gain = Economy.preview(cfg, Line, S, a, mult) - now
		if gain > 1e-12 then
			local payback = a.price / gain
			local wait = math.max(0, a.price - c) / math.max(now, 1e-9)
			table.insert(scored, { a = a, payback = payback })
			local score = wait + payback
			if score < bestScore - 1e-9 or (best ~= nil and math.abs(score - bestScore) <= 1e-9 and a.price < best.price) then
				best, bestScore = a, score
			end
		end
	end
	if best == nil then
		-- nothing adds income: the cheapest thing on the list
		local cheapest = cands[1]
		for _, a in cands do
			if a.price < cheapest.price then cheapest = a end
		end
		return { kind = cheapest.kind, t = cheapest.t, price = cheapest.price, rule = 1, saving = false }
	end
	-- rule 2: a filler while saving
	if best.price > c then
		local wait = (best.price - c) / math.max(now, 1e-9)
		local filler, fp = nil, math.huge
		for _, sc in scored do
			if sc.a.price <= c and sc.payback < wait then
				if sc.payback < fp or (sc.payback == fp and filler ~= nil and sc.a.price < filler.price) then
					filler, fp = sc.a, sc.payback
				end
			end
		end
		if filler then
			return { kind = filler.kind, t = filler.t, price = filler.price, rule = 2, saving = false }
		end
	end
	return { kind = best.kind, t = best.t, price = best.price, rule = 1, saving = false }
end

-- What the panel paints GREEN when affordable (REVIEW-2 R3): a set keyed "kind:t". Empty while the ★ saves for the
-- next station (rule 0): nothing but the ★ (gold) invites a tap then. Otherwise the next station's build, and every
-- purchase that adds income and pays for itself within Star.GreenPayback x the best payback on the list. Plans for a
-- working line, as the ★ does. Affordability is the caller's (the HUD compares cash and price).
function Economy.worth(cfg: any, Line: any, S: { any }, cash: number, mult: number): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local star = Economy.star(cfg, Line, S, cash, mult)
	if star ~= nil and star.saving then return out end
	local cands = Economy.candidates(cfg, S)
	local now = (Line.income(cfg, S, mult, true))
	local pay: { [number]: number } = {}
	local best = math.huge
	for i, a in cands do
		local gain = Economy.preview(cfg, Line, S, a, mult) - now
		if gain > 1e-12 then
			pay[i] = a.price / gain
			best = math.min(best, pay[i])
		end
	end
	for i, a in cands do
		if a.kind == "build" or (pay[i] ~= nil and pay[i] <= cfg.Star.GreenPayback * best + 1e-9) then
			out[a.kind .. ":" .. a.t] = true
		end
	end
	return out
end

-- Seconds of income until the starred purchase is affordable (0 when it already is).
function Economy.saveSeconds(cfg: any, Line: any, S: { any }, cash: number, mult: number, star: any?): number
	if star == nil then return 0 end
	local now = (Line.income(cfg, S, mult, true))
	return math.max(0, star.price - cash) / math.max(now, 1e-9)
end

--============================================================================ texts
local SUFFIX = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Economy.short(n: number): string
	if not finite(n) or n <= 0 then return "0" end
	if n < 1000 then return tostring(math.floor(n)) end
	local i = 0
	local v = n
	while v >= 1000 and i < #SUFFIX do
		v /= 1000
		i += 1
	end
	if v < 100 then
		local t = math.floor(v * 10) / 10
		return string.format("%.1f%s", t, SUFFIX[i])
	end
	return string.format("%d%s", math.floor(v), SUFFIX[i])
end

function Economy.money(n: number): string
	return "$" .. Economy.short(n)
end

-- A per-second rate: one decimal under 10, compact above.
function Economy.rate(n: number): string
	if not finite(n) or n <= 0 then return "0" end
	if n < 10 then return string.format("%.1f", math.floor(n * 10) / 10) end
	return Economy.short(n)
end

function Economy.clock(seconds: number): string
	local s = if finite(seconds) then math.max(0, math.ceil(seconds)) else 0
	return string.format("%d:%02d", s // 60, s % 60)
end

function Economy.refusalText(cfg: any, why: string?, price: number?, cash: number?, t: number?): string
	local names = cfg.Stations.Names
	if why == "cash" then
		return string.format("Need %s, you have %s", Economy.short(price or 0), Economy.short(cash or 0))
	elseif why == "locked" and t then
		return "Build a " .. names[t - 1] .. " first"
	elseif why == "unbuilt" and t then
		return "Build the " .. names[t] .. " first"
	elseif why == "built" and t then
		return "Your " .. names[t] .. " is already built"
	elseif why == "twinned" then
		return "This station already has its twin"
	elseif why == "maxlevel" and t then
		return "The " .. names[t] .. " is at its top level"
	elseif why == "loading" then
		return "Loading your factory…"
	elseif why == "recycling" then
		return "Recycling… one moment"
	end
	return "That isn't a machine"
end

return Economy
