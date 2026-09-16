-- Hud.client.luau — HUD for "Nightwatch Manor: Haunted Escape Tycoon".
--
-- DISPLAY ONLY. Every action in this game is an in-world ProximityPrompt (take a relic, escape,
-- enter the manor, buy an upgrade), so this file sends nothing to the server and has exactly two
-- interactive controls: the drawer toggles on a phone. It renders what the State remote pushes
-- and narrates what the Notice remote announces.
--
-- Layout goes through Responsive.luau. Most Roblox players are on a phone, and a HUD authored
-- in fixed desktop pixels is unusable there: the two panels collapse behind top-edge toggles in
-- compact mode, nothing interactive is ever drawn in the bottom-left or bottom-right (Roblox's
-- own thumbstick and jump button own those), and the upgrade list is a ScrollingFrame whose
-- canvas is recomputed from its real content size.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local plr = Players.LocalPlayer
-- Shared modules are required the ROBLOX way — with an Instance. Never `require("./Responsive")`:
-- a path string resolves in the luau CLI and is invalid here, which kills the whole LocalScript.
--
-- Config is deliberately NOT required: every number and every piece of copy this file renders
-- arrives in the State payload, so the HUD cannot drift out of step with what the server
-- actually charged or granted.
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local Remotes = ReplicatedStorage:WaitForChild("ManorRemotes")
local StateRemote = Remotes:WaitForChild("State") :: RemoteEvent
local NoticeRemote = Remotes:WaitForChild("Notice") :: RemoteEvent

-- CurrentCamera is normally already there, but it is nil for the first frames of a slow join and
-- every layout decision below reads its ViewportSize. Indexing nil would take the HUD with it.
local camera = workspace.CurrentCamera
while not camera do
	task.wait()
	camera = workspace.CurrentCamera
end

local gui = Instance.new("ScreenGui")
gui.Name = "NightwatchHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = plr:WaitForChild("PlayerGui")

-- A UIScale does NOTHING parented to a ScreenGui, so everything hangs off this root Frame and
-- the scale rides on the root instead.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local layout = Responsive.layout(camera.ViewportSize.X, camera.ViewportSize.Y, UserInputService.TouchEnabled)

local DARK = Color3.fromRGB(16, 14, 20)
local ACCENT = Color3.fromRGB(214, 168, 96) -- candlelight
local WARN = Color3.fromRGB(228, 74, 74)
local GOOD = Color3.fromRGB(110, 205, 135)
local MUTED = Color3.fromRGB(196, 192, 205)

-- Roblox's own guidance and both mobile platform guidelines put the smallest comfortable tap
-- target at 44 SCREEN px. Below that a control is drawn but not reliably hittable with a thumb.
local TAP_MIN = 44
local TOGGLE_W_STATUS = 108
local TOGGLE_W_HOUSE = 132

-- Interactive controls are sized in SCREEN px, not design px: a UIScale below 1 shrinks every
-- button on exactly the device whose players need them biggest. Dividing the design size by the
-- scale keeps a control the same physical size whatever the scale is; the ceil keeps a derived
-- size from landing a fraction of a pixel under the bar.
local function tapSize(designPx: number): number
	if layout.controlPad <= 0 then
		return designPx
	end
	return math.ceil(math.max(designPx, TAP_MIN) / layout.scale)
end

local function tapText(designSize: number): number
	if layout.controlPad <= 0 then
		return designSize
	end
	return math.floor(designSize / layout.scale)
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, ts: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = Color3.fromRGB(236, 232, 240)
	l.TextScaled = false
	l.TextSize = ts
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function capWidth(g: GuiObject, maxX: number)
	local c = Instance.new("UISizeConstraint")
	c.MaxSize = Vector2.new(maxX, math.huge)
	c.Parent = g
end

--============================================================================ status panel

local panel = Instance.new("Frame")
panel.Name = "Status"
panel.Size = UDim2.fromOffset(250, 138)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Parent = root
FxClient.theme(panel, { corner = 10, stroke = Color3.fromRGB(150, 110, 60), strokeThickness = 1.5, strokeTransparency = 0.4 })

