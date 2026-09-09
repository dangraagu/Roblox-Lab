-- DEEP VEIN ⛏️ — klient-HUD. Havner i StarterPlayerScripts.
--
-- Ren visning + knapper. Serveren eier all økonomi, all graving og all posisjon: denne fila
-- sender bare intensjon ("kjøp hakke", "heis opp") og tegner det serveren svarer med. Selve
-- gravingen skjer ved å klikke steinene i verden (server-side ClickDetector), ikke herfra.
--
-- Mobil først: en UIScale på ROT-framen (ikke på ScreenGui, der gjør den ingenting), paneler
-- gjennom Responsive.sideWidth/fitHeight, ingenting klikkbart nede til venstre eller høyre
-- (der tegner Roblox styrestikka og hoppknappen), og ny layout når ViewportSize endrer seg.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local Ore = require(ReplicatedStorage:WaitForChild("Ore"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local remotes = ReplicatedStorage:WaitForChild("VeinRemotes")
local StateEvent = remotes:WaitForChild("State")
local BuyEvent = remotes:WaitForChild("Buy")
local ElevatorEvent = remotes:WaitForChild("Elevator")
local RebirthEvent = remotes:WaitForChild("Rebirth")
local ToastEvent = remotes:WaitForChild("Toast")
local LeaderboardEvent = remotes:WaitForChild("Leaderboard")

local MAXO = Config.MaxOre

local function corner(i, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = i
end
local function pad(i, px)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = i
end
local function cap(i, px)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = px
	c.Parent = i
end
local function oreColor(t)
	local c = Ore.color(Config, t)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local gui = Instance.new("ScreenGui")
gui.Name = "DeepVeinHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- A UIScale parented to a ScreenGui does nothing, so every element lives in this root frame and
-- the ROOT carries the scale. applyLayout also grows the root by 1/scale so root * scale lands
-- exactly on the viewport; forget that and the whole HUD shrinks into the top-left corner —
-- only on phones, where you are not looking.
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
	repeat task.wait() until workspace.CurrentCamera
	camera = workspace.CurrentCamera
end

local DESIGN_SHOP_W, DESIGN_SHOP_H = 258, 430
local DESIGN_LB_W, DESIGN_LB_H = 200, 280

-- IgnoreGuiInset is left false, so the drawable area is the viewport MINUS the topbar inset.
-- Every vertical budget has to come from that shorter height or a full-height panel overflows
-- the real bottom edge straight into the touch-control band this layout exists to keep clear.
local function effectiveHeight(vy: number): number
	if vy <= 0 or gui.IgnoreGuiInset then return vy end
	return math.max(1, vy - GuiService:GetGuiInset().Y)
end

local layout = Responsive.layout(camera.ViewportSize.X, effectiveHeight(camera.ViewportSize.Y),
	UserInputService.TouchEnabled, camera.ViewportSize.Y)

-- 44 screen px is the smallest comfortable tap target on both mobile platforms. A UIScale below
-- 1 shrinks every button on exactly the device that needs them biggest, so interactive elements
-- are sized in SCREEN space: divide the design size by the scale, never go under the floor.
local MIN_TAP = 44
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then return designPx end
	return math.ceil(math.max(designPx, MIN_TAP) / layout.scale)
end

--============================================================================ top readout

local top = Instance.new("Frame")
top.Name = "Readout"
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, 10)
top.Size = UDim2.new(0, 320, 0, 58)
top.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
top.BackgroundTransparency = 0.08
top.Parent = root
FxClient.theme(top, { corner = 12, stroke = Color3.fromRGB(120, 100, 60), strokeThickness = 1.5 })

local cashLabel = Instance.new("TextLabel")
cashLabel.BackgroundTransparency = 1
cashLabel.Size = UDim2.new(1, 0, 0.56, 0)
cashLabel.Font = Enum.Font.GothamBlack
cashLabel.TextScaled = true
cashLabel.TextColor3 = Color3.fromRGB(255, 214, 120)
cashLabel.Text = "$0"
cashLabel.Parent = top
cap(cashLabel, 28)

local depthLabel = Instance.new("TextLabel")
depthLabel.BackgroundTransparency = 1
depthLabel.Position = UDim2.new(0, 0, 0.56, 0)
depthLabel.Size = UDim2.new(1, 0, 0.44, 0)
depthLabel.Font = Enum.Font.GothamBold
depthLabel.TextScaled = true
depthLabel.TextColor3 = Color3.fromRGB(150, 200, 230)
depthLabel.Text = "⛏️ 0m deep"
depthLabel.Parent = top
cap(depthLabel, 16)

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0, 72)
hint.Size = UDim2.new(0.9, 0, 0, 22)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(210, 214, 230)
hint.Text = "👆 Click the rock under you to DIG · fill your bag · then hit 🛗 SURFACE to sell"
hint.Parent = root
cap(hint, 14)
do
	local sc = Instance.new("UISizeConstraint")
	sc.MaxSize = Vector2.new(500, math.huge)
	sc.Parent = hint
end

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 100)
toast.Size = UDim2.new(0.9, 0, 0, 24)
toast.BackgroundTransparency = 1
toast.Font = Enum.Font.GothamBold
toast.TextScaled = true
toast.TextColor3 = Color3.fromRGB(255, 210, 120)
toast.Text = ""
toast.Parent = root
cap(toast, 15)
do
	local sc = Instance.new("UISizeConstraint")
	sc.MaxSize = Vector2.new(500, math.huge)
	sc.Parent = toast
