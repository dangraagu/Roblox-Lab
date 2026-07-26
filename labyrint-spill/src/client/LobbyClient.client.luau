--[[==================================================================
	LABYRINT-SPILL  -  LOBBY NIVÅ-VELGER (klient)
	Laget for Marius & onkel :)

	I lobby-modus åpner Solo- og Friends-dørene denne velgeren (serveren sender
	LobbyRemotes/OpenPicker). Spilleren velger "Continue" (neste nivå) eller et
	spesifikt nivå 1..accepted+1, og vi sender valget tilbake (StartRun). Group-
	døra trenger ingen velger (matches direkte). All tekst er engelsk.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--==========================  GUI  ===============================--
local old = playerGui:FindFirstChild("LobbyPicker")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyPicker"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 14
gui.Enabled = false
gui.Parent = playerGui

local function corner(inst, r)
	local u = Instance.new("UICorner"); u.CornerRadius = UDim.new(0, r or 8); u.Parent = inst
end

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(360, 380)
panel.BackgroundColor3 = Color3.fromRGB(28, 31, 44)
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 14)
local pscale = Instance.new("UIScale"); pscale.Parent = panel
local function fit()
	local vp = gui.AbsoluteSize
	if vp.X > 0 and vp.Y > 0 then
		pscale.Scale = math.clamp(math.min((vp.X - 24) / 360, (vp.Y - 24) / 380), 0.5, 1)
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 34)
title.Position = UDim2.fromOffset(10, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Solo Climb"
title.Parent = panel
local ttc = Instance.new("UITextSizeConstraint"); ttc.MaxTextSize = 22; ttc.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -8, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextScaled = true
closeBtn.Text = "✕"
closeBtn.Parent = panel
corner(closeBtn, 8)
closeBtn.Activated:Connect(function() gui.Enabled = false end)

local currentMode = "solo"
local startRunEvent  -- fylles ut

local function choose(level)
	if startRunEvent then startRunEvent:FireServer(level, currentMode) end
	gui.Enabled = false
end

-- Stor "Continue"-knapp (neste nivå).
local continueBtn = Instance.new("TextButton")
continueBtn.Size = UDim2.new(1, -20, 0, 48)
continueBtn.Position = UDim2.fromOffset(10, 48)
continueBtn.BackgroundColor3 = Color3.fromRGB(70, 140, 90)
continueBtn.TextColor3 = Color3.new(1, 1, 1)
continueBtn.Font = Enum.Font.GothamBold
continueBtn.TextScaled = true
continueBtn.Text = "▶ Continue"
continueBtn.Parent = panel
corner(continueBtn, 10)
local ctc = Instance.new("UITextSizeConstraint"); ctc.MaxTextSize = 20; ctc.Parent = continueBtn

local pickLabel = Instance.new("TextLabel")
pickLabel.Size = UDim2.new(1, -20, 0, 18)
pickLabel.Position = UDim2.fromOffset(10, 104)
pickLabel.BackgroundTransparency = 1
pickLabel.Font = Enum.Font.GothamMedium
pickLabel.TextColor3 = Color3.fromRGB(180, 186, 200)
pickLabel.TextScaled = true
pickLabel.TextXAlignment = Enum.TextXAlignment.Left
pickLabel.Text = "…or replay a level you've unlocked:"
pickLabel.Parent = panel
local ptc = Instance.new("UITextSizeConstraint"); ptc.MaxTextSize = 13; ptc.Parent = pickLabel

-- Rullbar rute med nivå-knapper (1 .. accepted+1).
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -136)
scroll.Position = UDim2.fromOffset(10, 128)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new()
scroll.Parent = panel
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(56, 40)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

local function rebuild(accepted)
	continueBtn.Text = "▶ Continue  →  Level " .. (accepted + 1)
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("TextButton") then ch:Destroy() end
	end
	-- nivåer 1..accepted+1 (accepted+1 = neste; <= accepted = replay)
	for lvl = 1, accepted + 1 do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(56, 40)
		b.LayoutOrder = lvl
		b.BackgroundColor3 = (lvl == accepted + 1) and Color3.fromRGB(70, 110, 170) or Color3.fromRGB(52, 56, 74)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.Text = tostring(lvl)
		b.Parent = scroll
		local tsc = Instance.new("UITextSizeConstraint"); tsc.MaxTextSize = 16; tsc.Parent = b
		corner(b, 6)
		b.Activated:Connect(function() choose(lvl) end)
	end
	scroll.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 8)
end
grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 8)
end)

continueBtn.Activated:Connect(function()
	-- Continue = accepted+1; serveren klamper uansett.
	local acc = tonumber(gui:GetAttribute("accepted")) or 0
	choose(acc + 1)
end)

--==================  KOBLE TIL SERVEREN  ========================--
task.spawn(function()
	local lobby = ReplicatedStorage:WaitForChild("LobbyRemotes", 30)
	if not lobby then return end
	startRunEvent = lobby:WaitForChild("StartRun", 15)
	local openPicker = lobby:WaitForChild("OpenPicker", 15)
	if openPicker then
		openPicker.OnClientEvent:Connect(function(info)
			if type(info) ~= "table" then return end
			local accepted = tonumber(info.accepted) or 0
			currentMode = (info.mode == "friends") and "friends" or "solo"
			title.Text = (currentMode == "friends") and "Host: Play with Friends" or "Solo Climb"
			gui:SetAttribute("accepted", accepted)
			pcall(rebuild, accepted)
			fit()
			gui.Enabled = true
		end)
	end
end)
