-- Spec for the environment's NUMBERS in Config: bands, grades, palettes, hazards, rest, budgets.
-- Run: luau tests/EnvConfig.spec.luau
--
-- The rules the owner's brief and the game's design put on those numbers, checked against the real
-- Config. Where a rule is about brightness, luma is re-derived here (Rec. 709) instead of read back
-- from the module that uses it.
local Config = require("../src/shared/Config")
local EnvBands = require("../src/shared/EnvBands")
local Hazards = require("../src/shared/Hazards")
local Rest = require("../src/shared/Rest")
local Dressing = require("../src/shared/Dressing")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

local Env, F = Config.Env, Config.Facility
local function luma(c) return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end
-- LIGHT, not gamma: sRGB (IEC 61966-2-1) to linear, and the relative luminance (Rec. 709) a surface of colour
-- s returns under a light of colour l (white when nil), per channel. Re-derived here, not read from Dressing.
local function lin(v)
	local c = v / 255
	return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end
local function returned(s, l)
	l = l or { 255, 255, 255 }
	return 0.2126 * lin(s[1]) * lin(l[1]) + 0.7152 * lin(s[2]) * lin(l[2]) + 0.0722 * lin(s[3]) * lin(l[3])
end
-- Review finding 1 (EYECANDY.md §11): a palette may repaint the server's room, not dim it. Written out, not read
-- from Config: every surface returns 60-100 % of the light the server's did (about 80 % as bright on screen,
-- 0.6^(1/2.2), the allowance the grade's tint already had), the room light keeps 90-100 % of its output, and a
-- closed door stays as much darker than its wall as the server built it, within 10 %.
local REFLECT_MIN, LIGHT_MIN, DOOR_MIN, DOOR_MAX = 0.6, 0.9, 0.9, 1.1

--================================================================ bands

local bands = Env.Bands
truthy((EnvBands.validate(bands)), "Config.Env.Bands validates")
local ids = {}
for _, b in bands do table.insert(ids, b.id) end
eq(table.concat(ids, ","), "offices,labs,servers,flooded,reactor,biolab,void",
	"seven bands, deeper and stranger: offices, labs, server rooms, flooded maintenance, reactor, overgrown bio-lab, the void")
-- The progress value is the sublevel number k >= 1, the number on the HUD and in leaderstats.Deepest.
eq(EnvBands.indexAt(bands, 1), 1, "sublevel 1 is the offices")
for i = 2, #bands do
	local b, prev = bands[i], bands[i - 1]
	eq(b.from % 1, 0, b.id .. " starts on a whole sublevel (" .. b.from .. ")")
	truthy(b.from - math.max(prev.from, 1) >= 2, b.id .. ": the band before it lasts at least two sublevels")
	local _, j, t = EnvBands.locate(bands, b.from - 1)
	truthy(j == i and t >= 0.15 and t <= 0.4, string.format("%s is foreshadowed on sublevel %d (weight %.2f, in 0.15..0.4)", b.id, b.from - 1, t))
	local _, j2, t2 = EnvBands.locate(bands, b.from - 2)
	truthy(j2 ~= i or t2 == 0, b.id .. " does not show two sublevels early")
	eq(EnvBands.indexAt(bands, b.from), i, b.id .. " is fully there on sublevel " .. b.from)
