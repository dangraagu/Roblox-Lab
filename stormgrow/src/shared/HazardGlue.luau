--!strict
-- HazardGlue.luau — StormGrow's adaptations of the verbatim Hazards.luau to flat ground (DESIGN.md §4).
-- Pure, no requires (Farm is passed in). Hazards.luau itself is untouched (sha256 recorded in CLAUDE.md).
--
-- plus1-jump's climber stands over open air, so a lane may start below them and fly on below them. A farm
-- has ground, so:
--   1. ctxPitch: the camera pitch handed to Hazards.step is clamped to >= GroundPitchFloor (-25 degrees).
--      The view window is +-ViewPitchDegrees (25) around it, so its upper edge is never below level and a
--      lane never STARTS below the player's root.
--   2. drawnY: a descending lane (the crow swoops at up to 10 degrees) flies on past the player for `pass`
--      seconds and would dive up to 3.2 studs into the ground (tests/EnvConfig.spec.luau measured -3.21).
--      The client DRAWS the hazard no lower than ground + SkimHeight. Hits still use the true plan, which
--      is lower there, so the clamp can only make a hit less likely than it looks: forgiving, never unfair.

local HazardGlue = {}

HazardGlue.SkimHeight = 1

function HazardGlue.ctxPitch(cameraPitch: number, Hz: any): number
	if cameraPitch ~= cameraPitch then return 0 end
	return math.max(cameraPitch, math.rad(Hz.GroundPitchFloor))
end

function HazardGlue.drawnY(y: number, groundY: number): number
	return math.max(y, groundY + HazardGlue.SkimHeight)
end

-- 3. surfaceY / ringY (REVIEW-1): the red ring has to lie ON what the farmer stands on. It was drawn 0.05-0.25 studs
--    over the ground, inside the porch (top 0.4), the farm pads (top 1) and the soil plates (top 0.6), so wherever a
--    farmer usually stands it was hidden under the floor (check_stormgrow_hazards part G: 0 of 16 points seen on the
--    pad, the porch or a plate). These are the tops of what Main.server builds (part G also compares them with the
--    real parts); the ring is drawn on the HIGHEST top under its footprint, so no part of it is buried.
function HazardGlue.surfaceY(x: number, z: number, F: any, Farm: any): number
	local g = F.GroundY
	local k = Farm.slotAt(x, z, F)
	if k ~= nil then
		local lx, lz = Farm.toLocal(k, x, z, F)
		if math.abs(lx) <= F.PadSize / 2 and math.abs(lz - F.PadLocalZ) <= F.PadSize / 2 then return g + 1 end
		if lz <= F.PorchDepth then return g + 0.4 end
		for f = 1, F.Fields do
			for t = 1, F.TilesPerField do
				local tx, tz = Farm.tileLocal(f, t, F)
				if math.abs(lx - tx) <= F.SoilSize / 2 and math.abs(lz - tz) <= F.SoilSize / 2 then
					return g + F.SoilHeight * 0.6
				end
			end
		end
		return g + 0.2 -- the bed
	end
	if math.abs(x) <= 3 and math.abs(z + 14) <= 3 then return g + 1 end -- the market pad
	if math.abs(x) <= F.MarketRadius and math.abs(z) <= F.MarketRadius then return g + 0.4 end -- the square
	return g
end

function HazardGlue.ringY(x: number, z: number, radius: number, F: any, Farm: any): number
	local top = HazardGlue.surfaceY(x, z, F, Farm)
	for i = 0, 15 do
		local a = i * math.pi / 8
		for _, f in { 0.5, 1 } do
			top = math.max(top, HazardGlue.surfaceY(x + math.cos(a) * radius * f, z + math.sin(a) * radius * f, F, Farm))
		end
	end
	return top
end

return HazardGlue
