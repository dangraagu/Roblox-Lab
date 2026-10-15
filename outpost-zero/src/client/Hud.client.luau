-- OUTPOST ZERO — the HUD. Client only (StarterPlayerScripts). DISPLAY ONLY: it shows the player's own State, the
-- toasts and the public announcements, marks the ★ lot, and draws the owner's Census rows on their own board.
-- There is no client -> server remote: building happens at the lot, through the prompt Roblox draws itself.
--
-- Phone first (docs/new-game-checklist.md §2b): a root Frame owns the UIScale and is sized 1/scale; every rectangle
-- comes from HudLayout (the same function Sky.client.luau uses for its chip, ☕ Break and warning, so the two can
-- never overlap); nothing tappable sits in the bottom-left or bottom-right band (Roblox's thumbstick and jump
-- button); tap targets reach 44 screen px on touch; everything re-lays out on Camera.ViewportSize and TouchEnabled.
-- Layout:  top centre   credits · (band chip, Sky) · balance · Orders · ★ line · (warning, Sky) · toast · hint
--          right edge   (☕ Break, Sky) · ★ Show me
-- Headless checks: robloxemu/check_outpostzero_hud.luau (hudcheck, overlap = true) and
-- robloxemu/check_outpostzero_board.luau (the Census renders, only in the owner's PlayerGui).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local HudLayout = require(ReplicatedStorage:WaitForChild("HudLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait(0.1)
	camera = workspace.CurrentCamera
end

local remotes = ReplicatedStorage:WaitForChild("CityRemotes")
local StateR = remotes:WaitForChild("State") :: RemoteEvent
local ToastR = remotes:WaitForChild("Toast") :: RemoteEvent
local FxR = remotes:WaitForChild("Fx") :: RemoteEvent
local BoardR = remotes:WaitForChild("Board") :: RemoteEvent
local AnnounceR = remotes:WaitForChild("Announce") :: RemoteEvent

local short = Economy.short
local T = Config.Tutorial

--============================================================================ building blocks
local gui = Instance.new("ScreenGui")
gui.Name = "OutpostHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 1
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local PANEL_BG = Color3.fromRGB(18, 20, 34)
local GOLD = Color3.fromRGB(255, 215, 90)
local HOME = Color3.fromRGB(120, 200, 255)
local WORK = Color3.fromRGB(255, 196, 110)

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end
local function stroke(inst: Instance, colour: Color3)
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = 1.5
	s.Transparency = 0.35
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
end
local function panel(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = PANEL_BG
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 10)
	return f
end
local function label(parent: Instance, name: string, x: number, w: number, font, colour: Color3, maxSize: number, align): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.new(x, 8, 0, 0)
	t.Size = UDim2.new(w, -16, 1, 0)
	t.Font = font
	t.TextColor3 = colour
	t.TextScaled = true
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	t.Text = ""
	t.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = t
	return t
end

--============================================================================ the top stack
local creditsPanel = panel("CreditsPanel", root)
stroke(creditsPanel, GOLD)
local creditsText = label(creditsPanel, "CreditsText", 0, 0.62, Enum.Font.GothamBlack, GOLD, 26, Enum.TextXAlignment.Left)
creditsText.Text = "30 credits"
local rateText = label(creditsPanel, "RateText", 0.62, 0.38, Enum.Font.GothamBold, Color3.fromRGB(220, 230, 255), 16, Enum.TextXAlignment.Right)

-- the balance bar: settlers against jobs
local balancePanel = panel("BalancePanel", root)
local balanceBar = Instance.new("Frame")
balanceBar.Name = "BalanceBar"
balanceBar.BackgroundColor3 = WORK
balanceBar.BorderSizePixel = 0
balanceBar.Position = UDim2.new(0, 6, 0.18, 0)
balanceBar.Size = UDim2.new(0.38, -6, 0.64, 0)
balanceBar.Parent = balancePanel
corner(balanceBar, 6)
local homesFill = Instance.new("Frame")
homesFill.Name = "HomesFill"
homesFill.BackgroundColor3 = HOME
homesFill.BorderSizePixel = 0
homesFill.Size = UDim2.fromScale(0.5, 1)
homesFill.Parent = balanceBar
corner(homesFill, 6)
local balanceText = label(balancePanel, "BalanceText", 0.38, 0.62, Enum.Font.GothamBold, Color3.fromRGB(235, 240, 255), 15, Enum.TextXAlignment.Left)

local ordersPanel = panel("OrdersPanel", root)
local ordersText = label(ordersPanel, "OrdersText", 0, 1, Enum.Font.GothamBold, Color3.fromRGB(230, 240, 255), 16)

local starPanel = panel("StarPanel", root)
starPanel.BackgroundColor3 = Color3.fromRGB(44, 36, 16)
stroke(starPanel, GOLD)
local starText = label(starPanel, "StarText", 0, 1, Enum.Font.GothamBold, GOLD, 16)

local toastPanel = panel("ToastPanel", root)
toastPanel.Visible = false
local toastText = label(toastPanel, "ToastText", 0, 1, Enum.Font.GothamBold, Color3.fromRGB(255, 244, 214), 16)

local hintPanel = panel("HintPanel", root)
hintPanel.BackgroundColor3 = Color3.fromRGB(30, 44, 70)
hintPanel.Visible = false
local hintText = label(hintPanel, "HintText", 0, 1, Enum.Font.GothamBold, Color3.fromRGB(230, 244, 255), 16)

--============================================================================ ★ Show me
local showSlot = Instance.new("Frame")
showSlot.Name = "ShowSlot"
showSlot.BackgroundTransparency = 1
showSlot.BorderSizePixel = 0
showSlot.Parent = root
local showBtn = Instance.new("TextButton")
showBtn.Name = "ShowMeButton"
showBtn.Size = UDim2.fromScale(1, 1)
showBtn.BackgroundColor3 = Color3.fromRGB(150, 116, 30)
showBtn.Font = Enum.Font.GothamBlack
showBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
showBtn.TextScaled = true
showBtn.Text = "★ Show me"
showBtn.AutoButtonColor = true
showBtn.Parent = showSlot
corner(showBtn, 10)
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 18
	c.Parent = showBtn
end

--============================================================================ layout
local function apply(inst: GuiObject, r: any)
	inst.Position = UDim2.fromOffset(r.x, r.y)
	inst.Size = UDim2.fromOffset(r.w, r.h)
end
local function applyLayout()
	local v = camera.ViewportSize
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, topLeft = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and topLeft ~= nil then topLeft.Y else 0
	end
	local L = HudLayout.compute(Responsive, v.X, v.Y, UserInputService.TouchEnabled, inset)
	uiScale.Scale = L.scale
	root.Size = UDim2.fromScale(1 / L.scale, 1 / L.scale)
	apply(creditsPanel, L.credits)
	apply(balancePanel, L.balance)
	apply(ordersPanel, L.orders)
	apply(starPanel, L.star)
	apply(toastPanel, L.toast)
	apply(hintPanel, L.hint)
	apply(showSlot, L.showBtn)
end
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

--============================================================================ toasts
local toastToken = 0
local function showToast(text: string)
	toastToken += 1
	local mine = toastToken
	toastText.Text = text
	toastPanel.Visible = true
	task.delay(3.5, function()
		if toastToken == mine then toastPanel.Visible = false end
	end)
end
ToastR.OnClientEvent:Connect(function(text)
	if type(text) == "string" then showToast(text) end
end)
AnnounceR.OnClientEvent:Connect(function(ev)
	if type(ev) == "table" and ev.kind == "text" and type(ev.text) == "string" then showToast("📣 " .. ev.text) end
end)

--============================================================================ the ★ over the lot, and ★ Show me
-- Both are client-only: a BillboardGui and a soft light on the starred lot's own sign post (the interactive thing
-- reads as interactive), and for 4 s a beam from the avatar to it. Nothing here replicates.
local localFolder = Instance.new("Folder")
localFolder.Name = "HudLocal"
localFolder.Parent = playerGui
local latest: any = nil
local starPost: BasePart? = nil
local starMarker: BillboardGui? = nil
local starLight: PointLight? = nil

