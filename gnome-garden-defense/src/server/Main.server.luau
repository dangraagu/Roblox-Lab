-- GNOME GARDEN DEFENSE: the server. Authoritative. Lives in ServerScriptService.
--
-- Every player owns a garden bed in one of 8 fixed slots. A procedurally drawn path runs from the hedge gap to
-- the carrot patch; waves of bugs walk it; gnomes planted on the pads beside it stop them. The SIMULATION is
-- src/shared/Garden.luau, stepped here at a fixed 0.1 s for every garden; this file turns it into Parts,
-- attributes and remote traffic, keeps the save and the board, and checks every client request.
--
-- Deliberate, not accidental:
--  * Server-only state (each garden's bugs, gnomes, seeds, timers, its bed seed, the session token) lives in
--    Lua tables here, never in an Instance, an attribute or a payload. Checks read ServerStorage.GardenInfo
--    (anomaly-observatory: "ServerStorage, not the zone"). There is no hidden answer: the path, the next wave
--    and every bug's stats are shown on purpose.
--  * The client only ASKS (Plant, Upgrade, Sell, Ready, SetPaused, Restart, NextSeason). Each request is
--    type-checked, indexes only the caller's own garden, passes one shared token bucket, and every refusal is
--    told to the player (no silent no-ops). Any garden action resumes a paused garden FIRST.
--  * Spawn (robloxemu/SPAWN-ORDER.md): each slot has a real SpawnLocation; plr.RespawnLocation is set before
--    anything yields, and CharacterAdded never writes a CFrame, so there is no race to lose.
--  * GetDataStore THROWS in an unpublished place: everything DataStore is pcall'd and degrades to "not saved".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService") -- GenerateGUID only (session tokens); no HTTP

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Garden = require(ReplicatedStorage:WaitForChild("Garden"))
local PathGen = require(ReplicatedStorage:WaitForChild("PathGen"))
local Waves = require(ReplicatedStorage:WaitForChild("Waves"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local GardenArt = require(ReplicatedStorage:WaitForChild("GardenArt"))
local Wire = require(ReplicatedStorage:WaitForChild("Wire"))

local DEPS = { Waves = Waves, PathGen = PathGen }
local W = Config.World
local T = Config.Tile
local BED_W, BED_D = Config.GridW * T, Config.GridH * T -- 96 x 72 studs

-- Warm garden light until the client's season bands take over (docs/new-game-checklist.md §2).
Fx.applyLighting(Fx.Presets.Cozy)

--============================================================================== remotes

local remotes = Instance.new("Folder")
remotes.Name = "GardenRemotes"
remotes.Parent = ReplicatedStorage
local function mk(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local PlantEvent = mk("Plant")           -- client -> server: (padId, kind)
local UpgradeEvent = mk("Upgrade")       -- client -> server: (padId)
local SellEvent = mk("Sell")             -- client -> server: (padId)
local ReadyEvent = mk("Ready")           -- client -> server
local PauseEvent = mk("SetPaused")       -- client -> server: (paused)
local RestartEvent = mk("Restart")       -- client -> server: a lost attempt, again on a fresh bed
local NextSeasonEvent = mk("NextSeason") -- client -> server: a won chapter, on to the next
local HereEvent = mk("Here")             -- client -> server: the gardener's own input was seen (the AFK hold)
local TickEvent = mk("GardenTick")       -- server -> the garden's owner, 10 Hz while bugs are out
local ToastEvent = mk("Toast")           -- server -> one player: a short sentence
local FanfareEvent = mk("Fanfare")       -- server -> one player: { kind = "season"|"lost"|"clear", ... }
local BoardEvent = mk("Board")           -- server -> one player: their view of the board

local function toast(plr: Player, msg: string)
	ToastEvent:FireClient(plr, msg)
end

-- Gardeners never collide with each other (disaster-rounds' DRPlayers rule): nobody can shove a gardener off
-- their deck or fling them (REVIEW-2). robloxemu has no PhysicsService: pcall'd, and the feel of walking
-- through each other is on EYECANDY.md's needs-Studio list.
local PLAYER_GROUP = "GardenPlayers"
pcall(function()
	local PhysicsService = game:GetService("PhysicsService")
	PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
	PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, PLAYER_GROUP, false)
end)
local function intoGroup(d: Instance)
	if d:IsA("BasePart") then pcall(function() (d :: any).CollisionGroup = PLAYER_GROUP end) end
end
local function groupCharacter(char: Model)
	-- no CFrame is written and nothing yields (robloxemu/SPAWN-ORDER.md)
	for _, d in char:GetDescendants() do intoGroup(d) end
	char.DescendantAdded:Connect(intoGroup)
end

--============================================================================== data

local function tryStore(fn, what: string)
	if not Config.Save.Enabled then return nil end
	local ok, ds = pcall(fn)
	if ok then return ds end
	warn("[GnomeGarden] " .. what .. " datastore unavailable (" .. tostring(ds)
		.. ") - the game runs, progress will NOT be saved this session.")
	return nil
end
local store = tryStore(function() return DataStoreService:GetDataStore(Config.Save.Store) end, "profiles")
local orderedLB = tryStore(function() return DataStoreService:GetOrderedDataStore(Config.Save.Leaderboard) end, "leaderboard")
local dailyStore = tryStore(function() return DataStoreService:GetDataStore(Config.Save.Daily) end, "daily bed")

local profiles: { [Player]: any } = {}

local function defaultProfile()
	return {
		chapter = 1,       -- the highest chapter unlocked (1..5); the gnome kinds derive from it
		bestWave = 0,      -- the board metric: the highest wave survived, measured by this server
		bestAt = 0,        -- unix seconds when bestWave was first reached (the board's tie-break)
		published = 0,     -- the bestWave last written to the board
		tutorialDone = false,
		-- runtime only, never stored:
		loaded = false,    -- the real record has been read at least once
		canSave = false,   -- this session holds the record's lock (only then does it write)
		session = nil,     -- the token this session's lock wrote into the record
		saving = false,    -- a write is in flight: the next one waits for it (they land in the order asked)
		released = false,  -- the leave's write released the lock: nothing after it writes again
		leaving = false,   -- the player has left: retries stop, a lock taken late is given straight back
	}
end

local function key(uid: number): string
	return "u_" .. uid
end

local function newSessionToken(plr: Player): string
	local ok, guid = pcall(function() return HttpService:GenerateGUID(false) end)
	if ok and type(guid) == "string" and #guid > 0 then return guid end
	return string.format("%s-%d-%d", tostring(game.JobId), plr.UserId, math.floor(tick() * 1e6))
end

-- A stored profile, normalised (anything broken reads as a fresh value).
local function readStored(d: any): any?
	if type(d) ~= "table" then return nil end
	return {
		chapter = math.clamp(math.floor(tonumber(d.chapter) or 1), 1, #Config.Chapters),
		bestWave = math.max(0, math.floor(tonumber(d.bestWave) or 0)),
		bestAt = tonumber(d.bestAt) or 0,
		published = math.max(0, math.floor(tonumber(d.published) or 0)),
		tutorialDone = d.tutorialDone == true,
	}
end

-- What is stored and what this session played, together: the higher of each (a read-only session may have
-- played past the record, and the record may have moved on since an earlier read). At an equal best wave the
-- earlier time stands: the board's tie-break is who reached it first.
local function mergeStored(p: any, s: any?)
	if not s then return end
	p.chapter = math.max(p.chapter, s.chapter)
	if s.bestWave > p.bestWave then
		p.bestWave, p.bestAt = s.bestWave, s.bestAt
	elseif s.bestWave == p.bestWave and s.bestAt > 0 and (p.bestAt <= 0 or s.bestAt < p.bestAt) then
		p.bestAt = s.bestAt
	end
	p.published = math.max(p.published, s.published)
	p.tutorialDone = p.tutorialDone or s.tutorialDone
end

-- One try at the record (deep-vein's soft session lock): ALWAYS read it, and take the lock unless another
-- server holds it. Returns (read, acquired). A locked record is read without being written (the transform
-- returns nil). Nothing is written before the real record has been read: a failed read never saves defaults.
local function tryLoad(plr: Player, p: any): (boolean, boolean)
	if not store then return false, false end
	local token = newSessionToken(plr)
	local acquired, stored = false, nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			acquired, stored = false, nil -- UpdateAsync may run the transform again
			old = if type(old) == "table" then old else {}
			stored = readStored(old.data)
			local now = os.time()
			if (tonumber(old.lockUntil) or 0) > now and old.jobId ~= game.JobId then
				return nil
			end
			acquired = true
			old.jobId = game.JobId
			old.session = token
			old.lockUntil = now + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	if not ok then
		warn("[GnomeGarden] load failed for " .. plr.Name .. ": " .. tostring(err) .. " (retrying)")
		return false, false
	end
	mergeStored(p, stored)
	p.loaded = true
	if p.bestWave > 0 and p.bestAt <= 0 then p.bestAt = os.time() end
	if acquired then
		p.canSave = true
		p.session = token
	else
		warn("[GnomeGarden] " .. plr.Name .. " READ-ONLY for now (locked by another session); retrying.")
	end
	return true, acquired
end

-- Give back a lock this session took but will not use (the player left while it was being taken).
local function releaseLock(userId: number, session: string?)
	if not store or not session then return end
	pcall(function()
		store:UpdateAsync(key(userId), function(old)
			if type(old) ~= "table" or old.session ~= session or old.jobId ~= game.JobId then return nil end
			old.lockUntil = 0
			return old
		end)
	end)
end

-- The board's store: written only when the best wave passes the last one written, never lower than what is
-- stored (Board.keepHigher aborts the UpdateAsync otherwise). Called only after a profile write landed.
local function writeBoard(p: any, userId: number)
	if not orderedLB or p.bestWave <= (p.published or 0) then return end
	local wave = p.bestWave
	local value = Board.encode(wave, p.bestAt, Config.Board)
	local ok = pcall(function()
		orderedLB:UpdateAsync(key(userId), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	if ok then p.published = wave end
end

-- One write at a time per player, in the order asked: a season's win is saved on its own thread (REVIEW-1: on
-- the simulation thread it froze every garden for the DataStore round trips), so a leave can be asked while it
-- is in flight; the leave then waits for it, and once the leave has released the lock nothing writes again
-- (a late win save landing after the release re-locked the record for 45 s).
local function saveProfile(plr: Player, releaseLock: boolean): boolean
	local p = profiles[plr]
	if not p then return false end
	while p.saving do task.wait(0.05) end
	if not p.canSave or p.released or not store then return false end
	p.saving = true
	-- OWNERSHIP: the write lands only if the record still carries this session's token AND this server's jobId.
	local lost = false
	local ok = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			if old.session ~= p.session or old.jobId ~= game.JobId then
				lost = true
				return nil
			end
			lost = false
			old.data = {
				version = Config.Save.Version,
				chapter = p.chapter, bestWave = p.bestWave, bestAt = p.bestAt,
				published = p.published, tutorialDone = p.tutorialDone,
			}
			old.jobId = game.JobId
			old.lockUntil = if releaseLock then 0 else (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	if ok and lost then
		p.saving = false
		p.canSave = false
		p.session = nil
		warn("[GnomeGarden] " .. plr.Name .. ": another session has taken this profile; nothing here saves any more.")
		if plr.Parent ~= nil then toast(plr, "Your progress is saved by another server now, so nothing here saves any more. Rejoin to carry on.") end
		return false
	end
	if ok and releaseLock then p.released = true end
	if ok then pcall(writeBoard, p, plr.UserId) end
	p.saving = false
	return ok
end

-- The endless chapter's bed: one seed per UTC day, drawn by the first server to ask and kept in a DataStore
-- (UpdateAsync keeps the first writer's value). Not a salt in code: the repo is public.
local serverRng = Random.new()
-- `seed` is the day's bed as the store answered it (kept for the day). `fallback` is this server's own bed while
-- the store does not answer: kept for DailyFallbackSeconds only, then the store is asked again. Caching a
-- fallback for the whole day put every endless gardener on this server on a bed of their own for up to 24 h,
-- ranked on the same board as the shared one (REVIEW-1).
local daily = { day = -1, seed = 0, fallbackDay = -1, fallback = 0, fallbackUntil = -math.huge }
local function dailySeed(): number
	local day = math.floor(os.time() / 86400)
	if daily.day == day then return daily.seed end
	if not dailyStore then -- no DataStore at all (Studio without API access): this server's own bed for the day
		daily.day, daily.seed = day, serverRng:NextInteger(1, 2147483646)
		return daily.seed
	end
	if daily.fallbackDay == day and tick() < daily.fallbackUntil then return daily.fallback end
	-- ONE bed of this server's own per day: it is what the store gets if this server is the day's first writer,
	-- and what this server plays while the store is down. A fresh draw on every ask gave a new endless bed on
	-- every TRY AGAIN a minute apart during an outage, so a gardener could reroll until an easy one came up and
	-- post its wave on the shared board (REVIEW-2: 7 beds in 7 restarts)
	if daily.fallbackDay ~= day then
		daily.fallbackDay, daily.fallback, daily.fallbackUntil = day, serverRng:NextInteger(1, 2147483646), -math.huge
	end
	local candidate = daily.fallback
	for try = 1, Config.Save.DailyTries do
		local seed = nil
		local ok = pcall(function()
			dailyStore:UpdateAsync("d_" .. day, function(old)
				if type(old) == "number" then
					seed = old
					return nil -- keep the first writer's bed
				end
				seed = candidate
				return candidate
			end)
		end)
		if daily.day == day then return daily.seed end -- another join got the answer while this one waited
		if ok and type(seed) == "number" then
			daily.day, daily.seed = day, seed
			return seed
		end
		if try < Config.Save.DailyTries then task.wait(try) end
	end
	warn("[GnomeGarden] the day's bed could not be read; this server uses its own for " .. Config.Save.DailyFallbackSeconds .. " s.")
	daily.fallbackUntil = tick() + Config.Save.DailyFallbackSeconds
	return candidate
end

--============================================================================== slots and the world

local gardensFolder = Instance.new("Folder")
gardensFolder.Name = "Gardens"
gardensFolder.Parent = workspace

local boardsFolder = Instance.new("Folder")
boardsFolder.Name = "GardenBoards"
boardsFolder.Parent = workspace

-- server-only debug state for the headless checks: never under workspace, ReplicatedStorage or a player
local infoFolder = Instance.new("Folder")
infoFolder.Name = "GardenInfo"
infoFolder.Parent = ServerStorage

local slotOf: { [Player]: number } = {}
local usedSlots: { [number]: Player } = {}

-- The meadow: one ground part under every slot (three rows: the eight slots and a spare row for overflow) and
-- MeadowMargin past the outer hedges. Without it the hedge gap the bugs come through led into the void, and a
-- curious gardener fell out of the world (REVIEW-1). Its top is MeadowDrop under the lawns.
do
	local world = Instance.new("Folder")
	world.Name = "GardenWorld"
	world.Parent = workspace
	local rows = math.ceil(W.Slots / W.SlotColumns) + 1
	local slotW = BED_W + W.PatchLength + 2 * W.HedgeMargin
	local slotD = BED_D + W.DeckGap + W.DeckDepth + 2 * W.HedgeMargin
	local x0 = -W.HedgeMargin - W.MeadowMargin
	local x1 = (W.SlotColumns - 1) * W.SlotPitchX + slotW - W.HedgeMargin + W.MeadowMargin
	local z0 = -W.HedgeMargin - W.MeadowMargin
	local z1 = (rows - 1) * W.SlotPitchZ + slotD - W.HedgeMargin + W.MeadowMargin
	local meadow = Instance.new("Part")
	meadow.Name = "Meadow"
	meadow.Anchored = true
	meadow.CanCollide = true
	meadow.CanTouch = false
	meadow.CastShadow = false
	meadow.Material = Enum.Material.Grass
	meadow.Color = Color3.fromRGB(110, 160, 80)
	meadow.Size = Vector3.new(x1 - x0, 4, z1 - z0)
	meadow.CFrame = CFrame.new((x0 + x1) / 2, W.BedY - W.MeadowDrop - 2, (z0 + z1) / 2)
	meadow.Parent = world
end

local function claimSlot(plr: Player): number
	for i = 0, W.Slots - 1 do
		if usedSlots[i] == nil then
			usedSlots[i] = plr
			slotOf[plr] = i
			return i
		end
	end
	-- a 9th player on an 8-player server: never expected (MaxPlayers 8), handled by sharing the last slot's
	-- origin offset further out rather than overlapping a stranger's bed
	local i = W.Slots
	while usedSlots[i] ~= nil do i += 1 end
	usedSlots[i] = plr
	slotOf[plr] = i
	return i
end

-- The bed's corner (cell 0,0's outer corner, x east, z south) for a slot. Fixed and recycled: never marches out.
local function slotOrigin(i: number): Vector3
	local col = i % W.SlotColumns
	local row = math.floor(i / W.SlotColumns)
	return Vector3.new(col * W.SlotPitchX, W.BedY, row * W.SlotPitchZ)
end

local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.CanCollide = props.CanCollide ~= false
	p.CanTouch = false
	p.CastShadow = props.CastShadow == true
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Color = props.Color or Color3.fromRGB(120, 180, 90)
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Name = props.Name
	if props.Transparency then p.Transparency = props.Transparency end
	if props.Shape then (p :: any).Shape = props.Shape end
	p.Parent = props.Parent
	return p
end

-- what each player's garden is, server-side
type Run = {
	sim: any,
	seed: number,
	attempt: number,
	paused: boolean,
	digging: boolean,        -- a new bed is being drawn (the endless chapter's may wait on the DataStore)
	lastActivity: number,    -- the gardener's own last request or input (never a move of their character)
	lastHere: number,
	lastPauseAt: number,
	limiter: any,
	folder: Folder,
	bed: Folder?,
	origin: Vector3,
	padParts: { [number]: BasePart },
	gnomeModels: { [number]: Model },
	carrots: { BasePart },
	sign: TextLabel?,
	attrs: { [string]: any },
	info: Folder,
}
local runs: { [Player]: Run } = {}

local function setAttr(run: Run, name: string, value: any)
	if run.attrs[name] ~= value then
		run.attrs[name] = value
		run.folder:SetAttribute(name, value)
	end
end

-- The parts of a slot that never change: lawn, hedge (with a gap per bed), deck, spawn, carrot bed, sign.
local function buildSlot(plr: Player, slot: number): (Folder, SpawnLocation, Vector3)
	local o = slotOrigin(slot)
	local folder = Instance.new("Folder")
	folder.Name = "Garden_" .. slot
	folder:SetAttribute("Owner", plr.UserId)
	folder:SetAttribute("OwnerName", plr.Name)
	folder:SetAttribute("Slot", slot)
	folder:SetAttribute("OriginX", o.X)
	folder:SetAttribute("OriginY", o.Y)
	folder:SetAttribute("OriginZ", o.Z)
	local m = W.HedgeMargin
	local deckZ0 = BED_D + W.DeckGap
	local deckZ1 = deckZ0 + W.DeckDepth
	local x0, x1 = -m, BED_W + W.PatchLength + m
	local z0, z1 = -m, deckZ1 + m
	-- the lawn under everything
	part({ Name = "Lawn", Parent = folder, Size = Vector3.new(x1 - x0, 1, z1 - z0),
		CFrame = CFrame.new(o + Vector3.new((x0 + x1) / 2, -0.5, (z0 + z1) / 2)), Material = Enum.Material.Grass,
		Color = Color3.fromRGB(96, 168, 72) })
	-- hedge: north, east and south walls; the west wall is per bed (it has the gap the bugs come through)
	local H = W.HedgeHeight
	local hedgeColor = Color3.fromRGB(46, 110, 52)
	part({ Name = "Hedge_N", Parent = folder, Size = Vector3.new(x1 - x0, H, 3), CFrame = CFrame.new(o + Vector3.new((x0 + x1) / 2, H / 2, z0 - 1.5)),
		Material = Enum.Material.Grass, Color = hedgeColor })
	part({ Name = "Hedge_S", Parent = folder, Size = Vector3.new(x1 - x0, H, 3), CFrame = CFrame.new(o + Vector3.new((x0 + x1) / 2, H / 2, z1 + 1.5)),
		Material = Enum.Material.Grass, Color = hedgeColor })
	part({ Name = "Hedge_E", Parent = folder, Size = Vector3.new(3, H, z1 - z0 + 6), CFrame = CFrame.new(o + Vector3.new(x1 + 1.5, H / 2, (z0 + z1) / 2)),
		Material = Enum.Material.Grass, Color = hedgeColor })
	-- the deck along the bed's south edge: where the gardener stands and looks north over the bed
	local deck = part({ Name = "Deck", Parent = folder, Size = Vector3.new(BED_W, W.DeckY, W.DeckDepth),
		CFrame = CFrame.new(o + Vector3.new(BED_W / 2, W.DeckY / 2, (deckZ0 + deckZ1) / 2)), Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(160, 116, 74) })
	deck:SetAttribute("Deck", true)
	-- the spawn, flush with the deck's top, facing north (-Z) over the bed
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn_" .. plr.UserId
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Enabled = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(o + Vector3.new(BED_W / 2, W.DeckY - 0.5, (deckZ0 + deckZ1) / 2))
	spawn.Parent = folder
	-- the sign at the deck's east end: who gardens here, which wave and season (public)
	local signPart = part({ Name = "Sign", Parent = folder, Size = Vector3.new(7, 4, 0.4),
		CFrame = CFrame.new(o + Vector3.new(BED_W - 4, W.DeckY + 4, deckZ1 - 1)), Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(130, 90, 55) })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = signPart
	local label = Instance.new("TextLabel")
	label.Name = "SignText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 244, 220)
	label.Text = plr.Name .. "'s garden"
	label.Parent = gui
	folder.Parent = gardensFolder
	return folder, spawn, o
end

local function updateCarrots(run: Run)
	local left = math.max(0, run.sim.carrots)
	for i, c in run.carrots do
		local want = if i <= left then 0 else 1
		if c.Transparency ~= want then c.Transparency = want end
	end
end

-- The per-bed parts: path gravel, pads, the west hedge with the gap, the carrots. A pad has no ClickDetector: a tap
-- is picked by the garden view (View.client: GardenCam.pickRay from the PathCells attribute), which also takes a
-- finger on the path beside a pad or on a gnome's body, and zooms when the cell is small on a phone (REVIEW-1).
local function buildBed(run: Run)
	if run.bed then run.bed:Destroy() end
	run.padParts = {}
	run.gnomeModels = {}
	run.carrots = {}
	local o = run.origin
	local bed = Instance.new("Folder")
	bed.Name = "Bed"
	local sim = run.sim
	local path = sim.path
	for i, c in path.cells do
		part({ Name = "Path_" .. i, Parent = bed, Size = Vector3.new(T, 0.2, T),
			CFrame = CFrame.new(o + Vector3.new((c.x + 0.5) * T, 0.1, (c.y + 0.5) * T)), Material = Enum.Material.Pebble,
			Color = Color3.fromRGB(196, 176, 140), CanCollide = true })
	end
	for i, pd in sim.pads do
		local p = part({ Name = "Pad_" .. i, Parent = bed, Size = Vector3.new(W.PadSize, 0.6, W.PadSize),
			CFrame = CFrame.new(o + Vector3.new(pd.cx, 0.3, pd.cz)), Material = Enum.Material.Grass,
			Color = Color3.fromRGB(150, 210, 110) })
		p:SetAttribute("PadId", i)
		-- a faint rim glow: anything interactive should read as interactive (docs/new-game-checklist.md §2)
		part({ Name = "Rim", Parent = p, Size = Vector3.new(W.PadSize + 0.4, 0.3, W.PadSize + 0.4),
			CFrame = CFrame.new(o + Vector3.new(pd.cx, 0.15, pd.cz)), Material = Enum.Material.Neon,
			Color = Color3.fromRGB(210, 255, 170), CanCollide = false, Transparency = 0.55 })
		run.padParts[i] = p
	end
	-- the west hedge, with the gap where the path enters
	local m = W.HedgeMargin
	local z0, z1 = -m, BED_D + W.DeckGap + W.DeckDepth + m
	local gz = (path.cells[1].y + 0.5) * T
	local gap = T
	local H = W.HedgeHeight
	local hedgeColor = Color3.fromRGB(46, 110, 52)
	local northLen = (gz - gap / 2) - z0
	local southLen = z1 - (gz + gap / 2)
	part({ Name = "Hedge_W1", Parent = bed, Size = Vector3.new(3, H, northLen + 3), CFrame = CFrame.new(o + Vector3.new(-m - 1.5, H / 2, z0 - 1.5 + (northLen + 3) / 2)),
		Material = Enum.Material.Grass, Color = hedgeColor })
	part({ Name = "Hedge_W2", Parent = bed, Size = Vector3.new(3, H, southLen + 3), CFrame = CFrame.new(o + Vector3.new(-m - 1.5, H / 2, z1 + 1.5 - (southLen + 3) / 2)),
		Material = Enum.Material.Grass, Color = hedgeColor })
	-- the gravel from the hedge gap to the bed edge, and from the bed to the patch
	part({ Name = "Gravel_In", Parent = bed, Size = Vector3.new(m, 0.2, T), CFrame = CFrame.new(o + Vector3.new(-m / 2, 0.1, gz)),
		Material = Enum.Material.Pebble, Color = Color3.fromRGB(196, 176, 140) })
	-- the carrot patch at the path's end: 20 carrots in a 5 x 4 bed that visibly empties
	local last = path.cells[#path.cells]
	local pz = (last.y + 0.5) * T
	part({ Name = "Patch", Parent = bed, Size = Vector3.new(W.PatchLength - 2, 0.3, 14),
		CFrame = CFrame.new(o + Vector3.new(BED_W + W.PatchLength / 2, 0.15, pz)), Material = Enum.Material.Ground,
		Color = Color3.fromRGB(110, 76, 50) })
	for i = 1, Config.Carrots do
		local cx = BED_W + 2.5 + ((i - 1) % 5) * 2.6
		local cz = pz - 4.5 + math.floor((i - 1) / 5) * 3
		local c = part({ Name = "Carrot_" .. i, Parent = bed, Size = Vector3.new(0.9, 1.6, 0.9),
			CFrame = CFrame.new(o + Vector3.new(cx, 0.9, cz)), Color = Color3.fromRGB(245, 130, 35), CanCollide = false })
		table.insert(run.carrots, c)
	end
	local gnomes = Instance.new("Folder")
	gnomes.Name = "Gnomes"
	gnomes.Parent = bed
	bed.Parent = run.folder
	run.bed = bed
	updateCarrots(run)
end

local function placeGnome(run: Run, gn: any)
	local old = run.gnomeModels[gn.padIndex]
	if old then old:Destroy() end
	local at = CFrame.new(run.origin + Vector3.new(gn.pad.cx, 0.6, gn.pad.cz)) * CFrame.Angles(0, math.pi, 0)
	local m = GardenArt.gnome(gn.kind, gn.level, at)
	m.Name = "Gnome_" .. gn.padIndex
	m:SetAttribute("Kind", gn.kind)
	m:SetAttribute("Level", gn.level)
	m:SetAttribute("Pad", gn.padIndex)
	m.Parent = run.bed and run.bed:FindFirstChild("Gnomes")
	run.gnomeModels[gn.padIndex] = m
end

--============================================================================== what the clients see

local function seasonName(chapter: number): string
	return Config.Chapters[chapter].name
end

local function publish(plr: Player, run: Run)
	local g = run.sim
	-- the attempt first: a client names a new bed's band quietly, so it must know the bed is new before it sees
	-- the bed's progress (REVIEW-2)
	setAttr(run, "Attempt", run.attempt)
	setAttr(run, "Chapter", g.chapter)
	setAttr(run, "Season", seasonName(g.chapter))
	setAttr(run, "Wave", g.wave)
	setAttr(run, "WaveInChapter", Waves.waveInChapter(Config, g.wave))
	setAttr(run, "Endless", g.endless)
	setAttr(run, "Phase", g.phase)
	setAttr(run, "Paused", run.paused)
	setAttr(run, "Carrots", math.max(0, g.carrots))
	setAttr(run, "Seeds", g.seeds)
	setAttr(run, "Gnomes", #g.gnomes)
	setAttr(run, "BuildLeft", math.ceil(g.buildLeft))
	setAttr(run, "Progress", math.floor(Garden.progress(Config, g) * 1000 + 0.5) / 1000)
	-- the next wave's preview is a function of the wave number: built once per wave, not every 0.1 s step
	if run.attrs.PreviewWave ~= g.wave then
		run.attrs.PreviewWave = g.wave
		setAttr(run, "Preview", Waves.preview(Config, g.wave))
	end
	-- the boss bar: the boss's health while it walks (public: every bug's health is on the owner's screen anyway)
	local bossFrac = -1
	for _, b in g.bugs do
		if Config.Bugs[b.kind].boss then bossFrac = math.clamp(b.hp / b.maxHp, 0, 1) end
	end
	setAttr(run, "BossFrac", math.floor(bossFrac * 100 + 0.5) / 100)
	if run.sign then
		local text = string.format("%s\nWave %d - %s", plr.Name, g.wave, seasonName(g.chapter))
		if run.sign.Text ~= text then run.sign.Text = text end
	end
end

local function sendTick(plr: Player, run: Run, ev: any?)
	local g = run.sim
	-- the bugs as packed text (Wire: ~17 bytes a bug), the owner and the attempt so a client draws only its own
	local payload = { o = plr.UserId, a = run.attempt, w = g.wave, b = Wire.packBugs(Config, g.bugs) }
	if ev then
		if #ev.kills > 0 then
			local k = {}
			for _, e in ev.kills do table.insert(k, { e.id, e.kind, e.bounty }) end
			payload.k = k
		end
		if #ev.leaks > 0 then
			local l = {}
			for _, e in ev.leaks do table.insert(l, { e.id, e.bite }) end
			payload.l = l
		end
		if #ev.shots > 0 then
			local s = {}
			for i, e in ev.shots do
				if i > Config.MaxGnomes then break end
				table.insert(s, e.pad)
			end
			payload.s = s
		end
	end
	TickEvent:FireClient(plr, payload)
end

--============================================================================== a garden's life

-- A fresh bed. The endless chapter's seed may YIELD (the day's bed is in a DataStore): one draw at a time per
-- garden (requests in between are told the bed is being dug), and a gardener who left meanwhile gets nothing
-- built (REVIEW-1: a board was built for a player who had gone, and stacked on the next one in that slot).
local function newAttempt(plr: Player, run: Run, chapter: number): boolean
	if run.digging then return false end
	local ch = Config.Chapters[chapter]
	run.digging = true
	local seed = if ch.endless then dailySeed() else serverRng:NextInteger(1, 2147483646)
	run.digging = false
	if runs[plr] ~= run or plr.Parent ~= Players then return false end
	local path = PathGen.genPath(Config, Rng.new(seed))
	run.sim = Garden.new(Config, chapter, path, DEPS)
	run.seed = seed
	run.attempt += 1
	run.paused = false
	run.info:SetAttribute("BedSeed", seed)
	run.info:SetAttribute("Chapter", chapter)
	setAttr(run, "PathCells", PathGen.encodeCells(path.cells))
	buildBed(run)
	publish(plr, run)
	return true
end

local function noteActivity(run: Run)
	run.lastActivity = tick()
	local g = run.sim
	if g and g.phase == "held" then
		g.phase = "build"
		g.buildLeft = Config.BuildSeconds
	end
end

local function setPaused(plr: Player, run: Run, paused: boolean)
	if run.paused == paused then return end
	run.paused = paused
	publish(plr, run)
end

local function onWaveCleared(plr: Player, run: Run, wave: number, bonus: number)
	local p = profiles[plr]
	local g = run.sim
	if p then
		if wave > p.bestWave then
			p.bestWave = wave
			p.bestAt = os.time()
			plr:SetAttribute("BestWave", wave)
			local ls = plr:FindFirstChild("leaderstats")
			local best = ls and ls:FindFirstChild("Best")
			if best then (best :: IntValue).Value = wave end
		end
		if not p.tutorialDone then
			p.tutorialDone = true
			plr:SetAttribute("TutorialDone", true)
		end
	end
	if g.phase == "won" then
		local nextCh = math.min(#Config.Chapters, g.chapter + 1)
		local unlockName = nil
		local unlock = Config.Chapters[nextCh] and Config.Chapters[nextCh].unlock[1]
		if unlock and nextCh > g.chapter then unlockName = Config.Gnomes[unlock].name end
		if p and nextCh > p.chapter then
			p.chapter = nextCh
			plr:SetAttribute("Chapter", nextCh)
		end
		local bossKind = Waves.bossOf(Config, wave)
		FanfareEvent:FireClient(plr, {
			kind = "season", o = plr.UserId, chapter = g.chapter, wave = wave,
			season = seasonName(g.chapter), next = seasonName(nextCh),
			boss = bossKind and Config.Bugs[bossKind].name or nil, unlock = unlockName,
			brag = wave == Config.Pacing.BragWave,
		})
		-- the one moment worth a write of its own, on its own thread: this runs inside the simulation step, and a
		-- DataStore call there froze every garden on the server for its round trips (REVIEW-1)
		task.spawn(saveProfile, plr, false)
	else
		FanfareEvent:FireClient(plr, { kind = "clear", o = plr.UserId, wave = wave, bonus = bonus })
	end
end

local function stepGarden(plr: Player, run: Run, dt: number)
	if run.paused or run.sim == nil then return end -- no bed yet: the first one is still being drawn
	local g = run.sim
	if g.phase == "wave" then
		local ev = { kills = {}, leaks = {}, shots = {} }
		Garden.step(Config, g, dt, ev)
		if #ev.leaks > 0 then updateCarrots(run) end
		sendTick(plr, run, ev)
		if g.phase == "lost" then
			updateCarrots(run)
			FanfareEvent:FireClient(plr, { kind = "lost", o = plr.UserId, wave = g.wave, season = seasonName(g.chapter) })
		elseif g.waveDone then
			local wave = g.wave
			local bonus = Garden.finishWave(Config, g)
			onWaveCleared(plr, run, wave, bonus)
		end
	elseif g.phase == "build" then
		local active = tick() - run.lastActivity <= Config.AfkHoldSeconds
		Garden.tickBuild(Config, g, dt, active)
	end
	publish(plr, run)
end

--============================================================================== requests

-- Every request: a live garden, the shared rate limit, then "you are here" (activity) and a paused garden
-- resumes FIRST, so nothing can be done while paused. Refusals are always said.
-- The two refusals a flood can trigger ("slow down", "still being dug") are said at most once per
-- RepeatToastSeconds: one toast per refused call let a client make the server echo thousands (REVIEW-1).
local joining: { [Player]: boolean } = {}
local lastSaid: { [Player]: { [string]: number } } = {}
local function sayOnce(plr: Player, msg: string)
	local now = tick()
	local said = lastSaid[plr]
	if said == nil then
		said = {}
		lastSaid[plr] = said
	end
	if now - (said[msg] or -math.huge) < Config.Net.RepeatToastSeconds then return end
	said[msg] = now
	toast(plr, msg)
end

-- The caller's garden if it can take orders now; otherwise nil, and the player is told why (a tap in the
-- join's load window, or while a new bed is drawn, was dropped without a word: REVIEW-1).
local function liveRun(plr: Player): Run?
	local run = runs[plr]
	if run and run.sim ~= nil and not run.digging then return run end
	if run or joining[plr] then sayOnce(plr, Config.Text.NotReady) end
	return nil
end

local function request(plr: Player, fn: (Run) -> ())
	local run = liveRun(plr)
	if not run then return end
	if not Board.take(run.limiter, tick()) then
		sayOnce(plr, Config.Text.TooFast)
		return
	end
	noteActivity(run)
	if run.paused then setPaused(plr, run, false) end
	fn(run)
	publish(plr, run)
end

PlantEvent.OnServerEvent:Connect(function(plr: Player, padId: any, kind: any)
	request(plr, function(run)
		local ok, res = Garden.plant(Config, run.sim, kind, padId)
		if not ok then
			toast(plr, res)
			return
		end
		placeGnome(run, res)
	end)
end)

UpgradeEvent.OnServerEvent:Connect(function(plr: Player, padId: any)
	request(plr, function(run)
		local ok, res = Garden.upgrade(Config, run.sim, padId)
		if not ok then
			toast(plr, res)
			return
		end
		placeGnome(run, res)
	end)
end)

SellEvent.OnServerEvent:Connect(function(plr: Player, padId: any)
	request(plr, function(run)
		local idx = padId
		local ok, res = Garden.sell(Config, run.sim, padId)
		if not ok then
			toast(plr, res)
			return
		end
		local m = run.gnomeModels[idx]
		if m then m:Destroy() end
		run.gnomeModels[idx] = nil
		toast(plr, string.format("Sold for %d seeds", res))
	end)
end)

ReadyEvent.OnServerEvent:Connect(function(plr: Player)
	request(plr, function(run)
		local ok, why = Garden.ready(Config, run.sim)
		if not ok then toast(plr, why :: string) end
	end)
end)

RestartEvent.OnServerEvent:Connect(function(plr: Player)
	request(plr, function(run)
		if run.sim.phase ~= "lost" then
			toast(plr, "Your garden is still standing")
			return
		end
		-- the profile's chapter can be ahead of this bed's (a load that came back late: REVIEW-1)
		local p = profiles[plr]
		newAttempt(plr, run, math.max(run.sim.chapter, p and p.chapter or 1))
	end)
end)

NextSeasonEvent.OnServerEvent:Connect(function(plr: Player)
	request(plr, function(run)
		if run.sim.phase ~= "won" then
			toast(plr, "Win this season first")
			return
		end
		local p = profiles[plr]
		newAttempt(plr, run, math.min(#Config.Chapters, math.max(run.sim.chapter + 1, p and p.chapter or 1)))
	end)
end)

-- PAUSE is not a garden action: it does not resume first, it IS the switch. Both sides of the garden stop
-- (the sim is not stepped at all), so a pause only buys thinking time (DESIGN.md §9).
-- Only the gardener ends a pause: their client's wake (Rest: their own step), this switch, or a garden action.
-- REVIEW-2: the server also resumed on any 4-stud move of the character, and a neighbour's shove is a move.
PauseEvent.OnServerEvent:Connect(function(plr: Player, want: any)
	local run = liveRun(plr)
	if not run then return end
	-- the bucket first: a malformed call costs a token like any other (it was answered before the limit)
	if not Board.take(run.limiter, tick()) then return sayOnce(plr, Config.Text.TooFast) end
	if type(want) ~= "boolean" then return toast(plr, Config.Text.CantPause) end
	local now = tick()
	-- the cooldown holds back PAUSING only: a resume always lands (the client's wake comes 0.4 s after a pause
	-- when the gardener moves, inside the 0.5 s, and was refused with "Slow down a little": REVIEW-2)
	if want and now - run.lastPauseAt < Config.Net.PauseCooldown then return sayOnce(plr, Config.Text.TooFast) end
	if want then run.lastPauseAt = now end
	noteActivity(run)
	if want then
		local ph = run.sim.phase
		if ph ~= "reveal" and ph ~= "build" and ph ~= "wave" and ph ~= "held" then
			return toast(plr, Config.Text.CantPause)
		end
	end
	setPaused(plr, run, want)
end)

-- The gardener's own input, reported by their client (Garden.client: thumbstick, keys, a tap) at most every
-- Config.Net.HereSeconds: "here" for the AFK hold. It resumes nothing and is never answered (no echo, no
-- token). A hacked client that sends it only keeps its OWN garden from being held; nobody can send it for
-- someone else, and a shove or a fling is not an input (REVIEW-2).
HereEvent.OnServerEvent:Connect(function(plr: Player)
	local run = runs[plr]
	if not run or run.sim == nil then return end
	local now = tick()
	if now - run.lastHere < Config.Net.HereMinGap then return end
	run.lastHere = now
	noteActivity(run)
end)

--============================================================================== the board: public + friends

local BC = Config.Board
local BOARD_SIZE = Vector3.new(14, 9, 0.4) -- 560 x 360 px at Board.client's 40 px per stud
local boardParts: { [Player]: BasePart } = {}
local boardMode: { [Player]: string } = {}
local lastToggle: { [Player]: number } = {}
local showBoard

local function buildBoard(plr: Player, origin: Vector3)
	-- ON the deck's west end, in its south half, its face turned south to the garden view's camera: it is in the
	-- first view, 41 studs from the spawn, and hides no pad (REVIEW-1: on the lawn west of the deck, 53 studs out
	-- and turned toward the spawn, it stood outside a phone's first view). Walk up to it and the camera reads it.
	local deckZ1 = BED_D + W.DeckGap + W.DeckDepth
	local centre = origin + Vector3.new(W.BoardX, W.DeckY + BOARD_SIZE.Y / 2 + 0.6, deckZ1 - W.BoardBack)
	local look = centre + Vector3.new(0, 0, 1)
	local p = Instance.new("Part")
	p.Name = "GardenBoard_" .. plr.UserId
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = BOARD_SIZE
	p.CFrame = CFrame.lookAt(centre, Vector3.new(look.X, centre.Y, look.Z))
	p.Material = Enum.Material.WoodPlanks
	p.Color = Color3.fromRGB(70, 50, 34)
	p:SetAttribute("BoardOf", plr.UserId)
	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.CanTouch = false
	trim.CanQuery = false
	trim.CastShadow = false
	trim.Size = Vector3.new(BOARD_SIZE.X + 0.6, BOARD_SIZE.Y + 0.6, 0.2)
	trim.CFrame = p.CFrame * CFrame.new(0, 0, BOARD_SIZE.Z / 2 + 0.05)
	trim.Material = Enum.Material.Neon
	trim.Color = Color3.fromRGB(255, 210, 110)
	trim.Parent = p
	local at = Instance.new("Attachment")
	at.Name = "PromptAt"
	at.Position = Vector3.new(0, -BOARD_SIZE.Y / 2 + 0.5, -BOARD_SIZE.Z / 2 - 0.3)
	at.Parent = p
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = BC.Text.Prompt
	prompt.ObjectText = "Best Gardeners"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = BC.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = at
	prompt.Triggered:Connect(function(who: Player)
		if who ~= plr then
			sayOnce(who, "That board belongs to another gardener. Yours stands at the west end of your own deck.")
			return
		end
		-- one toggle per BC.ToggleSeconds: every trigger was answered with a payload (and a friends view), the
		-- only client-triggered server work outside the token bucket (REVIEW-2: 2000 triggers, 2001 payloads)
		local now = tick()
		if now - (lastToggle[plr] or -math.huge) < BC.ToggleSeconds then return sayOnce(plr, Config.Text.TooFast) end
		lastToggle[plr] = now
		boardMode[plr] = if boardMode[plr] == "friends" then "public" else "friends"
		showBoard(plr)
	end)
	p.Parent = boardsFolder
	boardParts[plr] = p
end

local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then return cached end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		nameCache[userId] = here.Name
		return here.Name
	end
	local ok, res = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	if ok and type(res) == "string" then
		nameCache[userId] = res
		return res
	end
	return "#" .. tostring(userId)
end
local function withNames(rows: { any }): { any }
	local out = {}
	for i, r in rows do
		out[i] = { rank = r.rank, userId = r.userId, tier = r.tier, you = r.you, name = nameOf(r.userId) }
	end
	return out
end

local function liveValue(p: any): number
	if not p or p.bestWave <= 0 then return 0 end
	return Board.encode(p.bestWave, p.bestAt, BC)
end

local publicView: any = { rows = {}, note = BC.Text.Loading }

local function sendBoard(plr: Player, mode: string, view: any)
	BoardEvent:FireClient(plr, { viewer = plr.UserId, mode = mode, rows = view.rows, note = view.note })
end

local function refreshPublic()
	if not orderedLB then
		publicView = Board.publicView({}, BC)
		return
	end
	local ok, page = pcall(function() return orderedLB:GetSortedAsync(false, BC.PublicRows) end)
	if not ok or not page then return end
	local okPage, items = pcall(function() return page:GetCurrentPage() end)
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
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, tick())
local fetching: { [Player]: boolean } = {}

local function friendIdsOf(plr: Player): ({ number }, boolean)
	local now = tick()
	local hit = Board.cacheGet(friendsCache, plr.UserId, now)
	if hit then return hit, false end
	if Board.cacheHas(friendsFailed, plr.UserId, now) then return {}, true end
	local ok, pages = pcall(function() return (Players :: any):GetFriendsAsync(plr.UserId) end)
	local ids = {}
	local broken = not ok or pages == nil
	while not broken and #ids < BC.FriendsCap do
		local okPage, items = pcall(function() return pages:GetCurrentPage() end)
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

local function budgetLeft(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return not (ok and type(budget) == "number" and budget < BC.BudgetReserve)
end

local function friendValue(userId: number): number?
	local here = Players:GetPlayerByUserId(userId)
	if here and profiles[here] then return liveValue(profiles[here]) end
	local now = tick()
	if Board.cacheHas(scoreCache, userId, now) then return Board.cacheGet(scoreCache, userId, now) end
	if not orderedLB then return 0 end
	if not budgetLeft() or not Board.take(readLimiter, now) then return nil end
	local ok, v = pcall(function() return orderedLB:GetAsync(key(userId)) end)
	if not ok then return 0 end
	local value = if type(v) == "number" then v else 0
	Board.cachePut(scoreCache, userId, value, now)
	return value
end

showBoard = function(plr: Player)
	if boardMode[plr] ~= "friends" then
		sendBoard(plr, "public", publicView)
		return
	end
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
			values[plr.UserId] = liveValue(profiles[plr])
			local view = Board.friendsView(plr.UserId, values, status, BC)
			sendBoard(plr, "friends", { rows = withNames(view.rows), note = view.note })
		end
		local i, lastPush = 1, -math.huge
		while i <= #ids and plr.Parent == Players and boardMode[plr] == "friends" do
			local v = friendValue(ids[i])
			if v == nil then
				status.checked = i - 1
				if tick() - lastPush >= 0.5 then
					push()
					lastPush = tick()
				end
				task.wait(1)
			else
				values[ids[i]] = v
				i += 1
			end
		end
		status.checked = i - 1
		if plr.Parent == Players and boardMode[plr] == "friends" then push() end
		fetching[plr] = nil
	end)
end

local function teardownBoard(plr: Player)
	local p = boardParts[plr]
	boardParts[plr] = nil
	if p then p:Destroy() end
	boardMode[plr] = nil
	lastToggle[plr] = nil
	fetching[plr] = nil
end

--============================================================================== lifecycle

-- The profile's numbers on the player (attributes, leaderstats), after a load or a merge.
local function showProfile(plr: Player, p: any)
	plr:SetAttribute("Chapter", p.chapter)
	plr:SetAttribute("BestWave", p.bestWave)
	plr:SetAttribute("TutorialDone", p.tutorialDone)
	plr:SetAttribute("Saving", p.canSave)
	local ls = plr:FindFirstChild("leaderstats")
	local best = ls and ls:FindFirstChild("Best")
	if best then (best :: IntValue).Value = p.bestWave end
end

-- A session that has not got the record (a failed read, or another server's lock) keeps asking: 2 s after join,
-- then 4, 8, 10, 10 ... s apart. REVIEW-1: it tried once and stayed read-only for the whole session, so a
-- reconnect within 45 s of a crash, or one DataStore blip, lost everything played that session (a veteran even
-- played on in Spring). When it gets the record it merges what is stored with what was played, saves at once,
-- says so, and a garden still on its reveal moves to the restored chapter.
local function keepTrying(plr: Player, p: any)
	if not store then return end
	task.spawn(function()
		local waitFor = Config.Save.RetryFirstSeconds
		while not p.canSave do
			task.wait(waitFor)
			if p.leaving or profiles[plr] ~= p then return end
			local chapterBefore = p.chapter
			local read, acquired = tryLoad(plr, p)
			if p.leaving or profiles[plr] ~= p then
				if acquired then releaseLock(plr.UserId, p.session) end -- taken after the player left: give it back
				return
			end
			if read then
				showProfile(plr, p)
				local run = runs[plr]
				if p.chapter > chapterBefore and run and run.sim and run.sim.phase == "reveal" and run.sim.chapter < p.chapter then
					if newAttempt(plr, run, p.chapter) then
						toast(plr, string.format(Config.Text.Restored, Config.Chapters[p.chapter].name))
					end
				end
			end
			if acquired then
				toast(plr, Config.Text.SavingAgain)
				saveProfile(plr, false)
				return
			end
			waitFor = math.min(waitFor * 2, Config.Save.RetryMaxSeconds)
		end
	end)
end

-- What a joined player holds before anything yields: the slot, its folder (the spawn is in it) and the
-- server-only info folder. PlayerRemoving frees exactly this, whenever it comes.
type Seat = { slot: number, folder: Folder, info: Folder }
local seats: { [Player]: Seat } = {}

local function onPlayerAdded(plr: Player)
	-- BEFORE ANY YIELD: a slot, its spawn, and the player's RespawnLocation (robloxemu/SPAWN-ORDER.md). The
	-- engine places the character on it by itself, after CharacterAdded; nothing here writes a CFrame.
	local slot = claimSlot(plr)
	local folder, spawn, origin = buildSlot(plr, slot)
	plr.RespawnLocation = spawn
	plr.CharacterAdded:Connect(groupCharacter)
	if plr.Character then groupCharacter(plr.Character) end
	local info = Instance.new("Folder")
	info.Name = tostring(plr.UserId)
	info.Parent = infoFolder
	local seat: Seat = { slot = slot, folder = folder, info = info }
	seats[plr] = seat
	joining[plr] = true

	local p = defaultProfile()
	profiles[plr] = p
	local read, acquired = tryLoad(plr, p) -- YIELDS on UpdateAsync
	-- leaving during that yield is normal: PlayerRemoving freed the seat; give back a lock taken meanwhile
	if seats[plr] ~= seat or plr.Parent ~= Players then
		if acquired then releaseLock(plr.UserId, p.session) end
		return
	end

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Value = p.bestWave
	best.Parent = ls
	ls.Parent = plr
	showProfile(plr, p)
	if not acquired then keepTrying(plr, p) end

	local signGui = folder:FindFirstChild("Sign") and folder.Sign:FindFirstChild("SignGui")
	local run: Run = {
		sim = nil :: any,
		seed = 0,
		attempt = 0,
		paused = false,
		digging = false,
		lastActivity = tick(),
		lastHere = -math.huge,
		lastPauseAt = -math.huge,
		limiter = Board.newLimiter(Config.Net.RateBurst, Config.Net.RatePerSecond, tick()),
		folder = folder,
		bed = nil,
		origin = origin,
		padParts = {},
		gnomeModels = {},
		carrots = {},
		sign = signGui and signGui:FindFirstChild("SignText") :: TextLabel?,
		attrs = {},
		info = info,
	}
	runs[plr] = run
	-- the endless chapter's first bed may yield on the day's store; a gardener who leaves meanwhile gets no bed
	-- and no board (newAttempt returns false)
	if not newAttempt(plr, run, p.chapter) then return end
	joining[plr] = nil

	buildBoard(plr, origin)
	boardMode[plr] = "public"
	showBoard(plr)
	if not p.canSave then toast(plr, Config.Text.NoSave) end
end

local function onPlayerRemoving(plr: Player)
	-- free the world first (nothing here yields), then save: a slot is never held by someone who has gone
	joining[plr] = nil
	lastSaid[plr] = nil
	local p = profiles[plr]
	if p then p.leaving = true end
	local run = runs[plr]
	runs[plr] = nil
	if run then run.digging = false end
	local seat = seats[plr]
	seats[plr] = nil
	if seat then
		seat.folder:Destroy() -- the spawn goes with it: the engine can never pick a stale one
		seat.info:Destroy()
	end
	teardownBoard(plr)
	local slot = slotOf[plr]
	slotOf[plr] = nil
	if slot ~= nil and usedSlots[slot] == plr then usedSlots[slot] = nil end
	saveProfile(plr, true) -- waits for a write in flight (a season's win), then releases the lock
	profiles[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, plr) end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr, true) end
end)

-- THE SIMULATION: every garden, a fixed step, at most MaxStepsPerFrame per wake. A lagging server slows both
-- sides of every garden equally; it never skips a step's worth of bugs past a gnome.
task.spawn(function()
	local acc = 0
	local dt = Config.Dt
	while true do
		local waited = task.wait(dt)
		acc = math.min(acc + (tonumber(waited) or dt), dt * Config.Net.MaxStepsPerFrame)
		while acc >= dt - 1e-9 do
			acc -= dt
			for plr, run in runs do
				local ok, err = pcall(stepGarden, plr, run, dt)
				if not ok then warn("[GnomeGarden] garden step failed for " .. plr.Name .. ": " .. tostring(err)) end
			end
		end
	end
end)

-- (No poll of the characters: REVIEW-2. "Here" is the gardener's own input, from their client; a move of their
-- character can be someone else's doing.)

-- Autosave (also renews the session lock).
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr, false) end
	end
end)

task.spawn(function()
	while true do
		refreshPublic() -- at most one GetSortedAsync per PublicCacheSeconds
		for _, plr in ipairs(Players:GetPlayers()) do
			if boardMode[plr] == "public" then sendBoard(plr, "public", publicView) end
		end
		task.wait(BC.PublicCacheSeconds)
	end
end)

print("[GnomeGarden] Gnome Garden Defense loaded: " .. W.Slots .. " gardens, " .. Config.PathCells .. "-cell paths")
