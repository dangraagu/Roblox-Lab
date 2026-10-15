-- YardArt.luau — Scrapline Tycoon's yard scenery, critters, weather, hazard models, belt items, machine animation
-- and the lift-off, built in code (no assets). CLIENT ONLY: required by src/client/Yard.client.luau; the server
-- never touches it.
--
-- Pattern copied from meteor-drop-tycoon/src/shared/SkyArt.luau (itself plus1-jump's): items that fade together,
-- pooled critters on a ring around the camera, capped weather, a hazard model with its telegraph. Everything here
-- is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off (nothing can be stood on, touched or ray-hit),
-- CastShadow off. Nothing is built until a band first needs it, and anything whose weight falls to zero is
-- UNPARENTED, so a band you are not in costs no draw calls. Red is used by exactly one thing: the hazard ring
-- (Config.Hazards.RingColor), which is the hazard's hit zone.
--
-- Dependencies arrive as arguments (a bare require("./X") is invalid in Roblox):
--   YardArt.new(folder, rand, Config, EnvBands, PlotGeom)
-- Budgets are measured, not assumed: robloxemu/check_scraplinetycoon_yard.luau counts what this module has
-- parented at every band, every frame, against Config.Budget.

local YardArt = {}
YardArt.__index = YardArt

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

--──────────────────────────────────────────────────────────── items: parts that fade together

local function newItem(name)
	return { name = name, entries = {}, beams = {}, trails = {}, lights = {}, emitters = {}, shown = false, weight = 0 }
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
			for _, pe in item.emitters do pe.Enabled = false end
			item.shown = false
		end
		return
	end
	if not item.shown then
		for _, e in item.entries do
			e.part.Parent = folder
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
	for _, pe in item.emitters do pe.Enabled = w > 0.3 end
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
	beam.Width0 = props.width0 or 6
	beam.Width1 = props.width1 or 6
	beam.LightEmission = props.lightEmission or 1
	beam.FaceCamera = props.faceCamera ~= false
	beam.Segments = props.segments or 10
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

--──────────────────────────────────────────────────────────── pieces (static scenery)
-- anchor = "world" (placed once round the whole world, beyond every plot: plot corners end 191 studs out) or
-- "sky" (travels with the camera, like a skybox with depth).

local PIECES = {}

-- the Junkyard: mounds of junk, tyre stacks and rusted car hulks round the horizon
PIECES.junkMounds = function(art)
	local item = newItem("JunkMounds")
	item.anchor = "world"
	item.root = CFrame.new()
	local cols = { rgb(120, 96, 76), rgb(104, 90, 80), rgb(140, 110, 80) }
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * math.pi * 2
		local r = 280 + (i % 3) * 30
		local s = 60 + (i % 4) * 16
		addPart(item, { name = "JunkMound", shape = BALL, size = Vector3.new(s * 1.6, s * 0.6, s * 1.2), color = cols[1 + i % 3],
			material = Enum.Material.CorrodedMetal, offset = CFrame.new(math.sin(a) * r, -s * 0.1, math.cos(a) * r) * CFrame.Angles(0, a, 0) })
	end
	return item
end

PIECES.tyreStacks = function(art)
	local item = newItem("TyreStacks")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + 0.25
		local x, z = math.sin(a) * 235, math.cos(a) * 235
		for j = 0, 1 do
			addPart(item, { name = "TyreStack", shape = CYL, size = Vector3.new(2.4, 7, 7), color = rgb(36, 36, 40),
				material = Enum.Material.Rubber, offset = CFrame.new(x, 1.2 + j * 2.5, z) * UPRIGHT })
		end
	end
	return item
end

PIECES.carHulks = function(art)
	local item = newItem("CarHulks")
	item.anchor = "world"
	item.root = CFrame.new()
	local cols = { rgb(150, 100, 60), rgb(110, 120, 130), rgb(170, 140, 70) }
	for i = 1, 5 do
		local a = (i + 0.3) / 5 * math.pi * 2
		local x, z = math.sin(a) * 255, math.cos(a) * 255
		addPart(item, { name = "CarHulk", size = Vector3.new(14, 5, 7), color = cols[1 + i % 3], material = Enum.Material.CorrodedMetal,
			offset = CFrame.new(x, 2.5, z) * CFrame.Angles(math.rad(6), a, math.rad(4)) })
		addPart(item, { name = "CarRoof", size = Vector3.new(8, 3, 6.4), color = cols[1 + i % 3], material = Enum.Material.CorrodedMetal,
			offset = CFrame.new(x, 6, z) * CFrame.Angles(math.rad(6), a, math.rad(4)) })
	end
	return item
end

-- the Foundry: brick chimneys with smoke plumes
PIECES.brickChimneys = function(art)
	local item = newItem("BrickChimneys")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 5 do
		local a = (i - 0.2) / 5 * math.pi * 2
		local x, z = math.sin(a) * 300, math.cos(a) * 300
		local h = 70 + (i % 3) * 20
		local stack = addPart(item, { name = "BrickChimney", shape = CYL, size = Vector3.new(h, 9, 9), color = rgb(140, 84, 60),
			material = Enum.Material.Brick, offset = CFrame.new(x, h / 2, z) * UPRIGHT })
		if i == 1 then -- one smoke plume: weather (2) + this + the lift-off smoke stay within MaxEmitters 4
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "ChimneySmoke"
			pe.Rate = 4
			pe.Lifetime = NumberRange.new(5, 8)
			pe.Speed = NumberRange.new(4, 7)
			pe.EmissionDirection = Enum.NormalId.Right -- the stood-up cylinder's +X points up
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 18) })
			pe.Color = ColorSequence.new(rgb(120, 118, 116))
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			pe.Enabled = false
			pe.Parent = stack
			table.insert(item.emitters, pe)
		end
	end
	return item
