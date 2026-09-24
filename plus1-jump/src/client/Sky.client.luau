-- +1 JUMP EVERY STEP — the sky you climb into. Client only (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads how high the local character stands and converts it to tiers climbed
--     (Progression.tierProgressAtY) — the game's real progress, never a timer;
--   * blends the environment bands in Config.Env (EnvBands): lighting, atmosphere, stars, post-fx,
--     scenery, critters and weather, smoothed so nothing ever hard-cuts, even on a teleport;
--   * runs the rare hazards (Hazards) and the rest rules (Rest), and knocks the local character
--     off its platform on a hit. The server's fall rescue does the rest; nothing is lost.
--
-- Why all of it is client-side, and why that is safe:
--   * it is cosmetic, or it only ever harms the local player, whose character physics the client
--     already owns. The server does not know hazards or rest exist and trusts nothing from here;
--     this script never fires a remote. Progress is still earned only by the server's platform
--     Touched handler, and a knock is capped (Hazards.MAX_KNOCK_LIFT) so it can never carry a
--     player UP to anything;
--   * everything built here is created by the client and never replicates. It reads only the local
--     character's position, the local camera and Config — no other player's state, nothing the
--     server has not already given this player.
-- Measured budgets and the band table: EYECANDY.md. Headless check: robloxemu/check_plus1_sky.luau.

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
local Progression = require(ReplicatedStorage:WaitForChild("Progression"))
local SkyArt = require(ReplicatedStorage:WaitForChild("SkyArt"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Env, Hz, RestCfg, Tower = Config.Env, Config.Hazards, Config.Rest, Config.Tower
local bands = Env.Bands

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[Plus1Sky] Config.Env.Bands is invalid (" .. tostring(err) .. "); the sky stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[Plus1Sky] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[Plus1Sky] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- ── local world + lighting rig ────────────────────────────────────────────────
local folder = Instance.new("Folder")
folder.Name = "Plus1LocalSky"
folder.Parent = workspace

-- TowerGen: the scenery keeps its cloud decks off the climbing path the server builds from the same seed
local TowerGen = require(ReplicatedStorage:WaitForChild("TowerGen"))
local art = SkyArt.new(folder, rand, Config, Progression, EnvBands, TowerGen)

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
	sky = rig("Sky", "Plus1Sky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
pcall(function() (targets.sky :: any).CelestialBodiesShown = true end)

local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "Plus1RestFocus"
restFocus.FarIntensity = 0.25
restFocus.FocusDistance = 18
restFocus.InFocusRadius = 30
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

-- ── UI: band chip + rest button + warning + title card ─────────────────────────
local MARGIN, GAP = Responsive.MARGIN, 8
-- Mirrors Hud.client.luau's top row so this row sits directly under the counter and between the
-- phone drawers. check_plus1_sky.luau measures that the two never overlap.
local HUD_TOGGLE_H, HUD_TOP_H, HUD_TOP_H_COMPACT = 34, 92, 72
local HUD_SIDE_W = 210
local ROW_W, ROW_H = 460, 34
local REST_W = 104
local MIN_TAP = 44

local gui = Instance.new("ScreenGui")
gui.Name = "Plus1Sky"
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
chip.AnchorPoint = Vector2.new(0, 0)
chip.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
chip.BackgroundTransparency = 0.2
chip.Font = Enum.Font.GothamBold
chip.TextColor3 = Color3.fromRGB(235, 240, 255)
chip.TextScaled = true
chip.Text = "🏛️ Temple Grounds"
chip.Parent = root
corner(chip, 10)
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 17
	c.Parent = chip
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = chip
end

local restBtn = Instance.new("TextButton")
restBtn.Name = "RestButton"
restBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
restBtn.Font = Enum.Font.GothamBlack
restBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restBtn.TextScaled = true
restBtn.Text = "☕ Rest"
restBtn.AutoButtonColor = true
restBtn.Parent = root
corner(restBtn, 10)
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 17
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
cardSub.TextColor3 = Color3.fromRGB(220, 230, 255)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root

local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
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

	local compact = layout.compact
	local topH = if compact then HUD_TOP_H_COMPACT else HUD_TOP_H
	local rowTop = MARGIN + math.max(topH, if compact then touchSize(HUD_TOGGLE_H) else 0) + GAP
	local sideW = Responsive.sideWidth(HUD_SIDE_W, vx, layout)
	local rowW = math.min(ROW_W, rootW - 2 * (MARGIN + sideW + GAP))
	local btnW, rowH = touchSize(REST_W), touchSize(ROW_H)
	rowW = math.max(rowW, btnW + 60)
	local left = (rootW - rowW) / 2

	restBtn.Position = UDim2.fromOffset(left + rowW - btnW, rowTop)
	restBtn.Size = UDim2.fromOffset(btnW, rowH)
	chip.Position = UDim2.fromOffset(left, rowTop)
	chip.Size = UDim2.fromOffset(rowW - btnW - GAP, rowH)
	warning.Position = UDim2.fromOffset(left, rowTop + rowH + GAP)
	warning.Size = UDim2.fromOffset(rowW, math.max(30, math.floor(rowH * 0.8)))

	local cardW = math.min(760, rootW - 2 * MARGIN)
	card.Position = UDim2.fromOffset(rootW / 2, rootH * 0.36)
	card.Size = UDim2.fromOffset(cardW, math.min(70, rootH * 0.14))
	cardSub.Position = UDim2.fromOffset(rootW / 2, rootH * 0.36 + math.min(70, rootH * 0.14) / 2 + 4)
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
		FxClient.flash(Color3.fromRGB(255, 255, 255), 0.45, 0.9)
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

-- ── state ─────────────────────────────────────────────────────────────────────
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local suitLight: PointLight? = nil

local now = 0
local weights: { [number]: number } = {}
local current: { [string]: any }? = nil -- smoothed lighting groups
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat = false -- this script sat the character down (manual rest)
local knockUntil: number? = nil
local settleLeft = 0 -- seconds after the profile has loaded before bands are announced (placement arrives late)
local settleWaited = 0 -- seconds since the character appeared, for the timeout
local SETTLE_SECONDS = 1.5
local SETTLE_TIMEOUT = 15
local boltUntil = 0
local nextBolt = 8
local flashBoost = 0
local frameError = false

local pieceIds: { [string]: boolean } = {}
for _, b in bands do
	for _, id in b.pieces or {} do
		pieceIds[id] = true
	end
end

local spaceIdx = EnvBands.indexOf(bands, Env.SpaceBandId)
local hazardNames = {
	bird = "BIRD", plane = "PLANE", jet = "JET", weatherBalloon = "WEATHER BALLOON", booster = "ROCKET STAGE",
	junk = "SPACE JUNK", astronaut = "ASTRONAUT", asteroid = "ASTEROID", ship = "SPACESHIP", comet = "COMET",
}
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

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	suitLight = nil
	rest = Rest.new()
	sat = false
	restFocus.Enabled = false
	knockUntil = nil
	settleLeft = SETTLE_SECONDS
	settleWaited = 0
	if scheduler.active then
		art:hideHazard(scheduler.active.kind)
		scheduler.active = nil
	end
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

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
		restFocus.Enabled = true
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
	end
end)

-- ── the frame ─────────────────────────────────────────────────────────────────
local function frame(dt: number)
	now += dt
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camCF = camera.CFrame
	local camPos = camCF.Position
	local y = if hrp then (hrp :: BasePart).Position.Y else Tower.BaseY
	-- Continuous progress (tiers climbed) drives every blend: lighting, scenery, critters, weather.
	local p = Progression.tierProgressAtY(y, Tower)
	-- The NAMED band (chip, title cards, which hazards fly) goes by the tier number the server credits
	-- and the HUD and top-10 board show, so "Best: 85 🚀" and the player's own sky never disagree.
	local tierNow = Progression.tierAtY(y - Env.FloorBelowRoot, Tower)
	local bandIdx = EnvBands.indexAt(bands, tierNow)

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
			local s = EnvBands.sample(bands, p, g)
			for _, layer in Env.Layers or {} do
				local lw = EnvBands.layerWeight(layer, p)
				if lw > 0 and layer[g] then
					s = EnvBands.overlay(s, layer[g], lw)
				end
			end
			target[g] = s
		end
		if current == nil then
			-- start from the server's preset (band 1) and glide to where this player actually is
			current = {}
			for _, g in GROUPS do
				(current :: any)[g] = EnvBands.sample(bands, 0, g)
			end
		end
		for _, g in GROUPS do
			(current :: any)[g] = EnvBands.approachTable((current :: any)[g], target[g], step, Env.HalfLife)
		end
		for _, g in GROUPS do
			local props = (current :: any)[g]
			if g == "colorCorrection" and flashBoost > 0.001 then
				props = table.clone(props)
				props.Brightness = (props.Brightness or 0) + flashBoost
			end
			writeGroup(targets[g], props)
		end
	end

	-- scenery, critters, weather
	local pieceW: { [string]: number } = {}
	local critters: { [string]: number } = {}
	local weather: { [string]: number } = {}
	local stormW, nightW = 0, 0
	local boltSpec, boltSpecW = nil, 0
	for i, b in bands do
		local w = weights[i] or 0
		if w > 0.001 then
			for _, id in b.pieces or {} do
				pieceW[id] = math.min(1, (pieceW[id] or 0) + w)
			end
			for _, a in b.ambient or {} do
				if SkyArt.hasCritter(a.kind) then
					critters[a.kind] = (critters[a.kind] or 0) + a.count * w
				end
			end
			if b.weather and SkyArt.hasWeather(b.weather.kind) then
				weather[b.weather.kind] = (weather[b.weather.kind] or 0) + b.weather.rate * w
			end
			if b.lightning then
				stormW += w
				if w > boltSpecW then boltSpec, boltSpecW = b.lightning, w end
			end
			if b.lighting.ClockTime >= 19 then nightW += w end
		end
	end
	for id in pieceIds do
		art:updatePiece(id, pieceW[id] or 0, camPos, now)
	end
	for kind, n in critters do
		critters[kind] = math.floor(n + 0.5)
	end
	art:updateCritters(critters, camPos, dt, now)
	art:updateWeather(weather, camPos)

	-- lightning inside the storm
	if boltUntil > 0 and now >= boltUntil then
		art:flashBolt(camPos, false)
		boltUntil = 0
	end
	flashBoost = EnvBands.approach(flashBoost, 0, dt, 0.08)
	if stormW > 0.35 then
		nextBolt -= dt
		if nextBolt <= 0 then
			local spec = boltSpec :: any
			nextBolt = spec.everyMin + (spec.everyMax - spec.everyMin) * rand()
			art:flashBolt(camPos, true)
			boltUntil = now + 0.14
			flashBoost = 0.3 * stormW
			local props = table.clone((current :: any).colorCorrection)
			props.Brightness = (props.Brightness or 0) + flashBoost
			writeGroup(targets.colorCorrection, props)
		end
	end

	if hrp == nil or hum == nil then
		return
	end
	local root = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- a soft suit light once the sky goes dark, so the tower still reads at night and in space
	if suitLight == nil or suitLight.Parent ~= root then
		local light = Instance.new("PointLight")
		light.Name = "Plus1SuitLight"
		light.Color = Color3.fromRGB(200, 215, 255)
		light.Range = 40
		light.Shadows = false
		light.Brightness = 0
		light.Parent = root
		suitLight = light
	end
	local wantBright = 1.4 * nightW
	if math.abs((suitLight :: PointLight).Brightness - wantBright) > 0.02 then
		(suitLight :: PointLight).Brightness = wantBright
	end

	-- the knock wears off
	if knockUntil and now >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end

	-- grounded / moving, from the Humanoid (the client's own character)
	local fm = (humanoid :: any).FloorMaterial
	local grounded = fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
	-- A seated Humanoid may report FloorMaterial = Air. For the rest rules, a player we sat down is
	-- supported as long as they are not actually falling.
	local supported = grounded
	if sat and not grounded and knockUntil == nil then
		local vy = root.AssemblyLinearVelocity.Y
		supported = math.abs(vy) < 2
	end
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true

	-- rest
	if restOn then
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = scheduler.active ~= nil })
		if ev == "started" and rest.source == "manual" then
			sat = true
			restFocus.Enabled = true
			pcall(function() humanoid.Sit = true end)
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
	end
	local resting = restOn and Rest.isResting(rest)

	-- hazards
	if hazardsOn then
		local look = camCF.LookVector
		local yaw = math.atan2(look.X, look.Z)
		-- the camera's pitch too: a lane must START on screen, not just in front (review 2026-09-17)
		local pitch = math.asin(math.clamp(look.Y, -1, 1))
		local before = if scheduler.active then scheduler.active.t else nil
		local pos = vec(root.Position)
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting,
			grounded = grounded,
			kinds = bands[bandIdx].hazards or {},
			aim = pos,
			yaw = yaw,
			pitch = pitch,
		}, rand)
		if ev and ev.type == "done" then
			art:hideHazard(ev.plan.kind)
		end
		local plan = scheduler.active
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			art:showHazard(plan, hp, now, Hazards.zone(plan, Hz.PlayerRadius))
			if Hazards.checkHit(plan, before or 0, plan.t, pos, Hz.PlayerRadius) then
				plan.hit = true
				local kv = Hazards.knockVelocity(Hz, plan, pos)
				pcall(function() humanoid.PlatformStand = true end)
				root.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				Rest.stop(rest)
				unsit()
				FxClient.shake(0.4, 0.9)
				FxClient.flash(Color3.fromRGB(255, 255, 255), 0.3, 0.35)
			end
			if plan.t <= plan.arriveAt and not plan.hit then
				local b = Hazards.bearing(vec(camPos), vec(look), hp)
				local label = hazardNames[plan.kind] or string.upper(plan.kind)
				local text = if plan.locked then "⚠️ MOVE! " .. label .. " " .. ARROWS[b] else "⚠️ " .. label .. " INCOMING " .. ARROWS[b]
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
		chipText = if rest.source == "idle" then "💤 Idle — the sky leaves you alone" else "☕ Resting — the sky leaves you alone"
	else
		local b = bands[bandIdx]
		chipText = b.emoji .. " " .. b.name
		-- "in N" counts tiers, the unit on the HUD: on Tier 84 space is 1 away
		if spaceIdx and bandIdx < spaceIdx then
			chipText ..= string.format("  ·  🚀 Space in %d", math.max(1, bands[spaceIdx].from - tierNow))
		else
			local nextIdx, remaining = EnvBands.nextBand(bands, tierNow)
			if nextIdx then
				chipText ..= string.format("  ·  %s in %d", bands[nextIdx].emoji, math.max(1, math.ceil(remaining :: number)))
			end
		end
	end
	if chip.Text ~= chipText then chip.Text = chipText end
	local btnText = if resting then "▶ Climb" elseif rest.pending then "☕ …" else "☕ Rest"
	if restBtn.Text ~= btnText then restBtn.Text = btnText end

	-- A new band is announced when the climber STANDS in it: flying past tier 85's height on a jump
	-- that then misses must not play "YOU REACHED SPACE!".
	local standing = (fm ~= nil and fm ~= Enum.Material.Air) or sat
	if settleLeft > 0 or announcer.highest == 0 then
		-- Settling after a spawn. The server places a returning climber on their platform only once
		-- their profile has LOADED (a DataStore call that can take seconds), so a fixed timer is not
		-- enough (review 2026-09-17): wait until leaderstats exist (the load has returned), then
		-- SETTLE_SECONDS for the placement to arrive, and until the character stands at least near the
		-- tier the server credits. A timeout stops a placement that never arrives from silencing the cards.
		-- Review round 2: the timeout counted from the spawn, so a load slower than SETTLE_TIMEOUT (DataStore
		-- queues have no upper bound) showed a returning space climber TEMPLE GROUNDS and then a repeat
		-- "YOU REACHED SPACE!". Both clocks now start when the profile has loaded; before that no card shows
		-- (the sky itself runs from the first frame).
		local stats = player:FindFirstChild("leaderstats")
		local tierValue = stats and stats:FindFirstChild("Tier")
		if tierValue then
			settleLeft -= dt
			settleWaited += dt
		end
		local credited = if tierValue then ((tierValue :: any).Value or 0) else 0
		local placed = tierValue ~= nil and tierNow >= credited - 1
		if (settleLeft <= 0 and placed) or settleWaited >= SETTLE_TIMEOUT then
			settleLeft = 0
			if announcer.highest == 0 then
				-- first sight of the sky this session: say where you are, quietly (no "you reached space!"
				-- fanfare for a player who reached it in an earlier session). The announcer also counts the
				-- band of the tier the server credits them with, so a placement that reaches this client only
				-- after the timeout does not announce, or celebrate, a climb from an earlier session.
				EnvBands.announce(announcer, math.max(bandIdx, EnvBands.indexAt(bands, credited)))
				local b = bands[bandIdx]
				showCard(b.emoji .. " " .. string.upper(b.name), "tier " .. tostring(tierNow), false)
			end
		end
	elseif standing and EnvBands.announce(announcer, bandIdx) then
		local b = bands[bandIdx]
		if b.celebrate then
			showCard("🚀 YOU REACHED SPACE!", b.name .. " · tier " .. tostring(tierNow), true)
		else
			showCard(b.emoji .. " " .. string.upper(b.name), "tier " .. tostring(tierNow), false)
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken sky must not flood the output
		warn("[Plus1Sky] frame error: " .. tostring(err))
	end
end)