local function postFor(key: string?): BasePart?
	if latest == nil or key == nil then return nil end
	local shelves = workspace:FindFirstChild("Shelves")
	local shelf = shelves and shelves:FindFirstChild("Shelf_" .. tostring(latest.shelf))
	local lots = shelf and shelf:FindFirstChild("Lots")
	local lot = lots and lots:FindFirstChild("Lot_" .. key)
	return lot and lot:FindFirstChild("Post") :: BasePart?
end

local function markStar()
	local post = postFor(latest and latest.star and latest.star.key)
	if post == starPost and (post == nil or (starMarker and starMarker.Adornee == post)) then return end
	starPost = post
	if starMarker == nil then
		local bb = Instance.new("BillboardGui")
		bb.Name = "StarMarker"
		bb.Size = UDim2.fromOffset(60, 60)
		bb.StudsOffset = Vector3.new(0, 4.5, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 300
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = GOLD
		t.TextStrokeTransparency = 0.3
		t.Text = "★"
		t.Parent = bb
		bb.Parent = localFolder
		starMarker = bb
	end
	(starMarker :: BillboardGui).Adornee = post;
	(starMarker :: BillboardGui).Enabled = post ~= nil
	if starLight then
		starLight:Destroy()
		starLight = nil
	end
	if post then
		local light = Instance.new("PointLight")
		light.Name = "StarGlow"
		light.Color = GOLD
		light.Range = 12
		light.Brightness = 1.4
		light.Parent = post
		starLight = light
	end
end

local beamToken = 0
local showBeam: Beam? = nil
showBtn.Activated:Connect(function()
	local post = postFor(latest and latest.star and latest.star.key)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if post == nil or hrp == nil then
		showToast(if latest and latest.complete then "Your skyline is complete: nothing left to build." else "No ★ yet: your city is loading.")
		return
	end
	beamToken += 1
	local mine = beamToken
	if showBeam then
		showBeam:Destroy()
		showBeam = nil
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "ShowMeFrom"
	a0.Parent = hrp
	local a1 = Instance.new("Attachment")
	a1.Name = "ShowMeTo"
	a1.Position = Vector3.new(0, 2, 0)
	a1.Parent = post
	local beam = Instance.new("Beam")
	beam.Name = "ShowMeBeam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(GOLD)
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = a0
	showBeam = beam
	task.delay(4, function()
		if beamToken ~= mine then return end
		a0:Destroy()
		a1:Destroy()
		showBeam = nil
	end)
end)

--============================================================================ the owner's state
local starHintUntil: number? = nil
local sawEarlyTutorial = false

local function render(st: any)
	creditsText.Text = short(st.credits) .. " credits"
	rateText.Text = if (st.rate or 0) > 0.5 then "+" .. short(st.rate) .. "/min" elseif st.income > 0 then "+" .. short(st.income * 60) .. "/min" else ""
	-- balance
	local total = math.max(1, st.settlers + st.jobs)
	homesFill.Size = UDim2.fromScale(if st.settlers + st.jobs > 0 then st.settlers / total else 0.5, 1)
	balanceText.Text = Economy.balanceText({ settlers = st.settlers, jobs = st.jobs })
	-- Orders
	if st.complete then
		ordersText.Text = "👑 Skyline complete"
	elseif (st.ordersLeft or 0) > 0 then
		ordersText.Text = "📋 Orders " .. Economy.clock(st.ordersLeft)
	elseif st.net then
		ordersText.Text = "📋 Orders out: the workers save up for your next build"
	elseif st.population > 0 then
		ordersText.Text = T.Idle
	else
		ordersText.Text = "📋 Build to give your workers Orders"
	end
	-- the ★ line
	local s = st.star
	if s then
		local zone = if s.zone == "H" then "Home" else "Workshop"
		local ready = if st.credits >= s.price then "ready now" elseif (s.wait or math.huge) < math.huge then "ready in " .. Economy.clock(s.wait) else "save up"
		starText.Text = string.format("★ %s · storey %d · %s · %s", zone, s.storey, short(s.price), ready)
	else
		starText.Text = if st.complete then "★ Every lot is topped out" else "★ …"
	end
	-- the hint: saving first, then the first-minutes tutorial (the persisted step, so a rejoin resumes)
	local hint = ""
	if not st.loaded then
		hint = T.Loading
	elseif not st.saving then
		hint = if st.lockChanged then T.LockChanged elseif st.lockedElsewhere then T.NotSavingLocked else T.NotSaving
	elseif st.tutorial == 0 then
		sawEarlyTutorial = true
		hint = T.Walk
	elseif st.tutorial == 1 then
		sawEarlyTutorial = true
		hint = if st.settlers > st.jobs then T.NeedJobs else T.NeedHomes
	elseif st.tutorial == 2 then
		sawEarlyTutorial = true
		hint = T.Orders
	elseif st.tutorial == 3 and sawEarlyTutorial then
		-- the last hint, once, for a while; a returning player who is past it never sees it again
		if starHintUntil == nil then starHintUntil = tick() + T.StarHintSeconds end
		if tick() < (starHintUntil :: number) then hint = T.Star end
	end
	hintText.Text = hint
	hintPanel.Visible = hint ~= ""
end

local ensureBoardGui: () -> ()

StateR.OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then return end
	latest = st
	render(st)
	markStar()
	ensureBoardGui()
end)
FxR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	if ev.kind == "district" and type(ev.name) == "string" then
		showToast("🏗️ " .. ev.name .. " is open: new lots on your shelf")
	end
