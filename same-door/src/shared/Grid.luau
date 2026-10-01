--!strict
-- Grid.luau — lane geometry shared by the server's run monitor and the client's builder. Pure.
--
-- Lane-local coordinates: x east, z north, the grid's south-west corner at (0, 0), floor top at y 0.
-- Cell (cx, cy) spans x in [Cell*cx, Cell*cx + Cell] and z in [Cell*cy, Cell*cy + Cell]; a wall is
-- centred on a cell boundary. The antechamber is the cell (EntranceX, -1) south of the entrance, and
-- the start line is z = 0 across the entrance cell. Every day shares this grid: nothing here knows
-- a layout.

local Grid = {}

Grid.SIDES = { N = 1, E = 2, S = 4, W = 8 }

function Grid.index(x: number, y: number, W: number): number
	return y * W + x
end

function Grid.coords(i: number, W: number): (number, number)
	return i % W, i // W
end

function Grid.hasSide(mask: number, side: string): boolean
	return bit32.band(mask, Grid.SIDES[side]) ~= 0
end

-- (cx, cy, kind): kind "grid", "ante" (the antechamber) or nil (out of bounds).
function Grid.cellOf(lx: number, lz: number, cfg: any): (number?, number?, string?)
	if type(lx) ~= "number" or type(lz) ~= "number" or lx ~= lx or lz ~= lz then return nil, nil, nil end
	local g = cfg.Grid
	local c = g.Cell
	local cx, cy = math.floor(lx / c), math.floor(lz / c)
	if cx >= 0 and cx < g.W and cy >= 0 and cy < g.H then
		return cx, cy, "grid"
	end
	if cx == g.EntranceX and cy == -1 and lz >= -cfg.World.AntechamberDepth then
		return cx, cy, "ante"
	end
	return nil, nil, nil
end

function Grid.centre(cx: number, cy: number, cfg: any): (number, number)
	local c = cfg.Grid.Cell
	return cx * c + c / 2, cy * c + c / 2
end

-- Fraction along the step (x0,z0) -> (x1,z1) at which it crosses the start line northward, or nil.
function Grid.lineCrossing(x0: number, z0: number, x1: number, z1: number, cfg: any): number?
	if not (z0 < 0 and z1 >= 0) then return nil end
	local f = -z0 / (z1 - z0)
	local x = x0 + (x1 - x0) * f
	local c = cfg.Grid.Cell
	local lo = cfg.Grid.EntranceX * c
	if x < lo or x > lo + c then return nil end
	return f
end

-- Fraction along the step at which it first comes within r (horizontally) of (cx, cz), or nil.
-- 0 when it starts inside. Used for seal pickups and the Door, so a fast step never skips one.
function Grid.entryFraction(x0: number, z0: number, x1: number, z1: number, cx: number, cz: number, r: number): number?
	local fx, fz = x0 - cx, z0 - cz
	local c0 = fx * fx + fz * fz - r * r
	if c0 <= 0 then return 0 end
	local dx, dz = x1 - x0, z1 - z0
	local a = dx * dx + dz * dz
	if a <= 1e-12 then return nil end
	local b = 2 * (fx * dx + fz * dz)
	local disc = b * b - 4 * a * c0
	if disc < 0 then return nil end
	local t = (-b - math.sqrt(disc)) / (2 * a)
	if t < 0 or t > 1 then return nil end
	return t
end

-- Canonical key of the wall on `side` of cell (x, y): "E:x,y" for the wall between (x,y) and
-- (x+1,y), "N:x,y" for the wall between (x,y) and (x,y+1). Both cells name the same wall.
function Grid.edgeKey(x: number, y: number, side: string, _cfg: any): string
	if side == "E" then return "E:" .. x .. "," .. y end
	if side == "W" then return "E:" .. (x - 1) .. "," .. y end
	if side == "N" then return "N:" .. x .. "," .. y end
	return "N:" .. x .. "," .. (y - 1)
end

local function parseKey(key: string): (string?, number?, number?)
	local k, xs, ys = string.match(key, "^([EN]):(%-?%d+),(%-?%d+)$")
	if k == nil then return nil, nil, nil end
	return k, tonumber(xs), tonumber(ys)
end

function Grid.isPerimeter(key: string, cfg: any): boolean
	local k, x, y = parseKey(key)
	if k == nil then return false end
	local g = cfg.Grid
	if k == "E" then return (x :: number) <= -1 or (x :: number) >= g.W - 1 end
	return (y :: number) <= -1 or (y :: number) >= g.H - 1
end

-- The wall as a box in lane-local coordinates: centre (x, z), size (sx, sz). Walls are extended by
-- their thickness so neighbouring walls overlap at the corners and leave no pinholes.
function Grid.edgeSegment(key: string, cfg: any): any?
	local k, x, y = parseKey(key)
	if k == nil then return nil end
	local c, t = cfg.Grid.Cell, cfg.Grid.WallThick
	if k == "E" then
		return { x = ((x :: number) + 1) * c, z = (y :: number) * c + c / 2, sx = t, sz = c + t }
	end
	return { x = (x :: number) * c + c / 2, z = ((y :: number) + 1) * c, sx = c + t, sz = t }
end

-- World origin of lane i (1-based): the grid's south-west corner at floor level.
function Grid.laneOrigin(i: number, cfg: any): { x: number, y: number, z: number }
	return { x = (i - 1) * cfg.World.LaneSpacing, y = cfg.World.FloorY, z = cfg.World.LaneZ }
end

return Grid
