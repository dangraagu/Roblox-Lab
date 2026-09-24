--!strict
-- CellHazards.luau — rare, telegraphed hazards that fall into one maze cell. Pure, no Roblox.
--
-- Why this is not the +1 Jump `Hazards` template: that one launches a random lane at the player
-- from where the camera looks, on a random clock. The labyrinth is a TIMED game whose medal times
-- come from a shared seed, so a hazard here must be part of the LEVEL, like the lava pulse:
--   * WHERE: a pure function of (level, maze size, trap cells). Never the start, the exit, a trap
--     cell, or within StartClearCells of the start; never two within MinSpacing cells. Density
--     keeps them rare. No RNG state, no clock, no player: everyone on level 140 gets the same cells.
--   * WHEN: each hazard cell runs a fixed cycle on the level clock (seconds since the level began):
--     quiet, a WarnSeconds warning, ONE impact instant, harmless debris. The first impact is never
--     inside GraceSeconds. Two players on the same level meet the same impacts at the same moments
--     of their run.
--   * WHETHER IT HIT: an impact instant inside the frame and the player's root within StrikeRadius +
--     PlayerRadius of the cell centre (horizontal). That zone fits inside the cell, so the passage
--     next to it is always safe: a hazard can make you wait, it can never wall a level off.
--   * HOW HARD: knocked down (KnockSeconds) with a small horizontal push away from the impact,
--     capped so it can never carry you onto the next cell's trap. Only up to MaxHitHeight over the
--     floor: a jump is no dodge, a god-mode flyer over the maze is not knocked out of the air.
-- Vectors are plain { x, y, z } tables. The caller renders and applies the knock.

local CellHazards = {}

CellHazards.SERVER_CELL_SIZE = 9 -- MazeGame.server CONFIG.CellSize
CellHazards.MIN_WARN_FLOOR = 2   -- "easy to see coming": no config may warn for less
CellHazards.MAX_DENSITY = 0.1    -- "rare": never more than one cell in ten
CellHazards.MIN_HIT_HEIGHT = 12  -- studs over the floor: a jumping player's root peaks near 10.5

-- Deterministic [0, 1) from integers (same construction as EnvBands.hash01; kept local so this
-- module needs no dependency). Every intermediate stays under 2^53.
local function hash01(a: number, b: number, c: number, seed: number): number
	local h = (seed % 2147483647 + 2147483647) % 2147483647
	for _, v in { a, b, c } do
		local x = (math.floor(v) % 2147483647 + 2147483647) % 2147483647
		h = (h * 31 + x + 7919) % 2147483647
		h = (h * 48271) % 2147483647
		h = (h * 16807 + 12345) % 2147483647
	end
	return h / 2147483647
end
CellHazards.hash01 = hash01

local function num(x: any): boolean
	return type(x) == "number" and x == x
end

