-- FIND IT! CHAPTERS: the authoritative server (ServerScriptService). DESIGN.md is the spec; CLAUDE.md the traps.
--
-- What lives here, and why it is safe (DESIGN.md §3.3, §12-14):
--   * THE SECRET (which prop hides each item) is drawn by Attempt.hide AFTER the room's payload has been built
--     and sent, from server entropy (a Random made at start XOR a fresh Random per draw; no seed exists). It
--     lives in this script's memory; one JSON copy sits in ServerStorage.FindIt.Attempts for headless checks
--     and the filming rig ("ServerStorage, not the zone", anomaly-observatory/CLAUDE.md). It is never an
--     attribute, an Instance under Workspace / ReplicatedStorage / a player, or part of a remote payload,
--     except the one prop a hit or a hint names;
--   * no remote carries a find, a time, a count or a credit. Search(id) is looked up in the sender's own room,
--     reach is checked against the server's view of the root, one search is in flight at a time, and hit and
--     miss are both answered after exactly Search.Seconds;
--   * the clock is the sum of Heartbeat dt while the attempt is live and not paused (never os.clock);
--   * spawn (robloxemu/SPAWN-ORDER.md): HubSpawn is the ONE enabled SpawnLocation, built before PlayerAdded is
--     connected; PlayerAdded points RespawnLocation at it first thing; CharacterAdded writes no CFrame;
--   * saving: pcall everything, a per-session token on every write, a clear is ONE atomic UpdateAsync (stars,
--     first clear, the Daily credit by the day the attempt started, Cases Solved), the board is written only
--     after that write landed, and nothing about an attempt is ever saved.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local Dressing = require(ReplicatedStorage:WaitForChild("Dressing"))
local Attempt = require(ReplicatedStorage:WaitForChild("Attempt"))
local Ledger = require(ReplicatedStorage:WaitForChild("Ledger"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local Bands = require(ReplicatedStorage:WaitForChild("Bands"))
local Clue = require(ReplicatedStorage:WaitForChild("Clue"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))

-- First thing: the hub's light (Config.Env.Hub = Fx.Presets.Agency), so the client's band glide starts from it.
Fx.applyLighting(Fx.Presets.Agency)

local W = Config.World
local R = Config.Room
local T = Config.Text

Players.RespawnTime = W.RespawnTime
Players.CharacterAutoLoads = true

local serverNow = 0 -- the sum of Heartbeat dt: the attempt clocks and the Resume delay run on it
-- Wall time for DataStore pacing and remote rate limits (tick() is virtual in the emulator). A loop that waits on
-- the Heartbeat sum would spin inside one emulator frame, so nothing below ever waits on serverNow.
local function wallNow(): number
	return tick()
end

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

--============================================================================ entropy [DESIGN §3.3]
-- fork-tower's mintSecret construction: a Random made once at start XOR a fresh Random per draw, mapped to [0, 1)
-- through all 32 bits (the high bits decide every range: never `state % span`).
local life = Random.new()
local function draw(): number
	local v = bit32.bxor(life:NextInteger(0, 4294967295), Random.new():NextInteger(0, 4294967295))
	return v / 4294967296
end

--============================================================================ building helpers
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
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

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Text = text
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color or Color3.fromRGB(60, 44, 30)
	l.Font = Enum.Font.GothamBold
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

--============================================================================ remotes [DESIGN §12.4]
local remotes = Instance.new("Folder")
remotes.Name = "FindItRemotes"
local function remote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
-- server -> client
local RoomEv = remote("Room")
local StateEv = remote("State")
local ResultEv = remote("Result")
local HintEv = remote("Hint")
local ToastEv = remote("Toast")
local NoticeEv = remote("Notice")
local BoardEv = remote("Board")
local ProfileEv = remote("Profile")
-- client -> server
local OpenEv = remote("Open")
local OpenDailyEv = remote("OpenDaily")
local SearchEv = remote("Search")
local AskHintEv = remote("AskHint")
local PauseEv = remote("Pause")
local ResumeEv = remote("Resume")
local NextEv = remote("Next")
local RetryEv = remote("Retry")
local HubEv = remote("Hub")
local HelloEv = remote("Hello")
remotes.Parent = ReplicatedStorage

local function toast(plr: Player, text: string, kind: string?)
	ToastEv:FireClient(plr, { text = text, kind = kind or "info" })
end

--============================================================================ the hub [DESIGN §6]
local world = Instance.new("Folder")
world.Name = "FindItWorld"
world.Parent = workspace

local hub = Instance.new("Folder")
hub.Name = "Hub"
hub.Parent = world

local HUB = W.HubSize
part(hub, "HubFloor", Vector3.new(HUB, 1, HUB), CFrame.new(0, -0.5, 0), Color3.fromRGB(176, 132, 92), Enum.Material.WoodPlanks)
-- the walls stand over the tallest hub part plus a jump (REVIEW-1 B9: at 6 studs a 7.2-stud jump left the hub)
local WALL_H = W.HubWallHeight
for i, spec in { { 0, HUB / 2, HUB, 1 }, { 0, -HUB / 2, HUB, 1 }, { HUB / 2, 0, 1, HUB }, { -HUB / 2, 0, 1, HUB } } do
	part(hub, "HubWall" .. i, Vector3.new(spec[3], WALL_H, spec[4]), CFrame.new(spec[1], WALL_H / 2, spec[2]), Color3.fromRGB(226, 208, 176), Enum.Material.SmoothPlastic)
end
-- a few agency touches (decor: never a prop silhouette)
part(hub, "AgencyRug", Vector3.new(14, 0.1, 10), CFrame.new(0, 0.05, 12), Color3.fromRGB(150, 96, 120), Enum.Material.Fabric, false)
part(hub, "AgencyDesk", Vector3.new(8, 3, 3), CFrame.new(0, 1.5, -20), Color3.fromRGB(120, 84, 54), Enum.Material.Wood)
part(hub, "AgencySign", Vector3.new(20, 4, 0.5), CFrame.new(0, 8, -HUB / 2 + 0.8), Color3.fromRGB(64, 46, 32), Enum.Material.Wood, false)
do
	local sign = hub:FindFirstChild("AgencySign") :: Part
	local g = Instance.new("SurfaceGui")
	g.Name = "Face"
	g.Face = Enum.NormalId.Back
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 30
	g.Parent = sign
	label(g, "Title", "THE FINDER'S AGENCY", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), Color3.fromRGB(255, 236, 196))
end

-- HubSpawn: the ONE enabled SpawnLocation, built before PlayerAdded is connected [DESIGN §13]
local hubSpawn = Instance.new("SpawnLocation")
hubSpawn.Name = "HubSpawn"
hubSpawn.Anchored = true
hubSpawn.Size = Vector3.new(6, 1, 6)
-- an unrotated CFrame faces -Z: toward the Case Book 10 studs ahead (REVIEW-1 B2: a pi turn faced the back wall)
hubSpawn.CFrame = CFrame.new(W.HubSpawn[1], W.HubSpawn[2], W.HubSpawn[3])
hubSpawn.Color = Color3.fromRGB(214, 190, 150)
hubSpawn.Material = Enum.Material.Wood
hubSpawn.Enabled = true
hubSpawn.Neutral = true
hubSpawn.Duration = 0
hubSpawn.Parent = hub

-- the Case Book lectern, 10 studs ahead of the spawn
local lectern = part(hub, "Lectern", Vector3.new(2.4, 3.6, 2), CFrame.new(W.Lectern[1], 1.8, W.Lectern[3]), Color3.fromRGB(110, 76, 48), Enum.Material.Wood)
local caseBook = part(hub, "CaseBook", Vector3.new(2.6, 0.5, 2), CFrame.new(W.Lectern[1], 3.85, W.Lectern[3]) * CFrame.Angles(math.rad(-15), 0, 0),
	Color3.fromRGB(140, 60, 70), Enum.Material.Fabric)
Fx.sparkle(caseBook, Color3.fromRGB(255, 240, 200))
local lecternPrompt = prompt(caseBook, "OpenCaseBook", "Open", "Case Book", W.LecternPromptDistance)

-- the Daily Case door
-- turned +90 degrees: its Front face (the sign) looks along -X, into the hub (REVIEW-1 B7: -90 faced the east wall)
local dailyDoor = part(hub, "DailyDoor", Vector3.new(6, 9, 1), CFrame.new(W.DailyDoor[1], 4.5, W.DailyDoor[3]) * CFrame.Angles(0, math.rad(90), 0),
	Color3.fromRGB(70, 92, 120), Enum.Material.Wood)
local dailyPrompt = prompt(dailyDoor, "OpenDaily", "Open", "Daily Case", W.DailyPromptDistance)
local dailySign
do
	local g = Instance.new("SurfaceGui")
	g.Name = "Sign"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 30
	g.Parent = dailyDoor
	label(g, "Title", "DAILY CASE", UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.18), Color3.fromRGB(255, 244, 220))
	dailySign = label(g, "Case", "", UDim2.fromScale(0.05, 0.26), UDim2.fromScale(0.9, 0.14), Color3.fromRGB(255, 244, 220))
	label(g, "Rule", "Opens after Chapter 3", UDim2.fromScale(0.05, 0.42), UDim2.fromScale(0.9, 0.1), Color3.fromRGB(230, 222, 200))
