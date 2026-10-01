-- Main.server.luau — authoritative server for SIGNAL LOST: Derelict Station.
--
-- One shared lifeboat (the hub) at the world origin; one private zone per player, 400 studs apart along +X. A
-- sector: stand in the LIFT -> a 3 s ride -> sector best + 1's dock, the only module that exists. Every other
-- module is built the moment its hatch opens, and a hatch opens by itself when the server's TRUSTED position comes
-- within 8 studs of it. Air modules refill the tank; vacuum modules drain it one second per second. The SIGNAL
-- meter's bars lead to the sector's one relay; reaching it splices it: carried salvage is banked plus a bonus,
-- the relay count goes up, the lights come on, and a floor hatch drops you into the next sector. Everything is in
-- DESIGN.md; the section numbers below point there.
--
-- THE RULES THIS FILE IS WRITTEN AGAINST (each one cost a sibling game a shipped defect):
--   * Requires go through Instances (`require(ReplicatedStorage:WaitForChild("X"))`), never a path.
--   * The lifeboat and HubSpawn are built synchronously BEFORE PlayerAdded is connected and before any DataStore
--     call, and HubSpawn is the only enabled SpawnLocation anywhere. PlayerAdded points plr.RespawnLocation at it,
--     so the engine's own placement is right; the CharacterAdded handler writes no CFrame and never yields
--     (robloxemu/SPAWN-ORDER.md).
--   * Every rule reads the TRUSTED position and module (shared/Trust.luau), never the claim.
--   * Nothing secret is written to an Instance: not the relay, not the air map, not an unopened module, not a
--     stream. Zones carry ZERO attributes. Test-only data lives in ServerStorage.SignalDebug, which never
--     replicates (anomaly-observatory's "ServerStorage, not the zone").
--   * Every stream is Random.new() with no seed, one per stream per attempt (DESIGN.md §12, fork-tower REVIEW-4).
--   * Time is accumulated from task.wait's return value; the emulator drives a virtual clock.
--   * No Raycast, no PathfindingService, no Touched in any rule: everything spatial is grid arithmetic.
--   * Every refused request gets a toast. Nothing fails silently.
--   * An unspliced sector is paid exactly once (shared/Economy.luau), whatever ends it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage
local Config = require(Shared:WaitForChild("Config"))
local MazeGen = require(Shared:WaitForChild("MazeGen"))
local Station = require(Shared:WaitForChild("Station"))
local Air = require(Shared:WaitForChild("Air"))
local Meter = require(Shared:WaitForChild("Meter"))
local Trust = require(Shared:WaitForChild("Trust"))
local Economy = require(Shared:WaitForChild("Economy"))
local Board = require(Shared:WaitForChild("Board"))
local EnvBands = require(Shared:WaitForChild("EnvBands"))
local Fx = require(Shared:WaitForChild("Fx"))

-- Visuals from the first build (checklist §2): space-dark ambient, each module's own light carries the scene.
Fx.applyLighting(Fx.Presets.Station)

pcall(function()
	(Players :: any).RespawnTime = Config.Server.RespawnTime
end)

local S = Config.Station
local CELL = S.CellSize
local TICK = Config.Server.TickSeconds
local BC = Config.Board

local function rgb(t: any): Color3
	if t.r then return Color3.fromRGB(t.r, t.g, t.b) end
	return Color3.fromRGB(t[1], t[2], t[3])
end
local ACCENT = rgb(Config.Hud.Accent)
local GOOD = rgb(Config.Hud.Good)
local SALVAGE = rgb(Config.SignalColors.Salvage)
local CANISTER = rgb(Config.SignalColors.Canister)
local LAMP_VAC = rgb(Config.SignalColors.HatchVacuum)
local LAMP_AIR = rgb(Config.SignalColors.HatchAir)

-- A clock for rate limits and caches: the virtual clock headless, the real one in Roblox.
local function clock(): number
	return tick()
end

--============================================================================ remotes

local Remotes = Instance.new("Folder")
Remotes.Name = "SignalRemotes"
Remotes.Parent = ReplicatedStorage
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = Remotes
	return r
end
local StateRemote = remote("State") -- server -> owner, 5 Hz
local NoticeRemote = remote("Notice") -- server -> owner: (kind, data)
local BoardRemote = remote("Board") -- server -> one viewer: their view of the board
local AnnounceRemote = remote("Announce") -- server -> everyone: the Main Array restored
local BuyRemote = remote("BuyUpgrade") -- client -> server: (upgradeId)

local function notice(plr: Player, kind: string, data: any?)
	NoticeRemote:FireClient(plr, kind, data)
end
local function toast(plr: Player, text: string)
	notice(plr, "toast", text)
end

--============================================================================ DataStores

local okStore, profileStore = pcall(function()
	return DataStoreService:GetDataStore(Config.Data.Store)
end)
if not okStore then
	profileStore = nil
end
local okOrdered, orderedStore = pcall(function()
	return DataStoreService:GetOrderedDataStore(BC.Store)
end)
if not okOrdered then
	orderedStore = nil
end

--============================================================================ parts

local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
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

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A SurfaceGui label whose canvas takes the FACE's proportions (facility-nightmare trap 14: a fixed canvas is
-- stretched onto its face). Axis-aligned hosts only.
local function faceSize(host: BasePart, face): (number, number)
	local s = host.Size
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return s.Z, s.Y
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return s.X, s.Z
	end
	return s.X, s.Y
