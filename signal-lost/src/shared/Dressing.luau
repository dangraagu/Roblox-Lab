--!strict
-- Dressing.luau — each environment band's dressing kit and the rules that keep the art fair (DESIGN.md §4.3).
-- PURE: it requires nothing; the config and EnvBands come in as arguments. EnvArt (client) turns its output into
-- local Parts; tests/EnvConfig.spec.luau holds every rule below against the real Config.
--
-- The art is client-side: the server builds the structure, this client dresses and recolours it. It must never
-- change what the player needs to read:
--   * nothing covers an item or a hatch: every piece hugs a wall (within 2.5 studs of its inner face), keeps 4 studs
--     (one hull) off every doorway's line, stays out of the item volume and off the consoles, mast and floor hatch;
--   * the four signal colours stay unique: nothing that glows comes within 30 degrees of hue of the salvage amber,
--     the canister cyan, or the red / green hatch lamps (unsaturated colours have no hue to confuse);
--   * a palette may change hue, not how much light a surface returns: 60-100 % of the server's in linear light;
--   * a grade never crushes the image.
-- Module-local coordinates: the floor's top face at the module centre is the origin.

local Dressing = {}

-- The exterior model's part count: planet + atmosphere 2, the dish 8, 30 relay beacons, the brag's beam 1, and
-- the exterior critters (Config.Budget.MaxCritters).
Dressing.EXTERIOR_PARTS = 2 + 8 + 30 + 1 + 3

-- Each kit: templates of wall-mounted pieces. along = length along the wall, height, depth = off the wall, lift =
-- bottom above the floor. color = { r, g, b } or a palette key ("wall" | "floor" | "trim"). glow = Neon.
Dressing.KITS = {
	docking = {
		{ name = "Locker", along = 3, height = 7, depth = 1.6, lift = 0, color = "trim", material = "Metal" },
		{ name = "Handrail", along = 9, height = 0.4, depth = 0.5, lift = 3.6, color = "trim", material = "Metal" },
		{ name = "Placard", along = 2.4, height = 1.4, depth = 0.2, lift = 6, color = { 220, 226, 236 }, material = "SmoothPlastic" },
		{ name = "Netting", along = 6, height = 4, depth = 0.3, lift = 1.5, color = { 120, 124, 130 }, material = "Fabric" },
		{ name = "ToolRack", along = 4, height = 3, depth = 1, lift = 2.5, color = "trim", material = "Metal" },
		{ name = "GuideLight", along = 6, height = 0.25, depth = 0.25, lift = 11, color = { 100, 120, 255 }, material = "Neon", glow = true },
	},
	hydro = {
		{ name = "PlantRack", along = 8, height = 5, depth = 2.2, lift = 0, color = { 70, 110, 70 }, material = "Grass" },
		{ name = "GrowLamp", along = 8, height = 0.3, depth = 0.8, lift = 7.5, color = { 230, 70, 230 }, material = "Neon", glow = true },
		{ name = "Vine", along = 1, height = 10, depth = 0.5, lift = 4, color = { 60, 120, 60 }, material = "Grass" },
		{ name = "SeedTray", along = 4, height = 0.6, depth = 1.8, lift = 2.6, color = { 90, 70, 50 }, material = "Wood" },
		{ name = "Bladder", along = 2, height = 2.6, depth = 1.6, lift = 0.6, color = { 150, 190, 210 }, material = "SmoothPlastic" },
	},
	cargo = {
		{ name = "CrateStack", along = 4, height = 4, depth = 2.4, lift = 0, color = { 140, 110, 60 }, material = "Wood" },
		{ name = "Container", along = 6, height = 5, depth = 2.5, lift = 0, color = "trim", material = "Metal" },
		{ name = "CargoNet", along = 5, height = 3.5, depth = 0.3, lift = 1, color = { 100, 100, 96 }, material = "Fabric" },
		{ name = "CeilingRail", along = 12, height = 0.4, depth = 0.6, lift = 16.5, color = { 80, 80, 86 }, material = "Metal" },
		{ name = "Stripes", along = 6, height = 0.6, depth = 0.2, lift = 0.4, color = { 180, 160, 60 }, material = "SmoothPlastic" },
	},
	reactor = {
		{ name = "CoolantPipe", along = 12, height = 0.8, depth = 0.8, lift = 12, color = { 110, 100, 96 }, material = "Metal" },
		{ name = "CoolantBand", along = 1, height = 1.2, depth = 1, lift = 11.8, color = { 130, 110, 255 }, material = "Neon", glow = true },
		{ name = "HeatVent", along = 3, height = 2, depth = 0.4, lift = 1, color = { 70, 60, 56 }, material = "Metal" },
		{ name = "Gauge", along = 1.6, height = 1.6, depth = 0.2, lift = 5, color = { 200, 196, 186 }, material = "SmoothPlastic" },
		{ name = "Tank", along = 3, height = 6, depth = 2.4, lift = 0, color = "trim", material = "Metal" },
	},
	array = {
		{ name = "Antenna", along = 1, height = 8, depth = 1, lift = 0, color = { 170, 176, 190 }, material = "Metal" },
		{ name = "Cables", along = 12, height = 0.6, depth = 0.6, lift = 14, color = { 40, 44, 60 }, material = "SmoothPlastic" },
		{ name = "Screen", along = 3, height = 2, depth = 0.2, lift = 5, color = { 120, 110, 255 }, material = "Neon", glow = true },
		{ name = "Rack", along = 3, height = 7, depth = 2, lift = 0, color = "trim", material = "Metal" },
		{ name = "Dishlet", along = 2, height = 2, depth = 1.2, lift = 8, color = { 200, 204, 216 }, material = "Metal" },
	},
	deep = {
		{ name = "IceSheet", along = 6, height = 5, depth = 0.3, lift = 2, color = { 200, 220, 235 }, material = "Ice" },
		{ name = "FrozenPool", along = 4, height = 0.2, depth = 2.2, lift = 0, color = { 180, 200, 215 }, material = "Ice" },
		{ name = "DeadScreen", along = 3, height = 2, depth = 0.2, lift = 5, color = { 20, 22, 26 }, material = "SmoothPlastic" },
		{ name = "Icicles", along = 5, height = 1.2, depth = 0.8, lift = 16.5, color = { 220, 235, 245 }, material = "Ice" },
		{ name = "Frost", along = 8, height = 0.3, depth = 1, lift = 0, color = { 230, 240, 250 }, material = "Snow" },
	},
	echo = {
		{ name = "FlickerPanel", along = 3, height = 4, depth = 0.2, lift = 3, color = { 180, 110, 255 }, material = "Neon", glow = true },
		{ name = "DarkCrate", along = 3, height = 3, depth = 2.2, lift = 0, color = { 30, 26, 40 }, material = "Metal" },
		{ name = "Cables", along = 10, height = 0.6, depth = 0.6, lift = 13, color = { 40, 34, 56 }, material = "SmoothPlastic" },
		{ name = "Residue", along = 6, height = 0.2, depth = 1.6, lift = 0, color = { 60, 40, 90 }, material = "Glass" },
	},
}

