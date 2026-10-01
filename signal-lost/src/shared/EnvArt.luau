-- EnvArt.luau — the CLIENT's art for SIGNAL LOST (DESIGN.md §4, §17): the exterior (planet, the Main Array's dish,
-- the relay beacons, what crosses the sky), the dressing on built modules, the weather, the interior critters and
-- the hazard's debris and ring. Called only by src/client/Env.client.luau; everything it makes lives in one local
-- folder (workspace.SignalEnvLocal) on this client and never replicates. It creates NO light source (glow is Neon),
-- fires no remote, sets no attribute. Every Part is anchored, non-collidable, non-queryable, non-touchable.

local EnvArt = {}
EnvArt.__index = EnvArt

local function c3(t: { number }): Color3
	return Color3.fromRGB(math.clamp(math.floor(t[1] + 0.5), 0, 255), math.clamp(math.floor(t[2] + 0.5), 0, 255),
		math.clamp(math.floor(t[3] + 0.5), 0, 255))
end
EnvArt.c3 = c3

local MATERIALS = {
	Metal = Enum.Material.Metal, SmoothPlastic = Enum.Material.SmoothPlastic, Fabric = Enum.Material.Fabric,
	Neon = Enum.Material.Neon, Grass = Enum.Material.Grass, Wood = Enum.Material.Wood, Ice = Enum.Material.Ice,
	Snow = Enum.Material.Snow, Glass = Enum.Material.Glass,
}

