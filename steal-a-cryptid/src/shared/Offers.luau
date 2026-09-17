--!strict
-- Offers.luau - the three Sighting pedestals outside every lair. Pure logic.
--
-- DESIGN.md section 4. No mystery rolls: each pedestal shows the exact species, tier, rate and
-- price before anyone pays. P1 is a Common, P2 the player's own tier, P3 the next tier up; the
-- species is drawn uniformly within the tier. "rank" is the highest tier in the Journal (ever
-- owned), 0 before the first cryptid. While the tutorial step is 0, P1 is the Jackalope, so the
-- first purchase costs exactly the starting Essence.
--
-- Pure: cfg and an Rng stream come in as arguments; this file requires NOTHING.

local Offers = {}

function Offers.tierFor(cfg: any, slot: number, rank: number): number
	local top = #cfg.Camps
	if slot == 1 then return 1 end
	if slot == 2 then return math.max(1, rank) end
	return math.min(top, rank + 1)
end

-- One pedestal's species. The per-player stream is server-only (salted), so a rejoin cannot be
-- used to predict the next sighting; re-rolls are free regardless.
function Offers.draw(cfg: any, rng: any, slot: number, rank: number, tutorial: number): string
	if slot == 1 and tutorial == 0 then return "jackalope" end
	local tier = Offers.tierFor(cfg, slot, rank)
	local list = {}
	for _, s in cfg.Species do
		if s.tier == tier then table.insert(list, s.id) end
	end
	return list[rng:below(#list)]
end

function Offers.initial(cfg: any, rng: any, rank: number, tutorial: number): { string }
	local out = {}
	for slot = 1, cfg.Offers.Pedestals do
		out[slot] = Offers.draw(cfg, rng, slot, rank, tutorial)
	end
	return out
end

-- A free re-roll of every pedestal. P1 is excluded while the tutorial Jackalope holds it; an empty
-- pedestal (a purchase still being delivered) stays empty and refills on delivery.
function Offers.reroll(cfg: any, rng: any, offers: { string }, rank: number, tutorial: number): { string }
	local out = table.clone(offers)
	for slot = 1, cfg.Offers.Pedestals do
		if out[slot] ~= "" and not (slot == 1 and tutorial == 0) then
			out[slot] = Offers.draw(cfg, rng, slot, rank, tutorial)
		end
	end
	return out
end

function Offers.canReroll(cfg: any, lastAt: number?, now: number): (boolean, number)
	if lastAt == nil then return true, 0 end
	local left = cfg.Offers.RerollCooldownSeconds - (now - lastAt)
	if left <= 0 then return true, 0 end
	return false, math.ceil(left)
end

-- When the rank rises, P2 and P3 redraw at once so the next tier's goal shows immediately.
function Offers.onRankChange(cfg: any, rng: any, offers: { string }, oldRank: number, newRank: number, tutorial: number): { string }
	local out = table.clone(offers)
	if newRank <= oldRank then return out end
	for slot = 2, cfg.Offers.Pedestals do
		if out[slot] ~= "" then
			out[slot] = Offers.draw(cfg, rng, slot, newRank, tutorial)
		end
	end
	return out
end

-- One stream per player: (sessionSalt * 7 + (userId % 999983) * 104729) % 2147483647.
function Offers.seed(_cfg: any, salt: number, userId: number): number
	return (salt * 7 + (math.floor(userId) % 999983) * 104729) % 2147483647
end

return Offers
