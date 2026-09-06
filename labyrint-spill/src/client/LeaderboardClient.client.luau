--[[==================================================================
	LABYRINT-SPILL  -  REKORDER / TOPPLISTE (klient, ØVERST-TIL-HØYRE)
	Laget for Marius & onkel :)

	Et lite alltid-synlig panel øverst-til-høyre med TO seksjoner:
	  • 🏆 Fastest — de 3 raskeste tidene på GJELDENDE nivå (fra HudRemotes/LevelInfo).
	  • ⛰️ Top Climbers — de 3 spillerne med HØYEST nivå (fra HudRemotes/Leaderboard).
	Serveren er fasit; klienten bare tegner. All tekst er engelsk, alt nil-sjekket.

	På telefon er dette et ekte sidepanel, og da starter det SKJULT bak en liten
	knapp øverst i høyre kolonne — et alltid-synlig listepanel ville spist en for
	stor del av skjermen.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Medals = require(ReplicatedStorage:WaitForChild("Medals"))

-- Delt skjermstørrelse-modul (ren data — se src/shared/Responsive.luau).
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
-- Delt trykk-mål-modul (ren data — se src/shared/TouchTarget.luau).
local TouchTarget = require(ReplicatedStorage:WaitForChild("TouchTarget"))

local TOP_N = 3

-- Design-mål på panelet. Begge går gjennom takene i Responsive før de brukes.
local PANEL_W, PANEL_H = 212, 240
-- Høyden på telefon-knappen som panelet gjemmer seg bak, og på tema-butikk-knappen
-- rett over den. Begge er tegnet 48 px høye, og begge VOKSER på berøring (et 48 px
-- trykk-mål lander på 29 px når UIScale-en krymper HUD-en ned på en telefon), så
-- hvor kolonnen begynner må regnes ut pr oppsett i stedet for å stå fast på 66.
local TOGGLE_H = 48
local SHOP_TOGGLE_Y, COLUMN_GAP = 12, 6
-- Startverdi til første tegning; applyLayout regner den om (som topY) med en gang.
local START_TOP_Y = SHOP_TOGGLE_Y + TOGGLE_H + COLUMN_GAP

--==========================  GUI  ===============================--
local old = playerGui:FindFirstChild("Records")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "Records"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9
gui.Parent = playerGui

--====================  ROT-RAMME MED UISCALE  ====================--
-- En UIScale gjør INGENTING når den henger rett på en ScreenGui, så vi trenger en
-- gjennomsiktig rot-ramme som eier skaleringen, og panelet henger under den.
-- Active = false: spilleren holder finger på skjermen nesten hele tiden i en
-- hinderløype, og en gjennomsiktig ramme som sluker trykk ville låst bevegelsen.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Active = false
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- Gjeldende skjerm-oppsett. Settes ordentlig av applyLayout() lenger nede.
local rlayout = Responsive.layout(0, 0, UserInputService.TouchEnabled)

-- Trykk-mål i SKJERM-rom: UIScale-en som får HUD-en til å passe på en telefon krymper
-- samtidig hver knapp, så en 48 px knapp ble 29 px — under 44 px-gulvet. tap() vokser
-- design-tallet med 1/skala og lar det aldri lande under gulvet. Gjør ingenting uten
-- berøringskontroller på skjermen, så desktop står stille.
local function tap(designPx)
	return TouchTarget.tap(designPx, rlayout)
end

-- Telefon-knappen panelet gjemmer seg bak. Den ligger øverst i høyre kolonne —
-- ALDRI nederst, der mobil-kontrollene bor. Skjult på nettbrett og desktop.
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "RekordKnapp"
toggleBtn.AnchorPoint = Vector2.new(1, 0)
toggleBtn.Position = UDim2.new(1, -12, 0, START_TOP_Y)
toggleBtn.Size = UDim2.fromOffset(TOGGLE_H, TOGGLE_H)
toggleBtn.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
toggleBtn.BackgroundTransparency = 0.2
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = true
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextScaled = true
toggleBtn.TextColor3 = Color3.fromRGB(255, 210, 90)
toggleBtn.Text = "🏆"
toggleBtn.Visible = false
toggleBtn.Parent = root
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 10)
toggleCorner.Parent = toggleBtn
local togglePad = Instance.new("UIPadding")
togglePad.PaddingTop = UDim.new(0, 8)
togglePad.PaddingBottom = UDim.new(0, 8)
togglePad.Parent = toggleBtn

