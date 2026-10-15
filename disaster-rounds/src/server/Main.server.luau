-- DISASTER ROUNDS - server, authoritative. Lives in ServerScriptService.
--
-- The core loop (DESIGN.md §1): every 88 s everyone who is not on a break is dropped onto a freshly generated island,
-- the disaster is named 4 s later, and for 60 s every danger is drawn in red first, exactly where it hits. One hit
-- sends you back to the Lookout until the next round. Surviving raises your streak; Heat aims more rings at you.
--
-- This file is the ONLY place that knows Roblox exists. The rules live in the pure, spec-tested modules in
-- ReplicatedStorage (MapGen, Round, Zones, Strikes, Flood, Tornado, Quake, Guard, Progress, Board) and this file turns
-- them into Parts, attributes and remote calls. Deliberate choices, each from a defect this repo has shipped before:
--   * the next island is built under ServerStorage and parented only after the roster freezes (anomaly-observatory
--     CLAUDE.md "ServerStorage, not the zone"): nothing about a round is visible while a player can still sit it out;
--   * the disaster draws from its own Random, made fresh each round, never the map's; no seed exists anywhere a client
--     can see (fork-tower REVIEW-4);
--   * the engine places a spawning character AFTER CharacterAdded (robloxemu/SPAWN-ORDER.md): RespawnLocation points
--     at LookoutSpawn before any yield, and nothing writes a CFrame inside CharacterAdded before the parent arrives;
--   * every DataStore call is pcall'd, every write carries the session's owner token, a failed load writes nothing;
--   * no silent no-ops: every refused request gets a Toast that says why.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService") -- GenerateGUID only (session tokens); no HTTP

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local MapGen = require(ReplicatedStorage:WaitForChild("MapGen"))
local Round = require(ReplicatedStorage:WaitForChild("Round"))
local Zones = require(ReplicatedStorage:WaitForChild("Zones"))
local Strikes = require(ReplicatedStorage:WaitForChild("Strikes"))
local Flood = require(ReplicatedStorage:WaitForChild("Flood"))
local Tornado = require(ReplicatedStorage:WaitForChild("Tornado"))
local Quake = require(ReplicatedStorage:WaitForChild("Quake"))
local Guard = require(ReplicatedStorage:WaitForChild("Guard"))
local Progress = require(ReplicatedStorage:WaitForChild("Progress"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

-- Calm Cove's light, so the first frame is already band 1 (the client's bands take over from here, Sky.client).
Fx.applyLighting(Fx.Presets.Coast)

local IC, RC, LC = Config.Island, Config.Round, Config.Lookout
local HALF = MapGen.halfSize(IC)
local RING_R = Zones.ringRadius(Config)
local FUNNEL_R = Zones.funnelRadius(Config)

local function now(): number
	return tick() -- os.clock would freeze every timer headless (deep-vein Main.server.luau)
end

-- Stand at `pos`, facing the island's centre. CFrame.lookAt toward the point you stand on is NaN (fairness check
-- 2026-10-07: every player dropped on the centre cell became an unhittable NaN body), so the centre faces +X.
local function facingCentre(pos: Vector3): CFrame
	local flat = Vector3.new(-pos.X, 0, -pos.Z)
	if flat.Magnitude < 0.5 then return CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)) end
	return CFrame.lookAt(pos, pos + flat.Unit)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local RED = Color3.fromRGB(255, 40, 40) -- the only "it hits here" colour in the game

--============================================================================== remotes

local remotes = Instance.new("Folder")
remotes.Name = "DRRemotes"
remotes.Parent = ReplicatedStorage
local function mk(n: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
	return r
end
local ToastEvent = mk("Toast") -- server -> client: a short line of text
local CardEvent = mk("Card") -- server -> client: (kind, data) a centre card (name, survived, swept, practice, brag)
local BoardEvent = mk("Board") -- server -> client: { viewer, mode, rows, note }
local JumpInEvent = mk("JumpIn") -- client -> server: practice drop-in
local SetRestEvent = mk("SetRest") -- client -> server: (on: boolean)

local function toast(plr: Player, text: string)
	ToastEvent:FireClient(plr, text)
end

--============================================================================== the world: the Lookout

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local lookout = Instance.new("Model")
lookout.Name = "Lookout"
local DECK_CX, DECK_CZ = (LC.MinX + LC.MaxX) / 2, (LC.MinZ + LC.MaxZ) / 2
local DECK_W, DECK_D = LC.MaxX - LC.MinX, LC.MaxZ - LC.MinZ
do
	local deck = part({ Name = "Deck", Size = Vector3.new(DECK_W, 2, DECK_D), Position = Vector3.new(DECK_CX, LC.FloorY - 1, DECK_CZ),
		Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(150, 112, 78) })
	deck.Parent = lookout
	-- the cliff the deck stands on: a stone column down to the sea
	local cliff = part({ Name = "Cliff", Size = Vector3.new(DECK_W + 6, LC.FloorY + 10, DECK_D + 6),
		Position = Vector3.new(DECK_CX - 2, (LC.FloorY - 2 - 12) / 2, DECK_CZ), Material = Enum.Material.Slate,
		Color = Color3.fromRGB(110, 106, 100) })
	cliff.Parent = lookout
	-- a 4-stud rail you can see, and invisible walls you cannot jump over (a default jump clears the rail)
	local railY = LC.FloorY + LC.RailHeight / 2
	local wallY = LC.FloorY + LC.WallHeight / 2
	local edges = {
		{ "North", Vector3.new(DECK_W, 0, 0.6), Vector3.new(DECK_CX, 0, LC.MinZ + 0.3) },
		{ "South", Vector3.new(DECK_W, 0, 0.6), Vector3.new(DECK_CX, 0, LC.MaxZ - 0.3) },
		{ "West", Vector3.new(0.6, 0, DECK_D), Vector3.new(LC.MinX + 0.3, 0, DECK_CZ) },
		{ "East", Vector3.new(0.6, 0, DECK_D), Vector3.new(LC.MaxX - 0.3, 0, DECK_CZ) },
	}
	for _, e in edges do
		local rail = part({ Name = "Rail" .. e[1], Size = Vector3.new(math.max(e[2].X, 0.6), 0.5, math.max(e[2].Z, 0.6)),
			Position = Vector3.new(e[3].X, LC.FloorY + LC.RailHeight, e[3].Z), Material = Enum.Material.Wood,
			Color = Color3.fromRGB(120, 86, 58) })
		rail.Parent = lookout
		local low = part({ Name = "RailLow" .. e[1], Size = Vector3.new(math.max(e[2].X, 0.6), 0.4, math.max(e[2].Z, 0.6)),
			Position = Vector3.new(e[3].X, LC.FloorY + LC.RailHeight / 2, e[3].Z), Material = Enum.Material.Wood,
			Color = Color3.fromRGB(120, 86, 58) })
		low.Parent = lookout
		local wall = part({ Name = "Wall" .. e[1], Size = Vector3.new(math.max(e[2].X, 1), LC.WallHeight, math.max(e[2].Z, 1)),
			Position = Vector3.new(e[3].X, wallY, e[3].Z), Transparency = 1, CanCollide = true, CanQuery = false, CanTouch = false })
		wall.Parent = lookout
		local _ = railY
	end
	-- posts every 6 studs along the rail
	local n = 0
	for x = LC.MinX, LC.MaxX, 5 do
		for _, z in { LC.MinZ + 0.3, LC.MaxZ - 0.3 } do
			n += 1
			part({ Name = "Post" .. n, Size = Vector3.new(0.6, LC.RailHeight, 0.6), Position = Vector3.new(x, LC.FloorY + LC.RailHeight / 2, z),
				Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 78, 52) }).Parent = lookout
		end
	end
	for z = LC.MinZ + 6, LC.MaxZ - 6, 6 do
		for _, x in { LC.MinX + 0.3, LC.MaxX - 0.3 } do
			n += 1
			part({ Name = "Post" .. n, Size = Vector3.new(0.6, LC.RailHeight, 0.6), Position = Vector3.new(x, LC.FloorY + LC.RailHeight / 2, z),
				Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 78, 52) }).Parent = lookout
		end
	end
	-- two lamps with a warm glow, so the deck reads at night (bands 4-5)
	for k, z in { LC.MinZ + 3, LC.MaxZ - 3 } do
		local lamp = part({ Name = "Lamp" .. k, Size = Vector3.new(0.8, 7, 0.8), Position = Vector3.new(LC.MaxX - 2, LC.FloorY + 3.5, z),
			Material = Enum.Material.Metal, Color = Color3.fromRGB(60, 60, 66) })
		lamp.Parent = lookout
		local bulb = part({ Name = "Bulb" .. k, Size = Vector3.new(1.4, 1.4, 1.4), Shape = Enum.PartType.Ball,
			Position = Vector3.new(LC.MaxX - 2, LC.FloorY + 7.4, z), Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 214, 140), CanCollide = false, CanQuery = false })
		bulb.Parent = lookout
		Fx.attachGlow(bulb, Color3.fromRGB(255, 200, 130), 1.4, 18)
	end
end

