--!nocheck
-- M8: is leaving a sector early (return pod / blackout / rejoin) ever a better income than splicing?
-- Normal: carried * value + bonus over the attempt plus transit. Farmer: walks to the FIRST salvage it
-- finds, walks straight back to the dock (same time again, optimistic: no O2 cost counted), rides the
-- return pod and the lift back (7 s) into a freshly generated sector, and banks keep * value.
local S = require("./station")
local N = 1500
print("M8 farming vs splicing, " .. N .. " plans per row, salvage per minute (p50 of per-attempt rates)")
for _, k in { 5, 10, 23, 40 } do
	for _, name in { "fast", "medium" } do
		local normal, farm = {}, {}
		for i = 1, N do
			local p = S.plan(k, S.seedsFor(i, 4000 + k))
			local r = S.run(p, S.PROFILES[name], { tank = 2, boots = 2 }, S.lcg01(7 * i + k))
			if r.ok then
				table.insert(normal, (r.carried * S.ECON.value(k) + S.ECON.bonus(k)) / ((r.t + S.OVERHEAD.transit) / 60))
			end
			if r.firstSalvT then
				local cycle = 2 * r.firstSalvT + 7
				table.insert(farm, S.ECON.keep * S.ECON.value(k) / (cycle / 60))
			end
		end
		print(string.format("k=%-2d %-6s | splicing %.1f/min | farming the first salvage %.1f/min | ratio %.2f", k, name,
			S.pct(normal, 0.5), S.pct(farm, 0.5), S.pct(normal, 0.5) / S.pct(farm, 0.5)))
	end
end
