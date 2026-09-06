-- GROW A CRYSTAL 💎 — klient-HUD. Havner i StarterPlayerScripts.
-- Ren visning + valg. Server eier all økonomi/vekst. Plant/høst = klikk soklene i
-- verden (server ClickDetector). Denne setter valgt seed + viser butikk/Codex/koder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local remotes = ReplicatedStorage:WaitForChild("CrystalRemotes")
local StateEvent = remotes:WaitForChild("State")
local BuyEvent = remotes:WaitForChild("Buy")
local SelectEvent = remotes:WaitForChild("Select")
local GeodeEvent = remotes:WaitForChild("Geode")
local RedeemFunc = remotes:WaitForChild("Redeem")
local LeaderboardEvent = remotes:WaitForChild("Leaderboard")
local ToastEvent = remotes:WaitForChild("Toast")

local TIERS = Config.Tiers
local MAXT = Config.MaxTier
local unlockByChamber = Config.Economy.SeedShopUnlockedByChamber

local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = i end
local function pad(i, px) local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px); p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px); p.PaddingBottom = UDim.new(0, px); p.Parent = i end
local function tierColor(t) local c = Config.TierColor[t]; return Color3.fromRGB(c[1], c[2], c[3]) end

local gui = Instance.new("ScreenGui")
gui.Name = "CrystalHud"; gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- A UIScale does nothing when parented to a ScreenGui, so every HUD element lives in this
-- root frame instead and the root carries the scale. The root is grown by 1/scale in
-- applyLayout so that root * scale lands exactly on the viewport; without that the whole HUD
-- would shrink into the top-left corner on phones while looking fine on desktop.
local root = Instance.new("Frame")
root.Name = "Root"; root.BackgroundTransparency = 1; root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1); root.Parent = gui
local uiScale = Instance.new("UIScale"); uiScale.Parent = root

local camera = workspace.CurrentCamera
if not camera then
	repeat task.wait() until workspace.CurrentCamera
	camera = workspace.CurrentCamera
end

-- Design-space sizes the HUD was authored at; applyLayout shrinks them to fit.
local DESIGN_LEFT_W, DESIGN_LEFT_H = 250, 470
local DESIGN_LB_W, DESIGN_LB_H = 200, 300
local DESIGN_CODE_H = 68
-- On a phone the drawers open under the toggle row plus the dust/hint/toast stack.
local DRAWER_TOP = 104

local layout = Responsive.layout(camera.ViewportSize.X, camera.ViewportSize.Y, UserInputService.TouchEnabled)

-- ── Top: Dust ─────────────────────────────────────────────────────────────
local top = Instance.new("Frame")
top.AnchorPoint = Vector2.new(0.5, 0); top.Position = UDim2.new(0.5, 0, 0, 10)
top.Size = UDim2.new(0, 300, 0, 56); top.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
top.BackgroundTransparency = 0.1; top.Parent = root; corner(top, 12)
local dustLabel = Instance.new("TextLabel")
dustLabel.BackgroundTransparency = 1; dustLabel.Size = UDim2.new(1, 0, 1, 0)
dustLabel.Font = Enum.Font.GothamBlack; dustLabel.TextScaled = true
dustLabel.TextColor3 = Color3.fromRGB(150, 230, 255); dustLabel.Text = "💎 0"
dustLabel.Parent = top
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 30; cc.Parent = dustLabel end

-- Full-width text is sized in scale with an offset cap: 460 px wide on a desktop window, and
-- never wider than the screen on a phone.
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0); hint.Position = UDim2.new(0.5, 0, 0, 70)
hint.Size = UDim2.new(0.9, 0, 0, 22); hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium; hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(210, 214, 230)
hint.Text = "👆 Click a glowing socket to PLANT (you start with 3 free seeds!) · click a grown crystal to HARVEST 💎"
hint.Parent = root
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 14; cc.Parent = hint end
do local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(460, math.huge); sc.Parent = hint end

-- transient toast (server messages, e.g. "not enough dust")
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0); toast.Position = UDim2.new(0.5, 0, 0, 98)
toast.Size = UDim2.new(0.9, 0, 0, 24); toast.BackgroundTransparency = 1
toast.Font = Enum.Font.GothamBold; toast.TextScaled = true
toast.TextColor3 = Color3.fromRGB(255, 210, 120); toast.Text = ""
toast.Parent = root
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 15; cc.Parent = toast end
do local sc = Instance.new("UISizeConstraint"); sc.MaxSize = Vector2.new(460, math.huge); sc.Parent = toast end
ToastEvent.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "string" then return end
	toast.Text = msg
	task.delay(3, function()
		if toast.Text == msg then toast.Text = "" end
	end)
