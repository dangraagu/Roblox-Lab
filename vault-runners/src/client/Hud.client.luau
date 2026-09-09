-- VAULT RUNNERS — HUD (klient). Viser bare; serveren bestemmer alt.
--
-- Havner i StarterPlayerScripts. Den bygges for TELEFON først: alt er tegnet i design-piksler
-- mot 1280x720 og skalert av ÉN UIScale på rot-framen, og på en telefon (`layout.compact`)
-- gjemmer sidepanelene seg bak knapper langs TOPPKANTEN.
--
-- Reglene fra docs/mobile-ui-brief.md som denne fila følger bokstavelig:
--   1. UIScale ligger på en Frame, aldri på ScreenGui (der gjør den ingenting), og roten er
--      UDim2.fromScale(1/scale, 1/scale) så den fortsatt dekker skjermen ETTER skalering.
--   2. Sidepaneler gjennom Responsive.sideWidth / fitHeight, og de kollapser når compact.
--   3. INGENTING trykkbart nede til venstre eller nede til høyre — der bor Roblox sin egen
--      styrespak og hoppknapp, og en knapp tegnet der kan aldri trykkes.
--   4. Ny layout på Camera:GetPropertyChangedSignal("ViewportSize") — rotasjon og vindusendring.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local remotes = ReplicatedStorage:WaitForChild("VaultRemotes")
local StateEvent = remotes:WaitForChild("State")
local RunEvent = remotes:WaitForChild("Run")
local EnterEvent = remotes:WaitForChild("Enter")
local BuyEvent = remotes:WaitForChild("Buy")
local EquipEvent = remotes:WaitForChild("Equip")
local ToastEvent = remotes:WaitForChild("Toast")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local ACCENT = Color3.fromRGB(Config.Hud.AccentColor.r, Config.Hud.AccentColor.g, Config.Hud.AccentColor.b)
local DANGER = Color3.fromRGB(Config.Hud.DangerColor.r, Config.Hud.DangerColor.g, Config.Hud.DangerColor.b)
local PANEL = Color3.fromRGB(Config.Hud.PanelColor.r, Config.Hud.PanelColor.g, Config.Hud.PanelColor.b)

--============================================================================ scaffolding

local gui = Instance.new("ScreenGui")
gui.Name = "VaultHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- The UIScale lives HERE, on a Frame, not on the ScreenGui.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = root

local function panel(name, size, position, anchor)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor or Vector2.new(0, 0)
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Parent = root
	FxClient.theme(f, { corner = 12, stroke = ACCENT, strokeThickness = 1.5, strokeTransparency = 0.5 })
	return f
end

local function text(parent, name, size, position, txt, textSize, colour, align)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = size
	t.Position = position
	t.BackgroundTransparency = 1
	t.Text = txt
	t.TextSize = textSize or 18
	t.TextColor3 = colour or Color3.fromRGB(240, 238, 250)
	t.Font = Enum.Font.GothamBold
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

local function button(parent, name, size, position, txt)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = Color3.fromRGB(38, 36, 52)
	b.BorderSizePixel = 0
	b.Text = txt
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(242, 240, 250)
	b.Font = Enum.Font.GothamBold
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.AutoButtonColor = true
	b.Parent = parent
	FxClient.theme(b, { corner = 10, stroke = ACCENT, strokeThickness = 1, strokeTransparency = 0.6 })
	return b
end

--============================================================================ the pieces

-- Wallet: top-left, never tappable, never in the way.
local wallet = panel("Wallet", UDim2.fromOffset(300, 62), UDim2.fromOffset(14, 14))
local walletGems = text(wallet, "Gems", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(12, 6), "💎 0", 20, ACCENT)
local walletSub = text(wallet, "Sub", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(12, 32),
	"🏆 0 banked   🐾 x1.00", 14, Color3.fromRGB(190, 188, 205))

-- The collapse clock: dead centre at the top, the only thing that matters mid-run.
local timer = panel("Timer", UDim2.fromOffset(280, 92), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0))
local timerBig = text(timer, "Seconds", UDim2.new(1, -20, 0, 44), UDim2.fromOffset(10, 4),
	"70.0", 40, ACCENT, Enum.TextXAlignment.Center)
