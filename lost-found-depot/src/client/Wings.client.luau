-- LOST & FOUND DEPOT — the wings. Client only (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads the player's career from the server's own State payload (shifts completed + the share of the
--     running shift cleared: Wings.progress) — the game's real progress, never a timer — and blends the
--     wings in Config.Env (EnvBands): lighting, atmosphere, stars, post-fx, the roof over the bay, the
--     landmarks over the walls, ambient life and weather, smoothed so nothing ever hard-cuts;
--   * runs the rare, telegraphed hazards (Hazards) on the sorting floor (Wings lanes) while the shift
--     clock runs, and gives the local character a short stumble on a hit;
--   * runs the BREAK (Rest via Wings): it starts only while the clock is not running, is booked when
--     pressed mid-shift, and ends at the first pickup. It pauses hazards; it never touches the clock.
--
-- Why all of it is client-side, and why that is safe:
--   * it is cosmetic, or it only ever harms the local player, whose character physics the client already
--     owns. The server does not know wings, hazards or breaks exist: this script fires no remote and adds
--     none, sets no attribute and writes nothing the server built. Every sort, pay, clock and save stays
--     the server's; a stumble costs a second or two of the player's own clock and moves nothing else;
--   * everything it builds is created here, lives in its own workspace folder (never in a bay) and is
--     non-collidable, non-queryable and non-touchable: taps and the camera pass straight through it;
--   * it reads only this player's State payload (which the server sends to this player alone; the HUD
--     passes it on through StateCache, so this script adds no listener to the remote), the local
--     character, the local camera, Config and the bay's public BayPad position.
-- Budgets and bands: EYECANDY.md. Headless checks: robloxemu/check_lostfounddepot_wings.luau (glue,
-- hazards, break, budgets, leaks), _wingview (tags and taps with the wings built), _hud_wings (both
-- ScreenGuis on every viewport) and _compile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Wings = require(ReplicatedStorage:WaitForChild("Wings"))
local WingArt = require(ReplicatedStorage:WaitForChild("WingArt"))
local Layout = require(ReplicatedStorage:WaitForChild("Layout"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Env, Hz, RestCfg = Config.Env, Config.Hazards, Config.Rest
local bands = Env.Bands

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[DepotWings] Config.Env.Bands is invalid (" .. tostring(err) .. "); the depot stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[DepotWings] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[DepotWings] Config.Rest is invalid (" .. tostring(restErr) .. "); the break is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- The server's State payload, as the HUD received it. This script never listens on the State remote
-- itself: Roblox hands an event queued before any listener to the FIRST connection, and the HUD must
-- keep getting the loaded profile at join (StateCache.luau).
local StateCache = require(ReplicatedStorage:WaitForChild("StateCache"))

-- ── local world + lighting rig ────────────────────────────────────────────────
local folder = Instance.new("Folder")
folder.Name = "DepotWings"
folder.Parent = workspace

local art = WingArt.new(folder, rand, Config, EnvBands)

-- Take over the server's Fx.applyLighting objects by name (Fx.Presets.Temple = wing 1), so the client
-- starts from exactly the values the server set instead of stacking a second Atmosphere on top.
local function rig(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end
local targets = {
	lighting = Lighting,
	atmosphere = rig("Atmosphere", "FxAtmosphere"),
	sky = rig("Sky", "DepotSky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
pcall(function() (targets.sky :: any).CelestialBodiesShown = true end)

local breakFocus = Instance.new("DepthOfFieldEffect")
breakFocus.Name = "DepotBreakFocus"
breakFocus.FarIntensity = 0.3
breakFocus.FocusDistance = 12
breakFocus.InFocusRadius = 16
breakFocus.NearIntensity = 0
breakFocus.Enabled = false
breakFocus.Parent = Lighting

local written: { [Instance]: { [string]: any } } = {}
local function writeGroup(inst: Instance, props: { [string]: any })
	local last = written[inst]
	if last == nil then
		last = {}
		written[inst] = last
	end
	for k, v in props do
		local prev = last[k]
		local changed
		if type(v) == "table" then
			changed = prev == nil or math.abs(prev[1] - v[1]) > 0.5 or math.abs(prev[2] - v[2]) > 0.5
				or math.abs(prev[3] - v[3]) > 0.5
		else
			changed = prev == nil or (type(v) == "number" and math.abs(prev - v) > 1e-3) or (type(v) ~= "number" and prev ~= v)
		end
		if changed then
			local value = v
			if type(v) == "table" then
				value = Color3.fromRGB(math.clamp(math.round(v[1]), 0, 255), math.clamp(math.round(v[2]), 0, 255),
					math.clamp(math.round(v[3]), 0, 255))
			elseif k == "StarCount" then
				value = math.round(v)
			end
			local ok = pcall(function()
				(inst :: any)[k] = value
			end)
			if ok then
				last[k] = if type(v) == "table" then { v[1], v[2], v[3] } else v
			end
		end
	end
end

-- ── UI: the wing panel (name, next wing, BREAK), the hazard warning, the title card ─────────────
-- Laid out against the HUD's own numbers (Hud.client.luau applyLayout): the panel sits left of the
-- hotbar, level with it (above the thumbstick), never higher than the HUD's memo, hint and toast rows;
-- the warning sits centred above the hotbar, or right of it on a short phone. On a phone an open drawer
-- or card takes the centre of the screen, so both step aside while it is up.
-- check_lostfounddepot_hud_wings.luau measures both scripts together in every HUD mode.
local M, GAP = 10, 6
local MIN_TAP = 44
local PANEL_W = 196 -- stacked: name, next, then BREAK
local PANEL_W_ROW = 300 -- a short landscape phone: BREAK to the right of the text
local INK = Color3.fromRGB(245, 245, 245)
local DIM = Color3.fromRGB(190, 192, 202)
local GOLD = Color3.fromRGB(255, 214, 110)
local PANEL = Color3.fromRGB(26, 28, 34)

local gui = Instance.new("ScreenGui")
gui.Name = "DepotWings"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 1
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function textLabel(name: string, parent: Instance, font: Enum.Font, color: Color3, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.Text = ""
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

local panel = Instance.new("Frame")
panel.Name = "WingPanel"
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = root
FxClient.theme(panel, { corner = 10, stroke = Color3.fromRGB(214, 186, 120), strokeThickness = 1.5 })
local wingName = textLabel("WingName", panel, Enum.Font.GothamBlack, GOLD, 17)
wingName.TextXAlignment = Enum.TextXAlignment.Left
local wingNext = textLabel("WingNext", panel, Enum.Font.GothamMedium, DIM, 13)
wingNext.TextXAlignment = Enum.TextXAlignment.Left
local breakBtn = Instance.new("TextButton")
breakBtn.Name = "BreakButton"
breakBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
breakBtn.BorderSizePixel = 0
breakBtn.AutoButtonColor = true
breakBtn.Font = Enum.Font.GothamBlack
breakBtn.TextScaled = true
breakBtn.TextColor3 = INK
breakBtn.Text = "BREAK"
breakBtn.Parent = panel
FxClient.theme(breakBtn, { corner = 8 })
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 16
	c.Parent = breakBtn
end

local warnPanel = Instance.new("Frame")
warnPanel.Name = "WarningPanel"
warnPanel.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
warnPanel.BackgroundTransparency = 0.12
warnPanel.BorderSizePixel = 0
warnPanel.Visible = false
warnPanel.Parent = root
FxClient.theme(warnPanel, { corner = 10 })
local warnText = textLabel("WarningText", warnPanel, Enum.Font.GothamBlack, Color3.fromRGB(255, 236, 120), 20)
warnText.Position = UDim2.fromScale(0.03, 0.08)
warnText.Size = UDim2.fromScale(0.94, 0.84)

local card = textLabel("WingCard", root, Enum.Font.GothamBlack, Color3.fromRGB(255, 255, 255), 48)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.TextStrokeTransparency = 0.4
card.Visible = false
local cardSub = textLabel("WingCardSub", root, Enum.Font.GothamBold, Color3.fromRGB(235, 232, 220), 22)
cardSub.AnchorPoint = Vector2.new(0.5, 0)
cardSub.TextStrokeTransparency = 0.5
cardSub.Visible = false

local lastState: any = nil
local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then
		return designPx
	end
	return math.ceil(math.max(designPx, MIN_TAP) / layout.scale)
end

-- The HUD's centre panels: while one is up on a phone, it owns the middle of the screen.
local HUD_CENTRE = { "ManualDrawer", "UpgradesDrawer", "CodesDrawer", "SummaryCard", "NoteCard" }
local function hudCentreOpen(): boolean
	local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("DepotHud")
	local hudRoot = hud and hud:FindFirstChild("Root")
	if hudRoot == nil then
		return false
	end
	for _, name in HUD_CENTRE do
		local f = hudRoot:FindFirstChild(name)
		if f and (f :: any).Visible then
			return true
		end
	end
	return false
end

local panelWanted, warnWanted = false, false
-- The last layout's numbers in design px (the same UIScale as the HUD's root): the crowded warning is placed
-- against them every frame. warnHome is where the warning sits when nothing covers the middle of the screen.
local lay = { rootW = Responsive.REF_X, rootH = Responsive.REF_Y, padDesign = 0 }
local warnHome = { pos = UDim2.fromOffset(0, 0), size = UDim2.fromOffset(0, 0) }
local WARN_H_TALL = 52 -- two lines: the warning's size when it steps aside for a phone's drawer or card
local cardFits, cardSubFits = true, true -- where the title card can go without covering the HUD (applyLayout)
local cardUp = false -- a card is on (from showCard until it has faded): a new layout re-decides what of it shows
local function applyLayout()
	local v = camera.ViewportSize
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, topLeft = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and topLeft ~= nil then topLeft.Y else 0
	end
	local effY = math.max(1, vy - inset)
	layout = Responsive.layout(vx, effY, UserInputService.TouchEnabled, vy)
	local sc = layout.scale
	uiScale.Scale = sc
	root.Size = UDim2.fromScale(1 / sc, 1 / sc)
	local rootW = vx / sc
	local rootH = effY / sc
	local padDesign = layout.controlPad / sc

	-- The HUD's own rows, as Hud.client.luau applyLayout lays them out (the same game's code: the two move
	-- together, and check_lostfounddepot_hud_wings.luau measures them side by side on every viewport).
	-- Top: cash (left), clock (centre), toggles (right), then the memo, hint and toast rows, 90% wide.
	local toggleW, toggleH = touchSize(80), touchSize(34)
	local togglesW = 3 * toggleW + 2 * GAP
	local cashW, cashH, clockW, clockH = 150, 46, 200, 64
	local single = rootW / 2 - clockW / 2 >= M + cashW + 8 and rootW / 2 + clockW / 2 <= rootW - M - togglesW - 8
	local topBottom = if single then M + math.max(toggleH, clockH, cashH) else M + math.max(toggleH, cashH) + GAP + clockH
	local ceiling = topBottom + 80 -- nothing of ours above this line (Hud: textBottom)
	-- Bottom: the hotbar, centred in a 40% band above the touch controls.
	local carry = math.clamp((lastState and lastState.carry) or 2, 1, 5)
	local slotH = touchSize(56)
	local bandW = vx * 0.4 / sc
	local minSlotW = if layout.controlPad > 0 then math.ceil(MIN_TAP / sc) else 70
	local slotW = math.min(110, math.floor((bandW - GAP * (carry - 1)) / carry))
	local perRow = carry
	if slotW < minSlotW then
		slotW = minSlotW
		perRow = math.max(1, math.floor((bandW + GAP) / (slotW + GAP)))
	end
	local rows = math.ceil(carry / perRow)
	local cols = math.min(carry, perRow)
	local barW = cols * slotW + (cols - 1) * GAP
	local barH = rows * slotH + (rows - 1) * GAP
	local barTop = rootH - M - padDesign - barH
	local barBottom = barTop + barH
	local sideRoom = (rootW - barW) / 2 - M - GAP -- beside the hotbar, either side

	-- The wing panel sits LEFT of the hotbar, its bottom level with the hotbar's (so above the thumbstick),
	-- growing upward no higher than the HUD's text rows. Stacked (name, next, BREAK under them) when that
	-- fits; on a short landscape phone the BREAK button goes to the right of the text instead.
	local btnH = touchSize(34)
	local stackedH = 6 + 20 + 16 + 4 + btnH + 6
	local rowH = 6 + math.max(40, btnH) + 6
	local availH = barBottom - ceiling
	local panelW, panelH
	if stackedH <= availH or rowH > availH then
		panelW = math.max(0, math.min(PANEL_W, sideRoom))
		panelH = stackedH
		wingName.Position = UDim2.fromOffset(8, 6)
		wingName.Size = UDim2.fromOffset(panelW - 16, 20)
		wingNext.Position = UDim2.fromOffset(8, 26)
		wingNext.Size = UDim2.fromOffset(panelW - 16, 16)
		breakBtn.Position = UDim2.fromOffset(6, 46)
		breakBtn.Size = UDim2.fromOffset(panelW - 12, btnH)
	else
		panelW = math.max(0, math.min(PANEL_W_ROW, sideRoom))
		panelH = rowH
		local btnW = math.max(touchSize(96), math.floor(panelW * 0.4))
		local textW = panelW - btnW - 20
		local textTop = (panelH - 38) / 2
		wingName.Position = UDim2.fromOffset(8, textTop)
		wingName.Size = UDim2.fromOffset(textW, 20)
		wingNext.Position = UDim2.fromOffset(8, textTop + 21)
		wingNext.Size = UDim2.fromOffset(textW, 16)
		breakBtn.Position = UDim2.fromOffset(panelW - btnW - 6, 6)
		breakBtn.Size = UDim2.fromOffset(btnW, panelH - 12)
	end
	panel.Position = UDim2.fromOffset(M, barBottom - panelH)
	panel.Size = UDim2.fromOffset(panelW, panelH)

	-- The warning: centred just above the hotbar when there is room under the text rows; otherwise to the
	-- RIGHT of the hotbar, in its band (it is not a button, so the jump button's corner does not matter).
	local warnH = 34
	local centreW = math.min(440, rootW - 2 * (M + panelW + GAP))
	if barTop - GAP - warnH >= ceiling and centreW >= 240 then
		warnHome.pos = UDim2.fromOffset((rootW - centreW) / 2, barTop - GAP - warnH)
		warnHome.size = UDim2.fromOffset(centreW, warnH)
	else
		local w = math.max(0, math.min(440, sideRoom))
		warnHome.pos = UDim2.fromOffset((rootW + barW) / 2 + GAP, barTop + (barH - warnH) / 2)
		warnHome.size = UDim2.fromOffset(w, warnH)
	end
	warnPanel.Position = warnHome.pos
	warnPanel.Size = warnHome.size
	lay.rootW, lay.rootH, lay.padDesign = rootW, rootH, padDesign

	-- The title card (REVIEW-2 finding 5: at 40% of the height it sat on the hotbar on 800x360, 844x390 and
	-- 640x300 phones, covering the slot labels that say what E drops). It never covers the HUD's text rows or
	-- the hotbar: both lines in the free band between them when they fit; the title alone there when only it
	-- fits; else both lines beside the hotbar, on its right (the wing panel is on its left, and no hazard
	-- launches while a card is up, so the warning is never there with it). Nowhere clear: not shown at all
	-- (the wing panel names the wing anyway). check_lostfounddepot_hud_wings.luau measures it on every viewport.
	local cardW = math.min(720, rootW - 2 * M)
	local titleH, subH = 64, 28
	local bandTop, bandBottom = ceiling + 4, barTop - GAP
	local band = bandBottom - bandTop
	local rightW = math.min(420, sideRoom)
	cardFits = true
	if band >= titleH + 4 + subH then
		local cy = math.clamp(rootH * 0.4, bandTop + titleH / 2, bandBottom - subH - 4 - titleH / 2)
		card.Position = UDim2.fromOffset(rootW / 2, cy)
		card.Size = UDim2.fromOffset(cardW, titleH)
		cardSub.Position = UDim2.fromOffset(rootW / 2, cy + titleH / 2 + 4)
		cardSub.Size = UDim2.fromOffset(cardW, subH)
		cardSubFits = true
	elseif band >= 40 then
		local h = math.min(titleH, band)
		card.Position = UDim2.fromOffset(rootW / 2, bandTop + band / 2)
		card.Size = UDim2.fromOffset(cardW, h)
		cardSubFits = false
	elseif rightW >= 200 then
		local x = (rootW + barW) / 2 + GAP + rightW / 2
		local h1 = math.floor(barH * 0.62)
		card.Position = UDim2.fromOffset(x, barTop + h1 / 2)
		card.Size = UDim2.fromOffset(rightW, h1)
		cardSub.Position = UDim2.fromOffset(x, barTop + h1 + 2)
		cardSub.Size = UDim2.fromOffset(rightW, math.max(0, barH - h1 - 2))
		cardSubFits = true
	else
		cardFits = false
	end
	if cardUp then
		card.Visible = cardFits
		cardSub.Visible = cardFits and cardSubFits
	end
end

-- The HUD's open centre panel reaching lowest down the screen, as a rect in design px (the HUD lays its
-- panels out with fromOffset under the same UIScale as ours), or nil.
local function openCentreRect(): { x: number, y: number, w: number, h: number }?
	local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("DepotHud")
	local hudRoot = hud and hud:FindFirstChild("Root")
	if hudRoot == nil then
		return nil
	end
	local best = nil
	for _, name in HUD_CENTRE do
		local f = hudRoot:FindFirstChild(name) :: any
		if f and f.Visible then
			local r = {
				x = f.Position.X.Offset + f.Position.X.Scale * lay.rootW,
				y = f.Position.Y.Offset + f.Position.Y.Scale * lay.rootH,
				w = f.Size.X.Offset + f.Size.X.Scale * lay.rootW,
				h = f.Size.Y.Offset + f.Size.Y.Scale * lay.rootH,
			}
			if best == nil or r.y + r.h > best.y + best.h then best = r end
		end
	end
	return best
end

-- On a phone an open drawer or card owns the middle of the screen. A hazard already flying when it opened
-- keeps its warning ON SCREEN (REVIEW-2 finding 2: it used to be hidden, and the marker sat behind the
-- drawer): two lines just below the panel, where the hidden hotbar sits and, on a touch screen, between the
-- thumbstick and the jump button; else beside the panel. New hazards wait while it is up (Wings.mayLaunch).
local function placeWarningAside(): boolean
	local r = openCentreRect()
	if r == nil then
		return false
	end
	local rootW, rootH = lay.rootW, lay.rootH
	local left, right = M, rootW - M
	if layout.controlPad > 0 then
		left, right = rootW * 0.35 + GAP, rootW * 0.75 - GAP
	end
	local w = math.min(440, right - left)
	local top = r.y + r.h + GAP
	if w >= 200 and top + WARN_H_TALL <= rootH - M then
		warnPanel.Position = UDim2.fromOffset(left + (right - left - w) / 2, top)
		warnPanel.Size = UDim2.fromOffset(w, WARN_H_TALL)
		return true
	end
	local leftW = r.x - GAP - M
	local rightW = rootW - M - (r.x + r.w + GAP)
	local sideW = math.min(300, math.max(leftW, rightW))
	if sideW >= 150 then
		local x = if leftW >= rightW then r.x - GAP - sideW else r.x + r.w + GAP
		warnPanel.Position = UDim2.fromOffset(x, r.y)
		warnPanel.Size = UDim2.fromOffset(sideW, WARN_H_TALL)
		return true
	end
	return false
end

local function refreshVisibility()
	local crowded = layout.compact and hudCentreOpen()
	local loaded = lastState ~= nil and lastState.loaded == true
	panel.Visible = panelWanted and loaded and not crowded
	local shown = false
	if warnWanted then
		if crowded then
			shown = placeWarningAside()
		else
			if warnPanel.Position ~= warnHome.pos then warnPanel.Position = warnHome.pos end
			if warnPanel.Size ~= warnHome.size then warnPanel.Size = warnHome.size end
			shown = true
		end
	end
	warnPanel.Visible = shown
end

applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

local cardToken = 0
local function showCard(title: string, sub: string, celebrate: boolean)
	cardToken += 1
	local mine = cardToken
	card.Text = title
	cardSub.Text = sub
	card.TextTransparency = 0
	cardSub.TextTransparency = 0
	cardUp = true
	card.Visible = cardFits
	cardSub.Visible = cardFits and cardSubFits
	if celebrate then
		FxClient.flash(Color3.fromRGB(255, 255, 255), 0.45, 0.9)
		FxClient.fovPunch(8, 0.12, 0.6)
	end
	task.delay(if celebrate then 4.5 else 3.5, function()
		if cardToken ~= mine then return end
		local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tw = TweenService:Create(card, info, { TextTransparency = 1 })
		TweenService:Create(cardSub, info, { TextTransparency = 1 }):Play()
		tw.Completed:Connect(function()
			if cardToken ~= mine then return end
			cardUp = false
			card.Visible = false
			cardSub.Visible = false
		end)
		tw:Play()
	end)
end

-- ── state ─────────────────────────────────────────────────────────────────────
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil

local now = 0
local weights: { [number]: number } = {}
local current: { [string]: any }? = nil
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local pendingCard: number? = nil -- a wing reached while the HUD's centre was busy: shown when it clears
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local brk = Wings.newBreak()
local sat = false
local knockUntil: number? = nil
local bayOx: number? = nil
local rect: any = nil
local boxes: { any } = {}
local FLOOR_Y = 0 -- every bay's floor top (Main.server.luau builds the floor with its top at y = 0)
local ROOT_ABOVE_FLOOR = 3 -- a standing character's root part

local pieceIds: { [string]: boolean } = {}
for _, b in bands do
	for _, id in b.pieces or {} do
		pieceIds[id] = true
	end
end
local spaceIdx = EnvBands.indexOf(bands, Env.SpaceBandId)

local function vec(v: Vector3)
	return { x = v.X, y = v.Y, z = v.Z }
end

local seenVersion = 0
local function pollState()
	local st, version = StateCache.get()
	if version == seenVersion or type(st) ~= "table" then
		return
	end
	seenVersion = version
	local carryBefore = lastState and lastState.carry
	lastState = st
	if st.carry ~= carryBefore then
		applyLayout()
	end
end
pollState()

local function unsit()
	if sat and hum then
		pcall(function() (hum :: Humanoid).Sit = false end)
	end
	sat = false
	breakFocus.Enabled = false
end

local function sitDown()
	sat = true
	breakFocus.Enabled = true
	if hum then
		pcall(function() (hum :: Humanoid).Sit = true end)
	end
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	rest = Rest.new()
	brk = Wings.newBreak()
	sat = false
	breakFocus.Enabled = false
	knockUntil = nil
	if scheduler.active then
		art:hideHazard(scheduler.active.kind)
		scheduler.active = nil
	end
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local function shiftState(): string?
	return lastState and lastState.shift and lastState.shift.state
end

local function isGrounded(): boolean
	if hum == nil then return false end
	local fm = (hum :: any).FloorMaterial
	return fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
end

breakBtn.Activated:Connect(function()
	if not restOn then return end
	local result = Wings.pressBreak(brk, rest, Rest, RestCfg, shiftState(),
		{ moving = false, grounded = isGrounded() or sat, threat = scheduler.active ~= nil })
	if result == "resting" then
		sitDown()
	elseif result == "stopped" or result == "cancelled" then
		unsit()
	end
end)

-- The wing panel: name, what comes next, and the BREAK button. Written at the END of the frame, after the
-- break and hazards have moved, so it never shows last frame's state (it also runs while a character
-- respawns).
local function updatePanel(bandIdx: number, named: number, state: string?)
	local resting = restOn and Rest.isResting(rest)
	local nextIdx = if bandIdx < #bands then bandIdx + 1 else nil
	local nameText = bands[bandIdx].name
	local nextText
	if resting then
		nextText = if rest.source == "idle" then "Idle - hazards leave you alone" else "On break - the clock waits for your first pickup"
	elseif brk.afterShift then
		nextText = "Break booked for the end of this shift"
	elseif nextIdx then
		local left = bands[nextIdx].from - named
		nextText = string.format("Next: %s in %d shift%s", bands[nextIdx].name, left, if left == 1 then "" else "s")
	else
		nextText = "The farthest wing there is"
	end
	if wingName.Text ~= nameText then wingName.Text = nameText end
	if wingNext.Text ~= nextText then wingNext.Text = nextText end
	local btnText = if resting then "BACK TO WORK" elseif rest.pending then "BREAK..." elseif brk.afterShift then "BREAK BOOKED"
		elseif Wings.clockRunning(state) then "BREAK AFTER SHIFT" else "TAKE A BREAK"
	if breakBtn.Text ~= btnText then breakBtn.Text = btnText end
	panelWanted = true
end

-- ── the frame ─────────────────────────────────────────────────────────────────
-- Every step of a frame runs on its own guard (REVIEW-2 finding 4). A broken COSMETIC step (a Roblox-only
-- error the headless checks cannot raise, say the first time a wing's scenery is built mid-shift) costs only
-- that step: the stumble's release runs FIRST, and the break, the hazards and the panel keep working. Each
-- step warns once, never every frame.
local warned: { [string]: boolean } = {}
local function guard(name: string, fn: (...any) -> (), ...: any): boolean
	local ok, err = pcall(fn, ...)
	if not ok and not warned[name] then
		warned[name] = true
		warn("[DepotWings] " .. name .. " failed: " .. tostring(err))
	end
	return ok
end

-- What every step reads this frame (worked out by `readFrame`, which only reads).
local fr = { dt = 0, camCF = CFrame.new(), camPos = Vector3.zero, p = 0, named = 0, bandIdx = 1, state = nil :: string? }

-- the stumble wears off: first thing every frame, whatever fails after it
local function releaseStumble()
	if knockUntil and now >= knockUntil then
		knockUntil = nil
		if hum then
			pcall(function() (hum :: Humanoid).PlatformStand = false end)
		end
	end
end

local function readFrame()
	pollState()
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	-- where the player's bay is: from their own State (bayName) and the bay's public spawn pad
	if lastState and lastState.bayName then
		local bays = workspace:FindFirstChild("Bays")
		local bay = bays and bays:FindFirstChild(lastState.bayName)
		local pad = bay and bay:FindFirstChild("BayPad")
		if pad and (pad :: BasePart).Position.X ~= bayOx then
			bayOx = (pad :: BasePart).Position.X
			rect = Wings.bayRect(Config, bayOx :: number)
			boxes = Wings.obstacles(Config, Layout, bayOx :: number, Hz.ObstacleMargin)
			guard("bay", function() art:setBay(bayOx) end)
		end
	end
	fr.camCF = camera.CFrame
	fr.camPos = fr.camCF.Position
	-- continuous progress blends; whole completed shifts NAME the wing
	fr.p = Wings.progress(lastState)
	fr.named = Wings.completedShifts(lastState)
	fr.bandIdx = EnvBands.indexAt(bands, fr.named)
	fr.state = shiftState()
	-- The scenery waits for the loaded profile and then fades in from nothing to the player's own wing: a
	-- returning veteran never sees the first wing's roof flash up at join. (The lighting glides from the
	-- server's preset, which is the first wing's, so it needs no such wait.)
	local loaded = lastState ~= nil and lastState.loaded == true
	local targetW = if loaded then EnvBands.weights(bands, fr.p) else {}
	for i = 1, #bands do
		weights[i] = EnvBands.approach(weights[i] or 0, targetW[i] or 0, fr.dt, Env.HalfLife)
	end
end

-- lighting at LightingHz
local function stepLighting(dt: number)
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		local target = {}
		for _, g in GROUPS do
			target[g] = EnvBands.sample(bands, fr.p, g)
		end
		if current == nil then
			-- start from the server's preset (wing 1) and glide to where this player's career is
			current = {}
			for _, g in GROUPS do
				(current :: any)[g] = EnvBands.sample(bands, 0, g)
			end
		end
		for _, g in GROUPS do
			(current :: any)[g] = EnvBands.approachTable((current :: any)[g], target[g], step, Env.HalfLife)
			writeGroup(targets[g], (current :: any)[g])
		end
	end
end

-- scenery, critters, weather: from the two strongest wings only (normal play never blends more; a flurry of
-- career jumps cannot stack a third wing's roofs and landmarks onto the budget). Each is its own step.
local function sceneryWants()
	local pieceW: { [string]: number } = {}
	local critters: { [string]: number } = {}
	local weather: { [string]: number } = {}
	local shownW = Wings.keepStrongest(weights, 2)
	for i, b in bands do
		local w = shownW[i] or 0
		if w > 0.001 then
			for _, id in b.pieces or {} do
				pieceW[id] = math.min(1, (pieceW[id] or 0) + w)
			end
			for _, a in b.ambient or {} do
				critters[a.kind] = (critters[a.kind] or 0) + a.count * w
			end
			if b.weather then
				weather[b.weather.kind] = (weather[b.weather.kind] or 0) + b.weather.rate * w
			end
		end
	end
	for kind, n in critters do
		critters[kind] = math.floor(n + 0.5)
	end
	return pieceW, critters, weather
end

local function stepPieces(pieceW: { [string]: number })
	-- the overhead pieces fade with the camera's height: zoomed out above the walls, nothing hangs between the
	-- camera and the tags (Wings.overheadFade)
	local overhead = Wings.overheadFade(fr.camPos.Y, Env.OverheadFade)
	for id in pieceIds do
		local w = pieceW[id] or 0
		if WingArt.isOverhead(id) then w *= overhead end
		art:updatePiece(id, w, now)
	end
	if bayOx then
		art:updatePiece("wingSigns", 1, now)
		art:setSignText(bands[fr.bandIdx].name)
	end
end

-- a new wing is announced once, when the HUD's centre is clear (the summary card comes first); the first wing
-- seen this session is announced quietly (a returning player is not congratulated twice)
local function stepCards()
	if lastState and lastState.loaded == true then
		if announcer.highest == 0 then
			EnvBands.announce(announcer, fr.bandIdx)
			pendingCard = -fr.bandIdx
		elseif EnvBands.announce(announcer, fr.bandIdx) then
			pendingCard = fr.bandIdx
		end
	end
	if pendingCard and not hudCentreOpen() then
		local idx = math.abs(pendingCard)
		local quiet = pendingCard < 0
		pendingCard = nil
		local b = bands[idx]
		if b.celebrate and not quiet then
			showCard("YOU MADE IT TO SPACE!", b.name .. " - " .. b.sub, true)
		else
			showCard((if quiet then "" else "NOW POSTED: ") .. b.name, b.sub, false)
		end
	end
end

local function stepBreak(dt: number, moving: boolean, supported: boolean)
	if not restOn then return end
	local ev = Wings.updateBreak(brk, rest, Rest, RestCfg, dt, fr.state,
		{ moving = moving, grounded = supported, threat = scheduler.active ~= nil })
	if ev == "started" and rest.source == "manual" then
		sitDown()
	elseif ev == "woke" or ev == "dropped" or ev == "expired" or ev == "clock" then
		unsit()
	end
	if sat and not Rest.isResting(rest) then unsit() end
end

-- hazards: only on this player's own sorting floor, only while the clock runs and nobody rests
local function stepHazards(dt: number, grounded: boolean)
	local rootPart = hrp :: BasePart
	local humanoid = hum :: Humanoid
	local camCF, camPos = fr.camCF, fr.camPos
	local look = camCF.LookVector
	local yaw = math.atan2(look.X, look.Z)
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	local pos = vec(rootPart.Position)
	local aim = { x = pos.x, y = FLOOR_Y + ROOT_ABOVE_FLOOR, z = pos.z }
	local onFloor = Wings.inRect(rect, pos, Hz.FloorMargin)
	-- room for a lane in view is only worked out on a frame when a hazard is due
	local due = scheduler.active == nil and scheduler.clock + dt >= scheduler.nextAt
	local roomy = onFloor and (not due or Wings.room(rect, pos, yaw, Hz.SpreadDegrees, Hz.FloorMargin, boxes) >= Hz.MinLaneStuds)
	-- a due hazard waits (stays due) while a phone's drawer or card, or our title card, covers the screen
	local covered = (layout.compact and hudCentreOpen()) or cardUp
	local before = if scheduler.active then scheduler.active.t else nil
	local ev = Hazards.step(scheduler, Hz, dt, {
		resting = not Wings.hazardsMayRun(rest, Rest, fr.state),
		grounded = grounded and Wings.mayLaunch({ onFloor = onFloor, roomy = roomy, covered = covered }),
		kinds = bands[fr.bandIdx].hazards or {},
		aim = if onFloor then aim else nil,
		yaw = yaw,
		pitch = pitch,
	}, rand)
	if ev and ev.type == "spawn" then
		local plan = ev.plan
		if Hz.Kinds[plan.kind].ground then Wings.groundLane(plan) end
		if Wings.clipLane(plan, rect, Hz.FloorMargin, boxes) < Hz.MinLaneStuds then
			Wings.withdraw(scheduler) -- a crate corner in the way: stays due, tried again with room
		end
		before = nil
	elseif ev and ev.type == "done" then
		art:hideHazard(ev.plan.kind)
	end
	local plan = scheduler.active
	if plan == nil then return end
	Wings.lockNear(plan, pos, Hz.PlayerRadius, Hz.LockExtraStuds, Hz.MinReactSeconds)
	Wings.noteLock(plan)
	Wings.endAtWall(plan, rect, boxes)
	local hp = Hazards.positionAt(plan, math.min(plan.t, plan.duration))
	local zone = Hazards.zone(plan, Hz.PlayerRadius)
	-- the ring (and the warning) stay up exactly as long as a hit inside the ring is possible
	local ringLive = Wings.zoneLive(plan, zone, Hz.PlayerRadius)
	-- drawn BEFORE the hit test: a hazard that cannot be drawn (showHazard failing) cannot knock anyone
	art:showHazard(plan, hp, now, zone, FLOOR_Y, ringLive)
	-- the knock: the ring rule, and only after MinReactSeconds inside the red ring and MinWarnSeconds of
	-- warning, whatever the player does (Wings.checkHit; REVIEW-2 finding 1)
	if Wings.checkHit(Hazards, plan, before or 0, math.min(plan.t, plan.duration), pos, Hz.PlayerRadius, Hz.MinWarnSeconds, Hz.MinReactSeconds) then
		plan.hit = true
		local kv = Hazards.knockVelocity(Hz, plan, pos)
		-- the release time first: whatever fails after this line, the stumble wears off (releaseStumble)
		knockUntil = now + Hz.KnockSeconds
		pcall(function() humanoid.PlatformStand = true end)
		pcall(function() rootPart.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z) end)
		Rest.stop(rest)
		unsit()
		FxClient.shake(0.3, 0.6)
		FxClient.flash(Color3.fromRGB(255, 255, 255), 0.25, 0.3)
	end
	if ringLive and not plan.hit then
		local b = Hazards.bearing(vec(camPos), vec(look), hp)
		local label = Hz.Kinds[plan.kind].label
		local arrowL = if b == "left" then "<< " elseif b == "behind" then "v " elseif b == "ahead" then "^ " else ""
		local arrowR = if b == "right" then " >>" elseif b == "behind" then " v" elseif b == "ahead" then " ^" else ""
		local text = if plan.locked then arrowL .. "MOVE! " .. label .. arrowR else arrowL .. label .. " INCOMING" .. arrowR
		if warnText.Text ~= text then warnText.Text = text end
		warnWanted = true
	end
end

local function frame(dt: number)
	now += dt
	fr.dt = dt
	guard("stumble", releaseStumble)
	if not guard("read", readFrame) then
		return
	end
	guard("lighting", stepLighting, dt)
	local okWants, pieceW, critters, weather = pcall(sceneryWants)
	if okWants then
		guard("pieces", stepPieces, pieceW)
		guard("critters", function() art:updateCritters(critters, fr.camPos, dt, now) end)
		guard("weather", function() art:updateWeather(weather) end)
	end

	-- no hazard outlives the shift: the moment the clock stops, one still in the air is taken away
	local gone = Wings.endWithShift(scheduler, fr.state)
	if gone then
		guard("hide", function() art:hideHazard(gone.kind) end)
	end
	guard("cards", stepCards)

	warnWanted = false
	if hrp ~= nil and hum ~= nil then
		local rootPart = hrp :: BasePart
		local humanoid = hum :: Humanoid
		local grounded = isGrounded()
		-- a seated Humanoid may report FloorMaterial = Air: a player we sat down is supported unless falling
		local supported = grounded
		if sat and not grounded and knockUntil == nil then
			supported = math.abs(rootPart.AssemblyLinearVelocity.Y) < 2
		end
		local md = (humanoid :: any).MoveDirection
		local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true
		guard("break", stepBreak, dt, moving, supported)
		if hazardsOn and rect then
			guard("hazards", stepHazards, dt, grounded)
		end
	end
	-- the wing panel is written at the END of the frame, after the break and hazards have moved, so it never
	-- shows last frame's state (it also runs while a character respawns)
	guard("panel", function()
		updatePanel(fr.bandIdx, fr.named, fr.state)
		refreshVisibility()
	end)
end

RunService.RenderStepped:Connect(function(dt)
	-- every step guards itself; this outer pcall only catches a bug in the guards themselves
	local ok, err = pcall(frame, dt)
	if not ok and not warned.frame then
		warned.frame = true
		warn("[DepotWings] frame error: " .. tostring(err))
	end
end)
