-- FORK TOWER — the tower changes as you climb. Client only (StarterPlayerScripts).
--
-- Every frame, for THIS player only:
--   * reads the player's FLOOR from their own lane (the highest fork the server has built, or the
--     summit) and their altitude inside the section they are climbing, and turns both into floors
--     climbed (Climb.progress). That is the game's real progress; nothing here runs on a timer;
--   * blends the environment bands in Config.Env (EnvBands): lighting, atmosphere, stars, post-fx,
--     scenery walls, far set pieces, critters and weather, smoothed so nothing ever hard-cuts — not
--     even a rebirth from the summit back to the dungeon;
--   * runs the rare hazards (Hazards) behind the fork-pad sanctuary (Climb.gate) and the rest rules
--     (Rest), and knocks the local character off its platform on a hit. The server's fall rescue
--     puts it back on its checkpoint; nothing is lost.
--
-- WHY IT CANNOT GIVE A FORK AWAY. What this script reads: its own character, the camera, Config,
-- leaderstats, and in its OWN lane only the names, positions and sizes of the fork pads, the lobby
-- and summit pads, and each section's exit platform (the `Exit` attribute, which exists only once the
-- door has been chosen). It never reads a door, a sign, the inscription or any attribute a fork
-- carries. At a fork the progress is exactly (floor - 1) whatever else is true, so the world in front
-- of two unread doors depends on the floor number and nothing else (robloxemu/check_forktower_env_secret
-- proves it by playing two worlds whose traps sit on opposite doors and diffing everything drawn here).
--
-- WHY IT IS SAFE TO RUN ON THE CLIENT. It is cosmetic, or it only harms the local player, whose
-- character physics the client already owns. It fires no remote, adds no remote, sets no attribute on
-- anything the server built, and every part it makes is local, anchored and non-collidable,
-- non-queryable and non-touchable. Progress is still earned only by the server's platform Touched
-- handlers, and a knock's lift is capped (Hazards.MAX_KNOCK_LIFT; EnvConfig.spec: below the smallest
-- step), so it can never carry anyone up to anything.
-- Measured budgets and the band table: EYECANDY.md. Headless: robloxemu/check_forktower_env*.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Climb = require(ReplicatedStorage:WaitForChild("Climb"))
local TowerArt = require(ReplicatedStorage:WaitForChild("TowerArt"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Env, Hz, RestCfg = Config.Env, Config.Hazards, Config.Rest
local bands = Env.Bands
local FLOORS = Config.Tower.Floors

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[ForkAmbience] Config.Env.Bands is invalid (" .. tostring(err) .. "); the tower stays as the server lit it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[ForkAmbience] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[ForkAmbience] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- ── local world + lighting rig ────────────────────────────────────────────────
local folder = Instance.new("Folder")
folder.Name = "ForkLocalEnv"
folder.Parent = workspace
local art = TowerArt.new(folder, rand, Config, EnvBands)

-- Reuse the server's Fx.applyLighting objects by name, so the client takes over from exactly the
-- values the server set instead of stacking a second Atmosphere on top.
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
	sky = rig("Sky", "ForkSky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
pcall(function() (targets.sky :: any).CelestialBodiesShown = true end)

local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "ForkRestFocus"
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
			changed = prev == nil or math.abs(prev - v) > 1e-3
		end
		if changed then
			local value: any = v
			if type(v) == "table" then
				value = Color3.fromRGB(math.clamp(math.round(v[1]), 0, 255), math.clamp(math.round(v[2]), 0, 255),
					math.clamp(math.round(v[3]), 0, 255))
			elseif k == "StarCount" then
				value = math.round(v)
			elseif k == "ClockTime" then
				value = Climb.clockOf(v) -- the glide may run past midnight (Climb.nearestClock)
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

-- The values the server's preset left on the rig, read back in band 1's shape, so the first frame
-- glides FROM them instead of jumping to band 1 (Fx.Presets.Fork is not band 1).
local function readRig(): { [string]: any }
	local out = {}
	for _, g in GROUPS do
		local grp = {}
		for k, bv in bands[1][g] do
			local ok, cur = pcall(function() return (targets[g] :: any)[k] end)
			if ok and type(cur) == "number" then
				grp[k] = cur
			elseif ok and cur ~= nil and type(bv) == "table" then
				local okc, r, gg, b = pcall(function() return cur.R, cur.G, cur.B end)
				grp[k] = if okc and type(r) == "number" then { r * 255, gg * 255, b * 255 } else { bv[1], bv[2], bv[3] }
			else
				grp[k] = if type(bv) == "table" then { bv[1], bv[2], bv[3] } else bv
			end
		end
		out[g] = grp
	end
	return out
end

-- ── UI: band chip + rest button (in the HUD's row), title card ──────────────────
-- The HUD owns the layout (Hud.client.luau reserves `AmbienceRow` under the toast and sizes its two
-- slots for touch), so the two scripts can never disagree about where anything goes.
local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("ForkHud", 10)
local hudRoot = hud and hud:WaitForChild("Root", 5)
local row = hudRoot and hudRoot:WaitForChild("AmbienceRow", 5)
local chipSlot = row and row:WaitForChild("ChipSlot", 5)
local restSlot = row and row:WaitForChild("RestSlot", 5)
local cardSlot = row and row:WaitForChild("CardSlot", 5)
if chipSlot == nil or restSlot == nil then
	-- no HUD row (a broken HUD): a plain fallback at the top centre, so the player can still rest
	warn("[ForkAmbience] the HUD's AmbienceRow is missing; using a fallback row.")
	local g = Instance.new("ScreenGui")
	g.Name = "ForkAmbienceFallback"
	g.ResetOnSpawn = false
	g.Parent = playerGui
	row = Instance.new("Frame")
	row.Name = "AmbienceRow"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 90)
	row.Size = UDim2.fromOffset(420, 44)
	row.Parent = g
	chipSlot = Instance.new("Frame")
	chipSlot.Name = "ChipSlot"
	chipSlot.BackgroundTransparency = 1
	chipSlot.Size = UDim2.new(1, -120, 1, 0)
	chipSlot.Parent = row
	restSlot = Instance.new("Frame")
	restSlot.Name = "RestSlot"
	restSlot.BackgroundTransparency = 1
	restSlot.Position = UDim2.new(1, -112, 0, 0)
	restSlot.Size = UDim2.fromOffset(112, 44)
	restSlot.Parent = row
	cardSlot = nil
end
if cardSlot == nil then
	-- no slot from the HUD: under the row
	cardSlot = Instance.new("Frame")
	cardSlot.Name = "CardSlot"
	cardSlot.BackgroundTransparency = 1
	cardSlot.Position = UDim2.new(0, 0, 1, 10)
	cardSlot.Size = UDim2.new(1, 0, 2, 0)
	cardSlot.Parent = row
end

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end
local function capText(inst: Instance, n: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = n
	c.Parent = inst
end

local CHIP_BG = Color3.fromRGB(26, 22, 40)
local WARN_BG = Color3.fromRGB(130, 24, 24)
local chip = Instance.new("TextLabel")
chip.Name = "BandChip"
chip.BackgroundColor3 = CHIP_BG
chip.BackgroundTransparency = 0.2
chip.Font = Enum.Font.GothamBold
chip.TextColor3 = Color3.fromRGB(235, 232, 250)
chip.TextScaled = true
chip.Size = UDim2.fromScale(1, 1)
chip.Text = bands[1].emoji .. " " .. bands[1].name
chip.Parent = chipSlot
corner(chip, 10)
capText(chip, 17)
do
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
restBtn.AutoButtonColor = true
restBtn.Size = UDim2.fromScale(1, 1)
restBtn.Text = "☕ Hvil"
restBtn.Parent = restSlot
corner(restBtn, 10)
capText(restBtn, 17)

-- The title card fills the HUD's card slot: the strip between the HUD and the player's character where
-- there is room, else the chip itself for its few seconds (Hud.client.luau decides; review 2026-09-24).
-- On a plate, so it reads over the world and over the chip alike.
local BANNER_BG_T = 0.18
local banner = Instance.new("Frame")
banner.Name = "BandBanner"
banner.BackgroundColor3 = Color3.fromRGB(34, 26, 18)
banner.BackgroundTransparency = BANNER_BG_T
banner.BorderSizePixel = 0
banner.Size = UDim2.fromScale(1, 1)
banner.ZIndex = 3
banner.Visible = false
banner.Parent = cardSlot
corner(banner, 10)
local card = Instance.new("TextLabel")
card.Name = "BandCard"
card.AnchorPoint = Vector2.new(0.5, 0)
card.BackgroundTransparency = 1
card.Font = Enum.Font.GothamBlack
card.TextColor3 = Color3.fromRGB(255, 236, 190)
card.TextStrokeTransparency = 0.4
card.TextScaled = true
card.Position = UDim2.new(0.5, 0, 0.04, 0)
card.Size = UDim2.new(1, -16, 0.58, 0)
card.ZIndex = 4
card.Text = ""
card.Visible = false
card.Parent = banner
capText(card, 40)
local cardSub = Instance.new("TextLabel")
cardSub.Name = "BandCardSub"
cardSub.AnchorPoint = Vector2.new(0.5, 0)
cardSub.BackgroundTransparency = 1
cardSub.Font = Enum.Font.GothamBold
cardSub.TextColor3 = Color3.fromRGB(225, 222, 245)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Position = UDim2.new(0.5, 0, 0.62, 0)
cardSub.Size = UDim2.new(1, -16, 0.34, 0)
cardSub.ZIndex = 4
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = banner
capText(cardSub, 22)

local function revealShowing(): boolean
	local reveal = hudRoot and hudRoot:FindFirstChild("Reveal")
	return reveal ~= nil and (reveal :: any).Visible == true
end

local cardToken = 0
local pendingCard: { string }? = nil
local function hideCard()
	cardToken += 1 -- a fade still running for the card being hidden finds its token gone
	banner.Visible = false
	card.Visible = false
	cardSub.Visible = false
end
local function showCard(title: string, sub: string)
	-- the Build Reveal card is the summit's celebration; a band card never sits on top of it. It waits
	-- (a rebirth pressed with the card still open announces the dungeon once the card is closed).
	if revealShowing() then
		pendingCard = { title, sub }
		return
	end
	pendingCard = nil
	cardToken += 1
	local mine = cardToken
	card.Text = title
	cardSub.Text = sub
	card.TextTransparency = 0
	cardSub.TextTransparency = 0
	banner.BackgroundTransparency = BANNER_BG_T
	banner.Visible = true
	card.Visible = true
	cardSub.Visible = true
	task.delay(3, function()
		if cardToken ~= mine then return end
		local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tw = TweenService:Create(card, info, { TextTransparency = 1 })
		TweenService:Create(cardSub, info, { TextTransparency = 1 }):Play()
		TweenService:Create(banner, info, { BackgroundTransparency = 1 }):Play()
		tw.Completed:Connect(function()
			if cardToken ~= mine then return end
			hideCard()
		end)
		tw:Play()
	end)
end

-- ── the player's own lane, read at 4 Hz ─────────────────────────────────────────
-- Only pads, their positions and sizes, and the exit platform of a section that exists. Nothing
-- under a Fork folder except its pad; nothing a door or sign carries.
local lane = {
	folder = nil :: Instance?,
	level = 1, summit = false, laneX = nil :: number?,
	forkY = {} :: { [number]: number }, exitY = {} :: { [number]: number },
	pads = {} :: { any },
}
-- Anything new in MY lane (the next fork or the summit when a floor clears, a section when a door is
-- chosen) is scanned on the very next frame, not at the next 4 Hz tick. From the floor clear on, the
-- next fork's read prompt reaches the exit's edge (16 studs; review 2026-09-24), and that frame is
-- when Climb.gate dismisses a hazard still in flight. Only the fact that something arrived is used.
local laneChanged = false
local laneWatch: RBXScriptConnection? = nil
local function padOf(part: Instance): any
	local p = part :: BasePart
	return { x = p.Position.X, y = p.Position.Y + p.Size.Y / 2, z = p.Position.Z, sx = p.Size.X, sz = p.Size.Z }
end
local function scanLane()
	local f = lane.folder
	if f == nil or f.Parent == nil then
		f = nil
		local towers = workspace:FindFirstChild("Towers")
		if towers then
			for _, c in towers:GetChildren() do
				if c:GetAttribute("Owner") == player.UserId then f = c; break end
			end
		end
		lane.folder = f
		lane.exitY = {}
		if laneWatch then
			(laneWatch :: RBXScriptConnection):Disconnect()
			laneWatch = nil
		end
		if f then
			laneWatch = f.DescendantAdded:Connect(function()
				laneChanged = true
			end)
		end
	end
	lane.forkY = {}
	lane.pads = {}
	lane.summit = false
	lane.laneX = nil
	local level = 1
	if f == nil then
		lane.level = 1
		return
	end
	for _, c in f:GetChildren() do
		local n = tonumber(string.match(c.Name, "^Fork_(%d+)$"))
		if n then
			local pad = c:FindFirstChild("ForkPad_" .. n)
			if pad and pad:IsA("BasePart") then
				local info = padOf(pad)
				lane.forkY[n] = info.y
				table.insert(lane.pads, info)
				if n > level then level = n end
			end
		elseif c.Name == "Summit" then
			local pad = c:FindFirstChild("SummitPad")
			if pad and pad:IsA("BasePart") then
				lane.summit = true
				table.insert(lane.pads, padOf(pad))
			end
		elseif c.Name == "LobbyPad" and c:IsA("BasePart") then
			lane.laneX = (c :: BasePart).Position.X
			table.insert(lane.pads, padOf(c))
		else
			local s = tonumber(string.match(c.Name, "^Section_(%d+)$"))
			if s and lane.exitY[s] == nil then
				for _, part in c:GetChildren() do
					if part:IsA("BasePart") and part:GetAttribute("Exit") == true then
						lane.exitY[s] = (part :: BasePart).Position.Y + (part :: BasePart).Size.Y / 2
					end
				end
			end
		end
	end
	-- a section folder that is gone (rebirth rebuilt the lane) takes its exit with it
	for s in lane.exitY do
		if f:FindFirstChild("Section_" .. s) == nil then lane.exitY[s] = nil end
	end
	lane.level = math.min(level, FLOORS)
end

-- ── state ─────────────────────────────────────────────────────────────────────
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local lantern: PointLight? = nil

local now = 0
local weights: { [number]: number } = {}
local current: { [string]: any }? = nil
local lightAccum = 0
local scanAccum = 1
local announced = 0 -- the highest band index announced this run (0 = nothing yet this session)
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat = false
local knockUntil: number? = nil
-- The first title card waits until the profile has LOADED (leaderstats) and the player's lane exists,
-- then 1.5 s more. There is deliberately no timeout: before the lane exists the floor is unknown, and
-- a card shown then would name floor 1's band to a player saved on floor 7 (+1 Jump's slow-load
-- finding, 2026-09-17). Without a lane the chip still shows the dungeon; nothing else waits on this.
local settleLeft = 1.5
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

local hazardNames = {
	bee = "HUMLE", seedpod = "FRØKAPSEL", cog = "TANNHJUL", clockbird = "URVERKSFUGL",
	spark = "KULELYN", debris = "TAKSTEIN", meteor = "METEOR", comet = "KOMET",
}
local ARROWS = { ahead = "▲", left = "◀", right = "▶", behind = "▼" }

local function vec(v3: Vector3)
	return { x = v3.X, y = v3.Y, z = v3.Z }
end

local function unsit()
	if sat and hum then
		pcall(function() (hum :: Humanoid).Sit = false end)
	end
	sat = false
	restFocus.Enabled = false
end

local function dismissHazard()
	if scheduler.active then
		art:hideHazard(scheduler.active.kind)
		scheduler.active = nil
	end
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	lantern = nil
	rest = Rest.new()
	sat = false
	restFocus.Enabled = false
	knockUntil = nil
	dismissHazard()
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
	if character and (hrp == nil or (hrp :: BasePart).Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	scanAccum += dt
	if scanAccum >= 0.25 or laneChanged then
		scanAccum = 0
		laneChanged = false
		scanLane()
	end
	local camCF = camera.CFrame
	local camPos = camCF.Position
	local rootPos = if hrp then (hrp :: BasePart).Position else camPos
	local feetY = rootPos.Y - Env.FloorBelowRoot

	-- Progress (floors climbed) drives every blend; the NAMED floor (the HUD's number) names the band.
	local p = Climb.progress(lane.level, lane.summit, feetY, lane.forkY, lane.exitY, FLOORS)
	local named = Climb.namedFloor(lane.level, lane.summit, FLOORS)
	local bandIdx = EnvBands.indexAt(bands, named - 1)

	-- band weights, smoothed so a rebirth or a rescue glides instead of cutting
	local targetW = EnvBands.weights(bands, p)
	for i = 1, #bands do
		local tw = targetW[i] or 0
		weights[i] = if current == nil then tw else EnvBands.approach(weights[i] or 0, tw, dt, Env.HalfLife)
	end

	-- lighting at LightingHz
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		if current == nil then
			current = readRig()
		end
		for _, g in GROUPS do
			local target = EnvBands.sample(bands, p, g)
			local cur = (current :: any)[g]
			if g == "lighting" and cur.ClockTime ~= nil then
				-- the dial: glide the short way round (a rebirth goes through midnight, not noon)
				cur.ClockTime = Climb.nearestClock(cur.ClockTime, target.ClockTime)
			end
			local props = EnvBands.approachTable(cur, target, step, Env.HalfLife);
			(current :: any)[g] = props
			if g == "colorCorrection" and flashBoost > 0.001 then
				props = table.clone(props)
				props.Brightness = (props.Brightness or 0) + flashBoost
			end
			writeGroup(targets[g], props)
		end
	end

	-- scenery, far pieces, critters, weather
	local pieceW: { [string]: number } = {}
	local critters: { [string]: number } = {}
	local weather: { [string]: number } = {}
	local stormW, darkW = 0, 0
	local boltSpec, boltSpecW = nil, 0
	for i, b in bands do
		local w = weights[i] or 0
		if w > 0.001 then
			for _, id in b.pieces or {} do
				pieceW[id] = math.min(1, (pieceW[id] or 0) + w)
			end
			for _, a in b.ambient or {} do
				if TowerArt.hasCritter(a.kind) then
					critters[a.kind] = (critters[a.kind] or 0) + a.count * w
				end
			end
			if b.weather and TowerArt.hasWeather(b.weather.kind) then
				weather[b.weather.kind] = (weather[b.weather.kind] or 0) + b.weather.rate * w
			end
			if b.lightning then
				stormW += w
				if w > boltSpecW then boltSpec, boltSpecW = b.lightning, w end
			end
			local ct = b.lighting.ClockTime
			if ct >= 18.5 or ct <= 5 then darkW += w end
		end
	end
	local laneX = lane.laneX or camPos.X
	for id in pieceIds do
		art:updatePiece(id, pieceW[id] or 0, camPos, now, laneX, rootPos)
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
	if stormW > 0.35 and boltSpec then
		nextBolt -= dt
		if nextBolt <= 0 then
			local spec = boltSpec :: any
			nextBolt = spec.everyMin + (spec.everyMax - spec.everyMin) * rand()
			art:flashBolt(camPos, true)
			boltUntil = now + 0.14
			flashBoost = 0.3 * stormW
		end
	end

	if hrp == nil or hum == nil then
		return
	end
	local root = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- a soft lantern on the climber in the dark bands, so the tower reads in the dungeon and at night
	if lantern == nil or (lantern :: PointLight).Parent ~= root then
		local light = Instance.new("PointLight")
		light.Name = "ForkLantern"
		light.Color = Color3.fromRGB(255, 214, 170)
		light.Range = 36
		light.Shadows = false
		light.Brightness = 0
		light.Parent = root
		lantern = light
	end
	local wantBright = 1.3 * darkW
	if math.abs((lantern :: PointLight).Brightness - wantBright) > 0.02 then
		(lantern :: PointLight).Brightness = wantBright
	end

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
		supported = math.abs(root.AssemblyLinearVelocity.Y) < 2
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

	-- hazards, behind the sanctuary: the clock runs only while climbing a section, off every pad
	local sanctuary = Climb.inSanctuary(vec(rootPos), lane.pads, Env.Sanctuary.Radius, Env.Sanctuary.Ceiling)
	local climbing = lane.folder ~= nil and not lane.summit and lane.exitY[lane.level] ~= nil
	local gate = Climb.gate({ climbing = climbing, sanctuary = sanctuary, resting = resting })
	local warningText: string? = nil
	if hazardsOn then
		if gate.dismiss and scheduler.active then
			-- on a pad, or the floor cleared (the next read's prompt reaches the exit's edge): the player
			-- may be reading, and nothing flies at a reader
			dismissHazard()
		end
		local look = camCF.LookVector
		local yaw = math.atan2(look.X, look.Z)
		local pitch = math.asin(math.clamp(look.Y, -1, 1))
		local before = if scheduler.active then scheduler.active.t else nil
		local pos = vec(rootPos)
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = not gate.clock,
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
			if gate.hit and Hazards.checkHit(plan, before or 0, plan.t, pos, Hz.PlayerRadius) then
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
				warningText = if plan.locked then "⚠️ FLYTT DEG! " .. label .. " " .. ARROWS[b]
					else "⚠️ " .. label .. " KOMMER " .. ARROWS[b]
			end
		end
	end

	-- A warning ends a title card. Where there is no room for the card above the character it sits ON
	-- the chip, and the chip is where the warning is written (review 2026-09-24).
	if warningText and banner.Visible then
		hideCard()
	end

	-- the chip (the warning takes it over while a hazard comes), the button, the cards
	local chipText
	if warningText then
		chipText = warningText
	elseif resting then
		chipText = if rest.source == "idle" then "💤 Pause — farene lar deg være" else "☕ Hviler — farene lar deg være"
	else
		local b = bands[bandIdx]
		chipText = b.emoji .. " " .. b.name
		local nextIdx, remaining = EnvBands.nextBand(bands, named - 1)
		if nextIdx then
			local n = math.max(1, math.ceil(remaining :: number))
			chipText ..= string.format("  ·  %s om %d %s", bands[nextIdx].emoji, n, if n == 1 then "etasje" else "etasjer")
		end
	end
	if chip.Text ~= chipText then chip.Text = chipText end
	local chipBg = if warningText then WARN_BG else CHIP_BG
	if chip.BackgroundColor3 ~= chipBg then chip.BackgroundColor3 = chipBg end
	local btnText = if resting then "▶ Klatre" elseif rest.pending then "☕ …" else "☕ Hvil"
	if restBtn.Text ~= btnText then restBtn.Text = btnText end

	if pendingCard and not revealShowing() then
		local pc = pendingCard :: { string }
		showCard(pc[1], pc[2])
	end
	-- Title cards: once the player's profile has LOADED (leaderstats) and their lane exists, say where
	-- they are, quietly; then a card for each new band reached this run. A rebirth starts the count over.
	if settleLeft > 0 then
		local stats = player:FindFirstChild("leaderstats")
		if stats and lane.folder then
			settleLeft -= dt
		end
		if settleLeft <= 0 then
			settleLeft = 0
			announced = bandIdx
			local b = bands[bandIdx]
			showCard(b.emoji .. " " .. string.upper(b.name), if lane.summit then "toppen" else "etasje " .. tostring(named))
		end
	elseif bandIdx < announced then
		-- a rebirth: back to the first environment, and the run's cards start again
		announced = bandIdx
		local b = bands[bandIdx]
		showCard(b.emoji .. " " .. string.upper(b.name), "etasje " .. tostring(named))
	elseif bandIdx > announced and grounded then
		announced = bandIdx
		local b = bands[bandIdx]
		showCard(b.emoji .. " " .. string.upper(b.name), if lane.summit then "toppen" else "etasje " .. tostring(named))
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken ambience must not flood the output
		warn("[ForkAmbience] frame error: " .. tostring(err))
	end
end)