end

-- the Cases Solved board, facing the spawn
local boardPart = part(hub, "CasesBoard", Vector3.new(12, 9, 0.6), CFrame.lookAt(Vector3.new(W.Board[1], 5.5, W.Board[3]),
	Vector3.new(W.HubSpawn[1], 5.5, W.HubSpawn[3])), Color3.fromRGB(56, 44, 34), Enum.Material.Wood)
local boardPrompt = prompt(boardPart, "BoardToggle", "Switch view", "Cases Solved board", W.BoardPromptDistance)
local boardFace
do
	local g = Instance.new("SurfaceGui")
	g.Name = "PublicFace"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Parent = boardPart
	boardFace = g
	label(g, "Title", Config.Board.Text.Title .. "  \u{00B7}  PUBLIC", UDim2.fromScale(0.04, 0.02), UDim2.fromScale(0.92, 0.1), Color3.fromRGB(255, 226, 150))
	for i = 1, Config.Board.PublicRows do
		label(g, "Row_" .. i, "", UDim2.fromScale(0.06, 0.13 + (i - 1) * 0.074), UDim2.fromScale(0.88, 0.066), Color3.fromRGB(250, 244, 230))
	end
	label(g, "Note", "", UDim2.fromScale(0.06, 0.88), UDim2.fromScale(0.88, 0.1), Color3.fromRGB(230, 220, 200))
end

--============================================================================ the lanes [DESIGN §6]
local lanesFolder = Instance.new("Folder")
lanesFolder.Name = "Lanes"
lanesFolder.Parent = world
local lanes = {}
for i = 1, W.Lanes do
	local x = W.LaneX0 + W.LaneDX * (i - 1)
	local origin = Vector3.new(x, 0, W.LaneZ - R.ShellD / 2) -- the door mat's centre: room-local (0, 0, 0)
	local f = Instance.new("Folder")
	f.Name = "Lane_" .. i
	f.Parent = lanesFolder
	local wall, H = R.Wall, R.Height
	local cx, cz = x, W.LaneZ
	local shellColor = Color3.fromRGB(196, 182, 160)
	part(f, "Floor", Vector3.new(R.ShellW + 2 * wall, 1, R.ShellD + 2 * wall), CFrame.new(cx, -0.5, cz), Color3.fromRGB(140, 110, 80), Enum.Material.WoodPlanks)
	part(f, "Ceiling", Vector3.new(R.ShellW + 2 * wall, 1, R.ShellD + 2 * wall), CFrame.new(cx, H + 0.5, cz), shellColor)
	part(f, "WallN", Vector3.new(R.ShellW + 2 * wall, H, wall), CFrame.new(cx, H / 2, cz + R.ShellD / 2 + wall / 2), shellColor)
	part(f, "WallS", Vector3.new(R.ShellW + 2 * wall, H, wall), CFrame.new(cx, H / 2, cz - R.ShellD / 2 - wall / 2), shellColor)
	part(f, "WallE", Vector3.new(wall, H, R.ShellD), CFrame.new(cx + R.ShellW / 2 + wall / 2, H / 2, cz), shellColor)
	part(f, "WallW", Vector3.new(wall, H, R.ShellD), CFrame.new(cx - R.ShellW / 2 - wall / 2, H / 2, cz), shellColor)
	part(f, "DoorMat", Vector3.new(6, 0.1, R.MatDepth), CFrame.new(origin.X, 0.05, origin.Z + R.MatDepth / 2), Color3.fromRGB(120, 70, 60), Enum.Material.Fabric, false)
	part(f, "DoorFrame", Vector3.new(7, 9, 0.4), CFrame.new(origin.X, 4.5, origin.Z + 0.3), Color3.fromRGB(96, 68, 46), Enum.Material.Wood, false)
	lanes[i] = { index = i, origin = origin, folder = f, owner = nil :: Player? }
end
local freeLanes = {}
for i = W.Lanes, 1, -1 do table.insert(freeLanes, i) end
local function takeLane(): number?
	if #freeLanes == 0 then return nil end
	table.sort(freeLanes, function(a, b) return a > b end)
	return table.remove(freeLanes)
end
local function giveLane(i: number?)
	if i and not table.find(freeLanes, i) then table.insert(freeLanes, i) end
end

--============================================================================ the server-only rig [DESIGN §12.2]
local rig = Instance.new("Folder")
rig.Name = "FindIt"
rig.Parent = ServerStorage
local rigAttempts = Instance.new("Folder")
rigAttempts.Name = "Attempts"
rigAttempts.Parent = rig

--============================================================================ sessions
type Session = any
local sessions: { [Player]: Session } = {}

local function rootOf(plr: Player): BasePart?
	local c = plr.Character
	if c == nil or c.Parent == nil then return nil end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then return nil end
	return c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function limited(s: Session, kind: string): boolean
	local gap = Config.Limits[kind] or 0
	local last = s.limits[kind]
	local t = wallNow()
	if last ~= nil and t - last < gap then return true end
	s.limits[kind] = t
	return false
end