-- Øverst-til-høyre. Ligger rett under "🎨 Shop"-knappen (~12..60) NÅR minikartet
-- ikke vises; eier spilleren minikartet (som står øverst i samme kolonne), legger
-- panelet seg UNDER kartet (se applyLayout() nederst). Høyre kant følger Shop/kart (-12).
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, START_TOP_Y)
panel.Size = UDim2.new(0, PANEL_W, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Active = false
-- Høyde-taket under kan bite i et svært lavt vindu. Da vil vi heller klippe den
-- nederste linja enn å la lista male seg utover selve labyrinten.
panel.ClipsDescendants = true
panel.Parent = root

local sizeC = Instance.new("UISizeConstraint")
sizeC.MaxSize = Vector2.new(PANEL_W, PANEL_H)
sizeC.MinSize = Vector2.new(150, 0)
sizeC.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 80, 50)
stroke.Thickness = 1
stroke.Transparency = 0.25
stroke.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingBottom = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.Parent = panel

-- Heter listLayout og ikke layout, så den ikke forveksles med skjerm-oppsettet
-- (rlayout) fra Responsive lenger opp.
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 1)
listLayout.Parent = panel

-- Liten fabrikk for en tekst-linje i panelet.
local function mkLine(order, size, color, font, xalign)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, 16)
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = size or 13
	l.TextColor3 = color or Color3.fromRGB(232, 236, 244)
	l.TextXAlignment = xalign or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.RichText = false
	l.Text = ""
	l.Parent = panel
	return l
end

-- Seksjon 1: raskeste tider på nivået.
local fastHeader = mkLine(0, 13, Color3.fromRGB(255, 210, 90), Enum.Font.GothamBold)
fastHeader.Text = "🏆 Fastest"
local fastRows = { mkLine(1), mkLine(2), mkLine(3) }
local fastEmpty = mkLine(4, 12, Color3.fromRGB(150, 156, 170))
fastEmpty.Text = "No times yet"

-- Liten luft mellom seksjonene.
local spacer = Instance.new("Frame")
spacer.LayoutOrder = 5
spacer.Size = UDim2.new(1, 0, 0, 6)
spacer.BackgroundTransparency = 1
spacer.Parent = panel

-- Seksjon 2: høyeste nivå (klatrerne).
local climbHeader = mkLine(6, 13, Color3.fromRGB(140, 200, 255), Enum.Font.GothamBold)
climbHeader.Text = "⛰️ Top Climbers"
local climbRows = { mkLine(7), mkLine(8), mkLine(9) }
local climbEmpty = mkLine(10, 12, Color3.fromRGB(150, 156, 170))
climbEmpty.Text = "Be the first to climb!"

--==========================  RENDER  ============================--
-- Fyll en rad-liste fra data; skjul ubrukte rader, vis "empty" om ingen.
local function fillRows(rows, emptyLbl, count, textFor)
	emptyLbl.Visible = (count == 0)
	for i = 1, TOP_N do
		local r = rows[i]
		if i <= count then
			r.Text = textFor(i)
			r.Visible = true
		else
			r.Visible = false
		end
	end
end

