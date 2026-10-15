-- GNOME GARDEN DEFENSE: the garden you see. Client only (StarterPlayerScripts).
--
-- Every frame, for THIS player's own garden:
--   * reads the garden's Progress attribute (waves survived + the share of this wave's bugs already gone: the
--     game's real progress, never a timer) and blends the season bands in Config.Env (EnvBands): lighting,
--     atmosphere, sky, post-fx, scenery, critters and weather, smoothed so nothing hard-cuts, even when a lost
--     chapter sends progress back to the chapter's start;
--   * draws the bugs from the server's 10 Hz GardenTick snapshots, interpolated between ticks;
--   * runs the rare hazards (Hazards, vertical drops) and PAUSE (Rest): a hit knocks the gardener down and
--     dazes them for Config.Hazards.DazeSeconds (the gnome sheet greys out). Nothing else is lost.
--
-- Why all of it is client-side, and why that is safe: it is cosmetic, or it only ever harms the local player
-- (whose character the client owns). The hazard clock runs on garden time (waves and build phases), frozen
-- while paused, held, on the reveal and on the result screens, and in band 1. The server freezes the WHOLE
-- garden on SetPaused, so a pause buys thinking time and nothing else. Everything built here is local and
-- never replicates; it reads only this player's garden, the local character and camera, and Config.
-- Budgets: Config.Budget, enforced in GardenArt, measured by robloxemu/check_gnomegardendefense_env.luau.

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
local PathGen = require(ReplicatedStorage:WaitForChild("PathGen"))
local Sim = require(ReplicatedStorage:WaitForChild("Garden")) -- the pure rules: only Sim.suggestKind is used here
local GardenArt = require(ReplicatedStorage:WaitForChild("GardenArt"))
local Wire = require(ReplicatedStorage:WaitForChild("Wire"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("GardenRemotes")
local PauseEvent = remotes:WaitForChild("SetPaused")
local HereEvent = remotes:WaitForChild("Here")
local TickEvent = remotes:WaitForChild("GardenTick")
local FanfareEvent = remotes:WaitForChild("Fanfare")

local Env, Hz, RestCfg, HC = Config.Env, Config.Hazards, Config.Rest, Config.Hud
local bands = Env.Bands

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[GnomeGarden] Config.Env.Bands is invalid (" .. tostring(err) .. "); the garden keeps the server's light.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then warn("[GnomeGarden] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.") end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then warn("[GnomeGarden] Config.Rest is invalid (" .. tostring(restErr) .. "); PAUSE is OFF.") end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

--============================================================================ local world + lighting rig
local folder = Instance.new("Folder")
folder.Name = "GardenLocal"
folder.Parent = workspace
local art = GardenArt.new(folder, rand, { Config = Config, EnvBands = EnvBands, PathGen = PathGen })

local function rig(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then return existing end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end
local targets = {
	lighting = Lighting,
	atmosphere = rig("Atmosphere", "FxAtmosphere"),
	sky = rig("Sky", "GardenSky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
pcall(function() (targets.sky :: any).CelestialBodiesShown = true end)

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
				value = Color3.fromRGB(math.clamp(math.round(v[1]), 0, 255), math.clamp(math.round(v[2]), 0, 255), math.clamp(math.round(v[3]), 0, 255))
			elseif k == "StarCount" then
				value = math.round(v)
			end
			local ok = pcall(function() (inst :: any)[k] = value end)
			if ok then last[k] = if type(v) == "table" then { v[1], v[2], v[3] } else v end
		end
	end
end

--============================================================================ UI: chip + PAUSE + warning + cards
local MARGIN, GAP = Responsive.MARGIN, HC.Gap
local playerGui = player:WaitForChild("PlayerGui")
local state = playerGui:FindFirstChild("GardenClientState")
if state == nil then
	state = Instance.new("Folder")
	state.Name = "GardenClientState"
	state.Parent = playerGui
end

local gui = Instance.new("ScreenGui")
gui.Name = "GardenSky"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 2
gui.Parent = playerGui
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
local function maxText(inst: Instance, n: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = n
	c.Parent = inst
end

local chip = Instance.new("TextLabel")
chip.Name = "BandChip"
chip.BackgroundColor3 = Color3.fromRGB(24, 34, 26)
chip.BackgroundTransparency = 0.25
chip.Font = Enum.Font.GothamBold
chip.TextColor3 = Color3.fromRGB(240, 250, 230)
chip.TextScaled = true
chip.Text = bands[1].emoji .. " " .. bands[1].name
chip.Parent = root
corner(chip, 10)
maxText(chip, 17)

local pauseBtn = Instance.new("TextButton")
pauseBtn.Name = "PauseButton"
pauseBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
pauseBtn.Font = Enum.Font.GothamBlack
pauseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
pauseBtn.TextScaled = true
pauseBtn.Text = "⏸ PAUSE"
pauseBtn.Parent = root
corner(pauseBtn, 10)
maxText(pauseBtn, 17)

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

local pausedLabel = Instance.new("TextLabel")
pausedLabel.Name = "PausedOverlay"
pausedLabel.AnchorPoint = Vector2.new(0.5, 0.5)
pausedLabel.BackgroundTransparency = 1
pausedLabel.Font = Enum.Font.GothamBlack
pausedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
pausedLabel.TextStrokeTransparency = 0.3
pausedLabel.TextScaled = true
local PAUSED_TEXT = "⏸ PAUSED · move or tap anything to carry on"
pausedLabel.Text = PAUSED_TEXT
pausedLabel.Visible = false
pausedLabel.Parent = root

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
cardSub.TextColor3 = Color3.fromRGB(255, 240, 210)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root

local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local function touchSize(designPx: number): number
	if layout.controlPad <= 0 then return designPx end
	local wanted = math.max(designPx, HC.MinTap)
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
	-- directly under Hud.client's top bar (Config.Hud is the shared geometry)
	local topH = if layout.compact then HC.TopHCompact else HC.TopH
	local rowTop = MARGIN + topH + GAP
	local rowH = touchSize(HC.RowH)
	local btnW = touchSize(HC.PauseW)
	local rowW = math.min(HC.RowW, rootW - 2 * MARGIN)
	rowW = math.max(rowW, btnW + 80)
	local left = (rootW - rowW) / 2
	pauseBtn.Position = UDim2.fromOffset(left + rowW - btnW, rowTop)
	pauseBtn.Size = UDim2.fromOffset(btnW, rowH)
	chip.Position = UDim2.fromOffset(left, rowTop)
	chip.Size = UDim2.fromOffset(rowW - btnW - GAP, rowH)
	warning.Position = UDim2.fromOffset(left, rowTop + rowH + GAP)
	warning.Size = UDim2.fromOffset(rowW, HC.WarnH)
	local cardW = math.min(760, rootW - 2 * MARGIN)
	card.Position = UDim2.fromOffset(rootW / 2, rootH * 0.4)
	card.Size = UDim2.fromOffset(cardW, math.min(70, rootH * 0.14))
	cardSub.Position = UDim2.fromOffset(rootW / 2, rootH * 0.4 + math.min(70, rootH * 0.14) / 2 + 4)
	cardSub.Size = UDim2.fromOffset(cardW, math.min(30, rootH * 0.07))
	pausedLabel.Position = UDim2.fromOffset(rootW / 2, rootH * 0.55)
	pausedLabel.Size = UDim2.fromOffset(cardW, math.min(44, rootH * 0.09))
end
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

-- A season's win and the band it reaches come in the same moment (the boss falls, the progress lands on the
-- band): two cards and two flashes, and the band's card replaced the season's after one frame, so the brag's own
-- line ("The Slug Queen falls!") was never readable (REVIEW-2). Within CARD_MERGE_SECONDS the second one JOINS
-- the first: one card (the season's title and line, the band added to the line when it is another name), one
-- flash. tick(), not this script's frame clock: the Fanfare handler runs between frames.
local CARD_MERGE_SECONDS = 2
local lastFlashAt = -math.huge
local seasonCard: any = nil -- { title, sub, at }: the season's own card
local bandCard: any = nil   -- { name, at }: the band reached last

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
	if celebrate and tick() - lastFlashAt >= CARD_MERGE_SECONDS then
		lastFlashAt = tick()
		FxClient.flash(Color3.fromRGB(255, 236, 170), 0.45, 0.9)
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

--============================================================================ state
local garden: Instance? = nil
local gardenAttempt = -1
local path: any = nil
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local now = 0
local pShown: number? = nil -- smoothed progress
local current: { [string]: any }? = nil
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local primedAttempt = -1 -- the attempt whose first progress the announcer has seen (a new bed is not a reach)
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local knockUntil: number? = nil
local frameError = false
local pathTint = false
local lastTickT = 0
local flashing: { [BasePart]: any } = {} -- gnome tools lit for a moment as they fire
local glowPads: { BasePart } = {}       -- the rims of the pads that glow
local glowIds: { number } = {}          -- which pads those are (their rims are looked up again until found:
local glowScanAt = -math.huge           -- a bed that streams in after the attempt began still glows)
local bedPads: { any } = {}             -- this attempt's pads (PathGen.pads of the replicated path)
local litKey = ""                       -- the taken pads the glow was ranked for ("" = not yet ranked)
local padParts: { [number]: BasePart } = {} -- pad id -> the pad's Part, looked up again until all are found
local padScanAt = -math.huge
local padWas: { [BasePart]: { color: Color3, material: Enum.Material, look: string } } = {}
local GOLD = Color3.fromRGB(255, 196, 60)   -- the pad the gnome sheet is for
local GLOW_A, GLOW_B = Color3.fromRGB(110, 235, 80), Color3.fromRGB(200, 255, 150)
local lastInputAt = -math.huge          -- the gardener's own last input (Here, for the AFK hold)
local lastHereAt = -math.huge
UserInputService.InputBegan:Connect(function() lastInputAt = now end)
UserInputService.TouchTap:Connect(function() lastInputAt = now end)

local pieceIds: { [string]: boolean } = {}
for _, b in bands do
	for _, id in b.pieces or {} do pieceIds[id] = true end
end
local ARROWS = { ahead = "▲", left = "◀", right = "▶", behind = "▼" }

local function vec(v: Vector3)
	return { x = v.X, y = v.Y, z = v.Z }
end

local function findGarden(): Instance?
	local gardens = workspace:FindFirstChild("Gardens")
	if not gardens then return nil end
	for _, g in gardens:GetChildren() do
		if g:GetAttribute("Owner") == player.UserId then return g end
	end
	return nil
end

local function originOf(g: Instance): CFrame
	return CFrame.new(g:GetAttribute("OriginX") or 0, g:GetAttribute("OriginY") or 0, g:GetAttribute("OriginZ") or 0)
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	rest = Rest.new()
	knockUntil = nil
	if scheduler.active then
		art:hideHazard(scheduler.active.kind)
		scheduler.active = nil
	end
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local function serverPaused(): boolean
	return garden ~= nil and garden:GetAttribute("Paused") == true
end

-- a short line where the PAUSED overlay goes (the overlay itself shows while the server says paused)
local noticeText, noticeUntil = "", -math.huge
local function notice(text: string)
	noticeText, noticeUntil = text, now + 2
end

pauseBtn.Activated:Connect(function()
	if not restOn then return end
	if serverPaused() or Rest.isResting(rest) or rest.pending then
		Rest.stop(rest)
		PauseEvent:FireServer(false)
		return
	end
	local grounded, moving = false, false
	if hum then
		local fm = (hum :: any).FloorMaterial
		grounded = fm ~= nil and fm ~= Enum.Material.Air
		local md = (hum :: any).MoveDirection
		moving = (md ~= nil and md.Magnitude > 0.05) or (hum :: any).Jump == true
	end
	-- Walking: a rest would wake 0.4 s later (Rest: any movement wakes), so the garden flickered paused and the
	-- server answered the wake with "Slow down a little" (REVIEW-2). Say what to do instead. (With a hazard on
	-- its way, moving is what the warning asks for: then the press is queued as before.)
	if moving and scheduler.active == nil then
		notice(Config.Text.StandStill)
		return
	end
	local res = Rest.request(rest, RestCfg, { moving = false, grounded = grounded, threat = scheduler.active ~= nil })
	if res == "resting" then
		PauseEvent:FireServer(true)
	end
end)

TickEvent.OnClientEvent:Connect(function(t)
	if type(t) ~= "table" or t.o ~= player.UserId or garden == nil then return end
	if t.a ~= nil and t.a ~= gardenAttempt then return end
	lastTickT = now
	art:setBugs(Wire.unpackBugs(Config, t.b), path, now)
	-- the gnomes that fired this tick flash their tool (a pebble's sling, a lantern's light): no new parts
	if type(t.s) == "table" and garden then
		local bed = (garden :: Instance):FindFirstChild("Bed")
		local gnomes = bed and bed:FindFirstChild("Gnomes")
		for _, pad in t.s do
			local m = gnomes and gnomes:FindFirstChild("Gnome_" .. tostring(pad))
			local tool = m and m:FindFirstChild("Tool")
			if tool and tool:IsA("BasePart") then
				if flashing[tool] == nil then flashing[tool] = { material = tool.Material, color = tool.Color } end
				tool.Material = Enum.Material.Neon
				tool.Color = Color3.fromRGB(255, 250, 200)
				flashing[tool].untilT = now + 0.12
			end
		end
	end
	-- a seed sparkle where a bug was stopped (one burst per tick: the emitter is shared)
	if type(t.k) == "table" and #t.k > 0 then
		local k = t.k[#t.k]
		local at = art:bugWorldPos(k[1])
		if at == nil and path then
			local x, z = PathGen.posAt(path, 0)
			at = (originOf(garden :: Instance) * CFrame.new(x, 1, z)).Position
		end
		if at then
			local boss = Config.Bugs[k[2]] and Config.Bugs[k[2]].boss
			art:burst(at, if boss then Color3.fromRGB(255, 210, 80) else Color3.fromRGB(170, 255, 120), if boss then 60 else 8)
		end
	end
end)

FanfareEvent.OnClientEvent:Connect(function(f)
	if type(f) ~= "table" or (f.o ~= nil and f.o ~= player.UserId) then return end
	if f.kind == "season" then
		local title, sub
		if f.brag then
			title, sub = "🌕 HARVEST MOON", "The Slug Queen falls!"
		else
			title, sub = "🏆 " .. string.upper(tostring(f.season)) .. " WON", if f.unlock then tostring(f.unlock) .. " unlocked" else ""
		end
		-- the band can be named first (the progress arrived before this): the season's card takes over and carries it
		if bandCard and tick() - bandCard.at < CARD_MERGE_SECONDS and not string.find(string.upper(title), string.upper(bandCard.name), 1, true) then
			sub = if sub == "" then bandCard.name else sub .. "  ·  " .. bandCard.name
		end
		seasonCard = { title = title, sub = sub, at = tick() }
		showCard(title, sub, true)
		if garden then
			local o = originOf(garden :: Instance)
			art:burst((o * CFrame.new(Config.GridW * Config.Tile, 3, Config.GridH * Config.Tile / 2)).Position, Color3.fromRGB(255, 215, 90), 80)
		end
	end
end)

local function bindGarden()
	local g = findGarden()
	if g ~= garden then
		garden = g
		gardenAttempt = -1
	end
	if garden == nil then return end
	local attempt = (garden :: Instance):GetAttribute("Attempt") or 0
	if attempt ~= gardenAttempt then
		gardenAttempt = attempt
		path = PathGen.fromText(Config, (garden :: Instance):GetAttribute("PathCells"))
		local bed = (garden :: Instance):FindFirstChild("Bed")
		art:setOrigin(originOf(garden :: Instance))
		art:clearBugs()
		pathTint = false
		-- the pads that glow are ranked again in the frame (litKey), the pad Parts looked up again (a new bed)
		table.clear(glowPads)
		table.clear(glowIds)
		glowScanAt = -math.huge
		bedPads = if path then PathGen.pads(Config, path) else {}
		litKey = ""
		table.clear(padParts)
		table.clear(padWas)
		padScanAt = -math.huge
		-- a soil puff where a gnome is planted (bound when the attempt is seen; a bed that arrives later goes
		-- without puffs until the next attempt: cosmetic only)
		local gnomes = bed and bed:FindFirstChild("Gnomes")
		if gnomes then
			gnomes.ChildAdded:Connect(function(m)
				if m:IsA("Model") and m.PrimaryPart then
					art:burst((m.PrimaryPart :: BasePart).Position, Color3.fromRGB(140, 100, 60), 14)
				end
			end)
		end
	end
end

-- Night bands keep the path readable: the gravel glows faintly instead of adding lights (the light budget is 3).
local function tintPath(night: boolean)
	if night == pathTint or garden == nil then return end
	pathTint = night
	local bed = (garden :: Instance):FindFirstChild("Bed")
	if not bed then return end
	for _, d in bed:GetChildren() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "Path_" then
			d.Material = if night then Enum.Material.Neon else Enum.Material.Pebble
			d.Color = if night then Color3.fromRGB(120, 104, 78) else Color3.fromRGB(196, 176, 140)
		end
	end
end

--============================================================================ the frame
local function frame(dt: number)
	now += dt
	bindGarden()
	if garden == nil then return end
	local g = garden :: Instance
	-- "Here" for the AFK hold: only the gardener's OWN input counts (the thumbstick or keys through MoveDirection,
	-- a tap, a click, a key), never a move of the character, which a neighbour's shove or a hazard's knock can
	-- cause (REVIEW-2). At most one every HereSeconds while the input lasts.
	if now - lastInputAt < 1 and now - lastHereAt >= Config.Net.HereSeconds then
		lastHereAt = now
		HereEvent:FireServer()
	end
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local phase = g:GetAttribute("Phase") or "reveal"
	local paused = g:GetAttribute("Paused") == true
	local pTarget = tonumber(g:GetAttribute("Progress")) or 0
	-- The LOOK is smoothed: a lost chapter sends progress back to the chapter's start and the season glides back.
	-- The NAMED band (the chip, the title cards, which hazards fall) goes by the server's exact progress, so the
	-- Harvest Moon is announced the instant the Queen falls, not when an asymptote gets there.
	pShown = if pShown == nil then pTarget else EnvBands.approach(pShown, pTarget, dt, Env.HalfLife)
	if math.abs((pShown :: number) - pTarget) < 1e-3 then pShown = pTarget end
	local p = pShown :: number
	local bandIdx = EnvBands.indexAt(bands, pTarget)
	local weights = EnvBands.weights(bands, p)

	-- lighting at LightingHz
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		if current == nil then
			current = {}
			for _, grp in GROUPS do (current :: any)[grp] = EnvBands.sample(bands, p, grp) end
		end
		for _, grp in GROUPS do
			(current :: any)[grp] = EnvBands.approachTable((current :: any)[grp], EnvBands.sample(bands, p, grp), step, Env.HalfLife)
			writeGroup(targets[grp], (current :: any)[grp])
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
			for _, id in b.pieces or {} do pieceW[id] = math.min(1, (pieceW[id] or 0) + w) end
			for _, a in b.ambient or {} do
				if GardenArt.hasCritter(a.kind) then critters[a.kind] = (critters[a.kind] or 0) + a.count * w end
			end
			for _, wx in b.weather or {} do
				if GardenArt.hasWeather(wx.kind) then weather[wx.kind] = (weather[wx.kind] or 0) + wx.rate * w end
			end
			local ct = b.lighting.ClockTime
			if ct >= 19 or ct < 5 then nightW += w end
		end
	end
	for id in pieceIds do art:updatePiece(id, pieceW[id] or 0) end
	for kind, n in critters do critters[kind] = math.floor(n + 0.5) end
	art:updateCritters(critters, dt, now)
	art:updateWeather(weather)
	tintPath(nightW > 0.5)

	-- the tools that fired go back to their look
	for tool, f in flashing do
		if now >= f.untilT then
			tool.Material = f.material
			tool.Color = f.color
			flashing[tool] = nil
		end
	end
	-- What the player sees of the pads (REVIEW-2):
	--  * the pads that see the most path GLOW, all game, while there is room for a gnome: the Config.Glow.Count best
	--    FREE pads for the gnome the sheet stars (Sim.suggestKind, PathGen.bestPads: what the pacing model's normal
	--    player plants). They used to glow only until the first gnome stood, and as a rim the pad itself hides
	--    from the garden view;
	--  * the pad the gnome sheet is for is GOLD: a phone tap on a 17 px cell opened another pad's sheet with
	--    nothing in the world to show it.
	-- Client-only looks on the server's pad Parts (nothing replicates back); a new bed brings new Parts.
	local gnomeCount = g:GetAttribute("Gnomes") or 0
	local active = phase == "reveal" or phase == "build" or phase == "wave" or phase == "held"
	local bed = g:FindFirstChild("Bed")
	local gnomesFolder = bed and bed:FindFirstChild("Gnomes")
	local standing = {}
	local keyParts = {}
	for _, m in (if gnomesFolder then gnomesFolder:GetChildren() else {}) do
		local pad, kind = m:GetAttribute("Pad"), m:GetAttribute("Kind")
		if type(pad) == "number" and type(kind) == "string" then
			table.insert(standing, { pad = pad, kind = kind })
			table.insert(keyParts, kind .. pad)
		end
	end
	table.sort(keyParts)
	local chapter = g:GetAttribute("Chapter") or 1
	local key = chapter .. ":" .. table.concat(keyParts, ",")
	if path and key ~= litKey then
		litKey = key
		table.clear(glowIds)
		local _, best = PathGen.glow(Config, path, bedPads, standing, chapter, Sim.suggestKind)
		for _, id in best do table.insert(glowIds, id) end
		for _, rim in glowPads do rim.Transparency = 0.55 end
		table.clear(glowPads)
		glowScanAt = -math.huge
	end
	local lit: { [number]: boolean } = {}
	if active and gnomeCount < Config.MaxGnomes then
		for _, id in glowIds do lit[id] = true end
	end
	local pickedPad = if active then (state:GetAttribute("SelectedPad") or 0) else 0
	local found = 0
	for _ in padParts do found += 1 end
	if found < #bedPads and bed and now - padScanAt >= 0.5 then
		padScanAt = now
		for _, d in bed:GetChildren() do
			local id = d:GetAttribute("PadId")
			if type(id) == "number" and d:IsA("BasePart") then padParts[id] = d end
		end
	end
	local pulse = phase == "reveal" and gnomeCount == 0
	for id, part in padParts do
		local look = if id == pickedPad then "gold" elseif lit[id] then "glow" else "plain"
		local was = padWas[part]
		if was == nil then
			was = { color = part.Color, material = part.Material, look = "plain" }
			padWas[part] = was
		end
		if look == "gold" then
			if was.look ~= "gold" then part.Material = Enum.Material.Neon; part.Color = GOLD end
		elseif look == "glow" then
			local k = if pulse then 0.5 + 0.5 * math.sin(now * 5) else 0
			part.Material = Enum.Material.Neon
			part.Color = GLOW_A:Lerp(GLOW_B, k)
		elseif was.look ~= "plain" then
			part.Material = was.material
			part.Color = was.color
		end
		was.look = look
	end
	if #glowPads < #glowIds and now - glowScanAt >= 0.5 then
		glowScanAt = now
		table.clear(glowPads)
		local bed = g:FindFirstChild("Bed")
		for _, id in glowIds do
			for _, d in (if bed then bed:GetChildren() else {}) do
				if d:GetAttribute("PadId") == id then
					local rim = d:FindFirstChild("Rim")
					if rim and rim:IsA("BasePart") then table.insert(glowPads, rim) end
				end
			end
		end
	end
	for _, rim in glowPads do
		local want = if pulse then 0.15 + 0.4 * (0.5 + 0.5 * math.sin(now * 5)) elseif next(lit) ~= nil then 0.25 else 0.55
		if math.abs(rim.Transparency - want) > 0.02 then rim.Transparency = want end
	end

	-- the bugs (stopped drawing when no tick has come for a second: paused, or the wave is over)
	if phase == "wave" and now - lastTickT < 1 then
		art:drawBugs(now)
	elseif phase ~= "wave" and art.bugCount > 0 then
		art:clearBugs()
	end

	-- the paused overlay and the button (and, for a moment, a notice in the overlay's place)
	local noticing = not paused and now < noticeUntil
	local overlayText = if noticing then noticeText else PAUSED_TEXT
	if pausedLabel.Text ~= overlayText then pausedLabel.Text = overlayText end
	pausedLabel.Visible = paused or noticing
	if paused ~= Rest.isResting(rest) then
		if not paused and Rest.isResting(rest) then Rest.stop(rest) end -- the server resumed (an action, a step)
	end
	local btnText = if paused then "▶ PLAY" elseif rest.pending then "⏸ ..." else "⏸ PAUSE"
	if pauseBtn.Text ~= btnText then pauseBtn.Text = btnText end

	local b = bands[bandIdx]
	local chipText = b.emoji .. " " .. b.name
	local nextIdx = EnvBands.nextBand(bands, pTarget)
	if nextIdx then chipText ..= "  ·  " .. bands[nextIdx].emoji .. " at wave " .. tostring(bands[nextIdx].from) end
	if chip.Text ~= chipText then chip.Text = chipText end
	-- A band is announced when this session's garden REACHES it. The first sight of the garden's progress only
	-- says where the gardener is, quietly: Frost's bed starts at Progress 30, the HARVEST MOON's band, and
	-- celebrating that on every join (the flash, the 4.5 s card, the look up at the moon) replayed the brag for a
	-- win from an earlier session (found by the build; check_gnomegardendefense_frost). Before the server has
	-- published the bed (the profile is still loading) there is nothing to name yet.
	-- A NEW BED is never a reach either: REVIEW-2 reached the brag through a save restored late (the first read
	-- failed, the gardener started on Spring at 0, and the retry re-dug the bed at Frost's 30). Bands are reached
	-- by play inside one attempt, so the first progress of every attempt is named the same quiet way.
	local published = g:GetAttribute("Progress") ~= nil
	local firstSight = announcer.highest == 0 or primedAttempt ~= gardenAttempt
	if published and firstSight then
		primedAttempt = gardenAttempt
		local first = announcer.highest == 0
		if EnvBands.announce(announcer, bandIdx) and (bandIdx > 1 or not first) then
			showCard(b.emoji .. " " .. string.upper(b.name), "wave " .. tostring(math.floor(pTarget) + 1), false)
		end
	elseif published and EnvBands.announce(announcer, bandIdx) then
		local name = b.emoji .. " " .. b.name
		bandCard = { name = name, at = tick() }
		if seasonCard and tick() - seasonCard.at < CARD_MERGE_SECONDS then
			-- the season's own card is up (its boss just fell): the band joins it, it does not replace it
			if not string.find(string.upper(seasonCard.title), string.upper(b.name), 1, true) then
				seasonCard.sub = if seasonCard.sub == "" then name else seasonCard.sub .. "  ·  " .. name
			end
			showCard(seasonCard.title, seasonCard.sub, true)
		else
			showCard(b.emoji .. " " .. string.upper(b.name), "wave " .. tostring(math.floor(pTarget) + 1), b.celebrate == true)
		end
		-- a celebrated band looks up at its sky piece (the moon, the aurora): the garden view looks down at the bed
		-- and would never show them (View.client reads these)
		if b.celebrate then
			for _, id in b.pieces or {} do
				if GardenArt.skyAnchor(id) then
					state:SetAttribute("SkyPiece", id)
					state:SetAttribute("SkyUntil", tick() + Config.Camera.SkySeconds)
					break
				end
			end
		end
	end

	if hrp == nil or hum == nil then return end
	local rootPart = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- the knock wears off
	if knockUntil and now >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end
	local fm = (humanoid :: any).FloorMaterial
	local grounded = fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true
	if moving then lastInputAt = now end

	-- PAUSE (Rest): a queued pause starts the first still moment after the hazard; any movement wakes
	if restOn then
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = grounded, threat = scheduler.active ~= nil })
		if ev == "started" then
			PauseEvent:FireServer(true)
		elseif ev == "woke" then
			PauseEvent:FireServer(false)
		end
	end

	-- hazards, on garden time
	local hazardLive = false
	local kinds = b.hazards or {}
	local gardenTime = (phase == "wave" or phase == "build") and not paused and not Rest.isResting(rest) and #kinds > 0
	if hazardsOn then
		local look = camera.CFrame.LookVector
		local before = if scheduler.active then scheduler.active.t else nil
		local pos = vec(rootPart.Position)
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = not gardenTime,
			grounded = grounded,
			kinds = kinds,
			aim = pos,
			yaw = math.atan2(look.X, look.Z),
			pitch = math.asin(math.clamp(look.Y, -1, 1)),
		}, rand)
		if ev and ev.type == "done" then art:hideHazard(ev.plan.kind) end
		local plan = scheduler.active
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			art:showHazard(plan, hp, now, if live then Hazards.zone(plan, Hz.PlayerRadius) else nil)
			if Hazards.checkHit(plan, before or 0, plan.t, pos, Hz.PlayerRadius) then
				plan.hit = true
				local kv = Hazards.knockVelocity(Hz, plan, pos, vec(rootPart.CFrame.LookVector * -1))
				pcall(function() humanoid.PlatformStand = true end)
				rootPart.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				state:SetAttribute("DazedUntil", tick() + Hz.DazeSeconds)
				state:SetAttribute("Hits", (state:GetAttribute("Hits") or 0) + 1)
				FxClient.shake(0.4, 0.9)
				FxClient.flash(Color3.fromRGB(255, 255, 255), 0.3, 0.35)
			end
			hazardLive = live and not plan.hit
			if live and not plan.hit then
				local name = Hz.Kinds[plan.kind] and Hz.Kinds[plan.kind].name or string.upper(plan.kind)
				local brg = Hazards.bearing(vec(camera.CFrame.Position), vec(look), hp)
				local text = if plan.locked then "⚠️ STEP OUT OF THE RED RING! " .. name else "⚠️ " .. name .. " " .. ARROWS[brg]
				if warning.Text ~= text then warning.Text = text end
				warning.Visible = true
			else
				warning.Visible = false
			end
		else
			warning.Visible = false
		end
	end
	state:SetAttribute("Resting", Rest.isResting(rest))
	state:SetAttribute("Band", b.id)
	-- a live hazard: View.client zooms on the gardener so the red ring is big enough to step out of
	if state:GetAttribute("HazardLive") ~= hazardLive then state:SetAttribute("HazardLive", hazardLive) end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken frame must not flood the output
		warn("[GnomeGarden] frame error: " .. tostring(err))
	end
end)
