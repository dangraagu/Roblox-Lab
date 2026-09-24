--!strict
-- Dressing.luau — what each environment band adds to a built room, and the rules that keep it fair. Pure.
--
-- A band's KIT is a catalogue of small pieces (a filing cabinet, a lab bench with glowing flasks, a pair
-- of server racks, a rusted pipe run, a coolant riser, a vine, a rift in the wall). build() places some of
-- them in one room, deterministically from (kit, room id, sublevel), around the room's server props. It
-- never sees the room's item: what a room is dressed with says nothing about what the room holds.
--
-- The rules every piece obeys (check(); tests/Dressing.spec.luau re-derives them against real rooms):
--   * WALL pieces lie entirely within WallBand of a wall's inner face. Items stand at least
--     ItemWallClearance (6) off every wall, so a wall piece can never stand where an item can.
--   * Anything else is OVERHEAD: its bottom at or above OverheadMinY (6.5), above every standing eye
--     (~4.5), so it can never come between an eye and an item; and out of the centre column, where the
--     lift's and the car's roofs and the light fixture are.
--   * FILMS (water, moss, papers) are at most FilmMaxTop (0.2) thick; items float at 0.7 and up.
--   * Below the door height, nothing stands in front of the middle of ANY wall (door or not, so the
--     dressing does not even say where the doors are), with DoorKeepOut to spare past a doorway's edge.
--   * Nothing intersects a server prop; pieces may stand ON one (a monitor on a desk).
--   * No glowing surface is within 30 degrees of hue of a fuse (amber) or a battery cell (green) unless it
--     is near-white; no painted surface is a bright, saturated fuse-amber or cell-green either.
--   * Particles never reach the item volume. At most one emitter, three screens and MaxPartsPerRoom
--     parts per room. Materials come from a matte list: no Neon on a dull part, no Glass, no Foil.
-- Glow is SELF-LIT surfaces (Neon, glowing screens, light-emitting particles), never a light source;
-- the client switches all of it off in a room whose light is off, and follows the room's flicker.
--
-- Coordinates are room-local: x/z from the room's centre, y from the floor top; walls' inner faces at
-- +-inner (13 in a 28-stud cell). Colours are { r, g, b } 0..255. Everything runs in the luau CLI.

local Dressing = {}

Dressing.MATERIALS = {
	SmoothPlastic = true, Plastic = true, Concrete = true, Slate = true, Metal = true, DiamondPlate = true,
	CorrodedMetal = true, Fabric = true, Brick = true, Cobblestone = true, Granite = true, Pebble = true,
	Wood = true, WoodPlanks = true, Grass = true, Ground = true, Mud = true, Basalt = true, Asphalt = true,
	Rock = true, LeafyGrass = true, Sand = true,
}

local EPS = 1e-6

--============================================================================ colour

function Dressing.luma(c: { number }): number
	return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

-- (hue degrees 0..360, saturation 0..1, value 0..1)
function Dressing.hsv(c: { number }): (number, number, number)
	local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = 60 * (((g - b) / d) % 6)
		elseif mx == g then
			h = 60 * ((b - r) / d + 2)
		else
			h = 60 * ((r - g) / d + 4)
		end
	end
	local s = if mx > 0 then d / mx else 0
	return h, s, mx
end

-- Can `c` be told apart from an item of colour `item`? Glowing: a hue at least 30 degrees away, or
-- near-white. Painted: a hue 30 degrees away, or a dull (low-saturation) colour, or one far darker than
-- the glowing item.
function Dressing.distinct(c: { number }, item: { number }, emissive: boolean): boolean
	local h1, s1, v1 = Dressing.hsv(c)
	local h2, _, v2 = Dressing.hsv(item)
	local dh = math.abs(h1 - h2) % 360
	dh = math.min(dh, 360 - dh)
	if dh >= 30 then return true end
	if emissive then return s1 <= 0.2 end
	return s1 <= 0.25 or v1 <= 0.6 * v2
end

