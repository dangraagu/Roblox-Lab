-- VaultArt.luau — Vault Runners' client-side eye candy: ceiling props, sky pieces over the top
-- storey, ambient weather, the collapse's dust and sparks, the ceiling drops, cracks on crumbling
-- pads, debris, and the hub's vault door. Code-only (no assets), CLIENT-ONLY.
--
-- Every Part made here is LOCAL (the client made it, so it never replicates), anchored, and
-- non-collidable / non-queryable / non-touchable with no shadow: nothing here can be stood on,
-- block a jump, catch a camera ray or trip a Touched. Everything is POOLED — built the first time it
-- is needed, moved and re-coloured afterwards, and unparented (not destroyed) when unused, so a band
-- you are not in costs no draw calls. robloxemu/check_vaultrunners_env.luau measures the budgets
-- (Config.Budget) every frame; EYECANDY.md has the table.
--
-- Positions come in as WORLD Vector3s from the glue (src/client/Vault.client.luau); this module
-- never reads the maze, the route, the gems or any other player. Like every shared module it
-- requires nothing: Config, EnvBands and VaultEnv are handed to `new`.

local VaultArt = {}
VaultArt.__index = VaultArt

local function rgb(c: any): Color3
	return Color3.fromRGB(math.clamp(math.round(c[1]), 0, 255), math.clamp(math.round(c[2]), 0, 255),
		math.clamp(math.round(c[3]), 0, 255))
end
VaultArt.rgb = rgb

