-- +1 JUMP EVERY STEP — Sky Temple Obby (server, autoritativt)
-- Havner i ServerScriptService. All logikk er styrt av ReplicatedStorage.Config og de
-- rene modulene (Progression/TowerGen/Codes) som er enhets-testet med luau-CLI.
--
-- Kjerne-idé: å tråkke en NY plattform gir +1 jump power (server-autoritativt). Mer
-- jump power => høyere Humanoid.JumpHeight => klarer høyere etasjer. REBIRTH nullstiller
-- jump power men banker en permanent multiplier. Alt lagres pr spiller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService") -- GenerateGUID only (session-eier-token); ingen HTTP

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("Progression"))
local TowerGen = require(ReplicatedStorage:WaitForChild("TowerGen"))
local Codes = require(ReplicatedStorage:WaitForChild("Codes"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))

-- ÉN klokke for klatre-vakta og topplista-cachene. os.clock() måler CPU-tid i Roblox (en rolig server teller
-- nesten ikke), så den er feil her. GetServerTimeNow er veggklokka; tick() er reserven for motorer (og den
-- hodeløse harnessen) som ikke har den. Sjekket én gang ved oppstart (samme mønster som fork-tower).
local clock: () -> number
do
	local ok, t = pcall(function()
		return (workspace :: any):GetServerTimeNow()
	end)
	clock = if ok and type(t) == "number" then function()
		return (workspace :: any):GetServerTimeNow()
	end else tick
end

-- Visuell polish (kun kode, additiv): lys, luftig sky-tempel-rigg + post-fx (bloom/sunrays).
Fx.applyLighting(Fx.Presets.Temple)

-- Hoppspor: gir hver spillerkarakter en Trail så hoppene leser som «fancy» i klipp/thumbnails.
Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		local root = char:WaitForChild("HumanoidRootPart", 5)
		if root then
			Fx.trail(root, Color3.fromRGB(160, 210, 255), 0.45)
		end
	end)
end)

local genCfg = { Tower = Config.Tower, Jump = Config.Jump, WorldSeed = Config.WorldSeed }

-- Fail-fast runtime-vakt for reachability-invarianten (samme som Progression.spec, men
-- kjørt ved oppstart): hvis noen endrer Config.Jump/Tower slik at en etasje IKKE lenger
-- er klarerbar for en fersk (ingen rebirth) spiller, ROP høyt i Output. Bygger fortsatt
-- (bricker ikke et live spill på en tunings-tabbe), men gjør regresjonen umulig å overse.
do
	local firstBad = nil
	for t = 1, 1000 do
		if not Progression.isTierReachable(t, Config.Tower, Config.Jump) then
			firstBad = t
			break
		end
	end
	if firstBad then
		warn(string.format(
			"[Plus1] ADVARSEL: reachability-invarianten BRUTT ved etasje %d — StepHeight overstiger trygt hopp. Juster Config.Tower/Jump. Tårnet kan bli uklarerbart!",
			firstBad))
	end
end

-- ── Remotes ─────────────────────────────────────────────────────────────────
local remotes = Instance.new("Folder")
remotes.Name = "Plus1Remotes"
remotes.Parent = ReplicatedStorage
local function mkRemote(className: string, name: string): Instance
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end
local StateEvent = mkRemote("RemoteEvent", "State")       -- server -> klient: spiller-tilstand
local RebirthEvent = mkRemote("RemoteEvent", "Rebirth")   -- klient -> server: be om rebirth
local RedeemFunc = mkRemote("RemoteFunction", "Redeem")   -- klient -> server: løs inn kode
local LeaderboardEvent = mkRemote("RemoteEvent", "Leaderboard") -- server -> klient: topp 10 (HUD-panelet)
local BoardEvent = mkRemote("RemoteEvent", "Board") -- server -> klient: den fysiske tavlas visning (per spiller)

-- ── Data ────────────────────────────────────────────────────────────────────
-- GetDataStore RAISES in a place that has not been published to the web, and again when
-- "Enable Studio Access to API Services" is off. Unwrapped, that error killed this whole server
-- script at load - no tower, no remotes, no game - which is why this one could not be opened in
-- Studio at all without publishing first. Saving is what should degrade, not the game; every
-- write path already checks `store`.
local function tryStore(fn, what)
	if not Config.Save.Enabled then return nil end
	local ok, ds = pcall(fn)
	if ok then return ds end
	warn("[Plus1] " .. what .. " datastore unavailable (" .. tostring(ds)
		.. ") - the game runs, progress will NOT be saved this session.")
	return nil
end

local store = tryStore(function() return DataStoreService:GetDataStore(Config.Save.Store) end, "profiles")
local orderedLB = tryStore(function() return DataStoreService:GetOrderedDataStore(Config.Save.Leaderboard) end, "leaderboard")

