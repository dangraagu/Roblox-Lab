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

-- Visual polish (code-only, additive): warm glowing cavern lighting + post-fx + ambient dust.
Fx.applyLighting(Fx.Presets.Cozy)
Fx.dustVolume(workspace, Vector3.new(600, 160, 600), CFrame.new(0, 70, 0), Color3.fromRGB(150, 200, 220), 40)

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
local socketParts = {}        -- [player]={ [socketId]=Part }

local function claimPlot(plr)
	local i = 0
	while usedPlots[i] do i += 1 end
	usedPlots[i] = plr
	playerPlot[plr] = i
	return i
end

local function socketWorldPos(plotIndex, socketId)
	local ec = Config.Economy
	local chamber = math.floor((socketId - 1) / ec.SocketsPerChamber) -- 0-based
	local col = (socketId - 1) % ec.SocketsPerChamber
	local origin = Vector3.new(plotIndex * PLOT_SPACING, 3, 0)
	-- deterministic tiny jitter per socket so caverns feel organic (shared shape)
	local rng = Rng.new(Config.WorldSeed + socketId * 31 + chamber * 7)
	local jitter = (rng:int(-15, 15)) / 10
	return origin + Vector3.new(col * 8 - 20, 0, chamber * 10 + jitter)
end

local grantHarvest, tryPlant -- forward decls

local function makeSocket(plr, socketId)
	local plotIndex = playerPlot[plr]
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(6, 1, 6)
	part.Position = socketWorldPos(plotIndex, socketId)
	part.Material = Enum.Material.Slate
	part.Color = Color3.fromRGB(70, 74, 92)
	-- a faint rim glow so empty sockets read as "plantable" (onboarding affordance)
	Fx.attachGlow(part, Color3.fromRGB(90, 150, 200), 0.6, 8)
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
	if not plant then return end
	local c = Instance.new("Part")
	c.Name = "Crystal"
	c.Anchored = true
	c.CanCollide = false
	local prog = Growth.progress(plant.at, os.time(), plant.tier, Config.Growth, growthMultOf(p))
	c.Size = Vector3.new(1.5, 2 + 4 * prog, 1.5)
	c.Position = part.Position + Vector3.new(0, c.Size.Y / 2, 0)
	c.Material = Enum.Material.Neon
	local rgb = Config.TierColor[plant.tier]
	local col = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	c.Color = col
	c.Parent = part
	-- visual polish: crystals glow + sparkle, brighter as they mature and by tier
	Fx.attachGlow(c, col, 1 + 2 * prog, 10 + 6 * plant.tier)
	if prog >= 1 then
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
		if ok then buildChambers(plr) end
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
	selected[plr] = 1

	local ls = Instance.new("Folder"); ls.Name = "leaderstats"
	local dust = Instance.new("IntValue"); dust.Name = "Dust"; dust.Parent = ls
	ls.Parent = plr

	claimPlot(plr)
	buildChambers(plr)

	-- Spawn the player on/near their plot pad
	local pad = Instance.new("Part")
	pad.Anchored = true; pad.Size = Vector3.new(48, 1, 60)
	pad.Position = Vector3.new(playerPlot[plr] * PLOT_SPACING, 2, 20)
	pad.Material = Enum.Material.SmoothPlastic; pad.Color = Color3.fromRGB(40, 44, 60)
	pad.Name = "Pad_" .. plr.UserId
	pad.Parent = plotsFolder

	local function place(char)
		local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
		hrp.CFrame = CFrame.new(pad.Position + Vector3.new(0, 4, 0))
	end
	plr.CharacterAdded:Connect(place)
	if plr.Character then place(plr.Character) end

	pushState(plr)
end

local function onPlayerRemoving(plr)
	saveProfile(plr, true)
	-- free the plot + destroy its parts
	local idx = playerPlot[plr]
	if idx ~= nil then usedPlots[idx] = nil end
	playerPlot[plr] = nil
	if socketParts[plr] then
		for _, part in pairs(socketParts[plr]) do part:Destroy() end
	end
	socketParts[plr] = nil
	local pad = plotsFolder:FindFirstChild("Pad_" .. plr.UserId)
	if pad then pad:Destroy() end
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
