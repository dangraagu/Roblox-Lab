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

	Phone layout: on a phone the list opens as a near-full-screen modal below the
	toggle row rather than as a drawer, it stops above Roblox's touch controls, and
	the ✕ is always visible. Sizes come from Responsive.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Delt perk-liste (ren data: id / name / desc / coinPrice + :byId). MÅ finnes;
-- serveren kloner src/shared inn i ReplicatedStorage før spillerne kobler seg på.
local Perks = require(ReplicatedStorage:WaitForChild("PerkDefs"))

-- Shared sizing rules so this HUD survives a phone. Note the require form: a bare string
-- require like `require("./Responsive")` resolves in the luau CLI but is invalid in Roblox.
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))

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
	insufficient = "Not enough coins",
	owned = "Already owned",
	unknown = "Unknown",
	notforsale = "Not for sale",
	badinput = "Not for sale",
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
-- 8, ikke 9: LeaderboardClient bruker 9, og på telefon dekker oppgraderings-modalen
-- 🏆-knappen dens. Med lik DisplayOrder avgjør Roblox rekkefølgen på PlayerGui-barna, altså
-- laste-rekkefølgen på to uavhengige LocalScripts — da er det tilfeldig om en ugjennomsiktig
-- modal eller en levende knapp havner øverst.
gui.DisplayOrder = 8
gui.Parent = playerGui

-- A UIScale does nothing parented to a ScreenGui, so every element below hangs off this
-- root Frame instead, and the root is what the scale acts on.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- The size this panel was drawn at, and how much room along the top edge the toggle owns.
local PANEL_W, PANEL_H = 380, 560
local TOP_BAR = 66

local layout = Responsive.layout(camera.ViewportSize.X, camera.ViewportSize.Y, UserInputService.TouchEnabled)

-- A control drawn 44 px tall comes out at 44 * scale on screen, which is 26 px on a phone —
-- too small for a thumb, and this file is full of deliberate 44 px touch targets. Where the
-- player is on touch (controlPad is only non-zero then) we grow them by 1/scale so they land
-- at the size they were drawn for. Text size caps get the same treatment, otherwise the
-- label shrinks inside a button that grew. Widths are left alone: they are generous already,
-- and stretching them would squeeze the perk description out of the row.
local function touchSize(designPx)
	if layout.controlPad <= 0 then
		return designPx
	end
	return math.ceil(designPx / layout.scale)
end

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
toggle.Text = "⚡ Upgrades"
toggle.AutoButtonColor = true
toggle.Parent = root
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
-- Størrelse og plassering settes av applyLayout nederst i fila — på desktop en
-- skuff i venstre kant, på telefon en nesten fullskjerms modal. Verdiene her er
-- bare noe å tegne før første kall.
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.AnchorPoint = Vector2.new(0, 0)
panel.Position = UDim2.new(0, Responsive.MARGIN, 0, TOP_BAR)
panel.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
panel.BorderSizePixel = 0
panel.Visible = false
-- A plain Frame does not consume input, so a tap on the panel background would fall through
-- to whatever sits behind it — on a phone that is the toggle button the modal covers.
panel.Active = true
panel.Parent = root
corner(panel, 10)

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
title.Text = "⚡ Upgrades"
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
balance.Text = "🪙 0 coins"
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
scroll.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 2)
pad.PaddingBottom = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 2)
pad.PaddingRight = UDim.new(0, 2)
pad.Parent = scroll

-- The canvas follows the rows. Rows get taller in compact mode, so this has to be measured
-- rather than assumed; the +8 covers the padding above and below the list.
--
-- AbsoluteContentSize is post-UIScale SCREEN px; CanvasSize offsets are pre-scale DESIGN px.
-- Feeding one into the other without dividing the scale back out makes the canvas short by
-- exactly the scale factor, and only on the screens where scale < 1 — so it looks perfect on a
-- 1080p monitor while a phone player simply cannot scroll to the last rows. That cost seven of
-- the seventeen themes and the `minimap` perk their only purchase button.
local function syncCanvas()
	local scale = uiScale.Scale
	if scale <= 0 then scale = 1 end
	scroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(listLayout.AbsoluteContentSize.Y / scale) + 8)
end
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)