local function seq(points: { { number } }): NumberSequence
	local kps = {}
	for _, p in points do
		kps[#kps + 1] = NumberSequenceKeypoint.new(p[1], p[2])
	end
	return NumberSequence.new(kps)
end

function VaultArt.new(folder: Instance, rand: () -> number, Config: any, EnvBands: any, VaultEnv: any): any
	local self = setmetatable({}, VaultArt)
	self.folder = folder
	self.rand = rand
	self.cfg = Config
	self.EnvBands = EnvBands
	self.VaultEnv = VaultEnv
	self.made = 0            -- Parts ever created (a pool that keeps growing is a leak)
	self.propPools = {}      -- [kind] = { items }
	self.propKey = nil
	self.pieces = {}         -- [id] = item
	self.weatherHost = nil
	self.weather = {}        -- [kind] = ParticleEmitter
	self.collapse = nil
	self.hazards = {}        -- [kind] = item
	self.shared = nil        -- ring, crack, stream host
	self.debris = {}         -- { part, vel, life }
	self.cracks = {}         -- [key] = item ; pool in self.crackPool
	self.crackPool = {}
	return self
end

--============================================================================ part factory

function VaultArt._part(self: any, name: string, size: Vector3, color: any, material: any, shape: any?, transparency: number?, wedge: boolean?): BasePart
	local p = Instance.new(if wedge then "WedgePart" else "Part") :: BasePart
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = rgb(color) -- always an {r, g, b} array here (typeof cannot tell a Color3 apart headless)
	p.Material = material
	if shape ~= nil then (p :: any).Shape = shape end
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	self.made += 1
	return p
end

-- An item is a group of parts placed together: { parts = { { part, offset: CFrame, role } }, on }.
local function newItem(): any
	return { parts = {}, on = false }
end

local function add(item: any, part: BasePart, offset: CFrame, role: string?)
	table.insert(item.parts, { part = part, offset = offset, role = role })
end

function VaultArt._place(self: any, item: any, cf: CFrame)
	for _, e in item.parts do
		e.part.CFrame = cf * e.offset
		if e.part.Parent ~= self.folder then e.part.Parent = self.folder end
	end
	item.on = true
end

function VaultArt._hide(self: any, item: any)
	if not item.on then return end
	for _, e in item.parts do
		e.part.Parent = nil
	end
	item.on = false
end

local function colourRole(item: any, role: string, color: Color3)
	for _, e in item.parts do
		if e.role == role and e.part.Color ~= color then e.part.Color = color end
	end
end

--============================================================================ ceiling props

local UP = CFrame.new()
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is X; this stands it up

-- How far below the ceiling each kind reaches (its lowest point). check_vaultrunners_env asserts
-- that ceiling - drop stays above Config.Env.PropBottomAboveFloor.
VaultArt.PropDrop = { lamp = 3.1, brazier = 2.3, panel = 2.75, icicles = 2.8, embers = 2.9 }

function VaultArt._buildProp(self: any, kind: string): any
	local it = newItem()
	local M = Enum.Material
	if kind == "lamp" then
		add(it, self:_part("PropRod", Vector3.new(0.25, 2, 0.25), { 90, 80, 60 }, M.Metal), CFrame.new(0, -1, 0), "accent")
		add(it, self:_part("PropBulb", Vector3.new(1.2, 1.2, 1.2), { 255, 226, 160 }, M.Neon, Enum.PartType.Ball), CFrame.new(0, -2.5, 0), "glow")
		add(it, self:_part("PropShade", Vector3.new(0.5, 1.8, 1.8), { 90, 80, 60 }, M.Metal, Enum.PartType.Cylinder), CFrame.new(0, -1.9, 0) * VERTICAL, "accent")
	elseif kind == "brazier" then
		add(it, self:_part("PropChain", Vector3.new(0.2, 1.6, 0.2), { 40, 34, 30 }, M.Metal), CFrame.new(0, -0.8, 0))
		add(it, self:_part("PropBowl", Vector3.new(0.6, 1.6, 1.6), { 46, 150, 160 }, M.Sandstone, Enum.PartType.Cylinder), CFrame.new(0, -1.9, 0) * VERTICAL, "accent")
		add(it, self:_part("PropFlame", Vector3.new(0.9, 0.9, 0.9), { 255, 166, 84 }, M.Neon, Enum.PartType.Ball), CFrame.new(0, -1.35, 0), "glow")
	elseif kind == "panel" then
		add(it, self:_part("PropPanel", Vector3.new(4.5, 0.3, 1), { 120, 230, 255 }, M.Neon), CFrame.new(0, -0.15, 0), "glow")
		add(it, self:_part("PropCable", Vector3.new(0.15, 2.4, 0.15), { 20, 22, 26 }, M.SmoothPlastic), CFrame.new(1.6, -1.2, 0))
		add(it, self:_part("PropBeacon", Vector3.new(0.5, 0.5, 0.5), { 0, 255, 210 }, M.Neon, Enum.PartType.Ball), CFrame.new(1.6, -2.5, 0), "accent")
	elseif kind == "icicles" then
		add(it, self:_part("PropIcicle", Vector3.new(0.55, 2.8, 0.55), { 190, 240, 255 }, M.Ice, nil, 0.15), CFrame.new(0, -1.4, 0) * CFrame.Angles(0, math.pi / 4, 0), "glow")
		add(it, self:_part("PropIcicle", Vector3.new(0.4, 2, 0.4), { 190, 240, 255 }, M.Ice, nil, 0.15), CFrame.new(0.8, -1, 0.3) * CFrame.Angles(0, math.pi / 4, 0), "glow")
		add(it, self:_part("PropIcicle", Vector3.new(0.35, 1.4, 0.35), { 190, 240, 255 }, M.Ice, nil, 0.15), CFrame.new(-0.7, -0.7, -0.4) * CFrame.Angles(0, math.pi / 4, 0), "glow")
	else -- embers
		add(it, self:_part("PropChain", Vector3.new(0.25, 1.8, 0.25), { 30, 22, 20 }, M.Metal), CFrame.new(0, -0.9, 0))
		add(it, self:_part("PropCage", Vector3.new(1.3, 1.3, 1.3), { 40, 30, 28 }, M.Basalt, Enum.PartType.Ball, 0.35), CFrame.new(0, -2.25, 0))
		add(it, self:_part("PropEmber", Vector3.new(0.8, 0.8, 0.8), { 255, 110, 30 }, M.Neon, Enum.PartType.Ball), CFrame.new(0, -2.25, 0), "glow")
	end
	return it
end

-- Hang props for the given sites. `sites` = { { pos: Vector3 (the ceiling point), kind, yaw,
-- accent: Color3, glow: Color3 } }. `key` changes only when the set changes (a new storey, a new
-- run), so on most frames this is one comparison.
function VaultArt.updateProps(self: any, key: string?, sites: { any }?)
	if key == self.propKey then return end
	self.propKey = key
	local used = {}
	for kind, pool in self.propPools do used[kind] = 0 end
	for _, s in sites or {} do
		local pool = self.propPools[s.kind]
		if pool == nil then
			pool = {}
			self.propPools[s.kind] = pool
			used[s.kind] = 0
		end
		used[s.kind] += 1
		local item = pool[used[s.kind]]
		if item == nil then
			item = self:_buildProp(s.kind)
			pool[used[s.kind]] = item
		end
		self:_place(item, CFrame.new(s.pos) * CFrame.Angles(0, s.yaw or 0, 0))
		colourRole(item, "accent", s.accent)
		colourRole(item, "glow", s.glow)
	end
	for kind, pool in self.propPools do
		for i = (used[kind] or 0) + 1, #pool do
			self:_hide(pool[i])
		end
	end
end

--============================================================================ sky pieces (over the top storey)

local function ring(self: any, it: any, n: number, radius: number, size: Vector3, color: any, material: any, role: string?)
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2
		add(it, self:_part("Ring", size, color, material), CFrame.Angles(0, a, 0) * CFrame.new(0, 0, radius), role)
	end
end

function VaultArt._buildPiece(self: any, id: string): any
	local it = newItem()
	local M = Enum.Material
	if id == "dome" then
		-- the bank's great hall over the vault: a brass ring and a skylight
		ring(self, it, 8, 70, Vector3.new(56, 3, 3), { 214, 172, 82 }, M.Metal, "accent")
		add(it, self:_part("Skylight", Vector3.new(3, 118, 118), { 255, 236, 190 }, M.Glass, Enum.PartType.Cylinder, 0.45), VERTICAL, "glow")
	elseif id == "sunDisc" then
		-- a winged sun over the tomb
		add(it, self:_part("Sun", Vector3.new(3, 80, 80), { 255, 176, 84 }, M.Neon, Enum.PartType.Cylinder), VERTICAL, "glow")
		add(it, self:_part("Wing", Vector3.new(4, 12, 70), { 214, 172, 110 }, M.Sandstone, nil, 0, true), CFrame.new(-75, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), "accent")
		add(it, self:_part("Wing", Vector3.new(4, 12, 70), { 214, 172, 110 }, M.Sandstone, nil, 0, true), CFrame.new(75, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), "accent")
	elseif id == "reactorRing" then
		-- a reactor ring turning slowly over the vault, and its core
		ring(self, it, 10, 60, Vector3.new(38, 4, 4), { 0, 255, 210 }, M.Neon, "accent")
		add(it, self:_part("Core", Vector3.new(24, 24, 24), { 120, 230, 255 }, M.Neon, Enum.PartType.Ball, 0.2), UP, "glow")
		it.spin = 0.15
	elseif id == "aurora" then
		-- the frozen vault's sky: a pale moon and aurora ribbons (Beams between two anchors)
		add(it, self:_part("Moon", Vector3.new(30, 30, 30), { 226, 240, 255 }, M.Neon, Enum.PartType.Ball), CFrame.new(90, 60, -40), "glow")
		local a = self:_part("AuroraA", Vector3.new(1, 1, 1), { 0, 0, 0 }, M.SmoothPlastic, nil, 1)
		local b = self:_part("AuroraB", Vector3.new(1, 1, 1), { 0, 0, 0 }, M.SmoothPlastic, nil, 1)
		add(it, a, CFrame.new(-160, 10, 0))
		add(it, b, CFrame.new(160, 30, 0))
		it.beams = {}
		for i = 1, 3 do
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0, (i - 2) * 50)
			a0.Parent = a
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, 20 * i, (i - 2) * 50 - 40)
			a1.Parent = b
			local beam = Instance.new("Beam")
			beam.Name = "Aurora"
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0 = 40
			beam.Width1 = 70
			beam.CurveSize0 = 60
			beam.CurveSize1 = -60
			beam.FaceCamera = false
			beam.LightEmission = 1
			beam.Color = ColorSequence.new(Color3.fromRGB(90, 255, 180), Color3.fromRGB(120, 160, 255))
			beam.Transparency = seq({ { 0, 1 }, { 0.3, 0.55 }, { 0.7, 0.6 }, { 1, 1 } })
			beam.Parent = a
			table.insert(it.beams, beam)
		end
	else -- eruption
		-- the volcano temple: a crater rim of basalt around a lake of light
		ring(self, it, 8, 78, Vector3.new(62, 10, 12), { 40, 28, 26 }, M.Basalt)
		add(it, self:_part("Lava", Vector3.new(3, 140, 140), { 255, 110, 30 }, M.Neon, Enum.PartType.Cylinder, 0.2), CFrame.new(0, 3, 0) * VERTICAL, "glow")
	end
	return it
