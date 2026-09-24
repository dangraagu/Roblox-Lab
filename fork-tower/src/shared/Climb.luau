--!strict
-- Climb.luau — Fork Tower's progress value, the fork-pad sanctuary and the hazard gate. Pure.
--
-- The environment bands (EnvBands, copied verbatim from +1 Jump) blend on a continuous progress
-- value. In Fork Tower that value is FLOORS CLIMBED:
--
--     progress = (floor - 1) + the fraction of the current section's height the player has climbed
--
-- and it is built so that nothing the inscription sells can reach it:
--   * at a fork (the door not chosen, so the floor's section does not exist yet) it is EXACTLY
--     floor - 1. The world in front of two unread doors is a function of the floor number and
--     nothing else. The trap side, the traits and the floor's secret are not inputs here, and
--     they are not on the client's wire either (REVIEW-4, check_forktower_plansecret);
--   * climbing, the fraction is measured against the section the player already chose, so a
--     trapped (longer) section moves the blend more slowly only after the choice was made;
--   * the fraction clamps to [0, 1]: a fall never takes the world back, and nothing runs ahead of
--     the next fork.
--
-- The SANCTUARY is the fork pad (and the lobby and summit pads): hazards never run, launch or hit
-- there. Reading the inscription costs Config.Fork.ReadSeconds on the SERVER's clock and that
-- price is measured against never reading (tests/readcost.measure.luau); a hazard that could knock
-- a reader off the pad would add a cost the measurement never priced. See Climb.gate.
--
-- Plain tables only, no Roblox: runs in the luau CLI (tests/Climb.spec.luau).

local Climb = {}

local function isNaN(x: number): boolean
	return x ~= x
end

local function clampFloor(level: number, floors: number): number
	if type(level) ~= "number" or isNaN(level) then return 1 end
	return math.clamp(math.floor(level), 1, floors)
end

-- Floors climbed. `level` is the server's floor (leaderstats / the highest fork built), `summit`
-- whether the summit exists, `y` the player's FEET height, forkY[n] fork n's pad top, exitY[n]
-- section n's exit platform top (nil until the door is chosen).
function Climb.progress(level: number, summit: boolean, y: number, forkY: { [number]: number },
	exitY: { [number]: number }, floors: number): number
	if summit then return floors end
	local n = clampFloor(level, floors)
	local base = n - 1
	local lo, hi = forkY[n], exitY[n]
	if lo == nil or hi == nil or hi - lo <= 1e-6 then return base end
	if type(y) ~= "number" or isNaN(y) then return base end
	return base + math.clamp((y - lo) / (hi - lo), 0, 1)
end

-- The floor a band is NAMED by: the number the HUD shows ("ETASJE n/10"), and one past the top at
-- the summit. Bands are named by it and blended by progress; at every fork the two agree
-- (namedFloor - 1 == progress), so the chip, the title card and the sky never disagree.
function Climb.namedFloor(level: number, summit: boolean, floors: number): number
	if summit then return floors + 1 end
	return clampFloor(level, floors)
end

-- Is `pos` (the root part) over `pad` = { x, y, z, sx, sz } (top-centre and footprint)? The
-- footprint is grown by the player's radius, since a body overlapping the pad is standing on it,
-- and it reaches `ceiling` studs above the top, so a hop on the pad does not leave it.
function Climb.onPad(pos: any, pad: any, radius: number, ceiling: number): boolean
	local x, y, z = pos.x, pos.y, pos.z
	if isNaN(x) or isNaN(y) or isNaN(z) then return false end
	if math.abs(x - pad.x) > pad.sx / 2 + radius then return false end
	if math.abs(z - pad.z) > pad.sz / 2 + radius then return false end
	return y >= pad.y and y <= pad.y + ceiling
end

function Climb.inSanctuary(pos: any, pads: { any }, radius: number, ceiling: number): boolean
	for _, pad in pads do
		if Climb.onPad(pos, pad, radius, ceiling) then return true end
	end
	return false
end

-- What hazards may do this frame. ctx = { climbing, sanctuary, resting }:
--   climbing  — the current floor's section exists (door chosen) and this is not the summit;
--   sanctuary — the root is over a fork, lobby or summit pad;
--   resting   — Rest says so.
-- clock:   the hazard clock runs ONLY while climbing, off a pad, not resting. Time spent reading and
--          deciding at a fork therefore never brings a hazard closer.
-- launch:  never without the clock.
-- hit:     only while climbing, and never on a pad. Resting does NOT cancel a hazard already in
--          flight (Rest.luau: rest is never a panic button, and it cannot start with a threat
--          inbound anyway).
-- dismiss: a hazard in flight when the player reaches a pad fizzles out, and so does one in flight
--          when the floor is CLEARED (not climbing any more), wherever the player stands. The next
--          fork's LES prompt reaches 16 studs (Main.server) and its pad sits 2 studs past the exit,
--          so the exit's front edge is in reach of the read and off the pad: measured 2026-09-24
--          (review), a hazard launched in the last seconds of the climb knocked a player who began
--          the read there 0.97 s into the 1.1 s hold. From the floor clear on, the player can be
--          reading, so nothing flies at them. Reaching the exit or the next fork is progress, not a
--          dodge; a hazard takes nothing anyway.
function Climb.gate(ctx: any): { clock: boolean, launch: boolean, hit: boolean, dismiss: boolean }
	local climbing = ctx.climbing == true
	local sanctuary = ctx.sanctuary == true
	local clock = climbing and not sanctuary and ctx.resting ~= true
	return {
		clock = clock,
		launch = clock,
		hit = climbing and not sanctuary,
		dismiss = sanctuary or not climbing,
	}
end

-- Lighting.ClockTime is a DIAL. Bands blend it linearly, which is right between bands (their times
-- only ever rise up the tower; EnvConfig.spec), but a glide across a JUMP in progress — a rebirth
-- from the night summit (23.95) back to the dungeon (0.5), or a join from the server's preset — must
-- take the short way round, through midnight, not back through noon. The reading of `current`
-- (mod 24) nearest to `target`: approach() from it then takes the short arc.
function Climb.nearestClock(current: number, target: number): number
	local c = current % 24
	local d = (c - target) % 24 -- [0, 24)
	if d > 12 then d -= 24 end
	return target + d
end

-- A clock reading folded onto [0, 24), for writing.
function Climb.clockOf(t: number): number
	return t % 24
end

return Climb