-- LevelInfo: { level, records = { {time, name}, ... }, yourBest }.
local function onLevelInfo(p)
	if type(p) ~= "table" then return end
	local lvl = tonumber(p.level)
	fastHeader.Text = "🏆 Fastest" .. (lvl and (" — Lvl " .. lvl) or "")
	local recs = (type(p.records) == "table") and p.records or {}
	local n = math.min(#recs, TOP_N)
	fillRows(fastRows, fastEmpty, n, function(i)
		local e = recs[i]
		if type(e) ~= "table" then return i .. ". —" end
		local nm = (type(e.name) == "string" and e.name ~= "") and e.name or "?"
		local t = (type(e.time) == "number") and e.time or nil
		return string.format("%d. %s  %s", i, Medals.fmtTime(t), nm)
	end)
end

-- Leaderboard: array { {name, level}, ... } (høyest først).
local function onLeaderboard(list)
	if type(list) ~= "table" then list = {} end
	local n = math.min(#list, TOP_N)
	fillRows(climbRows, climbEmpty, n, function(i)
		local e = list[i]
		local nm = (type(e) == "table" and type(e.name) == "string" and e.name ~= "") and e.name or "Player"
		local lvl = (type(e) == "table" and tonumber(e.level)) or 0
		return string.format("%d. %s · Lvl %d", i, nm, lvl)
	end)
end

--============  SKJERM-TILPASNING + PLASSERING RUNDT KARTET  =====--
-- Minikartet (perk) står øverst-til-høyre på y=66. Eies det + vises det, legger vi
-- rekord-panelet RETT UNDER kartet; ellers rett under Shop-knappen (y=66). På
-- telefon ligger telefon-knappen øverst i kolonnen og panelet under DEN igjen.
local expanded = false

local function applyLayout()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(0, 0)
	rlayout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = rlayout.scale

	-- Rot-rammen må vokse med 1/skala så rot × skala lander nøyaktig på skjermkanten.
	-- Uten dette krymper panelet inn i øvre venstre hjørne på telefon, mens det ser
	-- helt riktig ut på desktop der skalaen er 1 og feilen er usynlig.
	root.Size = UDim2.fromScale(1 / rlayout.scale, 1 / rlayout.scale)

	-- Knappen er hele veien inn til lista på telefon, så den måles i skjerm-piksler:
	-- 48x48 design-piksler kom ut som 29x29 på en 800x360-skjerm. Vokser den, må resten
	-- av kolonnen flytte seg ned — både under tema-butikk-knappen over oss og under vår
	-- egen knapp når skuffa åpner seg.
	local toggleH = tap(TOGGLE_H)
	toggleBtn.Size = UDim2.fromOffset(toggleH, toggleH)
	local topY = SHOP_TOGGLE_Y + toggleH + COLUMN_GAP

	-- Hvor høyt oppe i kolonnen vi får begynne.
	local top = topY
	local mini = playerGui:FindFirstChild("Minikart")
	local frame = mini and mini:FindFirstChild("Kart")
	if frame and frame.Visible and frame.Size.Y.Offset > 0 then
		-- Vi leser Size.Y.Offset og IKKE AbsoluteSize: kartet settes i design-piksler
		-- under sin egen UIScale, og det er design-piksler vi regner i her inne.
		top = topY + frame.Size.Y.Offset + 8
	end

	-- Hvor panelet faktisk begynner. På telefon sitter knappen ØVERST i kolonnen (rett
	-- under butikk-knappen) og skuffen åpner seg rett under den — den legger seg da
	-- oppå minikartet, slik en skuff skal. Da får lista hele resten av kolonnen i
	-- stedet for den vesle stripa som blir igjen under kartet. Minikartet vet om
	-- denne knappen og flytter seg ned for den (se TOGGLE_H/COLUMN_GAP i
	-- MinimapClient), så knappen dekker aldri kartet når skuffen er lukket.
	local panelTop = if rlayout.compact then topY + toggleH + COLUMN_GAP else top

	-- Bredden gjennom sidepanel-taket (venstre + høyre panel kan aldri dekke mer enn
	-- halve skjermen), høyden gjennom fitHeight mot plassen over mobil-kontrollene.
	-- Merk at budsjettet regnes fra panelTop — ikke fra toppen av kolonnen — ellers
	-- stikker den åpne skuffa ned i kontroll-båndet på en lav telefonskjerm.
	local w = Responsive.sideWidth(PANEL_W, v.X, rlayout)
	local usable = Responsive.usableHeight(v.Y, rlayout) - panelTop * rlayout.scale
	local h = Responsive.fitHeight(PANEL_H, usable, rlayout)
	sizeC.MaxSize = Vector2.new(w, math.max(40, h))
	sizeC.MinSize = Vector2.new(math.min(150, w), 0)
	panel.Size = UDim2.new(0, w, 0, 0)

	toggleBtn.Visible = rlayout.compact
	toggleBtn.Position = UDim2.new(1, -12, 0, topY)
	panel.Visible = (not rlayout.compact) or expanded
	panel.Position = UDim2.new(1, -12, 0, panelTop)
end

toggleBtn.Activated:Connect(function()
	expanded = not expanded
	toggleBtn.Text = expanded and "✕" or "🏆"
	applyLayout()
end)

-- workspace.CurrentCamera er nil et bilde eller to ved oppstart, og Roblox bytter
-- den ut ved enkelte respawn, så vi kobler lytteren på nytt når kameraet byttes.
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
watchViewport()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)

task.spawn(function()
	local function hookFrame(frame)
		frame:GetPropertyChangedSignal("Visible"):Connect(applyLayout)
		frame:GetPropertyChangedSignal("Size"):Connect(applyLayout)
		applyLayout()
	end
	local mini = playerGui:FindFirstChild("Minikart")
	if mini then
		local f = mini:FindFirstChild("Kart")
		if f then hookFrame(f) end
	end
	-- Minikart-GUI-en kan bli lagd ETTER dette skriptet (perk lastes async).
	playerGui.ChildAdded:Connect(function(ch)
		if ch.Name == "Minikart" then
			local f = ch:WaitForChild("Kart", 5)
			if f then hookFrame(f) end
		end
	end)
end)

--==================  KOBLE TIL SERVEREN  ========================--
task.spawn(function()
	local hud = ReplicatedStorage:WaitForChild("HudRemotes", 30)
	if not hud then return end

	local levelInfo = hud:WaitForChild("LevelInfo", 15)
	if levelInfo then
		levelInfo.OnClientEvent:Connect(function(p) pcall(onLevelInfo, p) end)
	end

	local leaderboard = hud:WaitForChild("Leaderboard", 15)
	if leaderboard then
		leaderboard.OnClientEvent:Connect(function(list) pcall(onLeaderboard, list) end)
	end
end)
