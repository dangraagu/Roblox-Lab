--!strict
-- Ledger.luau — the server's travel ledger (DESIGN.md §10.3), which decides whether a Perfect Shift counts
-- on the highscore board. Pure, requires nothing; tests/Ledger.spec.luau.
--
-- From a shift's first accepted interaction (a pick, a deposit, a put-back), each one adds
--     max(0, |p - pPrev| - PositionSlack) / (WalkSpeed * SpeedTolerance)
-- seconds to `required`, where p is the server-observed root-part position (x, z), and the ledger holds
-- while  elapsed + LatencySlack >= required.  The latency slack is granted ONCE per ledger: a draft that
-- granted it per leg let a bot clear 30 items in 4.3 s (design/model.luau), because on short legs the
-- per-leg slack is longer than the leg.
--
-- It refuses nothing. A broken ledger only means the shift is not counted on the board (sticky for the
-- shift); the sort, the pay, the Perfect and the personal best all stand. `cfg` is Config.Ledger.

local Ledger = {}

export type Ledger = { t0: number?, required: number, x: number, z: number, broken: boolean }

function Ledger.new(): Ledger
	return { t0 = nil, required = 0, x = 0, z = 0, broken = false }
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- One accepted interaction at (x, z) at time `now`, while the player's shoes give `speed`. Commits it and
-- returns whether the ledger holds at this step. Junk (a NaN position, a speed of 0) fails closed.
function Ledger.step(L: Ledger, now: number, x: number, z: number, speed: number, cfg: any): boolean
	if not (finite(now) and finite(x) and finite(z) and finite(speed)) or speed <= 0 then
		L.broken = true
		return false
	end
	if L.t0 == nil then
		L.t0 = now
		L.x, L.z = x, z
		return true
	end
	local d = math.sqrt((x - L.x) ^ 2 + (z - L.z) ^ 2)
	L.required += math.max(0, d - cfg.PositionSlack) / (speed * cfg.SpeedTolerance)
	L.x, L.z = x, z
	local ok = (now - (L.t0 :: number)) + cfg.LatencySlack >= L.required
	if not ok then
		L.broken = true
	end
	return ok
end

function Ledger.verified(L: Ledger): boolean
	return not L.broken
end

return Ledger
