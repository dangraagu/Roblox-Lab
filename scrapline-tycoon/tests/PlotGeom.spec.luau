-- PlotGeom — where the six plots are, how a plot-local point maps into the world, where every machine sits, the
-- belt's path, and the low surfaces a hazard zone is drawn up to. Run: luau tests/PlotGeom.spec.luau
--
-- DESIGN.md section 3's geometry, checked as arithmetic: plot centres on a ring of 150, 60 degrees apart, each
-- plot's -Z facing the Scrap Market; neighbours 56.6 studs apart at their closest corners; the farthest corner
-- 190.7 from the origin (inside the 400-stud plate); the board 11.4 studs from the arrival (REVIEW-2 R1); the launch pad 26.1;
-- a 132-stud belt; the U-turn's outer edge a stud short of the back wall.

local Config = require("../src/shared/Config")
local PlotGeom = require("../src/shared/PlotGeom")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want ~" .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local C = Config
local P = C.Plot

--============================================================================ the ring
do
	for k = 1, 6 do
		local cx, cz = PlotGeom.centre(C, k)
		near(math.sqrt(cx * cx + cz * cz), 150, 1e-9, "plot " .. k .. " sits on the ring of radius 150")
		-- local -Z faces the origin: one stud towards -Z is one stud closer
		local fx, fz = PlotGeom.toWorld(C, k, 0, -1)
		near(math.sqrt(fx * fx + fz * fz), 149, 1e-9, "plot " .. k .. "'s local -Z points at the Scrap Market")
		-- the round trip
		local wx, wz = PlotGeom.toWorld(C, k, 7.5, -12.25)
		local lx, lz = PlotGeom.toLocal(C, k, wx, wz)
		near(lx, 7.5, 1e-9, "toLocal(toWorld) gives x back on plot " .. k)
		near(lz, -12.25, 1e-9, "...and z")
		eq(PlotGeom.plotAt(C, wx, wz), k, "plotAt finds plot " .. k .. " from a point on it")
	end
	eq(PlotGeom.plotAt(C, 0, 0), nil, "the Scrap Market is on no plot")
	local a1 = { PlotGeom.centre(C, 1) }
	local a2 = { PlotGeom.centre(C, 2) }
	near(math.sqrt((a1[1] - a2[1]) ^ 2 + (a1[2] - a2[2]) ^ 2), 150, 1e-9, "neighbouring centres are 150 apart (60 degrees on a ring of 150)")
end

--============================================================================ plots never touch, and all fit on the plate
do
	local function corners(k)
		local out = {}
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, z = PlotGeom.toWorld(C, k, sx * P.HalfX, sz * P.HalfZ)
				table.insert(out, { x, z })
			end
		end
		return out
	end
	local far, closest = 0, math.huge
	for k = 1, 6 do
		for _, c in corners(k) do
			far = math.max(far, math.sqrt(c[1] ^ 2 + c[2] ^ 2))
			-- the distance from this corner to the neighbouring plot's rectangle
			local n = k % 6 + 1
			local lx, lz = PlotGeom.toLocal(C, n, c[1], c[2])
			local dx = math.max(math.abs(lx) - P.HalfX, 0)
			local dz = math.max(math.abs(lz) - P.HalfZ, 0)
			closest = math.min(closest, math.sqrt(dx * dx + dz * dz))
		end
	end
	print(string.format("  farthest plot corner %.1f studs from the origin; closest gap between neighbours %.1f studs", far, closest))
	truthy(far <= C.World.BaseplateSize / 2, string.format("every plot lies on the 400-stud plate (farthest corner %.1f)", far))
	near(far, 190.7, 0.05, "the farthest corner is 190.7 from the origin (DESIGN 3)")
	truthy(closest >= 50, "neighbouring plots are far apart: nothing of one reaches another")
	-- the market's radius vs the nearest plot edge
	local nearEdge = 150 - P.HalfZ
	truthy(nearEdge - C.World.MarketRadius >= 80, "the Scrap Market (radius 30) is far from every plot's front edge (112)")
end