local titleLbl = label(panel, "SAFEHOUSE", UDim2.new(1, -28, 0, 32), UDim2.fromOffset(14, 8), 26)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextColor3 = ACCENT

local carryLbl = label(panel, "Carrying: nothing", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 42), 15)
local stashLbl = label(panel, "Stash: 0 relics", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 62), 15)
local bestLbl = label(panel, "Best night: 0", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 82), 15)

-- Dread meter. Only meaningful during a night; in the safehouse it is emptied and relabelled.
local dreadTrack = Instance.new("Frame")
dreadTrack.Name = "DreadTrack"
dreadTrack.Size = UDim2.new(1, -28, 0, 10)
dreadTrack.Position = UDim2.fromOffset(14, 110)
dreadTrack.BackgroundColor3 = Color3.fromRGB(44, 40, 50)
dreadTrack.BorderSizePixel = 0
dreadTrack.Parent = panel
Instance.new("UICorner", dreadTrack).CornerRadius = UDim.new(1, 0)

local dreadFill = Instance.new("Frame")
dreadFill.Name = "DreadFill"
dreadFill.Size = UDim2.fromScale(0, 1)
dreadFill.BackgroundColor3 = GOOD
dreadFill.BorderSizePixel = 0
dreadFill.Parent = dreadTrack
Instance.new("UICorner", dreadFill).CornerRadius = UDim.new(1, 0)

local dreadLbl = label(panel, "The manor sleeps", UDim2.new(1, -28, 0, 16), UDim2.fromOffset(14, 122), 13)
dreadLbl.TextColor3 = MUTED

--========================================================================= safehouse panel

local house = Instance.new("Frame")
house.Name = "Safehouse"
house.AnchorPoint = Vector2.new(1, 0)
house.Size = UDim2.fromOffset(300, 368)
house.Position = UDim2.new(1, -16, 0, 16)
house.BackgroundColor3 = DARK
house.BackgroundTransparency = 0.2
house.BorderSizePixel = 0
house.Parent = root
FxClient.theme(house, { corner = 10, stroke = Color3.fromRGB(150, 110, 60), strokeThickness = 1.5, strokeTransparency = 0.4 })

local houseTitle = label(house, "SAFEHOUSE — hub level 0", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 8), 16)
houseTitle.Font = Enum.Font.GothamBold
houseTitle.TextColor3 = ACCENT
local houseHint = label(house, "Walk onto a pad in the safehouse and press E to buy.", UDim2.new(1, -24, 0, 30), UDim2.fromOffset(12, 30), 13)
houseHint.TextColor3 = MUTED
houseHint.TextWrapped = true

local list = Instance.new("ScrollingFrame")
list.Name = "UpgradeList"
list.Size = UDim2.new(1, -20, 1, -70)
list.Position = UDim2.fromOffset(10, 62)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = house

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = list

-- AbsoluteContentSize is post-UIScale SCREEN px; CanvasSize is design px. Mixing the two is
-- invisible on a monitor (scale 1) and silently costs a phone player the bottom of the list.
local function refreshCanvas()
	list.CanvasSize = UDim2.new(0, 0, 0, math.ceil(listLayout.AbsoluteContentSize.Y / math.max(uiScale.Scale, 0.01)) + 8)
end
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshCanvas)

local rows: { [string]: { frame: Frame, name: TextLabel, cost: TextLabel } } = {}

