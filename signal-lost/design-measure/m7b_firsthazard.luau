--!nocheck
-- M7b: minute of play at which the first-ever hazard arrives, with and without a short first interval.
local S = require("./station")
local RUNS = 300
print("M7b first hazard, " .. RUNS .. " campaigns per row (interval 80-120 s of exposure after the first)")
for _, first in { 0, 30 } do
	for _, name in { "fast", "medium", "slow" } do
		local T, K = {}, {}
		for s = 1, RUNS do
			local c = S.campaign(S.PROFILES[name], S.ECON, { cfg = S.CFG, schedule = S.schedule, overhead = S.OVERHEAD,
				maxSector = 30, maxSeconds = 120 * 60 }, s)
			local rng = S.lcg01(s * 31 + 7)
			local nextAt = if first > 0 then first else 80 + 40 * rng()
			local clock = 0
			local elapsed = 0
			for _, e in c.log do
				local play = e.dur + (if e.ok then S.OVERHEAD.transit else S.OVERHEAD.blackout)
				if S.bandOf(e.k) >= 2 and e.eligible > 0 and clock + e.eligible >= nextAt then
					-- place it proportionally inside the attempt (exposure is spread over the attempt)
					local frac = (nextAt - clock) / e.eligible
					table.insert(T, (e.t0 + frac * e.dur) / 60)
					table.insert(K, e.k)
					break
				end
				if S.bandOf(e.k) >= 2 then clock += e.eligible end
			end
		end
		print(string.format("first interval %-9s %-6s | first hazard at minute p10/p50/p90 %.1f / %.1f / %.1f, in sector p50 %d (hydroponics starts at sector 5)",
			if first > 0 then first .. " s" else "80-120 s", name, S.pct(T, 0.1), S.pct(T, 0.5), S.pct(T, 0.9), S.pct(K, 0.5)))
	end
end
