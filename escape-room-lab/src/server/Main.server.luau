-- ESCAPE ROOM LAB — the authoritative server (ServerScriptService).
--
-- What lives here, and why it is safe (DESIGN.md §12-14):
--   * every answer (door code, hidden line text, shelf order, lamp press set) is a Lua value in THIS
--     script's memory. It is never an Instance, an attribute or a value under Workspace,
--     ReplicatedStorage or a player; RoomView builds the only payload that leaves, from an allowlist;
--   * there is NO seed: each room draws from a fresh Random.new() (engine entropy), so no client can
--     regenerate a room from public numbers (fork-tower REVIEW-4's two traps are both absent);
--   * no remote takes a star, a result, a time, a position or a room. Stars come only from this
--     script's verdicts. Act validates exact types, the station is in the player's own room, reach by
--     the server's own view of the root, a rate limit, and the station's state;
--   * spawn follows robloxemu/SPAWN-ORDER.md's preferred pattern: AtriumSpawn is the ONE enabled
--     SpawnLocation, built before PlayerAdded is connected, and PlayerAdded points RespawnLocation at it
--     before anything else. CharacterAdded writes no CFrame and never yields;
--   * saving: pcall everything, a per-session token on every write, canSave only while we hold the
--     lock, the board written only after the profile write carrying the new total has landed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local CodeLock = require(ReplicatedStorage:WaitForChild("CodeLock"))
local Shelf = require(ReplicatedStorage:WaitForChild("Shelf"))
local Lamps = require(ReplicatedStorage:WaitForChild("Lamps"))
local Lab = require(ReplicatedStorage:WaitForChild("Lab"))
local Profile = require(ReplicatedStorage:WaitForChild("Profile"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local Text = require(ReplicatedStorage:WaitForChild("Text"))
local RoomView = require(ReplicatedStorage:WaitForChild("RoomView"))

-- First thing: the Lab's lighting. Equal to band 1, so the client's bands take over with no jump.
Fx.applyLighting(Fx.Presets.Lab)
RoomView.setText(Text)

local W = Config.World
local BANDS = Config.Env.Bands

Players.RespawnTime = W.RespawnTime
Players.CharacterAutoLoads = true

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function now(): number
	return tick() -- a monotonic clock for lockouts and cooldowns (virtual in the emulator)
end

--============================================================================ building helpers

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?,
	collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = collide ~= false
	p.Parent = parent
	return p
end

local function decorPart(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function surface(host: BasePart, face: Enum.NormalId, name: string?): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Name = name or "Face"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Parent = host
	return g
end

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3?,
	font: Enum.Font?, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Text = text
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color or Color3.fromRGB(245, 245, 245)
	l.Font = font or Enum.Font.GothamBold
	if align then l.TextXAlignment = align end
	l.Parent = parent
	return l
end

local function prompt(host: BasePart, name: string, action: string, object: string, distance: number): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = object
	pp.MaxActivationDistance = distance
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.Parent = host
	return pp
end

--============================================================================ remotes

local remotes = Instance.new("Folder")
remotes.Name = "LabRemotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local Act = remote("Act")
local RoomStateEv = remote("RoomState")
local HintEv = remote("Hint")
local Notice = remote("Notice")
local ProfileEv = remote("Profile")
local BoardEv = remote("Board")
local OpenEv = remote("Open")
-- C -> S, no payload: "I have loaded, send me my state again". Roblox queues events fired before a client
-- connects its handlers, but a HUD that reloads, or loads after the first Profile went out, must not
-- start blank. It carries nothing and credits nothing; a small bucket bounds it.
local Hello = remote("Hello")
remotes.Parent = ReplicatedStorage

local function toast(plr: Player, text: string, kind: string?)
	Notice:FireClient(plr, { kind = kind or "toast", text = text })
end

--============================================================================ the Atrium, the Roof

local world = {}

local function buildAtrium()
	local f = Instance.new("Folder")
	f.Name = "Atrium"
	local hx, hz, ht = W.AtriumHalfX, W.AtriumHalfZ, W.AtriumHeight
	local marble = Color3.fromRGB(226, 222, 212)
	local wallC = Color3.fromRGB(236, 226, 204)
	part(f, "Floor", Vector3.new(2 * hx + 2, 1, 2 * hz + 2), CFrame.new(0, -0.5, 0), marble, Enum.Material.Marble)
	part(f, "Ceiling", Vector3.new(2 * hx + 2, 1, 2 * hz + 2), CFrame.new(0, ht + 0.5, 0), wallC)
	part(f, "WallN", Vector3.new(2 * hx + 2, ht, 1), CFrame.new(0, ht / 2, -hz - 0.5), wallC)
	part(f, "WallS", Vector3.new(2 * hx + 2, ht, 1), CFrame.new(0, ht / 2, hz + 0.5), wallC)
	part(f, "WallW", Vector3.new(1, ht, 2 * hz + 2), CFrame.new(-hx - 0.5, ht / 2, 0), wallC)
	part(f, "WallE", Vector3.new(1, ht, 2 * hz + 2), CFrame.new(hx + 0.5, ht / 2, 0), wallC)

	-- the ONE enabled SpawnLocation in the world (SPAWN-ORDER.md §3, preferred pattern)
	local sp = Instance.new("SpawnLocation")
	sp.Name = "AtriumSpawn"
	sp.Anchored = true
	sp.Size = Vector3.new(W.SpawnSize[1], W.SpawnSize[2], W.SpawnSize[3])
	sp.CFrame = CFrame.new(W.Spawn[1], W.Spawn[2], W.Spawn[3])
	sp.Color = Color3.fromRGB(40, 120, 120)
	sp.Material = Enum.Material.SmoothPlastic
	sp.Enabled = true
	sp.Neutral = true
	sp.Duration = 0
	sp.Parent = f
	world.spawn = sp

	-- the Solo Lift: an 8 x 8 cab, doorway on +Z; standing inside for BoardSeconds starts the ride
	local sx, sz = W.SoloCab[1], W.SoloCab[2]
	local cabC = Color3.fromRGB(70, 80, 96)
	part(f, "SoloBack", Vector3.new(10, 10, 1), CFrame.new(sx, 5, sz - 4.5), cabC, Enum.Material.Metal)
	part(f, "SoloWallW", Vector3.new(1, 10, 8), CFrame.new(sx - 4.5, 5, sz), cabC, Enum.Material.Metal)
	part(f, "SoloWallE", Vector3.new(1, 10, 8), CFrame.new(sx + 4.5, 5, sz), cabC, Enum.Material.Metal)
	part(f, "SoloRoof", Vector3.new(10, 1, 10), CFrame.new(sx, 10.5, sz), cabC, Enum.Material.Metal)
	local soloFloor = decorPart(part(f, "SoloLiftFloor", Vector3.new(8, 0.1, 8), CFrame.new(sx, 0.05, sz),
		Color3.fromRGB(110, 230, 220), Enum.Material.Neon))
	soloFloor.Transparency = 0.4
	-- the doors are the RIDER's own, a local part Lab.client shuts for that player's ride (review-1 A2: one
	-- server door shut for every ride could be held shut by riders on a loop, keeping everyone else out)
	local soloSign = part(f, "SoloSign", Vector3.new(8, 1.6, 0.4), CFrame.new(sx, 11.8, sz + 4.2), Color3.fromRGB(30, 36, 48))
	label(surface(soloSign, Enum.NormalId.Back), "Text", "SOLO LIFT", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
		Color3.fromRGB(150, 255, 240))

	-- the Pair Lift: 12 x 8, two pads and a GO panel
	local px, pz = W.PairCab[1], W.PairCab[2]
	part(f, "PairBack", Vector3.new(14, 10, 1), CFrame.new(px, 5, pz - 4.5), cabC, Enum.Material.Metal)
	part(f, "PairWallW", Vector3.new(1, 10, 8), CFrame.new(px - 6.5, 5, pz), cabC, Enum.Material.Metal)
	part(f, "PairWallE", Vector3.new(1, 10, 8), CFrame.new(px + 6.5, 5, pz), cabC, Enum.Material.Metal)
	part(f, "PairRoof", Vector3.new(14, 1, 10), CFrame.new(px, 10.5, pz), cabC, Enum.Material.Metal)
	for i, dx in { -W.PairPadDX, W.PairPadDX } do
		decorPart(part(f, "PairPad" .. (if i == 1 then "A" else "B"), Vector3.new(4, 0.1, 4), CFrame.new(px + dx, 0.05, pz),
			Color3.fromRGB(255, 190, 90), Enum.Material.Neon))
	end
	local go = part(f, "PairGo", Vector3.new(3, 3, 0.5), CFrame.new(px, 4, pz - 3.75), Color3.fromRGB(40, 44, 60))
	label(surface(go, Enum.NormalId.Back), "Text", "GO", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(255, 200, 100))
	world.goPrompt = prompt(go, "GoPrompt", "GO", "PAIR LIFT", Config.Act.PromptDistance)
	local pairSign = part(f, "PairSign", Vector3.new(12, 1.6, 0.4), CFrame.new(px, 11.8, pz + 4.2), Color3.fromRGB(30, 36, 48))
	label(surface(pairSign, Enum.NormalId.Back), "Text", "PAIR LIFT", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
		Color3.fromRGB(255, 200, 100))

	-- the Star Board, facing the spawn (-X)
	local b = part(f, "StarBoard", Vector3.new(0.5, W.BoardSize[2], W.BoardSize[1]), CFrame.new(W.Board[1], W.Board[2], W.Board[3]),
		Color3.fromRGB(24, 28, 44))
	local bg = surface(b, Enum.NormalId.Left, "BoardFace")
	label(bg, "Title", "STAR BOARD", UDim2.fromScale(0.03, 0.02), UDim2.fromScale(0.94, 0.12), Color3.fromRGB(255, 214, 90), Enum.Font.GothamBlack)
	label(bg, "Mode", "PUBLIC  -  top 10", UDim2.fromScale(0.03, 0.14), UDim2.fromScale(0.94, 0.06), Color3.fromRGB(200, 210, 230))
	for i = 1, Config.Board.PublicRows do
		label(bg, "Row_" .. i, "", UDim2.fromScale(0.06, 0.21 + (i - 1) * 0.068), UDim2.fromScale(0.88, 0.062),
			Color3.fromRGB(240, 240, 245), Enum.Font.GothamBold, Enum.TextXAlignment.Left)
	end
	label(bg, "Note", "", UDim2.fromScale(0.05, 0.9), UDim2.fromScale(0.9, 0.08), Color3.fromRGB(190, 200, 220), Enum.Font.Gotham)
	world.board = b
	world.boardFace = bg
	world.boardPrompt = prompt(b, "BoardPrompt", "Friends / public", "STAR BOARD", Config.Board.PromptDistance)

	-- the Roof Access door on the north wall
	local rd = part(f, "RoofAccess", Vector3.new(6, 8, 0.4), CFrame.new(W.RoofDoor[1], 4, W.RoofDoor[2] + 0.4),
		Color3.fromRGB(60, 64, 84), Enum.Material.Metal)
	local rdg = surface(rd, Enum.NormalId.Back)
	label(rdg, "Text", "ROOF\nfor Lab escapees", UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.35), Color3.fromRGB(200, 215, 255))
	world.roofPrompt = prompt(rd, "RoofPrompt", "Go up", "ROOF", Config.Act.PromptDistance)

	-- AtriumArrival: where ATRIUM and "Back down" put you, in front of the lifts. A plain Part.
	local arr = decorPart(part(f, "AtriumArrival", Vector3.new(6, 0.1, 6), CFrame.new(W.Arrival[1], 0.05, W.Arrival[2]),
		Color3.fromRGB(200, 190, 170), Enum.Material.SmoothPlastic))
	arr.Transparency = 0.6
	world.arrival = arr

	-- the wing directory on the west wall
	local dir = part(f, "Directory", Vector3.new(0.3, 8, 14), CFrame.new(-W.AtriumHalfX + 0.15, 9, 0), Color3.fromRGB(30, 36, 48))
	local dg = surface(dir, Enum.NormalId.Right)
	label(dg, "Title", "THE LAB", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.16), Color3.fromRGB(255, 214, 90), Enum.Font.GothamBlack)
	for i, wing in Config.Lab.Wings do
		label(dg, "Wing_" .. i, string.format("WING %d  %s  (rooms %d-%d)", i, string.upper(wing.name), (i - 1) * 3 + 1, i * 3),
			UDim2.fromScale(0.05, 0.2 + (i - 1) * 0.13), UDim2.fromScale(0.9, 0.11), c3(BANDS[i].light.color), Enum.Font.GothamBold,
			Enum.TextXAlignment.Left)
	end
	label(dg, "Roof", "THE ROOF  (escapees)", UDim2.fromScale(0.05, 0.86), UDim2.fromScale(0.9, 0.11), Color3.fromRGB(200, 215, 255))

	-- two ceiling lights and one dust volume (the signature particle)
	for i, x in { -12, 12 } do
		local fx = part(f, "AtriumLight_" .. i, Vector3.new(6, 0.3, 6), CFrame.new(x, ht - 0.2, 0), Color3.fromRGB(255, 240, 210), Enum.Material.Neon)
		local l = Instance.new("PointLight")
		l.Range = 40
		l.Brightness = 1.2
		l.Color = Color3.fromRGB(255, 226, 180)
		l.Parent = fx
	end
	Fx.dustVolume(f, Vector3.new(2 * hx - 4, ht - 4, 2 * hz - 4), CFrame.new(0, ht / 2, 0), Color3.fromRGB(255, 236, 200), 4)
	f.Parent = workspace
	world.atrium = f
end

local function buildRoof()
	local f = Instance.new("Folder")
	f.Name = "Roof"
	local y, h = W.RoofY, W.RoofHalf
	part(f, "RoofDeck", Vector3.new(2 * h, 1, 2 * h), CFrame.new(0, y - 0.5, 0), Color3.fromRGB(88, 94, 110), Enum.Material.Slate)
	for i, spec in { { 0, -h, 2 * h, 0.4 }, { 0, h, 2 * h, 0.4 }, { -h, 0, 0.4, 2 * h }, { h, 0, 0.4, 2 * h } } do
		part(f, "Rail_" .. i, Vector3.new(spec[3], 3.5, spec[4]), CFrame.new(spec[1], y + 1.75, spec[2]), Color3.fromRGB(200, 210, 255),
			Enum.Material.Metal)
	end
	local dome = part(f, "Dome", Vector3.new(14, 14, 14), CFrame.new(-12, y, -12), Color3.fromRGB(200, 205, 215), Enum.Material.Metal)
	dome.Shape = Enum.PartType.Ball
	local tel = part(f, "Telescope", Vector3.new(9, 1.6, 1.6), CFrame.new(-8, y + 7, -8) * CFrame.Angles(0, math.rad(45), math.rad(35)),
		Color3.fromRGB(60, 64, 84), Enum.Material.Metal)
	tel.Shape = Enum.PartType.Cylinder
	decorPart(part(f, "RoofArrival", Vector3.new(6, 0.1, 6), CFrame.new(0, y + 0.05, 8), Color3.fromRGB(200, 212, 255), Enum.Material.Neon))
	local back = part(f, "BackDown", Vector3.new(4, 3, 0.5), CFrame.new(0, y + 4, 16), Color3.fromRGB(40, 44, 60))
	label(surface(back, Enum.NormalId.Front), "Text", "BACK DOWN", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(200, 215, 255))
	world.backPrompt = prompt(back, "BackPrompt", "Back down", "LIFT", Config.Act.PromptDistance)
	f.Parent = workspace
	world.roof = f
end

buildAtrium()
buildRoof()

local zonesFolder = Instance.new("Folder")
zonesFolder.Name = "Zones"
zonesFolder.Parent = workspace

--============================================================================ state

type Session = any
local sessions: { [Player]: Session } = {}

local ZONES = math.max(W.MinZones, Players.MaxPlayers)
local zones = {}
for i = 1, ZONES do
	zones[i] = { index = i, origin = Vector3.new(W.ZoneSpacing * i, 0, 0), party = nil, folder = nil }
end

local nextRoomId = 0

local function rootOf(plr: Player): BasePart?
	local c = plr.Character
	if c == nil or c.Parent == nil then return nil end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum == nil or hum.Health <= 0 then return nil end
	return c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Every server move is a write on a character already in the world (SPAWN-ORDER.md): guarded, never
-- raced against the engine's own placement.
local function teleport(plr: Player, pos: Vector3, look: Vector3): boolean
	local root = rootOf(plr)
	if root == nil then return false end
	root.CFrame = CFrame.lookAt(pos, pos + look)
	pcall(function() root.AssemblyLinearVelocity = Vector3.zero end)
	return true
end

local function arrivalPos(): Vector3
	return Vector3.new(W.Arrival[1], 3.5, W.Arrival[2])
end

-- The Atrium's lift cabs. `margin` widens a cab for the departure check, which reads the server's view of a
-- root that may lag the client's by a stride.
local function inSoloCab(root: BasePart, margin: number?): boolean
	local p, m = root.Position, margin or 0
	return math.abs(p.X - W.SoloCab[1]) <= W.CabHalf + m and math.abs(p.Z - W.SoloCab[2]) <= W.CabHalf + m and p.Y < 12
end

local function padOf(root: BasePart): string?
	local px, pz = W.PairCab[1], W.PairCab[2]
	local p = root.Position
	if p.Y > 12 then return nil end
	for i, dx in { -W.PairPadDX, W.PairPadDX } do
		if math.abs(p.X - (px + dx)) <= 2.2 and math.abs(p.Z - pz) <= 2.2 then
			return if i == 1 then "A" else "B"
		end
	end
	return nil
end

local function inPairCab(root: BasePart): boolean
	local p = root.Position
	return math.abs(p.X - W.PairCab[1]) <= W.PairCabHalfX + 0.5 and math.abs(p.Z - W.PairCab[2]) <= W.CabHalf + 0.5 and p.Y < 12
end

--============================================================================ profile, save, board

local profileStore, boardStore = nil, nil
do
	local ok, s = pcall(function() return DataStoreService:GetDataStore(Config.Save.Store) end)
	if ok then profileStore = s end
	local ok2, b = pcall(function() return DataStoreService:GetOrderedDataStore(Config.Board.Store) end)
	if ok2 then boardStore = b end
end

local function continueFor(s: Session): number
	local slot = Lab.continueSolo(s.profile.best, s.lastSlot)
	-- Studio staging only: IsStudio AND a profile that cannot save (CLAUDE.md trap 7)
	if Config.Studio.StartSlot ~= nil and RunService:IsStudio() and not s.canSave then
		local ss = Config.Studio.StartSlot
		if type(ss) == "number" and ss >= 1 and ss <= 15 then slot = ss end
	end
	return slot
end

local function sendProfile(plr: Player)
	local s = sessions[plr]
	if not s then return end
	local best = {}
	for k, v in s.profile.best do best[k] = v end
	ProfileEv:FireClient(plr, {
		stars = Profile.total(s.profile),
		best = best,
		frontier = Lab.frontier(s.profile.best),
		continue = continueFor(s),
		escaped = s.profile.escapedAt > 0,
		canSave = s.canSave,
		loaded = s.loaded,
	})
	local ls = plr:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Stars")
	if v then (v :: IntValue).Value = Profile.total(s.profile) end
end

local function copyProfile(p: any): any
	local best = {}
	for k, v in p.best do best[k] = v end
	return { v = 1, best = best, starsAt = p.starsAt, escapedAt = p.escapedAt, boarded = p.boarded, rooms = p.rooms }
end

-- Write the profile, only while the record carries OUR session token (fork-tower REVIEW-4 §10). Then,
-- once that write has landed, the board, keeping max(old, new). Returns true when the profile landed.
--
-- The release (leave, shutdown) is FINAL: from the moment it starts, no other write of this session can
-- land, not even one already in flight, because the transform runs when the write lands and checks
-- `releasing` there; and the released record carries no session token, so a write that slipped past
-- would fail the token check too (review 2026-10-01: an autosave in flight with the release re-took the
-- lock for 45 s, and an immediate rejoin was told "open on another server" and saved nothing).
local function saveNow(plr: Player, release: boolean?): boolean
	local s = sessions[plr]
	if s == nil or not s.canSave or profileStore == nil then return false end
	if s.released or (s.releasing and not release) then return false end
	if release then s.releasing = true end
	local key = "u_" .. tostring(plr.UserId)
	local snapshot = copyProfile(s.profile)
	local stamp = os.time()
	local landed = false
	s.lastWrite = now()
	local ok = pcall(function()
		profileStore:UpdateAsync(key, function(rec)
			landed = false
			if s.releasing and not release then return nil end
			if type(rec) ~= "table" or type(rec.lock) ~= "table" or rec.lock.session ~= s.token then
				return nil
			end
			landed = true
			local lock = if release then { session = "", ["until"] = 0 }
				else { session = s.token, ["until"] = stamp + Config.Save.SessionLockSeconds }
			return { data = snapshot, lock = lock }
		end)
	end)
	if release and ok and landed then s.released = true end
	if s.releasing and not release then return false end
	if ok and not landed then
		s.canSave = false
		if not release and sessions[plr] == s then
			toast(plr, "Your save is open on another server. Progress here will not save.")
			sendProfile(plr)
		end
		return false
	end
	if not ok then return false end
	local total = Profile.total(snapshot)
	if boardStore and total > (s.profile.boarded or 0) then
		local value = Board.encode(total, snapshot.starsAt, Config.Board)
		local okB = pcall(function()
			boardStore:UpdateAsync(Board.key(plr.UserId), function(old)
				return Board.keepHigher(old, value)
			end)
		end)
		if okB then s.profile.boarded = total end
	end
	return true
end

local function requestSave(plr: Player)
	local s = sessions[plr]
	if s == nil or not s.canSave then return end
	local since = now() - s.lastWrite
	if since >= Config.Save.CoalesceSeconds then
		task.spawn(saveNow, plr)
	elseif not s.queued then
		s.queued = true
		task.delay(Config.Save.CoalesceSeconds - since, function()
			s.queued = false
			if sessions[plr] == s then saveNow(plr) end
		end)
	end
end

-- A session that left while its load was in flight may still have taken the lock: release it, if it is ours.
local function releaseGone(key: string, s: Session)
	pcall(function()
		(profileStore :: any):UpdateAsync(key, function(rec)
			if type(rec) ~= "table" or type(rec.lock) ~= "table" or rec.lock.session ~= s.token then return nil end
			return { data = rec.data, lock = { session = "", ["until"] = 0 } }
		end)
	end)
end

-- Load, taking the session lock if it is free, expired or ours. Progress made while the load was
-- pending (the lock held elsewhere) is kept: best per room, merged.
--
-- A load CALL that fails (a throttle, a 5xx) is not the end of the session: the state is "retry", the
-- player is told and plays on, and every autosave tick tries again (review 2026-10-01: one failed call
-- used to leave canSave false for the whole session, with the stored stars hidden). Only a server with no
-- DataStore at all (Studio without API access) plays a session that never saves.
local function loadProfile(plr: Player)
	local s = sessions[plr]
	if s == nil or s.loading then return end
	if profileStore == nil then
		s.loaded = true
		s.state = "nostore"
		toast(plr, Config.Save.Text.NoStore)
		sendProfile(plr)
		return
	end
	s.loading = true
	local key = "u_" .. tostring(plr.UserId)
	local stamp = os.time()
	local result, data = nil, nil
	local ok = pcall(function()
		profileStore:UpdateAsync(key, function(rec)
			-- a session that is gone never takes the lock (review-1 A3: a load landing after the leave held it
			-- for SessionLockSeconds; an immediate rejoin showed 0 stars and could not save for about a minute)
			if s.gone then
				result = "gone"
				return nil
			end
			rec = if type(rec) == "table" then rec else {}
			local lock = rec.lock
			if type(lock) == "table" and lock.session ~= s.token and (tonumber(lock["until"]) or 0) > stamp then
				result = "locked"
				return nil
			end
			result = "ok"
			data = Profile.sanitize(rec.data, stamp)
			return { data = data, lock = { session = s.token, ["until"] = stamp + Config.Save.SessionLockSeconds } }
		end)
	end)
	s.loading = false
	if sessions[plr] ~= s or s.gone then
		-- the transform ran before the leave and the write landed after it: give the lock back
		if ok and result == "ok" then releaseGone(key, s) end
		return
	end
	if not ok then
		s.loaded = true
		s.state = "retry"
		if not s.retryToasted then
			s.retryToasted = true
			toast(plr, Config.Save.Text.LoadRetry)
		end
	elseif result == "locked" then
		s.loaded = true
		s.state = "locked"
		if not s.lockToasted then
			s.lockToasted = true
			toast(plr, "Your save is open on another server - retrying.")
		end
	else
		local played = s.profile
		s.profile = data
		local merged = false
		for k, v in played.best do
			local slot = tonumber(k)
			if slot then
				Profile.record(s.profile, slot, v, os.time())
				merged = true
			end
		end
		s.loaded = true
		s.canSave = true
		s.state = "ready"
		s.lastWrite = now()
		if s.retryToasted or s.lockToasted then toast(plr, Config.Save.Text.Loaded) end
		sendProfile(plr)
		-- what was earned before the load landed goes to the store on the next coalesced write
		if merged then requestSave(plr) end
		return
	end
	sendProfile(plr)
end

--============================================================================ the public board

local nameCache = Board.newCache(Config.Board.NameCacheSeconds)
local function nameOf(userId: number): string
	local cached = Board.cacheGet(nameCache, userId, now())
	if cached then return cached end
	local p = Players:GetPlayerByUserId(userId)
	if p then return p.Name end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	local name = if ok and type(n) == "string" then n else ("Player " .. tostring(userId))
	Board.cachePut(nameCache, userId, name, now())
	return name
end

local function renderPublic(rows: { any }, note: string?)
	local g = world.boardFace
	for i = 1, Config.Board.PublicRows do
		local l = g:FindFirstChild("Row_" .. i) :: TextLabel
		local r = rows[i]
		l.Text = if r then string.format("%d.  %s   \u{2605} %d", r.rank, r.name, r.stars) else ""
	end
	(g:FindFirstChild("Note") :: TextLabel).Text = note or ""
end

local function refreshPublic()
	if boardStore == nil then
		renderPublic({}, Config.Board.Text.Unavailable)
		return
	end
	local ok, page = pcall(function()
		return boardStore:GetSortedAsync(false, Config.Board.PublicRows):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		renderPublic({}, Config.Board.Text.Unavailable)
		return
	end
	local entries = {}
	for _, e in page do
		local id = Board.userIdOf(tostring(e.key))
		if id and type(e.value) == "number" then table.insert(entries, { userId = id, value = e.value }) end
	end
	local view = Board.publicView(entries, Config.Board)
	local rows = {}
	for _, r in view.rows do
		table.insert(rows, { rank = r.rank, name = nameOf(r.userId), stars = r.stars })
	end
	renderPublic(rows, view.note)
end

--============================================================================ friends (on demand, paced)
--
-- Review 2026-10-01: 41 presses on the board prompt used to start 11 fetches (a toggle aborted the
-- running one and the next press began again), 1005 GetAsync reads with 6 in flight at once, so the
-- request-budget check before each read was passed by several fetches together. Now:
--   * single-flight per player: a press while the player's fetch runs starts nothing, and a toggle never
--     aborts it (a later press runs again from the caches below, at no cost);
--   * one friend-score read at a time across the whole server, so the budget check before each read is
--     exact (Board.readStep: read above the reserve, wait up to FriendReadMaxWaitSeconds, else stop and
--     say how far it got);
--   * friend lists and scores are cached across players (a friend's score is read once per 5 min).

local friendLists = Board.newCache(Config.Board.FriendListCacheSeconds)
local friendScores = Board.newCache(Config.Board.FriendScoreCacheSeconds)
local readerBusy = false

local function myValue(s: Session): number
	return Board.encode(Profile.total(s.profile), s.profile.starsAt, Config.Board)
end

local function getAsyncBudget(): number?
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return if ok and type(n) == "number" then n else nil
end

-- One friend's stored board value (0 when they have none), or nil when the budget stayed at the reserve
-- for FriendReadMaxWaitSeconds: the caller stops there.
local function readFriendScore(id: number): number?
	while readerBusy do task.wait(0.05) end
	if Board.cacheHas(friendScores, id, now()) then return Board.cacheGet(friendScores, id, now()) end
	readerBusy = true
	local waited, value = 0, nil
	while true do
		local stepKind = Board.readStep(getAsyncBudget(), Config.Board.GetAsyncReserve, waited, Config.Board.FriendReadMaxWaitSeconds)
		if stepKind == "read" then
			local ok, v = pcall(function() return (boardStore :: any):GetAsync(Board.key(id)) end)
			value = if ok and type(v) == "number" then v else 0
			Board.cachePut(friendScores, id, value, now())
			break
		elseif stepKind == "wait" then
			task.wait(1)
			waited += 1
		else
			break
		end
	end
	readerBusy = false
	return value
end

local function sendFriends(plr: Player, view: any, loading: boolean?)
	local rows = {}
	for _, r in view.rows do
		table.insert(rows, { rank = r.rank, name = nameOf(r.userId), stars = r.stars, you = r.you })
	end
	BoardEv:FireClient(plr, { mode = "friends", rows = rows, message = view.note, loading = loading == true })
end

-- The view from what has been gathered, with the viewer's own row as of NOW.
local function friendsViewOf(plr: Player, s: Session, got: any): any
	got.values[plr.UserId] = myValue(s)
	return Board.friendsView(plr.UserId, got.values, got.status, Config.Board)
end

local function fetchFriends(plr: Player)
	local s = sessions[plr]
	if s == nil or s.friendsBusy then return end
	s.friendsBusy = true
	local function show(loading: boolean)
		if sessions[plr] == s and s.boardMode == "friends" then sendFriends(plr, friendsViewOf(plr, s, s.friendsGot), loading) end
	end
	local ids = Board.cacheGet(friendLists, plr.UserId, now())
	if ids == nil then
		local ok, got = pcall(function()
			local out = {}
			local pages = (Players :: any):GetFriendsAsync(plr.UserId)
			while true do
				for _, item in pages:GetCurrentPage() do
					local id = type(item) == "table" and tonumber(item.Id) or nil
					if id then table.insert(out, id) end
					if #out >= Config.Board.FriendCap then return out end
				end
				if pages.IsFinished then break end
				pages:AdvanceToNextPageAsync()
			end
			return out
		end)
		if not ok or type(got) ~= "table" then
			s.friendsBusy = false
			s.friendsFailedAt = now()
			if sessions[plr] == s and s.boardMode == "friends" then
				BoardEv:FireClient(plr, { mode = "friends", rows = {}, message = Config.Board.Text.FriendsFailed })
			end
			return
		end
		ids = got
		Board.cachePut(friendLists, plr.UserId, ids, now())
	end
	s.friendsGot = { values = {}, status = { friendCount = #ids, checked = 0, failed = false, partial = false } }
	local got = s.friendsGot
	for i, id in ids do
		if sessions[plr] ~= s then return end
		local other = Players:GetPlayerByUserId(id)
		local os_ = other and sessions[other]
		if os_ and os_.loaded then
			got.values[id] = myValue(os_)
		elseif Board.cacheHas(friendScores, id, now()) then
			got.values[id] = Board.cacheGet(friendScores, id, now())
		elseif boardStore then
			local v = readFriendScore(id)
			if v == nil then
				got.status.partial = true
				break
			end
			got.values[id] = v
		end
		got.status.checked = i
		if i % 20 == 0 and i < #ids then show(true) end
	end
	if sessions[plr] ~= s then return end
	s.friendsBusy = false
	show(false)
end

--============================================================================ rooms: generation (server memory only)

local function generateRoom(slot: number): any
	local spec = Lab.roomSpec(Config, slot)
	-- a fresh engine-seeded Random per room: nothing public goes into it (DESIGN.md §14.1)
	local rng = Random.new()
	local function rand(): number
		return rng:NextNumber()
	end
	local feeders = {}
	for _, f in spec.feeders do
		if f.kind == "lamp" then
			local g = nil
			while g == nil do g = Lamps.generate({ n = f.n, k = f.k }, rand) end
			table.insert(feeders, { id = f.id, kind = "lamp", n = f.n, k = f.k, grid = g.grid, set = g.set,
				solved = false, lockUntil = 0, wrongs = 0, hints = {}, told = {} })
		else
			local sh = nil
			while sh == nil do sh = Shelf.generate({ N = f.N, maxClues = Config.Puzzles.MaxShelfClues }, rand) end
			table.insert(feeders, { id = f.id, kind = "shelf", N = f.N, colors = sh.colors, secret = sh.secret, clues = sh.clues,
				order = sh.start, solved = false, lockUntil = 0, wrongs = 0, hints = {}, told = {} })
		end
	end
	local d = nil
	while d == nil do
		d = CodeLock.generate({ L = spec.door.L, alphabet = spec.door.alphabet, feeders = #spec.feeders,
			maxLines = spec.door.maxLines, maxGenerations = Config.Puzzles.MaxGenerations }, rand)
	end
	local feederOf, lineOf = {}, {}
	for i, idx in d.hidden do
		feederOf[idx] = feeders[i].id
		lineOf[feeders[i].id] = idx
	end
	local door = { id = "Door", kind = "door", L = spec.door.L, alphabet = spec.door.alphabet, secret = d.secret,
		lines = d.lines, hidden = d.hidden, feederOf = feederOf, lineOf = lineOf, lit = {}, solved = false,
		lockUntil = 0, wrongs = 0, lastWrong = nil, hints = {}, told = {} }
	local byId = { Door = door }
	for _, f in feeders do byId[f.id] = f end
	nextRoomId += 1
	return {
		roomId = nextRoomId, slot = slot, spec = spec, wing = spec.wing, room = spec.room, wingName = spec.wingName,
		feeders = feeders, door = door, byId = byId, rand = rand, state = "playing",
	}
end

--============================================================================ rooms: the build

local LIT = Color3.fromRGB(255, 226, 110)
local UNLIT = Color3.fromRGB(46, 50, 62)
local RIM_OPEN = Color3.fromRGB(90, 220, 255)
local RIM_DONE = Color3.fromRGB(110, 255, 140)
local FLASK_COLORS = {
	Color3.fromRGB(230, 60, 60), Color3.fromRGB(60, 110, 240), Color3.fromRGB(60, 200, 90),
	Color3.fromRGB(245, 215, 60), Color3.fromRGB(160, 80, 220),
}

local function kindName(st: any): string
	if st.kind == "lamp" then return "LAMP GRID " .. st.id end
	if st.kind == "shelf" then return "FLASK SHELF " .. st.id end
	return "DOOR"
end

local PROP_SLOTS = { { -13, 12 }, { 13, 12 }, { -13.5, -9 }, { 13.5, -9 } }

local function buildProp(f: Folder, kind: string, at: Vector3, band: any)
	local trim = c3(band.palette.trim)
	if kind == "desk" then
		part(f, "Prop_desk", Vector3.new(4, 0.3, 2), CFrame.new(at + Vector3.new(0, 2.6, 0)), trim, Enum.Material.Wood)
		part(f, "Prop_deskBase", Vector3.new(3.6, 2.45, 1.6), CFrame.new(at + Vector3.new(0, 1.225, 0)), trim, Enum.Material.Wood)
	elseif kind == "fern" or kind == "fern2" then
		part(f, "Prop_pot", Vector3.new(1.4, 1.4, 1.4), CFrame.new(at + Vector3.new(0, 0.7, 0)), Color3.fromRGB(170, 100, 70), Enum.Material.Slate)
		local leaves = part(f, "Prop_fern", Vector3.new(2.6, 2.4, 2.6), CFrame.new(at + Vector3.new(0, 2.4, 0)), Color3.fromRGB(70, 150, 70),
			Enum.Material.Grass)
		leaves.Shape = Enum.PartType.Ball
	elseif kind == "cooler" then
		part(f, "Prop_cooler", Vector3.new(1.4, 3.2, 1.4), CFrame.new(at + Vector3.new(0, 1.6, 0)), Color3.fromRGB(230, 232, 236))
		part(f, "Prop_bottle", Vector3.new(1.1, 1.4, 1.1), CFrame.new(at + Vector3.new(0, 3.9, 0)), Color3.fromRGB(150, 200, 255), Enum.Material.Glass)
	elseif kind == "shelves" then
		part(f, "Prop_shelves", Vector3.new(1.6, 8, 4), CFrame.new(at + Vector3.new(0, 4, 0)), trim, Enum.Material.Wood)
		part(f, "Prop_files", Vector3.new(1.7, 1.2, 3.6), CFrame.new(at + Vector3.new(0, 5.5, 0)), Color3.fromRGB(200, 180, 140), Enum.Material.Fabric)
	elseif kind == "ladder" then
		part(f, "Prop_railL", Vector3.new(0.3, 9, 0.3), CFrame.new(at + Vector3.new(0, 4.5, -0.8)), trim, Enum.Material.Wood)
		part(f, "Prop_railR", Vector3.new(0.3, 9, 0.3), CFrame.new(at + Vector3.new(0, 4.5, 0.8)), trim, Enum.Material.Wood)
		part(f, "Prop_rungs", Vector3.new(0.2, 0.2, 1.6), CFrame.new(at + Vector3.new(0, 3, 0)), trim, Enum.Material.Wood)
	elseif kind == "boxes" then
		for i = 1, 3 do
			part(f, "Prop_box" .. i, Vector3.new(1.8, 1.4, 1.8), CFrame.new(at + Vector3.new(0, 0.7 + (i - 1) * 1.4, 0)) * CFrame.Angles(0, i * 0.3, 0),
				Color3.fromRGB(180, 150, 110), Enum.Material.Cardboard)
		end
	elseif kind == "bankerlamp" then
		part(f, "Prop_table", Vector3.new(2.4, 2.6, 1.6), CFrame.new(at + Vector3.new(0, 1.3, 0)), trim, Enum.Material.Wood)
		part(f, "Prop_shade", Vector3.new(1.2, 0.5, 0.6), CFrame.new(at + Vector3.new(0, 3.2, 0)), Color3.fromRGB(40, 160, 90), Enum.Material.Neon)
	elseif kind == "palm" then
		part(f, "Prop_trunk", Vector3.new(0.8, 7, 0.8), CFrame.new(at + Vector3.new(0, 3.5, 0)), Color3.fromRGB(120, 90, 60), Enum.Material.Wood)
		local fronds = part(f, "Prop_fronds", Vector3.new(5, 1.6, 5), CFrame.new(at + Vector3.new(0, 7.4, 0)), Color3.fromRGB(60, 160, 70),
			Enum.Material.Grass)
		fronds.Shape = Enum.PartType.Ball
	elseif kind == "planter" or kind == "planter2" then
		part(f, "Prop_planter", Vector3.new(3, 1.2, 1.6), CFrame.new(at + Vector3.new(0, 0.6, 0)), Color3.fromRGB(150, 95, 70), Enum.Material.Slate)
		local plant = part(f, "Prop_plant", Vector3.new(2.6, 1.8, 1.4), CFrame.new(at + Vector3.new(0, 1.9, 0)), Color3.fromRGB(90, 180, 80),
			Enum.Material.Grass)
		plant.Shape = Enum.PartType.Ball
	elseif kind == "mistpipe" then
		part(f, "Prop_mistpipe", Vector3.new(0.5, 9, 0.5), CFrame.new(at + Vector3.new(0, 4.5, 0)), Color3.fromRGB(180, 190, 200), Enum.Material.Metal)
	elseif kind == "rack" or kind == "rack2" then
		part(f, "Prop_rack", Vector3.new(1.6, 7, 3.6), CFrame.new(at + Vector3.new(0, 3.5, 0)), Color3.fromRGB(170, 185, 200), Enum.Material.DiamondPlate)
		part(f, "Prop_frost", Vector3.new(1.7, 0.4, 3.7), CFrame.new(at + Vector3.new(0, 7.1, 0)), Color3.fromRGB(235, 245, 255), Enum.Material.Snow)
	elseif kind == "crates" or kind == "crates2" then
		part(f, "Prop_crate1", Vector3.new(2, 2, 2), CFrame.new(at + Vector3.new(0, 1, 0)), Color3.fromRGB(200, 225, 245), Enum.Material.Ice)
		part(f, "Prop_crate2", Vector3.new(1.6, 1.6, 1.6), CFrame.new(at + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0.4, 0),
			Color3.fromRGB(200, 225, 245), Enum.Material.Ice)
	elseif kind == "core" then
		local core = part(f, "Prop_core", Vector3.new(8, 3.4, 3.4), CFrame.new(at + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(60, 255, 230), Enum.Material.Glass)
		core.Shape = Enum.PartType.Cylinder
		core.Transparency = 0.35
		local glow = part(f, "Prop_coreGlow", Vector3.new(7.6, 1.2, 1.2), CFrame.new(at + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(170, 90, 255), Enum.Material.Neon)
		glow.Shape = Enum.PartType.Cylinder
	elseif kind == "pipes" or kind == "pipes2" then
		part(f, "Prop_pipeA", Vector3.new(0.9, 12, 0.9), CFrame.new(at + Vector3.new(0, 6, -0.8)), Color3.fromRGB(90, 96, 110), Enum.Material.Metal)
		part(f, "Prop_pipeB", Vector3.new(0.9, 12, 0.9), CFrame.new(at + Vector3.new(0, 6, 0.8)), Color3.fromRGB(90, 96, 110), Enum.Material.Metal)
	elseif kind == "stripes" then
		decorPart(part(f, "Prop_stripes", Vector3.new(3, 0.05, 3), CFrame.new(at + Vector3.new(0, 0.03, 0)), Color3.fromRGB(250, 200, 40)))
	end
end

-- Fill a SurfaceGui-carrying part's labels from the room's current state.
local function renderDoorBoard(party: any)
	local room, parts = party.room, party.parts
	local d = room.door
	local hiddenSet = {}
	for _, i in d.hidden do hiddenSet[i] = true end
	local g = parts.boardGui
	for i = 1, Config.Puzzles.MaxDoorLines do
		local gl = g:FindFirstChild("RowGuess_" .. i) :: TextLabel
		local tl = g:FindFirstChild("RowText_" .. i) :: TextLabel
		local ln = d.lines[i]
		if ln == nil then
			gl.Text = ""
			tl.Text = ""
		elseif hiddenSet[i] and not d.lit[i] then
			gl.Text = string.rep("? ", d.L - 1) .. "?"
			tl.Text = "Lit by " .. kindName(room.byId[d.feederOf[i]])
			gl.TextColor3 = Color3.fromRGB(120, 130, 150)
			tl.TextColor3 = Color3.fromRGB(120, 130, 150)
		else
			gl.Text = Text.codeGuess(ln.guess)
			tl.Text = Text.codeSentence(ln.a, ln.b)
			gl.TextColor3 = Color3.fromRGB(255, 236, 170)
			tl.TextColor3 = Color3.fromRGB(240, 240, 245)
		end
	end
	for i, lamp in parts.locks do
		local dark = hiddenSet[i] and not d.lit[i]
		lamp.Color = if dark then Color3.fromRGB(230, 60, 60) else Color3.fromRGB(90, 240, 120)
	end
	local allLit = true
	for _, i in d.hidden do
		if not d.lit[i] then allLit = false end
	end
	local kp = parts.keypadLabel :: TextLabel
	local lockLeft = d.lockUntil - now()
	if d.solved then
		kp.Text = "OPEN"
	elseif lockLeft > 0 and d.lastWrong then
		kp.Text = Text.codeGuess(d.lastWrong) .. " X"
	elseif allLit then
		kp.Text = string.rep("? ", d.L - 1) .. "?"
	else
		kp.Text = "DARK"
	end
	parts.lockGlow.Color = if allLit then Color3.fromRGB(90, 240, 120) else Color3.fromRGB(230, 60, 60)
end

local function renderStation(party: any, st: any)
	local sp = party.parts.stations[st.id]
	if sp == nil then return end
	if st.kind == "lamp" then
		for i, lamp in sp.lamps do
			local lit = st.grid[i]
			lamp.Color = if lit then LIT else UNLIT
			lamp.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	elseif st.kind == "shelf" then
		for slot, flask in sp.flasks do
			local c = st.order[slot]
			flask.Color = FLASK_COLORS[c]
			local l = flask:FindFirstChild("Letter", true) :: TextLabel
			if l then l.Text = Text.FlaskLetters[c] end
		end
	end
	sp.rim.Color = if st.solved then RIM_DONE else RIM_OPEN
end

local function buildRoom(party: any)
	local zone = party.zone
	if zone.folder then zone.folder:Destroy() end
	local room = party.room
	local band = BANDS[room.wing]
	local o = zone.origin
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(o.X + x, o.Y + y, o.Z + z)
	end
	local f = Instance.new("Folder")
	f.Name = "Zone_" .. zone.index
	local wallC, floorC = c3(band.palette.wall), c3(band.palette.floor)
	local wallM = (Enum.Material :: any)[band.palette.wallMaterial]
	local floorM = (Enum.Material :: any)[band.palette.floorMaterial]
	local H, R, T = W.RoomHeight, W.RoomHalf, W.Wall
	local dw, dh = W.DoorwayWidth, W.DoorwayHeight
	local side = (R - dw / 2) -- 13: a wall segment beside a doorway
	-- the shell (10 parts)
	part(f, "Floor", Vector3.new(2 * R + 2 * T, 1, 2 * R + 2 * T), at(0, -0.5, 0), floorC, floorM)
	part(f, "Ceiling", Vector3.new(2 * R + 2 * T, 1, 2 * R + 2 * T), at(0, H + 0.5, 0), wallC, wallM)
	part(f, "WallW", Vector3.new(T, H, 2 * R + 2 * T), at(-R - T / 2, H / 2, 0), wallC, wallM)
	part(f, "WallE", Vector3.new(T, H, 2 * R + 2 * T), at(R + T / 2, H / 2, 0), wallC, wallM)
	for _, zSign in { 1, -1 } do
		local zc = zSign * (R + T / 2)
		local tag = if zSign > 0 then "S" else "N"
		part(f, "Wall" .. tag .. "L", Vector3.new(side, H, T), at(-(dw / 2 + side / 2), H / 2, zc), wallC, wallM)
		part(f, "Wall" .. tag .. "R", Vector3.new(side, H, T), at(dw / 2 + side / 2, H / 2, zc), wallC, wallM)
		part(f, "Wall" .. tag .. "Top", Vector3.new(dw, H - dh, T), at(0, dh + (H - dh) / 2, zc), wallC, wallM)
	end
	-- the entry cab, south (8 parts)
	local cabC = Color3.fromRGB(70, 80, 96)
	local ce = R + T + W.CabHalf -- 21
	part(f, "EntryFloor", Vector3.new(2 * W.CabHalf, 1, 2 * W.CabHalf), at(0, -0.5, ce), cabC, Enum.Material.DiamondPlate)
	part(f, "EntryRoof", Vector3.new(2 * W.CabHalf + 2, 1, 2 * W.CabHalf + 2), at(0, W.CabHeight + 0.5, ce), cabC, Enum.Material.Metal)
	part(f, "EntryWallW", Vector3.new(1, W.CabHeight, 2 * W.CabHalf), at(-W.CabHalf - 0.5, W.CabHeight / 2, ce), cabC, Enum.Material.Metal)
	part(f, "EntryWallE", Vector3.new(1, W.CabHeight, 2 * W.CabHalf), at(W.CabHalf + 0.5, W.CabHeight / 2, ce), cabC, Enum.Material.Metal)
	part(f, "EntryBack", Vector3.new(2 * W.CabHalf + 2, W.CabHeight, 1), at(0, W.CabHeight / 2, ce + W.CabHalf + 0.5), cabC, Enum.Material.Metal)
	local entryDoor = part(f, "EntryDoor", Vector3.new(dw, dh, T), at(0, dh / 2, R + T / 2), Color3.fromRGB(140, 150, 165), Enum.Material.Metal)
	local leaveEntry = part(f, "LeaveEntry", Vector3.new(2, 2, 0.4), at(0, 4.5, ce + W.CabHalf - 0.3), Color3.fromRGB(40, 44, 60))
	label(surface(leaveEntry, Enum.NormalId.Front), "Text", "ATRIUM", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(200, 215, 255))
	-- the corridor and exit cab, north (11 parts)
	local cl = W.CorridorLength
	local cz = -(R + T + cl / 2)
	part(f, "CorridorFloor", Vector3.new(dw, 1, cl), at(0, -0.5, cz), cabC, Enum.Material.DiamondPlate)
	part(f, "CorridorRoof", Vector3.new(dw + 2, 1, cl), at(0, W.CabHeight + 0.5, cz), cabC, Enum.Material.Metal)
	part(f, "CorridorW", Vector3.new(1, W.CabHeight, cl), at(-dw / 2 - 0.5, W.CabHeight / 2, cz), cabC, Enum.Material.Metal)
	part(f, "CorridorE", Vector3.new(1, W.CabHeight, cl), at(dw / 2 + 0.5, W.CabHeight / 2, cz), cabC, Enum.Material.Metal)
	local cx = -(R + T + cl + W.CabHalf) -- -24
	part(f, "ExitFloor", Vector3.new(2 * W.CabHalf, 1, 2 * W.CabHalf), at(0, -0.5, cx), cabC, Enum.Material.DiamondPlate)
	part(f, "ExitRoof", Vector3.new(2 * W.CabHalf + 2, 1, 2 * W.CabHalf + 2), at(0, W.CabHeight + 0.5, cx), cabC, Enum.Material.Metal)
	part(f, "ExitWallW", Vector3.new(1, W.CabHeight, 2 * W.CabHalf), at(-W.CabHalf - 0.5, W.CabHeight / 2, cx), cabC, Enum.Material.Metal)
	part(f, "ExitWallE", Vector3.new(1, W.CabHeight, 2 * W.CabHalf), at(W.CabHalf + 0.5, W.CabHeight / 2, cx), cabC, Enum.Material.Metal)
	part(f, "ExitBack", Vector3.new(2 * W.CabHalf + 2, W.CabHeight, 1), at(0, W.CabHeight / 2, cx - W.CabHalf - 0.5), cabC, Enum.Material.Metal)
	local nextPanel = part(f, "NextPanel", Vector3.new(2, 2, 0.4), at(-2, 4.5, cx - W.CabHalf + 0.3), Color3.fromRGB(40, 44, 60))
	local nextLabel = label(surface(nextPanel, Enum.NormalId.Back), "Text", "NEXT", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1),
		Color3.fromRGB(150, 255, 200))
	local leaveExit = part(f, "LeaveExit", Vector3.new(2, 2, 0.4), at(2, 4.5, cx - W.CabHalf + 0.3), Color3.fromRGB(40, 44, 60))
	label(surface(leaveExit, Enum.NormalId.Back), "Text", "ATRIUM", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(200, 215, 255))

	-- the door station (the leaf, the prompt anchor, the board, the keypad, a lock lamp per line)
	local S = W.Stations
	local leaf = part(f, "DoorLeaf", Vector3.new(dw, dh, T), at(0, dh / 2, -R - T / 2), Color3.fromRGB(120, 128, 150), Enum.Material.DiamondPlate)
	local lockGlow = Instance.new("PointLight")
	lockGlow.Name = "LockGlow"
	lockGlow.Range = 10
	lockGlow.Brightness = 1.5
	lockGlow.Color = Color3.fromRGB(230, 60, 60)
	lockGlow.Parent = leaf
	local doorAnchor = decorPart(part(f, "Door", Vector3.new(dw, dh, 0.2), at(S.Door[1], S.Door[2], S.Door[3]), Color3.new(1, 1, 1)))
	doorAnchor.Transparency = 1
	local boardPart = part(f, "DoorBoard", Vector3.new(12, 7, 0.5), at(W.DoorBoard[1], W.DoorBoard[2], W.DoorBoard[3] - 0.25),
		Color3.fromRGB(22, 26, 38))
	local bg = surface(boardPart, Enum.NormalId.Back, "BoardFace")
	label(bg, "Title", string.format("DOOR  -  %d digits, none repeat", room.door.L), UDim2.fromScale(0.03, 0.02), UDim2.fromScale(0.94, 0.12),
		Color3.fromRGB(150, 230, 255), Enum.Font.GothamBlack)
	for i = 1, Config.Puzzles.MaxDoorLines do
		local y = 0.17 + (i - 1) * 0.135
		label(bg, "RowGuess_" .. i, "", UDim2.fromScale(0.03, y), UDim2.fromScale(0.22, 0.11), Color3.fromRGB(255, 236, 170), Enum.Font.GothamBlack)
		label(bg, "RowText_" .. i, "", UDim2.fromScale(0.27, y), UDim2.fromScale(0.7, 0.11), Color3.fromRGB(240, 240, 245), Enum.Font.Gotham,
			Enum.TextXAlignment.Left)
	end
	local keypad = part(f, "Keypad", Vector3.new(3, 4, 0.5), at(W.Keypad[1], W.Keypad[2], W.Keypad[3] - 0.25), Color3.fromRGB(30, 34, 46), Enum.Material.Metal)
	local keypadLabel = label(surface(keypad, Enum.NormalId.Back), "KeypadText", "DARK", UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.9, 0.4),
		Color3.fromRGB(255, 236, 170), Enum.Font.GothamBlack)
	local locks = {}
	local nLines = #room.door.lines
	for i = 1, nLines do
		locks[i] = part(f, "Lock_" .. i, Vector3.new(0.6, 0.6, 0.3), at((i - (nLines + 1) / 2) * 0.9, dh + 0.7, -R + 0.15), Color3.fromRGB(230, 60, 60),
			Enum.Material.Neon)
	end

	-- feeder stations
	local stations = {}
	for _, st in room.feeders do
		local sideSign = if st.id == "A" then -1 else 1
		local pos = S[st.id]
		local face = if sideSign < 0 then Enum.NormalId.Right else Enum.NormalId.Left
		local panel = part(f, "Station_" .. st.id, Vector3.new(1, 8, 10), at(pos[1], pos[2], pos[3]), Color3.fromRGB(34, 38, 52))
		local rim = part(f, "Rim_" .. st.id, Vector3.new(0.3, 8.6, 10.6), at(sideSign * (R - 0.15), pos[2], pos[3]), RIM_OPEN, Enum.Material.Neon)
		local sign = part(f, "Sign_" .. st.id, Vector3.new(0.4, 1.4, 7), at(sideSign * (R - 0.2), 11.6, pos[3]), Color3.fromRGB(30, 36, 48))
		label(surface(sign, face), "Text", kindName(st), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(150, 230, 255))
		local entry = { panel = panel, rim = rim, lamps = {}, flasks = {} }
		local faceX = sideSign * (R - 1) -- the panel's face, 1 stud off the wall
		if st.kind == "lamp" then
			local n = st.n
			local mid = (n + 1) / 2
			for r = 1, n do
				for c = 1, n do
					local i = (r - 1) * n + c
					local lamp = part(panel, "Lamp_" .. i, Vector3.new(0.3, 1.2, 1.2),
						at(faceX - sideSign * 0.15, 6.8 + (mid - r) * 1.6, sideSign * (c - mid) * 1.6), UNLIT)
					entry.lamps[i] = lamp
				end
			end
		else
			local N = st.N
			part(f, "ShelfPlank_" .. st.id, Vector3.new(1.2, 0.3, 9), at(faceX - sideSign * 0.6, 4.4, 0), c3(band.palette.trim), Enum.Material.Wood)
			for s = 1, N do
				local flask = part(panel, "Flask_" .. s, Vector3.new(0.9, 1.8, 0.9),
					at(faceX - sideSign * 0.6, 5.45, sideSign * (s - (N + 1) / 2) * 1.7), FLASK_COLORS[1], Enum.Material.Glass)
				local fg = surface(flask, face, "LetterFace")
				label(fg, "Letter", "", UDim2.fromScale(0, 0.2), UDim2.fromScale(1, 0.6), Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack)
				entry.flasks[s] = flask
			end
			local cg = surface(panel, face, "ClueFace")
			label(cg, "Title", "Clues", UDim2.fromScale(0.04, 0.02), UDim2.fromScale(0.92, 0.07), Color3.fromRGB(150, 230, 255), Enum.Font.GothamBlack)
			for i, c in st.clues do
				label(cg, "Clue_" .. i, Text.shelfClue(c), UDim2.fromScale(0.04, 0.09 + (i - 1) * 0.048), UDim2.fromScale(0.92, 0.045),
					Color3.fromRGB(240, 240, 245), Enum.Font.Gotham, Enum.TextXAlignment.Left)
			end
		end
		stations[st.id] = entry
		entry.prompt = prompt(panel, "OpenPrompt", "Open", kindName(st), Config.Act.PromptDistance)
	end
	local doorPrompt = prompt(doorAnchor, "OpenPrompt", "Open", "DOOR", Config.Act.PromptDistance)

	-- the ceiling lights: two fixtures, each a PointLight in the wing's colour
	for i, z in { -8, 8 } do
		local fx = part(f, "Fixture_" .. i, Vector3.new(4, 0.3, 4), at(0, H - 0.15, z), c3(band.light.color), Enum.Material.Neon)
		local l = Instance.new("PointLight")
		l.Range = W.LightRange
		l.Brightness = band.light.brightness
		l.Color = c3(band.light.color)
		l.Parent = fx
	end
	-- the wing's props, in four slots clear of every station face and doorway
	for i, kind in band.props do
		local slot = PROP_SLOTS[i]
		if slot then buildProp(f, kind, Vector3.new(o.X + slot[1], o.Y, o.Z + slot[2]), band) end
	end

	-- prompts
	local leaveEntryPrompt = prompt(leaveEntry, "LeavePrompt", "Atrium", "LIFT", Config.Act.PromptDistance)
	leaveEntryPrompt.HoldDuration = Config.Act.LeaveHoldSeconds
	local nextPrompt = prompt(nextPanel, "NextPrompt", if room.slot == 15 then "Up to the Roof" else "Next room", "LIFT", Config.Act.PromptDistance)
	nextPrompt.Enabled = false
	local leaveExitPrompt = prompt(leaveExit, "LeavePrompt", "Atrium", "LIFT", Config.Act.PromptDistance)
	leaveExitPrompt.HoldDuration = Config.Act.LeaveHoldSeconds
	leaveExitPrompt.Enabled = false
	nextLabel.Text = if room.slot == 15 then "ROOF" else "NEXT"

	f.Parent = zonesFolder
	zone.folder = f
	party.parts = {
		folder = f, stations = stations, boardGui = bg, keypadLabel = keypadLabel, locks = locks, lockGlow = lockGlow,
		leaf = leaf, entryDoor = entryDoor, doorPrompt = doorPrompt, nextPrompt = nextPrompt, leaveExitPrompt = leaveExitPrompt,
		leaveEntryPrompt = leaveEntryPrompt,
	}
	for _, st in room.feeders do renderStation(party, st) end
	renderDoorBoard(party)
	return f
end

--============================================================================ parties

local function localPos(party: any, p: Vector3): Vector3
	return p - party.zone.origin
end

local function inExitCab(party: any, plr: Player): boolean
	local root = rootOf(plr)
	if root == nil then return false end
	local l = localPos(party, root.Position)
	local zc = -(W.RoomHalf + W.Wall + W.CorridorLength + W.CabHalf)
	return math.abs(l.X) <= W.CabHalf + 0.5 and math.abs(l.Z - zc) <= W.CabHalf + 0.5 and l.Y < W.CabHeight
end

local function sendRoomState(party: any)
	local room = party.room
	if room == nil then return end
	room.origin = { party.zone.origin.X, party.zone.origin.Y, party.zone.origin.Z }
	local names = {}
	for _, m in party.members do table.insert(names, m.Name) end
	room.members = names
	room.pair = party.pair
	for _, m in party.members do
		RoomStateEv:FireClient(m, RoomView.build(room, party.results[m] or {}, now()))
	end
end

local function noticeParty(party: any, payload: any)
	for _, m in party.members do Notice:FireClient(m, payload) end
end

local function freeZone(zone: any)
	if zone.folder then
		zone.folder:Destroy()
		zone.folder = nil
	end
	zone.party = nil
end

local function removeMember(party: any, plr: Player)
	for i, m in party.members do
		if m == plr then
			table.remove(party.members, i)
			break
		end
	end
	party.results[plr] = nil
	local s = sessions[plr]
	if s and s.party == party then s.party = nil end
	if #party.members == 0 then
		party.dead = true
		freeZone(party.zone)
		return
	end
	-- the one left carries on solo, and from now on the hands-on rule no longer applies to them
	party.pair = false
	for _, m in party.members do
		toast(m, plr.Name .. " went back to the Atrium. Carry on solo.")
	end
	if party.parts then sendRoomState(party) end
end

local function leaveToAtrium(plr: Player, move: boolean)
	local s = sessions[plr]
	if s == nil then return end
	local party = s.party
	if party then removeMember(party, plr) end
	s.riding = false
	s.location = "atrium"
	if move then teleport(plr, arrivalPos(), Vector3.new(0, 0, -1)) end
	RoomStateEv:FireClient(plr, RoomView.outside("atrium"))
end

local function newParty(members: { Player }): any
	local zone = nil
	for _, z in zones do
		if z.party == nil then
			zone = z
			break
		end
	end
	if zone == nil then
		for _, m in members do toast(m, "Every room is busy. Try again in a moment.") end
		return nil
	end
	local party = { members = table.clone(members), zone = zone, pair = #members == 2, results = {}, room = nil,
		parts = nil, state = "riding", dead = false }
	zone.party = party
	for _, m in members do
		sessions[m].party = party
		sessions[m].riding = true
	end
	return party
end

local function cardText(room: any): string
	local kinds = {}
	for _, st in room.feeders do table.insert(kinds, kindName(st)) end
	local what = table.concat(kinds, " and ")
	if #room.feeders == 1 then
		return "The door's code is in its clue lines. Solve the " .. what .. " to light the last one."
	end
	return "Solve the " .. what .. " to light the door's last lines, then crack its code."
end

local function startRoom(party: any, slot: number)
	if party.dead then return end
	local room = generateRoom(slot)
	party.room = room
	party.results = {}
	party.shared = #party.members == 2 -- the room's stars are a pair's from here on, even if one leaves
	for _, m in party.members do party.results[m] = { wrong = false, hinted = false, handsOn = false } end
	buildRoom(party)
	party.state = "playing"
	local o = party.zone.origin
	local cabZ = W.RoomHalf + W.Wall + W.CabHalf
	for i, m in party.members do
		local s = sessions[m]
		s.riding = false
		s.location = "room"
		local dx = if #party.members == 2 then (if i == 1 then -1.5 else 1.5) else 0
		teleport(m, o + Vector3.new(dx, 3.5, cabZ), Vector3.new(0, 0, -1))
	end
	-- the cab door opens a beat after arrival: the lift illusion
	local doorPart = party.parts.entryDoor
	task.delay(0.6, function()
		if doorPart.Parent then
			doorPart.CanCollide = false
			doorPart.Transparency = 1
		end
	end)
	sendRoomState(party)
	noticeParty(party, { kind = "room", slot = slot, wing = room.wing, room = room.room, wingName = room.wingName,
		text = cardText(room) })
end

-- Is this member still aboard the Atrium lift `lift` ("solo" | "pair") as it leaves? (review-1 A2, B2: a
-- rider who walked out during the ride, or a partner who walked off to the Star Board, used to be taken
-- anyway, from wherever they stood.) A room's exit lift (lift = nil) takes everyone in the party.
local function aboard(plr: Player, lift: string?): boolean
	local root = rootOf(plr)
	if root == nil then return false end
	if lift == "solo" then return inSoloCab(root, 0.5) end
	if lift == "pair" then return inPairCab(root) end
	return true
end

local function ride(party: any, slot: number, lift: string?)
	party.state = "riding"
	-- NEXT goes dark as the lift leaves (review-1 B3: it stayed lit, and a partner's second press was told
	-- "The door is still shut." as the lift went up)
	if party.parts then party.parts.nextPrompt.Enabled = false end
	local wingName = Config.Lab.Wings[(Lab.wingRoomOf(slot))].name
	noticeParty(party, { kind = "ride", text = "Going up to " .. wingName .. "...", lift = lift })
	task.delay(Config.Lift.RideSeconds, function()
		if party.dead then return end
		for _, m in table.clone(party.members) do
			if m.Parent ~= Players or rootOf(m) == nil then
				removeMember(party, m)
			elseif not aboard(m, lift) then
				-- stays in the Atrium; a pair that loses one goes on solo (removeMember tells the other)
				leaveToAtrium(m, false)
				toast(m, Config.Lift.SteppedOutText)
			end
		end
		if party.dead then return end
		startRoom(party, slot)
	end)
end

-- On the Roof. The brag moment plays on the FIRST arrival after the escape that completed the Lab, by
-- room 15's lift or by the Atrium's Roof door (review 2026-10-01: taking ATRIUM from room 15 and then
-- the door skipped the card and the announcement for good).
local function arriveRoof(plr: Player, s: Session, card: boolean)
	s.location = "roof"
	RoomStateEv:FireClient(plr, RoomView.outside("roof"))
	local first = s.roofFirst == true
	if card or first then
		Notice:FireClient(plr, { kind = "roof", first = first, text = "YOU ESCAPED THE LAB" })
	end
	if first then
		s.roofFirst = false
		for _, other in Players:GetPlayers() do
			Notice:FireClient(other, { kind = "brag", text = plr.Name .. " escaped the Lab!" })
		end
	end
end

-- Room 15's lift goes up with everyone in it. The party is dissolved as a whole: taking it apart one
-- member at a time told the other one "X went back to the Atrium" (review 2026-10-01).
local function sendToRoof(party: any)
	local members = table.clone(party.members)
	party.dead = true
	party.members = {}
	party.results = {}
	freeZone(party.zone)
	for _, m in members do
		local s = sessions[m]
		if s then
			if s.party == party then s.party = nil end
			s.riding = false
			teleport(m, Vector3.new(0, W.RoofY + 3.5, 8), Vector3.new(0, 0, -1))
			arriveRoof(m, s, true)
		end
	end
end

--============================================================================ verdicts

local function allLit(room: any): boolean
	for _, i in room.door.hidden do
		if not room.door.lit[i] then return false end
	end
	return true
end

local function darkNames(room: any): string
	local out = {}
	for _, st in room.feeders do
		if not st.solved then table.insert(out, kindName(st)) end
	end
	return table.concat(out, " and ")
end

local function sparkle(host: BasePart, color: Color3)
	local e = Fx.sparkle(host, color)
	task.delay(2, function()
		if e.Parent then e.Enabled = false end
	end)
end

local function solveFeeder(party: any, st: any, plr: Player)
	local room = party.room
	st.solved = true
	st.lockUntil = 0
	st.wrongs = 0
	party.results[plr].handsOn = true
	local idx = room.door.lineOf[st.id]
	room.door.lit[idx] = true
	renderStation(party, st)
	renderDoorBoard(party)
	sparkle(party.parts.stations[st.id].panel, RIM_DONE)
	local lit = allLit(room)
	noticeParty(party, { kind = "lit", text = string.format("%s solved! Door line %d is lit.%s", kindName(st), idx,
		if lit then " The keypad is awake." else "") })
	sendRoomState(party)
end

local function starReasons(r: any, party: any): { string }
	local out = {}
	if party.pair and not r.handsOn then
		table.insert(out, "No stars: complete a station yourself to earn them in a pair.")
		return out
	end
	if r.wrong then
		table.insert(out, if party.shared then "Clean star missed: a wrong try in your pair." else "Clean star missed: a wrong try.")
	end
	if r.hinted then
		table.insert(out, if party.shared then "Unaided star missed: a hint was taken in your pair." else "Unaided star missed: you took a hint.")
	end
	return out
end

-- The Clean and Unaided stars belong to the room's TEAM: a wrong try or a hint marks everyone in it, and the
-- mark stays with whoever carries on (review-1 A4: per-player marks let one partner absorb every hint and
-- wrong try while the other entered the code worked out for them and took all 3 stars).
local function markTeam(party: any, field: string)
	for _, m in party.members do
		local r = party.results[m]
		if r then r[field] = true end
	end
end

local function solveDoor(party: any, plr: Player)
	local room = party.room
	local d = room.door
	d.solved = true
	d.lockUntil = 0
	party.results[plr].handsOn = true
	party.state = "escaped"
	room.state = "escaped"
	local parts = party.parts
	parts.leaf.CanCollide = false
	parts.leaf.Transparency = 1
	parts.leaf.CFrame = parts.leaf.CFrame + Vector3.new(0, W.DoorwayHeight - 0.2, 0)
	parts.doorPrompt.Enabled = false
	renderDoorBoard(party)
	sparkle(parts.leaf, RIM_DONE)
	parts.nextPrompt.Enabled = true
	parts.leaveExitPrompt.Enabled = true
	local stamp = os.time()
	for _, m in party.members do
		local s = sessions[m]
		local r = party.results[m]
		local stars = Lab.stars({ escaped = true, wrong = r.wrong, hinted = r.hinted, pair = party.pair, handsOn = r.handsOn })
		local rec = Profile.record(s.profile, room.slot, stars, stamp)
		s.lastSlot = room.slot
		if rec.roofFirst then s.roofFirst = true end
		sendProfile(m)
		requestSave(m)
		local glyphs = string.rep("\u{2605}", stars) .. string.rep("\u{2606}", 3 - stars)
		Notice:FireClient(m, { kind = "escape", stars = stars, slot = room.slot, text = "ESCAPED " .. glyphs,
			reasons = starReasons(r, party), roof = room.slot == 15 })
	end
	sendRoomState(party)
end

local function wrongTry(party: any, st: any, plr: Player, what: string)
	markTeam(party, "wrong")
	st.wrongs += 1
	local lock = Lab.lockoutFor(Config, st.wrongs)
	st.lockUntil = now() + lock
	toast(plr, string.format("%s Locked for %d s after a wrong try.", what, lock))
	if st.kind == "door" then renderDoorBoard(party) end
	sendRoomState(party)
	local room = party.room
	task.delay(lock + 0.05, function()
		if party.room == room and not party.dead then
			if st.kind == "door" then renderDoorBoard(party) end
			sendRoomState(party)
		end
	end)
end

local function isInt(x: any, lo: number, hi: number): boolean
	return type(x) == "number" and x == x and math.floor(x) == x and x >= lo and x <= hi
end

local function takeToken(s: Session): boolean
	local t = now()
	s.tokens = math.min(Config.Act.Burst, s.tokens + (t - s.tokenAt) * Config.Act.RatePerSecond)
	s.tokenAt = t
	if s.tokens >= 1 then
		s.tokens -= 1
		return true
	end
	return false
end

local function doHint(plr: Player, s: Session, party: any, st: any)
	if st.solved then return toast(plr, "Already solved.") end
	local capSpec = if st.kind == "door" then { kind = "door", L = st.L }
		elseif st.kind == "shelf" then { kind = "shelf", N = st.N } else { kind = "lamp", k = st.k }
	local used = st.hints[plr] or 0
	if used >= Lab.hintCap(capSpec) then return toast(plr, "No more hints here. The last step is yours.") end
	local wait = s.hintAt + Config.Hints.CooldownSeconds - now()
	if wait > 0 then return toast(plr, string.format("Next hint in %d s.", math.ceil(wait))) end
	local told = st.told[plr] or {}
	st.told[plr] = told
	local text, lamp = nil, nil
	if st.kind == "door" then
		local pos, digit = CodeLock.hint(st.secret, told, party.room.rand)
		if pos then
			told[pos] = true
			text = Text.doorHint(pos, digit)
		end
	elseif st.kind == "shelf" then
		local color, slot = Shelf.hint(st.secret, told, party.room.rand)
		if color then
			told[color] = true
			text = Text.shelfHint(color, slot)
		end
	else
		lamp = Lamps.hint(st.grid, st.n, party.room.rand)
		if lamp then text = Text.lampHint(lamp, st.n) end
	end
	if text == nil then return toast(plr, "No more hints here. The last step is yours.") end
	st.hints[plr] = used + 1
	s.hintAt = now()
	markTeam(party, "hinted")
	-- the hint itself to the taker only, never into the world (CLAUDE.md trap 3); the lost star to everyone
	HintEv:FireClient(plr, { station = st.id, text = text, lamp = lamp })
	sendRoomState(party)
end

local function stationWorldPos(party: any, id: string): Vector3
	local p = W.Stations[id]
	return party.zone.origin + Vector3.new(p[1], p[2], p[3])
end

local function withinReach(plr: Player, pos: Vector3): boolean
	local root = rootOf(plr)
	return root ~= nil and (root.Position - pos).Magnitude <= Config.Act.StationReach
end

Act.OnServerEvent:Connect(function(plr: Player, stationId: any, verb: any, a: any, b: any)
	-- exact types first: anything the honest HUD cannot produce is dropped without a word (DESIGN.md §16.2)
	if type(stationId) ~= "string" or type(verb) ~= "string" then return end
	if #stationId > Config.Act.MaxIdLength or #verb > 8 then return end
	local s = sessions[plr]
	if s == nil then return end
	if not takeToken(s) then
		if now() - s.rateToastAt >= Config.Act.RateToastSeconds then
			s.rateToastAt = now()
			toast(plr, "Slow down.")
		end
		return
	end
	local party = s.party
	local room = party and party.room
	if room == nil then return end
	local st = room.byId[stationId]
	if st == nil then return end
	-- argument shapes per verb
	if verb == "hint" then
		if a ~= nil or b ~= nil then return end
	elseif st.kind == "lamp" then
		if verb ~= "press" or not isInt(a, 1, st.n * st.n) or b ~= nil then return end
	elseif st.kind == "shelf" then
		if verb == "swap" then
			if not isInt(a, 1, st.N) or not isInt(b, 1, st.N) or a == b then return end
		elseif verb == "test" then
			if a ~= nil or b ~= nil then return end
		else
			return
		end
	else
		if verb ~= "enter" or b ~= nil or not CodeLock.valid(a, st.L, st.alphabet) then return end
	end
	-- then the state, and every refusal an honest player can hit is answered in words
	if party.state ~= "playing" then
		return toast(plr, if party.state == "escaped" then "This room is solved. Step into the exit lift." else "Wait for the lift doors.")
	end
	if not withinReach(plr, stationWorldPos(party, stationId)) then return toast(plr, "Walk up to the station.") end
	if verb == "hint" then return doHint(plr, s, party, st) end
	if st.solved then return toast(plr, "Already solved.") end
	local left = st.lockUntil - now()
	if left > 0 then return toast(plr, string.format("Locked for %d s after a wrong try.", math.ceil(left))) end
	if st.kind == "lamp" then
		Lamps.press(st.grid, st.n, a)
		renderStation(party, st)
		if Lamps.allLit(st.grid) then
			solveFeeder(party, st, plr)
		else
			sendRoomState(party)
		end
	elseif st.kind == "shelf" then
		if verb == "swap" then
			Shelf.swap(st.order, a, b)
			renderStation(party, st)
			sendRoomState(party)
		elseif Shelf.same(st.order, st.secret) then
			solveFeeder(party, st, plr)
		else
			wrongTry(party, st, plr, "Not that order.")
		end
	else
		if not allLit(room) then
			return toast(plr, string.format(Text.DoorDark, darkNames(room)))
		end
		if CodeLock.equal(a, st.secret) then
			solveDoor(party, plr)
		else
			st.lastWrong = table.clone(a)
			wrongTry(party, st, plr, "Not that code.")
		end
	end
end)

--============================================================================ Hello: resend this player's state

Hello.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	local t = now()
	s.helloTokens = math.min(4, (s.helloTokens or 4) + (t - (s.helloAt or t)) / 5)
	s.helloAt = t
	if s.helloTokens < 1 then return end
	s.helloTokens -= 1
	if s.loaded then sendProfile(plr) end
	local party = s.party
	if party and party.room and party.parts and not party.dead then
		RoomStateEv:FireClient(plr, RoomView.build(party.room, party.results[plr] or {}, now()))
	else
		RoomStateEv:FireClient(plr, RoomView.outside(s.location or "atrium"))
	end
end)

--============================================================================ prompts

-- A station prompt opens that station's overlay for the player who pressed it (after the server's
-- own checks). The Open payload names the station and nothing else.
local function onStationPrompt(plr: Player, pp: ProximityPrompt)
	local s = sessions[plr]
	if s == nil then return end
	local party = s.party
	if party == nil or party.parts == nil or not pp:IsDescendantOf(party.parts.folder) then
		return toast(plr, "That station belongs to another room.")
	end
	local host = pp.Parent :: BasePart
	local id = if host.Name == "Door" then "Door" else string.match(host.Name, "^Station_(%a)$")
	if id == nil or party.room.byId[id] == nil then return end
	if not withinReach(plr, stationWorldPos(party, id)) then return toast(plr, "Walk up to the station.") end
	OpenEv:FireClient(plr, { station = id })
end

local function onNext(plr: Player)
	local s = sessions[plr]
	local party = s and s.party
	if party ~= nil and party.state == "riding" then return toast(plr, "The lift is already on its way.") end
	if party == nil or party.state ~= "escaped" then return toast(plr, "The door is still shut.") end
	for _, m in party.members do
		if not inExitCab(party, m) then return toast(plr, "Waiting for " .. m.Name .. ".") end
	end
	if party.room.slot == 15 then
		party.state = "riding"
		party.parts.nextPrompt.Enabled = false
		noticeParty(party, { kind = "ride", text = "Going up to the Roof..." })
		task.delay(Config.Lift.RideSeconds, function()
			if not party.dead then sendToRoof(party) end
		end)
		return
	end
	local slot
	if #party.members == 2 then
		local a, b = sessions[party.members[1]], sessions[party.members[2]]
		slot = Lab.continuePair(a.profile.best, a.lastSlot, b.profile.best, b.lastSlot)
	else
		slot = continueFor(sessions[party.members[1]])
	end
	ride(party, slot)
end

local function onPromptTriggered(pp: ProximityPrompt, plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	if pp.Name == "OpenPrompt" then return onStationPrompt(plr, pp) end
	if pp.Name == "NextPrompt" then return onNext(plr) end
	if pp.Name == "LeavePrompt" then
		if s.party and s.party.parts and pp:IsDescendantOf(s.party.parts.folder) then
			return leaveToAtrium(plr, true)
		end
		return toast(plr, "That lift belongs to another room.")
	end
end

-- Room prompts are wired as rooms are built; one listener per prompt, found by name.
zonesFolder.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") then
		(d :: ProximityPrompt).Triggered:Connect(function(plr) onPromptTriggered(d :: ProximityPrompt, plr) end)
	end
end)

--============================================================================ the Atrium's lifts, door and board

local pairLeaving = false
local pairLeavingWith: { Player } = {}

world.goPrompt.Triggered:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	if s.party or s.riding then return toast(plr, "You are already on your way.") end
	local root = rootOf(plr)
	local mine = root and padOf(root)
	if mine == nil then return toast(plr, "Stand on a pad in the PAIR LIFT, then press GO.") end
	if pairLeaving then
		-- "full" is for a third player; one of the departing pair is told it is leaving (review-1)
		if table.find(pairLeavingWith, plr) then return toast(plr, "The Pair Lift leaves in a moment.") end
		return toast(plr, "The Pair Lift is full.")
	end
	if not s.loaded then return toast(plr, "Loading your stars...") end
	s.goAt = now()
	-- The partner is a player on the OTHER pad who pressed GO inside the window, the earliest first. Anyone
	-- else standing on a pad is ignored (review-1 A1: one idle player on either pad used to make every GO
	-- answer "The Pair Lift is full.", switching the only way to play together off for the whole server).
	local other, otherAt, samePad = nil, math.huge, false
	for p, os_ in sessions do
		if p ~= plr and not os_.party and not os_.riding and os_.goAt ~= nil and now() - os_.goAt <= Config.Lift.PairGoWindowSeconds then
			local r = rootOf(p)
			local pad = r and padOf(r)
			if pad == mine then
				samePad = true
			elseif pad ~= nil and os_.goAt < otherAt then
				other, otherAt = p, os_.goAt
			end
		end
	end
	if other == nil then
		if samePad then return toast(plr, Config.Lift.OtherPadText) end
		return toast(plr, "The Pair Lift needs two players who both press GO. Waiting for a partner...")
	end
	pairLeaving = true
	local pairMembers = { other :: Player, plr }
	pairLeavingWith = pairMembers
	for _, m in pairMembers do
		Notice:FireClient(m, { kind = "ride", text = string.format("Pair Lift leaves in %d s. Step off to cancel.",
			Config.Lift.PairCountdownSeconds) })
	end
	task.delay(Config.Lift.PairCountdownSeconds, function()
		pairLeaving = false
		pairLeavingWith = {}
		local ok = true
		for _, m in pairMembers do
			local ms = sessions[m]
			local r = rootOf(m)
			if ms == nil or ms.party or r == nil or padOf(r) == nil then ok = false end
		end
		for _, m in pairMembers do
			if sessions[m] then sessions[m].goAt = nil end
		end
		if not ok then
			for _, m in pairMembers do
				if sessions[m] then toast(m, "The Pair Lift was cancelled: someone stepped off.") end
			end
			return
		end
		local party = newParty(pairMembers)
		if party == nil then return end
		local a, b = sessions[pairMembers[1]], sessions[pairMembers[2]]
		ride(party, Lab.continuePair(a.profile.best, a.lastSlot, b.profile.best, b.lastSlot), "pair")
	end)
end)

world.roofPrompt.Triggered:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	if s.profile.escapedAt <= 0 then
		return toast(plr, string.format("Roof access is for Lab escapees. You are at room %d of 15.", math.min(15, Lab.frontier(s.profile.best))))
	end
	if teleport(plr, Vector3.new(0, W.RoofY + 3.5, 8), Vector3.new(0, 0, -1)) then
		arriveRoof(plr, s, false)
	end
end)

world.backPrompt.Triggered:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	if teleport(plr, arrivalPos(), Vector3.new(0, 0, -1)) then
		s.location = "atrium"
		RoomStateEv:FireClient(plr, RoomView.outside("atrium"))
	end
end)

world.boardPrompt.Triggered:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	s.boardMode = if s.boardMode == "friends" then "public" else "friends"
	if s.boardMode == "public" then
		BoardEv:FireClient(plr, { mode = "public" })
		return
	end
	if s.friendsBusy then
		-- the fetch already running sends its progress and its result; a press starts nothing
		if s.friendsGot then
			sendFriends(plr, friendsViewOf(plr, s, s.friendsGot), true)
		else
			BoardEv:FireClient(plr, { mode = "friends", rows = {}, loading = true, message = "Loading friends..." })
		end
		return
	end
	if s.friendsFailedAt and now() - s.friendsFailedAt < Config.Board.FriendsFailSeconds then
		BoardEv:FireClient(plr, { mode = "friends", rows = {}, message = Config.Board.Text.FriendsFailed })
		return
	end
	BoardEv:FireClient(plr, { mode = "friends", rows = {}, loading = true, message = "Loading friends..." })
	task.spawn(fetchFriends, plr)
end)

