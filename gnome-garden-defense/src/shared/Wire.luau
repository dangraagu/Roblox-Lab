--!strict
-- Wire.luau: the GardenTick bug snapshot, packed as text. Pure, no Roblox globals (tests/Wire.spec.luau).
--
-- "id,kind,s,hp;" per bug: kind as a small code (Config.Bugs' names in alphabetical order, so the server and
-- the client derive the same codes from the same Config), s (studs along the path) to 0.1, health to the
-- percent and never 0 while the bug lives. ~16 bytes a bug instead of ~40 as a table of doubles.

local Wire = {}

local function codes(cfg: any): ({ [string]: number }, { string })
	local names = {}
	for name in cfg.Bugs do table.insert(names, name) end
	table.sort(names)
	local byName = {}
	for i, name in names do byName[name] = i end
	return byName, names
end

-- bugs: { { id, kind, s, hp, maxHp } } (the Garden's own bug records)
function Wire.packBugs(cfg: any, bugs: { any }): string
	local byName = codes(cfg)
	local parts = table.create(#bugs)
	for i, b in bugs do
		local frac = if b.maxHp > 0 then b.hp / b.maxHp else 0
		local pct = math.clamp(math.floor(frac * 100 + 0.5), 0, 100)
		if b.hp > 0 and pct < 1 then pct = 1 end
		parts[i] = string.format("%d,%d,%.1f,%d", b.id, byName[b.kind] or 0, math.floor(b.s * 10 + 0.5) / 10, pct)
	end
	return table.concat(parts, ";")
end

-- -> { { id, kind, s, hpFrac } }; anything malformed or with an unknown kind is dropped
function Wire.unpackBugs(cfg: any, text: any): { any }
	local out = {}
	if type(text) ~= "string" then return out end
	local _, names = codes(cfg)
	for entry in string.gmatch(text, "[^;]+") do
		local id, code, s, pct = string.match(entry, "^(%d+),(%d+),([%d%.]+),(%d+)$")
		local kind = code and names[tonumber(code) :: number]
		if id and kind then
			table.insert(out, { tonumber(id), kind, tonumber(s), (tonumber(pct) :: number) / 100 })
		end
	end
	return out
end

return Wire
