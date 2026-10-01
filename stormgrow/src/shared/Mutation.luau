--!strict
-- Mutation.luau — marks, variants, the strike tick and the Almanac (DESIGN.md §2.2). Pure, no requires.
--
-- A crop carries a set of marks as bits: 1 = Charged (storm), 2 = Frosted (frost), 4 = Prismatic
-- (rainbow). Marks never go away and never hurt a crop, and their values multiply.
--
-- strikeTick is the ONLY function in the game that adds a mark, and the server is its only caller: at its
-- own strike tick, on its own clock, with its own unseeded Random (DESIGN.md §8.2). No remote, click or
-- attribute can reach it. That is why the Almanac count is a leaderboard metric a script cannot inflate.
--
-- M is Config.Marks, W is Config.Weather, byId maps a crop id to its Config.Crops entry.

local Mutation = {}

local BIT_ORDER = { "storm", "frost", "rainbow" } -- bit 1, 2, 4

function Mutation.bitOf(kind: string, M: any): number
	return M[kind].bit
end

-- product of the multipliers of every mark the crop carries
function Mutation.mult(marks: number, M: any): number
	local v = 1
	for _, kind in BIT_ORDER do
		if bit32.band(marks, M[kind].bit) ~= 0 then
			v *= M[kind].mult
		end
	end
	return v
end

function Mutation.variant(marks: number, variants: any): string?
	if marks == 0 then return nil end
	return variants[marks]
end

function Mutation.emoji(marks: number, M: any): string
	local out = ""
	for _, kind in BIT_ORDER do
		if bit32.band(marks, M[kind].bit) ~= 0 then
			out ..= M[kind].emoji
		end
	end
	return out
end

-- The Almanac key: always a string (DataStore trap: sparse integer keys come back as strings).
function Mutation.key(cropId: string, marks: number): string
	return cropId .. ":" .. tostring(marks)
end

-- (cropId, marks) for a valid entry key ("pumpkin:5"), nil otherwise (plain and junk are not entries)
function Mutation.parseKey(key: string): (string?, number?)
	if type(key) ~= "string" then return nil, nil end
	local c, m = string.match(key, "^([%a]+):(%d+)$")
	local marks = tonumber(m)
	if c == nil or marks == nil or marks < 1 or marks > 7 then return nil, nil end
	return c, marks
end

-- all 56 entries, crop-major, marks 1..7
function Mutation.allKeys(crops: { any }): { string }
	local out = {}
	for _, c in crops do
		for m = 1, 7 do
			table.insert(out, Mutation.key(c.id, m))
		end
	end
	return out
end

-- "0/1" per entry in allKeys order: the HUD's Almanac grid reads this from one Player attribute
function Mutation.bits(almanac: { [string]: any }, crops: { any }): string
	local out = table.create(#crops * 7)
	for _, k in Mutation.allKeys(crops) do
		table.insert(out, if almanac[k] ~= nil then "1" else "0")
	end
	return table.concat(out)
end

function Mutation.count(almanac: { [string]: any }, crops: { any }): number
	local n = 0
	for _, k in Mutation.allKeys(crops) do
		if almanac[k] ~= nil then n += 1 end
	end
	return n
end

-- entries of this crop still to find (the seed panel's "📖 N to find")
function Mutation.missing(almanac: { [string]: any }, cropId: string): number
	local n = 0
	for m = 1, 7 do
		if almanac[Mutation.key(cropId, m)] == nil then n += 1 end
	end
	return n
end

-- Record a discovery. Returns true when it is a NEW entry. `t` is the server's clock; the tie-break time
-- is its whole second (DESIGN.md §7).
function Mutation.grant(p: any, cropId: string, marks: number, t: number): boolean
	if marks < 1 or marks > 7 then return false end
	local k = Mutation.key(cropId, marks)
	if p.almanac[k] ~= nil then return false end
	local sec = math.floor(t)
	p.almanac[k] = sec
	p.almanacCount = (p.almanacCount or 0) + 1
	p.almanacAt = sec
	return true
end

-- Tile keys "<field>_<tile>" in numeric order, so a strike tick draws in a stable order.
function Mutation.sortedKeys(tiles: { [string]: any }): { string }
	local keys = {}
	for k in tiles do table.insert(keys, k) end
	table.sort(keys, function(a: string, b: string): boolean
		local af, at = string.match(a, "^(%d+)_(%d+)$")
		local bf, bt = string.match(b, "^(%d+)_(%d+)$")
		local an, bn = tonumber(af), tonumber(bf)
		if an and bn and an ~= bn then return an < bn end
		local ai, bi = tonumber(at), tonumber(bt)
		if ai and bi and ai ~= bi then return ai < bi end
		return a < b
	end)
	return keys
end

-- One strike wave of `kind` at server second t. Every crop that is RIPE at t and LACKS the event's mark
-- takes it with the per-tick chance (Weather.perTick, inlined here so this file needs no require).
-- rand() in [0, 1) is drawn exactly once per eligible crop. Mutates the tiles; returns the strikes
-- { { key, crop, marks (after), gained } }.
function Mutation.strikeTick(tiles: { [string]: any }, kind: string, t: number, rand: () -> number, W: any, M: any, byId: { [string]: any }): { any }
	local e = W.Events[kind]
	local P = W.Chance[kind]
	local q = if P >= 1 then 1 else 1 - (1 - P) ^ (1 / (e.len / W.TickSeconds))
	local bit = M[kind].bit
	local struck = {}
	for _, key in Mutation.sortedKeys(tiles) do
		local tile = tiles[key]
		local crop = type(tile) == "table" and byId[tile.c] or nil
		if crop and type(tile.at) == "number" and type(tile.m) == "number"
			and t >= tile.at + crop.grow and bit32.band(tile.m, bit) == 0 then
			if rand() < q then
				tile.m = bit32.bor(tile.m, bit)
				table.insert(struck, { key = key, crop = tile.c, marks = tile.m, gained = bit })
			end
		end
	end
	return struck
end

return Mutation
