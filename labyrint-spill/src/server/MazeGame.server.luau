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
	-- Ferdigbygd + gjennomgått: lobby PÅ. (Bryter noe live: sett false + publiser
	-- på nytt for umiddelbar rollback til v14-enkeltmaze-loopen.)
	UseLobby = true,

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
	-- Økt-lås (docs/complete-game-standard.md §1, 01.10): lasten tar låsen med et eier-token, hver lagring
	-- lander bare mens posten fortsatt bærer tokenet, og autolagringen fornyer låsen. To autolagringer må
	-- rekke innenfor én lås (check_labyrintspill_save §0), ellers kan en levende økt miste låsen sin.
	SessionLockSeconds = 180,
	AutosaveSeconds = 60,

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

	------------------------------------------------------------------
	-- FELLER: PULSENDE LAVA
	-- Labyrinten er et PERFEKT tre — det finnes nøyaktig ÉN rute fra start til
	-- utgang. Feller plasseres på en hvilken som helst passasjecelle, også på
	-- den eneste ruta, og en felle fyller hele korridoren (CellSize - 2 studs
	-- bred) med en 10 studs høy dødelig trigger: umulig å gå rundt, umulig å
	-- hoppe over. Det gjorde nivåer bokstavelig talt uløselige (en ekte spiller
	-- ga opp på "lava-dammen" rundt level 5-6 — første nivå med felle er 6).
	-- Nå PULSERER fella: TRYGG -> FORVARSEL (gul) -> DØDELIG -> TRYGG. Den er
	-- fortsatt livsfarlig, men det finnes alltid et vindu å gå gjennom i.
	-- Pulse = false gir eksakt gammel oppførsel (alltid dødelig) = rollback.
	------------------------------------------------------------------
	Traps = {
		Pulse = true,
		OffTime = 3.0,        -- sekunder ufarlig (forvarselet under er en del av denne)
		WarnTime = 0.8,       -- de siste sekundene av det trygge vinduet blinker gult
		OnTime = 2.2,         -- sekunder dødelig
		MinSafeSeconds = 1.5, -- gulv: for korte trygge vinduer klampes opp ved oppstart
	},

	------------------------------------------------------------------
	-- "HJELP MEG"-GUIDEN
	-- Hvert nivå er vanskeligere enn forrige, så før eller siden treffer alle en
	-- vegg. Har du feilet samme nivå OfferAfterFails ganger, tilbyr spillet en
	-- lysende rute til utgangen for MYNTER. Eierbeslutning 30.09: den beholdes til nivået
	-- er klart (dør du eller går ut, venter den der), aldri på et annet nivå (Assist.keptFor).
	-- Den hopper IKKE over noe: du må fortsatt gå ut selv, og en guide-kjøring
	-- gir ingen tidsrekord (se Progression.recordEligible). Enabled = false slår
	-- hele mekanikken av. Kun lobby-modus (CONFIG.UseLobby).
	------------------------------------------------------------------
	-- GÅ-VAKTA (01.10, docs/complete-game-standard.md §3): topplista rangerer på `accepted`, og bevegelse er
	-- klientens. En utgang nådd raskere enn noen kan gå dit (Progression.minClearSeconds: korteste rute med alle
	-- hemmelige dører åpne, hjørner skåret på skrå, i toppfart med speed-perken) teller ikke, og spilleren får vite
	-- hvorfor. Slack < 1 er margin; tests/Progression.spec viser at modellens raske spiller bruker minst 2x gulvet.
	-- Gude-runder hoppes over (de teller uansett ikke). Enabled = false slår vakta av.
	WalkGuard = {
		Enabled = true,
		Slack = 0.85,
		NoticeEverySeconds = 3,
	},

	Assist = {
		Enabled = true,
		OfferAfterFails = 3,   -- ekte, server-talte mislykkede forsøk på SAMME nivå
		MinRunSeconds = 8,     -- gikk du FRIVILLIG ut igjen raskere enn dette, teller
		                       -- det ikke som et forsøk (ellers kunne man låst opp
		                       -- tilbudet ved å gå inn og ut av døra). Død teller alltid.
		BasePrice = 40,        -- pris = BasePrice + PricePerLevel * nivå, tak MaxPrice
		PricePerLevel = 6,
		MaxPrice = 250,
		MaxTrailParts = 400,   -- tak på antall guide-merker (ytelse på store baner)
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
local HttpService = game:GetService("HttpService") -- bare GenerateGUID (eier-token for økt-låsen); ingen HTTP

-- ÉN veggklokke for topplista-cachene og gå-vakta (samme mønster som plus1-jump og fork-tower): GetServerTimeNow
-- der den finnes, ellers tick() (motorer uten den, og den hodeløse harnessen, der tick er den virtuelle klokka).
-- Spillets medalje-tider bruker fortsatt os.clock() som før; denne er bare for de nye reglene.
local clock
do
	local ok, t = pcall(function() return workspace:GetServerTimeNow() end)
	clock = if ok and typeof(t) == "number" then function() return workspace:GetServerTimeNow() end else tick
end

local Themes = require(ReplicatedStorage:WaitForChild("Themes"))
local ShopService = require(ReplicatedStorage:WaitForChild("ShopService"))
local Medals = require(ReplicatedStorage:WaitForChild("Medals"))
local PerkDefs = require(ReplicatedStorage:WaitForChild("PerkDefs"))
local PerkService = require(ReplicatedStorage:WaitForChild("PerkService"))
local GodUsers = require(ReplicatedStorage:WaitForChild("GodUsers"))
local Contributors = require(ReplicatedStorage:WaitForChild("Contributors"))
local Progression = require(ReplicatedStorage:WaitForChild("Progression"))
local MazeGen = require(ReplicatedStorage:WaitForChild("MazeGen"))
local Hazard = require(ReplicatedStorage:WaitForChild("Hazard"))
local Assist = require(ReplicatedStorage:WaitForChild("Assist"))
local Fx = require(ReplicatedStorage:WaitForChild("Fx"))
local LightingPresets = require(ReplicatedStorage:WaitForChild("LightingPresets"))
local MazeRef = require(ReplicatedStorage:WaitForChild("MazeRef"))
local Board = require(ReplicatedStorage:WaitForChild("Board"))             -- +1 Jumps mal, ordrett
local BoardConfig = require(ReplicatedStorage:WaitForChild("BoardConfig"))

-- Presetene lagrer farger som {r, g, b} 0-255 så de kan enhetstestes uten Roblox-API.
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Felle-vaktposten: uansett hva som står i CONFIG.Traps, sørg for at det trygge
-- vinduet er langt nok til å faktisk gå over ei felle. Slik kan ingen fremtidig
-- CONFIG-redigering gjenskape den umulige banen (felle som sperrer den eneste
-- ruta for godt). Blir noe rettet, sier vi tydelig fra i Output.
local TRAP_CFG = (function()
	local minSafe = Hazard.crossSeconds(CONFIG.CellSize, CONFIG.PlayerWalkSpeed)
	local cfg, fixes = Hazard.sanitize(CONFIG.Traps, minSafe)
	for _, f in ipairs(fixes) do
		warn("[Labyrint] CONFIG.Traps rettet for å holde nivåene løsbare: " .. f)
	end
	return cfg
end)()

-- Gå-vakta (CONFIG.WalkGuard): den raskeste en spiller kan gå = gangfarten + den største speed-perken.
local MAX_WALK_SPEED = (function()
	local bonus = 0
	for _, p in ipairs(PerkDefs.List) do bonus = math.max(bonus, p.speedBonus or 0) end
	return CONFIG.PlayerWalkSpeed + bonus
end)()

-- Visuell polish (kun kode, KONSERVATIV): Maze-presetet setter BEVISST ingen Lighting-
-- felter — kun post-fx (Atmosphere/Bloom/ColorCorrection/DepthOfField) LAGT OPPÅ. Det
-- rører altså ikke spillets egen per-nivå-tåke (FogEnd) eller fakkel-logikk.
Fx.applyLighting(Fx.Presets.Maze)

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

-- Global toppliste (docs/complete-game-standard.md §3, 01.10): HØYESTE nivå hver spiller har klart i sekvens
-- (`accepted`, gud-fritt, bak gå-vakta), delt på tvers av alle servere. v3 = +1 Jumps mal (Board.luau):
-- nøkkel u_<userId>, verdi nivå * 2e9 + (2e9 - nåddUnix), så uavgjort går til den som nådde nivået FØRST.
-- v2 (nøkkel tostring(userId), rått nivå) leses bare for å bære over topp-10 én gang per serverstart.
local boardStore, legacyBoardStore = nil, nil
if CONFIG.SaveData then
	local ok, ds = pcall(function() return DataStoreService:GetOrderedDataStore(BoardConfig.Store) end)
	if ok then boardStore = ds end
	local ok2, ds2 = pcall(function() return DataStoreService:GetOrderedDataStore(BoardConfig.LegacyStore) end)
	if ok2 then legacyBoardStore = ds2 end
end
local nameCache = {}          -- [userId] = navn (i minnet, aldri lagret)
local leaderboardEvent        -- RemoteEvent (fylles ut i HUD-seksjonen): HUD-panelets topp 10
local boardEvent              -- RemoteEvent (fylles ut i HUD-seksjonen): den fysiske tavlas visning, per spiller

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
local runStartAt = {}         -- [player] = clock() da spilleren ble satt på starten av nivået (gå-vakta)
local guardNoticeAt = {}      -- [player] = clock() da gå-vakta sist sa fra (ikke spam banneret)
local shieldUsed = {}         -- [player] = true hvis skjold-perk er brukt på gjeldende nivå
local invulnUntil = {}        -- [player] = os.clock()-tid uskadelig til (kort vindu etter skjold)
local godActive = {}          -- [player] = true hvis gudemodus er på (kun GodUsers)
local levelHadGod = false     -- true hvis NOEN brukte gud på gjeldende nivå (nullstilles pr bygging)
local playerInstance = {}     -- LOBBY-MODUS: [player] = instansen de er inne i (nil = lobbyen)
local stuckState = {}         -- [player] = { level, fails } — server-talte mislykkede forsøk
                              -- (grunnlaget for "Hjelp meg"-guiden; klienten kan ikke røre den)
local handleLobbySpawn        -- forhånds-deklarert; fylles ut i lobby-seksjonen
local teardownPlayerInstance  -- forhånds-deklarert; fjerner spiller fra instans + rydder

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

--========================  FELLER (PULS)  ========================--
-- Se CONFIG.Traps for HVORFOR. Kort: labyrinten har bare ÉN rute, en felle
-- sperrer hele korridoren, og før pulsen kunne det gjøre nivået uløselig.
-- Alle feller i SAMME labyrint pulserer i takt — da er det lett å lese timingen,
-- og ett trygt vindu holder til å løpe forbi flere feller på rad.

-- Hvordan fella SER ut i hver fase. "warn" er ufarlig; den er forvarselet.
local TRAP_LOOK = {
	safe   = { Color = Color3.fromRGB(74, 46, 38),   Material = Enum.Material.Slate, Transparency = 0.4 },
	warn   = { Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Neon,  Transparency = 0.25 },
	deadly = { Color = Color3.fromRGB(230, 90, 30),  Material = Enum.Material.Neon,  Transparency = 0 },
}

-- Felle-kontekst: samler alle fellene i én labyrint så de deler klokke og fase.
-- deadly = true fra start hvis pulsen er av (da er oppførselen som før).
local function newTrapCtx()
	return { traps = {}, deadly = (TRAP_CFG.Pulse == false), t0 = os.clock(), phase = nil }
end

-- Bygg én felle i `folder` på verdens-punktet `w` og registrer den i `ctx`.
-- Samme deler og samme mål som før; det eneste nye er at treffet er fase-styrt.
local function spawnTrap(ctx, folder, w)
	local S = CONFIG.CellSize
	local pad = makePart({
		Name = "Trap", Size = Vector3.new(S - 2, 0.6, S - 2),
		Position = Vector3.new(w.X, 0.3, w.Z),
		Color = TRAP_LOOK.deadly.Color, Material = TRAP_LOOK.deadly.Material,
		CanCollide = false,
	})
	pad.Parent = folder                 -- MÅ parentes ellers vises den ikke / fyrer ikke Touched
	-- Usynlig, høyere trigger så man ikke sklir/hopper "over" den tynne fella i fart.
	local trig = makePart({
		Name = "TrapTrigger", Size = Vector3.new(S - 2, 10, S - 2),
		Position = Vector3.new(w.X, 5, w.Z), Transparency = 1, CanCollide = false,
	})
	trig.Parent = folder
	-- Dreper BARE i dødelig fase. Touched fyrer hele tiden; fasen bestemmer.
	local function hurt(hit)
		if ctx.deadly then killTouch(hit) end
	end
	pad.Touched:Connect(hurt)
	trig.Touched:Connect(hurt)
	table.insert(ctx.traps, { pad = pad, trig = trig })
end

-- Sett fase på alle fellene i konteksten (farge/materiale + dødelig-flagget).
local function applyTrapPhase(ctx, phase)
	local look = TRAP_LOOK[phase] or TRAP_LOOK.deadly
	local nowDeadly = (phase == "deadly")
	local justLit = nowDeadly and not ctx.deadly
	ctx.deadly = nowDeadly
	ctx.phase = phase
	for _, t in ipairs(ctx.traps) do
		if t.pad.Parent then
			t.pad.Color = look.Color
			t.pad.Material = look.Material
			t.pad.Transparency = look.Transparency
		end
		-- Sto noen OPPÅ fella i det den tente? Touched fyrer ikke på nytt for den
		-- som allerede står der, så vi må sjekke selv — ellers ville "stå stille
		-- på lavaen" vært helt trygt.
		if justLit and t.trig.Parent then
			local ok, parts = pcall(function() return t.trig:GetTouchingParts() end)
			if ok and parts then
				for _, p in ipairs(parts) do killTouch(p) end
			end
		end
	end
end

-- Kjør pulsen til `alive()` blir false (nivået bygges om / instansen rives).
-- Fasen regnes av ren logikk (Hazard), så den er testet uten Roblox.
local function runTrapPulse(ctx, alive)
	if TRAP_CFG.Pulse == false then return end        -- rollback: alltid dødelig
	if #ctx.traps == 0 then return end
	applyTrapPhase(ctx, Hazard.phaseAt(0, TRAP_CFG))  -- riktig utseende med en gang
	task.spawn(function()
		while alive() do
			local phase = Hazard.phaseAt(os.clock() - ctx.t0, TRAP_CFG)
			if phase ~= ctx.phase then applyTrapPhase(ctx, phase) end
			task.wait(0.1)
		end
	end)
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

--===================  TOPPLISTE: OFFENTLIG + VENNER  =============--
-- (docs/complete-game-standard.md §3, eier 16.09; bygget 01.10 etter +1 Jumps mal.) Metrikken er `accepted`,
-- målt av serveren ved utgangen (finishRun, bak gå-vakta Progression.minClearSeconds), skrevet bare når den stiger
-- (writeBoard), kodet med tidspunktet den ble nådd (Board.encode). Offentlig topp 10 hentes høyst én gang per
-- PublicCacheSeconds og vises BÅDE i HUD-panelet (LeaderboardClient, som før) og på tavla ved spawn i lobbyen.
-- Venner hentes først når en spiller ber om dem på tavla (ProximityPrompt), capet, cachet og strupet. Tavla
-- tegnes av klienten (BoardClient): hver spiller ser sin egen visning. Navn slås opp og huskes i minnet, aldri lagret.
local BC = BoardConfig
local boardMode = {}          -- [plr] = "public" | "friends"
local publicView = { rows = {}, note = BC.Text.Loading }

-- Navn: fra spillere på serveren, venne-lista eller GetNameFromUserIdAsync; husket i minnet, aldri lagret.
local function nameOf(userId)
	-- en spiller på serveren først (som den gamle resolveName): et navn som er byttet siden sist, vises riktig
	local here = Players:GetPlayerByUserId(userId)
	if here then
		nameCache[userId] = here.Name
		return here.Name
	end
	local cached = nameCache[userId]
	if cached then return cached end
	local ok, res = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	if ok and typeof(res) == "string" and res ~= "" then
		nameCache[userId] = res
		return res
	end
	return "#" .. tostring(userId) -- ikke husket: neste visning prøver igjen
end
local function withNames(rows)
	local out = {}
	for i, r in ipairs(rows) do
		out[i] = { rank = r.rank, userId = r.userId, tier = r.tier, you = r.you, name = nameOf(r.userId) }
	end
	return out
end

-- En spillers egen verdi fra minnet (ferskere enn datastoren). Gude-spillere står aldri på tavla.
local function liveValue(plr)
	local d = plr and playerData[plr]
	if not d or (d.accepted or 0) <= 0 or GodUsers.has(plr) then return 0 end
	return Board.encode(d.accepted, d.acceptedAt or os.time(), BC)
end

-- HUD-panelet (LeaderboardClient) får samme offentlige topp 10 i sin gamle form: { { name, level } }.
local function broadcastLeaderboard(plr)
	if not leaderboardEvent then return end
	local list = {}
	for i, r in ipairs(publicView.rows) do list[i] = { name = r.name, level = r.tier } end
	if plr then leaderboardEvent:FireClient(plr, list) else leaderboardEvent:FireAllClients(list) end
end

local function sendBoard(plr, mode, view)
	-- `viewer`: FireClient når bare denne spilleren i Roblox; feltet lar klienten se bort fra alt annet.
	if boardEvent then
		boardEvent:FireClient(plr, { viewer = plr.UserId, mode = mode, rows = view.rows, note = view.note })
	end
end

local function refreshPublic()
	if not boardStore then
		publicView = Board.publicView({}, BC)
		return
	end
	-- Feiler hentingen, beholdes forrige liste. Har tavla aldri fått noe å vise (den første hentingen etter oppstart
	-- feilet: utfall, eller Studio uten API-tilgang), sier den det i stedet for å stå på "Loading..." for alltid.
	local function failed()
		if #publicView.rows == 0 then publicView = { rows = {}, note = BC.Text.PublicFailed } end
	end
	local ok, page = pcall(function() return boardStore:GetSortedAsync(false, BC.PublicRows) end)
	if not ok or not page then failed(); return end
	local okPage, items = pcall(function() return page:GetCurrentPage() end)
	if not okPage or typeof(items) ~= "table" then failed(); return end
	local entries = {}
	for _, e in ipairs(items) do
		local uid = Board.userIdOf(tostring(e.key))
		if uid and typeof(e.value) == "number" then table.insert(entries, { userId = uid, value = e.value }) end
	end
	local view = Board.publicView(entries, BC)
	publicView = { rows = withNames(view.rows), note = view.note }
end

local function pushPublic()
	broadcastLeaderboard()
	for _, p in ipairs(Players:GetPlayers()) do
		if (boardMode[p] or "public") == "public" then sendBoard(p, "public", publicView) end
	end
end

-- Skriv spillerens `accepted` når den har steget over det som sist ble skrevet (boardLevel), og aldri lavere enn
-- det som står der (Board.keepHigher avbryter). Bare en økt som holder låsen skriver; gude-spillere aldri.
local function writeBoard(plr)
	local d = playerData[plr]
	if not boardStore or not d or d.canSave == false or not d.session or GodUsers.has(plr) then return end
	local level = d.accepted or 0
	if level <= (d.boardLevel or 0) then return end
	local value = Board.encode(level, d.acceptedAt or os.time(), BC)
	local ok = pcall(function()
		boardStore:UpdateAsync(Board.key(plr.UserId), function(old) return Board.keepHigher(old, value) end)
	end)
	if ok then d.boardLevel = math.max(d.boardLevel or 0, level) end -- også når keepHigher avbrøt
end

-- Den gamle tavla (v2) sin topp 10 bæres over én gang per serverstart. Når de ble nådd er ukjent, men det var
-- før BC.LegacyReachedAt. keepHigher gjør det trygt å gjøre om igjen: et like høyt eller høyere v3-tall står.
local function carryLegacyBoard()
	if not boardStore or not legacyBoardStore then return end
	local ok, page = pcall(function() return legacyBoardStore:GetSortedAsync(false, BC.PublicRows) end)
	if not ok or not page then return end
	local okPage, items = pcall(function() return page:GetCurrentPage() end)
	if not okPage or typeof(items) ~= "table" then return end
	for _, e in ipairs(items) do
		local uid, lvl = tonumber(e.key), tonumber(e.value)
		if uid and lvl and lvl >= 1 then
			local value = Board.encode(math.floor(lvl), BC.LegacyReachedAt, BC)
			pcall(function()
				boardStore:UpdateAsync(Board.key(uid), function(old) return Board.keepHigher(old, value) end)
			end)
		end
	end
end

-- Venner: kun på forespørsel, capet på FriendsCap, cachet per spiller. En feilet henting prøves igjen etter et
-- minutt, ikke på hvert trykk.
local friendsCache = Board.newCache(BC.FriendsCacheSeconds)
local friendsFailed = Board.newCache(60)
local scoreCache = Board.newCache(BC.ScoreCacheSeconds)
local readLimiter = Board.newLimiter(BC.ReadsBurst, BC.ReadsPerSecond, clock())
local boardFetching = {}

local function friendIdsOf(plr)
	local now = clock()
	local hit = Board.cacheGet(friendsCache, plr.UserId, now)
	if hit then return hit, false end
	if Board.cacheHas(friendsFailed, plr.UserId, now) then return {}, true end
	local ok, pages = pcall(function() return Players:GetFriendsAsync(plr.UserId) end)
	local ids = {}
	local broken = not ok or pages == nil
	while not broken and #ids < BC.FriendsCap do
		local okPage, items = pcall(function() return pages:GetCurrentPage() end)
		if not okPage or typeof(items) ~= "table" then
			broken = #ids == 0
			break
		end
		for _, item in ipairs(items) do
			local id = tonumber(item.Id)
			if id and #ids < BC.FriendsCap then
				table.insert(ids, id)
				if typeof(item.Username) == "string" then nameCache[id] = item.Username end
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
local function budgetLeft()
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
	end)
	return not (ok and typeof(budget) == "number" and budget < BC.BudgetReserve)
