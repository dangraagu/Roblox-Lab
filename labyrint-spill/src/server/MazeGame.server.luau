--[[==================================================================
	LABYRINT-SPILL  -  versjon 1
	Laget for Marius & onkel :)

	HVOR LEGGER JEG DETTE?
	  Roblox Studio  ->  ServerScriptService  ->  (høyreklikk) Insert Object -> Script
	  Lim inn ALT dette inn i det skriptet. Trykk PLAY.

	Alt styres fra CONFIG-blokken rett under. Kurven (progresjonskurven)
	bestemmer hvor vanskelig hvert nivå er, fra level 1 (bittelite, ingen
	monstre) og oppover mot level 500. Skru på/av det dere vil med true/false.
==================================================================]]

--============================  CONFIG  ============================--
local CONFIG = {
	-- Grunnleggende
	CellSize = 9,             -- studs pr celle (gjør større hvis spilleren sitter fast)
	WallHeight = 24,          -- høyere vegger så spillere ikke kan booste hverandre over
	UnlockExitBy = "none",    -- "coins" | "gems" | "none": hva som må samles for å åpne utgangen
	                          -- "none" = utgangen er ALLTID åpen (ingen innsamling kreves)
	MultipleLevels = true,
	MaxLevel = 500,           -- der kurven er på sitt vanskeligste (spillet fortsetter uansett)

	-- LOBBY-MODUS: true = ny lobby + doors + per-spiller-instanser (sekvensiell
	-- progresjon, ingen carry). false = det gamle, verifiserte enkelt-maze-spillet
	-- (v14). Dette er ROLLBACK-spaken: bryter lobbyen live, sett false + publiser
	-- på nytt for å være tilbake på det som funket.
	-- STÅR PÅ false til lobby-koden er ferdigbygd + gjennomgått (bygges nå).
	UseLobby = false,

	-- Verden-frø: samme frø + samme level gir NØYAKTIG samme bane for ALLE
	-- spillere, hver gang (level 4 er alltid den samme level 4). Endre tallet
	-- for å trekke om alle nivåene på nytt — de forblir fortsatt like for alle.
	WorldSeed = 20260721,

	-- Spillerens gangfart (studs/s), brukt til å regne "optimal tid" for medaljer.
	PlayerWalkSpeed = 16,

	-- Monster
	MonsterDetectRange = 34,  -- hvor nær du må være før monsteret jakter

	-- Mørke + fakkel
	Darkness = true,
	TorchRange = 28,          -- lyskulen rundt spilleren

	-- Lagring (mynter/edelstener/pokaler overlever at man logger av)
	-- MERK: virker bare i publisert spill, eller i Studio hvis
	-- Game Settings -> Security -> "Enable Studio Access to API Services" er på.
	SaveData = true,

	------------------------------------------------------------------
	-- PROGRESJONSKURVE  (level 1  ->  500)
	-- Alle "MaxX" nås omtrent ved level 500. Juster fritt.
	------------------------------------------------------------------
	Curve = {
		-- Størrelse: starter 6x6 (lite!), vokser +1 hver 10. level opp til 30x30
		-- (raskere vekst = hvert nivå merkbart større og vanskeligere enn før).
		StartSize = 6, SizeEveryNLevels = 10, MaxSize = 30,

		-- Feller (lava/feller): mildere nå — ingen før level 6, +1 hver 16. level, tak 12
		FirstTrapLevel = 6, TrapEveryNLevels = 16, MaxTraps = 12,

		-- Monstre: ingen før level 4, +1 hver 25. level opp til 10
		FirstMonsterLevel = 4, MonsterEveryNLevels = 25, MaxMonsters = 10,
		-- Fart: fra 7 og øker sakte til 15 (spilleren går 16, så du kan alltid rømme)
		MonsterSpeedStart = 7, MonsterSpeedPerLevel = 0.02, MonsterSpeedMax = 15,

		-- Mynter: ca 10% av gangene har en mynt (skalerer med størrelsen)
		CoinDensity = 0.10, MinCoins = 3,

		-- Edelstener og knapper vokser sakte
		StartGems = 3, GemsPerLevels = 125,
		StartButtons = 3, ButtonsPerLevels = 170,

		-- Mørket kryper litt innover: sikt 60 -> 35 mot level 500
		StartSight = 60, SightTightenPerLevel = 0.05, MinSight = 35,
	},
}
--=================================================================--

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Themes = require(ReplicatedStorage:WaitForChild("Themes"))
local ShopService = require(ReplicatedStorage:WaitForChild("ShopService"))
local Medals = require(ReplicatedStorage:WaitForChild("Medals"))
local PerkDefs = require(ReplicatedStorage:WaitForChild("PerkDefs"))
local PerkService = require(ReplicatedStorage:WaitForChild("PerkService"))
local GodUsers = require(ReplicatedStorage:WaitForChild("GodUsers"))
local Progression = require(ReplicatedStorage:WaitForChild("Progression"))
local MazeGen = require(ReplicatedStorage:WaitForChild("MazeGen"))

-- Start-gave: de spesielle spillerne (samme liste som gudemodus, se GodUsers)
-- får startkapital FØRSTE gang de blir med. Gis én gang og lagres.
local STARTER_GIFT = { id = "starter2", coins = 999999, gems = 999999 }

-- Robux -> edelstener. SKRUS PÅ SENERE PÅ ROBLOX. Så lenge EnableRobux = false
-- gis INGEN Robux-kjøp. For å skru på: lag Developer Products på create.roblox.com,
-- fyll inn { [produktId] = antallGems } under, sett EnableRobux = true. GJENNOMGÅ
-- ProcessReceipt-koden før du skrur på ekte penger.
local RobuxConfig = {
	EnableRobux = false,
	RobuxGemProducts = {},  -- [developerProductId] = gems å gi
}

local dataStore = nil
if CONFIG.SaveData then
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore("LabyrintSpill_v1")
	end)
	if ok then dataStore = ds end
end

-- Globale nivå-rekorder (én delt rekord pr nivå, på tvers av alle servere).
local recordStore = nil
if CONFIG.SaveData then
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore("LabyrintRekord_v1")
	end)
	if ok then recordStore = ds end
end
local recordCache = {}  -- [level] = { time = number?, name = string? }

-- Global toppliste: HØYESTE nivå hver spiller har nådd, delt på tvers av alle
-- servere (OrderedDataStore). Vises på en tavle ved starten av hvert nivå. Egen
-- store så den ikke blandes med per-nivå-tidsrekordene over.
local topStore = nil
if CONFIG.SaveData then
	local ok, ds = pcall(function()
		-- v2: nytt navn for en REN topp-liste basert på "accepted" (sekvensielt,
		-- gud-fritt). v1 kunne ha carry-/gud-oppblåste tall — de arves ikke.
		return DataStoreService:GetOrderedDataStore("LabyrintTopp_v2")
	end)
	if ok then topStore = ds end
end
local leaderboardCache = {}   -- { { name = string, level = number }, ... } høyest først
local nameCache = {}          -- [userId] = navn (unngå gjentatte navne-oppslag)
local leaderboardEvent        -- RemoteEvent (fylles ut i HUD-seksjonen): sender topplista til klientene

-- Normaliser lagret rekord-data til en liste { {time, name}, ... }. Bakover-
-- kompatibel: gammelt format var ÉN {time, name}; nytt format er en array.
local function normalizeRecords(saved)
	local list = {}
	if typeof(saved) == "table" then
		if typeof(saved.time) == "number" then
			list[1] = { time = saved.time, name = (typeof(saved.name) == "string") and saved.name or "?" }
		else
			for _, e in ipairs(saved) do
				if typeof(e) == "table" and typeof(e.time) == "number" then
					list[#list + 1] = { time = e.time, name = (typeof(e.name) == "string") and e.name or "?" }
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.time < b.time end)
	return list
end

-- Topp-3 raskeste tider for et nivå: liste { {time, name}, ... } sortert raskest
-- først (kan være tom). Cachet.
local function getRecord(level)
	if recordCache[level] then return recordCache[level] end
	local list = {}
	if recordStore then
		local ok, saved = pcall(function() return recordStore:GetAsync("lvl_" .. level) end)
		if ok then list = normalizeRecords(saved) end
	end
	recordCache[level] = list
	return list
end

