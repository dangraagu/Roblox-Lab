-- Hud.client.luau — HUD for "Anomaly: Night Shift at the Observatory".
-- The ADVANCE / TURN BACK / USE HINT actions are in-world ProximityPrompts (keys E / Q / H),
-- so this is display + the code-redeem box + the tint picker only. All state is pushed by
-- the server via the State remote; the client trusts nothing it computes itself.
--
-- Layout goes through Responsive.luau. This is a game about LOOKING at the hall, so screen
-- space is the scarce resource here: on a phone the status panel and the code/tint tools are
-- collapsed behind two small toggles on the TOP edge, the middle of the screen is left empty,
-- and nothing interactive is parked at the bottom where Roblox draws the movement thumbstick
-- and the jump button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local plr = Players.LocalPlayer
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
-- Shared data lives in ReplicatedStorage and is required the ROBLOX way — with an Instance.
-- Never `require("./Config")`: a path string resolves in the luau CLI but is invalid in
-- Roblox and makes the whole LocalScript fail to load.
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local Remotes = ReplicatedStorage:WaitForChild("AnomalyRemotes")
local StateRemote = Remotes:WaitForChild("State") :: RemoteEvent
local RevealRemote = Remotes:WaitForChild("Reveal") :: RemoteEvent
local DeathRemote = Remotes:WaitForChild("Death") :: RemoteEvent
local RedeemRemote = Remotes:WaitForChild("Redeem") :: RemoteEvent
local TintRemote = Remotes:WaitForChild("SetTint") :: RemoteEvent

-- CurrentCamera is normally already there, but it is nil for the first frames of a rare slow
-- join and every layout decision below reads its ViewportSize — indexing nil would kill the
-- whole HUD, redeem box included.
local camera = workspace.CurrentCamera
while not camera do
	task.wait()
	camera = workspace.CurrentCamera
end

-- id -> catalog entry { id, name, kind, hint }. Lets a death name the anomaly the player
-- walked straight past, which is the single most useful teaching beat in the game.
local ANOMALY_BY_ID = {}
for _, entry in Config.Anomaly.Catalog do
	ANOMALY_BY_ID[entry.id] = entry
end

local gui = Instance.new("ScreenGui")
gui.Name = "AnomalyHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = plr:WaitForChild("PlayerGui")

-- A UIScale does NOTHING parented to a ScreenGui, so every HUD element hangs off this root
-- Frame and the scale rides on the root instead.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local layout = Responsive.layout(camera.ViewportSize.X, camera.ViewportSize.Y, UserInputService.TouchEnabled)

local DARK = Color3.fromRGB(18, 20, 30)
local ACCENT = Color3.fromRGB(120, 180, 255)
local WARN = Color3.fromRGB(230, 90, 80)
local GOOD = Color3.fromRGB(90, 200, 130)

-- Roblox's own guidance and both mobile platform guidelines put the smallest comfortable tap
-- target at 44 SCREEN px in both dimensions. Below that a control is drawn but not reliably
-- hittable with a thumb.
local TAP_MIN = 44

-- Design widths of the two phone drawer toggles. Named because applyLayout has to convert them
-- into screen space and the toggleButton factory has to seed them.
local TOGGLE_W_STATUS = 112
local TOGGLE_W_MENU = 96

-- Interactive controls are sized in SCREEN px, not design px. A UIScale below 1 shrinks every
-- button on exactly the device whose players need them biggest: the DAY and MENU toggles came
-- out at 67x18 and 58x18 on a phone, and the tint swatches at 16x16 — the colour picker was
-- smaller under a thumb than it is under a mouse pointer, which is backwards. Dividing the
-- design size by the scale keeps a control the same physical size whatever the scale is, and
-- the floor keeps it thumb-sized.
--
-- The touch test is `controlPad > 0`, which is true exactly when Roblox is drawing its own
-- touch controls. A small mouse-driven window is therefore left alone, and so is every desktop
-- viewport, where the scale is 1 and this returns the design size unchanged.
-- The ceil is not cosmetic: 44 / 0.6 is 73.33, which the swatch row then floors back to 73 and
-- lands at 43.8 screen px — a fifth of a pixel under the bar, and Roblox rounds an offset to a
-- whole pixel anyway. Rounding up here means every derived size clears 44 with room to spare.
local function tapSize(designPx: number): number
	if layout.controlPad <= 0 then
		return designPx
	end
	return math.ceil(math.max(designPx, TAP_MIN) / layout.scale)
