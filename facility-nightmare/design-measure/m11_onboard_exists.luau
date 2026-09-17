--!nocheck
-- M11: on a 4x4 sublevel-1 plan, is there ALWAYS a non-entry, non-exit room within 2 doorways of the entry?
local S = require("./sim")
local N, none, minMaxD = 20000, 0, math.huge
for i = 1, N do
	local p = S.plan(4, (i * 2654435761) % 4294967296, (i * 40503 + 7) % 4294967296, 3, 2, false)
	local near = 0
	for r = 1, p.n2 do
		if r ~= p.entry and r ~= p.exit and p.d[r] <= 2 then near += 1 end
	end
	if near == 0 then none += 1 end
	minMaxD = math.min(minMaxD, p.maxD)
end
print(string.format("4x4 plans %d | plans with NO onboarding candidate %d | smallest maxD seen %d", N, none, minMaxD))
