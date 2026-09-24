-- WingArt.luau — Lost & Found Depot's wings, built in code (no assets). CLIENT ONLY: required by
-- src/client/Wings.client.luau; the server never touches it.
--
-- Everything here is LOCAL decoration: anchored, CanCollide/CanQuery/CanTouch off (so the camera never
-- pops in front of it, a tap passes straight through it and nothing can be stood on), CastShadow off.
-- Nothing is built until a wing first needs it, and anything whose weight falls to zero is UNPARENTED,
-- so a wing you are not in costs no draw calls. It lives in its own workspace folder, never in a bay.
--
-- WHERE THINGS GO, so the job stays readable (robloxemu/check_lostfounddepot_wings.luau measures it):
--   * inside the bay's walls (x -36..36, z -36..20, the 16-stud walls): only the wing SIGNS, flush on a
--     wall face in the free stretches beside the manual, memo, backlog and name boards; the hazard, its
--     ring and its lane while one is in flight; the invisible weather host and its particles (particles
--     are not parts);
--   * overhead (OVERHEAD below): roof frames, lights and domes, every part above the wall tops (y >= 16;
--     the train shed and the station dome rest their feet on the walls). The client fades them out as
--     the camera rises to Config.Env.OverheadFade.Gone (16), so a camera that shows any roof is below
--     all of it and never looks down at a tag through it;
--   * far out: landmarks 150-1500 studs away, tall enough to show over the walls.
--
-- The top level makes no Roblox call, so the luau CLI can require this file for its id lists
-- (tests/EnvConfig.spec.luau checks every id Config names exists here).
--
-- Dependencies arrive as arguments (a bare require("./X") is invalid in Roblox):
--   WingArt.new(folder, rand, Config, EnvBands)

local WingArt = {}
WingArt.__index = WingArt

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end
local function V(x, y, z)
	return Vector3.new(x, y, z)
end

-- ─────────────────────────────────────────── items: parts that fade together (the +1 Jump pattern)

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
	p.Color = if props.color then rgb(props.color) else Color3.new(1, 1, 1)
	if props.shape then p.Shape = props.shape end
	p.Size = props.size or V(1, 1, 1)
	p.Transparency = 1
	local entry = { part = p, base = props.transparency or 0, offset = props.offset or CFrame.new(), lastT = 1, role = props.role }
	table.insert(item.entries, entry)
	return p, entry
end

-- A straight member from a to b (item-local), `thick` studs square.
local function member(item, a, b, thick, color, props)
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local dir = (b - a).Unit
	local up = if math.abs(dir.Y) > 0.95 then V(1, 0, 0) else V(0, 1, 0)
	local p = props or {}
	return addPart(item, {
		name = p.name or item.name,
		size = V(thick, thick, len),
		offset = CFrame.lookAt(mid, b, up),
		color = color,
		material = p.material,
		transparency = p.transparency,
		role = p.role,
	})
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
	for _, pe in item.emitters do pe.Enabled = w > 0.3 end
end

local function place(item, root)
	for _, e in item.entries do
		e.part.CFrame = root * e.offset
	end
end

local function addHost(item, offset)
	return addPart(item, { name = item.name .. "Host", size = V(1, 1, 1), transparency = 1, offset = offset })
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
	beam.Color = ColorSequence.new(rgb(props.color))
	beam.Width0 = props.width0 or 40
	beam.Width1 = props.width1 or 40
	beam.CurveSize0 = props.curve0 or 0
	beam.CurveSize1 = props.curve1 or 0
	beam.LightEmission = 1
	beam.FaceCamera = false
	beam.Segments = 16
	beam.Enabled = false
	beam.Parent = host
	table.insert(item.beams, { beam = beam, base = props.transparency or 0.5 })
	return beam
end