end

-- En venns lagrede verdi (0 = har ikke klart et nivå), eller nil når lesingen er strupet (prøv igjen senere). En
-- lesing som feiler teller som 0 uten å caches, så én dårlig nøkkel ikke stopper lista.
local function friendValue(userId)
	local here = Players:GetPlayerByUserId(userId)
	if here and playerData[here] then return liveValue(here) end
	local now = clock()
	if Board.cacheHas(scoreCache, userId, now) then return Board.cacheGet(scoreCache, userId, now) end
	if not boardStore then return 0 end
	if not budgetLeft() or not Board.take(readLimiter, now) then return nil end
	local ok, v = pcall(function() return boardStore:GetAsync(Board.key(userId)) end)
	if not ok then return 0 end
	local value = (typeof(v) == "number") and v or 0
	Board.cachePut(scoreCache, userId, value, now)
	return value
end

local function showFriends(plr)
	if boardFetching[plr] then
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading }) -- den som går, sender snart
		return
	end
	boardFetching[plr] = true
	task.spawn(function()
		sendBoard(plr, "friends", { rows = {}, note = BC.Text.Loading })
		local ids, failedList = friendIdsOf(plr)
		local values = {}
		local status = { friendCount = #ids, checked = 0, failed = failedList }
		local function push()
			values[plr.UserId] = liveValue(plr)
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
		boardFetching[plr] = nil
	end)
end

local function toggleBoard(plr)
	boardMode[plr] = if boardMode[plr] == "friends" then "public" else "friends"
	if boardMode[plr] == "friends" then
		showFriends(plr)
	else
		sendBoard(plr, "public", publicView)
	end
end

--============================  LAGRING  ==========================--
-- Økt-lås + eier-token (docs/complete-game-standard.md §1; mønsteret er fork-tower sitt `old.session`).
-- Posten er fortsatt FLAT (samme felt som før, der de var) og har fått tre til: `session` (eier-tokenet denne
-- øktas last skrev), `lockUntil` (unix-sekunder; 0 = sluppet) og `jobId`. Regler:
--   * lasten er én UpdateAsync: den leser ALLTID ekte data, og tar låsen bare hvis ingen annen levende server
--     holder den (en annen jobId med lockUntil i framtida). Holder en annen den, spiller økta READ-ONLY med ekte
--     data og får beskjed; en lås som har gått ut (krasjet server) tas over.
--   * hver lagring er en UpdateAsync som lander bare mens posten bærer VÅRT token. Har en nyere økt tatt posten,
--     avbrytes skrivingen, økta slutter å lagre (canSave = false) og spilleren får vite hvorfor.
--   * autolagringen (AutosaveSeconds) fornyer låsen; å gå ut og BindToClose slipper den (lockUntil = 0).
--   * engangs-gaver (start-gave, bidragsyter, daglig belønning) gis INNE i én slik skriving (grantOnce): lander
--     den ikke, rulles gaven tilbake i minnet, så den verken går tapt i en halv tilstand eller kan tas to ganger.
-- check_labyrintspill_save holder hver av disse.
local notifyPlayer -- forhånds-deklarert: (plr, tekst) -> banneret øverst hos den ene spilleren (HUD-seksjonen)

local function playerKey(plr) return "p_" .. plr.UserId end

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
		local token = HttpService:GenerateGUID(false)
		local saved, lockedByOther = nil, false
		local ok, err = pcall(function()
			dataStore:UpdateAsync(playerKey(plr), function(old)
				-- Transformen kan kjøres flere ganger; bare siste kjøring teller, så alt settes på nytt hver gang.
				saved = old
				local now = os.time()
				lockedByOther = typeof(old) == "table" and old.session ~= nil
					and (tonumber(old.lockUntil) or 0) > now and old.jobId ~= game.JobId
				if lockedByOther then return nil end -- en annen levende server eier posten: ikke rør den
				local rec = (typeof(old) == "table") and old or {}
				rec.session = token
				rec.lockUntil = now + CONFIG.SessionLockSeconds
				rec.jobId = game.JobId
				return rec
			end)
		end)
		if not ok then
			-- Lese-feil: vi vet ikke hva som er lagret, så økta lagrer ingenting (aldri default over ekte data).
			loadOk = false
			saved = nil
			d.pendingNotice = "Your saved progress could not be loaded right now, so this session will not be saved. Rejoin in a minute to keep your progress."
			warn("[Labyrint] lasten feilet for " .. plr.Name .. " (" .. tostring(err) .. "): økta er read-only")
		elseif lockedByOther then
			loadOk = false
			d.pendingNotice = "Your progress is open in another server right now, so this session will not be saved. Rejoin in a minute to keep your progress."
			warn("[Labyrint] " .. plr.Name .. " er låst av en annen server: økta er read-only")
		else
			d.session = token
		end
		if typeof(saved) == "table" then
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
			-- (eierbeslutning 30.09) nivået en kjøpt "Hjelp meg"-guide venter på (Assist.keptFor)
			if typeof(saved.guideLevel) == "number" and saved.guideLevel >= 1 then d.guideLevel = math.floor(saved.guideLevel) end
			-- (01.10) topplista: når `accepted` ble nådd (uavgjort til den som var først), og hva som sist ble skrevet dit
			if typeof(saved.acceptedAt) == "number" and saved.acceptedAt > 0 then d.acceptedAt = math.floor(saved.acceptedAt) end
			if typeof(saved.boardLevel) == "number" then d.boardLevel = math.floor(saved.boardLevel) end
		end
	end
	-- Migrering: mangler spilleren "accepted" (nytt felt), seed fra personlige
	-- rekorder — høyeste sammenhengende nivå de faktisk har fullført. Slik beholdes
	-- ekte fremgang uten å importere oppblåste/carry-tall.
	if d.accepted == 0 then
		d.accepted = Progression.seedAccepted(d.bestByLevel)
	end
	d.bestWithGod = math.max(d.bestWithGod, d.accepted, d.level or 0)
	-- Lagret før 01.10: nivået uten tidspunkt. Når det ble nådd er ukjent, så det stemples med denne økta (det kommer
	-- på topplista ved første skriving, bak alle som nådde samme nivå før).
	if d.accepted > 0 and not d.acceptedAt then d.acceptedAt = os.time() end
	d.owned.classic = true                                    -- classic eies alltid
	if not d.owned[d.theme] then d.theme = Themes.default end -- kan ikke ha valgt et uleid tema
	d.canSave = loadOk                                       -- false: lasten feilet, eller en annen server har låsen
	playerData[plr] = d
	refreshStats(plr)
end

-- `release` = spilleren går / serveren stenger: slipp låsen (lockUntil = 0). Returnerer true når skrivingen
-- faktisk landet (kjøp med ekte penger og engangs-gaver ruller tilbake ellers).
local function savePlayer(plr, release)
	local d = playerData[plr]
	if not d or not dataStore then return false end
	if d.canSave == false or not d.session then return false end  -- read-only økt: aldri skriv over ekte lagring
	local lost = false
	local ok = pcall(function()
		dataStore:UpdateAsync(playerKey(plr), function(old)
			-- EIERSKAP: lander bare mens posten bærer tokenet denne øktas last skrev. `lost` settes på hver kjøring.
			if typeof(old) ~= "table" or old.session ~= d.session then
				lost = true
				return nil
			end
			lost = false
			return {
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
				guideLevel = d.guideLevel,
				acceptedAt = d.acceptedAt,
				boardLevel = d.boardLevel,
				session = d.session,
				jobId = game.JobId,
				lockUntil = (release or d.released) and 0 or (os.time() + CONFIG.SessionLockSeconds),
			}
		end)
	end)
	if lost then
		-- En nyere økt eier posten nå. Ingenting denne gjør blir tatt vare på herfra, så den slutter å skrive.
		d.canSave = false
		warn("[Labyrint] " .. plr.Name .. ": en nyere økt har tatt over posten; denne økta lagrer ikke lenger")
		if notifyPlayer and plr.Parent then
			notifyPlayer(plr, "Your progress is now open in another server, so this session stops saving. Rejoin to keep playing where you left off.")
		end
		return false
	end
	return ok
end

-- Engangs-gave: `apply` gir den i minnet, og den står bare hvis den samme skrivingen lander (savePlayer over).
-- Feiler skrivingen, gjør `undo` den ugjort igjen: aldri en gave som kan tas på nytt, aldri en halv.
local function grantOnce(plr, apply, undo)
	local d = playerData[plr]
	if not d or d.canSave == false then return false end
	apply(d)
	if savePlayer(plr) then return true end
	undo(d)
	return false
end

-- Debouncet lagring for hyppige, ikke-kritiske endringer (kjøp/valg av tema).
-- Slår sammen mange raske endringer til én skriving, så en klient ikke kan
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

	-- Feller (pulserende — se CONFIG.Traps + "FELLER (PULS)")
	local trapCtx = newTrapCtx()
	for _, c in ipairs(take(diff.traps)) do
		spawnTrap(trapCtx, folder, cellCenterWorld(c[1], c[2], gCols, gRows))
	end
	runTrapPulse(trapCtx, function() return gen == currentGen end)

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
			-- (Gammel enkelt-maze-modus har ingen instanser, altså ingen guide.)
			local clean = Progression.recordEligible(levelHadGod, false)
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
			if res.acceptedGained then
				acceptedGainers[p] = true
				pd.acceptedAt = os.time() -- topplista: uavgjort til den som nådde nivået først
			end
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
				if acceptedGainers[p] then task.spawn(writeBoard, p) end -- writeBoard sjekker lås og GodUsers
			end
		end
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

-- Den fysiske topplista-tavlas visning, per spiller (BoardClient tegner den). Forhånds-deklarert over.
boardEvent = Instance.new("RemoteEvent")
boardEvent.Name = "Board"
boardEvent.Parent = hudFolder

-- Admin-kringkasting (/bc): vises i et gjennomsiktig felt øverst hos ALLE spillere.
-- Samme RemoteEvent begge veier: klienten FireServer(text) for å be om kringkasting;
-- serveren verifiserer admin + filtrerer + FireAllClients(navn, tekst) for å vise.
local broadcastEvent = Instance.new("RemoteEvent")
broadcastEvent.Name = "Broadcast"
broadcastEvent.Parent = hudFolder

-- Spillets egne beskjeder til ÉN spiller (aldri stille: en nektet handling sier hvorfor) i samme banner.
notifyPlayer = function(plr, text)
	broadcastEvent:FireClient(plr, "Labyrint", text)
end

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
		-- Delt-maze-modus har ingen lobby. LightingClient bruker flagget til å velge
		-- mørke-presetet; uten det ville den falle tilbake til lys hub og fjerne mørket.
		inLobby = false,
		-- Sikten strammes inn med nivået; klienten speiler den i stedet for å gjette.
		fog = getDifficulty(currentLevel).sight,
		-- Uten flagget svarter klienten ut verden mens serveren dropper å dele ut fakler:
		-- en helsvart labyrint uten lys. Darkness=false skal gi et OPPLYST spill.
		darkness = CONFIG.Darkness,
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
	if (boardMode[plr] or "public") == "public" then sendBoard(plr, "public", publicView) end -- tavla ved spawn

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
	-- Read-only økt (lasten feilet, eller en annen server har låsen): si det, aldri stille.
	if d and d.pendingNotice and notifyPlayer then
		local text = d.pendingNotice
		d.pendingNotice = nil
		task.delay(2.5, function()
			if plr.Parent then notifyPlayer(plr, text) end
		end)
	end
end

-- plr.RespawnLocation = lobby-platen (robloxemu/SPAWN-ORDER.md regel 1, motorens FØRSTE valg). Den er i dag
-- den eneste SpawnLocation-en i verden, så motoren fant den uansett; nå trenger den ikke lete. Kalles for hver
-- som blir med, og én gang etter buildLobby for dem som var her før lobbyen fantes (Studio-play).
local function pointRespawn(plr)
	local lobby = workspace:FindFirstChild("Lobby")
	local pad = lobby and lobby:FindFirstChild("LobbySpawn")
	if pad and pad:IsA("SpawnLocation") then plr.RespawnLocation = pad end
end

local function onPlayerAdded(plr)
	pointRespawn(plr)
	loadPlayer(plr)
	task.spawn(writeBoard, plr) -- et nivå som aldri kom på tavla (lagret før 01.10, eller en tapt skriving) kommer dit nå

	-- Engangs-gavene under gis alle med grantOnce: i minnet, og står bare hvis den ene skrivingen lander.
	-- En read-only økt (canSave == false) gir ingenting den ikke kan lagre.
	local d = playerData[plr]

	-- Del ut start-gaven til spesielle spillere (samme liste som gudemodus).
	if d and d.canSave ~= false and GodUsers.has(plr) and not (d.gifts or {})[STARTER_GIFT.id] then
		d.gifts = d.gifts or {}
		local granted = grantOnce(plr, function(pd)
			pd.coins += STARTER_GIFT.coins
			pd.gems += STARTER_GIFT.gems
			pd.gifts[STARTER_GIFT.id] = true
		end, function(pd)
			pd.coins -= STARTER_GIFT.coins
			pd.gems -= STARTER_GIFT.gems
			pd.gifts[STARTER_GIFT.id] = nil
		end)
		if granted then
			refreshStats(plr)
			sendShopData(plr)
		end
	end

	-- Bidragsyter-belønning: hjelpere hvis content-bidrag FAKTISK er tatt i bruk
	-- (se Contributors-lista) får en engangs-bonus første gang de blir med. Samme
	-- idempotens-mønster som start-gaven (d.gifts[REWARD.id]). Navnet vises også på
	-- "Content Contributors"-tavla i lobbyen.
	if d and d.canSave ~= false and Contributors.has(plr) and Contributors.shouldReward(true, d.gifts or {}) then
		d.gifts = d.gifts or {}
		local granted = grantOnce(plr, function(pd)
			pd.coins += Contributors.REWARD.coins
			pd.gems += Contributors.REWARD.gems
			pd.gifts[Contributors.REWARD.id] = true
		end, function(pd)
			pd.coins -= Contributors.REWARD.coins
			pd.gems -= Contributors.REWARD.gems
			pd.gifts[Contributors.REWARD.id] = nil
		end)
		if granted then
			refreshStats(plr)
			sendShopData(plr)
		end
	end

	-- Daglig belønning (retention): første innlogging på en ny UTC-dag gir mynter,
	-- og en streak-bonus som vokser den første uka + en liten edelsten-bonus hver
	-- 7. dag. Stashes i d.pendingReward og vises som en toast ved første spawn — bare når den er lagret.
	if d and d.canSave ~= false then
		local today = math.floor(os.time() / 86400)
		if d.rewardDay ~= today then
			local oldDay, oldStreak = d.rewardDay, d.streak
			local streak = (d.rewardDay == today - 1) and ((d.streak or 0) + 1) or 1 -- hull i rekka: start på nytt
			local coinReward = 150 * math.min(streak, 7)      -- 150 .. 1050
			local gemReward = (streak % 7 == 0) and 5 or 0     -- gullbonus hver 7. dag
			local granted = grantOnce(plr, function(pd)
				pd.streak = streak
				pd.rewardDay = today
				pd.coins += coinReward
				pd.gems += gemReward
			end, function(pd)
				pd.streak = oldStreak
				pd.rewardDay = oldDay
				pd.coins -= coinReward
				pd.gems -= gemReward
			end)
			if granted then
				d.pendingReward = { coins = coinReward, gems = gemReward, streak = streak }
				refreshStats(plr)
			end
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
	-- Flush umiddelbart OG slipp låsen. `released` først: en lagring som allerede er på vei (finishRun,
	-- debounce) og lander ETTER denne, slipper låsen den også, i stedet for å låse posten igjen i
	-- SessionLockSeconds så spillerens neste server må spille read-only.
	if playerData[plr] then playerData[plr].released = true end
	savePlayer(plr, true)
	-- Lobby-modus: forlot spilleren en instans, fjern dem (riv om tom, prune lister).
	if teardownPlayerInstance then teardownPlayerInstance(plr) end
	playerData[plr] = nil
	startClock[plr] = nil
	saveScheduled[plr] = nil
	shieldUsed[plr] = nil
	invulnUntil[plr] = nil
	godActive[plr] = nil
	stuckState[plr] = nil
	boardMode[plr] = nil
	boardFetching[plr] = nil
	runStartAt[plr] = nil
	guardNoticeAt[plr] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		if playerData[plr] then playerData[plr].released = true end
		savePlayer(plr, true)
	end
end)

