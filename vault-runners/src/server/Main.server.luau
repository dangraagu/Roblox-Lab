-- VAULT RUNNERS 💎 — server, autoritativt.
--
-- Havner i ServerScriptService. Hele kjerneløkka: gå inn i et hvelv, plukk gems mens
-- kollapsen stiger, kom deg UT før forseglingen — ellers mister du alt du bar på.
--
-- Denne fila eier ÉN ting: motoren (Instance.new, posisjoner, remotes, DataStore). Alle regler
-- ligger i de rene modulene i ReplicatedStorage, som er enhetstestet fra luau-CLI uten Roblox:
--   VaultFloor  — geometrien (bygget på labyrint-spill sin MazeGen, kopiert uendret)
--   RunState    — banking-regelen (gems teller BARE hvis du kommer ut før forseglingen)
--   Progression — hvilket hvelv som er låst opp, og hvor slemt gulvet er
--   Pets        — stallen i hubben
--
-- Every require here is an INSTANCE require from ReplicatedStorage. A bare `require("./X")`
-- resolves in the luau CLI and is invalid in Roblox; that mistake once made a server in this
-- repo fail to load while every unit test stayed green.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")   -- GenerateGUID only (the session's owner token); no HTTP

local Config = require(ReplicatedStorage:WaitForChild("Config"))
-- No Studio playtest writes to the live stores unless the open place says so (second review 2026-10-09).
local STUDIO_BLOCKED = game:GetService("RunService"):IsStudio() and not Config.Save.AllowStudio
if STUDIO_BLOCKED then warn("[VaultRunners] Studio: the live stores are OFF (Config.Save.AllowStudio) - nothing is saved.") end
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local MazeGen = require(ReplicatedStorage:WaitForChild("MazeGen"))
local VaultFloor = require(ReplicatedStorage:WaitForChild("VaultFloor"))
local VaultPath = require(ReplicatedStorage:WaitForChild("VaultPath"))
local Progression = require(ReplicatedStorage:WaitForChild("Progression"))
local RunState = require(ReplicatedStorage:WaitForChild("RunState"))
local Pets = require(ReplicatedStorage:WaitForChild("Pets"))
local Trace = require(ReplicatedStorage:WaitForChild("Trace"))
local Ascent = require(ReplicatedStorage:WaitForChild("Ascent"))
local FlierGate = require(ReplicatedStorage:WaitForChild("FlierGate"))   -- which escapes count for the board
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local VaultEnv = require(ReplicatedStorage:WaitForChild("VaultEnv"))   -- deepestCleared: the board's metric
local Board = require(ReplicatedStorage:WaitForChild("Board"))

-- Visuals are part of the first build, not a later pass (docs/new-game-checklist.md §2).
-- Cozy: no sun, warm glow, dark fog — an underground vault lit by what is inside it.
Fx.applyLighting(Fx.Presets.Cozy)

local RUN = Config.Run
local HUB = Config.Hub

local function vec(t) return Vector3.new(t.x, t.y, t.z) end
local function col(t) return Color3.fromRGB(t.r, t.g, t.b) end

--============================================================================ remotes

local remotes = Instance.new("Folder")
remotes.Name = "VaultRemotes"
remotes.Parent = ReplicatedStorage

local function mk(className, name)
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local StateEvent = mk("RemoteEvent", "State")   -- server -> client: the whole profile
local RunEvent = mk("RemoteEvent", "Run")       -- server -> client: run start / tick / end
local EnterEvent = mk("RemoteEvent", "Enter")   -- client -> server: enter vault <tierIndex>
local BuyEvent = mk("RemoteEvent", "Buy")       -- client -> server: buy pet <id>
local EquipEvent = mk("RemoteEvent", "Equip")   -- client -> server: equip pet <id or nil>
local ToastEvent = mk("RemoteEvent", "Toast")   -- server -> client: one short line
local BoardEvent = mk("RemoteEvent", "Board")   -- server -> client: THIS player's view of the board

--============================================================================ data

-- DataStoreService:GetDataStore RAISES in an unpublished place and again when Studio API access
-- is off. Unwrapped it kills this whole script at load: no world, no remotes, no game, and the
-- place cannot even be opened in Studio. SAVING is what degrades here, never the game.
local function tryStore(fn, what)
	if not Config.Save.Enabled then return nil end
	local ok, ds = pcall(fn)
	if ok then return ds end
	warn("[Vault] " .. what .. " datastore unavailable (" .. tostring(ds)
		.. ") — the game runs, progress will NOT be saved this session.")
	return nil
end

local store = tryStore(function()
	if STUDIO_BLOCKED then error("Studio") end return DataStoreService:GetDataStore(Config.Save.Store)
end, "profiles")

-- The highscore board (Config.Board). Nil when the place has no DataStore access, and then the sign
-- says it is offline rather than showing an empty board as if nobody had ever escaped.
local boardStore = tryStore(function()
	if STUDIO_BLOCKED then error("Studio") end return DataStoreService:GetOrderedDataStore(Config.Save.Board)
end, "board")

-- ONE clock for the board's caches and read limiter. os.clock() is CPU time in Roblox (a quiet
-- server barely counts) and os.time() has whole seconds; GetServerTimeNow is the wall clock, and
-- tick() is the fallback for an engine (and the headless harness) that does not have it.
local clock: () -> number
do
	local ok, t = pcall(function()
		return (workspace :: any):GetServerTimeNow()
	end)
	clock = if ok and type(t) == "number" then function()
		return (workspace :: any):GetServerTimeNow()
	end else tick
end

local profiles = {}   -- [player] = profile
local pendingSave = {}   -- [player] = true, "this profile wants a write on the next flush tick"
local requestSave     -- forward declaration; defined under flush()
local toast           -- forward declaration; defined with the runs (flush tells a player it lost the save)

