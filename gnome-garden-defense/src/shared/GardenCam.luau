--!strict
-- GardenCam.luau: the garden view's camera math and the tap that picks a pad. Pure, no Roblox (REVIEW-1).
--
-- A pose is { pos = V, look = V, fov = degrees } (V = { x, y, z }, bed coordinates: x east, z south, y up): a
-- camera at `pos` looking at `look` with world up +Y and a VERTICAL field of view, as Roblox's
-- CFrame.lookAt(pos, look) + Camera.FieldOfView draw it. A view is { w, h }: the viewport in px (Camera.
-- ViewportSize, the whole screen; screen input positions are below the GUI inset, the caller adds it).
--
--   project(pose, view, p) -> x, y, depth          viewport px (y down) and the distance along the view
--   ray(pose, view, x, y) -> origin, dir           the inverse: the ray through a viewport pixel
--   orbit(focus, pitch, yaw, dist, fov) -> pose    looking at `focus` from `dist` away, pitched down `pitch`
--                                                  degrees, heading `yaw` degrees (0 = north, -Z)
--   fit(points, region, view, pitch, yaw, fov)     the pose that shows every point inside the screen region
--                                                  { x0, y0, x1, y1 }, centred and as big as it goes
--   zoomOn(point, cell, minPx, region, ...)        the farthest pose at which a `cell`-stud square around the
--                                                  point is at least minPx on screen, the point at the region's
--                                                  centre
--   fitClear(points, region, view, pitch, yaw, fov, cells, zones) -> pose, ok
--                                                  fit's framing, moved sideways (and only when that is not
--                                                  enough, made smaller) until no cell (a quad of 4 points) overlaps
--                                                  a zone { x0, y0, x1, y1 } on screen: no pad under Roblox's touch
--                                                  controls (REVIEW-2). ok = false: no such framing, fit's is returned
--   cellPx(pose, view, cx, cz, cell, y) -> w, h    a square cell's size on screen
--   pickRay(origin, dir, pads, tile, padTop, columns, colHalf) -> padIndex?
--                                                  a gnome's column first (a tap on its body: colHalf studs
--                                                  either side of the pad's centre, as tall as columns[pad]),
--                                                  else the pad whose cell the ray meets at the pads' top, else
--                                                  the nearest pad within one cell (a tap on the path beside it)

local GardenCam = {}

type V = { x: number, y: number, z: number }

local function v(x: number, y: number, z: number): V
	return { x = x, y = y, z = z }
end
local function sub(a: V, b: V): V return v(a.x - b.x, a.y - b.y, a.z - b.z) end
local function add(a: V, b: V): V return v(a.x + b.x, a.y + b.y, a.z + b.z) end
local function mul(a: V, s: number): V return v(a.x * s, a.y * s, a.z * s) end
local function dot(a: V, b: V): number return a.x * b.x + a.y * b.y + a.z * b.z end
local function unit(a: V): V
	local l = math.sqrt(dot(a, a))
	if l < 1e-12 then return v(0, 0, -1) end
	return mul(a, 1 / l)
end

-- forward, right, up of a pose (CFrame.lookAt with world up +Y: right = forward x up, up = right x forward)
function GardenCam.basis(pose: any): (V, V, V)
	local f = unit(sub(pose.look, pose.pos))
	local r = unit(v(-f.z, 0, f.x))
	local u = v(r.y * f.z - r.z * f.y, r.z * f.x - r.x * f.z, r.x * f.y - r.y * f.x)
	return f, r, u
end

local function focal(pose: any, view: any): number
	return (view.h / 2) / math.tan(math.rad(pose.fov) / 2)
end

function GardenCam.project(pose: any, view: any, p: V): (number, number, number)
	local f, r, u = GardenCam.basis(pose)
	local d = sub(p, pose.pos)
	local zc = dot(d, f)
	local k = focal(pose, view)
	if zc <= 1e-9 then return math.huge, math.huge, zc end
	return view.w / 2 + dot(d, r) / zc * k, view.h / 2 - dot(d, u) / zc * k, zc
end

function GardenCam.ray(pose: any, view: any, x: number, y: number): (V, V)
	local f, r, u = GardenCam.basis(pose)
	local k = focal(pose, view)
	local dir = add(add(f, mul(r, (x - view.w / 2) / k)), mul(u, -(y - view.h / 2) / k))
	return v(pose.pos.x, pose.pos.y, pose.pos.z), unit(dir)
end

function GardenCam.orbit(focus: V, pitch: number, yaw: number, dist: number, fov: number): any
	local p, y = math.rad(pitch), math.rad(yaw)
	local dir = v(-math.sin(y) * math.cos(p), -math.sin(p), -math.cos(y) * math.cos(p))
	return { pos = sub(focus, mul(dir, dist)), look = v(focus.x, focus.y, focus.z), fov = fov }
