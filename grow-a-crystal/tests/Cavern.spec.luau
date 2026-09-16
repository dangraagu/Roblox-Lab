-- Rene tester for Cavern (The Sunken Grotto geometry generator).
-- Kjør: luau tests/Cavern.spec.luau
--
-- Cavern.build is a PURE function: it takes cfg + plotIndex + the Rng module and returns plain
-- tables. No Roblox datatype is touched, so every invariant below is exact arithmetic in the
-- luau CLI with no engine present.
--
-- The two defects this suite exists to pin:
--   1. the shipped layout ran 48 sockets out to z = 72.9 against a 48x1x60 pad ending at z = 50,
--      so chamber 5 overhung by 3 studs and chambers 6-7 floated free;
--   2. the shipped jitter drew the SAME value for all six sockets in a row, because Rng.int is
--      `min + state % span` — the LOW bits of an LCG. The witness at the bottom reproduces that
--      formula exactly and proves the check kills it.

local Cavern = require("../src/shared/Cavern")
local Config = require("../src/shared/Config")
local Rng = require("../src/shared/Rng")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want ~", tostring(b))
	end
end

--============================================================================ small vector/AABB kit

local EPS = 1e-6
local RAD = math.pi / 180

-- Roblox CFrame.Angles(rx,ry,rz) = Rx*Ry*Rz. Rows of that product, signed.
local function rows(ori)
	local cx, sx = math.cos(ori.x * RAD), math.sin(ori.x * RAD)
	local cy, sy = math.cos(ori.y * RAD), math.sin(ori.y * RAD)
	local cz, sz = math.cos(ori.z * RAD), math.sin(ori.z * RAD)
	return {
		{ cy * cz, -cy * sz, sy },
		{ cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
		{ sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
	}
end

-- World-axis-aligned bounding box of a (possibly rotated) box part.
local function aabb(p)
	local r = rows(p.orientation)
	local h = { p.size.x / 2, p.size.y / 2, p.size.z / 2 }
	local hx = math.abs(r[1][1]) * h[1] + math.abs(r[1][2]) * h[2] + math.abs(r[1][3]) * h[3]
	local hy = math.abs(r[2][1]) * h[1] + math.abs(r[2][2]) * h[2] + math.abs(r[2][3]) * h[3]
	local hz = math.abs(r[3][1]) * h[1] + math.abs(r[3][2]) * h[2] + math.abs(r[3][3]) * h[3]
	return {
		minX = p.position.x - hx, maxX = p.position.x + hx,
		minY = p.position.y - hy, maxY = p.position.y + hy,
		minZ = p.position.z - hz, maxZ = p.position.z + hz,
		hx = hx, hy = hy, hz = hz,
	}
end

-- STRICT overlap: two boxes that merely touch face-to-face (a crystal standing on its deck, a
-- tread butted against the next deck) are NOT overlapping. Every clearance test below leans on
-- this, so flush construction never reads as a collision.
local function overlaps(a, b)
	return a.minX < b.maxX - EPS and b.minX < a.maxX - EPS
		and a.minY < b.maxY - EPS and b.minY < a.maxY - EPS
		and a.minZ < b.maxZ - EPS and b.minZ < a.maxZ - EPS
end

local function box(x0, x1, y0, y1, z0, z1)
	return { minX = x0, maxX = x1, minY = y0, maxY = y1, minZ = z0, maxZ = z1 }
end

-- Segment vs AABB (slab method). Used only for the 48 click lines.
local function segHitsBox(a, b, bb)
	local t0, t1 = 0, 1
	local o = { a.x, a.y, a.z }
	local d = { b.x - a.x, b.y - a.y, b.z - a.z }
	local lo = { bb.minX, bb.minY, bb.minZ }
	local hi = { bb.maxX, bb.maxY, bb.maxZ }
	for i = 1, 3 do
		if math.abs(d[i]) < 1e-12 then
			if o[i] < lo[i] + EPS or o[i] > hi[i] - EPS then return false end
		else
			local ta = (lo[i] - o[i]) / d[i]
			local tb = (hi[i] - o[i]) / d[i]
			if ta > tb then ta, tb = tb, ta end
			if ta > t0 then t0 = ta end
			if tb < t1 then t1 = tb end
			if t0 > t1 - EPS then return false end
		end
	end
	return true
end

-- Exact XZ shadow of a (possibly rotated) box: the convex hull of its eight projected corners.
local function xzHull(p)
	local r = rows(p.orientation)
	local ax = {
		{ r[1][1], r[3][1] }, { r[1][2], r[3][2] }, { r[1][3], r[3][3] },
	}
	local h = { p.size.x / 2, p.size.y / 2, p.size.z / 2 }
	local pts = {}
	for i = -1, 1, 2 do
		for j = -1, 1, 2 do
			for k = -1, 1, 2 do
				table.insert(pts, {
					p.position.x + i * ax[1][1] * h[1] + j * ax[2][1] * h[2] + k * ax[3][1] * h[3],
					p.position.z + i * ax[1][2] * h[1] + j * ax[2][2] * h[2] + k * ax[3][2] * h[3],
				})
			end
		end
	end
	table.sort(pts, function(a, b)
		if a[1] ~= b[1] then return a[1] < b[1] end
		return a[2] < b[2]
	end)
	local function cross(o, a, b)
		return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
	end
	local function chain(list)
		local out = {}
		for _, pt in ipairs(list) do
			while #out >= 2 and cross(out[#out - 1], out[#out], pt) <= 0 do table.remove(out) end
			table.insert(out, pt)
		end
		table.remove(out)
		return out
	end
	local rev = {}
	for i = #pts, 1, -1 do table.insert(rev, pts[i]) end
	local lower, upper = chain(pts), chain(rev)
	for _, pt in ipairs(upper) do table.insert(lower, pt) end
	return lower
end

-- Distance from a 2D point to a convex polygon (0 when inside).
local function distToHull(px, pz, hull)
	local n = #hull
	if n == 0 then return math.huge end
	if n == 1 then
		local dx, dz = px - hull[1][1], pz - hull[1][2]
		return math.sqrt(dx * dx + dz * dz)
	end
	local inside = true
	local best = math.huge
	for i = 1, n do
		local a, b = hull[i], hull[i % n + 1]
		local ex, ez = b[1] - a[1], b[2] - a[2]
		if ex * (pz - a[2]) - ez * (px - a[1]) < 0 then inside = false end
		local len2 = ex * ex + ez * ez
		local t = 0
		if len2 > 1e-12 then
			t = ((px - a[1]) * ex + (pz - a[2]) * ez) / len2
			t = math.max(0, math.min(1, t))
		end
		local cx, cz = a[1] + t * ex, a[2] + t * ez
		local dx, dz = px - cx, pz - cz
		best = math.min(best, math.sqrt(dx * dx + dz * dz))
	end
	if inside then return 0 end
	return best
end

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, val in pairs(v) do out[k] = deepCopy(val) end
	return out
end

local function byName(cav, name)
	for _, p in ipairs(cav.parts) do if p.name == name then return p end end
	return nil
end

--============================================================================ the checks

-- Every check takes the cavern and returns a list of failure strings. Empty = the invariant
-- holds. Factoring them this way is what makes the mutation sweep at the bottom possible: the
-- same code that guards the shipped build is re-run against deliberately broken copies.

local WALK_GROUPS = {
	deck = true, tread = true, apron = true, shelf = true, basin = true,
	wall = true, ceiling = true,
}

local ec = Config.Economy
local PER = ec.SocketsPerChamber
local TOTAL_SOCKETS = ec.MaxChambers * PER
local K = Cavern.Const

local CHECK = {}

-- 1. Socket containment: every plate a maxed player can own stands on solid floor.
function CHECK.socketContainment(cav)
	local f = {}
	for s = 1, #cav.sockets do
		local c = math.floor((s - 1) / PER)
		local col = (s - 1) % PER
		local sp = cav.sockets[s]
		-- both jitter extremes, plus the actual drawn position
		for _, x in ipairs({ sp.x, col * 8 - 20 - 0.75, col * 8 - 20 + 0.75 }) do
			local plate = box(x - 3, x + 3, sp.y - 0.5, sp.y + 0.5, sp.z - 3, sp.z + 3)
			local hosts = {}
			for _, p in ipairs(cav.parts) do
				if p.walkable then
					local a = aabb(p)
					if a.minX <= plate.minX + EPS and a.maxX >= plate.maxX - EPS
						and a.minZ <= plate.minZ + EPS and a.maxZ >= plate.maxZ - EPS
						and math.abs(a.maxY - sp.y) < 1e-6 then
						table.insert(hosts, p)
					end
				end
			end
			if #hosts ~= 1 then
				table.insert(f, string.format(
					"socket %d at x=%.2f z=%.2f: %d walkable hosts with top y=%.2f, want exactly 1",
					s, x, sp.z, #hosts, sp.y))
			else
				local a = aabb(hosts[1])
				local m = math.min(plate.minX - a.minX, a.maxX - plate.maxX,
					plate.minZ - a.minZ, a.maxZ - plate.maxZ)
				if m < 0.5 - EPS then
					table.insert(f, string.format("socket %d margin %.3f on %s, want >= 0.5", s, m, hosts[1].name))
				end
			end
			local bandZ = K.PITCH * c + 9
			if plate.maxZ > bandZ - 1 + EPS then
				table.insert(f, string.format("socket %d reaches z=%.2f, stair band starts %.2f (want 1 clear)",
					s, plate.maxZ, bandZ))
			end
		end
	end
	return f
end

-- 2. Slice containment: nothing crosses into the neighbouring plot's 80-stud slice.
function CHECK.sliceContainment(cav)
	local f = {}
	local b = { minX = math.huge, maxX = -math.huge, minY = math.huge,
		maxY = -math.huge, minZ = math.huge, maxZ = -math.huge }
	for _, p in ipairs(cav.parts) do
		local a = aabb(p)
		if math.abs(p.position.x) + a.hx > 38 - EPS then
			table.insert(f, string.format("%s reaches |x|=%.3f, the slice half-width is 38",
				p.name, math.abs(p.position.x) + a.hx))
		end
		b.minX = math.min(b.minX, a.minX); b.maxX = math.max(b.maxX, a.maxX)
		b.minY = math.min(b.minY, a.minY); b.maxY = math.max(b.maxY, a.maxY)
		b.minZ = math.min(b.minZ, a.minZ); b.maxZ = math.max(b.maxZ, a.maxZ)
	end
	for _, k in ipairs({ "minX", "maxX", "minY", "maxY", "minZ", "maxZ" }) do
		if math.abs(cav.bounds[k] - b[k]) > 1e-6 then
			table.insert(f, string.format("bounds.%s = %.4f, computed union %.4f", k, cav.bounds[k], b[k]))
		end
	end
	return f
end

-- 3. Axis-aligned collider invariant: this is what makes 4-11 exact arithmetic.
function CHECK.colliderAxisAligned(cav)
	local f, n = {}, 0
	for _, p in ipairs(cav.parts) do
		if p.collide then
			n += 1
			if p.orientation.x ~= 0 or p.orientation.y ~= 0 or p.orientation.z ~= 0 then
				table.insert(f, string.format("collider %s is rotated (%.1f,%.1f,%.1f)",
					p.name, p.orientation.x, p.orientation.y, p.orientation.z))
			end
			if p.shape ~= "Block" then
				table.insert(f, string.format("collider %s is a %s, not a Block", p.name, p.shape))
			end
		end
	end
	if n ~= 36 then table.insert(f, string.format("collider count %d, want 36", n)) end
	return f
end

-- Rasterise the walkable tops onto a 1-stud grid. Cell (ix,iz) is the unit square
-- [ix,ix+1] x [iz,iz+1]; its centre never lands on a part boundary, so membership is exact.
local X0, X1 = -32, 31
local Z0, Z1 = -14, 133
local function walkGrid(cav)
	local top = {}
	for _, p in ipairs(cav.parts) do
		if p.walkable then
			local a = aabb(p)
			local ix0 = math.max(X0, math.floor(a.minX))
			local ix1 = math.min(X1, math.ceil(a.maxX) - 1)
			local iz0 = math.max(Z0, math.floor(a.minZ))
			local iz1 = math.min(Z1, math.ceil(a.maxZ) - 1)
			for ix = ix0, ix1 do
				local cx = ix + 0.5
				if cx > a.minX and cx < a.maxX then
					for iz = iz0, iz1 do
						local cz = iz + 0.5
						if cz > a.minZ and cz < a.maxZ then
							local key = ix * 1000 + iz
							if top[key] == nil or a.maxY > top[key] then top[key] = a.maxY end
						end
					end
				end
			end
		end
	end
	return top
end

-- 4. Walkability: one component, symmetric step rule, so ONE fill proves both
--    "can reach every socket" and "can never be trapped".
function CHECK.walkability(cav)
	local f = {}
	local top = walkGrid(cav)
	for ix = X0, X1 do
		for iz = Z0, Z1 do
			if top[ix * 1000 + iz] == nil then
				table.insert(f, string.format("no walkable floor at cell (%d,%d)", ix, iz))
				if #f > 12 then return f end
			end
		end
	end
	local seen = {}
	local sx, sz = math.floor(cav.spawn.position.x), math.floor(cav.spawn.position.z)
	local startKey = sx * 1000 + sz
	if top[startKey] == nil then
		table.insert(f, "the spawn cell is not walkable")
		return f
	end
	seen[startKey] = true
	local stack = { { sx, sz } }
	while #stack > 0 do
		local cell = table.remove(stack)
		local ix, iz = cell[1], cell[2]
		local h = top[ix * 1000 + iz]
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nx, nz = ix + d[1], iz + d[2]
			if nx >= X0 and nx <= X1 and nz >= Z0 and nz <= Z1 then
				local nk = nx * 1000 + nz
				local nh = top[nk]
				-- symmetric rule: a step you can take up you can take back down
				if nh ~= nil and not seen[nk] and math.abs(nh - h) <= 2.0 + EPS then
					seen[nk] = true
					table.insert(stack, { nx, nz })
				end
			end
		end
	end
	for s = 1, #cav.stands do
		local st = cav.stands[s]
		local k = math.floor(st.x) * 1000 + math.floor(st.z)
		if not seen[k] then
			table.insert(f, string.format("the stand for socket %d is unreachable from the spawn", s))
		elseif math.abs(top[k] - st.y) > 1e-6 then
			table.insert(f, string.format("the stand for socket %d claims y=%.2f, the floor is %.2f",
				s, st.y, top[k]))
		end
	end
	local landmarks = { "Apron", "ShelfFront", "ShelfBack", "ShelfLeft", "ShelfRight", "BasinFloor" }
	for c = 0, K.G - 1 do table.insert(landmarks, "Deck_" .. c) end
	for c = 0, K.G - 2 do table.insert(landmarks, "TreadA_" .. c); table.insert(landmarks, "TreadB_" .. c) end
	for _, name in ipairs(landmarks) do
		local p = byName(cav, name)
		if p == nil then
			table.insert(f, "missing walkable landmark " .. name)
		else
			local a = aabb(p)
			local ix = math.floor((a.minX + a.maxX) / 2)
			local iz = math.floor((a.minZ + a.maxZ) / 2)
			if not seen[ix * 1000 + iz] then
				table.insert(f, name .. " is not in the spawn's walk component")
			end
		end
	end
	local n = 0
	for _ in pairs(seen) do n += 1 end
	local total = (X1 - X0 + 1) * (Z1 - Z0 + 1)
	if n ~= total then
		table.insert(f, string.format("the walk component holds %d of %d cells", n, total))
	end
	return f
end

-- 5. No fall-out: the collider union is a closed shell except the declared shaft hole.
--    Colliders are axis-aligned (check 3), so an axis-aligned ray test is exact and cheap.
function CHECK.noFallOut(cav)
	local f = {}
	local top = walkGrid(cav)
	local cols = {}
	for _, p in ipairs(cav.parts) do if p.collide then table.insert(cols, aabb(p)) end end
	local function blocked(ox, oy, oz, axis, dir)
		for _, b in ipairs(cols) do
			local aligned
			if axis == 1 then
				aligned = oy > b.minY + EPS and oy < b.maxY - EPS and oz > b.minZ + EPS and oz < b.maxZ - EPS
					and ((dir > 0 and b.minX >= ox) or (dir < 0 and b.maxX <= ox))
			elseif axis == 2 then
				aligned = ox > b.minX + EPS and ox < b.maxX - EPS and oz > b.minZ + EPS and oz < b.maxZ - EPS
					and ((dir > 0 and b.minY >= oy) or (dir < 0 and b.maxY <= oy))
			else
				aligned = ox > b.minX + EPS and ox < b.maxX - EPS and oy > b.minY + EPS and oy < b.maxY - EPS
					and ((dir > 0 and b.minZ >= oz) or (dir < 0 and b.maxZ <= oz))
			end
			if aligned then return true end
		end
		return false
	end
	local DIRS = { { 1, 1 }, { 1, -1 }, { 2, 1 }, { 2, -1 }, { 3, 1 }, { 3, -1 } }
	for ix = X0, X1 do
		for iz = Z0, Z1 do
			local h = top[ix * 1000 + iz]
			if h ~= nil then
				local ox, oy, oz = ix + 0.5, h + 1, iz + 0.5
				for _, d in ipairs(DIRS) do
					if not blocked(ox, oy, oz, d[1], d[2]) then
						-- the one declared opening: straight up through the light shaft
						local throughShaft = d[1] == 2 and d[2] == 1
							and ox > -14 and ox < 14 and oz > 112 and oz < 126
						if not throughShaft then
							table.insert(f, string.format("cell (%d,%d) escapes the shell along axis %d dir %d",
								ix, iz, d[1], d[2]))
							if #f > 8 then return f end
						end
					end
				end
			end
		end
	end
	return f
end

-- 6. Water safety: you can always step back out of the basin.
function CHECK.waterSafety(cav)
	local f = {}
	local basin = byName(cav, "BasinFloor")
	if basin == nil then table.insert(f, "BasinFloor missing"); return f end
	local ba = aabb(basin)
	for _, name in ipairs({ "ShelfFront", "ShelfBack", "ShelfLeft", "ShelfRight" }) do
		local p = byName(cav, name)
		if p == nil then
			table.insert(f, "missing " .. name)
		else
			local lip = aabb(p).maxY - ba.maxY
			if lip > 1.9 + EPS then
				table.insert(f, string.format("%s lip is %.2f above the basin floor, want <= 1.9", name, lip))
			end
		end
	end
	local top = walkGrid(cav)
	for ix = math.floor(ba.minX) - 1, math.ceil(ba.maxX) do
		for _, iz in ipairs({ math.floor(ba.minZ) - 1, math.ceil(ba.maxZ) }) do
			if top[ix * 1000 + iz] == nil then
				table.insert(f, string.format("gap in the pool ring at (%d,%d)", ix, iz))
			end
		end
	end
	for iz = math.floor(ba.minZ) - 1, math.ceil(ba.maxZ) do
		for _, ix in ipairs({ math.floor(ba.minX) - 1, math.ceil(ba.maxX) }) do
			if top[ix * 1000 + iz] == nil then
				table.insert(f, string.format("gap in the pool ring at (%d,%d)", ix, iz))
			end
		end
	end
	local water = byName(cav, "Water")
	if water then
		local depth = aabb(water).maxY - ba.maxY
		if depth > 1.9 then
			table.insert(f, string.format("the water is %.2f deep — a Humanoid would start swimming", depth))
		end
	end
	return f
end

-- 7. Stair continuity: two 1.5-stud steps, full width, no edge, no crawlspace.
function CHECK.stairContinuity(cav)
	local f = {}
	for c = 0, K.G - 2 do
		local deck = byName(cav, "Deck_" .. c)
		local nextDeck = byName(cav, "Deck_" .. (c + 1))
		local a = byName(cav, "TreadA_" .. c)
		local b = byName(cav, "TreadB_" .. c)
		if not (deck and nextDeck and a and b) then
			table.insert(f, "riser " .. c .. " is missing a slab")
		else
			local da, aa, bb, na = aabb(deck), aabb(a), aabb(b), aabb(nextDeck)
			for _, pair in ipairs({ { da, aa, "deck->A" }, { aa, bb, "A->B" } }) do
				local rise = pair[2].maxY - pair[1].maxY
				if math.abs(rise - 1.5) > 1e-9 then
					table.insert(f, string.format("riser %d %s is %.3f, want 1.5", c, pair[3], rise))
				end
			end
			if math.abs(bb.maxY - na.maxY) > 1e-9 then
				table.insert(f, string.format("TreadB_%d top %.3f != Deck_%d top %.3f", c, bb.maxY, c + 1, na.maxY))
			end
			for _, t in ipairs({ { aa, "TreadA_" .. c }, { bb, "TreadB_" .. c } }) do
				if math.abs(t[1].minX + K.HALF_W) > 1e-9 or math.abs(t[1].maxX - K.HALF_W) > 1e-9 then
					table.insert(f, t[2] .. " does not span the full interior width")
				end
				if math.abs(t[1].minY - K.DECK_BOTTOM) > 1e-9 then
					table.insert(f, string.format("%s bottom is %.2f, want %.2f (crawlspace)",
						t[2], t[1].minY, K.DECK_BOTTOM))
				end
			end
			if math.abs(aa.maxZ - bb.minZ) > 1e-9 then
				table.insert(f, "the treads of riser " .. c .. " are not flush in z")
			end
		end
	end
	return f
end

-- 8. Query invariant: no decoration can ever silently eat a ClickDetector ray.
function CHECK.queryInvariant(cav)
	local f = {}
	for _, p in ipairs(cav.parts) do
		if not WALK_GROUPS[p.group] and p.query then
			table.insert(f, string.format("%s (group %s) has query = true", p.name, p.group))
		end
	end
	return f
end

-- 9. Line of sight: from its declared stand, every socket is clickable.
function CHECK.lineOfSight(cav)
	local f = {}
	local blockers = {}
	for _, p in ipairs(cav.parts) do if p.query then table.insert(blockers, { p, aabb(p) }) end end
	for s = 1, #cav.sockets do
		local st, sp = cav.stands[s], cav.sockets[s]
		local eye = { x = st.x, y = st.y + 4.5, z = st.z }
		local target = { x = sp.x, y = sp.y + 0.5, z = sp.z }
		for _, entry in ipairs(blockers) do
			if segHitsBox(eye, target, entry[2]) then
				table.insert(f, string.format("socket %d is occluded by %s", s, entry[1].name))
			end
		end
	end
	return f
end

-- 10. Crystal headroom: a mature crystal is 6 studs tall; 7 gives margin.
function CHECK.crystalHeadroom(cav)
	local f = {}
	local cols = {}
	for _, p in ipairs(cav.parts) do if p.collide then table.insert(cols, { p, aabb(p) }) end end
	for s = 1, #cav.sockets do
		local sp = cav.sockets[s]
		local vol = box(sp.x - 1, sp.x + 1, sp.y, sp.y + 7, sp.z - 1, sp.z + 1)
		for _, entry in ipairs(cols) do
			if overlaps(vol, entry[2]) then
				table.insert(f, string.format("a crystal on socket %d would grow into %s", s, entry[1].name))
			end
		end
	end
	return f
end

-- 11. Character headroom: nothing to bump your head on anywhere you can stand.
function CHECK.characterHeadroom(cav)
	local f = {}
	local top = walkGrid(cav)
	local cols = {}
	for _, p in ipairs(cav.parts) do if p.collide then table.insert(cols, { p, aabb(p) }) end end
	for ix = X0, X1 do
		for iz = Z0, Z1 do
			local h = top[ix * 1000 + iz]
			if h ~= nil then
				local vol = box(ix, ix + 1, h + 0.2, h + 6, iz, iz + 1)
				for _, entry in ipairs(cols) do
					if overlaps(vol, entry[2]) then
						table.insert(f, string.format("cell (%d,%d) has %s in its headroom", ix, iz, entry[1].name))
						if #f > 8 then return f end
					end
				end
			end
		end
	end
	return f
end

-- 12. Spawn safety: solid ground under the spawn and a clear column around it.
--     The keep-out uses the EXACT rotated footprint (convex hull of the projected corners), so
--     a tilted lock slab is judged on where it actually is, not on its bounding box.
function CHECK.spawnSafety(cav)
	local f = {}
	local sp = cav.spawn.position
	local under = false
	for _, p in ipairs(cav.parts) do
		if p.walkable then
			local a = aabb(p)
			if sp.x > a.minX and sp.x < a.maxX and sp.z > a.minZ and sp.z < a.maxZ
				and math.abs(a.maxY) < 1e-9 then
				under = true
			end
		end
	end
	if not under then table.insert(f, "no walkable top at y=0 directly under the spawn") end
	if cav.spawn.look.z <= 0 then table.insert(f, "the spawn does not look down +Z into the cavern") end
	for _, p in ipairs(cav.parts) do
		local a = aabb(p)
		if a.minY < 16 - EPS and a.maxY > EPS then
			if distToHull(0, -6, xzHull(p)) < 6 - EPS then
				table.insert(f, string.format("%s intrudes into the spawn keep-out cylinder", p.name))
			end
		end
	end
	return f
end

-- 13. Lock coverage and safety: a locked bed reads as a hole, and can never strand anyone.
function CHECK.lockCoverage(cav)
	local f = {}
	local locks = {}
	for _, p in ipairs(cav.parts) do
		if p.group == "lock" then
			table.insert(locks, p)
			if p.collide or p.query then
				table.insert(f, p.name .. " collides or queries — a failed teardown could strand a player")
			end
			if p.chamber < 0 or p.chamber >= K.G then
				table.insert(f, p.name .. " has no usable chamber tag")
			end
		end
	end
	if #locks ~= 3 * K.G then table.insert(f, string.format("%d lock slabs, want %d", #locks, 3 * K.G)) end
	for c = 0, K.G - 1 do
		local mine = {}
		for _, p in ipairs(locks) do if p.chamber == c then table.insert(mine, p) end end
		local inside, hit = 0, 0
		local zc = K.PITCH * c + 5
		for i = 0, 94 do
			local x = -23.75 + i * (47.5 / 94)
			for j = 0, 24 do
				local z = zc - 3 + j * (6 / 24)
				inside += 1
				local covered = false
				for _, p in ipairs(mine) do
					local a = p.orientation.y * RAD
					local dx, dz = x - p.position.x, z - p.position.z
					-- local +X maps to (cos a, -sin a); local +Z maps to (sin a, cos a)
					local u = dx * math.cos(a) - dz * math.sin(a)
					local w = dx * math.sin(a) + dz * math.cos(a)
					if math.abs(u) <= p.size.x / 2 and math.abs(w) <= p.size.z / 2 then covered = true end
				end
				if covered then hit += 1 end
			end
		end
		local frac = hit / inside
		if frac < 0.80 then
			table.insert(f, string.format("the chamber %d lock cap covers only %.1f%% of its socket row",
				c, frac * 100))
		end
	end
	-- The chamber price label rides the TOP of the last tread up to its terrace, not the deck's
	-- own riser. The deck version was measured 100% buried on all seven: a deck's -Z face is
	-- coplanar with, and identical in width and height to, the back face of the tread in front
	-- of it, which is an opaque collider. Seven invisible signs and fourteen wasted instances
	-- per plot, and no assertion here noticed, because this loop only ever asked WHICH part
	-- carries the label and never whether that face could be seen.
	--
	-- So the label must sit on a face nothing is coplanar with. That is asserted below, not
	-- assumed: for each labelled part, no other collider may share the plane of its top face.
	for c = 0, K.G - 1 do
		if byName(cav, "Deck_" .. c) == nil then
			table.insert(f, "Deck_" .. c .. " missing")
		end
	end
	local labelled = {}
	for _, p in cav.parts do
		if p.chamberLabel ~= nil then labelled[p.chamberLabel] = p end
	end
	for c = 1, K.G - 1 do
		local p = labelled[c]
		if p == nil then
			table.insert(f, string.format("no part carries chamberLabel %d", c))
		else
			local topY = p.position.y + p.size.y / 2
			for _, q in cav.parts do
				if q ~= p and q.collide and math.abs((q.position.y - q.size.y / 2) - topY) < 1e-6 then
					local dx = math.abs(q.position.x - p.position.x) < (q.size.x + p.size.x) / 2
					local dz = math.abs(q.position.z - p.position.z) < (q.size.z + p.size.z) / 2
					if dx and dz then
						table.insert(f, string.format(
							"chamber %d's label sits on %s, whose top face is buried under %s",
							c, p.name, q.name))
					end
				end
			end
		end
	end
	if labelled[0] ~= nil then
		table.insert(f, "chamber 0 is free and owned from the start; it must carry no price label")
	end
	return f
end

-- 14. Budget.
function CHECK.budget(cav, cfg)
	local f = {}
	local cc = cfg.Cavern
	local expected = 41 + 10 + 3 * K.G
		+ cc.Stalactites + cc.Boulders + cc.Rubble + cc.Veins + 2 * cc.Mushrooms
	if #cav.parts ~= expected then
		table.insert(f, string.format("#parts = %d, want %d", #cav.parts, expected))
	end
	if #cav.lights ~= 10 then table.insert(f, string.format("#lights = %d, want 10", #cav.lights)) end
	if #cav.dust ~= 2 then table.insert(f, string.format("#dust = %d, want 2", #cav.dust)) end
	local walk, seen = 0, {}
	for _, p in ipairs(cav.parts) do
		if p.walkable then walk += 1 end
		if p.walkable and not p.collide then table.insert(f, p.name .. " is walkable but does not collide") end
		if p.castShadow ~= p.collide then table.insert(f, p.name .. " breaks castShadow == collide") end
		if seen[p.name] then table.insert(f, "duplicate part name " .. p.name) end
		seen[p.name] = true
	end
	if walk ~= 28 then table.insert(f, string.format("walkable count %d, want 28", walk)) end
	for _, l in ipairs(cav.lights) do
		local p = byName(cav, l.name)
		if p == nil or p.group ~= "lamp" then
			table.insert(f, "light " .. l.name .. " has no matching lamp part")
		elseif p.position.x ~= l.position.x or p.position.y ~= l.position.y or p.position.z ~= l.position.z then
			table.insert(f, "light " .. l.name .. " is not at its lamp nub")
		end
	end
	return f
end

local ORDER = {
	"socketContainment", "sliceContainment", "colliderAxisAligned", "walkability", "noFallOut",
	"waterSafety", "stairContinuity", "queryInvariant", "lineOfSight", "crystalHeadroom",
	"characterHeadroom", "spawnSafety", "lockCoverage", "budget",
}

local function runSome(cav, cfg, names)
	local out = {}
	for _, name in ipairs(names) do out[name] = CHECK[name](cav, cfg) end
	return out
end

--============================================================================ the shipped cavern

local cav = Cavern.build(Config, 0, Rng)

eq(K.PITCH, 13, "PITCH")
eq(K.RISE, 3, "RISE")
eq(K.HALF_W, 32, "HALF_W")
eq(K.WALL_T, 4, "WALL_T")
eq(K.DECK_BOTTOM, -3, "DECK_BOTTOM")
eq(K.CEIL_UNDER, 44, "CEIL_UNDER")
eq(K.CEIL_TOP, 48, "CEIL_TOP")
eq(K.G, 8, "G = 8 chambers")
eq(K.G * PER, TOTAL_SOCKETS, "the terrace count matches MaxChambers")

eq(#cav.sockets, TOTAL_SOCKETS, "48 socket positions")
eq(#cav.stands, TOTAL_SOCKETS, "48 declared stands")

local results = runSome(cav, Config, ORDER)
for _, name in ipairs(ORDER) do
	local fs = results[name]
	if #fs == 0 then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. " (" .. #fs .. " problem(s))")
		for i = 1, math.min(#fs, 6) do print("        " .. fs[i]) end
	end
end

-- bounds are the ones the spec commits to
near(cav.bounds.minX, -36, 1e-9, "bounds.minX")
near(cav.bounds.maxX, 36, 1e-9, "bounds.maxX")
near(cav.bounds.minY, -6, 1e-9, "bounds.minY")
near(cav.bounds.maxY, 48, 1e-9, "bounds.maxY")
near(cav.bounds.minZ, -18, 1e-9, "bounds.minZ")
near(cav.bounds.maxZ, 138, 1e-9, "bounds.maxZ")
-- The gap between neighbours is a property of the PARTS, not of the reported bounds. The old
-- assertion here compared bounds.maxX - bounds.minX against 76, which the two +/-36 pins
-- directly above already entail exactly: it could not fail under any edit. Measure the real
-- thing instead - the furthest any part actually reaches, including rotation.
local worstX = 0
for _, p in ipairs(cav.parts) do
	local hx = p.size.x / 2
	if p.orientation ~= nil then
		local ry = math.rad(p.orientation.y)
		hx = math.abs(math.cos(ry)) * p.size.x / 2 + math.abs(math.sin(ry)) * p.size.z / 2
	end
	worstX = math.max(worstX, math.abs(p.position.x) + hx)
end
truthy(worstX <= 38, string.format(
	"no part reaches into the neighbouring plot: worst |x| = %.3f against the 40-stud half-pitch", worstX))

-- the shipped part budget, spelled out so a change to it is a decision and not an accident
eq(#cav.parts, 149, "149 generated parts")
local alive1, alive8 = 0, 0
for _, p in ipairs(cav.parts) do
	if p.chamber == -1 or p.chamber >= 1 then alive1 += 1 end
	if p.chamber == -1 or p.chamber >= 8 then alive8 += 1 end
end
eq(alive1, 146, "a 1-chamber player gets 146 generated parts (125 always + 21 caps)")
eq(alive8, 125, "a maxed player gets 125 generated parts (every cap gone)")

-- spawn + cameras are committed values
near(cav.spawn.position.x, 0, 1e-9, "spawn x")
near(cav.spawn.position.y, 4, 1e-9, "spawn y (HRP)")
near(cav.spawn.position.z, -6, 1e-9, "spawn z")
truthy(cav.camera.hero ~= nil and cav.camera.wide ~= nil, "both committed cameras are returned")

--============================================================================ purity of the API

local sp7 = Cavern.socketPos(Config, 7, Rng)
truthy(math.abs(sp7.x - cav.sockets[7].x) < 1e-12
	and math.abs(sp7.y - cav.sockets[7].y) < 1e-12
	and math.abs(sp7.z - cav.sockets[7].z) < 1e-12,
	"socketPos agrees with build()'s socket table")
-- Cavern.build returns `spawn = Cavern.spawn(cfg)` verbatim, so comparing the two is one value
-- against itself and cannot fail. What is worth asserting is that the spawn point is on the
-- apron, above its surface, and clear of every collider - which is the property a player
-- actually depends on and the one a moved wall would break.
local spawnOnly = Cavern.spawn(Config)
local sx, sy, sz = spawnOnly.position.x, spawnOnly.position.y, spawnOnly.position.z
local inside = 0
for _, p in ipairs(cav.parts) do
	if p.collide then
		local dx = math.abs(sx - p.position.x) < p.size.x / 2 + 2
		local dy = math.abs(sy - p.position.y) < p.size.y / 2 + 3
		local dz = math.abs(sz - p.position.z) < p.size.z / 2 + 2
		if dx and dy and dz then inside += 1 end
	end
end
eq(inside, 0, "the spawn point is not inside any collider, head or feet")
truthy(spawnOnly.look.z > 0, "the spawn looks INTO the cavern, not at the entrance wall")

--============================================================================ determinism

local function canon(c)
	local out = {}
	local function n(v) return string.format("%.4f", v) end
	local function v3(v) return n(v.x) .. "," .. n(v.y) .. "," .. n(v.z) end
	for _, p in ipairs(c.parts) do
		table.insert(out, table.concat({
			p.name, p.group, p.shape, v3(p.size), v3(p.position), v3(p.orientation), p.material,
			n(p.color.r) .. "/" .. n(p.color.g) .. "/" .. n(p.color.b),
			n(p.transparency), n(p.reflectance),
			tostring(p.collide), tostring(p.query), tostring(p.castShadow), tostring(p.walkable),
			tostring(p.chamber), tostring(p.chamberLabel),
		}, "|"))
	end
	for _, l in ipairs(c.lights) do
		table.insert(out, table.concat({ "L", l.name, v3(l.position),
			n(l.color.r) .. "/" .. n(l.color.g) .. "/" .. n(l.color.b), n(l.brightness), n(l.range) }, "|"))
	end
	for _, d in ipairs(c.dust) do
		table.insert(out, table.concat({ "D", d.name, v3(d.position), v3(d.size), n(d.rate) }, "|"))
	end
	for i, s in ipairs(c.sockets) do table.insert(out, "S" .. i .. "|" .. v3(s)) end
	for i, s in ipairs(c.stands) do table.insert(out, "T" .. i .. "|" .. v3(s)) end
	table.insert(out, "SP|" .. v3(c.spawn.position) .. "|" .. v3(c.spawn.look))
	table.insert(out, "CH|" .. v3(c.camera.hero.from) .. "|" .. v3(c.camera.hero.at))
	table.insert(out, "CW|" .. v3(c.camera.wide.from) .. "|" .. v3(c.camera.wide.at))
	table.insert(out, string.format("B|%s|%s|%s|%s|%s|%s", n(c.bounds.minX), n(c.bounds.maxX),
		n(c.bounds.minY), n(c.bounds.maxY), n(c.bounds.minZ), n(c.bounds.maxZ)))
	return table.concat(out, "\n")
end

-- FNV-1a, 32-bit. bit32 for the xor; the multiply stays well under 2^53 in a double.
local function fnv1a(s)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return string.format("%08x", h)
end

local a3, b3 = Cavern.build(Config, 3, Rng), Cavern.build(Config, 3, Rng)
eq(canon(a3), canon(b3), "the same seed and plot index give byte-identical geometry")

-- Cross-process golden: this constant was recorded from an earlier luau invocation, so a build
-- that drifts between processes (a pairs() leak into the output order, a stale table) breaks it.
-- Re-recorded 2026-09-09 after two deliberate geometry changes: the chamber price label moved
-- from the deck's buried riser onto the tread top, and rubble gained the socket keep-out that
-- boulders already had. Both changed the emitted model, so the old constant b8eb7b08 was
-- correctly rejected. Only ever move this number when you meant to change the geometry.
local GOLDEN_PLOT3 = "3b23c880"
local hash3 = fnv1a(canon(a3))
if hash3 ~= GOLDEN_PLOT3 then print("  (plot 3 canonical hash: " .. hash3 .. ")") end
eq(hash3, GOLDEN_PLOT3, "plot 3 hashes to the recorded golden")

--============================================================================ plot invariance

local VARIES = { stalactite = true, boulder = true, rubble = true, vein = true, stem = true, cap = true }
local c0, c7, c19 = Cavern.build(Config, 0, Rng), Cavern.build(Config, 7, Rng), Cavern.build(Config, 19, Rng)
local fixedDiffs, decoDiffs = 0, 0
for i, p in ipairs(c0.parts) do
	local q, r = c7.parts[i], c19.parts[i]
	local function same(o)
		return o.name == p.name and o.group == p.group
			and o.position.x == p.position.x and o.position.y == p.position.y and o.position.z == p.position.z
			and o.size.x == p.size.x and o.size.y == p.size.y and o.size.z == p.size.z
			and o.orientation.y == p.orientation.y
			and o.color.r == p.color.r and o.color.g == p.color.g and o.color.b == p.color.b
	end
	if VARIES[p.group] then
		if not same(q) then decoDiffs += 1 end
	else
		if not same(q) then fixedDiffs += 1 end
		if not same(r) then fixedDiffs += 1 end
	end
end
eq(fixedDiffs, 0, "structure, lamps and lock caps are identical on every plot (no translation applied)")
truthy(decoDiffs >= 8, "at least 8 decoration parts genuinely differ between plots (variation is on)")
local socketDrift = 0
for s = 1, TOTAL_SOCKETS do
	-- All three axes. This used to compare only .x while claiming to cover the sockets, so a
	-- plot-dependent Z would have slipped past it and been caught only by the golden hash.
	local a, b, c = c0.sockets[s], c7.sockets[s], c19.sockets[s]
	if a.x ~= b.x or a.y ~= b.y or a.z ~= b.z
		or a.x ~= c.x or a.y ~= c.y or a.z ~= c.z
		or c0.stands[s].x ~= c19.stands[s].x
		or c0.stands[s].y ~= c19.stands[s].y
		or c0.stands[s].z ~= c19.stands[s].z then socketDrift += 1 end
end
eq(socketDrift, 0, "all 48 sockets and stands are identical across plots 0, 7 and 19")

--============================================================================ jitter is not degenerate

local function jitterCheck(sockets)
	local f = {}
	local all = {}
	for c = 0, K.G - 1 do
		local row = {}
		for col = 0, PER - 1 do
			local s = c * PER + col + 1
			local jx = sockets[s].x - (col * 8 - 20)
			local key = string.format("%.6f", jx)
			if row[key] then table.insert(f, string.format("chamber %d repeats jitter %s", c, key)) end
			row[key] = true
			all[key] = true
		end
	end
	local n = 0
	for _ in pairs(all) do n += 1 end
	if n < 40 then table.insert(f, string.format("only %d distinct jitter values across 48 sockets", n)) end
	return f
end

eq(#jitterCheck(cav.sockets), 0, "six distinct jitter values per chamber, >= 40 across all 48")

-- Witness: the SHIPPED formula (Rng.int, i.e. the low bits of the LCG) reproduced exactly.
-- It must be killed by the same check, or the check proves nothing.
local degenerate = {}
for s = 1, TOTAL_SOCKETS do
	local c = math.floor((s - 1) / PER)
	local col = (s - 1) % PER
	local rng = Rng.new(Config.WorldSeed + s * 31 + c * 7)
	degenerate[s] = { x = col * 8 - 20 + rng:int(-15, 15) / 10, y = 3 * c, z = 13 * c + 5 }
end
truthy(#jitterCheck(degenerate) > 0, "the shipped Rng.int jitter is degenerate and this check kills it")

--============================================================================ mutation sweep

-- Rule from the checklist: a sweep where EVERYTHING dies is a broken harness, not a strong one.
-- So the controls come first — edits the suite must NOT notice — and every kill names the check
-- it is supposed to break.

local function mutate(fn, names)
	local m = deepCopy(cav)
	fn(m)
	return runSome(m, Config, names or ORDER)
end

local function total(res)
	local n = 0
	for _, fs in pairs(res) do n += #fs end
	return n
end

-- CONTROL 1: move a boulder somewhere else that is equally legal. Nothing may notice.
--
-- This used to nudge a boulder's COLOUR, which no check reads - so it would have passed against
-- a harness whose fourteen checks all returned {} and proved nothing about discrimination. A
-- position is read by containment, walkability, line of sight and clearance, so a legal move
-- exercises those and must still come back clean. The boulder is placed at |x| = 30 in a stretch
-- with no socket row and no stair, well inside the +/-36 shell.
local control = mutate(function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "boulder" then
			p.position.x = 30
			p.position.z = 62
			p.orientation = { x = 0, y = 0, z = 0 }
			p.size = { x = 4, y = 4, z = 4 }
			break
		end
	end
end)
eq(total(control), 0, "CONTROL: a boulder moved to another legal spot is invisible to all 14 checks")

-- CONTROL 2: one more legal stalactite. Only the budget count may see it.
local control2 = mutate(function(m)
	local base
	for _, p in ipairs(m.parts) do if p.group == "stalactite" then base = deepCopy(p) end end
	base.name = "Stalactite_extra"
	base.orientation = { x = 0, y = 0, z = 0 }
	base.position = { x = 0, y = 40, z = 50 }
	table.insert(m.parts, base)
end)
eq(#control2.walkability + #control2.spawnSafety + #control2.lineOfSight
	+ #control2.sliceContainment + #control2.characterHeadroom, 0,
	"CONTROL: one more legal stalactite disturbs no geometry invariant")
truthy(#control2.budget > 0, "...but the budget check does see the extra part")

local function killed(name, res, msg)
	if res[name] ~= nil and #res[name] > 0 then passed += 1 else
		failed += 1; print("FAIL: mutation not caught by " .. name .. ": " .. msg)
	end
end

killed("socketContainment", mutate(function(m) m.sockets[6].x += 9 end, { "socketContainment" }),
	"socket 6 pushed off the side of its deck")

local noTread = mutate(function(m)
	for i, p in ipairs(m.parts) do if p.name == "TreadA_3" then table.remove(m.parts, i); break end end
end, { "walkability", "stairContinuity", "budget" })
killed("walkability", noTread, "TreadA_3 deleted")
killed("stairContinuity", noTread, "TreadA_3 deleted")
killed("budget", noTread, "TreadA_3 deleted")

local seeing = mutate(function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "stalactite" then
			p.query = true
			p.orientation = { x = 0, y = 0, z = 0 }
			p.size = { x = 3, y = 3, z = 3 }
			p.position = { x = m.sockets[1].x, y = m.sockets[1].y + 2, z = m.sockets[1].z - 2 }
			break
		end
	end
end, { "queryInvariant", "lineOfSight" })
killed("queryInvariant", seeing, "a stalactite set to CanQuery")
killed("lineOfSight", seeing, "a stalactite dropped into socket 1's click line")

killed("colliderAxisAligned", mutate(function(m)
	byName(m, "WallLeft").orientation = { x = 0, y = 5, z = 0 }
end, { "colliderAxisAligned" }), "WallLeft rotated 5 degrees")

killed("sliceContainment", mutate(function(m)
	for _, p in ipairs(m.parts) do if p.group == "boulder" then p.position.x = 39; break end end
end, { "sliceContainment" }), "a boulder at x = 39")

-- ...and one that is only out of bounds AFTER its rotation is applied, so the OBB->AABB
-- arithmetic is doing the work rather than a bare |x| comparison passing vacuously.
killed("sliceContainment", mutate(function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "boulder" then
			p.position = { x = 30, y = p.position.y, z = p.position.z }
			p.size = { x = 6, y = 6, z = 30 }
			p.orientation = { x = 0, y = 45, z = 0 }
			break
		end
	end
end, { "sliceContainment" }), "a boulder inside |x| <= 38 whose ROTATED corner is not")

killed("waterSafety", mutate(function(m)
	byName(m, "BasinFloor").position.y -= 3
end, { "waterSafety" }), "the basin floor dropped 3 studs")

killed("lockCoverage", mutate(function(m)
	for _, p in ipairs(m.parts) do if p.group == "lock" then p.collide = true; break end end
end, { "lockCoverage" }), "a lock slab made solid")

killed("characterHeadroom", mutate(function(m)
	byName(m, "CeilFront").position.y = 24
end, { "characterHeadroom" }), "the ceiling lowered onto the terraces")

killed("spawnSafety", mutate(function(m)
	for _, p in ipairs(m.parts) do
		if p.group == "rubble" then p.position = { x = 0, y = 2, z = -6 }; break end
	end
end, { "spawnSafety" }), "rubble dropped on the spawn point")

killed("noFallOut", mutate(function(m)
	byName(m, "WallRight").position.z = 400
end, { "noFallOut" }), "WallRight moved away, opening the side of the cavern")

killed("crystalHeadroom", mutate(function(m)
	local d = byName(m, "Deck_2")
	d.position = { x = 0, y = d.position.y + 4, z = d.position.z }
end, { "crystalHeadroom" }), "Deck_2 raised into its own sockets' crystal column")

print(string.format("Cavern: %d passed, %d failed", passed, failed))
assert(failed == 0, "Cavern tests failed")