end

-- Press Works: steel girder frames and a water tower
PIECES.girders = function(art)
	local item = newItem("Girders")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 4 do
		local a = (i - 0.6) / 4 * math.pi * 2
		local x, z = math.sin(a) * 270, math.cos(a) * 270
		local base = CFrame.new(x, 0, z) * CFrame.Angles(0, a, 0)
		addPart(item, { name = "GirderPost", size = Vector3.new(3, 60, 3), color = rgb(120, 140, 170), material = Enum.Material.Metal,
			offset = base * CFrame.new(-14, 30, 0) })
		addPart(item, { name = "GirderPost", size = Vector3.new(3, 60, 3), color = rgb(120, 140, 170), material = Enum.Material.Metal,
			offset = base * CFrame.new(14, 30, 0) })
		addPart(item, { name = "GirderBeam", size = Vector3.new(34, 3, 3), color = rgb(120, 140, 170), material = Enum.Material.Metal,
			offset = base * CFrame.new(0, 58, 0) })
	end
	return item
end

PIECES.waterTower = function(art)
	local item = newItem("WaterTower")
	item.anchor = "world"
	item.root = CFrame.new(-230, 0, 120)
	for i = 1, 4 do
		local a = i * math.pi / 2
		addPart(item, { name = "TowerLeg", size = Vector3.new(1.6, 40, 1.6), color = rgb(150, 150, 160), material = Enum.Material.Metal,
			offset = CFrame.new(math.cos(a) * 7, 20, math.sin(a) * 7) })
	end
	addPart(item, { name = "WaterTank", shape = CYL, size = Vector3.new(14, 20, 20), color = rgb(170, 180, 190), material = Enum.Material.Metal,
		offset = CFrame.new(0, 47, 0) * UPRIGHT })
	return item
end

-- the Machine Shop: giant gears turning on far towers
PIECES.farGears = function(art)
	local item = newItem("FarGears")
	item.anchor = "world"
	item.root = CFrame.new()
	item.gears = {}
	for i = 1, 4 do
		local a = (i - 0.35) / 4 * math.pi * 2
		local x, z = math.sin(a) * 320, math.cos(a) * 320
		addPart(item, { name = "GearTower", size = Vector3.new(10, 70, 10), color = rgb(90, 96, 110), material = Enum.Material.Metal,
			offset = CFrame.new(x, 35, z) })
		local _, e = addPart(item, { name = "FarGear", shape = CYL, size = Vector3.new(4, 40, 40), color = rgb(205, 165, 60),
			material = Enum.Material.Metal, offset = CFrame.new(x, 80, z) * CFrame.Angles(0, a + math.pi / 2, 0) })
		table.insert(item.gears, e)
	end
	item.spinParts = true
	return item
end

-- Robot Works: neon signs, holo billboards and searchlights
PIECES.neonSigns = function(art)
	local item = newItem("NeonSigns")
	item.anchor = "world"
	item.root = CFrame.new()
	local cols = { rgb(0, 230, 255), rgb(255, 120, 230), rgb(140, 255, 120), rgb(255, 220, 90) }
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * math.pi * 2
		local x, z = math.sin(a) * 240, math.cos(a) * 240
		addPart(item, { name = "NeonSign", size = Vector3.new(30, 8, 1), color = cols[1 + i % 4], material = Enum.Material.Neon,
			transparency = 0.1, offset = CFrame.lookAt(Vector3.new(x, 30 + (i % 3) * 10, z), Vector3.new(0, 30, 0)) })
	end
	return item
end

