-- Spec for Pick: a tap on the screen -> which prop (DESIGN.md §3.4, §17). Run: luau tests/Pick.spec.luau 2>&1
--
-- The ray through a screen point (the camera's look at the centre, the field of view at the edges), a box test
-- per prop, the nearest hit wins, a table in front blocks what is behind it, and a tap that drags is not a tap.
local Pick = require("../src/shared/Pick")
local RoomArt = require("../src/shared/RoomArt")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- a camera at (0, 5, -10) looking along +z
local cam = { pos = { 0, 5, -10 }, look = { 0, 0, 1 }, right = { 1, 0, 0 }, up = { 0, 1, 0 } }

do
	local o, d = Pick.ray(cam, 70, 1280, 720, 640, 360)
	near(d[1], 0, 1e-9, "the screen centre looks straight ahead (x)")
	near(d[2], 0, 1e-9, "(y)")
	near(d[3], 1, 1e-9, "(z)")
	eq(o[3], -10, "the ray starts at the camera")
	local _, top = Pick.ray(cam, 70, 1280, 720, 640, 0)
	near(math.deg(math.atan2(top[2], top[3])), 35, 1e-6, "the top edge is half the 70-degree vertical field of view up")
	local _, left = Pick.ray(cam, 70, 1280, 720, 0, 360)
	truthy(left[1] < 0, "the left edge looks left")
	local half = math.deg(math.atan2(-left[1], left[3]))
	near(half, math.deg(math.atan(math.tan(math.rad(35)) * 1280 / 720)), 1e-6, "the horizontal half-angle follows the aspect ratio")
end

-- props: a box straight ahead at z = 10, another behind it at z = 20, a vase off to the side
local props = {
	{ id = 1, kind = "box", x = 0, y = 4, z = 10 },
	{ id = 2, kind = "box", x = 0, y = 4, z = 20 },
	{ id = 3, kind = "vase", x = 8, y = 0, z = 10 },
}
do
	local o, d = Pick.ray(cam, 70, 1280, 720, 640, 360)
	local hit = Pick.pick(o, d, props, {}, RoomArt.pickBox)
	eq(hit and hit.id, 1, "the nearest prop on the ray wins (1, not the one behind it)")
	local lessProps = { props[2], props[3] }
	local hit2 = Pick.pick(o, d, lessProps, {}, RoomArt.pickBox)
	eq(hit2 and hit2.id, 2, "with the front one gone, the one behind is hit")
	-- a table (an occluder box) in front of prop 2 blocks it
	local occ = { { cx = 0, cy = 5, cz = 15, hx = 3, hy = 1.5, hz = 1.5 } }
	local hit3 = Pick.pick(o, d, lessProps, occ, RoomArt.pickBox)
	eq(hit3, nil, "a table in front blocks the prop behind it")
	-- aim at the vase: project its centre
	local sx, sy = Pick.project(cam, 70, 1280, 720, { 8, 1, 10 })
	local o4, d4 = Pick.ray(cam, 70, 1280, 720, sx, sy)
	local hit4 = Pick.pick(o4, d4, props, {}, RoomArt.pickBox)
	eq(hit4 and hit4.id, 3, "a tap on the vase's projected centre picks the vase (project and ray agree)")
	local o5, d5 = Pick.ray(cam, 70, 1280, 720, 1270, 10)
	eq(Pick.pick(o5, d5, props, {}, RoomArt.pickBox), nil, "a tap on empty space picks nothing")
end

--============================================================ reach and taps
eq(Pick.inReach({ 0, 3, 0 }, { x = 9.9, y = 8, z = 0 }, 10), true, "9.9 studs away horizontally, any height: in reach")
eq(Pick.inReach({ 0, 3, 0 }, { x = 7.2, y = 8, z = 7.2 }, 10), false, "10.18 studs: out of reach")
eq(Pick.isTap({ x = 100, y = 100 }, { x = 104, y = 103 }, 0.2), true, "a short press that barely moves is a tap")
eq(Pick.isTap({ x = 100, y = 100 }, { x = 140, y = 100 }, 0.2), false, "a drag (turning the camera) is never a tap")
eq(Pick.isTap({ x = 100, y = 100 }, { x = 100, y = 100 }, 0.9), false, "a long press is not a tap")

--============================================================ every kind's pick box is at least a tap target wide
for kind in RoomArt.Kinds do
	local hx, hy, hz = RoomArt.pickBox(kind)
	truthy(hx >= 0.8 and hy >= 0.5 and hz >= 0.8, kind .. "'s pick box is generous (" .. hx .. ", " .. hy .. ", " .. hz .. ")")
end

print(string.format("Pick: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pick spec failed", 0) end
