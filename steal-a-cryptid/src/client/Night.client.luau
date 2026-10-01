-- STEAL A CRYPTID - the night over Pine Hollow. Client only (StarterPlayerScripts). EYECANDY.md.
--
-- What this script does, every frame, for THIS player only:
--   * reads the Journal's rank the server reports in State (the game's own progress value: the highest
--     tier ever owned, which already drives the pedestals and the camps) and blends the HOME bands in
--     Config.Night.Home: the rarer your collection, the deeper the night (dusk -> moonrise -> strange
--     lights -> mythic night), and past the Mythic, once the best lair income ever (State.best) reaches
--     GatheringRate, the gathering (Night.level). In a camp pocket it blends that camp tier's own place instead;
--   * glides every written value (lighting, sky, scenery, critters, weather), so a new rank or a raid's
--     teleport never hard-cuts, and keeps every frame above the readability floor (Night.readable);
--   * dresses YOUR OWN occupied cages with a habitat per species (the rarest one lit);
--   * runs rare, telegraphed hazards at home only (Night.stepGate), and the rest rules (Rest).
--
-- Why all of it is client-side, and why that is safe:
--   * it is cosmetic, or it only ever harms the local player, whose character physics the client owns.
--     This script fires no remote and sets no attribute; the server does not know hazards or rest exist
--     and trusts nothing from here. Rest pauses only the hazards below: poachers, jars, raids, heat and
--     permits are the server's and do not change;
--   * it reads only the local character, the local camera, Config, this player's own State (rank, best, plot,
--     cages, raid, tutorial, build mode, poacher) and public workspace geometry (the road's Ground, its
--     pine crowns, this player's own cage bases). No other player's state; nothing about a camp's
--     traps or cages: camp scenery depends on the camp's TIER only and keeps out of the camp itself.
-- Headless checks: robloxemu/check_stealacryptid_night.luau, _hazards.luau, _rest.luau, _nighthud.luau,
-- _edge.luau (the ravine, and knocks near the edge) and _view.luau (nothing local between the camera and
-- the camp or the player), among the rest listed in CLAUDE.md.

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
local Night = require(ReplicatedStorage:WaitForChild("Night"))
local NightArt = require(ReplicatedStorage:WaitForChild("NightArt"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local N = Config.Night
local Home, Camp, Hz, RestCfg = N.Home, N.Camp, N.Hazards, N.Rest

-- A broken config must cost the polish, never the game: warn loudly and switch the part off.
do
	local ok, err = Night.validate(Config, EnvBands)
	if not ok then
		warn("[CryptidNight] Config.Night is invalid (" .. tostring(err) .. "); the night stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then
	warn("[CryptidNight] Config.Night.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then
	warn("[CryptidNight] Config.Night.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.")
end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

--============================================================================ local world + lighting rig

local folder = Instance.new("Folder")
folder.Name = "CryptidNight"
folder.Parent = workspace

local art = NightArt.new(folder, rand, Config, EnvBands, Night)

-- Take over the server's Fx.applyLighting objects by name, so the client glides on from exactly the
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
	sky = rig("Sky", "CryptidSky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "CryptidSunRays"),
}
pcall(function() (targets.sky :: any).CelestialBodiesShown = true end)

-- Soft focus while resting at home (never in a camp: DESIGN.md 13, it blurs the far side of a camp).
local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "CryptidRestFocus"
restFocus.FarIntensity = 0.25
restFocus.FocusDistance = 16
restFocus.InFocusRadius = 28
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
				value = Color3.fromRGB(math.clamp(math.round(v[1]), 0, 255), math.clamp(math.round(v[2]), 0, 255), math.clamp(math.round(v[3]), 0, 255))
			elseif k == "ClockTime" then
				value = Night.clockTime(v) -- night hours -> 0..24
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

--============================================================================ title card (own ScreenGui)

local gui = Instance.new("ScreenGui")
gui.Name = "CryptidNight"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 1
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function capText(i: Instance, px: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = px
	c.Parent = i
end
local card = Instance.new("TextLabel")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.BackgroundTransparency = 1
card.Font = Enum.Font.GothamBlack
card.TextColor3 = Color3.fromRGB(255, 244, 220)
card.TextStrokeTransparency = 0.4
card.TextScaled = true
card.Text = ""
card.Visible = false
card.Parent = root
capText(card, 44)
local cardSub = Instance.new("TextLabel")
cardSub.Name = "CardSub"
cardSub.AnchorPoint = Vector2.new(0.5, 0)
cardSub.BackgroundTransparency = 1
cardSub.Font = Enum.Font.GothamBold
cardSub.TextColor3 = Color3.fromRGB(225, 230, 245)
cardSub.TextStrokeTransparency = 0.5
cardSub.TextScaled = true
cardSub.Text = ""
cardSub.Visible = false
cardSub.Parent = root
capText(cardSub, 20)

-- the card's smallest legible heights (design px): the title stays >= 11 screen px at the phone scale 0.6, the
-- subtitle >= 85 % of its 20-px cap (check_stealacryptid_nighthud's legibility rule)
local CARD_MIN_TITLE, CARD_MIN_SUB = 22, 20
local subFits = true
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
	local layout = Responsive.layout(vx, vyDraw, UserInputService.TouchEnabled, vy)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
	local rootW, rootH = vx / layout.scale, vyDraw / layout.scale
	local w = math.min(760, rootW - 2 * Responsive.MARGIN)
	local cardH = math.min(64, rootH * 0.13)
	local subH = math.min(28, rootH * 0.06)
	-- Centred at 46 % of the height where there is room; never over the HUD's top stack (its lines, the chip's
	-- slot) and never into the touch-control band: the HUD says where that room is, in the same design px
	-- (NightBus CardTop / CardBottom). Second review of the night, 2026-09-30, finding 4: at a fixed 46 % the card
	-- crossed the chip (800x360) and the toast (640x300).
	local top = rootH * 0.46 - cardH / 2
	local pg = player:FindFirstChild("PlayerGui")
	local hudGui = pg and pg:FindFirstChild("CryptidHud")
	local nb = hudGui and hudGui:FindFirstChild("NightBus")
	local ct = nb and nb:FindFirstChild("CardTop")
	local cb = nb and nb:FindFirstChild("CardBottom")
	subFits = true
	if ct and (ct :: any).Value > 0 then
		local stackBottom = (ct :: any).Value
		top = math.max(top, stackBottom)
		local bottom = if cb and (cb :: any).Value > 0 then (cb :: any).Value else rootH
		if top + cardH + 4 + subH > bottom then
			-- not enough room at full size: sit right under the stack; shrink the title first (to CARD_MIN_TITLE),
			-- keep the subtitle legible (CARD_MIN_SUB), and on a very short screen show the title alone
			top = stackBottom
			local room = bottom - top
			if cardH + 4 + subH > room then
				local sub = math.min(subH, math.max(CARD_MIN_SUB, room - 4 - cardH))
				local title = math.min(cardH, room - 4 - sub)
				if title >= CARD_MIN_TITLE then
					cardH, subH = title, sub
				else
					subFits = false
					cardH = math.max(CARD_MIN_TITLE, math.min(cardH, room))
				end
			end
		end
	end
	card.Position = UDim2.fromOffset(rootW / 2, top + cardH / 2)
	card.Size = UDim2.fromOffset(w, cardH)
	cardSub.Position = UDim2.fromOffset(rootW / 2, top + cardH + 4)
	cardSub.Size = UDim2.fromOffset(w, subH)
	if card.Visible and not subFits then cardSub.Visible = false end
end
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
-- the HUD moves its top stack (a banner, a chip) and says so on its NightBus: follow it
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")
	local hudGui = pg:WaitForChild("CryptidHud", 30)
	local nb = hudGui and hudGui:WaitForChild("NightBus", 30)
	if not nb then return end
	for _, name in { "CardTop", "CardBottom" } do
		local v = nb:WaitForChild(name, 30)
		if v then v:GetPropertyChangedSignal("Value"):Connect(applyLayout) end
	end
	applyLayout()
end)
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)

local cardToken = 0
local pendingCard: { string }? = nil -- a band reached while a panel was open: named once it closes
local function showCard(title: string, sub: string)
	cardToken += 1
	local mine = cardToken
	card.Text = title
	cardSub.Text = sub
	card.TextTransparency = 0
	cardSub.TextTransparency = 0
	card.Visible = true
	cardSub.Visible = subFits
	task.delay(3.5, function()
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
local function hideCard()
	cardToken += 1
	card.Visible = false
	cardSub.Visible = false
end

--============================================================================ the player's State (own)

local state: any = nil
-- the home sky's level (Night.level): the Journal's rank, then the gathering past the Mythic once State.best (the
-- best lair income ever, the Top Lairs board's metric) reaches Config.Night.GatheringRate
local level = 0
local lastRaidTier: number? = nil
local remotes = ReplicatedStorage:WaitForChild("CryptidRemotes")
remotes:WaitForChild("State").OnClientEvent:Connect(function(s)
	if type(s) ~= "table" then return end
	state = s
	level = Night.level(Config, s, level)
end)
remotes:WaitForChild("Fx").OnClientEvent:Connect(function(kind, data)
	if kind == "raidStart" and type(data) == "table" then
		lastRaidTier = tonumber(data.tier)
	end
end)

-- public geometry: the road's Ground (for the far scenery and the edge rule) and its pine crowns (owls).
-- A LocalScript can start before the server's workspace has reached this client, so the road is looked
-- for until it is found (once a second), and hazards wait for it: without the Ground the edge rule cannot
-- be judged (check_stealacryptid_lateroad.luau).
local groundRect = nil
local roadLookAt = -math.huge
local function findRoad(t: number)
	if groundRect ~= nil or t - roadLookAt < 1 then return end
	roadLookAt = t
	local road = workspace:FindFirstChild("Road")
	local ground = road and road:FindFirstChild("Ground")
	if not (ground and ground:IsA("BasePart")) then return end
	groundRect = { cx = ground.Position.X, cz = ground.Position.Z, sx = ground.Size.X, sz = ground.Size.Z }
	local perches = {}
	for _, c in (road :: Instance):GetChildren() do
		if c:IsA("BasePart") and string.sub(c.Name, 1, 10) == "PineCrown_" then
			table.insert(perches, c.Position + Vector3.new(0, c.Size.Y / 2, 0))
		end
	end
	art:setHome(groundRect, perches)
end
findRoad(0)

-- the HUD's side of the contract (Hud.client builds it): the Rest button's presses in, labels out
local bus: Instance? = nil
local seenPresses: number? = nil
local function findBus()
	if bus and bus.Parent then return bus end
	local pg = player:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("CryptidHud")
	bus = hud and hud:FindFirstChild("NightBus")
	if bus then
		local presses = bus:FindFirstChild("RestPresses")
		seenPresses = if presses then (presses :: any).Value else 0
	end
	return bus
end
local function busSet(name: string, value: string)
	local b = findBus()
	local v = b and b:FindFirstChild(name)
	if v and (v :: any).Value ~= value then (v :: any).Value = value end
end
local function hudPanelOpen(): boolean
	local pg = player:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("CryptidHud")
	local r = hud and hud:FindFirstChild("Root")
	if not r then return false end
	for _, name in { "HuntPanel", "BuildSheet" } do
		local p = r:FindFirstChild(name)
		if p and (p :: any).Visible then return true end
	end
	return false
end

-- my own cage bases (server-built, public), refreshed when the State changes and every 2 s
local function cageBases(): { [number]: CFrame }
	local out = {}
	if not state or state.plot == nil then return out end
	local lairs = workspace:FindFirstChild("Lairs")
	local plot = lairs and lairs:FindFirstChild("Plot_" .. tostring(state.plot))
	local lair = plot and plot:FindFirstChild("Lair")
	local cages = lair and lair:FindFirstChild("Cages")
	if not cages then return out end
	for col = 1, 9 do
		local base = cages:FindFirstChild("Cage_" .. col)
		if base and base:IsA("BasePart") then
			out[col] = base.CFrame * CFrame.new(0, base.Size.Y / 2, 0)
		end
	end
	return out
end

--============================================================================ state

local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil

local now = 0
local homeW: { [number]: number } = {}
local campW: { [number]: number } = {}
local current: { [string]: any }? = nil -- smoothed lighting groups
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local scheduler = Hazards.newScheduler(Hz, rand)
local gate = Night.newGate()
local rest = Rest.new()
local sat = false
local knockUntil: number? = nil
local lastScene = "home"
local lastState = nil
local bases: { [number]: CFrame } = {}
local basesAge = math.huge
local campfireCF: CFrame? = nil
local frameError = false

local homePieces, campPieces = {}, {}
for _, b in Home do for _, id in b.pieces do homePieces[id] = true end end
for _, b in Camp do for _, id in b.pieces do campPieces[id] = true end end
local SKY = { auroraGreen = true, auroraGold = true, bloodMoon = true }

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

local function clearKnock()
	if knockUntil and hum then
		pcall(function() (hum :: Humanoid).PlatformStand = false end)
		if hrp then pcall(function() (hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero end) end
	end
	knockUntil = nil
end

local function cancelHazard()
	if scheduler.active then
		art:hideHazard(scheduler.active.kind)
		scheduler.active = nil
	end
end

local function bindCharacter(char: Model)
	character = char
	hrp = nil
	hum = nil
	rest = Rest.new()
	sat = false
	restFocus.Enabled = false
	knockUntil = nil
	campfireCF = nil
	cancelHazard()
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local function grounded(): boolean
	if not hum then return false end
	local fm = (hum :: any).FloorMaterial
	return fm ~= nil and fm ~= Enum.Material.Air
end

-- the Rest button (the HUD's): toggle
local function onRestPressed(scene: string)
	if not restOn then return end
	if Rest.isResting(rest) or rest.pending then
		Rest.stop(rest)
		unsit()
		return
	end
	if scene ~= "home" then return end -- no rest in a camp (the button is gone there)
	-- Mid-stumble the press is QUEUED like any press with a hazard about ("Rest...", and the chip says rest
	-- starts when the sky is clear): a stumbling player is not on their feet. It used to be dropped with no
	-- word (second review of the night, 2026-09-30, finding 2: standard section 1, no silent no-ops).
	local onFeet = (grounded() or sat) and knockUntil == nil
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = onFeet, threat = scheduler.active ~= nil })
	if result == "resting" then
		sat = true
		restFocus.Enabled = true
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
		campfireCF = nil
	end
end

--============================================================================ the frame

local function frame(dt: number)
	now += dt
	findRoad(now)
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camCF = camera.CFrame
	local camPos = camCF.Position
	local loaded = state ~= nil and hrp ~= nil

	-- where am I: home, or a camp of which tier (from my root's position; the tier from the server)
	local x = if hrp then (hrp :: BasePart).Position.X else 0
	local scene, tier, slot = Night.scene(Config, x, state, lastRaidTier)
	art:setPocket(if slot then Night.pocketOriginX(Config, slot :: number) else nil)
	local sceneChanged = scene ~= lastScene
	lastScene = scene
	if sceneChanged then
		-- a teleport: no stumble or rest crosses it, and a hazard from home never follows into a camp
		clearKnock()
		Rest.stop(rest)
		unsit()
		cancelHazard()
	end

	-- band weights: the scene you are in blends in, the other fades out; both glide (no cut)
	local homeTarget = EnvBands.weights(Home, level)
	local campTarget = EnvBands.weights(Camp, (tier or 1) - 1)
	-- (everything starts at 0 and fades in once my State has arrived: nothing pops in at join)
	for i = 1, #Home do
		local t = if loaded and scene == "home" then (homeTarget[i] or 0) else 0
		homeW[i] = EnvBands.approach(homeW[i] or 0, t, dt, N.HalfLife)
	end
	for j = 1, #Camp do
		local t = if loaded and scene == "camp" then (campTarget[j] or 0) else 0
		campW[j] = EnvBands.approach(campW[j] or 0, t, dt, N.HalfLife)
	end

	-- lighting at LightingHz, only once the State (my level) is known: until then the server's stays
	lightAccum += dt
	if loaded and (current == nil or lightAccum >= 1 / N.LightingHz) then
		local step = if current == nil then 0 else lightAccum
		lightAccum = 0
		local target = {}
		for _, g in Night.GROUPS do
			target[g] = if scene == "camp" then EnvBands.sample(Camp, (tier :: number) - 1, g) else EnvBands.sample(Home, level, g)
		end
		if current == nil then
			-- start from the game as it shipped (the server's preset) and glide to where this player is
			local base = Night.baseGroups(Config)
			current = {}
			for _, g in Night.GROUPS do (current :: any)[g] = base[g] end
		end
		for _, g in Night.GROUPS do
			(current :: any)[g] = EnvBands.approachTable((current :: any)[g], target[g], step, N.HalfLife)
		end
		for _, g in Night.GROUPS do
			writeGroup(targets[g], (current :: any)[g])
		end
	end

	-- scenery: world-anchored pieces of the other scene are thousands of studs away and go at once;
	-- sky pieces fade with the band weights
	local pieceW: { [string]: number } = {}
	local critters: { [string]: number } = {}
	local weather: { [string]: number } = {}
	for i, b in Home do
		local w = homeW[i] or 0
		if w > 0.001 then
			for _, id in b.pieces do pieceW[id] = math.min(1, (pieceW[id] or 0) + w) end
			if scene == "home" then
				for _, a in b.ambient do critters[a.kind] = (critters[a.kind] or 0) + a.count * w end
			end
			if b.weather then weather[b.weather.kind] = (weather[b.weather.kind] or 0) + b.weather.rate * w end
		end
	end
	for j, b in Camp do
		local w = campW[j] or 0
		if w > 0.001 then
			for _, id in b.pieces do pieceW[id] = math.min(1, (pieceW[id] or 0) + w) end
			if scene == "camp" then
				for _, a in b.ambient do critters[a.kind] = (critters[a.kind] or 0) + a.count * w end
			end
			if b.weather then weather[b.weather.kind] = (weather[b.weather.kind] or 0) + b.weather.rate * w end
		end
	end
	-- at home, keep the player in view: no horizon piece may stand between the camera and the root
	art:setViewTarget(if hrp and scene == "home" then (hrp :: BasePart).Position else nil)
	for id in homePieces do
		local w = pieceW[id] or 0
		if scene ~= "home" and not SKY[id] then w = 0 end
		art:updatePiece(id, w, camPos, now)
	end
	for id in campPieces do
		local w = pieceW[id] or 0
		if scene ~= "camp" then w = 0 end
		art:updatePiece(id, w, camPos, now)
	end
	for kind, n in critters do critters[kind] = math.floor(n + 0.5) end
	local keepOut = nil
	if scene == "camp" and slot then
		-- no critter in the camp or its corridor (Night.critterClear), nor between the camera and the camp
		-- (Night.campViewHull: review 2026-09-24, finding 3). 3 studs along each axis covers what a critter DRAWS
		-- round its centre: wings, bob and halo (a wisp: 2.9); a bigger one names its own reach (the Jersey Devil: 7)
		local ox = Night.pocketOriginX(Config, slot :: number)
		local hull = Night.campViewHull(Config, camPos.X - ox, camPos.Z)
		keepOut = function(p: Vector3, reach: number?): boolean
			local lx = p.X - ox
			local r = reach or 3
			return not Night.critterClear(Config, lx, p.Z, r) or Night.boxOverlapsHull(hull, lx - r, lx + r, p.Z - r, p.Z + r)
		end
	end
	art:updateCritters(critters, camPos, dt, now, keepOut)
	art:updateWeather(weather, camPos, if scene == "camp" then "campBack" else "camera")

	-- habitats: my own occupied cages, at home only
	basesAge += dt
	if state ~= lastState or basesAge >= 2 then
		bases = cageBases()
		basesAge = 0
		lastState = state
	end
	local habs = Night.habitats(Config, state and state.cages, N.Budget.MaxHabitatEmitters)
	art:updateHabitats(habs, bases, if loaded and scene == "home" then 1 else 0)

	if hrp == nil or hum == nil then
		art:updateCampfire(false, nil, now)
		return
	end
	local rootPart = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- the stumble wears off
	if knockUntil and now >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end

	local isGrounded = grounded() and knockUntil == nil
	-- a Humanoid we sat down may report FloorMaterial = Air: supported while it is not actually falling
	local supported = isGrounded
	if sat and not isGrounded and knockUntil == nil then
		supported = math.abs(rootPart.AssemblyLinearVelocity.Y) < 2
	end
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true

	-- the Rest button
	local b = findBus()
	if b then
		local presses = b:FindFirstChild("RestPresses")
		local n = if presses then (presses :: any).Value else 0
		if seenPresses ~= nil and n ~= seenPresses then
			onRestPressed(scene)
		end
		seenPresses = n
	end

	-- rest (home only; a camp's clock is never paused)
	if restOn then
		if scene ~= "home" then
			if Rest.isResting(rest) or rest.pending then Rest.stop(rest) end
		else
			local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = scheduler.active ~= nil })
			if ev == "started" and rest.source == "manual" then
				sat = true
				restFocus.Enabled = true
				pcall(function() humanoid.Sit = true end)
				campfireCF = nil
			elseif ev == "woke" or ev == "dropped" or ev == "expired" then
				unsit()
			end
		end
		if sat and not Rest.isResting(rest) then unsit() end
	end
	local resting = restOn and Rest.isResting(rest)
	if resting and rest.source == "manual" and scene == "home" then
		if campfireCF == nil then
			-- ahead of the sitter, or behind / aside when ahead is over the ravine (Night.campfireSpot)
			local look = rootPart.CFrame.LookVector
			local rp = rootPart.Position
			local fx, fz = Night.campfireSpot(Config, groundRect, rp.X, rp.Z, look.X, look.Z)
			campfireCF = CFrame.new(fx, rp.Y - Config.World.RootHeight, fz)
		end
		art:updateCampfire(true, campfireCF, now)
	else
		art:updateCampfire(false, nil, now)
	end

	-- hazards: at home only, behind the gate; a closed gate freezes the clock (never resets it)
	local alert = ""
	if hazardsOn then
		local pos = vec(rootPart.Position)
		local gateCtx = {
			loaded = loaded and groundRect ~= nil, -- no ground known: the edge rule cannot be judged
			scene = scene,
			tutorial = state and state.tutorial or 0,
			poacher = state ~= nil and state.poacher ~= nil,
			buildMode = state ~= nil and state.buildMode == true,
			panelOpen = hudPanelOpen(),
			edge = Night.edgeDistance(groundRect, pos.x, pos.z),
		}
		local run, why = Night.stepGate(gate, Config, dt, gateCtx)
		if not run and Night.cancelsFlight(why) then cancelHazard() end
		local look = camCF.LookVector
		local yaw = math.atan2(look.X, look.Z)
		-- a lane starts on screen and never out of the ground (Night.hazardPitch); a steep camera holds it
		local viewOk, hzPitch = Night.hazardPitch(Config, math.asin(math.clamp(look.Y, -1, 1)))
		local before = if scheduler.active then scheduler.active.t else nil
		local bandIdx = EnvBands.indexAt(Home, level)
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting or not run,
			grounded = isGrounded and viewOk,
			kinds = Home[bandIdx].hazards or {},
			aim = pos,
			yaw = yaw,
			pitch = hzPitch,
		}, rand)
		if ev and ev.type == "done" then
			art:hideHazard(ev.plan.kind)
		end
		local plan = scheduler.active
		if plan then
			local groundY = rootPart.Position.Y - Config.World.RootHeight
			-- The ring and the warning stay up while the rest of this frame's flight can still hit someone in the
			-- ring (Hazards.threatLive, from `before`, so the frame of a hit still shows them). They went at
			-- arriveAt, but checkHit runs to the flight's end and the lane aims up to AimJitter off the ring's
			-- centre: a player on the far side was knocked up to 0.2 s later with nothing on screen (second review,
			-- 2026-09-30, finding 1). plan.liveUntil tells the drawing when to swoop away (Night.drawPosition).
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			if live then plan.liveUntil = plan.t end
			if Hazards.checkHit(plan, before or 0, plan.t, pos, Hz.PlayerRadius) then
				plan.hit = true
				-- the push, cut so its frictionless slide stops PlayerRadius inside the Ground (Night.limitKnock:
				-- the edge margin only gates launches; review 2026-09-24, finding 2)
				local kv = Night.limitKnock(groundRect, pos, Hazards.knockVelocity(Hz, plan, pos), Hz.KnockSeconds, Hz.PlayerRadius)
				pcall(function() humanoid.PlatformStand = true end)
				rootPart.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				Rest.stop(rest)
				unsit()
				FxClient.shake(0.35, 0.8)
				FxClient.flash(Color3.fromRGB(255, 255, 255), 0.25, 0.3)
			end
			-- the hit rule above is the LANE's (inside the ring); what is drawn is Night.drawPosition: the lane
			-- until arrival, its line (level) while the ring lingers, then a swoop away (a meteorite ends
			-- there), and over a player who has left the ring instead of through them. The drawing can never
			-- hit or spare anyone.
			local avoid = if not plan.hit and not Hazards.inZone(plan, pos, Hz.PlayerRadius) then pos else nil
			local hp, visible = Night.drawPosition(Config, plan, plan.t, avoid, plan.liveUntil)
			local warning = live and not plan.hit
			art:showHazard(plan, hp, now, if live then Hazards.zone(plan, Hz.PlayerRadius) else nil, groundY, visible, warning)
			if warning then
				local bearing = Hazards.bearing(vec(camPos), vec(look), hp)
				alert = Night.alertText(Config, plan.kind, bearing, plan.locked)
			end
		end
	end

	-- the HUD: the Rest button's label, the chip line (hazard first, then rest)
	local restWhich = if resting then rest.source elseif rest.pending then "queued" else nil
	busSet("RestLabel", Night.restLabel(Config, resting, rest.pending == true))
	if alert ~= "" then
		busSet("Status", alert)
		busSet("StatusKind", "danger")
	else
		local text = Night.restText(Config, restWhich)
		busSet("Status", text)
		busSet("StatusKind", if text ~= "" then "calm" else "")
	end
	restFocus.Enabled = sat and scene == "home"

	-- title cards: once the State is known, quietly name where you are; later, each new band your
	-- Journal reaches. Never over a camp (it would cover the nets), and never over an open panel: a band
	-- reached with the Hunt panel or the build sheet open waits until it closes, and a panel opened while a
	-- card is up hides it (second review of the night, 2026-09-30, finding 4: MOONRISE lay over the open Hunt
	-- panel for 129 of 150 frames on a phone).
	if loaded and scene == "home" then
		local bandIdx = EnvBands.indexAt(Home, level)
		local reached = false
		if announcer.highest == 0 then
			EnvBands.announce(announcer, bandIdx)
			reached = true
		elseif EnvBands.announce(announcer, bandIdx) then
			reached = true
		end
		if reached then
			local band = Home[bandIdx]
			pendingCard = { string.upper(band.name), band.sub }
		end
		if hudPanelOpen() then
			if card.Visible then hideCard() end
		elseif pendingCard then
			showCard(pendingCard[1], pendingCard[2])
			pendingCard = nil
		end
	elseif scene == "camp" and card.Visible then
		hideCard()
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	-- after every emitter's owner has had its say this frame: Budget.MaxEmitters / MaxEmitterRate (NightArt)
	if ok then ok, err = pcall(art.capEmitters, art) end
	if not ok and not frameError then
		frameError = true -- once: a broken night must not flood the output
		warn("[CryptidNight] frame error: " .. tostring(err))
	end
end)
