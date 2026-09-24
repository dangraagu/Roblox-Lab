-- CaveArt.luau — Deep Vein's strata dressing, critters, weather and hazard models, built in code
-- (no assets). CLIENT ONLY: required by src/client/Cave.client.luau; the server never touches it.
--
-- Everything here is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off (a swing's click
-- passes straight through to the rock behind it, the camera never pops in front of a crystal, nothing
-- can be stood on or touched), CastShadow off. It lives in one workspace folder the client made, so it
-- never replicates and never reaches the server.
--
-- What it builds, and how it stays cheap (budgets measured in robloxemu/check_deepvein_cave.luau):
--   * pieces: set pieces tied to a band's weight — the pithead headframe and meadow at the surface,
--     the glowing floor of the core. Built the first time a band needs them, faded by weight,
--     UNPARENTED at weight 0, so a band you are not in costs nothing;
--   * decor: the inner faces of the bedrock walls, per layer (Strata.decorAt), only within
--     Env.DecorLayers of the miner, at most Env.DecorBuildPerFrame items built per frame, destroyed
--     when the miner moves away. Decor sits ON the wall, inside the first cell of rock: it appears
--     when the player digs through to the wall, like a find;
--   * critters: pooled per kind, flying only between cells the miner has actually stood in (known
--     open air), so a bat never flies through rock;
--   * weather: one host box around the camera, emitters created lazily, at most
--     Budget.MaxWeatherEmitters on and Budget.MaxEmitterRate particles/s (EnvBands.capRates);
--   * hazards: one model per kind, one ring (the shadow / the vent), one lane line;
--   * rest: one lantern beside a resting miner.
--
-- Dependencies arrive as arguments (a bare `require("./X")` is invalid in Roblox):
--   CaveArt.new(folder, rand, Config, EnvBands, Strata, Mine)

local CaveArt = {}
CaveArt.__index = CaveArt

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is X; this stands it on end

local function newPart(props)
	local p = Instance.new(props.class or "Part")
	p.Name = props.name or "CavePart"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Color = props.color or rgb(255, 255, 255)
	if props.shape then p.Shape = props.shape end
	p.Size = props.size or Vector3.new(1, 1, 1)
	p.Transparency = props.transparency or 0
	if props.reflectance then p.Reflectance = props.reflectance end
	return p
end

-- ─────────────────────────────────────────────────────────────── items: parts that fade together

local function newItem(name)
	return { name = name, entries = {}, lights = {}, emitters = {}, shown = false, weight = 0 }
end

local function addPart(item, props)
	local p = newPart(props)
	p.Transparency = 1
	local entry = { part = p, base = props.transparency or 0, offset = props.offset or CFrame.new(), lastT = 1 }
	table.insert(item.entries, entry)
	return p, entry
end

local function setWeight(item, w, folder)
	w = math.clamp(w, 0, 1)
	item.weight = w
	if w <= 0.01 then
		if item.shown then
			for _, e in item.entries do
				e.part.Parent = nil
				e.lastT = 1
			end
			for _, l in item.lights do l.Enabled = false end
			for _, pe in item.emitters do pe.Enabled = false end
			item.shown = false
		end
		return
	end
	if not item.shown then
		for _, e in item.entries do e.part.Parent = folder end
		item.shown = true
	end
	for _, e in item.entries do
		local t = 1 - (1 - e.base) * w
		if math.abs(t - e.lastT) > 0.02 or (w >= 0.99 and e.lastT ~= e.base) then
			e.part.Transparency = t
			e.lastT = t
		end
	end
	for _, l in item.lights do l.Enabled = w > 0.3 end
end

local function place(item, root)
	for _, e in item.entries do
		e.part.CFrame = root * e.offset
	end
end

-- ─────────────────────────────────────────────────────────────── set pieces (shaft-local)

-- The pithead: a timber headframe over the mouth with its sheave wheel and cable, lanterns on the rim,
-- grass on the rim tops and a meadow around the shaft, so the mouth reads as a mine entrance from the
-- outside (thumbnail shot 1) and the sky above the mouth has a silhouette in it from the inside.
local function buildHeadframe(item, cfg)
	local S = cfg.Mine.CellSize
	local gw = cfg.Mine.GridW
	local c = (gw + 1) / 2
	local far = (gw - c) * S + S / 2 -- outer edge of the ring (27)
	local rimTop = (cfg.Mine.RimCells - 1) * S + S / 2 -- 15
	local wallMid = far - S / 2 -- 24
	local wood = rgb(116, 80, 46)
	local topY = rimTop + 32
	for _, sx in { -7, 7 } do
		for _, sz in { -wallMid, wallMid } do
			addPart(item, { name = "HeadframePost", size = Vector3.new(1.6, topY - rimTop, 1.6), material = Enum.Material.Wood,
				color = wood, offset = CFrame.new(sx, (topY + rimTop) / 2, sz) })
		end
		addPart(item, { name = "HeadframeBeam", size = Vector3.new(1.6, 1.6, 2 * wallMid + 1.6), material = Enum.Material.Wood,
			color = wood, offset = CFrame.new(sx, topY + 0.8, 0) })
	end
	for _, sz in { -wallMid, wallMid } do
		addPart(item, { name = "HeadframeBrace", size = Vector3.new(15.6, 1.2, 1.2), material = Enum.Material.Wood,
			color = wood, offset = CFrame.new(0, rimTop + 16, sz) })
	end
	addPart(item, { name = "SheaveWheel", class = "Part", shape = Enum.PartType.Cylinder, size = Vector3.new(1.2, 9, 9),
		material = Enum.Material.Metal, color = rgb(70, 72, 80), offset = CFrame.new(0, topY + 5.6, 0) })
	addPart(item, { name = "Cable", size = Vector3.new(0.25, topY + 1.2 - (rimTop + 2), 0.25), material = Enum.Material.Metal,
		color = rgb(40, 40, 44), offset = CFrame.new(0, (topY + 1.2 + rimTop + 2) / 2, 0) })
	local lantern = nil
	for _, sx in { -12, 12 } do
		lantern = addPart(item, { name = "RimLantern", size = Vector3.new(1.2, 1.6, 1.2), material = Enum.Material.Neon,
			color = rgb(255, 196, 120), transparency = 0.1, offset = CFrame.new(sx, rimTop + 1, -wallMid) })
	end
	local light = Instance.new("PointLight")
	light.Name = "RimLanternLight"
	light.Color = rgb(255, 200, 130)
	light.Range = 34
	light.Brightness = 1.4
	light.Shadows = false
	light.Enabled = false
	light.Parent = lantern
	table.insert(item.lights, light)
	local grass = rgb(84, 122, 56)
	for _, wz in { -wallMid, wallMid } do
		addPart(item, { name = "RimGrass", size = Vector3.new(2 * far, 0.4, S), material = Enum.Material.Grass, color = grass,
			offset = CFrame.new(0, rimTop + 0.2, wz) })
	end
	for _, wx in { -wallMid, wallMid } do
		addPart(item, { name = "RimGrass", size = Vector3.new(S, 0.4, 2 * (far - S)), material = Enum.Material.Grass, color = grass,
			offset = CFrame.new(wx, rimTop + 0.2, 0) })
	end
	-- the meadow: a square annulus flush with the rim top, from the rim out to 90 studs
	local out = 90
	local meadow = rgb(78, 112, 52)
	addPart(item, { name = "Meadow", size = Vector3.new(2 * out, 1, out - far), material = Enum.Material.Grass, color = meadow,
		offset = CFrame.new(0, rimTop - 0.5, -(far + out) / 2) })
	addPart(item, { name = "Meadow", size = Vector3.new(2 * out, 1, out - far), material = Enum.Material.Grass, color = meadow,
		offset = CFrame.new(0, rimTop - 0.5, (far + out) / 2) })
	addPart(item, { name = "Meadow", size = Vector3.new(out - far, 1, 2 * far), material = Enum.Material.Grass, color = meadow,
		offset = CFrame.new(-(far + out) / 2, rimTop - 0.5, 0) })
	addPart(item, { name = "Meadow", size = Vector3.new(out - far, 1, 2 * far), material = Enum.Material.Grass, color = meadow,
		offset = CFrame.new((far + out) / 2, rimTop - 0.5, 0) })