--==========================  UI-OPPFRISK  ========================--
local function refreshHeader()
	balance.Text = string.format("🪙 %d coins", state.coins)
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
		setReason(id, "Loading shop…")
		return
	end
	local ok, res = pcall(function()
		return BuyPerk:InvokeServer(id)
	end)
	if not ok or type(res) ~= "table" then
		setReason(id, "Network error")
		return
	end
	applyServerData(res) -- coins + perks fra fasit
	if res.ok == false then
		setReason(id, REASON_NO[res.reason] or "Failed")
	end
end

-- Liten fabrikk for en handlings-knapp (44px høyt trykk-mål, TextScaled + tak).
local function makeButton(parent, text, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(140, touchSize(44))
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
	tsc.MaxTextSize = touchSize(15)
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

	-- Every vertical measurement in a row is grown by 1/scale on touch, so the row comes out
	-- on a phone at the same physical size it has on a desktop.
	local BTN_W = 140
	local TEXT_W = BTN_W + 26

	for i, p in ipairs(Perks.List) do
		local owned = state.perks[p.id] == true
		local affordable = (state.coins or 0) >= (p.coinPrice or 0)

		local row = Instance.new("Frame")
		row.Name = "Rad_" .. tostring(p.id)
		row.Size = UDim2.new(1, -4, 0, touchSize(66))
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
		name.Size = UDim2.new(1, -TEXT_W, 0, touchSize(22))
		name.Position = UDim2.fromOffset(10, touchSize(8))
		name.BackgroundTransparency = 1
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.Text = tostring(p.name or p.id)
		name.Parent = row
		local nameTsc = Instance.new("UITextSizeConstraint")
		nameTsc.MaxTextSize = touchSize(16)
		nameTsc.MinTextSize = 10
		nameTsc.Parent = name

		-- Beskrivelses-linja.
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -TEXT_W, 0, touchSize(18))
		desc.Position = UDim2.fromOffset(10, touchSize(32))
		desc.BackgroundTransparency = 1
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.TextColor3 = Color3.fromRGB(190, 196, 214)
		desc.Font = Enum.Font.Gotham
		desc.TextScaled = true
		desc.Text = tostring(p.desc or "")
		desc.Parent = row
		local descTsc = Instance.new("UITextSizeConstraint")
		descTsc.MaxTextSize = touchSize(13)
		descTsc.MinTextSize = 9
		descTsc.Parent = desc

		-- Grunn-melding (skjult normalt; vises kort når et kjøp feiler).
		local reason = Instance.new("TextLabel")
		reason.Size = UDim2.new(1, -TEXT_W, 0, touchSize(14))
		reason.Position = UDim2.fromOffset(10, touchSize(50))
		reason.BackgroundTransparency = 1
		reason.TextXAlignment = Enum.TextXAlignment.Left
		reason.TextColor3 = Color3.fromRGB(255, 150, 140)
		reason.Font = Enum.Font.GothamMedium
		reason.TextScaled = true
		reason.Text = ""
		reason.Visible = false
		reason.Parent = row
		local reasonTsc = Instance.new("UITextSizeConstraint")
		reasonTsc.MaxTextSize = touchSize(12)
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
			eid.Size = UDim2.fromOffset(BTN_W, touchSize(44))
			eid.AnchorPoint = Vector2.new(1, 0.5)
			eid.Position = UDim2.new(1, -8, 0.5, 0)
			eid.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
			eid.TextColor3 = Color3.fromRGB(15, 35, 20)
			eid.Font = Enum.Font.GothamBold
			eid.TextScaled = true
			eid.Text = "Owned ✓"
			eid.Parent = row
			corner(eid, 6)
			local eidTsc = Instance.new("UITextSizeConstraint")
			eidTsc.MaxTextSize = touchSize(16)
			eidTsc.MinTextSize = 10
			eidTsc.Parent = eid
		else
			-- Ikke eid: kjøp-knapp. Gyllen når du har råd, dempet ellers
			-- (server validerer uansett, så knappen er alltid trykkbar).
			local btnColor = affordable and Color3.fromRGB(198, 156, 44) or Color3.fromRGB(96, 92, 74)
			local buy = makeButton(row, "Buy: " .. tostring(p.coinPrice or 0) .. " coins", btnColor)
			buy.Activated:Connect(function()
				doBuy(p.id)
			end)
		end
	end
end

