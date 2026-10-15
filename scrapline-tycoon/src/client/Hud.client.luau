-- SCRAPLINE TYCOON — the HUD. Client only (StarterPlayerScripts). DISPLAY ONLY: it shows the player's own State,
-- sends Buy / Fix / Recycle / BoardView and nothing else, creates the prompts on the player's OWN plot, and draws the
-- owner's Top Recyclers rows on their own board.
--
-- Phone first (docs/new-game-checklist.md §2b): a root Frame owns the UIScale and is sized 1/scale; every rectangle
-- comes from HudLayout (the same function Yard.client.luau uses for its chip, ☕ Break slot and warning, so the two
-- can never overlap); nothing tappable sits in the bottom-left or bottom-right band (Roblox's thumbstick and jump
-- button); tap targets reach 44 screen px on touch; everything re-lays out on Camera.ViewportSize, on
-- TouchEnabled, and when the line panel opens or closes.
-- Layout:  top centre   wallet · (band chip, Yard) · alert · (hazard warning, Yard) · toast · hint
--          right edge   slot 1 🏭 Line · slot 2 (☕ Break, Yard) · slot 3 ♻ Recycle; the line panel opens at the right
--                       edge and PAGES (slot 3 turns the page); a recycle asks again in slots 1 and 3
-- Every prompt is created HERE, on the player's own plot: station consoles (open the panel there; the glowing
-- Shredder pad builds it), Fix on a sputtering or jammed machine, and the board toggle. Nothing replicates, and a
-- visitor never sees a prompt on someone else's plot.
-- Headless checks: robloxemu/check_scraplinetycoon_hud.luau (hudcheck, overlap = true), check_scraplinetycoon.luau
-- (prompts reachable, the board renders).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local HudLayout = require(ReplicatedStorage:WaitForChild("HudLayout"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait(0.1)
	camera = workspace.CurrentCamera
end

local remotes = ReplicatedStorage:WaitForChild("ScraplineRemotes")
local StateR = remotes:WaitForChild("State") :: RemoteEvent
local ToastR = remotes:WaitForChild("Toast") :: RemoteEvent
local FxR = remotes:WaitForChild("Fx") :: RemoteEvent
local BoardR = remotes:WaitForChild("Board") :: RemoteEvent
local AnnounceR = remotes:WaitForChild("Announce") :: RemoteEvent
local BuyR = remotes:WaitForChild("Buy") :: RemoteEvent
local FixR = remotes:WaitForChild("Fix") :: RemoteEvent
local RecycleR = remotes:WaitForChild("Recycle") :: RemoteEvent
local BoardViewR = remotes:WaitForChild("BoardView") :: RemoteEvent

local ST = Config.Stations
local IDS = ST.Order
local short, money = Economy.short, Economy.money

--============================================================================ building blocks
local gui = Instance.new("ScreenGui")
gui.Name = "ScraplineHud"
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

local PANEL_BG = Color3.fromRGB(28, 26, 32)
local GOLD = Color3.fromRGB(255, 205, 80)
local AMBER = Color3.fromRGB(255, 190, 40)
local BTN_GOLD = Color3.fromRGB(200, 150, 40) -- the starred, affordable purchase (the walk taps this colour)
local BTN_OK = Color3.fromRGB(60, 150, 90) -- affordable AND worth it (Economy.worth, sent per row as `worth`)
local BTN_NO = Color3.fromRGB(80, 80, 96) -- not affordable
local BTN_MEH = Color3.fromRGB(58, 84, 104) -- affordable, not worth it now (REVIEW-2 R3: it used to be green too)

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
local cashText = label(wallet, "CashText", 0, 0.55, Enum.Font.GothamBlack, GOLD, 26, Enum.TextXAlignment.Left)
cashText.Text = "$0"
local incomeText = label(wallet, "IncomeText", 0.55, 0.45, Enum.Font.GothamBold, Color3.fromRGB(230, 236, 255), 16, Enum.TextXAlignment.Right)

local alertPanel = panel("AlertPanel", root)
alertPanel.BackgroundColor3 = Color3.fromRGB(80, 56, 16)
alertPanel.Visible = false
local alertText = label(alertPanel, "AlertText", 0, 1, Enum.Font.GothamBlack, AMBER, 17)

local toastPanel = panel("ToastPanel", root)
toastPanel.Visible = false
local toastText = label(toastPanel, "ToastText", 0, 1, Enum.Font.GothamBold, Color3.fromRGB(255, 244, 214), 16)

local hintPanel = panel("HintPanel", root)
hintPanel.BackgroundColor3 = Color3.fromRGB(34, 48, 62)
hintPanel.Visible = false
local hintText = label(hintPanel, "HintText", 0, 1, Enum.Font.GothamBold, Color3.fromRGB(230, 244, 255), 16)

-- transient cards (never Active: they cannot eat a tap)
local function cardLabel(name: string, colour: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Active = false
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = colour
	t.TextStrokeTransparency = 0.3
	t.TextScaled = true
	t.TextWrapped = true
	t.Visible = false
	t.Parent = root
	return t
end
local bragCard = cardLabel("BragCard", GOLD)
local confirmCard = cardLabel("ConfirmCard", Color3.fromRGB(255, 255, 255))

--============================================================================ the column and the line panel
local lineSlot = Instance.new("Frame")
lineSlot.Name = "LineSlot"
lineSlot.BackgroundTransparency = 1
lineSlot.BorderSizePixel = 0
lineSlot.Parent = root
local lineBtn = button("LineButton", lineSlot, "🏭 Line", Color3.fromRGB(70, 110, 150))
lineBtn.Size = UDim2.fromScale(1, 1)

local recycleSlot = Instance.new("Frame")
recycleSlot.Name = "RecycleSlot"
recycleSlot.BackgroundTransparency = 1
recycleSlot.BorderSizePixel = 0
recycleSlot.Visible = false
recycleSlot.Parent = root
local recycleBtn = button("RecycleButton", recycleSlot, "♻ Recycle", Color3.fromRGB(70, 130, 90))
recycleBtn.Size = UDim2.fromScale(1, 1)

local linePanel = Instance.new("Frame")
linePanel.Name = "LinePanel"
linePanel.BackgroundColor3 = PANEL_BG
linePanel.BackgroundTransparency = 0.08
linePanel.BorderSizePixel = 0
linePanel.Visible = false
linePanel.Parent = root
corner(linePanel, 12)
stroke(linePanel, GOLD)
local header = Instance.new("TextLabel")
header.Name = "HeaderText"
header.BackgroundTransparency = 1
header.Font = Enum.Font.GothamBlack
header.TextColor3 = GOLD
header.TextScaled = true
header.TextXAlignment = Enum.TextXAlignment.Left
header.Parent = linePanel

-- Row slots, placed explicitly from HudLayout.panelRow (no UIListLayout: Roblox would override the positions
-- hudcheck measures). A slot shows station (page - 1) * perPage + slot.
local rowUi = {}
for i = 1, HudLayout.STATIONS do
	local row = Instance.new("Frame")
	row.Name = "Row_" .. i
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	row.Visible = false
	row.Parent = linePanel
	corner(row, 8)
	local name = Instance.new("TextLabel")
	name.Name = "NameText"
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextColor3 = Color3.fromRGB(255, 255, 255)
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row
	local info = Instance.new("TextLabel")
	info.Name = "InfoText"
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.Gotham
	info.TextColor3 = Color3.fromRGB(210, 214, 230)
	info.TextScaled = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.Parent = row
	local bar = Instance.new("Frame")
	bar.Name = "LoadBar"
	bar.BackgroundColor3 = Color3.fromRGB(60, 60, 72)
	bar.BorderSizePixel = 0
	bar.Parent = row
	local fill = Instance.new("Frame")
	fill.Name = "LoadFill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	local b1 = button("Btn1", row, "", BTN_NO)
	local b2 = button("Btn2", row, "", BTN_NO)
	rowUi[i] = { row = row, name = name, info = info, bar = bar, fill = fill, b1 = b1, b2 = b2, t = nil :: number? }
end

--============================================================================ layout and modes
local mode = "normal" -- "normal" | "panel" | "confirm"
local page = 1
local L: any = nil
local PL: any = nil
local latest: any = nil
local render: () -> ()

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
	L = HudLayout.compute(Responsive, v.X, v.Y, UserInputService.TouchEnabled, inset, mode == "panel")
	PL = HudLayout.panelLayout(L)
	page = math.clamp(page, 1, PL.pages)
	uiScale.Scale = L.scale
	root.Size = UDim2.fromScale(1 / L.scale, 1 / L.scale)
	apply(wallet, L.wallet)
	apply(alertPanel, L.alert)
	apply(toastPanel, L.toast)
	apply(hintPanel, L.hint)
	apply(lineSlot, L.slot1)
	apply(recycleSlot, L.slot3)
	apply(linePanel, L.panel)
	apply(bragCard, L.bragCard)
	confirmCard.Position = UDim2.fromOffset(L.card.x, L.card.y)
	confirmCard.Size = UDim2.fromOffset(L.card.w, L.bragCard.y + L.bragCard.h - L.card.y)
	header.Position = UDim2.fromOffset(10, 2)
	header.Size = UDim2.fromOffset(L.panel.w - 20, PL.headerH - 4)
	for i, ui in rowUi do
		if i <= PL.perPage then
			local r = HudLayout.panelRow(L, PL, i)
			ui.row.Position = UDim2.fromOffset(HudLayout.PANEL_PAD, r.y)
			ui.row.Size = UDim2.fromOffset(L.panel.w - 2 * HudLayout.PANEL_PAD, r.h)
			-- row-relative rectangles
			local ox, oy = HudLayout.PANEL_PAD, r.y
			ui.name.Position = UDim2.fromOffset(r.text.x - ox, r.text.y - oy)
			ui.name.Size = UDim2.fromOffset(r.text.w, r.text.h * 0.45)
			ui.info.Position = UDim2.fromOffset(r.text.x - ox, r.text.y - oy + r.text.h * 0.47)
			ui.info.Size = UDim2.fromOffset(r.text.w, r.text.h * 0.33)
			ui.bar.Position = UDim2.fromOffset(r.text.x - ox, r.text.y - oy + r.text.h * 0.84)
			ui.bar.Size = UDim2.fromOffset(r.text.w, math.max(3, r.text.h * 0.1))
			local b1, b2 = r.buttons[1], r.buttons[2]
			ui.b1.Position = UDim2.fromOffset(b1.x - ox, b1.y - oy)
			ui.b1.Size = UDim2.fromOffset(b1.w, b1.h)
			ui.b2.Position = UDim2.fromOffset(b2.x - ox, b2.y - oy)
			ui.b2.Size = UDim2.fromOffset(b2.w, b2.h)
		end
	end
	if render then render() end
end

local function setMode(m: string)
	mode = m
	linePanel.Visible = m == "panel"
	confirmCard.Visible = m == "confirm"
	applyLayout()
end

local function openPanelAt(t: number?)
	if PL == nil then applyLayout() end
	page = if t then HudLayout.pageOf(PL, t) else 1
	setMode("panel")
end

local function buildShredderMode(): boolean
	return latest ~= nil and latest.loaded and type(latest.stations) == "table" and latest.stations[1].n == 0
end

local function starAffordable(): boolean
	return latest ~= nil and latest.star ~= nil and latest.cash >= latest.star.price
end

lineBtn.Activated:Connect(function()
	if mode == "panel" then
		setMode("normal")
	elseif mode == "confirm" then
		RecycleR:FireServer()
		setMode("normal")
	elseif buildShredderMode() then
		BuyR:FireServer("build", "shredder") -- the core action, one tap
	else
		openPanelAt(if latest and latest.star then latest.star.t else nil)
	end
end)

recycleBtn.Activated:Connect(function()
	if mode == "panel" then
		page = page % PL.pages + 1
		render()
	elseif mode == "confirm" then
		setMode("normal")
	elseif latest and latest.recycleReady then
		setMode("confirm") -- a stray tap on a phone must not end a run: ask again, in slot 1
	else
		RecycleR:FireServer() -- not ready: the server says how far off the rocket rate is (never a silent no-op)
	end
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

local cardToken = 0
local function showBragCard(text: string)
	cardToken += 1
	local mine = cardToken
	bragCard.Text = text
	bragCard.TextTransparency = 0
	bragCard.Visible = true
	task.delay(4, function()
		if cardToken ~= mine then return end
		local tw = TweenService:Create(bragCard, TweenInfo.new(0.8), { TextTransparency = 1 })
		tw.Completed:Connect(function()
			if cardToken == mine then bragCard.Visible = false end
		end)
		tw:Play()
	end)
end

AnnounceR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	local own = latest ~= nil and ev.plot == latest.plot
	if ev.kind == "liftoff" then
		showToast("🚀 " .. tostring(ev.name) .. " launched their first rocket!")
		if own then
			FxClient.flash(Color3.fromRGB(255, 240, 200), 0.45, 1.0)
			showBragCard(if (ev.run or 1) > 1 then "🚀 RUN " .. tostring(ev.run) .. ": LIFT-OFF!" else "🚀 LIFT-OFF! Your factory builds rockets!")
		end
	elseif ev.kind == "recycle" and not own then
		showToast("♻ " .. tostring(ev.name) .. " recycled for Gold Bolt #" .. tostring(ev.bolts))
	end
end)

FxR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	if ev.kind == "recycled" then
		showBragCard("♻ RECYCLED! Gold Bolt #" .. tostring(ev.bolts) .. "  ·  everything ships for x" .. tostring(1 + Config.Recycle.BoltValue * (ev.bolts or 0)))
	end
end)

--============================================================================ the owner's state
local function product(t: number): string
	return Config.Products.Names[t + 1]
end

local function renderRow(ui: any, t: number, st: any)
	local row = st.stations[t]
	local star = st.star
	local starred = star ~= nil and star.t == t

	ui.t = t
	local nameText = (if starred then "★ " else "") .. ST.Emoji[t] .. " " .. ST.Names[t]
	if row.n > 0 then
		nameText ..= "  Lv " .. row.L .. (if row.n == 2 then " ×2" else "")
	end
	if st.bottleneck == t then nameText ..= "  🐢" end
	if starred and star.kind == "build" and star.saving then nameText ..= "  NEW" end
	ui.name.Text = nameText
	local jammedA = row.n >= 1 and row.jamA == 2
	local jammedB = row.n >= 2 and row.jamB == 2
	local sputtering = (row.n >= 1 and row.jamA == 1) or (row.n >= 2 and row.jamB == 1)
	local infoText
	if row.n == 0 then
		infoText = if row.locked then "🔒 Build a " .. ST.Names[t - 1] .. " first" else "Turns " .. product(t - 1) .. " into " .. product(t)
	elseif sputtering then
		infoText = "⚠ Sputtering: walk over and hold Fix!"
	elseif jammedA or jammedB then
		infoText = "⚠ JAMMED: items ride past. Hold Fix on it"
	else
		local loadPct = if row.load < 0 then 0 else math.floor(row.load * 100 + 0.5)
		infoText = string.format("%s %s/s · load %d%%%s", product(t), Economy.rate(row.cap), loadPct, if row.load > 1 then ": items ride past" else "")
	end
	ui.info.Text = infoText
	local load = if row.load < 0 then 1.5 else math.clamp(row.load, 0, 1.5)
	ui.fill.Size = UDim2.fromScale(load / 1.5, 1)
	ui.fill.BackgroundColor3 = if row.load > 1 or row.load < 0 then AMBER else Color3.fromRGB(90, 200, 120)
	ui.bar.Visible = row.n > 0
	-- REVIEW-2 R3: gold = the ★; green = affordable and worth it (the server's Economy.worth: the next station, or a
	-- payback within Star.GreenPayback x the best, and nothing while the ★ saves for the next station); muted = you can
	-- afford it but it is not a good buy now; grey = not affordable. A player who taps whatever is green lands the
	-- first Rocket in 30-45 min (Pacing.spec); when every affordable button was green, they took about 53.
	local worth = row.worth or {}
	local function paint(b: TextButton, price: number?, isStar: boolean, good: boolean?)
		if price == nil or st.cash < price then
			b.BackgroundColor3 = BTN_NO
		elseif isStar then
			b.BackgroundColor3 = BTN_GOLD
		else
			b.BackgroundColor3 = if good then BTN_OK else BTN_MEH
		end
	end
	-- button 1: the twin; button 2: the upgrade, or Build
	local p = row.prices
	ui.b1.Visible = p.twin ~= nil
	if p.twin ~= nil then
		ui.b1.Text = "+ Twin " .. money(p.twin)
		paint(ui.b1, p.twin, starred and star.kind == "twin", worth.twin)
	end
	if row.locked then
		ui.b2.Visible = false
	elseif row.n == 0 then
		ui.b2.Visible = true
		ui.b2.Text = if p.build == 0 then "🔨 FREE" else "🔨 " .. money(p.build)
		paint(ui.b2, p.build, starred and star.kind == "build", worth.build)
	else
		ui.b2.Visible = true
		if p.up == nil then
			ui.b2.Text = "MAX"
			ui.b2.BackgroundColor3 = BTN_NO
		else
			ui.b2.Text = "⬆ " .. money(p.up)
			paint(ui.b2, p.up, starred and star.kind == "up", worth.up)
		end
	end
	ui.row.BackgroundColor3 = if starred then Color3.fromRGB(70, 58, 30) else Color3.fromRGB(40, 40, 50)
end

for _, ui in rowUi do
	ui.b1.Activated:Connect(function()
		if ui.t then BuyR:FireServer("twin", IDS[ui.t]) end
	end)
	ui.b2.Activated:Connect(function()
		-- always sent: an unaffordable tap is refused by the server WITH a toast saying why (no silent no-op)
		if ui.t and latest then
			local row = latest.stations[ui.t]
			BuyR:FireServer(if row.n == 0 then "build" else "up", IDS[ui.t])
		end
	end)
end

render = function()
	local st = latest
	if st == nil or type(st.stations) ~= "table" then return end
	cashText.Text = money(st.cash)
	incomeText.Text = "+" .. money(st.income) .. "/s" .. (if (st.bolts or 0) > 0 then "  ·  🔩×" .. tostring(st.mult) else "")
	-- the column
	local rocketBay = st.stations[6].n > 0
	if mode == "panel" then
		lineBtn.Text = "✕ Close"
		recycleSlot.Visible = PL ~= nil and PL.pages > 1
		recycleBtn.Text = string.format("▼ Page %d/%d", page, if PL then PL.pages else 1)
	elseif mode == "confirm" then
		lineBtn.Text = "✓ Recycle!"
		recycleSlot.Visible = true
		recycleBtn.Text = "✕ Not yet"
	else
		lineBtn.Text = if buildShredderMode() then "🔧 Build Shredder" elseif starAffordable() then "🏭 Line ★" else "🏭 Line"
		recycleSlot.Visible = rocketBay
		recycleBtn.Text = if st.recycleReady then "♻ Recycle ★" else string.format("♻ %s/%s", short(st.rocketRate), short(st.recycleNeed))
	end
	if mode == "confirm" then
		confirmCard.Text = string.format("♻ Recycle your factory? You keep your Gold Bolts. You lose your cash and machines. "
			.. "You get Gold Bolt #%d: everything you ship is worth %d%% more, forever.", (st.bolts or 0) + 1, math.floor(Config.Recycle.BoltValue * 100))
	end
	-- the panel
	if mode == "panel" and PL then
		header.Text = string.format("🏭 Your line · %s/s%s", money(st.income), if PL.pages > 1 then string.format("  ·  %d/%d", page, PL.pages) else "")
		for i, ui in rowUi do
			local t = (page - 1) * PL.perPage + i
			if i <= PL.perPage and t <= 6 then
				ui.row.Visible = true
				renderRow(ui, t, st)
			else
				ui.row.Visible = false
				ui.t = nil
			end
		end
	end
	-- the alert line: a machine needs you (amber, never red)
	local alert = ""
	if st.sputter then
		alert = string.format("⚠ %s sputtering: Fix %s", ST.Names[st.sputter.t], Economy.clock(st.sputter.left))
	else
		for t = 1, 6 do
			if (st.jammed[t] or 0) > 0 then
				alert = "⚠ " .. ST.Names[t] .. " JAMMED: walk over and hold Fix"
				break
			end
		end
	end
	alertText.Text = alert
	alertPanel.Visible = alert ~= ""
	-- the hint: saving first, then the first-minutes tutorial (the persisted step, so a rejoin resumes), then the ★
	local T = Config.Tutorial
	local hint = ""
	if st.loaded and not st.saving then
		hint = if st.lockChanged then T.LockChanged elseif st.lockedElsewhere then T.NotSavingLocked else T.NotSaving
	elseif st.tutorial == 0 then
		hint = T.Build
	elseif st.tutorial == 1 then
		hint = T.Upgrade
	elseif st.tutorial == 2 then
		-- REVIEW-2 R4: name the Furnace only while the ★ points at it; before that the ★ is a Shredder upgrade or its
		-- twin, and "Save for a Furnace" told a new player the opposite of the gold row (22-77 s into the walk)
		hint = if st.star and st.star.kind == "build" and st.star.t == 2 then T.Save else T.Follow
	elseif st.tutorial == 3 and st.sputter then
		hint = T.Fix
	elseif st.star and st.star.saving then
		hint = string.format("Saving for the %s ★: %s", ST.Names[st.star.t], Economy.clock(st.star.wait))
	end
	hintText.Text = hint
	hintPanel.Visible = hint ~= ""
end

applyLayout()
-- until the first State arrives, say what is happening (never a blank first screen)
hintText.Text = "Loading your factory…"
hintPanel.Visible = true
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

--============================================================================ prompts on the player's OWN plot
local promptFolder = Instance.new("Folder")
promptFolder.Name = "ScraplineLocal" -- pointers that must render in the world (BillboardGuis with an Adornee)
promptFolder.Parent = playerGui
local consolePrompts: { [number]: ProximityPrompt } = {}
local fixPrompts: { [string]: any } = {} -- "t:m" -> { prompt, pointer }
local boardPrompt: ProximityPrompt? = nil
local boardMode = "public"
local myPlot: Instance? = nil

local function stationFolderName(t: number): string
	return "Station_" .. string.gsub(ST.Names[t], " ", "")
end
local function machineBody(t: number, m: number): BasePart?
	if myPlot == nil then return nil end
	local folder = (myPlot :: Instance):FindFirstChild(stationFolderName(t))
	local mdl = folder and folder:FindFirstChild("Machine_" .. string.gsub(ST.Names[t], " ", "") .. "_" .. (if m == 1 then "a" else "b"))
	return mdl and mdl:FindFirstChild("Body") :: BasePart?
end

local function newPrompt(parent: Instance, object: string, action: string, hold: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ObjectText = object
	p.ActionText = action
	p.HoldDuration = hold
	p.MaxActivationDistance = Config.Jams.PromptDistance
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local ensureBoardGui: () -> ()

local function ensurePrompts()
	if latest == nil or not latest.loaded then return end
	if myPlot == nil then
		local plots = workspace:FindFirstChild("Plots")
		myPlot = plots and plots:FindFirstChild("Plot_" .. tostring(latest.plot))
		if myPlot == nil then return end
	end
	local plot = myPlot :: Instance
	-- the station consoles: open the panel at that station; the glowing Shredder pad builds it (one tap)
	for t, id in IDS do
		if consolePrompts[t] == nil then
			local console = plot:FindFirstChild("Console_" .. id)
			if console then
				local p = newPrompt(console, ST.Emoji[t] .. " " .. ST.Names[t], "Open line", 0)
				p.Name = "ConsolePrompt"
				p.Triggered:Connect(function()
					if t == 1 and buildShredderMode() then
						BuyR:FireServer("build", "shredder")
					else
						openPanelAt(t)
					end
				end)
				consolePrompts[t] = p
			end
		end
		local cp = consolePrompts[t]
		if cp then
			local want = if t == 1 and buildShredderMode() then "Build free Shredder" else "Open line"
			if cp.ActionText ~= want then cp.ActionText = want end
			-- REVIEW-1 B1: while a machine at this station sputters or is jammed, its console steps aside, so the Fix
			-- prompt is the one in reach (on touch, where a key cannot tell them apart); 🏭 Line still opens the panel
			local row = latest.stations[t]
			local trouble = row ~= nil and ((row.n >= 1 and row.jamA ~= 0) or (row.n >= 2 and row.jamB ~= 0))
			if cp.Enabled ~= not trouble then cp.Enabled = not trouble end
		end
	end
	-- Fix on every machine that sputters or is jammed (a hold, so a brush-past never fixes)
	local seen = {}
	for t = 1, 6 do
		local row = latest.stations[t]
		for m = 1, math.min(row.n, 2) do
			local state = if m == 1 then row.jamA else row.jamB
			local keyTM = t .. ":" .. m
			if state ~= 0 then
				seen[keyTM] = true
				local body = machineBody(t, m)
				local fp = fixPrompts[keyTM]
				if fp and fp.body ~= body then
					fp.prompt:Destroy()
					fp.pointer:Destroy()
					fixPrompts[keyTM] = nil
					fp = nil
				end
				if fp == nil and body then
					local p = newPrompt(body, "⚠ " .. ST.Names[t], "Fix", Config.Jams.FixHold)
					p.Name = "FixPrompt"
					-- REVIEW-1 B1: Fix has its OWN key and button and always shows. With the default (E, OnePerButton)
					-- Roblox showed only the nearest E prompt, and the station's console (4.51 studs from where a
					-- player fixes) beat the machine (4.53-4.74): pressing E opened the line instead of fixing.
					p.KeyboardKeyCode = Enum.KeyCode.F
					p.GamepadKeyCode = Enum.KeyCode.ButtonY
					p.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
					p.Triggered:Connect(function()
						FixR:FireServer(IDS[t], if m == 1 then "a" else "b")
					end)
					-- a pointer over the machine, seen from anywhere on the plot
					local bb = Instance.new("BillboardGui")
					bb.Name = "FixPointer"
					bb.Adornee = body
					bb.AlwaysOnTop = true
					bb.Size = UDim2.fromOffset(110, 36)
					bb.StudsOffset = Vector3.new(0, 7, 0)
					local tl = Instance.new("TextLabel")
					tl.BackgroundTransparency = 1
					tl.Size = UDim2.fromScale(1, 1)
					tl.Font = Enum.Font.GothamBlack
					tl.TextScaled = true
					tl.TextColor3 = AMBER
					tl.TextStrokeTransparency = 0.2
					tl.Text = "⚠ FIX"
					tl.Parent = bb
					bb.Parent = promptFolder
					fixPrompts[keyTM] = { prompt = p, pointer = bb, body = body }
				end
			end
		end
	end
	for keyTM, fp in fixPrompts do
		if not seen[keyTM] then
			fp.prompt:Destroy()
			fp.pointer:Destroy()
			fixPrompts[keyTM] = nil
		end
	end
	-- the board toggle
	if boardPrompt == nil then
		local board = plot:FindFirstChild("Board")
		local face = board and board:FindFirstChild("BoardFace")
		if face then
			local p = newPrompt(face, "♻ Top Recyclers", "Switch Public / Friends", 0)
			p.Name = "BoardPrompt"
			p.MaxActivationDistance = Config.Board.PromptDistance
			p.Triggered:Connect(function()
				boardMode = if boardMode == "public" then "friends" else "public"
				BoardViewR:FireServer(boardMode)
			end)
			boardPrompt = p
		end
	end
	ensureBoardGui()
end

StateR.OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then return end
	latest = st
	if mode == "confirm" and not st.recycleReady then setMode("normal") end
	render()
	ensurePrompts()
end)

--============================================================================ the Top Recyclers rows, on the owner's own board
-- A SurfaceGui in THIS player's PlayerGui with Adornee = their own board, so their friends list and rows reach
-- only them. It sits in a Folder so it is never mistaken for screen furniture.
local boardFolder = Instance.new("Folder")
boardFolder.Name = "BoardGuis"
boardFolder.Parent = playerGui
local surface: SurfaceGui? = nil
local rowsFrame: Frame? = nil
local statusText: TextLabel? = nil
local modeText: TextLabel? = nil
local footerText: TextLabel? = nil
local pendingBoard: any = nil
local renderBoard: (any) -> ()

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

ensureBoardGui = function()
	if surface ~= nil or myPlot == nil then return end
	local board = (myPlot :: Instance):FindFirstChild("Board")
	local face = board and board:FindFirstChild("BoardFace")
	if face == nil then return end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "TopRecyclers"
	sg.Adornee = face
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0
	sg.ResetOnSpawn = false
	sg.ZOffset = 1
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	bg.BorderSizePixel = 0
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = sg
	-- REVIEW-2 R1: the rows take 82 % of the face (was 62 %); the mode line, status and footer are thin strips
	modeText = boardText(bg, "ModeText", 0.01, 0.07, Enum.Font.GothamBlack, GOLD)
	local rf = Instance.new("Frame")
	rf.Name = "Rows"
	rf.BackgroundTransparency = 1
	rf.Position = UDim2.fromScale(0, 0.085)
	rf.Size = UDim2.fromScale(1, 0.82)
	rf.Parent = bg
	rowsFrame = rf
	statusText = boardText(bg, "StatusText", 0.905, 0.045, Enum.Font.GothamBold, Color3.fromRGB(210, 214, 240))
	footerText = boardText(bg, "FooterText", 0.95, 0.045, Enum.Font.Gotham, Color3.fromRGB(180, 184, 210))
	sg.Parent = boardFolder
	surface = sg
	if pendingBoard then renderBoard(pendingBoard) end
end

renderBoard = function(payload: any)
	pendingBoard = payload
	if surface == nil or rowsFrame == nil then return end
	local rf = rowsFrame :: Frame
	for _, c in rf:GetChildren() do c:Destroy() end
	boardMode = if payload.mode == "friends" then "friends" else "public"
	;(modeText :: TextLabel).Text = if payload.mode == "friends" then "♻ TOP RECYCLERS · FRIENDS" else "♻ TOP RECYCLERS · EVERYONE"
	-- REVIEW-2 R2: the top PublicSize rows, and the viewer's own row under them when it is not among them (the
	-- server sends it as an 11th row on the public view; a friends view can send up to 201). It used to be cut off.
	local rows = payload.rows or {}
	local top = Config.Board.PublicSize
	local slots = Config.Board.ShownRows
	local list = {}
	local mineShown = false
	for i = 1, math.min(#rows, top) do
		table.insert(list, rows[i])
		if rows[i].you then mineShown = true end
	end
	if not mineShown then
		for i = top + 1, #rows do
			if rows[i].you then
				table.insert(list, rows[i])
				break
			end
		end
	end
	for i, r in list do
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
		t.Text = string.format("%s %s  %s %d", rank, tostring(r.name), tostring(r.emoji), r.bolts or 0)
		t.Parent = rf
	end
	;(statusText :: TextLabel).Text = payload.status or ""
	;(footerText :: TextLabel).Text = payload.footer or "" -- the prompt itself says "Switch Public / Friends"
end
BoardR.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then renderBoard(payload) end
end)
