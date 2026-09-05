-- +1 JUMP EVERY STEP — klient-HUD. Havner i StarterPlayerScripts.
-- Ren visning: lytter på server-tilstand og tegner teller/rebirth/koder/topp-10.
-- Ingen spill-autoritet her (serveren eier jump power).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Plus1Remotes")
local StateEvent = remotes:WaitForChild("State")
local RebirthEvent = remotes:WaitForChild("Rebirth")
local RedeemFunc = remotes:WaitForChild("Redeem")
local LeaderboardEvent = remotes:WaitForChild("Leaderboard")

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

local gui = Instance.new("ScreenGui")
gui.Name = "Plus1Hud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- ── Topp-panel: stor jump power-teller ──────────────────────────────────────
local top = Instance.new("Frame")
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, 12)
top.Size = UDim2.new(0, 360, 0, 92)
top.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
top.BackgroundTransparency = 0.1
top.Parent = gui
corner(top, 14)

local jumpLabel = Instance.new("TextLabel")
jumpLabel.BackgroundTransparency = 1
jumpLabel.Size = UDim2.new(1, 0, 0, 52)
jumpLabel.Position = UDim2.new(0, 0, 0, 6)
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
subLabel.Size = UDim2.new(1, 0, 0, 26)
subLabel.Position = UDim2.new(0, 0, 0, 60)
subLabel.Font = Enum.Font.GothamMedium
subLabel.TextColor3 = Color3.fromRGB(220, 225, 240)
subLabel.TextScaled = true
subLabel.Text = "Jump Power · step every tile for +1"
subLabel.Parent = top
do
	local cc = Instance.new("UITextSizeConstraint"); cc.MaxTextSize = 16; cc.Parent = subLabel
end

-- ── Venstre panel: tier / best / multiplier + rebirth ───────────────────────
local left = Instance.new("Frame")
left.AnchorPoint = Vector2.new(0, 0.5)
left.Position = UDim2.new(0, 12, 0.5, 0)
left.Size = UDim2.new(0, 210, 0, 210)
left.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
left.BackgroundTransparency = 0.15
left.Parent = gui
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

-- ── Koder (nederst til venstre) ─────────────────────────────────────────────
local codeFrame = Instance.new("Frame")
codeFrame.AnchorPoint = Vector2.new(0, 1)
codeFrame.Position = UDim2.new(0, 12, 1, -12)
codeFrame.Size = UDim2.new(0, 210, 0, 76)
codeFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
codeFrame.BackgroundTransparency = 0.15
codeFrame.Parent = gui
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
lbFrame.AnchorPoint = Vector2.new(1, 0.5)
lbFrame.Position = UDim2.new(1, -12, 0.5, 0)
lbFrame.Size = UDim2.new(0, 200, 0, 300)
lbFrame.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
lbFrame.BackgroundTransparency = 0.2
lbFrame.Parent = gui
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

local lbList = Instance.new("Frame")
lbList.BackgroundTransparency = 1
lbList.Position = UDim2.new(0, 0, 0, 30)
lbList.Size = UDim2.new(1, 0, 1, -30)
lbList.Parent = lbFrame
local lbLayout = Instance.new("UIListLayout")
lbLayout.Padding = UDim.new(0, 3)
lbLayout.Parent = lbList

local function renderLeaderboard(top)
	for _, c in ipairs(lbList:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	for i, entry in ipairs(top) do
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

-- ── State-oppdatering ───────────────────────────────────────────────────────
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