PIECES.holoBoards = function(art)
	local item = newItem("HoloBoards")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 3 do
		local a = (i + 0.4) / 3 * math.pi * 2
		local x, z = math.sin(a) * 210, math.cos(a) * 210
		addPart(item, { name = "HoloBoard", size = Vector3.new(26, 16, 0.5), color = rgb(120, 200, 255), material = Enum.Material.ForceField,
			transparency = 0.35, offset = CFrame.lookAt(Vector3.new(x, 26, z), Vector3.new(0, 26, 0)) })
	end
	return item
end

PIECES.searchlights = function(art)
	local item = newItem("Searchlights")
	item.anchor = "world"
	item.root = CFrame.new()
	item.spin = 0.35
	for i = 1, 2 do
		local a = i * math.pi
		local lamp = addPart(item, { name = "Searchlight", shape = BALL, size = Vector3.new(4, 4, 4), color = rgb(230, 240, 255),
			material = Enum.Material.Neon, offset = CFrame.new(math.sin(a) * 205, 6, math.cos(a) * 205) })
		addBeam(item, lamp, Vector3.new(0, 0, 0), Vector3.new(0, 400, -120), { color = ColorSequence.new(rgb(220, 235, 255)),
			width0 = 4, width1 = 40, transparency = 0.7 })
	end
	return item
end

-- the Launch Site: a launch gantry, a big moon and sweeping searchlights
PIECES.gantry = function(art)
	local item = newItem("Gantry")
	item.anchor = "world"
	item.root = CFrame.new(0, 0, -260)
	addPart(item, { name = "GantryTower", size = Vector3.new(10, 110, 10), color = rgb(200, 190, 170), material = Enum.Material.Metal,
		offset = CFrame.new(-12, 55, 0) })
	addPart(item, { name = "GantryArm", size = Vector3.new(16, 3, 3), color = rgb(200, 190, 170), material = Enum.Material.Metal,
		offset = CFrame.new(-2, 90, 0) })
	addPart(item, { name = "GantryRocket", shape = CYL, size = Vector3.new(80, 12, 12), color = rgb(245, 245, 250),
		material = Enum.Material.SmoothPlastic, offset = CFrame.new(8, 44, 0) * UPRIGHT })
	addPart(item, { name = "GantryNose", shape = BALL, size = Vector3.new(12, 16, 12), color = rgb(255, 200, 60),
		material = Enum.Material.SmoothPlastic, offset = CFrame.new(8, 86, 0) })
	return item
end

PIECES.bigMoon = function(art)
	local item = newItem("BigMoon")
	item.anchor = "sky"
	item.centre = CFrame.new()
	addPart(item, { name = "Moon", shape = BALL, size = Vector3.new(160, 160, 160), color = rgb(236, 236, 250),
		material = Enum.Material.Neon, offset = CFrame.new(-600, 650, -1100) })
	return item
end

PIECES.sweepLights = function(art)
	local item = newItem("SweepLights")
	item.anchor = "world"
	item.root = CFrame.new()
	item.spin = 0.6
	for i = 1, 2 do
		local a = (i + 0.5) * math.pi
		local lamp = addPart(item, { name = "SweepLamp", shape = BALL, size = Vector3.new(4, 4, 4), color = rgb(255, 240, 200),
			material = Enum.Material.Neon, offset = CFrame.new(math.sin(a) * 215, 6, math.cos(a) * 215) })
		addBeam(item, lamp, Vector3.new(0, 0, 0), Vector3.new(80, 420, 0), { color = ColorSequence.new(rgb(255, 245, 210)),
			width0 = 4, width1 = 50, transparency = 0.65 })
	end
	return item
end

--──────────────────────────────────────────────────────────── critters (moving life)

local CRITTERS = {}

local function flapper(colour, span, thick)
	return function(item)
		local wing = Vector3.new(span, 0.15, thick)
		addPart(item, { name = "WingL", size = wing, color = colour })
		addPart(item, { name = "WingR", size = wing, color = colour })
		item.animate = function(it, cf, now)
			local flap = math.sin(now * 11 + (it.phase or 0)) * 0.45
			it.entries[1].part.CFrame = cf * CFrame.Angles(0, 0, 0.25 + flap) * CFrame.new(-span / 2, 0, 0)
			it.entries[2].part.CFrame = cf * CFrame.Angles(0, 0, -0.25 - flap) * CFrame.new(span / 2, 0, 0)
		end
	end
end

CRITTERS.crow = flapper(rgb(30, 30, 36), 2.6, 0.9)
CRITTERS.pigeon = flapper(rgb(150, 155, 170), 2.0, 0.8)
CRITTERS.swallow = flapper(rgb(40, 44, 66), 2.2, 0.8)
CRITTERS.drone = function(item)
	addPart(item, { name = "DroneBody", size = Vector3.new(1.6, 0.6, 1.6), color = rgb(200, 205, 215), material = Enum.Material.Metal })
	addPart(item, { name = "DroneLamp", shape = BALL, size = Vector3.new(0.5, 0.5, 0.5), color = rgb(90, 220, 200), material = Enum.Material.Neon,
		offset = CFrame.new(0, -0.4, 0) })
