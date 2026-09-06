-- GROW A CRYSTAL ðŸ’Ž â€” klient-HUD. Havner i StarterPlayerScripts.
-- Ren visning + valg. Server eier all Ã¸konomi/vekst. Plant/hÃ¸st = klikk soklene i
-- verden (server ClickDetector). Denne setter valgt seed + viser butikk/Codex/koder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

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
-- Desktop height of the code box plus the Redeem button; applyLayout recomputes it whenever
-- either of those grows to stay a thumb's width.
local DESIGN_CODE_H = 68

-- IgnoreGuiInset is left at its default false, so Roblox hands this ScreenGui a drawable area
-- that is the viewport minus the topbar inset, and the root frame starts below the inset rather
-- than at the top of the screen. Every vertical budget in this file therefore has to come from
-- that shorter height: computing them from the full ViewportSize.Y makes a panel sized to fill
-- the screen overflow the real bottom edge by the inset, straight into the touch-control band
-- this layout exists to keep clear. Bottom-anchored elements are already measured from the real
-- bottom, which is why the mistake is invisible on a desktop monitor. GetGuiInset returns two
-- Vector2s and the first is the top-left one.
local function effectiveHeight(vy: number): number
	-- A viewport of zero means "not known yet"; pass it through so Responsive's own handling of
	-- an unknown viewport still applies rather than subtracting the inset from nothing.
	if vy <= 0 or gui.IgnoreGuiInset then return vy end
	return math.max(1, vy - GuiService:GetGuiInset().Y)
end

local layout = Responsive.layout(camera.ViewportSize.X, effectiveHeight(camera.ViewportSize.Y), UserInputService.TouchEnabled, camera.ViewportSize.Y)

-- Roblox's own guidance and both mobile platform guidelines put the smallest comfortable tap
-- target at 44 screen px in both dimensions. A UIScale below 1 shrinks every button on exactly
-- the device that needs them biggest, so interactive elements are sized in SCREEN space instead:
-- divide the design size by the scale so the control lands at the same physical size whatever
-- the scale factor, and never let it come out under the floor. controlPad is only non-zero on
-- touch, so a small mouse-driven window and the desktop layout keep their design sizes untouched.
local MIN_TAP = 44
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then return designPx end
	-- Rounded up so the control lands a hair over the floor rather than a hair under it: 44 /
	-- 0.8 is not exactly 55 in floating point, and 54.99... * 0.8 measures as 43.99 screen px.
	return math.ceil(math.max(designPx, MIN_TAP) / layout.scale)
end

-- â”€â”€ Top: Dust â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local top = Instance.new("Frame")
top.AnchorPoint = Vector2.new(0.5, 0); top.Position = UDim2.new(0.5, 0, 0, 10)
top.Size = UDim2.new(0, 300, 0, 56); top.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
top.BackgroundTransparency = 0.1; top.Parent = root; corner(top, 12)
local dustLabel = Instance.new("TextLabel")
dustLabel.BackgroundTransparency = 1; dustLabel.Size = UDim2.new(1, 0, 1, 0)
dustLabel.Font = Enum.Font.GothamBlack; dustLabel.TextScaled = true
dustLabel.TextColor3 = Color3.fromRGB(150, 230, 255); dustLabel.Text = "ðŸ’Ž 0"
dustLabel.Parent = top
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 30; cc.Parent = dustLabel end

-- Full-width text is sized in scale with an offset cap: 460 px wide on a desktop window, and
-- never wider than the screen on a phone.
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0); hint.Position = UDim2.new(0.5, 0, 0, 70)
hint.Size = UDim2.new(0.9, 0, 0, 22); hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium; hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(210, 214, 230)
hint.Text = "ðŸ‘† Click a glowing socket to PLANT (you start with 3 free seeds!) Â· click a grown crystal to HARVEST ðŸ’Ž"
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

-- â”€â”€ Left: Seeds + shop â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
title.Text = "ðŸŒ± SEEDS"; title.Parent = left
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

-- applyLayout re-heights every one of these, so they are collected as they are made.
local shopButtons = {}
local function shopBtn(order, text, color, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 32); b.LayoutOrder = order
	b.Font = Enum.Font.GothamBold; b.TextScaled = true; b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.BackgroundColor3 = color; b.Text = text; b.Parent = left; corner(b, 6)
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 13; cc.Parent = b
	b.Activated:Connect(cb)
	table.insert(shopButtons, b)
	return b