-- A refusal is answered in words, but a flood of them is not (REVIEW-1 A6): each player has a small bucket of
-- answers (RefusalBurst, refilled at RefusalsPerSecond of wall time). An honest HUD never empties it; a script
-- firing 1000 refused calls a frame gets a handful of answers and costs the server nothing more.
local function refuse(plr: Player, s: Session, text: string, kind: string?)
	local t = wallNow()
	local cap = Config.Limits.RefusalBurst
	local tokens = math.min(cap, (s.refuseTokens or cap) + (t - (s.refuseAt or t)) * Config.Limits.RefusalsPerSecond)
	s.refuseAt = t
	if tokens < 1 then
		s.refuseTokens = tokens
		return
	end
	s.refuseTokens = tokens - 1
	toast(plr, text, kind)
end

local function isInt(x: any, lo: number, hi: number): boolean
	return type(x) == "number" and x == x and x >= lo and x <= hi and x % 1 == 0
end

--============================================================================ profile, save, board [DESIGN §12.1]
local profileStore, boardStore = nil, nil
do
	local ok, s = pcall(function() return DataStoreService:GetDataStore(Config.Save.Store) end)
	if ok then profileStore = s end
	local ok2, b = pcall(function() return DataStoreService:GetOrderedDataStore(Config.Board.Store) end)
	if ok2 then boardStore = b end
end

local function today(): number
	return Ledger.dayIndex(os.time())
end

-- (solved, solvedAt) as other players may see them: the stored record's, or this session's in a no-store server
local function publicCount(s: Session): (number, number)
	if s.state == "nostore" then return s.profile.solved, s.profile.solvedAt end
	local st = s.stored
	if st == nil then return 0, 0 end
	return st.solved, st.solvedAt
end

local function sendProfile(plr: Player)
	local s = sessions[plr]
	if not s then return end
	local p = s.profile
	local stars = {}
	for k, v in p.book.stars do stars[k] = { f = v.f, w = v.w, s = v.s } end
	local day = today()
	ProfileEv:FireClient(plr, {
		cleared = p.book.cleared, stars = stars, solved = p.solved, totalStars = Ledger.totalStars(p),
		continue = Ledger.continueChapter(p, Config), dailyOpen = Ledger.dailyOpen(p, Config),
		dailySolvedToday = p.daily.lastDay == day, dailySolved = p.daily.solved, streak = p.daily.streak,
		bestStreak = p.daily.bestStreak, title = Ledger.title(p.daily.solved, Config), caseNumber = Ledger.caseNumber(day, Config),
		bookSolved = p.bookSolvedAt ~= nil, canSave = s.canSave, loaded = s.loaded, state = s.state,
		goldBook = Ledger.goldBook(p, Config), -- REVIEW-1 round 2 D6: the long-term goal, on show in the Case Book
	})
	-- what other players see (leaderstats, their friends board) is what the STORE holds: a clear still queued
	-- counts on this player's own HUD only (REVIEW-1: a read-only session credits nothing in public)
	local ls = plr:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Solved")
	if v then (v :: IntValue).Value = (publicCount(s)) end
end

local function nameTag(plr: Player)
	local s = sessions[plr]
	local char = plr.Character
	if s == nil or char == nil or s.profile.bookSolvedAt == nil then return end
	if char:FindFirstChild("FindItTag", true) then return end
	local host = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if host == nil then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "FindItTag"
	bb.Size = UDim2.fromOffset(160, 28)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = false
	bb.Parent = host
	label(bb, "Tag", "\u{1F50D} Book One Solved", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), c3(Config.Reserved.Gold))
end

--============================================================================ the clear queue [REVIEW-1 A1-A3]
-- Every clear is queued in s.pending ({ kind, chapter | day, stars, at }) until a write that CARRIES it lands. Every
-- write this server makes to the profile (the clear's own, the autosave, the load, the release on leave or
-- shutdown) folds the whole queue into the record inside its one atomic UpdateAsync (Ledger.applyClear is
-- idempotent: a chapter counts once, a Daily once per UTC day, stars only rise). So a clear inside the write gap
-- survives a leave or a shutdown, one failed write is retried by the next one, and clears made while the load is
-- retrying are merged when it lands. s.profile is the stored record plus the queue (what the HUD shows and what
-- opens the next chapter); s.stored is what the store holds (what the board may rank).

-- Inside a transform: apply the queue to `data` (a fresh sanitized record). -> { [clear] = info }
local function fold(data: any, s: Session): any
	local infos = {}
	for _, c in s.pending do infos[c] = Ledger.applyClear(data, c, c.at, Config) end
	data.seenIntro = data.seenIntro or s.profile.seenIntro == true
	return infos
end

-- Every write's transform takes a number when it runs (each run: a transform may run more than once). The store
-- holds what the transform that ran LAST wrote, so a write's answer is applied only if its number is the highest
-- applied yet (REVIEW-1 round 2 C4: an autosave answering 9 s late put the session back a chapter, and Next said
-- "Clear Chapter 6 first" for ~12 s).
local function nextSeq(s: Session): number
	s.writeSeq = (s.writeSeq or 0) + 1
	return s.writeSeq
end

-- After a write carrying `infos` landed with `data`: drop what it carried, mirror the store, re-apply the rest.
-- A write older than the last one applied changes nothing: what it carried, the newer write carried too.
local function settle(plr: Player, s: Session, data: any, infos: any, seq: number?)
	if seq ~= nil then
		if seq < (s.appliedSeq or 0) then return end
		s.appliedSeq = seq
	end
	local left, told = {}, false
	for _, c in s.pending do
		local info = infos[c]
		if info then
			c.info = info
			if c.tell then told = true end
		else
			table.insert(left, c)
		end
	end
	s.pending = left
	s.stored = { solved = data.solved, solvedAt = data.solvedAt, boarded = data.boarded or 0 }
	local p = Ledger.sanitize(data, os.time())
	for _, c in left do Ledger.applyClear(p, c, c.at, Config) end
	s.profile = p
	if told and sessions[plr] == s and not s.releasing then
		toast(plr, Config.Save.Text.Saved)
		sendProfile(plr)
	end
end

