--!strict
-- DoorHazards.luau — the day's three fork hazards (DESIGN §8). Pure, no Roblox.
--
-- Adapted from labyrint-spill/src/shared/CellHazards.luau, the family's reviewed adaptation of the
-- +1 Jump Hazards template for a timed, shared maze. +1 Jump's template is NOT used here: it launches
-- a lane at the player from wherever the camera looks, on a random clock, and on a ranked shared
-- layout that would put luck into the time. What changed from CellHazards, and why:
--   1. WHERE comes from the day record (src/server/Dungeon.pickHazards, sent in a revealed cell's
--      payload), not hash01(level): a hash of a public number would let a client compute the cells,
--      which is a layout leak;
--   2. forks only (3+ open sides): the measured fix for rarity, and a fork is visibly a fork once
--      revealed, so a hazard tells nobody where the best route goes;
--   3. staggered slots on the RUN clock: slot k impacts at First + Slot * (k - 1) + Cycle * n, and
--      warning + debris fit inside a slot, so a run never meets two at once (labyrint allowed two);
--   4. the ring is RED (labyrint used blue because red means a lethal floor there; this game has none).
-- Unchanged: a telegraph of >= 2 s, ONE impact instant, a hit zone that is exactly the ring
-- (StrikeRadius + PlayerRadius, horizontal), a height cap (a jump is no dodge), and a knock that is
-- horizontal, away from the impact, capped, and costs about a second, never the run.
-- Vectors are plain { x, y, z } tables; the client renders and applies the knock to its own character.

local DoorHazards = {}

DoorHazards.CELL = 16 -- Config.Grid.Cell
DoorHazards.WALL = 2 -- Config.Grid.WallThick
DoorHazards.MIN_WARN_FLOOR = 2
DoorHazards.MIN_HIT_HEIGHT = 12

local function num(x: any): boolean
	return type(x) == "number" and x == x
end

function DoorHazards.validate(cfg: any): (boolean, string?)
	if type(cfg) ~= "table" then return false, "no hazard config" end
	for _, k in { "CellSize", "Count", "Cycle", "Slot", "First", "WarnSeconds", "MinWarnSeconds", "DebrisSeconds",
		"StrikeRadius", "PlayerRadius", "LaneWidth", "MaxHitHeight", "KnockSeconds", "KnockPush",
		"MaxKnockDisplacement", "NearRadius" } do
		if not num(cfg[k]) then return false, k .. " must be a number" end
	end
	if cfg.CellSize ~= DoorHazards.CELL then return false, "CellSize must be the game's cell (16)" end
	if cfg.MinWarnSeconds < DoorHazards.MIN_WARN_FLOOR then return false, "MinWarnSeconds must be >= 2" end
	if cfg.WarnSeconds < cfg.MinWarnSeconds then return false, "WarnSeconds shorter than MinWarnSeconds" end
	if cfg.DebrisSeconds < 0 then return false, "DebrisSeconds must be >= 0" end
	if cfg.WarnSeconds + cfg.DebrisSeconds > cfg.Slot then
		return false, "warning + debris must fit in a slot, or two hazards could be live at once"
	end
	if cfg.Count < 1 or cfg.Count * cfg.Slot > cfg.Cycle then return false, "Count slots must fit in a cycle" end
	if cfg.First < cfg.WarnSeconds then return false, "the first warning must not start before the line" end
	if cfg.StrikeRadius <= 0 or cfg.PlayerRadius <= 0 or cfg.LaneWidth <= 0 then return false, "radii must be > 0" end
	local freeHalf = (cfg.CellSize - DoorHazards.WALL) / 2
	if cfg.StrikeRadius + cfg.PlayerRadius + cfg.LaneWidth + cfg.PlayerRadius > freeHalf + 1e-9 then
		return false, "the ring must leave a lane beside it inside the cell (a hazard can make you wait, never wall you off)"
	end
	if cfg.KnockSeconds < 0 or cfg.KnockPush < 0 then return false, "knock must be >= 0" end
	if cfg.KnockPush * cfg.KnockSeconds > cfg.MaxKnockDisplacement then
		return false, "KnockPush * KnockSeconds exceeds MaxKnockDisplacement"
	end
	if cfg.MaxHitHeight < DoorHazards.MIN_HIT_HEIGHT then
		return false, "MaxHitHeight must be >= 12 (a jump must never dodge an impact; stepping out of the ring does)"
	end
	if cfg.NearRadius <= cfg.StrikeRadius + cfg.PlayerRadius then return false, "NearRadius must reach past the ring" end
	return true, nil