local function ensureRow(id: string, order: number)
	local existing = rows[id]
	if existing then
		return existing
	end
	local f = Instance.new("Frame")
	f.Name = "Row_" .. id
	f.Size = UDim2.new(1, -6, 0, 44)
	f.BackgroundColor3 = Color3.fromRGB(30, 26, 34)
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	f.LayoutOrder = order
	f.Parent = list
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)

	local nameLbl = label(f, "", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(10, 4), 14)
	nameLbl.Font = Enum.Font.GothamBold
	local costLbl = label(f, "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(10, 23), 12)
	costLbl.TextColor3 = MUTED

	local row = { frame = f, name = nameLbl, cost = costLbl }
	rows[id] = row
	return row
end

--============================================================================ help + toasts

local HELP_DAY = "Buy upgrades on the pads, then walk into the manor door and press E."
local HELP_DAY_SHORT = "Buy on the pads. Manor door = E."
local HELP_NIGHT = "Take relics (E), then reach the Servants' Exit before the manor wakes."
local HELP_NIGHT_SHORT = "Grab relics. Find the exit."

local help = label(root, HELP_DAY, UDim2.new(0.9, 0, 0, 24), UDim2.new(0.5, 0, 0, 20), 15)
help.AnchorPoint = Vector2.new(0.5, 0)
help.TextXAlignment = Enum.TextXAlignment.Center
help.TextColor3 = Color3.fromRGB(206, 200, 214)
capWidth(help, 680)

local toast = label(root, "", UDim2.new(0.9, 0, 0, 40), UDim2.new(0.5, 0, 0.5, -140), 28)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Font = Enum.Font.GothamBold
toast.TextXAlignment = Enum.TextXAlignment.Center
capWidth(toast, 640)

local toastDetail = label(root, "", UDim2.new(0.9, 0, 0, 26), UDim2.new(0.5, 0, 0.5, -98), 18)
toastDetail.AnchorPoint = Vector2.new(0.5, 0)
toastDetail.TextXAlignment = Enum.TextXAlignment.Center
toastDetail.TextColor3 = Color3.fromRGB(212, 206, 220)
capWidth(toastDetail, 680)

local function showToast(text: string, color: Color3, detail: string?, lifetime: number?)
	toast.Text = text
	toast.TextColor3 = color
	toast.TextTransparency = 0
	toastDetail.Text = detail or ""
	toastDetail.TextTransparency = 0
	task.spawn(function()
		local mine = text
		local steps = math.max(1, math.floor((lifetime or 2) / 0.06))
		for i = 1, steps do
			if toast.Text ~= mine then
				return
			end
			toast.TextTransparency = i / steps
			toastDetail.TextTransparency = i / steps
			task.wait(0.06)
		end
		if toast.Text == mine then
			toast.Text = ""
			toastDetail.Text = ""
		end
	end)
end

-- The "it has seen you" banner. Deliberately NOT a toast: it is a state, not an event, and it
-- has to stay on screen for exactly as long as the server says it is true.
local seen = label(root, "IT SEES YOU", UDim2.new(0.9, 0, 0, 34), UDim2.new(0.5, 0, 0.16, 0), 24)
seen.AnchorPoint = Vector2.new(0.5, 0)
seen.Font = Enum.Font.GothamBold
seen.TextXAlignment = Enum.TextXAlignment.Center
seen.TextColor3 = WARN
seen.Visible = false
capWidth(seen, 520)

--============================================================================ phone drawers

local statusOpen, houseOpen = true, true

local function toggleButton(name: string, text: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(TOGGLE_W_STATUS, 30)
	b.BackgroundColor3 = DARK
	b.BackgroundTransparency = 0.15
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = ACCENT
	b.TextSize = 16
	b.Text = text
	b.AutoButtonColor = true
	b.Visible = false
	b.Parent = root
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end

local statusToggle = toggleButton("StatusToggle", "STATUS")
local houseToggle = toggleButton("SafehouseToggle", "SAFEHOUSE")
houseToggle.AnchorPoint = Vector2.new(1, 0)

--============================================================================ layout

local function applyLayout()
	local v = camera.ViewportSize
	layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale
	-- CRITICAL: grow the root by 1/scale so root * scale lands exactly on the viewport. Skip
	-- this and the whole HUD shrinks into the top-left corner on phones while looking perfect
	-- on desktop, where the scale is 1 and the bug is invisible.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	local compact = layout.compact
	local usable = Responsive.usableHeight(v.Y, layout)
	local insetTop = GuiService:GetGuiInset().Y / layout.scale
	local topY = if compact then insetTop + 8 else 16
	local toggleH = tapSize(30)
	local statusW = tapSize(TOGGLE_W_STATUS)
	local houseW = tapSize(TOGGLE_W_HOUSE)
	local drawerY = topY + toggleH + 8
	local topRoom = math.max(40, usable - (if compact then drawerY else 16) * layout.scale)

	statusToggle.Visible = compact
	houseToggle.Visible = compact
	statusToggle.Size = UDim2.fromOffset(statusW, toggleH)
	houseToggle.Size = UDim2.fromOffset(houseW, toggleH)
	statusToggle.TextSize = tapText(16)
	houseToggle.TextSize = tapText(16)
	statusToggle.Position = UDim2.new(0, 12, 0, topY)
	houseToggle.Position = UDim2.new(1, -12, 0, topY)

	panel.Size = UDim2.new(0, Responsive.sideWidth(250, v.X, layout), 0, Responsive.fitHeight(138, topRoom, layout))
	panel.Position = if compact then UDim2.new(0, 12, 0, drawerY) else UDim2.fromOffset(16, 16)
	panel.Visible = (not compact) or statusOpen

	house.Size = UDim2.new(0, Responsive.sideWidth(300, v.X, layout), 0, Responsive.fitHeight(368, topRoom, layout))
	house.Position = if compact then UDim2.new(1, -12, 0, drawerY) else UDim2.new(1, -16, 0, 16)
	house.Visible = (not compact) or houseOpen

	-- The help line takes the gap the toggles leave on a phone rather than a fixed fraction of
	-- the screen, which would run underneath them in portrait.
	help.TextWrapped = compact
	if compact then
		local rootW = v.X / layout.scale
		local gapLeft = rootW / 2 - (12 + statusW) - 8
		local gapRight = rootW / 2 - (12 + houseW) - 8
		help.Size = UDim2.new(0, math.max(120, 2 * math.min(gapLeft, gapRight)), 0, toggleH)
		help.Position = UDim2.new(0.5, 0, 0, topY)
	else
		help.Size = UDim2.new(0.9, 0, 0, 24)
		help.Position = UDim2.new(0.5, 0, 0, 20)
	end

	-- Toasts move into the upper third on a phone rather than sitting over the middle of a dark
	-- corridor, and get room for a second line there.
	toast.TextWrapped = compact
	toastDetail.TextWrapped = compact
	seen.TextWrapped = compact
	if compact then
		toast.Size = UDim2.new(0.62, 0, 0, 60)
		toast.Position = UDim2.new(0.5, 0, 0.3, 0)
		toastDetail.Size = UDim2.new(0.62, 0, 0, 44)
		toastDetail.Position = UDim2.new(0.5, 0, 0.3, 64)
		seen.Size = UDim2.new(0.62, 0, 0, 30)
		seen.Position = UDim2.new(0.5, 0, 0.19, 0)
	else
		toast.Size = UDim2.new(0.9, 0, 0, 40)
		toast.Position = UDim2.new(0.5, 0, 0.5, -140)
		toastDetail.Size = UDim2.new(0.9, 0, 0, 26)
		toastDetail.Position = UDim2.new(0.5, 0, 0.5, -98)
		seen.Size = UDim2.new(0.9, 0, 0, 34)
		seen.Position = UDim2.new(0.5, 0, 0.16, 0)
	end

	refreshCanvas()
end

statusToggle.Activated:Connect(function()
	statusOpen = not statusOpen
	applyLayout()
end)
houseToggle.Activated:Connect(function()
	houseOpen = not houseOpen
	applyLayout()
end)

-- Both signals matter. ViewportSize alone misses a device where only the touch flag changed
-- (a touch laptop, or Studio's device emulator switching input), and the tap-target sizes are
-- decided by exactly that flag.
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)

--============================================================================ state

-- On a phone both drawers start CLOSED: the whole game is looking down a dark corridor, and a
-- HUD that owns half the screen is the complaint a sibling game actually received.
if layout.compact then
	statusOpen = false
	houseOpen = false
end
applyLayout()

local function describeCarry(count: number, worth: number): string
	if count <= 0 then
		return "Carrying: nothing"
	end
	return string.format("Carrying: %d relic%s (%d)", count, if count == 1 then "" else "s", worth)
end

StateRemote.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then
		return
	end
	local night = tonumber(s.night) or 1
	local isNight = s.phase == "NIGHT"

	titleLbl.Text = if isNight then string.format("NIGHT %d", night) else "SAFEHOUSE"
	titleLbl.TextColor3 = if isNight then WARN else ACCENT
	carryLbl.Text = describeCarry(tonumber(s.carried) or 0, tonumber(s.carriedWorth) or 0)
	stashLbl.Text = string.format("Stash: %d relics", tonumber(s.stash) or 0)
	bestLbl.Text = string.format("Best night: %d%s", tonumber(s.best) or 0, if s.canSave == false then "  (not saving)" else "")

	local dread = math.clamp(tonumber(s.dread) or 0, 0, 1)
	dreadFill.Size = UDim2.fromScale(if isNight then dread else 0, 1)
	dreadFill.BackgroundColor3 = if dread > 0.75 then WARN elseif dread > 0.4 then ACCENT else GOOD
	if isNight then
		dreadLbl.Text = string.format("Dread %d%%  ·  %ds left  ·  relics %d/%d",
			math.floor(dread * 100), math.floor(tonumber(s.secondsLeft) or 0),
			(tonumber(s.relicsTotal) or 0) - (tonumber(s.relicsLeft) or 0), tonumber(s.relicsTotal) or 0)
	else
		dreadLbl.Text = "The manor sleeps. Night " .. night .. " is waiting."
	end

	-- Two different warnings, and they must not be confused with each other: SPOTTED is "it is
	-- coming for you", NEAR is only what the Alarm Bell heard through a wall.
	if isNight and s.spotted == true then
		seen.Text = "IT SEES YOU"
		seen.TextColor3 = WARN
		seen.Visible = true
	elseif isNight and s.near == true then
		seen.Text = "THE BELL RINGS — SOMETHING IS CLOSE"
		seen.TextColor3 = ACCENT
		seen.Visible = true
	else
		seen.Visible = false
	end
	help.Text = if isNight
		then (if layout.compact then HELP_NIGHT_SHORT else HELP_NIGHT)
		else (if layout.compact then HELP_DAY_SHORT else HELP_DAY)

	houseTitle.Text = string.format("SAFEHOUSE — hub level %d", tonumber(s.hubLevel) or 0)
	if type(s.upgrades) == "table" then
		for i, u in s.upgrades do
			local row = ensureRow(tostring(u.id), i)
			row.name.Text = string.format("%s  Lv %d/%d", tostring(u.name), tonumber(u.level) or 0, tonumber(u.max) or 0)
			if u.cost == nil then
				row.cost.Text = "fully built"
				row.cost.TextColor3 = GOOD
			else
				local cost = tonumber(u.cost) or 0
				local affordable = (tonumber(s.stash) or 0) >= cost
				row.cost.Text = string.format("%d relics  ·  %s", cost, tostring(u.blurb))
				row.cost.TextColor3 = if affordable then ACCENT else MUTED
			end
		end
		refreshCanvas()
	end
end)

NoticeRemote.OnClientEvent:Connect(function(n)
	if type(n) ~= "table" then
		return
	end
	local kind = tostring(n.kind)
	local text = tostring(n.text or "")
	local detail = if n.detail ~= nil then tostring(n.detail) else nil

	if kind == "CAUGHT" then
		showToast(text, WARN, detail, 3)
		FxClient.flash(Color3.fromRGB(150, 20, 20), 0.55, 0.6)
		FxClient.shake(0.6, 2.2)
	elseif kind == "EVICTED" then
		showToast(text, WARN, detail, 3)
		FxClient.flash(Color3.fromRGB(90, 40, 130), 0.4, 0.7)
	elseif kind == "EXTRACTED" then
		showToast(text, GOOD, detail, 3)
		FxClient.fovPunch(-6, 0.15, 0.5)
	elseif kind == "SPOTTED" then
		showToast(text, WARN, detail, 1.4)
		FxClient.shake(0.35, 1.2)
	elseif kind == "NEAR" then
		showToast(text, ACCENT, detail, 1.2)
	elseif kind == "NIGHT" then
		showToast(text, ACCENT, detail, 3)
	elseif kind == "DENIED" then
		showToast(text, MUTED, nil, 1.8)
	elseif kind == "BOUGHT" then
		showToast(text, GOOD, nil, 1.6)
	elseif kind == "TOOK" then
		showToast(text, ACCENT, nil, 1.2)
	elseif kind == "READONLY" then
		showToast(text, WARN, detail, 4)
	else
		showToast(text, MUTED, detail, 2)
	end
end)