end
CRITTERS.deliveryDrone = function(item)
	addPart(item, { name = "DroneBody", size = Vector3.new(2, 0.7, 2), color = rgb(60, 64, 80), material = Enum.Material.Metal })
	addPart(item, { name = "DroneBlink", shape = BALL, size = Vector3.new(0.6, 0.6, 0.6), color = rgb(0, 230, 255), material = Enum.Material.Neon,
		offset = CFrame.new(0, -0.5, 0) })
	item.animate = function(it, cf, now)
		it.entries[1].part.CFrame = cf
		it.entries[2].part.CFrame = cf * CFrame.new(0, -0.5, 0)
		local on = math.floor(now * 2 + (it.phase or 0)) % 2 == 0
		it.entries[2].part.Transparency = if on then 0 else 0.85
		it.entries[2].lastT = it.entries[2].part.Transparency
	end
end
CRITTERS.satellite = function(item)
	addPart(item, { name = "Satellite", shape = BALL, size = Vector3.new(4, 4, 4), color = rgb(240, 240, 250), material = Enum.Material.Neon })
end
CRITTERS.farRocket = function(item)
	local p = addPart(item, { name = "FarRocket", shape = BALL, size = Vector3.new(5, 5, 5), color = rgb(255, 230, 160), material = Enum.Material.Neon })
	addTrail(item, p, 2.5, { lifetime = 2.5, color = rgb(255, 210, 140), transparency = 0.2, lightEmission = 1 })
end

--──────────────────────────────────────────────────────────── construction

