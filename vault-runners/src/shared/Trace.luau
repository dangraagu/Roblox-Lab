--!strict
-- Trace.luau — hvor serveren TROR løperen er. REN logikk.
--
-- In Roblox the client owns its own character's physics. `hrp.Position` read on the server is
-- not an observation, it is a CLAIM, and Vault Runners' entire economy is one number — gems
-- banked — decided by that claim. v1 tested it directly: gem pickup was
-- `(pos - gem).Magnitude <= CollectRadius` and the escape was the same test against the exit
-- pad, with no displacement check anywhere in the run loop. Writing the root part onto the exit
-- pad banked 100% of a vault instantly, which is also exactly what the headless check did to
-- assert a successful escape.
--
-- This module does not try to detect cheating. It removes the thing cheating was worth: the
-- server keeps its own position for the runner, moves it toward the claim NO FASTER THAN A
-- RUNNER CAN MOVE, and every rule in the game reads that instead of the claim. A player who
-- teleports to the exit does not escape; their trusted position starts walking there, at walking
-- pace, and arrives when a runner would have arrived.
--
-- WHAT THIS DOES NOT DO, so nobody reads more into it than is here:
--   * it does not test walls. The trusted position moves in straight lines, so a flier still
--     gets the straight-line route rather than the maze route. That is a real advantage and it
--     is bounded by speed rather than removed.
--   * it does not punish. There is no kick, no flag, no counter shown to anybody. A lagging
--     honest player is indistinguishable from a slow cheat, and the correct response to both is
--     the same: nothing happens any faster than a runner could make it happen.
--   * falling is free. Losing height costs the runner and gains them nothing, so the trusted
--     position follows a fall exactly — and the collapse underneath reads the same number.
--
-- Pure: cfg + a plain {x,y,z} in, plain numbers out. No Roblox global, no clock of its own, no
-- Vector3 — the server subtracts the vault origin before it calls, so this never sees a world
-- coordinate. And, like every other module in src/shared, it requires nothing: a bare
-- `require("./X")` resolves in the luau CLI and is INVALID in Roblox.

local Trace = {}

-- The two speeds the trusted position is allowed, derived from the movement model the countdown
-- is already derived from, so they cannot drift apart from it.
--
--   horizontal — WalkSpeed with a tolerance. Roblox preserves horizontal velocity through a
--                jump and the game writes WalkSpeed onto the Humanoid itself, so a runner on the
--                flat cannot exceed it; the tolerance is for replication jitter, not for speed.
--   up         — the climb, which is what actually limits how fast a runner gains height: one
--                storey per (steps x ClimbSecondsPerStep). The factor is generous because a good
--                player skips treads, and being wrong in this direction only costs enforcement.
function Trace.speeds(cfg: any): (number, number)
	local move = cfg.Movement
	local horizontal = move.WalkSpeed * cfg.Run.TrustedSpeedFactor
	local stepsPerStorey = math.floor(cfg.Vault.StoreyHeight / cfg.Vault.StepRise)
	local climbRate = cfg.Vault.StoreyHeight / (stepsPerStorey * move.ClimbSecondsPerStep)
	return horizontal, climbRate * cfg.Run.TrustedClimbFactor
end

-- `start` is where the SERVER put the runner, in vault-local studs — never a position the client
-- supplied. The run's first trusted position is the drop-in the server wrote itself.
function Trace.new(cfg: any, start: any): any
	local h, up = Trace.speeds(cfg)
	local burst = cfg.Run.TrustedBurstSeconds
	return {
		x = start.x, y = start.y, z = start.z,
		-- Unused allowance BANKS, up to a few seconds of it. Without this a single slow server
		-- tick or a burst of delayed replication reads as a teleport, and the honest player is
		-- the one throttled; with it, jitter is paid for out of savings and only sustained
		-- impossible speed runs the account down.
		budgetH = 0, budgetUp = 0,
		maxBudgetH = h * burst, maxBudgetUp = up * burst,
		speedH = h, speedUp = up,
		-- Diagnostics only. Nothing in the game reads these; they exist so a spec can prove the
		-- throttle actually engaged rather than inferring it from a position that agrees anyway.
		throttled = 0, drift = 0,
	}
end

-- One tick. `observed` is the client's claim in vault-local studs, `dt` the seconds since the
-- last call. Returns the trusted position — the one every rule must use.
function Trace.step(t: any, observed: any, dt: number): any
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 then dt = 0 end

	t.budgetH = math.min(t.maxBudgetH, t.budgetH + t.speedH * dt)
	t.budgetUp = math.min(t.maxBudgetUp, t.budgetUp + t.speedUp * dt)

	local dx, dz = observed.x - t.x, observed.z - t.z
	local flat = math.sqrt(dx * dx + dz * dz)
	if flat > 1e-9 then
		local allowed = math.min(flat, t.budgetH)
		t.x += dx / flat * allowed
		t.z += dz / flat * allowed
		t.budgetH -= allowed
		if allowed + 1e-9 < flat then
			t.throttled += 1
			t.drift = math.max(t.drift, flat - allowed)
		end
	end

	local dy = observed.y - t.y
	if dy > 0 then
		local allowed = math.min(dy, t.budgetUp)
		t.y += allowed
		t.budgetUp -= allowed
		if allowed + 1e-9 < dy then
			t.throttled += 1
			t.drift = math.max(t.drift, dy - allowed)
		end
	else
		-- Down is free: a runner who loses height has lost height. Following it exactly also
		-- means the collapse below reads the true number rather than a flattering one.
		t.y = observed.y
	end

	return { x = t.x, y = t.y, z = t.z }
end

return Trace