end)

-- ── Left: Seeds + shop ──────────────────────────────────────────────────────
-- One row per tier plus the shop buttons is more than the box can hold once the box has to
-- shrink to fit a phone, so this is a ScrollingFrame: the canvas follows the list layout's
-- content and the panel scrolls instead of clipping.
local left = Instance.new("ScrollingFrame")
left.Name = "SeedPanel"
left.AnchorPoint = Vector2.new(0, 0.5); left.Position = UDim2.new(0, 12, 0.5, 0)
left.Size = UDim2.new(0, DESIGN_LEFT_W, 0, DESIGN_LEFT_H); left.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
left.BackgroundTransparency = 0.12
left.ScrollingDirection = Enum.ScrollingDirection.Y
left.CanvasSize = UDim2.new(0, 0, 0, 0)
left.ScrollBarThickness = 4
left.ScrollBarImageColor3 = Color3.fromRGB(120, 190, 230)
left.ZIndex = 3
left.Parent = root; corner(left, 12); pad(left, 8)
local list = Instance.new("UIListLayout"); list.Padding = UDim.new(0, 4)
list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = left

-- AbsoluteContentSize is post-UIScale screen px; CanvasSize is design px, so divide it back
-- out or the canvas comes up short on a phone and the last shop buttons become unreachable.
local function refreshCanvas()
	left.CanvasSize = UDim2.new(0, 0, 0, math.ceil(list.AbsoluteContentSize.Y / uiScale.Scale) + 8)
end
list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)
refreshCanvas()

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Size = UDim2.new(1, 0, 0, 22); title.LayoutOrder = 0
title.Font = Enum.Font.GothamBlack; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(150, 230, 255)
title.Text = "🌱 SEEDS"; title.Parent = left
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 16; cc.Parent = title end

-- One row per tier: select (plant this) + owned count + buy
local seedRows = {}
for t = 1, MAXT do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 34); row.BackgroundColor3 = Color3.fromRGB(34, 38, 56)
	row.LayoutOrder = t; row.Parent = left; corner(row, 6)
	-- Half-width each rather than a fixed 120/118: the panel narrows on small screens, and a
	-- ScrollingFrame clips what hangs over its edge.
	local sel = Instance.new("TextButton")
	sel.Size = UDim2.new(0.5, -4, 1, -4); sel.Position = UDim2.new(0, 2, 0, 2)
	sel.Font = Enum.Font.GothamBold; sel.TextScaled = true; sel.TextColor3 = Color3.fromRGB(20, 22, 34)
	sel.BackgroundColor3 = tierColor(t); sel.Text = TIERS[t]; sel.Parent = row; corner(sel, 6)
	do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 13; cc.Parent = sel end
	sel.Activated:Connect(function() SelectEvent:FireServer(t) end)
	local buy = Instance.new("TextButton")
	buy.Size = UDim2.new(0.5, -4, 1, -4); buy.Position = UDim2.new(0.5, 2, 0, 2)
	buy.Font = Enum.Font.GothamMedium; buy.TextScaled = true; buy.TextColor3 = Color3.fromRGB(255, 255, 255)
	buy.BackgroundColor3 = Color3.fromRGB(70, 150, 90); buy.Text = "Buy"; buy.Parent = row; corner(buy, 6)
	do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 12; cc.Parent = buy end
	buy.Activated:Connect(function() BuyEvent:FireServer("seed", t) end)
	seedRows[t] = { row = row, sel = sel, buy = buy }
end

local function shopBtn(order, text, color, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 32); b.LayoutOrder = order
	b.Font = Enum.Font.GothamBold; b.TextScaled = true; b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.BackgroundColor3 = color; b.Text = text; b.Parent = left; corner(b, 6)
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 13; cc.Parent = b
	b.Activated:Connect(cb)
	return b
