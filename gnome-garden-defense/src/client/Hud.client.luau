-- GNOME GARDEN DEFENSE: the HUD (client, display + requests only). Lives in StarterPlayerScripts.
--
-- Phone first (docs/new-game-checklist.md §2b, docs/mobile-ui-brief.md): one root Frame owns the UIScale and is
-- sized 1/scale; it re-lays-out on ViewportSize and TouchEnabled; every tappable thing is >= 44 SCREEN px on a
-- touch screen; nothing tappable sits in the bottom-left (thumbstick) or bottom-right (jump) bands.
--   * top bar: seeds, carrots, wave + season, and the next wave (build) or the boss's health (boss wave);
--   * READY: right edge, vertically centred;
--   * the gnome sheet: bottom centre, above Roblox's touch controls; it opens when you tap a pad (plant) or a
--     gnome (upgrade / sell). Greyed while a hazard has you dazed;
--   * the result panel (season won: NEXT SEASON; carrots lost: TRY AGAIN), toasts, first-minute hints.
-- The band chip, PAUSE and the hazard warning are Garden.client's row directly under the top bar.
-- The server owns every number shown here (the garden's attributes); this script only ASKS over the remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local Sim = require(ReplicatedStorage:WaitForChild("Garden")) -- the pure rules: only Sim.suggestKind is used here

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("GardenRemotes")
local PlantEvent = remotes:WaitForChild("Plant")
local UpgradeEvent = remotes:WaitForChild("Upgrade")
local SellEvent = remotes:WaitForChild("Sell")
local ReadyEvent = remotes:WaitForChild("Ready")
local RestartEvent = remotes:WaitForChild("Restart")
local NextSeasonEvent = remotes:WaitForChild("NextSeason")
local ToastEvent = remotes:WaitForChild("Toast")
local FanfareEvent = remotes:WaitForChild("Fanfare")

local HC = Config.Hud
local MARGIN, GAP = Responsive.MARGIN, HC.Gap
local KINDS = {}
for kind, def in Config.Gnomes do table.insert(KINDS, { kind = kind, def = def }) end
table.sort(KINDS, function(a, b) return a.def.order < b.def.order end)

--============================================================================ local state shared with Garden.client
local playerGui = player:WaitForChild("PlayerGui")
local function clientState(): Folder
	local f = playerGui:FindFirstChild("GardenClientState")
	if f == nil then
		f = Instance.new("Folder")
		f.Name = "GardenClientState"
		f.Parent = playerGui
	end
	return f :: Folder
end
local state = clientState()

--============================================================================ widgets
local gui = Instance.new("ScreenGui")
gui.Name = "GardenHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 1
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end
local function maxText(inst: Instance, n: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = n
	c.Parent = inst
end
local function textLabel(name: string, parent: Instance, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = color or Color3.fromRGB(255, 250, 235)
	l.TextScaled = true
	l.Text = ""
	l.Parent = parent
	maxText(l, 22)
	return l
end
local function button(name: string, parent: Instance, color: Color3, text: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	maxText(b, 22)
	return b
end

-- top bar
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.BackgroundColor3 = Color3.fromRGB(34, 52, 30)
topBar.BackgroundTransparency = 0.2
topBar.BorderSizePixel = 0
topBar.Parent = root
corner(topBar, 12)
FxClient.theme(topBar)
local seedsLabel = textLabel("SeedsLabel", topBar, Color3.fromRGB(190, 255, 150))
local carrotsLabel = textLabel("CarrotsLabel", topBar, Color3.fromRGB(255, 190, 120))
local waveLabel = textLabel("WaveLabel", topBar)
local infoLabel = textLabel("InfoLabel", topBar, Color3.fromRGB(235, 230, 210))
local bossBar = Instance.new("Frame")
bossBar.Name = "BossBar"
bossBar.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
bossBar.BorderSizePixel = 0
bossBar.Visible = false
bossBar.Parent = topBar
corner(bossBar, 6)
local bossFill = Instance.new("Frame")
bossFill.Name = "Fill"
bossFill.BackgroundColor3 = Color3.fromRGB(230, 60, 60)
bossFill.BorderSizePixel = 0
bossFill.Size = UDim2.fromScale(1, 1)
bossFill.Parent = bossBar
corner(bossFill, 6)
local bossName = textLabel("BossName", bossBar)
bossName.Size = UDim2.fromScale(1, 1)
bossName.ZIndex = 3

-- READY
local readyBtn = button("ReadyButton", root, Color3.fromRGB(70, 170, 70), "READY ▶")

-- the gnome sheet
local sheet = Instance.new("Frame")
sheet.Name = "GnomeSheet"
sheet.BackgroundColor3 = Color3.fromRGB(40, 34, 28)
sheet.BackgroundTransparency = 0.12
sheet.BorderSizePixel = 0
sheet.Visible = false
sheet.Parent = root
corner(sheet, 12)
local sheetTitle = textLabel("SheetTitle", sheet)
local slots: { TextButton } = {}
for i = 1, 4 do
	slots[i] = button("Slot" .. i, sheet, Color3.fromRGB(90, 140, 70), "")
end
local closeBtn = button("CloseButton", sheet, Color3.fromRGB(110, 70, 60), "✕")

-- the result panel
local result = Instance.new("Frame")
result.Name = "ResultPanel"
result.BackgroundColor3 = Color3.fromRGB(28, 26, 40)
result.BackgroundTransparency = 0.08
result.BorderSizePixel = 0
result.Visible = false
result.Parent = root
corner(result, 14)
local resultTitle = textLabel("ResultTitle", result, Color3.fromRGB(255, 220, 120))
maxText(resultTitle, 30)
local resultSub = textLabel("ResultSub", result)
local resultBtn = button("ResultButton", result, Color3.fromRGB(70, 150, 220), "")

-- toast + hint (labels, not panels)
local toastLabel = textLabel("Toast", root)
toastLabel.BackgroundTransparency = 0.25
toastLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
toastLabel.Visible = false
corner(toastLabel, 10)
local hintLabel = textLabel("Hint", root, Color3.fromRGB(255, 255, 200))
hintLabel.TextStrokeTransparency = 0.4
hintLabel.Visible = false

--============================================================================ layout
local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then return designPx end
	local wanted = math.max(designPx, HC.MinTap)
	local n = math.ceil(wanted / layout.scale)
	if n * layout.scale <= wanted then n += 1 end
	return n
end
local rootW, rootH = Responsive.REF_X, Responsive.REF_Y
local resultMode = false
-- The part of the screen the garden view may use, in viewport px (View.client frames the garden in it): under
-- Garden.client's row (chip + PAUSE), above Roblox's touch controls, and above the gnome sheet while it is open.
local view = { w = Responsive.REF_X, h = Responsive.REF_Y, inset = 0, top = 0, band = Responsive.REF_Y, sheetTop = Responsive.REF_Y }
local function publishView()
	local bottom = if sheet.Visible then math.min(view.band, view.sheetTop) else view.band
	for name, value in { ViewW = view.w, ViewH = view.h, Inset = view.inset, WorldTop = view.top, WorldBand = view.band, WorldBottom = bottom } do
		if state:GetAttribute(name) ~= value then state:SetAttribute(name, value) end
	end
end
-- A short phone (a 568x320 landscape) has no room between the rows under the top bar and Roblox's touch
-- controls: then READY and the sheet move into the bottom band's MIDDLE (between the thumbstick and the jump
-- button), and READY steps aside while the sheet is open.
local tight = false

local function applyLayout()
	local v = camera.ViewportSize
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, topLeft = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and topLeft ~= nil then topLeft.Y else 0
	end
	local vyDraw = math.max(1, vy - inset)
	layout = Responsive.layout(vx, vyDraw, UserInputService.TouchEnabled, vy)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
	rootW = vx / layout.scale
	rootH = vyDraw / layout.scale
	local controlPad = layout.controlPad / layout.scale -- design px owned by Roblox's touch controls

	-- top bar across the top
	local topH = if layout.compact then HC.TopHCompact else HC.TopH
	topBar.Position = UDim2.fromOffset(MARGIN, MARGIN)
	topBar.Size = UDim2.fromOffset(rootW - 2 * MARGIN, topH)
	seedsLabel.Position = UDim2.fromScale(0.02, 0.1)
	seedsLabel.Size = UDim2.fromScale(0.15, 0.8)
	carrotsLabel.Position = UDim2.fromScale(0.18, 0.1)
	carrotsLabel.Size = UDim2.fromScale(0.13, 0.8)
	waveLabel.Position = UDim2.fromScale(0.32, 0.1)
	waveLabel.Size = UDim2.fromScale(0.3, 0.8)
	infoLabel.Position = UDim2.fromScale(0.63, 0.1)
	infoLabel.Size = UDim2.fromScale(0.35, 0.8)
	bossBar.Position = UDim2.fromScale(0.63, 0.2)
	bossBar.Size = UDim2.fromScale(0.35, 0.6)

	-- Garden.client's row (chip + PAUSE) and its warning sit under the top bar: the space below them is ours
	local rowTop = MARGIN + topH + GAP
	local rowBottom = rowTop + touchSize(HC.RowH) + GAP + HC.WarnH + GAP

	local bandTop = rootH - MARGIN - controlPad -- where Roblox's thumbstick and jump button begin
	-- the bottom band's middle: x between the thumbstick (left 35%) and the jump button (right 25%), with a margin
	local midL, midR = rootW * HC.ThumbShare + MARGIN, rootW * (1 - HC.JumpShare) - MARGIN

	-- READY: right edge, vertically centred between the rows and the touch band
	local readyW, readyH = touchSize(HC.ReadyW), touchSize(HC.ReadyH)
	readyBtn.Size = UDim2.fromOffset(readyW, readyH)
	tight = bandTop - rowBottom < readyH
	if tight then
		local w = math.min(readyW, midR - midL)
		readyBtn.Size = UDim2.fromOffset(w, readyH)
		readyBtn.Position = UDim2.fromOffset((midL + midR - w) / 2, rootH - MARGIN - readyH)
	else
		local y = math.clamp((rootH - readyH) / 2, rowBottom, bandTop - readyH)
		readyBtn.Position = UDim2.fromOffset(rootW - MARGIN - readyW, y)
	end

	-- the sheet: a title row with the close button, then four buttons. Centred above the touch band when it
	-- fits there; otherwise in the band's middle, never under the thumbstick or the jump button.
	local btnH = touchSize(HC.SheetBtnH)
	local closeW = touchSize(HC.CloseW)
	local titleH = touchSize(HC.SheetTitleH)
	local sheetH = titleH + btnH + 3 * GAP
	local above = bandTop - rowBottom >= sheetH
	local maxW = if above then rootW - 2 * MARGIN - (if tight then 0 else readyW + GAP) else midR - midL
	local btnW = math.min(HC.SheetBtnW, math.floor((maxW - 5 * GAP) / 4))
	btnW = math.max(btnW, touchSize(44))
	local sheetW = 4 * btnW + 5 * GAP
	sheet.Size = UDim2.fromOffset(sheetW, sheetH)
	if above then
		local x = math.max(MARGIN, (rootW - sheetW) / 2 - (if tight then 0 else (readyW + GAP) / 2))
		sheet.Position = UDim2.fromOffset(x, bandTop - sheetH)
	else
		sheet.Position = UDim2.fromOffset((midL + midR - sheetW) / 2, rootH - MARGIN - sheetH)
	end
	sheetTitle.Position = UDim2.fromOffset(GAP, GAP)
	sheetTitle.Size = UDim2.fromOffset(sheetW - 3 * GAP - closeW, titleH)
	closeBtn.Position = UDim2.fromOffset(sheetW - GAP - closeW, GAP)
	closeBtn.Size = UDim2.fromOffset(closeW, titleH)
	for i, b in slots do
		b.Position = UDim2.fromOffset(GAP + (i - 1) * (btnW + GAP), titleH + 2 * GAP)
		b.Size = UDim2.fromOffset(btnW, btnH)
	end
	local sheetBottom = bandTop

	-- the result panel: centred between the row and the touch band
	local regionTop, regionBottom = rowBottom, rootH - MARGIN - controlPad
	local resBtnH = touchSize(56)
	local resH = math.min(HC.ResultH, math.max(resBtnH + 70, regionBottom - regionTop))
	local resW = math.min(HC.ResultW, rootW - 2 * MARGIN)
	result.Size = UDim2.fromOffset(resW, resH)
	result.Position = UDim2.fromOffset((rootW - resW) / 2, regionTop + math.max(0, (regionBottom - regionTop - resH) / 2))
	resultTitle.Position = UDim2.fromOffset(16, 8)
	resultTitle.Size = UDim2.fromOffset(resW - 32, math.floor((resH - resBtnH - 24) * 0.55))
	resultSub.Position = UDim2.fromOffset(16, 8 + math.floor((resH - resBtnH - 24) * 0.55))
	resultSub.Size = UDim2.fromOffset(resW - 32, math.floor((resH - resBtnH - 24) * 0.45))
	resultBtn.Size = UDim2.fromOffset(math.min(260, resW - 32), resBtnH)
	resultBtn.Position = UDim2.fromOffset((resW - math.min(260, resW - 32)) / 2, resH - resBtnH - 10)

	toastLabel.Size = UDim2.fromOffset(math.min(560, rootW - 2 * MARGIN), 34)
	toastLabel.Position = UDim2.fromOffset((rootW - math.min(560, rootW - 2 * MARGIN)) / 2, rowBottom + 4)
	hintLabel.Size = UDim2.fromOffset(math.min(620, rootW - 2 * MARGIN), 30)
	hintLabel.Position = UDim2.fromOffset((rootW - math.min(620, rootW - 2 * MARGIN)) / 2, math.max(rowBottom + 44, sheetBottom - sheetH - 40))

	view.w, view.h, view.inset = vx, vy, inset
	view.top = inset + (rowTop + touchSize(HC.RowH) + GAP) * layout.scale
	view.band = inset + bandTop * layout.scale
	view.sheetTop = inset + sheet.Position.Y.Offset * layout.scale
	publishView()
end
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

--============================================================================ the garden
local garden: Instance? = nil
local selected: { kind: string, pad: number }? = nil
local padConns: { RBXScriptConnection } = {}
local boundAttempt = -1
local refresh -- forward

local function attr(name: string): any
	return garden and garden:GetAttribute(name)
end

local toastToken = 0
local function toast(text: string, seconds: number?)
	toastToken += 1
	local mine = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(seconds or 3, function()
		if toastToken == mine then toastLabel.Visible = false end
	end)
end

local function dazedLeft(): number
	local untilT = state:GetAttribute("DazedUntil")
	if type(untilT) ~= "number" then return 0 end
	return math.max(0, untilT - tick())
end

local function gnomeOn(pad: number): Instance?
	local bed = garden and garden:FindFirstChild("Bed")
	local gnomes = bed and bed:FindFirstChild("Gnomes")
	return gnomes and gnomes:FindFirstChild("Gnome_" .. pad)
end

local function select(kind: string?, pad: number?)
	if kind == nil then
		selected = nil
	else
		selected = { kind = kind :: string, pad = pad :: number }
	end
	state:SetAttribute("SelectedPad", if pad then pad else 0)
	refresh()
end

local function onPadClicked(padId: number)
	if gnomeOn(padId) then select("gnome", padId) else select("pad", padId) end
end

-- A tap on the garden is picked by View.client (the camera's owner: GardenCam.pickRay on the bed's PathCells,
-- so no pad Instance has to exist yet), which names the pad here through GardenClientState.PickPad/PickSeq. The
-- HUD only follows the gnomes, to know whether a picked pad holds one. It (re)binds when the bed or its Gnomes
-- folder arrives, whenever that is: pad taps bound once per attempt never worked for a bed that streamed in
-- after the attempt began (REVIEW-1).
local function bindBed()
	for _, c in padConns do c:Disconnect() end
	table.clear(padConns)
	local bed = garden and garden:FindFirstChild("Bed")
	if not bed then return end
	local function hookGnomes(gnomes: Instance)
		table.insert(padConns, gnomes.ChildAdded:Connect(function() refresh() end))
		table.insert(padConns, gnomes.ChildRemoved:Connect(function() refresh() end))
	end
	local gnomes = bed:FindFirstChild("Gnomes")
	if gnomes then
		hookGnomes(gnomes)
	else
		table.insert(padConns, bed.ChildAdded:Connect(function(c)
			if c.Name == "Gnomes" then
				hookGnomes(c)
				refresh()
			end
		end))
	end
end

local function findGarden(): Instance?
	local gardens = workspace:FindFirstChild("Gardens")
	if not gardens then return nil end
	for _, g in gardens:GetChildren() do
		if g:GetAttribute("Owner") == player.UserId then return g end
	end
	return nil
end

--============================================================================ refresh: attributes -> widgets
local PHASE_ACTIVE = { reveal = true, build = true, wave = true, held = true }

refresh = function()
	if garden == nil or garden.Parent == nil then
		garden = findGarden()
		boundAttempt = -1
		if garden then
			garden.AttributeChanged:Connect(function() refresh() end)
			garden.ChildAdded:Connect(function(c)
				if c.Name == "Bed" then
					bindBed()
					refresh()
				end
			end)
		end
	end
	if garden == nil then
		waveLabel.Text = "Preparing your garden..."
		readyBtn.Visible = false
		sheet.Visible = false
		result.Visible = false
		return
	end
	local attempt = attr("Attempt") or 0
	if attempt ~= boundAttempt then
		boundAttempt = attempt
		selected = nil
		bindBed()
	end
	local phase = attr("Phase") or "reveal"
	local seeds = attr("Seeds") or 0
	local chapter = attr("Chapter") or 1
	local endless = attr("Endless") == true
	seedsLabel.Text = "🌱 " .. tostring(seeds)
	carrotsLabel.Text = "🥕 " .. tostring(attr("Carrots") or 0)
	local season = attr("Season") or ""
	if endless then
		waveLabel.Text = string.format("Wave %d · %s", attr("Wave") or 0, season)
	else
		waveLabel.Text = string.format("Wave %d/%d · %s", attr("WaveInChapter") or 1, Config.WavesPerChapter, season)
	end
	local bossFrac = attr("BossFrac") or -1
	if phase == "wave" and bossFrac >= 0 then
		bossBar.Visible = true
		infoLabel.Visible = false
		bossFill.Size = UDim2.fromScale(bossFrac, 1)
		bossName.Text = string.format("BOSS %d%%", math.floor(bossFrac * 100 + 0.5))
	else
		bossBar.Visible = false
		infoLabel.Visible = true
		if phase == "build" then
			infoLabel.Text = string.format("Next in %ds: %s", attr("BuildLeft") or 0, attr("Preview") or "")
		elseif phase == "held" then
			infoLabel.Text = "Waiting for you: press READY"
		elseif phase == "wave" then
			infoLabel.Text = "Bugs incoming!"
		else
			infoLabel.Text = "Next: " .. tostring(attr("Preview") or "")
		end
	end

	-- READY (on a short phone it shares the bottom band's middle with the sheet, and steps aside for it)
	readyBtn.Visible = (phase == "reveal" or phase == "build" or phase == "held")
		and not (tight and selected ~= nil and PHASE_ACTIVE[phase] == true)
	readyBtn.Text = if phase == "build" then string.format("READY (%d)", attr("BuildLeft") or 0) else "READY ▶"

	-- the result panel
	resultMode = phase == "won" or phase == "lost"
	result.Visible = resultMode

	-- the sheet
	local showSheet = selected ~= nil and PHASE_ACTIVE[phase] == true and not resultMode
	sheet.Visible = showSheet
	publishView()
	if showSheet then
		local sel = selected :: { kind: string, pad: number }
		local dazed = dazedLeft() > 0
		local g = gnomeOn(sel.pad)
		if sel.kind == "pad" and g then
			sel.kind = "gnome"
		end
		if sel.kind == "pad" then
			sheetTitle.Text = if dazed then "Seeing stars..." else "Plant a gnome"
			local unlocked = {}
			for c = 1, math.min(chapter, #Config.Chapters) do
				for _, k in Config.Chapters[c].unlock do unlocked[k] = true end
			end
			-- the gnome the game suggests is starred; the glowing pads are the best free ones for it (Garden.client).
			-- The pacing model's normal player plants exactly that (REVIEW-2)
			local have = {}
			local bed = garden and garden:FindFirstChild("Bed")
			local gnomesF = bed and bed:FindFirstChild("Gnomes")
			for _, m in (if gnomesF then gnomesF:GetChildren() else {}) do
				local k = m:GetAttribute("Kind")
				if type(k) == "string" then have[k] = (have[k] or 0) + 1 end
			end
			local starred = Sim.suggestKind(Config, chapter, have)
			for i, e in KINDS do
				local b = slots[i]
				b.Visible = true
				local cost = e.def.levels[1].cost
				if unlocked[e.kind] then
					b.Text = string.format("%s%s\n%d", if e.kind == starred then "★ " else "", e.def.name, cost)
					b.BackgroundColor3 = if dazed or seeds < cost then Color3.fromRGB(90, 90, 90) else Color3.fromRGB(90, 150, 70)
				else
					local season2 = "later"
					for c, ch in Config.Chapters do
						for _, k in ch.unlock do
							if k == e.kind then season2 = Config.Chapters[c].name end
						end
					end
					b.Text = string.format("%s\n🔒 %s", e.def.name, season2)
					b.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
				end
			end
		else
			local kind = g and g:GetAttribute("Kind") or "pebble"
			local level = g and g:GetAttribute("Level") or 1
			local def = Config.Gnomes[kind]
			local lv = def and def.levels[level]
			sheetTitle.Text = if dazed then "Seeing stars..."
				else string.format("%s L%d · %d dmg · range %d", def and def.name or "?", level, lv and lv.dmg or 0, lv and lv.range or 0)
			local nxt = def and def.levels[level + 1]
			slots[1].Visible = true
			slots[1].Text = if nxt then string.format("UPGRADE\n%d", nxt.cost) else "MAX LEVEL"
			slots[1].BackgroundColor3 = if nxt and seeds >= nxt.cost and not dazed then Color3.fromRGB(70, 130, 200) else Color3.fromRGB(90, 90, 90)
			local paid = 0
			if def then
				for i = 1, level do paid += def.levels[i].cost end
			end
			slots[2].Visible = true
			-- before the bed's first wave a sale gives everything back (Garden.refundShare; REVIEW-1)
			local share = if phase == "reveal" then Config.RevealRefund else Config.SellRefund
			slots[2].Text = string.format("SELL\n+%d", math.floor(paid * share))
			slots[2].BackgroundColor3 = if dazed then Color3.fromRGB(90, 90, 90) else Color3.fromRGB(170, 110, 60)
			slots[3].Visible = false
			slots[4].Visible = false
		end
	end

	-- first-minute hints (until wave 1 is survived)
	local tutorialDone = player:GetAttribute("TutorialDone") == true
	local gnomes = attr("Gnomes") or 0
	local hint = nil
	if not tutorialDone and not resultMode then
		if phase == "reveal" and gnomes == 0 then
			hint = "Tap a glowing pad to plant a gnome"
		elseif phase == "reveal" and gnomes == 1 then
			hint = "One more on a glowing pad, then press READY"
		elseif phase == "reveal" then
			hint = "Press READY when your gnomes are in place"
		end
	elseif phase == "build" and gnomes > 0 and (attr("Wave") or 0) == 2 then
		hint = "Tap a gnome to upgrade it"
	end
	-- on a phone a tap on a small pad zooms in and picks nothing (View.client; REVIEW-2): say what comes next
	if selected == nil and not resultMode and PHASE_ACTIVE[phase] == true and state:GetAttribute("ZoomPeek") == true then
		hint = "Tap the pad you want"
	end
	hintLabel.Visible = hint ~= nil and not sheet.Visible
	hintLabel.Text = hint or ""
end

--============================================================================ buttons
local function guardDazed(): boolean
	local left = dazedLeft()
	if left > 0 then
		toast(string.format(Config.Text.Dazed, math.ceil(left)), 1.2)
		return true
	end
	return false
end

for i, b in slots do
	b.Activated:Connect(function()
		local sel = selected
		if not sel then return end
		if guardDazed() then return end
		if sel.kind == "pad" then
			local e = KINDS[i]
			if e then PlantEvent:FireServer(sel.pad, e.kind) end
			select(nil, nil)
		else
			if i == 1 then
				UpgradeEvent:FireServer(sel.pad)
			elseif i == 2 then
				SellEvent:FireServer(sel.pad)
				select(nil, nil)
			end
		end
	end)
end
closeBtn.Activated:Connect(function() select(nil, nil) end)
readyBtn.Activated:Connect(function()
	ReadyEvent:FireServer()
end)
resultBtn.Activated:Connect(function()
	local phase = attr("Phase")
	if phase == "won" then
		NextSeasonEvent:FireServer()
	elseif phase == "lost" then
		RestartEvent:FireServer()
	end
end)

--============================================================================ server messages
ToastEvent.OnClientEvent:Connect(function(msg)
	if type(msg) == "string" then toast(msg) end
end)

FanfareEvent.OnClientEvent:Connect(function(f)
	if type(f) ~= "table" or (f.o ~= nil and f.o ~= player.UserId) then return end
	if f.kind == "season" then
		resultTitle.Text = if f.brag then "HARVEST MOON!" else string.upper(tostring(f.season)) .. " WON!"
		local sub = if f.boss then "The " .. tostring(f.boss) .. " falls." else "Season survived."
		if f.unlock then sub ..= " " .. tostring(f.unlock) .. " unlocked!" end
		resultSub.Text = sub
		resultBtn.Text = if f.next and f.next ~= f.season then "NEXT: " .. string.upper(tostring(f.next)) else "PLAY ON"
		pcall(function() FxClient.popIn(result) end)
	elseif f.kind == "lost" then
		resultTitle.Text = "The bugs ate your carrots!"
		resultSub.Text = string.format("Wave %d of %s. A fresh bed is waiting.", tonumber(f.wave) or 0, tostring(f.season))
		resultBtn.Text = "TRY AGAIN"
		pcall(function() FxClient.popIn(result) end)
	elseif f.kind == "clear" then
		toast(string.format("Wave %d survived: +%d seeds", tonumber(f.wave) or 0, tonumber(f.bonus) or 0), 2)
	end
	refresh()
end)

-- View.client picked a pad from a tap
state:GetAttributeChangedSignal("PickSeq"):Connect(function()
	local pad = state:GetAttribute("PickPad")
	if type(pad) ~= "number" or garden == nil then return end
	if PHASE_ACTIVE[attr("Phase") or "reveal"] ~= true then return end
	onPadClicked(pad)
end)

player:GetAttributeChangedSignal("TutorialDone"):Connect(function() refresh() end)
state:GetAttributeChangedSignal("ZoomPeek"):Connect(function() refresh() end)
state:GetAttributeChangedSignal("DazedUntil"):Connect(function()
	refresh()
	local left = dazedLeft()
	if left > 0 then task.delay(left + 0.05, refresh) end
end)
local gardensFolder = workspace:FindFirstChild("Gardens")
if gardensFolder then
	gardensFolder.ChildAdded:Connect(function() refresh() end)
end
refresh()
-- a slow join (the garden built after this script started) is picked up within a second
task.spawn(function()
	while garden == nil do
		task.wait(1)
		refresh()
	end
end)