end

-- The core: the bedrock floor glows through its cracks. Placed on the floor slab's top face.
local function buildCoreGlow(item, cfg)
	local w = (cfg.Mine.GridW - 2) * cfg.Mine.CellSize
	local plate = addPart(item, { name = "CoreGlow", size = Vector3.new(w - 0.4, 0.2, w - 0.4), material = Enum.Material.Neon,
		color = rgb(255, 96, 24), transparency = 0.35, offset = CFrame.new(0, 0.12, 0) })
	for i, a in { 0.3, -0.5, 1.2, -1.0 } do
		addPart(item, { name = "CoreCrack", size = Vector3.new(0.5, 0.25, w * (0.55 + 0.1 * i)), material = Enum.Material.Neon,
			color = rgb(255, 214, 120), transparency = 0.1, offset = CFrame.new((i - 2.5) * 6, 0.2, 0) * CFrame.Angles(0, a, 0) })
	end
	local light = Instance.new("PointLight")
	light.Name = "CoreLight"
	light.Color = rgb(255, 120, 40)
	light.Range = 40
	light.Brightness = 2.2
	light.Shadows = false
	light.Enabled = false
	light.Parent = plate
	table.insert(item.lights, light)
end

local PIECES = { headframe = buildHeadframe, coreglow = buildCoreGlow }

function CaveArt.hasPiece(id)
	return PIECES[id] ~= nil
end

-- ─────────────────────────────────────────────────────────────── wall decor (shaft-local)

-- Each builder returns parts described in FACE space: x along the face, y up, z out of the wall.
-- `g` is the kind's glow palette, Config.Env.DecorGlow[kind]: every Neon colour a builder uses comes from it,
-- because EnvConfig.spec holds that palette away from every ore that can sit beside the decor (review
-- 2026-09-24: ice-blue crystals were diamond, gold glyphs were gold) and check_deepvein_cave checks the
-- built Parts against it.
local function glow(g, i)
	local c = g and (g[i] or g[1])
	if c then return rgb(c[1], c[2], c[3]) end
	return rgb(255, 255, 255)