local timerSub = text(timer, "Detail", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 48),
	"", 15, Color3.fromRGB(210, 208, 225), Enum.TextXAlignment.Center)
local timerBarBg = Instance.new("Frame")
timerBarBg.Name = "BarBg"
timerBarBg.Size = UDim2.new(1, -20, 0, 8)
timerBarBg.Position = UDim2.fromOffset(10, 74)
timerBarBg.BackgroundColor3 = Color3.fromRGB(50, 48, 66)
timerBarBg.BorderSizePixel = 0
timerBarBg.Parent = timer
FxClient.theme(timerBarBg, { corner = 4 })
local timerBar = Instance.new("Frame")
timerBar.Name = "Bar"
timerBar.Size = UDim2.fromScale(1, 1)
timerBar.BackgroundColor3 = ACCENT
timerBar.BorderSizePixel = 0
timerBar.Parent = timerBarBg
FxClient.theme(timerBar, { corner = 4 })
timer.Visible = false

-- Both side panels are SCROLLING lists. A list that can outgrow its box has to be a
-- ScrollingFrame, and on a phone every one of these boxes outgrows itself: the tap targets below
-- are sized so they are still 44+ SCREEN px after the UIScale, which makes them roughly twice as
-- tall in design px as they look on a monitor.
local function listPanel(name, title, designW, designH, right)
	local f = panel(name, UDim2.fromOffset(designW, designH),
		right and UDim2.new(1, -14, 0, 88) or UDim2.fromOffset(14, 88),
		right and Vector2.new(1, 0) or Vector2.new(0, 0))
	text(f, "Title", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 8), title, 18, ACCENT)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, -24, 1, -44)
	scroll.Position = UDim2.fromOffset(12, 34)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = f
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 8)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = scroll
	return f, scroll, lay
end

local vaultPanel, vaultScroll, vaultLayout = listPanel("Vaults", "🏦 VAULTS", 280, 250, false)
local petPanel, petScroll, petLayout =
	listPanel("Pets", "🐾 " .. Config.Pets.Rarity .. "S", 280, 330, true)

local vaultRows = {}
for i = 1, #Config.Tiers do
	local b = button(vaultScroll, "Tier_" .. i, UDim2.new(1, -8, 0, 58), UDim2.new(), "")
	b.LayoutOrder = i
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.Activated:Connect(function() EnterEvent:FireServer(i) end)
	vaultRows[i] = b
end

local petRows = {}
for i, pet in ipairs(Config.Pets.List) do
	local b = button(petScroll, "Pet_" .. pet.id, UDim2.new(1, -8, 0, 44), UDim2.new(), "")
	b.LayoutOrder = i
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.Activated:Connect(function()
		local row = petRows[pet.id]
		if row and row.owned then EquipEvent:FireServer(pet.id) else BuyEvent:FireServer(pet.id) end
	end)
	petRows[pet.id] = { button = b, owned = false }
end

-- THE CANVAS IS IN DESIGN PX; AbsoluteContentSize IS IN SCREEN PX.
-- Under a UIScale those are different numbers, and mixing them only shows up below 1280x720 —
-- i.e. on the phones where most of the players are. Dividing by the scale is the whole fix, and
-- the headless HUD check on an 800x360 viewport is the only thing that catches it.
local function syncCanvas()
	local sc = math.max(uiScale.Scale, 0.01)
	vaultScroll.CanvasSize = UDim2.fromOffset(0, math.ceil(vaultLayout.AbsoluteContentSize.Y / sc) + 10)
	petScroll.CanvasSize = UDim2.fromOffset(0, math.ceil(petLayout.AbsoluteContentSize.Y / sc) + 10)
end
vaultLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)
petLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)

-- Compact-mode toggles live on the TOP edge. Never the bottom corners — Roblox's own thumbstick
-- and jump button own those, and a button drawn there can never be pressed.
local vaultToggle = button(root, "VaultToggle", UDim2.fromOffset(130, 44), UDim2.fromOffset(14, 88), "🏦 VAULTS")
local petToggle = button(root, "PetToggle", UDim2.fromOffset(130, 44), UDim2.new(1, -14, 0, 88), "🐾 PETS")
petToggle.AnchorPoint = Vector2.new(1, 0)

