-- STEAL A CRYPTID - the HUD. Lives in StarterPlayerScripts. Display and intent only: the server
-- owns every number, and every button here fires a remote the server validates and answers.
--
-- Phone first (docs/mobile-ui-brief.md):
--   1. the UIScale sits on a ROOT FRAME sized 1/scale, never on the ScreenGui (where it does nothing);
--   2. panels go through Responsive.fitHeight / sideWidth, and the long one scrolls;
--   3. nothing tappable in the bottom-left or bottom-right (Roblox's thumbstick and jump button);
--   4. re-layout on Camera ViewportSize AND on UserInputService.TouchEnabled;
--   5. every tappable control is at least 44 SCREEN px on a touch device.
-- Layout: top-left readout (Essence, rate, Journal), top-right toggles (Rest, Hunt, Build, or Leave
-- camp while raiding), hints / toasts / the raid chip top-centre, the Hunt panel and the build sheet as
-- centre panels, the not-saving banner under the readout. No emoji anywhere: Roblox's font draws
-- some as empty boxes (fork-tower/STUDIO.md section 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local remotes = ReplicatedStorage:WaitForChild("CryptidRemotes")
local StateEvent = remotes:WaitForChild("State")
local ToastEvent = remotes:WaitForChild("Toast")
local FxEvent = remotes:WaitForChild("Fx")
local HuntEvent = remotes:WaitForChild("Hunt")
local LeaveEvent = remotes:WaitForChild("LeaveCamp")
local RerollEvent = remotes:WaitForChild("Reroll")
local ExpandEvent = remotes:WaitForChild("Expand")
local BuildEvent = remotes:WaitForChild("BuildMode")
local TrapEvent = remotes:WaitForChild("TrapAction")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local ACCENT = rgb(Config.Hud.Accent)
local DANGER = rgb(Config.Hud.Danger)
local GOLD = rgb(Config.Hud.Gold)
local PANEL = rgb(Config.Hud.Panel)
local DIM = Color3.fromRGB(60, 64, 72)
local WHITE = Color3.fromRGB(235, 238, 240)

--============================================================================ scaffolding

local gui = Instance.new("ScreenGui")
gui.Name = "CryptidHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- The night's side of the HUD (src/client/Night.client.luau, EYECANDY.md): client-local values, never
-- replicated. This HUD counts presses of its Rest button; the night writes back the button's label and
-- one status line for the chip (a hazard's warning, or "Resting - poachers still come"). The night owns
-- the rules; the HUD only draws them.
local nightBus = Instance.new("Folder")
nightBus.Name = "NightBus"
local restPresses = Instance.new("IntValue")
restPresses.Name = "RestPresses"
restPresses.Value = 0
restPresses.Parent = nightBus
local restLabel = Instance.new("StringValue")
restLabel.Name = "RestLabel"
restLabel.Value = "Rest"
restLabel.Parent = nightBus
local nightStatus = Instance.new("StringValue")
nightStatus.Name = "Status"
nightStatus.Value = ""
nightStatus.Parent = nightBus
local nightKind = Instance.new("StringValue")
nightKind.Name = "StatusKind"
nightKind.Value = ""
nightKind.Parent = nightBus
nightBus.Parent = gui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- IgnoreGuiInset is false, so the drawable height is the viewport minus the topbar inset.
local function effectiveHeight(vy: number): number
	if vy <= 0 or gui.IgnoreGuiInset then return vy end
	return math.max(1, vy - GuiService:GetGuiInset().Y)
end

local layout = Responsive.layout(camera.ViewportSize.X, effectiveHeight(camera.ViewportSize.Y),
	UserInputService.TouchEnabled, camera.ViewportSize.Y)

local MIN_TAP = 44
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then return designPx end
	return math.ceil(math.max(designPx * layout.scale, MIN_TAP) / layout.scale)
end

local function cap(i: Instance, px: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = px
	c.Parent = i
end

local function textLabel(parent: Instance, name: string, text: string, color: Color3, maxSize: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.6
	t.Text = text
	t.Parent = parent
	cap(t, maxSize)
	return t
end

local buttons: { TextButton } = {}
local function button(parent: Instance, name: string, text: string, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.TextColor3 = WHITE
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.Text = text
	b.TextWrapped = true
	b.Parent = parent
	FxClient.theme(b, { corner = 8 })
	cap(b, 16)
	b.Activated:Connect(onClick)
	table.insert(buttons, b)
	return b
end

local state: any = nil

--============================================================================ top-left readout

local readout = Instance.new("Frame")
readout.Name = "Readout"
readout.Position = UDim2.new(0, 8, 0, 8)
readout.Size = UDim2.new(0, 250, 0, 58)
readout.BackgroundColor3 = PANEL
readout.BackgroundTransparency = 0.15
readout.Parent = root
FxClient.theme(readout, { corner = 10, stroke = ACCENT, strokeThickness = 1.5, strokeTransparency = 0.5 })

local essenceLabel = textLabel(readout, "Essence", "30 Essence", GOLD, 26)
essenceLabel.Position = UDim2.new(0, 10, 0, 2)
essenceLabel.Size = UDim2.new(1, -20, 0.58, 0)
essenceLabel.TextXAlignment = Enum.TextXAlignment.Left
local rateLabel = textLabel(readout, "Rate", "+0/s   Journal 0/8", Color3.fromRGB(190, 230, 200), 15)
rateLabel.Position = UDim2.new(0, 10, 0.58, 0)
rateLabel.Size = UDim2.new(1, -20, 0.38, 0)
rateLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Long lines WRAP in a two-line box instead of shrinking to one line. REVIEW-1 measured the banner
-- (99 characters) at 276 x 10.8 screen px on an 844x390 phone and the toast (112 characters) at
-- 360 x 13: both fit, neither could be read. check_stealacryptid_hud.luau estimates every shown
-- string's rendered size against a 100-character toast and a 90-character banner.
local banner = textLabel(root, "SaveBanner", "", DANGER, 14)
banner.Visible = false
banner.TextXAlignment = Enum.TextXAlignment.Left
banner.TextWrapped = true

--============================================================================ top-right toggles

local toggles = Instance.new("Frame")
toggles.Name = "Toggles"
toggles.BackgroundTransparency = 1
toggles.AnchorPoint = Vector2.new(1, 0)
toggles.Position = UDim2.new(1, -8, 0, 8)
toggles.Parent = root
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = toggles
end

local huntPanel: ScrollingFrame
local buildSheet: Frame
local huntOpen, sheetCell = false, nil
local applyLayout -- forward

-- Rest: only a pause from the night's critters (Night.client); poachers, jars and raids carry on
local restToggle = button(toggles, "RestToggle", "Rest", Color3.fromRGB(60, 80, 130), function()
	restPresses.Value += 1
end)
restToggle.LayoutOrder = 0
local huntToggle = button(toggles, "HuntToggle", "Hunt", Color3.fromRGB(150, 90, 40), function()
	huntOpen = not huntOpen
	sheetCell = nil
	applyLayout()
end)
huntToggle.LayoutOrder = 1
local buildToggle = button(toggles, "BuildToggle", "Build", Color3.fromRGB(50, 120, 80), function()
	BuildEvent:FireServer(not (state and state.buildMode))
end)
buildToggle.LayoutOrder = 2
local leaveToggle = button(toggles, "LeaveToggle", "Leave camp", Color3.fromRGB(150, 50, 50), function()
	LeaveEvent:FireServer()
end)
leaveToggle.LayoutOrder = 3
leaveToggle.Visible = false

--============================================================================ top-centre: hint, toast, raid chip

local hint = textLabel(root, "Hint", "", WHITE, 17)
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.TextWrapped = true
local toastLabel = textLabel(root, "Toast", "", GOLD, 16)
toastLabel.AnchorPoint = Vector2.new(0.5, 0)
toastLabel.TextWrapped = true

local chip = Instance.new("Frame")
chip.Name = "RaidChip"
chip.AnchorPoint = Vector2.new(0.5, 0)
chip.BackgroundColor3 = Color3.fromRGB(40, 16, 18)
chip.BackgroundTransparency = 0.15
chip.Visible = false
chip.Parent = root
FxClient.theme(chip, { corner = 10, stroke = DANGER, strokeThickness = 1.5, strokeTransparency = 0.3 })
local chipText = textLabel(chip, "Text", "", WHITE, 17)
chipText.Size = UDim2.new(1, -16, 1, 0)
chipText.Position = UDim2.new(0, 8, 0, 0)

ToastEvent.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "string" then return end
	toastLabel.Text = msg
	task.delay(4, function()
		if toastLabel.Text == msg then toastLabel.Text = "" end
	end)
end)

--============================================================================ the Hunt panel

huntPanel = Instance.new("ScrollingFrame")
huntPanel.Name = "HuntPanel"
huntPanel.AnchorPoint = Vector2.new(0.5, 0)
huntPanel.BackgroundColor3 = PANEL
huntPanel.BackgroundTransparency = 0.08
huntPanel.BorderSizePixel = 0
huntPanel.ScrollBarThickness = 5
huntPanel.ScrollingDirection = Enum.ScrollingDirection.Y
huntPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
huntPanel.Visible = false
huntPanel.Parent = root
FxClient.theme(huntPanel, { corner = 12, stroke = GOLD, strokeThickness = 1.5, strokeTransparency = 0.4 })
do
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(pad :: any)[side] = UDim.new(0, 8)
	end
	pad.Parent = huntPanel
end
local huntList = Instance.new("UIListLayout")
huntList.Padding = UDim.new(0, 5)
huntList.SortOrder = Enum.SortOrder.LayoutOrder
huntList.Parent = huntPanel
local function refreshCanvas()
	-- AbsoluteContentSize is SCREEN px after the UIScale; CanvasSize is design px
	huntPanel.CanvasSize = UDim2.new(0, 0, 0, math.ceil(huntList.AbsoluteContentSize.Y / uiScale.Scale) + 16)
end
huntList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)

local huntTitle = textLabel(huntPanel, "Title", "HUNT BOARD - rival camps", GOLD, 20)
huntTitle.LayoutOrder = 0

local rows: { any } = {}
local function row(order: number, name: string, labelText: string, btnText: string, color: Color3, onClick: () -> ()): any
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Parent = huntPanel
	local l = textLabel(f, "Label", labelText, WHITE, 15)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Position = UDim2.new(0, 0, 0, 0)
	local b = button(f, "Go", btnText, color, onClick)
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, 0, 0, 0)
	local r = { frame = f, label = l, button = b }
	table.insert(rows, r)
	return r
end

local campRows = {}
for tier = 1, #Config.Camps do
	campRows[tier] = row(tier, "Camp_" .. tier, "Camp " .. tier, "Enter", Color3.fromRGB(150, 90, 40), function()
		HuntEvent:FireServer(tier)
	end)
end

local lairTitle = textLabel(huntPanel, "LairTitle", "YOUR LAIR", ACCENT, 18)
lairTitle.LayoutOrder = 10
local expandRow = row(11, "ExpandRow", "Add a cage", "Add", Color3.fromRGB(50, 110, 150), function()
	ExpandEvent:FireServer()
end)
local rerollRow = row(12, "RerollRow", "New sightings on your pedestals (free)", "Re-roll", Color3.fromRGB(90, 80, 150), function()
	RerollEvent:FireServer()
end)
local statsLabel = textLabel(huntPanel, "Stats", "Steals 0 - Caught 0 - Poachers caught 0", Color3.fromRGB(180, 185, 195), 14)
statsLabel.LayoutOrder = 20
row(30, "CloseRow", "", "Close", DIM, function()
	huntOpen = false
	applyLayout()
end)

--============================================================================ the build sheet

buildSheet = Instance.new("Frame")
buildSheet.Name = "BuildSheet"
buildSheet.AnchorPoint = Vector2.new(0.5, 0)
buildSheet.BackgroundColor3 = PANEL
buildSheet.BackgroundTransparency = 0.08
buildSheet.Visible = false
buildSheet.Parent = root
FxClient.theme(buildSheet, { corner = 12, stroke = ACCENT, strokeThickness = 1.5, strokeTransparency = 0.4 })
local sheetTitle = textLabel(buildSheet, "Title", "", ACCENT, 18)
local sheetButtons = {
	button(buildSheet, "Laser", "Laser 250", Color3.fromRGB(170, 40, 40), function()
		if sheetCell then TrapEvent:FireServer(sheetCell.col, sheetCell.row, "laser") end
		sheetCell = nil
		applyLayout()
	end),
	button(buildSheet, "Snare", "Snare 100", Color3.fromRGB(120, 70, 40), function()
		if sheetCell then TrapEvent:FireServer(sheetCell.col, sheetCell.row, "snare") end
		sheetCell = nil
		applyLayout()
	end),
	button(buildSheet, "Clear", "Clear", Color3.fromRGB(70, 90, 110), function()
		if sheetCell then TrapEvent:FireServer(sheetCell.col, sheetCell.row, "clear") end
		sheetCell = nil
		applyLayout()
	end),
	button(buildSheet, "Close", "Close", DIM, function()
		sheetCell = nil
		applyLayout()
	end),
}

--============================================================================ state render

local function hintText(s: any): string
	local touch = UserInputService.TouchEnabled
	if s.raid then
		if s.raid.carrying then return "Get back out the gate with your " .. s.raid.carrying end
		if s.tutorial <= 3 then
			return "Watch the red nets. Walk through when they go dark. " .. (if touch then "Hold GRAB at a cage." else "Hold E at a cage to grab.")
		end
		return ""
	end
	if s.tutorial == 0 then
		return "Buy your first cryptid - walk to the glowing pedestal and " .. (if touch then "tap BUY" else "press E")
	elseif s.tutorial == 1 then
		return if s.collectHint then "Step on the Collect Pad to bank your jar" else "Your cryptid is filling its Essence jar..."
	elseif s.tutorial == 2 then
		return "Rival camps have cryptids too - use the Hunt Board"
	end
	if s.buildMode then return "Tap a glowing tile to place a laser net or a snare" end
	return ""
end

local function render()
	local s = state
	if not s then return end
	essenceLabel.Text = string.format("%d Essence", s.essence)
	rateLabel.Text = string.format("+%d/s   Journal %d/%d", s.rate, s.journal, s.journalMax)
	banner.Visible = s.canSave == false
	banner.Text = s.saveBanner or ""
	hint.Text = hintText(s)

	local raiding = s.raid ~= nil
	restToggle.Visible = not raiding
	restToggle.Text = restLabel.Value
	restToggle.BackgroundColor3 = if restLabel.Value == "Rest" then Color3.fromRGB(60, 80, 130) else Color3.fromRGB(90, 130, 200)
	huntToggle.Visible = not raiding
	buildToggle.Visible = not raiding
	buildToggle.BackgroundColor3 = if s.buildMode then Color3.fromRGB(80, 190, 120) else Color3.fromRGB(50, 120, 80)
	buildToggle.Text = if s.buildMode then "Build: on" else "Build"
	leaveToggle.Visible = raiding

	if raiding then
		chip.Visible = true
		-- no camp name here: it is on the camp's own sign, and on a phone it squeezed the timer
		chipText.Text = string.format("%d s left%s", s.raid.timeLeft,
			if s.raid.carrying then " - carrying " .. s.raid.carrying else "")
	elseif s.poacher and s.poacher.warningLeft then
		chip.Visible = true
		chipText.Text = string.format("A poacher arrives in %d s", s.poacher.warningLeft)
	elseif s.poacher and s.poacher.active then
		chip.Visible = true
		chipText.Text = "A poacher is in your yard"
	elseif nightStatus.Value ~= "" then
		-- the night's line: a hazard's warning (danger) or rest (calm); raid and poacher come first
		chip.Visible = true
		chipText.Text = nightStatus.Value
	else
		chip.Visible = false
	end
	local calm = not raiding and not s.poacher and nightKind.Value == "calm"
	chip.BackgroundColor3 = if calm then Color3.fromRGB(20, 30, 50) else Color3.fromRGB(40, 16, 18)

	for tier, r in campRows do
		local c = s.camps[tier]
		local price = if c.permit > 0 then "permit " .. c.permit else "free"
		r.label.Text = string.format("Camp %d - %s - %s%s", tier, c.name, price, if c.reason then " - " .. c.reason else "")
		local ready = c.unlocked and c.heatLeft <= 0 and s.essence >= c.permit
		r.button.Text = if not c.unlocked then "Locked" elseif c.heatLeft > 0 then "Alert" else "Enter"
		r.button.BackgroundColor3 = if ready then Color3.fromRGB(150, 90, 40) else DIM
	end
	if s.expandPrice then
		expandRow.label.Text = string.format("Add cage %d of 9 - %d Essence", s.cagesUnlocked + 1, s.expandPrice)
		expandRow.button.Text = "Add"
	else
		expandRow.label.Text = "All nine cages unlocked"
		expandRow.button.Text = "Full"
	end
	rerollRow.button.Text = if s.rerollLeft > 0 then s.rerollLeft .. " s" else "Re-roll"
	statsLabel.Text = string.format("Steals %d - Caught %d - Poachers caught %d", s.stats.steals, s.stats.caught, s.stats.poachersCaught)
	sheetButtons[1].Text = string.format("Laser %d (%d/%d)", s.laserPrice, s.lasers, s.maxLasers)
	sheetButtons[2].Text = string.format("Snare %d (%d/%d)", s.snarePrice, s.snares, s.maxSnares)
end

local lastRaid = false
StateEvent.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	state = s
	local raiding = s.raid ~= nil
	if raiding and not lastRaid then
		huntOpen = false
		sheetCell = nil
	end
	if not s.buildMode then sheetCell = nil end
	lastRaid = raiding
	render()
	applyLayout()
end)

--============================================================================ camera juice

FxEvent.OnClientEvent:Connect(function(kind, data)
	if kind == "openHunt" then
		huntOpen = true
		sheetCell = nil
		applyLayout()
	elseif kind == "buildCell" and type(data) == "table" then
		sheetCell = data
		huntOpen = false
		sheetTitle.Text = string.format("Yard cell %s, %s%s", tostring(data.col), tostring(data.row),
			if data.trap then " - " .. tostring(data.trap) else "")
		applyLayout()
	elseif kind == "caught" then
		FxClient.shake(0.45, 1.4)
		FxClient.flash(DANGER, 0.5, 0.6)
	elseif kind == "escaped" then
		FxClient.fovPunch(12)
		FxClient.flash(GOLD, 0.45, 0.7)
	elseif kind == "poacherWarning" then
		FxClient.flash(DANGER, 0.3, 0.5)
	elseif kind == "bounty" then
		FxClient.flash(GOLD, 0.35, 0.5)
	elseif kind == "grab" then
		FxClient.fovPunch(6)
	end
end)

--============================================================================ responsive layout

function applyLayout()
	local v = camera.ViewportSize
	local effY = effectiveHeight(v.Y)
	layout = Responsive.layout(v.X, effY, UserInputService.TouchEnabled, v.Y)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
	local rootW = v.X / layout.scale
	local usable = Responsive.usableHeight(effY, layout)

	-- top row: readout left, toggles right
	local btnH = touchSize(40)
	local btnW = touchSize(96)
	local visibleToggles = 0
	for _, b in { restToggle, huntToggle, buildToggle, leaveToggle } do
		if b.Visible then visibleToggles += 1 end
		b.Size = UDim2.new(0, if b == leaveToggle then math.max(btnW, touchSize(120)) else btnW, 0, btnH)
	end
	local togglesW = visibleToggles * btnW + math.max(0, visibleToggles - 1) * 6 + (if leaveToggle.Visible then math.max(0, touchSize(120) - btnW) else 0)
	toggles.Size = UDim2.new(0, togglesW, 0, btnH)
	local readoutW = math.clamp(rootW - togglesW - 32, 150, 260)
	readout.Size = UDim2.new(0, readoutW, 0, math.max(52, btnH))
	local topH = math.max(readout.Size.Y.Offset, btnH)

	-- two lines each (a line is MaxTextSize x 1.2 design px), so a long string wraps at full size
	banner.Position = UDim2.new(0, 8, 0, 8 + topH + 2)
	banner.Size = UDim2.new(0, math.min(rootW - 16, 460), 0, if banner.Visible then 36 else 0)
	local y = 8 + topH + 4 + (if banner.Visible then 38 else 0)

	local centreW = math.min(rootW - 16, 600)
	hint.Position = UDim2.new(0.5, 0, 0, y)
	hint.Size = UDim2.new(0, centreW, 0, 42)
	y += 44
	toastLabel.Position = UDim2.new(0.5, 0, 0, y)
	toastLabel.Size = UDim2.new(0, centreW, 0, 40)
	y += 42
	chip.Position = UDim2.new(0.5, 0, 0, y)
	chip.Size = UDim2.new(0, math.min(rootW - 16, 420), 0, 30)
	if chip.Visible then y += 34 end

	-- centre panels start under the top stack and stop above the touch-control band
	local roomDesign = math.max(40, (usable - y * layout.scale) / layout.scale)
	local panelW = math.min(rootW - 16, 460)

	local rowH = touchSize(40)
	local goW = math.max(touchSize(90), 90)
	for _, r in rows do
		r.frame.Size = UDim2.new(1, 0, 0, rowH)
		r.label.Size = UDim2.new(1, -(goW + 8), 1, 0)
		r.button.Size = UDim2.new(0, goW, 1, 0)
	end
	huntTitle.Size = UDim2.new(1, 0, 0, 26)
	lairTitle.Size = UDim2.new(1, 0, 0, 24)
	statsLabel.Size = UDim2.new(1, 0, 0, 20)
	local contentH = 26 + 24 + 20 + #rows * rowH + (#rows + 3) * 5 + 16
	huntPanel.Position = UDim2.new(0.5, 0, 0, y)
	huntPanel.Size = UDim2.new(0, panelW, 0, math.min(contentH, math.floor(roomDesign)))
	huntPanel.Visible = huntOpen and state ~= nil and state.raid == nil
	refreshCanvas()

	local sheetW = math.min(rootW - 16, 420)
	local sBtnH = touchSize(40)
	sheetTitle.Position = UDim2.new(0, 10, 0, 6)
	sheetTitle.Size = UDim2.new(1, -20, 0, 24)
	-- one row of four, so the sheet stays short enough for a landscape phone's usable height
	local gap = 8
	local bw = math.floor((sheetW - gap * 5) / 4)
	for i, b in sheetButtons do
		b.Size = UDim2.new(0, bw, 0, sBtnH)
		b.Position = UDim2.new(0, gap + (i - 1) * (bw + gap), 0, 36)
	end
	local sheetH = 36 + sBtnH + 10
	buildSheet.Position = UDim2.new(0.5, 0, 0, y)
	buildSheet.Size = UDim2.new(0, sheetW, 0, math.min(sheetH, math.floor(roomDesign)))
	buildSheet.Visible = sheetCell ~= nil and state ~= nil and state.buildMode == true and state.raid == nil
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
-- the night's label and status line change the chip (and so the layout under it)
local function nightChanged()
	render()
	applyLayout()
end
restLabel:GetPropertyChangedSignal("Value"):Connect(nightChanged)
nightStatus:GetPropertyChangedSignal("Value"):Connect(nightChanged)
nightKind:GetPropertyChangedSignal("Value"):Connect(nightChanged)
-- A touch device can appear without the window changing size (a touch laptop). The layout is
-- cosmetic and the readout is not, so this sits last and in a pcall.
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