end
local WOOD = rgb(120, 84, 48)
local DECOR = {
	roots = function(s, r)
		return {
			{ size = Vector3.new(0.35, 4.2 * s, 0.35), pos = Vector3.new(0, 1.2, 0.25), material = Enum.Material.Wood, color = rgb(92, 64, 40) },
			{ size = Vector3.new(0.3, 3 * s, 0.3), pos = Vector3.new(0.9, 1.8, 0.3), material = Enum.Material.Wood, color = rgb(84, 58, 36),
				tilt = 0.25 },
			{ size = Vector3.new(0.25, 2.2 * s, 0.25), pos = Vector3.new(-0.8, 2.2, 0.25), material = Enum.Material.Wood, color = rgb(100, 70, 44),
				tilt = -0.3 },
		}
	end,
	seam = function(s, r)
		return { { size = Vector3.new(12 * s, 0.5, 0.15), pos = Vector3.new(0, (r - 0.5) * 2, 0.07), material = Enum.Material.Slate,
			color = rgb(68, 70, 78) } }
	end,
	pebbles = function(s, r)
		return {
			{ size = Vector3.new(0.9, 0.9, 0.9) * s, pos = Vector3.new(0, 0, 0.2), shape = Enum.PartType.Ball, color = rgb(196, 196, 202) },
			{ size = Vector3.new(0.6, 0.6, 0.6) * s, pos = Vector3.new(1.1, 0.5, 0.15), shape = Enum.PartType.Ball, color = rgb(214, 208, 196) },
			{ size = Vector3.new(0.7, 0.7, 0.7) * s, pos = Vector3.new(-0.9, -0.6, 0.15), shape = Enum.PartType.Ball, color = rgb(180, 184, 192) },
		}
	end,
	timber = function(s, r)
		return {
			{ size = Vector3.new(0.9, 5.6, 0.9), pos = Vector3.new(-2.3, 0, 0.45), material = Enum.Material.Wood, color = WOOD },
			{ size = Vector3.new(0.9, 5.6, 0.9), pos = Vector3.new(2.3, 0, 0.45), material = Enum.Material.Wood, color = WOOD },
			{ size = Vector3.new(5.6, 0.9, 1.0), pos = Vector3.new(0, 2.6, 0.5), material = Enum.Material.Wood, color = rgb(104, 72, 40) },
		}
	end,
	rust = function(s, r)
		return {
			{ size = Vector3.new(0.5, 4 * s, 0.12), pos = Vector3.new(0, 0, 0.06), color = rgb(150, 74, 40), tilt = 0.35 },
			{ size = Vector3.new(0.35, 3 * s, 0.12), pos = Vector3.new(0.9, -0.4, 0.06), color = rgb(132, 64, 36), tilt = 0.2 },
		}
	end,
	waterfall = function(s, r, g)
		return {
			{ size = Vector3.new(0.9, 11, 0.25), pos = Vector3.new(0, -2.6, 0.13), material = Enum.Material.Neon, color = glow(g, 1),
				transparency = 0.35 },
			{ size = Vector3.new(0.25, 3.2, 3.2), pos = Vector3.new(0, -8.1, 1.6), shape = Enum.PartType.Cylinder, material = Enum.Material.Neon,
				color = glow(g, 2), transparency = 0.45, flat = true },
		}
	end,
	wet = function(s, r)
		return { { size = Vector3.new(1.2, 5 * s, 0.1), pos = Vector3.new(0, 0, 0.05), color = rgb(40, 70, 92), reflectance = 0.35 } }
	end,
	shrooms = function(s, r, g)
		local cap = if r < 0.5 then glow(g, 1) else glow(g, 2)
		return {
			{ size = Vector3.new(0.3, 3.0 * s, 3.0 * s), pos = Vector3.new(0, 0.4, 0.4), shape = Enum.PartType.Cylinder,
				material = Enum.Material.Neon, color = cap, transparency = 0.1, flat = true },
			{ size = Vector3.new(0.3, 2.0 * s, 2.0 * s), pos = Vector3.new(1.3, -0.9, 0.3), shape = Enum.PartType.Cylinder,
				material = Enum.Material.Neon, color = cap, transparency = 0.15, flat = true },
			{ size = Vector3.new(0.3, 1.3 * s, 1.3 * s), pos = Vector3.new(-1.1, -1.5, 0.2), shape = Enum.PartType.Cylinder,
				material = Enum.Material.Neon, color = cap, transparency = 0.2, flat = true },
		}
	end,
	lavacrack = function(s, r, g)
		return {
			{ size = Vector3.new(0.3, 3.6 * s, 0.12), pos = Vector3.new(0, 0.6, 0.06), material = Enum.Material.Neon, color = glow(g, 1),
				tilt = 0.45 },
			{ size = Vector3.new(0.25, 2.8 * s, 0.12), pos = Vector3.new(0.9, -1.2, 0.06), material = Enum.Material.Neon, color = glow(g, 2),
				tilt = -0.4 },
		}
	end,
	lavafall = function(s, r, g)
		return {
			{ size = Vector3.new(1.1, 10, 0.3), pos = Vector3.new(0, -2.2, 0.15), material = Enum.Material.Neon, color = glow(g, 1) },
			{ size = Vector3.new(0.25, 3.6, 3.6), pos = Vector3.new(0, -7.3, 1.8), shape = Enum.PartType.Cylinder, material = Enum.Material.Neon,
				color = glow(g, 2), transparency = 0.15, flat = true },
		}
	end,
	crystals = function(s, r, g)
		local a = if r < 0.5 then glow(g, 1) else glow(g, 2)
		return {
			{ size = Vector3.new(0.8, 3.4 * s, 0.8), pos = Vector3.new(0, 0, 1.2), material = Enum.Material.Neon, color = a, transparency = 0.15,
				out = 0.9 },
			{ size = Vector3.new(0.6, 2.4 * s, 0.6), pos = Vector3.new(0.9, -0.5, 0.9), material = Enum.Material.Neon, color = a, transparency = 0.2,
				out = 0.6, tilt = -0.5 },
			{ size = Vector3.new(0.6, 2.2 * s, 0.6), pos = Vector3.new(-0.9, -0.3, 0.9), material = Enum.Material.Neon, color = a, transparency = 0.2,
				out = 0.6, tilt = 0.5 },
			{ size = Vector3.new(0.5, 1.6 * s, 0.5), pos = Vector3.new(0.2, 0.9, 0.7), material = Enum.Material.Glass, color = rgb(240, 230, 255),
				transparency = 0.3, out = 0.4, tilt = 0.2 },
		}
	end,
	ammonite = function(s, r)
		return {
			{ size = Vector3.new(0.2, 4.4 * s, 4.4 * s), pos = Vector3.new(0, 0, 0.1), shape = Enum.PartType.Cylinder, material = Enum.Material.Limestone,
				color = rgb(214, 200, 170), wall = true },
			{ size = Vector3.new(0.3, 2.8 * s, 2.8 * s), pos = Vector3.new(0.4 * s, 0.2 * s, 0.15), shape = Enum.PartType.Cylinder,
				material = Enum.Material.Limestone, color = rgb(176, 160, 130), wall = true },
			{ size = Vector3.new(0.4, 1.4 * s, 1.4 * s), pos = Vector3.new(0.7 * s, 0.1 * s, 0.2), shape = Enum.PartType.Cylinder,
				material = Enum.Material.Limestone, color = rgb(224, 212, 184), wall = true },
		}
	end,
	ribs = function(s, r)
		local bone = rgb(226, 214, 186)
		local out = {
			{ size = Vector3.new(7 * s, 0.5, 0.3), pos = Vector3.new(0, 1.2, 0.15), material = Enum.Material.Limestone, color = bone },
		}
		for i = 1, 4 do
			table.insert(out, { size = Vector3.new(0.35, 3.2 * s, 0.3), pos = Vector3.new((i - 2.5) * 1.6 * s, -0.3, 0.15),
				material = Enum.Material.Limestone, color = bone, tilt = 0.15 * (i - 2.5) })
		end
		return out
	end,
	arch = function(s, r, g)
		local stone = rgb(182, 160, 120)
		return {
			{ size = Vector3.new(1.2, 5, 0.8), pos = Vector3.new(-2.2, -0.3, 0.4), material = Enum.Material.Sandstone, color = stone },
			{ size = Vector3.new(1.2, 5, 0.8), pos = Vector3.new(2.2, -0.3, 0.4), material = Enum.Material.Sandstone, color = stone },
			{ size = Vector3.new(5.8, 1, 0.9), pos = Vector3.new(0, 2.6, 0.45), material = Enum.Material.Sandstone, color = rgb(196, 174, 132) },
			{ size = Vector3.new(0.8, 0.8, 0.1), pos = Vector3.new(0, 2.6, 0.95), material = Enum.Material.Neon, color = glow(g, 1) },
		}
	end,
	glyphs = function(s, r, g)
		local lit = glow(g, 1)
		return {
			{ size = Vector3.new(0.7, 0.9, 0.08), pos = Vector3.new(-1.1, 0, 0.04), material = Enum.Material.Neon, color = lit },
			{ size = Vector3.new(0.5, 0.9, 0.08), pos = Vector3.new(0, 0.2, 0.04), material = Enum.Material.Neon, color = lit },
			{ size = Vector3.new(0.7, 0.6, 0.08), pos = Vector3.new(1.1, -0.1, 0.04), material = Enum.Material.Neon, color = lit },
		}
	end,
	shards = function(s, r, g)
		-- black volcanic glass spiking out of the wall, lit along one edge
		local glass = rgb(22, 18, 30)
		local edge = glow(g, 1)
		return {
			{ size = Vector3.new(0.7, 3.6 * s, 0.7), pos = Vector3.new(0, 0, 1.2), material = Enum.Material.Glass, color = glass,
				transparency = 0.05, out = 0.8 },
			{ size = Vector3.new(0.5, 2.6 * s, 0.5), pos = Vector3.new(1.0, -0.4, 0.9), material = Enum.Material.Glass, color = glass,
				transparency = 0.05, out = 0.6, tilt = -0.45 },
			{ size = Vector3.new(0.12, 3.0 * s, 0.12), pos = Vector3.new(0.3, 0.1, 1.3), material = Enum.Material.Neon, color = edge,
				transparency = 0.1, out = 0.8 },
		}
	end,
	runes = function(s, r, g)
		local hot = glow(g, 1)
		return {
			{ size = Vector3.new(0.35, 1.6, 0.1), pos = Vector3.new(-0.9, 0, 0.05), material = Enum.Material.Neon, color = hot, tilt = 0.4 },
			{ size = Vector3.new(0.35, 1.6, 0.1), pos = Vector3.new(0, 0, 0.05), material = Enum.Material.Neon, color = hot },
			{ size = Vector3.new(0.35, 1.6, 0.1), pos = Vector3.new(0.9, 0, 0.05), material = Enum.Material.Neon, color = hot, tilt = -0.4 },
		}
	end,
}
CaveArt.DECOR_MAX_PARTS = 5