--============================================================================ bands

function Dressing.bandOf(env: any, k: number): number
	local idx = 1
	for i, b in env.Bands do
		if k >= b.first then idx = i end
	end
	return idx
end

-- p = (k - 1) + visited / n^2: the blend creeps forward as you explore (§4.1). `visited` and n are public.
function Dressing.progress(k: number, visited: number, n2: number): number
	local frac = if n2 > 0 then math.clamp(visited / n2, 0, 1) else 0
	return (k - 1) + frac * 0.999
end

-- The band whose kit a module wears: its sector's band, or (foreshadowing, facility-nightmare's rule) the NEXT
-- band's when hash01(k, module) is below that band's blend weight at the current progress.
function Dressing.roomBand(env: any, EnvBands: any, k: number, id: number, visited: number?, n2: number?): number
	local i = Dressing.bandOf(env, k)
	local p = Dressing.progress(k, visited or 0, n2 or 1)
	local _, j, t = EnvBands.locate(env.Bands, p)
	if j == i + 1 and t > 0 and EnvBands.hash01(k, id, 0, env.ForeshadowSeed) < t then
		return j
	end
	return i
end

--============================================================================ colour rules

local function lin(c: number): number
	local s = c / 255
	if s <= 0.04045 then return s / 12.92 end
	return ((s + 0.055) / 1.055) ^ 2.4
end
function Dressing.luminance(c: { number }): number
	return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end

function Dressing.paletteOk(env: any, palette: any): (boolean, string?)
	local server = { wall = env.ServerWall, floor = env.ServerFloor, trim = env.ServerTrim }
	for key, ref in server do
		local c = palette[key]
		if type(c) ~= "table" then return false, "no " .. key end
		local ratio = Dressing.luminance(c) / Dressing.luminance(ref)
		if ratio < 0.6 - 1e-9 or ratio > 1.0 + 1e-9 then
			return false, string.format("%s returns %.0f %% of the server's light (60-100 %% allowed)", key, ratio * 100)
		end
	end
	return true, nil
end

