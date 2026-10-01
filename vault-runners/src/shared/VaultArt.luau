-- VaultArt.luau — Vault Runners' client-side eye candy: ceiling props, sky pieces over the top
-- storey, ambient weather, the collapse's dust and sparks, the ceiling drops, cracks on crumbling
-- pads, debris, and the hub's vault door. Code-only (no assets), CLIENT-ONLY.
--
-- And each stratum's CRITTERS (Config.Env.Bands[*].critters): rats, scarabs, drones, bats and
-- salamanders, three parts each, never Neon, walking a loop inside one maze cell (VaultEnv.critterOffset).
--
-- Every Part made here is LOCAL (the client made it, so it never replicates), anchored, and
-- non-collidable / non-queryable / non-touchable with no shadow: nothing here can be stood on,
-- block a jump, catch a camera ray or trip a Touched. Everything is POOLED — built the first time it
-- is needed, moved and re-coloured afterwards, and unparented (not destroyed) when unused, so a band
-- you are not in costs no draw calls.
--
-- THE BUDGETS ARE CAPS, ENFORCED HERE (Config.Budget; second review, REVIEW-5 §B1). Every part this
-- module parents is counted (`live`), and decoration yields when the count would pass
-- MaxLocalParts: props are hung only while they fit under the budget less the headroom the
-- telegraph, the pad cracks and the debris may need, and `enforceBudget` (the glue calls it once a
-- frame) takes props down, and then debris, if anything still pushes past it. Emitters never write
-- their own Rate or Enabled: they say what they WANT, and enforceBudget grants it by priority —
-- the drop's trickle first, then the collapse's sparks and dust, then the weather — within
-- MaxEmitters and MaxEmitterRate (VaultEnv.grantRates). Lights and beams the same way, within
-- MaxLights and MaxBeams. robloxemu/check_vaultrunners_budget.luau forces every budget below what a
-- scene asks for and measures every frame; check_vaultrunners_env §9 measures the shipped ones.
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
	self.live = 0            -- parts this module (or the glue, via adopt) has parented in `folder` right now
	self.propPlaced = {}     -- the prop items hung for the current key, in the order they were hung
	self.propLive = 0        -- ...and how many parts they are
	self.emitters = {}       -- { pe, prio, want } — enforceBudget grants the wants
	self.emitterOf = {}      -- [pe] = its entry
	self.lightWant = {}      -- [light] = the brightness it asked for
	self.beamWant = {}       -- [beam] = whether it asked to be drawn
	self.beamOrder = {}
	self.critterPools = {}   -- [kind] = { items }
	self.critterPlaced = {}  -- the critter items on show, in the order they were placed
	self.critterLive = 0     -- ...and how many parts they are
	return self
end

-- Parent `part` into the folder (on) or out of it, keeping `live` exact. Every parenting of a part in
-- this module goes through here, so the parts budget is never counted from a stale number.
function VaultArt._parent(self: any, part: BasePart, on: boolean)
	if on then
		if part.Parent ~= self.folder then
			part.Parent = self.folder
			self.live += 1
		end
	elseif part.Parent ~= nil then
		if part.Parent == self.folder then self.live -= 1 end
		part.Parent = nil
	end
end