-- THE spawn. The engine places every character on it, at every spawn and respawn (SPAWN-ORDER §3, preferred pattern).
local spawnPos = Vector3.new(LC.SpawnPos[1], LC.SpawnPos[2], LC.SpawnPos[3])
local lookoutSpawn = Instance.new("SpawnLocation")
lookoutSpawn.Name = "LookoutSpawn"
lookoutSpawn.Anchored = true
lookoutSpawn.Size = Vector3.new(6, 1, 6)
lookoutSpawn.CFrame = CFrame.lookAt(spawnPos, spawnPos + Vector3.new(1, 0, 0)) -- faces +X: the island
lookoutSpawn.Enabled = true
lookoutSpawn.Neutral = true
lookoutSpawn.Duration = 0
lookoutSpawn.Material = Enum.Material.SmoothPlastic
lookoutSpawn.Color = Color3.fromRGB(70, 150, 170)
lookoutSpawn.Parent = lookout
lookout.Parent = workspace

-- where swept-out players and the outro return land: spots on the deck, facing the island
local RETURN_SPOTS = {
	Vector3.new(-68, 0, -9), Vector3.new(-68, 0, -3), Vector3.new(-68, 0, 3), Vector3.new(-68, 0, 9),
	Vector3.new(-77, 0, -12), Vector3.new(-77, 0, -7), Vector3.new(-77, 0, 7), Vector3.new(-77, 0, 12),
}
local returnIdx = 0
local function lookoutCFrame(): CFrame
	returnIdx = returnIdx % #RETURN_SPOTS + 1
	local s = RETURN_SPOTS[returnIdx]
	local p = Vector3.new(s.X, LC.FloorY + 3, s.Z)
	return CFrame.lookAt(p, p + Vector3.new(1, 0, 0))
end
local function onLookout(pos: Vector3): boolean
	return pos.X >= LC.MinX - 1 and pos.X <= LC.MaxX + 1 and pos.Z >= LC.MinZ - 1 and pos.Z <= LC.MaxZ + 1
		and pos.Y > LC.FloorY - 4
end

--============================================================================== the world: the round's stage

local roundFolder = Instance.new("Folder")
roundFolder.Name = "Round"
roundFolder.Parent = workspace
local ringsFolder = Instance.new("Folder")
ringsFolder.Name = "Rings"
ringsFolder.Parent = roundFolder

-- the island's invisible walls: a dodge or a jump never ends in the sea (holes and water are the only ways off)
do
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	local h = IC.WallHeight
	local yc = IC.ColumnBottomY + h / 2
	local w = IC.WallHalf
	for k, spec in { { w, 0, 1, 2 * w + 2 }, { -w, 0, 1, 2 * w + 2 }, { 0, w, 2 * w + 2, 1 }, { 0, -w, 2 * w + 2, 1 } } do
		part({ Name = "Wall" .. k, Size = Vector3.new(spec[3], h, spec[4]), Position = Vector3.new(spec[1], yc, spec[2]),
			Transparency = 1, CanCollide = true, CanQuery = false, CanTouch = false }).Parent = walls
	end
	walls.Parent = roundFolder
end

-- the sea: one big translucent sheet, never collidable (you sink, and below FallOutY you are out)
local seaPart = part({ Name = "Sea", Size = Vector3.new(1200, 1, 1200), Position = Vector3.new(0, IC.SeaY - 0.5, 0),
	Material = Enum.Material.Glass, Color = Color3.fromRGB(64, 190, 200), Transparency = 0.35,
	CanCollide = false, CanQuery = false, CanTouch = false })
seaPart.Parent = workspace

-- the flood's water and its red line, the tornado's anchor: shown only while their disaster runs
local water = part({ Name = "Water", Size = Vector3.new(2 * HALF + 40, 1, 2 * HALF + 40), Position = Vector3.new(0, -200, 0),
	Material = Enum.Material.Glass, Color = Color3.fromRGB(40, 120, 170), Transparency = 1,
	CanCollide = false, CanQuery = false, CanTouch = false })
water.Parent = roundFolder
local slab = part({ Name = "FloodLine", Size = Vector3.new(2 * HALF + 2, 0.3, 2 * HALF + 2), Position = Vector3.new(0, -200, 0),
	Material = Enum.Material.Neon, Color = RED, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
slab.Parent = roundFolder
local funnel = part({ Name = "Funnel", Size = Vector3.new(2, 2, 2), Position = Vector3.new(0, -200, 0), Transparency = 1,
	CanCollide = false, CanQuery = false, CanTouch = false })
funnel.Parent = roundFolder

--============================================================================== island building

local mapRng = Random.new() -- entropy-seeded; it builds islands and picks drop cells, nothing else
local function mapRand(): number
	return mapRng:NextNumber()
end
local kindRng = Random.new() -- picks the next disaster: a stream of its own, never the map's
local function kindRand(): number
	return kindRng:NextNumber()
end

local PROP_PARTS_MAX = IC.MaxProps

local function buildProp(folder: Folder, map: any, pr: any, budget: { n: number })
	local level = map.levels[pr.i][pr.j]
	local cx, cz = MapGen.cellCenter(IC, pr.i, pr.j)
	local base = Vector3.new(cx + pr.ox, MapGen.topY(IC, level), cz + pr.oz)
	local s = pr.scale
	local function add(props: { [string]: any })
		if budget.n >= PROP_PARTS_MAX then return end
		budget.n += 1
		props.CanCollide = false
		props.CanQuery = false
		props.CanTouch = false
		props.CastShadow = true
		part(props).Parent = folder
	end
	local rot = CFrame.Angles(0, math.rad(pr.rot), 0)
	if pr.kind == "palm" then
		add({ Name = "PalmTrunk", Size = Vector3.new(0.8 * s, 7 * s, 0.8 * s), CFrame = CFrame.new(base + Vector3.new(0, 3.5 * s, 0)) * rot * CFrame.Angles(0, 0, math.rad(8)),
			Material = Enum.Material.Wood, Color = Color3.fromRGB(150, 110, 70) })
		add({ Name = "PalmCrown", Size = Vector3.new(5 * s, 1 * s, 5 * s), CFrame = CFrame.new(base + Vector3.new(0.5 * s, 7.2 * s, 0)) * rot,
			Material = Enum.Material.Grass, Color = Color3.fromRGB(60, 150, 70) })
	elseif pr.kind == "pine" then
		add({ Name = "PineTrunk", Size = Vector3.new(0.7 * s, 3 * s, 0.7 * s), CFrame = CFrame.new(base + Vector3.new(0, 1.5 * s, 0)) * rot,
			Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 80, 56) })
		add({ Name = "PineCrown", Size = Vector3.new(3.2 * s, 6 * s, 3.2 * s), CFrame = CFrame.new(base + Vector3.new(0, 5.5 * s, 0)) * rot,
			Material = Enum.Material.Grass, Color = Color3.fromRGB(40, 100, 60) })
	elseif pr.kind == "cactus" then
		add({ Name = "Cactus", Size = Vector3.new(1.2 * s, 4.5 * s, 1.2 * s), CFrame = CFrame.new(base + Vector3.new(0, 2.25 * s, 0)) * rot,
			Material = Enum.Material.Grass, Color = Color3.fromRGB(90, 150, 80) })
	elseif pr.kind == "log" then
		add({ Name = "Log", Size = Vector3.new(4 * s, 0.9 * s, 0.9 * s), CFrame = CFrame.new(base + Vector3.new(0, 0.45 * s, 0)) * rot,
			Material = Enum.Material.Wood, Color = Color3.fromRGB(120, 90, 60) })
	else -- rocks
		local col = if pr.kind == "bleachedRock" then Color3.fromRGB(226, 220, 204) else Color3.fromRGB(130, 128, 120)
		add({ Name = "Rock", Size = Vector3.new(2 * s, 1.2 * s, 1.6 * s), CFrame = CFrame.new(base + Vector3.new(0, 0.5 * s, 0)) * rot,
			Material = Enum.Material.Slate, Color = col })
	end
end

-- -> the island Model (unparented) and its map
local function buildIsland(): (Model, any)
	local seed = Config.Shots.IslandSeed
	local rand = mapRand
	if seed ~= nil then
		local r = Random.new(seed)
		rand = function() return r:NextNumber() end
	end
	local map = MapGen.generate(IC, rand)
	local style = IC.Styles[map.style]
	local model = Instance.new("Model")
	model.Name = "NextIsland"
	model:SetAttribute("Style", style.name)
	local cells = Instance.new("Folder")
	cells.Name = "Cells"
	cells.Parent = model
	for i = 1, IC.Grid do
		for j = 1, IC.Grid do
			local level = map.levels[i][j]
			local top = MapGen.topY(IC, level)
			local cx, cz = MapGen.cellCenter(IC, i, j)
			local h = top - IC.ColumnBottomY
			local c = part({
				Name = "Cell_" .. i .. "_" .. j,
				Size = Vector3.new(IC.CellStuds, h, IC.CellStuds),
				Position = Vector3.new(cx, IC.ColumnBottomY + h / 2, cz),
				Material = (Enum.Material :: any)[style.materials[level + 1]],
				Color = rgb(style.levels[level + 1]),
			})
			c:SetAttribute("Level", level)
			c:SetAttribute("I", i)
			c:SetAttribute("J", j)
			c.Parent = cells
		end
	end
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = model
	local budget = { n = 0 }
	for _, pr in map.props do
		buildProp(props, map, pr, budget)
	end
	return model, map
end

local nextIsland: Model? = nil
local nextMap: any = nil
local function prepareNextIsland()
	if nextIsland ~= nil then return end
	local m, map = buildIsland()
	-- ServerStorage, not workspace: nothing about the next round is visible while a player can still sit it out
	m.Parent = ServerStorage
	nextIsland, nextMap = m, map
end

--============================================================================== data: profiles and the session lock

local function tryStore(fn, what: string)
	if not Config.Save.Enabled then return nil end
	local ok, ds = pcall(fn)
	if ok then return ds end
	warn("[DisasterRounds] " .. what .. " datastore unavailable (" .. tostring(ds) .. ") - progress will NOT be saved this session.")
	return nil
end
local store = tryStore(function() return DataStoreService:GetDataStore(Config.Save.Store) end, "profiles")
local orderedLB = tryStore(function() return DataStoreService:GetOrderedDataStore(Config.Save.Leaderboard) end, "leaderboard")

-- [player] = { data = profile, token, canSave, newer, loaded, writing, pending, leaving, lastWrite }
local sessions: { [Player]: any } = {}
local closing = false

local function key(uid: number): string
	return "u_" .. tostring(uid)
end

local function newToken(plr: Player): string
	local ok, guid = pcall(function() return HttpService:GenerateGUID(false) end)
	if ok and type(guid) == "string" and #guid > 0 then return guid end
	return string.format("%s-%d-%d", tostring(game.JobId), plr.UserId, math.floor(now() * 1e6))
end

local publishPlayer -- forward: attributes + leaderstats from the profile
-- forward: the board (built further down) is re-sent at a round's end
local sendBoard: (Player, string, any) -> ()
local boardMode: { [Player]: string } = {}
local publicView: any = nil

-- One attempt to load and take the lock. -> "ok" | "locked" | "newer" | "error", raw profile data
local function tryLoad(plr: Player, token: string): (string, any)
	local status, raw = "error", nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			raw = old.data
			if type(old.v) == "number" and old.v > Config.Version then
				status = "newer"
				return nil
			end
			local s = old.session
			local t = os.time()
			if type(s) == "table" and s.token ~= token and (tonumber(s.expires) or 0) > t then
				status = "locked"
				return nil
			end
			status = "ok"
			-- an expired lock, a released one, or none at all: this session takes it (with the data as it was)
			old.session = { token = token, expires = t + Config.Save.LockSeconds }
			old.v = old.v or Config.Version
			return old
		end)
	end)
	if not ok then
		warn("[DisasterRounds] load failed for " .. plr.Name .. ": " .. tostring(err))
		return "error", nil
	end
	return status, raw
