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
	WallHeight = 16,
	UnlockExitBy = "coins",   -- "coins" | "gems" | "none": hva som må samles for å åpne utgangen
	MultipleLevels = true,
	MaxLevel = 500,           -- der kurven er på sitt vanskeligste (spillet fortsetter uansett)

	-- Verden-frø: samme frø + samme level gir NØYAKTIG samme bane for ALLE
	-- spillere, hver gang (level 4 er alltid den samme level 4). Endre tallet
	-- for å trekke om alle nivåene på nytt — de forblir fortsatt like for alle.
	WorldSeed = 20260721,

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
		-- Størrelse: starter 6x6 (lite!), vokser +1 hver 20. level opp til 30x30
		StartSize = 6, SizeEveryNLevels = 20, MaxSize = 30,

		-- Feller: ingen før level 3, +1 hver 17. level opp til 30
		FirstTrapLevel = 3, TrapEveryNLevels = 17, MaxTraps = 30,

		-- Monstre: ingen før level 4, +1 hver 50. level opp til 10
		FirstMonsterLevel = 4, MonsterEveryNLevels = 50, MaxMonsters = 10,
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

local Themes = require(ReplicatedStorage:WaitForChild("Themes"))
local ShopService = require(ReplicatedStorage:WaitForChild("ShopService"))

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

--============================  STATE  ============================--
local currentLevel = 1
local currentGen = 0          -- økes hver bygging; gamle monster-løkker stopper
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

--==========================  HJELPERE  ===========================--
local function halfOf(n) return (n - 1) / 2 end

local function gridToWorld(x, y, gCols, gRows)
	local S = CONFIG.CellSize
	return Vector3.new((x - halfOf(gCols)) * S, 0, (y - halfOf(gRows)) * S)
end

local function cellCenterWorld(cx, cy, gCols, gRows)
	return gridToWorld(2 * cx + 1, 2 * cy + 1, gCols, gRows)
end

local function fmtTime(t) return string.format("%.1fs", t) end

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
		hum.Health = 0
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
		Niva = num("Niva"),
		Mynter = num("Mynter"),
		Edelstener = num("Edelstener"),
		Pokaler = num("Pokaler"),
		BesteTid = str("BesteTid"),
	}
end

local function refreshStats(plr)
	local d = playerData[plr]; if not d then return end
	local s = ensureLeaderstats(plr)
	s.Niva.Value = currentLevel
	s.Mynter.Value = d.coins
	s.Edelstener.Value = d.gems
	s.Pokaler.Value = d.trophies
	s.BesteTid.Value = (d.best < math.huge) and fmtTime(d.best) or "-"
end

--============================  LAGRING  ==========================--
local function loadPlayer(plr)
	local d = { coins = 0, gems = 0, trophies = 0, best = math.huge,
		owned = { classic = true }, theme = Themes.default, receipts = {} }
	if dataStore then
		local ok, saved = pcall(function() return dataStore:GetAsync("p_" .. plr.UserId) end)
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
		end
	end
	d.owned.classic = true                                    -- classic eies alltid
	if not d.owned[d.theme] then d.theme = Themes.default end -- kan ikke ha valgt et uleid tema
	playerData[plr] = d
	refreshStats(plr)
end

local function savePlayer(plr)
	local d = playerData[plr]
	if not d or not dataStore then return false end
	local ok = pcall(function()
		dataStore:SetAsync("p_" .. plr.UserId, {
			coins = d.coins, gems = d.gems, trophies = d.trophies,
			best = (d.best < math.huge) and d.best or nil,
			owned = d.owned, theme = d.theme, receipts = d.receipts,
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
		if exitBillboard then exitBillboard.Text = "UTGANG APEN!" end
	else
		exitPad.Color = Color3.fromRGB(200, 60, 60)
		if exitBillboard then
			if CONFIG.UnlockExitBy == "gems" then
				exitBillboard.Text = "LAST - " .. (gemsTotalInLevel - gemsGrabbedCount) .. " edelsten igjen"
			else
				exitBillboard.Text = "LAST - " .. (coinsTotal - coinsCollected) .. " mynt igjen"
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
	local rng = Random.new(CONFIG.WorldSeed + currentLevel)

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
			if elapsed < d.best then d.best = elapsed end
		end
		d.trophies += 1
		refreshStats(plr)
		savePlayer(plr)
	end

	if CONFIG.MultipleLevels then currentLevel += 1 end
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
	giveTorch(char)
	sendShopData(plr)  -- send saldo/eierskap/valgt tema når klienten sikkert er lastet
end

local function onPlayerAdded(plr)
	loadPlayer(plr)
	plr.CharacterAdded:Connect(function(char) onCharacterAdded(plr, char) end)
	if plr.Character then onCharacterAdded(plr, plr.Character) end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end

Players.PlayerRemoving:Connect(function(plr)
	savePlayer(plr)                 -- flush umiddelbart (fanger evt. debouncet endring)
	playerData[plr] = nil
	startClock[plr] = nil
	saveScheduled[plr] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do savePlayer(plr) end
end)

--============================  START  ============================--
applyDarkness()
buildLevel()
print("[Labyrint] Lastet. Level " .. currentLevel .. " bygget. Lykke til!")
