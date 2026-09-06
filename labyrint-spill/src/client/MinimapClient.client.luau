--[[==================================================================
	LABYRINT-SPILL  -  LIVE MINIKART (klient)
	Laget for Marius & onkel :)

	Dette er et LOKALT skript (Rojo legger src/client i StarterPlayerScripts).
	Det tegner et lite kart i hjørnet som viser labyrinten ovenfra: veggene, start
	og utgang, og en lys prikk for DEG som beveger seg i sanntid.

	Kartet vises BARE hvis du eier perket "minimap" (kjøpes i oppgraderings-
	butikken). Vi lytter på det SAMME PerkData-eventet som perk-butikken for å
	vite om du eier det.

	Ingen bilder/assets — bare Frame / TextLabel / UICorner / UIStroke.

	Ytelse: veggprikkene tegnes ÉN gang pr nivå (statisk). Bare din egen prikk
	oppdateres pr bilde. Alt er nil-sikret: mangler labyrinten, gulvet eller
	figuren din, så gjør kartet ingenting i stedet for å krasje.

	Mobil-vennlig: kartet ligger ØVERST TIL HØYRE, UNDER tema-butikk-knappen (så
	det ikke dekker den), og aldri i de nederste hjørnene der mobil-kontrollene er
	(styrepinne nede-venstre, hopp nede-høyre). Størrelsen regnes ut fra vinduet via
	den delte Responsive-modulen, ikke som en fast firkant, slik at kartet aldri kan
	sluke en telefonskjerm.
==================================================================]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Delt skjermstørrelse-modul (ren data — se src/shared/Responsive.luau).
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
-- Delt trykk-mål-modul (ren data — se src/shared/TouchTarget.luau).
local TouchTarget = require(ReplicatedStorage:WaitForChild("TouchTarget"))

--============================  INNSTILLINGER  ====================--
-- Tak på antall veggprikker (sikkerhets-vakt mot å sprute ut tusenvis av Frames).
-- Størrelsen her: en full 30x30-labyrint blir et 61x61-rutenett med ~1900 vegger,
-- så taket er satt over det (2200) slik at selv de STØRSTE nivåene tegner alle
-- veggene — det er der et kart hjelper mest. Veggprikkene er statiske (tegnes én
-- gang pr nivå), så ~1900 Frames er billig. Over taket faller vi pent tilbake til
-- BARE ramme + utgang + start + spilleren. Senk til f.eks. 1200 om du heller vil
-- spare minne på de aller største nivåene.
local MAX_WALL_DOTS = 2200
-- Hvor lenge vi venter på at flere vegger skal strømme inn før vi tegner kartet
-- (avdemping: vi tegner én gang når labyrinten har "roet seg").
local REBUILD_DEBOUNCE = 0.35

--============================  STATE  ============================--
local hasMinimap = false -- fra PerkData: eier du "minimap"?

-- Kartleggings-tall, fanget fra "Floor" ved siste vellykkede bygging. floorSizeX
-- > 0 betyr "kartet er klart å tegnes". Gulvet er sentrert i verden, så
-- min-hjørnet = Position - Size/2.
local floorSizeX, floorSizeZ = 0, 0
local floorMinX, floorMinZ = 0, 0

local playerDot = nil -- din prikk (oppdateres pr bilde)
local activeFolder = nil -- nåværende MazeGame-mappe
local descConn = nil -- forbindelse til mappas DescendantAdded
local rebuildSeq = 0 -- avdempings-teller for ombygging

--============================  UI-OPPSETT  =======================--
local playerGui = player:WaitForChild("PlayerGui")

-- Aldri to like GUI-er.
if playerGui:FindFirstChild("Minikart") then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "Minikart"
gui.ResetOnSpawn = false -- overlever respawn; ingen dobbel-GUI
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 6 -- under tema-butikken (10), så butikk-panelet legger seg over
gui.Enabled = true
gui.Parent = playerGui

