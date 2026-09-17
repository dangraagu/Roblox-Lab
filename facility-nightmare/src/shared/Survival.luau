--!strict
-- Survival.luau — battery, exposure, stamina and Second Wind, one server tick at a time. PURE.
--
-- The server owns all of this and the client only asks (DESIGN.md §2.3). Each tick the server
-- works out whether the player's TRUSTED room is dark, reads the LATEST requested flashlight and
-- sprint state, and calls `step`. Nothing here reads a clock: `dt` is handed in, accumulated by
-- the server from `task.wait`'s return value, so the emulator's virtual clock drives it too.
--
-- Why toggling buys nothing: the battery drains only while the light is on, and exposure rises
-- only while it is off in the dark. A tick therefore splits between two costs and there is no
-- third state that costs neither.
--
-- Requires nothing.

local Survival = {}

-- A tick is compared against the grace with this much slack, so forty 0.1 s ticks (which sum to
-- 3.9999999999999996 in a double) are four seconds, as they are to a player.
local EPS = 1e-9

-- effects = { batteryCap, grace, staminaCap, secondWinds } — the run's perk snapshot.
function Survival.new(cfg: any, effects: any): any
	return {
		batteryCap = effects.batteryCap,
		battery = effects.batteryCap,
		grace = effects.grace,
		exposure = 0,
		staminaCap = effects.staminaCap,
		stamina = effects.staminaCap,
		secondWinds = effects.secondWinds or 0,
		lightOn = false,
		sprinting = false,
		exhausted = false,
		emptySaid = false,
		dead = false,
	}
end

local function validDt(dt: any): boolean
	return type(dt) == "number" and dt == dt and dt > 0 and dt < math.huge
end

-- input = { wantLight: boolean?, wantSprint: boolean?, sprintPressed: boolean?, dark: boolean }
-- Returns the events this tick produced: "batteryEmpty", "secondWind", "dead".
function Survival.step(cfg: any, s: any, input: any, dt: any): { string }
	local events = {}
	if s.dead or not validDt(dt) then
		return events
	end

	-- flashlight and battery
	local onFor = 0
	if input.wantLight and s.battery > 0 then
		onFor = math.min(s.battery, dt * cfg.Battery.DrainPerSecond) / cfg.Battery.DrainPerSecond
		s.battery = math.max(0, s.battery - dt * cfg.Battery.DrainPerSecond)
		s.lightOn = s.battery > 0
		if s.battery <= 0 then
			s.battery = 0
			if not s.emptySaid then
				s.emptySaid = true
				table.insert(events, "batteryEmpty")
			end
		end
	else
		s.lightOn = false
	end
	if s.battery > 0 then
		s.emptySaid = false
	end

	-- exposure
	if input.dark then
		local unlit = dt - onFor
		if unlit > 0 then
			s.exposure += unlit * cfg.Exposure.RisePerSecond
		end
		if s.exposure >= s.grace - EPS then
			if s.secondWinds > 0 then
				s.secondWinds -= 1
				s.exposure = 0
				s.battery = math.min(s.batteryCap, s.battery + cfg.SecondWind.BatterySeconds)
				table.insert(events, "secondWind")
			else
				s.exposure = s.grace
				s.dead = true
				s.lightOn = false
				table.insert(events, "dead")
				return events
			end
		end
	else
		s.exposure = math.max(0, s.exposure - dt * cfg.Exposure.RecoverPerSecond)
	end

	-- sprint and stamina. Emptying the bar EXHAUSTS the sprint until the request is released or
	-- pressed afresh: otherwise every refused tick refills a crumb that re-arms sprint on the next
	-- one, and a held Shift alternates 24/16 every tick (an average of 20 studs/s for ever).
	-- `sprintPressed` is a new press this tick. A phone's SPRINT is a tap, not a held key, so its
	-- release and its next press can land inside one tick; without this a tapper needed two taps
	-- for every sprint after the first.
	--
	-- A sprint tick costs its WHOLE dt: it moves the player dt at SprintSpeed. Starting one on a
	-- crumb (anything above zero) let a press on every tick buy a full 0.1 s at 24 studs/s with the
	-- 0.05 s one regen tick refilled, 20.03 studs/s for ever (REVIEW-1 A3). A request the bar can no
	-- longer fund is exhausted, exactly as an empty bar is, so a held key never flip-flops on a
	-- jittering tick either.
	if not input.wantSprint or input.sprintPressed then
		s.exhausted = false
	end
	if input.wantSprint and not s.exhausted and s.stamina < dt - EPS then
		s.exhausted = true
	end
	if input.wantSprint and not s.exhausted then
		s.sprinting = true
		s.stamina = math.max(0, s.stamina - dt)
		if s.stamina <= EPS then
			s.stamina = 0
			s.exhausted = true
		end
	else
		s.sprinting = false
		s.stamina = math.min(s.staminaCap, s.stamina + dt * s.staminaCap / cfg.Movement.StaminaRegenSeconds)
	end

	return events
end

-- A battery cell. Consumed whole below the cap; LEFT WHERE IT IS at a full battery, so a player
-- who walks over one with a full bar can come back for it.
function Survival.pickupCell(cfg: any, s: any): boolean
	if s.battery >= s.batteryCap then
		return false
	end
	s.battery = math.min(s.batteryCap, s.battery + cfg.Battery.CellSeconds)
	return true
end

function Survival.exposureFraction(s: any): number
	if s.grace <= 0 then return 1 end
	return math.clamp(s.exposure / s.grace, 0, 1)
end

-- A new sublevel's car doors open: the ride was a breather.
function Survival.arrive(s: any)
	s.exposure = 0
	s.lightOn = false
	s.sprinting = false
end

return Survival
