--!nocheck
-- M7: first-ever run only — the front on sublevel 1 is HELD until the first fuse is picked up.
-- Compares P(clear sublevel 1) with and without the hold for slow proxies.
local S = require("./sim")
local LEAD = 2
local N = 3000
for _, sp in { 10.4, 8, 6.4 } do
	local plain, held = 0, 0
	local darkStart = {}
	for i = 1, N do
		local ls = (i * 131 + 7919) % 4294967296
		local p = S.plan(4, ls, (ls * 7 + 12345) % 4294967296, 3, 2, true)
		local base = S.explore(p, {})
		local step = 2.0 * base.t / (p.maxD + LEAD)
		local bat = { cap = 45, cell = 15, grace = 4, recover = 1 }
		local a = S.explore(p, { speed = sp, front = { lead = LEAD * step, step = step }, battery = bat })
		if not a.died then plain += 1 end
		local ff = S.explore(p, { speed = sp }).firstFuseT
		local b = S.explore(p, { speed = sp, front = { lead = ff + LEAD * step, step = step }, battery = bat })
		if not b.died then held += 1 end
		table.insert(darkStart, ff + LEAD * step)
	end
	print(string.format("v%4.1f  P(clear sublevel 1): plain %.3f  held-until-first-fuse %.3f | first darkness at s p10 %.1f p50 %.1f",
		sp, plain / N, held / N, S.pct(darkStart, 0.1), S.pct(darkStart, 0.5)))
end