local function defaultProfile()
	local floors = {}
	for i = 1, #Config.Tiers do floors[i] = 1 end
	return {
		gems = 0,
		totalBanked = 0,     -- only ever goes UP; this is what unlocks vaults
		pets = {},
		equipped = nil,
		floors = floors,     -- [tierIndex] = next floor number in that vault
		-- THE BOARD'S OWN COUNT (owner decision 2026-10-11: fliers must not top the board). Shaped like
		-- `floors`: [tierIndex] = 1 + the escapes in that vault the server could TRACE through its
		-- corridors and stairwells (src/shared/FlierGate.luau). An honest runner's is equal to `floors`.
		-- A noclip escape advances `floors` (the economy is not the gate's business) and not this, so
		-- flying to floor 99 and walking one vault is one, not a hundred. Never more than `floors`.
		traced = table.clone(floors),
		escapes = 0,
		wipes = 0,
		-- When the deepest escape (the board's metric) was reached, in unix seconds. Saved, so a board
		-- write that failed is retried with the time the player GOT there, not the time of the retry:
		-- a tie on the board goes to whoever escaped that deep first.
		bestAt = 0,
		canSave = false,
	}
end

local function key(uid) return "u_" .. uid end

-- DataStore serialises through JSON, and sparse INTEGER keys come back as STRINGS. `floors` is
-- keyed by tier index, so without this a returning player's floor progress silently resets.
local function numKeys(src)
	local out = {}
	if type(src) == "table" then
		for k, v in pairs(src) do out[tonumber(k) or k] = v end
	end
	return out
end

-- Soft session lock (docs/complete-game-standard.md §1, fork-tower's `old.session`).
-- TWO fields, two jobs. `jobId` + `lockUntil` say whether a LOAD may take the record: a live lock held
-- by another server is respected (the player plays without saving). `session` is the OWNER TOKEN: a
-- fresh GUID written by the load that takes the record, and every later write of this session lands
-- only while the record still carries it (flush). game.JobId alone was the token before, and it is per
-- SERVER, not per session: every session on one server shares it, so it could not tell this session's
-- record from one a newer session had loaded since, and flush wrote whenever the record's jobId was
-- nil or its lock had run out, which is every player who stood still in the hub for two minutes (the
-- lock is renewed only by a write). A timestamp would be worse: rewritten on every save, it fires the
-- guard against yourself and silently stops saving.
local function loadProfile(plr)
	local p = defaultProfile()
	if not store then return p end
	local token = HttpService:GenerateGUID(false)
	local acquired = false
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			local lockedByOther = (tonumber(old.lockUntil) or 0) > now and old.jobId ~= game.JobId
			local d = old.data
			if d then
				p.gems = tonumber(d.gems) or 0
				p.totalBanked = tonumber(d.totalBanked) or 0
				p.pets = (type(d.pets) == "table") and d.pets or {}
				p.equipped = (type(d.equipped) == "string") and d.equipped or nil
				p.escapes = tonumber(d.escapes) or 0
				p.wipes = tonumber(d.wipes) or 0
				p.bestAt = tonumber(d.bestAt) or 0
				local f = numKeys(d.floors)
				for i = 1, #Config.Tiers do p.floors[i] = math.max(1, tonumber(f[i]) or 1) end
				-- A record saved before the flier gate existed has no `traced`: it keeps the depth its
				-- floors gave it (the game was not public, so there is nobody to take a row from). One
				-- that has it is held to 1..floors: the board never counts more than was cleared.
				local tr = if type(d.traced) == "table" then numKeys(d.traced) else nil
				for i = 1, #Config.Tiers do
					local v = if tr then tonumber(tr[i]) or 1 else p.floors[i]
					if v ~= v then v = 1 end
					p.traced[i] = math.clamp(math.floor(v), 1, p.floors[i])
				end
			end
			if lockedByOther then
				acquired = false
				return old
			end
			acquired = true
			old.jobId = game.JobId
			old.session = token
			old.lockUntil = now + Config.Save.LockSeconds
			old.data = old.data or {}
			return old
		end)
	end)
	if not ok then
		warn("[Vault] load failed for " .. plr.Name .. ": " .. tostring(err))
		return p
	end
	p.canSave = acquired
	p.session = if acquired then token else nil
	if not acquired then
		warn("[Vault] " .. plr.Name .. " is locked by another server; playing without saving.")
	end
	-- A profile saved before bestAt existed still has a deepest escape; it is stamped with the session
	-- it came back in (the true time is unknown, and a later stamp can only lose a tie, never steal one).
	if p.bestAt <= 0 and VaultEnv.deepestCleared(Config, p.traced) > 0 then
		p.bestAt = os.time()
	end
	return p
end

-- THE BOARD'S METRIC: the deepest vault escaped, counting only the escapes the server could trace
-- (`traced`, above). Every place that ranks a player reads this, never `floors`.
local function boardDepth(p)
	return VaultEnv.deepestCleared(Config, p.traced)
end

-- EXACTLY the fields flush() writes, as one comparable string. A profile whose fingerprint has
-- not moved since the last successful write has nothing to save, and writing it anyway is how a
-- rejected remote used to cost a DataStore call: doBuy and doEquip fell out of their "poor" /
-- "owned" / "unknown" / "unowned" branches straight into flush().
--
-- A fingerprint rather than a `dirty` flag set at each mutation site, deliberately: a flag has
-- to be remembered at every future place that touches the profile, and the one that is forgotten
-- is silent in exactly the same way the original defect was. This reads the fields instead, so a
-- new field is only invisible here if it is also not being saved.
local function saveFingerprint(p)
	local owned = {}
	-- Config order, not pairs() order: a Lua table's iteration order is not stable, and a
	-- fingerprint that reshuffles itself would report every profile as changed forever.
	for _, pet in ipairs(Config.Pets.List) do
		if p.pets and p.pets[pet.id] == true then owned[#owned + 1] = pet.id end
	end
	local floors, traced = {}, {}
	for i = 1, #Config.Tiers do
		floors[i] = tostring(p.floors[i] or 1)
		traced[i] = tostring(p.traced[i] or 1)
	end
	return table.concat({
		tostring(p.gems), tostring(p.totalBanked), tostring(p.escapes), tostring(p.wipes),
		tostring(p.equipped), table.concat(owned, ","), table.concat(floors, ","), tostring(p.bestAt),
		table.concat(traced, ","),
	}, "|")
end

--============================================================================ the board's writes

-- The depth this session has confirmed on the board, per player. Memory only: at worst a join
-- re-offers a depth the board already holds, and Board.keepHigher aborts that write.
local boardSent = {}   -- [player] = depth

-- Offer this player's deepest TRACED escape to the board. Only while this session can save (so the board
-- never holds a depth the profile would roll back), only when it is deeper than what this session
-- already confirmed, and through UpdateAsync + Board.keepHigher, so the stored value only ever moves
-- when the DEPTH improves and a tie keeps its first reach time.
local function writeBoard(plr, p)
	if not boardStore or not p or not p.canSave then return end
	local depth = boardDepth(p)
	if depth <= 0 or depth <= (boardSent[plr] or 0) then return end
	local value = Board.encode(depth, p.bestAt, Config.Board)
	local ok = pcall(function()
		boardStore:UpdateAsync(Board.key(plr.UserId), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	-- Also when keepHigher aborted: what the board holds is at least this deep.
	if ok then boardSent[plr] = depth end
end

local function flush(plr, releaseLock)
	local p = profiles[plr]
	if not store or not p or not p.canSave then return false end

	-- Nothing changed, nothing to write. The lock release is the one exception: it is a write
	-- ABOUT the write, not about the data, and skipping it strands the player's own save behind
	-- a 120-second lock they would experience as "the game would not let me back in".
	local fingerprint = saveFingerprint(p)
	if not releaseLock and fingerprint == p.savedFingerprint then
		pendingSave[plr] = nil
		return false
	end

	local wrote = false
	-- Set on EVERY invocation: UpdateAsync may run the transform more than once.
	local lost = false
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			-- OWNERSHIP. Only while the record still carries the token this session's load wrote. A
			-- newer session that took the record (its own load, after this lock ran out) has written its
			-- own token; this write is then cancelled whatever it is, a flush tick, a run's end or the
			-- release on leaving, and whether or not that newer session still holds a live lock.
			if old.session ~= p.session then
				lost = true
				return nil   -- somebody else owns the slot; ABORT the write
			end
			lost = false
			-- if-then-else, NOT `releaseLock and nil or game.JobId`. That and-or reads as a
			-- ternary and is not one: nil is falsy, so it ALWAYS evaluates to game.JobId and the
			-- lock is never released. luau-analyze flags it as MisleadingAndOr, which is how it
			-- was found — a player would only have seen it as "the game would not let me back in
			-- for two minutes after I left".
			old.jobId = if releaseLock then nil else game.JobId
			old.lockUntil = if releaseLock then 0 else (os.time() + Config.Save.LockSeconds)
			old.data = {
				gems = p.gems, totalBanked = p.totalBanked,
				pets = p.pets, equipped = p.equipped,
				floors = p.floors, escapes = p.escapes, wipes = p.wipes,
				bestAt = p.bestAt, traced = p.traced,
			}
			wrote = true
			return old
		end)
	end)
	if not ok then warn("[Vault] save failed for " .. plr.Name .. ": " .. tostring(err)) end
	if ok and lost then
		-- Nothing this session does is kept from here on, so it stops trying, and says so once.
		p.canSave = false
		pendingSave[plr] = nil
		warn("[Vault] " .. plr.Name .. ": another session has taken over this profile; progress is no longer saved this session.")
		if plr.Parent == Players and toast then
			toast(plr, "⚠️ You are playing in another server too: progress here is no longer saved.")
		end
		return false
	end
	-- Only a transform that actually RETURNED a value wrote anything. The abort branch above
	-- returns nil, which is a successful pcall and a save that did not happen; treating that as
	-- written would clear the fingerprint and lose the change for good.
	if ok and wrote then
		p.savedFingerprint = fingerprint
		pendingSave[plr] = nil
		-- The profile holding this depth is saved; now the board may hear about it.
		if not releaseLock then writeBoard(plr, p) end
	end
	return ok and wrote
end

-- Ask for a save; the flush loop performs it, at most once per Config.Save.FlushTickSeconds.
-- Remote handlers call THIS, never flush: a client firing EquipEvent in a loop between two pets
-- it owns changes the profile every time, so a "did anything change" test alone would still let
-- it drive the write rate.
function requestSave(plr)
	pendingSave[plr] = true
end

--============================================================================ world roots

local hubFolder = Instance.new("Folder")
hubFolder.Name = "Hub"
hubFolder.Parent = workspace

local vaultsFolder = Instance.new("Folder")
vaultsFolder.Name = "Vaults"
vaultsFolder.Parent = workspace

-- One Part out of one plain table. The pure generator owns every number; this owns every engine
-- call, and nothing in between decides anything.
local function instantiate(def, origin, parent)
	local part = Instance.new("Part")
	part.Name = def.name
	part.Anchored = true
	part.Size = vec(def.size)
	part.CFrame = CFrame.new(origin + vec(def.position))
	part.Material = Enum.Material[def.material]
	part.Color = col(def.color)
	part.Transparency = def.transparency
	part.Reflectance = def.reflectance
	part.CanCollide = def.collide
	part.CanQuery = def.query
	part.CanTouch = false
	part.CastShadow = def.castShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent   -- an unparented Instance raises nothing and is invisible to everyone
	return part
end

local function label(parent, text, size, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(size or 220, 60)
	gui.StudsOffset = Vector3.new(0, offsetY or 5, 0)
	gui.AlwaysOnTop = true
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.TextColor3 = col(Config.Hud.AccentColor)
	t.Font = Enum.Font.GothamBold
	t.TextStrokeTransparency = 0.4
	t.Parent = gui
	gui.Parent = parent
	return t
end

--============================================================================ the hub

local portalParts = {}   -- [tierIndex] = Part
local stallParts = {}    -- [petId] = Part
local hubSpawn           -- the one SpawnLocation; every player's RespawnLocation (onPlayerAdded)

local function buildHub()
	local pad = Instance.new("Part")
	pad.Name = "HubPad"
	pad.Anchored = true
	pad.Size = vec(HUB.PadSize)
	pad.CFrame = CFrame.new(0, -HUB.PadSize.y / 2, 0)
	pad.Material = Enum.Material.Marble
	pad.Color = Color3.fromRGB(46, 44, 58)
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Parent = hubFolder

	-- THIS IS WHAT PUTS EVERY PLAYER ON THE HUB, and it is load-bearing rather than decorative.
	-- Measured in Studio 2026-09-10 (robloxemu/SPAWN-ORDER.md): CharacterAdded fires while the
	-- character is still UNPARENTED at the world origin, and the engine parents AND positions it
	-- one frame later, on the enabled SpawnLocation, discarding anything a handler wrote in
	-- between. This game never writes a CFrame from CharacterAdded, so it does not lose that
	-- race — the engine's own placement is the answer, and this brick is the answer it uses.
	--
	-- With no ENABLED SpawnLocation, Roblox instead drops the character above the highest ground
	-- over the origin. slotOrigin(0) is (0, VaultOriginY, 0), so the first player's vault is a
	-- sealed shell built directly over this pad: measured, a single `spawnPad.Enabled = false`
	-- puts a joining player at (0.00, 254.51, 0.00), on the roof of somebody else's vault, out
	-- of reach of every portal. Do not remove it, do not disable it, and do not add a second
	-- SpawnLocation anywhere — the engine picks among ALL the eligible ones.
	-- check_vaultrunners.luau's "WHERE THE ENGINE PUTS YOU" block asserts all three.
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "HubSpawn"
	spawnPad.Anchored = true
	spawnPad.Size = Vector3.new(12, 1, 12)
	spawnPad.CFrame = CFrame.new(vec(HUB.SpawnPosition) - Vector3.new(0, 3.5, 0))
	spawnPad.Material = Enum.Material.Neon
	spawnPad.Color = col(Config.Hud.AccentColor)
	spawnPad.Transparency = 0.4
	spawnPad.CanCollide = true
	spawnPad.Parent = hubFolder
	hubSpawn = spawnPad

	-- Three portals, one per vault. Clicking one is the whole "start a run" interaction: the
	-- first-run action is one click, with no purchase and no prerequisite in front of it.
	local n = #Config.Tiers
	for i, tier in ipairs(Config.Tiers) do
		local p = Instance.new("Part")
		p.Name = "Portal_" .. i
		p.Anchored = true
		p.CanCollide = false
		p.Size = vec(HUB.PortalSize)
		p.CFrame = CFrame.new((i - (n + 1) / 2) * HUB.PortalSpacing, HUB.PortalSize.y / 2, HUB.PortalZ)
		p.Material = Enum.Material.Neon
		p.Color = col(tier.gemColor)
		p.Transparency = 0.35
		p:SetAttribute("TierIndex", i)
		p.Parent = hubFolder

		local cd = Instance.new("ClickDetector")
		cd.Name = "Click"
		cd.MaxActivationDistance = 40
		cd.Parent = p

		label(p, tier.emoji .. " " .. tier.name, 260, 9)
		Fx.attachGlow(p, col(tier.gemColor), 2, 26)
		portalParts[i] = p
	end

	-- The pet stall: eight pedestals, one per Vault-Keeper. Clicking a pedestal buys that pet.
	local stall = Instance.new("Part")
	stall.Name = "PetStall"
	stall.Anchored = true
	stall.Size = vec(HUB.StallSize)
	stall.CFrame = CFrame.new(vec(HUB.StallPosition))
	stall.Material = Enum.Material.WoodPlanks
	stall.Color = Color3.fromRGB(92, 66, 44)
	stall.Parent = hubFolder
	label(stall, "🐾 " .. Config.Pets.Rarity .. " Stall", 300, 6)

	for i, pet in ipairs(Config.Pets.List) do
		local ped = Instance.new("Part")
		ped.Name = "Pet_" .. pet.id
		ped.Anchored = true
		ped.CanCollide = false
		ped.Shape = Enum.PartType.Ball
		ped.Size = Vector3.new(3, 3, 3)
		ped.CFrame = CFrame.new(
			HUB.StallPosition.x - HUB.StallSize.x / 2 + 1.5 + ((i - 1) % 4) * 3.6,
			HUB.StallPosition.y + HUB.StallSize.y / 2 + 2.5,
			HUB.StallPosition.z + (i <= 4 and -2 or 2))
		ped.Material = Enum.Material.Neon
		ped.Color = Color3.fromRGB(210, 200, 255)
		ped.Transparency = 0.15
		ped:SetAttribute("PetId", pet.id)
		ped.Parent = hubFolder

		local cd = Instance.new("ClickDetector")
		cd.Name = "Click"
		cd.MaxActivationDistance = 30
		cd.Parent = ped

		label(ped, pet.emoji .. " " .. pet.name .. "\n💎 " .. pet.cost, 200, 3)
		Fx.sparkle(ped, Color3.fromRGB(220, 210, 255))
		stallParts[pet.id] = ped
	end

	Fx.attachGlow(pad, col(Config.Hud.AccentColor), 1.2, 60)
end

buildHub()

--============================================================================ companions

-- The pet you have equipped follows you around, in the hub and inside the vault. The brief's own
-- scope line: "each just a follow-script + small stat multiplier". This is the follow-script.
local companionFolder = Instance.new("Folder")
companionFolder.Name = "Companions"
companionFolder.Parent = workspace

local companions = {}   -- [player] = Part

local function refreshCompanion(plr)
	local p = profiles[plr]
	-- Pets.owns, never `p.equipped` on its own: an id in the slot is a preference, not a pet.
	local id = (p and Pets.owns(p, p.equipped)) and p.equipped or nil
	local existing = companions[plr]

	if id == nil then
		if existing then existing:Destroy() end
		companions[plr] = nil
		return
	end

	local pet = Pets.byId(Config, id)
	local part = existing
	if part == nil then
		part = Instance.new("Part")
		part.Name = "Companion_" .. plr.UserId
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(2.2, 2.2, 2.2)
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(214, 206, 255)
		part.Transparency = 0.1
		part.CFrame = CFrame.new(vec(HUB.SpawnPosition))
		part.Parent = companionFolder
		label(part, pet.emoji .. " " .. pet.name, 180, 2.4)
		Fx.sparkle(part, Color3.fromRGB(214, 206, 255))
		Fx.attachGlow(part, Color3.fromRGB(214, 206, 255), 1.4, 14)
		companions[plr] = part
	else
		local gui = part:FindFirstChild("Label")
		local t = gui and gui:FindFirstChild("Text")
		if t then t.Text = pet.emoji .. " " .. pet.name end
	end
	part:SetAttribute("PetId", id)
end

task.spawn(function()
	while true do
		task.wait(Config.Pets.FollowTick)
		for plr, part in pairs(companions) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and part.Parent ~= nil then
				local target = hrp.Position
					+ Vector3.new(0, Config.Pets.FollowHeight, 0)
					- hrp.CFrame.LookVector * Config.Pets.FollowDistance
				part.CFrame = CFrame.new(part.Position:Lerp(target, Config.Pets.FollowLerp))
			end
		end
	end
end)

--============================================================================ vault slots

local usedSlots = {}    -- [index] = player
local playerSlot = {}   -- [player] = index

local function claimSlot(plr)
	local i = 0
	while usedSlots[i] do i += 1 end
	usedSlots[i] = plr
	playerSlot[plr] = i
	return i
end

local function releaseSlot(plr)
	local i = playerSlot[plr]
	if i ~= nil then usedSlots[i] = nil end
	playerSlot[plr] = nil
end

-- Recycled indices, never an offset that marches outward forever.
local function slotOrigin(index)
	return Vector3.new(index * HUB.VaultSpacing, HUB.VaultOriginY, 0)
end

--============================================================================ runs

local active = {}   -- [player] = { run, model, folder, origin, gemParts, plane, seal, elapsed }

function toast(plr, text)
	ToastEvent:FireClient(plr, text)
end

local function tierSummary(p)
	local out = {}
	for i, t in ipairs(Config.Tiers) do
		local unlocked = Progression.isUnlocked(Config, i, p.totalBanked)
		out[i] = {
			index = i, id = t.id, name = t.name, emoji = t.emoji,
			unlocked = unlocked, unlockGems = t.unlockGems,
			floor = p.floors[i] or 1,
			remaining = math.max(0, t.unlockGems - p.totalBanked),
		}
	end
	return out
end

local function pushState(plr)
	local p = profiles[plr]
	if not p then return end
	local petList = {}
	for i, pet in ipairs(Config.Pets.List) do
		petList[i] = {
			id = pet.id, name = pet.name, emoji = pet.emoji, cost = pet.cost, mult = pet.mult,
			owned = Pets.owns(p, pet.id), equipped = (p.equipped == pet.id),
		}
	end
	StateEvent:FireClient(plr, {
		gems = p.gems, totalBanked = p.totalBanked,
		escapes = p.escapes, wipes = p.wipes,
		mult = Pets.multiplier(Config, p),
		rarity = Config.Pets.Rarity,
		tiers = tierSummary(p),
		pets = petList,
		inRun = active[plr] ~= nil,
		canSave = p.canSave,
	})
end

local function updateLeaderstats(plr)
	local p = profiles[plr]
	local ls = plr:FindFirstChild("leaderstats")
	if not p or not ls then return end
	local g = ls:FindFirstChild("Gems")
	if g then g.Value = p.gems end
	local b = ls:FindFirstChild("Banked")
	if b then b.Value = p.totalBanked end
end

local function teleportToHub(plr)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(vec(HUB.SpawnPosition) + Vector3.new(0, 2, 0))
	end
end

local function teardownRun(plr)
	local a = active[plr]
	if not a then return end
	active[plr] = nil
	if a.folder then a.folder:Destroy() end   -- ONE Destroy takes the whole vault with it
	releaseSlot(plr)
end

-- Build the vault for one run. Returns the model (pure tables) and the folder it landed in.
local function buildVault(plr, tierIndex, floor)
	local spec = Progression.difficulty(Config, tierIndex, floor)
	spec.seed = Progression.seedFor(Config, tierIndex, floor)
	local model = VaultFloor.build(Config, spec, MazeGen, Rng)

	-- THE COUNTDOWN IS DERIVED FROM THE VAULT THAT WAS JUST BUILT, and it has to happen in this
	-- order: BFS the maze that actually generated, price the climb, then hand the runner that
	-- much time times the floor's slack. v1 read three typed numbers off the tier and computed
	-- the plane's speed as height/countdown, so every storey added made the plane sweep the lower
	-- ones FASTER — Silver and Gold were unwinnable on floor 1 and nothing in the repo measured a
	-- traversal to notice. See src/shared/VaultPath.luau and tests/Collapse.spec.luau.
	spec.collapseSeconds = VaultPath.countdown(Config, model, spec.slack, VaultFloor)

	local idx = claimSlot(plr)
	local origin = slotOrigin(idx)

	local folder = Instance.new("Folder")
	folder.Name = "Vault_" .. plr.UserId
	folder:SetAttribute("TierIndex", tierIndex)
	folder:SetAttribute("Floor", floor)
	folder.Parent = vaultsFolder

	local plane, seal
	-- THE SHAFT'S PADS, indexed the way src/shared/Ascent.luau indexes them, so the crumble loop
	-- can turn one change into one part write. The name is the join: VaultFloor builds
	-- "Step_<storey>_<index>" and nothing else in the vault is called that.
	local padParts = {}
	for s = 0, model.storeys - 2 do padParts[s] = {} end
	for _, def in ipairs(model.parts) do
		local part = instantiate(def, origin, folder)
		if def.group == "step" then padParts[def.storey][tonumber(string.match(def.name, "_(%d+)$"))] = part end
		if def.group == "killplane" then plane = part end
		if def.group == "seal" then seal = part end
		if def.group == "exitpad" then
			Fx.attachGlow(part, col(Config.Tiers[tierIndex].gemColor), 3, 34)
			label(part, "🚪 ESCAPE", 240, 6)
		end
	end
	-- EVERY PAD ASCENT WILL MOVE HAS A PART TO MOVE. Ascent.update records a flip as drawn when it
	-- reports it, and the flip loop skips a pad with no part — so a pad missing here would be a pad
	-- stuck gone (or stuck solid) for the rest of the run, silently. Refuse to build that vault
	-- instead (obby review finding 12, REVIEW-5 §12).
	for s = 0, model.storeys - 2 do
		for _, pad in ipairs(model.shafts[s + 1].pads) do
			assert(padParts[s][pad.index] ~= nil, string.format(
				"[Vault] %s: shaft %d pad %d has no part to crumble", folder.Name, s, pad.index))
		end
	end
	if plane then Fx.attachGlow(plane, col(Config.Hud.DangerColor), 3, 60) end
	if seal then Fx.attachGlow(seal, col(Config.Hud.DangerColor), 2, 24) end

	-- One torch per storey, at the stairwell, so a Cozy-lit vault is readable without a light
	-- on every gem. ClockTime is 0 in this preset: with no lamps the vault is pitch black and
	-- completely silent about it.
	for s = 0, model.storeys - 1 do
		local cell = model.exitCells[s + 1]
		local fx, fy = 2 * cell.cx + 1, 2 * cell.cy + 1
		local lx = (fx - (model.gCols - 1) / 2) * model.cellSize
		local lz = (fy - (model.gRows - 1) / 2) * model.cellSize
		local torch = Instance.new("Part")
		torch.Name = "Torch_" .. s
		torch.Anchored = true
		torch.CanCollide = false
		torch.CanQuery = false
		torch.Size = Vector3.new(0.6, 0.6, 0.6)
		torch.Transparency = 1
		torch.CFrame = CFrame.new(origin + Vector3.new(lx, s * model.storeyHeight + 10, lz))
		torch.Parent = folder
		Fx.attachGlow(torch, Color3.fromRGB(255, 190, 120), 2.2, 46)
	end

	local gemParts = {}
	for _, g in ipairs(model.gems) do
		local part = Instance.new("Part")
		part.Name = "Gem_" .. g.id
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(2.4, 2.4, 2.4)
		part.CFrame = CFrame.new(origin + vec(g.position))
		part.Material = Enum.Material.Neon
		part.Color = col(g.color)
		part:SetAttribute("GemId", g.id)
		part.Parent = folder
		Fx.sparkle(part, col(g.color))
		gemParts[g.id] = part
	end

	Fx.dustVolume(folder, Vector3.new(model.footprint.w, model.storeys * model.storeyHeight,
		model.footprint.d),
		CFrame.new(origin + Vector3.new(0, model.storeys * model.storeyHeight / 2, 0)),
		Color3.fromRGB(190, 170, 140), 10)

	-- ASK THE FOLDER. Counting a loop counter against itself is the same arithmetic on both
	-- sides and can never disagree; the defect that shipped in this repo was a missing
	-- `part.Parent`, which raises nothing, warns nothing, and leaves every unit test green.
	local landed = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then landed += 1 end
	end
	local wanted = #model.parts + #model.gems + model.storeys
	assert(landed >= wanted, string.format(
		"[Vault] %s built %d BaseParts, wanted at least %d", folder.Name, landed, wanted))

	return model, folder, origin, gemParts, plane, seal, spec, padParts
end

local finishRun

-- WHERE THE RUNNER IS, AND THE SHAFT UNDER THEM, looked at every Config.Ascent.SampleSeconds —
-- four times per rules tick. A runner who chains the hops has a pad under their feet for about
-- 0.13 s, and the 0.2 s rules tick missed a third of those landings: the pads they chained over
-- never crumbled (REVIEW-5 §3, robloxemu/check_vaultrunners_shaft.luau §6). So the trusted position
-- is stepped here, the pad under it is touched here, and the shaft's flips are drawn here; the
-- rules (gems, exit, collapse, seal) still run at Run.TickSeconds in tickRun, against the position
-- this left in `a.trusted`.
local function watchRunner(plr, a, dt)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		-- WHERE THE CLIENT SAYS IT IS...
		local claimed = hrp.Position - a.origin
		-- ...and where a runner could actually have got to by now. Every rule reads the second
		-- one. In Roblox the client owns its character's physics, so the first is a claim; writing
		-- the root part onto the exit pad used to bank a whole vault instantly.
		local claim = { x = claimed.X, y = claimed.Y, z = claimed.Z }
		local t = Trace.step(a.trace, claim, dt)
		a.trusted = Vector3.new(t.x, t.y, t.z)
		-- ...and whether a runner could have got to the CLAIM through the corridors and stairwells.
		-- The gate decides nothing here: it keeps its own validated position, and finishRun asks it
		-- once whether the escape counts for the board. Every rule still reads `a.trusted`.
		-- pcall'd: the gate is new code beside the economy, and a fault in it must cost a rank, never a run.
		pcall(FlierGate.step, a.gate, a.model, claim, dt)

		-- THE CLIMB SHAFT. Standing on a pad starts its crumble; the pad is gone a beat later and
		-- back a few seconds after that. This reads the TRUSTED position like every rule in the run
		-- loop: a crumble driven by the client's claim would let a teleporting client pre-crumble a
		-- whole vault on the way past.
		local onStorey, onPad = Ascent.padUnder(Config, a.model, t, a.ascent, a.elapsed)
		if onPad ~= nil then Ascent.touch(Config, a.ascent, onStorey, onPad, a.elapsed) end
	else
		a.trusted = nil
	end

	-- ...and draw whatever the shaft did. Only the FLIPS: writing CanCollide on every pad of a
	-- five-storey vault every sample is 24 replicated property writes at 20Hz for nothing.
	-- This runs outside the `if hrp` above on purpose: a pad that has crumbled must come back on
	-- time even while the server cannot see the runner's root for a moment. (A respawn is not that
	-- case: onCharacter ends the run on every CharacterAdded, and the vault, its pads and this state
	-- go with it.)
	for _, ch in ipairs(Ascent.update(Config, a.ascent, a.elapsed)) do
		local part = a.padParts[ch.storey] and a.padParts[ch.storey][ch.index]
		if part then
			part.CanCollide = ch.solid
			part.CanQuery = ch.solid
			part.Transparency = ch.solid and 0 or 1
			part.CastShadow = ch.solid
		end
	end
end

local function tickRun(plr, a)
	local p = profiles[plr]
	if not p then return end
	local model, run = a.model, a.run
	local now = a.elapsed

	-- The collapse: one plane sweeping up, one seal coming down. No new physics — two CFrame
	-- writes per tick against numbers RunState already owns.
	local planeY = RunState.planeY(run, model, now)
	if a.plane then
		a.plane.CFrame = CFrame.new(a.origin + Vector3.new(0, planeY, 0))
	end
	if a.seal then
		local t = RunState.collapseProgress(run, now)
		local sy = model.seal.startY + (model.seal.endY - model.seal.startY) * t
		a.seal.CFrame = CFrame.new(a.origin + Vector3.new(model.seal.x, sy, model.seal.z))
	end

	-- The TRUSTED position watchRunner left this sample (nil while there is no root part).
	local local_ = a.trusted
	if local_ then
		for id, part in pairs(a.gemParts) do
			local g = a.gemById[id]
			if (local_ - vec(g.position)).Magnitude <= RUN.CollectRadius then
				local ok = RunState.collect(run, id, g.value, now)
				if ok then
					part:Destroy()
					a.gemParts[id] = nil
					RunEvent:FireClient(plr, "gem", {
						carried = run.carried,
						collected = RunState.collectedCount(run),
						total = #model.gems,
					})
				end
			end
		end

		if (local_ - vec(model.exit.position)).Magnitude <= RUN.ExitRadius then
			finishRun(plr, "exit")
			return
		end

		-- The collapse caught you: your feet are under the plane. RunState owns the comparison,
		-- so tests/Collapse.spec.luau can ask "would this runner have died here" a few thousand
		-- times per vault without booting a server, against the same rule that runs live.
		if RunState.caught(run, model, local_.Y, now) then
			finishRun(plr, "collapse")
			return
		end
	end

	-- Sealed and still inside. Always terminate the run here, so a player who stops moving is
	-- resolved rather than left standing in a vault with a finished countdown.
	if RunState.isSealed(run, now) then
		finishRun(plr, "exit")
		return
	end

	a.sinceTick += 1
	if a.sinceTick >= 3 then
		a.sinceTick = 0
		RunEvent:FireClient(plr, "tick", {
			timeLeft = RunState.timeLeft(run, now),
			carried = run.carried,
			collected = RunState.collectedCount(run),
			total = #model.gems,
			progress = RunState.collapseProgress(run, now),
		})
	end
end

function finishRun(plr, cause)
	local a = active[plr]
	local p = profiles[plr]
	if not a or not p then return end
	local run, now = a.run, a.elapsed

	local outcome
	if cause == "exit" then
		-- tryEscape is the ONLY place gems become real, and it refuses once the vault has
		-- sealed. Reaching the exit is not the win condition; reaching it in time is.
		local res = RunState.tryEscape(run, Pets.multiplier(Config, p), now)
		if res.ok then
			local deepestBefore = boardDepth(p)
			p.gems += res.banked
			p.totalBanked += res.banked
			p.escapes += 1
			p.floors[a.tierIndex] = (p.floors[a.tierIndex] or 1) + 1
			-- THE FLIER GATE (owner decision 2026-10-11). The escape is banked either way: gems, the
			-- floor and the run were judged on Trace and stay exactly as they were. What the gate
			-- decides is whether it counts for the BOARD: only if the position it validated sample by
			-- sample, through the vault's own corridors and stairwells, can be at the exit now.
			local gateOk, verdict = pcall(FlierGate.traced, Config, a.gate, a.model)
			local traced = gateOk and verdict == true
			if traced then
				p.traced[a.tierIndex] = math.min((p.traced[a.tierIndex] or 1) + 1, p.floors[a.tierIndex])
			end
			-- THE BOARD'S REACH TIME. Stamped here, when the server banks an escape DEEPER than any
			-- before it, and saved with the floors in the flush below: a tie on the board goes to
			-- whoever got there first, so the time must be the escape's, never the board write's
			-- (a write can fail and be retried a session later). An escape that is not the deepest
			-- (Silver floor 1 after Bronze floor 29) leaves it alone, and so does one that was not traced.
			if boardDepth(p) > deepestBefore then
				p.bestAt = os.time()
			end
			outcome = { ok = true, reason = "escaped", banked = res.banked, carried = res.carried,
				time = now, floor = a.floor, tier = a.tierIndex, ranked = traced }
			if traced then
				toast(plr, string.format("💎 Banked %d gems — %s floor %d cleared!",
					res.banked, Config.Tiers[a.tierIndex].name, a.floor))
			else
				-- Told once, here, in one line with what they banked (the HUD shows one toast at a time).
				toast(plr, string.format(Config.Board.Text.Untraced, res.banked))
			end
		else
			p.wipes += 1
			outcome = { ok = false, reason = "sealed", banked = 0, carried = res.carried,
				time = now, floor = a.floor, tier = a.tierIndex }
			toast(plr, string.format("🔒 The vault sealed with %d gems inside. Nothing banked.",
				res.carried))
		end
	else
		local res = RunState.kill(run, now, cause)
		p.wipes += 1
		outcome = { ok = false, reason = cause, banked = 0, carried = res.lost,
			time = now, floor = a.floor, tier = a.tierIndex }
		toast(plr, string.format("💀 The collapse took you — %d gems lost.", res.lost))
	end

	teleportToHub(plr)
	teardownRun(plr)
	updateLeaderstats(plr)
	RunEvent:FireClient(plr, "end", outcome)
	pushState(plr)
	-- The one remaining IMMEDIATE write, and it is safe to make immediate: a run cannot end more
	-- often than a run can be started, and the shortest countdown the game can generate is
	-- Config.Collapse.MinSeconds. This is also the moment worth not losing — gems just became
	-- real, or a wipe just happened.
	flush(plr, false)
end

local function beginRun(plr, tierIndex)
	local p = profiles[plr]
	if not p then return end
	if type(tierIndex) ~= "number" then return end
	tierIndex = math.floor(tierIndex)

	if active[plr] then
		toast(plr, "You are already inside a vault.")
		return
	end

	-- NO BODY, NO RUN — and this check has to come BEFORE anything is built or claimed, not just
	-- before the teleport. Players.RespawnTime is 5 seconds and Reset is how a stuck player gets
	-- unstuck, so `plr.Character == nil` is a window every player passes through several times a
	-- session. Starting the run anyway built a vault they were not in, refused every further tap
	-- with "You are already inside a vault" for the whole countdown, and charged them a permanent
	-- wipe at the end for a run they never took.
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		toast(plr, "⏳ Still respawning — tap again once you are back on your feet.")
		return
	end

	local tier = Progression.tier(Config, tierIndex)
	if not tier then
		toast(plr, "That vault does not exist.")
		return
	end
	if not Progression.isUnlocked(Config, tierIndex, p.totalBanked) then
		-- Never a silent no-op: say exactly what is missing.
		toast(plr, string.format("🔒 %s needs %d gems banked in total — %d to go.",
			tier.name, tier.unlockGems, tier.unlockGems - p.totalBanked))
		return
	end

	local floor = math.max(1, p.floors[tierIndex] or 1)
	local model, folder, origin, gemParts, plane, seal, spec, padParts = buildVault(plr, tierIndex, floor)

	local gemById = {}
	for _, g in ipairs(model.gems) do gemById[g.id] = g end

	local a = {
		run = RunState.start(Config, spec, 0),
		model = model, folder = folder, origin = origin,
		gemParts = gemParts, gemById = gemById,
		plane = plane, seal = seal,
		padParts = padParts,
		-- THE OBBY'S STATE, one per run. The pads of the climb shaft crumble under the runner and
		-- come back; Ascent owns when, this file owns the Roblox writes.
		ascent = Ascent.new(Config, model),
		tierIndex = tierIndex, floor = floor,
		elapsed = 0, sinceTick = 0,
		-- Seeded from the drop-in the SERVER is about to write, never from anything the client
		-- said. If the trace started at the client's claimed position, a client that claimed to
		-- be at the exit before the run began would start there.
		trace = Trace.new(Config, model.spawn.position),
		-- ...and so is the flier gate's validated position: the drop-in is the one move the SERVER
		-- makes in a run (a death or a respawn ends the run, onCharacter), so this is its only seed.
		gate = FlierGate.new(Config, model, model.spawn.position),
	}
	active[plr] = a

	-- `hrp` was captured before the vault was built, and nothing between here and there yields,
	-- so it is still the same root part. Re-reading plr.Character here instead would reintroduce
	-- the guard-shaped-but-not-guarding shape this whole block exists to remove.
	hrp.CFrame = CFrame.new(origin + vec(model.spawn.position))

	RunEvent:FireClient(plr, "start", {
		tier = tierIndex, tierName = tier.name, emoji = tier.emoji,
		floor = floor, collapseSeconds = spec.collapseSeconds,
		gems = #model.gems, storeys = model.storeys,
		mult = Pets.multiplier(Config, p),
	})
	pushState(plr)

	-- Two rates in one loop: the runner and the shaft are watched every Ascent.SampleSeconds
	-- (watchRunner), the run's rules are judged every Run.TickSeconds (tickRun). One clock,
	-- `a.elapsed`, for both, so a pad's crumble and the collapse can never disagree about the time.
	task.spawn(function()
		local sample = Config.Ascent.SampleSeconds
		local sinceRules = 0
		while active[plr] == a do
			local dt = task.wait(sample)
			if type(dt) ~= "number" then dt = sample end
			if active[plr] ~= a then break end
			a.elapsed += dt
			watchRunner(plr, a, dt)
			sinceRules += dt
			if sinceRules >= RUN.TickSeconds - 1e-6 then
				sinceRules = math.min(sinceRules - RUN.TickSeconds, RUN.TickSeconds)
				tickRun(plr, a)
			end
		end
	end)
end

--============================================================================ remotes in

EnterEvent.OnServerEvent:Connect(function(plr, tierIndex)
	beginRun(plr, tierIndex)
end)

local function doBuy(plr, petId)
	local p = profiles[plr]
	if not p or type(petId) ~= "string" then return end
	local res = Pets.buy(Config, p, petId)
	if res.ok then
		toast(plr, "🐾 " .. res.pet.emoji .. " " .. res.pet.name .. " joined your squad!")
		if not Pets.owns(p, p.equipped) then Pets.equip(Config, p, res.pet.id) end
	elseif res.reason == "poor" then
		local pet = Pets.byId(Config, petId)
		toast(plr, string.format("💎 %s costs %d — you have %d.", pet.name, pet.cost, p.gems))
	elseif res.reason == "owned" then
		Pets.equip(Config, p, petId)
		toast(plr, "🐾 Equipped.")
	else
		toast(plr, "That pet is not on the stall.")
	end
	updateLeaderstats(plr)
	refreshCompanion(plr)
	pushState(plr)
	-- The player sees the toast, the wallet and the companion IMMEDIATELY; only the DataStore
	-- write is coalesced. A refusal above leaves the profile untouched, so it will not produce a
	-- write at all.
	requestSave(plr)
end

local function doEquip(plr, petId)
	local p = profiles[plr]
	if not p then return end
	if petId ~= nil and type(petId) ~= "string" then return end
	local res = Pets.equip(Config, p, petId)
	if not res.ok then
		toast(plr, res.reason == "unowned" and "You do not own that one yet."
			or "That pet is not on the stall.")
	end
	refreshCompanion(plr)
	pushState(plr)
	requestSave(plr)
end

BuyEvent.OnServerEvent:Connect(doBuy)
EquipEvent.OnServerEvent:Connect(doEquip)

-- The in-world affordances go through the SAME handlers as the HUD buttons.
for i, part in pairs(portalParts) do
	local cd = part:FindFirstChildOfClass("ClickDetector")
	if cd then
		cd.MouseClick:Connect(function(clicker)
			beginRun(clicker, i)
		end)
	end
end
for petId, part in pairs(stallParts) do
	local cd = part:FindFirstChildOfClass("ClickDetector")
	if cd then
		-- Straight into the same handler the remote uses. `RemoteEvent:FireServer` is a CLIENT
		-- call and does nothing here; routing a server-side click through it would have made
		-- every pedestal in the stall inert.
		cd.MouseClick:Connect(function(clicker) doBuy(clicker, petId) end)
	end
end

--============================================================================ the highscore board

-- docs/complete-game-standard.md §3, Config.Board. The metric is the deepest vault escaped, measured
-- by this server (finishRun, behind RunState and Trace) and counted only for escapes it could trace
-- through the vault (FlierGate, `boardDepth`), stored encoded so a tie goes to whoever got
-- there FIRST (Board.encode), and written only when it deepens (writeBoard, above). The sign stands in
-- the hub, west of the spawn with its face turned to it; its ProximityPrompt toggles PUBLIC / FRIENDS
-- per player, and each player's view goes to their own client (Board.client draws it on the sign).
-- Public: one GetSortedAsync per PublicCacheSeconds. Friends: only when asked, capped at FriendsCap,
-- cached per player and throttled (Board.newLimiter plus Roblox's own budget). Names are looked up and
-- kept in memory, never stored.
local BC = Config.Board

local boardPart = Instance.new("Part")
boardPart.Name = "DeepestBoard"
boardPart.Anchored = true
boardPart.Size = vec(BC.Size)
do
	local centre = vec(BC.Position)
	local spawnAt = vec(HUB.SpawnPosition)
	-- the front face (local -Z, where Board.client draws) looks at the spawn, level
	boardPart.CFrame = CFrame.lookAt(centre, Vector3.new(spawnAt.X, centre.Y, spawnAt.Z))
end
boardPart.Material = Enum.Material.SmoothPlastic
boardPart.Color = Color3.fromRGB(24, 22, 34)
boardPart.TopSurface = Enum.SurfaceType.Smooth
boardPart.Parent = hubFolder
do
	-- A gold frame behind the sign: something interactive should look interactive
	-- (docs/new-game-checklist.md §2). Parented to the sign, so it is part of it, not in the way.
	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.CanQuery = false
	trim.CastShadow = false
	trim.Size = Vector3.new(BC.Size.x + 0.8, BC.Size.y + 0.8, 0.6)
	trim.CFrame = boardPart.CFrame * CFrame.new(0, 0, 0.35)   -- local +Z is behind the sign
	trim.Material = Enum.Material.Neon
	trim.Color = col(Config.Hud.AccentColor)
	trim.Parent = boardPart
end
local boardPrompt = Instance.new("ProximityPrompt")
do
	-- Low on the front face. It pops up when a runner walks over to the sign, never while they stand on
	-- the spawn pad (check_vaultrunners_board measures the nearest point of the pad against the reach).
	local at = Instance.new("Attachment")
	at.Name = "PromptAt"
	at.Position = Vector3.new(0, -BC.Size.y / 2 + 2, -(BC.Size.z / 2 + 0.1))
	at.Parent = boardPart
	boardPrompt.Name = "BoardPrompt"
	boardPrompt.ActionText = BC.Text.Prompt
	boardPrompt.ObjectText = BC.Text.Title
	boardPrompt.HoldDuration = 0
	boardPrompt.MaxActivationDistance = BC.PromptDistance
	boardPrompt.RequiresLineOfSight = false
	boardPrompt.KeyboardKeyCode = Enum.KeyCode.E
	boardPrompt.Parent = at
end

-- Names: a player in this server, the friends list, or GetNameFromUserIdAsync; kept in memory, never
-- stored. A failed lookup is not remembered, so the next view tries again.
local nameCache = {}   -- [userId] = name
local function nameOf(userId)
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
	return "#" .. tostring(userId)
end
local function withNames(rows)
	local out = {}
	for i, r in ipairs(rows) do
		out[i] = { rank = r.rank, userId = r.userId, depth = r.depth, you = r.you, name = nameOf(r.userId) }
	end
	return out
end

-- A player in this server: their value from memory, fresher than the store (which hears about a new
-- depth after the profile holding it is saved).
local function liveValue(p)
	if not p then return 0 end
	local depth = boardDepth(p)
	if depth <= 0 then return 0 end
	return Board.encode(depth, p.bestAt, BC)
end

local boardMode = {}   -- [player] = "public" | "friends"
local publicView = { rows = {}, note = if boardStore then BC.Text.Loading else BC.Text.Offline }

local function sendBoard(plr, mode, view)
	-- `viewer`: FireClient reaches only this player in Roblox; the field lets the client ignore the rest.
	BoardEvent:FireClient(plr, { viewer = plr.UserId, mode = mode, rows = view.rows, note = view.note })
end

local function refreshPublic()
	if not boardStore then return end
	local ok, page = pcall(function()
		return boardStore:GetSortedAsync(false, BC.PublicRows)
	end)
	if not ok or not page then return end   -- keep the last list rather than blank the sign
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

-- Friends: on demand, capped, cached per player. A failed fetch is retried after a minute, not per tap.
local friendsCache = Board.newCache(BC.FriendsCacheSeconds)
local friendsFailed = Board.newCache(60)
local scoreCache = Board.newCache(BC.ScoreCacheSeconds)
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, clock())
local fetching = {}   -- [player] = true while their friends list is being read

local function friendIdsOf(plr)
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

-- Always leave BudgetReserve GetAsync calls in Roblox's own budget (if it cannot be read, only the
-- limiter applies).
local function budgetLeft()
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return not (ok and type(budget) == "number" and budget < BC.BudgetReserve)
end

