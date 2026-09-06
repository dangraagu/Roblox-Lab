-- +1 JUMP EVERY STEP — klient-HUD. Havner i StarterPlayerScripts.
-- Ren visning: lytter på server-tilstand og tegner teller/rebirth/koder/topp-10.
-- Ingen spill-autoritet her (serveren eier jump power).
--
-- Layout note: every panel below is authored in design pixels against a 1280x720 window and
-- then scaled and repositioned by the shared Responsive module, so the HUD survives a phone
-- viewport. Three things follow from that and are easy to break by accident:
--   * a UIScale does nothing parented to a ScreenGui, so every element lives inside `root`;
--   * `root` is grown by 1/scale so that root * scale lands exactly on the viewport;
--   * on a phone the two side panels start collapsed behind toggle buttons along the TOP
--     edge, and nothing is allowed into the band at the bottom of the screen where Roblox
--     draws its own movement thumbstick and jump button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Plus1Remotes")
local StateEvent = remotes:WaitForChild("State")
local RebirthEvent = remotes:WaitForChild("Rebirth")
local RedeemFunc = remotes:WaitForChild("Redeem")
local LeaderboardEvent = remotes:WaitForChild("Leaderboard")

local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
-- CurrentCamera can still be nil for the first frames of a join. Indexing it inside
-- applyLayout would throw before the state connections below are made, leaving the player with
-- a fully drawn HUD that silently never updates again: jump power stuck at 0, an empty
-- leaderboard, a rebirth button that never changes. Wait for it instead.
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

-- Design-space sizes. These are the numbers the HUD was drawn with; Responsive shrinks them.
local MARGIN = Responsive.MARGIN
local GAP = 8
local TOGGLE_W, TOGGLE_H = 96, 34
local TOP_W = 360
local LEFT_W, LEFT_H = 210, 210
local CODE_H = 76
local LB_W, LB_H = 200, 300

-- ── UI-hjelpere ─────────────────────────────────────────────────────────────
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
-- math.clamp throws when the bounds cross, which a degenerate viewport can arrange.
local function clampNum(n, lo, hi)
	if hi < lo then return lo end
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local gui = Instance.new("ScreenGui")
gui.Name = "Plus1Hud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Everything hangs off this frame so the UIScale below actually applies.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- ── Topp-panel: stor jump power-teller ──────────────────────────────────────
local top = Instance.new("Frame")
top.Name = "Counter"
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, MARGIN)
top.Size = UDim2.new(0, TOP_W, 0, 92)
top.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
top.BackgroundTransparency = 0.1
top.Parent = root
corner(top, 14)

-- The two labels are sized as a fraction of the panel so the panel can shrink on a phone
-- without leaving the subtitle hanging off the bottom edge.
local jumpLabel = Instance.new("TextLabel")
jumpLabel.BackgroundTransparency = 1
jumpLabel.Size = UDim2.new(1, 0, 0.58, 0)
jumpLabel.Position = UDim2.new(0, 0, 0.06, 0)
jumpLabel.Font = Enum.Font.GothamBlack
jumpLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
jumpLabel.TextScaled = true
jumpLabel.Text = "🔼 0"
jumpLabel.Parent = top
do
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 40; cc.Parent = jumpLabel
end

local subLabel = Instance.new("TextLabel")
subLabel.BackgroundTransparency = 1
subLabel.Size = UDim2.new(1, 0, 0.28, 0)
subLabel.Position = UDim2.new(0, 0, 0.66, 0)
subLabel.Font = Enum.Font.GothamMedium
subLabel.TextColor3 = Color3.fromRGB(220, 225, 240)
subLabel.TextScaled = true
subLabel.Text = "Jump Power · step every tile for +1"
subLabel.Parent = top
do
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 16; cc.Parent = subLabel
end

-- ── Skuff-knapper (kun telefon) ─────────────────────────────────────────────
-- Both toggles sit on the top edge. They are the only way to reach the side panels on a
-- phone, so they must never be parked where a touch control would swallow the tap.
local function toggleButton(name, text, anchorX)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(anchorX, 0)
	b.Size = UDim2.new(0, TOGGLE_W, 0, TOGGLE_H)
	b.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
	b.BackgroundTransparency = 0.1
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(230, 234, 245)
	b.Text = text
	b.AutoButtonColor = true
	b.Visible = false
	b.Parent = root
	corner(b, 10)
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 16; cc.Parent = b
	return b