end
ToastEvent.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "string" then return end
	toast.Text = msg
	task.delay(3.5, function()
		if toast.Text == msg then toast.Text = "" end
	end)
end)

--============================================================================ shop panel

-- A ScrollingFrame, not a Frame: three upgrade rows plus the haul list plus rebirth does not fit
-- once the panel has to shrink to a phone, and a Frame just clips the bottom off silently.
local shop = Instance.new("ScrollingFrame")
shop.Name = "ShopPanel"
shop.AnchorPoint = Vector2.new(0, 0.5)
shop.Position = UDim2.new(0, 12, 0.5, 0)
shop.Size = UDim2.new(0, DESIGN_SHOP_W, 0, DESIGN_SHOP_H)
shop.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
shop.BackgroundTransparency = 0.1
shop.ScrollingDirection = Enum.ScrollingDirection.Y
shop.CanvasSize = UDim2.new(0, 0, 0, 0)
shop.ScrollBarThickness = 4
shop.ScrollBarImageColor3 = Color3.fromRGB(200, 160, 80)
shop.BorderSizePixel = 0
shop.ZIndex = 3
shop.Parent = root
corner(shop, 12)
pad(shop, 8)
local shopList = Instance.new("UIListLayout")
shopList.Padding = UDim.new(0, 4)
shopList.SortOrder = Enum.SortOrder.LayoutOrder
shopList.Parent = shop

-- AbsoluteContentSize is post-UIScale SCREEN px; CanvasSize is design px. Divide the scale back
-- out or the canvas comes up short on a phone and the rebirth button becomes unreachable.
local function refreshCanvas()
	shop.CanvasSize = UDim2.new(0, 0, 0, math.ceil(shopList.AbsoluteContentSize.Y / uiScale.Scale) + 8)
end
shopList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)
refreshCanvas()

local function sectionLabel(order, text, color)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 22)
	l.LayoutOrder = order
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = color
	l.Text = text
	l.Parent = shop
	cap(l, 16)
	return l
end

sectionLabel(0, "🎒 HAUL", Color3.fromRGB(150, 220, 255))

-- Backpack fill bar. This is the clock the whole loop runs on, so it is the first thing in the
-- panel and it is a bar rather than a number.
local bagFrame = Instance.new("Frame")
bagFrame.Size = UDim2.new(1, 0, 0, 20)
bagFrame.LayoutOrder = 1
bagFrame.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
bagFrame.Parent = shop
corner(bagFrame, 6)
local bagFill = Instance.new("Frame")
bagFill.Size = UDim2.new(0, 0, 1, 0)
bagFill.BackgroundColor3 = Color3.fromRGB(90, 200, 130)
bagFill.BorderSizePixel = 0
bagFill.Parent = bagFrame
corner(bagFill, 6)
local bagText = Instance.new("TextLabel")
bagText.BackgroundTransparency = 1
bagText.Size = UDim2.new(1, 0, 1, 0)
bagText.Font = Enum.Font.GothamBold
bagText.TextScaled = true
bagText.TextColor3 = Color3.fromRGB(240, 245, 255)
bagText.Text = "0 / 12"
bagText.ZIndex = 2
bagText.Parent = bagFrame
cap(bagText, 13)