-- Write the board only after the profile write carrying the new count has landed (s.stored); keep max(old, new).
local function writeBoard(plr: Player, s: Session)
	local p = s.stored
	if boardStore == nil or not s.canSave or p == nil or p.solved <= math.max(p.boarded or 0, s.boardedPending or 0) then return end
	local value = Board.encode(p.solved, p.solvedAt, Config.Board)
	local okB = pcall(function()
		boardStore:UpdateAsync(Board.key(plr.UserId), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	if okB then
		s.boardedPending = p.solved
	end
end

-- Wait until MinWriteGap after this key's last write (writes to one key stay >= 6 s apart).
local function waitWriteGap(s: Session)
	local gap = Config.Save.MinWriteGap - (wallNow() - s.lastWrite)
	while gap > 0 do
		task.wait(math.max(gap, 0.05))
		gap = Config.Save.MinWriteGap - (wallNow() - s.lastWrite)
	end
end

-- The lock refresh (autosave) and the release: data is never rewritten from memory. The stored record gets the
-- clear queue folded in (normally empty: a clear writes itself), seenIntro and `boarded` (what the board holds).
-- A release that fails is retried (it may be the last write that can carry a queued clear).
local function saveLock(plr: Player, release: boolean?): boolean
	local s = sessions[plr]
	if s == nil or not s.canSave or profileStore == nil or s.released then return false end
	if s.releasing and not release then return false end
	if release then s.releasing = true end
	local key = "u_" .. tostring(plr.UserId)
	local tries = if release then Config.Save.ReleaseTries else 1
	for try = 1, tries do
		local stamp = os.time()
		local landed, data, infos, seq = false, nil, nil, nil
		local boarded = s.boardedPending or (s.stored and s.stored.boarded) or 0
		s.lastWrite = wallNow()
		local ok = pcall(function()
			profileStore:UpdateAsync(key, function(rec)
				landed = false
				if s.releasing and not release then return nil end
				if type(rec) ~= "table" or type(rec.lock) ~= "table" or rec.lock.session ~= s.token then return nil end
				data = Ledger.sanitize(rec.data, stamp)
				infos = fold(data, s)
				data.boarded = math.max(data.boarded or 0, math.min(boarded, data.solved))
				landed = true
				seq = nextSeq(s)
				local lock = if release then { session = "", ["until"] = 0 } else { session = s.token, ["until"] = stamp + Config.Save.SessionLockSeconds }
				return { data = data, lock = lock }
			end)
		end)
		if ok and landed then
			settle(plr, s, data, infos, seq)
			if release then s.released = true end
			return true
		end
		if ok and not landed then
			if not release then
				s.canSave = false
				s.state = "locked"
				if sessions[plr] == s then
					toast(plr, Config.Save.Text.Locked)
					sendProfile(plr)
				end
			end
			return false
		end
		if try < tries then task.wait(Config.Save.ReleaseRetrySeconds) end
	end
	return false
end

-- THE CLEAR: one atomic UpdateAsync. The first clear, the Daily's one credit per UTC day (by the attempt's
-- START day), the stars and Cases Solved are decided inside the transform against the stored record, and only
-- while this session holds the lock. The clear is already in s.pending (handleEnd queued it): this write folds
-- the queue. Returns the clear's info once a write carrying it landed, else nil (it stays queued: the next write
-- that lands carries it, whether the autosave, the load or the release).
local function commitClear(plr: Player, s: Session, clear: any): any
	if s.state == "nostore" then
		-- no DataStore at all (Studio without API access): progress lives for this session only, nothing ranks
		return Ledger.applyClear(s.profile, clear, clear.at, Config)
	end
	if not s.canSave or profileStore == nil then return nil end
	waitWriteGap(s)
	if clear.info then return clear.info end -- another write carried it meanwhile
	if sessions[plr] ~= s or s.releasing then return nil end -- the release carries it
	local key = "u_" .. tostring(plr.UserId)
	local stamp = os.time()
	local infos, data, landed, seq = nil, nil, false, nil
	s.lastWrite = wallNow()
	local ok = pcall(function()
		profileStore:UpdateAsync(key, function(rec)
			landed = false
			if s.releasing then return nil end
			if type(rec) ~= "table" or type(rec.lock) ~= "table" or rec.lock.session ~= s.token then return nil end
			data = Ledger.sanitize(rec.data, stamp)
			infos = fold(data, s)
			landed = true
			seq = nextSeq(s)
			return { data = data, lock = { session = s.token, ["until"] = stamp + Config.Save.SessionLockSeconds } }
		end)
	end)
	if ok and landed and data then
		settle(plr, s, data, infos, seq)
		s.lastWrite = wallNow() -- the next autosave is pushed back
		writeBoard(plr, s)
		return clear.info
	end
	if ok and not landed and not s.releasing then
		s.canSave = false
		s.state = "locked"
		toast(plr, Config.Save.Text.Locked)
	end
	return nil
end

-- A session that never held the lock (its load is retrying, or another server held it) leaves with clears still
-- queued: one last write takes the record ONLY if no other live session holds it, folds the queue and leaves the
-- lock free. Also used when the player left while their load was in flight.
local function mergeGone(key: string, s: Session)
	if profileStore == nil then return end
	for try = 1, Config.Save.ReleaseTries do
		local stamp = os.time()
		local ok = pcall(function()
			(profileStore :: any):UpdateAsync(key, function(rec)
				rec = if type(rec) == "table" then rec else {}
				local lock = rec.lock
				local mine = type(lock) == "table" and lock.session == s.token
				if type(lock) == "table" and not mine and lock.session ~= "" and (tonumber(lock["until"]) or 0) > stamp then return nil end
				local data = Ledger.sanitize(rec.data, stamp)
				fold(data, s)
				return { data = data, lock = { session = "", ["until"] = 0 } }
			end)
		end)
		if ok then return end
		if try < Config.Save.ReleaseTries then task.wait(Config.Save.ReleaseRetrySeconds) end
	end
end

local function loadProfile(plr: Player)
	local s = sessions[plr]
	if s == nil or s.loading then return end
	if profileStore == nil then
		s.loaded = true
		s.state = "nostore"
		-- Studio staging ONLY (filming later bands): never in a live server, never on a profile that can save
		local staged = Config.Studio.Cleared
		if type(staged) == "number" and RunService:IsStudio() and not s.canSave then
			s.profile.book.cleared = math.clamp(math.floor(staged), 0, #Config.Chapters)
			s.profile.solved = s.profile.book.cleared
		end
		toast(plr, Config.Save.Text.NoStore)
		sendProfile(plr)
		return
	end
	s.loading = true
	local key = "u_" .. tostring(plr.UserId)
	local stamp = os.time()
	local result, data, infos, seq = nil, nil, nil, nil
	local ok = pcall(function()
		profileStore:UpdateAsync(key, function(rec)
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
			data = Ledger.sanitize(rec.data, stamp)
			-- clears made while this load was retrying (or locked) are merged here [REVIEW-1 A3]
			infos = fold(data, s)
			seq = nextSeq(s)
			return { data = data, lock = { session = s.token, ["until"] = stamp + Config.Save.SessionLockSeconds } }
		end)
	end)
	s.loading = false
	if sessions[plr] ~= s or s.gone then
		if ok and result == "ok" then mergeGone(key, s) end
		return
	end
	-- REVIEW-1 round 2 C3: a first load that failed or found another server's lock (a hop: the old server is still
	-- releasing) is tried again within seconds, a few times, before the 20 s autosave tick takes over
	local function quickRetry()
		if (s.quick or 0) >= Config.Save.QuickRetries then return end
		s.quick = (s.quick or 0) + 1
		task.delay(Config.Save.QuickRetrySeconds, function()
			if sessions[plr] == s and (s.state == "retry" or s.state == "locked") then loadProfile(plr) end
		end)
	end
	if not ok then
		s.loaded = true
		s.state = "retry"
		if not s.retryToasted then
			s.retryToasted = true
			toast(plr, Config.Save.Text.LoadRetry)
		end
		quickRetry()
	elseif result == "locked" then
		s.loaded = true
		s.state = "locked"
		if not s.lockToasted then
			s.lockToasted = true
			toast(plr, Config.Save.Text.Locked)
		end
		quickRetry()
	else
		s.loaded = true
		s.canSave = true
		s.state = "ready"
		s.lastWrite = wallNow()
		settle(plr, s, data, infos, seq)
		if s.retryToasted or s.lockToasted then toast(plr, Config.Save.Text.Loaded) end
		-- a count the board never got (a failed board write in an earlier session) is written now
		task.spawn(writeBoard, plr, s)
		nameTag(plr)
	end
	sendProfile(plr)
