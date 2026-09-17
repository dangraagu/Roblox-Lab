--!nocheck
-- M3: whole runs. Battery carries between sublevels; cells refill it; the front tightens with depth.
-- Reports P(clear sublevel k) for three explorer speeds, for a few parameter sets.
local S = require("./sim")
local RUNS = 1500
local LEAD = 2
local MAXSUB = 14

local function shape(k)
	if k <= 2 then return 4, 3, 2 end
	if k <= 5 then return 5, 4, 3 end
	return 6, 5, 3
end

local function slack(k, P)
	return P.smin + (P.s1 - P.smin) * (1 + (k - 1) / P.K) ^ (-P.e)
end

-- returns sublevels cleared, seconds on floors, per-floor seconds list
local function run(seedBase, speed, P)
	local battery = P.cap
	local cleared, secs, per = 0, 0, {}
	for k = 1, MAXSUB do
		local n, f, b = shape(k)
		local ls = (seedBase * 131 + k * 7919) % 4294967296
		local p = S.plan(n, ls, (ls * 7 + 12345) % 4294967296, f, b + (P.scav or 0), k == 1)
		local base = S.explore(p, {})
		local step = slack(k, P) * base.t / (p.maxD + LEAD)
		local r = S.explore(p, {
			speed = speed,
			front = { lead = LEAD * step, step = step },
			battery = { cap = P.cap, start = battery, cell = P.cell, grace = P.grace, recover = 1 },
		})
		secs += r.t
		per[k] = r.t
		if r.died then return cleared, secs, per end
		cleared = k
		battery = r.battery
	end
	return cleared, secs, per
end

local M = { run = run, slack = slack, shape = shape, RUNS = RUNS, MAXSUB = MAXSUB }

if not _G.__M3_LIB then
	local sets = {
		{ name = "A cap45 cell15 g4 s2.0->1.1", cap = 45, cell = 15, grace = 4, s1 = 2.0, smin = 1.1, K = 3, e = 1 },
		{ name = "B cap60 cell20 g4 s2.0->1.1", cap = 60, cell = 20, grace = 4, s1 = 2.0, smin = 1.1, K = 3, e = 1 },
		{ name = "C cap60 cell20 g4 s2.5->1.2", cap = 60, cell = 20, grace = 4, s1 = 2.5, smin = 1.2, K = 3, e = 1 },
		{ name = "D cap90 cell30 g4 s2.0->1.1", cap = 90, cell = 30, grace = 4, s1 = 2.0, smin = 1.1, K = 3, e = 1 },
	}
	for _, P in sets do
		print("== " .. P.name .. "   slack k=1..8: " .. string.format("%.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f",
			slack(1, P), slack(2, P), slack(3, P), slack(4, P), slack(5, P), slack(6, P), slack(7, P), slack(8, P)))
		for _, sp in { 16, 12.8, 10.4 } do
			local reach = {}
			for k = 0, MAXSUB do reach[k] = 0 end
			local depthSum = 0
			for i = 1, RUNS do
				local c = run(i, sp, P)
				for k = 0, c do reach[k] += 1 end
				depthSum += c
			end
			local line = string.format("  v%4.1f  mean cleared %.2f | P(clear k): ", sp, depthSum / RUNS)
			for k = 1, 10 do line ..= string.format("%d:%.2f ", k, reach[k] / RUNS) end
			print(line)
		end
	end
end
return M