-- Autolagring: fornyer låsen (to runder rekker innenfor SessionLockSeconds) og tar vare på det som ikke
-- lagres ved hendelser. En økt som har mistet eller aldri fikk låsen (canSave == false) hoppes over.
task.spawn(function()
	while true do
		task.wait(CONFIG.AutosaveSeconds)
		for _, p in ipairs(Players:GetPlayers()) do
			local pd = playerData[p]
			if pd and pd.canSave ~= false and pd.session then
				task.spawn(savePlayer, p)
				-- en tavle-skriving som gikk tapt (utfall) prøves igjen her; writeBoard gjør ingen kall når intet er skyldig
				task.spawn(writeBoard, p)
			end
		end
	end
end)

--====================  LOBBY + PER-SPILLER-INSTANSER  ============--
-- Ny modus (CONFIG.UseLobby). En lobby-hub der alle spawner + går inn i "doors";
-- hver kjøring bygger en EGEN labyrint-instans langt unna de andre, så ingen dras
-- med på et for høyt nivå. Gjenbruker MazeGen + makePart + killTouch +
-- findNearestPlayerRoot. Utgangen er alltid åpen (CONFIG.UnlockExitBy = "none").
local LOBBY_ORIGIN = Vector3.new(0, 0, 0)
local INSTANCE_SPACING = 6000       -- studs mellom instanser (godt utenfor sikt/range)
-- Huben er lys. Startverdiene serveren setter kommer fra ReplicatedStorage.LightingPresets,
-- delt med LightingClient som eier lyset per spiller fra første payload (Lighting er global på
-- serveren, og to spillere kan stå i hver sin instans samtidig). Ingen håndkopierte tall her:
-- de to kopiene drev fra hverandre innen et døgn sist.
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

