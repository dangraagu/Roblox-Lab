-- DEEP VEIN ⛏️ — server, autoritativ. Havner i ServerScriptService.
--
-- All logikk styres av ReplicatedStorage.Config + de rene, enhets-testede modulene
-- (Mine / Ore / Economy / Prestige). Denne fila er det ENESTE stedet som vet at Roblox finnes:
-- de rene modulene returnerer vanlige tabeller, og her blir de til Parts.
--
-- Kjerne-loopen: hver spiller får sin egen sjakt (rutenett av Parts, ikke Terrain) → klikk en
-- stein for å slå på den → blokka mister HP → den knuses, malmen havner i sekken og NABOENE
-- avdekkes → sekk full → heis opp og selg → oppgrader hakke/sekk/lampe → grav dypere → treff
-- berggrunn-veggen → Rebirth: alt nullstilles mot en permanent multiplikator og en NY hule.
--
-- Et par ting som er bevisste, ikke tilfeldige:
--  * Hver Instance som lages her blir PARENTET, og etter at sjakta er bygget SPØR vi mappa hvor
--    mange deler som faktisk landet. Grow a Crystal shippet med `part.Parent` uteglemt i
--    makeSocket: hele kjerne-loopen var uspillbar, og alle 166 enhetstestene var grønne.
--  * DataStoreService:GetDataStore KASTER i en upublisert place. Uten pcall dør hele
--    server-scriptet ved lasting, og spillet kan ikke engang åpnes i Studio.
--  * Ingen stille no-ops: hver avvist handling sender en Toast til spilleren.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Mine = require(ReplicatedStorage:WaitForChild("Mine"))
local Ore = require(ReplicatedStorage:WaitForChild("Ore"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Prestige = require(ReplicatedStorage:WaitForChild("Prestige"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

-- Mørkt, kaldt og tåkete: en gruve. Horror-preset setter ClockTime 0.2, så det finnes ingen sol
-- under bakken — lampa på hodelykta og de lysende malmårene er ALT lyset spilleren har.
Fx.applyLighting(Fx.Presets.Horror)

--============================================================================== remotes

local remotes = Instance.new("Folder")
remotes.Name = "VeinRemotes"
remotes.Parent = ReplicatedStorage
local function mk(cn: string, n: string)
	local r = Instance.new(cn)
	r.Name = n
	r.Parent = remotes
	return r
end
local StateEvent = mk("RemoteEvent", "State") -- server -> klient: full tilstand
local BuyEvent = mk("RemoteEvent", "Buy") -- klient -> server: "pickaxe" | "backpack" | "lamp"
local ElevatorEvent = mk("RemoteEvent", "Elevator") -- klient -> server: "up" | "down"
local RebirthEvent = mk("RemoteEvent", "Rebirth") -- klient -> server: prestige
local ToastEvent = mk("RemoteEvent", "Toast") -- server -> klient: kort melding
local LeaderboardEvent = mk("RemoteEvent", "Leaderboard")

local function toast(plr: Player, msg: string)
	ToastEvent:FireClient(plr, msg)
end

--============================================================================== data

-- GetDataStore KASTER i en place som aldri er publisert, og igjen når "Enable Studio Access to
-- API Services" er av. Upakket drepte akkurat den feilen hele server-scriptet i forrige spill:
-- ingen verden, ingen remotes, ingen gruve. Det som skal degradere er LAGRINGEN, ikke spillet.
local function tryStore(fn, what: string)
	if not Config.Save.Enabled then return nil end
	local ok, ds = pcall(fn)
	if ok then return ds end
	warn("[DeepVein] " .. what .. " datastore unavailable (" .. tostring(ds)
		.. ") - the game runs, progress will NOT be saved this session.")
	return nil
end

local store = tryStore(function() return DataStoreService:GetDataStore(Config.Save.Store) end, "profiles")
local orderedLB = tryStore(function()
	return DataStoreService:GetOrderedDataStore(Config.Save.Leaderboard)
end, "leaderboard")

local profiles = {} -- [player] = profile

local function defaultProfile()
	return {
		cash = Config.Economy.StartCash,
		totalCash = 0,
		inventory = {}, -- [oreTier] = units carried
		pickTier = 1,
		backpackLevel = 0,
		lampLevel = 0,
		rebirths = 0,
		depthLayer = 0, -- deepest LAYER opened this run (studs are display only)
		bestLayer = 0, -- deepest LAYER ever, across every rebirth — the leaderboard
		canSave = false,
	}
end

local function key(uid: number): string
	return "u_" .. uid
end

-- DataStore serialiserer via JSON: spredte HELTALLS-nøkler kommer tilbake som STRENGER.
-- `inventory` er nøklet på malm-tier (heltall), så den MÅ normaliseres, ellers ser en
-- rejoinet spiller en tom sekk mens dataene ligger der under strengnøkler.
local function numKeys(src: any)
	local out = {}
	if type(src) == "table" then
		for k, v in pairs(src) do
			out[tonumber(k) or k] = v
		end
	end
	return out
end

-- Last + soft session-lock: last ALLTID ekte data; canSave = eier vi låsen. Kort TTL fornyet
-- av autosave, så en krasj ikke låser spilleren ute.
local function loadProfile(plr: Player)
	local p = defaultProfile()
	if not store then
		p.canSave = false
		return p
	end
	local acquired = false
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			local lockedByOther = (tonumber(old.lockUntil) or 0) > now and old.jobId ~= game.JobId
			local d = old.data
			if d then
				p.cash = tonumber(d.cash) or p.cash
				p.totalCash = tonumber(d.totalCash) or 0
				p.inventory = numKeys(d.inventory) -- integer ore-tier keys
				p.pickTier = tonumber(d.pickTier) or 1
				p.backpackLevel = tonumber(d.backpackLevel) or 0
				p.lampLevel = tonumber(d.lampLevel) or 0
				p.rebirths = tonumber(d.rebirths) or 0
				p.depthLayer = tonumber(d.depthLayer) or 0
				p.bestLayer = tonumber(d.bestLayer) or 0
			end
			if lockedByOther then
				acquired = false
				return old
			end
			acquired = true
			old.jobId = game.JobId
			old.lockUntil = now + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	if not ok then
		p.canSave = false
		warn("[DeepVein] load failed for " .. plr.Name .. ": " .. tostring(err))
	else
		p.canSave = acquired
		if not acquired then
			warn("[DeepVein] " .. plr.Name .. " READ-ONLY (locked by another session); progress won't save.")
		end
	end
	return p
end

-- Returnerer true bare hvis dataene faktisk ble persistert. Rebirth bruker det til en atomisk
-- flush: den ene uopprettelige handlingen i spillet skal aldri kunne halv-lagres.
local function saveProfile(plr: Player, releaseLock: boolean): boolean
	local p = profiles[plr]
	if not p or not p.canSave or not store then return false end
	local ok = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			old.data = {
				cash = p.cash, totalCash = p.totalCash, inventory = p.inventory,
				pickTier = p.pickTier, backpackLevel = p.backpackLevel, lampLevel = p.lampLevel,
				rebirths = p.rebirths, depthLayer = p.depthLayer, bestLayer = p.bestLayer,
			}
			old.jobId = game.JobId
			old.lockUntil = releaseLock and 0 or (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	if ok and orderedLB and p.bestLayer > 0 then
		-- OrderedDataStore krever heltall. Studs, ikke lag, så tallet leser som en dybde.
		pcall(function()
			orderedLB:SetAsync(key(plr.UserId), math.floor(Mine.depthStuds(Config, p.bestLayer)))
		end)
	end
	return ok
end

--============================================================================== per-player world

local shaftsFolder = Instance.new("Folder")
shaftsFolder.Name = "Shafts"
shaftsFolder.Parent = workspace

local SHAFT_SPACING = 160 -- studs between two players' shafts along +X
local RIM_MULT = 3 -- the layer-0 bedrock ring is built this many cells tall: nobody jumps out

local usedShafts = {} -- [shaftIndex] = player
local shaftIndex = {} -- [player] = index
local shaftFolders = {} -- [player] = Folder ("Shaft_<idx>"; EVERYTHING the player owns is in here)
local worlds = {} -- [player] = Mine.World
local opened = {} -- [player] = { [cellKey] = true }  (broken rock + entered air)
local cellParts = {} -- [player] = { [cellKey] = Part }
local cellDefs = {} -- [player] = { [cellKey] = Mine.Cell }
local cellHp = {} -- [player] = { [cellKey] = remaining hit points }
local deepestOpen = {} -- [player] = { x, y, z } — where the "DESCEND" elevator drops you
local lastSwing = {} -- [player] = tick() of the last accepted swing
local lampOf = {} -- [player] = PointLight on the character
local buildQueue = {} -- [player] = { cells, head, folder } — solids waiting for a frame's budget

local function claimShaft(plr: Player): number
	local i = 0
	while usedShafts[i] do i += 1 end
	usedShafts[i] = plr
	shaftIndex[plr] = i
	return i
end

local function shaftOrigin(idx: number): Vector3
	return Vector3.new(idx * SHAFT_SPACING, 0, 0)
end

-- Mine returns shaft-LOCAL coordinates; the per-player offset is added here and nowhere else.
local function worldPos(plr: Player, x: number, y: number, z: number): Vector3
	local lp = Mine.localPos(Config, x, y, z)
	return shaftOrigin(shaftIndex[plr] or 0) + Vector3.new(lp.x, lp.y, lp.z)
end

-- The Y a character standing inside layer `y` has its root part at: the top face of the cell
-- below, plus enough clearance for an R15 root. Used by both the spawn and the elevator, so the
-- two can never disagree about where "the floor" is.
local function standY(y: number): number
	return Mine.floorY(Config, y) + 4
end

-- The cell the SURFACE button and every respawn aim at. One name, used by the landing and by the
-- thing the landing stands on, so the two cannot drift apart.
local SPAWN_CELL_Z = 2

local function spawnCFrame(plr: Player): CFrame
	-- On the north edge of the mouth, feet on the layer-1 floor, looking south across the shaft
	-- so the first thing on screen is the SELL pad and then the hole you are about to dig.
	-- CFrame.new's identity frame looks down -Z, so this MUST be the two-argument form.
	local c = Mine.center(Config)
	local base = worldPos(plr, c, 0, SPAWN_CELL_Z)
	local at = Vector3.new(base.X, standY(0), base.Z)
	return CFrame.new(at, at + Vector3.new(0, 0, 1))
end

--============================================================================== parts

local swing -- forward declaration (the ClickDetector handler needs it)
-- Forward-declared for the same reason: sellHaul is built with the world, well before the state
-- pusher exists, and the headless check caught what happens without this — the SELL pad DID sell
-- your haul and then never told the client, so the cash readout and the backpack bar both sat
-- there unchanged and the only reasonable thing a player could conclude was that it was broken.
local pushState

local function tintOf(cell): Color3
	local rgb = Ore.color(Config, cell.ore)
	if cell.kind == "bedrock" then
		return Color3.fromRGB(26, 24, 30)
	end
	if cell.ore == 0 then
		-- A per-cell jitter drawn from the cell's OWN hash, so a wall of stone is not one flat
		-- colour and the jitter is identical for everyone looking at the same block.
		local j = math.floor(Mine.unit(0, cell.x, cell.y, cell.z, 91) * 22) - 11
		return Color3.fromRGB(
			math.clamp(rgb[1] + j, 0, 255),
			math.clamp(rgb[2] + j, 0, 255),
			math.clamp(rgb[3] + j, 0, 255)
		)
	end
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- One cell -> one Part. The pure generator owns every number; this owns every engine call.
local function makeCellPart(plr: Player, cell): BasePart
	local folder = shaftFolders[plr]
	local s = Config.Mine.CellSize
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = true
	part.CanQuery = true
	part.CastShadow = false -- a few hundred shadow casters per player is not worth the frame time
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local size = Vector3.new(s, s, s)
	local pos = worldPos(plr, cell.x, cell.y, cell.z)
	if cell.kind == "bedrock" and cell.y == 0 then
		-- The surface rim. One cell is 6 studs and a Roblox jump clears 7.2, so a one-cell lip
		-- would let a player hop out of the mine onto the top of the world.
		size = Vector3.new(s, s * RIM_MULT, s)
		pos += Vector3.new(0, s * (RIM_MULT - 1) / 2, 0)
	end
	part.Size = size
	part.Position = pos
	part.Color = tintOf(cell)

	if cell.kind == "bedrock" then
		part.Material = Enum.Material.Basalt
		part.Name = "Bedrock_" .. plr.UserId .. "_" .. cell.key
	elseif cell.ore > 0 then
		-- A glowing translucent ore cube is the thing you are hunting for in a dark shaft, and
		-- Neon blooms under the Horror preset at zero light cost.
		part.Material = Enum.Material.Neon
		part.Transparency = 0.25
		part.Name = "Ore_" .. plr.UserId .. "_" .. cell.key
	else
		part.Material = Enum.Material.Slate
		part.Name = "Rock_" .. plr.UserId .. "_" .. cell.key
	end

	part:SetAttribute("CellKey", cell.key)
	part:SetAttribute("Ore", cell.ore)
	part:SetAttribute("Layer", cell.y)
	part:SetAttribute("Owner", plr.UserId)

	-- A ClickDetector goes on anything a swing can be aimed at. The bedrock FLOOR gets one too,
	-- so the depth wall can explain itself instead of being a rock that ignores you; the ring
	-- does not, because 32 more detectors per layer buys nothing.
	local clickable = cell.breakable or (cell.kind == "bedrock" and cell.y > worlds[plr].maxLayer)
	if clickable then
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = Config.Mine.ReachStuds
		cd.Parent = part
		cd.MouseClick:Connect(function(clicker)
			if clicker ~= plr then return end -- your shaft, your swings
			swing(plr, cell.key)
		end)
	end

	-- Gold and better light their own pocket. Copper and iron do not: ~25% of every exposed
	-- face carries ore, and a PointLight on each of those is a light budget nobody can pay.
	if cell.ore >= 3 then
		Fx.attachGlow(part, tintOf(cell), 1.6, 14 + 2 * cell.ore)
	end

	-- PARENT LAST, with the ClickDetector already inside, so the block never exists in the
	-- world for a frame without the thing that makes it minable. And it is parented AT ALL:
	-- an unparented Instance raises nothing, warns nothing, and returns a perfectly good Part.
	part.Parent = folder

	cellParts[plr][cell.key] = part
	cellDefs[plr][cell.key] = cell
	cellHp[plr][cell.key] = cell.hp
	return part
end

--============================================================================== the build pump

-- ONE SWING MUST COST ONE FRAME'S WORTH OF WORK, WHATEVER IS BEHIND THE WALL.
--
-- Config.Mine.RevealBudget bounds the AIR cells a single break may flood through. It does not
-- bound the SOLID list that comes out of that flood, and the solid list is what costs: every
-- entry is an Instance.new("Part"), a ClickDetector, four SetAttribute calls and a signal
-- connection. Measured against the real modules, breaking into the 144-cell cave in a rebirth-0
-- shaft produced 334 of those, and the largest void at rebirth 24 produced 3031 — all of them
-- built synchronously inside the ClickDetector handler, so the frame the README sells as the
-- game's best moment ("a natural cave void that opens up all at once") was the frame the whole
-- server froze, every other miner in it included.
--
-- So the reveal now hands its solids to this queue, and the queue is drained PartsPerFrame at a
-- time. That bounds the per-frame cost by a CONSTANT rather than by the size of the cave, which
-- is the part that matters: no seed, no rebirth and no lucky void can push it back up. The order
-- is the flood's own breadth-first order, so the faces closest to the player — the floor they
-- are standing on, the walls beside them — are always in the first batch.
local function drainBuild(budget: number): number
	local made = 0
	for plr, q in pairs(buildQueue) do
		if shaftFolders[plr] == nil or shaftFolders[plr] ~= q.folder or cellParts[plr] == nil then
			-- the player left, or rebirthed into a brand new cave: these cells are about a world
			-- that no longer exists
			buildQueue[plr] = nil
		else
			while q.head <= #q.cells do
				if made >= budget then return made end
				local s = q.cells[q.head]
				q.head += 1
				-- A cell can be built by another reveal, or dug out, between being queued and
				-- being built. Both are re-checked here rather than assumed.
				if not cellParts[plr][s.key] and not opened[plr][s.key] then
					makeCellPart(plr, s)
					made += 1
				end
			end
			buildQueue[plr] = nil
		end
	end
	return made
end

local pumping = false
local function pumpBuild()
	if pumping then return end
	pumping = true
	task.spawn(function()
		while true do
			-- The first batch runs in the caller's own frame, so a swing still puts the walls
			-- around the player up immediately; everything past the budget waits for a frame.
			if drainBuild(Config.Mine.PartsPerFrame) == 0 then break end
			task.wait()
		end
		pumping = false
	end)
end

local function enqueueBuild(plr: Player, cells)
	if #cells == 0 then return end
	local q = buildQueue[plr]
	if q == nil or q.folder ~= shaftFolders[plr] then
		q = { cells = {}, head = 1, folder = shaftFolders[plr] }
		buildQueue[plr] = q
	end
	for _, c in ipairs(cells) do q.cells[#q.cells + 1] = c end
	pumpBuild()
end

--============================================================================== opening cells

-- One place that records "this cell is now open", so the depth readout, the leaderboard figure
-- and the elevator's destination can never drift apart.
local function noteOpen(plr: Player, x: number, y: number, z: number)
	local p = profiles[plr]
	if not p then return end
	if y > p.depthLayer then p.depthLayer = y end
	if y > p.bestLayer then p.bestLayer = y end
	local d = deepestOpen[plr]
	if not d or y > d.y then deepestOpen[plr] = { x = x, y = y, z = z } end
end

-- Mark a cell open, then ask Mine what became visible and what became walkable. Returns the
-- solid cells that still need a Part; the caller decides whether to build them now or to hand
-- them to the pump above.
local function openCell(plr: Player, x: number, y: number, z: number): { any }
	local w = worlds[plr]
	local op = opened[plr]
	local k = Mine.key(x, y, z)
	op[k] = true

	-- AN OPENED CELL HOLDS NO PART, and this is the only place that can guarantee it. A swing
	-- destroys the block before it gets here, so this looks redundant — but the rejoin restore
	-- opens the elevator column WITHOUT breaking anything, and each of those cells is holding a
	-- Part that the reveal of the cell above it built moments earlier. Nothing removed them, so
	-- the "restored elevator shaft" a returning player got was 18 layers of solid rock, and
	-- DESCEND aimed them at the bottom of it.
	local standing = cellParts[plr][k]
	if standing then
		cellParts[plr][k] = nil
		cellDefs[plr][k] = nil
		cellHp[plr][k] = nil
		standing:Destroy()
	end

	noteOpen(plr, x, y, z)

	local r = Mine.reveal(Config, Ore, w, op, x, y, z)
	for _, a in ipairs(r.air) do
		-- Walking into a natural void counts: those cells are reachable from your own tunnel,
		-- which is exactly what "how deep did you get" means.
		op[a.key] = true
		noteOpen(plr, a.x, a.y, a.z)
	end
	if r.truncated then
		warn("[DeepVein] reveal budget exhausted for " .. plr.Name .. " at " .. Mine.key(x, y, z))
	end

	local todo = {}
	for _, s in ipairs(r.solids) do
		if not cellParts[plr][s.key] then todo[#todo + 1] = s end
	end
	return todo
end

--============================================================================== the shaft

local function sellHaul(plr: Player, quiet: boolean?)
	local p = profiles[plr]
	if not p then return 0 end
	local mult = Prestige.multiplier(Config, p.rebirths)
	local got = Economy.sell(p, Config, Ore, mult)
	if got > 0 then
		toast(plr, "💰 Sold your haul for $" .. got .. (mult > 1 and ("  (x" .. mult .. ")") or ""))
	elseif not quiet then
		toast(plr, "Nothing to sell — go dig some ore! ⛏️")
	end
	-- Push unconditionally. Both callers used to rely on doing this themselves and the SELL pad
	-- did not, so a pad click emptied your backpack into a cash counter that never moved.
	pushState(plr)
	return got
end

local function buildSellPad(plr: Player)
	local c = Mine.center(Config)
	local pad = Instance.new("Part")
	pad.Name = "SellPad_" .. plr.UserId
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanTouch = false
	pad.Size = Vector3.new(10, 1, 10)
	pad.Position = worldPos(plr, c, 0, 3) + Vector3.new(0, -Config.Mine.CellSize / 2 + 0.5, 0)
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(90, 220, 130)
	pad.Transparency = 0.15
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 32
	cd.Parent = pad
	cd.MouseClick:Connect(function(clicker)
		if clicker ~= plr then return end
		sellHaul(plr)
	end)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SellLabel"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(20, 40, 26)
	label.Text = "SELL"
	label.Parent = gui
	gui.Parent = pad
	pad.Parent = shaftFolders[plr]
	Fx.attachGlow(pad, Color3.fromRGB(90, 220, 130), 2, 30)
end

-- A LANDING THAT CANNOT BE DUG AWAY.
--
-- SURFACE is the button that also sells your haul, so it is the button a player presses more
-- than any other, and it teleports to a FIXED point at the mouth. The floor under that point was
-- ordinary breakable rock, all the way down to bedrock — and digging straight down from where
-- you are standing is the most natural first move in a mining game, so the spawn column is the
-- first thing a player removes. Every SURFACE press after that dropped them straight back down
-- the hole they had just dug (measured: 13 layers, 78 studs, and the drop only ends at the
-- bedrock floor 150 studs down). The SELL pad does not catch them either; it is one cell south.
--
-- The fix is not a cleverer destination, it is a destination that is guaranteed to have ground.
-- This deck is an anchored slab filling the top stud of the cell below the landing point, with
-- no ClickDetector and no cell of its own — nothing in the game can aim a swing at it. While the
-- rock under the spawn is intact the deck is buried inside it and invisible; the moment that
-- rock is mined out, the deck is the ledge that is left standing.
local function buildSurfaceDeck(plr: Player)
	local c = Mine.center(Config)
	local s = Config.Mine.CellSize
	local deck = Instance.new("Part")
	deck.Name = "SurfaceDeck_" .. plr.UserId
	deck.Anchored = true
	deck.CanCollide = true
	deck.CanTouch = false
	deck.CanQuery = true
	deck.CastShadow = false
	deck.TopSurface = Enum.SurfaceType.Smooth
	deck.BottomSurface = Enum.SurfaceType.Smooth
	deck.Size = Vector3.new(s, 1, s)
	-- Top face flush with the mouth floor, Mine.floorY(Config, 0): the same surface the spawn
	-- height is measured from, so standing on the deck and standing on the rock are the same
	-- thing to a character.
	deck.Position = worldPos(plr, c, 0, SPAWN_CELL_Z) + Vector3.new(0, -s / 2 - 0.5, 0)
	deck.Material = Enum.Material.DiamondPlate
	deck.Color = Color3.fromRGB(118, 124, 136)
	deck.Parent = shaftFolders[plr]
end

local function buildShaft(plr: Player)
	local idx = shaftIndex[plr]
	local p = profiles[plr]
	if idx == nil or p == nil then return end

	local folder = Instance.new("Folder")
	folder.Name = "Shaft_" .. idx
	folder.Parent = shaftsFolder
	shaftFolders[plr] = folder

	worlds[plr] = Mine.world(Config, p.rebirths)
	opened[plr] = {}
	cellParts[plr] = {}
	cellDefs[plr] = {}
	cellHp[plr] = {}
	deepestOpen[plr] = { x = Mine.center(Config), y = 0, z = Mine.center(Config) }

	-- The mouth: one flood from its centre opens the whole 7x7 surface room and builds the rim
	-- and the floor a player lands on. This one is built OUTRIGHT rather than pumped — it is a
	-- fixed 113 cells at every rebirth, bounded by the grid rather than by the cave, and the
	-- count below has to be able to see all of them.
	local c = Mine.center(Config)
	local made = 0
	for _, s in ipairs(openCell(plr, c, 0, c)) do
		if not cellParts[plr][s.key] then
			makeCellPart(plr, s)
			made += 1
		end
	end
	buildSellPad(plr)
	buildSurfaceDeck(plr)

	-- ASK THE FOLDER. Not the counter next to the build loop — that is the same arithmetic on
	-- both sides of the comparison and can never disagree with itself. The only question that
	-- catches an unparented Instance is how many parts actually landed in the world.
	local landed = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then landed += 1 end
	end
	assert(landed >= made,
		"[DeepVein] shaft build put " .. landed .. " parts in " .. folder.Name
			.. ", wanted at least " .. made)

	-- Restore the elevator shaft down to the depth this player had already reached. Their side
	-- tunnels are not saved (see README); the column that makes the depth reachable again is.
	if p.depthLayer > 0 then
		task.spawn(function()
			for _, cellPos in ipairs(Mine.column(Config, worlds[plr], p.depthLayer)) do
				if shaftFolders[plr] ~= folder then return end -- the player left mid-restore
				-- One column cell per frame, and the parts it exposes go to the pump. The single
				-- worst cell of a rebirth-0 restore exposes 361 faces on its own; the old
				-- "yield every 40" counted between openCell calls, never inside one.
				enqueueBuild(plr, openCell(plr, cellPos.x, cellPos.y, cellPos.z))
				task.wait()
			end
		end)
	end
end

local function teardownShaft(plr: Player)
	local folder = shaftFolders[plr]
	shaftFolders[plr] = nil
	if folder then folder:Destroy() end -- one Destroy takes the entire shaft; nothing leaks
	buildQueue[plr] = nil -- solids still queued are about a cave that no longer exists
	cellParts[plr] = nil
	cellDefs[plr] = nil
	cellHp[plr] = nil
	opened[plr] = nil
	worlds[plr] = nil
	deepestOpen[plr] = nil
end

--============================================================================== state push

pushState = function(plr: Player)
	local p = profiles[plr]
	if not p then return end
	local ec = Config.Economy

	-- Integer keys go over the wire as strings on purpose: the client indexes them by string and
	-- never has to care whether the transport preserved the key type.
	local inv = {}
	for tier, count in pairs(p.inventory) do
		inv[tostring(tier)] = count
	end

	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local depthValue = ls:FindFirstChild("Depth")
		local cashValue = ls:FindFirstChild("Cash")
		if depthValue then (depthValue :: IntValue).Value = math.floor(Mine.depthStuds(Config, p.bestLayer)) end
		if cashValue then (cashValue :: IntValue).Value = math.floor(p.cash) end
	end

	local mult = Prestige.multiplier(Config, p.rebirths)
	StateEvent:FireClient(plr, {
		cash = math.floor(p.cash),
		totalCash = math.floor(p.totalCash),
		inventory = inv,
		carried = Economy.carried(p),
		capacity = Economy.backpackCapacity(Config, p.backpackLevel),
		haulValue = Economy.haulValue(Config, Ore, p.inventory, mult),

		pickTier = p.pickTier,
		pickName = Economy.pickaxeName(Config, p.pickTier),
		pickPower = Economy.swingPower(Config, p.pickTier),
		pickCost = Economy.nextPickaxeCost(Config, p.pickTier),
		pickMax = ec.Pickaxe.MaxTier,

		backpackLevel = p.backpackLevel,
		backpackCost = (p.backpackLevel < ec.Backpack.MaxLevel)
			and Economy.backpackCost(Config, p.backpackLevel) or nil,
		lampLevel = p.lampLevel,
		lampRadius = Economy.lampRadius(Config, p.lampLevel),
		lampCost = (p.lampLevel < ec.Lamp.MaxLevel) and Economy.lampCost(Config, p.lampLevel) or nil,

		rebirths = p.rebirths,
		mult = mult,
		rebirthCost = Prestige.requirement(Config, p.rebirths),
		rebirthProgress = Prestige.progress(p, Config),
		canRebirth = (Prestige.canRebirth(p, Config)),

		depth = math.floor(Mine.depthStuds(Config, p.depthLayer)),
		bestDepth = math.floor(Mine.depthStuds(Config, p.bestLayer)),
		maxDepth = math.floor(Mine.depthStuds(Config, worlds[plr] and worlds[plr].maxLayer or 0)),
		canSave = p.canSave,
	})
end

--============================================================================== swinging

swing = function(plr: Player, cellKey: string)
	local p = profiles[plr]
	if not p or not cellDefs[plr] then return end
	local cell = cellDefs[plr][cellKey]
	local part = cellParts[plr][cellKey]
	if not cell or not part then return end

	-- Rate limit. Server-side, because the ClickDetector fires as fast as the client can click.
	-- `tick()` rather than `os.clock()`: os.clock is CPU time, which barely moves in a headless
	-- run, so a cooldown built on it would refuse every swing the emulator ever makes and the
	-- entire dig loop would be untestable. tick() is the clock the harness advances.
	local now = tick()
	local last = lastSwing[plr]
	if last and (now - last) < Config.Mine.SwingCooldown then return end
	lastSwing[plr] = now

	if not cell.breakable then
		toast(plr, "🪨 Bedrock. This is as deep as this cave goes — REBIRTH to open a deeper one!")
		return
	end

	-- Refuse the swing BEFORE grinding a block whose ore would not fit. Grinding a vein down to
	-- nothing and then being told the ore was dropped is the sort of silent loss that reads as
	-- a bug rather than a rule.
	if Ore.isOre(Config, cell.ore) and Economy.spaceLeft(p, Config) <= 0 then
		toast(plr, "🎒 Backpack full — take the elevator up and SELL before you mine that vein!")
		return
	end

	local power = Economy.swingPower(Config, p.pickTier)
	local left = (cellHp[plr][cellKey] or cell.hp) - power
	if left > 0 then
		cellHp[plr][cellKey] = left
		-- Visible damage: the block shrinks toward its centre. No new instances, no tween, and
		-- readable from across a dark room.
		local frac = 0.7 + 0.3 * (left / math.max(1, cell.hp))
		local s = Config.Mine.CellSize
		part.Size = Vector3.new(s * frac, s * frac, s * frac)
		return
	end

	-- Broken.
	local yield = Ore.yieldOf(Config, cell.ore)
	if yield > 0 then
		local took = Economy.addOre(p, Config, cell.ore, yield)
		if took > 0 then
			toast(plr, "⛏️ +" .. took .. " " .. Ore.name(Config, cell.ore))
		else
			toast(plr, "🎒 Backpack full — that " .. Ore.name(Config, cell.ore) .. " was lost!")
		end
	end

	cellParts[plr][cellKey] = nil
	cellDefs[plr][cellKey] = nil
	cellHp[plr][cellKey] = nil
	part:Destroy()

	enqueueBuild(plr, openCell(plr, cell.x, cell.y, cell.z))
	pushState(plr)
end

--============================================================================== shop / elevator

BuyEvent.OnServerEvent:Connect(function(plr, kind)
	local p = profiles[plr]
	if not p then return end
	local ok, reason = false, "unknown"
	if kind == "pickaxe" then
		ok, reason = Economy.buyPickaxe(p, Config)
	elseif kind == "backpack" then
		ok, reason = Economy.buyBackpack(p, Config)
	elseif kind == "lamp" then
		ok, reason = Economy.buyLamp(p, Config)
		if ok and lampOf[plr] then
			lampOf[plr].Range = Economy.lampRadius(Config, p.lampLevel)
		end
	end
	if ok then
		toast(plr, "✅ Upgraded!")
		pushState(plr)
	elseif reason == "poor" then
		toast(plr, "💸 Not enough cash for that upgrade.")
	elseif reason == "max" then
		toast(plr, "⭐ That one is already maxed out.")
	end
end)

ElevatorEvent.OnServerEvent:Connect(function(plr, dir)
	local p = profiles[plr]
	if not p then return end
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		toast(plr, "The elevator needs you to be standing somewhere first.")
		return
	end
	if dir == "up" then
		(hrp :: BasePart).CFrame = spawnCFrame(plr)
		sellHaul(plr, true) -- hauling up IS selling; that is the whole loop in one button
		pushState(plr)
	elseif dir == "down" then
		local d = deepestOpen[plr]
		if not d or d.y <= 0 then
			toast(plr, "⛏️ Nothing dug yet — break the floor to start your shaft!")
			return
		end
		local at = worldPos(plr, d.x, d.y, d.z)
		at = Vector3.new(at.X, standY(d.y), at.Z)
		;(hrp :: BasePart).CFrame = CFrame.new(at)
		toast(plr, "🛗 Down to " .. math.floor(Mine.depthStuds(Config, d.y)) .. " studs.")
	end
end)

RebirthEvent.OnServerEvent:Connect(function(plr)
	local p = profiles[plr]
	if not p then return end

	-- Snapshot BEFORE applying. Rebirth is the one irreversible action in the game, so it is
	-- granted only inside an atomic flush: if the write did not persist, put everything back
	-- rather than leave a player who paid 30000 and got nothing after a server restart.
	local before = {
		cash = p.cash, inventory = p.inventory, pickTier = p.pickTier,
		backpackLevel = p.backpackLevel, lampLevel = p.lampLevel,
		rebirths = p.rebirths, depthLayer = p.depthLayer,
	}

	local ok, reason = Prestige.apply(p, Config)
	if not ok then
		if reason == "max" then
			toast(plr, "⭐ You have every rebirth there is. Nothing left to prove.")
		else
			toast(plr, "♻️ Rebirth needs $" .. Prestige.requirement(Config, p.rebirths)
				.. " in hand — you have $" .. math.floor(p.cash) .. ".")
		end
		return
	end

	if p.canSave and not saveProfile(plr, false) then
		for k, v in pairs(before) do p[k] = v end
		toast(plr, "⚠️ Could not save the rebirth — nothing was spent. Try again in a moment.")
		pushState(plr)
		return
	end

	-- A new cave, from a new seed, with the wall further down. This is the payoff.
	teardownShaft(plr)
	buildShaft(plr)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then (hrp :: BasePart).CFrame = spawnCFrame(plr) end
	if lampOf[plr] then lampOf[plr].Range = Economy.lampRadius(Config, p.lampLevel) end
	toast(plr, "♻️ REBIRTH " .. p.rebirths .. "! x" .. Prestige.multiplier(Config, p.rebirths)
		.. " cash, and a brand new cave " .. math.floor(Mine.depthStuds(Config, worlds[plr].maxLayer)) .. " studs deep.")
	pushState(plr)
end)

--============================================================================== leaderboard

local function refreshLeaderboard()
	if not orderedLB then return end
	local ok, page = pcall(function() return orderedLB:GetSortedAsync(false, 10) end)
	if not ok or not page then return end
	local top = {}
	for _, e in ipairs(page:GetCurrentPage()) do
		top[#top + 1] = { userId = tonumber((string.gsub(e.key, "^u_", ""))), depth = e.value }
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		LeaderboardEvent:FireClient(plr, top)
	end
end

--============================================================================== lifecycle

local function attachLamp(plr: Player, char: Model)
	local p = profiles[plr]
	if not p then return end
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end
	local old = lampOf[plr]
	if old then old:Destroy() end
	-- The mine has no sun. Without this the player is in a black box holding a pickaxe.
	local light = Fx.attachGlow(hrp :: BasePart, Color3.fromRGB(255, 226, 170), 2.2,
		Economy.lampRadius(Config, p.lampLevel))
	light.Name = "MinerLamp"
	lampOf[plr] = light
end

local function onPlayerAdded(plr: Player)
	profiles[plr] = loadProfile(plr)

	-- loadProfile YIELDS on UpdateAsync, and leaving during that yield is a thing real players do
	-- constantly. PlayerRemoving fires while every table below is still empty, frees nothing, and
	-- then this function resumes and builds an entire shaft for somebody who is gone — a leaked
	-- shaft index and a live folder of hundreds of parts, per occurrence, for the life of the
	-- server. Found by review in the sibling game; the emulator cannot reproduce it, because its
	-- DataStore is synchronous and never yields.
	if plr.Parent == nil then
		profiles[plr] = nil
		return
	end

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local depthValue = Instance.new("IntValue")
	depthValue.Name = "Depth"
	depthValue.Parent = ls
	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Parent = ls
	ls.Parent = plr

	claimShaft(plr)
	buildShaft(plr)

	local function place(char: Model)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if hrp then (hrp :: BasePart).CFrame = spawnCFrame(plr) end
		attachLamp(plr, char)
	end
	plr.CharacterAdded:Connect(place)
	if plr.Character then place(plr.Character) end

	pushState(plr)
end

local function onPlayerRemoving(plr: Player)
	saveProfile(plr, true)
	-- Destroy the shaft FIRST, then free the index: a join in the same frame must never be able
	-- to claim a name that is still taken.
	teardownShaft(plr)
	local idx = shaftIndex[plr]
	shaftIndex[plr] = nil
	if idx ~= nil then usedShafts[idx] = nil end
	profiles[plr] = nil
	lastSwing[plr] = nil
	lampOf[plr] = nil
	buildQueue[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr, true) end
end)

-- Autosave (also renews the session lock).
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr, false) end
	end
end)

task.spawn(function()
	while true do
		refreshLeaderboard()
		task.wait(30)
	end
end)

print("[DeepVein] Deep Vein lastet. WorldSeed=" .. Config.WorldSeed
	.. " · shaft " .. Config.Mine.GridW .. "x" .. Config.Mine.GridW
	.. " · depth wall " .. Mine.maxLayer(Config, 0) .. " layers")