end

-- Text inside a control that grew has to grow with it, or a 44 px button carries a 9 px label.
-- Same touch-only gate, and no floor: this is readability, not hit area.
local function tapText(designSize: number): number
	if layout.controlPad <= 0 then
		return designSize
	end
	return math.floor(designSize / layout.scale)
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, ts: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = Color3.fromRGB(235, 235, 245)
	l.TextScaled = false
	l.TextSize = ts
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

-- Caps a scale-based width so a wide monitor does not stretch a line of text across 2000px.
local function capWidth(g: GuiObject, maxX: number)
	local c = Instance.new("UISizeConstraint")
	c.MaxSize = Vector2.new(maxX, math.huge)
	c.Parent = g
end

-- top-left status panel (on a phone this is a drawer behind the DAY toggle)
local panel = Instance.new("Frame")
panel.Name = "Status"
panel.Size = UDim2.fromOffset(230, 96)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.25
panel.BorderSizePixel = 0
panel.Parent = root
-- visual polish: rounded + cold stroke so the HUD reads as part of the horror theme
FxClient.theme(panel, { corner = 10, stroke = Color3.fromRGB(90, 120, 170), strokeThickness = 1.5, strokeTransparency = 0.35 })

-- Panel labels are sized off the panel width, not a fixed 200px: on a narrow phone the panel
-- itself shrinks (Responsive.sideWidth) and fixed-width children would spill out of it.
local dayLbl = label(panel, "DAY 1", UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 8), 28)
dayLbl.Font = Enum.Font.GothamBold
dayLbl.TextColor3 = ACCENT
local bestLbl = label(panel, "Best: Day 0", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 44), 15)
local codexLbl = label(panel, "Field Guide: 0/0", UDim2.new(1, -28, 0, 20), UDim2.fromOffset(14, 66), 15)

-- instructions (top-center). The long line is unreadable clutter on a phone, where the top
-- edge also has to hold both toggles, so compact mode uses the short form.
local HELP_FULL = "Walk the hall. Something wrong? TURN BACK (Q). Looks normal? ADVANCE (E). Wrong call = back to Day 1."
local HELP_SHORT = "Wrong? TURN BACK (Q).  Normal? ADVANCE (E)."
local help = label(root, HELP_FULL, UDim2.new(0.9, 0, 0, 24), UDim2.new(0.5, 0, 0, 20), 15)
help.AnchorPoint = Vector2.new(0.5, 0)
help.TextXAlignment = Enum.TextXAlignment.Center
help.TextColor3 = Color3.fromRGB(200, 205, 220)
capWidth(help, 680)

-- hint pill (top-right on a big screen; moved inside the status drawer on a phone)
local hintLbl = label(root, "Hints: 0  (H at start pad)", UDim2.fromOffset(240, 22), UDim2.new(1, -256, 0, 18), 15)
hintLbl.TextXAlignment = Enum.TextXAlignment.Right