-- A colour grade may darken and tint, never brighten: tint luma within 80-100 % of the preset's,
-- colour-correction brightness no higher, contrast within preset..+0.2, saturation -0.5..0, the
-- atmosphere's colour and decay no brighter. It never names density, haze, glare, exposure, ambient,
-- bloom or depth of field (visibility stays the server's preset).
function Dressing.gradeOk(env: any, g: any): (boolean, string?)
	local B = env.Base
	local lt, lb = Dressing.luma(g.tint), Dressing.luma(B.tint)
	if lt > lb + EPS or lt < 0.8 * lb then return false, "tint luma outside 80-100 % of the preset" end
	if g.brightness > B.brightness + EPS then return false, "brightness above the preset" end
	if g.contrast < B.contrast - EPS or g.contrast > B.contrast + 0.2 + EPS then return false, "contrast outside preset..+0.2" end
	if g.saturation < -0.5 - EPS or g.saturation > EPS then return false, "saturation outside -0.5..0" end
	if Dressing.luma(g.atmosColor) > Dressing.luma(B.atmosColor) + EPS then return false, "atmosphere colour brighter than the preset" end
	if Dressing.luma(g.atmosDecay) > Dressing.luma(B.atmosDecay) + EPS then return false, "atmosphere decay brighter than the preset" end
	for _, f in { "density", "haze", "glare", "exposure", "ambient", "bloom", "depthOfField" } do
		if g[f] ~= nil then return false, "a grade may not set " .. f end
	end
	return true, nil
end

-- sRGB 0..255 -> linear light 0..1 (IEC 61966-2-1). Gamma luma is how bright a colour LOOKS as a number; how
-- much light a surface sends back to the eye is linear, and gamma hides a lot of darkening: a wall at 26 %
-- of the server's gamma luma returns 7 % of its light.
function Dressing.linear(v: number): number
	local c = v / 255
	return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end

-- The relative luminance (Rec. 709) a surface of colour `s` returns under a light of colour `l` (white when
-- nil), per channel: what the eye gets back from a wall under the flashlight (white) or the room's own light.
function Dressing.returned(s: { number }, l: { number }?): number
	local L = l or { 255, 255, 255 }
	local lin = Dressing.linear
	return 0.2126 * lin(s[1]) * lin(L[1]) + 0.7152 * lin(s[2]) * lin(L[2]) + 0.0722 * lin(s[3]) * lin(L[3])
end

-- A palette recolours the server's own room parts on this client. It may change their hue and material, not
-- how much light they give back (EYECANDY.md §2 and §11). In LINEAR light, under the flashlight's white light
-- AND under the room's own light:
--   * the room light's colour carries LightOutputMin..100 % of the server's light;
--   * every surface (wall, floor, ceiling, door) returns ReflectanceMin..100 % of what the server's did: never
--     brighter, and never darker than about 80 % as bright on screen;
--   * a closed door stands out from its wall DoorContrastMin..DoorContrastMax as much as in the server's room
--     (wall light / door light): doors are no harder, and no easier, to find than designed;
--   * matte materials only, and nothing item-coloured.
function Dressing.paletteOk(env: any, p: any): (boolean, string?)
	local B = env.Base
	local ret = Dressing.returned
	local white = { 255, 255, 255 }
	local out = ret(white, p.light) / ret(white, B.light)
	if out > 1 + EPS or out < env.LightOutputMin - EPS then
		return false, string.format("the room light carries %.0f %% of the server's light (%.0f-100 %%)", 100 * out, 100 * env.LightOutputMin)
	end
	local lights = {
		{ name = "the flashlight", l = white, lb = white },
		{ name = "the room's own light", l = p.light, lb = B.light },
	}
	for _, f in { "wall", "floor", "ceiling", "door" } do
		for _, L in lights do
			local r = ret(p[f], L.l) / ret(B[f], L.lb)
			if r > 1 + EPS or r < env.ReflectanceMin - EPS then
				return false, string.format("the %s returns %.0f %% of the server's light under %s (%.0f-100 %%)", f, 100 * r, L.name,
					100 * env.ReflectanceMin)
			end
		end
		if not Dressing.distinct(p[f], B.fuse, false) or not Dressing.distinct(p[f], B.cell, false) then
			return false, f .. " could pass for a fuse or a cell"
		end
	end
	for _, L in lights do
		local c = (ret(p.wall, L.l) / ret(p.door, L.l)) / (ret(B.wall, L.lb) / ret(B.door, L.lb))
		if c < env.DoorContrastMin - EPS or c > env.DoorContrastMax + EPS then
			return false, string.format("a closed door stands out from its wall %.0f %% as much as in the server's room under %s (%.0f-%.0f %%)",
				100 * c, L.name, 100 * env.DoorContrastMin, 100 * env.DoorContrastMax)
		end
	end
	if not Dressing.MATERIALS[p.wallMaterial] then return false, "wall material " .. tostring(p.wallMaterial) .. " is not matte" end
	if not Dressing.MATERIALS[p.floorMaterial] then return false, "floor material " .. tostring(p.floorMaterial) .. " is not matte" end
	return true, nil
end

--============================================================================ which band dresses a room

-- Deterministic [0, 1) from integers (EnvBands.hash01, repeated so this module needs no dependency).
local function hash01(a: number, b: number, c: number, seed: number): number
	local h = (seed % 2147483647 + 2147483647) % 2147483647
	for _, v in { a, b, c } do
		local x = (math.floor(v) % 2147483647 + 2147483647) % 2147483647
		h = (h * 31 + x + 7919) % 2147483647
		h = (h * 48271) % 2147483647
		h = (h * 16807 + 12345) % 2147483647
	end
	return h / 2147483647
end
Dressing.hash01 = hash01

-- The band that dresses room `roomId` on sublevel k. On a band's last sublevel the next band blends in
-- with weight t (EnvBands.locate), and that share of the rooms, chosen by a hash of (k, room), already
-- wears it: the labs creep into the offices before you reach them.
function Dressing.roomBand(env: any, EnvBands: any, k: number, roomId: number): number
	local i, j, t = EnvBands.locate(env.Bands, k)
	if j ~= i and t > 0 and hash01(k, roomId, 17, env.SeamSalt) < t then
		return j
	end
	return i
end

--============================================================================ geometry

local WALLS = { "+x", "-x", "+z", "-z" }
Dressing.WALLS = WALLS
-- The face of a wall piece that looks into the room (Roblox NormalId names).
Dressing.FACE = { ["+x"] = "Left", ["-x"] = "Right", ["+z"] = "Front", ["-z"] = "Back" }

-- A template part in its wall's frame -> a room-local AABB. a = centre along the wall; o = from the wall
-- face to the part's back; w along, d into the room, h up; y = bottom.
local function toRoom(inner: number, wall: string, a: number, o: number, w: number, d: number, y: number, h: number): ({ number }, { number })
	if wall == "+x" then
		return { inner - o - d, y, a - w / 2 }, { inner - o, y + h, a + w / 2 }
	elseif wall == "-x" then
		return { -inner + o, y, a - w / 2 }, { -inner + o + d, y + h, a + w / 2 }
	elseif wall == "+z" then
		return { a - w / 2, y, inner - o - d }, { a + w / 2, y + h, inner - o }
	else
		return { a - w / 2, y, -inner + o }, { a + w / 2, y + h, -inner + o + d }
	end
end

-- Room axis a template cylinder runs along: "up" = y; "along" = the wall's tangent; "out" = its normal.
local function roomAxis(wall: string, axis: string): string
	if axis == "up" then return "y" end
	local xWall = wall == "+x" or wall == "-x"
	if axis == "along" then
		return if xWall then "z" else "x"
	end
	return if xWall then "x" else "z"
end

local function classOf(env: any, inner: number, mn: { number }, mx: { number }): string
	if mx[2] <= env.FilmMaxTop + EPS then return "film" end
	local band = inner - env.WallBand
	if mn[1] >= band - EPS or mx[1] <= -band + EPS or mn[3] >= band - EPS or mx[3] <= -band + EPS then
		return "wall"
	end
	return "overhead"
end

local function boxesOverlap(a: any, b: any, pad: number): boolean
	for i = 1, 3 do
		if a.min[i] >= b.max[i] + pad - 0.02 or b.min[i] >= a.max[i] + pad - 0.02 then return false end
	end
	return true
end

-- The box particles from `p`'s emitter can reach (a conservative bound: straight-line travel at the top
-- speed for the longest life, plus constant acceleration, plus half a particle).
function Dressing.emitterRegion(p: any): any
	local e = p.emitter
	local L, v = e.life[2], e.speed[2]
	local s = math.rad(math.min(e.spread, 90))
	local ax, ay, az = e.accel[1], e.accel[2], e.accel[3]
	local half = e.size / 2
	local hReach = v * L * math.sin(s) + 0.5 * math.sqrt(ax * ax + az * az) * L * L + half
	local up = (if e.dir == "up" then v * L else 0) + 0.5 * math.max(0, ay) * L * L + half
	local down = (if e.dir == "down" then v * L else 0) + 0.5 * math.max(0, -ay) * L * L + half
	return {
		min = { p.min[1] - hReach, p.min[2] - down, p.min[3] - hReach },
		max = { p.max[1] + hReach, p.max[2] + up, p.max[3] + hReach },
	}
end

