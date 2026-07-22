--[[==================================================================
	LABYRINT-SPILL  -  OPPGRADERINGS-BUTIKK / PERKS (klient)
	Laget for Marius & onkel :)

	Dette er et LOKALT skript (Rojo legger src/client i StarterPlayerScripts).
	Det tegner en liten butikk der du kjøper PERKS (varige oppgraderinger) med
	Mynter: lengre fakkel, ekstra liv, fartsboost og minikart. Perks eies for
	alltid når de først er kjøpt.

	Serveren er sjefen: klienten spør pent via en Remote, serveren validerer,
	trekker mynter og svarer med fasit ({ ok, reason, coins, perks }). Vi TEGNER
	bare det serveren forteller oss. PerkData-eventet er fasit for saldo + eierskap.

	Ingen bilder/lyder/assets — bare Frame / TextLabel / TextButton / UICorner /
	UIStroke / UIListLayout / ScrollingFrame / UITextSizeConstraint / UISizeConstraint.

	Mobil-vennlig: knappen ligger ØVERST TIL VENSTRE (tema-butikken er øverst til
	høyre, nivå-HUD-en øverst i midten), godt klar av mobil-kontrollene
	(styrepinne nede-venstre, hopp nede-høyre). Alle trykk-mål er >= 44px, all
	tekst er TextScaled med tak/gulv så ingenting flyter over på en liten telefon,
	og panelet ruller.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Delt perk-liste (ren data: id / name / desc / coinPrice + :byId). MÅ finnes;
-- serveren kloner src/shared inn i ReplicatedStorage før spillerne kobler seg på.
local Perks = require(ReplicatedStorage:WaitForChild("PerkDefs"))

--============================  STATE  ============================--
-- Fasit kommer fra serveren via PerkData-eventet. Vi starter forsiktig: ingen
-- mynter, ingen perks eid.
local state = {
	coins = 0,
	perks = {}, -- { [id] = true }
}

-- Remote fylles ut når vi finner den (kan mangle en stund ved oppstart, eller
-- helt hvis server-delen ikke er lagt inn ennå). Alltid nil-sjekket.
local BuyPerk = nil

-- Norske forklaringer på hvorfor et kjøp ikke gikk (server-grunner).
local REASON_NO = {
	insufficient = "Ikke nok mynter",
	owned = "Eid allerede",
	unknown = "Ukjent",
	notforsale = "Ikke til salgs",
	badinput = "Ikke til salgs",
}

-- Bare én grunn-melding vises av gangen, ved raden den hører til. Overlever
-- ombygging av lista fordi refreshRows leser denne.
local activeReason = nil -- { id = "...", text = "..." }
local reasonToken = 0

--==========================  HJELPERE  ===========================--
local function corner(inst, r)
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(0, r or 6)
	uc.Parent = inst
	return uc
end

--============================  UI-OPPSETT  =======================--
local playerGui = player:WaitForChild("PlayerGui")

-- Aldri to like GUI-er: hvis en henger igjen (f.eks. ResetOnSpawn=false + en
-- sjelden dobbelt-kjøring), gjenbruk ikke — vi hopper heller helt av.
if playerGui:FindFirstChild("Oppgraderinger") then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "Oppgraderinger"
gui.ResetOnSpawn = false -- overlever respawn; ingen dobbel-GUI
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9
gui.Parent = playerGui

-- ---- Knapp øverst til VENSTRE som åpner/lukker butikken ----
-- Stort trykk-mål (48px høyt) for telefon. Klar av mobil-kontrollene nede.
local toggle = Instance.new("TextButton")
toggle.Name = "PerkKnapp"
toggle.Size = UDim2.fromOffset(180, 48)
toggle.AnchorPoint = Vector2.new(0, 0)
toggle.Position = UDim2.new(0, 12, 0, 12)
toggle.BackgroundColor3 = Color3.fromRGB(78, 58, 96)
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Font = Enum.Font.GothamBold
toggle.TextScaled = true
toggle.Text = "⚡ Oppgraderinger"
toggle.AutoButtonColor = true
toggle.Parent = gui
corner(toggle, 8)
local toggleTsc = Instance.new("UITextSizeConstraint")
toggleTsc.MaxTextSize = 19
toggleTsc.MinTextSize = 12
toggleTsc.Parent = toggle
local togglePad = Instance.new("UIPadding")
togglePad.PaddingLeft = UDim.new(0, 10)
togglePad.PaddingRight = UDim.new(0, 10)
togglePad.PaddingTop = UDim.new(0, 6)
togglePad.PaddingBottom = UDim.new(0, 6)
togglePad.Parent = toggle

-- ---- Selve panelet (skjult til man trykker) ----
-- Skala-basert størrelse (andel av skjermen) med tak/gulv nedenfor. På en liten
-- telefon blir panelet <= 80% av skjermhøyden, så radene MÅ kunne rulles.
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0.9, 0, 0.8, 0)
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.new(0, 12, 0, 66)
panel.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
corner(panel, 10)
-- Tak/gulv: aldri enormt på desktop, aldri klemt på en bitteliten skjerm.
local panelSize = Instance.new("UISizeConstraint")
panelSize.MaxSize = Vector2.new(380, 560)
panelSize.MinSize = Vector2.new(280, 300)
panelSize.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(96, 78, 116)
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- ---- Topptekst: tittel, saldo, lukkeknapp ----
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -66, 0, 28)
title.Position = UDim2.fromOffset(14, 10)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.Text = "⚡ Oppgraderinger"
title.Parent = panel
local titleTsc = Instance.new("UITextSizeConstraint")
titleTsc.MaxTextSize = 20
titleTsc.MinTextSize = 12
titleTsc.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(44, 44) -- 44px = komfortabelt trykk-mål på telefon
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
balance.Position = UDim2.fromOffset(14, 42)
balance.BackgroundTransparency = 1
balance.TextXAlignment = Enum.TextXAlignment.Left
balance.TextColor3 = Color3.fromRGB(235, 220, 150)
balance.Font = Enum.Font.GothamMedium
balance.TextScaled = true
balance.Text = "🪙 0 mynter"
balance.Parent = panel
local balanceTsc = Instance.new("UITextSizeConstraint")
balanceTsc.MaxTextSize = 17
balanceTsc.MinTextSize = 11
balanceTsc.Parent = balance

