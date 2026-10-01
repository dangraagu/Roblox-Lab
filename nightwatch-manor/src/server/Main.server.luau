-- Main.server.luau — authoritative server for "Nightwatch Manor: Haunted Escape Tycoon".
--
-- Per player: one private zone at a far offset, holding a persistent SAFEHOUSE and, 400 studs
-- away, the MANOR for whatever night they are on. Two phases:
--
--   DAY   — you stand in the safehouse. Every upgrade is an in-world pad with a ProximityPrompt;
--           walking up and pressing E buys a level. There is no client -> server remote for
--           buying at all, so there is nothing for a client to lie to.
--   NIGHT — the server builds the manor from Manor.plan (planned from a server-only salt, one per
--           player, night and session, sized by the night: see the secrets block), fills it with relics,
--           starts the Nightwatcher on its patrol, and teleports you into the foyer. Take relics,
--           reach the servants' exit before dread fills. Getting caught or running out of night
--           costs you the haul but never the night you are on. The exit opens only to a walk a
--           person could have made (Crossing.luau): the best night is the highscore board's metric.
--
-- Everything the player can do is an in-world ProximityPrompt whose `.Triggered` handler checks
-- `who == plr`; the only remotes are server -> client (State, Notice). No chase AI, no
-- PathfindingService: the Nightwatcher walks room centres and, once it has seen you, beelines
-- along Manor.pathBetween — our own BFS over at most 18 nodes.
--
-- Persistence uses a soft session-lock (load real data always; save only while we hold the
-- lock). DataStoreService:GetDataStore RAISES in an unpublished place, so it is pcall'd — left
-- bare it kills this whole script at load and the game cannot even be opened in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage
-- Requires go through Instances, the Roblox way. NEVER `require("./Config")`: a path string
-- resolves in the luau CLI and is invalid here, which makes the whole server fail to load
-- while every unit test stays green.
local Config = require(Shared:WaitForChild("Config"))
local Rng = require(Shared:WaitForChild("Rng"))
local Manor = require(Shared:WaitForChild("Manor"))
local Watcher = require(Shared:WaitForChild("Watcher"))
local Upgrades = require(Shared:WaitForChild("Upgrades"))
local Night = require(Shared:WaitForChild("Night"))
local Fx = require(Shared:WaitForChild("Fx"))
local Board = require(Shared:WaitForChild("Board"))
local Crossing = require(Shared:WaitForChild("Crossing"))
local Salt = require(Shared:WaitForChild("Salt"))
local ServerStorage = game:GetService("ServerStorage")

-- Visuals from the first build, not as a later pass: this is a horror game, and without the
-- rig the manor reads as grey boxes in daylight.
Fx.applyLighting(Fx.Presets.Horror)

-- ------------------------------------------------------------------ Remotes (server -> client)
local Remotes = Instance.new("Folder")
Remotes.Name = "ManorRemotes"
Remotes.Parent = ReplicatedStorage
local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = Remotes
	return r
end
local StateRemote = makeRemote("State") -- full HUD state
local NoticeRemote = makeRemote("Notice") -- transient events: took a relic, spotted, night over

-- ------------------------------------------------------------------ DataStore
local okStore, profileStore = pcall(function()
	return DataStoreService:GetDataStore(Config.Save.Store)
end)
if not okStore then
	profileStore = nil
	warn("[Nightwatch] DataStore unavailable — running without saves (Studio API access off?)")
end
local okBoard, bestBoard = pcall(function()
	return DataStoreService:GetOrderedDataStore(Config.Save.LeaderStore)
end)
if not okBoard then
	bestBoard = nil
end

type Profile = {
	night: number,
	stash: number,
	best: number,
	levels: { [string]: number },
	canSave: boolean, -- true only while we hold the session lock
	loaded: boolean, -- the DataStore round-trip has landed; nothing may be SPENT before it does
	lockToken: string, -- STABLE per session; never a timestamp (a timestamp fires against itself)
	closing: boolean, -- set before the releasing save, blocks any further renewal
	bestAt: number, -- unix time the best night was FIRST reached (the board's tie-break); saved
	boardBest: number, -- the best night last written to the board; saved, so a rejoin does not write it again
	lastPublishAt: number,
}

type Run = {
	phase: string, -- "DAY" | "NIGHT"
	token: number, -- bumped on every phase change; the night loop dies when it no longer matches
	carried: { string },
	plan: any?,
	points: { { x: number, z: number } }?,
	watcher: any?,
	watcherModel: Model?,
	elapsed: number,
	dreadTotal: number,
	effects: any,
	relicsTotal: number,
	relicsLeft: number,
	spotted: boolean,
	near: boolean, -- the Alarm Bell heard it (independent of sight)
	ending: boolean, -- a resolution is already in flight; ignore further triggers
	crossSeconds: number, -- Crossing.minSeconds for this night's plan: the exit stays barred until the clock passes it
}

local profiles: { [Player]: Profile } = {}
local runs: { [Player]: Run } = {}
local zones: { [Player]: Model } = {}

-- One clock for the board's caches and write throttle. os.clock() is CPU time in Roblox (a quiet server barely
-- counts), so it is wrong here. GetServerTimeNow is the wall clock; tick() is the fallback for engines (and the
-- headless harness) that do not have it. Checked once at boot (the pattern plus1-jump and fork-tower use).
local clock: () -> number
do
	local ok, t = pcall(function()
		return (workspace :: any):GetServerTimeNow()
	end)
	clock = if ok and type(t) == "number" then function()
		return (workspace :: any):GetServerTimeNow()
	end else tick
end

-- ------------------------------------------------------------------ manor secrets (server-only)
-- docs/complete-game-standard.md §1, Salt.luau. Every manor is planned from two 32-bit halves drawn here, never from
-- the public WorldSeed: Config and Manor ship to every client, so a public seed let anyone compute every night's
-- rooms, relics, exit and patrol ahead of time. One pair per player, per night, per SESSION (`manorSalt`): a retry
-- after being caught is the same manor, so you learn it the way a person does (and the pacing model's first-time
-- player, who remembers what it walked, is this game); the next night, a rejoin or another player draws new halves,
-- and so does the same night after Config.Manor.ShiftAfterFails failures in a row there ("the manor has shifted": a
-- player is never stuck in halls they cannot get out of) (check_nightwatchmanor_guard). `saltSource` is a local of this
-- script, seeded by the engine, and a fresh Random is XORed into every draw, so predicting the next manor needs the
-- internal state of both. The halves are recorded in ServerStorage (which never replicates) as "night:a:b" under the
-- player's key, so the server's own tools and the headless checks can rebuild the plan; nothing about them reaches
-- a client: no attribute outside ServerStorage, no remote, no Instance name.
-- `PublicLayouts`: an attribute on the same folder, unset unless somebody sets it from Studio's command bar (Server
-- context). While it is true, nights are planned from the old public seed, which is what the thumbnail recipe in
-- EYECANDY.md §12 finds its rooms by. A client cannot set it.
local secrets = Instance.new("Folder")
secrets.Name = "NightwatchSecrets"
secrets.Parent = ServerStorage
local saltSource = Random.new()
local manorSalt: { [Player]: { night: number, a: number, b: number, fails: number } } = {}
local function drawHalf(): number
	local fresh = Random.new()
	local hi = bit32.bxor(saltSource:NextInteger(0, 65535), fresh:NextInteger(0, 65535))
	local lo = bit32.bxor(saltSource:NextInteger(0, 65535), fresh:NextInteger(0, 65535))
	return hi * 65536 + lo
end

-- ------------------------------------------------------------------ zone indices
-- Recycled through a free list, so a long-lived server never marches out to a hundred thousand
-- studs where physics and render precision fall apart.
local nextZoneIndex = 0
local freeZoneIndices: { number } = {}

local function acquireZoneIndex(): number
	if #freeZoneIndices > 0 then
		table.sort(freeZoneIndices)
		return table.remove(freeZoneIndices, 1) :: number
	end
	nextZoneIndex += 1
	return nextZoneIndex
end

local function releaseZoneIndex(index: number)
	if index <= 0 then
		return
	end
	for _, taken in freeZoneIndices do
		if taken == index then
			return -- never double-release
		end
	end
	table.insert(freeZoneIndices, index)
end

local function zoneOrigin(index: number): Vector3
	return Vector3.new(index * Config.ZoneSpacing, 100, 0)
end

local function manorOrigin(index: number): Vector3
	local o = Config.Hub.ManorOffset
	return zoneOrigin(index) + Vector3.new(o[1], o[2], o[3])
end

-- ------------------------------------------------------------------ build helpers
local WOOD = Color3.fromRGB(78, 58, 44)
local STONE = Color3.fromRGB(58, 56, 62)
local DARKWOOD = Color3.fromRGB(48, 36, 28)
local CANDLE = Color3.fromRGB(255, 186, 96)
local GHOST = Color3.fromRGB(150, 200, 210)

