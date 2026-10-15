-- Pacing — the brag moment, the long goal, the bands, the first minute and the exploit bounds, measured by
-- tests/CityModel.luau playing the game's own Economy (prices, Orders, the ★) and City (the seeded layout) from
-- Config. Run: luau tests/Pacing.spec.luau
--
-- The player profiles are ASSUMPTIONS (Config.Pacing); every minute below inherits that. What this spec pins
-- (DESIGN 16): normal and slow open the Skyport (the brag, band 4) in 30-45 min; Crown Heights at least 2x later
-- and under 3 h; every band lasts at least 2 min; 0 Orders lapses for every profile; the teleport exploit's brag is
-- at least 0.95 of the normal player's time; AFK and the one-lot macro add 0 population in 8 h; plus the first
-- minute (core action by 5 s, 7 purchases), the hazard rhythm, idle rest under 1.5 %, and the dead-end rule.
-- It prints the same lines as design/model.py so the port can be compared with design/model.out.txt.

local Config = require("../src/shared/Config")
local Model = require("./CityModel")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

local SEEDS, MINUTES = 40, 240
local fmt, median, pct = Model.fmt, Model.median, Model.pct

--============================================================================ [M3] minutes to enter each band
print(string.format("[M3] minutes to ENTER each band (district), %d seeds each, %d min sessions", SEEDS, MINUTES))
local runs = {}
local brag = {}
for _, name in Config.Pacing.ProfileOrder do
	runs[name] = {}
	local cols = { [2] = {}, [3] = {}, [4] = {}, [5] = {}, [6] = {} }
	local lapses, gaps = 0, {}
	for seed = 1, SEEDS do
		local r = Model.simulate(Config, name, seed, MINUTES)
		runs[name][seed] = r
		for b = 2, 6 do table.insert(cols[b], (r.bandAt[b] or math.huge) / 60) end
		lapses += r.lapses
		table.insert(gaps, r.maxGap)
	end
	local line = string.format("  %-8s", name)
	for b = 2, 6 do
		line ..= string.format("  b%d %6s (p10 %6s p90 %6s)", b, fmt(median(cols[b])), fmt(pct(cols[b], 0.1)), fmt(pct(cols[b], 0.9)))
	end
	print(line)
	print(string.format("  %-8s  orders lapses %d; longest gap between purchases: median %s s, max %s s", "", lapses, fmt(median(gaps)), fmt(math.max(table.unpack(gaps)))))
	eq(lapses, 0, name .. ": the Orders never run out on a player who follows the ★")
	truthy(math.max(table.unpack(gaps)) < Config.Economy.OrdersSeconds / 2,
		string.format("%s: the longest gap between purchases (%.1f s) is under half the Orders", name, math.max(table.unpack(gaps))))
	brag[name] = { b4 = median(cols[4]), b6 = median(cols[6]), b4max = pct(cols[4], 1), cols = cols }
end
do
	local lo, hi = Config.Pacing.BragMinutes[1], Config.Pacing.BragMinutes[2]
	for _, name in { "normal", "slow" } do
		local b = brag[name]
		truthy(b.b4 >= lo and b.b4 <= hi, string.format("%s: the Skyport (the brag) opens at %.1f min, inside %d-%d", name, b.b4, lo, hi))
		truthy(b.b4max <= hi, string.format("%s: even the slowest seed's brag (%.1f min) is inside the window", name, b.b4max))
		truthy(b.b6 >= 2 * b.b4, string.format("%s: Crown Heights (%.1f min) is at least 2x the brag (%.1f)", name, b.b6, b.b4))
		truthy(b.b6 <= 180, string.format("%s: Crown Heights (%.1f min) comes within 3 h", name, b.b6))
	end
	truthy(brag.teleport.b4 / brag.normal.b4 >= 0.95,
		string.format("the teleport exploit's brag (%.1f) is at least 0.95 of the normal player's (%.1f): automation buys %.1f %%",
			brag.teleport.b4, brag.normal.b4, 100 * (1 - brag.teleport.b4 / brag.normal.b4)))
end