end

local function bbox(pose: any, view: any, points: { V }): (number, number, number, number, boolean)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in points do
		local x, y, z = GardenCam.project(pose, view, p)
		if z <= 1e-6 then return 0, 0, 0, 0, false end
		x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
	end
	return x0, y0, x1, y1, true
end

-- Move the orbit's focus until the points' screen box is centred on (cx, cy). A few passes: moving the focus
-- across the view shifts the picture by about (move / dist) * focal px.
local function centred(points: { V }, focus: V, cx: number, cy: number, view: any, pitch: number, yaw: number, dist: number, fov: number): any
	local pose = GardenCam.orbit(focus, pitch, yaw, dist, fov)
	for _ = 1, 8 do
		local x0, y0, x1, y1, ok = bbox(pose, view, points)
		if not ok then return pose end
		local ex, ey = (x0 + x1) / 2 - cx, (y0 + y1) / 2 - cy
		if math.abs(ex) < 0.05 and math.abs(ey) < 0.05 then break end
		local _, r, u = GardenCam.basis(pose)
		local _, _, depth = GardenCam.project(pose, view, focus)
		local s = depth / focal(pose, view)
		focus = add(focus, add(mul(r, ex * s), mul(u, -ey * s)))
		pose = GardenCam.orbit(focus, pitch, yaw, dist, fov)
	end
	return pose
end