end

local function adopt(plr: Player, s: any, raw: any, canSave: boolean)
	local p, warnings = Progress.normalise(raw, Config)
	for _, w in warnings do
		warn("[DisasterRounds] " .. plr.Name .. "'s profile: " .. w)
	end
	s.data = p
	s.canSave = canSave
	if p.bestAt <= 0 and p.best > 0 then p.bestAt = os.time() end
	local le = if canSave then Progress.takeLastEnd(p) else nil
	if le ~= nil and le.reason == "left" then
		toast(plr, string.format("You left during a round, so your streak ended at %d.", le.streak))
	end
end

-- Load with retries; a lock held elsewhere is waited for, then read-only with a takeover check; a failed load gives
-- a fresh UNSAVED profile and keeps retrying. Never writes a default profile over real data.
local function loadProfile(plr: Player, s: any)
	if not store then
		s.data = Progress.default()
		s.canSave = false
		return
	end
	local token = s.token
	local status, raw = "error", nil
	for attempt = 1, Config.Save.LoadAttempts do
		status, raw = tryLoad(plr, token)
		if status ~= "error" then break end
		if attempt < Config.Save.LoadAttempts then task.wait(Config.Save.LoadBackoff[attempt] or 1) end
		if plr.Parent ~= Players then return end
	end
	if status == "ok" then
		adopt(plr, s, raw, true)
		return
	end
	if status == "newer" then
		adopt(plr, s, raw, false)
		s.newer = true
		toast(plr, "Progress here won't save: your save was made by a newer version of the game.")
		return
	end
	if status == "locked" then
		toast(plr, "⏳ Your save is open in another server. Waiting for it…")
		local waited = 0
		while waited < Config.Save.LockWaitSeconds and plr.Parent == Players do
			task.wait(Config.Save.LockPollSeconds)
			waited += Config.Save.LockPollSeconds
			status, raw = tryLoad(plr, token)
			if status == "ok" then
				adopt(plr, s, raw, true)
				toast(plr, "Your save is here now. Progress saves again.")
				return
			end
		end
		adopt(plr, s, raw, false)
		toast(plr, "Progress here won't save: your save is open in another server.")
		-- keep checking: an expired lock on an untouched record is taken over
		task.spawn(function()
			while plr.Parent == Players and sessions[plr] == s and not s.canSave and not s.newer do
				task.wait(Config.Save.ReadOnlyRecheckSeconds)
				if plr.Parent ~= Players or sessions[plr] ~= s then return end
				local st, r = tryLoad(plr, token)
				if st == "ok" then
					-- take it over only if the stored record is still what this session showed (nothing newer landed)
					local p2 = Progress.normalise(r, Config)
					if p2.survived <= s.data.survived and p2.best <= s.data.best then
						s.canSave = true
						toast(plr, "Your save is here now. Progress saves again.")
					else
						adopt(plr, s, r, true)
						toast(plr, "Your save is here now. Progress saves again.")
					end
					publishPlayer(plr)
					return
				end
			end
		end)
		return
	end
	-- three failures: a fresh profile that is NOT saved, and a retry every LoadRetrySeconds
	s.data = Progress.default()
	s.canSave = false
	toast(plr, "Couldn't load your profile — nothing will be saved this session. Rejoin to try again.")
	task.spawn(function()
		while plr.Parent == Players and sessions[plr] == s and not s.canSave do
			task.wait(Config.Save.LoadRetrySeconds)
			if plr.Parent ~= Players or sessions[plr] ~= s then return end
			local st, r = tryLoad(plr, token)
			if st == "ok" then
				adopt(plr, s, r, true)
				toast(plr, "Your profile loaded. Progress saves from now on.")
				publishPlayer(plr)
				return
			end
		end
	end)
end

-- The board's store (docs/complete-game-standard.md §3): written only when the SAVED metric (Progress.boardEntry: the
-- best streak up to Config.Board.StreakCap) passes the last one written, max-merged (Board.keepHigher), and only by
-- the session that holds the lock (called after a landed write).
local function writeBoard(s: any, uid: number, best: number, bestAt: number)
	if not orderedLB or best <= (s.data.boardBest or 0) then return end
	local value = Board.encode(best, bestAt, Config.Board)
	local ok = pcall(function()
		orderedLB:UpdateAsync(key(uid), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	if ok then s.data.boardBest = math.max(s.data.boardBest or 0, best) end
end

-- One write, serialised per player. Every write carries the owner token, including the release on leave; a write
-- after the leave began never re-locks. -> true when the record now holds this session's data.
-- It works on the SESSION, never on sessions[plr]: a leave clears sessions[plr] at once, and the leave's own write
-- (the release, and a mid-round elimination) may be waiting behind a write still in flight (REVIEW-1 F3: looked up
-- by player, that waiting write found no session and was lost: a 300 s stale lock, and a leave that cost nothing).
local writesInFlight = 0
local function saveSession(plr: Player, s: any, release: boolean): boolean
	if not s or not s.canSave or not store then return false end
	if s.leaving and not release then return false end
	if s.writing then
		s.pending = true
		s.pendingRelease = s.pendingRelease or release
		return false
	end
	s.writing = true
	writesInFlight += 1
	plr:SetAttribute("Saving", true)
	local lost = false
	local snapshot = Progress.toSave(s.data)
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local sess = old.session
			if type(sess) ~= "table" or sess.token ~= s.token or (type(old.v) == "number" and old.v > Config.Version) then
				lost = true
				return nil
			end
			lost = false
			old.v = Config.Version
			old.data = snapshot
			old.session = { token = s.token, expires = if release then 0 else os.time() + Config.Save.LockSeconds }
			return old
		end)
	end)
	s.writing = false
	if plr.Parent ~= nil then plr:SetAttribute("Saving", false) end
	if not ok then
		warn("[DisasterRounds] save failed for " .. plr.Name .. ": " .. tostring(err))
	elseif lost then
		s.canSave = false
		warn("[DisasterRounds] " .. plr.Name .. ": another session has taken this profile; nothing here saves any more.")
		if plr.Parent ~= nil then
			toast(plr, "Progress here won't save: your save is open in another server.")
		end
	else
		s.lastWrite = now()
		writeBoard(s, plr.UserId, Progress.boardEntry(snapshot, Config))
	end
	local result = ok and not lost
	if s.pending and not lost then
		local rel = s.pendingRelease
		s.pending, s.pendingRelease = false, false
		result = saveSession(plr, s, rel) or result
	end
	-- counted down only after the write that waited behind this one, so BindToClose never sees 0 in between
	writesInFlight -= 1
	return result
