--!strict
-- City.luau — a city's layout from its seed, and the shelf geometry. PURE: the game's Config arrives as `cfg`
-- and the Rng module as an argument (a bare require("./X") is invalid in Roblox).
--
-- A shelf has six 60-degree slots around its plaza; slot 0 is shelf-local -Z, in front of the arrival pad.
-- District 1 always takes slot 0; districts 2-6 take slots 1-5 in an order drawn from the seed. Each district
-- draws one of three lot templates (rows, column, arc) and a mirror that swaps Homes and Workshops, so every
-- district has 3 Homes and 3 Workshops and every layout has the same lots and prices: a layout predicts nothing
-- (DESIGN 3.2, 10.3). 3^6 templates x 2^6 mirrors x 5! slot orders = 5 598 720 layouts.
--
-- The draws match design/model.py's layout() exactly (same LCG, same order: the slot shuffle, then per district
-- the template and the mirror), so the pacing model's geometry numbers carry over; the facade picks come after,
-- in a second pass, so they never shift the other draws.
--
-- The seed is SERVER-ONLY (the profile and ServerStorage.CityInfo). Spec: tests/City.spec.luau.

local City = {}

City.SLOTS = 6

-- Slot `slot` (0..5), (u along the slot's axis outward, v sideways) -> shelf-local x, z. model.py's toWorld.
function City.slotXZ(slot: number, u: number, v: number): (number, number)
	local a = math.rad(180 + 60 * slot)
	return u * math.sin(a) + v * math.cos(a), u * math.cos(a) - v * math.sin(a)
end

function City.layout(cfg: any, seed: number, Rng: any): any
	assert(type(seed) == "number" and seed == math.floor(seed) and seed >= 1 and seed <= cfg.Save.SeedMax,
		"City.layout: seed must be an integer 1..SeedMax")
	local r = Rng.new(seed * 7919 + 17)
	-- slots 1..5 for districts 2..6: a Fisher-Yates shuffle
	local slots = { 1, 2, 3, 4, 5 }
	for i = #slots, 2, -1 do
		local j = Rng.below(r, i)
		slots[i], slots[j] = slots[j], slots[i]
	end
	local slotOf = { [1] = 0 }
	for d = 2, 6 do slotOf[d] = slots[d - 1] end
	local order = cfg.Templates.Order
	local template, mirror = {}, {}
	local lots, byKey = {}, {}
	for d = 1, 6 do
		local name = order[Rng.below(r, #order)]
		local m = Rng.next(r) < 0.5
		template[d] = name
		mirror[d] = m
		for i, t in cfg.Templates[name] do
			local zone = t[3]
			if m then zone = if zone == "H" then "W" else "H" end
			local x, z = City.slotXZ(slotOf[d], t[1], t[2])
			local l = { key = d .. "_" .. i, d = d, i = i, slot = slotOf[d], u = t[1], v = t[2], x = x, z = z, zone = zone, facade = 1 }
			table.insert(lots, l)
			byKey[l.key] = l
		end
	end
	for _, l in lots do
		l.facade = Rng.below(r, 3)
	end
	return { seed = seed, slotOf = slotOf, template = template, mirror = mirror, lots = lots, byKey = byKey }
end

-- The sign post: PostInset studs from the lot's centre toward the shelf centre, along the slot's axis.
function City.postXZ(cfg: any, l: any): (number, number)
	return City.slotXZ(l.slot, l.u - cfg.Lots.PostInset, l.v)
end

-- A locked district's sign, on its slot's axis.
function City.signXZ(cfg: any, slot: number): (number, number)
	return City.slotXZ(slot, cfg.Shelf.SignU, 0)
end

-- The angle (radians) a lot faces: its local -Z toward the shelf centre.
function City.facing(l: any): number
	return math.rad(180 + 60 * l.slot)
end

--============================================================================ shelves in the world
-- Shelf k's centre on the ring, and its orientation: local -Z points at the ring's centre (CFrame.lookAt).
function City.shelfCentre(cfg: any, k: number): (number, number, number)
	local th = (k - 1) * math.rad(360 / cfg.World.Shelves)
	local R = cfg.World.RingRadius
	return math.sin(th) * R, math.cos(th) * R, th
end

function City.toWorld(cfg: any, k: number, lx: number, lz: number): (number, number)
	local cx, cz, th = City.shelfCentre(cfg, k)
	local c, s = math.cos(th), math.sin(th)
	return cx + lx * c + lz * s, cz - lx * s + lz * c
end

function City.toLocal(cfg: any, k: number, wx: number, wz: number): (number, number)
	local cx, cz, th = City.shelfCentre(cfg, k)
	local c, s = math.cos(th), math.sin(th)
	local dx, dz = wx - cx, wz - cz
	return dx * c - dz * s, dx * s + dz * c
end

-- Which shelf's rock is under (wx, wz), or nil over open sky.
function City.shelfAt(cfg: any, wx: number, wz: number): number?
	for k = 1, cfg.World.Shelves do
		local cx, cz = City.shelfCentre(cfg, k)
		if (wx - cx) ^ 2 + (wz - cz) ^ 2 <= cfg.World.ShelfRadius ^ 2 then return k end
	end
	return nil
end

-- (ok, err): 36 lots, string keys, 3 + 3 per district, no two lots overlapping, everything on the shelf.
function City.validate(cfg: any, L: any): (boolean, string?)
	if type(L) ~= "table" or type(L.lots) ~= "table" or #L.lots ~= 36 then return false, "need 36 lots" end
	local per = {}
	local h = cfg.Lots.Size / 2
	for _, l in L.lots do
		if type(l.key) ~= "string" then return false, "a lot key is not a string" end
		per[l.d] = per[l.d] or { H = 0, W = 0 }
		per[l.d][l.zone] = (per[l.d][l.zone] or 0) + 1
		local r = math.sqrt(l.x * l.x + l.z * l.z)
		if r + h * math.sqrt(2) > cfg.World.ShelfRadius then return false, l.key .. " leaves the shelf" end
		if r - h * math.sqrt(2) < cfg.Shelf.PlazaRadius then return false, l.key .. " reaches into the plaza" end
	end
	for d = 1, 6 do
		if per[d] == nil or per[d].H ~= 3 or per[d].W ~= 3 then return false, "district " .. d .. " is not 3 + 3" end
	end
	for i = 1, #L.lots do
		for j = i + 1, #L.lots do
			local a, b = L.lots[i], L.lots[j]
			if math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) < cfg.Lots.Size then return false, a.key .. " overlaps " .. b.key end
		end
	end
	return true, nil
end

return City
