-- TowerArt.luau — Fork Tower's scenery, life, hazard models, weather and lightning, built in code
-- (no assets). CLIENT ONLY: required by src/client/Ambience.client.luau; the server never touches it.
--
-- Everything here is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off (the camera never
-- pops in front of a leaf, nothing can be stood on, touched or raycast), CastShadow off. Nothing is
-- built until a band first needs it, and anything whose weight falls to zero is UNPARENTED, so a band
-- the player is not in costs no draw calls.
--
-- WHAT IT MAY LOOK AT, and why that matters in THIS game. Every fork is two doors, and the only thing
-- in the world that may say which is the trap is the inscription the player pays 1.1 s to read. So
-- nothing here is placed by, coloured by or aimed at a door, a pad, a section or anything a floor's
-- secret decides. The scenery stands in two WALLS either side of the lane, mirrored about the lane's
-- centre line and outside the tower's corridor (Config.Env.WallOffset/WallDepth; EnvConfig.spec
-- proves the gap), and its content is a hash of world-fixed cell coordinates and a constant seed.
-- The far set pieces follow the camera like a skybox. Critters spawn on a ring around the camera.
--
-- Dependencies arrive as arguments (a bare `require("./X")` is invalid in Roblox):
--     TowerArt.new(folder, rand, Config, EnvBands)
-- Budgets are measured, not assumed: robloxemu/check_forktower_env.luau counts what this module has
-- parented at every band and every band boundary against Config.Budget.

local TowerArt = {}
TowerArt.__index = TowerArt

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- ─────────────────────────────────────────────────────────────── items: parts that fade together
-- item = { entries = { { part, base, offset, lastT, hidden } }, beams, trails, lights, shown, weight }

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
				-- written, not only remembered: a part that comes back must come back invisible and fade
				-- in. (+1 Jump's SkyArt reset only lastT, so a part re-shown at a small weight kept its
				-- old transparency and popped in; measured here by check_forktower_env.)
				e.part.Transparency = 1
				e.lastT = 1
				e.alpha = 0
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
			if not e.hidden then e.part.Parent = folder end
		end
		item.shown = true
	end
	if not item.customAlpha then
		for _, e in item.entries do
			local t = 1 - (1 - e.base) * w
			if math.abs(t - e.lastT) > 0.02 or (w >= 0.99 and e.lastT ~= t) then
				e.part.Transparency = t
				e.lastT = t
			end
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

local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis is X; this stands it up
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- a Cylinder lying along Z (a disc facing +Z)

-- ─────────────────────────────────────────────────────────────── walls (world-fixed, mirrored)
--
-- A wall is a grid of world-fixed cells in (y, z) at x = laneX ± WallOffset. Each cell holds `slots`
-- parts whose shape and material are fixed per slot; `fill(slot, h)` decides each part's look from
-- h(k) = a hash of the cell's coordinates. The hash has NO side input: the two walls are mirror
-- images of each other about the lane's centre line. Offsets from `fill` are in wall space: +x points
-- AWAY from the lane, so a torch at x = -6 hangs on the inner face on both sides.
-- fill returns nil (leave the slot empty) or { size, x, y, z, color, spin?, rotX?, base? }.

local WALLS = {}

WALLS.dungeonWalls = {
	cellY = 60, cellZ = 60, radiusY = 1, radiusZ = 2, seed = 11,
	slots = {
		{ name = "Pillar", material = Enum.Material.Slate },
		{ name = "Torch", shape = BALL, material = Enum.Material.Neon },
	},
	fill = function(slot, h)
		if slot == 1 then
			local g = 62 + math.floor(h(1) * 14)
			return { size = Vector3.new(10, 60.4, 10), x = 0, y = 0, z = 0, color = rgb(g + 6, g, g - 4) }
		end
		if h(2) < 0.6 then
			return { size = Vector3.new(2.2, 2.2, 2.2), x = -6.2, y = (h(3) - 0.5) * 36, z = 0, color = rgb(255, 150 + math.floor(h(4) * 40), 60) }
		end
		return nil
	end,
}

