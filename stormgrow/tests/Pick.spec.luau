-- Spec for Pick: which tile a tap lands on (REVIEW-1 B1). Run: luau tests/Pick.spec.luau
--
-- A tap is a ray from the camera through the tapped screen point. It lands on the FIRST drawn thing it meets:
-- a crop part or a soil plate, each a box (a ball or a cylinder counts as its bounding box). Nothing invisible
-- takes part, so a tile is never hidden behind a box the player cannot see (the 6-stud hitboxes did that).
-- Pure math on plain numbers: a box is { x, y, z, r = 9 rotation numbers (CFrame:GetComponents order), hx, hy, hz }.
local Pick = require("../src/shared/Pick")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b), "+-", tol)
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end

local I = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function box(x, y, z, sx, sy, sz, r, id)
	return { x = x, y = y, z = z, r = r or I, hx = sx / 2, hy = sy / 2, hz = sz / 2, id = id }
end

-- 1. the slab test: straight down onto a 2 x 2 x 2 box at the origin
near(Pick.slab(0, 10, 0, 0, -1, 0, box(0, 0, 0, 2, 2, 2)), 9, 1e-9, "a ray from 10 above enters the box's top at t = 9")
eq(Pick.slab(3, 10, 0, 0, -1, 0, box(0, 0, 0, 2, 2, 2)), nil, "a ray 3 studs to the side misses it")
eq(Pick.slab(0, 10, 0, 0, 1, 0, box(0, 0, 0, 2, 2, 2)), nil, "a ray pointing away misses it")
near(Pick.slab(0, 0, 0, 0, -1, 0, box(0, 0, 0, 2, 2, 2)), 0, 1e-9, "a ray starting inside enters at t = 0")
near(Pick.slab(0, 10, 0, 0, -2, 0, box(0, 0, 0, 2, 2, 2)), 4.5, 1e-9, "t is in units of the direction (not normalised)")
-- a box turned 45 degrees about Y: its corner reaches x = sqrt(2)
local c, s = math.cos(math.rad(45)), math.sin(math.rad(45))
local R45 = { c, 0, s, 0, 1, 0, -s, 0, c }
near(Pick.slab(10, 0, 0, -1, 0, 0, box(0, 0, 0, 2, 2, 2, R45)), 10 - math.sqrt(2), 1e-9, "a turned box is entered at its corner")
eq(Pick.slab(10, 1.2, 0, -1, 0, 0, box(0, 0, 0, 2, 2, 2, R45)), nil, "and missed just above it")

-- 2. the first box along the ray wins; a box behind the start never does
do
	local near1 = box(0, 0, 5, 2, 2, 2, nil, "near")
	local far1 = box(0, 0, 20, 2, 2, 2, nil, "far")
	local behind = box(0, 0, -5, 2, 2, 2, nil, "behind")
	local b, t = Pick.first(0, 0, 0, 0, 0, 1, { far1, behind, near1 }, 100)
	eq(b and b.id, "near", "the nearest box along the ray is picked, whatever the list order")
	near(t, 4, 1e-9, "at the distance it is entered")
	eq((Pick.first(0, 0, 0, 0, 0, 1, { far1 }, 15)), nil, "nothing beyond maxT")
	eq((Pick.first(0, 0, 0, 0, 0, -1, { near1, far1 }, 100)), nil, "nothing behind the camera")
end

