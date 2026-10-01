--!strict
-- PlotGeom.luau — where the 8 plots are and how a plot-local point maps into the world. PURE.
--
-- Plot k's centre sits on a ring of radius World.RingRadius around the origin (the observatory),
-- 360/8 = 45 degrees apart. Plot-local axes: -Z points AT the observatory, +Z away from it, +X to the
-- right when facing the observatory... from the plot's own point of view that is the frame
-- CFrame.lookAt(centre, origin), whose LookVector is -Z. The server builds every Part with that CFrame
-- and uses these functions for every rule; the client uses them to know where its own plot is. The two
-- must agree, and robloxemu/check_meteordroptycoon.luau measures that they do on the built parts.
-- Requires nothing. Spec: tests/Meteors.spec.luau.

local PlotGeom = {}

-- (x, z) of plot k's centre, and the outward unit vector (ux, uz).
function PlotGeom.centre(cfg: any, k: number): (number, number, number, number)
	local a = (k - 1) / cfg.World.Plots * math.pi * 2
	local ux, uz = math.sin(a), math.cos(a)
	local R = cfg.World.RingRadius
	return ux * R, uz * R, ux, uz
end

-- Plot-local (lx, lz) -> world (x, z). Local +Z = outward (ux, uz); local +X = CFrame.lookAt's
-- RightVector = LookVector x Up = (-ux, 0, -uz) x (0, 1, 0) = (uz, 0, -ux).
function PlotGeom.toWorld(cfg: any, k: number, lx: number, lz: number): (number, number)
	local cx, cz, ux, uz = PlotGeom.centre(cfg, k)
	return cx + uz * lx + ux * lz, cz - ux * lx + uz * lz
end

function PlotGeom.toLocal(cfg: any, k: number, x: number, z: number): (number, number)
	local cx, cz, ux, uz = PlotGeom.centre(cfg, k)
	local dx, dz = x - cx, z - cz
	return dx * uz - dz * ux, dx * ux + dz * uz
end

-- The plot a world point stands on (within PlotRadius of its centre), or nil.
function PlotGeom.plotAt(cfg: any, x: number, z: number): number?
	for k = 1, cfg.World.Plots do
		local cx, cz = PlotGeom.centre(cfg, k)
		local dx, dz = x - cx, z - cz
		if dx * dx + dz * dz <= cfg.World.PlotRadius * cfg.World.PlotRadius then
			return k
		end
	end
	return nil
end

-- The low surfaces a player can stand on inside a plot (plot-local centres; `top` in world y), as
-- Main.server.luau builds them. Walls (the Smelter's body, the board, the sign post) are not floors.
function PlotGeom.floors(cfg: any): { any }
	local P, disc = cfg.Plot, cfg.World.DiscTopY
	return {
		{ part = "Arrival", shape = "square", x = P.Arrival.x, z = P.Arrival.z, half = P.ArrivalSize / 2, top = P.ArrivalTopY },
		{ part = "SmelterBase", shape = "disc", x = 0, z = 0, radius = P.SmelterRadius, top = disc + P.SmelterBaseHeight },
		{ part = "BeaconBase", shape = "disc", x = P.Beacon.x, z = P.Beacon.z, radius = P.BeaconBaseRadius, top = disc + P.BeaconBaseHeight },
	}
end

-- The height a hazard's zone (a circle at plot-local lx, lz with radius r) is drawn up to: the highest low
-- surface it overlaps, or the plot disc. REVIEW-1: drawn at the disc, 57-81% of a zone on the arrival pad
-- lay under the pad. Overlap is strict (touching edges do not count).
function PlotGeom.zoneFloor(cfg: any, lx: number, lz: number, r: number): number
	local y = cfg.World.DiscTopY
	for _, f in PlotGeom.floors(cfg) do
		local over
		if f.shape == "square" then
			local dx = math.max(math.abs(lx - f.x) - f.half, 0)
			local dz = math.max(math.abs(lz - f.z) - f.half, 0)
			over = dx * dx + dz * dz < r * r
		else
			local dx, dz = lx - f.x, lz - f.z
			over = math.sqrt(dx * dx + dz * dz) < r + f.radius
		end
		if over and f.top > y then y = f.top end
	end
	return y
end

return PlotGeom