function CaveArt.hasDecor(kind)
	return DECOR[kind] ~= nil
end

-- ─────────────────────────────────────────────────────────────── critters (world space)

local CRITTERS = {
	fireflies = { parts = { { size = Vector3.new(0.3, 0.3, 0.3), shape = Enum.PartType.Ball, material = Enum.Material.Neon, color = rgb(220, 255, 120) } },
		blink = true, drift = 1.6 },
	moths = { parts = { { size = Vector3.new(0.3, 0.3, 0.6), color = rgb(200, 190, 160) },
		{ size = Vector3.new(1.2, 0.05, 0.6), color = rgb(226, 216, 186), transparency = 0.2, wing = true } }, drift = 1.4 },
	bats = { parts = { { size = Vector3.new(0.7, 0.7, 0.7), shape = Enum.PartType.Ball, color = rgb(40, 32, 36) },
		{ size = Vector3.new(1.2, 0.08, 0.7), color = rgb(52, 42, 48), wing = 1 },
		{ size = Vector3.new(1.2, 0.08, 0.7), color = rgb(52, 42, 48), wing = -1 } }, drift = 2.2, flap = 14 },
	glowmoths = { parts = { { size = Vector3.new(0.3, 0.3, 0.5), material = Enum.Material.Neon, color = rgb(80, 240, 210) },
		{ size = Vector3.new(1.0, 0.05, 0.5), material = Enum.Material.Neon, color = rgb(150, 255, 230), transparency = 0.35, wing = true } },
		drift = 1.4 },
	cinders = { parts = { { size = Vector3.new(0.35, 0.35, 0.35), shape = Enum.PartType.Ball, material = Enum.Material.Neon,
		color = rgb(255, 140, 40) } }, drift = 1.0, rise = true },
	wisps = { parts = { { size = Vector3.new(0.6, 0.6, 0.6), shape = Enum.PartType.Ball, material = Enum.Material.Neon, color = rgb(190, 214, 255) },
		{ size = Vector3.new(1.4, 1.4, 1.4), shape = Enum.PartType.Ball, material = Enum.Material.Neon, color = rgb(160, 190, 255),
			transparency = 0.8 } }, drift = 1.0 },
}

function CaveArt.hasCritter(kind)
	return CRITTERS[kind] ~= nil
end

-- ─────────────────────────────────────────────────────────────── weather

