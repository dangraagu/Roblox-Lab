--!strict
-- BiomeArt.luau — builds what Biome.client shows. Client-only, code-only (no assets), pooled.
--
-- Every part made here is LOCAL (it never replicates), anchored, and non-collidable, non-queryable,
-- non-touchable, casts no shadow: it can never be stood on, block a monster's path (pathfinding is
-- server-side and never sees it), catch a touch, swallow a camera ray or hide anything behind a
-- shadow. Decor pieces are built from the pure data in Biomes.Pieces, so the geometry rules its
-- spec checks (no Neon, 3+ studs off the floor, at most 1.2 studs out of the face, a quarter of the
-- face at most) are exactly what gets built. Hazard models MAY glow: a warning is meaningful.

local BiomeArt = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
BiomeArt.rgb = rgb

-- A local, inert part.
local function inert(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end
BiomeArt.inert = inert

local function material(name: string): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and m then return m end
	return Enum.Material.SmoothPlastic
end

--------------------------------------------------------------------------- decor pieces

-- A pooled piece: { id, parts = { { part, prim } }, host = wall part?, face, key }
function BiomeArt.buildPiece(id: string, def: any, parent: Instance): any
	local parts = {}
	for _, prim in def.prims do
		local p: BasePart
		if prim.shape == "Wedge" or prim.shape == "WedgeDown" then
			p = Instance.new("WedgePart")
		else
			local part = Instance.new("Part")
			if prim.shape == "Ball" then
				part.Shape = Enum.PartType.Ball
			elseif prim.shape == "CylV" or prim.shape == "CylU" then
				part.Shape = Enum.PartType.Cylinder
			end
			p = part
		end
		inert(p)
		p.Name = "Decor_" .. id
		p.Material = material(prim.material)
		p.Color = rgb(prim.color)
		p.Transparency = 1
		local su, sv, sw = prim.size[1], prim.size[2], prim.size[3]
		if prim.shape == "Ball" then
			local s = math.max(su, sv, sw)
			p.Size = Vector3.new(s, s, s)
		elseif prim.shape == "CylV" then
			p.Size = Vector3.new(sv, su, sw) -- a Roblox cylinder's axis is X: turned upright below
		else
			p.Size = Vector3.new(su, sv, sw)
		end
		table.insert(parts, { part = p, prim = prim })
	end
	return { id = id, parts = parts, alpha = 0, parent = parent, parented = false }
end

-- Frame of face `face` (Biomes.FACES index) of an axis-aligned wall part: (centre of the face at
-- the wall's bottom, u axis, normal). u x up = normal, so CFrame.fromMatrix gets a right-handed basis.
local FACE_N = {
	Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
}
function BiomeArt.faceFrame(wall: BasePart, face: number): (Vector3, Vector3, Vector3)
	local n = FACE_N[face]
	local u = Vector3.new(n.Z, 0, -n.X)
	local pos = wall.Position
	local half = wall.Size.X / 2
	local bottom = pos.Y - wall.Size.Y / 2
	return Vector3.new(pos.X, bottom, pos.Z) + n * half, u, n
end

-- Put a piece on a wall face, `alpha` 0..1 (0 = invisible, 1 = its own transparency).
function BiomeArt.placePiece(piece: any, wall: BasePart, face: number, alpha: number)
	local origin, u, n = BiomeArt.faceFrame(wall, face)
	local up = Vector3.new(0, 1, 0)
	for _, e in piece.parts do
		local prim = e.prim
		local at = prim.at
		local pos = origin + u * at[1] + up * at[2] + n * at[3]
		local cf = CFrame.fromMatrix(pos, u, up, n)
		if prim.shape == "WedgeDown" then
			cf = cf * CFrame.Angles(math.pi, 0, 0)
		elseif prim.shape == "CylV" then
			cf = cf * CFrame.Angles(0, 0, math.pi / 2)
		end
		e.part.CFrame = cf
		local base = prim.transparency or 0
		e.part.Transparency = 1 - (1 - base) * math.clamp(alpha, 0, 1)
	end
	piece.alpha = alpha
end

function BiomeArt.setPieceParent(piece: any, on: boolean)
	if piece.parented == on then return end
	piece.parented = on
	for _, e in piece.parts do
		e.part.Parent = if on then piece.parent else nil
	end
end

--------------------------------------------------------------------------- air (particles)

-- One invisible box around the player; particles are born anywhere inside it.
function BiomeArt.airHost(parent: Instance): BasePart
	local p = Instance.new("Part")
	inert(p)
	p.Name = "BiomeAir"
	p.Transparency = 1
	p.Size = Vector3.new(34, 18, 34)
	p.Parent = parent
	return p
end

-- Enable/update the emitter for `kind` at `rate`; create it lazily. Rate 0 = off.
function BiomeArt.setAir(host: BasePart, emitters: { [string]: ParticleEmitter }, kind: string, def: any, rate: number)
	local e = emitters[kind]
	if e == nil then
		if rate <= 0 then return end
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Air_" .. kind
		pe.Color = ColorSequence.new(rgb(def.color))
		pe.LightEmission = def.lightEmission
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, def.size),
			NumberSequenceKeypoint.new(0.8, def.size),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, def.transparency),
			NumberSequenceKeypoint.new(0.75, def.transparency),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Lifetime = NumberRange.new(def.lifetime * 0.7, def.lifetime)
		pe.Speed = NumberRange.new(def.speed * 0.5, def.speed)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Acceleration = Vector3.new(0, def.rise, 0)
		pe.Drag = 0.5
		pe.Shape = Enum.ParticleEmitterShape.Box
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		pe.LockedToPart = false
		pe.Parent = host
		emitters[kind] = pe
		e = pe
	end
	local em = e :: ParticleEmitter
	em.Rate = math.max(0, rate)
	em.Enabled = rate > 0
