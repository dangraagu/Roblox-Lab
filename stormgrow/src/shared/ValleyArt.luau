-- ValleyArt.luau — the client's scenery, critters, weather, rainbow and hazard visuals (DESIGN.md §3, §4).
-- Required only by Sky.client. Code-only art (no assets): Parts, Beams, ParticleEmitters, PointLights.
-- Everything is built under one client-side folder, never replicates, and never collides, queries or touches.
--
-- Budgets (Config.Budget, measured by robloxemu/check_stormgrow_env.luau at every band, seam and event):
--   * scenery Parts: each piece is built lazily when its weight rises above 0 and destroyed 2 s after it
--     falls back to 0, so at most two bands' pieces exist at once (a seam);
--   * critters: one Part each, at most MaxCritterParts;
--   * weather: one host Part with an emitter per kind; Sky.client enables at most MaxWeatherEmitters,
--     through EnvBands.capRates;
--   * lights: every PointLight here is registered, and capLights keeps only the nearest MaxLights enabled.
-- Positions are world-fixed and derived from EnvBands.hash01, so every client draws the same valley and
-- nothing slides with the camera. Pure dependencies arrive as arguments (a string require is invalid).

local ValleyArt = {}
ValleyArt.__index = ValleyArt

local TAU = math.pi * 2

local function c3(t: { number }): Color3
	return Color3.fromRGB(math.clamp(math.round(t[1]), 0, 255), math.clamp(math.round(t[2]), 0, 255), math.clamp(math.round(t[3]), 0, 255))
end

-- ── construction ───────────────────────────────────────────────────────────────────────────────────
-- hooks = { farmCentre = () -> Vector3?, farmFrame = () -> { halfW, depth, toWorld(lx, y, lz) -> Vector3 }? }:
-- where the local player's own farm is (the sunbeam falls on it, the lanterns hang on its fences).
function ValleyArt.new(parent: Instance, rand: () -> number, Config: any, EnvBands: any, hooks: any): any
	local folder = Instance.new("Folder")
	folder.Name = "ValleyArt"
	folder.Parent = parent
	local self = setmetatable({
		folder = folder,
		rand = rand,
		Config = Config,
		EnvBands = EnvBands,
		farmCentre = hooks and hooks.farmCentre,
		farmFrame = hooks and hooks.farmFrame,
		pieces = {}, -- id -> { parts = { { part, baseT } }, lights = {}, zeroSince = t?, spin = fn? }
		critters = {}, -- list of { part, kind, pos, vel, phase }
		lights = {},
		emitters = {},
		weatherHost = nil,
		rainbow = nil,
		hazard = nil,
		bolts = {},
		groundY = Config.Farm.GroundY,
	}, ValleyArt)
	for _, name in { "Scenery", "Critters", "Weather", "Rainbow", "Hazard", "Bolts" } do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
		self[name] = f
	end
	return self
end