end

--============================================================================ the public board [DESIGN §11]
local nameCache = Board.newCache(Config.Board.NameCacheSeconds)
local nameCount = 0
local function nameOf(userId: number): string
	local cached = Board.cacheGet(nameCache, userId, wallNow())
	if cached then return cached end
	local p = Players:GetPlayerByUserId(userId)
	if p then return p.DisplayName ~= nil and p.DisplayName ~= "" and p.DisplayName or p.Name end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	local name = if ok and type(n) == "string" then n else ("Player " .. tostring(userId))
	if nameCount >= Config.Board.NameCacheMax then
		nameCache = Board.newCache(Config.Board.NameCacheSeconds)
		nameCount = 0
	end
	nameCount += 1
	Board.cachePut(nameCache, userId, name, wallNow())
	return name
end

local function renderPublic(rows: { any }, note: string?)
	for i = 1, Config.Board.PublicRows do
		local l = boardFace:FindFirstChild("Row_" .. i) :: TextLabel
		local r = rows[i]
		l.Text = if r then string.format("%d.  %s   %d", r.rank, r.name, r.solved) else ""
	end
	(boardFace:FindFirstChild("Note") :: TextLabel).Text = note or ""
end

local lastPublicAt = -math.huge
local function refreshPublic(force: boolean?)
	-- every 60 s; a clear forces one, at most every 10 s (GetSortedAsync's budget is 5 + 2 per player a minute)
	local age = wallNow() - lastPublicAt
	if age < (if force then 10 else Config.Board.PublicCacheSeconds) then return end
	lastPublicAt = wallNow()
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
	for _, r in view.rows do table.insert(rows, { rank = r.rank, name = nameOf(r.userId), solved = r.solved }) end
	renderPublic(rows, view.note)
end

--============================================================================ friends (on demand, paced) [DESIGN §11]
-- escape-room-lab's reviewed reader: single-flight per player, one friend-score read at a time per server, the
-- budget checked before each read (Board.readStep with a reserve), lists and scores cached across players.
local friendLists = Board.newCache(Config.Board.FriendListCacheSeconds)
local friendScores = Board.newCache(Config.Board.FriendScoreCacheSeconds)
local readerBusy = false

local function myValue(s: Session): number
	local solved, at = publicCount(s)
	return Board.encode(solved, at, Config.Board)
end

local function getAsyncBudget(): number?
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return if ok and type(n) == "number" then n else nil
end

local function readFriendScore(id: number): number?
	while readerBusy do task.wait(0.05) end
	if Board.cacheHas(friendScores, id, wallNow()) then return Board.cacheGet(friendScores, id, wallNow()) end
	readerBusy = true
	local waited, value = 0, nil
	while true do
		local step = Board.readStep(getAsyncBudget(), Config.Board.GetAsyncReserve, waited, Config.Board.FriendReadMaxWaitSeconds)
		if step == "read" then
			local ok, v = pcall(function() return (boardStore :: any):GetAsync(Board.key(id)) end)
			value = if ok and type(v) == "number" then v else 0
			Board.cachePut(friendScores, id, value, wallNow())
			break
		elseif step == "wait" then
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
	for _, r in view.rows do table.insert(rows, { rank = r.rank, name = nameOf(r.userId), solved = r.solved, you = r.you }) end
	BoardEv:FireClient(plr, { mode = "friends", rows = rows, message = view.note, loading = loading == true })
end

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
	local ids = Board.cacheGet(friendLists, plr.UserId, wallNow())
	if ids == nil then
		local ok, got = pcall(function()
			local out = {}
			local pages = (Players :: any):GetFriendsAsync(plr.UserId)
			while true do
				for _, item in pages:GetCurrentPage() do
					local id = type(item) == "table" and tonumber(item.Id) or nil
					if id then
						table.insert(out, id)
						-- the page already names the friend: cache it (memory only), saving a GetNameFromUserIdAsync
						local nm = item.DisplayName or item.Username
						if type(nm) == "string" and nm ~= "" then
							Board.cachePut(nameCache, id, nm, wallNow())
						end
					end
					if #out >= Config.Board.FriendCap then return out end
				end
				if pages.IsFinished then break end
				pages:AdvanceToNextPageAsync()
			end
			return out
		end)
		if not ok or type(got) ~= "table" then
			s.friendsBusy = false
			if sessions[plr] == s and s.boardMode == "friends" then
				BoardEv:FireClient(plr, { mode = "friends", rows = {}, message = Config.Board.Text.FriendsFailed })
			end
			return
		end
		ids = got
		Board.cachePut(friendLists, plr.UserId, ids, wallNow())
	end
	s.friendsGot = { values = {}, status = { friendCount = #ids, checked = 0, failed = false, partial = false } }
	local got = s.friendsGot
	show(true)
	for i, id in ids do
		if sessions[plr] ~= s then return end
		local other = Players:GetPlayerByUserId(id)
		local os_ = other and sessions[other]
		if os_ and os_.loaded then
			got.values[id] = myValue(os_)
		elseif Board.cacheHas(friendScores, id, wallNow()) then
			got.values[id] = Board.cacheGet(friendScores, id, wallNow())
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

--============================================================================ attempts
local function laneOf(s: Session): any
	return s.attempt and lanes[s.attempt.lane]
end

local function worldPos(att: any, p: any): Vector3
	local o = lanes[att.lane].origin
	return Vector3.new(o.X + p.x, o.Y + p.y, o.Z + p.z)
end

local function writeRig(plr: Player, att: any?)
	local key = tostring(plr.UserId)
	local v = rigAttempts:FindFirstChild(key) :: StringValue?
	if att == nil then
		if v then v:Destroy() end
		return
	end
	if v == nil then
		v = Instance.new("StringValue")
		v.Name = key
		v.Parent = rigAttempts
	end
	local snap = Attempt.snapshot(att.a)
	snap.lane = att.lane
	local ok, json = pcall(function() return HttpService:JSONEncode(snap) end)
	if ok then (v :: StringValue).Value = json end
end

local function statePayload(s: Session): any
	local att = s.attempt
	if att == nil then return { where = "hub" } end
	local a = att.a
	local pub = Attempt.public(a, serverNow)
	pub.where = "room"
	pub.kind = att.kind
	pub.chapter = att.chapter
	pub.day = att.day
	pub.case = if att.day then Ledger.caseNumber(att.day, Config) else nil
	pub.band = att.band
	pub.progress = att.progress
	pub.n = a.n
	pub.items = att.items
	pub.intro = if a.state == "intro" then a.introLeft else nil
	pub.introText = att.introText
	pub.origin = { lanes[att.lane].origin.X, lanes[att.lane].origin.Y, lanes[att.lane].origin.Z }
	pub.result = att.result
	pub.attemptId = att.id
	pub.W = att.spec.W
	pub.D = att.spec.D
	return pub
end

local function sendState(plr: Player)
	local s = sessions[plr]
	if s then
		StateEv:FireClient(plr, statePayload(s))
		s.lastStateAt = serverNow
	end
end

local function teleportTo(plr: Player, pos: Vector3, look: Vector3): boolean
	local char = plr.Character
	local root = rootOf(plr)
	if char == nil or root == nil then return false end
	local cf = CFrame.lookAt(pos, pos + look)
	local ok = pcall(function() (char :: Model):PivotTo(cf) end)
	if not ok then root.CFrame = cf end
	pcall(function() root.AssemblyLinearVelocity = Vector3.zero end)
	return true
end

local function endAttempt(plr: Player, s: Session, move: boolean)
	local att = s.attempt
	if att then
		Attempt.abandon(att.a)
		giveLane(att.lane)
		lanes[att.lane].owner = nil
		s.attempt = nil
		s.resumeAt = nil
		writeRig(plr, nil)
	end
	if move then
		teleportTo(plr, Vector3.new(W.HubSpawn[1], 3.5, W.HubSpawn[3]), Vector3.new(0, 0, -1))
	end
	sendState(plr)
end

local nextAttemptId = 0

-- items for an attempt: drawn independently of the room (cosmetic), never repeating
local function drawItems(n: number, bandId: string, rand: () -> number): { string }
	local pool = table.clone(Config.Items.Shared)
	for _, it in Config.Items.Band[bandId] or {} do table.insert(pool, it) end
	for i = #pool, 2, -1 do
		local j = math.floor(rand() * i) + 1
		if j > i then j = i end
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, n do out[i] = pool[i] end
	return out
end

local function drawFor(s: Session, salt: number): () -> number
	-- Studio shot room ONLY: deterministic dressing and secret, never in a live server [DESIGN §21.2]
	local seed = Config.Studio.ShotSeed
	if seed ~= nil and RunService:IsStudio() and not s.canSave then
		local g = Rng.new(seed + salt)
		return function() return g:next() end
	end
	return draw
end

local function startAttempt(plr: Player, kind: string, which: number, retry: boolean?)
	local s = sessions[plr]
	if s == nil then return end
	if not s.loaded then
		toast(plr, "Opening your Case Book...")
		return
	end
	local p = s.profile
	if kind == "book" then
		local ok, need = Ledger.canOpen(p, which)
		if not ok then
			toast(plr, string.format(T.Locked, need or 1))
			return
		end
	else
		if not Ledger.dailyOpen(p, Config) then
			toast(plr, T.DailyLocked)
			return
		end
		if p.daily.lastDay >= which then toast(plr, T.DailyDone) end
	end
	local root = rootOf(plr)
	if root == nil then
		toast(plr, "Wait for your character to load")
		return
	end
	-- leave a room you are in (the same lane is taken again at once)
	local laneIndex = nil
	if s.attempt then
		laneIndex = s.attempt.lane
		Attempt.abandon(s.attempt.a)
		s.attempt = nil
		s.resumeAt = nil
	else
		laneIndex = takeLane()
	end
	if laneIndex == nil then
		toast(plr, "Every room is busy. Try again in a moment.")
		return
	end
	lanes[laneIndex].owner = plr
	local spec = Dressing.spec(kind, which, Config)
	local bandIndex = if kind == "book" then Bands.forChapter(which, Config) else Ledger.dailyBand(which, Config)
	local band = Config.Env.Bands[bandIndex]
	local rand = drawFor(s, if kind == "book" then which else 100)
	-- §3.3 steps 1-4: clues, dressing, positions and ids dealt after a shuffle, then THE PAYLOAD, sent now
	local room = Dressing.build(spec, rand, Config)
	local items = drawItems(spec.n, band.id, rand)
	local payload = Dressing.payload(room, items, bandIndex, Config)
	payload.origin = { lanes[laneIndex].origin.X, lanes[laneIndex].origin.Y, lanes[laneIndex].origin.Z }
	nextAttemptId += 1
	payload.attemptId = nextAttemptId
	RoomEv:FireClient(plr, payload)
	-- §3.3 step 5: the secret, drawn only now, kept in memory
	local first = not (s.seenChapter[kind .. which] == true)
	s.seenChapter[kind .. which] = true
	local intro = if retry or not first then Config.Cards.IntroRetry else Config.Cards.IntroFirst
	local a = Attempt.new(room, spec, Config, { intro = intro })
	Attempt.hide(a, rand)
	s.attempt = {
		id = nextAttemptId, a = a, kind = kind, chapter = if kind == "book" then which else nil, day = if kind == "daily" then which else nil,
		startDay = if kind == "daily" then which else today(), lane = laneIndex, band = bandIndex,
		progress = if kind == "book" then which else Bands.progressForDaily(which, Config), items = items, spec = spec,
		introText = if retry or not first then string.format(T.IntroRetry, spec.n) else string.format(T.Intro, spec.n),
		rand = rand,
	}
	writeRig(plr, s.attempt)
	-- the move: onto the lane's door mat, facing into the room (long after the character is parented: not the
	-- spawn race)
	local o = lanes[laneIndex].origin
	teleportTo(plr, o + Vector3.new(0, 3, 1.5), Vector3.new(0, 0, 1))
	if not p.seenIntro then p.seenIntro = true end
	sendState(plr)
end

-- Next on a result card: the next chapter after a first clear of a book chapter, else the hub
local function doNext(plr: Player, s: Session, att: any)
	if att.kind == "book" and att.a.reason == "found" and att.chapter < #Config.Chapters then
		startAttempt(plr, "book", att.chapter + 1)
	else
		endAttempt(plr, s, true)
	end
end

local function handleEnd(plr: Player, s: Session, reason: string)
	local att = s.attempt
	if att == nil then return end
	local a = att.a
	local stars = Attempt.stars(a)
	local res = { reason = reason, stars = stars, saving = reason == "found", foundCount = Attempt.foundCount(a), n = a.n }
	if reason == "found" and att.kind == "book" then
		res.progress = Bands.progressAfterClear(att.chapter, Config)
		att.progress = res.progress
	end
	att.result = res
	sendState(plr)
	if reason ~= "found" then return end
	local clear = if att.kind == "book" then { kind = "book", chapter = att.chapter, stars = stars, at = os.time() }
		else { kind = "daily", day = att.startDay, stars = stars, at = os.time() }
	-- queued FIRST: from here every write that lands carries it, even if this player leaves now [REVIEW-1 A1]
	if s.state ~= "nostore" then table.insert(s.pending, clear) end
	task.spawn(function()
		local info = commitClear(plr, s, clear)
		if sessions[plr] ~= s then return end
		res.saving = false
		if info == nil and clear.info then info = clear.info end
		if info == nil then
			-- not in the store yet: it stays queued, counts in this session now, and the card says which wait it is in
			info = Ledger.applyClear(s.profile, clear, clear.at, Config)
			clear.tell = true
			res.pendingSave = true
			if s.state == "locked" then
				res.cantSave = true
				res.note = Config.Save.Text.CantSave
			elseif s.state == "retry" or s.state == "loading" then
				res.note = Config.Save.Text.LoadPending
			else
				res.note = Config.Save.Text.SaveLater
			end
		end
		res.first = info.first
		res.credited = info.credited
		res.solved = info.solvedAfter
		res.bookSolved = info.bookSolved
		if info.goldBook then res.goldBook = true end -- REVIEW-1 round 2 D6: the 45th star
		if s.state == "nostore" then res.note = Config.Save.Text.NoStore end
		if info.bookSolved then
			local name = plr.DisplayName ~= nil and plr.DisplayName ~= "" and plr.DisplayName or plr.Name
			NoticeEv:FireAllClients({ kind = "brag", name = name, text = string.format(T.BookSolvedNotice, name) })
			nameTag(plr)
		end
		if s.attempt == att then sendState(plr) end
		sendProfile(plr)
		refreshPublic(true)
		-- REVIEW-1 round 2 D4: a Next tapped while this clear was saving opens the next chapter now (unless the player
		-- went to the hub or retried meanwhile)
		if att.nextQueued and s.attempt == att and sessions[plr] == s then
			att.nextQueued = nil
			doNext(plr, s, att)
		end
	end)
end

local function resultName(prop: any): string
	return Clue.name(prop, Config)
end

--============================================================================ the frame: clocks and answers
RunService.Heartbeat:Connect(function(dt: number)
	if type(dt) ~= "number" or dt ~= dt or dt < 0 then return end
	dt = math.min(dt, 1)
	serverNow += dt
	for plr, s in sessions do
		local att = s.attempt
		if att == nil then continue end
		local a = att.a
		-- REVIEW-1 round 2 C2: a break past Pause.MaxBreakSeconds (summed over the attempt) closes the room
		if a.state == "paused" and #Attempt.closeBreak(a, serverNow) > 0 then
			s.resumeAt = nil
			writeRig(plr, att)
			handleEnd(plr, s, "break")
			continue
		end
		-- a queued Resume lands no sooner than ResumeMinSeconds after the Pause
		if s.resumeAt and serverNow >= s.resumeAt and a.state == "paused" then
			s.resumeAt = nil
			local res, counts = Attempt.resume(a, serverNow)
			if res == "redress" and counts then
				local room = Dressing.redress(a.room, counts, att.rand, Config)
				local found = {}
				for i = 1, a.n do found[i] = a.found[i] == true end
				local payload = Dressing.payload(room, att.items, att.band, Config, found)
				payload.origin = { lanes[att.lane].origin.X, lanes[att.lane].origin.Y, lanes[att.lane].origin.Z }
				payload.attemptId = att.id
				payload.redress = true
				RoomEv:FireClient(plr, payload)
				Attempt.applyRedress(a, room, att.rand)
				writeRig(plr, att)
				if a.hintProp then HintEv:FireClient(plr, { item = a.hint, id = a.hintProp }) end
				sendState(plr)
			end
		end
		local events = Attempt.tick(a, dt)
		for _, e in events do
			if e.type == "result" then
				local prop = a.byId[e.id]
				ResultEv:FireClient(plr, { id = e.id, hit = e.hit, item = e.item, offClue = e.offClue, attemptId = att.id })
				if e.offClue and not e.hit and prop then
					toast(plr, string.format(T.NoFit, resultName(prop)), "nofit")
				end
				writeRig(plr, att)
				sendState(plr)
			elseif e.type == "end" then
				writeRig(plr, att)
				handleEnd(plr, s, e.reason)
			elseif e.type == "live" or e.type == "paused" then
				sendState(plr)
			end
		end
		if a.state == "live" and serverNow - (s.lastStateAt or 0) >= 1 then sendState(plr) end
	end
end)

--============================================================================ remotes: what a player may ask
OpenEv.OnServerEvent:Connect(function(plr: Player, chapter: any)
	local s = sessions[plr]
	if s == nil or not isInt(chapter, 1, #Config.Chapters) then return end
	if s.attempt and s.attempt.a.state ~= "done" then
		refuse(plr, s, T.FinishFirst)
		return
	end
	if limited(s, "Open") then
		refuse(plr, s, T.Busy)
		return
	end
	startAttempt(plr, "book", chapter)
end)

OpenDailyEv.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	if s.attempt and s.attempt.a.state ~= "done" then
		refuse(plr, s, T.FinishFirst)
		return
	end
	if limited(s, "Open") then
		refuse(plr, s, T.Busy)
		return
	end
	startAttempt(plr, "daily", today())
end)

local SEARCH_WORDS = {
	intro = T.GetReady, pending = T.OneAtATime, paused = T.OnBreak, time = T.TimeUp, looks = T.NoLooks,
	done = "This room is done", already = T.Already, unknown = T.DecorTap, ["break"] = T.BreakClosed,
}

SearchEv.OnServerEvent:Connect(function(plr: Player, id: any)
	local s = sessions[plr]
	if s == nil or not isInt(id, 1, 1e9) then return end
	local att = s.attempt
	if att == nil then
		refuse(plr, s, T.NotInRoom)
		return
	end
	local a = att.a
	local prop = a.byId[id]
	-- reach: the server's own view of the root, with slack for a walking player's late position
	if prop and a.state == "live" and not a.pending and not a.searched[id] then
		local root = rootOf(plr)
		if root == nil then return end
		local wp = worldPos(att, prop)
		local dx, dz = root.Position.X - wp.X, root.Position.Z - wp.Z
		local reach = Config.Search.Reach + Config.Search.ReachSlack
		if dx * dx + dz * dz > reach * reach then
			refuse(plr, s, T.WalkCloser)
			return
		end
	end
	local ok, why = Attempt.search(a, id)
	if not ok then
		refuse(plr, s, SEARCH_WORDS[why or ""] or T.DecorTap, why)
		return
	end
	writeRig(plr, att)
	sendState(plr)
end)

local HINT_WORDS = { intro = T.GetReady, paused = T.OnBreak, used = T.HintUsed, pick = T.HintPick, found = T.HintFound, done = "This room is done" }
AskHintEv.OnServerEvent:Connect(function(plr: Player, item: any)
	local s = sessions[plr]
	if s == nil then return end
	if item ~= nil and type(item) ~= "number" then return end
	if limited(s, "Hint") then return end
	local att = s.attempt
	if att == nil then
		refuse(plr, s, T.NotInRoom)
		return
	end
	local id, why = Attempt.hint(att.a, item)
	if id == nil then
		refuse(plr, s, HINT_WORDS[why or ""] or T.HintPick, why)
		return
	end
	HintEv:FireClient(plr, { item = item, id = id, attemptId = att.id })
	writeRig(plr, att)
	sendState(plr)
end)

PauseEv.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or limited(s, "Pause") then return end
	local att = s.attempt
	if att == nil then return end
	local st = Attempt.pause(att.a, serverNow)
	if st == "intro" then refuse(plr, s, T.GetReady) end
	if st == "done" then refuse(plr, s, "This room is done") end
	if st == "soon" then refuse(plr, s, string.format(T.PauseSoon, math.max(1, math.ceil(Attempt.pauseIn(att.a))))) end
	sendState(plr)
end)

ResumeEv.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or limited(s, "Resume") then return end -- the honest HUD sends one; a repeat inside 0.25 s adds nothing
	local att = s.attempt
	if att == nil then return end
	local a = att.a
	if a.state ~= "paused" then
		if a.pauseQueued then Attempt.resume(a, serverNow) end
		sendState(plr)
		return
	end
	local due = (a.pausedAt or serverNow) + Config.Pause.ResumeMinSeconds
	if serverNow < due then toast(plr, T.Resuming) end
	s.resumeAt = math.max(due, serverNow)
end)