end
local function saveProfile(plr: Player, release: boolean): boolean
	return saveSession(plr, sessions[plr], release)
end

--============================================================================== player attributes

publishPlayer = function(plr: Player)
	local s = sessions[plr]
	if not s or not s.data then return end
	local p = s.data
	plr:SetAttribute("Survived", p.survived)
	plr:SetAttribute("Streak", p.streak)
	plr:SetAttribute("Best", p.best)
	plr:SetAttribute("Played", p.played)
	plr:SetAttribute("Codex", Progress.codexString(p))
	if (plr:GetAttribute("InRound") or "") == "" then
		plr:SetAttribute("Heat", Progress.heat(Config, p.streak))
	end
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local st = ls:FindFirstChild("Streak") :: IntValue?
		local bv = ls:FindFirstChild("Best") :: IntValue?
		if st then st.Value = p.streak end
		if bv then bv.Value = p.best end
	end
end

local function shownName(plr: Player): string
	local ok, n = pcall(function() return plr.DisplayName end)
	if ok and type(n) == "string" and n ~= "" then return n end
	return plr.Name
end

local function bumpMoveSeq(plr: Player)
	plr:SetAttribute("MoveSeq", (plr:GetAttribute("MoveSeq") or 0) + 1)
end

local function rootOf(plr: Player): BasePart?
	local char = plr.Character
	if not char or char.Parent == nil then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- a server move: the character is already in the world (drops, returns); never a spawn
local function moveTo(plr: Player, cf: CFrame)
	local char = plr.Character
	if not char or char.Parent == nil then return end
	pcall(function() (char :: Model):PivotTo(cf) end)
	bumpMoveSeq(plr)
end

--============================================================================== the round

local R = Round.new(RC, now())
local cur: any = nil -- the running round, see startDrop
local dodgeCount: { [Player]: number } = {}
local guards: { [Player]: any } = {}

local function setRoundAttr(name: string, value: any)
	if roundFolder:GetAttribute(name) ~= value then
		roundFolder:SetAttribute(name, value)
	end
end

local function phaseAttrs()
	setRoundAttr("Phase", R.phase)
	setRoundAttr("PhaseEnds", R.ends)
	setRoundAttr("RoundId", R.roundId)
end

local function clearDisasterAttrs()
	for _, n in { "Kind", "NameAt", "WaterFrom", "WaterTo", "RiseAt", "RiseEnd", "WarnLevel", "Path" } do
		roundFolder:SetAttribute(n, nil)
	end
	water.Transparency = 1
	water.Position = Vector3.new(0, -200, 0)
	slab.Transparency = 1
	slab.Position = Vector3.new(0, -200, 0)
	funnel.Position = Vector3.new(0, -200, 0)
	ringsFolder:ClearAllChildren()
end

local function secondsToNextDrop(): number
	return Round.secondsToNextDrop(RC, R, now())
end

local function isResting(plr: Player): boolean
	return plr:GetAttribute("Resting") == true
end

local function eligible(plr: Player): boolean
	local s = sessions[plr]
	return plr.Parent == Players and s ~= nil and s.loaded and not isResting(plr) and rootOf(plr) ~= nil
end

local function islandCell(x: number, z: number): (number?, number?)
	return MapGen.cellAt(IC, x, z)
end

local function cellPart(i: number, j: number): BasePart?
	if not cur or not cur.island then return nil end
	return cur.island.Cells:FindFirstChild("Cell_" .. i .. "_" .. j) :: BasePart?
end

-- standing ground for the ring placement rule and the practice landing: intact, not cracking, not flooded, and not
-- in the last PlayerRadius at the island's edge (the walls stand at WallHalf: a root never gets that far out).
-- Fairness check 2026-10-07: counting the edge itself as ground let a third ring into a one-cell pocket.
local STAND_HALF = HALF - Config.Hits.PlayerRadius
local function solidAt(x: number, z: number): boolean
	if not cur then return false end
	if math.abs(x) > STAND_HALF or math.abs(z) > STAND_HALF then return false end
	local i, j = islandCell(x, z)
	if i == nil or j == nil then return false end
	if cur.quake and (Quake.isDropped(cur.quake, i, j) or Quake.isCracking(cur.quake, i, j)) then return false end
	if cur.flood then
		local level = cur.map.levels[i][j]
		if Zones.flooded(IC, level, cur.waterY) then return false end
		local a = cur.floodAttrs
		if a and Flood.warnedLevel(level, a.rise) then return false end
	end
	if cur.tornado and cur.nameAt then
		-- the drawn red path (the next HorizonSeconds) is red ground too: a ring never leaves a player only that way out
		local rel = now() - cur.nameAt
		if Tornado.onPath(cur.tornado, rel - Config.Tornado.StepSeconds, math.max(rel, Config.Tornado.TouchdownAt)
			+ Config.Tornado.HorizonSeconds, FUNNEL_R + 0.8, x, z) then
			return false
		end
	end
	return true
end

local function walkableArea(): number
	local n = 0
	for i = 1, IC.Grid do
		for j = 1, IC.Grid do
			local cx, cz = MapGen.cellCenter(IC, i, j)
			if solidAt(cx, cz) then n += 1 end
		end
	end
	return n * IC.CellStuds * IC.CellStuds
end

local function sweptText(reason: string): string
	if reason == "guard" then return "Movement check failed: you moved faster than walking. Round lost." end
	if reason == "reset" then return "You reset — round lost." end
	if reason == "fell" then return "🌊 You fell into the sea" end
	local info = Config.Disasters.Info[reason]
	if info then return info.icon .. " " .. info.hit end
	local ringHit = string.match(reason, "^ring:(.+)$")
	if ringHit then return "💥 " .. (Config.Disasters.RingHit[ringHit] or "Hit") end
	return "Swept away"
end

-- Off the island: a hit, the guard, a reset or a leave. Counted players lose their streak (never their progress).
local function sweepOut(plr: Player, reason: string, move: boolean)
	if not cur or cur.on[plr] == nil then return end
	local kindOfEntry = cur.on[plr]
	cur.on[plr] = nil
	cur.swept[plr] = true
	cur.strikes[plr] = nil
	local s = sessions[plr]
	if kindOfEntry == "counted" and s and s.data then
		Progress.eliminate(s.data, if reason == "left" then "left" elseif reason == "reset" then "reset" elseif reason == "guard" then "guard" else reason)
		cur.results[plr] = "out"
	end
	if plr.Parent == Players then
		plr:SetAttribute("InRound", "")
		plr:SetAttribute("SweptRound", R.roundId) -- the HUD hides Jump-in for the rest of this round
		publishPlayer(plr)
		if move then moveTo(plr, lookoutCFrame()) end
		if guards[plr] then Guard.reset(guards[plr], Config, now()) end
		CardEvent:FireClient(plr, "swept", {
			text = sweptText(reason),
			practice = kindOfEntry == "practice",
			nextIn = secondsToNextDrop(),
			streak = if s and s.data then s.data.streak else 0,
		})
	end
end

-- players of a set in a stable order (by UserId): every random draw this round takes happens in the same order on
-- every run, so a headless check that seeds Random replays a round exactly
local function ordered(set: { [Player]: any }): { Player }
	local out = {}
	for plr in set do table.insert(out, plr) end
	table.sort(out, function(a, b) return a.UserId < b.UserId end)
	return out
end

local function aliveOnIsland(): { Player }
	local out = {}
	if not cur then return out end
	for _, plr in ordered(cur.on) do
		if plr.Parent == Players then table.insert(out, plr) end
	end
	return out
end

