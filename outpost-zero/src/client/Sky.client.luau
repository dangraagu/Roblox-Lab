-- OUTPOST ZERO — the sky over your city. Client only (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads the owner's population from their own State payload (the city's own progress, never a timer) and
--     blends the six environment bands in Config.Env (EnvBands): lighting, atmosphere, stars, post-fx, scenery,
--     critters and weather, gliding with a 1.5 s half-life; Storm Front's silent lightning at most once per 3 s;
--   * flies a copy of the Grand Airship in whenever any city in the server opens its Skyport (Announce), and shows
--     the owner's title cards (band, airship, docking, a complete skyline);
--   * runs the rare hazards (Hazards, vertical kinds) and the ☕ Break (Rest), and knocks the local character on a
--     hit. A hit costs about 1.9 s and nothing else.
--
-- Why all of it is client-side, and why that is safe (+1 Jump's split):
--   * it is cosmetic, or it only ever harms the local player, whose character physics the client already owns. The
--     server does not know hazards or breaks exist, and there is no client -> server remote to fire at all;
--   * everything built here is created by the client and never replicates. It reads only the local character, the
--     local camera, Config and the player's own State / Fx payloads and the public Announce.
-- A break never becomes an exploit: it pauses only hazards (their clock freezes, never resets); income depends only
-- on population and the Orders, and the Orders keep counting down during a break.
-- Budgets are capped in code and measured headless: robloxemu/check_outpostzero_sky.luau.

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
local City = require(ReplicatedStorage:WaitForChild("City"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))

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
		warn("[OutpostSky] Config.Env.Bands is invalid (" .. tostring(err) .. "); the sky stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[OutpostSky] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[OutpostSky] Config.Rest is invalid (" .. tostring(restErr) .. "); the Break is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

--============================================================================ the local world + lighting rig
local folder = Instance.new("Folder")
folder.Name = "OutpostLocalSky"
folder.Parent = workspace
local art = SkyArt.new(folder, rand, Config, EnvBands)

-- Reuse the server's Fx.applyLighting objects by name, so the client takes over from exactly the values the server
-- set instead of stacking a second Atmosphere on top.
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
	sky = rig("Sky", "OutpostSky"),
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

--============================================================================ UI: band chip, ☕ Break, warning, title card
local gui = Instance.new("ScreenGui")
gui.Name = "OutpostSky"
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
slot.Name = "BreakSlot"
slot.BackgroundTransparency = 1
slot.BorderSizePixel = 0
slot.Parent = root
local restBtn = Instance.new("TextButton")
restBtn.Name = "BreakButton"
restBtn.Size = UDim2.fromScale(1, 1)
restBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
restBtn.Font = Enum.Font.GothamBlack
restBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restBtn.TextScaled = true
restBtn.Text = "☕ Break"
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
local function applyLayout()
	local v = camera.ViewportSize
	local inset = 0
	if not gui.IgnoreGuiInset then
		local ok, topLeft = pcall(function() return GuiService:GetGuiInset() end)
		inset = if ok and topLeft ~= nil then topLeft.Y else 0
	end
	local L = HudLayout.compute(Responsive, v.X, v.Y, UserInputService.TouchEnabled, inset)
	uiScale.Scale = L.scale
	root.Size = UDim2.fromScale(1 / L.scale, 1 / L.scale)
	apply(chip, L.chip)
	apply(slot, L.breakBtn)
	apply(warningPanel, L.warning)
	apply(card, L.card)
	apply(cardSub, L.cardSub)
end
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

-- A title card and a hazard never share the screen (REVIEW-1 F7): on a landscape phone the card sits over the lower
-- middle of the screen, where the avatar's feet and the red ring are. A card that arrives while a hazard is up waits
-- (the newest one) until it has passed; while a card is up, a due hazard is held (the frame's canDodge).
local cardToken = 0
local hazardUp = false -- set by the frame: a hazard is in the air
local queuedCard: { any }? = nil
local function showCard(title: string, sub: string, celebrate: boolean, seconds: number?)
	if hazardUp then
		queuedCard = { title, sub, celebrate, seconds }
		return
	end
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
	task.delay(seconds or (if celebrate then 4.5 else 3), function()
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

--============================================================================ the owner's own state, and the server's news
local latest: any = nil -- the newest State payload for this player
local remotes = ReplicatedStorage:WaitForChild("CityRemotes")
local StateR = remotes:WaitForChild("State") :: RemoteEvent
local FxR = remotes:WaitForChild("Fx") :: RemoteEvent
local AnnounceR = remotes:WaitForChild("Announce") :: RemoteEvent

local now = 0 -- the frame clock (seconds since this script started)
local airshipCardAt = -math.huge
local announcer = EnvBands.newAnnouncer()
local seeded = false -- the first loaded State seeds the announcer quietly (a returning player gets a chip, not a card)
local shelfSet = 0
StateR.OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then return end
	latest = st
	if not st.loaded then return end
	if st.shelf and st.shelf ~= shelfSet then
		shelfSet = st.shelf
		local cx, cz = City.shelfCentre(Config, st.shelf)
		art:setShelf(CFrame.lookAt(Vector3.new(cx, 0, cz), Vector3.new(0, 0, 0)))
	end
	local idx = EnvBands.indexAt(bands, st.population or 0)
	if not seeded then
		seeded = true
		EnvBands.announce(announcer, idx)
		return
	end
	if EnvBands.announce(announcer, idx) then
		local b = bands[idx]
		local dist = Config.Districts[idx]
		if b.celebrate then
			-- the airship's own card (Fx "airship", sent just before this State) already said it
			if now - airshipCardAt > 5 then
				showCard(b.emoji .. " " .. string.upper(b.name) .. " · ⚓ SKYPORT OPEN!", "The Grand Airship is coming", true)
			end
		else
			showCard(b.emoji .. " " .. string.upper(b.name), (if dist then dist.name .. " is open" else ""), false)
		end
	end
end)

FxR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	if ev.kind == "moored" then
		-- the brag moment: white flash, FOV punch, camera shake, and the card
		FxClient.flash(Color3.fromRGB(255, 255, 255), 0.5, 1.0)
		FxClient.fovPunch(10, 0.12, 0.7)
		FxClient.shake(0.5, 0.9)
		showCard("⚓ THE GRAND AIRSHIP HAS DOCKED!", "Moored over your Town Hall, for the whole server to see", false, 5)
	elseif ev.kind == "complete" then
		FxClient.flash(Color3.fromRGB(255, 240, 200), 0.5, 1.0)
		FxClient.fovPunch(10, 0.12, 0.7)
		FxClient.shake(0.4, 0.8)
		showCard("👑 SKYLINE COMPLETE!", "Every lot at " .. Config.Economy.MaxStoreys .. " storeys: the Crown Spire lights up", false, 6)
	elseif ev.kind == "airship" then
		airshipCardAt = now
		showCard("🏮 LANTERN DUSK · ⚓ SKYPORT OPEN!", "The Grand Airship is coming", true)
	end
end)

local flights = 0 -- drawn flights, for the headless check
local flightShelf: number? = nil -- the shelf the drawn flight is mooring at
AnnounceR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" or ev.kind ~= "airship" or type(ev.mast) ~= "table" then return end
	local mast = Vector3.new(ev.mast[1], ev.mast[2], ev.mast[3])
	if art:startFlight(mast, tonumber(ev.seconds) or Config.Airship.FlightSeconds, ev.nose) then
		flights += 1
		flightShelf = tonumber(ev.shelf)
	end
end)

-- the hand-over: the copy holds its last pose until the server's moored airship is on that shelf here (round 2, B2)
local function mooredOn(k: number?): boolean
	local folder = workspace:FindFirstChild("Shelves")
	local shelf = if folder and k then folder:FindFirstChild("Shelf_" .. tostring(k)) else nil
	return shelf ~= nil and shelf:FindFirstChild("Airship") ~= nil
end

local function ownShelf(): number?
	return if latest then latest.shelf else nil
end

--============================================================================ state
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local nightLight: PointLight? = nil

local weights: { [number]: number } = {}
local current: { [string]: any }? = nil
local lightAccum = 0
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat = false
local satAt = 0
local SIT_SETTLE_SECONDS = 1.0 -- a Humanoid sat without a seat drops onto the floor for ~0.3 s (plus1-jump, Studio 2026-09-27)
local knockUntil: number? = nil
local gazing = false -- this script took the camera for the break
local frameError = false
local lastFlash = -math.huge
local flashOffAt = 0
local flashes = 0

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

-- The break: sit down where you stand and let the camera tilt slowly up to your band's sky piece.
local function gaze()
	if hrp == nil then return end
	gazing = true
	pcall(function() camera.CameraType = Enum.CameraType.Scriptable end)
	local from = (hrp :: BasePart).Position + Vector3.new(0, 4, 0)
	local out = Vector3.new(0, 0, 1)
	local k = ownShelf()
	if k then
		local cx, cz = City.shelfCentre(Config, k)
		local o = Vector3.new(cx, 0, cz)
		if o.Magnitude > 1 then out = o.Unit end
	end
	local lookAt = from + out * 60 + Vector3.new(0, 60, 0)
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
	hazardUp = false -- a queued card shows on the next frame
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

restBtn.Activated:Connect(function()
	if not restOn then return end
	-- already resting because they stood still (idle rest): pressing turns it into a break (sit, tilt the camera up)
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

-- Pressing a lot's BUILD ends a break (DESIGN 7): the server tells the owner about every build it made.
FxR.OnClientEvent:Connect(function(ev)
	if type(ev) == "table" and ev.kind == "build" and (Rest.isResting(rest) or rest.pending) then
		Rest.stop(rest)
		unsit()
	end
end)

-- The hazard hold during the Grand Airship's arrival (the brag can never be knocked): from the title card until
-- HoldAfterSeconds after the mooring (the server's own state).
local function airshipHold(): boolean
	if latest == nil then return false end
	if latest.airship == "flying" or latest.airship == "pending" then return true end
	return latest.airship == "moored" and (latest.airshipLeft or 0) > 0
end

--============================================================================ the frame
local function frame(dt: number)
	now += dt
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camPos = camera.CFrame.Position
	local P = if latest and latest.loaded then (latest.population or 0) else 0
	local bandIdx = EnvBands.indexAt(bands, P)

	-- band weights from the population, smoothed so every purchase near a seam glides a visible step
	local targetW = EnvBands.weights(bands, P)
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
			target[g] = EnvBands.sample(bands, P, g)
		end
		if current == nil then
			-- start from the server's preset (band 1) and glide to where this city actually is
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
			if b.lighting.ClockTime >= 17 then nightW += w end
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
	art:stepFlight(dt)
	if art:flightDocked() and mooredOn(flightShelf) then art:endFlight() end

	-- Storm Front's silent lightning: one distant flash, at most once per LightingMinGap seconds, never full-screen
	if (pieceW.cloudLightning or 0) > 0.5 then
		if now >= flashOffAt and flashOffAt > 0 then
			art:flashLightning(false)
			flashOffAt = 0
		end
		if now - lastFlash >= Env.LightningMinGap and rand() < dt / 2 then
			if art:flashLightning(true) then
				lastFlash = now
				flashOffAt = now + 0.15
				flashes += 1
			end
		end
	elseif flashOffAt > 0 then
		art:flashLightning(false)
		flashOffAt = 0
	end

	if hrp == nil or hum == nil then
		return
	end
	local rootPart = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- a soft light on the player once dusk falls, so the shelf still reads (one of MaxLights 3)
	if nightLight == nil or nightLight.Parent ~= rootPart then
		local light = Instance.new("PointLight")
		light.Name = "OutpostNightLight"
		light.Color = Color3.fromRGB(255, 230, 200)
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

	-- the break
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

	-- hazards: only on your OWN shelf (the clock freezes elsewhere, as it does at rest), grounded, not resting, and
	-- never during the Grand Airship's arrival (deep-vein's canDodge hold)
	local k = ownShelf()
	local pos = rootPart.Position
	local onOwn = k ~= nil and City.shelfAt(Config, pos.X, pos.Z) == k
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
			canDodge = not airshipHold() and not card.Visible and queuedCard == nil,
		}, rand)
		if ev and ev.type == "done" then
			art:hideHazard(ev.plan.kind)
		end
		local plan = scheduler.active
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			local zone = if live then Hazards.zone(plan, Hz.PlayerRadius) else nil
			-- the ring lies on what the player stands on (the rock, a lot's plate, a roof): the root minus its height
			local hip = (humanoid :: any).HipHeight
			local floorY = pos.Y - (if type(hip) == "number" then hip else 2) - rootPart.Size.Y / 2
			art:showHazard(plan, hp, now, zone, floorY)
			if Hazards.checkHit(plan, before or 0, plan.t, p, Hz.PlayerRadius) then
				plan.hit = true
				-- dead centre under a vertical lane: push toward the shelf's centre, which is always open plaza
				local fallback = { x = 0, y = 0, z = 0 }
				if k then
					local cx, cz = City.shelfCentre(Config, k)
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
		hazardUp = scheduler.active ~= nil
		if not hazardUp and queuedCard ~= nil then
			local q = queuedCard :: { any }
			queuedCard = nil
			showCard(q[1], q[2], q[3], q[4])
		end
	end

	-- the chip and the button
	local text
	if rest.pending and not resting then
		-- the real reason it waits (round 2, B4): a hazard inbound, the player in the air, or still walking
		text = if scheduler.active ~= nil then "☕ Break queued: step out of the red ring first"
			elseif not supported then "☕ Break queued: it starts when you land"
			else "☕ Break queued: stand still to sit down"
	elseif resting then
		local orders = if latest and (latest.ordersLeft or 0) > 0 then ". Orders " .. Economy.clock(latest.ordersLeft) else ""
		text = if rest.source == "idle" then "💤 Resting: nothing falls on you" .. orders
			else "☕ On a break: nothing falls on you" .. orders
	else
		local b = bands[bandIdx]
		text = string.format("%s %s · population %s", b.emoji, b.name, Economy.group(P))
		local nd, at = Economy.nextDistrict(Config, P)
		if nd then
			text ..= string.format(" · %s at %s", Config.Districts[nd].name, Economy.group(at :: number))
		end
	end
	if chipText.Text ~= text then chipText.Text = text end
	local btnText = if resting and rest.source == "manual" then "▶ Carry on" elseif rest.pending then "☕ …" else "☕ Break"
	if restBtn.Text ~= btnText then restBtn.Text = btnText end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken sky must not flood the output
		warn("[OutpostSky] frame error: " .. tostring(err))
	end
end)

-- For robloxemu/check_outpostzero_sky.luau: read-only counters, never used by the game itself.
local probe = Instance.new("BindableFunction")
probe.Name = "OutpostSkyProbe"
probe.OnInvoke = function()
	return { lightingWrites = lightingWrites, hazardClock = scheduler.clock, hazardsSpawned = scheduler.spawned,
		resting = Rest.isResting(rest), weights = table.clone(weights), gazing = gazing, hazardActive = scheduler.active ~= nil,
		pending = rest.pending, flights = flights, flightActive = art:flightActive(), flashes = flashes, lastFlash = lastFlash,
		hold = airshipHold() }
end
probe.Parent = gui
