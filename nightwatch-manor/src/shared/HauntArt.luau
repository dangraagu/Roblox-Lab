-- HauntArt.luau — Nightwatch Manor's eye candy, built in code (no assets). CLIENT ONLY.
-- Required by src/client/Haunt.client.luau; the server never requires it and never sees what it builds.
--
-- What it builds, all of it LOCAL decoration (anchored; CanCollide, CanQuery, CanTouch and CastShadow off,
-- so nothing can be stood on, bumped, touched, raycast or used to hide behind):
--   * WINDOWS on the manor's OUTER walls: closed picture-boxes on the inside face of a solid wall (frame,
--     night sky, moon, treeline, mist, mullions, swaying curtains). Nothing is seen THROUGH them, so a
--     window can never show a player another room or the Nightwatcher in it. Lightning flashes them.
--   * PORTRAITS whose eyes follow YOU: a painted face on each Portrait Hall portrait, pupils that slide
--     toward the local player's head. They never look at, or glow like, the Nightwatcher.
--   * DUST motes in the room you are in, RAIN on the nearest window, LIGHTNING (sky panels flash, one
--     pooled light at the nearest window, a bolt drawn in its glass).
--   * FLICKER: the manor's own room lights (Fixture / FoyerFlame / Candelabra, never the exit's, never the
--     Nightwatcher's) have their Brightness modulated within Nightfall's floor. The ONLY writes this module
--     makes to anything the server built, and they never replicate.
--   * the SAFEHOUSE growing cosier with hub level: hearth, fire, rugs, armchairs, books, candles, a cat,
--     a garland, a painting, a plant; and two windows on its south wall with the manor across the grounds,
--     its windows lit, a figure passing behind one of them.
--   * HAZARD models (bats, a will-o'-wisp, flying crockery, a wraith), each with an always-on-top warning
--     marker and an amber blink; one lane line and one ring for all of them.
--
-- Pooled and bounded (Config.Budget): windows and portraits are built the first time they are near and
-- UNPARENTED when far; at most MaxWindowsShown / MaxPortraitsShown are parented; one model per hazard kind;
-- one dust host, one rain host, one flash light, one bolt. robloxemu/check_nightwatchmanor_budget.luau
-- counts what is parented every frame.
--
-- Dependencies arrive as arguments (a bare `require("./X")` is invalid in Roblox):
--   HauntArt.new(folder, rand, Config, Nightfall, EnvBands)

local HauntArt = {}
HauntArt.__index = HauntArt

local function rgb(c: any): Color3
	return Color3.fromRGB(math.clamp(math.round(c[1]), 0, 255), math.clamp(math.round(c[2]), 0, 255),
		math.clamp(math.round(c[3]), 0, 255))
end

local WOOD = { 48, 36, 28 }
local VELVET = { 96, 22, 30 }
local STONE = { 86, 80, 84 }
local SOOT = { 14, 12, 12 }
local BLACK = { 8, 8, 10 }

local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder

-- Window stars, as fractions of the window's width and height from its centre: the open sky left of the
-- moon and above the treeline, clear of the mullions and of the curtains.
local STARS = { { -0.25, 0.42 }, { -0.15, 0.27 }, { -0.23, 0.15 }, { -0.08, 0.44 }, { 0.26, 0.45 } }
-- The corona is this much wider than the moon it rings.
local CORONA_SCALE = 1.32

-- One local, inert part. Every part this module makes goes through here.
local function part(name: string, size: Vector3, color: any, material: Enum.Material?, shape: Enum.PartType?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = rgb(color)
	if shape then p.Shape = shape end
	p.Size = size
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function setParent(list: { Instance }, parent: Instance?)
	for _, p in list do
		if p.Parent ~= parent then p.Parent = parent end
	end
end

function HauntArt.new(folder: Instance, rand: () -> number, Config: any, Nightfall: any, EnvBands: any)
	local self = setmetatable({}, HauntArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.Nightfall = Nightfall
	self.EnvBands = EnvBands
	self.manor = nil -- the server's Manor folder we last synced to
	self.windows = {} -- manor windows, by face key
	self.windowList = {}
	self.portraits = {}
	self.lights = {} -- { light = PointLight, base = number, seed = number, room = Vector3 }
	self.hazardModels = {}
	self.house = nil
	self.housePieces = nil
	self.lastSort = -math.huge
	self.flashT = 0
	return self
end

--============================================================================ windows

-- A window box on a face. `pos` is the placement point (just in front of the wall), `n` points into the
-- room. `variant` = "manor" (sky, moon, treeline, mist) or "house" (the same plus the distant manor).
local function buildWindow(self, key: string, pos: Vector3, n: Vector3, variant: string)
	local W, H = self.cfg.Env.Window.Width, self.cfg.Env.Window.Height
	local base = CFrame.lookAt(pos, pos + n)
	local function at(x: number, y: number, d: number): CFrame
		return base * CFrame.new(x, y, -d) -- local -Z is along n (into the room)
	end
	local w = { key = key, pos = pos, n = n, base = base, parts = {}, shown = false, variant = variant, phase = self.rand() * 6.28 }
	local function add(p: Part, cf: CFrame): Part
		p.CFrame = cf
		table.insert(w.parts, p)
		return p
	end
	w.frame = add(part("WinFrame", Vector3.new(W + 1.0, H + 1.0, 0.1), WOOD, Enum.Material.Wood), at(0, 0, 0.02))
	w.sky = add(part("WinSky", Vector3.new(W, H, 0.02), { 26, 34, 62 }, Enum.Material.Neon), at(0, 0, 0.09))
	-- stars in the open sky left of the moon, clear of the mullions and the curtains (|x| < W * 0.3)
	w.stars = {}
	for i, s in STARS do
		local st = add(part("WinStar", Vector3.new(0.18, 0.18, 0.01), { 236, 238, 255 }, Enum.Material.Neon, nil, 1), at(s[1] * W, s[2] * H, 0.103))
		table.insert(w.stars, { p = st, phase = self.rand() * 6.28, speed = 1.3 + 0.4 * i })
	end
	-- the moon sits in the gap between the curtains (they cover |x| > W * 0.3), a little right of the mullion
	local md = H * 0.34
	w.moonHome = at(W * 0.1, H * 0.2, 0.12)
	-- the eclipse's corona: a pale disc just behind the moon, shown only as the band's `eclipse` rises
	w.corona = add(part("WinCorona", Vector3.new(0.01, md * CORONA_SCALE, md * CORONA_SCALE), { 214, 244, 196 }, Enum.Material.Neon, CYL, 1),
		at(W * 0.1, H * 0.2, 0.112) * CFrame.Angles(0, math.rad(90), 0))
	w.moon = add(part("WinMoon", Vector3.new(0.02, md, md), { 226, 230, 242 }, Enum.Material.Neon, CYL), w.moonHome * CFrame.Angles(0, math.rad(90), 0))
	w.moonD = md
	w.hills = add(part("WinTreeline", Vector3.new(W, H * 0.28, 0.02), BLACK, Enum.Material.SmoothPlastic), at(0, -H / 2 + H * 0.14, 0.14))
	w.mist = add(part("WinMist", Vector3.new(W, H * 0.45, 0.02), { 200, 205, 215 }, Enum.Material.SmoothPlastic, nil, 0.7), at(0, -H / 2 + H * 0.225, 0.16))
	if variant == "house" then
		-- the manor across the grounds: body, two towers, lit windows, and someone behind one of them
		w.manorBody = add(part("WinManor", Vector3.new(W * 0.42, H * 0.26, 0.02), BLACK), at(-W * 0.12, -H / 2 + H * 0.35, 0.15))
		w.towerA = add(part("WinTower", Vector3.new(W * 0.08, H * 0.42, 0.02), BLACK), at(-W * 0.3, -H / 2 + H * 0.42, 0.15))
		w.towerB = add(part("WinTower", Vector3.new(W * 0.07, H * 0.36, 0.02), BLACK), at(W * 0.07, -H / 2 + H * 0.39, 0.15))
		w.litA = add(part("WinLit", Vector3.new(W * 0.05, H * 0.06, 0.02), { 255, 200, 110 }, Enum.Material.Neon), at(-W * 0.2, -H / 2 + H * 0.37, 0.17))
		w.litB = add(part("WinLit", Vector3.new(W * 0.05, H * 0.06, 0.02), { 255, 200, 110 }, Enum.Material.Neon), at(-W * 0.03, -H / 2 + H * 0.37, 0.17))
		w.figureHome = { x = -W * 0.2, y = -H / 2 + H * 0.37 }
		w.figure = add(part("WinFigure", Vector3.new(W * 0.022, H * 0.055, 0.02), BLACK), at(-W * 0.2, -H / 2 + H * 0.37, 0.19))
		w.at = at
	end
	w.mullV = add(part("WinMullion", Vector3.new(0.25, H, 0.3), WOOD, Enum.Material.Wood), at(0, 0, 0.25))
	w.mullH = add(part("WinMullion", Vector3.new(W, 0.25, 0.3), WOOD, Enum.Material.Wood), at(0, H * 0.08, 0.25))
	local cw, ch = W * 0.2, H + 1.4
	w.curtainTop = H / 2 + 0.7
	w.curtainL = add(part("WinCurtain", Vector3.new(cw, ch, 0.12), VELVET, Enum.Material.Fabric), at(-W / 2 + cw / 2, w.curtainTop - ch / 2, 0.45))
	w.curtainR = add(part("WinCurtain", Vector3.new(cw, ch, 0.12), VELVET, Enum.Material.Fabric), at(W / 2 - cw / 2, w.curtainTop - ch / 2, 0.45))
	w.cw, w.ch = cw, ch
	w.boltPoint = at(-W * 0.1, H * 0.4, 0.13)
	w.rainPoint = at(0, H / 2 - 0.1, 0.2)
	w.flashPoint = at(0, 0, 1.5)
	return w
end

local function paintWindow(w: any, look: any, flash: number, now: number, sway: number)
	local g, o = look.glow or {}, look.outside or {}
	local sky = g.sky or { 26, 34, 62 }
	local fl = g.flash or { 205, 215, 255 }
	-- Lightning is a blink, not a fade: the glass is the flash colour for the first half of the flash and the
	-- sky again after. A linear fade from a dark sky to a pale flash passes through pale cyans, within 32 of the
	-- Nightwatcher's own lamp colour (measured, check_nightwatchmanor_budget.luau); the two ends are both fair.
	local c = if flash > 0.5 then fl else sky
	w.sky.Color = rgb(c)
	local moonC = g.moon or { 226, 230, 242 }
	w.moon.Color = rgb(moonC)
	local ms = math.clamp(o.moonSize or 1, 0.3, 1.8)
	local cloud = math.clamp(o.cloud or 0, 0, 1)
	w.moon.Size = Vector3.new(0.02, w.moonD * ms, w.moonD * ms)
	-- clouds drift across the moon: a slow bob and a veil. An eclipsed moon is a solid black disc (the veil
	-- would let the corona behind it show through and turn the eclipse back into a pale moon).
	local eclipse = math.clamp(o.eclipse or 0, 0, 1)
	w.moon.Transparency = math.clamp(cloud * (0.35 + 0.35 * math.sin(now * 0.21 + w.phase)), 0, 0.85) * (1 - eclipse)
	local cd = w.moonD * ms * CORONA_SCALE
	w.corona.Size = Vector3.new(0.01, cd, cd)
	w.corona.Color = rgb(g.corona or { 214, 244, 196 })
	w.corona.Transparency = 1 - 0.85 * eclipse
	-- stars twinkle gently, between 80 % and 100 % of the band's `stars`; a cloudy band has none (0 hides all)
	local stars = math.clamp(o.stars or 0, 0, 1)
	for _, s in w.stars do
		s.p.Transparency = 1 - stars * (0.9 + 0.1 * math.sin(now * s.speed + s.phase))
	end
	w.mist.Transparency = 1 - math.clamp(o.mist or 0, 0, 1) * 0.75
	-- curtains breathe in the draught; more in a storm, more as the manor wakes
	local a = math.rad(sway) * math.sin(now * 1.3 + w.phase)
	local b = math.rad(sway) * math.sin(now * 1.1 + w.phase * 1.7)
	local W = w.cw
	w.curtainL.CFrame = w.base * CFrame.new(-(w.sky.Size.X) / 2 + W / 2, w.curtainTop, -0.45) * CFrame.Angles(a, 0, 0) * CFrame.new(0, -w.ch / 2, 0)
	w.curtainR.CFrame = w.base * CFrame.new((w.sky.Size.X) / 2 - W / 2, w.curtainTop, -0.45) * CFrame.Angles(b, 0, 0) * CFrame.new(0, -w.ch / 2, 0)
	if w.variant == "house" then
		-- a figure crosses the lit window now and then (7 s of every 23)
		local cyc = (now + w.phase * 3) % 23
		local lit = w.litA
		if cyc < 7 then
			local k = cyc / 7
			local x = w.figureHome.x - 0.3 + 0.6 * k
			w.figure.CFrame = w.at(x, w.figureHome.y, 0.19)
			w.figure.Transparency = 0
		else
			w.figure.Transparency = 1
		end
		lit.Transparency = 0.15 * (0.5 + 0.5 * math.sin(now * 3.1 + w.phase))
	end
end

--============================================================================ the manor

-- Find this night's rooms, faces, portraits and room lights in the server's Manor folder. Called when the
-- folder changes (a new night). Reads parts only; writes nothing.
function HauntArt:syncManor(manor: Instance?)
	if manor == self.manor then return false end
	self:clearManor()
	self.manor = manor
	if manor == nil then return true end
	local size = self.cfg.Manor.RoomSize
	local cells, byKey = {}, {}
	for _, f in manor:GetChildren() do
		local kind = string.match(tostring(f.Name), "^Room%d+_(.+)$")
		local floor = kind and f:FindFirstChild("Floor")
		if floor and floor:IsA("BasePart") then
			local c = floor.Position
			local cell = { gx = math.floor(c.X / size + 0.5), gz = math.floor(c.Z / size + 0.5), kind = kind, centre = c, folder = f }
			table.insert(cells, cell)
			byKey[cell.gx .. "," .. cell.gz] = cell
		end
	end
	self.cells = cells
	-- the exit's face: the ExitDoor stands 6 studs inside one face of the exit room
	local exitFace = nil
	local door = manor:FindFirstChild("ExitDoor")
	if door and door:IsA("BasePart") and #cells > 0 then
		local best, bestD
		for _, c in cells do
			local d = (c.centre - door.Position).Magnitude
			if bestD == nil or d < bestD then best, bestD = c, d end
		end
		local off = door.Position - best.centre
		local dx = if math.abs(off.X) > math.abs(off.Z) then (if off.X > 0 then 1 else -1) else 0
		local dz = if dx == 0 then (if off.Z > 0 then 1 else -1) else 0
		exitFace = { gx = best.gx, gz = best.gz, dx = dx, dz = dz }
	end
	local faces = self.Nightfall.outerFaces(cells, exitFace, self.cfg.Env.WindowSkip)
	self.faces = {}
	for _, f in faces do
		local c = byKey[f.gx .. "," .. f.gz]
		local wp = self.Nightfall.windowPlacement(size, self.cfg.Env.Window, f)
		table.insert(self.faces, {
			key = f.gx .. "," .. f.gz .. "," .. f.dx .. "," .. f.dz,
			pos = Vector3.new(c.centre.X + wp.x, c.centre.Y + wp.y, c.centre.Z + wp.z),
			n = Vector3.new(wp.nx, 0, wp.nz),
		})
	end
	-- portraits (the Portrait Hall's two per room) and the room lights that may flicker
	self.portraitSpots = {}
	for _, c in cells do
		for _, d in c.folder:GetChildren() do
			if d.Name == "Portrait" and d:IsA("BasePart") then
				local off = c.centre - d.Position
				local n = if math.abs(off.X) > math.abs(off.Z) then Vector3.new(if off.X > 0 then 1 else -1, 0, 0)
					else Vector3.new(0, 0, if off.Z > 0 then 1 else -1)
				table.insert(self.portraitSpots, { part = d, n = n, key = d:GetFullName() })
			end
			if (d.Name == "Fixture" or d.Name == "FoyerFlame" or d.Name == "Candelabra") and d:IsA("BasePart") then
				local pl = d:FindFirstChild("PL")
				if pl and pl:IsA("PointLight") then
					table.insert(self.lights, { light = pl, base = pl.Brightness, seed = #self.lights * 7 + 3, at = d.Position, last = pl.Brightness })
				end
			end
		end
	end
	return true
end

function HauntArt:clearManor()
	for _, w in self.windowList do
		for _, p in w.parts do p:Destroy() end
	end
	self.windows, self.windowList = {}, {}
	for _, pt in self.portraits do
		for _, p in pt.parts do p:Destroy() end
	end
	self.portraits = {}
	-- lights belong to the server's (now destroyed) manor; restore any still standing and forget them
	for _, l in self.lights do
		if l.light.Parent ~= nil then l.light.Brightness = l.base end
	end
	self.lights = {}
	self.faces, self.portraitSpots, self.cells = {}, {}, {}
	if self.dustHost then self.dustHost.Parent = nil end
	if self.rainHost then self.rainHost.Parent = nil end
	-- the HOST goes, never the light: unparenting the PointLight itself orphaned it for the rest of the session
	-- (every later bolt drawn dark; check_nightwatchmanor_budget.luau "every frame with a bolt ... flash light on")
	if self.flashHost then self.flashHost.Parent = nil end
	if self.flashLight then self.flashLight.Enabled = false end
	if self.bolt then setParent(self.bolt, nil) end
	self.manor = nil
	self.nearest = nil
end

local function buildPortrait(spot: any)
	local p = spot.part
	local n = spot.n
	local pos = p.Position + n * (p.Size.X / 2 + 0.03)
	if math.abs(n.Z) > 0.5 then pos = p.Position + n * (p.Size.Z / 2 + 0.03) end
	local base = CFrame.lookAt(pos, pos + n)
	local function at(x: number, y: number, d: number): CFrame
		return base * CFrame.new(x, y, -d)
	end
	local pt = { spot = spot, parts = {}, base = base, n = n }
	local function add(q: Part, cf: CFrame): Part
		q.CFrame = cf
		table.insert(pt.parts, q)
		return q
	end
	add(part("PortraitCanvas", Vector3.new(3.3, 5.1, 0.04), { 46, 36, 30 }, Enum.Material.SmoothPlastic), at(0, 0, 0.02))
	add(part("PortraitFace", Vector3.new(0.04, 1.9, 1.9), { 170, 150, 128 }, Enum.Material.SmoothPlastic, CYL), at(0, 0.7, 0.05) * CFrame.Angles(0, math.rad(90), 0))
	pt.eyes = {}
	for i = -1, 1, 2 do
		-- discs facing the room (a Cylinder's axis is its local X, turned onto the canvas normal)
		local sclera = add(part("PortraitEye", Vector3.new(0.05, 0.34, 0.34), { 230, 200, 90 }, Enum.Material.Neon, CYL),
			at(i * 0.36, 0.95, 0.08) * CFrame.Angles(0, math.rad(90), 0))
		local pupil = add(part("PortraitPupil", Vector3.new(0.05, 0.15, 0.15), BLACK, Enum.Material.SmoothPlastic, CYL),
			at(i * 0.36, 0.95, 0.11) * CFrame.Angles(0, math.rad(90), 0))
		table.insert(pt.eyes, { sclera = sclera, pupil = pupil, home = at(i * 0.36, 0.95, 0.11).Position })
	end
	return pt
end

-- Every frame at night. ctx = { cam: Vector3, head: Vector3?, now, look, dread, flash (0..1) }
function HauntArt:updateManor(ctx: any)
	if self.manor == nil or self.manor.Parent == nil then return end
	local cfg, Env, B = self.cfg, self.cfg.Env, self.cfg.Budget
	local cam = ctx.cam
	local look = ctx.look
	local inside = look.inside or {}
	local now = ctx.now

	-- which windows and portraits are near: re-sorted 4x a second, not every frame
	if now - self.lastSort >= 0.25 then
		self.lastSort = now
		local near = {}
		for _, f in self.faces do
			local d = (f.pos - cam).Magnitude
			if d <= Env.WindowRange then table.insert(near, { f = f, d = d }) end
		end
		table.sort(near, function(a, b) return a.d < b.d end)
		local want = {}
		for i = 1, math.min(#near, B.MaxWindowsShown) do
			local f = near[i].f
			want[f.key] = true
			if self.windows[f.key] == nil then
				local w = buildWindow(self, f.key, f.pos, f.n, "manor")
				self.windows[f.key] = w
				table.insert(self.windowList, w)
			end
		end
		for key, w in self.windows do
			local on = want[key] == true
			if on ~= w.shown then
				setParent(w.parts, if on then self.folder else nil)
				w.shown = on
			end
		end
		self.nearest = near[1] and self.windows[near[1].f.key] or nil

		local pnear = {}
		for _, s in self.portraitSpots do
			local d = (s.part.Position - cam).Magnitude
			if d <= Env.PortraitRange and s.part.Parent ~= nil then table.insert(pnear, { s = s, d = d }) end
		end
		table.sort(pnear, function(a, b) return a.d < b.d end)
		local pwant = {}
		for i = 1, math.min(#pnear, B.MaxPortraitsShown) do
			local s = pnear[i].s
			pwant[s.key] = true
			if self.portraits[s.key] == nil then
				self.portraits[s.key] = buildPortrait(s)
			end
		end
		for key, pt in self.portraits do
			local on = pwant[key] == true
			if on ~= pt.shown then
				setParent(pt.parts, if on then self.folder else nil)
				pt.shown = on
			end
		end
	end

	local flash = ctx.flash or 0
	local sway = (inside.sway or 0) * (1 + 0.6 * (ctx.dread or 0))
	for _, w in self.windowList do
		if w.shown then paintWindow(w, look, flash, now, sway) end
	end

	-- portraits: the pupils follow YOUR head; the eyes glow more as the band darkens and dread rises
	local target = ctx.head or cam
	local eyeC = (look.glow or {}).eyes or { 230, 200, 90 }
	local glow = math.clamp((inside.eyes or 0) + 0.4 * (ctx.dread or 0), 0, 1)
	for _, pt in self.portraits do
		if pt.shown then
			for _, e in pt.eyes do
				local o = self.Nightfall.pupil({ x = e.home.X, y = e.home.Y, z = e.home.Z }, { x = pt.n.X, y = pt.n.Y, z = pt.n.Z },
					{ x = target.X, y = target.Y, z = target.Z }, Env.EyeShift)
				e.pupil.CFrame = (pt.base.Rotation * CFrame.Angles(0, math.rad(90), 0)) + (e.home + Vector3.new(o.x, o.y, o.z))
				e.sclera.Color = rgb(eyeC)
				e.sclera.Transparency = 0.55 - 0.5 * glow
			end
		end
	end

	-- flicker the manor's own room lights, within the floor; never below FlickerMin of the server's value
	local fair = self.Nightfall.HARD
	local amp = Env.FlickerAmp * math.clamp((inside.flicker or 0) + Env.FlickerDreadGain * (ctx.dread or 0), 0, 1)
	local lo = math.max((Env.Fairness and Env.Fairness.FlickerMin) or fair.FlickerMin, fair.FlickerMin)
	for _, l in self.lights do
		if l.light.Parent ~= nil and (l.at - cam).Magnitude <= 90 then
			local want = l.base * self.Nightfall.flicker(now, l.seed, amp, lo, 1 + amp)
			if math.abs(want - l.last) > 0.01 then
				l.light.Brightness = want
				l.last = want
			end
		end
	end
end

-- The room the camera's subject stands in, for the dust host (nil outside every room).
function HauntArt:roomAt(pos: Vector3): any
	local size = self.cfg.Manor.RoomSize
	for _, c in self.cells or {} do
		if math.abs(pos.X - c.centre.X) <= size / 2 and math.abs(pos.Z - c.centre.Z) <= size / 2 then
			return c
		end
	end
	return nil
end

--============================================================================ weather: dust + rain

local function emitter(name: string, parent: Instance, props: any): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Name = name
	for k, v in props do
		(pe :: any)[k] = v
	end
	pe.Parent = parent
	return pe
end

-- rates = { dust = n, rain = n } (particles/s, already blended); capped by EnvBands.capRates to the budget.
-- dustAt: the room centre (Vector3) or nil; rainAt: a window (or nil).
function HauntArt:updateWeather(rates: any, dustAt: Vector3?, rainAt: any, look: any)
	local B = self.cfg.Budget
	-- the fire's embers (safehouse, by day) are an emitter too: the weather gets what they leave of the rate
	-- budget. Without this a heavy rain at the cap plus the embers came to 68 of 60 particles/s (measured,
	-- check_nightwatchmanor_budget.luau). updateSafehouse runs first each frame, so this is this frame's rate.
	local embers = if self.firePE and self.firePE.Enabled then self.firePE.Rate else 0
	local capped = self.EnvBands.capRates(rates, math.min(B.MaxWeatherEmitters, B.MaxEmitters - (if embers > 0 then 1 else 0)),
		math.max(0, B.MaxEmitterRate - embers), 0.05)
	local g = look.glow or {}
	if self.dustHost == nil then
		self.dustHost = part("DustHost", Vector3.new(self.cfg.Manor.RoomSize - 4, 10, self.cfg.Manor.RoomSize - 4), BLACK, nil, nil, 1)
		self.dustPE = emitter("Dust", self.dustHost, {
			Rate = 0, Enabled = false,
			Lifetime = NumberRange.new(6, 11), Speed = NumberRange.new(0.2, 0.7),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.16), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, -0.35, 0), LightEmission = 0.35,
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
	end
	local dr = capped.dust or 0
	if dr > 0.05 and dustAt then
		self.dustHost.CFrame = CFrame.new(dustAt + Vector3.new(0, 6, 0))
		self.dustHost.Parent = self.folder
		self.dustPE.Color = ColorSequence.new(rgb(g.dust or { 220, 225, 235 }))
		if self.dustPE.Rate > dr or math.abs(self.dustPE.Rate - dr) > 0.25 then self.dustPE.Rate = dr end -- never above the cap
		self.dustPE.Enabled = true
	else
		self.dustPE.Enabled = false
		self.dustHost.Parent = nil
	end

	if self.rainHost == nil then
		self.rainHost = part("RainHost", Vector3.new(self.cfg.Env.Window.Width, 0.1, 0.1), BLACK, nil, nil, 1)
		self.rainPE = emitter("Rain", self.rainHost, {
			Rate = 0, Enabled = false,
			Color = ColorSequence.new(rgb(self.cfg.Env.Glow.rain)),
			Lifetime = NumberRange.new(0.22, 0.28), Speed = NumberRange.new(22, 26),
			Size = NumberSequence.new(0.06),
			Transparency = NumberSequence.new(0.35), LightEmission = 0.2,
			EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(3, 3),
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		})
	end
	local rr = capped.rain or 0
	if rr > 0.05 and rainAt then
		self.rainHost.CFrame = rainAt.rainPoint
		self.rainHost.Parent = self.folder
		if self.rainPE.Rate > rr or math.abs(self.rainPE.Rate - rr) > 0.25 then self.rainPE.Rate = rr end -- never above the cap
		self.rainPE.Enabled = true
	else
		self.rainPE.Enabled = false
		self.rainHost.Parent = nil
	end
end

--============================================================================ lightning

-- t in [0, 1]: 0 = no flash. The nearest shown window gets a light (so the room is lit FROM the window)
-- and, when `bolt`, a jagged bolt drawn in its glass.
function HauntArt:flash(t: number, bolt: boolean, window: any, look: any)
	local g = look.glow or {}
	local fl = g.flash or { 205, 215, 255 }
	if self.flashLight == nil then
		local host = part("FlashHost", Vector3.new(0.2, 0.2, 0.2), BLACK, nil, nil, 1)
		local l = Instance.new("PointLight")
		l.Name = "LightningFlash"
		l.Range = 34
		l.Shadows = false
		l.Brightness = 0
		l.Enabled = false
		l.Parent = host
		self.flashHost, self.flashLight = host, l
		self.bolt = {}
		for i = 1, 3 do
			table.insert(self.bolt, part("Bolt" .. i, Vector3.new(0.12, 1, 0.02), { 240, 245, 255 }, Enum.Material.Neon))
		end
	end
	if t <= 0.01 or window == nil then
		self.flashLight.Enabled = false
		self.flashHost.Parent = nil
		setParent(self.bolt, nil)
		return
	end
	self.flashHost.CFrame = window.flashPoint
	self.flashHost.Parent = self.folder
	self.flashLight.Color = rgb(fl)
	self.flashLight.Brightness = 3 * t
	self.flashLight.Enabled = true
	if bolt then
		local W, H = self.cfg.Env.Window.Width, self.cfg.Env.Window.Height
		local p = Vector3.new(-W * 0.1 + (self.rand() - 0.5) * W * 0.3, H * 0.45, 0)
		for _, seg in self.bolt do
			local q = p + Vector3.new((self.rand() - 0.5) * W * 0.25, -H * 0.2 - self.rand() * H * 0.08, 0)
			local mid = (p + q) / 2
			local len = (q - p).Magnitude
			seg.Size = Vector3.new(0.12, len, 0.02)
			local ang = math.atan2(q.X - p.X, p.Y - q.Y)
			seg.CFrame = window.base * CFrame.new(mid.X, mid.Y, -0.11) * CFrame.Angles(0, 0, ang)
			seg.Parent = self.folder
			p = q
		end
	else
		setParent(self.bolt, nil)
	end
end

--============================================================================ the safehouse

-- tier = Nightfall.cosyTier(Config.Env.Cosy, hubLevel): which props stand.
local function buildHouse(self, floor: BasePart)
	local o = floor.Position
	local pieces = {} -- { tier = n, parts = {}, shown = false }
	local function piece(tier: number): any
		local pc = { tier = tier, parts = {}, shown = false }
		table.insert(pieces, pc)
		return pc
	end
	local function add(pc: any, name: string, size: Vector3, cf: CFrame, color: any, material: Enum.Material?, shape: Enum.PartType?, tr: number?): Part
		local p = part(name, size, color, material, shape, tr)
		p.CFrame = cf
		table.insert(pc.parts, p)
		return p
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(o + Vector3.new(x, y, z))
	end
	-- 1: the hearth (always) on the north wall, cold until it is kindled
	local hearth = piece(1)
	add(hearth, "Chimney", Vector3.new(10, 13, 1.6), at(0, 7, 28.7), STONE, Enum.Material.Slate)
	add(hearth, "Firebox", Vector3.new(4.6, 3.6, 0.3), at(0, 2.3, 27.8), SOOT)
	add(hearth, "Mantel", Vector3.new(11.5, 0.6, 2.2), at(0, 5.0, 27.7), WOOD, Enum.Material.Wood)
	add(hearth, "Hearth", Vector3.new(11, 0.3, 2.9), at(0, 0.65, 28.05), STONE, Enum.Material.Slate)
	-- 2: kindled: the fire, its light and embers, and a rug
	local kindled = piece(2)
	local flame = add(kindled, "Fire", Vector3.new(1.6, 1.6, 1.6), at(0, 1.6, 27.6), { 255, 150, 60 }, Enum.Material.Neon, BALL)
	add(kindled, "Rug", Vector3.new(14, 0.08, 10), at(0, 0.54, 2), { 92, 34, 38 }, Enum.Material.Fabric)
	self.fire = flame
	-- 3: homely: an armchair by the fire, a bookshelf, candles on the mantel
	local homely = piece(3)
	local chair = CFrame.new(o + Vector3.new(-11, 0, 22)) * CFrame.Angles(0, math.rad(-35), 0)
	add(homely, "ChairSeat", Vector3.new(4, 1.2, 4), chair * CFrame.new(0, 1.6, 0), VELVET, Enum.Material.Fabric)
	add(homely, "ChairBack", Vector3.new(4, 4, 0.8), chair * CFrame.new(0, 3.4, -1.6), VELVET, Enum.Material.Fabric)
	add(homely, "ChairArm", Vector3.new(0.8, 1.4, 4), chair * CFrame.new(-2.2, 2.4, 0), VELVET, Enum.Material.Fabric)
	add(homely, "ChairArm", Vector3.new(0.8, 1.4, 4), chair * CFrame.new(2.2, 2.4, 0), VELVET, Enum.Material.Fabric)
	add(homely, "Bookshelf", Vector3.new(5, 9, 1.4), at(13, 5, 28.8), WOOD, Enum.Material.Wood)
	add(homely, "Books", Vector3.new(4.4, 1.3, 1.1), at(13, 6.4, 28.6), { 110, 70, 50 })
	for i = -1, 1, 2 do
		add(homely, "Candle", Vector3.new(0.3, 0.8, 0.3), at(i * 3.8, 5.7, 27.7), { 255, 205, 130 }, Enum.Material.Neon)
	end
	-- 4: cosy: a sleeping cat on the hearth, a garland over the mantel, a painting
	local cosy = piece(4)
	add(cosy, "CatBody", Vector3.new(1.3, 1.3, 1.3), at(3.3, 1.35, 27.0), { 38, 34, 32 }, nil, BALL)
	add(cosy, "CatHaunch", Vector3.new(1.1, 1.1, 1.1), at(4.2, 1.25, 27.1), { 38, 34, 32 }, nil, BALL)
	add(cosy, "CatHead", Vector3.new(0.85, 0.85, 0.85), at(2.5, 1.5, 26.7), { 38, 34, 32 }, nil, BALL)
	add(cosy, "CatTail", Vector3.new(1.6, 0.25, 0.25), at(2.4, 0.95, 26.5), { 38, 34, 32 })
	for i = 0, 6 do
		local x = -9 + i * 3
		local sag = 0.6 * math.sin(math.pi * i / 6)
		add(cosy, "Garland", Vector3.new(0.4, 0.4, 0.4), at(x, 11.4 - sag, 27.7), if i % 2 == 0 then { 255, 196, 110 } else { 255, 150, 90 }, Enum.Material.Neon, BALL)
	end
	add(cosy, "PaintingFrame", Vector3.new(6, 3.6, 0.2), at(0, 8.4, 27.85), { 120, 90, 40 }, Enum.Material.Wood)
	add(cosy, "Painting", Vector3.new(5.4, 3.0, 0.1), at(0, 8.4, 27.7), { 60, 70, 60 })
	-- 5: haven: a second armchair, a potted plant
	local haven = piece(5)
	local chair2 = CFrame.new(o + Vector3.new(10, 0, 22)) * CFrame.Angles(0, math.rad(35), 0)
	add(haven, "ChairSeat", Vector3.new(4, 1.2, 4), chair2 * CFrame.new(0, 1.6, 0), { 70, 50, 90 }, Enum.Material.Fabric)
	add(haven, "ChairBack", Vector3.new(4, 4, 0.8), chair2 * CFrame.new(0, 3.4, -1.6), { 70, 50, 90 }, Enum.Material.Fabric)
	add(haven, "Pot", Vector3.new(2, 2, 2), at(-17, 1.5, 27), { 120, 70, 50 }, nil, CYL)
	add(haven, "Plant", Vector3.new(3, 3.4, 3), at(-17, 3.8, 27), { 60, 110, 60 }, Enum.Material.Grass, BALL)
	-- the windows on the south wall, either side of the manor door: the manor across the grounds
	local windows = {}
	for i = -1, 1, 2 do
		local pos = o + Vector3.new(i * 15, 7, -self.cfg.Hub.Size / 2 + 0.55)
		table.insert(windows, buildWindow(self, "house" .. i, pos, Vector3.new(0, 0, 1), "house"))
	end
	return pieces, windows
end

function HauntArt:syncSafehouse(house: Instance?)
	if house == self.house then return end
	self:clearSafehouse()
	self.house = house
	local floor = house and house:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		self.housePieces, self.houseWindows = buildHouse(self, floor)
	end
end

function HauntArt:clearSafehouse()
	for _, pc in self.housePieces or {} do
		for _, p in pc.parts do p:Destroy() end
	end
	for _, w in self.houseWindows or {} do
		for _, p in w.parts do p:Destroy() end
	end
	if self.fireLight then self.fireLight:Destroy() end
	if self.firePE then self.firePE:Destroy() end
	self.housePieces, self.houseWindows, self.fire, self.fireLight, self.firePE = nil, nil, nil, nil, nil
	self.house = nil
end

-- shown = false hides everything (the player is in the manor). ctx = { now, look, tier, dread }
function HauntArt:updateSafehouse(shown: boolean, ctx: any)
	if self.housePieces == nil then return end
	local tier = ctx.tier or 1
	for _, pc in self.housePieces do
		local on = shown and tier >= pc.tier
		if on ~= pc.shown then
			setParent(pc.parts, if on then self.folder else nil)
			pc.shown = on
		end
	end
	for _, w in self.houseWindows do
		if shown ~= w.shown then
			setParent(w.parts, if shown then self.folder else nil)
			w.shown = shown
		end
		if shown then paintWindow(w, ctx.look, ctx.flash or 0, ctx.now, (ctx.look.inside or {}).sway or 0) end
	end
	-- the fire: its light and embers exist only while it is lit (tier 2+), and grow with the haven
	local lit = shown and tier >= 2 and self.fire ~= nil
	if lit and self.fireLight == nil then
		local l = Instance.new("PointLight")
		l.Name = "FireLight"
		l.Color = rgb(self.cfg.Env.Glow.fire)
		l.Range = 26
		l.Shadows = false
		l.Parent = self.fire
		self.fireLight = l
		self.firePE = emitter("Embers", self.fire, {
			Rate = 6, Color = ColorSequence.new(Color3.fromRGB(255, 170, 80)),
			Lifetime = NumberRange.new(1.2, 2.2), Speed = NumberRange.new(1.5, 3),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = 1, Acceleration = Vector3.new(0, 1.5, 0), SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top,
		})
	end
	if self.fireLight then
		self.fireLight.Enabled = lit
		self.firePE.Enabled = lit
		if lit then
			local big = if tier >= 5 then 1.35 else 1
			local f = self.Nightfall.flicker(ctx.now, 11, 0.25, 0.75, 1.25)
			self.fireLight.Brightness = 2.2 * big * f
			self.firePE.Rate = 6 * big
			self.fire.Size = Vector3.new(1.6, 1.6, 1.6) * big * (0.9 + 0.1 * f)
		end
	end
end

--============================================================================ hazards

local HAZARD_NAMES = { bats = "BATS", wisp = "WILL-O'-WISP", crockery = "FLYING CROCKERY", wraith = "WRAITH" }
HauntArt.HAZARD_NAMES = HAZARD_NAMES

local RECIPES = {
	bats = function(item)
		for i = 1, 5 do
			table.insert(item.shapes, { p = part("Bat", Vector3.new(1.4, 0.2, 0.6), { 20, 18, 24 }), off = Vector3.new((i - 3) * 0.9, (i % 2) * 0.6, (i % 3) * 0.7), flap = true })
		end
	end,
	-- the ghosts' glow is Config.Env.Glow.ghost / ghostHalo, a violet ghost-light, so Nightfall.fairness checks it
	-- statically (review 4: it was a hard-coded (120, 255, 140), 35 from the Servants' Exit's green)
	wisp = function(item, glow)
		table.insert(item.shapes, { p = part("Wisp", Vector3.new(1.1, 1.1, 1.1), glow.ghost, Enum.Material.Neon, BALL, 0.15), off = Vector3.zero })
		table.insert(item.shapes, { p = part("WispHalo", Vector3.new(2.2, 2.2, 2.2), glow.ghostHalo, Enum.Material.Neon, BALL, 0.75), off = Vector3.zero })
	end,
	crockery = function(item)
		for i = 1, 3 do
			table.insert(item.shapes, { p = part("Plate", Vector3.new(0.12, 1.3, 1.3), { 236, 232, 222 }, Enum.Material.SmoothPlastic, CYL), off = Vector3.new((i - 2) * 1.2, (i % 2) * 0.5, 0), spin = true })
		end
		table.insert(item.shapes, { p = part("Cup", Vector3.new(0.7, 0.7, 0.7), { 236, 232, 222 }, nil, CYL), off = Vector3.new(0, 1, 0.4), spin = true })
	end,
	wraith = function(item, glow)
		table.insert(item.shapes, { p = part("WraithShroud", Vector3.new(2.4, 3.6, 1.2), { 225, 232, 236 }, Enum.Material.SmoothPlastic, nil, 0.35), off = Vector3.new(0, -0.6, 0) })
		table.insert(item.shapes, { p = part("WraithHead", Vector3.new(1.5, 1.5, 1.5), { 225, 232, 236 }, Enum.Material.SmoothPlastic, BALL, 0.3), off = Vector3.new(0, 1.7, 0) })
		for i = -1, 1, 2 do
			table.insert(item.shapes, { p = part("WraithEye", Vector3.new(0.3, 0.3, 0.3), glow.ghost, Enum.Material.Neon, BALL), off = Vector3.new(i * 0.35, 1.8, -0.7) })
		end
	end,
}

function HauntArt.hazardKinds(): { [string]: boolean }
	local out = {}
	for k in RECIPES do out[k] = true end
	return out
end

function HauntArt:hazardModel(kind: string): any
	local item = self.hazardModels[kind]
	if item then return item end
	local recipe = RECIPES[kind]
	if recipe == nil then return nil end
	item = { kind = kind, shapes = {}, parts = {}, shown = false }
	recipe(item, self.cfg.Env.Glow)
	for _, s in item.shapes do
		s.p.Name = "Hazard_" .. kind .. "_" .. s.p.Name
		table.insert(item.parts, s.p)
	end
	local main = item.shapes[1].p
	local bb = Instance.new("BillboardGui")
	bb.Name = "HazardWarning"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(46, 46)
	bb.StudsOffset = Vector3.new(0, 3.5, 0)
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = main
	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.fromScale(1, 1)
	mark.Text = "⚠️"
	mark.TextScaled = true
	mark.Font = Enum.Font.GothamBlack
	mark.TextColor3 = Color3.fromRGB(255, 220, 60)
	mark.Parent = bb
	item.billboard = bb
	local light = Instance.new("PointLight")
	light.Name = "HazardBlink"
	light.Color = rgb(self.cfg.Env.Glow.hazardBlink)
	light.Range = 18
	light.Brightness = 1.6
	light.Enabled = false
	light.Parent = main
	item.light = light
	self.hazardModels[kind] = item
	return item
end

function HauntArt:laneItem(): any
	if self.lane then return self.lane end
	local lane = part("HazardLane", Vector3.new(0.3, 0.3, 10), self.cfg.Env.Glow.ringTrack, Enum.Material.Neon, nil, 0.45)
	local ring = part("HazardZone", Vector3.new(0.2, 8, 8), self.cfg.Env.Glow.ringTrack, Enum.Material.Neon, CYL, 0.55)
	self.lane = { lane = lane, ring = ring }
	return self.lane
end

-- Draw the hazard for this frame. `zone` = Hazards.zone(plan, PlayerRadius): the ring IS the hit rule.
-- `floorY` is the floor under the player (the ring lies on it). `calm` (Roblox's Reduced Motion setting): the
-- amber light and the marker stay steady instead of blinking.
function HauntArt:showHazard(plan: any, pos: any, now: number, zone: any, floorY: number, calm: boolean?)
	local item = self:hazardModel(plan.kind)
	if item == nil then return end
	if not item.shown then
		setParent(item.parts, self.folder)
		item.shown = true
	end
	-- at most Nightfall.HARD.BlinkHzMax blinks a second (review 4: the locked marker blinked 3 times a second)
	local blinkOn = calm == true or self.Nightfall.blink(now, self.cfg.Env.BlinkHz)
	item.billboard.Enabled = not plan.locked or blinkOn
	item.light.Enabled = blinkOn
	local p = Vector3.new(pos.x, pos.y, pos.z)
	local v = Vector3.new(plan.velocity.x, plan.velocity.y, plan.velocity.z)
	local hv = Vector3.new(v.X, 0, v.Z)
	local cf = CFrame.lookAt(p, if hv.Magnitude > 0.01 then p + hv else p + Vector3.new(0, 0, -1))
	for i, s in item.shapes do
		local c = cf * CFrame.new(s.off)
		if s.flap then
			c = c * CFrame.Angles(0, 0, math.sin(now * 18 + i) * 0.7)
		elseif s.spin then
			c = c * CFrame.Angles(now * 6 + i, 0, now * 4)
		end
		s.p.CFrame = c
	end

	local l = self:laneItem()
	local target = Vector3.new(plan.target.x, plan.target.y, plan.target.z)
	local beyond = target + (if v.Magnitude > 0 then v.Unit * 12 else Vector3.zero)
	local len = (beyond - p).Magnitude
	if plan.t > plan.arriveAt or len < 1 then
		l.lane.Parent = nil
		l.ring.Parent = nil
		return
	end
	local colour = if plan.locked then self.cfg.Env.Glow.ringLocked else self.cfg.Env.Glow.ringTrack
	l.lane.Color = rgb(colour)
	l.lane.Size = Vector3.new(0.3, 0.3, len)
	l.lane.CFrame = CFrame.lookAt(p:Lerp(beyond, 0.5), beyond)
	l.lane.Parent = self.folder
	local d = 2 * zone.radius
	l.ring.Color = rgb(colour)
	l.ring.Size = Vector3.new(0.2, d, d)
	l.ring.CFrame = CFrame.new(zone.x, floorY + 0.12, zone.z) * CFrame.Angles(0, 0, math.rad(90))
	l.ring.Parent = self.folder
end

function HauntArt:hideHazard(kind: string?)
	for k, item in self.hazardModels do
		if kind == nil or k == kind then
			item.billboard.Enabled = false
			item.light.Enabled = false
			if item.shown then
				setParent(item.parts, nil)
				item.shown = false
			end
		end
	end
	if self.lane then
		self.lane.lane.Parent = nil
		self.lane.ring.Parent = nil
	end
end

return HauntArt