local function addTrail(item, p, halfWidth, color, lifetime)
	local a0 = Instance.new("Attachment")
	a0.Position = V(0, halfWidth, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = V(0, -halfWidth, 0)
	a1.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Color = ColorSequence.new(rgb(color))
	tr.Lifetime = lifetime
	tr.LightEmission = 1
	tr.Transparency = NumberSequence.new(0.2, 1)
	tr.Enabled = false
	tr.Parent = p
	table.insert(item.trails, tr)
	return tr
end

-- A one-sided sign (the bay's own board() recipe): the Part is invisible, the SurfaceGui's opaque
-- background on `face` is the board, so it hides nothing behind it and shows nothing from behind.
local function addSign(item, size, offset, face, text, colors)
	local p = addPart(item, { name = item.name .. "Sign", size = size, offset = offset, transparency = 1, color = colors.board })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = rgb(colors.board)
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = rgb(colors.text)
	label.Text = text
	label.Parent = gui
	gui.Parent = p
	return p, label
end

-- ─────────────────────────────────────────────────────────────── colours (arrays: no Roblox at load)

local STEEL = { 120, 126, 138 }
local DARK = { 40, 42, 50 }
local WHITE = { 240, 240, 236 }
local GLASS = { 170, 210, 235 }
local BRASS = { 210, 170, 70 }
local BULBS = { { 255, 90, 90 }, { 255, 215, 60 }, { 80, 220, 110 }, { 110, 170, 255 }, { 240, 120, 200 } }
-- Roblox enums and one CFrame, filled in by WingArt.new (the luau CLI has neither, and only needs the
-- id lists below). UPRIGHT turns a cylinder (which runs along X) to run along Y.
local NEON, GLASSM, METAL, BALL, CYL, UPRIGHT
local function initRoblox()
	if UPRIGHT ~= nil then return end
	NEON = Enum.Material.Neon
	GLASSM = Enum.Material.Glass
	METAL = Enum.Material.Metal
	BALL = Enum.PartType.Ball
	CYL = Enum.PartType.Cylinder
	UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
end

-- ─────────────────────────────────────────────────────────────── pieces
-- Each builder returns an item; offsets are BAY-LOCAL (x -36..36, z -36..20, floor top y = 0) and the
-- item is placed at CFrame.new(bayOriginX, 0, 0). `animate(item, root, now)` moves the parts that move.

local PIECES = {}

-- CITY DEPOT: steel trusses over the open bay with four warm hanging lamps (Neon, no lights).
PIECES.cityRoof = function()
	local it = newItem("CityRoof")
	for _, z in { -32, -20, -8, 4, 16 } do
		member(it, V(-37, 24, z), V(37, 24, z), 0.8, STEEL, { material = METAL })
		member(it, V(-37, 20.4, z), V(37, 20.4, z), 0.6, STEEL, { material = METAL })
	end
	for _, x in { -18, 18 } do
		member(it, V(x, 24.7, -34), V(x, 24.7, 18), 0.6, STEEL, { material = METAL })
	end
	for _, at in { { -14, -14 }, { 14, -14 }, { -14, 10 }, { 14, 10 } } do
		local x, z = at[1], at[2]
		member(it, V(x, 20.1, z), V(x, 24.4, z), 0.15, DARK)
		addPart(it, { size = V(0.8, 2.4, 2.4), offset = CFrame.new(x, 19.5, z) * UPRIGHT, color = { 60, 90, 70 }, shape = CYL, material = METAL })
		addPart(it, { size = V(0.9, 0.9, 0.9), offset = CFrame.new(x, 18.9, z), color = { 255, 214, 150 }, shape = BALL, material = NEON })
	end
	return it
end

-- CITY DEPOT: a skyline in front and behind, lit windows as a Neon band on each tower.
PIECES.citySkyline = function()
	local it = newItem("CitySkyline")
	local towers = {
		{ -260, -300, 50, 150 }, { -140, -380, 60, 190 }, { -20, -260, 40, 120 }, { 90, -340, 55, 170 }, { 220, -290, 45, 140 },
		{ -220, 280, 50, 130 }, { -80, 360, 60, 175 }, { 60, 250, 40, 110 }, { 190, 330, 55, 160 }, { 320, 300, 45, 125 },
	}
	for i, t in towers do
		local x, z, w, h = t[1], t[2], t[3], t[4]
		local body = if i % 3 == 0 then { 150, 160, 175 } elseif i % 3 == 1 then { 120, 130, 150 } else { 175, 170, 160 }
		addPart(it, { size = V(w, h, w), offset = CFrame.new(x, h / 2, z), color = body, material = Enum.Material.Concrete })
		local face = if z < 0 then 1 else -1
		addPart(it, { size = V(w * 0.8, h * 0.55, 0.4), offset = CFrame.new(x, h * 0.55, z + face * (w / 2 + 0.3)),
			color = { 255, 226, 150 }, material = NEON, transparency = 0.55 })
	end
	return it
end

-- AIRPORT: a glass terminal roof on steel ribs, and a departures board hung over the arc.
PIECES.airportRoof = function()
	local it = newItem("AirportRoof")
	for _, z in { -30, -12, 6 } do
		member(it, V(-37, 18.5, z), V(-18, 26, z), 0.8, WHITE, { material = METAL })
		member(it, V(-18, 26, z), V(18, 26, z), 0.8, WHITE, { material = METAL })
		member(it, V(18, 26, z), V(37, 18.5, z), 0.8, WHITE, { material = METAL })
	end
	local slope = math.atan2(7.5, 19)
	addPart(it, { size = V(20.4, 0.3, 58), offset = CFrame.new(-27.5, 22.6, -8) * CFrame.Angles(0, 0, slope), color = GLASS, material = GLASSM, transparency = 0.72 })
	addPart(it, { size = V(36, 0.3, 58), offset = CFrame.new(0, 26.4, -8), color = GLASS, material = GLASSM, transparency = 0.72 })
	addPart(it, { size = V(20.4, 0.3, 58), offset = CFrame.new(27.5, 22.6, -8) * CFrame.Angles(0, 0, -slope), color = GLASS, material = GLASSM, transparency = 0.72 })
	member(it, V(-6, 22.5, -12), V(-6, 25.6, -12), 0.15, DARK)
	member(it, V(6, 22.5, -12), V(6, 25.6, -12), 0.15, DARK)
	local _, label = addSign(it, V(16, 4, 0.4), CFrame.new(0, 20.5, -12), Enum.NormalId.Back,
		"ARRIVALS\nLOST PROPERTY  B3  ON TIME", { board = { 20, 22, 30 }, text = { 255, 200, 60 } })
	it.label = label
	return it
end

-- AIRPORT: control tower with a blinking beacon, a hangar and a terminal behind the front wall.
PIECES.airfield = function()
	local it = newItem("Airfield")
	addPart(it, { size = V(110, 14, 14), offset = CFrame.new(-160, 55, -320) * UPRIGHT, color = { 200, 200, 196 }, shape = CYL, material = Enum.Material.Concrete })
	addPart(it, { size = V(28, 12, 28), offset = CFrame.new(-160, 116, -320), color = { 90, 150, 190 }, material = GLASSM, transparency = 0.2 })
	addPart(it, { size = V(32, 2, 32), offset = CFrame.new(-160, 123, -320), color = WHITE })
	addPart(it, { size = V(0.8, 16, 0.8), offset = CFrame.new(-160, 132, -320), color = DARK })
	local _, beacon = addPart(it, { size = V(2, 2, 2), offset = CFrame.new(-160, 141, -320), color = { 255, 40, 40 }, shape = BALL, material = NEON })
	it.beacon = beacon
	addPart(it, { size = V(100, 46, 80), offset = CFrame.new(170, 23, -300), color = { 150, 155, 165 }, material = METAL })
	addPart(it, { size = V(90, 30, 1), offset = CFrame.new(170, 20, -259.4), color = { 60, 64, 72 }, material = METAL })
	addPart(it, { size = V(240, 96, 40), offset = CFrame.new(40, 48, 280), color = { 210, 214, 220 }, material = Enum.Material.Concrete })
	addPart(it, { size = V(236, 40, 1), offset = CFrame.new(40, 62, 259.4), color = { 80, 150, 210 }, material = GLASSM, transparency = 0.25 })
	it.animate = function(item, _root, now)
		-- blinks by colour, so it never fights setWeight over Transparency
		local on = math.floor(now * 1.25) % 2 == 0
		if item.beaconOn ~= on then
			item.beaconOn = on
			item.beacon.part.Color = if on then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(70, 20, 20)
		end
	end
	return it
end

-- TRAIN STATION: an arched iron-and-glass shed over the bay, with a station clock on the ridge.
local function arch(item, z, rise, color, thick)
	local pts = {}
	for k = 0, 6 do
		local a = math.pi * k / 6
		table.insert(pts, V(-37 * math.cos(a), 16.5 + rise * math.sin(a), z))
	end
	for k = 1, 6 do
		member(item, pts[k], pts[k + 1], thick, color, { material = METAL })
	end
end
PIECES.trainShed = function()
	local it = newItem("TrainShed")
	for _, z in { -32, -16, 0, 16 } do
		arch(it, z, 18, { 70, 84, 80 }, 0.9)
	end
	member(it, V(0, 34.6, -34), V(0, 34.6, 18), 0.7, { 70, 84, 80 }, { material = METAL })
	for _, side in { -1, 1 } do
		for _, seg in { { 37, 16.5, 26, 28.2 }, { 26, 28.2, 0.1, 34.4 } } do
			local x1, y1, x2, y2 = seg[1] * side, seg[2], seg[3] * side, seg[4]
			local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
			local ang = math.atan2(y2 - y1, x2 - x1)
			addPart(it, { size = V(len, 0.25, 50), offset = CFrame.new((x1 + x2) / 2, (y1 + y2) / 2 + 0.6, -8) * CFrame.Angles(0, 0, ang),
				color = { 200, 225, 225 }, material = GLASSM, transparency = 0.8 })
		end
	end
	-- the clock: a face toward the tray side (+Z), hung from the ridge over the arc
	member(it, V(0, 30.6, -20), V(0, 34.2, -20), 0.2, DARK)
	addPart(it, { size = V(0.6, 7, 7), offset = CFrame.new(0, 27, -20) * CFrame.Angles(0, math.rad(90), 0), color = WHITE, shape = CYL })
	addPart(it, { size = V(0.4, 7.8, 7.8), offset = CFrame.new(0, 27, -20.15) * CFrame.Angles(0, math.rad(90), 0), color = BRASS, shape = CYL, material = METAL })
	local _, hour = addPart(it, { size = V(0.3, 2, 0.1), offset = CFrame.new(0, 27, -19.6), color = DARK, role = "hour" })
	local _, minute = addPart(it, { size = V(0.2, 3, 0.1), offset = CFrame.new(0, 27, -19.55), color = DARK, role = "minute" })
	it.hour, it.minute = hour, minute
	it.animate = function(item, root, now)
		-- one lap of the minute hand per real minute: a clock that visibly runs. Each hand turns about the
		-- clock's centre (0, 27) in its own plane, seen from the tray side.
		local m = (now / 60) * 2 * math.pi
		local h = m / 12
		item.minute.part.CFrame = root * CFrame.new(0, 27, -19.55) * CFrame.Angles(0, 0, -m) * CFrame.new(0, 1.5, 0)
		item.hour.part.CFrame = root * CFrame.new(0, 27, -19.6) * CFrame.Angles(0, 0, -h) * CFrame.new(0, 1.0, 0)
	end
	return it
end

-- TRAIN STATION: a viaduct behind the back wall with a train crossing it, a clock tower in front.
-- The deck is 70 studs up and 150 out: high enough that a sorting camera sees it over the 16-stud back wall
-- (check_lostfounddepot_wingview measures every landmark's biggest part over the walls).
local DECK_Y, DECK_Z = 70, -150
PIECES.viaduct = function()
	local it = newItem("Viaduct")
	addPart(it, { size = V(900, 3, 12), offset = CFrame.new(0, DECK_Y - 1.5, DECK_Z), color = { 150, 120, 100 }, material = Enum.Material.Brick })
	for _, x in { -330, -200, -70, 60, 190, 320 } do
		addPart(it, { size = V(8, DECK_Y - 3, 8), offset = CFrame.new(x, (DECK_Y - 3) / 2, DECK_Z), color = { 140, 110, 92 }, material = Enum.Material.Brick })
	end
	addPart(it, { size = V(22, 130, 22), offset = CFrame.new(110, 65, 240), color = { 150, 118, 96 }, material = Enum.Material.Brick })
	addPart(it, { size = V(0.6, 16, 16), offset = CFrame.new(110, 110, 228.6) * CFrame.Angles(0, math.rad(90), 0), color = WHITE, shape = CYL })
	addPart(it, { size = V(16, 14, 16), offset = CFrame.new(110, 137, 240) * CFrame.Angles(0, math.rad(45), 0), color = { 60, 70, 66 }, material = METAL })
	-- the train: loco + three carriages, moved along the deck by animate()
	local cars = {
		{ V(14, 8, 7), { 40, 90, 60 }, "loco" }, { V(20, 7, 6.5), { 150, 40, 40 } }, { V(20, 7, 6.5), { 150, 40, 40 } }, { V(20, 7, 6.5), { 150, 40, 40 } },
	}
	it.cars = {}
	for i, c in cars do
		local p, e = addPart(it, { name = "TrainCar", size = c[1], offset = CFrame.new(0, DECK_Y + 4, DECK_Z), color = c[2], material = METAL, role = "car" })
		it.cars[i] = { entry = e, len = c[1].X }
		if c[3] == "loco" then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "Smoke"
			pe.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
			pe.Size = NumberSequence.new(3, 9)
			pe.Transparency = NumberSequence.new(0.3, 1)
			pe.Lifetime = NumberRange.new(2, 3)
			pe.Speed = NumberRange.new(6, 9)
			pe.Acceleration = V(0, 3, 0)
			pe.Rate = 4
			pe.EmissionDirection = Enum.NormalId.Top
			pe.Enabled = false
			pe.Parent = p
			table.insert(it.emitters, pe)
		end
	end
	it.animate = function(item, root, now)
		-- 42 studs/s, one pass every 30 s, wrapping 450 studs either side of the bay
		local head = ((now * 42) % 1260) - 450
		local x = head
		for _, c in item.cars do
			local cx = x - c.len / 2
			c.entry.part.CFrame = root * CFrame.new(cx, DECK_Y + c.entry.part.Size.Y / 2, DECK_Z)
			x -= c.len + 1
		end
	end
	return it
end

-- THEME PARK: string lights over the bay, each bulb Neon in a festival colour.
PIECES.parkLights = function()
	local it = newItem("ParkLights")
	for s, z in { -26, -8, 10 } do
		local sag = 18.8
		member(it, V(-37, 22, z), V(0, sag, z), 0.12, DARK)
		member(it, V(0, sag, z), V(37, 22, z), 0.12, DARK)
		for k = 1, 5 do
			local x = -30 + (k - 1) * 15
			local y = sag + (22 - sag) * (math.abs(x) / 37) - 0.5
			addPart(it, { size = V(0.9, 0.9, 0.9), offset = CFrame.new(x, math.max(18.2, y), z), color = BULBS[((k + s) % #BULBS) + 1], shape = BALL, material = NEON })
		end
	end
	return it
end

-- THEME PARK: a turning ferris wheel and a loop coaster behind the back wall, a big top in front.
PIECES.parkRides = function()
	local it = newItem("ParkRides")
	local hub = V(-90, 78, -230)
	addPart(it, { size = V(4, 6, 6), offset = CFrame.new(hub), color = WHITE, shape = CYL, material = METAL })
	member(it, V(-90 - 35, 0, -236), hub + V(0, 0, -6), 2.4, WHITE, { material = METAL })
	member(it, V(-90 + 35, 0, -236), hub + V(0, 0, -6), 2.4, WHITE, { material = METAL })
	it.wheel = { hub = hub, rim = {}, spokes = {}, cars = {} }
	for k = 1, 10 do
		-- chord of a 60-stud radius in 10 steps: 2 x 60 x sin(18 degrees) = 37.08
		local _, e = addPart(it, { name = "WheelRim", size = V(1.6, 1.6, 37.1), color = { 255, 120, 180 }, material = NEON, transparency = 0.1, role = "rim" })
		it.wheel.rim[k] = e
	end
	for k = 1, 5 do
		local _, e = addPart(it, { name = "WheelSpoke", size = V(0.8, 0.8, 120), color = WHITE, material = METAL, role = "spoke" })
		it.wheel.spokes[k] = e
		local _, g = addPart(it, { name = "Gondola", size = V(6, 6, 6), color = BULBS[k], role = "car" })
		it.wheel.cars[k] = g
	end
	-- the coaster loop, in the y-z plane
	local centre = V(150, 52, -270)
	local pts = {}
	for k = 0, 8 do
		local a = 2 * math.pi * k / 8
		table.insert(pts, centre + V(0, math.sin(a) * 30, math.cos(a) * 30))
	end
	for k = 1, 8 do
		member(it, pts[k], pts[k + 1], 2, { 90, 180, 255 }, { material = METAL })
	end
	member(it, V(150, 0, -270), V(150, 21, -270), 2, WHITE)
	member(it, V(150, 0, -300), V(150, 52, -300), 1.6, WHITE)
	-- the big top, seen when you walk back to the tray
	addPart(it, { size = V(30, 80, 80), offset = CFrame.new(60, 15, 260) * UPRIGHT, color = { 230, 60, 60 }, shape = CYL })
	addPart(it, { size = V(24, 60, 60), offset = CFrame.new(60, 42, 260) * UPRIGHT, color = WHITE, shape = CYL })
	addPart(it, { size = V(14, 30, 30), offset = CFrame.new(60, 60, 260) * UPRIGHT, color = { 230, 60, 60 }, shape = CYL })
	addPart(it, { size = V(0.6, 18, 0.6), offset = CFrame.new(60, 76, 260), color = DARK })
	it.animate = function(item, root, now)
		-- about one turn a minute; parts written at most 20 times a second
		if item.nextSpin and now < item.nextSpin then return end
		item.nextSpin = now + 0.05
		local w = item.wheel
		local spin = now * 2 * math.pi / 60
		local R = 60
		for k, e in w.rim do
			local a0 = spin + 2 * math.pi * (k - 1) / #w.rim
			local a1 = spin + 2 * math.pi * k / #w.rim
			local p0 = w.hub + V(math.cos(a0) * R, math.sin(a0) * R, 0)
			local p1 = w.hub + V(math.cos(a1) * R, math.sin(a1) * R, 0)
			e.part.CFrame = root * CFrame.lookAt((p0 + p1) / 2, p1, V(0, 0, 1))
		end
		for k, e in w.spokes do
			local a = spin + math.pi * (k - 1) / #w.spokes
			local p0 = w.hub + V(math.cos(a) * R, math.sin(a) * R, 0)
			local p1 = w.hub - V(math.cos(a) * R, math.sin(a) * R, 0)
			e.part.CFrame = root * CFrame.lookAt((p0 + p1) / 2, p1, V(0, 0, 1))
			local g = w.cars[k]
			local ga = spin + 2 * math.pi * (k - 1) / #w.cars
			g.part.CFrame = root * CFrame.new(w.hub + V(math.cos(ga) * R, math.sin(ga) * R - 4, 0))
		end
	end
	return it
end

-- SPACE STATION (and beyond): white ribs over the bay with blue running lights.
PIECES.stationDome = function()
	local it = newItem("StationDome")
	for _, z in { -32, -20, -8, 4, 16 } do
		member(it, V(-37, 16.5, z), V(-30, 27, z), 1, WHITE, { material = METAL })
		member(it, V(-30, 27, z), V(30, 27, z), 1, WHITE, { material = METAL })
		member(it, V(30, 27, z), V(37, 16.5, z), 1, WHITE, { material = METAL })
		addPart(it, { size = V(40, 0.3, 0.3), offset = CFrame.new(0, 26.3, z), color = { 90, 180, 255 }, material = NEON })
	end
	member(it, V(-30, 27.8, -34), V(-30, 27.8, 18), 0.8, { 200, 204, 212 }, { material = METAL })
	member(it, V(30, 27.8, -34), V(30, 27.8, 18), 0.8, { 200, 204, 212 }, { material = METAL })
	return it
end

-- SPACE STATION: the Earth over the back wall (with its cloud shell and airglow), solar wings in front.
PIECES.earthView = function()
	local it = newItem("EarthView")
	local c = V(200, 330, -1500)
	addPart(it, { size = V(900, 900, 900), offset = CFrame.new(c), color = { 40, 90, 170 }, shape = BALL })
	addPart(it, { size = V(914, 914, 914), offset = CFrame.new(c), color = WHITE, shape = BALL, transparency = 0.72 })
	addPart(it, { size = V(960, 960, 960), offset = CFrame.new(c), color = { 110, 180, 255 }, shape = BALL, material = NEON, transparency = 0.9 })
	member(it, V(-180, 70, 190), V(180, 70, 190), 3, { 200, 204, 212 }, { material = METAL })
	for _, x in { -140, -70, 70, 140 } do
		addPart(it, { size = V(56, 1, 28), offset = CFrame.new(x, 70, 190) * CFrame.Angles(math.rad(70), 0, 0), color = { 40, 60, 140 }, material = GLASSM })
	end
	addPart(it, { size = V(60, 18, 18), offset = CFrame.new(-120, 40, -170), color = WHITE, shape = CYL, material = METAL })
	return it
end

-- BEYOND THE GALAXY: a spiral galaxy (disc, core, curved arms as Beams), a ringed planet, a nebula.
PIECES.galaxyView = function()
	local it = newItem("GalaxyView")
	local c = V(-150, 420, -1600)
	local tilt = CFrame.new(c) * CFrame.Angles(math.rad(62), 0, math.rad(18))
	addPart(it, { size = V(10, 1400, 1400), offset = tilt * CFrame.Angles(0, 0, math.rad(90)), color = { 150, 90, 220 }, shape = CYL, material = NEON, transparency = 0.86 })
	addPart(it, { size = V(160, 160, 160), offset = CFrame.new(c), color = { 255, 230, 180 }, shape = BALL, material = NEON, transparency = 0.2 })
	local host = addHost(it, tilt)
	for k = 0, 3 do
		local a = k * math.pi / 2
		addBeam(it, host, V(0, 0, 0), V(math.cos(a) * 640, 0, math.sin(a) * 640), {
			color = if k % 2 == 0 then { 190, 140, 255 } else { 120, 170, 255 }, width0 = 120, width1 = 30, curve0 = 260, curve1 = -120, transparency = 0.35 })
	end
	addPart(it, { size = V(260, 260, 260), offset = CFrame.new(620, 260, 900), color = { 210, 150, 90 }, shape = BALL })
	addPart(it, { size = V(4, 520, 520), offset = CFrame.new(620, 260, 900) * CFrame.Angles(math.rad(20), 0, math.rad(80)), color = { 230, 200, 160 }, shape = CYL, transparency = 0.35 })
	addPart(it, { size = V(700, 700, 700), offset = CFrame.new(-900, 300, 700), color = { 255, 100, 170 }, shape = BALL, material = NEON, transparency = 0.9 })
	return it
end

-- The wing's name on two wall faces, beside (never over) the bay's own boards: the back wall left of
-- the backlog sign (read while sorting) and the front wall right of the name sign (read walking back).
PIECES.wingSigns = function()
	local it = newItem("WingSigns")
	local _, back = addSign(it, V(18, 3, 0.2), CFrame.new(-22, 12.5, -35.9), Enum.NormalId.Back, "",
		{ board = { 28, 30, 36 }, text = { 255, 214, 110 } })
	local _, front = addSign(it, V(18, 3, 0.2), CFrame.new(22, 12.5, 19.9), Enum.NormalId.Front, "",
		{ board = { 28, 30, 36 }, text = { 255, 214, 110 } })
	it.labels = { back, front }
	return it
end

-- ─────────────────────────────────────────────────────────────── critters (pooled ambient life)

local CRITTERS = {}
CRITTERS.pigeon = function()
	local it = newItem("Pigeon")
	addPart(it, { size = V(1.2, 1.2, 1.6), color = { 150, 150, 160 }, shape = BALL })
	addPart(it, { size = V(1.6, 0.15, 0.9), offset = CFrame.new(-0.9, 0.2, 0), color = { 120, 120, 132 }, role = "wingL" })
	addPart(it, { size = V(1.6, 0.15, 0.9), offset = CFrame.new(0.9, 0.2, 0), color = { 120, 120, 132 }, role = "wingR" })
	it.animate = function(item, cf, now)
		local flap = math.sin(now * 14 + (item.phase or 0)) * 0.6
		item.entries[1].part.CFrame = cf
		item.entries[2].part.CFrame = cf * CFrame.new(-0.9, 0.2, 0) * CFrame.Angles(0, 0, -flap)
		item.entries[3].part.CFrame = cf * CFrame.new(0.9, 0.2, 0) * CFrame.Angles(0, 0, flap)
	end
	return it
end
CRITTERS.airliner = function()
	local it = newItem("Airliner")
	addPart(it, { size = V(48, 6, 6), offset = CFrame.Angles(0, math.rad(90), 0), color = WHITE, shape = CYL })
	addPart(it, { size = V(44, 0.8, 8), offset = CFrame.new(0, -0.5, 2), color = { 210, 212, 218 } })
	addPart(it, { size = V(0.8, 8, 6), offset = CFrame.new(0, 5, 21), color = { 40, 90, 170 } })
	addPart(it, { size = V(16, 0.6, 4), offset = CFrame.new(0, 2, 21), color = { 210, 212, 218 } })
	addPart(it, { size = V(5, 2.6, 2.6), offset = CFrame.new(-9, -2.6, 0) * CFrame.Angles(0, math.rad(90), 0), color = { 170, 172, 180 }, shape = CYL })
	addPart(it, { size = V(5, 2.6, 2.6), offset = CFrame.new(9, -2.6, 0) * CFrame.Angles(0, math.rad(90), 0), color = { 170, 172, 180 }, shape = CYL })
	return it
end
CRITTERS.balloon = function()
	local it = newItem("Balloon")
	local c = BULBS[math.random(1, #BULBS)]
	addPart(it, { size = V(2.4, 2.8, 2.4), color = c, shape = BALL })
	addPart(it, { size = V(0.08, 4, 0.08), offset = CFrame.new(0, -3.3, 0), color = WHITE })
	return it
end
CRITTERS.satellite = function()
	local it = newItem("Satellite")
	addPart(it, { size = V(3, 3, 4), color = { 210, 180, 90 }, material = Enum.Material.Foil })
	addPart(it, { size = V(7, 0.2, 3), offset = CFrame.new(-5.5, 0, 0), color = { 40, 60, 140 }, material = GLASSM })
	addPart(it, { size = V(7, 0.2, 3), offset = CFrame.new(5.5, 0, 0), color = { 40, 60, 140 }, material = GLASSM })
	return it
end
CRITTERS.astronaut = function()
	local it = newItem("Astronaut")
	addPart(it, { size = V(2, 2.6, 1.4), color = WHITE })
	addPart(it, { size = V(1.8, 1.8, 1.8), offset = CFrame.new(0, 2.1, 0), color = WHITE, shape = BALL })
	addPart(it, { size = V(1.2, 0.8, 0.3), offset = CFrame.new(0, 2.1, -0.85), color = BRASS, material = Enum.Material.Glass })
	addPart(it, { size = V(1.6, 2, 0.8), offset = CFrame.new(0, 0.2, 1), color = { 200, 200, 205 } })
	it.animate = function(item, cf, now)
		local tumble = cf * CFrame.Angles(now * 0.4 + (item.phase or 0), now * 0.25, 0)
		place(item, tumble)
	end
	return it
end
CRITTERS.comet = function()
	local it = newItem("Comet")
	local head = addPart(it, { size = V(8, 8, 8), color = { 200, 230, 255 }, shape = BALL, material = NEON })
	addTrail(it, head, 3, { 160, 210, 255 }, 3)
	return it
end

-- ─────────────────────────────────────────────────────────────── weather over the bay

-- Emitters live on ONE invisible host over the player's bay. At most Budget.MaxWeatherEmitters are on,
-- summed rate at most Budget.MaxEmitterRate (EnvBands.capRates, enforced in updateWeather).
local WEATHER = {
	steam = { color = { 240, 240, 240 }, size = { 5, 10 }, transparency = 0.55, lifetime = { 4, 6 }, speed = { 2, 4 },
		accel = { 0, 2.5, 0 }, light = 0, hostY = 30, hostH = 2, dir = "Top" },
	confetti = { color = nil, size = { 0.35, 0.35 }, transparency = 0, lifetime = { 6, 8 }, speed = { 1, 3 },
		accel = { 0, -3, 0 }, light = 0.3, hostY = 26, hostH = 1, dir = "Bottom", spin = true },
	motes = { color = { 170, 210, 255 }, size = { 0.18, 0.18 }, transparency = 0.1, lifetime = { 6, 9 }, speed = { 0.2, 0.6 },
		accel = { 0, 0, 0 }, light = 1, hostY = 8, hostH = 14, dir = "Top" },
	stardust = { color = { 220, 170, 255 }, size = { 0.2, 0.2 }, transparency = 0.1, lifetime = { 6, 9 }, speed = { 0.2, 0.6 },
		accel = { 0, 0, 0 }, light = 1, hostY = 8, hostH = 14, dir = "Top" },
}

-- ─────────────────────────────────────────────────────────────── hazard models

local HAZARDS = {}
HAZARDS.trolley = function(it)
	addPart(it, { size = V(3.4, 0.4, 5), offset = CFrame.new(0, 0.6, 0), color = STEEL, material = METAL })
	addPart(it, { size = V(3.2, 3.2, 0.3), offset = CFrame.new(0, 2.2, 2.4), color = STEEL, material = METAL })
	addPart(it, { size = V(2.8, 1.6, 3.8), offset = CFrame.new(0, 1.6, -0.2), color = { 60, 110, 190 } })
	addPart(it, { size = V(2.2, 1.2, 2.6), offset = CFrame.new(0, 3, -0.4), color = { 200, 90, 60 } })
	return 0
end
HAZARDS.suitcase = function(it)
	addPart(it, { size = V(3, 2.2, 1.3), color = { 160, 40, 60 } })
	addPart(it, { size = V(1.2, 0.4, 0.3), offset = CFrame.new(0, 1.3, 0), color = DARK })
	it.spin = V(6, 0, 0)
	return 1.3
end
HAZARDS.porter = function(it)
	addPart(it, { size = V(3.6, 0.5, 6), offset = CFrame.new(0, 0.7, 0), color = { 110, 80, 50 }, material = Enum.Material.Wood })
	addPart(it, { size = V(0.3, 3.4, 0.3), offset = CFrame.new(0, 2.4, 3), color = DARK })
	addPart(it, { size = V(3, 2, 2.4), offset = CFrame.new(0, 2, -1), color = { 120, 70, 40 }, material = Enum.Material.Leather })
	addPart(it, { size = V(1.8, 1.4, 1.8), offset = CFrame.new(0, 3.7, -1), color = { 220, 200, 150 }, shape = CYL })
	return 0
end
HAZARDS.pigeon = function(it)
	addPart(it, { size = V(1.8, 1.8, 2.4), color = { 150, 150, 160 }, shape = BALL })
	addPart(it, { size = V(2.6, 0.2, 1.2), offset = CFrame.new(-1.4, 0.3, 0), color = { 120, 120, 132 } })
	addPart(it, { size = V(2.6, 0.2, 1.2), offset = CFrame.new(1.4, 0.3, 0), color = { 120, 120, 132 } })
	return nil
end
HAZARDS.beachball = function(it)
	addPart(it, { size = V(4.4, 4.4, 4.4), color = { 250, 200, 60 }, shape = BALL })
	addPart(it, { size = V(1, 4.46, 4.46), color = { 90, 200, 190 }, shape = CYL })
	it.spin = V(5, 0, 0)
	it.bounce = 1.5
	return 2.2
end
HAZARDS.bumpercar = function(it)
	addPart(it, { size = V(4.2, 1.4, 5.4), offset = CFrame.new(0, 0.9, 0), color = { 230, 50, 60 } })
	addPart(it, { size = V(3, 1.4, 2), offset = CFrame.new(0, 2, 0.8), color = { 40, 40, 48 } })
	addPart(it, { size = V(0.25, 4, 0.25), offset = CFrame.new(0, 3.4, 2.4), color = STEEL })
	addPart(it, { size = V(0.6, 0.6, 0.6), offset = CFrame.new(0, 5.5, 2.4), color = { 255, 240, 120 }, shape = BALL, material = NEON })
	return 0
end
HAZARDS.crate = function(it)
	addPart(it, { size = V(3.2, 3.2, 3.2), color = { 170, 140, 90 }, material = Enum.Material.Wood })
	addPart(it, { size = V(3.3, 0.4, 3.3), color = { 90, 180, 255 }, material = NEON })
	it.spin = V(0.6, 0.9, 0.3)
	return nil
end
HAZARDS.drone = function(it)
	addPart(it, { size = V(2, 0.8, 2), color = WHITE })
	for _, o in { { 1.4, 1.4 }, { -1.4, 1.4 }, { 1.4, -1.4 }, { -1.4, -1.4 } } do
		addPart(it, { size = V(0.2, 1.4, 1.4), offset = CFrame.new(o[1], 0.5, o[2]) * UPRIGHT, color = { 90, 180, 255 }, shape = CYL, material = NEON, transparency = 0.3 })
	end
	return nil
end
HAZARDS.blob = function(it)
	addPart(it, { size = V(3.6, 2.6, 3.6), color = { 120, 240, 120 }, shape = BALL, material = NEON, transparency = 0.25 })
	addPart(it, { size = V(0.7, 0.7, 0.7), offset = CFrame.new(-0.6, 0.9, -1.5), color = WHITE, shape = BALL })
	addPart(it, { size = V(0.7, 0.7, 0.7), offset = CFrame.new(0.6, 0.9, -1.5), color = WHITE, shape = BALL })
	it.wobble = true
	return 1.3
end
HAZARDS.meteorite = function(it)
	addPart(it, { size = V(3.4, 3, 3.2), color = { 90, 80, 76 }, shape = BALL, material = Enum.Material.Slate })
	addPart(it, { size = V(3.8, 3.4, 3.6), color = { 255, 140, 60 }, shape = BALL, material = NEON, transparency = 0.7 })
	it.spin = V(1.2, 0.8, 0)
	return nil
end

-- ─────────────────────────────────────────────────────────────── the pure lists (CLI-safe)

function WingArt.hasPiece(id)
	return PIECES[id] ~= nil
end
function WingArt.hasCritter(kind)
	return CRITTERS[kind] ~= nil
end
function WingArt.hasWeather(kind)
	return WEATHER[kind] ~= nil
end
function WingArt.hasHazardModel(kind)
	return HAZARDS[kind] ~= nil
end
-- The pieces that hang OVER the bay (y >= 18). The client multiplies their weight by Wings.overheadFade
-- of the camera's height, so a camera zoomed out above the walls never looks at the tags through them.
local OVERHEAD = { cityRoof = true, airportRoof = true, trainShed = true, parkLights = true, stationDome = true }
function WingArt.isOverhead(id)
	return OVERHEAD[id] == true
end
function WingArt.pieceIds()
	local out = {}
	for id in PIECES do table.insert(out, id) end
	table.sort(out)
	return out
end

-- ─────────────────────────────────────────────────────────────── the art object

function WingArt.new(folder, rand, Config, EnvBands)
	initRoblox()
	local self = setmetatable({}, WingArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.EnvBands = EnvBands
	self.items = {}
	self.critters = {}
	self.hazardModels = {}
	self.root = nil -- CFrame of the player's bay, set by setBay
	return self
end

-- Where the player's bay is. Every placed piece moves with it.
function WingArt:setBay(ox)
	local root = CFrame.new(ox, 0, 0)
	self.root = root
	for _, item in self.items do
		place(item, root)
	end
end

function WingArt:item(id)
	local it = self.items[id]
	if it == nil and PIECES[id] then
		it = PIECES[id]()
		self.items[id] = it
		if self.root then place(it, self.root) end
	end
	return it
end

function WingArt:updatePiece(id, w, now)
	if self.root == nil then return end
	if w <= 0.01 and self.items[id] == nil then return end
	local it = self:item(id)
	if it == nil then return end
	setWeight(it, w, self.folder)
	if it.shown and it.animate then
		it.animate(it, self.root, now)
	end
end

function WingArt:setSignText(text)
	local it = self:item("wingSigns")
	for _, l in it.labels do
		if l.Text ~= text then l.Text = text end
	end
end

function WingArt:critterList(kind)
	local list = self.critters[kind]
	if list == nil then
		list = {}
		self.critters[kind] = list
	end
	return list
end

function WingArt:updateCritters(desired, cam, dt, now)
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
						local look = if hv.Magnitude > 0.01 then p + hv else p + V(0, 0, -1)
						local cf = CFrame.lookAt(p, look)
						if c.item.animate then c.item.animate(c.item, cf, now) else place(c.item, cf) end
					end
				end
			end
		end
		-- at most one group per kind per frame: never a pop of ten
		if active < want and spec then
			local group = math.min(spec.flock or 1, want - active)
			local base = E.ambientSpawn(camV, spec, self.rand)
			for g = 1, group do
				local c = nil
				for _, existing in list do
					if not existing.active then c = existing; break end
				end
				if c == nil then
					c = { item = CRITTERS[kind](), active = false }
					table.insert(list, c)
				end
				c.active = true
				c.leaving = false
				c.w = 0
				c.item.phase = self.rand() * 6.28
				c.pos = { x = base.pos.x + (g - 1) % 3 * 3 - 3, y = base.pos.y + (g - 1) * 0.8, z = base.pos.z - (g - 1) * 2.5 }
				c.vel = base.vel
			end
		end
	end
end

function WingArt:updateWeather(rates)
	if self.weatherHost == nil then
		local host = Instance.new("Part")
		host.Name = "WeatherHost"
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = V(70, 2, 54)
		self.weatherHost = host
		self.emitters = {}
	end
	local budget = self.cfg.Budget
	local capped = self.EnvBands.capRates(rates, math.min(budget.MaxWeatherEmitters, budget.MaxEmitters), budget.MaxEmitterRate, 0.05)
	local on, hostY, hostH = nil, 20, 2
	for kind, def in WEATHER do
		local rate = capped[kind] or 0
		local pe = self.emitters[kind]
		if pe == nil and rate > 0.05 then
			pe = Instance.new("ParticleEmitter")
			pe.Name = "Weather_" .. kind
			if def.color then
				pe.Color = ColorSequence.new(rgb(def.color))
			else
				pe.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, rgb(BULBS[1])),
					ColorSequenceKeypoint.new(0.25, rgb(BULBS[2])),
					ColorSequenceKeypoint.new(0.5, rgb(BULBS[3])),
					ColorSequenceKeypoint.new(0.75, rgb(BULBS[4])),
					ColorSequenceKeypoint.new(1, rgb(BULBS[5])),
				})
			end
			pe.Size = NumberSequence.new(def.size[1], def.size[2])
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.15, def.transparency),
				NumberSequenceKeypoint.new(0.85, def.transparency),
				NumberSequenceKeypoint.new(1, 1),
			})
			pe.Lifetime = NumberRange.new(def.lifetime[1], def.lifetime[2])
			pe.Speed = NumberRange.new(def.speed[1], def.speed[2])
			pe.LightEmission = def.light
			pe.Acceleration = V(def.accel[1], def.accel[2], def.accel[3])
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.EmissionDirection = Enum.NormalId[def.dir]
			if def.spin then
				pe.RotSpeed = NumberRange.new(-180, 180)
			end
			pe.Shape = Enum.ParticleEmitterShape.Box
			pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			pe.Rate = 0
			pe.Enabled = false
			pe.Parent = self.weatherHost
			self.emitters[kind] = pe
		end
		if pe then
			local enabled = rate > 0.05
			pe.Enabled = enabled
			if math.abs((pe.Rate or 0) - rate) > 0.25 or (not enabled and pe.Rate ~= 0) then
				pe.Rate = if enabled then rate else 0
			end
			if enabled and (on == nil or rate > (capped[on] or 0)) then
				on, hostY, hostH = kind, def.hostY, def.hostH
			end
		end
	end
	if on and self.root then
		self.weatherHost.Size = V(70, hostH, 54)
		self.weatherHost.CFrame = self.root * CFrame.new(0, hostY, -8)
		self.weatherHost.Parent = self.folder
	else
		self.weatherHost.Parent = nil
	end
end

-- ─────────────────────────────────────────────────────────────── hazards on screen

function WingArt:hazardModel(kind)
	local item = self.hazardModels[kind]
	if item then return item end
	item = newItem("Hazard_" .. kind)
	local groundLift = HAZARDS[kind](item)
	item.groundLift = groundLift -- nil: flies at the lane's height; a number: rests that far above the floor
	local marker = Instance.new("BillboardGui")
	marker.Name = "Warning"
	marker.AlwaysOnTop = true
	marker.Size = UDim2.fromOffset(46, 46)
	marker.StudsOffset = V(0, 4, 0)
	marker.LightInfluence = 0
	marker.Enabled = false
	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
	mark.BackgroundTransparency = 0.1
	mark.TextColor3 = Color3.fromRGB(255, 240, 120)
	mark.Font = Enum.Font.GothamBlack
	mark.TextScaled = true
	mark.Text = "!"
	mark.Parent = marker
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = mark
	marker.Parent = item.entries[1].part
	item.billboard = marker
	local blink = Instance.new("PointLight")
	blink.Name = "Blink"
	blink.Color = Color3.fromRGB(255, 60, 60)
	blink.Range = 10
	blink.Brightness = 2
	blink.Shadows = false
	blink.Enabled = false
	blink.Parent = item.entries[1].part
	table.insert(item.lights, blink)
	self.hazardModels[kind] = item
	return item
end

function WingArt:laneItem()
	if self.lane then return self.lane end
	local it = newItem("HazardLane")
	addPart(it, { name = "Lane", size = V(0.5, 0.1, 1), color = { 255, 210, 60 }, material = NEON, transparency = 0.35 })
	self.lane = it
	return it
end

function WingArt:ringItem()
	if self.ring then return self.ring end
	local it = newItem("HazardRing")
	addPart(it, { name = "Ring", size = V(0.12, 4, 4), color = { 255, 210, 60 }, shape = CYL, material = NEON, transparency = 0.5 })
	self.ring = it
	return it
end

-- plan / pos / zone come from Hazards (plain {x,y,z}); floorY is the floor the player stands on.
-- ringLive (Wings.zoneLive): the ring stays on the floor for exactly as long as a hit inside it is
-- possible, which on a small floor can be a little after the hazard arrives. The lane goes at arrival.
function WingArt:showHazard(plan, pos, now, zone, floorY, ringLive)
	local item = self:hazardModel(plan.kind)
	setWeight(item, 1, self.folder)
	item.billboard.Enabled = not plan.locked or (math.floor(now * 6) % 2 == 0)
	item.lights[1].Enabled = math.floor(now * 4) % 2 == 0
	local p = Vector3.new(pos.x, pos.y, pos.z)
	if item.groundLift then
		local hop = if item.bounce then math.abs(math.sin(now * 5)) * item.bounce else 0
		p = Vector3.new(pos.x, floorY + item.groundLift + hop, pos.z)
	end
	local v = Vector3.new(plan.velocity.x, plan.velocity.y, plan.velocity.z)
	local hv = Vector3.new(v.X, 0, v.Z)
	local cf = CFrame.lookAt(p, if hv.Magnitude > 0.01 then p + hv else p + V(0, 0, -1))
	if item.spin then
		cf = cf * CFrame.Angles(item.spin.X * now, item.spin.Y * now, item.spin.Z * now)
	end
	if item.wobble then
		local s = 1 + math.sin(now * 9) * 0.12
		item.entries[1].part.Size = V(3.6 * s, 2.6 / s, 3.6 * s)
	end
	place(item, cf)

	-- on the floor: the lane from under the hazard through the zone and a little beyond (yellow while it
	-- tracks you, red once locked), and the RING, which is where not to stand (Hazards.checkHit).
	local colour = if plan.locked then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(255, 210, 60)
	local ring = self:ringItem()
	if ringLive then
		setWeight(ring, 1, self.folder)
		local ringE = ring.entries[1]
		local d = 2 * zone.radius
		ringE.part.Color = colour
		ringE.part.Size = V(0.12, d, d)
		ringE.part.CFrame = CFrame.new(zone.x, floorY + 0.07, zone.z) * UPRIGHT
	else
		setWeight(ring, 0, self.folder)
	end
	local lane = self:laneItem()
	local target = Vector3.new(plan.target.x, floorY + 0.08, plan.target.z)
	local from = Vector3.new(pos.x, floorY + 0.08, pos.z)
	local dir = target - from
	local beyond = target + (if dir.Magnitude > 0.01 then dir.Unit * 8 else Vector3.zero)
	local len = (beyond - from).Magnitude
	if plan.t > plan.arriveAt or len < 1 then
		setWeight(lane, 0, self.folder)
		return
	end
	setWeight(lane, 1, self.folder)
	local laneE = lane.entries[1]
	laneE.part.Color = colour
	laneE.part.Size = V(0.5, 0.1, len)
	laneE.part.CFrame = CFrame.lookAt(from:Lerp(beyond, 0.5), beyond)
end

function WingArt:hideHazard(kind)
	local item = self.hazardModels[kind]
	if item then
		item.billboard.Enabled = false
		setWeight(item, 0, self.folder)
	end
	if self.lane then setWeight(self.lane, 0, self.folder) end
	if self.ring then setWeight(self.ring, 0, self.folder) end
end

return WingArt