-- transient toast (upper middle — never dead centre, that is where the hall is)
local toast = label(root, "", UDim2.new(0.9, 0, 0, 40), UDim2.new(0.5, 0, 0.5, -120), 26)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Font = Enum.Font.GothamBold
toast.TextXAlignment = Enum.TextXAlignment.Center
capWidth(toast, 600)
-- second, smaller line under the toast: the "what you missed" explanation after a wrong call.
local toastDetail = label(root, "", UDim2.new(0.9, 0, 0, 26), UDim2.new(0.5, 0, 0.5, -80), 18)
toastDetail.AnchorPoint = Vector2.new(0.5, 0)
toastDetail.TextXAlignment = Enum.TextXAlignment.Center
toastDetail.TextColor3 = Color3.fromRGB(210, 216, 232)
capWidth(toastDetail, 680)
-- `lifetime` (seconds) defaults to the original 1.8s fade; the death toast asks for longer
-- because its detail line is the teaching beat and has to be readable (kept under the
-- server's 2.5s death pause so it never bleeds into the next pass).
local function showToast(text: string, color: Color3, detail: string?, lifetime: number?)
	toast.Text = text
	toast.TextColor3 = color
	toast.TextTransparency = 0
	toastDetail.Text = detail or ""
	toastDetail.TextTransparency = 0
	task.spawn(function()
		local myText = text
		local steps = math.max(1, math.floor((lifetime or 1.8) / 0.06))
		for i = 1, steps do
			if toast.Text ~= myText then return end
			toast.TextTransparency = i / steps
			toastDetail.TextTransparency = i / steps
			task.wait(0.06)
		end
		if toast.Text == myText then
			toast.Text = ""
			toastDetail.Text = ""
		end
	end)
end

-- Code redeem + tint picker. On a big screen this is a transparent strip along the bottom;
-- on a phone it becomes a small panel behind the MENU toggle, because the bottom band of a
-- touch screen belongs to Roblox's own controls and a button there can never be tapped.
local tools = Instance.new("Frame")
tools.Name = "Tools"
tools.BackgroundColor3 = DARK
tools.BackgroundTransparency = 1
tools.BorderSizePixel = 0
tools.Size = UDim2.new(1, 0, 0, 30)
tools.Position = UDim2.new(0, 0, 1, -46)
tools.Parent = root
Instance.new("UICorner", tools).CornerRadius = UDim.new(0, 10)

local codeBox = Instance.new("TextBox")
codeBox.Name = "CodeBox" -- named so a HUD check reports "CodeBox", not a bare "TextBox"
codeBox.Size = UDim2.fromOffset(150, 30)
codeBox.Position = UDim2.fromOffset(16, 0)
codeBox.BackgroundColor3 = DARK
codeBox.BackgroundTransparency = 0.15
codeBox.BorderSizePixel = 0
codeBox.Font = Enum.Font.Gotham
codeBox.TextColor3 = Color3.fromRGB(235, 235, 245)
codeBox.PlaceholderText = "enter code"
codeBox.TextSize = 15
codeBox.Text = ""
codeBox.ClearTextOnFocus = false
codeBox.Parent = tools
Instance.new("UICorner", codeBox).CornerRadius = UDim.new(0, 8)

local redeemBtn = Instance.new("TextButton")
redeemBtn.Name = "RedeemButton"
redeemBtn.Size = UDim2.fromOffset(90, 30)
redeemBtn.Position = UDim2.fromOffset(172, 0)
redeemBtn.BackgroundColor3 = ACCENT
redeemBtn.BorderSizePixel = 0
redeemBtn.Font = Enum.Font.GothamBold
redeemBtn.TextColor3 = DARK
redeemBtn.TextSize = 15
redeemBtn.Text = "REDEEM"
redeemBtn.Parent = tools
Instance.new("UICorner", redeemBtn).CornerRadius = UDim.new(0, 8)
redeemBtn.Activated:Connect(function()
	local t = codeBox.Text
	if #t > 0 then
		RedeemRemote:FireServer(t)
		codeBox.Text = ""
	end
end)

-- tint picker (populated from State)
local tintRow = Instance.new("Frame")
tintRow.Name = "Tints"
tintRow.AnchorPoint = Vector2.new(1, 0)
tintRow.Size = UDim2.fromOffset(300, 30)
tintRow.Position = UDim2.new(1, -16, 0, 0)
tintRow.BackgroundTransparency = 1
tintRow.Parent = tools
local tintLayout = Instance.new("UIListLayout")
tintLayout.FillDirection = Enum.FillDirection.Horizontal
tintLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
tintLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tintLayout.Padding = UDim.new(0, 6)
tintLayout.Parent = tintRow

-- Colours come from Config.TintRGB (plain {R,G,B} triples so the shared module stays usable
-- by the pure luau-CLI tests) — one source of truth for the swatch AND the carried light.
local TINT_FALLBACK = Color3.fromRGB(200, 200, 200)
local function tintColor(name: string): Color3
	local rgb = Config.TintRGB and Config.TintRGB[name]
	if type(rgb) == "table" and #rgb >= 3 then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return TINT_FALLBACK
end

local tintButtons: { [string]: TextButton } = {}
-- ownership as of the LAST State push. Read at click time (never captured in the closure) so
-- a tint unlocked mid-session — redeeming ECLIPSE — is clickable without a rebuild.
local tintOwned: { [string]: boolean } = {}

-- Design-space width the swatch row currently has; applyLayout keeps it in step with the mode.
local TINT_PAD = 6
local tintRowWidth = 300

-- How many swatches the row has to hold. Config.Tints is what the server sends and it is known
-- before the first State push, so applyLayout can budget the row on the very first pass rather
-- than laying the drawer out once for zero swatches and again for five.
local function tintCount(): number
	local n = 0
	for _ in tintButtons do
		n += 1
	end
	return math.max(n, #Config.Tints, 1)
end

-- Derive the swatch size from the row it has to fit into, so a narrow phone drawer (or a
-- sixth tint added to Config later) shrinks the swatches instead of pushing them off the edge.
--
-- The 26 px clamp used to be the whole story, which meant the swatches only ever got SMALLER
-- than their design size — 16x16 on a phone. The clamp is still the ceiling the row can afford,
-- but on a touch screen the 44 px tap floor wins; applyLayout budgets the row wide enough for
-- it, and `math.min(.., per)` is the belt to that pair of braces so a floor that genuinely will
-- not fit shrinks rather than running off the screen edge.
local function layoutTints()
	local n = 0
	for _ in tintButtons do
		n += 1
	end
	if n == 0 then return end
	local per = math.floor((tintRowWidth - TINT_PAD * (n - 1)) / n)
	local size = math.max(14, math.min(tapSize(math.clamp(per, 14, 26)), per))
	for _, b in tintButtons do
		b.Size = UDim2.fromOffset(size, size)
	end
end

-- Creates any swatch that doesn't exist yet. Appearance is NOT decided here (see
-- refreshTints): the old build-once guard is exactly why an unlocked tint kept looking
-- locked, and every locked tint kept looking live.
local function buildTints(tints: { string })
	for _, name in tints do
		if not tintButtons[name] then
			local b = Instance.new("TextButton")
			b.Name = "Tint_" .. name
			b.Size = UDim2.fromOffset(26, 26)
			b.Text = ""
			b.Font = Enum.Font.GothamBold
			b.TextSize = 13
			b.TextColor3 = Color3.fromRGB(20, 22, 32)
			b.AutoButtonColor = false
			b.BackgroundColor3 = tintColor(name)
			b.BorderSizePixel = 0
			b.Parent = tintRow
			Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
			local ring = Instance.new("UIStroke")
			ring.Name = "SelectionRing"
			ring.Color = ACCENT
			ring.Thickness = 2
			ring.Transparency = 1 -- shown only on the SELECTED tint
			ring.Parent = b
			b.Activated:Connect(function()
				if not tintOwned[name] then
					-- the server silently drops an unowned tint; without this the player just
					-- sees nothing happen and assumes the game is broken.
					showToast("Tint locked", WARN, "Unlock " .. name .. " with a code first.")
					return
				end
				TintRemote:FireServer(name)
			end)
			tintButtons[name] = b
		end
	end
	layoutTints()
end

-- Re-style every swatch for the CURRENT ownership set + selection. Called on every State
-- push, so the gold swatch lights up the moment ECLIPSE is redeemed.
local function refreshTints(owned, selected)
	-- fail OPEN if the server ever omits ownedTints: a HUD where nothing is clickable would
	-- be worse than the bug being fixed. The live server always sends the set.
	local haveSet = typeof(owned) == "table"
	for name, b in tintButtons do
		local isOwned = (not haveSet) or owned[name] == true
		tintOwned[name] = isOwned
		b.BackgroundColor3 = tintColor(name)
		b.BackgroundTransparency = if isOwned then 0 else 0.6
		b.Text = if isOwned then "" else "\u{1F512}" -- padlock on locked swatches
		local ring = b:FindFirstChild("SelectionRing")
		if ring and ring:IsA("UIStroke") then
			ring.Transparency = if name == selected then 0 else 1
		end
	end
end

-- ---------------------------------------------------------------- phone toggles
-- Both toggles sit on the TOP edge. The bottom of a touch screen is Roblox's (thumbstick on
-- the left, jump on the right) and anything we put there is unreachable.
local function toggleButton(name: string, anchorRight: boolean, width: number, text: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = if anchorRight then Vector2.new(1, 0) else Vector2.new(0, 0)
	b.Size = UDim2.fromOffset(width, 30)
	b.BackgroundColor3 = DARK
	b.BackgroundTransparency = 0.15
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = ACCENT
	b.TextSize = 16
	b.Text = text
	b.Visible = false -- phones only; applyLayout decides
	b.Parent = root
	FxClient.theme(b, { corner = 8, stroke = Color3.fromRGB(90, 120, 170), strokeThickness = 1.5, strokeTransparency = 0.35 })
	return b
end

local statusToggle = toggleButton("StatusToggle", false, TOGGLE_W_STATUS, "DAY 1")
local menuToggle = toggleButton("MenuToggle", true, TOGGLE_W_MENU, "MENU")

-- Which drawer the player has opened. Both start closed on a phone: the default view of this
-- game should be the hall and nothing else.
local statusOpen = false
local menuOpen = false

local CARET_DOWN = "\u{25BE}"
local CARET_UP = "\u{25B4}"

local function refreshDrawers()
	local compact = layout.compact
	-- Off a phone both panels are simply always on screen and the toggles are hidden.
	panel.Visible = (not compact) or statusOpen
	tools.Visible = (not compact) or menuOpen
	statusToggle.Text = dayLbl.Text .. "  " .. (if statusOpen then CARET_UP else CARET_DOWN)
	menuToggle.Text = "MENU  " .. (if menuOpen then CARET_UP else CARET_DOWN)
end

statusToggle.Activated:Connect(function()
	statusOpen = not statusOpen
	-- at most one drawer at a time: opened together they would overlap on a narrow screen
	if statusOpen then
		menuOpen = false
	end
	refreshDrawers()
end)

menuToggle.Activated:Connect(function()
	menuOpen = not menuOpen
	if menuOpen then
		statusOpen = false
	end
	refreshDrawers()
end)

-- ---------------------------------------------------------------- layout
-- Everything inside applyLayout is in design px (the units the UIScale multiplies).
-- `layout.controlPad` arrives in SCREEN px, so it is divided by the scale before use.
local function applyLayout()
	local v = camera.ViewportSize
	layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale
	-- CRITICAL: grow the root by 1/scale so root * scale lands exactly on the viewport.
	-- Skip this and the whole HUD shrinks into the top-left corner on phones while looking
	-- perfectly fine on desktop, where scale is 1 and the bug is invisible.
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)

	local compact = layout.compact
	local usable = Responsive.usableHeight(v.Y, layout)
	local padUp = layout.controlPad / layout.scale -- touch-control band, in design px
	-- IgnoreGuiInset is on, so Roblox's own top bar overlaps us. Top-edge buttons have to
	-- start below it or they are simply not tappable.
	local insetTop = GuiService:GetGuiInset().Y / layout.scale
	local topY = if compact then insetTop + 8 else 16
	-- The toggle row is sized in screen px now, so on a phone it stands 44 screen px tall
	-- instead of 18 and the drawers below it have to start correspondingly lower.
	local toggleH = tapSize(30)
	local statusW = tapSize(TOGGLE_W_STATUS)
	local menuW = tapSize(TOGGLE_W_MENU)
	local drawerY = topY + toggleH + 8
	-- A panel hanging off the top edge only gets the room that is left below its own top
	-- offset — otherwise a very short window drops the bottom of a drawer into the touch band.
	local topRoom = math.max(40, usable - (if compact then drawerY else 16) * layout.scale)

	statusToggle.Visible = compact
	menuToggle.Visible = compact
	statusToggle.Size = UDim2.fromOffset(statusW, toggleH)
	menuToggle.Size = UDim2.fromOffset(menuW, toggleH)
	-- A 44 px button carrying a 9 px label looks broken; the text grows with the button.
	statusToggle.TextSize = tapText(16)
	menuToggle.TextSize = tapText(16)
	statusToggle.Position = UDim2.new(0, 12, 0, topY)
	menuToggle.Position = UDim2.new(1, -12, 0, topY)

	-- status panel
	local panelH = if compact then 122 else 96 -- the phone version also carries the hint line
	panel.Size = UDim2.new(0, Responsive.sideWidth(230, v.X, layout), 0, Responsive.fitHeight(panelH, topRoom, layout))
	panel.Position = if compact then UDim2.new(0, 12, 0, drawerY) else UDim2.fromOffset(16, 16)
	bestLbl.TextSize = if compact then 17 else 15
	codexLbl.TextSize = if compact then 17 else 15

	-- hint readout: its own pill top-right on a big screen, a line inside the status drawer on
	-- a phone, where the top edge has only enough room for the two toggles and the help line.
	if compact then
		hintLbl.Parent = panel
		hintLbl.Size = UDim2.new(1, -28, 0, 20)
		hintLbl.Position = UDim2.fromOffset(14, 90)
		hintLbl.TextXAlignment = Enum.TextXAlignment.Left
		hintLbl.TextSize = 17
	else
		hintLbl.Parent = root
		hintLbl.Size = UDim2.fromOffset(240, 22)
		hintLbl.Position = UDim2.new(1, -256, 0, 18)
		hintLbl.TextXAlignment = Enum.TextXAlignment.Right
		hintLbl.TextSize = 15
	end

	-- Instruction line: the long form on a one-line strip as before, the short form squeezed
	-- between the two toggles on a phone. Wrapping is only turned on where the box is tall
	-- enough for a second line, otherwise a wrapped line would be hidden rather than trimmed.
	-- On a phone the width is measured from the gap the toggles actually leave rather than being
	-- a fixed 0.52 of the screen: the toggles are now three times wider in design px than they
	-- were, and a fixed fraction would run underneath them on a narrow portrait screen. Height
	-- matches the toggle row so the line sits centred against it.
	help.Text = if compact then HELP_SHORT else HELP_FULL
	help.TextWrapped = compact
	if compact then
		local rootW = v.X / layout.scale
		local gapLeft = rootW / 2 - (12 + statusW) - 8
		local gapRight = rootW / 2 - (12 + menuW) - 8
		help.Size = UDim2.new(0, math.max(120, 2 * math.min(gapLeft, gapRight)), 0, toggleH)
		help.Position = UDim2.new(0.5, 0, 0, topY)
	else
		help.Size = UDim2.new(0.9, 0, 0, 24)
		help.Position = UDim2.new(0.5, 0, 0, 20)
	end

	-- Toasts sit in the upper third on a phone rather than over the middle of the hall, and get
	-- room for a second line there because the same sentence has far fewer pixels to live in.
	toast.TextWrapped = compact
	toastDetail.TextWrapped = compact
	if compact then
		toast.Size = UDim2.new(0.9, 0, 0, 64)
		toast.Position = UDim2.new(0.5, 0, 0.22, 0)
		toastDetail.Size = UDim2.new(0.9, 0, 0, 44)
		toastDetail.Position = UDim2.new(0.5, 0, 0.22, 68)
	else
		toast.Size = UDim2.new(0.9, 0, 0, 40)
		toast.Position = UDim2.new(0.5, 0, 0.5, -120)
		toastDetail.Size = UDim2.new(0.9, 0, 0, 26)
		toastDetail.Position = UDim2.new(0.5, 0, 0.5, -80)
	end

	-- code + tint tools. Every control here is a tap target, so all four dimensions below come
	-- from tapSize and land on the same physical size whatever the scale is. On a desktop
	-- viewport tapSize is the identity and the arithmetic degenerates to the old literals:
	-- 150x30 code box at x 16, 90x30 button at x 172, a 30 px strip 46 px off the bottom.
	local rowH = tapSize(30)
	local btnW = tapSize(90)
	if compact then
		-- A drawer under the MENU toggle. At 44 screen px per control the old three stacked rows
		-- no longer clear the touch-control band on a short landscape phone — 800x360 leaves
		-- roughly 145 screen px between the toggle row and the thumbstick — so the drawer flows
		-- instead: the code box, the button and the swatches share ONE row when the screen is
		-- wide enough for it, and the swatches drop to a second row when it is not. A short
		-- landscape phone takes the single row, a tall portrait one the two-row form; both keep
		-- the drawer well clear of the band, and it is anchored to the right edge so the middle
		-- of the hall stays visible.
		local padIn, gapIn = 8, 6
		local n = tintCount()
		local maxW = math.max(120, v.X / layout.scale - 2 * 12)
		local codeMin = tapSize(120)
		-- A swatch that will not fit the widest drawer the screen allows shrinks rather than
		-- running off the edge; on every phone viewport we ship for, the tap floor wins.
		local roomPerSwatch = (maxW - padIn * 2 - TINT_PAD * (n - 1)) / n
		local swatch = math.max(14, math.min(tapSize(26), roomPerSwatch))
		local swatchRowW = swatch * n + TINT_PAD * (n - 1)

		local oneRowW = codeMin + gapIn + btnW + gapIn + swatchRowW + padIn * 2
		local twoRowW = math.max(codeMin + gapIn + btnW, swatchRowW) + padIn * 2
		local oneRow = oneRowW <= maxW
		local w = math.min(maxW, if oneRow then oneRowW else twoRowW)
		local needH = padIn * 2 + rowH + (if oneRow then 0 else gapIn + swatch)
		local codeW = math.max(codeMin, (w - padIn * 2) - gapIn - btnW - (if oneRow then gapIn + swatchRowW else 0))

		tools.AnchorPoint = Vector2.new(1, 0)
		tools.Size = UDim2.new(0, w, 0, Responsive.fitHeight(needH, topRoom, layout))
		tools.Position = UDim2.new(1, -12, 0, drawerY)
		tools.BackgroundTransparency = 0.15
		codeBox.Size = UDim2.fromOffset(codeW, rowH)
		codeBox.Position = UDim2.fromOffset(padIn, padIn)
		codeBox.TextSize = tapText(15)
		redeemBtn.Size = UDim2.fromOffset(btnW, rowH)
		redeemBtn.Position = UDim2.fromOffset(padIn + codeW + gapIn, padIn)
		redeemBtn.TextSize = tapText(15)
		tintRow.AnchorPoint = Vector2.new(0, 0)
		tintRow.Size = UDim2.fromOffset(swatchRowW, swatch)
		tintRow.Position = if oneRow
			then UDim2.fromOffset(padIn + codeW + gapIn + btnW + gapIn, padIn + (rowH - swatch) / 2)
			else UDim2.fromOffset(padIn, padIn + rowH + gapIn)
		tintLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		tintRowWidth = swatchRowW
	else
		-- A transparent full-width strip, lifted clear of the touch controls when there are any.
		-- The lift is measured from the strip's own height so a touch tablet, where the controls
		-- are taller, does not push the taller strip back down into the band.
		local codeW = tapSize(150)
		tools.AnchorPoint = Vector2.new(0, 0)
		tools.Size = UDim2.new(1, 0, 0, rowH)
		tools.Position = UDim2.new(0, 0, 1, -(rowH + 16 + padUp))
		tools.BackgroundTransparency = 1
		codeBox.Size = UDim2.fromOffset(codeW, rowH)
		codeBox.Position = UDim2.fromOffset(16, 0)
		codeBox.TextSize = tapText(15)
		redeemBtn.Size = UDim2.fromOffset(btnW, rowH)
		redeemBtn.Position = UDim2.fromOffset(16 + codeW + 6, 0)
		redeemBtn.TextSize = tapText(15)
		-- 300 is the design width the strip has always had, and on a desktop viewport five 26 px
		-- swatches need 154 of it, so this is that same 300. It only grows if the swatches would
		-- not otherwise fit — a touch tablet, or a sixth tint appended to Config — because a row
		-- too narrow for them makes layoutTints shrink them back under the tap target.
		local n = tintCount()
		local rowW = math.max(300, tapSize(26) * n + TINT_PAD * (n - 1) + 6)
		tintRow.AnchorPoint = Vector2.new(1, 0)
		tintRow.Size = UDim2.fromOffset(rowW, rowH)
		tintRow.Position = UDim2.new(1, -16, 0, 0)
		tintLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		tintRowWidth = rowW
	end
	layoutTints()
	refreshDrawers()
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
-- Every tap-target size above is decided by whether Roblox is drawing its own touch controls,
-- and that is not fixed for the life of a session: a detachable tablet keyboard flips it
-- without the viewport changing by a single pixel. Listening to the viewport alone leaves the
-- HUD laid out for the wrong input device until something else happens to resize it.
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)

