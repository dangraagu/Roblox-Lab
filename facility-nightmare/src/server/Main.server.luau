-- Main.server.luau — authoritative server for FACILITY: Endless Nightmare.
--
-- One shared break room (the hub) at the world origin; one private zone per player 400 studs apart
-- along +X. A run: walk into the hub car -> ride -> a freshly generated sublevel whose rooms are
-- built one at a time as their doors open -> find the fuses while the blackout front turns rooms
-- dark ring by ring -> power the freight elevator -> EXTRACT (bank the run) or DESCEND. The dark
-- takes you if you stand in it with no light for the grace; that ends the run and keeps a share.
-- Everything is in DESIGN.md; the section numbers below point there.
--
-- THE RULES THIS FILE IS WRITTEN AGAINST (each one cost a sibling game a shipped defect):
--   * Requires go through Instances (`require(ReplicatedStorage:WaitForChild("X"))`), never a path.
--   * The hub and HubSpawn are built synchronously BEFORE PlayerAdded is connected and before any
--     DataStore call, and HubSpawn is the only enabled SpawnLocation anywhere. PlayerAdded points
--     plr.RespawnLocation at it, so the engine's own placement is already right; the
--     CharacterAdded handler writes no CFrame and never yields (robloxemu/SPAWN-ORDER.md).
--   * Every rule reads the TRUSTED position and cell (shared/Trust.luau), never the claim.
--   * Nothing that gives the floor away is written to an Instance: not the exit, not an unopened
--     room, not d[], step or hold, not a seed. Zones carry ZERO attributes. Test-only data lives in
--     ServerStorage.FacilityDebug, which never replicates (§7.2, anomaly-observatory's lesson).
--   * Run time is accumulated from task.wait's return value; the emulator drives a virtual clock.
--   * No Raycast, no PathfindingService, no Touched in any rule: everything spatial is grid maths.
--   * Every refused request gets a toast. Nothing fails silently.
--   * A run is paid exactly once (shared/Economy.luau settle), whatever ends it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage
local Config = require(Shared:WaitForChild("Config"))
local Rng = require(Shared:WaitForChild("Rng"))
local MazeGen = require(Shared:WaitForChild("MazeGen"))
local Facility = require(Shared:WaitForChild("Facility"))
local Survival = require(Shared:WaitForChild("Survival"))
local Trust = require(Shared:WaitForChild("Trust"))
local Economy = require(Shared:WaitForChild("Economy"))
local Fx = require(Shared:WaitForChild("Fx"))

-- Visuals from the first build (checklist §2): an unlit room must read DARK, not dim.
Fx.applyLighting(Fx.Presets.Facility)

pcall(function()
	(Players :: any).RespawnTime = Config.Server.RespawnTime
end)

local F = Config.Facility
local CELL = F.CellSize
local TICK = Config.Run.ServerTickSeconds

local function rgb(t)
	return Color3.fromRGB(t.r, t.g, t.b)
end

--============================================================================ remotes

local Remotes = Instance.new("Folder")
Remotes.Name = "FacilityRemotes"
Remotes.Parent = ReplicatedStorage
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = Remotes
	return r
end
local StateRemote = remote("State") -- server -> owner, 5 Hz
local NoticeRemote = remote("Notice") -- server -> owner: (kind, data)
local FlashlightRemote = remote("Flashlight") -- client -> server: (boolean)
local SprintRemote = remote("Sprint") -- client -> server: (boolean)
local ChooseRemote = remote("Choose") -- client -> server: ("extract" | "descend")
local BuyPerkRemote = remote("BuyPerk") -- client -> server: (perkId)

local function notice(plr: Player, kind: string, data: any?)
	NoticeRemote:FireClient(plr, kind, data)
end
local function toast(plr: Player, text: string)
	notice(plr, "toast", text)
end

--============================================================================ DataStore

local okStore, profileStore = pcall(function()
	return DataStoreService:GetDataStore(Config.Data.Store)
end)
if not okStore then
	profileStore = nil
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

-- The canvas takes the FACE's proportions (100 px per stud): a SurfaceGui canvas is stretched onto
-- its face, so a fixed 400x200 drew SERVICE ELEVATOR 2.2 times too wide and PERKS 2.5 times too
-- tall. Axis-aligned hosts only, which every labelled part here is.
local function label(host: BasePart, face, text: string, textColor: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face
	local s = host.Size
	local w, hh = s.X, s.Y
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		w, hh = s.Z, s.Y
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		w, hh = s.X, s.Z
	end
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
	t.TextColor3 = textColor
	t.Parent = gui
	return t
end

--============================================================================ §8 the hub, FIRST

local H = Config.Hub
local hubFolder = folder("Hub", workspace)
local WALL_COLOR = Color3.fromRGB(58, 62, 66)

part({ Name = "HubFloor", Size = Vector3.new(H.SizeX, 1, H.SizeZ), CFrame = CFrame.new(0, -0.5, 0),
	Material = Enum.Material.Concrete, Color = Color3.fromRGB(70, 72, 74), Parent = hubFolder })
part({ Name = "HubCeiling", Size = Vector3.new(H.SizeX, 1, H.SizeZ), CFrame = CFrame.new(0, H.Height + 0.5, 0),
	Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(40, 42, 44), Parent = hubFolder })
for _, w in {
	{ "HubWallE", Vector3.new(1, H.Height, H.SizeZ), Vector3.new(H.SizeX / 2 + 0.5, H.Height / 2, 0) },
	{ "HubWallW", Vector3.new(1, H.Height, H.SizeZ), Vector3.new(-H.SizeX / 2 - 0.5, H.Height / 2, 0) },
	{ "HubWallN", Vector3.new(H.SizeX + 2, H.Height, 1), Vector3.new(0, H.Height / 2, H.SizeZ / 2 + 0.5) },
	{ "HubWallS", Vector3.new(H.SizeX + 2, H.Height, 1), Vector3.new(0, H.Height / 2, -H.SizeZ / 2 - 0.5) },
} do
	part({ Name = w[1], Size = w[2], CFrame = CFrame.new(w[3]), Material = Enum.Material.SmoothPlastic, Color = WALL_COLOR, Parent = hubFolder })
end
for i, x in { -18, 0, 18 } do
	local lamp = part({ Name = "HubLamp" .. i, Size = Vector3.new(6, 0.4, 3), CFrame = CFrame.new(x, H.Height - 0.2, 0),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 236, 200), CanCollide = false, Parent = hubFolder })
	local light = Instance.new("PointLight")
	light.Name = "HubLight"
	light.Range = 40
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 230, 190)
	light.Parent = lamp
end

