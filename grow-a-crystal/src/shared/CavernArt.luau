-- CavernArt.luau — Grow a Crystal's client-built eye candy: scenery, critters, particle "weather",
-- visitors and harvest bursts. Code only, no assets. CLIENT ONLY (required by Grotto.client.luau).
--
-- Every Part made here is LOCAL (the client creates it, so it never replicates), Anchored, and
-- CanCollide / CanQuery / CanTouch = false: nothing can be stood on, nothing blocks a click on a
-- socket, nothing can touch anything. Nothing here reads another player's state or writes to an
-- object the server built.
--
-- WHERE things go is decided by the pure Grotto.layout (plot-local coordinates, spec'd); this module
-- adds the player's plot origin and owns every engine call. How much of each piece shows is decided by
-- the caller from the band weights: a piece at weight w shows the first ceil(w * n) of its n elements,
-- the last one fading in, so the cavern fills up as chambers are bought instead of switching looks.
-- A piece at weight 0 is unparented (costs no draw calls). Pools: critters per kind, one visitor
-- flock per kind, MaxShards harvest shards, one ring, one beam (+ its light), one host per weather kind.
--
--   local art = CavernArt.new(folder, rand, Config, Grotto, layout, Cavern)
--   art:setOrigin(originVector3)
--   art:updatePiece(id, w, pulse, depth)
--   art:updateCritters({ moth = 4, bat = 3 }, dt, now)
--   art:updateWeather({ mist = 8 })              -- already capped (EnvBands.capRates)
--   art:startVisitor(kind) / art:updateVisitor(kind, u, now) / art:endVisitor(kind)
--   art:burst(worldPos, rule, color, now) / art:updateBursts(dt, now)

local CavernArt = {}
CavernArt.__index = CavernArt

local RAD = math.pi / 180

local function c3(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function v3(t: any): Vector3
	return Vector3.new(t.x, t.y, t.z)
end

local function newPart(name: string, shape: string, size: Vector3, color: Color3, transparency: number, material: string?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape ~= "Block" then
		p.Shape = Enum.PartType[shape]
	end
	p.Size = size
	p.Material = Enum.Material[material or "Neon"]
	p.Color = color
	p.Transparency = transparency
	return p
end

local function setTransparency(p: BasePart, t: number)
	if math.abs(p.Transparency - t) > 0.01 then
		p.Transparency = t
	end
end

function CavernArt.new(folder: Instance, rand: () -> number, Config: any, Grotto: any, layout: any, Cavern: any)
	local self = setmetatable({}, CavernArt)
	self.folder = folder
	self.rand = rand
	self.Config = Config
	self.Grotto = Grotto
	self.layout = layout
	self.Cavern = Cavern
	self.origin = nil :: Vector3?
	self.pieces = {} -- id -> { parts = { Part }, defs = { element } }
	self.critters = {} -- kind -> { critter record }
	self.weather = {} -- kind -> { host = Part, emitter = ParticleEmitter }
	self.visitors = {} -- kind -> { members = { record }, active = boolean }
	self.shards = {} -- pooled harvest shards
	self.ring = nil
	self.beam = nil
	return self
end

function CavernArt:setOrigin(origin: Vector3)
	if self.origin ~= nil and (self.origin - origin).Magnitude < 1e-3 then
		return
	end
	self.origin = origin
	-- a new plot (never expected mid-session): rebuild everything lazily at the new place
	for _, rec in self.pieces do
		for _, p in rec.parts do p:Destroy() end
	end
	self.pieces = {}
	for _, w in self.weather do
		w.host:Destroy()
	end
	self.weather = {}
end

--============================================================================ scenery pieces

function CavernArt:_buildPiece(id: string): any
	local defs = self.layout.pieces[id]
	local rec = { parts = {}, defs = defs }
	local origin = self.origin :: Vector3
	for i, e in defs do
		local p = newPart(e.name, e.shape, v3(e.size), c3(e.color), 1, e.material)
		local o = e.orientation
		p.CFrame = CFrame.new(origin + v3(e.position)) * CFrame.Angles(o.x * RAD, o.y * RAD, o.z * RAD)
		rec.parts[i] = p
	end
	self.pieces[id] = rec
	return rec
end

-- w: 0..1 (the caller smooths it). pulse: 0..1 (Grotto.pulse). depth: how far a glowing element dims
-- at the bottom of the pulse (0 = no breathing).
function CavernArt:updatePiece(id: string, w: number, pulse: number, depth: number)
	local rec = self.pieces[id]
	if w <= 0.001 or self.origin == nil then
		if rec then
			for _, p in rec.parts do
				if p.Parent ~= nil then p.Parent = nil end
			end
		end
		return
	end
	if rec == nil then
		if self.layout.pieces[id] == nil then return end
		rec = self:_buildPiece(id)
	end
	local n = #rec.parts
	for i, p in rec.parts do
		local alpha = math.clamp(w * n - (i - 1), 0, 1)
		if alpha <= 0.001 then
			if p.Parent ~= nil then p.Parent = nil end
		else
			local e = rec.defs[i]
			local base = e.transparency
			if e.glow then
				base += (1 - base) * depth * (1 - pulse) * 0.8
			end
			setTransparency(p, 1 - (1 - base) * alpha)
			if p.Parent ~= self.folder then p.Parent = self.folder end
		end
	end
end

--============================================================================ critters

local CRITTER_LOOK = {
	moth = { color = { 255, 236, 170 }, size = 0.32, transparency = 0.1 },
	wisp = { color = { 200, 240, 255 }, size = 0.55, transparency = 0.15 },
	bat = { color = { 34, 30, 40 } },
}

function CavernArt:_newCritter(kind: string): any
	local c = { kind = kind, parts = {}, alive = false, fade = 0 }
	if kind == "bat" then
		local col = c3(CRITTER_LOOK.bat.color)
		c.parts[1] = newPart("Bat_Body", "Block", Vector3.new(0.6, 0.5, 1.0), col, 0, "SmoothPlastic")
		c.parts[2] = newPart("Bat_WingL", "Block", Vector3.new(1.5, 0.08, 0.9), col, 0, "SmoothPlastic")
		c.parts[3] = newPart("Bat_WingR", "Block", Vector3.new(1.5, 0.08, 0.9), col, 0, "SmoothPlastic")
	else
		local look = CRITTER_LOOK[kind]
		c.parts[1] = newPart(kind == "moth" and "Moth" or "Wisp", "Ball", Vector3.one * look.size, c3(look.color), 1)
	end
	return c
end

local function zoneWorld(self: any, kind: string): (Vector3, Vector3)
	local z = self.layout.zones[kind]
	local o = self.origin :: Vector3
	return o + v3(z.min), o + v3(z.max)
end

function CavernArt:_spawnCritter(c: any)
	local lo, hi = zoneWorld(self, c.kind)
	local r = self.rand
	c.pos = Vector3.new(lo.X + (hi.X - lo.X) * r(), lo.Y + (hi.Y - lo.Y) * r(), lo.Z + (hi.Z - lo.Z) * r())
	if c.kind == "wisp" then
		c.pos = Vector3.new(c.pos.X, lo.Y + 0.5, c.pos.Z)
	end
	local spec = self.Config.Env.Critters[c.kind]
	c.speed = spec.speedMin + (spec.speedMax - spec.speedMin) * r()
	c.heading = r() * math.pi * 2
	c.phase = r() * 100
	c.alive = true
	c.dying = false
	c.fade = 0
	for _, p in c.parts do p.Parent = self.folder end
end

local function place(c: any, now: number)
	local p = c.parts
	if c.kind == "bat" then
		local dir = Vector3.new(math.sin(c.heading), 0, math.cos(c.heading))
		local body = CFrame.lookAt(c.pos, c.pos + dir)
		local flap = math.sin(now * 16 + c.phase) * 0.9
		p[1].CFrame = body
		p[2].CFrame = body * CFrame.new(-0.3, 0, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(-0.75, 0, 0)
		p[3].CFrame = body * CFrame.new(0.3, 0, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(0.75, 0, 0)
	else
		p[1].CFrame = CFrame.new(c.pos)
	end
end

function CavernArt:_moveCritter(c: any, dt: number, now: number)
	local lo, hi = zoneWorld(self, c.kind)
	local r = self.rand
	if c.kind == "wisp" then
		-- rise up the light shaft on a slow spiral, and start again from the water when out of the top
		c.pos += Vector3.new(math.cos(now * 0.8 + c.phase) * 0.6 * dt, c.speed * dt, math.sin(now * 0.8 + c.phase) * 0.6 * dt)
		if c.pos.Y > hi.Y then
			c.pos = Vector3.new(lo.X + (hi.X - lo.X) * r(), lo.Y + 0.5, lo.Z + (hi.Z - lo.Z) * r())
			c.fade = 0
		end
		return
	end
	-- wander: a heading that drifts, a gentle bob, turned back toward the middle at the zone's edge
	local turn = if c.kind == "bat" then 3 else 1.6
	c.heading += (r() - 0.5) * turn * dt * 4
	local centre = (lo + hi) / 2
	local out = c.pos.X < lo.X or c.pos.X > hi.X or c.pos.Z < lo.Z or c.pos.Z > hi.Z
	if out then
		c.heading = math.atan2(centre.X - c.pos.X, centre.Z - c.pos.Z)
	end
	local bob = math.sin(now * (if c.kind == "bat" then 2 else 3) + c.phase) * 0.8
	local vel = Vector3.new(math.sin(c.heading) * c.speed, bob, math.cos(c.heading) * c.speed)
	c.pos += vel * dt
	c.pos = Vector3.new(c.pos.X, math.clamp(c.pos.Y, lo.Y, hi.Y), c.pos.Z)
end

-- counts: { [kind] = how many should be alive }. At most one new critter per kind per frame.
function CavernArt:updateCritters(counts: { [string]: number }, dt: number, now: number)
	if self.origin == nil then return end
	for kind in self.layout.zones do
		local want = counts[kind] or 0
		local list = self.critters[kind]
		if list == nil then
			list = {}
			self.critters[kind] = list
		end
		local alive = 0
		for _, c in list do
			if c.alive and not c.dying then alive += 1 end
		end
		if alive < want then
			local spare = nil
			for _, c in list do
				if not c.alive then spare = c; break end
			end
			if spare == nil then
				spare = self:_newCritter(kind)
				table.insert(list, spare)
			end
			self:_spawnCritter(spare)
		elseif alive > want then
			for i = #list, 1, -1 do
				local c = list[i]
				if c.alive and not c.dying then
					c.dying = true
					break
				end
			end
		end
		for _, c in list do
			if c.alive then
				c.fade = math.clamp(c.fade + (if c.dying then -dt else dt), 0, 1)
				if c.dying and c.fade <= 0 then
					c.alive = false
					for _, p in c.parts do p.Parent = nil end
				else
					self:_moveCritter(c, dt, now)
					place(c, now)
					local base = if kind == "bat" then 0 else CRITTER_LOOK[kind].transparency
					for _, p in c.parts do setTransparency(p, 1 - (1 - base) * c.fade) end
				end
			end
		end
	end
end

--============================================================================ weather (particle volumes)

local WEATHER = {
	drips = function(pe: ParticleEmitter)
		pe.Lifetime = NumberRange.new(1.2, 1.8)
		pe.Speed = NumberRange.new(0, 1)
		pe.Acceleration = Vector3.new(0, -40, 0)
		pe.EmissionDirection = Enum.NormalId.Bottom
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.06) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		pe.LightEmission = 0.6
	end,
	spores = function(pe: ParticleEmitter)
		pe.Lifetime = NumberRange.new(5, 8)
		pe.Speed = NumberRange.new(0.3, 1)
		pe.Acceleration = Vector3.new(0, 0.6, 0)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(1, 1) })
		pe.LightEmission = 1
	end,
	mist = function(pe: ParticleEmitter)
		pe.Lifetime = NumberRange.new(2, 3.5)
		pe.Speed = NumberRange.new(1, 3)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.SpreadAngle = Vector2.new(40, 40)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
		pe.LightEmission = 0.3
	end,
	sparkle = function(pe: ParticleEmitter)
		pe.Lifetime = NumberRange.new(1, 2)
		pe.Speed = NumberRange.new(0, 0.5)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		pe.LightEmission = 1
	end,
}

function CavernArt.hasWeather(kind: string): boolean
	return WEATHER[kind] ~= nil
end

-- rates: the kinds to switch on and their particles per second, ALREADY capped by the caller.
function CavernArt:updateWeather(rates: { [string]: number })
	if self.origin == nil then return end
	for kind, rate in rates do
		local w = self.weather[kind]
		if w == nil and WEATHER[kind] and self.layout.emitters[kind] then
			local spec = self.layout.emitters[kind]
			local host = newPart("Weather_" .. kind, "Block", v3(spec.size), Color3.new(1, 1, 1), 1, "SmoothPlastic")
			host.CFrame = CFrame.new((self.origin :: Vector3) + v3(spec.position))
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "GrottoWeather"
			pe.Color = ColorSequence.new(c3(spec.color))
			pe.Rate = rate
			WEATHER[kind](pe)
			pe.Parent = host
			host.Parent = self.folder
			w = { host = host, emitter = pe, rate = rate }
			self.weather[kind] = w
		end
		if w then
			if not w.emitter.Enabled then w.emitter.Enabled = true end
			if math.abs(w.rate - rate) > 0.05 then
				w.emitter.Rate = rate
				w.rate = rate
			end
		end
	end
	for kind, w in self.weather do
		if rates[kind] == nil and w.emitter.Enabled then
			w.emitter.Enabled = false
		end
	end
end

--============================================================================ visitors (rare, harmless)

local FLOCK = { batSwoop = { kind = "bat", n = 6 }, mothSwirl = { kind = "moth", n = 10 } }

function CavernArt:startVisitor(kind: string)
	if self.origin == nil or FLOCK[kind] == nil then return end
	local v = self.visitors[kind]
	if v == nil then
		v = { members = {} }
		local f = FLOCK[kind]
		for j = 1, f.n do
			local c = self:_newCritter(f.kind)
			c.phase = j * 1.7
			c.lag = (j - 1) * 0.035 -- the flock strings out along the route
			c.side = ((j % 3) - 1) * 2.2
			c.lift = ((j % 2) * 2 - 1) * 1.1
			table.insert(v.members, c)
		end
		self.visitors[kind] = v
	end
	v.active = true
	for _, c in v.members do
		for _, p in c.parts do p.Parent = self.folder end
	end
end

-- u: 0..1 along the flight. The flock enters down the light shaft and leaves up it (Grotto.layout).
function CavernArt:updateVisitor(kind: string, u: number, now: number)
	local v = self.visitors[kind]
	if v == nil or not v.active then return end
	local route = self.layout.routes[kind]
	local origin = self.origin :: Vector3
	for _, c in v.members do
		local uj = math.clamp(u - c.lag, 0, 1)
		local a = self.Grotto.routePoint(route, uj)
		local b = self.Grotto.routePoint(route, math.min(1, uj + 0.01))
		local pos = origin + v3(a)
		local ahead = origin + v3(b)
		local dir = ahead - pos
		if dir.Magnitude < 1e-3 then dir = Vector3.new(0, 1, 0) end
		local frame = CFrame.lookAt(pos, pos + dir)
		local offset
		if c.kind == "moth" then
			-- a swirl around the route
			local ang = now * 5 + c.phase
			offset = frame.RightVector * math.cos(ang) * 2 + frame.UpVector * math.sin(ang) * 2
		else
			offset = frame.RightVector * c.side + frame.UpVector * c.lift
		end
		c.pos = pos + offset
		c.heading = math.atan2(dir.X, dir.Z)
		place(c, now)
		-- fade in over the first and out over the last 8 % (they are in the shaft there anyway)
		local edge = math.clamp(math.min(uj, 1 - uj) / 0.08, 0, 1)
		local base = if c.kind == "bat" then 0 else CRITTER_LOOK[c.kind].transparency
		for _, p in c.parts do setTransparency(p, 1 - (1 - base) * edge) end
	end
end

function CavernArt:endVisitor(kind: string)
	local v = self.visitors[kind]
	if v == nil then return end
	v.active = false
	for _, c in v.members do
		for _, p in c.parts do p.Parent = nil end
	end
end

--============================================================================ harvest bursts

local SHARD_LIFE = 1.1
local RING_LIFE = 0.7
local BEAM_LIFE = 2.5

-- pos: the top of the harvested socket's plate, in world space. rule: Grotto.burst(tier, ...).
function CavernArt:burst(pos: Vector3, rule: any, color: Color3, now: number)
	local r = self.rand
	local n = math.min(rule.shards or 0, self.Config.Budget.MaxShards)
	for i = 1, n do
		local s = self.shards[i]
		if s == nil then
			s = { part = newPart("Shard", "Block", Vector3.new(0.35, 0.9, 0.35), color, 1) }
			self.shards[i] = s
		end
		local a = r() * math.pi * 2
		local out = 5 + r() * 6
		s.pos = pos + Vector3.new(0, 1 + r() * 2, 0)
		s.vel = Vector3.new(math.cos(a) * out, 10 + r() * 7, math.sin(a) * out)
		s.spin = Vector3.new(r() * 8 - 4, r() * 8 - 4, r() * 8 - 4)
		s.t0 = now
		s.part.Color = color
		s.part.Transparency = 0.1
		s.part.Parent = self.folder
	end
	if rule.ring then
		if self.ring == nil then
			self.ring = { part = newPart("HarvestRing", "Cylinder", Vector3.new(0.2, 2, 2), color, 1) }
		end
		self.ring.t0 = now
		self.ring.pos = pos + Vector3.new(0, 0.15, 0)
		self.ring.part.Color = color
		self.ring.part.Parent = self.folder
	end
	if rule.beam then
		if self.beam == nil then
			local core = newPart("BeamCore", "Cylinder", Vector3.new(1, 1.6, 1.6), Color3.new(1, 1, 1), 1)
			local halo = newPart("BeamHalo", "Cylinder", Vector3.new(1, 4.5, 4.5), color, 1)
			local light = Instance.new("PointLight")
			light.Name = "BeamLight"
			light.Range = 30
			light.Shadows = false
			light.Brightness = 0
			light.Parent = core
			self.beam = { core = core, halo = halo, light = light }
		end
		local b = self.beam
		local top = (self.origin :: Vector3).Y + self.Cavern.Const.CEIL_UNDER
		b.len = math.max(4, top - pos.Y)
		b.base = pos
		b.t0 = now
		b.halo.Color = color
		b.light.Color = color
		b.core.Color = Color3.new(1, 1, 1):Lerp(color, 0.35)
		b.core.Parent = self.folder
		b.halo.Parent = self.folder
	end
end

function CavernArt:updateBursts(dt: number, now: number)
	for _, s in self.shards do
		if s.part.Parent ~= nil then
			local age = now - s.t0
			if age >= SHARD_LIFE then
				s.part.Parent = nil
			else
				s.vel += Vector3.new(0, -40 * dt, 0)
				s.pos += s.vel * dt
				s.part.CFrame = CFrame.new(s.pos) * CFrame.Angles(s.spin.X * age, s.spin.Y * age, s.spin.Z * age)
				setTransparency(s.part, 0.1 + 0.9 * (age / SHARD_LIFE) ^ 2)
			end
		end
	end
	local ring = self.ring
	if ring and ring.part.Parent ~= nil then
		local age = now - ring.t0
		if age >= RING_LIFE then
			ring.part.Parent = nil
		else
			local k = age / RING_LIFE
			local d = 2 + 9 * k
			ring.part.Size = Vector3.new(0.2, d, d)
			ring.part.CFrame = CFrame.new(ring.pos) * CFrame.Angles(0, 0, math.pi / 2)
			setTransparency(ring.part, 0.2 + 0.8 * k)
		end
	end
	local b = self.beam
	if b and b.core.Parent ~= nil then
		local age = now - b.t0
		if age >= BEAM_LIFE then
			b.core.Parent = nil
			b.halo.Parent = nil
			b.light.Brightness = 0
		else
			local grow = math.clamp(age / 0.2, 0, 1)
			local fade = math.clamp((age - 0.6) / (BEAM_LIFE - 0.6), 0, 1)
			local cf = CFrame.new(b.base + Vector3.new(0, b.len / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			b.core.Size = Vector3.new(b.len, 1.6 * grow + 0.05, 1.6 * grow + 0.05)
			b.halo.Size = Vector3.new(b.len, 4.5 * grow + 0.05, 4.5 * grow + 0.05)
			b.core.CFrame = cf
			b.halo.CFrame = cf
			setTransparency(b.core, 0.15 + 0.85 * fade)
			setTransparency(b.halo, 0.7 + 0.3 * fade)
			b.light.Brightness = 3 * (1 - fade)
		end
	end
end

return CavernArt
