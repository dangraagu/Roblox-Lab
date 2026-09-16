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
		-- Cash EARNED this run. Only ever goes up; spending does not touch it. This is what the
		-- rebirth gate reads, so a player can never shop themselves out of a rebirth in a cave
		-- that does not refill. See Economy.sell and Prestige.canRebirth.
		runEarned = 0,
		inventory = {}, -- [oreTier] = units carried
		pickTier = 1,
		backpackLevel = 0,
		lampLevel = 0,
		rebirths = 0,
		depthLayer = 0, -- deepest LAYER opened this run (studs are display only)
		bestLayer = 0, -- deepest LAYER ever, across every rebirth — the leaderboard
		-- THE CAVE ITSELF, packed one bit per cell (Mine.packOpened). Without it a rejoining
		-- player found every cell they had ever mined standing again, ore included, and could
		-- sell the same shaft over and over just by leaving and coming back.
		openedBits = nil,
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
				-- CASH IN HAND IS A LOWER BOUND ON WHAT THIS RUN EARNED, always: the only source of
				-- cash is a sale, a sale banks the same amount of earnings, and rebirth zeroes
				-- both together. So a profile written before runEarned existed is migrated to the
				-- cash it is holding rather than to zero — which would otherwise delete a
				-- returning player's rebirth progress the first time they logged in after this
				-- change. Economy.spec asserts the invariant the migration leans on.
				p.runEarned = math.max(tonumber(d.runEarned) or 0, tonumber(d.cash) or 0)
				p.openedBits = type(d.openedBits) == "string" and d.openedBits or nil
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

-- Forward-declared: packing the cave needs the live per-player tables, which are built with the
-- world further down, while saveProfile belongs up here with the rest of the DataStore code.
local openedBitsOf

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
				runEarned = p.runEarned,
				pickTier = p.pickTier, backpackLevel = p.backpackLevel, lampLevel = p.lampLevel,
				rebirths = p.rebirths, depthLayer = p.depthLayer, bestLayer = p.bestLayer,
				-- Packed HERE rather than maintained on every swing: the live `opened` table is
				-- the authority, and re-deriving the string at the write is the only arrangement
				-- in which the two cannot drift. A completely excavated rebirth-0 shaft is 336
				-- characters; the deepest wall in the game is 4 239.
				openedBits = openedBitsOf(plr, p),
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

-- SOMEWHERE TO STAND FOR THE FRAME BEFORE THE GAME TAKES OVER.
--
-- Every player is CFramed into their own shaft by `place`, but that write can only land AFTER the
-- engine's own placement — measured in Studio, the engine parents and positions the character one
-- frame after CharacterAdded fires, so `place` waits for it (see the long note there). Which means
-- this pad is not a nicety for a frame nobody sees: it is where the engine actually puts every
-- miner, every join and every respawn, for the one frame before the game moves them.
--
-- With no SpawnLocation at all Roblox picks the spot itself — above the highest ground over the
-- world origin, which in this game is the middle of the FIRST player's mouth, six studs above a
-- hole. One anchored pad, in the clear west of shaft 0 and outside every shaft's 54-stud
-- footprint, makes that frame boring instead of a fall down a stranger's dig.
--
-- It is parented to the workspace and NOT to Shafts, deliberately: everything under Shafts is
-- per-player and is destroyed when its owner leaves, and this is the one piece of world that
-- belongs to nobody.
local function buildSpawnPad()
	local pad = Instance.new("SpawnLocation")
	pad.Name = "MinersRest"
	pad.Anchored = true
	pad.CanCollide = true
	pad.Neutral = true
	pad.Duration = 0 -- no ForceField: there is nothing to be shot by
	pad.Size = Vector3.new(16, 1, 16)
	pad.Position = Vector3.new(-SHAFT_SPACING / 2, -0.5, 0)
	pad.Material = Enum.Material.Metal
	pad.Color = Color3.fromRGB(96, 104, 118)
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Parent = workspace
	return pad
end
buildSpawnPad()

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
local bandOf = {} -- [player] = { lo, hi, centre } — the LAYERS that currently hold Parts

