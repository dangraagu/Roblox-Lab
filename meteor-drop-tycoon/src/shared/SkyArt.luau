-- SkyArt.luau — Meteor Drop Tycoon's sky scenery, critters, weather, hazard models and meteor effects,
-- built in code (no assets). CLIENT ONLY: required by src/client/Sky.client.luau; the server never touches it.
--
-- Pattern copied from plus1-jump/src/shared/SkyArt.luau (items that fade together, pooled critters on a
-- ring around the camera, capped weather, a hazard model with its telegraph), with this game's own art.
-- Everything here is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off (nothing can be stood
-- on, touched or ray-hit), CastShadow off. Nothing is built until a band first needs it, and anything
-- whose weight falls to zero is UNPARENTED, so a band you are not in costs no draw calls. Red is used by
-- exactly one thing: the hazard ring (Config.Hazards.RingColor), which is the hazard's hit zone.
--
-- Dependencies arrive as arguments (a bare require("./X") is invalid in Roblox):
--   SkyArt.new(folder, rand, Config, EnvBands)
-- Budgets are measured, not assumed: robloxemu/check_meteordroptycoon_sky.luau counts what this module has
-- parented at every band and every seam, every frame, against Config.Budget.

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
-- anchor = "world" (placed once, around the whole world) or "sky" (travels with the camera, like a skybox
-- with depth: things that are meant to be infinitely far away).

local PIECES = {}

-- Dusk Meadow: rolling hills in a ring at the world's edge, beyond every plot (plot rims end 146 out)
PIECES.hills = function(art)
	local item = newItem("Hills")
	item.anchor = "world"
	item.root = CFrame.new()
	local greens = { rgb(104, 150, 86), rgb(92, 138, 80), rgb(118, 160, 92) }
	for i = 1, 10 do
		local a = (i - 1) / 10 * math.pi * 2 + 0.2
		local r = 360 + (i % 3) * 25
		local s = 120 + (i % 4) * 30
		addPart(item, { name = "Hill", shape = BALL, size = Vector3.new(s * 1.8, s * 0.7, s * 1.4), color = greens[1 + i % 3],
			material = Enum.Material.Grass, offset = CFrame.new(math.sin(a) * r, -s * 0.2, math.cos(a) * r) * CFrame.Angles(0, a, 0) })
	end
	return item
end

PIECES.birches = function(art)
	local item = newItem("Birches")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 6 do
		local a = (i - 0.5) / 6 * math.pi * 2
		local r = 250
		local x, z = math.sin(a) * r, math.cos(a) * r
		addPart(item, { name = "BirchTrunk", shape = CYL, size = Vector3.new(26, 2.2, 2.2), color = rgb(238, 236, 228),
			material = Enum.Material.Wood, offset = CFrame.new(x, 13, z) * UPRIGHT })
		addPart(item, { name = "BirchCrown", shape = BALL, size = Vector3.new(16, 18, 16), color = rgb(206, 190, 90),
			material = Enum.Material.Grass, offset = CFrame.new(x, 30, z) })
	end
	return item
end

PIECES.lowSun = function(art)
	local item = newItem("LowSun")
	item.anchor = "sky"
	item.centre = CFrame.new()
	addPart(item, { name = "Sun", shape = BALL, size = Vector3.new(120, 120, 120), color = rgb(255, 196, 120),
		material = Enum.Material.Neon, transparency = 0.05, offset = CFrame.new(900, 60, -1300) })
	return item
end

PIECES.moon = function(art)
	local item = newItem("Moon")
	item.anchor = "sky"
	item.centre = CFrame.new()
	addPart(item, { name = "Moon", shape = BALL, size = Vector3.new(90, 90, 90), color = rgb(236, 236, 250),
		material = Enum.Material.Neon, offset = CFrame.new(-700, 700, -1200) })
	-- the crescent: a dark disc in front of the moon, slightly off-centre
	addPart(item, { name = "MoonShadow", shape = BALL, size = Vector3.new(86, 86, 86), color = rgb(30, 30, 56),
		material = Enum.Material.SmoothPlastic, offset = CFrame.new(-680, 712, -1170) })
	return item