local WEATHER = {
	motes = { Color = { 255, 214, 150 }, Size = 0.14, Transparency = 0.4, Lifetime = { 6, 10 }, Speed = { 0.2, 0.6 },
		LightEmission = 0.6, Acceleration = Vector3.new(0, 0.05, 0) },
	dust = { Color = { 190, 190, 200 }, Size = 0.12, Transparency = 0.5, Lifetime = { 6, 10 }, Speed = { 0.1, 0.4 },
		LightEmission = 0.2, Acceleration = Vector3.new(0, -0.3, 0) },
	rust = { Color = { 230, 130, 70 }, Size = 0.12, Transparency = 0.35, Lifetime = { 3, 6 }, Speed = { 0.1, 0.5 },
		LightEmission = 0.7, Acceleration = Vector3.new(0, -0.2, 0) },
	drips = { Color = { 150, 210, 255 }, Size = 0.1, Transparency = 0.3, Lifetime = { 0.8, 1.2 }, Speed = { 18, 24 },
		LightEmission = 0.4, Acceleration = Vector3.new(0, -30, 0), streak = true },
	spores = { Color = { 110, 255, 210 }, Size = 0.16, Transparency = 0.3, Lifetime = { 5, 9 }, Speed = { 0.2, 0.7 },
		LightEmission = 1, Acceleration = Vector3.new(0, 0.3, 0) },
	embers = { Color = { 255, 140, 50 }, Size = 0.18, Transparency = 0.2, Lifetime = { 2, 4 }, Speed = { 2, 5 },
		LightEmission = 1, Acceleration = Vector3.new(0, 3, 0) },
	glints = { Color = { 230, 210, 255 }, Size = 0.2, Transparency = 0.25, Lifetime = { 1, 2 }, Speed = { 0, 0.3 },
		LightEmission = 1, Acceleration = Vector3.new(0, 0, 0) },
	sand = { Color = { 224, 200, 150 }, Size = 0.1, Transparency = 0.4, Lifetime = { 3, 5 }, Speed = { 0.5, 1.5 },
		LightEmission = 0.3, Acceleration = Vector3.new(0, -2, 0) },
	void = { Color = { 180, 120, 255 }, Size = 0.16, Transparency = 0.25, Lifetime = { 2, 4 }, Speed = { 0.1, 0.6 },
		LightEmission = 1, Acceleration = Vector3.new(0, -0.1, 0) },
	sparks = { Color = { 255, 196, 90 }, Size = 0.12, Transparency = 0.1, Lifetime = { 0.8, 1.6 }, Speed = { 8, 14 },
		LightEmission = 1, Acceleration = Vector3.new(0, 6, 0), streak = true, up = true },
}

function CaveArt.hasWeather(kind)
	return WEATHER[kind] ~= nil
end

-- ─────────────────────────────────────────────────────────────── hazards