-- Per-spiller runtime-tilstand (i minne). `saved` = det som skrives til DataStore.
type Profile = {
	frontierTier: number,  -- høyeste etasje spilleren har et fotfeste på (double-count-gate)
	frontierIdx: number,   -- + plattform-indeks i den etasjen
	jumpPower: number,      -- faktisk opptjent jump power (climb + koder)
	rebirths: number,
	bestTier: number,       -- høyeste etasje NOENSINNE (leaderboard), overlever rebirth
	bestTierAt: number,     -- os.time() da bestTier ble nådd (topplista: uavgjort til den som var FØRST)
	boardTier: number,      -- bestTier som sist ble skrevet til topplista (skriv bare når den stiger)
	redeemed: { [string]: boolean },
	passes: { [string]: boolean },
	canSave: boolean,       -- load-suksess-sentinel: ikke lagre hvis lasten feilet
	session: string?,       -- eier-token denne økta skrev ved lasten; en lagring lander bare om posten har den
}

local profiles: { [Player]: Profile } = {}

local function defaultProfile(): Profile
	return {
		frontierTier = 0, frontierIdx = 0,
		jumpPower = Config.Jump.StartJumpPower,
		rebirths = 0, bestTier = 0, bestTierAt = 0, boardTier = 0,
		redeemed = {}, passes = {}, canSave = false, session = nil,
	}
end

local function key(userId: number): string
	return "u_" .. userId
end

-- Last + soft session-lock (anti-dupe). Viktig: vi laster ALLTID ekte data (aldri
-- default) — selv om en annen fersk session holder låsen. Da spiller vi bare READ-ONLY
-- (canSave=false) så vi ikke klobber den andre. Låsen fornyes av autosave; crasher en
-- session, utløper låsen etter SessionLockSeconds og neste rejoin overtar. Så en legit
-- spiller ser aldri jump=0 ved rask rejoin, og data korrumperes aldri.
local function loadProfile(plr: Player): Profile
	local p = defaultProfile()
	if not store then
		p.canSave = false -- Studio uten API: kjør, men ikke lagre
		return p
	end
	local token = HttpService:GenerateGUID(false)
	local acquired = false
	local ok, err = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			local now = os.time()
			local lockedUntil = tonumber(old.lockUntil) or 0
			local lockedByOther = lockedUntil > now and old.jobId ~= game.JobId
			-- Kopier lagrede felt inn i profilen (ALLTID — også ved lås)
			if old.data then
				local d = old.data
				p.frontierTier = tonumber(d.frontierTier) or 0
				p.frontierIdx = tonumber(d.frontierIdx) or 0
				p.jumpPower = tonumber(d.jumpPower) or 0
				p.rebirths = tonumber(d.rebirths) or 0
				p.bestTier = tonumber(d.bestTier) or 0
				p.bestTierAt = tonumber(d.bestTierAt) or 0
				p.boardTier = tonumber(d.boardTier) or 0
				p.redeemed = (type(d.redeemed) == "table") and d.redeemed or {}
				p.passes = (type(d.passes) == "table") and d.passes or {}
			end
			if lockedByOther then
				acquired = false
				return old -- respekter den andre live-sessionen; ikke rør låsen
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
		warn("[Plus1] load failed for " .. plr.Name .. ": " .. tostring(err))
	else
		p.canSave = acquired
		p.session = if acquired then token else nil
		if not acquired then
			warn("[Plus1] " .. plr.Name .. " lastet READ-ONLY (låst av annen session); progresjon denne økta lagres ikke.")
		end
	end
	-- Lagret før 2026-09-30: beste etasje uten tidspunkt. Når den ble nådd er ukjent, så den stemples med
	-- denne økta (den kommer tilbake på topplista ved neste lagring, bak alle som nådde samme etasje før).
	if p.bestTier > 0 and p.bestTierAt <= 0 then
		p.bestTierAt = os.time()
	end
	return p
end

-- Topplista (OrderedDataStore): skriv bare når beste etasje har steget siden sist, og aldri lavere enn det
-- som står der (Board.keepHigher avbryter). Uavgjort vinner den som nådde etasjen først (Board.encode).
local function writeBoard(p: Profile, userId: number)
	if not orderedLB or p.bestTier <= p.boardTier then return end
	local tier = p.bestTier
	local value = Board.encode(tier, p.bestTierAt, Config.Board)
	local ok = pcall(function()
		orderedLB:UpdateAsync(key(userId), function(old)
			return Board.keepHigher(old, value)
		end)
	end)
	if ok then
		p.boardTier = tier -- også når keepHigher avbrøt: det som står der er minst like høyt
	end
end