function Dressing.gradeOk(g: any): (boolean, string?)
	if type(g) ~= "table" then return false, "no grade" end
	for i = 1, 3 do
		if type(g.tint) ~= "table" or g.tint[i] < 190 then return false, "a tint channel below 190 darkens everything" end
	end
	if math.abs(g.brightness or 0) > 0.05 then return false, "brightness outside +-0.05" end
	if (g.contrast or 0) < 0 or (g.contrast or 0) > 0.3 then return false, "contrast outside 0..0.3" end
	if (g.saturation or 0) < -0.5 or (g.saturation or 0) > 0.2 then return false, "saturation outside -0.5..0.2" end
	return true, nil
end

-- HSV hue in degrees (0..360), with saturation and value.
function Dressing.hue(c: { number }): (number, number, number)
	local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 1e-9 then
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

-- May something that GLOWS in this colour stand in the station? Not within 30 degrees of hue of a signal colour.
function Dressing.hueOk(cfg: any, c: { number }): boolean
	local h, s, v = Dressing.hue(c)
	if s < 0.25 or v < 0.2 then return true end
	for _, sc in cfg.SignalColors do
		local hs = Dressing.hue(sc)
		local d = math.abs(h - hs)
		d = math.min(d, 360 - d)
		if d < 30 then return false end
	end
	return true
end

--============================================================================ placing a kit

-- Deterministic [0, 1) for (k, id, i, salt). Pure integer arithmetic under 2^53 (EnvBands.hash01's recipe).
local function h01(a: number, b: number, c: number, seed: number): number
	local hsh = (seed % 2147483647 + 2147483647) % 2147483647
	for _, v in { a, b, c } do
		local x = (math.floor(v) % 2147483647 + 2147483647) % 2147483647
		hsh = (hsh * 31 + x + 7919) % 2147483647
		hsh = (hsh * 48271) % 2147483647
		hsh = (hsh * 16807 + 12345) % 2147483647
	end
	return hsh / 2147483647
end

-- The pieces for one module: { name, size = {x, y, z}, pos = {x, y, z}, color = {r, g, b} | key, material, glow }.
-- sides = { E = open?, W = open?, N = open?, S = open? } (a hatch in that wall); keep = { { x, z, r } } footprints
-- to stay off (consoles, the mast, the floor hatch). Same inputs, same output.
function Dressing.build(cfg: any, kitId: string, id: number, k: number, sides: any, keep: { any }?): { any }
	local S = cfg.Station
	local kit = Dressing.KITS[kitId]
	if kit == nil then return {} end
	local inner = S.CellSize / 2 - S.WallThickness
	local doorHalf = S.HatchWidth / 2 + 4 -- the doorway plus a hull either side
	local maxN = cfg.Budget.MaxDressPartsPerModule
	local want = 5 + math.floor(h01(k, id, 1, 4099) * (maxN - 4))
	local out = {}
	local boxes = {}
	local attempts = 0
	while #out < want and attempts < 40 do
		attempts += 1
		local tpl = kit[1 + math.floor(h01(k, id, 100 + attempts, 7) * #kit)]
		local side = ({ "E", "W", "N", "S" })[1 + math.floor(h01(k, id, 200 + attempts, 11) * 4)]
		local len = tpl.along
		local lo, hi = -inner + len / 2, inner - len / 2
		local along = lo + (hi - lo) * h01(k, id, 300 + attempts, 13)
		local ok = true
		if sides and sides[side] then
			if along + len / 2 > -doorHalf and along - len / 2 < doorHalf then ok = false end
		end
		local alongX = side == "N" or side == "S"
		local sgn = if side == "E" or side == "N" then 1 else -1
		local normal = sgn * (inner - tpl.depth / 2)
		local px, pz = if alongX then along else normal, if alongX then normal else along
		local sx, sz = if alongX then len else tpl.depth, if alongX then tpl.depth else len
		local py = (tpl.lift or 0) + tpl.height / 2
		local box = { px - sx / 2, px + sx / 2, py - tpl.height / 2, py + tpl.height / 2, pz - sz / 2, pz + sz / 2 }
		if ok and keep then
			for _, kz in keep do
				local cx, cz = math.clamp(kz.x, box[1], box[2]), math.clamp(kz.z, box[5], box[6])
				if (cx - kz.x) ^ 2 + (cz - kz.z) ^ 2 < kz.r * kz.r then ok = false end
			end
		end
		if ok then
			for _, b in boxes do
				if box[1] < b[2] and b[1] < box[2] and box[3] < b[4] and b[3] < box[4] and box[5] < b[6] and b[5] < box[6] then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(boxes, box)
			table.insert(out, { name = tpl.name, size = { sx, tpl.height, sz }, pos = { px, py, pz }, color = tpl.color,
				material = tpl.material, glow = tpl.glow == true })
		end
	end
	return out
end

return Dressing