local toast = text(root, "Toast", UDim2.new(0, 520, 0, 30), UDim2.new(0.5, 0, 0, 118),
	"", 17, ACCENT, Enum.TextXAlignment.Center)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.TextStrokeTransparency = 0.4
toast.Visible = false

--============================================================================ layout

-- On a phone only ONE side panel is open at a time; opening one closes the other.
local vaultOpen, petOpen = true, false
local layout = Responsive.layout(1280, 720, false)
local inRun = false

local function applyLayout()
	local v = camera.ViewportSize
	local touch = UserInputService.TouchEnabled
	layout = Responsive.layout(v.X, v.Y, touch)
	uiScale.Scale = layout.scale
	-- The root has to be BIGGER than the screen in design px, or a scaled HUD shrinks into the
	-- top-left corner — and only on phones, where nobody is looking.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	-- 44 SCREEN px is the floor for anything tappable. Design px are what we set, so the
	-- requirement has to be divided back through the scale: a 44-px button on a 0.5-scale phone
	-- is a 22-px button, which is a button nobody can hit.
	local minTap = touch and math.ceil(46 / layout.scale) or 0
	local tierH = math.max(58, minTap)
	local petH = math.max(44, minTap)
	local toggleH = math.max(44, minTap)

	for _, b in ipairs(vaultRows) do
		b.Size = UDim2.new(1, -8, 0, tierH)
	end
	for _, row in pairs(petRows) do
		row.button.Size = UDim2.new(1, -8, 0, petH)
	end
	vaultToggle.Size = UDim2.fromOffset(math.max(130, minTap), toggleH)
	petToggle.Size = UDim2.fromOffset(math.max(130, minTap), toggleH)

	local top = layout.compact and (88 + toggleH + 8) or 88
	vaultPanel.Position = UDim2.fromOffset(14, top)
	petPanel.Position = UDim2.new(1, -14, 0, top)

	-- Screen px left under the panel's own top edge, once the touch controls are out.
	local usable = math.max(60, Responsive.usableHeight(v.Y, layout) - top * layout.scale)
	local w = Responsive.sideWidth(280, v.X, layout)
	vaultPanel.Size = UDim2.fromOffset(w, Responsive.fitHeight(44 + 3 * (tierH + 8), usable, layout))
	petPanel.Size = UDim2.fromOffset(w, Responsive.fitHeight(44 + 8 * (petH + 8), usable, layout))

	vaultToggle.Visible = layout.compact and not inRun
	petToggle.Visible = layout.compact and not inRun
	vaultPanel.Visible = not inRun and ((not layout.compact) or vaultOpen)
	petPanel.Visible = not inRun and ((not layout.compact) or petOpen)

	toast.Position = UDim2.new(0.5, 0, 0, layout.compact and 96 or 118)
	toast.Size = UDim2.new(0, math.min(520, math.floor(v.X / layout.scale) - 28), 0, 30)
	wallet.Size = UDim2.fromOffset(math.min(300, math.floor(v.X / layout.scale) - 28), 62)
	syncCanvas()
end

vaultToggle.Activated:Connect(function()
	vaultOpen = not vaultOpen
	if vaultOpen then petOpen = false end
	applyLayout()
end)
petToggle.Activated:Connect(function()
	petOpen = not petOpen
	if petOpen then vaultOpen = false end
	applyLayout()
end)

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)

-- ViewportSize alone is NOT enough. A device can gain or lose touch without the window ever
-- changing size, and the layout would then keep mouse-sized tap targets on a touchscreen — every
-- button in the HUD at half the 44-px floor, on exactly the devices where it matters. The
-- headless HUD check runs the same 800x360 viewport twice, once with a mouse and once with
-- touch, for the sole purpose of catching a missing listener here; it caught this one.
-- pcall because a Roblox service can refuse a property signal, and a HUD that fails to build is
-- worse than a HUD that only follows the viewport.
local okTouch, touchErr = pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
if not okTouch then
	warn("[Vault] no TouchEnabled listener; layout will follow the viewport only: " .. tostring(touchErr))