-- 3. the case REVIEW-1 found: two tiles in a row seen from a shallow camera. With only what is drawn taking part
--    (a short soil plate each), the ray aimed at the far tile reaches it.
do
	local camY, camZ = 8, -10 -- a camera 8 up, 10 back
	local nearSoil = box(0, 0.3, 4, 7.6, 0.6, 7.6, nil, "near")
	local farSoil = box(0, 0.3, 12, 7.6, 0.6, 7.6, nil, "far")
	local dx, dy, dz = 0, 0.6 - camY, 12 - camZ -- aim at the far tile's soil top
	local b = Pick.first(0, camY, camZ, dx, dy, dz, { nearSoil, farSoil }, math.huge)
	eq(b and b.id, "far", "a ray aimed at the far tile's soil lands on the far tile")
	-- and an invisible 6-stud column over the near tile (the old hitbox) would have taken it
	local column = box(0, 3, 4, 7.6, 6, 7.6, nil, "column")
	local b2 = Pick.first(0, camY, camZ, dx, dy, dz, { column, farSoil }, math.huge)
	eq(b2 and b2.id, "column", "control: a tall invisible column in front takes the same ray (the defect)")
end

-- 4. the camera ray: a pinhole camera with a VERTICAL field of view (Roblox's Camera.FieldOfView)
do
	-- camera at (0, 5, 0) looking down -z (identity rotation: right +x, up +y, back +z)
	local cam = { x = 0, y = 5, z = 0, r = I }
	local ox, oy, oz, dx, dy, dz = Pick.viewportRay(cam, 70, 800, 400, 400, 200)
	near(ox, 0, 1e-9, "the ray starts at the camera (x)")
	near(oy, 5, 1e-9, "the ray starts at the camera (y)")
	near(dx, 0, 1e-9, "the screen centre looks straight ahead (x)")
	near(dy, 0, 1e-9, "the screen centre looks straight ahead (y)")
	truthy(dz < 0, "the screen centre looks along the camera's look vector (-z)")
	local _, _, _, tx, ty, tz = Pick.viewportRay(cam, 70, 800, 400, 400, 0)
	near(math.deg(math.atan2(ty, -tz)), 35, 1e-6, "the top edge is half the vertical field of view up")
	local _, _, _, rx, ry, rz = Pick.viewportRay(cam, 70, 800, 400, 800, 200)
	near(rx / -rz, math.tan(math.rad(35)) * 2, 1e-9, "the right edge is the vertical half-angle times the aspect (800/400)")
	near(ry, 0, 1e-9, "and level")
	-- project and ray are inverses
	local px, py, depth = Pick.project(cam, 70, 800, 400, 3, 1, -10)
	truthy(depth > 0, "a point in front projects with a positive depth")
	local _, _, _, qx, qy, qz = Pick.viewportRay(cam, 70, 800, 400, px, py)
	local k = -10 / qz
	near(qx * k, 3, 1e-9, "the ray through a projected point passes through the point (x)")
	near(5 + qy * k, 1, 1e-9, "the ray through a projected point passes through the point (y)")
	local _, _, behindDepth = Pick.project(cam, 70, 800, 400, 0, 5, 10)
	truthy(behindDepth <= 0, "a point behind the camera says so")
end

-- 5. a turned camera: looking down at 45 degrees, the screen centre ray goes down at 45 degrees
do
	local a = math.rad(-45) -- pitch down: rotate about x
	local ca, sa = math.cos(a), math.sin(a)
	-- CFrame.Angles(a, 0, 0) rotation matrix rows: { 1, 0, 0 }, { 0, ca, -sa }, { 0, sa, ca }
	local cam = { x = 0, y = 10, z = 0, r = { 1, 0, 0, 0, ca, -sa, 0, sa, ca } }
	local _, _, _, dx, dy, dz = Pick.viewportRay(cam, 70, 800, 400, 400, 200)
	near(dx, 0, 1e-9, "turned camera: centre ray has no sideways part")
	near(math.deg(math.atan2(-dy, -dz)), 45, 1e-6, "turned camera: the centre ray dips 45 degrees")
end

-- 6. the ground stops a ray: maxT to the ground plane
near(Pick.toGround(0, 10, 0, 0, -2, 0, 0), 5, 1e-9, "a ray falling 2 per t from 10 meets y = 0 at t = 5")
eq(Pick.toGround(0, 10, 0, 0, 1, 0, 0), math.huge, "a ray going up never meets the ground")

print(string.format("Pick: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pick spec failed", 0) end
