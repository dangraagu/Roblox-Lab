-- Hud.client.luau — SIGNAL LOST HUD. DISPLAY ONLY: the server decides everything; this file draws what State and
-- Notice say and turns input into "I would like X" requests (a purchase; rest goes to Env.client over EnvBus).
--
-- Built for a PHONE first (docs/mobile-ui-brief.md, checklist §2b, DESIGN.md §15):
--   1. One root Frame owns the UIScale, sized 1/scale so it still spans the screen after scaling. The ScreenGui
--      ignores the topbar inset and every top-edge element is pushed below it by hand, in design px.
--   2. Top-left: where you are (SECTOR / RELAYS / SALVAGE). Top-right: the AIR gauge. Right edge, 25-55 % of the
--      height and always above the jump button's band: the SIGNAL meter (display only). Top edge: REST, and SHOP
--      only at a fabricator. Top-centre: the toast, the hint and the banner.
--   3. Nothing tappable in the bottom-left or bottom-right: the thumbstick and the jump button own them. Tap targets
--      are >= 44 screen px after scaling (ceil(46 / scale) design px on touch).
--   4. The shop is a centre modal whose list is a ScrollingFrame (its canvas converted from SCREEN px back to design
--      px); while it is up the side panels hide and the text rows move below it.
--   5. Layout re-runs on ViewportSize AND TouchEnabled.
-- Glyphs: only those photographed rendering in Studio (robloxemu/check_forktower.luau): the em dash, the ellipsis
-- and the star, plus plain Latin text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local EnvBus = require(ReplicatedStorage:WaitForChild("EnvBus"))

local remotes = ReplicatedStorage:WaitForChild("SignalRemotes")
local StateEvent = remotes:WaitForChild("State")
local NoticeEvent = remotes:WaitForChild("Notice")
local AnnounceEvent = remotes:WaitForChild("Announce")
local BuyEvent = remotes:WaitForChild("BuyUpgrade")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local function rgb(t)
	return Color3.fromRGB(t.r, t.g, t.b)
end
local ACCENT = rgb(Config.Hud.Accent)
local DANGER = rgb(Config.Hud.Danger)
local GOOD = rgb(Config.Hud.Good)
local WARN = rgb(Config.Hud.Warn)
local PANEL = rgb(Config.Hud.Panel)
local TEXT = rgb(Config.Hud.Text)
local MUTED = rgb(Config.Hud.Muted)

local M = 12 -- design-px margin
-- Roblox's own touch controls own the bottom-left (thumbstick) and bottom-right (jump): hudcheck's fractions
local THUMB_FRACTION, JUMP_FRACTION = 0.35, 0.25

--============================================================================ scaffolding

local gui = Instance.new("ScreenGui")
gui.Name = "SignalHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = root

-- Full-screen effects in their own ScreenGui, outside the scaled root: they are not panels.
local overlay = Instance.new("ScreenGui")
overlay.Name = "SignalOverlay"
overlay.ResetOnSpawn = false
overlay.IgnoreGuiInset = true
overlay.DisplayOrder = 5
overlay.Parent = playerGui

