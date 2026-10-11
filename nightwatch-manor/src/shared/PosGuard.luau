--!strict
-- PosGuard.luau — the position guard: what the server makes of where a character IS, every tick of a night.
-- PURE: config, plan and its two dependencies (Manor, Crossing) are passed in (tests/PosGuard.spec.luau).
--
-- Why it exists (second review, 2026-10-09, HIGH). The exit's guard (Crossing.verdictFor) measures the night's clock
-- and the room at the moment of the press, and nothing in between. The Nightwatcher sees by ROOM (Manor.roomAtWorld),
-- so a character standing outside every room is never seen. A script could therefore teleport out of the manor, wait
-- out the clock in perfect safety, teleport into the exit room and press E: one night every ~12 s, the board's 500
-- nights in under two hours. A player's own client moves their character in Roblox, so the server cannot stop the
-- teleport; it can refuse to COUNT a night in which one happened. Two kinds of evidence void a night:
--
--   * OUTSIDE. The root is in no room of the manor. A walking player's root cannot be: every room is closed by
--     walls whose faces are half a stud inside the room's cell, and the doorways are on the planes between two cells.
--     Config.Guard.OutsideGraceSeconds of it, in total over the night, is forgiven (a stray sample), counted a
--     tick at a time; the bank below does not refill out there.
--   * JUMP. The root covered more ground than a walk allows. The allowance is a BANK of studs: it starts at
--     Config.Guard.JumpSlack, refills at WalkSpeed * (1 + SpeedSlack) for every second the server's clock runs, and
--     holds at most `cap` = JumpSlack + LagSeconds of refill. So waiting buys nothing past the cap, while a client
--     that goes silent for a few seconds and then reports where it walked to is made up in one sample. Every sample
--     spends the shortest LEGAL walk from the last one (`cost`: the straight line inside a room, the walk through
--     the doorways between rooms, Crossing.walkBound), so a hop through a wall costs the way round by the door.
--
-- Both are lower bounds on what a walking player does: the cost is never more than a walk a player can really make
-- between the two points, and the bank refills faster than a player walks. The spec walks 240 salted manors and the
-- public nights 1-150 through it, with jittered ticks, latency swings and lag gaps, and states the margins.
--
-- SETTLING. When the server itself places the character (the night's start, a respawn), the engine and the client
-- may show it somewhere else for a moment (a new character is dropped on the safehouse's SpawnLocation first:
-- robloxemu/SPAWN-ORDER.md). For Config.Guard.SettleSeconds after a (re)seed nothing is judged; after it, the walk is
-- measured from where the SERVER put the character, with the bank the window earned. A press of the exit is judged
-- even inside the window (`final`), so the window is never a way out.
--
-- What it does NOT do (EYECANDY.md, "Night shift 2026-10-11"): it cannot tell a script that walks from a person who
-- does, and inside the bank's cap a hop looks exactly like a lag gap.

local PosGuard = {}

export type State = {
	x: number, -- the last judged position, manor studs (the server's placement until the first sample after it)
	z: number,
	bank: number, -- studs of walking in hand
	outside: number, -- seconds of this night spent in no room
	settle: number, -- seconds left before samples are judged
}

-- Studs per second the bank refills at.
function PosGuard.rate(cfg: any): number
	return cfg.Player.WalkSpeed * (1 + cfg.Guard.SpeedSlack)
end

-- The most the bank holds.
function PosGuard.cap(cfg: any): number
	return cfg.Guard.JumpSlack + PosGuard.rate(cfg) * cfg.Guard.LagSeconds
end

-- A night begins: the server has put the character at (x, z).
function PosGuard.seed(cfg: any, x: number, z: number): State
	return { x = x, z = z, bank = cfg.Guard.JumpSlack, outside = 0, settle = cfg.Guard.SettleSeconds }
end

-- The server has put the character somewhere again (a respawn). The outside time already on the record stays.
function PosGuard.reseed(cfg: any, st: State, x: number, z: number)
	st.x, st.z = x, z
	st.bank = cfg.Guard.JumpSlack
	st.settle = cfg.Guard.SettleSeconds
end

-- The shortest legal walk from (x1, z1) to (x2, z2): never more than a walk a player can make between them.
-- `M` is Manor, `C` is Crossing (shared modules take their dependencies as arguments).
function PosGuard.cost(cfg: any, plan: any, M: any, C: any, x1: number, z1: number, x2: number, z2: number): number
	local straight = math.sqrt((x1 - x2) ^ 2 + (z1 - z2) ^ 2)
	local a = M.roomAtWorld(plan, cfg, x1, z1)
	local b = M.roomAtWorld(plan, cfg, x2, z2)
	if a == nil or b == nil or a == b then
		return straight
	end
	-- both are lower bounds on the real walk, so the larger one is too
	return math.max(straight, C.walkBound(cfg, plan, a, x1, z1, b, x2, z2, 0))
end

-- One sample: the root is at (x, z), `dt` seconds of the server's clock after the last one. -> ok, why
-- ("outside" | "jump"). `final` is the exit's own press: judged even while settling (dt 0: no time has passed).
-- A refusal leaves the state as it was.
function PosGuard.step(cfg: any, plan: any, M: any, C: any, st: State, x: number, z: number, dt: number, final: boolean?): (boolean, string?)
	if dt ~= dt or dt < 0 then
		dt = 0
	end
	local cap = PosGuard.cap(cfg)
	-- the tick's own time is always usable (a server hitch is not the player's doing); only what is LEFT is capped
	local avail = st.bank + PosGuard.rate(cfg) * dt
	if st.settle > 1e-9 and final ~= true then
		st.settle -= dt
		st.bank = math.min(cap, avail)
		return true, nil
	end
	local finite = x == x and z == z and math.abs(x) ~= math.huge and math.abs(z) ~= math.huge
	local room = if finite then M.roomAtWorld(plan, cfg, x, z) else nil
	if room == nil then
		-- in no room. Not a place to measure a walk from: the last judged position stands, and the way back in is
		-- charged from there.
		-- Counted a tick at a time (one stray sample in a long server hitch is still one sample), and the bank does
		-- NOT refill out here: time spent where the Nightwatcher cannot see buys no ground.
		local counted = math.min(dt, cfg.TickSeconds)
		if st.outside + counted > cfg.Guard.OutsideGraceSeconds then
			return false, "outside"
		end
		st.outside += counted
		return true, nil
	end
	local cost = PosGuard.cost(cfg, plan, M, C, st.x, st.z, x, z)
	if cost > avail then
		return false, "jump"
	end
	st.bank = math.min(cap, avail - cost)
	st.x, st.z = x, z
	return true, nil
end

return PosGuard
