-- STORMGROW — the sky over your farm, the weather's show, hazards and rest (StarterPlayerScripts).
--
-- What this script does, every frame, for THIS player only:
--   * reads `Harvested` (lifetime coins from harvests, server-written, only goes up) and blends the seven
--     environment bands of Config.Env with EnvBands (verbatim from plus1-jump): lighting, atmosphere, stars,
--     post-fx, the valley floor's colour, scenery, critters and ambient weather, smoothed (0.6 s half-life)
--     so a big harvest or a rejoin never cuts;
--   * lays the GLOBAL weather event (Weather.weight on the server clock) over the band: storm, frost or
--     rainbow, faded in and out over 4 s, with its own particles, distant bolts and the rainbow arc;
--   * runs the rare hazards (Hazards, verbatim) and the rest rules (Rest, verbatim), with StormGrow's two
--     flat-ground adaptations in HazardGlue: the camera pitch floor and the ground-skim of a drawn hazard;
--   * plays the band cards, and the brag: "YOUR FARM IS IN THE EYE OF THE STORM".
--
-- Why it is client-side and safe: it is cosmetic, or it only ever touches the local character, whose physics
-- the client owns anyway. It never fires a remote and the server never reads anything from it. Rest
-- freezes ONLY the hazard clock (never reset, so toggling cannot thin hazards), cannot start with a hazard
-- inbound, and ends on any movement or any server-accepted farm action (the ActionSeq attribute): taps do
-- not move the character, so without that last rule rest would be a hazard-free farming mode.
-- The HUD owns every label; this script writes the rest state (a LOCAL Player attribute, RestState), the
-- hazard banner and the band cards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Weather = require(ReplicatedStorage:WaitForChild("Weather"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local HazardGlue = require(ReplicatedStorage:WaitForChild("HazardGlue"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Farm = require(ReplicatedStorage:WaitForChild("Farm"))
local Text = require(ReplicatedStorage:WaitForChild("Text"))
local ValleyArt = require(ReplicatedStorage:WaitForChild("ValleyArt"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local ClientClock = require(ReplicatedStorage:WaitForChild("ClientClock"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Env, Hz, RestCfg, W, F = Config.Env, Config.Hazards, Config.Rest, Config.Weather, Config.Farm
local bands = Env.Bands
local now = ClientClock.attach(workspace, Config.Play.ClientExtrapolateMax)

-- A broken config must cost the polish, never the game: warn loudly and switch that part off.
do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[StormSky] Config.Env.Bands is invalid (" .. tostring(err) .. "); the sky stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then warn("[StormSky] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.") end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then warn("[StormSky] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.") end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- ── the HUD's widgets this script drives (built by Hud.client, which runs first) ─────────────────────
local hud = player:WaitForChild("PlayerGui"):WaitForChild("StormHud")
local hudRoot = hud:WaitForChild("Root")
local restButton = hudRoot:WaitForChild("Toggles"):WaitForChild("RestButton") :: TextButton
local banner = hudRoot:WaitForChild("HazardBanner") :: TextLabel
local card = hudRoot:WaitForChild("Card") :: TextLabel
local cardSub = hudRoot:WaitForChild("CardSub") :: TextLabel

-- ── my farm, for the sunbeam and the lanterns ─────────────────────────────────────────────────────────
local function mySlot(): number?
	local s = player:GetAttribute("Slot")
	return if type(s) == "number" and s >= 1 then s else nil
end
local hooks = {
	farmCentre = function(): Vector3?
		local k = mySlot()
		if k == nil then return nil end
		local x, z = Farm.toWorld(k, 0, F.Depth / 2, F)
		return Vector3.new(x, F.GroundY, z)
	end,
	farmFrame = function(): any
		local k = mySlot()
		if k == nil then return nil end
		return {
			halfW = F.Width / 2, depth = F.Depth,
			toWorld = function(lx: number, y: number, lz: number): Vector3
				local x, z = Farm.toWorld(k :: number, lx, lz, F)
				return Vector3.new(x, F.GroundY + y, z)
			end,
		}
	end,
}

local folder = Instance.new("Folder")
folder.Name = "StormLocalSky"
folder.Parent = workspace
local art = ValleyArt.new(folder, rand, Config, EnvBands, hooks)

-- ── the lighting rig: reuse the server's Fx objects by name, so the hand-over never jumps ─────────────
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
	sky = rig("Sky", "StormSky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }
pcall(function() (targets.sky :: any).CelestialBodiesShown = true end)
local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "StormRestFocus"
restFocus.FarIntensity = 0.25
restFocus.FocusDistance = 18
restFocus.InFocusRadius = 30
restFocus.NearIntensity = 0
restFocus.Enabled = false
restFocus.Parent = Lighting

local written: { [Instance]: { [string]: any } } = {}
local writes = 0 -- measured by check_stormgrow_env: Lighting is written at most LightingHz times a second
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
			if ok then
				writes += 1
				last[k] = if type(v) == "table" then { v[1], v[2], v[3] } else v
			end
		end
	end
end

-- event overlay on a sampled band: `set` fields blend toward their value, `mul` fields scale
local function withEvent(group: string, props: { [string]: any }, kind: string, w: number): { [string]: any }
	local o = Env.Overlays[kind]
	if o == nil or w <= 0 then return props end
	local out = props
	if o.set and o.set[group] then out = EnvBands.overlay(out, o.set[group], w) end
	if o.mul and o.mul[group] then
		out = table.clone(out)
		for field, m in o.mul[group] do
			if type(out[field]) == "number" then out[field] = out[field] * (1 + (m - 1) * w) end
		end
	end
	return out
end

-- ── cards ─────────────────────────────────────────────────────────────────────────────────────────────
local cardToken = 0
local cardsShown = 0 -- measured by the checks
local lastCard = ""
local function showCard(title: string, sub: string, celebrate: boolean)
	cardToken += 1
	cardsShown += 1
	lastCard = title
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

-- ── state ─────────────────────────────────────────────────────────────────────────────────────────────
local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil
local clock = 0
local weights: { [number]: number } = {}
local current: { [string]: any }? = nil
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local seeded = false
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat, satAt = false, 0
local SIT_SETTLE_SECONDS = 1.0
local knockUntil: number? = nil
local nextBolt = 5
local flashBoost = 0
local lastActionSeq = player:GetAttribute("ActionSeq")
local frameError = false
local groundPart = workspace:FindFirstChild("Valley") and workspace.Valley:FindFirstChild("Ground") :: BasePart?

local pieceIds: { [string]: boolean } = {}
for _, b in bands do
	for _, id in b.pieces or {} do pieceIds[id] = true end
end
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

local function setRestState(state: string?)
	if player:GetAttribute("RestState") ~= state then
		player:SetAttribute("RestState", state)
	end
end

local function bindCharacter(char: Model)
	character = char
	hrp, hum = nil, nil
	rest = Rest.new()
	sat = false
	restFocus.Enabled = false
	knockUntil = nil
	if scheduler.active then
		art:hideHazard()
		scheduler.active = nil
	end
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

restButton.Activated:Connect(function()
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
	local threat = scheduler.active ~= nil and Hazards.threatLive(scheduler.active, Hz.PlayerRadius)
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = grounded, threat = threat or scheduler.active ~= nil })
	if result == "resting" then
		sat = true
		satAt = clock
		restFocus.Enabled = true
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
	end
end)

-- ── the frame ─────────────────────────────────────────────────────────────────────────────────────────
local function frame(dt: number)
	clock += dt
	local t = now()
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camCF = camera.CFrame
	local camPos = camCF.Position
	local loaded = player:GetAttribute("Loaded") == true
	local harvested = player:GetAttribute("Harvested")
	local p = if type(harvested) == "number" then harvested else 0
	local bandIdx = EnvBands.indexAt(bands, p)

	-- band weights, gliding
	local targetW = EnvBands.weights(bands, p)
	for i = 1, #bands do
		local tw = targetW[i] or 0
		if current == nil then
			weights[i] = tw
		else
			weights[i] = EnvBands.approach(weights[i] or 0, tw, dt, Env.HalfLife)
		end
	end
	local eventKind, eventW = Weather.weight(t, W)

	-- lighting, at most LightingHz writes per second, only when a value changed
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		local target = {}
		for _, g in GROUPS do
			target[g] = withEvent(g, EnvBands.sample(bands, p, g), eventKind, eventW)
		end
		if current == nil then
			current = {}
			for _, g in GROUPS do (current :: any)[g] = EnvBands.sample(bands, 0, g) end
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
		-- the valley floor takes the band's colour (a local change to a server part; never replicates)
		if groundPart then
			local gc = EnvBands.sample(bands, p, "ground")
			local groundColor = { gc[1] or 96, gc[2] or 168, gc[3] or 78 }
			writeGroup(groundPart, { Color = groundColor })
		end
	end

	-- scenery, critters, ambient weather: bands blended by weight, the event on top
	local pieceW: { [string]: number } = {}
	local critters: { [string]: number } = {}
	local rates: { [string]: number } = {}
	local stormW, boltSpec, boltSpecW = 0, nil, 0
	for i, b in bands do
		local w = weights[i] or 0
		if w > 0.001 then
			for _, id in b.pieces or {} do pieceW[id] = math.min(1, (pieceW[id] or 0) + w) end
			for _, a in b.ambient or {} do critters[a.kind] = (critters[a.kind] or 0) + a.count * w end
			if b.weather and ValleyArt.hasWeather(b.weather.kind) then
				rates[b.weather.kind] = (rates[b.weather.kind] or 0) + b.weather.rate * w
			end
			if b.lightning then
				stormW += w
				if w > boltSpecW then boltSpec, boltSpecW = b.lightning, w end
			end
		end
	end
	if eventKind ~= "clear" and eventW > 0 then
		local o = Env.Overlays[eventKind]
		if o and o.weather then
			rates[o.weather.kind] = (rates[o.weather.kind] or 0) + o.weather.rate * eventW
		end
		if eventKind == "storm" then
			stormW += eventW
			if eventW > boltSpecW then boltSpec, boltSpecW = { everyMin = 3, everyMax = 6 }, eventW end
		end
	end
	local ground = EnvBands.sample(bands, p, "ground")
	for id in pieceIds do
		art:updatePiece(id, pieceW[id] or 0, clock, { ground = ground })
	end
	for kind, n in critters do critters[kind] = math.floor(n + 0.5) end
	art:updateCritters(critters, camPos, dt, clock)
	art:updateWeather(EnvBands.capRates(rates, Config.Budget.MaxWeatherEmitters, Config.Budget.MaxEmitterRate, 0.5), camPos)
	art:updateRainbow(if eventKind == "rainbow" then eventW else 0, camCF)
	art:capLights(camPos)

	-- distant bolts: in a stormy band, and during every storm
	art:updateBolts(clock)
	flashBoost = EnvBands.approach(flashBoost, 0, dt, 0.08)
	if stormW > 0.35 and boltSpec then
		nextBolt -= dt
		if nextBolt <= 0 then
			local spec = boltSpec :: any
			nextBolt = spec.everyMin + (spec.everyMax - spec.everyMin) * rand()
			local a = rand() * math.pi * 2
			art:bolt(Vector3.new(math.sin(a) * 300, F.GroundY + 20, math.cos(a) * 300), clock)
			flashBoost = 0.2 * math.min(stormW, 1)
		end
	end

	if hrp == nil or hum == nil then return end
	local root = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- a server-accepted farm action wakes you (DESIGN.md §5: taps do not move the character)
	local seq = player:GetAttribute("ActionSeq")
	local acted = seq ~= lastActionSeq
	lastActionSeq = seq

	if knockUntil and clock >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end
	local fm = (humanoid :: any).FloorMaterial
	local grounded = fm ~= nil and fm ~= Enum.Material.Air and knockUntil == nil
	local supported = grounded
	if sat and not grounded and knockUntil == nil then
		local vy = root.AssemblyLinearVelocity.Y
		supported = math.abs(vy) < 2 or (clock - satAt) < SIT_SETTLE_SECONDS
	end
	local md = (humanoid :: any).MoveDirection
	-- A server-accepted farm action counts as activity: it wakes a rest AND resets the idle timer, so a farmer
	-- tapping crops from the porch never drifts into idle rest (tests/walk.luau found that, 2026-10-01).
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true or acted

	-- rest
	local threat = scheduler.active ~= nil and Hazards.threatLive(scheduler.active, Hz.PlayerRadius)
	if restOn then
		if acted and (Rest.isResting(rest) or rest.pending) then
			Rest.stop(rest)
			unsit()
		end
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = threat })
		if ev == "started" and rest.source == "manual" then
			sat = true
			satAt = clock
			restFocus.Enabled = true
			pcall(function() humanoid.Sit = true end)
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
	end
	local resting = restOn and Rest.isResting(rest)
	setRestState(if resting then (if rest.source == "idle" then "idle" else "resting") elseif rest.pending then "queued" else nil)
	local btnText = if resting then "▶ Farm" elseif rest.pending then "☕ …" else "☕ Rest"
	if restButton.Text ~= btnText then restButton.Text = btnText end

	-- hazards
	if hazardsOn and loaded then
		local look = camCF.LookVector
		local yaw = math.atan2(look.X, look.Z)
		local pitch = HazardGlue.ctxPitch(math.asin(math.clamp(look.Y, -1, 1)), Hz)
		local before = if scheduler.active then scheduler.active.t else nil
		local pos = vec(root.Position)
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting, grounded = grounded, kinds = bands[bandIdx].hazards or {},
			aim = pos, yaw = yaw, pitch = pitch,
		}, rand)
		if ev and ev.type == "done" then art:hideHazard() end
		local plan = scheduler.active
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local drawn = Vector3.new(hp.x, HazardGlue.drawnY(hp.y, F.GroundY), hp.z)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			local zone = if live then Hazards.zone(plan, Hz.PlayerRadius) else nil
			if zone then
				-- the ring lies ON the porch, pad or soil under it, never inside it (REVIEW-1, HazardGlue.ringY)
				zone.y = HazardGlue.ringY(zone.x, zone.z, zone.radius, F, Farm)
			end
			art:showHazard(plan, drawn, zone, clock)
			if Hazards.checkHit(plan, before or 0, plan.t, pos, Hz.PlayerRadius) then
				plan.hit = true
				local kv = Hazards.knockVelocity(Hz, plan, pos)
				pcall(function() humanoid.PlatformStand = true end)
				root.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = clock + Hz.KnockSeconds
				Rest.stop(rest)
				unsit()
				FxClient.shake(0.4, 0.9)
				FxClient.flash(Color3.fromRGB(255, 255, 255), 0.3, 0.35)
			end
			if live and not plan.hit then
				local b = Hazards.bearing(vec(camPos), vec(look), hp)
				local name = Hz.Names[plan.kind] or string.upper(plan.kind)
				local text = if plan.locked then "⚠️ MOVE! " .. name .. " " .. ARROWS[b] .. " step out of the ring"
					else "⚠️ " .. name .. " INCOMING " .. ARROWS[b]
				if banner.Text ~= text then banner.Text = text end
				banner.Visible = true
			else
				banner.Visible = false
			end
		else
			banner.Visible = false
		end
	else
		banner.Visible = false
	end

	-- band cards: announced only after the profile has loaded (so a rejoin deep in the ladder is quiet)
	if loaded then
		if not seeded then
			seeded = true
			EnvBands.announce(announcer, bandIdx)
			local b = bands[bandIdx]
			showCard(b.emoji .. " " .. string.upper(b.name), "your farm's sky", false)
		elseif EnvBands.announce(announcer, bandIdx) then
			local b = bands[bandIdx]
			local nextIdx = EnvBands.nextBand(bands, p)
			local sub = if nextIdx then string.format("next: %s %s at %s harvested", bands[nextIdx :: number].emoji, bands[nextIdx :: number].name, Text.short(bands[nextIdx :: number].from)) else "the last sky"
			if b.celebrate then
				showCard(b.emoji .. " YOUR FARM IS IN THE " .. string.upper(b.name), "🔮 Stormfruit is on sale in 🌱 Seeds", true)
			else
				showCard(b.emoji .. " " .. string.upper(b.name), sub, false)
			end
		end
	end
end

-- measurement hooks for the headless checks (read-only, client-local)
local probe = Instance.new("BindableFunction")
probe.Name = "StormSkyProbe"
probe.OnInvoke = function(what: string)
	if what == "counts" then
		local c = art:counts()
		c.writes = writes
		c.cards = cardsShown
		c.lastCard = lastCard
		c.hazardActive = scheduler.active ~= nil
		c.hazardClock = scheduler.clock
		c.hazardSpawned = scheduler.spawned
		c.resting = Rest.isResting(rest)
		c.pending = rest.pending
		c.weights = table.clone(weights)
		return c
	elseif what == "plan" then
		return scheduler.active
	elseif what == "force" then
		scheduler.clock = scheduler.nextAt
		return true
	end
	return nil
end
probe.Parent = folder

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true -- once: a broken sky must not flood the output
		warn("[StormSky] frame error: " .. tostring(err))
	end
end)