local finishRun       -- forward-deklarert (buildInstance kobler exit-touch til den)
local returnToLobby   -- forward-deklarert (buildInstance kobler retur-døra til den)

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
	inst.assist = false   -- "Hjelp meg"-guiden hører til nivået: nullstilles pr bygging (applyKeptGuide tenner en beholdt)
	inst.trail = nil

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
	-- Hemmelige dorer velges IKKE her lenger. En dor uten knapp er en vegg spilleren SER at er
	-- annerledes, leter etter bryteren til, og aldri kan apne. En spiller rapporterte nettopp
	-- det: "There were 2 doors but only for one of them there was a switch." Antallene kom fra
	-- to urelaterte uttrykk -- dorer fra min(diff.buttons, #doorCandidates), knapper fra
	-- take(min(diff.buttons, 4)) -- og diff.buttons er 3 + floor(level / 170), sa fra niva 340
	-- garanterte taket alene en foreldrelos dor i HVER labyrint.
	--
	-- Na bygges alle vegger like, og en vegg gjores om til hemmelig dor forst NAR den har fatt
	-- sin knapp (se knappe-blokka lenger ned). Da kan antallene ikke sprike, uansett hvor mange
	-- celler `take` faktisk klarer a gi.
	-- Dorene VELGES her, pa nøyaktig samme punkt og med noyaktig like mange rng-trekk som for.
	-- Det er ikke pynt: `pool` (der mynter, edelstener, feller og monstre plukkes fra) Fisher-
	-- Yates-stokkes med SAMME rng noen linjer lenger ned. Flytter man disse trekkene, starter
	-- stokkingen fra en annen tilstand og alt innhold i HVERT nivaa trekkes pa nytt. Nivaaene er
	-- delte og deterministiske, sa det ville stille om baner spillere har lart seg.
	-- Valget er bare en PLAN her; en vegg blir forst en dor nar den faktisk har fatt en knapp.
	local plannedDoors = {}
	for _ = 1, math.min(diff.buttons, #doorCandidates) do
		local c = table.remove(doorCandidates, rng:NextInteger(1, #doorCandidates))
		table.insert(plannedDoors, c[1] .. "," .. c[2])
	end
	local wallByKey = {}
	for y = 0, gRows - 1 do
		for x = 0, gCols - 1 do
			if grid[y][x] then
				local wp = MazeGen.gridToWorld(x, y, gCols, gRows, S, origin)
				local wall = makePart({
					Name = "Wall",
					Size = Vector3.new(S, CONFIG.WallHeight, S),
					Position = Vector3.new(wp.X, CONFIG.WallHeight / 2, wp.Z),
					Color = Color3.fromRGB(90, 94, 105),
					Material = Enum.Material.Slate,
				})
				wall.Parent = folder
				wallByKey[x .. "," .. y] = wall
			end
		end
	end
	-- En planlagt dor sitter alltid pa en vegg mellom to apne celler, altsa en snarvei og aldri
	-- selve ruta: labyrinten er perfekt, sa eneste vei til utgangen gar utenom. Derfor er en
	-- foreldrelos dor grusom, ikke uvinnbar -- og derfor overlevde den sa lenge. Ingenting
	-- feiler; spilleren kaster bare bort runden pa a lete etter en bryter som ikke finnes.

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
	-- Start-markoren. Den fantes bare i buildLevel (rollback-stien), sa minikartet -- som leter
	-- etter navnet "MazeSpawn" -- tegnet aldri startprikken i live-spillet, og perken til 800
	-- mynter viste to av de tre markorene den lover. Samme feilklasse som `MazeGame` mot
	-- `Maze_<id>`: et navne-oppslag som stille gir nil fordi bare den dode byggeren lager navnet.
	-- Vanlig Part, ikke SpawnLocation: i lobby-modus teleporterer placeInInstance spilleren hit,
	-- og en ekte SpawnLocation ville blandet seg inn i hvor Roblox respawner folk.
	makePart({
		Name = "MazeSpawn",
		Size = Vector3.new(S - 3, 1, S - 3),
		Position = Vector3.new(sw.X, 0.6, sw.Z),
		Color = Color3.fromRGB(60, 200, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}).Parent = folder
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

	-- Retur-dør ved STARTEN (motsatt vei av utgangen): gå bort til den + trykk for å
	-- gå tilbake til lobbyen uten å fullføre nivået. Står på start-cellas bakvegg.
	local retDoor = makePart({ Name = "LobbyDoor", Size = Vector3.new(S - 3, 7, 1),
		Position = Vector3.new(sw.X, 4, sw.Z - (S / 2) + 0.6),
		Color = Color3.fromRGB(210, 80, 80), Material = Enum.Material.Neon, CanCollide = false })
	retDoor.Parent = folder
	local rbb = Instance.new("BillboardGui"); rbb.Size = UDim2.fromScale(6, 1.5)
	rbb.StudsOffset = Vector3.new(0, 3.5, 0); rbb.AlwaysOnTop = true; rbb.Parent = retDoor
	local rl = Instance.new("TextLabel"); rl.Size = UDim2.fromScale(1, 1); rl.BackgroundTransparency = 1
	rl.TextColor3 = Color3.new(1, 1, 1); rl.TextStrokeTransparency = 0; rl.TextScaled = true
	rl.Font = Enum.Font.GothamBold; rl.Text = "🚪 Lobby"; rl.Parent = rbb
	local rprompt = Instance.new("ProximityPrompt")
	rprompt.ActionText = "Return to Lobby"; rprompt.ObjectText = ""; rprompt.HoldDuration = 0.3
	rprompt.MaxActivationDistance = 10; rprompt.RequiresLineOfSight = false; rprompt.Parent = retDoor
	rprompt.Triggered:Connect(function(plr)
		if playerInstance[plr] == inst and returnToLobby then returnToLobby(plr) end
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
	-- Feller (pulserende — se CONFIG.Traps + "FELLER (PULS)")
	local trapCtx = newTrapCtx()
	for _, c in ipairs(take(diff.traps)) do
		spawnTrap(trapCtx, folder, MazeGen.cellCenterWorld(c[1], c[2], gCols, gRows, S, origin))
	end
	local trapGen = inst.gen
	runTrapPulse(trapCtx, function() return inst.gen == trapGen and folder.Parent ~= nil end)
	-- Skjulte knapper. Hver knapp far SIN dor her, og veggen blir forst en SecretWall nar paret
	-- finnes -- det er dette som gjor at antallene ikke kan sprike.
	--
	-- Paret deler farge. For delte alle knapper samme cyan, og alle dorer samme morke lilla, sa
	-- koblingen var usynlig: du trykket en knapp, en vegg forsvant et sted du ikke kunne se, og
	-- fant du en hemmelig vegg visste du ikke hvilken av knappene som horte til. Na er doren
	-- tonet mot knappens farge (svakt -- den skal fortsatt oppdages, ikke lyse), mens knappen
	-- har fargen i fullt.
	-- Fargene er valgt for a IKKE ligne noe annet som lyser i en helsvart labyrint. Ambient er
	-- {0,0,0} og tavla er 45 studs, sa fargetonen er nesten alt spilleren har a ga pa. Fallgruver
	-- som ble malt bort igjen: rav lignet bade Coin (250,205,50) og feltas GULE FORVARSEL
	-- (255,205,60) -- en gul glod som betyr "dor" ved siden av en som betyr "dette gulvet dreper
	-- deg om et oyeblikk"; lilla lignet Gem (170,90,240); gronn lignet Exit (60,200,90); rose
	-- lignet LobbyDoor (210,80,80).
	local PAIR_COLORS = {
		{ 60, 200, 220 },  -- cyan (den opprinnelige knappefargen)
		{ 245, 245, 255 }, -- hvit
		{ 70, 110, 255 },  -- dypbla
		{ 255, 90, 200 },  -- knallrosa
	}
	-- Parfargen ligger pa en egen del, "SecretMark", ikke pa veggen. Grunnen: alt som maler om
	-- deler etter NAVN vil ellers vaske koblingen bort. Tema-butikka gjor nettopp det --
	-- ShopClient.PART_FIELD mapper "SecretWall" til temaets ene `secret`-farge -- og "SecretMark"
	-- star ikke i den tabellen, sa den blir staende uansett tema.
	-- Historikk, siden markoren ellers ser overflodig ut: da den ble lagt inn traff tema-
	-- omfargingen ikke live-labyrinten i det hele tatt -- klientene lette etter workspace.MazeGame
	-- mens denne byggeren navngir mappa "Maze_<id>". Det er rettet na (se MazeRef), sa omfargingen
	-- treffer, og da er det nettopp den som ville vasket parfargen bort om den lag pa veggen.
	-- Veggen selv beholder den klassiske hemmelig-fargen, sa temaene virker akkurat som for.
	-- Baandet stikker bare 0.125 studs ut fra en 9x9-vegg, og en dor star alltid mellom to apne
	-- celler, sa to av sidene er begravd i naboveggene: den leses fra de to passasje-sidene.
	for i, c in ipairs(take(math.min(diff.buttons, 4))) do
		local key = table.remove(plannedDoors, 1)
		if not key then break end
		local doorPart = wallByKey[key]
		if not doorPart then break end
		local rgb = PAIR_COLORS[((i - 1) % #PAIR_COLORS) + 1]
		doorPart.Name = "SecretWall"
		doorPart.Color = Color3.fromRGB(70, 66, 78)

		local mark = makePart({
			Name = "SecretMark",
			Size = Vector3.new(S + 0.25, 1.1, S + 0.25),
			Position = doorPart.Position - Vector3.new(0, CONFIG.WallHeight / 2 - 1.2, 0),
			Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		mark.Parent = folder

		local w = MazeGen.cellCenterWorld(c[1], c[2], gCols, gRows, S, origin)
		local btn = makePart({ Name = "SecretButton", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3, 3),
			Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]), Material = Enum.Material.Neon, CanCollide = false,
			CFrame = CFrame.new(w + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
		btn.Parent = folder
		local used = false
		btn.Touched:Connect(function(hit)
			if used then return end
			local plr = Players:GetPlayerFromCharacter(hit.Parent); if not plr then return end
			used = true
			-- Brukt knapp beholder fargen sin, bare dempet, sa spilleren fortsatt kan se hvilket
			-- par den horte til etterpa.
			btn.Color = Color3.fromRGB(
				math.floor(rgb[1] * 0.35), math.floor(rgb[2] * 0.35), math.floor(rgb[3] * 0.35))
			if doorPart and doorPart.Parent then
				doorPart.CanCollide = false
				local drop = Vector3.new(0, CONFIG.WallHeight + 2, 0)
				TweenService:Create(doorPart, TweenInfo.new(0.7, Enum.EasingStyle.Quad),
					{ Position = doorPart.Position - drop }):Play()
				-- Markoren ma synke med veggen sin, ellers henter den igjen i lufta.
				if mark and mark.Parent then
					TweenService:Create(mark, TweenInfo.new(0.7, Enum.EasingStyle.Quad),
						{ Position = mark.Position - drop }):Play()
				end
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

	-- Gå-vakta: korteste rute med ALLE planlagte hemmelige dører åpne (også en som ikke fikk knapp: det kan bare
	-- senke gulvet), i toppfart med den raskeste speed-perken. Se CONFIG.WalkGuard.
	do
		local openGrid = {}
		for y = 0, gRows - 1 do openGrid[y] = table.clone(grid[y]) end
		for _, k in ipairs(plannedDoors) do
			local dx, dy = string.match(k, "^(%d+),(%d+)$")
			if dx and openGrid[tonumber(dy)] then openGrid[tonumber(dy)][tonumber(dx)] = false end
		end
		local openSteps = Medals.solveRoute(openGrid, gCols, gRows, startFine, exitFine, {})
		inst.minClear = openSteps and Progression.minClearSeconds(openSteps, S, MAX_WALK_SPEED, CONFIG.WalkGuard.Slack) or 0
	end

	-- Ruta til "Hjelp meg"-guiden regnes NÅ (mens vi har grid-en) og lagres som
	-- ferdige verdens-punkter. Selve merkene tegnes først hvis noen kjøper guiden.
	-- Medals.dist sendes INN til Assist — delte moduler krever aldri hverandre.
	inst.routeWorld = nil
	if CONFIG.Assist.Enabled then
		local ok, route = pcall(function()
			return Assist.route(Medals.dist, grid, gCols, gRows, startFine, exitFine)
		end)
		-- Tynn ut FØR vi lager punkter, så en lang rute blir jevnt fordelte merker
		-- hele veien til utgangen i stedet for å stoppe halvveis.
		local thinned = ok and Assist.thin(route, CONFIG.Assist.MaxTrailParts) or nil
		if thinned then
			local pts = {}
			for _, fine in ipairs(thinned) do
				pts[#pts + 1] = MazeGen.gridToWorld(fine[1], fine[2], gCols, gRows, S, origin)
			end
			inst.routeWorld = pts
		end
	end

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
		-- LightingClient bruker denne til tåka inne i instansen. Lyset settes per klient
		-- fordi Lighting er global på serveren og to spillere kan stå i hver sin instans.
		fog = INSTANCE_FOG,
		darkness = CONFIG.Darkness,
	})
end

local groupInstances = {}          -- åpne GROUP-instanser (matchet på nivå)
local friendsInstances = {}        -- FRIENDS-instanser (bli med hos en venn)

-- Klient-lobby-remotes: server ber klienten åpne nivå-velgeren; klienten sender
-- valgt {level, mode} tilbake.
local lobbyFolder = Instance.new("Folder"); lobbyFolder.Name = "LobbyRemotes"; lobbyFolder.Parent = ReplicatedStorage
local openPickerEvent = Instance.new("RemoteEvent"); openPickerEvent.Name = "OpenPicker"; openPickerEvent.Parent = lobbyFolder
local startRunEvent = Instance.new("RemoteEvent"); startRunEvent.Name = "StartRun"; startRunEvent.Parent = lobbyFolder

local function countParticipants(inst)
	local n = 0
	for _ in pairs(inst.participants) do n += 1 end
	return n
end

-- Øyeblikksbilde av deltakerne (trygt å iterere selv om settet endres under).
local function participantList(inst)
	local out = {}
	for p in pairs(inst.participants) do out[#out + 1] = p end
	return out
end

-- Fjern en instans fra matchmaking-listene (så de ikke vokser i det uendelige).
local function removeInstanceFromLists(inst)
	for i = #groupInstances, 1, -1 do if groupInstances[i] == inst then table.remove(groupInstances, i) end end
	for i = #friendsInstances, 1, -1 do if friendsInstances[i] == inst then table.remove(friendsInstances, i) end end
end

--===================  "HJELP MEG"-GUIDEN  ========================--
-- Se CONFIG.Assist for HVORFOR. Kort: har du feilet samme nivå nok ganger, kan
-- du kjøpe en lysende rute til utgangen for mynter. Den beholdes til nivået er klart
-- (eierbeslutning 30.09: død eller retur mister den ikke), og tennes bare på det nivået.
--
-- SERVER-AUTORITATIVT, og umulig å utnytte til gratis fremgang:
--   * Klienten sender BARE et ønske (ingen argumenter: ingen pris, intet nivå).
--     Pris og nivå leses av serveren fra CONFIG og spillerens egen instans.
--   * `stuckState` telles KUN i teardownPlayerInstance (ekte død / ekte retur til
--     lobbyen) og bor bare på serveren. Klienten kan ikke sette seg selv "fast".
--   * Guiden gis bare på NØYAKTIG det nivået forsøkene gjelder (Assist.shouldOffer),
--     så den kan ikke spares opp på et lett nivå og brukes på et vanskelig.
--   * Ingen hopp: du må fortsatt gå ut selv. accepted krever fremdeles nøyaktig
--     accepted+1 og ingen gud (Progression) — guiden rører ikke det tallet.
--   * En guide-kjøring gir INGEN tid/rekord (Progression.recordEligible), så
--     rekordtavla kan ikke kjøpes for mynter.
--   * Én guide pr kjøring (inst.assist), og flagget settes i samme steg som
--     myntene trekkes (ingen yield imellom), så spam-klikk kan ikke belaste to
--     ganger eller tegne ruta på nytt.
--   * En beholdt guide (d.guideLevel, lagret) tennes BARE på nivået den ble kjøpt
--     for (Assist.keptFor), og er brukt opp når nivået klares (Assist.afterClear).
--     Den koster ingenting igjen og kan ikke kjøpes to ganger (inst.assist).
local assistFolder = Instance.new("Folder")
assistFolder.Name = "AssistRemotes"
assistFolder.Parent = ReplicatedStorage

local assistStateEvent = Instance.new("RemoteEvent")
assistStateEvent.Name = "AssistState"
assistStateEvent.Parent = assistFolder

local buyAssistFn = Instance.new("RemoteFunction")
buyAssistFn.Name = "BuyAssist"
buyAssistFn.Parent = assistFolder

-- Fortell klienten hva den skal vise: ingenting, "du står fast — kjøp guide",
-- eller "guide aktiv". Sendes ved hvert spawn, hvert nivåbytte og hvert kjøp.
local function sendAssistState(plr)
	local d = playerData[plr]
	if not d then return end
	local inst = playerInstance[plr]
	local stuck = stuckState[plr]
	local level = (inst and inst.level) or (stuck and stuck.level) or 0
	assistStateEvent:FireClient(plr, {
		enabled = CONFIG.Assist.Enabled,
		inMaze = inst ~= nil,
		level = level,
		fails = (stuck and stuck.level == level) and stuck.fails or 0,
		need = CONFIG.Assist.OfferAfterFails,
		offered = Assist.shouldOffer(stuck, level, CONFIG.Assist),
		active = (inst ~= nil) and (inst.assist == true),
		kept = Assist.keptFor(d.guideLevel, level),   -- en kjøpt guide venter på dette nivået (eierbeslutning 30.09)
		price = Assist.price(level, CONFIG.Assist),
		coins = d.coins,
	})
end

-- Tegn guiden: lysende prikker langs ruta som allerede ble regnet i buildInstance.
-- I mørket ser du bare de nærmeste — den viser veien uten å avsløre hele banen.
local function buildAssistTrail(inst)
	if not inst.routeWorld or inst.trail then return 0 end
	local folder = Instance.new("Folder")
	folder.Name = "Guide"
	folder.Parent = inst.folder
	inst.trail = folder
	local n = 0
	for _, pos in ipairs(inst.routeWorld) do
		local dot = makePart({
			Name = "GuideDot", Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.1, 1.1, 1.1),
			Position = pos + Vector3.new(0, 1.3, 0),
			Color = Color3.fromRGB(90, 235, 255), Material = Enum.Material.Neon,
			Transparency = 0.15, CanCollide = false, CanTouch = false,
			CanQuery = false, CastShadow = false,
		})
		dot.Parent = folder
		n += 1
	end
	return n
end

buyAssistFn.OnServerInvoke = function(plr)
	local d = playerData[plr]
	if not d then return { ok = false, reason = "noplayer", price = 0, coins = 0 } end
	local inst = playerInstance[plr]
	if not inst then                       -- guiden kjøpes INNE i labyrinten
		sendAssistState(plr)
		return { ok = false, reason = "notinmaze", price = 0, coins = d.coins }
	end
	if not inst.routeWorld then            -- ingen rute å tegne => ingen betaling
		sendAssistState(plr)
		return { ok = false, reason = "noroute", price = 0, coins = d.coins }
	end
	local ok, reason, price = Assist.buy(d, stuckState[plr], inst.level, inst.assist == true, CONFIG.Assist)
	if ok then
		inst.assist = true                 -- samme steg som trekket: ingen dobbeltkjøp
		d.guideLevel = inst.level          -- beholdes til nivået er klart (eierbeslutning 30.09, Assist.keptFor)
		buildAssistTrail(inst)
		refreshStats(plr)
		scheduleSave(plr)
		sendPerkData(plr)                  -- alle mynt-tellere skal vise samme tall
		sendShopData(plr)
		-- Hele instansen mister rekord-retten, så alle skal se at guiden er på.
		for _, p in ipairs(participantList(inst)) do sendAssistState(p) end
	else
		sendAssistState(plr)
	end
	return { ok = ok, reason = reason, price = price, coins = d.coins }
end

-- (Eierbeslutning 30.09, "aldri straffende") En guide spilleren har kjøpt for dette nivået, og ennå ikke brukt
-- opp ved å klare det, tennes igjen når de går inn på nivået -- etter død, retur til lobbyen eller et nytt besøk.
-- Serveren avgjør det ut fra det lagrede nivået de betalte for; aldri på et annet nivå. Som et kjøp i en delt
-- kjøring gjelder guiden hele instansen (og da gir ingen i den tid/rekord, Progression.recordEligible).
local function applyKeptGuide(plr, inst)
	local d = playerData[plr]
	if not d or not CONFIG.Assist.Enabled or inst.assist or not inst.routeWorld then return false end
	if not Assist.keptFor(d.guideLevel, inst.level) then return false end
	inst.assist = true
	buildAssistTrail(inst)
	for _, p in ipairs(participantList(inst)) do
		if p ~= plr then sendAssistState(p) end
	end
	return true
end

-- Fjern spilleren fra sin instans (forlot/døde). Tom instans -> riv + prune.
-- Forhånds-deklarert i STATE så PlayerRemoving (definert over) kan kalle den.
-- `voluntary` = spilleren gikk selv ut via retur-døra (ikke død). Da kreves det
-- at de faktisk var inne en stund før det teller som et forsøk.
teardownPlayerInstance = function(plr, voluntary)
	local inst = playerInstance[plr]
	if not inst then return end
	-- Ett mislykket forsøk til på dette nivået (døde eller ga opp). Dette er det
	-- ENESTE stedet tellingen øker, og den skjer på serveren — grunnlaget for at
	-- "Hjelp meg"-guiden tilbys.
	local runSeconds = startClock[plr] and (os.clock() - startClock[plr]) or 0
	if Assist.countsAsFail(runSeconds, voluntary, CONFIG.Assist) then
		stuckState[plr] = Assist.noteFail(stuckState[plr], inst.level)
	end
	playerInstance[plr] = nil
	plr:SetAttribute(MazeRef.ATTRIBUTE, nil)
	if inst.participants then inst.participants[plr] = nil end
	if not inst.participants or not next(inst.participants) then
		inst.gen = (inst.gen or 0) + 1
		if inst.folder then inst.folder:Destroy() end
		removeInstanceFromLists(inst)
	end
end

-- Frivillig retur til lobbyen (retur-døra inne i labyrinten). Ut av instansen +
-- teleporter til lobbyen + vis lobby-HUD.
returnToLobby = function(plr)
	teardownPlayerInstance(plr, true)   -- frivillig: kort inn-og-ut teller ikke
	local char = plr.Character
	if char then pcall(function() char:PivotTo(CFrame.new(LOBBY_ORIGIN + Vector3.new(0, 5, 0))) end) end
	sendInstanceInfo(plr, nil)
	sendAssistState(plr)   -- i lobbyen: vis "du står fast"-hintet hvis det gjelder
end

local endInstance, advanceInstance

-- Plasser en spiller inn i en (allerede bygd) instans.
local function placeInInstance(plr, inst)
	inst.participants[plr] = true
	if godActive[plr] then inst.hadGod = true end   -- gikk inn med gud på = nivået teller ikke
	playerInstance[plr] = inst
	local char = plr.Character
	if char then pcall(function() char:PivotTo(CFrame.new(inst.spawnPos)) end) end
	startClock[plr] = os.clock()
	runStartAt[plr] = clock()
	shieldUsed[plr] = false
	-- Merk spilleren med SIN egen labyrint-mappe. Klientene (tema-omfarging, minikart) sto og
	-- lette etter `workspace.MazeGame`, som bare den ubrukte buildLevel lager -- derfor var
	-- temaene og minikart-perken doede i live-spillet. Attributtet replikeres, sa hvert
	-- klientskript kan sla opp sin egen instans uten en ny remote, og uten a gjette pa den
	-- forste `Maze_<id>`-mappa i workspace (som ofte tilhorer en annen spiller).
	if inst.folder then
		plr:SetAttribute(MazeRef.ATTRIBUTE, inst.folder.Name)
	end
	applyKeptGuide(plr, inst)
	sendInstanceInfo(plr, inst)
	sendAssistState(plr)   -- inne i labyrinten: her dukker kjøp-knappen opp (eller den beholdte guiden)
end

-- Lag en ny instans (bygd) med `plr` som første deltaker.
local function createInstance(plr, level, mode)
	nextInstanceId += 1
	local inst = {
		id = nextInstanceId, level = level, mode = mode,
		origin = Vector3.new(nextInstanceId * INSTANCE_SPACING, 0, 0),
		participants = {}, hostUserId = plr.UserId, solving = false,
	}
	local ok, err = pcall(function() buildInstance(inst) end)
	if not ok then warn("[Labyrint] buildInstance feilet: " .. tostring(err)); return nil end
	placeInInstance(plr, inst)
	return inst
end

-- Solo: din egen instans på valgt nivå (<= accepted+1).
local function startSolo(plr, level)
	local d = playerData[plr]; if not d or playerInstance[plr] then return end
	createInstance(plr, math.clamp(math.floor(level or (d.accepted + 1)), 1, d.accepted + 1), "solo")
end

-- Group: matches med andre i serveren på SAMME nivå (accepted+1). Ingen carry.
local function startGroup(plr)
	local d = playerData[plr]; if not d or playerInstance[plr] then return end
	local want = d.accepted + 1
	for _, inst in ipairs(groupInstances) do
		if inst.folder and inst.folder.Parent and inst.mode == "group"
			and inst.level == want and countParticipants(inst) < 4 then
			placeInInstance(plr, inst); return
		end
	end
	local inst = createInstance(plr, want, "group")
	if inst then table.insert(groupInstances, inst) end
end

-- Hvilken Friends-instans kan `plr` gå inn i nå? Først VERTENS EGEN (andre review 30.09: Roblox regner deg
-- aldri som din egen venn, så en vert som gikk ut i løpet av "gratis pause"-sekundene kom seg ikke tilbake --
-- Friends-døra åpnet velgeren for å være vert for en NY kjøring, og vennene sto igjen alene i den gamle).
-- Deretter en venns. Aldri en fremmeds, og aldri en full (4) instans.
local function findFriendsInstance(plr)
	local function open(inst)
		return inst.folder and inst.folder.Parent and inst.mode == "friends" and countParticipants(inst) < 4
	end
	for _, inst in ipairs(friendsInstances) do
		if open(inst) and inst.hostUserId == plr.UserId then return inst end
	end
	for _, inst in ipairs(friendsInstances) do
		if open(inst) then
			local ok, isFriend = pcall(function() return plr:IsFriendsWith(inst.hostUserId) end)
			if ok and isFriend then return inst end
		end
	end
	return nil
end

-- Friends: tilbake i din EGEN kjøring, eller bli med hos en VENN som allerede er vert her; ellers vert selv
-- (velger nivå).
local function startFriendsJoinOrHost(plr, hostLevel)
	local d = playerData[plr]; if not d or playerInstance[plr] then return end
	local join = findFriendsInstance(plr)
	if join then placeInInstance(plr, join); return end
	-- Ingen venn er vert: bli vert selv på valgt nivå (<= accepted+1).
	local lvl = math.clamp(math.floor(hostLevel or (d.accepted + 1)), 1, d.accepted + 1)
	local inst = createInstance(plr, lvl, "friends")
	if inst then table.insert(friendsInstances, inst) end
end

-- Riv en instans og send ALLE deltakere til lobbyen.
endInstance = function(inst)
	for _, p in ipairs(participantList(inst)) do
		playerInstance[p] = nil
		-- Fjern merkelappen her ogsaa. teardownPlayerInstance gjor det, denne gjorde det ikke, og
		-- asymmetrien var bare ufarlig fordi nextInstanceId aldri gjenbruker et navn: en spiller
		-- sto igjen merket med en revet mappe. MazeRef faller riktignok tilbake, men en peker som
		-- lyver er ikke noe aa spare paa.
		p:SetAttribute(MazeRef.ATTRIBUTE, nil)
		local char = p.Character
		if char then pcall(function() char:PivotTo(CFrame.new(LOBBY_ORIGIN + Vector3.new(0, 5, 0))) end) end
		sendInstanceInfo(p, nil)
		sendAssistState(p)
	end
	inst.participants = {}
	inst.gen = (inst.gen or 0) + 1
	if inst.folder then inst.folder:Destroy() end
	removeInstanceFromLists(inst)
end

-- Avanser en (group/friends) instans til neste nivå: bygg om, respawn alle.
advanceInstance = function(inst)
	inst.level += 1
	local ok, err = pcall(function() buildInstance(inst) end)
	if not ok then warn("[Labyrint] advance-bygg feilet: " .. tostring(err)); endInstance(inst); return end
	for _, p in ipairs(participantList(inst)) do applyKeptGuide(p, inst) end
	for _, p in ipairs(participantList(inst)) do
		if godActive[p] then inst.hadGod = true end   -- flyr fortsatt inn i nytt nivå = teller ikke
		local char = p.Character
		if char then pcall(function() char:PivotTo(CFrame.new(inst.spawnPos)) end) end
		startClock[p] = os.clock()
		runStartAt[p] = clock()
		shieldUsed[p] = false
		sendInstanceInfo(p, inst)
		sendAssistState(p)   -- nytt nivå = ny (u)tilbudt guide
	end
end

-- Løsning: solverens tid/rekord/kort + accepted til ALLE deltakere (Progression,
-- per-instans hadGod). Så: solo -> lobby ; group/friends -> avanser. Idempotent.
finishRun = function(solverPlr, inst)
	if inst.solving then return end                -- én løsning pr nivå (mange Touched)
	if not inst.participants[solverPlr] then return end
	-- Effektiv gud-status: inst.hadGod (gud aktivert i løpet av nivået) ELLER en
	-- deltaker flyr NÅ (aktiverte gud i lobbyen før de gikk inn, eller skrudde av
	-- rett før mål). Fanger ALLE gud-veier — ellers kunne Mio "rent" løse nivået.
	local hadGod = inst.hadGod
	for p in pairs(inst.participants) do if godActive[p] then hadGod = true end end
	-- Gå-vakta: raskere enn noen kan gå hit = teller ikke (et teleport-skript), og spilleren får vite hvorfor.
	-- Ingenting endres: løsningen er fortsatt åpen for en ekte ankomst senere.
	if CONFIG.WalkGuard.Enabled and not hadGod and (inst.minClear or 0) > 0 then
		local now = clock()
		local walked = now - (runStartAt[solverPlr] or now)
		if walked < inst.minClear then
			if notifyPlayer and now - (guardNoticeAt[solverPlr] or -math.huge) >= CONFIG.WalkGuard.NoticeEverySeconds then
				guardNoticeAt[solverPlr] = now
				notifyPlayer(solverPlr, string.format(
					"Too fast: nobody can run this maze in %.1f s. That exit only counts when you walk there.", walked))
			end
			return
		end
	end
	inst.solving = true
	local level = inst.level
	-- Ble "Hjelp meg"-guiden kjøpt på dette nivået, teller kjøringen for
	-- fremgang (du gikk faktisk ut) men gir INGEN tid/rekord — rekordtavla skal
	-- ikke kunne kjøpes for mynter. Én regel, samme sted som gud: Progression.
	local usedAssist = inst.assist and true or false
	local sd = playerData[solverPlr]
	local elapsed
	if sd then
		local st = startClock[solverPlr]
		elapsed = st and (os.clock() - st) or nil
		local clean = Progression.recordEligible(hadGod, usedAssist)
		local medal, isNewPB, isNewRecord, recs
		if elapsed then
			if clean and elapsed < sd.best then sd.best = elapsed end
			local lkey = tostring(level)
			sd.bestByLevel = sd.bestByLevel or {}
			local prevPB = sd.bestByLevel[lkey]
			isNewPB = clean and ((prevPB == nil) or (elapsed < prevPB))
			if isNewPB then sd.bestByLevel[lkey] = elapsed end
			medal = Medals.medalFor(elapsed, inst.thresholds)
			recs = getRecord(level)
			local bestTime = recs[1] and recs[1].time or nil
			isNewRecord = clean and ((bestTime == nil) or (elapsed < bestTime))
			local worst = recs[3] and recs[3].time or nil
			local qualifies = (#recs < 3) or (worst and elapsed < worst)
			if clean and qualifies then
				local nl = {}
				for _, e in ipairs(recs) do nl[#nl + 1] = { time = e.time, name = e.name } end
				nl[#nl + 1] = { time = elapsed, name = solverPlr.Name }
				table.sort(nl, function(a, b) return a.time < b.time end)
				while #nl > 3 do table.remove(nl) end
				recordCache[level] = nl; recs = nl
				task.spawn(function() tryUpdateRecord(level, elapsed, solverPlr.Name) end)
			end
		end
		sd.trophies += 1  -- pokal til den som kom seg ut
		if levelCompleteEvent and elapsed then
			levelCompleteEvent:FireClient(solverPlr, {
				level = level, time = elapsed, yourBest = sd.bestByLevel[tostring(level)],
				record = recs and recs[1] or nil, records = recs, medal = medal,
				isNewPB = isNewPB, isNewRecord = isNewRecord, thresholds = inst.thresholds,
			})
		end
	end
	-- Accepted til ALLE deltakere (hver tjener bare sitt eget accepted+1, gud-fritt).
	for _, p in ipairs(participantList(inst)) do
		local pd = playerData[p]
		if pd then
			local res = Progression.resolveClear({
				level = level, accepted = pd.accepted, bestWithGod = pd.bestWithGod,
				hadGod = hadGod, usedAssist = usedAssist, mode = inst.mode,
			})
			pd.accepted = res.newAccepted; pd.bestWithGod = res.newBestWithGod
			if res.acceptedGained then pd.acceptedAt = os.time() end -- topplista: uavgjort til den som var først
			stuckState[p] = Assist.noteClear(stuckState[p], level)  -- klarte det: null forsøk
			pd.guideLevel = Assist.afterClear(pd.guideLevel, level)  -- en beholdt guide for nivået er brukt opp
			refreshStats(p)
			if res.acceptedGained then task.spawn(writeBoard, p) end -- writeBoard sjekker lås og GodUsers
			task.spawn(function() savePlayer(p) end)
		end
	end
	-- Neste
	-- Alle modus: fortsett til neste nivå (bli i labyrinten). Retur til lobby skjer
	-- via retur-døra inne i labyrinten (eller død).
	advanceInstance(inst)
	inst.solving = false
end

-- Klienten sender valgt nivå fra velgeren.
startRunEvent.OnServerEvent:Connect(function(plr, level, mode)
	if playerInstance[plr] then return end
	if typeof(level) ~= "number" then return end
	if mode == "friends" then startFriendsJoinOrHost(plr, level)
	else startSolo(plr, level) end
end)

-- Bygg en dør i lobbyen (part + skilt + ProximityPrompt).
local function makeDoor(hub, name, label, actionText, pos, color, onTrigger)
	local door = makePart({ Name = name, Size = Vector3.new(8, 10, 2), Position = pos, Color = color, Material = Enum.Material.Neon })
	door.Parent = hub
	local sign = Instance.new("BillboardGui"); sign.Size = UDim2.fromScale(9, 2)
	sign.StudsOffset = Vector3.new(0, 6, 0); sign.AlwaysOnTop = true; sign.Parent = door
	local sl = Instance.new("TextLabel"); sl.Size = UDim2.fromScale(1, 1); sl.BackgroundTransparency = 1
	sl.TextColor3 = Color3.new(1, 1, 1); sl.TextStrokeTransparency = 0; sl.TextScaled = true
	sl.Font = Enum.Font.GothamBold; sl.Text = label; sl.Parent = sign
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText; prompt.ObjectText = ""; prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 12; prompt.RequiresLineOfSight = false; prompt.Parent = door
	prompt.Triggered:Connect(function(plr) pcall(onTrigger, plr) end)
end

-- Bygg lobby-huben: gulv, spawn, tre dører.
local function buildLobby()
	local hub = Instance.new("Folder"); hub.Name = "Lobby"; hub.Parent = workspace
	makePart({ Name = "LobbyFloor", Size = Vector3.new(70, 2, 70),
		Position = LOBBY_ORIGIN + Vector3.new(0, -1, 0), Color = Color3.fromRGB(45, 48, 62),
		Material = Enum.Material.SmoothPlastic }).Parent = hub
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"; spawn.Anchored = true; spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = LOBBY_ORIGIN + Vector3.new(0, 0.5, 0); spawn.Color = Color3.fromRGB(60, 200, 90)
	spawn.Material = Enum.Material.Neon; spawn.Duration = 0; spawn.Parent = hub

	makeDoor(hub, "SoloDoor", "🧗 Solo Climb", "Solo",
		LOBBY_ORIGIN + Vector3.new(-16, 5, -22), Color3.fromRGB(70, 120, 200), function(plr)
			if playerInstance[plr] then return end
			openPickerEvent:FireClient(plr, { accepted = (playerData[plr] and playerData[plr].accepted) or 0, mode = "solo" })
		end)
	makeDoor(hub, "GroupDoor", "👥 Group", "Group",
		LOBBY_ORIGIN + Vector3.new(0, 5, -22), Color3.fromRGB(90, 180, 110), function(plr)
			startGroup(plr)
		end)
	makeDoor(hub, "FriendsDoor", "🤝 Play with Friends", "Friends",
		LOBBY_ORIGIN + Vector3.new(16, 5, -22), Color3.fromRGB(200, 140, 70), function(plr)
			if playerInstance[plr] then return end
			-- Din egen kjøring, eller en venn som er vert? bli med direkte. Ellers åpne velger (du blir vert).
			local join = findFriendsInstance(plr)
			if join then placeInInstance(plr, join); return end
			openPickerEvent:FireClient(plr, { accepted = (playerData[plr] and playerData[plr].accepted) or 0, mode = "friends" })
		end)

	-- Topplista-tavla ved spawn (docs/complete-game-standard.md §3): forsiden (lokal -Z) vender mot spawn-platen.
	-- Serveren bygger bare tavla og prompten; KLIENTEN tegner innholdet (BoardClient), så hver spiller ser sin egen
	-- visning (Public/Friends). En gull-kant bak: noe interaktivt skal se interaktivt ut.
	do
		local bp, bs = BC.Position, BC.Size
		local centre = LOBBY_ORIGIN + Vector3.new(bp[1], bp[2], bp[3])
		local facing = Vector3.new(LOBBY_ORIGIN.X, centre.Y, LOBBY_ORIGIN.Z)
		local board = makePart({ Name = "TopBoard", Size = Vector3.new(bs[1], bs[2], bs[3]),
			CFrame = CFrame.lookAt(centre, facing), Color = Color3.fromRGB(24, 26, 40),
			Material = Enum.Material.SmoothPlastic })
		board.Parent = hub
		local trim = makePart({ Name = "TopBoardTrim", Size = Vector3.new(bs[1] + 0.8, bs[2] + 0.8, 0.6),
			CFrame = board.CFrame * CFrame.new(0, 0, 0.35), Color = Color3.fromRGB(255, 205, 90),
			Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
		trim.Parent = board
		local at = Instance.new("Attachment")
		at.Name = "PromptAt"
		at.Position = Vector3.new(0, -bs[2] / 2 + 1.5, -bs[3] / 2 - 0.6)
		at.Parent = board
		local bprompt = Instance.new("ProximityPrompt")
		bprompt.Name = "BoardPrompt"
		bprompt.ActionText = BC.Text.Prompt
		bprompt.ObjectText = BC.Text.Object
		bprompt.HoldDuration = 0
		bprompt.MaxActivationDistance = BC.PromptDistance
		bprompt.RequiresLineOfSight = false
		bprompt.KeyboardKeyCode = Enum.KeyCode.E
		bprompt.Parent = at
		bprompt.Triggered:Connect(function(plr) toggleBoard(plr) end)
	end

	-- "Content Contributors"-tavle: takker hjelpere hvis content-bidrag er brukt
	-- (navn fra Contributors.list()). BillboardGui = alltid vendt mot kamera, så
	-- ingen face-orientering å bomme på. Tom liste -> oppfordring om å hjelpe.
	local pole = makePart({ Name = "ContributorsPole", Size = Vector3.new(1.2, 12, 1.2),
		Position = LOBBY_ORIGIN + Vector3.new(-20, 6, 16), Color = Color3.fromRGB(50, 54, 72),
		Material = Enum.Material.Metal })
	pole.Parent = hub
	local bb = Instance.new("BillboardGui")
	bb.Name = "ContributorsBoard"; bb.Size = UDim2.fromScale(11, 7)
	bb.StudsOffset = Vector3.new(0, 8, 0); bb.MaxDistance = 140; bb.Parent = pole
	local frame = Instance.new("Frame"); frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(24, 26, 38); frame.BackgroundTransparency = 0.1
	frame.Parent = bb
	local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(0, 14); uic.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 10); pad.Parent = frame
	local lay = Instance.new("UIListLayout"); lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 6); lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.Parent = frame
	local ctitle = Instance.new("TextLabel"); ctitle.Size = UDim2.new(1, 0, 0, 26)
	ctitle.BackgroundTransparency = 1; ctitle.Font = Enum.Font.GothamBold; ctitle.TextScaled = true
	ctitle.TextColor3 = Color3.fromRGB(255, 220, 120); ctitle.Text = "Content Contributors"
	ctitle.LayoutOrder = 1; ctitle.Parent = frame
	local tsc = Instance.new("UITextSizeConstraint"); tsc.MaxTextSize = 26; tsc.Parent = ctitle
	local cbody = Instance.new("TextLabel"); cbody.Size = UDim2.new(1, 0, 1, -32)
	cbody.BackgroundTransparency = 1; cbody.Font = Enum.Font.Gotham; cbody.TextColor3 = Color3.new(1, 1, 1)
	cbody.TextWrapped = true; cbody.TextScaled = true; cbody.TextYAlignment = Enum.TextYAlignment.Top
	cbody.LayoutOrder = 2; cbody.Parent = frame
	local bsc = Instance.new("UITextSizeConstraint"); bsc.MaxTextSize = 20; bsc.Parent = cbody
	local clist = Contributors.list()
	if #clist > 0 then
		cbody.Text = "Thank you!\n\n\u{2605} " .. table.concat(clist, "\n\u{2605} ")
	else
		cbody.Text = "Help make content (screenshots / clips)\non our Reddit and get "
			.. Contributors.REWARD.coins .. " coins,\n" .. Contributors.REWARD.gems
			.. " gems + your name up here!"
	end

	-- "DAILY REWARD"-tavle: markedsfører den daglige innloggings-belønningen så
	-- spillere ser at det lønner seg å komme tilbake (retention -> engaged players).
	local dpole = makePart({ Name = "DailyRewardPole", Size = Vector3.new(1.2, 12, 1.2),
		Position = LOBBY_ORIGIN + Vector3.new(20, 6, 16), Color = Color3.fromRGB(72, 60, 30),
		Material = Enum.Material.Metal })
	dpole.Parent = hub
	local dbb = Instance.new("BillboardGui")
	dbb.Name = "DailyRewardBoard"; dbb.Size = UDim2.fromScale(11, 7)
	dbb.StudsOffset = Vector3.new(0, 8, 0); dbb.MaxDistance = 140; dbb.Parent = dpole
	local dframe = Instance.new("Frame"); dframe.Size = UDim2.fromScale(1, 1)
	dframe.BackgroundColor3 = Color3.fromRGB(38, 32, 16); dframe.BackgroundTransparency = 0.1
	dframe.Parent = dbb
	local duic = Instance.new("UICorner"); duic.CornerRadius = UDim.new(0, 14); duic.Parent = dframe
	local dpad = Instance.new("UIPadding")
	dpad.PaddingTop = UDim.new(0, 10); dpad.PaddingBottom = UDim.new(0, 10)
	dpad.PaddingLeft = UDim.new(0, 10); dpad.PaddingRight = UDim.new(0, 10); dpad.Parent = dframe
	local dlay = Instance.new("UIListLayout"); dlay.SortOrder = Enum.SortOrder.LayoutOrder
	dlay.Padding = UDim.new(0, 6); dlay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dlay.Parent = dframe
	local dtitle = Instance.new("TextLabel"); dtitle.Size = UDim2.new(1, 0, 0, 28)
	dtitle.BackgroundTransparency = 1; dtitle.Font = Enum.Font.GothamBold; dtitle.TextScaled = true
	dtitle.TextColor3 = Color3.fromRGB(255, 224, 130); dtitle.Text = "🎁 DAILY REWARD"
	dtitle.LayoutOrder = 1; dtitle.Parent = dframe
	local dtsc = Instance.new("UITextSizeConstraint"); dtsc.MaxTextSize = 28; dtsc.Parent = dtitle
	local dbody = Instance.new("TextLabel"); dbody.Size = UDim2.new(1, 0, 1, -34)
	dbody.BackgroundTransparency = 1; dbody.Font = Enum.Font.Gotham; dbody.TextColor3 = Color3.new(1, 1, 1)
	dbody.TextWrapped = true; dbody.TextScaled = true; dbody.TextYAlignment = Enum.TextYAlignment.Top
	dbody.LayoutOrder = 2; dbody.Parent = dframe
	local dbsc = Instance.new("UITextSizeConstraint"); dbsc.MaxTextSize = 20; dbsc.Parent = dbody
	dbody.Text = "Log in EVERY DAY!\n\n🔥 Streak = more coins\n(up to +1050 / day)\n💎 Day 7 = BONUS gems!"

	-- 3x-statue av Mios ekte avatar, bak spawn og vendt mot dørene. Alt pcall-et:
	-- feiler avatar-henting (nett/ukjent navn), står lobbyen bare uten statue.
	local ped = makePart({ Name = "Pedestal", Size = Vector3.new(14, 4, 14),
		Position = LOBBY_ORIGIN + Vector3.new(0, 2, 22), Color = Color3.fromRGB(60, 64, 84),
		Material = Enum.Material.Marble })
	ped.Parent = hub
	task.spawn(function()
		local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync("MioSpille") end)
		if not ok or type(uid) ~= "number" then return end
		local ok2, model = pcall(function() return Players:CreateHumanoidModelFromUserId(uid) end)
		if not ok2 or not model then return end
		model.Name = "MioStatue"
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.EvaluateStateMachine = false
			pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
		end
		-- Forankre alt (statisk), så 3x-skaler, så plasser på sokkelen vendt mot spawn.
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false end
		end
		pcall(function() model:ScaleTo(3) end)
		pcall(function()
			model:PivotTo(CFrame.new(LOBBY_ORIGIN + Vector3.new(0, 12, 22)) * CFrame.Angles(0, math.pi, 0))
		end)
		model.Parent = hub
		-- Navneplate over hodet.
		local anchor = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or ped
		local plate = Instance.new("BillboardGui"); plate.Size = UDim2.fromScale(8, 2)
		plate.StudsOffset = Vector3.new(0, 4, 0); plate.AlwaysOnTop = true; plate.Parent = anchor
		local pl = Instance.new("TextLabel"); pl.Size = UDim2.fromScale(1, 1); pl.BackgroundTransparency = 1
		pl.TextColor3 = Color3.fromRGB(255, 220, 120); pl.TextStrokeTransparency = 0; pl.TextScaled = true
		pl.Font = Enum.Font.GothamBold; pl.Text = "⭐ Mio ⭐"; pl.Parent = plate
	end)
end

-- Kalles fra onCharacterAdded ved hvert spawn i lobby-modus. Døde spilleren i en
-- instans, spawner Roblox dem på LobbySpawn — da river vi den forlatte instansen
-- og viser lobby-HUD. Første spawn (ingen instans): bare vis lobby-HUD.
handleLobbySpawn = function(plr)
	teardownPlayerInstance(plr)   -- døde i en instans -> ut av den (riv hvis tom)
	sendInstanceInfo(plr, nil)
	sendAssistState(plr)          -- døde du for mange ganger, sier lobbyen fra her
end

--============================  START  ============================--
if CONFIG.UseLobby then
	-- Alle spawner i lobbyen, så lobbyen er riktig STARTtilstand. Før satte vi mørke-
	-- presetet her og lot det stå: huben fikk labyrintens svarte tåke fra 0 til 45 studs, og
	-- det første en ny spiller så var et grått gulv i fakkellys. En spiller beskrev spillet
	-- som "a black part that is scaled in the shape of a square" — det var dette.
	-- Mørket settes nå per klient (LightingClient) når spilleren går inn i en instans.
	local lobbyLight = if CONFIG.Darkness then LightingPresets.LOBBY else LightingPresets.LIT
	Lighting.ClockTime = lobbyLight.ClockTime
	Lighting.Brightness = lobbyLight.Brightness
	Lighting.Ambient = rgb(lobbyLight.Ambient)
	Lighting.OutdoorAmbient = rgb(lobbyLight.OutdoorAmbient)
	Lighting.FogColor = rgb(lobbyLight.FogColor)
	Lighting.FogStart = lobbyLight.FogStart
	Lighting.FogEnd = lobbyLight.FogEnd
	buildLobby()
	for _, p in ipairs(Players:GetPlayers()) do pointRespawn(p) end -- de som var her før lobbyen fantes
	print("[Labyrint] Lobby-modus lastet.")
else
	applyDarkness()
	buildLevel()
	print("[Labyrint] Lastet. Level " .. currentLevel .. " bygget. Lykke til!")
end

-- Topplista: den gamle tavlas topp 10 bæres over, så hentes den offentlige topp 10 høyst én gang per
-- PublicCacheSeconds og sendes til HUD-panelet og til tavla hos alle som ser på PUBLIC.
task.spawn(function()
	carryLegacyBoard()
	while true do
		refreshPublic()
		pushPublic()
		task.wait(BC.PublicCacheSeconds)
	end
end)
