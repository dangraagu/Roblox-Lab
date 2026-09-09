-- GROW A CRYSTAL 💎 (Cavern Idle) — server, autoritativt.
-- Havner i ServerScriptService. All logikk styres av ReplicatedStorage.Config + de rene,
-- enhets-testede modulene (Rarity/Growth/Economy/Geode/Codex/Codes).
--
-- Kjerne: hver spiller får et privat plott (rutenett av sokler). Plant en seed → den
-- vokser med REELL tid (offline-vekst gratis: modenhet regnes fra plantedAt vs os.time()).
-- Høst en moden krystall → refraksjons-rull (fersk rng pr plante) → Gem Dust + Codex.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Rarity = require(ReplicatedStorage:WaitForChild("Rarity"))
local Growth = require(ReplicatedStorage:WaitForChild("Growth"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Geode = require(ReplicatedStorage:WaitForChild("Geode"))
local Codex = require(ReplicatedStorage:WaitForChild("Codex"))
local Codes = require(ReplicatedStorage:WaitForChild("Codes"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local Cavern = require(ReplicatedStorage:WaitForChild("Cavern"))

-- Visual polish (code-only, additive): warm glowing cavern lighting + post-fx.
-- The ambient dust is PER PLOT now (Cavern returns two volumes per cavern). The single global
-- 600x600 volume that used to live here was centred on x = 0, so it covered plots 0-3 and left
-- plot 19 at x = 1520 with no dust at all.
Fx.applyLighting(Fx.Presets.Cozy)

-- ── Remotes ─────────────────────────────────────────────────────────────────
local remotes = Instance.new("Folder")
remotes.Name = "CrystalRemotes"
remotes.Parent = ReplicatedStorage
local function mk(cn, n) local r = Instance.new(cn); r.Name = n; r.Parent = remotes; return r end
local StateEvent = mk("RemoteEvent", "State")        -- server -> klient: full tilstand
local BuyEvent = mk("RemoteEvent", "Buy")            -- klient -> server: {kind, arg}
local SelectEvent = mk("RemoteEvent", "Select")      -- klient -> server: valgt seed-tier
local GeodeEvent = mk("RemoteEvent", "Geode")        -- klient -> server: knus geode
local RedeemFunc = mk("RemoteFunction", "Redeem")    -- klient -> server: løs inn kode
local LeaderboardEvent = mk("RemoteEvent", "Leaderboard")
local ToastEvent = mk("RemoteEvent", "Toast")        -- server -> klient: kort melding (f.eks. "kjøp en seed")

-- ── Data ─────────────────────────────────────────────────────────────────────
local store = Config.Save.Enabled and DataStoreService:GetDataStore(Config.Save.Store) or nil
local orderedLB = Config.Save.Enabled and DataStoreService:GetOrderedDataStore(Config.Save.Leaderboard) or nil

local profiles = {} -- [player] = profile
local selected = {} -- [player] = seedTier currently selected in the shop UI

local function defaultProfile()
	return {
		dust = Config.Economy.StartDust,
		seeds = { [1] = 3 },              -- [tier]=count · start with 3 free Shard seeds so a new player can plant IMMEDIATELY (feedback: "i cant even place a seed")
		chambers = Config.Economy.StartChambers,
		luckLevel = 0, growthLevel = 0,
		plants = {},                      -- [socketId]={tier=,at=}
		codex = {},                       -- [tier]=true
		redeemed = {},                    -- [CODE]=true
		lastGeodeWeek = -1,
		totalDust = 0,                    -- cumulative earned (leaderboard)
		passes = {},
		canSave = false,
	}
end

local function key(uid) return "u_" .. uid end

-- DataStore serialiserer via JSON: spredte HELTALLS-nøkler (sockets/tiers) kommer
-- tilbake som STRENGER. Normaliser tilbake til tall så p.plants[socketId] /
-- p.seeds[tier] / p.codex[tier]-oppslag (heltall) treffer etter reload.
local function numKeys(src)
	local out = {}
	if type(src) == "table" then
		for k, v in pairs(src) do out[tonumber(k) or k] = v end
	end
	return out
end

-- Last + soft session-lock (samme robuste mønster som plus1-jump etter review):
-- last ALLTID ekte data; canSave = eier vi låsen. Kort TTL fornyet av autosave.
local function loadProfile(plr)
	local p = defaultProfile()
	if not store then p.canSave = false; return p end
	local acquired = false
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			local lockedByOther = (tonumber(old.lockUntil) or 0) > now and old.jobId ~= game.JobId
			local d = old.data
			if d then
				p.dust = tonumber(d.dust) or p.dust
				p.seeds = numKeys(d.seeds)   -- integer tier keys (JSON round-trip → string → number)
				p.chambers = tonumber(d.chambers) or p.chambers
				p.luckLevel = tonumber(d.luckLevel) or 0
				p.growthLevel = tonumber(d.growthLevel) or 0
				p.plants = numKeys(d.plants) -- integer socketId keys
				p.codex = numKeys(d.codex)   -- integer tier keys
				p.redeemed = (type(d.redeemed) == "table") and d.redeemed or {} -- string CODE keys (keep)
				p.lastGeodeWeek = tonumber(d.lastGeodeWeek) or -1
				p.totalDust = tonumber(d.totalDust) or 0
				p.passes = (type(d.passes) == "table") and d.passes or {}
			end
			if lockedByOther then acquired = false; return old end
			acquired = true
			old.jobId = game.JobId
			old.lockUntil = now + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	if not ok then
		p.canSave = false
		warn("[Crystal] load failed for " .. plr.Name .. ": " .. tostring(err))
	else
		p.canSave = acquired
		if not acquired then
			warn("[Crystal] " .. plr.Name .. " READ-ONLY (locked by another session); progress won't save.")
		end
	end
	return p
end

-- Returnerer true bare hvis dataene faktisk ble persistert (brukes for atomisk flush
-- av kode-innløsning + geode så en stille save-feil ikke duper/mister belønninger).
local function saveProfile(plr, releaseLock): boolean
	local p = profiles[plr]
	if not p or not p.canSave or not store then return false end
	local ok = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			old.data = {
				dust = p.dust, seeds = p.seeds, chambers = p.chambers,
				luckLevel = p.luckLevel, growthLevel = p.growthLevel,
				plants = p.plants, codex = p.codex, redeemed = p.redeemed,
				lastGeodeWeek = p.lastGeodeWeek, totalDust = p.totalDust, passes = p.passes,
			}
			old.jobId = game.JobId
			old.lockUntil = releaseLock and 0 or (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	if ok and orderedLB and p.totalDust > 0 then
		pcall(function() orderedLB:SetAsync(key(plr.UserId), math.floor(p.totalDust)) end)
	end
	return ok
end

-- ── Derived helpers ──────────────────────────────────────────────────────────
local function luckMultOf(p) return Rarity.luckMult(p.luckLevel, Config.Boosters) end
local function growthMultOf(p) return Growth.growthMult(p.growthLevel, Config.Boosters) end

-- ── Plot / cavern build (per player, deterministic layout) ──────────────────
local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"
plotsFolder.Parent = workspace

local PLOT_SPACING = 80
local usedPlots = {}          -- [plotIndex]=player
local playerPlot = {}         -- [player]=plotIndex
local plotFolders = {}        -- [player]=Folder ("Plot_<idx>"; EVERYTHING the player owns lives here)
local socketParts = {}        -- [player]={ [socketId]=Part }

local function claimPlot(plr)
	local i = 0
	while usedPlots[i] do i += 1 end
	usedPlots[i] = plr
	playerPlot[plr] = i
	return i
end

local function plotOrigin(plotIndex)
	return Vector3.new(plotIndex * PLOT_SPACING, 0, 0)
end

-- Cavern returns plot-LOCAL coordinates; the plot offset is added here and nowhere else.
local function socketWorldPos(plr, socketId)
	local local_ = Cavern.socketPos(Config, socketId, Rng)
	return plotOrigin(playerPlot[plr]) + Vector3.new(local_.x, local_.y, local_.z)
end

local grantHarvest, tryPlant -- forward decls

-- ── Turning one PartDef into one Part. The pure generator owns every number; this owns every
--    engine call, and nothing in between decides anything.
local function instantiate(def, origin, folder)
	local part = Instance.new("Part")
	part.Name = def.name
	part.Anchored = true
	if def.shape ~= "Block" then part.Shape = Enum.PartType[def.shape] end
	part.Size = Vector3.new(def.size.x, def.size.y, def.size.z)
	local pos = origin + Vector3.new(def.position.x, def.position.y, def.position.z)
	part.CFrame = CFrame.new(pos) * CFrame.Angles(
		math.rad(def.orientation.x), math.rad(def.orientation.y), math.rad(def.orientation.z))
	part.Material = Enum.Material[def.material]
	part.Color = Color3.fromRGB(def.color.r, def.color.g, def.color.b)
	part.Transparency = def.transparency
	part.Reflectance = def.reflectance
	part.CanCollide = def.collide
	part.CanQuery = def.query
	part.CanTouch = false
	part.CastShadow = def.castShadow
	part:SetAttribute("Chamber", def.chamber)
	part.Parent = folder
	return part
end

-- The price tag is painted on the TOP of the last step up to the terrace it belongs to. It used
-- to go on the deck's own -Z face with Face = Front, which is buried: that face is coplanar with
-- the back of the tread in front of it, an opaque collider of identical width and height, and
-- review measured it 100% occluded on all seven decks. Cavern emits the chamber INDEX; the money
-- is formatted here, so the pure generator never imports Economy.
local function attachPriceLabel(part, chamberIndex)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ChamberLabel"
	gui.Face = Enum.NormalId.Top
	gui.MaxDistance = 60
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui:SetAttribute("ChamberIndex", chamberIndex)
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(190, 220, 240)
	label.Text = ""
	label.Parent = gui
	gui.Parent = part
end

local function refreshChamberLabels(plr)
	local folder, p = plotFolders[plr], profiles[plr]
	if not folder or not p then return end
	for _, d in ipairs(folder:GetDescendants()) do
		if d.Name == "ChamberLabel" and d.ClassName == "SurfaceGui" then
			local c = d:GetAttribute("ChamberIndex")
			local label = d:FindFirstChild("Text")
			if c ~= nil and label then
				if c < p.chambers then
					label.Text = "CHAMBER " .. (c + 1)
				else
					label.Text = "CHAMBER " .. (c + 1) .. "  ·  "
						.. Economy.chamberCost(c, Config.Economy) .. " DUST"
				end
			end
		end
	end
end

local function makeSocket(plr, socketId)
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(6, 1, 6)
	part.Position = socketWorldPos(plr, socketId)
	-- An EMPTY plate is the glowing thing: Neon at 1 part and 0 lights, which keeps the HUD's
	-- "click a glowing socket to PLANT" literally true. It used to be a Slate plate with its own
	-- PointLight, i.e. 48 lights per plot before a single crystal existed.
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(58, 104, 132)
	part.Transparency = 0.35
	part.CanTouch = false
	part.Name = "Socket_" .. plr.UserId .. "_" .. socketId
	part:SetAttribute("SocketId", socketId)
	part:SetAttribute("Owner", plr.UserId)
	local cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 32
	cd.Parent = part
	cd.MouseClick:Connect(function(clicker)
		if clicker ~= plr then return end -- only the plot owner interacts
		local p = profiles[plr]
		if not p then return end
		if p.plants[socketId] then
			grantHarvest(plr, socketId)
		else
			tryPlant(plr, socketId)
		end
	end)
	-- INTO THE WORLD. This line was missing, and its absence is why nobody could plant anything:
	-- the Part was built, sized, positioned, named, given its attributes and handed a
	-- ClickDetector, and then left unparented. It existed only in `socketParts` below - not in
	-- the workspace, never replicated, and the ClickDetector could not fire from inside an
	-- orphan. refreshSocketVisual parented the crystal to the same orphan, so growth was
	-- invisible too. Nothing raised: an unparented Instance is silent, and the function returned
	-- a perfectly good Part the whole time.
	--
	-- Parent LAST, with the ClickDetector already inside, so the socket never exists in the
	-- world for a frame without the thing that makes it clickable.
	part.Parent = plotFolders[plr] or plotsFolder

	socketParts[plr] = socketParts[plr] or {}
	socketParts[plr][socketId] = part
	return part
end

-- A visible crystal model sits on a socket while something grows there.
local function refreshSocketVisual(plr, socketId)
	local part = socketParts[plr] and socketParts[plr][socketId]
	if not part then return end
	local old = part:FindFirstChild("Crystal")
	if old then old:Destroy() end
	local p = profiles[plr]
	local plant = p and p.plants[socketId]
	if not plant then
		-- empty again: back to the dim Neon "plant here" plate
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(58, 104, 132)
		part.Transparency = 0.35
		return
	end
	-- planted: the PLATE goes dark so the crystal is the bright thing on it
	part.Material = Enum.Material.Slate
	part.Color = Color3.fromRGB(52, 56, 70)
	part.Transparency = 0
	local c = Instance.new("Part")
	c.Name = "Crystal"
	c.Anchored = true
	c.CanCollide = false
	c.CanTouch = false
	local prog = Growth.progress(plant.at, os.time(), plant.tier, Config.Growth, growthMultOf(p))
	c.Size = Vector3.new(1.5, 2 + 4 * prog, 1.5)
	c.Position = part.Position + Vector3.new(0, c.Size.Y / 2, 0)
	c.Material = Enum.Material.Neon
	local rgb = Config.TierColor[plant.tier]
	local col = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	c.Color = col
	c.Parent = part
	-- A ClickDetector only fires from the surface of the part it is parented to, so the HUD's
	-- "click a grown crystal to HARVEST" was false until the crystal got its own.
	local ccd = Instance.new("ClickDetector")
	ccd.MaxActivationDistance = 32
	ccd.Parent = c
	ccd.MouseClick:Connect(function(clicker)
		if clicker ~= plr then return end
		local prof = profiles[plr]
		if not prof then return end
		if prof.plants[socketId] then grantHarvest(plr, socketId) else tryPlant(plr, socketId) end
	end)
	-- A growing crystal is Neon under a threshold-0.9 Bloom and glows fine unlit. The light is
	-- gated so it means "ready, and it is a rare one" — without this gate the 10-light budget
	-- for the whole plot is a lie.
	if prog >= 1 then
		if plant.tier >= 3 then
			Fx.attachGlow(c, col, 1 + 2 * prog, 10 + 6 * plant.tier)
		end
		Fx.sparkle(c, col) -- mature crystals glint (ready to harvest)
	end
end

local function buildChambers(plr)
	local p = profiles[plr]
	local total = Economy.totalSockets(p.chambers, Config.Economy)
	socketParts[plr] = socketParts[plr] or {}
	for socketId = 1, total do
		if not socketParts[plr][socketId] then
			makeSocket(plr, socketId)
		end
		refreshSocketVisual(plr, socketId)
	end
end

-- Everything a player owns goes in one folder, so teardown is a single :Destroy() and nothing
-- can leak. Build order matters: the 36 colliders synchronously first, so a character that
-- spawns on the very first frame cannot drop through the world; then the sockets; then the
-- decoration, lamps and dust in yielding chunks, so twenty players joining at once do not
-- instantiate ~3,000 parts in one burst.
local function buildCavern(plr)
	local idx = playerPlot[plr]
	local p = profiles[plr]
	if idx == nil or p == nil then return end

	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. idx
	folder.Parent = plotsFolder
	plotFolders[plr] = folder

	local cav = Cavern.build(Config, idx, Rng)
	local origin = plotOrigin(idx)

	local wanted, deferred = 0, {}
	for _, def in ipairs(cav.parts) do
		local live = (def.chamber == -1 or def.chamber >= p.chambers)
		if live then
			wanted += 1
			if def.collide then
				local part = instantiate(def, origin, folder)
				if def.chamberLabel then attachPriceLabel(part, def.chamberLabel) end
			else
				deferred[#deferred + 1] = def
			end
		end
	end
	refreshChamberLabels(plr)

	buildChambers(plr)

	task.spawn(function()
		local made = wanted - #deferred
		local since = 0
		for _, def in ipairs(deferred) do
			if plotFolders[plr] ~= folder then return end -- the player left mid-build
			instantiate(def, origin, folder)
			made += 1
			since += 1
			if since >= 30 then since = 0; task.wait() end
		end
		for _, d in ipairs(cav.dust) do
			if plotFolders[plr] ~= folder then return end
			Fx.dustVolume(folder, Vector3.new(d.size.x, d.size.y, d.size.z),
				CFrame.new(origin + Vector3.new(d.position.x, d.position.y, d.position.z)),
				Color3.fromRGB(d.color.r, d.color.g, d.color.b), d.rate)
		end
		for _, l in ipairs(cav.lights) do
			if plotFolders[plr] ~= folder then return end
			local nub = folder:FindFirstChild(l.name)
			if nub then
				Fx.attachGlow(nub, Color3.fromRGB(l.color.r, l.color.g, l.color.b), l.brightness, l.range)
			end
		end
		-- ASK THE FOLDER, do not count the loop. The previous version compared `made` - a counter
		-- incremented beside each instantiate call - against `wanted`, which is the same
		-- arithmetic on both sides and can never disagree. Review proved it: deleting
		-- `part.Parent = folder` from instantiate, which is exactly the defect that shipped on
		-- 5 September, left 8 parts of 154 in the world and this assert stayed silent.
		-- An unparented Instance raises nothing and logs nothing. The only question worth
		-- asking is how many actually landed.
		local landed = 0
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then landed += 1 end
		end
		assert(landed >= wanted,
			"[Crystal] cavern build put " .. landed .. " parts in " .. folder.Name
				.. ", wanted at least " .. wanted .. " (made=" .. made .. ")")
	end)
end

-- Buying a chamber clears its rubble cap. Sweep every already-owned index, so the folder is
-- correct even if an earlier sweep was interrupted.
local function clearOwnedLocks(plr)
	local folder, p = plotFolders[plr], profiles[plr]
	if not folder or not p then return end
	for _, d in ipairs(folder:GetDescendants()) do
		local c = d:GetAttribute("Chamber")
		if type(c) == "number" and c >= 0 and c < p.chambers then
			d:Destroy()
		end
	end
end

-- ── State push ────────────────────────────────────────────────────────────────
local function pushState(plr)
	local p = profiles[plr]
	if not p then return end
	local ec = Config.Economy
	local plants = {}
	for sid, pl in pairs(p.plants) do
		plants[tostring(sid)] = { tier = pl.tier, at = pl.at }
	end
	local ls = plr:FindFirstChild("leaderstats")
	if ls then (ls:FindFirstChild("Dust") :: IntValue).Value = math.floor(p.dust) end
	StateEvent:FireClient(plr, {
		dust = math.floor(p.dust),
		seeds = p.seeds,
		chambers = p.chambers,
		totalSockets = Economy.totalSockets(p.chambers, ec),
		socketsPerChamber = ec.SocketsPerChamber,
		luckLevel = p.luckLevel, growthLevel = p.growthLevel,
		luckMult = luckMultOf(p), growthMult = growthMultOf(p),
		plants = plants,
		codexCount = Codex.count(p.codex, Config.MaxTier),
		codex = p.codex,
		chamberCost = Economy.chamberCost(p.chambers, ec),
		luckCost = Economy.boosterCost(p.luckLevel, Config.Boosters.Luck),
		growthCost = Economy.boosterCost(p.growthLevel, Config.Boosters.Growth),
		geodeCanCrack = Geode.canCrack(p, os.time(), Config.Geode),
		geodeExclusive = Geode.exclusiveFor(os.time(), Config.Geode),
		geodeCost = Config.Geode.CostDust,
		now = os.time(),
	})
end

-- ── Plant / Harvest ──────────────────────────────────────────────────────────
tryPlant = function(plr, socketId)
	local p = profiles[plr]
	if not p then return end
	local total = Economy.totalSockets(p.chambers, Config.Economy)
	if socketId < 1 or socketId > total then return end
	if p.plants[socketId] then return end -- occupied
	local tier = selected[plr] or 1
	-- Auto-buy on click: if you don't own a seed of the selected tier, try to buy one with
	-- your dust right here so a single click just plants (no hidden buy->select->plant dance).
	-- This + the free starter seeds fixes the "i cant even place a seed" feedback.
	if (p.seeds[tier] or 0) <= 0 then
		if not Economy.buySeed(p, tier, Config.Economy) then
			ToastEvent:FireClient(plr, "Not enough Gem Dust for that seed — harvest a crystal first!")
			return
		end
	end
	p.seeds[tier] -= 1
	p.plants[socketId] = { tier = tier, at = os.time() }
	refreshSocketVisual(plr, socketId)
	pushState(plr)
end

grantHarvest = function(plr, socketId)
	local p = profiles[plr]
	if not p then return end
	local plant = p.plants[socketId]
	if not plant then return end
	if not Growth.isMature(plant.at, os.time(), plant.tier, Config.Growth, growthMultOf(p)) then
		return -- not ready
	end
	-- Refraction roll: fresh rng per plant (varies each harvest but reproducible)
	local rng = Rng.new((os.time() * 1000 + socketId * 977 + plr.UserId) % 2147483647)
	local finalTier = Rarity.roll(plant.tier, luckMultOf(p), rng, Config.Refraction, Config.MaxTier)
	local dust = Economy.harvestDust(finalTier, p.passes.DoubleDust == true, Config.Economy)
	p.dust += dust
	p.totalDust += dust
	Codex.discover(p.codex, finalTier)
	p.plants[socketId] = nil
	refreshSocketVisual(plr, socketId)
	pushState(plr)
end

-- ── Buy / Geode / Redeem ──────────────────────────────────────────────────────
BuyEvent.OnServerEvent:Connect(function(plr, kind, arg)
	local p = profiles[plr]
	if not p then return end
	local ok = false
	if kind == "seed" then
		local tier = tonumber(arg)
		if tier then ok = Economy.buySeed(p, tier, Config.Economy) end
	elseif kind == "chamber" then
		ok = Economy.buyChamber(p, Config.Economy)
		if ok then
			buildChambers(plr)
			clearOwnedLocks(plr)      -- the rubble over the new terrace goes
			refreshChamberLabels(plr) -- and its riser stops advertising a price
		end
	elseif kind == "booster" then
		if arg == "Luck" or arg == "Growth" then ok = Economy.buyBooster(p, arg, Config.Boosters) end
	end
	if ok then pushState(plr) end
end)

SelectEvent.OnServerEvent:Connect(function(plr, tier)
	tier = tonumber(tier)
	if tier and tier >= 1 and tier <= Config.MaxTier then selected[plr] = tier end
end)

GeodeEvent.OnServerEvent:Connect(function(plr)
	local p = profiles[plr]
	if not p then return end
	local prevWeek = p.lastGeodeWeek
	local ok, _, tier = Geode.crack(p, os.time(), Config.Geode) -- deducts dust + sets lastGeodeWeek
	if not (ok and tier) then return end
	p.seeds[tier] = (p.seeds[tier] or 0) + 1 -- grant an exclusive seed of that tier
	-- Atomic flush: geode is once-per-week — if it didn't persist, roll back everything
	-- so a crash can't leave dust spent / week burned without the reward.
	if not saveProfile(plr, false) then
		p.dust += Config.Geode.CostDust
		p.lastGeodeWeek = prevWeek
		p.seeds[tier] -= 1
		pushState(plr)
		return
	end
	pushState(plr)
end)

RedeemFunc.OnServerInvoke = function(plr, input)
	local p = profiles[plr]
	if not p then return { ok = false, reason = "notready" } end
	if type(input) ~= "string" then return { ok = false, reason = "empty" } end
	local ok, reward, reason = Codes.redeem(input, p.redeemed, Config.Codes)
	if not ok then return { ok = false, reason = reason } end
	local code = Codes.normalize(input)
	p.redeemed[code] = true
	if reward.dust then p.dust += reward.dust end
	if reward.seedTier then p.seeds[reward.seedTier] = (p.seeds[reward.seedTier] or 0) + 1 end
	-- Atomic flush: mark redeemed + reward persist together. If the save did NOT persist,
	-- roll back so a crash can't let the code be redeemed a second time (dupe) or grant a
	-- phantom reward the DataStore never recorded.
	if not saveProfile(plr, false) then
		p.redeemed[code] = nil
		if reward.dust then p.dust -= reward.dust end
		if reward.seedTier then p.seeds[reward.seedTier] -= 1 end
		return { ok = false, reason = "retry" }
	end
	pushState(plr)
	return { ok = true, reason = "ok", dust = reward.dust, seedTier = reward.seedTier }
end

-- ── Leaderboard ────────────────────────────────────────────────────────────────
local function refreshLeaderboard()
	if not orderedLB then return end
	local ok, page = pcall(function() return orderedLB:GetSortedAsync(false, 10) end)
	if not ok or not page then return end
	local top = {}
	for _, e in ipairs(page:GetCurrentPage()) do
		top[#top + 1] = { userId = tonumber((string.gsub(e.key, "^u_", ""))), dust = e.value }
	end
	for _, plr in ipairs(Players:GetPlayers()) do LeaderboardEvent:FireClient(plr, top) end
end

-- ── Player lifecycle ────────────────────────────────────────────────────────
local function onPlayerAdded(plr)
	profiles[plr] = loadProfile(plr)

	-- loadProfile YIELDS on DataStore:UpdateAsync, and leaving during that yield is one of the
	-- commonest things a real player does. PlayerRemoving fires while profiles/playerPlot/
	-- plotFolders are still empty, so onPlayerRemoving frees nothing - there is nothing yet -
	-- and then THIS function resumes and builds a whole cavern for somebody who is gone.
	-- Per occurrence, for the life of the server: a plot index never released, and a live folder
	-- holding 154 parts, 10 lights, 2 emitters and 6 ClickDetectors.
	-- Found by review, by reading. The harness cannot reproduce it: its DataStore is synchronous
	-- and never yields, so no ordering it can produce exercises the race.
	if plr.Parent == nil then
		profiles[plr] = nil
		return
	end

	selected[plr] = 1

	local ls = Instance.new("Folder"); ls.Name = "leaderstats"
	local dust = Instance.new("IntValue"); dust.Name = "Dust"; dust.Parent = ls
	ls.Parent = plr

	local idx = claimPlot(plr)
	buildCavern(plr)

	-- Spawn on the entrance apron looking down +Z into the cavern. The identity frame looks
	-- down -Z, so this MUST be the two-argument form or the player faces the entrance wall.
	local sp = Cavern.spawn(Config)
	local origin = plotOrigin(idx)
	local function place(char)
		local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
		local at = origin + Vector3.new(sp.position.x, sp.position.y, sp.position.z)
		hrp.CFrame = CFrame.new(at, at + Vector3.new(sp.look.x, sp.look.y, sp.look.z))
	end
	plr.CharacterAdded:Connect(place)
	if plr.Character then place(plr.Character) end

	pushState(plr)
end

local function onPlayerRemoving(plr)
	saveProfile(plr, true)
	-- Destroy the plot FIRST, then free the index: a join in the same frame must never be able
	-- to claim a name that is still taken. One :Destroy() takes the whole cavern with it —
	-- previously only the sockets and the pad were ever cleaned up, so everything else leaked.
	local folder = plotFolders[plr]
	plotFolders[plr] = nil
	if folder then folder:Destroy() end
	socketParts[plr] = nil
	local idx = playerPlot[plr]
	playerPlot[plr] = nil
	if idx ~= nil then usedPlots[idx] = nil end
	profiles[plr] = nil
	selected[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr, true) end
end)

-- Autosave (also renews the session lock) + periodic visual refresh + leaderboard
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for _, plr in ipairs(Players:GetPlayers()) do saveProfile(plr, false) end
	end
end)
task.spawn(function()
	while true do
		task.wait(5)
		-- Iterate a stable snapshot (Players), not the live `profiles` map that
		-- onPlayerRemoving mutates, and skip anyone whose profile is already gone.
		for _, plr in ipairs(Players:GetPlayers()) do
			if profiles[plr] and socketParts[plr] then
				for sid in pairs(socketParts[plr]) do refreshSocketVisual(plr, sid) end
			end
		end
	end
end)
task.spawn(function()
	while true do refreshLeaderboard(); task.wait(30) end
end)

print("[Crystal] Grow a Crystal lastet. WorldSeed=" .. Config.WorldSeed)
