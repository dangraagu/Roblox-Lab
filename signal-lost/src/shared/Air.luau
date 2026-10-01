--!strict
-- Air.luau — the suit's AIR, hypoxia and the blackout (DESIGN.md §2.3, §2.6). PURE, requires nothing.
--
-- AIR is a number of seconds, capped at the tank. In a vacuum module it drains 1 per second; in an air
-- module it refills to full in RefillSeconds whatever the tank. At 0 the player is hypoxic; GraceSeconds
-- of hypoxia is a blackout. Reaching air, or taking a canister, ends hypoxia at once. The server ticks it
-- with dt from task.wait's return value (the emulator's clock is virtual), and a NaN, negative, zero or
-- infinite dt changes nothing.
--
-- Nothing here drains outside vacuum and nothing accrues with time: rest in air pauses no number (§6).

local Air = {}

function Air.tankFor(cfg: any, rank: number?): number
	local r = math.clamp(math.floor(tonumber(rank) or 0), 0, cfg.Upgrades.Catalog.tank.max)
	return cfg.Air.TankBase + cfg.Air.TankStep * r
end

function Air.new(_cfg: any, tank: number): any
	return { air = tank, tank = tank, hypoxia = 0, hypoxic = false, blackedOut = false }
end

local function finite(v: number): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- One tick. Returns a list of events: "hypoxic" (the air ran out), "recovered" (hypoxia ended in air),
-- "blackout" (the grace ran out; reported once).
function Air.step(cfg: any, s: any, dt: number, vacuum: boolean): { string }
	local events = {}
	if s.blackedOut or not finite(dt) or dt <= 0 then
		return events
	end
	if vacuum then
		s.air -= dt
		if s.air < 0 then
			s.hypoxia += -s.air
			s.air = 0
			if not s.hypoxic then
				s.hypoxic = true
				table.insert(events, "hypoxic")
			end
			if s.hypoxia >= cfg.Air.GraceSeconds - 1e-9 then
				s.blackedOut = true
				table.insert(events, "blackout")
			end
		end
	else
		if s.hypoxic then
			s.hypoxic = false
			s.hypoxia = 0
			table.insert(events, "recovered")
		end
		s.air = math.min(s.tank, s.air + s.tank / cfg.Air.RefillSeconds * dt)
	end
	return events
end

-- The vacuum seconds one server tick costs (REVIEW-1 finding 1, DESIGN.md §14). Charging only the module a tick
-- ENDED in let a client that writes its own position cross a whole vacuum module between two ticks almost free. So
-- a tick costs its time if it ended in vacuum, or the vacuum distance the TRUSTED path covered (Trust's vacStuds)
-- at the vacuum walk speed the server set, whichever is more. Time paid in this vacuum stretch while covering less
-- ground than that (standing, or a replication stall whose catch-up burst comes later) is kept as credit, at most
-- cfg.Air.CreditSeconds, and covers a later burst, so an honest stall is never paid twice; the credit ends with the
-- stretch. An honest walker (never faster than the server's speed) pays exactly what time-only charging paid.
function Air.vacuumCharge(cfg: any, s: any, dt: number, endsInVacuum: boolean, vacStuds: number?, vacSpeed: number?): number
	if not finite(dt) or dt <= 0 then
		return 0
	end
	local a = if endsInVacuum then dt else 0
	local b = 0
	if type(vacStuds) == "number" and finite(vacStuds) and vacStuds > 0
		and type(vacSpeed) == "number" and finite(vacSpeed) and vacSpeed > 0 then
		b = vacStuds / vacSpeed
	end
	local credit = s.credit or 0
	local charge = a
	if b > a then
		local used = math.min(credit, b - a)
		credit -= used
		charge = b - used
	else
		credit = math.min(cfg.Air.CreditSeconds, credit + (a - b))
	end
	s.credit = if endsInVacuum then credit else 0
	return charge
end

-- A canister in reach. Taken (true) only when it helps: below a full tank, or hypoxic. At a full tank it
-- stays where it is and the HUD says so.
function Air.canister(cfg: any, s: any): boolean
	if s.blackedOut then return false end
	if s.air >= s.tank - 1e-9 and not s.hypoxic then
		return false
	end
	s.air = math.min(s.tank, s.air + cfg.Air.CanisterSeconds)
	s.hypoxic = false
	s.hypoxia = 0
	return true
end

function Air.fraction(s: any): number
	if s.tank <= 0 then return 0 end
	return math.clamp(s.air / s.tank, 0, 1)
end

function Air.graceLeft(cfg: any, s: any): number
	return math.max(0, cfg.Air.GraceSeconds - s.hypoxia)
end

-- May a hazard's clock run for this player (§5.1 adaptation 1)? In a vacuum module, in a band that has
-- hazards, after the sector's first ArrivalGraceSeconds, while AIR >= LowO2Seconds. Rest is the caller's
-- (it only exists in air, where this is false anyway).
function Air.hazardEligible(cfg: any, vacuum: boolean, bandHasHazards: boolean, secondsInSector: number?, air: number): boolean
	if not vacuum or not bandHasHazards then return false end
	if type(secondsInSector) ~= "number" or secondsInSector < cfg.Hazards.ArrivalGraceSeconds - 1e-9 then return false end
	if type(air) ~= "number" or air < cfg.Hazards.LowO2Seconds - 1e-9 then return false end
	return true
end

return Air
