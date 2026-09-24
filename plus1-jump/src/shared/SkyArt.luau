-- SkyArt.luau — +1 Jump's sky scenery, critters and hazard models, built in code (no assets).
-- CLIENT ONLY. Required by src/client/Sky.client.luau; the server never touches it.
--
-- Everything here is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off (so the camera
-- never pops in front of a cloud and nothing can be stood on or touched), CastShadow off (cheap, and
-- a 2048-stud planet must not shade the tower). Nothing is built until a band first needs it, and
-- anything whose weight falls to zero is UNPARENTED, so a band you are not in costs no draw calls.
--
-- Dependencies arrive as arguments (a bare `require("./X")` is invalid in Roblox):
--   SkyArt.new(folder, rand, Config, Progression, EnvBands, TowerGen)
--
-- Budgets are measured, not assumed: robloxemu/check_plus1_sky.luau counts what this module has
-- parented at every band and every band boundary against Config.Budget.

local SkyArt = {}
SkyArt.__index = SkyArt

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- ─────────────────────────────────────────────────────────────── items: parts that fade together
-- item = { entries = { { part, base, offset } }, beams = { { beam, base } }, trails = {}, lights = {},
--          emitters = {}, shown = false, weight = 0 }

local function newItem(name)
	return { name = name, entries = {}, beams = {}, trails = {}, lights = {}, shown = false, weight = 0 }
end

local function addPart(item, props)
	local p = Instance.new(props.class or "Part")
	p.Name = props.name or item.name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Color = props.color or rgb(255, 255, 255)
	if props.shape then p.Shape = props.shape end
	p.Size = props.size or Vector3.new(1, 1, 1)
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
			for _, b in item.beams do b.beam.Enabled = false end
			for _, t in item.trails do t.Enabled = false end
			for _, l in item.lights do l.Enabled = false end
			item.shown = false
		end
		return
	end
	if not item.shown then
		for _, e in item.entries do
			-- an entry left out to keep the climb clear (tiled scenery, see updatePiece) stays out
			if not e.hidden then e.part.Parent = folder end
		end
		item.shown = true
	end
	for _, e in item.entries do
		local t = 1 - (1 - e.base) * w
		if math.abs(t - e.lastT) > 0.02 or (w >= 0.99 and e.lastT ~= e.base) then
			e.part.Transparency = t
			e.lastT = t
		end
	end
	for _, b in item.beams do
		local on = w > 0.05
		b.beam.Enabled = on
		if on and math.abs((b.lastW or -1) - w) > 0.05 then
			local mid = 1 - (1 - b.base) * w
			b.beam.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, mid),
				NumberSequenceKeypoint.new(1, 1),
			})
			b.lastW = w
		end
	end
	for _, t in item.trails do t.Enabled = w > 0.5 end
	for _, l in item.lights do l.Enabled = w > 0.3 end
end

local function place(item, root)
	for _, e in item.entries do
		e.part.CFrame = root * e.offset
	end
end

-- An invisible anchor part for attachments (beams, trails). Counted like any other part.
local function addHost(item, offset)
	local host = addPart(item, { name = item.name .. "Host", size = Vector3.new(1, 1, 1), transparency = 1, offset = offset })
	return host
end

local function addBeam(item, host, a0pos, a1pos, props)
	local a0 = Instance.new("Attachment")
	a0.Position = a0pos
	a0.Parent = host
	local a1 = Instance.new("Attachment")
	a1.Position = a1pos
	a1.Parent = host
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = props.color
	beam.Width0 = props.width0 or 40
	beam.Width1 = props.width1 or 40
	beam.CurveSize0 = props.curve0 or 0
	beam.CurveSize1 = props.curve1 or 0
	beam.LightEmission = props.lightEmission or 1
	beam.FaceCamera = props.faceCamera ~= false
	beam.Segments = props.segments or 16
	beam.Enabled = false
	beam.Parent = host
	table.insert(item.beams, { beam = beam, base = props.transparency or 0.4 })
	return beam
end

local function addTrail(item, p, halfWidth, props)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, halfWidth, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -halfWidth, 0)
	a1.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Lifetime = props.lifetime or 1
	tr.Color = ColorSequence.new(props.color or rgb(255, 255, 255))
	tr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, props.transparency or 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	tr.LightEmission = props.lightEmission or 0.5
	tr.FaceCamera = true
	tr.Enabled = false
	tr.Parent = p
	table.insert(item.trails, tr)
	return tr
end

local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis is X; this stands it up
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- a Cylinder lying along the travel direction

-- ─────────────────────────────────────────────────────────────── pieces (static scenery)

local PIECES = {}

