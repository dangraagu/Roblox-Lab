-- SkyArt.luau - the client-side art of Disaster Rounds' sky: far scenery per band, critters, weather emitters and
-- the Lookout strays. Code-only (Parts, emitters, lights; no assets). CLIENT ONLY: everything here is built under a
-- folder the local script made, so it never replicates and never touches the server's world.
--
-- Budgets (Config.Budget, capped in code here and measured in robloxemu/check_disasterrounds_env.luau at every band,
-- every seam and every disaster): scenery Parts <= SceneryPartsPerPiece per piece (a band has at most two) and
-- <= SceneryParts in all, trimmed in updatePiece; critters <= Critters;
-- weather emitters <= WeatherEmitters (EnvBands.capRates); PointLights <= Lights; one stray at a time.
-- Nothing here is red except the stray's ring: red is the game's "it hits here" colour.

local SkyArt = {}
SkyArt.__index = SkyArt

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local CENTRE = Vector3.new(0, 0, 0) -- far scenery rings the island (the Lookout sits 74 studs west of it)

--============================================================================== construction

function SkyArt.new(folder: Instance, rand: () -> number, Config: any, EnvBands: any): any
	local self = setmetatable({
		folder = folder,
		rand = rand,
		Config = Config,
		EnvBands = EnvBands,
		pieces = {}, -- id -> { model, parts = { { part, base transparency } }, weight }
		critters = {}, -- list of { kind, model, vel }
		weather = {}, -- kind -> ParticleEmitter
		weatherHost = nil,
		stray = nil,
		strayRing = nil,
		lights = 0,
	}, SkyArt)
	local scenery = Instance.new("Folder")
	scenery.Name = "Scenery"
	scenery.Parent = folder
	self.scenery = scenery
	local life = Instance.new("Folder")
	life.Name = "Critters"
	life.Parent = folder
	self.life = life
	local host = Instance.new("Part")
	host.Name = "WeatherHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(120, 1, 120)
	host.Parent = folder
	self.weatherHost = host
	return self
end

local function mkPart(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- a point on the far ring at compass angle `deg` (0 = +X, the way the Lookout faces), `dist` studs out
local function far(deg: number, dist: number, y: number): Vector3
	local a = math.rad(deg)
	return CENTRE + Vector3.new(math.cos(a) * dist, y, math.sin(a) * dist)
end

--============================================================================== the pieces

local BUILDERS: { [string]: (any, Model) -> () } = {}

local function islet(self: any, m: Model, at: Vector3, r: number, sand: Color3)
	mkPart(m, { Name = "Islet", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 2 * r, 2 * r),
		CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Sand, Color = sand })
	mkPart(m, { Name = "Hill", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 1.2, r * 0.6, r * 1.2),
		Position = at + Vector3.new(0, 1.5, 0), Material = Enum.Material.Grass, Color = Color3.fromRGB(80, 150, 80) })
end
local function tree(m: Model, at: Vector3, h: number, lean: number, crown: Color3)
	mkPart(m, { Name = "Trunk", Size = Vector3.new(1.2, h, 1.2), CFrame = CFrame.new(at + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(lean)),
		Material = Enum.Material.Wood, Color = Color3.fromRGB(140, 104, 70) })
	mkPart(m, { Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.new(h * 0.8, h * 0.35, h * 0.8),
		Position = at + Vector3.new(math.sin(math.rad(-lean)) * h * 0.4, h, 0), Material = Enum.Material.Grass, Color = crown })
end

BUILDERS.palmIslets = function(self, m)
	for k, deg in { -30, 15, 55 } do
		local at = far(deg, 300 + k * 30, -1)
		islet(self, m, at, 14 + k * 3, Color3.fromRGB(236, 214, 160))
		tree(m, at + Vector3.new(3, 1, 2), 14, 10, Color3.fromRGB(60, 150, 70))
		tree(m, at + Vector3.new(-4, 1, -3), 11, -12, Color3.fromRGB(70, 160, 76))
	end
end
BUILDERS.sailboat = function(self, m)
	local at = far(-8, 260, 0)
	mkPart(m, { Name = "Hull", Size = Vector3.new(14, 3, 5), Position = at + Vector3.new(0, 0.5, 0), Material = Enum.Material.Wood, Color = Color3.fromRGB(120, 80, 50) })
	mkPart(m, { Name = "Mast", Size = Vector3.new(0.6, 14, 0.6), Position = at + Vector3.new(0, 9, 0), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 76, 50) })
	mkPart(m, { Name = "Sail", Size = Vector3.new(8, 11, 0.3), Position = at + Vector3.new(2, 9, 0), Material = Enum.Material.Fabric, Color = Color3.fromRGB(245, 240, 228) })