--============================================================================ the plot layout
do
	local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) end
	near(dist(P.Board, P.Arrival), 11.4, 0.01, "the board stands 11.4 studs from the arrival (inside its 13-stud prompt)")
	truthy(dist(P.Board, P.Arrival) < C.Board.PromptDistance, "...inside the prompt's reach")
	-- REVIEW-2 R1: the bigger board (its frame is width + 0.6 wide, turned to face the arrival) stands clear of every
	-- footprint on the yard floor: the belt legs, the dock, the chute, the arrival pad, the launch pad, the consoles
	-- and every machine. Sampled along the frame's bottom edge.
	do
		local B = P.Board
		local fx, fz = P.Arrival.x - B.x, P.Arrival.z - B.z
		local len = math.sqrt(fx * fx + fz * fz)
		local wx, wz = -fz / len, fx / len -- along the face
		local half = (B.width + 0.6) / 2
		local rects = {
			{ "the left belt leg", -14, -3, 2, 22 }, { "the right belt leg", 14, -3, 2, 22 },
			{ "the dock", P.Dock.x, P.Dock.z, P.Dock.size / 2, P.Dock.size / 2 },
			{ "the chute", P.Chute.x, P.Chute.z, P.Chute.size / 2, P.Chute.size / 2 },
			{ "the arrival pad", P.Arrival.x, P.Arrival.z, P.ArrivalSize / 2, P.ArrivalSize / 2 },
			{ "the launch pad", P.LaunchPad.x, P.LaunchPad.z, P.LaunchPad.radius, P.LaunchPad.radius },
		}
		for t = 1, 6 do
			local cx, cz = PlotGeom.consolePos(C, t)
			table.insert(rects, { "console " .. t, cx, cz, P.ConsoleSize.x / 2, P.ConsoleSize.z / 2 })
			for m = 1, 2 do
				local mx, mz = PlotGeom.machinePos(C, t, m)
				table.insert(rects, { "machine " .. t .. m, mx, mz, P.MachineAcross / 2, P.MachineAlong / 2 })
			end
		end
		local worst, worstName = math.huge, ""
		for i = 0, 100 do
			local a = -half + 2 * half * i / 100
			local x, z = B.x + wx * a, B.z + wz * a
			for _, r in rects do
				local dx = math.max(0, math.abs(x - r[2]) - r[4])
				local dz = math.max(0, math.abs(z - r[3]) - r[5])
				local d = math.sqrt(dx * dx + dz * dz)
				if d < worst then worst, worstName = d, r[1] end
			end
		end
		print(string.format("  the board's frame comes closest to %s: %.2f studs", worstName, worst))
		truthy(worst >= 0.5, string.format("the board's frame stands clear of everything on the yard floor (%.2f studs from %s)", worst, worstName))
	end
	near(dist(P.LaunchPad, P.Arrival), 26.1, 0.05, "the launch pad is 26.1 studs from the arrival, in view")
	near(PlotGeom.beltLength(C), 44 + 44 + math.pi * 14, 1e-9, "the belt is 44 + 44 + a 44-stud U-turn = 132 studs")
	near(P.Belt.turnZ + P.Belt.turnRadius + P.Belt.width / 2, 35, 1e-9, "the U-turn's outer edge is at z = 35...")
	truthy(P.Wall.z - P.Wall.depth / 2 >= 36, "...a stud short of the back wall (z = 36)")
	-- every station centre lies on the belt path, in order
	local last = -1
	for t = 1, 6 do
		local s = PlotGeom.stationS(C, t)
		local x, z = PlotGeom.beltPoint(C, s)
		near(x, P.StationCentres[t].x, 1e-9, "station " .. t .. " is on the belt (x)")
		near(z, P.StationCentres[t].z, 1e-9, "station " .. t .. " is on the belt (z)")
		truthy(s > last, "station " .. t .. " comes after station " .. (t - 1) .. " along the flow")
		last = s
	end
	-- machine a sits UPSTREAM of its station centre, its twin downstream, on both legs
	for t = 1, 6 do
		local ax, az = PlotGeom.machinePos(C, t, 1)
		local bx, bz = PlotGeom.machinePos(C, t, 2)
		eq(ax, P.StationCentres[t].x, "machine a of station " .. t .. " is on the belt")
		near(math.abs(az - bz), 7, 1e-9, "a machine and its twin are 7 studs apart")
		local sa = PlotGeom.stationS(C, t) + (if t <= 3 then az - P.StationCentres[t].z else P.StationCentres[t].z - az)
		truthy(sa < PlotGeom.stationS(C, t), "machine a of station " .. t .. " is upstream of the centre")
	end
	-- the middle of the U to every station: 14.0 or 19.8 studs (DESIGN 3)
	local mid = { x = 0, z = -2 }
	for t = 1, 6 do
		local d = dist(mid, P.StationCentres[t])
		truthy(math.abs(d - 14) < 0.05 or math.abs(d - 19.8) < 0.05, string.format("station %d is %.1f studs from the middle of the U", t, d))
	end
	-- consoles are inside the U, on the floor you walk
	for t = 1, 6 do
		local cx, cz = PlotGeom.consolePos(C, t)
		truthy(math.abs(cx) < P.Belt.legX - P.Belt.width / 2, "station " .. t .. "'s console is inside the U")
		eq(cz, P.StationCentres[t].z, "...level with its station")
	end
