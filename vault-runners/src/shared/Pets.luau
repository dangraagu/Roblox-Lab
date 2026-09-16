--!strict
-- Pets.luau — hub-stallen. ÉN sjeldenhet, kjøpes med bankede gems, én utstyrt om gangen.
--
-- v1 scope, deliberately: a pet is a row in a flat table with a cost and a multiplier. No
-- breeding, no trading, no eggs, no levels. The multiplier applies where RunState banks, so a
-- pet is worth exactly what you escape with.
--
-- OWNERSHIP IS NEVER INFERRED FROM SELECTION. `profile.equipped` is a preference the client can
-- ask to change; `profile.pets` is the ledger. The first cut of this file read the multiplier
-- straight off `equipped`, and the spec proved a profile that owned nothing at all could carry
-- a 1.65x Crownwyrm. Both `equip` and `multiplier` check the ledger now, so neither a hacked
-- remote nor a half-restored save can pay a bonus nobody bought.

local Pets = {}

function Pets.list(cfg: any): any
	return cfg.Pets.List
end

function Pets.byId(cfg: any, id: string?): any
	if id == nil then return nil end
	for _, p in ipairs(cfg.Pets.List) do
		if p.id == id then return p end
	end
	return nil
end

function Pets.owns(profile: any, id: string?): boolean
	if id == nil then return false end
	return (profile.pets ~= nil and profile.pets[id] == true)
end

function Pets.ownedCount(profile: any): number
	local n = 0
	if type(profile.pets) == "table" then
		for _, v in pairs(profile.pets) do if v then n += 1 end end
	end
	return n
end

function Pets.canBuy(cfg: any, profile: any, id: string?): (boolean, string?)
	local pet = Pets.byId(cfg, id)
	if not pet then return false, "unknown" end
	if Pets.owns(profile, id) then return false, "owned" end
	if (profile.gems or 0) < pet.cost then return false, "poor" end
	return true, nil
end

function Pets.buy(cfg: any, profile: any, id: string?): any
	local ok, why = Pets.canBuy(cfg, profile, id)
	if not ok then return { ok = false, reason = why } end
	local pet = Pets.byId(cfg, id)
	profile.gems -= pet.cost
	profile.pets = profile.pets or {}
	profile.pets[pet.id] = true
	return { ok = true, reason = "bought", cost = pet.cost, pet = pet }
end

function Pets.equip(cfg: any, profile: any, id: string?): any
	if id == nil then
		profile.equipped = nil
		return { ok = true, reason = "unequipped" }
	end
	local pet = Pets.byId(cfg, id)
	if not pet then return { ok = false, reason = "unknown" } end
	if not Pets.owns(profile, pet.id) then return { ok = false, reason = "unowned" } end
	profile.equipped = pet.id
	return { ok = true, reason = "equipped" }
end

-- The equipped pet's multiplier, or exactly 1 if the slot is empty, holds an id that is not a
-- pet, or holds a pet this profile does not own.
function Pets.multiplier(cfg: any, profile: any): number
	local id = profile.equipped
	if not Pets.owns(profile, id) then return 1 end
	local pet = Pets.byId(cfg, id)
	if not pet then return 1 end
	return math.max(1, pet.mult)
end

return Pets