end

-- Show the sky pieces with weight > 0 above `anchor` (a CFrame high over the top storey), hide the
-- rest. weights = { [pieceId] = 0..1 }. Pieces are built the first time they are needed.
function VaultArt.updatePieces(self: any, weights: { [string]: number }, anchor: CFrame?, now: number, pal: any)
	for id, w in weights do
		if w > 0.01 and anchor ~= nil and self.pieces[id] == nil then
			self.pieces[id] = self:_buildPiece(id)
		end
	end
	for id, it in self.pieces do
		local w = weights[id] or 0
		if w > 0.01 and anchor ~= nil then
			local cf = anchor
			if it.spin then cf = cf * CFrame.Angles(0, now * it.spin, 0) end
			self:_place(it, cf)
			if pal then colourRole(it, "accent", rgb(pal.accent)) end
			for _, e in it.parts do
				local base = e.base
				if base == nil then
					base = e.part.Transparency
					e.base = base
				end
				local want = 1 - (1 - base) * w
				if math.abs(e.part.Transparency - want) > 0.02 then e.part.Transparency = want end
			end
			for _, beam in it.beams or {} do
				if beam.Enabled ~= (w > 0.3) then beam.Enabled = w > 0.3 end
			end
		else
			self:_hide(it)
		end
	end