end)

--============================================================================ the Census, on the owner's own board
-- A SurfaceGui in THIS player's PlayerGui with Adornee = their own board, so their friends list and rows reach only
-- them. It sits in a Folder so it is never mistaken for screen furniture.
local boardFolder = Instance.new("Folder")
boardFolder.Name = "BoardGuis"
boardFolder.Parent = playerGui
local surface: SurfaceGui? = nil
local rowsFrame: Frame? = nil
local statusText: TextLabel? = nil
local modeText: TextLabel? = nil
local footerText: TextLabel? = nil
local pendingBoard: any = nil

local function boardText(parent: Instance, name: string, y: number, h: number, font, colour: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.04, y)
	t.Size = UDim2.fromScale(0.92, h)
	t.Font = font
	t.TextColor3 = colour
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = ""
	t.Parent = parent
	return t
end

local renderBoard: (any) -> ()

ensureBoardGui = function()
	if surface ~= nil or latest == nil then return end
	local shelves = workspace:FindFirstChild("Shelves")
	local shelf = shelves and shelves:FindFirstChild("Shelf_" .. tostring(latest.shelf))
	local board = shelf and shelf:FindFirstChild("Board")
	local face = board and board:FindFirstChild("BoardFace")
	if face == nil then return end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Census"
	sg.Adornee = face
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0
	sg.ResetOnSpawn = false
	sg.ZOffset = 1
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	bg.BorderSizePixel = 0
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = sg
	modeText = boardText(bg, "ModeText", 0.02, 0.12, Enum.Font.GothamBlack, GOLD)
	local rf = Instance.new("Frame")
	rf.Name = "Rows"
	rf.BackgroundTransparency = 1
	rf.Position = UDim2.fromScale(0, 0.15)
	rf.Size = UDim2.fromScale(1, 0.62)
	rf.Parent = bg
	rowsFrame = rf
	statusText = boardText(bg, "StatusText", 0.78, 0.1, Enum.Font.GothamBold, Color3.fromRGB(200, 214, 240))
	footerText = boardText(bg, "FooterText", 0.89, 0.09, Enum.Font.Gotham, Color3.fromRGB(170, 180, 210))
	sg.Parent = boardFolder
	surface = sg
	if pendingBoard then renderBoard(pendingBoard) end