function ValleyArt.part(self: any, parentFolder: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parentFolder
	return p
end

function ValleyArt.light(self: any, host: BasePart, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = host
	table.insert(self.lights, l)
	return l
end

-- deterministic [0, 1) for piece `id`, item i, channel c
local function h01(EnvBands: any, id: string, i: number, c: number): number
	local s = 0
	for k = 1, #id do s = (s * 31 + string.byte(id, k)) % 2147483647 end
	return EnvBands.hash01(i, c, s, 20260930)
end

-- a point on the valley floor at polar (angle, radius)
local function polar(a: number, r: number, y: number): Vector3
	return Vector3.new(math.sin(a) * r, y, math.cos(a) * r)
end

-- ── the pieces: each returns { { part, baseTransparency } }, lights, and an optional per-frame animator ─
local BUILDERS = {}

-- Slots of the six farms are at yaw 0, 60, ... 300: scenery inside the wall goes BETWEEN farms (yaw 30 +
-- 60k) or beyond the wall, never onto a field.
local function betweenFarms(EnvBands: any, id: string, i: number, n: number): number
	local gap = (i - 1) % 6
	local jitter = (h01(EnvBands, id, i, 1) - 0.5) * math.rad(16)
	return math.rad(30 + 60 * gap) + jitter
end

BUILDERS.hills = function(self, id, ctx)
	local out = {}
	for i = 1, 16 do
		local a = (i - 1) / 16 * TAU + (h01(self.EnvBands, id, i, 2) - 0.5) * 0.3
		local r = 280 + 60 * h01(self.EnvBands, id, i, 3)
		local size = 110 + 60 * h01(self.EnvBands, id, i, 4)
		local p = self:part(self.Scenery, { Name = "Hill_" .. i, Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(polar(a, r, self.groundY - size * 0.35)), Color = c3(ctx.ground), Material = Enum.Material.Grass })
		table.insert(out, { p, 0, tint = true })
	end
	return out
end

local function trees(self: any, id: string, n: number, trunkColor: Color3, leafColors: { Color3 }, rMin: number, rMax: number, tall: boolean?)
	local out = {}
	for i = 1, n do
		local a = betweenFarms(self.EnvBands, id, i, n)
		local r = rMin + (rMax - rMin) * h01(self.EnvBands, id, i, 5)
		local base = polar(a, r, self.groundY)
		local h = (if tall then 12 else 7) + 4 * h01(self.EnvBands, id, i, 6)
		local trunk = self:part(self.Scenery, { Name = "Trunk_" .. i, Size = Vector3.new(1.4, h, 1.4),
			CFrame = CFrame.new(base + Vector3.new(0, h / 2, 0)), Color = trunkColor, Material = Enum.Material.Wood })
		local leafC = leafColors[1 + (i % #leafColors)]
		local crown = if tall
			then self:part(self.Scenery, { Name = "Crown_" .. i, Size = Vector3.new(6, h * 1.1, 6), Shape = Enum.PartType.Ball,
				CFrame = CFrame.new(base + Vector3.new(0, h * 0.95, 0)), Color = leafC, Material = Enum.Material.Grass })
			else self:part(self.Scenery, { Name = "Crown_" .. i, Size = Vector3.new(9, 8, 9), Shape = Enum.PartType.Ball,
				CFrame = CFrame.new(base + Vector3.new(0, h + 2, 0)), Color = leafC, Material = Enum.Material.Grass })
		table.insert(out, { trunk, 0 })
		table.insert(out, { crown, 0 })
	end
	return out
end

BUILDERS.oaks = function(self, id)
	return trees(self, id, 10, Color3.fromRGB(110, 80, 50), { Color3.fromRGB(70, 150, 60), Color3.fromRGB(90, 165, 70) }, 185, 215)
end
BUILDERS.orchard = function(self, id)
	return trees(self, id, 14, Color3.fromRGB(100, 70, 45), { Color3.fromRGB(215, 110, 40), Color3.fromRGB(190, 60, 40), Color3.fromRGB(230, 160, 50) }, 180, 218)
end
BUILDERS.pines = function(self, id)
	return trees(self, id, 14, Color3.fromRGB(90, 70, 50), { Color3.fromRGB(40, 90, 60), Color3.fromRGB(55, 105, 70) }, 180, 218, true)
end

BUILDERS.pond = function(self, id)
	local a = math.rad(150)
	return { { self:part(self.Scenery, { Name = "Pond", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 26, 26),
		CFrame = CFrame.new(polar(a, 200, self.groundY + 0.1)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(80, 150, 200), Material = Enum.Material.Glass, Reflectance = 0.2 }), 0.2 } }
end

local function house(self: any, id: string, yawDeg: number, r: number, body: Color3, roof: Color3, w: number, d: number, hgt: number)
	local a = math.rad(yawDeg)
	local base = polar(a, r, self.groundY)
	local face = CFrame.lookAt(base, Vector3.new(0, self.groundY, 0))
	local out = {}
	local b = self:part(self.Scenery, { Name = id .. "Body", Size = Vector3.new(w, hgt, d), CFrame = face * CFrame.new(0, hgt / 2, 0), Color = body, Material = Enum.Material.WoodPlanks })
	local r1 = self:part(self.Scenery, { Name = id .. "Roof", Size = Vector3.new(w + 2, 1.2, d * 0.62),
		CFrame = face * CFrame.new(0, hgt + d * 0.18, -d * 0.24) * CFrame.Angles(math.rad(35), 0, 0), Color = roof, Material = Enum.Material.Slate })
	local r2 = self:part(self.Scenery, { Name = id .. "Roof2", Size = Vector3.new(w + 2, 1.2, d * 0.62),
		CFrame = face * CFrame.new(0, hgt + d * 0.18, d * 0.24) * CFrame.Angles(math.rad(-35), 0, 0), Color = roof, Material = Enum.Material.Slate })
	local door = self:part(self.Scenery, { Name = id .. "Door", Size = Vector3.new(w * 0.3, hgt * 0.6, 0.4),
		CFrame = face * CFrame.new(0, hgt * 0.3, -d / 2 - 0.1), Color = Color3.fromRGB(70, 45, 30), Material = Enum.Material.Wood })
	for _, p in { b, r1, r2, door } do table.insert(out, { p, 0 }) end
	return out
end

BUILDERS.farmhouse = function(self, id) return house(self, id, 210, 205, Color3.fromRGB(235, 225, 200), Color3.fromRGB(120, 60, 50), 16, 12, 9) end
BUILDERS.barn = function(self, id) return house(self, id, 90, 205, Color3.fromRGB(180, 45, 40), Color3.fromRGB(70, 60, 60), 20, 14, 12) end

BUILDERS.hayRolls = function(self, id)
	local out = {}
	for i = 1, 12 do
		local a = betweenFarms(self.EnvBands, id, i, 12)
		local r = 180 + 36 * h01(self.EnvBands, id, i, 7)
		table.insert(out, { self:part(self.Scenery, { Name = "Hay_" .. i, Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 5, 5),
			CFrame = CFrame.new(polar(a, r, self.groundY + 2.5)) * CFrame.Angles(0, a, 0), Color = Color3.fromRGB(220, 190, 90),
			Material = Enum.Material.Fabric }), 0 })
	end
	return out
end

BUILDERS.windmill = function(self, id)
	local a = math.rad(330)
	local base = polar(a, 210, self.groundY)
	local tower = self:part(self.Scenery, { Name = "MillTower", Size = Vector3.new(6, 26, 6), CFrame = CFrame.new(base + Vector3.new(0, 13, 0)),
		Color = Color3.fromRGB(230, 220, 200), Material = Enum.Material.Brick })
	local cap = self:part(self.Scenery, { Name = "MillCap", Size = Vector3.new(8, 4, 8), CFrame = CFrame.new(base + Vector3.new(0, 28, 0)),
		Color = Color3.fromRGB(120, 60, 50), Material = Enum.Material.Slate })
	local hub = CFrame.lookAt(base + Vector3.new(0, 26, 0), Vector3.new(0, 26, 0)) * CFrame.new(0, 0, -4.5)
	local b1 = self:part(self.Scenery, { Name = "Blade1", Size = Vector3.new(2, 24, 0.4), CFrame = hub, Color = Color3.fromRGB(245, 240, 230), Material = Enum.Material.Fabric })
	local b2 = self:part(self.Scenery, { Name = "Blade2", Size = Vector3.new(24, 2, 0.4), CFrame = hub, Color = Color3.fromRGB(245, 240, 230), Material = Enum.Material.Fabric })
	local list = { { tower, 0 }, { cap, 0 }, { b1, 0 }, { b2, 0 } }
	return list, nil, function(t)
		local spin = CFrame.Angles(0, 0, t * 0.8)
		b1.CFrame = hub * spin
		b2.CFrame = hub * spin
	end
end

BUILDERS.scarecrow = function(self, id)
	local base = polar(math.rad(270), 196, self.groundY)
	local post = self:part(self.Scenery, { Name = "CrowPost", Size = Vector3.new(0.6, 8, 0.6), CFrame = CFrame.new(base + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(8)),
		Color = Color3.fromRGB(110, 80, 50), Material = Enum.Material.Wood })
	local arms = self:part(self.Scenery, { Name = "CrowArms", Size = Vector3.new(6, 0.5, 0.5), CFrame = CFrame.new(base + Vector3.new(0.5, 6, 0)) * CFrame.Angles(0, 0, math.rad(8)),
		Color = Color3.fromRGB(150, 110, 60), Material = Enum.Material.Fabric })
	local head = self:part(self.Scenery, { Name = "CrowHead", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8), CFrame = CFrame.new(base + Vector3.new(0.9, 8.6, 0)),
		Color = Color3.fromRGB(220, 190, 110), Material = Enum.Material.Fabric })
	return { { post, 0 }, { arms, 0 }, { head, 0 } }
end

BUILDERS.cloudBank = function(self, id)
	local out = {}
	for i = 1, 12 do
		local a = math.rad(-60 + 120 * (i - 1) / 11) + math.rad(200)
		local r = 330 + 50 * h01(self.EnvBands, id, i, 8)
		local s = 70 + 40 * h01(self.EnvBands, id, i, 9)
		table.insert(out, { self:part(self.Scenery, { Name = "Cloud_" .. i, Shape = Enum.PartType.Ball, Size = Vector3.new(s * 1.6, s * 0.6, s),
			CFrame = CFrame.new(polar(a, r, 90 + 40 * h01(self.EnvBands, id, i, 10))), Color = Color3.fromRGB(70, 65, 90),
			Material = Enum.Material.SmoothPlastic, Transparency = 0.15 }), 0.15 })
	end
	return out
end

BUILDERS.lightningRod = function(self, id)
	local base = polar(math.rad(150), 214, self.groundY)
	local pole = self:part(self.Scenery, { Name = "RodPole", Size = Vector3.new(0.6, 30, 0.6), CFrame = CFrame.new(base + Vector3.new(0, 15, 0)),
		Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.Metal })
	local tip = self:part(self.Scenery, { Name = "RodTip", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = CFrame.new(base + Vector3.new(0, 30.5, 0)), Color = Color3.fromRGB(160, 200, 255), Material = Enum.Material.Neon })
	return { { pole, 0 }, { tip, 0 } }
end

BUILDERS.peaks = function(self, id)
	local out = {}
	for i = 1, 10 do
		local a = (i - 1) / 10 * TAU + 0.2
		local r = 330 + 50 * h01(self.EnvBands, id, i, 11)
		local hgt = 120 + 80 * h01(self.EnvBands, id, i, 12)
		local base = polar(a, r, self.groundY)
		local face = CFrame.lookAt(base, Vector3.new(0, self.groundY, 0))
		local rock = self:part(self.Scenery, { Name = "Peak_" .. i, Size = Vector3.new(120, hgt, 90), CFrame = face * CFrame.new(0, hgt / 2 - 10, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color = Color3.fromRGB(110, 115, 130), Material = Enum.Material.Rock })
		local cap = self:part(self.Scenery, { Name = "Snow_" .. i, Size = Vector3.new(60, hgt * 0.25, 45), CFrame = face * CFrame.new(0, hgt - 10 - hgt * 0.12, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color = Color3.fromRGB(245, 250, 255), Material = Enum.Material.Snow })
		table.insert(out, { rock, 0 })
		table.insert(out, { cap, 0 })
	end
	return out
end

BUILDERS.frozenFall = function(self, id)
	local base = polar(math.rad(90), 212, self.groundY)
	local face = CFrame.lookAt(base, Vector3.new(0, self.groundY, 0))
	local cliff = self:part(self.Scenery, { Name = "Cliff", Size = Vector3.new(26, 34, 8), CFrame = face * CFrame.new(0, 17, 4), Color = Color3.fromRGB(100, 105, 120), Material = Enum.Material.Rock })
	local ice = self:part(self.Scenery, { Name = "IceFall", Size = Vector3.new(8, 32, 1), CFrame = face * CFrame.new(0, 16, -0.6), Color = Color3.fromRGB(190, 230, 255),
		Material = Enum.Material.Ice, Transparency = 0.2 })
	local pool = self:part(self.Scenery, { Name = "IcePool", Size = Vector3.new(14, 0.4, 8), CFrame = face * CFrame.new(0, 0.2, -5), Color = Color3.fromRGB(200, 235, 255), Material = Enum.Material.Ice })
	return { { cliff, 0 }, { ice, 0.2 }, { pool, 0 } }
end

-- The brag's set piece: a slow-turning storm wall ringing the whole valley, lightning veins inside it. It
-- RISES with its weight (the band blend), so approaching the Eye you watch it grow on the horizon.
BUILDERS.stormWall = function(self, id)
	local out = {}
	local n, r = 24, 330
	local segs = {}
	for i = 1, n do
		local p = self:part(self.Scenery, { Name = "StormWall_" .. i, Size = Vector3.new(95, 300, 40), Color = Color3.fromRGB(60, 55, 75),
			Material = Enum.Material.SmoothPlastic, Transparency = 0.1 })
		table.insert(out, { p, 0.1 })
		segs[i] = p
	end
	local veins = {}
	for i = 1, 6 do
		local v = self:part(self.Scenery, { Name = "Vein_" .. i, Size = Vector3.new(1.5, 90, 1.5), Color = Color3.fromRGB(190, 220, 255), Material = Enum.Material.Neon, Transparency = 1 })
		table.insert(out, { v, 1 })
		veins[i] = v
	end
	local piece = { weight = 0 }
	return out, nil, function(t, w)
		local rise = math.clamp(w or 0, 0, 1)
		for i, p in segs do
			local a = (i - 1) / n * TAU + t * 0.02
			local hgt = 300 * rise
			p.Size = Vector3.new(95, math.max(hgt, 1), 40)
			p.CFrame = CFrame.lookAt(polar(a, r, self.groundY + hgt / 2), Vector3.new(0, self.groundY + hgt / 2, 0))
		end
		for i, v in veins do
			local a = (i - 1) / 6 * TAU + t * 0.02 + 0.1
			local flicker = (math.sin(t * (3 + i) + i * 1.7) > 0.93) and rise > 0.5
			v.Transparency = if flicker then 0.1 else 1
			v.CFrame = CFrame.new(polar(a, r - 22, self.groundY + 150 * rise)) * CFrame.Angles(0, 0, math.sin(t + i) * 0.3)
		end
		piece.weight = rise
	end
end

BUILDERS.sunbeam = function(self, id)
	local beam = self:part(self.Scenery, { Name = "Sunbeam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(300, 40, 40),
		Color = Color3.fromRGB(255, 225, 160), Material = Enum.Material.Neon, Transparency = 0.88 })
	local light = self:light(beam, Color3.fromRGB(255, 220, 160), 1.5, 60)
	return { { beam, 0.88 } }, { light }, function(t)
		local c = self.farmCentre and self.farmCentre()
		if c then
			beam.CFrame = CFrame.new(c + Vector3.new(0, 150, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

BUILDERS.isles = function(self, id)
	local out = {}
	local anim = {}
	for i = 1, 6 do
		local a = (i - 1) / 6 * TAU + 0.5
		local r = 250 + 40 * h01(self.EnvBands, id, i, 13)
		local y = 70 + 50 * h01(self.EnvBands, id, i, 14)
		local rock = self:part(self.Scenery, { Name = "IsleRock_" .. i, Shape = Enum.PartType.Ball, Size = Vector3.new(26, 18, 26), Color = Color3.fromRGB(110, 100, 90), Material = Enum.Material.Rock })
		local top = self:part(self.Scenery, { Name = "IsleTop_" .. i, Size = Vector3.new(22, 2, 22), Color = Color3.fromRGB(110, 170, 80), Material = Enum.Material.Grass })
		table.insert(out, { rock, 0 })
		table.insert(out, { top, 0 })
		anim[i] = { rock, top, polar(a, r, y) }
	end
	return out, nil, function(t)
		for i, it in anim do
			local bob = Vector3.new(0, math.sin(t * 0.4 + i) * 3, 0)
			it[1].CFrame = CFrame.new(it[3] + bob)
			it[2].CFrame = CFrame.new(it[3] + bob + Vector3.new(0, 6, 0))
		end
	end
end

BUILDERS.aurora = function(self, id)
	local out = {}
	local ribbons = {}
	for i = 1, 8 do
		local p = self:part(self.Scenery, { Name = "Aurora_" .. i, Size = Vector3.new(160, 50, 1), Color = Color3.fromRGB(90, 255, 180),
			Material = Enum.Material.Neon, Transparency = 0.7 })
		table.insert(out, { p, 0.7 })
		ribbons[i] = p
	end
	return out, nil, function(t)
		for i, p in ribbons do
			local a = math.rad(160 + i * 14)
			p.CFrame = CFrame.lookAt(polar(a, 360, 210 + math.sin(t * 0.3 + i) * 12), Vector3.new(0, 210, 0))
			p.Color = Color3.fromHSV((0.35 + 0.15 * math.sin(t * 0.2 + i * 0.6)) % 1, 0.7, 1)
		end
	end
end

BUILDERS.fallingStars = function(self, id)
	local out = {}
	local stars = {}
	for i = 1, 6 do
		local p = self:part(self.Scenery, { Name = "FallingStar_" .. i, Size = Vector3.new(0.6, 0.6, 18), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon })
		table.insert(out, { p, 0 })
		stars[i] = { part = p, phase = i * 1.7 }
	end
	return out, nil, function(t)
		for i, s in stars do
			local cyc = (t * 0.25 + s.phase) % 6
			local a = math.rad(40 * i + 20)
			local from = polar(a, 380, 260)
			local dir = Vector3.new(math.cos(a), -0.45, -math.sin(a)).Unit
			local pos = from + dir * (cyc * 90)
			s.part.CFrame = CFrame.lookAt(pos, pos + dir)
			s.part.Transparency = if cyc < 2.2 then 0 else 1
		end
	end
end

-- Lanterns on YOUR fences (band 7), so the fields still read at night.
BUILDERS.lanterns = function(self, id)
	local out, lights = {}, {}
	local posts = {}
	for i = 1, 11 do
		local p = self:part(self.Scenery, { Name = "Lantern_" .. i, Size = Vector3.new(1, 1.4, 1), Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon })
		table.insert(out, { p, 0 })
		table.insert(lights, self:light(p, Color3.fromRGB(255, 190, 110), 1.2, 22))
		posts[i] = p
	end
	return out, lights, function(t)
		local ctx = self.farmFrame and self.farmFrame()
		if ctx == nil then return end
		for i, p in posts do
			local along = (i - 1) / 10
			-- left fence, back fence, right fence, 11 posts evenly round the three sides
			local lx, lz
			local perim = along * 3
			if perim < 1 then
				lx, lz = -ctx.halfW, perim * ctx.depth
			elseif perim < 2 then
				lx, lz = -ctx.halfW + (perim - 1) * 2 * ctx.halfW, ctx.depth
			else
				lx, lz = ctx.halfW, ctx.depth - (perim - 2) * ctx.depth
			end
			p.CFrame = CFrame.new(ctx.toWorld(lx, 3.8 + math.sin(t * 2 + i) * 0.1, lz))
		end
	end
end

function ValleyArt.hasPiece(id: string): boolean
	return BUILDERS[id] ~= nil
end

-- Show piece `id` at weight w (0 hides it; its parts are destroyed after 2 s at 0).
function ValleyArt.updatePiece(self: any, id: string, w: number, t: number, ctx: any)
	local piece = self.pieces[id]
	if w <= 0.001 then
		if piece then
			piece.zeroSince = piece.zeroSince or t
			for _, e in piece.parts do e[1].Transparency = 1 end
			for _, l in piece.lights do l.Enabled = false end
			if t - piece.zeroSince >= 2 then
				for _, e in piece.parts do e[1]:Destroy() end
				for _, l in piece.lights do
					local idx = table.find(self.lights, l)
					if idx then table.remove(self.lights, idx) end
				end
				self.pieces[id] = nil
			end
		end
		return
	end
	if piece == nil then
		local builder = BUILDERS[id]
		if builder == nil then return end
		local parts, lights, anim = builder(self, id, ctx)
		piece = { parts = parts, lights = lights or {}, anim = anim }
		self.pieces[id] = piece
	end
	piece.zeroSince = nil
	for _, e in piece.parts do
		local base = e[2]
		e[1].Transparency = 1 - (1 - base) * w
		if e.tint and ctx.ground then e[1].Color = c3(ctx.ground) end
	end
	for _, l in piece.lights do l.Enabled = true end
	if piece.anim then piece.anim(t, w) end
end

-- ── critters ─────────────────────────────────────────────────────────────────────────────────────────
local CRITTER_LOOK = {
	butterfly = { size = Vector3.new(0.8, 0.1, 0.5), color = Color3.fromRGB(255, 240, 140), neon = false },
	bee = { size = Vector3.new(0.4, 0.4, 0.5), color = Color3.fromRGB(250, 200, 40), neon = false },
	sparrow = { size = Vector3.new(0.9, 0.4, 1.2), color = Color3.fromRGB(150, 110, 70), neon = false },
	crow = { size = Vector3.new(2.4, 0.4, 1.4), color = Color3.fromRGB(25, 25, 30), neon = false },
	goose = { size = Vector3.new(3, 0.6, 2), color = Color3.fromRGB(230, 230, 225), neon = false },
	owl = { size = Vector3.new(1.6, 1.6, 1.6), color = Color3.fromRGB(245, 245, 250), neon = false },
	sprite = { size = Vector3.new(0.6, 0.6, 0.6), color = Color3.fromRGB(150, 230, 255), neon = true },
	firefly = { size = Vector3.new(0.35, 0.35, 0.35), color = Color3.fromRGB(255, 240, 120), neon = true },
}

function ValleyArt.updateCritters(self: any, counts: { [string]: number }, camPos: Vector3, dt: number, t: number)
	local Env = self.Config.Env
	local cap = self.Config.Budget.MaxCritterParts
	local have: { [string]: number } = {}
	for i = #self.critters, 1, -1 do
		local c = self.critters[i]
		local spec = Env.Critters[c.kind]
		c.pos = c.pos + c.vel * dt
		local want = counts[c.kind] or 0
		have[c.kind] = (have[c.kind] or 0) + 1
		local centre = { x = camPos.X, y = self.groundY, z = camPos.Z }
		local expired = self.EnvBands.ambientExpired({ x = c.pos.X, y = c.pos.Y, z = c.pos.Z }, centre, spec)
		if expired or have[c.kind] > want then
			c.part:Destroy()
			table.remove(self.critters, i)
			have[c.kind] -= 1
		else
			local flap = if c.kind == "butterfly" or c.kind == "firefly" then math.sin(t * 9 + c.phase) * 0.3 else 0
			c.part.CFrame = CFrame.lookAt(c.pos + Vector3.new(0, flap, 0), c.pos + c.vel + Vector3.new(0, flap, 0))
			if c.kind == "firefly" then
				c.part.Transparency = if math.sin(t * 2.5 + c.phase) > 0.2 then 0 else 0.8
			end
		end
	end
	local kinds = {}
	for kind in counts do table.insert(kinds, kind) end
	table.sort(kinds)
	for _, kind in kinds do
		local spec, look = Env.Critters[kind], CRITTER_LOOK[kind]
		while spec and look and (have[kind] or 0) < counts[kind] and #self.critters < cap do
			local s = self.EnvBands.ambientSpawn({ x = camPos.X, y = self.groundY, z = camPos.Z }, spec, self.rand)
			local pos = Vector3.new(s.pos.x, s.pos.y, s.pos.z)
			local p = self:part(self.Critters, { Name = "Critter_" .. kind, Size = look.size, Color = look.color,
				Material = if look.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				Shape = if kind == "owl" or kind == "bee" or look.neon then Enum.PartType.Ball else Enum.PartType.Block,
				CFrame = CFrame.new(pos) })
			table.insert(self.critters, { part = p, kind = kind, pos = pos, vel = Vector3.new(s.vel.x, s.vel.y, s.vel.z), phase = self.rand() * 6 })
			have[kind] = (have[kind] or 0) + 1
		end
	end
end

-- ── weather: one host part over the camera, one emitter per kind ────────────────────────────────────
local WEATHER_LOOK = {
	fluff = { color = Color3.fromRGB(255, 255, 250), size = 0.25, speed = 2, accel = Vector3.new(1, -0.3, 0), life = 6, light = 0.2 },
	pollen = { color = Color3.fromRGB(255, 230, 120), size = 0.15, speed = 1, accel = Vector3.new(0.4, -0.1, 0), life = 6, light = 0.5 },
	leaves = { color = Color3.fromRGB(220, 110, 40), size = 0.5, speed = 3, accel = Vector3.new(3, -2, 1), life = 5, light = 0 },
	drizzle = { color = Color3.fromRGB(190, 200, 230), size = 0.1, speed = 30, accel = Vector3.new(0, -20, 0), life = 1.5, light = 0 },
	rain = { color = Color3.fromRGB(180, 190, 230), size = 0.12, speed = 60, accel = Vector3.new(0, -40, 0), life = 1, light = 0 },
	snow = { color = Color3.fromRGB(255, 255, 255), size = 0.3, speed = 4, accel = Vector3.new(0.5, -3, 0), life = 5, light = 0.3 },
	sparks = { color = Color3.fromRGB(255, 200, 120), size = 0.2, speed = 3, accel = Vector3.new(0, 2, 0), life = 3, light = 1 },
	glints = { color = Color3.fromRGB(230, 240, 255), size = 0.2, speed = 0.5, accel = Vector3.new(0, 0.2, 0), life = 2, light = 1 },
}

function ValleyArt.hasWeather(kind: string): boolean
	return WEATHER_LOOK[kind] ~= nil
end

-- rates: { [kind] = particles per second }, ALREADY capped by EnvBands.capRates in Sky.client
function ValleyArt.updateWeather(self: any, rates: { [string]: number }, camPos: Vector3)
	if self.weatherHost == nil then
		self.weatherHost = self:part(self.Weather, { Name = "WeatherHost", Size = Vector3.new(90, 1, 90), Transparency = 1 })
	end
	self.weatherHost.CFrame = CFrame.new(camPos + Vector3.new(0, 30, 0))
	for kind, rate in rates do
		if self.emitters[kind] == nil and WEATHER_LOOK[kind] then
			local look = WEATHER_LOOK[kind]
			local e = Instance.new("ParticleEmitter")
			e.Name = "Weather_" .. kind
			e.Color = ColorSequence.new(look.color)
			e.Size = NumberSequence.new(look.size)
			e.Speed = NumberRange.new(look.speed * 0.6, look.speed)
			e.Acceleration = look.accel
			e.Lifetime = NumberRange.new(look.life * 0.7, look.life)
			e.LightEmission = look.light
			e.EmissionDirection = Enum.NormalId.Bottom
			e.Rate = 0
			e.Enabled = false
			e.Parent = self.weatherHost
			self.emitters[kind] = e
		end
	end
	for kind, e in self.emitters do
		local r = rates[kind] or 0
		e.Rate = r
		e.Enabled = r > 0
	end
end

function ValleyArt.enabledEmitters(self: any): number
	local n = 0
	for _, e in self.emitters do
		if e.Enabled then n += 1 end
	end
	return n
end

-- ── the rainbow arc: seven curved Beams in front of the camera ───────────────────────────────────────
local RAINBOW = { { 255, 60, 60 }, { 255, 150, 40 }, { 255, 230, 60 }, { 80, 220, 90 }, { 60, 150, 255 }, { 90, 80, 220 }, { 170, 90, 230 } }
function ValleyArt.updateRainbow(self: any, w: number, camCF: CFrame)
	if w <= 0.001 then
		if self.rainbow then
			for _, b in self.rainbow.beams do b.Enabled = false end
		end
		return
	end
	if self.rainbow == nil then
		local a = self:part(self.Rainbow, { Name = "RainbowA", Size = Vector3.new(1, 1, 1), Transparency = 1 })
		local b = self:part(self.Rainbow, { Name = "RainbowB", Size = Vector3.new(1, 1, 1), Transparency = 1 })
		local beams = {}
		for i, col in RAINBOW do
			local a0 = Instance.new("Attachment")
			a0.Name = "A" .. i
			a0.Position = Vector3.new(i * 7, 0, 0)
			a0.Axis = Vector3.new(0, 1, 0)
			a0.SecondaryAxis = Vector3.new(1, 0, 0)
			a0.Parent = a
			local a1 = Instance.new("Attachment")
			a1.Name = "B" .. i
			a1.Position = Vector3.new(-i * 7, 0, 0)
			a1.Axis = Vector3.new(0, 1, 0)
			a1.SecondaryAxis = Vector3.new(1, 0, 0)
			a1.Parent = b
			local beam = Instance.new("Beam")
			beam.Name = "Band" .. i
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.CurveSize0 = 420 - i * 9
			beam.CurveSize1 = -(420 - i * 9)
			beam.Width0 = 8
			beam.Width1 = 8
			beam.FaceCamera = true
			beam.LightEmission = 0.6
			beam.Color = ColorSequence.new(Color3.fromRGB(col[1], col[2], col[3]))
			beam.Segments = 40
			beam.Parent = a
			beams[i] = beam
		end
		self.rainbow = { a = a, b = b, beams = beams }
	end
	local look = camCF.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, 1)
	local right = Vector3.new(flat.Z, 0, -flat.X)
	local centre = Vector3.new(camCF.Position.X, self.groundY, camCF.Position.Z) + flat * 380
	self.rainbow.a.CFrame = CFrame.new(centre - right * 330)
	self.rainbow.b.CFrame = CFrame.new(centre + right * 330)
	for _, beam in self.rainbow.beams do
		beam.Enabled = true
		beam.Transparency = NumberSequence.new(1 - 0.65 * math.clamp(w, 0, 1))
	end
end

-- ── lightning bolts: a zig-zag of neon segments, gone after 0.25 s ───────────────────────────────────
function ValleyArt.bolt(self: any, target: Vector3, t: number, color: Color3?): boolean
	if #self.bolts >= self.Config.Budget.MaxBolts then return false end
	local segs = {}
	local top = target + Vector3.new((self.rand() - 0.5) * 30, 140, (self.rand() - 0.5) * 30)
	local prev = top
	for i = 1, 4 do
		local f = i / 4
		local nextP = if i == 4 then target else top:Lerp(target, f) + Vector3.new((self.rand() - 0.5) * 10, 0, (self.rand() - 0.5) * 10)
		local len = (nextP - prev).Magnitude
		local p = self:part(self.Bolts, { Name = "Bolt", Size = Vector3.new(0.6, 0.6, len), Color = color or Color3.fromRGB(200, 225, 255),
			Material = Enum.Material.Neon, CFrame = CFrame.lookAt((prev + nextP) / 2, nextP) })
		table.insert(segs, p)
		prev = nextP
	end
	table.insert(self.bolts, { parts = segs, untilT = t + 0.25 })
	return true
end

function ValleyArt.updateBolts(self: any, t: number)
	for i = #self.bolts, 1, -1 do
		local b = self.bolts[i]
		if t >= b.untilT then
			for _, p in b.parts do p:Destroy() end
			table.remove(self.bolts, i)
		end
	end
end

-- ── hazards: the model, the red ring (= the zone) and the lane ───────────────────────────────────────
local HAZARD_LOOK = {
	hay = { { shape = Enum.PartType.Cylinder, size = Vector3.new(4, 5, 5), color = Color3.fromRGB(220, 190, 90), mat = Enum.Material.Fabric, roll = true } },
	crow = { { shape = Enum.PartType.Ball, size = Vector3.new(1.6, 1.6, 2.2), color = Color3.fromRGB(25, 25, 30) },
		{ shape = Enum.PartType.Block, size = Vector3.new(3.6, 0.3, 1.2), color = Color3.fromRGB(35, 35, 40), flap = true } },
	ballLightning = { { shape = Enum.PartType.Ball, size = Vector3.new(4, 4, 4), color = Color3.fromRGB(150, 220, 255), mat = Enum.Material.Neon, flicker = true } },
	snowball = { { shape = Enum.PartType.Ball, size = Vector3.new(5, 5, 5), color = Color3.fromRGB(245, 250, 255), mat = Enum.Material.Snow, roll = true } },
	dustDevil = { { shape = Enum.PartType.Cylinder, size = Vector3.new(3, 5, 5), color = Color3.fromRGB(190, 160, 110), t = 0.4, spin = 0 },
		{ shape = Enum.PartType.Cylinder, size = Vector3.new(3, 4, 4), color = Color3.fromRGB(200, 170, 120), t = 0.45, spin = 3 },
		{ shape = Enum.PartType.Cylinder, size = Vector3.new(2.5, 3, 3), color = Color3.fromRGB(210, 180, 130), t = 0.5, spin = 5.5 } },
}

function ValleyArt.showHazard(self: any, plan: any, pos: Vector3, zone: any?, t: number)
	local hz = self.hazard
	if hz == nil or hz.kind ~= plan.kind then
		self:hideHazard()
		local parts = {}
		for i, look in HAZARD_LOOK[plan.kind] or {} do
			parts[i] = self:part(self.Hazard, { Name = "Hazard_" .. plan.kind .. "_" .. i, Shape = look.shape, Size = look.size, Color = look.color,
				Material = look.mat or Enum.Material.SmoothPlastic, Transparency = look.t or 0 })
		end
		local ring = self:part(self.Hazard, { Name = "HazardRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1, 1),
			Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, Transparency = 0.45 })
		local lane = self:part(self.Hazard, { Name = "HazardLane", Size = Vector3.new(0.3, 0.3, 1), Color = Color3.fromRGB(255, 80, 60),
			Material = Enum.Material.Neon, Transparency = 0.5 })
		hz = { kind = plan.kind, parts = parts, ring = ring, lane = lane }
		self.hazard = hz
	end
	local vel = Vector3.new(plan.velocity.x, plan.velocity.y, plan.velocity.z)
	local dir = if vel.Magnitude > 1e-3 then vel.Unit else Vector3.new(0, 0, 1)
	local base = CFrame.lookAt(pos, pos + dir)
	for i, p in hz.parts do
		local look = HAZARD_LOOK[plan.kind][i]
		local cf = base
		if look.shape == Enum.PartType.Cylinder and plan.kind ~= "dustDevil" then
			cf = base * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(t * 6, 0, 0)
		elseif plan.kind == "dustDevil" then
			cf = CFrame.new(pos + Vector3.new(0, (i - 1) * 2.8, 0)) * CFrame.Angles(0, t * 8 + (look.spin or 0), math.rad(90))
		end
		if look.flap then cf = cf * CFrame.Angles(0, 0, math.sin(t * 14) * 0.5) end
		p.CFrame = cf
		if look.flicker then p.Transparency = if math.sin(t * 40) > 0.3 then 0 else 0.3 end
	end
	if zone then
		local r = zone.radius
		hz.ring.Size = Vector3.new(0.2, r * 2, r * 2)
		-- zone.y: the top of what the farmer stands on under the ring (Sky.client, HazardGlue.ringY); the ground if unset
		local base = zone.y or self.groundY
		hz.ring.CFrame = CFrame.new(zone.x, base + 0.15, zone.z) * CFrame.Angles(0, 0, math.rad(90))
		hz.ring.Transparency = 0.45
		local target = Vector3.new(zone.x, base + 0.3, zone.z)
		local from = Vector3.new(pos.X, base + 0.3, pos.Z)
		local len = (target - from).Magnitude
		if len > 0.5 and not plan.locked then
			hz.lane.Size = Vector3.new(0.3, 0.3, len)
			hz.lane.CFrame = CFrame.lookAt((from + target) / 2, target)
			hz.lane.Transparency = 0.5
		else
			hz.lane.Transparency = 1
		end
	else
		hz.ring.Transparency = 1
		hz.lane.Transparency = 1
	end
	hz.zoneShown = zone ~= nil
end

function ValleyArt.hideHazard(self: any)
	if self.hazard then
		for _, p in self.hazard.parts do p:Destroy() end
		self.hazard.ring:Destroy()
		self.hazard.lane:Destroy()
		self.hazard = nil
	end
end

-- ── lights: only the nearest MaxLights stay on ───────────────────────────────────────────────────────
function ValleyArt.capLights(self: any, camPos: Vector3): number
	local live = {}
	for _, l in self.lights do
		local host = l.Parent
		if host and host:IsA("BasePart") and l.Enabled ~= false then
			table.insert(live, { l = l, d = ((host :: BasePart).Position - camPos).Magnitude })
		end
	end
	table.sort(live, function(a, b) return a.d < b.d end)
	local on = 0
	for i, e in live do
		local keep = i <= self.Config.Budget.MaxLights
		e.l.Enabled = keep
		if keep then on += 1 end
	end
	return on
end

-- ── measurement (robloxemu checks) ────────────────────────────────────────────────────────────────────
function ValleyArt.counts(self: any): any
	local out = { scenery = 0, critters = 0, weather = 0, hazard = 0, bolts = 0, rainbow = 0, lightsOn = 0, emittersOn = 0, beams = 0 }
	for _, name in { "Scenery", "Critters", "Weather", "Hazard", "Bolts", "Rainbow" } do
		local n = 0
		for _, d in self[name]:GetDescendants() do
			if d:IsA("BasePart") then n += 1 end
			if d.ClassName == "PointLight" and d.Enabled then out.lightsOn += 1 end
			if d.ClassName == "Beam" and d.Enabled then out.beams += 1 end
		end
		out[string.lower(name)] = n
	end
	out.emittersOn = self:enabledEmitters()
	return out
end

return ValleyArt