end
local function label(host: BasePart, face, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face
	local w, hh = faceSize(host, face)
	gui.CanvasSize = Vector2.new(math.floor(w * 100 + 0.5), math.floor(hh * 100 + 0.5))
	gui.LightInfluence = 0
	gui.Parent = host
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = color
	t.Parent = gui
	return t
end

local function prompt(host: Instance, name: string, action: string, object: string, distance: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	-- never Roblox's default ButtonX: the HUD binds ButtonX to REST, and Roblox shows one prompt per button, so the
	-- relay console's two prompts on one button left one unreachable on a gamepad (REVIEW-1). Fabricators and the
	-- board use ButtonY, the RETURN consoles ButtonB (set where they are made).
	p.GamepadKeyCode = Enum.KeyCode.ButtonY
	p.Parent = host
	return p
end

--============================================================================ §2.8 the lifeboat, FIRST

local H = Config.Hub
local hubFolder = folder("Lifeboat", workspace)
local HULL = Color3.fromRGB(190, 196, 206)
local HULL_DARK = Color3.fromRGB(70, 76, 88)

part({ Name = "HubFloor", Size = Vector3.new(H.SizeX, 1, H.SizeZ), CFrame = CFrame.new(0, -0.5, 0),
	Material = Enum.Material.DiamondPlate, Color = Color3.fromRGB(96, 102, 112), Parent = hubFolder })
part({ Name = "HubCeiling", Size = Vector3.new(H.SizeX, 1, H.SizeZ), CFrame = CFrame.new(0, H.Height + 0.5, 0),
	Material = Enum.Material.SmoothPlastic, Color = HULL_DARK, Parent = hubFolder })
for _, w in {
	{ "HubWallE", Vector3.new(1, H.Height, H.SizeZ), Vector3.new(H.SizeX / 2 + 0.5, H.Height / 2, 0) },
	{ "HubWallW", Vector3.new(1, H.Height, H.SizeZ), Vector3.new(-H.SizeX / 2 - 0.5, H.Height / 2, 0) },
	{ "HubWallS", Vector3.new(H.SizeX + 2, H.Height, 1), Vector3.new(0, H.Height / 2, -H.SizeZ / 2 - 0.5) },
	-- the north wall frames the planet window (40 x 8, from 4 to 12 studs up)
	{ "HubWallN_Low", Vector3.new(H.SizeX + 2, 4, 1), Vector3.new(0, 2, H.SizeZ / 2 + 0.5) },
	{ "HubWallN_High", Vector3.new(H.SizeX + 2, H.Height - 12, 1), Vector3.new(0, 12 + (H.Height - 12) / 2, H.SizeZ / 2 + 0.5) },
	{ "HubWallN_W", Vector3.new(11, 8, 1), Vector3.new(-H.SizeX / 2 - 1 + 5.5, 8, H.SizeZ / 2 + 0.5) },
	{ "HubWallN_E", Vector3.new(11, 8, 1), Vector3.new(H.SizeX / 2 + 1 - 5.5, 8, H.SizeZ / 2 + 0.5) },
} do
	part({ Name = w[1], Size = w[2], CFrame = CFrame.new(w[3]), Material = Enum.Material.SmoothPlastic, Color = HULL, Parent = hubFolder })
end
part({ Name = "PlanetWindow", Size = Vector3.new(H.SizeX + 2 - 22, 8, 0.4), CFrame = CFrame.new(0, 8, H.SizeZ / 2 + 0.5),
	Material = Enum.Material.Glass, Color = Color3.fromRGB(160, 190, 230), Transparency = 0.7, CastShadow = false, Parent = hubFolder })
for i, x in { -18, 0, 18 } do
	local lamp = part({ Name = "HubLamp" .. i, Size = Vector3.new(6, 0.4, 3), CFrame = CFrame.new(x, H.Height - 0.2, 0),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(235, 242, 255), CanCollide = false, Parent = hubFolder })
	local light = Instance.new("PointLight")
	light.Name = "HubLight"
	light.Enabled = true
	light.Range = 40
	light.Brightness = 1.8
	light.Color = Color3.fromRGB(225, 235, 255)
	light.Parent = lamp
end

-- HubSpawn: the ONLY enabled SpawnLocation anywhere. It faces +X: the LIFT is 12 studs ahead, the board beyond.
local hubSpawn = Instance.new("SpawnLocation")
hubSpawn.Name = "HubSpawn"
hubSpawn.Size = Vector3.new(6, 1, 6)
hubSpawn.CFrame = CFrame.lookAt(Vector3.new(H.SpawnX, 0.5, 0), Vector3.new(H.SpawnX + 1, 0.5, 0))
hubSpawn.Anchored = true
hubSpawn.Enabled = true -- explicit: a disabled SpawnLocation is not a legal RespawnLocation
hubSpawn.Neutral = true
hubSpawn.Duration = 0 -- no ForceField
hubSpawn.Material = Enum.Material.DiamondPlate
hubSpawn.Color = Color3.fromRGB(120, 128, 140)
hubSpawn.Parent = hubFolder

local hubArrival = part({ Name = "HubArrival", Size = Vector3.new(6, 0.2, 6), CFrame = CFrame.new(H.ArrivalX, 0.1, H.ArrivalZ),
	Material = Enum.Material.DiamondPlate, Color = Color3.fromRGB(120, 128, 140), CanCollide = false, Parent = hubFolder })

-- The LIFT: an open pad 12 studs ahead of the spawn, under a lit arch. Stand in it BoardingSeconds to ride down.
local liftFolder = folder("Lift", hubFolder)
local LS = H.LiftSize
local liftPad = part({ Name = "LiftPad", Size = Vector3.new(LS, 0.4, LS), CFrame = CFrame.new(H.LiftX, 0.2, 0),
	Material = Enum.Material.Metal, Color = Color3.fromRGB(70, 110, 150), Parent = liftFolder })
do
	part({ Name = "LiftRing", Size = Vector3.new(LS + 0.6, 0.1, LS + 0.6), CFrame = CFrame.new(H.LiftX, 0.05, 0),
		Material = Enum.Material.Neon, Color = ACCENT, CanCollide = false, Parent = liftFolder })
	for i, z in { -LS / 2 - 0.4, LS / 2 + 0.4 } do
		part({ Name = "LiftPost" .. i, Size = Vector3.new(0.6, 11, 0.6), CFrame = CFrame.new(H.LiftX, 5.5, z),
			Material = Enum.Material.Metal, Color = HULL_DARK, Parent = liftFolder })
	end
	local sign = part({ Name = "LiftSign", Size = Vector3.new(0.4, 1.6, LS + 1.4), CFrame = CFrame.new(H.LiftX, 11.6, 0),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(14, 22, 34), CanCollide = false, Parent = liftFolder })
	label(sign, Enum.NormalId.Left, "LIFT", ACCENT)
	Fx.attachGlow(sign, ACCENT, 1.2, 14)
	-- the thing to walk toward glows: a guide strip from the spawn to the lift
	local from, to = H.SpawnX + 3, H.LiftX - LS / 2
	part({ Name = "GuideStrip", Size = Vector3.new(to - from, 0.05, 1), CFrame = CFrame.new((from + to) / 2, 0.03, 0),
		Material = Enum.Material.Neon, Color = ACCENT, CanCollide = false, Parent = liftFolder })
end

-- The fabricator, against the south wall. Its prompt opens the upgrade panel.
local hubFab = part({ Name = "Fabricator", Size = Vector3.new(4, 5, 2), CFrame = CFrame.new(H.FabX, 2.5, H.FabZ),
	Material = Enum.Material.Metal, Color = Color3.fromRGB(44, 52, 64), Parent = hubFolder })
label(hubFab, Enum.NormalId.Back, "FABRICATOR", GOOD)
Fx.attachGlow(hubFab, GOOD, 1, 10)
local hubFabPrompt = prompt(hubFab, "FabricatorPrompt", "Open fabricator", "Upgrades", S.ConsoleRadius)

-- Two benches (real Seats) facing the planet window: where a player rests in the lifeboat (§6).
local benches = folder("Benches", hubFolder)
for i, x in H.BenchXs do
	local seat = Instance.new("Seat")
	seat.Name = "Bench" .. i
	seat.Anchored = true
	seat.Size = Vector3.new(6, 1, 2.4)
	seat.CFrame = CFrame.new(x, 1.3, -H.SizeZ / 2 + 1.6) -- a Seat seats you along its front (-Z local): facing +Z
		* CFrame.Angles(0, math.pi, 0)
	seat.Material = Enum.Material.Fabric
	seat.Color = Color3.fromRGB(60, 74, 96)
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Parent = benches
	part({ Name = "BenchBack" .. i, Size = Vector3.new(6, 3.2, 0.5), CFrame = CFrame.new(x, 2.9, -H.SizeZ / 2 + 0.35),
		Material = Enum.Material.Fabric, Color = Color3.fromRGB(50, 62, 82), Parent = benches })
	part({ Name = "BenchBase" .. i, Size = Vector3.new(5.6, 0.8, 2), CFrame = CFrame.new(x, 0.4, -H.SizeZ / 2 + 1.6),
		Material = Enum.Material.Metal, Color = HULL_DARK, Parent = benches })
end

-- §10.3 the board, on the wall the spawn faces. Its face is drawn per viewer by Board.client.
local boardPart = part({ Name = "RelayBoard", Size = Vector3.new(14, 9, 0.8), Material = Enum.Material.SmoothPlastic,
	Color = Color3.fromRGB(14, 20, 32), Parent = hubFolder })
do
	local centre = Vector3.new(H.BoardX, 7, H.BoardZ)
	boardPart.CFrame = CFrame.lookAt(centre, centre + Vector3.new(-1, 0, 0)) -- its Front face (-Z local) faces -X
	local trim = part({ Name = "RelayBoardTrim", Size = Vector3.new(14.8, 9.8, 0.4), CFrame = boardPart.CFrame * CFrame.new(0, 0, 0.5),
		Material = Enum.Material.Neon, Color = ACCENT, CanCollide = false, CastShadow = false, Parent = hubFolder })
	local _ = trim
end
local boardPrompt: ProximityPrompt
do
	local at = Instance.new("Attachment")
	at.Name = "PromptAt"
	at.Position = Vector3.new(0, -3.5, -0.6)
	at.Parent = boardPart
	boardPrompt = prompt(at, "BoardPrompt", BC.Text.Prompt, "Relays restored", BC.PromptDistance)
	boardPrompt.KeyboardKeyCode = Enum.KeyCode.E
end

local function inLift(pos: Vector3): boolean
	return math.abs(pos.X - H.LiftX) <= LS / 2 and math.abs(pos.Z) <= LS / 2 and pos.Y < 8
end
local function nearHubFab(pos: Vector3): boolean
	local d = pos - hubFab.Position
	return math.sqrt(d.X * d.X + d.Z * d.Z) <= S.ConsoleRadius
end

--============================================================================ zones

local stationFolder = folder("Station", workspace)
local debugRoot = folder("SignalDebug", ServerStorage)

local zoneTaken: { [number]: boolean } = {}
local function acquireZone(): number
	local i = 1
	while zoneTaken[i] do i += 1 end
	zoneTaken[i] = true
	return i
end
local function zoneOrigin(index: number): Vector3
	return Vector3.new(Config.Server.ZoneSpacing * index, 0, 0)
end
local POD_Z = -(6 * CELL / 2 + Config.Server.PodOffset)

-- The transit pod: a closed, lit capsule out of sight of every module, where the 3 s ride happens.
local function buildPod(zone: Folder, origin: Vector3)
	local pod = folder("Pod", zone)
	local o = origin + Vector3.new(0, 0, POD_Z)
	local metal = Color3.fromRGB(70, 78, 92)
	part({ Name = "PodFloor", Size = Vector3.new(10, 1, 10), CFrame = CFrame.new(o + Vector3.new(0, -0.5, 0)),
		Material = Enum.Material.DiamondPlate, Color = Color3.fromRGB(100, 108, 120), Parent = pod })
	local roof = part({ Name = "PodRoof", Size = Vector3.new(10, 1, 10), CFrame = CFrame.new(o + Vector3.new(0, 10.5, 0)),
		Material = Enum.Material.Metal, Color = metal, Parent = pod })
	for _, w in {
		{ "PodWallE", Vector3.new(1, 10, 10), Vector3.new(5.5, 5, 0) },
		{ "PodWallW", Vector3.new(1, 10, 10), Vector3.new(-5.5, 5, 0) },
		{ "PodWallN", Vector3.new(12, 10, 1), Vector3.new(0, 5, 5.5) },
		{ "PodWallS", Vector3.new(12, 10, 1), Vector3.new(0, 5, -5.5) },
	} do
		part({ Name = w[1], Size = w[2], CFrame = CFrame.new(o + w[3]), Material = Enum.Material.Metal, Color = metal, Parent = pod })
	end
	local light = Instance.new("PointLight")
	light.Name = "PodLight"
	light.Enabled = true
	light.Range = 12
	light.Brightness = 1
	light.Color = Color3.fromRGB(150, 200, 255)
	light.Parent = roof
end

--============================================================================ sessions

type Session = {
	plr: Player,
	profile: any,
	loaded: boolean,
	canSave: boolean,
	token: string,
	closing: boolean,
	buying: boolean,
	buyBusyTold: boolean,
	loadFailed: boolean,
	dirty: boolean,
	saveTick: number,
	zoneIndex: number,
	zone: Folder,
	phase: string, -- "hub" | "transit" | "sector" | "blackout"
	boardT: number,
	boardCooldown: number,
	transitLeft: number,
	transitTo: string, -- "sector" | "hub"
	beatLeft: number,
	pushLeft: number,
	sector: any?,
	buyAt: number,
	boardToggleAt: number,
	boardMode: string,
	lastOrdered: number, -- the metric this server last wrote to the ordered store
	lastOrderedAt: number?,
	firstVacuumTold: boolean,
	debug: Folder?,
}

local sessions: { [Player]: Session } = {}

local function newToken(): string
	local ok, guid = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	if ok and type(guid) == "string" then
		return guid
	end
	return string.format("%d-%d", os.time(), math.random(1, 2147483646))
end

local function key(userId: number): string
	return "u_" .. tostring(userId)
end

-- One lock-claim attempt. The owner is a STABLE per-session GUID, never a timestamp we also rewrite (checklist:
-- session lock). Returns got, data, failed.
local function claimProfile(sess: Session): (boolean, any, boolean)
	if not profileStore then
		return false, nil, true
	end
	local got, data = false, nil
	local ok = pcall(function()
		(profileStore :: any):UpdateAsync(key(sess.plr.UserId), function(old)
			old = if type(old) == "table" then old else {}
			local lock = old.lock
			local now = os.time()
			local free = type(lock) ~= "table" or lock.owner == sess.token or (tonumber(lock.expires) or 0) < now
			got, data = free, old.data
			if not free then
				return nil
			end
			return { data = old.data, lock = { owner = sess.token, expires = now + Config.Data.SessionLockSeconds } }
		end)
	end)
	if not ok then
		return false, nil, true
	end
	return got, data, false
end

-- Give back a lock this session holds WITHOUT writing its data (a claim that came back after the player left).
local function releaseLock(sess: Session)
	if not profileStore then return end
	pcall(function()
		(profileStore :: any):UpdateAsync(key(sess.plr.UserId), function(old)
			if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.owner ~= sess.token then
				return nil
			end
			return { data = old.data, lock = nil }
		end)
	end)
end

-- Flush the WHOLE profile under the lock (an owner token on every write). true only if the write persisted.
local function saveProfile(sess: Session, releasing: boolean?): boolean
	if not profileStore or not sess.canSave then
		return false
	end
	if sess.closing and not releasing then
		-- REVIEW-1 finding 2: once a session is closing, only its releasing write may run; any other would re-take
		-- the lock for SessionLockSeconds after the release and lock the player out of their own file on rejoin
		return false
	end
	local payload = Economy.snapshot(sess.profile)
	local wrote, lostLock = false, false
	local ok, result = pcall(function()
		return (profileStore :: any):UpdateAsync(key(sess.plr.UserId), function(old)
			wrote = false
			lostLock = false
			old = if type(old) == "table" then old else {}
			local lock = old.lock
			local now = os.time()
			if type(lock) == "table" and lock.owner ~= sess.token and (tonumber(lock.expires) or 0) >= now then
				lostLock = true
				return nil -- another server owns this file now; never clobber it
			end
			wrote = true
			local newLock = nil
			if not releasing then
				newLock = { owner = sess.token, expires = now + Config.Data.SessionLockSeconds }
			end
			return { data = payload, lock = newLock }
		end)
	end)
	if ok and lostLock then
		sess.canSave = false
		warn("[SignalLost] " .. sess.plr.Name .. ": another server took this profile; this session stops saving.")
	end
	local persisted = ok and result ~= nil and wrote
	if persisted then sess.dirty = false end
	return persisted
end

--============================================================================ §10 the board

-- Write the ordered store only when `best` improved on what this server last wrote, at most once per
-- WriteMinSeconds, plus on leaving (Board.shouldWrite). UpdateAsync keeps the larger value (Board.keepHigher).
local function writeBoard(sess: Session, leaving: boolean)
	local p = sess.profile
	if not orderedStore or not sess.canSave then return end
	local now = clock()
	if not Board.shouldWrite(sess.lastOrdered, p.best, sess.lastOrderedAt, now, leaving, BC) then return end
	local metric = p.best
	local value = Board.encode(metric, p.bestAt, BC)
	local ok = pcall(function()
		(orderedStore :: any):UpdateAsync(key(sess.plr.UserId), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	if ok then
		sess.lastOrdered = metric -- also when keepHigher aborted: what is stored is at least as high
		sess.lastOrderedAt = now
	end
end

local function setRelays(sess: Session)
	local ls = sess.plr:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Relays")
	if v then
		(v :: IntValue).Value = sess.profile.best
	end
end

--============================================================================ characters

local function character(sess: Session): (Model?, Humanoid?, BasePart?)
	local char = sess.plr.Character
	if not char then return nil, nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return char, hum, hrp :: BasePart?
end

-- Every server move is guarded: a character that is not alive in the world is already on the reset path.
local function moveCharacter(sess: Session, pos: Vector3): boolean
	local char, hum, hrp = character(sess)
	if not char or char.Parent == nil or not hum or hum.Health <= 0 or not hrp then
		return false
	end
	char:PivotTo(CFrame.new(pos))
	return true
end

-- The server assigns WalkSpeed and JumpHeight on every module change (DESIGN.md §19 trap list).
local function applyMove(sess: Session, vacuum: boolean)
	local _, hum = character(sess)
	if not hum then return end
	local speed, jump = Config.Move.AirWalkSpeed, Config.Move.AirJumpHeight
	if vacuum and sess.sector then
		speed, jump = sess.sector.vacSpeed, Config.Move.VacJumpHeight
	end
	pcall(function()
		(hum :: any).UseJumpPower = false
	end)
	if hum.WalkSpeed ~= speed then hum.WalkSpeed = speed end
	if (hum :: any).JumpHeight ~= jump then (hum :: any).JumpHeight = jump end
end

--============================================================================ the sector

local LIGHT_AIR = Color3.fromRGB(255, 240, 220)
local LIGHT_VAC = Color3.fromRGB(255, 70, 55)
local LIGHT_SPLICED = Color3.fromRGB(225, 255, 238)
local WALL = rgb(Config.Env.ServerWall)
local FLOOR = rgb(Config.Env.ServerFloor)
local TRIM = rgb(Config.Env.ServerTrim)

local function worldOf(sess: Session, lx: number, y: number, lz: number): Vector3
	return zoneOrigin(sess.zoneIndex) + Vector3.new(lx, y, lz)
end

local function hatchKey(a: number, b: number): string
	return math.min(a, b) .. "_" .. math.max(a, b)
end

local function list(t: { number }): string
	local out = {}
	for _, v in t do table.insert(out, tostring(v)) end
	return table.concat(out, ",")
end

local function writeDebug(sess: Session)
	local sec = sess.sector
	if not sec then return end
	local d = sess.debug
	if not d then
		d = folder("Run_" .. sess.plr.UserId, debugRoot)
		sess.debug = d
	end
	local plan = sec.plan
	local air, salv, can = {}, {}, {}
	for m = 1, plan.n2 do table.insert(air, if plan.vac[m] then "0" else "1") end
	for m = 1, plan.n2 do
		local it = plan.items[m]
		if it and it.kind == "salvage" then table.insert(salv, m) end
		if it and it.kind == "canister" then table.insert(can, m) end
	end
	d:SetAttribute("Sector", sec.k)
	d:SetAttribute("Grid", plan.n)
	d:SetAttribute("DockCell", plan.dock)
	d:SetAttribute("RelayCell", plan.relay)
	d:SetAttribute("AirMap", table.concat(air))
	d:SetAttribute("SalvageCells", list(salv))
	d:SetAttribute("CanisterCells", list(can))
	d:SetAttribute("ZoneIndex", sess.zoneIndex)
	d:SetAttribute("TrustedCell", if sec.trust then sec.trust.cell else plan.dock)
	d:SetAttribute("Spliced", sec.spliced)
	d:SetAttribute("AttemptId", sec.id)
end

local function destroySector(sess: Session)
	local sec = sess.sector
	if sec and sec.folder then
		sec.folder:Destroy()
		sec.folder = nil
	end
end

local function lightModule(sec: any, m: number)
	local rec = sec.lights[m]
	if not rec then return end
	if sec.spliced then
		rec.light.Color = LIGHT_SPLICED
		rec.light.Brightness = S.SplicedLightBrightness
		rec.fixture.Color = LIGHT_SPLICED
	elseif sec.plan.vac[m] then
		rec.light.Color = LIGHT_VAC
		rec.light.Brightness = S.VacuumLightBrightness
		rec.fixture.Color = LIGHT_VAC
	else
		rec.light.Color = LIGHT_AIR
		rec.light.Brightness = S.ModuleLightBrightness
		rec.fixture.Color = LIGHT_AIR
	end
end

-- The hatch lamp (§2.2): on a lintel's inner face, what is BEHIND the hatch — green AIR or red VACUUM. Public by
-- design. A SurfaceGui, not a Part: the module's own lintel carries it, so a hatch costs one Part (its leaf).
local INNER_FACE = { E = Enum.NormalId.Left, W = Enum.NormalId.Right, N = Enum.NormalId.Front, S = Enum.NormalId.Back }
local function hatchLamp(lintel: BasePart, side: string, behindVacuum: boolean)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "HatchLamp"
	gui.Face = INNER_FACE[side]
	local w, hh = faceSize(lintel, gui.Face)
	gui.CanvasSize = Vector2.new(math.floor(w * 50 + 0.5), math.floor(hh * 50 + 0.5))
	gui.LightInfluence = 0
	gui.Parent = lintel
	local bar = Instance.new("Frame")
	bar.Name = "Lamp"
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(0.8, 0.24)
	bar.Position = UDim2.fromScale(0.1, 0.72)
	bar.BackgroundColor3 = if behindVacuum then LAMP_VAC else LAMP_AIR
	bar.Parent = gui
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(10, 12, 16)
	t.Text = if behindVacuum then "VACUUM" else "AIR"
	t.Parent = bar
end

local function buildLeaf(sess: Session, a: number, b: number)
	local sec = sess.sector
	local k = hatchKey(a, b)
	if sec.leaves[k] then return end
	local spec = Station.leafSpec(Config, sec.plan.n, a, b)
	sec.leaves[k] = {
		part = part({
			Name = spec.name,
			Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3]),
			CFrame = CFrame.new(worldOf(sess, spec.pos[1], spec.pos[2], spec.pos[3])),
			Material = Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(88, 96, 108),
			Parent = sec.folders.hatches,
		}),
		axis = spec.axis,
	}
end

local function buildItem(sess: Session, m: number, c: Vector3)
	local sec = sess.sector
	local it = sec.plan.items[m]
	if not it or sec.taken[m] then return end
	local pos = c + Vector3.new(it.x, it.y, it.z)
	local p
	if it.kind == "salvage" then
		p = part({ Name = "Salvage", Size = Vector3.new(1.6, 1.6, 1.6), CFrame = CFrame.new(pos) * CFrame.Angles(0.4, 0.7, 0.2),
			Material = Enum.Material.Neon, Color = SALVAGE, CanCollide = false, CastShadow = false, Parent = sec.modules[m] })
		Fx.attachGlow(p, SALVAGE, 1.5, 10)
	else
		p = part({ Name = "Canister", Size = Vector3.new(1.2, 2.2, 1.2), CFrame = CFrame.new(pos),
			Material = Enum.Material.Neon, Color = CANISTER, CanCollide = false, CastShadow = false, Parent = sec.modules[m] })
		Fx.attachGlow(p, CANISTER, 1.5, 10)
	end
	sec.itemParts[m] = p
end

local buildRelayExtras -- forward

-- §2.1: a module exists only once a hatch into it opens (or it is the dock).
local function buildModule(sess: Session, m: number)
	local sec = sess.sector
	if sec.modules[m] then return end
	local plan = sec.plan
	local mf = folder("Module_" .. m, sec.folders.modules)
	sec.modules[m] = mf
	sec.visited += 1
	local cx, cz = Station.cellCenter(Config, plan.n, m)
	local c = worldOf(sess, cx, 0, cz)
	local mainArray = sec.k == Config.Brag.Sector and m == plan.relay
	for _, sp in Station.moduleParts(Config, plan, m, { mainArray = mainArray }) do
		local size = Vector3.new(sp.size[1], sp.size[2], sp.size[3])
		local cf = CFrame.new(c + Vector3.new(sp.pos[1], sp.pos[2], sp.pos[3]))
		if sp.role == "floor" then
			part({ Name = sp.name, Size = size, CFrame = cf, Material = Enum.Material.DiamondPlate, Color = FLOOR, Parent = mf })
		elseif sp.role == "ceiling" then
			part({ Name = sp.name, Size = size, CFrame = cf, Material = Enum.Material.Metal, Color = TRIM, Parent = mf })
		elseif sp.role == "glass" then
			part({ Name = sp.name, Size = size, CFrame = cf, Material = Enum.Material.Glass, Color = Color3.fromRGB(150, 180, 220),
				Transparency = 0.6, CastShadow = false, Parent = mf })
		elseif sp.role == "wall" then
			local w = part({ Name = sp.name, Size = size, CFrame = cf, Material = Enum.Material.SmoothPlastic, Color = WALL, Parent = mf })
			if sp.nb and string.sub(sp.name, -4) == "_Top" then
				hatchLamp(w, sp.side, plan.vac[sp.nb])
			end
		elseif sp.role == "fixture" then
			local fixture = part({ Name = sp.name, Size = size, CFrame = cf, Material = Enum.Material.Neon, Color = LIGHT_AIR,
				CanCollide = false, Parent = mf })
			local light = Instance.new("PointLight")
			light.Name = "ModuleLight"
			light.Enabled = true
			light.Range = S.ModuleLightRange
			light.Shadows = false
			light.Parent = fixture
			sec.lights[m] = { light = light, fixture = fixture }
			lightModule(sec, m)
		end
	end
	buildItem(sess, m, c)
	if m == plan.dock then
		local lx, lz = Station.dockConsole(Config, plan.n, m)
		local console = part({ Name = "ReturnConsole", Size = Vector3.new(2.4, 3.2, 2.4), CFrame = CFrame.new(c + Vector3.new(lx, 1.6, lz)),
			Material = Enum.Material.Metal, Color = Color3.fromRGB(40, 48, 60), Parent = mf })
		Fx.attachGlow(console, ACCENT, 0.8, 8)
		local pr = prompt(console, "ReturnPrompt", "Return to the lifeboat", "RETURN", S.ConsoleRadius)
		pr.GamepadKeyCode = Enum.KeyCode.ButtonB
		sec.returnPrompts[pr] = true
		pr.Triggered:Connect(function(who)
			local onReturn = sess.onReturn
			if onReturn then onReturn(who, pr) end
		end)
		part({ Name = "ArrivalHatch", Size = Vector3.new(6, 0.2, 6), CFrame = CFrame.new(c + Vector3.new(0, S.CeilingHeight - 0.15, 0)),
			Material = Enum.Material.Neon, Color = Color3.fromRGB(70, 90, 120), CanCollide = false, Parent = mf })
	end
	if m == plan.relay then
		local mast = part({ Name = "RelayMast", Size = Vector3.new(1.6, 12, 1.6), CFrame = CFrame.new(c + Vector3.new(0, 6, 0)),
			Material = Enum.Material.Neon, Color = if sec.spliced then GOOD else LAMP_VAC, CanCollide = false, Parent = mf })
		Fx.attachGlow(mast, if sec.spliced then GOOD else LAMP_VAC, 2, 18)
		sec.mast = mast
		if sec.spliced then buildRelayExtras(sess) end
	end
	for _, nb in plan.adj[m] do
		buildLeaf(sess, m, nb)
	end
	writeDebug(sess)
end

local function openHatch(sess: Session, a: number, b: number)
	local sec = sess.sector
	local k = hatchKey(a, b)
	if sec.open[k] then return end
	sec.open[k] = true
	buildModule(sess, a)
	buildModule(sess, b)
	local leaf = sec.leaves[k]
	if leaf then
		leaf.part.CanCollide = false
		local slide = if leaf.axis == "x" then Vector3.new(0, 0, S.HatchWidth) else Vector3.new(S.HatchWidth, 0, 0)
		TweenService:Create(leaf.part, TweenInfo.new(S.HatchSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = leaf.part.CFrame + slide }):Play()
	end
end

--============================================================================ state push

local function upRows(prof: any): { any }
	local rows = {}
	for _, id in Config.Upgrades.Order do
		local u = Config.Upgrades.Catalog[id]
		local rank = Economy.rankOf(Config, prof.up, id)
		table.insert(rows, { id = id, name = u.name, blurb = u.blurb, rank = rank, max = u.max,
			price = Economy.price(Config, id, rank) })
	end
	return rows
end

local function nearFabricator(sess: Session): boolean
	local sec = sess.sector
	if sess.phase == "hub" then
		local _, _, hrp = character(sess)
		return hrp ~= nil and nearHubFab((hrp :: BasePart).Position)
	end
	if sess.phase == "sector" and sec and sec.spliced and sec.trust and sec.trust.cell == sec.plan.relay then
		local lay = Station.relayLayout(Config)
		local cx, cz = Station.cellCenter(Config, sec.plan.n, sec.plan.relay)
		local dx, dz = sec.trust.x - (cx + lay.console[1]), sec.trust.z - (cz + lay.console[2])
		return dx * dx + dz * dz <= S.ConsoleRadius * S.ConsoleRadius
	end
	return false
end

local function bandIndexOf(k: number): number
	local idx = 1
	for i, b in Config.Env.Bands do
		if k >= b.first then idx = i end
	end
	return idx
end

-- The State payload. Its key set is asserted exactly by check_signallost: no cell, no relay, no air map, no
-- distance, no stream ever leaves the server.
local function pushState(sess: Session)
	local prof = sess.profile
	local sec = sess.sector
	local payload: any = {
		uid = sess.plr.UserId, -- FireClient reaches only this player; the field lets a test client ignore others
		phase = sess.phase,
		loaded = sess.loaded,
		saving = profileStore ~= nil and sess.canSave,
		storeless = profileStore == nil,
		salvage = prof.salvage,
		best = prof.best,
		arrayDone = prof.arrayAt ~= nil,
		up = { tank = Economy.rankOf(Config, prof.up, "tank"), boots = Economy.rankOf(Config, prof.up, "boots") },
		upRows = upRows(prof),
		recommended = Economy.recommended(Config, prof),
		nearFab = nearFabricator(sess),
		boarding = if sess.phase == "hub" and sess.boardT > 0 then math.clamp(sess.boardT / Config.Run.BoardingSeconds, 0, 1) else 0,
		moduleType = "hub",
	}
	if sec then
		local vac = sess.phase == "sector" and sec.trust ~= nil and sec.plan.vac[sec.trust.cell] == true
		payload.k = sec.k
		payload.band = bandIndexOf(sec.k)
		payload.n = sec.plan.n
		payload.visited = sec.visited
		payload.carried = if prof.open then prof.open.carried else 0
		payload.air = sec.air.air
		payload.tank = sec.air.tank
		payload.hypoxic = sec.air.hypoxic
		payload.grace = Air.graceLeft(Config, sec.air)
		payload.bars = sec.bars or 1
		payload.spliced = sec.spliced
		payload.splicing = if sec.spliceLeft then math.clamp(1 - sec.spliceLeft / Config.Run.SpliceSeconds, 0, 1) else 0
		payload.secondsIn = sec.secondsIn
		payload.moduleType = if sess.phase == "sector" then (if vac then "vacuum" else "air") else sess.phase
	end
	StateRemote:FireClient(sess.plr, payload)
end

--============================================================================ sectors: begin, arrive, end

-- §2.7: every way out of an unspliced sector comes through here. Idempotent: a second call pays nothing.
local function endSector(sess: Session, reason: string): number
	local sec = sess.sector
	local of = if sess.profile.open then sess.profile.open.carried else 0
	local paid = Economy.settle(Config, sess.profile, reason)
	if sec then sec.ended = true end
	if of > 0 or paid > 0 then sess.dirty = true end
	if reason ~= "left" and reason ~= "shutdown" and (of > 0 or paid > 0 or (sec and not sec.spliced)) then
		task.spawn(saveProfile, sess) -- the write that clears `open` is the one that pays it
	end
	-- blackout and return tell the player themselves; a reset (the Roblox Reset button, a fall) is said here
	if reason == "reset" and sec and not sec.spliced then
		notice(sess.plr, "sectorEnd", { reason = reason, paid = paid, of = of })
	end
	return paid
end

local function goHub(sess: Session)
	destroySector(sess)
	sess.sector = nil
	sess.phase = "hub"
	sess.boardT = 0
	applyMove(sess, false)
	if sess.debug then
		sess.debug:Destroy()
		sess.debug = nil
	end
end

-- A fresh plan from engine entropy (Station.freshStreams: Random.new() x 4, no seed), and the dock built.
local function beginSector(sess: Session, k: number)
	destroySector(sess)
	local fx = Economy.effects(Config, sess.profile.up)
	local plan = Station.plan(Config, k, Station.freshStreams(function()
		return Random.new()
	end), MazeGen)
	local sf = folder("Sector", sess.zone)
	local sec: any = {
		k = k,
		id = newToken(),
		plan = plan,
		folder = sf,
		folders = { modules = folder("Modules", sf), hatches = folder("Hatches", sf) },
		modules = {},
		leaves = {},
		open = {},
		lights = {},
		itemParts = {},
		taken = {},
		returnPrompts = {},
		visited = 0,
		spliced = false,
		spliceLeft = nil,
		trust = nil,
		lastCell = nil,
		air = Air.new(Config, fx.tank),
		vacSpeed = fx.vacSpeed,
		secondsIn = 0,
		bars = 1,
		fullTold = nil,
		ended = false,
	}
	sec.isOpen = function(a: number, b: number): boolean
		return sec.open[hatchKey(a, b)] == true
	end
	sec.isVac = function(c: number): boolean
		return plan.vac[c] == true
	end
	sess.sector = sec
	Economy.beginSector(sess.profile, sec.id, k)
	sess.dirty = true
	buildModule(sess, plan.dock)
	writeDebug(sess)
end

local function startTransit(sess: Session, to: string)
	sess.phase = "transit"
	sess.transitLeft = Config.Run.TransitSeconds
	sess.transitTo = to
	moveCharacter(sess, zoneOrigin(sess.zoneIndex) + Vector3.new(0, 3, POD_Z))
	applyMove(sess, false)
end

local function arrive(sess: Session)
	local sec = sess.sector
	local plan = sec.plan
	local cx, cz = Station.cellCenter(Config, plan.n, plan.dock)
	if not moveCharacter(sess, worldOf(sess, cx, 3, cz)) then
		endSector(sess, "reset") -- not alive in the world: the reset path owns this
		goHub(sess)
		return
	end
	sec.trust = Trust.new(Config, plan.n, plan.dock, cx, cz)
	sec.lastCell = plan.dock
	sec.secondsIn = 0
	sec.bars = Meter.between(Config, plan.n, plan.dock, plan.relay)
	sess.phase = "sector"
	applyMove(sess, false)
	writeDebug(sess)
	local band = Config.Env.Bands[bandIndexOf(sec.k)]
	notice(sess.plr, "arrive", { k = sec.k, band = band.name })
end

local function tryStartSector(sess: Session): boolean
	local plr = sess.plr
	if not sess.loaded then
		toast(plr, "Your file is still loading — one moment.")
		return false
	end
	if profileStore and not sess.canSave then
		toast(plr, if sess.loadFailed then "Couldn't reach the save server — retrying." else "Your file is open on another server — retrying.")
		return false
	end
	if sess.buying then
		toast(plr, "Still saving your purchase — one moment.")
		return false
	end
	if sess.profile.open ~= nil then
		toast(plr, "Your last sector is still being settled — retrying.")
		return false
	end
	local char, hum = character(sess)
	if not char or char.Parent == nil or not hum or hum.Health <= 0 then
		toast(plr, "Stand in the LIFT to go down.")
		return false
	end
	local k = sess.profile.best + 1
	beginSector(sess, k)
	startTransit(sess, "sector")
	local band = Config.Env.Bands[bandIndexOf(k)]
	notice(plr, "sector", { k = k, band = band.name, line = band.line })
	return true
end

-- §2.6: the grace ran out. Settle at once (half of what was carried), the fade, then the SAME sector number,
-- generated again from fresh entropy, and the player wakes in its new dock. The Humanoid never dies.
local function blackout(sess: Session)
	local of = if sess.profile.open then sess.profile.open.carried else 0
	local kept = endSector(sess, "blackout")
	sess.phase = "blackout"
	sess.beatLeft = Config.Run.BlackoutBeatSeconds
	notice(sess.plr, "blackout", { kept = kept, of = of })
end

-- The relay module's console and floor hatch wake up after the splice.
buildRelayExtras = function(sess: Session)
	local sec = sess.sector
	local plan = sec.plan
	local mf = sec.modules[plan.relay]
	if not mf or sec.extrasBuilt then return end
	sec.extrasBuilt = true
	local cx, cz = Station.cellCenter(Config, plan.n, plan.relay)
	local c = worldOf(sess, cx, 0, cz)
	local lay = Station.relayLayout(Config)
	local hatch = part({ Name = "FloorHatch", Size = Vector3.new(5, 0.2, 5), CFrame = CFrame.new(c + Vector3.new(lay.floorHatch[1], 0.1, lay.floorHatch[2])),
		Material = Enum.Material.Neon, Color = GOOD, CanCollide = false, Parent = mf })
	Fx.attachGlow(hatch, GOOD, 1.2, 10)
	local console = part({ Name = "RelayConsole", Size = Vector3.new(2.4, 3.2, 2.4), CFrame = CFrame.new(c + Vector3.new(lay.console[1], 1.6, lay.console[2])),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(40, 48, 60), Parent = mf })
	local fabP = prompt(console, "FabricatorPrompt", "Open fabricator", "Upgrades", S.ConsoleRadius)
	fabP.KeyboardKeyCode = Enum.KeyCode.F
	fabP.Triggered:Connect(function(who)
		if who ~= sess.plr then
			toast(who, "That fabricator belongs to another engineer's sector.")
			return
		end
		if not nearFabricator(sess) then
			toast(who, "Step closer to the fabricator.")
			return
		end
		notice(who, "shop")
	end)
	local retP = prompt(console, "ReturnPrompt", "Return to the lifeboat", "RETURN", S.ConsoleRadius)
	retP.GamepadKeyCode = Enum.KeyCode.ButtonB
	sec.returnPrompts[retP] = true
	retP.Triggered:Connect(function(who)
		local onReturn = sess.onReturn
		if onReturn then onReturn(who, retP) end
	end)
end

local function splice(sess: Session)
	local sec = sess.sector
	local plan = sec.plan
	local r = Economy.splice(Config, sess.profile, sec.k, os.time())
	sec.spliced = true
	sec.spliceLeft = nil
	sess.dirty = true
	setRelays(sess)
	if sec.mast then
		sec.mast.Color = GOOD
		local glow = sec.mast:FindFirstChild("FxGlow")
		if glow then (glow :: PointLight).Color = GOOD end
	end
	-- the payoff: every built module's light comes on, rippling out from the dock in doorway order
	for m in sec.modules do
		task.delay(0.12 * (plan.d[m] or 0), function()
			if sess.sector == sec then lightModule(sec, m) end
		end)
	end
	buildRelayExtras(sess)
	writeDebug(sess)
	task.spawn(function()
		saveProfile(sess)
		writeBoard(sess, false)
	end)
	notice(sess.plr, "spliced", { k = sec.k, paid = r.paid, carried = r.carried, bonus = r.bonus, record = r.record, array = r.array })
	if r.array then
		notice(sess.plr, "brag", { k = sec.k })
		AnnounceRemote:FireAllClients({ name = sess.plr.DisplayName, userId = sess.plr.UserId, k = sec.k })
	end
end

--============================================================================ the tick

local function tickHub(sess: Session, dt: number)
	if sess.boardCooldown > 0 then
		sess.boardCooldown -= dt
	end
	local _, _, hrp = character(sess)
	local inside = hrp ~= nil and inLift((hrp :: BasePart).Position)
	if inside and sess.boardCooldown <= 0 then
		if sess.boardT == 0 then
			notice(sess.plr, "boarding")
		end
		sess.boardT += dt
		if sess.boardT >= Config.Run.BoardingSeconds - 1e-6 then
			sess.boardT = 0
			if not tryStartSector(sess) then
				sess.boardCooldown = Config.Run.LiftCooldownSeconds
			end
		end
	elseif not inside and sess.boardT > 0 then
		sess.boardT = 0
		toast(sess.plr, "Boarding cancelled — stand in the LIFT to go down.")
	end
end

local function tickSector(sess: Session, dt: number)
	local sec = sess.sector
	local plan = sec.plan
	local plr = sess.plr
	sec.secondsIn += dt

	-- 1. the trusted position (§14), at the speed the SERVER set for the module the player is trusted to be in
	local _, _, hrp = character(sess)
	local t = sec.trust
	local vacNow = plan.vac[t.cell] == true
	local claimY = S.StandHeight
	t.vacStuds = 0
	if hrp then
		local o = zoneOrigin(sess.zoneIndex)
		local p = (hrp :: BasePart).Position
		local speed = if vacNow then sec.vacSpeed else Config.Move.AirWalkSpeed
		Trust.step(Config, t, p.X - o.X, p.Z - o.Z, dt, speed, sec.isOpen, sec.isVac)
		claimY = p.Y - o.Y
	end
	local cell = t.cell
	local vac = plan.vac[cell] == true
	local trustY = Trust.clampHeight(Config, claimY, vac)

	-- 2. hatches open by themselves on a trusted approach from the adjacent module
	for _, nb in Station.hatchesNear(Config, plan, cell, t.x, t.z, sec.isOpen) do
		openHatch(sess, cell, nb)
	end

	-- 3. entering a module: speed and jump follow its type; the meter follows its distance to the relay
	if cell ~= sec.lastCell then
		sec.lastCell = cell
		applyMove(sess, vac)
		sec.bars = Meter.between(Config, plan.n, cell, plan.relay)
		if vac then
			notice(plr, "vacuum", { first = not sess.firstVacuumTold })
			sess.firstVacuumTold = true
		else
			notice(plr, "air")
		end
		if sess.debug then sess.debug:SetAttribute("TrustedCell", cell) end
	end

	-- 4. AIR (§2.3): server arithmetic. A tick costs its time in vacuum OR the vacuum distance the trusted path covered
	--    at the vacuum walk speed, whichever is more (REVIEW-1 finding 1: charging only the module a tick ENDED in let
	--    a client that writes its position cross a vacuum module between two ticks for free). Then air refills.
	local events = {}
	local charge = Air.vacuumCharge(Config, sec.air, dt, vac, t.vacStuds, sec.vacSpeed)
	if charge > 0 then
		events = Air.step(Config, sec.air, charge, true)
	end
	if not vac and not sec.air.blackedOut then
		for _, e in Air.step(Config, sec.air, dt, false) do
			table.insert(events, e)
		end
	end
	for _, e in events do
		if e == "blackout" then
			blackout(sess)
			return
		elseif e == "hypoxic" then
			notice(plr, "hypoxic")
		elseif e == "recovered" then
			notice(plr, "recovered")
		end
	end

	-- 5. pickups: in the item's module, within PickupRadius horizontally and the height window
	local item = plan.items[cell]
	if item and not sec.taken[cell] then
		local cx, cz = Station.cellCenter(Config, plan.n, cell)
		local dx, dz = t.x - (cx + item.x), t.z - (cz + item.z)
		local inReach = dx * dx + dz * dz <= S.PickupRadius * S.PickupRadius and math.abs(trustY - item.y) <= S.PickupHeightWindow
		if inReach and item.kind == "salvage" and sec.spliced then
			-- carried salvage is banked only AT a splice (§2.5); after it there is nothing to carry it into, so the
			-- piece stays where it floats and the player is told why, never a silent "+0"
			if not sec.toldLogged then
				sec.toldLogged = true
				toast(plr, "Relay spliced — this sector's salvage is already logged. Drop through the floor hatch.")
			end
		elseif inReach and item.kind == "salvage" then
			sec.taken[cell] = true
			local p = sec.itemParts[cell]
			if p then p:Destroy() end
			local v = Economy.carry(Config, sess.profile, sec.k)
			sess.dirty = true
			notice(plr, "salvage", { value = v, carried = if sess.profile.open then sess.profile.open.carried else 0 })
		elseif inReach and item.kind == "canister" then
			if Air.canister(Config, sec.air) then
				sec.taken[cell] = true
				local p = sec.itemParts[cell]
				if p then p:Destroy() end
				sec.fullTold = nil
				notice(plr, "canister", { air = sec.air.air })
			elseif sec.fullTold ~= cell then
				sec.fullTold = cell
				toast(plr, "AIR FULL — canister left here.")
			end
		elseif not inReach and sec.fullTold == cell then
			sec.fullTold = nil
		end
	end

	-- 6. the splice: automatic within SpliceRadius of the mast; two seconds nothing can interrupt (you are in air)
	if cell == plan.relay and not sec.spliced then
		if sec.spliceLeft == nil then
			local cx, cz = Station.cellCenter(Config, plan.n, cell)
			local dx, dz = t.x - cx, t.z - cz
			if dx * dx + dz * dz <= S.SpliceRadius * S.SpliceRadius then
				sec.spliceLeft = Config.Run.SpliceSeconds
				notice(plr, "splicing", { seconds = Config.Run.SpliceSeconds })
			end
		end
	end
	if sec.spliceLeft ~= nil and not sec.spliced then
		sec.spliceLeft -= dt
		if sec.spliceLeft <= 1e-6 then
			splice(sess)
		end
	end

	-- 7. after the splice, the floor hatch drops you into the next sector
	if sec.spliced and cell == plan.relay then
		local lay = Station.relayLayout(Config)
		local cx, cz = Station.cellCenter(Config, plan.n, cell)
		local dx, dz = t.x - (cx + lay.floorHatch[1]), t.z - (cz + lay.floorHatch[2])
		if dx * dx + dz * dz <= S.FloorHatchRadius * S.FloorHatchRadius then
			if sess.buying then
				if not sec.toldBuying then
					sec.toldBuying = true
					toast(plr, "Still saving your purchase — one moment.")
				end
			else
				local k = sec.k + 1
				beginSector(sess, k)
				startTransit(sess, "sector")
				local band = Config.Env.Bands[bandIndexOf(k)]
				notice(plr, "sector", { k = k, band = band.name, line = band.line })
			end
		end
	end
end

local function tickSession(sess: Session, dt: number)
	if sess.phase == "hub" then
		tickHub(sess, dt)
	elseif sess.phase == "transit" then
		sess.transitLeft -= dt
		if sess.transitLeft <= 1e-6 then
			if sess.transitTo == "sector" and sess.sector then
				arrive(sess)
			else
				moveCharacter(sess, hubArrival.Position + Vector3.new(0, 3, 0))
				goHub(sess)
				notice(sess.plr, "home")
			end
		end
	elseif sess.phase == "sector" and sess.sector then
		tickSector(sess, dt)
	elseif sess.phase == "blackout" then
		sess.beatLeft -= dt
		if sess.beatLeft <= 1e-6 then
			-- the next sector to play is always best + 1: an unspliced sector IS best + 1 (the lift and the floor
			-- hatch only ever start best + 1), and a blackout AFTER a splice must not replay the relay just spliced
			local k = sess.profile.best + 1
			if sess.buying or (profileStore and not sess.canSave) then
				moveCharacter(sess, hubArrival.Position + Vector3.new(0, 3, 0))
				goHub(sess)
			else
				beginSector(sess, k)
				arrive(sess)
			end
		end
	end

	sess.pushLeft -= dt
	if sess.pushLeft <= 1e-6 then
		sess.pushLeft = Config.Server.StatePushSeconds
		pushState(sess)
	end
end

task.spawn(function()
	while true do
		local dt = task.wait(TICK)
		for _, sess in sessions do
			-- a closing session (leaving, or the server shutting down) never ticks again: no arrival, blackout or
			-- splice may happen, or start a save, while its releasing write is in flight (REVIEW-1 finding 2)
			if sess.closing then continue end
			local ok, err = pcall(tickSession, sess, dt)
			if not ok then
				warn("[SignalLost] tick failed for " .. sess.plr.Name .. ": " .. tostring(err))
			end
		end
	end
end)

--============================================================================ RETURN

local function onReturn(sess: Session, who: Player, pr: ProximityPrompt)
	if who ~= sess.plr then
		toast(who, "That console belongs to another engineer's sector.")
		return
	end
	local sec = sess.sector
	if sess.phase ~= "sector" or not sec or not sec.trust then
		toast(who, "The RETURN console works once you are in the sector.")
		return
	end
	local host = pr.Parent :: BasePart
	local o = zoneOrigin(sess.zoneIndex)
	local dx, dz = sec.trust.x - (host.Position.X - o.X), sec.trust.z - (host.Position.Z - o.Z)
	if dx * dx + dz * dz > S.ConsoleRadius * S.ConsoleRadius then
		toast(who, "Step closer to the RETURN console.")
		return
	end
	if sess.buying then
		toast(who, "Still saving your purchase — one moment.")
		return
	end
	local unspliced = not sec.spliced
	local of = if sess.profile.open then sess.profile.open.carried else 0
	local paid = endSector(sess, "return")
	notice(who, "returning", { unspliced = unspliced, paid = paid, of = of })
	destroySector(sess)
	startTransit(sess, "hub")
end

--============================================================================ BuyUpgrade (§9)

BuyRemote.OnServerEvent:Connect(function(plr, id)
	local sess = sessions[plr]
	if not sess or sess.closing then return end
	-- the cooldown comes FIRST and a refusal inside it is said once (REVIEW-1 finding 3): a flood of calls gets one
	-- answer per BuyCooldownSeconds, never one RemoteEvent reply per call
	local now = clock()
	if now - sess.buyAt < Config.Upgrades.BuyCooldownSeconds then
		if not sess.buyBusyTold then
			sess.buyBusyTold = true
			toast(plr, "One moment…")
		end
		return
	end
	sess.buyAt = now
	sess.buyBusyTold = false
	if type(id) ~= "string" or Config.Upgrades.Catalog[id] == nil then
		toast(plr, "That upgrade does not exist.")
		return
	end
	if not sess.loaded then
		toast(plr, "Your file is still loading — one moment.")
		return
	end
	if not profileStore then
		toast(plr, "Progress can't be saved on this server, so nothing can be bought.")
		return
	end
	if not sess.canSave then
		toast(plr, "Your file is open on another server — nothing can be bought right now.")
		return
	end
	if sess.buying then
		toast(plr, "Still saving your last purchase…")
		return
	end
	if not nearFabricator(sess) then
		toast(plr, "Stand at a fabricator to buy upgrades.")
		return
	end
	local ok, why = Economy.canBuy(Config, sess.profile, id)
	if not ok then
		toast(plr, why or "You can't buy that.")
		return
	end
	sess.buying = true
	local snap = Economy.snapshot(sess.profile)
	local price = Economy.buy(Config, sess.profile, id)
	local persisted = saveProfile(sess)
	sess.buying = false
	if sessions[plr] ~= sess then return end
	if not persisted then
		Economy.restore(sess.profile, snap)
		toast(plr, "Couldn't reach the save server — nothing was spent.")
	else
		local u = Config.Upgrades.Catalog[id]
		-- the new tank or boots apply from the next sector attempt (a sector is played with what it began with)
		notice(plr, "purchased", { id = id, name = u.name, rank = sess.profile.up[id], price = price })
	end
	pushState(sess)
end)

hubFabPrompt.Triggered:Connect(function(who)
	local sess = sessions[who]
	if not sess then return end
	if sess.phase ~= "hub" then
		toast(who, "That fabricator is in the lifeboat.")
		return
	end
	notice(who, "shop")
end)

--============================================================================ §10.3 the board in the world

local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then return cached end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		nameCache[userId] = here.Name
		return here.Name
	end
	local ok, res = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(res) == "string" then
		nameCache[userId] = res
		return res
	end
	return "#" .. tostring(userId) -- not cached: the next view tries again
end
local function withNames(rows: { any }): { any }
	local out = {}
	for i, r in rows do
		out[i] = { rank = r.rank, userId = r.userId, tier = r.tier, you = r.you, star = r.star, name = nameOf(r.userId) }
	end
	return out
end

-- A player's own value, from memory (fresher than the store).
local function liveValue(sess: Session?): number
	if not sess or sess.profile.best <= 0 then return 0 end
	return Board.encode(sess.profile.best, sess.profile.bestAt, BC)
end

local publicView: any = { rows = {}, note = BC.Text.Loading }
local function sendBoard(plr: Player, mode: string, view: any)
	BoardRemote:FireClient(plr, { viewer = plr.UserId, mode = mode, rows = view.rows, note = view.note })
end

local function refreshPublic()
	if not orderedStore then
		publicView = Board.publicView({}, BC)
		return
	end
	local ok, page = pcall(function()
		return (orderedStore :: any):GetSortedAsync(false, BC.PublicRows)
	end)
	if not ok or not page then return end -- keep the last list
	local okPage, items = pcall(function()
		return page:GetCurrentPage()
	end)
	if not okPage or type(items) ~= "table" then return end
	local entries = {}
	for _, e in ipairs(items) do
		local uid = Board.userIdOf(tostring(e.key))
		if uid and type(e.value) == "number" then
			table.insert(entries, { userId = uid, value = e.value })
		end
	end
	local view = Board.publicView(entries, BC)
	publicView = { rows = withNames(view.rows), note = view.note }
end

local friendsCache = Board.newCache(BC.FriendsCacheSeconds)
local friendsFailed = Board.newCache(60)
local scoreCache = Board.newCache(BC.ScoreCacheSeconds)
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, clock())
local fetching: { [Player]: boolean } = {}

local function friendIdsOf(plr: Player): ({ number }, boolean)
	local now = clock()
	local hit = Board.cacheGet(friendsCache, plr.UserId, now)
	if hit then return hit, false end
	if Board.cacheHas(friendsFailed, plr.UserId, now) then return {}, true end
	local ok, pages = pcall(function()
		return (Players :: any):GetFriendsAsync(plr.UserId)
	end)
	local ids = {}
	local broken = not ok or pages == nil
	while not broken and #ids < BC.FriendsCap do
		local okPage, items = pcall(function()
			return pages:GetCurrentPage()
		end)
		if not okPage or type(items) ~= "table" then
			broken = #ids == 0
			break
		end
		for _, item in ipairs(items) do
			local id = tonumber(item.Id)
			if id and #ids < BC.FriendsCap then
				table.insert(ids, id)
				if type(item.Username) == "string" then nameCache[id] = item.Username end
			end
		end
		if pages.IsFinished or #ids >= BC.FriendsCap then break end
		if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
	end
	if broken then
		Board.cachePut(friendsFailed, plr.UserId, true, now)
		return {}, true
	end
	Board.cachePut(friendsCache, plr.UserId, ids, now)
	return ids, false
end

-- Keep BudgetReserve GetAsync requests in Roblox's budget for profile loads.
local function budgetLeft(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return not (ok and type(budget) == "number" and budget < BC.BudgetReserve)
end

-- A friend's stored value (0 = none), or nil when throttled (try again later).
local function friendValue(userId: number): number?
	local here = Players:GetPlayerByUserId(userId)
	if here and sessions[here] then return liveValue(sessions[here]) end
	local now = clock()
	if Board.cacheHas(scoreCache, userId, now) then return Board.cacheGet(scoreCache, userId, now) end
	if not orderedStore then return 0 end
	if not budgetLeft() or not Board.take(readLimiter, now) then return nil end
	local ok, v = pcall(function()
		return (orderedStore :: any):GetAsync(key(userId))
	end)
	if not ok then return 0 end
	local value = if type(v) == "number" then v else 0
	Board.cachePut(scoreCache, userId, value, now)
	return value
end

local function showFriends(plr: Player)
	if fetching[plr] then
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading })
		return
	end
	fetching[plr] = true
	task.spawn(function()
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading })
		local ids, failedList = friendIdsOf(plr)
		local values: { [number]: number } = {}
		local status = { friendCount = #ids, checked = 0, failed = failedList }
		local function push()
			values[plr.UserId] = liveValue(sessions[plr])
			local view = Board.friendsView(plr.UserId, values, status, BC)
			sendBoard(plr, "friends", { rows = withNames(view.rows), note = view.note })
		end
		local i, lastPush = 1, -math.huge
		local sess = sessions[plr]
		while i <= #ids and plr.Parent == Players and sess and sess.boardMode == "friends" do
			local v = friendValue(ids[i])
			if v == nil then
				status.checked = i - 1
				if clock() - lastPush >= 0.5 then
					push()
					lastPush = clock()
				end
				task.wait(1)
			else
				values[ids[i]] = v
				i += 1
			end
		end
		status.checked = i - 1
		if plr.Parent == Players and sess and sess.boardMode == "friends" then push() end
		fetching[plr] = nil
	end)
