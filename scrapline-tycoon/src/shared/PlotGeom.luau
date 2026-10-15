--!strict
-- PlotGeom.luau — where the six plots are, how a plot-local point maps into the world, where every machine and
-- console sits, the belt's path, and the low surfaces a player stands on. PURE.
--
-- Plot k's centre sits on a ring of radius World.RingRadius around the Scrap Market, 360/6 = 60 degrees apart.
-- Plot-local axes: -Z points AT the market, +Z away from it; the frame is CFrame.lookAt(centre, origin), whose
-- LookVector is -Z. The server builds every Part with that CFrame and uses these functions for every rule (Fix
-- range, the trusted position, the arrival); the clients use them to draw belt items and hazards. The two must
-- agree, and robloxemu/check_scraplinetycoon*.luau measure that they do on the built parts.
--
-- The belt (DESIGN.md section 3): a left leg at x = -14 from z = -25 up to 19, a U-turn of radius 14 around
-- (0, 19), a right leg at x = +14 back down to -25. Items ride it at Belt.speed studs/s; station t acts at
-- path distance stationS(t). The U-turn is built from turnSegments straight chords (beltSegments), which is also
-- what floors() reports. Requires nothing. Spec: tests/PlotGeom.spec.luau.

local PlotGeom = {}

-- (x, z) of plot k's centre, and the outward unit vector (ux, uz).
function PlotGeom.centre(cfg: any, k: number): (number, number, number, number)
	local a = (k - 1) / cfg.World.Plots * math.pi * 2
	local ux, uz = math.sin(a), math.cos(a)
	local R = cfg.World.RingRadius
	return ux * R, uz * R, ux, uz
end

-- Plot-local (lx, lz) -> world (x, z). Local +Z = outward (ux, uz); local +X = CFrame.lookAt's RightVector =
-- LookVector x Up = (-ux, 0, -uz) x (0, 1, 0) = (uz, 0, -ux).
function PlotGeom.toWorld(cfg: any, k: number, lx: number, lz: number): (number, number)
	local cx, cz, ux, uz = PlotGeom.centre(cfg, k)
	return cx + uz * lx + ux * lz, cz - ux * lx + uz * lz
end

function PlotGeom.toLocal(cfg: any, k: number, x: number, z: number): (number, number)
	local cx, cz, ux, uz = PlotGeom.centre(cfg, k)
	local dx, dz = x - cx, z - cz
	return dx * uz - dz * ux, dx * ux + dz * uz
end

-- The plot a world point stands on (inside its 64 x 76 rectangle), or nil.
function PlotGeom.plotAt(cfg: any, x: number, z: number): number?
	local P = cfg.Plot
	for k = 1, cfg.World.Plots do
		local lx, lz = PlotGeom.toLocal(cfg, k, x, z)
		if math.abs(lx) <= P.HalfX and math.abs(lz) <= P.HalfZ then return k end
	end
	return nil
end

--============================================================================ the belt
function PlotGeom.beltLength(cfg: any): number
	local B = cfg.Plot.Belt
	return 2 * (B.z1 - B.z0) + math.pi * B.turnRadius
end

-- (x, z) at path distance s from the start of the left leg (clamped to the belt).
function PlotGeom.beltPoint(cfg: any, s: number): (number, number)
	local B = cfg.Plot.Belt
	local leg = B.z1 - B.z0
	local arc = math.pi * B.turnRadius
	local d = math.clamp(s, 0, 2 * leg + arc)
	if d <= leg then
		return -B.legX, B.z0 + d
	elseif d <= leg + arc then
		local theta = math.pi - (d - leg) / B.turnRadius
		return B.turnRadius * math.cos(theta), B.turnZ + B.turnRadius * math.sin(theta)
	end
	return B.legX, B.z1 - (d - leg - arc)
end

-- Path distance of station t's centre.
function PlotGeom.stationS(cfg: any, t: number): number
	local B = cfg.Plot.Belt
	local c = cfg.Plot.StationCentres[t]
	if t <= 3 then return c.z - B.z0 end
	return (B.z1 - B.z0) + math.pi * B.turnRadius + (B.turnZ - c.z)
end

-- Plot-local (x, z) of machine m (1 = a, 2 = the twin) at station t: a sits upstream of the centre.
function PlotGeom.machinePos(cfg: any, t: number, m: number): (number, number)
	local c = cfg.Plot.StationCentres[t]
	local off = cfg.Plot.MachineOffset
	local up = if t <= 3 then -1 else 1 -- the left leg flows +Z, the right leg -Z
	local sign = if m == 1 then up else -up
	return c.x, c.z + sign * off
