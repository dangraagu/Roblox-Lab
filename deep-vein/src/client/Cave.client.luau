-- DEEP VEIN ⛏️ — the strata you dig through. Client only (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads how deep the local character stands in its own shaft (Strata.depthAt / layerAt) — the
--     game's real progress value, never a timer;
--   * blends the environment bands in Config.Env (EnvBands): lighting, atmosphere, post-fx, the
--     surface headframe and meadow, the glowing core floor, wall decorations, critters and weather,
--     smoothed so nothing ever hard-cuts, even on an elevator ride;
--   * runs the rare hazards (Hazards: a rock working loose overhead, a steam vent underfoot) and the
--     rest rules (Rest), and knocks the local character down on a hit. Nothing is lost.
--
-- Why all of it is client-side, and why that is safe:
--   * it is cosmetic, or it only ever harms the local player, whose character physics the client
--     already owns. The server does not know hazards or rest exist and trusts nothing from here: this
--     script never fires a remote, and digging is still the server's ClickDetector on the server's
--     rock. A knock is capped (Hazards.MAX_KNOCK_LIFT) and pushes sideways;
--   * everything built here is created by the client in its own folder and never replicates. It reads
--     only the local character, the local camera, Config, the local player's own leaderstats, and the
--     Parts of its own shaft that the server already replicated to it — never the cave generator, so
--     no decoration can reveal a cell the player has not dug to.
-- The rock itself changes colour and material with depth too; that is the server's (Strata.rockLook),
-- because a Part's Color is replicated with it anyway. Measured budgets, the band table, the rest
-- rules and the shot list: EYECANDY.md. Headless checks: robloxemu/check_deepvein_cave*.luau.

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
local Strata = require(ReplicatedStorage:WaitForChild("Strata"))
local Mine = require(ReplicatedStorage:WaitForChild("Mine"))
local CaveArt = require(ReplicatedStorage:WaitForChild("CaveArt"))
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
local S = Config.Mine.CellSize

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[DeepVeinCave] Config.Env.Bands is invalid (" .. tostring(err) .. "); the cave stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[DeepVeinCave] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[DeepVeinCave] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- ── local world + lighting rig ────────────────────────────────────────────────
local folder = Instance.new("Folder")
folder.Name = "DeepVeinLocalCave"
folder.Parent = workspace

local art = CaveArt.new(folder, rand, Config, EnvBands, Strata, Mine)

-- Reuse the server's Fx.applyLighting objects by name so the client takes over from exactly the
-- values the server set, instead of stacking a second Atmosphere on top.
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
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "sunRays" }

-- Rest softens the view: the server's depth of field steps aside for a stronger one while resting.
local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "CaveRestFocus"
restFocus.FarIntensity = 0.3
restFocus.FocusDistance = 10
restFocus.InFocusRadius = 14
restFocus.NearIntensity = 0
restFocus.Enabled = false
restFocus.Parent = Lighting
local function setRestFocus(on: boolean)
	restFocus.Enabled = on
	local server = Lighting:FindFirstChild("FxDoF")
	if server and server:IsA("DepthOfFieldEffect") then
		(server :: any).Enabled = not on
	end
end

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

-- ── UI: band chip + rest button + warning + title card ─────────────────────────
-- Sits directly under the HUD's readout, hint and toast (Hud.client.luau's own numbers), between its
-- side panels. check_deepvein_cave_hud.luau measures that it fits every viewport and never lands on a
-- HUD panel or under Roblox's touch controls.
local MARGIN, GAP = Responsive.MARGIN, 8
local HUD_ROW_TOP_DESKTOP = 130 -- below the toast (100 + 24) with a small gap
local HUD_TOGGLE_H = 28
local HUD_SHOP_W = 258
local ROW_W, ROW_H = 440, 34
local REST_W = 104
local MIN_TAP = 44

