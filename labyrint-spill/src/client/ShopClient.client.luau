--[[==================================================================
	LABYRINT-SPILL  -  TEMA-BUTIKK (klient)
	Laget for Marius & onkel :)

	Dette er et LOKALT skript (Rojo legger src/client i StarterPlayerScripts).
	Det gjør to jobber:

	  JOBB 1 — Butikk-vindu (UI): en knapp oppe i hjørnet ("🎨 Butikk") som
	           åpner en liste over alle vegg-temaene. Du ser en liten fargeprøve,
	           navnet, og enten "Valgt", en "Velg"-knapp, eller kjøp-knapper.
	           Serveren er sjefen: klienten spør bare pent via Remotes, serveren
	           validerer, trekker mynter/edelstener og svarer med fasit.

	  JOBB 2 — Farg om veggene BARE for meg: serveren bygger labyrinten med de
	           klassiske gråfargene. Denne koden maler mine egne vegger/gulv om
	           til temaet JEG har valgt. Fargeendring på klienten er lokal (ingen
	           andre ser den), så alle kan ha hvert sitt utseende samtidig.

	Ingen bilder/assets brukes — alt tegnes av Frames og TextButtons.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Delt tema-liste (ren data, samme som serveren bruker).
local Themes = require(ReplicatedStorage:WaitForChild("Themes"))

--============================  STATE  ============================--
-- Fasit kommer fra serveren via ShopData-eventet. Vi starter forsiktig:
-- bare "classic" eies, ingen valuta, klassisk tema valgt.
local state = {
	coins = 0,
	gems = 0,
	owned = { [Themes.default] = true },
	theme = Themes.default,
}

-- Hvilket tema veggene mine skal males med akkurat nå. Styrer JOBB 2.
local currentTheme = Themes.default

-- Remotes fylles ut når vi finner dem (kan mangle en liten stund ved oppstart,
-- eller helt hvis server-delen ikke er lagt inn ennå). Alltid nil-sjekket.
local BuyTheme = nil
local SelectTheme = nil
local ShopData = nil

--==========================  HJELPERE  ===========================--
-- {r,g,b} 0-255  ->  Color3
local function c3(rgb)
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Hvilket farge-felt hører til hvilket delnavn i labyrinten.
local PART_FIELD = {
	Wall = "wall",
	SecretWall = "secret",
	Floor = "floor",
}

-- Norske forklaringer på hvorfor et kjøp/valg ikke gikk (server-grunner).
local REASON_NO = {
	insufficient = "Ikke nok",
	owned = "Eier allerede",
	notowned = "Ikke kjøpt",
	unknown = "Ukjent tema",
	badcurrency = "Ikke til salgs",
	notforsale = "Ikke til salgs",
}

--==================  JOBB 2: FARG OM VEGGENE  ====================--
-- Mal én enkelt del etter navnet sitt, hvis temaet har en farge for den.
local function recolorPart(part, theme)
	local field = PART_FIELD[part.Name]
	if not field then return end
	local rgb = theme[field]
	if rgb then
		part.Color = c3(rgb)
	end
end

-- Mal ALLE veggene/gulvet i labyrinten om til et gitt tema. Tåler at
-- MazeGame ikke finnes ennå (returnerer bare stille).
local function recolorAll(themeId)
	local folder = workspace:FindFirstChild("MazeGame")
	if not folder then return end
	local theme = Themes.byId(themeId)
	if not theme then return end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			recolorPart(d, theme)
		end
	end
end

-- Legg mitt valgte tema på hele labyrinten.
-- KLASSISK = ikke fargelegg: da er serverens originalfarger allerede riktige.
-- (Å BYTTE fra et annet tema tilbake til klassisk håndteres i applyServerState,
--  der vi tilbakestiller til de klassiske fargene igjen.)
local function applyTheme()
	if currentTheme == Themes.default then
		return
	end
	recolorAll(currentTheme)
end

-- Nye deler dukker opp hele tiden når serveren bygger et nytt nivå. Fang dem
-- og mal dem straks — så temaet overlever hver ombygging uten at vi må gjette.
workspace.DescendantAdded:Connect(function(inst)
	if currentTheme == Themes.default then return end
	if not inst:IsA("BasePart") then return end
	if not PART_FIELD[inst.Name] then return end
	local folder = workspace:FindFirstChild("MazeGame")
	if not folder or not inst:IsDescendantOf(folder) then return end
	local theme = Themes.byId(currentTheme)
	if theme then
		recolorPart(inst, theme)
	end
end)

-- Når en helt ny MazeGame-mappe dukker opp (nytt nivå), ta en full runde.
-- Mappa er som regel tom i akkurat dette øyeblikket — DescendantAdded over
-- tar delene etter hvert — men dette er beltet i tillegg til bukseselene.
workspace.ChildAdded:Connect(function(child)
	if child.Name == "MazeGame" then
		applyTheme()
	end
end)

-- Hvis labyrinten allerede står der når skriptet starter, mal den nå.
applyTheme()

--==================  DEL UT NY FASIT FRA SERVEREN  ===============--
-- Brukes både for ShopData-eventet og for svaret på kjøp/valg. Oppdaterer
-- saldo, eierskap og valgt tema, farger om veggene, og frisker opp UI.
local refreshHeader -- fylles ut lenger nede (UI)
local refreshRows -- fylles ut lenger nede (UI)

local function applyServerState(data)
	if type(data) ~= "table" then return end

	if type(data.coins) == "number" then state.coins = data.coins end
	if type(data.gems) == "number" then state.gems = data.gems end
	if type(data.owned) == "table" then state.owned = data.owned end

	-- Klassisk eies alltid, uansett hva serveren sier.
	state.owned = state.owned or {}
	state.owned[Themes.default] = true

	if type(data.theme) == "string" and data.theme ~= currentTheme then
		local newTheme = data.theme
		currentTheme = newTheme
		state.theme = newTheme
		if newTheme == Themes.default then
			-- Byttet TILBAKE til klassisk: tilbakestill veggene til serverens
			-- originalfarger (som nettopp ER de klassiske fargene).
			recolorAll(Themes.default)
		else
			applyTheme()
		end
	elseif type(data.theme) == "string" then
		state.theme = data.theme
	end

	if refreshHeader then refreshHeader() end
	if refreshRows then refreshRows() end
end

--============================  JOBB 1: UI  =======================--
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "TemaButikk"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
gui.Parent = playerGui

local function corner(inst, r)
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(0, r or 6)
	uc.Parent = inst
	return uc
end

-- Knapp øverst til høyre som åpner/lukker butikken.
local toggle = Instance.new("TextButton")
toggle.Name = "ButikkKnapp"
-- Stort trykk-mål (48px høyt) for telefon. Blir liggende ØVERST til høyre,
-- godt klar av mobil-kontrollene (styrepinne nede-venstre, hopp nede-høyre).
toggle.Size = UDim2.fromOffset(140, 48)
toggle.AnchorPoint = Vector2.new(1, 0)
toggle.Position = UDim2.new(1, -12, 0, 12)
toggle.BackgroundColor3 = Color3.fromRGB(52, 58, 78)
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Font = Enum.Font.GothamBold
toggle.TextScaled = true
toggle.Text = "🎨 Butikk"
toggle.AutoButtonColor = true
toggle.Parent = gui
corner(toggle, 8)
-- Tekst-tilpasning: fyll knappen pent, men ikke bli enorm på desktop.
local toggleTsc = Instance.new("UITextSizeConstraint")
toggleTsc.MaxTextSize = 20
toggleTsc.MinTextSize = 12
toggleTsc.Parent = toggle
local togglePad = Instance.new("UIPadding")
togglePad.PaddingLeft = UDim.new(0, 10)
togglePad.PaddingRight = UDim.new(0, 10)
togglePad.PaddingTop = UDim.new(0, 6)
togglePad.PaddingBottom = UDim.new(0, 6)
togglePad.Parent = toggle

-- Selve panelet (skjult til man trykker).
local panel = Instance.new("Frame")
panel.Name = "Panel"
-- Skala-basert størrelse (andel av skjermen) med tak nedenfor. På en liten
-- telefon blir panelet ≤80% av skjermhøyden, så de 17 radene MÅ rulles; på
-- desktop kapper UISizeConstraint det så det ikke blir enormt.
panel.Size = UDim2.new(0.94, 0, 0.8, 0)
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -12, 0, 66)
panel.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
corner(panel, 10)
-- Tak/gulv på panel-størrelsen: aldri større enn dette på desktop, aldri så
-- lite at innholdet klemmes på en bitteliten skjerm.
local panelSize = Instance.new("UISizeConstraint")
panelSize.MaxSize = Vector2.new(380, 620)
panelSize.MinSize = Vector2.new(300, 300)
panelSize.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(70, 78, 100)
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- ---- Topptekst: tittel, saldo, lukkeknapp, status ----
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -66, 0, 28)
title.Position = UDim2.fromOffset(14, 10)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.Text = "🎨 Tema-butikk"
title.Parent = panel
local titleTsc = Instance.new("UITextSizeConstraint")
titleTsc.MaxTextSize = 20
titleTsc.MinTextSize = 12
titleTsc.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(44, 44)  -- 44px = komfortabelt trykk-mål på telefon
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -10, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(70, 50, 58)
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 24
closeBtn.Text = "✕"
closeBtn.Parent = panel
corner(closeBtn, 6)