--==================  EFFEKTIV HØYDE (topplinja)  ================--
-- IgnoreGuiInset står på false (standard), så Roblox korter ned det tegnbare området med
-- topplinje-innslaget (~36 px) — mens budsjettene under regnes fra camera.ViewportSize.Y,
-- altså HELE skjermen. Et panel som fyller den høyden stikker nøyaktig innslaget for langt
-- ned, ned i båndet der mobil-kontrollene bor. Derfor mates den EFFEKTIVE høyden inn i
-- Responsive.layout og i alt som regnes ut av den. GetGuiInset gir TO Vector2-er; den
-- første er innslaget øverst til venstre. pcall fordi et oppsett som ikke gir oss innslaget
-- skal ende med hele høyden — som før — og ikke velte tegningen.
local function effectiveY(vy: number): number
	if gui.IgnoreGuiInset then
		return vy
	end
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and inset ~= nil and type(inset.Y) == "number" and vy - inset.Y > 0 then
		return vy - inset.Y
	end
	return vy
end

--====================  ROT-RAMME MED UISCALE  ====================--
-- En UIScale gjør INGENTING når den henger rett på en ScreenGui, så vi trenger en
-- gjennomsiktig rot-ramme som eier skaleringen, og alt kart-innhold henger under
-- den. Active = false: i et hinderløype-spill holder spilleren finger på skjermen
-- nesten hele tiden, og en gjennomsiktig ramme som sluker trykk ville gjort det
-- umulig å bevege seg. En Frame sluker bare input når Active er true.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Active = false
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- Kartet starter rett under tema-butikk-knappen, og på telefon ett hakk til: da legger
-- LeaderboardClient sin lille rekord-knapp seg øverst i den SAMME høyre kolonnen.
-- Begge knappene er tegnet 48 px høye, og begge VOKSER på berøring (et 48 px trykk-mål
-- lander på 29 px når UIScale-en krymper HUD-en ned på en telefon), så vi regner ut hvor
-- kolonnen begynner pr oppsett i stedet for å bake inn 66 og 54. Endres knapphøyden i
-- ShopClient eller LeaderboardClient, må den endres her også — kolonnen deles av de tre.
local TOGGLE_H = 48
local SHOP_TOGGLE_Y, COLUMN_GAP = 12, 6
-- Startverdi til første tegning; applyLayout regner den om (som topY) med en gang.
local START_TOP_Y = SHOP_TOGGLE_Y + TOGGLE_H + COLUMN_GAP

-- Gjeldende skjerm-oppsett. Settes ordentlig av applyLayout() lenger nede.
local layout = Responsive.layout(0, 0, UserInputService.TouchEnabled)

-- Selve kart-ruta: en liten firkant øverst til høyre, UNDER butikk-knappen.
local mapFrame = Instance.new("Frame")
mapFrame.Name = "Kart"
mapFrame.AnchorPoint = Vector2.new(1, 0)
mapFrame.Position = UDim2.new(1, -12, 0, START_TOP_Y)
mapFrame.Size = UDim2.fromOffset(150, 150) -- settes av applyLayout under
mapFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
mapFrame.BackgroundTransparency = 0.25 -- halv-gjennomsiktig
mapFrame.BorderSizePixel = 0
mapFrame.Active = false -- kartet er ren visning; må aldri sluke trykk
mapFrame.Visible = false -- skjult til du eier perket OG labyrinten finnes
mapFrame.Parent = root

local mapCorner = Instance.new("UICorner")
mapCorner.CornerRadius = UDim.new(0, 8)
mapCorner.Parent = mapFrame

-- Ramma = labyrintens yttergrense (vises alltid, også når vi hopper over vegger).
local mapStroke = Instance.new("UIStroke")
mapStroke.Color = Color3.fromRGB(120, 128, 150)
mapStroke.Thickness = 1
mapStroke.Parent = mapFrame

-- Tittel-stripe øverst.
local titleLbl = Instance.new("TextLabel")
titleLbl.Name = "Tittel"
titleLbl.Size = UDim2.new(1, 0, 0, 18)
titleLbl.Position = UDim2.fromOffset(0, 0)
titleLbl.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
titleLbl.BackgroundTransparency = 0.35
titleLbl.TextColor3 = Color3.fromRGB(225, 230, 245)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextScaled = true
titleLbl.Text = "Map"
titleLbl.ZIndex = 8
titleLbl.Parent = mapFrame
local titleTsc = Instance.new("UITextSizeConstraint")
titleTsc.MaxTextSize = 13
titleTsc.MinTextSize = 8
titleTsc.Parent = titleLbl