local function panel(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	f.Parent = parent
	FxClient.theme(f, { corner = 10, stroke = ACCENT, strokeThickness = 1.2, strokeTransparency = 0.6 })
	return f
end

local function text(parent: Instance, name: string, size: number, color: Color3, align): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = ""
	t.Parent = parent
	return t
end

local function button(parent: Instance, name: string, label: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = Color3.fromRGB(24, 30, 42)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 17
	b.TextColor3 = color
	b.Text = label
	b.Parent = parent
	FxClient.theme(b, { corner = 10, stroke = color, strokeThickness = 1.5, strokeTransparency = 0.3 })
	return b
end

--============================================================================ pieces

-- top-left: where you are
local STATUS_W, STATUS_H = 300, 64
local status = panel("Status", root)
local statusTop = text(status, "Title", 18, ACCENT)
statusTop.Position = UDim2.fromOffset(12, 6)
statusTop.Size = UDim2.new(1, -24, 0, 24)
local statusSub = text(status, "Sub", 15, TEXT)
statusSub.Position = UDim2.fromOffset(12, 34)
statusSub.Size = UDim2.new(1, -24, 0, 22)

-- top-right: AIR
local AIR_W, AIR_H = 220, 58
local airPanel = panel("Air", root)
airPanel.AnchorPoint = Vector2.new(1, 0)
local airText = text(airPanel, "Value", 18, TEXT)
airText.Position = UDim2.fromOffset(12, 6)
airText.Size = UDim2.new(1, -24, 0, 22)
local airBg = Instance.new("Frame")
airBg.Name = "BarBg"
airBg.BackgroundColor3 = Color3.fromRGB(34, 40, 52)
airBg.BorderSizePixel = 0
airBg.Position = UDim2.fromOffset(12, 34)
airBg.Size = UDim2.new(1, -24, 0, 12)
airBg.Parent = airPanel
FxClient.theme(airBg, { corner = 4 })
local airBar = Instance.new("Frame")
airBar.Name = "Bar"
airBar.BackgroundColor3 = ACCENT
airBar.BorderSizePixel = 0
airBar.Size = UDim2.fromScale(1, 1)
airBar.Parent = airBg
FxClient.theme(airBar, { corner = 4 })

-- right edge: the SIGNAL meter, five bars (display only)
local SIG_W, SIG_H = 70, 104
local signal = panel("Signal", root)
local sigTitle = text(signal, "Title", 12, MUTED, Enum.TextXAlignment.Center)
sigTitle.Text = "SIGNAL"
sigTitle.Position = UDim2.fromOffset(4, 4)
sigTitle.Size = UDim2.new(1, -8, 0, 16)
local sigBars = {}
for i = 1, Config.Signal.MaxBars do
	local b = Instance.new("Frame")
	b.Name = "Bar" .. i
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.fromRGB(50, 58, 72)
	b.AnchorPoint = Vector2.new(0, 1)
	b.Size = UDim2.fromOffset(8, 12 + i * 12)
	b.Position = UDim2.fromOffset(8 + (i - 1) * 11, SIG_H - 8)
	b.Parent = signal
	sigBars[i] = b
end

local toast = text(root, "Toast", 18, ACCENT, Enum.TextXAlignment.Center)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.TextStrokeTransparency = 0.3
toast.TextWrapped = true
toast.TextTruncate = Enum.TextTruncate.None
toast.Visible = false

local hint = text(root, "Hint", 16, TEXT, Enum.TextXAlignment.Center)
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.TextStrokeTransparency = 0.4
hint.TextWrapped = true
hint.TextTruncate = Enum.TextTruncate.None

local banner = text(root, "Banner", 28, DANGER, Enum.TextXAlignment.Center)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Font = Enum.Font.GothamBlack
banner.TextStrokeTransparency = 0.2
banner.TextWrapped = true
banner.TextTruncate = Enum.TextTruncate.None
banner.Visible = false

local boarding = panel("Boarding", root)
boarding.AnchorPoint = Vector2.new(0.5, 0)
boarding.Visible = false
local boardingText = text(boarding, "Text", 16, ACCENT, Enum.TextXAlignment.Center)
boardingText.Position = UDim2.fromOffset(8, 4)
boardingText.Size = UDim2.new(1, -16, 0, 20)
boardingText.Text = "Boarding…"
local boardBg = Instance.new("Frame")
boardBg.Name = "BarBg"
boardBg.BackgroundColor3 = Color3.fromRGB(34, 40, 52)
boardBg.BorderSizePixel = 0
boardBg.Position = UDim2.fromOffset(12, 28)
boardBg.Size = UDim2.new(1, -24, 0, 8)
boardBg.Parent = boarding
local boardBar = Instance.new("Frame")
boardBar.Name = "Bar"
boardBar.BackgroundColor3 = ACCENT
boardBar.BorderSizePixel = 0
boardBar.Size = UDim2.fromScale(0, 1)
boardBar.Parent = boardBg

local restButton = button(root, "RestButton", "REST", TEXT)
local shopButton = button(root, "ShopButton", "SHOP", GOOD)

-- the shop (fabricator panel)
local shop = panel("Shop", root)
shop.Visible = false
local shopTitle = text(shop, "Title", 19, GOOD)
shopTitle.Text = "FABRICATOR"
local shopClose = button(shop, "CloseButton", "CLOSE", TEXT)
local shopList = Instance.new("ScrollingFrame")
shopList.Name = "List"
shopList.BackgroundTransparency = 1
shopList.BorderSizePixel = 0
shopList.ScrollBarThickness = 6
shopList.CanvasSize = UDim2.new()
shopList.Parent = shop
local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 8)
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = shopList
local shopNote = text(shop, "Note", 13, MUTED)
shopNote.TextWrapped = true
shopNote.TextTruncate = Enum.TextTruncate.None
shopNote.Text = "Salvage only. Nothing here costs Robux. A new rank applies from your next sector."

local shopRows: { [string]: any } = {}
for i, id in Config.Upgrades.Order do
	local u = Config.Upgrades.Catalog[id]
	local row = Instance.new("Frame")
	row.Name = "Row_" .. id
	row.BackgroundTransparency = 1
	row.LayoutOrder = i
	row.Parent = shopList
	local name = text(row, "Name", 16, TEXT)
	name.Position = UDim2.fromOffset(4, 2)
	name.Text = u.name
	local blurb = text(row, "Blurb", 13, MUTED)
	blurb.Text = u.blurb
	local buy = button(row, "BuyButton", "BUY", ACCENT)
	buy.AnchorPoint = Vector2.new(1, 0)
	buy.Activated:Connect(function()
		BuyEvent:FireServer(id)
	end)
	shopRows[id] = { row = row, name = name, blurb = blurb, buy = buy }
end

-- the blackout card, the brag card and the hypoxia vignette: full-screen, in the overlay
local blackCard = Instance.new("Frame")
blackCard.Name = "BlackoutCard"
blackCard.Size = UDim2.fromScale(1, 1)
blackCard.BackgroundColor3 = Color3.new(0, 0, 0)
blackCard.BackgroundTransparency = 0.05
blackCard.BorderSizePixel = 0
blackCard.Visible = false
blackCard.Parent = overlay
local blackText = text(blackCard, "Text", 28, DANGER, Enum.TextXAlignment.Center)
blackText.Size = UDim2.new(0.9, 0, 0.3, 0)
blackText.Position = UDim2.fromScale(0.05, 0.35)
blackText.TextWrapped = true
blackText.TextTruncate = Enum.TextTruncate.None
blackText.Font = Enum.Font.GothamBlack

local bragCard = Instance.new("Frame")
bragCard.Name = "BragCard"
bragCard.Size = UDim2.fromScale(1, 1)
bragCard.BackgroundTransparency = 1
bragCard.BorderSizePixel = 0
bragCard.Visible = false
bragCard.Parent = overlay
local bragTitle = text(bragCard, "Title", 40, GOOD, Enum.TextXAlignment.Center)
bragTitle.Size = UDim2.new(0.9, 0, 0.14, 0)
bragTitle.Position = UDim2.fromScale(0.05, 0.3)
bragTitle.Font = Enum.Font.GothamBlack
bragTitle.TextScaled = true
bragTitle.TextStrokeTransparency = 0.2
local bragSub = text(bragCard, "Sub", 20, TEXT, Enum.TextXAlignment.Center)
bragSub.Size = UDim2.new(0.9, 0, 0.08, 0)
bragSub.Position = UDim2.fromScale(0.05, 0.45)
bragSub.TextWrapped = true
bragSub.TextTruncate = Enum.TextTruncate.None
bragSub.TextStrokeTransparency = 0.3

local vignette = {}
for _, side in { "Top", "Bottom", "Left", "Right" } do
	local f = Instance.new("Frame")
	f.Name = "Vignette" .. side
	f.BackgroundColor3 = Color3.fromRGB(20, 0, 0)
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = overlay
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Rotation = if side == "Top" then 90 elseif side == "Bottom" then -90 elseif side == "Left" then 0 else 180
	g.Parent = f
	vignette[side] = f
end

--============================================================================ state

local S: any = nil -- the last State
local shopOpen = false
local resting = false
local hintOverride, hintUntil = nil, 0
local idleWarned = false
local layout = Responsive.layout(1280, 720, false)
local lastSectorK = nil

local function now()
	-- tick(), not os.clock(): os.clock is CPU time and barely moves under the headless virtual clock
	return tick()
end

local function bandOf(k: number?): any
	local bands = Config.Env.Bands
	if type(k) ~= "number" then return nil end
	local idx = 1
	for i, b in bands do
		if k >= b.first then idx = i end
	end
	return bands[idx]
end

--============================================================================ layout

local function applyLayout()
	local v = camera.ViewportSize
	local touch = UserInputService.TouchEnabled
	local inset = 36
	local okInset, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if okInset and topLeft then inset = topLeft.Y end
	layout = Responsive.layout(v.X, v.Y - inset, touch, v.Y)
	local sc = layout.scale
	uiScale.Scale = sc
	root.Size = UDim2.fromScale(1 / sc, 1 / sc)

	local designW = v.X / sc
	local designH = v.Y / sc
	local topY = inset / sc + 8
	local bandTop = (v.Y - layout.controlPad - M) / sc -- the lowest y anything tappable may reach
	local minTap = if touch then math.ceil(46 / sc) else 0
	local btnH = math.max(44, minTap)

	local inSector = S ~= nil and S.phase ~= "hub" and S.k ~= nil
	-- top panels; stacked when the screen is too narrow for both side by side
	local statusW = math.min(STATUS_W, designW - 2 * M)
	local airW = math.min(AIR_W, designW - 2 * M)
	status.Size = UDim2.fromOffset(statusW, STATUS_H)
	status.Position = UDim2.fromOffset(M, topY)
	airPanel.Size = UDim2.fromOffset(airW, AIR_H)
	airPanel.Visible = inSector and not shopOpen
	local stacked = statusW + airW + 3 * M > designW
	local airY = if stacked then topY + STATUS_H + 8 else topY
	airPanel.Position = UDim2.new(0, designW - M, 0, airY)
	local topBottom = if stacked and airPanel.Visible then airY + AIR_H else topY + STATUS_H

	-- the button row: REST always, SHOP at a fabricator. Right of centre, under the top panels when they are
	-- side by side on a narrow screen, else between them.
	local bw = math.max(96, minTap)
	local nearFab = S ~= nil and S.nearFab == true
	shopButton.Visible = nearFab and not shopOpen
	restButton.Visible = not shopOpen and S ~= nil and (S.phase == "hub" or S.phase == "sector")
	local rowW = bw * (if shopButton.Visible then 2 else 1) + (if shopButton.Visible then 8 else 0)
	local gapStart, gapEnd = M + statusW + M, designW - M - airW - M
	local rowY, rowX
	if not stacked and gapEnd - gapStart >= rowW then
		rowY = topY + (math.min(STATUS_H, AIR_H) - btnH) / 2
		rowX = math.max(gapStart, math.min(designW / 2 + 12, gapEnd - rowW))
		if rowY + btnH > topY + math.max(STATUS_H, AIR_H) then rowY = topY end
	else
		rowY = topBottom + 8
		rowX = designW - M - rowW
	end
	restButton.Size = UDim2.fromOffset(bw, btnH)
	shopButton.Size = UDim2.fromOffset(bw, btnH)
	restButton.Position = UDim2.fromOffset(rowX, rowY)
	shopButton.Position = UDim2.fromOffset(rowX + bw + 8, rowY)
	restButton.Text = if resting then "RESTING" else "REST"
	local rowBottom = math.max(topBottom, if (restButton.Visible or shopButton.Visible) and rowY >= topBottom then rowY + btnH else topBottom)

	-- the SIGNAL meter: right edge, 25-55 % of the height, and always above the jump button's band
	local sigTop = math.max(rowBottom + 8, 0.25 * designH)
	local sigBottomLimit = math.min(0.55 * designH, (v.Y - layout.controlPad) / sc - 8)
	local sigH = math.max(40, math.min(SIG_H, sigBottomLimit - sigTop))
	signal.Size = UDim2.fromOffset(SIG_W, sigH)
	signal.Position = UDim2.fromOffset(designW - M - SIG_W, sigTop)
	signal.Visible = inSector and S.phase == "sector" and not shopOpen
	for i, b in sigBars do
		b.Size = UDim2.fromOffset(8, math.max(4, (sigH - 30) * i / #sigBars))
		b.Position = UDim2.fromOffset(8 + (i - 1) * 11, sigH - 8)
	end

	-- the text rows, top-centre, clear of the side panels
	local midW = math.min(520, designW - 2 * M - (if signal.Visible then SIG_W + M else 0) * 2)
	toast.Size = UDim2.fromOffset(midW, 46)
	toast.Position = UDim2.new(0, designW / 2, 0, rowBottom + 8)
	hint.Size = UDim2.fromOffset(midW, 44)
	hint.Position = UDim2.new(0, designW / 2, 0, rowBottom + 58)
	banner.Size = UDim2.fromOffset(midW, 72)
	banner.Position = UDim2.new(0, designW / 2, 0, rowBottom + 106)
	boarding.Size = UDim2.fromOffset(math.min(280, midW), 44)
	boarding.Position = UDim2.new(0, designW / 2, 0, rowBottom + 106)

	-- the shop: between the top panels and the touch band; the text rows move below it
	local modalTop = topY + STATUS_H + 8
	local screenBottom = designH - M
	local ROWS_BELOW = 8 + 72 + 4 + 46
	local room = math.max(60, math.min(bandTop, screenBottom - ROWS_BELOW) - modalTop - 8)
	local pw = math.min(460, designW - 2 * M)
	local ph = math.max(60, math.min(330, room))
	shop.Size = UDim2.fromOffset(pw, ph)
	shop.Position = UDim2.fromOffset(designW / 2 - pw / 2, modalTop)
	shopTitle.Position = UDim2.fromOffset(12, 10)
	shopTitle.Size = UDim2.new(1, -40 - math.max(96, minTap), 0, btnH)
	shopClose.Size = UDim2.fromOffset(math.max(96, minTap), btnH)
	shopClose.Position = UDim2.new(1, -12 - math.max(96, minTap), 0, 8)
	local noteH = 34
	shopList.Position = UDim2.fromOffset(12, 16 + btnH)
	shopList.Size = UDim2.new(1, -24, 1, -(28 + btnH + noteH))
	shopNote.Position = UDim2.new(0, 12, 1, -noteH - 6)
	shopNote.Size = UDim2.new(1, -24, 0, noteH)
	local rowH = math.max(58, btnH)
	for _, r in shopRows do
		r.row.Size = UDim2.new(1, -10, 0, rowH)
		r.name.Size = UDim2.new(1, -(math.max(110, minTap) + 16), 0, 22)
		r.blurb.Position = UDim2.fromOffset(4, 26)
		r.blurb.Size = UDim2.new(1, -(math.max(110, minTap) + 16), 0, 18)
		r.buy.Size = UDim2.fromOffset(math.max(110, minTap), math.min(rowH, btnH))
		r.buy.Position = UDim2.new(1, 0, 0, 0)
	end
	shop.Visible = shopOpen
	shopClose.Modal = shop.Visible -- a PC cursor is free while the panel is open
	status.Visible = not shopOpen or designW >= 2 * pw
	if shopOpen then
		local y = modalTop + ph + 8
		local w, cx = midW, designW / 2
		if touch and y + 72 + 4 + 46 > (v.Y - layout.controlPad) / sc then
			local left, right = THUMB_FRACTION * designW, (1 - JUMP_FRACTION) * designW
			w = math.min(midW, right - left - 2 * M)
			cx = (left + right) / 2
		end
		banner.Size = UDim2.fromOffset(w, 72)
		banner.Position = UDim2.new(0, cx, 0, y)
		toast.Size = UDim2.fromOffset(w, 46)
		toast.Position = UDim2.new(0, cx, 0, y + 76)
		hint.Visible = false
	else
		hint.Visible = true
	end
	shopList.CanvasSize = UDim2.fromOffset(0, math.ceil(shopLayout.AbsoluteContentSize.Y / math.max(sc, 0.01)) + 12)

	-- hypoxia: the edge closes in over the grace (screen px, outside the scale)
	local thick = 0
	if S and S.phase == "sector" and S.hypoxic then
		local left = math.clamp((S.grace or 0) / Config.Air.GraceSeconds, 0, 1)
		thick = math.floor(math.min(v.X, v.Y) * (0.12 + 0.33 * (1 - left)))
	end
	for side, f in vignette do
		f.Visible = thick > 0
		if side == "Top" then
			f.Size = UDim2.fromOffset(v.X, thick); f.Position = UDim2.fromOffset(0, 0)
		elseif side == "Bottom" then
			f.Size = UDim2.fromOffset(v.X, thick); f.Position = UDim2.fromOffset(0, v.Y - thick)
		elseif side == "Left" then
			f.Size = UDim2.fromOffset(thick, v.Y); f.Position = UDim2.fromOffset(0, 0)
		else
			f.Size = UDim2.fromOffset(thick, v.Y); f.Position = UDim2.fromOffset(v.X - thick, 0)
		end
	end
end

shopLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	shopList.CanvasSize = UDim2.fromOffset(0, math.ceil(shopLayout.AbsoluteContentSize.Y / math.max(uiScale.Scale, 0.01)) + 12)
end)

--============================================================================ painting

local toastToken = 0
local function showToast(msg: string, seconds: number?)
	toastToken += 1
	local mine = toastToken
	toast.Text = msg
	toast.Visible = true
	task.delay(seconds or 4, function()
		if toastToken == mine then toast.Visible = false end
	end)
end

local bannerToken = 0
local function showBanner(msg: string, color: Color3?, seconds: number?)
	bannerToken += 1
	local mine = bannerToken
	banner.Text = msg
	banner.TextColor3 = color or DANGER
	banner.Visible = true
	task.delay(seconds or 3, function()
		if bannerToken == mine then banner.Visible = false end
	end)
end

local function setHint(msg: string, seconds: number)
	hintOverride = msg
	hintUntil = now() + seconds
end

local function paint()
	if not S then return end
	local b = bandOf(S.k)
	if S.phase == "hub" then
		statusTop.Text = "LIFEBOAT"
	elseif S.k then
		statusTop.Text = string.format("SECTOR %d · %s", S.k, if b then b.name else "")
	end
	local carried = if S.k and S.phase ~= "hub" then string.format("  (CARRIED %d)", S.carried or 0) else ""
	statusSub.Text = string.format("RELAYS %d%s · SALVAGE %d%s", S.best or 0, if S.arrayDone then " " .. Config.Board.Star else "",
		S.salvage or 0, carried)

	if S.air and S.tank then
		local frac = if S.tank > 0 then math.clamp(S.air / S.tank, 0, 1) else 0
		if S.hypoxic then
			airText.Text = string.format("NO AIR — %.1fs", S.grace or 0)
			airText.TextColor3 = DANGER
		else
			airText.Text = string.format("AIR %ds / %ds", math.ceil((S.air or 0) - 1e-6), S.tank)
			airText.TextColor3 = if S.moduleType == "vacuum" then WARN else TEXT
		end
		airBar.Size = UDim2.fromScale(frac, 1)
		airBar.BackgroundColor3 = if frac < 0.25 then DANGER elseif frac < 0.5 then WARN else ACCENT
	end
	local bars = S.bars or 1
	for i, f in sigBars do
		f.BackgroundColor3 = if i <= bars then (if bars >= 5 then GOOD else ACCENT) else Color3.fromRGB(50, 58, 72)
	end

	boarding.Visible = S.phase == "hub" and (S.boarding or 0) > 0
	boardBar.Size = UDim2.fromScale(S.boarding or 0, 1)

	-- the hint line: resting first (REVIEW-1 finding 7: REST tapped in the relay room within 5 s of a splice read
	-- "Drop through the hatch"), then an event's hint for a few seconds, then the standing one
	local h = ""
	if resting then
		h = Config.Rest.Text.Resting
		if idleWarned and (S.carried or 0) > 0 then
			h = string.format(Config.Rest.Text.IdleWarning, S.carried)
		end
	elseif hintOverride and now() < hintUntil then
		h = hintOverride
	elseif S.phase == "hub" then
		if S.storeless then
			h = "Saving is off on this server — progress will not be kept. Walk into the LIFT."
		elseif not S.loaded then
			h = "Loading your file…"
		elseif S.nearFab then
			h = "The fabricator turns salvage into upgrades. Tap SHOP."
		else
			h = "Walk into the LIFT to go down to sector " .. tostring((S.best or 0) + 1) .. "."
		end
	elseif S.phase == "transit" then
		h = if b then b.line else "…"
	elseif S.phase == "sector" then
		if S.hypoxic then
			h = "OUT OF AIR — get to a green hatch light!"
		elseif S.spliced then
			h = if S.nearFab then "Tap SHOP to spend salvage, or drop through the hatch to go deeper."
				else "Drop through the green floor hatch to go deeper, or RETURN at the console."
		elseif (S.splicing or 0) > 0 then
			h = "Splicing the relay…"
		elseif S.moduleType == "vacuum" then
			h = "No air here — your AIR is draining. Green hatch light: air."
		else
			h = "Follow the SIGNAL to the relay. Green light: air. Red light: vacuum."
		end
	elseif S.phase == "blackout" then
		h = ""
	end
	hint.Text = h

	if shopOpen and S.upRows then
		shopTitle.Text = string.format("FABRICATOR — %d SALVAGE", S.salvage or 0)
		for _, r in S.upRows do
			local row = shopRows[r.id]
			if row then
				row.name.Text = string.format("%s  %d/%d%s", r.name, r.rank, r.max, if S.recommended == r.id then "  RECOMMENDED" else "")
				if r.price then
					row.buy.Text = tostring(r.price)
					row.buy.TextColor3 = if (S.salvage or 0) >= r.price then ACCENT else MUTED
				else
					row.buy.Text = "MAX"
					row.buy.TextColor3 = MUTED
				end
			end
		end
	end
end

StateEvent.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	if s.uid ~= nil and s.uid ~= player.UserId then return end
	local wasPhase = S and S.phase
	S = s
	if shopOpen and not s.nearFab then
		shopOpen = false -- walked away from the fabricator: the panel closes
	end
	if wasPhase ~= s.phase then
		applyLayout()
	end
	paint()
	applyLayout()
end)

--============================================================================ notices

NoticeEvent.OnClientEvent:Connect(function(kind, raw)
	local data = if type(raw) == "table" then raw else {}
	if kind == "toast" then
		showToast(tostring(raw))
	elseif kind == "shop" then
		shopOpen = true
	elseif kind == "boarding" then
		setHint("Boarding the LIFT…", 1.5)
	elseif kind == "sector" then
		shopOpen = false
		lastSectorK = data.k
		showBanner(string.format("SECTOR %d — %s", data.k or 0, tostring(data.band or "")), ACCENT, 3)
		FxClient.shake(0.3, 0.6)
	elseif kind == "arrive" then
		if data.k == 1 then
			setHint("Follow the SIGNAL to the relay. Green light: air. Red light: vacuum.", 8)
		end
	elseif kind == "vacuum" then
		if data.first then
			setHint("No air here — your AIR is draining. Jump to drift.", 6)
		end
	elseif kind == "hypoxic" then
		showBanner("OUT OF AIR — GET TO A GREEN HATCH", DANGER, 2)
	elseif kind == "recovered" then
		showToast("Air again.", 2)
	elseif kind == "salvage" then
		FxClient.fovPunch(-3, 0.06, 0.2)
		showToast(string.format("+%d salvage — banked when you splice the relay.", data.value or 0), 3)
	elseif kind == "canister" then
		showToast("O2 canister — AIR +" .. Config.Air.CanisterSeconds .. " s", 2)
	elseif kind == "splicing" then
		showBanner("SPLICING…", ACCENT, data.seconds or 2)
	elseif kind == "spliced" then
		showBanner(string.format("RELAY %d ONLINE", data.k or 0), GOOD, 3)
		showToast(string.format("+%d salvage banked (%d carried + %d bonus)", data.paid or 0, data.carried or 0, data.bonus or 0), 4)
		FxClient.flash(GOOD, 0.3, 0.6)
		setHint("Drop through the hatch to go deeper.", 5)
	elseif kind == "brag" then
		bragTitle.Text = "SIGNAL SENT"
		bragSub.Text = string.format("Relay %d. The Main Array is transmitting.", data.k or Config.Brag.Sector)
		bragCard.Visible = true
		FxClient.flash(Color3.new(1, 1, 1), 0.6, 1.2)
		FxClient.fovPunch(-8, 0.1, 0.6)
		task.delay(3, function()
			bragSub.Text = "…something answered."
			FxClient.shake(0.4, 1)
		end)
		task.delay(6, function()
			bragCard.Visible = false
		end)
	elseif kind == "blackout" then
		blackText.Text = string.format("SIGNAL LOST — you blacked out. Kept %d of %d carried salvage.", data.kept or 0, data.of or 0)
		blackCard.Visible = true
		FxClient.shake(0.7, 1.5)
		task.delay(Config.Run.BlackoutBeatSeconds + 0.3, function()
			blackCard.Visible = false
		end)
	elseif kind == "sectorEnd" then
		showToast(string.format("Sector left — kept %d of %d carried salvage.", data.paid or 0, data.of or 0), 5)
	elseif kind == "returning" then
		if data.unspliced then
			showToast(string.format("Back to the lifeboat — kept %d of %d carried salvage.", data.paid or 0, data.of or 0), 5)
		else
			showToast("Back to the lifeboat.", 3)
		end
	elseif kind == "home" then
		setHint("Welcome back aboard.", 3)
	elseif kind == "purchased" then
		showToast(string.format("%s rank %d — applies from your next sector.", tostring(data.name), data.rank or 0), 4)
		FxClient.flash(GOOD, 0.2, 0.4)
	end
	paint()
	applyLayout()
end)

AnnounceEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	showToast(string.format("%s %s restored the MAIN ARRAY", Config.Board.Star, tostring(data.name or "Someone")), 6)
end)