local haulLabel = Instance.new("TextLabel")
haulLabel.BackgroundTransparency = 1
haulLabel.Size = UDim2.new(1, 0, 0, 18)
haulLabel.LayoutOrder = 2
haulLabel.Font = Enum.Font.GothamMedium
haulLabel.TextScaled = true
haulLabel.TextColor3 = Color3.fromRGB(255, 214, 120)
haulLabel.Text = "worth $0"
haulLabel.Parent = shop
cap(haulLabel, 13)

-- One row per ore tier, so a player can see what they are carrying without opening anything.
local oreRows = {}
for t = 1, MAXO do
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 16)
	l.LayoutOrder = 2 + t
	l.Font = Enum.Font.GothamMedium
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = oreColor(t)
	l.Text = Ore.name(Config, t) .. " x0"
	l.Visible = false
	l.Parent = shop
	cap(l, 12)
	oreRows[t] = l
end

sectionLabel(20, "⛏️ UPGRADES", Color3.fromRGB(255, 190, 100))

local shopButtons = {}
local function shopBtn(order, text, color, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 36)
	b.LayoutOrder = order
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.BackgroundColor3 = color
	b.Text = text
	b.Parent = shop
	corner(b, 6)
	cap(b, 13)
	b.Activated:Connect(cb)
	table.insert(shopButtons, b)
	return b
end

local pickBtn = shopBtn(21, "Pickaxe", Color3.fromRGB(150, 110, 60), function() BuyEvent:FireServer("pickaxe") end)
local bagBtn = shopBtn(22, "Backpack", Color3.fromRGB(70, 140, 90), function() BuyEvent:FireServer("backpack") end)
local lampBtn = shopBtn(23, "Lamp", Color3.fromRGB(180, 150, 60), function() BuyEvent:FireServer("lamp") end)

sectionLabel(30, "♻️ REBIRTH", Color3.fromRGB(200, 140, 255))

local rebirthBar = Instance.new("Frame")
rebirthBar.Size = UDim2.new(1, 0, 0, 14)
rebirthBar.LayoutOrder = 31
rebirthBar.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
rebirthBar.Parent = shop
corner(rebirthBar, 6)
local rebirthFill = Instance.new("Frame")
rebirthFill.Size = UDim2.new(0, 0, 1, 0)
rebirthFill.BackgroundColor3 = Color3.fromRGB(180, 110, 240)
rebirthFill.BorderSizePixel = 0
rebirthFill.Parent = rebirthBar
corner(rebirthFill, 6)

local rebirthBtn = shopBtn(32, "Rebirth", Color3.fromRGB(140, 80, 200), function() RebirthEvent:FireServer() end)

local saveWarn = Instance.new("TextLabel")
saveWarn.BackgroundTransparency = 1
saveWarn.Size = UDim2.new(1, 0, 0, 16)
saveWarn.LayoutOrder = 33
saveWarn.Font = Enum.Font.GothamMedium
saveWarn.TextScaled = true
saveWarn.TextColor3 = Color3.fromRGB(255, 130, 130)
saveWarn.Text = ""
saveWarn.Visible = false
saveWarn.Parent = shop
cap(saveWarn, 12)

--============================================================================ elevator

-- The core traversal control. NOT bottom-left or bottom-right: Roblox draws its own thumbstick
-- and jump button there and anything we put in that band can never be pressed.
local elevator = Instance.new("Frame")
elevator.Name = "Elevator"
elevator.AnchorPoint = Vector2.new(0.5, 1)
elevator.Position = UDim2.new(0.5, 0, 1, -14)
elevator.Size = UDim2.new(0, 300, 0, 44)
elevator.BackgroundTransparency = 1
elevator.ZIndex = 4
elevator.Parent = root
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 8)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = elevator
end

local elevatorButtons = {}
local function elevatorBtn(order, text, color, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 146, 1, 0)
	b.LayoutOrder = order
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.05
	b.Text = text
	b.ZIndex = 4
	b.Parent = elevator
	corner(b, 10)
	cap(b, 16)
	b.Activated:Connect(cb)
	table.insert(elevatorButtons, b)
	return b
end
elevatorBtn(1, "🛗 SURFACE + SELL", Color3.fromRGB(60, 140, 90), function() ElevatorEvent:FireServer("up") end)
elevatorBtn(2, "⬇️ DESCEND", Color3.fromRGB(70, 90, 160), function() ElevatorEvent:FireServer("down") end)

