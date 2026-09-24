-- GROW A CRYSTAL 💎 — the cavern comes alive. Client only (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads how many chambers the player owns from the server's State push (the game's real
--     progress; never a timer) and blends the environment bands in Config.Env (EnvBands): lighting,
--     atmosphere, bloom, colour grade, depth of field, a slow "geode pulse", scenery that fills in as
--     chambers are bought, critters, particle weather. A change glides over Env.HalfLife; it never cuts;
--   * plays a burst where a crystal was harvested, in the colour of the tier it refracted into, and a
--     beam of light for Legendary and Mythic (the server's State push says which, after paying it);
--   * flies a rare, HARMLESS visitor through the cavern about every 2-3 minutes of play (Visitors);
--   * runs Relax (Rest): sit down, soften the view, visitors leave you alone. Crystals keep growing.
--
-- Why all of it is client-side, and why that is safe:
--   * it is cosmetic. The server does not know bands, visitors or rest exist and trusts nothing from
--     here: this script fires no remote, adds no remote, sets no attribute and writes to nothing the
--     server built. Growth, harvests, dust and the leaderboard are exactly as they were;
--   * every part it makes is local, anchored and CanCollide/CanQuery/CanTouch = false, so nothing can
--     be stood on and nothing stands between a click and a socket;
--   * it reads only this player's own State push, its own plot's socket (to find where its cavern is),
--     its own character and camera, and Config. Nothing about any other player.
-- Measured budgets, bands, rest and the shot list: EYECANDY.md. Headless: robloxemu/check_growacrystal_*.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Visitors = require(ReplicatedStorage:WaitForChild("Visitors"))
local Grotto = require(ReplicatedStorage:WaitForChild("Grotto"))
local Cavern = require(ReplicatedStorage:WaitForChild("Cavern"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local CavernArt = require(ReplicatedStorage:WaitForChild("CavernArt"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local StateFeed = require(ReplicatedStorage:WaitForChild("StateFeed"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Env, RestCfg, VisCfg, Budget = Config.Env, Config.Rest, Config.Visitors, Config.Budget
local bands = Env.Bands
local MAXC = Config.Economy.MaxChambers

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[CrystalGrotto] Config.Env.Bands is invalid (" .. tostring(err) .. "); the cavern stays as the server lit it.")
		return
	end
end
local visitorsOn, visErr = Visitors.validate(VisCfg)
if not visitorsOn then
	warn("[CrystalGrotto] Config.Visitors is invalid (" .. tostring(visErr) .. "); visitors are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[CrystalGrotto] Config.Rest is invalid (" .. tostring(restErr) .. "); Relax is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- ── local world + lighting rig ────────────────────────────────────────────────
local folder = Instance.new("Folder")
folder.Name = "CrystalLocalGrotto"
folder.Parent = workspace

local layout = Grotto.layout(Config, Rng, Cavern)
local art = CavernArt.new(folder, rand, Config, Grotto, layout, Cavern)

-- Reuse the server's Fx.applyLighting objects by name so the client takes over from exactly the values
-- the server set (Fx.Presets.Cozy = band 1), instead of stacking a second Atmosphere on top.
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
	depthOfField = rig("DepthOfFieldEffect", "FxDoF"),
}
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "depthOfField" }
-- Relax softens the view: the depth of field glides toward this while resting.
local REST_FOCUS = { FarIntensity = 0.35, FocusDistance = 14, InFocusRadius = 12, NearIntensity = 0 }

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

-- ── UI: band chip + relax button + title card ───────────────────────────────────
-- The row sits under the HUD's header (dust, hint, toast) in the column BETWEEN the side panels,
-- mirroring Hud.client.luau's geometry, so it never covers a panel or an open drawer
-- (robloxemu/check_growacrystal_hud.luau measures that at every viewport, every drawer open).
local MARGIN, GAP = Responsive.MARGIN, 8
local HUD_LEFT_W, HUD_LB_W = 250, 200
local HUD_TOGGLE_H = 28
local ROW_W, ROW_H = 420, 34
local RELAX_W = 84
local MIN_TAP = 44
local CHIP_MIN_W = 200 -- below this the chip moves under the button instead of beside it

local gui = Instance.new("ScreenGui")
gui.Name = "CrystalGrotto"
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
local function maxText(inst: Instance, n: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = n
	c.Parent = inst
end

local chip = Instance.new("TextLabel")
chip.Name = "BandChip"
chip.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
chip.BackgroundTransparency = 0.2
chip.Font = Enum.Font.GothamBold
chip.TextColor3 = Color3.fromRGB(215, 235, 250)
chip.TextScaled = true
chip.Text = bands[1].emoji .. " " .. bands[1].name
chip.Parent = root
corner(chip, 10)
maxText(chip, 16)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = chip
end

local relaxBtn = Instance.new("TextButton")
relaxBtn.Name = "RelaxButton"
relaxBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 150)
relaxBtn.Font = Enum.Font.GothamBlack
relaxBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
relaxBtn.TextScaled = true
relaxBtn.Text = "🛋 Relax"
relaxBtn.AutoButtonColor = true
relaxBtn.Parent = root
corner(relaxBtn, 10)
maxText(relaxBtn, 16)

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
cardSub.TextColor3 = Color3.fromRGB(220, 235, 255)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root

local ui = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
-- Hud.client's own rule, so the header this row sits under is measured the same way.
local function hudTouchSize(designPx: number): number
	if ui.controlPad <= 0 then return designPx end
	return math.ceil(math.max(designPx, MIN_TAP) / ui.scale)
end
-- A tap target that lands at least MIN_TAP screen px, without blowing a big design size up further.
local function tapSize(designPx: number): number
	if ui.controlPad <= 0 then return designPx end
	local n = math.max(designPx, math.ceil(MIN_TAP / ui.scale))
	if n * ui.scale < MIN_TAP then n += 1 end
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
	ui = Responsive.layout(vx, vyDraw, UserInputService.TouchEnabled, vy)
	uiScale.Scale = ui.scale
	root.Size = UDim2.fromScale(1 / ui.scale, 1 / ui.scale)
	local rootW = vx / ui.scale
	local rootH = vyDraw / ui.scale

	-- the HUD's header bottom (Hud.client.luau applyLayout): the toast line, plus a gap
	local rowTop
	if ui.compact then
		local toggleH = hudTouchSize(HUD_TOGGLE_H)
		rowTop = 10 + toggleH + 6 + 26 + 28
	else
		rowTop = 98 + 24 + 6
	end
	-- the column between the side panels (Responsive.sideWidth caps each at a quarter of the screen)
	local leftW = Responsive.sideWidth(HUD_LEFT_W, vx, ui)
	local lbW = Responsive.sideWidth(HUD_LB_W, vx, ui)
	local colL = MARGIN + leftW + GAP
	local colR = rootW - MARGIN - lbW - GAP
	local avail = math.max(1, colR - colL)
	local rowW = math.min(ROW_W, avail)
	local x0 = colL + (avail - rowW) / 2
	local btnW = math.min(tapSize(RELAX_W), rowW)
	local rowH = tapSize(ROW_H)
	local chipW = rowW - btnW - GAP
	if chipW >= CHIP_MIN_W then
		relaxBtn.Position = UDim2.fromOffset(x0 + rowW - btnW, rowTop)
		chip.Position = UDim2.fromOffset(x0, rowTop)
		chip.Size = UDim2.fromOffset(chipW, rowH)
	else
		-- a narrow screen: the button on its own row, the chip full width under it
		relaxBtn.Position = UDim2.fromOffset(x0 + (rowW - btnW) / 2, rowTop)
		chip.Position = UDim2.fromOffset(x0, rowTop + rowH + 6)
		chip.Size = UDim2.fromOffset(rowW, math.max(26, math.floor(ROW_H * 0.8)))
	end
	relaxBtn.Size = UDim2.fromOffset(btnW, rowH)

	local cardW = math.min(760, avail)
	local cardH = math.min(70, rootH * 0.14)
	card.Position = UDim2.fromOffset(colL + avail / 2, rootH * 0.4)
	card.Size = UDim2.fromOffset(cardW, cardH)
	cardSub.Position = UDim2.fromOffset(colL + avail / 2, rootH * 0.4 + cardH / 2 + 4)
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
		FxClient.flash(Color3.fromRGB(255, 235, 255), 0.4, 0.9)
		FxClient.fovPunch(6, 0.12, 0.6)
	end
	task.delay(if celebrate then 4 else 3, function()
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

-- ── what the player owns: the progress value ───────────────────────────────────
-- Two sources. The State push: Roblox flushes a RemoteEvent that fired before any listener to the FIRST
-- connection only, so this script and Hud.client share ONE connection (StateFeed.luau) instead of racing
-- for the join push with one each; whichever starts first makes it, and the other is handed the latest
-- payload when it subscribes (robloxemu/check_growacrystal_queue*.luau, both orders). And the world: the
-- server builds six sockets per owned chamber in our plot (Grotto.chambersFromSockets), which needs no
-- remote at all, so a push that is late or lost still cannot leave the cavern in the wrong look.
-- The progress value is the larger of the two; it never shrinks (chambers only grow, a stale push is not
-- believed over the sockets). robloxemu/check_growacrystal_race.luau runs this with NO State push at all.
local stateChambers = 0     -- from the State push (0 = none seen yet)
local socketChambers = 0    -- from our own sockets in the world (0 = none arrived yet)
local chambers = 1          -- max(1, stateChambers, socketChambers)
local shownChambers: number? = nil -- what the title cards have announced; nil until the count has settled
local steadyFor = 0         -- seconds the count has held still (a batch of sockets can replicate over frames)
local lastCount = -1
local SETTLE_SECONDS = 1
local lastHarvestN = 0      -- a per-SESSION counter from the server: anything above what we drew is new
local pendingBursts = {}    -- harvests that arrived before the plot origin was known
local lastFlashAt: number? = nil -- when a harvest last flashed the screen (Grotto.flashDue)
local announcer = EnvBands.newAnnouncer()

local function bandIndex(c: number): number
	return EnvBands.indexAt(bands, c)
end

local remotes = ReplicatedStorage:WaitForChild("CrystalRemotes")
local StateEvent = remotes:WaitForChild("State")

StateFeed.of(StateEvent, task.spawn):subscribe(function(s)
	if type(s) ~= "table" then return end
	stateChambers = math.max(stateChambers, Grotto.progress(s.chambers, MAXC))
	local lh = s.lastHarvest
	local n = if type(lh) == "table" and type(lh.n) == "number" then lh.n else 0
	if n > lastHarvestN and type(lh) == "table" then
		lastHarvestN = n
		table.insert(pendingBursts, { socket = lh.socket, tier = lh.tier, seed = lh.seed })
	end
end)

-- The cards. The first one says where the player is, quietly, once the count has held still for
-- SETTLE_SECONDS: a returning player whose cavern is the Heart of the Geode gets its name, never a fanfare
-- for chambers bought in an earlier session, and never a card for a half-replicated count first.
local function announceProgress(dt: number, haveSource: boolean)
	if chambers ~= lastCount then
		lastCount = chambers
		steadyFor = 0
	else
		steadyFor += dt
	end
	if shownChambers == nil then
		if haveSource and steadyFor >= SETTLE_SECONDS then
			shownChambers = chambers
			local idx = bandIndex(chambers)
			EnvBands.announce(announcer, idx)
			local b = bands[idx]
			showCard(b.emoji .. " " .. string.upper(b.name), "chamber " .. tostring(chambers) .. " of " .. tostring(MAXC), false)
		end
		return
	end
	if chambers > (shownChambers :: number) then
		local before = shownChambers :: number
		shownChambers = chambers
		local idx = bandIndex(chambers)
		if EnvBands.announce(announcer, idx) then
			local b = bands[idx]
			showCard(b.emoji .. " " .. string.upper(b.name), "chamber " .. tostring(chambers) .. " opened", idx == #bands)
		else
			-- the next look starts showing before its band opens (it fades in over `fade` chambers)
			local nb = bands[idx + 1]
			local wNow = EnvBands.weights(bands, chambers)[idx + 1] or 0
			local wBefore = EnvBands.weights(bands, before)[idx + 1] or 0
			if nb and wNow > 0.001 and wBefore <= 0.001 then
				showCard(nb.emoji .. " " .. (nb.teaser or nb.name), "chamber " .. tostring(chambers) .. " opened", false)
			end
		end
	end
end

-- ── finding our own cavern ─────────────────────────────────────────────────────
-- The server builds every plot at (plotIndex * spacing, 0, 0) and names our sockets
-- Socket_<UserId>_<id>. Socket 1's world position minus its plot-local position (Cavern.socketPos,
-- the same pure function the server uses) is our origin. Nothing of anybody else's plot is read.
local origin: Vector3? = nil
local plotFolder: Instance? = nil
local lookAgain = 0
local socketPrefix = "Socket_" .. tostring(player.UserId) .. "_"
local function findOrigin()
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then return end
	for _, f in plots:GetChildren() do
		local s = f:FindFirstChild(socketPrefix .. "1")
		if s and s:IsA("BasePart") then
			local lp = Cavern.socketPos(Config, 1, Rng)
			origin = (s :: BasePart).Position - Vector3.new(lp.x, lp.y, lp.z)
			plotFolder = f
			art:setOrigin(origin :: Vector3)
			return
		end
	end
end
local function countSockets()
	local f = plotFolder
	if f == nil or f.Parent == nil then
		plotFolder = nil
		origin = nil
		return
	end
	socketChambers = Grotto.chambersFromSockets(function(id: number): boolean
		return (f :: Instance):FindFirstChild(socketPrefix .. tostring(id)) ~= nil
	end, Config.Economy.SocketsPerChamber, MAXC)
end

local function socketTop(id: number): Vector3?
	if origin == nil then return nil end
	local lp = Cavern.socketPos(Config, id, Rng)
	return (origin :: Vector3) + Vector3.new(lp.x, lp.y + 0.5, lp.z)
end

-- ── character + rest ───────────────────────────────────────────────────────────
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local rest = Rest.new()
local sat = false
local restW = 0

local function unsit()
	if sat and hum then
		pcall(function() (hum :: Humanoid).Sit = false end)
	end
	sat = false
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	rest = Rest.new()
	sat = false
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local function groundedNow(): boolean
	if hum == nil then return false end
	local fm = (hum :: any).FloorMaterial
	return fm ~= nil and fm ~= Enum.Material.Air
end

relaxBtn.Activated:Connect(function()
	if not restOn then return end
	if Rest.isResting(rest) or rest.pending then
		Rest.stop(rest)
		unsit()
		return
	end
	-- visitors are harmless, so nothing is ever a threat that could queue a rest
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = groundedNow(), threat = false })
	if result == "resting" then
		sat = true
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
	end
end)

-- ── the frame ─────────────────────────────────────────────────────────────────
local now = 0
local pulsePhase = 0
local weights: { [number]: number } = {}
local current: { [string]: any }? = nil -- smoothed lighting groups
local lightAccum = 0
local clock = Visitors.newClock(VisCfg, rand)
local visitorKind: string? = nil
local visitorSeconds = 0

local pieceIds: { [string]: boolean } = {}
for _, b in bands do
	for _, id in b.pieces or {} do pieceIds[id] = true end
end

local function frame(dt: number)
	now += dt
	-- twice a second: find our plot, and count its chambers from the sockets in it
	lookAgain -= dt
	if lookAgain <= 0 then
		lookAgain = 0.5
		if origin == nil then findOrigin() end
		countSockets()
	end
	chambers = math.max(1, stateChambers, socketChambers)
	announceProgress(dt, origin ~= nil or stateChambers > 0)
	if character and (hrp == nil or (hrp :: BasePart).Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end

	local p = chambers
	local bandIdx = bandIndex(p)

	-- band weights, smoothed: buying a chamber (or a returning player's first push) glides, never cuts
	local targetW = EnvBands.weights(bands, p)
	for i = 1, #bands do
		local tw = targetW[i] or 0
		if current == nil then
			weights[i] = if i == 1 then 1 else 0 -- start from the server's preset (band 1)
		else
			weights[i] = EnvBands.approach(weights[i] or 0, tw, dt, Env.HalfLife)
		end
	end

	-- rest (Relax)
	local resting = false
	if restOn and hum then
		local humanoid = hum :: Humanoid
		local grounded = groundedNow()
		-- a Humanoid we sat down may report FloorMaterial = Air; it is supported unless actually falling
		local supported = grounded
		if sat and not grounded and hrp then
			local vel = (hrp :: BasePart).AssemblyLinearVelocity
			supported = vel ~= nil and math.abs(vel.Y) < 2
		end
		local md = (humanoid :: any).MoveDirection
		local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = false })
		if ev == "started" and rest.source == "manual" then
			sat = true
			pcall(function() humanoid.Sit = true end)
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
		resting = Rest.isResting(rest)
	end
	restW = EnvBands.approach(restW, if resting then 1 else 0, dt, 0.35)

	-- the geode pulse: a slow ambient cycle whose depth and period follow the (smoothed) band weights.
	-- The PHASE is integrated, so a change of period never makes the pulse jump or race.
	local depth, period = 0, 0
	for i, b in bands do
		depth += (weights[i] or 0) * b.pulse.depth
		period += (weights[i] or 0) * b.pulse.period
	end
	if period <= 0 then period = bands[1].pulse.period end
	pulsePhase = (pulsePhase + dt / period) % 1
	local pulse = Grotto.pulse(pulsePhase, 1)

	-- lighting (and, below, the scenery's fade and pulse) at LightingHz
	lightAccum += dt
	local tick = current == nil or lightAccum >= 1 / Env.LightingHz
	if tick then
		local step = lightAccum
		lightAccum = 0
		local target = {}
		for _, g in GROUPS do
			target[g] = EnvBands.sample(bands, p, g)
		end
		target.depthOfField = EnvBands.overlay(target.depthOfField, REST_FOCUS, restW)
		if current == nil then
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
			if g == "bloom" and depth > 0 then
				props = table.clone(props)
				props.Intensity = props.Intensity * (1 + 0.25 * depth * (pulse - 0.5))
			end
			writeGroup(targets[g], props)
		end
	end

	-- scenery, critters, weather
	if origin ~= nil then
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
					critters[a.kind] = (critters[a.kind] or 0) + a.count * w
				end
				for _, wx in b.weather or {} do
					if CavernArt.hasWeather(wx.kind) then
						weather[wx.kind] = (weather[wx.kind] or 0) + wx.rate * w
					end
				end
			end
		end
		if tick then
			for id in pieceIds do
				art:updatePiece(id, pieceW[id] or 0, pulse, depth)
			end
		end
		for kind, n in critters do
			critters[kind] = math.floor(n + 0.5)
		end
		art:updateCritters(critters, dt, now)
		art:updateWeather(EnvBands.capRates(weather, Budget.MaxWeatherEmitters, Budget.MaxEmitterRate, 0.05))

		-- harvest bursts (the server told us the tier after paying it)
		while #pendingBursts > 0 do
			local h = table.remove(pendingBursts, 1)
			-- a payload is data, never trusted to be well-formed: a bad field must cost one burst, not the frame
			local sid = tonumber(h.socket)
			local tier = math.clamp(math.floor(tonumber(h.tier) or 1), 1, Config.MaxTier)
			local total = Config.Economy.MaxChambers * Config.Economy.SocketsPerChamber
			local at = if sid and sid == math.floor(sid) and sid >= 1 and sid <= total then socketTop(sid) else nil
			if at then
				local rule = Grotto.burst(tier, Env.Harvest)
				local tc = Config.TierColor[tier]
				local color = Color3.fromRGB(tc[1], tc[2], tc[3])
				art:burst(at, rule, color, now)
				-- the full-screen part waits out a cooldown, so a row of Legendary harvests never stacks flashes
				-- into a wash; the burst, beam and card above and below play for every harvest
				local hf = Env.HarvestFlash
				if (rule.flash or (rule.shake or 0) > 0) and Grotto.flashDue(lastFlashAt, now, hf.cooldown) then
					lastFlashAt = now
					if rule.flash then FxClient.flash(color, hf.alpha, hf.fade) end
					if (rule.shake or 0) > 0 then FxClient.shake(0.5, rule.shake) end
				end
				if rule.card then
					local seed = tonumber(h.seed)
					local sub = if seed and Config.Tiers[seed] and tier > seed
						then "refracted from a " .. Config.Tiers[seed] .. " seed ✨"
						else "a " .. Config.Tiers[tier] .. " crystal"
					showCard(rule.card, sub, false)
				end
			end
		end
		art:updateBursts(dt, now)
	end

	-- visitors: rare, harmless; the clock freezes while resting and never resets
	if visitorsOn and origin ~= nil then
		local ev = Visitors.step(clock, VisCfg, dt, { resting = resting, kinds = bands[bandIdx].visitors or {} }, rand)
		if ev and ev.type == "launch" then
			visitorKind = ev.kind
			visitorSeconds = ev.seconds
			art:startVisitor(ev.kind)
		elseif ev and ev.type == "done" then
			art:endVisitor(ev.kind)
			visitorKind = nil
		end
		local a = clock.active
		if a and visitorKind then
			art:updateVisitor(visitorKind, a.t / visitorSeconds, now)
		end
	end

	-- the chip and the button
	local chipText
	if resting then
		chipText = "🛋 Relaxing — your crystals keep growing"
	else
		chipText = Grotto.chipText(bands, p)
	end
	if chip.Text ~= chipText then chip.Text = chipText end
	local btnText = if resting then "▶ Back" elseif rest.pending then "🛋 …" else "🛋 Relax"
	if relaxBtn.Text ~= btnText then relaxBtn.Text = btnText end
end

local broken = false
RunService.RenderStepped:Connect(function(dt)
	if broken then return end
	local ok, err = pcall(frame, dt)
	if not ok then
		-- cosmetic: one warning, then stand down rather than spam the log every frame
		broken = true
		warn("[CrystalGrotto] visuals stopped: " .. tostring(err))
	end
end)