end

--------------------------------------------------------------------------- hazards

-- The ring's colour is passed in (Biomes.Hazards.RingColor). It is NOT the trap's warning yellow: glowing
-- yellow on this floor means "this floor kills you in a moment", and a knock is not that (review fix).
local HOT = Color3.fromRGB(255, 120, 40)

local function part(parent: Instance?, name: string, shape: string?, size: Vector3, color: Color3, mat: Enum.Material, transparency: number?): BasePart
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		if shape == "Ball" then q.Shape = Enum.PartType.Ball end
		if shape == "Cylinder" then q.Shape = Enum.PartType.Cylinder end
		p = q
	end
	inert(p)
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

-- The falling object for each kind: a list of { part, offset CFrame from the object's centre }.
local function buildObject(kind: string): { any }
	local out = {}
	local function add(p: BasePart, off: CFrame)
		table.insert(out, { part = p, off = off, base = p.Transparency })
	end
	if kind == "icicle" then
		add(part(nil, "Icicle", "Wedge", Vector3.new(1.4, 4.2, 1.4), Color3.fromRGB(200, 232, 250), Enum.Material.Ice, 0.15), CFrame.Angles(math.pi, 0, 0))
		add(part(nil, "Icicle", "Wedge", Vector3.new(0.8, 2.6, 0.8), Color3.fromRGB(215, 240, 255), Enum.Material.Ice, 0.15), CFrame.new(0.9, 0.7, 0.3) * CFrame.Angles(math.pi, 0, 0))
		add(part(nil, "IcicleCore", "Wedge", Vector3.new(0.4, 2.8, 0.4), Color3.fromRGB(160, 225, 255), Enum.Material.Neon, 0.4), CFrame.new(0, 0.2, 0) * CFrame.Angles(math.pi, 0, 0))
	elseif kind == "lavabomb" then
		add(part(nil, "LavaBomb", "Ball", Vector3.new(2.2, 2.2, 2.2), Color3.fromRGB(60, 30, 25), Enum.Material.Basalt, 0), CFrame.new())
		add(part(nil, "LavaCore", "Ball", Vector3.new(1.7, 1.7, 1.7), HOT, Enum.Material.Neon, 0.1), CFrame.new(0.25, 0.2, 0.2))
	elseif kind == "shard" then
		add(part(nil, "Shard", "Wedge", Vector3.new(1.0, 4.0, 1.2), Color3.fromRGB(170, 220, 235), Enum.Material.Glass, 0.2), CFrame.Angles(math.pi, 0, 0))
		add(part(nil, "Shard", "Wedge", Vector3.new(0.7, 2.6, 0.8), Color3.fromRGB(200, 185, 240), Enum.Material.Glass, 0.2), CFrame.new(-0.7, 0.5, 0) * CFrame.Angles(math.pi, 0, 0.3))
		add(part(nil, "ShardCore", "Wedge", Vector3.new(0.3, 2.8, 0.3), Color3.fromRGB(220, 240, 255), Enum.Material.Neon, 0.45), CFrame.Angles(math.pi, 0, 0))
	elseif kind == "chandelier" then
		add(part(nil, "Hoop", "Cylinder", Vector3.new(0.3, 3.4, 3.4), Color3.fromRGB(70, 62, 50), Enum.Material.Metal, 0), CFrame.Angles(0, 0, math.pi / 2))
		for k = 0, 3 do
			local a = k * math.pi / 2
			local off = Vector3.new(math.cos(a) * 1.5, 0.5, math.sin(a) * 1.5)
			add(part(nil, "Candle", "Cylinder", Vector3.new(0.8, 0.3, 0.3), Color3.fromRGB(235, 228, 205), Enum.Material.SmoothPlastic, 0), CFrame.new(off) * CFrame.Angles(0, 0, math.pi / 2))
		end
		add(part(nil, "Flames", "Cylinder", Vector3.new(0.25, 3.3, 3.3), Color3.fromRGB(255, 210, 120), Enum.Material.Neon, 0.55), CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.pi / 2))
	elseif kind == "lightning" then
		add(part(nil, "StormPuff", "Ball", Vector3.new(4, 2.2, 4), Color3.fromRGB(70, 75, 95), Enum.Material.SmoothPlastic, 0.2), CFrame.new(0, 3, 0))
		add(part(nil, "Bolt", nil, Vector3.new(0.35, 7, 0.35), Color3.fromRGB(220, 235, 255), Enum.Material.Neon, 0), CFrame.new(0.5, -1, 0) * CFrame.Angles(0, 0, 0.25))
		add(part(nil, "Bolt", nil, Vector3.new(0.35, 7, 0.35), Color3.fromRGB(220, 235, 255), Enum.Material.Neon, 0), CFrame.new(-0.4, -7.5, 0) * CFrame.Angles(0, 0, -0.3))
		add(part(nil, "Bolt", nil, Vector3.new(0.35, 7, 0.35), Color3.fromRGB(220, 235, 255), Enum.Material.Neon, 0), CFrame.new(0.3, -14, 0) * CFrame.Angles(0, 0, 0.2))
	else -- meteor
		add(part(nil, "Meteor", "Ball", Vector3.new(2.4, 2.4, 2.4), Color3.fromRGB(70, 55, 90), Enum.Material.Basalt, 0), CFrame.new())
		add(part(nil, "MeteorGlow", "Ball", Vector3.new(1.9, 1.9, 1.9), Color3.fromRGB(230, 150, 255), Enum.Material.Neon, 0.15), CFrame.new(0, 0.35, 0))
	end
	return out