local balance = Instance.new("TextLabel")
balance.Size = UDim2.new(1, -28, 0, 22)
balance.Position = UDim2.fromOffset(14, 40)
balance.BackgroundTransparency = 1
balance.TextXAlignment = Enum.TextXAlignment.Left
balance.TextColor3 = Color3.fromRGB(235, 220, 150)
balance.Font = Enum.Font.GothamMedium
balance.TextScaled = true
balance.Text = "🪙 0 mynter    💎 0 edelstener"
balance.Parent = panel
local balanceTsc = Instance.new("UITextSizeConstraint")
balanceTsc.MaxTextSize = 16
balanceTsc.MinTextSize = 10
balanceTsc.Parent = balance

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -28, 0, 18)
status.Position = UDim2.fromOffset(14, 66)
status.BackgroundTransparency = 1
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(255, 150, 140)
status.Font = Enum.Font.GothamMedium
status.TextScaled = true
status.Text = ""
status.Parent = panel
local statusTsc = Instance.new("UITextSizeConstraint")
statusTsc.MaxTextSize = 15
statusTsc.MinTextSize = 10
statusTsc.Parent = status

-- ---- Listen med temaer (kan rulles) ----
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Liste"
scroll.Size = UDim2.new(1, -16, 1, -96)
scroll.Position = UDim2.fromOffset(8, 90)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 10  -- litt bredere så det er lett å ta tak i med finger
scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 128, 150)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 2)
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = scroll

