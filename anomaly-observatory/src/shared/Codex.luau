--!strict
-- Codex.luau — the "Field Guide" of anomalies the player has correctly caught.
-- A string-keyed set { [anomalyId] = true }. String keys are deliberate: DataStore JSON
-- turns sparse INTEGER keys into strings on round-trip, so string ids sidestep that trap
-- and load back unchanged.

local Codex = {}

export type Set = { [string]: boolean }

-- Mark an anomaly discovered. Returns whether it was NEWLY discovered (false if already
-- in the set). Mutates the set in place.
function Codex.discover(set: Set, id: string): boolean
	if set[id] then
		return false
	end
	set[id] = true
	return true
end

function Codex.has(set: Set, id: string): boolean
	return set[id] == true
end

-- Raw size of the persisted set — counts EVERY key, including ids that were renamed or
-- dropped from the catalog by a later version. Behaviour deliberately unchanged (existing
-- callers rely on it), but it is NOT safe for an "X / Y" HUD readout on a returning
-- player's profile: use `Codex.countKnown` for that.
function Codex.count(set: Set): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

-- Size of the set counting only ids the predicate still recognises (i.e. ids that are
-- still in the catalog). `isKnown(id)` should return true for a live catalog id.
-- This is what the HUD should show, so a profile carrying stale ids from an older catalog
-- can't report "27 / 24".
function Codex.countKnown(set: Set, isKnown: (string) -> boolean): number
	local n = 0
	for id in set do
		if isKnown(id) then
			n += 1
		end
	end
	return n
end

-- Fraction discovered, CLAMPED to [0, 1]. total<=0 yields 0 (avoids divide-by-zero).
-- Pass the optional `isKnown` predicate to ignore stale ids (see `countKnown`). Without it
-- the clamp is the only thing keeping a stale-id profile from reporting > 100%.
function Codex.completion(set: Set, total: number, isKnown: ((string) -> boolean)?): number
	if total <= 0 then
		return 0
	end
	local n = if isKnown then Codex.countKnown(set, isKnown) else Codex.count(set)
	local c = n / total
	if c > 1 then
		c = 1
	elseif c < 0 then
		c = 0
	end
	return c
end

return Codex