end
local chamberBtn = shopBtn(20, "Buy Chamber", Color3.fromRGB(90, 110, 200), function() BuyEvent:FireServer("chamber") end)
local luckBtn = shopBtn(21, "Luck", Color3.fromRGB(200, 150, 60), function() BuyEvent:FireServer("booster", "Luck") end)
local growthBtn = shopBtn(22, "Growth", Color3.fromRGB(60, 170, 120), function() BuyEvent:FireServer("booster", "Growth") end)
local geodeBtn = shopBtn(23, "Crack Geode", Color3.fromRGB(180, 90, 220), function() GeodeEvent:FireServer() end)
local codexLabel = Instance.new("TextLabel")
codexLabel.BackgroundTransparency = 1; codexLabel.Size = UDim2.new(1, 0, 0, 22); codexLabel.LayoutOrder = 24
codexLabel.Font = Enum.Font.GothamMedium; codexLabel.TextScaled = true
codexLabel.TextColor3 = Color3.fromRGB(230, 234, 245); codexLabel.Text = "ðŸ“– Codex: 0/" .. MAXT; codexLabel.Parent = left
do local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 14; cc.Parent = codexLabel end

-- â”€â”€ Codes (bottom-left on desktop, a top drawer on a phone) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
		if res.ok then codeBox.Text = ""; codeBtn.Text = "âœ… Redeemed!"
		elseif res.reason == "already" then codeBtn.Text = "Already used"
		elseif res.reason == "unknown" then codeBtn.Text = "Invalid code"
		else codeBtn.Text = "Try again" end
		task.delay(2, function() codeBtn.Text = "Redeem" end)
	end
end)

-- â”€â”€ Leaderboard (right) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local lb = Instance.new("Frame")
lb.AnchorPoint = Vector2.new(1, 0.5); lb.Position = UDim2.new(1, -12, 0.5, 0)
lb.Size = UDim2.new(0, DESIGN_LB_W, 0, DESIGN_LB_H); lb.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
lb.BackgroundTransparency = 0.2; lb.ZIndex = 3
lb.Parent = root; corner(lb, 12); pad(lb, 8)
local lbTitle = Instance.new("TextLabel")
lbTitle.BackgroundTransparency = 1; lbTitle.Size = UDim2.new(1, 0, 0, 24)
lbTitle.Font = Enum.Font.GothamBlack; lbTitle.TextScaled = true
lbTitle.TextColor3 = Color3.fromRGB(255, 215, 90); lbTitle.Text = "ðŸ† TOP MINERS"; lbTitle.Parent = lb
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
		l.Text = string.format("%d. %s â€” ðŸ’Ž%d", i, name, e.dust); l.Parent = lbList
		local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 14; cc.Parent = l
	end
end)

-- â”€â”€ State render â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
StateEvent.OnClientEvent:Connect(function(s)
	dustLabel.Text = "ðŸ’Ž " .. tostring(s.dust)
	for t = 1, MAXT do
		local r = seedRows[t]
		local owned = (s.seeds and s.seeds[t]) or 0
		r.sel.Text = TIERS[t] .. " (" .. owned .. ")"
		local unlocked = s.chambers >= (unlockByChamber[t] or 999)
		if unlocked then
			r.buy.Text = "Buy ðŸ’Ž" .. tostring(Config.Economy.SeedCost[t])
			r.buy.BackgroundColor3 = Color3.fromRGB(70, 150, 90); r.buy.Active = true
		else
			r.buy.Text = "ðŸ”’ Ch." .. tostring(unlockByChamber[t])
			r.buy.BackgroundColor3 = Color3.fromRGB(80, 84, 100); r.buy.Active = false
		end
	end
	chamberBtn.Text = (s.chambers >= Config.Economy.MaxChambers) and "Chambers MAX"
		or ("Buy Chamber ðŸ’Ž" .. tostring(s.chamberCost) .. " (" .. s.chambers .. ")")
	luckBtn.Text = "Luck Lv" .. s.luckLevel .. " â†’ ðŸ’Ž" .. tostring(s.luckCost)
	growthBtn.Text = "Growth Lv" .. s.growthLevel .. " â†’ ðŸ’Ž" .. tostring(s.growthCost)
	if s.geodeCanCrack then
		geodeBtn.Text = "Crack Geode ðŸ’Ž" .. s.geodeCost .. " â†’ " .. TIERS[s.geodeExclusive]
		geodeBtn.BackgroundColor3 = Color3.fromRGB(180, 90, 220)
	else
		geodeBtn.Text = "Geode used (back next week)"
		geodeBtn.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	end
	codexLabel.Text = "ðŸ“– Codex: " .. tostring(s.codexCount) .. "/" .. MAXT
end)