function YardArt.new(folder, rand, Config, EnvBands, PlotGeom)
	local self = setmetatable({}, YardArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.EnvBands = EnvBands
	self.PlotGeom = PlotGeom
	self.pieces = {}
	self.critters = {}
	self.hazardModels = {}
	self.effects = {}
	self.pool = {}
	self.lines = {} -- [plot k] = { items = { ... }, acc = number }
	self.itemPool = {}
	self.anims = {}
	return self
end

function YardArt.hasPiece(id)
	return PIECES[id] ~= nil
end
function YardArt.hasCritter(kind)
	return CRITTERS[kind] ~= nil
end
function YardArt.pieceIds()
	local out = {}
	for id in PIECES do table.insert(out, id) end
	table.sort(out)
	return out
end

function YardArt:updatePiece(id, w, cam, now)
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
		if item.spin then
			place(item, item.root * CFrame.Angles(0, (now or 0) * item.spin, 0))
		elseif not item.placed then
			place(item, item.root)
			item.placed = true
		end
		if item.spinParts then
			for _, e in item.gears do
				e.part.CFrame = item.root * e.offset * CFrame.Angles((now or 0) * 0.4, 0, 0)
			end
		end
	else
		local root = CFrame.new(cam)
		if item.centre then root = root * item.centre end
		place(item, root)
	end
end

--──────────────────────────────────────────── critters: pooled, spawned on a ring, recycled

local function buildCritter(kind)
	local item = newItem(kind)
	CRITTERS[kind](item)
	for _, e in item.entries do e.part.Name = "Critter_" .. kind .. "_" .. e.part.Name end
	return item
end

function YardArt:updateCritters(desired, cam, dt, now)
	local E = self.EnvBands
	local specs = self.cfg.Env.Critters
	local camV = { x = cam.X, y = cam.Y, z = cam.Z }
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
						if c.item.animate then c.item.animate(c.item, cf, now) else place(c.item, cf) end
					end
				end
			end
		end
		if active < want and spec then
			local group = math.min(spec.flock or 1, want - active)
			local base = E.ambientSpawn(camV, spec, self.rand)
			for g = 1, group do
				local c = nil
				for _, existing in list do
					if not existing.active then c = existing break end
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

--──────────────────────────────────────────── hazards: what the crane drops, and its telegraph

local HAZARD_BUILD = {
	scrapBale = function(item)
		addPart(item, { name = "Bale", size = Vector3.new(4.4, 3.4, 4.4), color = rgb(120, 110, 100), material = Enum.Material.CorrodedMetal })
		addPart(item, { name = "BaleStrap", size = Vector3.new(4.6, 0.4, 4.6), color = rgb(200, 180, 60), material = Enum.Material.Metal })
	end,
	pipe = function(item)
		addPart(item, { name = "Pipe", shape = CYL, size = Vector3.new(5, 1.6, 1.6), color = rgb(150, 160, 170), material = Enum.Material.Metal })
	end,
	bigGear = function(item)
		addPart(item, { name = "Gear", shape = CYL, size = Vector3.new(1.2, 6.4, 6.4), color = rgb(205, 165, 60), material = Enum.Material.Metal })
		addPart(item, { name = "GearHub", shape = CYL, size = Vector3.new(1.6, 2, 2), color = rgb(90, 90, 100), material = Enum.Material.Metal })
	end,
	boltBucket = function(item)
		addPart(item, { name = "Bucket", shape = CYL, size = Vector3.new(3, 4, 4), color = rgb(90, 110, 140), material = Enum.Material.Metal,
			offset = UPRIGHT })
		addPart(item, { name = "Bolts", shape = BALL, size = Vector3.new(3.6, 1.6, 3.6), color = rgb(190, 190, 200), material = Enum.Material.Metal,
			offset = CFrame.new(0, 1.4, 0) })
	end,
	parcel = function(item)
		addPart(item, { name = "Parcel", size = Vector3.new(3, 2.4, 3), color = rgb(190, 150, 100), material = Enum.Material.Cardboard })
	end,
	boosterCap = function(item)
		addPart(item, { name = "Cap", shape = BALL, size = Vector3.new(6, 4, 6), color = rgb(245, 245, 250), material = Enum.Material.SmoothPlastic })
		addPart(item, { name = "CapBand", shape = CYL, size = Vector3.new(0.6, 6.2, 6.2), color = rgb(255, 200, 60), material = Enum.Material.Neon,
			offset = UPRIGHT })
	end,
}

function YardArt.hazardKinds()
	local out = {}
	for k in HAZARD_BUILD do out[k] = true end
	return out
end

function YardArt:hazardModel(kind)
	local item = self.hazardModels[kind]
	if item then return item end
	item = newItem("Hazard_" .. kind)
	HAZARD_BUILD[kind](item)
	local main = item.entries[1].part
	local bb = Instance.new("BillboardGui")
	bb.Name = "HazardWarning"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(46, 46)
	bb.StudsOffset = Vector3.new(0, 5, 0)
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
	light.Color = rgb(255, 200, 80)
	light.Range = 24
	light.Brightness = 2
	light.Enabled = false
	light.Parent = main
	table.insert(item.lights, light)
	for _, e in item.entries do e.part.Name = "Hazard_" .. kind .. "_" .. e.part.Name end
	self.hazardModels[kind] = item
	return item
end

-- The telegraph: the crane's trolley over the player, a light pillar down to the ring, the ring at their feet.
function YardArt:telegraphItem()
	if self.tele then return self.tele end
	local item = newItem("HazardTelegraph")
	addPart(item, { name = "HazardPillar", shape = CYL, size = Vector3.new(10, 0.6, 0.6), color = c3(self.cfg.Hazards.TrackColor),
		material = Enum.Material.Neon, transparency = 0.55 })
	addPart(item, { name = "HazardZone", shape = CYL, size = Vector3.new(0.2, 8, 8), color = c3(self.cfg.Hazards.RingColor),
		material = Enum.Material.Neon, transparency = 0.5 })
	addPart(item, { name = "CraneTrolley", size = Vector3.new(4, 2, 4), color = c3(self.cfg.Palette.Crane), material = Enum.Material.Metal })
	self.tele = item
	return item
end

-- Draw the hazard for this frame. `zone` is Hazards.zone(plan, PlayerRadius) while Hazards.threatLive holds (nil
-- once it can no longer hit): the ring is drawn EXACTLY there, radius = the zone's radius, because it IS the hit
-- rule. Red from the first frame; at the lock it turns solid and the pillar turns red too. `floorY` (PlotGeom
-- .zoneFloor): the zone is a column from the ground up to that height, so on the arrival pad or the belt it shows
-- on top (meteor-drop-tycoon REVIEW-1). `craneY`: the trolley rides the crane bridge above the zone.
function YardArt:showHazard(plan, pos, now, zone, groundY, floorY, craneY)
	local item = self:hazardModel(plan.kind)
	setWeight(item, 1, self.folder)
	item.billboard.Enabled = not plan.locked or (math.floor(now * 6) % 2 == 0)
	item.lights[1].Enabled = math.floor(now * 4) % 2 == 0
	local p = Vector3.new(pos.x, pos.y, pos.z)
	local spin = CFrame.Angles(now * 0.8, now * 1.3, 0)
	place(item, CFrame.new(p) * spin)
	local tele = self:telegraphItem()
	if zone == nil then
		setWeight(tele, 0, self.folder)
		return
	end
	setWeight(tele, 1, self.folder)
	local pillarE, zoneE, trolleyE = tele.entries[1], tele.entries[2], tele.entries[3]
	local baseY = groundY or (zone.y - 3)
	local bottom = baseY + 0.02
	local top = math.max(floorY or baseY, baseY) + 0.22
	local ringY = top - 0.1
	local topY = pos.y
	local len = math.max(0.5, topY - ringY)
	pillarE.part.Color = c3(if plan.locked then self.cfg.Hazards.RingColor else self.cfg.Hazards.TrackColor)
	pillarE.part.Size = Vector3.new(len, 0.6, 0.6)
	pillarE.part.CFrame = CFrame.new(zone.x, ringY + len / 2, zone.z) * UPRIGHT
	local d = 2 * zone.radius
	zoneE.part.Size = Vector3.new(top - bottom, d, d)
	zoneE.part.CFrame = CFrame.new(zone.x, (top + bottom) / 2, zone.z) * UPRIGHT
	local wantT = if plan.locked then 0.15 else 0.5
	if math.abs(zoneE.part.Transparency - wantT) > 0.01 then
		zoneE.part.Transparency = wantT
		zoneE.lastT = wantT
	end
	pillarE.part.Transparency = if plan.locked then 0.25 else 0.55
	trolleyE.part.CFrame = CFrame.new(zone.x, craneY or (topY + 3), zone.z)
end

function YardArt:hideHazard(kind)
	local item = self.hazardModels[kind]
	if item then
		item.billboard.Enabled = false
		setWeight(item, 0, self.folder)
	end
	if self.tele then setWeight(self.tele, 0, self.folder) end
end

--──────────────────────────────────────────── weather

function YardArt:updateWeather(rates, cam)
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
	local budget = self.cfg.Budget
	local capped = self.EnvBands.capRates(rates, math.min(budget.MaxWeatherEmitters, budget.MaxEmitters),
		budget.MaxEmitterRate, 0.05)
	local anyOn = false
	for kind, def in self.cfg.Env.Weather do
		local rate = capped[kind] or 0
		local pe = self.emitters[kind]
		if pe == nil and rate > 0.05 then
			pe = Instance.new("ParticleEmitter")
			pe.Name = "Weather_" .. kind
			pe.Color = ColorSequence.new(c3(def.color))
			pe.Size = NumberSequence.new(def.size)
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.15, def.transparency),
				NumberSequenceKeypoint.new(0.85, def.transparency),
				NumberSequenceKeypoint.new(1, 1),
			})
			pe.Lifetime = NumberRange.new(def.lifetime[1], def.lifetime[2])
			pe.Speed = NumberRange.new(def.speed[1], def.speed[2])
			pe.LightEmission = def.lightEmission
			pe.Acceleration = Vector3.new(def.accel[1], def.accel[2], def.accel[3])
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.EmissionDirection = Enum.NormalId.Top
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