end
local chamberBtn = shopBtn(20, "Buy Chamber", Color3.fromRGB(90, 110, 200), function() BuyEvent:FireServer("chamber") end)
local luckBtn = shopBtn(21, "Luck", Color3.fromRGB(200, 150, 60), function() BuyEvent:FireServer("booster", "Luck") end)
local growthBtn = shopBtn(22, "Growth", Color3.fromRGB(60, 170, 120), function() BuyEvent:FireServer("booster", "Growth") end)
local geodeBtn = shopBtn(23, "Crack Geode", Color3.fromRGB(180, 90, 220), function() GeodeEvent:FireServer() end)
local codexLabel = Instance.new("TextLabel")
codexLabel.BackgroundTransparency = 1; codexLabel.Size = UDim2.new(1, 0, 0, 22); codexLabel.LayoutOrder = 24
codexLabel.Font = Enum.Font.GothamMedium; codexLabel.TextScaled = true
codexLabel.TextColor3 = Color3.fromRGB(230, 234, 245); codexLabel.Text = "📖 Codex: 0/" .. MAXT; codexLabel.Parent = left
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 14; cc.Parent = codexLabel end

-- ── Codes (bottom-left on desktop, a top drawer on a phone) ─────────────────
-- Bottom-left is where Roblox draws the movement thumbstick, so on touch this frame is lifted
-- clear of the control band, and on a phone it moves to the top entirely.
local codeFrame = Instance.new("Frame")
codeFrame.AnchorPoint = Vector2.new(0, 1); codeFrame.Position = UDim2.new(0, 12, 1, -12)
codeFrame.Size = UDim2.new(0, DESIGN_LEFT_W, 0, DESIGN_CODE_H); codeFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
codeFrame.BackgroundTransparency = 0.12; codeFrame.ZIndex = 3
codeFrame.Parent = root; corner(codeFrame, 10); pad(codeFrame, 6)
local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(1, 0, 0, 28); codeBox.Font = Enum.Font.GothamMedium; codeBox.TextScaled = true
codeBox.PlaceholderText = "Enter code..."; codeBox.Text = ""; codeBox.ClearTextOnFocus = false
codeBox.TextColor3 = Color3.fromRGB(20, 22, 34); codeBox.BackgroundColor3 = Color3.fromRGB(235, 238, 248)
codeBox.Parent = codeFrame; corner(codeBox, 6)
local codeBtn = Instance.new("TextButton")
codeBtn.Position = UDim2.new(0, 0, 0, 32); codeBtn.Size = UDim2.new(1, 0, 0, 24)
codeBtn.Font = Enum.Font.GothamBold; codeBtn.TextScaled = true; codeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
codeBtn.BackgroundColor3 = Color3.fromRGB(70, 150, 90); codeBtn.Text = "Redeem"; codeBtn.Parent = codeFrame; corner(codeBtn, 6)
codeBtn.Activated:Connect(function()
	local input = codeBox.Text
	if input == "" then return end
	local ok, res = pcall(function() return RedeemFunc:InvokeServer(input) end)
	if ok and type(res) == "table" then
		if res.ok then codeBox.Text = ""; codeBtn.Text = "✅ Redeemed!"
		elseif res.reason == "already" then codeBtn.Text = "Already used"
		elseif res.reason == "unknown" then codeBtn.Text = "Invalid code"
		else codeBtn.Text = "Try again" end
		task.delay(2, function() codeBtn.Text = "Redeem" end)
	end
end)

-- ── Leaderboard (right) ──────────────────────────────────────────────────────
local lb = Instance.new("Frame")
lb.AnchorPoint = Vector2.new(1, 0.5); lb.Position = UDim2.new(1, -12, 0.5, 0)
lb.Size = UDim2.new(0, DESIGN_LB_W, 0, DESIGN_LB_H); lb.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
lb.BackgroundTransparency = 0.2; lb.ZIndex = 3
lb.Parent = root; corner(lb, 12); pad(lb, 8)
local lbTitle = Instance.new("TextLabel")
lbTitle.BackgroundTransparency = 1; lbTitle.Size = UDim2.new(1, 0, 0, 24)
lbTitle.Font = Enum.Font.GothamBlack; lbTitle.TextScaled = true
lbTitle.TextColor3 = Color3.fromRGB(255, 215, 90); lbTitle.Text = "🏆 TOP MINERS"; lbTitle.Parent = lb
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 17; cc.Parent = lbTitle end
-- Scrollable for the same reason as the seed panel: ten entries do not fit once the board is
-- shrunk to a phone's usable height.
local lbList = Instance.new("ScrollingFrame")
lbList.BackgroundTransparency = 1; lbList.Position = UDim2.new(0, 0, 0, 28); lbList.Size = UDim2.new(1, 0, 1, -28)
lbList.ScrollingDirection = Enum.ScrollingDirection.Y
lbList.CanvasSize = UDim2.new(0, 0, 0, 0)
lbList.ScrollBarThickness = 4
lbList.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 90)
lbList.BorderSizePixel = 0
lbList.Parent = lb
local lbLayout = Instance.new("UIListLayout"); lbLayout.Padding = UDim.new(0, 3); lbLayout.Parent = lbList
lbLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	lbList.CanvasSize = UDim2.new(0, 0, 0, math.ceil(lbLayout.AbsoluteContentSize.Y / uiScale.Scale) + 4)
end)

