-- STORMGROW — the HUD (StarterPlayerScripts). Display only: it reads Player/tile attributes and the server
-- clock, and asks the server through three remotes (Select, Unlock, BuyField). Nothing here is trusted.
--
-- Phone first (docs/mobile-ui-brief.md, DESIGN.md §12): one root Frame owns the UIScale and is sized
-- 1/scale; the layout re-runs on ViewportSize and TouchEnabled; nothing tappable sits in the bottom
-- bands (Roblox's thumbstick and jump button); every tap target is >= 44 screen px on touch; panels never
-- overlap (robloxemu/check_stormgrow_hud.luau runs the hudcheck with overlap = true):
--   * the top row: Stats (left, not tappable), TopBar (forecast chip + band chip), Toggles (right);
--   * under it, the centre column: the hazard banner, the toast line, then Timeline or Almanac;
--   * the right column: Seeds (always on a wide screen, a drawer behind 🌱 on a phone);
--   * opening the Almanac hides Seeds and the Timeline; on a phone Seeds and the Timeline exclude each other.
-- This file owns the ONLY client connections to the Toast and Board remotes (grow-a-crystal review
-- finding 1: a queued RemoteEvent reaches only the first connection).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Weather = require(ReplicatedStorage:WaitForChild("Weather"))
local Mutation = require(ReplicatedStorage:WaitForChild("Mutation"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Growth = require(ReplicatedStorage:WaitForChild("Growth"))
local Hints = require(ReplicatedStorage:WaitForChild("Hints"))
local Text = require(ReplicatedStorage:WaitForChild("Text"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local ClientClock = require(ReplicatedStorage:WaitForChild("ClientClock"))
local remotes = ReplicatedStorage:WaitForChild("StormRemotes")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local W, M = Config.Weather, Config.Marks
local bands = Config.Env.Bands
local now = ClientClock.attach(workspace, Config.Play.ClientExtrapolateMax)

--============================================================================== widgets
local MARGIN, GAP, MIN_TAP = Responsive.MARGIN, 8, 44
local STATS_W, STATS_ROW = 190, 22
local BTN_W, BTN_H = 70, 36
local FORECAST_H, CHIP_H = 34, 26
local LINE_H = 30
local SEEDS_W, SEED_ROW_H, SEEDS_HEAD = 300, 54, 30
local TIMELINE_W, TIMELINE_ROW = 380, 24
local ALMANAC_W = 580

local gui = Instance.new("ScreenGui")
gui.Name = "StormHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local DARK = Color3.fromRGB(22, 28, 40)
local INK = Color3.fromRGB(240, 244, 255)
local GOLD = Color3.fromRGB(255, 214, 90)

local function frame(name: string, parent: Instance, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = DARK
	f.BackgroundTransparency = transparency or 0.2
	f.BorderSizePixel = 0
	f.Parent = parent
	FxClient.theme(f, { corner = 10, stroke = Color3.fromRGB(120, 140, 190), strokeThickness = 1 })
	return f
end

local function label(name: string, parent: Instance, textSize: number?, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = if bold then Enum.Font.GothamBlack else Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = textSize or 18
	c.Parent = l
	return l
end

local function button(name: string, parent: Instance, text: string, color: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = color or Color3.fromRGB(60, 90, 150)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextScaled = true
	b.AutoButtonColor = true
	b.Text = text
	b.Parent = parent
	FxClient.theme(b, { corner = 10 })
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 18
	c.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	return b
end

-- ── top left: stats (not tappable) ─────────────────────────────────────────────────────────────────
local stats = frame("Stats", root)
local coinsLabel = label("Coins", stats, 20, true)
local harvestLabel = label("Harvested", stats, 16)
local almanacLabel = label("AlmanacCount", stats, 16)

-- ── top centre: forecast chip (tap: the 30-minute timeline) and the band chip ─────────────────────
local topBar = frame("TopBar", root, 1)
local forecast = button("Forecast", topBar, "⛅ Forecast", Color3.fromRGB(45, 60, 95))
local bandChip = label("BandChip", topBar, 16)
bandChip.TextXAlignment = Enum.TextXAlignment.Center
bandChip.BackgroundTransparency = 0.25
bandChip.BackgroundColor3 = DARK
FxClient.theme(bandChip, { corner = 8 })

-- ── top right: Rest, Almanac, Seeds (the Seeds toggle only on a phone) ─────────────────────────────
local toggles = frame("Toggles", root, 1)
local restButton = button("RestButton", toggles, "☕ Rest", Color3.fromRGB(70, 110, 170))
local almanacButton = button("AlmanacButton", toggles, "📖", Color3.fromRGB(120, 80, 160))
local seedsButton = button("SeedsButton", toggles, "🌱", Color3.fromRGB(60, 130, 70))

-- ── the centre strip: hazard banner (driven by Sky.client) and the toast line ─────────────────────
local hazardBanner = label("HazardBanner", root, 20, true)
hazardBanner.TextXAlignment = Enum.TextXAlignment.Center
hazardBanner.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
hazardBanner.BackgroundTransparency = 0.15
hazardBanner.TextColor3 = Color3.fromRGB(255, 236, 120)
hazardBanner.Visible = false
FxClient.theme(hazardBanner, { corner = 8 })
local toastLabel = label("Toast", root, 18, true)
toastLabel.TextXAlignment = Enum.TextXAlignment.Center
toastLabel.BackgroundColor3 = DARK
toastLabel.BackgroundTransparency = 0.25
toastLabel.TextWrapped = true
toastLabel.Visible = false
FxClient.theme(toastLabel, { corner = 8 })

-- ── right column: the Seeds panel ───────────────────────────────────────────────────────────────────
local seeds = frame("Seeds", root)
local seedsTitle = label("SeedsTitle", seeds, 18, true)
seedsTitle.Text = "🌱 Seeds"
local seedList = Instance.new("ScrollingFrame")
seedList.Name = "SeedList"
seedList.BackgroundTransparency = 1
seedList.BorderSizePixel = 0
seedList.ScrollBarThickness = 6
seedList.ScrollingDirection = Enum.ScrollingDirection.Y
seedList.CanvasSize = UDim2.fromOffset(0, 0)
seedList.Parent = seeds
local seedLayout = Instance.new("UIListLayout")
seedLayout.Padding = UDim.new(0, 6)
seedLayout.SortOrder = Enum.SortOrder.LayoutOrder
seedLayout.Parent = seedList
local seedRows: { TextButton } = {}
for i, crop in Config.Crops do
	local row = button("Seed_" .. crop.id, seedList, crop.name, Color3.fromRGB(45, 60, 80))
	row.LayoutOrder = i
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextWrapped = true
	row.Font = Enum.Font.GothamBold
	seedRows[i] = row
end
local fieldButton = button("FieldButton", seeds, "🧱 Next field", Color3.fromRGB(150, 110, 60))

-- ── centre: the 30-minute timeline ──────────────────────────────────────────────────────────────────
local timeline = frame("Timeline", root)
timeline.Visible = false
local timelineTitle = label("TimelineTitle", timeline, 18, true)
timelineTitle.Text = "⛅ The next 30 minutes (every server)"
local timelineLines: { TextLabel } = {}
for i = 1, 9 do
	timelineLines[i] = label("Line_" .. i, timeline, 16)
end

-- ── centre modal: the Almanac ───────────────────────────────────────────────────────────────────────
local almanac = frame("Almanac", root, 0.08)
almanac.Visible = false
local almanacTitle = label("AlmanacTitle", almanac, 20, true)
local almanacClose = button("AlmanacClose", almanac, "X", Color3.fromRGB(150, 60, 60))
local almanacGrid = Instance.new("ScrollingFrame")
almanacGrid.Name = "AlmanacGrid"
almanacGrid.BackgroundTransparency = 1
almanacGrid.BorderSizePixel = 0
almanacGrid.ScrollBarThickness = 6
almanacGrid.ScrollingDirection = Enum.ScrollingDirection.Y
almanacGrid.Parent = almanac
local gridLayout = Instance.new("UIGridLayout")
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.CellPadding = UDim2.fromOffset(4, 4)
gridLayout.Parent = almanacGrid
local almanacCells: { TextLabel } = {}
local almanacNote = label("AlmanacNote", almanac, 14)
almanacNote.TextWrapped = true
do
	-- 8 columns: the crop, then its 7 marked variants in bit order (1..7)
	local order = 0
	local heads = { "", "⚡", "❄️", "⚡❄️", "🌈", "⚡🌈", "❄️🌈", "⚡❄️🌈" }
	for _, h in heads do
		order += 1
		local cell = label("Head_" .. order, almanacGrid, 16, true)
		cell.TextXAlignment = Enum.TextXAlignment.Center
		cell.Text = h
		cell.LayoutOrder = order
	end
	for ci, crop in Config.Crops do
		order += 1
		local name = label("Crop_" .. crop.id, almanacGrid, 14, true)
		name.Text = crop.emoji .. " " .. crop.name
		name.LayoutOrder = order
		for m = 1, 7 do
			order += 1
			local cell = label("Entry_" .. crop.id .. "_" .. m, almanacGrid, 14)
			cell.TextXAlignment = Enum.TextXAlignment.Center
			cell.BackgroundColor3 = Color3.fromRGB(40, 48, 70)
			cell.BackgroundTransparency = 0.3
			cell.LayoutOrder = order
			almanacCells[(ci - 1) * 7 + m] = cell
		end
	end
	local P = function(kind: string): string
		return string.format("1 in %s", if W.Chance[kind] == 0.5 then "2" else string.format("%.1f", 1 / W.Chance[kind]))
	end
	almanacNote.Text = string.format(
		"Each ripe crop, each event: %s ⚡ per storm, %s ❄️ per frost, %s 🌈 per rainbow. Marks multiply: ⚡x5 ❄️x5 🌈x8, "
			.. "Stormglass x25, Radiant x40, Aurora x40, TEMPEST x200 (all three: ripe at :00 or :30, kept to the :05 frost).",
		P("storm"), P("frost"), P("rainbow"))
end

-- ── bottom centre: hint + save banner (not tappable); centre: cards and the loading line ───────────
local hint = label("Hint", root, 18, true)
hint.TextXAlignment = Enum.TextXAlignment.Center
hint.BackgroundColor3 = DARK
hint.BackgroundTransparency = 0.3
hint.TextWrapped = true
hint.Visible = false
FxClient.theme(hint, { corner = 8 })
local saveBanner = label("SaveBanner", root, 14, true)
saveBanner.TextXAlignment = Enum.TextXAlignment.Center
saveBanner.BackgroundColor3 = Color3.fromRGB(120, 60, 20)
saveBanner.BackgroundTransparency = 0.2
saveBanner.TextWrapped = true
saveBanner.Text = "⚠️ Not saving this session (see the message above). Rejoin to save again."
saveBanner.Visible = false
FxClient.theme(saveBanner, { corner = 8 })
local loading = label("Loading", root, 26, true)
loading.TextXAlignment = Enum.TextXAlignment.Center
loading.Text = "🌱 Loading your farm…"
loading.TextStrokeTransparency = 0.4
local card = label("Card", root, 40, true)
card.TextXAlignment = Enum.TextXAlignment.Center
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.TextStrokeTransparency = 0.3
card.Visible = false
local cardSub = label("CardSub", root, 22)
cardSub.TextXAlignment = Enum.TextXAlignment.Center
cardSub.AnchorPoint = Vector2.new(0.5, 0)
cardSub.TextStrokeTransparency = 0.4
cardSub.Visible = false

--============================================================================== layout
local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local seedsOpen = false -- the phone drawer
local timelineOpen = false
local almanacOpen = false

local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then return designPx end
	local wanted = math.max(designPx * layout.scale, MIN_TAP)
	local n = math.ceil(wanted / layout.scale)
	if n * layout.scale < MIN_TAP then n += 1 end
	return n
end

local function place(g: GuiObject, x: number, y: number, w: number, h: number)
	g.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	g.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
end

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
	local rootW, rootH = vx / layout.scale, vyDraw / layout.scale
	local compact = layout.compact
	local padDesign = layout.controlPad / layout.scale
	local bottom = rootH - MARGIN - padDesign

	-- toggles, right
	local btnW, btnH = touchSize(BTN_W), touchSize(BTN_H)
	local restW = touchSize(104)
	seedsButton.Visible = compact
	local togglesW = restW + GAP + btnW + (if compact then GAP + btnW else 0)
	local togglesX = rootW - MARGIN - togglesW
	place(toggles, togglesX, MARGIN, togglesW, btnH)
	place(restButton, 0, 0, restW, btnH)
	place(almanacButton, restW + GAP, 0, btnW, btnH)
	place(seedsButton, restW + GAP + btnW + GAP, 0, btnW, btnH)

	-- stats, left
	local statsH = 3 * STATS_ROW + 10
	place(stats, MARGIN, MARGIN, STATS_W, statsH)
	place(coinsLabel, 10, 4, STATS_W - 20, STATS_ROW)
	place(harvestLabel, 10, 4 + STATS_ROW, STATS_W - 20, STATS_ROW)
	place(almanacLabel, 10, 4 + 2 * STATS_ROW, STATS_W - 20, STATS_ROW)

	-- the Seeds column (reserved on a wide screen)
	local sideW = Responsive.sideWidth(SEEDS_W, vx, layout)
	local centreRight = if compact then rootW - MARGIN else rootW - MARGIN - sideW - GAP

	-- top bar: between stats and toggles when it fits, else a second row
	local fh, ch = touchSize(FORECAST_H), CHIP_H
	local barH = fh + 4 + ch
	local spanL, spanR = MARGIN + STATS_W + GAP, togglesX - GAP
	local rowBottom
	local barX, barW
	if spanR - spanL >= 300 then
		barW = math.min(560, spanR - spanL)
		barX = spanL + (spanR - spanL - barW) / 2
		place(topBar, barX, MARGIN, barW, barH)
		rowBottom = MARGIN + math.max(statsH, barH, btnH)
	else
		local row1 = MARGIN + math.max(statsH, btnH)
		barX, barW = MARGIN, rootW - 2 * MARGIN
		place(topBar, barX, row1 + GAP, barW, barH)
		rowBottom = row1 + GAP + barH
	end
	place(forecast, 0, 0, barW, fh)
	place(bandChip, 0, fh + 4, barW, ch)

	-- centre column below the top row
	local colL = MARGIN
	local colW = centreRight - colL
	local stripW = math.min(640, colW)
	local stripX = colL + (colW - stripW) / 2
	place(hazardBanner, stripX, rowBottom + GAP, stripW, LINE_H)
	place(toastLabel, stripX, rowBottom + GAP + LINE_H + 4, stripW, LINE_H * 1.3)
	local stripBottom = rowBottom + GAP + LINE_H + 4 + LINE_H * 1.3

	-- Seeds. On a wide screen: the reserved right column, from under the top row down to just above the
	-- touch controls. On a phone it is a drawer under the strip: in the right column when there is room
	-- above the jump button (portrait), otherwise in the safe middle band between the thumbstick (left 35 %)
	-- and the jump button (right 25 %), where it may run down to the bottom margin (landscape).
	local fieldH = touchSize(40)
	local designSeedsH = SEEDS_HEAD + fieldH + 12 + 8 * (touchSize(SEED_ROW_H) + 6) + 12
	local seedsX, seedsTop, seedsW, seedsH
	if not compact then
		seedsTop = rowBottom + GAP
		seedsW = sideW
		seedsX = rootW - MARGIN - sideW
		seedsH = math.max(80, math.min(designSeedsH, bottom - seedsTop))
	else
		seedsTop = stripBottom + GAP
		if bottom - seedsTop >= 260 then
			seedsW = math.min(420, rootW - 2 * MARGIN)
			seedsX = rootW - MARGIN - seedsW
			seedsH = math.min(designSeedsH, bottom - seedsTop)
		else
			local safeL, safeR = vx * 0.35 / layout.scale + GAP, vx * 0.75 / layout.scale - GAP
			seedsW = math.min(520, safeR - safeL)
			seedsX = safeL + (safeR - safeL - seedsW) / 2
			seedsH = math.max(80, math.min(designSeedsH, rootH - MARGIN - seedsTop))
		end
	end
	place(seeds, seedsX, seedsTop, seedsW, seedsH)
	place(seedsTitle, 10, 4, seedsW - 20, SEEDS_HEAD - 6)
	place(fieldButton, 8, SEEDS_HEAD, seedsW - 16, fieldH)
	local listTop = SEEDS_HEAD + fieldH + 6
	place(seedList, 6, listTop, seedsW - 12, math.max(20, seedsH - listTop - 6))
	local rowH = touchSize(SEED_ROW_H)
	for _, row in seedRows do
		row.Size = UDim2.new(1, -8, 0, rowH)
	end

	-- the timeline under the strip, in the centre column. Nothing in it is tappable, so it may run down to
	-- the bottom margin.
	local tlW = math.min(TIMELINE_W, colW)
	local tlH = math.min(40 + 9 * TIMELINE_ROW, rootH - MARGIN - stripBottom - GAP)
	place(timeline, colL + (colW - tlW) / 2, stripBottom + GAP, tlW, math.max(60, tlH))
	place(timelineTitle, 10, 6, tlW - 20, 26)
	for i, l in timelineLines do
		place(l, 14, 36 + (i - 1) * TIMELINE_ROW, tlW - 28, TIMELINE_ROW - 2)
	end

	-- the Almanac modal: centred under the strip (it hides Seeds and the timeline)
	local amW = math.min(ALMANAC_W, rootW - 2 * MARGIN)
	local amTop = stripBottom + GAP
	-- its one button (close) sits at its top, so the modal may run down to the bottom margin
	local amH = math.min(520, math.max(120, rootH - MARGIN - amTop))
	place(almanac, (rootW - amW) / 2, amTop, amW, amH)
	local closeS = touchSize(34)
	place(almanacTitle, 12, 6, amW - closeS - 30, 30)
	place(almanacClose, amW - closeS - 8, 6, closeS, closeS)
	local noteH = 58
	place(almanacGrid, 8, 12 + math.max(30, closeS), amW - 16, amH - math.max(30, closeS) - noteH - 26)
	place(almanacNote, 12, amH - noteH - 8, amW - 24, noteH)
	local cellW = math.floor((amW - 16 - 12 - 7 * 4) / 8)
	gridLayout.CellSize = UDim2.fromOffset(cellW, 28)

	-- bottom centre: hint above the touch controls, save banner above it
	local hintW = math.min(560, colW)
	local hintH = 44
	place(hint, colL + (colW - hintW) / 2, bottom - hintH, hintW, hintH)
	place(saveBanner, colL + (colW - hintW) / 2, bottom - hintH - GAP - 34, hintW, 34)

	-- centre text
	place(loading, rootW / 2 - 240, rootH * 0.42, 480, 44)
	local cardW = math.min(820, rootW - 2 * MARGIN)
	card.Position = UDim2.fromOffset(rootW / 2, rootH * 0.4)
	card.Size = UDim2.fromOffset(cardW, math.min(76, rootH * 0.14))
	cardSub.Position = UDim2.fromOffset(rootW / 2, rootH * 0.4 + math.min(76, rootH * 0.14) / 2 + 4)
	cardSub.Size = UDim2.fromOffset(cardW, math.min(32, rootH * 0.07))

	-- visibility: which panels may be open together
	if almanacOpen then
		seeds.Visible = false
		timeline.Visible = false
		almanac.Visible = true
	else
		almanac.Visible = false
		seeds.Visible = (not compact) or seedsOpen
		timeline.Visible = timelineOpen and not (compact and seedsOpen)
	end
	hint.Visible = hint.Text ~= "" and not almanacOpen
end

local function canvasFit()
	-- CanvasSize is DESIGN px, AbsoluteContentSize is SCREEN px: divide by the scale (the canvas trap)
	local s = if layout.scale > 0 then layout.scale else 1
	seedList.CanvasSize = UDim2.fromOffset(0, math.ceil(seedLayout.AbsoluteContentSize.Y / s) + 4)
	almanacGrid.CanvasSize = UDim2.fromOffset(0, math.ceil(gridLayout.AbsoluteContentSize.Y / s) + 4)
end
seedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(canvasFit)
gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(canvasFit)

applyLayout()
canvasFit()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	applyLayout()
	canvasFit()
end)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
		applyLayout()
		canvasFit()
	end)
end)

--============================================================================== toasts
-- One queue for the server's toasts and the HUD's own refusals, so a line the client says (a locked seed row)
-- stays up as long as a server toast does instead of vanishing at the next 0.2 s refresh.
local queue: { { text: string, kind: string } } = {}
local toastUntil = 0
local function showNextToast()
	local item = table.remove(queue, 1)
	if item == nil then
		toastLabel.Visible = false
		return
	end
	toastLabel.Text = item.text
	toastLabel.TextColor3 = if item.kind == "announce" then GOLD elseif item.kind == "warn" then Color3.fromRGB(255, 190, 120) else INK
	toastLabel.Visible = true
	toastUntil = tick() + (if item.kind == "announce" then 4 else 3)
end
local function pushToast(text: string, kind: string)
	table.insert(queue, { text = text, kind = kind })
	if #queue > 4 then table.remove(queue, 1) end
	if not toastLabel.Visible or tick() >= toastUntil then showNextToast() end
end
remotes.Toast.OnClientEvent:Connect(function(text: any, kind: any)
	if type(text) ~= "string" then return end
	pushToast(text, if type(kind) == "string" then kind else "info")
end)

--============================================================================== buttons
seedsButton.Activated:Connect(function()
	seedsOpen = not seedsOpen
	if seedsOpen then
		almanacOpen = false
		if layout.compact then timelineOpen = false end
	end
	applyLayout()
end)
forecast.Activated:Connect(function()
	timelineOpen = not timelineOpen
	if timelineOpen then
		almanacOpen = false
		if layout.compact then seedsOpen = false end
	end
	applyLayout()
end)
almanacButton.Activated:Connect(function()
	almanacOpen = not almanacOpen
	applyLayout()
end)
almanacClose.Activated:Connect(function()
	almanacOpen = false
	applyLayout()
end)

for i, row in seedRows do
	row.Activated:Connect(function()
		local unlocked = player:GetAttribute("Unlocked") or 1
		if i <= unlocked then
			remotes.Select:FireServer(Config.Crops[i].id)
		elseif i == unlocked + 1 then
			remotes.Unlock:FireServer()
		else
			-- say why rather than doing nothing (no silent no-ops, even client-side)
			local prev = Config.Crops[i - 1]
			pushToast(string.format("Unlock %s %s first", prev.emoji, prev.name), "info")
		end
	end)
end
fieldButton.Activated:Connect(function()
	remotes.BuyField:FireServer()
end)

--============================================================================== the board
-- Each player's own view of the physical boards: SurfaceGuis created HERE, on the client, parented to the
-- board parts. They never replicate, so two players at a board see different views. One view on the market
-- board, one on the small board on YOUR porch (the standard: a board near spawn; you spawn on the porch).
type BoardView = { gui: SurfaceGui, title: TextLabel, rows: { TextLabel }, you: TextLabel, note: TextLabel }
local boardViews: { [Instance]: BoardView } = {}
local lastPayload: any = nil
-- `shown` rows: the market board lists the top 10; the porch board the top 5 in rows twice as tall, so they read
-- >= 12 pt on a phone from its prompt (REVIEW-1 B5; check_stormgrow_board part 6 measures both)
local function buildView(boardPart: BasePart, shown: number): BoardView
	local sg = Instance.new("SurfaceGui")
	sg.Name = "BoardView"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Adornee = boardPart
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(30, 36, 28)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local short = shown <= 5
	local title = label("Title", bg, 60, true)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Position = UDim2.fromScale(0.03, 0.02)
	title.Size = UDim2.fromScale(0.94, if short then 0.13 else 0.11)
	title.Text = "🏆 Almanac"
	local rows = {}
	for i = 1, shown do
		local r = label("Row_" .. i, bg, 44)
		if short then
			r.Position = UDim2.fromScale(0.05, 0.17 + (i - 1) * 0.1)
			r.Size = UDim2.fromScale(0.9, 0.092)
		else
			r.Position = UDim2.fromScale(0.05, 0.14 + (i - 1) * 0.062)
			r.Size = UDim2.fromScale(0.9, 0.058)
		end
		rows[i] = r
	end
	local you = label("You", bg, 44, true)
	you.TextColor3 = GOLD
	you.Position = UDim2.fromScale(0.05, if short then 0.68 else 0.77)
	you.Size = UDim2.fromScale(0.9, if short then 0.1 else 0.07)
	local note = label("Note", bg, 32)
	note.TextWrapped = true
	note.Position = UDim2.fromScale(0.05, if short then 0.8 else 0.85)
	note.Size = UDim2.fromScale(0.9, if short then 0.18 else 0.13)
	note.Text = "Loading the board…"
	sg.Parent = boardPart
	return { gui = sg, title = title, rows = rows, you = you, note = note }
end
local function paint(v: BoardView, payload: any)
	v.title.Text = tostring(payload.title or "🏆 Almanac")
	for i, r in v.rows do
		local row = payload.rows and payload.rows[i]
		if row then
			r.Text = string.format("%d.  %s   📖 %d", row.rank, tostring(row.name), row.count)
			r.TextColor3 = if row.you then GOLD else INK
		else
			r.Text = ""
		end
	end
	v.you.Text = tostring(payload.you or "")
	v.note.Text = tostring(payload.note or "Walk up to a board and press the prompt to switch Friends / Everyone.")
end
-- the boards this client should draw on: the market's, and its own porch's (which changes with the slot)
local function syncBoards()
	local want: { [Instance]: number } = {}
	local valley = workspace:FindFirstChild("Valley")
	local market = valley and valley:FindFirstChild("AlmanacBoard")
	if market then want[market] = Config.Board.PublicShown end
	local slot = player:GetAttribute("Slot")
	local farms = workspace:FindFirstChild("Farms")
	if type(slot) == "number" and slot >= 1 and farms then
		local farm = farms:FindFirstChild("Farm_" .. slot)
		local porch = farm and farm:FindFirstChild("FarmBoard_" .. slot)
		if porch then want[porch] = Config.Board.PorchShown end
	end
	for part, v in boardViews do
		if not want[part] then
			v.gui:Destroy()
			boardViews[part] = nil
		end
	end
	for part, shown in want do
		if boardViews[part] == nil then
			boardViews[part] = buildView(part :: BasePart, shown)
			if lastPayload then paint(boardViews[part], lastPayload) end
		end
	end
end
syncBoards()
player:GetAttributeChangedSignal("Slot"):Connect(syncBoards)
remotes.Board.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then return end
	lastPayload = payload
	syncBoards()
	for _, v in boardViews do paint(v, payload) end
end)

--============================================================================== the frame
local myFarm: Instance? = nil
local lastCoins: number? = nil
local lastBandIdx = 0

local function myTiles(): { BasePart }
	local slot = player:GetAttribute("Slot")
	if type(slot) ~= "number" or slot < 1 then return {} end
	if myFarm == nil or myFarm.Parent == nil then
		local farms = workspace:FindFirstChild("Farms")
		myFarm = farms and farms:FindFirstChild("Farm_" .. slot)
	end
	local tiles = myFarm and myFarm:FindFirstChild("Tiles")
	local out = {}
	if tiles then
		for _, c in tiles:GetChildren() do
			if c:GetAttribute("Key") ~= nil then table.insert(out, c :: BasePart) end
		end
	end
	return out
end

local accum = 0
local function refresh(dt: number)
	accum += dt
	if accum < 0.2 then return end
	accum = 0
	local t = now()
	local loaded = player:GetAttribute("Loaded") == true
	loading.Visible = not loaded
	local coins = player:GetAttribute("Coins") or 0
	local harvested = player:GetAttribute("Harvested") or 0
	local count = player:GetAttribute("AlmanacCount") or 0
	local unlocked = player:GetAttribute("Unlocked") or 1
	local fields = player:GetAttribute("Fields") or 1
	local selected = player:GetAttribute("Selected") or Config.Crops[1].id
	local bitsStr = player:GetAttribute("AlmanacBits") or ""
	coinsLabel.Text = "💰 " .. Text.int(coins)
	harvestLabel.Text = "🌾 " .. Text.short(harvested) .. " harvested"
	almanacLabel.Text = string.format("📖 %d / 56 Almanac", count)
	saveBanner.Visible = loaded and player:GetAttribute("CanSave") == false and not almanacOpen
	if lastCoins ~= nil and coins > lastCoins + 0.5 then
		coinsLabel.TextColor3 = GOLD
		task.delay(0.4, function() coinsLabel.TextColor3 = INK end)
	end
	lastCoins = coins

	-- forecast
	local kind, _, to = Weather.at(t, W)
	local nk, ns = Weather.nextEvent(t, W)
	if kind ~= "clear" then
		forecast.Text = string.format("%s %s · %s left  ·  next %s %s", W.Emoji[kind], string.upper(W.Names[kind]),
			Text.clock(to - t), W.Emoji[nk], Text.clock(ns - t))
	else
		local k2, s2 = Weather.nextEvent(ns, W)
		forecast.Text = string.format("Next %s %s %s  ·  %s %s", W.Emoji[nk], W.Names[nk], Text.clock(ns - t), W.Emoji[k2], Text.clock(s2 - t))
	end
	if timeline.Visible then
		local list = Weather.timeline(t, W, 1800)
		for i, l in timelineLines do
			local e = list[i]
			if e then
				local mark = M[e.kind]
				local live = t >= e.from
				l.Text = string.format("%s %s %s  %s  %s %s x%d", if live then "▶" else " ", Weather.minuteLabel(e.from, W),
					W.Emoji[e.kind], if live then "NOW" else "in " .. Text.clock(e.from - t), mark.emoji, mark.name, mark.mult)
			else
				l.Text = ""
			end
		end
	end

	-- band chip (Sky.client owns the rest state and publishes it as a LOCAL Player attribute)
	local bi = EnvBands.indexAt(bands, harvested)
	local b = bands[bi]
	local nextIdx = EnvBands.nextBand(bands, harvested)
	local restState = player:GetAttribute("RestState")
	if restState == "resting" then
		bandChip.Text = "☕ Resting · the wind leaves you alone (move or tap to carry on)"
	elseif restState == "idle" then
		bandChip.Text = "💤 Idle · the wind leaves you alone"
	elseif restState == "queued" then
		bandChip.Text = "☕ Rest as soon as the sky is clear"
	elseif nextIdx then
		local nb = bands[nextIdx :: number]
		bandChip.Text = string.format("%s %s  ·  %s %s at %s", b.emoji, b.name, nb.emoji, nb.name, Text.short(nb.from))
	else
		bandChip.Text = b.emoji .. " " .. b.name
	end
	lastBandIdx = bi

	-- seeds panel
	local almanacMap = {}
	for i, k in Mutation.allKeys(Config.Crops) do
		if string.sub(bitsStr, i, i) == "1" then almanacMap[k] = true end
	end
	for i, crop in Config.Crops do
		local row = seedRows[i]
		local txt
		if i <= unlocked then
			local ck, cs = Weather.catchesEvent(t, crop.grow, W)
			local tag = if ck ~= "clear" then string.format("%s ripe for the %s %s", M[ck].emoji, Weather.minuteLabel(cs, W), string.lower(W.Names[ck])) else ""
			local missing = Mutation.missing(almanacMap, crop.id)
			local find = if missing > 0 then string.format("  📖 %d to find", missing) else "  📖 done"
			txt = string.format("%s%s %s · seed %s · %s · sells %s\n%s%s", if crop.id == selected then "▶ " else "", crop.emoji,
				crop.name, Text.short(crop.seed), Text.clock(crop.grow), Text.short(crop.sell), tag, find)
			row.BackgroundColor3 = if crop.id == selected then Color3.fromRGB(60, 120, 70) else Color3.fromRGB(45, 60, 80)
		elseif i == unlocked + 1 then
			local gate = crop.needHarvested or 0
			if harvested < gate then
				txt = string.format("🔒 %s %s · grows only in the Eye of the Storm\nharvest %s to get there", crop.emoji, crop.name, Text.short(gate))
			else
				txt = string.format("🔓 Unlock %s %s for %s\n%s", crop.emoji, crop.name, Text.int(crop.unlock),
					if coins >= crop.unlock then "tap to unlock" else "you have " .. Text.int(coins))
			end
			row.BackgroundColor3 = if coins >= crop.unlock and harvested >= gate then Color3.fromRGB(150, 120, 40) else Color3.fromRGB(55, 55, 65)
		else
			txt = string.format("🔒 %s %s", crop.emoji, crop.name)
			row.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
		end
		if row.Text ~= txt then row.Text = txt end
	end
	local fp = Economy.nextFieldPrice({ fields = fields }, Config)
	fieldButton.Text = if fp then string.format("🧱 Field %d: %s", fields + 1, Text.int(fp)) else "🧱 All six fields are yours"
	fieldButton.BackgroundColor3 = if fp and coins >= fp then Color3.fromRGB(190, 140, 50) else Color3.fromRGB(110, 90, 60)

	-- almanac grid
	if almanac.Visible then
		almanacTitle.Text = string.format("📖 Almanac  %d / 56", count)
		for i, cell in almanacCells do
			local found = string.sub(bitsStr, i, i) == "1"
			cell.Text = if found then "✓" else "·"
			cell.BackgroundColor3 = if found then Color3.fromRGB(70, 140, 90) else Color3.fromRGB(40, 48, 70)
		end
	end

	-- the hint, from state
	local tiles = myTiles()
	local owned, planted, ripe, heldMarked, ripeValue = 0, 0, 0, 0, 0
	local running = Weather.at(t, W)
	local cueKind = if running ~= "clear" then running else nk
	local cueBit = M[cueKind].bit
	for _, hb in tiles do
		if hb:GetAttribute("Locked") ~= true then
			owned += 1
			local c = hb:GetAttribute("Crop")
			if type(c) == "string" and c ~= "" then
				planted += 1
				local at, grow = hb:GetAttribute("PlantedAt") or 0, hb:GetAttribute("Grow") or 0
				if Growth.shownRipe(t, at, grow, Config.Play.RipeLeadSeconds) then
					local marks = hb:GetAttribute("Marks") or 0
					if bit32.band(marks, cueBit) == 0 then
						ripe += 1
						if ripeValue == 0 then ripeValue = Economy.saleValue(c, marks, Config) end
					elseif running ~= "clear" then
						heldMarked += 1
					end
				end
			end
		end
	end
	local text = if loaded then Hints.pick({
		now = t, harvests = player:GetAttribute("Harvests") or 0, planted = planted, owned = owned, ripe = ripe,
		ripeValue = ripeValue, coins = coins, unlocked = unlocked, fields = fields, heldMarked = heldMarked,
	}, Config, Weather) else nil
	hint.Text = text or ""
	hint.Visible = text ~= nil and not almanacOpen

	if toastLabel.Visible and tick() >= toastUntil then showNextToast() end
end

local frameError = false
RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(refresh, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken HUD frame must not flood the output
		warn("[StormHud] frame error: " .. tostring(err))
	end
end)
-- one refresh right away, so the very first frame already reads right
pcall(refresh, 1)