--============================================================================ leaderboard

local board = Instance.new("Frame")
board.Name = "Board"
board.AnchorPoint = Vector2.new(1, 0.5)
board.Position = UDim2.new(1, -12, 0.5, 0)
board.Size = UDim2.new(0, DESIGN_LB_W, 0, DESIGN_LB_H)
board.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
board.BackgroundTransparency = 0.18
board.ZIndex = 3
board.Parent = root
corner(board, 12)
pad(board, 8)

local boardTitle = Instance.new("TextLabel")
boardTitle.BackgroundTransparency = 1
boardTitle.Size = UDim2.new(1, 0, 0, 24)
boardTitle.Font = Enum.Font.GothamBlack
boardTitle.TextScaled = true
boardTitle.TextColor3 = Color3.fromRGB(255, 215, 90)
boardTitle.Text = "🏆 DEEPEST"
boardTitle.Parent = board
cap(boardTitle, 17)

local boardList = Instance.new("ScrollingFrame")
boardList.BackgroundTransparency = 1
boardList.Position = UDim2.new(0, 0, 0, 28)
boardList.Size = UDim2.new(1, 0, 1, -28)
boardList.ScrollingDirection = Enum.ScrollingDirection.Y
boardList.CanvasSize = UDim2.new(0, 0, 0, 0)
boardList.ScrollBarThickness = 4
boardList.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 90)
boardList.BorderSizePixel = 0
boardList.Parent = board
local boardLayout = Instance.new("UIListLayout")
boardLayout.Padding = UDim.new(0, 3)
boardLayout.Parent = boardList
boardLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	boardList.CanvasSize = UDim2.new(0, 0, 0, math.ceil(boardLayout.AbsoluteContentSize.Y / uiScale.Scale) + 4)
end)

LeaderboardEvent.OnClientEvent:Connect(function(topList)
	for _, c in ipairs(boardList:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	for i, e in ipairs(topList) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, 22)
		l.LayoutOrder = i
		l.Font = Enum.Font.GothamMedium
		l.TextScaled = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = Color3.fromRGB(225, 230, 245)
		local name = "Miner"
		local okn, res = pcall(function() return Players:GetNameFromUserIdAsync(e.userId) end)
		if okn then name = res end
		l.Text = string.format("%d. %s — %dm", i, name, e.depth)
		l.Parent = boardList
		cap(l, 14)
	end
end)

--============================================================================ state render

local lastRebirths = nil

