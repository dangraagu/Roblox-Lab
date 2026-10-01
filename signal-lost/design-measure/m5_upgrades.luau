--!nocheck
-- M5: what each rank buys, one upgrade at a time, medium and slow profiles.
local S = require("./station")
local N = 1000
print("M5 upgrade value, " .. N .. " plans per row: P(splice) and T p50 (s), medium | slow")
for _, k in { 10, 23, 40 } do
	for _, st in {
		{ "none", 0, 0 }, { "tank 1", 1, 0 }, { "tank 2", 2, 0 }, { "tank 3", 3, 0 }, { "tank 4", 4, 0 },
		{ "boots 1", 0, 1 }, { "boots 2", 0, 2 }, { "boots 3", 0, 3 }, { "boots 4", 0, 4 }, { "both 4", 4, 4 },
	} do
		local res = {}
		for _, name in { "medium", "slow" } do
			local ok, T = 0, {}
			for i = 1, N do
				local p = S.plan(k, S.seedsFor(i, 7000 + k))
				local r = S.run(p, S.PROFILES[name], { tank = st[2], boots = st[3] }, S.lcg01(13 * i + k))
				if r.ok then ok += 1; table.insert(T, r.t) end
			end
			res[name] = string.format("%.3f %5.1f", ok / N, S.pct(T, 0.5))
		end
		print(string.format("k=%-2d %-8s | %s | %s", k, st[1], res.medium, res.slow))
	end
end
