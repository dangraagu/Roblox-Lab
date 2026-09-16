-- Pets — the hub stall. ONE rarity, buy with banked gems, equip one, it multiplies what you bank.
-- Run: luau tests/Pets.spec.luau
--
-- No breeding, no trading, no eggs: that is v1's scope, and the shape of this module is the
-- promise. A pet is a row in a flat table with a cost and a multiplier, and nothing else.
--
-- The trap this file is aimed at is on the repo's standing list: OWNERSHIP VS SELECTION. A
-- profile carries both `pets` (what you own) and `equipped` (what you picked), and the moment
-- anything reads the multiplier straight off `equipped` without checking `pets`, a client that
-- can set `equipped` gets a 1.65x pet for free.

local Config = require("../src/shared/Config")
local Pets = require("../src/shared/Pets")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function near(a, b, tol, msg)
	if type(a) == "number" and math.abs(a - b) <= (tol or 1e-9) then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want ~", tostring(b))
	end
end

local C = Config

local function profile(gems, owned, equipped)
	local pets = {}
	for _, id in ipairs(owned or {}) do pets[id] = true end
	return { gems = gems, totalBanked = 99999, pets = pets, equipped = equipped }
end

--============================================================================ the table itself

do
	local list = Pets.list(C)
	eq(#list, 8, "the stall sells eight Vault-Keepers")
	eq(C.Pets.Rarity, "Vault-Keeper", "and they are all one rarity")

	local ids, dupes = {}, 0
	local costsRise, multsRise = true, true
	for i, p in ipairs(list) do
		if ids[p.id] then dupes += 1 end
		ids[p.id] = true
		truthy(type(p.name) == "string" and #p.name > 0, "pet " .. i .. " has a name")
		truthy(p.cost > 0, "pet " .. i .. " costs something")
		truthy(p.mult >= 1, "pet " .. i .. " never makes a run worth less")
		if i > 1 then
			if p.cost <= list[i - 1].cost then costsRise = false end
			if p.mult <= list[i - 1].mult then multsRise = false end
		end
	end
	eq(dupes, 0, "no two pets share an id")
	truthy(costsRise, "the ladder costs strictly more as it climbs")
	truthy(multsRise, "and pays strictly more, so no pet is a trap purchase")

	eq(Pets.byId(C, "lockjaw").cost, 900, "byId finds a pet")
	eq(Pets.byId(C, "nosuchpet"), nil, "and returns nothing for an id that does not exist")
end

--============================================================================ buying

do
	local p = profile(1000)
	local ok, why = Pets.canBuy(C, p, "lockjaw")
	truthy(ok, "1000 gems buys the 900-gem pet")
	eq(why, nil, "with no complaint")

	local res = Pets.buy(C, p, "lockjaw")
	truthy(res.ok, "the buy goes through")
	eq(p.gems, 100, "and takes exactly the cost")
	truthy(Pets.owns(p, "lockjaw"), "the pet is owned")
	eq(Pets.ownedCount(p), 1, "one pet owned")
	eq(p.totalBanked, 99999, "buying does NOT reduce total banked — the vault unlocks are safe")
end

do -- exact change
	local p = profile(900)
	truthy(Pets.buy(C, p, "lockjaw").ok, "exactly the price is enough")
	eq(p.gems, 0, "and leaves you broke")
end

do -- one short
	local p = profile(899)
	local ok, why = Pets.canBuy(C, p, "lockjaw")
	falsy(ok, "one gem short is short")
	eq(why, "poor", "and it says so, rather than failing silently")
	local res = Pets.buy(C, p, "lockjaw")
	falsy(res.ok, "the buy is refused")
	eq(res.reason, "poor", "with the reason")
	eq(p.gems, 899, "and nothing is deducted")
	falsy(Pets.owns(p, "lockjaw"), "and nothing is granted")
end

do -- no double-buy
	local p = profile(5000, { "lockjaw" })
	local ok, why = Pets.canBuy(C, p, "lockjaw")
	falsy(ok, "you cannot buy a pet you already own")
	eq(why, "owned", "with the reason")
	local res = Pets.buy(C, p, "lockjaw")
	falsy(res.ok, "the second buy is refused")
	eq(p.gems, 5000, "and you are not charged twice")
end

do -- a made-up id from a hacked client
	local p = profile(10 ^ 6)
	local ok, why = Pets.canBuy(C, p, "megawyrm_9000")
	falsy(ok, "an id that is not on the stall cannot be bought")
	eq(why, "unknown", "with the reason")
	local res = Pets.buy(C, p, "megawyrm_9000")
	falsy(res.ok, "the buy is refused")
	eq(Pets.ownedCount(p), 0, "and nothing lands in the profile")
	eq(p.gems, 10 ^ 6, "and nothing is charged")
end

--============================================================================ equipping

do
	local p = profile(0, { "coppertail", "emberwing" })
	near(Pets.multiplier(C, p), 1, 1e-9, "with nothing equipped a run pays 1.00x")

	truthy(Pets.equip(C, p, "emberwing").ok, "equipping a pet you own works")
	eq(p.equipped, "emberwing", "and it sticks")
	near(Pets.multiplier(C, p), 1.24, 1e-9, "and the run now pays 1.24x")

	truthy(Pets.equip(C, p, "coppertail").ok, "swapping works")
	near(Pets.multiplier(C, p), 1.05, 1e-9, "to the OTHER pet's multiplier, not the best owned")

	local res = Pets.equip(C, p, nil)
	truthy(res.ok, "unequipping works")
	eq(p.equipped, nil, "and clears the slot")
	near(Pets.multiplier(C, p), 1, 1e-9, "back to 1.00x")
end

do -- OWNERSHIP VS SELECTION
	local hacked = profile(0, {}, "crownwyrm")   -- equipped set, nothing owned
	falsy(Pets.owns(hacked, "crownwyrm"), "an equipped id is NOT proof of ownership")
	near(Pets.multiplier(C, hacked), 1, 1e-9,
		"and an unowned equipped pet multiplies by exactly 1.00x")

	local res = Pets.equip(C, hacked, "crownwyrm")
	falsy(res.ok, "equipping a pet you do not own is refused")
	eq(res.reason, "unowned", "with the reason")

	local nonsense = profile(0, {}, "not_a_pet_at_all")
	near(Pets.multiplier(C, nonsense), 1, 1e-9, "an equipped id that is not a pet pays 1.00x")
end

do -- a profile fresh out of the DataStore, with nothing in it at all
	local blank = { gems = 0, totalBanked = 0 }
	near(Pets.multiplier(C, blank), 1, 1e-9, "a profile with no pets table still pays 1.00x")
	eq(Pets.ownedCount(blank), 0, "and owns nothing")
	falsy(Pets.owns(blank, "coppertail"), "and does not own a pet by accident")
end

--============================================================================ CONTROL

-- A change the suite must NOT notice: the display side of a pet. Names and emoji are what the
-- stall prints; costs and multipliers are what the economy runs on. If renaming a pet moves any
-- number below, something has started keying economics off a label.
do
	local relabelled = { Pets = { Rarity = C.Pets.Rarity, List = {},
		FollowDistance = C.Pets.FollowDistance, FollowHeight = C.Pets.FollowHeight } }
	for i, src in ipairs(C.Pets.List) do
		relabelled.Pets.List[i] = {
			id = src.id, cost = src.cost, mult = src.mult,
			name = "Pet " .. i, emoji = "⬛",
		}
	end

	local a = profile(1000)
	local b = profile(1000)
	eq(Pets.buy(C, a, "lockjaw").ok, Pets.buy(relabelled, b, "lockjaw").ok,
		"CONTROL: renaming a pet does not change whether it can be bought")
	eq(a.gems, b.gems, "CONTROL: nor the price paid")

	Pets.equip(C, a, "lockjaw")
	Pets.equip(relabelled, b, "lockjaw")
	near(Pets.multiplier(C, a), Pets.multiplier(relabelled, b), 1e-9,
		"CONTROL: nor the multiplier it pays")
end

print(string.format("Pets: %d passed, %d failed", passed, failed))
if failed > 0 then error("Pets tests failed", 0) end
