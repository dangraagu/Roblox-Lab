-- METEOR DROP TYCOON — the sky over your plot. Client only (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads the owner's Beacon level from their own State payload (how far into space the plot listens:
--     the game's own progress, never a timer) and blends the environment bands in Config.Env (EnvBands):
--     lighting, atmosphere, stars, post-fx, scenery, critters and weather, gliding with a 1.5 s half-life;
--   * draws the falling streak of every meteor announced on the player's OWN plot (the server only shows
--     the landing glow), and the zips, burn-ups and puffs the Fx remote reports;
--   * runs the rare hazards (Hazards, deep-vein's vertical kinds) and Stargaze (Rest), and knocks the
--     local character on a hit. The ground is continuous: a hit costs about 1.9 s and nothing else.
--
-- Why all of it is client-side, and why that is safe (+1 Jump's split):
--   * it is cosmetic, or it only ever harms the local player, whose character physics the client already
--     owns. The server does not know hazards or rest exist; this script NEVER fires a remote. Stardust is
--     still earned only by the server's pickup poll against the trusted position;
--   * everything built here is created by the client and never replicates. It reads only the local
--     character, the local camera, Config and the player's own State and Fx payloads.
-- Rest never becomes an exploit: it pauses only hazards (their clock freezes, never resets), pickups need
-- walking and walking wakes you, and the Collector's 10-minute timer does not freeze during rest.
-- Budgets are capped in code and measured headless: robloxemu/check_meteordroptycoon_sky.luau.

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
local SkyArt = require(ReplicatedStorage:WaitForChild("SkyArt"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local HudLayout = require(ReplicatedStorage:WaitForChild("HudLayout"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local PlotGeom = require(ReplicatedStorage:WaitForChild("PlotGeom"))
local Meteors = require(ReplicatedStorage:WaitForChild("Meteors"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait(0.1)
	camera = workspace.CurrentCamera
end

local Env, Hz, RestCfg = Config.Env, Config.Hazards, Config.Rest
local bands = Env.Bands

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[MeteorSky] Config.Env.Bands is invalid (" .. tostring(err) .. "); the sky stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[MeteorSky] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[MeteorSky] Config.Rest is invalid (" .. tostring(restErr) .. "); Stargaze is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local function c3(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

--============================================================================ the local world + lighting rig
local folder = Instance.new("Folder")
folder.Name = "MeteorLocalSky"
folder.Parent = workspace
local art = SkyArt.new(folder, rand, Config, EnvBands)

-- Reuse the server's Fx.applyLighting objects by name, so the client takes over from exactly the values
-- the server set instead of stacking a second Atmosphere on top.
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
	sky = rig("Sky", "MeteorSky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
pcall(function() (targets.sky :: any).CelestialBodiesShown = true end)

local written: { [Instance]: { [string]: any } } = {}
local lightingWrites = 0 -- measured by the headless sky check (a purchase must glide, not snap)
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
				value = Color3.fromRGB(math.clamp(math.round(v[1]), 0, 255), math.clamp(math.round(v[2]), 0, 255), math.clamp(math.round(v[3]), 0, 255))
			elseif k == "StarCount" then
				value = math.round(v)
			end
			local ok = pcall(function()
				(inst :: any)[k] = value
			end)
			if ok then
				lightingWrites += 1
				last[k] = if type(v) == "table" then { v[1], v[2], v[3] } else v
			end
		end
	end
end

--============================================================================ UI: band chip, Stargaze, warning, title card
local gui = Instance.new("ScreenGui")
gui.Name = "MeteorSky"
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
local function textIn(parent: Instance, name: string, font, colour: Color3, maxSize: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -16, 1, 0)
	t.Position = UDim2.fromOffset(8, 0)
	t.Font = font
	t.TextColor3 = colour
	t.TextScaled = true
	t.Text = ""
	t.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = t
	return t
end

local chip = Instance.new("Frame")
chip.Name = "BandChip"
chip.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
chip.BackgroundTransparency = 0.25
chip.BorderSizePixel = 0
chip.Parent = root
corner(chip, 10)
local chipText = textIn(chip, "ChipText", Enum.Font.GothamBold, Color3.fromRGB(235, 240, 255), 17)
chipText.Text = bands[1].emoji .. " " .. bands[1].name

local slot = Instance.new("Frame")
slot.Name = "StargazeSlot"
slot.BackgroundTransparency = 1
slot.BorderSizePixel = 0
slot.Parent = root
local restBtn = Instance.new("TextButton")
restBtn.Name = "StargazeButton"
restBtn.Size = UDim2.fromScale(1, 1)
restBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
restBtn.Font = Enum.Font.GothamBlack
restBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restBtn.TextScaled = true
restBtn.Text = "☕ Stargaze"
restBtn.AutoButtonColor = true
restBtn.Parent = slot
corner(restBtn, 10)
do
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 18
	c.Parent = restBtn
end

local warningPanel = Instance.new("Frame")
warningPanel.Name = "WarningPanel"
warningPanel.BackgroundColor3 = Color3.fromRGB(110, 26, 30)
warningPanel.BackgroundTransparency = 0.15
warningPanel.BorderSizePixel = 0
warningPanel.Visible = false
warningPanel.Parent = root
corner(warningPanel, 10)
local warningText = textIn(warningPanel, "WarningText", Enum.Font.GothamBlack, Color3.fromRGB(255, 236, 120), 18)

-- Transient title cards are TextLabels over the play area (never Active, so they cannot eat a tap), placed by
-- HudLayout below the top stack and left of the button column.
local card = Instance.new("TextLabel")
card.Name = "BandCard"
card.BackgroundTransparency = 1
card.Active = false
card.Font = Enum.Font.GothamBlack
card.TextColor3 = Color3.fromRGB(255, 255, 255)
card.TextStrokeTransparency = 0.4
card.TextScaled = true
card.Text = ""
card.Visible = false
card.Parent = root
local cardSub = Instance.new("TextLabel")
cardSub.Name = "BandCardSub"
cardSub.BackgroundTransparency = 1
cardSub.Active = false
cardSub.Font = Enum.Font.GothamBold
cardSub.TextColor3 = Color3.fromRGB(220, 230, 255)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root

local function apply(inst: GuiObject, r: any)
	inst.Position = UDim2.fromOffset(r.x, r.y)
	inst.Size = UDim2.fromOffset(r.w, r.h)
end

-- The upgrade panel lives in Hud.client.luau; when it opens the button column moves to its left edge.
-- Read its visibility each frame rather than coupling the two scripts with a shared object.
local function panelOpen(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("MeteorHud")
	local r = hud and hud:FindFirstChild("Root")
	local panel = r and r:FindFirstChild("UpgradePanel")
	return panel ~= nil and (panel :: any).Visible == true
end

local layoutOpen = false
local function applyLayout()
	local v = camera.ViewportSize
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, topLeft = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and topLeft ~= nil then topLeft.Y else 0
	end
	layoutOpen = panelOpen()
	local L = HudLayout.compute(Responsive, v.X, v.Y, UserInputService.TouchEnabled, inset, layoutOpen)
	uiScale.Scale = L.scale
	root.Size = UDim2.fromScale(1 / L.scale, 1 / L.scale)
	apply(chip, L.chip)
	apply(slot, L.stargazeBtn)
	apply(warningPanel, L.warning)
	apply(card, L.card)
	apply(cardSub, L.cardSub)
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
		FxClient.flash(Color3.fromRGB(255, 240, 200), 0.35, 0.8)
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

--============================================================================ the owner's own state
local latest: any = nil -- the newest State payload for this player
local remotes = ReplicatedStorage:WaitForChild("MeteorRemotes")
local StateR = remotes:WaitForChild("State") :: RemoteEvent
local FxR = remotes:WaitForChild("Fx") :: RemoteEvent

local announcer = EnvBands.newAnnouncer()
local seeded = false -- the first loaded State seeds the announcer quietly (a returning player gets a chip, not a card)
StateR.OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then return end
	latest = st
	if not st.loaded then return end
	local idx = EnvBands.indexAt(bands, st.beacon or 0)
	if not seeded then
		seeded = true
		EnvBands.announce(announcer, idx)
		return
	end
	if EnvBands.announce(announcer, idx) then
		local b = bands[idx]
		if b.celebrate then
			showCard(b.emoji .. " " .. string.upper(b.name) .. "!", "A Falling Star is coming to your plot", true)
		else
			showCard(b.emoji .. " " .. string.upper(b.name), "Beacon " .. tostring(st.beacon), false)
		end
	end
end)

local function ownPlot(): number?
	return if latest then latest.plot else nil
end

--============================================================================ meteor effects on the player's own plot
local streakDir = nil
do
	local a = math.rad(Config.Meteors.StreakTiltDegrees)
	streakDir = Vector3.new(math.sin(a) * 0.6, math.cos(a), math.sin(a) * 0.8).Unit
end
local watched: { [Instance]: boolean } = {}
local watchedFolder: Instance? = nil
local function onMeteorAdded(p: Instance)
	if not p:IsA("BasePart") then return end
	local name = p.Name
	if string.sub(name, 1, 9) ~= "Incoming_" then return end
	if watched[p] then return end
	watched[p] = true
	local to = (p :: BasePart).Position
	if name == "Incoming_Star" then
		art:streak(to + Vector3.new(0, 60, 0), to + Vector3.new(0, 2.2, 0), Config.Meteors.StarFallSeconds, c3(Config.Rarities.StarColor), Config.Meteors.MaxStreakTrails, true)
	else
		local rarity = string.lower(string.sub(name, 10))
		local def = Config.Rarities.Defs[rarity]
		local colour = if def then c3(def.color) else Color3.fromRGB(255, 255, 255)
		art:streak(to + streakDir * Config.Meteors.StreakHeight, to + Vector3.new(0, 1, 0), Config.Meteors.FallSeconds, colour, Config.Meteors.MaxStreakTrails, false)
	end
end
local function watchOwnPlot()
	local k = ownPlot()
	if k == nil then return end
	local plots = workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. k)
	local mf = plot and plot:FindFirstChild("Meteors")
	if mf == nil or mf == watchedFolder then return end
	watchedFolder = mf
	table.clear(watched)
	mf.ChildAdded:Connect(function(c)
		if watchedFolder == mf then onMeteorAdded(c) end
	end)
end

local function smelterMouth(): Vector3?
	local k = ownPlot()
	if k == nil then return nil end
	local x, z = PlotGeom.toWorld(Config, k, 0, -3.6)
	return Vector3.new(x, Config.World.DiscTopY + 3, z)
end

FxR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	if ev.kind == "zip" then
		local to = smelterMouth()
		local def = Config.Rarities.Defs[ev.rarity or "common"]
		if to and type(ev.x) == "number" then
			local colour = if def then c3(def.color) else Color3.fromRGB(255, 255, 255)
			if ev.instant then
				art:puff(Vector3.new(ev.x, (ev.y or 1) + 1, ev.z), colour, 0.5, 3)
			else
				art:zip(Vector3.new(ev.x, ev.y or 1, ev.z), to, colour)
			end
		end
	elseif ev.kind == "burn" and type(ev.x) == "number" then
		art:puff(Vector3.new(ev.x, Config.World.DiscTopY + 90, ev.z), Color3.fromRGB(255, 200, 120), 0.6, 2.5)
	elseif (ev.kind == "dish" or ev.kind == "bounce") and type(ev.x) == "number" then
		local def = Config.Rarities.Defs[ev.rarity or "common"]
		local colour = if ev.kind == "dish" and def then c3(def.color) else Color3.fromRGB(200, 200, 200)
		art:puff(Vector3.new(ev.x, Config.World.DiscTopY + 1, ev.z), colour, 0.4, if ev.kind == "dish" then 1.8 else 2.6)
	end
end)

--============================================================================ state
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local nightLight: PointLight? = nil

local now = 0
local weights: { [number]: number } = {}
local current: { [string]: any }? = nil
local lightAccum = 0
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat = false
local satAt = 0
local SIT_SETTLE_SECONDS = 1.0 -- a Humanoid sat without a seat drops onto the floor for ~0.3 s (plus1-jump, Studio 2026-09-27)
local knockUntil: number? = nil
local gazing = false -- this script took the camera for Stargaze
local frameError = false

local pieceIds: { [string]: boolean } = {}
for _, b in bands do
	for _, id in b.pieces or {} do
		pieceIds[id] = true
	end
end

local function vec(v: Vector3)
	return { x = v.X, y = v.Y, z = v.Z }
end

local function releaseCamera()
	if gazing then
		gazing = false
		pcall(function() camera.CameraType = Enum.CameraType.Custom end)
	end
end

local function unsit()
	if sat and hum then
		pcall(function() (hum :: Humanoid).Sit = false end)
	end
	sat = false
	releaseCamera()
end

-- Stargaze: sit down on your plot and let the camera tilt slowly up to your band's sky piece.
local function gaze()
	if hrp == nil then return end
	gazing = true
	pcall(function() camera.CameraType = Enum.CameraType.Scriptable end)
	local from = (hrp :: BasePart).Position + Vector3.new(0, 4, 0)
	local k = ownPlot()
	local out = Vector3.new(0, 0, 1)
	if k then
		local _, _, ux, uz = PlotGeom.centre(Config, k)
		out = Vector3.new(ux, 0, uz)
	end
	local lookAt = from + out * 60 + Vector3.new(0, 90, 0)
	pcall(function()
		local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		TweenService:Create(camera, info, { CFrame = CFrame.lookAt(from - out * 10, lookAt) }):Play()
	end)
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	nightLight = nil
	rest = Rest.new()
	sat = false
	releaseCamera()
	knockUntil = nil
	if scheduler.active then
		art:hideHazard(scheduler.active.kind)
		scheduler.active = nil
	end
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

restBtn.Activated:Connect(function()
	if not restOn then return end
	-- already resting because they stood still (idle rest): the button still says Stargaze, and pressing it
	-- turns the idle rest into a stargaze (sit, tilt the camera up) instead of ending it
	if Rest.isResting(rest) and rest.source == "idle" then
		rest.source = "manual"
		sat = true
		satAt = now
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
		gaze()
		return
	end
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
		satAt = now
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
		gaze()
	end
end)

--============================================================================ the frame
local function frame(dt: number)
	now += dt
	if layoutOpen ~= panelOpen() then applyLayout() end
	watchOwnPlot()
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camPos = camera.CFrame.Position
	local L = if latest and latest.loaded then (latest.beacon or 0) else 0
	local bandIdx = EnvBands.indexAt(bands, L)

	-- band weights from the Beacon level, smoothed so every purchase near a seam glides a visible step
	local targetW = EnvBands.weights(bands, L)
	for i = 1, #bands do
		local tw = targetW[i] or 0
		if current == nil then
			weights[i] = tw
		else
			weights[i] = EnvBands.approach(weights[i] or 0, tw, dt, Env.HalfLife)
		end
	end

	-- lighting at LightingHz, only on change
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		local target = {}
		for _, g in GROUPS do
			target[g] = EnvBands.sample(bands, L, g)
		end
		if current == nil then
			-- start from the server's preset (band 1) and glide to where this plot actually is
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

	-- scenery, critters, weather
	local pieceW: { [string]: number } = {}
	local critters: { [string]: number } = {}
	local weather: { [string]: number } = {}
	local nightW = 0
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
			if b.weather and Env.Weather[b.weather.kind] then
				weather[b.weather.kind] = (weather[b.weather.kind] or 0) + b.weather.rate * w
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
	art:stepEffects(dt)

	if hrp == nil or hum == nil then
		return
	end
	local rootPart = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- a soft light on the player once night falls, so the plot still reads (one of MaxLights 3)
	if nightLight == nil or nightLight.Parent ~= rootPart then
		local light = Instance.new("PointLight")
		light.Name = "MeteorNightLight"
		light.Color = Color3.fromRGB(210, 220, 255)
		light.Range = 30
		light.Shadows = false
		light.Brightness = 0
		light.Parent = rootPart
		nightLight = light
	end
	local wantBright = 1.2 * nightW
	if math.abs((nightLight :: PointLight).Brightness - wantBright) > 0.02 then
		(nightLight :: PointLight).Brightness = wantBright
	end

	-- the knock wears off
	if knockUntil and now >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end

	local fm = (humanoid :: any).FloorMaterial
	local grounded = fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
	local supported = grounded
	if sat and not grounded and knockUntil == nil then
		local vy = rootPart.AssemblyLinearVelocity.Y
		supported = math.abs(vy) < 2 or (now - satAt) < SIT_SETTLE_SECONDS
	end
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true

	-- rest
	if restOn then
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = scheduler.active ~= nil })
		if ev == "started" and rest.source == "manual" then
			sat = true
			satAt = now
			pcall(function() humanoid.Sit = true end)
			gaze()
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
	end
	local resting = restOn and Rest.isResting(rest)

	-- hazards: only on your OWN plot (the clock freezes elsewhere, as it does at rest), grounded, not resting,
	-- and never during the Falling Star (from its grant until it is caught: deep-vein's canDodge hold)
	local onOwn = false
	local k = ownPlot()
	local pos = rootPart.Position
	if k then
		onOwn = PlotGeom.plotAt(Config, pos.X, pos.Z) == k
	end
	local starSequence = latest ~= nil and latest.star == 1
	if hazardsOn then
		local look = camera.CFrame.LookVector
		local before = if scheduler.active then scheduler.active.t else nil
		local p = vec(pos)
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting or not onOwn,
			grounded = grounded,
			kinds = if bandIdx >= Hz.FirstBand then (bands[bandIdx].hazards or {}) else {},
			aim = p,
			yaw = math.atan2(look.X, look.Z),
			pitch = math.asin(math.clamp(look.Y, -1, 1)),
			canDodge = not starSequence,
		}, rand)
		if ev and ev.type == "done" then
			art:hideHazard(ev.plan.kind)
		end
		local plan = scheduler.active
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			local groundY = Config.World.DiscTopY
			local zone = if live then Hazards.zone(plan, Hz.PlayerRadius) else nil
			-- drawn up to the pad (or a machine's base) it overlaps, never hidden under it (REVIEW-1)
			local floorY = groundY
			if zone and k then
				local zlx, zlz = PlotGeom.toLocal(Config, k, zone.x, zone.z)
				floorY = PlotGeom.zoneFloor(Config, zlx, zlz, zone.radius)
			end
			art:showHazard(plan, hp, now, zone, groundY, floorY)
			if Hazards.checkHit(plan, before or 0, plan.t, p, Hz.PlayerRadius) then
				plan.hit = true
				-- dead centre under a vertical lane: push toward the plot's centre side, which is always open ground
				local fallback = { x = 0, y = 0, z = 0 }
				if k then
					local cx, cz = PlotGeom.centre(Config, k)
					fallback = { x = cx - pos.X, y = 0, z = cz - pos.Z }
				end
				local kv = Hazards.knockVelocity(Hz, plan, p, fallback)
				pcall(function() humanoid.PlatformStand = true end)
				rootPart.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				Rest.stop(rest)
				unsit()
				FxClient.shake(0.4, 0.8)
			end
			if live and not plan.hit then
				local label = Hz.Kinds[plan.kind].label or string.upper(plan.kind)
				local text = if plan.locked then "⚠️ MOVE! " .. label else "⚠️ " .. label .. " INCOMING: step out of the red ring"
				if warningText.Text ~= text then warningText.Text = text end
				warningPanel.Visible = true
			else
				warningPanel.Visible = false
			end
		else
			warningPanel.Visible = false
		end
	end

	-- the chip and the button
	local text
	if resting then
		local awake = if latest and (latest.awake or -1) >= 0 then ". Collector awake " .. Meteors.clock(latest.awake) else ""
		text = if rest.source == "idle" then "💤 Resting: the sky leaves you alone" .. awake
			else "☕ Stargazing: the sky leaves you alone" .. awake
	else
		local b = bands[bandIdx]
		text = b.emoji .. " " .. b.name
		local nextIdx, remaining = EnvBands.nextBand(bands, L)
		if nextIdx then
			local n = math.max(1, math.ceil(remaining :: number))
			text ..= string.format("  ·  %s %s in %d level%s", bands[nextIdx].emoji, bands[nextIdx].name, n, if n == 1 then "" else "s")
		else
			text ..= "  ·  Beacon " .. tostring(L)
		end
	end
	if chipText.Text ~= text then chipText.Text = text end
	local btnText = if resting and rest.source == "manual" then "▶ Carry on" elseif rest.pending then "☕ …" else "☕ Stargaze"
	if restBtn.Text ~= btnText then restBtn.Text = btnText end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken sky must not flood the output
		warn("[MeteorSky] frame error: " .. tostring(err))
	end
end)

-- For robloxemu/check_meteordroptycoon_sky.luau: read-only counters, never used by the game itself.
local probe = Instance.new("BindableFunction")
probe.Name = "MeteorSkyProbe"
probe.OnInvoke = function()
	return { lightingWrites = lightingWrites, hazardClock = scheduler.clock, hazardsSpawned = scheduler.spawned,
		resting = Rest.isResting(rest), weights = table.clone(weights), gazing = gazing, hazardActive = scheduler.active ~= nil,
		pending = rest.pending }
end
probe.Parent = gui
