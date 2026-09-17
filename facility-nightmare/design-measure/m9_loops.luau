--!nocheck
-- M9: ExtraDoorChance 0 / 0.2 / 0.4 — dead-end share, model floor time, and run depth for the slow proxy.
local S = require("./sim")
local LEAD = 2
local function slack(k) return 1.0 + (2.0 - 1.0) * (1 + (k - 1) / 4) ^ (-1) end
local function shape(k)
	if k <= 3 then return 4, 3, 2 end
	if k <= 8 then return 5, 4, 2 end
	return 5, 5, 1
end
for _, chance in { 0, 0.2, 0.4 } do
	local cfg = {}
	for k, v in S.CFG do cfg[k] = v end
	cfg.ExtraDoorChance = chance
	local deadEnds, t4, t5 = {}, {}, {}
	for i = 1, 2000 do
		for _, n in { 4, 5 } do
			local p = S.plan(n, i * 131 + n, i * 977 + n, n == 4 and 3 or 4, 2, false, cfg)
			local de = 0
			for r = 1, p.n2 do if #p.adj[r] == 1 then de += 1 end end
			table.insert(deadEnds, de / p.n2)
			local base = S.explore(p, {}, cfg)
			table.insert(n == 4 and t4 or t5, base.t)
		end
	end
	local line = string.format("chance %.1f | dead-end rooms %.0f%% | model s 4x4 p50 %.1f 5x5 p50 %.1f |", chance,
		100 * S.mean(deadEnds), S.pct(t4, 0.5), S.pct(t5, 0.5))
	for _, sp in { 12.8, 10.4 } do
		local depths = {}
		for i = 1, 800 do
			local battery, c = 45, 0
			for k = 1, 30 do
				local n, f, b = shape(k)
				local ls = (i * 131 + k * 7919) % 4294967296
				local p = S.plan(n, ls, (ls * 7 + 12345) % 4294967296, f, b, k == 1, cfg)
				local base = S.explore(p, {}, cfg)
				local step = slack(k) * base.t / (p.maxD + LEAD)
				local r = S.explore(p, { speed = sp, front = { lead = LEAD * step, step = step },
					battery = { cap = 45, start = battery, cell = 15, grace = 4, recover = 1 } }, cfg)
				if r.died then break end
				c = k; battery = r.battery
			end
			table.insert(depths, c)
		end
		line ..= string.format(" v%.1f cleared p50 %d mean %.2f |", sp, S.pct(depths, 0.5), S.mean(depths))
	end
	print(line)
end
