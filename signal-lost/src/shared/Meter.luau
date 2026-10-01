--!strict
-- Meter.luau — the SIGNAL meter (DESIGN.md §2.4). PURE, requires nothing.
--
-- bars = clamp(5 - floor(d), 1, 5), where d is the straight-line distance in MODULES between the centre of
-- the module the server trusts you are in and the centre of the relay's module. Five bars: you are in the
-- relay module; four: next to it (1 or 1.41); one: four or more away. The SERVER computes it and pushes the
-- bars, never d, never a cell (§11.3).

local Meter = {}

-- Straight-line distance in modules between two module ids on an n x n grid (id = y n + x + 1).
function Meter.distance(n: number, a: number, b: number): number
	local ax, ay = (a - 1) % n, (a - 1) // n
	local bx, by = (b - 1) % n, (b - 1) // n
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

function Meter.bars(cfg: any, d: number): number
	local maxBars, minBars = cfg.Signal.MaxBars, cfg.Signal.MinBars
	if type(d) ~= "number" or d ~= d then
		return minBars
	end
	-- 1e-9: sqrt(2) and friends are exact enough, but a distance of 4 computed as 3.9999999 must read 1 bar
	return math.clamp(maxBars - math.floor(d + 1e-9), minBars, maxBars)
end

function Meter.between(cfg: any, n: number, here: number, relay: number): number
	return Meter.bars(cfg, Meter.distance(n, here, relay))
end

return Meter