local function ghost(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function newPart(name: string, parent: Instance, size: Vector3, color: Color3, material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	ghost(p)
	p.Parent = parent
	return p
end

function EnvArt.new(root: Instance, cfg: any, Dressing: any): any
	local self = setmetatable({
		cfg = cfg,
		Dressing = Dressing,
		root = root,
		exterior = Instance.new("Folder"),
		dressing = Instance.new("Folder"),
		weather = Instance.new("Folder"),
		critters = Instance.new("Folder"),
		hazard = Instance.new("Folder"),
		ext = {},
		weatherHosts = {},
		critterParts = {},
		hz = nil,
	}, EnvArt)
	for name, f in { Exterior = self.exterior, Dressing = self.dressing, Weather = self.weather, Critters = self.critters, Hazard = self.hazard } do
		f.Name = name
		f.Parent = root
	end
	return self
end

--============================================================================ the exterior

-- WHERE the exterior stands, so that the only two openings actually SHOW it (measured on the real window and glass
-- parts by robloxemu/check_signallost_env.luau; EYECANDY.md §2.3). The first placement put the planet 37 degrees up
-- and the beacons about 30 degrees up: the benches, which face the window, saw none of it, and no vacuum module's glass
-- ever showed a single beacon.
--   hub:    beyond the lifeboat's north window, LOW. The window is 8 studs tall and 38 wide, so from the benches it
--           shows only elevations -1.5 to 10.4 degrees and azimuths -1.5 to 35 (from +Z toward +X). The planet's limb
--           fills the bottom of the window, the 30 beacons arc just above it, the dish stands to the right.
--   sector: OVERHEAD, anchored to the character. A vacuum module's 16 x 16 glass pane, 13.3 studs above the eye, shows
--           only sky within about 30 degrees of the zenith, so the planet, the dish and the beacon ring sit near it, and
--           follow the player so every module's glass shows the same sky.
-- Directions are (azimuth from +Z toward +X, elevation, distance) from `eye` (relative to the anchor): in the hub the
-- first bench's seated eye; in a sector the character's floor point. Sizes stay under 2048 studs (what the engine
-- draws as written).
local LAYOUT = {
	hub = {
		eye = Vector3.new(-8, 5, -17.5),
		planet = { az = 17, el = -14, d = 2400, r = 742 },
		dish = { az = 29, el = 0.5, d = 600, mul = 2 },
		beacons = { az0 = 1, az1 = 22, el = 6.6, wave = 1, d = 700, size = 6 },
		crossers = { from = Vector3.new(-700, 60, 1000), to = Vector3.new(900, 90, 1100), step = Vector3.new(0, 25, 80) },
	},
	sector = {
		eye = Vector3.new(0, 0, 0),
		planet = { az = 0, el = 78, d = 2400, r = 899 },
		dish = { az = 180, el = 80, d = 520, mul = 2.5 },
		beacons = { ring = 13, d = 560, size = 6 },
		crossers = { from = Vector3.new(-320, 480, -60), to = Vector3.new(320, 500, 60), step = Vector3.new(0, 30, 40) },
	},
}
EnvArt.LAYOUT = LAYOUT

local function dirOf(az: number, el: number): Vector3
	local a, e = math.rad(az), math.rad(el)
	return Vector3.new(math.cos(e) * math.sin(a), math.sin(e), math.cos(e) * math.cos(a))
end

function EnvArt:buildExterior()
	local f = self.exterior
	local e = self.ext
	e.planet = newPart("Planet", f, Vector3.new(2000, 2000, 2000), Color3.fromRGB(70, 130, 220), Enum.Material.SmoothPlastic)
	e.planet.Shape = Enum.PartType.Ball
	e.atmos = newPart("Atmosphere", f, Vector3.new(2040, 2040, 2040), Color3.fromRGB(200, 225, 255), Enum.Material.Neon)
	e.atmos.Shape = Enum.PartType.Ball
	e.atmos.Transparency = 0.82
	-- the Main Array's dish: 8 parts
	e.dish = {}
	for _, spec in {
		{ "DishBase", Vector3.new(10, 4, 10) }, { "DishMast", Vector3.new(3, 26, 3) }, { "DishBowl", Vector3.new(4, 44, 44) },
		{ "DishRim", Vector3.new(1.5, 48, 48) }, { "DishArmA", Vector3.new(1, 1, 24) }, { "DishArmB", Vector3.new(1, 1, 24) },
		{ "DishFeed", Vector3.new(3, 3, 3) }, { "DishLamp", Vector3.new(2, 2, 2) },
	} do
		local p = newPart(spec[1], f, spec[2], Color3.fromRGB(190, 196, 210), Enum.Material.Metal)
		if spec[1] == "DishBowl" or spec[1] == "DishRim" then p.Shape = Enum.PartType.Cylinder end
		e.dish[spec[1]] = { part = p, base = spec[2] }
	end
	e.dish.DishLamp.part.Material = Enum.Material.Neon
	e.dish.DishLamp.part.Color = Color3.fromRGB(80, 90, 110)
	-- 30 relay beacons along the hull, one lit per relay restored
	e.beacons = {}
	for i = 1, 30 do
		local b = newPart("Beacon" .. i, f, Vector3.new(3, 3, 3), Color3.fromRGB(40, 46, 58), Enum.Material.SmoothPlastic)
		b.Shape = Enum.PartType.Ball
		e.beacons[i] = b
	end
	-- the brag's beam, hidden until the Main Array fires
	e.beam = newPart("Beam", f, Vector3.new(6, 6, 900), Color3.fromRGB(190, 240, 255), Enum.Material.Neon)
	e.beam.Transparency = 1
	-- what crosses the sky (satellites, meteors, dark shapes): never near a module
	e.crossers = {}
	for i = 1, self.cfg.Budget.MaxCritters do
		local p = newPart("Crosser" .. i, f, Vector3.new(6, 3, 10), Color3.fromRGB(200, 205, 220), Enum.Material.Metal)
		p.Transparency = 1
		e.crossers[i] = p
	end
	self.anchor = Vector3.new(0, 0, 0)
	self:placeExterior(self.anchor, 0.5)
end

function EnvArt:exteriorCount(): number
	local n = 0
	for _, d in self.exterior:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

-- dishScale: 0.3 .. 1, the dish growing in the viewports through the Array Spine. where: "hub" | "sector" (LAYOUT).
function EnvArt:placeExterior(anchor: Vector3, dishScale: number, where: string?)
	local e = self.ext
	self.anchor = anchor
	self.where = where or self.where or "hub"
	local L = LAYOUT[self.where] or LAYOUT.hub
	local ref = anchor + L.eye
	local pc = ref + dirOf(L.planet.az, L.planet.el) * L.planet.d
	local pd = 2 * L.planet.r
	e.planet.Size = Vector3.new(pd, pd, pd)
	e.planet.CFrame = CFrame.new(pc)
	e.atmos.Size = Vector3.new(pd, pd, pd) * 1.02
	e.atmos.CFrame = CFrame.new(pc)
	self.planetCentre = pc
	local d = ref + dirOf(L.dish.az, L.dish.el) * L.dish.d
	local s = math.clamp(dishScale, 0.2, 1) * L.dish.mul
	local function put(name: string, offset: Vector3, rot: CFrame?)
		local rec = e.dish[name]
		rec.part.Size = rec.base * s
		rec.part.CFrame = CFrame.new(d + offset * s) * (rot or CFrame.new())
	end
	local tilt = CFrame.Angles(0, 0, math.rad(if self.swing then 90 - 55 * self.swing else 90))
	put("DishBase", Vector3.new(0, 0, 0))
	put("DishMast", Vector3.new(0, 15, 0))
	put("DishBowl", Vector3.new(0, 30, 0), tilt)
	put("DishRim", Vector3.new(0, 31.5, 0), tilt)
	put("DishArmA", Vector3.new(0, 38, 6), CFrame.Angles(math.rad(40), 0, 0))
	put("DishArmB", Vector3.new(0, 38, -6), CFrame.Angles(math.rad(-40), 0, 0))
	put("DishFeed", Vector3.new(0, 46, 0))
	put("DishLamp", Vector3.new(0, 49, 0))
	local B = L.beacons
	local n = #e.beacons
	for i, b in e.beacons do
		b.Size = Vector3.new(B.size, B.size, B.size)
		if B.ring then
			-- a ring around the zenith
			local a = 2 * math.pi * (i - 1) / n
			local r, up = math.sin(math.rad(B.ring)) * B.d, math.cos(math.rad(B.ring)) * B.d
			b.CFrame = CFrame.new(ref + Vector3.new(r * math.cos(a), up, r * math.sin(a)))
		else
			-- an arc along the hull, just above the planet's limb
			local u = (i - 1) / math.max(1, n - 1)
			local az = B.az0 + (B.az1 - B.az0) * u
			local el = B.el + B.wave * math.sin(math.pi * u)
			b.CFrame = CFrame.new(ref + dirOf(az, el) * B.d)
		end
	end
	e.beam.CFrame = CFrame.lookAt(d + Vector3.new(0, 46 * s, 0), pc) * CFrame.new(0, 0, -450)
end

-- ex = the blended exterior of the band (planet, rim colours), lit beacons, the dish lit once the Main Array is.
function EnvArt:updateExterior(t: number, ex: any, phase: string, best: number, arrayDone: boolean)
	local e = self.ext
	if ex.planet then e.planet.Color = c3(ex.planet) end
	if ex.rim then e.atmos.Color = c3(ex.rim) end
	-- the Echo: the planet is gone behind you, a violet nebula in its place
	local gone = phase == "nebula"
	e.planet.Transparency = if gone then 1 else 0
	e.atmos.Transparency = if gone then 0.6 else 0.82
	local lit = math.clamp(math.floor(best), 0, #e.beacons)
	for i, b in e.beacons do
		local on = i <= lit
		b.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		b.Color = if on then Color3.fromRGB(170, 190, 255) else Color3.fromRGB(40, 46, 58)
	end
	e.dish.DishLamp.part.Color = if arrayDone then Color3.fromRGB(200, 245, 255) else Color3.fromRGB(80, 90, 110)
	-- the brag's beam fades out after its six seconds
	if self.beamUntil then
		local left = self.beamUntil - t
		e.beam.Transparency = if left > 0 then 0.25 + 0.75 * math.clamp(1 - left / 6, 0, 1) else 1
		if left <= 0 then self.beamUntil = nil; self.swing = nil end
	end
end

-- The Main Array fires (§7.1): the dish swings toward the planet, a beam fires, the beacons light in sequence.
function EnvArt:brag(t: number)
	self.beamUntil = t + 6
	self.swing = 1
	self:placeExterior(self.anchor, 1, self.where)
end

-- Exterior critters: a few things crossing the sky far outside, never toward a module (§4.3). spec = the band's
-- critters when they live `outside`.
function EnvArt:updateCrossers(t: number, spec: any?)
	for i, p in self.ext.crossers do
		if spec and spec.where == "outside" then
			local period = 40 + i * 17
			local u = ((t / period) + i * 0.37) % 1
			-- across what the openings show: the window's band of sky in the hub, the zenith in a sector
			local C = (LAYOUT[self.where or "hub"] or LAYOUT.hub).crossers
			local a = self.anchor
			local start = a + C.from + C.step * i
			local finish = a + C.to + C.step * i
			p.CFrame = CFrame.lookAt(start:Lerp(finish, u), finish)
			p.Color = c3(spec.color)
			p.Transparency = 0
		else
			p.Transparency = 1
		end
	end
end

--============================================================================ dressing

-- Recolour the server's module parts on this client with the band's palette (never brighter, §4.3).
function EnvArt:repaint(moduleFolder: Instance, palette: any)
	for _, c in moduleFolder:GetChildren() do
		if c:IsA("BasePart") then
			if c.Name == "Floor" then
				c.Color = c3(palette.floor)
			elseif string.sub(c.Name, 1, 4) == "Wall" then
				c.Color = c3(palette.wall)
			elseif string.sub(c.Name, 1, 7) == "Ceiling" then
				c.Color = c3(palette.trim)
			end
		end
	end
end

-- pieces from Dressing.build, placed around `origin` (the module's floor-top centre).
function EnvArt:dressModule(pieces: { any }, palette: any, key: string, origin: Vector3): any
	local f = Instance.new("Folder")
	f.Name = "Dress_" .. key
	local parts = {}
	for _, p in pieces do
		local col = if type(p.color) == "string" then palette[p.color] else p.color
		local part = newPart(p.name, f, Vector3.new(p.size[1], p.size[2], p.size[3]), c3(col), MATERIALS[p.material])
		part.CFrame = CFrame.new(origin + Vector3.new(p.pos[1], p.pos[2], p.pos[3]))
		table.insert(parts, part)
	end
	f.Parent = self.dressing
	return { folder = f, parts = parts, key = key, origin = origin, parented = true }
end

function EnvArt:setParented(rec: any, on: boolean)
	if rec.parented ~= on then
		rec.parented = on
		rec.folder.Parent = if on then self.dressing else nil
	end
end

function EnvArt:destroyModule(rec: any)
	rec.folder:Destroy()
end

--============================================================================ weather

-- rates = { [kind] = particles/s } already capped (EnvBands.capRates), specs = { [kind] = band.weather }. The hosts
-- fill the module the player is in (its interior box).
function EnvArt:setWeather(origin: Vector3?, rates: { [string]: number }, specs: { [string]: any })
	local want = {}
	if origin then
		for kind, rate in rates do want[kind] = rate end
	end
	for kind, host in self.weatherHosts do
		if not want[kind] then
			host:Destroy()
			self.weatherHosts[kind] = nil
		end
	end
	for kind, rate in want do
		local host = self.weatherHosts[kind]
		local spec = specs[kind]
		if not host and spec then
			host = newPart("Weather_" .. kind, self.weather, Vector3.new(28, 14, 28), Color3.new(1, 1, 1))
			host.Transparency = 1
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "Weather"
			pe.Lifetime = NumberRange.new(4, 8)
			pe.Speed = NumberRange.new(0.2, 0.8)
			pe.Rotation = NumberRange.new(0, 360)
			pe.RotSpeed = NumberRange.new(-20, 20)
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, spec.size),
				NumberSequenceKeypoint.new(1, 0) })
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.4),
				NumberSequenceKeypoint.new(1, 1) })
			pe.Color = ColorSequence.new(c3(spec.color))
			local selfLit = kind == "embers" or kind == "static" or kind == "violet"
			pe.LightEmission = if selfLit then 0.6 else 0
			pe.LightInfluence = if selfLit then 0 else 1 -- written: Roblox's default is 0 (facility trap 36)
			pe.Acceleration = if kind == "embers" then Vector3.new(0, 0.6, 0) else Vector3.new(0, -0.2, 0)
			pe.Parent = host
			self.weatherHosts[kind] = host
		end
		if host and origin then
			host.CFrame = CFrame.new(origin + Vector3.new(0, 8, 0))
			local pe = host:FindFirstChild("Weather")
			if pe then
				(pe :: any).Rate = rate
				;(pe :: any).Enabled = rate > 0
			end
		end
	end