end

--============================================================================ weather around the camera

local WEATHER = {
	glitter = function(pe: ParticleEmitter)
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 226, 150))
		pe.Size = seq({ { 0, 0.12 }, { 0.5, 0.2 }, { 1, 0 } })
		pe.Transparency = seq({ { 0, 1 }, { 0.2, 0.2 }, { 1, 1 } })
		pe.Lifetime = NumberRange.new(3, 5)
		pe.Speed = NumberRange.new(0.5, 1.5)
		pe.Acceleration = Vector3.new(0, -0.6, 0)
		pe.LightEmission = 1
	end,
	sand = function(pe: ParticleEmitter)
		pe.Color = ColorSequence.new(Color3.fromRGB(226, 186, 128))
		pe.Size = seq({ { 0, 0.1 }, { 1, 0.18 } })
		pe.Transparency = seq({ { 0, 0.3 }, { 1, 1 } })
		pe.Lifetime = NumberRange.new(2, 3.5)
		pe.Speed = NumberRange.new(2, 4)
		pe.Acceleration = Vector3.new(2.5, -3, 0.8)
		pe.LightEmission = 0.2
	end,
	sparks = function(pe: ParticleEmitter)
		pe.Color = ColorSequence.new(Color3.fromRGB(150, 245, 255))
		pe.Size = seq({ { 0, 0.22 }, { 1, 0 } })
		pe.Transparency = seq({ { 0, 0 }, { 1, 1 } })
		pe.Lifetime = NumberRange.new(0.35, 0.7)
		pe.Speed = NumberRange.new(6, 11)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Acceleration = Vector3.new(0, -20, 0)
		pe.LightEmission = 1
	end,
	snow = function(pe: ParticleEmitter)
		pe.Color = ColorSequence.new(Color3.fromRGB(245, 250, 255))
		pe.Size = seq({ { 0, 0.22 }, { 1, 0.28 } })
		pe.Transparency = seq({ { 0, 0.15 }, { 0.8, 0.3 }, { 1, 1 } })
		pe.Lifetime = NumberRange.new(5, 7)
		pe.Speed = NumberRange.new(1, 2)
		pe.Acceleration = Vector3.new(0.4, -1.2, 0)
		pe.RotSpeed = NumberRange.new(-40, 40)
		pe.LightEmission = 0.3
	end,
	embers = function(pe: ParticleEmitter)
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(255, 60, 20))
		pe.Size = seq({ { 0, 0.25 }, { 1, 0 } })
		pe.Transparency = seq({ { 0, 0 }, { 1, 1 } })
		pe.Lifetime = NumberRange.new(2.5, 4)
		pe.Speed = NumberRange.new(1, 3)
		pe.Acceleration = Vector3.new(0, 2.5, 0)
		pe.LightEmission = 1
	end,
}
VaultArt.WeatherKinds = WEATHER

function VaultArt.hasWeather(kind: string): boolean
	return WEATHER[kind] ~= nil
end