NextEv.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or limited(s, "Card") then return end
	local att = s.attempt
	if att == nil or att.a.state ~= "done" then return end
	if att.result and att.result.saving then
		-- REVIEW-1 round 2 D4: remembered, not refused: the next chapter opens the moment the save lands
		att.nextQueued = true
		toast(plr, T.NextAfterSave)
		return
	end
	doNext(plr, s, att)
end)

RetryEv.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or limited(s, "Card") then return end
	local att = s.attempt
	if att == nil or att.a.state ~= "done" then return end
	if att.kind == "book" then startAttempt(plr, "book", att.chapter :: number, true)
	else startAttempt(plr, "daily", today(), true) end
end)

-- Hub: from a result card, the paused card, or a live room's Leave button (REVIEW-1 round 2 D1: abandoning is always
-- allowed and earns nothing). Its own bucket, and a refusal has words (round 2 D4: sharing Next's bucket, a Hub tap
-- 0.4 s after a refused Next was dropped without a word).
HubEv.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	if limited(s, "Hub") then
		refuse(plr, s, T.Busy)
		return
	end
	endAttempt(plr, s, true)
end)

HelloEv.OnServerEvent:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or limited(s, "Hello") then return end
	sendProfile(plr)
	sendState(plr)
	local att = s.attempt
	if att and att.a.state ~= "done" then
		local found = {}
		for i = 1, att.a.n do found[i] = att.a.found[i] == true end
		local payload = Dressing.payload(att.a.room, att.items, att.band, Config, found)
		payload.origin = { lanes[att.lane].origin.X, lanes[att.lane].origin.Y, lanes[att.lane].origin.Z }
		payload.attemptId = att.id
		RoomEv:FireClient(plr, payload)
		if att.a.hintProp then HintEv:FireClient(plr, { item = att.a.hint, id = att.a.hintProp, attemptId = att.id }) end
	end
	BoardEv:FireClient(plr, { mode = s.boardMode })