--==========================  UI-OPPFRISK  ========================--
function refreshHeader()
	balance.Text = string.format("🪙 %d mynter    💎 %d edelstener", state.coins, state.gems)
end

-- Vis en kort beskjed (grunn/kvittering) som forsvinner av seg selv.
local statusToken = 0
local function showStatus(msg, good)
	status.Text = msg or ""
	status.TextColor3 = good and Color3.fromRGB(140, 235, 160) or Color3.fromRGB(255, 150, 140)
	statusToken += 1
	local mine = statusToken
	task.delay(2.5, function()
		if mine == statusToken then
			status.Text = ""
		end
	end)
end

-- Send et kjøps-/valg-svar inn i staten, og vis grunn/kvittering.
local function handleActionResult(res, successMsg)
	if type(res) ~= "table" then
		showStatus("Nettverksfeil, prøv igjen")
		return
	end
	applyServerState(res) -- oppdater fra fasit (coins/gems/owned/theme)
	if res.ok == false then
		showStatus(REASON_NO[res.reason] or "Gikk ikke")
	elseif successMsg then
		showStatus(successMsg, true)
	end
end

local function doBuy(themeId, payWith)
	if not BuyTheme then
		showStatus("Butikken laster ...")
		return
	end
	local ok, res = pcall(function()
		return BuyTheme:InvokeServer(themeId, payWith)
	end)
	if ok then
		handleActionResult(res, "Kjøpt!")
	else
		showStatus("Nettverksfeil, prøv igjen")
	end
end

local function doSelect(themeId)
	if not SelectTheme then
		showStatus("Butikken laster ...")
		return
	end
	local ok, res = pcall(function()
		return SelectTheme:InvokeServer(themeId)
	end)
	if ok then
		handleActionResult(res, "Valgt!")
	else
		showStatus("Nettverksfeil, prøv igjen")
	end
