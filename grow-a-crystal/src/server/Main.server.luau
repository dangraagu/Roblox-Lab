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
local HttpService = game:GetService("HttpService") -- GenerateGUID only (the session token); no HTTP
local RunService = game:GetService("RunService")   -- IsStudio only: a failed load in Studio means "never saves"

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
local Board = require(ReplicatedStorage:WaitForChild("Board"))
local BC = Config.Board

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

-- ── Refusals say why ──────────────────────────────────────────────────────────
-- A refused player action must never be a silent no-op (docs/new-game-checklist.md; the first player report,
-- "i cant even place a seed", was one). Every refusal sends the player a toast with the reason and, where
-- money is the reason, the price (robloxemu/check_growacrystal_refused.luau).
local function refuse(plr, msg: string)
	ToastEvent:FireClient(plr, msg)
end
local function notYourCavern(clicker, owner)
	-- short enough to read at 12 px on a tablet with a 20-character name (check_growacrystal_refused)
	refuse(clicker, "That's " .. owner.Name .. "'s cavern, not yours")
end

-- ── Data ─────────────────────────────────────────────────────────────────────
-- GetDataStore RAISES in a place that has not been published to the web, and again when
-- "Enable Studio Access to API Services" is off. Unwrapped, that error killed this entire server
-- script at load: no world, no remotes, no game, and the only clue a line in the console. It is
-- why this game could not be opened in Studio at all without publishing first, which is a large
-- part of why it went so long without ever being run by a person.
-- Saving is what should degrade, not the game. Every write path already checks `store`.
local function tryStore(fn, what)
	if not Config.Save.Enabled then return nil end
	local ok, ds = pcall(fn)
	if ok then return ds end
	warn("[Crystal] " .. what .. " datastore unavailable (" .. tostring(ds)
		.. ") - the game runs, progress will NOT be saved this session.")
	return nil
end

local store = tryStore(function() return DataStoreService:GetDataStore(Config.Save.Store) end, "profiles")
local orderedLB = tryStore(function() return DataStoreService:GetOrderedDataStore(Config.Save.Leaderboard) end, "leaderboard")

