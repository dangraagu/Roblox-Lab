local M = require("./maze")
local X = require("./model")
local W, H, LOOPS = 9, 9, 8
local HZ = { count = 3, period = 18, grace = 6, near = 0.4, minE = 3, sep = 4, onRoute = true }
local N = 2000
local FILTER = (...) == "band"

local perfects, walls, firstSeal, firstRun, accepted = {}, {}, {}, { fast = {}, normal = {}, slow = {} }, 0
local dEntranceDoor = {}
for s = 1, N do
	local dr = M.rng(s * 7907 + 3)
	local day = X.makeDay(W, H, LOOPS, dr, HZ)
	while FILTER and (day.perfect < 22 or day.perfect > 34) do day = X.makeDay(W, H, LOOPS, dr, HZ) end
	table.insert(perfects, day.perfect)
	if day.perfect >= 22 and day.perfect <= 34 then accepted += 1 end
	-- closed wall segments incl. boundary, minus the entrance opening
	local m = day.m
	local closed = 0
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local i = y * W + x
			if x + 1 < W and not m.openE[i] then closed += 1 end
			if y + 1 < H and not m.openN[i] then closed += 1 end
		end
	end
	closed += 2 * W + 2 * H - 1
	table.insert(walls, closed)
	table.insert(dEntranceDoor, day.p.dE[day.p.door])
	if s <= 600 then
		for _, pname in { "fast", "normal", "slow" } do
			local prof = X.PROFILES[pname]
			local mem = X.newMemory()
			local trace = {}
			local t = X.explore(day.m, day.p, mem, prof, M.rng(s * 13 + 1), nil, day.p.entrance, nil, 0.5 * X.CELL / (X.WALK * prof.effExplore), trace)
			table.insert(firstRun[pname], t)
			if pname == "normal" then
				for _, e in trace do
					if e[1] == day.p.seals[1] or e[1] == day.p.seals[2] or e[1] == day.p.seals[3] then
						table.insert(firstSeal, e[2]); break
					end
				end
			end
		end
	end
end
local P = X.pct
print(string.format("perfect line s: min %.1f p5 %.1f p15 %.1f p50 %.1f p85 %.1f p95 %.1f max %.1f | in [22,34]: %.1f%%",
	P(perfects, 0), P(perfects, 0.05), P(perfects, 0.15), P(perfects, 0.5), P(perfects, 0.85), P(perfects, 0.95), P(perfects, 1), accepted / N * 100))
print(string.format("wall segments per lane (all cells built): min %d p50 %d max %d", P(walls, 0), P(walls, 0.5), P(walls, 1)))
print(string.format("door path distance from entrance (cells): min %d p50 %d max %d", P(dEntranceDoor, 0), P(dEntranceDoor, 0.5), P(dEntranceDoor, 1)))
print(string.format("normal first run: time to first seal s p10 %.1f p50 %.1f p90 %.1f max %.1f", P(firstSeal, 0.1), P(firstSeal, 0.5), P(firstSeal, 0.9), P(firstSeal, 1)))
for _, pname in { "fast", "normal", "slow" } do
	local f = firstRun[pname]
	print(string.format("%s first run s: p50 %.0f p90 %.0f p99 %.0f max %.0f", pname, P(f, 0.5), P(f, 0.9), P(f, 0.99), P(f, 1)))
end