-- rates = { [kind] = particles/s } already capped by the caller (EnvBands.capRates). Kinds absent
-- from `rates` are switched off.
function VaultArt.updateWeather(self: any, rates: { [string]: number }, camPos: Vector3?)
	local any = false
	for _, r in rates do if r > 0 then any = true end end
	if self.weatherHost == nil and any then
		self.weatherHost = self:_part("WeatherHost", Vector3.new(50, 1, 50), { 0, 0, 0 }, Enum.Material.SmoothPlastic, nil, 1)
	end
	local host = self.weatherHost
	if host == nil then return end
	if camPos and any then
		host.CFrame = CFrame.new(camPos + Vector3.new(0, 10, 0))
		if host.Parent ~= self.folder then host.Parent = self.folder end
	end
	for kind, r in rates do
		if r > 0 and self.weather[kind] == nil and WEATHER[kind] then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "Weather_" .. kind
			pe.Enabled = false
			pe.Rate = 0
			pe.EmissionDirection = Enum.NormalId.Bottom
			WEATHER[kind](pe)
			pe.Parent = host
			self.weather[kind] = pe
		end
	end
	for kind, pe in self.weather do
		local r = rates[kind] or 0
		local on = r > 0
		if pe.Enabled ~= on then pe.Enabled = on end
		if on and math.abs(pe.Rate - r) > 0.05 then pe.Rate = r end
	end
	if not any and host.Parent ~= nil then host.Parent = nil end
end

--============================================================================ the collapse

-- Ceiling dust over the runner (the storey above is giving way) and sparks off the kill plane.
-- dust/sparks are particles/s; nil switches both off (no run).
function VaultArt.updateCollapse(self: any, ceilingCF: CFrame?, planeCF: CFrame?, planeSize: Vector3?, dust: number, sparks: number)
	local c = self.collapse
	if c == nil then
		if ceilingCF == nil then return end
		c = {}
		c.dustHost = self:_part("CeilingDust", Vector3.new(36, 0.4, 36), { 0, 0, 0 }, Enum.Material.SmoothPlastic, nil, 1)
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Dust"
		pe.EmissionDirection = Enum.NormalId.Bottom
		pe.Color = ColorSequence.new(Color3.fromRGB(170, 150, 128))
		pe.Size = seq({ { 0, 0.3 }, { 1, 0.7 } })
		pe.Transparency = seq({ { 0, 0.55 }, { 1, 1 } })
		pe.Lifetime = NumberRange.new(1.5, 2.5)
		pe.Speed = NumberRange.new(1, 3)
		pe.Acceleration = Vector3.new(0, -8, 0)
		pe.Rate = 0
		pe.Enabled = false
		pe.Parent = c.dustHost
		c.dust = pe
		c.sparkHost = self:_part("PlaneSparks", Vector3.new(10, 0.4, 10), { 0, 0, 0 }, Enum.Material.SmoothPlastic, nil, 1)
		local sp = Instance.new("ParticleEmitter")
		sp.Name = "Sparks"
		sp.EmissionDirection = Enum.NormalId.Top
		sp.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(255, 70, 40))
		sp.Size = seq({ { 0, 0.35 }, { 1, 0 } })
		sp.Transparency = seq({ { 0, 0 }, { 1, 1 } })
		sp.Lifetime = NumberRange.new(0.6, 1.2)
		sp.Speed = NumberRange.new(8, 16)
		sp.SpreadAngle = Vector2.new(25, 25)
		sp.Acceleration = Vector3.new(0, -12, 0)
		sp.LightEmission = 1
		sp.Rate = 0
		sp.Enabled = false
		sp.Parent = c.sparkHost
		c.sparks = sp
		self.collapse = c
	end
	if ceilingCF then
		c.dustHost.CFrame = ceilingCF
		if c.dustHost.Parent ~= self.folder then c.dustHost.Parent = self.folder end
	elseif c.dustHost.Parent ~= nil then
		c.dustHost.Parent = nil
	end
	if planeCF and planeSize then
		c.sparkHost.CFrame = planeCF
		if c.sparkHost.Size ~= planeSize then c.sparkHost.Size = planeSize end
		if c.sparkHost.Parent ~= self.folder then c.sparkHost.Parent = self.folder end
	elseif c.sparkHost.Parent ~= nil then
		c.sparkHost.Parent = nil
	end
	local dOn, sOn = ceilingCF ~= nil and dust > 0, planeCF ~= nil and sparks > 0
	if c.dust.Enabled ~= dOn then c.dust.Enabled = dOn end
	if c.sparks.Enabled ~= sOn then c.sparks.Enabled = sOn end
	if dOn and math.abs(c.dust.Rate - dust) > 0.05 then c.dust.Rate = dust end
	if sOn and math.abs(c.sparks.Rate - sparks) > 0.05 then c.sparks.Rate = sparks end
end

--============================================================================ ceiling drops