end

-- Liten fabrikk for knapper i en rad.
local function makeButton(parent, text, size, position, color)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	-- TextScaled + tak: pris-teksten fyller knappen og krymper for å få plass,
	-- så ingenting flyter over på en liten telefon-skjerm.
	b.TextScaled = true
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 6)
	local tsc = Instance.new("UITextSizeConstraint")
	tsc.MaxTextSize = 16
	tsc.MinTextSize = 9
	tsc.Parent = b
	local bp = Instance.new("UIPadding")
	bp.PaddingLeft = UDim.new(0, 8)
	bp.PaddingRight = UDim.new(0, 8)
	bp.PaddingTop = UDim.new(0, 4)
	bp.PaddingBottom = UDim.new(0, 4)
	bp.Parent = b
	return b
end

-- Bygg hele lista på nytt fra staten. Enkelt og trygt: 17 rader er billig.
function refreshRows()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end

	for i, t in ipairs(Themes.List) do
		local owned = (t.id == Themes.default) or (state.owned[t.id] == true)
		local selected = (state.theme == t.id)

		-- Finn kjøp-knappene FØRST, så vi vet hvor høy raden må være: hver knapp
		-- skal være et komfortabelt trykk-mål (~44px) på telefon. (Samme betingelse
		-- som "else"-grenen under: bare når temaet verken er eid eller valgt.)
		local buys = {}
		if (not owned) and (not selected) then
			if t.coinPrice and t.coinPrice > 0 then
				table.insert(buys, {
					text = "Kjøp: " .. t.coinPrice .. " mynter",
					pay = "coins",
					color = Color3.fromRGB(198, 156, 44),
				})
			end
			if t.gemPrice and t.gemPrice > 0 then
				table.insert(buys, {
					text = t.gemPrice .. " edelstener",
					pay = "gems",
					color = Color3.fromRGB(150, 92, 216),
				})
			end
		end

		local BTN_H, BTN_GAP, ROW_PAD = 44, 8, 10
		local nBuys = #buys
		local rowH = 64
		if nBuys > 1 then
			-- To knapper stables loddrett -> raden må være høyere. Panelet ruller,
			-- så det er greit at raden blir høy.
			rowH = nBuys * BTN_H + (nBuys - 1) * BTN_GAP + ROW_PAD * 2
		end

		local row = Instance.new("Frame")
		row.Name = "Rad_" .. t.id
		row.Size = UDim2.new(1, -6, 0, rowH)
		row.BackgroundColor3 = selected and Color3.fromRGB(40, 62, 46) or Color3.fromRGB(42, 46, 60)
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = scroll
		corner(row, 6)
		if selected then
			local rs = Instance.new("UIStroke")
			rs.Color = Color3.fromRGB(60, 200, 90)
			rs.Thickness = 1
			rs.Parent = row
		end

		-- Fargeprøve: tre bittesmå ruter (vegg / hemmelig / gulv). Sentrert loddrett
		-- så den sitter fint uansett radhøyde.
		local swatch = Instance.new("Frame")
		swatch.AnchorPoint = Vector2.new(0, 0.5)
		swatch.Size = UDim2.fromOffset(18, 42)
		swatch.Position = UDim2.new(0, 8, 0.5, 0)
		swatch.BackgroundTransparency = 1
		swatch.Parent = row
		local function chip(idx, rgb)
			local f = Instance.new("Frame")
			f.Size = UDim2.new(1, 0, 0, 13)
			f.Position = UDim2.fromOffset(0, (idx - 1) * 14)
			f.BackgroundColor3 = c3(rgb)
			f.BorderSizePixel = 0
			f.Parent = swatch
			corner(f, 3)
		end
		chip(1, t.wall)
		chip(2, t.secret)
		chip(3, t.floor)

		-- Navn på temaet (sentrert loddrett; teksten krymper for å få plass).
		local name = Instance.new("TextLabel")
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Size = UDim2.new(1, -214, 0, 26)
		name.Position = UDim2.new(0, 34, 0.5, 0)
		name.BackgroundTransparency = 1
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Font = Enum.Font.GothamMedium
		name.TextScaled = true
		name.Text = t.name
		name.Parent = row
		local nameTsc = Instance.new("UITextSizeConstraint")
		nameTsc.MaxTextSize = 16
		nameTsc.MinTextSize = 10
		nameTsc.Parent = name

		-- Handlings-området til høyre.
		if selected then
			-- Eid + valgt: bare et fremhevet "Valgt"-merke.
			local valgt = Instance.new("TextLabel")
			valgt.Size = UDim2.fromOffset(168, 40)
			valgt.AnchorPoint = Vector2.new(1, 0.5)
			valgt.Position = UDim2.new(1, -8, 0.5, 0)
			valgt.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
			valgt.TextColor3 = Color3.fromRGB(15, 35, 20)
			valgt.Font = Enum.Font.GothamBold
			valgt.TextScaled = true
			valgt.Text = "✓ Valgt"
			valgt.Parent = row
			corner(valgt, 6)
			local valgtTsc = Instance.new("UITextSizeConstraint")
			valgtTsc.MaxTextSize = 16
			valgtTsc.MinTextSize = 10
			valgtTsc.Parent = valgt
		elseif owned then
			-- Eid, men ikke valgt: en "Velg"-knapp (44px høyt trykk-mål).
			local velg = makeButton(
				row,
				"Velg",
				UDim2.fromOffset(168, BTN_H),
				UDim2.new(1, -176, 0.5, -BTN_H / 2),
				Color3.fromRGB(60, 140, 210)
			)
			velg.Activated:Connect(function()
				doSelect(t.id)
			end)
		else
			-- Ikke eid: vis kjøp-knapp for hver valuta som faktisk har en pris.
			-- Knappene stables loddrett, midtstilt, hver 44px høy (telefon-vennlig).
			local totalH = nBuys * BTN_H + (nBuys - 1) * BTN_GAP
			local yTop = (rowH - totalH) / 2
			for idx, opt in ipairs(buys) do
				local y = yTop + (idx - 1) * (BTN_H + BTN_GAP)
				local b = makeButton(
					row,
					opt.text,
					UDim2.fromOffset(168, BTN_H),
					UDim2.new(1, -176, 0, y),
					opt.color
				)
				b.Activated:Connect(function()
					doBuy(t.id, opt.pay)
				end)
			end
		end
	end
