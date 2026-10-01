--!nocheck
-- M4: the endless curve. P(splice) per attempt by sector and upgrade state.
local S = require("./station")
local N = 800
local states = {
	{ label = "none", up = { tank = 0, boots = 0 } },
	{ label = "half", up = { tank = 2, boots = 2 } },
	{ label = "all ", up = { tank = 4, boots = 4 } },
}
print("M4 endless curve, " .. N .. " plans per cell. P(splice) fast / medium / slow; T p50 (s) medium; O2<25% share medium")
for _, k in { 1, 5, 10, 16, 23, 30, 40, 60, 80, 100, 150, 250 } do
	local sc = S.schedule(k)
	for _, st in states do
		local res = {}
		for _, name in { "fast", "medium", "slow" } do
			local ok, T, low = 0, {}, 0
			for i = 1, N do
				local p = S.plan(k, S.seedsFor(i, 9000 + k))
				local r = S.run(p, S.PROFILES[name], st.up, S.lcg01(17 * i + k))
				if r.ok then ok += 1; table.insert(T, r.t) end
				if r.minO2 < 0.25 * r.tank then low += 1 end
			end
			res[name] = { ok / N, S.pct(T, 0.5), low / N }
		end
		print(string.format("k=%-3d n%d breach %.3f reach %2d | %s | %.3f %.3f %.3f | %5.1f | %.2f", k, sc.n, sc.breach, sc.reach,
			st.label, res.fast[1], res.medium[1], res.slow[1], res.medium[2], res.medium[3]))
	end
end