-- A part the glue made itself (the hub's sign anchors), parented through here so it is counted.
function VaultArt.adopt(self: any, part: BasePart)
	self:_parent(part, true)
end

-- Priorities for the emitter budget (lower is more important).
VaultArt.EmitterPriority = { trickle = 1, sparks = 2, dust = 3, weather = 4 }

function VaultArt._emitter(self: any, pe: ParticleEmitter, prio: number)
	local e = { pe = pe, prio = prio, want = 0 }
	table.insert(self.emitters, e)
	self.emitterOf[pe] = e
	pe.Enabled = false
	pe.Rate = 0
end

function VaultArt._want(self: any, pe: ParticleEmitter, rate: number)
	local e = self.emitterOf[pe]
	if e then e.want = math.max(0, rate) end
end

-- Parts the hung props must leave room for: a drop in the air (its model and the shared ring, crack
-- and stream), every pad of a shaft cracking at once, and a full set of debris — counted from what
-- this module builds (31 parts at the shipped numbers). robloxemu/check_vaultrunners_budget.luau §1
-- asks for props in every cell and measures the total staying under MaxLocalParts on every frame.
VaultArt.HazardParts = 2 + 3
VaultArt.CrackParts = 3
VaultArt.MaxDebris = 8
function VaultArt.headroom(cfg: any): number
	local pads = math.floor(cfg.Vault.StoreyHeight / cfg.Vault.StepRise)
	return VaultArt.HazardParts + pads * VaultArt.CrackParts + VaultArt.MaxDebris
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
		self:_parent(e.part, true)
	end
	item.on = true
end

function VaultArt._hide(self: any, item: any)
	if not item.on then return end
	for _, e in item.parts do
		self:_parent(e.part, false)
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
VaultArt.PropParts = 3 -- every prop kind below is three parts

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
--
-- PROPS FIT THE PARTS BUDGET. Sites are hung in the order given (the glue lists the runner's own
-- storey first) while the props fit under Budget.MaxLocalParts, less everything else parented right
-- now and less the headroom the telegraph, the cracks and the debris may still need. The rest are
-- not hung. A retune that asked for props in every cell asked the phone for 235 parts against 180.
function VaultArt.updateProps(self: any, key: string?, sites: { any }?)
	if key == self.propKey then return end
	self.propKey = key
	local allowance = self.cfg.Budget.MaxLocalParts - VaultArt.headroom(self.cfg) - (self.live - self.propLive - self.critterLive)
	local used = {}
	for kind, pool in self.propPools do used[kind] = 0 end
	local placed, parts = {}, 0
	for _, s in sites or {} do
		local pool = self.propPools[s.kind]
		if pool == nil then
			pool = {}
			self.propPools[s.kind] = pool
			used[s.kind] = 0
		end
		local item = pool[used[s.kind] + 1]
		local need = if item then #item.parts else VaultArt.PropParts
		if parts + need > allowance then break end
		used[s.kind] += 1
		if item == nil then
			item = self:_buildProp(s.kind)
			pool[used[s.kind]] = item
		end
		self:_place(item, CFrame.new(s.pos) * CFrame.Angles(0, s.yaw or 0, 0))
		colourRole(item, "accent", s.accent)
		colourRole(item, "glow", s.glow)
		table.insert(placed, item)
		parts += #item.parts
	end
	for kind, pool in self.propPools do
		for i = (used[kind] or 0) + 1, #pool do
			self:_hide(pool[i])
		end
	end
	self.propPlaced = placed
	self.propLive = parts
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
			beam.Enabled = false
			beam.Parent = a
			table.insert(it.beams, beam)
			table.insert(self.beamOrder, beam)
			self.beamWant[beam] = false
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
			for _, beam in it.beams or {} do self.beamWant[beam] = w > 0.3 end
		else
			self:_hide(it)
			for _, beam in it.beams or {} do self.beamWant[beam] = false end
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
	ash = function(pe: ParticleEmitter)
		-- the Volcano Temple's Ash Hall (Config.Env.Halls): grey flakes drifting down, slowly
		pe.Color = ColorSequence.new(Color3.fromRGB(150, 146, 142), Color3.fromRGB(96, 92, 90))
		pe.Size = seq({ { 0, 0.16 }, { 0.6, 0.24 }, { 1, 0.2 } })
		pe.Transparency = seq({ { 0, 0.25 }, { 0.8, 0.4 }, { 1, 1 } })
		pe.Lifetime = NumberRange.new(4, 6)
		pe.Speed = NumberRange.new(0.6, 1.4)
		pe.Acceleration = Vector3.new(0.3, -0.9, 0.2)
		pe.RotSpeed = NumberRange.new(-30, 30)
		pe.LightEmission = 0
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
		self:_parent(host, true)
	end
	for kind, r in rates do
		if r > 0 and self.weather[kind] == nil and WEATHER[kind] then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "Weather_" .. kind
			pe.EmissionDirection = Enum.NormalId.Bottom
			WEATHER[kind](pe)
			self:_emitter(pe, VaultArt.EmitterPriority.weather)
			pe.Parent = host
			self.weather[kind] = pe
		end
	end
	for kind, pe in self.weather do
		self:_want(pe, rates[kind] or 0)
	end
	if not any then self:_parent(host, false) end
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
		self:_emitter(pe, VaultArt.EmitterPriority.dust)
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
		self:_emitter(sp, VaultArt.EmitterPriority.sparks)
		sp.Parent = c.sparkHost
		c.sparks = sp
		self.collapse = c
	end
	if ceilingCF then
		c.dustHost.CFrame = ceilingCF
		self:_parent(c.dustHost, true)
	else
		self:_parent(c.dustHost, false)
	end
	if planeCF and planeSize then
		c.sparkHost.CFrame = planeCF
		if c.sparkHost.Size ~= planeSize then c.sparkHost.Size = planeSize end
		self:_parent(c.sparkHost, true)
	else
		self:_parent(c.sparkHost, false)
	end
	self:_want(c.dust, if ceilingCF ~= nil then dust else 0)
	self:_want(c.sparks, if planeCF ~= nil then sparks else 0)
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
	self:_emitter(pe, VaultArt.EmitterPriority.trickle)
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
	self.lightWant[light] = 0
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
		self:_parent(p, true)
	end
	self:_want(s.trickle, if landed then 0 else (if locked then 40 else 18))
	self.lightWant[s.light] = if landed then 0 elseif (math.floor(now * (if locked then 8 else 3)) % 2 == 0) then 2 else 0
end

function VaultArt.hideHazard(self: any, kind: string?)
	for k, it in self.hazards do
		if kind == nil or k == kind then self:_hide(it) end
	end
	local s = self.shared
	if s then
		for _, p in { s.ring, s.crack, s.stream } do self:_parent(p, false) end
		self:_want(s.trickle, 0)
		self.lightWant[s.light] = 0
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
	while fresh < n and #self.debris < VaultArt.MaxDebris do
		fresh += 1
		local d = { part = self:_part("Debris", Vector3.new(0.7, 0.5, 0.6), { 0, 0, 0 }, Enum.Material.Slate), vel = Vector3.zero, life = 0 }
		table.insert(self.debris, d)
		self:_launch(d, at, color, spread)
	end
end

function VaultArt._launch(self: any, d: any, at: Vector3, color: Color3, spread: number)
	-- debris is decoration and yields first: no chunk flies while the parts budget is full
	if d.part.Parent ~= self.folder and self.live + 1 > self.cfg.Budget.MaxLocalParts then return end
	local a = self.rand() * math.pi * 2
	local sp = spread * (0.5 + 0.5 * self.rand())
	d.vel = Vector3.new(math.cos(a) * sp, 6 + 6 * self.rand(), math.sin(a) * sp)
	d.life = 1
	d.part.Color = color
	d.part.Transparency = 0
	d.part.CFrame = CFrame.new(at)
	self:_parent(d.part, true)
end

function VaultArt.step(self: any, dt: number)
	for _, d in self.debris do
		if d.life > 0 then
			d.life -= dt
			if d.life <= 0 then
				self:_parent(d.part, false)
			else
				d.vel += Vector3.new(0, -60 * dt, 0)
				d.part.CFrame = d.part.CFrame + d.vel * dt
				d.part.Transparency = 1 - d.life
			end
		end
	end
end

--============================================================================ critters

-- Built facing -Z (a CFrame.lookAt's forward), every part within Config.Env.CritterHalfLength (1 stud)
-- of the centre. Parts with the role "body" wear the band's critter colour (EnvConfig.spec keeps it
-- MinGemPadDistance from every gem and pad on its floor); the rest are small and dark. Never Neon:
-- Neon is what glows here, and what glows is treasure, the exit or a lamp.
VaultArt.CritterParts = 3
local CRITTERS = {}
CRITTERS.rat = function(self: any, it: any)
	local M = Enum.Material
	add(it, self:_part("Critter_rat", Vector3.new(0.7, 0.5, 1.0), { 140, 124, 110 }, M.Fabric), UP, "body")
	add(it, self:_part("Critter_rat", Vector3.new(0.45, 0.4, 0.5), { 140, 124, 110 }, M.Fabric), CFrame.new(0, 0.05, -0.7), "body")
	add(it, self:_part("Critter_rat", Vector3.new(0.1, 0.1, 0.6), { 70, 50, 50 }, M.SmoothPlastic), CFrame.new(0, -0.12, 0.65))
end
CRITTERS.scarab = function(self: any, it: any)
	local M = Enum.Material
	add(it, self:_part("Critter_scarab", Vector3.new(0.8, 0.4, 1.0), { 24, 60, 56 }, M.Metal), UP, "body")
	add(it, self:_part("Critter_scarab", Vector3.new(0.5, 0.3, 0.3), { 20, 24, 22 }, M.SmoothPlastic), CFrame.new(0, -0.05, -0.62))
	add(it, self:_part("Critter_scarab", Vector3.new(0.12, 0.12, 0.3), { 20, 24, 22 }, M.SmoothPlastic), CFrame.new(0, 0.1, -0.8))
end
CRITTERS.drone = function(self: any, it: any)
	local M = Enum.Material
	add(it, self:_part("Critter_drone", Vector3.new(0.9, 0.5, 0.9), { 150, 150, 160 }, M.Metal), UP, "body")
	add(it, self:_part("Critter_drone", Vector3.new(1.8, 0.08, 0.25), { 40, 42, 48 }, M.SmoothPlastic), CFrame.new(0, 0.35, 0))
	add(it, self:_part("Critter_drone", Vector3.new(0.25, 0.25, 0.1), { 90, 20, 20 }, M.SmoothPlastic), CFrame.new(0, 0, -0.5))
end
CRITTERS.bat = function(self: any, it: any)
	local M = Enum.Material
	add(it, self:_part("Critter_bat", Vector3.new(0.5, 0.5, 0.6), { 70, 60, 72 }, M.Fabric), UP, "body")
	add(it, self:_part("Critter_bat", Vector3.new(0.8, 0.06, 0.5), { 70, 60, 72 }, M.Fabric), CFrame.new(-0.5, 0.05, 0) * CFrame.Angles(0, 0, 0.3), "body")
	add(it, self:_part("Critter_bat", Vector3.new(0.8, 0.06, 0.5), { 70, 60, 72 }, M.Fabric), CFrame.new(0.5, 0.05, 0) * CFrame.Angles(0, 0, -0.3), "body")
end
CRITTERS.salamander = function(self: any, it: any)
	local M = Enum.Material
	add(it, self:_part("Critter_salamander", Vector3.new(0.5, 0.3, 1.0), { 150, 44, 30 }, M.SmoothPlastic), UP, "body")
	add(it, self:_part("Critter_salamander", Vector3.new(0.45, 0.28, 0.4), { 150, 44, 30 }, M.SmoothPlastic), CFrame.new(0, 0.02, -0.65), "body")
	add(it, self:_part("Critter_salamander", Vector3.new(0.18, 0.15, 0.5), { 90, 30, 20 }, M.SmoothPlastic), CFrame.new(0, -0.05, 0.72))
end

function VaultArt.hasCritter(kind: string): boolean
	return CRITTERS[kind] ~= nil
end

function VaultArt._buildCritter(self: any, kind: string): any
	local it = newItem()
	CRITTERS[kind](self, it)
	return it
end

-- Parts of the drop, the cracking pads and the debris that are parented right now: what the headroom
-- is for. The critters reserve the whole headroom whatever of it is in use, like the props.
function VaultArt._transient(self: any): number
	local n = 0
	for _, it in self.hazards do
		if it.on then n += #it.parts end
	end
	local s = self.shared
	if s then
		for _, p in { s.ring, s.crack, s.stream } do
			if p.Parent == self.folder then n += 1 end
		end
	end
	for _, it in self.cracks do
		if it.on then n += #it.parts end
	end
	for _, d in self.debris do
		if d.part.Parent == self.folder then n += 1 end
	end
	return n
end

-- Show these critters, once a frame. `list` = { { kind, pos: Vector3, face: Vector3 (the way it walks),
-- color: Color3 } }, nearest first; nil or {} shows none. At most Budget.MaxCritters, and only what fits
-- under MaxLocalParts after everything else that is not a drop, a crack or debris, less the headroom
-- those may need: critters are the first decoration to yield (enforceBudget takes them down first).
function VaultArt.updateCritters(self: any, list: { any }?)
	local B = self.cfg.Budget
	local fixed = self.live - self.critterLive - self:_transient()
	local allowance = B.MaxLocalParts - VaultArt.headroom(self.cfg) - fixed
	local used = {}
	local placed, parts = {}, 0
	for i, c in list or {} do
		if i > B.MaxCritters then break end
		if CRITTERS[c.kind] == nil then continue end
		local pool = self.critterPools[c.kind]
		if pool == nil then
			pool = {}
			self.critterPools[c.kind] = pool
		end
		local k = (used[c.kind] or 0) + 1
		local item = pool[k]
		local need = if item then #item.parts else VaultArt.CritterParts
		if parts + need > allowance then break end
		if item == nil then
			item = self:_buildCritter(c.kind)
			pool[k] = item
		end
		used[c.kind] = k
		local face = c.face
		local cf = if face and (face.X * face.X + face.Z * face.Z) > 1e-6
			then CFrame.lookAt(c.pos, c.pos + Vector3.new(face.X, 0, face.Z))
			else CFrame.new(c.pos)
		self:_place(item, cf)
		colourRole(item, "body", c.color)
		placed[#placed + 1] = item
		parts += #item.parts
	end
	for kind, pool in self.critterPools do
		for i = (used[kind] or 0) + 1, #pool do
			self:_hide(pool[i])
		end
	end
	self.critterPlaced = placed
	self.critterLive = parts
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

--============================================================================ the budgets, enforced

-- ONCE A FRAME, after everything above has said what it wants (the glue calls it last). Parts first:
-- if anything still pushes the count past MaxLocalParts, decoration yields — critters first, then props
-- from the last one hung back to the first (the runner's own storey is hung first, so it goes last), then debris in
-- flight. Then emitters (VaultEnv.grantRates: by priority, within MaxEmitters and MaxEmitterRate),
-- lights (within MaxLights) and beams (within MaxBeams), written only where a value changes.
function VaultArt.enforceBudget(self: any)
	local B = self.cfg.Budget
	if self.live > B.MaxLocalParts then
		for i = #self.critterPlaced, 1, -1 do
			if self.live <= B.MaxLocalParts then break end
			local it = self.critterPlaced[i]
			if it.on then
				self:_hide(it)
				self.critterLive -= #it.parts
			end
		end
		for i = #self.propPlaced, 1, -1 do
			if self.live <= B.MaxLocalParts then break end
			local it = self.propPlaced[i]
			if it.on then
				self:_hide(it)
				self.propLive -= #it.parts
			end
		end
		for _, d in self.debris do
			if self.live <= B.MaxLocalParts then break end
			if d.life > 0 then
				d.life = 0
				self:_parent(d.part, false)
			end
		end
	end
	local wants = {}
	for i, e in self.emitters do wants[i] = { rate = e.want, prio = e.prio } end
	local grants = self.VaultEnv.grantRates(wants, B.MaxEmitters, B.MaxEmitterRate)
	for i, e in self.emitters do
		local r = grants[i] or 0
		local on = r > 0
		if e.pe.Enabled ~= on then e.pe.Enabled = on end
		if on and math.abs(e.pe.Rate - r) > 0.05 then e.pe.Rate = r end
	end
	local lights = 0
	for light, b in self.lightWant do
		local give = if b > 0 and lights < B.MaxLights then b else 0
		if give > 0 then lights += 1 end
		if light.Brightness ~= give then light.Brightness = give end
	end
	local beams = 0
	for _, beam in self.beamOrder do
		local on = self.beamWant[beam] == true and beams < B.MaxBeams
		if on then beams += 1 end
		if beam.Enabled ~= on then beam.Enabled = on end
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
