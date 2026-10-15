-- Wire.spec: the GardenTick bug snapshot, packed as text (DESIGN.md §3.7). Run: luau tests/Wire.spec.luau
--
-- Ten times a second the server sends the garden's owner every bug on the path. As a table of doubles that is
-- ~40 bytes a bug; as text ("id,kind,s,hp;") it is ~16. The client needs the position to 0.1 stud (bugs are
-- interpolated between ticks) and the health to the percent (the boss bar).

local Wire = require("../src/shared/Wire")
local Config = require("../src/shared/Config")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

do
	local bugs = {
		{ id = 1, kind = "aphid", s = 0, hp = 24, maxHp = 24 },
		{ id = 1234, kind = "queen", s = 123.456, hp = 250.5, maxHp = 1000 },
		{ id = 99999, kind = "mantis", s = 239.99, hp = 0.001, maxHp = 680 },
	}
	local text = Wire.packBugs(Config, bugs)
	eq(type(text), "string", "a snapshot packs to text")
	local back = Wire.unpackBugs(Config, text)
	eq(#back, 3, "and unpacks to the same number of bugs")
	eq(back[2][1], 1234, "ids survive")
	eq(back[2][2], "queen", "kinds survive")
	eq(back[2][3], 123.5, "positions to 0.1 stud")
	eq(back[2][4], 0.25, "health to the percent (25%)")
	eq(back[3][4], 0.01, "a nearly dead bug still shows a sliver (never 0 while alive)")
	eq(back[1][3], 0, "the hedge gap is s = 0")
	eq(#Wire.unpackBugs(Config, Wire.packBugs(Config, {})), 0, "an empty path packs and unpacks")
	-- every kind has a code, and the codes are unique
	local seen, missing = {}, {}
	for kind in Config.Bugs do
		local text1 = Wire.packBugs(Config, { { id = 7, kind = kind, s = 1, hp = 1, maxHp = 1 } })
		local b = Wire.unpackBugs(Config, text1)[1]
		if b == nil or b[2] ~= kind then table.insert(missing, kind) end
		local code = string.match(text1, "^%d+,(%d+),")
		if code and seen[code] then table.insert(missing, kind .. " shares code " .. code) end
		if code then seen[code] = true end
	end
	eq(table.concat(missing, ", "), "", "every bug kind round-trips with a unique code")
	-- garbage is dropped, not drawn
	eq(#Wire.unpackBugs(Config, "x,y,z;1,99,3,4;"), 0, "malformed or unknown entries are dropped")
	eq(#Wire.unpackBugs(Config, nil), 0, "a missing snapshot is an empty one")
end

do
	-- size: 35 bugs (the measured peak) at full detail
	local bugs = {}
	for i = 1, 35 do
		table.insert(bugs, { id = 10000 + i, kind = "beetle", s = 100 + i * 3.33, hp = 37.7, maxHp = 60 })
	end
	local text = Wire.packBugs(Config, bugs)
	print(string.format("Wire: 35 bugs pack to %d bytes (%.1f a bug); at 10 Hz that is %.1f KB/s", #text, #text / 35, #text * 10 / 1024))
	truthy(#text <= 35 * 20, "35 bugs pack to at most 20 bytes a bug (" .. #text .. " bytes)")
end

print(("Wire: %d passed, %d failed"):format(passed, failed))