local function startDrop(t: number)
	prepareNextIsland()
	-- the roster freezes NOW, before the island is visible
	local roster = {}
	for _, plr in Players:GetPlayers() do
		if eligible(plr) then table.insert(roster, plr) end
	end
	local old = roundFolder:FindFirstChild("Island")
	if old then old:Destroy() end
	clearDisasterAttrs()
	local island = nextIsland :: Model
	local map = nextMap
	nextIsland, nextMap = nil, nil
	island.Name = "Island"
	island.Parent = roundFolder
	setRoundAttr("Style", island:GetAttribute("Style"))
	cur = {
		id = R.roundId, island = island, map = map, kind = nil, nameAt = nil, endAt = nil,
		on = {}, swept = {}, results = {}, heat = {}, strikes = {}, rings = {},
		dwell = Zones.newDwell(), judges = {}, flood = nil, tornado = nil, quake = nil, waterY = IC.SeaY,
		rand = nil,
	}
	local cells = MapGen.dropCells(IC, map.levels, #roster, mapRand)
	for k, plr in roster do
		local c = cells[k]
		local s = sessions[plr]
		local heat = Config.Shots.ForceHeat or Progress.heat(Config, s.data.streak)
		cur.on[plr] = "counted"
		cur.heat[plr] = heat
		plr:SetAttribute("InRound", "counted")
		plr:SetAttribute("Heat", heat)
		local cx, cz = MapGen.cellCenter(IC, c.i, c.j)
		local pos = Vector3.new(cx, MapGen.topY(IC, map.levels[c.i][c.j]) + 3, cz)
		moveTo(plr, facingCentre(pos))
		guards[plr] = guards[plr] or Guard.new()
		Guard.reset(guards[plr], Config, t)
		CardEvent:FireClient(plr, "drop", { heat = heat })
	end
end

local function nameDisaster(t: number)
	if not cur then return end
	-- an even draw, owing nothing to the last round (REVIEW-1 F4: a "never twice in a row" rule told a resting player
	-- which disaster could not come next)
	local kind = Round.pickKind(Config.Disasters.Kinds, kindRand, Config.Shots.ForceKind)
	-- the disaster's own stream, fresh every round and never the map's (fork-tower REVIEW-4 trap 1)
	local rng = Random.new()
	cur.rand = function() return rng:NextNumber() end
	cur.kind = kind
	cur.nameAt = t
	cur.endAt = R.ends
	setRoundAttr("Kind", kind)
	setRoundAttr("LastKind", kind)
	setRoundAttr("NameAt", t)
	local positions = {}
	for _, plr in aliveOnIsland() do
		local r = rootOf(plr)
		if r then table.insert(positions, { x = r.Position.X, z = r.Position.Z }) end
		cur.strikes[plr] = Strikes.newPlayer(Config, kind, cur.heat[plr] or 0, t, cur.rand)
	end
	if kind == "flood" then
		cur.flood = Flood.plan(Config)
		water.Transparency = 0.25
		water.Position = Vector3.new(0, IC.SeaY - 0.5, 0)
	elseif kind == "tornado" then
		cur.tornado = Tornado.start(Config, positions, cur.rand)
		Tornado.extend(Config, cur.tornado, Config.Tornado.TouchdownAt + Config.Tornado.HorizonSeconds, positions, cur.rand)
	elseif kind == "quake" then
		cur.quake = Quake.new()
		cur.batches = Quake.batchTimes(Config)
		cur.nextBatch = 1
	end
	CardEvent:FireAllClients("name", { kind = kind })
end

-- ring parts: the ring IS the telegraph. Attributes say when it lands; the client adds the pulse and the projectile.
-- the ground under cell (i, j) now: its level, or nil once a quake has dropped it
local function groundLevel(i: number, j: number): number?
	if not cur then return nil end
	if cur.quake and Quake.isDropped(cur.quake, i, j) then return nil end
	return cur.map.levels[i][j]
end

local function placeRing(plr: Player, x: number, z: number, t: number)
	local i, j = islandCell(x, z)
	local groundY = (if i and j then MapGen.topY(IC, cur.map.levels[i][j]) else 0) + 0.15
	-- a red VOLUME from just over the lowest top the ring reaches to just over the highest, so its red shows on every
	-- terrace it reaches (REVIEW-1 F7: drawn flat at the centre's top, it was buried inside a higher neighbour's column,
	-- and a player who stepped up out of the red they could see was hit). Over flat ground: the old flat disc.
	local lo, hi = Zones.redSpan(IC, Zones.cellsUnderDisk(IC, x, z, RING_R), groundLevel)
	if lo == nil or hi == nil then lo, hi = groundY - 0.1, groundY + 0.1 end
	local ring = part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(hi - lo, 2 * RING_R, 2 * RING_R),
		CFrame = CFrame.new(x, (lo + hi) / 2, z) * CFrame.Angles(0, 0, math.rad(90)), Material = Enum.Material.Neon,
		Color = RED, Transparency = 0.35, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	ring:SetAttribute("GroundY", groundY) -- where the projectile lands (World.client): the top under the ring's centre
	ring:SetAttribute("ImpactAt", t + Config.Strikes.TelegraphSeconds)
	ring:SetAttribute("Radius", RING_R)
	ring:SetAttribute("TargetId", plr.UserId)
	ring:SetAttribute("Theme", cur.kind)
	ring.Parent = ringsFolder
	table.insert(cur.rings, {
		part = ring, x = x, z = z, target = plr, impact = t + Config.Strikes.TelegraphSeconds,
		ends = t + Config.Strikes.TelegraphSeconds + Config.Strikes.PassSeconds,
		judge = Zones.newJudge(t + Config.Strikes.TelegraphSeconds, Config.Hits.LagGrace),
	})
end

local function updateRings(t: number, pos: { [Player]: Vector3 })
	-- schedule
	local players = {}
	for _, plr in ordered(pos) do table.insert(players, { x = pos[plr].X, z = pos[plr].Z }) end
	local live = {}
	for _, r in cur.rings do
		if r.ends > t then table.insert(live, { x = r.x, z = r.z, r = RING_R }) end
	end
	local area = nil
	for _, plr in ordered(cur.strikes) do
		local ps = cur.strikes[plr]
		local p = pos[plr]
		if p and Strikes.due(Config, ps, t, cur.endAt) then
			area = area or walkableArea()
			local ok = Strikes.canPlace(Config, { x = p.X, z = p.Z }, live, players, solidAt, area, Zones.exitDistance)
			if ok then
				placeRing(plr, p.X, p.Z, t)
				table.insert(live, { x = p.X, z = p.Z, r = RING_R })
				Strikes.placed(Config, ps, t, cur.rand)
			else
				Strikes.deferred(Config, ps, t)
			end
		end
	end
	-- judge: a ring hits ANYONE inside it at every sample in [impact, impact + LagGrace]
	local keep = {}
	local posOrder = ordered(pos)
	for _, r in cur.rings do
		for _, plr in posOrder do
			local p = pos[plr]
			if cur.on[plr] ~= nil then
				local verdict = Zones.judgeSample(r.judge, plr, t, Zones.inDisk(r.x, r.z, RING_R, p.X, p.Z))
				if verdict == "hit" then
					sweepOut(plr, "ring:" .. cur.kind, true)
				elseif verdict == "dodge" and plr == r.target then
					dodgeCount[plr] = (dodgeCount[plr] or 0) + 1
					if dodgeCount[plr] <= Config.Brag.DodgedPopups then
						CardEvent:FireClient(plr, "dodged", { n = dodgeCount[plr] })
					end
				end
			end
		end
		if r.ends > t then
			table.insert(keep, r)
		else
			r.part:Destroy()
		end
	end
	cur.rings = keep
end

local function updateFlood(t: number, rel: number, pos: { [Player]: Vector3 })
	local y = Flood.waterAt(Config, cur.flood, rel)
	cur.waterY = y
	water.Position = Vector3.new(0, y - 0.5, 0)
	local a = Flood.attributes(cur.flood, rel)
	if a then
		local k = Flood.currentRise(cur.flood, rel) :: number
		cur.floodAttrs = { rise = cur.flood[k] }
		setRoundAttr("WaterFrom", a.WaterFrom)
		setRoundAttr("WaterTo", a.WaterTo)
		setRoundAttr("RiseAt", cur.nameAt + a.RiseAt)
		setRoundAttr("RiseEnd", cur.nameAt + a.RiseEnd)
		setRoundAttr("WarnLevel", a.WarnLevel)
		-- the red line at the coming height, from the warning until the rise is done
		if rel < a.RiseEnd then
			slab.Transparency = 0.55
			slab.Position = Vector3.new(0, a.WaterTo, 0)
		else
			slab.Transparency = 1
			slab.Position = Vector3.new(0, -200, 0)
			cur.floodAttrs = nil
		end
	end
	for plr, p in pos do
		local i, j = islandCell(p.X, p.Z)
		local level = if i and j then cur.map.levels[i][j] else -1
		-- off the island is the sea (the walls keep a root from getting there, but a glitch must not save anyone)
		local wet = if level < 0 then true else Zones.flooded(IC, level, y)
		if Zones.dwell(cur.dwell, "flood:" .. plr.UserId, wet, t, Config.Hits.GroundGrace) then
			sweepOut(plr, "flood", true)
		end
	end
end

local function updateTornado(t: number, rel: number, pos: { [Player]: Vector3 })
	local tc = Config.Tornado
	local players = {}
	for _, plr in ordered(pos) do table.insert(players, { x = pos[plr].X, z = pos[plr].Z }) end
	Tornado.extend(Config, cur.tornado, math.max(rel, tc.TouchdownAt) + tc.HorizonSeconds, players, cur.rand)
	setRoundAttr("Path", Tornado.encode(cur.tornado, rel - tc.StepSeconds, math.max(rel, tc.TouchdownAt) + tc.HorizonSeconds, cur.nameAt))
	local fx, fz = Tornado.positionAt(cur.tornado, rel)
	if fx == nil or fz == nil then return end
	local i, j = islandCell(fx, fz)
	local y = if i and j then MapGen.topY(IC, cur.map.levels[i][j]) else 0
	funnel.Position = Vector3.new(fx, y + 1, fz)
	for plr, p in pos do
		if Zones.dwell(cur.dwell, "funnel:" .. plr.UserId, Zones.inDisk(fx, fz, FUNNEL_R, p.X, p.Z), t, Config.Hits.LagGrace) then
			sweepOut(plr, "tornado", true)
		end
	end
end

local function updateQuake(t: number, rel: number, pos: { [Player]: Vector3 })
	local q = cur.quake
	-- a new batch cracks red, 3 s before it drops
	while cur.nextBatch <= #cur.batches and rel >= cur.batches[cur.nextBatch] - 1e-9 do
		local standing = {}
		for _, plr in ordered(pos) do
			local p = pos[plr]
			local i, j = islandCell(p.X, p.Z)
			if i and j and not Quake.isDropped(q, i, j) then table.insert(standing, { i = i, j = j }) end
		end
		-- a cell a live ring overlaps is not a safe way off a crack
		local blocked = {}
		for _, r in cur.rings do
			if r.ends > t then
				for i = 1, IC.Grid do
					for j = 1, IC.Grid do
						local cx, cz = MapGen.cellCenter(IC, i, j)
						local dx = math.max(0, math.abs(r.x - cx) - IC.CellStuds / 2)
						local dz = math.max(0, math.abs(r.z - cz) - IC.CellStuds / 2)
						if dx * dx + dz * dz < RING_R * RING_R then blocked[MapGen.key(i, j)] = true end
					end
				end
			end
		end
		local batch = Quake.pickBatch(Config, cur.map.levels, q, standing, cur.rand, blocked)
		Quake.crack(q, batch, rel, Config.Quake.CrackSeconds)
		for _, c in batch do
			local cp = cellPart(c.i, c.j)
			if cp then
				cp:SetAttribute("CrackAt", t)
				cp:SetAttribute("DropAt", t + Config.Quake.CrackSeconds)
			end
			table.insert(cur.judges, { i = c.i, j = c.j, judge = Zones.newJudge(t + Config.Quake.CrackSeconds, Config.Hits.LagGrace) })
		end
		cur.nextBatch += 1
	end
	-- cells whose time is up drop into the sea
	for _, c in Quake.update(q, rel) do
		local cp = cellPart(c.i, c.j)
		if cp then
			cp:SetAttribute("Dropped", true)
			cp.Transparency = 1
			cp.CanCollide = false
			cp.CanQuery = false
		end
	end
	-- the drop: the root over a dropping cell at every sample in [drop, drop + grace]
	local keep = {}
	for _, jd in cur.judges do
		for plr, p in pos do
			if cur.on[plr] ~= nil then
				if Zones.judgeSample(jd.judge, plr, t, Zones.overCell(IC, jd.i, jd.j, p.X, p.Z)) == "hit" then
					sweepOut(plr, "quake", true)
				end
			end
		end
		if not Zones.judgeDone(jd.judge, t) then table.insert(keep, jd) end
	end
	cur.judges = keep
	-- later: over a hole for GroundGrace in a row
	for plr, p in pos do
		if cur.on[plr] ~= nil then
			local i, j = islandCell(p.X, p.Z)
			local hole = i ~= nil and j ~= nil and Quake.isDropped(q, i, j)
			if Zones.dwell(cur.dwell, "hole:" .. plr.UserId, hole, t, Config.Hits.GroundGrace) then
				sweepOut(plr, "quake", true)
			end
		end
	end
end

-- every tick of a drop or a disaster: positions, the guard, falls, the disaster's hit tests and the rings
local function updateIsland(t: number)
	if not cur then return end
	local pos: { [Player]: Vector3 } = {}
	for _, plr in ordered(cur.on) do
		if plr.Parent ~= Players then
			cur.on[plr] = nil
		else
			local r = rootOf(plr)
			if r == nil then
				sweepOut(plr, "reset", false)
			else
				local p = r.Position
				if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z then
					-- a body with no real position can be neither judged nor saved by the red: it is out
					sweepOut(plr, "fell", true)
					continue
				end
				local g = guards[plr]
				local verdict = if g then Guard.sample(g, Config, t, p.X, p.Z, HALF) else "ok"
				if verdict ~= "ok" and cur.on[plr] == "counted" then
					sweepOut(plr, "guard", true)
				elseif p.Y < IC.FallOutY then
					sweepOut(plr, "fell", true)
				elseif Zones.dwell(cur.dwell, "sea:" .. plr.UserId, islandCell(p.X, p.Z) == nil, t, Config.Hits.GroundGrace) then
					-- off the island is the sea, in every disaster and in the drop, as the flood always had it. The walls
					-- keep a walking root over the cells; only a flying or noclipping client gets out here, and the first
					-- build let it park over the sea in a corner where no ring could be placed, no funnel could reach and
					-- no cell could crack (REVIEW-1 F2: 12 of 12 rounds survived with no input)
					sweepOut(plr, "fell", true)
				else
					pos[plr] = p
				end
			end
		end
	end
	if R.phase ~= "disaster" or cur.kind == nil then return end
	local rel = t - cur.nameAt
	if cur.kind == "flood" then
		updateFlood(t, rel, pos)
	elseif cur.kind == "tornado" then
		updateTornado(t, rel, pos)
	elseif cur.kind == "quake" then
		updateQuake(t, rel, pos)
	end
	for plr in pos do
		if cur.on[plr] == nil then pos[plr] = nil end
	end
	updateRings(t, pos)
end

local function saveRoundResults()
	if not cur then return end
	for plr in cur.results do
		if plr.Parent == Players then
			task.spawn(saveProfile, plr, false)
		end
	end
end

-- the disaster ran its 60 s: whoever is still on the island survived it
local function endDisaster(t: number)
	if not cur then return end
	ringsFolder:ClearAllChildren()
	cur.rings = {}
	local alive = aliveOnIsland()
	-- the round is over: nobody is "in" it any more. A leave, a reset, a death or a fall during the outro is not a leave
	-- or a reset DURING a round (REVIEW-1 F1: the first build swept them out of a round they had just survived and wiped
	-- the streak it had just awarded). They stay on the island for the SURVIVED card and are taken home at the outro's end.
	cur.returning = cur.on
	cur.on = {}
	for _, plr in alive do
		local s = sessions[plr]
		if cur.returning[plr] == "counted" and s and s.data then
			local ev = Progress.survive(s.data, Config, cur.kind or "meteor", cur.heat[plr] or 0, os.time())
			cur.results[plr] = "survived"
			publishPlayer(plr)
			plr:SetAttribute("Heat", cur.heat[plr] or 0) -- the round's Heat holds through the outro
			CardEvent:FireClient(plr, "survived", { streak = s.data.streak, best = s.data.best, newBest = ev.newBest,
				heat = Progress.heat(Config, s.data.streak) })
			if ev.brag then
				ToastEvent:FireAllClients("☄️ " .. shownName(plr) .. " has survived " .. s.data.survived .. " disasters. Their sky is falling.")
				CardEvent:FireClient(plr, "brag", { survived = s.data.survived })
			end
			if ev.maxHeat then
				ToastEvent:FireAllClients("🔥 " .. shownName(plr) .. " hit MAX HEAT: " .. s.data.streak .. " in a row")
			end
		else
			CardEvent:FireClient(plr, "practice", {})
		end
	end
	saveRoundResults()
	for _, plr in Players:GetPlayers() do
		if boardMode[plr] ~= "friends" then sendBoard(plr, "public", publicView) end
	end
end

-- everyone back to the Lookout; the stage is cleared and the next island is built out of sight
local function returnAll(t: number)
	if cur then
		-- the island's survivors (cur.returning, after a full disaster) or whoever is still on it (an empty or idle end)
		local home = {}
		for plr in cur.on do home[plr] = true end
		for plr in cur.returning or {} do home[plr] = true end
		for plr in home do
			if plr.Parent == Players then
				plr:SetAttribute("InRound", "")
				moveTo(plr, lookoutCFrame())
				if guards[plr] then Guard.reset(guards[plr], Config, t) end
				publishPlayer(plr)
			end
		end
		for plr in cur.swept do
			if plr.Parent == Players then publishPlayer(plr) end
		end
	end
	cur = nil
	clearDisasterAttrs()
	task.spawn(prepareNextIsland)
end

local function onRoundEvent(ev: string, t: number)
	if ev == "drop" then
		startDrop(t)
	elseif ev == "name" then
		nameDisaster(t)
	elseif ev == "survive" then
		endDisaster(t)
	elseif ev == "empty" then
		saveRoundResults()
		returnAll(t)
	elseif ev == "return" then
		returnAll(t)
	end
end

--============================================================================== remotes from clients

local lastJump: { [Player]: number } = {}
local jumpToastAt: { [Player]: number } = {}
JumpInEvent.OnServerEvent:Connect(function(plr: Player)
	local t = now()
	if lastJump[plr] and t - lastJump[plr] < Config.Rates.JumpInSeconds then
		-- said at most once per JumpInToastSeconds, as SetRest does: a flood of requests is not a flood of replies
		-- (REVIEW-1 F6: 500 requests in one tick were answered with 500 toasts)
		if not jumpToastAt[plr] or t - jumpToastAt[plr] >= Config.Rates.JumpInToastSeconds then
			jumpToastAt[plr] = t
			toast(plr, Round.refusalText("rate", 0))
		end
		return
	end
	lastJump[plr] = t
	local who = {
		inRound = plr:GetAttribute("InRound") or "",
		swept = cur ~= nil and cur.swept[plr] == true,
		resting = isResting(plr),
	}
	local ok, code = Round.jumpInCheck(RC, R, t, who)
	if not ok then
		toast(plr, Round.refusalText(code :: string, secondsToNextDrop()))
		return
	end
	local root = rootOf(plr)
	if not cur or not root then
		toast(plr, Round.refusalText("nospot", 0))
		return
	end
	-- a free, solid level >= 1 cell, away from rings, the funnel's path and other players
	local best = nil
	local candidates = {}
	for i = 1, IC.Grid do
		for j = 1, IC.Grid do
			if cur.map.levels[i][j] >= 1 then table.insert(candidates, { i = i, j = j }) end
		end
	end
	for k = #candidates, 2, -1 do
		local r = 1 + math.min(k - 1, math.floor(mapRand() * k))
		candidates[k], candidates[r] = candidates[r], candidates[k]
	end
	local rel = if cur.nameAt then t - cur.nameAt else 0
	for _, c in candidates do
		local cx, cz = MapGen.cellCenter(IC, c.i, c.j)
		local ok2 = solidAt(cx, cz)
		if ok2 then
			for _, r in cur.rings do
				if Zones.inDisk(r.x, r.z, RING_R + 3, cx, cz) then ok2 = false break end
			end
		end
		if ok2 and cur.tornado then
			ok2 = not Tornado.onPath(cur.tornado, rel - 0.5, rel + Config.Tornado.HorizonSeconds + 2, FUNNEL_R + 4, cx, cz)
		end
		if ok2 then
			for other in cur.on do
				local orr = rootOf(other)
				if orr and math.abs(orr.Position.X - cx) < 10 and math.abs(orr.Position.Z - cz) < 10 then ok2 = false break end
			end
		end
		if ok2 then
			best = c
			break
		end
	end
	if not best then
		toast(plr, Round.refusalText("nospot", 0))
		return
	end
	local cx, cz = MapGen.cellCenter(IC, best.i, best.j)
	local pos = Vector3.new(cx, MapGen.topY(IC, cur.map.levels[best.i][best.j]) + 3, cz)
	cur.on[plr] = "practice"
	cur.heat[plr] = 0
	plr:SetAttribute("InRound", "practice")
	moveTo(plr, facingCentre(pos))
	guards[plr] = guards[plr] or Guard.new()
	Guard.reset(guards[plr], Config, t)
	if cur.kind then
		cur.strikes[plr] = Strikes.newPlayer(Config, cur.kind, 0, t, cur.rand)
	end
	CardEvent:FireClient(plr, "practice-start", {})
end)

local restTimes: { [Player]: { number } } = {}
local restLater: { [Player]: boolean } = {} -- the latest request over the rate, applied when the second is up
local restLaterAt: { [Player]: boolean } = {}
local function applyRest(plr: Player, on: boolean)
	local t = now()
	local keep = {}
	for _, x in restTimes[plr] or {} do if t - x < 1 then table.insert(keep, x) end end
	if #keep >= Config.Rates.SetRestPerSecond then
		-- over the rate (2 a second): never dropped, deferred. The client sends only when its own state changes, so a
		-- dropped request was never sent again: three quick taps on ☕ left the HUD "on a break" while the server kept
		-- dropping the player into rounds (REVIEW-1 F9). The LAST request lands when the oldest leaves the window.
		restLater[plr] = on
		restTimes[plr] = keep
		if not restLaterAt[plr] then
			restLaterAt[plr] = true
			task.delay(1 - (t - keep[1]) + 0.01, function()
				restLaterAt[plr] = nil
				local want = restLater[plr]
				restLater[plr] = nil
				if want ~= nil and plr.Parent == Players then applyRest(plr, want) end
			end)
		end
		return
	end
	table.insert(keep, t)
	restTimes[plr] = keep
	restLater[plr] = nil -- a request that lands now supersedes one still waiting
	-- a break only ever keeps you OFF the next roster; it never takes you out of a round you are in
	plr:SetAttribute("Resting", on)
end
SetRestEvent.OnServerEvent:Connect(function(plr: Player, on: any)
	applyRest(plr, on == true)
end)

--============================================================================== the board: public + friends

local BC = Config.Board
local boardPart: BasePart
do
	local size = Vector3.new(BC.Size[1], BC.Size[2], BC.Size[3])
	local centre = Vector3.new(DECK_CX, LC.FloorY + 1 + size.Y / 2, LC.MinZ + 2)
	boardPart = part({ Name = "StreakBoard", Size = size, CFrame = CFrame.lookAt(centre, centre + Vector3.new(0, 0, 1)),
		Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(24, 26, 36), CanTouch = false, CanQuery = false,
		CastShadow = false })
	local trim = part({ Name = "Trim", Size = Vector3.new(size.X + 0.8, size.Y + 0.8, 0.2),
		CFrame = boardPart.CFrame * CFrame.new(0, 0, size.Z / 2 + 0.05), Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 196, 90), CanCollide = false, CanTouch = false, CanQuery = false })
	trim.Parent = boardPart
	local leg1 = part({ Name = "Leg", Size = Vector3.new(0.6, 1.2, 0.6), Position = centre + Vector3.new(-size.X / 2 + 1, -size.Y / 2 - 0.6, 0),
		Material = Enum.Material.Metal, Color = Color3.fromRGB(60, 60, 66) })
	leg1.Parent = boardPart
	local at = Instance.new("Attachment")
	at.Name = "PromptAt"
	at.Position = Vector3.new(0, -size.Y / 2 + 0.5, -size.Z / 2 - 0.3)
	at.Parent = boardPart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = "🏆 " .. BC.Text.Prompt
	prompt.ObjectText = "Longest streaks"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = BC.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = at
	boardPart.Parent = lookout
