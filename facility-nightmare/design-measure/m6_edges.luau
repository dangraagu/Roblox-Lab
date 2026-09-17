--!nocheck
-- M6: (a) front step seconds by shape at the slack values the schedule actually uses (min / p1 / p50);
--     (b) a much slower first-run proxy (8 studs/s) on sublevels 1-3 with no perks;
--     (c) time to first fuse and to first dark room for the onboarding floor at 16 / 10.4 / 8.
local S = require("./sim")
local LEAD = 2
local function slack(k) return 1.0 + (2.0 - 1.0) * (1 + (k - 1) / 4) ^ (-1) end
print(string.format("slack at k=1,3,4,8,9,30,100: %.3f %.3f %.3f %.3f %.3f %.3f %.3f", slack(1), slack(3), slack(4), slack(8), slack(9), slack(30), slack(100)))
local N = 3000
for _, c in { { 4, 3, 2, 1 }, { 4, 3, 2, 3 }, { 5, 4, 2, 4 }, { 5, 4, 2, 8 }, { 5, 5, 1, 9 }, { 5, 5, 1, 30 }, { 5, 5, 1, 100 } } do
	local n, f, b, k = c[1], c[2], c[3], c[4]
	local steps, leads = {}, {}
	for i = 1, N do
		local ls = (i * 131 + k * 7919) % 4294967296
		local p = S.plan(n, ls, (ls * 7 + 12345) % 4294967296, f, b, k == 1)
		local base = S.explore(p, {})
		local step = slack(k) * base.t / (p.maxD + LEAD)
		table.insert(steps, step); table.insert(leads, LEAD * step)
	end
	print(string.format("%dx%d F%d k=%3d slack %.3f | step min %.2f p1 %.2f p50 %.2f max %.2f", n, n, f, k, slack(k),
		S.pct(steps, 0), S.pct(steps, 0.01), S.pct(steps, 0.5), S.pct(steps, 1)))
end

-- (b) + (c)
for _, sp in { 16, 10.4, 8 } do
	local reach = { 0, 0, 0 }
	local ff, fd = {}, {}
	for i = 1, 2000 do
		local battery = 45
		for k = 1, 3 do
			local n, f, b = 4, 3, 2
			local ls = (i * 131 + k * 7919) % 4294967296
			local p = S.plan(n, ls, (ls * 7 + 12345) % 4294967296, f, b, k == 1)
			local base = S.explore(p, {})
			local step = slack(k) * base.t / (p.maxD + LEAD)
			local r = S.explore(p, { speed = sp, front = { lead = LEAD * step, step = step },
				battery = { cap = 45, start = battery, cell = 15, grace = 4, recover = 1 } })
			if k == 1 then
				table.insert(ff, r.firstFuseT or 999)
				-- first moment ANY room the explorer could be in goes dark = lead (entry room, d = 0)
				table.insert(fd, LEAD * step)
			end
			if r.died then break end
			reach[k] += 1
			battery = r.battery
		end
	end
	print(string.format("v%4.1f  P(clear 1/2/3) %.3f %.3f %.3f | sublevel 1: first fuse s p50 %.1f p90 %.1f | entry room goes dark at s p10 %.1f p50 %.1f",
		sp, reach[1] / 2000, reach[2] / 2000, reach[3] / 2000, S.pct(ff, 0.5), S.pct(ff, 0.9), S.pct(fd, 0.1), S.pct(fd, 0.5)))
end
