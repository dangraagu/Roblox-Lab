--!strict
-- Farm.luau — where the six farms, their fields, tiles and pads are (DESIGN.md §2.4, §9). Pure geometry.
--
-- A farm's LOCAL frame: z runs outward from the market (z = 0 is the inner edge, F.InnerRadius from the
-- origin), x runs sideways. Farm k sits at yaw (k - 1) * 360 / Slots degrees, outward direction
-- (sin yaw, cos yaw). Positions are plain numbers in the ground plane (x, z); the server adds heights.
-- F is Config.Farm.

local Farm = {}

-- { ox, oz (inner edge centre), dx, dz (outward unit), lx, lz (sideways unit), yaw (radians) }
function Farm.frame(k: number, F: any): any
	local yaw = math.rad((k - 1) * 360 / F.Slots)
	local dx, dz = math.sin(yaw), math.cos(yaw)
	return { ox = dx * F.InnerRadius, oz = dz * F.InnerRadius, dx = dx, dz = dz, lx = dz, lz = -dx, yaw = yaw }
end

function Farm.toWorld(k: number, lx: number, lz: number, F: any): (number, number)
	local fr = Farm.frame(k, F)
	return fr.ox + fr.dx * lz + fr.lx * lx, fr.oz + fr.dz * lz + fr.lz * lx
end

function Farm.toLocal(k: number, x: number, z: number, F: any): (number, number)
	local fr = Farm.frame(k, F)
	local rx, rz = x - fr.ox, z - fr.oz
	return rx * fr.lx + rz * fr.lz, rx * fr.dx + rz * fr.dz
end

-- centre of field f in the farm's local frame
function Farm.fieldCentreLocal(f: number, F: any): (number, number)
	local cell = F.FieldGrid[f]
	local step = F.FieldSize + F.PathWidth
	local lx = cell[1] * step
	local lz = F.PorchDepth + F.FieldSize / 2 + (cell[2] - 1) * step
	return lx, lz
end

-- centre of tile t (1..9, row-major, 3 x 3) of field f, local
function Farm.tileLocal(f: number, t: number, F: any): (number, number)
	local cx, cz = Farm.fieldCentreLocal(f, F)
	local col = (t - 1) % 3 - 1
	local row = (t - 1) // 3 - 1
	return cx + col * F.TileSize, cz + row * F.TileSize
end

function Farm.fieldCentre(k: number, f: number, F: any): (number, number)
	local lx, lz = Farm.fieldCentreLocal(f, F)
	return Farm.toWorld(k, lx, lz, F)
end

function Farm.tileCentre(k: number, f: number, t: number, F: any): (number, number)
	local lx, lz = Farm.tileLocal(f, t, F)
	return Farm.toWorld(k, lx, lz, F)
end

function Farm.tileKey(f: number, t: number): string
	return tostring(f) .. "_" .. tostring(t)
end

function Farm.padPos(k: number, F: any): (number, number)
	return Farm.toWorld(k, 0, F.PadLocalZ, F)
end

-- the farm rectangle's four corners { { x, z } }
function Farm.corners(k: number, F: any): { { number } }
	local out = {}
	for _, c in { { -F.Width / 2, 0 }, { F.Width / 2, 0 }, { F.Width / 2, F.Depth }, { -F.Width / 2, F.Depth } } do
		local x, z = Farm.toWorld(k, c[1], c[2], F)
		table.insert(out, { x, z })
	end
	return out
end

-- which farm's rectangle contains (x, z), or nil
function Farm.slotAt(x: number, z: number, F: any): number?
	for k = 1, F.Slots do
		local lx, lz = Farm.toLocal(k, x, z, F)
		if math.abs(lx) <= F.Width / 2 and lz >= 0 and lz <= F.Depth then
			return k
		end
	end
	return nil
end

return Farm
