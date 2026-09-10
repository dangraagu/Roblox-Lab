-- Main.server.luau — authoritative server for "Nightwatch Manor: Haunted Escape Tycoon".
--
-- Per player: one private zone at a far offset, holding a persistent SAFEHOUSE and, 400 studs
-- away, the MANOR for whatever night they are on. Two phases:
--
--   DAY   — you stand in the safehouse. Every upgrade is an in-world pad with a ProximityPrompt;
--           walking up and pressing E buys a level. There is no client -> server remote for
--           buying at all, so there is nothing for a client to lie to.
--   NIGHT — the server builds the manor from Manor.plan (seeded by WorldSeed + night only, so
--           night 7 is the same manor for everyone), fills it with relics, starts the
--           Nightwatcher on its patrol, and teleports you into the foyer. Take relics, reach
--           the servants' exit before dread fills. Getting caught or running out of night costs
--           you the haul but never the night you are on.
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
	publishedBest: number,
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
}

local profiles: { [Player]: Profile } = {}
local runs: { [Player]: Run } = {}
local zones: { [Player]: Model } = {}

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
		publishedBest = 0,
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

local function saveProfile(plr: Player, releasing: boolean?)
	local prof = profiles[plr]
	if not prof or not profileStore or not prof.canSave then
		return
	end
	local payload = {
		night = prof.night,
		stash = prof.stash,
		best = prof.best,
		levels = prof.levels,
	}
	pcall(function()
		(profileStore :: any):UpdateAsync(profileKey(plr), function(old)
			old = old or {}
			local lock = old.lock
			-- Somebody else took the lock while we were playing: do NOT clobber their data.
			if lock and lock.token ~= prof.lockToken and (os.time() - (tonumber(lock.at) or 0)) <= Config.Save.SessionLockSeconds then
				return nil
			end
			local newLock = nil
			if not releasing and not prof.closing then
				newLock = { token = prof.lockToken, at = os.time() }
			end
			return { data = payload, lock = newLock }
		end)
	end)
end

local function publishBest(plr: Player, force: boolean?)
	local prof = profiles[plr]
	if not prof or not bestBoard or prof.best <= prof.publishedBest then
		return
	end
	local now = os.clock()
	if not force and (now - prof.lastPublishAt) < PUBLISH_MIN_INTERVAL then
		return
	end
	local ok = pcall(function()
		(bestBoard :: any):SetAsync("u_" .. plr.UserId, prof.best)
	end)
	if ok then
		prof.publishedBest = prof.best
		prof.lastPublishAt = now
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
		local cx, cz = Manor.roomCenter(Config, exitRoom)
		local centre = origin + Vector3.new(cx, 0, cz)
		-- WHICH WALL. The slab is exactly DoorWidth wide and stands six studs inside a face, so a
		-- face that has a doorway in it gets the slab planted squarely in the gap — which is the only
		-- way into the room the player has to reach. It used to be hard-coded to +Z and landed in a
		-- live doorway on 249 of nights 1-500. `Manor.exitFace` picks an OUTER face instead.
		local fx, fz = Manor.exitFace(Config, plan)
		fx, fz = fx or 0, fz or 1
		local inset = M.RoomSize / 2 - 6
		local size = if fx ~= 0
			then Vector3.new(1.2, 12, M.DoorWidth)
			else Vector3.new(M.DoorWidth, 12, 1.2)
		local door = newPart({
			Name = "ExitDoor", Size = size,
			CFrame = CFrame.new(centre + Vector3.new(fx * inset, 6.5, fz * inset)),
			Color = Color3.fromRGB(40, 90, 60), Material = Enum.Material.Neon, Transparency = 0.15,
			Parent = manor,
		})
		candle(door, 3, 30, Color3.fromRGB(120, 220, 140))
		local prompt = makePrompt(door, "ESCAPE", "Servants' Exit", Enum.KeyCode.E)
		prompt.Triggered:Connect(function(who)
			if who ~= plr then
				return
			end
			local r = runs[plr]
			if not r or r.phase ~= "NIGHT" or r.ending then
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
	-- And again next frame. The engine finishes placing a SPAWNING character after this handler
	-- returns, and whichever write lands last wins; doing it twice makes that us. (Taken from
	-- grow-a-crystal, where one write was measurably not enough.)
	task.defer(function()
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
		publishBest(plr)
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

	-- Seeded by WorldSeed and the night, and nothing else: night 7 is night 7 for everybody. The
	-- player's hub level is deliberately NOT passed — see Manor.roomCount.
	local plan = Manor.plan(Rng.new(Manor.seedFor(Config, prof.night)), Config, prof.night)

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

	local entrance = Manor.roomById(plan, plan.entranceId)
	if entrance then
		local x, z = Manor.roomCenter(Config, entrance)
		teleport(plr, origin + Vector3.new(x, 4, z + 12))
	end
	lightPlayer(plr)

	notice(plr, "NIGHT", string.format("NIGHT %d", prof.night),
		string.format("%d relics inside. Reach the Servants' Exit before the manor wakes.", run.relicsTotal))
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
			local entrance = Manor.roomById(run.plan, run.plan.entranceId)
			if entrance then
				local mo = manorOrigin(idx)
				local x, z2 = Manor.roomCenter(Config, entrance)
				teleport(plr, mo + Vector3.new(x, 4, z2 + 12))
				lightPlayer(plr) -- the light lived on the old character; respawning replaced it
				return
			end
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
	prof.publishedBest = prof.best
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
			saveProfile(plr)
			publishBest(plr)
		end
	end)
end

local function onPlayerRemoving(plr: Player)
	local prof = profiles[plr]
	if prof then
		prof.closing = true
		publishBest(plr, true)
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