--============================================================================ the Solo Lift: stand inside for BoardSeconds

local function startSolo(plr: Player)
	local s = sessions[plr]
	local party = newParty({ plr })
	if party == nil then return end
	ride(party, continueFor(s), "solo")
end

task.spawn(function()
	local dt = Config.Lift.PollSeconds
	while true do
		task.wait(dt)
		local inCab = {}
		for plr, s in sessions do
			local root = rootOf(plr)
			if root and not s.party and not s.riding and inSoloCab(root) then
				table.insert(inCab, plr)
			else
				s.soloFor = 0
				s.soloWarned = false
			end
		end
		for _, plr in inCab do
			local s = sessions[plr]
			s.soloFor += dt
			-- everyone who has stood in the cab for BoardSeconds rides, each to a room of their own: a second
			-- player in the cab can never hold anyone back (review 2026-10-01: "One at a time" let a griefer
			-- standing in the cab block every solo ride)
			if s.soloFor >= Config.Lift.BoardSeconds - 1e-6 then
				if not s.loaded then
					if not s.soloWarned then
						s.soloWarned = true
						toast(plr, "Loading your stars...")
					end
				else
					s.soloFor = 0
					if #inCab > 1 then toast(plr, Config.Lift.SoloTogetherText) end
					startSolo(plr)
				end
			end
		end
	end
end)

