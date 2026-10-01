local M = require("./maze")
local X = require("./model")
local SETS = {
	{ name = "3 random, 12 s", count = 3, period = 12, grace = 6, near = 0.4, minE = 3, sep = 4, onRoute = false },
	{ name = "4 random, 16 s", count = 4, period = 16, grace = 6, near = 0.4, minE = 3, sep = 4, onRoute = false },
	{ name = "4 random, 18 s", count = 4, period = 18, grace = 6, near = 0.4, minE = 3, sep = 3, onRoute = false },
	{ name = "5 random, 20 s", count = 5, period = 20, grace = 6, near = 0.4, minE = 3, sep = 3, onRoute = false },
}
local MULTS = { 1.6, 1.25, 1.10 }
for _, pname in { "fast", "normal", "slow" } do
	local prof = X.PROFILES[pname]
	local acc = {}
	local placed = {}
	for i = 1, #SETS do acc[i] = { near = 0, run = 0 }; placed[i] = {} end
	for pl = 1, 60 do
		for d = 1, 8 do
			local dr = M.rng(pl * 1000003 + d * 7919)
			local day
			repeat day = X.makeDay(9, 9, 8, dr, SETS[1]) until day.perfect >= 22 and day.perfect <= 34
			local thr = { day.perfect * MULTS[1], day.perfect * MULTS[2], day.perfect * MULTS[3] }
			for i, hz in SETS do
				local hazards = X.placeHazards(day.m, day.p, day.r.cells, hz, M.rng(pl * 77 + d))
				table.insert(placed[i], #hazards)
				local res = X.day(day.m, day.p, prof, M.rng(pl * 31 + d * 17), thr, prof.sessionMin, hazards, hz)
				acc[i].near += res.near; acc[i].run += res.running
			end
		end
	end
	for i, hz in SETS do
		local r = acc[i].near / (acc[i].run / 60)
		print(string.format("%-6s [%s]: %.3f near-misses/running min (one per %.1f min); cells placed min %d", pname, hz.name, r, 1 / r, X.pct(placed[i], 0)))
	end
end
