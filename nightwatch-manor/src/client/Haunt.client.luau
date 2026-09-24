-- Haunt.client.luau — the nights escalate. Client only (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads the progress the server already tells this player (State: phase, night, dread, spotted, hub
--     level) and turns it into Nightfall.progress: the night number, nudged forward by dread while a
--     night runs. Never a timer. Surviving a night moves you a whole band-step; being caught does not;
--   * blends the bands in Config.Env (EnvBands): lighting, fog and grade inside the fairness envelope,
--     the windows' sky, moon, mist and rain, lightning, dust, candle flicker, curtain sway, the portraits'
--     eyes, and the safehouse's cosiness by hub level. Everything glides; nothing hard-cuts;
--   * runs the rare hazards (Hazards + Nightfall.hazardClock) at night only: one every 2-3 minutes of night,
--     the clock frozen in the day and HELD (running, no launch) while the Nightwatcher sees you and for
--     QuietAfterSpottedSeconds after; calls a hazard off and ends a knock the moment it sees you;
--   * offers rest in the safehouse (the break room between rounds); never inside the manor. No lightning
--     flashes while you rest;
--   * honours Roblox's own Reduced Motion setting (GuiService.ReducedMotionEnabled, read live): no lightning
--     flashes, no screen flash or shake on a hit or a card, and the hazard's warning light holds steady.
--
-- Why it is client-side, and why that is safe:
--   * it is cosmetic, or it only ever harms the local player (a knock), whose character physics the
--     client already owns. It fires no remote, adds no remote, sets no attribute, and builds nothing that
--     can collide, be touched or be raycast. Relics, dread, the night and the Nightwatcher are the
--     server's and never hear of any of this;
--   * it reads only what this player already has: the State payload the HUD shows, its own character and
--     camera, Config, and the manor's parts (which it can see). It never reads the Nightwatcher's
--     position, and nothing it draws depends on where the Nightwatcher is.
--   * What it WRITES outside its own folder and GUI (review 4 corrected an earlier "only room lights" claim):
--       - the Lighting service's band keys and the server's FxAtmosphere / FxBloom / FxColorCorrection (the
--         bands ARE this), inside Nightfall.fairness's envelope; never FxDoF or any other Lighting child, and
--         one effect of its own there, NightwatchRestFocus. A future SERVER change to Lighting would be
--         overwritten here: put it in the bands instead;
--       - the Brightness of the manor's room lights (flicker), inside Nightfall's floor;
--       - its own character: Humanoid.Sit (rest), Humanoid.PlatformStand and the root's AssemblyLinearVelocity
--         (a knock). Those are normal character state and may replicate like any movement; the server reads
--         none of them. robloxemu/check_nightwatchmanor_haunt.luau asserts the Lighting write-set.
-- Measured budgets and the band table: EYECANDY.md. Headless checks: robloxemu/check_nightwatchmanor_*.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Nightfall = require(ReplicatedStorage:WaitForChild("Nightfall"))
local HauntArt = require(ReplicatedStorage:WaitForChild("HauntArt"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local Remotes = ReplicatedStorage:WaitForChild("ManorRemotes")
local StateRemote = Remotes:WaitForChild("State") :: RemoteEvent
local NoticeRemote = Remotes:WaitForChild("Notice") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Env, Hz, RestCfg = Config.Env, Config.Hazards, Config.Rest
local bands = Env.Bands

-- A broken config must cost the polish, never the game: warn loudly and switch that part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[Nightwatch] Config.Env.Bands is invalid (" .. tostring(err) .. "); the night stays as the server set it.")
		return
	end
end
-- Fairness is a gate on the LIGHTING only: an unfair band would change how far you can see the
-- Nightwatcher, so the grade stays exactly the server's tuned preset. The rest of the eye candy still runs.
local lightingOn, fairErr = Nightfall.fairness(Config)
if not lightingOn then
	warn("[Nightwatch] Config.Env is not fair to the chase (" .. tostring(fairErr) .. "); lighting stays the server's preset.")
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if hazardsOn then
	hazardsOn, hazardsErr = Nightfall.validateHazards(Config)
end
if not hazardsOn then
	warn("[Nightwatch] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if restOn then
	restOn, restErr = Nightfall.validateRest(RestCfg)
end
if not restOn then
	warn("[Nightwatch] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- Roblox's own accessibility setting (Settings > Reduced Motion), read live. Review 4: lightning flashed every
-- 2.7-3.5 s late in a storm night and there was no way to opt out. With it on, nothing of ours flashes: no
-- lightning (the rain, the windows and the rest of the band stay), no screen flash or shake on a hit or a title
-- card, and a hazard's warning light and marker hold steady. pcall: an engine without the property reads as off.
local function readCalm(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end
local calm = readCalm()
pcall(function()
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		calm = readCalm()
	end)
end)

-- ── local world + lighting rig ────────────────────────────────────────────────
local folder = Instance.new("Folder")
folder.Name = "NightwatchLocal"
folder.Parent = workspace
local art = HauntArt.new(folder, rand, Config, Nightfall, EnvBands)

-- Reuse the server's Fx.applyLighting objects by name so the client takes over from exactly the values
-- the server set (band 1 IS that preset) instead of stacking a second Atmosphere on top.
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
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection" }
local targets = {
	lighting = Lighting,
	atmosphere = rig("Atmosphere", "FxAtmosphere"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
}
local LOOKS = { "glow", "outside", "inside" }

-- Rest's soft focus: its own effect, so it can never disturb the server's DepthOfField (the chase's).
local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "NightwatchRestFocus"
restFocus.FarIntensity = 0.3
restFocus.FocusDistance = 14
restFocus.InFocusRadius = 20
restFocus.NearIntensity = 0
restFocus.Enabled = false
restFocus.Parent = Lighting

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
			changed = prev == nil or math.abs(prev[1] - v[1]) > 0.5 or math.abs(prev[2] - v[2]) > 0.5 or math.abs(prev[3] - v[3]) > 0.5
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
-- Laid out AROUND Hud.client.luau. On a desktop or tablet: a row under the HUD's help line and between its
-- side panels (their sizes are mirrored here), the warning under the HUD's "IT SEES YOU" banner, the card
-- below the middle of the screen where the HUD's toasts are not. On a phone the top belongs to the HUD, so
-- ours stacks up from the bottom centre, between Roblox's thumbstick and jump button.
-- robloxemu/check_nightwatchmanor_layout.luau measures that none of it overlaps the HUD at ten viewports,
-- day and night, with the phone drawers open and the HUD's banner and toasts forced on.
local MARGIN, GAP = Responsive.MARGIN, 8
local HUD_STATUS_W, HUD_HOUSE_W = 250, 300
local ROW_W, ROW_H, REST_W = 440, 32, 118
local MIN_TAP = 44

local gui = Instance.new("ScreenGui")
gui.Name = "NightwatchHaunt"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
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
local function maxText(inst: Instance, size: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = size
	c.Parent = inst
end

local chip = Instance.new("TextLabel")
chip.Name = "BandChip"
chip.BackgroundColor3 = Color3.fromRGB(16, 14, 20)
chip.BackgroundTransparency = 0.25
chip.Font = Enum.Font.GothamBold
chip.TextColor3 = Color3.fromRGB(226, 220, 236)
chip.TextScaled = true
chip.Text = ""
chip.Visible = false
chip.Parent = root
corner(chip, 10)
maxText(chip, 16)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = chip
end

local restBtn = Instance.new("TextButton")
restBtn.Name = "RestButton"
restBtn.BackgroundColor3 = Color3.fromRGB(150, 96, 40)
restBtn.Font = Enum.Font.GothamBlack
restBtn.TextColor3 = Color3.fromRGB(255, 244, 226)
restBtn.TextScaled = true
restBtn.Text = "☕ Rest"
restBtn.AutoButtonColor = true
restBtn.Visible = false
restBtn.Parent = root
corner(restBtn, 10)
maxText(restBtn, 16)

local warning = Instance.new("TextLabel")
warning.Name = "HazardWarning"
warning.BackgroundColor3 = Color3.fromRGB(90, 40, 10)
warning.BackgroundTransparency = 0.15
warning.Font = Enum.Font.GothamBlack
warning.TextColor3 = Color3.fromRGB(255, 226, 120)
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
card.TextColor3 = Color3.fromRGB(255, 244, 232)
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
cardSub.TextColor3 = Color3.fromRGB(226, 214, 236)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root

local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local function tapSize(designPx: number): number
	-- the HUD's own rule (Hud.client.luau tapSize), so the two rows line up
	if layout.controlPad <= 0 then return designPx end
	return math.ceil(math.max(designPx, MIN_TAP) / layout.scale)
end

local function applyLayout()
	local v = camera.ViewportSize
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	layout = Responsive.layout(vx, vy, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
	local rootW = vx / layout.scale
	local rootH = vy / layout.scale
	local compact = layout.compact

	local rowH = tapSize(ROW_H)
	local btnW = tapSize(REST_W)
	local restShown = restBtn.Visible

	if not compact then
		-- DESKTOP / TABLET: a row under the HUD's help line, between its two side panels
		local rowTop = 20 + 24 + GAP
		local side = math.max(16 + Responsive.sideWidth(HUD_STATUS_W, vx, layout), 16 + Responsive.sideWidth(HUD_HOUSE_W, vx, layout)) + GAP
		local rowW = math.min(ROW_W, rootW - 2 * side)
		local left = (rootW - rowW) / 2
		if restShown then
			chip.Position = UDim2.fromOffset(left, rowTop)
			chip.Size = UDim2.fromOffset(rowW - btnW - GAP, rowH)
		else
			chip.Position = UDim2.fromOffset(left, rowTop)
			chip.Size = UDim2.fromOffset(rowW, rowH)
		end
		restBtn.Position = UDim2.fromOffset(left + rowW - btnW, rowTop)
		restBtn.Size = UDim2.fromOffset(btnW, rowH)
		-- the hazard warning under the HUD's "IT SEES YOU" banner (THE BELL RINGS uses the same banner and
		-- can be up at the same time as a hazard)
		local warnW = math.min(420, rootW - 2 * side)
		warning.Position = UDim2.fromOffset((rootW - warnW) / 2, rootH * 0.16 + 34 + GAP)
		warning.Size = UDim2.fromOffset(warnW, 30)
		-- the title card below the middle of the screen, where the HUD's toasts are not
		local cardW = math.min(700, rootW - 2 * side)
		local cardY = rootH * 0.6
		local cardH = math.min(56, rootH * 0.1)
		card.Position = UDim2.fromOffset(rootW / 2, cardY)
		card.Size = UDim2.fromOffset(cardW, cardH)
		cardSub.Position = UDim2.fromOffset(rootW / 2, cardY + cardH / 2 + 4)
		cardSub.Size = UDim2.fromOffset(cardW, math.min(26, rootH * 0.05))
		return
	end

	-- PHONE: the top of the screen belongs to the HUD (its toggles, help line, drawers, the "IT SEES YOU"
	-- banner and its toasts), so everything of ours stacks up from the BOTTOM CENTRE, in the gap between
	-- Roblox's own thumbstick (left 35%) and jump button (right 25%): chip row at the bottom, the warning
	-- above it, the card above that. check_nightwatchmanor_layout.luau measures it on ten viewports.
	local colL = rootW * 0.35 + GAP
	local colR = rootW * 0.75 - GAP
	local colW = math.max(80, colR - colL)
	local y = rootH - MARGIN
	if restShown and colW < btnW + 120 then
		-- too narrow for both on one line: the chip at the bottom, the button on its own line above it
		y -= rowH
		chip.Position = UDim2.fromOffset(colL, y)
		chip.Size = UDim2.fromOffset(colW, rowH)
		y -= rowH + GAP
		restBtn.Position = UDim2.fromOffset(colR - btnW, y)
		restBtn.Size = UDim2.fromOffset(btnW, rowH)
	else
		y -= rowH
		chip.Position = UDim2.fromOffset(colL, y)
		chip.Size = UDim2.fromOffset(if restShown then colW - btnW - GAP else colW, rowH)
		restBtn.Position = UDim2.fromOffset(colR - btnW, y)
		restBtn.Size = UDim2.fromOffset(btnW, rowH)
	end
	y -= GAP + 30
	warning.Position = UDim2.fromOffset(colL, y)
	warning.Size = UDim2.fromOffset(colW, 30)
	local subH = math.min(24, rootH * 0.045)
	local cardH = math.min(46, rootH * 0.08)
	y -= GAP + subH
	cardSub.Position = UDim2.fromOffset(colL + colW / 2, y)
	cardSub.Size = UDim2.fromOffset(colW, subH)
	y -= 4 + cardH / 2
	card.Position = UDim2.fromOffset(colL + colW / 2, y)
	card.Size = UDim2.fromOffset(colW, cardH)
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
	if celebrate and not calm then
		FxClient.flash(Color3.fromRGB(255, 240, 230), 0.4, 0.9)
		FxClient.fovPunch(6, 0.12, 0.6)
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

-- ── what the server has told this player (the HUD shows all of it) ─────────────
local srv = { loaded = false, phase = nil :: string?, night = 1, dread = 0, spotted = false, hubLevel = 0, ended = false }
-- The night is over the moment the server says so (the HUD's own EXTRACTED / CAUGHT / EVICTED notice), even
-- though the phase stays NIGHT for the 2.5 s beat before the teleport home: no hazard starts in that beat.
NoticeRemote.OnClientEvent:Connect(function(n)
	if type(n) ~= "table" then return end
	if n.kind == "EXTRACTED" or n.kind == "CAUGHT" or n.kind == "EVICTED" then
		srv.ended = true
	end
end)
StateRemote.OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	-- The server pushes State for the first time only once the profile has LOADED (Main.server's
	-- onPlayerAdded), so the first push is the "loaded" signal; no card or band change before it.
	srv.loaded = true
	local phase = if s.phase == "NIGHT" then "NIGHT" elseif s.phase == "DAY" then "DAY" else srv.phase
	if phase ~= srv.phase then srv.ended = false end
	srv.phase = phase
	srv.night = math.max(1, math.floor(tonumber(s.night) or srv.night))
	srv.dread = math.clamp(tonumber(s.dread) or 0, 0, 1)
	srv.spotted = s.spotted == true
	srv.hubLevel = math.max(0, math.floor(tonumber(s.hubLevel) or 0))
end)

-- ── state ─────────────────────────────────────────────────────────────────────
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil

local now = 0
local current: { [string]: any }? = nil -- smoothed lighting groups
local look: { [string]: any }? = nil -- smoothed glow / outside / inside
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat = false
local knockUntil: number? = nil
local lastSpottedAt = -math.huge
local lastPhase: string? = nil
local dayFor = 0 -- seconds in the current day phase (cards wait for the extraction toast to clear)
local nextBolt = 8
local flashLeft = 0
local flashBolt = false
local frameError = false

local ARROWS = { ahead = "▲", left = "◀", right = "▶", behind = "▼" }

local function vec(v: Vector3)
	return { x = v.X, y = v.Y, z = v.Z }
end

local function unsit()
	if sat and hum then
		pcall(function() (hum :: Humanoid).Sit = false end)
	end
	sat = false
	restFocus.Enabled = false
end

local function endKnock()
	if knockUntil ~= nil then
		knockUntil = nil
		if hum then pcall(function() (hum :: Humanoid).PlatformStand = false end) end
	end
end

local function callOffHazard()
	if scheduler.active then
		Hazards.cancel(scheduler)
	end
	art:hideHazard(nil)
	warning.Visible = false
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	rest = Rest.new()
	sat = false
	restFocus.Enabled = false
	knockUntil = nil
	callOffHazard()
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

restBtn.Activated:Connect(function()
	if not restOn or not Nightfall.restAllowed(RestCfg, srv.phase) then return end
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
	-- no hazard ever runs in the day, so there is never a threat here; the template's rule is kept anyway
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = grounded, threat = scheduler.active ~= nil })
	if result == "resting" then
		sat = true
		restFocus.Enabled = true
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
	end
end)

local function myZone(): Instance?
	return workspace:FindFirstChild("Zone_" .. tostring(player.UserId))
end

-- ── the frame ─────────────────────────────────────────────────────────────────
local function frame(dt: number)
	now += dt
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camCF = camera.CFrame
	local camPos = camCF.Position
	local phase = srv.phase
	local night = srv.night

	-- a phase change: nothing carries over. A hazard in flight is called off, a knock ends, rest ends.
	if phase ~= lastPhase then
		lastPhase = phase
		dayFor = 0
		callOffHazard()
		endKnock()
		-- rest belongs to one stay in the safehouse: a new day starts a fresh idle count, and the night
		-- ends any rest (nothing may carry into, or out of, a round)
		if Rest.isResting(rest) or rest.pending then
			Rest.stop(rest)
			unsit()
		end
		rest = Rest.new()
	end
	if phase == "DAY" then dayFor += dt end

	-- progress: the night, nudged by dread (never time); the band NAMED by the whole night number
	local p = Nightfall.progress(Env, phase, night, srv.dread)
	local bandIdx = Nightfall.bandIndex(bands, night)

	-- lighting + look at LightingHz, smoothed so a night starting or ending glides
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		if current == nil then
			-- start from band 1, which IS the server's preset, and glide to where this player is
			current, look = {}, {}
			for _, g in GROUPS do (current :: any)[g] = EnvBands.sample(bands, 0, g) end
			for _, g in LOOKS do (look :: any)[g] = EnvBands.sample(bands, 0, g) end
		end
		for _, g in GROUPS do
			(current :: any)[g] = EnvBands.approachTable((current :: any)[g], EnvBands.sample(bands, p, g), step, Env.HalfLife)
		end
		for _, g in LOOKS do
			(look :: any)[g] = EnvBands.approachTable((look :: any)[g], EnvBands.sample(bands, p, g), step, Env.HalfLife)
		end
		if lightingOn then
			for _, g in GROUPS do
				local props = (current :: any)[g]
				if g == "colorCorrection" and flashLeft > 0 then
					props = table.clone(props)
					props.Brightness = (props.Brightness or 0) + math.min(Env.FlashBoost, Nightfall.HARD.FlashBoostMax)
				end
				writeGroup(targets[g], props)
			end
		end
	end
	local L = look :: any

	-- lightning: bands with a storm in them flash their windows, more often as dread rises. The gap is REAL seconds
	-- from Nightfall.boltGap and never under HARD.FlashGapMin (review 4: a countdown run at (1 + dread) x real time
	-- flashed every 2.7 s in the Witching Hour). A strike that falls due while you rest by the fire, or with
	-- Reduced Motion on, is silent: the gap is kept, nothing flashes.
	local flash = 0
	local stormSpec = bands[bandIdx].lightning
	if flashLeft > 0 then
		flashLeft -= dt
		flash = math.clamp(flashLeft / 0.12, 0, 1)
		if flashLeft <= 0 then
			flash = 0
			-- the grade's flash boost comes off at the next lighting write; force it now
			if lightingOn then writeGroup(targets.colorCorrection, (current :: any).colorCorrection) end
		end
	end
	if stormSpec and srv.loaded then
		nextBolt -= dt
		if nextBolt <= 0 then
			nextBolt = Nightfall.boltGap(stormSpec, if phase == "NIGHT" then srv.dread else 0, rand())
			if not calm and not Rest.isResting(rest) then
				flashLeft = 0.12
				flash = 1
				flashBolt = stormSpec.bolt == true
				if lightingOn then
					local props = table.clone((current :: any).colorCorrection)
					props.Brightness = (props.Brightness or 0) + math.min(Env.FlashBoost, Nightfall.HARD.FlashBoostMax)
					writeGroup(targets.colorCorrection, props)
				end
			end
		end
	end

	-- the world: the manor at night, the safehouse by day
	local zone = myZone()
	local manor = if phase == "NIGHT" and zone then zone:FindFirstChild("Manor") else nil
	local house = zone and zone:FindFirstChild("Safehouse") or nil
	art:syncManor(manor)
	art:syncSafehouse(house)
	local head = if hrp then (hrp :: BasePart).Position + Vector3.new(0, 1.5, 0) else nil
	local dread = if phase == "NIGHT" then srv.dread else 0
	art:updateManor({ cam = camPos, head = head, now = now, look = L, dread = dread, flash = flash })
	local tier = Nightfall.cosyTier(Env.Cosy, srv.hubLevel)
	art:updateSafehouse(phase ~= "NIGHT" and srv.loaded, { now = now, look = L, tier = tier, flash = flash })

	-- weather: dust in the room you stand in, rain on the nearest window (the budget caps both)
	local focus = if hrp then (hrp :: BasePart).Position else camPos
	local room = if manor then art:roomAt(focus) else nil
	local rainWindow = nil
	if manor then
		rainWindow = art.nearest
	elseif phase ~= "NIGHT" and art.houseWindows then
		local best, bd = nil, math.huge
		for _, w in art.houseWindows do
			local d = (w.pos - focus).Magnitude
			if d < bd then best, bd = w, d end
		end
		rainWindow = best
	end
	local inside, outside = L.inside or {}, L.outside or {}
	art:updateWeather({
		dust = if room then (inside.dust or 0) * (1 + 0.5 * dread) else 0,
		rain = outside.rain or 0,
	}, room and room.centre or nil, rainWindow, L)
	art:flash(flash, flashBolt, rainWindow, L)

	if hrp == nil or hum == nil then
		return
	end
	local root = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- the Nightwatcher has seen you: nothing of ours may be in the way of running
	if srv.spotted then
		lastSpottedAt = now
		if scheduler.active then callOffHazard() end
		endKnock()
	end
	if knockUntil and now >= knockUntil then
		endKnock()
	end

	local fm = (humanoid :: any).FloorMaterial
	local grounded = fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
	local supported = grounded
	if sat and not grounded and knockUntil == nil then
		supported = math.abs((root.AssemblyLinearVelocity or Vector3.zero).Y) < 2
	end
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true

	-- rest: the safehouse only (Nightfall.restAllowed); the night never pauses
	local restHere = restOn and srv.loaded and Nightfall.restAllowed(RestCfg, phase)
	if restHere then
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = false })
		if ev == "started" and rest.source == "manual" then
			sat = true
			restFocus.Enabled = true
			pcall(function() humanoid.Sit = true end)
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
	elseif Rest.isResting(rest) or rest.pending then
		Rest.stop(rest)
		unsit()
	end
	local resting = restHere and Rest.isResting(rest)

	-- hazards: at night, on this band's kinds; the clock frozen outside the night, held while it hunts you
	if hazardsOn then
		local clock = Nightfall.hazardClock(Hz, { phase = if srv.ended then "ENDED" else phase, spotted = srv.spotted, sinceSpotted = now - lastSpottedAt })
		if srv.ended and scheduler.active then callOffHazard() end
		if srv.ended then endKnock() end
		local lookV = camCF.LookVector
		local yaw = math.atan2(lookV.X, lookV.Z)
		local pitch = math.asin(math.clamp(lookV.Y, -1, 1))
		local before = if scheduler.active then scheduler.active.t else nil
		local pos = vec(root.Position)
		local vel = root.AssemblyLinearVelocity or Vector3.zero
		local remaining = if scheduler.active then scheduler.active.arriveAt - scheduler.active.t else 0
		local aim = Nightfall.leadAim(pos, { x = vel.X, y = 0, z = vel.Z }, remaining, Hz.LeadSeconds, Config.Player.WalkSpeed)
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting,
			paused = clock == "freeze",
			held = clock == "hold",
			grounded = grounded,
			kinds = if phase == "NIGHT" then (bands[bandIdx].hazards or {}) else {},
			aim = aim,
			yaw = yaw,
			pitch = pitch,
		}, rand)
		if ev and ev.type == "done" then
			art:hideHazard(ev.plan.kind)
		end
		local plan = scheduler.active
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local floorY = root.Position.Y - 3
			art:showHazard(plan, hp, now, Hazards.zone(plan, Hz.PlayerRadius), floorY, calm)
			if Hazards.checkHit(plan, before or 0, plan.t, pos, Hz.PlayerRadius) then
				plan.hit = true
				local kv = Hazards.knockVelocity(Hz, plan, pos)
				pcall(function() humanoid.PlatformStand = true end)
				root.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				if not calm then
					FxClient.shake(0.35, 0.8)
					FxClient.flash(Color3.fromRGB(230, 236, 240), 0.25, 0.3)
				end
			end
			if plan.t <= plan.arriveAt and not plan.hit then
				local b = Hazards.bearing(vec(camPos), vec(lookV), hp)
				local label = HauntArt.HAZARD_NAMES[plan.kind] or string.upper(plan.kind)
				local text = if plan.locked then "⚠️ DODGE THE RING! " .. label .. " " .. ARROWS[b] else "⚠️ " .. label .. " INCOMING " .. ARROWS[b]
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
	local wantRest = restOn and srv.loaded and phase == "DAY"
	if restBtn.Visible ~= wantRest then
		restBtn.Visible = wantRest
		applyLayout()
	end
	chip.Visible = srv.loaded
	local chipText
	if resting then
		chipText = if rest.source == "idle" then "💤 Dozing by the fire · the manor waits" else "☕ Resting by the fire · the manor waits"
	else
		chipText = Nightfall.chipText(bands, night)
	end
	if chip.Text ~= chipText then chip.Text = chipText end
	local btnText = if resting then "▶ Up" elseif rest.pending then "☕ …" else "☕ Rest"
	if restBtn.Text ~= btnText then restBtn.Text = btnText end

	-- Cards: the first State push is the loaded signal. The first card of a session is quiet (a returning
	-- player is told where they are, not congratulated for an old night). A new band after that is
	-- announced back in the safehouse, once the server's own "YOU GOT OUT" toast has cleared.
	if srv.loaded then
		if announcer.highest == 0 then
			EnvBands.announce(announcer, bandIdx)
			local b = bands[bandIdx]
			showCard(b.emoji .. " " .. string.upper(b.name), "night " .. tostring(night), false)
		elseif phase == "DAY" and dayFor >= 1.2 and EnvBands.announce(announcer, bandIdx) then
			local b = bands[bandIdx]
			if b.celebrate then
				showCard(b.emoji .. " THE " .. string.upper(b.name) .. " RISES", "night " .. tostring(night) .. " is waiting", true)
			else
				showCard(b.emoji .. " " .. string.upper(b.name), "night " .. tostring(night) .. " is waiting", false)
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken frame must not flood the output
		warn("[Nightwatch] haunt frame error: " .. tostring(err))
	end
end)