--============================================================================ players

local function onCharacterAdded(plr: Player, char: Model)
	-- no CFrame writes and no yields here: the engine places the character on AtriumSpawn (SPAWN-ORDER.md)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = W.WalkSpeed end
	local s = sessions[plr]
	if s and (s.party or s.riding) then
		leaveToAtrium(plr, false)
		toast(plr, "You left the room. Your stars are safe.")
	elseif s then
		s.location = "atrium"
		RoomStateEv:FireClient(plr, RoomView.outside("atrium"))
	end
end

local function onPlayerAdded(plr: Player)
	plr.RespawnLocation = world.spawn -- FIRST, before any yield (SPAWN-ORDER.md §3)
	if sessions[plr] then return end
	local s = {
		token = HttpService:GenerateGUID(false),
		profile = Profile.new(),
		loaded = false,
		canSave = false,
		state = "loading",
		lastWrite = -math.huge,
		queued = false,
		party = nil,
		riding = false,
		soloFor = 0,
		soloWarned = false,
		tokens = Config.Act.Burst,
		tokenAt = now(),
		rateToastAt = -math.huge,
		hintAt = -math.huge,
		goAt = nil,
		boardMode = "public",
		location = "atrium",
		lastSlot = nil,
	}
	sessions[plr] = s
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local stars = Instance.new("IntValue")
	stars.Name = "Stars"
	stars.Value = 0
	stars.Parent = ls
	ls.Parent = plr
	plr.CharacterAdded:Connect(function(char) onCharacterAdded(plr, char) end)
	if plr.Character then onCharacterAdded(plr, plr.Character) end
	task.spawn(loadProfile, plr)
end

local function onPlayerRemoving(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	s.gone = true -- a load still in flight must not take the lock (review-1 A3)
	if s.party then removeMember(s.party, plr) end
	saveNow(plr, true)
	sessions[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

pcall(function()
	game:BindToClose(function()
		for plr in sessions do
			saveNow(plr, true)
		end
	end)
end)

-- autosave (renews the lock), retries a load blocked by another server's lock
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for plr, s in sessions do
			if s.state == "locked" or s.state == "retry" then
				task.spawn(loadProfile, plr)
			elseif s.canSave then
				task.spawn(saveNow, plr)
			end
		end
	end
end)

-- the public board: at boot, then every PublicCacheSeconds (a cache of ~60 s, the owner's standard)
task.spawn(function()
	while true do
		refreshPublic()
		task.wait(Config.Board.PublicCacheSeconds)
	end
end)
