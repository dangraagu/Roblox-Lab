-- GardenArt.luau: Gnome Garden Defense's models and eye candy, built in code from Parts (no assets).
--
-- Two users:
--   * the SERVER builds the gnomes with GardenArt.gnome(kind, level) (replicated: everyone sees your garden);
--   * the CLIENT builds everything else for its own garden only, through GardenArt.new(folder, rand, deps):
--     the bugs (from the GardenTick snapshots), the band scenery, critters, weather and the hazards.
-- Everything the client builds is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off, CastShadow off,
-- built only when a band first needs it, and UNPARENTED when its weight falls to zero, so a band you are not in
-- costs no draw calls. Budgets (Config.Budget) are enforced here and measured by
-- robloxemu/check_gnomegardendefense_env.luau at every band and seam.
--
-- Dependencies arrive as arguments (a bare require("./X") is invalid in Roblox):
--   GardenArt.new(folder, rand, { Config = Config, EnvBands = EnvBands, PathGen = PathGen })

local GardenArt = {}
GardenArt.__index = GardenArt

-- Nothing Roblox-only runs when this module LOADS (the tables below hold plain numbers), so the luau CLI can
-- require it: tests/EnvConfig.spec.luau checks that every band's pieces, critters, weather and hazards exist.
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function C(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local function cyl() return Enum.PartType.Cylinder end
local function ball() return Enum.PartType.Ball end
local function upright() return CFrame.Angles(0, 0, math.rad(90)) end -- a Cylinder's axis is X; this stands it up

--=========================================================================== the gnomes (server-built)

-- hat colour per kind, body colour per level
local GNOME_LOOK = {
	pebble = { hat = { 200, 40, 40 }, tool = { 120, 90, 60 } },
	sprinkler = { hat = { 40, 120, 220 }, tool = { 150, 210, 255 } },
	mushroom = { hat = { 150, 60, 190 }, tool = { 235, 225, 210 } },
	lantern = { hat = { 240, 180, 40 }, tool = { 255, 230, 140 } },
}
local LEVEL_COAT = { { 70, 140, 70 }, { 60, 110, 170 }, { 150, 110, 40 } }

local function gnomePart(model, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.Parent = model
	return p
end

-- A garden gnome of `kind` at `level`, standing at CFrame `at` (feet on the pad). 5 parts; bigger per level.
-- A tap on any part of it picks its pad: View.client tests the tap's ray against the gnome's column (Config.Camera).
function GardenArt.gnome(kind: string, level: number, at: CFrame): Model
	local look = GNOME_LOOK[kind] or GNOME_LOOK.pebble
	local s = 1 + 0.15 * (level - 1)
	local m = Instance.new("Model")
	m.Name = "Gnome"
	local body = gnomePart(m, "Body", Vector3.new(1.8, 2.2, 1.8) * s, at * CFrame.new(0, 1.1 * s, 0),
		C(LEVEL_COAT[level] or LEVEL_COAT[1]), Enum.Material.SmoothPlastic)
	gnomePart(m, "Head", Vector3.new(1.4, 1.4, 1.4) * s, at * CFrame.new(0, 2.8 * s, 0), rgb(255, 214, 180), nil, ball())
	gnomePart(m, "Beard", Vector3.new(1.2, 1.0, 0.5) * s, at * CFrame.new(0, 2.25 * s, -0.55 * s), rgb(245, 245, 245))
	gnomePart(m, "Hat", Vector3.new(1.6, 1.7, 1.6) * s, at * CFrame.new(0, 4.0 * s, 0), C(look.hat))
	local tool = gnomePart(m, "Tool", Vector3.new(0.4, 1.4, 0.4) * s, at * CFrame.new(0.9 * s, 1.6 * s, -0.3 * s), C(look.tool),
		if kind == "lantern" then Enum.Material.Neon else nil)
	if kind == "lantern" then tool.Size = Vector3.new(0.8, 0.8, 0.8) * s end
	m.PrimaryPart = body
	return m
end

--=========================================================================== items: parts that fade together

local function newItem(name)
	return { name = name, entries = {}, beams = {}, lights = {}, shown = false, weight = 0 }
end

local function addPart(item, props)
	local p = Instance.new("Part")
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
			for _, l in item.lights do l.Enabled = false end
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
	for _, b in item.beams do b.beam.Enabled = w > 0.05 end
	for _, l in item.lights do l.Enabled = w > 0.3 end
end

local function place(item, root)
	for _, e in item.entries do
		e.part.CFrame = root * e.offset
	end
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
	beam.Width0 = props.width or 20
	beam.Width1 = props.width or 20
	beam.CurveSize0 = props.curve or 0
	beam.CurveSize1 = -(props.curve or 0)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Segments = 16
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, props.transparency or 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Enabled = false
	beam.Parent = host
	table.insert(item.beams, { beam = beam })
	return beam
end

--=========================================================================== scenery pieces (bed-relative)
-- Bed coordinates: x 0..96 (hedge gap to carrot patch), z 0..72 (north to south), the deck south of z = 76.
-- Every piece stands OUTSIDE the bed (on the hedge line, the verges or the sky), so nothing ever hides a pad,
-- a gnome or the path from the deck camera.

local function ring(n, cx, cz, rx, rz, i)
	local a = (i - 0.5) / n * math.pi * 2
	return cx + math.cos(a) * rx, cz + math.sin(a) * rz
end

-- positions along the hedge line (outside the bed): north edge, then the east/west verges
local function hedgeSpots(n, inset)
	local out = {}
	for i = 1, n do
		local f = (i - 0.5) / n
		if i % 3 == 0 then
			table.insert(out, { x = -8 + inset, z = f * 72 })
		elseif i % 3 == 1 then
			table.insert(out, { x = f * 112, z = -8 + inset })
		else
			table.insert(out, { x = 104 - inset, z = f * 60 })
		end
	end
	return out
end

local PIECES = {}
PIECES.seedlings = function(item)
	for i, s in hedgeSpots(12, 2) do
		addPart(item, { name = "Seedling", size = Vector3.new(0.4, 1.6, 0.4), color = rgb(110, 200, 90), offset = CFrame.new(s.x, 0.8, s.z) })
		if i % 2 == 0 then
			addPart(item, { name = "Leaf", size = Vector3.new(1.4, 0.2, 0.8), color = rgb(140, 220, 100), offset = CFrame.new(s.x, 1.6, s.z) })
		end
	end
end
PIECES.dewTufts = function(item)
	for _, s in hedgeSpots(10, 4) do
		addPart(item, { name = "Dew", shape = ball(), size = Vector3.new(0.6, 0.6, 0.6), color = rgb(200, 240, 255), material = Enum.Material.Glass, transparency = 0.3, offset = CFrame.new(s.x, 0.4, s.z) })
	end
end
PIECES.blossomTrees = function(item)
	for i = 1, 5 do
		local x, z = -12 + i * 26, -12
		addPart(item, { name = "Trunk", size = Vector3.new(1.4, 9, 1.4), color = rgb(110, 75, 50), offset = CFrame.new(x, 4.5, z) })
		addPart(item, { name = "Blossom", shape = ball(), size = Vector3.new(9, 7, 9), color = rgb(255, 190, 215), offset = CFrame.new(x, 10, z) })
	end
end
PIECES.sunflowers = function(item)
	for _, s in hedgeSpots(9, 1) do
		addPart(item, { name = "Stem", size = Vector3.new(0.4, 6, 0.4), color = rgb(80, 150, 60), offset = CFrame.new(s.x, 3, s.z) })
		addPart(item, { name = "Bloom", shape = cyl(), size = Vector3.new(0.5, 3, 3), color = rgb(255, 205, 40), offset = CFrame.new(s.x, 6.2, s.z) * CFrame.Angles(0, math.rad(90), 0) })
	end
end
PIECES.bunting = function(item)
	for i = 1, 14 do
		addPart(item, { name = "Flag", size = Vector3.new(1.2, 1.2, 0.1), color = if i % 3 == 0 then rgb(240, 80, 80) elseif i % 3 == 1 then rgb(250, 210, 60) else rgb(80, 160, 240),
			offset = CFrame.new(i * 8 - 4, 7 + math.sin(i) * 0.4, -16) })
	end
end
PIECES.puddles = function(item)
	for i = 1, 6 do
		local x, z = ring(6, 48, 36, 62, 50, i)
		addPart(item, { name = "Puddle", shape = cyl(), size = Vector3.new(0.1, 5, 5), color = rgb(120, 140, 190), material = Enum.Material.Glass, transparency = 0.35, offset = CFrame.new(x, 0.06, z) * upright() })
	end
end
PIECES.rainbow = function(item)
	local host = addPart(item, { name = "RainbowHost", size = Vector3.new(1, 1, 1), transparency = 1, offset = CFrame.new(48, 0, -60) })
	local colours = { rgb(255, 80, 80), rgb(255, 200, 60), rgb(90, 200, 120), rgb(80, 140, 255) }
	for i, c in colours do
		addBeam(item, host, Vector3.new(-70 + i * 3, 0, 0), Vector3.new(70 - i * 3, 0, 0), { color = ColorSequence.new(c), width = 3, curve = 90, transparency = 0.45 })
	end
end
PIECES.pumpkins = function(item)
	for _, s in hedgeSpots(8, 3) do
		addPart(item, { name = "Pumpkin", shape = ball(), size = Vector3.new(2.6, 2, 2.6), color = rgb(240, 130, 30), offset = CFrame.new(s.x, 1, s.z) })
	end
end
PIECES.hayBales = function(item)
	for i = 1, 4 do
		addPart(item, { name = "Hay", shape = cyl(), size = Vector3.new(4, 3.4, 3.4), color = rgb(225, 190, 90), offset = CFrame.new(-12, 1.7, i * 16) })
	end
end
PIECES.lanterns = function(item)
	for i = 1, 12 do
		addPart(item, { name = "PaperLantern", shape = ball(), size = Vector3.new(1.4, 1.8, 1.4), color = rgb(255, 170, 70), material = Enum.Material.Neon,
			offset = CFrame.new(i * 9 - 6, 7.5, -16) })
	end
end
-- Where the sky pieces hang (bed coordinates). View.client looks up here when their band is celebrated: the
-- garden view looks down at the bed, so without it the HARVEST MOON and the AURORA would never be on screen.
local SKY = { moon = { x = 48, y = 70, z = -260 }, aurora = { x = 48, y = 100, z = -200 } }
function GardenArt.skyAnchor(id: string): { x: number, y: number, z: number }?
	return SKY[id]
end

PIECES.moon = function(item)
	local p = addPart(item, { name = "HarvestMoon", shape = ball(), size = Vector3.new(60, 60, 60), color = rgb(255, 214, 140), material = Enum.Material.Neon, offset = CFrame.new(SKY.moon.x, SKY.moon.y, SKY.moon.z) })
	local light = Instance.new("PointLight")
	light.Name = "MoonGlow"
	light.Color = rgb(255, 210, 150)
	light.Range = 60
	light.Brightness = 1
	light.Enabled = false
	light.Parent = p
	table.insert(item.lights, light)
end
PIECES.frostHedge = function(item)
	for i = 1, 8 do
		addPart(item, { name = "Frost", size = Vector3.new(16, 0.4, 2.4), color = rgb(235, 245, 255), material = Enum.Material.Ice, offset = CFrame.new(i * 16 - 16, 7.2, -16) })
	end
end
PIECES.birdbath = function(item)
	addPart(item, { name = "BathStand", shape = cyl(), size = Vector3.new(3, 1, 1), color = rgb(190, 190, 200), offset = CFrame.new(-10, 1.5, 70) * upright() })
	addPart(item, { name = "BathIce", shape = cyl(), size = Vector3.new(0.4, 3.4, 3.4), color = rgb(200, 230, 255), material = Enum.Material.Ice, offset = CFrame.new(-10, 3.1, 70) * upright() })
end
PIECES.snowHedge = function(item)
	for i = 1, 8 do
		addPart(item, { name = "SnowCap", size = Vector3.new(16, 1, 2.8), color = rgb(250, 252, 255), material = Enum.Material.Snow, offset = CFrame.new(i * 16 - 16, 7.5, -16) })
	end
end
PIECES.sledge = function(item)
	addPart(item, { name = "Sledge", size = Vector3.new(5, 0.6, 2.4), color = rgb(190, 60, 50), offset = CFrame.new(110, 0.8, 84) })
	addPart(item, { name = "Runner", size = Vector3.new(5.4, 0.2, 0.2), color = rgb(90, 90, 100), offset = CFrame.new(110, 0.3, 83) })
end
PIECES.snowdrifts = function(item)
	for i = 1, 7 do
		local x, z = ring(7, 48, 36, 64, 52, i)
		addPart(item, { name = "Drift", shape = ball(), size = Vector3.new(9, 2.4, 6), color = rgb(245, 248, 255), material = Enum.Material.Snow, offset = CFrame.new(x, 0.4, z) })
	end
end
PIECES.snowman = function(item)
	addPart(item, { name = "SnowBase", shape = ball(), size = Vector3.new(4, 4, 4), color = rgb(250, 252, 255), material = Enum.Material.Snow, offset = CFrame.new(114, 2, 70) })
	addPart(item, { name = "SnowHead", shape = ball(), size = Vector3.new(2.6, 2.6, 2.6), color = rgb(250, 252, 255), material = Enum.Material.Snow, offset = CFrame.new(114, 5, 70) })
	addPart(item, { name = "Nose", size = Vector3.new(0.3, 0.3, 1.2), color = rgb(240, 120, 30), offset = CFrame.new(114, 5, 68.8) })
end
PIECES.lampPosts = function(item)
	for i = 1, 4 do
		local x = i * 24 - 12
		addPart(item, { name = "Post", size = Vector3.new(0.5, 8, 0.5), color = rgb(40, 40, 50), offset = CFrame.new(x, 4, -14) })
		addPart(item, { name = "Lamp", shape = ball(), size = Vector3.new(1.4, 1.4, 1.4), color = rgb(255, 235, 170), material = Enum.Material.Neon, offset = CFrame.new(x, 8.3, -14) })
	end
end
PIECES.aurora = function(item)
	local host = addPart(item, { name = "AuroraHost", size = Vector3.new(1, 1, 1), transparency = 1, offset = CFrame.new(SKY.aurora.x, SKY.aurora.y - 10, SKY.aurora.z) })
	local colours = { rgb(60, 255, 170), rgb(90, 200, 255), rgb(170, 110, 255) }
	for i, c in colours do
		addBeam(item, host, Vector3.new(-180, i * 12, 0), Vector3.new(180, i * 12 - 20, 0), { color = ColorSequence.new(c), width = 36, curve = 40 * (if i % 2 == 0 then 1 else -1), transparency = 0.35 })
	end
end

--=========================================================================== critters

local CRITTERS = {}
CRITTERS.butterfly = function(item)
	addPart(item, { name = "WingL", size = Vector3.new(0.7, 0.05, 0.6), color = rgb(255, 170, 60), offset = CFrame.new(-0.35, 0, 0) })
	addPart(item, { name = "WingR", size = Vector3.new(0.7, 0.05, 0.6), color = rgb(255, 170, 60), offset = CFrame.new(0.35, 0, 0) })
end
CRITTERS.bee = function(item)
	addPart(item, { name = "Bee", shape = ball(), size = Vector3.new(0.5, 0.4, 0.7), color = rgb(250, 200, 40) })
end
CRITTERS.dragonfly = function(item)
	addPart(item, { name = "Dragonfly", size = Vector3.new(0.2, 0.2, 1.4), color = rgb(60, 200, 210), material = Enum.Material.Neon, transparency = 0.2 })
end
CRITTERS.robin = function(item)
	addPart(item, { name = "Robin", shape = ball(), size = Vector3.new(0.9, 0.9, 1.2), color = rgb(200, 90, 60) })
end
CRITTERS.firefly = function(item)
	addPart(item, { name = "Firefly", shape = ball(), size = Vector3.new(0.3, 0.3, 0.3), color = rgb(240, 255, 120), material = Enum.Material.Neon })
end
CRITTERS.owl = function(item)
	addPart(item, { name = "Owl", shape = ball(), size = Vector3.new(1.6, 1.8, 1.6), color = rgb(140, 110, 80) })
end
CRITTERS.crow = function(item)
	addPart(item, { name = "Crow", size = Vector3.new(2.4, 0.2, 1), color = rgb(30, 30, 35) })
end
CRITTERS.shootingStar = function(item)
	addPart(item, { name = "ShootingStar", size = Vector3.new(0.6, 0.6, 9), color = rgb(255, 250, 220), material = Enum.Material.Neon })
end
CRITTERS.hare = function(item)
	addPart(item, { name = "Hare", shape = ball(), size = Vector3.new(1.2, 1.2, 1.8), color = rgb(245, 245, 250), material = Enum.Material.Snow })
end

--=========================================================================== weather

local WEATHER = {
	fluff = { Color = { 255, 255, 240 }, Size = 0.3, Lifetime = { 7, 10 }, Speed = { 0.4, 1.2 }, LightEmission = 0.3, Acceleration = { 0.5, 0.25, 0.15 }, Transparency = 0.15 },
	petals = { Color = { 255, 186, 206 }, Size = 0.45, Lifetime = { 6, 9 }, Speed = { 1, 3 }, LightEmission = 0.1, Acceleration = { 0.6, -1.4, 0.3 }, Transparency = 0.1 },
	pollen = { Color = { 255, 240, 150 }, Size = 0.2, Lifetime = { 5, 8 }, Speed = { 0.3, 1 }, LightEmission = 0.4, Acceleration = { 0.2, 0.1, 0 }, Transparency = 0.2 },
	rain = { Color = { 190, 200, 230 }, Size = 0.15, Lifetime = { 1, 1.4 }, Speed = { 60, 80 }, LightEmission = 0.2, Acceleration = { 0, -40, 0 }, Transparency = 0.35, streak = true },
	leaves = { Color = { 230, 140, 50 }, Size = 0.5, Lifetime = { 6, 9 }, Speed = { 1, 2 }, LightEmission = 0, Acceleration = { 0.8, -1.2, 0.4 }, Transparency = 0.05 },
	fireflies = { Color = { 240, 255, 120 }, Size = 0.25, Lifetime = { 3, 6 }, Speed = { 0.2, 0.6 }, LightEmission = 1, Acceleration = { 0, 0, 0 }, Transparency = 0.1 },
	frost = { Color = { 220, 240, 255 }, Size = 0.22, Lifetime = { 2.5, 4 }, Speed = { 0.5, 1 }, LightEmission = 1, Acceleration = { 0, 0, 0 }, Transparency = 0.15 },
	snow = { Color = { 250, 252, 255 }, Size = 0.35, Lifetime = { 5, 8 }, Speed = { 2, 4 }, LightEmission = 0.3, Acceleration = { 0.3, -2.5, 0.2 }, Transparency = 0.05 },
	stardust = { Color = { 200, 212, 255 }, Size = 0.28, Lifetime = { 5, 8 }, Speed = { 0.2, 0.8 }, LightEmission = 1, Acceleration = { 0, 0, 0 }, Transparency = 0.2 },
}

--=========================================================================== hazards (vertical drops)

local HAZARD_LOOK = {
	acorn = { color = { 150, 100, 50 }, size = 1.6 },
	apple = { color = { 220, 40, 40 }, size = 1.8 },
	pinecone = { color = { 120, 80, 45 }, size = 1.8 },
	icicle = { color = { 200, 235, 255 }, size = 1.6, material = "Ice" },
	snowClump = { color = { 250, 252, 255 }, size = 2.4, material = "Snow" },
	starShard = { color = { 255, 245, 170 }, size = 1.4, material = "Neon" },
	sprinklerJet = { color = { 120, 190, 255 }, size = 1.4, material = "Glass", jet = true },
	molehill = { color = { 100, 70, 45 }, size = 2.6 },
}

--=========================================================================== bugs (client-drawn from GardenTick)

local BUG_LOOK = {
	aphid = { body = { 120, 200, 80 }, size = 1.2 },
	ant = { body = { 60, 40, 35 }, size = 1.0 },
	beetle = { body = { 40, 70, 110 }, size = 1.6, shell = { 80, 120, 170 } },
	wasp = { body = { 250, 200, 40 }, size = 1.3, stripe = { 30, 30, 30 } },
	snail = { body = { 190, 170, 130 }, size = 1.8, shell = { 170, 100, 60 } },
	stag = { body = { 80, 50, 30 }, size = 4.0, shell = { 130, 80, 40 } },
	baron = { body = { 200, 180, 140 }, size = 4.4, shell = { 190, 120, 60 } },
	queen = { body = { 160, 210, 120 }, size = 5.0, shell = { 255, 200, 80 } },
	mantis = { body = { 170, 230, 255 }, size = 4.6, shell = { 120, 200, 255 } },
}

-- at most 3 parts per bug (Config.Budget.MaxBugParts / MaxRenderedBugs)
local function buildBug(kind)
	local look = BUG_LOOK[kind] or BUG_LOOK.aphid
	local item = newItem("Bug_" .. kind)
	local s = look.size
	addPart(item, { name = "Body", shape = ball(), size = Vector3.new(s, s * 0.7, s * 1.3), color = C(look.body) })
	if look.shell then
		addPart(item, { name = "Shell", shape = ball(), size = Vector3.new(s * 0.9, s * 0.6, s * 0.9), color = C(look.shell), offset = CFrame.new(0, s * 0.35, s * 0.15) })
	elseif look.stripe then
		addPart(item, { name = "Stripe", size = Vector3.new(s * 1.02, s * 0.2, s * 0.25), color = C(look.stripe), offset = CFrame.new(0, 0, s * 0.2) })
	end
	addPart(item, { name = "Head", shape = ball(), size = Vector3.new(s * 0.55, s * 0.55, s * 0.55), color = C(look.body), offset = CFrame.new(0, s * 0.1, -s * 0.75) })
	return item
end

--=========================================================================== construction

function GardenArt.new(folder, rand, deps)
	local self = setmetatable({}, GardenArt)
	self.folder = folder
	self.rand = rand
	self.cfg = deps.Config
	self.EnvBands = deps.EnvBands
	self.PathGen = deps.PathGen
	self.origin = CFrame.new()  -- the bed's corner (x = 0, z = 0) in world space
	self.pieces = {}
	self.critters = {}
	self.hazardModels = {}
	self.bugPool = {}
	self.bugs = {}       -- id -> { item, kind, s0, s1, t }
	self.bugCount = 0
	return self
end

function GardenArt.hasPiece(id) return PIECES[id] ~= nil end
function GardenArt.hasCritter(kind) return CRITTERS[kind] ~= nil end
function GardenArt.hasWeather(kind) return WEATHER[kind] ~= nil end
function GardenArt.hasHazard(kind) return HAZARD_LOOK[kind] ~= nil end
function GardenArt.hasBug(kind) return BUG_LOOK[kind] ~= nil end

-- Move everything to a (new) bed origin: the garden's slot. Pieces re-place on their next update.
function GardenArt:setOrigin(cf: CFrame)
	self.origin = cf
	for _, item in self.pieces do item.placed = false end
end

function GardenArt:updatePiece(id, w)
	local item = self.pieces[id]
	if item == nil then
		if w <= 0.01 then return end
		local build = PIECES[id]
		if build == nil then return end
		item = newItem(id)
		build(item)
		self.pieces[id] = item
	end
	setWeight(item, w, self.folder)
	if item.shown and not item.placed then
		place(item, self.origin)
		item.placed = true
	end
end

-- desired: { [kind] = count }. Critters wander on a ring around the bed's centre.
function GardenArt:updateCritters(desired, dt, now)
	local E = self.EnvBands
	local specs = self.cfg.Env.Critters
	local centreW = self.origin * CFrame.new(48, 0, 36)
	local centre = { x = centreW.X, y = centreW.Y, z = centreW.Z }
	for kind in desired do
		if self.critters[kind] == nil then self.critters[kind] = {} end
	end
	for kind, list in self.critters do
		local want = desired[kind] or 0
		local spec = specs[kind]
		local active = 0
		for _, c in list do
			if c.active then
				c.pos = { x = c.pos.x + c.vel.x * dt, y = c.pos.y + c.vel.y * dt, z = c.pos.z + c.vel.z * dt }
				if E.ambientExpired(c.pos, centre, spec) then
					c.active = false
					setWeight(c.item, 0, self.folder)
				else
					active += 1
					if active > want then c.leaving = true end
					c.w = E.approach(c.w, if c.leaving then 0 else 1, dt, 0.35)
					if c.leaving and c.w < 0.03 then
						c.active = false
						setWeight(c.item, 0, self.folder)
					else
						setWeight(c.item, c.w, self.folder)
						local p = Vector3.new(c.pos.x, c.pos.y, c.pos.z)
						local hv = Vector3.new(c.vel.x, 0, c.vel.z)
						local flap = math.sin(now * 12 + c.phase) * 0.15
						place(c.item, CFrame.lookAt(p, if hv.Magnitude > 0.01 then p + hv else p + Vector3.new(0, 0, -1)) * CFrame.new(0, flap, 0))
					end
				end
			end
		end
		if active < want and spec then
			local base = E.ambientSpawn(centre, spec, self.rand)
			local c = nil
			for _, existing in list do
				if not existing.active then c = existing; break end
			end
			if c == nil then
				local item = newItem("Critter_" .. kind)
				CRITTERS[kind](item)
				c = { item = item, active = false }
				table.insert(list, c)
			end
			c.active = true
			c.leaving = false
			c.w = 0
			c.phase = self.rand() * 6.28
			c.pos = base.pos
			c.vel = base.vel
		end
	end
end

-- rates: { [kind] = particles per second }. The host hangs over the bed.
function GardenArt:updateWeather(rates)
	if self.weatherHost == nil then
		local host = Instance.new("Part")
		host.Name = "WeatherHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = Vector3.new(130, 2, 110)
		self.weatherHost = host
		self.emitters = {}
	end
	-- the budget, enforced here: at most MaxWeatherEmitters on, summed rate at most MaxEmitterRate
	local budget = self.cfg.Budget
	local capped = self.EnvBands.capRates(rates, math.min(budget.MaxWeatherEmitters, budget.MaxEmitters),
		budget.MaxEmitterRate, 0.05)
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
			pe.Acceleration = Vector3.new(def.Acceleration[1], def.Acceleration[2], def.Acceleration[3])
			pe.SpreadAngle = if def.streak then Vector2.new(4, 4) else Vector2.new(180, 180)
			pe.EmissionDirection = if def.streak then Enum.NormalId.Bottom else Enum.NormalId.Top
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
		self.weatherHost.CFrame = self.origin * CFrame.new(48, 24, 36)
	else
		self.weatherHost.Parent = nil
	end
end

-- One-shot sparkle bursts (a kill, a plant, a boss) share ONE emitter, so they never add to the emitter budget
-- beyond it: the budget's MaxEmitters counts the weather emitters plus this one.
function GardenArt:burst(worldPos: Vector3, color: Color3, count: number)
	if self.burstHost == nil then
		local host = Instance.new("Part")
		host.Name = "BurstHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = Vector3.new(1, 1, 1)
		host.Parent = self.folder
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Burst"
		pe.Rate = 0
		pe.Lifetime = NumberRange.new(0.5, 0.9)
		pe.Speed = NumberRange.new(6, 12)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(0.35)
		pe.LightEmission = 1
		pe.Acceleration = { 0, -14, 0 }
		pe.Parent = host
		self.burstHost = host
		self.burstEmitter = pe
	end
	self.burstHost.CFrame = CFrame.new(worldPos)
	self.burstEmitter.Color = ColorSequence.new(color)
	pcall(function() self.burstEmitter:Emit(count) end)
end

--=========================================================================== bugs

-- snapshot: { { id, kind, s, hp } } from GardenTick. Interpolated from the last position to the new one
-- over one tick (Config.Dt), capped at MaxRenderedBugs (the furthest along are drawn first: they matter most).
function GardenArt:setBugs(snapshot, path, now)
	local cap = self.cfg.Budget.MaxRenderedBugs
	local list = table.clone(snapshot)
	table.sort(list, function(a, b) return (a[3] or 0) > (b[3] or 0) end)
	local seen = {}
	for i, b in list do
		if i > cap then break end
		local id, kind, s = b[1], b[2], b[3]
		seen[id] = true
		local v = self.bugs[id]
		if v == nil then
			local pool = self.bugPool[kind]
			local item = pool and table.remove(pool) or buildBug(kind)
			v = { item = item, kind = kind, s0 = s, s1 = s, t = now }
			self.bugs[id] = v
			self.bugCount += 1
		else
			v.s0 = self:bugS(v, now)
			v.s1 = s
			v.t = now
		end
		v.hp = b[4]
	end
	for id, v in self.bugs do
		if not seen[id] then self:dropBug(id) end
	end
	self.path = path
end

function GardenArt:bugS(v, now)
	local f = math.clamp((now - v.t) / self.cfg.Dt, 0, 1)
	return v.s0 + (v.s1 - v.s0) * f
end

function GardenArt:dropBug(id)
	local v = self.bugs[id]
	if not v then return end
	self.bugs[id] = nil
	self.bugCount -= 1
	setWeight(v.item, 0, self.folder)
	local pool = self.bugPool[v.kind]
	if pool == nil then
		pool = {}
		self.bugPool[v.kind] = pool
	end
	table.insert(pool, v.item)
end

function GardenArt:clearBugs()
	for id in self.bugs do self:dropBug(id) end
end

function GardenArt:drawBugs(now)
	local path = self.path
	if path == nil then return end
	for _, v in self.bugs do
		local s = self:bugS(v, now)
		local x, z = self.PathGen.posAt(path, s)
		local xa, za = self.PathGen.posAt(path, s + 1)
		local look = Vector3.new(xa - x, 0, za - z)
		local p = Vector3.new(x, 0.6, z)
		local cf = self.origin * CFrame.lookAt(p, if look.Magnitude > 0.01 then p + look else p + Vector3.new(1, 0, 0))
		setWeight(v.item, 1, self.folder)
		place(v.item, cf * CFrame.new(0, math.abs(math.sin(now * 10 + s)) * 0.15, 0))
	end
end

function GardenArt:bugWorldPos(id)
	local v = self.bugs[id]
	if not v or not self.path then return nil end
	local x, z = self.PathGen.posAt(self.path, v.s1)
	return (self.origin * CFrame.new(x, 1, z)).Position
end

--=========================================================================== hazards

function GardenArt:hazardModel(kind)
	local item = self.hazardModels[kind]
	if item then return item end
	local look = HAZARD_LOOK[kind] or HAZARD_LOOK.acorn
	item = newItem("Hazard_" .. kind)
	local p = addPart(item, { name = "Hazard_" .. kind, shape = if look.jet then cyl() else ball(),
		size = if look.jet then Vector3.new(4, look.size, look.size) else Vector3.new(look.size, look.size, look.size),
		color = C(look.color), material = if look.material then (Enum.Material :: any)[look.material] else nil })
	local bb = Instance.new("BillboardGui")
	bb.Name = "HazardWarning"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(46, 46)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = p
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "⚠️"
	mark.TextScaled = true
	mark.Font = Enum.Font.GothamBlack
	mark.TextColor3 = rgb(255, 220, 60)
	mark.Parent = bb
	item.billboard = bb
	item.jet = look.jet
	self.hazardModels[kind] = item
	return item
end

function GardenArt:ringItem()
	if self.ring then return self.ring end
	local item = newItem("HazardRing")
	addPart(item, { name = "HazardZone", shape = cyl(), size = Vector3.new(0.3, 6, 6), color = rgb(255, 60, 60), material = Enum.Material.Neon, transparency = 0.45 })
	self.ring = item
	return item
end

-- Draw the hazard for this frame. `pos` = where it is now ({x,y,z}); `zone` = Hazards.zone(plan, PlayerRadius)
-- while Hazards.threatLive holds, else nil. The red ring is drawn EXACTLY at the zone: it IS the hit rule.
function GardenArt:showHazard(plan, pos, now, zone)
	local item = self:hazardModel(plan.kind)
	setWeight(item, 1, self.folder)
	item.billboard.Enabled = not plan.locked or (math.floor(now * 6) % 2 == 0)
	local p = Vector3.new(pos.x, pos.y, pos.z)
	if item.jet then
		place(item, CFrame.new(p) * upright())
	else
		place(item, CFrame.new(p) * CFrame.Angles(now * 3, now * 2, 0))
	end
	local ringItem = self:ringItem()
	if zone == nil then
		setWeight(ringItem, 0, self.folder)
		return
	end
	setWeight(ringItem, 1, self.folder)
	local e = ringItem.entries[1]
	local d = 2 * zone.radius
	e.part.Color = if plan.locked then rgb(255, 40, 40) else rgb(255, 120, 60)
	e.part.Size = Vector3.new(0.3, d, d)
	e.part.CFrame = CFrame.new(zone.x, zone.y - 2.9, zone.z) * upright()
end

function GardenArt:hideHazard(kind)
	local item = self.hazardModels[kind]
	if item then
		item.billboard.Enabled = false
		setWeight(item, 0, self.folder)
	end
	if self.ring then setWeight(self.ring, 0, self.folder) end
end

return GardenArt