-- Returnerer true når skrivingen faktisk landet (kode-innløsning ruller tilbake ellers).
local function saveProfile(plr: Player, releaseLock: boolean): boolean
	local p = profiles[plr]
	if not p or not p.canSave or not store then return false end
	-- EIERSKAP: skrivingen lander bare hvis posten fortsatt bærer tokenet denne øktas last skrev. Har en annen
	-- økt tatt posten siden (låsen vår gikk ut under et avbrudd, eller en sen BindToClose-skriving), avbrytes
	-- den (nil) — autosave, leave og kode-flush likt. `lost` settes på hvert kall: transformen kan kjøres flere
	-- ganger. Mønsteret er fork-tower sitt (`old.session`).
	local lost = false
	local ok = pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			if old.session ~= p.session then
				lost = true
				return nil
			end
			lost = false
			old.data = {
				frontierTier = p.frontierTier, frontierIdx = p.frontierIdx,
				jumpPower = p.jumpPower, rebirths = p.rebirths, bestTier = p.bestTier,
				bestTierAt = p.bestTierAt, boardTier = p.boardTier,
				redeemed = p.redeemed, passes = p.passes,
			}
			old.jobId = game.JobId
			old.lockUntil = releaseLock and 0 or (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	if lost then
		-- En annen økt eier profilen nå. Ingenting denne gjør blir tatt vare på herfra, så den slutter å skrive
		-- (og Redeem, som krever canSave, slutter å gi).
		p.canSave = false
		warn("[Plus1] " .. plr.Name .. ": en nyere økt har tatt over profilen; progresjon denne økta lagres ikke lenger.")
		return false
	end
	if not ok then return false end
	writeBoard(p, plr.UserId)
	return true
end

-- ── Tårn (delt, én instans for hele serveren) ───────────────────────────────
local towerFolder = Instance.new("Folder")
towerFolder.Name = "Tower"
towerFolder.Parent = workspace

local BASE_POS = Vector3.new(0, Config.Tower.BaseY, 0) -- 8; himmel-båndene regner høyde fra samme tall
type Built = { origin: Vector3, top: Vector3, parts: { BasePart } }
local builtTiers: { [number]: Built } = {}
local highestBuilt = 0

local function makePlatform(pos: Vector3, size: number, tier: number, idx: number): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(size, 1, size)
	part.Position = pos
	part.Material = Enum.Material.SmoothPlastic
	-- Fargen skifter sakte med etasjen (visuell høyde-følelse)
	local h = (tier * 12) % 360
	part.Color = Color3.fromHSV(h / 360, 0.5, 0.9)
	part:SetAttribute("Tier", tier)
	part:SetAttribute("Idx", idx)
	part.Name = "P_" .. tier .. "_" .. idx
	part.Parent = towerFolder
	return part
end

-- Dekorativ (ufarlig) hindring — snurrer for liv. Lethal hindringer = v2-toggle.
local function makeHazard(pos: Vector3, kind: string): BasePart
	local h = Instance.new("Part")
	h.Anchored = true
	h.CanCollide = false
	h.Size = Vector3.new(2, 2, 2)
	h.Position = pos + Vector3.new(0, 3, 0)
	h.Material = Enum.Material.Neon
	h.Color = Color3.fromRGB(255, 80, 80)
	h.Name = "Hazard_" .. kind
	h.Parent = towerFolder
	return h
end

local grantStep -- forward-deklarasjon (Touched-handler bruker den)
-- Klatre-vakt per spiller (Progression.newGuard): høyden til siste krediterte plattform (eller der serveren
-- satte spilleren: frontier ved join, sokkelen ved rebirth) og en bøtte med lovlig stigning. Se Config.Guard.
local guards: { [Player]: any } = {}

local function buildTier(t: number)
	if builtTiers[t] then return end
	if t > 1 and not builtTiers[t - 1] then buildTier(t - 1) end
	local origin = (t == 1) and BASE_POS or builtTiers[t - 1].top
	local gen = TowerGen.tier(t, genCfg)
	local parts = {}
	for i, p in ipairs(gen.platforms) do
		local pos = origin + Vector3.new(p.dx, p.dy, p.dz)
		local part = makePlatform(pos, p.size, t, i)
		part.Touched:Connect(function(hit)
			grantStep(hit, t, i, part)
		end)
		parts[i] = part
	end
	for _, hz in ipairs(gen.hazards) do
		makeHazard(origin + Vector3.new(hz.dx, hz.dy, hz.dz), hz.kind)
	end
	builtTiers[t] = { origin = origin, top = origin + Vector3.new(gen.exitDx, gen.exitHeight, gen.exitDz), parts = parts }
	if t > highestBuilt then highestBuilt = t end
end

-- Bygg startsokkel (etasje 0-plattform) å spawne på
local basePad = Instance.new("Part")
basePad.Anchored = true
basePad.Size = Vector3.new(24, 2, 24)
basePad.Position = BASE_POS - Vector3.new(0, 1, 0)
basePad.Material = Enum.Material.Slate
basePad.Color = Color3.fromRGB(120, 120, 140)
basePad.Name = "BasePad"
basePad.Parent = towerFolder

-- SPAWN-PUNKT — vi PEKER motoren, den skal ikke gjette.
-- Uten en enabled SpawnLocation slipper Roblox karakteren over det HØYESTE kolliderbare
-- underlaget over verdens-origo. I dag er det sokkelen, så spillet så riktig ut — men det var
-- FLAKS, ikke konstruksjon: målt over 5000 WorldSeed-verdier legger TowerGen en etasje-1-
-- plattform rett over origo i 410 av dem (8,2 %). Og siden `isBeyondFrontier` er monoton, ville
-- en spiller som ble sluppet på plattform 2 ALDRI kunne tjene +1 for plattform 1 — for resten av
-- lagringen. Ett tall i Config skal ikke kunne gjøre det, så vi bygger et ekte spawn-punkt.
-- Topp-flaten flukter med sokkelens topp (y = 8), så ingen spawner inni eller over sokkelen.
local spawnPad = Instance.new("SpawnLocation")
spawnPad.Name = "TempleSpawn"
spawnPad.Anchored = true
spawnPad.Size = Vector3.new(12, 1, 12)
spawnPad.Position = BASE_POS - Vector3.new(0, 0.5, 0)
spawnPad.Neutral = true
spawnPad.Duration = 0 -- ingen forcefield: obby-en har ingen kamp å beskytte mot
spawnPad.Material = Enum.Material.Neon
spawnPad.Color = Color3.fromRGB(160, 210, 255)
spawnPad.Parent = towerFolder

buildTier(1)

-- ── Spiller-tilstand -> Humanoid + HUD ──────────────────────────────────────
local function multiplierOf(p: Profile): number
	return Progression.rebirthMultiplier(p.rebirths, Config.Rebirth)
end

local function applyJump(plr: Player)
	local p = profiles[plr]
	if not p then return end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.UseJumpPower = false
		hum.JumpHeight = Progression.jumpHeight(p.jumpPower, multiplierOf(p), Config.Jump)
		hum.WalkSpeed = Config.WalkSpeed
	end
end

local function pushState(plr: Player)
	local p = profiles[plr]
	if not p then return end
	-- Beste etasje noensinne, offentlig (står alt på HUD og topp-10). Sky.client seeder bånd-annonsøren
	-- med den, så en romklatrer som rebirthet i en tidligere økt ikke får «YOU REACHED SPACE!» igjen.
	plr:SetAttribute("BestTier", p.bestTier)
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Jumps") :: IntValue).Value = p.jumpPower
		;(ls:FindFirstChild("Tier") :: IntValue).Value = p.frontierTier
		;(ls:FindFirstChild("Rebirths") :: IntValue).Value = p.rebirths
	end
	StateEvent:FireClient(plr, {
		jumpPower = p.jumpPower,
		jumpHeight = Progression.jumpHeight(p.jumpPower, multiplierOf(p), Config.Jump),
		tier = p.frontierTier,
		bestTier = p.bestTier,
		rebirths = p.rebirths,
		multiplier = multiplierOf(p),
		nextRebirthTier = Progression.rebirthTierRequired(p.rebirths, Config.Rebirth),
		canRebirth = Progression.canRebirth(p.frontierTier, p.rebirths, Config.Rebirth),
	})
end

-- Er (tier,idx) forbi spillerens frontier? (kun da gir tråkket +1)
local function isBeyondFrontier(p: Profile, tier: number, idx: number): boolean
	if tier > p.frontierTier then return true end
	if tier == p.frontierTier and idx > p.frontierIdx then return true end
	return false
end

grantStep = function(hit: BasePart, tier: number, idx: number, part: BasePart)
	local char = hit and hit.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local plr = Players:GetPlayerFromCharacter(char)
	if not plr then return end
	local p = profiles[plr]
	if not p then return end
	if not isBeyondFrontier(p, tier, idx) then return end

	-- KLATRE-VAKT (docs/complete-game-standard.md §3: topplista skal ikke kunne blåses opp av et skript).
	-- Touched kan fyres av klienten for en del den eier, fra hvor som helst, og klienten eier sin egen karakter.
	-- (1) Rot-delen må være ved plattformen. (2) Stigningen siden forrige kreditt må være fysisk mulig med
	-- hoppet serveren har gitt spilleren (Progression.allowRise). Ingen melding: en ekte klatrer treffer aldri
	-- dette (tests/Pacing.spec: 0 av 18 profiler x 300 etasjer), og et skript skal ikke få en fasit.
	if Config.Guard.Enabled then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not part then return end
		local rp, pp, ps = root.Position, part.Position, part.Size
		if not Progression.nearBox(rp.X, rp.Y, rp.Z, pp.X, pp.Y, pp.Z, ps.X / 2, ps.Y / 2, ps.Z / 2, Config.Guard.ReachStuds) then
			return
		end
		local gd = guards[plr]
		local h = Progression.jumpHeight(p.jumpPower, multiplierOf(p), Config.Jump)
		if not gd or not Progression.allowRise(gd, pp.Y, clock(), h, workspace.Gravity, Config.Guard) then
			return
		end
	end

	-- Avansér frontier plattform-for-plattform (hopp forbi tomrom teller likevel bare
	-- de faktisk tråkkede; men vi krever monotont fremrykk, så sett frontier hit).
	-- +1 pr NY plattform, for alle. Hvis spilleren hoppet over noen, teller vi bare
	-- den de faktisk landet på (frontier settes til denne). Ingen gamepass gir mer: et pass får bare endre
	-- utseendet (docs/complete-game-standard.md §3: aldri pay-to-win; check_plus1jump_paywin). `p.passes` lagres
	-- videre urørt, men leses aldri her.
	p.jumpPower += 1
	p.frontierTier = tier
	p.frontierIdx = idx
	if tier > p.bestTier then
		p.bestTier = tier
		p.bestTierAt = os.time() -- topplista: uavgjort til den som nådde etasjen først
	end

	-- Bygg mer tårn foran spilleren
	if tier + Config.Tower.StreamAhead > highestBuilt then
		for tt = highestBuilt + 1, tier + Config.Tower.StreamAhead do buildTier(tt) end
	end

	applyJump(plr)
	pushState(plr)
end

-- ── Rebirth ─────────────────────────────────────────────────────────────────
RebirthEvent.OnServerEvent:Connect(function(plr)
	local p = profiles[plr]
	-- Et avvist trykk sier hvorfor (ingen stille no-op): HUD-en viser svaret på knappen.
	if not p then
		RebirthEvent:FireClient(plr, { ok = false, reason = "notready" })
		return
	end
	if not Progression.canRebirth(p.frontierTier, p.rebirths, Config.Rebirth) then
		RebirthEvent:FireClient(plr, { ok = false, reason = "tier", tier = p.frontierTier,
			need = Progression.rebirthTierRequired(p.rebirths, Config.Rebirth) })
		return
	end
	p.rebirths += 1
	p.frontierTier = 0
	p.frontierIdx = 0
	p.jumpPower = 0
	-- bestTier beholdes; multiplier hentes fra rebirths
	-- Klatre-vakta starter på nytt fra sokkelen, med det nye (lave) hoppet.
	guards[plr] = Progression.newGuard(BASE_POS.Y, clock(),
		Progression.jumpHeight(p.jumpPower, multiplierOf(p), Config.Jump), Config.Guard)
	applyJump(plr)
	pushState(plr)
	-- Send spilleren tilbake til start
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then (hrp :: BasePart).CFrame = CFrame.new(BASE_POS + Vector3.new(0, 4, 0)) end
end)

-- ── Koder ───────────────────────────────────────────────────────────────────
RedeemFunc.OnServerInvoke = function(plr, input)
	local p = profiles[plr]
	if not p then return { ok = false, reason = "notready" } end
	if type(input) ~= "string" then return { ok = false, reason = "empty" } end
	local ok, reward, reason = Codes.redeem(input, p.redeemed, Config.Codes)
	if not ok then return { ok = false, reason = reason } end
	-- Kan vi ikke lagre (en annen økt holder profilen, eller lasten feilet), gir vi ikke: en kode som ble
	-- gitt men aldri lagret er borte når spilleren går, og spilleren tror den er brukt. Uten datastore i det
	-- hele tatt (Studio uten API-tilgang) lagres ingenting uansett, og koden virker for økta.
	if store and not p.canSave then return { ok = false, reason = "nosave" } end
	local code = Codes.normalize(input)
	local jump = tonumber(reward.jump) or 0
	p.redeemed[code] = true
	p.jumpPower += jump
	-- Flush UMIDDELBART: redeemed + jumpPower skrives atomisk i én UpdateAsync, så en crash mellom
	-- innløsning og autosave verken duper koden eller taper belønningen. Lander ikke skrivingen, rulles begge
	-- tilbake og spilleren får vite det (koden kan brukes igjen når lagringen virker).
	if store and not saveProfile(plr, false) then
		p.redeemed[code] = nil
		p.jumpPower -= jump
		return { ok = false, reason = "savefail" }
	end
	applyJump(plr)
	pushState(plr)
	return { ok = true, reason = "ok", jump = reward.jump }
end

-- ── Topplista: offentlig + venner, på en fysisk tavle ved spawn (docs/complete-game-standard.md §3) ────────
-- Metrikken er beste etasje, målt av serveren (grantStep, bak klatre-vakta). Lagret kodet i Config.Save.Leaderboard
-- (Board.encode: uavgjort til den som nådde den først), skrevet bare når den stiger (writeBoard). Offentlig topp 10
-- hentes høyst én gang per PublicCacheSeconds. Venner hentes først når en spiller ber om dem på tavla, capet,
-- cachet og strupet (Board.newLimiter + Roblox-budsjettet). Navn slås opp og huskes i minnet, lagres aldri.
local BC = Config.Board

-- Tavla står på sokkelens bakkant (-Z) med forsiden mot spawn. Tårnet går aldri mot -Z (TowerGen: forover er +Z,
-- ellers til sidene), så den står aldri i klatreruta. KLIENTEN tegner innholdet (Board.client.luau): hver spiller
-- ser sin egen visning, og en SurfaceGui i PlayerGui ville HUD-sjekken målt som skjerm-paneler.
local boardPart = Instance.new("Part")
boardPart.Name = "TopClimbersBoard"
boardPart.Anchored = true
boardPart.Size = Vector3.new(16, 11, 1)
do
	local centre = Vector3.new(0, BASE_POS.Y + 5.5, -11.5)
	boardPart.CFrame = CFrame.lookAt(centre, centre + Vector3.new(0, 0, 1)) -- forsiden (-Z lokalt) peker mot +Z
end
boardPart.Material = Enum.Material.SmoothPlastic
boardPart.Color = Color3.fromRGB(24, 28, 46)
boardPart.Parent = workspace
do
	-- gull-kant bak tavla: noe interaktivt skal se interaktivt ut (docs/new-game-checklist.md §2)
	local trim = Instance.new("Part")
	trim.Name = "TopClimbersTrim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.CastShadow = false
	trim.Size = Vector3.new(16.8, 11.8, 0.6)
	trim.CFrame = boardPart.CFrame * CFrame.new(0, 0, 0.35) -- lokal +Z = bak tavla
	trim.Material = Enum.Material.Neon
	trim.Color = Color3.fromRGB(255, 205, 90)
	trim.Parent = workspace
end
local boardPrompt = Instance.new("ProximityPrompt")
do
	-- Nede på forsiden: ~11 studs fra spawn-senteret, så prompten dukker opp når du går bort, ikke ved spawn.
	local at = Instance.new("Attachment")
	at.Name = "PromptAt"
	at.Position = Vector3.new(0, -3.5, -0.6)
	at.Parent = boardPart
	boardPrompt.Name = "BoardPrompt"
	boardPrompt.ActionText = BC.Text.Prompt
	boardPrompt.ObjectText = "Top Climbers"
	boardPrompt.HoldDuration = 0
	boardPrompt.MaxActivationDistance = BC.PromptDistance
	boardPrompt.RequiresLineOfSight = false
	boardPrompt.KeyboardKeyCode = Enum.KeyCode.E
	boardPrompt.Parent = at
end

-- Navn: fra spillere på serveren, venne-lista eller GetNameFromUserIdAsync; husket i minnet, aldri lagret.
local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
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
	return "#" .. tostring(userId) -- ikke husket: neste visning prøver igjen
end
local function withNames(rows: { any }): { any }
	local out = {}
	for i, r in rows do
		out[i] = { rank = r.rank, userId = r.userId, tier = r.tier, you = r.you, name = nameOf(r.userId) }
	end
	return out
end

-- En spillers egen verdi, fra minnet (ferskere enn datastoren, som skrives ved autosave).
local function liveValue(p: Profile?): number
	if not p or p.bestTier <= 0 then return 0 end
	return Board.encode(p.bestTier, p.bestTierAt, BC)
end

local boardMode: { [Player]: string } = {} -- "public" | "friends", per spiller
local publicView: any = { rows = {}, note = BC.Text.Loading }

local function sendBoard(plr: Player, mode: string, view: any)
	-- `viewer`: FireClient når bare denne spilleren i Roblox; feltet lar klienten se bort fra alt annet.
	BoardEvent:FireClient(plr, { viewer = plr.UserId, mode = mode, rows = view.rows, note = view.note })
end

local function refreshPublic()
	if not orderedLB then
		publicView = Board.publicView({}, BC)
		return
	end
	local ok, page = pcall(function()
		return orderedLB:GetSortedAsync(false, BC.PublicRows)
	end)
	if not ok or not page then return end -- behold forrige liste
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

local function sendPublic(plr: Player)
	local hudRows = {}
	for i, r in publicView.rows do
		hudRows[i] = { userId = r.userId, tier = r.tier, name = r.name }
	end
	LeaderboardEvent:FireClient(plr, hudRows) -- HUD-ens topp-10-panel (offentlig)
	if boardMode[plr] == "public" then sendBoard(plr, "public", publicView) end
end

-- Venner: kun på forespørsel, capet på FriendsCap, cachet per spiller. En feilet henting prøves igjen etter et
-- minutt, ikke på hvert trykk.
local friendsCache = Board.newCache(BC.FriendsCacheSeconds)
local friendsFailed = Board.newCache(60)
local scoreCache = Board.newCache(BC.ScoreCacheSeconds)
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, clock())
local fetching: { [Player]: boolean } = {}

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