-- A friend's stored value (0 = never escaped), or nil when throttled (try again shortly). A read that
-- fails counts as 0 without being cached, so one bad key never stalls the list.
local function friendValue(userId)
	local here = Players:GetPlayerByUserId(userId)
	if here and profiles[here] then return liveValue(profiles[here]) end
	local now = clock()
	if Board.cacheHas(scoreCache, userId, now) then return Board.cacheGet(scoreCache, userId, now) end
	if not boardStore then return 0 end
	if not budgetLeft() or not Board.take(readLimiter, now) then return nil end
	local ok, v = pcall(function()
		return boardStore:GetAsync(Board.key(userId))
	end)
	if not ok then return 0 end
	local value = if type(v) == "number" then v else 0
	Board.cachePut(scoreCache, userId, value, now)
	return value
end

local function showFriends(plr)
	if not boardStore then
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Offline })
		return
	end
	if fetching[plr] then
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading })   -- the fetch running sends soon
		return
	end
	fetching[plr] = true
	task.spawn(function()
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading })
		local ids, failedList = friendIdsOf(plr)
		local values = {}
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
				if clock() - lastPush >= 0.5 then
					push()
					lastPush = clock()
				end
				task.wait(1)   -- throttled: wait for the limiter
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

-- The prompt is the player's own action, and it always answers: the other view, at once.
boardPrompt.Triggered:Connect(function(plr)
	-- (a player still loading gets the view too: liveValue(nil) is "not escaped yet". Only one who has
	-- already left is ignored, so the per-player tables never keep an entry for them.)
	if plr.Parent ~= Players then return end
	boardMode[plr] = if boardMode[plr] == "friends" then "public" else "friends"
	if boardMode[plr] == "friends" then
		showFriends(plr)
	else
		sendBoard(plr, "public", publicView)
	end
end)