end

-- A pooled hazard view: disc (the danger zone, in `ringColor`), a darker inner disc (so it reads as a
-- ring), a growing shadow, and the object. `radius` = the zone radius the hit test uses.
function BiomeArt.buildHazardView(parent: Instance, radius: number, ringColor: Color3): any
	local d = radius * 2
	local ring = part(nil, "HazardRing", "Cylinder", Vector3.new(0.12, d, d), ringColor, Enum.Material.Neon, 0.35)
	local inner = part(nil, "HazardRingInner", "Cylinder", Vector3.new(0.14, d - 0.8, d - 0.8), Color3.fromRGB(20, 16, 10), Enum.Material.SmoothPlastic, 0.1)
	local shadow = part(nil, "HazardShadow", "Cylinder", Vector3.new(0.16, 1, 1), Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic, 0.35)
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "ImpactBurst"
	burst.Enabled = false
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.4, 0.9)
	burst.Speed = NumberRange.new(8, 16)
	burst.SpreadAngle = Vector2.new(70, 70)
	burst.Acceleration = Vector3.new(0, -30, 0)
	burst.Size = NumberSequence.new(0.35, 0)
	burst.LightEmission = 0.5
	burst.Parent = ring
	return { parent = parent, ring = ring, inner = inner, shadow = shadow, burst = burst, objects = {}, kind = nil, radius = radius, shown = false, ringColor = ringColor }