-- ---- Listen med perks (kan rulles) ----
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Liste"
scroll.Size = UDim2.new(1, -16, 1, -78)
scroll.Position = UDim2.fromOffset(8, 72)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 10 -- litt bredere så det er lett å ta tak i med finger
scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 128, 150)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y -- panelet ruller på telefon
scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 2)
pad.PaddingBottom = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 2)
pad.PaddingRight = UDim.new(0, 2)
pad.Parent = scroll

--==========================  UI-OPPFRISK  ========================--
local function refreshHeader()
	balance.Text = string.format("🪙 %d mynter", state.coins)
end

local refreshRows -- fylles ut like nedenfor

-- Vis en kort grunn-melding ved en bestemt rad, som forsvinner av seg selv.
local function setReason(id, text)
	reasonToken += 1
	local mine = reasonToken
	activeReason = { id = id, text = text }
	if refreshRows then refreshRows() end
	task.delay(2.5, function()
		if mine == reasonToken then
			activeReason = nil
			if refreshRows then refreshRows() end
		end
	end)
end

-- Ta imot fasit fra serveren (fra PerkData ELLER fra svaret på et kjøp).
local function applyServerData(data)
	if type(data) ~= "table" then return end
	if type(data.coins) == "number" then state.coins = data.coins end
	if type(data.perks) == "table" then state.perks = data.perks end
	refreshHeader()
	if refreshRows then refreshRows() end
end

-- Kjøp et perk. pcall rundt nettverkskallet; oppdater fra fasiten i svaret.
local function doBuy(id)
	if not BuyPerk then
		setReason(id, "Butikken laster ...")
		return
	end
	local ok, res = pcall(function()
		return BuyPerk:InvokeServer(id)
	end)
	if not ok or type(res) ~= "table" then
		setReason(id, "Nettverksfeil")
		return
	end
	applyServerData(res) -- coins + perks fra fasit
	if res.ok == false then
		setReason(id, REASON_NO[res.reason] or "Gikk ikke")
	end
end

-- Liten fabrikk for en handlings-knapp (44px høyt trykk-mål, TextScaled + tak).
local function makeButton(parent, text, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(140, 44)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -8, 0.5, 0)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 6)
	local tsc = Instance.new("UITextSizeConstraint")
	tsc.MaxTextSize = 15
	tsc.MinTextSize = 9
	tsc.Parent = b
	local bp = Instance.new("UIPadding")
	bp.PaddingLeft = UDim.new(0, 6)
	bp.PaddingRight = UDim.new(0, 6)
	bp.Parent = b
	return b
end