local gui = Instance.new("ScreenGui")
gui.Name = "DeepVeinCave"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 2
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local chip = Instance.new("TextLabel")
chip.Name = "BandChip"
chip.BackgroundColor3 = Color3.fromRGB(22, 20, 28)
chip.BackgroundTransparency = 0.2
chip.Font = Enum.Font.GothamBold
chip.TextColor3 = Color3.fromRGB(240, 236, 226)
chip.TextScaled = true
chip.Text = "🌱 Topsoil & Roots"
chip.Parent = root
corner(chip, 10)
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 16
	c.Parent = chip
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = chip
end

local restBtn = Instance.new("TextButton")
restBtn.Name = "RestButton"
restBtn.BackgroundColor3 = Color3.fromRGB(150, 104, 52)
restBtn.Font = Enum.Font.GothamBlack
restBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restBtn.TextScaled = true
restBtn.Text = "⛺ Rest"
restBtn.AutoButtonColor = true
restBtn.Parent = root
corner(restBtn, 10)
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 16
	c.Parent = restBtn
end

local warning = Instance.new("TextLabel")
warning.Name = "HazardWarning"
warning.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
warning.BackgroundTransparency = 0.15
warning.Font = Enum.Font.GothamBlack
warning.TextColor3 = Color3.fromRGB(255, 236, 120)
warning.TextScaled = true
warning.Text = ""
warning.Visible = false
warning.Parent = root
corner(warning, 10)

local card = Instance.new("TextLabel")
card.Name = "BandCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.BackgroundTransparency = 1
card.Font = Enum.Font.GothamBlack
card.TextColor3 = Color3.fromRGB(255, 255, 255)
card.TextStrokeTransparency = 0.4
card.TextScaled = true
card.Text = ""
card.Visible = false
card.Parent = root
local cardSub = Instance.new("TextLabel")
cardSub.Name = "BandCardSub"
cardSub.AnchorPoint = Vector2.new(0.5, 0)
cardSub.BackgroundTransparency = 1
cardSub.Font = Enum.Font.GothamBold
cardSub.TextColor3 = Color3.fromRGB(236, 228, 214)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root

local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)

-- The row's metrics from the last layout, in design px, and the free span it was last placed in.
local row: any = nil
local rowPlacedFor = ""
local chipFits = true

-- Place the chip, the Rest button and the warning banner inside the horizontal span [fl, fr]. With no
-- HUD drawer open that span is the row's own (centred between the HUD's side panels); with a phone
-- drawer open it is the side the drawer leaves free. Review 2026-09-24, finding 3: the row used to
-- HIDE while a drawer was open, so a phone player shopping underground never saw the hazard banner and
-- could not press Rest. With no drawer open the placement is exactly the one before that review.
local WARN_MIN_W = 200
local function placeRow(fl: number, fr: number)
	local m = row
	if m == nil then return end
	local key = string.format("%.2f %.2f", fl, fr)
	if key == rowPlacedFor then return end
	rowPlacedFor = key
	local rowTop, rowH, btnW, warnH = m.rowTop, m.rowH, m.btnW, m.warnH
	local warnTop = rowTop + rowH + GAP
	if m.split then
		-- left of the elevator pair and right of it, each clipped to the free span
		local lL, lR = math.max(MARGIN, fl), math.min(m.elevLeft - GAP, fr)
		local rL, rR = math.max(m.elevRight + GAP, fl), math.min(m.rootW - MARGIN, fr)
		local leftW, rightW = math.max(0, lR - lL), math.max(0, rR - rL)
		local chipW
		if rightW >= btnW then
			restBtn.Position = UDim2.fromOffset(rR - btnW, rowTop)
			chipW = leftW
		else
			restBtn.Position = UDim2.fromOffset(lR - btnW, rowTop)
			chipW = leftW - btnW - GAP
		end
		restBtn.Size = UDim2.fromOffset(btnW, rowH)
		chipFits = chipW >= 60 or (fl <= MARGIN and fr >= m.rootW - MARGIN)
		chip.Position = UDim2.fromOffset(lL, rowTop)
		chip.Size = UDim2.fromOffset(math.max(60, chipW), rowH)
		-- the banner goes under the chip, unless a drawer squeezed that side and the other has more room
		if leftW >= WARN_MIN_W or leftW >= rightW then
			warning.Position = UDim2.fromOffset(lL, warnTop)
			warning.Size = UDim2.fromOffset(math.max(60, leftW), warnH)
		else
			warning.Position = UDim2.fromOffset(rL, warnTop)
			warning.Size = UDim2.fromOffset(rightW, warnH)
		end
	else
		local width = fr - fl
		local rowW = math.max(math.min(ROW_W, width), btnW + 60)
		local left = fl + (width - rowW) / 2
		restBtn.Position = UDim2.fromOffset(left + rowW - btnW, rowTop)
		restBtn.Size = UDim2.fromOffset(btnW, rowH)
		chipFits = true
		chip.Position = UDim2.fromOffset(left, rowTop)
		chip.Size = UDim2.fromOffset(rowW - btnW - GAP, rowH)
		warning.Position = UDim2.fromOffset(left, warnTop)
		warning.Size = UDim2.fromOffset(rowW, warnH)
	end
