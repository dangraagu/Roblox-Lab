-- EnvArt.luau — FACILITY's environment art, built on the CLIENT only (Env.client.luau requires it; the
-- server never does). Code-only: no assets.
--
--   * dressRoom: a Dressing.build() list -> local Parts, screens (SurfaceGuis) and at most one emitter;
--   * recolour: a band's palette on the server's own room parts, on this client only (Dressing.paletteOk, in
--     linear light: every surface returns 60-100 % of the server's light, a closed door stands out from its
--     wall as the server built it), and the room light's colour (a tint: 90-100 % of the server's output);
--   * updateRoom: glow FOLLOWS THE ROOM'S POWER. Neon, glowing screens and EVERY particle emitter (self-lit
--     or not: steam and drips too) are on only while the room's own light is on, and they follow its flicker,
--     so a dark room never holds anything self-lit or moving and the dying room's warning is only ever
--     reinforced, never imitated;
--   * the break room's dressing (vending machine, coffee corner, plants, posters, the DEPTH RECORD board);
--   * hazard visuals: one pooled set per kind, one ring, only one kind parented at a time.
-- Every part it makes is Anchored, CanQuery = false, CanTouch = false. Floor-standing wall furniture
-- collides for THIS client only (Dressing marks it `solid`); everything else does not. It creates NO light
-- source of any kind. It never reads an item, a plan, a seed or ServerStorage.

local EnvArt = {}
EnvArt.__index = EnvArt

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local function dim(c: { number }, f: number): Color3
	return Color3.fromRGB(math.floor(c[1] * f), math.floor(c[2] * f), math.floor(c[3] * f))
end