end

local menuToggle = toggleButton("MenuToggle", "☰ Menu", 0)
menuToggle.Position = UDim2.new(0, MARGIN, 0, MARGIN)
local lbToggle = toggleButton("TopToggle", "🏆 Top", 1)
lbToggle.Position = UDim2.new(1, -MARGIN, 0, MARGIN)

-- ── Venstre panel: tier / best / multiplier + rebirth ───────────────────────
-- A ScrollingFrame rather than a Frame: on a short phone the panel gets shortened to fit
-- above the touch controls, and scrolling the last stat into view beats clipping it away.
local left = Instance.new("ScrollingFrame")
left.Name = "Stats"
left.AnchorPoint = Vector2.new(0, 0.5)
left.Position = UDim2.new(0, MARGIN, 0.5, 0)
left.Size = UDim2.new(0, LEFT_W, 0, LEFT_H)
left.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
left.BackgroundTransparency = 0.15
left.BorderSizePixel = 0
left.ScrollBarThickness = 4
left.ScrollBarImageColor3 = Color3.fromRGB(120, 220, 255)
left.ScrollingDirection = Enum.ScrollingDirection.Y
left.CanvasSize = UDim2.new()
left.AutomaticCanvasSize = Enum.AutomaticSize.Y
left.Parent = root
corner(left, 12); pad(left, 10)

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = left

local function statLabel(order, text)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 26)
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = Color3.fromRGB(230, 234, 245)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextScaled = true
	l.LayoutOrder = order
	l.Text = text
	l.Parent = left
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 18; cc.Parent = l
	return l
end

local tierLabel = statLabel(1, "🏛️ Tier: 0")
local bestLabel = statLabel(2, "⭐ Best: 0")
local multLabel = statLabel(3, "✖️ Multiplier: 1x")
local heightLabel = statLabel(4, "📏 Jump: 7.2")

local rebirthBtn = Instance.new("TextButton")
rebirthBtn.Size = UDim2.new(1, 0, 0, 54)
rebirthBtn.LayoutOrder = 5
rebirthBtn.Font = Enum.Font.GothamBlack
rebirthBtn.TextScaled = true
rebirthBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
rebirthBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
rebirthBtn.Text = "REBIRTH"
rebirthBtn.AutoButtonColor = true
rebirthBtn.Parent = left
corner(rebirthBtn, 10)
do
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 20; cc.Parent = rebirthBtn
end
rebirthBtn.Activated:Connect(function()
	RebirthEvent:FireServer()
end)

-- ── Koder ───────────────────────────────────────────────────────────────────
-- This used to be pinned to the bottom-left corner, which on a phone is exactly where the
-- movement thumbstick lives — the text box and the Redeem button were untappable. It is now
-- lifted clear of the touch-control band, and on a phone it rides directly under the stats
-- panel as part of the same drawer instead of being bottom-anchored at all.
local codeFrame = Instance.new("Frame")
codeFrame.Name = "Codes"
codeFrame.AnchorPoint = Vector2.new(0, 1)
codeFrame.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
codeFrame.Size = UDim2.new(0, LEFT_W, 0, CODE_H)
codeFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
codeFrame.BackgroundTransparency = 0.15
codeFrame.Parent = root
corner(codeFrame, 12); pad(codeFrame, 8)

local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(1, 0, 0, 30)
codeBox.Font = Enum.Font.GothamMedium
codeBox.TextScaled = true
codeBox.PlaceholderText = "Enter code..."
codeBox.Text = ""
codeBox.ClearTextOnFocus = false
codeBox.TextColor3 = Color3.fromRGB(20, 24, 40)
codeBox.BackgroundColor3 = Color3.fromRGB(235, 238, 248)
codeBox.Parent = codeFrame
corner(codeBox, 8)

local codeBtn = Instance.new("TextButton")
codeBtn.Position = UDim2.new(0, 0, 0, 34)
codeBtn.Size = UDim2.new(1, 0, 0, 26)
codeBtn.Font = Enum.Font.GothamBold
codeBtn.TextScaled = true
codeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
codeBtn.BackgroundColor3 = Color3.fromRGB(70, 150, 90)
codeBtn.Text = "Redeem"
codeBtn.Parent = codeFrame
corner(codeBtn, 8)