end

--============================================================================ state

local function renderState(s)
	walletGems.Text = string.format("💎 %d", s.gems)
	walletSub.Text = string.format("🏆 %d banked   🐾 x%.2f", s.totalBanked, s.mult)

	for i, t in ipairs(s.tiers) do
		local b = vaultRows[i]
		if b then
			if t.unlocked then
				b.Text = string.format("  %s %s\n  Floor %d  ·  tap to drop in", t.emoji, t.name, t.floor)
				b.TextColor3 = Color3.fromRGB(242, 240, 250)
			else
				b.Text = string.format("  🔒 %s\n  %d more gems to bank", t.name, t.remaining)
				b.TextColor3 = Color3.fromRGB(150, 148, 165)
			end
		end
	end

	for _, pet in ipairs(s.pets) do
		local row = petRows[pet.id]
		if row then
			row.owned = pet.owned
			if pet.equipped then
				row.button.Text = string.format("  %s %s  ·  EQUIPPED  x%.2f", pet.emoji, pet.name, pet.mult)
				row.button.TextColor3 = ACCENT
			elseif pet.owned then
				row.button.Text = string.format("  %s %s  ·  tap to equip  x%.2f", pet.emoji, pet.name, pet.mult)
				row.button.TextColor3 = Color3.fromRGB(200, 235, 205)
			else
				row.button.Text = string.format("  %s %s  ·  💎 %d  ·  x%.2f", pet.emoji, pet.name, pet.cost, pet.mult)
				row.button.TextColor3 = Color3.fromRGB(200, 198, 215)
			end
		end
	end

	inRun = s.inRun == true
	applyLayout()
end

StateEvent.OnClientEvent:Connect(renderState)

--============================================================================ the run

local toastToken = 0
local function showToast(msg)
	toastToken += 1
	local mine = toastToken
	toast.Text = msg
	toast.Visible = true
	task.delay(4, function()
		if toastToken == mine then toast.Visible = false end
	end)
end
ToastEvent.OnClientEvent:Connect(showToast)

local live = nil   -- { timeLeft, at, collapseSeconds, carried, collected, total }

local function paintTimer()
	if not live then return end
	local left = math.max(0, live.timeLeft - (os.clock() - live.at))
	timerBig.Text = string.format("%.1f", left)
	timerSub.Text = string.format("💎 %d carried   ·   %d/%d found", live.carried, live.collected, live.total)
	local frac = live.collapseSeconds > 0 and math.clamp(left / live.collapseSeconds, 0, 1) or 0
	timerBar.Size = UDim2.fromScale(frac, 1)
	local danger = left <= Config.Run.SealWarnSeconds
	timerBig.TextColor3 = danger and DANGER or ACCENT
	timerBar.BackgroundColor3 = danger and DANGER or ACCENT
end

RunEvent.OnClientEvent:Connect(function(kind, data)
	if kind == "start" then
		live = { timeLeft = data.collapseSeconds, at = os.clock(),
			collapseSeconds = data.collapseSeconds, carried = 0, collected = 0, total = data.gems }
		timer.Visible = true
		FxClient.popIn(timer)
		showToast(string.format("%s %s · Floor %d — %d storeys, %d gems, %.0f seconds. RUN.",
			data.emoji, data.tierName, data.floor, data.storeys, data.gems, data.collapseSeconds))
		inRun = true
		applyLayout()
	elseif kind == "tick" and live then
		live.timeLeft = data.timeLeft
		live.at = os.clock()
		live.carried = data.carried
		live.collected = data.collected
		live.total = data.total
		paintTimer()
	elseif kind == "gem" and live then
		live.carried = data.carried
		live.collected = data.collected
		live.total = data.total
		FxClient.fovPunch(-2, 0.06, 0.12)
		paintTimer()
	elseif kind == "end" then
		live = nil
		timer.Visible = false
		inRun = false
		applyLayout()
		if data.ok then
			FxClient.flash(ACCENT, 0.25, 0.35)
		else
			FxClient.shake(0.45, 1.6)
			FxClient.flash(DANGER, 0.35, 0.5)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.05)
		if live then paintTimer() end
	end
end)