end)

--============================================================================ prompts (server-side reach)
local function promptReach(plr: Player, host: BasePart, pp: ProximityPrompt): boolean
	local root = rootOf(plr)
	if root == nil then return false end
	return (root.Position - host.Position).Magnitude <= pp.MaxActivationDistance + 4
end

lecternPrompt.Triggered:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or not promptReach(plr, caseBook, lecternPrompt) then return end
	-- a first-timer goes straight into Chapter 1, but only once the profile LOADED (REVIEW-1 round 2 C3: a hopper whose
	-- load still waits on the old server's lock has an empty book in memory, and was thrown into Chapter 1)
	local opensRoom = (s.state == "ready" or s.state == "nostore") and s.profile.book.cleared == 0
	-- opening the menu is not an Open: it must not eat the Open the player taps in it a moment later (REVIEW-1 B1)
	if limited(s, if opensRoom then "Open" else "Book") then return end
	if not s.loaded then
		toast(plr, "Opening your Case Book...")
		return
	end
	if opensRoom then
		-- a first-time player goes straight into Chapter 1: the core action within about 5 s
		startAttempt(plr, "book", 1)
	else
		NoticeEv:FireClient(plr, { kind = "casebook" })
	end
end)

dailyPrompt.Triggered:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or not promptReach(plr, dailyDoor, dailyPrompt) then return end
	if limited(s, "Open") then
		refuse(plr, s, T.Busy)
		return
	end
	startAttempt(plr, "daily", today())