end
truthy(bands[#bands].from <= 13, "the void, the long-term goal, starts by sublevel 13 (" .. bands[#bands].from .. ")")
eq(bands[3].from, 5, "server rooms from sublevel 5: the bot at the slow proxy powers sublevel 5 on 41-45 % of perk-less runs (CLAUDE.md)")

local fields = { "tint", "saturation", "contrast", "brightness", "atmosColor", "atmosDecay" }
local pfields = { "wall", "floor", "ceiling", "door", "light", "wallMaterial", "floorMaterial" }
for _, b in bands do
	truthy(type(b.name) == "string" and #b.name > 0, b.id .. " has a name")
	local ascii = true
	for _, cp in utf8.codes(b.name .. (b.line or "")) do
		if cp >= 0x80 and cp ~= 0x2014 and cp ~= 0x2026 then ascii = false end
	end
	truthy(ascii, b.id .. ": name and line use only glyphs photographed in Studio (ASCII, em dash, ellipsis)")
	truthy(Dressing.KITS[b.kit] ~= nil, b.id .. " has a dressing kit")
	for _, f in fields do truthy(b.grade[f] ~= nil, b.id .. ".grade." .. f) end
	for _, f in pfields do truthy(b.palette[f] ~= nil, b.id .. ".palette." .. f) end
	truthy(type(b.hazards) == "table", b.id .. " lists its hazard kinds")
	for _, kind in b.hazards do
		truthy(Config.Hazards.Kinds[kind] ~= nil, b.id .. ": hazard kind " .. kind .. " exists")
	end
end
eq(#bands[1].hazards, 0, "the offices are quiet: a first run meets the dark before anything else")
for i = 2, #bands do
	truthy(#bands[i].hazards >= 1, bands[i].id .. " has a hazard of its own")
end

--================================================================ never brighter, never easier to see

local B = Env.Base
local function gradeRules(name, g)
	local tl = luma(g.tint)
	truthy(tl <= luma(B.tint) + 1e-9 and tl >= 0.8 * luma(B.tint),
		string.format("%s: tint luma %.1f within 80-100%% of the Facility preset's %.1f", name, tl, luma(B.tint)))
	truthy(g.brightness <= B.brightness + 1e-9, name .. ": colour-correction brightness never above the preset")
	truthy(g.contrast >= B.contrast - 1e-9 and g.contrast <= B.contrast + 0.2 + 1e-9, name .. ": contrast within preset..preset + 0.2")
	truthy(g.saturation >= -0.5 and g.saturation <= 0, name .. ": saturation within -0.5..0 (never more vivid than neutral)")
	truthy(luma(g.atmosColor) <= luma(B.atmosColor) + 1e-9, name .. ": atmosphere colour never brighter (haze is what fills the dark)")
	truthy(luma(g.atmosDecay) <= luma(B.atmosDecay) + 1e-9, name .. ": atmosphere decay never brighter")
	for _, f in { "density", "haze", "glare", "exposure", "ambient", "bloom", "depthOfField" } do
		eq(g[f], nil, name .. ": a band never touches " .. f .. " (visibility and exposure stay the server's)")
	end
end
eq(Env.ReflectanceMin, REFLECT_MIN, "Config.Env.ReflectanceMin is 0.6: a surface returns at least 60 % of the server's light")
eq(Env.LightOutputMin, LIGHT_MIN, "Config.Env.LightOutputMin is 0.9: the room light keeps at least 90 % of its output")
eq(Env.DoorContrastMin, DOOR_MIN, "Config.Env.DoorContrastMin is 0.9")
eq(Env.DoorContrastMax, DOOR_MAX, "Config.Env.DoorContrastMax is 1.1: a closed door stands out from its wall as the server built it, within 10 %")
local serverRatio = { white = returned(B.wall) / returned(B.door), room = returned(B.wall, B.light) / returned(B.door, B.light) }
truthy(serverRatio.white > 2.5 and serverRatio.white < 2.8, string.format("control: the server's wall returns %.2f x what its door does", serverRatio.white))
for _, b in bands do
	gradeRules(b.id, b.grade)
	local p = b.palette
	local out = returned({ 255, 255, 255 }, p.light) / returned({ 255, 255, 255 }, B.light)
	truthy(out <= 1 + 1e-9 and out >= LIGHT_MIN - 1e-9,
		string.format("%s: the room light's colour carries %.0f %% of the server's light (90-100 %%)", b.id, 100 * out))
	for _, f in { "wall", "floor", "ceiling", "door" } do
		-- under the flashlight (white) and under the room's own light
		local rw = returned(p[f]) / returned(B[f])
		local rr = returned(p[f], p.light) / returned(B[f], B.light)
		truthy(rw <= 1 + 1e-9 and rw >= REFLECT_MIN - 1e-9,
			string.format("%s: the %s returns %.0f %% of the server's light under the flashlight (60-100 %%)", b.id, f, 100 * rw))
		truthy(rr <= 1 + 1e-9 and rr >= REFLECT_MIN - 1e-9,
			string.format("%s: the %s returns %.0f %% of the server's light under the room's own light (60-100 %%)", b.id, f, 100 * rr))
		truthy(Dressing.distinct(p[f], B.fuse, false) and Dressing.distinct(p[f], B.cell, false), b.id .. ": the " .. f .. " never looks like a fuse or a cell")
	end
	local cw = (returned(p.wall) / returned(p.door)) / serverRatio.white
	local cr = (returned(p.wall, p.light) / returned(p.door, p.light)) / serverRatio.room
	truthy(cw >= DOOR_MIN - 1e-9 and cw <= DOOR_MAX + 1e-9,
		string.format("%s: a closed door stands out from its wall %.0f %% as much as in the server's room, under the flashlight (90-110 %%)", b.id, 100 * cw))
	truthy(cr >= DOOR_MIN - 1e-9 and cr <= DOOR_MAX + 1e-9,
		string.format("%s: …and %.0f %% under the room's own light", b.id, 100 * cr))
	truthy(Dressing.MATERIALS[p.wallMaterial] == true, b.id .. ": wall material " .. tostring(p.wallMaterial) .. " is matte")
	truthy(Dressing.MATERIALS[p.floorMaterial] == true, b.id .. ": floor material " .. tostring(p.floorMaterial) .. " is matte")
	truthy((Dressing.paletteOk(Env, p)), b.id .. ": Dressing.paletteOk agrees")
	truthy((Dressing.gradeOk(Env, b.grade)), b.id .. ": Dressing.gradeOk agrees")
end
gradeRules("break room", Env.BreakRoom.grade)
do -- every blend the client can ever write, including mid-seam and mid-glide, obeys the same rules
	local worst = 0
	for p = 0, 20, 0.05 do
		local g = EnvBands.sample(bands, p, "grade")
		worst = math.max(worst, luma(g.tint) - luma(B.tint), luma(g.atmosColor) - luma(B.atmosColor), g.brightness - B.brightness)
		local h = EnvBands.lerp(Env.BreakRoom.grade, g, 0.5)
		worst = math.max(worst, luma(h.tint) - luma(B.tint))
	end
	truthy(worst <= 1e-9, "no blend at any sublevel, or halfway from the break room, is brighter than the preset (worst +" .. worst .. ")")
end
do -- the checker is not vacuous
	local bright = table.clone(bands[1].grade)
	bright.tint = { 255, 255, 255 }
	eq((Dressing.gradeOk(Env, bright)), false, "gradeOk rejects a white tint")
	local lit = table.clone(bands[1].palette)
	lit.wall = { 240, 240, 240 }
	eq((Dressing.paletteOk(Env, lit)), false, "paletteOk rejects white walls")
	local neon = table.clone(bands[1].palette)
	neon.wallMaterial = "Neon"
	eq((Dressing.paletteOk(Env, neon)), false, "paletteOk rejects glowing walls")
end
do -- review finding 1 (EYECANDY.md §11): each rule on its own. Every case below breaks exactly ONE rule (the numbers were solved for
	-- that), so the reason paletteOk gives names the rule that must have caught it.
	local function why(p)
		local ok, reason = Dressing.paletteOk(Env, p)
		return if ok then "ACCEPTED" else tostring(reason)
	end
	local function has(s, ...)
		for _, needle in { ... } do
			if not string.find(s, needle, 1, true) then return false end
		end
		return true
	end
	local server = { wall = B.wall, floor = B.floor, ceiling = B.ceiling, door = B.door, light = B.light,
		wallMaterial = "SmoothPlastic", floorMaterial = "Concrete" }
	eq(why(server), "ACCEPTED", "the server's own room is a legal palette (every ratio exactly 1)")
	local labs = bands[2].palette
	eq(why(labs), "ACCEPTED", "control: the labs' palette, the base of the cases below, is accepted")
	local function with(fields)
		local p = table.clone(labs)
		for k, v in fields do p[k] = v end
		return p
	end
	local w = why(with({ light = { 190, 215, 255 } }))
	truthy(has(w, "room light carries"), "a room light that carries 75 % of the server's light is rejected for its output: " .. w)
	w = why(with({ light = { 255, 255, 255 } }))
	truthy(has(w, "room light carries"), "a room light brighter than the server's is rejected for its output: " .. w)
	w = why(with({ wall = { 97, 117, 117 }, door = { 67, 73, 76 } }))
	truthy(has(w, "wall returns"), "walls (and the door with them) at half the server's light are rejected for the light they return: " .. w)
	w = why(with({ light = { 255, 228, 190 }, wall = { 109, 124, 169 }, door = { 68, 78, 108 } }))
	truthy(has(w, "wall returns", "room's own light"),
		"blue walls fine under the flashlight (62 %) but at 54 % under a warm room light are rejected: " .. w)
	w = why(with({ wall = { 108, 129, 129 } }))
	truthy(has(w, "stands out"), "a door that stands out from its wall at 63 % of the server's is rejected (harder to find): " .. w)
	w = why(with({ door = { 73, 80, 83 } }))
	truthy(has(w, "stands out"), "a door that stands out at 156 % of the server's is rejected (easier to find than designed): " .. w)
	-- the palettes the review found: a closed door as bright as its wall, walls at 7-19 % of the server's light
	local old = {
		servers = { wall = { 66, 72, 84 }, floor = { 70, 74, 82 }, ceiling = { 34, 36, 42 }, door = { 70, 76, 86 }, light = { 190, 215, 255 } },
		reactor = { wall = { 96, 88, 84 }, floor = { 66, 62, 60 }, ceiling = { 40, 34, 32 }, door = { 110, 90, 40 }, light = { 255, 200, 170 } },
		void = { wall = { 44, 38, 56 }, floor = { 30, 28, 38 }, ceiling = { 20, 18, 26 }, door = { 48, 42, 60 }, light = { 215, 195, 255 } },
	}
	for name, p in old do
		eq((Dressing.paletteOk(Env, with(p))), false, "the " .. name .. " palette the review measured is rejected now")
	end
end

--================================================================ hazards

local Hz = Config.Hazards
truthy((Hazards.validate(Hz)), "Config.Hazards validates")
eq(Hz.IntervalMin, 120, "at most one hazard per 2 exposed minutes")
eq(Hz.IntervalMax, 180, "…at least one per 3 (the owner: about one near-hit per 2-3 minutes)")
truthy(Hz.EscapeSpeed <= 10.4 + 1e-9, "every telegraph is escapable at the SLOW proxy's 10.4 studs/s, not only at walk speed")
truthy(Hz.MinTelegraphSeconds >= 2.5, "every hazard is telegraphed at least 2.5 s")
truthy(Hz.SpotMinWallDistance >= F.ItemWallClearance, "a hazard starts no nearer a wall than an item stands (the interior)")
truthy(Hz.ArrivalGraceSeconds >= 3 and Hz.ArrivalGraceSeconds <= 10,
	"no hazard in the first " .. Hz.ArrivalGraceSeconds .. " s on a sublevel: longer than the arrival's 3 s POWER IS FAILING banner, short of a quiet zone")
do
	local maxR = 0
	for _, k in Hz.Kinds do maxR = math.max(maxR, k.hitRadius + Hz.PlayerRadius) end
	truthy(maxR <= Hz.SpotMinWallDistance - 1,
		"the largest zone (" .. maxR .. ") leaves at least a stud of floor to every wall from any legal spot")
end
do -- Banners. Nothing headless can see how a phone wraps a 30 px banner, so no banner the environment adds
	-- may be longer than the longest one the HUD showed before it existed. The suffixes mirror Hud.client.luau;
	-- check_facilitynightmare_hazards reads the real banner off the real HUD.
	local LONGEST = utf8.len("THE POWER IS FAILING — STAY IN THE LIGHT")
	eq(LONGEST, 40, "control: the longest pre-existing banner is 40 characters")
	for kind, k in Hz.Kinds do
		local ascii = type(k.name) == "string" and #k.name > 0
		for _, cp in utf8.codes(k.name or "") do
			if cp >= 0x80 then ascii = false end
		end
		truthy(ascii, kind .. " has a plain ASCII name")
		for _, suffix in { " — STEP OUT OF THE RING", " — YOU ARE CLEAR" } do
			local len = utf8.len(tostring(k.name) .. suffix)
			truthy(len <= LONGEST, string.format("%s's banner '%s%s' is %d characters (max %d)", kind, tostring(k.name), suffix, len, LONGEST))
		end
	end
	for _, b in bands do
		local len = utf8.len("SUBLEVEL 99 — " .. b.name)
		truthy(len <= LONGEST, string.format("%s's banner 'SUBLEVEL 99 — %s' is %d characters (max %d)", b.id, b.name, len, LONGEST))
	end
	-- the ride's hint (Hud.client rideHint: a name that starts with THE takes no second article)
	local LONGEST_HINT = utf8.len("Saving is off on this server — progress will not be kept. Walk into the elevator.")
	eq(LONGEST_HINT, 81, "control: the longest pre-existing hint is 81 characters")
	for _, b in bands do
		local article = if string.sub(b.name, 1, 4) == "THE " then "" else "the "
		local hint = "Going down to " .. article .. b.name .. "… " .. tostring(b.line)
		truthy(type(b.line) == "string" and #b.line > 0 and utf8.len(hint) <= LONGEST_HINT,
			string.format("%s's ride hint '%s' is %d characters (max %d)", b.id, hint, utf8.len(hint), LONGEST_HINT))
	end
end

--================================================================ rest

truthy((Rest.validate(Config.Rest)), "Config.Rest validates")
local phases = {}
for ph, on in Config.Rest.Phases do if on then table.insert(phases, ph) end end
eq(table.concat(phases, ","), "hub", "rest exists only in the break room, between runs")

--================================================================ budgets

local Bu = Config.Budget
do -- the most built rooms that can be within DressRadius of any point of a 5x5 floor
	local n, cell = 5, F.CellSize
	local most = 0
	for px = -n * cell / 2, n * cell / 2, 1 do
		for pz = -n * cell / 2, n * cell / 2, 1 do
			local c = 0
			for i = 0, n - 1 do
				for j = 0, n - 1 do
					local cx, cz = (i - (n - 1) / 2) * cell, (j - (n - 1) / 2) * cell
					if (cx - px) ^ 2 + (cz - pz) ^ 2 <= Env.DressRadius ^ 2 then c += 1 end
				end
			end
			most = math.max(most, c)
		end
	end
	print(string.format("    at most %d rooms within %d studs; %d x %d parts + %d hazard parts = %d (budget %d)",
		most, Env.DressRadius, most, Env.MaxPartsPerRoom, Bu.MaxHazardParts, most * Env.MaxPartsPerRoom + Bu.MaxHazardParts, Bu.MaxLocalParts))
	truthy(most * Env.MaxPartsPerRoom + Bu.MaxHazardParts <= Bu.MaxLocalParts, "the worst case fits MaxLocalParts by arithmetic")
	truthy(Bu.MaxHubParts <= Bu.MaxLocalParts, "the break room's dressing fits too (it is never shown at the same time as a floor's)")
end
eq(Bu.MaxLights, 0, "the environment adds NO light source: glow is self-lit surfaces only, off when their room is dark")
truthy(Bu.MaxEmitters <= 4 and Bu.MaxEmitterRate <= 40, "at most 4 emitters and 40 particles/s on at once (mobile)")
truthy(type(Bu.HazardEmitterRate) == "number" and Bu.HazardEmitterRate > 0, "a hazard's warning particles have a rate budget")
truthy((Bu.MaxEmitters - 1) * Env.MaxRoomEmitterRate + (Bu.HazardEmitterRate or math.huge) <= Bu.MaxEmitterRate,
	"rooms' emitters at their cap plus a hazard's warning never exceed MaxEmitterRate, by arithmetic")
eq(Bu.MaxHazards, 1, "one hazard at a time")

print(string.format("EnvConfig: %d passed, %d failed", passed, failed))
