--!nocheck
-- M1: one sector attempt with no upgrades, per schedule step and profile.
local S = require("./station")
local N = 2000
print("M1 sector attempt, no upgrades, " .. N .. " plans per row (seeds S.seedsFor(i, k), noise lcg01(9001 i + k))")
print("k  n  prof   | P(splice) | T p10 p50 p90 (s) | vac% time | visited% p50 | maxD p50/max | breached% | retreats | O2<25% | cand p50 | flips p50 | forced")
for _, k in { 1, 3, 5, 10, 16, 23, 30 } do
	for _, name in { "fast", "medium", "slow" } do
		local prof = S.PROFILES[name]
		local ok, T, V, VIS, D, B, R, C, F, low, FO = 0, {}, {}, {}, {}, {}, {}, {}, {}, 0, 0
		for i = 1, N do
			local p = S.plan(k, S.seedsFor(i, k))
			local r = S.run(p, prof, { tank = 0, boots = 0 }, S.lcg01(9001 * i + k))
			if r.ok then ok += 1; table.insert(T, r.t) end
			table.insert(V, r.vacT / math.max(r.t, 1e-9))
			table.insert(VIS, r.visited / p.n2)
			table.insert(D, p.maxD)
			table.insert(B, p.nVac / p.n2)
			table.insert(R, r.retreats)
			table.insert(C, p.nCand)
			table.insert(F, p.flips)
			if r.minO2 < 0.25 * r.tank then low += 1 end
			if p.forced then FO += 1 end
		end
		print(string.format("%-2d %d  %-6s | %.3f | %5.1f %5.1f %5.1f | %4.1f | %3.0f | %d/%d | %3.0f | %.2f | %.2f | %d | %d | %d",
			k, S.schedule(k).n, name, ok / N, S.pct(T, 0.1), S.pct(T, 0.5), S.pct(T, 0.9),
			100 * S.mean(V), 100 * S.pct(VIS, 0.5), S.pct(D, 0.5), S.pct(D, 1.0), 100 * S.mean(B), S.mean(R), low / N,
			S.pct(C, 0.5), S.pct(F, 0.5), FO))
	end
end
