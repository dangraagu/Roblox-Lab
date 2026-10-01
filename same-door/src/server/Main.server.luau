-- The Same Door — the authoritative server. ServerScriptService.
--
-- Every UTC day the dungeon rearranges itself around the same old Door, and every player gets the
-- identical layout. From the hub arch you enter your own copy of today's dungeon (9 x 9 cells of
-- 16 studs), collect 3 Seals in any order and reach the Door. The server's clock (the sum of its own
-- Heartbeat dt) runs from its sighting of you crossing the line to its sighting of you at the Door,
-- and that time goes on today's public + friends board. DESIGN.md is the spec; CLAUDE.md the gates.
--
-- What never leaves this script (DESIGN §3.4, §12): the day's record lives in server memory and in
-- ONE server-only copy, ServerStorage.SameDoor.Day (anomaly-observatory: "ServerStorage, not the
-- zone"). Clients receive a cell only after the server has seen them walk within 2 open steps of it
-- (Cell remote, to the owner only), and no remote carries a time, a position, a seal or a finish.
--
-- Spawn (robloxemu/SPAWN-ORDER.md): exactly one enabled SpawnLocation, HubSpawn, and
-- plr.RespawnLocation points at it before the character loads. CharacterAdded never writes a CFrame.
-- Entering a run is a server PivotTo after the arch prompt, long after the character is parented.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService") -- JSONEncode for the server-only copy, GenerateGUID for session tokens

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Day = require(ReplicatedStorage:WaitForChild("Day"))
local Medals = require(ReplicatedStorage:WaitForChild("Medals"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local Ledger = require(ReplicatedStorage:WaitForChild("Ledger"))
local Grid = require(ReplicatedStorage:WaitForChild("Grid"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Dungeon = require(ServerScriptService:WaitForChild("Dungeon"))
local RunCheck = require(ServerScriptService:WaitForChild("RunCheck"))
local RunState = require(ServerScriptService:WaitForChild("RunState"))

local DEPS = { RunCheck = RunCheck, Grid = Grid, Dungeon = Dungeon }
local G = Config.Grid
local CELL = G.Cell

--============================================================================ look (hub daylight)
-- The hub is not a band: it keeps one daylight look. The client restores it on return.
Fx.applyLighting(Fx.Presets.Temple)

--============================================================================ helpers
local function make(className: string, parent: Instance?, props: { [string]: any }?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
	inst.Parent = parent
	return inst
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: { number }, props: { [string]: any }?): BasePart
	local p = make("Part", nil, {
		Name = name, Size = size, CFrame = cf, Anchored = true, Color = rgb(color),
		Material = Enum.Material.Slate, TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
	})
	if props then
		for k, v in props do (p :: any)[k] = v end
	end
	p.Parent = parent
	return p
end

--============================================================================ remotes
local remotes = make("Folder", ReplicatedStorage, { Name = "SameDoorRemotes" })
local CellEvent = make("RemoteEvent", remotes, { Name = "Cell" }) -- server -> owner: revealed cells
local RunEvent = make("RemoteEvent", remotes, { Name = "Run" }) -- server -> owner: run state
local BoardEvent = make("RemoteEvent", remotes, { Name = "Board" }) -- server -> client: board rows
local ToastEvent = make("RemoteEvent", remotes, { Name = "Toast" }) -- server -> client: every refusal's reason
local DayEvent = make("RemoteEvent", remotes, { Name = "DayInfo" }) -- server -> client: Door #, medal times
local LeaveEvent = make("RemoteEvent", remotes, { Name = "Leave" }) -- client -> server
local RunAgainEvent = make("RemoteEvent", remotes, { Name = "RunAgain" }) -- client -> server
local HubEvent = make("RemoteEvent", remotes, { Name = "GoHub" }) -- client -> server

-- Wall-clock seconds for caches and rate limits. NOT os.clock: that is CPU time and barely moves
-- headless (deep-vein CLAUDE.md). The run clock is never this: it is the sum of Heartbeat dt.
local function now(): number
	return tick()
end

local function toast(plr: Player, msg: string)
	ToastEvent:FireClient(plr, msg)
end

--============================================================================ stores
local function tryStore(fn: () -> any): any
	local ok, s = pcall(fn)
	return if ok then s else nil
end
local daysStore = tryStore(function() return DataStoreService:GetDataStore(Config.Day.StoreName) end)
local playerStore = tryStore(function() return DataStoreService:GetDataStore(Config.Save.StoreName) end)
local boardStores: { [string]: any } = {}
local function boardStore(dayIndex: number): any
	local scope = Day.boardScope(dayIndex)
	local s = boardStores[scope]
	if s == nil then
		s = tryStore(function() return DataStoreService:GetOrderedDataStore(Config.Board.StoreName, scope) end)
		boardStores[scope] = s
	end
	return s
end

--============================================================================ the hub
local hub = make("Folder", workspace, { Name = "Hub" })
part(hub, "HubFloor", Vector3.new(160, 1, 160), CFrame.new(0, -0.5, 0), { 118, 124, 112 }, { Material = Enum.Material.Cobblestone })

-- The ONE enabled SpawnLocation. 14 studs south of the arch, facing it (north, +z).
local ARCH_Z = 20
local SPAWN_POS = Vector3.new(0, -0.45, ARCH_Z - Config.World.HubSpawnToArch)
local hubSpawn = make("SpawnLocation", nil, {
	Name = "HubSpawn", Size = Vector3.new(6, 1, 6),
	CFrame = CFrame.lookAt(SPAWN_POS, SPAWN_POS + Vector3.new(0, 0, 1)),
	Anchored = true, Enabled = true, Neutral = true, Duration = 0,
	Color = Color3.fromRGB(150, 160, 175), Material = Enum.Material.Marble,
	TopSurface = Enum.SurfaceType.Smooth,
})
hubSpawn.Parent = hub

-- The arch: two pillars, a lintel and a glowing doorway that carries the prompt.
local archFolder = make("Folder", hub, { Name = "Arch" })
part(archFolder, "PillarW", Vector3.new(2, 12, 2), CFrame.new(-5, 6, ARCH_Z), { 90, 88, 100 }, { Material = Enum.Material.Marble })
part(archFolder, "PillarE", Vector3.new(2, 12, 2), CFrame.new(5, 6, ARCH_Z), { 90, 88, 100 }, { Material = Enum.Material.Marble })
part(archFolder, "Lintel", Vector3.new(12, 2, 2), CFrame.new(0, 13, ARCH_Z), { 90, 88, 100 }, { Material = Enum.Material.Marble })
local archGlow = part(archFolder, "Doorway", Vector3.new(8, 11, 0.4), CFrame.new(0, 5.5, ARCH_Z), Config.Colours.DoorAwake,
	{ Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false })
Fx.attachGlow(archGlow, rgb(Config.Colours.DoorAwake), 1.2, 14)
local archPrompt = make("ProximityPrompt", archGlow, {
	Name = "EnterPrompt", ActionText = "Enter Today's Door", ObjectText = "The Same Door",
	HoldDuration = 0, MaxActivationDistance = Config.World.PromptDistance, RequiresLineOfSight = false,
})
local archSign = make("BillboardGui", archGlow, { Name = "Sign", Size = UDim2.fromOffset(260, 60), StudsOffset = Vector3.new(0, 8, 0), AlwaysOnTop = false })
local archLabel = make("TextLabel", archSign, {
	Name = "Text", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 244, 225), Font = Enum.Font.GothamBold, Text = "Today's Door is being carved...",
})

-- The board faces the spawn from the left; yesterday's plaque stands beside it.
local BOARD_POS = Vector3.new(14, 7, ARCH_Z - 4)
local boardPart = part(hub, "DoorBoard", Vector3.new(12, 12, 1), CFrame.lookAt(BOARD_POS, Vector3.new(0, 7, SPAWN_POS.Z)),
	{ 40, 36, 48 }, { Material = Enum.Material.WoodPlanks })
local boardPrompt = make("ProximityPrompt", boardPart, {
	Name = "TogglePrompt", ActionText = "Show friends", ObjectText = "Today's board",
	HoldDuration = 0, MaxActivationDistance = Config.World.PromptDistance, RequiresLineOfSight = false,
})
local PLAQUE_POS = Vector3.new(22, 3.5, ARCH_Z - 1)
part(hub, "YesterdayPlaque", Vector3.new(8, 5, 0.6), CFrame.lookAt(PLAQUE_POS, Vector3.new(0, 3.5, SPAWN_POS.Z)),
	{ 70, 60, 50 }, { Material = Enum.Material.Wood })

-- The campfire on the right. Its "Rest by the fire" prompt is made by the client (rest is client-only).
local CAMP_POS = Vector3.new(-14, 0, ARCH_Z - 4)
local campfire = make("Folder", hub, { Name = "Campfire" })
part(campfire, "Stones", Vector3.new(6, 0.6, 6), CFrame.new(CAMP_POS + Vector3.new(0, 0.3, 0)), { 96, 92, 88 }, { Material = Enum.Material.Rock })
local fireCore = part(campfire, "Fire", Vector3.new(2, 1.5, 2), CFrame.new(CAMP_POS + Vector3.new(0, 1.2, 0)), { 255, 150, 120 },
	{ Material = Enum.Material.Neon, CanCollide = false, Transparency = 0.2 })
Fx.attachGlow(fireCore, Color3.fromRGB(255, 160, 120), 1.6, 18)
Fx.emitter(fireCore, { Rate = 10, Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(2, 4),
	Color = ColorSequence.new(Color3.fromRGB(255, 170, 120)), LightEmission = 1, SpreadAngle = Vector2.new(15, 15) })
for i, a in { 0, 120, 240 } do
	local r = math.rad(a)
	part(campfire, "Log" .. i, Vector3.new(4, 1, 1), CFrame.new(CAMP_POS + Vector3.new(math.cos(r) * 3.2, 0.5, math.sin(r) * 3.2)) * CFrame.Angles(0, -r, 0),
		{ 110, 80, 60 }, { Material = Enum.Material.Wood })
end

--============================================================================ lanes (one per player, recycled)
local lanesFolder = make("Folder", workspace, { Name = "Lanes" })
local laneBuilt: { [number]: Folder } = {}
local laneOf: { [Player]: number } = {}
local freeLanes: { number } = {}
for i = Config.World.MaxLanes, 1, -1 do table.insert(freeLanes, i) end

local function laneOrigin(i: number): Vector3
	local o = Grid.laneOrigin(i, Config)
	return Vector3.new(o.x, o.y, o.z)
end

local SIZE_GRID = G.W * CELL -- 144
local WALL_T, WALL_H = G.WallThick, G.WallHeight

-- The shell every lane shares, identical every day: floor, ceiling, the perimeter (the south wall in
-- two pieces around the entrance), the antechamber with its start line, and the Dawn Sanctum.
-- Built BEFORE anyone is moved into it (deep-vein: build the landing first).
local function buildLane(i: number): Folder
	if laneBuilt[i] then return laneBuilt[i] end
	local o = laneOrigin(i)
	local f = make("Folder", nil, { Name = "Lane_" .. i })
	local stone = { 70, 72, 80 }
	local function at(x: number, y: number, z: number): CFrame return CFrame.new(o + Vector3.new(x, y, z)) end
	local mid = SIZE_GRID / 2
	part(f, "Floor", Vector3.new(SIZE_GRID + WALL_T, 1, SIZE_GRID + WALL_T), at(mid, -0.5, mid), { 58, 58, 64 }, { Material = Enum.Material.Slate })
	part(f, "Ceiling", Vector3.new(SIZE_GRID + WALL_T, 1, SIZE_GRID + WALL_T), at(mid, WALL_H + 0.5, mid), { 30, 30, 34 })
	part(f, "WallN", Vector3.new(SIZE_GRID + WALL_T, WALL_H, WALL_T), at(mid, WALL_H / 2, SIZE_GRID), stone)
	part(f, "WallW", Vector3.new(WALL_T, WALL_H, SIZE_GRID + WALL_T), at(0, WALL_H / 2, mid), stone)
	part(f, "WallE", Vector3.new(WALL_T, WALL_H, SIZE_GRID + WALL_T), at(SIZE_GRID, WALL_H / 2, mid), stone)
	local gapL, gapR = G.EntranceX * CELL, (G.EntranceX + 1) * CELL -- 64 .. 80
	part(f, "WallS_W", Vector3.new(gapL + WALL_T / 2, WALL_H, WALL_T), at((gapL - WALL_T / 2) / 2, WALL_H / 2, 0), stone)
	part(f, "WallS_E", Vector3.new(SIZE_GRID - gapR + WALL_T / 2, WALL_H, WALL_T), at(gapR + (SIZE_GRID - gapR + WALL_T / 2) / 2 - WALL_T / 4, WALL_H / 2, 0), stone)
	-- the antechamber: 16 x 16 south of the entrance, closed except the start line
	local D = Config.World.AntechamberDepth
	part(f, "AnteFloor", Vector3.new(CELL, 1, D), at(gapL + CELL / 2, -0.5, -D / 2), { 64, 62, 70 })
	part(f, "AnteCeiling", Vector3.new(CELL + WALL_T, 1, D), at(gapL + CELL / 2, WALL_H + 0.5, -D / 2), { 30, 30, 34 })
	part(f, "AnteW", Vector3.new(WALL_T, WALL_H, D), at(gapL, WALL_H / 2, -D / 2), stone)
	part(f, "AnteE", Vector3.new(WALL_T, WALL_H, D), at(gapR, WALL_H / 2, -D / 2), stone)
	part(f, "AnteS", Vector3.new(CELL + WALL_T, WALL_H, WALL_T), at(gapL + CELL / 2, WALL_H / 2, -D), stone)
	local line = part(f, "StartLine", Vector3.new(CELL - WALL_T, 0.1, 0.6), at(gapL + CELL / 2, 0.05, 0), { 190, 225, 255 },
		{ Material = Enum.Material.Neon, CanCollide = false, CanQuery = false })
	line:SetAttribute("StartLine", true)
	-- the Dawn Sanctum: an open-air balcony north of the grid, where every finish lands
	local sz = SIZE_GRID + Config.World.SanctumOffset
	local sanct = make("Folder", f, { Name = "Sanctum" })
	part(sanct, "SanctumFloor", Vector3.new(40, 1, 40), at(mid, -0.5, sz), { 225, 215, 205 }, { Material = Enum.Material.Marble })
	for k, off in { Vector3.new(-16, 0, -16), Vector3.new(16, 0, -16), Vector3.new(-16, 0, 16), Vector3.new(16, 0, 16) } do
		part(sanct, "Column" .. k, Vector3.new(2, 10, 2), at(mid + off.X, 5, sz + off.Z), { 230, 225, 215 }, { Material = Enum.Material.Marble })
	end
	part(sanct, "FlowersW", Vector3.new(4, 1, 24), at(mid - 17, 0.5, sz), { 255, 170, 200 }, { Material = Enum.Material.Grass })
	part(sanct, "FlowersE", Vector3.new(4, 1, 24), at(mid + 17, 0.5, sz), { 170, 120, 255 }, { Material = Enum.Material.Grass })
	local opened = part(sanct, "OpenDoor", Vector3.new(8, 12, 1), at(mid, 6, sz + 12), Config.Colours.DoorAwake,
		{ Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false })
	-- A glass parapet on all four edges: the balcony stands over nothing, and a player reading the
	-- finish card must not walk or jump off it (12 high: a jump's apex puts the root at 3 + 7.2).
	-- Glass keeps the dawn sky in view (how it reads is on the needs-Studio list).
	for _, r in {
		{ "RailN", Vector3.new(40, 12, 1), Vector3.new(0, 0, 19.5) }, { "RailS", Vector3.new(40, 12, 1), Vector3.new(0, 0, -19.5) },
		{ "RailE", Vector3.new(1, 12, 40), Vector3.new(19.5, 0, 0) }, { "RailW", Vector3.new(1, 12, 40), Vector3.new(-19.5, 0, 0) },
	} do
		part(sanct, r[1], r[2], at(mid + r[3].X, 6, sz + r[3].Z), { 235, 240, 250 },
			{ Material = Enum.Material.Glass, Transparency = 0.8, CastShadow = false })
	end
	Fx.attachGlow(opened, rgb(Config.Colours.DoorAwake), 1.4, 16)
	f.Parent = lanesFolder
	laneBuilt[i] = f
	return f
end

local function antechamberCFrame(i: number): CFrame
	local o = laneOrigin(i)
	local ax, az = Grid.centre(G.EntranceX, -1, Config)
	local p = o + Vector3.new(ax, 3, az)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end

local function sanctumCFrame(i: number): CFrame
	local o = laneOrigin(i)
	local p = o + Vector3.new(SIZE_GRID / 2, 3, SIZE_GRID + Config.World.SanctumOffset - 6)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end

local function hubCFrame(): CFrame
	local p = SPAWN_POS + Vector3.new(0, 3, 0)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end

local function campCFrame(): CFrame
	local p = CAMP_POS + Vector3.new(4.5, 3, -2)
	return CFrame.lookAt(p, Vector3.new(CAMP_POS.X, p.Y, CAMP_POS.Z))
end

--============================================================================ the day
-- dayState: "loading" | "ready" | "failed" | "outdated"
local serverStorageFolder = make("Folder", ServerStorage, { Name = "SameDoor" })
local dayCopy = make("StringValue", serverStorageFolder, { Name = "Day", Value = "" }) -- server-only, for rigs and checks

local today = {
	index = 0,
	state = "loading",
	record = nil :: any,
	world = nil :: any,
	message = "Today's Door is being carved...",
}
local worldsByDay: { [number]: any } = {}

-- Server entropy for the mint: a server-lifetime Random XORed with a fresh Random per mint, read
-- through the HIGH bits (checklist: never state % span). fork-tower mintSecret, REVIEW-4 §2.
local lifeRandom = Random.new()
local TWO32 = 4294967296
local function mintDraw(): (number) -> number
	local fresh = Random.new()
	return function(n: number): number
		local u = bit32.bxor(lifeRandom:NextInteger(0, TWO32 - 1), fresh:NextInteger(0, TWO32 - 1))
		local v = math.floor(u / TWO32 * n) + 1
		return math.clamp(v, 1, n)
	end
end

local function publishDay()
	local info = {
		state = today.state,
		message = today.message,
		day = today.index,
		door = Day.doorNumber(today.index, Config.Day),
		serverNow = os.time(),
		studio = today.world ~= nil and today.world.studio or false,
	}
	if today.record then
		local P = today.record.perfectMs
		info.perfectMs = P
		info.silverMs = Medals.thresholdMs(P, "Silver", Config)
		info.goldMs = Medals.thresholdMs(P, "Gold", Config)
		info.sealerMs = Medals.thresholdMs(P, "Sealer", Config)
	end
	DayEvent:FireAllClients(info)
	-- The same public facts as attributes on the remotes folder, so a client that loads after this
	-- fired still reads them at once (nothing here is secret: the Door number, the state and the
	-- medal times shown in every antechamber).
	remotes:SetAttribute("DayState", info.state)
	remotes:SetAttribute("DayMessage", info.message)
	remotes:SetAttribute("Door", info.door)
	remotes:SetAttribute("Studio", info.studio)
	remotes:SetAttribute("PerfectMs", info.perfectMs)
	remotes:SetAttribute("SilverMs", info.silverMs)
	remotes:SetAttribute("GoldMs", info.goldMs)
	remotes:SetAttribute("SealerMs", info.sealerMs)
	if today.state == "ready" then
		archLabel.Text = string.format("Door #%d%s", info.door, if info.studio then " (Studio door, unranked)" else "")
	else
		archLabel.Text = today.message
	end
	return info
end

local function dayInfoFor(plr: Player)
	local info = {
		state = today.state, message = today.message, day = today.index,
		door = Day.doorNumber(today.index, Config.Day), serverNow = os.time(),
		studio = today.world ~= nil and today.world.studio or false,
	}
	if today.record then
		local P = today.record.perfectMs
		info.perfectMs = P
		info.silverMs = Medals.thresholdMs(P, "Silver", Config)
		info.goldMs = Medals.thresholdMs(P, "Gold", Config)
		info.sealerMs = Medals.thresholdMs(P, "Sealer", Config)
	end
	DayEvent:FireClient(plr, info)
end

local function useRecord(d: number, rec: any)
	today.record = rec
	today.world = Dungeon.fromRecord(Config, rec)
	worldsByDay[d] = today.world
	today.state = "ready"
	today.message = ""
	dayCopy.Value = HttpService:JSONEncode(rec)
	publishDay()
end

-- (true) when the day is settled one way or the other; (false) when the store failed and a retry is due.
local function loadDay(d: number): boolean
	today.index = d
	today.state = "loading"
	today.record, today.world = nil, nil
	today.message = "Today's Door is being carved..."
	local key = Day.recordKey(d)
	local function studioFallback(): boolean
		if not RunService:IsStudio() then return false end
		local rec = Dungeon.studioDoor(Config, Rng, d, os.time())
		if rec == nil then return false end
		useRecord(d, rec)
		return true
	end
	if daysStore == nil then
		if studioFallback() then return true end
		today.message = "Today's Door is still being carved; retrying"
		publishDay()
		return false
	end
	local okGet, got = pcall(function() return daysStore:GetAsync(key) end)
	if okGet and got ~= nil then
		local valid, why = Dungeon.validate(Config, got, d)
		if valid then
			useRecord(d, got)
			return true
		end
		if type(got) == "table" and got.v ~= Config.Day.RecordVersion then
			today.state = "outdated"
			today.message = "This server is out of date for today's Door; rejoin"
		else
			today.state = "failed"
			today.message = "Today's Door failed its check; runs are closed until a fix"
			warn("[SameDoor] the stored record for day " .. d .. " is invalid: " .. tostring(why))
		end
		publishDay()
		return true -- fail closed: NEVER re-mint over a stored day (that would change a layout mid-day)
	end
	if not okGet then
		if studioFallback() then return true end
		today.message = "Today's Door is still being carved; retrying"
		publishDay()
		return false
	end
	-- nothing stored yet: mint, atomically. UpdateAsync is atomic per key, so two servers racing at
	-- 00:00 both end up holding the ONE record that was written.
	local kept = nil
	local okMint, committed = pcall(function()
		return daysStore:UpdateAsync(key, function(old)
			if old ~= nil then
				kept = old
				return nil -- keep what is there; never overwrite a day
			end
			kept = nil
			local rec = Dungeon.mint(Config, mintDraw(), d, os.time())
			return rec
		end)
	end)
	if not okMint then
		today.message = "Today's Door is still being carved; retrying"
		publishDay()
		return false
	end
	local rec = committed or kept
	local valid, why = Dungeon.validate(Config, rec, d)
	if not valid then
		today.state = "failed"
		today.message = "Today's Door failed its check; runs are closed until a fix"
		warn("[SameDoor] minted or kept record for day " .. d .. " is invalid: " .. tostring(why))
		publishDay()
		return true
	end
	useRecord(d, rec)
	return true
end

local loadingDay = false
local function ensureDay()
	local d = Day.index(os.time(), Config.Day)
	if d == today.index and today.state ~= "loading" then return end
	if loadingDay then return end
	loadingDay = true
	task.spawn(function()
		local tries = 0
		while true do
			local want = Day.index(os.time(), Config.Day)
			if loadDay(want) then break end
			tries += 1
			local sched = Config.Day.RetrySchedule
			task.wait(sched[tries] or Config.Day.RetryEvery)
		end
		loadingDay = false
	end)
end

--============================================================================ profiles
type Profile = {
	data: any,
	canSave: boolean,
	session: string?,
	pendingRuns: number,
	-- Verified finishes not yet in the stored profile (REVIEW-1 finding 3): every commit applies them
	-- inside its transform and drops them only once that write has landed, so one failed save never
	-- loses a run. { id, day, timeMs, medal, at, deferred }
	pendingFinishes: { any },
	posted: any,
	writing: boolean,
	acquiring: boolean,
	loaded: boolean,
	reason: string?,
	-- os.time() at which to try for the session lock again (REVIEW-1 finding 4); nil = never (the
	-- store is missing, or a newer session took the profile over)
	retryAt: number?,
}
local profiles: { [Player]: Profile } = {}

local function profileKey(uid: number): string
	return "u_" .. tostring(uid)
end

-- Take the session lock. "ok" | "locked" (another live session holds it until `lockedUntil`) |
-- "error" (the store call failed). On "ok" and "locked" p.data is the stored copy.
local function acquire(plr: Player, p: Profile): (string, number?)
	local token = HttpService:GenerateGUID(false)
	local status, lockedUntil = "error", nil
	local ok, err = pcall(function()
		playerStore:UpdateAsync(profileKey(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			local held = tonumber(old.lockUntil) or 0
			p.data = Ledger.normalize(old.data, Config)
			if held > now and old.session ~= nil then
				status, lockedUntil = "locked", held
				return nil -- respect the other live session; do not touch its lock
			end
			status = "ok"
			old.session = token
			old.lockUntil = now + Config.Save.SessionLockSeconds
			old.data = p.data
			return old
		end)
	end)
	if not ok then
		warn("[SameDoor] profile load failed for " .. plr.Name .. ": " .. tostring(err))
		return "error", nil
	end
	if status == "ok" then
		p.canSave = true
		p.session = token
		p.reason = nil
		p.retryAt = nil
	end
	return status, lockedUntil
end

local LOCKED_REASON = "Your profile is still open in another server: saving starts when that lock runs out (under a minute). Runs meanwhile are kept."
local LOAD_REASON = "Your profile did not load: retrying. Runs meanwhile are kept and saved once it loads."

local function loadProfile(plr: Player): Profile
	local p: Profile = { data = Ledger.new(Config), canSave = false, session = nil, pendingRuns = 0, pendingFinishes = {},
		posted = nil, writing = false, acquiring = false, loaded = false, reason = nil, retryAt = nil }
	if playerStore == nil then
		p.reason = "Saving is unavailable on this server: runs are shown but not ranked."
		return p
	end
	local status, lockedUntil = acquire(plr, p)
	p.loaded = status ~= "error"
	if status == "error" then
		p.reason = LOAD_REASON
		p.retryAt = os.time() + Config.Save.LockRetrySeconds
	elseif status == "locked" then
		p.reason = LOCKED_REASON
		p.retryAt = math.max((lockedUntil or 0) + 1, os.time() + 1)
	end
	return p
end

-- EVERY profile write goes through here, one at a time per player: the stored copy is the truth, and
-- memory is the last committed copy plus pending run counts and pending finishes. Inside the
-- transform (which may run more than once, so it depends only on the stored copy and the snapshots
-- taken before it) the pending runs are counted and the pending finishes applied with
-- Ledger.applyFinish, the ONLY place a medal, a Door day or a streak moves. OWNERSHIP (fork-tower
-- REVIEW-4 §10): the write lands only while the record still carries this session's token.
-- (ok, applied) where applied = { { finish, res } } for the finishes this write carried.
local function commit(plr: Player, release: boolean): (boolean, { any })
	local p = profiles[plr]
	if p == nil or not p.canSave or playerStore == nil then return false, {} end
	local waited = 0
	while p.writing and waited < 15 do
		task.wait(0.1)
		waited += 0.1
	end
	if p.writing then return false, {} end
	p.writing = true
	local applied = p.pendingRuns
	local finishes = table.clone(p.pendingFinishes)
	local posted = p.posted
	local runDay = Day.index(os.time(), Config.Day)
	local results, lost = {}, false
	local ok, committed = pcall(function()
		return playerStore:UpdateAsync(profileKey(plr.UserId), function(old)
			old = old or {}
			if old.session ~= p.session then
				lost = true
				return nil
			end
			lost = false
			local data = Ledger.normalize(old.data, Config)
			for _ = 1, applied do Ledger.noteRunStart(data, runDay) end
			results = {}
			for k, f in finishes do
				results[k] = Ledger.applyFinish(data, { day = f.day, timeMs = f.timeMs, medal = f.medal, at = f.at }, Config, Medals)
			end
			if posted then Ledger.markPosted(data, posted.day, posted.ms) end
			old.data = data
			old.lockUntil = if release then 0 else os.time() + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	p.writing = false
	if lost then
		p.canSave = false
		p.retryAt = nil
		p.reason = "A newer session took over your profile; this one no longer saves."
		warn("[SameDoor] " .. plr.Name .. ": a newer session owns the profile; this one stops writing")
		return false, {}
	end
	if not ok or type(committed) ~= "table" then
		return false, {}
	end
	p.data = Ledger.normalize(committed.data, Config)
	p.pendingRuns -= applied
	-- drop exactly the finishes this write carried (a finish that arrived during it stays pending)
	local out = {}
	for k, f in finishes do
		table.remove(p.pendingFinishes, table.find(p.pendingFinishes, f) :: number)
		f.res = results[k] -- whichever commit carried it, the finish knows it landed and what it did
		table.insert(out, { finish = f, res = results[k] })
	end
	return true, out
end

--============================================================================ leaderstats + torch
local function formatBest(p: Profile?): string
	if p == nil then return "--" end
	local d = Day.index(os.time(), Config.Day)
	if p.data.today.day ~= d or p.data.today.bestMs == nil then return "--" end
	return Medals.formatTime(p.data.today.bestMs)
end

local function refreshStats(plr: Player)
	local p = profiles[plr]
	local ls = plr:FindFirstChild("leaderstats")
	if ls == nil or p == nil then return end
	local best = ls:FindFirstChild("Best")
	local streak = ls:FindFirstChild("Streak")
	if best then best.Value = formatBest(p) end
	-- the streak as of today: a stored streak that broke days ago shows 0 (REVIEW-1)
	if streak then streak.Value = Ledger.liveStreak(p.data.life, Day.index(os.time(), Config.Day)) end
end

local function refreshTorch(plr: Player)
	local p = profiles[plr]
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp == nil then return end
	local torch = hrp:FindFirstChild("Torch")
	if torch == nil then
		torch = make("PointLight", hrp, { Name = "Torch", Range = 16, Brightness = 1.2, Shadows = false })
	end
	local rank = if p then Medals.rank(p.data.life, Config) else 0
	torch.Color = rgb(Medals.torch(rank, Config))
end

--============================================================================ the board
local nameCache = Board.newNameCache()
local function nameOf(uid: number): string
	local cached = Board.cachedName(nameCache, uid)
	if cached then return cached end
	local plr = Players:GetPlayerByUserId(uid)
	local name = if plr then plr.Name else nil
	if name == nil then
		local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
		name = if ok and type(n) == "string" then n else ("Player " .. uid)
	end
	Board.rememberName(nameCache, uid, name :: string, Config.Board)
	return name :: string
end

local function gradeFor(dayIndex: number): (number) -> string?
	local w = worldsByDay[dayIndex]
	return function(t: number): string?
		if w == nil then return nil end
		return Medals.grade(t, w.perfectMs, Config)
	end
end

local publicCache = { at = nil :: number?, day = -1, rows = {} :: { any } }
local yesterdayCache = { at = nil :: number?, day = -1, rows = {} :: { any } }

local function fetchTop(dayIndex: number, size: number): { any }?
	local store = boardStore(dayIndex)
	if store == nil then return nil end
	local ok, pages = pcall(function() return store:GetSortedAsync(false, size) end)
	if not ok or pages == nil then return nil end
	local okPage, page = pcall(function() return pages:GetCurrentPage() end)
	if not okPage then return nil end
	return Board.rows(page, nameOf, gradeFor(dayIndex), Config.Board)
end

local function sendPublic(target: Player?)
	local payload = { mode = "public", day = today.index, door = Day.doorNumber(today.index, Config.Day), rows = publicCache.rows,
		empty = Config.Board.EmptyPublic }
	if target then BoardEvent:FireClient(target, payload) else BoardEvent:FireAllClients(payload) end
end

local function sendYesterday(target: Player?)
	local payload = { mode = "yesterday", day = today.index - 1, rows = yesterdayCache.rows }
	if target then BoardEvent:FireClient(target, payload) else BoardEvent:FireAllClients(payload) end
end

local function refreshPublic(force: boolean?)
	if today.state ~= "ready" then return end
	local t = now()
	if not force and publicCache.day == today.index and Board.fresh(publicCache.at, t, Config.Board.PublicCacheSeconds) then return end
	local rows = fetchTop(today.index, Config.Board.PublicSize)
	if rows then
		publicCache.rows = rows
		publicCache.day = today.index
		publicCache.at = t
		sendPublic(nil)
	end
end

local function refreshYesterday()
	local t = now()
	if yesterdayCache.day == today.index - 1 and Board.fresh(yesterdayCache.at, t, Config.Board.YesterdayCacheSeconds) then return end
	local rows = fetchTop(today.index - 1, Config.Board.YesterdaySize)
	if rows then
		yesterdayCache.rows = rows
		yesterdayCache.day = today.index - 1
		yesterdayCache.at = t
		sendYesterday(nil)
	end
end

-- Friends: fetched only on demand (the board toggle), capped, one ordered GetAsync per friend while
-- the GetAsync budget stays above the reserve, cached per player.
local friendsCache: { [Player]: { at: number, day: number, rows: { any }, partial: boolean } } = {}
local friendsBusy: { [Player]: boolean } = {}
local boardMode: { [Player]: string } = {}

local function budget(): number?
	local ok, b = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return if ok then b else nil
end

local function sendFriends(plr: Player)
	local cached = friendsCache[plr]
	if cached and cached.day == today.index and Board.fresh(cached.at, now(), Config.Board.FriendsCacheSeconds) then
		BoardEvent:FireClient(plr, { mode = "friends", day = today.index, rows = cached.rows, partial = cached.partial,
			empty = Config.Board.EmptyFriends })
		return
	end
	if friendsBusy[plr] then return end -- one fetch at a time per player; spam toggling costs nothing
	friendsBusy[plr] = true
	BoardEvent:FireClient(plr, { mode = "friends", day = today.index, loading = true, rows = {}, text = "Loading friends..." })
	local ids = { plr.UserId }
	local okF, pages = pcall(function() return Players:GetFriendsAsync(plr.UserId) end)
	if okF and pages then
		while #ids < Config.Board.FriendsCap + 1 do
			local okP, page = pcall(function() return pages:GetCurrentPage() end)
			if not okP or type(page) ~= "table" then break end
			for _, f in page do
				local id = tonumber(f.Id)
				if id then table.insert(ids, id) end
			end
			if pages.IsFinished then break end
			local okA = pcall(function() pages:AdvanceToNextPageAsync() end)
			if not okA then break end
		end
	end
	local capped = { ids[1] }
	for _, id in Board.capFriends({ table.unpack(ids, 2) }, Config.Board) do table.insert(capped, id) end
	local store = boardStore(today.index)
	local found, partial = {}, not okF
	for n, id in capped do
		if store == nil then partial = true; break end
		if not Board.mayRead(budget(), Config.Board) then partial = true; break end
		local okG, v = pcall(function() return store:GetAsync(Board.key(id)) end)
		if okG and type(v) == "number" then table.insert(found, { userId = id, value = v }) end
		if n % 20 == 0 then
			BoardEvent:FireClient(plr, { mode = "friends", day = today.index, loading = true, rows = {},
				text = string.format("Loading friends %d/%d", n, #capped) })
		end
	end
	local entries = {}
	for _, e in Board.sortFound(found) do
		table.insert(entries, { key = Board.key(e.userId), value = e.value })
	end
	local rows = Board.rows(entries, nameOf, gradeFor(today.index), Config.Board)
	friendsCache[plr] = { at = now(), day = today.index, rows = rows, partial = partial }
	friendsBusy[plr] = nil
	BoardEvent:FireClient(plr, { mode = "friends", day = today.index, rows = rows, partial = partial, empty = Config.Board.EmptyFriends })
end

boardPrompt.Triggered:Connect(function(plr: Player)
	if plr == nil or plr.Parent ~= Players then return end
	local mode = if boardMode[plr] == "friends" then "public" else "friends"
	boardMode[plr] = mode
	if mode == "friends" then
		task.spawn(sendFriends, plr)
	else
		sendPublic(plr)
	end
end)

local function postBest(plr: Player, dayIndex: number, timeMs: number, at: number): boolean
	local world = worldsByDay[dayIndex]
	if world and world.studio then return false end
	local value = Board.encode(timeMs, at, Config.Board)
	local store = boardStore(dayIndex)
	if value == nil or store == nil then return false end
	local ok = pcall(function()
		store:UpdateAsync(Board.key(plr.UserId), Board.improve(value :: number))
	end)
	if ok then
		local p = profiles[plr]
		if p then p.posted = { day = dayIndex, ms = timeMs } end
		friendsCache[plr] = nil
	end
	return ok
end

-- After a commit: post what the finishes it carried changed (a late finish to its own day's board,
-- otherwise today's best if it improved), and tell the player about finishes that had to wait for a
-- later save (a failed save, a lock that was still held). { [finish] = true } for those posted.
local function settle(plr: Player, applied: { any }): { [any]: boolean }
	local p = profiles[plr]
	local posted = {}
	local any = false
	for _, a in applied do
		local f, res = a.finish, a.res
		local ok = false
		if res.late then
			ok = postBest(plr, f.day, f.timeMs, f.at)
		elseif p and Ledger.needsPost(p.data, f.day) then
			ok = postBest(plr, f.day, p.data.today.bestMs, p.data.today.bestAt)
		end
		if ok then
			posted[f] = true
			f.posted = true
			any = true
		end
		if f.deferred and plr.Parent == Players then
			toast(plr, string.format("Your %s run of %s is saved%s.", tostring(f.medal), Medals.formatDuration(f.timeMs),
				if ok then " and on today's board" else ""))
			if res.firstSealer then toast(plr, "THE DOOR IS SEALED: your first Sealer run is saved.") end
		end
	end
	if #applied > 0 and plr.Parent == Players then
		refreshStats(plr)
		refreshTorch(plr)
	end
	if any then task.spawn(refreshPublic, true) end
	return posted
end

-- Every save outside a finish (autosave, leaving, the server closing, a lock just taken).
local function save(plr: Player, release: boolean): boolean
	local ok, applied = commit(plr, release)
	if ok then settle(plr, applied) end
	return ok
end

-- A session that found its profile locked (or failed to load it) tries again: just after the other
-- lock runs out, or every LockRetrySeconds after an error (REVIEW-1 finding 4). The first build never
-- retried, so one failed release on leaving cost the whole next session.
local function retryLock(plr: Player, p: Profile)
	if p.acquiring or p.canSave or p.retryAt == nil or playerStore == nil then return end
	p.acquiring = true
	local status, lockedUntil = acquire(plr, p)
	p.acquiring = false
	if profiles[plr] ~= p or plr.Parent ~= Players then
		-- the player left while the lock was being taken: give it straight back
		if status == "ok" then
			profiles[plr] = p
			commit(plr, true)
			profiles[plr] = nil
		end
		return
	end
	if status == "ok" then
		p.loaded = true
		toast(plr, "Your profile is loaded now: this session saves and ranks, the runs you finished while waiting too.")
		save(plr, false)
		refreshStats(plr)
		refreshTorch(plr)
	elseif status == "locked" then
		p.loaded = true
		p.retryAt = math.max((lockedUntil or 0) + 1, os.time() + 1)
	else
		p.retryAt = os.time() + Config.Save.LockRetrySeconds
	end
end

--============================================================================ runs
type Run = {
	id: string,
	lane: number,
	origin: Vector3,
	day: number,
	world: any,
	state: any,
	busy: boolean,
}
local runs: { [Player]: Run } = {}
local lastRemote: { [Player]: { [string]: number } } = {}
local runCounter = 0

local function rateOk(plr: Player, what: string): boolean
	local t = now()
	local m = lastRemote[plr]
	if m == nil then
		m = {}
		lastRemote[plr] = m
	end
	if m[what] and t - m[what] < Config.Limits.RemoteMinInterval then return false end
	m[what] = t
	return true
end

local function payloadCells(run: Run, cells: { number }): { any }
	local out = {}
	for _, c in cells do table.insert(out, Dungeon.cellPayload(run.world, c)) end
	return out
end

local function sendCells(plr: Player, run: Run, cells: { number })
	if #cells == 0 then return end
	CellEvent:FireClient(plr, { run = run.id, cells = payloadCells(run, cells) })
end

local function medalTimes(world: any): any
	local P = world.perfectMs
	return { perfectMs = P, silverMs = Medals.thresholdMs(P, "Silver", Config), goldMs = Medals.thresholdMs(P, "Gold", Config),
		sealerMs = Medals.thresholdMs(P, "Sealer", Config) }
end

local function allocLane(plr: Player): number?
	local i = laneOf[plr]
	if i then return i end
	i = table.remove(freeLanes)
	if i then laneOf[plr] = i end
	return i
end

-- A lane is held from the arch until its player is back in the hub (Leave run, the Hub button, death,
-- a reset, leaving the game). The first build held it for the whole session, so after 12 players had
-- each run once a 13th could never run (REVIEW-1, reviewer 2). Standing on the finish or void card
-- keeps it: Run again reuses it.
local function freeLane(plr: Player)
	local lane = laneOf[plr]
	if lane then
		laneOf[plr] = nil
		table.insert(freeLanes, lane)
	end
end

local function pivot(plr: Player, cf: CFrame)
	local char = plr.Character
	if char then char:PivotTo(cf) end
end

local SEAL_TOASTS = { "1/3 Seals. The moss wakes.", "2/3 Seals. Crystal seams glitter.", "3/3 Seals. The Door is awake!" }

local function startRun(plr: Player): boolean
	if today.state ~= "ready" or today.world == nil then
		toast(plr, today.message ~= "" and today.message or "Today's Door is still being carved; retrying")
		return false
	end
	local existing = runs[plr]
	if existing and (existing.state.phase == "ready" or existing.state.phase == "running") then
		toast(plr, "You are already in a run.")
		return false
	end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char == nil or char.Parent == nil or hum == nil or hum.Health <= 0 then
		toast(plr, "Your character is still loading. Try again in a moment.")
		return false
	end
	local lane = allocLane(plr)
	if lane == nil then
		toast(plr, string.format("All %d lanes are in runs right now. One frees as soon as a player is back in the hub.", Config.World.MaxLanes))
		return false
	end
	buildLane(lane)
	runCounter += 1
	local world = today.world
	local run: Run = {
		id = tostring(runCounter) .. "-" .. HttpService:GenerateGUID(false),
		lane = lane,
		origin = laneOrigin(lane),
		day = today.index,
		world = world,
		state = RunState.new(Config, world, DEPS),
		busy = false,
	}
	runs[plr] = run
	pivot(plr, antechamberCFrame(lane))
	local p = profiles[plr]
	if p then p.pendingRuns += 1 end
	local first = RunState.arrive(run.state)
	local o = run.origin
	local mt = medalTimes(world)
	RunEvent:FireClient(plr, {
		run = run.id, state = "ready", seals = 0, door = Day.doorNumber(run.day, Config.Day),
		origin = { x = o.X, y = o.Y, z = o.Z }, perfectMs = mt.perfectMs, silverMs = mt.silverMs, goldMs = mt.goldMs,
		sealerMs = mt.sealerMs, studio = world.studio, unranked = world.studio or not (p and p.canSave),
		reason = if world.studio then "Studio door (unranked)"
			elseif p == nil then "Your profile is still loading: this run is shown but not saved."
			elseif not p.canSave then p.reason else nil,
		hazards = #world.hazards,
	})
	for _, e in first do
		if e.type == "reveal" then sendCells(plr, run, e.cells) end
	end
	return true
end

local function endRun(plr: Player, why: string)
	local run = runs[plr]
	if run == nil then return end
	runs[plr] = nil
	RunEvent:FireClient(plr, { run = run.id, state = "ended", why = why })
end

local function finishRun(plr: Player, run: Run, timeMs: number)
	run.busy = true
	pivot(plr, sanctumCFrame(run.lane))
	local p = profiles[plr]
	local world = run.world
	local medal = Medals.grade(timeMs, world.perfectMs, Config) or "Bronze"
	local at = os.time()
	local result = nil
	local unrankedReason = nil
	local posted = false
	if world.studio then
		unrankedReason = "Studio door: nothing is saved or ranked."
	elseif p == nil or (not p.canSave and p.retryAt == nil) then
		-- this session can never save (no store, or a newer session owns the profile)
		unrankedReason = (p and p.reason) or "Your profile is not loaded: this run is shown but not saved."
	else
		-- the finish waits in memory until a write that carries it LANDS (REVIEW-1 finding 3)
		local f = { id = run.id, day = run.day, timeMs = timeMs, medal = medal, at = at, deferred = false }
		table.insert(p.pendingFinishes, f)
		if p.canSave then
			local ok, applied = commit(plr, false)
			if ok then settle(plr, applied) end
		end
		-- f.res is set by whichever commit carried f: this one, or an autosave that took it while this
		-- one waited for the write lock
		if f.res then
			result = f.res
			posted = f.posted == true
		end
		if result == nil then
			f.deferred = true
			unrankedReason = if p.canSave
				then "Saving failed just now. This run is kept and saved at the next try (within 20 s)."
				else p.reason
		end
	end
	refreshStats(plr)
	refreshTorch(plr)
	local rank = if p then Medals.rank(p.data.life, Config) else 0
	local nowDay = Day.index(os.time(), Config.Day)
	RunEvent:FireClient(plr, {
		run = run.id, state = "finished", seals = 3, timeMs = timeMs, medal = medal,
		door = Day.doorNumber(run.day, Config.Day),
		bestMs = if p and p.data.today.day == run.day then p.data.today.bestMs else timeMs,
		improved = result and result.improved or false,
		streak = if p then Ledger.liveStreak(p.data.life, Day.index(os.time(), Config.Day)) else 0,
		rank = rank, rankLabel = Medals.rankLabel(rank, Config), rankUp = result and result.rankUp or false,
		brag = result and result.firstSealer or false,
		unranked = unrankedReason ~= nil, reason = unrankedReason, posted = posted,
		newDoor = if nowDay ~= run.day then Day.doorNumber(nowDay, Config.Day) else nil,
		perfectMs = world.perfectMs,
	})
	run.busy = false
end

local function onEvents(plr: Player, run: Run, events: { any })
	for _, e in events do
		if e.type == "reveal" then
			sendCells(plr, run, e.cells)
		elseif e.type == "start" then
			RunEvent:FireClient(plr, { run = run.id, state = "running", seals = 0 })
		elseif e.type == "seal" then
			local s = run.world.seals[e.seal]
			local W = run.world.W
			RunEvent:FireClient(plr, { run = run.id, state = "running", seals = e.count, taken = { x = s % W, y = s // W } })
			toast(plr, SEAL_TOASTS[e.count] or "A Seal!")
		elseif e.type == "doorLocked" then
			toast(plr, string.format("The Door needs 3 Seals (%d/3)", e.count))
		elseif e.type == "finish" then
			task.spawn(finishRun, plr, run, e.timeMs)
		elseif e.type == "void" then
			RunEvent:FireClient(plr, { run = run.id, state = "void", reason = e.reason })
			toast(plr, e.reason)
		end
	end
end

-- The run monitor: every Heartbeat, every live run, the server's own sample of the root.
RunService.Heartbeat:Connect(function(dt: number)
	for plr, run in runs do
		local st = run.state
		if st.phase == "ready" or st.phase == "running" then
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp == nil or char.Parent == nil then
				endRun(plr, "character")
			else
				local pos = (hrp :: BasePart).Position
				local o = run.origin
				onEvents(plr, run, RunState.step(st, dt, pos.X - o.X, pos.Y - o.Y, pos.Z - o.Z))
			end
		end
	end
end)

--============================================================================ remotes from clients
-- None carries a time, a position, a seal or a finish. Each is rate-limited and state-checked, and
-- every refusal says why.
LeaveEvent.OnServerEvent:Connect(function(plr: Player)
	if not rateOk(plr, "leave") then toast(plr, "One moment..."); return end
	local run = runs[plr]
	if run == nil or not (run.state.phase == "ready" or run.state.phase == "running") then
		toast(plr, "You are not in a run.")
		return
	end
	endRun(plr, "leave")
	pivot(plr, campCFrame())
	freeLane(plr)
end)

RunAgainEvent.OnServerEvent:Connect(function(plr: Player)
	if not rateOk(plr, "again") then toast(plr, "One moment..."); return end
	local run = runs[plr]
	if run and run.busy then toast(plr, "Saving your run..."); return end
	if run and (run.state.phase == "ready" or run.state.phase == "running") then
		toast(plr, "You are already in a run.")
		return
	end
	startRun(plr)
end)

HubEvent.OnServerEvent:Connect(function(plr: Player)
	if not rateOk(plr, "hub") then toast(plr, "One moment..."); return end
	local run = runs[plr]
	if run and (run.state.phase == "ready" or run.state.phase == "running") then
		toast(plr, "Use the pause button to leave a run.")
		return
	end
	runs[plr] = nil
	pivot(plr, hubCFrame())
	freeLane(plr)
	RunEvent:FireClient(plr, { state = "hub" })
end)

archPrompt.Triggered:Connect(function(plr: Player)
	if plr == nil or plr.Parent ~= Players then return end
	startRun(plr)
end)

--============================================================================ players
local function onCharacter(plr: Player, char: Model)
	-- No CFrame write here, ever: the engine places the character on HubSpawn (RespawnLocation).
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum.WalkSpeed = Config.Walk.Speed
		hum.Died:Connect(function()
			if runs[plr] and (runs[plr].state.phase == "ready" or runs[plr].state.phase == "running") then
				endRun(plr, "died")
			end
			freeLane(plr) -- the next character spawns in the hub
		end)
	end
	refreshTorch(plr)
end

local function onPlayerAdded(plr: Player)
	plr.RespawnLocation = hubSpawn
	local ls = make("Folder", plr, { Name = "leaderstats" })
	make("StringValue", ls, { Name = "Best", Value = "--" })
	make("IntValue", ls, { Name = "Streak", Value = 0 })
	plr.CharacterAdded:Connect(function(char) onCharacter(plr, char) end)
	plr.CharacterRemoving:Connect(function()
		if runs[plr] and (runs[plr].state.phase == "ready" or runs[plr].state.phase == "running") then
			endRun(plr, "character")
		end
		freeLane(plr) -- the next character spawns in the hub
	end)
	if plr.Character then task.spawn(onCharacter, plr, plr.Character) end
	dayInfoFor(plr)
	sendPublic(plr)
	sendYesterday(plr)
	local p = loadProfile(plr)
	if plr.Parent ~= Players then
		-- the player left while the profile loaded: PlayerRemoving found nothing to release, so give
		-- back the lock this load just took (it would otherwise block the next join for 45 s)
		if p.canSave then
			profiles[plr] = p
			commit(plr, true)
			profiles[plr] = nil
		end
		return
	end
	profiles[plr] = p
	refreshStats(plr)
	refreshTorch(plr)
	if p.reason then toast(plr, p.reason) end
	-- a best that never reached the board (a throttled write, a crash) is posted again
	local d = Day.index(os.time(), Config.Day)
	if p.canSave and Ledger.needsPost(p.data, d) and worldsByDay[d] then
		postBest(plr, d, p.data.today.bestMs, p.data.today.bestAt)
	end
end

local function onPlayerRemoving(plr: Player)
	runs[plr] = nil
	save(plr, true)
	profiles[plr] = nil
	friendsCache[plr] = nil
	friendsBusy[plr] = nil
	boardMode[plr] = nil
	lastRemote[plr] = nil
	freeLane(plr)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do task.spawn(onPlayerAdded, plr) end

game:BindToClose(function()
	for _, plr in Players:GetPlayers() do
		save(plr, true)
	end
end)

--============================================================================ loops
ensureDay()

-- the clock: once a second, a new UTC day loads the new Door (runs in progress keep theirs)
task.spawn(function()
	while true do
		task.wait(1)
		local before = today.index
		ensureDay()
		if today.index ~= before then
			publicCache.at = nil
			yesterdayCache.at = nil
			for _, plr in Players:GetPlayers() do refreshStats(plr) end -- "Best" is today's best
		end
	end
end)

-- autosave under the session lock (20 s save, 45 s lock: the save is always shorter than the lock)
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for _, plr in Players:GetPlayers() do
			task.spawn(save, plr, false)
		end
	end
end)

-- a session waiting for its profile lock tries again when it is due (REVIEW-1 finding 4)
task.spawn(function()
	while true do
		task.wait(1)
		local t = os.time()
		for plr, p in profiles do
			if not p.canSave and p.retryAt ~= nil and t >= p.retryAt and not p.acquiring then
				task.spawn(retryLock, plr, p)
			end
		end
	end
end)

-- the boards: public every PublicCacheSeconds, yesterday hourly
task.spawn(function()
	while true do
		refreshPublic(false)
		refreshYesterday()
		task.wait(5)
	end
end)