-- One part against every per-part rule. (ok, why)
function Dressing.partOk(env: any, fac: any, p: any, props: { any }): (boolean, string?)
	local inner = fac.CellSize / 2 - fac.WallThickness
	local mn, mx = p.min, p.max
	for _, ax in { 1, 3 } do
		if mn[ax] < -inner - EPS or mx[ax] > inner + EPS then return false, p.name .. " pokes through a wall" end
	end
	if mn[2] < -EPS or mx[2] > fac.CeilingHeight + EPS then return false, p.name .. " pokes through the floor or ceiling" end
	local class = classOf(env, inner, mn, mx)
	if p.class ~= nil and p.class ~= class then
		-- a piece labelled overhead/film that is not, or the other way round
		if not (p.class == "overhead" and class == "wall") then
			return false, p.name .. " claims to be " .. tostring(p.class) .. " but is " .. class
		end
	end
	if class == "film" then
		if mx[2] > env.FilmMaxTop + EPS then return false, p.name .. " is too thick for a film" end
	elseif class == "overhead" then
		if mn[2] < env.OverheadMinY - EPS then return false, p.name .. " hangs below OverheadMinY into the room" end
		local k = env.OverheadPadKeepOut
		if mx[1] > -k and mn[1] < k and mx[3] > -k and mn[3] < k then return false, p.name .. " enters the centre column" end
	end
	if class ~= "film" and mn[2] < fac.DoorHeight + 0.5 then
		local half = fac.DoorWidth / 2 + env.DoorKeepOut
		local band = inner - env.WallBand
		if (mx[1] > band and mx[3] > -half and mn[3] < half) or (mn[1] < -band and mx[3] > -half and mn[3] < half)
			or (mx[3] > band and mx[1] > -half and mn[1] < half) or (mn[3] < -band and mx[1] > -half and mn[1] < half) then
			return false, p.name .. " stands in front of the middle of a wall (a doorway's place) below the door height"
		end
	end
	if class ~= "film" then -- a film lies under everything on the floor, props included
		for _, pr in props do
			if boxesOverlap(p, pr, 0) then return false, p.name .. " intersects the prop " .. tostring(pr.name) end
		end
	end
	local B = env.Base
	if p.emissive then
		if not Dressing.distinct(p.color, B.fuse, true) or not Dressing.distinct(p.color, B.cell, true) then
			return false, p.name .. " glows like a fuse or a cell"
		end
	else
		if not Dressing.distinct(p.color, B.fuse, false) or not Dressing.distinct(p.color, B.cell, false) then
			return false, p.name .. " is painted like a fuse or a cell"
		end
		if Dressing.luma(p.color) > env.MaxDullLuma + EPS then return false, p.name .. " is painted brighter than MaxDullLuma" end
		if not Dressing.MATERIALS[p.material] then return false, p.name .. ": material " .. tostring(p.material) .. " is not on the matte list" end
	end
	if p.screen and (p.shape or "Block") ~= "Block" then
		return false, p.name .. " carries a screen but is not a plain Block (a screen's face must point into the room)"
	end
	if p.screen and p.screen.glow and p.screen.color then
		if not Dressing.distinct(p.screen.color, B.fuse, true) or not Dressing.distinct(p.screen.color, B.cell, true) then
			return false, p.name .. "'s screen glows like a fuse or a cell"
		end
	end
	if p.emitter then
		local e = p.emitter
		if e.rate > env.MaxRoomEmitterRate + EPS then return false, p.name .. ": emitter rate above MaxRoomEmitterRate" end
		if e.spread > 45 then return false, p.name .. ": emitter spread above 45 degrees" end
		if e.lightEmission > 0 and (not Dressing.distinct(e.color, B.fuse, true) or not Dressing.distinct(e.color, B.cell, true)) then
			return false, p.name .. ": glowing particles look like an item"
		end
		local r = Dressing.emitterRegion(p)
		local lim = inner - fac.ItemWallClearance + 1
		local itemVolume = { min = { -lim, -1, -lim }, max = { lim, 3.5, lim } }
		if boxesOverlap(r, itemVolume, 0) then return false, p.name .. ": particles reach the item volume" end
	end
	return true, nil
end

-- A whole room: every part, the counts, and no two pieces through each other. (ok, why)
function Dressing.check(env: any, fac: any, parts: { any }, props: { any }): (boolean, string?)
	if #parts > env.MaxPartsPerRoom then return false, #parts .. " parts (max " .. env.MaxPartsPerRoom .. ")" end
	local emitters, screens = 0, 0
	for i, p in parts do
		local ok, why = Dressing.partOk(env, fac, p, props)
		if not ok then return false, why end
		if p.emitter then emitters += 1 end
		if p.screen then screens += 1 end
		for j = 1, i - 1 do
			local q = parts[j]
			local sameA = p.pieceId or p.piece
			local sameB = q.pieceId or q.piece
			local film = p.class == "film" or q.class == "film"
			if sameA ~= sameB and not film and boxesOverlap(p, q, 0) then
				return false, p.name .. " intersects " .. q.name
			end
		end
	end
	if emitters > 1 then return false, emitters .. " emitters (max 1)" end
	if screens > env.MaxScreensPerRoom then return false, screens .. " screens (max " .. env.MaxScreensPerRoom .. ")" end
	return true, nil
end

--============================================================================ the kits

local function c3(r: number, g: number, b: number): { number }
	return { r, g, b }
end

-- colours
local GREY_BEIGE, DARK_METAL, STEEL = c3(128, 126, 112), c3(70, 70, 66), c3(140, 146, 150)
local CARPET_BLUE, RAIL = c3(70, 80, 104), c3(150, 150, 150)
local RUST, RUST_DARK, VALVE_RED = c3(104, 70, 54), c3(86, 58, 42), c3(140, 40, 36)
local HAZARD_YELLOW = c3(140, 118, 30)
local VINE, VINE_DARK, LEAF = c3(52, 86, 44), c3(46, 78, 40), c3(58, 96, 50)
local VOID_STONE = c3(40, 36, 52)