end

--============================================================================ beltPoint
do
	local x0, z0 = PlotGeom.beltPoint(C, 0)
	eq(x0, -14, "the belt starts on the left leg")
	eq(z0, -25, "...at z = -25, by the chute")
	local x1, z1 = PlotGeom.beltPoint(C, 44)
	near(x1, -14, 1e-9, "the left leg ends at x = -14")
	near(z1, 19, 1e-9, "...z = 19, where the U-turn begins")
	local xt, zt = PlotGeom.beltPoint(C, 44 + math.pi * 7)
	near(xt, 0, 1e-9, "half way round the U-turn: x = 0")
	near(zt, 33, 1e-9, "...at its far point z = 33")
	local xe, ze = PlotGeom.beltPoint(C, PlotGeom.beltLength(C))
	near(xe, 14, 1e-9, "the belt ends on the right leg")
	near(ze, -25, 1e-9, "...at z = -25, by the dock")
	local xc, zc = PlotGeom.beltPoint(C, 1e6)
	near(zc, -25, 1e-9, "past the end it stays at the end")
	eq(xc, 14, "...")
end

--============================================================================ the floors a hazard zone is drawn up to
do
	local floor = C.World.FloorTopY
	near(PlotGeom.zoneFloor(C, 0, -2, 4), floor, 1e-9, "a zone in the middle of the U touches nothing: drawn at the floor")
	near(PlotGeom.zoneFloor(C, P.Arrival.x, P.Arrival.z, 3), P.ArrivalTopY, 1e-9, "a zone on the arrival pad is drawn on top of it")
	near(PlotGeom.zoneFloor(C, -14, 0, 3), P.Belt.topY, 1e-9, "a zone on the left leg of the belt is drawn on top of the belt")
	near(PlotGeom.zoneFloor(C, 0, 33, 3), P.Belt.topY, 1e-9, "...and on the U-turn")
	near(PlotGeom.zoneFloor(C, -9, -2, 3), floor + P.ConsoleSize.y, 1e-9, "on a console pad: its top")
	near(PlotGeom.zoneFloor(C, P.LaunchPad.x, P.LaunchPad.z, 2), floor + P.LaunchPad.height, 1e-9, "on the launch pad: its top")
	near(PlotGeom.zoneFloor(C, P.Dock.x, P.Dock.z, 2), floor + P.Dock.height, 1e-9, "on the dock: its top")
	-- touching edges do not count: a zone whose edge just reaches the belt's inner edge (x = -12)
	near(PlotGeom.zoneFloor(C, -8, 0, 4), floor + P.ConsoleSize.y, 1e-9, "a zone reaching the console but stopping at the belt's edge")
	near(PlotGeom.zoneFloor(C, -6, 0, 6.5), P.Belt.topY, 1e-9, "a zone crossing the belt's edge is drawn on the belt")
end

print(string.format("PlotGeom: %d passed, %d failed", passed, failed))
if failed > 0 then error("PlotGeom spec failed", 0) end
