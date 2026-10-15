--!strict
-- Pick.luau: which prop a tap lands on (DESIGN.md §3.4, §17). Pure: vectors are {x, y, z} arrays, the camera is
-- { pos, look, right, up } (unit vectors), field of view in degrees (vertical, Roblox's Camera.FieldOfView).
-- In Roblox the client asks the engine for the ray (Camera:ViewportPointToRay) when it has one and falls back to
-- `Pick.ray`; the box test below is the same either way, so the headless checks pick exactly what a player would.

local Pick = {}

local function dot(a: { number }, b: { number }): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

-- The ray through screen point (sx, sy) of a vpW x vpH viewport.
function Pick.ray(cam: any, fovDeg: number, vpW: number, vpH: number, sx: number, sy: number): ({ number }, { number })
	local t = math.tan(math.rad(fovDeg) / 2)
	local nx = (2 * sx / vpW - 1) * t * (vpW / vpH)
	local ny = (1 - 2 * sy / vpH) * t
	local d = {
		cam.look[1] + cam.right[1] * nx + cam.up[1] * ny,
		cam.look[2] + cam.right[2] * nx + cam.up[2] * ny,
		cam.look[3] + cam.right[3] * nx + cam.up[3] * ny,
	}
	local len = math.sqrt(dot(d, d))
	return { cam.pos[1], cam.pos[2], cam.pos[3] }, { d[1] / len, d[2] / len, d[3] / len }
end

-- The screen point of a world point (the inverse of `ray`), or nil behind the camera.
function Pick.project(cam: any, fovDeg: number, vpW: number, vpH: number, p: { number }): (number?, number?)
	local rel = { p[1] - cam.pos[1], p[2] - cam.pos[2], p[3] - cam.pos[3] }
	local z = dot(rel, cam.look)
	if z <= 1e-6 then return nil, nil end
	local t = math.tan(math.rad(fovDeg) / 2)
	local nx = dot(rel, cam.right) / z / (t * vpW / vpH)
	local ny = dot(rel, cam.up) / z / t
	return (nx + 1) * vpW / 2, (1 - ny) * vpH / 2
end

-- Slab test: distance along the ray to an axis-aligned box (centre c, half sizes h), or nil.
function Pick.hitBox(o: { number }, d: { number }, c: { number }, h: { number }): number?
	local tmin, tmax = -math.huge, math.huge
	for i = 1, 3 do
		local lo, hi = c[i] - h[i], c[i] + h[i]
		if math.abs(d[i]) < 1e-12 then
			if o[i] < lo or o[i] > hi then return nil end
		else
			local t1, t2 = (lo - o[i]) / d[i], (hi - o[i]) / d[i]
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return nil end
		end
	end
	if tmax < 0 then return nil end
	return math.max(tmin, 0)
end

-- props: { id, kind, x, y, z } in the SAME frame as the ray; boxFn(kind) -> half sizes; occluders:
-- { cx, cy, cz, hx, hy, hz }. Returns the nearest prop hit before any occluder, or nil.
function Pick.pick(o: { number }, d: { number }, props: { any }, occluders: { any }, boxFn: (string) -> (number, number, number)): any
	local best, bestT = nil, math.huge
	for _, p in props do
		local hx, hy, hz = boxFn(p.kind)
		local t = Pick.hitBox(o, d, { p.x, p.y + hy, p.z }, { hx, hy, hz })
		if t and t < bestT then best, bestT = p, t end
	end
	if best == nil then return nil end
	for _, oc in occluders do
		local t = Pick.hitBox(o, d, { oc.cx, oc.cy, oc.cz }, { oc.hx, oc.hy, oc.hz })
		if t and t < bestT - 0.05 then return nil end
	end
	return best
end

-- Horizontal reach from a root position {x, y, z} to a prop.
function Pick.inReach(root: { number }, p: any, reach: number): boolean
	local dx, dz = p.x - root[1], p.z - root[3]
	return dx * dx + dz * dz <= reach * reach + 1e-9
end

-- A press that moved less than 12 px and lasted under 0.5 s is a tap; anything else is a camera drag.
function Pick.isTap(downAt: any, upAt: any, seconds: number): boolean
	local dx, dy = upAt.x - downAt.x, upAt.y - downAt.y
	return dx * dx + dy * dy <= 144 and seconds <= 0.5
end

return Pick