-- The public list, refreshed at most once per PublicCacheSeconds and only while someone is here.
task.spawn(function()
	while true do
		if #Players:GetPlayers() > 0 then
			refreshPublic()
			for plr, mode in pairs(boardMode) do
				if mode == "public" and plr.Parent == Players then sendBoard(plr, "public", publicView) end
			end
		end
		task.wait(BC.PublicCacheSeconds)
	end
end)

--============================================================================ players

local function onCharacter(plr, char)
	-- A player who dies or resets mid-run loses the run; the vault they were in has to go with
	-- them, or the slot leaks and the next join builds further out along +X forever.
	if active[plr] then
		task.defer(function()
			if active[plr] then finishRun(plr, "collapse") end
		end)
	end

	-- MAKE Config.Movement.WalkSpeed TRUE. Every countdown in the game is derived from
	-- (distance along the BFS-optimal route) / WalkSpeed, so if the Humanoid keeps Roblox's
	-- default 16 while Config says 24, every vault in the game is 50% harder than the spec that
	-- signed it off believes — and the spec would still be green, because it reads Config too.
	-- The review's exact words were "nothing in the game sets WalkSpeed".
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = Config.Movement.WalkSpeed
	end
end

local function onPlayerAdded(plr)
	-- docs/complete-game-standard.md §1, SPAWN-ORDER.md §3: point the engine at the one real, enabled
	-- spawn BEFORE the character loads (loadProfile below yields), so its own placement is the answer.
	plr.RespawnLocation = hubSpawn
	local p = loadProfile(plr)
	profiles[plr] = p
	-- What is already on disk. Without this a player who joins and changes nothing still writes
	-- on their first flush tick, which is the same wasted call the fingerprint exists to stop.
	p.savedFingerprint = saveFingerprint(p)

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local gems = Instance.new("IntValue")
	gems.Name = "Gems"
	gems.Value = p.gems
	gems.Parent = ls
	local banked = Instance.new("IntValue")
	banked.Name = "Banked"
	banked.Value = p.totalBanked
	banked.Parent = ls
	ls.Parent = plr

	plr.CharacterAdded:Connect(function(char) onCharacter(plr, char) end)
	if plr.Character then onCharacter(plr, plr.Character) end

	refreshCompanion(plr)
	pushState(plr)
	if not p.canSave then
		toast(plr, "⚠️ Progress cannot be saved this session.")
	end

	-- The board: this player sees the public view first, and their saved deepest escape is offered to
	-- the board (Board.keepHigher keeps a deeper or earlier value that is already there). That is also
	-- the retry for a board write that failed last session: bestAt was saved with the floors.
	boardMode[plr] = "public"
	sendBoard(plr, "public", publicView)
	writeBoard(plr, p)
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- Anyone already in when this script finished loading (Studio play-solo joins before the server
-- scripts do) would otherwise have no profile and no leaderstats, and every click would no-op.
for _, plr in ipairs(Players:GetPlayers()) do
	if profiles[plr] == nil then task.spawn(onPlayerAdded, plr) end
