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

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("Progression"))
local TowerGen = require(ReplicatedStorage:WaitForChild("TowerGen"))
local Codes = require(ReplicatedStorage:WaitForChild("Codes"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))

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
local LeaderboardEvent = mkRemote("RemoteEvent", "Leaderboard") -- server -> klient: topp 10

-- ── Data ────────────────────────────────────────────────────────────────────
local store = Config.Save.Enabled and DataStoreService:GetDataStore(Config.Save.Store) or nil
local orderedLB = Config.Save.Enabled and DataStoreService:GetOrderedDataStore(Config.Save.Leaderboard) or nil

-- Per-spiller runtime-tilstand (i minne). `saved` = det som skrives til DataStore.
type Profile = {
	frontierTier: number,  -- høyeste etasje spilleren har et fotfeste på (double-count-gate)
	frontierIdx: number,   -- + plattform-indeks i den etasjen
	jumpPower: number,      -- faktisk opptjent jump power (climb + koder)
	rebirths: number,
	bestTier: number,       -- høyeste etasje NOENSINNE (leaderboard), overlever rebirth
	redeemed: { [string]: boolean },
	passes: { [string]: boolean },
	canSave: boolean,       -- load-suksess-sentinel: ikke lagre hvis lasten feilet
}

local profiles: { [Player]: Profile } = {}

local function defaultProfile(): Profile
	return {
		frontierTier = 0, frontierIdx = 0,
		jumpPower = Config.Jump.StartJumpPower,
		rebirths = 0, bestTier = 0,
		redeemed = {}, passes = {}, canSave = false,
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
				p.redeemed = (type(d.redeemed) == "table") and d.redeemed or {}
				p.passes = (type(d.passes) == "table") and d.passes or {}
			end
			if lockedByOther then
				acquired = false
				return old -- respekter den andre live-sessionen; ikke rør låsen
			end
			acquired = true
			old.jobId = game.JobId
			old.lockUntil = now + Config.Save.SessionLockSeconds
			return old
		end)
	end)
	if not ok then
		p.canSave = false
		warn("[Plus1] load failed for " .. plr.Name .. ": " .. tostring(err))
	else
		p.canSave = acquired
		if not acquired then
			warn("[Plus1] " .. plr.Name .. " lastet READ-ONLY (låst av annen session); progresjon denne økta lagres ikke.")
		end
	end
	return p
end

local function saveProfile(plr: Player, releaseLock: boolean)
	local p = profiles[plr]
	if not p or not p.canSave or not store then return end
	pcall(function()
		store:UpdateAsync(key(plr.UserId), function(old)
			old = old or {}
			old.data = {
				frontierTier = p.frontierTier, frontierIdx = p.frontierIdx,
				jumpPower = p.jumpPower, rebirths = p.rebirths, bestTier = p.bestTier,
				redeemed = p.redeemed, passes = p.passes,
			}
			old.jobId = game.JobId
			old.lockUntil = releaseLock and 0 or (os.time() + Config.Save.SessionLockSeconds)
			return old
		end)
	end)
	if orderedLB and p.bestTier > 0 then
		pcall(function()
			orderedLB:SetAsync(key(plr.UserId), p.bestTier)
		end)
	end
end

-- ── Tårn (delt, én instans for hele serveren) ───────────────────────────────
local towerFolder = Instance.new("Folder")
towerFolder.Name = "Tower"
towerFolder.Parent = workspace

local BASE_POS = Vector3.new(0, 8, 0)
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
			grantStep(hit, t, i)
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

grantStep = function(hit: BasePart, tier: number, idx: number)
	local char = hit and hit.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local plr = Players:GetPlayerFromCharacter(char)
	if not plr then return end
	local p = profiles[plr]
	if not p then return end
	if not isBeyondFrontier(p, tier, idx) then return end

	-- Avansér frontier plattform-for-plattform (hopp forbi tomrom teller likevel bare
	-- de faktisk tråkkede; men vi krever monotont fremrykk, så sett frontier hit).
	local earn = (p.passes.DoubleJump and 2 or 1)
	-- +1 (eller +2) pr NY plattform. Hvis spilleren hoppet over noen, teller vi bare
	-- den de faktisk landet på (frontier settes til denne).
	p.jumpPower += earn
	p.frontierTier = tier
	p.frontierIdx = idx
	if tier > p.bestTier then p.bestTier = tier end

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
	if not p then return end
	if not Progression.canRebirth(p.frontierTier, p.rebirths, Config.Rebirth) then return end
	p.rebirths += 1
	p.frontierTier = 0
	p.frontierIdx = 0
	p.jumpPower = 0
	-- bestTier beholdes; multiplier hentes fra rebirths
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
	local code = Codes.normalize(input)
	p.redeemed[code] = true
	p.jumpPower += tonumber(reward.jump) or 0
	-- Flush UMIDDELBART: redeemed + jumpPower skrives atomisk i én UpdateAsync, så en
	-- crash mellom innløsning og autosave verken duper koden (redeemed persistert) eller
	-- taper belønningen (jumpPower persistert sammen med den).
	saveProfile(plr, false)
	applyJump(plr)
	pushState(plr)
	return { ok = true, reason = "ok", jump = reward.jump }
end

-- ── Leaderboard broadcast ───────────────────────────────────────────────────
local function refreshLeaderboard()
	if not orderedLB then return end
	local ok, page = pcall(function()
		return orderedLB:GetSortedAsync(false, 10)
	end)
	if not ok or not page then return end
	local top = {}
	for _, entry in ipairs(page:GetCurrentPage()) do
		local uid = tonumber((string.gsub(entry.key, "^u_", "")))
		top[#top + 1] = { userId = uid, tier = entry.value }
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		LeaderboardEvent:FireClient(plr, top)
	end
end

-- ── Spiller inn/ut ──────────────────────────────────────────────────────────
local function onCharacter(plr: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	applyJump(plr)
	-- Spawn på frontier-plattformen (gjenoppta klatringen), ellers på sokkelen
	local p = profiles[plr]
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
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
				local target = BASE_POS + Vector3.new(0, 4, 0)
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
	local p = loadProfile(plr)
	profiles[plr] = p

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, n in ipairs({ "Tier", "Jumps", "Rebirths" }) do
		local v = Instance.new("IntValue")
		v.Name = n
		v.Parent = ls
	end
	ls.Parent = plr

	plr.CharacterAdded:Connect(function(char) onCharacter(plr, char) end)
	if plr.Character then onCharacter(plr, plr.Character) end

	-- Bygg nok tårn til spillerens frontier
	if p.frontierTier + Config.Tower.StreamAhead > highestBuilt then
		for tt = highestBuilt + 1, p.frontierTier + Config.Tower.StreamAhead do buildTier(tt) end
	end
	pushState(plr)
end

local function onPlayerRemoving(plr: Player)
	saveProfile(plr, true) -- slipp låsen
	profiles[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		saveProfile(plr, true)
	end
end)

-- Autosave + leaderboard-loop
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
		refreshLeaderboard()
		task.wait(30)
	end
end)

print("[Plus1] +1 Jump Every Step lastet. WorldSeed=" .. Config.WorldSeed)
