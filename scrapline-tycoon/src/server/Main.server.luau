-- SCRAPLINE TYCOON — the authoritative server (ServerScriptService).
--
-- Junk pours out of a chute onto a U-shaped belt on each player's own plot and rides past six stations to a dock
-- that sells whatever arrives. Players build, upgrade and twin stations, fix machines that sputter, and Recycle a
-- line that ships rockets fast enough for a Gold Bolt (+50 % value forever). DESIGN.md is the spec; every number
-- lives in Config; the line's flow is Line.luau, the shop Economy.luau, the jams Jams.luau, the prestige Recycle.luau.
--
-- What the server owns, and why nothing a client says can inflate the Top Recyclers board:
--   * cash is minted only here, every Line.TickSeconds, from the line's flow (Line.income), which reads only
--     server state: station levels and twins (changed only by a Buy this file priced and validated) and jams
--     (cleared only by a Fix this file checked against the TRUSTED position, Trace.luau);
--   * a Gold Bolt is minted only inside a recycle's ONE owner-checked UpdateAsync, only when the server's own
--     flow ships the required rocket rate, and never in a session that is not saving;
--   * the jam clock and its Random.new() never leave the server: the State payload carries only a live sputter,
--     and ServerStorage.PlotInfo (debug values for headless checks) is the only place JamIn is written down;
--   * client -> server remotes are Buy(kind, station), Fix(station, machine), Recycle(), BoardView(mode): string
--     whitelists, price / unlock / range checks, 8 calls/s, and a toast for every refusal.
-- Nothing secret replicates: no attribute is set on anything under workspace or ReplicatedStorage.
--
-- Spawn (robloxemu/SPAWN-ORDER.md, the preferred pattern): every plot's arrival pad is a real enabled
-- SpawnLocation built before anyone joins, PlayerAdded sets plr.RespawnLocation synchronously, and CharacterAdded
-- only waits (bounded) and corrects a character the engine put somewhere else.
--
-- Saving (meteor-drop-tycoon's code after its REVIEW-1): one UpdateAsync load that takes the lock with a fresh
-- owner token; every later write lands only while the record still carries that token; writes serialised per
-- session; canSave only while holding the lock. The recycle is the game's one irreversible action: every check
-- first, then one owner-checked write of the whole new run and bolts + 1, swapped in only when that write lands.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService") -- GenerateGUID only (session tokens); no HTTP

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Line = require(ReplicatedStorage:WaitForChild("Line"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Jams = require(ReplicatedStorage:WaitForChild("Jams"))
local Recycle = require(ReplicatedStorage:WaitForChild("Recycle"))
local Save = require(ReplicatedStorage:WaitForChild("Save"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local PlotGeom = require(ReplicatedStorage:WaitForChild("PlotGeom"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Trace = require(ReplicatedStorage:WaitForChild("Trace"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

-- The look, first thing: dusty midday, equal to band 1, so every client's first glide takes over with no jump.
Fx.applyLighting(Fx.Presets.Junkyard)

local W, P, ST = Config.World, Config.Plot, Config.Stations
local Palette = Config.Palette
local IDS = ST.Order
local FLOOR = W.FloorTopY

-- tick() is the in-session clock (robloxemu advances it; os.clock barely moves headless). os.time() for
-- everything persisted.
local function now(): number
	return tick()
end

local rng = Random.new() -- the server's one source of randomness (the jam targets and gaps); never seeded
local function rand(): number
	return rng:NextNumber()
end

local function finite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
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

local function textLabel(parent: Instance, text: string, colour: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = colour
	t.TextStrokeTransparency = 0.4
	t.Text = text
	t.Parent = parent
	return t
end

--============================================================================ remotes
local remotes = Instance.new("Folder")
remotes.Name = "ScraplineRemotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local StateR = remote("State") -- server -> owner: their own PRESENT state
local ToastR = remote("Toast") -- server -> one player: a sentence
local FxR = remote("Fx") -- server -> owner: a sputter, a jam, a fix, a new band, a purchase, a recycle
local BoardR = remote("Board") -- server -> viewer: their own board view
local LineStateR = remote("LineState") -- server -> all: every plot's stations (public facts), for belt items
local AnnounceR = remote("Announce") -- server -> all: a first-rocket lift-off, a recycle
local BuyR = remote("Buy") -- client -> server
local FixR = remote("Fix")
local RecycleR = remote("Recycle")
local BoardViewR = remote("BoardView")
remotes.Parent = ReplicatedStorage

--============================================================================ stores (all pcall'd)
-- GetDataStore raises in an unpublished place; unwrapped, it kills this script.
local store: any = nil
local boardStore: any = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(Config.Save.Store)
	end)
	if ok then store = s else warn("[Scrapline] DataStore unavailable; progress will not be saved: " .. tostring(s)) end
	local okB, b = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Board.Store)
	end)
	if okB then boardStore = b else warn("[Scrapline] board store unavailable: " .. tostring(b)) end
end
local function key(userId: number): string
	return "u_" .. tostring(userId)
end

--============================================================================ ServerStorage: the kit and the debug folder
local kit = Instance.new("Folder")
kit.Name = "MachineKit" -- one model per machine type; the server clones these (anomaly-observatory's rule)
kit.Parent = ServerStorage
local plotInfoRoot = Instance.new("Folder")
plotInfoRoot.Name = "PlotInfo" -- debug values for headless checks and tools; never replicated
plotInfoRoot.Parent = ServerStorage

-- A machine: Body (straddles the belt), Accent (its working part, Neon), Cap. At most Budget.MachineParts parts.
-- Emitters (sputter sparks, jam smoke) and the JAMMED sign start off; the level plate is a SurfaceGui.
for t, id in IDS do
	local h = ST.MachineHeight[t]
	local m = Instance.new("Model")
	m.Name = "Kit_" .. id
	local body = makePart({ name = "Body", size = Vector3.new(P.MachineAcross, h, P.MachineAlong), cf = CFrame.new(0, h / 2, 0),
		material = Enum.Material.Metal, color = c3(ST.Colors[t]), collide = true, shadow = true, parent = m })
	m.PrimaryPart = body
	local accent = c3(ST.Accents[t])
	-- each station's working part: shredder teeth, furnace mouth, press head, cutter laser head, assembler arm, rocket dome
	local shapes = {
		{ size = Vector3.new(P.MachineAcross + 0.4, 0.8, 1.2), cf = CFrame.new(0, h - 1.2, -P.MachineAlong / 2 - 0.3) },
		{ size = Vector3.new(3.6, 2.4, 0.4), cf = CFrame.new(0, 2.4, -P.MachineAlong / 2 - 0.2) },
		{ size = Vector3.new(P.MachineAcross - 1, 1.2, P.MachineAlong - 1), cf = CFrame.new(0, h + 0.6, 0) },
		{ size = Vector3.new(1.4, 1.4, 1.4), cf = CFrame.new(0, h + 0.7, 0) },
		{ size = Vector3.new(1, 1, P.MachineAlong + 1.6), cf = CFrame.new(P.MachineAcross / 2 - 1, h - 1, 0) },
		{ size = Vector3.new(5, 5, 5), cf = CFrame.new(0, h + 1.5, 0), shape = Enum.PartType.Ball },
	}
	local sh = shapes[t]
	makePart({ name = "Accent", size = sh.size, cf = sh.cf, shape = sh.shape, material = Enum.Material.Neon, color = accent, parent = m })
	makePart({ name = "Cap", size = Vector3.new(P.MachineAcross - 2, 0.6, P.MachineAlong - 2), cf = CFrame.new(0, h + 0.3, 0),
		material = Enum.Material.DiamondPlate, color = c3(Palette.BeltRail), parent = m })
	local sparks = Fx.emitter(body, {
		Name = "Sparks", Rate = 30, Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(60, 60), Color = ColorSequence.new(c3(Palette.Sputter)), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }),
	})
	sparks.Enabled = false
	local smoke = Fx.emitter(body, {
		Name = "Smoke", Rate = 8, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(2, 4),
		Color = ColorSequence.new(c3(Palette.Smoke)), LightEmission = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
	})
	smoke.Enabled = false
	local sign = Instance.new("BillboardGui")
	sign.Name = "JamSign"
	sign.Size = UDim2.fromOffset(150, 40)
	sign.StudsOffset = Vector3.new(0, h / 2 + 3, 0)
	sign.MaxDistance = 140
	sign.Enabled = false
	local signText = textLabel(sign, "⚠ JAMMED", c3(Palette.JamSign))
	signText.Name = "JamText"
	sign.Parent = body
	local plate = Instance.new("SurfaceGui")
	plate.Name = "LevelPlate"
	plate.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plate.PixelsPerStud = 30
	local lv = textLabel(plate, "Lv 1", Color3.fromRGB(255, 255, 255))
	lv.Name = "LevelText"
	lv.Size = UDim2.fromScale(1, 0.3)
	lv.BackgroundTransparency = 0.2
	lv.BackgroundColor3 = c3(Palette.LevelPlate)
	plate.Parent = body
	m.Parent = kit
end

-- The rocket that lifts off the pad (everyone's client animates it from Announce; the server keeps the model).
do
	local rocket = Instance.new("Model")
	rocket.Name = "Kit_Rocket"
	makePart({ name = "RocketBody", shape = Enum.PartType.Cylinder, size = Vector3.new(6, 2, 2), cf = CFrame.new(0, 3, 0) * UPRIGHT,
		material = Enum.Material.SmoothPlastic, color = c3(Palette.Rocket), parent = rocket })
	rocket.Parent = kit
end

--============================================================================ the world: ground, the Scrap Market, six plots
local baseplate = makePart({ name = "Baseplate", size = Vector3.new(W.BaseplateSize, 2, W.BaseplateSize),
	cf = CFrame.new(0, W.GroundY - 1, 0), material = Enum.Material.Ground, color = c3(Palette.Ground), collide = true })
baseplate.Parent = workspace

-- REVIEW-2 R7: the edge of the world is a wall, not a drop. Invisible (Roblox's camera ignores a part this
-- transparent, so it never pushes the camera in), collidable, on the plate's four edges.
do
	local edge = Instance.new("Folder")
	edge.Name = "WorldEdge"
	local half, th, ht = W.BaseplateSize / 2, W.EdgeWallThickness, W.EdgeWallHeight
	local long = W.BaseplateSize + 2 * th
	for i, e in { { half + th / 2, 0, th, long }, { -half - th / 2, 0, th, long }, { 0, half + th / 2, long, th }, { 0, -half - th / 2, long, th } } do
		makePart({ name = "Wall_" .. i, size = Vector3.new(e[3], ht, e[4]), cf = CFrame.new(e[1], W.GroundY - 2 + ht / 2, e[2]),
			transparency = 1, collide = true, parent = edge })
	end
	edge.Parent = workspace
end

do
	-- a junk mountain and a dead crane: a landmark for orientation and thumbnails; nothing interactive
	local market = Instance.new("Model")
	market.Name = "ScrapMarket"
	local heaps = { { 0, 0, 22, 9 }, { 9, 6, 14, 7 }, { -8, 7, 13, 6 }, { 4, -9, 12, 6 }, { -6, -8, 10, 5 }, { 12, -3, 9, 4 } }
	for i, hp in heaps do
		makePart({ name = "Heap_" .. i, shape = Enum.PartType.Ball, size = Vector3.new(hp[3], hp[4] * 2, hp[3]),
			cf = CFrame.new(hp[1], 0, hp[2]), material = Enum.Material.CorrodedMetal,
			color = c3(if i % 2 == 0 then Palette.MarketRust else Palette.Market), collide = true, parent = market })
	end
	makePart({ name = "CraneTower", size = Vector3.new(2, 30, 2), cf = CFrame.new(-14, 15, 14), material = Enum.Material.Metal,
		color = c3(Palette.Crane), collide = true, parent = market })
	makePart({ name = "CraneArm", size = Vector3.new(2, 2, 24), cf = CFrame.new(-14, 30, 4) * CFrame.Angles(math.rad(-12), 0, 0),
		material = Enum.Material.Metal, color = c3(Palette.Crane), parent = market })
	makePart({ name = "CraneCab", size = Vector3.new(4, 3, 4), cf = CFrame.new(-14, 27, 14), material = Enum.Material.Metal,
		color = c3(Palette.MarketRust), parent = market })
	makePart({ name = "CraneHook", size = Vector3.new(0.4, 12, 0.4), cf = CFrame.new(-14, 22, -6), material = Enum.Material.Metal,
		color = c3(Palette.Smoke), parent = market })
	for i = 1, 4 do
		local a = i * math.pi / 2 + 0.4
		makePart({ name = "Tyre_" .. i, shape = Enum.PartType.Cylinder, size = Vector3.new(1.4, 4, 4),
			cf = CFrame.new(math.sin(a) * 24, 1.2, math.cos(a) * 24) * CFrame.Angles(0, a, 0), material = Enum.Material.Rubber,
			color = Color3.fromRGB(40, 40, 44), collide = true, parent = market })
	end
	makePart({ name = "MarketSign", size = Vector3.new(14, 3, 0.6), cf = CFrame.new(0, 21, 0), material = Enum.Material.Neon,
		color = c3(Palette.ChuteGlow), parent = market })
	market.Parent = workspace
end

local plots = {}
local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"

local function gradePaint(plot: any, bolts: number)
	local g = Config.Grades[Recycle.grade(Config, bolts)]
	local mat = (Enum.Material :: any)[g.material] or Enum.Material.Metal
	for _, part in plot.graded do
		part.Color = c3(g.color)
		part.Material = mat
		part.Reflectance = g.reflectance
	end
end

local function buildPlot(k: number)
	local cx, cz = PlotGeom.centre(Config, k)
	local cf = CFrame.lookAt(Vector3.new(cx, 0, cz), Vector3.new(0, 0, 0)) -- LookVector = local -Z, at the market
	local function at(lx: number, ly: number, lz: number): CFrame
		return cf * CFrame.new(lx, ly, lz)
	end
	local model = Instance.new("Model")
	model.Name = "Plot_" .. k
	local graded = {}

	makePart({ name = "Floor", size = Vector3.new(2 * P.HalfX, FLOOR, 2 * P.HalfZ), cf = at(0, FLOOR / 2, 0),
		material = Enum.Material.Concrete, color = c3(Palette.Floor), collide = true, parent = model })
	-- painted kerb lines round the yard (flat: nothing to trip on)
	for i, e in { { 0, -P.HalfZ + 0.5, 2 * P.HalfX, 1 }, { 0, P.HalfZ - 0.5, 2 * P.HalfX, 1 }, { -P.HalfX + 0.5, 0, 1, 2 * P.HalfZ }, { P.HalfX - 0.5, 0, 1, 2 * P.HalfZ } } do
		makePart({ name = "Curb_" .. i, size = Vector3.new(e[3], 0.06, e[4]), cf = at(e[1], FLOOR + 0.03, e[2]),
			material = Enum.Material.SmoothPlastic, color = c3(Palette.Curb), parent = model })
	end
	-- the belt: two legs and the U-turn's chords (PlotGeom.beltSegments), top at Belt.topY
	local beltH = P.Belt.topY - FLOOR
	for _, seg in PlotGeom.beltSegments(Config) do
		local centre = at(seg.x, FLOOR + beltH / 2, seg.z).Position
		local ahead = at(seg.x + seg.ax, FLOOR + beltH / 2, seg.z + seg.az).Position
		makePart({ name = seg.name, size = Vector3.new(2 * seg.hx, beltH, 2 * seg.hz), cf = CFrame.lookAt(centre, ahead),
			material = Enum.Material.DiamondPlate, color = c3(Palette.Belt), collide = true, parent = model })
	end
	-- the chute (junk pours in), front-left; its mouth glows and carries the plot's one chute light
	local C_ = P.Chute
	local chute = makePart({ name = "ChuteBody", size = Vector3.new(C_.size, C_.height, C_.size), cf = at(C_.x, FLOOR + C_.height / 2, C_.z),
		material = Enum.Material.CorrugatedPlate, color = c3(Config.Grades[1].color), collide = true, parent = model })
	table.insert(graded, chute)
	local mouth = makePart({ name = "ChuteMouth", size = Vector3.new(4, 3, 0.4), cf = at(C_.x, FLOOR + 2, C_.z + C_.size / 2 + 0.2),
		material = Enum.Material.Neon, color = c3(Palette.ChuteGlow), parent = model })
	Fx.attachGlow(mouth, c3(Palette.ChuteGlow), 1.2, 18)
	Fx.sparkle(mouth, c3(Palette.ChuteGlow)) -- signature particles: the junk glints as it pours
	local magnet = makePart({ name = "ChuteMagnet", shape = Enum.PartType.Cylinder, size = Vector3.new(1, 6, 6),
		cf = at(C_.x, FLOOR + C_.height + 3, C_.z) * UPRIGHT, material = Enum.Material.Metal, color = c3(Palette.Crane), parent = model })
	-- the shipping dock, front-right: low enough to stand on
	local D = P.Dock
	local dock = makePart({ name = "Dock", size = Vector3.new(D.size, D.height, D.size), cf = at(D.x, FLOOR + D.height / 2, D.z),
		material = Enum.Material.CorrugatedPlate, color = c3(Config.Grades[1].color), collide = true, parent = model })
	table.insert(graded, dock)
	makePart({ name = "DockStrip", size = Vector3.new(D.size, 0.3, 0.6), cf = at(D.x, FLOOR + D.height + 0.15, D.z + D.size / 2 - 0.3),
		material = Enum.Material.Neon, color = c3(Palette.DockGlow), parent = model })
	makePart({ name = "DockCrate", size = Vector3.new(2.5, 2.5, 2.5), cf = at(D.x + 2.2, FLOOR + D.height + 1.25, D.z - 2.2),
		material = Enum.Material.Wood, color = Color3.fromRGB(150, 120, 80), collide = true, parent = model })
	-- the launch pad, beside the dock
	local LP = P.LaunchPad
	makePart({ name = "LaunchPad", shape = Enum.PartType.Cylinder, size = Vector3.new(LP.height, 2 * LP.radius, 2 * LP.radius),
		cf = at(LP.x, FLOOR + LP.height / 2, LP.z) * UPRIGHT, material = Enum.Material.Concrete, color = c3(Palette.LaunchPad), collide = true, parent = model })
	makePart({ name = "LaunchRing", shape = Enum.PartType.Cylinder, size = Vector3.new(0.1, 2 * LP.radius - 1, 2 * LP.radius - 1),
		cf = at(LP.x, FLOOR + LP.height + 0.05, LP.z) * UPRIGHT, material = Enum.Material.Neon, color = c3(Palette.LaunchRing), transparency = 0.4, parent = model })
	-- the factory wall at the back, its chimneys and the SCRAPLINE sign (its neon is the band's accent)
	local WL = P.Wall
	local wall = makePart({ name = "FactoryWall", size = Vector3.new(2 * WL.halfX, WL.height, WL.depth), cf = at(0, FLOOR + WL.height / 2, WL.z),
		material = Enum.Material.CorrugatedPlate, color = c3(Config.Grades[1].color), collide = true, parent = model })
	table.insert(graded, wall)
	for i, sx in { -1, 1 } do
		local ch = makePart({ name = "Chimney_" .. i, shape = Enum.PartType.Cylinder, size = Vector3.new(WL.chimneyHeight, 4, 4),
			cf = at(sx * WL.chimneyX, FLOOR + WL.chimneyHeight / 2, WL.z) * UPRIGHT, material = Enum.Material.CorrugatedPlate,
			color = c3(Config.Grades[1].color), collide = true, parent = model })
		table.insert(graded, ch)
	end
	local sign = makePart({ name = "ScraplineSign", size = Vector3.new(24, 3, 0.4), cf = at(0, FLOOR + WL.height - 2.5, WL.z - WL.depth / 2 - 0.2),
		material = Enum.Material.Neon, color = c3(Config.Env.Bands[1].accent), parent = model })
	do
		local sg = Instance.new("SurfaceGui")
		sg.Name = "SignText"
		sg.Face = Enum.NormalId.Front -- the face that looks into the yard: the part's -Z, its LookVector (REVIEW-1 B4)
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 30
		textLabel(sg, "SCRAPLINE", Color3.fromRGB(30, 30, 36))
		sg.Parent = sign
	end
	-- the gantry crane: two rails high over the yard and a bridge (hazards hang from it; the client moves a trolley)
	local CH = P.CraneHeight
	for i, sx in { -1, 1 } do
		makePart({ name = "CraneRail_" .. i, size = Vector3.new(1.2, 1.2, 2 * P.HalfZ), cf = at(sx * (P.HalfX - 2), CH, 0),
			material = Enum.Material.Metal, color = c3(Palette.Crane), parent = model })
		makePart({ name = "CranePost_" .. i, size = Vector3.new(1.2, CH, 1.2), cf = at(sx * (P.HalfX - 2), CH / 2, -P.HalfZ + 1),
			material = Enum.Material.Metal, color = c3(Palette.Crane), collide = true, parent = model })
	end
	makePart({ name = "CraneBridge", size = Vector3.new(2 * P.HalfX - 4, 1.4, 1.6), cf = at(0, CH + 0.8, 4),
		material = Enum.Material.Metal, color = c3(Palette.Crane), parent = model })

	-- the arrival pad: a real, enabled SpawnLocation, facing up the U (+Z local)
	local pad = Instance.new("SpawnLocation")
	pad.Name = "Arrival"
	pad.Anchored = true
	pad.CanCollide = true
	pad.Enabled = true
	pad.Neutral = true
	pad.Duration = 0 -- no force-field bubble (needs-Studio: confirm it removes it)
	pad.Size = Vector3.new(P.ArrivalSize, P.ArrivalTopY, P.ArrivalSize)
	pad.CFrame = at(P.Arrival.x, P.ArrivalTopY / 2, P.Arrival.z) * CFrame.Angles(0, math.pi, 0)
	pad.Material = Enum.Material.Marble
	pad.Color = c3(Palette.Arrival)
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Parent = model

	-- the Top Recyclers board: a frame on two posts, a public title plate, and a face the owner's client draws on
	local boardModel = Instance.new("Model")
	boardModel.Name = "Board"
	local B = P.Board
	local boardPos = at(B.x, FLOOR + B.height / 2 + 0.5, B.z).Position
	local arrivalPos = at(P.Arrival.x, FLOOR + B.height / 2 + 0.5, P.Arrival.z).Position
	local facing = CFrame.lookAt(boardPos, arrivalPos) -- Front face toward the arrival
	makePart({ name = "BoardFrame", size = Vector3.new(B.width + 0.6, B.height, 0.5), cf = facing * CFrame.new(0, 0, 0.3),
		material = Enum.Material.Metal, color = c3(Palette.BoardFrame), collide = true, parent = boardModel })
	local face = makePart({ name = "BoardFace", size = Vector3.new(B.width, B.height - 0.8, 0.2), cf = facing * CFrame.new(0, -0.2, 0),
		material = Enum.Material.SmoothPlastic, color = c3(Palette.BoardFace), parent = boardModel })
	for i, sx in { -1, 1 } do
		-- two legs behind the frame's edges, from the floor to its top
		makePart({ name = "BoardPost_" .. i, size = Vector3.new(0.4, B.height + 0.5, 0.4),
			cf = facing * CFrame.new(sx * (B.width / 2), -0.25, 0.6),
			material = Enum.Material.Metal, color = c3(Palette.BoardFrame), parent = boardModel })
	end
	local plate = Instance.new("SurfaceGui")
	plate.Name = "TitlePlate"
	plate.Face = Enum.NormalId.Front
	plate.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plate.PixelsPerStud = 40
	local title = textLabel(plate, "♻ TOP RECYCLERS", c3(Palette.LaunchRing))
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.1)
	plate.Parent = face
	boardModel.Parent = model

	-- six station consoles inside the U (the next one to build glows) and the station models on the belt
	local consoles, stations = {}, {}
	for t, id in IDS do
		local x, z = PlotGeom.consolePos(Config, t)
		local CS = P.ConsoleSize
		consoles[t] = makePart({ name = "Console_" .. id, size = Vector3.new(CS.x, CS.y, CS.z), cf = at(x, FLOOR + CS.y / 2, z),
			material = Enum.Material.SmoothPlastic, color = c3(Palette.Console), collide = true, parent = model })
		local folder = Instance.new("Model")
		folder.Name = "Station_" .. string.gsub(ST.Names[t], " ", "")
		folder.Parent = model
		stations[t] = folder
	end
	local nextGlow = Instance.new("PointLight")
	nextGlow.Name = "NextGlow"
	nextGlow.Color = c3(Palette.ConsoleNext)
	nextGlow.Range = 14
	nextGlow.Brightness = 1.6
	nextGlow.Enabled = false
	nextGlow.Parent = consoles[1]

	-- the owner sign over the chute
	local ownerSign = Instance.new("BillboardGui")
	ownerSign.Name = "OwnerSign"
	ownerSign.Size = UDim2.fromOffset(220, 44)
	ownerSign.StudsOffset = Vector3.new(0, 5, 0)
	ownerSign.MaxDistance = 260
	local ownerText = textLabel(ownerSign, "Free factory", Color3.fromRGB(255, 255, 255))
	ownerSign.Parent = magnet

	model.Parent = plotsFolder
	plots[k] = {
		k = k,
		cf = cf,
		at = at,
		model = model,
		arrival = pad,
		graded = graded,
		sign = sign,
		consoles = consoles,
		stations = stations,
		machines = {}, -- [t] = { [m] = Model }
		nextGlow = nextGlow,
		ownerText = ownerText,
		title = title,
		face = face,
		owner = nil :: Player?,
	}
end

for k = 1, W.Plots do
	buildPlot(k)
end
plotsFolder.Parent = workspace -- every plot, with its SpawnLocation, exists before anyone can join

--============================================================================ plot visuals
local function machineName(t: number, m: number): string
	return "Machine_" .. string.gsub(ST.Names[t], " ", "") .. "_" .. (if m == 1 then "a" else "b")
end

-- Make the plot's machines match the station states (n, level, jams). Writes only what changed.
local function syncMachines(plot: any, d: any)
	for t, id in IDS do
		local st = d.stations[id]
		plot.machines[t] = plot.machines[t] or {}
		for m = 1, 2 do
			local have = plot.machines[t][m]
			if m <= st.n then
				if have == nil then
					local proto = kit:FindFirstChild("Kit_" .. id) :: Model
					local mdl = proto:Clone()
					mdl.Name = machineName(t, m)
					local mx, mz = PlotGeom.machinePos(Config, t, m)
					local base = plot.at(mx, FLOOR, mz)
					for _, part in mdl:GetDescendants() do
						if part:IsA("BasePart") then
							part.CFrame = base * part.CFrame
						end
					end
					-- the level plate faces into the U (local +X for the left leg, -X for the right)
					local plate = mdl:FindFirstChild("Body") and (mdl :: any).Body:FindFirstChild("LevelPlate")
					if plate then plate.Face = if t <= 3 then Enum.NormalId.Right else Enum.NormalId.Left end
					mdl.Parent = plot.stations[t]
					plot.machines[t][m] = mdl
					have = mdl
				end
				local body = (have :: any).Body
				local lv = body.LevelPlate.LevelText
				local text = "Lv " .. st.L
				if lv.Text ~= text then lv.Text = text end
				local state = st.jam[m]
				local sparks, smoke, sign = body.Sparks, body.Smoke, body.JamSign
				if sparks.Enabled ~= (state == 1) then sparks.Enabled = state == 1 end
				if smoke.Enabled ~= (state == 2) then smoke.Enabled = state == 2 end
				if sign.Enabled ~= (state == 2) then sign.Enabled = state == 2 end
			elseif have ~= nil then
				have:Destroy()
				plot.machines[t][m] = nil
			end
		end
	end
	-- the next station's console glows (interactive things read as interactive)
	local nextT = nil
	for t, id in IDS do
		if d.stations[id].n == 0 then
			nextT = t
			break
		end
	end
	for t, c in plot.consoles do
		local glow = t == nextT
		local mat = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		if c.Material ~= mat then
			c.Material = mat
			c.Color = c3(if glow then Palette.ConsoleNext else Palette.Console)
		end
	end
	if nextT then
		if plot.nextGlow.Parent ~= plot.consoles[nextT] then plot.nextGlow.Parent = plot.consoles[nextT] end
		plot.nextGlow.Enabled = true
	else
		plot.nextGlow.Enabled = false
	end
end

local function signAccent(plot: any, tier: number)
	local band = Config.Env.Bands[EnvBands.indexAt(Config.Env.Bands, tier)]
	local col = c3(band.accent)
	if plot.sign.Color ~= col then plot.sign.Color = col end
end

local function resetPlotVisuals(plot: any)
	local blank = Save.defaults(Config)
	syncMachines(plot, blank)
	signAccent(plot, 0)
	gradePaint(plot, 0)
	plot.ownerText.Text = "Free factory"
	plot.title.Text = "♻ TOP RECYCLERS"
end

for _, plot in plots do
	resetPlotVisuals(plot)
end

--============================================================================ sessions
local sessions: { [Player]: any } = {}
-- REVIEW-1 A3: the session of a userId that is LEAVING this server and still writing; a rejoin's load waits for it
local leavingByUser: { [number]: any } = {}

local function toast(plr: Player, text: string)
	ToastR:FireClient(plr, text)
end
local function toastEvery(s: any, reason: string, every: number, text: string)
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

local function linesOf(s: any): { any }
	return Line.ordered(Config, s.data.stations)
end

--============================================================================ state to the owner
local function stationRows(s: any, S: { any }, mult: number): { any }
	local d = s.data
	local loads = Line.loads(Config, S)
	local reach, cap = Line.reach(Config, S)
	-- REVIEW-2 R3: what the panel paints green when affordable (Economy.worth: the HUD's colour rule, the server's call)
	local w = Economy.worth(Config, Line, S, d.cash, mult)
	local rows = {}
	for t, id in IDS do
		local st = S[t]
		local prices: any = {}
		local locked = false
		if st.n == 0 then
			if t == 1 or S[t - 1].n > 0 then prices.build = Economy.buildPrice(Config, t) else locked = true end
		else
			if st.n < 2 then prices.twin = Economy.twinPrice(Config, t) end
			if st.L < ST.MaxLevel then prices.up = Economy.upPrice(Config, t, st.L) end
		end
		rows[t] = {
			id = id,
			n = st.n,
			L = st.L,
			jamA = st.jam[1],
			jamB = st.jam[2],
			load = if loads[t] == math.huge then -1 else loads[t], -- -1: every machine jammed
			cap = cap[t],
			reach = reach[t],
			prices = prices,
			worth = { build = w["build:" .. t] == true, twin = w["twin:" .. t] == true, up = w["up:" .. t] == true },
			locked = locked,
		}
	end
	return rows
end

local function pushState(s: any, force: boolean?)
	local t = now()
	-- (a millisecond of slack: the 0.5 s line tick must not miss a 0.5 s throttle by a rounding error and wait a second)
	if not force and t - s.lastStateAt < Config.Line.StateSeconds - 1e-3 then return end
	s.lastStateAt = t
	local d = s.data
	local S = linesOf(s)
	local mult = Line.mult(Config, d.bolts)
	local income, flow = Line.income(Config, S, mult)
	local star = Economy.star(Config, Line, S, d.cash, mult)
	local starOut = nil
	if star then
		starOut = { kind = star.kind, t = star.t, id = IDS[star.t], price = star.price, saving = star.saving,
			wait = Economy.saveSeconds(Config, Line, S, d.cash, mult, star) }
	end
	local bottleneck = Line.bottleneck(Config, S)
	local need = Recycle.requirement(Config, d.bolts)
	local sp = d.jams.sputter
	StateR:FireClient(s.plr, {
		loaded = s.loaded,
		saving = s.canSave,
		lockedElsewhere = s.lockedElsewhere,
		lockChanged = s.lockChanged,
		plot = s.plot.k,
		cash = d.cash,
		income = income,
		mult = mult,
		flow = flow,
		bolts = d.bolts,
		tier = d.tier,
		tutorial = d.tutorial,
		stations = stationRows(s, S, mult),
		bottleneck = bottleneck or 0,
		star = starOut,
		sputter = if sp then { t = sp.t, m = sp.m, left = sp.left } else nil,
		jammed = Jams.jammedCounts(S),
		rocketRate = flow[7],
		recycleNeed = need,
		recycleReady = flow[7] >= need - 1e-9,
		recycling = s.recycling or now() < s.holdUntil,
	})
	if s.leader then
		local cashText = Economy.money(d.cash)
		if s.leader.cash.Value ~= cashText then s.leader.cash.Value = cashText end
		if s.leader.bolts.Value ~= d.bolts then s.leader.bolts.Value = d.bolts end
	end
	s.lastStarKey = if star then star.kind .. star.t .. tostring(star.saving) else ""
end

--============================================================================ every plot's line, for everyone's belt items
local lineDirty = true
local lastLineSend = -math.huge
local function linePayload(): any
	local out = {}
	for k = 1, W.Plots do
		local plot = plots[k]
		local s = plot.owner and sessions[plot.owner]
		local entry: any = { k = k, userId = 0, mult = 1, st = {} }
		if s and s.loaded then
			entry.userId = s.plr.UserId
			entry.mult = Line.mult(Config, s.data.bolts)
			for t, id in IDS do
				local st = s.data.stations[id]
				entry.st[t] = { st.n, st.L, st.jam[1], st.jam[2] }
			end
		else
			for t = 1, 6 do entry.st[t] = { 0, 1, 0, 0 } end
		end
		out[k] = entry
	end
	return out
end
local function broadcastLines(force: boolean?)
	local t = now()
	-- on change at most LineStateSeconds apart, and every LineResendSeconds anyway: a client whose scripts started
	-- after the last send (a slow join) still gets every line
	local due = lineDirty or t - lastLineSend >= Config.Line.LineResendSeconds
	if not force and (not due or t - lastLineSend < Config.Line.LineStateSeconds) then return end
	lineDirty = false
	lastLineSend = t
	LineStateR:FireAllClients(linePayload())
end

--============================================================================ saving
-- Every write lands only while the record still carries this session's token. A late releasing write (BindToClose,
-- then PlayerRemoving; or an autosave queued behind a newer session's load) is cancelled by the transform returning
-- nil. Returns true when the profile reached the store. WRITES ARE SERIALISED PER SESSION (meteor-drop-tycoon
-- REVIEW-1): `waitTurn` waits for the write in flight; without it (the periodic flush) a write that finds one in
-- flight skips, leaving `pending` set for the next tick. `pending` is cleared BEFORE the yield, so a change made
-- while the write is in flight is written next tick, and set again on failure.
local function writeProfile(s: any, release: boolean, waitTurn: boolean?): boolean
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
	local packed = Save.pack(Config, s.data)
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
			-- read at commit time: once the player is leaving, no write of this session locks the record again
			old.lockUntil = if release or s.leaving then 0 else os.time() + Config.Save.LockSeconds
			return old
		end)
	end)
	s.writing = false
	if not ok then
		s.pending = true
		warn("[Scrapline] save failed for " .. s.plr.Name .. ": " .. tostring(err))
		return false
	end
	if lost then
		s.canSave = false
		warn("[Scrapline] " .. s.plr.Name .. ": a newer session owns this profile; this session stops saving.")
		toast(s.plr, Config.Tutorial.NotSaving)
		pushState(s, true)
		return false
	end
	s.lastSave = now()
	s.savedBolts = packed.bolts
	s.savedBoltsAt = packed.boltsAt
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

-- The load (meteor-drop-tycoon REVIEW-1): tried LoadAttempts times, LoadRetrySeconds x attempt apart, before the
-- session plays unsaved; a lock is re-read every LockRetrySeconds for up to LockWaitSeconds at the join.
local function load(s: any)
	local plr = s.plr
	if store == nil then
		s.canSave = false
		s.loaded = true
		return
	end
	-- REVIEW-1 A3: the same user leaving THIS server a moment ago may still be writing. The lock lets this JobId
	-- through, so taking the record now would cancel that write (the owner token) and lose what it carried: wait for
	-- it to land first (bounded).
	local prev = leavingByUser[plr.UserId]
	if prev ~= nil and prev ~= s then
		toast(plr, Config.Tutorial.LeaveWaiting)
		local held = 0
		while leavingByUser[plr.UserId] == prev and held < Config.Save.LeaveWaitSeconds and not s.leaving do
			task.wait(0.1)
			held += 0.1
		end
	end
	-- REVIEW-2 X1: gone while it waited: take nothing. A token taken now would cancel the earlier leave's write.
	if s.leaving then return end
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
			warn(string.format("[Scrapline] load failed for %s (attempt %d of %d): %s", plr.Name, failures,
				Config.Save.LoadAttempts, tostring(err)))
			if failures >= Config.Save.LoadAttempts then break end
			task.wait(Config.Save.LoadRetrySeconds * failures)
		end
		if s.leaving then break end
	end
	if s.leaving then
		if ok and acquired then releaseLock(plr.UserId, token) end
		return
	end
	s.data = Save.normalise(Config, if ok then raw else nil)
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

-- A session that started read-only because another server held the lock re-reads the record every
-- LockRecheckSeconds; it takes over only when the lock is gone AND the data is exactly what it loaded.
local function recheckLock(s: any)
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
			warn("[Scrapline] save failed (lock re-check) for " .. s.plr.Name .. ": " .. tostring(err))
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

--============================================================================ the Top Recyclers board
-- meteor-drop-tycoon's board server code after its REVIEW-1 (per-viewer round-robin friend reads, generations,
-- one GetFriendsAsync per viewer in flight), with the metric renamed to Gold Bolts.
local publicCache = { rows = nil :: { any }?, at = -math.huge }
local nameCache: { [number]: string } = {}
local friendCache: { [number]: { value: number?, at: number } } = {}
local friendJobs: { [Player]: { { id: number, gen: number } } } = {}
local friendTurn: { Player } = {}
local lastFriendRead = -math.huge

-- REVIEW-1 A2: a failed lookup is not retried for NameRetrySeconds and only one lookup per id is ever in flight, so
-- a client spamming BoardView cannot multiply the server's name lookups (and keep a 429 going for everyone).
local nameFailedAt: { [number]: number } = {}
local nameInFlight: { [number]: boolean } = {}
local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then return cached end
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		nameCache[userId] = inServer.Name
		return inServer.Name
	end
	local fallback = "Player " .. tostring(userId)
	local failedAt = nameFailedAt[userId]
	if nameInFlight[userId] or (failedAt ~= nil and now() - failedAt < Config.Board.NameRetrySeconds) then
		return fallback
	end
	nameInFlight[userId] = true
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameInFlight[userId] = nil
	if ok and type(name) == "string" then
		nameCache[userId] = name
		nameFailedAt[userId] = nil
		return name
	end
	nameFailedAt[userId] = now()
	return fallback
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

-- A player's own row, from what has been SAVED (the board never shows a count this server has not written).
local function ownValue(s: any): number?
	if s.savedBolts <= 0 then return s.boardLast end
	return Board.encode(Config, s.savedBolts, s.savedBoltsAt)
end

local function rowsPayload(ranked: { any }, viewerId: number): { any }
	local out = {}
	for _, r in ranked do
		table.insert(out, {
			rank = r.rank,
			name = nameOf(r.userId),
			bolts = r.bolts,
			emoji = Board.emojiFor(Config, r.bolts),
			you = r.userId == viewerId,
		})
	end
	return out
end

local function sendBoard(s: any)
	local view = s.view
	local d = s.data
	local payload: any = { mode = view.mode, footer = string.format("Your factory: %s, %d Gold Bolt%s",
		Config.Grades[Recycle.grade(Config, d.bolts)].name, d.bolts, if d.bolts == 1 then "" else "s"), rows = {}, status = "" }
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
			table.insert(payload.rows, { rank = 0, name = s.plr.Name, bolts = b, emoji = Board.emojiFor(Config, b), you = true })
		end
		if #payload.rows == 0 then
			payload.status = if boardStore then "Be the first on the board: ship rockets, then Recycle for a Gold Bolt."
				else "The board is unavailable right now."
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
			table.insert(payload.rows, { rank = 0, name = s.plr.Name, bolts = d.bolts, emoji = Board.emojiFor(Config, d.bolts), you = true })
		end
		if view.unavailable then
			payload.status = Board.UNAVAILABLE
		elseif view.fetching then
			payload.status = Board.loadingText(0, 0)
		elseif view.done < view.total then
			payload.status = Board.loadingText(view.done, view.total)
		elseif friendsOn == 0 then
			payload.status = Board.emptyFriendsText(Config, d.bolts)
		end
	end
	BoardR:FireClient(s.plr, payload)
end

local function dropFriendJobs(plr: Player)
	friendJobs[plr] = nil
	local i = table.find(friendTurn, plr)
	if i then table.remove(friendTurn, i) end
end

local function fillFriends(s: any, ids: { number })
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

local function startFriends(s: any)
	local view = s.view
	view.gen += 1 -- a second request replaces the first
	dropFriendJobs(s.plr)
	view.friendValues = {}
	view.done, view.total, view.unavailable, view.fetching = 0, 0, false, true
	-- REVIEW-1 A2: the friend list is fetched at most once per FriendListSeconds per viewer (a failed fetch once per
	-- FriendListRetrySeconds), so toggling Friends at the remote limit costs one fetch, not one per toggle
	local list = s.friendList
	if list ~= nil and now() - list.at < (if list.ok then Config.Board.FriendListSeconds else Config.Board.FriendListRetrySeconds) then
		if list.ok then
			fillFriends(s, list.ids)
		else
			view.fetching = false
			view.unavailable = true
			sendBoard(s)
		end
		return
	end
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
	s.friendList = { ok = ok and type(ids) == "table", ids = if ok and type(ids) == "table" then ids else {}, at = now() }
	if sessions[plr] ~= s or s.leaving or view.mode ~= "friends" then return end
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

-- Only what has been SAVED is ranked, only when it improves on what this server last wrote or read, and never
-- from a session that is not saving. A failed write is retried by the board loop (boardDue).
local function boardWrite(s: any)
	if boardStore == nil or not s.canSave then return end
	if not Board.shouldWrite(Config, s.boardLast, s.savedBolts) then
		s.boardDue = false
		return
	end
	local v = Board.encode(Config, s.savedBolts, s.savedBoltsAt)
	local ok = pcall(function()
		boardStore:SetAsync(key(s.plr.UserId), v)
	end)
	if ok then
		s.boardLast = v
		s.boardDue = false
		publicCache.at = -math.huge -- the next view re-reads, so the writer sees themselves
	else
		s.boardDue = true
		s.boardRetryAt = now() + 30 -- a failing store is retried twice a minute, never every second
	end
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
	plot.owner = nil
	resetPlotVisuals(plot)
	lineDirty = true
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
	if s == nil or s.leaving or plr.Character ~= char then return end
	local plot = s.plot
	if plr.RespawnLocation ~= plot.arrival then plr.RespawnLocation = plot.arrival end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = Config.Trace.WalkSpeed end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pad = plot.arrival.Position
	if hrp then
		local p = hrp.Position
		local off = math.sqrt((p.X - pad.X) ^ 2 + (p.Z - pad.Z) ^ 2)
		if off > P.SpawnCorrectStuds then
			local stand = Vector3.new(pad.X, P.ArrivalTopY + P.RootAbovePad, pad.Z)
			local ahead = plot.at(0, stand.Y, 0).Position
			hrp.CFrame = CFrame.lookAt(stand, ahead)
		end
	end
	-- the trusted position restarts at a point the SERVER chose, never one the client supplied
	s.trace = Trace.new(Config, { x = P.Arrival.x, y = P.ArrivalTopY + P.RootAbovePad, z = P.Arrival.z })
end

local function makeLeaderstats(plr: Player, s: any)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = "$0"
	cash.Parent = ls
	local bolts = Instance.new("IntValue")
	bolts.Name = "Bolts"
	bolts.Parent = ls
	ls.Parent = plr
	s.leader = { cash = cash, bolts = bolts }
end

local function afterLoad(s: any)
	local plr, plot, d = s.plr, s.plot, s.data
	if s.leaving or sessions[plr] ~= s then return end
	syncMachines(plot, d)
	signAccent(plot, d.tier)
	gradePaint(plot, d.bolts)
	s.savedBolts = if s.canSave then d.bolts else 0
	s.savedBoltsAt = d.boltsAt
	lineDirty = true
	-- the board's "last value": one read of the player's own key, so a rejoin never writes a lower or equal one
	if boardStore then
		local ok, v = pcall(function()
			return boardStore:GetAsync(key(plr.UserId))
		end)
		if ok and type(v) == "number" then s.boardLast = v end
		if s.leaving or sessions[plr] ~= s then return end
		-- bolts saved in an earlier session whose board write never landed are ranked now, with their own time
		s.boardDue = Board.shouldWrite(Config, s.boardLast, s.savedBolts)
	end
	if s.lockedElsewhere then task.spawn(recheckLock, s) end
	if not s.canSave then
		toast(plr, if s.lockedElsewhere then Config.Tutorial.NotSavingLocked else Config.Tutorial.NotSaving)
	end
	pushState(s, true)
	sendBoard(s)
	LineStateR:FireClient(plr, linePayload())
end

local function onPlayerAdded(plr: Player)
	if sessions[plr] then return end
	local plot = claimPlot(plr)
	if plot == nil then
		warn("[Scrapline] a seventh player arrived; all 6 factories are taken (Players.MaxPlayers must be 6): " .. plr.Name)
		plr:Kick(W.KickMessage)
		return
	end
	-- BEFORE ANY YIELD: tell the engine where this player's character goes (SPAWN-ORDER.md, preferred pattern)
	plr.RespawnLocation = plot.arrival
	local info = Instance.new("Folder")
	info.Name = tostring(plr.UserId)
	info.Parent = plotInfoRoot
	local s: any = {
		plr = plr,
		plot = plot,
		data = Save.defaults(Config),
		loaded = false,
		canSave = false,
		lockedElsewhere = false,
		lockChanged = false,
		token = nil,
		pending = false,
		lastSave = now(),
		writing = false,
		loadedRaw = nil,
		trace = nil,
		shipped = { 0, 0, 0, 0, 0, 0, 0 },
		lastStateAt = -math.huge,
		lastStarKey = "",
		boardLast = nil,
		boardDue = false,
		savedBolts = 0,
		savedBoltsAt = 0,
		rl = {},
		toastAt = {},
		leaving = false,
		leader = nil,
		info = info,
		view = { mode = "public", friendValues = {}, done = 0, total = 0, unavailable = false, fetching = false, gen = 0 },
		friendsFetching = false,
		recycling = false,
		holdUntil = -math.huge,
		recycleRetryAt = -math.huge, -- REVIEW-2 X3
	}
	sessions[plr] = s
	makeLeaderstats(plr, s)
	plot.ownerText.Text = "🏭 " .. displayName(plr)
	plot.title.Text = "♻ " .. displayName(plr) .. "'s TOP RECYCLERS"
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
	if s == nil or s.leaving then return end
	s.leaving = true
	-- REVIEW-1 A1: the factory is free BEFORE anything yields. Roblox frees the player slot at once, so a joiner can
	-- arrive while this leave is still saving; holding the plot until the writes returned kicked them ("all 6
	-- factories are taken"). The writes below read only s.data, never the plot, and every handler and loop skips a
	-- leaving session.
	freePlot(s.plot)
	s.info:Destroy()
	dropFriendJobs(plr)
	if s.loaded then
		-- REVIEW-1 A3: a rejoin on this server waits for these writes. REVIEW-2 X1: only a LOADED session registers;
		-- one that never loaded writes nothing, and registering it replaced (then cleared) an earlier leave's entry
		leavingByUser[plr.UserId] = s
		writeProfile(s, true, true) -- a live sputter is written as a jam (Save.pack)
		boardWrite(s)
		if leavingByUser[plr.UserId] == s then leavingByUser[plr.UserId] = nil end
	end
	if sessions[plr] == s then sessions[plr] = nil end
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
			boardWrite(s)
		end
	end
end)

--============================================================================ client -> server
local function rateOk(s: any, which: string): boolean
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

local function tutorialStep(s: any, from: number, to: number)
	if s.data.tutorial == from then
		s.data.tutorial = to
		s.pending = true
	end
end

-- Buy(kind, station): "build" | "twin" | "up" at one of the six station ids.
BuyR.OnServerEvent:Connect(function(plr: Player, kind: any, id: any)
	local s = sessions[plr]
	if s == nil or s.leaving then return end -- a leaving session's plot may already be a joiner's
	if not rateOk(s, "buy") then return end
	if not s.loaded then
		toast(plr, Economy.refusalText(Config, "loading"))
		return
	end
	if s.recycling or now() < s.holdUntil then
		toast(plr, Economy.refusalText(Config, "recycling"))
		return
	end
	local d = s.data
	local ok, why, price, t = Economy.buy(Config, d, kind, id)
	if not ok then
		toast(plr, Economy.refusalText(Config, why, price, d.cash, t))
		return
	end
	s.pending = true
	if kind == "build" and id == "shredder" then
		tutorialStep(s, 0, 1)
	else
		tutorialStep(s, 1, 2)
	end
	if kind == "build" and id == "furnace" then tutorialStep(s, 2, 3) end
	syncMachines(s.plot, d)
	lineDirty = true
	FxR:FireClient(plr, { kind = kind, t = t })
	pushState(s, true)
end)

-- Fix(station, machine): station id, "a" or "b". Against the TRUSTED position, on the caller's own plot only.
FixR.OnServerEvent:Connect(function(plr: Player, id: any, which: any)
	local s = sessions[plr]
	if s == nil or s.leaving then return end
	if not rateOk(s, "fix") then return end
	if not s.loaded then
		toast(plr, Economy.refusalText(Config, "loading"))
		return
	end
	if s.recycling or now() < s.holdUntil then
		toast(plr, Economy.refusalText(Config, "recycling"))
		return
	end
	local t = Line.indexOf(Config, id)
	local m = if which == "a" then 1 elseif which == "b" then 2 else nil
	local d = s.data
	if t == nil or m == nil or m > d.stations[id].n then
		toast(plr, "That isn't a machine")
		return
	end
	local st = d.stations[id]
	if st.jam[m] == 0 then
		toast(plr, "That machine is running fine")
		return
	end
	local tr = s.trace
	local mx, mz = PlotGeom.machinePos(Config, t, m)
	-- written fail-closed (REVIEW-2 X2): a distance that is not a number is never "close enough"
	if tr == nil or not (math.sqrt((tr.x - mx) ^ 2 + (tr.z - mz) ^ 2) <= Config.Jams.FixRange) then
		toast(plr, "Get closer to fix it")
		return
	end
	local S = linesOf(s)
	local res = Jams.fix(Config, d.jams, S, t, m)
	if res == nil then
		toast(plr, "That machine is running fine")
		return
	end
	s.pending = true
	tutorialStep(s, 3, 4)
	syncMachines(s.plot, d)
	lineDirty = true
	toast(plr, if res == "saved" then "Saved it! The " .. ST.Names[t] .. " runs on." else "Fixed! The " .. ST.Names[t] .. " is back to work.")
	FxR:FireClient(plr, { kind = res, t = t, m = m })
	pushState(s, true)
end)

-- Recycle(): every check first; then ONE owner-checked write of the whole new run with bolts + 1; the new run is
-- swapped in only when that write lands. A failed write changes nothing and says so.
local function doRecycle(s: any)
	local plr = s.plr
	local d = s.data
	local ok, why, rate, need = Recycle.check(Config, Line, d, {
		loaded = s.loaded, saving = s.canSave and store ~= nil, busy = s.recycling or now() < s.holdUntil })
	if not ok then
		toast(plr, Recycle.text(Config, why, rate, need))
		return
	end
	-- REVIEW-2 X3: a write failed a moment ago: hold the next try (said out loud), never one write per remote call
	if now() < s.recycleRetryAt then
		toast(plr, Recycle.text(Config, "retry", s.recycleRetryAt - now()))
		return
	end
	s.recycling = true
	pushState(s, true)
	-- writes are serialised: wait for the one in flight
	local waited = 0
	while s.writing and waited < Config.Save.WriteQueueSeconds do
		task.wait(0.1)
		waited += 0.1
	end
	local nd = Recycle.nextRun(Config, d, os.time())
	local packed = Save.pack(Config, nd)
	local lost, okW = false, false
	if not s.writing and s.canSave and sessions[plr] == s and not s.leaving then
		s.writing = true
		local okCall, err = pcall(function()
			store:UpdateAsync(key(plr.UserId), function(old)
				old = old or {}
				if old.session ~= s.token then
					lost = true
					return nil
				end
				lost = false
				old.data = packed
				old.jobId = game.JobId
				old.lockUntil = if s.leaving then 0 else os.time() + Config.Save.LockSeconds
				return old
			end)
		end)
		s.writing = false
		okW = okCall and not lost
		if not okCall then
			warn("[Scrapline] recycle write failed for " .. plr.Name .. ": " .. tostring(err))
			s.recycleRetryAt = now() + Config.Recycle.RetrySeconds
		end
	end
	if not okW then
		s.recycling = false
		if lost then
			s.canSave = false
			toast(plr, Config.Tutorial.NotSaving)
		end
		toast(plr, Recycle.text(Config, "failed"))
		pushState(s, true)
		return
	end
	-- the write landed: swap the new run in (keeping what moved during the yield that a recycle keeps)
	nd.jams.jamIn = d.jams.jamIn
	nd.tutorial = d.tutorial
	s.data = nd
	s.shipped = { 0, 0, 0, 0, 0, 0, 0 }
	s.lastSave = now()
	s.savedBolts = nd.bolts
	s.savedBoltsAt = nd.boltsAt
	s.holdUntil = now() + Config.Recycle.SequenceSeconds
	s.recycling = false
	if sessions[plr] == s and not s.leaving then
		local plot = s.plot
		syncMachines(plot, nd)
		signAccent(plot, 0)
		gradePaint(plot, nd.bolts)
		lineDirty = true
		FxR:FireClient(plr, { kind = "recycled", bolts = nd.bolts })
		AnnounceR:FireAllClients({ kind = "recycle", plot = plot.k, name = displayName(plr), bolts = nd.bolts })
		toast(plr, string.format("♻ Recycled! Gold Bolt #%d: everything you ship is worth x%s now.", nd.bolts,
			tostring(Line.mult(Config, nd.bolts))))
		pushState(s, true)
	end
	boardWrite(s)
	if sessions[plr] == s then sendBoard(s) end
end

RecycleR.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or s.leaving then return end
	if not rateOk(s, "recycle") then return end
	-- its own thread: the write may yield (and wait for a write in flight); `recycling` is set before any yield,
	-- so a second call in the meantime is refused as busy
	task.spawn(doRecycle, s)
end)

-- BoardView(mode): "public" or "friends", from the prompt the owner's client creates on their own board.
BoardViewR.OnServerEvent:Connect(function(plr: Player, mode: any)
	local s = sessions[plr]
	if s == nil or s.leaving then return end
	if not rateOk(s, "board") then return end
	if mode ~= "public" and mode ~= "friends" then
		toast(plr, "That isn't a board view")
		return
	end
	if not s.loaded then
		toast(plr, Economy.refusalText(Config, "loading"))
		return
	end
	s.view.mode = mode
	if mode == "friends" then
		task.spawn(startFriends, s)
	else
		s.view.gen += 1
		dropFriendJobs(plr)
		sendBoard(s)
	end
end)

--============================================================================ the line: TickSeconds
local function stepLine(s: any, dt: number)
	local d = s.data
	local plr = s.plr
	local S = linesOf(s)
	-- 1. jams: the server's own clock and Random.new(); the State carries only a live sputter
	local ev = Jams.step(Config, d.jams, S, dt, rand)
	if ev then
		s.pending = true -- a live sputter is written as a jam, so a rejoin never clears it
		syncMachines(s.plot, d)
		lineDirty = true
		FxR:FireClient(plr, { kind = ev.kind, t = ev.t, m = ev.m })
		pushState(s, true)
	end
	-- 2. the dock sells what arrives
	local mult = Line.mult(Config, d.bolts)
	local income, r = Line.income(Config, S, mult)
	d.cash += income * dt
	for i = 1, 7 do
		s.shipped[i] += r[i] * dt
	end
	-- 3. the tier: the highest product shipped this run (a product counts once one whole item has been sold)
	for state = 6, 1, -1 do
		if s.shipped[state + 1] >= 1 then
			if state > d.tier then
				d.tier = state
				s.pending = true
				signAccent(s.plot, state)
				FxR:FireClient(plr, { kind = "tier", tier = state })
				if state == 6 then
					-- the brag moment: the first Rocket of this run lifts off from this plot, for the whole server
					AnnounceR:FireAllClients({ kind = "liftoff", plot = s.plot.k, name = displayName(plr), run = d.bolts + 1 })
				end
				pushState(s, true)
			end
			break
		end
	end
	-- 4. the star changed (a price came into reach): push at once, so the HUD never quotes a stale ★
	local star = Economy.star(Config, Line, S, d.cash, mult)
	local starKey = if star then star.kind .. star.t .. tostring(star.saving) else ""
	if starKey ~= s.lastStarKey then pushState(s, true) end
	-- 5. the debug folder (ServerStorage: never replicated)
	local info = s.info
	info:SetAttribute("JamIn", d.jams.jamIn)
	info:SetAttribute("Cash", d.cash)
	info:SetAttribute("Income", income)
	info:SetAttribute("Tier", d.tier)
	info:SetAttribute("RocketRate", r[7])
	info:SetAttribute("Sputter", if d.jams.sputter then IDS[d.jams.sputter.t] .. ":" .. d.jams.sputter.m else "")
	pushState(s, false)
end

task.spawn(function()
	local last = now()
	local lineAcc = 0
	while true do
		task.wait(Config.Line.TraceSeconds)
		local t = now()
		local dt = math.clamp(t - last, 0, 1)
		last = t
		lineAcc += dt
		local lineDt = 0
		if lineAcc >= Config.Line.TickSeconds - 1e-6 then
			lineDt = math.min(lineAcc, 1)
			lineAcc = 0
		end
		for plr, s in sessions do
			if s.leaving then continue end
			-- the trusted position follows the claimed root at no more than 21.6 studs/s (plot-local studs)
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local p = hrp and hrp.Position
			-- REVIEW-2 X2: a claim that is not a finite number is skipped. inf / inf = NaN turned the trusted position
			-- into NaN for good, and NaN passes every "too far" comparison.
			if p and s.trace and finite(p.X) and finite(p.Y) and finite(p.Z) then
				local lx, lz = PlotGeom.toLocal(Config, s.plot.k, p.X, p.Z)
				Trace.step(s.trace, { x = lx, y = p.Y, z = lz }, dt)
				s.info:SetAttribute("TrustedX", s.trace.x)
				s.info:SetAttribute("TrustedZ", s.trace.z)
			end
			if lineDt > 0 and s.loaded then
				local ok, err = pcall(stepLine, s, lineDt)
				if not ok and not s.warned then
					s.warned = true -- once: a broken line must not flood the output
					warn("[Scrapline] line tick failed for " .. plr.Name .. ": " .. tostring(err))
				end
			end
		end
		broadcastLines(false)
	end
end)

--============================================================================ saving and the board, on their own clocks
task.spawn(function()
	while true do
		task.wait(Config.Save.FlushTickSeconds)
		local t = now()
		for _, s in sessions do
			if s.loaded and not s.leaving and not s.recycling and s.canSave and (s.pending or t - s.lastSave >= Config.Save.AutosaveSeconds) then
				writeProfile(s, false)
			end
		end
	end
end)

task.spawn(function()
	local n = 0
	while true do
		task.wait(1)
		n += 1
		for _, s in sessions do
			if s.loaded and not s.leaving then
				if s.boardDue and now() >= (s.boardRetryAt or 0) then boardWrite(s) end
				-- every 30 s each owner's board is re-sent: the public view refreshes from its 60 s cache, and a
				-- client that connected after the first send (a slow HUD) still gets its rows
				if n % Config.Board.ResendSeconds == 0 then sendBoard(s) end
			end
		end
		stepFriendQueue()
	end
end)
