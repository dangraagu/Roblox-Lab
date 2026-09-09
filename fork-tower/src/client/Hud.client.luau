-- FORK TOWER — client HUD. Lands in StarterPlayerScripts.
-- Display only: it listens to server state and draws it. No authority lives here — the server
-- owns which door is the trap, and this file never even asks.
--
-- THE INSCRIPTION IS THE HUD. Everything else on screen is furniture. A player who cannot read
-- which sign to trust is playing a coin-flip game, which is the one thing Fork Tower promises it
-- is not, so the rule panel is the largest, highest-contrast, most central thing drawn — and it
-- is the panel that never collapses behind a drawer on a phone.
--
-- Layout note: every panel is authored in design pixels against a 1280x720 window and then
-- scaled and repositioned by the shared Responsive module. Five things follow from that and are
-- easy to break by accident:
--   * a UIScale does nothing parented to a ScreenGui, so every element lives inside `root`;
--   * `root` is grown by 1/scale so that root * scale lands exactly on the viewport;
--   * on a phone the two side panels collapse behind toggles along the TOP edge, and nothing is
--     allowed into the band at the bottom where Roblox draws its thumbstick and jump button;
--   * the scaling that makes the HUD fit also shrinks every button on the one device whose input
--     is a thumb, so anything tappable is sized through `touchSize`. Text may shrink; tap targets
--     may not;
--   * the drawable area is SHORTER than the viewport by the topbar inset, so every vertical
--     budget is measured against `drawableHeight`, never against camera.ViewportSize.Y.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("ForkRemotes")
local StateEvent = remotes:WaitForChild("State")
local NoticeEvent = remotes:WaitForChild("Notice")
local RevealEvent = remotes:WaitForChild("Reveal")
local RebirthEvent = remotes:WaitForChild("Rebirth")
local ArmSkipEvent = remotes:WaitForChild("ArmSkip")
local LeaderboardEvent = remotes:WaitForChild("Leaderboard")
local RedeemFunc = remotes:WaitForChild("Redeem")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

-- CurrentCamera can still be nil for the first frames of a join. Indexing it inside applyLayout
-- would throw before the state connections below are made, leaving the player with a fully drawn
-- HUD that silently never updates again.
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local MARGIN = Responsive.MARGIN
local GAP = 8
local TOGGLE_W, TOGGLE_H = 92, 34
local TOP_W, TOP_H = 260, 62
local RULE_W, RULE_H = 470, 92
local TOAST_W, TOAST_H = 420, 34
local LEFT_W, LEFT_H = 220, 236
local STAT_H, LEFT_PAD, LIST_GAP = 24, 10, 6
local BTN_H = 40
local CODE_PAD, CODE_GAP = 8, 4
local CODE_BOX_H, CODE_BTN_H = 30, 26
local LB_W, LB_H = 210, 300
local CARD_W, CARD_H = 380, 320

-- Roblox's own guidance and both mobile platform guidelines put the smallest comfortable tap
-- target at 44 SCREEN px. Design px are not screen px: the UIScale that makes the HUD fit a phone
-- shrinks every button on exactly the device whose input is a thumb.
local MIN_TAP = 44

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
end
local function pad(inst, px)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px); p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px); p.PaddingBottom = UDim.new(0, px)
	p.Parent = inst
end
local function cap(inst, maxSize)
	local cc = Instance.new("UITextSizeConstraint")
	cc.MaxTextSize = maxSize
	cc.Parent = inst
end
-- math.clamp throws when the bounds cross, which a degenerate viewport can arrange.
local function clampNum(n, lo, hi)
	if hi < lo then return lo end
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local INK = Color3.fromRGB(232, 228, 246)
local PANEL = Color3.fromRGB(26, 22, 40)
local GOLD = Color3.fromRGB(255, 216, 120)
local WARN = Color3.fromRGB(255, 130, 130)

local gui = Instance.new("ScreenGui")
gui.Name = "ForkHud"
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

--============================================================================ floor counter

local top = Instance.new("Frame")
top.Name = "Counter"
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, MARGIN)
top.Size = UDim2.new(0, TOP_W, 0, TOP_H)
top.BackgroundColor3 = PANEL
top.BackgroundTransparency = 0.1
top.Parent = root
corner(top, 14)