end

local lastSwitch: { [Player]: number } = {}
local nameCache: { [number]: string } = {}
local failedNames: { [number]: number } = {}
local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then return cached end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		nameCache[userId] = here.Name
		return here.Name
	end
	local failedAt = failedNames[userId]
	if failedAt and now() - failedAt < 60 then return "#" .. tostring(userId) end
	local ok, res = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	if ok and type(res) == "string" then
		nameCache[userId] = res
		return res
	end
	failedNames[userId] = now()
	return "#" .. tostring(userId)
end
local function withNames(rows: { any }): { any }
	local out = {}
	for i, r in rows do
		out[i] = { rank = r.rank, userId = r.userId, tier = r.tier, you = r.you, name = nameOf(r.userId) }
	end
	return out
end
-- the board's metric (REVIEW-1 F5): the best streak up to Config.Board.StreakCap, and when it was reached
local function liveValue(s: any): number
	if not s or not s.data or s.data.best <= 0 then return 0 end
	local metric, reachedAt = Progress.boardEntry(s.data, Config)
	return Board.encode(metric, reachedAt, BC)
end

publicView = { rows = {}, note = BC.Text.Loading }
-- You are always in your own view (DESIGN.md §7): on the public board, a viewer who is not in the cached top 10 gets
-- their own best pinned under it (rank 0 = "not ranked here"), from memory, so a first survival shows at once.
sendBoard = function(plr: Player, mode: string, view: any)
	local rows = view.rows
	local note = view.note
	if mode == "public" then
		local s = sessions[plr]
		local mine = false
		for _, r in rows do
			if r.userId == plr.UserId then mine = true end
		end
		if not mine and s and s.data and s.data.best > 0 then
			rows = table.clone(rows)
			table.insert(rows, { rank = 0, userId = plr.UserId, tier = (Progress.boardEntry(s.data, Config)), you = true, name = plr.Name })
			if #view.rows == 0 then note = nil end
		end
	end
	BoardEvent:FireClient(plr, { viewer = plr.UserId, mode = mode, rows = rows, note = note })
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
		if uid and type(e.value) == "number" then table.insert(entries, { userId = uid, value = e.value }) end
	end
	local view = Board.publicView(entries, BC)
	publicView = { rows = withNames(view.rows), note = view.note }
