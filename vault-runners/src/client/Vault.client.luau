-- VAULT RUNNERS — the vault you run through, dressed. Client only (StarterPlayerScripts).
--
-- What this script does for THIS player only (EYECANDY.md has the whole design and the numbers):
--   * reads the DEPTH of the run the server just started (Config.Env.TierDepth + the floor from the
--     run's own "start" event) and blends the five strata of Config.Env.Bands — bank vault, pyramid
--     tomb, reactor core, frozen vault, volcano temple — into Lighting, the colours of the vault's
--     walls, floors and pads, the props hanging from the ceilings, the sky over the top storey and
--     the weather around the camera. Every written value glides; nothing hard-cuts;
--   * reads the kill plane the server moves and turns "how close is the collapse" into ceiling
--     dust, sparks off the plane, a warmer grade and the odd rumble;
--   * cracks the pad under the runner as it crumbles and HOLDS the crack until the server drops it,
--     throws debris when it goes and flashes it when it comes back, so the obby reads at a glance;
--   * keeps what a runner must find findable in every stratum: the gems and the exit pad, and the
--     ring a ceiling drop draws at their feet, are drawn in a colour that reads against the floor;
--   * runs the rare ceiling drops (Hazards + VaultEnv.hazardEligible) and knocks the local
--     character down on a hit;
--   * offers REST in the hub, between runs (Rest). A run is a timed round and never pauses.
--
-- Why all of it is client-side, and why that is safe:
--   * it is cosmetic, or it only ever harms the local player, whose character physics the client
--     already owns. The server does not know any of it exists and trusts nothing from here: this
--     script never fires a remote, and gems, pads, the countdown and saves are all the server's;
--   * everything it builds is local (never replicates), non-collidable, non-queryable and
--     non-touchable. On the server's own vault parts it writes COLOUR and Reflectance only — never
--     Material, Size, CFrame, CanCollide, CanQuery, Transparency or an attribute — so physics and
--     the obby are exactly what the server built;
--   * it reads only what this player already has: its own character, its own camera, its own
--     run's "start"/"tick"/"end" and state pushes, the parts of its OWN vault, and Config. It
--     never reads another player's vault, and decoration is placed from (storey, cell, floor seed)
--     alone, so no prop can point at the exit.
-- Headless checks: robloxemu/check_vaultrunners_env.luau, robloxemu/check_vaultrunners_hazards.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local VaultEnv = require(ReplicatedStorage:WaitForChild("VaultEnv"))
local VaultArt = require(ReplicatedStorage:WaitForChild("VaultArt"))
local Progression = require(ReplicatedStorage:WaitForChild("Progression"))
local VaultFloor = require(ReplicatedStorage:WaitForChild("VaultFloor"))
local MazeGen = require(ReplicatedStorage:WaitForChild("MazeGen"))
local Rng = require(ReplicatedStorage:WaitForChild("Rng"))
local Ascent = require(ReplicatedStorage:WaitForChild("Ascent"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Env, Hz, RestCfg, Budget = Config.Env, Config.Hazards, Config.Rest, Config.Budget
local bands = Env.Bands

-- A broken config must cost the polish, never the game: warn loudly and switch that part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[VaultFx] Config.Env.Bands is invalid (" .. tostring(err) .. "); the vault keeps the server's look.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[VaultFx] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); ceiling drops are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[VaultFx] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local folder = Instance.new("Folder")
folder.Name = "VaultRunnersFx"
folder.Parent = workspace
local art = VaultArt.new(folder, rand, Config, EnvBands, VaultEnv)
local rgb = VaultArt.rgb

--============================================================================ lighting

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
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sky = rig("Sky", "VaultSky"),
}
local GROUPS = { "lighting", "atmosphere", "bloom", "colorCorrection", "sky" }

local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "VaultRestFocus"
restFocus.FarIntensity = 0.3
restFocus.FocusDistance = 16
restFocus.InFocusRadius = 24
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
				value = rgb(v)
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

--============================================================================ UI

local MARGIN, GAP = 14, 8
local ROW_W, ROW_H, REST_W, WARN_H = 380, 34, 96, 36
local MIN_TAP = 44

local gui = Instance.new("ScreenGui")
gui.Name = "VaultFx"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
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

-- The band row: a chip naming where you are, and (in the hub only) the ☕ Rest button. It sits at
-- the BOTTOM CENTRE, between Roblox's thumbstick (left 35%) and jump button (right 25%), because the
-- top of the screen belongs to the HUD's wallet, collapse timer, toast and phone drawers.
local row = Instance.new("Frame")
row.Name = "BandRow"
row.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
row.BackgroundTransparency = 0.25
row.BorderSizePixel = 0
row.Parent = root
corner(row, 10)

local chip = Instance.new("TextLabel")
chip.Name = "BandChip"
chip.BackgroundTransparency = 1
chip.Font = Enum.Font.GothamBold
chip.TextColor3 = Color3.fromRGB(240, 236, 250)
chip.TextScaled = true
chip.Text = ""
chip.Parent = row
maxText(chip, 17)

local restBtn = Instance.new("TextButton")
restBtn.Name = "RestButton"
restBtn.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
restBtn.Font = Enum.Font.GothamBlack
restBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restBtn.TextScaled = true
restBtn.Text = "☕ Rest"
restBtn.AutoButtonColor = true
restBtn.Parent = row
corner(restBtn, 8)
maxText(restBtn, 17)

local warning = Instance.new("Frame")
warning.Name = "HazardWarning"
warning.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
warning.BackgroundTransparency = 0.15
warning.BorderSizePixel = 0
warning.Visible = false
warning.Parent = root
corner(warning, 10)
local warningText = Instance.new("TextLabel")
warningText.Name = "Text"
warningText.BackgroundTransparency = 1
warningText.Size = UDim2.fromScale(1, 1)
warningText.Font = Enum.Font.GothamBlack
warningText.TextColor3 = Color3.fromRGB(255, 236, 120)
warningText.TextScaled = true
warningText.Text = ""
warningText.Parent = warning
maxText(warningText, 22)

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
cardSub.TextColor3 = Color3.fromRGB(230, 226, 245)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root

local inRun = false
local layout = Responsive.layout(Responsive.REF_X, Responsive.REF_Y, UserInputService.TouchEnabled)
local function touchSize(designPx: number): number
	if not UserInputService.TouchEnabled then return designPx end
	local wanted = math.max(designPx, MIN_TAP)
	local n = math.ceil(wanted / layout.scale)
	if n * layout.scale <= wanted then n += 1 end
	return n
end

local function applyLayout()
	local v = camera.ViewportSize
	local vx = if v.X > 0 then v.X else Responsive.REF_X
	local vy = if v.Y > 0 then v.Y else Responsive.REF_Y
	layout = Responsive.layout(vx, vy, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
	local sc = layout.scale
	local rootW, rootH = vx / sc, vy / sc

	-- the free band at the bottom: right of the thumbstick (35%), left of the jump button (75%)
	local bandL, bandR = (0.35 * vx + GAP) / sc, (0.75 * vx - GAP) / sc
	local rowH = touchSize(ROW_H)
	local rowW = math.min(ROW_W, bandR - bandL)
	local centre = (bandL + bandR) / 2
	row.Position = UDim2.fromOffset(centre - rowW / 2, rootH - MARGIN - rowH)
	row.Size = UDim2.fromOffset(rowW, rowH)
	local btnW = touchSize(REST_W)
	local showRest = restOn and not inRun
	restBtn.Visible = showRest
	if showRest then
		restBtn.Position = UDim2.fromOffset(rowW - btnW, 0)
		restBtn.Size = UDim2.fromOffset(btnW, rowH)
		chip.Position = UDim2.fromOffset(8, 0)
		chip.Size = UDim2.fromOffset(math.max(20, rowW - btnW - GAP - 8), rowH)
	else
		chip.Position = UDim2.fromOffset(8, 0)
		chip.Size = UDim2.fromOffset(rowW - 16, rowH)
	end

	local warnW = math.min(520, rootW - 2 * MARGIN)
	warning.Position = UDim2.fromOffset((rootW - warnW) / 2, rootH * 0.3)
	warning.Size = UDim2.fromOffset(warnW, WARN_H)

	local cardW = math.min(760, rootW - 2 * MARGIN)
	local cardH = math.min(64, rootH * 0.12)
	card.Position = UDim2.fromOffset(rootW / 2, rootH * 0.44)
	card.Size = UDim2.fromOffset(cardW, cardH)
	cardSub.Position = UDim2.fromOffset(rootW / 2, rootH * 0.44 + cardH / 2 + 4)
	cardSub.Size = UDim2.fromOffset(cardW, math.min(28, rootH * 0.06))
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
		FxClient.flash(Color3.fromRGB(255, 244, 220), 0.4, 0.8)
		FxClient.fovPunch(6, 0.12, 0.5)
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

--============================================================================ state

local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local now = 0
local current: { [string]: any }? = nil
local lightAccum = 0
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat = false
local knockUntil: number? = nil
local rumbleIn = 6
local frameError = false
local floorsKnown: { number }? = nil -- next floor per tier, from the server's state pushes
local tiersKnown: { any }? = nil
local lastCardBand: number? = nil
local runSerial = 0
local lastBand = 1
local pieceW: { [string]: number } = {}

-- the run this client is watching: nil in the hub
local run: any = nil

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
	rest = Rest.new()
	sat = false
	restFocus.Enabled = false
	knockUntil = nil
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

--============================================================================ the run

local function vecOf(t: any): Vector3
	return Vector3.new(t.x, t.y, t.z)
end

local function reskin(part: Instance)
	if run == nil or not part:IsA("BasePart") then return end
	local pal = run.pal
	local name = part.Name
	if run.origin == nil then
		-- streaming: the first part that did not move tells us where the vault is
		local def = run.defs[name]
		if def and def.group ~= "killplane" and def.group ~= "seal" then
			run.origin = (part :: BasePart).Position - vecOf(def.position)
		end
	end
	if string.sub(name, 1, 5) == "Wall_" then
		part.Color = rgb(pal.wall)
		part.Reflectance = pal.wallReflect
	elseif string.sub(name, 1, 6) == "Floor_" then
		part.Color = rgb(pal.floor)
	elseif string.sub(name, 1, 5) == "Step_" then
		part.Color = rgb(pal.pad)
	elseif string.sub(name, 1, 4) == "Gem_" or name == "ExitPad" then
		-- the tier's gem colour where it reads against this stratum, the stratum's own where it would
		-- vanish (Silver's pale blue on the Frozen Vault's ice read 1.10:1). The exit pad has always
		-- worn the gem colour. Colour only: the server destroys a gem when it is collected.
		part.Color = rgb(run.gem)
	end
end

local function attachFolder(f: Instance)
	run.folder = f
	-- the vault's origin, from any part that does not move: its world position minus the position
	-- VaultFloor gave it. Streaming-safe: whichever part arrived first will do.
	for _, d in f:GetChildren() do
		local def = run.defs[d.Name]
		if def and d:IsA("BasePart") and def.group ~= "killplane" and def.group ~= "seal" then
			run.origin = (d :: BasePart).Position - vecOf(def.position)
			break
		end
	end
	for _, d in f:GetDescendants() do
		reskin(d)
	end
	run.added = f.DescendantAdded:Connect(reskin)
	for s = 0, run.model.storeys - 2 do
		local sh = run.model.shafts[s + 1]
		for _, p in sh.pads do
			local key = s .. ":" .. p.index
			run.pads[key] = { storey = s, index = p.index, top = p, part = nil, gone = false, crack = {} }
		end
	end
end

local function endRun()
	if run == nil then return end
	if run.added then run.added:Disconnect() end
	for key in run.pads do art:padCrackEnd(key) end
	run = nil
	inRun = false
	if Hazards.cancel(scheduler) then art:hideHazard(nil) end
	warning.Visible = false
	art:updateProps(nil, nil)
	art:updateWeather({}, nil)
	art:updateCollapse(nil, nil, nil, 0, 0)
	applyLayout()
end

local function startRun(data: any)
	endRun()
	local tier, floor = tonumber(data.tier), tonumber(data.floor)
	if tier == nil or floor == nil or Config.Tiers[tier] == nil then return end
	local ok, model, spec = pcall(function()
		local spec = Progression.difficulty(Config, tier, floor)
		spec.seed = Progression.seedFor(Config, tier, floor)
		return VaultFloor.build(Config, spec, MazeGen, Rng), spec
	end)
	if not ok then
		warn("[VaultFx] could not rebuild the vault's layout: " .. tostring(model))
		return
	end
	runSerial += 1
	local depth = VaultEnv.depth(Config, tier, floor)
	local defs = {}
	for _, d in model.parts do defs[d.name] = d end
	local pal = VaultEnv.palette(Config, EnvBands, depth)
	run = {
		serial = runSerial, tier = tier, floor = floor, depth = depth,
		model = model, spec = spec, defs = defs,
		pal = pal,
		gem = VaultEnv.gem(Config, pal, tier),
		-- the drop's ring, in colours that read against this stratum's floor (every storey's floor is
		-- painted pal.floor): following, and locked
		ringFollow = VaultEnv.ring(Config, pal.floor, false),
		ringLock = VaultEnv.ring(Config, pal.floor, true),
		band = EnvBands.indexAt(bands, depth),
		t = 0, timeLeft = tonumber(data.collapseSeconds) or 0, timeAt = 0,
		folder = nil, origin = nil, added = nil,
		pads = {},
	}
	inRun = true
	Rest.stop(rest)
	unsit()
	applyLayout()
	-- every run is a different vault somewhere else: its sky piece fades in from nothing, and the
	-- last vault's piece (which the player can no longer see) does not linger over this one
	for id in pieceW do pieceW[id] = 0 end

	-- a title card when the stratum changes; a fanfare the first time this player goes this deep
	local b = bands[run.band]
	if lastCardBand ~= run.band then
		lastCardBand = run.band
		local best = if floorsKnown then EnvBands.indexAt(bands, VaultEnv.deepestCleared(Config, floorsKnown)) else run.band
		local celebrate = floorsKnown ~= nil and run.band > best
		local tierName = Config.Tiers[tier].name
		showCard(b.emoji .. " " .. string.upper(b.name), string.format("%s · floor %d · %s", tierName, floor, b.blurb), celebrate)
	end
end

local remotes = ReplicatedStorage:WaitForChild("VaultRemotes", 30)
if remotes then
	local RunEvent = remotes:WaitForChild("Run", 10)
	local StateEvent = remotes:WaitForChild("State", 10)
	if RunEvent then
		(RunEvent :: RemoteEvent).OnClientEvent:Connect(function(kind, data)
			if kind == "start" and type(data) == "table" then
				startRun(data)
			elseif kind == "tick" and run and type(data) == "table" then
				run.timeLeft = tonumber(data.timeLeft) or run.timeLeft
				run.timeAt = run.t
			elseif kind == "end" then
				endRun()
			end
		end)
	end
	if StateEvent then
		(StateEvent :: RemoteEvent).OnClientEvent:Connect(function(s)
			if type(s) ~= "table" or type(s.tiers) ~= "table" then return end
			local floors = {}
			for i, t in s.tiers do floors[i] = tonumber(t.floor) or 1 end
			floorsKnown = floors
			tiersKnown = s.tiers
			if s.inRun == false and run ~= nil then endRun() end
		end)
	end
end

--============================================================================ rest (the hub only)

restBtn.Activated:Connect(function()
	if not restOn or inRun then return end
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
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = grounded, threat = inRun })
	if result == "resting" then
		sat = true
		restFocus.Enabled = true
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
	end
end)

--============================================================================ the hub's set pieces

local hubBuilt = false
local emblems: { [number]: TextLabel } = {}
local function buildHub()
	if hubBuilt then return end
	local hub = workspace:FindFirstChild("Hub")
	if hub == nil then return end
	hubBuilt = true
	-- the great vault door behind the portals
	local portal = hub:FindFirstChild("Portal_2")
	local z = if portal then (portal :: BasePart).Position.Z - 14 else Config.Hub.PortalZ - 14
	art:buildHubDoor(Vector3.new(0, 25, z))
	-- which stratum each vault's next floor is in, on a local sign under its portal's name label.
	-- BOTH ARE FIXED-PIXEL BILLBOARDS, so the sign is anchored at the SAME world point as the server's
	-- label and pushed below it in PIXELS: a gap in studs shrinks on screen with distance, and the
	-- first cut (6 studs apart) overlapped the label from the spawn view on a phone
	-- (robloxemu/check_vaultrunners_readable.luau §3). The label's own offset and height are read
	-- from the server's BillboardGui, so a change there cannot bring the overlap back.
	local SIGN_W, SIGN_H, SIGN_GAP = 220, 34, 4
	for i = 1, #Config.Tiers do
		local p = hub:FindFirstChild("Portal_" .. i)
		if p then
			local label = p:FindFirstChild("Label")
			local labelOffset = Vector3.new(0, 9, 0)
			local labelH = 60
			if label and label:IsA("BillboardGui") then
				labelOffset = (label :: BillboardGui).StudsOffset
				labelH = (label :: BillboardGui).Size.Y.Offset
			end
			local anchor = Instance.new("Part")
			anchor.Name = "PortalSign_" .. i
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.CanTouch = false
			anchor.CastShadow = false
			anchor.Transparency = 1
			anchor.Size = Vector3.new(1, 1, 1)
			anchor.CFrame = CFrame.new((p :: BasePart).Position + labelOffset)
			anchor.Parent = folder
			-- centred on the label's point, tall enough that its bottom SIGN_H px sit SIGN_GAP px under
			-- the label's bottom edge; the rest of it is empty and see-through
			local half = labelH / 2 + SIGN_GAP + SIGN_H
			local bb = Instance.new("BillboardGui")
			bb.Name = "Stratum"
			bb.Size = UDim2.fromOffset(SIGN_W, 2 * half)
			bb.AlwaysOnTop = true
			bb.MaxDistance = 90
			local t = Instance.new("TextLabel")
			t.Name = "Text"
			t.BackgroundTransparency = 1
			t.Position = UDim2.new(0, 0, 1, -SIGN_H)
			t.Size = UDim2.new(1, 0, 0, SIGN_H)
			t.Font = Enum.Font.GothamBold
			t.TextScaled = true
			t.TextColor3 = Color3.fromRGB(240, 236, 250)
			t.TextStrokeTransparency = 0.4
			t.Text = ""
			t.Parent = bb
			bb.Parent = anchor
			emblems[i] = t
		end
	end
end

local function paintEmblems()
	if tiersKnown == nil then return end
	for i, t in tiersKnown :: { any } do
		local label = emblems[i]
		if label then
			local text
			if t.unlocked then
				local b = bands[EnvBands.indexAt(bands, VaultEnv.depth(Config, i, tonumber(t.floor) or 1))]
				text = string.format("Floor %d · %s %s", tonumber(t.floor) or 1, b.emoji, b.name)
			else
				text = "🔒"
			end
			if label.Text ~= text then label.Text = text end
		end
	end
end

--============================================================================ the frame

local function frame(dt: number)
	now += dt
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	if not hubBuilt then buildHub() end
	paintEmblems()
	art:step(dt)

	local camPos = camera.CFrame.Position
	local r = run
	if r then
		r.t += dt
		if r.folder == nil then
			local vaults = workspace:FindFirstChild("Vaults")
			local f = vaults and vaults:FindFirstChild("Vault_" .. tostring(player.UserId))
			if f then attachFolder(f) end
		end
	end
	local model = r and r.model
	local origin: Vector3? = r and r.origin
	local lp: Vector3? = nil -- the root, vault-local
	if r and origin and hrp then
		lp = (hrp :: BasePart).Position - (origin :: Vector3)
	end
	local loc = if lp and model then VaultEnv.locate(Config, model, { x = lp.X, y = lp.Y, z = lp.Z }) else nil
	local inShaft = if lp and model then VaultEnv.inShaft(Config, model, { x = lp.X, y = lp.Y, z = lp.Z }) else false
	local shaftScale = if inShaft then Env.ShaftWeatherScale else 1

	-- the collapse, from the plane the server moves
	local danger, planeY = 0, nil
	if r and r.folder and origin and model then
		local plane = (r.folder :: Instance):FindFirstChild("Collapse")
		if plane and plane:IsA("BasePart") then
			planeY = (plane :: BasePart).Position.Y - (origin :: Vector3).Y
			if lp then danger = VaultEnv.danger(Config, model, planeY :: number, lp.Y) end
		end
	end

	-- lighting: the band (or the hub), graded toward the collapse, gliding, at LightingHz
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		local target = {}
		for _, g in GROUPS do
			local s = if r then EnvBands.sample(bands, r.depth, g) else table.clone(Env.Hub[g])
			local over = Env.Danger[g]
			if over and danger > 0 then
				s = EnvBands.overlay(s, over, danger * Env.MaxDangerBlend)
			end
			target[g] = s
		end
		if current == nil then
			-- start from the server's own preset (Env.Hub is Fx.Presets.Cozy's numbers): no jump at join
			current = {}
			for _, g in GROUPS do (current :: any)[g] = table.clone(Env.Hub[g]) end
		end
		for _, g in GROUPS do
			(current :: any)[g] = EnvBands.approachTable((current :: any)[g], target[g], step, Env.HalfLife)
			writeGroup(targets[g], (current :: any)[g])
		end
	end

	-- scenery: props on this storey's ceiling and the next, the set piece over the top storey
	if r and origin and model and loc then
		local S, H = model.cellSize, model.storeyHeight
		local wallH = model.wallHeight
		local key = r.serial .. ":" .. loc.storey
		if key ~= art.propKey then
			local pal = r.pal
			local a, b = bands[pal.band], bands[pal.next]
			local density = a.props.density + (b.props.density - a.props.density) * pal.t
			local sites = {}
			for s = loc.storey, math.min(loc.storey + Env.PropStoreysAbove, model.storeys - 2) do
				for _, site in VaultEnv.propSites(model, s, r.spec.seed, density) do
					local kind = if site.roll < pal.t then b.props.kind else a.props.kind
					local x = (2 * site.cx + 1 - (model.gCols - 1) / 2) * S
					local z = (2 * site.cy + 1 - (model.gRows - 1) / 2) * S
					table.insert(sites, {
						pos = (origin :: Vector3) + Vector3.new(x, s * H + wallH, z),
						kind = kind, yaw = site.roll * math.pi * 2,
						accent = rgb(pal.accent), glow = rgb(pal.glow),
					})
				end
			end
			art:updateProps(key, sites)
		end
	end
	do
		local want: { [string]: number } = {}
		if r and origin and model then
			local pal = r.pal
			want[bands[pal.band].piece] = (want[bands[pal.band].piece] or 0) + (1 - pal.t)
			if pal.t > 0 then want[bands[pal.next].piece] = (want[bands[pal.next].piece] or 0) + pal.t end
		end
		for _, b in bands do
			local id = b.piece
			pieceW[id] = EnvBands.approach(pieceW[id] or 0, want[id] or 0, dt, Env.HalfLife)
			if pieceW[id] < 0.005 and (want[id] or 0) == 0 then pieceW[id] = 0 end
		end
		local anchor = nil
		if r and origin and model then
			local topY = (model.storeys - 1) * model.storeyHeight + model.wallHeight
			anchor = CFrame.new((origin :: Vector3) + Vector3.new(0, topY + 110, 0))
		end
		art:updatePieces(if anchor then pieceW else {}, anchor, now, r and r.pal)
	end

	-- weather around the camera, capped (at most MaxWeatherEmitters kinds, MaxWeatherRate in all)
	do
		local rates: { [string]: number } = {}
		if r and origin then
			local pal = r.pal
			local a, b = bands[pal.band], bands[pal.next]
			if VaultArt.hasWeather(a.weather.kind) then rates[a.weather.kind] = (rates[a.weather.kind] or 0) + a.weather.rate * (1 - pal.t) * shaftScale end
			if pal.t > 0 and VaultArt.hasWeather(b.weather.kind) then
				rates[b.weather.kind] = (rates[b.weather.kind] or 0) + b.weather.rate * pal.t * shaftScale
			end
		end
		art:updateWeather(EnvBands.capRates(rates, Budget.MaxWeatherEmitters, Budget.MaxWeatherRate, 0.1), camPos)
	end

	-- the collapse: dust out of the ceiling over you, sparks off the plane, and the odd rumble
	if r and origin and model and loc and planeY then
		local o = origin :: Vector3
		local ceilingCF = nil
		if loc.storey < model.storeys - 1 then
			ceilingCF = CFrame.new(Vector3.new(camPos.X, o.Y + loc.storey * model.storeyHeight + model.wallHeight - 0.3, camPos.Z))
		end
		local planeCF = CFrame.new(o + Vector3.new(0, (planeY :: number) + 1.5, 0))
		art:updateCollapse(ceilingCF, planeCF, Vector3.new(model.footprint.w, 0.4, model.footprint.d),
			(1.5 + 10 * danger) * shaftScale, 3 + 15 * danger)
	else
		art:updateCollapse(nil, nil, nil, 0, 0)
	end

	-- the obby: cracks where you stand, debris when a pad goes, a flash when it comes back. The look
	-- follows the SERVER's pad (VaultEnv.padLook): the crack is held at full until the server's drop
	-- arrives, never "whole again" a beat before the pad falls, and a pad landed on while it still
	-- flashes "it's back" is cracking, not flashing (robloxemu/check_vaultrunners_shaft.luau §5).
	if r and r.folder and origin and model then
		local o = origin :: Vector3
		-- which pad the runner stands on, by geometry alone: whether it is still there is the server's
		-- word (its Transparency), not this client's clock
		local standS, standK = nil, nil
		if lp then standS, standK = Ascent.padUnder(Config, model, { x = lp.X, y = lp.Y, z = lp.Z }) end
		for key, pad in r.pads do
			if pad.part == nil or pad.part.Parent == nil then
				pad.part = (r.folder :: Instance):FindFirstChild(string.format("Step_%d_%d", pad.storey, pad.index))
			end
			local part = pad.part :: BasePart?
			if part then
				local top = o + Vector3.new(pad.top.x, pad.top.y, pad.top.z)
				local gone = part.Transparency > 0.5
				if gone ~= pad.gone then
					pad.gone = gone
					if gone then
						art:burst(top - Vector3.new(0, 0.5, 0), rgb(VaultEnv.crackedPad(Config, r.pal, 1)), 3, 5)
					end
				end
				local standing = standK ~= nil and standS == pad.storey and standK == pad.index
				local look, amount = VaultEnv.padLook(Config, pad.crack, standing, gone, r.t)
				-- colour writes only when the look changes (a crack step, a flash step, back to whole)
				local colour, colourKey = r.pal.pad, "whole"
				if look == "crack" then
					local progress = amount :: number
					art:padCrack(key, top, progress)
					colourKey = "crack" .. math.floor(progress * 20)
					colour = VaultEnv.crackedPad(Config, r.pal, progress)
				else
					art:padCrackEnd(key)
					if look == "flash" then
						local k = amount :: number
						local p = r.pal.pad
						colourKey = "flash" .. math.floor(k * 10)
						colour = { p[1] + (255 - p[1]) * k * 0.7, p[2] + (255 - p[2]) * k * 0.7, p[3] + (255 - p[3]) * k * 0.7 }
					end
				end
				if colourKey ~= pad.colourKey then
					pad.colourKey = colourKey
					part.Color = rgb(colour)
				end
			end
		end
	end

	local rootPart = hrp
	local humanoid = hum
	local grounded, moving = false, false
	if rootPart and humanoid then
		if knockUntil and now >= knockUntil then
			knockUntil = nil
			pcall(function() (humanoid :: Humanoid).PlatformStand = false end)
		end
		local fm = (humanoid :: any).FloorMaterial
		grounded = fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
		local md = (humanoid :: any).MoveDirection
		moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true
	end

	-- the rumble: more often, and harder, the closer the collapse (never on the pads)
	if r and danger > 0.25 and grounded and not inShaft then
		rumbleIn -= dt
		if rumbleIn <= 0 then
			rumbleIn = 9 - 6 * danger
			FxClient.shake(0.35, 0.12 + 0.3 * danger)
		end
	end

	-- rest: the hub only. "Threat" is a run: rest can never start, or be queued, inside a vault.
	if restOn and rootPart and humanoid then
		local supported = grounded
		if sat and not grounded and knockUntil == nil then
			supported = math.abs((rootPart :: BasePart).AssemblyLinearVelocity.Y) < 2
		end
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = inRun })
		if ev == "started" and rest.source == "manual" then
			sat = true
			restFocus.Enabled = true
			pcall(function() (humanoid :: Humanoid).Sit = true end)
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
	end
	local resting = restOn and Rest.isResting(rest)

	-- ceiling drops: only in a run, only where VaultEnv says one may land
	if hazardsOn then
		local paused = not (r and origin and model and rootPart and humanoid)
		local eligible = false
		local aim = nil
		if not paused and lp and model then
			aim = { x = lp.X, y = lp.Y, z = lp.Z }
			local timeLeft = math.max(0, r.timeLeft - (r.t - r.timeAt))
			eligible = grounded and VaultEnv.hazardEligible(Config, model, aim, { elapsed = r.t, timeLeft = timeLeft, danger = danger })
		end
		local before = if scheduler.active then scheduler.active.t else nil
		-- the kinds of the last run's band even in the hub: paused + kinds HOLDS a due drop (it
		-- launches at the first eligible moment of the next run), where an empty list would re-roll it
		if r then lastBand = r.band end
		local ev = Hazards.step(scheduler, Hz, dt, {
			paused = paused,
			eligible = eligible,
			kinds = bands[lastBand].hazards or {},
			aim = aim,
		}, rand)
		if ev and ev.type == "done" then
			art:hideHazard(ev.plan.kind)
		end
		local plan = scheduler.active
		if plan and r and origin and model and rootPart and humanoid then
			local o = origin :: Vector3
			local pos = Hazards.positionAt(plan, plan.t)
			local zone = Hazards.zone(plan, Hz.PlayerRadius)
			-- the storey's own floor and ceiling, never "the root minus RunnerRootHeight": an avatar whose
			-- root sits higher or lower than the model's 3 studs would float the ring and the landed chunk
			-- above the floor, or sink them into it
			local zs = VaultEnv.locate(Config, model, { x = zone.x, y = zone.y, z = zone.z }).storey
			local floorY = o.Y + zs * model.storeyHeight
			local ceiling = floorY + model.wallHeight
			local landed = plan.t >= plan.arriveAt
			-- 0 while it hangs, 1 once it is down: the rule's point falls from dropHeight over the root to
			-- the root; the art hangs the model off the ceiling and lays it on the floor along the same curve
			local fall = math.clamp(1 - (pos.y - plan.target.y) / plan.dropHeight, 0, 1)
			art:showHazard(plan.kind, o + vecOf(pos), {
				centre = Vector3.new(o.X + zone.x, floorY, o.Z + zone.z), radius = zone.radius,
			}, ceiling, plan.locked, landed, now, fall, if plan.locked then r.ringLock else r.ringFollow)
			if before ~= nil and before < plan.arriveAt and plan.t >= plan.arriveAt then
				-- the landing: debris, a dust burst, and a shake that fades with distance
				local here = (rootPart :: BasePart).Position
				local land = o + vecOf(plan.target)
				art:burst(land, rgb(r.pal.wall), 5, 10)
				local dist = (Vector3.new(here.X, 0, here.Z) - Vector3.new(land.X, 0, land.Z)).Magnitude
				-- ...but never on a runner in the climb shaft: a drop can only have started before they
				-- stepped in, and a camera that jolts mid-hop is a pad nobody can read (the rumble above
				-- follows the same rule). robloxemu/check_vaultrunners_shaft.luau §3.
				if not inShaft then
					FxClient.shake(0.3, 0.6 * math.clamp(1 - dist / 40, 0.15, 1))
				end
			end
			if lp and Hazards.checkHit(plan, before or 0, plan.t, { x = lp.X, y = lp.Y, z = lp.Z }, Hz.PlayerRadius) then
				plan.hit = true
				local look = camera.CFrame.LookVector
				local kv = Hazards.knockVelocity(Hz, plan, { x = lp.X, y = lp.Y, z = lp.Z }, { x = -look.X, y = 0, z = -look.Z })
				pcall(function() (humanoid :: Humanoid).PlatformStand = true end)
				local body = rootPart :: BasePart
				body.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				FxClient.shake(0.4, 0.9)
				FxClient.flash(Color3.fromRGB(255, 255, 255), 0.3, 0.35)
			end
			if plan.t < plan.arriveAt and not plan.hit then
				local name = (Hz.Kinds[plan.kind] and Hz.Kinds[plan.kind].name) or string.upper(plan.kind)
				local text = if plan.locked then "⚠️ MOVE! " .. name .. " ⬇" else "⚠️ " .. name .. " — keep moving!"
				if warningText.Text ~= text then warningText.Text = text end
				warning.BackgroundColor3 = if plan.locked then Color3.fromRGB(150, 20, 20) else Color3.fromRGB(120, 70, 10)
				warning.Visible = true
			else
				warning.Visible = false
			end
		else
			warning.Visible = false
		end
	end

	-- the chip
	local chipText
	if r then
		local b = bands[r.band]
		chipText = b.emoji .. " " .. b.name
		local nextIdx, remaining = EnvBands.nextBand(bands, r.depth)
		if nextIdx then
			local n = math.max(1, math.ceil(remaining :: number))
			chipText ..= string.format("  ·  %s in %d floor%s", bands[nextIdx].emoji, n, if n == 1 then "" else "s")
		end
	elseif resting then
		chipText = "☕ Resting — the vault waits for you"
	elseif rest.pending then
		chipText = "☕ Stand still to rest"
	else
		local deepest = if floorsKnown then EnvBands.indexAt(bands, VaultEnv.deepestCleared(Config, floorsKnown)) else 1
		local b = bands[deepest]
		chipText = "🏠 Hub · deepest: " .. b.emoji .. " " .. b.name
	end
	if chip.Text ~= chipText then chip.Text = chipText end
	local btnText = if resting then "▶ Play" elseif rest.pending then "☕ …" else "☕ Rest"
	if restBtn.Text ~= btnText then restBtn.Text = btnText end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken frame must not flood the output
		warn("[VaultFx] frame error: " .. tostring(err))
	end
end)
