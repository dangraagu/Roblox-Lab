--!nocheck
-- M2: one knob at a time around the chosen base, at k = 10 (cargo) and k = 23 (array spine), no upgrades.
local S = require("./station")
local N = 1000
local function row(label, cfgPatch, k)
	local cfg = table.clone(S.CFG)
	for key, v in cfgPatch do cfg[key] = v end
	local res = {}
	for _, name in { "medium", "slow" } do
		local ok, T, low, flips = 0, {}, 0, 0
		for i = 1, N do
			local p = S.plan(k, S.seedsFor(i, 300 + k), S.schedule(k), cfg)
			local r = S.run(p, S.PROFILES[name], { tank = 0, boots = 0 }, S.lcg01(41 * i + k), cfg)
			if r.ok then ok += 1; table.insert(T, r.t) end
			if r.minO2 < 0.25 * r.tank then low += 1 end
			flips += p.flips
		end
		res[name] = string.format("%.3f %5.1f %.2f", ok / N, S.pct(T, 0.5), low / N)
		res.flips = flips / N
	end
	print(string.format("k=%-2d %-22s | medium %s | slow %s | reach flips/plan %.2f", k, label, res.medium, res.slow, res.flips))
end
print("M2 sensitivity, " .. N .. " plans per row. Columns per profile: P(splice), T p50 (s), share of attempts with O2 < 25% of the tank")
for _, k in { 10, 23 } do
	row("BASE", {}, k)
	for _, v in { 15, 25, 30 } do row("TankBase " .. v, { TankBase = v }, k) end
	for _, v in { 10, 14, 16 } do row("VacSpeed " .. v, { VacSpeed = v }, k) end
	for _, v in { 0, 3, 8 } do row("GraceSeconds " .. v, { GraceSeconds = v }, k) end
	for _, v in { 5, 15 } do row("CanisterSeconds " .. v, { CanisterSeconds = v }, k) end
	for _, v in { 1, 4 } do row("RefillSeconds " .. v, { RefillSeconds = v }, k) end
	for _, v in { 0, 0.4 } do row("ExtraDoorChance " .. v, { ExtraDoorChance = v }, k) end
	for _, v in { 0.5, 1.0 } do row("RelayDepthFrac " .. v, { RelayDepthFrac = v }, k) end
	for _, v in { 32, 0 } do row("RecvBase " .. v .. (if v == 32 then " (meter everywhere)" else " (no meter)"), { RecvBase = v }, k) end
	row("HatchSeconds 1.0", { HatchSeconds = 1.0 }, k)
	row("CellSize 28", { CellSize = 28 }, k)
end