local function newPart(props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.CanQuery = false
	p.CanTouch = false
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p :: BasePart
end

local function frame(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = alpha or 0
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Parent = parent
	return f
end

local function label(parent: Instance, name: string, text: string, x: number, y: number, w: number, h: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.Parent = parent
	return t
end

function EnvArt.new(folder: Instance, Config: any, Dressing: any)
	local self = setmetatable({}, EnvArt)
	self.folder = folder
	self.cfg = Config
	self.D = Dressing
	self.roomsFolder = Instance.new("Folder")
	self.roomsFolder.Name = "Rooms"
	self.roomsFolder.Parent = folder
	self.hazardFolder = Instance.new("Folder")
	self.hazardFolder.Name = "Hazard"
	self.hazardFolder.Parent = folder
	self.hazardPool = {}
	self.hazard = nil
	self.hub = nil
	self.rng = Random.new()
	return self
end

--============================================================================ screens

-- The SurfaceGui for one dressing part; returns { gui, blink = { frames }, kind }.
local function buildScreen(part: BasePart, spec: any, rng: any): any
	local sc = spec.screen
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId[spec.face or "Front"]
	-- canvas in the face's proportions (100 px per stud), as Main.server's labels do
	local s = part.Size
	local w, h = s.X, s.Y
	local f = spec.face
	if f == "Left" or f == "Right" then w = s.Z end
	gui.CanvasSize = Vector2.new(math.max(20, math.floor(w * 100)), math.max(20, math.floor(h * 100)))
	gui.LightInfluence = if sc.glow then 0 else 1
	gui.Enabled = false
	gui.Parent = part
	local out = { gui = gui, blink = {}, kind = sc.kind, glow = sc.glow == true }
	local glowC = if sc.color then rgb(sc.color) else Color3.fromRGB(120, 180, 255)
	if sc.kind == "rack" then
		frame(gui, "Bg", 0, 0, 1, 1, Color3.fromRGB(10, 10, 12))
		for row = 0, 5 do
			for col = 0, 2 do
				local c = if (row + col) % 4 == 0 then Color3.fromRGB(255, 60, 60) elseif (row * 3 + col) % 5 == 0 then Color3.fromRGB(230, 235, 240) else glowC
				local led = frame(gui, "Led", 0.18 + col * 0.26, 0.08 + row * 0.15, 0.1, 0.04, c)
				table.insert(out.blink, led)
			end
		end
	elseif sc.kind == "monitor" then
		frame(gui, "Bg", 0, 0, 1, 1, dim(sc.color or { 40, 92, 160 }, 0.55))
		for i = 0, 3 do
			local bar = frame(gui, "Line", 0.08, 0.14 + i * 0.18, 0.3 + (i * 0.37) % 0.55, 0.07, glowC)
			table.insert(out.blink, bar)
		end
	elseif sc.kind == "console" then
		frame(gui, "Bg", 0, 0, 1, 1, Color3.fromRGB(8, 8, 10))
		label(gui, "Core", "CORE 712 C", 0.05, 0.08, 0.9, 0.36, glowC)
		label(gui, "Pressure", "PRESSURE HIGH", 0.05, 0.5, 0.9, 0.26, Color3.fromRGB(120, 220, 255))
		local bar = frame(gui, "Bar", 0.05, 0.82, 0.6, 0.1, glowC)
		table.insert(out.blink, bar)
	elseif sc.kind == "glitch" then
		frame(gui, "Bg", 0, 0, 1, 1, Color3.fromRGB(4, 3, 6))
		for i = 1, 7 do
			local c = if i % 3 == 0 then Color3.fromRGB(235, 235, 245) else glowC
			local g = frame(gui, "Noise", rng:NextNumber() * 0.8, rng:NextNumber() * 0.9, 0.2, 0.04, c)
			table.insert(out.blink, g)
		end
	elseif sc.kind == "notices" then
		frame(gui, "Paper1", 0.06, 0.1, 0.26, 0.55, Color3.fromRGB(200, 198, 186))
		frame(gui, "Paper2", 0.38, 0.18, 0.24, 0.45, Color3.fromRGB(186, 196, 200))
		frame(gui, "Paper3", 0.68, 0.08, 0.26, 0.62, Color3.fromRGB(204, 200, 190))
		label(gui, "Text", "SAFETY FIRST", 0.06, 0.74, 0.88, 0.2, Color3.fromRGB(40, 36, 30))
	elseif sc.kind == "whiteboard" then
		label(gui, "Ink", "E = mc2   H2O + ? = ?", 0.05, 0.1, 0.9, 0.3, Color3.fromRGB(30, 50, 120))
		label(gui, "Warn", "DO NOT OPEN TANK 3", 0.05, 0.55, 0.9, 0.3, Color3.fromRGB(140, 30, 30))
	elseif sc.kind == "clock" then
		local face = frame(gui, "Face", 0.08, 0.08, 0.84, 0.84, Color3.fromRGB(200, 200, 196))
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = face
		local hour = frame(gui, "Hour", 0.48, 0.3, 0.04, 0.22, Color3.fromRGB(20, 20, 20))
		hour.Rotation = 100 -- the clocks all stopped at 3:17
		local minute = frame(gui, "Minute", 0.49, 0.16, 0.02, 0.36, Color3.fromRGB(20, 20, 20))
		minute.Rotation = 100
	elseif sc.kind == "hazard" then
		frame(gui, "Bg", 0, 0, 1, 1, Color3.fromRGB(140, 118, 30))
		gui.ClipsDescendants = true
		for i = 0, 4 do
			local stripe = frame(gui, "Stripe", -0.2 + i * 0.3, -0.3, 0.1, 1.6, Color3.fromRGB(16, 16, 16))
			stripe.Rotation = 35
		end
		label(gui, "Text", "HIGH TEMPERATURE", 0.05, 0.4, 0.9, 0.2, Color3.fromRGB(10, 10, 10))
	end
	return out
end

--============================================================================ rooms

local function cylinderCFrame(centre: Vector3, axis: string?): CFrame
	if axis == "y" then
		return CFrame.new(centre) * CFrame.Angles(0, 0, math.pi / 2)
	elseif axis == "z" then
		return CFrame.new(centre) * CFrame.Angles(0, math.pi / 2, 0)
	end
	return CFrame.new(centre)
end

-- Build one dressing part at room origin `o` (the floor top at the room's centre, world space).
local function buildPart(spec: any, o: Vector3, parent: Instance): (BasePart, CFrame)
	local mn, mx = spec.min, spec.max
	local size = Vector3.new(mx[1] - mn[1], mx[2] - mn[2], mx[3] - mn[3])
	if spec.anim == "bob" then
		size = Vector3.new(size.X, size.Y - 0.4, size.Z) -- the bob's travel is the top of the checked box
	end
	local centre = o + Vector3.new((mn[1] + mx[1]) / 2, mn[2] + size.Y / 2, (mn[3] + mx[3]) / 2)
	local cf = CFrame.new(centre)
	local realSize = size
	local shape = Enum.PartType.Block
	if spec.shape == "Ball" then
		local d = math.min(size.X, size.Y, size.Z)
		realSize = Vector3.new(d, d, d)
		shape = Enum.PartType.Ball
	elseif spec.shape == "Cylinder" then
		local len, dia
		if spec.axis == "y" then
			len, dia = size.Y, math.min(size.X, size.Z)
		elseif spec.axis == "z" then
			len, dia = size.Z, math.min(size.X, size.Y)
		else
			len, dia = size.X, math.min(size.Y, size.Z)
		end
		realSize = Vector3.new(len, dia, dia)
		cf = cylinderCFrame(centre, spec.axis)
		shape = Enum.PartType.Cylinder
	end
	local p = newPart({
		Name = spec.name,
		Size = realSize,
		CFrame = cf,
		Shape = shape,
		Color = rgb(spec.color),
		Material = if spec.emissive then Enum.Material.SmoothPlastic else Enum.Material[spec.material],
		Transparency = spec.transparency or 0,
		CanCollide = spec.solid == true,
		CastShadow = spec.solid == true,
		Parent = parent,
	})
	return p, cf
end

local function buildEmitter(host: BasePart, e: any): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "EnvParticles"
	pe.Rate = e.rate
	pe.Lifetime = NumberRange.new(e.life[1], e.life[2])
	pe.Speed = NumberRange.new(e.speed[1], e.speed[2])
	pe.SpreadAngle = Vector2.new(e.spread, e.spread)
	pe.EmissionDirection = if e.dir == "down" then Enum.NormalId.Bottom else Enum.NormalId.Top
	pe.Acceleration = Vector3.new(e.accel[1], e.accel[2], e.accel[3])
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, e.size * 0.4),
		NumberSequenceKeypoint.new(0.3, e.size),
		NumberSequenceKeypoint.new(1, e.size * 0.6),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Color = ColorSequence.new(rgb(e.color))
	pe.LightEmission = e.lightEmission
	-- Roblox's default LightInfluence is 0: particles drawn at full colour whatever the light. Only self-lit ones may
	-- be; steam, drips, fumes and motes are lit by the scene like any wall (EYECANDY.md §11, review finding 5).
	pe.LightInfluence = if e.lightEmission > 0 then 0 else 1
	pe.LockedToPart = false
	pe.Enabled = false
	pe.Parent = host
	return pe
end

-- Dress one room. `roomFolder` is the server's Room_<id>; `o` its floor-top centre; `band` the band table.
function EnvArt:dressRoom(roomFolder: Instance, parts: { any }, band: any, key: string, o: Vector3): any
	local model = Instance.new("Folder")
	model.Name = "Dress_" .. roomFolder.Name
	local rec = {
		key = key, band = band, folder = roomFolder, origin = o, model = model,
		glows = {}, screens = {}, emitters = {}, anims = {}, parts = {}, powered = nil, near = nil,
		lightRef = nil,
	}
	for _, spec in parts do
		local p, cf = buildPart(spec, o, model)
		table.insert(rec.parts, p)
		if spec.emissive then
			table.insert(rec.glows, { part = p, spec = spec, on = rgb(spec.color), off = dim(spec.color, 0.22) })
			p.Color = dim(spec.color, 0.22)
		end
		if spec.screen then
			local sc = buildScreen(p, spec, self.rng)
			table.insert(rec.screens, sc)
		end
		if spec.emitter then
			table.insert(rec.emitters, { pe = buildEmitter(p, spec.emitter), spec = spec.emitter, rate = spec.emitter.rate,
				glow = spec.emitter.lightEmission > 0 })
		end
		if spec.anim then
			table.insert(rec.anims, { part = p, kind = spec.anim, base = cf, phase = self.rng:NextNumber() * math.pi * 2, spec = spec })
		end
	end
	self:recolour(roomFolder, band.palette)
	model.Parent = self.roomsFolder
	rec.parented = true
	return rec
end

-- The band's palette on the server's own room parts, on this client only. Idempotent.
function EnvArt:recolour(roomFolder: Instance, palette: any)
	for _, c in roomFolder:GetChildren() do
		if c:IsA("BasePart") then
			local n = c.Name
			if n == "Floor" then
				c.Color = rgb(palette.floor)
				c.Material = Enum.Material[palette.floorMaterial]
			elseif n == "Ceiling" then
				c.Color = rgb(palette.ceiling)
			elseif string.sub(n, 1, 4) == "Wall" or string.sub(n, 1, 6) == "Lintel" then
				c.Color = rgb(palette.wall)
				c.Material = Enum.Material[palette.wallMaterial]
			end
		end
	end
	local fixture = roomFolder:FindFirstChild("Fixture")
	local light = fixture and fixture:FindFirstChild("RoomLight")
	if light then
		(light :: any).Color = rgb(palette.light)
	end
end

function EnvArt:recolourDoor(leaf: BasePart, palette: any)
	leaf.Color = rgb(palette.door)
end

function EnvArt:setParented(rec: any, on: boolean)
	if rec.parented == on then return end
	rec.parented = on
	rec.model.Parent = if on then self.roomsFolder else nil
	if not on then
		for _, e in rec.emitters do e.pe.Enabled = false end
		for _, s in rec.screens do s.gui.Enabled = false end
		rec.near = nil
	end
end

function EnvArt:destroyRoom(rec: any)
	rec.model:Destroy()
	rec.parented = false
end

-- The room's power as the client can see it: its own light on at full brightness. "low" during the
-- flicker counts as off, so self-lit dressing flickers WITH the room.
function EnvArt.roomPowered(roomFolder: Instance, fullBrightness: number): boolean
	local fixture = roomFolder:FindFirstChild("Fixture")
	local light = fixture and fixture:FindFirstChild("RoomLight")
	if not light then return false end
	return (light :: any).Enabled == true and (light :: any).Brightness >= 0.5 * fullBrightness
end

-- Per frame: power-follow, screens near and powered, animations near. `emitterOn` says whether this room's
-- emitter may run this frame: the client gives it only to near, POWERED rooms, nearest first, within the cap.
function EnvArt:updateRoom(rec: any, t: number, powered: boolean, near: boolean, emitterOn: boolean, screensOn: boolean)
	if not rec.parented then return end
	if rec.powered ~= powered then
		rec.powered = powered
		for _, g in rec.glows do
			g.part.Material = if powered then Enum.Material.Neon else Enum.Material.SmoothPlastic
			g.part.Color = if powered then g.on else g.off
		end
	end
	for _, s in rec.screens do
		local on = screensOn and (powered or not s.glow)
		if s.gui.Enabled ~= on then s.gui.Enabled = on end
	end
	for _, e in rec.emitters do
		-- `emitterOn` is the caller's whole decision: near, POWERED (every particle follows the room's power, self-lit
		-- or not, so nothing moves in a dark room: review finding 5) and within the emitter budget
		local on = emitterOn
		if e.pe.Enabled ~= on then e.pe.Enabled = on end
	end
	rec.near = near
	if not near then return end
	-- animations only where they can be seen
	for _, a in rec.anims do
		if a.kind == "bob" then
			local up = 0.2 + 0.2 * math.sin(t * 0.9 + a.phase)
			a.part.CFrame = a.base + Vector3.new(0, up, 0)
		elseif a.kind == "pulse" and powered then
			a.part.Transparency = 0.1 + 0.4 * (0.5 + 0.5 * math.sin(t * 5 + a.phase))
		elseif a.kind == "flicker" and powered then
			a.part.Transparency = if math.sin(t * 23 + a.phase) > 0.6 then 0.6 else 0
		end
	end
	if screensOn and powered then
		local step = math.floor(t * 4)
		if rec.lastBlink ~= step then
			rec.lastBlink = step
			for _, s in rec.screens do
				for i, f in s.blink do
					if s.kind == "glitch" then
						f.Position = UDim2.fromScale(self.rng:NextNumber() * 0.8, self.rng:NextNumber() * 0.9)
					elseif (i + step) % 5 == 0 or self.rng:NextNumber() < 0.15 then
						f.BackgroundTransparency = if f.BackgroundTransparency > 0.5 then 0 else 0.85
					end
				end
			end
		end
	end
end

--============================================================================ the break room

-- Built once, parented only while the player is in the break room. Hub-local: origin at the hub
-- floor's centre, walls' inner faces at x = +-30 and z = +-20. Kept off the spawn -> car path (z = 0),
-- the arrival pad (12, 0), the perk terminal (12, 19.5) and the benches (x 6 and 18 on the south wall).
function EnvArt:buildHub(bands: { any })
	local hub = Instance.new("Folder")
	hub.Name = "BreakRoom"
	local rec = { model = hub, parented = false, emitters = {}, board = nil, rows = {} }
	local function p(name, size, pos, color, mat, extra)
		local props = { Name = name, Size = size, CFrame = CFrame.new(pos), Color = color, Material = mat, Parent = hub,
			CanCollide = true, CastShadow = true }
		for k, v in extra or {} do props[k] = v end
		return newPart(props)
	end
	-- vending machine, north wall
	p("VendingBody", Vector3.new(4, 7, 2.4), Vector3.new(-2, 3.5, 18.7), Color3.fromRGB(110, 30, 36), Enum.Material.Metal)
	local front = p("VendingFront", Vector3.new(3.2, 5, 0.1), Vector3.new(-2, 4, 17.45), Color3.fromRGB(170, 220, 255), Enum.Material.Neon,
		{ CanCollide = false, CastShadow = false })
	do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Screen"
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(320, 500)
		gui.LightInfluence = 0
		gui.Parent = front
		label(gui, "Title", "SNACKS", 0.1, 0.03, 0.8, 0.12, Color3.fromRGB(20, 40, 80))
		for r = 0, 3 do
			for c = 0, 2 do
				local col = ({ Color3.fromRGB(200, 60, 60), Color3.fromRGB(60, 120, 220), Color3.fromRGB(230, 230, 230) })[1 + (r + c) % 3]
				frame(gui, "Snack", 0.1 + c * 0.28, 0.2 + r * 0.19, 0.2, 0.12, col)
			end
		end
	end
	-- coffee corner, north-east
	p("CoffeeCounter", Vector3.new(7, 3, 2.6), Vector3.new(23, 1.5, 18.6), Color3.fromRGB(74, 60, 52), Enum.Material.Wood)
	p("CoffeeMachine", Vector3.new(1.6, 2.2, 1.4), Vector3.new(21, 4.1, 18.9), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	p("CoffeeCup", Vector3.new(0.5, 0.6, 0.5), Vector3.new(22.4, 3.3, 18.4), Color3.fromRGB(230, 226, 214), Enum.Material.SmoothPlastic,
		{ CanCollide = false })
	local steamHost = p("SteamHost", Vector3.new(0.3, 0.2, 0.3), Vector3.new(22.4, 3.7, 18.4), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CastShadow = false })
	local steam = buildEmitter(steamHost, { rate = 3, life = { 1.5, 2.5 }, speed = { 0.4, 0.8 }, spread = 10, dir = "up",
		accel = { 0, 0.3, 0 }, size = 0.5, color = { 235, 235, 235 }, lightEmission = 0 })
	table.insert(rec.emitters, steam)
	-- water cooler and plants
	p("CoolerBody", Vector3.new(1.4, 3.2, 1.4), Vector3.new(-28.2, 1.6, -12), Color3.fromRGB(180, 182, 180), Enum.Material.SmoothPlastic)
	newPart({ Name = "CoolerBottle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 1.1, 1.1),
		CFrame = CFrame.new(-28.2, 3.95, -12) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(120, 170, 210),
		Material = Enum.Material.SmoothPlastic, Transparency = 0.45, Parent = hub })
	for i, pos in { Vector3.new(-28, 0, 17), Vector3.new(28, 0, -17), Vector3.new(-3, 0, -18) } do
		newPart({ Name = "PlantPot" .. i, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 1.6, 1.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(90, 64, 52),
			Material = Enum.Material.Concrete, CanCollide = true, Parent = hub })
		newPart({ Name = "PlantLeaves" .. i, Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 2.4, 0)), Color = Color3.fromRGB(58, 96, 50), Material = Enum.Material.Grass, Parent = hub })
	end
	-- a rug under the benches
	p("Rug", Vector3.new(18, 0.05, 5), Vector3.new(12, 0.025, -16.6), Color3.fromRGB(70, 44, 44), Enum.Material.Fabric,
		{ CanCollide = false, CastShadow = false })
	-- posters on the west wall
	for i, spec in { { -7, "IF THE LIGHTS FLICKER — RUN" }, { 7, "DAYS WITHOUT AN INCIDENT: 0" } } do
		local poster = p("Poster" .. i, Vector3.new(0.1, 3, 4), Vector3.new(-29.9, 6, spec[1]), Color3.fromRGB(190, 186, 170), Enum.Material.SmoothPlastic,
			{ CanCollide = false })
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Screen"
		gui.Face = Enum.NormalId.Right
		gui.CanvasSize = Vector2.new(400, 300)
		gui.Parent = poster
		label(gui, "Text", spec[2], 0.06, 0.1, 0.88, 0.8, Color3.fromRGB(120, 24, 24))
	end
	-- the DEPTH RECORD board on the south wall, in front of a player who has just spawned
	local board = p("DepthBoard", Vector3.new(13, 7, 0.2), Vector3.new(-19, 5.5, -19.85), Color3.fromRGB(18, 20, 24), Enum.Material.Metal,
		{ CanCollide = false })
	do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Screen"
		gui.Face = Enum.NormalId.Back
		gui.CanvasSize = Vector2.new(1300, 700)
		gui.LightInfluence = 0
		gui.Parent = board
		local title = label(gui, "Title", "DEPTH RECORD", 0.05, 0.03, 0.9, 0.12, Color3.fromRGB(255, 196, 92))
		title.Font = Enum.Font.GothamBlack
		rec.best = label(gui, "Best", "DEEPEST: —", 0.05, 0.16, 0.9, 0.09, Color3.fromRGB(236, 234, 228))
		for i, b in bands do
			local row = label(gui, "Row" .. i, "", 0.1, 0.27 + (i - 1) * 0.1, 0.8, 0.08, Color3.fromRGB(120, 120, 120))
			row.TextXAlignment = Enum.TextXAlignment.Left
			rec.rows[i] = { label = row, band = b }
		end
		rec.board = gui
	end
	self.hub = rec
	self:updateBoard(0)
	return rec