LeaderboardEvent.OnClientEvent:Connect(function(top)
	for _, c in ipairs(lbList:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	for i, e in ipairs(top) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1; l.Size = UDim2.new(1, 0, 0, 22); l.LayoutOrder = i
		l.Font = Enum.Font.GothamMedium; l.TextScaled = true; l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = Color3.fromRGB(225, 230, 245)
		local name = "Player"
		local okn, res = pcall(function() return Players:GetNameFromUserIdAsync(e.userId) end)
		if okn then name = res end
		l.Text = string.format("%d. %s — 💎%d", i, name, e.dust); l.Parent = lbList
		local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 14; cc.Parent = l
	end
end)

-- ── State render ───────────────────────────────────────────────────────────
StateEvent.OnClientEvent:Connect(function(s)
	dustLabel.Text = "💎 " .. tostring(s.dust)
	for t = 1, MAXT do
		local r = seedRows[t]
		local owned = (s.seeds and s.seeds[t]) or 0
		r.sel.Text = TIERS[t] .. " (" .. owned .. ")"
		local unlocked = s.chambers >= (unlockByChamber[t] or 999)
		if unlocked then
			r.buy.Text = "Buy 💎" .. tostring(Config.Economy.SeedCost[t])
			r.buy.BackgroundColor3 = Color3.fromRGB(70, 150, 90); r.buy.Active = true
		else
			r.buy.Text = "🔒 Ch." .. tostring(unlockByChamber[t])
			r.buy.BackgroundColor3 = Color3.fromRGB(80, 84, 100); r.buy.Active = false
		end
	end
	chamberBtn.Text = (s.chambers >= Config.Economy.MaxChambers) and "Chambers MAX"
		or ("Buy Chamber 💎" .. tostring(s.chamberCost) .. " (" .. s.chambers .. ")")
	luckBtn.Text = "Luck Lv" .. s.luckLevel .. " → 💎" .. tostring(s.luckCost)
	growthBtn.Text = "Growth Lv" .. s.growthLevel .. " → 💎" .. tostring(s.growthCost)
	if s.geodeCanCrack then
		geodeBtn.Text = "Crack Geode 💎" .. s.geodeCost .. " → " .. TIERS[s.geodeExclusive]
		geodeBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 220)
	else
		geodeBtn.Text = "Geode used (back next week)"
		geodeBtn.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	end
	codexLabel.Text = "📖 Codex: " .. tostring(s.codexCount) .. "/" .. MAXT
end)

-- ── Responsive layout ───────────────────────────────────────────────────────
-- On a phone the three panels are drawers behind toggle buttons along the TOP edge (the
-- bottom belongs to Roblox's movement stick and jump button), and only one drawer is open at
-- a time so two of them can never cover the screen together. On desktop nothing collapses and
-- the layout is the one the game shipped with.

local openDrawer: string? = nil
local toggleButtons: { [string]: TextButton } = {}
local TOGGLE_SHUT = Color3.fromRGB(34, 38, 56)
local TOGGLE_OPEN = Color3.fromRGB(70, 150, 90)

local function refreshDrawers()
	local compact = layout.compact
	left.Visible = (not compact) or openDrawer == "seeds"
	codeFrame.Visible = (not compact) or openDrawer == "code"
	lb.Visible = (not compact) or openDrawer == "board"
	for key, btn in pairs(toggleButtons) do
		btn.BackgroundColor3 = if openDrawer == key then TOGGLE_OPEN else TOGGLE_SHUT
	end
end

local function setDrawer(key: string)
	openDrawer = if openDrawer == key then nil else key
	refreshDrawers()
end

local toggleBar = Instance.new("Frame")
toggleBar.Name = "Toggles"; toggleBar.BackgroundTransparency = 1; toggleBar.BorderSizePixel = 0
toggleBar.Position = UDim2.new(0, 12, 0, 10); toggleBar.Size = UDim2.new(0, 276, 0, 28)
toggleBar.Visible = false; toggleBar.ZIndex = 4; toggleBar.Parent = root
do
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal; tl.Padding = UDim.new(0, 6)
	tl.SortOrder = Enum.SortOrder.LayoutOrder; tl.Parent = toggleBar
end

local function toggleBtn(order: number, key: string, text: string)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 88, 1, 0); b.LayoutOrder = order
	b.Font = Enum.Font.GothamBold; b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(235, 238, 248); b.BackgroundColor3 = TOGGLE_SHUT
	b.BackgroundTransparency = 0.1; b.Text = text; b.ZIndex = 4; b.Parent = toggleBar; corner(b, 6)
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 13; cc.Parent = b
	b.Activated:Connect(function() setDrawer(key) end)
	toggleButtons[key] = b