end

local friendsCache = Board.newCache(BC.FriendsCacheSeconds)
local friendsFailed = Board.newCache(60)
local scoreCache = Board.newCache(BC.ScoreCacheSeconds)
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, now())
local fetching: { [Player]: boolean } = {}

local function friendIdsOf(plr: Player): ({ number }, boolean)
	local t = now()
	local hit = Board.cacheGet(friendsCache, plr.UserId, t)
	if hit then return hit, false end
	if Board.cacheHas(friendsFailed, plr.UserId, t) then return {}, true end
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
		Board.cachePut(friendsFailed, plr.UserId, true, t)
		return {}, true
	end
	Board.cachePut(friendsCache, plr.UserId, ids, t)
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
	if here and sessions[here] then return liveValue(sessions[here]) end
	local t = now()
	if Board.cacheHas(scoreCache, userId, t) then return Board.cacheGet(scoreCache, userId, t) end
	if not orderedLB then return 0 end
	if not budgetLeft() or not Board.take(readLimiter, t) then return nil end
	local ok, v = pcall(function() return orderedLB:GetAsync(key(userId)) end)
	if not ok then return 0 end
	local value = if type(v) == "number" then v else 0
	Board.cachePut(scoreCache, userId, value, t)
	return value
end

local function showBoard(plr: Player)
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
			values[plr.UserId] = liveValue(sessions[plr])
			local view = Board.friendsView(plr.UserId, values, status, BC)
			sendBoard(plr, "friends", { rows = withNames(view.rows), note = view.note })
		end
		local i, lastPush = 1, -math.huge
		while i <= #ids and plr.Parent == Players and boardMode[plr] == "friends" do
			local v = friendValue(ids[i])
			if v == nil then
				status.checked = i - 1
				if now() - lastPush >= 0.5 then
					push()
					lastPush = now()
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