end
BUILDERS.lighthouse = function(self, m)
	local at = far(-40, 280, 0)
	mkPart(m, { Name = "Stack", Size = Vector3.new(26, 18, 22), Position = at + Vector3.new(0, 4, 0), Material = Enum.Material.Slate, Color = Color3.fromRGB(116, 110, 104) })
	for k = 0, 5 do
		local col = if k % 2 == 0 then Color3.fromRGB(245, 245, 245) else Color3.fromRGB(40, 70, 140)
		mkPart(m, { Name = "Tower" .. k, Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 7 - k * 0.4, 7 - k * 0.4),
			CFrame = CFrame.new(at + Vector3.new(0, 15.5 + k * 5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.SmoothPlastic, Color = col })
	end
	local lamp = mkPart(m, { Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = at + Vector3.new(0, 45, 0),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 240, 190) })
	if self.lights < self.Config.Budget.Lights then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 236, 180)
		l.Range = 40
		l.Brightness = 2
		l.Parent = lamp
		self.lights += 1
	end
end
BUILDERS.bentTrees = function(self, m)
	for k, deg in { 25, 70 } do
		local at = far(deg, 320 + k * 20, -1)
		islet(self, m, at, 16, Color3.fromRGB(214, 200, 150))
		for n = 1, 3 do tree(m, at + Vector3.new(n * 3 - 6, 1, n - 2), 10 + n, 25, Color3.fromRGB(70, 130, 76)) end
	end
end
BUILDERS.stormBank = function(self, m)
	for k = 0, 9 do
		local deg = -60 + k * 13
		mkPart(m, { Name = "Cloud" .. k, Shape = Enum.PartType.Ball, Size = Vector3.new(90, 40 + (k % 3) * 10, 70),
			Position = far(deg, 420, 70 + (k % 4) * 8), Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(70, 70, 92) })
	end
end
BUILDERS.shipwreck = function(self, m)
	local at = far(35, 270, -1)
	mkPart(m, { Name = "Reef", Size = Vector3.new(30, 3, 16), Position = at, Material = Enum.Material.Slate, Color = Color3.fromRGB(90, 86, 82) })
	mkPart(m, { Name = "Hull", Size = Vector3.new(22, 6, 7), CFrame = CFrame.new(at + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(18)),
		Material = Enum.Material.Wood, Color = Color3.fromRGB(96, 70, 50) })
	mkPart(m, { Name = "Mast", Size = Vector3.new(0.8, 16, 0.8), CFrame = CFrame.new(at + Vector3.new(2, 10, 0)) * CFrame.Angles(0, 0, math.rad(32)),
		Material = Enum.Material.Wood, Color = Color3.fromRGB(90, 66, 46) })
end
BUILDERS.volcano = function(self, m)
	local at = far(10, 400, -2)
	for k = 0, 5 do
		mkPart(m, { Name = "Cone" .. k, Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 150 - k * 22, 150 - k * 22),
			CFrame = CFrame.new(at + Vector3.new(0, 7 + k * 14, 0)) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Basalt,
			Color = Color3.fromRGB(60 + k * 4, 52 + k * 2, 50) })
	end
	local glow = mkPart(m, { Name = "LavaGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(26, 10, 26), Position = at + Vector3.new(0, 90, 0),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 150, 40) })
	if self.lights < self.Config.Budget.Lights then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 150, 60)
		l.Range = 60
		l.Brightness = 3
		l.Parent = glow
		self.lights += 1
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Rate = 4
	smoke.Lifetime = NumberRange.new(8, 12)
	smoke.Speed = NumberRange.new(8, 14)
	smoke.Size = NumberSequence.new(14, 40)
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 84, 80))
	smoke.Parent = glow
