--!strict
-- DungeonArt.luau — the client's part factories for a revealed dungeon. ReplicatedStorage.
--
-- Everything here is built by the CLIENT, inside its own folder, from what the server has already
-- sent it (Cell payloads for revealed cells only). Nothing here knows a layout. All parts are
-- anchored; everything but walls is CanCollide = false and CanQuery = false, so no decoration, veil,
-- critter or fixture can block or be raycast. Dependencies (Config, Grid) are passed in.

local DungeonArt = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
DungeonArt.rgb = rgb

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: { number }, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = rgb(color)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	if props then
		for k, v in props do (p :: any)[k] = v end
	end
	p.Parent = parent
	return p
end
DungeonArt.part = mk

local function ghost(): { [string]: any }
	return { CanCollide = false, CanQuery = false, CanTouch = false }
end

-- world position of a lane-local point
function DungeonArt.world(origin: Vector3, x: number, y: number, z: number): Vector3
	return origin + Vector3.new(x, y, z)
end

-- An interior wall (collidable: the local character's physics is the client's anyway).
function DungeonArt.wall(parent: Instance, origin: Vector3, seg: any, cfg: any, color: { number }): BasePart
	local h = cfg.Grid.WallHeight
	local p = mk(parent, "Wall", Vector3.new(seg.sx, h, seg.sz), CFrame.new(origin + Vector3.new(seg.x, h / 2, seg.z)), color,
		{ Material = Enum.Material.Slate, CastShadow = true })
	return p
end

-- A veil: a matte black box filling an unrevealed cell, so a doorway always looks into darkness.
-- Uniform for every cell, so it carries no information.
function DungeonArt.veil(parent: Instance, origin: Vector3, cx: number, cy: number, cfg: any): BasePart
	local c, t, h = cfg.Grid.Cell, cfg.Grid.WallThick, cfg.Grid.WallHeight
	local p = mk(parent, "Veil", Vector3.new(c - t, h, c - t), CFrame.new(origin + Vector3.new(cx * c + c / 2, h / 2, cy * c + c / 2)),
		cfg.Colours.Veil, ghost())
	p.Material = Enum.Material.SmoothPlastic
	p:SetAttribute("Cell", cx .. "," .. cy)
	return p
end

