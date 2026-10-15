-- SkyArt.luau — Outpost Zero's sky: scenery per band, critters, weather, hazard models and their telegraph, and the
-- Grand Airship's flight, built in code (no assets). CLIENT ONLY: required by src/client/Sky.client.luau; the
-- server never touches it.
--
-- Pattern copied from meteor-drop-tycoon/src/shared/SkyArt.luau (items that fade together, pooled critters on a
-- ring around the camera, capped weather, a hazard model with its telegraph), with this game's own art.
-- Everything here is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off (nothing can be stood on, touched
-- or ray-hit), CastShadow off. Nothing is built until a band first needs it, and anything whose weight falls to zero
-- is UNPARENTED, so a band you are not in costs no draw calls. Red is used by exactly one thing: the hazard ring
-- (Config.Hazards.RingColor), which is the hazard's hit zone.
--
-- Dependencies arrive as arguments (a bare require("./X") is invalid in Roblox):
--   SkyArt.new(folder, rand, Config, EnvBands)
-- Budgets are measured, not assumed: robloxemu/check_outpostzero_sky.luau counts what this module has parented at
-- every band and every seam, every frame, against Config.Budget.

local SkyArt = {}
SkyArt.__index = SkyArt

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

--──────────────────────────────────────────────────────────── items: parts that fade together

local function newItem(name)
	return { name = name, entries = {}, beams = {}, trails = {}, lights = {}, shown = false, weight = 0 }
end

-- Roblox forces a Ball's Size uniform (robloxemu does not), so a stretched sphere (a fog bank, a cloud, a balloon,
-- the airship's envelope, a whale) is a Block whose Sphere SpecialMesh fills the box (round 2, B1; the same fix as
-- anomaly-observatory's "Ellipsoid"). A uniform Ball stays a Ball.
local function shapePart(p, shape, size)
	local uniform = math.abs(size.X - size.Y) < 1e-6 and math.abs(size.Y - size.Z) < 1e-6
	if shape == Enum.PartType.Ball and not uniform then
		local mesh = Instance.new("SpecialMesh")
		mesh.Name = "EllipsoidMesh"
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape then
		p.Shape = shape
	end
	p.Size = size
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
	shapePart(p, props.shape, props.size or Vector3.new(1, 1, 1))
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

local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis is X; this stands it up

