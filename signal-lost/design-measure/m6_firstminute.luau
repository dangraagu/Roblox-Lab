--!nocheck
-- M6: a new player's first sector (sector 1, no upgrades). Seconds after the dock doors open.
local S = require("./station")
local N = 3000
print("M6 first sector, " .. N .. " plans. Seconds after the dock doors open (p10 / p50 / p90)")
local function airOnlyReach(p)
	-- can the relay be reached from the entry through air modules only?
	local seen, q, h = { [p.entry] = true }, { p.entry }, 1
	while h <= #q do
		local a = q[h]; h += 1
		for _, b in p.adj[a] do
			if not seen[b] and not p.vac[b] then seen[b] = true; table.insert(q, b) end
		end
	end
	return seen[p.relay] == true
end
local airPath, anyVacAdj = 0, 0
for i = 1, N do
	local p = S.plan(1, S.seedsFor(i, 1))
	if airOnlyReach(p) then airPath += 1 end
	for _, b in p.adj[p.entry] do if p.vac[b] then anyVacAdj += 1; break end end
end
print(string.format("relay reachable through air only: %.3f of plans | entry has a breached neighbour: %.3f", airPath / N, anyVacAdj / N))
for _, name in { "fast", "medium", "slow" } do
	local V, SA, T, entered, low = {}, {}, {}, 0, 0
	for i = 1, N do
		local p = S.plan(1, S.seedsFor(i, 1))
		local r = S.run(p, S.PROFILES[name], { tank = 0, boots = 0 }, S.lcg01(9001 * i + 1))
		if r.firstVacT then table.insert(V, r.firstVacT); entered += 1 end
		if r.firstSalvT then table.insert(SA, r.firstSalvT) end
		table.insert(T, r.t)
		if r.minO2 < 0.5 * r.tank then low += 1 end
	end
	print(string.format("%-6s | first vacuum entry %4.1f / %4.1f / %4.1f (%.0f%% of runs) | first salvage %4.1f / %4.1f / %4.1f (%.0f%%) | splice done %4.1f / %4.1f / %4.1f | O2 below half: %.0f%%",
		name, S.pct(V, 0.1), S.pct(V, 0.5), S.pct(V, 0.9), 100 * entered / N, S.pct(SA, 0.1), S.pct(SA, 0.5), S.pct(SA, 0.9),
		100 * #SA / N, S.pct(T, 0.1), S.pct(T, 0.5), S.pct(T, 0.9), 100 * low / N))
end