--============================================================================ [M4] band durations
print("[M4] how long each band lasts (normal profile, minutes)")
do
	local shortest = math.huge
	for b = 1, 5 do
		local d = {}
		for seed = 1, SEEDS do
			local r = runs.normal[seed]
			local a = r.bandAt[b] or 0
			local z = r.bandAt[b + 1]
			if z then table.insert(d, (z - a) / 60) end
		end
		local mn = math.min(table.unpack(d))
		shortest = math.min(shortest, mn)
		print(string.format("  band %d: median %s, min %s", b, fmt(median(d), 2), fmt(mn, 2)))
	end
	truthy(shortest >= 2, string.format("every band lasts at least 2 min for every seed (shortest %.2f)", shortest))
end

--============================================================================ [M5] the first minute
print("[M5] the first purchases of a normal player (seed 1..5)")
do
	local firstBuild = 0
	for seed = 1, 5 do
		local r = runs.normal[seed]
		local parts = {}
		for i = 1, math.min(6, #r.first) do
			local f = r.first[i]
			table.insert(parts, string.format("%ss %s (pop %d)", fmt(f.t), f.what, f.pop))
		end
		print(string.format("  seed %d: %s", seed, table.concat(parts, "; ")))
	end
	local n60 = {}
	for seed = 1, SEEDS do
		local r = Model.simulate(Config, "normal", seed, 1)
		table.insert(n60, r.buys)
		firstBuild = math.max(firstBuild, runs.normal[seed].first[1].t)
	end
	print(string.format("  purchases in the first 60 s: median %s, min %s", fmt(median(n60), 0), fmt(math.min(table.unpack(n60)), 0)))
	truthy(firstBuild <= 5, string.format("the core action (the first build) comes by %.1f s for every seed (checklist: ~5 s)", firstBuild))
	eq(math.min(table.unpack(n60)), 7, "7 purchases in the first minute, every seed [M5]")
end

--============================================================================ [M6] hazards before the brag
print("[M6] hazards for a normal player (none in band 1)")
do
	local before = {}
	for seed = 1, SEEDS do
		local b4 = runs.normal[seed].bandAt[4]
		local r = Model.simulate(Config, "normal", seed, b4 / 60 + 1e-6)
		table.insert(before, r.hazards)
	end
	print(string.format("  hazards launched before the brag: median %s (min %s, max %s)", fmt(median(before), 0),
		fmt(math.min(table.unpack(before)), 0), fmt(math.max(table.unpack(before)), 0)))
	truthy(median(before) >= 10 and median(before) <= 18, "about one hazard per 2-3 minutes before the brag (median " .. median(before) .. ")")
end

--============================================================================ [M7] AFK and macros
print("[M7] AFK and macros, starting from the normal player's state when the brag band opens (seed 1..10)")
do
	local afkPop, one, two, human, oneSt = {}, {}, {}, {}, {}
	local afkMinutes = 0
	for seed = 1, 10 do
		local r = Model.simulate(Config, "normal", seed, MINUTES, { stopAtBand = 4 })
		local st = r.st
		-- AFK (or an anti-AFK jiggle): 8 h of the game's own earning rule with no purchase
		local afk = Model.afk(Config, st, r.t, r.ordersUntil, 8)
		afkMinutes = math.max(afkMinutes, (afk.worked + afk.net) / 60)
		if afk.net > 0 then Model.NET.engaged += 1 end
		Model.NET.checked += 1
		table.insert(afkPop, afk.pop - st.pop)
		local bestPop, bestS = 0, 0
		for i = 1, #st.layout.lots do
			local dp, s = Model.macroOneLot(Config, st, i, 8)
			if dp > bestPop or (dp == bestPop and s > bestS) then bestPop, bestS = dp, s end
		end
		table.insert(one, bestPop / math.max(1, st.pop))
		table.insert(oneSt, bestS)
		local bestTwo = 0
		for i, a in st.layout.lots do
			if a.zone == "H" then
				for j, b in st.layout.lots do
					if b.zone == "W" then bestTwo = math.max(bestTwo, Model.macroTwoLots(Config, st, i, j, 8)) end
				end
			end
		end
		table.insert(two, bestTwo / math.max(1, st.pop))
		local r8 = Model.simulate(Config, "normal", seed, r.t / 60 + 480)
		table.insert(human, (r8.st.pop - st.pop) / math.max(1, st.pop))
		if seed == 1 then
			print(string.format("  seed 1 state: population %d, income %s/s, credits %s", st.pop, Model.compact(st.income), Model.compact(st.credits)))
		end
	end
	print(string.format("  idle (AFK or an anti-AFK jiggle): the city earns at most %s more minutes of income, then stops; population +%d", fmt(afkMinutes, 2), math.max(table.unpack(afkPop))))
	print(string.format("  one-lot prompt macro, best lot, 8 h: population x%s (median x%s), that lot ends at storey %s", fmt(1 + math.max(table.unpack(one)), 3), fmt(1 + median(one), 3), fmt(median(oneSt), 0)))
	print(string.format("  two-lot route macro, best pair, 8 h: population x%s (median x%s)", fmt(1 + math.max(table.unpack(two)), 3), fmt(1 + median(two), 3)))
	print(string.format("  the normal human, 8 more hours:      population x%s .. x%s", fmt(1 + math.min(table.unpack(human)), 3), fmt(1 + math.max(table.unpack(human)), 3)))
	print(string.format("  safety net (the city also works while no storey is affordable): engaged %d of %d stalls", Model.NET.engaged, Model.NET.checked))
	eq(math.max(table.unpack(afkPop)), 0, "AFK adds 0 population in 8 h")
	truthy(afkMinutes <= Config.Economy.OrdersSeconds / 60 + 1e-9, string.format("AFK earns at most the Orders' %.0f minutes", Config.Economy.OrdersSeconds / 60))
	eq(math.max(table.unpack(one)), 0, "a one-lot prompt macro adds 0 population in 8 h (one side alone adds no citizens)")
	truthy(1 + math.max(table.unpack(two)) < 0.05 * (1 + math.min(table.unpack(human))),
		"the best two-lot route macro gets under 5 % of what the normal human builds in the same 8 h")
end

--============================================================================ [M9] the dead end
print("[M9] dead-end check: walker macro (perfect play) for 48 h, seeds 1..5")
do
	local worstAll = 0
	for seed = 1, 5 do
		local box = { worst = 0, done = nil }
		local r = Model.simulate(Config, "walker", seed, 48 * 60, { log = function(t, st)
			local cheapest = Model.cheapestOpen(Config, st)
			if cheapest then
				box.worst = math.max(box.worst, (cheapest - st.credits) / math.max(st.income, 1e-9))
			elseif box.done == nil then
				box.done = t
			end
		end })
		worstAll = math.max(worstAll, box.worst)
		print(string.format("  seed %d: worst wait for the cheapest storey %s s (Orders %d s); lapses %d; city complete at %s h; pop %s",
			seed, fmt(box.worst), Config.Economy.OrdersSeconds, r.lapses, if box.done then fmt(box.done / 3600, 2) else "not yet", Model.compact(r.st.pop)))
		eq(r.lapses, 0, "walker seed " .. seed .. ": no Orders lapse in 48 h")
		truthy(box.done ~= nil, "walker seed " .. seed .. ": the city completes")
	end
	truthy(worstAll <= Config.Economy.OrdersSeconds / 2, string.format("the worst wait for the cheapest storey (%.1f s) is under half the Orders", worstAll))
end

--============================================================================ [M10] idle rest share
print("[M10] share of a normal player's first 60 min spent in idle rest, by IdleSeconds (stormgrow REVIEW-1 B2)")
do
	for _, idle in { 20, 45, Config.Rest.IdleSeconds, 90 } do
		local shares = {}
		for seed = 1, SEEDS do
			local r = Model.simulate(Config, "normal", seed, 60)
			local rested = 0
			for _, sp in r.spans do rested += math.max(0, sp - idle) end
			table.insert(shares, rested / r.t)
		end
		print(string.format("  IdleSeconds %3d: median %s%%, max %s%%", idle, fmt(100 * median(shares)), fmt(100 * math.max(table.unpack(shares)))))
		if idle == Config.Rest.IdleSeconds then
			truthy(math.max(table.unpack(shares)) < 0.015, string.format("at the shipped IdleSeconds (%d) idle rest is under 1.5 %% of the first hour for every seed", idle))
		end
	end
end

--============================================================================ [M11] the skyline and the complete city
print("[M11] skyline: average and highest storey per open district when a band opens (normal, seeds 1..10)")
do
	for _, band in { 4, 6 } do
		local per = {}
		for d = 1, 6 do per[d] = {} end
		for seed = 1, 10 do
			local r = Model.simulate(Config, "normal", seed, MINUTES, { stopAtBand = band })
			for _, l in r.st.layout.lots do table.insert(per[l.d], r.st.lots[l.key] or 0) end
		end
		local parts = {}
		for d = 1, band - 1 do
			local sum, mx = 0, 0
			for _, s in per[d] do sum += s; mx = math.max(mx, s) end
			table.insert(parts, string.format("d%d avg %s max %d", d, fmt(sum / #per[d]), mx))
		end
		print(string.format("  band %d opens: %s", band, table.concat(parts, "; ")))
	end
	local done = {}
	for seed = 1, 5 do
		local box = { done = nil }
		Model.simulate(Config, "normal", seed, 12 * 60, { log = function(t, st)
			if box.done == nil and Model.complete(Config, st) then box.done = t end
		end })
		table.insert(done, if box.done then box.done / 3600 else math.huge)
	end
	local doneText = {}
	for _, x in done do table.insert(doneText, fmt(x, 2)) end
	print(string.format("  normal player completes the city (every lot at %d storeys): median %s h (seeds 1..5: %s)", Config.Economy.MaxStoreys, fmt(median(done), 2), table.concat(doneText, ", ")))
	truthy(median(done) < 6, "the normal player completes the skyline (median " .. fmt(median(done), 2) .. " h)")
end

--============================================================================ [M12] players who do not follow the ★
-- (round 2, finding B3) Every number above is a player who buys what the ★ marks. The reviewer measured players who
-- buy something else: the cheapest storey, the tallest, or the most people per credit (the prompt shows "+N"
-- since round 2). The game cannot make every way of playing equally fast: a storey in a newer district brings 5x the
-- people for 6x the price, so the cheapest storey is usually the worst buy. What is pinned: the ★ is the fastest way;
-- a player who reads the prompts' "+N" and waits for the best buy is as fast and inside the window; and nobody who
-- builds on the short side is more than 1.6x slower than the ★.
print("[M12] minutes to the Skyport (the brag) by what the player buys, 10 seeds (median, max)")
do
	local lo, hi = Config.Pacing.BragMinutes[1], Config.Pacing.BragMinutes[2]
	local N = 10
	for _, prof in { "normal", "slow" } do
		local res = {}
		for _, name in { "star", table.unpack(Model.StrategyOrder) } do
			local ts = {}
			for seed = 1, N do
				local pick = Model.Strategies[name]
				local r = Model.simulate(Config, prof, seed, MINUTES, { stopAtBand = 4, pick = pick })
				table.insert(ts, (r.bandAt[4] or math.huge) / 60)
			end
			res[name] = { med = median(ts), max = math.max(table.unpack(ts)) }
		end
		local line = string.format("  %-7s", prof)
		for _, name in { "star", table.unpack(Model.StrategyOrder) } do
			line ..= string.format("  %s %s (%s)", name, fmt(res[name].med), fmt(res[name].max))
		end
		print(line)
		local slowest, slowName = 0, ""
		for _, name in Model.StrategyOrder do
			truthy(res.star.med <= res[name].med + 1e-9, string.format("%s: the ★ (%.1f min) is at least as fast as buying by '%s' (%.1f)", prof, res.star.med, name, res[name].med))
			if res[name].max > slowest then slowest, slowName = res[name].max, name end
		end
		truthy(res.value.max >= lo and res.value.max <= hi,
			string.format("%s: a player who reads the prompts' +N and waits for the best buy docks the airship inside %d-%d (slowest seed %.1f)", prof, lo, hi, res.value.max))
		truthy(slowest <= 1.6 * res.star.med,
			string.format("%s: no short-side way of buying is more than 1.6x slower than the ★ (slowest: %s, %.1f min vs %.1f)", prof, slowName, slowest, res.star.med))
	end
end

print(string.format("Pacing: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pacing spec failed", 0) end