end

renderBoard = function(payload: any)
	pendingBoard = payload
	if surface == nil or rowsFrame == nil then return end
	local rf = rowsFrame :: Frame
	for _, c in rf:GetChildren() do c:Destroy() end
	;(modeText :: TextLabel).Text = if payload.mode == "friends" then "📊 CENSUS · FRIENDS" else "📊 CENSUS · EVERYONE"
	local rows = payload.rows or {}
	local slots = Config.Board.Rows
	local n = math.min(#rows, slots) -- the server already sends at most `slots`, the viewer's own row among them
	for i = 1, n do
		local r = rows[i]
		local t = Instance.new("TextLabel")
		t.Name = "Row_" .. i
		t.BackgroundTransparency = if r.you then 0.6 else 1
		t.BackgroundColor3 = Color3.fromRGB(90, 70, 20)
		t.Position = UDim2.fromScale(0.04, (i - 1) / slots)
		t.Size = UDim2.fromScale(0.92, 1 / slots)
		t.Font = if r.you then Enum.Font.GothamBlack else Enum.Font.GothamBold
		t.TextColor3 = if r.you then GOLD else Color3.fromRGB(235, 240, 255)
		t.TextScaled = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		local rank = if (r.rank or 0) > 0 then tostring(r.rank) .. "." else "—"
		t.Text = string.format("%s %s  %s %s", rank, tostring(r.name), tostring(r.emoji), Economy.group(r.pop or 0))
		t.Parent = rf
	end
	;(statusText :: TextLabel).Text = payload.status or ""
	;(footerText :: TextLabel).Text = (payload.footer or "") .. "  ·  Use the board's prompt: Everyone / Friends"
end
BoardR.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then renderBoard(payload) end
end)