-- â”€â”€ Responsive layout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

-- Design width and height of one toggle on a desktop-sized window; on touch applyLayout grows
-- both until the button is at least MIN_TAP screen px, because these three are the only route
-- to the seeds, the shop, the codes and the leaderboard.
local TOGGLE_W, TOGGLE_H = 88, 28
local TOGGLE_GAP = 6

local toggleBar = Instance.new("Frame")
toggleBar.Name = "Toggles"; toggleBar.BackgroundTransparency = 1; toggleBar.BorderSizePixel = 0
toggleBar.Position = UDim2.new(0, 12, 0, 10)
toggleBar.Size = UDim2.new(0, 3 * TOGGLE_W + 2 * TOGGLE_GAP, 0, TOGGLE_H)
toggleBar.Visible = false; toggleBar.ZIndex = 4; toggleBar.Parent = root
do
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal; tl.Padding = UDim.new(0, TOGGLE_GAP)
	tl.SortOrder = Enum.SortOrder.LayoutOrder; tl.Parent = toggleBar
end

local function toggleBtn(order: number, key: string, text: string)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, TOGGLE_W, 1, 0); b.LayoutOrder = order
	b.Font = Enum.Font.GothamBold; b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(235, 238, 248); b.BackgroundColor3 = TOGGLE_SHUT
	b.BackgroundTransparency = 0.1; b.Text = text; b.ZIndex = 4; b.Parent = toggleBar; corner(b, 6)
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 13; cc.Parent = b
	b.Activated:Connect(function() setDrawer(key) end)
	toggleButtons[key] = b
end
toggleBtn(1, "seeds", "ðŸŒ± Seeds")
toggleBtn(2, "code", "ðŸŽŸ Code")
toggleBtn(3, "board", "ðŸ† Top")

