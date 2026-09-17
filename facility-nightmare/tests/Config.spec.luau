-- Config.spec — the numbers DESIGN.md §5 chose from measurements, pinned, plus the relations
-- between them that the design's reasoning depends on. A retune that breaks a relation (a flicker
-- longer than the smallest measured front step, a pickup radius that reaches through a wall) fails
-- here instead of in a playtest.
-- Run: luau tests/Config.spec.luau
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

-- §5.1 movement and geometry
local M, F = Config.Movement, Config.Facility
eq(M.WalkSpeed, 16, "WalkSpeed")
eq(M.SprintSpeed, 24, "SprintSpeed")
eq(M.StaminaSeconds, 4, "StaminaSeconds")
eq(M.StaminaRegenSeconds, 8, "StaminaRegenSeconds")
eq(F.CellSize, 28, "CellSize")
eq(F.WallThickness, 1, "WallThickness")
eq(F.CeilingHeight, 14, "CeilingHeight")
eq(F.DoorWidth, 6, "DoorWidth")
eq(F.DoorHeight, 9, "DoorHeight")
eq(F.DoorOpenSeconds, 0.5, "DoorOpenSeconds")
eq(F.DoorOpenRadius, 8, "DoorOpenRadius")
eq(F.PickupRadius, 5, "PickupRadius")
eq(F.ItemWallClearance, 6, "items sit at least 6 studs from walls")
eq(F.ExtraDoorChance, 0.2, "ExtraDoorChance (the whole curve was measured at 0.2)")
eq(F.OnboardFuseMaxDistance, 2, "OnboardFuseMaxDistance")
eq(F.PickupDetourSeconds, 0.9, "model pickup detour (Appendix A)")
eq(F.RoomLightRange, 26, "RoomLightRange")
eq(F.MaxPartsPerRoom, 20, "MaxPartsPerRoom")
eq(F.MaxDoorLeavesPerFloor, 40, "door leaves per floor")
eq(F.MaxPartsPerZone, 600, "Parts per zone cap")
truthy(F.PickupRadius < F.ItemWallClearance, "a pickup can never reach through a wall")
truthy(F.DoorOpenRadius / M.WalkSpeed <= F.DoorOpenSeconds + 1e-9,
	"a walker reaches the doorway no earlier than the tween finishes")

-- §3 schedule
local function shapeAt(k)
	for _, row in F.Schedule do
		if k <= row.upTo then return row end
	end
	return nil
end
for _, c in { { 1, 4, 3, 2 }, { 3, 4, 3, 2 }, { 4, 5, 4, 2 }, { 8, 5, 4, 2 }, { 9, 5, 5, 1 }, { 1000, 5, 5, 1 } } do
	local row = shapeAt(c[1])
	truthy(row ~= nil, "schedule covers sublevel " .. c[1])
	if row then
		eq(row.grid, c[2], "grid at sublevel " .. c[1])
		eq(row.fuses, c[3], "fuses at sublevel " .. c[1])
		eq(row.cells, c[4], "cells at sublevel " .. c[1])
	end
end

-- §5.2 front
local Fr = Config.Front
eq(Fr.LeadSteps, 2, "LeadSteps")
eq(Fr.SlackStart, 2, "slack S1")
eq(Fr.SlackMin, 1, "slack Smin")
eq(Fr.SlackK, 4, "slack K")
eq(Fr.SlackExponent, 1, "slack e")
eq(Fr.FlickerSeconds, 2, "FlickerSeconds")
truthy(Fr.FlickerSeconds < 2.34, "flicker is shorter than the smallest measured step (M6: 2.34 s)")
eq(Fr.FlickerToggleSeconds, 0.2, "10 Brightness changes over the 2 s flicker")
eq(Fr.ExitExtraRings, 1, "an unpowered elevator room dies one ring after the farthest ring (REVIEW-1 B3)")

-- §5.3 survival
eq(Config.Battery.CapSeconds, 45, "battery cap")
eq(Config.Battery.CellSeconds, 15, "cell")
eq(Config.Exposure.GraceSeconds, 4, "grace")
eq(Config.Exposure.RecoverPerSecond, 1, "recover")
eq(Config.SecondWind.BatterySeconds, 10, "Second Wind battery")