end

--============================  ÅPNE/LUKKE  =======================--
toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		refreshHeader()
		refreshRows()
	end
end)

closeBtn.Activated:Connect(function()
	panel.Visible = false
end)

-- Fyll lista med en gang, så den er klar før første ShopData rekker frem.
refreshHeader()
refreshRows()

--==================  SPEIL LEADERSTATS (valgfritt)  ==============--
-- ShopData er fasit, men leaderstats (Mynter/Edelstener) oppdateres også når
-- man plukker mynter ute i labyrinten. Speil dem så saldoen i toppen holder
-- seg fersk under vanlig spilling. Best-effort, aldri kritisk.
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 15)
	if not ls then return end
	local function hook(valName, field)
		local v = ls:FindFirstChild(valName)
		if not v then return end
		state[field] = v.Value
		v.Changed:Connect(function(nv)
			state[field] = nv
			refreshHeader()
		end)
	end
	hook("Mynter", "coins")
	hook("Edelstener", "gems")
	refreshHeader()
end)

--==================  KOBLE TIL REMOTES (JOBB 1)  =================--
-- Serveren lager mappa "ShopRemotes" i ReplicatedStorage. Vi venter litt på
-- den, men blokkerer ikke resten (JOBB 2 virker uansett). Mangler den, står
-- butikken bare og venter — den krasjer aldri.
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("ShopRemotes", 30)
	if not remotes then
		warn("[Butikk] Fant ikke ShopRemotes — butikken er inaktiv til server-delen er inne.")
		return
	end

	BuyTheme = remotes:WaitForChild("BuyTheme", 10)
	SelectTheme = remotes:WaitForChild("SelectTheme", 10)
	ShopData = remotes:WaitForChild("ShopData", 10)

	if ShopData then
		-- Server sender fasit ved innlogging og etter hver endring.
		ShopData.OnClientEvent:Connect(function(data)
			applyServerState(data)
		end)
	end
end)
