--!nocheck
-- M3: whole campaigns. Minutes of play to reach each sector, deaths, purchases, per profile.
-- Usage: edit SCHED / ECON below, or require this file's `measure` from another script.
local S = require("./station")

local M = {}

M.schedule = S.schedule
M.econ = S.ECON
M.cfg = S.CFG
M.overhead = S.OVERHEAD

function M.measure(runs, maxSector, maxMinutes, label, cfg, econ, schedule, profiles)
	cfg = cfg or M.cfg
	econ = econ or M.econ
	schedule = schedule or M.schedule
	profiles = profiles or { "fast", "medium", "slow" }
	print("== " .. (label or "campaign") .. string.format(" (%d runs, cap %d sectors / %d min)", runs, maxSector, maxMinutes))
	local marks = { 5, 10, 16, 23, 30, 31, 40, 50, 60 }
	local out = {}
	for _, name in profiles do
		local prof = S.PROFILES[name]
		local at = {}
		for _, m in marks do at[m] = {} end
		local deaths, vacShare, buysFirst, ranksAt35, reached35 = {}, {}, {}, {}, {}
		local incomePerMin, allRanksAt, lowO2 = {}, {}, {}
		local deathsBy = {}
		local nth = {}
		for n = 1, 8 do nth[n] = {} end
		local bandAtt, bandLow, bandFail = {}, {}, {}
		local brag, echo = {}, {}
		for s = 1, runs do
			local c = S.campaign(prof, econ, { cfg = cfg, schedule = schedule, overhead = M.overhead,
				maxSector = maxSector, maxSeconds = maxMinutes * 60 }, s)
			for _, m in marks do
				if c.reachAt[m] then table.insert(at[m], c.reachAt[m] / 60) end
			end
			table.insert(deaths, c.deaths)
			if c.reachAt[S.BRAG + 1] then table.insert(brag, (c.reachAt[S.BRAG + 1] - M.overhead.transit) / 60) end
			if c.reachAt[60] then table.insert(echo, c.reachAt[60] / 60) end
			for n = 1, 8 do if c.buys[n] then table.insert(nth[n], c.buys[n].t / 60) end end
			for _, e in c.log do
				local b = S.bandOf(e.k)
				bandAtt[b] = (bandAtt[b] or 0) + 1
				if e.lowO2 then bandLow[b] = (bandLow[b] or 0) + 1 end
				if not e.ok then bandFail[b] = (bandFail[b] or 0) + 1 end
			end
			table.insert(incomePerMin, c.earned / (c.t / 60))
			if #c.buys == 8 then table.insert(allRanksAt, c.buys[8].t / 60) end
			table.insert(vacShare, c.vacTotal / (c.vacTotal + c.airTotal))
			if c.buys[1] then table.insert(buysFirst, c.buys[1].t / 60) end
			local ranks, best = 0, 1
			for _, b in c.buys do if b.t <= 35 * 60 then ranks += 1 end end
			for kk, tt in c.reachAt do if tt <= 35 * 60 and kk > best then best = kk end end
			table.insert(ranksAt35, ranks)
			table.insert(reached35, best)
			for kk, ps in c.perSector do
				deathsBy[kk] = deathsBy[kk] or { a = 0, n = 0 }
				deathsBy[kk].a += ps.attempts
				deathsBy[kk].n += 1
			end
		end
		local line = {}
		for _, m in marks do
			local list = at[m]
			if #list >= runs / 2 then
				table.insert(line, string.format("%d:%.1f", m, S.pct(list, 0.5)))
			else
				table.insert(line, string.format("%d:--(%d%%)", m, math.floor(100 * #list / runs)))
			end
		end
		print(string.format("%-6s sector:minutes p50  %s", name, table.concat(line, "  ")))
		print(string.format("       BRAG (relay %d spliced) at minute p10/p50/p90 %.1f / %.1f / %.1f (%d%% of runs) | THE ECHO (sector 60 entered) p50 %.1f min (%d%%)",
			S.BRAG, S.pct(brag, 0.1), S.pct(brag, 0.5), S.pct(brag, 0.9), math.floor(100 * #brag / runs), S.pct(echo, 0.5), math.floor(100 * #echo / runs)))
		print(string.format("       income p50 %.1f salvage/min | all 8 ranks by p50 %.1f min (%d%% of runs)",
			S.pct(incomePerMin, 0.5), S.pct(allRanksAt, 0.5), math.floor(100 * #allRanksAt / runs)))
		print(string.format("       deaths p50 %d | vacuum share of sector time %.2f | first purchase p50 %.1f min | ranks bought by 35 min p50 %d | sector at 35 min p10/p50/p90 %d/%d/%d",
			S.pct(deaths, 0.5), S.mean(vacShare), S.pct(buysFirst, 0.5), S.pct(ranksAt35, 0.5),
			S.pct(reached35, 0.1), S.pct(reached35, 0.5), S.pct(reached35, 0.9)))
		local att = {}
		for _, kk in { 1, 3, 6, 10, 12, 15, 20, 25, 30 } do
			local d = deathsBy[kk]
			if d then table.insert(att, string.format("%d:%.2f", kk, d.a / d.n)) end
		end
		print("       attempts per sector (mean): " .. table.concat(att, "  "))
		local pl = {}
		for n = 1, 8 do
			local ids = {}
			table.insert(pl, string.format("#%d %.1f", n, S.pct(nth[n], 0.5)))
		end
		print("       purchase n at minute p50: " .. table.concat(pl, "  "))
		local bl = {}
		for b = 1, #S.BANDS do
			if bandAtt[b] then
				table.insert(bl, string.format("%s: O2<25%% %.2f, blackout/attempt %.3f", S.BANDS[b].id,
					(bandLow[b] or 0) / bandAtt[b], (bandFail[b] or 0) / bandAtt[b]))
			end
		end
		print("       by band: " .. table.concat(bl, " | "))
		out[name] = { at = at, deaths = deaths, reached35 = reached35 }
	end
	return out
end

return M
