-- SkyArt.luau — builds and animates the night sky outside the observatory. CLIENT ONLY: required by
-- src/client/Sky.client.luau and nothing else; the server never builds, replicates or reads any of it.
--
-- It turns NightSky.layout (pure data) into local Parts, so where every piece sits is decided and
-- proven in one place: each Part's CFrame is CFrame.fromMatrix(pos, NightSky.pieceAxes(...)), the same
-- axes tests/SkyConfig.spec.luau uses to prove every corner stays beyond the hall's entrance plane.
--
-- Shapes: "Ball", "Block", "Wedge", "Cylinder", and "Ellipsoid" (a flattened sphere: a Block whose
-- Sphere SpecialMesh fills the box, since Roblox forces a Ball to a uniform size).
--
-- Every Part is Anchored and CanCollide / CanQuery / CanTouch false, CastShadow false: nothing can be
-- stood on, bumped, ray-hit or touched, and nothing throws a shadow into the entrance. No Light of
-- any kind is created (Config.Sky.Budget.MaxLights = 0): Neon glows on screen but lights nothing, so
-- no sky event can change how the hall is lit.
--
-- Pooling: a feature's parts are built the first time it shows and UNPARENTED (not destroyed) when
-- its weight reaches zero, so a band you are not in costs no draw calls. Meteors are a pool of
-- `Meteors.Pool` parts that alternate by slot; lightning is one three-segment bolt; the aurora is one
-- host part carrying Beams; the comet's tail is two Beams on its head. Writes are skipped when a value
-- has not changed, so a settled sky costs a handful of writes per frame (the turning stars and the
-- aurora sway at 10 Hz, and whatever meteor or bolt is in flight).
--
-- Dependencies are arguments: `require("./X")` is invalid in Roblox.

local SkyArt = {}
SkyArt.__index = SkyArt

local HIDE_BELOW = 0.003 -- a feature weight under this is off: its folder is unparented
local WRITE_EPS = 0.004 -- transparency changes smaller than this are not written
local SWAY_HZ = 10

local function v3(t: any): Vector3
	return Vector3.new(t.x, t.y, t.z)
end

local function rgb(sky: any, key: string): Color3
	local c = sky.Palette[key]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function plainOrigin(o: Vector3): any
	return { x = o.X, y = o.Y, z = o.Z }
end

-- weight-scaled transparency: weight 1 shows the piece as designed, weight 0 hides it
local function faded(base: number, w: number): number
	return 1 - (1 - base) * math.clamp(w, 0, 1)
end