-- A Seal: pedestal, gem, halo. The ONLY thing in the game that glows seal-gold.
function DungeonArt.seal(parent: Instance, origin: Vector3, cx: number, cy: number, cfg: any): Model
	local c = cfg.Grid.Cell
	local m = Instance.new("Model")
	m.Name = "Seal"
	local base = origin + Vector3.new(cx * c + c / 2, 0, cy * c + c / 2)
	mk(m, "Pedestal", Vector3.new(2.4, 2, 2.4), CFrame.new(base + Vector3.new(0, 1, 0)), { 80, 78, 90 }, ghost())
	local gem = mk(m, "Gem", Vector3.new(1.6, 1.6, 1.6), CFrame.new(base + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0.6, 0.6, 0),
		cfg.Colours.SealGold, ghost())
	gem.Material = Enum.Material.Neon
	local halo = mk(m, "Halo", Vector3.new(0.2, 4.2, 4.2), CFrame.new(base + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		cfg.Colours.SealGold, ghost())
	halo.Shape = Enum.PartType.Cylinder
	halo.Transparency = 0.7
	halo.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = rgb(cfg.Colours.SealGold)
	light.Range = 14
	light.Brightness = 1.4
	light.Parent = gem
	local em = Instance.new("ParticleEmitter")
	em.Name = "Sparkle"
	em.Color = ColorSequence.new(rgb(cfg.Colours.SealGold))
	em.Rate = 8
	em.Lifetime = NumberRange.new(0.8, 1.4)
	em.Speed = NumberRange.new(0.5, 1.5)
	em.LightEmission = 1
	em.Parent = gem
	m.PrimaryPart = gem
	m.Parent = parent
	return m
end

-- The Door: a frame of 3, the slab, 3 sockets and a glow plate (8 parts). Asleep until 3 seals.
function DungeonArt.door(parent: Instance, origin: Vector3, cx: number, cy: number, cfg: any): Model
	local c = cfg.Grid.Cell
	local m = Instance.new("Model")
	m.Name = "Door"
	local base = origin + Vector3.new(cx * c + c / 2, 0, cy * c + c / 2)
	local stone = { 96, 90, 104 }
	mk(m, "FrameW", Vector3.new(1.2, 11, 1.2), CFrame.new(base + Vector3.new(-3.6, 5.5, 0)), stone, ghost())
	mk(m, "FrameE", Vector3.new(1.2, 11, 1.2), CFrame.new(base + Vector3.new(3.6, 5.5, 0)), stone, ghost())
	mk(m, "FrameTop", Vector3.new(8.4, 1.2, 1.2), CFrame.new(base + Vector3.new(0, 11.4, 0)), stone, ghost())
	local slab = mk(m, "Slab", Vector3.new(6, 10.4, 0.6), CFrame.new(base + Vector3.new(0, 5.2, 0)), cfg.Colours.DoorAsleep, ghost())
	slab.Material = Enum.Material.Marble
	for k = 1, 3 do
		local s = mk(m, "Socket" .. k, Vector3.new(0.8, 0.8, 0.3), CFrame.new(base + Vector3.new(-1.6 + (k - 1) * 1.6, 8, -0.4)),
			{ 40, 38, 46 }, ghost())
		s:SetAttribute("Socket", k)
	end
	local plate = mk(m, "GlowPlate", Vector3.new(5, 9, 0.2), CFrame.new(base + Vector3.new(0, 5.2, -0.45)), cfg.Colours.DoorAwake, ghost())
	plate.Transparency = 1
	plate.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = rgb(cfg.Colours.DoorAwake)
	light.Range = 16
	light.Brightness = 0
	light.Parent = plate
	m.PrimaryPart = slab
	m.Parent = parent
	return m
end

-- Wake the Door (3 seals) or fill its sockets (seals so far).
function DungeonArt.setDoor(door: Model, seals: number, cfg: any)
	for k = 1, 3 do
		local s = door:FindFirstChild("Socket" .. k) :: BasePart?
		if s then
			s.Color = if k <= seals then rgb(cfg.Colours.DoorAwake) else Color3.fromRGB(40, 38, 46)
			s.Material = if k <= seals then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
	local plate = door:FindFirstChild("GlowPlate") :: BasePart?
	if plate then
		plate.Transparency = if seals >= 3 then 0.25 else 1
		local light = plate:FindFirstChild("Glow") :: PointLight?
		if light then light.Brightness = if seals >= 3 then 2 else 0 end
	end
	local slab = door:FindFirstChild("Slab") :: BasePart?
	if slab then slab.Color = if seals >= 3 then Color3.fromRGB(150, 140, 160) else rgb(cfg.Colours.DoorAsleep) end
end

-- A hazard: the fixture in the ceiling (cosmetic kind), the RED ring on the floor that is exactly
-- the hit zone, and the falling piece. The ring's radius is DoorHazards.ringRadius, never a look.
function DungeonArt.hazard(parent: Instance, origin: Vector3, cx: number, cy: number, kind: string, ringRadius: number, cfg: any): Model
	local c, h = cfg.Grid.Cell, cfg.Grid.WallHeight
	local m = Instance.new("Model")
	m.Name = "Hazard"
	local base = origin + Vector3.new(cx * c + c / 2, 0, cy * c + c / 2)
	local fixture = mk(m, "Fixture", Vector3.new(2, 2.4, 2), CFrame.new(base + Vector3.new(0, h - 1.4, 0)), { 120, 118, 128 }, ghost())
	fixture:SetAttribute("Kind", kind)
	local ring = mk(m, "Ring", Vector3.new(0.1, ringRadius * 2, ringRadius * 2),
		CFrame.new(base + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), cfg.Hazards.RingColor, ghost())
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Transparency = 1
	local rock = mk(m, "Falling", Vector3.new(1.6, 2.2, 1.6), CFrame.new(base + Vector3.new(0, h - 1.4, 0)), { 130, 126, 136 }, ghost())
	rock.Transparency = 1
	m.PrimaryPart = fixture
	m.Parent = parent
	return m
end

-- One decor piece standing `out` studs off a wall face.
function DungeonArt.decor(parent: Instance, pos: Vector3, normal: Vector3, piece: any): BasePart
	local size = if piece.kind == "column" then Vector3.new(1.2, 6, 1.2)
		elseif piece.kind == "chain" then Vector3.new(0.3, 4, 0.3)
		elseif piece.kind == "cobweb" or piece.kind == "moss" then Vector3.new(2.4, 2.4, 0.2)
		else Vector3.new(1.2, 1.2, 1.2)
	local p = mk(parent, "Decor", size, CFrame.lookAt(pos, pos + normal), piece.color, ghost())
	p.Material = if piece.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p:SetAttribute("Kind", piece.kind)
	return p
end

-- A critter: a small non-collidable body that drifts above head height.
function DungeonArt.critter(parent: Instance, pos: Vector3, band: any): BasePart
	local p = mk(parent, "Critter", Vector3.new(0.6, 0.3, 0.6), CFrame.new(pos), band.critter.color, ghost())
	if band.critter.kind == "firefly" or band.critter.kind == "fire sprite" or band.critter.kind == "moth" then
		p.Material = Enum.Material.Neon
	end
	p:SetAttribute("Kind", band.critter.kind)
	return p
end

-- A weather host: an invisible box over the player's head carrying one emitter.
function DungeonArt.weather(parent: Instance, name: string): (BasePart, ParticleEmitter)
	local p = mk(parent, "Weather_" .. name, Vector3.new(24, 1, 24), CFrame.new(0, -500, 0), { 0, 0, 0 }, ghost())
	p.Transparency = 1
	local em = Instance.new("ParticleEmitter")
	em.Name = "Weather"
	em.Rate = 0
	em.Enabled = false
	em.Lifetime = NumberRange.new(3, 5)
	em.Speed = NumberRange.new(0.2, 0.6)
	em.Size = NumberSequence.new(0.15)
	em.Parent = p
	return p, em
end

return DungeonArt
