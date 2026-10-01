local M = require("./maze")
local X = require("./model")
local HZ = { count = 3, period = 18, grace = 6, near = 0.4, minE = 3, sep = 4, onRoute = true }
local MULTS = { 1.6, 1.25, 1.10 }
for _, pname in { "fast", "normal", "slow" } do
	local prof = X.PROFILES[pname]
	local got = { 0, 0, 0 }
	local days = 0
	for pl = 1, 60 do
		for d = 1, 10 do
			local dr = M.rng(pl * 1000003 + d * 7919)
			local day
			repeat day = X.makeDay(9, 9, 8, dr, HZ) until day.perfect >= 22 and day.perfect <= 34
			local thr = { day.perfect * MULTS[1], day.perfect * MULTS[2], day.perfect * MULTS[3] }
			local res = X.day(day.m, day.p, prof, M.rng(pl * 31 + d * 17), thr, prof.sessionMin, day.hazards, HZ)
			days += 1
			for i = 1, 3 do if res.reached[i] then got[i] += 1 end end
		end
	end
	print(string.format("%s, %d-min sessions, %d days: silver on %.0f%%, gold on %.0f%%, sealer on %.0f%% of days",
		pname, prof.sessionMin, days, got[1] / days * 100, got[2] / days * 100, got[3] / days * 100))
end