function SkyArt.new(parent: Instance, sky: any, NightSky: any, EnvBands: any, origin: Vector3)
	local self = setmetatable({}, SkyArt)
	self.sky = sky
	self.NightSky = NightSky
	self.EnvBands = EnvBands
	self.origin = origin
	self.o = plainOrigin(origin)
	self.eye = NightSky.eye(sky.Hall, self.o)
	self.pieces = NightSky.layout(sky, self.o)

	local root = Instance.new("Folder")
	root.Name = "ObservatorySky"
	root.Parent = parent
	self.root = root

	self.byFeature = {}
	for _, p in self.pieces do
		local list = self.byFeature[p.feature]
		if list == nil then
			list = {}
			self.byFeature[p.feature] = list
		end
		table.insert(list, p)
	end

	self.folders = {} -- feature -> Folder (built lazily)
	self.parts = {} -- key -> BasePart
	self.shown = {} -- key -> last written transparency
	self.weights = {}
	self.emitters = {} -- kind -> ParticleEmitter
	self.beams = {} -- list of { beam, baseT = {a, b} }
	self.trails = {}
	self.meteor = { slot = -1, events = {} }
	self.bolt = { slot = -1, ev = nil, lit = false }
	self.swayClock = -1

	-- the land is the place, not a band: it is there every night (it still fades in at join, with
	-- everything else, through setWeights' `land`)
	return self
end

-- ------------------------------------------------------------------ building

function SkyArt:_makePart(p: any): BasePart
	local part: BasePart
	if p.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local pp = Instance.new("Part")
		if p.shape == "Ball" then
			pp.Shape = Enum.PartType.Ball
		elseif p.shape == "Cylinder" then
			pp.Shape = Enum.PartType.Cylinder
		end
		part = pp
	end
	part.Name = p.key
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = if p.material == "SmoothPlastic" then Enum.Material.SmoothPlastic else Enum.Material.Neon
	part.Color = rgb(self.sky, p.color)
	part.Size = v3(p.size)
	if p.shape == "Ellipsoid" then
		-- A flattened sphere: Roblox forces a Ball uniform, so this is a Block whose Sphere mesh fills
		-- the box (the box is what NightSky's clearance proof measures, so the proof still holds).
		local mesh = Instance.new("SpecialMesh")
		mesh.Name = "EllipsoidMesh"
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	local ax = self.NightSky.pieceAxes(p, self.eye)
	part.CFrame = CFrame.fromMatrix(v3(p.pos), v3(ax.X), v3(ax.Y), v3(ax.Z))
	part.Transparency = 1
	return part
end

function SkyArt:_build(feature: string)
	if self.folders[feature] then return end
	local folder = Instance.new("Folder")
	folder.Name = "Sky_" .. feature
	self.folders[feature] = folder
	local sky = self.sky
	for _, p in self.byFeature[feature] or {} do
		local part = self:_makePart(p)
		part.Parent = folder
		self.parts[p.key] = part
		self.shown[p.key] = 1
		if p.emitter == "stars" then
			self:_starEmitter(part)
		elseif p.emitter == "rain" then
			self:_rainEmitter(part)
		elseif p.role == "meteor" then
			self:_meteorTrail(part)
		elseif p.role == "auroraHost" then
			self:_aurora(part)
		elseif p.role == "cometHead" then
			self:_cometTail(part)
		end
	end
	local _ = sky
end

function SkyArt:_starEmitter(host: BasePart)
	local S = self.sky.Stars
	local e = Instance.new("ParticleEmitter")
	e.Name = "StarTwinkle"
	e.Rate = 0
	e.Enabled = false
	e.Lifetime = NumberRange.new(S.Lifetime[1], S.Lifetime[2])
	e.Speed = NumberRange.new(0, 0)
	e.LockedToPart = true
	e.LightEmission = 1
	e.Color = ColorSequence.new(rgb(self.sky, S.Color))
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, S.ParticleSize),
		NumberSequenceKeypoint.new(0.7, S.ParticleSize * 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	pcall(function()
		(e :: any).Shape = Enum.ParticleEmitterShape.Box;
		(e :: any).ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end)
	e.Parent = host
	self.emitters.stars = e
end

function SkyArt:_rainEmitter(host: BasePart)
	local R = self.sky.Rain
	local e = Instance.new("ParticleEmitter")
	e.Name = "Rain"
	e.Rate = 0
	e.Enabled = false
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Speed = NumberRange.new(R.Speed, R.Speed)
	e.SpreadAngle = Vector2.new(R.SpreadDegrees, R.SpreadDegrees)
	e.Lifetime = NumberRange.new(R.Lifetime, R.Lifetime)
	e.Color = ColorSequence.new(rgb(self.sky, R.Color))
	e.Size = NumberSequence.new(0.12)
	e.Transparency = NumberSequence.new(0.45)
	e.LightEmission = 0.2
	pcall(function()
		(e :: any).Orientation = Enum.ParticleOrientation.VelocityParallel;
		(e :: any).Squash = NumberSequence.new(3)
	end)
	e.Parent = host
	self.emitters.rain = e
end

function SkyArt:_meteorTrail(part: BasePart)
	local Me = self.sky.Meteors
	local a0 = Instance.new("Attachment")
	a0.Name = "Head"
	a0.Position = Vector3.new(0, 0, -Me.Size[3] / 2)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "Tail"
	a1.Position = Vector3.new(0, 0, Me.Size[3] / 2)
	a1.Parent = part
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = Me.TrailSeconds
	t.LightEmission = 1
	t.FaceCamera = true
	t.Color = ColorSequence.new(rgb(self.sky, Me.Color))
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	t.Enabled = false
	t.Parent = part
	self.trails[part] = t
end

-- One Beam between two world points, hosted on `host` (attachments placed in host space).
function SkyArt:_beam(host: BasePart, name: string, fromW: Vector3, toW: Vector3, widths: { number }, colors: ColorSequence,
	transparency: { number }, curve: boolean): Beam
	local cf = host.CFrame
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "A0"
	a0.Position = cf:PointToObjectSpace(fromW)
	a0.Parent = host
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "A1"
	a1.Position = cf:PointToObjectSpace(toW)
	a1.Parent = host
	local b = Instance.new("Beam")
	b.Name = name
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = widths[1]
	b.Width1 = widths[2]
	b.Color = colors
	b.LightEmission = 1
	b.FaceCamera = true
	b.Segments = if curve then 16 else 1
	b.Transparency = NumberSequence.new(1)
	b.Enabled = false
	b.Parent = host
	table.insert(self.beams, { beam = b, base = transparency, weight = -1, curve = curve })
	return b
end

function SkyArt:_aurora(host: BasePart)
	local A = self.sky.Aurora
	local NS = self.NightSky
	local span = (A.AzRange[2] - A.AzRange[1]) / A.Count
	for i = 1, A.Count do
		local az0 = A.AzRange[1] + (i - 1) * span
		local el = A.ElRange[1] + (A.ElRange[2] - A.ElRange[1]) * ((i - 1) % 2) * 0.6
		local p0 = NS.skyPoint(self.eye, az0, el, A.Distance)
		local p1 = NS.skyPoint(self.eye, az0 + span * 1.1, el + 2, A.Distance)
		local c1 = rgb(self.sky, A.Colors[(i - 1) % #A.Colors + 1])
		local c2 = rgb(self.sky, A.Colors[i % #A.Colors + 1])
		local w = A.Width[1] + (A.Width[2] - A.Width[1]) * (((i * 7) % 5) / 4)
		self:_beam(host, "Aurora" .. i, v3(p0), v3(p1), { w, w * 0.8 },
			ColorSequence.new(c1, c2), { A.Transparency[1], A.Transparency[2] }, true)
	end
end

function SkyArt:_cometTail(head: BasePart)
	local C = self.sky.Comet
	local NS = self.NightSky
	local hp = { x = head.Position.X, y = head.Position.Y, z = head.Position.Z }
	local tip = NS.skyPoint(hp, C.TailAzimuth, C.TailElevation, C.TailLength)
	local colors = ColorSequence.new(rgb(self.sky, C.ComaColor), rgb(self.sky, C.TailColor))
	self:_beam(head, "CometTail", head.Position, v3(tip), { C.TailWidth[1], C.TailWidth[2] }, colors, { 0.35, 1 }, false)
	local core = NS.skyPoint(hp, C.TailAzimuth, C.TailElevation, C.TailLength * 0.6)
	self:_beam(head, "CometCore", head.Position, v3(core), { C.TailWidth[1] * 0.35, C.TailWidth[2] * 0.25 }, colors, { 0.1, 1 }, false)
end

-- ------------------------------------------------------------------ weights

function SkyArt:_setFeatureWeight(feature: string, w: number)
	local list = self.byFeature[feature]
	if list == nil then return end
	if w < HIDE_BELOW then
		local f = self.folders[feature]
		if f and f.Parent ~= nil then
			f.Parent = nil
		end
		self.weights[feature] = 0
		return
	end
	self:_build(feature)
	local f = self.folders[feature]
	if f.Parent ~= self.root then
		f.Parent = self.root
	end
	self.weights[feature] = w
	for _, p in list do
		if not p.live and p.role ~= "moon" and p.role ~= "shade" then
			self:_show(p.key, faded(p.transparency, w))
		end
	end
end

-- Small changes are skipped mid-glide to save writes; once the caller says the sky has SETTLED
-- (setWeights(.., true)) every value is written exactly, so a Day's sky ends identical whatever
-- path led to it (a climb, a reset, a rejoin).
function SkyArt:_show(key: string, t: number)
	local last = self.shown[key]
	if last == t then return end
	local eps = if self.exact then 0 else WRITE_EPS
	if last ~= nil and math.abs(last - t) < eps and not (t >= 1 and last < 1) and not (t < 1 and last >= 1) then
		return
	end
	local part = self.parts[key]
	if part then
		part.Transparency = t
		self.shown[key] = t
	end
end

-- weights: { [feature] = 0..1 } as blended (and glided) by the caller. `settled`: the caller's
-- glide has arrived, so write exact values.
function SkyArt:setWeights(weights: { [string]: number }, settled: boolean?)
	self.exact = settled == true
	self:_setFeatureWeight("land", weights.land or 0)
	for _, feature in self.NightSky.FEATURES do
		self:_setFeatureWeight(feature, weights[feature] or 0)
	end
	-- beams follow their feature's weight
	for _, b in self.beams do
		local feature = if string.sub(b.beam.Name, 1, 6) == "Aurora" then "aurora" else "comet"
		local w = self.weights[feature] or 0
		local stepEps = if self.exact then 0 else 0.01
		if (w ~= b.weight and math.abs(w - b.weight) >= stepEps) or (w == 0) ~= (b.weight == 0) then
			b.weight = w
			if w <= 0 then
				b.beam.Enabled = false
			else
				b.beam.Enabled = true
				b.beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, faded(b.base[1], w)),
					NumberSequenceKeypoint.new(1, faded(b.base[2], w)),
				})
			end
		end
	end
	-- emitters: blended rates, capped to the budget in code (EnvBands.capRates)
	local B = self.sky.Budget
	local want = {
		stars = self.sky.Stars.Rate * (self.weights.stars or 0),
		rain = self.sky.Rain.Rate * (self.weights.storm or 0),
	}
	local on = self.EnvBands.capRates(want, B.MaxEmitters, B.MaxEmitterRate, 0.05)
	for kind, e in self.emitters do
		local rate = on[kind]
		if rate then
			if not e.Enabled then e.Enabled = true end
			if e.Rate ~= rate and (self.exact or math.abs(e.Rate - rate) > 0.05) then e.Rate = rate end
		elseif e.Enabled then
			e.Enabled = false
			e.Rate = 0
		end
	end
end

-- ------------------------------------------------------------------ the moon

-- draw = NightSky.moonDraw(phase); w = the moon feature's weight.
function SkyArt:setMoon(draw: any, w: number)
	local moon, shade = self.parts.Moon, self.parts.MoonShade
	if moon == nil or shade == nil then return end
	local M = self.sky.Moon
	local visible = w >= HIDE_BELOW and draw.showMoon
	self:_show("Moon", if visible then faded(0, w * draw.moonAlpha) else 1)
	if visible and draw.showShade then
		local home = self.NightSky.skyPoint(self.eye, M.Azimuth, M.Elevation, M.Distance - 2)
		local basis = self.NightSky.faceBasis(self.eye, home)
		-- slide the dark disc AWAY from the lit limb: waxing (side 1) is lit on the right
		local k = -draw.side * draw.offset * M.Radius
		local pos = Vector3.new(home.x + basis.right.x * k, home.y + basis.right.y * k, home.z + basis.right.z * k)
		local gap = (shade.Position - pos).Magnitude
		if gap > 0.01 or (self.exact and gap > 0) then
			shade.CFrame = CFrame.new(pos)
		end
		self:_show("MoonShade", faded(0, w * draw.shadeAlpha))
	else
		self:_show("MoonShade", 1)
	end
end

-- ------------------------------------------------------------------ animation

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Meteors: on the first frame of each slot, decide (roll < Chance * weight) and queue; a queued
-- meteor flies along NightSky.meteorPath, its pooled part alternating by slot parity.
function SkyArt:_meteors(clock: number)
	local Me = self.sky.Meteors
	local NS = self.NightSky
	local w = self.weights.meteors or 0
	local slot = NS.slotOf(Me, clock)
	if slot ~= self.meteor.slot then
		self.meteor.slot = slot
		if w > 0 then
			local ev = NS.slotEvent(Me, slot, self.sky.Seed, self.EnvBands)
			if ev.roll < Me.Chance * w then
				table.insert(self.meteor.events, { ev = ev, path = NS.meteorPath(Me, ev), key = "Meteor" .. (slot % Me.Pool + 1), started = false })
			end
		end
	end
	local keep = {}
	for _, m in self.meteor.events do
		local part = self.parts[m.key]
		local trail = part and self.trails[part]
		local f = (clock - m.ev.start) / m.ev.duration
		if part == nil then
			continue
		end
		if f < 0 then
			table.insert(keep, m)
		elseif f <= 1 then
			local at = NS.skyPoint(self.eye, lerp(m.path.from.az, m.path.to.az, f), lerp(m.path.from.el, m.path.to.el, f), Me.Distance)
			local ahead = NS.skyPoint(self.eye, lerp(m.path.from.az, m.path.to.az, f + 0.05), lerp(m.path.from.el, m.path.to.el, f + 0.05), Me.Distance)
			part.CFrame = CFrame.lookAt(v3(at), v3(ahead))
			if not m.started then
				m.started = true
				if trail then
					pcall(function() (trail :: any):Clear() end)
					trail.Enabled = true
				end
			end
			self:_show(m.key, 0)
			table.insert(keep, m)
		else
			if trail then trail.Enabled = false end
			self:_show(m.key, 1)
		end
	end
	self.meteor.events = keep
end

-- Silent lightning: one bolt, three segments, drawn along NightSky.boltPath for the flash.
function SkyArt:_lightning(clock: number)
	local Li = self.sky.Lightning
	local NS = self.NightSky
	local w = self.weights.storm or 0
	local slot = NS.slotOf(Li, clock)
	if slot ~= self.bolt.slot then
		self.bolt.slot = slot
		self.bolt.ev = nil
		if w > 0 then
			local ev = NS.slotEvent(Li, slot, self.sky.Seed, self.EnvBands)
			if ev.roll < Li.Chance * w then
				self.bolt.ev = ev
			end
		end
	end
	local ev = self.bolt.ev
	local on = ev ~= nil and clock >= ev.start and clock <= ev.start + ev.duration
	if on and not self.bolt.lit then
		local pts = NS.boltPath(Li, ev)
		for i = 1, 3 do
			local a = v3(NS.skyPoint(self.eye, pts[i].az, pts[i].el, Li.Distance))
			local b = v3(NS.skyPoint(self.eye, pts[i + 1].az, pts[i + 1].el, Li.Distance))
			local part = self.parts["Bolt" .. i]
			if part then
				part.Size = Vector3.new(Li.Thickness, Li.Thickness, (b - a).Magnitude)
				part.CFrame = CFrame.lookAt((a + b) / 2, b)
			end
			self:_show("Bolt" .. i, 0)
		end
		self.bolt.lit = true
	elseif not on and self.bolt.lit then
		for i = 1, 3 do
			self:_show("Bolt" .. i, 1)
		end
		self.bolt.lit = false
	end
end

-- Slow motion at 10 Hz: the aurora's curtains sway, the other sky's stars turn.
function SkyArt:_sway(clock: number)
	local tick = math.floor(clock * SWAY_HZ)
	if tick == self.swayClock then return end
	self.swayClock = tick
	local A = self.sky.Aurora
	if (self.weights.aurora or 0) > 0 then
		for i, b in self.beams do
			if b.curve then
				local ph = 2 * math.pi * clock / A.SwaySeconds + i * 1.7
				b.beam.CurveSize0 = A.SwayStuds * math.sin(ph)
				b.beam.CurveSize1 = -A.SwayStuds * math.sin(ph * 0.8 + 1.1)
			end
		end
	end
	if (self.weights.othersky or 0) > 0 then
		local Sp = self.sky.OtherSky.Spiral
		local NS = self.NightSky
		local centre = NS.skyPoint(self.eye, Sp.Azimuth, Sp.Elevation, Sp.Distance)
		for i = 1, Sp.Count do
			local part = self.parts["Turning" .. i]
			if part then
				part.CFrame = CFrame.new(v3(NS.spiralPoint(Sp, self.eye, centre, i, clock)))
				self:_show("Turning" .. i, faded(0, self.weights.othersky))
			end
		end
	end
end

-- Everything that moves, for the sky's own clock (seconds). Call after setWeights.
function SkyArt:step(clock: number)
	if self.folders.meteors and (self.weights.meteors or 0) > 0 or #self.meteor.events > 0 then
		self:_meteors(clock)
	end
	if self.folders.storm and ((self.weights.storm or 0) > 0 or self.bolt.lit) then
		self:_lightning(clock)
	end
	self:_sway(clock)
end

-- ------------------------------------------------------------------ measuring

-- What is actually in the world right now (parented under workspace), for the budget.
function SkyArt:stats(): any
	local s = { parts = 0, emitters = 0, rate = 0, beams = 0, trails = 0, lights = 0 }
	for _, d in self.root:GetDescendants() do
		if d:IsA("BasePart") then
			s.parts += 1
		elseif d:IsA("ParticleEmitter") then
			if d.Enabled then
				s.emitters += 1
				s.rate += d.Rate
			end
		elseif d:IsA("Beam") then
			if d.Enabled then s.beams += 1 end
		elseif d:IsA("Trail") then
			if d.Enabled then s.trails += 1 end
		elseif d:IsA("Light") then
			s.lights += 1
		end
	end
	return s
end

return SkyArt