end

PIECES.lighthouse = function(art)
	local item = newItem("Lighthouse")
	item.anchor = "world"
	item.root = CFrame.new(-300, 0, 300)
	addPart(item, { name = "LighthouseTower", shape = CYL, size = Vector3.new(60, 10, 10), color = rgb(236, 236, 236),
		material = Enum.Material.Concrete, offset = CFrame.new(0, 30, 0) * UPRIGHT })
	addPart(item, { name = "LighthouseStripe", shape = CYL, size = Vector3.new(8, 10.4, 10.4), color = rgb(60, 70, 120),
		material = Enum.Material.Concrete, offset = CFrame.new(0, 40, 0) * UPRIGHT })
	local lamp = addPart(item, { name = "LighthouseLamp", shape = BALL, size = Vector3.new(7, 7, 7), color = rgb(255, 240, 180),
		material = Enum.Material.Neon, offset = CFrame.new(0, 63, 0) })
	addBeam(item, lamp, Vector3.new(0, 0, 0), Vector3.new(0, 0, -600), { color = ColorSequence.new(rgb(255, 245, 200)),
		width0 = 6, width1 = 60, transparency = 0.6, faceCamera = true })
	item.spin = 0.6 -- the lamp sweeps
	return item
end

PIECES.aurora = function(art)
	local item = newItem("Aurora")
	item.anchor = "sky"
	item.centre = CFrame.new()
	local host = addPart(item, { name = "AuroraHost", size = Vector3.new(1, 1, 1), transparency = 1, offset = CFrame.new(0, 420, -600) })
	local colours = { rgb(80, 255, 190), rgb(90, 200, 255), rgb(160, 120, 255) }
	for i = 1, 3 do
		local y = 30 * (i - 2)
		addBeam(item, host, Vector3.new(-900, y, (i - 2) * 120), Vector3.new(900, y + 40, (i - 2) * 160), {
			color = ColorSequence.new(colours[i]), width0 = 140, width1 = 220, curve0 = 300, curve1 = -260, transparency = 0.45,
			faceCamera = false, segments = 24 })
	end
	return item
end

PIECES.peaks = function(art)
	local item = newItem("Peaks")
	item.anchor = "world"
	item.root = CFrame.new()
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2 + 0.5
		local r = 650
		local hgt = 180 + (i % 3) * 60
		addPart(item, { class = "WedgePart", name = "Peak", size = Vector3.new(220, hgt, 160), color = rgb(150, 160, 190),
			material = Enum.Material.Rock, offset = CFrame.new(math.sin(a) * r, hgt / 2 - 10, math.cos(a) * r) * CFrame.Angles(0, a, 0) })
		addPart(item, { class = "WedgePart", name = "Snowcap", size = Vector3.new(80, hgt * 0.3, 60), color = rgb(245, 250, 255),
			material = Enum.Material.Snow, offset = CFrame.new(math.sin(a) * r, hgt * 0.85, math.cos(a) * r) * CFrame.Angles(0, a, 0) })
	end
	return item
end

PIECES.comet = function(art)
	local item = newItem("GreatComet")
	item.anchor = "sky"
	item.centre = CFrame.new()
	addPart(item, { name = "CometHead", shape = BALL, size = Vector3.new(40, 40, 40), color = rgb(230, 250, 255),
		material = Enum.Material.Neon, offset = CFrame.new(300, 900, -1400) })
	for i = 1, 4 do
		addPart(item, { name = "CometTail", size = Vector3.new(30 - i * 4, 30 - i * 4, 220), color = rgb(160, 210, 255),
			material = Enum.Material.Neon, transparency = 0.25 + i * 0.15,
			offset = CFrame.new(300 - i * 170, 900 + i * 50, -1400 - i * 60) * CFrame.Angles(math.rad(-15), math.rad(-70), 0) })
	end
	return item