local hubSpawn = Instance.new("SpawnLocation")
hubSpawn.Name = "HubSpawn"
hubSpawn.Size = Vector3.new(6, 1, 6)
hubSpawn.CFrame = CFrame.new(H.SpawnX, 0.5, 0)
hubSpawn.Anchored = true
hubSpawn.Enabled = true -- explicit: a disabled SpawnLocation is not a legal RespawnLocation
hubSpawn.Neutral = true
hubSpawn.Duration = 0 -- no ForceField
hubSpawn.Material = Enum.Material.DiamondPlate
hubSpawn.Color = Color3.fromRGB(90, 94, 98)
hubSpawn.Parent = hubFolder

local hubArrival = part({ Name = "HubArrival", Size = Vector3.new(6, 0.2, 6), CFrame = CFrame.new(H.ArrivalX, 0.1, H.ArrivalZ),
	Material = Enum.Material.DiamondPlate, Color = Color3.fromRGB(90, 94, 98), CanCollide = false, Parent = hubFolder })

-- The service elevator: open toward the spawn (-X), closed on its other three sides.
local hubCar = folder("HubCar", hubFolder)
do
	local cx, d, w = H.CarX, H.CarDepth, H.CarWidth
	part({ Name = "CarFloor", Size = Vector3.new(d, 0.4, w), CFrame = CFrame.new(cx, 0.2, 0),
		Material = Enum.Material.DiamondPlate, Color = Color3.fromRGB(120, 124, 128), Parent = hubCar })
	part({ Name = "CarBack", Size = Vector3.new(0.6, 10, w + 1.2), CFrame = CFrame.new(cx + d / 2 + 0.3, 5, 0),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(80, 84, 90), Parent = hubCar })
	part({ Name = "CarSideN", Size = Vector3.new(d, 10, 0.6), CFrame = CFrame.new(cx, 5, w / 2 + 0.3),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(80, 84, 90), Parent = hubCar })
	part({ Name = "CarSideS", Size = Vector3.new(d, 10, 0.6), CFrame = CFrame.new(cx, 5, -w / 2 - 0.3),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(80, 84, 90), Parent = hubCar })
	part({ Name = "CarRoof", Size = Vector3.new(d + 0.6, 0.4, w + 1.2), CFrame = CFrame.new(cx, 10.2, 0),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(60, 64, 70), Parent = hubCar })
	local sign = part({ Name = "CarSign", Size = Vector3.new(0.2, 1.6, 7), CFrame = CFrame.new(cx + d / 2 - 0.1, 8.6, 0),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(30, 18, 8), CanCollide = false, Parent = hubCar })
	label(sign, Enum.NormalId.Left, "SERVICE ELEVATOR", rgb(Config.Hud.Accent))
	Fx.attachGlow(sign, rgb(Config.Hud.Accent), 1.2, 14)
	-- the guide strip on the floor: the thing to walk toward glows
	part({ Name = "GuideStrip", Size = Vector3.new(H.CarX - d / 2 - (H.SpawnX + 3), 0.05, 1),
		CFrame = CFrame.new((H.CarX - d / 2 + H.SpawnX + 3) / 2, 0.03, 0),
		Material = Enum.Material.Neon, Color = rgb(Config.Hud.Accent), CanCollide = false, Parent = hubCar })
end

local perkTerminal = part({ Name = "PerkTerminal", Size = Vector3.new(4, 5, 1), CFrame = CFrame.new(H.TerminalX, 2.5, H.SizeZ / 2 - 0.5),
	Material = Enum.Material.Metal, Color = Color3.fromRGB(40, 44, 50), Parent = hubFolder })
do
	label(perkTerminal, Enum.NormalId.Front, "PERKS", rgb(Config.Hud.Good))
	Fx.attachGlow(perkTerminal, rgb(Config.Hud.Good), 1, 10)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PerkPrompt"
	prompt.ActionText = "Open perks"
	prompt.ObjectText = "Terminal"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = perkTerminal
	prompt.Triggered:Connect(function(who)
		notice(who, "perks")
	end)
end

local function inHubCar(pos: Vector3): boolean
	return math.abs(pos.X - H.CarX) <= H.CarDepth / 2 and math.abs(pos.Z) <= H.CarWidth / 2 and pos.Y < 10
end

--============================================================================ zones

local facilityFolder = folder("Facility", workspace)
local debugRoot = folder("FacilityDebug", ServerStorage)

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

local RIDE_Z = -(5 * CELL / 2 + Config.Server.RideCarOffset)

local function buildRideCar(zone: Folder, origin: Vector3)
	local car = folder("RideCar", zone)
	local o = origin + Vector3.new(0, 0, RIDE_Z)
	local metal = Color3.fromRGB(62, 64, 70)
	part({ Name = "RideFloor", Size = Vector3.new(10, 1, 10), CFrame = CFrame.new(o + Vector3.new(0, -0.5, 0)),
		Material = Enum.Material.DiamondPlate, Color = Color3.fromRGB(100, 104, 110), Parent = car })
	local roof = part({ Name = "RideRoof", Size = Vector3.new(10, 1, 10), CFrame = CFrame.new(o + Vector3.new(0, 10.5, 0)),
		Material = Enum.Material.Metal, Color = metal, Parent = car })
	for _, w in {
		{ "RideWallE", Vector3.new(1, 10, 10), Vector3.new(5.5, 5, 0) },
		{ "RideWallW", Vector3.new(1, 10, 10), Vector3.new(-5.5, 5, 0) },
		{ "RideWallN", Vector3.new(12, 10, 1), Vector3.new(0, 5, 5.5) },
		{ "RideWallS", Vector3.new(12, 10, 1), Vector3.new(0, 5, -5.5) },
	} do
		part({ Name = w[1], Size = w[2], CFrame = CFrame.new(o + w[3]), Material = Enum.Material.Metal, Color = metal, Parent = car })
	end
	local light = Instance.new("PointLight")
	light.Name = "RideLight"
	light.Range = 12
	light.Brightness = 1
	light.Color = Color3.fromRGB(255, 120, 90)
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
	loadFailed: boolean, -- the last claim raised (store error), as opposed to a lock held elsewhere
	zoneIndex: number,
	zone: Folder,
	floor: Folder?,
	phase: string, -- "hub" | "ride" | "floor" | "dying"
	boardT: number,
	boardCooldown: number,
	rideLeft: number,
	rideTo: string, -- "floor" | "hub"
	beatLeft: number,
	pushLeft: number,
	autosaveLeft: number,
	run: any?,
	wantLight: boolean,
	wantSprint: boolean,
	sprintPress: boolean, -- a fresh press since the last floor tick (Survival re-arms on it)
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

local function key(plr: Player): string
	return "u_" .. plr.UserId
end