WALLS.gardenWalls = {
	cellY = 50, cellZ = 50, radiusY = 1, radiusZ = 2, seed = 23,
	slots = {
		{ name = "Foliage", material = Enum.Material.Grass },
		{ name = "Bloom", shape = BALL, material = Enum.Material.Neon },
	},
	fill = function(slot, h)
		if slot == 1 then
			local k = h(1)
			if k < 0.45 then -- a giant leaf, tilted about the wall's axis
				return { size = Vector3.new(1.2, 26, 14), x = -2, y = (h(3) - 0.5) * 20, z = (h(4) - 0.5) * 24,
					rotX = (h(2) - 0.5) * 1.2, color = rgb(70 + math.floor(h(5) * 40), 150 + math.floor(h(6) * 40), 60 + math.floor(h(7) * 30)) }
			elseif k < 0.8 then -- a hanging vine
				return { size = Vector3.new(1.4, 50.4, 1.4), x = -3, y = 0, z = (h(4) - 0.5) * 36, color = rgb(62, 118 + math.floor(h(5) * 30), 50) }
			end
			-- a mossy ruin block
			return { size = Vector3.new(8, 12, 10), x = 1, y = (h(3) - 0.5) * 30, z = (h(4) - 0.5) * 24, color = rgb(92, 110, 80) }
		end
		if h(8) < 0.45 then
			local palette = { { 255, 140, 190 }, { 255, 220, 90 }, { 190, 130, 255 }, { 250, 250, 240 } }
			local c = palette[1 + math.floor(h(9) * #palette) % #palette]
			local s = 5 + h(10) * 3
			return { size = Vector3.new(s, s, s), x = -4, y = (h(11) - 0.5) * 36, z = (h(12) - 0.5) * 36, color = rgb(c[1], c[2], c[3]) }
		end
		return nil
	end,
}

WALLS.clockworkWalls = {
	cellY = 60, cellZ = 60, radiusY = 1, radiusZ = 2, seed = 37,
	slots = {
		{ name = "Gear", shape = CYL, material = Enum.Material.Metal },
		{ name = "Teeth", material = Enum.Material.Metal },
	},
	fill = function(slot, h)
		local gear = h(1) < 0.75
		local d = 20 + h(2) * 24
		local y, z = (h(3) - 0.5) * 24, (h(4) - 0.5) * 24
		local spin = (0.2 + h(5) * 0.4) * (if h(6) < 0.5 then -1 else 1)
		local brass = if h(7) < 0.6 then rgb(204, 162, 80) else rgb(188, 112, 62)
		if slot == 1 then
			if gear then
				-- a Cylinder's axis is X, so this disc faces the lane
				return { size = Vector3.new(2, d, d), x = -1, y = y, z = z, color = brass, spin = spin }
			end
			-- a vertical pipe (the cylinder stood up)
			return { size = Vector3.new(60.4, 3, 3), x = -2, y = 0, z = z, color = rgb(160, 110, 70), upright = true }
		end
		if gear then
			-- a bar across the disc, a little longer than it: the teeth, turning with the gear
			return { size = Vector3.new(1.4, d * 1.16, 3.2), x = -1.2, y = y, z = z, color = rgb(92, 80, 68), spin = spin }
		end
		return nil
	end,
}

WALLS.stormWalls = {
	cellY = 70, cellZ = 70, radiusY = 1, radiusZ = 2, seed = 51,
	slots = {
		{ name = "StormPuff", shape = BALL, material = Enum.Material.SmoothPlastic },
	},
	fill = function(_, h)
		local s = 34 + h(1) * 30
		local g = 72 + math.floor(h(2) * 24)
		return { size = Vector3.new(s, s, s), x = h(3) * 10, y = (h(4) - 0.5) * 30, z = (h(5) - 0.5) * 30,
			color = rgb(g, g + 6, g + 24), base = 0.18 }
	end,
}

WALLS.observatoryWalls = {
	cellY = 60, cellZ = 60, radiusY = 1, radiusZ = 2, seed = 67,
	slots = {
		{ name = "Lantern", shape = BALL, material = Enum.Material.Neon },
	},
	fill = function(_, h)
		local k = h(1)
		if k < 0.55 then -- a floating star lantern
			local palette = { { 255, 244, 214 }, { 180, 210, 255 }, { 255, 214, 130 } }
			local c = palette[1 + math.floor(h(2) * #palette) % #palette]
			local s = 1.6 + h(3) * 1.8
			return { size = Vector3.new(s, s, s), x = (h(4) - 0.5) * 16, y = (h(5) - 0.5) * 44, z = (h(6) - 0.5) * 44, color = rgb(c[1], c[2], c[3]) }
		elseif k < 0.75 then -- a small brass orrery ball
			local s = 5 + h(3) * 5
			return { size = Vector3.new(s, s, s), x = (h(4) - 0.5) * 12, y = (h(5) - 0.5) * 40, z = (h(6) - 0.5) * 40, color = rgb(214, 172, 90) }
		end
		return nil
	end,
}

local function wallItem(art, name, spec)
	local item = newItem(name)
	item.anchor = "walls"
	item.wall = spec
	item.customAlpha = true -- walls fade each slot by the band's weight AND by its distance to the grid's edge
	item.ny, item.nz = 2 * spec.radiusY + 1, 2 * spec.radiusZ + 1
	local cells = item.ny * item.nz * 2
	for _ = 1, cells do
		for _, s in spec.slots do
			local _, e = addPart(item, { name = s.name, shape = s.shape, material = s.material, size = Vector3.new(1, 1, 1) })
			e.slot = s
			e.alpha = 0
		end
	end
	return item
end

local function smooth01(x: number): number
	if x <= 0 then return 0 end
	if x >= 1 then return 1 end
	return x * x * (3 - 2 * x)
end

-- How much of a cell is shown: 1 in the middle of the grid, 0 at its edge, so the row that leaves the
-- grid and the row that enters it (the same slots, moved) are both invisible when they move.
local function edgeFade(spec, cellY: number, cellZ: number, cam: Vector3): number
	local fy = math.abs((cellY + 0.5) * spec.cellY - cam.Y) / ((spec.radiusY + 0.5) * spec.cellY)
	local fz = math.abs((cellZ + 0.5) * spec.cellZ - cam.Z) / ((spec.radiusZ + 0.5) * spec.cellZ)
	return 1 - smooth01((math.max(fy, fz) - 0.55) / 0.45)
end

-- Place a wall's cells around the camera. `laneX` is the lane's centre line. A cell keeps its slots
-- for as long as it stays inside the window (slot = cell coordinates modulo the window), so moving
-- the camera re-places only the row that left, as the row that enters; every other part stays put.
local function placeWall(self, item, cam, laneX)
	local spec = item.wall
	local E = self.EnvBands
	local cy, cz = E.cellOf(cam.Y, spec.cellY), E.cellOf(cam.Z, spec.cellZ)
	if item.cellY == cy and item.cellZ == cz and item.laneX == laneX then return end
	local laneMoved = item.laneX ~= laneX
	item.cellY, item.cellZ, item.laneX = cy, cz, laneX
	local W = self.cfg.Env.WallOffset
	local nSlots = #spec.slots
	local ny, nz = item.ny, item.nz
	for sideIdx, side in { -1, 1 } do
		for dy = -spec.radiusY, spec.radiusY do
			for dz = -spec.radiusZ, spec.radiusZ do
				local y0, z0 = cy + dy, cz + dz
				local cellIdx = (y0 % ny) * nz + (z0 % nz)
				local base = ((sideIdx - 1) * ny * nz + cellIdx) * nSlots
				local first = item.entries[base + 1]
				if laneMoved or first.cellY ~= y0 or first.cellZ ~= z0 then
					local function h(i)
						return E.hash01(y0, z0, i, spec.seed)
					end
					local anchor = Vector3.new(laneX + side * W, (y0 + 0.5) * spec.cellY, (z0 + 0.5) * spec.cellZ)
					for s = 1, nSlots do
						local e = item.entries[base + s]
						e.cellY, e.cellZ = y0, z0
						e.spinner = nil
						e.alpha = 0 -- a slot that moves starts invisible and fades in (it is at the edge anyway)
						e.lastT = 1
						e.part.Transparency = 1
						local d = spec.fill(s, h)
						e.hidden = d == nil
						if d == nil then
							e.part.Parent = nil
						else
							e.part.Size = d.size
							e.part.Color = d.color
							e.base = d.base or 0
							local cf = CFrame.new(anchor + Vector3.new(side * d.x, d.y, d.z))
							if d.upright then cf = cf * UPRIGHT end
							if d.rotX then cf = cf * CFrame.Angles(side * d.rotX, 0, 0) end
							e.home = cf
							e.part.CFrame = cf
							if d.spin then e.spinner = d.spin * side end
							if item.shown and e.part.Parent ~= self.folder then e.part.Parent = self.folder end
						end
					end
				end
			end
		end
	end
end

-- Each slot glides toward (band weight x edge fade), so neither a band seam, nor the grid moving,
-- nor a teleport (a door choice, a fall rescue) ever pops a part in or out.
local function fadeWall(item, cam: Vector3, dt: number, E)
	local spec = item.wall
	local w = item.weight
	for _, e in item.entries do
		if not e.hidden and e.cellY ~= nil then
			local target = w * edgeFade(spec, e.cellY, e.cellZ, cam)
			e.alpha = E.approach(e.alpha, target, dt, 0.35)
			local t = 1 - (1 - e.base) * e.alpha
			if math.abs(t - e.lastT) > 0.01 or (t >= 0.999 and e.lastT < 0.999) then
				e.part.Transparency = t
				e.lastT = t
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────── far set pieces (follow the camera)

local PIECES = {}

-- three giant flowers far out, rising from below
PIECES.farBlooms = function()
	local item = newItem("FarBlooms")
	item.anchor = "sky"
	for i, a in { 20, 140, 260 } do
		local r = math.rad(a)
		local x, z = math.sin(r) * 380, math.cos(r) * 380
		addPart(item, { name = "BloomStem", shape = CYL, size = Vector3.new(260, 10, 10), color = rgb(70, 140, 70), material = Enum.Material.Grass, offset = CFrame.new(x, -150, z) * UPRIGHT })
		local c = ({ rgb(255, 150, 196), rgb(255, 214, 96), rgb(196, 140, 255) })[i]
		addPart(item, { name = "BloomHead", shape = BALL, size = Vector3.new(64, 64, 64), color = c, material = Enum.Material.Neon, transparency = 0.1, offset = CFrame.new(x, -10, z) })
	end
	return item
end

-- a great clock face ahead of the climb (+Z), its hands turning
PIECES.clockFace = function()
	local item = newItem("ClockFace")
	item.anchor = "sky"
	item.centre = CFrame.new(0, 110, 560)
	addPart(item, { name = "ClockRim", shape = CYL, size = Vector3.new(3, 290, 290), color = rgb(196, 150, 70), material = Enum.Material.Metal, offset = CFrame.new(0, 0, 3) * ALONG_Z })
	addPart(item, { name = "ClockDial", shape = CYL, size = Vector3.new(3, 260, 260), color = rgb(236, 226, 196), offset = ALONG_Z })
	addPart(item, { name = "HourHand", size = Vector3.new(9, 80, 3), color = rgb(40, 32, 28), offset = CFrame.new(0, 0, -3) })
	addPart(item, { name = "MinuteHand", size = Vector3.new(6, 116, 3), color = rgb(40, 32, 28), offset = CFrame.new(0, 0, -4) })
	addPart(item, { name = "ClockHub", shape = BALL, size = Vector3.new(16, 16, 16), color = rgb(204, 162, 80), material = Enum.Material.Metal, offset = CFrame.new(0, 0, -5) })
	item.animate = function(it, root, now)
		for i, e in it.entries do
			local cf = root * e.offset
			if i == 3 then
				cf = root * CFrame.new(0, 0, -3) * CFrame.Angles(0, 0, -now * 0.03) * CFrame.new(0, 34, 0)
			elseif i == 4 then
				cf = root * CFrame.new(0, 0, -4) * CFrame.Angles(0, 0, -now * 0.36) * CFrame.new(0, 52, 0)
			end
			e.part.CFrame = cf
		end
	end
	return item
end

-- the storm's floor: dark cloud masses below the climber
PIECES.stormDeck = function()
	local item = newItem("StormDeck")
	item.anchor = "sky"
	item.spin = 0.01
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2 + 0.3
		local r = 150 + (i % 3) * 50
		local s = 110 + (i % 4) * 16
		addPart(item, { name = "StormDeckPuff", shape = BALL, size = Vector3.new(s, s * 0.6, s), color = rgb(64, 70, 88), transparency = 0.12, offset = CFrame.new(math.sin(a) * r, -110 - (i % 2) * 20, math.cos(a) * r) })
	end
	return item
end

-- a ringed planet, a small blue one and a constellation, far out in the night
PIECES.planets = function()
	local item = newItem("Planets")
	item.anchor = "sky"
	item.spin = 0.004
	addPart(item, { name = "RingedPlanet", shape = BALL, size = Vector3.new(180, 180, 180), color = rgb(222, 170, 116), offset = CFrame.new(520, 170, 700) })
	addPart(item, { name = "PlanetRing", shape = CYL, size = Vector3.new(2, 390, 390), color = rgb(236, 206, 160), transparency = 0.35, offset = CFrame.new(520, 170, 700) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(18), 0, math.rad(12)) })
	addPart(item, { name = "BluePlanet", shape = BALL, size = Vector3.new(64, 64, 64), color = rgb(96, 150, 236), offset = CFrame.new(-620, 250, 420) })
	-- a constellation: five stars joined by four thin lines
	local stars = { Vector3.new(-340, 380, 820), Vector3.new(-280, 430, 840), Vector3.new(-210, 400, 860), Vector3.new(-160, 460, 850), Vector3.new(-90, 420, 870) }
	for _, p in stars do
		addPart(item, { name = "ConstellationStar", shape = BALL, size = Vector3.new(7, 7, 7), color = rgb(255, 244, 214), material = Enum.Material.Neon, offset = CFrame.new(p) })
	end
	for i = 1, #stars - 1 do
		local a, b = stars[i], stars[i + 1]
		addPart(item, { name = "ConstellationLine", size = Vector3.new(0.8, 0.8, (b - a).Magnitude), color = rgb(190, 200, 255), material = Enum.Material.Neon, transparency = 0.45, offset = CFrame.lookAt(a:Lerp(b, 0.5), b) })
	end
	return item
end

-- the summit: a spiral galaxy far below
PIECES.galaxy = function()
	local item = newItem("Galaxy")
	item.anchor = "sky"
	item.centre = CFrame.new(0, -520, 260)
	item.spin = 0.02
	addPart(item, { name = "GalaxyCore", shape = BALL, size = Vector3.new(130, 60, 130), color = rgb(255, 232, 190), material = Enum.Material.Neon })
	addPart(item, { name = "GalaxyDisc", shape = CYL, size = Vector3.new(4, 900, 900), color = rgb(150, 110, 230), material = Enum.Material.Neon, transparency = 0.82, offset = UPRIGHT })
	local host = addHost(item, CFrame.new())
	for k = 0, 3 do
		local a = k * math.pi / 2
		addBeam(item, host, Vector3.new(math.sin(a) * 60, 0, math.cos(a) * 60), Vector3.new(math.sin(a + 1.9) * 430, 0, math.cos(a + 1.9) * 430), {
			color = ColorSequence.new(rgb(255, 236, 200), rgb(130, 110, 255)), width0 = 90, width1 = 40,
			curve0 = 240, curve1 = -140, transparency = 0.3, segments = 20, faceCamera = false,
		})
	end
	return item
end

-- the summit: a crown of ten golden stars circling the CLIMBER (anchored to them, not to the camera),
-- turning slowly. It fades in over the last stretch of floor 10 and never exists at a fork.
PIECES.crownRing = function()
	local item = newItem("CrownRing")
	item.anchor = "focus"
	item.centre = CFrame.new(0, 3.2, 0)
	item.spin = 0.6
	for i = 1, 10 do
		local a = (i - 1) / 10 * math.pi * 2
		addPart(item, { name = "CrownStar", shape = BALL, size = Vector3.new(1.1, 1.1, 1.1), color = rgb(255, 214, 110), material = Enum.Material.Neon, offset = CFrame.new(math.sin(a) * 4.2, math.sin(a * 3) * 0.35, math.cos(a) * 4.2) })
	end
	return item
end

-- ─────────────────────────────────────────────────────────────── critters (moving life)

local CRITTERS = {}

local function flapper(item, wing, color, rate, spread, material)
	addPart(item, { name = "WingL", size = wing, color = color, material = material })
	addPart(item, { name = "WingR", size = wing, color = color, material = material })
	item.animate = function(it, cf, now)
		local flap = math.sin(now * rate + (it.phase or 0)) * 0.55
		it.entries[1].part.CFrame = cf * CFrame.Angles(0, 0, 0.2 + flap) * CFrame.new(-spread, 0, 0)
		it.entries[2].part.CFrame = cf * CFrame.Angles(0, 0, -0.2 - flap) * CFrame.new(spread, 0, 0)
	end
end

CRITTERS.bat = function(item)
	flapper(item, Vector3.new(2, 0.12, 1), rgb(44, 34, 44), 16, 1)
end

CRITTERS.butterfly = function(item, rand)
	local palette = { rgb(255, 150, 200), rgb(255, 214, 90), rgb(140, 190, 255), rgb(255, 160, 80) }
	flapper(item, Vector3.new(1.3, 0.08, 1), palette[1 + math.floor(rand() * #palette) % #palette], 9, 0.62)
end

CRITTERS.firefly = function(item)
	addPart(item, { name = "Firefly", shape = BALL, size = Vector3.new(0.5, 0.5, 0.5), color = rgb(220, 255, 120), material = Enum.Material.Neon })
	item.animate = function(it, cf, now)
		it.entries[1].part.CFrame = cf * CFrame.new(0, math.sin(now * 2 + (it.phase or 0)) * 1.2, 0)
	end
end

CRITTERS.clockmoth = function(item)
	flapper(item, Vector3.new(1.6, 0.1, 1.1), rgb(214, 174, 94), 12, 0.8, Enum.Material.Metal)
end

local function tumble(spinX, spinY)
	return function(it, cf, now)
		local rot = CFrame.Angles(now * spinX + (it.phase or 0), now * spinY, 0)
		for _, e in it.entries do
			e.part.CFrame = cf * rot * e.offset
		end
	end
end

CRITTERS.leaf = function(item)
	addPart(item, { name = "Leaf", size = Vector3.new(1.4, 0.1, 0.9), color = rgb(122, 110, 60) })
	item.animate = tumble(2.4, 1.3)
end

CRITTERS.shootingStar = function(item)
	local p = addPart(item, { name = "ShootingStar", shape = BALL, size = Vector3.new(2, 2, 2), color = rgb(255, 240, 210), material = Enum.Material.Neon })
	addTrail(item, p, 1, { lifetime = 0.7, color = rgb(255, 230, 190), transparency = 0.1, lightEmission = 1 })
end

-- hazard-only models (never ambient)
local MODELS = {}

MODELS.bee = function(item)
	addPart(item, { name = "Body", shape = BALL, size = Vector3.new(2.6, 2.2, 3), color = rgb(255, 200, 50) })
	addPart(item, { name = "WingL", size = Vector3.new(2, 0.1, 1.2), color = rgb(240, 250, 255), transparency = 0.35 })
	addPart(item, { name = "WingR", size = Vector3.new(2, 0.1, 1.2), color = rgb(240, 250, 255), transparency = 0.35 })
	item.animate = function(it, cf, now)
		local flap = math.sin(now * 40) * 0.5
		it.entries[1].part.CFrame = cf
		it.entries[2].part.CFrame = cf * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, 0.3 + flap) * CFrame.new(-1.1, 0, 0)
		it.entries[3].part.CFrame = cf * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, -0.3 - flap) * CFrame.new(1.1, 0, 0)
	end
end

MODELS.seedpod = function(item)
	addPart(item, { name = "Pod", shape = BALL, size = Vector3.new(2.8, 2.8, 2.8), color = rgb(116, 126, 60), material = Enum.Material.Grass })
	addPart(item, { name = "SpikeA", size = Vector3.new(0.4, 4.4, 0.4), color = rgb(80, 70, 40), offset = CFrame.Angles(0, 0, math.rad(45)) })
	addPart(item, { name = "SpikeB", size = Vector3.new(0.4, 4.4, 0.4), color = rgb(80, 70, 40), offset = CFrame.Angles(math.rad(45), 0, 0) })
	item.animate = tumble(1.6, 0.9)
end

MODELS.cog = function(item)
	addPart(item, { name = "Disc", shape = CYL, size = Vector3.new(0.9, 4.6, 4.6), color = rgb(204, 162, 80), material = Enum.Material.Metal })
	addPart(item, { name = "Teeth", size = Vector3.new(1, 5.6, 1.3), color = rgb(92, 80, 68), material = Enum.Material.Metal })
	addPart(item, { name = "Hub", shape = BALL, size = Vector3.new(1.4, 1.4, 1.4), color = rgb(60, 52, 46), material = Enum.Material.Metal })
	-- the disc's axis points sideways (across the flight), so it rolls through the air
	item.animate = function(it, cf, now)
		local rot = cf * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(now * 9, 0, 0)
		for _, e in it.entries do
			e.part.CFrame = rot * e.offset
		end
	end
end

MODELS.clockbird = function(item)
	addPart(item, { name = "Body", size = Vector3.new(1.3, 1.3, 2.8), color = rgb(204, 162, 80), material = Enum.Material.Metal })
	addPart(item, { name = "WingL", size = Vector3.new(2.4, 0.15, 1.2), color = rgb(188, 112, 62), material = Enum.Material.Metal })
	addPart(item, { name = "WingR", size = Vector3.new(2.4, 0.15, 1.2), color = rgb(188, 112, 62), material = Enum.Material.Metal })
	item.animate = function(it, cf, now)
		local flap = math.sin(now * 13) * 0.5
		it.entries[1].part.CFrame = cf
		it.entries[2].part.CFrame = cf * CFrame.Angles(0, 0, 0.2 + flap) * CFrame.new(-1.3, 0, 0)
		it.entries[3].part.CFrame = cf * CFrame.Angles(0, 0, -0.2 - flap) * CFrame.new(1.3, 0, 0)
	end
end

MODELS.spark = function(item)
	local p = addPart(item, { name = "Spark", shape = BALL, size = Vector3.new(2.6, 2.6, 2.6), color = rgb(170, 210, 255), material = Enum.Material.Neon, transparency = 0.2 })
	addPart(item, { name = "Core", shape = BALL, size = Vector3.new(1.3, 1.3, 1.3), color = rgb(255, 255, 255), material = Enum.Material.Neon })
	addTrail(item, p, 1, { lifetime = 0.4, color = rgb(170, 210, 255), transparency = 0.2, lightEmission = 1 })
end

MODELS.debris = function(item)
	addPart(item, { name = "Tile", size = Vector3.new(3.2, 0.4, 2.2), color = rgb(148, 72, 58) })
	addPart(item, { name = "Plank", size = Vector3.new(0.5, 0.3, 3.4), color = rgb(120, 92, 60), material = Enum.Material.Wood, offset = CFrame.new(0.6, 0.3, 0) })
	item.animate = tumble(4, 2.5)
end

MODELS.meteor = function(item)
	local p = addPart(item, { name = "Meteor", shape = BALL, size = Vector3.new(2.8, 2.8, 2.8), color = rgb(255, 182, 110), material = Enum.Material.Neon })
	addTrail(item, p, 1.4, { lifetime = 0.6, color = rgb(255, 170, 100), transparency = 0.1, lightEmission = 1 })
end

MODELS.comet = function(item)
	local p = addPart(item, { name = "Comet", shape = BALL, size = Vector3.new(3.2, 3.2, 3.2), color = rgb(206, 240, 255), material = Enum.Material.Neon })
	addTrail(item, p, 1.6, { lifetime = 1.4, color = rgb(160, 220, 255), transparency = 0.15, lightEmission = 1 })
end

-- ─────────────────────────────────────────────────────────────── construction

function TowerArt.new(folder, rand, Config, EnvBands)
	local self = setmetatable({}, TowerArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.EnvBands = EnvBands
	self.pieces = {}
	self.critters = {}
	self.hazardModels = {}
	return self
end

function TowerArt.hasPiece(id)
	return PIECES[id] ~= nil or WALLS[id] ~= nil
end

function TowerArt.hasCritter(kind)
	return CRITTERS[kind] ~= nil
end

-- Show piece `id` at weight w. cam: the camera position (Vector3); laneX: the lane's centre line;
-- focus: the climber's root position (pieces anchored "focus" ride with them).
function TowerArt:updatePiece(id, w, cam, now, laneX, focus)
	local item = self.pieces[id]
	if item == nil then
		if w <= 0.01 then return end
		if WALLS[id] then
			item = wallItem(self, id, WALLS[id])
		elseif PIECES[id] then
			item = PIECES[id]()
		else
			return
		end
		self.pieces[id] = item
	end
	setWeight(item, w, self.folder)
	if not item.shown then return end
	if item.anchor == "walls" then
		placeWall(self, item, cam, laneX or cam.X)
		-- fading every frame (writes only on a visible change), turning at most every 1/20 s
		local dt = math.clamp(now - (item.lastNow or now), 0, 0.25)
		item.lastNow = now
		fadeWall(item, cam, dt, self.EnvBands)
		if now - (item.spunAt or -1) >= 0.05 then
			item.spunAt = now
			for _, e in item.entries do
				if e.spinner and not e.hidden then
					e.part.CFrame = e.home * CFrame.Angles(now * e.spinner, 0, 0)
				end
			end
		end
	else -- "sky": travels with the camera, like a skybox with depth; "focus": rides with the climber
		local root = CFrame.new(if item.anchor == "focus" and focus then focus else cam)
		if item.centre then root = root * item.centre end
		if item.spin then root = root * CFrame.Angles(0, now * item.spin, 0) end
		if item.animate then item.animate(item, root, now) else place(item, root) end
	end
end

-- ─────────────────────────────────────────────── critters: pooled, spawned on a ring, recycled

local function buildCritter(self, kind)
	local item = newItem(kind)
	CRITTERS[kind](item, self.rand)
	return item
end

function TowerArt:critterList(kind)
	local list = self.critters[kind]
	if list == nil then
		list = {}
		self.critters[kind] = list
	end
	return list
end

-- desired: { [kind] = count }. Called every frame.
function TowerArt:updateCritters(desired, cam, dt, now)
	local E = self.EnvBands
	local specs = self.cfg.Env.Critters
	local camV = { x = cam.X, y = cam.Y, z = cam.Z }
	for kind in desired do self:critterList(kind) end
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
		-- spawn at most one group per kind per frame (staggered, never a pop of ten)
		if active < want and spec then
			local group = math.min(spec.flock or 1, want - active)
			local base = E.ambientSpawn(camV, spec, self.rand)
			for g = 1, group do
				local c = nil
				for _, existing in list do
					if not existing.active then c = existing; break end
				end
				if c == nil then
					c = { item = buildCritter(self, kind), active = false }
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

-- ─────────────────────────────────────────────── hazards + their telegraph

function TowerArt.hazardKinds()
	local out = {}
	for k in MODELS do out[k] = true end
	return out
end

function TowerArt:hazardModel(kind)
	local item = self.hazardModels[kind]
	if item then return item end
	item = newItem("Hazard_" .. kind)
	MODELS[kind](item)
	local main = item.entries[1].part
	-- visible from anywhere, even through cloud: the warning marker
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
	light.Color = rgb(255, 80, 60)
	light.Range = 22
	light.Brightness = 2
	light.Enabled = false
	light.Parent = main
	table.insert(item.lights, light)
	for _, e in item.entries do e.part.Name = "Hazard_" .. kind .. "_" .. e.part.Name end
	self.hazardModels[kind] = item
	return item
end

function TowerArt:laneItem()
	if self.lane then return self.lane end
	local item = newItem("HazardLane")
	addPart(item, { name = "HazardLane", size = Vector3.new(0.35, 0.35, 10), color = rgb(255, 210, 60), material = Enum.Material.Neon, transparency = 0.45 })
	addPart(item, { name = "HazardZone", shape = CYL, size = Vector3.new(0.3, 8, 8), color = rgb(255, 210, 60), material = Enum.Material.Neon, transparency = 0.55 })
	self.lane = item
	return item
end

-- Draw the hazard for this frame. `zone` is Hazards.zone(plan, PlayerRadius): the ring is drawn
-- exactly there, because it IS the hit rule (a hit needs the player inside it).
function TowerArt:showHazard(plan, pos, now, zone)
	local item = self:hazardModel(plan.kind)
	setWeight(item, 1, self.folder)
	item.billboard.Enabled = not plan.locked or (math.floor(now * 6) % 2 == 0)
	item.lights[1].Enabled = math.floor(now * 4) % 2 == 0
	local p = Vector3.new(pos.x, pos.y, pos.z)
	local v = Vector3.new(plan.velocity.x, plan.velocity.y, plan.velocity.z)
	local hv = Vector3.new(v.X, 0, v.Z)
	local cf = CFrame.lookAt(p, if hv.Magnitude > 0.01 then p + hv else p + Vector3.new(0, 0, -1))
	if item.animate then item.animate(item, cf, now) else place(item, cf) end

	local lane = self:laneItem()
	local target = Vector3.new(plan.target.x, plan.target.y, plan.target.z)
	local beyond = target + (if v.Magnitude > 0 then v.Unit * 30 else Vector3.zero)
	local len = (beyond - p).Magnitude
	if plan.t > plan.arriveAt or len < 1 then
		setWeight(lane, 0, self.folder)
		return
	end
	setWeight(lane, 1, self.folder)
	local colour = if plan.locked then rgb(255, 60, 60) else rgb(255, 210, 60)
	local laneE, zoneE = lane.entries[1], lane.entries[2]
	laneE.part.Color = colour
	laneE.part.Size = Vector3.new(0.35, 0.35, len)
	laneE.part.CFrame = CFrame.lookAt(p:Lerp(beyond, 0.5), beyond)
	local d = 2 * zone.radius
	zoneE.part.Color = colour
	zoneE.part.Size = Vector3.new(0.3, d, d)
	zoneE.part.CFrame = CFrame.new(zone.x, zone.y - 3, zone.z) * UPRIGHT
end

function TowerArt:hideHazard(kind)
	local item = self.hazardModels[kind]
	if item then
		item.billboard.Enabled = false
		setWeight(item, 0, self.folder)
	end
	if self.lane then setWeight(self.lane, 0, self.folder) end
end

-- ─────────────────────────────────────────────── weather + lightning

local WEATHER = {
	embers = { Color = { 255, 150, 70 }, Size = 0.22, Lifetime = { 4, 6 }, Speed = { 1, 2.5 }, LightEmission = 1, Acceleration = Vector3.new(0.3, 1.2, 0.2), Transparency = 0.15 },
	pollen = { Color = { 255, 240, 170 }, Size = 0.3, Lifetime = { 6, 9 }, Speed = { 0.5, 1.5 }, LightEmission = 0.4, Acceleration = Vector3.new(0.4, -0.3, 0.2), Transparency = 0.2 },
	sparks = { Color = { 255, 196, 100 }, Size = 0.18, Lifetime = { 1.2, 2 }, Speed = { 4, 8 }, LightEmission = 1, Acceleration = Vector3.new(0, -12, 0), Transparency = 0.1 },
	rain = { Color = { 190, 200, 230 }, Size = 0.15, Lifetime = { 1, 1.4 }, Speed = { 90, 110 }, LightEmission = 0.2, Acceleration = Vector3.new(0, -40, 0), Transparency = 0.35, streak = true },
	stardust = { Color = { 200, 212, 255 }, Size = 0.28, Lifetime = { 5, 8 }, Speed = { 0.2, 0.8 }, LightEmission = 1, Acceleration = Vector3.zero, Transparency = 0.2 },
}

function TowerArt.hasWeather(kind)
	return WEATHER[kind] ~= nil
end

-- rates: { [kind] = particles per second }. The host rides above the camera. The budget is enforced
-- here: at most MaxWeatherEmitters on, summed rate at most MaxEmitterRate (EnvBands.capRates).
function TowerArt:updateWeather(rates, cam)
	if self.weatherHost == nil then
		local host = Instance.new("Part")
		host.Name = "WeatherHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = Vector3.new(120, 2, 120)
		self.weatherHost = host
		self.emitters = {}
	end
	local budget = self.cfg.Budget or {}
	local capped = self.EnvBands.capRates(rates, math.min(budget.MaxWeatherEmitters or 2, budget.MaxEmitters or 2),
		budget.MaxEmitterRate or 50, 0.05)
	local anyOn = false
	for kind, def in WEATHER do
		local rate = capped[kind] or 0
		local pe = self.emitters[kind]
		if pe == nil and rate > 0.05 then
			pe = Instance.new("ParticleEmitter")
			pe.Name = "Weather_" .. kind
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
			pe.SpreadAngle = if def.streak then Vector2.new(4, 4) else Vector2.new(180, 180)
			pe.EmissionDirection = if def.streak then Enum.NormalId.Bottom else Enum.NormalId.Top
			if def.streak then pe.Orientation = Enum.ParticleOrientation.VelocityParallel end
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
		self.weatherHost.CFrame = CFrame.new(cam + Vector3.new(0, 26, 0))
	else
		self.weatherHost.Parent = nil
	end
end

function TowerArt:flashBolt(cam, visible)
	if self.bolt == nil then
		local item = newItem("Lightning")
		for _ = 1, 5 do
			addPart(item, { name = "Bolt", size = Vector3.new(1.4, 1.4, 60), color = rgb(220, 230, 255), material = Enum.Material.Neon })
		end
		self.bolt = item
	end
	if not visible then
		setWeight(self.bolt, 0, self.folder)
		return
	end
	local r = self.rand
	local a = r() * math.pi * 2
	local d = 260 + r() * 300
	local p = cam + Vector3.new(math.sin(a) * d, 200, math.cos(a) * d)
	for _, e in self.bolt.entries do
		local nextP = p + Vector3.new((r() - 0.5) * 60, -80 - r() * 40, (r() - 0.5) * 60)
		e.part.Size = Vector3.new(1.4, 1.4, (nextP - p).Magnitude)
		e.part.CFrame = CFrame.lookAt(p:Lerp(nextP, 0.5), nextP)
		p = nextP
	end
	setWeight(self.bolt, 1, self.folder)
end

return TowerArt
