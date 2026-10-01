--!strict
-- Profile.luau — the saved document and what a load repairs (DESIGN.md §8.1). Pure, no requires.
--
-- One document per player, DataStore "StormGrow_v1", key "u_<userId>". String keys everywhere: tiles are
-- "<field>_<tile>", Almanac entries "<cropId>:<marks>". The session lock ({ token, lockUntil }) lives in
-- the STORED document only; the server's load/save transforms own it, so it is never part of the
-- in-memory profile and never replicates.

local Profile = {}

-- The version this game writes. A record with a HIGHER v was written by a newer version: this one must not write
-- it back (REVIEW-1 A4; Main.server plays it read-only), because normalize drops every crop, entry and field it
-- does not know.
Profile.VERSION = 1

function Profile.isNewer(raw: any): boolean
	return type(raw) == "table" and (tonumber(raw.v) or 1) > Profile.VERSION
end

local SAVED = { "v", "coins", "harvested", "fields", "unlocked", "selected", "tiles", "almanac", "almanacCount", "almanacAt", "harvests" }

function Profile.default(cfg: any): any
	return {
		v = Profile.VERSION,
		coins = cfg.StartCoins,
		harvested = 0,
		fields = 1,
		unlocked = 1,
		selected = cfg.Crops[1].id,
		tiles = {},
		almanac = {},
		almanacCount = 0,
		almanacAt = 0,
		harvests = 0,
	}
end

local function whole(x: any, lo: number, hi: number): number
	if type(x) ~= "number" or x ~= x then return lo end
	return math.clamp(math.floor(x), lo, hi)
end

-- (profile, fixes). Never raises; anything it cannot trust is repaired or dropped, and each repair is
-- described in `fixes` (the server logs them).
function Profile.normalize(raw: any, cfg: any, now: number): (any, { string })
	local fixes: { string } = {}
	local p = Profile.default(cfg)
	if raw == nil then return p, fixes end
	if type(raw) ~= "table" then
		table.insert(fixes, "record was not a table; loaded the default")
		return p, fixes
	end
	local F = cfg.Farm
	local byId, indexOf = {}, {}
	for i, c in cfg.Crops do
		byId[c.id] = c
		indexOf[c.id] = i
	end

	local function num(field: string, lo: number, hi: number)
		local v = raw[field]
		local w = whole(v, lo, hi)
		if v ~= nil and v ~= w then table.insert(fixes, field .. " " .. tostring(v) .. " -> " .. w) end
		return w
	end
	p.coins = num("coins", 0, 1e15)
	p.harvested = num("harvested", 0, 1e15)
	p.fields = num("fields", 1, F.Fields)
	p.unlocked = num("unlocked", 1, #cfg.Crops)
	p.harvests = num("harvests", 0, 1e12)
	p.almanacAt = num("almanacAt", 0, 1e11)

	local sel = raw.selected
	local si = if type(sel) == "string" then indexOf[sel] else nil
	if si == nil or si > p.unlocked then
		p.selected = cfg.Crops[p.unlocked].id
		if sel ~= nil then table.insert(fixes, "selected " .. tostring(sel) .. " -> " .. p.selected) end
	else
		p.selected = sel
	end

	if type(raw.tiles) == "table" then
		for key, t in raw.tiles do
			local f, i = nil, nil
			if type(key) == "string" then
				local fs, ts = string.match(key, "^(%d+)_(%d+)$")
				f, i = tonumber(fs), tonumber(ts)
			end
			if f == nil or i == nil or i < 1 or i > F.TilesPerField or f < 1 or f > F.Fields then
				table.insert(fixes, "tile key " .. tostring(key) .. " dropped")
			elseif f > p.fields then
				table.insert(fixes, "tile " .. key .. " is beyond the owned fields; dropped")
			elseif type(t) ~= "table" or type(t.c) ~= "string" or byId[t.c] == nil then
				table.insert(fixes, "tile " .. key .. " holds no known crop; cleared")
			else
				local at = if type(t.at) == "number" and t.at == t.at then t.at else now
				if at > now then
					table.insert(fixes, "tile " .. key .. " planted in the future; clamped")
					at = now
				end
				local m = t.m
				if type(m) ~= "number" or m < 0 or m > 7 or m % 1 ~= 0 then
					table.insert(fixes, "tile " .. key .. " marks " .. tostring(m) .. " cleared")
					m = 0
				end
				p.tiles[key] = { c = t.c, at = at, m = m }
			end
		end
	end

	if type(raw.almanac) == "table" then
		for key, at in raw.almanac do
			local c, m = nil, nil
			if type(key) == "string" then
				local cs, ms = string.match(key, "^([%a]+):(%d+)$")
				c, m = cs, tonumber(ms)
			end
			if c == nil or byId[c] == nil or m == nil or m < 1 or m > 7 then
				table.insert(fixes, "almanac key " .. tostring(key) .. " dropped")
			else
				p.almanac[key] = if type(at) == "number" then math.floor(at) else math.floor(now)
			end
		end
	end
	local count = 0
	for _ in p.almanac do count += 1 end
	if raw.almanacCount ~= nil and raw.almanacCount ~= count then
		table.insert(fixes, "almanacCount " .. tostring(raw.almanacCount) .. " -> " .. count)
	end
	p.almanacCount = count
	return p, fixes
end

-- A deep copy of the saved fields, so a tap during a queued write cannot change what is written.
function Profile.serialize(p: any): any
	local function copy(v: any): any
		if type(v) ~= "table" then return v end
		local out = {}
		for k, x in v do out[k] = copy(x) end
		return out
	end
	local doc = {}
	for _, k in SAVED do
		doc[k] = copy(p[k])
	end
	return doc
end

return Profile
