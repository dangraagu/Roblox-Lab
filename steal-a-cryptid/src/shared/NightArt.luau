-- NightArt.luau - Steal a Cryptid's night, built in code (no assets). CLIENT ONLY: required by
-- src/client/Night.client.luau; the server never touches it. Pattern: +1 Jump's SkyArt.luau.
--
-- Everything here is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off (the camera never
-- pops in front of a pine, nothing can be stood on, touched or clicked), CastShadow off. Nothing is
-- built until a band first needs it, and anything whose weight falls to zero is UNPARENTED, so a band
-- you are not in costs no draw calls.
--
-- Three anchors:
--   "home"   world-fixed around the road (the far floor beyond its ravine, ridges, far pines, owls on the
--            server's pines, UFOs, Bigfoot);
--   "pocket" relative to the camp pocket the player is in (badlands, barrens, loch, redwoods). Every
--            part is checked against Night.keepOut when placed and on every animated frame: a part
--            that would enter the camp or the camera corridor behind its gate is left out;
--   "sky"    travels with the camera, like a skybox with depth (the auroras).
-- Because Poppercam ignores non-collidable parts, the camera is never pulled in front of one: so every
-- frame NightArt:occlude hides a home or pocket part that stands between the camera and the player (at
-- home) or the camp (in a pocket), and fades it back when it is clear. Camp scenery can never hide a net,
-- a snare or the raider, from any camera position (review 2026-09-24, finding 3).
--
-- Dependencies arrive as arguments (a bare `require("./X")` is invalid in Roblox):
--   NightArt.new(folder, rand, Config, EnvBands, Night)
-- Budgets are measured, not assumed: robloxemu/check_stealacryptid_night.luau counts what this module
-- has parented at every band, every camp and every seam against Config.Night.Budget.

local NightArt = {}
NightArt.__index = NightArt

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis is X; this stands it up
local FLOOR_TOP = -1.0 -- the camp floor's underside: a local part wholly below it can hide nothing

-- ─────────────────────────────────────────────────────────────── items: parts that fade together

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
			-- an entry left out to keep a camp clear (Night.keepOut) stays out
			if not e.hidden then e.part.Parent = folder end
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
		e.fp = nil -- its footprint moved (NightArt:occlude caches a static part's)
	end
end

local function addHost(item, offset)
	return addPart(item, { name = item.name .. "Host", size = Vector3.new(1, 1, 1), transparency = 1, offset = offset })
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

local function addEmitter(item, host, def, rate)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = def.name or "Fx"
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
	pe.Acceleration = def.Acceleration
	pe.SpreadAngle = Vector2.new(def.Spread or 180, def.Spread or 180)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rate = rate
	pe.Enabled = false
	pe.Parent = host
	table.insert(item.emitters, pe)
	return pe
end

-- The world-aligned half extents of a placed part (a rotated trunk's length is its height).
-- Used to keep camp scenery out of Night.keepOut.
local function extents(p)
	local cf, s = p.CFrame, p.Size
	local rx, uy, lz = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(rx.X) * s.X / 2 + math.abs(uy.X) * s.Y / 2 + math.abs(lz.X) * s.Z / 2
	local ey = math.abs(rx.Y) * s.X / 2 + math.abs(uy.Y) * s.Y / 2 + math.abs(lz.Y) * s.Z / 2
	local ez = math.abs(rx.Z) * s.X / 2 + math.abs(uy.Z) * s.Y / 2 + math.abs(lz.Z) * s.Z / 2
	return ex, ey, ez
end

-- ─────────────────────────────────────────────────────────────── pieces (static scenery)

local PIECES = {}

-- home: the forest floor past the server's Ground, to the fog - beyond a RAVINE round it. The Ground is the
-- only floor at home and past its edge is the void: the first night's one 2 048-stud floor, 1.1 studs under
-- the Ground's top, hid the edge and dropped players through the world (review 2026-09-24, finding 1). The
-- far floor is now four slabs framing a hole (Night.farGroundRects), with cliff faces on both sides of the
-- ravine: the BLUFF under the Ground (its top inside the Ground's slab, y -1.2..-0.2 in Main.server, its
-- sides 0.1 inside the Ground's edges, so it adds nothing to stand on) and a wall under the far rim.
-- No road known yet: one slab round the origin (rebuilt round the road when it is found: setHome).
PIECES.farGround = function(art)
	local item = newItem("FarGround")
	item.anchor = "home"
	item.world = true
	local R = art.cfg.Night.Ravine
	local rect = art.homeRect
	for _, s in art.Night.farGroundRects(rect, R) do
		addPart(item, { name = "FarGround", size = Vector3.new(s.sx, 1, s.sz), color = rgb(30, 42, 30), material = Enum.Material.Grass, offset = CFrame.new(s.cx, -1.8, s.cz) })
	end
	if rect then
		local rock = rgb(48, 42, 40)
		local d = R.Depth
		addPart(item, { name = "Bluff", size = Vector3.new(rect.sx - 0.2, d, rect.sz - 0.2), color = rock, material = Enum.Material.Slate,
			offset = CFrame.new(rect.cx, -1.1 - d / 2, rect.cz) })
		local hx, hz, t = rect.sx / 2 + R.Width, rect.sz / 2 + R.Width, 2
		local y = -1.4 - d / 2 -- under the far floor's inner edge (its top is y -1.3)
		addPart(item, { name = "RavineWall", size = Vector3.new(2 * (hx + t), d, t), color = rock, material = Enum.Material.Slate, offset = CFrame.new(rect.cx, y, rect.cz - hz - t / 2) })
		addPart(item, { name = "RavineWall", size = Vector3.new(2 * (hx + t), d, t), color = rock, material = Enum.Material.Slate, offset = CFrame.new(rect.cx, y, rect.cz + hz + t / 2) })
		addPart(item, { name = "RavineWall", size = Vector3.new(t, d, 2 * hz), color = rock, material = Enum.Material.Slate, offset = CFrame.new(rect.cx - hx - t / 2, y, rect.cz) })
		addPart(item, { name = "RavineWall", size = Vector3.new(t, d, 2 * hz), color = rock, material = Enum.Material.Slate, offset = CFrame.new(rect.cx + hx + t / 2, y, rect.cz) })
	end
	return item
end

-- The horizon (ridges, UFOs, Bigfoot) is placed around the road's centre at angle `a` (from +z toward +x)
-- and distance r0, then pushed straight out until a footprint of `radius` keeps OFF_ROAD studs off the
-- road's Ground. The road grows with Players.MaxPlayers (504 studs at 8 players, 2 520 at 50): a fixed ring
-- stood hills and Bigfoot on the lairs of a long road (check_stealacryptid_longroad.luau). The smallest
-- such distance is found by bisection, so it moves smoothly with `a` (Bigfoot walks).
local OFF_ROAD = 40
local function offRoad(rect, a, r0, radius)
	local ux, uz = math.sin(a), math.cos(a)
	if rect == nil then return ux * r0, uz * r0 end
	local need = radius + OFF_ROAD
	local function clear(r)
		local dx = math.max(math.abs(r * ux) - rect.sx / 2, 0)
		local dz = math.max(math.abs(r * uz) - rect.sz / 2, 0)
		return dx * dx + dz * dz >= need * need
	end
	if clear(r0) then return ux * r0, uz * r0 end
	local lo, hi = r0, r0 + rect.sx + rect.sz + need
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		if clear(mid) then hi = mid else lo = mid end
	end
	return ux * hi, uz * hi
end

-- home: a ring of dark hills on the horizon
PIECES.ridges = function(art)
	local item = newItem("Ridges")
	item.anchor = "home"
	local E = art.EnvBands
	for i = 1, 14 do
		local a = (i - 1) / 14 * math.pi * 2 + (E.hash01(i, 1, 0, 71) - 0.5) * 0.3
		local r = 820 + 180 * E.hash01(i, 2, 0, 71)
		local w = 420 + 200 * E.hash01(i, 3, 0, 71)
		local hgt = 240 + 160 * E.hash01(i, 4, 0, 71)
		-- radius: the corner of its footprint box (w x 0.8 w), whatever its turn
		local x, z = offRoad(art.homeRect, a, r, 0.65 * w)
		addPart(item, { name = "Ridge", shape = BALL, size = Vector3.new(w, hgt, w * 0.8), color = rgb(24, 28, 40), material = Enum.Material.Slate,
			offset = CFrame.new(x, -hgt * 0.22, z) * CFrame.Angles(0, a, 0) })
	end
	return item
end

-- home: pine silhouettes beyond the lairs (never on the Ground the lairs stand on, never over the ravine)
PIECES.farPines = function(art)
	local item = newItem("FarPines")
	item.anchor = "home"
	local E = art.EnvBands
	local rect = art.homeRect
	local margin = art.cfg.Night.Ravine.PineMargin
	local n, k = 0, 0
	while n < 24 and k < 400 do
		k += 1
		local a = E.hash01(k, 1, 0, 53) * math.pi * 2
		local r = 170 + 320 * E.hash01(k, 2, 0, 53)
		local x, z = math.sin(a) * r, math.cos(a) * r
		local inside = rect and math.abs(x) < rect.sx / 2 + margin and math.abs(z) < rect.sz / 2 + margin
		if not inside then
			n += 1
			local s = 0.8 + 0.6 * E.hash01(k, 3, 0, 53)
			addPart(item, { name = "FarPine", shape = BALL, size = Vector3.new(12, 34, 12) * s, color = rgb(18, 34, 26), material = Enum.Material.Grass,
				offset = CFrame.new(x, 15 * s, z) })
		end
	end
	return item
end

-- home: owls perched on the SERVER's pine crowns (read from the workspace), watching the camera
PIECES.owls = function(art)
	local item = newItem("Owls")
	item.anchor = "home"
	item.world = true
	local E = art.EnvBands
	local perches = art.perches or {}
	local picked = 0
	for i, top in perches do
		if picked >= 5 then break end
		if E.hash01(i, 7, 0, 91) < 0.35 or #perches - i < 5 - picked then
			picked += 1
			local base = CFrame.new(top + Vector3.new(0, 1.2, 0))
			addPart(item, { name = "Owl", shape = BALL, size = Vector3.new(1.8, 2.4, 1.8), color = rgb(96, 76, 58), material = Enum.Material.Fabric, offset = base })
			addPart(item, { name = "OwlEye", shape = BALL, size = Vector3.new(0.42, 0.42, 0.42), color = rgb(255, 214, 60), material = Enum.Material.Neon, offset = base * CFrame.new(-0.38, 0.5, -0.8) })
			addPart(item, { name = "OwlEye", shape = BALL, size = Vector3.new(0.42, 0.42, 0.42), color = rgb(255, 214, 60), material = Enum.Material.Neon, offset = base * CFrame.new(0.38, 0.5, -0.8) })
		end
	end
	-- turn to face the camera; blink now and then
	item.animate = function(it, _root, now, cam)
		for j = 1, #it.entries, 3 do
			local body = it.entries[j]
			local pos = body.offset.Position
			local look = Vector3.new(cam.X, pos.Y, cam.Z)
			local cf = if (look - pos).Magnitude > 0.1 then CFrame.lookAt(pos, look) else CFrame.new(pos)
			body.part.CFrame = cf
			local blink = math.floor(now * 0.9 + j) % 7 == 0
			for e = 1, 2 do
				local eye = it.entries[j + e]
				eye.part.CFrame = cf * CFrame.new(if e == 1 then -0.38 else 0.38, 0.5, -0.8)
				local t = if blink then 1 else eye.lastT
				if blink ~= (eye.blinking == true) then
					eye.part.Transparency = t
					eye.blinking = blink
				end
			end
		end
	end
	return item
end

local function aurora(name, colors, n)
	local item = newItem(name)
	item.anchor = "sky"
	local host = addHost(item, CFrame.new(0, 300, 620))
	for i = 1, n do
		local z = -120 + i * 110
		addBeam(item, host, Vector3.new(-760, 0, z), Vector3.new(760, 50 * i, z - 140), {
			color = colors[i], width0 = 150, width1 = 90, curve0 = 240 - i * 40, curve1 = -170 + i * 30,
			transparency = 0.4, segments = 24, faceCamera = false,
		})
	end
	return item
end

PIECES.auroraGreen = function()
	return aurora("AuroraGreen", {
		ColorSequence.new(rgb(90, 255, 170), rgb(120, 90, 255)),
		ColorSequence.new(rgb(70, 230, 200), rgb(90, 255, 140)),
		ColorSequence.new(rgb(150, 110, 255), rgb(80, 255, 200)),
	}, 3)
end

PIECES.auroraGold = function()
	return aurora("AuroraGold", {
		ColorSequence.new(rgb(255, 210, 110), rgb(255, 120, 190)),
		ColorSequence.new(rgb(255, 170, 90), rgb(190, 120, 255)),
	}, 2)
end

-- home: three saucers hovering over the far ridge, each with a pale tractor beam
PIECES.ufos = function(art)
	local item = newItem("Ufos")
	item.anchor = "home"
	item.saucers = {}
	for i = 1, 3 do
		local a = math.rad(35 + (i - 1) * 118)
		local r = 640 + i * 40
		-- radius: the corner of the rim's footprint box (50 x 50) plus its drift (60 x, 40 z)
		local x, z = offRoad(art.homeRect, a, r, 110)
		local centre = Vector3.new(x, 170 + i * 20, z)
		local disc = addPart(item, { name = "Ufo", shape = CYL, size = Vector3.new(5, 46, 46), color = rgb(150, 156, 170), material = Enum.Material.Metal, offset = CFrame.new(centre) * UPRIGHT })
		addPart(item, { name = "UfoDome", shape = BALL, size = Vector3.new(18, 11, 18), color = rgb(120, 255, 210), material = Enum.Material.Neon, transparency = 0.2, offset = CFrame.new(centre + Vector3.new(0, 4, 0)) })
		addPart(item, { name = "UfoRim", shape = CYL, size = Vector3.new(1.4, 50, 50), color = rgb(255, 230, 120), material = Enum.Material.Neon, transparency = 0.35, offset = CFrame.new(centre - Vector3.new(0, 1.6, 0)) * UPRIGHT })
		-- the beam hangs from the disc: attachments in the disc's own space (its X axis points up)
		addBeam(item, disc, Vector3.new(-1, 0, 0), Vector3.new(-(centre.Y + 60), 0, 0), {
			color = ColorSequence.new(rgb(190, 255, 220), rgb(120, 255, 190)), width0 = 16, width1 = 70,
			transparency = 0.55, segments = 8, faceCamera = true,
		})
		table.insert(item.saucers, { centre = centre, phase = i * 2.1 })
	end
	item.animate = function(it, root, now)
		for i, s in it.saucers do
			local drift = Vector3.new(math.sin(now * 0.07 + s.phase) * 60, math.sin(now * 0.6 + s.phase) * 4, math.cos(now * 0.05 + s.phase) * 40)
			local c = root * CFrame.new(s.centre + drift)
			local k = (i - 1) * 3
			it.entries[k + 1].part.CFrame = c * UPRIGHT * CFrame.Angles(now * 0.8, 0, 0)
			it.entries[k + 2].part.CFrame = c * CFrame.new(0, 4, 0)
			it.entries[k + 3].part.CFrame = c * CFrame.new(0, -1.6, 0) * UPRIGHT
		end
	end
	return item
end

-- home: Bigfoot himself, 90 studs tall, walking the far ridge (Mythic Night)
local function silhouette(item, prefix, scale, color)
	local s = scale
	addPart(item, { name = prefix .. "LegL", size = Vector3.new(3, 12, 3.4) * s, color = color, offset = CFrame.new(-2 * s, 6 * s, 0) })
	addPart(item, { name = prefix .. "LegR", size = Vector3.new(3, 12, 3.4) * s, color = color, offset = CFrame.new(2 * s, 6 * s, 0) })
	addPart(item, { name = prefix .. "Torso", size = Vector3.new(8, 11, 5) * s, color = color, offset = CFrame.new(0, 17 * s, 0) })
	addPart(item, { name = prefix .. "Head", shape = BALL, size = Vector3.new(5, 5.6, 5) * s, color = color, offset = CFrame.new(0, 24.6 * s, -0.6 * s) })
	addPart(item, { name = prefix .. "ArmL", size = Vector3.new(2.4, 12, 2.6) * s, color = color, offset = CFrame.new(-5.4 * s, 15 * s, 0) })
	addPart(item, { name = prefix .. "ArmR", size = Vector3.new(2.4, 12, 2.6) * s, color = color, offset = CFrame.new(5.4 * s, 15 * s, 0) })
end

local function walkAnimate(it, cf, now, s)
	local swing = math.sin(now * 1.6) * 0.35
	local e = it.entries
	e[1].part.CFrame = cf * CFrame.new(-2 * s, 12 * s, 0) * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -6 * s, 0)
	e[2].part.CFrame = cf * CFrame.new(2 * s, 12 * s, 0) * CFrame.Angles(-swing, 0, 0) * CFrame.new(0, -6 * s, 0)
	e[3].part.CFrame = cf * e[3].offset
	e[4].part.CFrame = cf * e[4].offset
	e[5].part.CFrame = cf * CFrame.new(-5.4 * s, 20 * s, 0) * CFrame.Angles(-swing * 0.8, 0, 0) * CFrame.new(0, -5 * s, 0)
	e[6].part.CFrame = cf * CFrame.new(5.4 * s, 20 * s, 0) * CFrame.Angles(swing * 0.8, 0, 0) * CFrame.new(0, -5 * s, 0)
end

PIECES.bigfoot = function(art)
	local item = newItem("Bigfoot")
	item.anchor = "home"
	silhouette(item, "Bigfoot_", 3.6, rgb(20, 16, 14))
	item.animate = function(it, root, now)
		local a = math.rad(160) + math.sin(now * 0.012) * 0.5
		local r = 700
		-- radius: his arms and swinging legs at 3.6 x (the corners of their boxes reach about 26 studs)
		local x, z = offRoad(art.homeRect, a, r, 35)
		local x2, z2 = offRoad(art.homeRect, a + 0.01, r, 35)
		local pos = Vector3.new(x, -1.3, z)
		local ahead = Vector3.new(x2, -1.3, z2)
		if math.cos(now * 0.012) < 0 then ahead = pos - (ahead - pos) end
		walkAnimate(it, root * CFrame.lookAt(pos, ahead), now, 3.6)
	end
	return item
end

-- camps: the ground under and around the pocket (below the camp floor, so it hides nothing)
local function campGround(name, color, material)
	return function(art)
		local item = newItem(name)
		item.anchor = "pocket"
		addPart(item, { name = name, size = Vector3.new(1600, 1, 1600), color = color, material = material, offset = CFrame.new(36, -1.8, 56) })
		return item
	end
end
PIECES.campSand = campGround("CampSand", rgb(150, 112, 78), Enum.Material.Sand)
PIECES.campNeedles = campGround("CampNeedles", rgb(64, 48, 36), Enum.Material.Ground)
PIECES.campShore = campGround("CampShore", rgb(70, 76, 64), Enum.Material.Pebble)
PIECES.campFerns = campGround("CampFerns", rgb(34, 58, 38), Enum.Material.Grass)

-- positions around the camp centre (36, 56), pocket-local; the keep-out guard drops anything too close
local CENTRE = Vector3.new(36, 0, 56)
local function around(E, i, seed, rMin, rMax, spread)
	local a = (E.hash01(i, 1, 0, seed) * 2 - 1) * spread
	local r = rMin + (rMax - rMin) * E.hash01(i, 2, 0, seed)
	return CENTRE + Vector3.new(math.sin(a) * r, 0, math.cos(a) * r), E.hash01(i, 3, 0, seed)
end

PIECES.mesas = function(art)
	local item = newItem("Mesas")
	item.anchor = "pocket"
	local E = art.EnvBands
	for i = 1, 9 do
		local p, h = around(E, i, 17, 260, 460, math.rad(115))
		local w, d, hgt = 70 + 80 * h, 60 + 70 * E.hash01(i, 4, 0, 17), 45 + 70 * E.hash01(i, 5, 0, 17)
		addPart(item, { name = "Mesa", size = Vector3.new(w, hgt, d), color = rgb(150, 84, 56), material = Enum.Material.Sandstone, offset = CFrame.new(p + Vector3.new(0, hgt / 2 - 2, 0)) * CFrame.Angles(0, h * 3, 0) })
		addPart(item, { name = "MesaCap", size = Vector3.new(w + 6, 4, d + 6), color = rgb(120, 66, 46), material = Enum.Material.Sandstone, offset = CFrame.new(p + Vector3.new(0, hgt - 1, 0)) * CFrame.Angles(0, h * 3, 0) })
	end
	return item
end

PIECES.cacti = function(art)
	local item = newItem("Cacti")
	item.anchor = "pocket"
	local E = art.EnvBands
	for i = 1, 8 do
		local p, h = around(E, i, 29, 75, 140, math.rad(150))
		local tall = 10 + 6 * h
		local green = rgb(58, 104, 60)
		addPart(item, { name = "Cactus", shape = CYL, size = Vector3.new(tall, 2.2, 2.2), color = green, material = Enum.Material.Grass, offset = CFrame.new(p + Vector3.new(0, tall / 2 - 1, 0)) * UPRIGHT })
		addPart(item, { name = "CactusArm", shape = CYL, size = Vector3.new(4, 1.4, 1.4), color = green, material = Enum.Material.Grass, offset = CFrame.new(p + Vector3.new(-1.9, tall * 0.62, 0)) * UPRIGHT })
		addPart(item, { name = "CactusArm", shape = CYL, size = Vector3.new(3.4, 1.4, 1.4), color = green, material = Enum.Material.Grass, offset = CFrame.new(p + Vector3.new(1.9, tall * 0.5, 0)) * UPRIGHT })
	end
	return item
end

PIECES.pineRing = function(art)
	local item = newItem("PineRing")
	item.anchor = "pocket"
	local E = art.EnvBands
	for i = 1, 14 do
		local p, h = around(E, i, 41, 80, 150, math.rad(170))
		local s = 0.85 + 0.5 * h
		addPart(item, { name = "RingPineTrunk", shape = CYL, size = Vector3.new(26 * s, 2.4, 2.4), color = rgb(52, 38, 30), material = Enum.Material.Wood, offset = CFrame.new(p + Vector3.new(0, 13 * s - 1, 0)) * UPRIGHT })
		addPart(item, { name = "RingPine", shape = BALL, size = Vector3.new(13, 34, 13) * s, color = rgb(20, 40, 30), material = Enum.Material.Grass, offset = CFrame.new(p + Vector3.new(0, 30 * s, 0)) })
	end
	return item
end

PIECES.loch = function(art)
	local item = newItem("Loch")
	item.anchor = "pocket"
	addPart(item, { name = "LochWater", size = Vector3.new(1400, 1, 800), color = rgb(34, 58, 84), material = Enum.Material.Glass, transparency = 0.12, offset = CFrame.new(36, -1.7, 116 + 400) })
	addPart(item, { name = "LochMoonGlint", size = Vector3.new(10, 0.1, 360), color = rgb(190, 214, 255), material = Enum.Material.Neon, transparency = 0.55, offset = CFrame.new(60, -1.15, 330) })
	return item
end

PIECES.castle = function(art)
	local item = newItem("Castle")
	item.anchor = "pocket"
	local stone = rgb(46, 48, 58)
	local c = Vector3.new(210, 0, 430)
	addPart(item, { name = "CastleTower", size = Vector3.new(26, 66, 26), color = stone, material = Enum.Material.Cobblestone, offset = CFrame.new(c + Vector3.new(0, 33, 0)) })
	addPart(item, { name = "CastleWall", size = Vector3.new(74, 26, 8), color = stone, material = Enum.Material.Cobblestone, offset = CFrame.new(c + Vector3.new(-48, 13, 6)) })
	addPart(item, { name = "CastleKeep", size = Vector3.new(20, 42, 20), color = stone, material = Enum.Material.Cobblestone, offset = CFrame.new(c + Vector3.new(-92, 21, 4)) })
	for i = 1, 3 do
		addPart(item, { name = "CastleMerlon", size = Vector3.new(5, 6, 5), color = stone, material = Enum.Material.Cobblestone, offset = CFrame.new(c + Vector3.new(-9 + (i - 1) * 9, 69, -9)) })
	end
	addPart(item, { name = "CastleWindow", size = Vector3.new(3, 5, 0.4), color = rgb(255, 196, 110), material = Enum.Material.Neon, offset = CFrame.new(c + Vector3.new(0, 44, -13.2)) })
	return item
end

-- camps: the loch's resident, gliding far out on the water now and then
PIECES.nessie = function(art)
	local item = newItem("Nessie")
	item.anchor = "pocket"
	local skin = rgb(30, 64, 58)
	addPart(item, { name = "NessieHump", shape = BALL, size = Vector3.new(10, 10, 12), color = skin })
	addPart(item, { name = "NessieHump", shape = BALL, size = Vector3.new(8, 8, 10), color = skin })
	addPart(item, { name = "NessieHump", shape = BALL, size = Vector3.new(6, 6, 8), color = skin })
	addPart(item, { name = "NessieNeck", shape = CYL, size = Vector3.new(14, 3, 3), color = skin })
	addPart(item, { name = "NessieHead", shape = BALL, size = Vector3.new(3.4, 3, 5), color = skin })
	item.animate = function(it, root, now)
		local t = (now * 4) % 520
		local x = -170 + t
		local z = 250
		local bob = math.sin(now * 0.9) * 0.6
		local e = it.entries
		e[1].part.CFrame = root * CFrame.new(x, bob, z)
		e[2].part.CFrame = root * CFrame.new(x - 12, bob * 0.7 - 1, z)
		e[3].part.CFrame = root * CFrame.new(x - 22, bob * 0.5 - 1.5, z)
		e[4].part.CFrame = root * CFrame.new(x + 8, 7 + bob, z) * CFrame.Angles(0, 0, math.rad(70))
		e[5].part.CFrame = root * CFrame.new(x + 10.5, 13.5 + bob, z) * CFrame.Angles(0, math.rad(90), 0)
	end
	return item
end

PIECES.redwoods = function(art)
	local item = newItem("Redwoods")
	item.anchor = "pocket"
	local E = art.EnvBands
	for i = 1, 12 do
		local p, h = around(E, i, 67, 90, 175, math.rad(165))
		local d = 9 + 7 * h
		addPart(item, { name = "Redwood", shape = CYL, size = Vector3.new(190, d, d), color = rgb(112, 56, 40), material = Enum.Material.Wood, offset = CFrame.new(p + Vector3.new(0, 94, 0)) * UPRIGHT })
		if i % 2 == 0 then
			addPart(item, { name = "RedwoodCrown", shape = BALL, size = Vector3.new(40, 60, 40), color = rgb(24, 52, 34), material = Enum.Material.Grass, offset = CFrame.new(p + Vector3.new(0, 170, 0)) })
		end
	end
	return item
end

-- camps: a glimpse of Bigfoot between the redwoods, well behind the cage row
PIECES.bigfootGlimpse = function(art)
	local item = newItem("BigfootGlimpse")
	item.anchor = "pocket"
	silhouette(item, "Glimpse", 0.62, rgb(46, 32, 24))
	item.animate = function(it, root, now)
		local a = math.sin(now * 0.05) * math.rad(55)
		local r = 150
		local pos = CENTRE + Vector3.new(math.sin(a) * r, -1.3, math.cos(a) * r)
		local dir = math.cos(now * 0.05)
		local ahead = CENTRE + Vector3.new(math.sin(a + 0.02 * dir) * r, -1.3, math.cos(a + 0.02 * dir) * r)
		walkAnimate(it, root * CFrame.lookAt(pos, ahead), now, 0.62)
	end
	return item
end

-- ─────────────────────────────────────────────────────────────── critters (moving life)

local CRITTERS = {}

CRITTERS.crow = function(item, scale)
	scale = scale or 1
	local black = rgb(22, 20, 26)
	addPart(item, { name = "CrowBody", shape = BALL, size = Vector3.new(1, 1, 2) * scale, color = black })
	addPart(item, { name = "CrowWingL", size = Vector3.new(2.2, 0.12, 1) * scale, color = black })
	addPart(item, { name = "CrowWingR", size = Vector3.new(2.2, 0.12, 1) * scale, color = black })
	item.animate = function(it, cf, now)
		local flap = math.sin(now * 9 + (it.phase or 0)) * 0.5
		it.entries[1].part.CFrame = cf
		it.entries[2].part.CFrame = cf * CFrame.Angles(0, 0, 0.2 + flap) * CFrame.new(-1.1 * scale, 0, 0)
		it.entries[3].part.CFrame = cf * CFrame.Angles(0, 0, -0.2 - flap) * CFrame.new(1.1 * scale, 0, 0)
	end
end

CRITTERS.bat = function(item, scale)
	scale = scale or 1
	local c = rgb(36, 26, 40)
	addPart(item, { name = "BatBody", shape = BALL, size = Vector3.new(0.7, 0.7, 1) * scale, color = c })
	addPart(item, { name = "BatWingL", size = Vector3.new(1.6, 0.1, 0.9) * scale, color = c })
	addPart(item, { name = "BatWingR", size = Vector3.new(1.6, 0.1, 0.9) * scale, color = c })
	item.animate = function(it, cf, now)
		local flap = math.sin(now * 16 + (it.phase or 0)) * 0.7
		local wob = CFrame.new(0, math.sin(now * 3 + (it.phase or 0)) * 0.8, 0)
		it.entries[1].part.CFrame = cf * wob
		it.entries[2].part.CFrame = cf * wob * CFrame.Angles(0, 0, flap) * CFrame.new(-0.8 * scale, 0, 0)
		it.entries[3].part.CFrame = cf * wob * CFrame.Angles(0, 0, -flap) * CFrame.new(0.8 * scale, 0, 0)
	end
end

CRITTERS.wisp = function(item, scale)
	scale = scale or 1
	addPart(item, { name = "WispCore", shape = BALL, size = Vector3.new(0.9, 0.9, 0.9) * scale, color = rgb(170, 255, 230), material = Enum.Material.Neon, transparency = 0.05 })
	addPart(item, { name = "WispHalo", shape = BALL, size = Vector3.new(2.4, 2.4, 2.4) * scale, color = rgb(90, 255, 190), material = Enum.Material.Neon, transparency = 0.8 })
	item.animate = function(it, cf, now)
		local bob = CFrame.new(math.sin(now * 1.3 + (it.phase or 0)) * 1.2, math.sin(now * 2.1 + (it.phase or 0)) * 0.9, 0)
		for _, e in it.entries do e.part.CFrame = cf * bob end
	end
end

-- a pair of red eyes in the treeline, blinking (Mothman is watching)
CRITTERS.redEyes = function(item)
	addPart(item, { name = "RedEye", shape = BALL, size = Vector3.new(0.5, 0.35, 0.35), color = rgb(255, 30, 30), material = Enum.Material.Neon })
	addPart(item, { name = "RedEye", shape = BALL, size = Vector3.new(0.5, 0.35, 0.35), color = rgb(255, 30, 30), material = Enum.Material.Neon, offset = CFrame.new(0.9, 0, 0) })
	item.animate = function(it, cf, now)
		local shut = (now + (it.phase or 0) * 3) % 4 < 0.18
		for _, e in it.entries do
			e.part.CFrame = cf * e.offset
			local t = if shut then 1 else e.lastT
			e.part.Transparency = t
		end
	end
end

CRITTERS.meteor = function(item)
	local p = addPart(item, { name = "Meteor", shape = BALL, size = Vector3.new(3, 3, 3), color = rgb(255, 214, 160), material = Enum.Material.Neon })
	addTrail(item, p, 1.4, { lifetime = 0.6, color = rgb(255, 196, 120), transparency = 0.1, lightEmission = 1 })
end

CRITTERS.tumbleweed = function(item)
	addPart(item, { name = "Tumbleweed", shape = BALL, size = Vector3.new(3.2, 3.2, 3.2), color = rgb(150, 116, 70), material = Enum.Material.Grass, transparency = 0.15 })
	item.animate = function(it, cf, now)
		it.entries[1].part.CFrame = cf * CFrame.Angles(-now * 4 - (it.phase or 0), 0, 0)
	end
end

-- ─────────────────────────────────────────────────────────────── construction

function NightArt.new(folder, rand, Config, EnvBands, Night)
	local self = setmetatable({}, NightArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.EnvBands = EnvBands
	self.Night = Night
	self.pieces = {} -- id -> item
	self.critters = {} -- kind -> { critter records }
	self.hazardModels = {} -- kind -> item
	self.habitats = {} -- col -> { item, kind, key }
	self.homeRoot = CFrame.new()
	self.homeRect = nil
	self.perches = {}
	self.pocketX = nil
	return self
end

function NightArt.hasPiece(id)
	return PIECES[id] ~= nil
end

function NightArt.hasCritter(kind)
	return CRITTERS[kind] ~= nil
end

-- Where the road is: rect = { cx, cz, sx, sz } of the server's Ground; perches = the tops of its pine crowns.
function NightArt:setHome(rect, perches)
	self.homeRect = if rect then { cx = rect.cx, cz = rect.cz, sx = rect.sx, sz = rect.sz } else nil
	self.homeRoot = if rect then CFrame.new(rect.cx, 0, rect.cz) else CFrame.new()
	local rel = {}
	for _, p in perches or {} do table.insert(rel, p) end
	self.perches = rel
	-- home scenery built before the road was known (a client that started before it replicated) was
	-- centred on the origin with no perches: drop it, and it is rebuilt around the road when next shown
	for id, item in self.pieces do
		if item.anchor == "home" then
			for _, e in item.entries do e.part:Destroy() end
			self.pieces[id] = nil
		end
	end
end

-- The camp pocket the player is in (its origin x), or nil at home.
function NightArt:setPocket(originX)
	if originX ~= self.pocketX then
		self.pocketX = originX
		for _, item in self.pieces do
			if item.anchor == "pocket" then
				item.placed = false
				-- a new camp, a new camera: judge each part afresh on its first frame (no fade from the last camp)
				for _, e in item.entries do
					e.occ, e.occAt = nil, nil
				end
			end
		end
	end
end

-- Leave out a pocket entry whose placed part would reach into the camp or its camera corridor.
function NightArt:guard(e)
	local ox = self.pocketX
	if ox == nil then return end
	local ex, ey, ez = extents(e.part)
	local p = e.part.Position
	local lx = p.X - ox
	local bad = p.Y + ey > FLOOR_TOP and not self.Night.boxClearOfCamp(self.cfg, lx - ex, lx + ex, p.Z - ez, p.Z + ez)
	if bad ~= (e.hidden == true) then
		e.hidden = bad
	end
	if bad and e.part.Parent ~= nil then
		e.part.Parent = nil
	elseif not bad and e.part.Parent == nil and (self.pieces[e.owner] and self.pieces[e.owner].shown) then
		e.part.Parent = self.folder
	end
end

-- The camera's view. Scenery can stand between a zoomed-out, orbiting camera and what the player must see:
-- in a camp a pine crown or a redwood hid the raider and the nets (review 2026-09-24, finding 3), and at home
-- a far pine hid the player. Every line of sight from the camera to the camp projects into
-- Night.campViewHull; at home, to the player, into the hull of the camera and a HomeViewRadius box round the
-- root. A part whose footprint enters the hull is hidden AT ONCE, on the frame the camera moved, and fades
-- back in over OCC_FADE seconds once it is clear. (With the usual follow camera nothing is hidden: in a camp
-- that hull is the camp plus the corridor the keep-out already keeps clear; at home it is a few studs wide.)
-- It runs LAST for every shown piece each frame (updatePiece), so whatever setWeight and the keep-out guard
-- did earlier in the frame, the part ends the frame hidden or faded as the view requires. Floor pieces (the
-- far floor, the bluff, the ravine walls, a camp's ground, the loch) lie under FLOOR_TOP: never hidden.
local OCC_FADE = 0.4

-- The hull for this frame, cached per frame: "camp" (pocket-local) or "home" (world, round the player).
function NightArt:viewHull(which, cam, now)
	local key = which .. tostring(now)
	if self.hullKey == key then return self.hull end
	local hull = nil
	if cam ~= nil then
		if which == "camp" and self.pocketX ~= nil then
			hull = self.Night.campViewHull(self.cfg, cam.X - self.pocketX, cam.Z)
		elseif which == "home" and self.viewTarget ~= nil then
			local t, r = self.viewTarget, self.cfg.Night.HomeViewRadius
			hull = self.Night.viewHull(cam.X, cam.Z, t.X - r, t.X + r, t.Z - r, t.Z + r)
		end
	end
	self.hullKey, self.hull = key, hull
	return hull
end

-- The player to keep in view at home (Night.client sets it every frame): the local root's position, or nil.
function NightArt:setViewTarget(pos)
	self.viewTarget = pos
end

-- Hide (or fade back) each entry of a shown item by the hull; `ox` turns a world x into the hull's frame.
-- No hull (no pocket, no root known): nothing is in the way, so anything hidden comes back.
function NightArt:occlude(item, hull, ox, now)
	for _, e in item.entries do
		if not e.hidden then
			local inView = false
			if hull ~= nil then
				-- the world-aligned footprint; a static part's is kept until it is placed again (mobile: fewer reads)
				local fp = e.fp
				if fp == nil or item.animate then
					local ex, ey, ez = extents(e.part)
					local p = e.part.Position
					fp = { x0 = p.X - ex, x1 = p.X + ex, z0 = p.Z - ez, z1 = p.Z + ez, top = p.Y + ey }
					if not item.animate then e.fp = fp end
				end
				-- a part wholly under the floor (a camp's ground, the loch) can hide nothing
				inView = fp.top > FLOOR_TOP and self.Night.boxOverlapsHull(hull, fp.x0 - ox, fp.x1 - ox, fp.z0, fp.z1)
			end
			local occ
			if inView then
				occ = 0
			elseif e.occ ~= nil and e.occ < 1 and e.occAt ~= nil then
				occ = math.min(1, e.occ + math.max(0, now - e.occAt) / OCC_FADE)
			else
				occ = 1
			end
			e.occAt = now
			if occ ~= e.occ then
				e.occ = occ
				local t = 1 - (1 - e.base) * item.weight * occ
				e.part.Transparency = t
				e.lastT = t
			end
			local want = item.shown and occ > 0
			if want and e.part.Parent == nil then
				e.part.Parent = self.folder
			elseif not want and e.part.Parent ~= nil then
				e.part.Parent = nil
			end
		end
	end
end

-- Show piece `id` at weight w; `cam` is the camera position (a Vector3).
function NightArt:updatePiece(id, w, cam, now)
	local item = self.pieces[id]
	if item == nil then
		if w <= 0.01 then return end
		local build = PIECES[id]
		if build == nil then return end
		item = build(self)
		for _, e in item.entries do e.owner = id end
		self.pieces[id] = item
	end
	-- a pocket piece with no pocket to stand in has nowhere to be
	if item.anchor == "pocket" and self.pocketX == nil then w = 0 end
	setWeight(item, w, self.folder)
	if not item.shown then return end
	if item.anchor == "home" then
		if item.animate then
			item.animate(item, self.homeRoot, now or 0, cam)
		elseif not item.placed then
			place(item, if item.world then CFrame.new() else self.homeRoot)
			item.placed = true
		end
		self:occlude(item, self:viewHull("home", cam, now or 0), 0, now or 0)
	elseif item.anchor == "pocket" then
		local root = CFrame.new(self.pocketX :: number, 0, 0)
		if item.animate then
			item.animate(item, root, now or 0, cam)
			for _, e in item.entries do self:guard(e) end
		elseif not item.placed then
			place(item, root)
			for _, e in item.entries do self:guard(e) end
			item.placed = true
		end
		self:occlude(item, self:viewHull("camp", cam, now or 0), self.pocketX :: number, now or 0)
	else -- "sky": travels with the camera
		place(item, CFrame.new(cam))
	end
end

-- ─────────────────────────────────────────────── critters: pooled, spawned on a ring, recycled

local function buildCritter(kind, scale)
	local item = newItem(kind)
	CRITTERS[kind](item, scale)
	return item
end

-- desired: { [kind] = count }. keepOut(pos: Vector3) -> true where no critter may be (a camp).
function NightArt:updateCritters(desired, cam, dt, now, keepOut)
	local E = self.EnvBands
	local specs = self.cfg.Night.Critters
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
				if spec.ground then c.pos.y = spec.ground end
				local p = Vector3.new(c.pos.x, c.pos.y, c.pos.z)
				if E.ambientExpired(c.pos, camV, spec) or (keepOut and keepOut(p)) then
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
						local hv = Vector3.new(c.vel.x, 0, c.vel.z)
						local look = if hv.Magnitude > 0.01 then p + hv else p + Vector3.new(0, 0, -1)
						local cf = CFrame.lookAt(p, look)
						if c.item.animate then
							c.item.animate(c.item, cf, now)
						else
							place(c.item, cf)
						end
					end
				end
			end
		end
		-- spawn at most one group per kind per frame, never where a camp keeps life out
		if active < want and spec then
			local group = math.min(spec.flock or 1, want - active)
			local base = E.ambientSpawn(camV, spec, self.rand)
			if spec.ground then base.pos.y = spec.ground end
			local basePos = Vector3.new(base.pos.x, base.pos.y, base.pos.z)
			if not (keepOut and keepOut(basePos)) then
				for g = 1, group do
					local c = nil
					for _, existing in list do
						if not existing.active then c = existing; break end
					end
					if c == nil then
						c = { item = buildCritter(kind), active = false }
						table.insert(list, c)
					end
					local ox, oz = (g - 1) % 3 * 4 - 4, -(g - 1) * 3
					local pos = { x = base.pos.x + ox, y = base.pos.y + (g - 1) * 0.8, z = base.pos.z + oz }
					if not (keepOut and keepOut(Vector3.new(pos.x, pos.y, pos.z))) then
						c.active = true
						c.leaving = false
						c.w = 0
						c.item.phase = self.rand() * 6.28
						c.pos = pos
						c.vel = base.vel
					end
				end
			end
		end
	end
end

-- ─────────────────────────────────────────────── habitats: your own cages

local GLOW = { rgb(150, 176, 140), rgb(80, 150, 255), rgb(185, 95, 255), rgb(255, 200, 60) }

local HABITAT = {
	prairie = { color = rgb(168, 150, 92), material = Enum.Material.Grass, fx = "dust",
		props = function(item, add)
			add({ name = "Tuft", size = Vector3.new(1.2, 1.4, 1.2), color = rgb(120, 150, 70), material = Enum.Material.Grass, shape = BALL, at = Vector3.new(-2.6, 0.5, 2.6) })
			add({ name = "Burrow", size = Vector3.new(2, 1.2, 2), color = rgb(110, 84, 54), material = Enum.Material.Ground, shape = BALL, at = Vector3.new(2.5, 0.2, 2.5) })
		end },
	northwoods = { color = rgb(58, 70, 46), material = Enum.Material.Grass, fx = "smoke",
		props = function(item, add)
			add({ name = "Stump", size = Vector3.new(1.3, 1.8, 1.8), color = rgb(96, 70, 48), material = Enum.Material.Wood, shape = CYL, at = Vector3.new(-2.6, 0.65, 2.6), upright = true })
			add({ name = "MossRock", size = Vector3.new(1.6, 1, 1.4), color = rgb(80, 96, 70), material = Enum.Material.Slate, shape = BALL, at = Vector3.new(2.6, 0.3, 2.5) })
		end },
	desert = { color = rgb(196, 160, 110), material = Enum.Material.Sand, fx = "dust",
		props = function(item, add)
			add({ name = "Saguaro", size = Vector3.new(2.8, 0.8, 0.8), color = rgb(64, 110, 62), material = Enum.Material.Grass, shape = CYL, at = Vector3.new(-2.6, 1.4, 2.6), upright = true })
			add({ name = "Skull", size = Vector3.new(0.9, 0.7, 1), color = rgb(236, 230, 214), material = Enum.Material.SmoothPlastic, shape = BALL, at = Vector3.new(2.6, 0.3, 2.6) })
		end },
	moonfield = { color = rgb(150, 136, 70), material = Enum.Material.Grass, fx = "fireflies",
		props = function(item, add)
			add({ name = "Wheat", size = Vector3.new(1.6, 2.4, 0.3), color = rgb(214, 188, 96), material = Enum.Material.Grass, at = Vector3.new(-2.6, 1.2, 2.6) })
			add({ name = "Post", size = Vector3.new(0.4, 2.2, 0.4), color = rgb(90, 66, 46), material = Enum.Material.Wood, at = Vector3.new(2.7, 1.1, 2.7) })
		end },
	barrens = { color = rgb(70, 50, 36), material = Enum.Material.Ground, fx = "embers",
		props = function(item, add)
			add({ name = "Sapling", size = Vector3.new(1.4, 3, 1.4), color = rgb(24, 52, 34), material = Enum.Material.Grass, shape = BALL, at = Vector3.new(-2.6, 1.5, 2.6) })
			add({ name = "Ember", size = Vector3.new(0.6, 0.6, 0.6), color = rgb(255, 120, 50), material = Enum.Material.Neon, shape = BALL, at = Vector3.new(2.6, 0.3, 2.6) })
		end },
	bridge = { color = rgb(70, 74, 82), material = Enum.Material.Slate, fx = "moths",
		props = function(item, add)
			add({ name = "LampPost", size = Vector3.new(0.3, 4.4, 0.3), color = rgb(40, 42, 48), material = Enum.Material.Metal, at = Vector3.new(-2.8, 2.2, 2.8) })
			add({ name = "Lamp", size = Vector3.new(0.8, 0.8, 0.8), color = rgb(255, 214, 140), material = Enum.Material.Neon, shape = BALL, at = Vector3.new(-2.8, 4.5, 2.8) })
		end },
	loch = { color = rgb(58, 80, 70), material = Enum.Material.Pebble, fx = "mist",
		props = function(item, add)
			add({ name = "Pool", size = Vector3.new(0.14, 4.6, 4.6), color = rgb(50, 110, 150), material = Enum.Material.Glass, transparency = 0.25, shape = CYL, at = Vector3.new(1.2, 0.08, 1.2), upright = true })
			add({ name = "Reeds", size = Vector3.new(0.3, 2.2, 1.2), color = rgb(96, 130, 70), material = Enum.Material.Grass, at = Vector3.new(-2.7, 1.1, 2.7) })
		end },
	rainforest = { color = rgb(40, 72, 42), material = Enum.Material.Grass, fx = "mist",
		props = function(item, add)
			add({ name = "Fern", size = Vector3.new(2.4, 0.9, 2.4), color = rgb(52, 110, 56), material = Enum.Material.Grass, shape = BALL, at = Vector3.new(-2.5, 0.35, 2.5) })
			add({ name = "Boulder", size = Vector3.new(1.8, 1.4, 1.6), color = rgb(96, 98, 94), material = Enum.Material.Slate, shape = BALL, at = Vector3.new(2.5, 0.5, 2.5) })
		end },
}

local HABITAT_FX = {
	dust = { Color = { 210, 186, 140 }, Size = 0.35, Lifetime = { 2, 3 }, Speed = { 0.5, 1.2 }, LightEmission = 0, Acceleration = Vector3.new(0, 0.3, 0), Transparency = 0.5 },
	smoke = { Color = { 170, 170, 176 }, Size = 0.9, Lifetime = { 2.5, 3.5 }, Speed = { 0.8, 1.6 }, LightEmission = 0, Acceleration = Vector3.new(0, 0.8, 0), Transparency = 0.7, Spread = 20 },
	fireflies = { Color = { 255, 236, 120 }, Size = 0.2, Lifetime = { 2, 4 }, Speed = { 0.3, 0.9 }, LightEmission = 1, Acceleration = Vector3.zero, Transparency = 0.1 },
	embers = { Color = { 255, 140, 60 }, Size = 0.18, Lifetime = { 1.5, 2.5 }, Speed = { 1, 2 }, LightEmission = 1, Acceleration = Vector3.new(0, 1.2, 0), Transparency = 0.15, Spread = 25 },
	moths = { Color = { 240, 230, 200 }, Size = 0.22, Lifetime = { 2, 3 }, Speed = { 0.6, 1.4 }, LightEmission = 0.4, Acceleration = Vector3.zero, Transparency = 0.2 },
	mist = { Color = { 220, 235, 240 }, Size = 2.2, Lifetime = { 3, 4.5 }, Speed = { 0.2, 0.6 }, LightEmission = 0.1, Acceleration = Vector3.zero, Transparency = 0.85 },
}

-- habs: Night.habitats(...) { [col] = { kind, tier, glow, lit } }; bases: { [col] = CFrame of the server's cage base top }.
function NightArt:updateHabitats(habs, bases, w)
	local H = self.cfg.Night.Habitats
	for col = 1, 9 do
		local want = habs[col]
		local base = bases[col]
		local have = self.habitats[col]
		local key = if want and base then want.kind .. "|" .. want.tier .. "|" .. tostring(base) else nil
		if have and have.key ~= key then
			setWeight(have.item, 0, self.folder)
			for _, e in have.item.entries do e.part:Destroy() end
			self.habitats[col] = nil
			have = nil
		end
		if want and base and have == nil then
			local def = HABITAT[want.kind]
			if def then
				local item = newItem("Habitat_" .. col)
				addPart(item, { name = "Habitat_" .. col .. "_Rim", size = Vector3.new(7.4, 0.08, 7.4), color = GLOW[want.tier], material = Enum.Material.Neon, transparency = want.glow, offset = base * CFrame.new(0, 0.04, 0) })
				local patch = addPart(item, { name = "Habitat_" .. col .. "_Patch", size = Vector3.new(6.8, 0.12, 6.8), color = def.color, material = def.material, offset = base * CFrame.new(0, 0.1, 0) })
				def.props(item, function(p)
					local off = base * CFrame.new(p.at)
					if p.upright then off = off * UPRIGHT end
					addPart(item, { name = "Habitat_" .. col .. "_" .. p.name, size = p.size, color = p.color, material = p.material, shape = p.shape, transparency = p.transparency, offset = off })
				end)
				local fx = HABITAT_FX[def.fx]
				if fx then
					local fxDef = table.clone(fx)
					fxDef.name = "HabitatFx"
					addEmitter(item, patch, fxDef, H.EmitterRate)
				end
				place(item, CFrame.new())
				self.habitats[col] = { item = item, key = key }
				have = self.habitats[col]
			end
		end
		if have then
			setWeight(have.item, w, self.folder)
			local lit = want and want.lit and w > 0.3
			for _, pe in have.item.emitters do
				if pe.Enabled ~= lit then pe.Enabled = lit end
			end
		end
	end
end

-- ─────────────────────────────────────────────── the rest campfire

function NightArt:updateCampfire(on, groundCF, now)
	local C = self.cfg.Night.Campfire
	if self.campfire == nil then
		if not on then return end
		local item = newItem("Campfire")
		local wood = rgb(84, 58, 40)
		addPart(item, { name = "Campfire_Log", shape = CYL, size = Vector3.new(2.6, 0.5, 0.5), color = wood, material = Enum.Material.Wood, offset = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0.4, 0) })
		addPart(item, { name = "Campfire_Log", shape = CYL, size = Vector3.new(2.6, 0.5, 0.5), color = wood, material = Enum.Material.Wood, offset = CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 2.5, 0) })
		addPart(item, { name = "Campfire_Stones", shape = CYL, size = Vector3.new(0.3, 3.2, 3.2), color = rgb(80, 80, 84), material = Enum.Material.Slate, offset = CFrame.new(0, 0.1, 0) * UPRIGHT })
		local flame = addPart(item, { name = "Campfire_Flame", shape = BALL, size = Vector3.new(0.9, 1.3, 0.9), color = rgb(255, 150, 60), material = Enum.Material.Neon, transparency = 0.1, offset = CFrame.new(0, 0.9, 0) })
		addEmitter(item, flame, { name = "CampfireFx", Color = { 255, 150, 60 }, Size = 0.5, Lifetime = { 0.6, 1.1 }, Speed = { 2, 4 }, LightEmission = 1, Acceleration = Vector3.new(0, 2, 0), Transparency = 0.2, Spread = 15 }, C.Rate)
		local light = Instance.new("PointLight")
		light.Name = "CampfireLight"
		light.Color = rgb(255, 170, 90)
		light.Range = C.LightRange
		light.Brightness = C.LightBrightness
		light.Shadows = false
		light.Enabled = false
		light.Parent = flame
		table.insert(item.lights, light)
		self.campfire = item
	end
	local item = self.campfire
	if on and groundCF then
		if item.at ~= groundCF then
			place(item, groundCF)
			item.at = groundCF
		end
		local flicker = 1 + math.sin((now or 0) * 17) * 0.08
		item.entries[4].part.Size = Vector3.new(0.9, 1.3 * flicker, 0.9)
	end
	setWeight(item, if on then 1 else 0, self.folder)
	for _, pe in item.emitters do
		if pe.Enabled ~= on then pe.Enabled = on end
	end
end

-- ─────────────────────────────────────────────── hazards + their telegraph

local HAZARD_RECIPE = {
	crow = { "crow", 1.4 },
	bat = { "bat", 1.8 },
	wisp = { "wisp", 1.4 },
	meteorite = { "meteorite", 1 },
}

CRITTERS.meteorite = function(item, scale)
	scale = scale or 1
	local rock = addPart(item, { name = "Rock", shape = BALL, size = Vector3.new(2.6, 2.4, 2.8) * scale, color = rgb(70, 56, 50), material = Enum.Material.Basalt })
	addPart(item, { name = "Glow", shape = BALL, size = Vector3.new(2, 2, 2) * scale, color = rgb(255, 140, 60), material = Enum.Material.Neon, transparency = 0.25 })
	addTrail(item, rock, 1.1 * scale, { lifetime = 0.7, color = rgb(255, 160, 80), transparency = 0.15, lightEmission = 1 })
	item.animate = function(it, cf, now)
		local rot = CFrame.Angles(now * 2.3, now * 1.7, 0)
		it.entries[1].part.CFrame = cf * rot
		it.entries[2].part.CFrame = cf
	end
end

function NightArt.hazardKinds()
	local out = {}
	for k in HAZARD_RECIPE do out[k] = true end
	return out
end

function NightArt:hazardModel(kind)
	local item = self.hazardModels[kind]
	if item then return item end
	local recipe = HAZARD_RECIPE[kind] or { "crow", 1.4 }
	item = newItem("Hazard_" .. kind)
	CRITTERS[recipe[1]](item, recipe[2])
	local main = item.entries[1].part
	-- visible from anywhere: the warning marker. Text, never an emoji (Roblox's font draws some as boxes).
	local bb = Instance.new("BillboardGui")
	bb.Name = "HazardMarker"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(40, 40)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = main
	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.BackgroundColor3 = rgb(200, 30, 30)
	mark.BackgroundTransparency = 0.1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "!"
	mark.TextScaled = true
	mark.Font = Enum.Font.GothamBlack
	mark.TextColor3 = rgb(255, 236, 90)
	mark.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = mark
	item.billboard = bb
	local light = Instance.new("PointLight")
	light.Name = "HazardBlink"
	light.Color = rgb(255, 80, 60)
	light.Range = 18
	light.Brightness = 2
	light.Enabled = false
	light.Parent = main
	table.insert(item.lights, light)
	for _, e in item.entries do e.part.Name = "Hazard_" .. kind .. "_" .. e.part.Name end
	self.hazardModels[kind] = item
	return item
end

function NightArt:laneItem()
	if self.lane then return self.lane end
	local item = newItem("HazardLane")
	addPart(item, { name = "HazardLane", size = Vector3.new(0.3, 0.3, 10), color = rgb(255, 210, 60), material = Enum.Material.Neon, transparency = 0.45 })
	addPart(item, { name = "HazardRing", shape = CYL, size = Vector3.new(0.2, 8, 8), color = rgb(255, 210, 60), material = Enum.Material.Neon, transparency = 0.5 })
	self.lane = item
	return item
end

-- Draw the hazard this frame at `pos` (Night.drawPosition: the lane until arrival, then a swoop away, or
-- nothing once a meteorite has struck: `visible` false). `zone` is Hazards.zone(plan, PlayerRadius): the
-- ring IS the hit rule. `groundY` is the height of the floor under the player (the ring lies on it).
-- The "!" marker and the red blink are the WARNING: they run until arrival (or a hit) and are off after.
function NightArt:showHazard(plan, pos, now, zone, groundY, visible)
	local item = self:hazardModel(plan.kind)
	if visible == false then
		item.billboard.Enabled = false
		setWeight(item, 0, self.folder)
		if self.lane then setWeight(self.lane, 0, self.folder) end
		return
	end
	setWeight(item, 1, self.folder)
	local warning = plan.t <= plan.arriveAt and not plan.hit
	item.billboard.Enabled = warning and (not plan.locked or (math.floor(now * 6) % 2 == 0))
	item.lights[1].Enabled = warning and math.floor(now * 4) % 2 == 0
	local p = Vector3.new(pos.x, pos.y, pos.z)
	local v = Vector3.new(plan.velocity.x, plan.velocity.y, plan.velocity.z)
	local hv = Vector3.new(v.X, 0, v.Z)
	local cf = CFrame.lookAt(p, if hv.Magnitude > 0.01 then p + hv else p + Vector3.new(0, 0, -1))
	if item.animate then item.animate(item, cf, now) else place(item, cf) end

	local lane = self:laneItem()
	local target = Vector3.new(plan.target.x, plan.target.y, plan.target.z)
	local beyond = target + (if v.Magnitude > 0 then v.Unit * 20 else Vector3.zero)
	local len = (beyond - p).Magnitude
	if plan.t > plan.arriveAt or len < 1 then
		setWeight(lane, 0, self.folder)
		return
	end
	setWeight(lane, 1, self.folder)
	local colour = if plan.locked then rgb(255, 60, 60) else rgb(255, 210, 60)
	local laneE, ringE = lane.entries[1], lane.entries[2]
	laneE.part.Color = colour
	laneE.part.Size = Vector3.new(0.3, 0.3, len)
	laneE.part.CFrame = CFrame.lookAt(p:Lerp(beyond, 0.5), beyond)
	local d = 2 * zone.radius
	ringE.part.Color = colour
	ringE.part.Size = Vector3.new(0.2, d, d)
	ringE.part.CFrame = CFrame.new(zone.x, (groundY or (zone.y - 3)) + 0.12, zone.z) * UPRIGHT
end

function NightArt:hideHazard(kind)
	local item = self.hazardModels[kind]
	if item then
		item.billboard.Enabled = false
		setWeight(item, 0, self.folder)
	end
	if self.lane then setWeight(self.lane, 0, self.folder) end
end

-- ─────────────────────────────────────────────── weather

local WEATHER = {
	fireflies = { Color = { 255, 230, 120 }, Size = 0.28, Lifetime = { 4, 7 }, Speed = { 0.4, 1.2 }, LightEmission = 1, Acceleration = Vector3.new(0, 0.1, 0), Transparency = 0.1 },
	wisplights = { Color = { 150, 255, 200 }, Size = 0.32, Lifetime = { 4, 7 }, Speed = { 0.3, 1 }, LightEmission = 1, Acceleration = Vector3.zero, Transparency = 0.1 },
	mist = { Color = { 220, 228, 240 }, Size = 14, Lifetime = { 6, 9 }, Speed = { 0.5, 1.5 }, LightEmission = 0.1, Acceleration = Vector3.zero, Transparency = 0.9 },
	stardust = { Color = { 255, 214, 150 }, Size = 0.26, Lifetime = { 5, 8 }, Speed = { 0.2, 0.8 }, LightEmission = 1, Acceleration = Vector3.new(0, -0.2, 0), Transparency = 0.15 },
}

function NightArt.hasWeather(kind)
	return WEATHER[kind] ~= nil
end

-- rates: { [kind] = particles per second }. at: "camera" (rides with the camera at home) or "campBack"
-- (hangs behind the camp's back fence, so a camp's weather never drifts over the yard).
function NightArt:updateWeather(rates, cam, at)
	if self.weatherHost == nil then
		local host = Instance.new("Part")
		host.Name = "WeatherHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = Vector3.new(110, 14, 110)
		self.weatherHost = host
		self.emitters = {}
	end
	local B = self.cfg.Night.Budget
	local capped = self.EnvBands.capRates(rates, B.MaxWeatherEmitters, B.MaxWeatherRate, 0.05)
	local anyOn = false
	for kind, def in WEATHER do
		local rate = capped[kind] or 0
		local pe = self.emitters[kind]
		if pe == nil and rate > 0.05 then
			local holder = { emitters = {} }
			local d = table.clone(def)
			d.name = "Weather_" .. kind
			pe = addEmitter(holder, self.weatherHost, d, 0)
			pe.Shape = Enum.ParticleEmitterShape.Box
			pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
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
		local host = self.weatherHost
		if at == "campBack" and self.pocketX then
			local W = self.cfg.World
			local backZ = W.ApronDepth + W.CellSize * (W.CageRow + 1) + self.cfg.Night.CampMargin + 80
			host.Size = Vector3.new(220, 14, 60)
			host.CFrame = CFrame.new(self.pocketX + W.PlotWidth / 2, 7, backZ)
		else
			host.Size = Vector3.new(110, 14, 110)
			host.CFrame = CFrame.new(cam + Vector3.new(0, 4, 0))
		end
		host.Parent = self.folder
	else
		self.weatherHost.Parent = nil
	end
end

return NightArt
