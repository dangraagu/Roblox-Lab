-- EnvConfig.spec — the environment bands (DESIGN.md §4) and the rules that keep the art fair (§4.3), checked on the
-- real Config.Env and the real Dressing module. Run: luau tests/EnvConfig.spec.luau
local Config = require("../src/shared/Config")
local EnvBands = require("../src/shared/EnvBands")
local Dressing = require("../src/shared/Dressing")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local Env = Config.Env
local bands = Env.Bands

--================================================================ §4.1 the bands and what triggers them
do
	local ok, err = EnvBands.validate(bands)
	truthy(ok, "EnvBands.validate accepts Config.Env.Bands (" .. tostring(err) .. ")")
	eq(#bands, 7, "seven bands")
	local firsts = {}
	for _, b in bands do table.insert(firsts, tostring(b.first)) end
	eq(table.concat(firsts, "/"), "1/5/10/16/23/31/60", "bands start at sectors 1 / 5 / 10 / 16 / 23 / 31 / 60")
	local fields = { "id", "name", "first", "last", "from", "fade", "line", "grade", "palette", "kit", "weather", "critters", "exterior", "hazards" }
	for i, b in bands do
		for _, f in fields do
			truthy(b[f] ~= nil, b.id .. " defines " .. f)
		end
		eq(b.from, b.first - 1, b.id .. ": from = first sector - 1 (p units)")
		eq(b.fade, 1, b.id .. ": fade 1 (it blends in over the whole previous sector)")
		if i > 1 then eq(bands[i - 1].last, b.first - 1, bands[i - 1].id .. " ends where " .. b.id .. " begins") end
	end
	eq(bands[#bands].last, math.huge, "the last band never ends")
	-- the band NAME follows the integer sector; the blend follows p = (k - 1) + visited / n^2
	eq(Dressing.bandOf(Env, 4), 1, "sector 4 is the Docking Ring")
	eq(Dressing.bandOf(Env, 5), 2, "sector 5 is Hydroponics")
	eq(Dressing.bandOf(Env, 30), 5, "sector 30 (the Main Array) is the Array Spine")
	eq(Dressing.bandOf(Env, 31), 6, "sector 31 is the Deep")
	eq(Dressing.bandOf(Env, 1000), 7, "sector 1000 is the Echo")
	local _, j, t = EnvBands.locate(bands, Dressing.progress(4, 0, 16))
	eq(j, 2, "exploring sector 4: Hydroponics is blending in")
	truthy(t >= 0 and t < 0.01, "…from zero at its dock")
	local _, _, t2 = EnvBands.locate(bands, Dressing.progress(4, 16, 16))
	truthy(t2 > 0.99, "…to full once every module is open (" .. string.format("%.3f", t2) .. ")")
	local i5 = EnvBands.locate(bands, Dressing.progress(5, 1, 16))
	eq(i5, 2, "in sector 5 the grade is Hydroponics'")
end

--================================================================ hazards: one kind per band, none in the tutorial
do
	eq(#bands[1].hazards, 0, "the Docking Ring (the tutorial) has no hazards")
	local used = {}
	for i = 2, #bands do
		eq(#bands[i].hazards, 1, bands[i].id .. " has exactly one hazard kind")
		for _, k in bands[i].hazards do
			truthy(Config.Hazards.Kinds[k] ~= nil, bands[i].id .. "'s hazard " .. k .. " exists")
			truthy(used[k] == nil, k .. " belongs to one band only")
			used[k] = bands[i].id
		end
	end
	local n = 0
	for _ in Config.Hazards.Kinds do n += 1 end
	eq(n, #bands - 1, "every hazard kind is some band's")
end

--================================================================ §4.3 fairness: palettes, grades, hues
do
	for _, b in bands do
		local ok, why = Dressing.paletteOk(Env, b.palette)
		truthy(ok, b.id .. ": the palette returns 60-100 % of the server's light in linear terms (" .. tostring(why) .. ")")
		local okG, whyG = Dressing.gradeOk(b.grade)
		truthy(okG, b.id .. ": the grade never crushes the image (" .. tostring(whyG) .. ")")
	end
	local okL = Dressing.gradeOk(Env.Lifeboat.grade)
	truthy(okL, "the lifeboat's grade is fair too")
	-- the rules bite: a too-dark palette and a too-bright one fail
	local dark = table.clone(bands[6].palette)
	dark.wall = { 60, 64, 70 }
	eq((Dressing.paletteOk(Env, dark)), false, "a wall at ~20 % of the server's light is refused")
	local bright = table.clone(bands[1].palette)
	bright.floor = { 250, 250, 250 }
	eq((Dressing.paletteOk(Env, bright)), false, "a floor far brighter than the server's is refused")
	-- the four signal colours are themselves distinct
	local hues = {}
	for name, c in Config.SignalColors do hues[name] = Dressing.hue(c) end
	truthy(math.abs(hues.Salvage - hues.HatchVacuum) >= 30, "salvage amber and the red lamp are 30+ degrees apart")
	eq(Dressing.hueOk(Config, { 255, 170, 40 }), false, "an amber glow is refused (it would look like salvage)")
	eq(Dressing.hueOk(Config, { 60, 240, 100 }), false, "a green glow is refused (the air lamp)")
	eq(Dressing.hueOk(Config, { 255, 60, 50 }), false, "a red glow is refused (the vacuum lamp)")
	eq(Dressing.hueOk(Config, { 80, 220, 255 }), false, "a cyan glow is refused (a canister)")
	eq(Dressing.hueOk(Config, { 170, 110, 255 }), true, "violet is free")
	eq(Dressing.hueOk(Config, { 235, 240, 250 }), true, "a near-white glow has no hue to confuse")
	for _, b in bands do
		if b.critters.glow then
			truthy(Dressing.hueOk(Config, b.critters.color), b.id .. ": its glowing critters keep 30 degrees off every signal colour")
		end
		for _, piece in Dressing.KITS[b.kit] do
			if piece.glow then
				truthy(Dressing.hueOk(Config, piece.color), b.id .. ": glowing " .. piece.name .. " keeps 30 degrees off every signal colour")
			end
		end
	end
end

--================================================================ dressing a module: placement rules on many real layouts
do
	local S = Config.Station
	local half = S.CellSize / 2
	local inner = half - S.WallThickness
	local lim = inner - S.ItemWallClearance
	local worst, wallBad, doorBad, itemBad, keepBad, overlapBad, detBad, n = 0, 0, 0, 0, 0, 0, 0, 0
	local seed = 99
	local function r()
		seed = (1103515245 * seed + 12345) % 2147483648
		return seed / 2147483648
	end
	for _, b in bands do
		for trial = 1, 150 do
			local sides = {}
			for _, s in { "E", "W", "N", "S" } do sides[s] = r() < 0.5 end
			local keep = {}
			if trial % 3 == 0 then table.insert(keep, { x = -12, z = -12, r = 3.5 }) end -- a relay console
			if trial % 5 == 0 then table.insert(keep, { x = 0, z = 12, r = 3.5 }) end -- a dock console on an outer wall
			local id, k = 1 + math.floor(r() * 36), 1 + math.floor(r() * 80)
			local pieces = Dressing.build(Config, b.kit, id, k, sides, keep)
			local again = Dressing.build(Config, b.kit, id, k, sides, keep)
			if #again ~= #pieces then detBad += 1 end
			n += 1
			worst = math.max(worst, #pieces)
			for pi, p in pieces do
				local hx, hz = p.size[1] / 2, p.size[3] / 2
				local x0, x1, z0, z1 = p.pos[1] - hx, p.pos[1] + hx, p.pos[3] - hz, p.pos[3] + hz
				-- within 2.5 studs of a wall's inner face, and inside the module
				local e = 1e-6
				local inBand = (x0 >= inner - 2.5 - e and x1 <= inner + e and z0 >= -inner - e and z1 <= inner + e)
					or (x1 <= -inner + 2.5 + e and x0 >= -inner - e and z0 >= -inner - e and z1 <= inner + e)
					or (z0 >= inner - 2.5 - e and z1 <= inner + e and x0 >= -inner - e and x1 <= inner + e)
					or (z1 <= -inner + 2.5 + e and z0 >= -inner - e and x0 >= -inner - e and x1 <= inner + e)
				if not inBand then wallBad += 1 end
				-- off every doorway line by 4 studs (a hull): a wall with a hatch keeps |along| >= 4 + 4
				for s, open in sides do
					if open then
						local alongX = s == "N" or s == "S"
						local nearWall = if s == "E" then x1 > inner - 2.6 elseif s == "W" then x0 < -inner + 2.6
							elseif s == "N" then z1 > inner - 2.6 else z0 < -inner + 2.6
						if nearWall then
							local a0, a1 = if alongX then x0 else z0, if alongX then x1 else z1
							if a1 > -(S.HatchWidth / 2 + 4) + 1e-6 and a0 < S.HatchWidth / 2 + 4 - 1e-6 then doorBad += 1 end
						end
					end
				end
				-- never in the item square (|x|, |z| <= 9 at 0..10 studs up)
				if x1 > -lim and x0 < lim and z1 > -lim and z0 < lim and p.pos[2] - p.size[2] / 2 < 10 then itemBad += 1 end
				for _, kz in keep do
					local cx, cz = math.clamp(kz.x, x0, x1), math.clamp(kz.z, z0, z1)
					if (cx - kz.x) ^ 2 + (cz - kz.z) ^ 2 < kz.r * kz.r - 1e-6 then keepBad += 1 end
				end
				for qi = pi + 1, #pieces do
					local q = pieces[qi]
					local ox = math.min(x1, q.pos[1] + q.size[1] / 2) - math.max(x0, q.pos[1] - q.size[1] / 2)
					local oy = math.min(p.pos[2] + p.size[2] / 2, q.pos[2] + q.size[2] / 2) - math.max(p.pos[2] - p.size[2] / 2, q.pos[2] - q.size[2] / 2)
					local oz = math.min(z1, q.pos[3] + q.size[3] / 2) - math.max(z0, q.pos[3] - q.size[3] / 2)
					if ox > 0.05 and oy > 0.05 and oz > 0.05 then overlapBad += 1 end
				end
			end
		end
	end
	truthy(worst <= Config.Budget.MaxDressPartsPerModule, "at most " .. Config.Budget.MaxDressPartsPerModule .. " dressing parts per module (worst " .. worst .. ")")
	truthy(worst >= 4, "and a module does get dressed (worst " .. worst .. ")")
	eq(wallBad, 0, "every piece hugs a wall (within 2.5 studs of its inner face)")
	eq(doorBad, 0, "no piece within 4 studs of a doorway's line")
	eq(itemBad, 0, "no piece in the item volume")
	eq(keepBad, 0, "no piece on a console, the mast or the floor hatch")
	eq(overlapBad, 0, "no two pieces inside each other")
	eq(detBad, 0, "the same module in the same sector is dressed the same way every time")
	print(string.format("  dressed %d modules: worst %d pieces", n, worst))
end

--================================================================ foreshadowing: the next band's kit creeps in
do
	local counts = {}
	for k = 1, 4 do counts[k] = 0 end
	-- a module's kit is decided when it is first dressed, at the progress of that moment: the n-th module opened
	for k = 1, 4 do
		for id = 1, 400 do
			local bi = Dressing.roomBand(Env, EnvBands, k, id, 1 + id % 16, 16)
			if bi == 2 then counts[k] += 1 end
		end
	end
	eq(counts[1], 0, "sector 1: no farm dressing yet")
	truthy(counts[4] > 100 and counts[4] < 300, "sector 4, modules opened 1st..16th: some wear Hydroponics' kit (" .. counts[4] .. "/400)")
	local half = 0
	for id = 1, 400 do if Dressing.roomBand(Env, EnvBands, 4, id, 8, 16) == 2 then half += 1 end end
	truthy(half < counts[4], "fewer while it is half explored (" .. half .. ")")
	eq(Dressing.roomBand(Env, EnvBands, 7, 3, 1, 16), 2, "inside a band, every module wears its kit")
end

--================================================================ text: glyphs, lengths
do
	local SEEN = { [0x2014] = true, [0x2026] = true, [0x2605] = true }
	local bad = {}
	local function check(s, where)
		for _, cp in utf8.codes(s) do
			if cp >= 0x2000 and not SEEN[cp] then table.insert(bad, where) end
		end
	end
	for _, b in bands do
		check(b.name, b.id .. ".name")
		check(b.line, b.id .. ".line")
		truthy(#b.line <= 60, b.id .. ": its line fits the hint (" .. #b.line .. " bytes)")
		local banner = "SECTOR 60 — " .. b.name
		truthy(utf8.len(banner) <= 40, b.id .. ": its ride banner fits (" .. utf8.len(banner) .. " characters)")
	end
	for id, k in Config.Hazards.Kinds do
		local banner = k.name .. " — STEP OUT OF THE RING"
		truthy(utf8.len(banner) <= 40, id .. ": its warning banner fits in 40 characters (" .. utf8.len(banner) .. ")")
		check(k.name, id)
	end
	eq(#bad, 0, "every band and hazard text uses only glyphs photographed in Studio (" .. table.concat(bad, ", ") .. ")")
end

--================================================================ budgets are numbers the code can enforce
do
	local B = Config.Budget
	eq(B.MaxEmitters, 4, "4 active emitters")
	eq(B.MaxWeather, 2, "at most 2 of them weather")
	eq(B.MaxHazards, 1, "1 hazard")
	eq(B.MaxExteriorParts, 45, "45 exterior parts (planet 2, dish 8, 30 beacons, 5 spare)")
	truthy(B.MaxDressParts >= 24 * B.MaxDressPartsPerModule, "300 dressing parts cover the ~24 modules a 6x6 player opens, at the cap")
	-- The 300-part cap is a backstop that cannot bind, by construction: Env.client dresses only modules whose centre
	-- is within DressRadius of the player, and no point on the 32-stud grid has more module centres than this within
	-- that radius (scanned over one cell at 1-stud steps). A mutation sweep showed no gate can exercise the cap itself,
	-- so the bound is what is asserted.
	local cell, R = Config.Station.CellSize, Config.Env.DressRadius
	local worstCount = 0
	for xi = 0, cell do
		for zi = 0, cell do
			local n = 0
			for i = -8, 8 do
				for j = -8, 8 do
					local dx, dz = i * cell - xi, j * cell - zi
					if dx * dx + dz * dz <= R * R then n += 1 end
				end
			end
			worstCount = math.max(worstCount, n)
		end
	end
	print(string.format("  at most %d module centres lie within DressRadius %d of any point: %d x %d = %d dressing parts <= %d",
		worstCount, R, worstCount, B.MaxDressPartsPerModule, worstCount * B.MaxDressPartsPerModule, B.MaxDressParts))
	truthy(worstCount * B.MaxDressPartsPerModule <= B.MaxDressParts, "the dressing radius alone keeps the total under the cap")
	eq(Dressing.EXTERIOR_PARTS, 2 + 8 + 30 + 1 + B.MaxCritters, "the exterior model's own count: planet 2, dish 8, 30 beacons, the beam, the critters")
	truthy(Dressing.EXTERIOR_PARTS <= B.MaxExteriorParts, "and it fits the cap")
end

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
assert(failed == 0, "EnvConfig tests failed")