end)

boardPrompt.Triggered:Connect(function(plr: Player)
	local s = sessions[plr]
	if s == nil or not promptReach(plr, boardPart, boardPrompt) then return end
	s.boardMode = if s.boardMode == "friends" then "public" else "friends"
	if s.boardMode == "friends" then
		BoardEv:FireClient(plr, { mode = "friends", rows = {}, message = string.format(Config.Board.Text.FriendsChecking, 0, 0), loading = true })
		task.spawn(fetchFriends, plr)
	else
		BoardEv:FireClient(plr, { mode = "public" })
	end
end)

--============================================================================ players
local function onCharacterAdded(plr: Player, char: Model)
	-- never a CFrame write here (SPAWN-ORDER.md): the engine places the character on HubSpawn
	local s = sessions[plr]
	if s and s.attempt then
		-- a respawn while a room was open: that attempt is over (nothing of it was ever saved)
		endAttempt(plr, s, false)
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		pcall(function()
			hum.WalkSpeed = W.WalkSpeed
			hum.UseJumpPower = false
			hum.JumpHeight = W.JumpHeight
		end)
		hum.Died:Connect(function()
			local s2 = sessions[plr]
			if s2 and s2.attempt then endAttempt(plr, s2, false) end
		end)
	end
	task.defer(nameTag, plr)
end

local function onPlayerAdded(plr: Player)
	plr.RespawnLocation = hubSpawn -- first thing: the engine's own placement is then correct
	local s = {
		plr = plr, token = HttpService:GenerateGUID(false), profile = Ledger.new(os.time()), canSave = false, loaded = false,
		state = "loading", lastWrite = -math.huge, limits = {}, boardMode = "public", seenChapter = {},
		pending = {}, stored = nil,
	}
	sessions[plr] = s
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local solved = Instance.new("IntValue")
	solved.Name = "Solved"
	solved.Value = 0
	solved.Parent = ls
	ls.Parent = plr
	plr.CharacterAdded:Connect(function(char) onCharacterAdded(plr, char) end)
	if plr.Character then onCharacterAdded(plr, plr.Character) end
	task.spawn(loadProfile, plr)
end

local function onPlayerRemoving(plr: Player)
	local s = sessions[plr]
	if s == nil then return end
	s.gone = true
	local att = s.attempt
	if att then
		Attempt.abandon(att.a)
		giveLane(att.lane)
		lanes[att.lane].owner = nil
		s.attempt = nil
	end
	writeRig(plr, nil)
	if s.canSave then
		-- REVIEW-1 round 2 C1: a clear the release carried reaches the board too (the profile write landed first)
		if saveLock(plr, true) then writeBoard(plr, s) end
	elseif #s.pending > 0 and s.state ~= "nostore" then
		mergeGone("u_" .. tostring(plr.UserId), s) -- the load never landed: one last merge if the record is free
	end
	sessions[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do task.spawn(onPlayerAdded, plr) end

game:BindToClose(function()
	for plr, s in sessions do
		if s.canSave then
			local ok, landed = pcall(saveLock, plr, true)
			if ok and landed then pcall(writeBoard, plr, s) end -- REVIEW-1 round 2 C1
		elseif #s.pending > 0 and s.state ~= "nostore" then
			pcall(mergeGone, "u_" .. tostring(plr.UserId), s)
		end
	end
end)

--============================================================================ loops: autosave, board, the daily sign
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for plr, s in sessions do
			if s.state == "retry" or s.state == "locked" then
				task.spawn(loadProfile, plr)
			elseif s.canSave and wallNow() - s.lastWrite >= Config.Save.MinWriteGap then
				task.spawn(function()
					if saveLock(plr) then writeBoard(plr, s) end
				end)
			end
		end
	end
end)

task.spawn(function()
	while true do
		refreshPublic(false)
		dailySign.Text = string.format("Case #%d", Ledger.caseNumber(today(), Config))
		task.wait(5)
	end
end)