local floorLabel = Instance.new("TextLabel")
floorLabel.Name = "FloorLabel"
floorLabel.BackgroundTransparency = 1
floorLabel.Size = UDim2.new(1, 0, 0.62, 0)
floorLabel.Position = UDim2.new(0, 0, 0.06, 0)
floorLabel.Font = Enum.Font.GothamBlack
floorLabel.TextScaled = true
floorLabel.TextColor3 = GOLD
floorLabel.Text = "🔀 ETASJE 1/10"
floorLabel.Parent = top
cap(floorLabel, 30)

local stageLabel = Instance.new("TextLabel")
stageLabel.Name = "StageLabel"
stageLabel.BackgroundTransparency = 1
stageLabel.Size = UDim2.new(1, 0, 0.3, 0)
stageLabel.Position = UDim2.new(0, 0, 0.66, 0)
stageLabel.Font = Enum.Font.GothamMedium
stageLabel.TextScaled = true
stageLabel.TextColor3 = INK
stageLabel.Text = "Velg en dør"
stageLabel.Parent = top
cap(stageLabel, 14)

--============================================================================ the inscription

-- Never collapsed, never behind a toggle, on any device. This is the game.
local rule = Instance.new("Frame")
rule.Name = "Rule"
rule.AnchorPoint = Vector2.new(0.5, 0)
rule.Size = UDim2.new(0, RULE_W, 0, RULE_H)
rule.BackgroundColor3 = PANEL
rule.BackgroundTransparency = 0.05
rule.Parent = root
corner(rule, 12); pad(rule, 8)

local ruleText = Instance.new("TextLabel")
ruleText.Name = "RuleText"
ruleText.BackgroundTransparency = 1
ruleText.Size = UDim2.new(1, 0, 0.52, 0)
ruleText.Font = Enum.Font.GothamBlack
ruleText.TextScaled = true
ruleText.TextColor3 = GOLD
ruleText.Text = "STOL PÅ FLAMMEN — DEN MERKER FELLA"
ruleText.Parent = rule
cap(ruleText, 22)

local doorsText = Instance.new("TextLabel")
doorsText.Name = "DoorsText"
doorsText.BackgroundTransparency = 1
doorsText.Position = UDim2.new(0, 0, 0.54, 0)
doorsText.Size = UDim2.new(1, 0, 0.44, 0)
doorsText.Font = Enum.Font.GothamMedium
doorsText.TextScaled = true
doorsText.TextColor3 = INK
doorsText.Text = "VENSTRE …  ·  HØYRE …"
doorsText.Parent = rule
cap(doorsText, 15)

--============================================================================ toast

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Size = UDim2.new(0, TOAST_W, 0, TOAST_H)
toast.BackgroundColor3 = PANEL
toast.BackgroundTransparency = 0.15
toast.Font = Enum.Font.GothamBold
toast.TextScaled = true
toast.TextColor3 = INK
toast.Text = ""
toast.Visible = false
toast.Parent = root
corner(toast, 10); cap(toast, 16)

local toastToken = 0
local function showToast(text, color)
	toast.Text = text
	toast.TextColor3 = color or INK
	toast.Visible = true
	toastToken += 1
	local mine = toastToken
	task.delay(3.5, function()
		if toastToken == mine then
			toast.Visible = false
		end
	end)
end

--============================================================================ drawer toggles

local function toggleButton(name, text, anchorX)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(anchorX, 0)
	b.Size = UDim2.new(0, TOGGLE_W, 0, TOGGLE_H)
	b.BackgroundColor3 = PANEL
	b.BackgroundTransparency = 0.1
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = INK
	b.Text = text
	b.AutoButtonColor = true
	b.Visible = false
	b.Parent = root
	corner(b, 10); cap(b, 16)
	return b
end

local menuToggle = toggleButton("MenuToggle", "☰ Meny", 0)
menuToggle.Position = UDim2.new(0, MARGIN, 0, MARGIN)
local lbToggle = toggleButton("TopToggle", "🏆 Topp", 1)
lbToggle.Position = UDim2.new(1, -MARGIN, 0, MARGIN)

--============================================================================ left drawer

