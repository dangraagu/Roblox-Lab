--!strict
-- Economy.luau — plant, harvest, unlock, select, buy a field (DESIGN.md §2.3, §2.4, §12.3).
-- Pure: the server passes its own profile table and Config; nothing here trusts a client.
--
-- Rules:
--   * one tap on a tile harvests a ripe crop (it sells on the spot, x the product of its marks) AND
--     replants the selected seed; a growing crop refuses with the time left;
--   * Radish seeds are free, so a player with 0 coins can always plant;
--   * crops unlock strictly in order, so the owned set is a COUNT (`unlocked`). Ownership is never
--     inferred from `selected` (checklist trap): a selection above `unlocked` plants the newest owned crop;
--   * if the selected seed is too dear, the tap plants the best crop you can afford and says so;
--   * every refusal returns the words the player sees (checklist: no silent no-ops).
-- Tile keys are strings "<field>_<tile>" (DataStore trap: never integer keys).

local Economy = {}

local function int(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
	return (if n < 0 then "-" else "") .. out
end

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Economy.cropIndex(crops: { any }, id: any): number?
	if type(id) ~= "string" then return nil end
	for i, c in crops do
		if c.id == id then return i end
	end
	return nil
end

-- (field, tile) for a valid key within the farm's size, else nil
function Economy.parseTileKey(key: any, farm: any): (number?, number?)
	if type(key) ~= "string" then return nil, nil end
	local f, t = string.match(key, "^(%d+)_(%d+)$")
	local field, tile = tonumber(f), tonumber(t)
	if field == nil or tile == nil then return nil, nil end
	if field < 1 or field > farm.Fields or tile < 1 or tile > farm.TilesPerField then return nil, nil end
	return field, tile
end

function Economy.tileKey(field: number, tile: number): string
	return tostring(field) .. "_" .. tostring(tile)
end

-- product of the multipliers of the marks (the same rule as Mutation.mult; kept local so this file
-- needs no require)
local function mult(marks: number, M: any): number
	local v = 1
	for _, kind in { "storm", "frost", "rainbow" } do
		if bit32.band(marks, M[kind].bit) ~= 0 then v *= M[kind].mult end
	end
	return v
end

function Economy.saleValue(cropId: string, marks: number, cfg: any): number
	local i = Economy.cropIndex(cfg.Crops, cropId)
	if i == nil then return 0 end
	return cfg.Crops[i].sell * mult(marks, cfg.Marks)
end

-- The crop index a tap plants: the selection when it is owned and affordable, else the best owned crop
-- that is affordable (Radish is free, so there always is one).
function Economy.plantChoice(p: any, cfg: any): number
	local crops = cfg.Crops
	local want = Economy.cropIndex(crops, p.selected) or 1
	if want > p.unlocked then want = p.unlocked end
	local i = want
	while i > 1 and p.coins < crops[i].seed do
		i -= 1
	end
	return i
end

function Economy.nextFieldPrice(p: any, cfg: any): number?
	if p.fields >= cfg.Farm.Fields then return nil end
	return cfg.Farm.FieldCosts[p.fields]
end

function Economy.nextCrop(p: any, cfg: any): any?
	return cfg.Crops[p.unlocked + 1]
end

-- One tap on tile `key` at server time `now`.
-- -> { ok = false, reason = "badKey" | "locked" | "growing", text }
-- -> { ok = true, harvest = { crop, marks, value }?, planted = cropId, fallback = { wanted, got }?, text? }
function Economy.tap(p: any, cfg: any, key: string, now: number): any
	local field = Economy.parseTileKey(key, cfg.Farm)
	if field == nil then
		return { ok = false, reason = "badKey", text = "That is not a tile of your farm" }
	end
	if field > p.fields then
		local text
		if field == p.fields + 1 then
			text = string.format("🧱 Field %d is locked: buy it in 🌱 Seeds for %s", field, int(cfg.Farm.FieldCosts[p.fields]))
		else
			text = string.format("🧱 Field %d opens after field %d", field, field - 1)
		end
		return { ok = false, reason = "locked", text = text }
	end

	local out: any = { ok = true }
	local tile = p.tiles[key]
	if tile ~= nil then
		local i = Economy.cropIndex(cfg.Crops, tile.c)
		local crop = if i then cfg.Crops[i] else nil
		if crop ~= nil and now < tile.at + crop.grow then
			return { ok = false, reason = "growing", text = crop.name .. " · Ripe in " .. clock(tile.at + crop.grow - now) }
		end
		local marks = if type(tile.m) == "number" then tile.m else 0
		local value = if crop then crop.sell * mult(marks, cfg.Marks) else 0
		p.coins += value
		p.harvested += value
		p.harvests = (p.harvests or 0) + 1
		p.tiles[key] = nil
		out.harvest = { crop = tile.c, marks = marks, value = value }
	end

	local idx = Economy.plantChoice(p, cfg)
	local crop = cfg.Crops[idx]
	local wantIdx = Economy.cropIndex(cfg.Crops, p.selected)
	if wantIdx ~= nil and wantIdx <= p.unlocked and wantIdx ~= idx then
		local wanted = cfg.Crops[wantIdx]
		out.fallback = { wanted = wanted.id, got = crop.id }
		out.text = string.format("%s costs %s, you have %s: planted a %s (%s) instead",
			wanted.name, int(wanted.seed), int(p.coins), crop.name, int(crop.seed))
	end
	p.coins -= crop.seed
	-- to the millisecond: 13 significant digits survive a DataStore's JSON round trip exactly (Economy.spec)
	p.tiles[key] = { c = crop.id, at = math.floor(now * 1000 + 0.5) / 1000, m = 0 }
	out.planted = crop.id
	return out
end

-- (ok, text)
function Economy.unlock(p: any, cfg: any): (boolean, string)
	local nextCrop = Economy.nextCrop(p, cfg)
	if nextCrop == nil then
		return false, "Every crop is unlocked"
	end
	local need = nextCrop.needHarvested or 0
	if p.harvested < need then
		return false, string.format("%s only grows in the Eye of the Storm: harvest %s to get there",
			nextCrop.name, int(need))
	end
	if p.coins < nextCrop.unlock then
		return false, string.format("Unlock %s for %s: you have %s", nextCrop.name, int(nextCrop.unlock), int(p.coins))
	end
	p.coins -= nextCrop.unlock
	p.unlocked += 1
	p.selected = nextCrop.id
	return true, string.format("%s %s unlocked", nextCrop.emoji, nextCrop.name)
end

-- (ok, text)
function Economy.select(p: any, cfg: any, id: any): (boolean, string)
	local i = Economy.cropIndex(cfg.Crops, id)
	if i == nil then
		return false, "That is not a crop"
	end
	if i > p.unlocked then
		local c = cfg.Crops[i]
		return false, string.format("Unlock %s first (%s)", c.name, int(c.unlock))
	end
	p.selected = cfg.Crops[i].id
	return true, cfg.Crops[i].emoji .. " " .. cfg.Crops[i].name .. " selected"
end

-- (ok, text)
function Economy.buyField(p: any, cfg: any): (boolean, string)
	local price = Economy.nextFieldPrice(p, cfg)
	if price == nil then
		return false, "All six fields are yours"
	end
	if p.coins < price then
		return false, string.format("Next field: %s: you have %s", int(price), int(p.coins))
	end
	p.coins -= price
	p.fields += 1
	return true, string.format("🧱 Field %d is yours: tap its tiles to plant", p.fields)
end

return Economy