-- La alltid BudgetReserve GetAsync stå igjen i Roblox-budsjettet (kan det ikke leses, gjelder bare begrenseren).
local function budgetLeft(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return not (ok and type(budget) == "number" and budget < BC.BudgetReserve)
end

-- En venns lagrede verdi (0 = har ikke klatret), eller nil når lesingen er strupet (prøv igjen senere). En lesing
-- som feiler teller som 0 uten å caches, så én dårlig nøkkel ikke stopper lista.
local function friendValue(userId: number): number?
	local here = Players:GetPlayerByUserId(userId)
	if here and profiles[here] then return liveValue(profiles[here]) end
	local now = clock()
	if Board.cacheHas(scoreCache, userId, now) then return Board.cacheGet(scoreCache, userId, now) end
	if not orderedLB then return 0 end
	if not budgetLeft() or not Board.take(readLimiter, now) then return nil end
	local ok, v = pcall(function()
		return orderedLB:GetAsync(key(userId))
	end)
	if not ok then return 0 end
	local value = if type(v) == "number" then v else 0
	Board.cachePut(scoreCache, userId, value, now)
	return value
end

local function showFriends(plr: Player)
	if fetching[plr] then
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading }) -- den som går, sender snart
		return
	end
	fetching[plr] = true
	task.spawn(function()
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading })
		local ids, failedList = friendIdsOf(plr)
		local values: { [number]: number } = {}
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
				task.wait(1) -- strupet: vent på begrenseren
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