local profiles = {} -- [player] = profile
local selected = {} -- [player] = seedTier currently selected in the shop UI
-- [player] = { n, socket, seed, tier }: this session's LAST finished harvest, repeated in every State
-- push so the client can draw a burst in the colour the refraction roll produced (and a beam of light
-- for Legendary/Mythic) when n grows. Cosmetic only: never saved, never read back, and it describes a
-- roll that has already been paid, so it tells the player nothing their dust and codex do not.
local harvests = {}
-- The refraction roll's salt source (grantHarvest). SERVER-ONLY: a local of this script, seeded by the
-- engine's own entropy (Random.new() with no seed), never saved, never sent, never an attribute. One stream
-- for every player on the server, so a client also never sees the draws between two of its own harvests.
local rollSalt = Random.new()

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
		totalDust = 0,                    -- cumulative dust EARNED FROM HARVESTS (the highscore board's metric)
		boardAt = 0,                      -- unix time the board points (Board.metricOfDust) last rose: the tie-break
		boardMetric = 0,                  -- the points last written to the board store (write only when they rise)
		passes = {},
		canSave = false,
		-- Runtime only, never saved: the token this session's load wrote into the record when it took the
		-- lock. A write lands only while the record still carries it (saveProfile).
		session = nil,
		-- Runtime only: "ok" (holds the lock, or lost it later: saveProfile), "locked" (another server's lock was on
		-- the record at load), "retry" (the load call failed), "nostore" (this session can never save: no DataStore,
		-- or Studio without API access). "locked" and "retry" try again on every autosave (retryLoad).
		saveState = "ok",
		lockSeen = nil, -- "locked": the record's jobId/session/lockUntil as this session read them
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

-- The saved fields of a record's `data` onto a profile (load, and a retry that reads a newer record). A record with
-- no data leaves the profile's defaults.
local function applyData(p, d)
	if type(d) ~= "table" then return end
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
	p.boardAt = tonumber(d.boardAt) or 0
	p.boardMetric = tonumber(d.boardMetric) or 0
	p.passes = (type(d.passes) == "table") and d.passes or {}
	-- Saved before the board (2026-09-30): points without a time. When they were reached is unknown, so they are
	-- stamped with this session (the player comes back on the board at the next save, behind anyone who reached
	-- the same points before).
	if Board.metricOfDust(p.totalDust, BC) > 0 and p.boardAt <= 0 then
		p.boardAt = os.time()
	end
end

local function lockOf(rec)
	return { jobId = rec.jobId, session = rec.session, lockUntil = rec.lockUntil }
end

-- Last + soft session-lock (samme robuste mønster som plus1-jump etter review):
-- last ALLTID ekte data; canSave = eier vi låsen. Kort TTL fornyet av autosave.
-- A load that cannot take the lock is not the end of the session (standard §1, check_growacrystal_rejoin): the
-- player is told (onPlayerAdded) and every autosave tries again (retryLoad). Measured before: a rejoin within 45 s
-- of a server crash, or one failed call, gave a whole session that never saved and never said so.
local function loadProfile(plr)
	local p = defaultProfile()
	if not store then p.canSave = false; p.saveState = "nostore"; return p end
	local acquired = false
	local seen = nil
	local token = HttpService:GenerateGUID(false)
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			local lockedByOther = (tonumber(old.lockUntil) or 0) > now and old.jobId ~= game.JobId
			applyData(p, old.data)
			if lockedByOther then
				acquired = false
				seen = lockOf(old)
				return nil -- read only: the record is not this session's to write
			end
			acquired = true
			old.jobId = game.JobId
			old.session = token
			old.lockUntil = now + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	if not ok then
		p.canSave = false
		-- Studio without API access fails every call for the whole session: retrying would only nag
		p.saveState = if RunService:IsStudio() then "nostore" else "retry"
		warn("[Crystal] load failed for " .. plr.Name .. ": " .. tostring(err))
	else
		p.canSave = acquired
		p.session = if acquired then token else nil
		if not acquired then
			p.saveState = "locked"
			p.lockSeen = seen
			warn("[Crystal] " .. plr.Name .. " READ-ONLY (locked by another session); retrying on every autosave.")
		end
	end
	return p
end

-- The highscore board (standard §3). The stored value is Board.encode(points, reachedAt): a higher score always
-- ranks higher, and on the same points whoever reached them FIRST ranks higher. It is written only when the points
-- have risen since the last write, through UpdateAsync + Board.keepHigher, which never lowers what is stored and
-- aborts rather than rewrite the same value. It used to be SetAsync(raw totalDust) on every autosave: 30 writes
-- per player in 10 idle minutes with nothing changed (robloxemu/check_growacrystal_board.luau).
local scoreCache = Board.newCache(BC.ScoreCacheSeconds) -- [userId] = stored value (0 = none), per server

local function writeBoard(p, userId: number)
	local points = Board.metricOfDust(p.totalDust, BC)
	if not orderedLB or points <= p.boardMetric then return end
	local value = Board.encode(points, p.boardAt, BC)
	local ok = pcall(function()
		orderedLB:UpdateAsync(Board.key(userId), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	if ok then
		p.boardMetric = points -- also when keepHigher aborted: what is stored is at least as high
		Board.cachePut(scoreCache, userId, value, tick())
	end
end

-- Returnerer true bare hvis dataene faktisk ble persistert (brukes for atomisk flush
-- av kode-innløsning + geode så en stille save-feil ikke duper/mister belønninger).
local function saveProfile(plr, releaseLock): boolean
	local p = profiles[plr]
	if not p or not p.canSave or not store then return false end
	-- OWNERSHIP (the fork-tower pattern; standard §1 "an owner token on every write"). The write lands only
	-- while the record still carries the token this session's load wrote AND this server's jobId (a server
	-- that predates the token takes the record over by jobId alone). Otherwise it is cancelled, whatever it
	-- is: an autosave, a leave, a code or geode flush. Without this, a server that stalled past the lock
	-- overwrote the progress made on the server the player had moved to, and made a used code redeemable
	-- again (robloxemu/check_growacrystal_lock.luau). `lost` is set on every invocation: UpdateAsync may run
	-- the transform more than once.
	local lost = false
	local ok = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			if old.session ~= p.session or (old.jobId ~= nil and old.jobId ~= game.JobId) then
				lost = true
				return nil
			end
			lost = false
			old.data = {
				dust = p.dust, seeds = p.seeds, chambers = p.chambers,
				luckLevel = p.luckLevel, growthLevel = p.growthLevel,
				plants = p.plants, codex = p.codex, redeemed = p.redeemed,
				lastGeodeWeek = p.lastGeodeWeek, totalDust = p.totalDust, passes = p.passes,
				boardAt = p.boardAt, boardMetric = p.boardMetric,
			}
			old.jobId = game.JobId
			old.lockUntil = releaseLock and 0 or (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	if lost then
		-- Another session owns this profile now. Nothing this one does is kept from here on, so it stops
		-- writing, and the atomic flushes (codes, geode) refuse because they cannot persist.
		p.canSave = false
		warn("[Crystal] " .. plr.Name .. ": another session has taken this profile over; this session no longer saves.")
		if plr.Parent ~= nil then
			pcall(function()
				ToastEvent:FireClient(plr, "Opened on another server — this one won't save")
			end)
		end
		return false
	end
	if ok then writeBoard(p, plr.UserId) end
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
		if clicker ~= plr then notYourCavern(clicker, plr) return end -- only the plot owner interacts
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
--
-- BUILT ONCE PER PLANT, UPDATED IN PLACE. This used to destroy and rebuild the crystal, its ClickDetector, its
-- light and its sparkle on every call, and the 5-second loop below calls it for every socket: 144 instances per
-- plot destroyed and recreated every 5 s at chamber 8, every sparkle restarting at once (review round 2,
-- finding 4). Now a crystal is made when its plant appears, resized while it grows, and destroyed when the plant
-- goes. Lights and sparkles are dealt out per plot by applyPlotBudget.
local crystals = {} -- [player] = { [socketId] = { part = Part, plant = the profile's plant table, tier, ready } }

local function refreshSocketVisual(plr, socketId)
	local part = socketParts[plr] and socketParts[plr][socketId]
	if not part then return end
	local p = profiles[plr]
	local plant = p and p.plants[socketId]
	local mine = crystals[plr]
	if mine == nil then
		mine = {}
		crystals[plr] = mine
	end
	local rec = mine[socketId]
	if rec and rec.plant ~= plant then
		rec.part:Destroy()
		mine[socketId] = nil
		rec = nil
	end
	if not plant then
		-- empty again: back to the dim Neon "plant here" plate
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(58, 104, 132)
		part.Transparency = 0.35
		return
	end
	local prog = Growth.progress(plant.at, os.time(), plant.tier, Config.Growth, growthMultOf(p))
	local height = 2 + 4 * prog
	if rec == nil then
		local stray = part:FindFirstChild("Crystal")
		if stray then stray:Destroy() end
		-- planted: the PLATE goes dark so the crystal is the bright thing on it
		part.Material = Enum.Material.Slate
		part.Color = Color3.fromRGB(52, 56, 70)
		part.Transparency = 0
		local c = Instance.new("Part")
		c.Name = "Crystal"
		c.Anchored = true
		c.CanCollide = false
		c.CanTouch = false
		c.Size = Vector3.new(1.5, height, 1.5)
		c.Position = part.Position + Vector3.new(0, height / 2, 0)
		c.Material = Enum.Material.Neon
		local rgb = Config.TierColor[plant.tier]
		c.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		c.Parent = part
		-- A ClickDetector only fires from the surface of the part it is parented to, so the HUD's
		-- "click a grown crystal to HARVEST" was false until the crystal got its own.
		local ccd = Instance.new("ClickDetector")
		ccd.MaxActivationDistance = 32
		ccd.Parent = c
		ccd.MouseClick:Connect(function(clicker)
			if clicker ~= plr then notYourCavern(clicker, plr) return end
			local prof = profiles[plr]
			if not prof then return end
			if prof.plants[socketId] then grantHarvest(plr, socketId) else tryPlant(plr, socketId) end
		end)
		rec = { part = c, plant = plant, tier = plant.tier, ready = false }
		mine[socketId] = rec
	elseif math.abs(rec.part.Size.Y - height) > 1e-3 then
		rec.part.Size = Vector3.new(1.5, height, 1.5)
		rec.part.Position = part.Position + Vector3.new(0, height / 2, 0)
	end
	rec.ready = prog >= 1
end

-- The plot's crystal lights and sparkles, within Config.PlotBudget (standard §2: budgets capped in code).
-- * Every READY crystal glints: the sparkle is the "ready to harvest" cue, so it stays true for all of them.
--   Their summed rate is capped at PlotBudget.SparkleRate particles/s, shared equally; up to
--   SparkleRate / SparklePerCrystal ready crystals keep the full per-crystal rate.
-- * A ready crystal of tier 3 and up may cast light, the rarest first (then the lowest socket), at most
--   PlotBudget.CrystalLights of them. A growing crystal is Neon under a threshold-0.9 Bloom and glows unlit.
-- Measured before the cap (48 crystals ready at chamber 8, the returning idle player): 58 PointLights,
-- 50 emitters, 322 particles/s in one plot (robloxemu/check_growacrystal_plotbudget.luau).
local function applyPlotBudget(plr)
	local mine = crystals[plr]
	if mine == nil then return end
	local B = Config.PlotBudget
	local ready = {}
	for sid, rec in mine do
		if rec.ready then
			table.insert(ready, { sid = sid, rec = rec })
		else
			local glow = rec.part:FindFirstChild("FxGlow")
			if glow then glow:Destroy() end
			local sp = rec.part:FindFirstChild("FxSparkle")
			if sp then sp:Destroy() end
		end
	end
	table.sort(ready, function(a, b)
		if a.rec.tier ~= b.rec.tier then return a.rec.tier > b.rec.tier end
		return a.sid < b.sid
	end)
	local rate = if #ready > 0 then math.min(B.SparklePerCrystal, B.SparkleRate / #ready) else 0
	local lights = 0
	for _, r in ready do
		local c = r.rec.part
		local glow = c:FindFirstChild("FxGlow")
		if r.rec.tier >= 3 and lights < B.CrystalLights then
			lights += 1
			if not glow then Fx.attachGlow(c, c.Color, 3, 10 + 6 * r.rec.tier) end
		elseif glow then
			glow:Destroy()
		end
		local sp = c:FindFirstChild("FxSparkle") or Fx.sparkle(c, c.Color)
		if sp.Rate ~= rate then sp.Rate = rate end
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
	applyPlotBudget(plr)
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
		lastHarvest = harvests[plr],
	})
end

-- ── Refusals say why (refuse() is defined next to the Toast remote, above) ─────────────────────────────
local function seedRefusal(tier: number, reason: string): string
	local name = Config.Tiers[tier] or "that"
	if reason == "locked" then
		return name .. " seeds unlock at chamber " .. tostring(Config.Economy.SeedShopUnlockedByChamber[tier])
	end
	return "Not enough Gem Dust: a " .. name .. " seed costs " .. tostring(Config.Economy.SeedCost[tier])
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
	local free = false
	if (p.seeds[tier] or 0) <= 0 then
		local bought, reason = Economy.buySeed(p, tier, Config.Economy)
		if not bought then
			-- a dead end (nothing growing, no seed, less dust than a Shard) is not a refusal: it would be
			-- forever. A free Shard instead (owner decision 2026-09-30; Economy.needsFreeSeed).
			if not Economy.needsFreeSeed(p, Config.Economy) then
				refuse(plr, seedRefusal(tier, reason))
				return
			end
			tier = 1
			p.seeds[1] = (p.seeds[1] or 0) + 1
			free = true
		end
	end
	p.seeds[tier] -= 1
	p.plants[socketId] = { tier = tier, at = os.time() }
	refreshSocketVisual(plr, socketId)
	applyPlotBudget(plr)
	pushState(plr)
	if free then refuse(plr, "Out of Gem Dust, so here's a free Shard seed 🌱") end
end

grantHarvest = function(plr, socketId)
	local p = profiles[plr]
	if not p then return end
	local plant = p.plants[socketId]
	if not plant then return end
	if not Growth.isMature(plant.at, os.time(), plant.tier, Config.Growth, growthMultOf(p)) then
		local left = math.max(1, math.ceil(Growth.secondsToMature(plant.at, os.time(), plant.tier, Config.Growth, growthMultOf(p))))
		refuse(plr, "Still growing — ready in " .. tostring(left) .. "s")
		return
	end
	-- Refraction roll: a fresh rng per harvest, seeded with a SALT the client cannot know. The rest of the
	-- seed (the second, the socket, the UserId) is all in the client's hands, and a probe predicted 48 of 48
	-- rolls from it, so a script could click only on the second that rolls Mythic and farm the leaderboard.
	-- The salt is drawn per harvest (a salt fixed for the session is a constant the client could solve for
	-- from the tiers it sees) from `rollSalt`, which lives only in this script (robloxemu/check_growacrystal_salt).
	local salt = rollSalt:NextInteger(0, Rarity.SEED_MOD - 1)
	local rng = Rng.new(Rarity.rollSeed(os.time(), socketId, plr.UserId, salt))
	local finalTier = Rarity.roll(plant.tier, luckMultOf(p), rng, Config.Refraction, Config.MaxTier)
	local dust = Economy.harvestDust(finalTier, p.passes.DoubleDust == true, Config.Economy)
	local pointsBefore = Board.metricOfDust(p.totalDust, BC)
	p.dust += dust
	-- The board counts the harvest at its UN-doubled value: a paid pass may double what the player spends, never
	-- their place on the board (owner decision, DECIDED 2026-09-30 (owner: take recommended); EYECANDY.md §11;
	-- robloxemu/check_growacrystal_pass.luau).
	p.totalDust += Economy.harvestDust(finalTier, false, Config.Economy)
	-- the board's tie-break: when the points last rose (a code's or the Geode's dust never gets here)
	if Board.metricOfDust(p.totalDust, BC) > pointsBefore then p.boardAt = os.time() end
	Codex.discover(p.codex, finalTier)
	p.plants[socketId] = nil
	local last = harvests[plr]
	harvests[plr] = { n = (last and last.n or 0) + 1, socket = socketId, seed = plant.tier, tier = finalTier }
	refreshSocketVisual(plr, socketId)
	applyPlotBudget(plr)
	pushState(plr)
end

-- ── Buy / Geode / Redeem ──────────────────────────────────────────────────────
BuyEvent.OnServerEvent:Connect(function(plr, kind, arg)
	local p = profiles[plr]
	if not p then return end
	local ok, reason = false, nil
	if kind == "seed" then
		local tier = tonumber(arg)
		if tier and Config.Tiers[tier] then
			ok, reason = Economy.buySeed(p, tier, Config.Economy)
			if not ok then refuse(plr, seedRefusal(tier, reason)) end
		end
	elseif kind == "chamber" then
		local cost = Economy.chamberCost(p.chambers, Config.Economy)
		if p.saveState == "locked" or p.saveState == "retry" then
			-- this copy may be replaced by the record when the retry lands (retryLoad), and a built terrace cannot be
			-- taken back down; dust, seeds and plants can
			ok, reason = false, "wait"
		else
			ok, reason = Economy.buyChamber(p, Config.Economy)
		end
		if reason == "wait" then
			refuse(plr, Config.Save.Text.WaitChamber)
		elseif ok then
			buildChambers(plr)
			clearOwnedLocks(plr)      -- the rubble over the new terrace goes
			refreshChamberLabels(plr) -- and its riser stops advertising a price
		elseif reason == "max" then
			refuse(plr, "Every chamber is already open")
		else
			refuse(plr, "Not enough Gem Dust: chamber " .. tostring(p.chambers + 1) .. " costs " .. tostring(cost))
		end
	elseif kind == "booster" then
		if arg == "Luck" or arg == "Growth" then
			local level = if arg == "Luck" then p.luckLevel else p.growthLevel
			local cost = Economy.boosterCost(level, Config.Boosters[arg])
			ok, reason = Economy.buyBooster(p, arg, Config.Boosters)
			if not ok then
				if reason == "max" then
					refuse(plr, arg .. " is already at its max level")
				else
					refuse(plr, "Not enough Gem Dust: " .. arg .. " Lv" .. tostring(level + 1) .. " costs " .. tostring(cost))
				end
			end
		end
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
	local ok, reason, tier = Geode.crack(p, os.time(), Config.Geode) -- deducts dust + sets lastGeodeWeek
	if not (ok and tier) then
		if reason == "already" then
			refuse(plr, "This week's Geode is cracked — back next week")
		else
			refuse(plr, "Not enough Gem Dust: the Geode costs " .. tostring(Config.Geode.CostDust))
		end
		return
	end
	p.seeds[tier] = (p.seeds[tier] or 0) + 1 -- grant an exclusive seed of that tier
	-- Atomic flush: geode is once-per-week — if it didn't persist, roll back everything
	-- so a crash can't leave dust spent / week burned without the reward. A session that can NEVER save
	-- ("nostore") keeps it for the session: nothing from it persists, so there is nothing to duplicate.
	if p.saveState ~= "nostore" and not saveProfile(plr, false) then
		p.dust += Config.Geode.CostDust
		p.lastGeodeWeek = prevWeek
		p.seeds[tier] -= 1
		pushState(plr)
		refuse(plr, "Couldn't save — nothing spent, try again")
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
	-- phantom reward the DataStore never recorded. A session that can NEVER save ("nostore": no DataStore, or
	-- Studio without API access) keeps the grant for the session: nothing from it persists, the reward included,
	-- so there is nothing to duplicate; the player was told at join (MARKETING.md's clips are staged this way).
	if p.saveState ~= "nostore" and not saveProfile(plr, false) then
		p.redeemed[code] = nil
		if reward.dust then p.dust -= reward.dust end
		if reward.seedTier then p.seeds[reward.seedTier] -= 1 end
		return { ok = false, reason = "retry" }
	end
	pushState(plr)
	return { ok = true, reason = "ok", dust = reward.dust, seedTier = reward.seedTier }
end

-- ── The highscore board: public + friends (docs/complete-game-standard.md §3) ─────────────────────────
-- One physical board per cavern, on the entrance wall behind the spawn (Cavern.board), drawn by the server for the
-- cavern's owner. Its ProximityPrompt switches it between everyone (the store's top 10, read at most once per
-- Config.Board.PublicCacheSeconds for the whole server) and the owner's Roblox friends (fetched only when asked,
-- capped, cached, every call pcall'd, the score reads throttled by one token bucket for the whole server). The
-- HUD's panel gets the same public rows, names included, so no client looks a name up.
-- Names: resolved here, cached for the life of the server, never saved anywhere.
local names = {}            -- [userId] = name
local boards = {}           -- [player] = { part, rows = { TextLabel }, modeLabel, note, prompt, mode, job }
local publicSorted = nil    -- the last GetSortedAsync page: { { userId, value } }, nil before the first read
local publicRows = {}       -- the same, drawn: { { rank, userId, name, score } } (also the HUD panel's payload)
local friendsCache = Board.newCache(BC.FriendsCacheSeconds)  -- [userId] = { ids = { number } }
local friendsFailed = Board.newCache(BC.FriendsRetrySeconds) -- [userId] = true: a fetch failed, wait before retrying
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, tick())

local function nameOf(uid: number): string
	local n = names[uid]
	if n then return n end
	local online = Players:GetPlayerByUserId(uid)
	if online then
		names[uid] = online.Name
		return online.Name
	end
	local ok, res = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
	if ok and type(res) == "string" then
		names[uid] = res
		return res
	end
	return "Miner " .. tostring(uid) -- not cached: the next refresh tries again
end

-- A player on this server is ranked by their live points, never by a store read.
local function liveValue(plr): number
	local p = profiles[plr]
	if not p then return 0 end
	local points = Board.metricOfDust(p.totalDust, BC)
	if points <= 0 then return 0 end
	return Board.encode(points, p.boardAt, BC)
end

local function drawRows(b, view, you: number?)
	for i, label in b.rows do
		local r = view and view.rows[i]
		if r then
			local mark = if r.you then "  (you)" else ""
			label.Text = string.format("%d.  %s%s  —  💎 %s", r.rank, nameOf(r.userId), mark, Board.formatScore(r.metric, BC))
			label.TextColor3 = if r.userId == you then Color3.fromRGB(255, 215, 90) else Color3.fromRGB(225, 232, 245)
		else
			label.Text = ""
		end
	end
	b.note.Text = (view and view.note) or ""
end

local function drawPublic(plr)
	local b = boards[plr]
	if not b or b.mode ~= "public" then return end
	b.modeLabel.Text = BC.Text.Everyone .. "  ·  " .. BC.Text.Subtitle
	if not orderedLB then
		drawRows(b, { rows = {}, note = BC.Text.Offline }, nil)
	elseif publicSorted == nil then
		drawRows(b, { rows = {}, note = BC.Text.Loading }, nil)
	else
		drawRows(b, Board.publicView(publicSorted, BC), plr.UserId)
	end
end

-- One GetSortedAsync for the whole server, at most once per PublicCacheSeconds (the loop at the bottom). A failed
-- read keeps the rows the boards already show.
local function refreshPublic()
	if not orderedLB then return end
	local ok, page = pcall(function() return orderedLB:GetSortedAsync(false, BC.PublicRows) end)
	if not ok or not page then return end
	local okp, entries = pcall(function() return page:GetCurrentPage() end)
	if not okp or type(entries) ~= "table" then return end
	local sorted = {}
	for _, e in entries do
		local uid = Board.userIdOf(tostring(e.key))
		if uid and type(e.value) == "number" then table.insert(sorted, { userId = uid, value = e.value }) end
	end
	publicSorted = sorted
	local rows = {}
	for _, r in Board.publicView(sorted, BC).rows do
		table.insert(rows, { rank = r.rank, userId = r.userId, name = nameOf(r.userId), score = Board.formatScore(r.metric, BC) })
	end
	publicRows = rows
	for _, plr in Players:GetPlayers() do
		drawPublic(plr)
		LeaderboardEvent:FireClient(plr, publicRows)
	end
end

-- The owner's friends list: pages of GetFriendsAsync until FriendsCap, names kept from the pages (no lookups).
local function fetchFriends(uid: number): any
	local ok, pages = pcall(function() return Players:GetFriendsAsync(uid) end)
	if not ok or pages == nil then return nil end
	local ids = {}
	while #ids < BC.FriendsCap do
		local okp, page = pcall(function() return pages:GetCurrentPage() end)
		if not okp or type(page) ~= "table" then
			if #ids == 0 then return nil end
			break
		end
		for _, f in page do
			if #ids >= BC.FriendsCap then break end
			local id = tonumber(f.Id)
			if id then
				table.insert(ids, id)
				if type(f.Username) == "string" then names[id] = f.Username end
			end
		end
		if pages.IsFinished or #ids >= BC.FriendsCap then break end
		local oka = pcall(function() pages:AdvanceToNextPageAsync() end)
		if not oka then break end
	end
	return { ids = ids }
end

local function readBudgetLow(): boolean
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return ok and type(n) == "number" and n < BC.BudgetReserve
end

-- One friend's stored value: live if they are on this server, else cached, else ONE throttled store read.
local function friendValue(fid: number): number
	local fp = Players:GetPlayerByUserId(fid)
	if fp and profiles[fp] then return liveValue(fp) end
	local cached = Board.cacheGet(scoreCache, fid, tick())
	if cached ~= nil then return cached end
	if not orderedLB then return 0 end
	while not Board.take(readLimiter, tick()) or readBudgetLow() do
		task.wait(1 / BC.ReadsPerSecond)
	end
	local ok, v = pcall(function() return orderedLB:GetAsync(Board.key(fid)) end)
	local value = if ok and type(v) == "number" then v else 0
	if ok then Board.cachePut(scoreCache, fid, value, tick()) end
	return value
end

local function drawFriends(plr)
	local b = boards[plr]
	if not b or b.mode ~= "friends" then return end
	local job = {}
	b.job = job
	b.modeLabel.Text = BC.Text.Friends .. "  ·  " .. BC.Text.Subtitle
	drawRows(b, { rows = {}, note = BC.Text.Loading }, nil)
	local uid = plr.UserId
	local list = Board.cacheGet(friendsCache, uid, tick())
	local failed = false
	if list == nil then
		if Board.cacheHas(friendsFailed, uid, tick()) then
			failed = true
		else
			list = fetchFriends(uid) -- yields
			if list then
				Board.cachePut(friendsCache, uid, list, tick())
			else
				failed = true
				Board.cachePut(friendsFailed, uid, true, tick())
			end
		end
	end
	local function current(): boolean
		return boards[plr] == b and b.mode == "friends" and b.job == job
	end
	if not current() then return end
	local ids = if list then list.ids else {}
	local values = { [uid] = liveValue(plr) }
	local checked = 0
	local function draw()
		drawRows(b, Board.friendsView(uid, values, { friendCount = #ids, checked = checked, failed = failed }, BC), uid)
	end
	draw()
	for _, fid in ids do
		local v = friendValue(fid) -- may wait on the read limiter
		if not current() then return end
		values[fid] = v
		checked += 1
		if checked % 10 == 0 or checked == #ids then draw() end
	end
end

local function toggleBoard(plr)
	local b = boards[plr]
	if not b then return end
	b.mode = if b.mode == "public" then "friends" else "public"
	b.job = nil
	b.prompt.ActionText = if b.mode == "public" then BC.Text.ShowFriends else BC.Text.ShowEveryone
	if b.mode == "public" then drawPublic(plr) else task.spawn(drawFriends, plr) end
end

local function buildBoard(plr)
	local folder = plotFolders[plr]
	local idx = playerPlot[plr]
	if not folder or idx == nil then return end
	local def = Cavern.board(Config)
	local part = Instance.new("Part")
	part.Name = "Leaderboard"
	part.Anchored = true
	part.CanTouch = false
	part.Size = Vector3.new(def.size.x, def.size.y, def.size.z)
	part.CFrame = CFrame.new(plotOrigin(idx) + Vector3.new(def.position.x, def.position.y, def.position.z))
	part.Material = Enum.Material.Slate
	part.Color = Color3.fromRGB(30, 32, 44)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Back -- the part's +Z face: into the cavern, at the spawn (Cavern.board)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local function label(name: string, y: number, h: number, font, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0.05, 0, y, 0)
		l.Size = UDim2.new(0.9, 0, h, 0)
		l.Font = font
		l.TextScaled = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color
		l.Text = ""
		l.Parent = gui
		return l
	end
	local title = label("Title", 0.03, 0.11, Enum.Font.GothamBlack, Color3.fromRGB(255, 215, 90))
	title.Text = "🏆 " .. BC.Text.Title
	title.TextXAlignment = Enum.TextXAlignment.Center
	local modeLabel = label("Mode", 0.145, 0.06, Enum.Font.GothamMedium, Color3.fromRGB(170, 200, 230))
	modeLabel.TextXAlignment = Enum.TextXAlignment.Center
	local rows = {}
	for i = 1, BC.PublicRows do
		rows[i] = label("Row" .. i, 0.22 + (i - 1) * 0.065, 0.058, Enum.Font.GothamMedium, Color3.fromRGB(225, 232, 245))
	end
	local note = label("Note", 0.885, 0.09, Enum.Font.Gotham, Color3.fromRGB(190, 205, 225))
	note.TextXAlignment = Enum.TextXAlignment.Center
	gui.Parent = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ObjectText = BC.Text.Object
	prompt.ActionText = BC.Text.ShowFriends
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = BC.PromptDistance
	prompt.Parent = part
	-- A cavern is sealed, so only its owner can reach this prompt; anyone else is told why, never ignored.
	prompt.Triggered:Connect(function(who)
		if who ~= plr then
			refuse(who, BC.Text.NotYours)
			return
		end
		toggleBoard(plr)
	end)
	part.Parent = folder
	boards[plr] = { part = part, rows = rows, modeLabel = modeLabel, note = note, prompt = prompt, mode = "public" }
	drawPublic(plr)
end

-- ── A load that could not take the lock tries again (standard §1; robloxemu/check_growacrystal_rejoin.luau) ──
-- "locked": when the other server's lock has expired AND nobody has written the record since this session read it
-- (same jobId, token and lockUntil: every write of every version of this game sets lockUntil), what was played here
-- continues that record, so this session takes the lock and saves it. If the record changed, it is newer than the
-- copy played here: this session loads it and rebuilds the cavern to it. "retry" (the load call failed) loads the
-- record as soon as a call succeeds. Either way the player is told once while waiting and once when it is over.
local function reloadInto(plr, p, d)
	local base = defaultProfile()
	for _, k in { "dust", "seeds", "chambers", "luckLevel", "growthLevel", "plants", "codex", "redeemed",
		"lastGeodeWeek", "totalDust", "boardAt", "boardMetric", "passes" } do
		p[k] = base[k]
	end
	applyData(p, d)
	-- chambers only grow (a chamber is never bought while waiting), so building up is enough
	buildChambers(plr)
	clearOwnedLocks(plr)
	refreshChamberLabels(plr)
	pushState(plr)
end

local function retryLoad(plr)
	local p = profiles[plr]
	if not p or not store or p.retrying then return end
	p.retrying = true
	local token = HttpService:GenerateGUID(false)
	local outcome, fresh, seen = nil, nil, nil
	local ok = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			outcome, fresh, seen = "wait", nil, nil
			if (tonumber(old.lockUntil) or 0) > now and old.jobId ~= game.JobId then
				fresh, seen = old.data, lockOf(old) -- still held: a failed load now at least knows the profile
				return nil
			end
			local s = p.lockSeen
			if p.saveState == "locked" and s and old.jobId == s.jobId and old.session == s.session and old.lockUntil == s.lockUntil then
				outcome = "resume"
			else
				outcome, fresh = "reload", old.data
			end
			old.jobId = game.JobId
			old.session = token
			old.lockUntil = now + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	p.retrying = false
	if not ok then return end
	if profiles[plr] ~= p then
		-- left while the call was in flight: give back a lock this session has just taken
		if outcome ~= "wait" then
			pcall(function()
				store:UpdateAsync(key(plr.UserId), function(old)
					if type(old) ~= "table" or old.session ~= token then return nil end
					old.lockUntil = 0
					return old
				end)
			end)
		end
		return
	end
	if outcome == "wait" then
		if p.saveState == "retry" then
			reloadInto(plr, p, fresh)
			p.saveState, p.lockSeen = "locked", seen
		end
		return
	end
	if outcome == "reload" then reloadInto(plr, p, fresh) end
	p.session, p.canSave, p.saveState, p.lockSeen = token, true, "ok", nil
	refuse(plr, if outcome == "resume" then Config.Save.Text.Resumed else Config.Save.Text.Loaded)
	saveProfile(plr, false)
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
	buildBoard(plr)
	LeaderboardEvent:FireClient(plr, publicRows)

	-- SPAWN INSIDE THE CAVERN, and make Roblox agree.
	--
	-- Setting the root part's CFrame on CharacterAdded is not enough on its own. With no
	-- SpawnLocation anywhere, Roblox drops the character above the highest ground at the origin -
	-- which, now that the cavern is a sealed shell 48 studs tall, is its ROOF. Measured in a real
	-- play session: the player stood at y=51 on Plot_0.CeilFront, 55 studs from the nearest
	-- socket against a ClickDetector range of 32. They could see nothing and reach nothing. The
	-- core loop was unreachable again, for a completely different reason than the unparented
	-- sockets, and the emulator cannot see this because it has no spawn behaviour and no gravity.
	--
	-- A real SpawnLocation inside the cavern, assigned as this player's RespawnLocation, is what
	-- makes the engine put them where the game means to. The CFrame set stays as well, because it
	-- also fixes which way they are facing - the identity frame looks down -Z, i.e. at the
	-- entrance wall, and the cavern is the other way.
	local sp = Cavern.spawn(Config)
	local origin = plotOrigin(idx)
	local at = origin + Vector3.new(sp.position.x, sp.position.y, sp.position.z)

	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "Spawn_" .. plr.UserId
	spawnPad.Size = Vector3.new(6, 1, 6)
	spawnPad.Position = at - Vector3.new(0, 4, 0) -- the pad is under the feet, not at the root
	spawnPad.Anchored = true
	spawnPad.CanCollide = false
	spawnPad.Transparency = 1
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.Parent = plotFolders[plr]  -- inside the plot, so teardown takes it too
	plr.RespawnLocation = spawnPad

	-- WAIT FOR THE ENGINE TO FINISH BEFORE WRITING THE CFrame.
	--
	-- Measured in Roblox Studio on 2026-09-10 (fork-tower/STUDIO.md, robloxemu/SPAWN-ORDER.md):
	-- CharacterAdded fires while the model is still UNPARENTED with its root at the world origin,
	-- and ONE FRAME LATER the engine parents it AND places it on the spawn - discarding, with no
	-- error and no warning, anything the handler wrote in between.
	--
	-- The previous version wrote the CFrame twice, the second time from a `task.defer`, on the
	-- theory that the engine finishes "after this handler returns" so the last write wins. It does
	-- finish after the handler returns, but `task.defer` resumes at the end of the CURRENT
	-- resumption cycle - the same frame - so BOTH writes landed before the engine's step and both
	-- were thrown away. Measured against this build by replaying the recorded order
	-- (robloxemu/check_crystal_spawn.luau): the player ended at 0.00, 3.01, -6.00 facing 0, 0, -1
	-- - a stud low and turned exactly around, staring at the entrance wall with all six sockets,
	-- 11.9 studs away, behind their back. The RespawnLocation pad below is what stops them landing
	-- on the roof; it cannot fix which way they face, because the engine spawns them along the
	-- pad's own axis and the pad is not rotated.
	--
	-- `char.Parent` going non-nil is the signal that the engine has finished: the trace shows the
	-- parent and the placement arriving in the same frame. The loop is bounded so a character that
	-- never arrives cannot park this handler for the life of the session, and it is a no-op on the
	-- join path below, where the character is already in the world.
	local function place(char)
		local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
		local frames = 0
		while char.Parent == nil and frames < 300 do
			task.wait(1 / 60)
			frames += 1
		end
		-- No `if hrp.Parent` guard. The player can leave while this is parked, but then their
		-- character is destroyed and writing a CFrame to a destroyed Part is a no-op - measured,
		-- and true in Roblox too - so the guard could not be made to fail and was removed rather
		-- than left as a line no test can kill.
		hrp.CFrame = CFrame.new(at, at + Vector3.new(sp.look.x, sp.look.y, sp.look.z))
	end
	plr.CharacterAdded:Connect(place)
	if plr.Character then place(plr.Character) end

	pushState(plr)
	-- a session that cannot save says so at once, never silently (standard §1; check_growacrystal_rejoin)
	local pj = profiles[plr] -- nil if they left while place() waited for the character
	local why = pj and ({ nostore = Config.Save.Text.NoStore, locked = Config.Save.Text.Locked,
		retry = Config.Save.Text.LoadRetry })[pj.saveState]
	if why then refuse(plr, why) end
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
	crystals[plr] = nil
	local idx = playerPlot[plr]
	playerPlot[plr] = nil
	if idx ~= nil then usedPlots[idx] = nil end
	profiles[plr] = nil
	selected[plr] = nil
	harvests[plr] = nil
	boards[plr] = nil -- the board itself went with the plot folder
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
		for _, plr in ipairs(Players:GetPlayers()) do
			local p = profiles[plr]
			if p and (p.saveState == "locked" or p.saveState == "retry") then
				task.spawn(retryLoad, plr)
			else
				saveProfile(plr, false)
			end
		end
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
				applyPlotBudget(plr)
			end
		end
	end
end)
task.spawn(function()
	while true do refreshPublic(); task.wait(BC.PublicCacheSeconds) end
end)

print("[Crystal] Grow a Crystal lastet. WorldSeed=" .. Config.WorldSeed)