do
	local prompt = boardPart:FindFirstChild("PromptAt"):FindFirstChild("BoardPrompt") :: ProximityPrompt
	prompt.Triggered:Connect(function(who: Player)
		local t = now()
		if lastSwitch[who] and t - lastSwitch[who] < Config.Rates.BoardSwitchSeconds then
			toast(who, "One switch a second.")
			return
		end
		lastSwitch[who] = t
		boardMode[who] = if boardMode[who] == "friends" then "public" else "friends"
		showBoard(who)
	end)
end

--============================================================================== lifecycle

local function setupCollisions()
	-- characters never collide with each other, so nobody can be pushed into the red (robloxemu has no
	-- PhysicsService: pcall'd, and the real check is EYECANDY.md needs-Studio #9)
	pcall(function()
		local PhysicsService = game:GetService("PhysicsService")
		PhysicsService:RegisterCollisionGroup("DRPlayers")
		PhysicsService:CollisionGroupSetCollidable("DRPlayers", "DRPlayers", false)
	end)
end
setupCollisions()

local function onCharacter(plr: Player, char: Model)
	-- a new character while on the island is a reset: the round is lost (DESIGN.md §2.6)
	if cur and cur.on[plr] ~= nil then
		sweepOut(plr, "reset", false)
	end
	pcall(function()
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") then (d :: any).CollisionGroup = "DRPlayers" end
		end
	end)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Died:Connect(function()
			if cur and cur.on[plr] ~= nil then sweepOut(plr, "reset", false) end
		end)
	end
	-- the engine places the character on LookoutSpawn AFTER this event; only then turn it toward the island
	-- (SPAWN-ORDER §3, second pattern; bounded so a character that never arrives does not park this thread)
	local frames = 0
	while char.Parent == nil and frames < 300 do
		task.wait(1 / 60)
		frames += 1
	end
	if char.Parent == nil or plr.Character ~= char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and onLookout(root.Position) then
		local p = root.Position
		root.CFrame = CFrame.lookAt(p, p + Vector3.new(1, 0, 0))
	end
	if guards[plr] then Guard.reset(guards[plr], Config, now()) end
end

local function onPlayerAdded(plr: Player)
	-- FIRST, before any yield: the engine puts this player on the Lookout at every spawn (SPAWN-ORDER §3)
	plr.RespawnLocation = lookoutSpawn
	plr:SetAttribute("InRound", "")
	plr:SetAttribute("Resting", false)
	plr:SetAttribute("MoveSeq", 0)
	plr:SetAttribute("Loaded", false)
	local s = { token = newToken(plr), data = Progress.default(), canSave = false, loaded = false }
	sessions[plr] = s
	guards[plr] = Guard.new()
	boardMode[plr] = "public"
	plr.CharacterAdded:Connect(function(char) onCharacter(plr, char) end)
	if plr.Character then task.spawn(onCharacter, plr, plr.Character) end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local st = Instance.new("IntValue")
	st.Name = "Streak"
	st.Parent = ls
	local bv = Instance.new("IntValue")
	bv.Name = "Best"
	bv.Parent = ls
	ls.Parent = plr
	publishPlayer(plr)
	loadProfile(plr, s)
	-- the load yields; a player who left meanwhile has nothing more to set up
	if plr.Parent ~= Players or sessions[plr] ~= s then return end
	s.loaded = true
	publishPlayer(plr)
	plr:SetAttribute("Loaded", true)
	sendBoard(plr, "public", publicView)
end

local function onPlayerRemoving(plr: Player)
	local s = sessions[plr]
	-- leaving during a round counts as being swept out, saved in this leave's write (DESIGN.md §2.6)
	if cur and cur.on[plr] ~= nil and not closing then
		sweepOut(plr, "left", false)
	end
	if s then
		s.leaving = true
		if s.canSave then saveProfile(plr, true) end
	end
	sessions[plr] = nil
	guards[plr] = nil
	boardMode[plr] = nil
	lastSwitch[plr] = nil
	fetching[plr] = nil
	lastJump[plr] = nil
	restTimes[plr] = nil
	restLater[plr] = nil
	restLaterAt[plr] = nil
	jumpToastAt[plr] = nil
	dodgeCount[plr] = nil
	if cur then
		cur.on[plr] = nil
		if cur.returning then cur.returning[plr] = nil end
		cur.swept[plr] = nil
		cur.results[plr] = nil
		cur.strikes[plr] = nil
	end
end

-- task.spawn runs the handler at once, up to its first yield, so RespawnLocation is still set before anything
-- yields; the load's retries then wait on their own thread (Roblox gives a handler one anyway; robloxemu fires
-- PlayerAdded inline, where a wait would be an error).
Players.PlayerAdded:Connect(function(plr) task.spawn(onPlayerAdded, plr) end)
for _, plr in Players:GetPlayers() do task.spawn(onPlayerAdded, plr) end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	-- the round is void for everyone: nothing gained, no streak lost (not the player's doing)
	closing = true
	if cur then
		for plr in cur.on do cur.on[plr] = nil end
	end
	for _, plr in Players:GetPlayers() do
		local s = sessions[plr]
		if s and s.canSave then
			s.leaving = true
			saveProfile(plr, true)
		end
	end
	-- a release waiting behind a write in flight is written when that write lands: the server must not shut down
	-- before then (REVIEW-1 F3), and Roblox gives BindToClose 30 s
	local waited = 0
	while writesInFlight > 0 and waited < 25 do
		task.wait(0.1)
		waited += 0.1
	end
end)

--============================================================================== the loops

prepareNextIsland()
phaseAttrs()
workspace:SetAttribute("ServerNow", now())

-- the round clock: 10 Hz, the server's own time
task.spawn(function()
	while true do
		task.wait(RC.TickSeconds)
		if closing then continue end
		local t = now()
		-- the disaster's logic and the round clock are guarded separately: an error in one tick of a disaster costs
		-- that tick, never the clock (fairness check 2026-10-07: one error froze a round forever)
		if R.phase == "drop" or R.phase == "disaster" then
			local okIsland, errIsland = pcall(updateIsland, t)
			if not okIsland then warn("[DisasterRounds] disaster tick failed: " .. tostring(errIsland)) end
		end
		local ok, err = pcall(function()
			local nElig, nOn = 0, 0
			for _, plr in Players:GetPlayers() do
				if eligible(plr) then nElig += 1 end
			end
			if cur then
				for plr in cur.on do
					if plr.Parent == Players then nOn += 1 end
				end
			end
			local ev = Round.step(R, RC, t, { eligible = nElig, onIsland = nOn })
			if ev then onRoundEvent(ev, t) end
			phaseAttrs()
		end)
		if not ok then warn("[DisasterRounds] round tick failed: " .. tostring(err)) end
	end
end)

-- the clock clients extrapolate from
task.spawn(function()
	while true do
		task.wait(1 / RC.ServerNowHz)
		workspace:SetAttribute("ServerNow", now())
	end
end)

-- a lock-renewal write for players with no round result for RenewSeconds
task.spawn(function()
	while true do
		task.wait(10)
		local t = now()
		for plr, s in sessions do
			if s.canSave and s.loaded and t - (s.lastWrite or 0) >= Config.Save.RenewSeconds then
				task.spawn(saveProfile, plr, false)
			end
		end
	end
end)

-- a body that fell off the Lookout (it should not, the walls hold) is put back on the deck
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, plr in Players:GetPlayers() do
			local r = rootOf(plr)
			if r and (cur == nil or cur.on[plr] == nil) and (r.Position.Y < IC.FallOutY or math.abs(r.Position.X) > 400 or math.abs(r.Position.Z) > 400) then
				moveTo(plr, lookoutCFrame())
				if guards[plr] then Guard.reset(guards[plr], Config, now()) end
			end
		end
	end
end)

-- the public board: one GetSortedAsync a minute
task.spawn(function()
	while true do
		refreshPublic()
		for _, plr in Players:GetPlayers() do
			if boardMode[plr] == "public" then sendBoard(plr, "public", publicView) end
		end
		task.wait(BC.PublicCacheSeconds)
	end
end)

print("[DisasterRounds] loaded: island " .. IC.Grid .. "x" .. IC.Grid .. ", cycle " .. Round.cycleSeconds(RC) .. " s")