boardPrompt.Triggered:Connect(function(plr: Player)
	boardMode[plr] = if boardMode[plr] == "friends" then "public" else "friends"
	if boardMode[plr] == "friends" then
		showFriends(plr)
	else
		sendBoard(plr, "public", publicView)
	end
end)

-- ── Spiller inn/ut ──────────────────────────────────────────────────────────
local function onCharacter(plr: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
	applyJump(plr)

	-- ── VENT TIL MOTOREN ER FERDIG MED KARAKTEREN ────────────────────────────────────────────
	-- Målt i Roblox Studio 2026-09-10 (robloxemu/SPAWN-ORDER.md): CharacterAdded fyrer mens
	-- modellen fortsatt er UPARENTET, med HumanoidRootPart i verdens-origo. ÉN FRAME SENERE
	-- parenter motoren modellen OG plasserer den på spawn-punktet — og motoren vinner: CFrame-en
	-- vi skrev i mellomtiden blir kastet, uten feil og uten advarsel.
	--
	-- To ting var faktisk ødelagt her, begge målt mot den nye emulator-rekkefølgen:
	--   1) plasseringen ble forkastet. En tier-12-klatrer som joinet en server som ALT KJØRTE
	--      havnet på sokkelen (0.00, 10.51, 0.00) — 1352,17 studs fra sin egen plattform
	--      (-40.55, 1264.50, 504.20).
	--   2) fall-redningen under startet ALDRI. `while char.Parent and ...` blir evaluert i det
	--      task.spawn kjører den, og inne i CharacterAdded er char.Parent nil — så løkka gikk ut
	--      før første iterasjon, og INGEN karakter i en live server hadde fall-redning i det hele
	--      tatt. Redningen ble beskrevet som masken som gjorde (1) til «bare et rykk». Målt
	--      finnes ikke masken: en spiller dyttet i tomrommet ble liggende der.
	--
	-- char.Parent er signalet: opptaket viser at parenting og plassering skjer i SAMME frame, så
	-- ser vi en parent, er motoren ferdig. Løkka er bounded (5 s ved 60 fps) — en karakter som
	-- aldri kommer fram skal ikke parkere denne handleren resten av økta.
	-- `char:WaitForChild(...)` over kjøper oss INGENTING her: på serveren finnes begge barna alt
	-- når CharacterAdded fyrer, så ingen av dem yielder. Fork Tower prøvde nettopp det og tapte.
	local frames = 0
	while char.Parent == nil and frames < 300 do
		task.wait(1 / 60)
		frames += 1
	end
	if char.Parent == nil then return end

	-- Les alt på nytt etter ventingen: tårnet kan ha blitt bygget videre, og profilen byttet ut.
	-- Spawn på frontier-plattformen (gjenoppta klatringen), ellers på sokkelen
	local p = profiles[plr]
	if p and p.frontierTier >= 1 and builtTiers[p.frontierTier] then
		local b = builtTiers[p.frontierTier]
		local pt = b.parts[math.min(p.frontierIdx, #b.parts)] or b.parts[#b.parts]
		if pt then hrp.CFrame = CFrame.new(pt.Position + Vector3.new(0, 4, 0)) end
	else
		hrp.CFrame = CFrame.new(BASE_POS + Vector3.new(0, 4, 0))
	end
	pushState(plr)

	-- Fall-redning: dropper man langt under frontier-plattformen, teleporter tilbake
	hum.Died:Connect(function() end)
	task.spawn(function()
		while char.Parent and hum.Health > 0 do
			local pp = profiles[plr]
			local floorY = BASE_POS.Y
			if pp and pp.frontierTier >= 1 and builtTiers[pp.frontierTier] then
				floorY = builtTiers[pp.frontierTier].origin.Y
			end
			if hrp.Position.Y < floorY - 60 then
				-- Tilbake til NØYAKTIG frontier-plattformen (ikke toppen), så spilleren ikke
				-- hopper over plattformer og mister opptjening.
				-- `target` er UNDERLAGET; +4 legges på ÉN gang under. Sokkel-grenen la på +4
				-- her også, så en fersk spiller ble reddet til y=16 og falt de siste 4 studs
				-- ned på sokkelen hen alt sto på ved spawn (y=12). Det var usynlig fordi
				-- løkka aldri kjørte: char.Parent var nil da task.spawn evaluerte den.
				local target = BASE_POS
				if pp and pp.frontierTier >= 1 and builtTiers[pp.frontierTier] then
					local b = builtTiers[pp.frontierTier]
					local pt = b.parts[math.min(pp.frontierIdx, #b.parts)] or b.parts[#b.parts]
					if pt then target = pt.Position end
				end
				hrp.CFrame = CFrame.new(target + Vector3.new(0, 4, 0))
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
			task.wait(0.4)
		end
	end)
end

local function onPlayerAdded(plr: Player)
	-- FØRSTE linje, FØR loadProfile: `loadProfile` yielder på DataStore:UpdateAsync, og med
	-- CharacterAutoLoads kan karakteren rekke å laste i den yielden. Settes RespawnLocation
	-- etterpå, kommer den for sent for akkurat den karakteren. (Motoren ville uansett falle
	-- tilbake på det eneste enabled spawn-punktet i Workspace — dette er belte OG bukseseler,
	-- og det koster ingenting å ta det først.)
	plr.RespawnLocation = spawnPad

	local p = loadProfile(plr)
	profiles[plr] = p
	-- FØR leaderstats: klienten tar leaderstats som «profilen er lastet» og leser BestTier da.
	plr:SetAttribute("BestTier", p.bestTier)

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, n in ipairs({ "Tier", "Jumps", "Rebirths" }) do
		local v = Instance.new("IntValue")
		v.Name = n
		v.Parent = ls
	end
	ls.Parent = plr

	-- Bygg tårnet FØR karakteren plasseres. onCharacter setter deg på frontier-plattformen din,
	-- men bare hvis etasjen finnes: `builtTiers[p.frontierTier]` er nil ellers, og da faller
	-- den tilbake til sokkelen. Ved oppstart er kun etasje 1 bygd, så alle over etasje 1 landet
	-- på bakken. Fall-redningen napper deg opp igjen innen ~0,5 s, så klatringen gikk aldri
	-- tapt — men du så et teleport-rykk hver gang du kom tilbake.
	-- Rekkefølgen er hele fiksen. check_plus1_rejoin.luau måler plasseringen i selve øyeblikket,
	-- ikke etter en frame, nettopp fordi redningen ellers skjuler feilen.
	if p.frontierTier + Config.Tower.StreamAhead > highestBuilt then
		for tt = highestBuilt + 1, p.frontierTier + Config.Tower.StreamAhead do buildTier(tt) end
	end

	-- Klatre-vakta starter der serveren setter spilleren: frontier-plattformen, ellers sokkelen.
	do
		local startY = BASE_POS.Y
		local b = p.frontierTier >= 1 and builtTiers[p.frontierTier]
		if b then
			local pt = b.parts[math.min(p.frontierIdx, #b.parts)] or b.parts[#b.parts]
			if pt then startY = pt.Position.Y end
		end
		guards[plr] = Progression.newGuard(startY, clock(),
			Progression.jumpHeight(p.jumpPower, multiplierOf(p), Config.Jump), Config.Guard)
	end

	plr.CharacterAdded:Connect(function(char) onCharacter(plr, char) end)
	if plr.Character then onCharacter(plr, plr.Character) end

	pushState(plr)
	boardMode[plr] = "public"
	sendPublic(plr)
end

local function onPlayerRemoving(plr: Player)
	saveProfile(plr, true) -- slipp låsen
	profiles[plr] = nil
	guards[plr] = nil
	boardMode[plr] = nil
	fetching[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		saveProfile(plr, true)
	end
end)

-- Autosave + topplista-loop
task.spawn(function()
	while true do
		task.wait(Config.Save.AutosaveSeconds)
		for _, plr in ipairs(Players:GetPlayers()) do
			saveProfile(plr, false)
		end
	end
end)
task.spawn(function()
	while true do
		refreshPublic() -- høyst én GetSortedAsync per PublicCacheSeconds
		for _, plr in ipairs(Players:GetPlayers()) do
			sendPublic(plr)
		end
		task.wait(BC.PublicCacheSeconds)
	end
end)

print("[Plus1] +1 Jump Every Step lastet. WorldSeed=" .. Config.WorldSeed)
