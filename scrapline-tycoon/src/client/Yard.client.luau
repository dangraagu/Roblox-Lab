-- SCRAPLINE TYCOON — the yard around your line. Client only (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads the highest product the line has shipped this run (`tier` in the owner's own State payload: the
--     game's own progress, never a timer) and glides the environment bands in Config.Env (EnvBands): lighting,
--     atmosphere, stars, post-fx, scenery, critters and weather, with a 1.5 s half-life (fade 0: a band arrives
--     when its product ships); after a Recycle it SNAPS back to the Junkyard under the recycle's white flash;
--   * draws the belt items on every line near the camera from LineState (the public flow rule, Line.reach), and
--     animates the machines on the player's own plot;
--   * plays the lift-off of any plot's first Rocket from the server's Announce;
--   * runs the rare hazards (Hazards: the crane drops something) and ☕ Break (Rest), and knocks the local
--     character on a hit. The ground is continuous: a hit costs a stumble and nothing else.
--
-- Why all of it is client-side, and why that is safe (+1 Jump's split): it is cosmetic, or it only ever harms the
-- local player, whose character physics the client already owns. The server does not know hazards or rest exist;
-- this script NEVER fires a remote and never writes a part the server built. Rest never becomes an exploit: it
-- pauses only hazards (their clock freezes, never resets); the line earns the same whether you rest or not, and
-- the jam clock does not freeze. Budgets are capped in code and measured headless (check_scraplinetycoon_yard).

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
local YardArt = require(ReplicatedStorage:WaitForChild("YardArt"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local HudLayout = require(ReplicatedStorage:WaitForChild("HudLayout"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local PlotGeom = require(ReplicatedStorage:WaitForChild("PlotGeom"))
local Line = require(ReplicatedStorage:WaitForChild("Line"))

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
		warn("[ScraplineYard] Config.Env.Bands is invalid (" .. tostring(err) .. "); the sky stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[ScraplineYard] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[ScraplineYard] Config.Rest is invalid (" .. tostring(restErr) .. "); Break is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

--============================================================================ the local world + lighting rig
local folder = Instance.new("Folder")
folder.Name = "ScraplineLocalYard"
folder.Parent = workspace
local art = YardArt.new(folder, rand, Config, EnvBands, PlotGeom)

-- Reuse the server's Fx.applyLighting objects by name, so the client takes over from exactly the values the
-- server set instead of stacking a second Atmosphere on top.
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
	sky = rig("Sky", "ScraplineSky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
pcall(function() (targets.sky :: any).CelestialBodiesShown = true end)

local written: { [Instance]: { [string]: any } } = {}
local lightingWrites = 0 -- measured by the headless yard check (a new band must glide, not snap)
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

--============================================================================ UI: band chip, ☕ Break (column slot 2), warning, title card
local gui = Instance.new("ScreenGui")
gui.Name = "ScraplineYard"
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
chip.BackgroundColor3 = Color3.fromRGB(26, 24, 30)
chip.BackgroundTransparency = 0.25
chip.BorderSizePixel = 0
chip.Parent = root
corner(chip, 10)
local chipText = textIn(chip, "ChipText", Enum.Font.GothamBold, Color3.fromRGB(240, 236, 228), 17)
chipText.Text = bands[1].emoji .. " " .. bands[1].name

local slot = Instance.new("Frame")
slot.Name = "BreakSlot"
slot.BackgroundTransparency = 1
slot.BorderSizePixel = 0
slot.Parent = root
local restBtn = Instance.new("TextButton")
restBtn.Name = "BreakButton"
restBtn.Size = UDim2.fromScale(1, 1)
restBtn.BackgroundColor3 = Color3.fromRGB(110, 90, 70)
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

-- the hazard warning: amber-on-dark, never red (red is the ring's alone)
local warningPanel = Instance.new("Frame")
warningPanel.Name = "WarningPanel"
warningPanel.BackgroundColor3 = Color3.fromRGB(70, 40, 20)
warningPanel.BackgroundTransparency = 0.1
warningPanel.BorderSizePixel = 0
warningPanel.Visible = false
warningPanel.Parent = root
corner(warningPanel, 10)
local warningText = textIn(warningPanel, "WarningText", Enum.Font.GothamBlack, Color3.fromRGB(255, 220, 90), 18)

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
cardSub.TextColor3 = Color3.fromRGB(240, 232, 220)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root

local function apply(inst: GuiObject, r: any)
	inst.Position = UDim2.fromOffset(r.x, r.y)
	inst.Size = UDim2.fromOffset(r.w, r.h)
end

-- The line panel lives in Hud.client.luau; when it opens the column moves to its left edge. Read its visibility
-- each frame rather than coupling the two scripts with a shared object.
local function panelOpen(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("ScraplineHud")
	local r = hud and hud:FindFirstChild("Root")
	local panel = r and r:FindFirstChild("LinePanel")
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
	apply(slot, L.slot2)
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

--============================================================================ the owner's own state, and every line's
local latest: any = nil
local lines: { [number]: any } = {} -- [plot k] = { userId, S }
local remotes = ReplicatedStorage:WaitForChild("ScraplineRemotes")
local StateR = remotes:WaitForChild("State") :: RemoteEvent
local FxR = remotes:WaitForChild("Fx") :: RemoteEvent
local LineStateR = remotes:WaitForChild("LineState") :: RemoteEvent
local AnnounceR = remotes:WaitForChild("Announce") :: RemoteEvent

local announcer = EnvBands.newAnnouncer()
local seeded = false -- the first loaded State seeds the announcer quietly (a returning player gets a chip, not a card)
local snapNext = false -- the next lighting write jumps instead of gliding (behind the recycle's flash)
local lastTier = 0 -- a tier that DROPS is a recycle: the sky snaps back (whichever of State and Fx arrives first)
local recycleUntil = -math.huge -- the recycle sequence is playing: hazards hold
local now = 0

StateR.OnClientEvent:Connect(function(st)
	if type(st) ~= "table" then return end
	latest = st
	if not st.loaded then return end
	local idx = EnvBands.indexAt(bands, st.tier or 0)
	if not seeded then
		seeded = true
		EnvBands.announce(announcer, idx)
		return
	end
	if EnvBands.announce(announcer, idx) then
		local b = bands[idx]
		if b.celebrate then
			showCard(b.emoji .. " " .. string.upper(b.name) .. "!", "Your first Rocket is lifting off", true)
		else
			showCard(b.emoji .. " THE " .. string.upper(b.name), "You shipped your first " .. b.product, false)
		end
	end
end)

LineStateR.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	for _, e in payload do
		if type(e) == "table" and type(e.k) == "number" and type(e.st) == "table" then
			local S = {}
			for t = 1, 6 do
				local r = e.st[t] or { 0, 1, 0, 0 }
				S[t] = { n = r[1] or 0, L = r[2] or 1, jam = { r[3] or 0, r[4] or 0 } }
			end
			lines[e.k] = { userId = e.userId, S = S }
		end
	end
end)

local function ownPlot(): number?
	return if latest then latest.plot else nil
end

local function padOf(k: number): Vector3
	local x, z = PlotGeom.toWorld(Config, k, Config.Plot.LaunchPad.x, Config.Plot.LaunchPad.z)
	return Vector3.new(x, Config.World.FloorTopY + Config.Plot.LaunchPad.height, z)
end

AnnounceR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" or type(ev.plot) ~= "number" then return end
	if ev.kind == "liftoff" then
		-- every client animates the same launch from its plot's pad
		art:liftoff(padOf(ev.plot), 6)
		if ev.plot == ownPlot() then
			FxClient.shake(0.6, 0.9)
			FxClient.fovPunch(10, 0.12, 0.8)
		end
	end
end)

FxR.OnClientEvent:Connect(function(ev)
	if type(ev) ~= "table" then return end
	if ev.kind == "recycled" then
		-- the white flash hides the sky's jump back to midday (ClockTime only ever rises within a run)
		FxClient.flash(Color3.fromRGB(255, 255, 255), 0.6, 1.2)
		FxClient.shake(0.5, 0.7)
		recycleUntil = now + Config.Recycle.SequenceSeconds
		-- the old line crumbles: a puff of dust where every machine stood (client-only, 0.9 s, pooled)
		local k = ownPlot()
		if k then
			for t = 1, 6 do
				for m = 1, 2 do
					local mx, mz = PlotGeom.machinePos(Config, t, m)
					local wx, wz = PlotGeom.toWorld(Config, k, mx, mz)
					art:puff(Vector3.new(wx, Config.World.FloorTopY + 3, wz), Color3.fromRGB(150, 140, 125), 0.9, 2.6)
				end
			end
		end
		announcer = EnvBands.newAnnouncer()
		EnvBands.announce(announcer, 1)
	elseif (ev.kind == "build" or ev.kind == "twin") and type(ev.t) == "number" then
		local k = ownPlot()
		if k then
			local mx, mz = PlotGeom.machinePos(Config, ev.t, if ev.kind == "twin" then 2 else 1)
			local wx, wz = PlotGeom.toWorld(Config, k, mx, mz)
			art:puff(Vector3.new(wx, Config.World.FloorTopY + 3, wz), Color3.fromRGB(230, 225, 215), 0.5, 3)
		end
	end
end)

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
local gazing = false -- this script took the camera for ☕ Break
-- the drift is written by frame() while gazing and by nothing else (REVIEW-1 B2: an endless tween outlived the break)
local gazeFrom: { Vector3 }? = nil -- { eye, target } at the chute end
local gazeTo: { Vector3 }? = nil -- ... at the dock end
local gazeT = 0
local GAZE_SECONDS = 14 -- one way, chute to dock (sine in-out), then back
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
	gazeFrom, gazeTo = nil, nil
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

-- ☕ Break: sit down and let the camera drift slowly along your line, chute to dock.
local function gaze()
	local k = ownPlot()
	if hrp == nil or k == nil then return end
	gazing = true
	pcall(function() camera.CameraType = Enum.CameraType.Scriptable end)
	local function world(lx, ly, lz)
		local x, z = PlotGeom.toWorld(Config, k, lx, lz)
		return Vector3.new(x, ly, z)
	end
	gazeFrom = { world(-26, 16, -36), world(-14, 2, 0) }
	gazeTo = { world(26, 16, -36), world(14, 2, 0) }
	gazeT = 0
	pcall(function() camera.CFrame = CFrame.lookAt(world(-26, 16, -36), world(-14, 2, 0)) end)
end

-- One step of the break's drift, from frame(): written only while gazing, so it stops the moment the break does.
local function stepGaze(dt: number)
	if not gazing or gazeFrom == nil or gazeTo == nil then return end
	gazeT += dt
	local a = 0.5 - 0.5 * math.cos(math.pi * gazeT / GAZE_SECONDS) -- 0 -> 1 in 14 s, back to 0 in 28 s
	local f, t = gazeFrom :: { Vector3 }, gazeTo :: { Vector3 }
	pcall(function()
		camera.CFrame = CFrame.lookAt(f[1]:Lerp(t[1], a), f[2]:Lerp(t[2], a))
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
	-- already resting because they stood still (idle rest): pressing Break turns it into a sit-down break
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
	stepGaze(dt)
	if layoutOpen ~= panelOpen() then applyLayout() end
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camPos = camera.CFrame.Position
	local tier = if latest and latest.loaded then (latest.tier or 0) else 0
	local bandIdx = EnvBands.indexAt(bands, tier)
	if tier < lastTier then snapNext = true end
	lastTier = tier

	-- band weights from the tier, smoothed so a new product glides in (a recycle snaps, behind the flash)
	local targetW = EnvBands.weights(bands, tier)
	local snap = snapNext
	for i = 1, #bands do
		local tw = targetW[i] or 0
		if current == nil or snap then
			weights[i] = tw
		else
			weights[i] = EnvBands.approach(weights[i] or 0, tw, dt, Env.HalfLife)
		end
	end

	-- lighting at LightingHz, only on change
	lightAccum += dt
	if current == nil or snap or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		local target = {}
		for _, g in GROUPS do
			target[g] = EnvBands.sample(bands, tier, g)
		end
		if current == nil then
			-- start from the server's preset (band 1) and glide to where this line actually is
			current = {}
			for _, g in GROUPS do
				(current :: any)[g] = EnvBands.sample(bands, 0, g)
			end
		end
		for _, g in GROUPS do
			(current :: any)[g] = if snap then target[g] else EnvBands.approachTable((current :: any)[g], target[g], step, Env.HalfLife)
			writeGroup(targets[g], (current :: any)[g])
		end
		snapNext = false
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
				if YardArt.hasCritter(a.kind) then
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

	-- belt items on every line near the camera; machine animation on your own plot
	local k = ownPlot()
	local view = {}
	for pk, info in lines do
		local cx, cz = PlotGeom.centre(Config, pk)
		local near = info.userId ~= 0 and math.sqrt((cx - camPos.X) ^ 2 + (cz - camPos.Z) ^ 2) < 260
		view[pk] = { S = info.S, own = false, near = near }
	end
	-- your own line comes from your own State (always current; LineState is for everyone else's)
	if k and latest and latest.loaded and type(latest.stations) == "table" then
		local S = {}
		for t = 1, 6 do
			local row = latest.stations[t]
			S[t] = { n = row.n, L = row.L, jam = { row.jamA, row.jamB } }
		end
		view[k] = { S = S, own = true, near = true }
	end
	art:updateBelts(Line, view, dt)
	local built = {}
	if latest and latest.loaded and type(latest.stations) == "table" then
		for t = 1, 6 do
			local row = latest.stations[t]
			built[t] = row ~= nil and row.n > 0
		end
	end
	art:updateMachines(k, built, now)
	art:stepEffects(dt)

	if hrp == nil or hum == nil then
		return
	end
	local rootPart = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- a soft light on the player once night falls, so the yard still reads (one of MaxLights 3)
	if nightLight == nil or nightLight.Parent ~= rootPart then
		local light = Instance.new("PointLight")
		light.Name = "ScraplineNightLight"
		light.Color = Color3.fromRGB(230, 225, 255)
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

	-- hazards: only on your OWN plot (the clock freezes elsewhere, as it does at rest), grounded, not resting, and
	-- never while a machine SPUTTERS (its 15 s clock sends you walking), the lift-off plays or the recycle sequence
	-- plays (canDodge). A standing JAM does not hold them (REVIEW-2 R5): it has no clock, and holding for it froze the
	-- crane for good for anyone who left one jammed twin or rejoined with a saved jam.
	local onOwn = false
	local pos = rootPart.Position
	if k then
		onOwn = PlotGeom.plotAt(Config, pos.X, pos.Z) == k
	end
	local busy = (latest ~= nil and (latest.sputter ~= nil or latest.recycling == true)) or now < recycleUntil
		or (k ~= nil and art:liftoffActive())
	if hazardsOn then
		local look = camera.CFrame.LookVector
		local before = if scheduler.active then scheduler.active.t else nil
		local p = vec(pos)
		-- REVIEW-1 B5: standing ON something that is not a low surface (a machine, the crate, a wall), the ring would
		-- be drawn on the floor below, hidden inside the machine: no aim there, so nothing launches or tracks
		local perched = false
		if grounded and k then
			local plx, plz = PlotGeom.toLocal(Config, k, pos.X, pos.Z)
			perched = pos.Y - PlotGeom.zoneFloor(Config, plx, plz, Hz.PlayerRadius) > Hz.StandAboveFloorMax
		end
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting or not onOwn,
			grounded = grounded,
			kinds = if bandIdx >= Hz.FirstBand then (bands[bandIdx].hazards or {}) else {},
			aim = if perched then nil else p,
			yaw = math.atan2(look.X, look.Z),
			pitch = math.asin(math.clamp(look.Y, -1, 1)),
			canDodge = not busy,
		}, rand)
		if ev and ev.type == "done" then
			art:hideHazard(ev.plan.kind)
		end
		local plan = scheduler.active
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			local groundY = Config.World.FloorTopY
			local zone = if live then Hazards.zone(plan, Hz.PlayerRadius) else nil
			local floorY = groundY
			if zone and k then
				local zlx, zlz = PlotGeom.toLocal(Config, k, zone.x, zone.z)
				floorY = PlotGeom.zoneFloor(Config, zlx, zlz, zone.radius)
			end
			art:showHazard(plan, hp, now, zone, groundY, floorY, Config.World.FloorTopY + Config.Plot.CraneHeight - 1)
			if Hazards.checkHit(plan, before or 0, plan.t, p, Hz.PlayerRadius) then
				plan.hit = true
				-- dead centre under a vertical lane: push toward the middle of the U, which is open floor
				local fallback = { x = 0, y = 0, z = 0 }
				if k then
					local mx, mz = PlotGeom.toWorld(Config, k, 0, -2)
					fallback = { x = mx - pos.X, y = 0, z = mz - pos.Z }
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
				local text = if plan.locked then "⚠️ MOVE! " .. label else "⚠️ CRANE DROP: " .. label .. ". Step out of the red ring"
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
		-- (REVIEW-1 B6) the jam clock does not stop for a break, and the chip says so
		text = if rest.source == "idle" then "💤 Resting: the crane leaves you alone. Your line keeps running."
			else "☕ On break: the crane leaves you alone. Your line keeps running, and machines can still jam."
	else
		local b = bands[bandIdx]
		text = b.emoji .. " " .. b.name
		local nextIdx = EnvBands.nextBand(bands, tier)
		if nextIdx then
			text ..= string.format("  ·  next: %s ship a%s %s", bands[nextIdx].emoji,
				if string.find("AEIOU", string.sub(bands[nextIdx].product, 1, 1), 1, true) then "n" else "", bands[nextIdx].product)
		else
			text ..= "  ·  rockets away!"
		end
	end
	if chipText.Text ~= text then chipText.Text = text end
	local btnText = if resting and rest.source == "manual" then "▶ Carry on" elseif rest.pending then "☕ …" else "☕ Break"
	if restBtn.Text ~= btnText then restBtn.Text = btnText end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken yard must not flood the output
		warn("[ScraplineYard] frame error: " .. tostring(err))
	end
end)

-- For robloxemu/check_scraplinetycoon_yard.luau: read-only counters, never used by the game itself.
local probe = Instance.new("BindableFunction")
probe.Name = "YardProbe"
probe.OnInvoke = function()
	local k = ownPlot()
	return { lightingWrites = lightingWrites, hazardClock = scheduler.clock, hazardNextAt = scheduler.nextAt, hazardsSpawned = scheduler.spawned,
		resting = Rest.isResting(rest), weights = table.clone(weights), gazing = gazing, hazardActive = scheduler.active ~= nil,
		pending = rest.pending, ownItems = if k then art:beltItemCount(k) else 0, liftoff = art:liftoffActive() }
end
probe.Parent = gui
