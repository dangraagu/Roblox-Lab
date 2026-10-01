-- cumulative minutes of daily play until a medal; hazard near-miss rate per minute of running
local M = require("./maze")
local X = require("./model")
local W, H, LOOPS = 9, 9, 8
local MULTS = { silver = 1.6, gold = 1.25, sealer = 1.10 }
local ORDER = { "silver", "gold", "sealer" }
local PLAYERS = 120
local MAXDAYS = 14

local HZ_SETS = {
	{ name = "3 cells, 18 s cycle, 1 on route", count = 3, period = 18, grace = 6, near = 0.4, minE = 3, sep = 4, onRoute = true },
}

for _, pname in { "fast", "normal", "slow" } do
	local prof = X.PROFILES[pname]
	local cum = { silver = {}, gold = {}, sealer = {} }
	local days = { silver = {}, gold = {}, sealer = {} }
	local neverIn = { silver = 0, gold = 0, sealer = 0 }
	local nearRate = {}
	for _ = 1, #HZ_SETS do table.insert(nearRate, { near = 0, running = 0 }) end
	for pl = 1, PLAYERS do
		local total = 0
		local got = {}
		for d = 1, MAXDAYS do
			local dr = M.rng(pl * 1000003 + d * 7919)
			local day
			repeat day = X.makeDay(W, H, LOOPS, dr, HZ_SETS[1]) until day.perfect >= 22 and day.perfect <= 34
			local thr = {}
			for i, k in ORDER do thr[i] = day.perfect * MULTS[k] end
			local res = X.day(day.m, day.p, prof, M.rng(pl * 31 + d * 17), thr, prof.sessionMin, day.hazards, HZ_SETS[1])
			for i, k in ORDER do
				if not got[k] and res.reached[i] then
					got[k] = true
					table.insert(cum[k], (total + res.reached[i]) / 60)
					table.insert(days[k], d)
				end
			end
			total += res.clock
			-- hazard variants on the same day and the same player RNG
			for hi, hz in HZ_SETS do
				local hazards = X.placeHazards(day.m, day.p, day.r.cells, hz, M.rng(pl * 77 + d))
				local r2 = X.day(day.m, day.p, prof, M.rng(pl * 31 + d * 17), thr, prof.sessionMin, hazards, hz)
				nearRate[hi].near += r2.near
				nearRate[hi].running += r2.running
			end
		end
		for _, k in ORDER do if not got[k] then neverIn[k] += 1 end end
	end
	print(string.format("%s (sessions of %d min per UTC day, %d players, up to %d days):", pname, prof.sessionMin, PLAYERS, MAXDAYS))
	for _, k in ORDER do
		print(string.format("   first %-6s (x%.2f perfect line): cumulative play min p10 %.1f p50 %.1f p90 %.1f | on day p50 %d p90 %d | not within %d days: %d",
			k, MULTS[k], X.pct(cum[k], 0.1), X.pct(cum[k], 0.5), X.pct(cum[k], 0.9), X.pct(days[k], 0.5), X.pct(days[k], 0.9), MAXDAYS, neverIn[k]))
	end
	for hi, hz in HZ_SETS do
		local perMin = nearRate[hi].near / (nearRate[hi].running / 60)
		print(string.format("   hazards [%s]: %.3f near-misses per running minute (one per %.1f min)", hz.name, perMin, 1 / perMin))
	end
end