local left = Instance.new("ScrollingFrame")
left.Name = "Stats"
left.AnchorPoint = Vector2.new(0, 0.5)
left.Position = UDim2.new(0, MARGIN, 0.5, 0)
left.Size = UDim2.new(0, LEFT_W, 0, LEFT_H)
left.BackgroundColor3 = PANEL
left.BackgroundTransparency = 0.15
left.BorderSizePixel = 0
left.ScrollBarThickness = 4
left.ScrollBarImageColor3 = GOLD
left.ScrollingDirection = Enum.ScrollingDirection.Y
left.CanvasSize = UDim2.new()
left.AutomaticCanvasSize = Enum.AutomaticSize.Y
left.Parent = root
corner(left, 12); pad(left, LEFT_PAD)

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, LIST_GAP)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = left

-- Counted rather than written down, so adding a stat cannot leave the height arithmetic below
-- measuring a drawer that no longer exists.
local statRows = 0
local function statLabel(order, text)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, STAT_H)
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = INK
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextScaled = true
	l.LayoutOrder = order
	l.Text = text
	l.Parent = left
	cap(l, 17)
	statRows += 1
	return l
end

local bestLabel = statLabel(1, "⭐ Beste build: —")
local skipsLabel = statLabel(2, "🎟️ Skips: 0")
local jumpLabel = statLabel(3, "📏 Hopp: 7.2")
local rebirthLabel = statLabel(4, "🔁 Rebirths: 0")

local skipBtn = Instance.new("TextButton")
skipBtn.Name = "SkipButton"
skipBtn.Size = UDim2.new(1, 0, 0, BTN_H)
skipBtn.LayoutOrder = 5
skipBtn.Font = Enum.Font.GothamBold
skipBtn.TextScaled = true
skipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
skipBtn.BackgroundColor3 = Color3.fromRGB(58, 60, 86)
skipBtn.Text = "🎟️ ARMER SKIP"
skipBtn.AutoButtonColor = true
skipBtn.Parent = left
corner(skipBtn, 10); cap(skipBtn, 17)

local rebirthBtn = Instance.new("TextButton")
rebirthBtn.Name = "RebirthButton"
rebirthBtn.Size = UDim2.new(1, 0, 0, BTN_H)
rebirthBtn.LayoutOrder = 6
rebirthBtn.Font = Enum.Font.GothamBlack
rebirthBtn.TextScaled = true
rebirthBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
rebirthBtn.BackgroundColor3 = Color3.fromRGB(96, 62, 140)
rebirthBtn.Text = "🔁 REBIRTH"
rebirthBtn.AutoButtonColor = true
rebirthBtn.Parent = left
corner(rebirthBtn, 10); cap(rebirthBtn, 18)

-- Rebirth throws a run away, so it asks twice. A one-tap button that deletes ten floors of
-- choices is a bug report, not a feature.
local rebirthArmed = false
local rebirthToken = 0
rebirthBtn.Activated:Connect(function()
	if rebirthArmed then
		rebirthArmed = false
		rebirthBtn.Text = "🔁 REBIRTH"
		RebirthEvent:FireServer()
		return
	end
	rebirthArmed = true
	rebirthBtn.Text = "SIKKER? TRYKK IGJEN"
	rebirthToken += 1
	local mine = rebirthToken
	task.delay(4, function()
		if rebirthToken == mine and rebirthArmed then
			rebirthArmed = false
			rebirthBtn.Text = "🔁 REBIRTH"
		end
	end)
end)

local armedSkip = false
skipBtn.Activated:Connect(function()
	ArmSkipEvent:FireServer(not armedSkip)
end)

--============================================================================ codes

local codeFrame = Instance.new("Frame")
codeFrame.Name = "Codes"
codeFrame.AnchorPoint = Vector2.new(0, 1)
codeFrame.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
codeFrame.Size = UDim2.new(0, LEFT_W, 0, 2 * CODE_PAD + CODE_BOX_H + CODE_GAP + CODE_BTN_H)
codeFrame.LayoutOrder = 7 -- only consulted on a phone, where it joins the stats list
codeFrame.BackgroundColor3 = PANEL
codeFrame.BackgroundTransparency = 0.15
codeFrame.Parent = root
corner(codeFrame, 12); pad(codeFrame, CODE_PAD)