StateEvent.OnClientEvent:Connect(function(s)
	cashLabel.Text = "$" .. tostring(s.cash)
	depthLabel.Text = string.format("⛏️ %dm deep  ·  best %dm  ·  wall %dm", s.depth, s.bestDepth, s.maxDepth)

	local frac = (s.capacity > 0) and math.clamp(s.carried / s.capacity, 0, 1) or 0
	bagFill.Size = UDim2.new(frac, 0, 1, 0)
	bagFill.BackgroundColor3 = (frac >= 1) and Color3.fromRGB(220, 90, 90) or Color3.fromRGB(90, 200, 130)
	bagText.Text = s.carried .. " / " .. s.capacity
	haulLabel.Text = (s.carried > 0) and ("worth $" .. s.haulValue) or "empty — go dig"

	for t = 1, MAXO do
		local n = (s.inventory and s.inventory[tostring(t)]) or 0
		oreRows[t].Visible = n > 0
		oreRows[t].Text = Ore.name(Config, t) .. " x" .. n
	end

	if s.pickCost then
		pickBtn.Text = s.pickName .. " (⚡" .. s.pickPower .. ") → $" .. s.pickCost
		pickBtn.BackgroundColor3 = (s.cash >= s.pickCost) and Color3.fromRGB(150, 110, 60)
			or Color3.fromRGB(70, 62, 56)
	else
		pickBtn.Text = s.pickName .. " (⚡" .. s.pickPower .. ") — MAX"
		pickBtn.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	end

	if s.backpackCost then
		bagBtn.Text = "Backpack " .. s.capacity .. " → " .. (s.capacity + Config.Economy.Backpack.PerLevel)
			.. "  $" .. s.backpackCost
		bagBtn.BackgroundColor3 = (s.cash >= s.backpackCost) and Color3.fromRGB(70, 140, 90)
			or Color3.fromRGB(56, 66, 60)
	else
		bagBtn.Text = "Backpack " .. s.capacity .. " — MAX"
		bagBtn.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	end

	if s.lampCost then
		lampBtn.Text = "Lamp " .. s.lampRadius .. " → " .. (s.lampRadius + Config.Economy.Lamp.PerLevel)
			.. "  $" .. s.lampCost
		lampBtn.BackgroundColor3 = (s.cash >= s.lampCost) and Color3.fromRGB(180, 150, 60)
			or Color3.fromRGB(72, 66, 50)
	else
		lampBtn.Text = "Lamp " .. s.lampRadius .. " — MAX"
		lampBtn.BackgroundColor3 = Color3.fromRGB(80, 84, 100)
	end

	rebirthFill.Size = UDim2.new(math.clamp(s.rebirthProgress, 0, 1), 0, 1, 0)
	if s.canRebirth then
		rebirthBtn.Text = "♻️ REBIRTH → x" .. string.format("%.1f", s.mult + Config.Prestige.MultiplierPerRebirth)
		rebirthBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 200)
	else
		rebirthBtn.Text = "Rebirth " .. s.rebirths .. " (x" .. string.format("%.1f", s.mult)
			.. ") · need $" .. s.rebirthCost
		rebirthBtn.BackgroundColor3 = Color3.fromRGB(66, 56, 82)
	end

	-- A read-only session (another server holds the lock) is the one thing a player must be told
	-- about before they spend an hour in it.
	saveWarn.Visible = (s.canSave == false)
	saveWarn.Text = "⚠️ Progress is NOT saving this session"

	-- Rebirth juice: the payoff for the only irreversible button in the game.
	if lastRebirths ~= nil and s.rebirths > lastRebirths then
		FxClient.flash(Color3.fromRGB(200, 150, 255), 0.55, 0.7)
		FxClient.fovPunch(14)
	end
	lastRebirths = s.rebirths
end)

--============================================================================ responsive layout

local openDrawer: string? = nil
local toggleButtons: { [string]: TextButton } = {}
local TOGGLE_SHUT = Color3.fromRGB(34, 34, 46)
local TOGGLE_OPEN = Color3.fromRGB(70, 140, 90)

local function refreshDrawers()
	local compact = layout.compact
	shop.Visible = (not compact) or openDrawer == "shop"
	board.Visible = (not compact) or openDrawer == "board"
	for k, b in pairs(toggleButtons) do
		b.BackgroundColor3 = if openDrawer == k then TOGGLE_OPEN else TOGGLE_SHUT
	end
end

local function setDrawer(k: string)
	openDrawer = if openDrawer == k then nil else k
	refreshDrawers()
end

local TOGGLE_W, TOGGLE_H, TOGGLE_GAP = 96, 28, 6

local toggleBar = Instance.new("Frame")
toggleBar.Name = "Toggles"
toggleBar.BackgroundTransparency = 1
toggleBar.BorderSizePixel = 0
toggleBar.Position = UDim2.new(0, 12, 0, 10)
toggleBar.Size = UDim2.new(0, 2 * TOGGLE_W + TOGGLE_GAP, 0, TOGGLE_H)
toggleBar.Visible = false
toggleBar.ZIndex = 4
toggleBar.Parent = root
do
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, TOGGLE_GAP)
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Parent = toggleBar
end

local function toggleBtn(order: number, k: string, text: string)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, TOGGLE_W, 1, 0)
	b.LayoutOrder = order
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(235, 238, 248)
	b.BackgroundColor3 = TOGGLE_SHUT
	b.BackgroundTransparency = 0.1
	b.Text = text
	b.ZIndex = 4
	b.Parent = toggleBar
	corner(b, 6)
	cap(b, 13)
	b.Activated:Connect(function() setDrawer(k) end)
	toggleButtons[k] = b
end
toggleBtn(1, "shop", "⛏️ Shop")
toggleBtn(2, "board", "🏆 Top")