--──────────────────────────────────────────────────────────── pieces (static scenery)
-- anchor = "world" (placed once, around the whole ring), "sky" (travels with the camera, like a skybox with depth),
-- "sea" (follows the camera across, at a fixed height: the cloud sea) or "shelf" (placed on the player's own shelf).

local PIECES = {}

-- Fogbound Dawn: banks of fog rolling around the camera, low over the parapet
PIECES.fogBanks = function(art)
	local item = newItem("FogBanks")
	item.anchor = "sky"
	item.centre = CFrame.new(0, -12, 0)
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2 + 0.3
		local r = 110 + (i % 3) * 30
		addPart(item, { name = "FogBank", shape = BALL, size = Vector3.new(120, 26, 70), color = rgb(236, 228, 236),
			material = Enum.Material.SmoothPlastic, transparency = 0.55, offset = CFrame.new(math.sin(a) * r, (i % 2) * 6, math.cos(a) * r) * CFrame.Angles(0, a, 0) })
	end
	return item
end

-- Fogbound Dawn: the empty shelves of the frontier, bare rock spires in silhouette far out
PIECES.rockSpires = function(art)
	local item = newItem("RockSpires")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 5 do
		local a = (i - 0.5) / 5 * math.pi * 2 + 0.4
		local r = 700 + (i % 2) * 180
		local hgt = 140 + (i % 3) * 50
		addPart(item, { class = "WedgePart", name = "Spire", size = Vector3.new(90, hgt, 70), color = rgb(96, 92, 100),
			material = Enum.Material.Rock, offset = CFrame.new(math.sin(a) * r, hgt / 2 - 60, math.cos(a) * r) * CFrame.Angles(0, a, 0) })
	end
	return item
end

-- the cloud sea 80 studs below the shelves, with a few puffs on it
PIECES.cloudSea = function(art)
	local item = newItem("CloudSea")
	item.anchor = "sea"
	item.y = art.cfg.World.CloudSeaY
	addPart(item, { name = "CloudSea", size = Vector3.new(2048, 4, 2048), color = rgb(244, 244, 250), material = Enum.Material.SmoothPlastic,
		transparency = 0.08, offset = CFrame.new() })
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		local r = 260 + (i % 3) * 140
		addPart(item, { name = "CloudPuff", shape = BALL, size = Vector3.new(160, 40, 120), color = rgb(250, 250, 255),
			transparency = 0.15, offset = CFrame.new(math.sin(a) * r, 8, math.cos(a) * r) })
	end
	return item
end

-- far shelves of other settlers, with tents
PIECES.farShelves = function(art)
	local item = newItem("FarShelves")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 5 do
		local a = (i - 1) / 5 * math.pi * 2 + 1.1
		local r = 650 + (i % 3) * 200
		local x, z = math.sin(a) * r, math.cos(a) * r
		addPart(item, { name = "FarRock", shape = CYL, size = Vector3.new(10, 90, 90), color = rgb(132, 124, 116),
			material = Enum.Material.Rock, offset = CFrame.new(x, -6 + (i % 2) * 20, z) * UPRIGHT })
		addPart(item, { class = "WedgePart", name = "FarTent", size = Vector3.new(20, 12, 16), color = rgb(236, 226, 200),
			material = Enum.Material.Fabric, offset = CFrame.new(x, 5 + (i % 2) * 20, z) * CFrame.Angles(0, a, 0) })
	end
	return item
end

-- Lantern Dusk: the far shelves' windows light up
PIECES.farWindows = function(art)
	local item = newItem("FarWindows")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 5 do
		local a = (i - 1) / 5 * math.pi * 2 + 1.1
		local r = 650 + (i % 3) * 200
		addPart(item, { name = "FarWindow", size = Vector3.new(26, 6, 26), color = rgb(255, 214, 140), material = Enum.Material.Neon,
			transparency = 0.1, offset = CFrame.new(math.sin(a) * r, 1 + (i % 2) * 20, math.cos(a) * r) })
	end
	return item
end

-- Trade Winds: pennant strings over the player's own plaza
PIECES.pennants = function(art)
	local item = newItem("Pennants")
	item.anchor = "shelf"
	local host = addPart(item, { name = "PennantHost", size = Vector3.new(1, 1, 1), transparency = 1, offset = CFrame.new(0, 14, 0) })
	local colours = { rgb(255, 214, 90), rgb(90, 190, 230), rgb(140, 210, 140), rgb(250, 240, 220) }
	for i = 1, 4 do
		local a = (i - 1) / 4 * math.pi * 2 + math.pi / 4
		addBeam(item, host, Vector3.new(0, 0, 0), Vector3.new(math.sin(a) * 24, -8, math.cos(a) * 24), {
			color = ColorSequence.new(colours[i]), width0 = 1.2, width1 = 1.2, curve0 = -4, curve1 = 4, transparency = 0.1, segments = 10 })
	end
	return item
end

-- Trade Winds: a sky-rail line linking the far shelves
PIECES.skyRail = function(art)
	local item = newItem("SkyRail")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 3 do
		local a = (i - 1) / 3 * math.pi * 2 + 0.2
		local r = 760
		addPart(item, { name = "Rail", size = Vector3.new(2, 2, 700), color = rgb(150, 156, 170), material = Enum.Material.Metal,
			offset = CFrame.new(math.sin(a) * r, 40, math.cos(a) * r) * CFrame.Angles(0, a + math.pi / 2, 0) })
	end
	return item
end

-- Storm Front: a storm wall on the horizon
PIECES.stormWall = function(art)
	local item = newItem("StormWall")
	item.anchor = "sky"
	item.centre = CFrame.new()
	for i = 1, 3 do
		local a = (i - 2) * 0.5
		addPart(item, { name = "StormCloud", shape = BALL, size = Vector3.new(900, 360, 300), color = rgb(70, 66, 96),
			transparency = 0.25, offset = CFrame.new(math.sin(a) * 1300, 60, -math.cos(a) * 1300) })
	end
	return item
end

-- Storm Front: silent lightning inside the cloud sea (Sky.client flashes it, at most once per 3 s)
PIECES.cloudLightning = function(art)
	local item = newItem("CloudLightning")
	item.anchor = "sea"
	item.y = art.cfg.World.CloudSeaY - 6
	local p = addPart(item, { name = "CloudFlash", shape = BALL, size = Vector3.new(160, 30, 160), color = rgb(220, 226, 255),
		material = Enum.Material.Neon, transparency = 1, offset = CFrame.new(380, 0, -220) })
	item.flash = p
	return item
end

-- Aurora Crown: aurora curtains
PIECES.aurora = function(art)
	local item = newItem("Aurora")
	item.anchor = "sky"
	item.centre = CFrame.new()
	local host = addPart(item, { name = "AuroraHost", size = Vector3.new(1, 1, 1), transparency = 1, offset = CFrame.new(0, 420, -600) })
	local colours = { rgb(80, 255, 190), rgb(90, 200, 255), rgb(160, 120, 255), rgb(120, 255, 220) }
	for i = 1, 4 do
		local y = 30 * (i - 2.5)
		addBeam(item, host, Vector3.new(-900, y, (i - 2.5) * 120), Vector3.new(900, y + 40, (i - 2.5) * 160), {
			color = ColorSequence.new(colours[i]), width0 = 140, width1 = 220, curve0 = 300, curve1 = -260, transparency = 0.45,
			faceCamera = false, segments = 24 })
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

CRITTERS.gull = flapper(rgb(240, 240, 244), 3.2, 1.1)
CRITTERS.swift = flapper(rgb(40, 44, 66), 2.0, 0.7)
CRITTERS.petrel = flapper(rgb(36, 34, 52), 2.6, 0.9)
CRITTERS.balloon = function(item)
	local palette = { rgb(255, 196, 90), rgb(120, 190, 230), rgb(150, 210, 140) }
	addPart(item, { name = "Envelope", shape = BALL, size = Vector3.new(14, 17, 14), color = palette[math.random(1, #palette)], material = Enum.Material.Fabric })
	addPart(item, { name = "Basket", size = Vector3.new(3, 2.4, 3), color = rgb(150, 112, 76), material = Enum.Material.Wood, offset = CFrame.new(0, -11, 0) })
end
CRITTERS.lantern = function(item)
	addPart(item, { name = "SkyLantern", size = Vector3.new(1.2, 1.6, 1.2), color = rgb(255, 196, 110), material = Enum.Material.Neon, transparency = 0.1 })
end
CRITTERS.whale = function(item)
	addPart(item, { name = "WhaleBody", shape = BALL, size = Vector3.new(14, 11, 34), color = rgb(96, 120, 160), material = Enum.Material.SmoothPlastic })
	addPart(item, { class = "WedgePart", name = "WhaleTail", size = Vector3.new(16, 2, 8), color = rgb(86, 110, 150), offset = CFrame.new(0, 1, 19) })
	addPart(item, { name = "WhaleFinL", size = Vector3.new(8, 0.8, 4), color = rgb(86, 110, 150), offset = CFrame.new(-8, -2, -2) })
	addPart(item, { name = "WhaleFinR", size = Vector3.new(8, 0.8, 4), color = rgb(86, 110, 150), offset = CFrame.new(8, -2, -2) })
	item.animate = function(it, cf, now)
		local bob = CFrame.new(0, math.sin(now * 0.4 + (it.phase or 0)) * 2, 0)
		for _, e in it.entries do
			e.part.CFrame = cf * bob * e.offset
		end
	end
end

--──────────────────────────────────────────────────────────── construction

function SkyArt.new(folder, rand, Config, EnvBands)
	local self = setmetatable({}, SkyArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.EnvBands = EnvBands
	self.pieces = {}
	self.critters = {}
	self.hazardModels = {}
	self.effects = {}
	self.shelfCf = CFrame.new()
	self.flight = nil
	return self
end

function SkyArt.hasPiece(id)
	return PIECES[id] ~= nil
end
function SkyArt.hasCritter(kind)
	return CRITTERS[kind] ~= nil
end
function SkyArt.pieceIds()
	local out = {}
	for id in PIECES do table.insert(out, id) end
	table.sort(out)
	return out
end

-- The player's own shelf (shelf-anchored pieces sit on it).
function SkyArt:setShelf(cf)
	self.shelfCf = cf
	for _, item in self.pieces do
		if item.anchor == "shelf" then item.placed = false end
	end
end

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
	elseif item.anchor == "shelf" then
		if not item.placed then
			place(item, self.shelfCf)
			item.placed = true
		end
	elseif item.anchor == "sea" then
		place(item, CFrame.new(cam.X, item.y, cam.Z))
	else
		local root = CFrame.new(cam)
		if item.centre then root = root * item.centre end
		place(item, root)
	end
end

-- Storm Front's silent lightning: one distant flash (never full-screen), lit for `seconds`. Sky.client decides
-- WHEN (at most once per Config.Env.LightningMinGap s); this only draws it.
function SkyArt:flashLightning(on)
	local item = self.pieces.cloudLightning
	if item == nil or not item.shown or item.flash == nil then return false end
	local want = if on then 0.15 else 1
	if item.flash.Transparency ~= want then
		item.flash.Transparency = want
		item.entries[1].lastT = want
	end
	return true
end

--──────────────────────────────────────────── critters: pooled, spawned on a ring, recycled

local function buildCritter(kind)
	local item = newItem(kind)
	CRITTERS[kind](item)
	-- "Critter_<kind>_<part>": a headless check can tell a gull's wing from a petrel's
	for _, e in item.entries do e.part.Name = "Critter_" .. kind .. "_" .. e.part.Name end
	return item
end

function SkyArt:updateCritters(desired, cam, dt, now)
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

--──────────────────────────────────────────── hazards: what falls, and its telegraph

local HAZARD_BUILD = {
	crate = function(item)
		addPart(item, { name = "Crate", size = Vector3.new(3.6, 3.6, 3.6), color = rgb(176, 136, 90), material = Enum.Material.WoodPlanks })
		addPart(item, { name = "CrateBand", size = Vector3.new(3.7, 0.5, 3.7), color = rgb(80, 74, 70), material = Enum.Material.Metal })
	end,
	sandbag = function(item)
		addPart(item, { name = "Sandbag", shape = BALL, size = Vector3.new(3, 3.6, 3), color = rgb(214, 196, 150), material = Enum.Material.Fabric })
	end,
	lantern = function(item)
		addPart(item, { name = "SpentLantern", size = Vector3.new(2.2, 3, 2.2), color = rgb(150, 120, 90), material = Enum.Material.Fabric })
	end,
	lightning = function(item)
		addPart(item, { name = "Bolt", size = Vector3.new(0.8, 9, 0.8), color = rgb(230, 236, 255), material = Enum.Material.Neon,
			offset = CFrame.Angles(0, 0, math.rad(12)) })
		addPart(item, { name = "BoltFork", size = Vector3.new(0.6, 5, 0.6), color = rgb(200, 210, 255), material = Enum.Material.Neon,
			offset = CFrame.new(1.2, -3, 0) * CFrame.Angles(0, 0, math.rad(-25)) })
	end,
	hail = function(item)
		addPart(item, { name = "Hailstone", shape = BALL, size = Vector3.new(3.4, 3.4, 3.4), color = rgb(220, 236, 250), material = Enum.Material.Ice, transparency = 0.1 })
	end,
	shard = function(item)
		addPart(item, { name = "IceShard", size = Vector3.new(1.4, 5, 1.4), color = rgb(200, 240, 255), material = Enum.Material.Ice,
			offset = CFrame.Angles(0, 0, math.rad(20)) })
	end,
}

function SkyArt.hazardKinds()
	local out = {}
	for k in HAZARD_BUILD do out[k] = true end
	return out
end

function SkyArt:hazardModel(kind)
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

-- The telegraph: a light pillar from the falling object down to the ring, and the ring at the player's feet.
function SkyArt:telegraphItem()
	if self.tele then return self.tele end
	local item = newItem("HazardTelegraph")
	addPart(item, { name = "HazardPillar", shape = CYL, size = Vector3.new(10, 0.6, 0.6), color = c3(self.cfg.Hazards.TrackColor),
		material = Enum.Material.Neon, transparency = 0.55 })
	addPart(item, { name = "HazardZone", shape = CYL, size = Vector3.new(0.2, 8, 8), color = c3(self.cfg.Hazards.RingColor),
		material = Enum.Material.Neon, transparency = 0.5 })
	self.tele = item
	return item
end

-- Draw the hazard for this frame. `zone` is Hazards.zone(plan, PlayerRadius) while Hazards.threatLive holds (nil
-- once it can no longer hit): the ring is drawn EXACTLY there, radius = the zone's radius, because it IS the hit rule.
-- `floorY`: the surface the player stands on (a roof is ground too), so the ring is drawn on top of it, never under.
function SkyArt:showHazard(plan, pos, now, zone, floorY)
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
	local pillarE, zoneE = tele.entries[1], tele.entries[2]
	local ringY = floorY + 0.12
	local len = math.max(0.5, pos.y - ringY)
	pillarE.part.Color = c3(if plan.locked then self.cfg.Hazards.RingColor else self.cfg.Hazards.TrackColor)
	pillarE.part.Size = Vector3.new(len, 0.6, 0.6)
	pillarE.part.CFrame = CFrame.new(zone.x, ringY + len / 2, zone.z) * UPRIGHT
	local d = 2 * zone.radius
	zoneE.part.Size = Vector3.new(0.2, d, d)
	zoneE.part.CFrame = CFrame.new(zone.x, ringY, zone.z) * UPRIGHT
	local wantT = if plan.locked then 0.15 else 0.5
	if math.abs(zoneE.part.Transparency - wantT) > 0.01 then
		zoneE.part.Transparency = wantT
		zoneE.lastT = wantT
	end
	pillarE.part.Transparency = if plan.locked then 0.25 else 0.55
end

function SkyArt:hideHazard(kind)
	local item = self.hazardModels[kind]
	if item then
		item.billboard.Enabled = false
		setWeight(item, 0, self.folder)
	end
	if self.tele then setWeight(self.tele, 0, self.folder) end
end

--──────────────────────────────────────────── weather

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
	local budget = self.cfg.Budget
	local capped = self.EnvBands.capRates(rates, math.min(budget.MaxWeatherEmitters, budget.MaxEmitters), budget.MaxEmitterRate, 0.05)
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

--──────────────────────────────────────────── the Grand Airship's flight (each client flies its own copy)
-- 12 parts like the server's moored one. One flight at a time: a second arrival while one flies is skipped (the
-- server still moors it, and everyone sees the moored airship). Returns true when this flight is drawn.

local function buildAirship(item, cfg)
	local P = cfg.Palette
	local hull, trim = c3(P.AirshipHull), c3(P.AirshipTrim)
	local gy, ey = cfg.Airship.GondolaY, 10 -- the server's kit model, part for part (Main.server.luau)
	addPart(item, { name = "Gondola", size = Vector3.new(12, 3, 4), color = c3(P.AirshipGondola), material = Enum.Material.Wood, offset = CFrame.new(0, gy, 0) })
	addPart(item, { name = "GondolaWindows", size = Vector3.new(10, 0.8, 4.1), color = c3(P.AirshipLamp), material = Enum.Material.Neon, offset = CFrame.new(0, gy + 0.3, 0) })
	addPart(item, { name = "Envelope", shape = BALL, size = Vector3.new(44, 14, 14), color = hull, material = Enum.Material.Fabric, offset = CFrame.new(0, ey, 0) })
	addPart(item, { name = "BandFore", shape = CYL, size = Vector3.new(1.2, 14.4, 14.4), color = trim, material = Enum.Material.Fabric, offset = CFrame.new(10, ey, 0) })
	addPart(item, { name = "BandAft", shape = CYL, size = Vector3.new(1.2, 14.4, 14.4), color = trim, material = Enum.Material.Fabric, offset = CFrame.new(-10, ey, 0) })
	addPart(item, { name = "FinTop", size = Vector3.new(6, 6, 0.4), color = trim, material = Enum.Material.Fabric, offset = CFrame.new(-20, ey + 6, 0) })
	addPart(item, { name = "FinBottom", size = Vector3.new(6, 6, 0.4), color = trim, material = Enum.Material.Fabric, offset = CFrame.new(-20, ey - 6, 0) })
	addPart(item, { name = "FinLeft", size = Vector3.new(6, 0.4, 6), color = trim, material = Enum.Material.Fabric, offset = CFrame.new(-20, ey, -6) })
	addPart(item, { name = "FinRight", size = Vector3.new(6, 0.4, 6), color = trim, material = Enum.Material.Fabric, offset = CFrame.new(-20, ey, 6) })
	addPart(item, { name = "PropellerL", size = Vector3.new(0.4, 4, 0.6), color = trim, material = Enum.Material.Metal, offset = CFrame.new(-7, gy + 1, -3) })
	addPart(item, { name = "PropellerR", size = Vector3.new(0.4, 4, 0.6), color = trim, material = Enum.Material.Metal, offset = CFrame.new(-7, gy + 1, 3) })
	addPart(item, { name = "Lamp", shape = BALL, size = Vector3.new(1.6, 1.6, 1.6), color = c3(P.AirshipLamp), material = Enum.Material.Neon, offset = CFrame.new(6.5, gy, 0) })
end

function SkyArt:startFlight(mast, seconds, nose)
	if self.flight ~= nil then return false end
	if self.airshipItem == nil then
		self.airshipItem = newItem("AirshipFlight")
		buildAirship(self.airshipItem, self.cfg)
		for _, e in self.airshipItem.entries do e.part.Name = "Flight_" .. e.part.Name end
	end
	-- `mast` is where the moored gondola's centre will be and `nose` (x, z) the way the moored airship points. The
	-- copy starts FlightFrom studs back along that line and higher up and flies straight in, nose first, with one
	-- fixed heading: it ends in the moored airship's own pose, so nothing snaps or turns at the hand-over (round 2,
	-- B2). Without a nose it comes in toward the ring's centre.
	local heading
	if type(nose) == "table" and type(nose[1]) == "number" and type(nose[2]) == "number" and (nose[1] ~= 0 or nose[2] ~= 0) then
		heading = Vector3.new(nose[1], 0, nose[2]).Unit
	else
		local out = Vector3.new(mast.X, 0, mast.Z)
		heading = if out.Magnitude > 1 then -out.Unit else Vector3.new(0, 0, -1)
	end
	local from = mast - heading * self.cfg.Airship.FlightFrom + Vector3.new(0, 60, 0)
	self.flight = { from = from, to = mast, t = 0, seconds = seconds, heading = heading, held = 0 }
	setWeight(self.airshipItem, 1, self.folder)
	self:stepFlight(0)
	return true
end

-- "flying", then "docked" (holding the last pose until Sky.client sees the moored model and calls endFlight, at most
-- Config.Airship.HandOverSeconds), then "done". nil with no flight.
function SkyArt:stepFlight(dt)
	local f = self.flight
	if f == nil then return nil end
	f.t += dt
	local a = math.clamp(f.t / f.seconds, 0, 1)
	if a >= 1 then
		f.held += if f.docked then dt else 0
		f.docked = true
		if f.held >= self.cfg.Airship.HandOverSeconds then
			self:endFlight()
			return "done"
		end
	end
	local eased = 1 - (1 - a) ^ 3 -- slows into the mooring
	local p = f.from:Lerp(f.to, eased)
	-- the gondola is the pivot (as the server's model): the item's offsets are from the hull bottom, GondolaY below
	local cf = CFrame.lookAt(p, p + f.heading) * CFrame.Angles(0, math.rad(90), 0) -- the model's +X along the heading
	place(self.airshipItem, cf * CFrame.new(0, -self.cfg.Airship.GondolaY, 0))
	return if f.docked then "docked" else "flying"
end

function SkyArt:flightDocked()
	return self.flight ~= nil and self.flight.docked == true
end

-- the moored model is on screen: the copy goes, the same frame
function SkyArt:endFlight()
	if self.flight == nil then return end
	setWeight(self.airshipItem, 0, self.folder)
	self.flight = nil
end

function SkyArt:flightActive()
	return self.flight ~= nil
end

return SkyArt
