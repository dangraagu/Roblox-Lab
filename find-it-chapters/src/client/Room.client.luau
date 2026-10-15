-- FIND IT! CHAPTERS: the room you see (StarterPlayerScripts). Client only; the owner's client builds its own room.
-- The template glue follows escape-room-lab/src/client/Lab.client.luau (itself plus1-jump's Sky.client); what
-- differs for a hidden-object room, and why, is in EYECANDY.md.
--
-- Every frame, for THIS player only:
--   * the band (EnvBands.luau, verbatim): progress = the chapter you are in (the Daily: its theme band); in the
--     hub the target is Config.Env.Hub. Entering a room glides the light at a 0.8 s half-life; clearing a band's
--     last chapter moves progress to the next band, so the room glides toward it. The light never changes during
--     a search (progress only moves on entry and on a clear), so a clue colour never shifts under a reader;
--   * decor, critters (above head height, INSIDE the room: a closed room shows nothing beyond its walls), weather
--     (2 emitters, EnvBands.capRates; rain and drizzle run down glass, RoomArt.weatherSpots), lightning in the ship's
--     portholes (never a Lighting write), lamps (4 lights);
--   * the hazards (Hazards.luau, verbatim) with ctx.pitch = rad(85): a near-vertical drop from the ceiling. The
--     clock runs only on a legal spot of a live room past the arrival grace; anywhere else ctx.resting = true, so
--     a hazard can never come due where it cannot be released and be held (escape-room-lab REVIEW-1 B4);
--     the red ring IS the hit zone (Hazards.zone / checkHit);
--   * the Pause (Rest.luau, verbatim; IdleSeconds = 0 on purpose): it cannot start mid-air or with a drop on the
--     way; when it starts the server is told (Pause) and stops the clock; a move wakes it (Resume), and the server
--     re-dresses the room.
-- Taps: a short press that does not drag picks the nearest prop on the ray (Pick.luau); the first tap selects
-- (white outline, label in the HUD), the second (or Search, or E) asks the server. Nothing here decides a find.
-- Every part this script builds lives in workspace.FindItLocalRoom and never replicates; the part, light and
-- emitter budgets are capped in code (Config.Budget).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local RoomArt = require(ReplicatedStorage:WaitForChild("RoomArt"))
local Pick = require(ReplicatedStorage:WaitForChild("Pick"))
local Clue = require(ReplicatedStorage:WaitForChild("Clue"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local ClientBus = require(ReplicatedStorage:WaitForChild("ClientBus"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end
local remotes = ReplicatedStorage:WaitForChild("FindItRemotes")
local SearchEv = remotes:WaitForChild("Search") :: RemoteEvent
local PauseEv = remotes:WaitForChild("Pause") :: RemoteEvent
local ResumeEv = remotes:WaitForChild("Resume") :: RemoteEvent

local Env, Hz, RestCfg, Budget, W, Room = Config.Env, Config.Hazards, Config.Rest, Config.Budget, Config.World, Config.Room
local bands = Env.Bands
local GOLD = Color3.fromRGB(Config.Reserved.Gold[1], Config.Reserved.Gold[2], Config.Reserved.Gold[3])
local RING = Color3.fromRGB(Config.Reserved.Ring[1], Config.Reserved.Ring[2], Config.Reserved.Ring[3])

-- A broken config costs the polish, never the game: warn loudly and switch that part off.
local bandsOn = true
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[FindItRoom] Config.Env.Bands is invalid (" .. tostring(err) .. "); the room keeps the server's lighting.")
		bandsOn = false
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then warn("[FindItRoom] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.") end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then warn("[FindItRoom] Config.Rest is invalid (" .. tostring(restErr) .. "); Pause is OFF.") end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local function c3(t: { number }): Color3
	return Color3.fromRGB(math.clamp(math.round(t[1]), 0, 255), math.clamp(math.round(t[2]), 0, 255), math.clamp(math.round(t[3]), 0, 255))
end

--============================================================================ the local world and its budgets
local folder = Instance.new("Folder")
folder.Name = "FindItLocalRoom"
folder.Parent = workspace

local localCount, lightCount, emitterCount = 0, 0, 0
local stats = { refusedParts = 0, refusedLights = 0, refusedEmitters = 0, peakParts = 0 }
local function localPart(name: string, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?, reserved: boolean?, parent: Instance?): Part?
	local cap = if reserved then Budget.LocalParts else Budget.LocalParts - Budget.HazardParts
	if localCount >= cap then
		stats.refusedParts += 1
		return nil
	end
	localCount += 1
	if localCount > stats.peakParts then stats.peakParts = localCount end
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or folder
	p.Destroying:Connect(function() localCount -= 1 end)
	return p
end
local function localLight(host: BasePart, color: Color3, brightness: number, range: number): PointLight?
	if lightCount >= Budget.Lights then
		stats.refusedLights += 1
		return nil
	end
	lightCount += 1
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = host
	l.Destroying:Connect(function() lightCount -= 1 end)
	return l
end
local function localEmitter(host: BasePart, name: string): ParticleEmitter?
	if emitterCount >= Budget.Emitters then
		stats.refusedEmitters += 1
		return nil
	end
	emitterCount += 1
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Enabled = false
	e.Rate = 0
	e.Parent = host
	e.Destroying:Connect(function() emitterCount -= 1 end)
	return e
end

local MATERIALS: { [string]: Enum.Material } = {}
local function mat(name: string?): Enum.Material
	if name == nil then return Enum.Material.SmoothPlastic end
	local m = MATERIALS[name]
	if m == nil then
		local ok, v = pcall(function() return (Enum.Material :: any)[name] end)
		m = if ok and v then v else Enum.Material.SmoothPlastic
		MATERIALS[name] = m
	end
	return m
end

--============================================================================ the lighting rig
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
	sky = rig("Sky", "FindItSky"),
}
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "sky" }
local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "FindItRestFocus"
restFocus.FarIntensity = 0.4
restFocus.FocusDistance = 8
restFocus.InFocusRadius = 6
restFocus.NearIntensity = 0
restFocus.Enabled = false
restFocus.Parent = Lighting

local written: { [Instance]: { [string]: any } } = {}
local lightingWrites = 0
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
			if type(v) == "table" then value = c3(v) elseif k == "StarCount" then value = math.round(v) end
			local ok = pcall(function() (inst :: any)[k] = value end)
			if ok then
				last[k] = if type(v) == "table" then { v[1], v[2], v[3] } else v
				lightingWrites += 1
			end
		end
	end
end

--============================================================================ what the server told this player
local where = "hub"
local st: any = nil
local stateAt = 0 -- `now` when st arrived (the pause window counts down with the live clock)
local payload: any = nil
local origin = Vector3.zero
local arrivedAt = -math.huge
local now = 0
local attemptId = nil

local roomParts: { Part } = {} -- props, tables, shelves, screens (rebuilt on a re-dress: the props)
local propParts: { [number]: { Part } } = {}
local propById: { [number]: any } = {}
local fixtureParts: { Part } = {}
local decorParts: { Part } = {}
local lampParts: { Part } = {}
local itemParts: { Part } = {}
local searchedMarks: { [number]: Instance } = {}
local selectedId: number? = nil
local selection: SelectionBox? = nil
local hintBox: SelectionBox? = nil
local hintId: number? = nil
local burstHost: Part? = nil
local burst: ParticleEmitter? = nil
local glintHost: Part? = nil
local glint: ParticleEmitter? = nil

local function toWorld(x: number, y: number, z: number): Vector3
	return origin + Vector3.new(x, y, z)
end

local function clearList(list: { any })
	for _, p in list do
		(p :: Instance):Destroy()
	end
	table.clear(list)
end

local function clearSelection()
	selectedId = nil
	if selection then selection.Adornee = nil end
	ClientBus.fire("select", nil)
end

local function buildProps()
	for _, list in propParts do clearList(list) end
	table.clear(propParts)
	table.clear(propById)
	for _, m in searchedMarks do m:Destroy() end
	table.clear(searchedMarks)
	clearList(fixtureParts)
	clearSelection()
	if payload == nil then return end
	local P = payload
	-- tables and shelves
	local tw, td = Room.TableSize[1], Room.TableSize[2]
	local band = bands[P.band] or bands[1]
	local pal = band.palette
	for i, t in P.tables do
		local top = localPart("Table_" .. i, Vector3.new(tw, 0.4, td), c3(pal.table), Enum.Material.Wood)
		if top then
			top.CFrame = CFrame.new(toWorld(t.x, Room.TableTop - 0.2, t.z))
			top.CanCollide = true
			table.insert(fixtureParts, top)
		end
		local leg = localPart("TableLeg_" .. i, Vector3.new(tw * 0.8, Room.TableTop - 0.4, td * 0.6), c3(pal.trim), Enum.Material.Wood)
		if leg then
			leg.CFrame = CFrame.new(toWorld(t.x, (Room.TableTop - 0.4) / 2, t.z))
			leg.CanCollide = true
			table.insert(fixtureParts, leg)
		end
	end
	for i, s in P.shelves do
		local along = if s.wall == "N" or s.wall == "S" then Vector3.new(Room.ShelfLength, 0.3, 1.6) else Vector3.new(1.6, 0.3, Room.ShelfLength)
		local cx, cz = s.x, s.z
		if s.wall == "N" then cz = P.D - 0.8 elseif s.wall == "S" then cz = 0.8 elseif s.wall == "E" then cx = P.W / 2 - 0.8 else cx = -P.W / 2 + 0.8 end
		local plank = localPart("Shelf_" .. i, along, c3(pal.shelf), Enum.Material.Wood)
		if plank then
			plank.CFrame = CFrame.new(toWorld(cx, Room.ShelfY - 0.15, cz))
			table.insert(fixtureParts, plank)
		end
		for b = 1, 2 do
			local off = (b - 1.5) * (Room.ShelfLength - 1)
			local bx, bz = cx, cz
			if s.wall == "N" or s.wall == "S" then bx += off else bz += off end
			local br = localPart("ShelfBracket_" .. i .. "_" .. b, Vector3.new(0.3, 1.2, 0.3), c3(pal.trim), Enum.Material.Wood)
			if br then
				br.CFrame = CFrame.new(toWorld(bx, Room.ShelfY - 0.9, bz))
				table.insert(fixtureParts, br)
			end
		end
	end
	-- screens close the shell down to W x D
	local H = Room.Height
	if P.W < Room.ShellW then
		for side = -1, 1, 2 do
			local sc = localPart("Screen_" .. (if side < 0 then "W" else "E"), Vector3.new(0.6, H, Room.ShellD), c3(pal.wall), mat(pal.wallMaterial))
			if sc then
				sc.CFrame = CFrame.new(toWorld(side * (P.W / 2 + 0.3), H / 2, Room.ShellD / 2))
				sc.CanCollide = true
				table.insert(fixtureParts, sc)
			end
		end
	end
	if P.D < Room.ShellD then
		local sc = localPart("Screen_N", Vector3.new(P.W, H, 0.6), c3(pal.wall), mat(pal.wallMaterial))
		if sc then
			sc.CFrame = CFrame.new(toWorld(0, H / 2, P.D + 0.3))
			sc.CanCollide = true
			table.insert(fixtureParts, sc)
		end
	end
	-- the props: silhouettes in their clue colour (never red, never gold)
	for _, p in P.props do
		propById[p.id] = p
		local parts = {}
		local spec = RoomArt.Kinds[p.kind] or RoomArt.Kinds.box
		local base = CFrame.new(toWorld(p.x, p.y, p.z)) * CFrame.Angles(0, math.rad(p.yaw or 0), 0)
		for j, ps in spec do
			local color = if ps.role == "body" then c3(Config.Traits.RGB[p.colour]) else c3(RoomArt.Trim)
			local size = Vector3.new(ps.size[1], ps.size[2], ps.size[3])
			local part = localPart(string.format("Prop_%d_%d", p.id, j), size, color, Enum.Material.SmoothPlastic)
			if part then
				if ps.shape == "Ball" then part.Shape = Enum.PartType.Ball elseif ps.shape == "Cylinder" then part.Shape = Enum.PartType.Cylinder end
				local cf = base * CFrame.new(ps.offset[1], ps.offset[2], ps.offset[3])
				if ps.upright then cf = cf * CFrame.Angles(0, 0, math.rad(90)) end
				part.CFrame = cf
				table.insert(parts, part)
			end
		end
		propParts[p.id] = parts
	end
end

local function buildDecorAndLamps()
	clearList(decorParts)
	clearList(lampParts)
	if payload == nil then return end
	local band = bands[payload.band] or bands[1]
	local placed = 0
	for _, d in RoomArt.decorParts(band.decor, payload.W, payload.D) do
		if placed >= Budget.DecorParts then break end
		local p = localPart("Decor_" .. d.set .. "_" .. d.id, Vector3.new(d.size[1], d.size[2], d.size[3]), c3(d.color), mat(d.material), d.transparency)
		if p == nil then break end
		placed += 1
		if d.shape == "Ball" then p.Shape = Enum.PartType.Ball elseif d.shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder end
		local cf = CFrame.new(toWorld(d.pos[1], d.pos[2], d.pos[3]))
		if d.shape == "Cylinder" and d.orient == "up" then cf = cf * CFrame.Angles(0, 0, math.rad(90)) end
		p.CFrame = cf
		table.insert(decorParts, p)
	end
	for i, spot in RoomArt.lampSpots(payload.W, payload.D) do
		local lamp = localPart("Lamp_" .. i, Vector3.new(0.9, 0.9, 0.9), c3(band.lamp.color), Enum.Material.Neon, 0)
		if lamp == nil then break end
		lamp.Shape = Enum.PartType.Ball
		lamp.CFrame = CFrame.new(toWorld(spot[1], spot[2], spot[3]))
		localLight(lamp, c3(band.lamp.color), band.lamp.brightness, band.lamp.range)
		table.insert(lampParts, lamp)
	end
end

local function clearRoom()
	for _, list in propParts do clearList(list) end
	table.clear(propParts)
	table.clear(propById)
	clearList(fixtureParts)
	clearList(decorParts)
	clearList(lampParts)
	clearList(itemParts)
	for _, m in searchedMarks do m:Destroy() end
	table.clear(searchedMarks)
	clearSelection()
	if hintBox then hintBox.Adornee = nil end
	hintId = nil
	if glint then glint.Enabled = false end
end

--============================================================================ selection, search, results
local function rootPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if hrp then hrp.Position else nil
end

local function inReach(p: any): boolean
	local rp = rootPos()
	if rp == nil then return false end
	local w = toWorld(p.x, p.y, p.z)
	return Pick.inReach({ rp.X, rp.Y, rp.Z }, { x = w.X, y = w.Y, z = w.Z }, Config.Search.Reach)
end

local function select(id: number)
	local p = propById[id]
	if p == nil then return end
	selectedId = id
	if selection == nil then
		local sb = Instance.new("SelectionBox")
		sb.Name = "FindItSelection"
		sb.Color3 = Color3.new(1, 1, 1) -- white: never red (the ring), never gold (a find)
		sb.LineThickness = 0.06
		sb.SurfaceTransparency = 1
		sb.Parent = folder
		selection = sb
	end
	local parts = propParts[id]
	if selection then selection.Adornee = parts and parts[1] or nil end
	ClientBus.fire("select", { id = id, label = Clue.label(p, Config), inReach = inReach(p) })
end

local function trySearch(id: number)
	local p = propById[id]
	if p == nil then return end
	if not inReach(p) then
		ClientBus.fire("toast", Config.Text.WalkCloser)
		return
	end
	SearchEv:FireServer(id)
end

-- the pick: props in world space, tables as occluders
local function pickAt(sx: number, sy: number, isScreen: boolean): (any, boolean)
	if payload == nil then return nil, false end
	local o, d
	local ok = false
	if isScreen and (camera :: any).ScreenPointToRay then
		ok = pcall(function()
			local ray = (camera :: any):ScreenPointToRay(sx, sy)
			o = { ray.Origin.X, ray.Origin.Y, ray.Origin.Z }
			d = { ray.Direction.X, ray.Direction.Y, ray.Direction.Z }
		end)
	end
	if not ok then
		local cf = camera.CFrame
		local vp = camera.ViewportSize
		-- the headless path: an InputObject's Position is below the topbar, the viewport ray is not (REVIEW-1 B4: the
		-- topbar is read, not assumed)
		local topY = 36
		pcall(function()
			local a = GuiService:GetGuiInset()
			if a and type(a.Y) == "number" then topY = a.Y end
		end)
		local vy = if isScreen then sy + topY else sy
		o, d = Pick.ray({ pos = { cf.Position.X, cf.Position.Y, cf.Position.Z }, look = { cf.LookVector.X, cf.LookVector.Y, cf.LookVector.Z },
			right = { cf.RightVector.X, cf.RightVector.Y, cf.RightVector.Z }, up = { cf.UpVector.X, cf.UpVector.Y, cf.UpVector.Z } },
			camera.FieldOfView, vp.X, vp.Y, sx, vy)
	end
	local props = {}
	for _, p in payload.props do
		local w = toWorld(p.x, p.y, p.z)
		table.insert(props, { id = p.id, kind = p.kind, x = w.X, y = w.Y, z = w.Z })
	end
	local occ = {}
	for _, t in payload.tables do
		local w = toWorld(t.x, Room.TableTop / 2, t.z)
		table.insert(occ, { cx = w.X, cy = w.Y, cz = w.Z, hx = Room.TableSize[1] / 2, hy = Room.TableTop / 2, hz = Room.TableSize[2] / 2 })
	end
	local hit = Pick.pick(o, d, props, occ, RoomArt.pickBox)
	if hit then return hit, false end
	-- a tap on furniture or decor (something in the room that is not a prop) is answered on the client
	local decorHit = false
	for _, oc in occ do
		if Pick.hitBox(o, d, { oc.cx, oc.cy, oc.cz }, { oc.hx, oc.hy, oc.hz }) then decorHit = true end
	end
	for _, dp in decorParts do
		local c = dp.Position
		local s = dp.Size
		if Pick.hitBox(o, d, { c.X, c.Y, c.Z }, { s.X / 2, s.Y / 2, s.Z / 2 }) then decorHit = true end
	end
	return nil, decorHit
end

local function tapAt(sx: number, sy: number, isScreen: boolean)
	if where ~= "room" or st == nil or st.state == "done" then return end
	local hit, decorHit = pickAt(sx, sy, isScreen)
	if hit then
		if selectedId == hit.id then
			trySearch(hit.id)
		else
			select(hit.id)
		end
	elseif decorHit then
		ClientBus.fire("toast", Config.Text.DecorTap)
	end
end

local press: any = nil
UserInputService.InputBegan:Connect(function(input: any, processed: boolean)
	if processed then return end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		press = { x = input.Position.X, y = input.Position.Y, at = now }
	elseif t == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.E then
		if selectedId then trySearch(selectedId) end
	end
end)
UserInputService.InputEnded:Connect(function(input: any, processed: boolean)
	local t = input.UserInputType
	if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and press then
		local p = press
		press = nil
		if processed then return end
		if Pick.isTap({ x = p.x, y = p.y }, { x = input.Position.X, y = input.Position.Y }, now - p.at) then
			tapAt(input.Position.X, input.Position.Y, true)
		end
	end
end)
ClientBus.on("searchPressed", function()
	if selectedId then trySearch(selectedId) end
end)
-- a test/film hook that taps a prop the way a finger would: select, then search (never a shortcut past reach)
ClientBus.on("tapProp", function(id: any)
	if type(id) ~= "number" or propById[id] == nil then return end
	if selectedId == id then trySearch(id) else select(id) end
end)

local function ensureBurst()
	if burstHost == nil then
		burstHost = localPart("BurstHost", Vector3.new(0.2, 0.2, 0.2), GOLD, Enum.Material.SmoothPlastic, 1, true)
		if burstHost then
			burst = localEmitter(burstHost, "FoundBurst")
			if burst then
				burst.Color = ColorSequence.new(GOLD)
				burst.LightEmission = 1
				burst.Size = NumberSequence.new(0.35, 0)
				burst.Speed = NumberRange.new(6, 10)
				burst.Lifetime = NumberRange.new(0.5, 0.9)
				burst.SpreadAngle = Vector2.new(180, 180)
			end
		end
	end
end
local function ensureGlint()
	if glintHost == nil then
		glintHost = localPart("GlintHost", Vector3.new(0.2, 0.2, 0.2), GOLD, Enum.Material.SmoothPlastic, 1, true)
		if glintHost then
			glint = localEmitter(glintHost, "HintGlint")
			if glint then
				glint.Color = ColorSequence.new(GOLD)
				glint.LightEmission = 1
				glint.Size = NumberSequence.new(0.25, 0)
				glint.Speed = NumberRange.new(0.2, 0.8)
				glint.Lifetime = NumberRange.new(0.6, 1.2)
			end
		end
	end
end

local foundCount = 0
local function onResult(res: any)
	if type(res) ~= "table" or payload == nil then return end
	local p = propById[res.id]
	if p == nil then return end
	local top = toWorld(p.x, p.y + 2.4, p.z)
	if res.hit then
		ensureBurst()
		if burstHost and burst then
			burstHost.CFrame = CFrame.new(top)
			local e = burst
			pcall(function() e:Emit(24) end) -- cosmetic; robloxemu does not model Emit (the same guard as labyrint-spill)
		end
		local itemId = payload.clues[res.item] and payload.clues[res.item].item
		local look = itemId and RoomArt.Items[itemId]
		if look and #itemParts < Budget.ItemsShown then
			local ip = localPart("Item_" .. tostring(itemId), Vector3.new(look.size[1], look.size[2], look.size[3]), c3(look.color), Enum.Material.SmoothPlastic, 0, true)
			if ip then
				if look.shape == "Ball" then ip.Shape = Enum.PartType.Ball elseif look.shape == "Cylinder" then ip.Shape = Enum.PartType.Cylinder end
				ip.CFrame = CFrame.new(top)
				table.insert(itemParts, ip)
				pcall(function()
					TweenService:Create(ip, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = top + Vector3.new(0, 1.2, 0) }):Play()
				end)
			end
		end
		foundCount += 1
		FxClient.fovPunch(4, 0.25)
		if hintId == res.id then
			hintId = nil
			if hintBox then hintBox.Adornee = nil end
			if glint then glint.Enabled = false end
		end
		ClientBus.fire("found", { item = res.item, id = res.id })
	else
		-- a puff of dust and a grey tick, for memory
		local parts = propParts[res.id]
		local host = parts and parts[1]
		if host and searchedMarks[res.id] == nil then
			local bb = Instance.new("BillboardGui")
			bb.Name = "Searched"
			bb.Size = UDim2.fromOffset(28, 28)
			bb.StudsOffset = Vector3.new(0, 1.6, 0)
			bb.Adornee = host
			bb.Parent = folder
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Text = "\u{2713}"
			l.TextScaled = true
			l.TextColor3 = Color3.fromRGB(150, 150, 150)
			l.Parent = bb
			searchedMarks[res.id] = bb
		end
	end
	if selectedId == res.id then clearSelection() end
end

local function onHint(h: any)
	if type(h) ~= "table" or type(h.id) ~= "number" then return end
	hintId = h.id
	local parts = propParts[h.id]
	if hintBox == nil then
		local sb = Instance.new("SelectionBox")
		sb.Name = "FindItHint"
		sb.Color3 = GOLD -- gold: a hinted thing
		sb.LineThickness = 0.08
		sb.SurfaceTransparency = 1
		sb.Parent = folder
		hintBox = sb
	end
	if hintBox then hintBox.Adornee = parts and parts[1] or nil end
	ensureGlint()
	local p = propById[h.id]
	if glintHost and glint and p then
		glintHost.CFrame = CFrame.new(toWorld(p.x, p.y + 1.5, p.z))
		glint.Rate = 10
		glint.Enabled = true
	end
end

--============================================================================ critters and weather
local critters: { [string]: { { Part } } } = {}
local function updateCritters(bandIdx: number?)
	local counts: { [string]: number } = {}
	if bandIdx and where == "room" and payload then
		local shown = 0
		for _, c in bands[bandIdx].critters do
			local n = math.min(c.count, Budget.Critters - shown)
			shown += n
			counts[c.kind] = (counts[c.kind] or 0) + n
		end
	end
	for kind, list in critters do
		local n = counts[kind] or 0
		while #list > n do
			for _, p in table.remove(list) :: { Part } do p:Destroy() end
		end
	end
	for kind, n in counts do
		local spec = RoomArt.Critters[kind]
		if spec == nil then continue end
		local list = critters[kind]
		if list == nil then
			list = {}
			critters[kind] = list
		end
		while #list < n do
			local parts = {}
			for j, ps in spec.parts do
				local p = localPart(string.format("Critter_%s_%d_%d", kind, #list + 1, j), Vector3.new(ps.size[1], ps.size[2], ps.size[3]), c3(ps.color), mat(ps.material))
				if p == nil then break end
				if ps.shape == "Ball" then p.Shape = Enum.PartType.Ball end
				table.insert(parts, p)
			end
			if #parts < #spec.parts then
				for _, p in parts do p:Destroy() end
				break
			end
			table.insert(list, parts)
		end
		for i, parts in list do
			local pos = RoomArt.critterPos(kind, i, now, payload.W, payload.D)
			local ahead = RoomArt.critterPos(kind, i, now + 0.1, payload.W, payload.D)
			local a = toWorld(pos[1], pos[2], pos[3])
			local b = toWorld(ahead[1], ahead[2], ahead[3])
			local cf = if (b - a).Magnitude > 1e-3 then CFrame.lookAt(a, b) else CFrame.new(a)
			for j, part in parts do
				local o = spec.parts[j].offset
				part.CFrame = cf * CFrame.new(o[1], o[2], o[3])
			end
		end
	end
end

local weatherHosts = {}
local function ensureWeather()
	if #weatherHosts > 0 then return end
	for i = 1, Budget.WeatherEmitters do
		local host = localPart("WeatherHost_" .. i, Vector3.new(30, 0.4, 30), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1, true)
		if host == nil then return end
		local e = localEmitter(host, "Weather")
		if e then e.EmissionDirection = Enum.NormalId.Bottom end
		weatherHosts[i] = { host = host, emitter = e, kind = nil }
	end
end
local function styleEmitter(e: ParticleEmitter, kind: string)
	local w = RoomArt.Weather[kind]
	if w == nil then return end
	e.Color = ColorSequence.new(c3(w.color))
	e.Size = NumberSequence.new(w.size)
	e.Transparency = NumberSequence.new(w.alpha)
	e.Speed = NumberRange.new(w.speed[1], w.speed[2])
	e.Lifetime = NumberRange.new(w.life[1], w.life[2])
	e.Acceleration = Vector3.new(w.accel[1], w.accel[2], w.accel[3])
	e.LightEmission = w.light
end
local weatherOn = {}
-- Which emitter shows which kind where: every kind gets its first spot, then spare emitters go to the further
-- spots of kinds that have them (the ship's rain: one emitter per porthole), and a kind's rate is split between its
-- emitters. REVIEW-1 round 2 D2: rain and drizzle RUN DOWN GLASS inside the room (RoomArt.weatherSpots); they used
-- to fall beyond the east wall, where a closed room shows nothing.
local function assignWeather(kinds: { string }, W: number, D: number): { any }
	local out = {}
	local spare = {}
	for _, kind in kinds do
		local spots = RoomArt.weatherSpots(kind, W, D, Config)
		table.insert(out, { kind = kind, spot = spots[1] })
		for j = 2, #spots do table.insert(spare, { kind = kind, spot = spots[j] }) end
	end
	for _, sp in spare do
		if #out >= Budget.WeatherEmitters then break end
		table.insert(out, sp)
	end
	return out
end
local function updateWeather(bandIdx: number?)
	ensureWeather()
	local rates: { [string]: number } = {}
	if bandIdx and where == "room" then
		for _, wx in bands[bandIdx].weather do rates[wx.kind] = (rates[wx.kind] or 0) + wx.rate end
	end
	local on = EnvBands.capRates(rates, Budget.WeatherEmitters, Budget.MaxEmitterRate, Budget.MinWeatherRate)
	weatherOn = on
	local kinds = {}
	for kind in on do table.insert(kinds, kind) end
	table.sort(kinds)
	local plan = if payload then assignWeather(kinds, payload.W, payload.D) else {}
	local share: { [string]: number } = {}
	for _, a in plan do share[a.kind] = (share[a.kind] or 0) + 1 end
	for i, h in weatherHosts do
		local a = plan[i]
		if a and h.emitter and payload then
			local s = a.spot
			h.host.Size = Vector3.new(s.size[1], s.size[2], s.size[3])
			h.host.CFrame = CFrame.new(toWorld(s.pos[1], s.pos[2], s.pos[3]))
			if h.kind ~= a.kind then
				styleEmitter(h.emitter, a.kind)
				h.kind = a.kind
			end
			h.emitter.Rate = on[a.kind] / share[a.kind]
			h.emitter.Enabled = true
		elseif h.emitter then
			h.emitter.Enabled = false
			h.emitter.Rate = 0
			h.kind = nil
		end
	end
end

--============================================================================ the ship's storm: lightning in the portholes
-- REVIEW-1 round 2 D2: now and then the view in every porthole flashes pale (RoomArt.Lightning). Only those decor
-- parts change: never a Lighting property, so a clue colour never changes under a flash.
local lightning = { nextAt = nil :: number?, untilT = nil :: number?, count = 0, saved = {} :: { [Instance]: any } }
local function portholeViews(): { Part }
	local out = {}
	for _, d in decorParts do
		if string.match(d.Name, "^Decor_portholes_port[EW]%d") then table.insert(out, d) end
	end
	return out
end
local function endFlash()
	for p, was in lightning.saved do
		if p.Parent then
			p.Color = was.color
			p.Material = was.material
		end
	end
	table.clear(lightning.saved)
	lightning.untilT = nil
end
local function updateLightning(bandIdx: number?)
	local L = RoomArt.Lightning
	local on = bandIdx ~= nil and where == "room" and payload ~= nil and bands[bandIdx].lightning == true
	if lightning.untilT and (not on or now >= lightning.untilT) then endFlash() end
	if not on then
		lightning.nextAt = nil
		return
	end
	if lightning.nextAt == nil then lightning.nextAt = now + L.every[1] + (L.every[2] - L.every[1]) * rand() end
	if now >= lightning.nextAt and lightning.untilT == nil then
		local views = portholeViews()
		if #views > 0 then
			for _, p in views do
				lightning.saved[p] = { color = p.Color, material = p.Material }
				p.Color = c3(L.color)
				p.Material = Enum.Material.Neon
			end
			lightning.untilT = now + L.seconds
			lightning.count += 1
		end
		lightning.nextAt = now + L.every[1] + (L.every[2] - L.every[1]) * rand()
	end
end

--============================================================================ hazards: the model and the ring
local hazardParts: { Part } = {}
local hazardKind: string? = nil
local ring: Part? = nil
local function hideHazard()
	for _, p in hazardParts do p:Destroy() end
	table.clear(hazardParts)
	hazardKind = nil
	if ring then
		ring:Destroy()
		ring = nil
	end
end
local function showHazard(plan: any, pos: any, zone: any)
	if hazardKind ~= plan.kind then
		hideHazard()
		hazardKind = plan.kind
		for j, ps in RoomArt.Hazards[plan.kind] or RoomArt.Hazards.pinecone do
			local p = localPart(string.format("Hazard_%s_%d", plan.kind, j), Vector3.new(ps.size[1], ps.size[2], ps.size[3]), c3(ps.color), mat(ps.material), 0, true)
			if p then
				if ps.shape == "Ball" then p.Shape = Enum.PartType.Ball elseif ps.shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder end
				table.insert(hazardParts, p)
			end
		end
	end
	local spec = RoomArt.Hazards[plan.kind] or RoomArt.Hazards.pinecone
	local here = Vector3.new(pos.x, pos.y, pos.z)
	local wobble = if plan.t < plan.arriveAt - 0.4 then 0.25 * math.sin(now * 18) else 0
	for j, p in hazardParts do
		local o = (spec[j] or spec[1]).offset
		p.CFrame = CFrame.new(here + Vector3.new(o[1], o[2], o[3])) * CFrame.Angles(0, 0, wobble)
	end
	-- THE RING IS THE HIT ZONE: centred on Hazards.zone, radius = hitRadius + PlayerRadius, at the feet
	if zone then
		if ring == nil then
			ring = localPart("HazardRing", Vector3.new(0.1, 1, 1), RING, Enum.Material.Neon, 0.35, true)
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

--============================================================================ server payloads
local function onRoom(pl: any)
	if type(pl) ~= "table" then return end
	local o = pl.origin or { 0, 0, 0 }
	origin = Vector3.new(o[1], o[2], o[3])
	local fresh = pl.attemptId ~= attemptId or not pl.redress
	attemptId = pl.attemptId
	payload = pl
	if fresh and not pl.redress then
		clearRoom()
		buildDecorAndLamps()
		arrivedAt = now
		foundCount = 0
	end
	if pl.redress then
		-- every prop moved: a found item must not float where its prop used to be (its chip stays gold)
		clearList(itemParts)
	end
	buildProps()
	if pl.redress and hintBox then
		hintBox.Adornee = nil
		hintId = nil
		if glint then glint.Enabled = false end
	end
end

local function onState(s: any)
	if type(s) ~= "table" then return end
	local prevWhere = where
	st = s
	stateAt = now
	where = s.where or "hub"
	if where ~= "room" then
		if prevWhere == "room" then clearRoom() end
		payload = nil
	end
end

-- BOOK ONE SOLVED, for this player: the hub's Case Book turns gold (a local change; others see their own book)
local function onProfile(p: any)
	if type(p) ~= "table" or not p.bookSolved then return end
	local world = workspace:FindFirstChild("FindItWorld")
	local hubF = world and world:FindFirstChild("Hub")
	local book = hubF and hubF:FindFirstChild("CaseBook")
	if book and book:IsA("BasePart") then
		book.Color = GOLD
		book.Material = Enum.Material.Neon
	end
end

ClientBus.on("room", onRoom)
ClientBus.on("state", onState)
ClientBus.on("profile", onProfile)
if ClientBus.last("profile") then onProfile(ClientBus.last("profile")) end
ClientBus.on("result", onResult)
ClientBus.on("hint", onHint)
if ClientBus.last("room") then onRoom(ClientBus.last("room")) end
if ClientBus.last("state") then onState(ClientBus.last("state")) end

-- BOOK ONE SOLVED: the observatory dome opens and gold shooting stars cross it
local bragShown: { [any]: boolean } = {}
ClientBus.on("state", function(s: any)
	if type(s) ~= "table" or s.result == nil or not s.result.bookSolved or bragShown[s.attemptId] then return end
	bragShown[s.attemptId] = true
	for _, d in decorParts do
		if string.find(d.Name, "domeSlit", 1, true) then
			pcall(function() TweenService:Create(d, TweenInfo.new(2.5), { Transparency = 1 }):Play() end)
		end
	end
	for i = 1, 3 do
		task.delay((i - 1) * 0.6, function()
			-- under the dome's opaque disc (REVIEW-1 round 2 D3: at Height - 0.5 every star started inside it)
			local from = toWorld(-20 + 6 * i, Room.Height - 2, (payload and payload.D or 38) * 0.3)
			local star = localPart("ShootingStar_" .. i, Vector3.new(4, 0.2, 0.2), GOLD, Enum.Material.Neon, 0, true)
			if star == nil then return end
			star.CFrame = CFrame.lookAt(from, from + Vector3.new(1, -0.1, 0.4))
			local ok = pcall(function()
				local tw = TweenService:Create(star, TweenInfo.new(1.2, Enum.EasingStyle.Linear), { Position = from + Vector3.new(30, -2, 12), Transparency = 1 })
				tw.Completed:Connect(function() star:Destroy() end)
				tw:Play()
			end)
			if not ok then task.delay(1.2, function() star:Destroy() end) end
		end)
	end
	FxClient.flash(Color3.new(1, 1, 1), 0.4, 0.5)
	FxClient.fovPunch(10, 0.5)
end)

--============================================================================ the Pause (Rest) and the frame
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local current: { [string]: any }? = nil
local lightAccum = 0
local knockUntil: number? = nil
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local frameError = false
local selectedInReach: boolean? = nil
local lastRest = { resting = false, pending = false }
local lastHazardText: string? = nil
local lastHazardActive = false
local sentPause = false
local hazardStats = { launched = 0, hits = 0 }

local function postRest()
	local r = { resting = restOn and Rest.isResting(rest), pending = restOn and rest.pending == true }
	if r.resting ~= lastRest.resting or r.pending ~= lastRest.pending then
		lastRest = r
		ClientBus.fire("rest", r)
	end
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	rest = Rest.new()
	restFocus.Enabled = false
	knockUntil = nil
	sentPause = false
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

local function liveRoom(): boolean
	return where == "room" and st ~= nil and st.state == "live"
end

-- REVIEW-1 A4: after a re-dress the next pause waits for Pause.EverySeconds of clock (the server refuses it too)
local function pauseWait(): number
	if st == nil then return 0 end
	local left = (st.pauseIn or 0) - (if st.state == "live" then now - stateAt else 0)
	return math.max(0, left)
end
local function sayPauseSoon()
	ClientBus.fire("toast", string.format(Config.Text.PauseSoon, math.max(1, math.ceil(pauseWait()))))
end

ClientBus.on("pausePressed", function()
	if not restOn then return end
	if not liveRoom() then
		ClientBus.fire("toast", if st and st.state == "intro" then Config.Text.GetReady else Config.Text.NotInRoom)
		return
	end
	if pauseWait() > 1e-6 then
		sayPauseSoon()
		return
	end
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = groundedNow(), threat = scheduler.active ~= nil })
	if result == "resting" then
		restFocus.Enabled = true
		sentPause = true
		PauseEv:FireServer()
	end
	postRest()
end)
ClientBus.on("resumePressed", function()
	if restOn then Rest.stop(rest) end
	restFocus.Enabled = false
	postRest()
	if sentPause or (st and st.state == "paused") then
		sentPause = false
		ResumeEv:FireServer()
	end
end)

local function legalSpot(lx: number, lz: number): boolean
	if payload == nil then return false end
	local inset = W.LegalInset
	if math.abs(lx) > payload.W / 2 - inset or lz < inset or lz > payload.D - inset then return false end
	local mz = Room.MatDepth / 2
	return math.sqrt(lx * lx + (lz - mz) ^ 2) > inset + mz
end

local function frame(dt: number)
	now += dt
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	-- the band: progress = the chapter you are in; the hub keeps its own look
	local inRoom = where == "room" and payload ~= nil and st ~= nil
	local p = if inRoom then (st.progress or 0) else nil
	local bandIdx = if p ~= nil then EnvBands.indexAt(bands, p) else nil
	if bandsOn then
		lightAccum += dt
		if current == nil or lightAccum >= 1 / Env.LightingHz then
			local step = lightAccum
			lightAccum = 0
			if current == nil then
				current = {}
				for _, g in GROUPS do (current :: any)[g] = EnvBands.approachTable(nil, Env.Hub[g] or {}, 0, Env.HalfLife) end
			end
			local cur = current :: any
			for _, g in GROUPS do
				local target = if p ~= nil then EnvBands.sample(bands, p, g) else Env.Hub[g] or {}
				cur[g] = EnvBands.approachTable(cur[g], target, step, Env.HalfLife)
				writeGroup(targets[g], cur[g])
			end
		end
	end
	updateCritters(bandIdx)
	updateWeather(bandIdx)
	updateLightning(bandIdx)

	if hrp == nil or hum == nil then return end
	local root = hrp :: BasePart
	local humanoid = hum :: Humanoid
	if knockUntil and now >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end
	local grounded = groundedNow()
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true

	-- the Pause: Rest.luau decides; the server is told when it starts and when a move ends it
	if restOn then
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = grounded, threat = scheduler.active ~= nil })
		if ev == "started" then
			if liveRoom() and pauseWait() > 1e-6 then
				-- a pause queued behind a drop, but the window after the last re-dress is not over: no rest
				Rest.stop(rest)
				sayPauseSoon()
			else
				restFocus.Enabled = true
				if liveRoom() then
					sentPause = true
					PauseEv:FireServer()
				end
			end
		elseif ev == "woke" then
			restFocus.Enabled = false
			if sentPause then
				sentPause = false
				ResumeEv:FireServer()
			end
		elseif ev == "dropped" or ev == "expired" then
			restFocus.Enabled = false
		end
		if not liveRoom() and not (st and st.state == "paused") and Rest.isResting(rest) then
			Rest.stop(rest)
			restFocus.Enabled = false
			sentPause = false
		end
		-- the server refused the pause (its answer: still live, nothing queued, a wait left): stop resting here too
		if sentPause and liveRoom() and st and not st.pauseQueued and (st.pauseIn or 0) > 1e-6 then
			Rest.stop(rest)
			restFocus.Enabled = false
			sentPause = false
		end
		postRest()
	end
	local resting = restOn and (Rest.isResting(rest) or (st ~= nil and st.state == "paused"))

	-- hazards: exposed only on a legal spot of a live room, past the arrival grace
	if hazardsOn then
		local pos = root.Position
		local loc = pos - origin
		local releasable = inRoom and liveRoom() and legalSpot(loc.X, loc.Z) and (now - arrivedAt) >= W.ArrivalGrace
		local look = camera.CFrame.LookVector
		local before = if scheduler.active then scheduler.active.t else nil
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting or not releasable,
			grounded = grounded,
			kinds = if inRoom and bandIdx then (bands[bandIdx].hazards or {}) else {},
			aim = { x = pos.X, y = pos.Y, z = pos.Z },
			yaw = math.atan2(look.X, look.Z),
			pitch = math.rad(Hz.PitchDegrees), -- ALWAYS 85 degrees: straight down from the ceiling
		}, rand)
		if ev and ev.type == "spawn" then hazardStats.launched += 1 end
		if ev and ev.type == "done" then hideHazard() end
		local plan = scheduler.active
		local text, clear, active = nil, false, false
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			showHazard(plan, hp, if live then Hazards.zone(plan, Hz.PlayerRadius) else nil)
			if Hazards.checkHit(plan, before or 0, plan.t, { x = pos.X, y = pos.Y, z = pos.Z }, Hz.PlayerRadius) then
				plan.hit = true
				hazardStats.hits += 1
				local kv = Hazards.knockVelocity(Hz, plan, { x = pos.X, y = pos.Y, z = pos.Z })
				pcall(function() humanoid.PlatformStand = true end)
				root.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
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
	-- the selection's reach label follows the walk
	if selectedId and propById[selectedId] then
		local ir = inReach(propById[selectedId])
		if ir ~= selectedInReach then
			selectedInReach = ir
			ClientBus.fire("select", { id = selectedId, label = Clue.label(propById[selectedId], Config), inReach = ir })
		end
	end
end

-- read by the headless checks (never a secret: counts of this client's own local parts and events)
ClientBus.on("__stats", function(out: any)
	if type(out) ~= "table" then return end
	out.parts = localCount
	out.lights = lightCount
	out.emitters = emitterCount
	out.peakParts = stats.peakParts
	out.refusedParts = stats.refusedParts
	out.refusedLights = stats.refusedLights
	out.refusedEmitters = stats.refusedEmitters
	out.lightingWrites = lightingWrites
	out.hazards = hazardStats.launched
	out.hits = hazardStats.hits
	out.scheduler = scheduler
	out.rest = rest
	out.weatherOn = weatherOn
	out.weather = weatherHosts -- { host, emitter, kind } per weather emitter (where the rain runs: REVIEW-1 round 2 D2)
	out.lightning = lightning.count
	out.restFocus = restFocus.Enabled
	out.selectedId = selectedId
	out.hintId = hintId
	out.origin = origin
end)

RunService.RenderStepped:Connect(function(dt: number)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken frame must not flood the output
		warn("[FindItRoom] frame error: " .. tostring(err))
	end
end)
