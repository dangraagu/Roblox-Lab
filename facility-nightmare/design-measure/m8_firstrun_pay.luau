--!nocheck
-- M8: first-ever run, no perks, pushes until death (never extracts). Sublevel-1 time to the elevator,
-- sublevels cleared, and Essence banked at 25% of 10 + 5*(k-1) per cleared sublevel.
local S = require("./sim")
local LEAD = 2
local N = 2000
local function slack(k) return 1.0 + (2.0 - 1.0) * (1 + (k - 1) / 4) ^ (-1) end
local function shape(k)
	if k <= 3 then return 4, 3, 2 end
	if k <= 8 then return 5, 4, 2 end
	return 5, 5, 1
end
local function cum(k) local s = 0 for j = 1, k do s += 10 + 5 * (j - 1) end return s end
for _, sp in { 16, 10.4, 8 } do
	local t1, cleared, bank, runSecs = {}, {}, {}, {}
	for i = 1, N do
		local battery = 45
		local c, secs = 0, 0
		for k = 1, 30 do
			local n, f, b = shape(k)
			local ls = (i * 131 + k * 7919) % 4294967296
			local p = S.plan(n, ls, (ls * 7 + 12345) % 4294967296, f, b, k == 1)
			local base = S.explore(p, {})
			local step = slack(k) * base.t / (p.maxD + LEAD)
			local hold = 0
			if k == 1 then hold = S.explore(p, { speed = sp }).firstFuseT end
			local r = S.explore(p, { speed = sp, front = { lead = hold + LEAD * step, step = step },
				battery = { cap = 45, start = battery, cell = 15, grace = 4, recover = 1 } })
			secs += r.t
			if k == 1 and not r.died then table.insert(t1, r.t) end
			if r.died then break end
			c = k
			battery = r.battery
			secs += 4
		end
		table.insert(cleared, c); table.insert(bank, math.floor(0.25 * cum(c))); table.insert(runSecs, secs + 15)
	end
	print(string.format("v%4.1f  sublevel-1 seconds to elevator p10 %.0f p50 %.0f p90 %.0f | cleared p10 %d p50 %d p90 %d | banked p10 %d p50 %d p90 %d | run min p50 %.1f",
		sp, S.pct(t1, 0.1), S.pct(t1, 0.5), S.pct(t1, 0.9), S.pct(cleared, 0.1), S.pct(cleared, 0.5), S.pct(cleared, 0.9),
		S.pct(bank, 0.1), S.pct(bank, 0.5), S.pct(bank, 0.9), S.pct(runSecs, 0.5) / 60))
end
