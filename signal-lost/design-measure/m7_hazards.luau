--!nocheck
-- M7: how often a hazard comes. The hazard clock runs only in a breached module, in a band that has
-- hazards (hydroponics onward), after a sector's first ArrivalGraceSeconds, and while O2 >= LowO2Seconds.
-- It freezes everywhere else and never resets (the plus1-jump rule). Campaign timelines from M3's model.
local S = require("./station")
local RUNS = 200
print("M7 hazard rate over " .. RUNS .. " campaigns per profile, capped at 61 sectors / 240 min")
for _, iv in { { 60, 90 }, { 80, 120 }, { 100, 150 } } do
	for _, name in { "fast", "medium", "slow" } do
		local bandPlay, bandHaz, bandElig = {}, {}, {}
		local totalPlay, totalHaz, totalElig = 0, 0, 0
		for s = 1, RUNS do
			local c = S.campaign(S.PROFILES[name], S.ECON, { cfg = S.CFG, schedule = S.schedule, overhead = S.OVERHEAD,
				maxSector = 61, maxSeconds = 240 * 60 }, s)
			local rng = S.lcg01(s * 31 + 7)
			local clock, nextAt = 0, iv[1] + (iv[2] - iv[1]) * rng()
			for _, e in c.log do
				local b = S.bandOf(e.k)
				local play = e.dur + (if e.ok then S.OVERHEAD.transit else S.OVERHEAD.blackout)
				bandPlay[b] = (bandPlay[b] or 0) + play
				if b >= 2 then
					totalPlay += play
					clock += e.eligible
					totalElig += e.eligible
					bandElig[b] = (bandElig[b] or 0) + e.eligible
					while clock >= nextAt do
						bandHaz[b] = (bandHaz[b] or 0) + 1
						totalHaz += 1
						nextAt += iv[1] + (iv[2] - iv[1]) * rng()
					end
				end
			end
		end
		local parts = {}
		for b = 2, #S.BANDS do
			if bandPlay[b] and bandPlay[b] > 0 then
				table.insert(parts, string.format("%s %.1f", S.BANDS[b].id, (bandPlay[b] / 60) / math.max(bandHaz[b] or 0, 1e-9)))
			end
		end
		print(string.format("interval %d-%d s  %-6s | one hazard per %.2f min of play in hazard bands | exposed share of that play %.2f | per band (min of play per hazard): %s",
			iv[1], iv[2], name, (totalPlay / 60) / totalHaz, totalElig / totalPlay, table.concat(parts, "  ")))
	end
end
