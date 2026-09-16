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

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local MazeGen = require(ReplicatedStorage:WaitForChild("MazeGen"))
local VaultFloor = require(ReplicatedStorage:WaitForChild("VaultFloor"))
local VaultPath = require(ReplicatedStorage:WaitForChild("VaultPath"))
local Progression = require(ReplicatedStorage:WaitForChild("Progression"))
local RunState = require(ReplicatedStorage:WaitForChild("RunState"))
local Pets = require(ReplicatedStorage:WaitForChild("Pets"))
local Trace = require(ReplicatedStorage:WaitForChild("Trace"))
local Ascent = require(ReplicatedStorage:WaitForChild("Ascent"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

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
	return DataStoreService:GetDataStore(Config.Save.Store)
end, "profiles")

local profiles = {}   -- [player] = profile
local pendingSave = {}   -- [player] = true, "this profile wants a write on the next flush tick"
local requestSave     -- forward declaration; defined under flush()

local function defaultProfile()
	local floors = {}
	for i = 1, #Config.Tiers do floors[i] = 1 end
	return {
		gems = 0,
		totalBanked = 0,     -- only ever goes UP; this is what unlocks vaults
		pets = {},
		equipped = nil,
		floors = floors,     -- [tierIndex] = next floor number in that vault
		escapes = 0,
		wipes = 0,
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

-- Soft session lock. The owner token is game.JobId — a STABLE per-session value. A timestamp
-- rewritten on every save fires the guard against yourself and silently stops saving.
local function loadProfile(plr)
	local p = defaultProfile()
	if not store then return p end
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
				local f = numKeys(d.floors)
				for i = 1, #Config.Tiers do p.floors[i] = math.max(1, tonumber(f[i]) or 1) end
			end
			if lockedByOther then
				acquired = false
				return old
			end
			acquired = true
			old.jobId = game.JobId
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
	if not acquired then
		warn("[Vault] " .. plr.Name .. " is locked by another server; playing without saving.")
	end
	return p
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
	local floors = {}
	for i = 1, #Config.Tiers do floors[i] = tostring(p.floors[i] or 1) end
	return table.concat({
		tostring(p.gems), tostring(p.totalBanked), tostring(p.escapes), tostring(p.wipes),
		tostring(p.equipped), table.concat(owned, ","), table.concat(floors, ","),
	}, "|")
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
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			if old.jobId ~= nil and old.jobId ~= game.JobId
				and (tonumber(old.lockUntil) or 0) > os.time() then
				return nil   -- somebody else owns the slot; ABORT the write
			end
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
			}
			wrote = true
			return old
		end)
	end)
	if not ok then warn("[Vault] save failed for " .. plr.Name .. ": " .. tostring(err)) end
	-- Only a transform that actually RETURNED a value wrote anything. The abort branch above
	-- returns nil, which is a successful pcall and a save that did not happen; treating that as
	-- written would clear the fingerprint and lose the change for good.
	if ok and wrote then
		p.savedFingerprint = fingerprint
		pendingSave[plr] = nil
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

local function toast(plr, text)
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

local function tickRun(plr, a, dt)
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

	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		-- WHERE THE CLIENT SAYS IT IS...
		local claimed = hrp.Position - a.origin
		-- ...and where a runner could actually have got to by now. Every rule below reads the
		-- second one. In Roblox the client owns its character's physics, so the first is a claim;
		-- writing the root part onto the exit pad used to bank a whole vault instantly.
		local t = Trace.step(a.trace, { x = claimed.X, y = claimed.Y, z = claimed.Z }, dt)
		local local_ = Vector3.new(t.x, t.y, t.z)

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

		-- THE CLIMB SHAFT. Standing on a pad starts its crumble; the pad is gone a beat later and
		-- back a few seconds after that. This reads `local_` — the TRUSTED position — like every
		-- other rule in this loop: a crumble driven by the client's claim would let one player
		-- dissolve the shaft by lying about where they are, and would let a teleporting client
		-- pre-crumble a whole vault on the way past.
		local onStorey, onPad = Ascent.padUnder(Config, model,
			{ x = local_.X, y = local_.Y, z = local_.Z }, a.ascent, now)
		if onPad ~= nil then Ascent.touch(Config, a.ascent, onStorey, onPad, now) end

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

	-- ...and draw whatever the shaft did this tick. Only the FLIPS: writing CanCollide on every
	-- pad of a five-storey vault every tick is 24 replicated property writes at 5Hz for nothing.
	-- This runs outside the `if hrp` above on purpose — a pad that has crumbled must come back
	-- even while the player has no character, or a respawn mid-climb finds a shaft with holes in
	-- it that never fill.
	for _, ch in ipairs(Ascent.update(Config, a.ascent, now)) do
		local part = a.padParts[ch.storey] and a.padParts[ch.storey][ch.index]
		if part then
			part.CanCollide = ch.solid
			part.CanQuery = ch.solid
			part.Transparency = ch.solid and 0 or 1
			part.CastShadow = ch.solid
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
			p.gems += res.banked
			p.totalBanked += res.banked
			p.escapes += 1
			p.floors[a.tierIndex] = (p.floors[a.tierIndex] or 1) + 1
			outcome = { ok = true, reason = "escaped", banked = res.banked, carried = res.carried,
				time = now, floor = a.floor, tier = a.tierIndex }
			toast(plr, string.format("💎 Banked %d gems — %s floor %d cleared!",
				res.banked, Config.Tiers[a.tierIndex].name, a.floor))
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

	task.spawn(function()
		while active[plr] == a do
			local dt = task.wait(RUN.TickSeconds)
			if type(dt) ~= "number" then dt = RUN.TickSeconds end
			if active[plr] ~= a then break end
			a.elapsed += dt
			tickRun(plr, a, dt)
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

print("[Vault] Vault Runners server ready — "
	.. #Config.Tiers .. " vaults, " .. #Config.Pets.List .. " Vault-Keepers.")