end
BUILDERS.comet = function(self, m)
	local at = far(-15, 440, 120)
	local head = mkPart(m, { Name = "CometHead", Shape = Enum.PartType.Ball, Size = Vector3.new(40, 40, 40), Position = at,
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 220, 160) })
	for k = 1, 8 do
		mkPart(m, { Name = "Tail" .. k, Shape = Enum.PartType.Ball, Size = Vector3.new(36 - k * 3, 30 - k * 3, 30 - k * 3),
			Position = at + Vector3.new(-k * 16, k * 9, k * 4), Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 200 - k * 8, 120 + k * 10), Transparency = 0.2 + k * 0.07 })
	end
	for k = 1, 4 do
		mkPart(m, { Name = "Crack" .. k, Size = Vector3.new(30, 1.2, 1.2), CFrame = CFrame.new(at) * CFrame.Angles(math.rad(k * 40), math.rad(k * 25), 0),
			Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 250, 220) })
	end
	if self.lights < self.Config.Budget.Lights then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 210, 150)
		l.Range = 60
		l.Brightness = 2
		l.Parent = head
		self.lights += 1
	end
end
BUILDERS.farMeteors = function(self, m)
	for k = 1, 6 do
		local streak = mkPart(m, { Name = "Streak" .. k, Size = Vector3.new(24, 0.8, 0.8), Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 230, 190), Position = far(-50 + k * 22, 430, 160 + k * 12) })
		streak:SetAttribute("Moving", true)
	end
end
BUILDERS.rainbow = function(self, m)
	-- no red stripe: red means danger in this game, so the arc starts at orange
	local cols = { { 255, 160, 60 }, { 255, 220, 80 }, { 120, 210, 110 }, { 90, 170, 240 }, { 120, 110, 220 }, { 170, 110, 200 } }
	local at = far(0, 430, -10)
	for b, c in cols do
		local r = 170 - b * 6
		for s = 0, 8 do
			local a = math.rad(s * 22.5)
			local pos = at + Vector3.new(0, math.sin(a) * r, math.cos(a) * r)
			mkPart(m, { Name = "Arc" .. b .. "_" .. s, Size = Vector3.new(2, 6, 70), CFrame = CFrame.new(pos) * CFrame.Angles(-a, 0, 0),
				Material = Enum.Material.Neon, Color = rgb(c), Transparency = 0.45 })
		end
	end
end
BUILDERS.flowerIslets = function(self, m)
	for k, deg in { -25, 30 } do
		local at = far(deg, 300 + k * 25, -1)
		islet(self, m, at, 15, Color3.fromRGB(236, 220, 170))
		for n = 1, 6 do
			local col = ({ { 255, 170, 220 }, { 255, 230, 120 }, { 250, 250, 250 } })[(n % 3) + 1]
			mkPart(m, { Name = "Flower" .. n, Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4),
				Position = at + Vector3.new(math.cos(n) * 7, 3, math.sin(n) * 7), Material = Enum.Material.Neon, Color = rgb(col) })
		end
	end
end

function SkyArt.hasPiece(id: string): boolean
	return BUILDERS[id] ~= nil
end

-- Fade a piece with its band weight; build it the first time it is needed, destroy it when it is gone so a band
-- nobody is in costs nothing.
function SkyArt.updatePiece(self: any, id: string, weight: number, now: number)
	local p = self.pieces[id]
	if weight <= 0.001 then
		if p then
			p.model:Destroy()
			if p.lights then self.lights -= p.lights end
			self.pieces[id] = nil
		end
		return
	end
	if p == nil then
		local builder = BUILDERS[id]
		if not builder then return end
		local m = Instance.new("Model")
		m.Name = id
		local lightsBefore = self.lights
		builder(self, m)
		-- budgets capped in code, not just measured (REVIEW-1 F11): a piece keeps at most SceneryPartsPerPiece Parts,
		-- and all the far scenery together at most SceneryParts; anything a builder made past that is never shown
		local B = self.Config.Budget
		local cap = math.min(B.SceneryPartsPerPiece or math.huge, math.max(0, (B.SceneryParts or math.huge) - SkyArt.sceneryParts(self)))
		local kept = 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Parent ~= nil then
				kept += 1
				if kept > cap then d:Destroy() end
			end
		end
		m.Parent = self.scenery
		local parts = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then table.insert(parts, { part = d, base = d.Transparency }) end
		end
		p = { model = m, parts = parts, weight = -1, lights = self.lights - lightsBefore }
		self.pieces[id] = p
	end
	if math.abs(p.weight - weight) > 0.02 then
		p.weight = weight
		for _, e in p.parts do
			e.part.Transparency = 1 - (1 - e.base) * weight
		end
	end
	-- far meteor streaks drift across the sky
	if id == "farMeteors" then
		for _, e in p.parts do
			local part = e.part
			part.CFrame = part.CFrame * CFrame.new(-0.9, -0.12, 0)
			if part.Position.Y < 60 then part.CFrame = part.CFrame + Vector3.new(120, 140, 0) end
		end
	end
	local _ = now
