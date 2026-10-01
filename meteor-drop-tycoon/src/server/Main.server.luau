-- METEOR DROP TYCOON — the authoritative server (ServerScriptService).
--
-- Meteors fall onto each player's own round plot; walking over a landed one sends it into the Smelter,
-- which melts ore into Stardust; Stardust buys the Beacon (more, richer, rarer meteors and a new sky),
-- the Collector (a dish that catches with no walking, and sleeps 10 min after your last hand pickup)
-- and the Smelter (faster melting). DESIGN.md is the spec; every number lives in Config.
--
-- What the server owns, and why nothing a client says can inflate the Star Chart:
--   * every meteor is drawn here from one server-lifetime Random.new(); nothing is seeded, so there is
--     nothing to re-run, and a meteor exists only from its announcement (1.5 s before it lands);
--   * a pickup is tested against the TRUSTED position (Trace: the server's own copy of the player,
--     moving toward the claimed root at no more than 21.6 studs/s), never against the claim itself;
--   * Stardust is minted only by the Smelter on this server's clock, or by a legendary spawned here;
--   * a Beacon level is raised only by a Buy this file validated against Economy's price;
--   * the only client -> server remote is Buy(kind): a string whitelist, a price check, 8 calls/s, and a
--     toast for every refusal. Pickups are polls, the board toggle is a ProximityPrompt, rest and hazards
--     are client-only and grant nothing.
-- Nothing secret replicates: no attribute is set on anything under workspace or ReplicatedStorage;
-- debug values for headless checks live in ServerStorage.PlotInfo (anomaly-observatory's rule).
--
-- Spawn (robloxemu/SPAWN-ORDER.md, the preferred pattern): every plot's arrival pad is a real enabled
-- SpawnLocation built before anyone joins, PlayerAdded sets plr.RespawnLocation synchronously, and
-- CharacterAdded only waits (bounded) and corrects a character the engine put somewhere else.
--
-- Saving: one UpdateAsync load that takes the lock with a fresh owner token; every later write lands
-- only while the record still carries that token (fork-tower REVIEW-4 §10). canSave only while holding
-- the lock. The one-time Falling Star is granted inside one atomic write and spawns only after it lands
-- (or at once in a non-saving session, where an unsaved grant cannot be redeemed twice).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService") -- GenerateGUID only (session tokens); no HTTP

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Meteors = require(ReplicatedStorage:WaitForChild("Meteors"))
local PlotGeom = require(ReplicatedStorage:WaitForChild("PlotGeom"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local Save = require(ReplicatedStorage:WaitForChild("Save"))
local Trace = require(ReplicatedStorage:WaitForChild("Trace"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

-- The look, first thing: golden hour, equal to band 1, so every client's first blend takes over with no jump.
Fx.applyLighting(Fx.Presets.Dusk)

local W, P, MC = Config.World, Config.Plot, Config.Meteors
local Palette = Config.Palette
local STAR_BEACON = Config.Env.StarBeacon

-- tick() is the in-session clock (robloxemu advances it; os.clock barely moves headless). os.time() for
-- everything persisted.
local function now(): number
	return tick()
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

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
	if props.shape then (p :: Part).Shape = props.shape end
	p.Size = props.size
	p.CFrame = props.cf
	p.Transparency = props.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.parent then p.Parent = props.parent end
	return p
end

--============================================================================ remotes
local remotes = Instance.new("Folder")
remotes.Name = "MeteorRemotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local StateR = remote("State") -- server -> owner: their own present state
local ToastR = remote("Toast") -- server -> one player: a sentence
local FxR = remote("Fx") -- server -> owner: a catch, a zip, a burn-up, the Falling Star
local BoardR = remote("Board") -- server -> viewer: their own Star Chart view
local AnnounceR = remote("Announce") -- server -> all: "<name> caught a Falling Star!"
local BuyR = remote("Buy") -- client -> server: the only one
remotes.Parent = ReplicatedStorage

--============================================================================ stores (all pcall'd)
-- GetDataStore raises in an unpublished place; unwrapped, it kills this script.
local store: any = nil
local boardStore: any = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(Config.Save.Store)
	end)
	if ok then store = s else warn("[MeteorDrop] DataStore unavailable; progress will not be saved: " .. tostring(s)) end
	local okB, b = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Board.Store)
	end)
	if okB then boardStore = b else warn("[MeteorDrop] Star Chart store unavailable: " .. tostring(b)) end
end
local function key(userId: number): string
	return "u_" .. tostring(userId)
end

--============================================================================ ServerStorage: the kit and the debug folder
local kit = Instance.new("Folder")
kit.Name = "MeteorKit"
kit.Parent = ServerStorage
local plotInfoRoot = Instance.new("Folder")
plotInfoRoot.Name = "PlotInfo" -- debug values for headless checks and tools; never replicated
plotInfoRoot.Parent = ServerStorage

do
	-- the landing glow: a flat Neon disc in the rarity colour
	makePart({ name = "Glow", shape = Enum.PartType.Cylinder, size = Vector3.new(0.1, Config.Rarities.GlowSize, Config.Rarities.GlowSize),
		cf = CFrame.new() * UPRIGHT, material = Enum.Material.Neon, transparency = 0.35, parent = kit })
	-- the Falling Star's gold marker and beam, and the landed star
	local star = makePart({ name = "Star", shape = Enum.PartType.Ball, size = Vector3.new(4.5, 4.5, 4.5), cf = CFrame.new(),
		material = Enum.Material.Neon, color = c3(Config.Rarities.StarColor), parent = kit })
	local a0 = Instance.new("Attachment")
	a0.Name = "BeamBase"
	a0.Parent = star
	local a1 = Instance.new("Attachment")
	a1.Name = "BeamTop"
	a1.Position = Vector3.new(0, 60, 0)
	a1.Parent = star
	local beam = Instance.new("Beam")
	beam.Name = "GoldBeam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(c3(Config.Rarities.StarColor))
	beam.Width0 = 3
	beam.Width1 = 1
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	beam.Parent = star
end

--============================================================================ the world: ground, observatory, 8 plots
local baseplate = makePart({ name = "Baseplate", size = Vector3.new(W.BaseplateSize, 2, W.BaseplateSize),
	cf = CFrame.new(0, W.GroundY - 1, 0), material = Enum.Material.Grass, color = c3(Palette.Ground), collide = true })
baseplate.Parent = workspace

do
	local obs = Instance.new("Model")
	obs.Name = "Observatory"
	local R = W.ObservatoryRadius
	makePart({ name = "ObservatoryBase", shape = Enum.PartType.Cylinder, size = Vector3.new(2, 2 * R, 2 * R),
		cf = CFrame.new(0, 1, 0) * UPRIGHT, material = Enum.Material.Concrete, color = c3(Palette.Observatory), collide = true, parent = obs })
	makePart({ name = "ObservatoryWall", shape = Enum.PartType.Cylinder, size = Vector3.new(8, 2 * R - 6, 2 * R - 6),
		cf = CFrame.new(0, 6, 0) * UPRIGHT, material = Enum.Material.Concrete, color = c3(Palette.Observatory), collide = true, parent = obs })
	makePart({ name = "Dome", shape = Enum.PartType.Ball, size = Vector3.new(2 * R - 6, 2 * R - 6, 2 * R - 6),
		cf = CFrame.new(0, 10, 0), material = Enum.Material.Metal, color = c3(Palette.Dome), collide = true, parent = obs })
	makePart({ name = "DomeSlit", size = Vector3.new(3, 2, 2 * R - 5), cf = CFrame.new(0, 10 + R - 4, 0) * CFrame.Angles(math.rad(-20), 0, 0),
		material = Enum.Material.Metal, color = c3(Palette.Telescope), parent = obs })
	makePart({ name = "Telescope", shape = Enum.PartType.Cylinder, size = Vector3.new(16, 3, 3),
		cf = CFrame.new(0, 22, -4) * CFrame.Angles(0, math.rad(90), math.rad(55)), material = Enum.Material.Metal,
		color = c3(Palette.Telescope), parent = obs })
	makePart({ name = "TelescopeLens", shape = Enum.PartType.Cylinder, size = Vector3.new(0.4, 3.2, 3.2),
		cf = CFrame.new(0, 28.5, -8.6) * CFrame.Angles(0, math.rad(90), math.rad(55)), material = Enum.Material.Neon,
		color = c3(Palette.DishRim), parent = obs })
	obs.Parent = workspace
end

type Meteor = {
	part: BasePart?,
	x: number,
	z: number,
	rarity: string,
	ore: number,
	landAt: number,
	landed: boolean,
	fate: string,
	star: boolean,
}

local plots = {}
local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"

local function buildPlot(k: number)
	local cx, cz = PlotGeom.centre(Config, k)
	local cf = CFrame.lookAt(Vector3.new(cx, 0, cz), Vector3.new(0, 0, 0)) -- LookVector = local -Z, at the observatory
	local function at(lx: number, ly: number, lz: number): CFrame
		return cf * CFrame.new(lx, ly, lz)
	end
	local model = Instance.new("Model")
	model.Name = "Plot_" .. k
	local top = W.DiscTopY

	makePart({ name = "Disc", shape = Enum.PartType.Cylinder, size = Vector3.new(0.4, 2 * W.PlotRadius, 2 * W.PlotRadius),
		cf = at(0, top - 0.2, 0) * UPRIGHT, material = Enum.Material.Grass, color = c3(Palette.Disc), collide = true, parent = model })
	makePart({ name = "Rim", shape = Enum.PartType.Cylinder, size = Vector3.new(0.3, 2 * W.PlotRadius + 2, 2 * W.PlotRadius + 2),
		cf = at(0, top - 0.25, 0) * UPRIGHT, material = Enum.Material.Sand, color = c3(Palette.Rim), parent = model })

	-- the arrival pad: a real, enabled SpawnLocation, facing the Smelter (+Z local)
	local pad = Instance.new("SpawnLocation")
	pad.Name = "Arrival"
	pad.Anchored = true
	pad.CanCollide = true
	pad.Enabled = true
	pad.Neutral = true
	pad.Duration = 0 -- no force-field bubble (needs-Studio: confirm it removes it)
	pad.Size = Vector3.new(P.ArrivalSize, 1, P.ArrivalSize)
	pad.CFrame = at(P.Arrival.x, 0.5, P.Arrival.z) * CFrame.Angles(0, math.pi, 0)
	pad.Material = Enum.Material.Marble
	pad.Color = c3(Palette.Arrival)
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Parent = model

	-- the Smelter: 8 parts
	local smelter = Instance.new("Model")
	smelter.Name = "Smelter"
	makePart({ name = "SmelterBase", shape = Enum.PartType.Cylinder, size = Vector3.new(1, 2 * P.SmelterRadius, 2 * P.SmelterRadius),
		cf = at(0, top + 0.5, 0) * UPRIGHT, material = Enum.Material.Basalt, color = c3(Palette.SmelterBody), collide = true, parent = smelter })
	makePart({ name = "SmelterBody", size = Vector3.new(7, 6, 7), cf = at(0, top + 4, 0), material = Enum.Material.Metal,
		color = c3(Palette.SmelterBody), collide = true, parent = smelter })
	makePart({ name = "SmelterMouth", size = Vector3.new(3.4, 2.2, 0.4), cf = at(0, top + 3, -3.6), material = Enum.Material.Neon,
		color = c3(Palette.SmelterMouth), parent = smelter })
	makePart({ name = "Chimney", shape = Enum.PartType.Cylinder, size = Vector3.new(6, 2.2, 2.2), cf = at(1.8, top + 10, 1.8) * UPRIGHT,
		material = Enum.Material.Metal, color = c3(Palette.Chimney), parent = smelter })
	local cap = makePart({ name = "ChimneyCap", size = Vector3.new(2.8, 0.6, 2.8), cf = at(1.8, top + 13.2, 1.8), material = Enum.Material.Neon,
		color = c3(Palette.SmelterMouth), parent = smelter })
	makePart({ name = "HopperFrame", size = Vector3.new(1.2, 5, 0.3), cf = at(2.6, top + 4, -3.7), material = Enum.Material.Metal,
		color = c3(Palette.HopperFrame), parent = smelter })
	local fill = makePart({ name = "HopperFill", size = Vector3.new(0.8, 0.05, 0.2), cf = at(2.6, top + 1.7, -3.9), material = Enum.Material.Neon,
		color = c3(Palette.HopperFill), parent = smelter })
	makePart({ name = "SmelterGrate", size = Vector3.new(3.8, 0.4, 1.2), cf = at(0, top + 1.4, -4.2), material = Enum.Material.DiamondPlate,
		color = c3(Palette.Chimney), parent = smelter })
	Fx.sparkle(cap, c3(Palette.SmelterMouth)) -- signature particles: the chimney sparks
	local note = Instance.new("BillboardGui")
	note.Name = "HopperNote"
	note.Size = UDim2.fromOffset(150, 34)
	note.StudsOffset = Vector3.new(0, 4, 0)
	note.AlwaysOnTop = false
	note.MaxDistance = 90
	note.Enabled = false
	local noteText = Instance.new("TextLabel")
	noteText.BackgroundTransparency = 0.3
	noteText.BackgroundColor3 = Color3.fromRGB(30, 26, 20)
	noteText.Size = UDim2.fromScale(1, 1)
	noteText.Font = Enum.Font.GothamBlack
	noteText.TextScaled = true
	noteText.TextColor3 = c3(Palette.HopperFull)
	noteText.Text = "Hopper full!"
	noteText.Parent = note
	note.Parent = smelter:FindFirstChild("HopperFrame")
	smelter.Parent = model

	-- the Collector dish (hidden at level 0)
	local dishModel = Instance.new("Model")
	dishModel.Name = "Dish"
	local rim = makePart({ name = "DishRim", shape = Enum.PartType.Cylinder, size = Vector3.new(0.12, 2, 2), cf = at(0, top + 0.06, 0) * UPRIGHT,
		material = Enum.Material.Neon, color = c3(Palette.DishRim), transparency = 1, parent = dishModel })
	makePart({ name = "DishFloor", shape = Enum.PartType.Cylinder, size = Vector3.new(0.14, 1, 1), cf = at(0, top + 0.07, 0) * UPRIGHT,
		material = Enum.Material.Glass, color = c3(Palette.DishFloor), transparency = 1, parent = dishModel })
	local dishLight = Fx.attachGlow(rim, c3(Palette.DishRim), 1.2, 26) -- interactive things read as interactive
	dishLight.Enabled = false
	dishModel.Parent = model

	-- the Beacon tower
	local beacon = Instance.new("Model")
	beacon.Name = "Beacon"
	local base = makePart({ name = "BeaconBase", shape = Enum.PartType.Cylinder, size = Vector3.new(2, 5, 5), cf = at(P.Beacon.x, top + 1, P.Beacon.z) * UPRIGHT,
		material = Enum.Material.Marble, color = c3(Palette.BeaconBase), collide = true, parent = beacon })
	local beam = makePart({ name = "BeaconBeam", shape = Enum.PartType.Cylinder, size = Vector3.new(10, 0.8, 0.8),
		cf = at(P.Beacon.x, top + 7, P.Beacon.z) * UPRIGHT, material = Enum.Material.Neon, color = c3(Config.Env.Bands[1].beam), parent = beacon })
	local segs = Instance.new("Folder")
	segs.Name = "Segments"
	segs.Parent = beacon
	local crown = makePart({ name = "Crown", shape = Enum.PartType.Cylinder, size = Vector3.new(0.6, 4.2, 4.2), cf = at(P.Beacon.x, top + 3, P.Beacon.z) * UPRIGHT,
		material = Enum.Material.Neon, color = c3(Palette.Crown) })
	local beaconLight = Instance.new("PointLight")
	beaconLight.Name = "BeaconLight"
	beaconLight.Range = 22
	beaconLight.Brightness = 1.4
	beaconLight.Color = c3(Config.Env.Bands[1].beam)
	beaconLight.Parent = base
	beacon.Parent = model

	-- the Star Chart: a frame with a public title plate and a face the owner's client draws rows on
	local boardModel = Instance.new("Model")
	boardModel.Name = "Board"
	local boardPos = at(P.Board.x, top + 4.5, P.Board.z).Position
	local arrivalPos = at(P.Arrival.x, top + 4.5, P.Arrival.z).Position
	local facing = CFrame.lookAt(boardPos, arrivalPos) -- Front face toward the arrival
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
	title.TextColor3 = c3(Palette.Crown)
	title.Text = "⭐ STAR CHART"
	title.Parent = plate
	plate.Parent = frame
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StarChartPrompt"
	prompt.ObjectText = "⭐ Star Chart"
	prompt.ActionText = "Switch Public / Friends"
	prompt.MaxActivationDistance = Config.Board.PromptDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = face
	boardModel.Parent = model

	-- the owner sign above the rim
	local post = makePart({ name = "Sign", size = Vector3.new(0.6, 6, 0.6), cf = at(P.Sign.x, top + 3, P.Sign.z), material = Enum.Material.Wood,
		color = c3(Palette.Sign), parent = model })
	local sign = Instance.new("BillboardGui")
	sign.Name = "OwnerSign"
	sign.Size = UDim2.fromOffset(220, 44)
	sign.StudsOffset = Vector3.new(0, 5, 0)
	sign.MaxDistance = 200
	local signText = Instance.new("TextLabel")
	signText.BackgroundTransparency = 1
	signText.Size = UDim2.fromScale(1, 1)
	signText.Font = Enum.Font.GothamBlack
	signText.TextScaled = true
	signText.TextColor3 = Color3.fromRGB(255, 255, 255)
	signText.TextStrokeTransparency = 0.4
	signText.Text = "Free plot"
	signText.Parent = sign
	sign.Parent = post

	local meteorsFolder = Instance.new("Folder")
	meteorsFolder.Name = "Meteors"
	meteorsFolder.Parent = model

	model.Parent = plotsFolder
	plots[k] = {
		k = k,
		cf = cf,
		model = model,
		arrival = pad,
		fill = fill,
		note = note,
		dishRim = rim,
		dishFloor = dishModel:FindFirstChild("DishFloor"),
		dishLight = dishLight,
		beam = beam,
		beaconLight = beaconLight,
		segments = segs,
		crown = crown,
		boardFace = face,
		title = title,
		prompt = prompt,
		signText = signText,
		meteorsFolder = meteorsFolder,
		owner = nil :: Player?,
		meteors = {} :: { Meteor },
		nextSpawnAt = nil :: number?,
		firstPending = true,
		starMeteor = nil :: Meteor?,
		at = at,
	}
end

for k = 1, W.Plots do
	buildPlot(k)
end
plotsFolder.Parent = workspace -- every plot, with its SpawnLocation, exists before anyone can join

--============================================================================ sessions
type Session = {
	plr: Player,
	plot: any,
	data: any,
	loaded: boolean,
	canSave: boolean,
	lockedElsewhere: boolean,
	token: string?,
	pending: boolean,
	lastSave: number,
	trace: any,
	lastHand: number,
	rateEma: number,
	lastStateAt: number,
	grantPending: boolean,
	boardLast: number?,
	boardWriteAt: number,
	savedBeacon: number,
	savedBeaconAt: number,
	rl: { [string]: any },
	toastAt: { [string]: number },
	leaving: boolean,
	leader: any,
	info: Folder,
	view: any,
	-- REVIEW-1
	writing: boolean, -- a profile write is in flight (writes are serialised per session)
	loadedRaw: any, -- the record's data exactly as the load read it (the lock re-check compares against it)
	lockChanged: boolean, -- the lock cleared but another server had written meanwhile: never saves
	handPicked: boolean, -- a hand pickup happened this session (the load then keeps the session's own clock)
	friendsFetching: boolean, -- a GetFriendsAsync for this viewer is in flight
	fullEma: number, -- the share of recent time the hopper was full (Economy.fullEma); the star listens to it
	lastBest: string?, -- the star as last pushed: a change is pushed at once, before any refusal can quote it
}
local sessions: { [Player]: Session } = {}

local function toast(plr: Player, text: string)
	ToastR:FireClient(plr, text)
end
-- A toast at most once per `every` seconds per reason (refusals that repeat every poll).
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

local function rarityName(r: string): string
	return (string.upper(string.sub(r, 1, 1)) .. string.sub(r, 2))
end

--============================================================================ plot visuals
local function beaconHeight(L: number): number
	return 10 + 1.5 * math.min(L, 60)
end

local function updateBeacon(plot: any, d: any)
	local L = d.beacon
	local band = Config.Env.Bands[Economy.bandIndex(Config, L)]
	local h = beaconHeight(L)
	local top = W.DiscTopY
	plot.beam.Size = Vector3.new(h, 0.8 + 0.02 * math.min(L, 60), 0.8 + 0.02 * math.min(L, 60))
	plot.beam.CFrame = plot.at(P.Beacon.x, top + 2 + h / 2, P.Beacon.z) * UPRIGHT
	plot.beam.Color = c3(band.beam)
	plot.beaconLight.Color = c3(band.beam)
	-- one ring per SegmentEvery levels, up to MaxSegments (the part budget)
	local want = math.min(Config.Beacon.MaxSegments, math.floor(L / Config.Beacon.SegmentEvery))
	local have = #plot.segments:GetChildren()
	for i = have + 1, want do
		makePart({ name = "Segment_" .. i, shape = Enum.PartType.Cylinder, size = Vector3.new(1.2, 3.6, 3.6),
			cf = plot.at(P.Beacon.x, top + 2 + i * (h / (want + 1)), P.Beacon.z) * UPRIGHT, material = Enum.Material.Metal,
			color = c3(Palette.BeaconSegment), parent = plot.segments })
	end
	for i, seg in plot.segments:GetChildren() do
		if i > want then
			seg:Destroy()
		else
			local n = tonumber(string.match(seg.Name, "%d+")) or i
			local sp = seg :: BasePart
			sp.CFrame = plot.at(P.Beacon.x, top + 2 + n * (h / (want + 1)), P.Beacon.z) * UPRIGHT
		end
	end
	-- the gold crown, once the Falling Star is caught (everyone can see it)
	if d.star == 2 then
		plot.crown.CFrame = plot.at(P.Beacon.x, top + 2 + h + 0.8, P.Beacon.z) * UPRIGHT
		plot.crown.Parent = plot.model:FindFirstChild("Beacon")
	else
		plot.crown.Parent = nil
	end
end

local function updateDish(plot: any, d: any, awake: boolean)
	-- called every tick; writes only when the level or the awake state changed (no replication churn)
	local memo = tostring(d.collector) .. (if awake then "a" else "s")
	if plot.dishMemo == memo then return end
	plot.dishMemo = memo
	local r = Economy.dishRadius(Config, d.collector)
	if r <= 0 then
		plot.dishRim.Transparency = 1
		plot.dishFloor.Transparency = 1
		plot.dishLight.Enabled = false
		return
	end
	local top = W.DiscTopY
	plot.dishRim.Size = Vector3.new(0.12, 2 * r, 2 * r)
	plot.dishRim.CFrame = plot.at(0, top + 0.06, 0) * UPRIGHT
	plot.dishFloor.Size = Vector3.new(0.14, 2 * r - 1.2, 2 * r - 1.2)
	plot.dishFloor.CFrame = plot.at(0, top + 0.07, 0) * UPRIGHT
	-- awake: a bright rim; asleep: dim (the HUD says how to wake it)
	plot.dishRim.Transparency = if awake then 0.45 else 0.8
	plot.dishFloor.Transparency = if awake then 0.75 else 0.9
	plot.dishLight.Enabled = awake
end

local function updateHopper(plot: any, d: any)
	local cap = Economy.hopperCap(Config, d.smelter)
	local frac = math.clamp(d.hopper / cap, 0, 1)
	local full = d.hopper >= cap
	-- the gauge moves in 2% steps: a tick that changes less writes nothing
	local memo = math.floor(frac * 50) + (if full then 1000 else 0)
	if plot.hopperMemo == memo then return end
	plot.hopperMemo = memo
	local h = math.max(0.05, 4.6 * frac)
	local top = W.DiscTopY
	plot.fill.Size = Vector3.new(0.8, h, 0.2)
	plot.fill.CFrame = plot.at(2.6, top + 1.7 + h / 2, -3.9)
	plot.fill.Color = c3(if full then Palette.HopperFull else Palette.HopperFill)
	if plot.note.Enabled ~= full then plot.note.Enabled = full end
end

local function resetPlotVisuals(plot: any)
	local blank = Save.defaults()
	updateBeacon(plot, blank)
	updateDish(plot, blank, false)
	updateHopper(plot, blank)
	plot.signText.Text = "Free plot"
	plot.title.Text = "⭐ STAR CHART"
end

for _, plot in plots do
	resetPlotVisuals(plot)
end

--============================================================================ state to the owner
-- The HUD's star: the steady rule, overruled by a hopper that has actually been full (REVIEW-1), but only once a
-- first machine is bought: before that the first-minutes hint says "buy the ★ upgrade" and it is the Beacon
-- (DESIGN [M8]); one rare fills a fresh 12-ore hopper, and the star sat on the Smelter (measured: the first
-- purchase at 81 s instead of 40 in 1 of 40 walks).
local function bestOf(s: Session): (string, number)
	local d = s.data
	local measured = if d.beacon + d.collector + d.smelter > 0 then s.fullEma else nil
	return Economy.bestNext(Config, d.beacon, d.collector, d.smelter, measured)
end

local function pushState(s: Session, force: boolean?)
	local t = now()
	if not force and t - s.lastStateAt < MC.StateSeconds then return end
	s.lastStateAt = t
	local d = s.data
	local best, bestPrice = bestOf(s)
	s.lastBest = best
	local cap = Economy.hopperCap(Config, d.smelter)
	StateR:FireClient(s.plr, {
		loaded = s.loaded,
		saving = s.canSave,
		lockedElsewhere = s.lockedElsewhere,
		lockChanged = s.lockChanged,
		plot = s.plot.k,
		stardust = d.stardust,
		lifetime = d.lifetime,
		beacon = d.beacon,
		collector = d.collector,
		smelter = d.smelter,
		hopper = d.hopper,
		hopperCap = cap,
		hopperFull = d.hopper >= cap,
		melt = Economy.smeltRate(Config, d.smelter),
		rate = s.rateEma * 60, -- Stardust minted per minute, a measured moving average
		awake = if d.collector > 0 then Meteors.awakeLeft(Config, t, s.lastHand) else -1,
		star = d.star,
		starCores = d.starCores,
		tutorial = d.tutorial,
		best = best,
		bestPrice = bestPrice,
		prices = {
			beacon = Economy.beaconPrice(Config, d.beacon),
			collector = Economy.collectorPrice(Config, d.collector),
			smelter = Economy.smelterPrice(Config, d.smelter),
		},
	})
	if s.leader then
		s.leader.beacon.Value = d.beacon
		s.leader.stardust.Value = math.floor(d.stardust)
	end
end

--============================================================================ saving
-- Every write lands only while the record still carries this session's token. A late releasing write
-- (BindToClose, then PlayerRemoving; or an autosave queued behind a newer session's load) is cancelled by
-- the transform returning nil. Returns true when the profile reached the store.
--
-- WRITES ARE SERIALISED PER SESSION (REVIEW-1). A write packs the profile BEFORE its UpdateAsync yields, so
-- two overlapping writes could land in the wrong order and the older copy overwrite the newer one. Since the
-- Falling Star's catch writes from its own thread, that could happen. `waitTurn` = wait for the write in
-- flight (the grant, the catch, a leave); without it (the periodic flush) a write that finds one in flight
-- skips, leaving `pending` set for the next tick. `pending` is cleared BEFORE the yield, so a change made
-- while the write is in flight is written next tick (steal-a-cryptid REVIEW-1 A4), and set again on failure.
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
	-- the Collector's awake time is saved with the profile, so a rejoin cannot re-arm it (REVIEW-1)
	s.data.awake = Meteors.awakeLeft(Config, now(), s.lastHand)
	local packed = Save.pack(s.data)
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
			-- read at commit time: once the player is leaving, no write of this session locks the record again,
			-- whichever of its queued writes lands last (steal-a-cryptid REVIEW-1 A3)
			old.lockUntil = if release or s.leaving then 0 else os.time() + Config.Save.LockSeconds
			return old
		end)
	end)
	s.writing = false
	if not ok then
		s.pending = true
		warn("[MeteorDrop] save failed for " .. s.plr.Name .. ": " .. tostring(err))
		return false
	end
	if lost then
		s.canSave = false
		warn("[MeteorDrop] " .. s.plr.Name .. ": a newer session owns this profile; this session stops saving.")
		toast(s.plr, Config.Tutorial.NotSaving)
		pushState(s, true)
		return false
	end
	s.lastSave = now()
	s.savedBeacon = packed.beacon
	s.savedBeaconAt = packed.beaconAt
	return true
end

-- Deep equality of two values read from the store (tables of strings, numbers, booleans).
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

-- Hand back a lock this session took for a player who is already gone (owner-checked by its token).
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

-- The load (REVIEW-1, steal-a-cryptid's REVIEW-1 fix). A DataStore call can fail for a moment and succeed
-- the next: one failed UpdateAsync at the join used to hand a Beacon-21 veteran a blank plot for the whole
-- session. So it is tried LoadAttempts times, LoadRetrySeconds x attempt apart, and only then does the
-- session play unsaved. A LOCK is waited for too: a player who reconnects after a drop usually finds the old
-- server's lock on the record for the few seconds its leave-write takes, and a lock read once at the join
-- used to cost the whole session. The record is re-read every LockRetrySeconds for up to LockWaitSeconds
-- (the player is told once), and a session that still starts read-only re-checks later (recheckLock).
local function load(s: Session)
	local plr = s.plr
	local fresh = s.data -- whatever was earned while the load was in flight is merged in, never lost
	if store == nil then
		s.canSave = false
		s.loaded = true
		return
	end
	local token = HttpService:GenerateGUID(false)
	local acquired, raw, lockedByOther = false, nil, false
	local ok = false
	local failures, waited = 0, 0
	while true do
		acquired, raw, lockedByOther = false, nil, false
		local err
		ok, err = pcall(function()
			store:UpdateAsync(key(plr.UserId), function(old)
				old = old or {}
				raw = old.data
				local t = os.time()
				-- The transform may run more than once: every flag is set on every run.
				lockedByOther = (tonumber(old.lockUntil) or 0) > t and old.jobId ~= game.JobId
				if lockedByOther then
					acquired = false
					return nil -- another live session holds it: do not touch the record
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
			warn(string.format("[MeteorDrop] load failed for %s (attempt %d of %d): %s", plr.Name, failures,
				Config.Save.LoadAttempts, tostring(err)))
			if failures >= Config.Save.LoadAttempts then break end
			task.wait(Config.Save.LoadRetrySeconds * failures)
		end
		if s.leaving then break end
	end
	if s.leaving then
		-- the player left while the load was in flight: give the lock straight back (owner-checked), so a
		-- rejoin on another server within LockSeconds is not read-only for nothing
		if ok and acquired then releaseLock(plr.UserId, token) end
		return
	end
	local d = Save.normalise(Config, if ok then raw else nil)
	d.stardust += fresh.stardust
	d.lifetime += fresh.lifetime
	d.hopper += fresh.hopper
	s.data = d
	-- the Collector carries on from the saved awake time; a hand pickup made during the load wins
	if ok and type(raw) == "table" and not s.handPicked then
		s.lastHand = now() - (Config.Collector.IdleSeconds - d.awake)
	end
	if not ok then
		s.canSave = false
	else
		s.canSave = acquired
		s.token = if acquired then token else nil
		s.lockedElsewhere = lockedByOther
		s.loadedRaw = raw
	end
	s.loaded = true
end

-- REVIEW-1, after the join wait: a session that started read-only because another server held the lock
-- re-reads the record every LockRecheckSeconds. When the lock is gone AND the saved data is exactly what this
-- session loaded (the other server's leave-write was late, or it crashed), nothing can be lost by carrying
-- on: the session takes the lock with a fresh token in the same transform and saves from then on, its
-- progress since the join included. When the data CHANGED (the other server wrote after this session read
-- it), writing would erase that, so the session stays unsaved for good and tells the player to rejoin.
local function recheckLock(s: Session)
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
			warn("[MeteorDrop] save failed (lock re-check) for " .. s.plr.Name .. ": " .. tostring(err))
		elseif state == "taken" then
			if sessions[s.plr] ~= s or s.leaving then
				releaseLock(s.plr.UserId, token) -- left while the write was in flight
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

--============================================================================ the Star Chart
local publicCache = { rows = nil :: { any }?, at = -math.huge }
local nameCache: { [number]: string } = {}
local friendCache: { [number]: { value: number?, at: number } } = {}
local friendJobs: { [Player]: { { id: number, gen: number } } } = {} -- each viewer's reads still to make
local friendTurn: { Player } = {} -- viewers with reads waiting, in round-robin order
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

-- A player's own row, from what has been SAVED (the board never shows a level this server has not written).
local function ownValue(s: Session): number?
	if s.savedBeacon <= 0 then return s.boardLast end
	return Board.encode(Config, s.savedBeacon, s.savedBeaconAt)
end

local function rowsPayload(ranked: { any }, viewerId: number): { any }
	local out = {}
	for _, r in ranked do
		table.insert(out, {
			rank = r.rank,
			name = nameOf(r.userId),
			beacon = r.beacon,
			emoji = Board.emojiFor(Config, r.beacon),
			you = r.userId == viewerId,
		})
	end
	return out
end

local function sendBoard(s: Session)
	local view = s.view
	local d = s.data
	local payload: any = { mode = view.mode, footer = "Lifetime " .. Economy.short(d.lifetime) .. " Stardust", rows = {}, status = "" }
	if view.mode == "public" then
		refreshPublic()
		local rows = table.clone(publicCache.rows or {})
		local mine = ownValue(s)
		local present = false
		for _, r in rows do
			if r.userId == s.plr.UserId then present = true end
		end
		local ranked = Board.rank(Config, rows)
		payload.rows = rowsPayload(ranked, s.plr.UserId)
		if not present and mine ~= nil then
			local b = Board.decode(Config, mine)
			table.insert(payload.rows, { rank = 0, name = s.plr.Name, beacon = b, emoji = Board.emojiFor(Config, b), you = true })
		end
		if #payload.rows == 0 then
			payload.status = if boardStore then "Be the first on the Star Chart: buy a Beacon level." else "The Star Chart is unavailable right now."
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
		local ranked = Board.rank(Config, rows)
		payload.rows = rowsPayload(ranked, s.plr.UserId)
		if #payload.rows == 0 then
			table.insert(payload.rows, { rank = 0, name = s.plr.Name, beacon = d.beacon, emoji = Board.emojiFor(Config, d.beacon), you = true })
		end
		if view.unavailable then
			payload.status = Board.UNAVAILABLE
		elseif view.fetching then
			payload.status = Board.loadingText(0, 0)
		elseif view.done < view.total then
			payload.status = Board.loadingText(view.done, view.total)
		elseif friendsOn == 0 then
			payload.status = Board.emptyFriendsText(Config, d.beacon)
		end
	end
	BoardR:FireClient(s.plr, payload)
end

-- The friends view (REVIEW-1). One FIFO queue for the whole server let a 200-friend list hold everyone else's
-- view for minutes (203 s measured; 1001 s after 33 prompt presses, which also read each of the same 200 keys
-- about 5 times). Now: reads wait PER VIEWER and are served round-robin, one per FriendReadsPerSecond tick;
-- every request carries its view's generation, so a newer press (or a switch back to Public) drops the old
-- one's reads, also when its GetFriendsAsync lands after the yield; at most one GetFriendsAsync per viewer is
-- in flight; and the score cache is checked when a read is DUE, not only when it is queued.
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
	view.gen += 1 -- a second request replaces the first
	dropFriendJobs(s.plr)
	view.friendValues = {}
	view.done, view.total, view.unavailable, view.fetching = 0, 0, false, true
	sendBoard(s)
	if s.friendsFetching then return end -- the fetch in flight fills this view when it lands
	s.friendsFetching = true
	local plr = s.plr
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
	-- re-read after the yield: the viewer may have left, or switched back to Public meanwhile
	if sessions[plr] ~= s or view.mode ~= "friends" then return end
	if not ok or type(ids) ~= "table" then
		view.fetching = false
		view.unavailable = true
		sendBoard(s)
		return
	end
	fillFriends(s, ids) -- for the view as it is NOW (its latest generation)
end

-- Serve what the cache already holds (no request), then at most one real read, for the viewer whose turn it is.
local function stepFriendQueue()
	if #friendTurn == 0 or boardStore == nil then return end
	local t = now()
	local served = 0
	while #friendTurn > 0 and served < Config.Board.FriendsCap do
		local viewer = friendTurn[1]
		local s = sessions[viewer]
		local jobs = friendJobs[viewer]
		-- reads nobody is waiting for any more (the viewer left, switched back, or asked again)
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
	local s = sessions[viewer] -- re-read after the yield
	if s and s.view.mode == "friends" and s.view.gen == job.gen then
		s.view.friendValues[job.id] = value
		s.view.done += 1
		sendBoard(s)
	end
end

local function boardWrite(s: Session, force: boolean)
	if boardStore == nil or not s.canSave then return end
	-- only what has been SAVED is ranked, so the board never shows a level the profile does not have
	if not Board.shouldWrite(Config, s.boardLast, s.savedBeacon) then return end
	if not force and now() - s.boardWriteAt < Config.Board.WriteMinInterval then return end
	local v = Board.encode(Config, s.savedBeacon, s.savedBeaconAt)
	local ok = pcall(function()
		boardStore:SetAsync(key(s.plr.UserId), v)
	end)
	if ok then
		s.boardLast = v
		s.boardWriteAt = now()
		publicCache.at = -math.huge -- the next view re-reads, so the writer sees themselves
	end
end

--============================================================================ meteors
local function lyingCount(plot: any): number
	local n = 0
	for _, m in plot.meteors do
		if m.fate == "lie" and not m.star then n += 1 end
	end
	return n
end

local function destroyMeteor(plot: any, m: Meteor)
	local i = table.find(plot.meteors, m)
	if i then table.remove(plot.meteors, i) end
	if m.part then
		m.part:Destroy()
		m.part = nil
	end
	if plot.starMeteor == m then plot.starMeteor = nil end
end

local function glowPart(plot: any, m: Meteor, name: string, color: Color3)
	local p = (kit:FindFirstChild("Glow") :: BasePart):Clone()
	p.Name = name
	p.Color = color
	p.CFrame = plot.at(m.x, W.DiscTopY + 0.06, m.z) * UPRIGHT
	p.Parent = plot.meteorsFolder
	m.part = p
end

local function announce(plot: any, s: Session, t: number)
	local d = s.data
	local L = d.beacon
	local x, z, rarity
	if plot.firstPending then
		plot.firstPending = false
		x, z = Meteors.firstPoint(Config)
		rarity = "common"
	else
		x, z = Meteors.landingPoint(Config, rand)
		rarity = Meteors.rollRarity(Config, Economy.bandIndex(Config, L), rand)
	end
	plot.nextSpawnAt = t + Meteors.gap(Config, Economy.spawnInterval(Config, L), rand)
	local ore = Economy.oreOf(Config, L, rarity)
	local fate = Meteors.fate(Config, {
		x = x, z = z, rarity = rarity,
		dishRadius = Economy.dishRadius(Config, d.collector),
		awake = Meteors.awake(Config, t, s.lastHand),
		lying = lyingCount(plot),
	})
	if fate == "burn" then
		local wx, wz = PlotGeom.toWorld(Config, plot.k, x, z)
		FxR:FireClient(s.plr, { kind = "burn", x = wx, z = wz, rarity = rarity })
		return
	end
	local m: Meteor = { part = nil, x = x, z = z, rarity = rarity, ore = ore, landAt = t + MC.FallSeconds, landed = false, fate = fate, star = false }
	glowPart(plot, m, "Incoming_" .. rarityName(rarity), c3(Config.Rarities.Defs[rarity].color))
	table.insert(plot.meteors, m)
end

local function spawnStar(plot: any, s: Session, t: number)
	-- only on a plot this session still owns: every caller reaches here after a yield (a write, a board read),
	-- and a star spawned on a plot freed meanwhile was paid to whoever claimed it next (REVIEW-1)
	if s.leaving or sessions[s.plr] ~= s or s.plot ~= plot or plot.owner ~= s.plr then return end
	if plot.starMeteor ~= nil then return end
	local sx, sz = P.Showcase.x, P.Showcase.z
	local m: Meteor = { part = nil, x = sx, z = sz, rarity = "legendary", ore = Economy.oreOf(Config, s.data.beacon, "legendary"),
		landAt = t + MC.StarFallSeconds, landed = false, fate = "lie", star = true }
	glowPart(plot, m, "Incoming_Star", c3(Config.Rarities.StarColor))
	table.insert(plot.meteors, m)
	plot.starMeteor = m
	FxR:FireClient(s.plr, { kind = "starFalling" })
end

local function land(plot: any, s: Session, m: Meteor)
	m.landed = true
	local d = s.data
	if m.fate == "dish" then
		local res = Economy.dishCatch(Config, d, m.ore)
		local wx, wz = PlotGeom.toWorld(Config, plot.k, m.x, m.z)
		FxR:FireClient(s.plr, { kind = if res == "hopper" then "dish" else "bounce", x = wx, z = wz, rarity = m.rarity })
		if res == "hopper" then s.pending = true end
		destroyMeteor(plot, m)
		return
	end
	-- it lies where it landed: the glow becomes the rock
	local p = m.part
	if p == nil then return end
	if m.star then
		local star = (kit:FindFirstChild("Star") :: BasePart):Clone()
		star.Name = "FallingStar"
		star.CFrame = plot.at(m.x, W.DiscTopY + star.Size.Y / 2, m.z)
		star.Parent = plot.meteorsFolder
		p:Destroy()
		m.part = star
		return
	end
	local def = Config.Rarities.Defs[m.rarity]
	p.Name = "Meteor_" .. rarityName(m.rarity);
	(p :: Part).Shape = Enum.PartType.Ball
	p.Size = Vector3.new(def.size, def.size, def.size)
	p.CFrame = plot.at(m.x, W.DiscTopY + def.size / 2, m.z)
	p.Transparency = 0
	p.Material = if m.rarity == "legendary" or m.rarity == "epic" then Enum.Material.Neon
		elseif m.rarity == "rare" then Enum.Material.Glass else Enum.Material.Slate
	if m.rarity == "legendary" then
		-- a gold beam straight up, so a Star Core is seen from anywhere on the plot (no light: the budget)
		local a0 = Instance.new("Attachment")
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 50, 0)
		a1.Parent = p
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(c3(def.color))
		beam.Width0 = 2
		beam.Width1 = 0.5
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Parent = p
	end
end

local function tutorialStep(s: Session, from: number, to: number)
	if s.data.tutorial == from then
		s.data.tutorial = to
		s.pending = true
	end
end

local function collect(plot: any, s: Session, m: Meteor, t: number): boolean
	local d = s.data
	local res = Economy.collect(Config, d, m.rarity, m.ore)
	if res == "refused" then
		-- the refusal follows the HUD's star, never contradicts it (Economy.fullText, REVIEW-1)
		toastEvery(s, "full", MC.FullToastSeconds, Economy.fullText(Config, d, (bestOf(s))))
		return false
	end
	s.lastHand = t
	s.handPicked = true
	s.pending = true
	if res == "instant" then
		s.minted += m.ore
		d.starCores += 1
	end
	tutorialStep(s, 0, 1)
	local wp = m.part and m.part.Position or plot.at(m.x, 1, m.z).Position
	if m.star then
		Save.catchStar(d)
		FxR:FireClient(s.plr, { kind = "starCaught", ore = m.ore })
		AnnounceR:FireAllClients({ text = displayName(s.plr) .. " caught a Falling Star!" })
		updateBeacon(plot, d)
		-- star = 2 with its Stardust, in one write, in its OWN thread: this runs inside the shared 10 Hz tick,
		-- and a write that yields here froze every plot for its latency (REVIEW-1: 3 s at a 3 s write)
		task.spawn(writeProfile, s, false, true)
	else
		FxR:FireClient(s.plr, { kind = "zip", x = wp.X, y = wp.Y, z = wp.Z, rarity = m.rarity, instant = res == "instant" })
	end
	destroyMeteor(plot, m)
	return true
end

--============================================================================ the Falling Star grant
-- The one-time reward, gated on its own atomic write (checklist: grant only inside an atomic flush, and
-- refuse when you cannot persist). A saving session writes star = 1 with the rest of the profile and
-- spawns the star only after that write lands; if it fails the player is told and it retries every flush
-- tick. A non-saving session spawns it at once: a grant that is never written cannot be redeemed twice.
local function tryGrant(s: Session)
	if not s.grantPending or not s.loaded then return end
	local d = s.data
	if d.star ~= 0 then
		s.grantPending = false
		return
	end
	if s.canSave then
		d.star = 1
		if not writeProfile(s, false, true) then
			if s.canSave then
				d.star = 0 -- nothing was written; nothing is granted yet
				toastEvery(s, "starWait", 20, "🌠 Your Falling Star is waiting: it falls as soon as your progress saves.")
				return
			end
			-- the write was refused because another session took the profile: this one no longer saves
		end
	else
		d.star = 1
	end
	s.grantPending = false
	spawnStar(s.plot, s, now())
	pushState(s, true)
end

--============================================================================ players
local function claimPlot(plr: Player): any
	for k = 1, W.Plots do
		if plots[k].owner == nil then
			plots[k].owner = plr
			return plots[k]
		end
	end
	return nil
end

local function freePlot(plot: any)
	for i = #plot.meteors, 1, -1 do
		destroyMeteor(plot, plot.meteors[i])
	end
	plot.starMeteor = nil
	plot.owner = nil
	plot.nextSpawnAt = nil
	plot.firstPending = true
	resetPlotVisuals(plot)
end

local function onCharacter(plr: Player, char: Model)
	-- SPAWN-ORDER.md: the engine parents and places the character one frame AFTER CharacterAdded, and wins.
	-- RespawnLocation already told it where; this only waits (bounded) and corrects a stray placement.
	local frames = 0
	while char.Parent == nil and frames < P.SpawnWaitFrames do
		task.wait(1 / 60)
		frames += 1
	end
	local s = sessions[plr] -- re-read: anything can change across the yield
	if s == nil or plr.Character ~= char then return end
	local plot = s.plot
	-- whatever cleared or moved it, the next spawn goes to this player's own pad again
	if plr.RespawnLocation ~= plot.arrival then plr.RespawnLocation = plot.arrival end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = Config.Trace.WalkSpeed end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pad = plot.arrival.Position
	if hrp then
		local p = hrp.Position
		local off = math.sqrt((p.X - pad.X) ^ 2 + (p.Z - pad.Z) ^ 2)
		if off > P.SpawnCorrectStuds then
			local stand = Vector3.new(pad.X, pad.Y + 0.5 + P.RootAbovePad, pad.Z)
			local ahead = plot.at(0, stand.Y, 0).Position
			hrp.CFrame = CFrame.lookAt(stand, ahead)
		end
	end
	-- the trusted position restarts at a point the SERVER chose, never one the client supplied
	s.trace = Trace.new(Config, { x = P.Arrival.x, y = pad.Y + 0.5 + P.RootAbovePad, z = P.Arrival.z })
	if plot.nextSpawnAt == nil then
		plot.nextSpawnAt = now() + MC.FirstMeteorAt
	end
end

local function makeLeaderstats(plr: Player, s: Session)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local b = Instance.new("IntValue")
	b.Name = "Beacon"
	b.Parent = ls
	local st = Instance.new("IntValue")
	st.Name = "Stardust"
	st.Parent = ls
	ls.Parent = plr
	s.leader = { beacon = b, stardust = st }
end

local function afterLoad(s: Session)
	local plr, plot, d = s.plr, s.plot, s.data
	if s.leaving or sessions[plr] ~= s then return end
	updateBeacon(plot, d)
	updateDish(plot, d, true)
	updateHopper(plot, d)
	s.savedBeacon = if s.canSave then d.beacon else 0
	s.savedBeaconAt = d.beaconAt
	-- the board's "last value": one read of the player's own key, so a rejoin never writes a lower or equal one
	if boardStore then
		local ok, v = pcall(function()
			return boardStore:GetAsync(key(plr.UserId))
		end)
		if ok and type(v) == "number" then s.boardLast = v end
		-- re-read after the yield: the player may have left, and the plot gone to someone else (REVIEW-1)
		if s.leaving or sessions[plr] ~= s then return end
	end
	if s.lockedElsewhere then task.spawn(recheckLock, s) end
	if not s.canSave then
		toast(plr, if s.lockedElsewhere then Config.Tutorial.NotSavingLocked else Config.Tutorial.NotSaving)
	end
	-- a star granted and never caught falls again; a level past the star without a grant gets one
	if d.star == 1 then
		spawnStar(plot, s, now())
	elseif d.star == 0 and d.beacon >= STAR_BEACON then
		s.grantPending = true
		tryGrant(s)
	end
	pushState(s, true)
	sendBoard(s)
end

local function onPlayerAdded(plr: Player)
	if sessions[plr] then return end
	local plot = claimPlot(plr)
	if plot == nil then
		warn("[MeteorDrop] a ninth player arrived; all 8 plots are taken (Players.MaxPlayers must be 8): " .. plr.Name)
		plr:Kick(W.KickMessage)
		return
	end
	-- BEFORE ANY YIELD: tell the engine where this player's character goes (SPAWN-ORDER.md, preferred pattern)
	plr.RespawnLocation = plot.arrival
	local info = Instance.new("Folder")
	info.Name = tostring(plr.UserId)
	info.Parent = plotInfoRoot
	local s: Session = {
		plr = plr,
		plot = plot,
		data = Save.defaults(),
		loaded = false,
		canSave = false,
		lockedElsewhere = false,
		token = nil,
		pending = false,
		lastSave = now(),
		trace = nil,
		lastHand = now(), -- a session starts awake
		rateEma = 0,
		minted = 0,
		lastStateAt = -math.huge,
		grantPending = false,
		boardLast = nil,
		boardWriteAt = -math.huge,
		savedBeacon = 0,
		savedBeaconAt = 0,
		rl = {},
		toastAt = {},
		leaving = false,
		leader = nil,
		info = info,
		view = { mode = "public", friendValues = {}, done = 0, total = 0, unavailable = false, fetching = false, gen = 0 },
		writing = false,
		loadedRaw = nil,
		lockChanged = false,
		handPicked = false,
		friendsFetching = false,
		fullEma = 0,
		lastBest = nil,
	} :: any
	sessions[plr] = s
	makeLeaderstats(plr, s)
	plot.signText.Text = "⭐ " .. displayName(plr)
	plot.title.Text = "⭐ " .. displayName(plr) .. "'s STAR CHART"
	info:SetAttribute("Plot", plot.k)
	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)
	if plr.Character then
		task.spawn(onCharacter, plr, plr.Character)
	end
	task.spawn(function()
		load(s)
		afterLoad(s)
	end)
end

local function onPlayerRemoving(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	s.leaving = true
	if s.loaded then
		writeProfile(s, true, true)
		boardWrite(s, true)
	end
	freePlot(s.plot)
	s.info:Destroy()
	sessions[plr] = nil
	dropFriendJobs(plr)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
end

game:BindToClose(function()
	for _, s in sessions do
		if s.loaded then
			writeProfile(s, true, true)
			boardWrite(s, true)
		end
	end
end)

--============================================================================ the only client -> server remote
local function rateOk(s: Session, which: string): boolean
	local t = now()
	local b = s.rl[which]
	if b == nil or t - b.start >= 1 then
		b = { start = t, n = 0 }
		s.rl[which] = b
	end
	b.n += 1
	if b.n > Config.Remotes.MaxPerSecond then
		toastEvery(s, "slow", Config.Remotes.SlowToastSeconds, "Slow down: one tap is enough.")
		return false
	end
	return true
end

BuyR.OnServerEvent:Connect(function(plr: Player, kind: any)
	local s = sessions[plr]
	if s == nil then return end
	if not rateOk(s, "buy") then return end
	if not s.loaded then
		toast(plr, Economy.refusalText(Config, "loading"))
		return
	end
	local d = s.data
	local ok, why, price = Economy.buy(Config, d, kind)
	if not ok then
		toast(plr, Economy.refusalText(Config, why, price, d.stardust))
		return
	end
	s.pending = true
	tutorialStep(s, 1, 2)
	if kind == "beacon" then
		d.beaconAt = os.time()
		updateBeacon(s.plot, d)
		if d.beacon >= STAR_BEACON and d.star == 0 then
			s.grantPending = true
			tryGrant(s)
		end
	elseif kind == "collector" then
		tutorialStep(s, 2, 3)
		updateDish(s.plot, d, Meteors.awake(Config, now(), s.lastHand))
	else
		s.fullEma = 0 -- a new Smelter: the hopper's record starts again
		updateHopper(s.plot, d)
	end
	pushState(s, true)
end)

--============================================================================ the Star Chart prompt
for _, plot in plots do
	plot.prompt.Triggered:Connect(function(plr: Player)
		local s = sessions[plr]
		if s == nil then return end
		if plot.owner ~= plr then
			local who = if plot.owner then displayName(plot.owner :: Player) .. "'s" else "a free plot's"
			toast(plr, "This is " .. who .. " Star Chart. Yours is by your own arrival pad.")
			return
		end
		if not rateOk(s, "board") then return end
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
local function stepPlot(plot: any, s: Session, t: number, dt: number)
	local d = s.data
	local plr = s.plr
	-- 1. the trusted position follows the claimed root at walking pace (plot-local studs)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and s.trace then
		local p = hrp.Position
		local lx, lz = PlotGeom.toLocal(Config, plot.k, p.X, p.Z)
		Trace.step(s.trace, { x = lx, y = p.Y, z = lz }, dt)
	end
	-- 2. the sky
	if plot.nextSpawnAt ~= nil and t >= plot.nextSpawnAt then
		announce(plot, s, t)
	end
	-- 3. landings
	for i = #plot.meteors, 1, -1 do
		local m = plot.meteors[i]
		if m and not m.landed and t >= m.landAt then
			land(plot, s, m)
		end
	end
	-- the star listens to the hopper (REVIEW-1); a change reaches the HUD before any refusal below quotes it
	s.fullEma = Economy.fullEma(Config, s.fullEma, d.hopper >= Economy.hopperCap(Config, d.smelter), dt)
	if s.loaded and (bestOf(s)) ~= s.lastBest then pushState(s, true) end
	-- 4. pickups, tested against the TRUSTED position only
	if s.trace then
		local tx, tz = s.trace.x, s.trace.z
		for i = #plot.meteors, 1, -1 do
			local m = plot.meteors[i]
			if m and m.landed and m.fate == "lie" and Meteors.inPickup(Config, tx, tz, m.x, m.z) then
				collect(plot, s, m, t)
			end
		end
	end
	-- 5. the Smelter
	local melted = Economy.melt(Config, d, dt)
	if melted > 0 then s.pending = true end
	local minted = melted + s.minted
	s.minted = 0
	if dt > 0 then
		local a = 1 - 0.5 ^ (dt / MC.RateHalfLife)
		s.rateEma += (minted / dt - s.rateEma) * a
	end
	-- 6. visuals and the debug folder
	local awake = Meteors.awake(Config, t, s.lastHand)
	updateHopper(plot, d)
	if d.collector > 0 then updateDish(plot, d, awake) end
	local info = s.info
	info:SetAttribute("NextSpawnAt", plot.nextSpawnAt or -1)
	info:SetAttribute("TrustedX", if s.trace then s.trace.x else 0)
	info:SetAttribute("TrustedZ", if s.trace then s.trace.z else 0)
	info:SetAttribute("CollectorAwakeUntil", s.lastHand + Config.Collector.IdleSeconds)
	info:SetAttribute("Hopper", d.hopper)
	pushState(s, false)
end

-- A visitor on someone else's plot, next to a meteor there, is told why nothing happens.
local function visitorToasts()
	for plr, s in sessions do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local p = hrp.Position
			local k = PlotGeom.plotAt(Config, p.X, p.Z)
			local plot = k and plots[k]
			if plot and plot.owner ~= nil and plot.owner ~= plr then
				local lx, lz = PlotGeom.toLocal(Config, plot.k, p.X, p.Z)
				for _, m in plot.meteors do
					if m.landed and m.fate == "lie" and Meteors.inPickup(Config, lx, lz, m.x, m.z) then
						toastEvery(s, "visitor", MC.VisitorToastSeconds,
							"Only " .. displayName(plot.owner :: Player) .. " can collect here. Your plot has the ⭐ over it.")
						break
					end
				end
			end
		end
	end
end

task.spawn(function()
	local last = now()
	while true do
		task.wait(MC.PollSeconds)
		local t = now()
		local dt = math.clamp(t - last, 0, 1)
		last = t
		for _, plot in plots do
			local owner = plot.owner
			local s = owner and sessions[owner]
			if s then
				local ok, err = pcall(stepPlot, plot, s, t, dt)
				if not ok and not plot.warned then
					plot.warned = true -- once: a broken plot must not flood the output
					warn("[MeteorDrop] plot " .. plot.k .. " tick failed: " .. tostring(err))
				end
			end
		end
		visitorToasts()
	end
end)

--============================================================================ saving and the board, on their own clocks
task.spawn(function()
	while true do
		task.wait(Config.Save.FlushTickSeconds)
		local t = now()
		for _, s in sessions do
			if s.loaded and not s.leaving then
				if s.grantPending then
					tryGrant(s)
				elseif s.canSave and (s.pending or t - s.lastSave >= Config.Save.AutosaveSeconds) then
					writeProfile(s, false)
				end
			end
		end
	end
end)

task.spawn(function()
	local tick = 0
	while true do
		task.wait(1)
		tick += 1
		for _, s in sessions do
			if s.loaded and not s.leaving then
				boardWrite(s, false)
				-- every 30 s each owner's board is re-sent: the public view refreshes from its 60 s cache, and a
				-- client that connected after the first send (a slow HUD) still gets its rows
				if tick % 30 == 0 then sendBoard(s) end
			end
		end
		stepFriendQueue()
	end
end)