end

-- The brag: every band you have reached is named; the ones below you are not (no spoilers).
function EnvArt:updateBoard(best: number)
	local rec = self.hub
	if not rec or rec.shownBest == best then return end
	rec.shownBest = best
	rec.best.Text = if best > 0 then "DEEPEST: SUBLEVEL " .. best else "DEEPEST: —"
	for i, r in rec.rows do
		local from = math.max(1, r.band.from)
		if best >= from then
			r.label.Text = string.format("%2d  %s", from, r.band.name)
			r.label.TextColor3 = Color3.fromRGB(236, 234, 228)
		else
			r.label.Text = string.format("%2d  ???", from)
			r.label.TextColor3 = Color3.fromRGB(96, 96, 100)
		end
		-- the band you are in; the last row (THE VOID, the brag) has no next band to stop it (review finding 4)
		local nextFrom = if i < #rec.rows then math.max(1, rec.rows[i + 1].band.from) else math.huge
		if best >= from and best < nextFrom then
			r.label.TextColor3 = Color3.fromRGB(255, 196, 92)
		end
	end
end

function EnvArt:setHubParented(on: boolean)
	local rec = self.hub
	if not rec or rec.parented == on then return end
	rec.parented = on
	rec.model.Parent = if on then self.folder else nil
	for _, e in rec.emitters do e.Enabled = on end