codeBtn.Activated:Connect(function()
	local input = codeBox.Text
	if input == "" then return end
	local ok, res = pcall(function()
		return RedeemFunc:InvokeServer(input)
	end)
	if ok and type(res) == "table" then
		if res.ok then
			codeBox.Text = ""
			codeBtn.Text = "✅ +" .. tostring(res.jump)
		elseif res.reason == "already" then
			codeBtn.Text = "Already used"
		elseif res.reason == "unknown" then
			codeBtn.Text = "Invalid code"
		else
			codeBtn.Text = "Try again"
		end
		task.delay(2, function() codeBtn.Text = "Redeem" end)
	end
end)

-- ── Topp-10 (høyre) ─────────────────────────────────────────────────────────
local lbFrame = Instance.new("Frame")
lbFrame.Name = "Leaderboard"
lbFrame.AnchorPoint = Vector2.new(1, 0.5)
lbFrame.Position = UDim2.new(1, -MARGIN, 0.5, 0)
lbFrame.Size = UDim2.new(0, LB_W, 0, LB_H)
lbFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
lbFrame.BackgroundTransparency = 0.2
lbFrame.Parent = root
corner(lbFrame, 12); pad(lbFrame, 8)

local lbTitle = Instance.new("TextLabel")
lbTitle.BackgroundTransparency = 1
lbTitle.Size = UDim2.new(1, 0, 0, 26)
lbTitle.Font = Enum.Font.GothamBlack
lbTitle.TextScaled = true
lbTitle.TextColor3 = Color3.fromRGB(255, 215, 90)
lbTitle.Text = "🏆 TOP CLIMBERS"
lbTitle.Parent = lbFrame
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 18; cc.Parent = lbTitle end

-- Ten entries never fit once the panel has been shortened for a phone, so the list scrolls.
local lbList = Instance.new("ScrollingFrame")
lbList.BackgroundTransparency = 1
lbList.BorderSizePixel = 0
lbList.Position = UDim2.new(0, 0, 0, 30)
lbList.Size = UDim2.new(1, 0, 1, -30)
lbList.ScrollBarThickness = 4
lbList.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 90)
lbList.ScrollingDirection = Enum.ScrollingDirection.Y
lbList.CanvasSize = UDim2.new()
lbList.AutomaticCanvasSize = Enum.AutomaticSize.Y
lbList.Parent = lbFrame
local lbLayout = Instance.new("UIListLayout")
lbLayout.Padding = UDim.new(0, 3)
lbLayout.Parent = lbList

local function renderLeaderboard(entries)
	for _, c in ipairs(lbList:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	for i, entry in ipairs(entries) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, 22)
		l.Font = Enum.Font.GothamMedium
		l.TextScaled = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = Color3.fromRGB(225, 230, 245)
		l.LayoutOrder = i
		local name = "Player"
		local ok, res = pcall(function() return Players:GetNameFromUserIdAsync(entry.userId) end)
		if ok then name = res end
		l.Text = string.format("%d. %s — %d", i, name, entry.tier)
		l.Parent = lbList
		local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 15; cc.Parent = l
	end
end

-- ── Responsivt oppsett ──────────────────────────────────────────────────────
local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local menuOpen = false
local lbOpen = false

-- On a phone both drawers are closed until the player asks for one, and only one may be open
-- at a time so the play area is never buried under two panels at once. On anything larger the
-- panels are simply always there and the toggles do not exist.
local function refreshDrawers()
	local showMenu = (not layout.compact) or menuOpen
	local showLb = (not layout.compact) or lbOpen
	left.Visible = showMenu
	codeFrame.Visible = showMenu
	lbFrame.Visible = showLb
	menuToggle.Text = if menuOpen then "✕ Menu" else "☰ Menu"
	lbToggle.Text = if lbOpen then "✕ Top" else "🏆 Top"
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

