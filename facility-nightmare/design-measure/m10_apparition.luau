--!nocheck
-- M10: "the first door on a sublevel that opens into an already-dark room" — how often does it happen,
-- and when? Sublevel 1 (first-ever run, front held) and sublevels 2 / 4.
local S = require("./sim")
local LEAD = 2
local function slack(k) return 1.0 + (2.0 - 1.0) * (1 + (k - 1) / 4) ^ (-1) end
local N = 2000
for _, case in { { k = 1, n = 4, f = 3, b = 2, held = true }, { k = 2, n = 4, f = 3, b = 2 }, { k = 4, n = 5, f = 4, b = 2 } } do
	for _, sp in { 16, 10.4, 8 } do
		local hit, times = 0, {}
		for i = 1, N do
			local ls = (i * 131 + case.k * 7919) % 4294967296
			local p = S.plan(case.n, ls, (ls * 7 + 12345) % 4294967296, case.f, case.b, case.k == 1)
			local base = S.explore(p, {})
			local step = slack(case.k) * base.t / (p.maxD + LEAD)
			local hold = case.held and S.explore(p, { speed = sp }).firstFuseT or 0
			local r = S.explore(p, { speed = sp, front = { lead = hold + LEAD * step, step = step } })
			if r.firstDarkBehind then hit += 1; table.insert(times, r.firstDarkBehind) end
		end
		print(string.format("sublevel %d%s v%4.1f | floors where a walked-through room is dark next to a LIT player room %.0f%% | at s p50 %.1f p90 %.1f",
			case.k, case.held and " (first run, held)" or "", sp, 100 * hit / N,
			#times > 0 and S.pct(times, 0.5) or -1, #times > 0 and S.pct(times, 0.9) or -1))
	end
end