end

-- The span the row may use now: its own, or on a phone with a HUD drawer (the shop on the left, the
-- top-10 on the right) open, the side that drawer leaves free. Read off the drawer's own UDim2s, which
-- Hud.client sets in the same design px as this root.
local function rowSpan(): (number, number)
	local m = row
	if m == nil then return 0, 0 end
	if not layout.compact then return m.baseL, m.baseR end
	local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("DeepVeinHud")
	local hudRoot = hud and hud:FindFirstChild("Root")
	if hudRoot then
		for _, name in { "ShopPanel", "Board" } do
			local p = hudRoot:FindFirstChild(name)
			if p and (p :: any).Visible then
				local size, pos, anchor = (p :: any).Size, (p :: any).Position, (p :: any).AnchorPoint
				local w = size.X.Offset + size.X.Scale * m.rootW
				local x = pos.X.Scale * m.rootW + pos.X.Offset - anchor.X * w
				if x + w / 2 < m.rootW / 2 then
					return math.max(m.baseL, x + w + GAP), m.baseR
				end
				return m.baseL, math.min(m.baseR, x - GAP)
			end
		end
	end
	return m.baseL, m.baseR
end
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then return designPx end
	local wanted = math.max(designPx, MIN_TAP)
	local n = math.ceil(wanted / layout.scale)
	if n * layout.scale <= wanted then n += 1 end
	return n
end