-- Glowing hazard models use the strata's decor palette (Config.Env.DecorGlow), so a hazard poking out of the
-- roof never reads as ore either (review 2026-09-24: the relic's plate was gold, the crystal obsidian-violet).
local HAZARDS = {
	rock = { label = "FALLING ROCK", parts = { { size = Vector3.new(2.6, 2.6, 2.6), shape = Enum.PartType.Ball, material = Enum.Material.Slate,
		color = rgb(96, 96, 104) } }, trickle = { 150, 140, 130 } },
	stalactite = { label = "STALACTITE", parts = { { size = Vector3.new(1.1, 3.8, 1.1), material = Enum.Material.Rock,
		color = rgb(110, 124, 136) } }, trickle = { 150, 200, 240 } },
	lava = { label = "LAVA DRIP", parts = { { size = Vector3.new(2.0, 2.0, 2.0), shape = Enum.PartType.Ball, material = Enum.Material.Neon,
		color = rgb(255, 86, 22) } }, trickle = { 255, 140, 50 } },
	crystal = { label = "FALLING CRYSTAL", parts = { { size = Vector3.new(1.2, 3.4, 1.2), material = Enum.Material.Neon,
		color = rgb(214, 140, 255), transparency = 0.1 } }, trickle = { 220, 200, 255 } },
	relic = { label = "CRUMBLING RUIN", parts = { { size = Vector3.new(2.4, 2.0, 2.4), material = Enum.Material.Sandstone,
		color = rgb(182, 160, 120) }, { size = Vector3.new(0.9, 0.9, 0.1), material = Enum.Material.Neon, color = rgb(60, 230, 190),
		offset = CFrame.new(0, 0, -1.25) } }, trickle = { 220, 200, 150 } },
	shard = { label = "FALLING SHARD", parts = { { size = Vector3.new(1.0, 3.6, 1.0), material = Enum.Material.Glass,
		color = rgb(28, 22, 40) }, { size = Vector3.new(0.14, 3.2, 0.14), material = Enum.Material.Neon, color = rgb(230, 140, 255),
		offset = CFrame.new(0.45, 0, 0) } }, trickle = { 190, 150, 255 } },
	steam = { label = "STEAM VENT", parts = { { size = Vector3.new(7, 2.2, 2.2), shape = Enum.PartType.Cylinder, material = Enum.Material.SmoothPlastic,
		color = rgb(230, 240, 255), transparency = 0.45, jet = true } }, trickle = { 235, 240, 250 }, vent = true },
	magma = { label = "MAGMA BURST", parts = { { size = Vector3.new(7, 2.2, 2.2), shape = Enum.PartType.Cylinder, material = Enum.Material.Neon,
		color = rgb(255, 110, 30), transparency = 0.2, jet = true } }, trickle = { 255, 150, 60 }, vent = true },
}

function CaveArt.hazardKinds()
	local out = {}
	for k in HAZARDS do table.insert(out, k) end
	table.sort(out)
	return out
end

function CaveArt.hazardLabel(kind)
	local h = HAZARDS[kind]
	return if h then h.label else string.upper(tostring(kind))
end

-- Half the height of a hazard's model: how far under a ceiling its centre has to hang to be in view.
function CaveArt.hazardHalfHeight(kind)
	local h = HAZARDS[kind]
	if h == nil then return 1 end
	local half = 0
	for _, d in h.parts do
		half = math.max(half, d.size.Y / 2)
	end
	return half
end

function CaveArt.hazardFromBelow(kind)
	local h = HAZARDS[kind]
	return h ~= nil and h.vent == true
end

-- ─────────────────────────────────────────────────────────────── constructor

function CaveArt.new(folder, rand, Config, EnvBands, Strata, Mine)
	local self = setmetatable({}, CaveArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.EnvBands = EnvBands
	self.Strata = Strata
	self.Mine = Mine
	self.pieces = {}
	self.decor = {} -- [layer] = { parts }
	self.decorQueue = {}
	self.critters = {} -- [kind] = { list of critter }
	self.hazardModels = {}
	self.origin = nil
	self.floorTop = nil
	self.faces = Strata.wallFaces(Config)
	return self
end

-- The shaft this client decorates: its world origin (the centre of the mouth at y = 0) and the top of
-- its bedrock floor. nil when the shaft is not known (between a rebirth's teardown and rebuild).
function CaveArt:setShaft(origin, floorTop)
	local moved = (origin == nil) ~= (self.origin == nil)
		or (origin ~= nil and self.origin ~= nil and (origin - self.origin).Magnitude > 0.01)
	self.origin = origin
	self.floorTop = floorTop
	if moved then
		self:clearDecor()
		for _, item in self.pieces do setWeight(item, 0, self.folder) end
	end
end

function CaveArt:updatePiece(id, w)
	local build = PIECES[id]
	if build == nil then return end
	local item = self.pieces[id]
	if self.origin == nil then w = 0 end
	if item == nil then
		if w <= 0.01 then return end
		item = newItem(id)
		build(item, self.cfg)
		self.pieces[id] = item
	end
	setWeight(item, w, self.folder)
	if item.shown then
		local root = CFrame.new(self.origin)
		if id == "coreglow" then
			if self.floorTop == nil then
				setWeight(item, 0, self.folder)
				return
			end
			root = CFrame.new(self.origin.X, self.floorTop, self.origin.Z)
		end
		if item.placedAt ~= root then
			place(item, root)
			item.placedAt = root
		end
	end
end

-- ── decor ──

function CaveArt:clearDecor()
	for _, parts in self.decor do
		for _, p in parts do p:Destroy() end
	end
	self.decor = {}
	self.decorQueue = {}
	self.decorCentre = nil
end

local function faceCFrame(face, u, y, out)
	local right = Vector3.new(face.ux, 0, face.uz)
	local n = Vector3.new(face.nx, 0, face.nz)
	local pos = Vector3.new(face.x, 0, face.z) + right * u + n * out + Vector3.new(0, y, 0)
	return CFrame.fromMatrix(pos, right, Vector3.new(0, 1, 0), n)
end

function CaveArt:buildDecorLayer(layer)
	local items = self.Strata.decorAt(self.cfg, self.EnvBands, layer, self.cfg.Env.DecorSeed)
	local parts = {}
	local S = self.cfg.Mine.CellSize
	local yc = -(layer - 0.5) * S
	for _, item in items do
		local builder = DECOR[item.kind]
		local face = self.faces[item.wall]
		if builder and face then
			for _, d in builder(item.scale, item.roll, (self.cfg.Env.DecorGlow or {})[item.kind]) do
				local p = newPart({ name = "Decor_" .. item.kind, size = d.size, material = d.material, color = d.color, shape = d.shape,
					transparency = d.transparency, reflectance = d.reflectance })
				local base = faceCFrame(face, item.u + d.pos.X, yc + item.v * S + d.pos.Y, d.pos.Z)
				local cf = base
				if d.flat then
					-- a disc lying flat against the floor of the layer (a pool) or sticking out of the wall (a fungus shelf)
					cf = base * UPRIGHT
				elseif d.wall then
					cf = base * CFrame.Angles(0, math.pi / 2, 0) -- a disc facing out of the wall (an ammonite)
				end
				if d.tilt then cf = cf * CFrame.Angles(0, 0, d.tilt) end
				if d.out then cf = cf * CFrame.Angles(-d.out, 0, 0) end
				p.CFrame = CFrame.new(self.origin) * cf
				p.Parent = self.folder
				table.insert(parts, p)
			end
		end
	end
	self.decor[layer] = parts
end

-- Keep decor for the layers within DecorLayers of `centre`; build at most DecorBuildPerFrame layers a
-- frame (nearest first), destroy the rest at once.
function CaveArt:updateDecor(centre)
	if self.origin == nil then return end
	local range = self.cfg.Env.DecorLayers
	for layer, parts in self.decor do
		if math.abs(layer - centre) > range then
			for _, p in parts do p:Destroy() end
			self.decor[layer] = nil
		end
	end
	if self.decorCentre ~= centre then
		self.decorCentre = centre
		local q = {}
		for d = 0, range do
			for _, layer in (if d == 0 then { centre } else { centre + d, centre - d }) do
				if layer >= 1 and self.decor[layer] == nil then table.insert(q, layer) end
			end
		end
		self.decorQueue = q
	end
	local built = 0
	while built < self.cfg.Env.DecorBuildPerFrame and #self.decorQueue > 0 do
		local layer = table.remove(self.decorQueue, 1)
		if self.decor[layer] == nil and math.abs(layer - centre) <= range then
			self:buildDecorLayer(layer)
			built += 1
		end
	end
end

-- ── critters ──

local function buildCritter(kind)
	local def = CRITTERS[kind]
	local c = { kind = kind, parts = {}, t = 0 }
	for _, d in def.parts do
		local p = newPart({ name = "Critter_" .. kind, size = d.size, material = d.material, color = d.color, shape = d.shape,
			transparency = d.transparency })
		table.insert(c.parts, { part = p, def = d })
	end
	return c
end

-- `crumbs` = world positions (cell centres) the miner has stood in, newest last: known open air.
-- Each critter hops between neighbouring crumbs and drifts a little around the one it is at.
function CaveArt:updateCritters(desired, crumbs, dt, now)
	local rand = self.rand
	for kind, list in self.critters do
		local want = desired[kind] or 0
		for i = #list, want + 1, -1 do
			for _, e in list[i].parts do e.part:Destroy() end
			table.remove(list, i)
		end
	end
	if #crumbs == 0 then
		for _, list in self.critters do
			for _, c in list do
				for _, e in c.parts do e.part.Parent = nil end
			end
		end
		return
	end
	for kind, want in desired do
		if CRITTERS[kind] then
			local list = self.critters[kind]
			if list == nil then
				list = {}
				self.critters[kind] = list
			end
			-- at most one new critter per kind per frame
			if #list < want then
				local c = buildCritter(kind)
				c.at = 1 + math.floor(rand() * #crumbs) % #crumbs
				c.to = c.at
				c.hop = 0
				c.phase = rand() * 10
				table.insert(list, c)
			end
			local def = CRITTERS[kind]
			for _, c in list do
				c.t += dt
				if c.at > #crumbs then c.at = #crumbs end
				if c.to > #crumbs then c.to = #crumbs end
				c.hop -= dt
				if c.hop <= 0 then
					c.at = c.to
					local step = if rand() < 0.5 then -1 else 1
					c.to = math.clamp(c.at + step, 1, #crumbs)
					c.hop = 1.5 + rand() * 2.5
				end
				local a, b = crumbs[c.at], crumbs[c.to]
				local k = math.clamp(1 - c.hop / 1.5, 0, 1)
				local base = a:Lerp(b, k * k * (3 - 2 * k))
				local ph = c.phase + c.t
				local dr = def.drift
				local off = Vector3.new(math.sin(ph * 0.9) * dr, 1.2 + math.sin(ph * 1.3) * 0.8, math.cos(ph * 0.7) * dr)
				-- a cinder rises through the cell and starts again at the bottom, never past the cell's top
				if def.rise then off = Vector3.new(off.X * 0.5, ((c.t * 1.2 + c.phase) % 4.4) - 2, off.Z * 0.5) end
				local heading = b - a
				local cf = CFrame.new(base + off)
				if heading.Magnitude > 0.1 then cf = CFrame.lookAt(base + off, base + off + Vector3.new(heading.X, 0, heading.Z) + Vector3.new(0, 0, 0.001)) end
				for _, e in c.parts do
					local d = e.def
					local pcf = cf
					if d.wing then
						local flap = math.sin(now * (def.flap or 9) + c.phase) * 0.7
						local side = if type(d.wing) == "number" then d.wing else 1
						pcf = cf * CFrame.new(side * (if type(d.wing) == "number" then 0.8 else 0), 0, 0) * CFrame.Angles(0, 0, side * flap)
					end
					e.part.CFrame = pcf
					if def.blink then
						local tr = 0.15 + 0.8 * (0.5 + 0.5 * math.sin(now * 2.2 + c.phase * 3))
						if math.abs((e.lastT or -1) - tr) > 0.05 then
							e.part.Transparency = tr
							e.lastT = tr
						end
					end
					if e.part.Parent ~= self.folder then e.part.Parent = self.folder end
				end
			end
		end
	end
end

function CaveArt:critterCount(kind)
	return #(self.critters[kind] or {})
end

-- ── weather ──

function CaveArt:updateWeather(rates, cam)
	if self.weatherHost == nil then
		self.weatherHost = newPart({ name = "WeatherHost", size = Vector3.new(28, 18, 28), transparency = 1 })
		self.emitters = {}
	end
	local budget = self.cfg.Budget or {}
	local capped = self.EnvBands.capRates(rates, math.min(budget.MaxWeatherEmitters or 2, budget.MaxEmitters or 2),
		budget.MaxEmitterRate or 60, self.cfg.Env.WeatherMinRate or 0.05)
	local anyOn = false
	for kind, def in WEATHER do
		local rate = capped[kind] or 0
		local pe = self.emitters[kind]
		if pe == nil and rate > 0 then
			pe = Instance.new("ParticleEmitter")
			pe.Name = "Weather_" .. kind
			pe.Color = ColorSequence.new(rgb(def.Color[1], def.Color[2], def.Color[3]))
			pe.Size = NumberSequence.new(def.Size)
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.15, def.Transparency),
				NumberSequenceKeypoint.new(0.85, def.Transparency),
				NumberSequenceKeypoint.new(1, 1),
			})
			pe.Lifetime = NumberRange.new(def.Lifetime[1], def.Lifetime[2])
			pe.Speed = NumberRange.new(def.Speed[1], def.Speed[2])
			pe.LightEmission = def.LightEmission
			pe.Acceleration = def.Acceleration
			pe.SpreadAngle = if def.streak then Vector2.new(4, 4) else Vector2.new(180, 180)
			pe.EmissionDirection = if def.up then Enum.NormalId.Top elseif def.streak then Enum.NormalId.Bottom else Enum.NormalId.Top
			if def.streak then pe.Orientation = Enum.ParticleOrientation.VelocityParallel end
			pe.Shape = Enum.ParticleEmitterShape.Box
			pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			pe.Rate = 0
			pe.Enabled = false
			pe.Parent = self.weatherHost
			self.emitters[kind] = pe
		end
		if pe then
			local on = rate > 0
			pe.Enabled = on
			if math.abs((pe.Rate or 0) - rate) > 0.25 or (not on and pe.Rate ~= 0) then
				pe.Rate = if on then rate else 0
			end
			anyOn = anyOn or on
		end
	end
	if anyOn then
		self.weatherHost.Parent = self.folder
		self.weatherHost.CFrame = CFrame.new(cam)
	else
		self.weatherHost.Parent = nil
	end
end

-- ── hazards ──

function CaveArt:hazardModel(kind)
	local item = self.hazardModels[kind]
	if item then return item end
	local def = HAZARDS[kind] or HAZARDS.rock
	item = newItem("Hazard_" .. kind)
	local main = nil
	for _, d in def.parts do
		local p = addPart(item, { name = "Hazard_" .. kind, size = d.size, material = d.material, color = d.color, shape = d.shape,
			transparency = d.transparency, offset = d.offset })
		main = main or p
		if d.jet then item.jet = item.entries[#item.entries] end
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "HazardMarker"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromScale(4, 4)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.LightInfluence = 0
	bb.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Text = "⚠️"
	label.Parent = bb
	bb.Parent = main
	item.billboard = bb
	local light = Instance.new("PointLight")
	light.Name = "HazardBlink"
	light.Color = rgb(255, 60, 40)
	light.Range = 14
	light.Brightness = 2
	light.Shadows = false
	light.Enabled = false
	light.Parent = main
	table.insert(item.lights, light)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "HazardTrickle"
	pe.Color = ColorSequence.new(rgb(def.trickle[1], def.trickle[2], def.trickle[3]))
	pe.Size = NumberSequence.new(if def.vent then 0.8 else 0.18)
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(if def.vent then 0.8 else 1.2, if def.vent then 1.4 else 1.8)
	pe.Speed = NumberRange.new(if def.vent then 3 else 0.5, if def.vent then 6 else 2)
	pe.Acceleration = Vector3.new(0, if def.vent then 2 else -20, 0)
	pe.EmissionDirection = if def.vent then Enum.NormalId.Top else Enum.NormalId.Bottom
	pe.LightEmission = if kind == "lava" or kind == "magma" then 1 else 0.2
	pe.Rate = 0
	pe.Enabled = false
	pe.Parent = main
	table.insert(item.emitters, pe)
	item.main = main
	item.def = def
	self.hazardModels[kind] = item
	return item
end

function CaveArt:ringItem()
	if self.ring then return self.ring end
	local ring = newItem("HazardRing")
	addPart(ring, { name = "HazardShadow", shape = Enum.PartType.Cylinder, size = Vector3.new(0.12, 6, 6), color = rgb(10, 8, 8),
		transparency = 0.45 })
	addPart(ring, { name = "HazardRingEdge", shape = Enum.PartType.Cylinder, size = Vector3.new(0.1, 6.4, 6.4), material = Enum.Material.Neon,
		color = rgb(255, 210, 60), transparency = 0.25 })
	addPart(ring, { name = "HazardLane", size = Vector3.new(0.25, 1, 0.25), material = Enum.Material.Neon, color = rgb(255, 210, 60),
		transparency = 0.5 })
	self.ring = ring
	return ring
end

-- plan: the Hazards plan; pos: where it is now; zone: Hazards.zone; feetY: the floor under the miner.
function CaveArt:showHazard(plan, pos, now, zone, feetY)
	local item = self:hazardModel(plan.kind)
	setWeight(item, 1, self.folder)
	local def = item.def
	item.billboard.Enabled = not plan.locked or (math.floor(now * 6) % 2 == 0)
	item.lights[1].Enabled = math.floor(now * 4) % 2 == 0
	local hanging = plan.hang ~= nil and plan.t < plan.hang
	local pe = item.emitters[1]
	pe.Enabled = plan.t < plan.arriveAt
	local rate = if def.vent then (if hanging then 8 else 16) else (if hanging then 10 else 0)
	if pe.Rate ~= rate then pe.Rate = rate end
	local p = Vector3.new(pos.x, pos.y, pos.z)
	if def.vent then
		-- the vent: a column of steam/magma from the floor up to the jet's head
		local floor = feetY
		local head = math.max(floor + 0.2, p.Y)
		local h = head - floor
		local jet = item.jet
		if jet then
			jet.part.Size = Vector3.new(math.max(0.2, h), 2.2, 2.2)
			jet.part.CFrame = CFrame.new(p.X, floor + h / 2, p.Z) * UPRIGHT
			jet.lastT = 1
			jet.part.Transparency = if hanging then 1 else jet.base
		end
	else
		-- it shakes while it hangs (working loose), turns as it falls, and lies still once it has landed. The turn
		-- is about the vertical axis only, so no part of it (a relic's plate, a shard's edge) ever dips below the
		-- height it is drawn at: it lands ON the floor, never through it
		local landed = not hanging and p.Y <= feetY + CaveArt.hazardHalfHeight(plan.kind) + 0.01
		local spin = CFrame.Angles(0, now * 4, 0)
		place(item, CFrame.new(p) * (if hanging then CFrame.Angles(math.sin(now * 30) * 0.05, 0, 0) elseif landed then CFrame.new() else spin))
	end

	local ring = self:ringItem()
	if plan.t > plan.arriveAt then
		setWeight(ring, 0, self.folder)
		return
	end
	setWeight(ring, 1, self.folder)
	local colour = if plan.locked then rgb(255, 60, 60) else rgb(255, 210, 60)
	local shadow, edge, lane = ring.entries[1], ring.entries[2], ring.entries[3]
	local d = 2 * zone.radius
	local y = feetY + 0.06
	-- a rock's shadow darkens as it nears; a vent glows
	local near = math.clamp(plan.t / math.max(plan.arriveAt, 0.01), 0, 1)
	shadow.part.Color = if def.vent then rgb(255, 150, 70) else rgb(10, 8, 8)
	local st = if def.vent then 0.55 - 0.25 * near else 0.65 - 0.35 * near
	shadow.part.Transparency = st
	shadow.lastT = st
	shadow.part.Size = Vector3.new(0.12, d, d)
	shadow.part.CFrame = CFrame.new(zone.x, y + 0.03, zone.z) * UPRIGHT
	edge.part.Color = colour
	edge.part.Size = Vector3.new(0.1, d + 0.4, d + 0.4)
	edge.part.CFrame = CFrame.new(zone.x, y, zone.z) * UPRIGHT
	-- the lane runs from the model's tip as drawn (in a one-layer tunnel that is the bit poking out of the roof)
	-- down to the ring; a vent's from where it will burst out below the floor
	local top = if def.vent then Vector3.new(plan.start.x, plan.start.y, plan.start.z)
		else p - Vector3.new(0, CaveArt.hazardHalfHeight(plan.kind), 0)
	local bottom = Vector3.new(zone.x, y, zone.z)
	local len = (top - bottom).Magnitude
	lane.part.Color = colour
	lane.part.Size = Vector3.new(0.25, math.max(0.5, len), 0.25)
	lane.part.CFrame = CFrame.new(top:Lerp(bottom, 0.5))
end

function CaveArt:hideHazard(kind)
	local item = self.hazardModels[kind]
	if item then
		item.billboard.Enabled = false
		for _, pe in item.emitters do pe.Enabled = false end
		setWeight(item, 0, self.folder)
	end
	if self.ring then setWeight(self.ring, 0, self.folder) end
end

-- ── rest: a lantern beside a resting miner ──

-- floorY: the top of the floor the miner rests on (the lantern stands on it, whatever the root's height)
function CaveArt:setRestLantern(on, rootCF, floorY)
	if self.lantern == nil then
		local item = newItem("RestLantern")
		local body = addPart(item, { name = "RestLantern", size = Vector3.new(0.8, 1.1, 0.8), material = Enum.Material.Neon,
			color = rgb(255, 190, 110), transparency = 0.15, offset = CFrame.new(0, 0.55, 0) })
		addPart(item, { name = "RestLanternCap", size = Vector3.new(1.0, 0.2, 1.0), material = Enum.Material.Metal,
			color = rgb(60, 56, 52), offset = CFrame.new(0, 1.2, 0) })
		local light = Instance.new("PointLight")
		light.Name = "RestLanternLight"
		light.Color = rgb(255, 196, 130)
		light.Range = 14
		light.Brightness = 1.3
		light.Shadows = false
		light.Enabled = false
		light.Parent = body
		table.insert(item.lights, light)
		self.lantern = item
	end
	setWeight(self.lantern, if on then 1 else 0, self.folder)
	if on and rootCF then
		local at = (rootCF * CFrame.new(2.2, 0, -1)).Position
		place(self.lantern, CFrame.new(at.X, floorY or (rootCF.Position.Y - 3), at.Z))
	end
end

return CaveArt