-- THE CAVE, AS A STRING. Packed from the live `opened` table at every write.
--
-- The guard is not paranoia. Rebirth is an ATOMIC FLUSH — snapshot, Prestige.apply, saveProfile,
-- roll back if the write did not land — so saveProfile runs while `worlds[plr]` and `opened[plr]`
-- still describe the cave that was just paid for and thrown away, and `p.rebirths` already names
-- the new one. Packing then would write the old cave's dug-out cells under the new rebirth's
-- number, and unpacking those against a deeper world maps them onto cells that mean nothing:
-- a brand new cave arriving pre-drilled with holes in the wrong places.
openedBitsOf = function(plr: Player, p: any): string?
	local w = worlds[plr]
	local op = opened[plr]
	if w == nil or op == nil or w.rebirths ~= (p.rebirths or 0) then
		return p.openedBits -- no live shaft for THIS rebirth: keep whatever the profile carries
	end
	local bits = Mine.packOpened(Config, w, op)
	p.openedBits = bits
	return bits
end

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

local BEDROCK_COLOR = Color3.fromRGB(26, 24, 30)

local function tintOf(cell): Color3
	local rgb = Ore.color(Config, cell.ore)
	if cell.kind == "bedrock" then
		return BEDROCK_COLOR
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

-- Visible damage: the block shrinks toward its centre as it loses hit points. No new instances,
-- no tween, readable from across a dark room — and ONE function, because the swing that damages a
-- block and the streamer that rebuilds a damaged one have to agree about how it looks.
local function damageScale(left: number, hp: number): number
	return 0.7 + 0.3 * (math.max(0, left) / math.max(1, hp))
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

	-- A HALF-BROKEN BLOCK COMES BACK HALF BROKEN. The streamer destroys Parts outside the miner's
	-- band and rebuilds them from the generator when they come back — and the generator does not
	-- know about damage. It keeps the hit points instead (see setBand), and this is where they are
	-- honoured: without it, walking away and returning heals every block the player was part-way
	-- through, which is a swing they paid for and did not get.
	local hp = cellHp[plr][cell.key]
	local scale = (hp ~= nil and hp < cell.hp) and damageScale(hp, cell.hp) or 1
	part.Size = Vector3.new(s * scale, s * scale, s * scale)
	part.Position = worldPos(plr, cell.x, cell.y, cell.z)
	part.Color = tintOf(cell)

	if cell.kind == "bedrock" then
		-- Should be unreachable: buildable() refuses bedrock, because the ring and the floor are
		-- Mine.shell's five slabs now. Kept so a future caller that forgets gets a visible block
		-- rather than a mystery.
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

	-- A ClickDetector goes on anything a swing can be aimed at. That is now exactly the breakable
	-- cells: the depth wall still explains itself when you hit it, but it is the floor SLAB that
	-- carries that detector (see buildShell), not 49 separate bedrock cubes.
	if cell.breakable then
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
	cellHp[plr][cell.key] = hp or cell.hp
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
-- Forward-declared: the drain has to ask it, and it is defined with the rest of the streaming
-- code below, which needs makeCellPart and enqueueBuild first.
local buildable

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
				-- Two reveals in the same frame can queue the same face twice, so the second one
				-- finds the Part already standing. (An `opened` re-check used to sit here as
				-- well, with a comment claiming it caught a cell dug out between queueing and
				-- building. It cannot happen — a queued cell has no Part yet, so there is nothing
				-- to click — and a mutation sweep proved the branch dead. Gone; what would catch
				-- a real regression is the headless gate's "no Part stands in an opened cell".)
				-- ONE BAD CELL COSTS ONE CELL. Before the pump existed this loop ran inline in the
				-- click handler, so an error building a face cost exactly one swing; moving it
				-- into a shared pump made the same error cost every future Part for every player
				-- in the server. Per-cell, so the rest of the cave still goes up, and pumpBuild
				-- wraps the whole drain as well so the guard flag always comes back down.
				-- …AND A QUEUED CELL WHOSE LAYER HAS SINCE FALLEN OUT OF THE MINER'S BAND IS
				-- DROPPED rather than built. Without this, a big reveal followed by walking away
				-- builds the whole thing anyway, one frame behind the unload that was supposed to
				-- have prevented it.
				if not cellParts[plr][s.key] and buildable(plr, s) then
					local built, err = pcall(makeCellPart, plr, s)
					if built then
						made += 1
					else
						warn("[DeepVein] could not build cell " .. tostring(s.key) .. ": " .. tostring(err))
					end
				end
			end
			buildQueue[plr] = nil
		end
	end
	return made
end

-- ONE PUMP AT A TIME, ON A LEASE RATHER THAN A LATCH.
--
-- The guard here is server-wide, not per-player: every call site returns early while a pump is
-- believed to be running. As a plain boolean that made ONE thrown error permanent — the spawned
-- thread died with the flag stuck up, and from that instant no Part was ever built again for ANY
-- player in the server. The world silently stopped growing, nothing surfaced a second time, and
-- the only symptom was that swinging stopped revealing anything. Before the pump existed the same
-- error cost exactly one swing, because the building happened inline in the click handler.
--
-- Two things fix it, and they cover different failures:
--   * drainBuild pcalls each cell, so a Part that will not build costs that Part and nothing else;
--   * this lease covers everything else. A live pump renews it every frame; a dead one stops
--     renewing and the next enqueue takes over a second later. There is no failure — known,
--     unknown, or thrown by the error handler itself — that can wedge it permanently, which a
--     pcall around the loop could not promise, because a pcall only catches what it wraps.
-- Two pumps briefly overlapping is harmless: they share one queue, `head` only moves forward, and
-- a cell that already has a Part is skipped.
local PUMP_LEASE = 1 -- seconds a running pump's claim stays good without being renewed
local pumpLease = 0
local function pumpBuild()
	if tick() < pumpLease then return end
	pumpLease = tick() + PUMP_LEASE
	task.spawn(function()
		while true do
			pumpLease = tick() + PUMP_LEASE
			-- The first batch runs in the caller's own frame, so a swing still puts the walls
			-- around the player up immediately; everything past the budget waits for a frame.
			if drainBuild(Config.Mine.PartsPerFrame) == 0 then break end
			task.wait()
		end
		pumpLease = 0 -- finished cleanly: the next enqueue starts immediately, not in a second
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

--=============================================================== streaming: the shaft is bounded
--
-- THE COST THIS FIXES, MEASURED. Nothing used to unload, and the cave is saved, so a veteran's
-- whole excavation was rebuilt on every join and then kept for the session. At the deepest wall
-- that is 10 097 Parts for a fully excavated shaft (REVIEW-3's figure — and every one of them
-- bedrock), 11 960 for the ordinary "dig straight down to the wall", and 19 115 for a lattice dig,
-- which is what a strip mine is. Per player. On a shared server, times however many are in it.
--
-- Two bounds replace it, and they cover different halves of that number:
--   * THE BOX IS GEOMETRY, NOT CELLS. The bedrock ring and the bedrock floor never change and are
--     never breakable, so they are Mine.shell's five slabs instead of 10 097 cubes. Exact: same
--     volume, same collision, no policy, nothing to tune, and it cannot regress because the box
--     does not move. That is the whole of the fully excavated case.
--   * THE ROCK FACES LIVE IN A DEPTH BAND. A Part exists only while its layer is within
--     Config.Mine.StreamLayers of the miner; the rest are destroyed and rebuilt from `opened` when
--     the miner comes back. `opened` IS the cave and none of this touches it — the Parts were
--     always derived from it (that is what makes the restore possible at all), so unloading one is
--     forgetting a rendering, not forgetting a dig.
--
-- The band width is set by the LIGHT rather than by taste: the mine has no sun, and the best lamp
-- in the game reaches 74 studs. 16 layers is 96. Nothing a player could have seen is ever missing.

-- Should this cell hold a Part right now? ONE predicate, used by every path that builds one, so a
-- new caller cannot quietly opt out of either bound.
buildable = function(plr: Player, cell): boolean
	if cell.kind == "bedrock" then return false end -- the shell owns the box
	local b = bandOf[plr]
	if b == nil then return true end
	return cell.y >= b.lo and cell.y <= b.hi
end

local function keepOnly(cells, plr: Player)
	local out = {}
	for _, c in ipairs(cells) do
		if buildable(plr, c) and not cellParts[plr][c.key] then out[#out + 1] = c end
	end
	return out
end

-- Which layer the miner is standing in. The character is the honest answer — a player has to be
-- within Config.Mine.ReachStuds (26 studs, about four layers) of a block to swing at it, so the
-- band can be centred on them and nothing they can reach is ever outside it. With no character
-- yet (the frame or two before CharacterAdded lands) that is the mouth, which is where the game
-- puts them anyway.
local function minerLayer(plr: Player): number
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp == nil then return 0 end
	return Mine.layerOfY(Config, (hrp :: BasePart).Position.Y)
end

-- Move the band to `centre` and make the world match it: destroy every Part that fell out, queue
-- every face that fell in. Returns how many it destroyed.
local function setBand(plr: Player, centre: number): number
	local w, op = worlds[plr], opened[plr]
	if w == nil or op == nil or cellParts[plr] == nil then return 0 end
	local k = Config.Mine.StreamLayers
	local lo = math.max(0, centre - k)
	local hi = math.min(w.maxLayer + 1, centre + k)
	bandOf[plr] = { lo = lo, hi = hi, centre = centre }

	-- OUT. Clearing the key of the entry `next` is currently on is the one mutation pairs()
	-- allows, which is why this can destroy in place instead of collecting first.
	local dropped = 0
	for key, part in pairs(cellParts[plr]) do
		local def = cellDefs[plr][key]
		if def == nil or def.y < lo or def.y > hi then
			cellParts[plr][key] = nil
			cellDefs[plr][key] = nil
			-- A HALF-BROKEN BLOCK KEEPS ITS DAMAGE. Everything else about a Part is re-derivable
			-- from the generator; the hit points a player has already knocked off it are not, and
			-- silently healing a block because the player walked away is a swing they paid for and
			-- did not get. Undamaged cells drop their entry, so this cannot grow without bound.
			if def ~= nil and (cellHp[plr][key] or def.hp) >= def.hp then cellHp[plr][key] = nil end
			part:Destroy()
			dropped += 1
		end
	end

	-- IN. Faces the miner can see from the space they have opened, inside the band alone — which
	-- is why Mine.faces takes one: asking for the whole excavation here would cost the excavation.
	enqueueBuild(plr, keepOnly(Mine.faces(Config, Ore, w, op, lo, hi), plr))
	return dropped
end

-- The periodic sweep. Hysteresis, or stepping down one cell re-derives the whole face set for no
-- change at all.
local function restream(plr: Player)
	local b = bandOf[plr]
	local at = minerLayer(plr)
	if b ~= nil and math.abs(at - b.centre) < Config.Mine.StreamHysteresis then return end
	setBand(plr, at)
end

-- A TELEPORT NEEDS GROUND BEFORE IT LANDS, NOT A FRAME LATER. DESCEND aims at the deepest cell the
-- player opened — an empty cell by definition — and what holds them up is whatever is under it. If
-- that has not been built yet they fall through it, and the only thing under a dug shaft is the
-- bedrock floor a hundred and fifty studs down. So the band moves first and the innermost layers
-- of it are built SYNCHRONOUSLY, before the CFrame is set. Bounded on purpose: two layers, not the
-- whole band, so this is one frame's work and not the freeze the pump exists to prevent.
-- …and it is narrowed to the LANDING COLUMN, not the whole layer band. Measured over every state
-- this game can reach, the widest two-layer band anywhere is 202 faces — three frames' work in one
-- frame, which is a hitch on every elevator press. What actually holds a miner up is the cell under
-- their feet and its neighbours, so only the 3x3 column around (cx, cz) is built here and the rest
-- of the band goes to the pump like everything else. That is at most 45 cells and measures at 12.
local function streamTo(plr: Player, layer: number, cx: number, cz: number): number
	local w, op = worlds[plr], opened[plr]
	if w == nil or op == nil then return 0 end
	setBand(plr, layer)
	local r = Config.Mine.StreamLandingLayers
	local made = 0
	for _, cell in ipairs(Mine.faces(Config, Ore, w, op,
		math.max(0, layer - r), math.min(w.maxLayer + 1, layer + r))) do
		if math.abs(cell.x - cx) <= 1 and math.abs(cell.z - cz) <= 1
			and buildable(plr, cell) and not cellParts[plr][cell.key] then
			if (pcall(makeCellPart, plr, cell)) then made += 1 end
		end
	end
	return made
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

	-- Only the faces that should hold a Part right now: bedrock is the shell's, and a face outside
	-- the miner's depth band is rebuilt from `opened` when they come back to it.
	return keepOnly(r.solids, plr)
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
-- This deck is an anchored slab inside the cell below the landing point, with no ClickDetector
-- and no cell of its own — nothing in the game can aim a swing at it. While the rock under the
-- spawn is intact the deck is buried inside it; the moment that rock is mined out, the deck is
-- the ledge that is left standing.
--
-- AND IT IS BURIED PROPERLY, WHICH THE FIRST VERSION WAS NOT. That one filled the top stud of the
-- cell with a full 6x6 footprint and its top face at y = 0 — the same plane and the same
-- rectangle as the top face of the breakable rock it was hiding inside. Two consequences, both at
-- the one tile the game points every new player at: opaque coplanar faces z-fight, and a mouse
-- ray aimed straight down resolves to a tie, so a click that landed on the deck was a silent
-- no-op on the first block a player ever tries to mine. Three things fix it, and the headless
-- gate asserts all three:
--   * one stud LOWER, so no face of the deck shares a plane with any face of the rock;
--   * inset on X and Z, so the four side faces do not either once the neighbouring floor is dug;
--   * CanQuery = false, so a click can never resolve to it at all.
-- The inset stays far under half a cell. This slab is the only ground the SURFACE button
-- guarantees, and its SIZE was asserted nowhere: the review shrank it to a 1x1 stud pillar under
-- a 6x6 cell and every one of the repo's 1797 assertions stayed green.
local DECK_DROP = 1.5 -- studs below the cell's own top-stud slab, so nothing is coplanar
local DECK_FOOTPRINT = 0.9 -- of a cell, on each of X and Z
local function buildSurfaceDeck(plr: Player)
	local c = Mine.center(Config)
	local s = Config.Mine.CellSize
	local deck = Instance.new("Part")
	deck.Name = "SurfaceDeck_" .. plr.UserId
	deck.Anchored = true
	deck.CanCollide = true
	deck.CanTouch = false
	deck.CanQuery = false
	deck.CastShadow = false
	deck.TopSurface = Enum.SurfaceType.Smooth
	deck.BottomSurface = Enum.SurfaceType.Smooth
	deck.Size = Vector3.new(s * DECK_FOOTPRINT, 1, s * DECK_FOOTPRINT)
	deck.Position = worldPos(plr, c, 0, SPAWN_CELL_Z) + Vector3.new(0, -s / 2 - DECK_DROP, 0)
	deck.Material = Enum.Material.DiamondPlate
	deck.Color = Color3.fromRGB(118, 124, 136)
	-- The landing this deck exists to hold up, published so a gate can find the column instead of
	-- writing the coordinate out a second time. A test that hard-codes the spawn cell goes red
	-- when the spawn MOVES — the one change that cannot break it — which is what happened to the
	-- headless check the first time round.
	deck:SetAttribute("LandingCell", Mine.key(c, 1, SPAWN_CELL_Z))
	deck.Parent = shaftFolders[plr]
end

-- THE BOX, AS FIVE PARTS INSTEAD OF TEN THOUSAND.
--
-- The bedrock ring and the bedrock floor were built cell by cell, one 6-stud cube each, and they
-- ARE the number REVIEW-3 left open: a fully excavated rebirth-24 shaft is 10 097 Parts and every
-- single one of them is ring (10 048) or floor (49). Not one is rock — excavate a shaft and there
-- is no rock left to have a face. So "cull the interior of solid rock" saves nothing here and a
-- distance stream only hides it; what removes it is noticing that an indestructible rectangular
-- tube and a flat floor are five slabs of geometry, and building those instead.
--
-- Same volume, same collision, same colour, and Mine.shell is asserted cell by cell against the
-- generator: every bedrock cell of the box is inside a slab, and no slab reaches into a cell a
-- player is supposed to be able to dig. The rim (RimCells) is part of the wall now rather than a
-- special case in the part factory — one cell is 6 studs and a Roblox jump clears 7.2.
local function buildShell(plr: Player)
	local folder = shaftFolders[plr]
	local origin = shaftOrigin(shaftIndex[plr] or 0)
	local made = 0
	for _, s in ipairs(Mine.shell(Config, worlds[plr])) do
		local part = Instance.new("Part")
		part.Name = s.name .. "_" .. plr.UserId
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.CanQuery = true
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(s.sx, s.sy, s.sz)
		part.Position = origin + Vector3.new(s.x, s.y, s.z)
		part.Material = Enum.Material.Basalt
		part.Color = BEDROCK_COLOR
		part:SetAttribute("Owner", plr.UserId)
		part:SetAttribute("Shell", s.kind)
		if s.kind == "floor" then
			-- THE DEPTH WALL HAS TO EXPLAIN ITSELF. A rock that silently ignores you is
			-- indistinguishable from a broken game, so the floor is clickable and toasts — the same
			-- message the 49 bedrock floor cubes used to carry between them, on one Part. Rate
			-- limited on the same clock as a swing, because that is the path this replaced and a
			-- ClickDetector fires as fast as a client can send.
			local cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = Config.Mine.ReachStuds
			cd.Parent = part
			cd.MouseClick:Connect(function(clicker)
				if clicker ~= plr then return end
				local now = tick()
				local last = lastSwing[plr]
				if last and (now - last) < Config.Mine.SwingCooldown then return end
				lastSwing[plr] = now
				toast(plr, "🪨 Bedrock. This is as deep as this cave goes — REBIRTH to open a deeper one!")
			end)
		end
		part.Parent = folder
		made += 1
	end
	return made
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
	-- The band starts at the mouth, which is where the player is put. Set BEFORE anything is
	-- built, so the mouth flood and the restore below are both filtered by it rather than
	-- building the whole shaft and having the first sweep tear most of it down again.
	bandOf[plr] = { lo = 0, hi = math.min(worlds[plr].maxLayer + 1, Config.Mine.StreamLayers),
		centre = 0 }

	-- The box: four walls and a floor, whatever the depth. Built first, so a corrupt save cannot
	-- cost a player the thing that stops them walking out of the world.
	buildShell(plr)

	-- The mouth: one flood from its centre opens the whole 7x7 surface room and builds the floor a
	-- player lands on. This one is built OUTRIGHT rather than pumped — it is a fixed 49 cells at
	-- every rebirth, bounded by the grid rather than by the cave, and the count below has to be
	-- able to see all of them.
	--
	-- It runs FIRST and unconditionally, before any saved cave is merged in, so a corrupt or
	-- truncated save can cost a player their tunnels but can never cost them the room they are
	-- about to be teleported into.
	local c = Mine.center(Config)
	local solids = openCell(plr, c, 0, c)

	-- THE SAVED CAVE. Every cell this player has ever dug out of THIS rebirth's shaft, restored
	-- before a single Part of it is built — which is what stops the mined-out ore standing there
	-- again. `Mine.faces` then answers for the whole set at once; a reveal cannot, because its
	-- flood deliberately refuses to walk through cells that are already open, and every cell of a
	-- restored cave is exactly that.
	local restored = Mine.unpackOpened(Config, worlds[plr], p.openedBits)
	local restoredCells = 0
	for k in pairs(restored) do
		opened[plr][k] = true
		restoredCells += 1
	end
	if restoredCells > 0 then
		-- BANDED. `opened` is restored WHOLE — it is the cave, and losing part of it would lose
		-- tunnels — but only the layers around where the player is about to stand get Parts. A
		-- veteran who left at the bottom of a 312-layer shaft comes back to the surface, so their
		-- band is the top of it; the rest is built by DESCEND, and it is built from `opened`, which
		-- is exactly where it came from in the first place.
		solids = Mine.faces(Config, Ore, worlds[plr], opened[plr], bandOf[plr].lo, bandOf[plr].hi)
		local deep = Mine.deepestOpened(opened[plr])
		if deep then
			deepestOpen[plr] = deep
			noteOpen(plr, deep.x, deep.y, deep.z)
		end
	end

	-- The first frame's worth is built outright so the returning player has floor and walls the
	-- instant they arrive; everything past it goes to the pump, at PartsPerFrame per frame, so a
	-- veteran with a thousand faces to rebuild does not freeze the server for everybody else.
	local made = 0
	local queued = {}
	for i, cell in ipairs(solids) do
		if not buildable(plr, cell) then
			-- bedrock: the shell is standing there already
		elseif i <= Config.Mine.PartsPerFrame or restoredCells == 0 then
			if not cellParts[plr][cell.key] then
				makeCellPart(plr, cell)
				made += 1
			end
		else
			queued[#queued + 1] = cell
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

	if #queued > 0 then
		enqueueBuild(plr, queued)
		print("[DeepVein] restored " .. restoredCells .. " dug cells for " .. plr.Name
			.. " (" .. made .. " faces up front, " .. #queued .. " queued)")
	end

	-- LEGACY ONLY. A profile written before the cave was saved — or one whose session never got
	-- to write — still has a depth number and nothing else, so it gets the centre elevator column
	-- back and nothing more. Any profile with a saved cave has already had it restored above,
	-- tunnels and all, and re-opening the column on top would be both redundant and a second
	-- source of truth for how deep this player is.
	if restoredCells == 0 and p.depthLayer > 0 then
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
	bandOf[plr] = nil
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
		-- The rebirth readouts are all quoted in EARNINGS, not in the wallet, because that is
		-- what the gate reads. A bar that fell every time a player bought something would be
		-- telling them the truth about a rule the game no longer has.
		earned = math.floor(p.runEarned or 0),
		rebirthCost = Prestige.requirement(Config, Ore, p.rebirths),
		rebirthProgress = Prestige.progress(p, Config, Ore),
		canRebirth = (Prestige.canRebirth(p, Config, Ore)),

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
		local frac = damageScale(left, cell.hp)
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
		-- Load the mouth BEFORE arriving in it, for the same reason DESCEND does: an elevator that
		-- lands you a frame before your floor exists is an elevator that drops you down your own
		-- shaft. The mouth is nearly always already loaded, so this is nearly always free.
		streamTo(plr, 1, Mine.center(Config), SPAWN_CELL_Z)
		;(hrp :: BasePart).CFrame = spawnCFrame(plr)
		sellHaul(plr, true) -- hauling up IS selling; that is the whole loop in one button
		pushState(plr)
	elseif dir == "down" then
		local d = deepestOpen[plr]
		if not d or d.y <= 0 then
			toast(plr, "⛏️ Nothing dug yet — break the floor to start your shaft!")
			return
		end
		-- THE DESTINATION IS BUILT FIRST. DESCEND aims at the deepest cell the player opened, which
		-- is empty by definition, and what holds them up is whatever is under it. Since the shaft
		-- streams, "whatever is under it" may not exist yet — and the only other thing under a dug
		-- shaft is the bedrock floor, up to three hundred layers down. streamTo moves the band and
		-- builds the layers either side of the landing synchronously.
		streamTo(plr, d.y, d.x, d.z)
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
		-- The two the flush would otherwise lose: this run's earnings are the gate, and the saved
		-- cave is every tunnel the player has dug. A rollback that restored the counter but not
		-- the cave would hand back a rebirth the player already spent their whole shaft on.
		runEarned = p.runEarned, openedBits = p.openedBits,
	}

	local ok, reason = Prestige.apply(p, Config, Ore)
	if not ok then
		if reason == "max" then
			toast(plr, "⭐ You have every rebirth there is. Nothing left to prove.")
		else
			toast(plr, "♻️ Rebirth needs $" .. Prestige.requirement(Config, Ore, p.rebirths)
				.. " EARNED this run — you are at $" .. math.floor(p.runEarned or 0)
				.. ". Spending does not set you back.")
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
	if hrp then
		streamTo(plr, 1, Mine.center(Config), SPAWN_CELL_Z)
		;(hrp :: BasePart).CFrame = spawnCFrame(plr)
	end
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

	-- THE ENGINE PLACES THE CHARACTER **AFTER** CharacterAdded, AND THE ENGINE WINS.
	--
	-- Measured in Roblox Studio: CharacterAdded fires while the model is still UNPARENTED with its
	-- root part at the world origin, and ONE FRAME LATER the engine parents it AND drops it on the
	-- enabled SpawnLocation — silently discarding whatever CFrame the handler wrote in between. No
	-- error, no warning: the assignment succeeds and is thrown away.
	--
	-- This function used to write the CFrame straight away, so every miner in the server was left
	-- standing on MinersRest instead of in their own shaft: -80.00, 2.51, 0.00, which is 82 studs
	-- from shaft 0's landing and 240 studs from shaft 1's — and since the engine drops EVERY
	-- character on the SAME pad, two miners who joined together stood 0.0 studs apart.
	--
	-- So: wait until the character is genuinely in the world, then write. `char.Parent` becoming
	-- non-nil is the signal, because the recording shows parent and placement landing in the same
	-- frame — by the time a poll sees a parent, the engine has already finished. WaitForChild is
	-- NOT that signal: on the server both children already exist when the event fires, so neither
	-- call yields and neither buys the frame this needs.
	local function place(char: Model)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if hrp == nil then return end
		-- The lamp does not race anything, so hang it before yielding: a miner who somehow never
		-- gets parented is still better off lit than in a black box.
		attachLamp(plr, char)

		-- Bounded: a character that never arrives must not park this handler for the session.
		local frames = 0
		while char.Parent == nil and frames < 300 do
			task.wait(1 / 60)
			frames += 1
		end
		if char.Parent == nil then return end

		-- RE-READ ACROSS THE YIELD. Up to five seconds is long enough to leave, to rebirth (which
		-- tears the shaft down and builds a new one) or to die and be handed a different
		-- character; `shaftFolders` is cleared by teardownShaft, so its being nil covers both a
		-- departure and the gap inside a rebirth. Placing without this would CFrame a body the
		-- player no longer owns, and a spawnCFrame taken with no shaft index reads silently as
		-- shaft 0 — a stranger's mine. Defensive: nothing in the suite can reach it.
		if plr.Character ~= char or shaftFolders[plr] == nil then return end

		-- ground under the landing before the landing, every time
		streamTo(plr, 1, Mine.center(Config), SPAWN_CELL_Z)
		;(hrp :: BasePart).CFrame = spawnCFrame(plr)
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

-- THE STREAM SWEEP. Follows every miner down their own shaft: Parts exist for the layers around
-- them and nowhere else. Cheap by construction — Mine.faces answers for the window rather than
-- for the excavation, and StreamHysteresis means stepping down one cell does not re-derive
-- anything at all.
task.spawn(function()
	while true do
		task.wait(Config.Mine.StreamPeriod)
		for _, plr in ipairs(Players:GetPlayers()) do
			-- one bad player must not stop the sweep for the rest of the server
			pcall(restream, plr)
		end
	end
end)

print("[DeepVein] Deep Vein lastet. WorldSeed=" .. Config.WorldSeed
	.. " · shaft " .. Config.Mine.GridW .. "x" .. Config.Mine.GridW
	.. " · depth wall " .. Mine.maxLayer(Config, 0) .. " layers")