end

--============================================================================== critters

local CRITTER_LOOK: { [string]: { body: { number }, wing: { number }, size: number } } = {
	gull = { body = { 245, 245, 245 }, wing = { 200, 205, 215 }, size = 1.4 },
	albatross = { body = { 240, 240, 236 }, wing = { 80, 84, 92 }, size = 2.2 },
	petrel = { body = { 70, 70, 80 }, wing = { 50, 50, 60 }, size = 1.2 },
	bat = { body = { 50, 40, 46 }, wing = { 40, 32, 38 }, size = 1.2 },
	firebird = { body = { 255, 180, 70 }, wing = { 255, 220, 120 }, size = 2.0 },
	butterfly = { body = { 60, 50, 50 }, wing = { 255, 200, 230 }, size = 0.7 },
	dolphin = { body = { 120, 140, 160 }, wing = { 110, 128, 150 }, size = 2.6 },
}

function SkyArt.hasCritter(kind: string): boolean
	return CRITTER_LOOK[kind] ~= nil
end

local function buildCritter(self: any, kind: string): Model
	local look = CRITTER_LOOK[kind]
	local m = Instance.new("Model")
	m.Name = "Critter_" .. kind
	local s = look.size
	local glow = kind == "firebird" or kind == "butterfly"
	local body = mkPart(m, { Name = "Body", Size = Vector3.new(s * 1.6, s * 0.5, s * 0.5), Color = rgb(look.body),
		Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic })
	mkPart(m, { Name = "Wings", Size = Vector3.new(s * 0.6, s * 0.12, s * 3), Color = rgb(look.wing),
		Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic })
	m.PrimaryPart = body
	m.Parent = self.life
	return m
end

-- counts = { kind = n }; spawn up to the count (nearest first by construction: they are spawned around `centre`),
-- never more than Budget.Critters in all, move them, retire the ones that flew out of range.
function SkyArt.updateCritters(self: any, counts: { [string]: number }, centre: Vector3, dt: number, now: number)
	local cap = self.Config.Budget.Critters
	local specs = self.Config.Env.Critters
	local have: { [string]: number } = {}
	local keep = {}
	local c3 = { x = centre.X, y = centre.Y, z = centre.Z }
	for _, c in self.critters do
		local want = counts[c.kind] or 0
		have[c.kind] = (have[c.kind] or 0) + 1
		local pos = c.model.PrimaryPart.Position
		local p3 = { x = pos.X, y = pos.Y, z = pos.Z }
		if have[c.kind] > want or self.EnvBands.ambientExpired(p3, c3, specs[c.kind]) then
			c.model:Destroy()
			have[c.kind] -= 1
		else
			local np = pos + Vector3.new(c.vel.x, c.vel.y, c.vel.z) * dt
			local flap = math.sin(now * 8 + c.phase) * 0.4
			c.model:PivotTo(CFrame.lookAt(np, np + Vector3.new(c.vel.x, 0, c.vel.z) + Vector3.new(0, 0.001, 0)) * CFrame.Angles(flap, 0, 0))
			table.insert(keep, c)
		end
	end
	self.critters = keep
	for kind, n in counts do
		local spec = specs[kind]
		while spec and CRITTER_LOOK[kind] and (have[kind] or 0) < n and #self.critters < cap do
			local s = self.EnvBands.ambientSpawn(c3, spec, self.rand)
			local m = buildCritter(self, kind)
			m:PivotTo(CFrame.new(s.pos.x, s.pos.y, s.pos.z))
			table.insert(self.critters, { kind = kind, model = m, vel = s.vel, phase = self.rand() * 6 })
			have[kind] = (have[kind] or 0) + 1
		end
	end
end

function SkyArt.critterCount(self: any): number
	return #self.critters
end

--============================================================================== weather

