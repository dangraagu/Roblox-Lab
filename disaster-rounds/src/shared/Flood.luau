--!strict
-- Flood.luau - "Get above the red line." (DESIGN.md §2.5). Pure.
--
-- Three rises. Each is announced WarnSeconds ahead by a red translucent slab at the coming water height (and every
-- cell top below it tinted red: exactly the cells that will flood), then rises linearly over RiseSeconds from
-- StartUnder studs below the flooding level's top to OverTop studs over it. Times are seconds after the name.
-- A cell is flooded while the water is above its top (Zones.flooded); a hit needs the cell under the root flooded
-- for Hits.GroundGrace seconds in a row. Nothing about a later rise is published before its warning starts.

local Flood = {}

function Flood.plan(cfg: any): { any }
	local fc = cfg.Flood
	local lv = cfg.Island.LevelStuds
	local out = {}
	for k, level in fc.Levels do
		local warnAt = fc.WarnAt[k]
		local top = level * lv
		table.insert(out, {
			level = level,
			warnAt = warnAt,
			riseAt = warnAt + fc.WarnSeconds,
			riseEnd = warnAt + fc.WarnSeconds + fc.RiseSeconds,
			from = top - fc.StartUnder,
			to = top + fc.OverTop,
		})
	end
	return out
end

-- The water's height t seconds after the name.
function Flood.waterAt(cfg: any, plan: { any }, t: number): number
	local y = cfg.Island.SeaY
	for _, r in plan do
		if t < r.riseAt then return y end
		if t < r.riseEnd then
			return r.from + (r.to - r.from) * (t - r.riseAt) / (r.riseEnd - r.riseAt)
		end
		y = r.to
	end
	return y
end

-- The latest rise whose warning has started (nil before the first warning).
function Flood.currentRise(plan: { any }, t: number): number?
	local idx = nil
	for k, r in plan do
		if t >= r.warnAt - 1e-9 then idx = k end
	end
	return idx
end

-- Does the red tint cover a cell of this level for rise r? Exactly the cells whose top the rise ends above
-- (the rise covers its own level and everything under it; the spec checks this against Zones.flooded).
function Flood.warnedLevel(level: number, r: any): boolean
	return level <= r.level
end

-- The workspace.Round attributes the server publishes at time t: the current rise only, or nil before any warning.
function Flood.attributes(plan: { any }, t: number): any
	local k = Flood.currentRise(plan, t)
	if k == nil then return nil end
	local r = plan[k]
	return { WaterFrom = r.from, WaterTo = r.to, RiseAt = r.riseAt, RiseEnd = r.riseEnd, WarnLevel = r.level }
end

return Flood