end

--============================================================================ hazards

-- Kind visuals: colour of the warning particles, of the burst, and its shape.
local KINDS = {
	chemLeak = { warn = { 170, 90, 255 }, burst = { 170, 90, 255 }, glow = 0.8, shape = "splash" },
	cableArc = { warn = { 190, 220, 255 }, burst = { 190, 220, 255 }, glow = 1, shape = "arc" },
	pipeBurst = { warn = { 150, 180, 200 }, burst = { 120, 170, 210 }, glow = 0, shape = "column" },
	steamVent = { warn = { 225, 225, 230 }, burst = { 230, 232, 236 }, glow = 0, shape = "column" },
	sporePod = { warn = { 100, 220, 210 }, burst = { 100, 220, 210 }, glow = 0.6, shape = "splash" },
	rift = { warn = { 220, 60, 255 }, burst = { 220, 60, 255 }, glow = 1, shape = "arc" },
}
EnvArt.HAZARD_KINDS = KINDS
local RING = Color3.fromRGB(235, 72, 72)

local function hazardSet(self: any, kind: string): any
	local set = self.hazardPool[kind]
	if set then return set end
	local look = KINDS[kind] or KINDS.chemLeak
	local model = Instance.new("Folder")
	model.Name = "Hazard_" .. kind
	local ring = newPart({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 7, 7), Color = RING,
		Material = Enum.Material.Neon, Transparency = 0.5, Parent = model })
	local source = newPart({ Name = "Source", Size = Vector3.new(1.6, 0.5, 1.6), Color = Color3.fromRGB(40, 42, 46),
		Material = Enum.Material.Metal, Parent = model })
	local burst = newPart({ Name = "Burst", Shape = if look.shape == "splash" then Enum.PartType.Ball else Enum.PartType.Cylinder,
		Size = Vector3.new(1, 1, 1), Color = rgb(look.burst), Material = if look.glow > 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		Transparency = 1, Parent = model })
	local warn = buildEmitter(source, { rate = 4, life = { 0.5, 0.9 }, speed = { 3, 6 }, spread = 20, dir = "down",
		accel = { 0, -20, 0 }, size = 0.25, color = look.warn, lightEmission = look.glow })
	set = { kind = kind, model = model, ring = ring, source = source, burst = burst, warn = warn, look = look }
	self.hazardPool[kind] = set
	return set