end

Players.PlayerRemoving:Connect(function(plr)
	local comp = companions[plr]
	if comp then comp:Destroy() end
	companions[plr] = nil
	teardownRun(plr)
	flush(plr, true)   -- forced: the lock has to come off even if nothing changed
	pendingSave[plr] = nil
	profiles[plr] = nil
	boardMode[plr] = nil
	boardSent[plr] = nil
	fetching[plr] = nil
end)

-- THE ONLY PLACE A REMOTE-DRIVEN SAVE ACTUALLY WRITES. Handlers mark the profile pending and
-- this loop performs at most one write per player per tick, so the write rate is bounded by the
-- clock rather than by how fast a client can fire a RemoteEvent. It replaces a 45-second
-- autosave that wrote every profile whether or not anything had changed: a profile with nothing
-- pending now has nothing to write, and a change reaches the DataStore within one tick instead
-- of within forty-five seconds.
task.spawn(function()
	while true do
		task.wait(Config.Save.FlushTickSeconds)
		for plr in pairs(pendingSave) do
			if profiles[plr] ~= nil then flush(plr, false) end
		end
	end
end)

-- THE SHUTDOWN. Roblox gives game:BindToClose up to 30 s and waits for nothing else: a purchase still
-- pending on the flush tick, and the leave that releases the lock, may never run. So every profile this
-- server holds is written here, with its lock released (flush still writes only while the record carries
-- this session's token). One after another: a handful of UpdateAsyncs is well inside the 30 s.
game:BindToClose(function()
	for plr in pairs(profiles) do
		flush(plr, true)
	end
end)

print("[Vault] Vault Runners server ready — "
	.. #Config.Tiers .. " vaults, " .. #Config.Pets.List .. " Vault-Keepers.")