local WEATHER: { [string]: { color: { number }, size: number, speed: number, light: boolean? } } = {
	spray = { color = { 230, 245, 250 }, size = 0.3, speed = 6 },
	wind = { color = { 240, 244, 250 }, size = 0.15, speed = 40 },
	drizzle = { color = { 180, 190, 214 }, size = 0.12, speed = 60 },
	ash = { color = { 90, 86, 84 }, size = 0.25, speed = 4 },
	sparks = { color = { 255, 200, 120 }, size = 0.2, speed = 10, light = true },
	pollen = { color = { 255, 240, 170 }, size = 0.18, speed = 2, light = true },
}

function SkyArt.hasWeather(kind: string): boolean
	return WEATHER[kind] ~= nil
end

-- rates = { kind = particles per second } as blended by band weight; capped with EnvBands.capRates.
function SkyArt.updateWeather(self: any, rates: { [string]: number }, centre: Vector3)
	local B = self.Config.Budget
	local on = self.EnvBands.capRates(rates, B.WeatherEmitters, B.MaxEmitterRate, 0.05)
	self.weatherHost.CFrame = CFrame.new(centre + Vector3.new(0, 30, 0))
	for kind, e in self.weather do
		if on[kind] == nil then
			e:Destroy()
			self.weather[kind] = nil
		end
	end
	for kind, rate in on do
		local e = self.weather[kind]
		if e == nil then
			local w = WEATHER[kind]
			if w then
				e = Instance.new("ParticleEmitter")
				e.Name = "Weather_" .. kind
				e.Color = ColorSequence.new(rgb(w.color))
				e.Size = NumberSequence.new(w.size)
				e.Speed = NumberRange.new(w.speed * 0.8, w.speed * 1.2)
				e.Lifetime = NumberRange.new(3, 5)
				e.EmissionDirection = Enum.NormalId.Bottom
				e.LightEmission = if w.light then 1 else 0
				e.Parent = self.weatherHost
				self.weather[kind] = e
			end
		end
		if e then e.Rate = rate end
	end
end

function SkyArt.weatherCount(self: any): number
	local n = 0
	for _ in self.weather do n += 1 end
	return n
end

--============================================================================== the Lookout stray (Hazards.luau)

local STRAY_LOOK: { [string]: { color: { number }, size: Vector3, neon: boolean } } = {
	ember = { color = { 255, 170, 60 }, size = Vector3.new(2, 2, 2), neon = true },
	spray = { color = { 200, 230, 255 }, size = Vector3.new(2.4, 2.4, 2.4), neon = false },
	plank = { color = { 150, 110, 70 }, size = Vector3.new(4, 0.6, 1.2), neon = false },
	pebble = { color = { 130, 124, 116 }, size = Vector3.new(1.8, 1.6, 1.8), neon = false },
}

-- zone = Hazards.zone(...) while the flight can still hit someone in the ring, else nil (the ring goes)
function SkyArt.showStray(self: any, plan: any, pos: any, now: number, zone: any, floorY: number)
	if self.stray == nil or self.stray.Name ~= "Stray_" .. plan.kind then
		self:hideStray()
		local look = STRAY_LOOK[plan.kind] or STRAY_LOOK.ember
		self.stray = mkPart(self.folder, { Name = "Stray_" .. plan.kind, Size = look.size, Color = rgb(look.color),
			Material = if look.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic })
	end
	self.stray.CFrame = CFrame.new(pos.x, pos.y, pos.z) * CFrame.Angles(now * 6, now * 4, 0)
	if zone then
		if self.strayRing == nil then
			self.strayRing = mkPart(self.folder, { Name = "StrayRing", Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.12, 2 * zone.radius, 2 * zone.radius), Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 40, 40), Transparency = 0.35 })
		end
		-- on the deck's top face (StormGrow REVIEW-1 F3: a ring at the wrong height is invisible)
		self.strayRing.CFrame = CFrame.new(zone.x, floorY + 0.08, zone.z) * CFrame.Angles(0, 0, math.rad(90))
		local pulse = 0.3 + 0.25 * math.abs(math.sin(now * 8))
		self.strayRing.Transparency = pulse
	elseif self.strayRing then
		self.strayRing:Destroy()
		self.strayRing = nil
	end
end

function SkyArt.hideStray(self: any)
	if self.stray then
		self.stray:Destroy()
		self.stray = nil
	end
	if self.strayRing then
		self.strayRing:Destroy()
		self.strayRing = nil
	end
end

--============================================================================== measurement

function SkyArt.sceneryParts(self: any): number
	local n = 0
	for _, d in self.scenery:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

return SkyArt
