--!strict
-- Anomaly.luau — the procedural "is this hall clean, and if not, which anomaly?" roll.
-- Pure logic: takes an Rng + day + Config and returns a deterministic result, so the
-- whole roll is unit-testable in the luau CLI and reproducible per (player, pass).
--
-- Contract: exactly ONE anomaly per non-clean pass. Clean passes carry no anomalyId.

local Rng = require("./Rng")

export type Pass = { clean: boolean, anomalyId: string? }

local Anomaly = {}

-- Total catalog size.
function Anomaly.count(cfg: any): number
	return #cfg.Anomaly.Catalog
end

-- Look up a catalog entry by id (nil if unknown).
function Anomaly.byId(cfg: any, id: string)
	for _, entry in cfg.Anomaly.Catalog do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- How many catalog entries are in play at `day` (clamped to [1, #catalog]).
function Anomaly.poolSize(cfg: any, day: number): number
	local a = cfg.Anomaly
	local n = a.StartPool + math.floor((math.max(day, 1) - 1) * a.PoolPerDay)
	if n < 1 then
		n = 1
	end
	local total = #a.Catalog
	if n > total then
		n = total
	end
	return n
end

-- P(an anomaly is present) at `day`, clamped to [0, MaxChance].
function Anomaly.chance(cfg: any, day: number): number
	local a = cfg.Anomaly
	local c = a.BaseChance + (math.max(day, 1) - 1) * a.ChancePerDay
	if c < 0 then
		c = 0
	end
	if c > a.MaxChance then
		c = a.MaxChance
	end
	return c
end

-- Roll one pass. First draw decides clean vs anomaly; if anomaly, a second draw picks
-- which id from the day's active pool (the first poolSize catalog entries).
-- Exactly TWO draws on an anomalous pass, ONE on a clean pass.
--
-- The index MUST come from `Rng.below` (high bits), never `Rng.int` (low bits): the day-1
-- pool is 8 — a power of two — so the modulo path collapsed the choice onto the seed's
-- lowest 3 bits. Every real passSeed loses its low bits to float rounding (userId *
-- 2654435761 overflows 2^53), so every player drew the SAME anomaly on every pass forever.
function Anomaly.rollPass(self: Rng.Rng, cfg: any, day: number): Pass
	if Rng.next(self) >= Anomaly.chance(cfg, day) then
		return { clean = true }
	end
	local pool = Anomaly.poolSize(cfg, day)
	local idx = Rng.below(self, pool)
	return { clean = false, anomalyId = cfg.Anomaly.Catalog[idx].id }
end

return Anomaly