--============================================================================ the environment's messages

-- A hazard's banner (DESIGN.md §5.2): NAME — STEP OUT OF THE RING while inside, NAME — YOU ARE CLEAR once out.
local function hazardText(name: any, inside: boolean): string
	return tostring(name) .. (if inside then " — STEP OUT OF THE RING" else " — YOU ARE CLEAR")
end
local hazardBanner = 0
EnvBus.on(function(kind, data)
	if kind == "hazard" and type(data) == "table" then
		if data.phase == "warn" then
			local secs = if type(data.seconds) == "number" and data.seconds > 0 then data.seconds else nil
			showBanner(hazardText(data.name, true), DANGER, secs)
			hazardBanner = bannerToken
		elseif data.phase == "zone" then
			if hazardBanner ~= 0 and hazardBanner == bannerToken and banner.Visible then
				banner.Text = hazardText(data.name, data.inside == true)
				banner.TextColor3 = if data.inside == true then DANGER else GOOD
			end
		elseif data.phase == "clear" then
			if hazardBanner ~= 0 and hazardBanner == bannerToken then banner.Visible = false end
			hazardBanner = 0
		end
	elseif kind == "rest" and type(data) == "table" then
		resting = data.resting == true
		if not resting then idleWarned = false end
		paint()
		applyLayout()
	elseif kind == "restRefused" and type(data) == "table" then
		showToast(tostring(data.reason), 3) -- never a silent no-op
	end
end)

--============================================================================ input

local function toggleRest()
	EnvBus.fire("restRequest", { want = not resting })
end
restButton.Activated:Connect(toggleRest)
shopButton.Activated:Connect(function()
	shopOpen = true
	paint()
	applyLayout()
end)
shopClose.Activated:Connect(function()
	shopOpen = false
	applyLayout()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.R or kc == Enum.KeyCode.ButtonX then
		toggleRest()
	end
end)

-- Roblox disconnects a player idle for about 20 minutes; after Player.Idled the rest line says what it would cost.
pcall(function()
	player.Idled:Connect(function()
		idleWarned = true
		paint()
	end)
end)

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
local okTouch, touchErr = pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
if not okTouch then
	warn("[SignalLost] no TouchEnabled listener; layout follows the viewport only: " .. tostring(touchErr))
end

-- the hint's timeout needs a slow repaint even without a State push
task.spawn(function()
	while true do
		task.wait(0.5)
		paint()
	end
end)
local _ = lastSectorK
