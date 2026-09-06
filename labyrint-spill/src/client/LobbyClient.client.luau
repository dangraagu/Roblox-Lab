--[[==================================================================
	LABYRINT-SPILL  -  LOBBY NIVÅ-VELGER (klient)
	Laget for Marius & onkel :)

	I lobby-modus åpner Solo- og Friends-dørene denne velgeren (serveren sender
	LobbyRemotes/OpenPicker). Spilleren velger "Continue" (neste nivå) eller et
	spesifikt nivå 1..accepted+1, og vi sender valget tilbake (StartRun). Group-
	døra trenger ingen velger (matches direkte). All tekst er engelsk.

	The picker is a centred modal. It is sized from Responsive, so on a phone it
	shrinks to fit and sits above Roblox's touch controls instead of under them.
==================================================================]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

-- Shared sizing rules so this HUD survives a phone. Note the require form: a bare string
-- require like `require("./Responsive")` resolves in the luau CLI but is invalid in Roblox.
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local TouchTarget = require(ReplicatedStorage:WaitForChild("TouchTarget"))

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

-- A UIScale does nothing parented to a ScreenGui, so the picker hangs off this root Frame
-- and the root is what the scale acts on.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- The size the picker was drawn at.
local PANEL_W, PANEL_H = 360, 380

local layout = Responsive.layout(camera.ViewportSize.X, camera.ViewportSize.Y, UserInputService.TouchEnabled)

-- A control drawn 44 px tall comes out at 44 * scale on screen, which is 26 px on a phone —
-- too small for a thumb. Both helpers below only do anything where the player is on touch
-- (controlPad is non-zero exactly then); on a mouse-driven window they hand back the design
-- number untouched.
--
--   tap()  — something the player presses. Grown by 1/scale AND floored at 44 screen px.
--   grow() — text size caps and label rows. Grown, but no floor, or a 13 px cap would come
--            out enormous. Text still has to shrink to fit.
--
-- The arithmetic lives in the shared TouchTarget module rather than in a copy per file.
local function tap(designPx)
	return TouchTarget.tap(designPx, layout)
end
local function grow(designPx)
	return TouchTarget.grow(designPx, layout)
end

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.BackgroundColor3 = Color3.fromRGB(28, 31, 44)
panel.BorderSizePixel = 0
-- A plain Frame does not consume input, so a drag across the picker would fall through and
-- swing the camera behind it. This is a modal; it should absorb what lands on it.
panel.Active = true
panel.Parent = root
corner(panel, 14)

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
closeBtn.Size = UDim2.fromOffset(44, 44)
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

-- AbsoluteContentSize is post-UIScale SCREEN px; CanvasSize offsets are pre-scale DESIGN px.
-- Without dividing the scale back out the canvas is short by exactly that factor, and only
-- where scale < 1 — a 1080p monitor looks fine while a phone loses the bottom rows of levels.
local function syncCanvas()
	local scale = uiScale.Scale
	if scale <= 0 then scale = 1 end
	scroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(grid.AbsoluteContentSize.Y / scale) + 8)
end

local function rebuild(accepted)
	continueBtn.Text = "▶ Continue  →  Level " .. (accepted + 1)
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("TextButton") then ch:Destroy() end
	end
	-- nivåer 1..accepted+1 (accepted+1 = neste; <= accepted = replay)
	for lvl = 1, accepted + 1 do
		local b = Instance.new("TextButton")
		b.Size = grid.CellSize
		b.LayoutOrder = lvl
		b.BackgroundColor3 = (lvl == accepted + 1) and Color3.fromRGB(70, 110, 170) or Color3.fromRGB(52, 56, 74)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.Text = tostring(lvl)
		b.Parent = scroll
		local tsc = Instance.new("UITextSizeConstraint"); tsc.MaxTextSize = grow(16); tsc.Parent = b
		corner(b, 6)
		b.Activated:Connect(function() choose(lvl) end)
	end
	syncCanvas()
end
grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)

continueBtn.Activated:Connect(function()
	-- Continue = accepted+1; serveren klamper uansett.
	local acc = tonumber(gui:GetAttribute("accepted")) or 0
	choose(acc + 1)
end)

--==========================  RESPONSIVT OPPSETT  =================--
-- Re-lays the picker for the current viewport: never wider than the screen, never taller
-- than the room left above Roblox's touch controls, and every level button kept at a size
-- a thumb can actually hit.
local function applyLayout()
	local v = camera.ViewportSize
	layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale
	-- Grow the root by 1/scale so root * scale lands exactly on the viewport. Skip this and
	-- the picker shrinks into the top-left corner on a phone while looking fine on desktop.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	local viewX = if v.X > 0 then v.X else Responsive.REF_X
	local rootW = viewX / layout.scale
	local panelW = math.max(200, math.min(PANEL_W, math.floor(rootW) - 2 * Responsive.MARGIN))
	local panelH = Responsive.fitHeight(PANEL_H, Responsive.usableHeight(v.Y, layout), layout)
	panel.Size = UDim2.fromOffset(panelW, panelH)
	-- Centre it in the room that is actually free: lifting it by half the touch-control band
	-- keeps the bottom row of level buttons clear of the movement stick and the jump button.
	panel.Position = UDim2.new(0.5, 0, 0.5, -math.floor(layout.controlPad / layout.scale / 2))

	local closeW = tap(44)
	closeBtn.Size = UDim2.fromOffset(closeW, closeW)
	title.Position = UDim2.fromOffset(closeW + 16, 8)
	title.Size = UDim2.new(1, -2 * (closeW + 16), 0, grow(34))
	ttc.MaxTextSize = grow(22)

	-- Stack the body from the title down, so every row keeps its gap when the parts grow.
	local contY = 10 + grow(34) + 4
	local contH = tap(48)
	continueBtn.Position = UDim2.fromOffset(10, contY)
	continueBtn.Size = UDim2.new(1, -20, 0, contH)
	ctc.MaxTextSize = grow(20)

	local pickY = contY + contH + 8
	local pickH = grow(18)
	pickLabel.Position = UDim2.fromOffset(10, pickY)
	pickLabel.Size = UDim2.new(1, -20, 0, pickH)
	ptc.MaxTextSize = grow(13)

	local scrollY = pickY + pickH + 6
	scroll.Position = UDim2.fromOffset(10, scrollY)
	scroll.Size = UDim2.new(1, -20, 1, -(scrollY + 8))

	-- The grid owns the size of every level button, and the buttons copy it on rebuild.
	grid.CellSize = UDim2.fromOffset(tap(56), tap(44))
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)

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
			applyLayout()
			gui.Enabled = true
		end)
	end
end)