-- Bygg hele lista på nytt fra staten. Billig (få perks), så vi gjør det enkelt.
function refreshRows()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end

	for i, p in ipairs(Perks.List) do
		local owned = state.perks[p.id] == true
		local affordable = (state.coins or 0) >= (p.coinPrice or 0)

		local row = Instance.new("Frame")
		row.Name = "Rad_" .. tostring(p.id)
		row.Size = UDim2.new(1, -4, 0, 66)
		row.BackgroundColor3 = owned and Color3.fromRGB(40, 58, 46) or Color3.fromRGB(42, 46, 60)
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = scroll
		corner(row, 6)
		if owned then
			local rs = Instance.new("UIStroke")
			rs.Color = Color3.fromRGB(60, 200, 90)
			rs.Thickness = 1
			rs.Parent = row
		end

		-- Navn (fet). Krymper for å få plass; flyter aldri over.
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -166, 0, 22)
		name.Position = UDim2.fromOffset(10, 8)
		name.BackgroundTransparency = 1
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.Text = tostring(p.name or p.id)
		name.Parent = row
		local nameTsc = Instance.new("UITextSizeConstraint")
		nameTsc.MaxTextSize = 16
		nameTsc.MinTextSize = 10
		nameTsc.Parent = name

		-- Beskrivelses-linja.
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -166, 0, 18)
		desc.Position = UDim2.fromOffset(10, 32)
		desc.BackgroundTransparency = 1
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.TextColor3 = Color3.fromRGB(190, 196, 214)
		desc.Font = Enum.Font.Gotham
		desc.TextScaled = true
		desc.Text = tostring(p.desc or "")
		desc.Parent = row
		local descTsc = Instance.new("UITextSizeConstraint")
		descTsc.MaxTextSize = 13
		descTsc.MinTextSize = 9
		descTsc.Parent = desc

		-- Grunn-melding (skjult normalt; vises kort når et kjøp feiler).
		local reason = Instance.new("TextLabel")
		reason.Size = UDim2.new(1, -166, 0, 14)
		reason.Position = UDim2.fromOffset(10, 50)
		reason.BackgroundTransparency = 1
		reason.TextXAlignment = Enum.TextXAlignment.Left
		reason.TextColor3 = Color3.fromRGB(255, 150, 140)
		reason.Font = Enum.Font.GothamMedium
		reason.TextScaled = true
		reason.Text = ""
		reason.Visible = false
		reason.Parent = row
		local reasonTsc = Instance.new("UITextSizeConstraint")
		reasonTsc.MaxTextSize = 12
		reasonTsc.MinTextSize = 8
		reasonTsc.Parent = reason
		if activeReason and activeReason.id == p.id then
			reason.Text = activeReason.text
			reason.Visible = true
		end

		-- Handlings-området til høyre.
		if owned then
			-- Eid: et fremhevet "Eid ✓"-merke (grønt).
			local eid = Instance.new("TextLabel")
			eid.Size = UDim2.fromOffset(140, 44)
			eid.AnchorPoint = Vector2.new(1, 0.5)
			eid.Position = UDim2.new(1, -8, 0.5, 0)
			eid.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
			eid.TextColor3 = Color3.fromRGB(15, 35, 20)
			eid.Font = Enum.Font.GothamBold
			eid.TextScaled = true
			eid.Text = "Eid ✓"
			eid.Parent = row
			corner(eid, 6)
			local eidTsc = Instance.new("UITextSizeConstraint")
			eidTsc.MaxTextSize = 16
			eidTsc.MinTextSize = 10
			eidTsc.Parent = eid
		else
			-- Ikke eid: kjøp-knapp. Gyllen når du har råd, dempet ellers
			-- (server validerer uansett, så knappen er alltid trykkbar).
			local btnColor = affordable and Color3.fromRGB(198, 156, 44) or Color3.fromRGB(96, 92, 74)
			local buy = makeButton(row, "Kjøp: " .. tostring(p.coinPrice or 0) .. " mynter", btnColor)
			buy.Activated:Connect(function()
				doBuy(p.id)
			end)
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

-- Fyll lista med en gang, så den er klar før første PerkData rekker frem.
refreshHeader()
refreshRows()

--==================  KOBLE TIL REMOTES  =========================--
-- Serveren lager mappa "PerkRemotes" i ReplicatedStorage. Vi venter litt på den,
-- men blokkerer ikke resten. Mangler den, står butikken bare og venter — den
-- krasjer aldri.
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("PerkRemotes", 30)
	if not remotes then
		warn("[Perks] Fant ikke PerkRemotes — oppgraderinger er inaktive til server-delen er inne.")
		return
	end

	BuyPerk = remotes:WaitForChild("BuyPerk", 10)

	local PerkData = remotes:WaitForChild("PerkData", 10)
	if PerkData then
		-- Server sender fasit ({ coins, perks }) ved innlogging og etter hver endring.
		PerkData.OnClientEvent:Connect(function(data)
			applyServerData(data)
		end)
	end
end)