-- §5.4 economy and perks
eq(Config.Economy.PayBase, 10, "pay base")
eq(Config.Economy.PayPerSublevel, 5, "pay per sublevel")
eq(Config.Economy.DeathKeepPercent, 25, "death keep")
local P = Config.Perks.Catalog
local total = 0
for _, id in Config.Perks.Order do
	local p = P[id]
	truthy(p ~= nil, "perk " .. id .. " is in the catalog")
	if p then
		eq(#p.prices, p.max, id .. " has one price per rank")
		for _, pr in p.prices do total += pr end
	end
end
eq(#Config.Perks.Order, 5, "five perks")
eq(total, 970, "everything costs 970 Essence (§5.4)")
eq(P.deepCell.per, 10, "Deep Cell +10 s per rank")
eq(P.nightEyes.per, 1, "Night Eyes +1 s per rank")
eq(P.marathon.per, 1, "Marathon +1 s per rank")
eq(P.soulAnchor.per, 10, "Soul Anchor +10 points per rank")
eq(P.secondWind.max, 1, "Second Wind has one rank")
eq(P.secondWind.prices[1], 150, "Second Wind costs 150")
eq(P.deepCell.prices[1] .. "/" .. P.deepCell.prices[2] .. "/" .. P.deepCell.prices[3], "25/60/120", "rank ladder")

-- §5.5 pacing / server / data
local R = Config.Run
eq(R.ServerTickSeconds, 0.1, "tick")
eq(R.StatePushSeconds, 0.2, "state push")
eq(R.BoardingSeconds, 1.5, "boarding")
eq(R.RideSeconds, 4, "ride")
eq(R.DeathBeatSeconds, 2.5, "death beat")
eq(R.TrustedSpeedFactor, 1.35, "trusted speed factor")
eq(R.TrustedBurstSeconds, 3, "trusted burst")
eq(Config.Apparition.HideRadius, 12, "apparition hide radius")
eq(Config.Apparition.HideAngle, 60, "apparition hide angle")
eq(Config.Apparition.MinVisibleSeconds, 0.5, "apparition min visible")
eq(Config.Apparition.LifetimeSeconds, 10, "apparition lifetime")
eq(Config.Server.MinZones, 8, "zone pool floor")
eq(Config.Server.ZoneSpacing, 400, "zone spacing")
eq(Config.Server.RespawnTime, 3, "respawn time")
eq(Config.Data.Store, "FacilityNightmare_v1", "store name")
eq(Config.Data.AutosaveSeconds, 20, "autosave")
eq(Config.Data.SessionLockSeconds, 45, "session lock")
truthy(Config.Data.SessionLockSeconds > 2 * Config.Data.AutosaveSeconds, "one failed autosave does not drop the lock")

-- A zone's reach must not meet its neighbour's (§5.5): half the 5x5 footprint + the ride car
-- offset + the longest light range, twice, inside the spacing.
do
	local reach = (5 * F.CellSize) / 2 + Config.Server.RideCarOffset + 60
	truthy(2 * reach < Config.Server.ZoneSpacing, "two zones' reach fits inside ZoneSpacing")
	truthy(Config.Hub.SizeX / 2 + 60 < Config.Server.ZoneSpacing - reach, "the hub's reach clears the first zone")
	truthy((Config.Hub.CameraMinZoomDistance or 0) >= 1, "the break-room camera's minimum zoom is past the PlayerModule's first-person threshold of 1 stud (REVIEW-1 B1)")
end

-- The hub: the core action inside 5 seconds.
do
	local H = Config.Hub
	eq(H.CarX - H.SpawnX, 16, "the car is 16 studs ahead of the spawn")
	truthy((H.CarX - H.SpawnX) / M.WalkSpeed <= 1.0 + 1e-9, "…one second at walk")
	eq(H.CarDepth, 8, "car interior 8 studs deep")
end

print(string.format("Config: %d passed, %d failed", passed, failed))