--==========================  RESPONSIVT OPPSETT  =================--
-- Re-lays the panel for the current viewport. On a desktop or tablet it is a drawer down the
-- left edge, below its toggle; on a phone it is a near-full-screen modal that takes the top
-- edge as well and stops above Roblox's touch controls, so the movement stick and the jump
-- button stay reachable even while the upgrades are open.

-- The phone modal covers the toggle, so hide it while the panel is open: an opaque panel on
-- top of a live button is a tap waiting to land somewhere the player did not intend.
local function syncToggle()
	toggle.Visible = not (panel.Visible and layout.compact)
end

local function applyLayout()
	local v = camera.ViewportSize
	layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale
	-- Grow the root by 1/scale so root * scale lands exactly on the viewport. Skip this and
	-- the HUD shrinks into the top-left corner on a phone while looking fine on desktop.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	local usable = Responsive.usableHeight(v.Y, layout)
	-- Where the panel starts: below the toggle row when it is a drawer, but hard against the
	-- top edge on a phone, where the modal is allowed to cover the toggles (the ✕ is the way
	-- out) and every reclaimed pixel is another visible row.
	local topY = if layout.compact then Responsive.MARGIN else TOP_BAR
	-- Screen px left between that line and the touch-control band at the bottom; that is all
	-- the panel is ever allowed to fill, in either mode.
	local budget = math.max(80, usable + Responsive.MARGIN - topY * layout.scale)
	local roomH = math.floor(budget / layout.scale)

	local closeW = touchSize(44)
	local titleH, balanceH = touchSize(28), touchSize(22)
	closeBtn.Size = UDim2.fromOffset(closeW, closeW)
	closeBtn.TextSize = touchSize(24)
	title.Size = UDim2.new(1, -(closeW + 30), 0, titleH)
	title.Position = UDim2.fromOffset(14, 10)
	titleTsc.MaxTextSize = touchSize(20)
	balance.Size = UDim2.new(1, -28, 0, balanceH)
	balance.Position = UDim2.fromOffset(14, 12 + titleH)
	balanceTsc.MaxTextSize = touchSize(17)

	local headerH = 20 + titleH + balanceH
	scroll.Position = UDim2.fromOffset(8, headerH)
	scroll.Size = UDim2.new(1, -16, 1, -(headerH + 6))

	if layout.compact then
		-- Phone: a drawer wide enough to read the descriptions would cover the controls, so
		-- the upgrades take the screen instead and the ✕ is the way out.
		local panelH = Responsive.fitHeight(math.max(headerH + 120, roomH), usable, layout)
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.new(0.5, 0, 0, topY)
		panel.Size = UDim2.new(0.94, 0, 0, panelH)
	else
		local panelW = Responsive.sideWidth(PANEL_W, v.X, layout)
		local panelH = Responsive.fitHeight(math.min(PANEL_H, roomH), usable, layout)
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UDim2.new(0, Responsive.MARGIN, 0, topY)
		panel.Size = UDim2.fromOffset(panelW, panelH)
	end

	syncToggle()

	-- Row heights and label sizes depend on compact, so an open list has to be redrawn.
	if panel.Visible then
		refreshRows()
	end
end

--============================  ÅPNE/LUKKE  =======================--
-- The theme shop is the same kind of full-screen modal on a phone, and two of them at once
-- would simply stack. A shared attribute on PlayerGui lets whichever opened last ask the
-- other one to close; on bigger screens they sit on opposite edges and both may stay open.
local MODAL_ATTR = "MobileModalOpen"
local MODAL_ID = "perks"

local function setPanelOpen(open)
	panel.Visible = open
	syncToggle()
	if open then
		if layout.compact then
			playerGui:SetAttribute(MODAL_ATTR, MODAL_ID)
		end
		refreshHeader()
		refreshRows()
	elseif playerGui:GetAttribute(MODAL_ATTR) == MODAL_ID then
		playerGui:SetAttribute(MODAL_ATTR, nil)
	end
end

toggle.Activated:Connect(function()
	setPanelOpen(not panel.Visible)
end)

closeBtn.Activated:Connect(function()
	setPanelOpen(false)
end)

playerGui:GetAttributeChangedSignal(MODAL_ATTR):Connect(function()
	if panel.Visible and playerGui:GetAttribute(MODAL_ATTR) ~= MODAL_ID then
		setPanelOpen(false)
	end
end)

-- Fyll lista med en gang, så den er klar før første PerkData rekker frem.
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
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