local function applyLayout()
	local v = camera.ViewportSize
	-- The height the ScreenGui actually gets, not the height of the monitor. See effectiveHeight.
	local effY = effectiveHeight(v.Y)
	layout = Responsive.layout(v.X, effY, UserInputService.TouchEnabled, v.Y)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	-- controlPad is screen px; inside the scaled root everything is design px.
	local padDesign = layout.controlPad / layout.scale
	local usable = Responsive.usableHeight(effY, layout)
	local rootW = v.X / layout.scale
	local leftW = Responsive.sideWidth(DESIGN_LEFT_W, v.X, layout)
	local lbW = Responsive.sideWidth(DESIGN_LB_W, v.X, layout)

	-- Everything the player taps, sized so it survives the UIScale. On desktop each of these is
	-- the number the panel was authored with, so nothing below moves on a monitor.
	local seedBtnH = touchSize(30)
	local shopH = touchSize(32)
	local codeBoxH = touchSize(28)
	local codeBtnH = touchSize(24)
	for t = 1, MAXT do
		-- The row carries 2 px of margin above and below its two buttons, so it is the button
		-- height plus 4; the buttons themselves stay at `1, -4` of the row.
		seedRows[t].row.Size = UDim2.new(1, 0, 0, seedBtnH + 4)
	end
	for _, b in ipairs(shopButtons) do
		b.Size = UDim2.new(1, 0, 0, shopH)
	end
	codeBox.Size = UDim2.new(1, 0, 0, codeBoxH)
	codeBtn.Position = UDim2.new(0, 0, 0, codeBoxH + 4)
	codeBtn.Size = UDim2.new(1, 0, 0, codeBtnH)
	-- Box, gap, button, and the 6 px of padding at the top and the bottom. 68 on desktop.
	local codeH = codeBoxH + 4 + codeBtnH + 12

	toggleBar.Visible = layout.compact

	if layout.compact then
		local toggleW, toggleH = touchSize(TOGGLE_W), touchSize(TOGGLE_H)
		-- Widening the toggles must not push the row off the edge, so three of them plus their
		-- gaps and the dust readout have to keep fitting the width. On every phone viewport this
		-- has slack to spare; it only bites on a screen too narrow for three tap targets at all.
		local room = rootW - 2 * 12 - 2 * TOGGLE_GAP - 120 - 8
		if 3 * toggleW > room then toggleW = math.max(1, math.floor(room / 3)) end
		local barW = 3 * toggleW + 2 * TOGGLE_GAP
		toggleBar.Position = UDim2.new(0, 12, 0, 10)
		toggleBar.Size = UDim2.new(0, barW, 0, toggleH)
		for _, b in pairs(toggleButtons) do
			b.Size = UDim2.new(0, toggleW, 1, 0)
		end

		-- The dust readout shares the toggle row and takes whatever width is left over, so the
		-- taller toggles cost the drawers below only one row instead of two.
		top.AnchorPoint = Vector2.new(1, 0)
		top.Position = UDim2.new(1, -12, 0, 10)
		top.Size = UDim2.new(0, math.clamp(rootW - 12 - barW - 8 - 12, 120, 300), 0, toggleH)

		-- The header stack, and with it the drawers, starts below whatever the toggle row grew to.
		local hintY = 10 + toggleH + 6
		local toastY = hintY + 26
		local drawerTop = toastY + 28
		hint.Position = UDim2.new(0.5, 0, 0, hintY)
		toast.Position = UDim2.new(0.5, 0, 0, toastY)

		-- A drawer starts below the header stack, so it gets that much less room than a panel
		-- that may use the full height of the screen.
		local drawerUsable = math.max(60, usable - drawerTop * layout.scale)
		left.AnchorPoint = Vector2.new(0, 0)
		left.Position = UDim2.new(0, 12, 0, drawerTop)
		left.Size = UDim2.new(0, leftW, 0, Responsive.fitHeight(DESIGN_LEFT_H, drawerUsable, layout))
		codeFrame.AnchorPoint = Vector2.new(0, 0)
		codeFrame.Position = UDim2.new(0, 12, 0, drawerTop)
		lb.AnchorPoint = Vector2.new(1, 0)
		lb.Position = UDim2.new(1, -12, 0, drawerTop)
		lb.Size = UDim2.new(0, lbW, 0, Responsive.fitHeight(DESIGN_LB_H, drawerUsable, layout))
	else
		top.AnchorPoint = Vector2.new(0.5, 0)
		top.Position = UDim2.new(0.5, 0, 0, 10)
		top.Size = UDim2.new(0, 300, 0, 56)
		hint.Position = UDim2.new(0.5, 0, 0, 70)
		toast.Position = UDim2.new(0.5, 0, 0, 98)
		-- Centred panels are lifted by half the control band so a touch tablet keeps them off
		-- the jump button; padDesign is 0 on desktop, where this is the original layout.
		-- The seed panel also has to stop short of the code panel below it. That frame is
		-- bottom-anchored and grows upward as its tap targets grow, and both panels are opaque,
		-- so where they meet the code frame simply covers the shop buttons. The seed panel is
		-- centred rather than top-anchored, so shortening it by X lifts its bottom edge by only
		-- X/2 â€” hence twice the code panel's real height plus a 12 px gap, multiplied by the
		-- scale because `usable` is screen px while codeH is design px. Where the panel has to
		-- shrink at all this leaves exactly 12 screen px between the two; on a desktop window it
		-- never binds, because 470 px already fits with room to spare.
		local seedUsable = usable - 2 * (codeH + 12) * layout.scale
		left.AnchorPoint = Vector2.new(0, 0.5)
		left.Position = UDim2.new(0, 12, 0.5, -padDesign / 2)
		left.Size = UDim2.new(0, leftW, 0, Responsive.fitHeight(DESIGN_LEFT_H, seedUsable, layout))
		codeFrame.AnchorPoint = Vector2.new(0, 1)
		codeFrame.Position = UDim2.new(0, 12, 1, -12 - padDesign)
		lb.AnchorPoint = Vector2.new(1, 0.5)
		lb.Position = UDim2.new(1, -12, 0.5, -padDesign / 2)
		lb.Size = UDim2.new(0, lbW, 0, Responsive.fitHeight(DESIGN_LB_H, usable, layout))
	end
	codeFrame.Size = UDim2.new(0, leftW, 0, codeH)

	-- The rows just changed height, so the seed panel's canvas has to follow them or the shop
	-- buttons at the bottom of the list become unreachable on the screen that needs them most.
	refreshCanvas()
	refreshDrawers()
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)

-- Every tap target above is sized from layout.controlPad, which comes from TouchEnabled, not
-- from the pixel size of the window. A viewport-only listener therefore never re-runs when a
-- device gains or loses touch without resizing â€” a Windows touch laptop, a phone handing over
-- to a paired controller â€” and the HUD keeps whichever set of sizes it happened to be built
-- with. So watch the flag as well.
--
-- Two deliberate details. This sits at the very bottom, below every OnClientEvent and Activated
-- handler: wiring a cosmetic listener before the state pipeline would mean a failure here left
-- a live player with a HUD frozen at its startup values and no hint that anything was wrong.
-- And the connect is wrapped in pcall for the same reason â€” the layout is cosmetic, the dust
-- counter and the leaderboard are not, and no failure of the former may cost a player the latter.
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
