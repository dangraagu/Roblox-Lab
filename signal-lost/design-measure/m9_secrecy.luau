--!nocheck
-- M9: how much does the PUBLIC relay rule give away to someone who knows the whole map (walls + air)?
-- The relay is uniform among the candidates (air, not the entry, d >= ceil(frac * maxD)), so a map
-- reader's best guess succeeds with probability 1 / #candidates. Also: the meter reading at the entry.
local S = require("./station")
local N = 3000
print("M9 relay secrecy, " .. N .. " plans per row")
for _, frac in { 0.5, 0.6, 0.75 } do
	local cfg = table.clone(S.CFG)
	cfg.RelayDepthFrac = frac
	for _, k in { 1, 5, 10, 23, 40 } do
		local C, one, guess, bars = {}, 0, 0, { 0, 0, 0, 0, 0 }
		for i = 1, N do
			local p = S.plan(k, S.seedsFor(i, 8000 + k), S.schedule(k), cfg)
			table.insert(C, p.nCand)
			if p.nCand == 1 then one += 1 end
			guess += 1 / p.nCand
			local d = S.straight(p, p.entry, p.relay)
			local b = math.clamp(5 - math.floor(d), 1, 5)
			bars[b] += 1
		end
		print(string.format("frac %.2f k=%-2d | candidates p10/p50/p90 %d/%d/%d | only one: %.2f | map reader's hit chance %.2f | entry meter bars 1..5: %.2f %.2f %.2f %.2f %.2f",
			frac, k, S.pct(C, 0.1), S.pct(C, 0.5), S.pct(C, 0.9), one / N, guess / N,
			bars[1] / N, bars[2] / N, bars[3] / N, bars[4] / N, bars[5] / N))
	end
end