function VaultArt._buildHazard(self: any, kind: string): any
	local it = newItem()
	local M = Enum.Material
	if kind == "marble" then
		add(it, self:_part("Hazard_marble_slab", Vector3.new(3.2, 1.2, 3.2), { 222, 214, 198 }, M.Marble), UP)
		add(it, self:_part("Hazard_marble_trim", Vector3.new(3.4, 0.3, 3.4), { 214, 172, 82 }, M.Metal), CFrame.new(0, 0.6, 0))
	elseif kind == "sandstone" then
		add(it, self:_part("Hazard_sandstone_block", Vector3.new(3.2, 2, 3.2), { 214, 172, 110 }, M.Sandstone), UP)
		add(it, self:_part("Hazard_sandstone_glyph", Vector3.new(3.3, 0.35, 3.3), { 46, 150, 160 }, M.SmoothPlastic), CFrame.new(0, 0.3, 0))
	elseif kind == "pipe" then
		add(it, self:_part("Hazard_pipe_body", Vector3.new(4.5, 1.4, 1.4), { 120, 126, 136 }, M.Metal, Enum.PartType.Cylinder), UP)
		add(it, self:_part("Hazard_pipe_band", Vector3.new(0.5, 1.6, 1.6), { 0, 255, 210 }, M.Neon, Enum.PartType.Cylinder), UP)
	elseif kind == "icicle" then
		add(it, self:_part("Hazard_icicle_big", Vector3.new(1.3, 5, 1.3), { 200, 236, 255 }, M.Ice, nil, 0.1), CFrame.new(0, 1.2, 0) * CFrame.Angles(0, math.pi / 4, 0))
		add(it, self:_part("Hazard_icicle_small", Vector3.new(0.8, 3, 0.8), { 200, 236, 255 }, M.Ice, nil, 0.1), CFrame.new(0.9, 1.8, 0.4))
	else -- lavaBomb
		add(it, self:_part("Hazard_lavaBomb_crust", Vector3.new(2.6, 2.6, 2.6), { 60, 40, 36 }, M.Basalt, Enum.PartType.Ball, 0.25), UP)
		add(it, self:_part("Hazard_lavaBomb_core", Vector3.new(2.1, 2.1, 2.1), { 255, 120, 40 }, M.Neon, Enum.PartType.Ball), UP)
	end
	-- How far the model reaches above (top) and below (bottom) its own origin, rotation included, so
	-- showHazard can hang it FROM the ceiling and lay it ON the floor whatever its shape.
	local top, bottom = -math.huge, -math.huge
	for _, e in it.parts do
		local cf, sz = e.offset, e.part.Size
		local half = 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
		top = math.max(top, cf.Position.Y + half)
		bottom = math.max(bottom, half - cf.Position.Y)
	end
	it.top, it.bottom = top, bottom
	return it
end

function VaultArt._sharedHazard(self: any): any
	if self.shared then return self.shared end
	local s = {}
	-- built 1 stud across on purpose: showHazard sizes it to the zone every time, and a ring that
	-- was never sized would show as a dot (check_vaultrunners_hazards measures the width)
	s.ring = self:_part("HazardRing", Vector3.new(0.12, 1, 1), { 255, 210, 60 }, Enum.Material.Neon, Enum.PartType.Cylinder, 0.35)
	s.crack = self:_part("HazardCeilingCrack", Vector3.new(4, 0.1, 4), { 36, 26, 22 }, Enum.Material.SmoothPlastic, nil, 0.15)
	s.stream = self:_part("HazardStream", Vector3.new(2.5, 0.2, 2.5), { 0, 0, 0 }, Enum.Material.SmoothPlastic, nil, 1)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Trickle"
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.Color = ColorSequence.new(Color3.fromRGB(190, 170, 140))
	pe.Size = seq({ { 0, 0.25 }, { 1, 0.5 } })
	pe.Transparency = seq({ { 0, 0.3 }, { 1, 1 } })
	pe.Lifetime = NumberRange.new(0.8, 1.2)
	pe.Speed = NumberRange.new(4, 7)
	pe.Acceleration = Vector3.new(0, -20, 0)
	pe.Rate = 0
	pe.Enabled = false
	pe.Parent = s.stream
	s.trickle = pe
	local light = Instance.new("PointLight")
	light.Name = "HazardBlink"
	light.Color = Color3.fromRGB(255, 80, 60)
	light.Range = 12
	light.Brightness = 0
	light.Shadows = false
	light.Parent = s.ring
	s.light = light
	self.shared = s
	return s
