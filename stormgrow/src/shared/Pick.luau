--!strict
-- Pick.luau — which tile a tap lands on (REVIEW-1 B1). Pure math on plain numbers; Farm.client feeds it.
--
-- A tap is a ray from the camera through the tapped screen point, and it lands on the FIRST drawn thing it
-- meets: a crop part or a soil plate. Only what the player can see takes part, so no tile is ever hidden behind
-- something invisible. (Until REVIEW-1 the tiles were 6-stud invisible ClickDetector columns: Roblox delivers a
-- click to the first queryable part on the ray, so from in front of a field two taps in three reached the tile
-- in FRONT of the one the player tapped.) A ball or a cylinder counts as its bounding box: a little generous,
-- never smaller than what is drawn.
--
-- A box is { x, y, z (centre), r = { R00, R01, R02, R10, R11, R12, R20, R21, R22 } (CFrame:GetComponents()
-- order; the columns are the part's right, up and back axes), hx, hy, hz (half sizes), ... any payload }.
-- A camera is { x, y, z, r } the same way. Rays are (ox, oy, oz, dx, dy, dz); t is in units of d.

local Pick = {}

-- where the ray enters box b (t >= 0), or nil; 0 if it starts inside
function Pick.slab(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, b: any): number?
	local r = b.r
	local px, py, pz = ox - b.x, oy - b.y, oz - b.z
	-- into the box's own frame: local = R^T (p - centre)
	local lo = { px * r[1] + py * r[4] + pz * r[7], px * r[2] + py * r[5] + pz * r[8], px * r[3] + py * r[6] + pz * r[9] }
	local ld = { dx * r[1] + dy * r[4] + dz * r[7], dx * r[2] + dy * r[5] + dz * r[8], dx * r[3] + dy * r[6] + dz * r[9] }
	local hs = { b.hx, b.hy, b.hz }
	local tmin, tmax = 0, math.huge
	for i = 1, 3 do
		local o, d, s = lo[i], ld[i], hs[i]
		if math.abs(d) < 1e-12 then
			if o < -s or o > s then return nil end
		else
			local t1, t2 = (-s - o) / d, (s - o) / d
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return nil end
		end
	end
	return tmin
end

-- the first box the ray enters before maxT -> (box, t), or nil
function Pick.first(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, boxes: { any }, maxT: number): (any?, number)
	local best, bt = nil, maxT
	for _, b in boxes do
		local t = Pick.slab(ox, oy, oz, dx, dy, dz, b)
		if t ~= nil and t < bt then best, bt = b, t end
	end
	return best, bt
end

-- t where the ray meets the ground plane y = groundY (math.huge if it never does): nothing below the valley
-- floor is ever tapped
function Pick.toGround(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number, groundY: number): number
	if dy >= 0 then return math.huge end
	return (groundY - oy) / dy
end

-- The ray through viewport pixel (px, py) (top-left origin, the topbar included) of a pinhole camera whose
-- field of view is VERTICAL, as Roblox's Camera.FieldOfView is. Camera space looks down -z.
-- robloxemu has no Camera:ViewportPointToRay; in Roblox Farm.client uses the engine's own.
function Pick.viewportRay(cam: any, fovDeg: number, w: number, h: number, px: number, py: number): (number, number, number, number, number, number)
	local th = math.tan(math.rad(fovDeg) / 2)
	local cx = (2 * px / w - 1) * th * (w / h)
	local cy = (1 - 2 * py / h) * th
	local r = cam.r
	-- world = R * (cx, cy, -1)
	local dx = r[1] * cx + r[2] * cy - r[3]
	local dy = r[4] * cx + r[5] * cy - r[6]
	local dz = r[7] * cx + r[8] * cy - r[9]
	return cam.x, cam.y, cam.z, dx, dy, dz
end

-- world point -> (viewport px, py, depth); depth <= 0 means behind the camera
function Pick.project(cam: any, fovDeg: number, w: number, h: number, x: number, y: number, z: number): (number, number, number)
	local r = cam.r
	local px, py, pz = x - cam.x, y - cam.y, z - cam.z
	local lx = px * r[1] + py * r[4] + pz * r[7]
	local ly = px * r[2] + py * r[5] + pz * r[8]
	local lz = px * r[3] + py * r[6] + pz * r[9]
	local depth = -lz
	if depth <= 0 then return 0, 0, depth end
	local th = math.tan(math.rad(fovDeg) / 2)
	local nx = lx / (depth * th * (w / h))
	local ny = ly / (depth * th)
	return (nx + 1) / 2 * w, (1 - ny) / 2 * h, depth
end

return Pick