-- Part template fields: n, a, o, w, d, y, h, shape ("Block" | "Cylinder" | "Ball"), axis ("up" | "along"
-- | "out", cylinders), color, mat, glow (self-lit Neon, follows the room's power), alpha (transparency),
-- solid (collides for this client only; default: floor-standing wall pieces do), screen, emitter, anim,
-- hidden (an invisible emitter host).
Dressing.KITS = {
	offices = {
		wallMin = 3, wallMax = 5,
		film = { chance = 0.5, piece = { name = "papers", parts = {
			{ n = "Papers", a = 0.4, o = 0.3, w = 1.6, d = 1.3, y = 0, h = 0.04, color = c3(176, 174, 160), mat = "SmoothPlastic" },
			{ n = "PapersB", a = -0.9, o = 0.6, w = 1.0, d = 0.8, y = 0, h = 0.03, color = c3(168, 170, 164), mat = "SmoothPlastic" },
		} } },
		onDesk = { name = "monitor", parts = {
			{ n = "Monitor", a = 0.6, o = 0.5, w = 1.9, d = 0.22, y = 0.25, h = 1.25, color = c3(26, 28, 34), mat = "SmoothPlastic",
				screen = { kind = "monitor", glow = true, color = c3(40, 92, 160) } },
			{ n = "Stand", a = 0.6, o = 0.4, w = 0.5, d = 0.6, y = 0, h = 0.25, color = c3(30, 30, 34), mat = "SmoothPlastic" },
			{ n = "Keyboard", a = -0.5, o = 1.4, w = 1.6, d = 0.55, y = 0, h = 0.08, color = c3(44, 44, 48), mat = "SmoothPlastic" },
		} },
		wall = {
			{ name = "filing", weight = 3, parts = {
				{ n = "Cabinet", a = 0, o = 0, w = 2.0, d = 1.6, y = 0, h = 4.4, color = GREY_BEIGE, mat = "Metal" },
				{ n = "Drawers", a = 0, o = 1.6, w = 1.5, d = 0.05, y = 0.5, h = 3.4, color = DARK_METAL, mat = "Metal" },
			} },
			{ name = "cubicle", weight = 3, parts = {
				{ n = "Divider", a = -1.8, o = 0, w = 0.3, d = 2.4, y = 0, h = 4.6, color = CARPET_BLUE, mat = "Fabric" },
				{ n = "DividerRail", a = -1.8, o = 0, w = 0.4, d = 2.4, y = 4.6, h = 0.15, color = RAIL, mat = "Metal" },
				{ n = "ChairSeat", a = 0.2, o = 0.9, w = 1.4, d = 1.4, y = 1.5, h = 0.3, color = c3(38, 40, 48), mat = "Fabric" },
				{ n = "ChairBack", a = 0.2, o = 0.7, w = 1.4, d = 0.2, y = 1.8, h = 1.8, color = c3(38, 40, 48), mat = "Fabric" },
				{ n = "ChairLeg", shape = "Cylinder", axis = "up", a = 0.2, o = 1.4, w = 0.3, d = 0.3, y = 0, h = 1.5, color = DARK_METAL, mat = "Metal" },
			} },
			{ name = "cooler", weight = 2, parts = {
				{ n = "CoolerBody", a = 0, o = 0.2, w = 1.3, d = 1.3, y = 0, h = 3.2, color = c3(180, 182, 180), mat = "SmoothPlastic" },
				{ n = "Bottle", shape = "Cylinder", axis = "up", a = 0, o = 0.3, w = 1.1, d = 1.1, y = 3.2, h = 1.5,
					color = c3(120, 170, 210), mat = "SmoothPlastic", alpha = 0.45 },
			} },
			{ name = "noticeboard", weight = 2, parts = {
				{ n = "Board", a = 0, o = 0, w = 3.4, d = 0.12, y = 4.0, h = 2.2, color = c3(120, 92, 64), mat = "Fabric",
					screen = { kind = "notices" } },
			} },
			{ name = "plant", weight = 2, parts = {
				{ n = "Pot", shape = "Cylinder", axis = "up", a = 0, o = 0.3, w = 1.2, d = 1.2, y = 0, h = 1.2, color = c3(90, 64, 52), mat = "Concrete" },
				{ n = "Leaves", shape = "Ball", a = 0, o = 0.0, w = 1.8, d = 1.8, y = 1.1, h = 1.8, color = LEAF, mat = "Grass" },
			} },
			{ name = "clock", weight = 1, parts = {
				{ n = "Clock", a = 0, o = 0, w = 1.6, d = 0.2, y = 7.2, h = 1.6, color = c3(60, 60, 64), mat = "Metal", -- a Block: screens sit on unrotated faces
					screen = { kind = "clock" } },
			} },
		},
		runs = {},
		hangers = {},
	},

	labs = {
		wallMin = 3, wallMax = 5,
		onDesk = { name = "microscope", parts = {
			{ n = "ScopeBase", a = 0.4, o = 0.6, w = 0.9, d = 0.9, y = 0, h = 0.2, color = c3(170, 172, 176), mat = "Metal" },
			{ n = "ScopeArm", shape = "Cylinder", axis = "up", a = 0.4, o = 0.7, w = 0.3, d = 0.3, y = 0.2, h = 1.1, color = c3(60, 62, 66), mat = "Metal" },
			{ n = "Slide", a = -0.8, o = 1.2, w = 0.7, d = 0.3, y = 0, h = 0.05, color = c3(150, 110, 240), mat = "SmoothPlastic", glow = true },
		} },
		wall = {
			{ name = "bench", weight = 3, parts = {
				{ n = "Counter", a = 0, o = 0, w = 4.4, d = 2.2, y = 0, h = 3.0, color = c3(176, 180, 182), mat = "SmoothPlastic" },
				{ n = "Worktop", a = 0, o = 0, w = 4.4, d = 2.3, y = 3.0, h = 0.12, color = c3(30, 32, 34), mat = "Slate" },
				{ n = "FlaskA", shape = "Cylinder", axis = "up", a = -1.2, o = 0.8, w = 0.45, d = 0.45, y = 3.12, h = 0.8,
					color = c3(150, 100, 255), mat = "SmoothPlastic", glow = true },
				{ n = "FlaskB", shape = "Cylinder", axis = "up", a = 0.9, o = 1.1, w = 0.4, d = 0.4, y = 3.12, h = 0.6,
					color = c3(80, 210, 255), mat = "SmoothPlastic", glow = true },
			} },
			{ name = "fumehood", weight = 2, parts = {
				{ n = "Hood", a = 0, o = 0, w = 4.0, d = 2.2, y = 0, h = 6.2, color = STEEL, mat = "Metal" },
				{ n = "Sash", a = 0, o = 2.2, w = 3.4, d = 0.06, y = 3.2, h = 2.2, color = c3(160, 190, 200), mat = "SmoothPlastic", alpha = 0.6 },
				{ n = "FumeHost", a = 0, o = 0.8, w = 0.6, d = 0.6, y = 6.2, h = 0.3, color = STEEL, mat = "SmoothPlastic", hidden = true,
					emitter = { rate = 3, life = { 2, 3 }, speed = { 0.6, 1.2 }, spread = 10, dir = "up", accel = { 0, 0.2, 0 }, size = 1.2,
						color = c3(170, 160, 190), lightEmission = 0 } },
			} },
			{ name = "shelf", weight = 2, parts = {
				{ n = "Shelf", a = 0, o = 0, w = 3.6, d = 1.2, y = 0, h = 5.2, color = c3(120, 126, 130), mat = "Metal" },
				{ n = "JarA", shape = "Cylinder", axis = "up", a = -0.9, o = 0.3, w = 0.7, d = 0.7, y = 5.2, h = 1.0,
					color = c3(110, 190, 215), mat = "SmoothPlastic", glow = true },
				{ n = "JarB", shape = "Cylinder", axis = "up", a = 0.9, o = 0.3, w = 0.7, d = 0.7, y = 5.2, h = 0.8,
					color = c3(170, 120, 230), mat = "SmoothPlastic", glow = true },
			} },
			{ name = "whiteboard", weight = 2, parts = {
				{ n = "Whiteboard", a = 0, o = 0, w = 4.2, d = 0.12, y = 3.6, h = 2.4, color = c3(184, 188, 190), mat = "SmoothPlastic",
					screen = { kind = "whiteboard" } },
			} },
			{ name = "biobin", weight = 2, parts = {
				{ n = "Bin", shape = "Cylinder", axis = "up", a = 0, o = 0.3, w = 1.3, d = 1.3, y = 0, h = 1.7, color = c3(150, 44, 44), mat = "SmoothPlastic" },
				{ n = "Lid", shape = "Cylinder", axis = "up", a = 0, o = 0.25, w = 1.4, d = 1.4, y = 1.7, h = 0.15, color = c3(60, 60, 64), mat = "SmoothPlastic" },
			} },
		},
		runs = {
			{ chance = 0.6, piece = { name = "duct", parts = {
				{ n = "Duct", a = 0, o = 0, w = 22, d = 1.6, y = 11.9, h = 1.4, color = STEEL, mat = "Metal" },
			} } },
		},
		hangers = {},
	},

	servers = {
		wallMin = 3, wallMax = 5,
		onDesk = { name = "laptop", parts = {
			{ n = "Laptop", a = 0, o = 0.6, w = 1.4, d = 1.0, y = 0, h = 0.08, color = c3(40, 42, 46), mat = "SmoothPlastic" },
			{ n = "LaptopLid", a = 0, o = 0.5, w = 1.4, d = 0.08, y = 0.08, h = 0.95, color = c3(40, 42, 46), mat = "SmoothPlastic",
				screen = { kind = "monitor", glow = true, color = c3(30, 120, 190) } },
		} },
		wall = {
			{ name = "racks", weight = 4, parts = {
				{ n = "RackA", a = -1.15, o = 0, w = 2.2, d = 2.2, y = 0, h = 7.4, color = c3(30, 32, 36), mat = "Metal",
					screen = { kind = "rack", glow = true, color = c3(70, 150, 255) } },
				{ n = "RackB", a = 1.15, o = 0, w = 2.2, d = 2.2, y = 0, h = 7.4, color = c3(30, 32, 36), mat = "Metal",
					screen = { kind = "rack", glow = true, color = c3(70, 150, 255) } },
			} },
			{ name = "rack", weight = 3, parts = {
				{ n = "Rack", a = -0.8, o = 0, w = 2.2, d = 2.2, y = 0, h = 7.4, color = c3(30, 32, 36), mat = "Metal",
					screen = { kind = "rack", glow = true, color = c3(70, 150, 255) } },
				{ n = "CableBundle", shape = "Cylinder", axis = "up", a = 1.1, o = 0.3, w = 0.5, d = 0.5, y = 0, h = 14, color = c3(20, 20, 22), mat = "SmoothPlastic" },
			} },
			{ name = "crac", weight = 2, parts = {
				{ n = "CoolingUnit", a = 0, o = 0, w = 4.0, d = 2.0, y = 0, h = 5.6, color = c3(150, 154, 160), mat = "Metal" },
				{ n = "Grille", a = 0, o = 2.0, w = 3.2, d = 0.06, y = 3.6, h = 1.4, color = c3(60, 64, 70), mat = "Metal" },
			} },
			{ name = "breaker", weight = 2, parts = {
				{ n = "BreakerBox", a = 0, o = 0, w = 2.4, d = 0.5, y = 2.4, h = 3.2, color = c3(90, 96, 104), mat = "Metal" },
				{ n = "LooseCable", shape = "Cylinder", axis = "up", a = 0.8, o = 0.2, w = 0.25, d = 0.25, y = 5.6, h = 8.4, color = c3(22, 22, 24), mat = "SmoothPlastic" },
				{ n = "SparkHost", a = 0.8, o = 0.2, w = 0.3, d = 0.3, y = 5.3, h = 0.3, color = c3(22, 22, 24), mat = "SmoothPlastic", hidden = true,
					emitter = { rate = 5, life = { 0.3, 0.6 }, speed = { 2, 4 }, spread = 25, dir = "down", accel = { 0, -30, 0 }, size = 0.18,
						color = c3(190, 220, 255), lightEmission = 1 } },
			} },
		},
		runs = {
			{ chance = 0.7, piece = { name = "cabletray", parts = {
				{ n = "Tray", a = 0, o = 0.2, w = 22, d = 1.4, y = 12.4, h = 0.3, color = c3(80, 84, 90), mat = "Metal" },
				{ n = "Cables", shape = "Cylinder", axis = "along", a = 0, o = 0.5, w = 22, d = 0.6, y = 12.7, h = 0.6, color = c3(24, 24, 26), mat = "SmoothPlastic" },
			} } },
		},
		hangers = {
			{ chance = 0.5, piece = { name = "droopcable", parts = {
				{ n = "DroopCable", shape = "Cylinder", axis = "up", a = 0, o = 4.5, w = 0.25, d = 0.25, y = 8, h = 6, color = c3(22, 22, 24), mat = "SmoothPlastic" },
			} } },
		},
	},

	flooded = {
		wallMin = 3, wallMax = 4,
		film = { chance = 1, piece = { name = "water", room = true, parts = {
			{ n = "Water", min = { -13, 0, -13 }, max = { 13, 0.12, 13 }, color = c3(36, 62, 66), mat = "SmoothPlastic", alpha = 0.35 },
		} } },
		wall = {
			{ name = "pipes", weight = 3, parts = {
				{ n = "PipeRun", shape = "Cylinder", axis = "along", a = 0, o = 0.2, w = 4.6, d = 1.4, y = 0.6, h = 1.4, color = RUST, mat = "CorrodedMetal" },
				{ n = "Riser", shape = "Cylinder", axis = "up", a = 1.6, o = 0.3, w = 1.1, d = 1.1, y = 0, h = 14, color = c3(96, 66, 52), mat = "CorrodedMetal" },
				{ n = "Valve", shape = "Cylinder", axis = "out", a = -0.8, o = 1.6, w = 1.2, d = 0.2, y = 0.7, h = 1.2, color = VALVE_RED, mat = "Metal" },
			} },
			{ name = "streaks", weight = 2, parts = {
				{ n = "StreakA", a = -0.6, o = 0, w = 0.8, d = 0.04, y = 3, h = 6, color = RUST_DARK, mat = "CorrodedMetal" },
				{ n = "StreakB", a = 0.7, o = 0, w = 0.6, d = 0.04, y = 5, h = 4, color = RUST_DARK, mat = "CorrodedMetal" },
			} },
			{ name = "valvebank", weight = 2, parts = {
				{ n = "ValveBox", a = 0, o = 0, w = 3.0, d = 0.8, y = 2.5, h = 2.0, color = c3(70, 76, 72), mat = "Metal" },
				{ n = "WheelA", shape = "Cylinder", axis = "out", a = -0.7, o = 0.8, w = 0.9, d = 0.15, y = 3.0, h = 0.9, color = VALVE_RED, mat = "Metal" },
				{ n = "WheelB", shape = "Cylinder", axis = "out", a = 0.7, o = 0.8, w = 0.9, d = 0.15, y = 3.0, h = 0.9, color = VALVE_RED, mat = "Metal" },
			} },
			{ name = "pump", weight = 2, parts = {
				{ n = "PumpBody", shape = "Cylinder", axis = "along", a = 0, o = 0.2, w = 2.6, d = 1.8, y = 0, h = 1.8, color = c3(60, 70, 74), mat = "CorrodedMetal" },
				{ n = "PumpMotor", a = 1.6, o = 0.3, w = 1.0, d = 1.4, y = 0, h = 1.4, color = c3(44, 50, 54), mat = "Metal" },
			} },
		},
		runs = {
			{ chance = 1, piece = { name = "drippipe", parts = {
				{ n = "OverheadPipe", shape = "Cylinder", axis = "along", a = 0, o = 0.4, w = 22, d = 1.1, y = 12.2, h = 1.1, color = c3(96, 70, 58), mat = "CorrodedMetal" },
				{ n = "DripHost", a = 9, o = 0.6, w = 0.4, d = 0.4, y = 11.9, h = 0.2, color = RUST, mat = "SmoothPlastic", hidden = true,
					emitter = { rate = 6, life = { 0.6, 0.8 }, speed = { 0, 0.5 }, spread = 0, dir = "down", accel = { 0, -60, 0 }, size = 0.15,
						color = c3(150, 180, 190), lightEmission = 0 } },
			} } },
		},
		hangers = {},
	},

	reactor = {
		wallMin = 3, wallMax = 5,
		onDesk = { name = "readout", parts = {
			{ n = "Readout", a = 0, o = 0.4, w = 1.8, d = 0.2, y = 0, h = 1.0, color = c3(20, 22, 26), mat = "SmoothPlastic",
				screen = { kind = "console", glow = true, color = c3(255, 70, 60) } },
		} },
		wall = {
			{ name = "risers", weight = 3, parts = {
				{ n = "CoolantA", shape = "Cylinder", axis = "up", a = -0.9, o = 0.2, w = 1.4, d = 1.4, y = 0, h = 14, color = c3(70, 82, 96), mat = "Metal" },
				{ n = "CoolantB", shape = "Cylinder", axis = "up", a = 0.9, o = 0.2, w = 1.4, d = 1.4, y = 0, h = 14, color = c3(70, 82, 96), mat = "Metal" },
				{ n = "Band", a = 0, o = 0.1, w = 3.4, d = 1.6, y = 6, h = 0.4, color = HAZARD_YELLOW, mat = "Metal" },
			} },
			{ name = "hazardpanel", weight = 2, parts = {
				{ n = "HazardPanel", a = 0, o = 0, w = 3.0, d = 0.1, y = 1, h = 3, color = HAZARD_YELLOW, mat = "Metal",
					screen = { kind = "hazard" } },
			} },
			{ name = "beacon", weight = 2, parts = {
				{ n = "BeaconBase", a = 0, o = 0, w = 0.8, d = 0.5, y = 7.2, h = 0.4, color = c3(50, 50, 54), mat = "Metal" },
				{ n = "BeaconLamp", shape = "Ball", a = 0, o = 0.0, w = 0.7, d = 0.7, y = 7.6, h = 0.7, color = c3(255, 48, 40),
					mat = "SmoothPlastic", glow = true, anim = "pulse" },
			} },
			{ name = "console", weight = 2, parts = {
				{ n = "Console", a = 0, o = 0, w = 4.0, d = 2.0, y = 0, h = 3.0, color = c3(60, 64, 70), mat = "Metal" },
				{ n = "ConsoleScreen", a = 0, o = 0.3, w = 3.4, d = 0.2, y = 3.0, h = 1.4, color = c3(20, 22, 26), mat = "SmoothPlastic",
					screen = { kind = "console", glow = true, color = c3(255, 70, 60) } },
			} },
			{ name = "steamvent", weight = 2, parts = {
				{ n = "VentGrate", a = 0, o = 0, w = 1.6, d = 0.2, y = 0.6, h = 1.2, color = c3(80, 84, 90), mat = "Metal" },
				{ n = "SteamHost", a = 0, o = 0.2, w = 0.6, d = 0.3, y = 1.0, h = 0.4, color = c3(80, 84, 90), mat = "SmoothPlastic", hidden = true,
					emitter = { rate = 5, life = { 1.6, 2.2 }, speed = { 2, 3 }, spread = 12, dir = "up", accel = { 0, 1, 0 }, size = 1.4,
						color = c3(220, 222, 226), lightEmission = 0 } },
			} },
		},
		runs = {
			{ chance = 0.7, piece = { name = "coolantduct", parts = {
				{ n = "CoolantDuct", shape = "Cylinder", axis = "along", a = 0, o = 0.3, w = 22, d = 2.0, y = 11.6, h = 2.0, color = c3(76, 80, 86), mat = "Metal" },
			} } },
		},
		hangers = {},
	},

	biolab = {
		wallMin = 3, wallMax = 5,
		film = { chance = 0.5, piece = { name = "moss", parts = {
			{ n = "Moss", a = 0, o = 0.1, w = 4.4, d = 2.2, y = 0, h = 0.05, color = c3(46, 70, 40), mat = "Grass" },
		} } },
		onDesk = { name = "specimen", parts = {
			{ n = "Specimen", shape = "Cylinder", axis = "up", a = 0, o = 0.8, w = 0.9, d = 0.9, y = 0, h = 1.2, color = c3(60, 200, 190),
				mat = "SmoothPlastic", glow = true },
		} },
		wall = {
			{ name = "vines", weight = 3, parts = {
				{ n = "VineA", a = -1.2, o = 0, w = 0.35, d = 0.15, y = 0, h = 11, color = VINE, mat = "Grass" },
				{ n = "VineB", a = 0.2, o = 0, w = 0.3, d = 0.15, y = 2, h = 9.5, color = VINE_DARK, mat = "Grass" },
				{ n = "VineC", a = 1.4, o = 0, w = 0.3, d = 0.15, y = 0, h = 7, color = VINE, mat = "Grass" },
				{ n = "LeafClump", shape = "Ball", a = 0.8, o = 0, w = 1.2, d = 0.8, y = 6, h = 1.2, color = LEAF, mat = "Grass" },
			} },
			{ name = "tank", weight = 3, parts = {
				{ n = "TankBase", shape = "Cylinder", axis = "up", a = 0, o = 0.1, w = 2.3, d = 2.3, y = 0, h = 0.5, color = c3(70, 76, 80), mat = "Metal" },
				{ n = "TankGlass", shape = "Cylinder", axis = "up", a = 0, o = 0.2, w = 2.1, d = 2.1, y = 0.5, h = 4.6, color = c3(150, 190, 190),
					mat = "SmoothPlastic", alpha = 0.6 },
				{ n = "TankLiquid", shape = "Cylinder", axis = "up", a = 0, o = 0.35, w = 1.8, d = 1.8, y = 0.5, h = 2.8, color = c3(60, 200, 190),
					mat = "SmoothPlastic", glow = true },
				{ n = "TankCap", shape = "Cylinder", axis = "up", a = 0, o = 0.1, w = 2.3, d = 2.3, y = 5.1, h = 0.4, color = c3(70, 76, 80), mat = "Metal" },
			} },
			{ name = "fungus", weight = 2, parts = {
				{ n = "FungusA", shape = "Ball", a = -0.5, o = 0, w = 0.8, d = 0.5, y = 1.2, h = 0.8, color = c3(90, 200, 255), mat = "SmoothPlastic", glow = true },
				{ n = "FungusB", shape = "Ball", a = 0.4, o = 0, w = 0.6, d = 0.4, y = 1.8, h = 0.6, color = c3(120, 160, 255), mat = "SmoothPlastic", glow = true },
				{ n = "FungusC", shape = "Ball", a = 0, o = 0, w = 0.5, d = 0.35, y = 0.4, h = 0.5, color = c3(90, 200, 255), mat = "SmoothPlastic", glow = true },
			} },
			{ name = "cracked", weight = 1, parts = {
				{ n = "CrackedPanel", a = 0, o = 0, w = 2.6, d = 0.1, y = 1.5, h = 3.4, color = c3(70, 84, 66), mat = "Concrete" },
				{ n = "RootA", a = -0.3, o = 0.1, w = 0.3, d = 0.3, y = 0, h = 4.4, color = VINE_DARK, mat = "Grass" },
			} },
		},
		runs = {
			{ chance = 0.6, piece = { name = "ceilingvine", parts = {
				{ n = "CeilingVine", a = 0, o = 0, w = 22, d = 0.4, y = 13.4, h = 0.5, color = c3(48, 80, 42), mat = "Grass" },
			} } },
		},
		hangers = {
			{ chance = 0.6, piece = { name = "hangingvine", parts = {
				{ n = "HangingVine", a = 0, o = 4.0, w = 0.3, d = 0.3, y = 8.5, h = 5.5, color = VINE, mat = "Grass" },
				{ n = "Pod", shape = "Ball", a = 0, o = 3.8, w = 0.8, d = 0.8, y = 7.8, h = 0.8, color = c3(70, 150, 140), mat = "SmoothPlastic" },
			} } },
			{ chance = 0.6, piece = { name = "spores", parts = {
				{ n = "SporeHost", a = 0, o = 6, w = 1, d = 1, y = 11, h = 1, color = VINE, mat = "SmoothPlastic", hidden = true,
					emitter = { rate = 4, life = { 5, 7 }, speed = { 0.2, 0.5 }, spread = 40, dir = "up", accel = { 0, -0.12, 0 }, size = 0.25,
						color = c3(120, 230, 220), lightEmission = 0.6 } },
			} } },
		},
	},

	void = {
		wallMin = 3, wallMax = 5,
		film = { chance = 0.5, piece = { name = "ink", parts = {
			{ n = "Ink", a = 0, o = 0.2, w = 3.6, d = 2.2, y = 0, h = 0.05, color = c3(10, 8, 14), mat = "Slate" },
		} } },
		wall = {
			{ name = "glitch", weight = 3, parts = {
				{ n = "GlitchPanel", a = 0, o = 0, w = 3.2, d = 0.08, y = 2.4, h = 3.6, color = c3(14, 12, 18), mat = "Slate",
					screen = { kind = "glitch", glow = true, color = c3(220, 60, 255) } },
			} },
			{ name = "tear", weight = 3, parts = {
				{ n = "Tear", a = 0, o = 0, w = 0.8, d = 0.1, y = 1, h = 6.5, color = c3(6, 4, 10), mat = "Slate" },
				{ n = "TearEdgeL", a = -0.46, o = 0, w = 0.12, d = 0.14, y = 1, h = 6.5, color = c3(220, 60, 255), mat = "SmoothPlastic", glow = true, anim = "flicker" },
				{ n = "TearEdgeR", a = 0.46, o = 0, w = 0.12, d = 0.14, y = 1, h = 6.5, color = c3(220, 60, 255), mat = "SmoothPlastic", glow = true, anim = "flicker" },
			} },
			{ name = "monolith", weight = 2, parts = {
				{ n = "Monolith", a = 0, o = 0.2, w = 1.6, d = 1.2, y = 0, h = 5.8, color = c3(12, 10, 16), mat = "Basalt" },
			} },
			{ name = "motes", weight = 2, parts = {
				{ n = "Crack", a = 0, o = 0, w = 2.2, d = 0.06, y = 0, h = 0.6, color = c3(6, 4, 10), mat = "Slate" },
				{ n = "MoteHost", a = 0, o = 0.4, w = 0.8, d = 0.8, y = 0.2, h = 0.4, color = VOID_STONE, mat = "SmoothPlastic", hidden = true,
					emitter = { rate = 5, life = { 4, 6 }, speed = { 0.3, 0.7 }, spread = 20, dir = "up", accel = { 0, 0.1, 0 }, size = 0.3,
						color = c3(70, 40, 90), lightEmission = 0 } },
			} },
		},
		runs = {},
		hangers = {
			{ chance = 0.8, piece = { name = "debris", parts = {
				{ n = "DebrisA", a = -1.0, o = 4.0, w = 1.2, d = 1.2, y = 9.5, h = 1.6, color = VOID_STONE, mat = "Slate", anim = "bob" },
				{ n = "DebrisB", a = 1.2, o = 5.0, w = 0.8, d = 0.8, y = 11.0, h = 1.2, color = c3(34, 30, 44), mat = "Slate", anim = "bob" },
				{ n = "DebrisC", a = 0, o = 3.4, w = 1.6, d = 0.6, y = 12.0, h = 0.9, color = c3(28, 24, 36), mat = "Slate", anim = "bob" },
			} } },
		},
	},
}

function Dressing.kitNames(): { string }
	local out = {}
	for name in Dressing.KITS do table.insert(out, name) end
	table.sort(out)
	return out
end

-- The vertical travel an animated part may use, baked into its box (it only ever moves UP from its
-- resting place, so the checked box is exactly where it can be).
Dressing.BOB_STUDS = 0.4

-- One template part -> a room part. `lift` raises it (a monitor on a desk).
local function expand(env: any, inner: number, tmpl: any, wall: string, along: number, lift: number, pieceName: string, pieceId: number): any
	local mn, mx
	if tmpl.min then -- room-frame film
		mn, mx = table.clone(tmpl.min), table.clone(tmpl.max)
	else
		mn, mx = toRoom(inner, wall, along + tmpl.a, tmpl.o, tmpl.w, tmpl.d, tmpl.y + lift, tmpl.h)
	end
	if tmpl.anim == "bob" then mx[2] += Dressing.BOB_STUDS end
	local shape = tmpl.shape or "Block"
	local p = {
		name = tmpl.n,
		piece = pieceName,
		pieceId = pieceId,
		shape = shape,
		axis = if shape == "Cylinder" then roomAxis(wall, tmpl.axis or "up") else nil,
		min = mn,
		max = mx,
		color = tmpl.color,
		material = tmpl.mat or "SmoothPlastic",
		emissive = tmpl.glow == true,
		transparency = if tmpl.hidden then 1 else (tmpl.alpha or 0),
		hidden = tmpl.hidden == true,
		screen = tmpl.screen,
		emitter = tmpl.emitter,
		anim = tmpl.anim,
		face = if tmpl.min then nil else Dressing.FACE[wall],
		wall = if tmpl.min then nil else wall,
		class = nil :: string?,
		solid = false,
	}
	p.class = classOf(env, inner, mn, mx)
	-- Floor-standing wall furniture collides for THIS client only (you cannot walk through a filing
	-- cabinet); overhead pieces, films, hidden hosts and anything see-through do not.
	p.solid = p.class == "wall" and mn[2] < 0.5 and not p.hidden and (tmpl.alpha or 0) < 0.3
	return p
end

-- A small LCG: build() must be deterministic and must not touch the engine's Random.
local function lcg(seed: number): () -> number
	local s = seed % 4294967296
	return function(): number
		s = (1664525 * s + 1013904223) % 4294967296
		return s / 4294967296
	end
end

local function kitSeed(name: string, roomId: number, k: number): number
	local h = 0
	for i = 1, #name do h = (h * 131 + string.byte(name, i)) % 2147483647 end
	return math.floor(hash01(roomId, k, h, 90210) * 4294967295)
end

local function wallOfBox(inner: number, b: any): (string?, number)
	if b.max[1] >= inner - 0.05 then return "+x", (b.min[3] + b.max[3]) / 2 end
	if b.min[1] <= -inner + 0.05 then return "-x", (b.min[3] + b.max[3]) / 2 end
	if b.max[3] >= inner - 0.05 then return "+z", (b.min[1] + b.max[1]) / 2 end
	if b.min[3] <= -inner + 0.05 then return "-z", (b.min[1] + b.max[1]) / 2 end
	return nil, 0
end

-- The dressing of one room: a list of parts (see expand), in placement order. `props` are the room's
-- server props as { name, min, max } boxes; nothing else about the room is an input.
function Dressing.build(env: any, fac: any, kitName: string, roomId: number, k: number, props: { any }): { any }
	local kit = Dressing.KITS[kitName]
	assert(kit ~= nil, "Dressing.build: unknown kit " .. tostring(kitName))
	local inner = fac.CellSize / 2 - fac.WallThickness
	local rand = lcg(kitSeed(kitName, roomId, k))
	local out = {}
	local nextId = 0
	local screens, emitters = 0, 0

	local function tryPiece(piece: any, wall: string, along: number, lift: number): boolean
		nextId += 1
		local parts = {}
		local s, e = 0, 0
		for _, t in piece.parts do
			local p = expand(env, inner, t, wall, along, lift, piece.name, nextId)
			if p.screen then s += 1 end
			if p.emitter then e += 1 end
			table.insert(parts, p)
		end
		if #out + #parts > env.MaxPartsPerRoom then return false end
		if screens + s > env.MaxScreensPerRoom or emitters + e > 1 then return false end
		for _, p in parts do
			if not Dressing.partOk(env, fac, p, props) then return false end
			for _, q in out do
				if p.class ~= "film" and q.class ~= "film" and boxesOverlap(p, q, 0) then return false end
			end
		end
		for _, p in parts do table.insert(out, p) end
		screens += s
		emitters += e
		return true
	end

	-- 1. a floor film
	if kit.film and rand() < kit.film.chance then
		local wall = WALLS[1 + math.floor(rand() * 4)]
		local along = if rand() < 0.5 then -9.5 else 9.5
		tryPiece(kit.film.piece, wall, along, 0)
	end
	-- 2. on the room's desks
	if kit.onDesk then
		for _, pr in props do
			if pr.name == "Desk" and rand() < 0.8 then
				local wall, along = wallOfBox(inner, pr)
				if wall then tryPiece(kit.onDesk, wall, along, pr.max[2]) end
			end
		end
	end
	-- 3. long overhead runs along one wall. A rolled run tries the other walls when its wall is blocked (a
	-- chance-1 run such as the flooded kit's dripping pipe then really is in every room). The retries draw no
	-- random numbers, so a room whose first wall worked is dressed exactly as before.
	for _, run in kit.runs do
		if rand() < run.chance then
			local first = math.floor(rand() * 4)
			for n = 0, 3 do
				if tryPiece(run.piece, WALLS[1 + (first + n) % 4], 0, 0) then break end
			end
		end
	end
	-- 4. wall slots: two per wall, clear of every wall's middle
	local slots = {}
	for _, w in WALLS do
		table.insert(slots, { wall = w, along = -9.5 })
		table.insert(slots, { wall = w, along = 9.5 })
	end
	for i = #slots, 2, -1 do
		local j = 1 + math.floor(rand() * i)
		slots[i], slots[j] = slots[j], slots[i]
	end
	local total = 0
	for _, t in kit.wall do total += t.weight end
	local want = kit.wallMin + math.floor(rand() * (kit.wallMax - kit.wallMin + 1))
	local placed = 0
	for _, slot in slots do
		if placed >= want then break end
		for _ = 1, 3 do
			local r = rand() * total
			local pick = kit.wall[#kit.wall]
			for _, t in kit.wall do
				r -= t.weight
				if r < 0 then pick = t; break end
			end
			if tryPiece(pick, slot.wall, slot.along, 0) then
				placed += 1
				break
			end
		end
	end
	-- 5. things hanging into the upper room
	for _, hg in kit.hangers do
		if rand() < hg.chance then
			local slot = slots[1 + math.floor(rand() * #slots)]
			tryPiece(hg.piece, slot.wall, slot.along, 0)
		end
	end
	return out
end

return Dressing