local function applyLayout()
	local v = camera.ViewportSize
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, topLeft = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and topLeft ~= nil then topLeft.Y else 0
	end
	local vyDraw = math.max(1, vy - inset)
	layout = Responsive.layout(vx, vyDraw, UserInputService.TouchEnabled, vy)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
	local rootW = vx / layout.scale
	local rootH = vyDraw / layout.scale

	local rowTop, baseL, baseR
	if layout.compact then
		-- Hud.client: toggles and readout on one row, then the hint (+6) and the toast (+26); the
		-- drawers open below the toast (+28), which is where this row goes. While a drawer is open the
		-- row moves into the side it leaves free (rowSpan, frame()).
		local toggleH = touchSize(HUD_TOGGLE_H)
		rowTop = 10 + toggleH + 6 + 26 + 28
		baseL, baseR = MARGIN, rootW - MARGIN
	else
		rowTop = HUD_ROW_TOP_DESKTOP
		local sideW = Responsive.sideWidth(HUD_SHOP_W, vx, layout)
		baseL, baseR = MARGIN + sideW + GAP, rootW - (MARGIN + sideW + GAP)
	end
	local btnW, rowH = touchSize(REST_W), touchSize(ROW_H)
	local warnH = math.max(30, math.floor(rowH * 0.8))

	-- On a short landscape phone the HUD's elevator pair (bottom centre, lifted over the touch
	-- controls) reaches up into this row. Hud.client's own numbers: 2 buttons of min(160, (w-40)/2),
	-- 8 apart, bottom at 14 + the control pad, height touchSize(44). When they would meet, the row
	-- splits: chip and warning to the LEFT of the elevator, the button to the RIGHT of it.
	-- check_deepvein_cave.luau section 9 measures the result at all ten viewports, drawers open and shut.
	local padDesign = layout.controlPad / layout.scale
	local elevW = math.min(160, math.floor((rootW - 40) / 2))
	local elevTop = rootH - 14 - padDesign - touchSize(44)
	local elevLeft = (rootW - (2 * elevW + 8)) / 2
	row = {
		rootW = rootW, rowTop = rowTop, rowH = rowH, btnW = btnW, warnH = warnH, baseL = baseL, baseR = baseR,
		split = layout.compact and rowTop + rowH + GAP + warnH > elevTop - GAP,
		elevLeft = elevLeft, elevRight = elevLeft + 2 * elevW + 8,
	}
	rowPlacedFor = ""
	placeRow(rowSpan())

	local cardW = math.min(760, rootW - 2 * MARGIN)
	card.Position = UDim2.fromOffset(rootW / 2, rootH * 0.4)
	card.Size = UDim2.fromOffset(cardW, math.min(70, rootH * 0.14))
	cardSub.Position = UDim2.fromOffset(rootW / 2, rootH * 0.4 + math.min(70, rootH * 0.14) / 2 + 4)
	cardSub.Size = UDim2.fromOffset(cardW, math.min(30, rootH * 0.07))
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
	card.Visible = true
	cardSub.Visible = true
	if celebrate then
		FxClient.flash(Color3.fromRGB(255, 170, 90), 0.45, 0.9)
		FxClient.fovPunch(8, 0.12, 0.6)
	end
	task.delay(if celebrate then 4.5 else 3, function()
		if cardToken ~= mine then return end
		local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tw = TweenService:Create(card, info, { TextTransparency = 1 })
		TweenService:Create(cardSub, info, { TextTransparency = 1 }):Play()
		tw.Completed:Connect(function()
			if cardToken ~= mine then return end
			card.Visible = false
			cardSub.Visible = false
		end)
		tw:Play()
	end)
end

-- ── the player's own shaft, as the server replicated it ──────────────────────
-- The client finds its shaft by its own SELL pad, reads the shaft's origin and floor off the bedrock
-- floor slab, and keeps the set of cell keys that have a rock Part: the reveal builds every solid cell
-- next to an opened one, so a cell beside the miner with no Part is open air — somewhere to step out
-- of a hazard's shadow — known from what is already on this client's screen.
local myShaft: Instance? = nil
local shaftConns: { RBXScriptConnection } = {}
local solid: { [string]: boolean } = {}
local shaftOrigin: Vector3? = nil
local floorTop: number? = nil
local lastShaftSearch = -math.huge

local function unbindShaft()
	for _, c in shaftConns do c:Disconnect() end
	shaftConns = {}
	myShaft = nil
	solid = {}
	shaftOrigin = nil
	floorTop = nil
end

local function trackChild(ch: Instance, present: boolean)
	local k = ch:GetAttribute("CellKey")
	if type(k) == "string" then
		solid[k] = if present then true else nil
	end
end

local function bindShaft(f: Instance)
	unbindShaft()
	myShaft = f
	for _, ch in f:GetChildren() do trackChild(ch, true) end
	table.insert(shaftConns, f.ChildAdded:Connect(function(ch) trackChild(ch, true) end))
	table.insert(shaftConns, f.ChildRemoved:Connect(function(ch) trackChild(ch, false) end))
end