--──────────────────────────────────────────── belt items
-- Each client draws items on the lines near it from LineState and the public flow rule (Line.reach), so the line
-- you see is the line the server computes. Items appear at the chute at min(intake, VisualItemsMaxRate)/s, ride
-- at Belt.speed, and at each station take on its product with the share that station moves (an overloaded
-- station visibly lets some through unchanged). Own line: at most BeltItemsOwn; every other line: BeltItemsOther.

local ITEM_SIZE = { Vector3.new(1.1, 0.9, 1.1), Vector3.new(0.8, 0.5, 0.8), Vector3.new(1.4, 0.5, 0.7), Vector3.new(1.4, 0.2, 1.4),
	Vector3.new(0.3, 1.2, 1.2), Vector3.new(0.9, 1.3, 0.9), Vector3.new(0.6, 1.8, 0.6) }

local function itemPart(self)
	local p = table.remove(self.itemPool)
	if p == nil then
		p = Instance.new("Part")
		p.Name = "BeltItem"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	return p
end

local function dress(self, p, state)
	local cfg = self.cfg
	p.Size = ITEM_SIZE[state + 1]
	p.Color = c3(cfg.Products.Colors[state + 1])
	p.Material = if state == 2 or state == 6 then Enum.Material.Neon elseif state == 0 then Enum.Material.CorrodedMetal else Enum.Material.Metal
	p.Name = "BeltItem_" .. cfg.Products.Names[state + 1]
end