-- Sett en tid inn i topp-3 for nivået (atomisk, trygt om to servere prøver
-- samtidig). Skriver bare hvis tiden faktisk kom med i topp-3. Kalles asynkront.
local function tryUpdateRecord(level, time, name)
	if not recordStore then return end
	pcall(function()
		recordStore:UpdateAsync("lvl_" .. level, function(old)
			local list = normalizeRecords(old)
			local qualifies = (#list < 3) or (time < list[#list].time)
			if not qualifies then return nil end  -- kom ikke med i topp-3: ikke skriv
			list[#list + 1] = { time = time, name = name }
			table.sort(list, function(a, b) return a.time < b.time end)
			while #list > 3 do table.remove(list) end
			return list
		end)
	end)
end

--============================  STATE  ============================--
local currentLevel = 1
local currentGen = 0          -- økes hver bygging; gamle monster-løkker stopper
local currentPar = nil        -- optimal tid (sekunder) for gjeldende nivå
local currentThresholds = nil -- medalje-terskler for gjeldende nivå
local sendLevelInfo           -- fylles ut i HUD-seksjonen
local levelCompleteEvent      -- fylles ut i HUD-seksjonen
local playFx                  -- fylles ut i HUD-seksjonen (lyd-Fx)
local advancing = false
local mazeFolder = nil

local coinsTotal = 0
local coinsCollected = 0
local gemsTotalInLevel = 0
local gemsGrabbedCount = 0
local exitUnlocked = false
local exitBillboard = nil
local exitPad = nil
local onEscape                -- fylles ut lenger nede

local activeSpinners = {}     -- mynter/edelstener som skal spinne
local currentPassages = {}    -- Vector3-punkter for tilfeldig monster-vandring

local playerData = {}         -- [player] = {coins, gems, trophies, best}
local startClock = {}         -- [player] = os.clock() ved level-start
local shieldUsed = {}         -- [player] = true hvis skjold-perk er brukt på gjeldende nivå
local invulnUntil = {}        -- [player] = os.clock()-tid uskadelig til (kort vindu etter skjold)
local godActive = {}          -- [player] = true hvis gudemodus er på (kun GodUsers)
local levelHadGod = false     -- true hvis NOEN brukte gud på gjeldende nivå (nullstilles pr bygging)
local playerInstance = {}     -- LOBBY-MODUS: [player] = instansen de er inne i (nil = lobbyen)
local handleLobbySpawn        -- forhånds-deklarert; fylles ut i lobby-seksjonen

local function ownsPerk(plr, id)
	local d = playerData[plr]
	return d ~= nil and d.perks ~= nil and d.perks[id] == true
end

--==========================  HJELPERE  ===========================--
local function halfOf(n) return (n - 1) / 2 end

local function gridToWorld(x, y, gCols, gRows)
	local S = CONFIG.CellSize
	return Vector3.new((x - halfOf(gCols)) * S, 0, (y - halfOf(gRows)) * S)
end

local function cellCenterWorld(cx, cy, gCols, gRows)
	return gridToWorld(2 * cx + 1, 2 * cy + 1, gCols, gRows)
end

local function fmtTime(t) return Medals.fmtTime(t) end

--========================  PROGRESJONSKURVE  =====================--
local function getDifficulty(L)
	local c = CONFIG.Curve
	local size = math.clamp(c.StartSize + math.floor((L - 1) / c.SizeEveryNLevels), c.StartSize, c.MaxSize)
	local cells = size * size

	local traps = 0
	if L >= c.FirstTrapLevel then
		traps = math.clamp(1 + math.floor((L - c.FirstTrapLevel) / c.TrapEveryNLevels), 0, c.MaxTraps)
	end

	local monsters = 0
	if L >= c.FirstMonsterLevel then
		monsters = math.clamp(1 + math.floor((L - c.FirstMonsterLevel) / c.MonsterEveryNLevels), 0, c.MaxMonsters)
	end

	local speed = math.clamp(c.MonsterSpeedStart + (L - 1) * c.MonsterSpeedPerLevel, c.MonsterSpeedStart, c.MonsterSpeedMax)
	local coins = math.max(c.MinCoins, math.floor(cells * c.CoinDensity))
	local gems = c.StartGems + math.floor(L / c.GemsPerLevels)
	local buttons = c.StartButtons + math.floor(L / c.ButtonsPerLevels)
	local sight = math.clamp(c.StartSight - (L - 1) * c.SightTightenPerLevel, c.MinSight, c.StartSight)

	return {
		size = size, coins = coins, gems = gems, buttons = buttons,
		traps = traps, monsters = monsters, monsterSpeed = speed, sight = sight,
	}
end

--========================  MAZE-GENERATOR  =======================--
-- grid[y][x] = true betyr vegg. Recursive backtracker (iterativ).
local function generateMaze(cols, rows, rng)
	local gCols, gRows = 2 * cols + 1, 2 * rows + 1
	local grid = {}
	for y = 0, gRows - 1 do
		grid[y] = {}
		for x = 0, gCols - 1 do grid[y][x] = true end
	end

	local visited = {}
	local function key(cx, cy) return cx .. "," .. cy end

	local stack = { {0, 0} }
	visited[key(0, 0)] = true
	grid[1][1] = false
	local dirs = { {1, 0}, {-1, 0}, {0, 1}, {0, -1} }

	while #stack > 0 do
		local cur = stack[#stack]
		local cx, cy = cur[1], cur[2]
		local nbrs = {}
		for _, d in ipairs(dirs) do
			local nx, ny = cx + d[1], cy + d[2]
			if nx >= 0 and nx < cols and ny >= 0 and ny < rows and not visited[key(nx, ny)] then
				table.insert(nbrs, {nx, ny, d[1], d[2]})
			end
		end
		if #nbrs > 0 then
			local pick = nbrs[rng:NextInteger(1, #nbrs)]
			local nx, ny, dx, dy = pick[1], pick[2], pick[3], pick[4]
			visited[key(nx, ny)] = true
			grid[2 * cy + 1 + dy][2 * cx + 1 + dx] = false
			grid[2 * ny + 1][2 * nx + 1] = false
			table.insert(stack, {nx, ny})
		else
			table.remove(stack)
		end
	end
	return grid, gCols, gRows
end

--==========================  DEL-BYGGERE  ========================--
local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function findNearestPlayerRoot(pos, range)
	local best, bestDist = nil, range
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			local d = (root.Position - pos).Magnitude
			if d < bestDist then best, bestDist = root, d end
		end
	end
	return best
end

local function killTouch(hit)
	local char = hit and hit.Parent
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local plr = Players:GetPlayerFromCharacter(char)
	if plr and hum and hum.Health > 0 then
		if godActive[plr] then return end  -- gudemodus: udødelig
		-- Ett dødelig treff = mange Touched (flere lemmer + felle-trigger). Et kort
		-- uskadelig-vindu gjør at skjoldet tar ÉN hendelse, ikke bare den første.
		if os.clock() < (invulnUntil[plr] or 0) then return end
		if ownsPerk(plr, "shield") and not shieldUsed[plr] then
			shieldUsed[plr] = true                 -- skjoldet tar ett treff pr liv
			invulnUntil[plr] = os.clock() + 1.0
			if playFx then playFx(plr, "shield") end
			return
		end
		hum.Health = 0
		if playFx then playFx(plr, "death") end
	end
end

--==========================  LEADERSTATS  ========================--
local function ensureLeaderstats(plr)
	local ls = plr:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder"); ls.Name = "leaderstats"; ls.Parent = plr
	end
	local function num(name)
		local v = ls:FindFirstChild(name)
		if not v then v = Instance.new("IntValue"); v.Name = name; v.Parent = ls end
		return v
	end
	local function str(name)
		local v = ls:FindFirstChild(name)
		if not v then v = Instance.new("StringValue"); v.Name = name; v.Parent = ls end
		return v
	end
	return {
		Level = num("Level"),
		Coins = num("Coins"),
		Gems = num("Gems"),
		Trophies = num("Trophies"),
		BestTime = str("Best Time"),
	}
end

local function refreshStats(plr)
	local d = playerData[plr]; if not d then return end
	local s = ensureLeaderstats(plr)
	s.Level.Value = currentLevel
	s.Coins.Value = d.coins
	s.Gems.Value = d.gems
	s.Trophies.Value = d.trophies
	s.BestTime.Value = (d.best < math.huge) and fmtTime(d.best) or "-"
end

--========================  TOPPLISTE (PÅ SKJERM)  ================--
-- Send gjeldende topp-liste til klientene, som tegner den i et panel PÅ SKJERMEN
-- (mye lettere å SE enn en tavle inne i den mørke labyrinten). Med `plr` = bare
-- til den ene (ved innlogging); uten = til alle.
local function broadcastLeaderboard(plr)
	if not leaderboardEvent then return end
	if plr then
		leaderboardEvent:FireClient(plr, leaderboardCache)
	else
		leaderboardEvent:FireAllClients(leaderboardCache)
	end
end

-- Navn fra userId (online spiller først; ellers cachet API-oppslag). Faller pent
-- tilbake til "Player" hvis oppslaget feiler.
local function resolveName(userId)
	local online = Players:GetPlayerByUserId(userId)
	if online then return online.Name end
	if nameCache[userId] then return nameCache[userId] end
	local nm = "Player"
	local ok, res = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	if ok and typeof(res) == "string" and res ~= "" then nm = res end
	nameCache[userId] = nm
	return nm
end

-- Hent topp 10 (høyeste nivå) og oppdater cachen + tavla. Kjøres asynkront så den
-- aldri bremser nivå-byggingen; alt er pcall-et (DataStore kan feile/strupe).
-- Struped så raske nivå-hopp ikke spammer GetSortedAsync (les-grense pr minutt).
local lastLeaderboardRefresh = -1e9
local function refreshLeaderboard()
	if not topStore then return end
	local now = os.clock()
	if now - lastLeaderboardRefresh < 12 then return end
	lastLeaderboardRefresh = now
	task.spawn(function()
		local ok, pages = pcall(function()
			return topStore:GetSortedAsync(false, 10)  -- false = synkende: høyest nivå først
		end)
		if not ok or not pages then return end
		local ok2, top = pcall(function() return pages:GetCurrentPage() end)
		if not ok2 or typeof(top) ~= "table" then return end
		local list = {}
		for _, entry in ipairs(top) do
			local uid = tonumber(entry.key)
			local lvl = tonumber(entry.value)
			if uid and lvl then
				list[#list + 1] = { name = resolveName(uid), level = lvl }
			end
		end
		leaderboardCache = list
		broadcastLeaderboard()
	end)
end

-- Send inn en spillers nådde nivå (bare hvis høyere enn før). Asynkront + pcall.
local function submitTopScore(userId, level)
	if not topStore or typeof(level) ~= "number" then return end
	task.spawn(function()
		pcall(function()
			topStore:UpdateAsync(tostring(userId), function(old)
				if typeof(old) ~= "number" or level > old then
					return level
				end
				return nil  -- ikke høyere: ikke skriv
			end)
		end)
	end)
end

--============================  LAGRING  ==========================--
local function loadPlayer(plr)
	local d = { coins = 0, gems = 0, trophies = 0, best = math.huge,
		owned = { classic = true }, theme = Themes.default, receipts = {}, bestByLevel = {}, perks = {}, gifts = {},
		level = 1,          -- nivået spilleren skal fortsette på (lagres, se resume)
		rewardDay = 0,      -- siste dag daglig-belønning ble gitt (UTC-dagnummer)
		streak = 0,         -- antall dager på rad med daglig-belønning
		accepted = 0,       -- høyeste nivå fullført I SEKVENS uten gud (toppliste-grunnlag)
		bestWithGod = 0 }   -- høyeste nivå nådd inkl. gud-runder (kun skryt, aldri toppliste)
	local loadOk = true
	if dataStore then
		local ok, saved = pcall(function() return dataStore:GetAsync("p_" .. plr.UserId) end)
		if not ok then loadOk = false end  -- lese-feil: ikke lagre over ekte data senere
		if ok and typeof(saved) == "table" then
			if typeof(saved.coins) == "number" then d.coins = saved.coins end
			if typeof(saved.gems) == "number" then d.gems = saved.gems end
			if typeof(saved.trophies) == "number" then d.trophies = saved.trophies end
			if typeof(saved.best) == "number" then d.best = saved.best end
			if typeof(saved.owned) == "table" then
				for id in pairs(saved.owned) do
					if Themes.byId(id) then d.owned[id] = true end
				end
			end
			if typeof(saved.theme) == "string" and Themes.byId(saved.theme) then
				d.theme = saved.theme
			end
			if typeof(saved.receipts) == "table" then d.receipts = saved.receipts end
			if typeof(saved.bestByLevel) == "table" then
				for lvl, t in pairs(saved.bestByLevel) do
					if typeof(t) == "number" then d.bestByLevel[lvl] = t end
				end
			end
			if typeof(saved.perks) == "table" then
				for id in pairs(saved.perks) do
					if PerkDefs.byId(id) then d.perks[id] = true end
				end
			end
			if typeof(saved.gifts) == "table" then
				for id in pairs(saved.gifts) do d.gifts[id] = true end
			end
			-- Fortsett-på-nivå + daglig-belønning (bak-kompatibelt: gamle lagringer
			-- mangler feltene og faller tilbake til default-verdiene over).
			if typeof(saved.level) == "number" and saved.level >= 1 then
				d.level = math.floor(saved.level)
			end
			if typeof(saved.rewardDay) == "number" then d.rewardDay = saved.rewardDay end
			if typeof(saved.streak) == "number" then d.streak = saved.streak end
			if typeof(saved.accepted) == "number" then d.accepted = math.floor(saved.accepted) end
			if typeof(saved.bestWithGod) == "number" then d.bestWithGod = math.floor(saved.bestWithGod) end
		end
	end
	-- Migrering: mangler spilleren "accepted" (nytt felt), seed fra personlige
	-- rekorder — høyeste sammenhengende nivå de faktisk har fullført. Slik beholdes
	-- ekte fremgang uten å importere oppblåste/carry-tall.
	if d.accepted == 0 then
		d.accepted = Progression.seedAccepted(d.bestByLevel)
	end
	d.bestWithGod = math.max(d.bestWithGod, d.accepted, d.level or 0)
	d.owned.classic = true                                    -- classic eies alltid
	if not d.owned[d.theme] then d.theme = Themes.default end -- kan ikke ha valgt et uleid tema
	d.canSave = loadOk                                       -- false hvis GetAsync feilet
	playerData[plr] = d
	refreshStats(plr)
end

local function savePlayer(plr)
	local d = playerData[plr]
	if not d or not dataStore then return false end
	if d.canSave == false then return false end  -- lasten feilet: ikke overskriv ekte lagring
	local ok = pcall(function()
		dataStore:SetAsync("p_" .. plr.UserId, {
			coins = d.coins, gems = d.gems, trophies = d.trophies,
			best = (d.best < math.huge) and d.best or nil,
			owned = d.owned, theme = d.theme, receipts = d.receipts,
			bestByLevel = d.bestByLevel,
			perks = d.perks,
			gifts = d.gifts,
			level = d.level,
			rewardDay = d.rewardDay,
			streak = d.streak,
			accepted = d.accepted,
			bestWithGod = d.bestWithGod,
		})
	end)
	return ok
end

-- Debouncet lagring for hyppige, ikke-kritiske endringer (kjøp/valg av tema).
-- Slår sammen mange raske endringer til én SetAsync, så en klient ikke kan
-- spamme DataStore-skriv og strupe/miste de ekte lagringene (mynter/pokaler).
local saveScheduled = {}
local SAVE_DEBOUNCE = 6
local function scheduleSave(plr)
	if saveScheduled[plr] then return end
	saveScheduled[plr] = true
	task.delay(SAVE_DEBOUNCE, function()
		saveScheduled[plr] = nil
		if playerData[plr] then savePlayer(plr) end
	end)
end

--============================  UTGANG  ===========================--
local function updateExitVisual()
	if not exitPad then return end
	if exitUnlocked then
		exitPad.Color = Color3.fromRGB(60, 200, 90)
		exitPad.Material = Enum.Material.Neon
		if exitBillboard then exitBillboard.Text = "EXIT OPEN!" end
	else
		exitPad.Color = Color3.fromRGB(200, 60, 60)
		if exitBillboard then
			if CONFIG.UnlockExitBy == "gems" then
				exitBillboard.Text = "LOCKED - " .. (gemsTotalInLevel - gemsGrabbedCount) .. " gems left"
			else
				exitBillboard.Text = "LOCKED - " .. (coinsTotal - coinsCollected) .. " coins left"
			end
		end
	end
end

local function tryUnlockExit()
	if CONFIG.UnlockExitBy == "none" then
		exitUnlocked = true
	elseif CONFIG.UnlockExitBy == "gems" then
		exitUnlocked = gemsGrabbedCount >= gemsTotalInLevel
	else
		exitUnlocked = coinsCollected >= coinsTotal
	end
	updateExitVisual()
end

--============================  MONSTER  ==========================--
local function makeMonster(worldPos, gen, speed)
	local model = Instance.new("Model")
	model.Name = "Monster"

	local root = makePart({
		Name = "HumanoidRootPart",
		Size = Vector3.new(3.5, 5, 3.5),
		Color = Color3.fromRGB(150, 20, 20),
		Material = Enum.Material.Neon,
		Anchored = false, CanCollide = true,
		CFrame = CFrame.new(worldPos + Vector3.new(0, 3, 0)),
	})
	root.Parent = model

	local eye = makePart({
		Name = "Eye", Size = Vector3.new(3.6, 1.2, 0.2),
		Color = Color3.fromRGB(255, 240, 120), Material = Enum.Material.Neon,
		Anchored = false, CanCollide = false,
		CFrame = root.CFrame * CFrame.new(0, 0.8, -1.8),
	})
	eye.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root; weld.Part1 = eye; weld.Parent = root

	local hum = Instance.new("Humanoid")
	hum.WalkSpeed = speed
	hum.HipHeight = 0
	hum.Parent = model

	model.PrimaryPart = root
	root.Touched:Connect(killTouch)
	model.Parent = mazeFolder
	pcall(function() root:SetNetworkOwner(nil) end)  -- server eier fysikken => jevnere monster, mindre rykk

	task.spawn(function()
		local function moveTo(pos)
			local reached = false
			local conn = hum.MoveToFinished:Once(function() reached = true end)
			hum:MoveTo(pos)
			local t = 0
			while not reached and t < 1.2 and gen == currentGen and model.Parent do
				t += task.wait(0.1)
			end
			if conn then conn:Disconnect() end
		end

		while gen == currentGen and model.Parent do
			local targetRoot = findNearestPlayerRoot(root.Position, CONFIG.MonsterDetectRange)
			local goal
			if targetRoot then
				goal = targetRoot.Position
			elseif #currentPassages > 0 then
				-- Med vilje vanlig tilfeldighet: monster-vandring er oppførsel,
				-- ikke bane-layout, og skal ikke være lik for alle.
				goal = currentPassages[math.random(#currentPassages)]
			end

			if goal then
				local path = PathfindingService:CreatePath({
					AgentRadius = 2, AgentHeight = 5, AgentCanJump = false,
				})
				local ok = pcall(function() path:ComputeAsync(root.Position, goal) end)
				if ok and path.Status == Enum.PathStatus.Success then
					local wps = path:GetWaypoints()
					for i = 2, math.min(#wps, 5) do
						if gen ~= currentGen or not model.Parent then break end
						moveTo(wps[i].Position)
					end
				else
					task.wait(0.3)
				end
			else
				task.wait(0.3)
			end
			task.wait(0.05)
		end
	end)
end

--=========================  BYGG ET NIVÅ  ========================--
local function buildLevel()
	currentGen += 1
	local gen = currentGen
	exitUnlocked = false
	exitBillboard = nil
	exitPad = nil
	activeSpinners = {}
	currentPassages = {}
	coinsCollected = 0
	gemsGrabbedCount = 0
	levelHadGod = false           -- nytt nivå: nullstill gud-brukt-flagget

	if mazeFolder then mazeFolder:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "MazeGame"
	folder.Parent = workspace
	mazeFolder = folder

	local diff = getDifficulty(currentLevel)
	local cols, rows = diff.size, diff.size
	local S = CONFIG.CellSize

	-- oppdater mørket for dette nivået
	if CONFIG.Darkness then Lighting.FogEnd = diff.sight end

	-- Deterministisk RNG for dette nivået. Samme WorldSeed + samme level gir
	-- nøyaktig samme labyrint og plassering for alle spillere, hver gang.
	-- Monstrenes vandring (lenger nede) bruker med vilje vanlig tilfeldighet —
	-- det er oppførsel, ikke en del av selve bane-layouten.
	-- Vi sprer frøet kraftig pr level (i stedet for +1) så to nabo-nivåer får
	-- HELT ulike labyrinter (før føltes de like fordi frøene lå rett ved siden av
	-- hverandre). Begge ledd holder seg innenfor eksakt heltalls-område (< 2^53).
	local rng = Random.new(CONFIG.WorldSeed * 1000003 + currentLevel * 2654435761)

	local grid, gCols, gRows = generateMaze(cols, rows, rng)

	-- Gulv
	local floor = makePart({
		Name = "Floor",
		Size = Vector3.new(gCols * S, 1, gRows * S),
		Position = Vector3.new(0, -0.5, 0),
		Color = Color3.fromRGB(60, 62, 70),
		Material = Enum.Material.SmoothPlastic,
	})
	floor.Parent = folder

	-- Hemmelige-dør kandidater (vegg mellom to åpne celler)
	local doorCandidates = {}
	for cy = 0, rows - 1 do
		for cx = 0, cols - 1 do
			local gx, gy = 2 * cx + 1, 2 * cy + 1
			if cx + 1 < cols and grid[gy][gx + 1] then table.insert(doorCandidates, {gx + 1, gy}) end
			if cy + 1 < rows and grid[gy + 1][gx] then table.insert(doorCandidates, {gx, gy + 1}) end
		end
	end
	local doorSet = {}
	local nButtons = math.min(diff.buttons, #doorCandidates)
	for _ = 1, nButtons do
		local c = table.remove(doorCandidates, rng:NextInteger(1, #doorCandidates))
		doorSet[c[1] .. "," .. c[2]] = true
	end

	-- Bygg vegger (ta vare på dør-veggene)
	local doorParts = {}
	for y = 0, gRows - 1 do
		for x = 0, gCols - 1 do
			if grid[y][x] then
				local wp = gridToWorld(x, y, gCols, gRows)
				local isDoor = doorSet[x .. "," .. y]
				local wall = makePart({
					Name = isDoor and "SecretWall" or "Wall",
					Size = Vector3.new(S, CONFIG.WallHeight, S),
					Position = Vector3.new(wp.X, CONFIG.WallHeight / 2, wp.Z),
					Color = isDoor and Color3.fromRGB(70, 66, 78) or Color3.fromRGB(90, 94, 105),
					Material = Enum.Material.Slate,
				})
				wall.Parent = folder
				if isDoor then doorParts[x .. "," .. y] = wall end
			end
		end
	end

	-- Passasjeceller til plassering + monster-vandring
	local passageCells = {}
	for cy = 0, rows - 1 do
		for cx = 0, cols - 1 do
			table.insert(passageCells, {cx, cy})
			table.insert(currentPassages, cellCenterWorld(cx, cy, gCols, gRows) + Vector3.new(0, 2, 0))
		end
	end

	local function isReserved(cx, cy)
		return (cx == 0 and cy == 0) or (cx == cols - 1 and cy == rows - 1)
	end

	local pool = {}
	for _, c in ipairs(passageCells) do
		if not isReserved(c[1], c[2]) then table.insert(pool, c) end
	end
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i); pool[i], pool[j] = pool[j], pool[i]
	end
	local function take(n)
		local out = {}
		for _ = 1, math.min(n, #pool) do table.insert(out, table.remove(pool)) end
		return out
	end

	-- Start
	local sw = cellCenterWorld(0, 0, gCols, gRows)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "MazeSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(S - 3, 1, S - 3)
	spawn.Position = Vector3.new(sw.X, 0.5, sw.Z)
	spawn.Color = Color3.fromRGB(60, 200, 90)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Parent = folder

	-- (Topplista vises nå PÅ SKJERMEN hos hver spiller — se broadcastLeaderboard +
	-- HudRemotes/Leaderboard + klient-panelet — i stedet for en tavle inne i den
	-- mørke labyrinten, som var vanskelig å se.)

	-- Utgang
	local ew = cellCenterWorld(cols - 1, rows - 1, gCols, gRows)
	local pad = makePart({
		Name = "Exit",
		Size = Vector3.new(S - 3, 1, S - 3),
		Position = Vector3.new(ew.X, 0.6, ew.Z),
		Color = Color3.fromRGB(200, 60, 60),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	pad.Parent = folder
	exitPad = pad
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(6, 1.5)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.Parent = pad
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = bb
	exitBillboard = lbl

	pad.Touched:Connect(function(hit)
		local plr = Players:GetPlayerFromCharacter(hit.Parent)
		if plr and exitUnlocked and onEscape then onEscape(plr) end
	end)

	-- Mynter (vanlige)
	local coinCells = take(diff.coins)
	coinsTotal = #coinCells
	for _, c in ipairs(coinCells) do
		local w = cellCenterWorld(c[1], c[2], gCols, gRows)
		local coin = makePart({
			Name = "Coin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 2, 2),
			Color = Color3.fromRGB(250, 205, 50),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = CFrame.new(w + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		})
		coin.Parent = folder
		table.insert(activeSpinners, coin)
		local grabbed = false
		coin.Touched:Connect(function(hit)
			if grabbed then return end
			local plr = Players:GetPlayerFromCharacter(hit.Parent)
			if not plr then return end
			grabbed = true
			coin:Destroy()
			local d = playerData[plr]; if d then d.coins += 1; refreshStats(plr) end
			if playFx then playFx(plr, "coin") end
			coinsCollected += 1
			tryUnlockExit()
		end)
	end

	-- Edelstener (sjeldne)
	local gemCells = take(diff.gems)
	gemsTotalInLevel = #gemCells
	for _, c in ipairs(gemCells) do
		local w = cellCenterWorld(c[1], c[2], gCols, gRows)
		local gem = makePart({
			Name = "Gem",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2, 2, 2),
			Position = w + Vector3.new(0, 3.2, 0),
			Color = Color3.fromRGB(170, 90, 240),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		gem.Parent = folder
		table.insert(activeSpinners, gem)
		local grabbed = false
		gem.Touched:Connect(function(hit)
			if grabbed then return end
			local plr = Players:GetPlayerFromCharacter(hit.Parent)
			if not plr then return end
			grabbed = true
			gem:Destroy()
			local d = playerData[plr]; if d then d.gems += 1; refreshStats(plr) end
			if playFx then playFx(plr, "gem") end
			gemsGrabbedCount += 1
			tryUnlockExit()
		end)
	end

	-- Feller
	for _, c in ipairs(take(diff.traps)) do
		local w = cellCenterWorld(c[1], c[2], gCols, gRows)
		local trap = makePart({
			Name = "Trap",
			Size = Vector3.new(S - 2, 0.6, S - 2),
			Position = Vector3.new(w.X, 0.3, w.Z),
			Color = Color3.fromRGB(230, 90, 30),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		trap.Parent = folder
		trap.Touched:Connect(killTouch)
		-- Usynlig, høyere trigger så man ikke sklir/hopper "over" den tynne fella i fart.
		local trapTrigger = makePart({
			Name = "TrapTrigger",
			Size = Vector3.new(S - 2, 10, S - 2),
			Position = Vector3.new(w.X, 5, w.Z),
			Transparency = 1,
			CanCollide = false,
		})
		trapTrigger.Parent = folder
		trapTrigger.Touched:Connect(killTouch)
	end

	-- Knapper (åpner hemmelige vegger)
	local doorKeys = {}
	for k in pairs(doorParts) do table.insert(doorKeys, k) end
	table.sort(doorKeys)  -- pairs() er uordnet: sorter så knapp->dør-koblingen blir lik for alle
	local buttonCells = take(#doorKeys)
	for i, c in ipairs(buttonCells) do
		local doorPart = doorParts[doorKeys[i]]
		local w = cellCenterWorld(c[1], c[2], gCols, gRows)
		local btn = makePart({
			Name = "SecretButton",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 3, 3),
			Color = Color3.fromRGB(40, 200, 220),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = CFrame.new(w + Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		})
		btn.Parent = folder
		local used = false
		btn.Touched:Connect(function(hit)
			if used then return end
			local plr = Players:GetPlayerFromCharacter(hit.Parent)
			if not plr then return end
			used = true
			if playFx then playFx(plr, "button") end
			btn.Color = Color3.fromRGB(30, 90, 100)
			if doorPart and doorPart.Parent then
				doorPart.CanCollide = false
				local goal = { Position = doorPart.Position - Vector3.new(0, CONFIG.WallHeight + 2, 0) }
				TweenService:Create(doorPart, TweenInfo.new(0.7, Enum.EasingStyle.Quad), goal):Play()
			end
		end)
	end

	-- Monstre
	for _ = 1, diff.monsters do
		local mc = take(1)[1]
		if mc then makeMonster(cellCenterWorld(mc[1], mc[2], gCols, gRows), gen, diff.monsterSpeed) end
	end

	-- "Optimal tid" (par) + medalje-terskler for dette nivået: korteste rute som
	-- samler det utgangen krever og så når utgangen. Deterministisk => like for alle.
	do
		local reqCells
		if CONFIG.UnlockExitBy == "gems" then
			reqCells = gemCells
		elseif CONFIG.UnlockExitBy == "coins" then
			reqCells = coinCells
		else
			reqCells = {}
		end
		local mustVisit = {}
		for _, c in ipairs(reqCells) do
			table.insert(mustVisit, { 2 * c[1] + 1, 2 * c[2] + 1 })  -- celle -> finrute
		end
		local startFine = { 1, 1 }
		local exitFine = { 2 * (cols - 1) + 1, 2 * (rows - 1) + 1 }
		local steps = Medals.solveRoute(grid, gCols, gRows, startFine, exitFine, mustVisit)
		currentPar = Medals.parTime(steps, CONFIG.CellSize, CONFIG.PlayerWalkSpeed)
		currentThresholds = Medals.thresholds(currentPar)
	end

	tryUnlockExit()  -- åpen med en gang hvis ingen krav / ingen mynter

	-- Spinn på mynter/edelstener
	task.spawn(function()
		while gen == currentGen do
			for _, p in ipairs(activeSpinners) do
				if p.Parent then
					if p.Name == "Coin" then
						p.CFrame = p.CFrame * CFrame.Angles(math.rad(4), 0, 0)
					else
						p.CFrame = p.CFrame * CFrame.Angles(0, math.rad(4), 0)
					end
				end
			end
			task.wait(0.03)
		end
	end)

	-- Respawn alle spillere ved den nye starten. pcall så en spiller som er
	-- på vei ut (LoadCharacter kan feile) ikke stopper resten av respawn-løkka.
	for _, plr in ipairs(Players:GetPlayers()) do
		pcall(function() plr:LoadCharacter() end)
	end

	-- Oppdater HUD/leaderstats for ALLE spillere (ikke bare den som kom seg ut).
	for _, plr in ipairs(Players:GetPlayers()) do
		refreshStats(plr)
		if sendLevelInfo then sendLevelInfo(plr) end
	end
end

--======================  ESCAPE / NESTE NIVÅ  ====================--
onEscape = function(plr)
	if advancing then return end
	advancing = true

	local d = playerData[plr]
	if d then
		local st = startClock[plr]
		if st then
			local elapsed = os.clock() - st
			-- "clean" = INGEN brukte gud på dette nivået. Gud-runder oppdaterer ingen
			-- tider/rekorder (kun bestWithGod, se accepted-blokka lenger nede).
			local clean = not levelHadGod
			if clean and elapsed < d.best then d.best = elapsed end

			-- Per-nivå: personlig rekord, medalje, global rekord, oppsummering.
			local level = currentLevel
			local lkey = tostring(level)  -- DataStore lagrer heltalls-nøkler som tekst
			d.bestByLevel = d.bestByLevel or {}
			local prevPB = d.bestByLevel[lkey]
			local isNewPB = clean and ((prevPB == nil) or (elapsed < prevPB))
			if isNewPB then d.bestByLevel[lkey] = elapsed end

			local medal = Medals.medalFor(elapsed, currentThresholds)
			local recs = getRecord(level)                       -- topp-3 (raskest først)
			local bestTime = recs[1] and recs[1].time or nil
			local isNewRecord = clean and ((bestTime == nil) or (elapsed < bestTime))  -- ny #1?
			-- Kom tiden med i topp-3? (gude-runder teller ikke — beskytter tavla.)
			local worst = recs[3] and recs[3].time or nil
			local qualifies = (#recs < 3) or (worst and elapsed < worst)
			if clean and qualifies then
				local newList = {}
				for _, e in ipairs(recs) do newList[#newList + 1] = { time = e.time, name = e.name } end
				newList[#newList + 1] = { time = elapsed, name = plr.Name }
				table.sort(newList, function(a, b) return a.time < b.time end)
				while #newList > 3 do table.remove(newList) end
				recordCache[level] = newList
				recs = newList
				task.spawn(function() tryUpdateRecord(level, elapsed, plr.Name) end)
			end

			if levelCompleteEvent then
				levelCompleteEvent:FireClient(plr, {
					level = level, time = elapsed,
					yourBest = d.bestByLevel[lkey],
					record = recs[1], records = recs, medal = medal,
					isNewPB = isNewPB, isNewRecord = isNewRecord,
					thresholds = currentThresholds,
				})
			end
		end
		d.trophies += 1
		refreshStats(plr)
		task.spawn(function() savePlayer(plr) end)  -- async: ikke frys nivå-fremgangen på et DataStore-skriv
	end

	-- Progresjon ("accepted") for ALLE som er med i runden: hver tjener bare sitt
	-- EGET accepted hvis dette nivået er nøyaktig deres accepted+1 OG ingen brukte
	-- gud (carry gir ingenting, gud gir ingenting). bestWithGod oppdateres uansett.
	-- Regnes FØR currentLevel økes, mot nivået som nettopp ble løst.
	local solvedLevel = currentLevel
	local acceptedGainers = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local pd = playerData[p]
		if pd then
			local res = Progression.resolveClear({
				level = solvedLevel, accepted = pd.accepted, bestWithGod = pd.bestWithGod,
				hadGod = levelHadGod, mode = "group", isHostLevel = true,
			})
			pd.accepted = res.newAccepted
			pd.bestWithGod = res.newBestWithGod
			if res.acceptedGained then acceptedGainers[p] = true end
		end
	end

	if CONFIG.MultipleLevels then
		currentLevel += 1
		-- Lagre resume-nivået pr spiller (uendret oppførsel) + send ACCEPTED til
		-- den globale topplista.
		for _, p in ipairs(Players:GetPlayers()) do
			local pd = playerData[p]
			if pd then
				pd.level = math.max(pd.level or 1, currentLevel)
				scheduleSave(p)
				-- Toppliste bruker ACCEPTED (sekvensielt, gud-fritt) — ikke pd.level.
				-- Send bare de som faktisk ØKTE accepted denne runden, og aldri
				-- GodUsers (Mio holdes utenfor den globale tavla uansett).
				if pd.canSave ~= false and acceptedGainers[p] and not GodUsers.has(p) then
					submitTopScore(p.UserId, pd.accepted)
				end
			end
		end
		refreshLeaderboard()  -- hent oppdatert topp 10 (async) og oppdater tavla
	end
	task.wait(0.4)
	-- advancing MÅ nullstilles selv om buildLevel skulle feile, ellers låser
	-- progresjonen seg for godt (ingen kommer videre før server-omstart).
	local ok, err = pcall(buildLevel)
	if not ok then warn("[Labyrint] buildLevel feilet: " .. tostring(err)) end
	advancing = false
end

--========================  MØRKE / FAKKEL  =======================--
local function applyDarkness()
	if not CONFIG.Darkness then return end
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 28)
	Lighting.Ambient = Color3.fromRGB(15, 15, 20)
	Lighting.FogColor = Color3.fromRGB(8, 8, 12)
	Lighting.FogStart = 0
	Lighting.FogEnd = CONFIG.Curve.StartSight
end

local function giveTorch(char)
	if not CONFIG.Darkness then return end
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not root or root:FindFirstChild("Torch") then return end
	local light = Instance.new("PointLight")
	light.Name = "Torch"
	light.Range = CONFIG.TorchRange
	light.Brightness = 2.5
	light.Color = Color3.fromRGB(255, 235, 190)
	light.Parent = root
end

--============================  TEMA-BUTIKK  ======================--
-- Serveren eier all valuta og alt eierskap. Klienten sender bare ønsker via
-- Remotes; vi validerer med ShopService (ren logikk, testet) og lagrer.
local shopFolder = Instance.new("Folder")
shopFolder.Name = "ShopRemotes"
shopFolder.Parent = ReplicatedStorage

local buyThemeFn = Instance.new("RemoteFunction")
buyThemeFn.Name = "BuyTheme"
buyThemeFn.Parent = shopFolder

local selectThemeFn = Instance.new("RemoteFunction")
selectThemeFn.Name = "SelectTheme"
selectThemeFn.Parent = shopFolder

local shopDataEvent = Instance.new("RemoteEvent")
shopDataEvent.Name = "ShopData"
shopDataEvent.Parent = shopFolder

--============================  HUD / MEDALJER  ===================--
local hudFolder = Instance.new("Folder")
hudFolder.Name = "HudRemotes"
hudFolder.Parent = ReplicatedStorage

local levelInfoEvent = Instance.new("RemoteEvent")
levelInfoEvent.Name = "LevelInfo"
levelInfoEvent.Parent = hudFolder

-- levelCompleteEvent er forhånds-deklarert lenger oppe (brukes i onEscape).
levelCompleteEvent = Instance.new("RemoteEvent")
levelCompleteEvent.Name = "LevelComplete"
levelCompleteEvent.Parent = hudFolder

local fxEvent = Instance.new("RemoteEvent")
fxEvent.Name = "Fx"
fxEvent.Parent = hudFolder

-- Daglig-belønning-toast (serveren varsler klienten om dagens belønning + streak).
local rewardEvent = Instance.new("RemoteEvent")
rewardEvent.Name = "Reward"
rewardEvent.Parent = hudFolder

-- Toppliste til klientene (tegnes i et panel på skjermen). leaderboardEvent er
-- forhånds-deklarert lenger oppe (brukes av broadcastLeaderboard).
leaderboardEvent = Instance.new("RemoteEvent")
leaderboardEvent.Name = "Leaderboard"
leaderboardEvent.Parent = hudFolder

-- Admin-kringkasting (/bc): vises i et gjennomsiktig felt øverst hos ALLE spillere.
-- Samme RemoteEvent begge veier: klienten FireServer(text) for å be om kringkasting;
-- serveren verifiserer admin + filtrerer + FireAllClients(navn, tekst) for å vise.
local broadcastEvent = Instance.new("RemoteEvent")
broadcastEvent.Name = "Broadcast"
broadcastEvent.Parent = hudFolder

-- Admin = spillets eier (deg) ELLER gude-spillerne (Mio). CreatorId gjelder når
-- spillet er eid av en BRUKER (ikke gruppe) — som her.
local function isAdmin(plr)
	if game.CreatorType == Enum.CreatorType.User and plr.UserId == game.CreatorId then
		return true
	end
	return GodUsers.has(plr)
end

-- Chat-kommando "/bc <tekst>". Triggered fyrer på klienten som skrev den; klienten
-- (AdminBroadcastClient) sender resten hit via broadcastEvent:FireServer.
local bcCmd = Instance.new("TextChatCommand")
bcCmd.Name = "BroadcastCommand"
bcCmd.PrimaryAlias = "/bc"
bcCmd.Parent = TextChatService

-- Verifiser admin + filtrer + kringkast til alle. Kalles fra BEGGE veier under.
local function doBroadcast(plr, text)
	if not isAdmin(plr) then return end                 -- server-autoritativt: bare admin
	if typeof(text) ~= "string" then return end
	text = string.sub(text, 1, 200)
	if string.gsub(text, "%s", "") == "" then return end
	-- Filtrer (Roblox-krav: tekst vist til andre må filtreres). Feiler filteret,
	-- faller vi tilbake til rå tekst — admin (eier + Mio) er betrodd, og vi vil
	-- heller VISE meldingen enn å svelge den stille (som var feilen før).
	local filtered = text
	local ok, res = pcall(function()
		local obj = TextService:FilterStringAsync(text, plr.UserId)
		return obj:GetNonChatStringForBroadcastAsync()
	end)
	if ok and typeof(res) == "string" then filtered = res end
	broadcastEvent:FireAllClients(plr.DisplayName, filtered)
end

-- Moderne vei: klienten (TextChatCommand-relé i AdminBroadcastClient) sender hit.
broadcastEvent.OnServerEvent:Connect(function(plr, text)
	doBroadcast(plr, text)
end)

-- Legacy-vei: bruker spillet det GAMLE chat-systemet, fyrer TextChatCommand ikke
-- på klienten — men da fyrer plr.Chatted server-side. Vi fanger "/bc <tekst>" her.
-- (På moderne TextChatService fyrer Chatted ikke, så ingen dobbel-kringkasting.)
Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(message)
		if typeof(message) ~= "string" then return end
		local rest = string.match(message, "^/bc%s+(.+)$")
		if rest then doBroadcast(plr, rest) end
	end)
end)
for _, plr in ipairs(Players:GetPlayers()) do
	plr.Chatted:Connect(function(message)
		if typeof(message) ~= "string" then return end
		local rest = string.match(message, "^/bc%s+(.+)$")
		if rest then doBroadcast(plr, rest) end
	end)
end

-- playFx er forhånds-deklarert (brukes i killTouch + pickup-handlere lenger oppe).
playFx = function(plr, key)
	fxEvent:FireClient(plr, key)
end

-- sendLevelInfo er forhånds-deklarert lenger oppe (brukes i buildLevel).
sendLevelInfo = function(plr)
	local d = playerData[plr]
	levelInfoEvent:FireClient(plr, {
		level = currentLevel,
		thresholds = currentThresholds,
		records = getRecord(currentLevel),   -- topp-3 raskeste tider (raskest først)
		yourBest = (d and d.bestByLevel) and d.bestByLevel[tostring(currentLevel)] or nil,
		accepted = d and d.accepted or 0,    -- spillerens sekvensielle "accepted"-nivå
		-- Gude-spillere (Mio) ser sitt eget skille rent/gud; andre får ikke feltet.
		bestWithGod = (d and GodUsers.has(plr)) and d.bestWithGod or nil,
	})
end

--============================  PERKS (OPPGRADERINGER)  ===========--
local perkFolder = Instance.new("Folder")
perkFolder.Name = "PerkRemotes"
perkFolder.Parent = ReplicatedStorage

local buyPerkFn = Instance.new("RemoteFunction")
buyPerkFn.Name = "BuyPerk"
buyPerkFn.Parent = perkFolder

local perkDataEvent = Instance.new("RemoteEvent")
perkDataEvent.Name = "PerkData"
perkDataEvent.Parent = perkFolder

local applyPerks  -- fylles ut nedenfor (kjøps-handleren bruker den for å virke med en gang)

-- Gudemodus (kun GodUsers): klienten slår av/på og gjør fly + gå-gjennom-vegger
-- lokalt; serveren gjør spilleren udødelig (verifisert på brukernavn her).
local godFolder = Instance.new("Folder")
godFolder.Name = "GodRemotes"
godFolder.Parent = ReplicatedStorage

local setGodEvent = Instance.new("RemoteEvent")
setGodEvent.Name = "SetGodMode"
setGodEvent.Parent = godFolder

setGodEvent.OnServerEvent:Connect(function(plr, enabled)
	if GodUsers.has(plr) then
		godActive[plr] = enabled and true or false
		if godActive[plr] then
			levelHadGod = true  -- gammel enkelt-maze-modus: gud brukt = ingen kreditt
			-- Lobby-modus: marker spillerens EGEN instans (per-instans-rettferdighet).
			if CONFIG.UseLobby and playerInstance[plr] then playerInstance[plr].hadGod = true end
		end
	end
end)

local function sendPerkData(plr)
	local d = playerData[plr]; if not d then return end
	perkDataEvent:FireClient(plr, { coins = d.coins, perks = d.perks })
end

buyPerkFn.OnServerInvoke = function(plr, perkId)
	local d = playerData[plr]
	if not d then return { ok = false, reason = "noplayer", coins = 0, perks = {} } end
	if typeof(perkId) ~= "string" then
		return { ok = false, reason = "badinput", coins = d.coins, perks = d.perks }
	end
	local ok, reason = PerkService.buy(PerkDefs, d, perkId)
	if ok then
		refreshStats(plr)
		scheduleSave(plr)
		sendPerkData(plr)
		if plr.Character then applyPerks(plr, plr.Character) end  -- fart/fakkel virker med en gang
	end
	return { ok = ok, reason = reason, coins = d.coins, perks = d.perks }
end

-- Bruk perk-effekter på spilleren: fart + fakkel-rekkevidde. Kalles ved spawn og
-- rett etter kjøp. (skjold og minikart håndteres av killTouch / klienten.)
applyPerks = function(plr, char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		local sp = PerkDefs.byId("speed")
		local bonus = (ownsPerk(plr, "speed") and sp and sp.speedBonus) or 0
		hum.WalkSpeed = CONFIG.PlayerWalkSpeed + bonus
	end
	if CONFIG.Darkness then
		local root = char:FindFirstChild("HumanoidRootPart")
		local torch = root and root:FindFirstChild("Torch")
		if torch then
			local tp = PerkDefs.byId("torch")
			local bonus = (ownsPerk(plr, "torch") and tp and tp.torchBonus) or 0
			torch.Range = CONFIG.TorchRange + bonus
		end
	end
end

local function stateFor(plr, ok, reason)
	local d = playerData[plr]
	return {
		ok = ok, reason = reason,
		coins = d and d.coins or 0,
		gems = d and d.gems or 0,
		owned = d and d.owned or {},
		theme = d and d.theme or Themes.default,
	}
end

local function sendShopData(plr)
	local d = playerData[plr]; if not d then return end
	shopDataEvent:FireClient(plr, {
		coins = d.coins, gems = d.gems, owned = d.owned, theme = d.theme,
	})
end

buyThemeFn.OnServerInvoke = function(plr, themeId, payWith)
	local d = playerData[plr]
	if not d then return { ok = false, reason = "noplayer" } end
	if typeof(themeId) ~= "string" or typeof(payWith) ~= "string" then
		return stateFor(plr, false, "badinput")
	end
	local ok, reason = ShopService.buy(Themes, d, themeId, payWith)
	if ok then
		refreshStats(plr)       -- leaderstats oppdateres straks (spilleren ser trekket)
		scheduleSave(plr)       -- DataStore lagres debouncet
		sendShopData(plr)
	end
	return stateFor(plr, ok, reason)
end

selectThemeFn.OnServerInvoke = function(plr, themeId)
	local d = playerData[plr]
	if not d then return { ok = false, reason = "noplayer" } end
	if typeof(themeId) ~= "string" then return stateFor(plr, false, "badinput") end
	local prev = d.theme
	local ok, reason = ShopService.select(Themes, d, themeId)
	if ok and d.theme ~= prev then   -- bare lagre/sende hvis valget faktisk endret seg
		scheduleSave(plr)
		sendShopData(plr)
	end
	return stateFor(plr, ok, reason)
end

-- Robux -> edelstener. AV som standard (RobuxConfig.EnableRobux = false).
-- Roblox kaller ProcessReceipt når en ekte Developer Product kjøpes; den er
-- idempotent via d.receipts (Roblox kan kalle den flere ganger for samme kjøp).
MarketplaceService.ProcessReceipt = function(receiptInfo)
	if not RobuxConfig.EnableRobux then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local gems = RobuxConfig.RobuxGemProducts[receiptInfo.ProductId]
	if not gems then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local plr = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not plr then
		return Enum.ProductPurchaseDecision.NotProcessedYet  -- prøv igjen når spiller er tilbake
	end
	local d = playerData[plr]
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = tostring(receiptInfo.PurchaseId)
	d.receipts = d.receipts or {}
	if d.receipts[key] then
		return Enum.ProductPurchaseDecision.PurchaseGranted  -- allerede gitt, ikke gi dobbelt
	end
	d.gems = (d.gems or 0) + gems
	d.receipts[key] = true
	refreshStats(plr)
	-- Ekte penger: gi BARE PurchaseGranted når lagringen faktisk gikk gjennom.
	-- Feiler den, rull tilbake i minnet så Roblox kan prøve igjen rent (idempotent).
	if not savePlayer(plr) then
		d.gems = d.gems - gems
		d.receipts[key] = nil
		refreshStats(plr)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	sendShopData(plr)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--========================  SPILLER-HENDELSER  ====================--
local function onCharacterAdded(plr, char)
	startClock[plr] = os.clock()
	shieldUsed[plr] = false          -- skjold nullstilles ved hver respawn / nytt nivå
	giveTorch(char)
	applyPerks(plr, char)
	sendShopData(plr)  -- send saldo/eierskap/valgt tema når klienten sikkert er lastet
	if CONFIG.UseLobby then
		-- Lobby-modus: hvert spawn skjer i lobbyen (også etter død i en instans).
		if handleLobbySpawn then handleLobbySpawn(plr) end
	elseif sendLevelInfo then
		sendLevelInfo(plr)
	end
	sendPerkData(plr)
	broadcastLeaderboard(plr)  -- fyll spillerens topp-liste-panel med gjeldende cache

	-- Daglig belønning: vis ÉN gang etter at spilleren har spawnet (da er klient-
	-- HUD-en garantert oppe, så toasten ikke går tapt). Nullstill så den ikke gjentas.
	local d = playerData[plr]
	if d and d.pendingReward and rewardEvent then
		local rw = d.pendingReward
		d.pendingReward = nil
		task.delay(2.5, function()
			if plr.Parent then rewardEvent:FireClient(plr, rw) end
		end)
	end
end

local function onPlayerAdded(plr)
	loadPlayer(plr)

	-- Del ut start-gaven til spesielle spillere (samme liste som gudemodus).
	-- Bare hvis lasten gikk bra, ellers kunne vi overskrevet ekte data.
	local d = playerData[plr]
	if d and d.canSave ~= false and GodUsers.has(plr) then
		d.gifts = d.gifts or {}
		if not d.gifts[STARTER_GIFT.id] then
			d.coins += STARTER_GIFT.coins
			d.gems += STARTER_GIFT.gems
			d.gifts[STARTER_GIFT.id] = true
			refreshStats(plr)
			savePlayer(plr)  -- lagre straks så gaven ikke deles ut på nytt
			sendShopData(plr)
		end
	end

	-- Daglig belønning (retention): første innlogging på en ny UTC-dag gir mynter,
	-- og en streak-bonus som vokser den første uka + en liten edelsten-bonus hver
	-- 7. dag. Stashes i d.pendingReward og vises som en toast ved første spawn.
	if d and d.canSave ~= false then
		local today = math.floor(os.time() / 86400)
		if d.rewardDay ~= today then
			if d.rewardDay == today - 1 then
				d.streak = (d.streak or 0) + 1   -- to dager på rad: streaken vokser
			else
				d.streak = 1                     -- hull i rekka (eller første gang): start på nytt
			end
			d.rewardDay = today
			local coinReward = 150 * math.min(d.streak, 7)      -- 150 .. 1050
			local gemReward = (d.streak % 7 == 0) and 5 or 0     -- gullbonus hver 7. dag
			d.coins += coinReward
			d.gems += gemReward
			d.pendingReward = { coins = coinReward, gems = gemReward, streak = d.streak }
			refreshStats(plr)
			savePlayer(plr)  -- lagre straks så belønningen ikke gis to ganger samme dag
		end
	end

	plr.CharacterAdded:Connect(function(char) onCharacterAdded(plr, char) end)

	-- Fortsett-på-nivået-du-forlot. Labyrinten er DELT (én bane, alle avanserer
	-- sammen), så vi kan bare resume når spilleren er ALENE/først inne — da bygger
	-- vi om til nivået deres (som også spawner dem der). Er andre alt i gang, blir
	-- man med der de er, men beholder egen fremgang (mister ikke lagret nivå).
	local rebuilt = false
	-- Lobby-modus: ingen delt maze/resume — spilleren spawner i lobbyen og velger
	-- en dør. (onCharacterAdded -> handleLobbySpawn driver HUD-en.)
	-- Feilet DataStore-lasten (canSave == false), stol IKKE på d.level (den er
	-- da bare default) — la spilleren bli med på gjeldende nivå i stedet.
	if not CONFIG.UseLobby and d and d.canSave ~= false then
		if #Players:GetPlayers() <= 1 then
			local resumeAt = math.max(1, d.level or 1)
			-- Ikke bygg om midt i en pågående escape-rebuild (advancing) — da kunne
			-- to buildLevel-kall kollidert. Er vi midt i en, hopper vi over resume;
			-- spilleren blir med på nivået som er på vei inn.
			if resumeAt ~= currentLevel and not advancing then
				currentLevel = resumeAt
				local ok, err = pcall(buildLevel)  -- bygger nivået + respawner spilleren der
				if ok then rebuilt = true else warn("[Labyrint] resume-bygg feilet: " .. tostring(err)) end
			end
		else
			d.level = math.max(d.level or 1, currentLevel)
		end
	end

	-- Bygde vi om (over), spawnet buildLevel spilleren og trigget onCharacterAdded
	-- via CharacterAdded — da SKAL vi ikke kalle den igjen. Ellers: har spilleren
	-- alt en auto-lastet karakter, kjør oppsettet for den nå.
	if not rebuilt and plr.Character then onCharacterAdded(plr, plr.Character) end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end

Players.PlayerRemoving:Connect(function(plr)
	savePlayer(plr)                 -- flush umiddelbart (fanger evt. debouncet endring)
	-- Lobby-modus: forlot spilleren en instans, riv den (ellers lekker folder +
	-- monster/spinn-løkker kjører for alltid).
	local inst = playerInstance[plr]
	if inst then
		playerInstance[plr] = nil
		inst.gen = (inst.gen or 0) + 1
		if inst.folder then inst.folder:Destroy() end
	end
	playerData[plr] = nil
	startClock[plr] = nil
	saveScheduled[plr] = nil
	shieldUsed[plr] = nil
	invulnUntil[plr] = nil
	godActive[plr] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do savePlayer(plr) end
end)

--====================  LOBBY + PER-SPILLER-INSTANSER  ============--
-- Ny modus (CONFIG.UseLobby). En lobby-hub der alle spawner + går inn i "doors";
-- hver kjøring bygger en EGEN labyrint-instans langt unna de andre, så ingen dras
-- med på et for høyt nivå. Gjenbruker MazeGen + makePart + killTouch +
-- findNearestPlayerRoot. Utgangen er alltid åpen (CONFIG.UnlockExitBy = "none").
local LOBBY_ORIGIN = Vector3.new(0, 0, 0)
local INSTANCE_SPACING = 6000       -- studs mellom instanser (godt utenfor sikt/range)
local LOBBY_FOG = 90                -- huben er lys; instansene bruker samme globale tåke
local INSTANCE_FOG = 45            -- fast sikt i instansene (per-spiller-tåke kommer senere)
-- playerInstance er forhånds-deklarert i STATE-seksjonen (brukes av onCharacterAdded
-- + SetGodMode lenger oppe).
local nextInstanceId = 0

-- Instans-bevisst monster (som makeMonster, men bundet til instansens folder/gen/
-- passasjer i stedet for globalene). Chase bruker findNearestPlayerRoot (range 34);
-- instanser står 6000 fra hverandre, så et monster ser bare spillere i EGEN instans.
local function makeInstanceMonster(inst, worldPos, speed)
	local model = Instance.new("Model")
	model.Name = "Monster"
	local root = makePart({
		Name = "HumanoidRootPart", Size = Vector3.new(3.5, 5, 3.5),
		Color = Color3.fromRGB(150, 20, 20), Material = Enum.Material.Neon,
		Anchored = false, CanCollide = true,
		CFrame = CFrame.new(worldPos + Vector3.new(0, 3, 0)),
	})
	root.Parent = model
	local eye = makePart({
		Name = "Eye", Size = Vector3.new(3.6, 1.2, 0.2),
		Color = Color3.fromRGB(255, 240, 120), Material = Enum.Material.Neon,
		Anchored = false, CanCollide = false, CFrame = root.CFrame * CFrame.new(0, 0.8, -1.8),
	})
	eye.Parent = model
	local weld = Instance.new("WeldConstraint"); weld.Part0 = root; weld.Part1 = eye; weld.Parent = root
	local hum = Instance.new("Humanoid"); hum.WalkSpeed = speed; hum.HipHeight = 0; hum.Parent = model
	model.PrimaryPart = root
	root.Touched:Connect(killTouch)
	model.Parent = inst.folder
	pcall(function() root:SetNetworkOwner(nil) end)
	local myGen = inst.gen
	task.spawn(function()
		local function moveTo(pos)
			local reached = false
			local conn = hum.MoveToFinished:Once(function() reached = true end)
			hum:MoveTo(pos)
			local t = 0
			while not reached and t < 1.2 and inst.gen == myGen and model.Parent do t += task.wait(0.1) end
			if conn then conn:Disconnect() end
		end
		while inst.gen == myGen and model.Parent do
			local targetRoot = findNearestPlayerRoot(root.Position, CONFIG.MonsterDetectRange)
			local goal
			if targetRoot then
				goal = targetRoot.Position
			elseif #inst.passages > 0 then
				goal = inst.passages[math.random(#inst.passages)]
			end
			if goal then
				local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false })
				local ok = pcall(function() path:ComputeAsync(root.Position, goal) end)
				if ok and path.Status == Enum.PathStatus.Success then
					local wps = path:GetWaypoints()
					for i = 2, math.min(#wps, 5) do
						if inst.gen ~= myGen or not model.Parent then break end
						moveTo(wps[i].Position)
					end
				else task.wait(0.3) end
			else task.wait(0.3) end
			task.wait(0.05)
		end
	end)
end

local finishRun  -- forward-deklarert (buildInstance kobler exit-touch til den)

-- Bygg labyrinten for en instans på inst.origin, nivå inst.level. Utgangen er
-- alltid åpen; mynter/edelstener gir valuta ved berøring; feller dreper; monstre
-- vandrer/jager i instansen. Setter inst.folder/spawnPos/thresholds.
local function buildInstance(inst)
	inst.gen = (inst.gen or 0) + 1
	if inst.folder then inst.folder:Destroy() end
	local folder = Instance.new("Folder"); folder.Name = "Maze_" .. inst.id; folder.Parent = workspace
	inst.folder = folder
	inst.spinners = {}
	inst.passages = {}
	inst.hadGod = false

	local diff = MazeGen.getDifficulty(inst.level, CONFIG.Curve)
	local cols, rows = diff.size, diff.size
	local S = CONFIG.CellSize
	local origin = inst.origin
	local rng = Random.new(CONFIG.WorldSeed * 1000003 + inst.level * 2654435761)
	local grid, gCols, gRows = MazeGen.generate(cols, rows, rng)

	makePart({ Name = "Floor", Size = Vector3.new(gCols * S, 1, gRows * S),
		Position = origin + Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(60, 62, 70),
		Material = Enum.Material.SmoothPlastic }).Parent = folder

	-- Hemmelige-dør-kandidater + valg
	local doorCandidates = {}
	for cy = 0, rows - 1 do
		for cx = 0, cols - 1 do
			local gx, gy = 2 * cx + 1, 2 * cy + 1
			if cx + 1 < cols and grid[gy][gx + 1] then table.insert(doorCandidates, { gx + 1, gy }) end
			if cy + 1 < rows and grid[gy + 1][gx] then table.insert(doorCandidates, { gx, gy + 1 }) end
		end
	end
	local doorSet = {}
	for _ = 1, math.min(diff.buttons, #doorCandidates) do
		local c = table.remove(doorCandidates, rng:NextInteger(1, #doorCandidates))
		doorSet[c[1] .. "," .. c[2]] = true
	end
	local doorParts = {}
	for y = 0, gRows - 1 do
		for x = 0, gCols - 1 do
			if grid[y][x] then
				local wp = MazeGen.gridToWorld(x, y, gCols, gRows, S, origin)
				local isDoor = doorSet[x .. "," .. y]
				local wall = makePart({
					Name = isDoor and "SecretWall" or "Wall",
					Size = Vector3.new(S, CONFIG.WallHeight, S),
					Position = Vector3.new(wp.X, CONFIG.WallHeight / 2, wp.Z),
					Color = isDoor and Color3.fromRGB(70, 66, 78) or Color3.fromRGB(90, 94, 105),
					Material = Enum.Material.Slate,
				})
				wall.Parent = folder
				if isDoor then doorParts[x .. "," .. y] = wall end
			end
		end
	end

	-- Passasjeceller (plassering + monster-vandring) + plukk-pool
	local passageCells = {}
	for cy = 0, rows - 1 do
		for cx = 0, cols - 1 do
			table.insert(passageCells, { cx, cy })
			table.insert(inst.passages, MazeGen.cellCenterWorld(cx, cy, gCols, gRows, S, origin) + Vector3.new(0, 2, 0))
		end
	end
	local function isReserved(cx, cy) return (cx == 0 and cy == 0) or (cx == cols - 1 and cy == rows - 1) end
	local pool = {}
	for _, c in ipairs(passageCells) do if not isReserved(c[1], c[2]) then table.insert(pool, c) end end
	for i = #pool, 2, -1 do local j = rng:NextInteger(1, i); pool[i], pool[j] = pool[j], pool[i] end
	local function take(n)
		local out = {}
		for _ = 1, math.min(n, #pool) do table.insert(out, table.remove(pool)) end
		return out
	end

	-- Start + utgang
	local sw = MazeGen.cellCenterWorld(0, 0, gCols, gRows, S, origin)
	inst.spawnPos = Vector3.new(sw.X, 4, sw.Z)
	local ew = MazeGen.cellCenterWorld(cols - 1, rows - 1, gCols, gRows, S, origin)
	local pad = makePart({ Name = "Exit", Size = Vector3.new(S - 3, 1, S - 3),
		Position = Vector3.new(ew.X, 0.6, ew.Z), Color = Color3.fromRGB(60, 200, 90),
		Material = Enum.Material.Neon, CanCollide = false })
	pad.Parent = folder
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromScale(6, 1.5)
	bb.StudsOffset = Vector3.new(0, 4, 0); bb.AlwaysOnTop = true; bb.Parent = pad
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.new(1, 1, 1); lbl.TextStrokeTransparency = 0; lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold; lbl.Text = "EXIT"; lbl.Parent = bb
	pad.Touched:Connect(function(hit)
		local plr = Players:GetPlayerFromCharacter(hit.Parent)
		if plr and playerInstance[plr] == inst and finishRun then finishRun(plr, inst) end
	end)

	-- Mynter
	for _, c in ipairs(take(diff.coins)) do
		local w = MazeGen.cellCenterWorld(c[1], c[2], gCols, gRows, S, origin)
		local coin = makePart({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2),
			Color = Color3.fromRGB(250, 205, 50), Material = Enum.Material.Neon, CanCollide = false,
			CFrame = CFrame.new(w + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
		coin.Parent = folder
		table.insert(inst.spinners, coin)
		local grabbed = false
		coin.Touched:Connect(function(hit)
			if grabbed then return end
			local plr = Players:GetPlayerFromCharacter(hit.Parent); if not plr then return end
			grabbed = true; coin:Destroy()
			local d = playerData[plr]; if d then d.coins += 1; refreshStats(plr) end
			if playFx then playFx(plr, "coin") end
		end)
	end
	-- Edelstener
	for _, c in ipairs(take(diff.gems)) do
		local w = MazeGen.cellCenterWorld(c[1], c[2], gCols, gRows, S, origin)
		local gem = makePart({ Name = "Gem", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2),
			Position = w + Vector3.new(0, 3.2, 0), Color = Color3.fromRGB(170, 90, 240),
			Material = Enum.Material.Neon, CanCollide = false })
		gem.Parent = folder
		table.insert(inst.spinners, gem)
		local grabbed = false
		gem.Touched:Connect(function(hit)
			if grabbed then return end
			local plr = Players:GetPlayerFromCharacter(hit.Parent); if not plr then return end
			grabbed = true; gem:Destroy()
			local d = playerData[plr]; if d then d.gems += 1; refreshStats(plr) end
			if playFx then playFx(plr, "gem") end
		end)
	end
	-- Feller
	for _, c in ipairs(take(diff.traps)) do
		local w = MazeGen.cellCenterWorld(c[1], c[2], gCols, gRows, S, origin)
		makePart({ Name = "Trap", Size = Vector3.new(S - 2, 0.6, S - 2), Position = Vector3.new(w.X, 0.3, w.Z),
			Color = Color3.fromRGB(230, 90, 30), Material = Enum.Material.Neon, CanCollide = false })
			.Touched:Connect(killTouch)
		local trig = makePart({ Name = "TrapTrigger", Size = Vector3.new(S - 2, 10, S - 2),
			Position = Vector3.new(w.X, 5, w.Z), Transparency = 1, CanCollide = false })
		trig.Parent = folder
		trig.Touched:Connect(killTouch)
	end
	-- Skjulte knapper (senker en SecretWall)
	for _, c in ipairs(take(math.min(diff.buttons, 4))) do
		local key = next(doorParts)
		if not key then break end
		local doorPart = doorParts[key]; doorParts[key] = nil
		local w = MazeGen.cellCenterWorld(c[1], c[2], gCols, gRows, S, origin)
		local btn = makePart({ Name = "SecretButton", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3, 3),
			Color = Color3.fromRGB(60, 200, 220), Material = Enum.Material.Neon, CanCollide = false,
			CFrame = CFrame.new(w + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
		btn.Parent = folder
		local used = false
		btn.Touched:Connect(function(hit)
			if used then return end
			local plr = Players:GetPlayerFromCharacter(hit.Parent); if not plr then return end
			used = true; btn.Color = Color3.fromRGB(30, 90, 100)
			if doorPart and doorPart.Parent then
				doorPart.CanCollide = false
				TweenService:Create(doorPart, TweenInfo.new(0.7, Enum.EasingStyle.Quad),
					{ Position = doorPart.Position - Vector3.new(0, CONFIG.WallHeight + 2, 0) }):Play()
			end
		end)
	end
	-- Monstre
	for _, mc in ipairs(take(diff.monsters)) do
		makeInstanceMonster(inst, MazeGen.cellCenterWorld(mc[1], mc[2], gCols, gRows, S, origin), diff.monsterSpeed)
	end

	-- Par + medalje-terskler (utgang alltid åpen => korteste rute til utgangen).
	local startFine = { 1, 1 }
	local exitFine = { 2 * (cols - 1) + 1, 2 * (rows - 1) + 1 }
	local steps = Medals.solveRoute(grid, gCols, gRows, startFine, exitFine, {})
	inst.par = Medals.parTime(steps, CONFIG.CellSize, CONFIG.PlayerWalkSpeed)
	inst.thresholds = Medals.thresholds(inst.par)

	-- Spinn på mynter/edelstener
	local myGen = inst.gen
	task.spawn(function()
		while inst.gen == myGen and folder.Parent do
			for _, p in ipairs(inst.spinners) do
				if p.Parent then
					if p.Name == "Coin" then p.CFrame = p.CFrame * CFrame.Angles(math.rad(4), 0, 0)
					else p.CFrame = p.CFrame * CFrame.Angles(0, math.rad(4), 0) end
				end
			end
			task.wait(0.03)
		end
	end)
end

-- Send HUD-info for spillerens gjeldende instans (nivå + rekorder + accepted).
local function sendInstanceInfo(plr, inst)
	local d = playerData[plr]
	levelInfoEvent:FireClient(plr, {
		level = inst and inst.level or 0,
		thresholds = inst and inst.thresholds or nil,
		records = inst and getRecord(inst.level) or {},
		yourBest = (d and inst and d.bestByLevel) and d.bestByLevel[tostring(inst.level)] or nil,
		accepted = d and d.accepted or 0,
		bestWithGod = (d and GodUsers.has(plr)) and d.bestWithGod or nil,
		inLobby = (inst == nil),
	})
end

-- Start en solo-kjøring på et nivå (kan ikke over accepted+1).
local function startRun(plr, level)
	local d = playerData[plr]; if not d then return end
	level = math.clamp(math.floor(level or (d.accepted + 1)), 1, d.accepted + 1)
	if playerInstance[plr] then return end  -- alt i en instans
	nextInstanceId += 1
	local inst = {
		id = nextInstanceId, level = level,
		origin = Vector3.new(nextInstanceId * INSTANCE_SPACING, 0, 0),
		participants = { [plr] = true },
	}
	playerInstance[plr] = inst
	local ok, err = pcall(function() buildInstance(inst) end)
	if not ok then
		warn("[Labyrint] buildInstance feilet: " .. tostring(err))
		playerInstance[plr] = nil
		return
	end
	local char = plr.Character
	if char then pcall(function() char:PivotTo(CFrame.new(inst.spawnPos)) end) end
	startClock[plr] = os.clock()
	shieldUsed[plr] = false
	sendInstanceInfo(plr, inst)
end

-- Fullfør en kjøring: del ut accepted/rekord (Progression, per-instans hadGod),
-- riv instansen, send spilleren tilbake til lobbyen.
finishRun = function(plr, inst)
	-- Idempotent: utgangen gir MANGE Touched (flere lemmer), og getRecord under kan
	-- yield'e (DataStore). Krev at spilleren fortsatt er i DENNE instansen og claim
	-- den med en gang, så en runde bare belønnes ÉN gang.
	if playerInstance[plr] ~= inst then return end
	playerInstance[plr] = nil
	local d = playerData[plr]
	local level = inst.level
	if d then
		local st = startClock[plr]
		local elapsed = st and (os.clock() - st) or nil
		local clean = not inst.hadGod
		local medal, isNewPB, isNewRecord, recs
		if elapsed then
			if clean and elapsed < d.best then d.best = elapsed end
			local lkey = tostring(level)
			d.bestByLevel = d.bestByLevel or {}
			local prevPB = d.bestByLevel[lkey]
			isNewPB = clean and ((prevPB == nil) or (elapsed < prevPB))
			if isNewPB then d.bestByLevel[lkey] = elapsed end
			medal = Medals.medalFor(elapsed, inst.thresholds)
			recs = getRecord(level)
			local bestTime = recs[1] and recs[1].time or nil
			isNewRecord = clean and ((bestTime == nil) or (elapsed < bestTime))
			local worst = recs[3] and recs[3].time or nil
			local qualifies = (#recs < 3) or (worst and elapsed < worst)
			if clean and qualifies then
				local nl = {}
				for _, e in ipairs(recs) do nl[#nl + 1] = { time = e.time, name = e.name } end
				nl[#nl + 1] = { time = elapsed, name = plr.Name }
				table.sort(nl, function(a, b) return a.time < b.time end)
				while #nl > 3 do table.remove(nl) end
				recordCache[level] = nl; recs = nl
				task.spawn(function() tryUpdateRecord(level, elapsed, plr.Name) end)
			end
		end
		-- Progresjon: accepted +1 kun ved rent klarert accepted+1.
		local res = Progression.resolveClear({
			level = level, accepted = d.accepted, bestWithGod = d.bestWithGod,
			hadGod = inst.hadGod, mode = "solo", isHostLevel = true,
		})
		d.accepted = res.newAccepted; d.bestWithGod = res.newBestWithGod
		d.trophies += 1
		refreshStats(plr)
		if levelCompleteEvent and elapsed then
			levelCompleteEvent:FireClient(plr, {
				level = level, time = elapsed, yourBest = d.bestByLevel[tostring(level)],
				record = recs and recs[1] or nil, records = recs, medal = medal,
				isNewPB = isNewPB, isNewRecord = isNewRecord, thresholds = inst.thresholds,
			})
		end
		if res.acceptedGained and d.canSave ~= false and not GodUsers.has(plr) then
			submitTopScore(plr.UserId, d.accepted)
			refreshLeaderboard()
		end
		task.spawn(function() savePlayer(plr) end)
	end
	-- Riv instansen + send til lobby (playerInstance er alt nullstilt øverst).
	inst.gen = (inst.gen or 0) + 1  -- stopp løkker
	if inst.folder then inst.folder:Destroy() end
	local char = plr.Character
	if char then pcall(function() char:PivotTo(CFrame.new(LOBBY_ORIGIN + Vector3.new(0, 5, 0))) end) end
	sendInstanceInfo(plr, nil)
end

-- Bygg lobby-huben: gulv, spawn, og en "Solo Climb"-dør (ProximityPrompt).
local function buildLobby()
	local hub = Instance.new("Folder"); hub.Name = "Lobby"; hub.Parent = workspace
	makePart({ Name = "LobbyFloor", Size = Vector3.new(60, 2, 60),
		Position = LOBBY_ORIGIN + Vector3.new(0, -1, 0), Color = Color3.fromRGB(45, 48, 62),
		Material = Enum.Material.SmoothPlastic }).Parent = hub
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"; spawn.Anchored = true; spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = LOBBY_ORIGIN + Vector3.new(0, 0.5, 0); spawn.Color = Color3.fromRGB(60, 200, 90)
	spawn.Material = Enum.Material.Neon; spawn.Duration = 0; spawn.Parent = hub

	local door = makePart({ Name = "SoloDoor", Size = Vector3.new(8, 10, 2),
		Position = LOBBY_ORIGIN + Vector3.new(0, 5, -20), Color = Color3.fromRGB(70, 120, 200),
		Material = Enum.Material.Neon })
	door.Parent = hub
	local sign = Instance.new("BillboardGui"); sign.Size = UDim2.fromScale(8, 2)
	sign.StudsOffset = Vector3.new(0, 6, 0); sign.AlwaysOnTop = true; sign.Parent = door
	local sl = Instance.new("TextLabel"); sl.Size = UDim2.fromScale(1, 1); sl.BackgroundTransparency = 1
	sl.TextColor3 = Color3.new(1, 1, 1); sl.TextStrokeTransparency = 0; sl.TextScaled = true
	sl.Font = Enum.Font.GothamBold; sl.Text = "🧗 Solo Climb"; sl.Parent = sign
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Climb"; prompt.ObjectText = "Solo"; prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = door
	prompt.Triggered:Connect(function(plr)
		if playerInstance[plr] then return end
		local d = playerData[plr]
		startRun(plr, d and (d.accepted + 1) or 1)
	end)
end

-- Kalles fra onCharacterAdded ved hvert spawn i lobby-modus. Døde spilleren i en
-- instans, spawner Roblox dem på LobbySpawn — da river vi den forlatte instansen
-- og viser lobby-HUD. Første spawn (ingen instans): bare vis lobby-HUD.
handleLobbySpawn = function(plr)
	local inst = playerInstance[plr]
	if inst then
		playerInstance[plr] = nil
		inst.gen = (inst.gen or 0) + 1
		if inst.folder then inst.folder:Destroy() end
	end
	sendInstanceInfo(plr, nil)
end

--============================  START  ============================--
if CONFIG.UseLobby then
	Lighting.FogEnd = INSTANCE_FOG
	if CONFIG.Darkness then
		Lighting.ClockTime = 0; Lighting.Brightness = 1
		Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 28)
		Lighting.FogColor = Color3.fromRGB(8, 8, 12); Lighting.FogStart = 0
	end
	buildLobby()
	refreshLeaderboard()
	print("[Labyrint] Lobby-modus lastet.")
else
	applyDarkness()
	buildLevel()
	refreshLeaderboard()  -- fyll topplista-tavla ved oppstart
	print("[Labyrint] Lastet. Level " .. currentLevel .. " bygget. Lykke til!")
end