local function refreshShaft(now: number)
	if myShaft ~= nil and (myShaft :: Instance).Parent ~= nil and shaftOrigin ~= nil then return end
	if myShaft ~= nil and (myShaft :: Instance).Parent == nil then unbindShaft() end
	if now - lastShaftSearch < 0.5 then return end
	lastShaftSearch = now
	local shafts = workspace:FindFirstChild("Shafts")
	if shafts == nil then return end
	if myShaft == nil then
		for _, f in shafts:GetChildren() do
			if f:FindFirstChild("SellPad_" .. player.UserId) ~= nil then
				bindShaft(f)
				break
			end
		end
	end
	if myShaft ~= nil then
		local floor = (myShaft :: Instance):FindFirstChild("DepthWall_" .. player.UserId)
		if floor and floor:IsA("BasePart") then
			shaftOrigin = Vector3.new(floor.Position.X, 0, floor.Position.Z)
			floorTop = floor.Position.Y + floor.Size.Y / 2
		end
	end
end

local function isSolid(k: string): boolean
	return solid[k] == true
end

-- ── state ─────────────────────────────────────────────────────────────────────
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil

local now = 0
local weights: { [number]: number } = {}
local current: { [string]: any }? = nil -- smoothed lighting groups
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local celebrateAbove = math.huge -- set from the player's best depth once the profile has loaded
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat = false -- this script sat the character down (manual rest)
local knockUntil: number? = nil
local settleLeft = 0
local settleWaited = 0
local SETTLE_SECONDS = 1.5
local SETTLE_TIMEOUT = 15
local frameError = false
local clickPulse = false -- a world click or tap since the last frame: a swing, which is activity
local lastRootPos: Vector3? = nil
local ringPlan: any = nil -- the hazard the ring below belongs to
local ringLayerNow: number? = nil -- the layer whose floor its ring lies on (Strata.ringLayer)
local crumbs: { Vector3 } = {} -- centres of the cells the miner has stood in, newest last (open air)
local lastCrumbKey: string? = nil
local MAX_CRUMBS = 16

local pieceIds: { [string]: boolean } = {}
for _, b in bands do
	for _, id in b.pieces or {} do
		pieceIds[id] = true
	end
end

local function vec(v: Vector3)
	return { x = v.X, y = v.Y, z = v.Z }
end

local function unsit()
	if sat and hum then
		pcall(function() (hum :: Humanoid).Sit = false end)
	end
	sat = false
	setRestFocus(false)
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	rest = Rest.new()
	sat = false
	setRestFocus(false)
	knockUntil = nil
	settleLeft = SETTLE_SECONDS
	settleWaited = 0
	crumbs = {}
	lastCrumbKey = nil
	lastRootPos = nil
	if scheduler.active then
		art:hideHazard(scheduler.active.kind)
		scheduler.active = nil
	end
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

-- A swing is a click or a tap on the world (the server's ClickDetector does the digging). It counts as
-- activity: it wakes a resting miner and stops idle rest, so nobody mines while the cave leaves them
-- alone. On a phone that is a TAP (TouchTap): a finger dragged across the screen turns the camera, and
-- looking around must not wake a resting miner.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		clickPulse = true
	end
end)
pcall(function()
	UserInputService.TouchTap:Connect(function(_, processed)
		if not processed then clickPulse = true end
	end)
end)

restBtn.Activated:Connect(function()
	if not restOn then return end
	if Rest.isResting(rest) or rest.pending then
		Rest.stop(rest)
		unsit()
		return
	end
	local grounded = false
	if hum then
		local fm = (hum :: any).FloorMaterial
		grounded = fm ~= nil and fm ~= Enum.Material.Air
	end
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = grounded, threat = scheduler.active ~= nil })
	if result == "resting" then
		sat = true
		setRestFocus(true)
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
	end
end)

