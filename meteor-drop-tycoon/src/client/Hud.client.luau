-- METEOR DROP TYCOON — the HUD. Client only (StarterPlayerScripts). DISPLAY ONLY: it shows the player's own
-- State, sends Buy(kind) and nothing else, and draws the owner's Star Chart rows on their own board.
--
-- Phone first (docs/new-game-checklist.md §2b): a root Frame owns the UIScale and is sized 1/scale; every
-- rectangle comes from HudLayout (the same function Sky.client.luau uses for its chip, Stargaze button and
-- warning, so the two can never overlap); nothing tappable sits in the bottom-left or bottom-right band
-- (Roblox's thumbstick and jump button); tap targets reach 44 screen px on touch; everything re-lays out on
-- Camera.ViewportSize, on TouchEnabled, and when the upgrade panel opens or closes.
-- Layout:  top centre   wallet · (band chip, Sky) · hopper bar · (hazard warning, Sky) · toast · hint
--          right edge   ⬆ Upgrades · (☕ Stargaze, Sky); the upgrade panel opens at the right edge
-- Headless checks: robloxemu/check_meteordroptycoon_hud.luau (hudcheck, overlap = true) and
-- robloxemu/check_meteordroptycoon_board.luau (the Star Chart renders, only in the owner's PlayerGui).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Meteors = require(ReplicatedStorage:WaitForChild("Meteors"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local HudLayout = require(ReplicatedStorage:WaitForChild("HudLayout"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait(0.1)
	camera = workspace.CurrentCamera
end

local remotes = ReplicatedStorage:WaitForChild("MeteorRemotes")
local StateR = remotes:WaitForChild("State") :: RemoteEvent
local ToastR = remotes:WaitForChild("Toast") :: RemoteEvent
local FxR = remotes:WaitForChild("Fx") :: RemoteEvent
local BoardR = remotes:WaitForChild("Board") :: RemoteEvent
local AnnounceR = remotes:WaitForChild("Announce") :: RemoteEvent
local BuyR = remotes:WaitForChild("Buy") :: RemoteEvent

local bands = Config.Env.Bands
local short = Economy.short

--============================================================================ building blocks
local gui = Instance.new("ScreenGui")
gui.Name = "MeteorHud"
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
local function button(name: string, parent: Instance, text: string, colour: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = colour
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 18
	c.Parent = b
	return b
end

--============================================================================ the top stack
local wallet = panel("WalletPanel", root)
stroke(wallet, GOLD)
local dustText = label(wallet, "StardustText", 0, 0.6, Enum.Font.GothamBlack, GOLD, 26, Enum.TextXAlignment.Left)
dustText.Text = "⭐ 0"
local rateText = label(wallet, "RateText", 0.6, 0.4, Enum.Font.GothamBold, Color3.fromRGB(220, 230, 255), 16, Enum.TextXAlignment.Right)

local hopperPanel = panel("HopperPanel", root)
local hopperBar = Instance.new("Frame")
hopperBar.Name = "HopperBar"
hopperBar.BackgroundColor3 = Color3.fromRGB(46, 48, 64)
hopperBar.BorderSizePixel = 0
hopperBar.Position = UDim2.new(0, 6, 0.2, 0)
hopperBar.Size = UDim2.new(0.55, -6, 0.6, 0)
hopperBar.Parent = hopperPanel
corner(hopperBar, 6)
local hopperFill = Instance.new("Frame")
hopperFill.Name = "HopperFill"
hopperFill.BackgroundColor3 = Color3.fromRGB(255, 190, 90)
hopperFill.BorderSizePixel = 0
hopperFill.Size = UDim2.fromScale(0, 1)
hopperFill.Parent = hopperBar
corner(hopperFill, 6)
local hopperText = Instance.new("TextLabel")
hopperText.Name = "HopperText"
hopperText.BackgroundTransparency = 1
hopperText.Size = UDim2.fromScale(1, 1)
hopperText.Font = Enum.Font.GothamBold
hopperText.TextColor3 = Color3.fromRGB(255, 255, 255)
hopperText.TextScaled = true
hopperText.Text = "🔥 Hopper"
hopperText.Parent = hopperBar
local awakeText = label(hopperPanel, "AwakeText", 0.55, 0.45, Enum.Font.GothamBold, Color3.fromRGB(170, 230, 255), 14, Enum.TextXAlignment.Right)

local toastPanel = panel("ToastPanel", root)
toastPanel.Visible = false
local toastText = label(toastPanel, "ToastText", 0, 1, Enum.Font.GothamBold, Color3.fromRGB(255, 244, 214), 16)

local hintPanel = panel("HintPanel", root)
hintPanel.BackgroundColor3 = Color3.fromRGB(30, 44, 70)
hintPanel.Visible = false
local hintText = label(hintPanel, "HintText", 0, 1, Enum.Font.GothamBold, Color3.fromRGB(230, 244, 255), 16)

-- the Falling Star card (transient, never Active: it cannot eat a tap)
local starCard = Instance.new("TextLabel")
starCard.Name = "StarCard"
starCard.BackgroundTransparency = 1
starCard.Active = false
starCard.Font = Enum.Font.GothamBlack
starCard.TextColor3 = GOLD
starCard.TextStrokeTransparency = 0.3
starCard.TextScaled = true
starCard.Visible = false
starCard.Parent = root

--============================================================================ the button column and the panel
local upgradeSlot = Instance.new("Frame")
upgradeSlot.Name = "UpgradeSlot"
upgradeSlot.BackgroundTransparency = 1
upgradeSlot.BorderSizePixel = 0
upgradeSlot.Parent = root
local upgradeBtn = button("UpgradeButton", upgradeSlot, "⬆ Upgrades", Color3.fromRGB(70, 140, 90))
upgradeBtn.Size = UDim2.fromScale(1, 1)

local panelFrame = Instance.new("ScrollingFrame")
panelFrame.Name = "UpgradePanel"
panelFrame.BackgroundColor3 = PANEL_BG
panelFrame.BackgroundTransparency = 0.1
panelFrame.BorderSizePixel = 0
panelFrame.ScrollBarThickness = 6
panelFrame.ScrollingDirection = Enum.ScrollingDirection.Y
panelFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
panelFrame.Visible = false
panelFrame.Parent = root
corner(panelFrame, 12)
stroke(panelFrame, GOLD)
-- Rows are placed explicitly from HudLayout.panelRows (no UIListLayout), so the positions hudcheck measures
-- are exactly the positions Roblox draws; the canvas is the rows' own extent, in design px.

local ROWS = {
	{ kind = "beacon", icon = "🗼", title = "Beacon" },
	{ kind = "collector", icon = "📡", title = "Collector" },
	{ kind = "smelter", icon = "🔥", title = "Smelter" },
}
local rowUi = {}
for i, def in ROWS do
	local row = Instance.new("Frame")
	row.Name = "Row_" .. def.kind
	row.LayoutOrder = i
	row.BackgroundColor3 = Color3.fromRGB(34, 38, 60)
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	row.Parent = panelFrame
	corner(row, 8)
	local name = Instance.new("TextLabel")
	name.Name = "NameText"
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row
	local effect = Instance.new("TextLabel")
	effect.Name = "EffectText"
	effect.BackgroundTransparency = 1
	effect.Font = Enum.Font.Gotham
	effect.TextColor3 = Color3.fromRGB(200, 214, 240)
	effect.TextScaled = true
	effect.TextXAlignment = Enum.TextXAlignment.Left
	effect.Parent = row
	local buy = button("BuyButton", row, "BUY", Color3.fromRGB(60, 150, 90))
	buy.Activated:Connect(function()
		-- always sent: an unaffordable tap is refused by the server WITH a toast saying why (no silent no-op)
		BuyR:FireServer(def.kind)
	end)
	rowUi[def.kind] = { row = row, name = name, effect = effect, buy = buy, def = def }
end

--============================================================================ layout
local open = false
local function apply(inst: GuiObject, r: any)
	inst.Position = UDim2.fromOffset(r.x, r.y)
	inst.Size = UDim2.fromOffset(r.w, r.h)
end
local L: any = nil
local function applyLayout()
	local v = camera.ViewportSize
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, topLeft = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and topLeft ~= nil then topLeft.Y else 0
	end
	L = HudLayout.compute(Responsive, v.X, v.Y, UserInputService.TouchEnabled, inset, open)
	uiScale.Scale = L.scale
	root.Size = UDim2.fromScale(1 / L.scale, 1 / L.scale)
	apply(wallet, L.wallet)
	apply(hopperPanel, L.hopper)
	apply(toastPanel, L.toast)
	apply(hintPanel, L.hint)
	apply(upgradeSlot, L.upgradeBtn)
	apply(panelFrame, L.panel)
	apply(starCard, L.starCard)
	local rows = HudLayout.panelRows(L)
	for i, def in ROWS do
		local ui = rowUi[def.kind]
		local r = rows[i]
		ui.row.Size = UDim2.new(1, -2 * HudLayout.PANEL_PAD, 0, r.h)
		ui.row.Position = UDim2.fromOffset(HudLayout.PANEL_PAD, r.y)
		local textW = L.panel.w - 3 * HudLayout.PANEL_PAD - r.buy.w - 8
		ui.name.Position = UDim2.fromOffset(8, 2)
		ui.name.Size = UDim2.fromOffset(textW, r.h * 0.45)
		ui.effect.Position = UDim2.fromOffset(8, r.h * 0.5)
		ui.effect.Size = UDim2.fromOffset(textW, r.h * 0.42)
		ui.buy.Position = UDim2.fromOffset(r.buy.x - HudLayout.PANEL_PAD, r.buy.y - r.y) -- row-relative
		ui.buy.Size = UDim2.fromOffset(r.buy.w, r.buy.h)
	end
	local last = rows[#rows]
	panelFrame.CanvasSize = UDim2.fromOffset(0, math.ceil(last.y + last.h + HudLayout.PANEL_PAD))
end
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

local function setOpen(v: boolean)
	open = v
	panelFrame.Visible = v
	applyLayout()
end
upgradeBtn.Activated:Connect(function()
	setOpen(not open)
end)

--============================================================================ toasts and cards
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
	if type(ev) == "table" and type(ev.text) == "string" then showToast("🌠 " .. ev.text) end
end)

local cardToken = 0
local function showStarCard(text: string)
	cardToken += 1
	local mine = cardToken
	starCard.Text = text
	starCard.TextTransparency = 0
	starCard.Visible = true
	task.delay(4, function()
		if cardToken ~= mine then return end
		local tw = TweenService:Create(starCard, TweenInfo.new(0.8), { TextTransparency = 1 })
		tw.Completed:Connect(function()
			if cardToken == mine then starCard.Visible = false end
		end)
		tw:Play()
	end)
end
FxR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	if ev.kind == "starCaught" then
		-- the brag moment: white flash, FOV punch, camera shake, and the card
		FxClient.flash(Color3.fromRGB(255, 255, 255), 0.5, 1.0)
		FxClient.fovPunch(10, 0.12, 0.7)
		FxClient.shake(0.5, 0.9)
		showStarCard("🌠 YOU CAUGHT A FALLING STAR! +" .. short(ev.ore or 0) .. " ⭐")
	elseif ev.kind == "starFalling" then
		showToast("🌠 A Falling Star is coming down by your arrival pad. Catch it!")
	end
end)

--============================================================================ the owner's state
local latest: any = nil
local function bestAffordable(st: any): boolean
	return st.bestPrice ~= nil and st.stardust >= st.bestPrice
end

local function rowTexts(st: any, kind: string): (string, string, number?)
	if kind == "beacon" then
		local L0 = st.beacon
		local s0, s1 = Economy.spawnInterval(Config, L0), Economy.spawnInterval(Config, L0 + 1)
		local nextIdx, remaining = EnvBands.nextBand(bands, L0)
		local tail = ""
		if nextIdx then
			tail = string.format(" · %s in %d", bands[nextIdx].emoji, math.max(1, math.ceil(remaining :: number)))
		end
		return string.format("🗼 Beacon  Lv %d", L0), string.format("A meteor every %.1f s → %.1f s, ore ×1.14%s", s0, s1, tail), st.prices.beacon
	elseif kind == "collector" then
		local c = st.collector
		if c >= Config.Collector.Max then
			return string.format("📡 Collector  Lv %d (max)", c), string.format("Catches %d%% of landings", math.round(Economy.dishShare(Config, c) * 100)), nil
		end
		return string.format("📡 Collector  Lv %d", c),
			string.format("Catches %d%% → %d%% of landings", math.round(Economy.dishShare(Config, c) * 100), math.round(Economy.dishShare(Config, c + 1) * 100)),
			st.prices.collector
	end
	local s = st.smelter
	return string.format("🔥 Smelter  Lv %d", s),
		string.format("Melts %s → %s ore/s", string.format("%.1f", Economy.smeltRate(Config, s)), string.format("%.1f", Economy.smeltRate(Config, s + 1))),
		st.prices.smelter
end

local function render(st: any)
	dustText.Text = "⭐ " .. short(st.stardust)
	rateText.Text = if (st.rate or 0) > 0 then "+" .. short(st.rate) .. "/min" else ""
	-- hopper
	local frac = math.clamp(st.hopper / math.max(st.hopperCap, 1e-9), 0, 1)
	hopperFill.Size = UDim2.fromScale(frac, 1)
	hopperFill.BackgroundColor3 = if st.hopperFull then Color3.fromRGB(255, 230, 120) else Color3.fromRGB(255, 190, 90)
	hopperText.Text = if st.hopperFull then "🔥 Hopper full!" else string.format("🔥 Hopper %s / %s", short(st.hopper), short(st.hopperCap))
	if st.collector > 0 then
		awakeText.Text = if (st.awake or 0) > 0 then "📡 Collector awake " .. Meteors.clock(st.awake) else "💤 Collector asleep: grab a meteor to wake it"
	else
		awakeText.Text = ""
	end
	-- the Upgrades button pulses a star when the best upgrade is affordable
	upgradeBtn.Text = if open then "✕ Close" elseif bestAffordable(st) then "⬆ Upgrades ★" else "⬆ Upgrades"
	-- the rows
	for _, def in ROWS do
		local ui = rowUi[def.kind]
		local title, effect, price = rowTexts(st, def.kind)
		local starred = st.best == def.kind
		ui.name.Text = (if starred then "★ " else "") .. title
		ui.effect.Text = effect
		if price == nil then
			ui.buy.Text = "MAX"
			ui.buy.BackgroundColor3 = Color3.fromRGB(80, 80, 96)
		else
			ui.buy.Text = short(price) .. " ⭐"
			ui.buy.BackgroundColor3 = if st.stardust >= price then (if starred then Color3.fromRGB(200, 150, 40) else Color3.fromRGB(60, 150, 90))
				else Color3.fromRGB(80, 80, 96)
		end
		ui.row.BackgroundColor3 = if starred then Color3.fromRGB(60, 52, 30) else Color3.fromRGB(34, 38, 60)
	end
	-- the hint: saving first, then the first-minutes tutorial (the persisted step, so a rejoin resumes)
	local hint = ""
	local T = Config.Tutorial
	if st.loaded and not st.saving then
		hint = if st.lockChanged then T.LockChanged elseif st.lockedElsewhere then T.NotSavingLocked else T.NotSaving
	elseif st.tutorial == 0 then
		hint = T.Walk
	elseif st.tutorial == 1 then
		hint = if bestAffordable(st) then T.Buy else T.Keep
	elseif st.tutorial == 2 and st.best == "collector" then
		hint = T.Collector
	end
	hintText.Text = hint
	hintPanel.Visible = hint ~= ""
end

local ensureBoardGui: () -> () -- defined with the Star Chart below

StateR.OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then return end
	latest = st
	render(st)
	ensureBoardGui()
end)

--============================================================================ the Star Chart, on the owner's own board
-- A SurfaceGui in THIS player's PlayerGui with Adornee = their own board, so their friends list and rows
-- reach only them. It sits in a Folder so it is never mistaken for screen furniture.
local boardFolder = Instance.new("Folder")
boardFolder.Name = "BoardGuis"
boardFolder.Parent = playerGui
local surface: SurfaceGui? = nil
local rowsFrame: Frame? = nil
local statusText: TextLabel? = nil
local modeText: TextLabel? = nil
local footerText: TextLabel? = nil
local plotMarker: BillboardGui? = nil
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
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. tostring(latest.plot))
	local board = plot and plot:FindFirstChild("Board")
	local face = board and board:FindFirstChild("BoardFace")
	if face == nil then return end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "StarChart"
	sg.Adornee = face
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0
	sg.ResetOnSpawn = false
	sg.ZOffset = 1
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.BackgroundColor3 = Color3.fromRGB(16, 14, 30)
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
	-- the ⭐ over your own plot ("Your plot has the ⭐ over it"): client-only, only you see it
	local smelter = plot:FindFirstChild("Smelter")
	local anchor = smelter and smelter:FindFirstChild("ChimneyCap")
	if anchor then
		local bb = Instance.new("BillboardGui")
		bb.Name = "YourPlot"
		bb.Adornee = anchor
		bb.Size = UDim2.fromOffset(120, 40)
		bb.StudsOffset = Vector3.new(0, 7, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 400
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = GOLD
		t.TextStrokeTransparency = 0.3
		t.Text = "⭐ Your plot"
		t.Parent = bb
		bb.Parent = boardFolder
		plotMarker = bb
	end
	if pendingBoard then renderBoard(pendingBoard) end
end

renderBoard = function(payload: any)
	pendingBoard = payload
	if surface == nil or rowsFrame == nil then return end
	local rf = rowsFrame :: Frame
	for _, c in rf:GetChildren() do c:Destroy() end
	;(modeText :: TextLabel).Text = if payload.mode == "friends" then "⭐ STAR CHART · FRIENDS" else "⭐ STAR CHART · EVERYONE"
	local rows = payload.rows or {}
	local n = math.min(#rows, 10)
	for i = 1, n do
		local r = rows[i]
		local t = Instance.new("TextLabel")
		t.Name = "Row_" .. i
		t.BackgroundTransparency = if r.you then 0.6 else 1
		t.BackgroundColor3 = Color3.fromRGB(90, 70, 20)
		t.Position = UDim2.fromScale(0.04, (i - 1) / 10)
		t.Size = UDim2.fromScale(0.92, 1 / 10)
		t.Font = if r.you then Enum.Font.GothamBlack else Enum.Font.GothamBold
		t.TextColor3 = if r.you then GOLD else Color3.fromRGB(235, 240, 255)
		t.TextScaled = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		local rank = if (r.rank or 0) > 0 then tostring(r.rank) .. "." else "—"
		t.Text = string.format("%s %s  %s %d", rank, tostring(r.name), tostring(r.emoji), r.beacon or 0)
		t.Parent = rf
	end
	;(statusText :: TextLabel).Text = payload.status or ""
	;(footerText :: TextLabel).Text = (payload.footer or "") .. "  ·  Use the board's prompt: Everyone / Friends"
end
BoardR.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then renderBoard(payload) end
end)