end

-- Draw a drop in flight. `pos` = where the chunk is (world; its X and Z are the landing column),
-- `zone` = { centre: Vector3 on the floor, radius }, `ceiling` = world Y of the ceiling underside over
-- it, `locked`, `landed`, and `fall` = how far down it is, 0 (hanging) .. 1 (down). The rule
-- (Hazards.positionAt) moves a POINT from dropHeight over the runner's root to the root; the model is
-- drawn so that the same fall takes it from hanging off the ceiling (its top at the underside) to
-- lying on the floor (its bottom on the floor). Without `fall` it is drawn at `pos` as given.
-- `ring` = { color = {r, g, b}, transparency } is how the ring is drawn over this floor: the glue
-- passes VaultEnv.ring (the first colour that reads against the floor under it; yellow read 1.16:1
-- on the Frozen Vault's snow). Without it, the template's yellow / red.
function VaultArt.showHazard(self: any, kind: string, pos: Vector3, zone: any, ceiling: number, locked: boolean, landed: boolean, now: number, fall: number?, ring: any?)
	local it = self.hazards[kind]
	if it == nil then
		it = self:_buildHazard(kind)
		self.hazards[kind] = it
	end
	local s = self:_sharedHazard()
	local at = pos
	if fall ~= nil then
		local hangY = ceiling - it.top
		local restY = zone.centre.Y + it.bottom
		local f = math.clamp(fall, 0, 1)
		at = Vector3.new(pos.X, hangY + (restY - hangY) * f, pos.Z)
	end
	-- the chunk: shakes in place while it hangs, falls straight when it goes
	local wobble = if landed or locked then 0 else 0.06
	local shake = CFrame.Angles(math.sin(now * 37) * wobble, 0, math.cos(now * 29) * wobble)
	self:_place(it, CFrame.new(at) * shake)
	-- the ring: exactly the zone the rule uses (hitRadius + PlayerRadius), on the floor
	local d = zone.radius * 2
	if s.ring.Size.Y ~= d then s.ring.Size = Vector3.new(0.12, d, d) end
	s.ring.CFrame = CFrame.new(zone.centre + Vector3.new(0, 0.08, 0)) * VERTICAL
	local ringColor = if ring then rgb(ring.color) elseif locked then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(255, 210, 60)
	if s.ring.Color ~= ringColor then s.ring.Color = ringColor end
	local ringT = if landed then 1 elseif ring then ring.transparency else 0.35
	if s.ring.Transparency ~= ringT then s.ring.Transparency = ringT end
	-- the crack in the ceiling and the dust trickling out of it, over the landing point
	s.crack.CFrame = CFrame.new(Vector3.new(pos.X, ceiling - 0.05, pos.Z))
	s.stream.CFrame = CFrame.new(Vector3.new(pos.X, ceiling - 0.2, pos.Z))
	for _, p in { s.ring, s.crack, s.stream } do
		if p.Parent ~= self.folder then p.Parent = self.folder end
	end
	local trickle = if landed then 0 else (if locked then 40 else 18)
	if s.trickle.Enabled ~= (trickle > 0) then s.trickle.Enabled = trickle > 0 end
	if trickle > 0 and s.trickle.Rate ~= trickle then s.trickle.Rate = trickle end
	local blink = if landed then 0 elseif (math.floor(now * (if locked then 8 else 3)) % 2 == 0) then 2 else 0
	if s.light.Brightness ~= blink then s.light.Brightness = blink end
end

function VaultArt.hideHazard(self: any, kind: string?)
	for k, it in self.hazards do
		if kind == nil or k == kind then self:_hide(it) end
	end
	local s = self.shared
	if s then
		for _, p in { s.ring, s.crack, s.stream } do p.Parent = nil end
		s.trickle.Enabled = false
		s.light.Brightness = 0
	end
end

--============================================================================ debris (landings, pads)

-- Throw `n` pooled chunks from `at`, coloured `color`; they fall under gravity and fade.
function VaultArt.burst(self: any, at: Vector3, color: Color3, n: number, spread: number)
	local fresh = 0
	for _, d in self.debris do
		if d.life <= 0 and fresh < n then
			fresh += 1
			self:_launch(d, at, color, spread)
		end
	end
	while fresh < n and #self.debris < 8 do
		fresh += 1
		local d = { part = self:_part("Debris", Vector3.new(0.7, 0.5, 0.6), { 0, 0, 0 }, Enum.Material.Slate), vel = Vector3.zero, life = 0 }
		table.insert(self.debris, d)
		self:_launch(d, at, color, spread)
	end
end

function VaultArt._launch(self: any, d: any, at: Vector3, color: Color3, spread: number)
	local a = self.rand() * math.pi * 2
	local sp = spread * (0.5 + 0.5 * self.rand())
	d.vel = Vector3.new(math.cos(a) * sp, 6 + 6 * self.rand(), math.sin(a) * sp)
	d.life = 1
	d.part.Color = color
	d.part.Transparency = 0
	d.part.CFrame = CFrame.new(at)
	d.part.Parent = self.folder
end

function VaultArt.step(self: any, dt: number)
	for _, d in self.debris do
		if d.life > 0 then
			d.life -= dt
			if d.life <= 0 then
				d.part.Parent = nil
			else
				d.vel += Vector3.new(0, -60 * dt, 0)
				d.part.CFrame = d.part.CFrame + d.vel * dt
				d.part.Transparency = 1 - d.life
			end
		end
	end
end

--============================================================================ pad cracks

-- The pad the runner stands on is cracking: `progress` 0..1 of its crumble. Three dark cracks
-- spread across its top; the caller also pulls the pad's own colour toward the crack colour
-- (VaultEnv.crackedPad) so the whole pad reads "going". key = "storey:index".
function VaultArt.padCrack(self: any, key: string, top: Vector3, progress: number)
	local it = self.cracks[key]
	if it == nil then
		it = table.remove(self.crackPool)
		if it == nil then
			it = newItem()
			for i = 1, 3 do
				local p = self:_part("PadCrack", Vector3.new(2.6, 0.08, 0.14), { 30, 18, 14 }, Enum.Material.SmoothPlastic, nil, 0.8)
				add(it, p, CFrame.Angles(0, (i - 1) * math.pi / 3 + 0.3, 0))
			end
		end
		self.cracks[key] = it
	end
	self:_place(it, CFrame.new(top + Vector3.new(0, 0.05, 0)))
	local t = 0.85 - 0.75 * math.clamp(progress, 0, 1)
	for _, e in it.parts do
		if math.abs(e.part.Transparency - t) > 0.02 then e.part.Transparency = t end
		local len = 1.2 + 1.6 * math.clamp(progress, 0, 1)
		if math.abs(e.part.Size.X - len) > 0.05 then e.part.Size = Vector3.new(len, 0.08, 0.14) end
	end
end

function VaultArt.padCrackEnd(self: any, key: string)
	local it = self.cracks[key]
	if it then
		self:_hide(it)
		self.cracks[key] = nil
		table.insert(self.crackPool, it)
	end
end

--============================================================================ the hub's vault door

-- A great round vault door behind the three portals: the bank this whole game breaks into.
-- Built once, local, never collidable. `at` = the door's centre (world).
function VaultArt.buildHubDoor(self: any, at: Vector3): any
	if self.hubDoor then return self.hubDoor end
	local it = newItem()
	local M = Enum.Material
	local FACE = CFrame.Angles(0, math.pi / 2, 0) -- a Cylinder's axis is X; face it along Z
	add(it, self:_part("DoorRim", Vector3.new(3, 50, 50), { 214, 172, 82 }, M.Metal, Enum.PartType.Cylinder), CFrame.new(0, 0, -1.5) * FACE)
	add(it, self:_part("Door", Vector3.new(3, 44, 44), { 150, 156, 168 }, M.DiamondPlate, Enum.PartType.Cylinder), FACE)
	add(it, self:_part("DoorHub", Vector3.new(1.6, 12, 12), { 214, 172, 82 }, M.Metal, Enum.PartType.Cylinder), CFrame.new(0, 0, 2) * FACE)
	for i = 0, 2 do
		add(it, self:_part("DoorSpoke", Vector3.new(16, 1.2, 1.2), { 214, 172, 82 }, M.Metal), CFrame.new(0, 0, 2.6) * CFrame.Angles(0, 0, i * math.pi / 3))
	end
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2
		add(it, self:_part("DoorBolt", Vector3.new(2.2, 2.2, 2.2), { 214, 172, 82 }, M.Metal, Enum.PartType.Ball), CFrame.new(math.cos(a) * 18, math.sin(a) * 18, 1.6))
	end
	self:_place(it, CFrame.new(at))
	self.hubDoor = it
	return it
end

return VaultArt