end

PIECES.nebula = function(art)
	local item = newItem("Nebula")
	item.anchor = "sky"
	item.centre = CFrame.new()
	local colours = { rgb(200, 120, 255), rgb(120, 200, 255), rgb(255, 150, 220), rgb(150, 110, 255), rgb(90, 220, 220), rgb(230, 170, 255) }
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		addPart(item, { name = "NebulaCloud", shape = BALL, size = Vector3.new(500 + i * 40, 300, 420), color = colours[i],
			material = Enum.Material.Neon, transparency = 0.82,
			offset = CFrame.new(math.sin(a) * 900, 1100 + (i % 3) * 120, -1600 + math.cos(a) * 500) })
	end
	return item
end

PIECES.ringedPlanet = function(art)
	local item = newItem("RingedPlanet")
	item.anchor = "sky"
	item.centre = CFrame.new()
	addPart(item, { name = "Planet", shape = BALL, size = Vector3.new(420, 420, 420), color = rgb(214, 180, 140),
		material = Enum.Material.SmoothPlastic, offset = CFrame.new(-1500, 700, -2400) })
	addPart(item, { name = "PlanetRing", shape = CYL, size = Vector3.new(6, 900, 900), color = rgb(236, 220, 190),
		material = Enum.Material.Glass, transparency = 0.35, offset = CFrame.new(-1500, 700, -2400) * CFrame.Angles(0, 0, math.rad(70)) })
	return item
end