-- lines = { [k] = { S = station states (Line format), own = bool, near = bool } }; Line is the module.
function YardArt:updateBelts(Line, lines, dt)
	local cfg, PG = self.cfg, self.PlotGeom
	local B = cfg.Plot.Belt
	local length = PG.beltLength(cfg)
	local topY = B.topY
	for k, info in lines do
		local L = self.lines[k]
		if L == nil then
			L = { items = {}, acc = 0 }
			self.lines[k] = L
		end
		local cap = if not info.near then 0 elseif info.own then cfg.Budget.BeltItemsOwn else cfg.Budget.BeltItemsOther
		local reach, capT = Line.reach(cfg, info.S)
		local intake = reach[1]
		-- the share each station moves of what reaches it
		local share = {}
		for t = 1, 6 do
			share[t] = if reach[t] > 0 then math.min(1, capT[t] / reach[t]) else 0
		end
		-- spawn: own line at min(intake, 2.5)/s; another line no faster than its cap fills over one ride
		local rate = math.min(intake, cfg.Line.VisualItemsMaxRate)
		if not info.own then rate = math.min(rate, cap / (length / B.speed)) end
		L.acc += rate * dt
		while L.acc >= 1 do
			L.acc -= 1
			if #L.items < cap then
				local p = itemPart(self)
				dress(self, p, 0)
				table.insert(L.items, { part = p, s = 0, state = 0, next = 1 })
			end
		end
		for i = #L.items, 1, -1 do
			local it = L.items[i]
			it.s += B.speed * dt
			-- stations pass by: take on the product with the station's share
			while it.next <= 6 and it.s >= PG.stationS(cfg, it.next) do
				local t = it.next
				if it.state == t - 1 and info.S[t].n > 0 and self.rand() < share[t] then
					it.state = t
					dress(self, it.part, t)
				end
				it.next += 1
			end
			if it.s >= length or i > cap then
				it.part.Parent = nil
				table.insert(self.itemPool, it.part)
				table.remove(L.items, i)
			else
				local lx, lz = PG.beltPoint(cfg, it.s)
				local wx, wz = PG.toWorld(cfg, k, lx, lz)
				it.part.CFrame = CFrame.new(wx, topY + it.part.Size.Y / 2, wz)
				if it.part.Parent ~= self.folder then it.part.Parent = self.folder end
			end
		end
	end
end

function YardArt:beltItemCount(k)
	local L = self.lines[k]
	return if L then #L.items else 0
end

--──────────────────────────────────────────── machine animation (own plot only)
-- One client part per built station, moving on top of the server's machine: rollers turn, the Press stamps,
-- the Cutter's laser flickers, the Assembler's arm swings, the Rocket Bay's dome pulses. Never a server part.
function YardArt:updateMachines(k, built, now)
	local cfg, PG = self.cfg, self.PlotGeom
	for t = 1, 6 do
		local a = self.anims[t]
		local want = k ~= nil and built[t] == true
		if want and a == nil then
			a = newItem("Anim_" .. cfg.Stations.Order[t])
			local col = c3(cfg.Stations.Accents[t])
			if t == 1 then
				addPart(a, { name = "Anim_Roller", shape = CYL, size = Vector3.new(cfg.Plot.MachineAcross + 0.6, 1.6, 1.6), color = rgb(200, 200, 210), material = Enum.Material.Metal })
			elseif t == 2 then
				addPart(a, { name = "Anim_Glow", size = Vector3.new(3.8, 2.6, 0.3), color = col, material = Enum.Material.Neon })
			elseif t == 3 then
				addPart(a, { name = "Anim_Stamp", size = Vector3.new(5, 1, 3), color = rgb(170, 180, 200), material = Enum.Material.Metal })
			elseif t == 4 then
				local host = addPart(a, { name = "Anim_Laser", size = Vector3.new(0.6, 0.6, 0.6), color = col, material = Enum.Material.Neon })
				addBeam(a, host, Vector3.new(0, 0, 0), Vector3.new(0, -4, 0), { color = ColorSequence.new(rgb(90, 200, 255)), width0 = 0.3, width1 = 0.3, transparency = 0.1 })
			elseif t == 5 then
				addPart(a, { name = "Anim_Arm", size = Vector3.new(0.8, 0.8, 5), color = col, material = Enum.Material.Metal })
			else
				addPart(a, { name = "Anim_Dome", shape = BALL, size = Vector3.new(2, 2, 2), color = col, material = Enum.Material.Neon })
			end
			self.anims[t] = a
		end
		if a then
			setWeight(a, if want then 1 else 0, self.folder)
			if want then
				local mx, mz = PG.machinePos(cfg, t, 1)
				local wx, wz = PG.toWorld(cfg, k, mx, mz)
				local h = cfg.Stations.MachineHeight[t] + cfg.World.FloorTopY
				local cx, cz = PG.centre(cfg, k)
				local base = CFrame.lookAt(Vector3.new(wx, h, wz), Vector3.new(cx, h, cz))
				local cf
				if t == 1 then
					cf = base * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(now * 4, 0, 0)
				elseif t == 2 then
					cf = base * CFrame.new(0, -h + 2.6, 0)
					a.entries[1].part.Transparency = 0.2 + 0.2 * math.sin(now * 9)
				elseif t == 3 then
					cf = base * CFrame.new(0, 0.6 + math.abs(math.sin(now * 3)) * 1.6, 0)
				elseif t == 4 then
					cf = base * CFrame.new(0, 2, 0)
					local on = math.floor(now * 8) % 3 ~= 0
					if a.beams[1] then a.beams[1].beam.Enabled = on end
				elseif t == 5 then
					cf = base * CFrame.new(0, 1, 0) * CFrame.Angles(0, math.sin(now * 2) * 0.9, 0)
				else
					cf = base * CFrame.new(0, 3.6, 0)
					a.entries[1].part.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(now * 3))
				end
				place(a, cf)
			end
		end
	end