-- One lock-claim attempt with UpdateAsync. The owner is a STABLE per-session GUID, never a
-- timestamp we also rewrite (checklist: session lock). Returns got, data, failed.
local function claimProfile(sess: Session): (boolean, any, boolean)
	if not profileStore then
		return false, nil, true
	end
	local got, data = false, nil
	local ok = pcall(function()
		(profileStore :: any):UpdateAsync(key(sess.plr), function(old)
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

-- Give back a lock this session holds WITHOUT writing its data: for a claim that came back after
-- the player had already left (REVIEW-1 A2). The profile was never loaded into this session, so
-- there is nothing of ours to save; the stored data is carried over untouched.
local function releaseLock(sess: Session)
	if not profileStore then
		return
	end
	pcall(function()
		(profileStore :: any):UpdateAsync(key(sess.plr), function(old)
			if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.owner ~= sess.token then
				return nil -- not ours (any more): leave it alone
			end
			return { data = old.data, lock = nil }
		end)
	end)
end

-- Flush the WHOLE profile under the lock. Returns true only if the write persisted.
local function saveProfile(sess: Session, releasing: boolean?): boolean
	if not profileStore or not sess.canSave then
		return false
	end
	local payload = Economy.snapshot(sess.profile)
	local wrote = false
	local lostLock = false
	local ok, result = pcall(function()
		return (profileStore :: any):UpdateAsync(key(sess.plr), function(old)
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
	end
	return ok and result ~= nil and wrote
end

local function setDeepest(sess: Session)
	local ls = sess.plr:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Deepest")
	if v then
		(v :: IntValue).Value = sess.profile.bestSublevel
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

-- §8.5: every server move is guarded — a character that is not alive in the world is already on
-- the reset path, and its run is already settled.
local function moveCharacter(sess: Session, pos: Vector3): boolean
	local char, hum, hrp = character(sess)
	if not char or char.Parent == nil or not hum or hum.Health <= 0 or not hrp then
		return false
	end
	char:PivotTo(CFrame.new(pos))
	return true
end

local function setCamera(sess: Session, firstPerson: boolean)
	pcall(function()
		sess.plr.CameraMode = if firstPerson then Enum.CameraMode.LockFirstPerson else Enum.CameraMode.Classic
	end)
end

local function flashlightOf(sess: Session): SpotLight?
	local char = sess.plr.Character
	if not char then return nil end
	local host = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if not host then return nil end
	local spot = host:FindFirstChild("Flashlight")
	if not spot then
		spot = Instance.new("SpotLight")
		spot.Name = "Flashlight"
		spot.Range = Config.Flashlight.Range
		spot.Angle = Config.Flashlight.Angle
		spot.Brightness = Config.Flashlight.Brightness
		spot.Face = Enum.NormalId.Front
		spot.Shadows = true
		spot.Color = Color3.fromRGB(255, 244, 220)
		spot.Enabled = false
		spot.Parent = host
	end
	return spot :: SpotLight
end

local function applyBody(sess: Session, speed: number, lightOn: boolean)
	local _, hum = character(sess)
	if hum and hum.WalkSpeed ~= speed then
		hum.WalkSpeed = speed
	end
	local spot = flashlightOf(sess)
	if spot and spot.Enabled ~= lightOn then
		spot.Enabled = lightOn
	end
end

--============================================================================ the floor

local ROOM_WALL = Color3.fromRGB(150, 158, 150)
local ROOM_FLOOR = Color3.fromRGB(88, 92, 90)
local FIXTURE_LIT = Color3.fromRGB(255, 246, 222)
local FIXTURE_DARK = Color3.fromRGB(26, 26, 28)
local FUSE_COLOR = Color3.fromRGB(255, 176, 60)
local CELL_COLOR = Color3.fromRGB(90, 230, 120)

local function worldOf(sess: Session, lx: number, y: number, lz: number): Vector3
	return zoneOrigin(sess.zoneIndex) + Vector3.new(lx, y, lz)
end

local function doorKey(a: number, b: number): string
	return math.min(a, b) .. "_" .. math.max(a, b)
end

local function writeDebug(sess: Session)
	local run = sess.run
	if not run then return end
	local d = sess.debug
	if not d then
		d = folder("Run_" .. sess.plr.UserId, debugRoot)
		sess.debug = d
	end
	local plan = run.plan
	local function list(rooms)
		local parts = {}
		for _, r in rooms do table.insert(parts, tostring(r)) end
		return table.concat(parts, ",")
	end
	d:SetAttribute("Sublevel", run.k)
	d:SetAttribute("LayoutSeed", run.seeds.layout)
	d:SetAttribute("LootSeed", run.seeds.loot)
	d:SetAttribute("DecorSeed", run.seeds.decor)
	d:SetAttribute("EntryCell", plan.entry)
	d:SetAttribute("ExitCell", plan.exit)
	d:SetAttribute("FuseCells", list(plan.fuseRooms))
	d:SetAttribute("BatteryCells", list(plan.cellRooms))
	d:SetAttribute("StepSeconds", run.step)
	d:SetAttribute("HoldSeconds", if run.hold == nil then -1 else run.hold)
	d:SetAttribute("ModelSeconds", run.modelT)
	d:SetAttribute("ZoneIndex", sess.zoneIndex)
	d:SetAttribute("Grid", plan.n)
	d:SetAttribute("TrustedCell", run.trust and run.trust.cell or plan.entry)
	d:SetAttribute("RunClock", run.clock)
end

local function deathAt(run, room: number): number
	-- a powered elevator room never goes dark; an unpowered one does, last (REVIEW-1 B3)
	return Facility.deathTime(Config, run.plan, run.step, room, run.hold, run.powered)
end

-- "lit" | "low" | "high" | "dark" for a room at the run clock.
local function lightState(run, room: number): string
	local death = deathAt(run, room)
	if run.clock >= death then
		return "dark"
	end
	local start = death - Config.Front.FlickerSeconds
	if run.clock >= start then
		local idx = math.floor((run.clock - start) / Config.Front.FlickerToggleSeconds + 1e-6)
		return if idx % 2 == 0 then "low" else "high"
	end
	return "lit"
end

local function applyLight(run, room: number)
	local rec = run.lights[room]
	if not rec then return end
	local s = lightState(run, room)
	if rec.state == s then return end
	rec.state = s
	if s == "dark" then
		rec.light.Enabled = false
		rec.fixture.Material = Enum.Material.SmoothPlastic
		rec.fixture.Color = FIXTURE_DARK
	else
		rec.light.Enabled = true
		rec.light.Brightness = if s == "low" then F.FlickerLowBrightness else F.RoomLightBrightness
		rec.fixture.Material = if s == "low" then Enum.Material.SmoothPlastic else Enum.Material.Neon
		rec.fixture.Color = if s == "low" then FIXTURE_DARK else FIXTURE_LIT
	end
end

local function buildLeaf(sess: Session, a: number, b: number)
	local run = sess.run
	local k = doorKey(a, b)
	if run.leaves[k] then return end
	local spec = Facility.doorLeaf(Config, run.plan.n, a, b)
	run.leaves[k] = part({
		Name = spec.name,
		Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3]),
		CFrame = CFrame.new(worldOf(sess, spec.pos[1], spec.pos[2], spec.pos[3])),
		Material = Enum.Material.DiamondPlate,
		Color = Color3.fromRGB(96, 100, 104),
		Parent = run.floorParts.doors,
	})
end

local function buildEntryCar(sess: Session, c: Vector3)
	local car = folder("EntryCar", sess.run.floorParts.root)
	local metal = Color3.fromRGB(110, 114, 120)
	part({ Name = "CarFloor", Size = Vector3.new(10, 0.3, 10), CFrame = CFrame.new(c + Vector3.new(0, 0.15, 0)),
		Material = Enum.Material.DiamondPlate, Color = metal, Parent = car })
	for i, o in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		part({ Name = "CarPost" .. i, Size = Vector3.new(0.6, 10, 0.6), CFrame = CFrame.new(c + Vector3.new(4.7 * o[1], 5, 4.7 * o[2])),
			Material = Enum.Material.Metal, Color = metal, Parent = car })
	end
	part({ Name = "CarRoof", Size = Vector3.new(10, 0.4, 10), CFrame = CFrame.new(c + Vector3.new(0, 10.2, 0)),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(70, 72, 78), Parent = car })
end

local function buildExitLift(sess: Session, c: Vector3)
	local run = sess.run
	local lift = folder("ExitLift", run.floorParts.root)
	local metal = Color3.fromRGB(150, 110, 50)
	part({ Name = "LiftPlatform", Size = Vector3.new(10, 0.3, 10), CFrame = CFrame.new(c + Vector3.new(0, 0.15, 0)),
		Material = Enum.Material.DiamondPlate, Color = metal, Parent = lift })
	for i, o in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		part({ Name = "LiftPost" .. i, Size = Vector3.new(0.8, 10, 0.8), CFrame = CFrame.new(c + Vector3.new(4.6 * o[1], 5, 4.6 * o[2])),
			Material = Enum.Material.Metal, Color = metal, Parent = lift })
	end
	part({ Name = "LiftRoof", Size = Vector3.new(10, 0.4, 10), CFrame = CFrame.new(c + Vector3.new(0, 10.2, 0)),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(80, 60, 30), Parent = lift })
	local panel = part({ Name = "FusePanel", Size = Vector3.new(3.6, 3, 0.4), CFrame = CFrame.new(c + Vector3.new(0, 4, -4.4)),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(30, 30, 34), Parent = lift })
	local beacon = part({ Name = "Beacon", Size = Vector3.new(1.2, 0.6, 1.2), CFrame = CFrame.new(c + Vector3.new(0, 10.7, 0)),
		Material = Enum.Material.Neon, Color = rgb(Config.Hud.Danger), CanCollide = false, Parent = lift })
	Fx.attachGlow(beacon, rgb(Config.Hud.Danger), 2, 18)

	-- The lift is open on all four sides and the panel stands on its -Z edge, so a player sees it
	-- from inside the lift (Back, +Z, where they stand to choose) or from outside (Front, -Z),
	-- depending on the doorway they came in by. A SurfaceGui draws on one face: one per face.
	local faces = {}
	local n = run.plan.fuses
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Slots" .. face.Name
		gui.Face = face
		gui.CanvasSize = Vector2.new(360, 300)
		gui.LightInfluence = 0
		gui.Parent = panel
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0.4, 0)
		title.BackgroundTransparency = 1
		title.TextScaled = true
		title.Font = Enum.Font.GothamBlack
		title.TextColor3 = rgb(Config.Hud.Accent)
		title.Text = "FUSES 0/" .. n
		title.Parent = gui
		local slots = {}
		for i = 1, n do
			local s = Instance.new("Frame")
			s.Name = "Slot" .. i
			s.Size = UDim2.new(0.8 / n, -6, 0.4, 0)
			s.Position = UDim2.new(0.1 + (i - 1) * 0.8 / n, 3, 0.5, 0)
			s.BackgroundColor3 = rgb(Config.Hud.Danger)
			s.BorderSizePixel = 0
			s.Parent = gui
			slots[i] = s
		end
		table.insert(faces, { title = title, slots = slots })
	end
	run.exitPanel = { faces = faces, beacon = beacon }
end

local function refreshPanel(run)
	local p = run.exitPanel
	if not p then return end
	for _, face in p.faces do
		face.title.Text = "FUSES " .. run.fusesIn .. "/" .. run.plan.fuses
		for i, s in face.slots do
			s.BackgroundColor3 = if i <= run.fusesIn then rgb(Config.Hud.Good) else rgb(Config.Hud.Danger)
		end
	end
	if run.powered then
		p.beacon.Color = rgb(Config.Hud.Good)
		local glow = p.beacon:FindFirstChild("FxGlow")
		if glow then (glow :: PointLight).Color = rgb(Config.Hud.Good) end
	end
end

-- §4.7: a room exists only once a door into it opens (or it is the entry).
local function buildRoom(sess: Session, room: number)
	local run = sess.run
	if run.built[room] then return end
	local plan = run.plan
	local roomFolder = folder("Room_" .. room, run.floorParts.rooms)
	run.built[room] = roomFolder
	local cx, cz = Facility.cellCenter(Config, plan.n, room)
	local c = worldOf(sess, cx, 0, cz)
	local fixture
	for _, s in Facility.roomParts(Config, plan, room) do
		local size = Vector3.new(s.size[1], s.size[2], s.size[3])
		local cf = CFrame.new(c + Vector3.new(s.pos[1], s.pos[2], s.pos[3]))
		if s.role == "dust" then
			Fx.dustVolume(roomFolder, size, cf, Color3.fromRGB(200, 205, 215), 4)
		elseif s.role == "floor" then
			part({ Name = s.name, Size = size, CFrame = cf, Material = Enum.Material.Concrete, Color = ROOM_FLOOR, Parent = roomFolder })
		elseif s.role == "ceiling" then
			part({ Name = s.name, Size = size, CFrame = cf, Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(46, 48, 50), Parent = roomFolder })
		elseif s.role == "wall" then
			part({ Name = s.name, Size = size, CFrame = cf, Material = Enum.Material.SmoothPlastic, Color = ROOM_WALL, Parent = roomFolder })
		elseif s.role == "fixture" then
			fixture = part({ Name = s.name, Size = size, CFrame = cf, Material = Enum.Material.Neon, Color = FIXTURE_LIT, CanCollide = false, Parent = roomFolder })
			local light = Instance.new("PointLight")
			light.Name = "RoomLight"
			light.Enabled = true
			light.Range = F.RoomLightRange
			light.Brightness = F.RoomLightBrightness
			light.Color = Color3.fromRGB(255, 240, 215)
			light.Shadows = true
			light.Parent = fixture
			run.lights[room] = { light = light, fixture = fixture, state = "lit" }
		elseif s.role == "prop" then
			part({ Name = s.name, Size = size, CFrame = cf, Material = Enum.Material.Metal, Color = Color3.fromRGB(70, 76, 80), Parent = roomFolder })
		elseif s.role == "item" then
			local isFuse = s.name == "Fuse"
			local item = part({ Name = s.name, Size = size, CFrame = cf, Material = Enum.Material.Neon,
				Color = if isFuse then FUSE_COLOR else CELL_COLOR, CanCollide = false, Parent = roomFolder })
			Fx.attachGlow(item, if isFuse then FUSE_COLOR else CELL_COLOR, 1.5, 12)
			run.itemParts[room] = item
		end
	end
	if room == plan.entry then
		buildEntryCar(sess, c)
	end
	if room == plan.exit then
		buildExitLift(sess, c)
		refreshPanel(run)
	end
	for _, nb in plan.adj[room] do
		buildLeaf(sess, room, nb)
	end
	applyLight(run, room)
end

local function destroyFloor(sess: Session)
	if sess.floor then
		sess.floor:Destroy()
		sess.floor = nil
	end
end

local function openDoor(sess: Session, a: number, b: number)
	local run = sess.run
	local k = doorKey(a, b)
	if run.open[k] then return end
	run.open[k] = true
	buildRoom(sess, a)
	buildRoom(sess, b)
	local leaf = run.leaves[k]
	if leaf then
		leaf.CanCollide = false
		TweenService:Create(leaf, TweenInfo.new(F.DoorOpenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = leaf.CFrame + Vector3.new(0, F.DoorHeight - 0.5, 0) }):Play()
	end
end

local function removeApparition(run)
	if run.apparition then
		run.apparition:Destroy()
		run.apparition = nil
	end
end

-- §2.6: a silent 6-Part figure in a dark room you already walked through, seen through the open
-- doorway, on the far wall. Presentation only; it changes no rule.
local function spawnApparition(sess: Session, playerRoom: number, darkRoom: number)
	local run = sess.run
	run.apparitionShown = true
	-- Where it stands and what it is made of come from Facility.apparition, the one description
	-- tests/Facility.spec.luau checks against the room's props (REVIEW-1 B4).
	local spec = Facility.apparition(Config, run.plan, darkRoom, playerRoom)
	local base = worldOf(sess, spec.x, 0, spec.z)
	local look = CFrame.lookAt(base, base + Vector3.new(spec.dx, 0, spec.dz))
	local model = Instance.new("Model")
	model.Name = "Apparition"
	local black = Color3.fromRGB(4, 4, 5)
	for _, limb in spec.limbs do
		part({ Name = limb.name, Size = Vector3.new(limb.size[1], limb.size[2], limb.size[3]),
			CFrame = look * CFrame.new(limb.offset[1], limb.offset[2], limb.offset[3]), Color = black,
			Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false, CanTouch = false,
			CastShadow = false, Parent = model })
	end
	model.Parent = run.floorParts.root
	run.apparition = model
	run.apparitionLeft = Config.Apparition.LifetimeSeconds
end

--============================================================================ state push

local function perkRows(prof)
	local rows = {}
	for _, id in Config.Perks.Order do
		local p = Config.Perks.Catalog[id]
		local rank = prof.perks[id] or 0
		table.insert(rows, { id = id, name = p.name, blurb = p.blurb, rank = rank, max = p.max,
			price = Economy.price(Config, id, rank) })
	end
	return rows
end

local function pushState(sess: Session)
	local prof = sess.profile
	local perks = {}
	for _, id in Config.Perks.Order do perks[id] = prof.perks[id] or 0 end
	local payload: any = {
		phase = sess.phase,
		loaded = sess.loaded,
		saving = profileStore ~= nil and sess.canSave,
		storeless = profileStore == nil,
		essence = prof.essence,
		bestSublevel = prof.bestSublevel,
		runs = prof.runs,
		perks = perks,
		perkRows = perkRows(prof),
		boarding = if sess.phase == "hub" and sess.boardT > 0 then math.clamp(sess.boardT / Config.Run.BoardingSeconds, 0, 1) else 0,
	}
	local run = sess.run
	if run then
		local s = run.surv
		local cell = run.trust and run.trust.cell or run.plan.entry
		local ls = if sess.phase == "floor" then lightState(run, cell) else "lit"
		payload.run = {
			k = run.k,
			fuses = run.fusesHeld,
			fusesIn = run.fusesIn,
			fusesNeeded = run.plan.fuses,
			battery = s.battery,
			batteryCap = s.batteryCap,
			exposure = Survival.exposureFraction(s),
			stamina = s.stamina,
			staminaCap = s.staminaCap,
			lightOn = s.lightOn,
			sprinting = s.sprinting,
			runEssence = sess.profile.openRun and sess.profile.openRun.runEssence or 0,
			keepPercent = run.effects.keepPercent,
			dark = ls == "dark",
			flicker = ls == "low" or ls == "high",
			powered = run.powered,
			-- standing in the powered lift: the only place the choice is accepted, so the only place
			-- the HUD shows it (REVIEW-1 B2). False until powered, and powering happens only in the
			-- lift, so it never says where an unpowered exit is.
			atLift = sess.phase == "floor" and run.powered and cell == run.plan.exit,
			secondWinds = s.secondWinds,
		}
	end
	StateRemote:FireClient(sess.plr, payload)
end

--============================================================================ runs

-- §2.5: every way a run ends comes through here. Idempotent: a second call pays nothing.
local function endRun(sess: Session, reason: string): number
	local run = sess.run
	if not run then
		return 0
	end
	local runEssence = sess.profile.openRun and sess.profile.openRun.runEssence or 0
	local payout = Economy.settle(sess.profile, reason)
	sess.run = nil
	applyBody(sess, Config.Movement.WalkSpeed, false)
	if reason ~= "left" and reason ~= "shutdown" then
		task.spawn(saveProfile, sess)
		notice(sess.plr, "runEnd", { reason = reason, payout = payout, of = runEssence })
	end
	return payout
end

local function goHub(sess: Session)
	destroyFloor(sess)
	sess.phase = "hub"
	sess.boardT = 0
	setCamera(sess, false)
	applyBody(sess, Config.Movement.WalkSpeed, false)
end

-- Build sublevel k's entry and put the player in the ride car for the way down.
local function beginSublevel(sess: Session, k: number)
	local run = sess.run
	destroyFloor(sess)
	local floorFolder = folder("Floor", sess.zone)
	sess.floor = floorFolder
	run.floorParts = {
		root = floorFolder,
		rooms = folder("Rooms", floorFolder),
		doors = folder("Doors", floorFolder),
	}
	run.k = k
	run.seeds = Facility.drawSeeds(Random.new())
	run.plan = Facility.planForSublevel(Config, k, run.seeds, Rng, MazeGen)
	run.modelT = Facility.modelTime(Config, run.plan)
	run.step = Facility.front(Config, run.plan, k, run.modelT)
	run.hold = if run.firstRun and k == 1 then nil else 0
	run.clock = 0
	run.open = {}
	run.built = {}
	run.leaves = {}
	run.lights = {}
	run.itemParts = {}
	run.taken = {}
	run.fusesHeld = 0
	run.fusesIn = 0
	run.powered = false
	run.choosing = false
	run.apparitionShown = false
	run.apparition = nil
	run.exitPanel = nil
	run.trust = nil
	run.lastCell = nil
	run.toldDying = {}
	run.seenCell = nil
	run.seenState = nil
	run.cellFullTold = nil
	run.isOpen = function(a, b)
		return run.open[doorKey(a, b)] == true
	end
	buildRoom(sess, run.plan.entry)
	writeDebug(sess)

	sess.phase = "ride"
	sess.rideLeft = Config.Run.RideSeconds
	sess.rideTo = "floor"
	moveCharacter(sess, zoneOrigin(sess.zoneIndex) + Vector3.new(0, 3, RIDE_Z))
	setCamera(sess, true)
	applyBody(sess, Config.Movement.WalkSpeed, false)
	notice(sess.plr, "sublevel", { k = k, fuses = run.plan.fuses })
end

local function tryStartRun(sess: Session): boolean
	local plr = sess.plr
	if not sess.loaded then
		toast(plr, "Your file is still loading — one moment.")
		return false
	end
	if profileStore and not sess.canSave then
		toast(plr, if sess.loadFailed
			then "Couldn't reach the save server — retrying."
			else "Your file is open on another server — retrying.")
		return false
	end
	if sess.buying then
		-- A failed purchase flush restores the snapshot taken before it, and a run begun while it
		-- was saving would be wiped out of the profile with it: no checkpoint, no choice, no pay.
		toast(plr, "Still saving your purchase — one moment.")
		return false
	end
	if sess.profile.openRun ~= nil then
		toast(plr, "Your last run is still being settled — retrying.")
		return false
	end
	local char, hum = character(sess)
	if not char or char.Parent == nil or not hum or hum.Health <= 0 then
		toast(plr, "You need to be standing in the elevator to go down.")
		return false
	end
	local effects = Economy.effects(Config, sess.profile.perks)
	local id = newToken()
	sess.run = {
		id = id,
		effects = effects,
		firstRun = sess.profile.runs == 0,
		surv = Survival.new(Config, effects),
		speed = Config.Movement.WalkSpeed,
	}
	Economy.beginRun(sess.profile, id, effects.keepPercent)
	beginSublevel(sess, 1)
	return true
end

local function arrive(sess: Session)
	local run = sess.run
	local plan = run.plan
	local cx, cz = Facility.cellCenter(Config, plan.n, plan.entry)
	if not moveCharacter(sess, worldOf(sess, cx, 3, cz)) then
		-- not alive in the world: the reset path owns this, and it settles the run
		endRun(sess, "reset")
		goHub(sess)
		return
	end
	run.trust = Trust.new(Config, plan.n, plan.entry, cx, cz)
	run.lastCell = plan.entry
	Survival.arrive(run.surv)
	-- The REQUESTS are cleared too, not only the state: otherwise a light left on at the last exit
	-- comes straight back on next tick and drains the battery in a lit entry room, and a SPRINT
	-- tapped on at the exit burns the stamina there.
	sess.wantLight = false
	sess.wantSprint = false
	sess.sprintPress = false
	run.clock = 0
	sess.phase = "floor"
	writeDebug(sess)
	notice(sess.plr, "arrive", { k = run.k, fuses = plan.fuses, held = run.hold == nil })
	if run.hold ~= nil then
		notice(sess.plr, "powerFailing")
	end
end

local function power(sess: Session)
	local run = sess.run
	run.powered = true
	local pay = Economy.power(Config, sess.profile, run.k)
	setDeepest(sess)
	refreshPanel(run)
	task.spawn(saveProfile, sess) -- the checkpoint (§7.1)
	notice(sess.plr, "choice", {
		k = run.k,
		pay = pay,
		bank = sess.profile.openRun.runEssence,
		nextPay = Economy.floorPay(Config, run.k + 1),
		keepPercent = run.effects.keepPercent,
	})
end

local function die(sess: Session)
	local of = sess.profile.openRun and sess.profile.openRun.runEssence or 0
	local kept = endRun(sess, "dark")
	sess.phase = "dying"
	sess.beatLeft = Config.Run.DeathBeatSeconds
	notice(sess.plr, "death", { kept = kept, of = of })
end

--============================================================================ the tick

local function tickHub(sess: Session, dt: number)
	if sess.boardCooldown > 0 then
		sess.boardCooldown -= dt
	end
	local _, _, hrp = character(sess)
	local inside = hrp ~= nil and inHubCar((hrp :: BasePart).Position)
	if inside and sess.boardCooldown <= 0 then
		if sess.boardT == 0 then
			notice(sess.plr, "boarding")
		end
		sess.boardT += dt
		if sess.boardT >= Config.Run.BoardingSeconds - 1e-6 then
			sess.boardT = 0
			if not tryStartRun(sess) then
				sess.boardCooldown = 5
			end
		end
	elseif not inside and sess.boardT > 0 then
		sess.boardT = 0
		toast(sess.plr, "Boarding cancelled — stay in the elevator to go down.")
	end
end

local function tickFloor(sess: Session, dt: number)
	local run = sess.run
	local plan = run.plan
	local plr = sess.plr
	run.clock += dt

	-- 1. trusted position (§9)
	local _, _, hrp = character(sess)
	if hrp then
		local o = zoneOrigin(sess.zoneIndex)
		local p = (hrp :: BasePart).Position
		Trust.step(Config, run.trust, p.X - o.X, p.Z - o.Z, dt, run.speed, run.isOpen)
	end
	local t = run.trust
	local cell = t.cell

	-- 2. doors open by themselves on a trusted approach
	for _, nb in Facility.doorsNear(Config, plan, cell, t.x, t.z, run.isOpen) do
		openDoor(sess, cell, nb)
	end

	-- 3. entering a room
	if cell ~= run.lastCell then
		run.lastCell = cell
		if cell == plan.exit and not run.powered and run.fusesHeld + run.fusesIn < plan.fuses then
			local missing = plan.fuses - run.fusesHeld - run.fusesIn
			toast(plr, string.format("The freight elevator needs %d more fuse%s.", missing, if missing == 1 then "" else "s"))
		end
	end

	-- 4. pickups
	local item = plan.items[cell]
	if item and not run.taken[cell] then
		local cx, cz = Facility.cellCenter(Config, plan.n, cell)
		local dx, dz = t.x - (cx + item.x), t.z - (cz + item.z)
		local inReach = dx * dx + dz * dz <= F.PickupRadius * F.PickupRadius
		if inReach and item.kind == "fuse" then
			run.taken[cell] = true
			local p = run.itemParts[cell]
			if p then p:Destroy() end
			run.fusesHeld += 1
			notice(plr, "fuse", { held = run.fusesHeld, fusesIn = run.fusesIn, needed = plan.fuses })
			if run.hold == nil then
				run.hold = run.clock -- §2.2: the first-ever run's front starts at the first fuse
				writeDebug(sess)
				notice(plr, "powerFailing")
			end
		elseif inReach and item.kind == "cell" then
			if Survival.pickupCell(Config, run.surv) then
				run.taken[cell] = true
				local p = run.itemParts[cell]
				if p then p:Destroy() end
				run.cellFullTold = nil
				notice(plr, "cell", { battery = run.surv.battery })
			elseif run.cellFullTold ~= cell then
				run.cellFullTold = cell
				toast(plr, "Battery full — the cell stays here for later.")
			end
		elseif not inReach and run.cellFullTold == cell then
			run.cellFullTold = nil
		end
	end

	-- 5. the exit: fuses go in by themselves
	if cell == plan.exit and not run.powered then
		if run.fusesHeld > 0 then
			run.fusesIn += run.fusesHeld
			run.fusesHeld = 0
			refreshPanel(run)
			notice(plr, "inserted", { fusesIn = run.fusesIn, needed = plan.fuses })
			if run.fusesIn < plan.fuses then
				local missing = plan.fuses - run.fusesIn
				toast(plr, string.format("The freight elevator needs %d more fuse%s.", missing, if missing == 1 then "" else "s"))
			end
		end
		if run.fusesIn >= plan.fuses then
			power(sess)
		end
	end

	-- 6. the front's visuals
	for room in run.built do
		applyLight(run, room)
	end
	local myState = lightState(run, cell)
	if (myState == "low" or myState == "high") and not run.toldDying[cell] then
		run.toldDying[cell] = true
		notice(plr, "roomDying")
	end
	-- §11.4: the room dying AROUND the player (the same room, lit last tick), not walking into one
	-- that was already dark. The client shakes the camera on it.
	if myState == "dark" and run.seenCell == cell and run.seenState ~= "dark" then
		notice(plr, "roomDied")
	end
	run.seenCell, run.seenState = cell, myState

	-- 7. survival
	local events = Survival.step(Config, run.surv, {
		wantLight = sess.wantLight,
		wantSprint = sess.wantSprint,
		sprintPressed = sess.sprintPress,
		dark = myState == "dark",
	}, dt)
	sess.sprintPress = false
	for _, e in events do
		if e == "dead" then
			die(sess)
			return
		elseif e == "batteryEmpty" then
			notice(plr, "batteryEmpty")
		elseif e == "secondWind" then
			notice(plr, "secondWind")
		end
	end
	run.speed = if run.surv.sprinting then Config.Movement.SprintSpeed else Config.Movement.WalkSpeed
	applyBody(sess, run.speed, run.surv.lightOn)

	-- 8. the apparition, at most once per sublevel
	if run.apparition then
		run.apparitionLeft -= dt
		if run.apparitionLeft <= 0 then
			removeApparition(run)
		end
	elseif not run.apparitionShown and myState ~= "dark" then
		for _, c in plan.adj[cell] do
			if c ~= plan.exit and run.built[c] and run.isOpen(cell, c) and lightState(run, c) == "dark" then
				spawnApparition(sess, cell, c)
				break
			end
		end
	end

	if sess.debug then
		sess.debug:SetAttribute("TrustedCell", cell)
		sess.debug:SetAttribute("RunClock", run.clock)
	end
end

local function tickSession(sess: Session, dt: number)
	if sess.phase == "hub" then
		tickHub(sess, dt)
	elseif sess.phase == "ride" then
		sess.rideLeft -= dt
		if sess.rideLeft <= 1e-6 then
			if sess.rideTo == "floor" and sess.run then
				arrive(sess)
			else
				moveCharacter(sess, hubArrival.Position + Vector3.new(0, 3, 0))
				goHub(sess)
			end
		end
	elseif sess.phase == "floor" and sess.run then
		tickFloor(sess, dt)
	elseif sess.phase == "dying" then
		sess.beatLeft -= dt
		if sess.beatLeft <= 1e-6 then
			moveCharacter(sess, hubArrival.Position + Vector3.new(0, 3, 0))
			goHub(sess)
		end
	end

	sess.pushLeft -= dt
	if sess.pushLeft <= 1e-6 then
		sess.pushLeft = Config.Run.StatePushSeconds
		pushState(sess)
	end
end

task.spawn(function()
	while true do
		local dt = task.wait(TICK)
		for _, sess in sessions do
			local ok, err = pcall(tickSession, sess, dt)
			if not ok then
				warn("[Facility] tick failed for " .. sess.plr.Name .. ": " .. tostring(err))
			end
		end
	end
end)

--============================================================================ client requests

FlashlightRemote.OnServerEvent:Connect(function(plr, on)
	local sess = sessions[plr]
	if not sess then return end
	if type(on) ~= "boolean" then
		toast(plr, "That flashlight request made no sense.")
		return
	end
	if not sess.run or sess.phase ~= "floor" then
		toast(plr, "Your flashlight only works down in the facility.")
		return
	end
	if on and sess.run.surv.battery <= 0 then
		toast(plr, "Your battery is empty — find a cell.")
	end
	sess.wantLight = on -- applied by the next tick; only the latest request counts
end)

SprintRemote.OnServerEvent:Connect(function(plr, on)
	local sess = sessions[plr]
	if not sess then return end
	if type(on) ~= "boolean" then
		toast(plr, "That sprint request made no sense.")
		return
	end
	if on and (not sess.run or sess.phase ~= "floor") then
		-- releasing Shift in the break room is not a request worth answering; pressing it is
		toast(plr, "Sprint works down in the facility.")
	end
	if on then
		sess.sprintPress = true
	end
	sess.wantSprint = on
end)

ChooseRemote.OnServerEvent:Connect(function(plr, choice)
	local sess = sessions[plr]
	if not sess then return end
	if choice ~= "extract" and choice ~= "descend" then
		toast(plr, "Choose EXTRACT or DESCEND.")
		return
	end
	local run = sess.run
	if not run or sess.phase ~= "floor" or not run.powered then
		toast(plr, "Power the freight elevator first.")
		return
	end
	if run.trust.cell ~= run.plan.exit then
		toast(plr, "Stand at the freight elevator to choose.")
		return
	end
	if run.choosing then
		toast(plr, "Already on your way.")
		return
	end
	run.choosing = true
	if choice == "extract" then
		local banked = endRun(sess, "extract")
		notice(plr, "extracted", { banked = banked })
		sess.phase = "ride"
		sess.rideLeft = Config.Run.RideSeconds
		sess.rideTo = "hub"
		removeApparition(run)
		moveCharacter(sess, zoneOrigin(sess.zoneIndex) + Vector3.new(0, 3, RIDE_Z))
		destroyFloor(sess)
	else
		removeApparition(run)
		beginSublevel(sess, run.k + 1)
	end
	pushState(sess)
end)

BuyPerkRemote.OnServerEvent:Connect(function(plr, perkId)
	local sess = sessions[plr]
	if not sess then return end
	if type(perkId) ~= "string" or Config.Perks.Catalog[perkId] == nil then
		toast(plr, "That perk does not exist.")
		return
	end
	if not sess.loaded then
		toast(plr, "Your file is still loading — one moment.")
		return
	end
	if not profileStore then
		toast(plr, "Progress can't be saved on this server, so perks can't be bought.")
		return
	end
	if not sess.canSave then
		toast(plr, "Your file is open on another server — nothing can be bought right now.")
		return
	end
	if sess.run or sess.phase ~= "hub" then
		toast(plr, "Perks are bought in the break room, between runs.")
		return
	end
	if sess.buying then
		toast(plr, "Still saving your last purchase…")
		return
	end
	local ok, why = Economy.canBuy(Config, sess.profile, perkId)
	if not ok then
		toast(plr, why or "You can't buy that.")
		return
	end
	sess.buying = true
	local snap = Economy.snapshot(sess.profile)
	local price = Economy.buy(Config, sess.profile, perkId)
	local persisted = saveProfile(sess)
	sess.buying = false
	if sessions[plr] ~= sess then
		return
	end
	if not persisted then
		Economy.restore(sess.profile, snap)
		toast(plr, "Couldn't reach the save server — nothing was spent.")
	else
		local p = Config.Perks.Catalog[perkId]
		notice(plr, "purchased", { id = perkId, name = p.name, rank = sess.profile.perks[perkId], price = price })
	end
	pushState(sess)
end)

--============================================================================ join / leave

local function onCharacter(sess: Session, char: Model)
	-- NO CFrame write and NO yield here (SPAWN-ORDER.md): RespawnLocation already put us on HubSpawn.
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = Config.Movement.WalkSpeed
		hum.Died:Connect(function()
			if sessions[sess.plr] ~= sess or sess.plr.Character ~= char then
				return
			end
			if sess.run then
				endRun(sess, "reset")
			end
			if sess.phase ~= "hub" then
				goHub(sess)
			end
		end)
	end
	setCamera(sess, false)
	if sess.run then
		endRun(sess, "reset") -- idempotent: Died has usually settled it already
	end
	if sess.phase ~= "hub" then
		goHub(sess)
	end
end

local function onPlayerAdded(plr: Player)
	if sessions[plr] then return end
	plr.RespawnLocation = hubSpawn
	-- REVIEW-1 B1: coming back from LockFirstPerson, Roblox's camera re-clamps the old 0.5-stud
	-- distance to this minimum. At the default 0.5 it stayed in first person with the cursor locked
	-- to the centre, back in the break room. LockFirstPerson itself ignores the minimum.
	pcall(function()
		plr.CameraMinZoomDistance = Config.Hub.CameraMinZoomDistance
	end)

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local deepest = Instance.new("IntValue")
	deepest.Name = "Deepest"
	deepest.Value = 0
	deepest.Parent = ls
	ls.Parent = plr

	local index = acquireZone()
	local zone = folder("Zone_" .. index, facilityFolder)
	buildRideCar(zone, zoneOrigin(index))

	local sess: Session = {
		plr = plr,
		profile = Economy.newProfile(Config),
		loaded = false,
		canSave = false,
		token = newToken(),
		closing = false,
		buying = false,
		loadFailed = false,
		zoneIndex = index,
		zone = zone,
		floor = nil,
		phase = "hub",
		boardT = 0,
		boardCooldown = 0,
		rideLeft = 0,
		rideTo = "floor",
		beatLeft = 0,
		pushLeft = 0,
		autosaveLeft = Config.Data.AutosaveSeconds,
		run = nil,
		wantLight = false,
		wantSprint = false,
		sprintPress = false,
		debug = nil,
	}
	sessions[plr] = sess

	plr.CharacterAdded:Connect(function(char)
		if sessions[plr] == sess then
			onCharacter(sess, char)
		end
	end)
	if plr.Character then
		onCharacter(sess, plr.Character)
	end

	-- ------------------------------------------------ and NOW the network call (it may yield)
	if not profileStore then
		sess.loaded = true
		pushState(sess)
		notice(plr, "toast", "Saving is unavailable on this server — you can play, but progress will not be kept.")
	else
		local function attempt()
			local got, data, failed = claimProfile(sess)
			if sessions[plr] ~= sess or plr.Parent == nil then
				-- The player left while the claim was in flight: onPlayerRemoving could not release a
				-- lock it did not know it held (canSave was still false), so give it back here.
				if got then
					releaseLock(sess)
				end
				return
			end
			sess.loadFailed = failed
			if got then
				sess.profile = Economy.sanitize(Config, data)
				sess.canSave = true
				if sess.profile.openRun ~= nil then
					-- the server died mid-run last time: settle the checkpoint as a death, once
					local payout = Economy.settle(sess.profile, "load")
					saveProfile(sess)
					notice(plr, "toast", string.format("Your last run ended when the server did — you kept %d Essence.", payout))
				end
			elseif not sess.loaded then
				-- another server holds the file: show its data read-only, and retry on autosave
				sess.profile = Economy.sanitize(Config, data)
				sess.profile.openRun = nil
				notice(plr, "toast", if failed
					then "Couldn't reach the save server — retrying."
					else "Your file is open on another server — retrying.")
			end
			sess.loaded = true
			setDeepest(sess)
		end
		attempt()
		if sessions[plr] ~= sess then return end
		pushState(sess)

		task.spawn(function()
			while sessions[plr] == sess do
				task.wait(Config.Data.AutosaveSeconds)
				if sessions[plr] ~= sess or sess.closing then break end
				if sess.canSave then
					if not sess.buying then
						saveProfile(sess)
					end
				elseif not sess.run then
					attempt()
				end
			end
		end)
	end
end

local function onPlayerRemoving(plr: Player)
	local sess = sessions[plr]
	if not sess then return end
	sess.closing = true
	endRun(sess, "left")
	saveProfile(sess, true)
	sessions[plr] = nil
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
	for _, sess in sessions do
		sess.closing = true
		endRun(sess, "shutdown")
		saveProfile(sess, true)
	end
end)