-- ── the frame ─────────────────────────────────────────────────────────────────
local function frame(dt: number)
	now += dt
	refreshShaft(now)
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camPos = camera.CFrame.Position
	local originY = if shaftOrigin then (shaftOrigin :: Vector3).Y else 0
	local rootY = if hrp then (hrp :: BasePart).Position.Y - originY else Env.RootAboveFloor
	-- Continuous depth drives every blend; the NAMED layer (the root's cell, the server's minerLayer) drives
	-- the chip, the cards, the hazards and where the ring and the lantern are set down: on its floor.
	local p = Strata.depthAt(Config, rootY)
	local layer = Strata.layerAt(Config, Mine, rootY)
	local bandIdx = EnvBands.indexAt(bands, layer)
	art:setShaft(shaftOrigin, floorTop)

	-- band weights, smoothed so a teleport glides instead of cutting
	local targetW = EnvBands.weights(bands, p)
	for i = 1, #bands do
		local tw = targetW[i] or 0
		if current == nil then
			weights[i] = tw
		else
			weights[i] = EnvBands.approach(weights[i] or 0, tw, dt, Env.HalfLife)
		end
	end

	-- lighting at LightingHz
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		local target = {}
		for _, g in GROUPS do
			target[g] = EnvBands.sample(bands, p, g)
		end
		if current == nil then
			-- the client's own surface look on the very first frame (the player is still loading in),
			-- then glide to where this player actually is
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

	-- set pieces, wall decor, critters, weather
	local pieceW: { [string]: number } = {}
	local critters: { [string]: number } = {}
	local weather: { [string]: number } = {}
	for i, b in bands do
		local w = weights[i] or 0
		if w > 0.001 then
			for _, id in b.pieces or {} do
				pieceW[id] = math.min(1, (pieceW[id] or 0) + w)
			end
			for _, a in b.ambient or {} do
				if CaveArt.hasCritter(a.kind) then
					critters[a.kind] = (critters[a.kind] or 0) + a.count * w
				end
			end
			if b.weather and CaveArt.hasWeather(b.weather.kind) then
				weather[b.weather.kind] = (weather[b.weather.kind] or 0) + b.weather.rate * w
			end
		end
	end
	for id in pieceIds do
		art:updatePiece(id, pieceW[id] or 0)
	end
	art:updateDecor(layer)
	for kind, n in critters do
		critters[kind] = math.floor(n + 0.5)
	end
	art:updateCritters(critters, crumbs, dt, now)
	art:updateWeather(weather, camPos)

	if hrp == nil or hum == nil then
		return
	end
	local rootPart = hrp :: BasePart
	local humanoid = hum :: Humanoid
	local rootPos = rootPart.Position

	-- the knock wears off
	if knockUntil and now >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end

	-- grounded / moving, from the Humanoid (the client's own character)
	local fm = (humanoid :: any).FloorMaterial
	local grounded = fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
	local supported = grounded
	if sat and not grounded and knockUntil == nil then
		supported = math.abs(rootPart.AssemblyLinearVelocity.Y) < 2
	end
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true or clickPulse
	clickPulse = false

	-- where the miner is in their shaft: the cell, the open sides, the trail of cells they stood in
	local inShaft, cx, cz = false, 0, 0
	local open = {}
	if shaftOrigin then
		local rel = rootPos - (shaftOrigin :: Vector3)
		cx, cz = Strata.cellXZ(Config, rel.X, rel.Z)
		local gw = Config.Mine.GridW
		inShaft = cx >= 2 and cx <= gw - 1 and cz >= 2 and cz <= gw - 1 and rel.Y < Env.RootAboveFloor + S
		if inShaft then
			open = Strata.openSides(Config, Mine, isSolid, cx, layer, cz)
		end
	end
	local jumped = lastRootPos ~= nil and (rootPos - (lastRootPos :: Vector3)).Magnitude > 14
	lastRootPos = rootPos
	if jumped then
		-- an elevator ride or a rebirth: the trail behind is no longer where the miner is
		crumbs = {}
		lastCrumbKey = nil
	end
	if inShaft and grounded then
		local key = Mine.key(cx, layer, cz)
		if key ~= lastCrumbKey then
			lastCrumbKey = key
			local lp = Mine.localPos(Config, cx, layer, cz)
			table.insert(crumbs, (shaftOrigin :: Vector3) + Vector3.new(lp.x, lp.y, lp.z))
			if #crumbs > MAX_CRUMBS then table.remove(crumbs, 1) end
		end
	end

	-- rest
	if restOn then
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = scheduler.active ~= nil })
		if ev == "started" and rest.source == "manual" then
			sat = true
			setRestFocus(true)
			pcall(function() humanoid.Sit = true end)
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
	end
	local resting = restOn and Rest.isResting(rest)
	art:setRestLantern(resting and rest.source == "manual", rootPart.CFrame, originY + Mine.floorY(Config, layer))

	-- hazards
	if hazardsOn then
		local look = camera.CFrame.LookVector
		local yaw = math.atan2(look.X, look.Z)
		local pitch = math.asin(math.clamp(look.Y, -1, 1))
		local before = if scheduler.active then scheduler.active.t else nil
		local pos = vec(rootPos)
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting,
			grounded = grounded,
			kinds = if inShaft then (bands[bandIdx].hazards or {}) else {},
			aim = pos,
			yaw = yaw,
			pitch = pitch,
			canDodge = inShaft and #open > 0,
		}, rand)
		if ev and ev.type == "done" then
			art:hideHazard(ev.plan.kind)
		end
		local plan = scheduler.active
		if plan then
			-- The ring lies on the floor the miner STOOD on while the hazard followed them, and stays once it
			-- locks (Strata.ringLayer). It used to follow the root's layer, so a jump lifted the "shadow" 6
			-- studs into the air, and kept it there if the lock came mid-jump (review 2026-09-24, finding 4).
			if plan ~= ringPlan then
				ringPlan = plan
				ringLayerNow = nil
			end
			ringLayerNow = Strata.ringLayer(ringLayerNow, layer, grounded, plan.locked)
			local ringLayer = ringLayerNow :: number
			local zoneFloor = originY + Mine.floorY(Config, ringLayer)
			local hp = Hazards.positionAt(plan, plan.t)
			local zone = Hazards.zone(plan, Hz.PlayerRadius)
			if plan.drop == "above" and plan.hang ~= nil then
				-- DRAWN where it can be seen (Strata.dropY): under the real ceiling if one is within reach, never
				-- inside the miner (in a one-layer tunnel it pokes out of the roof), falling from there to pass the
				-- plan's aim at the plan's own moment, then lying on the floor. Drawing only: the plan, the zone
				-- and the hit are unchanged (review 2026-09-24, finding 1: it used to hang through the head).
				local ceiling = nil
				if shaftOrigin then
					local o = shaftOrigin :: Vector3
					local zx, zz = Strata.cellXZ(Config, zone.x - o.X, zone.z - o.Z)
					local reach = math.ceil((plan.height or 0) / S) + 1
					local openUp = Strata.openAbove(Config, Mine, isSolid, zx, ringLayer, zz, reach)
					if openUp < reach then
						ceiling = originY + Strata.ceilingY(Config, Mine, ringLayer, openUp)
					end
				end
				hp = { x = hp.x, z = hp.z, y = Strata.dropY({
					t = plan.t, hang = plan.hang, arrive = plan.arriveAt, startY = plan.start.y, targetY = plan.target.y,
					half = CaveArt.hazardHalfHeight(plan.kind), floorY = zoneFloor, ceilingY = ceiling,
					headTop = zoneFloor + Env.HeadTopAboveFloor,
				}) }
			end
			art:showHazard(plan, hp, now, zone, zoneFloor)
			if Hazards.checkHit(plan, before or 0, plan.t, pos, Hz.PlayerRadius) then
				plan.hit = true
				local side = open[1]
				local kv = Hazards.knockVelocity(Hz, plan, pos, if side then { x = side.x, y = 0, z = side.z } else nil)
				pcall(function() humanoid.PlatformStand = true end)
				rootPart.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				Rest.stop(rest)
				unsit()
				FxClient.shake(0.4, 0.9)
				FxClient.flash(Color3.fromRGB(255, 236, 210), 0.3, 0.35)
			end
			if plan.t <= plan.arriveAt and not plan.hit then
				local below = CaveArt.hazardFromBelow(plan.kind)
				local arrow = if below then "▼" else "▲"
				local text = if plan.locked
					then "⚠️ MOVE! Step out of the " .. (if below then "vent " else "shadow ") .. arrow
					else "⚠️ " .. CaveArt.hazardLabel(plan.kind) .. (if below then " BELOW " else " ABOVE ") .. arrow
				if warning.Text ~= text then warning.Text = text end
				warning.Visible = true
			else
				warning.Visible = false
			end
		else
			warning.Visible = false
		end
	end

	-- the chip, the button, the cards
	local chipText
	if resting then
		chipText = if rest.source == "idle" then "💤 Idle — the cave leaves you alone" else "⛺ Resting — the cave leaves you alone"
	else
		local b = bands[bandIdx]
		chipText = string.format("%s %s  ·  %d m", b.emoji, b.name, math.floor(Mine.depthStuds(Config, layer)))
		local nextIdx, remaining = EnvBands.nextBand(bands, layer)
		if nextIdx then
			chipText ..= string.format("  ·  %s in %d m", bands[nextIdx].emoji, math.max(1, math.ceil(remaining :: number)) * S)
		end
	end
	if chip.Text ~= chipText then chip.Text = chipText end
	local btnText = if resting then "▶ Mine" elseif rest.pending then "⛺ …" else "⛺ Rest"
	if restBtn.Text ~= btnText then restBtn.Text = btnText end
	-- a phone drawer open: the row steps into the side it leaves free, banner and Rest button included
	placeRow(rowSpan())
	chip.Visible = chipFits
	restBtn.Visible = true

	-- A new band is announced when the miner STANDS in it (not while falling past it). The first card
	-- waits for the profile to load (leaderstats), so the player's best-ever depth is known: only a band
	-- deeper than that gets the fanfare, once.
	local standing = (fm ~= nil and fm ~= Enum.Material.Air) or sat
	if settleLeft > 0 or announcer.highest == 0 then
		local stats = player:FindFirstChild("leaderstats")
		local depthValue = stats and stats:FindFirstChild("Depth")
		if depthValue then
			settleLeft -= dt
			settleWaited += dt
		end
		if (settleLeft <= 0 and depthValue ~= nil) or settleWaited >= SETTLE_TIMEOUT then
			settleLeft = 0
			if announcer.highest == 0 then
				local best = if depthValue then math.floor(((depthValue :: any).Value or 0) / S) else 0
				celebrateAbove = EnvBands.indexAt(bands, best)
				EnvBands.announce(announcer, bandIdx)
				local b = bands[bandIdx]
				showCard(b.emoji .. " " .. string.upper(b.name), string.format("%d m deep", math.floor(Mine.depthStuds(Config, layer))), false)
			end
		end
	elseif standing and EnvBands.announce(announcer, bandIdx) then
		local b = bands[bandIdx]
		local sub = string.format("%d m deep", math.floor(Mine.depthStuds(Config, layer)))
		if b.celebrate and bandIdx > celebrateAbove then
			celebrateAbove = bandIdx
			showCard(b.emoji .. " YOU REACHED " .. (b.reached or string.upper(b.name)) .. "!", sub, true)
		else
			showCard(b.emoji .. " " .. string.upper(b.name), sub, false)
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken cave must not flood the output
		warn("[DeepVeinCave] frame error: " .. tostring(err))
	end
end)
