-- ESCAPE ROOM LAB — the Lab you see: bands, decor, creatures, weather, the rare hazards and the Break.
-- Client only (StarterPlayerScripts). The template glue is plus1-jump/src/client/Sky.client.luau;
-- what differs for an indoor puzzle game, and why, is in EYECANDY.md §2-4.
--
-- Every frame, for THIS player only:
--   * the progress value p = (wing - 1) + (room - 1 + solved / stations) / 3 from the room's RoomState
--     (0 in the Atrium, 5 on the Roof) — the game's own logic, never time — drives every blend: light,
--     grade, decor, creatures, weather. The band's NAME (title card, which hazard flies) follows the
--     room's whole wing number. A lift ride makes p jump; every value glides at a 0.6 s half-life;
--   * the hazards (Hazards.luau, verbatim) with ctx.pitch = rad(85) so every lane comes straight down
--     from the ceiling (CLAUDE.md trap 4); a red ring at the feet IS the hit zone;
--   * the Break (Rest.luau, verbatim; IdleSeconds = 0 on purpose, CLAUDE.md trap 5).
--
-- Why client-side is safe: it is cosmetic or harms only the local character, whose physics this client
-- owns. The server never hears of a hazard or a Break, and nothing here fires a remote. Everything it
-- builds lives in workspace.LabLocalEnv and never replicates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Decor = require(ReplicatedStorage:WaitForChild("Decor"))
local Lab = require(ReplicatedStorage:WaitForChild("Lab"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local ClientBus = require(ReplicatedStorage:WaitForChild("ClientBus"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Env, Hz, RestCfg, Budget, W = Config.Env, Config.Hazards, Config.Rest, Config.Budget, Config.World
local bands = Env.Bands

-- A broken config must cost the polish, never the game: warn loudly and switch that part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[LabEnv] Config.Env.Bands is invalid (" .. tostring(err) .. "); the Lab keeps the server's lighting.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then warn("[LabEnv] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.") end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then warn("[LabEnv] Config.Rest is invalid (" .. tostring(restErr) .. "); the Break is OFF.") end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end


local function c3(rgb: { number }): Color3
	return Color3.fromRGB(math.clamp(math.round(rgb[1]), 0, 255), math.clamp(math.round(rgb[2]), 0, 255), math.clamp(math.round(rgb[3]), 0, 255))
end

--============================================================================ the local world and the lighting rig
local folder = Instance.new("Folder")
folder.Name = "LabLocalEnv"
folder.Parent = workspace

-- Reuse the server's Fx.applyLighting objects by name, so the client takes over from exactly the
-- values the server set (band 1 = Fx.Presets.Lab) instead of stacking a second Atmosphere on top.
local function rig(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then return existing end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end
local targets = {
	lighting = Lighting,
	atmosphere = rig("Atmosphere", "FxAtmosphere"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sky = rig("Sky", "LabSky"),
}
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "sky" }

local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "LabRestFocus"
restFocus.FarIntensity = 0.3
restFocus.FocusDistance = 12
restFocus.InFocusRadius = 20
restFocus.NearIntensity = 0
restFocus.Enabled = false
restFocus.Parent = Lighting

local written: { [Instance]: { [string]: any } } = {}
local function writeGroup(inst: Instance, props: { [string]: any })
	local last = written[inst]
	if last == nil then
		last = {}
		written[inst] = last
	end
	for k, v in props do
		local prev = last[k]
		local changed
		if type(v) == "table" then
			changed = prev == nil or math.abs(prev[1] - v[1]) > 0.5 or math.abs(prev[2] - v[2]) > 0.5 or math.abs(prev[3] - v[3]) > 0.5
		else
			changed = prev == nil or (type(v) == "number" and math.abs(prev - v) > 1e-3) or (type(v) ~= "number" and prev ~= v)
		end
		if changed then
			local value = v
			if type(v) == "table" then
				value = c3(v)
			elseif k == "StarCount" then
				value = math.round(v)
			end
			local ok = pcall(function() (inst :: any)[k] = value end)
			if ok then last[k] = if type(v) == "table" then { v[1], v[2], v[3] } else v end
		end
	end
end

-- The local part budget, CAPPED IN CODE (docs/complete-game-standard.md §2): every local part goes through
-- here, and past Config.Budget.LocalParts nothing new is built (decor, creatures and fireworks simply skip).
-- The hazard's model, thread and RING draw on a reserve of Budget.HazardParts that nothing cosmetic may
-- touch: a full budget must never cost the telegraph (check_escaperoomlab_budget found exactly that).
-- The config keeps the worst case far below the cap (tests/Decor.spec.luau); this is the belt to those braces.
local localCount = 0
local function budgetLeft(): number
	return Budget.LocalParts - Budget.HazardParts - localCount
end
local function localPart(name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number?,
	reserved: boolean?): Part?
	local cap = if reserved then Budget.LocalParts else Budget.LocalParts - Budget.HazardParts
	if localCount >= cap then return nil end
	localCount += 1
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.Parent = folder
	p.Destroying:Connect(function() localCount -= 1 end)
	return p
end

--============================================================================ what the server told this player
local where = "atrium"
local rs: any = nil
local prof: any = nil
local roomId: number? = nil
local arrivedAt = -math.huge
local now = 0

-- Hud.client forwards every RoomState, Profile and Notice onto ClientBus; `last` covers loading second.
local function onRoomState(payload: any)
	if type(payload) ~= "table" then return end
	rs = payload
	where = payload.where or "atrium"
	if where == "room" and payload.roomId ~= roomId then
		roomId = payload.roomId
		arrivedAt = now
	elseif where ~= "room" then
		roomId = nil
	end
end
ClientBus.on("roomState", onRoomState)
ClientBus.on("profile", function(payload: any)
	if type(payload) == "table" then prof = payload end
end)
if ClientBus.last("roomState") then onRoomState(ClientBus.last("roomState")) end
if ClientBus.last("profile") then prof = ClientBus.last("profile") end

local function progress(): number
	if where == "room" and rs and rs.wing then
		return Lab.progress(rs.wing, rs.room, rs.solved or 0, rs.total or 1)
	elseif where == "roof" then
		return 5
	end
	return 0
end

local function namedBand(): number
	if where == "room" and rs and rs.wing then return rs.wing end
	if where == "roof" then return #bands end
	return 1
end

local function anchor(): Vector3
	if where == "room" and rs and rs.origin then
		return Vector3.new(rs.origin[1], rs.origin[2], rs.origin[3])
	elseif where == "roof" then
		return Vector3.new(0, W.RoofY, 0)
	end
	return Vector3.zero
end

--============================================================================ decor: per band, faded by weight
local decor: { [string]: Part } = {}
local decorAnchor: Vector3? = nil
local function updateDecor(weights: { [number]: number }, at: Vector3)
	local moved = decorAnchor == nil or (decorAnchor - at).Magnitude > 0.01
	decorAnchor = at
	local want: { [string]: boolean } = {}
	for i, b in bands do
		local w = weights[i] or 0
		local allowed = (b.id == "roof" and where == "roof") or (b.id ~= "roof" and where == "room")
		if w > 0.01 and allowed then
			for _, piece in Decor.pieces(b.id) do
				local key = b.id .. ":" .. piece.id
				want[key] = true
				local p = decor[key]
				if p == nil then
					p = localPart("Decor_" .. b.id .. "_" .. piece.id, Vector3.new(piece.size[1], piece.size[2], piece.size[3]),
						c3(piece.color), (Enum.Material :: any)[piece.material])
					if p == nil then continue end
					decor[key] = p
					moved = true
				end
				if moved then
					p.CFrame = CFrame.new(at + Vector3.new(piece.pos[1], piece.pos[2], piece.pos[3]))
				end
				local t = 1 - (1 - piece.transparency) * math.min(1, w)
				if math.abs(p.Transparency - t) > 0.01 then p.Transparency = t end
			end
		end
	end
	for key, p in decor do
		if not want[key] then
			p:Destroy()
			decor[key] = nil
		end
	end
	if moved then
		for key, p in decor do
			local bandId, pid = string.match(key, "^([^:]+):(.+)$")
			for _, piece in Decor.pieces(bandId :: string) do
				if piece.id == pid then p.CFrame = CFrame.new(at + Vector3.new(piece.pos[1], piece.pos[2], piece.pos[3])) end
			end
		end
	end
end

--============================================================================ creatures: bounded indoor loops
local critters: { [string]: { { Part } } } = {}
local function updateCritters(weights: { [number]: number }, at: Vector3)
	local counts: { [string]: number } = {}
	for i, b in bands do
		local w = weights[i] or 0
		if w > 0.001 then
			for _, c in b.critters or {} do
				counts[c.kind] = (counts[c.kind] or 0) + c.count * w
			end
		end
	end
	for kind, list in critters do
		local n = math.floor((counts[kind] or 0) + 0.5)
		while #list > n do
			for _, p in table.remove(list) :: { Part } do p:Destroy() end
		end
	end
	for kind, raw in counts do
		local n = math.floor(raw + 0.5)
		local spec = Decor.CritterParts[kind]
		if spec == nil then continue end
		local list = critters[kind]
		if list == nil then
			list = {}
			critters[kind] = list
		end
		while #list < n and budgetLeft() >= #spec do
			local parts = {}
			for j, ps in spec do
				table.insert(parts, localPart(string.format("Critter_%s_%d_%d", kind, #list + 1, j), Vector3.new(ps.size[1], ps.size[2], ps.size[3]),
					c3(ps.color), (Enum.Material :: any)[ps.material], ps.transparency) :: Part)
			end
			table.insert(list, parts)
		end
		for i, parts in list do
			local p = Decor.critterPos(kind, i, now)
			local q = Decor.critterPos(kind, i, now + 0.1)
			local pos = at + Vector3.new(p.x, p.y, p.z)
			local ahead = at + Vector3.new(q.x, q.y, q.z)
			local cf = if (ahead - pos).Magnitude > 1e-3 then CFrame.lookAt(pos, ahead) else CFrame.new(pos)
			for j, part in parts do
				local o = spec[j].offset
				part.CFrame = cf * CFrame.new(o[1], o[2], o[3])
			end
		end
	end
end

--============================================================================ weather: two emitters, capped in code
local WEATHER = {
	dust = { color = { 255, 236, 200 }, size = 0.15, speed = { 0.2, 0.6 }, life = { 6, 10 }, accel = { 0, -0.3, 0 }, light = 0.4, alpha = 0.5 },
	paper = { color = { 240, 230, 210 }, size = 0.35, speed = { 0.5, 1.2 }, life = { 5, 8 }, accel = { 0, -1.2, 0 }, light = 0, alpha = 0.1 },
	mist = { color = { 220, 240, 225 }, size = 3, speed = { 0.2, 0.5 }, life = { 6, 9 }, accel = { 0, -0.1, 0 }, light = 0.1, alpha = 0.85 },
	drip = { color = { 170, 210, 255 }, size = 0.12, speed = { 6, 8 }, life = { 1.5, 2 }, accel = { 0, -30, 0 }, light = 0.2, alpha = 0.2 },
	snow = { color = { 250, 252, 255 }, size = 0.2, speed = { 1, 3 }, life = { 4, 6 }, accel = { 0, -4, 0 }, light = 0.3, alpha = 0.1 },
	steam = { color = { 220, 230, 235 }, size = 1.5, speed = { 1, 2 }, life = { 3, 5 }, accel = { 0, 1.5, 0 }, light = 0.1, alpha = 0.7 },
	sparks = { color = { 255, 200, 90 }, size = 0.12, speed = { 4, 8 }, life = { 0.5, 1 }, accel = { 0, -40, 0 }, light = 1, alpha = 0 },
	leaves = { color = { 200, 150, 60 }, size = 0.35, speed = { 1, 3 }, life = { 4, 7 }, accel = { 0, -1.5, 0 }, light = 0, alpha = 0.1 },
}
local weatherHosts = {}
for i = 1, Budget.WeatherEmitters do
	local host = localPart("WeatherHost_" .. i, Vector3.new(28, 0.5, 28), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1) :: Part
	local e = Instance.new("ParticleEmitter")
	e.Name = "Weather"
	e.Enabled = false
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Parent = host
	weatherHosts[i] = { host = host, emitter = e, kind = nil }
end
local function styleEmitter(e: ParticleEmitter, kind: string)
	local w = WEATHER[kind]
	if w == nil then return end
	e.Color = ColorSequence.new(c3(w.color))
	e.Size = NumberSequence.new(w.size)
	e.Transparency = NumberSequence.new(w.alpha)
	e.Speed = NumberRange.new(w.speed[1], w.speed[2])
	e.Lifetime = NumberRange.new(w.life[1], w.life[2])
	e.Acceleration = Vector3.new(w.accel[1], w.accel[2], w.accel[3])
	e.LightEmission = w.light
	e.RotSpeed = NumberRange.new(-60, 60)
end
local function updateWeather(weights: { [number]: number }, at: Vector3)
	local rates: { [string]: number } = {}
	for i, b in bands do
		local w = weights[i] or 0
		if w > 0.001 then
			for _, wx in b.weather or {} do
				rates[wx.kind] = (rates[wx.kind] or 0) + wx.rate * w
			end
		end
	end
	local on = EnvBands.capRates(rates, Budget.WeatherEmitters, Budget.MaxEmitterRate, Budget.MinWeatherRate)
	local kinds = {}
	for kind in on do table.insert(kinds, kind) end
	table.sort(kinds)
	-- keep a kind on the host it already has, so a style never flickers between frames
	local assigned: { [number]: string } = {}
	for i, h in weatherHosts do
		if h.kind and on[h.kind] then assigned[i] = h.kind end
	end
	for _, kind in kinds do
		local placed = false
		for i in weatherHosts do
			if assigned[i] == kind then placed = true end
		end
		if not placed then
			for i in weatherHosts do
				if assigned[i] == nil then
					assigned[i] = kind
					break
				end
			end
		end
	end
	local ceiling = if where == "room" then W.RoomHeight - 1 elseif where == "roof" then 18 else W.AtriumHeight - 2
	for i, h in weatherHosts do
		local kind = assigned[i]
		h.host.CFrame = CFrame.new(at + Vector3.new(0, ceiling, 0))
		if kind then
			if h.kind ~= kind then
				styleEmitter(h.emitter, kind)
				h.kind = kind
			end
			h.emitter.Rate = on[kind]
			h.emitter.Enabled = true
		else
			h.emitter.Enabled = false
			h.emitter.Rate = 0
			h.kind = nil
		end
	end
end

--============================================================================ hazards: the model, its thread, the ring
local HAZARD_MODEL = {
	spider = {
		{ size = { 1.2, 1.2, 1.2 }, offset = { 0, 0, 0 }, color = { 20, 20, 24 }, material = "SmoothPlastic", ball = true },
		{ size = { 2.4, 0.15, 0.15 }, offset = { 0, 0, 0.2 }, color = { 30, 30, 34 }, material = "SmoothPlastic" },
		{ size = { 0.15, 0.15, 2.4 }, offset = { 0, 0, 0 }, color = { 30, 30, 34 }, material = "SmoothPlastic" },
	},
	seedpod = {
		{ size = { 1.6, 2, 1.6 }, offset = { 0, 0, 0 }, color = { 120, 110, 50 }, material = "Grass", ball = true },
		{ size = { 0.3, 0.8, 0.3 }, offset = { 0, 1.2, 0 }, color = { 70, 130, 60 }, material = "Grass" },
	},
	icedrone = {
		{ size = { 1.4, 0.6, 1.4 }, offset = { 0, 0, 0 }, color = { 225, 240, 255 }, material = "Metal" },
		{ size = { 0.4, 0.4, 0.4 }, offset = { 0, -0.4, 0 }, color = { 120, 230, 255 }, material = "Neon" },
	},
	claw = {
		{ size = { 1.4, 0.8, 1.4 }, offset = { 0, 0.4, 0 }, color = { 250, 200, 40 }, material = "Metal" },
		{ size = { 0.3, 1.2, 0.3 }, offset = { -0.5, -0.4, 0 }, color = { 90, 96, 110 }, material = "Metal" },
		{ size = { 0.3, 1.2, 0.3 }, offset = { 0.5, -0.4, 0 }, color = { 90, 96, 110 }, material = "Metal" },
	},
}
local HAZARD_TRAIL = { spider = "dust", seedpod = "leaves", icedrone = "snow", claw = "sparks" }

local hazardParts: { Part } = {}
local hazardKind: string? = nil
local thread: Part? = nil
local ring: Part? = nil
local hazardEmitter: ParticleEmitter? = nil

local function hideHazard()
	for _, p in hazardParts do p:Destroy() end
	table.clear(hazardParts)
	hazardKind = nil
	hazardEmitter = nil
	if thread then thread:Destroy(); thread = nil end
	if ring then ring:Destroy(); ring = nil end
end

local function showHazard(plan: any, pos: any, zone: any, ceilingY: number)
	if hazardKind ~= plan.kind then
		hideHazard()
		hazardKind = plan.kind
		for j, ps in HAZARD_MODEL[plan.kind] or HAZARD_MODEL.spider do
			local p = localPart(string.format("Hazard_%s_%d", plan.kind, j), Vector3.new(ps.size[1], ps.size[2], ps.size[3]), c3(ps.color),
				(Enum.Material :: any)[ps.material], 0, true)
			if p then
				if ps.ball then p.Shape = Enum.PartType.Ball end
				table.insert(hazardParts, p)
			end
		end
		local trail = HAZARD_TRAIL[plan.kind]
		if trail and hazardParts[1] then
			local e = Instance.new("ParticleEmitter")
			e.Name = "HazardTrail"
			styleEmitter(e, trail)
			e.Rate = 12
			e.Parent = hazardParts[1]
			hazardEmitter = e
		end
		if plan.kind ~= "icedrone" then
			thread = localPart("HazardThread", Vector3.new(0.08, 1, 0.08), Color3.fromRGB(220, 220, 225), Enum.Material.SmoothPlastic, 0.3, true)
		end
	end
	local spec = HAZARD_MODEL[plan.kind] or HAZARD_MODEL.spider
	local here = Vector3.new(pos.x, pos.y, pos.z)
	for j, p in hazardParts do
		local o = (spec[j] or spec[1]).offset
		p.CFrame = CFrame.new(here + Vector3.new(o[1], o[2], o[3]))
	end
	if thread then
		local top = ceilingY
		local len = math.max(0.1, top - (here.Y + 1))
		thread.Size = Vector3.new(0.08, len, 0.08)
		thread.CFrame = CFrame.new(here.X, here.Y + 1 + len / 2, here.Z)
	end
	-- THE RING IS THE HIT ZONE: centred on Hazards.zone, radius = hitRadius + PlayerRadius, at the feet.
	if zone then
		if ring == nil then
			ring = localPart("HazardRing", Vector3.new(0.1, 1, 1), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, 0.35, true)
			if ring then (ring :: Part).Shape = Enum.PartType.Cylinder end
		end
		if ring then
			local d = zone.radius * 2
			ring.Size = Vector3.new(0.1, d, d)
			ring.CFrame = CFrame.new(zone.x, zone.y - Hz.RootHeight + 0.06, zone.z) * CFrame.Angles(0, 0, math.rad(90))
		end
	elseif ring then
		ring:Destroy()
		ring = nil
	end
end

--============================================================================ fireworks on the Roof, a shooting star
local function burst(at: Vector3, color: Color3)
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local p = localPart("Firework", Vector3.new(0.6, 0.6, 0.6), color, Enum.Material.Neon)
		if p == nil then return end
		p.Shape = Enum.PartType.Ball
		p.CFrame = CFrame.new(at)
		local dir = Vector3.new(math.cos(a), 0.4 * math.sin(a * 3), math.sin(a)) * 12
		local tw = TweenService:Create(p, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = at + dir, Transparency = 1 })
		tw.Completed:Connect(function() p:Destroy() end)
		tw:Play()
	end
end
ClientBus.on("notice", function(payload: any)
	if type(payload) ~= "table" or payload.kind ~= "roof" then return end
	local colors = { Color3.fromRGB(255, 214, 90), Color3.fromRGB(90, 220, 255), Color3.fromRGB(255, 110, 180) }
	for i, c in colors do
		task.delay((i - 1) * 0.7, function()
			burst(Vector3.new(-20 + i * 10, W.RoofY + 34, -40), c)
		end)
	end
end)
local nextShootingStar = 30
local shootingStar: Part? = nil

--============================================================================ the Solo Lift's doors: the rider's own
-- Review-1 A2: one door on the SERVER, shut for every ride, could be held shut by riders on a loop (two
-- clients: 99% of the time), keeping everyone else out of the cab. The doors are now THIS client's local
-- part, shut for its own ride: a client simulates its own character, so only the rider bumps into it and
-- nobody else is ever kept out. The server checks at departure that the rider is still inside, because a
-- client can move its character through anything it likes.
local soloDoor: Part? = nil
local function openSoloDoor()
	if soloDoor then
		soloDoor:Destroy()
		soloDoor = nil
	end
end
ClientBus.on("notice", function(payload: any)
	if type(payload) ~= "table" or payload.kind ~= "ride" or payload.lift ~= "solo" then return end
	openSoloDoor()
	local d = localPart("SoloDoorLocal", Vector3.new(2 * W.CabHalf, 10, 0.4), Color3.fromRGB(150, 160, 178), Enum.Material.Metal, 0, true)
	if d == nil then return end
	d.CanCollide = true
	d.CFrame = CFrame.new(W.SoloCab[1], 5, W.SoloCab[2] + W.CabHalf + 0.25)
	soloDoor = d
	task.delay(Config.Lift.RideSeconds + 2, function()
		if soloDoor == d then openSoloDoor() end
	end)
end)
-- the next RoomState is the arrival (or the Atrium, when the ride was called off): the doors open
ClientBus.on("roomState", function() openSoloDoor() end)

--============================================================================ the guide arrow (first rooms only)
local arrow = localPart("GuideArrow", Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(110, 255, 230), Enum.Material.Neon, 1) :: Part
local function arrowTarget(): Vector3?
	if prof == nil then return nil end
	if where == "atrium" and prof.frontier == 1 and prof.stars == 0 then
		return Vector3.new(W.SoloCab[1], 13.5, W.SoloCab[2] + W.CabHalf)
	end
	if where == "room" and rs and rs.slot and rs.slot <= 2 and rs.state == "playing" then
		local o = anchor()
		for _, s in rs.stations do
			if not s.solved then
				local p = W.Stations[s.id]
				return o + Vector3.new(p[1] * 0.85, 12.5, p[3])
			end
		end
		local d = W.Stations.Door
		return o + Vector3.new(d[1], 10.5, d[3] + 1.5)
	end
	return nil
end

--============================================================================ state
local current: { [string]: any }? = nil
local weights: { [number]: number } = {}
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local seeded = false
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat = false
local satAt = 0
local SIT_SETTLE_SECONDS = 1.0
local knockUntil: number? = nil
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local frameError = false
local lastRest = { resting = false, pending = false }
local lastHazardText: string? = nil
local lastHazardActive = false

local function postRest()
	local r = { resting = restOn and Rest.isResting(rest), pending = restOn and rest.pending == true }
	if r.resting ~= lastRest.resting or r.pending ~= lastRest.pending then
		lastRest = r
		ClientBus.fire("rest", r)
	end
end

local function unsit()
	if sat and hum then
		pcall(function() (hum :: Humanoid).Sit = false end)
	end
	sat = false
	restFocus.Enabled = false
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	rest = Rest.new()
	sat = false
	restFocus.Enabled = false
	knockUntil = nil
	if scheduler.active then
		scheduler.active = nil
		hideHazard()
	end
	postRest()
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local function groundedNow(): boolean
	if hum == nil then return false end
	local fm = (hum :: any).FloorMaterial
	return fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
end

ClientBus.on("breakPressed", function()
	if not restOn then return end
	if Rest.isResting(rest) or rest.pending then
		Rest.stop(rest)
		unsit()
		postRest()
		return
	end
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = groundedNow(), threat = scheduler.active ~= nil })
	if result == "resting" then
		sat = true
		satAt = now
		restFocus.Enabled = true
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
	end
	postRest()
end)

-- A Break is a pause from the room, never a hazard-free way to solve it: opening a station ends it.
ClientBus.on("overlay", function(o: any)
	if o and o.open and restOn then
		Rest.stop(rest)
		unsit()
		postRest()
	end
end)

--============================================================================ the frame
local function frame(dt: number)
	now += dt
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local p = progress()
	local bandIdx = namedBand()
	local at = anchor()

	-- band weights, smoothed so a lift ride glides instead of cutting
	local targetW = EnvBands.weights(bands, p)
	for i = 1, #bands do
		local tw = targetW[i] or 0
		weights[i] = if current == nil then tw else EnvBands.approach(weights[i] or 0, tw, dt, Env.HalfLife)
	end

	-- lighting, at most LightingHz, only when a value changed
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		if current == nil then
			current = {}
			for _, g in GROUPS do (current :: any)[g] = EnvBands.sample(bands, 0, g) end
		end
		for _, g in GROUPS do
			(current :: any)[g] = EnvBands.approachTable((current :: any)[g], EnvBands.sample(bands, p, g), step, Env.HalfLife)
			writeGroup(targets[g], (current :: any)[g])
		end
	end

	updateDecor(weights, at)
	updateCritters(weights, at)
	updateWeather(weights, at)

	-- a rare shooting star over the Roof
	if where == "roof" then
		nextShootingStar -= dt
		if nextShootingStar <= 0 and shootingStar == nil then
			nextShootingStar = 25 + 20 * rand()
			local s = localPart("ShootingStar", Vector3.new(6, 0.2, 0.2), Color3.fromRGB(230, 240, 255), Enum.Material.Neon)
			if s == nil then return end
			local from = Vector3.new(-120 + 60 * rand(), W.RoofY + 90, -160)
			s.CFrame = CFrame.lookAt(from, from + Vector3.new(1, -0.2, 0.3))
			shootingStar = s
			local tw = TweenService:Create(s, TweenInfo.new(1, Enum.EasingStyle.Linear), { Position = from + Vector3.new(200, -40, 60), Transparency = 1 })
			tw.Completed:Connect(function()
				s:Destroy()
				shootingStar = nil
			end)
			tw:Play()
		end
	end

	-- the guide arrow bobs over the next thing to do, in the first rooms
	local target = arrowTarget()
	if target then
		arrow.Transparency = 0.1
		arrow.CFrame = CFrame.new(target + Vector3.new(0, 0.4 * math.sin(now * 3), 0)) * CFrame.Angles(0, now * 2, math.rad(45))
	elseif arrow.Transparency < 1 then
		arrow.Transparency = 1
	end

	-- title cards: once per new highest band, seeded from the LOADED profile (+1 Jump's slow-load finding)
	if not seeded and prof and prof.loaded then
		seeded = true
		local f = prof.frontier or 1
		local seedBand = if prof.escaped then #bands else math.clamp(math.ceil(f / 3), 1, #bands - 1)
		EnvBands.announce(announcer, math.max(seedBand, 1))
	end
	if seeded and EnvBands.announce(announcer, bandIdx) and bandIdx < #bands then
		local b = bands[bandIdx]
		ClientBus.fire("card", { title = string.format("WING %d \u{00B7} THE %s", bandIdx, string.upper(b.name)),
			sub = "A new wing: new light, new weather, new things on the ceiling." })
	end

	if hrp == nil or hum == nil then return end
	local root = hrp :: BasePart
	local humanoid = hum :: Humanoid

	if knockUntil and now >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end

	local grounded = groundedNow()
	local supported = grounded
	if sat and not grounded and knockUntil == nil then
		local vy = root.AssemblyLinearVelocity.Y
		supported = math.abs(vy) < 2 or (now - satAt) < SIT_SETTLE_SECONDS
	end
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true

	-- the Break
	if restOn then
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = scheduler.active ~= nil })
		if ev == "started" and rest.source == "manual" then
			sat = true
			satAt = now
			restFocus.Enabled = true
			pcall(function() humanoid.Sit = true end)
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
		postRest()
	end
	local resting = restOn and Rest.isResting(rest)

	-- hazards: exposed only inside a room's play area, past the arrival grace, on a legal spot
	if hazardsOn then
		local pos = root.Position
		local loc = pos - at
		local inRoom = where == "room" and math.abs(loc.X) <= W.RoomHalf and math.abs(loc.Z) <= W.RoomHalf
		local look = camera.CFrame.LookVector
		local before = if scheduler.active then scheduler.active.t else nil
		-- The clock runs only where a hazard may be released: a legal spot, past the arrival grace (review-1
		-- B4). It used to run at the door station and in the grace with `grounded = false`, so a hazard that
		-- came due there was HELD and fired the moment the player stepped onto a legal spot, or exactly as the
		-- next room's grace ended (15 of 40 in the reviewer's runs). Frozen, it can never back up.
		local releasable = inRoom and Lab.legalSpot(loc.X, loc.Z, Config) and (now - arrivedAt) >= Config.Lift.ArrivalGraceSeconds
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting or not releasable, -- the Atrium, the cabs, the Roof, the doorways and the grace freeze it
			grounded = grounded,
			kinds = if where == "room" then (bands[bandIdx].hazards or {}) else {},
			aim = { x = pos.X, y = pos.Y, z = pos.Z },
			yaw = math.atan2(look.X, look.Z),
			pitch = math.rad(Hz.PitchDegrees), -- ALWAYS 85 degrees: straight down from the ceiling (trap 4)
		}, rand)
		if ev and ev.type == "done" then hideHazard() end
		local plan = scheduler.active
		local text, clear, active = nil, false, false
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			showHazard(plan, hp, if live then Hazards.zone(plan, Hz.PlayerRadius) else nil, at.Y + W.RoomHeight)
			if Hazards.checkHit(plan, before or 0, plan.t, { x = pos.X, y = pos.Y, z = pos.Z }, Hz.PlayerRadius) then
				plan.hit = true
				local kv = Hazards.knockVelocity(Hz, plan, { x = pos.X, y = pos.Y, z = pos.Z })
				pcall(function() humanoid.PlatformStand = true end)
				root.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				Rest.stop(rest)
				unsit()
				postRest()
				FxClient.shake(0.4, 0.9)
				FxClient.flash(Color3.fromRGB(255, 255, 255), 0.3, 0.35)
			end
			if live and not plan.hit then
				active = true
				local name = Hz.Names[plan.kind] or string.upper(plan.kind)
				if Hazards.inZone(plan, { x = pos.X, y = pos.Y, z = pos.Z }, Hz.PlayerRadius) then
					text = "\u{26A0} " .. name .. " - STEP OUT OF THE RING"
				else
					text = name .. " - CLEAR"
					clear = true
				end
			end
		end
		if active ~= lastHazardActive or text ~= lastHazardText then
			lastHazardActive = active
			lastHazardText = text
			ClientBus.fire("hazard", { active = active, text = text, clear = clear })
		end
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken frame must not flood the output
		warn("[LabEnv] frame error: " .. tostring(err))
	end
end)