local codeBox = Instance.new("TextBox")
codeBox.Name = "CodeBox"
codeBox.Size = UDim2.new(1, 0, 0, CODE_BOX_H)
codeBox.Font = Enum.Font.GothamMedium
codeBox.TextScaled = true
codeBox.PlaceholderText = "Skriv en kode…"
codeBox.Text = ""
codeBox.ClearTextOnFocus = false
codeBox.TextColor3 = PANEL
codeBox.BackgroundColor3 = Color3.fromRGB(234, 230, 246)
codeBox.Parent = codeFrame
corner(codeBox, 8)

local codeBtn = Instance.new("TextButton")
codeBtn.Name = "RedeemButton"
codeBtn.Position = UDim2.new(0, 0, 0, CODE_BOX_H + CODE_GAP)
codeBtn.Size = UDim2.new(1, 0, 0, CODE_BTN_H)
codeBtn.Font = Enum.Font.GothamBold
codeBtn.TextScaled = true
codeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
codeBtn.BackgroundColor3 = Color3.fromRGB(66, 140, 92)
codeBtn.Text = "Løs inn"
codeBtn.Parent = codeFrame
corner(codeBtn, 8)

codeBtn.Activated:Connect(function()
	local input = codeBox.Text
	if input == "" then
		codeBtn.Text = "Skriv en kode"
		task.delay(2, function() codeBtn.Text = "Løs inn" end)
		return
	end
	local ok, res = pcall(function()
		return RedeemFunc:InvokeServer(input)
	end)
	if ok and type(res) == "table" then
		if res.ok then
			codeBox.Text = ""
			codeBtn.Text = "✅ +" .. tostring(res.skips) .. " skip"
		elseif res.reason == "already" then
			codeBtn.Text = "Alt brukt"
		elseif res.reason == "unknown" then
			codeBtn.Text = "Ugyldig kode"
		elseif res.reason == "nosave" then
			codeBtn.Text = "Lagring nede — prøv senere"
		else
			codeBtn.Text = "Prøv igjen"
		end
	else
		codeBtn.Text = "Prøv igjen"
	end
	task.delay(2.5, function() codeBtn.Text = "Løs inn" end)
end)

--============================================================================ right drawer

local lbFrame = Instance.new("Frame")
lbFrame.Name = "Leaderboard"
lbFrame.AnchorPoint = Vector2.new(1, 0.5)
lbFrame.Position = UDim2.new(1, -MARGIN, 0.5, 0)
lbFrame.Size = UDim2.new(0, LB_W, 0, LB_H)
lbFrame.BackgroundColor3 = PANEL
lbFrame.BackgroundTransparency = 0.2
lbFrame.Parent = root
corner(lbFrame, 12); pad(lbFrame, 8)

local lbTitle = Instance.new("TextLabel")
lbTitle.Name = "Title"
lbTitle.BackgroundTransparency = 1
lbTitle.Size = UDim2.new(1, 0, 0, 24)
lbTitle.Font = Enum.Font.GothamBlack
lbTitle.TextScaled = true
lbTitle.TextColor3 = GOLD
lbTitle.Text = "🏆 BESTE BUILDS"
lbTitle.Parent = lbFrame
cap(lbTitle, 17)

local lbList = Instance.new("ScrollingFrame")
lbList.Name = "List"
lbList.BackgroundTransparency = 1
lbList.BorderSizePixel = 0
lbList.Position = UDim2.new(0, 0, 0, 28)
lbList.Size = UDim2.new(1, 0, 1, -28)
lbList.ScrollBarThickness = 4
lbList.ScrollBarImageColor3 = GOLD
lbList.ScrollingDirection = Enum.ScrollingDirection.Y
lbList.CanvasSize = UDim2.new()
lbList.AutomaticCanvasSize = Enum.AutomaticSize.Y
lbList.Parent = lbFrame
local lbLayout = Instance.new("UIListLayout")
lbLayout.Padding = UDim.new(0, 3)
lbLayout.SortOrder = Enum.SortOrder.LayoutOrder
lbLayout.Parent = lbList

local function row(parent, order, text, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 21)
	l.Font = Enum.Font.GothamMedium
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color or INK
	l.LayoutOrder = order
	l.Text = text
	l.Parent = parent
	cap(l, 14)
	return l
end

