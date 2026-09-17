--!nocheck
-- M5: reduced perk magnitudes (survival), then the push-your-luck economy per extraction policy.
local S = require("./sim")
local RUNS = 800
local LEAD = 2
local MAXSUB = 30
local RIDE = 4          -- elevator ride seconds between sublevels
local OVERHEAD = 15     -- per run: hub walk + first ride + return beat (assumption)

local P0 = { small = 3, mid = 8, cells1 = 2, cells2 = 2, cells3 = 1, cell = 15, s1 = 2.0, smin = 1.0, K = 4, e = 1 }
local function slack(k) return P0.smin + (P0.s1 - P0.smin) * (1 + (k - 1) / P0.K) ^ (-P0.e) end
local function shape(k)
	if k <= P0.small then return 4, 3, P0.cells1 end
	if k <= P0.mid then return 5, 4, P0.cells2 end
	return 5, 5, P0.cells3
end

-- returns cleared, deathTime (or total), endTimes[k] (time at which floor k's elevator was reached, incl rides)
local function run(seedBase, speed, perk)
	local battery = perk.cap
	local revives = perk.revives
	local t = OVERHEAD
	local ends = {}
	for k = 1, MAXSUB do
		local n, f, b = shape(k)
		local ls = (seedBase * 131 + k * 7919) % 4294967296
		local p = S.plan(n, ls, (ls * 7 + 12345) % 4294967296, f, b, k == 1)
		local base = S.explore(p, {})
		local step = slack(k) * base.t / (p.maxD + LEAD)
		local r = S.explore(p, {
			speed = speed,
			front = { lead = LEAD * step, step = step },
			battery = { cap = perk.cap, start = battery, cell = P0.cell, grace = perk.grace, recover = 1,
				revives = revives, reviveBattery = 10 },
		})
		t += r.t
		revives -= r.revivesUsed
		if r.died then return k - 1, t, ends end
		ends[k] = t
		t += RIDE
		battery = r.battery
	end
	return MAXSUB, t, ends
end

local perks = {
	{ "none", { cap = 45, grace = 4, revives = 0 } },
	{ "DeepCell3 (cap 75)", { cap = 75, grace = 4, revives = 0 } },
	{ "NightEyes3 (grace 7)", { cap = 45, grace = 7, revives = 0 } },
	{ "SecondWind (1 revive, +10s)", { cap = 45, grace = 4, revives = 1 } },
	{ "all survival perks", { cap = 75, grace = 7, revives = 1 } },
}
local speeds = { 16, 12.8, 10.4 }
local results = {}
for _, pk in perks do
	print("== " .. pk[1])
	results[pk[1]] = {}
	for _, sp in speeds do
		local rows = {}
		local reach = {}
		for k = 0, MAXSUB do reach[k] = 0 end
		local depths = {}
		for i = 1, RUNS do
			local c, t, ends = run(i, sp, pk[2])
			table.insert(rows, { c = c, t = t, ends = ends })
			for k = 0, c do reach[k] += 1 end
			table.insert(depths, c)
		end
		results[pk[1]][sp] = rows
		local line = string.format("  v%4.1f cleared p50 %2d mean %5.2f | P: ", sp, S.pct(depths, 0.5), S.mean(depths))
		for _, k in { 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30 } do line ..= string.format("%d:%.2f ", k, reach[k] / RUNS) end
		print(line)
	end
end

-- economy
local function cum(k, base, grow) -- essence for clearing sublevels 1..k
	local s = 0
	for j = 1, k do s += base + grow * (j - 1) end
	return s
end
local function policy(rows, K, keep, base, grow)
	local bank, time = 0, 0
	for _, r in rows do
		if r.c >= K then
			bank += cum(K, base, grow); time += r.ends[K]
		else
			bank += math.floor(keep * cum(r.c, base, grow)); time += r.t
		end
	end
	return bank / #rows, time / #rows
end
for _, econ in { { 10, 5 }, { 10, 10 }, { 20, 0 } } do
	for _, keep in { 0.25, 0.55 } do
		print(string.format("== economy: floor k pays %d + %d*(k-1); death keeps %.0f%%", econ[1], econ[2], keep * 100))
		for _, pkname in { "none", "all survival perks" } do
			for _, sp in speeds do
				local rows = results[pkname][sp]
				local line = string.format("  %-19s v%4.1f  E/run & E/min by extract-after K: ", pkname, sp)
				local bestK, bestRate = 0, -1
				for K = 1, 12 do
					local b, t = policy(rows, K, keep, econ[1], econ[2])
					local rate = b / (t / 60)
					if rate > bestRate then bestRate = rate; bestK = K end
					if K <= 8 or K == 12 then line ..= string.format("%d:%.0f/%.1f ", K, b, rate) end
				end
				line ..= string.format(" BEST K=%d (%.1f/min)", bestK, bestRate)
				print(line)
			end
		end
	end
end
