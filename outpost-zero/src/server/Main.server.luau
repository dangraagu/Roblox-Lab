-- OUTPOST ZERO: SKY CITY TYCOON — the authoritative server (ServerScriptService).
--
-- Six rock shelves float on a ring above the clouds, one per player. You build Homes (settlers) and Workshops (jobs)
-- on lots by pressing their sign posts' ProximityPrompts; population = min(settlers, jobs) earns 0.25 credits a
-- second each while the workers' Orders run (10 minutes after your last build). Districts open at population
-- milestones; the Skyport brings the Grand Airship (the brag). DESIGN.md is the spec; every number is in Config.
--
-- What the server owns, and why nothing a client says can inflate the Census:
--   * there is NO client -> server remote. Every action is a server-side ProximityPrompt.Triggered: the lot prompts
--     and the Census board's toggle. Each press is checked for shelf ownership, an open district, the storey cap,
--     8 presses/s and the server's own credits against the server's own price, and every refusal answers;
--   * credits are minted only here, by tick() x the population this file computed x the wage, while this file's
--     Orders run (or under the safety net); Orders are renewed only by a purchase. The one other source: a saved
--     city with nobody in it and too few credits to get anyone is lifted to exactly that price, once, at the join
--     (REVIEW-1 F5; canBuy keeps every live city above it, so only a record saved before that rule can need it);
--   * the layout seed is drawn here (Random.new()) and lives only in the profile and ServerStorage.CityInfo, and
--     every layout has the same lots and prices, so knowing it buys nothing (DESIGN 10.3).
-- Nothing secret replicates: no attribute is set on anything under workspace or ReplicatedStorage.
--
-- Spawn (robloxemu/SPAWN-ORDER.md, the preferred pattern): every shelf's arrival pad is a real enabled SpawnLocation
-- built before anyone joins; PlayerAdded sets plr.RespawnLocation synchronously, before any yield; CharacterAdded
-- only waits (bounded) and corrects a character the engine put somewhere else.
--
-- Saving: one UpdateAsync load that takes the lock with a fresh owner token; every later write lands only while the
-- record still carries that token (fork-tower REVIEW-4 §10). canSave only while holding the lock. credits and
-- savedAt always travel together, so offline earnings are paid once. No one-time grants exist in v1.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService") -- GenerateGUID only (session tokens); no HTTP
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local City = require(ReplicatedStorage:WaitForChild("City"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local Save = require(ReplicatedStorage:WaitForChild("Save"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

-- The look, first thing: a foggy dawn, equal to band 1, so every client's first blend takes over with no jump.
Fx.applyLighting(Fx.Presets.Dawn)

local W, SH, LT, E = Config.World, Config.Shelf, Config.Lots, Config.Economy
local Palette = Config.Palette
local MAX_STOREYS = E.MaxStoreys

-- tick() is the in-session clock (robloxemu advances it; os.clock barely moves headless). os.time() for everything
-- persisted.
local function now(): number
	return tick()
end

local rng = Random.new()

local function c3(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis is X; this stands it up

local function makePart(props: { [string]: any }): BasePart
	local p = Instance.new(props.class or "Part")
	p.Name = props.name
	p.Anchored = true
	p.CanCollide = props.collide == true
	p.CanTouch = false
	p.CanQuery = props.collide == true
	p.CastShadow = props.shadow == true
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Color = props.color or Color3.fromRGB(200, 200, 200)
	-- Roblox forces a Ball's Size uniform: a stretched sphere (the airship's 44 x 14 x 14 envelope) is a Block whose
	-- Sphere SpecialMesh fills the box (round 2, B1). A uniform Ball stays a Ball.
	local s = props.size :: Vector3
	if props.shape == Enum.PartType.Ball and (math.abs(s.X - s.Y) > 1e-6 or math.abs(s.Y - s.Z) > 1e-6) then
		local mesh = Instance.new("SpecialMesh")
		mesh.Name = "EllipsoidMesh"
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif props.shape then
		(p :: Part).Shape = props.shape
	end
	p.Size = s
	p.CFrame = props.cf
	p.Transparency = props.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.parent then p.Parent = props.parent end
	return p
end

local function billboardText(parent: Instance, name: string, text: string, size: UDim2, offset: Vector3, colour: Color3, maxDistance: number): TextLabel
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = size
	bb.StudsOffset = offset
	bb.MaxDistance = maxDistance
	bb.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = colour
	t.TextStrokeTransparency = 0.4
	t.Text = text
	t.Parent = bb
	bb.Parent = parent
	return t
end

--============================================================================ remotes (server -> client only)
local remotes = Instance.new("Folder")
remotes.Name = "CityRemotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local StateR = remote("State") -- server -> owner: their own present state
local ToastR = remote("Toast") -- server -> one player: a sentence
local FxR = remote("Fx") -- server -> owner: a build, a new district, the airship, the complete skyline
local BoardR = remote("Board") -- server -> viewer: their own Census view
local AnnounceR = remote("Announce") -- server -> all: the airship's flight, the public toasts
remotes.Parent = ReplicatedStorage

--============================================================================ stores (all pcall'd)
-- GetDataStore raises in an unpublished place; unwrapped, it kills this script.
local store: any = nil
local boardStore: any = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(Config.Save.Store)
	end)
	if ok then store = s else warn("[OutpostZero] DataStore unavailable; progress will not be saved: " .. tostring(s)) end
	local okB, b = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Board.Store)
	end)
	if okB then boardStore = b else warn("[OutpostZero] Census store unavailable: " .. tostring(b)) end
end
local function key(userId: number): string
	return "u_" .. tostring(userId)
end

--============================================================================ ServerStorage: the kit and the debug folder
local kit = Instance.new("Folder")
kit.Name = "CityKit"
kit.Parent = ServerStorage
local cityInfoRoot = Instance.new("Folder")
cityInfoRoot.Name = "CityInfo" -- debug values for headless checks and tools; never replicated
cityInfoRoot.Parent = ServerStorage

-- The Grand Airship, 12 parts, built once into the kit and cloned per mooring. Model-local: the gondola's bottom
-- is at y = 0, the envelope points along +X.
do
	local m = Instance.new("Model")
	m.Name = "Airship"
	local hull, trim = c3(Palette.AirshipHull), c3(Palette.AirshipTrim)
	local gy, ey = Config.Airship.GondolaY, 3 + 7
	makePart({ name = "Gondola", size = Vector3.new(12, 3, 4), cf = CFrame.new(0, gy, 0), material = Enum.Material.Wood, color = c3(Palette.AirshipGondola), parent = m })
	makePart({ name = "GondolaWindows", size = Vector3.new(10, 0.8, 4.1), cf = CFrame.new(0, gy + 0.3, 0), material = Enum.Material.Neon, color = c3(Palette.AirshipLamp), parent = m })
	makePart({ name = "Envelope", shape = Enum.PartType.Ball, size = Vector3.new(44, 14, 14), cf = CFrame.new(0, ey, 0), material = Enum.Material.Fabric, color = hull, parent = m })
	makePart({ name = "BandFore", shape = Enum.PartType.Cylinder, size = Vector3.new(1.2, 14.4, 14.4), cf = CFrame.new(10, ey, 0), material = Enum.Material.Fabric, color = trim, parent = m })
	makePart({ name = "BandAft", shape = Enum.PartType.Cylinder, size = Vector3.new(1.2, 14.4, 14.4), cf = CFrame.new(-10, ey, 0), material = Enum.Material.Fabric, color = trim, parent = m })
	makePart({ name = "FinTop", size = Vector3.new(6, 6, 0.4), cf = CFrame.new(-20, ey + 6, 0), material = Enum.Material.Fabric, color = trim, parent = m })
	makePart({ name = "FinBottom", size = Vector3.new(6, 6, 0.4), cf = CFrame.new(-20, ey - 6, 0), material = Enum.Material.Fabric, color = trim, parent = m })
	makePart({ name = "FinLeft", size = Vector3.new(6, 0.4, 6), cf = CFrame.new(-20, ey, -6), material = Enum.Material.Fabric, color = trim, parent = m })
	makePart({ name = "FinRight", size = Vector3.new(6, 0.4, 6), cf = CFrame.new(-20, ey, 6), material = Enum.Material.Fabric, color = trim, parent = m })
	makePart({ name = "PropellerL", size = Vector3.new(0.4, 4, 0.6), cf = CFrame.new(-7, gy + 1, -3), material = Enum.Material.Metal, color = trim, parent = m })
	makePart({ name = "PropellerR", size = Vector3.new(0.4, 4, 0.6), cf = CFrame.new(-7, gy + 1, 3), material = Enum.Material.Metal, color = trim, parent = m })
	local lamp = makePart({ name = "Lamp", shape = Enum.PartType.Ball, size = Vector3.new(1.6, 1.6, 1.6), cf = CFrame.new(6.5, gy, 0), material = Enum.Material.Neon, color = c3(Palette.AirshipLamp), parent = m })
	Fx.attachGlow(lamp, c3(Palette.AirshipLamp), 1.6, 24) -- the gold glow on the gondola lamp
	m.PrimaryPart = m:FindFirstChild("Gondola") :: BasePart
	m.Parent = kit
end

--============================================================================ the world: six shelves
local shelvesFolder = Instance.new("Folder")
shelvesFolder.Name = "Shelves"

local shelves = {}

local function buildShelf(k: number)
	local cx, cz = City.shelfCentre(Config, k)
	-- local -Z faces the ring's centre (City.toWorld is the same frame)
	local cf = CFrame.lookAt(Vector3.new(cx, 0, cz), Vector3.new(0, 0, 0))
	local function at(lx: number, ly: number, lz: number, yaw: number?): CFrame
		return cf * CFrame.new(lx, ly, lz) * CFrame.Angles(0, yaw or 0, 0)
	end
	local model = Instance.new("Model")
	model.Name = "Shelf_" .. k

	local R = W.ShelfRadius
	makePart({ name = "Rock", shape = Enum.PartType.Cylinder, size = Vector3.new(W.RockThickness, 2 * R, 2 * R),
		cf = at(0, -W.RockThickness / 2, 0) * UPRIGHT, material = Enum.Material.Rock, color = c3(Palette.Rock), collide = true, parent = model })
	makePart({ name = "Plaza", shape = Enum.PartType.Cylinder, size = Vector3.new(0.2, 2 * SH.PlazaRadius, 2 * SH.PlazaRadius),
		cf = at(0, 0.1, 0) * UPRIGHT, material = Enum.Material.Pavement, color = c3(Palette.Plaza), collide = true, parent = model })

	-- the parapet: 16 chords, a stone wall and invisible collidable glass up to 12 studs
	local parapet = Instance.new("Model")
	parapet.Name = "Parapet"
	local n = W.ParapetSegments
	local chord = 2 * W.RailRadius * math.sin(math.pi / n)
	local mid = W.RailRadius * math.cos(math.pi / n)
	for i = 1, n do
		local a = (i - 0.5) / n * math.pi * 2
		local yaw = a
		local lx, lz = math.sin(a) * mid, math.cos(a) * mid
		makePart({ name = "Wall_" .. i, size = Vector3.new(chord, W.WallHeight, 1), cf = at(lx, W.WallHeight / 2, lz, yaw),
			material = Enum.Material.Cobblestone, color = c3(Palette.Wall), collide = true, parent = parapet })
		makePart({ name = "Glass_" .. i, size = Vector3.new(chord, W.GlassHeight, 0.4), cf = at(lx, W.GlassHeight / 2, lz, yaw),
			material = Enum.Material.Glass, color = c3(Palette.Glass), transparency = 1, collide = true, parent = parapet })
	end
	parapet.Parent = model

	-- the Town Hall: the base hut (5 parts) and a light; districts add their pieces (hallPiece)
	local hall = Instance.new("Model")
	hall.Name = "TownHall"
	local body = makePart({ name = "HallBody", size = Vector3.new(10, 6, 10), cf = at(0, 3, 0), material = Enum.Material.WoodPlanks,
		color = c3(Palette.HallWood), collide = true, parent = hall })
	makePart({ class = "WedgePart", name = "HallRoofL", size = Vector3.new(11, 3, 5.5), cf = at(0, 7.5, -2.75, math.pi), material = Enum.Material.Fabric,
		color = c3(Palette.HallCanvas), collide = true, parent = hall })
	makePart({ class = "WedgePart", name = "HallRoofR", size = Vector3.new(11, 3, 5.5), cf = at(0, 7.5, 2.75), material = Enum.Material.Fabric,
		color = c3(Palette.HallCanvas), collide = true, parent = hall })
	makePart({ name = "WindsockMast", shape = Enum.PartType.Cylinder, size = Vector3.new(8, 0.4, 0.4), cf = at(4, 10, 4) * UPRIGHT,
		material = Enum.Material.Wood, color = c3(Palette.Post), parent = hall })
	makePart({ name = "Windsock", size = Vector3.new(2.4, 0.8, 0.8), cf = at(5.2, 13.4, 4), material = Enum.Material.Fabric,
		color = c3(Palette.Windsock), parent = hall })
	local light = Instance.new("PointLight")
	light.Name = "HallLight"
	light.Color = c3(Palette.HallLight)
	light.Range = 24
	light.Brightness = 1.2
	light.Enabled = true
	light.Parent = body
	local ownerSign = billboardText(body, "OwnerSign", "Free shelf", UDim2.fromOffset(240, 46), Vector3.new(0, 12, 0), Color3.fromRGB(255, 255, 255), 400)
	hall.Parent = model

	-- the arrival pad: a real, enabled SpawnLocation, facing district 1 (-Z)
	local pad = Instance.new("SpawnLocation")
	pad.Name = "Arrival"
	pad.Anchored = true
	pad.CanCollide = true
	pad.Enabled = true
	pad.Neutral = true
	pad.Duration = 0 -- no force-field bubble (needs-Studio: confirm it removes it)
	pad.Size = Vector3.new(SH.ArrivalSize, 1, SH.ArrivalSize)
	pad.CFrame = at(SH.Arrival.x, SH.ArrivalTopY - 0.5, SH.Arrival.z)
	pad.Material = Enum.Material.Marble
	pad.Color = c3(Palette.Arrival)
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Parent = model

	-- the Census board beside the pad, facing it
	local boardModel = Instance.new("Model")
	boardModel.Name = "Board"
	local boardPos = at(SH.Board.x, 4.5, SH.Board.z).Position
	local padPos = at(SH.Arrival.x, 4.5, SH.Arrival.z).Position
	local facing = CFrame.lookAt(boardPos, padPos)
	local frame = makePart({ name = "BoardFrame", size = Vector3.new(9, 8.4, 0.6), cf = facing * CFrame.new(0, 0.5, 0.35), material = Enum.Material.Wood,
		color = c3(Palette.BoardFrame), collide = true, parent = boardModel })
	local face = makePart({ name = "BoardFace", size = Vector3.new(8, 6, 0.2), cf = facing * CFrame.new(0, -0.4, 0), material = Enum.Material.SmoothPlastic,
		color = c3(Palette.BoardFace), parent = boardModel })
	local plate = Instance.new("SurfaceGui")
	plate.Name = "TitlePlate"
	plate.Face = Enum.NormalId.Front
	plate.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plate.PixelsPerStud = 40
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.14)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = c3(Palette.CrownGold)
	title.Text = "📊 CENSUS"
	title.Parent = plate
	plate.Parent = frame
	local boardPrompt = Instance.new("ProximityPrompt")
	boardPrompt.Name = "CensusPrompt"
	boardPrompt.ObjectText = "📊 Census"
	boardPrompt.ActionText = "Switch Public / Friends"
	boardPrompt.MaxActivationDistance = Config.Board.PromptDistance
	boardPrompt.HoldDuration = 0
	boardPrompt.RequiresLineOfSight = false
	boardPrompt.Parent = face
	boardModel.Parent = model

	local lotsFolder = Instance.new("Folder")
	lotsFolder.Name = "Lots"
	lotsFolder.Parent = model
	local signsFolder = Instance.new("Folder")
	signsFolder.Name = "Signs"
	signsFolder.Parent = model

	model.Parent = shelvesFolder
	shelves[k] = {
		k = k,
		cf = cf,
		at = at,
		model = model,
		arrival = pad,
		hall = hall,
		hallBody = body,
		ownerSign = ownerSign,
		boardFace = face,
		title = title,
		prompt = boardPrompt,
		lotsFolder = lotsFolder,
		signsFolder = signsFolder,
		owner = nil :: Player?,
		lots = {} :: { [string]: any },
		airship = nil :: Model?,
		beam = nil :: Beam?,
	}
end

for k = 1, W.Shelves do
	buildShelf(k)
end
shelvesFolder.Parent = workspace -- every shelf, with its SpawnLocation, exists before anyone can join

--============================================================================ sessions
type Session = any
local sessions: { [Player]: Session } = {}
-- userId -> leave-writes in flight on THIS server. A rejoin to this server waits for them before it loads (round 2,
-- A1): the lock rule treats this server's own JobId as free, so loading first would cancel the leave-write.
local leaveWrites: { [number]: number } = {}

local function toast(plr: Player, text: string)
	ToastR:FireClient(plr, text)
end
local function toastEvery(s: Session, reason: string, every: number, text: string)
	local t = now()
	if t - (s.toastAt[reason] or -math.huge) >= every then
		s.toastAt[reason] = t
		toast(s.plr, text)
	end
end

-- Roblox always gives a DisplayName; fall back to Name so a missing one can never break a sentence.
local function displayName(plr: Player): string
	local dn = (plr :: any).DisplayName
	if type(dn) ~= "string" or dn == "" then return plr.Name end
	return dn
end

--============================================================================ the city's parts
local function storeysOf(s: Session, lotKey: string): number
	return s.data.lots[lotKey] or 0
end

-- A building's three parts (body, roof, window strip) for `storeys`, in the lot's own frame.
local function buildingCFrames(shelf: any, l: any, storeys: number): (Vector3, CFrame, Vector3, CFrame, Vector3, CFrame)
	local yaw = math.atan2(l.x, l.z) -- local -Z toward the shelf centre
	local h = storeys * LT.StoreyHeight
	local base = LT.PlateHeight
	local bodySize = Vector3.new(LT.BodySize, h, LT.BodySize)
	local bodyCf = shelf.at(l.x, base + h / 2, l.z, yaw)
	local style = Config.Districts[l.d].roof
	local roofSize, roofCf
	local top = base + h
	if style == "pitched" then
		roofSize = Vector3.new(LT.BodySize, LT.RoofHeight, LT.BodySize)
		roofCf = shelf.at(l.x, top + LT.RoofHeight / 2, l.z, yaw)
	elseif style == "awning" then
		roofSize = Vector3.new(LT.BodySize + 1, 0.5, LT.BodySize + 1)
		roofCf = shelf.at(l.x, top + 0.25, l.z, yaw)
	elseif style == "sawtooth" then
		roofSize = Vector3.new(LT.BodySize, LT.RoofHeight, LT.BodySize)
		roofCf = shelf.at(l.x, top + LT.RoofHeight / 2, l.z, yaw + math.pi / 2)
	elseif style == "mast" then
		roofSize = Vector3.new(0.6, LT.RoofHeight * 2, 0.6)
		roofCf = shelf.at(l.x, top + LT.RoofHeight, l.z, yaw)
	elseif style == "dome" then
		-- a uniform sphere (Roblox draws a Ball only uniform: round 2, B1), sunk so that only a cap shows: 3 studs
		-- tall over a 6.9-stud circle; the rest is hidden inside the 8-stud body, and the cap is the collision too
		local r = (LT.BodySize - 1) / 2
		roofSize = Vector3.new(2 * r, 2 * r, 2 * r)
		roofCf = shelf.at(l.x, top + LT.RoofHeight * 1.5 - r, l.z, yaw)
	else -- spire
		roofSize = Vector3.new(1.6, LT.RoofHeight * 2, 1.6)
		roofCf = shelf.at(l.x, top + LT.RoofHeight, l.z, yaw + math.pi / 4)
	end
	-- the window strip: Neon, on the street-facing side
	local stripH = math.max(0.5, h - 1.2)
	local stripSize = Vector3.new(LT.BodySize * 0.5, stripH, 0.2)
	local stripCf = shelf.at(l.x, base + 0.6 + stripH / 2, l.z, yaw) * CFrame.new(0, 0, -LT.BodySize / 2 - 0.1)
	return bodySize, bodyCf, roofSize, roofCf, stripSize, stripCf
end

local function roofShape(style: string): (string, any)
	if style == "pitched" or style == "sawtooth" then return "WedgePart", nil end
	if style == "dome" then return "Part", Enum.PartType.Ball end
	return "Part", nil
end

local function updatePrompt(s: Session, lot: any)
	local st = s.st
	local prompt = lot.prompt
	local storeys = storeysOf(s, lot.l.key)
	prompt.ActionText = Economy.actionText(Config, st, lot.l.key)
	prompt.ObjectText = Economy.objectText(Config, st, lot.l.key)
	local topped = storeys >= MAX_STOREYS
	prompt.Enabled = not topped
	if topped and lot.toppedSign == nil then
		lot.toppedSign = billboardText(lot.post, "Topped", MAX_STOREYS .. "/" .. MAX_STOREYS .. " Topped out", UDim2.fromOffset(150, 32),
			Vector3.new(0, 3.5, 0), c3(Palette.Topped), 80)
	end
end

-- Raise or rebuild a lot's building to its saved storeys. `grow`: tween from the old height (a purchase).
local function setBuilding(s: Session, lot: any, grow: boolean)
	local shelf, l = s.shelf, lot.l
	local storeys = storeysOf(s, l.key)
	if storeys <= 0 then return end
	local dist = Config.Districts[l.d]
	local bodySize, bodyCf, roofSize, roofCf, stripSize, stripCf = buildingCFrames(shelf, l, storeys)
	if lot.body == nil then
		local oldSize, oldCf = bodySize, bodyCf
		if grow then
			oldSize = Vector3.new(bodySize.X, 0.2, bodySize.Z)
			oldCf = shelf.at(l.x, LT.PlateHeight + 0.1, l.z, math.atan2(l.x, l.z))
		end
		lot.body = makePart({ name = "Body", size = oldSize, cf = oldCf, material = Enum.Material.SmoothPlastic,
			color = c3(dist.palette[l.facade]), collide = true, parent = lot.model })
		local cls, shape = roofShape(dist.roof)
		lot.roof = makePart({ class = cls, name = "Roof", shape = shape, size = roofSize, cf = roofCf,
			material = if dist.roof == "spire" or dist.roof == "mast" then Enum.Material.Metal else Enum.Material.Fabric,
			color = c3(dist.roofColor), collide = dist.roof ~= "mast" and dist.roof ~= "spire", parent = lot.model })
		lot.strip = makePart({ name = "Windows", size = stripSize, cf = stripCf, material = Enum.Material.Neon,
			color = c3(dist.window), parent = lot.model })
	end
	if grow then
		local info = TweenInfo.new(LT.GrowSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(lot.body, info, { Size = bodySize, CFrame = bodyCf }):Play()
		TweenService:Create(lot.roof, info, { CFrame = roofCf }):Play()
		TweenService:Create(lot.strip, info, { Size = stripSize, CFrame = stripCf }):Play()
		-- the construction puff (signature particles), gone after a second
		local puff = Fx.sparkle(lot.body, c3(dist.window))
		puff.Rate = 40
		task.delay(1, function()
			if puff.Parent then puff:Destroy() end
		end)
	else
		lot.body.Size = bodySize
		lot.body.CFrame = bodyCf
		lot.roof.Size = roofSize
		lot.roof.CFrame = roofCf
		lot.strip.Size = stripSize
		lot.strip.CFrame = stripCf
	end
end

local onLotPrompt: (Player, any, string) -> ()

local function buildLot(s: Session, l: any)
	local shelf = s.shelf
	if shelf.lots[l.key] then return end
	local dist = Config.Districts[l.d]
	local model = Instance.new("Model")
	model.Name = "Lot_" .. l.key -- a visible fact: district and lot number
	local yaw = math.atan2(l.x, l.z)
	makePart({ name = "Plate", size = Vector3.new(LT.Size, LT.PlateHeight, LT.Size), cf = shelf.at(l.x, LT.PlateHeight / 2, l.z, yaw),
		material = Enum.Material.Concrete, color = c3(dist.paving), collide = true, parent = model })
	local px, pz = City.postXZ(Config, l)
	local post = makePart({ name = "Post", size = Vector3.new(0.6, LT.PostHeight, 0.6), cf = shelf.at(px, LT.PostHeight / 2, pz, yaw),
		material = Enum.Material.Wood, color = c3(Palette.Post), collide = true, parent = model })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuildPrompt"
	prompt.MaxActivationDistance = LT.PromptDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = post
	local lot = { l = l, model = model, post = post, prompt = prompt, body = nil, roof = nil, strip = nil, toppedSign = nil }
	shelf.lots[l.key] = lot
	prompt.Triggered:Connect(function(plr: Player)
		onLotPrompt(plr, shelf, l.key)
	end)
	model.Parent = shelf.lotsFolder
	setBuilding(s, lot, false)
	updatePrompt(s, lot)
end

local HALL_PIECES = {
	clock = function(shelf: any)
		return makePart({ name = "Clock", shape = Enum.PartType.Cylinder, size = Vector3.new(0.3, 3.4, 3.4),
			cf = shelf.at(0, 4.2, -5.2) * CFrame.Angles(0, math.rad(90), 0), material = Enum.Material.Neon, color = c3(Palette.Clock), parent = shelf.hall })
	end,
	canopy = function(shelf: any)
		return makePart({ name = "Canopy", size = Vector3.new(12, 0.4, 4), cf = shelf.at(0, 6.2, -7) * CFrame.Angles(math.rad(-12), 0, 0),
			material = Enum.Material.CorrodedMetal, color = c3(Palette.Canopy), parent = shelf.hall })
	end,
	mast = function(shelf: any)
		local h = Config.Airship.HullBottomY - 9
		return makePart({ name = "MooringMast", shape = Enum.PartType.Cylinder, size = Vector3.new(h, 1.2, 1.2),
			cf = shelf.at(0, 9 + h / 2, 0) * UPRIGHT, material = Enum.Material.Metal, color = c3(Palette.Mast), parent = shelf.hall })
	end,
	halo = function(shelf: any)
		return makePart({ name = "Halo", shape = Enum.PartType.Cylinder, size = Vector3.new(0.4, 16, 16),
			cf = shelf.at(0, 12, 0) * UPRIGHT, material = Enum.Material.Neon, color = c3(Palette.Halo), transparency = 0.45, parent = shelf.hall })
	end,
	spire = function(shelf: any)
		return makePart({ name = "Spire", size = Vector3.new(2, 14, 2), cf = shelf.at(0, 16, 0) * CFrame.Angles(0, math.rad(45), 0),
			material = Enum.Material.Metal, color = c3(Palette.CrownGold), parent = shelf.hall })
	end,
}
local HALL_NAMES = { clock = "Clock", canopy = "Canopy", mast = "MooringMast", halo = "Halo", spire = "Spire" }

local function addHallPiece(shelf: any, d: number)
	local which = Config.Districts[d].hall
	local build = HALL_PIECES[which]
	if build == nil then return end -- district 1's hut is the base
	if shelf.hall:FindFirstChild(HALL_NAMES[which]) then return end
	build(shelf)
end

local function buildSign(s: Session, d: number)
	local shelf = s.shelf
	local slot = s.layout.slotOf[d]
	local sx, sz = City.signXZ(Config, slot)
	local yaw = math.atan2(sx, sz)
	local sign = makePart({ name = "Sign_" .. d, size = Vector3.new(7, 4, 0.6), cf = shelf.at(sx, 3, sz, yaw), material = Enum.Material.Wood,
		color = c3(Palette.Sign), collide = true, parent = shelf.signsFolder })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(40, 36, 30)
	local dist = Config.Districts[d]
	t.Text = string.format("%s opens at population %s", dist.name, Economy.group(dist.open))
	t.Parent = gui
	gui.Parent = sign
end

-- The moored pose: the gondola (the model's pivot) at the hull line over the Town Hall's mast, nose along the shelf's
-- +X. The client's flying copy ends in exactly this pose (round 2, B2; check_outpostzero_handover).
local function airshipDock(shelf: any): CFrame
	return shelf.at(0, Config.Airship.HullBottomY + Config.Airship.GondolaY, 0)
end

local function placeAirship(shelf: any)
	if shelf.airship then return end
	local m = (kit:FindFirstChild("Airship") :: Model):Clone()
	m:PivotTo(airshipDock(shelf))
	m.Parent = shelf.model
	shelf.airship = m
end

local function setCrownBeam(shelf: any, on: boolean)
	local spire = shelf.hall:FindFirstChild("Spire")
	if on and spire and shelf.beam == nil then
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamBase"
		a0.Parent = spire
		local a1 = Instance.new("Attachment")
		a1.Name = "BeamTop"
		a1.Position = Vector3.new(0, 200, 0)
		a1.Parent = spire
		local beam = Instance.new("Beam")
		beam.Name = "CrownBeam"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(c3(Palette.CrownGold))
		beam.Width0 = 3
		beam.Width1 = 1
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = spire
		shelf.beam = beam
	end
end

-- Everything the city shows for the districts open at its population (idempotent).
local function syncDistricts(s: Session)
	local open = Economy.districtsOpen(Config, s.st.pop)
	for d = 2, open do
		local sign = s.shelf.signsFolder:FindFirstChild("Sign_" .. d)
		if sign then sign:Destroy() end
		addHallPiece(s.shelf, d)
	end
	for _, l in s.layout.lots do
		if l.d <= open then buildLot(s, l) end
	end
	s.openShown = open
end

local function resetShelf(shelf: any)
	for _, lot in shelf.lots do
		lot.model:Destroy()
	end
	shelf.lots = {}
	for _, c in shelf.signsFolder:GetChildren() do c:Destroy() end
	for _, name in HALL_NAMES do
		local p = shelf.hall:FindFirstChild(name)
		if p then p:Destroy() end
	end
	if shelf.airship then
		shelf.airship:Destroy()
		shelf.airship = nil
	end
	shelf.beam = nil
	shelf.ownerSign.Text = "Free shelf"
	shelf.title.Text = "📊 CENSUS"
end

--============================================================================ the economy, on the server's clock
-- Bring credits up to `t` by the game's rule (Orders, then the safety net), and remember what was minted.
local function settle(s: Session)
	local t = now()
	local st = s.st
	local before = st.credits
	local credits, _, net = Economy.earn(Config, st.credits, st.income, s.lastEarn, t, s.ordersUntil, Economy.cheapest(Config, st))
	st.credits = credits
	s.data.credits = credits
	local gain = credits - before
	if gain > 0 then
		s.data.lifetime += gain
		s.minted += gain
	end
	s.netNow = net > 0
	s.lastEarn = t
end

local function ordersLeft(s: Session): number
	return math.max(0, s.ordersUntil - now())
end

local function starOf(s: Session): any
	local char = s.plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lx, lz = SH.Arrival.x, SH.Arrival.z
	if hrp then
		lx, lz = City.toLocal(Config, s.shelf.k, hrp.Position.X, hrp.Position.Z)
	end
	return Economy.bestNext(Config, s.st, lx, lz)
end

local function airshipState(s: Session): (string, number)
	local a = s.airship
	if a == nil then return "none", 0 end
	if a.state == "flying" then return "flying", math.max(0, a.endsAt - now()) end
	if a.state == "pending" then return "pending", 0 end
	return "moored", math.max(0, (a.holdUntil or 0) - now())
end

local function pushState(s: Session, force: boolean?)
	local t = now()
	if not force and t - s.lastStateAt < E.StateSeconds then return end
	s.lastStateAt = t
	local st = s.st
	local pick = if s.loaded then starOf(s) else nil
	s.lastStarKey = pick and pick.key
	local left = ordersLeft(s)
	local cheapest = Economy.cheapest(Config, st)
	local working = left > 0 or (cheapest ~= nil and st.credits < cheapest and st.income > 0)
	local nd, nextAt = Economy.nextDistrict(Config, st.pop)
	local aState, aLeft = airshipState(s)
	StateR:FireClient(s.plr, {
		loaded = s.loaded,
		saving = s.canSave,
		lockedElsewhere = s.lockedElsewhere,
		lockChanged = s.lockChanged,
		shelf = s.shelf.k,
		credits = st.credits,
		lifetime = s.data.lifetime,
		income = st.income,
		rate = s.rateEma * 60,
		settlers = st.settlers,
		jobs = st.jobs,
		population = st.pop,
		ordersLeft = left,
		working = working,
		net = left <= 0 and working,
		cheapest = cheapest,
		star = if pick then {
			key = pick.key, d = pick.d, zone = pick.zone, storey = pick.storey, price = pick.price, wait = pick.wait,
			action = Economy.actionText(Config, st, pick.key),
		} else nil,
		tutorial = s.data.tutorial,
		districts = Economy.districtsOpen(Config, st.pop),
		nextDistrict = nd,
		nextAt = nextAt,
		airship = aState,
		airshipLeft = aLeft,
		complete = s.loaded and cheapest == nil,
	})
	if s.leader then s.leader.Value = st.pop end
end

--============================================================================ saving
-- Every write lands only while the record still carries this session's token. Writes are serialised per session
-- (meteor-drop-tycoon REVIEW-1): `waitTurn` waits for the write in flight; without it a write that finds one in
-- flight skips. `pending` is cleared before the yield and set again on failure.
local function writeProfile(s: Session, release: boolean, waitTurn: boolean?): boolean
	if store == nil or not s.canSave then return false end
	if s.writing then
		if not waitTurn then return false end
		local waited = 0
		while s.writing and waited < Config.Save.WriteQueueSeconds do
			task.wait(0.1)
			waited += 0.1
		end
		if s.writing or not s.canSave then return false end
	end
	if s.loaded then settle(s) end
	local d = s.data
	local t = os.time()
	d.savedAt = t -- credits and savedAt travel together, in this one write
	d.ordersUntil = t + math.floor(ordersLeft(s) + 0.5)
	local packed = Save.pack(d)
	-- the population that goes with `packed` (REVIEW-1 F1): a purchase that lands during the yield below changes
	-- s.st.pop but not the record this write saves, so the Census pair must be taken here, before the yield
	local packedPop = s.st.pop
	local lost = false
	s.pending = false
	s.writing = true
	local ok, err = pcall(function()
		store:UpdateAsync(key(s.plr.UserId), function(old)
			old = old or {}
			if old.session ~= s.token then
				lost = true
				return nil
			end
			lost = false
			old.data = packed
			old.jobId = game.JobId
			-- only the leave-write (release) frees the lock. A flush that was already in flight when the player left
			-- carries an older city; releasing here let another server load that city before the leave-write landed,
			-- and its new token then cancelled the leave-write (round 2, A1; check_outpostzero_latency E)
			old.lockUntil = if release then 0 else os.time() + Config.Save.LockSeconds
			return old
		end)
	end)
	s.writing = false
	if not ok then
		s.pending = true
		warn("[OutpostZero] save failed for " .. s.plr.Name .. ": " .. tostring(err))
		return false
	end
	if lost then
		s.canSave = false
		warn("[OutpostZero] " .. s.plr.Name .. ": a newer session owns this city; this session stops saving.")
		toast(s.plr, Config.Tutorial.NotSaving)
		pushState(s, true)
		return false
	end
	s.lastSave = now()
	s.savedPop = packedPop
	s.savedPopAt = packed.popAt
	return true
end

local function sameData(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in a do
		if not sameData(v, b[k]) then return false end
	end
	for k in b do
		if a[k] == nil then return false end
	end
	return true
end

local function releaseLock(userId: number, token: string)
	if store == nil then return end
	pcall(function()
		store:UpdateAsync(key(userId), function(old)
			if old == nil or old.session ~= token then return nil end
			old.lockUntil = 0
			return old
		end)
	end)
end

-- The load: tried LoadAttempts times (1 s, 2 s apart); a lock another server holds is re-read every
-- LockRetrySeconds for up to LockWaitSeconds; a record from a newer version is read but never locked or written.
local function load(s: Session)
	local plr = s.plr
	if store == nil then
		s.canSave = false
		return nil
	end
	-- the same player left THIS server a moment ago and their leave-write is still in flight: let it land first
	-- (bounded), so this load reads the city they left with and does not cancel that write (_latency F)
	local leftWait = 0
	while (leaveWrites[plr.UserId] or 0) > 0 and leftWait < Config.Save.RejoinWaitSeconds and not s.leaving do
		task.wait(0.1)
		leftWait += 0.1
	end
	local token = HttpService:GenerateGUID(false)
	local acquired, raw, lockedByOther, future = false, nil, false, false
	local ok = false
	local failures, waited = 0, 0
	while true do
		acquired, raw, lockedByOther, future = false, nil, false, false
		local err
		ok, err = pcall(function()
			store:UpdateAsync(key(plr.UserId), function(old)
				old = old or {}
				raw = old.data
				local t = os.time()
				-- the transform may run more than once: every flag is set on every run
				future = type(old.data) == "table" and type(old.data.v) == "number" and old.data.v > Save.VERSION
				if future then
					acquired = false
					lockedByOther = false
					return nil -- a newer game's record: never touched by this version
				end
				lockedByOther = (tonumber(old.lockUntil) or 0) > t and old.jobId ~= game.JobId
				if lockedByOther then
					acquired = false
					return nil
				end
				acquired = true
				old.session = token
				old.jobId = game.JobId
				old.lockUntil = t + Config.Save.LockSeconds
				return old
			end)
		end)
		if s.leaving then break end
		if ok then
			if not lockedByOther or waited >= Config.Save.LockWaitSeconds then break end
			if waited == 0 then toast(plr, Config.Tutorial.LockWaiting) end
			task.wait(Config.Save.LockRetrySeconds)
			waited += Config.Save.LockRetrySeconds
		else
			failures += 1
			warn(string.format("[OutpostZero] load failed for %s (attempt %d of %d): %s", plr.Name, failures, Config.Save.LoadAttempts, tostring(err)))
			if failures >= Config.Save.LoadAttempts then break end
			task.wait(Config.Save.LoadRetrySeconds * failures)
		end
		if s.leaving then break end
	end
	if s.leaving then
		if ok and acquired then releaseLock(plr.UserId, token) end
		return nil
	end
	if not ok then
		s.canSave = false
		return nil
	end
	s.canSave = acquired
	s.token = if acquired then token else nil
	s.lockedElsewhere = lockedByOther
	s.future = future
	s.loadedRaw = raw
	return raw
end

local recheckLock: (Session) -> ()
recheckLock = function(s: Session)
	while sessions[s.plr] == s and not s.leaving and not s.canSave and s.lockedElsewhere do
		task.wait(Config.Save.LockRecheckSeconds)
		if sessions[s.plr] ~= s or s.leaving or store == nil then return end
		local token = HttpService:GenerateGUID(false)
		local state = nil
		local ok, err = pcall(function()
			store:UpdateAsync(key(s.plr.UserId), function(old)
				state = nil
				old = old or {}
				local t = os.time()
				if (tonumber(old.lockUntil) or 0) > t and old.jobId ~= game.JobId then
					state = "locked"
					return nil
				end
				if not sameData(old.data, s.loadedRaw) then
					state = "changed"
					return nil
				end
				state = "taken"
				old.session = token
				old.jobId = game.JobId
				old.lockUntil = t + Config.Save.LockSeconds
				return old
			end)
		end)
		if not ok then
			warn("[OutpostZero] save failed (lock re-check) for " .. s.plr.Name .. ": " .. tostring(err))
		elseif state == "taken" then
			if sessions[s.plr] ~= s or s.leaving then
				releaseLock(s.plr.UserId, token)
				return
			end
			s.token = token
			s.canSave = true
			s.lockedElsewhere = false
			s.pending = true
			toast(s.plr, Config.Tutorial.LockTaken)
			pushState(s, true)
			return
		elseif state == "changed" then
			s.lockedElsewhere = false
			s.lockChanged = true
			toast(s.plr, Config.Tutorial.LockChanged)
			pushState(s, true)
			return
		end
	end
end

--============================================================================ the Census
local publicCache = { rows = nil :: { any }?, at = -math.huge }
local nameCache: { [number]: string } = {}
local friendCache: { [number]: { value: number?, at: number } } = {}
-- the viewer's friends LIST (round 2, A3): ids fetched at `at`, or a failed fetch at `failedAt`
local friendListCache: { [number]: { ids: { number }?, at: number, failedAt: number? } } = {}
local friendJobs: { [Player]: { { id: number, gen: number } } } = {}
local friendTurn: { Player } = {}
local lastFriendRead = -math.huge

local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then return cached end
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		nameCache[userId] = inServer.Name
		return inServer.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local n = if ok and type(name) == "string" then name else ("Player " .. tostring(userId))
	if ok then nameCache[userId] = n end
	return n
end

local function refreshPublic()
	local t = now()
	if boardStore == nil or t - publicCache.at < Config.Board.PublicCacheSeconds then return end
	publicCache.at = t
	local ok, page = pcall(function()
		local pages = boardStore:GetSortedAsync(false, Config.Board.PublicSize)
		return pages:GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then return end
	local rows = {}
	for _, e in page do
		local id = tonumber(string.match(tostring(e.key), "^u_(%d+)$"))
		if id and type(e.value) == "number" then
			table.insert(rows, { userId = id, value = e.value })
		end
	end
	publicCache.rows = rows
end

-- A player's own row, from what has been SAVED (the board never shows a population a save did not keep).
local function ownValue(s: Session): number?
	if s.savedPop <= 0 then return s.boardLast end
	return Board.encode(Config, s.savedPop, s.savedPopAt)
end

local function rowsPayload(ranked: { any }, viewerId: number): { any }
	local out = {}
	for _, r in ranked do
		table.insert(out, {
			rank = r.rank,
			name = nameOf(r.userId),
			pop = r.pop,
			emoji = Board.emojiFor(Config, r.pop),
			you = r.userId == viewerId,
		})
	end
	return out
end

local function sendBoard(s: Session)
	local view = s.view
	local payload: any = { mode = view.mode, footer = "Lifetime " .. Economy.short(s.data.lifetime) .. " credits", rows = {}, status = "" }
	if view.mode == "public" then
		refreshPublic()
		local rows = table.clone(publicCache.rows or {})
		local mine = ownValue(s)
		local present = false
		for _, r in rows do
			if r.userId == s.plr.UserId then present = true end
		end
		payload.rows = rowsPayload(Board.rank(Config, rows), s.plr.UserId)
		if not present and mine ~= nil then
			local p = Board.decode(Config, mine)
			table.insert(payload.rows, { rank = 0, name = s.plr.Name, pop = p, emoji = Board.emojiFor(Config, p), you = true })
		end
		if #payload.rows == 0 then
			payload.status = if boardStore then "Be the first on the Census: build a Home and a Workshop." else "The Census is unavailable right now."
		end
	else
		local rows = {}
		local mine = ownValue(s)
		if mine ~= nil then table.insert(rows, { userId = s.plr.UserId, value = mine }) end
		local friendsOn = 0
		for id, v in view.friendValues do
			if v ~= nil then
				table.insert(rows, { userId = id, value = v })
				friendsOn += 1
			end
		end
		payload.rows = rowsPayload(Board.rank(Config, rows), s.plr.UserId)
		if #payload.rows == 0 then
			table.insert(payload.rows, { rank = 0, name = s.plr.Name, pop = s.st.pop, emoji = Board.emojiFor(Config, s.st.pop), you = true })
		end
		if view.unavailable then
			payload.status = Board.UNAVAILABLE
		elseif view.fetching then
			payload.status = Board.loadingText(0, 0)
		elseif view.done < view.total then
			payload.status = Board.loadingText(view.done, view.total)
		elseif friendsOn == 0 then
			payload.status = Board.emptyFriendsText(Config, s.st.pop)
		end
	end
	-- the face has Config.Board.Rows slots, and the viewer's own row is always one of them (REVIEW-1 F6)
	payload.rows = Board.window(payload.rows, Config.Board.Rows)
	BoardR:FireClient(s.plr, payload)
end

local function dropFriendJobs(plr: Player)
	friendJobs[plr] = nil
	local i = table.find(friendTurn, plr)
	if i then table.remove(friendTurn, i) end
end

local function fillFriends(s: Session, ids: { number })
	local view = s.view
	dropFriendJobs(s.plr)
	view.friendValues = {}
	view.done, view.total, view.unavailable, view.fetching = 0, #ids, false, false
	local t = now()
	local jobs = {}
	for _, id in ids do
		local other = Players:GetPlayerByUserId(id)
		local os_ = other and sessions[other]
		if os_ then
			view.friendValues[id] = ownValue(os_) -- on this server: from memory, no request
			view.done += 1
		elseif friendCache[id] and t - friendCache[id].at < Config.Board.FriendCacheSeconds then
			view.friendValues[id] = friendCache[id].value
			view.done += 1
		else
			table.insert(jobs, { id = id, gen = view.gen })
		end
	end
	if #jobs > 0 then
		friendJobs[s.plr] = jobs
		table.insert(friendTurn, s.plr)
	end
	sendBoard(s)
end

local function startFriends(s: Session)
	local view = s.view
	view.gen += 1
	dropFriendJobs(s.plr)
	view.friendValues = {}
	view.done, view.total, view.unavailable, view.fetching = 0, 0, false, true
	sendBoard(s)
	if s.friendsFetching then return end
	local plr = s.plr
	-- the list itself is cached (standard §3): one fetch per FriendListCacheSeconds, and after a failure none for
	-- FriendListRetrySeconds, however often the board is switched (round 2, A3)
	local cached = friendListCache[plr.UserId]
	local t = now()
	if cached and cached.ids and t - cached.at < Config.Board.FriendListCacheSeconds then
		fillFriends(s, cached.ids)
		return
	end
	if cached and cached.failedAt and t - cached.failedAt < Config.Board.FriendListRetrySeconds then
		view.fetching = false
		view.unavailable = true
		sendBoard(s)
		return
	end
	s.friendsFetching = true
	local ok, ids = pcall(function()
		local pages = (Players :: any):GetFriendsAsync(plr.UserId)
		local first = true
		return Board.collectFriendIds(Config, function()
			if first then
				first = false
				return pages:GetCurrentPage()
			end
			if pages.IsFinished then return nil end
			pages:AdvanceToNextPageAsync()
			return pages:GetCurrentPage()
		end)
	end)
	s.friendsFetching = false
	if ok and type(ids) == "table" then
		friendListCache[plr.UserId] = { ids = ids, at = now() }
	else
		friendListCache[plr.UserId] = { ids = nil, at = -math.huge, failedAt = now() }
	end
	if sessions[plr] ~= s or view.mode ~= "friends" then return end
	if not ok or type(ids) ~= "table" then
		view.fetching = false
		view.unavailable = true
		sendBoard(s)
		return
	end
	fillFriends(s, ids)
end

local function stepFriendQueue()
	if #friendTurn == 0 or boardStore == nil then return end
	local t = now()
	local served = 0
	while #friendTurn > 0 and served < Config.Board.FriendsCap do
		local viewer = friendTurn[1]
		local s = sessions[viewer]
		local jobs = friendJobs[viewer]
		if s == nil or jobs == nil or #jobs == 0 or s.view.mode ~= "friends" or jobs[1].gen ~= s.view.gen then
			dropFriendJobs(viewer)
			continue
		end
		local c = friendCache[jobs[1].id]
		if c == nil or t - c.at >= Config.Board.FriendCacheSeconds then break end
		local job = table.remove(jobs, 1)
		s.view.friendValues[job.id] = c.value
		s.view.done += 1
		served += 1
		if #jobs == 0 then dropFriendJobs(viewer) end
		sendBoard(s)
	end
	if #friendTurn == 0 then return end
	local okB, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	if not okB or not Board.canRead(Config, t, lastFriendRead, budget) then return end
	local viewer = table.remove(friendTurn, 1)
	local jobs = friendJobs[viewer]
	local job = table.remove(jobs, 1)
	if #jobs > 0 then table.insert(friendTurn, viewer) else friendJobs[viewer] = nil end -- round-robin
	lastFriendRead = t
	local ok, v = pcall(function()
		return boardStore:GetAsync(key(job.id))
	end)
	local value = if ok and type(v) == "number" then v else nil
	if ok then friendCache[job.id] = { value = value, at = t } end
	local s = sessions[viewer]
	if s and s.view.mode == "friends" and s.view.gen == job.gen then
		s.view.friendValues[job.id] = value
		s.view.done += 1
		sendBoard(s)
	end
end

-- `attempts`: the leave passes Config.Board.LeaveWriteAttempts. After the leave nothing writes this key again until
-- the player returns, so one transient error there would keep the city off its rank indefinitely (round 2, A2);
-- the periodic write needs no retry (it runs again within a minute).
local function boardWrite(s: Session, force: boolean, attempts: number?)
	if boardStore == nil or not s.canSave then return end
	-- only what has been SAVED is ranked, so the board never shows a population the profile does not have
	if not Board.shouldWrite(Config, s.boardLast, s.savedPop) then return end
	if not force and now() - s.boardWriteAt < Config.Board.WriteMinInterval then return end
	local v = Board.encode(Config, s.savedPop, s.savedPopAt)
	local tries = attempts or 1
	local err
	for i = 1, tries do
		local ok, e = pcall(function()
			boardStore:SetAsync(key(s.plr.UserId), v)
		end)
		if ok then
			s.boardLast = v
			s.boardWriteAt = now()
			publicCache.at = -math.huge -- the next view re-reads, so the writer sees themselves
			return
		end
		err = e
		if i < tries then task.wait(Config.Board.LeaveRetrySeconds * i) end
	end
	if tries > 1 then
		warn(string.format("[OutpostZero] Census write failed %d times for %s; it is written at their next join: %s",
			tries, s.plr.Name, tostring(err)))
	end
end

--============================================================================ the Grand Airship and the skyline
local function startAirship(s: Session)
	local shelf = s.shelf
	addHallPiece(shelf, Config.SkyportDistrict)
	s.airship = { state = "flying", endsAt = now() + Config.Airship.FlightSeconds }
	local dock = airshipDock(shelf)
	local mast, nose = dock.Position, dock.RightVector -- the moored gondola's centre, and the way its nose points
	-- every client flies its own copy in, along the nose's line; the owner also gets the title card
	AnnounceR:FireAllClients({ kind = "airship", shelf = shelf.k, mast = { mast.X, mast.Y, mast.Z }, nose = { nose.X, nose.Z },
		seconds = Config.Airship.FlightSeconds, name = displayName(s.plr) })
	FxR:FireClient(s.plr, { kind = "airship", seconds = Config.Airship.FlightSeconds })
	pushState(s, true)
end

local function moorAirship(s: Session)
	placeAirship(s.shelf)
	s.airship = { state = "moored", holdUntil = now() + Config.Airship.HoldAfterSeconds }
	if not s.data.airshipSeen then
		s.data.airshipSeen = true
		s.pending = true
	end
	AnnounceR:FireAllClients({ kind = "text", text = displayName(s.plr) .. "'s city welcomed the Grand Airship!" })
	FxR:FireClient(s.plr, { kind = "moored" })
	pushState(s, true)
end

local function checkComplete(s: Session, announce: boolean)
	if Economy.cheapest(Config, s.st) ~= nil then return end
	if s.shelf.beam then return end
	setCrownBeam(s.shelf, true)
	if announce then
		AnnounceR:FireAllClients({ kind = "text", text = displayName(s.plr) .. " completed their skyline!" })
		FxR:FireClient(s.plr, { kind = "complete" })
	end
end

--============================================================================ players
local function claimShelf(plr: Player): any
	for k = 1, W.Shelves do
		if shelves[k].owner == nil then
			shelves[k].owner = plr
			return shelves[k]
		end
	end
	return nil
end

local function placeOnPad(plr: Player, hrp: BasePart, shelf: any)
	local pad = shelf.arrival.Position
	local stand = Vector3.new(pad.X, pad.Y + 0.5 + SH.RootAbovePad, pad.Z)
	local ahead = shelf.at(SH.Arrival.x, stand.Y, SH.Arrival.z - 10).Position
	hrp.CFrame = CFrame.lookAt(stand, ahead)
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
end

local function onCharacter(plr: Player, char: Model)
	-- SPAWN-ORDER.md: the engine parents and places the character one frame AFTER CharacterAdded, and wins.
	-- RespawnLocation already told it where; this only waits (bounded) and corrects a stray placement.
	local frames = 0
	while char.Parent == nil and frames < SH.SpawnWaitFrames do
		task.wait(1 / 60)
		frames += 1
	end
	local s = sessions[plr] -- re-read: anything can change across the yield
	if s == nil or plr.Character ~= char then return end
	local shelf = s.shelf
	if plr.RespawnLocation ~= shelf.arrival then plr.RespawnLocation = shelf.arrival end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local p = hrp.Position
		local pad = shelf.arrival.Position
		local off = math.sqrt((p.X - pad.X) ^ 2 + (p.Z - pad.Z) ^ 2)
		if off > SH.SpawnCorrectStuds then placeOnPad(plr, hrp, shelf) end
	end
end

local function makeLeaderstats(plr: Player, s: Session)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local p = Instance.new("IntValue")
	p.Name = "Population"
	p.Parent = ls
	ls.Parent = plr
	s.leader = p
end

-- After the load: the profile becomes a city (layout, offline earnings, parts), then the board and the toasts.
local function afterLoad(s: Session, raw: any)
	local plr = s.plr
	if s.leaving or sessions[plr] ~= s then return end
	local data, info = Save.normalise(Config, raw)
	if info.future then
		s.canSave = false
		warn("[OutpostZero] " .. plr.Name .. "'s record is from a newer version; this session plays it unsaved and never writes it.")
	end
	if info.reseed then
		data.seed = rng:NextInteger(1, Config.Save.SeedMax)
		if not info.fresh then warn("[OutpostZero] " .. plr.Name .. "'s layout seed was invalid; a new layout was drawn.") end
		s.pending = true
	end
	s.layout = City.layout(Config, data.seed, Rng)
	s.st = Economy.newState(Config, s.layout, data.lots, data.credits)
	s.data = data
	-- offline: the workers finished their Orders while the player was away (then the safety net, never more)
	local before = data.credits
	local offline = 0
	if not info.fresh then
		local credits = Economy.offline(Config, data, s.st.income, os.time(), Economy.cheapest(Config, s.st))
		offline = math.max(0, credits - before)
		s.st.credits = credits
		data.credits = credits
		data.lifetime += offline
		-- bank them at the next flush: credits and savedAt go out together, so the absence is paid exactly once
		if offline > 0 then s.pending = true end
	end
	-- REVIEW-1 F5: a city with nobody in it has no income, so the safety net cannot reach it. canBuy keeps every
	-- city at or above Economy.startNeed; a record below it (saved before that rule, or damaged) could never earn
	-- again, so it is lifted here, once, to exactly what its first citizens cost, and logged.
	local need = Economy.startNeed(Config, s.st)
	if s.st.credits < need and not info.fresh then
		local lift = need - s.st.credits
		s.st.credits = need
		data.credits = need
		data.lifetime += lift
		s.pending = true
		warn(string.format("[OutpostZero] %s's city had no citizens and too few credits to get any; lifted by %s to %s.",
			plr.Name, Economy.short(lift), Economy.short(need)))
	end
	s.ordersUntil = now() + math.max(0, data.ordersUntil - os.time())
	s.lastEarn = now()
	if s.st.pop > 0 and data.popAt <= 0 then data.popAt = os.time() end
	s.loaded = true
	s.savedPop = if s.canSave and not info.fresh then s.st.pop else 0
	s.savedPopAt = data.popAt
	-- the city
	local open = Economy.districtsOpen(Config, s.st.pop)
	for d = open + 1, #Config.Districts do buildSign(s, d) end
	syncDistricts(s)
	if open >= Config.SkyportDistrict then
		if data.airshipSeen then
			placeAirship(s.shelf)
			s.airship = { state = "moored", holdUntil = 0 }
		else
			-- the flight was missed (left mid-flight): it plays once more, a moment after the HUD is up
			s.airship = { state = "pending", startAt = now() + 3 }
		end
	end
	checkComplete(s, false)
	s.info:SetAttribute("Seed", data.seed)
	-- the board's "last value": one read of the player's own key, so a rejoin never writes a lower or equal one
	if boardStore then
		local ok, v = pcall(function()
			return boardStore:GetAsync(key(plr.UserId))
		end)
		if ok and type(v) == "number" then s.boardLast = v end
		if s.leaving or sessions[plr] ~= s then return end
	end
	if s.lockedElsewhere then task.spawn(recheckLock, s) end
	if not s.canSave then
		toast(plr, if s.lockedElsewhere then Config.Tutorial.NotSavingLocked else Config.Tutorial.NotSaving)
	end
	if offline >= 1 then
		toast(plr, "Your workers finished their orders while you were away: +" .. Economy.short(offline))
	end
	pushState(s, true)
	sendBoard(s)
end

local function onPlayerAdded(plr: Player)
	if sessions[plr] then return end
	local shelf = claimShelf(plr)
	if shelf == nil then
		warn("[OutpostZero] a seventh player arrived; all 6 shelves are taken (Players.MaxPlayers must be 6): " .. plr.Name)
		plr:Kick(W.KickMessage)
		return
	end
	-- BEFORE ANY YIELD: tell the engine where this player's character goes (SPAWN-ORDER.md, preferred pattern)
	plr.RespawnLocation = shelf.arrival
	local info = Instance.new("Folder")
	info.Name = tostring(plr.UserId)
	info.Parent = cityInfoRoot
	local data = Save.defaults(Config)
	local s: Session = {
		plr = plr,
		shelf = shelf,
		data = data,
		layout = nil,
		st = { layout = { lots = {}, byKey = {} }, lots = data.lots, credits = data.credits, settlers = 0, jobs = 0, pop = 0, income = 0 },
		loaded = false,
		canSave = false,
		lockedElsewhere = false,
		lockChanged = false,
		future = false,
		token = nil,
		pending = false,
		writing = false,
		lastSave = now(),
		loadedRaw = nil,
		ordersUntil = now(),
		lastEarn = now(),
		netNow = false,
		minted = 0,
		rateEma = 0,
		lastStateAt = -math.huge,
		lastStarKey = nil,
		boardLast = nil,
		boardWriteAt = -math.huge,
		savedPop = 0,
		savedPopAt = 0,
		rl = { start = -math.huge, n = 0 },
		toastAt = {},
		leaving = false,
		leader = nil,
		info = info,
		view = { mode = "public", friendValues = {}, done = 0, total = 0, unavailable = false, fetching = false, gen = 0 },
		friendsFetching = false,
		airship = nil,
		openShown = 1,
		lastInfo = "",
	}
	sessions[plr] = s
	makeLeaderstats(plr, s)
	shelf.ownerSign.Text = "🏙️ " .. displayName(plr) .. "'s city"
	shelf.title.Text = "📊 " .. displayName(plr) .. "'s CENSUS"
	info:SetAttribute("Shelf", shelf.k)
	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)
	if plr.Character then
		task.spawn(onCharacter, plr, plr.Character)
	end
	task.spawn(function()
		local raw = load(s)
		afterLoad(s, raw)
	end)
end

local function onPlayerRemoving(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	s.leaving = true
	-- REVIEW-1 F2: the shelf is freed FIRST, before the writes below yield (each takes real DataStore time), so a
	-- player Roblox sends in meanwhile gets it instead of a "6 shelves are taken" kick. From here on nothing touches
	-- the shelf for this session: the writes use only s.data / s.st, and stepSession skips a leaving session.
	s.shelf.owner = nil
	resetShelf(s.shelf)
	if s.loaded and not s.future then
		local uid = plr.UserId
		leaveWrites[uid] = (leaveWrites[uid] or 0) + 1
		writeProfile(s, true, true)
		leaveWrites[uid] -= 1
		if leaveWrites[uid] <= 0 then leaveWrites[uid] = nil end
		boardWrite(s, true, Config.Board.LeaveWriteAttempts)
	end
	s.info:Destroy()
	sessions[plr] = nil
	dropFriendJobs(plr)
	friendListCache[plr.UserId] = nil -- bounded: only the players in this server
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
end

game:BindToClose(function()
	for _, s in sessions do
		if s.loaded and not s.future then
			writeProfile(s, true, true)
			boardWrite(s, true)
		end
	end
end)

--============================================================================ the prompts: every player action
local function rateOk(s: Session): boolean
	local t = now()
	local b = s.rl
	if t - b.start >= 1 then
		b.start = t
		b.n = 0
	end
	b.n += 1
	if b.n > Config.Prompts.MaxPerSecond then
		toastEvery(s, "slow", Config.Prompts.SlowToastSeconds, "Slow down: one press is enough.")
		return false
	end
	return true
end

onLotPrompt = function(plr: Player, shelf: any, lotKey: string)
	local s = sessions[plr]
	if s == nil then return end
	if not rateOk(s) then return end
	if shelf.owner ~= plr then
		local who = if shelf.owner then displayName(shelf.owner :: Player) .. "'s" else "a free shelf's"
		toastEvery(s, "foreign", Config.Prompts.ForeignToastSeconds, "This is " .. who .. " city. Yours is the shelf with your name on it.")
		return
	end
	if not s.loaded then
		toast(plr, Config.Tutorial.Loading)
		return
	end
	settle(s)
	local st = s.st
	local ok, why, price = Economy.canBuy(Config, st, lotKey)
	if not ok then
		toast(plr, Economy.refusalText(Config, why, price, st.credits, st.income))
		return
	end
	local popBefore = st.pop
	local openBefore = Economy.districtsOpen(Config, popBefore)
	Economy.apply(Config, st, lotKey)
	s.data.credits = st.credits
	s.ordersUntil = now() + E.OrdersSeconds
	if st.pop > popBefore then s.data.popAt = os.time() end
	if s.data.tutorial < 3 then s.data.tutorial += 1 end
	s.pending = true
	local lot = shelf.lots[lotKey]
	if lot then
		setBuilding(s, lot, true)
		updatePrompt(s, lot)
		local p = lot.post.Position
		FxR:FireClient(plr, { kind = "build", key = lotKey, x = p.X, y = p.Y, z = p.Z, storeys = storeysOf(s, lotKey) })
	end
	local openAfter = Economy.districtsOpen(Config, st.pop)
	if openAfter > openBefore then
		syncDistricts(s)
		for d = openBefore + 1, openAfter do
			FxR:FireClient(plr, { kind = "district", d = d, name = Config.Districts[d].name })
		end
		if openBefore < Config.SkyportDistrict and openAfter >= Config.SkyportDistrict and s.airship == nil then
			startAirship(s)
		end
	end
	checkComplete(s, true)
	pushState(s, true)
end

for _, shelf in shelves do
	shelf.prompt.Triggered:Connect(function(plr: Player)
		local s = sessions[plr]
		if s == nil then return end
		if not rateOk(s) then return end -- first, as on the lots (REVIEW-1 F3: a foreign board toasted every press)
		if shelf.owner ~= plr then
			local who = if shelf.owner then displayName(shelf.owner :: Player) .. "'s" else "a free shelf's"
			toastEvery(s, "foreignBoard", Config.Prompts.ForeignToastSeconds, "This is " .. who .. " Census board. Yours is beside your own arrival pad.")
			return
		end
		s.view.mode = if s.view.mode == "public" then "friends" else "public"
		if s.view.mode == "friends" then
			task.spawn(startFriends, s)
		else
			s.view.gen += 1
			dropFriendJobs(plr)
			sendBoard(s)
		end
	end)
end

--============================================================================ the tick: 10 Hz
local function stepSession(s: Session, dt: number)
	-- a leaving session's shelf may already be someone else's (onPlayerRemoving): never move, moor or redraw there
	if s.leaving then return end
	local plr = s.plr
	-- the fall rescue: anyone below the shelves goes back to their own pad
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and hrp.Position.Y < W.RescueY then
		placeOnPad(plr, hrp, s.shelf)
		toast(plr, Config.Tutorial.Rescue)
	end
	if not s.loaded then
		pushState(s, false) -- "Loading your city…" until the profile arrives
		return
	end
	settle(s)
	local minted = s.minted
	s.minted = 0
	if dt > 0 then
		local a = 1 - 0.5 ^ (dt / E.RateHalfLife)
		s.rateEma += (minted / dt - s.rateEma) * a
	end
	-- the airship
	local a = s.airship
	if a then
		if a.state == "pending" and now() >= a.startAt then
			startAirship(s)
		elseif a.state == "flying" and now() >= a.endsAt then
			moorAirship(s)
		end
	end
	-- the debug folder (ServerStorage only), written on change
	local memo = string.format("%d|%.0f|%.1f", s.st.pop, s.st.credits, ordersLeft(s))
	if memo ~= s.lastInfo then
		s.lastInfo = memo
		s.info:SetAttribute("Credits", s.st.credits)
		s.info:SetAttribute("OrdersLeft", ordersLeft(s))
		s.info:SetAttribute("Population", s.st.pop)
	end
	-- a moved ★ reaches the HUD at once
	local pick = starOf(s)
	if (pick and pick.key) ~= s.lastStarKey then pushState(s, true) end
	pushState(s, false)
end

task.spawn(function()
	local last = now()
	local warned = {}
	while true do
		task.wait(E.TickSeconds)
		local t = now()
		local dt = math.clamp(t - last, 0, 1)
		last = t
		for plr, s in sessions do
			local ok, err = pcall(stepSession, s, dt)
			if not ok and not warned[plr] then
				warned[plr] = true -- once: a broken session must not flood the output
				warn("[OutpostZero] tick failed for " .. plr.Name .. ": " .. tostring(err))
			end
		end
	end
end)

--============================================================================ saving and the board, on their own clocks
task.spawn(function()
	while true do
		task.wait(Config.Save.FlushTickSeconds)
		local t = now()
		for _, s in sessions do
			if s.loaded and not s.leaving and s.canSave and (s.pending or t - s.lastSave >= Config.Save.AutosaveSeconds) then
				writeProfile(s, false)
			end
		end
	end
end)

task.spawn(function()
	local tickN = 0
	while true do
		task.wait(1)
		tickN += 1
		for _, s in sessions do
			if s.loaded and not s.leaving then
				boardWrite(s, false)
				-- every 30 s each owner's board is re-sent: the public view refreshes from its 60 s cache, and a client
				-- that connected after the first send (a slow HUD) still gets its rows
				if tickN % 30 == 0 then sendBoard(s) end
			end
		end
		stepFriendQueue()
	end
end)