end

boardPrompt.Triggered:Connect(function(plr: Player)
	local sess = sessions[plr]
	if not sess then return end
	local now = clock()
	if now - sess.boardToggleAt < BC.ToggleCooldownSeconds then
		toast(plr, "One moment…")
		return
	end
	sess.boardToggleAt = now
	sess.boardMode = if sess.boardMode == "friends" then "public" else "friends"
	if sess.boardMode == "friends" then
		showFriends(plr)
	else
		sendBoard(plr, "public", publicView)
	end
end)

task.spawn(function()
	while true do
		refreshPublic()
		for plr, sess in sessions do
			if sess.boardMode == "public" then sendBoard(plr, "public", publicView) end
		end
		task.wait(BC.PublicCacheSeconds)
	end
end)

--============================================================================ join / leave

local function onCharacter(sess: Session, char: Model)
	-- NO CFrame write and NO yield here (SPAWN-ORDER.md): RespawnLocation already puts us on HubSpawn.
	if sess.closing then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = Config.Move.AirWalkSpeed
		pcall(function()
			(hum :: any).UseJumpPower = false
			;(hum :: any).JumpHeight = Config.Move.AirJumpHeight
		end)
		hum.Died:Connect(function()
			if sessions[sess.plr] ~= sess or sess.closing or sess.plr.Character ~= char then return end
			if sess.sector then
				endSector(sess, "reset")
			end
			if sess.phase ~= "hub" then
				goHub(sess)
			end
		end)
	end
	pcall(function()
		sess.plr.CameraMode = Enum.CameraMode.Classic
	end)
	if sess.sector then
		endSector(sess, "reset") -- idempotent: Died has usually settled it already
	end
	if sess.phase ~= "hub" then
		goHub(sess)
	end
