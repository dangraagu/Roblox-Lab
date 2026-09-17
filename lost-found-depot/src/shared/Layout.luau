--!strict
-- Layout.luau — where everything in a bay is, in bay-local studs (DESIGN.md §4).
--
-- +Y up, the floor top at y = 0, the pick point P at the origin, the bins toward -Z and the spawn
-- toward +Z. Returns plain numbers so the luau CLI can assert every distance §4.1 quotes, and the
-- server builds the bay from these same functions — so the tested numbers ARE the built world.
--
-- Pure, requires nothing.

local Layout = {}

-- World x of bay `index` (1-based). Bays sit on a row along +X; indices are recycled through a
-- free list, so this never marches outward (checklist: unbounded coordinates).
function Layout.bayOriginX(cfg: any, index: number): number
	return cfg.Bay.FirstX + cfg.Bay.Pitch * (index - 1)
end

function Layout.binAngle(cfg: any, arcSlot: number): number
	return math.rad(cfg.Bay.ArcFirstDegrees + cfg.Bay.ArcStepDegrees * (arcSlot - 1))
end

-- The centre of bin `arcSlot`'s crate on the floor, on an arc of ArcRadius around P.
function Layout.binCentre(cfg: any, arcSlot: number): (number, number)
	local a = Layout.binAngle(cfg, arcSlot)
	return cfg.Bay.ArcRadius * math.cos(a), -cfg.Bay.ArcRadius * math.sin(a)
end

-- Where an honest player stands to use bin `arcSlot`: 5 studs short of its centre, toward P —
-- 2 studs in front of the crate's 6-deep front face, inside the 6-stud prompt.
function Layout.binStand(cfg: any, arcSlot: number): (number, number)
	local a = Layout.binAngle(cfg, arcSlot)
	local r = cfg.Bay.ArcRadius - 5
	return r * math.cos(a), -r * math.sin(a)
end

-- The crate's four footprint corners, { x, z } each. The crate faces P: its 8-stud width runs
-- across the arc and its 6-stud depth along the line to P.
function Layout.binCorners(cfg: any, arcSlot: number): { { number } }
	local cx, cz = Layout.binCentre(cfg, arcSlot)
	local len = math.sqrt(cx * cx + cz * cz)
	local ux, uz = -cx / len, -cz / len -- toward P
	local wx, wz = uz, -ux -- across
	local hw, hd = cfg.Bay.BinSize[1] / 2, cfg.Bay.BinSize[3] / 2
	local out = {}
	for _, sw in { -1, 1 } do
		for _, sd in { -1, 1 } do
			table.insert(out, { cx + sw * hw * wx + sd * hd * ux, cz + sw * hw * wz + sd * hd * uz })
		end
	end
	return out
end

-- Tray slots 1-4 are the front row (z = FrontRowZ), 5-8 the back row on the step.
function Layout.slotXZ(cfg: any, slot: number): (number, number)
	local cols = #cfg.Bay.SlotXs
	local col = ((slot - 1) % cols) + 1
	local row = if slot > cols then 2 else 1
	return cfg.Bay.SlotXs[col], if row == 1 then cfg.Bay.FrontRowZ else cfg.Bay.BackRowZ
end

-- The height an item in `slot` rests on: the tray top, or the step for the back row.
function Layout.slotSurfaceY(cfg: any, slot: number): number
	local trayTop = cfg.Bay.TrayCentre[2] + cfg.Bay.TraySize[2] / 2
	if slot > #cfg.Bay.SlotXs then
		return trayTop + cfg.Bay.StepHeight
	end
	return trayTop
end

-- Is a bay-local point inside the bay's walkable interior (the Back Room included)?
function Layout.inside(cfg: any, x: number, y: number, z: number): boolean
	local B = cfg.Bay
	if y < -2 or y > B.WallHeight then
		return false
	end
	if x >= B.MinX and x <= B.MaxX and z >= B.MinZ and z <= B.MaxZ then
		return true
	end
	local R = B.BackRoom
	return x >= R.MinX and x <= R.MaxX and z >= R.MinZ and z < B.MinZ
end

return Layout