local function applyLayout()
	local v = camera.ViewportSize
	local effY = effectiveHeight(v.Y)
	layout = Responsive.layout(v.X, effY, UserInputService.TouchEnabled, v.Y)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	local padDesign = layout.controlPad / layout.scale
	local usable = Responsive.usableHeight(effY, layout)
	local rootW = v.X / layout.scale
	local shopW = Responsive.sideWidth(DESIGN_SHOP_W, v.X, layout)
	local boardW = Responsive.sideWidth(DESIGN_LB_W, v.X, layout)

	local shopH = touchSize(36)
	for _, b in ipairs(shopButtons) do
		b.Size = UDim2.new(1, 0, 0, shopH)
	end

	-- The elevator pair is the most important control on the screen, so it is sized in screen
	-- space like the shop buttons and lifted clear of the touch band entirely.
	local elevH = touchSize(44)
	local elevW = math.min(160, math.floor((rootW - 40) / 2))
	for _, b in ipairs(elevatorButtons) do
		b.Size = UDim2.new(0, elevW, 1, 0)
	end
	elevator.Size = UDim2.new(0, 2 * elevW + 8, 0, elevH)
	elevator.Position = UDim2.new(0.5, 0, 1, -14 - padDesign)

	-- Panels must also stop short of the elevator row, which is bottom-anchored and grows upward
	-- as its tap targets grow. Centred panels move by half of what they lose, hence the doubling.
	local elevBand = (elevH + 22) * layout.scale
	toggleBar.Visible = layout.compact

	if layout.compact then
		local toggleW, toggleH = touchSize(TOGGLE_W), touchSize(TOGGLE_H)
		local room = rootW - 2 * 12 - TOGGLE_GAP - 130 - 8
		if 2 * toggleW > room then toggleW = math.max(1, math.floor(room / 2)) end
		local barW = 2 * toggleW + TOGGLE_GAP
		toggleBar.Size = UDim2.new(0, barW, 0, toggleH)
		for _, b in pairs(toggleButtons) do
			b.Size = UDim2.new(0, toggleW, 1, 0)
		end

		top.AnchorPoint = Vector2.new(1, 0)
		top.Position = UDim2.new(1, -12, 0, 10)
		top.Size = UDim2.new(0, math.clamp(rootW - 12 - barW - 8 - 12, 130, 320), 0, toggleH)

		local hintY = 10 + toggleH + 6
		local toastY = hintY + 26
		local drawerTop = toastY + 28
		hint.Position = UDim2.new(0.5, 0, 0, hintY)
		toast.Position = UDim2.new(0.5, 0, 0, toastY)

		local drawerUsable = math.max(60, usable - drawerTop * layout.scale - elevBand)
		shop.AnchorPoint = Vector2.new(0, 0)
		shop.Position = UDim2.new(0, 12, 0, drawerTop)
		shop.Size = UDim2.new(0, shopW, 0, Responsive.fitHeight(DESIGN_SHOP_H, drawerUsable, layout))
		board.AnchorPoint = Vector2.new(1, 0)
		board.Position = UDim2.new(1, -12, 0, drawerTop)
		board.Size = UDim2.new(0, boardW, 0, Responsive.fitHeight(DESIGN_LB_H, drawerUsable, layout))
	else
		top.AnchorPoint = Vector2.new(0.5, 0)
		top.Position = UDim2.new(0.5, 0, 0, 10)
		top.Size = UDim2.new(0, 320, 0, 58)
		hint.Position = UDim2.new(0.5, 0, 0, 72)
		toast.Position = UDim2.new(0.5, 0, 0, 100)

		local sideUsable = usable - 2 * elevBand
		shop.AnchorPoint = Vector2.new(0, 0.5)
		shop.Position = UDim2.new(0, 12, 0.5, -padDesign / 2)
		shop.Size = UDim2.new(0, shopW, 0, Responsive.fitHeight(DESIGN_SHOP_H, sideUsable, layout))
		board.AnchorPoint = Vector2.new(1, 0.5)
		board.Position = UDim2.new(1, -12, 0.5, -padDesign / 2)
		board.Size = UDim2.new(0, boardW, 0, Responsive.fitHeight(DESIGN_LB_H, sideUsable, layout))
	end

	refreshCanvas()
	refreshDrawers()
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)

-- Every tap target above is sized from layout.controlPad, which comes from TouchEnabled and not
-- from the size of the window. A viewport-only listener never re-runs when a device gains or
-- loses touch without resizing. This sits at the very bottom, below every OnClientEvent handler,
-- and in a pcall: the layout is cosmetic, the cash counter is not, and no failure of the former
-- may cost a player the latter.
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