-- The sky temple the tower rises from: an island far below the pad, on a marble column that carries
-- the pad. It is not collidable, so it sits Config.Env.IslandTopBelowPad under the pad: deeper than a
-- player who walks off the pad can fall before the server's rescue (poll + network) brings them back
-- (review 2026-09-17: at 70 studs, 89% of walk-offs sank through the grass first).
PIECES.templeIsland = function(art)
	local item = newItem("TempleIsland")
	item.anchor = "world"
	local baseY = art.cfg.Tower.BaseY
	item.root = CFrame.new(0, baseY, 0)
	local top = -(art.cfg.Env.IslandTopBelowPad or 70)
	addPart(item, { name = "IslandGrass", shape = CYL, size = Vector3.new(24, 300, 300), color = rgb(96, 168, 82), material = Enum.Material.Grass, offset = CFrame.new(0, top - 12, 0) * UPRIGHT })
	addPart(item, { name = "IslandEarth", shape = CYL, size = Vector3.new(50, 250, 250), color = rgb(122, 92, 66), material = Enum.Material.Ground, offset = CFrame.new(0, top - 49, 0) * UPRIGHT })
	addPart(item, { name = "IslandRock", shape = BALL, size = Vector3.new(170, 170, 170), color = rgb(110, 104, 100), material = Enum.Material.Slate, offset = CFrame.new(0, top - 130, 0) })
	-- the column from inside the island up to the underside of the pad (the pad's base is 2 studs thick)
	local spireLow, spireHigh = top - 10, -2
	addPart(item, { name = "Spire", shape = CYL, size = Vector3.new(spireHigh - spireLow, 14, 14), color = rgb(226, 218, 198), material = Enum.Material.Marble, offset = CFrame.new(0, (spireLow + spireHigh) / 2, 0) * UPRIGHT })
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2
		addPart(item, { name = "Pillar", shape = CYL, size = Vector3.new(44, 6, 6), color = rgb(236, 230, 214), material = Enum.Material.Marble, offset = CFrame.new(math.sin(a) * 96, top + 22, math.cos(a) * 96) * UPRIGHT })
	end
	-- a gate facing the way the tower climbs (+Z), in shot from the start pad
	local gz = 120
	addPart(item, { name = "GatePost", size = Vector3.new(4, 38, 4), color = rgb(196, 44, 44), material = Enum.Material.Wood, offset = CFrame.new(-16, top + 19, gz) })
	addPart(item, { name = "GatePost", size = Vector3.new(4, 38, 4), color = rgb(196, 44, 44), material = Enum.Material.Wood, offset = CFrame.new(16, top + 19, gz) })
	addPart(item, { name = "GateBeam", size = Vector3.new(46, 3, 5), color = rgb(40, 32, 30), material = Enum.Material.Wood, offset = CFrame.new(0, top + 39, gz) })
	addPart(item, { name = "GateBeam", size = Vector3.new(38, 2, 3), color = rgb(196, 44, 44), material = Enum.Material.Wood, offset = CFrame.new(0, top + 33, gz) })
	for i = 1, 4 do
		local a = (i - 0.5) / 4 * math.pi * 2
		local x, z = math.sin(a) * 60, math.cos(a) * 60
		addPart(item, { name = "Trunk", shape = CYL, size = Vector3.new(14, 2.6, 2.6), color = rgb(92, 64, 48), material = Enum.Material.Wood, offset = CFrame.new(x, top + 7, z) * UPRIGHT })
		addPart(item, { name = "Blossom", shape = BALL, size = Vector3.new(16, 16, 16), color = rgb(255, 184, 204), offset = CFrame.new(x, top + 18, z) })
	end
	addPart(item, { name = "Waterfall", size = Vector3.new(12, 110, 2), color = rgb(170, 220, 255), material = Enum.Material.Glass, transparency = 0.35, offset = CFrame.new(0, top - 60, -150) })
	return item
end

-- The climbing path near altitude band [yLo, yHi]: platform centres (+3.5, where a standing climber's
-- root is) from TowerGen, the same numbers the server builds from. Empty without TowerGen.
local function climbPathBetween(art, yLo, yHi)
	local TG = art.TowerGen
	if TG == nil then return nil end
	local tw = art.cfg.Tower
	local P = art.Progression
	local t0 = math.max(1, P.tierAtY(yLo, tw))
	local t1 = math.max(t0, P.tierAtY(yHi, tw) + 1)
	local out = {}
	for _, c in TG.platformCentres({ Tower = tw, Jump = art.cfg.Jump, WorldSeed = art.cfg.WorldSeed }, t0, t1) do
		out[#out + 1] = { x = c.x, y = c.y + 3.5, z = c.z }
	end
	return out
end

-- World-fixed tiled fields: content belongs to a grid cell, so nothing slides with the camera.
-- spec.keepClear: shrink or leave out any ball whose surface would come within Config.Env.SceneryClearance
-- of the climbing path (a deck the tower climbs THROUGH must not swallow a platform or hide it).
local function tiledPiece(art, name, spec)
	local item = newItem(name)
	item.anchor = "tiled"
	item.tile = spec
	if spec.keepClear then
		local clearance = art.cfg.Env.SceneryClearance or 0
		local reach = spec.yJitter + spec.sizeMax / 2 + clearance
		item.clearPath = climbPathBetween(art, spec.y - reach, spec.y + reach)
		item.clearance = clearance
	end
	local n = (2 * spec.radius + 1) ^ 2 * spec.perCell
	for _ = 1, n do
		addPart(item, { name = name .. "Puff", shape = BALL, size = Vector3.new(spec.sizeMin, spec.sizeMin, spec.sizeMin), color = spec.colors[1], material = spec.material, transparency = spec.transparency })
	end
	return item
end

local function layerY(art, pieceId, fallback)
	for _, layer in art.cfg.Env.Layers or {} do
		if layer.piece == pieceId then
			return art.Progression.yAtProgress(layer.center, art.cfg.Tower)
		end
	end
	return fallback
end

PIECES.canopy = function(art)
	return tiledPiece(art, "Canopy", {
		-- below the temple island (and its rock), so the forest never covers it
		cellSize = 360, radius = 1, perCell = 4, y = art.cfg.Tower.BaseY - (art.cfg.Env.IslandTopBelowPad or 70) - 150, yJitter = 40, seed = 11,
		sizeMin = 70, sizeMax = 150, transparency = 0, material = Enum.Material.Grass,
		colors = { rgb(62, 124, 56), rgb(84, 146, 62), rgb(104, 160, 74), rgb(150, 190, 90) },
	})
end

PIECES.cloudDeck = function(art)
	return tiledPiece(art, "CloudDeck", {
		cellSize = 420, radius = 1, perCell = 5, y = layerY(art, "cloudDeck", 5000), yJitter = 30, seed = 23, keepClear = true,
		sizeMin = 80, sizeMax = 210, transparency = 0.12, material = Enum.Material.SmoothPlastic,
		colors = { rgb(252, 252, 255), rgb(246, 244, 250), rgb(255, 246, 236) },
	})
end

PIECES.stormDeck = function(art)
	return tiledPiece(art, "StormDeck", {
		cellSize = 420, radius = 1, perCell = 4, y = layerY(art, "stormDeck", 10000), yJitter = 40, seed = 37, keepClear = true,
		sizeMin = 120, sizeMax = 250, transparency = 0.08, material = Enum.Material.SmoothPlastic,
		colors = { rgb(72, 70, 88), rgb(88, 84, 104), rgb(60, 58, 74) },
	})
end

PIECES.aurora = function(art)
	local item = newItem("Aurora")
	item.anchor = "sky"
	local host = addHost(item, CFrame.new(0, 380, -200))
	local colors = {
		ColorSequence.new(rgb(90, 255, 170), rgb(150, 90, 255)),
		ColorSequence.new(rgb(70, 230, 255), rgb(90, 255, 140)),
		ColorSequence.new(rgb(180, 110, 255), rgb(80, 255, 200)),
	}
	for i = 1, 3 do
		local z = -260 + i * 150
		addBeam(item, host, Vector3.new(-700, 0, z), Vector3.new(700, 40 * i, z - 120), {
			color = colors[i], width0 = 160, width1 = 90, curve0 = 260 - i * 40, curve1 = -180 + i * 30,
			transparency = 0.35, segments = 24, faceCamera = false,
		})
	end
	return item
end

PIECES.horizonGlow = function(art)
	local item = newItem("HorizonGlow")
	item.anchor = "sky"
	addPart(item, { name = "SunsetDisc", shape = CYL, size = Vector3.new(2, 2048, 2048), color = rgb(255, 140, 90), material = Enum.Material.Neon, transparency = 0.78, offset = CFrame.new(0, -950, 0) * UPRIGHT })
	addPart(item, { name = "SkyDisc", shape = CYL, size = Vector3.new(2, 1600, 1600), color = rgb(110, 150, 255), material = Enum.Material.Neon, transparency = 0.72, offset = CFrame.new(0, -930, 0) * UPRIGHT })
	return item
end

PIECES.earth = function(art)
	local item = newItem("Earth")
	item.anchor = "sky"
	addPart(item, { name = "Planet", shape = BALL, size = Vector3.new(2048, 2048, 2048), color = rgb(38, 92, 196), offset = CFrame.new(0, -2750, 300) })
	addPart(item, { name = "Clouds", shape = BALL, size = Vector3.new(2048, 2048, 2048), color = rgb(255, 255, 255), transparency = 0.86, offset = CFrame.new(0, -2715, 300) })
	addPart(item, { name = "AirGlow", shape = BALL, size = Vector3.new(2048, 2048, 2048), color = rgb(120, 190, 255), material = Enum.Material.Neon, transparency = 0.84, offset = CFrame.new(0, -2680, 300) })
	return item
end

PIECES.station = function(art)
	local item = newItem("Station")
	item.anchor = "sky"
	item.spin = 0.05
	item.centre = CFrame.new(900, 160, -1300) * CFrame.Angles(math.rad(70), 0, math.rad(15))
	for i = 1, 12 do
		local a = (i - 1) / 12 * math.pi * 2
		addPart(item, { name = "Ring", size = Vector3.new(60, 12, 18), color = rgb(222, 226, 232), material = Enum.Material.Metal, offset = CFrame.Angles(0, 0, a) * CFrame.new(0, 112, 0) })
	end
	addPart(item, { name = "Hub", shape = CYL, size = Vector3.new(60, 24, 24), color = rgb(200, 204, 214), material = Enum.Material.Metal, offset = ALONG_Z })
	addPart(item, { name = "PanelL", size = Vector3.new(90, 2, 50), color = rgb(40, 70, 160), material = Enum.Material.Glass, offset = CFrame.new(-150, 0, 0) })
	addPart(item, { name = "PanelR", size = Vector3.new(90, 2, 50), color = rgb(40, 70, 160), material = Enum.Material.Glass, offset = CFrame.new(150, 0, 0) })
	return item
end

PIECES.ringedPlanet = function(art)
	local item = newItem("RingedPlanet")
	item.anchor = "sky"
	local c = CFrame.new(-1600, 520, -2600)
	addPart(item, { name = "Planet", shape = BALL, size = Vector3.new(900, 900, 900), color = rgb(214, 164, 112), offset = c })
	addPart(item, { name = "Ring", shape = CYL, size = Vector3.new(4, 1900, 1900), color = rgb(236, 206, 164), transparency = 0.45, offset = c * CFrame.Angles(0, 0, math.rad(90 - 20)) })
	addPart(item, { name = "RingShade", shape = CYL, size = Vector3.new(5, 1300, 1300), color = rgb(150, 120, 90), transparency = 0.7, offset = c * CFrame.Angles(0, 0, math.rad(90 - 20)) })
	addPart(item, { name = "Moon", shape = BALL, size = Vector3.new(180, 180, 180), color = rgb(170, 170, 180), material = Enum.Material.Slate, offset = CFrame.new(-700, 760, -2200) })
	return item
end

PIECES.nebula = function(art)
	local item = newItem("Nebula")
	item.anchor = "sky"
	local blobs = {
		{ rgb(255, 90, 180), Vector3.new(-2600, 900, -2400), 2000 },
		{ rgb(90, 220, 255), Vector3.new(2800, 400, -1800), 1800 },
		{ rgb(160, 90, 255), Vector3.new(600, 1600, 3000), 2000 },
		{ rgb(255, 150, 90), Vector3.new(-3000, -600, 1800), 1500 },
		{ rgb(90, 255, 190), Vector3.new(2400, -900, 2600), 1400 },
	}
	for _, b in blobs do
		addPart(item, { name = "Nebula", shape = BALL, size = Vector3.new(b[3], b[3], b[3]), color = b[1], material = Enum.Material.Neon, transparency = 0.9, offset = CFrame.new(b[2]) })
	end
	return item
end

PIECES.galaxy = function(art)
	local item = newItem("Galaxy")
	item.anchor = "sky"
	item.spin = 0.02
	item.centre = CFrame.new(0, -1700, 700) * CFrame.Angles(math.rad(12), 0, 0)
	addPart(item, { name = "OuterDisc", shape = CYL, size = Vector3.new(6, 2048, 2048), color = rgb(120, 90, 220), material = Enum.Material.Neon, transparency = 0.88, offset = UPRIGHT })
	addPart(item, { name = "MidDisc", shape = CYL, size = Vector3.new(8, 1300, 1300), color = rgb(170, 130, 255), material = Enum.Material.Neon, transparency = 0.8, offset = UPRIGHT })
	addPart(item, { name = "InnerDisc", shape = CYL, size = Vector3.new(10, 600, 600), color = rgb(255, 222, 190), material = Enum.Material.Neon, transparency = 0.6, offset = UPRIGHT })
	addPart(item, { name = "Core", shape = BALL, size = Vector3.new(260, 260, 260), color = rgb(255, 242, 214), material = Enum.Material.Neon, transparency = 0.15, offset = CFrame.new() })
	local host = addHost(item, CFrame.new(0, 12, 0))
	for i = 1, 4 do
		local a = (i - 1) / 4 * math.pi * 2
		local inner = Vector3.new(math.sin(a) * 140, 0, math.cos(a) * 140)
		local outer = Vector3.new(math.sin(a + 1.9) * 980, 0, math.cos(a + 1.9) * 980)
		addBeam(item, host, inner, outer, {
			color = ColorSequence.new(rgb(255, 236, 200), rgb(130, 110, 255)), width0 = 170, width1 = 90,
			curve0 = 520, curve1 = -300, transparency = 0.3, segments = 20, faceCamera = false,
		})
	end
	return item
end

-- ─────────────────────────────────────────────────────────────── critters (moving life)

local CRITTERS = {}

CRITTERS.bird = function(item, scale)
	scale = scale or 1
	local wing = Vector3.new(2.3, 0.15, 0.9) * scale
	addPart(item, { name = "WingL", size = wing, color = rgb(46, 44, 52) })
	addPart(item, { name = "WingR", size = wing, color = rgb(46, 44, 52) })
	item.animate = function(it, cf, now)
		local flap = math.sin(now * 11 + (it.phase or 0)) * 0.45
		it.entries[1].part.CFrame = cf * CFrame.Angles(0, 0, 0.25 + flap) * CFrame.new(-1.1 * scale, 0, 0)
		it.entries[2].part.CFrame = cf * CFrame.Angles(0, 0, -0.25 - flap) * CFrame.new(1.1 * scale, 0, 0)
	end
end

CRITTERS.balloon = function(item)
	local palette = { rgb(232, 82, 70), rgb(250, 200, 60), rgb(90, 172, 232), rgb(120, 210, 120) }
	addPart(item, { name = "Envelope", shape = BALL, size = Vector3.new(22, 22, 22), color = palette[math.random(1, #palette)] })
	addPart(item, { name = "Burner", size = Vector3.new(1.2, 1.2, 1.2), color = rgb(255, 150, 60), material = Enum.Material.Neon, offset = CFrame.new(0, -12.5, 0) })
	addPart(item, { name = "Basket", size = Vector3.new(4, 3, 4), color = rgb(130, 92, 56), material = Enum.Material.WoodPlanks, offset = CFrame.new(0, -16, 0) })
end

CRITTERS.airliner = function(item)
	local body = addPart(item, { name = "Fuselage", shape = CYL, size = Vector3.new(40, 4.5, 4.5), color = rgb(240, 242, 246), material = Enum.Material.Metal, offset = ALONG_Z })
	addPart(item, { name = "Wings", size = Vector3.new(44, 0.6, 7), color = rgb(210, 214, 222), material = Enum.Material.Metal, offset = CFrame.new(0, -0.5, 2) })
	addPart(item, { name = "Tail", size = Vector3.new(0.6, 7, 5), color = rgb(40, 90, 200), offset = CFrame.new(0, 4, 18) })
	addTrail(item, body, 1.2, { lifetime = 3, color = rgb(255, 255, 255), transparency = 0.35, lightEmission = 0.2 })
end

CRITTERS.jet = function(item, scale)
	scale = scale or 1
	local body = addPart(item, { name = "Fuselage", shape = CYL, size = Vector3.new(18, 2, 2) * scale, color = rgb(170, 176, 186), material = Enum.Material.Metal, offset = ALONG_Z })
	addPart(item, { name = "Wings", size = Vector3.new(13, 0.4, 7) * scale, color = rgb(150, 156, 166), material = Enum.Material.Metal, offset = CFrame.new(0, 0, 2 * scale) })
	addPart(item, { name = "Fin", size = Vector3.new(0.4, 4, 3) * scale, color = rgb(150, 156, 166), offset = CFrame.new(0, 2 * scale, 8 * scale) })
	addTrail(item, body, 0.6 * scale, { lifetime = 2, color = rgb(255, 255, 255), transparency = 0.3, lightEmission = 0.3 })
end

CRITTERS.plane = function(item)
	addPart(item, { name = "Fuselage", size = Vector3.new(2.4, 2.4, 12), color = rgb(214, 52, 52) })
	addPart(item, { name = "Wings", size = Vector3.new(17, 0.4, 3.2), color = rgb(246, 246, 246), offset = CFrame.new(0, 0.8, -1) })
	addPart(item, { name = "Tail", size = Vector3.new(0.4, 3, 2.2), color = rgb(214, 52, 52), offset = CFrame.new(0, 1.8, 5.2) })
	addPart(item, { name = "Prop", size = Vector3.new(0.3, 4.6, 0.4), color = rgb(40, 40, 40), offset = CFrame.new(0, 0, -6.3) })
	item.animate = function(it, cf, now)
		for i = 1, 3 do
			it.entries[i].part.CFrame = cf * it.entries[i].offset
		end
		it.entries[4].part.CFrame = cf * it.entries[4].offset * CFrame.Angles(0, 0, now * 40)
	end
end

CRITTERS.weatherBalloon = function(item, scale)
	scale = scale or 1
	addPart(item, { name = "Balloon", shape = BALL, size = Vector3.new(9, 9, 9) * scale, color = rgb(244, 244, 244), transparency = 0.1 })
	addPart(item, { name = "String", size = Vector3.new(0.12, 9, 0.12) * scale, color = rgb(200, 200, 200), offset = CFrame.new(0, -9 * scale, 0) })
	addPart(item, { name = "Payload", size = Vector3.new(1.6, 1.1, 1.6) * scale, color = rgb(255, 140, 40), offset = CFrame.new(0, -14 * scale, 0) })
end

local function tumble(spinX, spinY)
	return function(it, cf, now)
		local rot = CFrame.Angles(now * spinX + (it.phase or 0), now * spinY, 0)
		for _, e in it.entries do
			e.part.CFrame = cf * rot * e.offset
		end
	end
end

CRITTERS.booster = function(item, scale)
	scale = scale or 1
	addPart(item, { name = "Stage", shape = CYL, size = Vector3.new(26, 7, 7) * scale, color = rgb(238, 238, 238), material = Enum.Material.Metal, offset = ALONG_Z })
	addPart(item, { name = "Band", shape = CYL, size = Vector3.new(2, 7.3, 7.3) * scale, color = rgb(30, 30, 34), offset = CFrame.new(0, 0, -6 * scale) * ALONG_Z })
	addPart(item, { name = "Nozzle", shape = BALL, size = Vector3.new(6, 6, 6) * scale, color = rgb(60, 60, 66), material = Enum.Material.Metal, offset = CFrame.new(0, 0, 13 * scale) })
	addPart(item, { name = "Flame", shape = BALL, size = Vector3.new(4, 4, 4) * scale, color = rgb(255, 150, 60), material = Enum.Material.Neon, transparency = 0.2, offset = CFrame.new(0, 0, 16 * scale) })
	item.animate = tumble(0.35, 0.2)
end

CRITTERS.meteor = function(item)
	local p = addPart(item, { name = "Meteor", shape = BALL, size = Vector3.new(3, 3, 3), color = rgb(255, 204, 150), material = Enum.Material.Neon })
	addTrail(item, p, 1.5, { lifetime = 0.6, color = rgb(255, 190, 120), transparency = 0.1, lightEmission = 1 })
end

CRITTERS.satellite = function(item)
	addPart(item, { name = "Body", size = Vector3.new(3, 3, 4), color = rgb(206, 174, 84), material = Enum.Material.Foil })
	addPart(item, { name = "PanelL", size = Vector3.new(10, 0.2, 4), color = rgb(40, 70, 160), material = Enum.Material.Glass, offset = CFrame.new(-7, 0, 0) })
	addPart(item, { name = "PanelR", size = Vector3.new(10, 0.2, 4), color = rgb(40, 70, 160), material = Enum.Material.Glass, offset = CFrame.new(7, 0, 0) })
	item.animate = tumble(0.05, 0.12)
end

CRITTERS.astronaut = function(item, scale)
	scale = scale or 1
	local white = rgb(244, 244, 248)
	addPart(item, { name = "Torso", size = Vector3.new(2, 2.4, 1.4) * scale, color = white })
	addPart(item, { name = "Helmet", shape = BALL, size = Vector3.new(2, 2, 2) * scale, color = white, offset = CFrame.new(0, 2.1 * scale, 0) })
	addPart(item, { name = "Visor", shape = BALL, size = Vector3.new(1.5, 1.5, 1.5) * scale, color = rgb(255, 196, 80), material = Enum.Material.Neon, transparency = 0.2, offset = CFrame.new(0, 2.15 * scale, -0.45 * scale) })
	addPart(item, { name = "Pack", size = Vector3.new(1.8, 2, 0.8) * scale, color = rgb(160, 160, 172), offset = CFrame.new(0, 0.1 * scale, 1.1 * scale) })
	addPart(item, { name = "ArmL", size = Vector3.new(0.6, 2, 0.6) * scale, color = white, offset = CFrame.new(-1.4 * scale, 0.2 * scale, 0) * CFrame.Angles(0, 0, 0.5) })
	addPart(item, { name = "ArmR", size = Vector3.new(0.6, 2, 0.6) * scale, color = white, offset = CFrame.new(1.4 * scale, 0.2 * scale, 0) * CFrame.Angles(0, 0, -0.5) })
	item.animate = tumble(0.15, 0.25)
end

CRITTERS.junk = function(item, scale)
	scale = scale or 1
	local pick = math.random(1, 3)
	if pick == 1 then
		addPart(item, { name = "Panel", size = Vector3.new(3, 0.3, 4) * scale, color = rgb(150, 154, 160), material = Enum.Material.Metal })
	elseif pick == 2 then
		addPart(item, { name = "Tank", shape = CYL, size = Vector3.new(4, 1.2, 1.2) * scale, color = rgb(210, 210, 214), material = Enum.Material.Metal })
	else
		addPart(item, { name = "Box", size = Vector3.new(1.8, 1.8, 1.8) * scale, color = rgb(206, 174, 84), material = Enum.Material.Foil })
	end
	item.animate = tumble(0.9, 0.6)
end

CRITTERS.asteroid = function(item, scale)
	scale = scale or (0.6 + math.random() * 1.2)
	local s = 14 * scale
	addPart(item, { name = "Rock", shape = BALL, size = Vector3.new(s, s, s), color = rgb(100, 90, 84), material = Enum.Material.Slate })
	addPart(item, { name = "Chunk", shape = BALL, size = Vector3.new(s * 0.55, s * 0.55, s * 0.55), color = rgb(84, 76, 72), material = Enum.Material.Slate, offset = CFrame.new(s * 0.35, s * 0.15, -s * 0.2) })
	item.animate = tumble(0.12, 0.18)
end

CRITTERS.ship = function(item, scale)
	scale = scale or 1
	local hull = addPart(item, { class = "WedgePart", name = "Hull", size = Vector3.new(6, 2.5, 16) * scale, color = rgb(196, 200, 214), material = Enum.Material.Metal, offset = CFrame.Angles(0, math.pi, 0) })
	addPart(item, { name = "Cockpit", shape = BALL, size = Vector3.new(2.6, 2.6, 2.6) * scale, color = rgb(80, 220, 255), material = Enum.Material.Neon, transparency = 0.15, offset = CFrame.new(0, 1 * scale, -2 * scale) })
	addPart(item, { name = "EngineL", shape = CYL, size = Vector3.new(4, 2, 2) * scale, color = rgb(90, 94, 104), material = Enum.Material.Metal, offset = CFrame.new(-2.2 * scale, -0.4 * scale, 7 * scale) * ALONG_Z })
	addPart(item, { name = "EngineR", shape = CYL, size = Vector3.new(4, 2, 2) * scale, color = rgb(90, 94, 104), material = Enum.Material.Metal, offset = CFrame.new(2.2 * scale, -0.4 * scale, 7 * scale) * ALONG_Z })
	addPart(item, { name = "GlowL", shape = BALL, size = Vector3.new(1.8, 1.8, 1.8) * scale, color = rgb(90, 200, 255), material = Enum.Material.Neon, offset = CFrame.new(-2.2 * scale, -0.4 * scale, 9.2 * scale) })
	addPart(item, { name = "GlowR", shape = BALL, size = Vector3.new(1.8, 1.8, 1.8) * scale, color = rgb(90, 200, 255), material = Enum.Material.Neon, offset = CFrame.new(2.2 * scale, -0.4 * scale, 9.2 * scale) })
	addTrail(item, hull, 0.8 * scale, { lifetime = 0.8, color = rgb(90, 200, 255), transparency = 0.2, lightEmission = 1 })
end

CRITTERS.comet = function(item, scale)
	scale = scale or 1
	local p = addPart(item, { name = "Comet", shape = BALL, size = Vector3.new(8, 8, 8) * scale, color = rgb(210, 244, 255), material = Enum.Material.Neon })
	addTrail(item, p, 4 * scale, { lifetime = 2.5, color = rgb(160, 220, 255), transparency = 0.15, lightEmission = 1 })
end

-- ─────────────────────────────────────────────────────────────── construction

function SkyArt.new(folder, rand, Config, Progression, EnvBands, TowerGen)
	local self = setmetatable({}, SkyArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.Progression = Progression
	self.EnvBands = EnvBands
	self.TowerGen = TowerGen
	self.pieces = {} -- id -> item
	self.critters = {} -- kind -> { list of critter items }
	self.hazardModels = {} -- kind -> item
	return self
end

function SkyArt.hasPiece(id)
	return PIECES[id] ~= nil
end

function SkyArt.hasCritter(kind)
	return CRITTERS[kind] ~= nil
end

-- Show piece `id` at weight w around camera position `cam` (a Vector3).
function SkyArt:updatePiece(id, w, cam, now)
	local item = self.pieces[id]
	if item == nil then
		if w <= 0.01 then return end
		local build = PIECES[id]
		if build == nil then return end
		item = build(self)
		self.pieces[id] = item
	end
	setWeight(item, w, self.folder)
	if not item.shown then return end
	if item.anchor == "world" then
		if not item.placed then
			place(item, item.root)
			item.placed = true
		end
	elseif item.anchor == "tiled" then
		local spec = item.tile
		local E = self.EnvBands
		local cx, cz = E.cellOf(cam.X, spec.cellSize), E.cellOf(cam.Z, spec.cellSize)
		if item.cellX ~= cx or item.cellZ ~= cz then
			item.cellX, item.cellZ = cx, cz
			local k = 0
			for _, cell in E.cellsAround(cam.X, cam.Z, spec.cellSize, spec.radius) do
				for j = 1, spec.perCell do
					k += 1
					local e = item.entries[k]
					local h1 = E.hash01(cell[1], cell[2], j * 10 + 1, spec.seed)
					local h2 = E.hash01(cell[1], cell[2], j * 10 + 2, spec.seed)
					local h3 = E.hash01(cell[1], cell[2], j * 10 + 3, spec.seed)
					local h4 = E.hash01(cell[1], cell[2], j * 10 + 4, spec.seed)
					local size = spec.sizeMin + (spec.sizeMax - spec.sizeMin) * h4
					local px, py, pz = (cell[1] + h1) * spec.cellSize, spec.y + (h3 - 0.5) * 2 * spec.yJitter, (cell[2] + h2) * spec.cellSize
					if item.clearPath then
						size = 2 * E.keepClear({ x = px, y = py, z = pz }, size / 2, item.clearPath, item.clearance, spec.sizeMin / 4)
					end
					e.hidden = size <= 0
					if e.hidden then
						e.part.Parent = nil
					else
						e.part.Size = Vector3.new(size, size, size)
						e.part.Color = spec.colors[1 + math.floor(h3 * #spec.colors) % #spec.colors]
						e.part.CFrame = CFrame.new(px, py, pz)
						if e.part.Parent ~= self.folder then e.part.Parent = self.folder end
					end
				end
			end
		end
	else -- "sky": travels with the camera, like a skybox with depth
		local root = CFrame.new(cam)
		if item.centre then
			root = root * item.centre * CFrame.Angles(0, (now or 0) * (item.spin or 0), 0)
		end
		place(item, root)
	end
end

function SkyArt:hideAllPiecesExcept(keep)
	for id, item in self.pieces do
		if not keep[id] then setWeight(item, 0, self.folder) end
	end
end

-- ─────────────────────────────────────────────── critters: pooled, spawned on a ring, recycled

local function buildCritter(kind, scale)
	local item = newItem(kind)
	CRITTERS[kind](item, scale)
	return item
end

function SkyArt:critterList(kind)
	local list = self.critters[kind]
	if list == nil then
		list = {}
		self.critters[kind] = list
	end
	return list
end

-- desired: { [kind] = count }. Called every frame.
function SkyArt:updateCritters(desired, cam, dt, now)
	local E = self.EnvBands
	local specs = self.cfg.Env.Critters
	local camV = { x = cam.X, y = cam.Y, z = cam.Z }
	for kind in desired do self:critterList(kind) end
	for kind, list in self.critters do
		local want = desired[kind] or 0
		local spec = specs[kind]
		local active = 0
		for _, c in list do
			if c.active then
				c.pos = { x = c.pos.x + c.vel.x * dt, y = c.pos.y + c.vel.y * dt, z = c.pos.z + c.vel.z * dt }
				if E.ambientExpired(c.pos, camV, spec) then
					c.active = false
					setWeight(c.item, 0, self.folder)
				else
					active += 1
					if active > want then c.leaving = true end
					local target = if c.leaving then 0 else 1
					c.w = E.approach(c.w, target, dt, 0.35)
					if c.leaving and c.w < 0.03 then
						c.active = false
						setWeight(c.item, 0, self.folder)
					else
						setWeight(c.item, c.w, self.folder)
						local p = Vector3.new(c.pos.x, c.pos.y, c.pos.z)
						local hv = Vector3.new(c.vel.x, 0, c.vel.z)
						local look = if hv.Magnitude > 0.01 then p + hv else p + Vector3.new(0, 0, -1)
						local cf = CFrame.lookAt(p, look)
						if c.item.animate then
							c.item.animate(c.item, cf, now)
						else
							place(c.item, cf)
						end
					end
				end
			end
		end
		-- spawn at most one group per kind per frame (staggered, never a pop of ten)
		if active < want and spec then
			local group = math.min(spec.flock or 1, want - active)
			local base = E.ambientSpawn(camV, spec, self.rand)
			for g = 1, group do
				local c = nil
				for _, existing in list do
					if not existing.active then c = existing; break end
				end
				if c == nil then
					c = { item = buildCritter(kind), active = false }
					table.insert(list, c)
				end
				c.active = true
				c.leaving = false
				c.w = 0
				c.item.phase = self.rand() * 6.28
				local ox, oz = (g - 1) % 3 * 4 - 4, -(g - 1) * 3
				c.pos = { x = base.pos.x + ox, y = base.pos.y + (g - 1) * 0.8, z = base.pos.z + oz }
				c.vel = base.vel
			end
		end
	end
end

-- ─────────────────────────────────────────────── hazards + their telegraph

local HAZARD_RECIPE = {
	bird = { "bird", 1.6 },
	plane = { "plane", 1 },
	jet = { "jet", 1 },
	weatherBalloon = { "weatherBalloon", 1 },
	booster = { "booster", 0.6 },
	junk = { "junk", 1.4 },
	astronaut = { "astronaut", 1.1 },
	asteroid = { "asteroid", 1 },
	ship = { "ship", 1 },
	comet = { "comet", 0.7 },
}

function SkyArt.hazardKinds()
	local out = {}
	for k in HAZARD_RECIPE do out[k] = true end
	return out
end

function SkyArt:hazardModel(kind)
	local item = self.hazardModels[kind]
	if item then return item end
	local recipe = HAZARD_RECIPE[kind]
	item = newItem("Hazard_" .. kind)
	CRITTERS[recipe[1]](item, recipe[2])
	local main = item.entries[1].part
	-- visible from anywhere, even through cloud: the warning marker
	local bb = Instance.new("BillboardGui")
	bb.Name = "HazardWarning"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(46, 46)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = main
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "⚠️"
	mark.TextScaled = true
	mark.Font = Enum.Font.GothamBlack
	mark.TextColor3 = rgb(255, 220, 60)
	mark.Parent = bb
	item.billboard = bb
	local light = Instance.new("PointLight")
	light.Name = "HazardBlink"
	light.Color = rgb(255, 80, 60)
	light.Range = 24
	light.Brightness = 2
	light.Enabled = false
	light.Parent = main
	table.insert(item.lights, light)
	for _, e in item.entries do e.part.Name = "Hazard_" .. kind .. "_" .. e.part.Name end
	self.hazardModels[kind] = item
	return item
end

function SkyArt:laneItem()
	if self.lane then return self.lane end
	local item = newItem("HazardLane")
	addPart(item, { name = "HazardLane", size = Vector3.new(0.35, 0.35, 10), color = rgb(255, 210, 60), material = Enum.Material.Neon, transparency = 0.45 })
	addPart(item, { name = "HazardZone", shape = CYL, size = Vector3.new(0.3, 8, 8), color = rgb(255, 210, 60), material = Enum.Material.Neon, transparency = 0.55 })
	self.lane = item
	return item
end

-- Draw the hazard for this frame. `plan` positions are {x,y,z}; `pos` is the hazard's position now;
-- `zone` is Hazards.zone(plan, PlayerRadius): the ring is drawn exactly there, because it IS the hit rule.
function SkyArt:showHazard(plan, pos, now, zone)
	local item = self:hazardModel(plan.kind)
	setWeight(item, 1, self.folder)
	item.billboard.Enabled = not plan.locked or (math.floor(now * 6) % 2 == 0)
	item.lights[1].Enabled = math.floor(now * 4) % 2 == 0
	local p = Vector3.new(pos.x, pos.y, pos.z)
	local v = Vector3.new(plan.velocity.x, plan.velocity.y, plan.velocity.z)
	local hv = Vector3.new(v.X, 0, v.Z)
	local cf = CFrame.lookAt(p, if hv.Magnitude > 0.01 then p + hv else p + Vector3.new(0, 0, -1))
	if item.animate then item.animate(item, cf, now) else place(item, cf) end

	-- the lane: from the hazard through the target and a little beyond; yellow while it tracks you,
	-- red once it has locked. The ring is where not to stand: a hit needs you inside it (Hazards.checkHit).
	local lane = self:laneItem()
	local target = Vector3.new(plan.target.x, plan.target.y, plan.target.z)
	local beyond = target + (if v.Magnitude > 0 then v.Unit * 30 else Vector3.zero)
	local len = (beyond - p).Magnitude
	if plan.t > plan.arriveAt or len < 1 then
		setWeight(lane, 0, self.folder)
		return
	end
	setWeight(lane, 1, self.folder)
	local colour = if plan.locked then rgb(255, 60, 60) else rgb(255, 210, 60)
	local laneE, zoneE = lane.entries[1], lane.entries[2]
	laneE.part.Color = colour
	laneE.part.Size = Vector3.new(0.35, 0.35, len)
	laneE.part.CFrame = CFrame.lookAt(p:Lerp(beyond, 0.5), beyond)
	local d = 2 * zone.radius
	zoneE.part.Color = colour
	zoneE.part.Size = Vector3.new(0.3, d, d)
	zoneE.part.CFrame = CFrame.new(zone.x, zone.y - 3, zone.z) * UPRIGHT
end

function SkyArt:hideHazard(kind)
	local item = self.hazardModels[kind]
	if item then
		item.billboard.Enabled = false
		setWeight(item, 0, self.folder)
	end
	if self.lane then setWeight(self.lane, 0, self.folder) end
end

-- ─────────────────────────────────────────────── weather + lightning

local WEATHER = {
	petals = { Color = { 255, 186, 206 }, Size = 0.45, Lifetime = { 6, 9 }, Speed = { 1, 3 }, LightEmission = 0.1, Acceleration = Vector3.new(0.6, -1.4, 0.3), Transparency = 0.1 },
	mist = { Color = { 255, 255, 255 }, Size = 22, Lifetime = { 6, 9 }, Speed = { 1, 3 }, LightEmission = 0.2, Acceleration = Vector3.zero, Transparency = 0.86 },
	rain = { Color = { 190, 200, 230 }, Size = 0.15, Lifetime = { 1, 1.4 }, Speed = { 90, 110 }, LightEmission = 0.2, Acceleration = Vector3.new(0, -40, 0), Transparency = 0.35, streak = true },
	ice = { Color = { 220, 240, 255 }, Size = 0.22, Lifetime = { 2.5, 4 }, Speed = { 1, 2 }, LightEmission = 1, Acceleration = Vector3.zero, Transparency = 0.1 },
	stardust = { Color = { 200, 212, 255 }, Size = 0.28, Lifetime = { 5, 8 }, Speed = { 0.2, 0.8 }, LightEmission = 1, Acceleration = Vector3.zero, Transparency = 0.2 },
}

function SkyArt.hasWeather(kind)
	return WEATHER[kind] ~= nil
end

-- rates: { [kind] = particles per second }. The host rides above the camera.
function SkyArt:updateWeather(rates, cam)
	if self.weatherHost == nil then
		local host = Instance.new("Part")
		host.Name = "WeatherHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = Vector3.new(140, 2, 140)
		self.weatherHost = host
		self.emitters = {}
	end
	-- the budget, enforced here: at most MaxWeatherEmitters on, summed rate at most MaxEmitterRate
	-- (EnvBands.capRates; review round 2 measured 5 on at once after fast teleports)
	local budget = self.cfg.Budget or {}
	local capped = self.EnvBands.capRates(rates, math.min(budget.MaxWeatherEmitters or 2, budget.MaxEmitters or 2),
		budget.MaxEmitterRate or 60, 0.05)
	local anyOn = false
	for kind, def in WEATHER do
		local rate = capped[kind] or 0
		local pe = self.emitters[kind]
		if pe == nil and rate > 0.05 then
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
			pe.EmissionDirection = if def.streak then Enum.NormalId.Bottom else Enum.NormalId.Top
			if def.streak then pe.Orientation = Enum.ParticleOrientation.VelocityParallel end
			pe.Shape = Enum.ParticleEmitterShape.Box
			pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			pe.Rate = 0
			pe.Enabled = false
			pe.Parent = self.weatherHost
			self.emitters[kind] = pe
		end
		if pe then
			local on = rate > 0.05
			pe.Enabled = on
			if math.abs((pe.Rate or 0) - rate) > 0.25 or (not on and pe.Rate ~= 0) then
				pe.Rate = if on then rate else 0
			end
			anyOn = anyOn or on
		end
	end
	if anyOn then
		self.weatherHost.Parent = self.folder
		self.weatherHost.CFrame = CFrame.new(cam + Vector3.new(0, 30, 0))
	else
		self.weatherHost.Parent = nil
	end
end

function SkyArt:flashBolt(cam, visible)
	if self.bolt == nil then
		local item = newItem("Lightning")
		for _ = 1, 5 do
			addPart(item, { name = "Bolt", size = Vector3.new(1.4, 1.4, 60), color = rgb(220, 230, 255), material = Enum.Material.Neon })
		end
		self.bolt = item
	end
	if not visible then
		setWeight(self.bolt, 0, self.folder)
		return
	end
	local r = self.rand
	local a = r() * math.pi * 2
	local d = 400 + r() * 500
	local p = cam + Vector3.new(math.sin(a) * d, 220, math.cos(a) * d)
	for _, e in self.bolt.entries do
		local nextP = p + Vector3.new((r() - 0.5) * 70, -90 - r() * 40, (r() - 0.5) * 70)
		e.part.Size = Vector3.new(1.4, 1.4, (nextP - p).Magnitude)
		e.part.CFrame = CFrame.lookAt(p:Lerp(nextP, 0.5), nextP)
		p = nextP
	end
	setWeight(self.bolt, 1, self.folder)
end

return SkyArt
