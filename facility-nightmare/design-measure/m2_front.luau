--!nocheck
-- M2: the blackout front. step = slack * Tmodel / (maxD + LeadSteps); lead = LeadSteps * step.
-- Measures seconds spent in dark rooms (no battery limit) for explorers at 1.0 / 0.8 / 0.65 of WalkSpeed.
local S = require("./sim")
local N = 2000
local LEAD = 2
local shapes = {
	{ n = 4, fuses = 3, bat = 2, onboard = true, label = "4x4" },
	{ n = 5, fuses = 4, bat = 3, onboard = false, label = "5x5" },
	{ n = 6, fuses = 5, bat = 3, onboard = false, label = "6x6" },
}
local slacks = { 1.0, 1.25, 1.5, 1.75, 2.0, 2.5 }
local speeds = { 16, 12.8, 10.4 }
print("dark seconds (p50 / p90) by shape, slack, speed; also step seconds p50")
for _, sh in shapes do
	for _, sl in slacks do
		local line = string.format("%s slack %.2f |", sh.label, sl)
		local steps = {}
		for _, sp in speeds do
			local DK = {}
			for i = 1, N do
				local p = S.plan(sh.n, 1000003 * i + 17, 7919 * i + 104729, sh.fuses, sh.bat, sh.onboard)
				local base = S.explore(p, {})
				local step = sl * base.t / (p.maxD + LEAD)
				if sp == 16 then table.insert(steps, step) end
				local r = S.explore(p, { speed = sp, front = { lead = LEAD * step, step = step } })
				table.insert(DK, r.darkSec)
			end
			line ..= string.format(" v%4.1f %5.1f/%5.1f |", sp, S.pct(DK, 0.5), S.pct(DK, 0.9))
		end
		line ..= string.format(" step p50 %.2f", S.pct(steps, 0.5))
		print(line)
	end
end