end

local function onPlayerAdded(plr: Player)
	if sessions[plr] then return end
	plr.RespawnLocation = hubSpawn

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local relays = Instance.new("IntValue")
	relays.Name = "Relays"
	relays.Value = 0
	relays.Parent = ls
	ls.Parent = plr

	local index = acquireZone()
	local zone = folder("Zone_" .. index, stationFolder)
	buildPod(zone, zoneOrigin(index))

	local sess: Session = {
		plr = plr,
		profile = Economy.newProfile(Config),
		loaded = false,
		canSave = false,
		token = newToken(),
		closing = false,
		buying = false,
		buyBusyTold = false,
		loadFailed = false,
		dirty = false,
		saveTick = 0,
		zoneIndex = index,
		zone = zone,
		phase = "hub",
		boardT = 0,
		boardCooldown = 0,
		transitLeft = 0,
		transitTo = "sector",
		beatLeft = 0,
		pushLeft = 0,
		sector = nil,
		buyAt = -math.huge,
		boardToggleAt = -math.huge,
		boardMode = "public",
		lastOrdered = 0,
		lastOrderedAt = nil,
		firstVacuumTold = false,
		debug = nil,
	}
	;(sess :: any).onReturn = function(who: Player, pr: ProximityPrompt)
		onReturn(sess, who, pr)
	end
	sessions[plr] = sess

	plr.CharacterAdded:Connect(function(char)
		if sessions[plr] == sess then
			onCharacter(sess, char)
		end
	end)
	if plr.Character then
		onCharacter(sess, plr.Character)
	end
	sendBoard(plr, "public", publicView)

	-- ------------------------------------------------ and NOW the network call (it may yield)
	if not profileStore then
		sess.loaded = true
		pushState(sess)
		toast(plr, "Saving is unavailable on this server — you can play, but progress will not be kept.")
		return
	end
	local function attempt()
		local got, data, failed = claimProfile(sess)
		if sessions[plr] ~= sess or plr.Parent == nil or sess.closing then
			if got then releaseLock(sess) end
			return
		end
		sess.loadFailed = failed
		if got then
			sess.profile = Economy.sanitize(Config, data)
			sess.canSave = true
			sess.lastOrdered = 0
			if sess.profile.open ~= nil then
				-- the server died mid-sector last time: settle it the §2.7 way, once, before anything else
				local paid = Economy.settle(Config, sess.profile, "crashed")
				saveProfile(sess)
				toast(plr, string.format("Your last sector ended when the server did — you kept %d salvage.", paid))
			end
		elseif not sess.loaded then
			-- another server holds the file: show its data read-only, and retry on autosave
			sess.profile = Economy.sanitize(Config, data)
			sess.profile.open = nil
			toast(plr, if failed then "Couldn't reach the save server — retrying." else "Your file is open on another server — retrying.")
		end
		sess.loaded = true
		setRelays(sess)
	end
	attempt()
	if sessions[plr] ~= sess then return end
	pushState(sess)
	writeBoard(sess, false)

	task.spawn(function()
		while sessions[plr] == sess do
			task.wait(Config.Data.AutosaveSeconds)
			if sessions[plr] ~= sess or sess.closing then break end
			if sess.canSave then
				sess.saveTick += 1
				-- dirty-only, but the lock is renewed at least every second autosave (45 s > 2 x 20 s)
				if not sess.buying and (sess.dirty or sess.saveTick % 2 == 0) then
					saveProfile(sess)
				end
				writeBoard(sess, false)
			elseif not sess.sector then
				attempt()
			end
		end
	end)
end

local function onPlayerRemoving(plr: Player)
	local sess = sessions[plr]
	if not sess then return end
	sess.closing = true
	endSector(sess, "left")
	saveProfile(sess, true)
	writeBoard(sess, true)
	sessions[plr] = nil
	fetching[plr] = nil
	sess.zone:Destroy()
	zoneTaken[sess.zoneIndex] = nil
	if sess.debug then
		sess.debug:Destroy()
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
end

game:BindToClose(function()
	-- every session is marked closing FIRST, so none ticks on while another's write waits (REVIEW-1 finding 2), then
	-- every releasing write runs at once: the shutdown waits for the slowest one, not for their sum
	local list = {}
	for _, sess in sessions do
		sess.closing = true
		table.insert(list, sess)
	end
	local left = #list
	for _, sess in list do
		task.spawn(function()
			pcall(function()
				endSector(sess, "shutdown")
				saveProfile(sess, true)
				writeBoard(sess, true)
			end)
			left -= 1
		end)
	end
	local waited = 0
	while left > 0 and waited < 25 do
		waited += task.wait(0.1)
	end
end)

-- Silence "unused" for helpers kept for the checks and the art (the band list is read by the clients).
local _ = EnvBands