end

-- Plot-local (x, z) of station t's console pad, inside the U.
function PlotGeom.consolePos(cfg: any, t: number): (number, number)
	local c = cfg.Plot.StationCentres[t]
	return (if c.x < 0 then -1 else 1) * cfg.Plot.ConsoleInset, c.z
end

-- The belt as straight pieces: { name, x, z, hx (half across), hz (half along), ax, az (unit along) }.
function PlotGeom.beltSegments(cfg: any): { any }
	local B = cfg.Plot.Belt
	local half = B.width / 2
	local midZ = (B.z0 + B.z1) / 2
	local out = {
		{ name = "BeltLeft", x = -B.legX, z = midZ, hx = half, hz = (B.z1 - B.z0) / 2, ax = 0, az = 1 },
		{ name = "BeltRight", x = B.legX, z = midZ, hx = half, hz = (B.z1 - B.z0) / 2, ax = 0, az = 1 },
	}
	local n = B.turnSegments
	for i = 1, n do
		local t0 = math.pi - (i - 1) * math.pi / n
		local t1 = math.pi - i * math.pi / n
		local x0, z0 = B.turnRadius * math.cos(t0), B.turnZ + B.turnRadius * math.sin(t0)
		local x1, z1 = B.turnRadius * math.cos(t1), B.turnZ + B.turnRadius * math.sin(t1)
		local dx, dz = x1 - x0, z1 - z0
		local len = math.sqrt(dx * dx + dz * dz)
		table.insert(out, { name = "BeltTurn_" .. i, x = (x0 + x1) / 2, z = (z0 + z1) / 2, hx = half, hz = len / 2 + 0.5,
			ax = dx / len, az = dz / len })
	end
	return out
end

--============================================================================ floors: the low surfaces a player stands on
-- As Main.server.luau builds them. Walls (machines, the chute, the board, the factory wall) are not floors.
-- shape "rect": centre x, z, half extents hx (across), hz (along unit (ax, az)); shape "disc": radius.
function PlotGeom.floors(cfg: any): { any }
	local P = cfg.Plot
	local floor = cfg.World.FloorTopY
	local out = {
		{ part = "Arrival", shape = "rect", x = P.Arrival.x, z = P.Arrival.z, hx = P.ArrivalSize / 2, hz = P.ArrivalSize / 2, ax = 0, az = 1, top = P.ArrivalTopY },
		{ part = "Dock", shape = "rect", x = P.Dock.x, z = P.Dock.z, hx = P.Dock.size / 2, hz = P.Dock.size / 2, ax = 0, az = 1, top = floor + P.Dock.height },
		{ part = "LaunchPad", shape = "disc", x = P.LaunchPad.x, z = P.LaunchPad.z, radius = P.LaunchPad.radius, top = floor + P.LaunchPad.height },
	}
	for _, seg in PlotGeom.beltSegments(cfg) do
		table.insert(out, { part = seg.name, shape = "rect", x = seg.x, z = seg.z, hx = seg.hx, hz = seg.hz, ax = seg.ax, az = seg.az, top = P.Belt.topY })
	end
	for t = 1, 6 do
		local cx, cz = PlotGeom.consolePos(cfg, t)
		table.insert(out, { part = "Console_" .. cfg.Stations.Order[t], shape = "rect", x = cx, z = cz, hx = P.ConsoleSize.x / 2,
			hz = P.ConsoleSize.z / 2, ax = 0, az = 1, top = floor + P.ConsoleSize.y })
	end
	return out
end

-- The height a hazard's zone (a circle at plot-local lx, lz with radius r) is drawn up to: the highest low
-- surface it overlaps, or the plot floor (meteor-drop-tycoon REVIEW-1: a zone drawn at the floor hid under a
-- pad). Overlap is strict (touching edges do not count).
function PlotGeom.zoneFloor(cfg: any, lx: number, lz: number, r: number): number
	local y = cfg.World.FloorTopY
	for _, f in PlotGeom.floors(cfg) do
		local over
		if f.shape == "rect" then
			local vx, vz = lx - f.x, lz - f.z
			local along = vx * f.ax + vz * f.az
			local across = vx * f.az - vz * f.ax
			local da = math.max(math.abs(along) - f.hz, 0)
			local dc = math.max(math.abs(across) - f.hx, 0)
			over = da * da + dc * dc < r * r
		else
			local dx, dz = lx - f.x, lz - f.z
			over = math.sqrt(dx * dx + dz * dz) < r + f.radius
		end
		if over and f.top > y then y = f.top end
	end
	return y
end

return PlotGeom