end

local BURST_COLOR = {
	icicle = Color3.fromRGB(225, 245, 255), lavabomb = HOT, shard = Color3.fromRGB(210, 230, 255),
	chandelier = Color3.fromRGB(255, 210, 120), lightning = Color3.fromRGB(220, 235, 255), meteor = Color3.fromRGB(230, 170, 255),
}

-- Hide a view (keeps its parts for reuse).
function BiomeArt.hideHazardView(v: any)
	if not v.shown then return end
	v.shown = false
	v.ring.Parent = nil
	v.inner.Parent = nil
	v.shadow.Parent = nil
	for _, o in v.objects do o.part.Parent = nil end
end

-- Draw hazard `kind` at `centre` (floor point, Vector3) in `state` ("warn" | "debris") with progress p.
-- `burstNow` = the impact just happened (emit the burst once).
function BiomeArt.showHazardView(v: any, kind: string, centre: Vector3, state: string, p: number, clock: number, burstNow: boolean)
	if v.kind ~= kind then
		for _, o in v.objects do o.part:Destroy() end
		v.objects = buildObject(kind)
		v.kind = kind
		v.burst.Color = ColorSequence.new(BURST_COLOR[kind] or v.ringColor)
	end
	if not v.shown then
		v.shown = true
		v.ring.Parent = v.parent
		v.inner.Parent = v.parent
		v.shadow.Parent = v.parent
		for _, o in v.objects do o.part.Parent = v.parent end
	end
	v.ring.CFrame = CFrame.new(centre + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	v.inner.CFrame = CFrame.new(centre + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local objY
	if state == "warn" then
		-- the ring pulses faster as the impact nears; the shadow grows to the zone's size
		local pulse = 0.5 + 0.5 * math.sin(clock * (6 + 14 * p))
		v.ring.Transparency = 0.15 + 0.35 * pulse
		v.inner.Transparency = 0.1
		local sd = math.max(0.5, v.radius * 2 * (0.25 + 0.75 * p))
		v.shadow.Size = Vector3.new(0.16, sd, sd)
		v.shadow.Transparency = 0.6 - 0.35 * p
		v.shadow.CFrame = CFrame.new(centre + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		-- the object hangs over the cell, shakes, and drops in the last 0.35 s of the warning
		local dropStart = 1 - 0.35 / 3
		if p < dropStart then
			local shake = 0.08 * p * math.sin(clock * 40)
			objY = 21 + shake
		else
			local q = (p - dropStart) / (1 - dropStart)
			objY = 21 - 19 * q * q
		end
	else
		v.ring.Transparency = 0.2 + 0.8 * p
		v.inner.Transparency = 0.1 + 0.9 * p
		v.shadow.Transparency = 1
		objY = 1.4 - 1.2 * p
	end
	for _, o in v.objects do
		local lightning = kind == "lightning"
		local visible = true
		if lightning and o.part.Name == "Bolt" then
			-- the bolt only exists for the instant of the strike and the first flicker after it
			visible = state == "debris" and p < 0.25
		end
		local y = if lightning then (if o.part.Name == "StormPuff" then 20 else 17) else objY
		o.part.CFrame = CFrame.new(centre + Vector3.new(0, y, 0)) * o.off
		if not visible then
			o.part.Transparency = 1
		elseif state == "debris" then
			o.part.Transparency = o.base + (1 - o.base) * p
		else
			o.part.Transparency = o.base
		end
	end
	if burstNow then
		-- Emit is a real ParticleEmitter method; pcall keeps a missing one (an emulator) from stopping a frame
		pcall(function() v.burst:Emit(18) end)
	end
end

return BiomeArt