-- ---------------------------------------------------------------- carried flashlight
-- The tint was stored, validated, persisted, replicated and pickable — but nothing ever lit
-- anything with it, so the cosmetic (and ECLIPSE's only reward) was invisible. A small light
-- carried by the local character: thematic for a dark observatory, deliberately not a
-- floodlight, and client-only (it is a cosmetic for its owner).
local LIGHT_NAME = "AnomalyTintLight"
local currentTint = Config.DefaultTint

local function ensureLight(char: Model): SpotLight?
	local head = char:FindFirstChild("Head") or char:WaitForChild("Head", 5)
	if not head or not head:IsA("BasePart") then return nil end
	local existing = head:FindFirstChild(LIGHT_NAME)
	if existing and existing:IsA("SpotLight") then return existing end
	if existing then existing:Destroy() end
	local s = Instance.new("SpotLight")
	s.Name = LIGHT_NAME
	s.Face = Enum.NormalId.Front -- the head's front == where the player is looking
	s.Angle = 55
	s.Range = 26
	s.Brightness = 1.2
	s.Shadows = false -- cheap: this is ambience, not a lighting rig
	s.Parent = head
	return s
end

-- yields (WaitForChild) — always call via task.spawn.
local function applyTintLight(char: Model?)
	if not char or not char.Parent then return end
	local light = ensureLight(char)
	if light then
		light.Color = tintColor(currentTint)
	end
end

plr.CharacterAdded:Connect(function(char)
	task.spawn(applyTintLight, char)
end)
if plr.Character then
	task.spawn(applyTintLight, plr.Character)
end

-- ---------------------------------------------------------------- remote wiring
StateRemote.OnClientEvent:Connect(function(s)
	if typeof(s) ~= "table" then return end
	dayLbl.Text = "DAY " .. tostring(s.day)
	bestLbl.Text = "Best: Day " .. tostring(s.best)
	codexLbl.Text = "Field Guide: " .. tostring(s.codexCount) .. "/" .. tostring(s.codexTotal)
	hintLbl.Text = "Hints: " .. tostring(s.hintTokens) .. "  (H at start pad)"
	-- the collapsed phone toggle doubles as the day readout, so it follows dayLbl
	refreshDrawers()
	if s.tints then
		buildTints(s.tints)
		refreshTints(s.ownedTints, s.tint)
	end
	if type(s.tint) == "string" and s.tint ~= currentTint then
		currentTint = s.tint
		task.spawn(applyTintLight, plr.Character) -- no character yet? CharacterAdded re-applies
	end
end)

RevealRemote.OnClientEvent:Connect(function(r)
	if typeof(r) ~= "table" then return end
	if r.redeem ~= nil then
		if r.redeem == "ok" then
			showToast("Code redeemed!", GOOD)
		elseif r.redeem == "already" then
			showToast("Code already used", WARN)
		elseif r.redeem == "unknown" then
			showToast("Unknown code", WARN)
		elseif r.redeem == "empty" then
			showToast("Enter a code", WARN)
		elseif r.redeem == "unavailable" or r.redeem == "retry" then
			-- saving is down / another session holds the lock: nothing was granted, so say so
			-- instead of silently doing nothing (server refuses to grant what it can't persist)
			showToast(r.message or "Saving unavailable — try again in a moment", WARN)
		end
		return
	end
	-- one-shot "this session cannot save" notice (server sets readOnly when it does not hold
	-- the DataStore lock, and clears it if a later retry wins the lock back). Without this the
	-- player grinds a best day that will never persist and is never told.
	if r.readOnly ~= nil then
		if r.readOnly then
			showToast(r.message or "Progress is NOT saving this session", WARN,
				"Another session holds your save, or the data service is down. Try rejoining.", 3.2)
		else
			showToast(r.message or "Saving restored", GOOD, nil, 2.2)
		end
		return
	end
	-- hint reveal
	if r.ok == false then
		if r.reason == "too_far" then
			-- the hint is only spendable at the start pad; say so instead of looking dead
			showToast("Too far from the start pad", WARN, "Walk back to the glowing pad to use a hint.", 2.4)
		else
			showToast("No hints left", WARN)
		end
	elseif r.ok == true then
		-- the server tells us how many tokens survived the spend; show it so the player can
		-- budget the last hint instead of guessing.
		local left = ""
		if type(r.remaining) == "number" then
			local n = math.max(0, math.floor(r.remaining))
			left = "  (" .. tostring(n) .. (if n == 1 then " hint left)" else " hints left)")
		end
		if r.clean then
			showToast("HINT: the hall looks clean" .. left, GOOD)
		else
			showToast("HINT: something is WRONG" .. left, WARN)
		end
	end
end)

DeathRemote.OnClientEvent:Connect(function(d)
	if typeof(d) ~= "table" then return end
	-- the jumpscare beat: red vignette flash + camera shake + a short FOV punch
	FxClient.flash(Color3.fromRGB(180, 20, 20), 0.6, 0.7)
	FxClient.shake(0.5, 1.6)
	FxClient.fovPunch(12, 0.08, 0.4)
	local msg, detail
	if d.wasClean then
		msg = "You turned back on a CLEAN hall — Night reset (reached Day " .. tostring(d.reached) .. ")"
		detail = "Nothing was wrong that pass. ADVANCE (E) when the hall looks normal."
	else
		msg = "You MISSED an anomaly — Night reset (reached Day " .. tostring(d.reached) .. ")"
		-- name what was actually wrong: the whole point of a spot-the-difference game is
		-- learning the tell you walked past.
		if type(d.anomalyId) == "string" then
			local entry = ANOMALY_BY_ID[d.anomalyId]
			if entry then
				detail = "It was " .. tostring(entry.name) .. " — " .. tostring(entry.hint)
			else
				detail = "It was: " .. d.anomalyId -- id from a newer catalog than this client
			end
		end
	end
	showToast(msg, WARN, detail, 2.4)
end)

print("[Anomaly] HUD ready.")