local function newPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function makePrompt(parent: BasePart, action: string, object: string, key: Enum.KeyCode?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	if key then
		pp.KeyboardKeyCode = key
	end
	pp.Parent = parent
	return pp
end

local function candle(part: BasePart, brightness: number, range: number, color: Color3?)
	local pl = Instance.new("PointLight")
	pl.Name = "PL"
	pl.Brightness = brightness
	pl.Range = range
	pl.Color = color or CANDLE
	pl.Parent = part
end

-- ------------------------------------------------------------------ ROOM_BUILDERS
-- Dispatched by room KIND id. Each one dresses an already-built shell (floor, ceiling, walls
-- and doorways are generic) with the furniture that makes the room recognisable. Signature:
--   (folder, centre: Vector3, room, plan) -> ()
-- Adding a kind to Config.Manor.Kinds does NOT make it exist; it needs an entry here, and the
-- startup guard below refuses to boot without one.
local ROOM_BUILDERS: { [string]: (Folder, Vector3, any, any) -> () } = {
	foyer = function(folder, c)
		newPart({ Name = "Rug", Size = Vector3.new(14, 0.2, 14), CFrame = CFrame.new(c + Vector3.new(0, 1.1, 0)), Color = Color3.fromRGB(96, 30, 34), Material = Enum.Material.Fabric, Parent = folder })
		local post = newPart({ Name = "FoyerLamp", Size = Vector3.new(1, 7, 1), CFrame = CFrame.new(c + Vector3.new(-12, 4.5, -12)), Color = DARKWOOD, Parent = folder })
		local flame = newPart({ Name = "FoyerFlame", Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(c + Vector3.new(-12, 8.4, -12)), Color = CANDLE, Material = Enum.Material.Neon, Parent = folder })
		candle(flame, 3, 26)
		local _ = post
	end,
	vestibule = function(folder, c)
		-- The way out. The door itself is built by buildManor (it carries the prompt), so this
		-- only marks the room: boot rack, coat hooks, and a light you can see from a doorway.
		newPart({ Name = "BootRack", Size = Vector3.new(8, 1.5, 2), CFrame = CFrame.new(c + Vector3.new(-11, 1.7, 6)), Color = DARKWOOD, Material = Enum.Material.Wood, Parent = folder })
		local lamp = newPart({ Name = "ExitLamp", Size = Vector3.new(2, 0.6, 2), CFrame = CFrame.new(c + Vector3.new(0, 12.5, 0)), Color = Color3.fromRGB(120, 220, 140), Material = Enum.Material.Neon, Parent = folder })
		candle(lamp, 4, 34, Color3.fromRGB(120, 220, 140))
	end,
	hall = function(folder, c)
		for i = -1, 1, 2 do
			newPart({ Name = "Portrait", Size = Vector3.new(0.4, 6, 4), CFrame = CFrame.new(c + Vector3.new(i * 18.5, 8, -6)), Color = Color3.fromRGB(30, 26, 24), Material = Enum.Material.Wood, Parent = folder })
		end
		newPart({ Name = "Runner", Size = Vector3.new(6, 0.2, 34), CFrame = CFrame.new(c + Vector3.new(0, 1.1, 0)), Color = Color3.fromRGB(74, 26, 30), Material = Enum.Material.Fabric, Parent = folder })
	end,
	library = function(folder, c)
		for i = -1, 1, 2 do
			newPart({ Name = "Shelf", Size = Vector3.new(3, 10, 16), CFrame = CFrame.new(c + Vector3.new(i * 15, 6, 0)), Color = DARKWOOD, Material = Enum.Material.Wood, Parent = folder })
		end
		newPart({ Name = "ReadingTable", Size = Vector3.new(8, 3, 4), CFrame = CFrame.new(c + Vector3.new(0, 2.5, 8)), Color = WOOD, Material = Enum.Material.Wood, Parent = folder })
	end,
	dining = function(folder, c)
		newPart({ Name = "LongTable", Size = Vector3.new(8, 3, 22), CFrame = CFrame.new(c + Vector3.new(0, 2.5, 0)), Color = WOOD, Material = Enum.Material.Wood, Parent = folder })
		for i = 1, 4 do
			newPart({ Name = "Chair" .. i, Size = Vector3.new(2, 4, 2), CFrame = CFrame.new(c + Vector3.new(if i % 2 == 0 then 7 else -7, 3, -8 + math.floor((i - 1) / 2) * 12)), Color = DARKWOOD, Parent = folder })
		end
		local cand = newPart({ Name = "Candelabra", Size = Vector3.new(1, 2.5, 1), CFrame = CFrame.new(c + Vector3.new(0, 5.2, 0)), Color = CANDLE, Material = Enum.Material.Neon, Parent = folder })
		candle(cand, 2.5, 22)
	end,
	nursery = function(folder, c)
		newPart({ Name = "Crib", Size = Vector3.new(6, 4, 4), CFrame = CFrame.new(c + Vector3.new(-8, 3, -6)), Color = Color3.fromRGB(150, 140, 130), Material = Enum.Material.Wood, Parent = folder })
		newPart({ Name = "RockingHorse", Size = Vector3.new(3, 3, 5), CFrame = CFrame.new(c + Vector3.new(9, 2.5, 7)) * CFrame.Angles(0, math.rad(25), 0), Color = Color3.fromRGB(120, 95, 70), Material = Enum.Material.Wood, Parent = folder })
		newPart({ Name = "ToyBox", Size = Vector3.new(5, 3, 3), CFrame = CFrame.new(c + Vector3.new(10, 2.5, -9)), Color = Color3.fromRGB(90, 70, 110), Parent = folder })
	end,
	cellar = function(folder, c)
		for i = 1, 3 do
			newPart({ Name = "Barrel" .. i, Size = Vector3.new(4, 5, 4), CFrame = CFrame.new(c + Vector3.new(-12 + i * 5, 3.5, -11)), Color = Color3.fromRGB(64, 44, 30), Material = Enum.Material.Wood, Parent = folder })
		end
		newPart({ Name = "Puddle", Size = Vector3.new(12, 0.15, 12), CFrame = CFrame.new(c + Vector3.new(4, 1.08, 5)), Color = Color3.fromRGB(30, 40, 45), Material = Enum.Material.Glass, Transparency = 0.35, Parent = folder })
	end,
	chapel = function(folder, c)
		newPart({ Name = "Altar", Size = Vector3.new(7, 4, 3), CFrame = CFrame.new(c + Vector3.new(0, 3, -12)), Color = STONE, Material = Enum.Material.Slate, Parent = folder })
		for i = -1, 1, 2 do
			newPart({ Name = "Pew", Size = Vector3.new(12, 2.5, 2), CFrame = CFrame.new(c + Vector3.new(0, 2.2, i * 6)), Color = DARKWOOD, Material = Enum.Material.Wood, Parent = folder })
		end
		local glass = newPart({ Name = "StainedGlass", Size = Vector3.new(8, 9, 0.4), CFrame = CFrame.new(c + Vector3.new(0, 9, -19)), Color = Color3.fromRGB(120, 60, 140), Material = Enum.Material.Neon, Transparency = 0.25, Parent = folder })
		candle(glass, 2, 26, Color3.fromRGB(150, 90, 190))
	end,
}

-- ------------------------------------------------------------------ RELIC_BUILDERS
-- Dispatched by relic TIER id. Builds the thing standing on the pedestal. Signature:
--   (parent, top: Vector3) -> BasePart   (the returned part is what gets the glow)
local RELIC_BUILDERS: { [string]: (Instance, Vector3) -> BasePart } = {
	trinket = function(parent, top)
		local p = newPart({ Name = "Relic", Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(top + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0.5, 0.5, 0), Color = Color3.fromRGB(190, 170, 110), Material = Enum.Material.Metal, Parent = parent })
		return p
	end,
	portrait = function(parent, top)
		local p = newPart({ Name = "Relic", Size = Vector3.new(2.6, 3.4, 0.4), CFrame = CFrame.new(top + Vector3.new(0, 1.9, 0)), Color = Color3.fromRGB(120, 60, 60), Material = Enum.Material.Wood, Parent = parent })
		return p
	end,
	reliquary = function(parent, top)
		local p = newPart({ Name = "Relic", Size = Vector3.new(2, 2.4, 2), CFrame = CFrame.new(top + Vector3.new(0, 1.4, 0)), Color = Color3.fromRGB(214, 220, 232), Material = Enum.Material.Metal, Parent = parent })
		return p
	end,
	heart = function(parent, top)
		local p = newPart({ Name = "Relic", Size = Vector3.new(2.2, 2.2, 2.2), CFrame = CFrame.new(top + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0.6, 0.8, 0), Color = Color3.fromRGB(200, 40, 60), Material = Enum.Material.Neon, Parent = parent })
		return p
	end,
}

-- ------------------------------------------------------------------ UPGRADE_PROPS
-- Dispatched by upgrade id. Builds the VISIBLE safehouse hardware for `level` levels, so the
-- tycoon side is something you can see growing rather than a number in a menu. Signature:
--   (parent, pad: BasePart, level: number) -> ()
local UPGRADE_PROPS: { [string]: (Instance, BasePart, number) -> () } = {
	lanterns = function(parent, pad, level)
		for i = 1, level do
			local p = newPart({ Name = "Lantern" .. i, Size = Vector3.new(1.2, 1.6, 1.2), CFrame = pad.CFrame * CFrame.new(-2.4 + (i - 1) * 1.2, 2.4, 0), Color = CANDLE, Material = Enum.Material.Neon, Parent = parent })
			candle(p, 1.6, 16)
		end
	end,
	wardstones = function(parent, pad, level)
		for i = 1, level do
			newPart({ Name = "Ward" .. i, Size = Vector3.new(1.2, 2.4 + i * 0.2, 1.2), CFrame = pad.CFrame * CFrame.new(-2.4 + (i - 1) * 1.2, 2.2, 0) * CFrame.Angles(0, math.rad(i * 17), 0), Color = Color3.fromRGB(96, 120, 140), Material = Enum.Material.Slate, Parent = parent })
		end
	end,
	beartraps = function(parent, pad, level)
		for i = 1, level do
			newPart({ Name = "Trap" .. i, Size = Vector3.new(1.8, 0.5, 1.8), CFrame = pad.CFrame * CFrame.new(-2.6 + (i - 1) * 1.3, 1.3, 0), Color = Color3.fromRGB(120, 120, 128), Material = Enum.Material.Metal, Parent = parent })
		end
	end,
	alarmbell = function(parent, pad, level)
		for i = 1, level do
			local b = newPart({ Name = "Bell" .. i, Size = Vector3.new(1.6, 1.8, 1.6), CFrame = pad.CFrame * CFrame.new(-1.8 + (i - 1) * 1.8, 3.2, 0), Color = Color3.fromRGB(200, 170, 80), Material = Enum.Material.Metal, Parent = parent })
			local _ = b
		end
	end,
	relicvault = function(parent, pad, level)
		for i = 1, level do
			newPart({ Name = "VaultBox" .. i, Size = Vector3.new(2, 1.4, 2), CFrame = pad.CFrame * CFrame.new(0, 1.7 + (i - 1) * 1.5, 0), Color = Color3.fromRGB(80, 90, 110), Material = Enum.Material.Metal, Parent = parent })
		end
	end,
	lockbox = function(parent, pad, level)
		for i = 1, level do
			newPart({ Name = "Lockbox" .. i, Size = Vector3.new(2.4, 1.6, 1.8), CFrame = pad.CFrame * CFrame.new(-1.6 + (i - 1) * 1.6, 1.8, 0), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal, Parent = parent })
		end
	end,
	floodlights = function(parent, pad, level)
		for i = 1, level do
			local p = newPart({ Name = "Floodlight" .. i, Size = Vector3.new(1.6, 1, 1.6), CFrame = pad.CFrame * CFrame.new(-2.2 + (i - 1) * 1.5, 4.2, 0), Color = Color3.fromRGB(240, 245, 255), Material = Enum.Material.Neon, Parent = parent })
			candle(p, 3, 30, Color3.fromRGB(220, 235, 255))
		end
	end,
}

-- ------------------------------------------------------------------ startup guards
-- Refuse to start when a catalog entry has no handler. Each of these three is an UNREACHABLE
-- or SILENTLY-BROKEN game, not a cosmetic gap:
--   * a room kind with no builder is an empty shell the player walks through wondering what
--     they missed, and it can hold relics, so the loot is in a room that looks unfinished;
--   * a relic tier with no builder is a pedestal with nothing on it — the plan counts a relic
--     that cannot be picked up, so a full clear of the manor is impossible;
--   * an upgrade with no prop is relics spent on a pad that never changes, which reads exactly
--     like the purchase failed.
-- All three are invisible from inside the game and green to every unit test, which is why this
-- is a hard error at boot, once, loud in the F9 console — the pattern taken from the sibling
-- anomaly-observatory, where the same guard catches an unwinnable round.
for _, kind in Config.Manor.Kinds do
	if ROOM_BUILDERS[kind.id] == nil then
		error(string.format(
			"[Nightwatch] room kind '%s' (%s) has no ROOM_BUILDERS handler. Every kind must dress "
				.. "its room, or the manor has a blank space in it that can still hold loot.",
			tostring(kind.id), tostring(kind.name)
		), 0)
	end
end
for _, tier in Config.Relics.Tiers do
	if RELIC_BUILDERS[tier.id] == nil then
		error(string.format(
			"[Nightwatch] relic tier '%s' (%s) has no RELIC_BUILDERS handler. The plan would place "
				.. "a relic nothing builds, so it could never be picked up.",
			tostring(tier.id), tostring(tier.name)
		), 0)
	end
end
for _, up in Config.Upgrades.Catalog do
	if UPGRADE_PROPS[up.id] == nil then
		error(string.format(
			"[Nightwatch] upgrade '%s' (%s) has no UPGRADE_PROPS handler. Buying it would cost "
				.. "relics and change nothing the player can see.",
			tostring(up.id), tostring(up.name)
		), 0)
	end
end

-- A fourth guard, and the one that would have caught the worst defect this game shipped with.
-- The Nightwatcher's speeds are bounded against Config.Player.WalkSpeed inside Watcher.speed; if
-- a retune ever drives the CEILING itself up to the player, being seen becomes being caught on
-- every night forever, with no counterplay and nothing on screen to explain it. That is a BALANCE
-- regression, which is exactly the class a unit test cannot see — so it is a boot failure
-- instead, loud, once, in the F9 console.
--
-- The audit itself lives in Watcher (pure, and tested from the CLI in tests/Watcher.spec.luau).
-- The first version of this guard was written here and swept `Watcher.speed`, which has already
-- been clamped by the time it returns — so it could only ever catch a MaxSpeedFraction >= 1,
-- while its own error text told the reader to lower three constants it could not see. The second
-- half of the audit is that ceiling BINDING: the game is still playable, but the knobs underneath
-- have stopped meaning anything, so it warns rather than raising. The headless gate asserts the
-- server boots with zero warnings, so it is still caught by something.
do
	local ok, why = Watcher.speedAudit(Config)
	if not ok then
		error(why, 0)
	end
	local binds, note = Watcher.ceilingBinds(Config)
	if binds then
		warn(note)
	end
end

-- ------------------------------------------------------------------ the world's own floor
-- A joining player exists before their zone does, and Roblox does not wait for us. With no
-- SpawnLocation anywhere in the place and nothing built at the origin — which is what this game
-- used to be — the character spawns into empty air and falls. At the default gravity it passes
-- FallenPartsDestroyHeight (-500) in roughly 2.3 seconds, and is then DESTROYED: the player dies
-- without ever seeing the game and waits out the respawn. The teleport meant to rescue them sat
-- behind a blocking DataStore round-trip that routinely takes longer than that.
--
-- Three things fix it, and all three are here: this floor, which exists before anybody can join;
-- a real SpawnLocation in each safehouse with `plr.RespawnLocation` pointed at it (buildSafehouse);
-- and building the zone BEFORE the profile round-trip rather than after it (onPlayerAdded).
local originFolder = Instance.new("Folder")
originFolder.Name = "NightwatchOrigin"
originFolder.Parent = workspace
do
	newPart({
		Name = "OriginPlate", Size = Vector3.new(48, 2, 48), CFrame = CFrame.new(0, 0, 0),
		Color = STONE, Material = Enum.Material.Slate, Parent = originFolder,
	})
	local sp = Instance.new("SpawnLocation")
	sp.Name = "OriginSpawn"
	sp.Size = Vector3.new(12, 1, 12)
	sp.CFrame = CFrame.new(0, 1.5, 0)
	sp.Anchored = true
	sp.CanCollide = true
	sp.Transparency = 1
	sp.Neutral = true
	sp.Duration = 0 -- no forcefield
	sp.Enabled = true -- explicit: a disabled SpawnLocation is not a legal RespawnLocation either
	sp.Parent = originFolder
end

-- ------------------------------------------------------------------ persistence
local PUBLISH_MIN_INTERVAL = 30

local function profileKey(plr: Player): string
	return "u_" .. plr.UserId
end

local function newSessionToken(): string
	local ok, guid = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	if ok and typeof(guid) == "string" then
		return guid
	end
	return string.format("%d-%d", os.time(), math.random(1, 2147483647))
end

local function defaultProfile(): Profile
	return {
		night = Config.Night.StartNight,
		stash = Config.Night.StartStash,
		best = 0,
		levels = {},
		canSave = false,
		loaded = false,
		lockToken = "",
		closing = false,
		bestAt = 0,
		boardBest = 0,
		lastPublishAt = -math.huge,
	}
end

-- One lock-claim attempt. Always returns the stored data (so a second session can still PLAY,
-- read-only), plus whether we now hold the lock.
--
-- Roblox may call an UpdateAsync transform MORE THAN ONCE, and a transform returning nil
-- ABORTS the write. Both are load-bearing here: `got` is assigned every call so the last one
-- wins, and losing the race returns nil rather than stamping our token over theirs.
local function claimProfile(plr: Player, token: string): { got: boolean, data: any }
	if not profileStore then
		return { got = false, data = nil }
	end
	local result = { got = false, data = nil }
	local ok = pcall(function()
		(profileStore :: any):UpdateAsync(profileKey(plr), function(old)
			old = old or {}
			local data = old.data
			local lock = old.lock
			local now = os.time()
			local mine = lock == nil
				or lock.token == token
				or (now - (tonumber(lock.at) or 0)) > Config.Save.SessionLockSeconds
			result = { got = mine, data = data }
			if not mine then
				return nil -- someone else is live; leave their lock alone
			end
			return { data = data, lock = { token = token, at = now } }
		end)
	end)
	if not ok then
		result = { got = false, data = nil }
	end
	return result
end

-- OWNERSHIP (second review, 2026-09-30; docs/complete-game-standard.md §1). A write lands only while the stored
-- record still carries THIS session's token. It used to land whenever the stored lock was nil or older than
-- SessionLockSeconds, whoever's token it carried: a server whose saves stalled past 45 s lost the lock, the player
-- carried on on another server, that server released the lock on leaving, and the stale server's next autosave
-- rolled the player back (robloxemu/check_nightwatchmanor_save.luau). A lock of ours that merely went stale is still
-- ours: nobody else wrote since. The first refused write turns canSave off for good and tells the player once.
-- Releasing keeps the token and sets `at` to 0 (claimProfile treats that as expired, so the next session takes it),
-- so a second releasing write of ours (BindToClose, then PlayerRemoving) still recognises the record as its own.
-- `lost` is assigned on every invocation: Roblox may run the transform more than once, and the last run decides.
local function saveProfile(plr: Player, releasing: boolean?)
	local prof = profiles[plr]
	if not prof or not profileStore or not prof.canSave then
		return
	end
	local payload = {
		night = prof.night,
		stash = prof.stash,
		best = prof.best,
		bestAt = prof.bestAt,
		boardBest = prof.boardBest,
		levels = prof.levels,
	}
	local lost = false
	pcall(function()
		(profileStore :: any):UpdateAsync(profileKey(plr), function(old)
			old = old or {}
			local lock = old.lock
			if type(lock) ~= "table" or lock.token ~= prof.lockToken then
				lost = true
				return nil -- another session has taken (or released) this profile since we loaded it: leave it alone
			end
			lost = false
			local at = if releasing or prof.closing then 0 else os.time()
			return { data = payload, lock = { token = prof.lockToken, at = at } }
		end)
	end)
	if lost then
		prof.canSave = false
		if not prof.closing then
			NoticeRemote:FireClient(plr, { kind = "READONLY", text = "Progress is no longer being saved",
				detail = "This profile was opened in another session since you joined. Rejoin to carry on from there." })
		end
	end
end

-- THE HIGHSCORE BOARD's write (docs/complete-game-standard.md §3, Board.luau). The value is the best night survived,
-- encoded so a tie goes to whoever reached it first (Board.encode, stamped with prof.bestAt, the unix time of the
-- extraction that first set it). Written only when the night improves on what this profile last wrote, only while
-- this session holds the profile's lock (a read-only session plays on, but its nights are not saved, so they must not
-- reach the board either), and through UpdateAsync + Board.keepHigher, so nothing, not even a stale server, can lower
-- or re-stamp what is stored. At most one write per PUBLISH_MIN_INTERVAL; the autosave and PlayerRemoving catch up.
local function writeBoard(plr: Player, force: boolean?)
	local prof = profiles[plr]
	if not prof or not bestBoard or not prof.canSave or prof.best <= prof.boardBest then
		return
	end
	local now = clock()
	if not force and (now - prof.lastPublishAt) < PUBLISH_MIN_INTERVAL then
		return
	end
	prof.lastPublishAt = now
	local value = Board.encode(prof.best, prof.bestAt, Config.Board)
	local ok = pcall(function()
		(bestBoard :: any):UpdateAsync(Board.key(plr.UserId), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	if ok then
		prof.boardBest = prof.best -- also when keepHigher aborted: what is stored is at least as high
	end
end

-- ------------------------------------------------------------------ HUD state
local function upgradeRows(prof: Profile)
	local rows = {}
	for _, e in Config.Upgrades.Catalog do
		local level = Upgrades.level(prof.levels, e.id)
		table.insert(rows, {
			id = e.id,
			name = e.name,
			blurb = e.blurb,
			level = level,
			max = e.max,
			cost = Upgrades.cost(Config, e.id, level), -- nil once maxed
		})
	end
	return rows
end

local function pushState(plr: Player)
	local prof = profiles[plr]
	local run = runs[plr]
	if not prof or not run then
		return
	end
	local dread = if run.phase == "NIGHT" then Watcher.dread(run.elapsed, run.dreadTotal) else 0
	StateRemote:FireClient(plr, {
		phase = run.phase,
		night = prof.night,
		best = prof.best,
		stash = prof.stash,
		hubLevel = Upgrades.hubLevel(prof.levels),
		carried = #run.carried,
		carriedWorth = Night.payout(Config, run.carried, run.effects),
		relicsLeft = run.relicsLeft,
		relicsTotal = run.relicsTotal,
		dread = dread,
		secondsLeft = math.max(run.dreadTotal - run.elapsed, 0),
		spotted = run.spotted,
		near = run.near,
		canSave = prof.canSave,
		upgrades = upgradeRows(prof),
	})
end

local function notice(plr: Player, kind: string, text: string, detail: string?)
	NoticeRemote:FireClient(plr, { kind = kind, text = text, detail = detail })
end

-- ------------------------------------------------------------------ the highscore board (public + friends)
-- docs/complete-game-standard.md §3, Board.luau. The metric is the best night survived, measured by the server
-- (resolveNight, behind the crossing guard on the Servants' Exit). Stored encoded in Config.Save.LeaderStore
-- (writeBoard: ties to whoever got there first, written only when it improves). The public top 10 is read at most
-- once per PublicCacheSeconds, and only while somebody is on the server. Friends are read only when a player asks
-- for them at the board, capped at FriendsCap, cached, and throttled (Board.newLimiter + Roblox's own budget). Names
-- come from players on the server, the friends list or GetNameFromUserIdAsync, kept in memory and never stored.
-- The board itself stands in every safehouse (buildBoard). The server draws it: a safehouse is its player's alone,
-- so there is nothing for a client to draw, and no remote.
local BC = Config.Board
local BOARD_GOLD = Color3.fromRGB(255, 205, 90)
local BOARD_TEXT = Color3.fromRGB(225, 222, 235)
local BOARD_DIM = Color3.fromRGB(160, 150, 175)
local BOARD_SIZE = Vector3.new(12, 8, 0.6) -- 480 x 320 px at 40 px per stud

type BoardUi = { mode: TextLabel, rows: { TextLabel }, note: TextLabel }
local boardUi: { [Player]: BoardUi } = {}
local boardMode: { [Player]: string } = {} -- "public" | "friends", per player
local publicView: any = { rows = {}, note = BC.Text.Loading }

local nameCache: { [number]: string } = {}
-- A player on this server is asked first (their current name, free); then the cache; then one lookup, cached.
local function nameOf(userId: number): string
	local here = Players:GetPlayerByUserId(userId)
	if here then
		nameCache[userId] = here.Name
		return here.Name
	end
	local cached = nameCache[userId]
	if cached then return cached end
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
		out[i] = { rank = r.rank, userId = r.userId, night = r.night, you = r.you, name = nameOf(r.userId) }
	end
	return out
end

local function renderBoard(plr: Player, mode: string, view: any)
	local ui = boardUi[plr]
	if not ui then return end
	local friends = mode == "friends"
	ui.mode.Text = if friends then "👥 FRIENDS" else "🌍 PUBLIC"
	ui.mode.TextColor3 = if friends then Color3.fromRGB(150, 220, 255) else BOARD_GOLD
	local rows = if type(view.rows) == "table" then view.rows else {}
	for i, label in ui.rows do
		local r = rows[i]
		if r then
			local you = r.you == true or r.userId == plr.UserId
			label.Text = Board.rowText({ rank = r.rank, name = r.name, night = r.night, you = you }, BC)
			label.TextColor3 = if you then BOARD_GOLD else BOARD_TEXT
			label.Visible = true
		else
			label.Text = ""
			label.Visible = false
		end
	end
	if type(view.note) == "string" and view.note ~= "" then
		ui.note.Text = view.note
		ui.note.Position = UDim2.new(0, 20, 0, 76 + #rows * 21)
		ui.note.Visible = true
	else
		ui.note.Text = ""
		ui.note.Visible = false
	end
end

local function refreshPublic()
	if not bestBoard then
		publicView = Board.publicView({}, BC)
		return
	end
	local ok, page = pcall(function()
		return (bestBoard :: any):GetSortedAsync(false, BC.PublicRows)
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

-- A player's own value, from memory (fresher than the store, which is written at the save after a new best).
local function liveValue(prof: Profile?): number
	if not prof or not prof.loaded or prof.best <= 0 then return 0 end
	return Board.encode(prof.best, prof.bestAt, BC)
end

local friendsCache = Board.newCache(BC.FriendsCacheSeconds)
local friendsFailed = Board.newCache(60)
local scoreCache = Board.newCache(BC.ScoreCacheSeconds)
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, clock())
local fetching: { [Player]: boolean } = {}

-- A player's friends, capped at FriendsCap, cached; a failed fetch is retried after a minute, not on every press.
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
	-- The cap is held by the two checks inside (an id only while under it; stop paging at it). The loop condition used
	-- to repeat it, and a mutation deleting that copy changed nothing (pass 2 sweep, B5): a guard nothing can reach.
	while not broken do
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

-- Always leave BudgetReserve GetAsync in Roblox's own budget (when it cannot be read, only the limiter applies).
local function budgetLeft(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return not (ok and type(budget) == "number" and budget < BC.BudgetReserve)
end

-- A friend's stored value (0 = never got out), or nil when the read is throttled (try again later). A failed read
-- counts as 0 and is not cached, so one bad key does not stop the list.
local function friendValue(userId: number): number?
	local here = Players:GetPlayerByUserId(userId)
	if here and profiles[here] then return liveValue(profiles[here]) end
	local now = clock()
	if Board.cacheHas(scoreCache, userId, now) then return Board.cacheGet(scoreCache, userId, now) end
	if not bestBoard then return 0 end
	if not budgetLeft() or not Board.take(readLimiter, now) then return nil end
	local ok, v = pcall(function()
		return (bestBoard :: any):GetAsync(Board.key(userId))
	end)
	if not ok then return 0 end
	local value = if type(v) == "number" then v else 0
	Board.cachePut(scoreCache, userId, value, now)
	return value
end

local function showFriends(plr: Player)
	if fetching[plr] then
		renderBoard(plr, "friends", { rows = {}, note = BC.Text.Loading }) -- the one running will draw soon
		return
	end
	fetching[plr] = true
	task.spawn(function()
		renderBoard(plr, "friends", { rows = {}, note = BC.Text.Loading })
		local ids, failedList = friendIdsOf(plr)
		local values: { [number]: number } = {}
		local status = { friendCount = #ids, checked = 0, failed = failedList }
		local function push()
			values[plr.UserId] = liveValue(profiles[plr])
			local view = Board.friendsView(plr.UserId, values, status, BC)
			renderBoard(plr, "friends", { rows = withNames(view.rows), note = view.note })
		end
		local i, lastPush = 1, -math.huge
		while i <= #ids and plr.Parent == Players and boardMode[plr] == "friends" do
			local v = friendValue(ids[i])
			if v == nil then
				status.checked = i - 1
				if clock() - lastPush >= 0.5 then
					push()
					lastPush = clock()
				end
				task.wait(1) -- throttled: wait for the limiter
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

-- The board in one safehouse: on the east wall by the north-east corner, about 29 studs from the spawn pad and in
-- sight of it, clear of the pads (x 19.5-26.5), the hearth, the props and the way to the manor door. Its prompt is F
-- (gamepad Y), so it never fights an upgrade pad's E.
local function buildBoard(plr: Player, house: Folder, origin: Vector3)
	local half = Config.Hub.Size / 2
	local centre = origin
		+ Vector3.new(half - 0.5 - 0.2 - BOARD_SIZE.Z / 2, 0.5 + 2 + BOARD_SIZE.Y / 2, half - 0.5 - 0.1 - BOARD_SIZE.X / 2)
	local frame = CFrame.lookAt(centre, centre + Vector3.new(-1, 0, 0)) -- the Front face (-Z local) looks into the room
	local board = newPart({
		Name = "NightsBoard", Size = BOARD_SIZE, CFrame = frame,
		Color = Color3.fromRGB(22, 18, 28), Material = Enum.Material.SmoothPlastic, Parent = house,
	})
	-- a gold frame behind it, against the wall: anything interactive reads as interactive (new-game-checklist §2)
	newPart({
		Name = "NightsBoardTrim", Size = Vector3.new(BOARD_SIZE.X + 0.8, BOARD_SIZE.Y + 0.8, 0.2),
		CFrame = frame * CFrame.new(0, 0, BOARD_SIZE.Z / 2 + 0.1), CanCollide = false, CastShadow = false,
		Color = BOARD_GOLD, Material = Enum.Material.Neon, Parent = house,
	})
	local at = Instance.new("Attachment")
	at.Name = "PromptAt"
	at.Position = Vector3.new(0, -3, -0.8)
	at.Parent = board
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = BC.Text.Prompt
	prompt.ObjectText = "🏆 " .. BC.Text.Title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = BC.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = at

	local gui = Instance.new("SurfaceGui")
	gui.Name = "NightsBoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.ClipsDescendants = true
	gui.Parent = board
	local function label(name: string, y: number, h: number, size: number, color: Color3, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0, 20, 0, y)
		l.Size = UDim2.new(1, -40, 0, h)
		l.Font = font
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = ""
		l.Parent = gui
		return l
	end
	local title = label("Title", 8, 36, 30, BOARD_GOLD, Enum.Font.GothamBlack)
	title.Text = "🏆 " .. BC.Text.Title
	local mode = label("Mode", 44, 26, 22, BOARD_GOLD, Enum.Font.GothamBold)
	local rows = {}
	for i = 1, math.max(BC.PublicRows, BC.FriendsRows) do
		rows[i] = label("Row" .. i, 76 + (i - 1) * 21, 21, 18, BOARD_TEXT, Enum.Font.GothamMedium)
		rows[i].Visible = false
	end
	local note = label("Note", 76, 84, 18, BOARD_DIM, Enum.Font.GothamMedium)
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.Visible = false
	local hint = label("Hint", 290, 24, 15, BOARD_DIM, Enum.Font.Gotham)
	hint.Text = BC.Text.Hint
	boardUi[plr] = { mode = mode, rows = rows, note = note }
	boardMode[plr] = "public"
	renderBoard(plr, "public", publicView)

	prompt.Triggered:Connect(function(who)
		if who ~= plr then
			return
		end
		boardMode[plr] = if boardMode[plr] == "friends" then "public" else "friends"
		if boardMode[plr] == "friends" then
			showFriends(plr)
		else
			renderBoard(plr, "public", publicView)
		end
	end)
end

-- The public top 10: read at most once per PublicCacheSeconds, and only while somebody is here to see it. Checked
-- every second, so the first player on a fresh server sees the list within a second instead of "Loading..." for up to
-- a minute (check_nightwatchmanor_board, pass 2). A failed read waits out the same minute and keeps the last list.
local publicReadAt = -math.huge
task.spawn(function()
	while true do
		if #Players:GetPlayers() > 0 and clock() - publicReadAt >= BC.PublicCacheSeconds then
			publicReadAt = clock()
			refreshPublic()
			for plr, mode in boardMode do
				if mode == "public" then renderBoard(plr, "public", publicView) end
			end
		end
		task.wait(1)
	end
end)

-- ------------------------------------------------------------------ the safehouse
local upgradePads: { [Player]: { [string]: BasePart } } = {}

local function refreshPad(plr: Player, id: string)
	local prof = profiles[plr]
	local pads = upgradePads[plr]
	if not prof or not pads then
		return
	end
	local pad = pads[id]
	if not pad or pad.Parent == nil then
		return
	end
	local entry = Upgrades.byId(Config, id)
	local level = Upgrades.level(prof.levels, id)
	local cost = Upgrades.cost(Config, id, level)

	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ObjectText = string.format("%s  Lv %d/%d", entry.name, level, entry.max)
		prompt.ActionText = if cost == nil then "MAXED" else string.format("BUY — %d relics", cost)
	end

	local props = pad:FindFirstChild("Props")
	if props then
		props:ClearAllChildren()
		UPGRADE_PROPS[id](props, pad, level)
	end
end

local function buildSafehouse(plr: Player, zone: Model, index: number)
	local prof = profiles[plr]
	if not prof then
		return
	end
	local origin = zoneOrigin(index)
	local H = Config.Hub
	local half = H.Size / 2

	local house = Instance.new("Folder")
	house.Name = "Safehouse"
	house.Parent = zone

	newPart({ Name = "Floor", Size = Vector3.new(H.Size, 1, H.Size), CFrame = CFrame.new(origin), Color = Color3.fromRGB(62, 50, 42), Material = Enum.Material.WoodPlanks, Parent = house })
	newPart({ Name = "Ceiling", Size = Vector3.new(H.Size, 1, H.Size), CFrame = CFrame.new(origin + Vector3.new(0, H.WallHeight, 0)), Color = DARKWOOD, Parent = house })
	newPart({ Name = "WallN", Size = Vector3.new(H.Size, H.WallHeight, 1), CFrame = CFrame.new(origin + Vector3.new(0, H.WallHeight / 2, half)), Color = STONE, Parent = house })
	newPart({ Name = "WallW", Size = Vector3.new(1, H.WallHeight, H.Size), CFrame = CFrame.new(origin + Vector3.new(-half, H.WallHeight / 2, 0)), Color = STONE, Parent = house })
	newPart({ Name = "WallE", Size = Vector3.new(1, H.WallHeight, H.Size), CFrame = CFrame.new(origin + Vector3.new(half, H.WallHeight / 2, 0)), Color = STONE, Parent = house })
	-- south wall, split around the manor door
	local segW = (H.Size - 14) / 2
	for i = -1, 1, 2 do
		newPart({ Name = "WallS" .. i, Size = Vector3.new(segW, H.WallHeight, 1), CFrame = CFrame.new(origin + Vector3.new(i * (7 + segW / 2), H.WallHeight / 2, -half)), Color = STONE, Parent = house })
	end

	-- The spawn pad you land on, and it is a REAL SpawnLocation rather than a decorative slab.
	-- Setting the root part's CFrame on CharacterAdded is not enough on its own: with no
	-- SpawnLocation in the place the engine picks its own spot, and every zone in this game sits
	-- at index * 3000 studs along +X, so the spot it picks is nowhere near the player's safehouse.
	-- A sibling game shipped exactly this defect and put every player on the ROOF of their own
	-- sealed cavern, 55 studs from anything they could interact with. `plr.RespawnLocation` is
	-- what makes the engine agree with us, and it also covers the respawn after a death, which no
	-- CharacterAdded teleport can be relied on to win.
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "SpawnPad"
	spawnPad.Size = Vector3.new(8, 0.2, 8)
	spawnPad.CFrame = CFrame.new(origin + Vector3.new(0, 0.6, half - 10))
	spawnPad.Color = Color3.fromRGB(70, 110, 150)
	spawnPad.Material = Enum.Material.Neon
	spawnPad.Transparency = 0.35
	spawnPad.Anchored = true
	spawnPad.CanCollide = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0 -- no forcefield: this is a horror game, not an arena
	spawnPad.Enabled = true -- explicit: Roblox will not respawn anyone at a disabled SpawnLocation
	spawnPad.Parent = house
	plr.RespawnLocation = spawnPad

	-- the highscore board, a few steps from the spawn pad (docs/complete-game-standard.md §3)
	buildBoard(plr, house, origin)

	-- the door into the manor
	local door = newPart({
		Name = "ManorDoor", Size = Vector3.new(12, 13, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, 6.5, -half)),
		Color = Color3.fromRGB(24, 20, 26), Material = Enum.Material.Slate, Parent = house,
	})
	candle(door, 2, 20, Color3.fromRGB(120, 90, 200))
	makePrompt(door, "ENTER THE MANOR", "Nightwatch Manor", Enum.KeyCode.E)

	-- upgrade pads, split between the two side walls
	local pads: { [string]: BasePart } = {}
	upgradePads[plr] = pads
	local catalog = Config.Upgrades.Catalog
	local perSide = math.ceil(#catalog / 2)
	for i, e in catalog do
		local side = if i <= perSide then -1 else 1
		local slot = if i <= perSide then i else i - perSide
		local count = if side == -1 then perSide else #catalog - perSide
		local spacing = (H.Size - 16) / math.max(count, 1)
		local z = -((H.Size - 16) / 2) + (slot - 0.5) * spacing
		local pad = newPart({
			Name = "Pad_" .. e.id, Size = Vector3.new(H.PadSize, 1, H.PadSize),
			CFrame = CFrame.new(origin + Vector3.new(side * (half - 7), 1, z)),
			Color = Color3.fromRGB(48, 62, 78), Material = Enum.Material.Neon, Transparency = 0.15,
			Parent = house,
		})
		pad:SetAttribute("UpgradeId", e.id)
		local props = Instance.new("Folder")
		props.Name = "Props"
		props.Parent = pad
		pads[e.id] = pad

		local prompt = makePrompt(pad, "BUY", e.name, Enum.KeyCode.E)
		prompt.Triggered:Connect(function(who)
			if who ~= plr then
				return
			end
			local p = profiles[plr]
			local run = runs[plr]
			if not p or not run or run.phase ~= "DAY" then
				return
			end
			-- The safehouse is standing before the DataStore round-trip lands, so that a joining
			-- player has a floor. Until it does, the levels and the stash on screen are the
			-- DEFAULT ones, and spending against them would either refuse a purchase the player
			-- can afford or grant one they cannot.
			if not p.loaded then
				notice(plr, "DENIED", "Still opening your safehouse — one moment.")
				return
			end
			local ok, newLevels, newStash, reason = Upgrades.buy(Config, p.levels, p.stash, e.id)
			if not ok then
				-- Never a silent no-op: the player is told exactly why nothing happened.
				local why = if reason == "maxed" then e.name .. " is already fully built."
					else string.format("You need %d relics for %s.", Upgrades.cost(Config, e.id, Upgrades.level(p.levels, e.id)) or 0, e.name)
				notice(plr, "DENIED", why)
				return
			end
			p.levels = newLevels
			p.stash = newStash
			refreshPad(plr, e.id)
			notice(plr, "BOUGHT", e.name .. " — level " .. Upgrades.level(p.levels, e.id))
			saveProfile(plr)
			pushState(plr)
		end)

		refreshPad(plr, e.id)
	end

	-- ambient light so the safehouse reads as the warm half of the game
	for i = -1, 1, 2 do
		local lamp = newPart({ Name = "HubLamp" .. i, Size = Vector3.new(3, 0.6, 3), CFrame = CFrame.new(origin + Vector3.new(i * 14, H.WallHeight - 1.5, 0)), Color = CANDLE, Material = Enum.Material.Neon, Parent = house })
		candle(lamp, 3, 40)
	end
end

-- ------------------------------------------------------------------ the manor
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- One wall on one edge of one room. `doorway` splits it into two jambs plus a lintel so the
-- player (and the Nightwatcher) can walk through.
local function buildWall(folder: Folder, centre: Vector3, dir: { number }, doorway: boolean, tag: string)
	local M = Config.Manor
	local half = M.RoomSize / 2
	local at = centre + Vector3.new(dir[1] * half, 0, dir[2] * half)
	local acrossX = dir[1] ~= 0 -- a wall on the X faces runs along Z
	local function seg(name: string, length: number, offset: number, y: number, height: number)
		local size = if acrossX then Vector3.new(1, height, length) else Vector3.new(length, height, 1)
		local pos = if acrossX then Vector3.new(0, y, offset) else Vector3.new(offset, y, 0)
		newPart({ Name = name, Size = size, CFrame = CFrame.new(at + pos), Color = STONE, Material = Enum.Material.Brick, Parent = folder })
	end

	if not doorway then
		seg("Wall" .. tag, M.RoomSize, 0, M.WallHeight / 2, M.WallHeight)
		return
	end
	local jamb = (M.RoomSize - M.DoorWidth) / 2
	seg("Wall" .. tag .. "A", jamb, -(M.DoorWidth + jamb) / 2, M.WallHeight / 2, M.WallHeight)
	seg("Wall" .. tag .. "B", jamb, (M.DoorWidth + jamb) / 2, M.WallHeight / 2, M.WallHeight)
	local lintelH = M.WallHeight - M.DoorHeight
	if lintelH > 0 then
		seg("Wall" .. tag .. "L", M.DoorWidth, 0, M.DoorHeight + lintelH / 2, lintelH)
	end
end

-- Where relic `slot` stands inside its room. MaxPerRoom is 2, so two opposite corners; a third
-- slot would land back on the first, which is why Manor.plan draws slots without replacement.
local function relicOffset(slot: number): Vector3
	local ring = { Vector3.new(-11, 0, -11), Vector3.new(11, 0, 11), Vector3.new(11, 0, -11), Vector3.new(-11, 0, 11) }
	return ring[((slot - 1) % #ring) + 1]
end

local resolveNight: (Player, string) -> ()

local function buildManor(plr: Player, zone: Model, plan: any, index: number)
	local M = Config.Manor
	local origin = manorOrigin(index)

	local manor = Instance.new("Folder")
	manor.Name = "Manor"
	manor.Parent = zone

	local byCell: { [string]: any } = {}
	for _, room in plan.rooms do
		byCell[room.gx .. "," .. room.gz] = room
	end

	for _, room in plan.rooms do
		local cx, cz = Manor.roomCenter(Config, room)
		local centre = origin + Vector3.new(cx, 0, cz)

		local folder = Instance.new("Folder")
		folder.Name = "Room" .. room.id .. "_" .. room.kind
		folder.Parent = manor

		newPart({ Name = "Floor", Size = Vector3.new(M.RoomSize, 1, M.RoomSize), CFrame = CFrame.new(centre), Color = Color3.fromRGB(44, 38, 34), Material = Enum.Material.WoodPlanks, Parent = folder })
		newPart({ Name = "Ceiling", Size = Vector3.new(M.RoomSize, 1, M.RoomSize), CFrame = CFrame.new(centre + Vector3.new(0, M.WallHeight, 0)), Color = Color3.fromRGB(26, 22, 22), Parent = folder })

		-- Walls are owned by the LOWER room id on a shared edge, so a wall between two rooms is
		-- built exactly once. An edge with no room behind it is an outer wall.
		for di, dir in DIRS do
			local other = byCell[(room.gx + dir[1]) .. "," .. (room.gz + dir[2])]
			if other == nil then
				buildWall(folder, centre, dir, false, tostring(di))
			elseif room.id < other.id then
				buildWall(folder, centre, dir, Manor.linked(plan, room.id, other.id), tostring(di))
			end
		end

		-- a dim fixture per room; the manor is meant to be dark, not unnavigable
		local fixture = newPart({ Name = "Fixture", Size = Vector3.new(2, 0.4, 2), CFrame = CFrame.new(centre + Vector3.new(0, M.WallHeight - 1, 0)), Color = Color3.fromRGB(120, 110, 96), Material = Enum.Material.Neon, Parent = folder })
		candle(fixture, 1.1, 22)

		ROOM_BUILDERS[room.kind](folder, centre, room, plan)
	end

	-- relics
	local run = runs[plr]
	for _, spot in plan.relics do
		local room = Manor.roomById(plan, spot.roomId)
		if room then
			local cx, cz = Manor.roomCenter(Config, room)
			local base = origin + Vector3.new(cx, 0, cz) + relicOffset(spot.slot)
			local tier = Night.tierById(Config, spot.tier)
			local pedestal = newPart({
				Name = "Pedestal_" .. spot.roomId .. "_" .. spot.slot, Size = Vector3.new(3, 4, 3),
				CFrame = CFrame.new(base + Vector3.new(0, 3, 0)), Color = STONE, Material = Enum.Material.Marble,
				Parent = manor,
			})
			pedestal:SetAttribute("Tier", spot.tier)
			local relic = RELIC_BUILDERS[spot.tier](pedestal, base + Vector3.new(0, 5, 0))
			relic.Name = "Relic"
			-- Anything the player is meant to chase glows. This is onboarding, not decoration:
			-- in a dark manor an unlit pedestal is furniture.
			Fx.attachGlow(relic, Color3.fromRGB(255, 210, 140), 2.4, 14)
			local prompt = makePrompt(pedestal, "TAKE", tier and tier.name or spot.tier, Enum.KeyCode.E)
			prompt.Triggered:Connect(function(who)
				if who ~= plr then
					return
				end
				local r = runs[plr]
				if not r or r.phase ~= "NIGHT" or r.ending then
					return
				end
				if pedestal:GetAttribute("Taken") then
					return -- a second trigger before the part is gone
				end
				pedestal:SetAttribute("Taken", true)
				table.insert(r.carried, spot.tier)
				r.relicsLeft = math.max(r.relicsLeft - 1, 0)
				prompt.Enabled = false
				relic:Destroy()
				notice(plr, "TOOK", (tier and tier.name or spot.tier) .. " taken")
				pushState(plr)
			end)
		end
	end

	-- the way out, standing in the vestibule
	local exitRoom = Manor.roomById(plan, plan.exitId)
	if exitRoom then
		-- WHICH WALL. The slab is exactly DoorWidth wide and stands six studs inside a face, so a
		-- face that has a doorway in it gets the slab planted squarely in the gap — which is the only
		-- way into the room the player has to reach. It used to be hard-coded to +Z and landed in a
		-- live doorway on 249 of nights 1-500. `Manor.exitFace` picks an OUTER face instead.
		-- WHERE on it: Crossing.exitDoorAt, the same point the crossing guard measures the walk to.
		local fx, fz = Manor.exitFace(Config, plan)
		fx, fz = fx or 0, fz or 1
		local dx, dz = Crossing.exitDoorAt(Config, plan, fx, fz)
		local size = if fx ~= 0
			then Vector3.new(1.2, 12, M.DoorWidth)
			else Vector3.new(M.DoorWidth, 12, 1.2)
		local door = newPart({
			Name = "ExitDoor", Size = size,
			CFrame = CFrame.new(origin + Vector3.new(dx, 6.5, dz)),
			Color = Color3.fromRGB(40, 90, 60), Material = Enum.Material.Neon, Transparency = 0.15,
			Parent = manor,
		})
		candle(door, 3, 30, Color3.fromRGB(120, 220, 140))
		local prompt = makePrompt(door, "ESCAPE", "Servants' Exit", Enum.KeyCode.E)
		prompt.MaxActivationDistance = Config.Guard.ExitPromptDistance
		prompt.Triggered:Connect(function(who)
			if who ~= plr then
				return
			end
			local r = runs[plr]
			if not r or r.phase ~= "NIGHT" or r.ending then
				return
			end
			-- THE CROSSING GUARD (Crossing.luau). Surviving the night is the highscore board's metric, and the client
			-- moves its own character, so a script could stand here a second into the night. The server measures both
			-- halves itself: the root within the prompt's reach (+ slack), and the night clock past the shortest walk
			-- here at WalkSpeed. A player walking the perfect line is never refused (Crossing.spec); a refusal says why.
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local dist = if hrp and hrp:IsA("BasePart") then (hrp.Position - door.Position).Magnitude else math.huge
			-- and in the exit room: the prompt needs no line of sight, so it reaches through a wall into the next room
			local inRoom = hrp ~= nil and hrp:IsA("BasePart")
				and Manor.roomAtWorld(plan, Config, hrp.Position.X - origin.X, hrp.Position.Z - origin.Z) == plan.exitId
			local ok, why, wait = Crossing.verdictFor(Config, r.crossSeconds, r.elapsed, dist, inRoom)
			if not ok then
				-- the HUD shows a DENIED notice's text only, so the reason is in the text
				if why == "far" then
					notice(plr, "DENIED", "Stand at the Servants' Exit to use it.")
				else
					notice(plr, "DENIED", string.format("The Servants' Exit is still barred: it opens in %.1f s", wait),
						"Nobody crosses the manor that fast.")
				end
				return
			end
			resolveNight(plr, Night.EXTRACTED)
		end)
	end

	-- the Nightwatcher itself
	local model = Instance.new("Model")
	model.Name = "Nightwatcher"
	local torso = newPart({ Name = "Torso", Size = Vector3.new(2.4, 4, 1.4), Color = Color3.fromRGB(10, 10, 14), Parent = model })
	local head = newPart({ Name = "Head", Size = Vector3.new(1.6, 1.6, 1.6), CFrame = torso.CFrame * CFrame.new(0, 2.8, 0), Color = Color3.fromRGB(10, 10, 14), Parent = model })
	candle(head, 3, 12, Color3.fromRGB(255, 70, 70))
	local lamp = newPart({ Name = "Lamp", Size = Vector3.new(1, 1.4, 1), CFrame = torso.CFrame * CFrame.new(1.6, 0.6, -0.8), Color = GHOST, Material = Enum.Material.Neon, Parent = model })
	candle(lamp, 2.5, 26, GHOST)
	model.PrimaryPart = torso
	model.Parent = manor
	if run then
		run.watcherModel = model
	end

	return manor
end

-- ------------------------------------------------------------------ movement helpers
-- The lantern the player carries. This is what `lampRadius` BUYS: without it the Safehouse
-- Lanterns upgrade would cost 40 relics a level, stack a visible prop on its pad, and change
-- nothing whatsoever inside the manor — which is indistinguishable, from the player's side,
-- from the purchase having failed.
local LAMP_BASE_RANGE = 18
local LAMP_NAME = "NightLantern"

local function lightPlayer(plr: Player)
	local run = runs[plr]
	local char = plr.Character
	if not run or not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return
	end
	local old = hrp:FindFirstChild(LAMP_NAME)
	if old then
		old:Destroy()
	end
	local pl = Instance.new("PointLight")
	pl.Name = LAMP_NAME
	pl.Color = Color3.fromRGB(255, 214, 150)
	pl.Brightness = 2
	pl.Range = LAMP_BASE_RANGE + (run.effects.lampRadius or 0)
	pl.Parent = hrp
end

local function douseLantern(plr: Player)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local old = hrp and hrp:FindFirstChild(LAMP_NAME)
	if old then
		old:Destroy()
	end
end

-- The player's walk speed is a NUMBER THE GAME OWNS. Watcher.speed bounds the Nightwatcher
-- against Config.Player.WalkSpeed, so leaving it to whatever the engine defaults to would rest
-- the entire balance of the chase on a value written down nowhere — which is precisely how a
-- hunter that outran the player from 0.8 seconds into night one shipped green.
local function applyWalkSpeed(char: Model?)
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		(hum :: any).WalkSpeed = Config.Player.WalkSpeed
	end
end

local function teleport(plr: Player, pos: Vector3)
	local char = plr.Character
	if not char then
		return
	end
	local frame = CFrame.new(pos)
	local function place()
		local okPivot = pcall(function()
			char:PivotTo(frame)
		end)
		if not okPivot then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				hrp.CFrame = frame
			end
		end
	end
	place()

	-- ...and again once the character is GENUINELY IN THE WORLD, because the write above can be
	-- thrown away and the player never sees an error.
	--
	-- Measured in Roblox Studio on 2026-09-10 (fork-tower/STUDIO.md, robloxemu/SPAWN-ORDER.md),
	-- sampling HumanoidRootPart every Heartbeat from inside a server CharacterAdded handler:
	--
	--     [0.0000] f01 parent=nil        hrp=0.00,0.00,0.00
	--     [0.0051] f02 parent=Workspace  hrp=0.00,3.51,-160.00   <- the enabled SpawnLocation
	--
	-- CharacterAdded fires while the model is still UNPARENTED with its root at the world origin;
	-- one frame LATER the engine parents it AND drops it on the SpawnLocation, silently
	-- discarding anything the handler wrote in between.
	--
	-- `task.defer` used to stand here and it is NOT enough: it resumes at the end of the current
	-- resumption cycle, which is still the frame BEFORE the engine's step, so its
	-- `char.Parent ~= nil` guard is false and the re-write simply never happens. Measured with a
	-- hand-rolled replay of that trace (robloxemu/check_nightwatch.luau): a player who reset in
	-- the middle of a live night ended up at (6000.0, 103.2, 20.0), standing on their safehouse
	-- SpawnPad 2.6 studs from its centre, when the manor they were robbing spans z -460..-300 —
	-- outside it, 408 studs from the foyer, with the clock running and no way back in. The 0.2 s
	-- fallback in onPlayerAdded does not rescue that: it only re-places a character more than 600
	-- studs from its zone origin, and the SpawnPad is 20.
	--
	-- `char.Parent` going non-nil is the signal to write, because the trace shows parent and
	-- placement landing in the SAME frame: once a poll can see a parent, the engine has finished
	-- and this write is the last one. Bounded at 300 frames so a character that never arrives
	-- cannot park a thread for the life of the server. An already-parented character (every
	-- teleport that is not a spawn — beginNight, goToSafehouse, escaping) never enters the loop
	-- and just gets the same CFrame written twice, which costs nothing.
	task.spawn(function()
		local frames = 0
		while char.Parent == nil and frames < 300 do
			task.wait(1 / 60)
			frames += 1
		end
		if char.Parent ~= nil and plr.Character == char then
			place()
		end
	end)
end

local function playerPos(plr: Player): Vector3?
	local char = plr.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	return nil
end

local function clearManor(zone: Model)
	local old = zone:FindFirstChild("Manor")
	if old then
		old:Destroy()
	end
end

-- ------------------------------------------------------------------ the night loop
local beginNight: (Player) -> ()

local function stepNight(plr: Player, dt: number)
	local run = runs[plr]
	local prof = profiles[plr]
	if not run or not prof or run.phase ~= "NIGHT" or run.ending then
		return
	end
	local plan = run.plan
	local points = run.points
	if not plan or not points or not run.watcher then
		return
	end

	-- The manor wakes up whether or not the player's character has loaded.
	run.elapsed += dt
	local dread = Watcher.dread(run.elapsed, run.dreadTotal)

	local pos = playerPos(plr)
	local index = tonumber(zones[plr] and zones[plr]:GetAttribute("Index")) or 0
	local origin = manorOrigin(index)

	local spotted = false
	local near = false
	local target: { x: number, z: number }? = nil

	if pos then
		-- The Alarm Bell: hearing, not seeing. Works through walls and behind its back, and is
		-- flatly off (warnRange 0) until a bell is bought.
		near = Watcher.hears(run.effects.warnRange or 0, run.watcher.x, run.watcher.z, pos.X, pos.Z)

		local px, pz = pos.X - origin.X, pos.Z - origin.Z
		local playerRoom = Manor.roomAtWorld(plan, Config, px, pz)
		local watcherRoom = Manor.roomAtWorld(plan, Config, run.watcher.x - origin.X, run.watcher.z - origin.Z)

		-- Walls block sight with no raycast: you have to be in its room or one door away.
		local roomOk = playerRoom ~= nil
			and watcherRoom ~= nil
			and (playerRoom == watcherRoom or Manor.linked(plan, watcherRoom, playerRoom))
		spotted = Watcher.spots(Config, run.watcher.x, run.watcher.z, run.watcher.fx, run.watcher.fz, pos.X, pos.Z, roomOk)

		if spotted and playerRoom and watcherRoom then
			-- Chase by walking the ROOM GRAPH, so it comes through doorways. Same room: straight at
			-- you. Otherwise `Manor.chaseStep`, which steers at the DOORWAY and only then at the room
			-- beyond. This used to aim straight at the next room's CENTRE, and that line crosses the
			-- wall from anywhere except the centre it starts at — which, one hunt tick in, is
			-- everywhere. The player cannot walk that line (the wall is a real Brick part with a
			-- DoorWidth hole in the middle of it), so the two of you were racing on different maps.
			if playerRoom == watcherRoom then
				target = { x = pos.X, z = pos.Z }
			else
				local nx, nz = Manor.chaseStep(Config, plan, watcherRoom,
					run.watcher.x - origin.X, run.watcher.z - origin.Z, playerRoom)
				if nx then
					target = { x = origin.X + nx, z = origin.Z + (nz :: number) }
				else
					target = { x = pos.X, z = pos.Z }
				end
			end
		end
	end

	if spotted ~= run.spotted or near ~= run.near then
		local wasSpotted = run.spotted
		run.spotted = spotted
		run.near = near
		if spotted and not wasSpotted then
			-- This advice has to be TRUE. It was not: the Nightwatcher used to be faster than the
			-- player from 0.8s into night one, so "keep moving" described something that could
			-- not be done. It is now capped below the player's walk speed (Watcher.speed), so
			-- running gains ground — and the text says which way the fight goes, because a player
			-- who does not know they are faster will freeze instead of run.
			notice(plr, "SPOTTED", "IT SEES YOU", "You are faster than it. Run, and put a room between you.")
		elseif near and not spotted then
			notice(plr, "NEAR", "THE BELL RINGS", "Something is close by.")
		end
		pushState(plr)
	end

	Watcher.step(run.watcher, dt, {
		cfg = Config,
		points = points,
		dread = dread,
		watcherSlow = run.effects.watcherSlow,
		spotted = spotted,
		target = target,
	})

	if run.watcherModel and run.watcherModel.Parent then
		-- CFrame.lookAt with from == to is a degenerate matrix (NaN in Roblox). The facing is
		-- always unit-length once the watcher has moved, but the very first tick of a
		-- one-waypoint patrol can hand back a zero, so fall back to a fixed heading.
		local fx, fz = run.watcher.fx, run.watcher.fz
		if math.abs(fx) + math.abs(fz) < 1e-6 then
			fx, fz = 0, -1
		end
		local eye = Vector3.new(run.watcher.x, origin.Y + 3, run.watcher.z)
		run.watcherModel:PivotTo(CFrame.lookAt(eye, eye + Vector3.new(fx, 0, fz)))
	end

	if pos and Watcher.caught(Config, run.watcher.x, run.watcher.z, pos.X, pos.Z) then
		resolveNight(plr, Night.CAUGHT)
		return
	end
	if run.elapsed >= run.dreadTotal then
		resolveNight(plr, Night.EVICTED)
	end
end

-- One task loop per live night. It dies the moment the run token moves on, so a night that
-- ended can never keep stepping a watcher into the next one.
local function startNightLoop(plr: Player)
	local run = runs[plr]
	if not run then
		return
	end
	local token = run.token
	task.spawn(function()
		local sincePush = 0
		while true do
			local dt = task.wait(Config.TickSeconds) or Config.TickSeconds
			local r = runs[plr]
			if not r or r.token ~= token or r.phase ~= "NIGHT" then
				break
			end
			stepNight(plr, dt)
			sincePush += dt
			if sincePush >= Config.PushEverySeconds then
				sincePush = 0
				pushState(plr)
			end
		end
	end)
end

local function goToSafehouse(plr: Player)
	local run = runs[plr]
	local zone = zones[plr]
	if not run or not zone then
		return
	end
	local index = tonumber(zone:GetAttribute("Index")) or 0
	run.phase = "DAY"
	run.token += 1
	run.spotted = false
	run.near = false
	run.ending = false
	run.plan = nil
	run.points = nil
	run.watcher = nil
	run.watcherModel = nil
	run.elapsed = 0
	run.relicsLeft = 0
	run.relicsTotal = 0
	clearManor(zone)
	douseLantern(plr)
	teleport(plr, zoneOrigin(index) + Vector3.new(0, 4, Config.Hub.Size / 2 - 10))
	pushState(plr)
end

resolveNight = function(plr: Player, outcome: string)
	local run = runs[plr]
	local prof = profiles[plr]
	if not run or not prof or run.phase ~= "NIGHT" or run.ending then
		return
	end
	run.ending = true
	run.token += 1 -- kills the stepping loop immediately

	local state = { night = prof.night, stash = prof.stash, best = prof.best, carried = run.carried }
	local newState, res = Night.resolve(state, outcome, Config, run.effects)
	prof.night = newState.night
	prof.stash = newState.stash
	prof.best = newState.best
	run.carried = {}

	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local n = ls:FindFirstChild("Night")
		if n then (n :: IntValue).Value = prof.night end
		local r = ls:FindFirstChild("Relics")
		if r then (r :: IntValue).Value = prof.stash end
		local b = ls:FindFirstChild("Best")
		if b then (b :: IntValue).Value = prof.best end
	end

	if res.newBest then
		prof.bestAt = os.time() -- the board's tie-break: when this night was FIRST survived
	end

	-- a failure in these halls counts toward the manor shifting (beginNight)
	local held = manorSalt[plr]
	if outcome ~= Night.EXTRACTED and held and held.night == res.night then
		held.fails += 1
	end

	if outcome == Night.EXTRACTED then
		notice(plr, "EXTRACTED", string.format("YOU GOT OUT — night %d survived", res.night),
			string.format("Banked %d relics. Night %d is waiting.", res.gained, newState.night))
	elseif outcome == Night.CAUGHT then
		notice(plr, "CAUGHT", "IT CAUGHT YOU",
			if res.gained > 0 then string.format("The lockbox saved %d of %d relics.", res.gained, res.gained + res.lost)
			else string.format("You lost %d relics of loot.", res.lost))
	else
		notice(plr, "EVICTED", "THE MANOR IS AWAKE",
			string.format("Thrown out with %d relics of %d.", res.gained, res.gained + res.lost))
	end

	if res.newBest then
		writeBoard(plr) -- before the save, so the profile records what the board now holds
	end
	saveProfile(plr)
	pushState(plr)

	task.delay(Config.BeatSeconds, function()
		if runs[plr] and profiles[plr] then
			goToSafehouse(plr)
		end
	end)
end

beginNight = function(plr: Player)
	local prof = profiles[plr]
	local run = runs[plr]
	local zone = zones[plr]
	if not prof or not run or not zone or run.phase ~= "DAY" then
		return
	end
	-- Never start a night on the default profile. Somebody really on night 14 with 900 relics
	-- would walk into night 1's manor, and the load landing mid-night would rewrite the night
	-- number under them.
	if not prof.loaded then
		notice(plr, "DENIED", "Still opening your safehouse — one moment.")
		return
	end
	local index = tonumber(zone:GetAttribute("Index")) or 0
	local origin = manorOrigin(index)

	run.effects = Upgrades.effects(Config, prof.levels)

	-- Planned from server-only halves (the secrets block above, Salt.luau): one pair per player per night per
	-- session, so a retry is the manor you were caught in and nobody can compute any manor ahead of time. Its SIZE is
	-- still the night's (Manor.roomCount, relicCount, patrolCount and the dread clock read the night and nothing
	-- else), so night 14 is equally hard for everybody and the best night stays comparable. The player's hub level is
	-- deliberately NOT passed — see Manor.roomCount.
	local plan
	local shifted = false
	local key = "u_" .. plr.UserId
	if secrets:GetAttribute("PublicLayouts") == true then
		plan = Manor.plan(Rng.new(Manor.seedFor(Config, prof.night)), Config, prof.night)
		secrets:SetAttribute(key, string.format("%d:public", prof.night))
	else
		local held = manorSalt[plr]
		if held ~= nil and held.night == prof.night and held.fails >= Config.Manor.ShiftAfterFails then
			shifted = true
			held = nil
		end
		if held == nil or held.night ~= prof.night then
			held = { night = prof.night, a = drawHalf(), b = drawHalf(), fails = 0 }
			manorSalt[plr] = held
		end
		plan = Manor.plan(Salt.new(held.a, held.b), Config, prof.night)
		secrets:SetAttribute(key, string.format("%d:%d:%d", prof.night, held.a, held.b))
	end

	clearManor(zone)
	run.phase = "NIGHT"
	run.token += 1
	run.ending = false
	run.spotted = false
	run.near = false
	run.carried = {}
	run.plan = plan
	run.elapsed = 0
	run.dreadTotal = Night.dreadSeconds(Config, prof.night, run.effects)
	run.relicsTotal = #plan.relics
	run.relicsLeft = #plan.relics
	-- the Servants' Exit stays barred until the clock passes the shortest walk to it (Crossing.luau)
	run.crossSeconds = Crossing.minSeconds(Config, plan, Manor)

	buildManor(plr, zone, plan, index)

	-- patrol route in world space
	local pts = {}
	for _, roomId in plan.patrol do
		local room = Manor.roomById(plan, roomId)
		if room then
			local x, z = Manor.roomCenter(Config, room)
			table.insert(pts, { x = origin.X + x, z = origin.Z + z })
		end
	end
	if #pts == 0 then
		pts = { { x = origin.X, z = origin.Z } }
	end
	run.points = Watcher.loopPoints(pts)
	run.watcher = Watcher.newState(run.points)

	-- where the crossing guard measures the night from (Crossing.start: the entrance's centre, 12 studs in)
	local sx, sz = Crossing.start(Config, plan)
	teleport(plr, origin + Vector3.new(sx, 4, sz))
	lightPlayer(plr)

	notice(plr, "NIGHT", string.format("NIGHT %d", prof.night),
		(if shifted then "The manor has shifted: these are new halls. " else "")
			.. string.format("%d relics inside. Reach the Servants' Exit before the manor wakes.", run.relicsTotal))
	pushState(plr)
	startNightLoop(plr)
end

-- ------------------------------------------------------------------ join / leave
local function ensureLeaderstats(plr: Player, prof: Profile)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local night = Instance.new("IntValue")
	night.Name = "Night"
	night.Value = prof.night
	night.Parent = ls
	local relics = Instance.new("IntValue")
	relics.Name = "Relics"
	relics.Value = prof.stash
	relics.Parent = ls
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Value = prof.best
	best.Parent = ls
	ls.Parent = plr
end

-- THE WORLD IS BUILT BEFORE THE NETWORK CALL, NOT AFTER IT.
--
-- claimProfile YIELDS on DataStore UpdateAsync. This function used to do that first and build
-- the zone afterwards, which meant a joining player had no floor anywhere near them for the
-- whole round-trip: no SpawnLocation in the place, nothing at the origin, and their safehouse
-- 3000 studs away and not yet created. A cold server or a throttled request outlasts the ~2.3
-- seconds it takes to fall past FallenPartsDestroyHeight, and the character is destroyed.
--
-- So: zone, safehouse, spawn point and character placement all happen synchronously here, off
-- the DEFAULT profile, and the real profile is applied when it lands. The one thing that must
-- not happen in between is SPENDING — a purchase against a stash of 0, or a night entered as
-- night 1 by somebody who is really on night 14 — so `prof.loaded` gates both.
local function onPlayerAdded(plr: Player)
	local prof = defaultProfile()
	profiles[plr] = prof

	ensureLeaderstats(plr, prof)

	local index = acquireZoneIndex()
	local zone = Instance.new("Model")
	zone.Name = "Zone_" .. plr.UserId
	zone:SetAttribute("Index", index)
	zone.Parent = workspace
	zones[plr] = zone

	runs[plr] = {
		phase = "DAY",
		token = 0,
		carried = {},
		plan = nil,
		points = nil,
		watcher = nil,
		watcherModel = nil,
		elapsed = 0,
		dreadTotal = 0,
		effects = Upgrades.effects(Config, prof.levels),
		relicsTotal = 0,
		relicsLeft = 0,
		spotted = false,
		near = false,
		ending = false,
		crossSeconds = 0,
	}

	buildSafehouse(plr, zone, index)

	-- The manor door is created by buildSafehouse; wire it after the run exists.
	local house = zone:FindFirstChild("Safehouse")
	local door = house and house:FindFirstChild("ManorDoor")
	local prompt = door and door:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(who)
			if who == plr then
				beginNight(plr)
			end
		end)
	end

	-- Where this player's character belongs RIGHT NOW: the foyer if a night is running (the manor
	-- is still standing and the clock is still going), their safehouse otherwise.
	local function placeCharacter()
		local run = runs[plr]
		local z = zones[plr]
		if not run or not z then
			return
		end
		local idx = tonumber(z:GetAttribute("Index")) or 0
		if run.phase == "NIGHT" and run.plan then
			local sx, sz = Crossing.start(Config, run.plan)
			teleport(plr, manorOrigin(idx) + Vector3.new(sx, 4, sz))
			lightPlayer(plr) -- the light lived on the old character; respawning replaced it
			return
		end
		teleport(plr, zoneOrigin(idx) + Vector3.new(0, 4, Config.Hub.Size / 2 - 10))
	end

	plr.CharacterAdded:Connect(function(char)
		-- Immediately, on the frame the character appears. This used to wait 0.2 seconds, which
		-- is 0.2 seconds of falling at 196 studs/s^2 before anything catches you; `teleport`
		-- re-asserts the CFrame next frame so the engine's own placement cannot win the race.
		applyWalkSpeed(char)
		placeCharacter()

		-- The body runs in its own task: a Roblox event handler already gets one, but firing a
		-- signal is synchronous in the headless emulator, so a bare `task.wait` in here would
		-- yield whichever thread happened to spawn the character.
		task.spawn(function()
			task.wait(0.2)
			if plr.Character ~= char then
				return
			end
			applyWalkSpeed(char) -- again, in case anything on the character reset it
			-- Only re-place if the first attempt PLAINLY did not take. A character still hundreds
			-- of studs from its own zone never walked there; one that has moved a little has a
			-- player at the controls, and yanking them back would be worse than the bug.
			local pos = playerPos(plr)
			local z = zones[plr]
			local idx = z and tonumber(z:GetAttribute("Index")) or 0
			if pos == nil or (pos - zoneOrigin(idx)).Magnitude > 600 then
				placeCharacter()
			end
		end)
	end)

	-- The character can already exist by the time this runs (a rejoin, or a slow PlayerAdded),
	-- in which case CharacterAdded has ALREADY fired and the handler above will never see it.
	-- Without this the player stands on the origin plate, 3000 studs from their own safehouse.
	if plr.Character then
		applyWalkSpeed(plr.Character)
		placeCharacter()
	end

	-- ---------------------------------------------------------------- and NOW the network call
	-- Everything above is synchronous. Everything below can yield for as long as Roblox likes.
	local token = newSessionToken()
	local claim = claimProfile(plr, token)

	-- Leaving during that yield is one of the commonest things a real player does, and
	-- PlayerRemoving has already run: it tore the zone down and freed the index. Writing into
	-- these tables now would resurrect a departed player's profile and leak their zone entry for
	-- the life of the server.
	if profiles[plr] ~= prof or plr.Parent == nil then
		return
	end

	local loaded = Night.startState(Config, claim.data)
	prof.night = loaded.night
	prof.stash = loaded.stash
	prof.best = loaded.best
	prof.levels = Upgrades.sanitize(Config, claim.data and claim.data.levels)
	prof.lockToken = token
	prof.canSave = claim.got
	-- A save from before the board existed has a best night and no time it was reached: it is stamped with the session
	-- it came back in, so it still gets on the board (behind anybody who got there earlier). boardBest says what this
	-- profile last wrote to the board, so a rejoin does not write it again.
	prof.bestAt = math.floor(tonumber(claim.data and claim.data.bestAt) or 0)
	if prof.best > 0 and prof.bestAt <= 0 then
		prof.bestAt = os.time()
	end
	prof.boardBest = math.clamp(math.floor(tonumber(claim.data and claim.data.boardBest) or 0), 0, prof.best)
	prof.loaded = true

	local run = runs[plr]
	if run then
		run.effects = Upgrades.effects(Config, prof.levels)
	end
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local n = ls:FindFirstChild("Night")
		if n then (n :: IntValue).Value = prof.night end
		local r = ls:FindFirstChild("Relics")
		if r then (r :: IntValue).Value = prof.stash end
		local b = ls:FindFirstChild("Best")
		if b then (b :: IntValue).Value = prof.best end
	end
	for _, e in Config.Upgrades.Catalog do
		refreshPad(plr, e.id) -- the pads were built off the default profile
	end

	if not prof.canSave then
		notice(plr, "READONLY", "Another session is live",
			"You can play, but progress will not be saved until it closes.")
	end

	pushState(plr)

	-- autosave + lock renewal
	task.spawn(function()
		while profiles[plr] do
			task.wait(Config.Save.AutosaveSeconds)
			if not profiles[plr] then
				break
			end
			writeBoard(plr)
			saveProfile(plr)
		end
	end)
end

local function onPlayerRemoving(plr: Player)
	local prof = profiles[plr]
	if prof then
		prof.closing = true
		writeBoard(plr, true)
		saveProfile(plr, true)
	end
	local run = runs[plr]
	if run then
		run.token += 1 -- stop any night loop before the zone goes
	end
	local zone = zones[plr]
	if zone then
		local index = tonumber(zone:GetAttribute("Index")) or 0
		zone:Destroy()
		releaseZoneIndex(index)
	end
	zones[plr] = nil
	runs[plr] = nil
	profiles[plr] = nil
	upgradePads[plr] = nil
	boardUi[plr] = nil
	boardMode[plr] = nil
	fetching[plr] = nil
	manorSalt[plr] = nil
	secrets:SetAttribute("u_" .. plr.UserId, nil)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
end

game:BindToClose(function()
	for plr, prof in profiles do
		prof.closing = true
		saveProfile(plr, true)
	end
end)
