-- Config.spec — pins DESIGN.md §3 and §8's numbers and the relations between them, so a silent retune
-- fails loudly. Every number here was measured against the whole difficulty curve (Appendix A); change
-- one only after re-running the pacing model (tests/Pacing.spec.luau) and the rig.
-- Run: luau tests/Config.spec.luau
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function approx(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= tol then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end

--================================================================ §8.1 geometry and movement
local S, M = Config.Station, Config.Move
eq(S.CellSize, 32, "CellSize 32 (the schedule was tuned at 32, M2)")
eq(S.WallThickness, 1, "WallThickness 1, inside the cell")
eq(S.CeilingHeight, 18, "CeilingHeight 18")
eq(S.HatchWidth, 8, "HatchWidth 8")
eq(S.HatchHeight, 10, "HatchHeight 10")
eq(S.HatchOpenRadius, 8, "HatchOpenRadius 8")
eq(S.HatchSeconds, 0.5, "HatchSeconds 0.5")
eq(S.PickupRadius, 5, "PickupRadius 5")
eq(S.PickupHeightWindow, 4, "the pickup height window is 4 studs")
eq(S.ItemWallClearance, 6, "items stand 6 studs off every wall")
eq(S.SalvageHeightMin, 3, "salvage floats 3..")
eq(S.SalvageHeightMax, 8, "..8 studs above the floor")
eq(S.SpliceRadius, 6, "SpliceRadius 6")
eq(S.ExtraDoorChance, 0.2, "ExtraDoorChance 0.2 (M2)")
eq(S.RelayDepthFrac, 0.75, "RelayDepthFrac 0.75 (M2, M9)")
eq(M.AirWalkSpeed, 16, "air walk speed 16")
eq(M.VacWalkSpeed, 12, "vacuum walk speed 12")
eq(M.BootsStep, 1, "Mag-Boots +1 stud/s per rank")
eq(M.AirJumpHeight, 7.2, "air JumpHeight 7.2 (Roblox default)")
eq(M.VacJumpHeight, 1.8, "vacuum JumpHeight 1.8")
eq(M.VacGravityFactor, 0.2, "vacuum gravity 20 %")

local inner = S.CellSize / 2 - S.WallThickness
eq(inner, 15, "a module's half-interior is 15 studs")
truthy(S.PickupRadius < S.ItemWallClearance, "no pickup reaches through a wall (radius < clearance)")
truthy(S.SpliceRadius < inner, "the splice fires only inside the relay module (6 < 15)")
truthy(S.HatchWidth < S.CellSize - 2 * S.ItemWallClearance, "a hatch fits beside the item square")
-- Roblox launches at sqrt(2 g JumpHeight); under g' = 0.2 g the apex is JumpHeight / 0.2
local apex = M.VacJumpHeight / M.VacGravityFactor
approx(apex, 9, 1e-9, "the vacuum hop's apex is 9 studs")
truthy(S.CeilingHeight >= apex + 5 + 4, "the ceiling is above the hop's apex plus an avatar plus 4 studs")
truthy(S.SalvageHeightMax - S.StandHeight <= S.PickupHeightWindow + apex, "the highest salvage is reachable with one hop")
truthy(S.SalvageHeightMin - S.StandHeight <= S.PickupHeightWindow, "the lowest salvage is walked into")
truthy(M.VacWalkSpeed + M.BootsStep * Config.Upgrades.Catalog.boots.max <= M.AirWalkSpeed,
	"Mag-Boots stop at air speed: vacuum is never faster than air")

--================================================================ §8.2 air
local A = Config.Air
eq(A.TankBase, 20, "TankBase 20 (M2's strongest lever)")
eq(A.TankStep, 5, "+5 s per Air Tank rank")
eq(A.RefillSeconds, 2, "RefillSeconds 2")
eq(A.GraceSeconds, 5, "GraceSeconds 5")
eq(A.CanisterSeconds, 10, "CanisterSeconds 10")
eq(A.CreditSeconds, 1, "CreditSeconds 1: a replication stall up to 1 s is never paid twice (REVIEW-1 finding 1)")
eq(A.LowO2Seconds, 10, "LowO2Seconds 10")
eq(A.TankBase + A.TankStep * Config.Upgrades.Catalog.tank.max, 40, "the tank tops out at 40 s")
truthy(A.LowO2Seconds < A.TankBase, "a full base tank is above the hazard floor")
-- five seconds covers crossing one vacuum module back to air at 12 studs/s
truthy(A.GraceSeconds > S.CellSize / M.VacWalkSpeed, "the grace covers one vacuum module at vacuum speed")

--================================================================ §8.3 signal, splice, transit
local R = Config.Run
eq(R.SpliceSeconds, 2, "SpliceSeconds 2")
eq(R.TransitSeconds, 3, "TransitSeconds 3")
eq(R.BoardingSeconds, 1, "BoardingSeconds 1")
eq(R.BlackoutBeatSeconds, 2.5, "BlackoutBeatSeconds 2.5")
eq(Config.Signal.MaxBars, 5, "five bars")
eq(Config.Brag.Sector, 30, "relay 30 is the Main Array")

--================================================================ §8.4 server and data
local Sv, D = Config.Server, Config.Data
eq(Sv.TickSeconds, 0.1, "ServerTickSeconds 0.1")
eq(Sv.StatePushSeconds, 0.2, "StatePushSeconds 0.2")
eq(Sv.TrustedSpeedFactor, 1.35, "TrustedSpeedFactor 1.35")
eq(Sv.TrustedBurstSeconds, 3, "TrustedBurstSeconds 3")
truthy(M.VacWalkSpeed * Sv.TrustedSpeedFactor >= M.AirWalkSpeed,
	"an honest walker still at 16 for a ping after a hatch into vacuum is not throttled (12 x 1.35 >= 16)")
eq(Sv.MaxPlayers, 8, "8 players")
truthy(Sv.Zones >= Sv.MaxPlayers, "at least one zone per player")
eq(Sv.ZoneSpacing, 400, "ZoneSpacing 400")
local reach = 6 * S.CellSize / 2 + 60
truthy(Sv.ZoneSpacing >= 2 * reach, "two zones' lights never reach each other (2 x 156 <= 400)")
truthy(Config.Hub.SizeX / 2 + 60 <= Sv.ZoneSpacing - reach, "the lifeboat's lights never reach zone 1")
eq(Sv.RespawnTime, 3, "RespawnTime 3")
eq(D.AutosaveSeconds, 20, "AutosaveSeconds 20")
eq(D.SessionLockSeconds, 45, "SessionLockSeconds 45")
truthy(D.SessionLockSeconds > 2 * D.AutosaveSeconds, "the lock outlives two autosaves")
eq(D.Store, "SignalLost_v1", "the profile store")
eq(Config.Board.Store, "SignalLost_Relays_v1", "the ordered store")
eq(Config.Board.WriteMinSeconds, 60, "at most one ordered write per 60 s per player")
eq(S.MaxPartsPerModule, 20, "at most 20 Parts per module")
eq(S.MaxPartsPerZone, 900, "at most 900 Parts per zone")

--================================================================ §3 the schedule
local Sch = Config.Schedule
local function row(k) return Config.scheduleFor(k) end
eq(row(1).n, 3, "sector 1 is 3x3")
eq(row(1).onboard, true, "sector 1 onboards")
eq(row(2).onboard, nil, "sector 2 does not")
eq(row(1).breach, 0.35, "sector 1 breach 0.35")
eq(row(1).reach, 1, "sector 1 reach 1")
eq(row(1).salvage, 2, "sector 1: 2 salvage")
eq(row(1).canisters, 1, "sector 1: 1 canister")
eq(row(3).n, 4, "sector 3 is 4x4")
eq(row(4).breach, 0.45, "sector 4 breach 0.45")
eq(row(5).breach, 0.55, "sector 5 breach 0.55")
eq(row(9).n, 4, "sector 9 still 4x4")
eq(row(10).n, 5, "sector 10 is 5x5")
eq(row(10).canisters, 2, "sector 10: 2 canisters")
eq(row(15).breach, 0.60, "sector 15 breach 0.60")
eq(row(16).breach, 0.65, "sector 16 breach 0.65")
eq(row(22).reach, 3, "sector 22 reach 3")
eq(row(23).n, 6, "sector 23 is 6x6")
approx(row(23).breach, 0.65, 1e-9, "sector 23 breach 0.650")
approx(row(30).breach, 0.95 - 0.30 * 0.97 ^ 7, 1e-12, "sector 30 breach 0.708")
eq(row(30).canisters, 2, "sector 30: 2 canisters")
eq(row(31).canisters, 1, "sector 31: 1 canister")
eq(row(31).reach, 5, "sector 31 reach 5")
eq(row(59).reach, 8, "sector 59 reach 8")
eq(row(71).reach, 10, "sector 71 reach 10")
eq(row(500).reach, 10, "reach caps at 10")
truthy(row(500).breach < 0.95 and row(10000).breach <= 0.95, "breach approaches 0.95 and never passes it")
eq(row(23).salvage, 5, "sector 23: 5 salvage")
truthy(type(Sch) == "table" and #Sch >= 7, "the schedule rows exist")

--================================================================ §9 economy
local E = Config.Economy
local function value(k) return E.ValueBase + E.ValuePerSector * (k - 1) end
local function bonus(k) return E.BonusBase + E.BonusPerSector * (k - 1) end
eq(value(1), 5, "value(1) = 5")
eq(value(30), 34, "value(30) = 34")
eq(bonus(1), 10, "bonus(1) = 10")
eq(bonus(30), 68, "bonus(30) = 68")
eq(E.KeepNumerator / E.KeepDenominator, 0.5, "keep 0.5")
local U = Config.Upgrades
eq(table.concat(U.Order, ","), "tank,boots", "two upgrades")
for _, id in U.Order do
	eq(table.concat(U.Catalog[id].prices, "/"), "120/300/600/1000", id .. " ladder 120/300/600/1000")
	eq(U.Catalog[id].max, 4, id .. " has 4 ranks")
end
local total = 0
for _, id in U.Order do for _, p in U.Catalog[id].prices do total += p end end
eq(total, 4040, "everything costs 4 040 salvage")

--================================================================ §5 hazards, §6 rest
local Hz = Config.Hazards
eq(Hz.IntervalMin, 55, "IntervalMin 55: one warning per 2.32-3.08 min (median 2.54) of play at k >= 5 on the real client path (REVIEW-1 finding 5)")
eq(Hz.IntervalMax, 85, "IntervalMax 85")
eq(Hz.FirstIntervalSeconds, 30, "first hazard after 30 s of eligible time (M7b)")
eq(Hz.ArrivalGraceSeconds, 6, "ArrivalGraceSeconds 6")
eq(Hz.WaitForStillSeconds, 15, "WaitForStillSeconds 15")
eq(Hz.StillSpeed, 4, "StillSpeed 4")
eq(Hz.LowO2Seconds, A.LowO2Seconds, "the hazards' air floor is the air config's")
eq(Config.Rest.IdleSeconds, 20, "idle rest after 20 s")
eq(Config.Rest.PendingSeconds, 7, "PendingSeconds 7")
eq(Config.Rest.AllowedIn.air, true, "rest in air modules")
eq(Config.Rest.AllowedIn.hub, true, "rest in the lifeboat")
eq(Config.Rest.AllowedIn.vacuum, nil, "never in vacuum")

--================================================================ the board
eq(Config.Board.PublicRows, 10, "public top 10")
eq(Config.Board.FriendsCap, 200, "friends capped at 200")
eq(Config.Board.PublicCacheSeconds, 60, "public cached 60 s")
eq(Config.Board.BudgetReserve, 20, "keep 20 GetAsync in the budget")
truthy(Config.Board.MaxMetric * 2e9 < 2 ^ 53, "every stored value is an exact integer")

print(string.format("Config: %d passed, %d failed", passed, failed))
assert(failed == 0, "Config tests failed")