end
toggleBtn(1, "seeds", "🌱 Seeds")
toggleBtn(2, "code", "🎟 Code")
toggleBtn(3, "board", "🏆 Top")

local function applyLayout()
	local v = camera.ViewportSize
	layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	-- controlPad is screen px; inside the scaled root everything is design px.
	local padDesign = layout.controlPad / layout.scale
	local usable = Responsive.usableHeight(v.Y, layout)
	local leftW = Responsive.sideWidth(DESIGN_LEFT_W, v.X, layout)
	local lbW = Responsive.sideWidth(DESIGN_LB_W, v.X, layout)

	toggleBar.Visible = layout.compact

	if layout.compact then
		-- A drawer starts below the header stack, so it gets that much less room than a panel
		-- that may use the full height of the screen.
		local drawerUsable = math.max(60, usable - DRAWER_TOP * layout.scale)
		top.AnchorPoint = Vector2.new(1, 0)
		top.Position = UDim2.new(1, -12, 0, 10)
		top.Size = UDim2.new(0, 220, 0, 28)
		hint.Position = UDim2.new(0.5, 0, 0, 46)
		toast.Position = UDim2.new(0.5, 0, 0, 74)
		left.AnchorPoint = Vector2.new(0, 0)
		left.Position = UDim2.new(0, 12, 0, DRAWER_TOP)
		left.Size = UDim2.new(0, leftW, 0, Responsive.fitHeight(DESIGN_LEFT_H, drawerUsable, layout))
		codeFrame.AnchorPoint = Vector2.new(0, 0)
		codeFrame.Position = UDim2.new(0, 12, 0, DRAWER_TOP)
		lb.AnchorPoint = Vector2.new(1, 0)
		lb.Position = UDim2.new(1, -12, 0, DRAWER_TOP)
		lb.Size = UDim2.new(0, lbW, 0, Responsive.fitHeight(DESIGN_LB_H, drawerUsable, layout))
	else
		top.AnchorPoint = Vector2.new(0.5, 0)
		top.Position = UDim2.new(0.5, 0, 0, 10)
		top.Size = UDim2.new(0, 300, 0, 56)
		hint.Position = UDim2.new(0.5, 0, 0, 70)
		toast.Position = UDim2.new(0.5, 0, 0, 98)
		-- Centred panels are lifted by half the control band so a touch tablet keeps them off
		-- the jump button; padDesign is 0 on desktop, where this is the original layout.
		left.AnchorPoint = Vector2.new(0, 0.5)
		left.Position = UDim2.new(0, 12, 0.5, -padDesign / 2)
		left.Size = UDim2.new(0, leftW, 0, Responsive.fitHeight(DESIGN_LEFT_H, usable, layout))
		codeFrame.AnchorPoint = Vector2.new(0, 1)
		codeFrame.Position = UDim2.new(0, 12, 1, -12 - padDesign)
		lb.AnchorPoint = Vector2.new(1, 0.5)
		lb.Position = UDim2.new(1, -12, 0.5, -padDesign / 2)
		lb.Size = UDim2.new(0, lbW, 0, Responsive.fitHeight(DESIGN_LB_H, usable, layout))
	end
	codeFrame.Size = UDim2.new(0, leftW, 0, DESIGN_CODE_H)

	refreshDrawers()
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