end

function DoorHazards.ringRadius(cfg: any): number
	return cfg.StrikeRadius + cfg.PlayerRadius
end

function DoorHazards.impactTime(slot: number, n: number, cfg: any): number
	return cfg.First + cfg.Slot * (slot - 1) + cfg.Cycle * n
end

-- The first impact of `slot` at or after run-time t.
function DoorHazards.nextImpact(slot: number, t: number, cfg: any): number
	local first = DoorHazards.impactTime(slot, 0, cfg)
	if t <= first then return first end
	return first + math.ceil((t - first) / cfg.Cycle) * cfg.Cycle
end

-- ("idle" | "warn" | "debris", progress 0..1) at run-time t.
function DoorHazards.stateAt(slot: number, t: number, cfg: any): (string, number)
	local first = DoorHazards.impactTime(slot, 0, cfg)
	if not num(t) or t < first - cfg.WarnSeconds then return "idle", 0 end
	local T = DoorHazards.nextImpact(slot, t, cfg)
	if T - t <= cfg.WarnSeconds then
		return "warn", math.clamp(1 - (T - t) / cfg.WarnSeconds, 0, 1)
	end
	local prev = T - cfg.Cycle
	if prev >= first - 1e-9 and t - prev < cfg.DebrisSeconds then
		return "debris", math.clamp((t - prev) / cfg.DebrisSeconds, 0, 1)
	end
	return "idle", 0
end

-- Slots warning or falling at run-time t (by construction never more than one).
function DoorHazards.activeSlots(t: number, cfg: any): { number }
	local out = {}
	for slot = 1, cfg.Count do
		if DoorHazards.stateAt(slot, t, cfg) ~= "idle" then table.insert(out, slot) end
	end
	return out
end

-- Impact times of `slot` in (t0, t1].
function DoorHazards.impactsBetween(slot: number, t0: number, t1: number, cfg: any): { number }
	local out = {}
	if not num(t0) or not num(t1) or t1 <= t0 then return out end
	local T = DoorHazards.nextImpact(slot, t0, cfg)
	if T <= t0 then T += cfg.Cycle end
	while T <= t1 do
		table.insert(out, T)
		T += cfg.Cycle
		if #out > 10000 then break end
	end
	return out
end

function DoorHazards.inZone(centre: any, pos: any, cfg: any): boolean
	local dx, dz = pos.x - centre.x, pos.z - centre.z
	local r = DoorHazards.ringRadius(cfg)
	return dx * dx + dz * dz <= r * r
end

-- Did an impact of `slot` at `centre` (the floor's top) land on a root at `pos` during (t0, t1]?
function DoorHazards.checkHit(slot: number, centre: any, t0: number, t1: number, pos: any, cfg: any): boolean
	if not DoorHazards.inZone(centre, pos, cfg) then return false end
	if (pos.y or 0) - (centre.y or 0) > cfg.MaxHitHeight then return false end
	return #DoorHazards.impactsBetween(slot, t0, t1, cfg) > 0
end

-- An impact in (t0, t1] within NearRadius that did NOT hit.
function DoorHazards.nearMiss(slot: number, centre: any, t0: number, t1: number, pos: any, cfg: any): boolean
	if DoorHazards.checkHit(slot, centre, t0, t1, pos, cfg) then return false end
	local dx, dz = pos.x - centre.x, pos.z - centre.z
	if dx * dx + dz * dz > cfg.NearRadius * cfg.NearRadius then return false end
	return #DoorHazards.impactsBetween(slot, t0, t1, cfg) > 0
end

-- (velocity, standSeconds): horizontal, away from the impact, never up.
function DoorHazards.knock(centre: any, pos: any, cfg: any): (any, number)
	local dx, dz = pos.x - centre.x, pos.z - centre.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.05 then
		dx, dz, len = 1, 0, 1
	end
	return { x = dx / len * cfg.KnockPush, y = 0, z = dz / len * cfg.KnockPush }, cfg.KnockSeconds
end

-- The cosmetic fixture for a band (stalactite, spore pod, crystal, ember bomb).
function DoorHazards.kindFor(band: number, cfg: any): string
	return cfg.Kinds[band] or cfg.Kinds[1]
end

return DoorHazards