-- Lerretet der prikkene tegnes (under tittelen). Vi rydder BARE dette, så
-- tittel/ramme står i fred.
local canvas = Instance.new("Frame")
canvas.Name = "Lerret"
canvas.Position = UDim2.new(0, 4, 0, 22)
canvas.Size = UDim2.new(1, -8, 1, -26)
canvas.BackgroundTransparency = 1
canvas.BorderSizePixel = 0
canvas.ClipsDescendants = true
canvas.Parent = mapFrame

--=====================  STØRRELSE (mobil-skalering)  =============--
-- Kartet er den delen av HUD-et som lettest kan sluke en telefonskjerm, så
-- størrelsen regnes ut fra vinduet — ikke som en fast firkant — og sendes gjennom
-- begge takene i Responsive før den brukes.
local function applyLayout()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(0, 0)
	-- Den tegnbare høyden, ikke hele vinduet: se effectiveY over.
	local effY = effectiveY(v.Y)
	layout = Responsive.layout(v.X, effY, UserInputService.TouchEnabled, v.Y)
	uiScale.Scale = layout.scale

	-- Rot-rammen må vokse med 1/skala så rot × skala lander nøyaktig på skjermkanten.
	-- Uten dette krymper hele kartet inn i øvre venstre hjørne på telefon, mens det
	-- ser helt riktig ut på desktop der skalaen er 1 og feilen er usynlig.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	-- Ønsket størrelse i DESIGN-piksler: ~22 % av den korteste kanten på design-flata
	-- (skjermen delt på skalaen). Aldri under 96 (fortsatt lesbart) eller over 150
	-- (ikke enormt på desktop) — samme tall som før, bare målt i riktig rom.
	local designMin = math.min(v.X, effY) / layout.scale
	if designMin <= 0 then
		designMin = Responsive.REF_Y -- vinduet er ikke kjent ennå; neste kall retter det
	end
	local want = math.clamp(math.floor(designMin * 0.22), 96, 150)

	-- Toppen av kolonnen. På telefon står rekord-knappen over oss, så vi flytter ned.
	-- Begge knappene vokser i skjerm-rom på berøring, så begge trinnene måles med tap().
	local toggleH = TouchTarget.tap(TOGGLE_H, layout)
	local topY = SHOP_TOGGLE_Y + toggleH + COLUMN_GAP
	local top = if layout.compact then topY + toggleH + COLUMN_GAP else topY

	-- Så gjennom takene: bredden kan aldri ta mer enn en fjerdedel av skjermen, og
	-- høyden må få plass mellom butikk-knappen og mobil-kontrollene nederst. Kartet
	-- er kvadratisk, så vi bruker det minste av de to.
	local wCap = Responsive.sideWidth(want, v.X, layout)
	-- usableHeight svarer i SKJERM-piksler, mens top er design-piksler — derfor
	-- ganges top opp med skalaen før vi trekker den fra.
	local usable = Responsive.usableHeight(effY, layout) - top * layout.scale
	local hCap = Responsive.fitHeight(want, usable, layout)

	local side = math.max(56, math.min(wCap, hCap))
	mapFrame.Position = UDim2.new(1, -12, 0, top)
	mapFrame.Size = UDim2.fromOffset(side, side)
end

-- workspace.CurrentCamera er nil et bilde eller to ved oppstart, og Roblox bytter
-- den ut ved enkelte respawn. Vi kobler lytteren på nytt når kameraet byttes — og
-- kobler den gamle FRA først, så vi ikke samler opp forbindelser over tid.
local viewportConn
local function watchViewport()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end

--============================  KARTLEGGING  ======================--
-- Verden (x,z) -> 0..1 kart-koordinat. nil hvis kartet ikke er klart. Deler på
-- gulvets størrelse (vakt mot deling på null).
local function mapCoords(worldX, worldZ)
	if floorSizeX <= 0 or floorSizeZ <= 0 then
		return nil
	end
	local nx = (worldX - floorMinX) / floorSizeX
	local nz = (worldZ - floorMinZ) / floorSizeZ
	return math.clamp(nx, 0, 1), math.clamp(nz, 0, 1)
