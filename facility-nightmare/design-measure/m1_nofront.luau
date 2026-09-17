--!nocheck
-- M1: how long does a floor take a perfect-memory blind explorer, with no threat at all?
local S = require("./sim")
local N = 3000
local shapes = {
	{ n = 4, fuses = 3, bat = 2, onboard = true, label = "4x4 F3 onboard" },
	{ n = 4, fuses = 3, bat = 2, onboard = false, label = "4x4 F3" },
	{ n = 5, fuses = 4, bat = 3, onboard = false, label = "5x5 F4" },
	{ n = 6, fuses = 5, bat = 3, onboard = false, label = "6x6 F5" },
	{ n = 7, fuses = 6, bat = 4, onboard = false, label = "7x7 F6" },
}
print("shape            | T p10  p50  p90  max | maxD p50 max | visited% p50 | firstFuse s p50 p90 | rooms<=1stFuse p50 p90 | T/maxD p50 | doors/room")
for _, sh in shapes do
	local T, D, V, FF, FR, TD, DR = {}, {}, {}, {}, {}, {}, {}
	for i = 1, N do
		local layoutSeed = 1000003 * i + 17
		local lootSeed = 7919 * i + 104729
		local p = S.plan(sh.n, layoutSeed, lootSeed, sh.fuses, sh.bat, sh.onboard)
		local r = S.explore(p, {})
		table.insert(T, r.t); table.insert(D, p.maxD); table.insert(V, r.visited / p.n2)
		table.insert(FF, r.firstFuseT); table.insert(FR, r.firstFuseRooms); table.insert(TD, r.t / p.maxD)
		table.insert(DR, p.doors / p.n2)
	end
	print(string.format("%-16s | %5.1f %5.1f %5.1f %5.1f | %d %d | %3.0f%% | %5.1f %5.1f | %d %d | %5.2f | %4.2f",
		sh.label, S.pct(T, 0.1), S.pct(T, 0.5), S.pct(T, 0.9), S.pct(T, 1.0), S.pct(D, 0.5), S.pct(D, 1.0),
		100 * S.pct(V, 0.5), S.pct(FF, 0.5), S.pct(FF, 0.9), S.pct(FR, 0.5), S.pct(FR, 0.9), S.pct(TD, 0.5), S.mean(DR)))
end
