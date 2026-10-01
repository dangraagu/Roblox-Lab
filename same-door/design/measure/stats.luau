local M = require("./maze")
local CELL, WALK, MARGIN = 16, 16, 2.5
local RULES = { sealAMin = 3, sealAMax = 6, sealMin = 6, sealSep = 6, doorFrac = 0.6, doorSealSep = 4 }

local function pct(t, p)
	table.sort(t)
	return t[math.max(1, math.floor(#t * p + 0.5))]
end
local function mean(t)
	local s = 0
	for _, v in t do s += v end
	return s / #t
end

local function trial(W, H, loops, seed)
	local rng = M.rng(seed)
	local entrance = { W // 2, 0 }
	for attempt = 1, 50 do
		local m = M.generate(W, H, loops, rng, entrance)
		local e = entrance[2] * W + entrance[1]
		local p = M.place(m, e, RULES, rng)
		if p then
			local r = M.route(m, p)
			-- funnel: start line point -> seals -> door centre
			local startPt = { x = (entrance[1] + 0.5) * CELL, y = 0 }
			local total = 0
			for k = 1, 4 do
				local a, b = r.waypointAt[k], r.waypointAt[k + 1]
				local seg = {}
				for j = a, b do table.insert(seg, r.cells[j]) end
				local s = if k == 1 then startPt else M.centre(m, r.cells[a], CELL)
				local en = M.centre(m, r.cells[b], CELL)
				total += M.funnel(m, seg, s, en, CELL, MARGIN, false)
			end
			local parSeconds = (r.steps + 0.5) * CELL / WALK
			-- unique cells on route
			local u, n = {}, 0
			for _, c in r.cells do if not u[c] then u[c] = true; n += 1 end end
			return { steps = r.steps, par = parSeconds, funnel = total / WALK, ratio = (total / WALK) / parSeconds,
				routeCells = n, cells = W * H, attempts = attempt, maxE = p.maxE }
		end
	end
	return nil
end

for _, cfg in { { 7, 7, 4 }, { 8, 8, 6 }, { 9, 9, 8 }, { 9, 9, 12 }, { 10, 10, 10 }, { 11, 11, 12 } } do
	local W, H, loops = cfg[1], cfg[2], cfg[3]
	local par, fun, ratio, cover, fails, att = {}, {}, {}, {}, 0, {}
	for s = 1, 2000 do
		local t = trial(W, H, loops, s * 7919 + W * 131 + loops)
		if t then
			table.insert(par, t.par); table.insert(fun, t.funnel); table.insert(ratio, t.ratio)
			table.insert(cover, t.routeCells / t.cells); table.insert(att, t.attempts)
		else
			fails += 1
		end
	end
	print(string.format("%dx%d loops %d: n=%d fails=%d | par s p10 %.1f p50 %.1f p90 %.1f mean %.1f | funnel s p10 %.1f p50 %.1f p90 %.1f | funnel/par min %.3f p10 %.3f p50 %.3f max %.3f | route covers %.0f%% of cells | placement attempts max %d",
		W, H, loops, #par, fails, pct(par, 0.1), pct(par, 0.5), pct(par, 0.9), mean(par), pct(fun, 0.1), pct(fun, 0.5), pct(fun, 0.9),
		pct(ratio, 0.0), pct(ratio, 0.1), pct(ratio, 0.5), pct(ratio, 1.0), mean(cover) * 100, pct(att, 1.0)))
end