end

--============================================================================ interior critters

-- Harmless things in the module the player is in: they never collide, cross above head height or along a wall,
-- and never move toward the player (they move ALONG a wall line). spec = the band's critters when not `outside`.
function EnvArt:updateCritters(t: number, origin: Vector3?, spec: any?, count: number)
	local inner = self.cfg.Station.CellSize / 2 - self.cfg.Station.WallThickness - 1.5
	for i = 1, self.cfg.Budget.MaxCritters do
		local p = self.critterParts[i]
		local on = origin ~= nil and spec ~= nil and i <= count
		if on and not p then
			p = newPart("Critter" .. i, self.critters, Vector3.new(0.8, 0.4, 0.8), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
			self.critterParts[i] = p
		end
		if p then
			if on then
				local side = (i - 1) % 4
				local u = math.sin(t * (0.25 + 0.07 * i) + i * 1.7) * (inner - 2)
				local y = 12 + 2 * math.sin(t * 0.9 + i)
				local lx, lz = u, inner
				if side == 1 then lx, lz = inner, u elseif side == 2 then lx, lz = u, -inner elseif side == 3 then lx, lz = -inner, u end
				p.CFrame = CFrame.new((origin :: Vector3) + Vector3.new(lx, y, lz)) * CFrame.Angles(t * 0.7, t * 0.5, 0)
				p.Color = c3(spec.color)
				p.Material = if spec.glow then Enum.Material.Neon else Enum.Material.Metal
				p.Transparency = 0
			else
				p.Transparency = 1
			end
		end
	end
end

--============================================================================ the hazard

local HAZARD_LOOK = {
	globe = { color = { 150, 200, 235 }, material = Enum.Material.Glass, shape = "Ball", size = 3.2 },
	crate = { color = { 130, 110, 80 }, material = Enum.Material.Wood, shape = "Block", size = 3 },
	slag = { color = { 200, 120, 255 }, material = Enum.Material.Neon, shape = "Ball", size = 2.8 },
	shard = { color = { 110, 120, 220 }, material = Enum.Material.Glass, shape = "Block", size = 3.2 },
	ice = { color = { 220, 235, 250 }, material = Enum.Material.Ice, shape = "Block", size = 3 },
	orb = { color = { 180, 110, 255 }, material = Enum.Material.Neon, shape = "Ball", size = 2.6 },
}
EnvArt.HAZARD_LOOK = HAZARD_LOOK

-- The debris and the red ring: the ring is EXACTLY the zone (Hazards.zone), drawn on the floor under the player.
function EnvArt:hazardShow(kind: string, zone: any, floorY: number)
	self:hazardHide()
	local look = HAZARD_LOOK[kind] or HAZARD_LOOK.crate
	local debris = newPart("Debris", self.hazard, Vector3.new(look.size, look.size, look.size), c3(look.color), look.material)
	if look.shape == "Ball" then debris.Shape = Enum.PartType.Ball end
	local ring = newPart("Ring", self.hazard, Vector3.new(0.2, zone.radius * 2, zone.radius * 2), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.35
	ring.CFrame = CFrame.new(zone.x, floorY + 0.12, zone.z) * CFrame.Angles(0, 0, math.rad(90))
	self.hz = { debris = debris, ring = ring, radius = zone.radius }
end

function EnvArt:hazardUpdate(pos: any, zone: any, floorY: number, locked: boolean, ringOn: boolean, t: number)
	local hz = self.hz
	if not hz then return end
	hz.debris.CFrame = CFrame.new(pos.x, pos.y, pos.z) * CFrame.Angles(t * 1.3, t * 0.9, t * 0.4)
	hz.ring.CFrame = CFrame.new(zone.x, floorY + 0.12, zone.z) * CFrame.Angles(0, 0, math.rad(90))
	hz.ring.Transparency = if ringOn then (if locked then 0.15 else 0.35 + 0.2 * math.sin(t * 10)) else 1
end

function EnvArt:hazardHide()
	if self.hz then
		self.hz.debris:Destroy()
		self.hz.ring:Destroy()
		self.hz = nil
	end
end

return EnvArt
