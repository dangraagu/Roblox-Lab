-- Spec for Grid: lane geometry shared by the server's run monitor and the client's builder.
-- Run: luau tests/Grid.spec.luau
--
-- Lane-local coordinates: x east, z north, the grid's south-west corner at (0, 0), cells 16 studs.
-- Cell (cx, cy) spans x in [16 cx, 16 cx + 16], z in [16 cy, 16 cy + 16]. The antechamber is the
-- cell (4, -1) south of the entrance; the start line is z = 0 across the entrance cell. Nothing here
-- knows a layout: it is pure arithmetic on the fixed grid every day shares.
local Grid = require("../src/shared/Grid")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function approx(a, b, msg, tol)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local cfg = Config

--================================================================ cells
do
	local cx, cy, kind = Grid.cellOf(72, 8, cfg)
	eq(cx, 4, "x 72 is column 4"); eq(cy, 0, "z 8 is row 0"); eq(kind, "grid", "inside the grid")
	cx, cy, kind = Grid.cellOf(72, -8, cfg)
	eq(kind, "ante", "z -8 over the entrance column is the antechamber"); eq(cy, -1, "row -1")
	local _, _, k2 = Grid.cellOf(40, -8, cfg)
	eq(k2, nil, "south of the grid but not over the entrance is out of bounds")
	local _, _, k3 = Grid.cellOf(144.01, 8, cfg)
	eq(k3, nil, "east of the grid is out of bounds")
	local _, _, k4 = Grid.cellOf(143.99, 143.99, cfg)
	eq(k4, "grid", "the far corner is inside")
	local _, _, k5 = Grid.cellOf(0 / 0, 8, cfg)
	eq(k5, nil, "NaN is out of bounds")
	local _, _, k6 = Grid.cellOf(72, -16.5, cfg)
	eq(k6, nil, "south of the antechamber is out of bounds")
end

do
	local x, z = Grid.centre(4, 0, cfg)
	eq(x, 72, "the entrance centre x"); eq(z, 8, "the entrance centre z")
	local ax, az = Grid.centre(4, -1, cfg)
	eq(ax, 72, "the antechamber centre x"); eq(az, -8, "the antechamber centre is 8 studs south of the line")
end

eq(Grid.index(4, 0, 9), 4, "index of the entrance")
eq(Grid.index(8, 8, 9), 80, "index of the last cell")
do
	local x, y = Grid.coords(40, 9)
	eq(x, 4, "coords x"); eq(y, 4, "coords y")
end

--================================================================ the start line
do
	approx(Grid.lineCrossing(72, -0.5, 72, 0.5, cfg), 0.5, "a northward crossing at the middle of the step")
	eq(Grid.lineCrossing(72, 0.5, 72, -0.5, cfg), nil, "a southward crossing does not start a run")
	eq(Grid.lineCrossing(72, -2, 72, -1, cfg), nil, "no crossing")
	eq(Grid.lineCrossing(60, -1, 60, 1, cfg), nil, "crossing z = 0 outside the entrance gap is not the line")
	approx(Grid.lineCrossing(72, -1, 72, 3, cfg), 0.25, "fraction along the segment")
end

--================================================================ reaching a point (seal / Door): first entry along a step
do
	approx(Grid.entryFraction(0, 0, 10, 0, 8, 0, 4), 0.4, "a step from 0 to 10 enters a 4-radius circle at 8 at x = 4")
	eq(Grid.entryFraction(0, 0, 10, 0, 8, 5, 4), nil, "a step passing 5 away misses a radius 4")
	eq(Grid.entryFraction(7, 0, 10, 0, 8, 0, 4), 0, "starting inside counts at the start")
	approx(Grid.entryFraction(0, 0, 0, 10, 3, 5, 4), (5 - math.sqrt(7)) / 10, "a tangent-ish pass enters on the chord", 1e-9)
	eq(Grid.entryFraction(0, 0, 0, 0, 8, 0, 4), nil, "a zero-length step outside the circle")
end

--================================================================ walls: every edge has one key
do
	local k1 = Grid.edgeKey(3, 3, "E", cfg)
	local k2 = Grid.edgeKey(4, 3, "W", cfg)
	eq(k1, k2, "the east wall of (3,3) is the west wall of (4,3)")
	eq(Grid.edgeKey(3, 3, "N", cfg), Grid.edgeKey(3, 4, "S", cfg), "north of (3,3) is south of (3,4)")
	truthy(Grid.isPerimeter(Grid.edgeKey(0, 3, "W", cfg), cfg), "the west edge of column 0 is perimeter")
	truthy(Grid.isPerimeter(Grid.edgeKey(8, 3, "E", cfg), cfg), "the east edge of column 8 is perimeter")
	truthy(Grid.isPerimeter(Grid.edgeKey(3, 8, "N", cfg), cfg), "the north edge of row 8 is perimeter")
	truthy(Grid.isPerimeter(Grid.edgeKey(3, 0, "S", cfg), cfg), "the south edge of row 0 is perimeter")
	truthy(not Grid.isPerimeter(Grid.edgeKey(3, 3, "E", cfg), cfg), "an inner edge is not")
	local seg = Grid.edgeSegment(Grid.edgeKey(3, 3, "E", cfg), cfg)
	eq(seg.x, 64, "the wall between columns 3 and 4 is centred on x = 64")
	eq(seg.z, 56, "…at the middle of row 3")
	eq(seg.sx, 2, "…2 thick")
	eq(seg.sz, 18, "…and 18 long, so it overlaps its neighbours at the corners (no pinholes)")
	local segN = Grid.edgeSegment(Grid.edgeKey(3, 3, "N", cfg), cfg)
	eq(segN.z, 64, "the wall between rows 3 and 4 is centred on z = 64")
	eq(segN.sx, 18, "a north wall runs along x")
end

--================================================================ sides bitmask
eq(Grid.SIDES.N + Grid.SIDES.E + Grid.SIDES.S + Grid.SIDES.W, 15, "four sides, four bits")
eq(Grid.hasSide(5, "N"), true, "5 has N")
eq(Grid.hasSide(5, "E"), false, "5 has no E")
eq(Grid.hasSide(5, "S"), true, "5 has S")

--================================================================ lanes stay bounded
do
	local o1 = Grid.laneOrigin(1, cfg)
	local o12 = Grid.laneOrigin(12, cfg)
	eq(o1.x, 0, "lane 1 at x = 0"); eq(o1.z, 1000, "every lane at z = +1000")
	eq(o12.x, 11 * 256, "lane 12 at x = 2816")
	truthy(o12.x < 4000, "lane coordinates stay bounded: indices are recycled, never marched outward")
end

print(string.format("Grid: %d passed, %d failed", passed, failed))
if failed > 0 then error("Grid spec failed", 0) end