function CellHazards.validate(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no hazard config" end
	for _, k in { "CellSize", "Period", "WarnSeconds", "MinWarnSeconds", "DebrisSeconds", "StrikeRadius", "PlayerRadius",
		"KnockSeconds", "KnockPush", "MaxKnockDisplacement", "Density", "MaxPerLevel", "MinSpacing", "StartClearCells",
		"GraceSeconds", "MaxHitHeight" } do
		if not num(cfg[k]) then return false, k .. " must be a number" end
	end
	if cfg.CellSize ~= CellHazards.SERVER_CELL_SIZE then
		return false, "CellSize must be the server's CONFIG.CellSize (" .. CellHazards.SERVER_CELL_SIZE .. ")"
	end
	if cfg.MinWarnSeconds < CellHazards.MIN_WARN_FLOOR then
		return false, "MinWarnSeconds must be >= " .. CellHazards.MIN_WARN_FLOOR
	end
	if cfg.WarnSeconds < cfg.MinWarnSeconds then return false, "WarnSeconds shorter than MinWarnSeconds" end
	if cfg.DebrisSeconds < 0 then return false, "DebrisSeconds must be >= 0" end
	if cfg.Period < cfg.WarnSeconds + cfg.DebrisSeconds + 3 then
		return false, "Period must leave a quiet gap of 3 s after the warning and the debris"
	end
	if cfg.StrikeRadius <= 0 or cfg.PlayerRadius <= 0 then return false, "radii must be > 0" end
	if cfg.StrikeRadius + cfg.PlayerRadius > cfg.CellSize / 2 then
		return false, "the danger zone must fit inside the cell (the passage next to it stays a safe place to wait)"
	end
	if cfg.KnockSeconds < 0 or cfg.KnockPush < 0 then return false, "knock must be >= 0" end
	if cfg.KnockPush * cfg.KnockSeconds > cfg.MaxKnockDisplacement then
		return false, "KnockPush * KnockSeconds exceeds MaxKnockDisplacement"
	end
	local trapHalf = (cfg.CellSize - 2) / 2 -- a trap plate is CellSize - 2 wide, centred in its cell
	if cfg.StrikeRadius + cfg.PlayerRadius + cfg.MaxKnockDisplacement >= 2 * cfg.CellSize - trapHalf - cfg.PlayerRadius then
		return false, "a knock could carry the player onto the neighbouring cell's trap"
	end
	if cfg.GraceSeconds < cfg.WarnSeconds then return false, "GraceSeconds must cover the first warning" end
	if cfg.MaxHitHeight < CellHazards.MIN_HIT_HEIGHT then
		return false, "MaxHitHeight must be >= " .. CellHazards.MIN_HIT_HEIGHT .. " (a jump must never dodge an impact; stepping out of the ring does)"
	end
	if cfg.Density < 0 or cfg.Density > CellHazards.MAX_DENSITY then
		return false, "Density must be within 0.." .. CellHazards.MAX_DENSITY
	end
	if cfg.MaxPerLevel < 0 then return false, "MaxPerLevel must be >= 0" end
	if cfg.MinSpacing < 1 then return false, "MinSpacing must be >= 1" end
	if cfg.StartClearCells < 1 then return false, "StartClearCells must be >= 1" end
	if type(cfg.Kinds) ~= "table" then return false, "no Kinds" end
	for name, k in cfg.Kinds do
		if type(k) ~= "table" or type(k.label) ~= "string" then return false, "kind " .. tostring(name) .. " has no label" end
	end
	return true, nil
end

-- The hazard cells of a level: { { cx, cy, phase } }, phase in [0, Period).
-- trapSet: { ["cx,cy"] = true } — the server's trap cells, read from its replicated Trap parts.
function CellHazards.pick(level: number, cols: number, rows: number, trapSet: { [string]: boolean }, seed: number, cfg: any): { any }
	local L = math.floor(level)
	local cands = {}
	for cy = 0, rows - 1 do
		for cx = 0, cols - 1 do
			local start = cx == 0 and cy == 0
			local exit = cx == cols - 1 and cy == rows - 1
			local nearStart = math.max(cx, cy) <= cfg.StartClearCells
			if not start and not exit and not nearStart and not trapSet[cx .. "," .. cy] then
				table.insert(cands, { cx = cx, cy = cy, h = hash01(cx, cy, L, seed) })
			end
		end
	end
	table.sort(cands, function(a: any, b: any): boolean
		if a.h ~= b.h then return a.h < b.h end
		if a.cy ~= b.cy then return a.cy < b.cy end
		return a.cx < b.cx
	end)
	local target = math.min(cfg.MaxPerLevel, math.floor(cfg.Density * cols * rows + 0.5))
	local out = {}
	for _, c in cands do
		if #out >= target then break end
		local clear = true
		for _, o in out do
			if math.max(math.abs(o.cx - c.cx), math.abs(o.cy - c.cy)) < cfg.MinSpacing then
				clear = false
				break
			end
		end
		if clear then
			table.insert(out, { cx = c.cx, cy = c.cy, phase = hash01(c.cy + 17, c.cx + 31, L, seed) * cfg.Period })
		end
	end
	return out
end

function CellHazards.firstImpact(hz: any, cfg: any): number
	return cfg.GraceSeconds + hz.phase
end

-- The first impact at or after level-time t.
function CellHazards.nextImpact(hz: any, t: number, cfg: any): number
	local first = CellHazards.firstImpact(hz, cfg)
	if t <= first then return first end
	local k = math.ceil((t - first) / cfg.Period)
	return first + k * cfg.Period
end

-- ("idle" | "warn" | "debris", progress 0..1) at level-time t.
function CellHazards.stateAt(hz: any, t: number, cfg: any): (string, number)
	local first = CellHazards.firstImpact(hz, cfg)
	if not num(t) or t < first - cfg.WarnSeconds then return "idle", 0 end
	local T = CellHazards.nextImpact(hz, t, cfg)
	if T - t <= cfg.WarnSeconds then
		return "warn", math.clamp(1 - (T - t) / cfg.WarnSeconds, 0, 1)
	end
	local prev = T - cfg.Period
	if prev >= first - 1e-9 and t - prev < cfg.DebrisSeconds then
		return "debris", math.clamp((t - prev) / cfg.DebrisSeconds, 0, 1)
	end
	return "idle", 0
end

-- Impact times in (t0, t1].
function CellHazards.impactsBetween(hz: any, t0: number, t1: number, cfg: any): { number }
	local out = {}
	if not num(t0) or not num(t1) or t1 <= t0 then return out end
	local first = CellHazards.firstImpact(hz, cfg)
	local k = math.max(0, math.floor((t0 - first) / cfg.Period) + 1)
	local T = first + k * cfg.Period
	-- floor() of an exact multiple can land one short; never report t0 itself
	if T <= t0 then
		k += 1
		T = first + k * cfg.Period
	end
	while T <= t1 do
		table.insert(out, T)
		k += 1
		T = first + k * cfg.Period
		if #out > 10000 then break end
	end
	return out
end

function CellHazards.inZone(centre: any, playerPos: any, cfg: any): boolean
	local dx, dz = playerPos.x - centre.x, playerPos.z - centre.z
	local r = cfg.StrikeRadius + cfg.PlayerRadius
	return dx * dx + dz * dz <= r * r
end

-- Did an impact of `hz` (at world `centre`, the floor's top) land on the player during (t0, t1]?
-- Horizontal zone, plus a height cap: the object falls into the cell from over the walls, so it hits
-- anyone standing or jumping in the ring, and nobody flying (god mode) high above the maze.
function CellHazards.checkHit(hz: any, centre: any, t0: number, t1: number, playerPos: any, cfg: any): boolean
	if not CellHazards.inZone(centre, playerPos, cfg) then return false end
	local above = (playerPos.y or 0) - (centre.y or 0)
	if above > cfg.MaxHitHeight then return false end
	return #CellHazards.impactsBetween(hz, t0, t1, cfg) > 0
end

-- (velocity, standSeconds): horizontal, away from the impact, never up.
function CellHazards.knock(centre: any, playerPos: any, cfg: any): (any, number)
	local dx, dz = playerPos.x - centre.x, playerPos.z - centre.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.05 then
		dx, dz, len = 1, 0, 1
	end
	return { x = dx / len * cfg.KnockPush, y = 0, z = dz / len * cfg.KnockPush }, cfg.KnockSeconds
end

return CellHazards