end

-- Liten rund markør (utgang/start/spiller).
local function makeMarker(nx, nz, color, sizePx, z)
	local m = Instance.new("Frame")
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.Position = UDim2.fromScale(nx, nz)
	m.Size = UDim2.fromOffset(sizePx, sizePx)
	m.BackgroundColor3 = color
	m.BorderSizePixel = 0
	m.ZIndex = z
	m.Parent = canvas
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0) -- rund
	c.Parent = m
	return m
end

--============================  BYGG STATISKE PRIKKER  ============--
-- Tegner vegger + utgang + start + spiller-prikk ÉN gang for et nivå. Trygg å
-- kalle når som helst: rydder først, og gjør ingenting hvis gulvet mangler.
local function buildStaticDots(folder)
	-- Rydd kun lerretet (prikkene). Nullstill "klar"-flagget til vi lykkes.
	canvas:ClearAllChildren()
	playerDot = nil
	floorSizeX = 0

	if not folder or folder.Parent == nil then
		return
	end

	local floor = folder:FindFirstChild("Floor")
	if not floor or not floor:IsA("BasePart") then
		return -- gulvet er ikke strømmet inn ennå; en senere ombygging fanger det
	end
	local fs = floor.Size
	local fp = floor.Position
	if fs.X <= 0 or fs.Z <= 0 then
		return
	end
	floorSizeX = fs.X
	floorSizeZ = fs.Z
	floorMinX = fp.X - fs.X / 2
	floorMinZ = fp.Z - fs.Z / 2

	-- Samle veggene.
	local walls = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Wall" or d.Name == "SecretWall") then
			table.insert(walls, d)
		end
	end

	-- Tegn vegger som små mørke ruter (hopp over hvis labyrinten er enorm).
	if #walls <= MAX_WALL_DOTS then
		for _, w in ipairs(walls) do
			local nx, nz = mapCoords(w.Position.X, w.Position.Z)
			if nx then
				local dot = Instance.new("Frame")
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Position = UDim2.fromScale(nx, nz)
				-- Fyll cella: veggens andel av gulvet i hver retning.
				dot.Size = UDim2.fromScale(
					math.clamp(w.Size.X / floorSizeX, 0, 1),
					math.clamp(w.Size.Z / floorSizeZ, 0, 1)
				)
				dot.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
				dot.BorderSizePixel = 0
				dot.ZIndex = 2
				dot.Parent = canvas
			end
		end
	end

	-- Utgang (rød prikk).
	local exit = folder:FindFirstChild("Exit")
	if exit and exit:IsA("BasePart") then
		local nx, nz = mapCoords(exit.Position.X, exit.Position.Z)
		if nx then
			makeMarker(nx, nz, Color3.fromRGB(230, 90, 60), 7, 4)
		end
	end

	-- Start (grønn prikk).
	local mazeSpawn = folder:FindFirstChild("MazeSpawn")
	if mazeSpawn and mazeSpawn:IsA("BasePart") then
		local nx, nz = mapCoords(mazeSpawn.Position.X, mazeSpawn.Position.Z)
		if nx then
			makeMarker(nx, nz, Color3.fromRGB(60, 200, 90), 7, 4)
		end
	end

	-- Din prikk (lys, tegnet sist så den ligger øverst). Plasseres pr bilde.
	playerDot = makeMarker(0.5, 0.5, Color3.fromRGB(90, 190, 255), 8, 6)
	local ps = Instance.new("UIStroke")
	ps.Color = Color3.fromRGB(255, 255, 255)
	ps.Thickness = 1
	ps.Parent = playerDot
	playerDot.Visible = false -- til vi har en gyldig figur-posisjon
end

--============================  SYNLIGHET  ========================--
local function updateVisibility()
	local folder = workspace:FindFirstChild("MazeGame")
	mapFrame.Visible = hasMinimap and folder ~= nil and floorSizeX > 0
end