local function centroid(points: { V }): V
	local s = v(0, 0, 0)
	for _, p in points do s = add(s, p) end
	return mul(s, 1 / math.max(1, #points))
end

function GardenCam.fit(points: { V }, region: any, view: any, pitch: number, yaw: number, fov: number): any
	local cx, cy = (region.x0 + region.x1) / 2, (region.y0 + region.y1) / 2
	local focus = centroid(points)
	local function inside(dist: number): (boolean, any)
		local pose = centred(points, focus, cx, cy, view, pitch, yaw, dist, fov)
		local x0, y0, x1, y1, ok = bbox(pose, view, points)
		return ok and x0 >= region.x0 and x1 <= region.x1 and y0 >= region.y0 and y1 <= region.y1, pose
	end
	local lo, hi = 1, 8000
	local _, best = inside(hi)
	for _ = 1, 48 do
		local mid = (lo + hi) / 2
		local ok, pose = inside(mid)
		if ok then
			hi, best = mid, pose
		else
			lo = mid
		end
	end
	return best
end

-- A pose's projector: the basis and focal length worked out once, for many points.
local function projector(pose: any, view: any): (p: V) -> (number, number, number)
	local f, r, u = GardenCam.basis(pose)
	local k = focal(pose, view)
	local px, py, pz = pose.pos.x, pose.pos.y, pose.pos.z
	local hw, hh = view.w / 2, view.h / 2
	return function(p: V): (number, number, number)
		local dx, dy, dz = p.x - px, p.y - py, p.z - pz
		local zc = dx * f.x + dy * f.y + dz * f.z
		if zc <= 1e-9 then return math.huge, math.huge, zc end
		return hw + (dx * r.x + dy * r.y + dz * r.z) / zc * k, hh - (dx * u.x + dy * u.y + dz * u.z) / zc * k, zc
	end
end

-- Do any of the cells' screen boxes overlap any zone? (A box, not the exact quad: a little conservative.)
local function overlapsZone(pose: any, view: any, cells: { { V } }, zones: { any }): boolean
	local proj = projector(pose, view)
	for _, quad in cells do
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, p in quad do
			local x, y, z = proj(p)
			if z <= 1e-6 then return true end
			x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
		end
		for _, zn in zones do
			if x1 > zn.x0 and x0 < zn.x1 and y1 > zn.y0 and y0 < zn.y1 then return true end
		end
	end
	return false
end

-- REVIEW-2: on a phone the whole-garden view put pads in the bottom band's corners, under Roblox's thumbstick and
-- jump button, where a tap moves or jumps the gardener instead. The framing that fixes it, as big as possible:
-- at fit's distance, the horizontal centre nearest the region's middle that keeps every point in the region and
-- every cell out of every zone; when none does, the nearest distance at which one does (binary search).
local CLEAR_STEPS = 24 -- horizontal centres tried either side of the middle, across half the region's width
function GardenCam.fitClear(points: { V }, region: any, view: any, pitch: number, yaw: number, fov: number, cells: { { V } }?, zones: { any }?): (any, boolean)
	local base = GardenCam.fit(points, region, view, pitch, yaw, fov)
	if cells == nil or zones == nil or #cells == 0 or #zones == 0 then return base, true end
	local cs, zs = cells :: { { V } }, zones :: { any }
	if not overlapsZone(base, view, cs, zs) then return base, true end
	local cy = (region.y0 + region.y1) / 2
	local cx0 = (region.x0 + region.x1) / 2
	local half = (region.x1 - region.x0) / 2
	local focus = centroid(points)
	local function clearAt(dist: number): any?
		for k = 0, CLEAR_STEPS do
			for _, sgn in { 1, -1 } do
				if k > 0 or sgn == 1 then
					local pose = centred(points, focus, cx0 + sgn * k * half / CLEAR_STEPS, cy, view, pitch, yaw, dist, fov)
					local x0, y0, x1, y1, ok = bbox(pose, view, points)
					if ok and x0 >= region.x0 and x1 <= region.x1 and y0 >= region.y0 and y1 <= region.y1
						and not overlapsZone(pose, view, cs, zs) then
						return pose
					end
				end
			end
		end
		return nil
	end
	local d0 = math.sqrt((base.pos.x - base.look.x) ^ 2 + (base.pos.y - base.look.y) ^ 2 + (base.pos.z - base.look.z) ^ 2)
	local now = clearAt(d0)
	if now then return now, true end
	local lo, hi = d0, d0 * 4
	local best = clearAt(hi)
	if best == nil then return base, false end
	for _ = 1, 20 do
		local mid = (lo + hi) / 2
		local pose = clearAt(mid)
		if pose then
			hi, best = mid, pose
		else
			lo = mid
		end
	end
	return best, true
end

function GardenCam.cellPx(pose: any, view: any, cx: number, cz: number, cell: number, y: number): (number, number)
	local h = cell / 2
	local x0, y0, x1, y1, ok = bbox(pose, view, {
		v(cx - h, y, cz - h), v(cx + h, y, cz - h), v(cx - h, y, cz + h), v(cx + h, y, cz + h),
	})
	if not ok then return 0, 0 end
	return x1 - x0, y1 - y0
end

function GardenCam.zoomOn(point: V, cell: number, minPx: number, region: any, view: any, pitch: number, yaw: number, fov: number): any
	local cx, cy = (region.x0 + region.x1) / 2, (region.y0 + region.y1) / 2
	local function at(dist: number): (boolean, any)
		local pose = centred({ point }, point, cx, cy, view, pitch, yaw, dist, fov)
		local w, h = GardenCam.cellPx(pose, view, point.x, point.z, cell, point.y)
		return math.min(w, h) >= minPx, pose
	end
	local lo, hi = 1, 4000
	local _, best = at(lo)
	for _ = 1, 48 do
		local mid = (lo + hi) / 2
		local ok, pose = at(mid)
		if ok then
			lo, best = mid, pose
		else
			hi = mid
		end
	end
	return best
end

-- the slab test: where a ray enters an axis-aligned box, or nil
local function rayBox(o: V, d: V, lo: V, hi: V): number?
	local t0, t1 = -math.huge, math.huge
	for _, k in { "x", "y", "z" } do
		local ok, dk = (o :: any)[k], (d :: any)[k]
		local a, b = (lo :: any)[k], (hi :: any)[k]
		if math.abs(dk) < 1e-12 then
			if ok < a or ok > b then return nil end
		else
			local ta, tb = (a - ok) / dk, (b - ok) / dk
			if ta > tb then ta, tb = tb, ta end
			t0, t1 = math.max(t0, ta), math.min(t1, tb)
			if t0 > t1 then return nil end
		end
	end
	if t1 < 0 then return nil end
	return math.max(t0, 0)
end

-- pads: { { cx, cz } } (PathGen.pads); columns: { [padIndex] = height } for the pads a gnome stands on. A column
-- is as wide as the gnome (colHalf), not its whole cell: a full-cell column hid the front of the pad behind it,
-- and a tap aimed at that pad picked the gnome in front.
function GardenCam.pickRay(o: V, d: V, pads: { any }, tile: number, padTop: number, columns: { [number]: number }, colHalf: number?): number?
	local h = tile / 2
	local c = colHalf or h
	local best, bestT = nil, math.huge
	for idx, height in columns do
		local pd = pads[idx]
		if pd then
			local t = rayBox(o, d, v(pd.cx - c, 0, pd.cz - c), v(pd.cx + c, height, pd.cz + c))
			if t and t < bestT then best, bestT = idx, t end
		end
	end
	if best then return best end
	if d.y >= -1e-9 then return nil end
	local t = (padTop - o.y) / d.y
	if t < 0 then return nil end
	local x, z = o.x + d.x * t, o.z + d.z * t
	local near, nearD = nil, math.huge
	for idx, pd in pads do
		local cheb = math.max(math.abs(x - pd.cx), math.abs(z - pd.cz))
		if cheb < nearD - 1e-9 then near, nearD = idx, cheb end
	end
	if near and nearD <= tile then return near end
	return nil
end

return GardenCam