local function applyLayout()
	local v = camera.ViewportSize
	-- ViewportSize is (0,0) for a frame or two at startup; fall back to the design window
	-- rather than laying the HUD out against nothing.
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	layout = Responsive.layout(vx, vy, UserInputService.TouchEnabled)

	uiScale.Scale = layout.scale
	-- Grow the root by 1/scale so root * scale lands exactly on the viewport. Without this the
	-- entire HUD shrinks into the top-left corner on a phone, while desktop (scale 1) looks fine
	-- and hides the bug.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	local compact = layout.compact
	local rootW = vx / layout.scale
	local rootH = vy / layout.scale
	local padDesign = layout.controlPad / layout.scale -- touch-control band, in design px
	local usable = Responsive.usableHeight(vy, layout) -- screen px

	menuToggle.Visible = compact
	lbToggle.Visible = compact

	-- The counter shrinks on a phone and is capped so the two toggles can never land on top of
	-- it, however narrow the window gets.
	local topH = if compact then 72 else 92
	local topW = TOP_W
	if compact then
		topW = clampNum(rootW - 2 * (MARGIN + TOGGLE_W + GAP), 160, TOP_W)
	end
	top.Size = UDim2.new(0, topW, 0, topH)

	-- The vertical band a side panel may occupy: below the counter, above the touch controls.
	local bandTop = MARGIN + topH + GAP
	local bandBottom = math.max(rootH - MARGIN - padDesign, bandTop + 1)
	local band = bandBottom - bandTop

	local leftW = Responsive.sideWidth(LEFT_W, vx, layout)
	local lbW = Responsive.sideWidth(LB_W, vx, layout)

	if compact then
		-- Phone: stats and the code box are one stack hanging from the top edge, so the code
		-- box ends up nowhere near the thumbstick and the whole drawer clears the control band.
		local leftRoom = math.max(1, band - GAP - CODE_H)
		local leftH = Responsive.fitHeight(LEFT_H, math.min(usable, leftRoom * layout.scale), layout)
		left.AnchorPoint = Vector2.new(0, 0)
		left.Position = UDim2.new(0, MARGIN, 0, bandTop)
		left.Size = UDim2.new(0, leftW, 0, leftH)

		codeFrame.AnchorPoint = Vector2.new(0, 0)
		codeFrame.Position = UDim2.new(0, MARGIN, 0, bandTop + leftH + GAP)
		codeFrame.Size = UDim2.new(0, leftW, 0, CODE_H)

		local lbH = Responsive.fitHeight(LB_H, math.min(usable, band * layout.scale), layout)
		lbFrame.AnchorPoint = Vector2.new(1, 0)
		lbFrame.Position = UDim2.new(1, -MARGIN, 0, bandTop)
		lbFrame.Size = UDim2.new(0, lbW, 0, lbH)
	else
		-- Desktop and tablet keep the familiar centred side panels. The code box stays in the
		-- bottom-left corner but is lifted by the control pad, which is zero on a mouse client
		-- and so leaves the desktop layout exactly where it was.
		codeFrame.AnchorPoint = Vector2.new(0, 1)
		codeFrame.Position = UDim2.new(0, MARGIN, 1, -(MARGIN + padDesign))
		codeFrame.Size = UDim2.new(0, leftW, 0, CODE_H)

		local leftBand = math.max(1, band - CODE_H - GAP)
		local leftH = Responsive.fitHeight(LEFT_H, math.min(usable, leftBand * layout.scale), layout)
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

	refreshDrawers()
end

-- ── State-oppdatering ───────────────────────────────────────────────────────
-- Connected BEFORE the first layout pass on purpose. Layout is cosmetic; these are the only
-- thing that keeps the numbers on screen true. If applyLayout ever throws, the player should
-- lose the polish, not the game.
StateEvent.OnClientEvent:Connect(function(s)
	jumpLabel.Text = "🔼 " .. tostring(s.jumpPower)
	tierLabel.Text = "🏛️ Tier: " .. tostring(s.tier)
	bestLabel.Text = "⭐ Best: " .. tostring(s.bestTier)
	multLabel.Text = "✖️ Multiplier: " .. tostring(s.multiplier) .. "x"
	heightLabel.Text = string.format("📏 Jump: %.1f", s.jumpHeight)
	if s.canRebirth then
		rebirthBtn.Text = "REBIRTH → " .. tostring(s.multiplier * 2) .. "x?"
		rebirthBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 220)
	else
		rebirthBtn.Text = "Reach tier " .. tostring(s.nextRebirthTier)
		rebirthBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	end
end)

LeaderboardEvent.OnClientEvent:Connect(renderLeaderboard)

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