end

--──────────────────────────────────────────── the lift-off and one-shot effects (pooled, timed)

function YardArt:liftoff(at, seconds)
	local item = self.liftItem
	if item == nil then
		item = newItem("Liftoff")
		addPart(item, { name = "Lift_Body", shape = CYL, size = Vector3.new(6, 2, 2), color = rgb(245, 245, 250), offset = UPRIGHT })
		addPart(item, { name = "Lift_Nose", shape = BALL, size = Vector3.new(2, 2.6, 2), color = rgb(255, 200, 60), offset = CFrame.new(0, 3.4, 0) })
		addPart(item, { name = "Lift_FinL", size = Vector3.new(0.2, 1.6, 1.4), color = rgb(255, 200, 60), offset = CFrame.new(-1.1, -2.4, 0) })
		addPart(item, { name = "Lift_FinR", size = Vector3.new(0.2, 1.6, 1.4), color = rgb(255, 200, 60), offset = CFrame.new(1.1, -2.4, 0) })
		local flame = addPart(item, { name = "Lift_Flame", shape = BALL, size = Vector3.new(1.6, 3, 1.6), color = rgb(255, 190, 80),
			material = Enum.Material.Neon, offset = CFrame.new(0, -4.4, 0) })
		addTrail(item, flame, 0.9, { lifetime = 1.6, color = rgb(255, 220, 160), transparency = 0.1, lightEmission = 1 })
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "LiftSmoke"
		smoke.Rate = 30
		smoke.Lifetime = NumberRange.new(1.5, 2.5)
		smoke.Speed = NumberRange.new(2, 6)
		smoke.SpreadAngle = Vector2.new(40, 40)
		smoke.EmissionDirection = Enum.NormalId.Bottom
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
		smoke.Color = ColorSequence.new(rgb(225, 225, 230))
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		smoke.Enabled = false
		smoke.Parent = flame
		table.insert(item.emitters, smoke)
		self.liftItem = item
	end
	-- one at a time: a second lift-off while one flies restarts it at its own pad
	for i = #self.effects, 1, -1 do
		if self.effects[i].item == item then table.remove(self.effects, i) end
	end
	setWeight(item, 1, self.folder)
	place(item, CFrame.new(at + Vector3.new(0, 4.4, 0)))
	table.insert(self.effects, { item = item, t = 0, duration = seconds, keep = true, update = function(it, a)
		-- a beat on the pad, then up, faster and faster
		local rise = if a < 0.2 then 0 else ((a - 0.2) / 0.8) ^ 2 * 320
		place(it, CFrame.new(at + Vector3.new(0, 4.4 + rise, 0)) * CFrame.Angles(0, a * 3, 0))
	end })
end

function YardArt:liftoffActive(): boolean
	for _, fx in self.effects do
		if fx.item == self.liftItem then return true end
	end
	return false
end

function YardArt:puff(at, colour, seconds, growTo)
	local item = table.remove(self.pool)
	if item == nil then
		item = newItem("Fx_puff")
		addPart(item, { name = "Fx_puff", shape = BALL, size = Vector3.new(3, 3, 3), material = Enum.Material.Neon })
	end
	item.entries[1].part.Color = colour
	setWeight(item, 1, self.folder)
	place(item, CFrame.new(at))
	table.insert(self.effects, { item = item, t = 0, duration = seconds, update = function(it, a)
		local s = 1 + (growTo - 1) * a
		it.entries[1].part.Size = Vector3.new(3 * s, 3 * s, 3 * s)
		it.entries[1].part.Transparency = a
		it.entries[1].lastT = a
		place(it, CFrame.new(at))
	end })
end

function YardArt:stepEffects(dt)
	for i = #self.effects, 1, -1 do
		local fx = self.effects[i]
		fx.t += dt
		local a = math.clamp(fx.t / fx.duration, 0, 1)
		fx.update(fx.item, a)
		if fx.t >= fx.duration then
			table.remove(self.effects, i)
			setWeight(fx.item, 0, self.folder)
			if not fx.keep then
				fx.item.entries[1].part.Size = Vector3.new(3, 3, 3)
				table.insert(self.pool, fx.item)
			end
		end
	end
end

return YardArt