local function renderLeaderboard(entries)
	for _, c in ipairs(lbList:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	for i, entry in ipairs(entries) do
		local name = "Spiller"
		local ok, res = pcall(function()
			return Players:GetNameFromUserIdAsync(entry.userId)
		end)
		if ok then name = res end
		row(lbList, i, string.format("%d. %s — %d", i, name, entry.score))
	end
end

--============================================================================ the build reveal

-- Hidden until the summit. Deliberately never drawn on top of a live fork: a card covering the
-- inscription is a card that costs the player the next floor.
local card = Instance.new("Frame")
card.Name = "Reveal"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.new(0.5, 0, 0.5, 0)
card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
card.BackgroundColor3 = Color3.fromRGB(20, 17, 32)
card.BackgroundTransparency = 0.02
card.Visible = false
card.ZIndex = 10
card.Parent = root
corner(card, 16); pad(card, 12)

local cardTitle = Instance.new("TextLabel")
cardTitle.Name = "CardTitle"
cardTitle.BackgroundTransparency = 1
cardTitle.Size = UDim2.new(1, 0, 0, 46)
cardTitle.Font = Enum.Font.GothamBlack
cardTitle.TextScaled = true
cardTitle.TextColor3 = GOLD
cardTitle.Text = "—"
cardTitle.ZIndex = 11
cardTitle.Parent = card
cap(cardTitle, 30)

local cardRarity = Instance.new("TextLabel")
cardRarity.Name = "CardRarity"
cardRarity.BackgroundTransparency = 1
cardRarity.Position = UDim2.new(0, 0, 0, 48)
cardRarity.Size = UDim2.new(1, 0, 0, 24)
cardRarity.Font = Enum.Font.GothamBold
cardRarity.TextScaled = true
cardRarity.TextColor3 = INK
cardRarity.Text = "—"
cardRarity.ZIndex = 11
cardRarity.Parent = card
cap(cardRarity, 18)

local cardList = Instance.new("ScrollingFrame")
cardList.Name = "CardTraits"
cardList.BackgroundTransparency = 1
cardList.BorderSizePixel = 0
cardList.Position = UDim2.new(0, 0, 0, 76)
cardList.Size = UDim2.new(1, 0, 1, -76 - BTN_H - GAP)
cardList.ScrollBarThickness = 4
cardList.ScrollBarImageColor3 = GOLD
cardList.ScrollingDirection = Enum.ScrollingDirection.Y
cardList.CanvasSize = UDim2.new()
cardList.AutomaticCanvasSize = Enum.AutomaticSize.Y
cardList.ZIndex = 11
cardList.Parent = card
local cardLayout = Instance.new("UIListLayout")
cardLayout.Padding = UDim.new(0, 3)
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Parent = cardList

local cardClose = Instance.new("TextButton")
cardClose.Name = "CardClose"
cardClose.AnchorPoint = Vector2.new(0, 1)
cardClose.Position = UDim2.new(0, 0, 1, 0)
cardClose.Size = UDim2.new(1, 0, 0, BTN_H)
cardClose.Font = Enum.Font.GothamBold
cardClose.TextScaled = true
cardClose.TextColor3 = Color3.fromRGB(255, 255, 255)
cardClose.BackgroundColor3 = Color3.fromRGB(58, 60, 86)
cardClose.Text = "LUKK"
cardClose.ZIndex = 11
cardClose.Parent = card
corner(cardClose, 10); cap(cardClose, 18)
cardClose.Activated:Connect(function()
	card.Visible = false
end)

--============================================================================ responsive layout

local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local menuOpen, lbOpen = false, false

-- Design px in, design px out — but the number that comes back is chosen so that what the
-- player's thumb meets is at least MIN_TAP screen px once the UIScale has had its way.
-- `controlPad` is non-zero only on a touch client, so a small mouse-driven window and a
-- 1920x1080 monitor both get the design numbers back unchanged.
local function touchSize(designPx)
	if layout.controlPad <= 0 then
		return designPx
	end
	local wanted = math.max(designPx, MIN_TAP)
	local n = math.ceil(wanted / layout.scale)
	-- The ceiling can land a hair short once the UIScale multiplies it back out. The test is
	-- `<=`, not `<`: a control that has to be measured to the third decimal to clear 44 px is one
	-- the next rounding change fails.
	if n * layout.scale <= wanted then
		n += 1
	end
	return n
end

local function stackHeight(btnH, codeH)
	local rows = statRows * STAT_H + 2 * btnH
	local count = statRows + 2
	if codeH ~= nil then
		rows += codeH
		count += 1
	end
	return math.max(LEFT_H, 2 * LEFT_PAD + rows + LIST_GAP * math.max(count - 1, 0))
end

local function refreshDrawers()
	local showMenu = (not layout.compact) or menuOpen
	local showLb = (not layout.compact) or lbOpen
	left.Visible = showMenu
	codeFrame.Visible = showMenu
	lbFrame.Visible = showLb
	menuToggle.Text = if menuOpen then "✕ Meny" else "☰ Meny"
	lbToggle.Text = if lbOpen then "✕ Topp" else "🏆 Topp"
end

menuToggle.Activated:Connect(function()
	menuOpen = not menuOpen
	if menuOpen then lbOpen = false end
	refreshDrawers()
end)
lbToggle.Activated:Connect(function()
	lbOpen = not lbOpen
	if lbOpen then menuOpen = false end
	refreshDrawers()
end)

-- ScreenGui.IgnoreGuiInset is left at its default false, so Roblox hands the ScreenGui an area
-- shorter than the viewport by the topbar strip. A panel sized from camera.ViewportSize.Y
-- overflows the real bottom edge by exactly that much — into the band of touch controls this
-- file exists to keep clear.
local function drawableHeight(vy)
	if gui.IgnoreGuiInset then
		return vy
	end
	local ok, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	local inset = if ok and topLeft ~= nil then topLeft.Y else 0
	return math.max(1, vy - inset)
end

local function applyLayout()
	local v = camera.ViewportSize
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	local vyDraw = drawableHeight(vy)
	layout = Responsive.layout(vx, vyDraw, UserInputService.TouchEnabled, vy)

	uiScale.Scale = layout.scale
	-- Grow the root by 1/scale so root * scale lands exactly on the viewport. Without this the
	-- whole HUD shrinks into the top-left corner on a phone, while desktop looks fine.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	local compact = layout.compact
	local rootW = vx / layout.scale
	local rootH = vyDraw / layout.scale
	local padDesign = layout.controlPad / layout.scale
	local usable = Responsive.usableHeight(vyDraw, layout)

	local toggleW, toggleH = touchSize(TOGGLE_W), touchSize(TOGGLE_H)
	local btnH = touchSize(BTN_H)
	local boxH, cBtnH = touchSize(CODE_BOX_H), touchSize(CODE_BTN_H)
	local codeH = 2 * CODE_PAD + boxH + CODE_GAP + cBtnH

	menuToggle.Size = UDim2.new(0, toggleW, 0, toggleH)
	lbToggle.Size = UDim2.new(0, toggleW, 0, toggleH)
	menuToggle.Visible = compact
	lbToggle.Visible = compact

	skipBtn.Size = UDim2.new(1, 0, 0, btnH)
	rebirthBtn.Size = UDim2.new(1, 0, 0, btnH)
	codeBox.Size = UDim2.new(1, 0, 0, boxH)
	codeBtn.Position = UDim2.new(0, 0, 0, boxH + CODE_GAP)
	codeBtn.Size = UDim2.new(1, 0, 0, cBtnH)
	cardClose.Size = UDim2.new(1, 0, 0, btnH)
	cardList.Size = UDim2.new(1, 0, 1, -76 - btnH - GAP)

	-- The counter shrinks and is capped so the two toggles can never land on top of it, however
	-- narrow the window gets.
	local topH = if compact then 54 else TOP_H
	local topW = TOP_W
	if compact then
		topW = clampNum(rootW - 2 * (MARGIN + toggleW + GAP), 80, TOP_W)
	end
	top.Size = UDim2.new(0, topW, 0, topH)

	local headerBottom = MARGIN + math.max(topH, if compact then toggleH else 0) + GAP

	-- The inscription sits directly under the header, centred, at whatever width fits. It is the
	-- only panel that never collapses, so it gets the width first and the side panels take what
	-- is left.
	local ruleW = clampNum(rootW - 2 * MARGIN, 120, RULE_W)
	local ruleH = if compact then 76 else RULE_H
	rule.Position = UDim2.new(0.5, 0, 0, headerBottom)
	rule.Size = UDim2.new(0, ruleW, 0, ruleH)

	toast.Position = UDim2.new(0.5, 0, 0, headerBottom + ruleH + GAP)
	toast.Size = UDim2.new(0, clampNum(rootW - 2 * MARGIN, 120, TOAST_W), 0, touchSize(TOAST_H))

	local bandTop = headerBottom + ruleH + GAP + touchSize(TOAST_H) + GAP
	local bandBottom = math.max(rootH - MARGIN - padDesign, bandTop + 1)
	local band = bandBottom - bandTop

	local leftW = Responsive.sideWidth(LEFT_W, vx, layout)
	local lbW = Responsive.sideWidth(LB_W, vx, layout)

	if compact then
		-- Phone: stats, buttons and the code box are ONE scrolling drawer hanging off the top
		-- edge, so nothing lands near the thumbstick.
		if codeFrame.Parent ~= left then
			codeFrame.Parent = left
		end
		codeFrame.AnchorPoint = Vector2.new(0, 0)
		codeFrame.Position = UDim2.new()
		codeFrame.Size = UDim2.new(1, 0, 0, codeH)

		local stackH = stackHeight(btnH, codeH)
		local leftH = Responsive.fitHeight(stackH, math.min(usable, band * layout.scale), layout)
		left.AnchorPoint = Vector2.new(0, 0)
		left.Position = UDim2.new(0, MARGIN, 0, bandTop)
		left.Size = UDim2.new(0, leftW, 0, leftH)

		local lbH = Responsive.fitHeight(LB_H, math.min(usable, band * layout.scale), layout)
		lbFrame.AnchorPoint = Vector2.new(1, 0)
		lbFrame.Position = UDim2.new(1, -MARGIN, 0, bandTop)
		lbFrame.Size = UDim2.new(0, lbW, 0, lbH)
	else
		if codeFrame.Parent ~= root then
			codeFrame.Parent = root
		end
		codeFrame.AnchorPoint = Vector2.new(0, 1)
		codeFrame.Position = UDim2.new(0, MARGIN, 1, -(MARGIN + padDesign))
		codeFrame.Size = UDim2.new(0, leftW, 0, codeH)

		local leftBand = math.max(1, band - codeH - GAP)
		local leftH = Responsive.fitHeight(stackHeight(btnH), math.min(usable, leftBand * layout.scale), layout)
		local leftCenter = clampNum(rootH * 0.5, bandTop + leftH * 0.5, bandTop + leftBand - leftH * 0.5)
		left.AnchorPoint = Vector2.new(0, 0.5)
		left.Position = UDim2.new(0, MARGIN, 0, leftCenter)
		left.Size = UDim2.new(0, leftW, 0, leftH)

		local lbH = Responsive.fitHeight(LB_H, math.min(usable, band * layout.scale), layout)
		local lbCenter = clampNum(rootH * 0.5, bandTop + lbH * 0.5, bandBottom - lbH * 0.5)
		lbFrame.AnchorPoint = Vector2.new(1, 0.5)
		lbFrame.Position = UDim2.new(1, -MARGIN, 0, lbCenter)
		lbFrame.Size = UDim2.new(0, lbW, 0, lbH)
	end

	-- The card is centred in the band, never over the inscription, and never taller than the
	-- room it has.
	local cardW = clampNum(rootW - 2 * MARGIN, 160, CARD_W)
	local cardH = Responsive.fitHeight(CARD_H, math.min(usable, band * layout.scale), layout)
	card.Size = UDim2.new(0, cardW, 0, cardH)
	card.Position = UDim2.new(0.5, 0, 0, bandTop + cardH * 0.5)

	refreshDrawers()
end

--============================================================================ state

-- Connected BEFORE the first layout pass on purpose. Layout is cosmetic; these are the only
-- thing that keeps the numbers on screen true. If applyLayout ever throws, the player should
-- lose the polish, not the game.
-- Read from Config, never re-typed here. A second copy of the sign glyphs on the client is a
-- second place to edit them, and the day the two disagree the HUD shows a sign that is not on
-- the door — which in this game is the difference between a readable fork and a coin flip.
local function signStrip(signs)
	local out = {}
	for _, k in ipairs(signs or {}) do
		out[#out + 1] = Config.Fork.SignEmoji[k] or "?"
	end
	return table.concat(out, " ")
end

StateEvent.OnClientEvent:Connect(function(s)
	local shown = math.min(s.level, s.floors)
	floorLabel.Text = string.format("🔀 ETASJE %d/%d", shown, s.floors)
	if s.stage == "summit" then
		stageLabel.Text = "Toppen nådd — se builden din"
	elseif s.stage == "climb" then
		stageLabel.Text = "Klatre til neste fork"
	else
		stageLabel.Text = "Velg en dør"
	end

	bestLabel.Text = "⭐ Beste build: " .. (if s.bestTitle ~= "" then s.bestTitle .. " (" .. s.bestScore .. ")" else "—")
	skipsLabel.Text = "🎟️ Skips: " .. tostring(s.skips)
	jumpLabel.Text = string.format("📏 Hopp %.1f · fart %d", s.jumpHeight, s.walkSpeed)
	rebirthLabel.Text = "🔁 Rebirths: " .. tostring(s.rebirths)

	armedSkip = s.armedSkip == true
	skipBtn.Text = if armedSkip then "🎟️ SKIP ARMERT" else "🎟️ ARMER SKIP"
	skipBtn.BackgroundColor3 = if armedSkip then Color3.fromRGB(66, 140, 92) else Color3.fromRGB(58, 60, 86)

	if s.rule then
		ruleText.Text = s.rule.sign .. " " .. s.rule.text
		ruleText.TextColor3 = if s.rule.inverted then WARN else GOLD
		doorsText.Text = string.format("◀ %s  %s      %s  %s ▶",
			s.rule.doors[1].label, signStrip(s.rule.doors[1].signs),
			signStrip(s.rule.doors[2].signs), s.rule.doors[2].label)
		rule.Visible = true
	else
		ruleText.Text = "👑 TOPPEN NÅDD"
		ruleText.TextColor3 = GOLD
		doorsText.Text = "Rebirth for et nytt tårn og et nytt valgtre"
		rule.Visible = true
	end
end)

NoticeEvent.OnClientEvent:Connect(function(n)
	if type(n) ~= "table" then return end
	local color = INK
	if n.kind == "trap" then
		color = WARN
		FxClient.shake(0.35, 1.4)
		FxClient.flash(Color3.fromRGB(255, 90, 90), 0.3, 0.5)
	elseif n.kind == "safe" or n.kind == "skip" then
		color = Color3.fromRGB(150, 235, 170)
	elseif n.kind == "summit" then
		color = GOLD
		FxClient.fovPunch(8)
	elseif n.kind == "blocked" or n.kind == "full" then
		color = WARN
	end
	showToast(tostring(n.text), color)
end)

RevealEvent.OnClientEvent:Connect(function(c)
	if type(c) ~= "table" then return end
	cardTitle.Text = tostring(c.title)
	if c.rarityColor then
		cardTitle.TextColor3 = Color3.fromRGB(c.rarityColor[1], c.rarityColor[2], c.rarityColor[3])
	end
	cardRarity.Text = string.format("%s · %d poeng%s", tostring(c.rarityName), c.score or 0,
		if c.banked then "" else " (allerede banket)")
	for _, ch in ipairs(cardList:GetChildren()) do
		if ch:IsA("TextLabel") then ch:Destroy() end
	end
	for i, t in ipairs(c.traits or {}) do
		row(cardList, i, string.format("%d. %s  %s", i, tostring(t.label), string.rep("★", t.power or 0)),
			if t.color then Color3.fromRGB(t.color[1], t.color[2], t.color[3]) else INK)
	end
	if (c.synergies or 0) > 0 then
		row(cardList, 99, string.format("✨ %d synergi(er)", c.synergies), GOLD)
	end
	card.Visible = true
	FxClient.popIn(card)
end)

LeaderboardEvent.OnClientEvent:Connect(renderLeaderboard)

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)

-- Touch can change without the window changing size: a laptop with a touchscreen, a tablet put
-- into and taken out of a dock. Every tap-target size above comes from layout.controlPad, which
-- comes from TouchEnabled. Connected last and wrapped, for the same reason the state remotes are
-- connected first.
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