PIECES.galaxy = function(art)
	local item = newItem("Galaxy")
	item.anchor = "sky"
	item.centre = CFrame.new()
	local core = addPart(item, { name = "GalaxyCore", shape = BALL, size = Vector3.new(260, 90, 260), color = rgb(255, 240, 200),
		material = Enum.Material.Neon, offset = CFrame.new(0, 1400, -1800) })
	local colours = { rgb(255, 225, 160), rgb(200, 170, 255), rgb(255, 200, 230), rgb(170, 210, 255) }
	for i = 1, 4 do
		local a = (i - 1) / 4 * math.pi * 2
		addBeam(item, core, Vector3.new(0, 0, 0), Vector3.new(math.cos(a) * 1200, 0, math.sin(a) * 1200), {
			color = ColorSequence.new(colours[i]), width0 = 180, width1 = 60, curve0 = 500, curve1 = 200, transparency = 0.35,
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

CRITTERS.swallow = flapper(rgb(40, 44, 66), 2.2, 0.8)
CRITTERS.bat = flapper(rgb(34, 30, 44), 2.6, 1.1)
CRITTERS.butterfly = function(item)
	local palette = { rgb(255, 200, 80), rgb(140, 200, 255), rgb(255, 170, 220) }
	local c = palette[math.random(1, #palette)]
	flapper(c, 0.9, 0.7)(item)
end
CRITTERS.firefly = function(item)
	addPart(item, { name = "Firefly", shape = BALL, size = Vector3.new(0.4, 0.4, 0.4), color = rgb(230, 255, 120), material = Enum.Material.Neon })
end
CRITTERS.wisp = function(item)
	addPart(item, { name = "Wisp", shape = BALL, size = Vector3.new(1.2, 1.2, 1.2), color = rgb(150, 255, 230), material = Enum.Material.Neon, transparency = 0.3 })
end
CRITTERS.owl = function(item)
	addPart(item, { name = "OwlBody", shape = BALL, size = Vector3.new(1.6, 2, 1.6), color = rgb(240, 242, 248) })
	flapper(rgb(230, 232, 240), 2.4, 1)(item)
	local wingAnim = item.animate
	item.animate = function(it, cf, now)
		it.entries[1].part.CFrame = cf
		local saved = it.entries
		it.entries = { saved[2], saved[3] }
		wingAnim(it, cf, now)
		it.entries = saved
	end
end
CRITTERS.shootingStar = function(item)
	local p = addPart(item, { name = "ShootingStar", shape = BALL, size = Vector3.new(3, 3, 3), color = rgb(255, 240, 200), material = Enum.Material.Neon })
	addTrail(item, p, 1.5, { lifetime = 0.7, color = rgb(255, 225, 170), transparency = 0.1, lightEmission = 1 })
end
CRITTERS.starJelly = function(item)
	addPart(item, { name = "JellyBell", shape = BALL, size = Vector3.new(5, 3.4, 5), color = rgb(190, 150, 255), material = Enum.Material.Neon, transparency = 0.35 })
	for i = 1, 3 do
		local a = (i - 1) / 3 * math.pi * 2
		addPart(item, { name = "JellyTendril", size = Vector3.new(0.3, 4, 0.3), color = rgb(220, 200, 255), material = Enum.Material.Neon,
			transparency = 0.4, offset = CFrame.new(math.sin(a) * 1.4, -3, math.cos(a) * 1.4) })
	end
	item.animate = function(it, cf, now)
		local bob = CFrame.new(0, math.sin(now * 1.3 + (it.phase or 0)) * 1.5, 0)
		for _, e in it.entries do
			e.part.CFrame = cf * bob * e.offset
		end
	end
end
CRITTERS.comet = function(item)
	local p = addPart(item, { name = "Comet", shape = BALL, size = Vector3.new(8, 8, 8), color = rgb(210, 244, 255), material = Enum.Material.Neon })
	addTrail(item, p, 4, { lifetime = 2.5, color = rgb(160, 220, 255), transparency = 0.15, lightEmission = 1 })
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
	self.effects = {} -- streaks, zips, burn-ups: { item, t, duration, update }
	self.pool = {} -- name -> { free items }
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
		if item.spin then
			place(item, item.root * CFrame.Angles(0, (now or 0) * item.spin, 0))
		elseif not item.placed then
			place(item, item.root)
			item.placed = true
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
	-- "Critter_<kind>_<part>": a headless check can tell a swallow's wing from a bat's
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
	satellite = function(item)
		addPart(item, { name = "Body", size = Vector3.new(3, 3, 4), color = rgb(206, 174, 84), material = Enum.Material.Foil })
		addPart(item, { name = "PanelL", size = Vector3.new(6, 0.2, 3), color = rgb(40, 70, 160), material = Enum.Material.Glass, offset = CFrame.new(-4.5, 0, 0) })
		addPart(item, { name = "PanelR", size = Vector3.new(6, 0.2, 3), color = rgb(40, 70, 160), material = Enum.Material.Glass, offset = CFrame.new(4.5, 0, 0) })
	end,
	ice = function(item)
		addPart(item, { name = "Ice", shape = BALL, size = Vector3.new(4.4, 3.6, 4), color = rgb(200, 240, 255), material = Enum.Material.Ice, transparency = 0.15 })
	end,
	bolide = function(item)
		addPart(item, { name = "Fireball", shape = BALL, size = Vector3.new(6, 6, 6), color = rgb(255, 150, 60), material = Enum.Material.Neon })
		addPart(item, { name = "Rock", shape = BALL, size = Vector3.new(4.4, 4.4, 4.4), color = rgb(70, 60, 56), material = Enum.Material.Slate })
	end,
	plasma = function(item)
		addPart(item, { name = "Plasma", shape = BALL, size = Vector3.new(5, 5, 5), color = rgb(230, 110, 255), material = Enum.Material.Neon, transparency = 0.2 })
	end,
	neutron = function(item)
		addPart(item, { name = "Shard", size = Vector3.new(1.2, 5, 1.2), color = rgb(220, 240, 255), material = Enum.Material.Neon,
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

-- Draw the hazard for this frame. `zone` is Hazards.zone(plan, PlayerRadius) while Hazards.threatLive holds
-- (nil once it can no longer hit): the ring is drawn EXACTLY there, radius = the zone's radius, because it
-- IS the hit rule. It is red from the first frame; at the lock it turns solid and the pillar turns red too.
-- `floorY` (PlotGeom.zoneFloor, REVIEW-1): the zone is a column from the ground up to that height plus the
-- old 0.2-stud disc, so one on the 1-stud arrival pad shows on top of it (the hit rule is horizontal: the
-- zone is a column anyway). It used to be a flat disc at the ground, 57-81% of it hidden under the pad.
function SkyArt:showHazard(plan, pos, now, zone, groundY, floorY)
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

function SkyArt.hasWeather(kind, Config)
	return Config.Env.Weather[kind] ~= nil
end

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

--──────────────────────────────────────────── meteor effects: streaks, zips, burn-ups, dish catches
-- Pooled per kind; every effect ends on its own timer, so nothing can pile up.

local function effectItem(self, kind, colour, withTrail)
	local pool = self.pool[kind]
	if pool == nil then
		pool = {}
		self.pool[kind] = pool
	end
	local item = table.remove(pool)
	if item == nil then
		item = newItem("Fx_" .. kind)
		local size = if kind == "star" then 4.5 elseif kind == "streak" then 2.2 elseif kind == "zip" then 1.2 else 3
		local p = addPart(item, { name = "Fx_" .. kind, shape = BALL, size = Vector3.new(size, size, size), material = Enum.Material.Neon })
		if withTrail then
			addTrail(item, p, size / 2, { lifetime = 0.5, color = rgb(255, 240, 210), transparency = 0.15, lightEmission = 1 })
		end
		item.kind = kind
	end
	item.entries[1].part.Color = colour
	for _, t in item.trails do t.Color = ColorSequence.new(colour) end
	return item
end

local function release(self, item)
	setWeight(item, 0, self.folder)
	table.insert(self.pool[item.kind], item)
end

function SkyArt:trailsInUse()
	local n = 0
	for _, fx in self.effects do
		if #fx.item.trails > 0 then n += 1 end
	end
	return n
end

-- A falling streak from `from` to `to` (Vector3s) over `seconds`. Trails only while fewer than maxTrails run.
function SkyArt:streak(from, to, seconds, colour, maxTrails, isStar)
	local trail = self:trailsInUse() < (maxTrails or 2)
	local kind = if isStar then "star" elseif trail then "streak" else "streakPlain"
	local item = effectItem(self, kind, colour, trail)
	setWeight(item, 1, self.folder)
	place(item, CFrame.new(from))
	table.insert(self.effects, { item = item, t = 0, duration = seconds, update = function(it, a)
		place(it, CFrame.new(from:Lerp(to, a)))
	end })
end

-- A collected meteor zips into the Smelter's mouth.
function SkyArt:zip(from, to, colour)
	local item = effectItem(self, "zip", colour, false)
	setWeight(item, 1, self.folder)
	table.insert(self.effects, { item = item, t = 0, duration = 0.35, update = function(it, a)
		local arc = Vector3.new(0, math.sin(a * math.pi) * 4, 0)
		place(it, CFrame.new(from:Lerp(to, a) + arc))
	end })
end

-- A burn-up high in the sky (the plot was full), or a puff (a bounce off a full hopper, a dish catch).
function SkyArt:puff(at, colour, seconds, growTo)
	local item = effectItem(self, "puff", colour, false)
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

function SkyArt:stepEffects(dt)
	for i = #self.effects, 1, -1 do
		local fx = self.effects[i]
		fx.t += dt
		local a = math.clamp(fx.t / fx.duration, 0, 1)
		fx.update(fx.item, a)
		if fx.t >= fx.duration then
			table.remove(self.effects, i)
			if fx.item.kind == "puff" then
				fx.item.entries[1].part.Size = Vector3.new(3, 3, 3)
			end
			release(self, fx.item)
		end
	end
end

function SkyArt:clearEffects()
	for i = #self.effects, 1, -1 do
		release(self, self.effects[i].item)
		table.remove(self.effects, i)
	end
end

return SkyArt