--============================  OMBYGGING (avdempet)  =============--
-- Veggene strømmer inn over litt tid etter at mappa dukker opp. Vi utsetter
-- tegningen litt hver gang en ny del kommer, så vi tegner ÉN gang når det har
-- roet seg — i stedet for hundrevis av ganger.
local function requestRebuild(folder)
	rebuildSeq += 1
	local mine = rebuildSeq
	task.delay(REBUILD_DEBOUNCE, function()
		if mine ~= rebuildSeq then
			return -- en nyere del kom; den planla en senere tegning
		end
		if folder ~= activeFolder or folder.Parent == nil then
			return
		end
		local ok = pcall(buildStaticDots, folder)
		if not ok then
			floorSizeX = 0
		end
		updateVisibility()
	end)
end

-- Bytt til en ny (eller ingen) MazeGame-mappe.
local function attachFolder(folder)
	if folder == activeFolder then
		return
	end
	if descConn then
		descConn:Disconnect()
		descConn = nil
	end
	activeFolder = folder
	-- Nullstill og rydd med en gang, så et gammelt kart ikke henger igjen.
	floorSizeX = 0
	canvas:ClearAllChildren()
	playerDot = nil
	updateVisibility()

	if not folder then
		return
	end
	-- Fang vegger som strømmer inn, og be om en (avdempet) tegning.
	descConn = folder.DescendantAdded:Connect(function()
		requestRebuild(folder)
	end)
	requestRebuild(folder) -- også hvis delene alt er der
end

-- Ny labyrint dukker opp (nytt nivå).
workspace.ChildAdded:Connect(function(child)
	if child.Name == "MazeGame" then
		attachFolder(child)
	end
end)

-- Labyrinten fjernes (serveren bygger nytt nivå).
workspace.ChildRemoved:Connect(function(child)
	if child == activeFolder then
		attachFolder(nil)
	end
end)

-- Håndter at labyrinten alt finnes når skriptet starter.
do
	local existing = workspace:FindFirstChild("MazeGame")
	if existing then
		attachFolder(existing)
	end
end

--============================  DIN PRIKK PR BILDE  ===============--
-- Eneste arbeidet pr bilde: flytt spiller-prikken. Alt annet er statisk.
RunService.RenderStepped:Connect(function()
	if not mapFrame.Visible then
		return
	end
	if not playerDot then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		playerDot.Visible = false
		return
	end
	local nx, nz = mapCoords(root.Position.X, root.Position.Z)
	if not nx then
		playerDot.Visible = false
		return
	end
	playerDot.Position = UDim2.fromScale(nx, nz)
	playerDot.Visible = true
end)

--==================  KOBLE TIL PERK-DATA  =======================--
-- Samme "PerkRemotes/PerkData"-event som perk-butikken. Vi bryr oss bare om
-- perks.minimap. Mangler mappa, står kartet bare skjult — det krasjer aldri.
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("PerkRemotes", 30)
	if not remotes then
		return -- ingen server-del ennå: kartet forblir skjult
	end
	local PerkData = remotes:WaitForChild("PerkData", 10)
	if not PerkData then
		return
	end
	PerkData.OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.perks) == "table" then
			hasMinimap = data.perks.minimap == true
		else
			hasMinimap = false
		end
		updateVisibility()
	end)
end)

--==============  FØRSTE OPPSETT + LYTTERE (ALLER SIST)  =========--
-- Rekkefølgen er med vilje: remotene kobles opp FØRST, så første oppsett, og lytteren på
-- inndata-enheten aller sist. Et LocalScript som reiser stopper på stedet, så det samme
-- kallet plassert over OnClientEvent-handlerne ville — den dagen det reiste — etterlatt
-- spilleren med et frosset HUD og ingen måte å merke det på.
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

-- Hver trykk-mål-størrelse henger på layout.controlPad, som kommer fra
-- UserInputService.TouchEnabled. Endrer berøringen seg UTEN at pikselstørrelsen gjør det
-- (et nettbrett som kobler fra tastaturet, en telefon som får mus), fyrer ViewportSize
-- aldri, og hver kontroll beholder størrelsen fra forrige inndata-enhet — nøyaktig slik
-- rekord-knappen ble stående på 29x29. Layout er kosmetikk; tilstands-røret er det ikke,
-- så selve Connect ligger i pcall.
local touchOk, touchErr = pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
if not touchOk then
	warn("[Minikart] ingen TouchEnabled-lytter; oppsettet følger bare vinduet: " .. tostring(touchErr))
end
