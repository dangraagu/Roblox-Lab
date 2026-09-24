-- LOST & FOUND DEPOT — client HUD. Lands in StarterPlayerScripts.
--
-- Display only. The server owns every sort, every price and every position; this file draws what
-- the State remote says and sends exactly two things back: which carried slot is selected
-- (Select) and a typed code (Redeem). Picking, depositing, buying and the Back Room door are
-- in-world ClickDetectors and ProximityPrompts, not buttons here.
--
-- Phone first (docs/mobile-ui-brief.md):
--  * a root Frame owns the UIScale (a UIScale on a ScreenGui does nothing), sized 1/scale so the
--    scaled root still spans the screen;
--  * every tappable control is sized in SCREEN space (>= 44 px on touch) via touchSize;
--  * nothing tappable in the bottom-left 35% or bottom-right 25%: the hotbar sits in the centre
--    40% band, above Roblox's touch controls;
--  * drawers open from top-edge toggles, at most one centre panel at a time;
--  * everything re-lays-out on Camera.ViewportSize and on UserInputService.TouchEnabled.
--
-- Text is ASCII plus the glyphs photographed rendering in Studio (DESIGN.md §13.4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
-- The HUD is the ONLY listener on State; it passes every payload to the wings (StateCache.luau says why).
local StateCache = require(ReplicatedStorage:WaitForChild("StateCache"))

local remotes = ReplicatedStorage:WaitForChild("DepotRemotes")
local StateEvent = remotes:WaitForChild("State")
local NoticeEvent = remotes:WaitForChild("Notice")
local SceneEvent = remotes:WaitForChild("Scene")
local SelectEvent = remotes:WaitForChild("Select")
local RedeemEvent = remotes:WaitForChild("Redeem")

local INK = Color3.fromRGB(245, 245, 245)
local DIM = Color3.fromRGB(170, 172, 182)
local PANEL = Color3.fromRGB(26, 28, 34)
local EDGE = Color3.fromRGB(214, 186, 120)
local GOLD = Color3.fromRGB(255, 214, 110)
local GOOD = Color3.fromRGB(80, 220, 110)
local BAD = Color3.fromRGB(255, 90, 90)
local MAX_CODE = 20

local gui = Instance.new("ScreenGui")
gui.Name = "DepotHud"
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

local camera = workspace.CurrentCamera
if not camera then
	repeat
		task.wait()
	until workspace.CurrentCamera
	camera = workspace.CurrentCamera
end

-- IgnoreGuiInset is false, so the drawable height is the viewport minus the topbar inset.
local function effectiveHeight(vy: number): number
	if vy <= 0 or gui.IgnoreGuiInset then
		return vy
	end
	return math.max(1, vy - GuiService:GetGuiInset().Y)
end

local layout = Responsive.layout(camera.ViewportSize.X, effectiveHeight(camera.ViewportSize.Y),
	UserInputService.TouchEnabled, camera.ViewportSize.Y)

local MIN_TAP = 44
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then
		return designPx
	end
	return math.ceil(math.max(designPx, MIN_TAP) / layout.scale)
end

local function frame(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	f.Parent = parent
	FxClient.theme(f, { corner = 10, stroke = EDGE, strokeThickness = 1.5 })
	return f
end

local function label(name: string, parent: Instance, text: string, font: Enum.Font?, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color or INK
	l.Text = text
	l.Parent = parent
	return l
end

local function button(name: string, parent: Instance, text: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = INK
	b.Text = text
	b.Parent = parent
	FxClient.theme(b, { corner = 8 })
	return b
end

local function capText(l: TextLabel | TextButton | TextBox, px: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = px
	c.Parent = l
end

--============================================================================ top: cash, clock, toggles

local cashPanel = frame("CashPanel", root)
local cashLabel = label("Cash", cashPanel, "CASH 0", Enum.Font.GothamBlack, GOLD)
cashLabel.Position = UDim2.fromScale(0.06, 0.06)
cashLabel.Size = UDim2.fromScale(0.88, 0.58)
local titleLabel = label("Title", cashPanel, "SORTER", Enum.Font.GothamMedium, DIM)
titleLabel.Position = UDim2.fromScale(0.06, 0.64)
titleLabel.Size = UDim2.fromScale(0.88, 0.32)

local clockPanel = frame("ClockPanel", root)
local clockLabel = label("Clock", clockPanel, "5:30", Enum.Font.GothamBlack)
clockLabel.Position = UDim2.fromScale(0.04, 0.04)
clockLabel.Size = UDim2.fromScale(0.44, 0.56)
local clockSub = label("ClockSub", clockPanel, "", Enum.Font.GothamMedium, DIM)
clockSub.Position = UDim2.fromScale(0.04, 0.62)
clockSub.Size = UDim2.fromScale(0.92, 0.32)
local clearedLabel = label("Cleared", clockPanel, "CLEARED 0/30", Enum.Font.GothamBold)
clearedLabel.Position = UDim2.fromScale(0.5, 0.06)
clearedLabel.Size = UDim2.fromScale(0.46, 0.26)
local barBack = Instance.new("Frame")
barBack.Name = "ClearedBar"
barBack.Position = UDim2.fromScale(0.5, 0.34)
barBack.Size = UDim2.fromScale(0.46, 0.1)
barBack.BackgroundColor3 = Color3.fromRGB(60, 62, 70)
barBack.BorderSizePixel = 0
barBack.Parent = clockPanel
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = GOOD
barFill.BorderSizePixel = 0
barFill.Parent = barBack
local comboLabel = label("Combo", clockPanel, "", Enum.Font.GothamBlack, GOLD)
comboLabel.Position = UDim2.fromScale(0.5, 0.46)
comboLabel.Size = UDim2.fromScale(0.46, 0.16)

local toggles = Instance.new("Frame")
toggles.Name = "Toggles"
toggles.BackgroundTransparency = 1
toggles.BorderSizePixel = 0
toggles.Parent = root
local toggleButtons: { [string]: TextButton } = {}
for i, key in { "manual", "upgrades", "codes" } do
	-- UPGRADES shows prices only; buying happens at the locker in the world (DESIGN.md §13.3)
	local text = ({ manual = "MANUAL", upgrades = "UPGRADES", codes = "CODES" })[key]
	local b = button("Toggle_" .. key, toggles, text)
	b.LayoutOrder = i
	capText(b, 16)
	toggleButtons[key] = b
end
-- The MANUAL button pulses once when the tutorial hands over to it (DESIGN.md §12).
local manualPulse = Instance.new("UIStroke")
manualPulse.Name = "Pulse"
manualPulse.Color = GOLD
manualPulse.Thickness = 3
manualPulse.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
manualPulse.Enabled = false
manualPulse.Parent = toggleButtons.manual

local memoBanner = label("Memo", root, "", Enum.Font.GothamBold, GOLD)
memoBanner.AnchorPoint = Vector2.new(0.5, 0)
capText(memoBanner, 18)
local hintLabel = label("Hint", root, "", Enum.Font.GothamMedium, INK)
hintLabel.AnchorPoint = Vector2.new(0.5, 0)
capText(hintLabel, 16)
local toastLabel = label("Toast", root, "", Enum.Font.GothamBold, GOLD)
toastLabel.AnchorPoint = Vector2.new(0.5, 0)
capText(toastLabel, 18)
-- The deposit stamp (DESIGN.md §5.1, §12): a correct sort gets a visual stamp, not only a number.
local stampLabel = label("Stamp", root, "FILED", Enum.Font.GothamBlack, GOOD)
stampLabel.AnchorPoint = Vector2.new(0.5, 0.5)
stampLabel.Rotation = -8
stampLabel.Visible = false
capText(stampLabel, 34)
do
	local st = Instance.new("UIStroke")
	st.Name = "Ink"
	st.Color = Color3.fromRGB(20, 60, 30)
	st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Parent = stampLabel
end
local saveWarn = label("SaveWarn", root, "", Enum.Font.GothamBold, BAD)
saveWarn.AnchorPoint = Vector2.new(0, 0)
saveWarn.Visible = false
capText(saveWarn, 13)
for _, l in { memoBanner, hintLabel, toastLabel } do
	local c = Instance.new("UISizeConstraint")
	c.MaxSize = Vector2.new(560, math.huge)
	c.Parent = l
end

local loadingLabel = label("Loading", root, "Unpacking your cart...", Enum.Font.GothamBlack, INK)
loadingLabel.AnchorPoint = Vector2.new(0.5, 0.5)
loadingLabel.Position = UDim2.fromScale(0.5, 0.4)
loadingLabel.Size = UDim2.new(0.6, 0, 0, 40)
capText(loadingLabel, 28)

--============================================================================ hotbar

local hotbar = Instance.new("Frame")
hotbar.Name = "Hotbar"
hotbar.BackgroundTransparency = 1
hotbar.BorderSizePixel = 0
hotbar.Parent = root
local slotButtons: { TextButton } = {}
local slotTags: { TextLabel } = {}
local slotNames: { TextLabel } = {}
for i = 1, 5 do
	local b = button("Slot_" .. i, hotbar, "")
	b.BackgroundColor3 = PANEL
	b.Text = ""
	local stroke = b:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Name = "Selected"
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Enabled = false
	stroke.Parent = b
	local t = label("TagText", b, "", Enum.Font.GothamBlack)
	t.RichText = true
	t.Position = UDim2.fromScale(0.05, 0.08)
	t.Size = UDim2.fromScale(0.9, 0.5)
	local n = label("ItemName", b, "", Enum.Font.GothamMedium, DIM)
	n.Position = UDim2.fromScale(0.05, 0.6)
	n.Size = UDim2.fromScale(0.9, 0.32)
	slotButtons[i] = b
	slotTags[i] = t
	slotNames[i] = n
	b.Activated:Connect(function()
		SelectEvent:FireServer(i)
	end)
end

--============================================================================ centre panels

local centre: string? = nil -- "manual" | "upgrades" | "codes" | "summary" | "note" | nil
-- The MANUAL drawer the HUD opened by itself for a new layer closes at the shift's first pickup;
-- one the player opened stays open (REVIEW-1 R2-5).
local manualAutoOpened = false
-- The Back Room note's camera flight, so ANY way the note leaves the screen can end it.
local noteTween: Tween? = nil

-- MANUAL: a ScrollingFrame of monospace lines; the lines a new stage added are marked NEW.
local manualPanel = Instance.new("ScrollingFrame")
manualPanel.Name = "ManualDrawer"
manualPanel.BackgroundColor3 = PANEL
manualPanel.BackgroundTransparency = 0.05
manualPanel.BorderSizePixel = 0
manualPanel.ScrollBarThickness = 6
manualPanel.ScrollingDirection = Enum.ScrollingDirection.Y
manualPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
manualPanel.Visible = false
manualPanel.Parent = root
FxClient.theme(manualPanel, { corner = 10, stroke = EDGE, strokeThickness = 1.5 })
do
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 10)
	p.PaddingRight = UDim.new(0, 10)
	p.PaddingTop = UDim.new(0, 8)
	p.PaddingBottom = UDim.new(0, 8)
	p.Parent = manualPanel
end
local manualList = Instance.new("UIListLayout")
manualList.SortOrder = Enum.SortOrder.LayoutOrder
manualList.Padding = UDim.new(0, 2)
manualList.Parent = manualPanel
local MANUAL_ROW = 18
local function refreshManualCanvas()
	-- AbsoluteContentSize is SCREEN px and CanvasSize is design px: divide by the scale, or a
	-- phone loses the bottom of the manual (a shipped defect in three sibling games).
	local content = manualList.AbsoluteContentSize.Y
	manualPanel.CanvasSize = UDim2.new(0, 0, 0, math.ceil(content / math.max(uiScale.Scale, 0.01)) + 16)
end
manualList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshManualCanvas)

-- UPGRADES: read-only. Buying happens at the locker in the world.
local upgradesPanel = frame("UpgradesDrawer", root)
upgradesPanel.Visible = false
local cartRow = label("CartRow", upgradesPanel, "", Enum.Font.GothamBold)
local shoesRow = label("ShoesRow", upgradesPanel, "", Enum.Font.GothamBold)
local lockerRow = label("LockerRow", upgradesPanel, "Buy at the locker by your spawn.", Enum.Font.GothamMedium, DIM)
for i, l in { cartRow, shoesRow, lockerRow } do
	l.Position = UDim2.new(0.05, 0, (i - 1) / 3 + 0.03, 0)
	l.Size = UDim2.new(0.9, 0, 1 / 3 - 0.06, 0)
	l.TextXAlignment = Enum.TextXAlignment.Left
	capText(l, 18)
end

-- CODES
local codesPanel = frame("CodesDrawer", root)
codesPanel.Visible = false
local codeBox = Instance.new("TextBox")
codeBox.Name = "CodeBox"
codeBox.BackgroundColor3 = Color3.fromRGB(16, 17, 21)
codeBox.BorderSizePixel = 0
codeBox.ClearTextOnFocus = false
codeBox.PlaceholderText = "Type a code"
codeBox.Text = ""
codeBox.Font = Enum.Font.GothamBold
codeBox.TextScaled = true
codeBox.TextColor3 = INK
codeBox.Parent = codesPanel
capText(codeBox, 20)
local redeemButton = button("RedeemButton", codesPanel, "REDEEM")
capText(redeemButton, 18)
local codeStatus = label("CodeStatus", codesPanel, "", Enum.Font.GothamMedium, DIM)
capText(codeStatus, 14)
codeBox:GetPropertyChangedSignal("Text"):Connect(function()
	if #codeBox.Text > MAX_CODE then
		codeBox.Text = string.sub(codeBox.Text, 1, MAX_CODE)
	end
end)
redeemButton.Activated:Connect(function()
	local text = codeBox.Text
	if text == "" then
		codeStatus.Text = "Type a code first."
		return
	end
	RedeemEvent:FireServer(string.sub(text, 1, MAX_CODE))
end)

-- SUMMARY
local summaryPanel = frame("SummaryCard", root)
summaryPanel.Visible = false
local summaryTitle = label("Title", summaryPanel, "", Enum.Font.GothamBlack, GOLD)
local summaryBody = label("Body", summaryPanel, "", Enum.Font.GothamMedium, INK)
summaryBody.TextYAlignment = Enum.TextYAlignment.Top
local summaryOk = button("OkButton", summaryPanel, "OK")
capText(summaryOk, 20)

-- The note card (its text arrives only in a Scene payload, only for the player who unlocked it)
local notePanel = frame("NoteCard", root)
notePanel.Visible = false
-- One paragraph (or two short ones) per page, scaled to fit, with NEXT then CLOSE. A 14-line note
-- in a scroll box is a wall of 7-px text on a 360-px phone; a page at a time is readable.
local noteText = label("NoteText", notePanel, "", Enum.Font.Merriweather, INK)
noteText.TextWrapped = true
noteText.TextXAlignment = Enum.TextXAlignment.Left
noteText.TextYAlignment = Enum.TextYAlignment.Top
capText(noteText, 22)
local notePageLabel = label("NotePage", notePanel, "", Enum.Font.GothamMedium, DIM)
capText(notePageLabel, 14)
local noteClose = button("CloseButton", notePanel, "CLOSE")
capText(noteClose, 18)
local notePages: { string } = {}
local notePage = 1

--============================================================================ state

local lastState: any = nil
-- The clock counts down from what the server said was left, by the local time since that push, so
-- no two clocks ever have to agree.
local receivedLeft = 330
local receivedAt = 0
local newLayerShown = 0
local lastShiftState = nil

local function localClock(): number
	local ok, t = pcall(function()
		return (workspace :: any):GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return tick()
end

local function fmtClock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local applyLayout -- forward

local function setCentre(which: string?)
	-- REVIEW-1 R2-4: the note flies the camera (Scriptable). Only its own CLOSE button used to give
	-- it back, so a top-edge toggle or a shift summary that replaced the note left the player's
	-- camera frozen, into the next shift. Whatever replaces the note gives the camera back.
	if centre == "note" and which ~= "note" then
		if noteTween then
			noteTween:Cancel()
			noteTween = nil
		end
		camera.CameraType = Enum.CameraType.Custom
	end
	if which ~= "manual" then
		manualAutoOpened = false
	end
	centre = which
	manualPanel.Visible = which == "manual"
	upgradesPanel.Visible = which == "upgrades"
	codesPanel.Visible = which == "codes"
	summaryPanel.Visible = which == "summary"
	notePanel.Visible = which == "note"
	for key, b in toggleButtons do
		b.BackgroundColor3 = if which == key then Color3.fromRGB(70, 130, 90) else Color3.fromRGB(48, 52, 62)
	end
	applyLayout()
end

for key, b in toggleButtons do
	b.Activated:Connect(function()
		setCentre(if centre == key then nil else key)
	end)
end
summaryOk.Activated:Connect(function()
	setCentre(nil)
end)
local function showNotePage(page: number)
	notePage = math.clamp(page, 1, math.max(1, #notePages))
	noteText.Text = notePages[notePage] or ""
	notePageLabel.Text = string.format("%d / %d", notePage, math.max(1, #notePages))
	noteClose.Text = if notePage < #notePages then "NEXT" else "CLOSE"
end

noteClose.Activated:Connect(function()
	if notePage < #notePages then
		showNotePage(notePage + 1)
		return
	end
	setCentre(nil) -- gives the camera back
end)

-- Split at blank lines; a paragraph under 40 characters (the title, the signature) rides along
-- with its neighbour instead of taking a page to itself.
local function paginate(lines: { string }): { string }
	local paras, current = {}, {}
	for _, line in lines do
		if line == "" then
			if #current > 0 then
				table.insert(paras, table.concat(current, " "))
				current = {}
			end
		else
			table.insert(current, line)
		end
	end
	if #current > 0 then
		table.insert(paras, table.concat(current, " "))
	end
	local pages = {}
	local carry = nil
	for i, p in paras do
		if carry then
			p = carry .. "\n\n" .. p
			carry = nil
		end
		if #p < 40 and i < #paras then
			carry = p
		elseif #p < 40 and #pages > 0 then
			pages[#pages] = pages[#pages] .. "\n\n" .. p
		else
			table.insert(pages, p)
		end
	end
	return pages
end

local manualSignature = ""
local function rebuildManual(sections: any, stage: number)
	-- State arrives after every pick and deposit; the manual only changes with the stage or memo.
	local parts = { tostring(stage) }
	for _, section in sections or {} do
		table.insert(parts, table.concat(section.lines, "\n"))
	end
	local signature = table.concat(parts, "\0")
	if signature == manualSignature then
		return
	end
	manualSignature = signature
	for _, c in manualPanel:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local order = 0
	for _, section in sections or {} do
		for _, line in section.lines do
			order += 1
			local isNew = section.layer > 1 and section.layer == stage
			local l = label("Line_" .. order, manualPanel, (if isNew then "NEW  " else "     ") .. line, Enum.Font.RobotoMono,
				if isNew then GOLD else INK)
			l.TextScaled = false
			l.TextSize = 13
			l.TextWrapped = true
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Size = UDim2.new(1, 0, 0, MANUAL_ROW)
			l.LayoutOrder = order
		end
	end
	refreshManualCanvas()
end

-- How a deposit is made on THIS device. A phone has no E key: its players tap the prompt's Drop
-- button, and the tutorial used to tell them to "press E" (REVIEW-1 pass 3, player-path finding 4).
-- Read from the layout (controlPad), like every other touch decision in this file.
local function dropVerb(): string
	return if layout.controlPad > 0 then "tap Drop" else "press E"
end
local function dropMarkerText(): string
	return if layout.controlPad > 0 then "DROP HERE" else "PRESS E HERE"
end

-- The server's tutorial step follows the SELECTED item, because E deposits the selected item
-- (REVIEW-1 R2-2): "sort" always names the selected one, "select" asks for a hotbar tap first.
local function tutorialHint(t: any, st: any): string
	if t == nil then
		return ""
	end
	if t.step == "select" then
		return "Tap the " .. t.item .. " in your hotbar, then take it to " .. t.bin .. "."
	end
	if t.step == "pick" then
		local sh = st and st.shift
		if sh and #sh.carried >= (st.carry or 2) then
			return "Hands full: take what you carry to its bin, then tap the " .. t.item .. "."
		end
		if t.index == 1 then
			return "Tap the " .. t.item .. " on the tray."
		end
		return "Now the " .. t.item .. ". Read its TAG, not the " .. string.lower(t.item) .. ": "
			.. tostring(t.letter) .. " means " .. t.bin .. "."
	end
	if t.index == 1 then
		return tostring(t.letter) .. " means " .. t.bin .. ". Walk to the " .. t.bin .. " bin and " .. dropVerb() .. "."
	end
	return "Read the TAG, not the " .. string.lower(t.item) .. ": " .. tostring(t.letter) .. " means " .. t.bin
		.. ". Walk to that bin and " .. dropVerb() .. "."
end

-- Tutorial markers: a floating label over the target, in PlayerGui so no other client sees it.
local markerItem = Instance.new("BillboardGui")
markerItem.Name = "TutorialItemMarker"
markerItem.Size = UDim2.fromScale(3, 1)
markerItem.StudsOffset = Vector3.new(0, 4.6, 0)
markerItem.AlwaysOnTop = true
-- This script runs once; a marker that reset on respawn would be gone for the rest of the tutorial.
markerItem.ResetOnSpawn = false
markerItem.Enabled = false
markerItem.Parent = gui.Parent
label("Text", markerItem, "TAP HERE", Enum.Font.GothamBlack, GOLD).Size = UDim2.fromScale(1, 1)
local markerBin = Instance.new("BillboardGui")
markerBin.Name = "TutorialBinMarker"
markerBin.Size = UDim2.fromScale(5, 1.2)
markerBin.StudsOffset = Vector3.new(0, 9.5, 0)
markerBin.AlwaysOnTop = true
markerBin.ResetOnSpawn = false
markerBin.Enabled = false
markerBin.Parent = gui.Parent
local markerBinText = label("Text", markerBin, "PRESS E HERE", Enum.Font.GothamBlack, GOLD)
markerBinText.Size = UDim2.fromScale(1, 1)

-- The target bin's light pulses while the tutorial points at it (DESIGN.md §12). Client-side: the
-- change never replicates, so no other player sees which bin a newcomer is heading for.
local pulseLight: PointLight? = nil
local pulseBase = 0
local pulseTween: Tween? = nil
local function stopBinPulse()
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	if pulseLight then
		pulseLight.Brightness = pulseBase
		pulseLight = nil
	end
end
local function startBinPulse(light: PointLight?)
	if light == pulseLight then
		return
	end
	stopBinPulse()
	if light == nil then
		return
	end
	pulseLight = light
	pulseBase = light.Brightness
	pcall(function()
		pulseTween = TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Brightness = pulseBase * 3 })
		pulseTween:Play()
	end)
end

local function updateMarkers(st: any)
	markerItem.Enabled = false
	markerBin.Enabled = false
	markerBinText.Text = dropMarkerText()
	local t = st and st.shift and st.shift.tutorial
	local bays = workspace:FindFirstChild("Bays")
	local bay = bays and st.bayName and bays:FindFirstChild(st.bayName)
	if t == nil or bay == nil then
		stopBinPulse()
		return
	end
	local pulseTarget = nil
	if t.step == "pick" and t.slot then
		local slot = bay:FindFirstChild("Slot_" .. t.slot)
		if slot then
			markerItem.Adornee = slot
			markerItem.Enabled = true
		end
	elseif t.step == "sort" then
		for k = 1, 6 do
			local bin = bay:FindFirstChild("Bin_" .. k)
			local sign = bin and bin:FindFirstChild("Sign")
			local signLabel = sign and sign:FindFirstChild("SignGui") and sign.SignGui:FindFirstChild("Label")
			if signLabel and signLabel.Text == t.bin then
				markerBin.Adornee = bin:FindFirstChild("Base")
				markerBin.Enabled = true
				local base = bin:FindFirstChild("Base")
				pulseTarget = base and base:FindFirstChild("BinLight")
			end
		end
	end
	startBinPulse(pulseTarget)
end

local function render(st: any)
	lastState = st
	local loaded = st.loaded == true
	loadingLabel.Visible = not loaded
	cashPanel.Visible = loaded
	clockPanel.Visible = loaded
	toggles.Visible = loaded
	if not loaded then
		hotbar.Visible = false
		applyLayout()
		return
	end
	cashLabel.Text = "CASH " .. tostring(st.cash)
	titleLabel.Text = if st.endingSeen then "DEPOT KEEPER" else "SHIFT " .. tostring((st.shifts or 0) + 1)
	saveWarn.Visible = st.canSave == false
	saveWarn.Text = "Progress is NOT saving this session"

	local sh = st.shift
	if sh then
		clearedLabel.Text = string.format("CLEARED %d/%d", sh.cleared, sh.total)
		barFill.Size = UDim2.fromScale(math.clamp(sh.cleared / math.max(sh.total, 1), 0, 1), 1)
		comboLabel.Text = if sh.combo >= 2 then "COMBO x" .. sh.combo else ""
		memoBanner.Text = if sh.memo then "TODAY'S MEMO: " .. sh.memo else ""
		receivedLeft = sh.secondsLeft
		receivedAt = localClock()
		if sh.state == "ARMED" then
			clockSub.Text = "starts when you pick something up"
		elseif sh.state == "RUNNING" then
			clockSub.Text = ""
		else
			clockSub.Text = "next cart rolling in"
		end
		clockLabel.Text = fmtClock(sh.secondsLeft)
		hintLabel.Text = tutorialHint(sh.tutorial, st)

		for i = 1, 5 do
			local entry = sh.carried[i]
			slotButtons[i].Visible = i <= (st.carry or 2)
			slotTags[i].Text = if entry then entry.rich else ""
			slotNames[i].Text = if entry then entry.name else "empty"
			local stroke = slotButtons[i]:FindFirstChild("Selected") :: UIStroke?
			if stroke then
				stroke.Enabled = entry ~= nil and sh.selected == i
			end
		end
		hotbar.Visible = true

		-- the summary card appears when a shift ends, and goes at the next pickup
		if sh.state == "SUMMARY" and lastShiftState ~= "SUMMARY" and sh.summary then
			local s = sh.summary
			summaryTitle.Text = if s.perfect then "\u{2605} PERFECT SHIFT \u{2605}"
				elseif s.timedOut then "TIME!" else "SHIFT CLEARED"
			local lines = {
				string.format("Sorted %d / %d", s.sorted, s.total),
				string.format("Misfiles %d", s.misfiles),
				string.format("Pay +%d%s", s.pay, if s.bonus and s.bonus > 0 then " (bonus " .. s.bonus .. ")" else ""),
				string.format("Backlog +%d   (%d / %d)", s.backlogGained, st.backlog, st.backlogSize),
			}
			if s.best and s.best > 0 then
				table.insert(lines, "Best Perfect Shift " .. fmtClock(s.best))
			end
			summaryBody.Text = table.concat(lines, "\n")
			setCentre("summary")
			FxClient.popIn(summaryPanel)
		elseif sh.state == "RUNNING" and centre == "summary" then
			setCentre(nil)
		elseif sh.state == "RUNNING" and centre == "manual" and manualAutoOpened then
			-- the drawer the HUD opened for a new layer was for reading before the clock started
			setCentre(nil)
		end
		lastShiftState = sh.state

		-- a new layer opens the manual by itself, once
		if st.newLayer and st.newLayer ~= newLayerShown and sh.state == "ARMED" then
			newLayerShown = st.newLayer
			rebuildManual(st.manual, st.stage)
			setCentre("manual")
			manualAutoOpened = true
		end
	end
	rebuildManual(st.manual, st.stage)

	local nextCart = if st.prices and st.prices.cart then string.format("carry %d -> %d for %d", st.carry, st.nextCarry, st.prices.cart)
		else "carry " .. tostring(st.carry) .. " (max)"
	local nextShoes = if st.prices and st.prices.shoes then string.format("speed %d -> %d for %d", st.walkSpeed, st.nextSpeed, st.prices.shoes)
		else "speed " .. tostring(st.walkSpeed) .. " (max)"
	cartRow.Text = "CART   " .. nextCart
	shoesRow.Text = "SHOES  " .. nextShoes

	updateMarkers(st)
	applyLayout()
end

StateEvent.OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then
		return
	end
	StateCache.set(st)
	render(st)
end)

local toastSerial = 0
local stampSerial = 0
NoticeEvent.OnClientEvent:Connect(function(n)
	if type(n) ~= "table" or type(n.text) ~= "string" then
		return
	end
	toastSerial += 1
	local mine = toastSerial
	local text: string = n.text
	toastLabel.Text = text
	toastLabel.TextColor3 = if n.kind == "misfile" or n.kind == "refused" then BAD elseif n.kind == "ok" or n.kind == "perfect" then GOOD else GOLD
	if n.kind == "ok" and n.amount then
		FxClient.fovPunch(3)
		stampSerial += 1
		local stampMine = stampSerial
		stampLabel.Text = if n.firstTry == false then "RE-FILED" else "FILED"
		stampLabel.Visible = true
		FxClient.popIn(stampLabel, UDim2.fromOffset(0, -10), 0.15)
		task.delay(0.9, function()
			if stampSerial == stampMine then
				stampLabel.Visible = false
			end
		end)
	elseif n.kind == "misfile" then
		FxClient.flash(BAD, 0.35, 0.5)
		FxClient.shake(0.25, 0.35)
	elseif n.kind == "perfect" then
		FxClient.flash(GOOD, 0.4, 0.7)
		FxClient.shake(0.3, 0.3)
	elseif n.kind == "tutorial" then
		manualPulse.Enabled = true
		pcall(function()
			TweenService:Create(manualPulse, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true),
				{ Thickness = 6 }):Play()
		end)
		task.delay(4, function()
			manualPulse.Enabled = false
			manualPulse.Thickness = 3
		end)
	end
	if string.find(text, "cash from", 1, true) then
		codeStatus.Text = text
		codeBox.Text = ""
	elseif codesPanel.Visible then
		codeStatus.Text = text
	end
	task.delay(if n.kind == "misfile" then 5 else 3, function()
		if toastSerial == mine then
			toastLabel.Text = ""
		end
	end)
end)

SceneEvent.OnClientEvent:Connect(function(scene)
	if type(scene) ~= "table" or type(scene.lines) ~= "table" then
		return
	end
	local lines = {}
	for _, l in scene.lines do
		if type(l) == "string" then
			table.insert(lines, l)
		end
	end
	notePages = paginate(lines)
	showNotePage(1)
	setCentre("note")
	FxClient.popIn(notePanel)
	local from, to = scene.camFrom, scene.camTo
	if type(from) == "table" and type(to) == "table" then
		local a = Vector3.new(from[1], from[2], from[3])
		local b = Vector3.new(to[1], to[2], to[3])
		pcall(function()
			if noteTween then
				noteTween:Cancel()
			end
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(a, b)
			noteTween = TweenService:Create(camera, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CFrame = CFrame.lookAt(b + (b - a).Unit * -2, b + (b - a).Unit) })
			noteTween:Play()
		end)
	end
end)

-- The clock counts down on its own between State pushes.
task.spawn(function()
	while true do
		task.wait(0.25)
		local st = lastState
		local sh = st and st.shift
		if sh and sh.state == "RUNNING" then
			local left = receivedLeft - (localClock() - receivedAt)
			clockLabel.Text = fmtClock(left)
			clockLabel.TextColor3 = if left <= 30 then BAD else INK
		else
			clockLabel.TextColor3 = INK
		end
	end
end)

--============================================================================ layout

applyLayout = function()
	local v = camera.ViewportSize
	if v.X <= 0 or v.Y <= 0 then
		return
	end
	local effY = effectiveHeight(v.Y)
	layout = Responsive.layout(v.X, effY, UserInputService.TouchEnabled, v.Y)
	local sc = layout.scale
	uiScale.Scale = sc
	root.Size = UDim2.fromScale(1 / sc, 1 / sc)
	-- a device can gain or lose touch without re-rendering: the deposit wording follows it here
	if lastState and lastState.shift then
		hintLabel.Text = tutorialHint(lastState.shift.tutorial, lastState)
	end
	markerBinText.Text = dropMarkerText()

	local rootW = v.X / sc
	local rootH = effY / sc
	local padDesign = layout.controlPad / sc
	local M = 10
	local GAP = 6

	-- top row
	local toggleW, toggleH = touchSize(80), touchSize(34)
	local togglesW = 3 * toggleW + 2 * GAP
	local cashW, cashH = 150, 46
	local clockW, clockH = 200, 64
	cashPanel.Position = UDim2.fromOffset(M, M)
	cashPanel.Size = UDim2.fromOffset(cashW, cashH)
	toggles.Position = UDim2.new(1, -M - togglesW, 0, M)
	toggles.Size = UDim2.fromOffset(togglesW, toggleH)
	local i = 0
	for _, key in { "manual", "upgrades", "codes" } do
		local b = toggleButtons[key]
		b.Position = UDim2.fromOffset(i * (toggleW + GAP), 0)
		b.Size = UDim2.fromOffset(toggleW, toggleH)
		i += 1
	end
	local left = rootW / 2 - clockW / 2
	local single = left >= M + cashW + 8 and rootW / 2 + clockW / 2 <= rootW - M - togglesW - 8
	local topBottom
	if single then
		clockPanel.Position = UDim2.new(0.5, -clockW / 2, 0, M)
		topBottom = M + math.max(toggleH, clockH, cashH)
	else
		local rowOne = math.max(toggleH, cashH)
		clockPanel.Position = UDim2.new(0.5, -clockW / 2, 0, M + rowOne + GAP)
		topBottom = M + rowOne + GAP + clockH
	end
	clockPanel.Size = UDim2.fromOffset(clockW, clockH)
	saveWarn.Position = UDim2.fromOffset(M, M + cashH + 2)
	saveWarn.Size = UDim2.fromOffset(cashW, 16)

	memoBanner.Position = UDim2.new(0.5, 0, 0, topBottom + 4)
	memoBanner.Size = UDim2.new(0.9, 0, 0, 24)
	hintLabel.Position = UDim2.new(0.5, 0, 0, topBottom + 30)
	hintLabel.Size = UDim2.new(0.9, 0, 0, 22)
	toastLabel.Position = UDim2.new(0.5, 0, 0, topBottom + 54)
	toastLabel.Size = UDim2.new(0.9, 0, 0, 24)
	stampLabel.Position = UDim2.new(0.5, 0, 0, topBottom + 54 + 24 + 34)
	stampLabel.Size = UDim2.fromOffset(200, 50)
	local textBottom = topBottom + 80

	-- hotbar: the centre 40% band, above the touch controls
	local carry = math.clamp((lastState and lastState.carry) or 2, 1, 5)
	local slotH = touchSize(56)
	local bandW = v.X * 0.4 / sc
	local minSlotW = if layout.controlPad > 0 then math.ceil(MIN_TAP / sc) else 70
	local slotW = math.min(110, math.floor((bandW - GAP * (carry - 1)) / carry))
	local perRow = carry
	if slotW < minSlotW then
		slotW = minSlotW
		perRow = math.max(1, math.floor((bandW + GAP) / (slotW + GAP)))
	end
	local rows = math.ceil(carry / perRow)
	local cols = math.min(carry, perRow)
	local barW = cols * slotW + (cols - 1) * GAP
	local barH = rows * slotH + (rows - 1) * GAP
	local barTop = rootH - M - padDesign - barH
	hotbar.Size = UDim2.fromOffset(barW, barH)
	hotbar.Position = UDim2.new(0.5, -barW / 2, 0, barTop)
	for k = 1, 5 do
		local r = (k - 1) // perRow
		local c = (k - 1) % perRow
		slotButtons[k].Position = UDim2.fromOffset(c * (slotW + GAP), r * (slotH + GAP))
		slotButtons[k].Size = UDim2.fromOffset(slotW, slotH)
	end

	-- the centre panel region
	local regionTop, regionBottom
	local crowded = layout.compact and centre ~= nil
	if crowded then
		-- a phone has no room for a drawer AND the text rows AND the hotbar: an open drawer takes
		-- the middle of the screen and the memo, hint and hotbar step aside until it is closed.
		-- THE TOAST DOES NOT: it is how a refusal or a misfile explains itself, and hiding it made
		-- both silent (REVIEW-1 R2-5). It takes the first text row, and the drawer starts below it.
		toastLabel.Position = UDim2.new(0.5, 0, 0, topBottom + 4)
		regionTop = topBottom + 4 + 24 + GAP
		regionBottom = rootH - M - padDesign
	else
		regionTop = textBottom
		regionBottom = barTop - GAP
	end
	local loaded = lastState ~= nil and lastState.loaded == true
	hotbar.Visible = loaded and lastState.shift ~= nil and not crowded
	memoBanner.Visible = not crowded
	hintLabel.Visible = not crowded
	toastLabel.Visible = true
	local regionH = math.max(60, regionBottom - regionTop)

	local sideW = Responsive.sideWidth(380, v.X, layout)
	local panelW = if layout.compact then math.min(rootW - 2 * M, 640) else sideW
	local panelX = if layout.compact then (rootW - panelW) / 2 else rootW - M - panelW

	manualPanel.Position = UDim2.fromOffset(panelX, regionTop)
	manualPanel.Size = UDim2.fromOffset(panelW, math.min(360, regionH))

	local upH = math.min(130, regionH)
	upgradesPanel.Position = UDim2.fromOffset(panelX, regionTop)
	upgradesPanel.Size = UDim2.fromOffset(panelW, upH)

	local rowH = touchSize(40)
	local codesH = math.min(regionH, rowH + 24 + 3 * GAP + 8)
	codesPanel.Position = UDim2.fromOffset(panelX, regionTop)
	codesPanel.Size = UDim2.fromOffset(panelW, codesH)
	local redeemW = touchSize(100)
	codeBox.Position = UDim2.fromOffset(GAP + 2, GAP + 2)
	codeBox.Size = UDim2.fromOffset(math.max(40, panelW - redeemW - 3 * GAP - 4), rowH)
	redeemButton.Position = UDim2.fromOffset(panelW - redeemW - GAP - 2, GAP + 2)
	redeemButton.Size = UDim2.fromOffset(redeemW, rowH)
	codeStatus.Position = UDim2.fromOffset(GAP + 2, GAP + 2 + rowH + GAP)
	codeStatus.Size = UDim2.fromOffset(panelW - 2 * GAP - 4, 22)

	local cardW = math.min(rootW - 2 * M, 400)
	local okH, okW = touchSize(40), touchSize(110)
	local cardH = math.min(regionH, 250)
	summaryPanel.Position = UDim2.fromOffset((rootW - cardW) / 2, regionTop)
	summaryPanel.Size = UDim2.fromOffset(cardW, cardH)
	summaryTitle.Position = UDim2.fromOffset(10, 6)
	summaryTitle.Size = UDim2.fromOffset(cardW - 20, math.min(34, cardH * 0.2))
	local bodyTop = 6 + math.min(34, cardH * 0.2) + 4
	summaryBody.Position = UDim2.fromOffset(12, bodyTop)
	summaryBody.Size = UDim2.fromOffset(cardW - 24, math.max(10, cardH - bodyTop - okH - 12))
	summaryOk.Position = UDim2.fromOffset((cardW - okW) / 2, cardH - okH - 6)
	summaryOk.Size = UDim2.fromOffset(okW, okH)

	local noteW = math.min(rootW - 2 * M, 560)
	local noteH = math.min(regionH, 300)
	notePanel.Position = UDim2.fromOffset((rootW - noteW) / 2, regionTop)
	notePanel.Size = UDim2.fromOffset(noteW, noteH)
	noteText.Position = UDim2.fromOffset(14, 10)
	noteText.Size = UDim2.fromOffset(noteW - 28, math.max(10, noteH - okH - 26))
	noteClose.Position = UDim2.fromOffset((noteW - okW) / 2, noteH - okH - 8)
	noteClose.Size = UDim2.fromOffset(okW, okH)
	notePageLabel.Position = UDim2.fromOffset(noteW - 14 - 60, noteH - 8 - 20)
	notePageLabel.Size = UDim2.fromOffset(60, 18)

	refreshManualCanvas()
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
-- Tap-target sizing reads TouchEnabled; a device can gain or lose touch without resizing. In a
-- pcall, below every remote handler: the layout is cosmetic, the cash counter is not.
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
