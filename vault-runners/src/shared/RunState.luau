--!strict
-- RunState.luau — én løpetur gjennom hvelvet, som REN logikk.
--
-- The entire risk of Vault Runners lives in this file: gems you are carrying are worth nothing
-- until you are out, and the vault seals on a countdown. Reaching the exit is not the win
-- condition — reaching it BEFORE `sealAt` is.
--
-- Pure by construction: no Roblox global, no clock of its own, no geometry. `now` is always
-- passed in (the server's run loop accumulates it from task.wait, which is virtual time under
-- the emulator and wall time in Roblox), and the collapse plane is computed from a `geom` table
-- the caller already has. That is what lets tests/RunState.spec.luau assert every boundary
-- exactly, in the luau CLI, with no engine present.
--
-- Dependencies are ARGUMENTS. Nothing in here requires anything.

local RunState = {}

export type Result = {
	ok: boolean,
	banked: number,
	carried: number,
	reason: string,
}

-- spec = { tier, floor, collapseSeconds, gemValue, gemCount }
-- `now` is the run-loop clock at the moment the runner dropped in.
function RunState.start(cfg: any, spec: any, now: number): any
	local _ = cfg -- cfg is accepted so every pure module in this game has the same shape
	return {
		tier = spec.tier,
		floor = spec.floor,
		gemValue = spec.gemValue,
		gemCount = spec.gemCount,
		collapseSeconds = spec.collapseSeconds,
		startedAt = now,
		sealAt = now + spec.collapseSeconds,
		carried = 0,   -- gems in hand, worth nothing yet
		banked = 0,    -- gems that made it out
		lost = 0,      -- gems the vault kept
		alive = true,
		escaped = false,
		collected = {},
	}
end

--============================================================================ clock

function RunState.timeLeft(run: any, now: number): number
	return math.max(0, run.sealAt - now)
end

-- INCLUSIVE at sealAt. A boundary that pays out on the exact second is a boundary players
-- learn to sit on, and "escaped at 0.0 seconds" would then be the safest way to play.
function RunState.isSealed(run: any, now: number): boolean
	return now >= run.sealAt
end

-- 0 at the drop-in, 1 at the seal. Clamped both ends so a stale `now` can never drive the
-- collapse plane out of the vault.
function RunState.collapseProgress(run: any, now: number): number
	if run.collapseSeconds <= 0 then return 1 end
	return math.clamp((now - run.startedAt) / run.collapseSeconds, 0, 1)
end

-- Height of the rising kill plane. `geom.killPlane` comes straight from VaultFloor.build, so
-- the plane reaches the top storey exactly as the vault seals — one countdown, drawn twice.
function RunState.planeY(run: any, geom: any, now: number): number
	local k = geom.killPlane
	return k.startY + (k.endY - k.startY) * RunState.collapseProgress(run, now)
end

function RunState.status(run: any, now: number): string
	if run.escaped then return "escaped" end
	if not run.alive then
		-- A runner who was still holding gems when the vault sealed is not the same story as
		-- one the collapse caught, and the HUD says so.
		return run.sealedIn and "sealed" or "dead"
	end
	if RunState.isSealed(run, now) then return "sealed" end
	return "running"
end

--============================================================================ gems

-- Never a silent no-op: every refusal returns a reason the server can put on screen.
function RunState.collect(run: any, gemId: number, value: number, _now: number): (boolean, string?)
	if run.escaped then return false, "escaped" end
	if not run.alive then return false, "dead" end
	if run.collected[gemId] then return false, "already" end
	run.collected[gemId] = true
	run.carried += value
	return true, nil
end

function RunState.collectedCount(run: any): number
	local n = 0
	for _ in pairs(run.collected) do n += 1 end
	return n
end

--============================================================================ the exit

-- THE RULE. `mult` is the equipped pet's multiplier and applies HERE, at the bank, not at
-- pickup: a pet is only ever worth what you actually escape with.
function RunState.tryEscape(run: any, mult: number, now: number): Result
	local carried = run.carried

	if run.escaped then
		return { ok = false, banked = 0, carried = carried, reason = "escaped" }
	end
	if not run.alive then
		return { ok = false, banked = 0, carried = carried, reason = "dead" }
	end

	if RunState.isSealed(run, now) then
		-- Too slow. The door is shut, and everything in your hands stays in the vault.
		run.carried = 0
		run.lost += carried
		run.alive = false
		run.sealedIn = true
		return { ok = false, banked = 0, carried = carried, reason = "sealed" }
	end

	local banked = math.floor(carried * mult)
	run.carried = 0
	run.banked += banked
	run.escaped = true
	return { ok = true, banked = banked, carried = carried, reason = "escaped" }
end

-- The collapse caught you (or anything else killed you). Same outcome as the seal for the gems;
-- different story for the player.
function RunState.kill(run: any, _now: number, cause: string?): any
	if run.escaped or not run.alive then
		return { lost = 0, cause = cause or "collapse" }
	end
	local lost = run.carried
	run.carried = 0
	run.lost += lost
	run.alive = false
	return { lost = lost, cause = cause or "collapse" }
end

return RunState