end

-- Show a hazard: the ring on the floor at `centre` (world, floor top), its source on the ceiling above.
function EnvArt:hazardShow(kind: string, centre: Vector3, radius: number, ceilingY: number)
	self:hazardHide()
	local set = hazardSet(self, kind)
	set.centre = centre
	set.radius = radius
	set.ceilingY = ceilingY
	set.ring.Size = Vector3.new(0.06, radius * 2, radius * 2)
	set.ring.CFrame = CFrame.new(centre + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	set.ring.Transparency = 0.55
	set.source.CFrame = CFrame.new(centre.X, ceilingY - 0.25, centre.Z)
	set.burst.Transparency = 1
	set.warn.Enabled = true
	set.model.Parent = self.hazardFolder
	self.hazard = set
end

-- Per frame. phase: "warn" | "burst" | "after"; frac: how far through the warning (0..1).
function EnvArt:hazardUpdate(phase: string, frac: number, t: number)
	local set = self.hazard
	if not set then return end
	if phase == "warn" then
		-- the ring pulses faster as the burst nears
		local speed = 4 + 14 * frac
		set.ring.Transparency = 0.35 + 0.3 * (0.5 + 0.5 * math.sin(t * speed))
		-- the warning thickens as the burst nears, never past the budget's HazardEmitterRate
		set.warn.Rate = math.min(4 + 6 * frac, self.cfg.Budget.HazardEmitterRate)
	else
		set.warn.Enabled = false
		set.ring.Transparency = if phase == "burst" then 0.2 else 0.8
		local c = set.centre -- the floor top under the zone's centre (world)
		local h = set.ceilingY - c.Y -- floor to ceiling
		if set.look.shape == "column" or set.look.shape == "arc" then
			local w = if set.look.shape == "arc" then 0.5 else set.radius * 1.4
			set.burst.Size = Vector3.new(h, w, w)
			set.burst.CFrame = CFrame.new(c.X, c.Y + h / 2, c.Z) * CFrame.Angles(0, 0, math.pi / 2)
		else
			local d = set.radius * 2
			set.burst.Size = Vector3.new(d, d, d)
			set.burst.CFrame = CFrame.new(c.X, c.Y + 1.2, c.Z)
		end
		set.burst.Transparency = if phase == "burst" then 0.35 else 0.85
	end
end

function EnvArt:hazardHide()
	local set = self.hazard
	if not set then return end
	set.warn.Enabled = false
	set.model.Parent = nil
	self.hazard = nil
end

return EnvArt
