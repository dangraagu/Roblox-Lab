--!nonstrict
-- Escape Room Lab -- DESIGN-TIME PROBE of the +1 Jump hazard template, run VERBATIM against the indoor
-- config DESIGN.md §8 specifies. Not game code. It requires plus1-jump's own files, unmodified:
--
--   luau design/hazard_probe.luau 2>&1
--
-- Prints the numbers DESIGN.md tags [P]: where a lane starts under a 16-stud ceiling, the ring's width,
-- stand-still vs step-out outcomes, the scheduler's rate over 20 h of exposed time, and the knock.
local Hazards = require("../../plus1-jump/src/shared/Hazards")
local Rest = require("../../plus1-jump/src/shared/Rest")
local cfg = {
	IntervalMin = 120, IntervalMax = 180, MinTelegraphSeconds = 3, MinCommitSeconds = 1.5,
	MaxRetargetSpeed = 1.5, PlayerRadius = 1.5, AimJitter = 0.8, SpreadDegrees = 0,
	ViewPitchDegrees = 20, KindFitDegrees = 25, KnockLift = 0,
	Kinds = {
		spider = { speed = 4, telegraph = 3.0, commit = 1.5, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 },
		pod = { speed = 4, telegraph = 3.0, commit = 1.5, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 },
		drone = { speed = 4, telegraph = 3.0, commit = 1.5, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 },
		claw = { speed = 4, telegraph = 3.0, commit = 1.5, pass = 0.6, hitRadius = 2.0, knock = 20, pitch = 85, pitchSpread = 0 },
	},
}
print("validate", Hazards.validate(cfg))
local rcfg = { IdleSeconds = 0, RequireGrounded = true, BlockWhileThreat = true, WakeOnMove = true, WakeGraceSeconds = 0.4, PendingSeconds = 6 }
print("rest validate", Rest.validate(rcfg))
local seed = 12345
local function rand() seed = (1664525 * seed + 1013904223) % 4294967296; return seed / 4294967296 end
-- geometry: floor y=0, root at y=3, ceiling y=16
local maxStartY, minStartY, maxHoriz = -1e9, 1e9, 0
for i = 1, 2000 do
	local yaw = rand() * math.pi * 2
	local p = Hazards.plan(cfg, "spider", { x = 0, y = 3, z = 0 }, yaw, rand, math.rad(85))
	maxStartY = math.max(maxStartY, p.start.y); minStartY = math.min(minStartY, p.start.y)
	local h = math.sqrt((p.start.x - p.target.x) ^ 2 + (p.start.z - p.target.z) ^ 2)
	maxHoriz = math.max(maxHoriz, h)
end
print(string.format("lane start y: %.3f..%.3f (root 3, ceiling 16); horizontal offset from target <= %.3f", minStartY, maxStartY, maxHoriz))
local z = Hazards.zone(Hazards.plan(cfg, "spider", { x = 0, y = 3, z = 0 }, 0, rand, math.rad(85)), cfg.PlayerRadius)
print(string.format("ring radius %.2f (diameter %.2f)", z.radius, z.radius * 2))
-- dodge sweep: stand still vs walk out at 16 studs/s after the lock, 36 directions, jitter included
local function trial(dirDeg, walk)
	local state = Hazards.newScheduler(cfg, rand)
	state.clock = state.nextAt -- due now
	local pos = { x = 0, y = 3, z = 0 }
	local ev = Hazards.step(state, cfg, 0, { resting = false, grounded = true, kinds = { "spider" }, aim = pos, yaw = 0, pitch = math.rad(85) }, rand)
	assert(ev and ev.type == "spawn")
	local plan = ev.plan
	local dt = 1 / 60
	local hit = false
	local t = 0
	local walked = 0
	while plan and t < 6 do
		local t0 = plan.t
		if walk and plan.locked then
			local step = math.min(16 * dt, 3.9 - walked)
			if step > 0 then
				pos = { x = pos.x + math.cos(math.rad(dirDeg)) * step, y = 3, z = pos.z + math.sin(math.rad(dirDeg)) * step }
				walked += step
			end
		end
		local e = Hazards.step(state, cfg, dt, { resting = false, grounded = true, kinds = { "spider" }, aim = pos, yaw = 0, pitch = math.rad(85) }, rand)
		if state.active == plan then
			if Hazards.checkHit(plan, t0, plan.t, pos, cfg.PlayerRadius) then hit = true; plan.hit = true end
		else
			break
		end
		t += dt
	end
	return hit
end
local standHits, walkHits = 0, 0
for d = 0, 350, 10 do
	if trial(d, false) then standHits += 1 end
	if trial(d, true) then walkHits += 1 end
end
print(string.format("stand still: %d of 36 hit; walk 3.9 studs out after the lock: %d of 36 hit", standHits, walkHits))
-- rate: 20 h of exposed time
local st = Hazards.newScheduler(cfg, rand)
local n = 0
local T = 20 * 3600
local t = 0
local dt = 0.5
while t < T do
	local e = Hazards.step(st, cfg, dt, { resting = false, grounded = true, kinds = { "spider" }, aim = { x = 0, y = 3, z = 0 }, yaw = 0, pitch = math.rad(85) }, rand)
	if e and e.type == "spawn" then n += 1 end
	t += dt
end
print(string.format("20 h exposed: %d hazards = one per %.1f s", n, T / n))
local kv = Hazards.knockVelocity(cfg, Hazards.plan(cfg, "spider", { x = 0, y = 3, z = 0 }, 0, rand, math.rad(85)), { x = 0.5, y = 3, z = 0.2 })
print(string.format("knock velocity (%.1f, %.1f, %.1f)", kv.x, kv.y, kv.z))
