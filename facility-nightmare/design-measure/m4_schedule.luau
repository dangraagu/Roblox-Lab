--!nocheck
-- M4: shape schedule capped at 5x5, slack decaying toward 1.0, cells thinning with depth.
-- Reports P(clear k) to 30 and the mean seconds a run lasts, for three explorer speeds and perk states.
local S = require("./sim")
local RUNS = 800
local LEAD = 2
local MAXSUB = 30

local function slack(k, P)
	return P.smin + (P.s1 - P.smin) * (1 + (k - 1) / P.K) ^ (-P.e)
end
local function shape(k, P)
	if k <= P.small then return 4, 3, P.cells1 end
	if k <= P.mid then return 5, 4, P.cells2 end
	return 5, 5, P.cells3
end

local function run(seedBase, speed, P)
	local battery = P.cap
	local cleared, secs = 0, 0
	for k = 1, MAXSUB do
		local n, f, b = shape(k, P)
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
		if r.died then return cleared, secs end
		cleared = k
		battery = r.battery
	end
	return cleared, secs
end

local base = { small = 3, mid = 8, cells1 = 2, cells2 = 2, cells3 = 1, cap = 45, cell = 15, grace = 4, s1 = 2.0, smin = 1.0, K = 4, e = 1 }
local function with(over)
	local t = {}
	for k, v in base do t[k] = v end
	for k, v in over do t[k] = v end
	return t
end
local sets = {
	{ "E  no perks", with({}) },
	{ "E+ battery perk max (cap 45+3*15=90)", with({ cap = 90 }) },
	{ "E+ night eyes max (grace 4+3*1.5=8.5)", with({ grace = 8.5 }) },
	{ "E+ scavenger max (+2 cells/floor)", with({ scav = 2 }) },
	{ "E+ all three maxed", with({ cap = 90, grace = 8.5, scav = 2 }) },
}
for _, s in sets do
	local name, P = s[1], s[2]
	print("== " .. name .. string.format("   slack 1/2/3/5/10/20/30: %.2f %.2f %.2f %.2f %.2f %.2f %.2f",
		slack(1, P), slack(2, P), slack(3, P), slack(5, P), slack(10, P), slack(20, P), slack(30, P)))
	for _, sp in { 16, 12.8, 10.4 } do
		local reach = {}
		for k = 0, MAXSUB do reach[k] = 0 end
		local depths, secsL = {}, {}
		for i = 1, RUNS do
			local c, secs = run(i, sp, P)
			for k = 0, c do reach[k] += 1 end
			table.insert(depths, c); table.insert(secsL, secs)
		end
		local line = string.format("  v%4.1f cleared p50 %2d mean %5.2f | run s p50 %4.0f | P: ", sp, S.pct(depths, 0.5), S.mean(depths), S.pct(secsL, 0.5))
		for _, k in { 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30 } do line ..= string.format("%d:%.2f ", k, reach[k] / RUNS) end
		print(line)
	end
end
