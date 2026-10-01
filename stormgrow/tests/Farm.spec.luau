-- Spec for Farm: where the six farms, their fields, tiles and pads are. Run: luau tests/Farm.spec.luau
--
-- Pure geometry (DESIGN.md §2.4, §9). The server builds the world from these numbers and the client draws
-- crops at the same numbers, so a wrong number here is a tile you can never tap or a farm inside another.
local Farm = require("../src/shared/Farm")
local Config = require("../src/shared/Config")
local F = Config.Farm

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end
local function approx(a, b, msg, tol)
	tol = tol or 1e-6
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

local function dist(ax, az, bx, bz)
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

--================================================================ the frames

do
	local x, z = Farm.toWorld(1, 0, 0, F)
	approx(x, 0, "farm 1's inner edge centre is on the +z axis")
	approx(z, 100, "100 studs from the origin")
	x, z = Farm.toWorld(2, 0, 0, F)
	approx(x, 100 * math.sin(math.rad(60)), "farm 2 sits at yaw 60 degrees (x)")
	approx(z, 100 * math.cos(math.rad(60)), "farm 2 sits at yaw 60 degrees (z)")
	for k = 1, F.Slots do
		local ix, iz = Farm.toWorld(k, 0, 0, F)
		local ox, oz = Farm.toWorld(k, 0, 10, F)
		approx(dist(ox, oz, 0, 0) - dist(ix, iz, 0, 0), 10, "farm " .. k .. ": local +z points away from the market")
	end
end

--================================================================ fields and tiles

do
	eq(#F.FieldGrid, F.Fields, "a grid cell for each of the six fields")
	local lx, lz = Farm.fieldCentreLocal(1, F)
	approx(lx, 0, "field 1 is front centre")
	approx(lz, 22, "its centre is 22 studs out (porch 10 + half a field)")
	lx, lz = Farm.fieldCentreLocal(6, F)
	approx(lx, 30, "field 6 is back right")
	approx(lz, 52, "centre 52 studs out")
	local bad = 0
	for f = 1, F.Fields do
		local cx, cz = Farm.fieldCentreLocal(f, F)
		for t = 1, F.TilesPerField do
			local tx, tz = Farm.tileLocal(f, t, F)
			if math.abs(tx - cx) + F.SoilSize / 2 > F.FieldSize / 2 + 1e-9 or math.abs(tz - cz) + F.SoilSize / 2 > F.FieldSize / 2 + 1e-9 then
				bad += 1
			end
			if math.abs(tx) + F.SoilSize / 2 > F.Width / 2 or tz - F.SoilSize / 2 < F.PorchDepth or tz + F.SoilSize / 2 > F.Depth then
				bad += 1
			end
		end
	end
	eq(bad, 0, "every tile's soil lies inside its field, and every field inside the farm, behind the porch")
	-- tiles never overlap: 54 soil plates, pairwise
	local all = {}
	for f = 1, F.Fields do
		for t = 1, F.TilesPerField do
			local x, z = Farm.tileLocal(f, t, F)
			table.insert(all, { x, z })
		end
	end
	eq(#all, 54, "54 tiles a farm")
	local overlap, minGap = 0, math.huge
	for i = 1, #all do
		for j = i + 1, #all do
			local dx, dz = math.abs(all[i][1] - all[j][1]), math.abs(all[i][2] - all[j][2])
			if dx < F.SoilSize and dz < F.SoilSize then overlap += 1 end
			minGap = math.min(minGap, math.max(dx, dz))
		end
	end
	eq(overlap, 0, "no two soil plates overlap")
	approx(minGap, F.TileSize, "neighbouring tiles are one tile (8 studs) apart")
	-- keys
	eq(Farm.tileKey(3, 7), "3_7", "tile keys are strings field_tile")
end

--================================================================ six farms around a market

do
	-- no two farm rectangles overlap, and the closest corners of neighbours are 27.3 studs apart
	local closest = math.huge
	for a = 1, F.Slots do
		for b = a + 1, F.Slots do
			for _, ca in Farm.corners(a, F) do
				for _, cb in Farm.corners(b, F) do
					closest = math.min(closest, dist(ca[1], ca[2], cb[1], cb[2]))
				end
			end
			-- separating-axis test on the two rectangles
			local sep = false
			for _, k in { a, b } do
				local fr = Farm.frame(k, F)
				for _, axis in { { fr.dx, fr.dz }, { fr.lx, fr.lz } } do
					local function span(slot)
						local lo, hi = math.huge, -math.huge
						for _, c in Farm.corners(slot, F) do
							local v = c[1] * axis[1] + c[2] * axis[2]
							lo, hi = math.min(lo, v), math.max(hi, v)
						end
						return lo, hi
					end
					local alo, ahi = span(a)
					local blo, bhi = span(b)
					if ahi < blo or bhi < alo then sep = true end
				end
			end
			truthy(sep, "farms " .. a .. " and " .. b .. " do not overlap")
		end
	end
	approx(closest, 27.25, "neighbouring farms' inner corners are 27.3 studs apart (DESIGN.md §2.4)", 0.05)
	-- every farm is outside the market and inside the valley wall
	local inner, outer = math.huge, 0
	for k = 1, F.Slots do
		for _, c in Farm.corners(k, F) do
			local d = dist(c[1], c[2], 0, 0)
			inner, outer = math.min(inner, d), math.max(outer, d)
		end
	end
	truthy(inner > F.MarketRadius + 20, string.format("every farm is well clear of the market square (nearest corner %.1f)", inner))
	truthy(outer < F.WallRadius - 40, string.format("and well inside the valley wall (farthest corner %.1f of %d)", outer, F.WallRadius))
end

--================================================================ the pad and the first taps

do
	for k = 1, F.Slots do
		local px, pz = Farm.padPos(k, F)
		local lx, lz = Farm.toLocal(k, px, pz, F)
		truthy(math.abs(lx) + F.PadSize / 2 <= F.Width / 2 and lz - F.PadSize / 2 >= 0 and lz + F.PadSize / 2 <= F.PorchDepth,
			"farm " .. k .. "'s pad lies on its porch")
		-- every tile of field 1 can be tapped from the pad without walking (the first 5 seconds)
		local far = 0
		for t = 1, F.TilesPerField do
			local x, z = Farm.tileCentre(k, 1, t, F)
			far = math.max(far, math.sqrt(dist(px, pz, x, z) ^ 2 + 3 ^ 2))
		end
		truthy(far < F.ServerReach, string.format("farm %d: every field-1 tile is within tap reach of the pad (%.1f < %d)", k, far, F.ServerReach))
	end
	-- toLocal inverts toWorld
	local x, z = Farm.toWorld(4, 13, 37, F)
	local lx, lz = Farm.toLocal(4, x, z, F)
	approx(lx, 13, "toLocal inverts toWorld (x)")
	approx(lz, 37, "toLocal inverts toWorld (z)")
	-- which farm is a point on
	local sx, sz = Farm.tileCentre(3, 5, 2, F)
	eq(Farm.slotAt(sx, sz, F), 3, "slotAt finds the farm under a tile")
	eq((Farm.slotAt(0, 0, F)), nil, "the market square is nobody's farm")
end

print(string.format("Farm: %d passed, %d failed", passed, failed))
assert(failed == 0, "Farm tests failed")
