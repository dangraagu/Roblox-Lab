-- DISASTER ROUNDS - your sky (client only). Lives in StarterPlayerScripts.
--
-- Every frame, for THIS player only:
--   * blends the environment bands of Config.Env by the server-written `Survived` attribute (EnvBands, plus1-jump's
--     module byte-identical): light, fog, post-fx, far scenery, critters and weather. The more disasters you live
--     through, the wilder your sky, until it falls (band 5, the brag), and much later a new dawn. Smoothed on a
--     0.6 s half-life, so a survival or a rejoin deep in the ladder never cuts;
--   * lays the running disaster's overlay on top (EnvBands.overlay, weighed in over 3 s at the name, out over 3 s);
--   * runs the Lookout strays (Hazards.luau, verbatim) and the rest rules (Rest.luau, verbatim) with this game's glue:
--     a break pressed on the island waits for the round to end, server moves (MoveSeq) are not movement, and the
--     stray clock runs only on the deck while awake (frozen otherwise, never reset).
--
-- Why it is safe on the client: it is cosmetic, or it only harms the local player, whose character the client
-- owns. The only thing it tells the server is SetRest(on), which can only keep this player OFF the next roster.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Hazards = require(ReplicatedStorage:WaitForChild("Hazards"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Round = require(ReplicatedStorage:WaitForChild("Round"))
local SkyArt = require(ReplicatedStorage:WaitForChild("SkyArt"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end
local remotes = ReplicatedStorage:WaitForChild("DRRemotes")
local SetRestEvent = remotes:WaitForChild("SetRest")
local roundFolder = workspace:WaitForChild("Round")

local Env, Hz, RestCfg, LC = Config.Env, Config.Hazards, Config.Rest, Config.Lookout
local bands = Env.Bands

do
	local ok, err = EnvBands.validate(bands)
	if not ok then
		warn("[DisasterRounds] Config.Env.Bands is invalid (" .. tostring(err) .. "); the sky stays as the server set it.")
		return
	end
end
local hazardsOn, hazardsErr = Hazards.validate(Hz)
if not hazardsOn then warn("[DisasterRounds] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); strays are OFF.") end
local restOn, restErr = Rest.validate(RestCfg)
if not restOn then warn("[DisasterRounds] Config.Rest is invalid (" .. tostring(restErr) .. "); rest is OFF.") end

local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

--============================================================================== the local world + lighting rig

local folder = Instance.new("Folder")
folder.Name = "DRLocalSky"
folder.Parent = workspace
local art = SkyArt.new(folder, rand, Config, EnvBands)

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
	sky = rig("Sky", "DRSky"),
	bloom = rig("BloomEffect", "FxBloom"),
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	sunRays = rig("SunRaysEffect", "FxSunRays"),
}
local GROUPS = { "lighting", "atmosphere", "sky", "bloom", "colorCorrection", "sunRays" }

local restFocus = Instance.new("DepthOfFieldEffect")
restFocus.Name = "DRRestFocus"
restFocus.FarIntensity = 0.25
restFocus.FocusDistance = 18
restFocus.InFocusRadius = 30
restFocus.NearIntensity = 0
restFocus.Enabled = false
restFocus.Parent = Lighting

local written: { [Instance]: { [string]: any } } = {}
local writes = 0
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

--============================================================================== the HUD link (rest button, local cards)

local hud = player:WaitForChild("PlayerGui"):WaitForChild("DRHud", 30)
local restRequest = hud and hud:FindFirstChild("RestRequest") :: BindableEvent?
local function setRestState(s: string)
	if hud and hud:GetAttribute("RestState") ~= s then hud:SetAttribute("RestState", s) end
end
local function localToast(text: string)
	if hud then
		local q = hud:FindFirstChild("LocalToast") :: BindableEvent?
		if q then q:Fire(text) end
	end
end
local function localCard(title: string, sub: string)
	if hud then
		local q = hud:FindFirstChild("LocalCard") :: BindableEvent?
		if q then q:Fire(title, sub) end
	end
end

--============================================================================== state

local character: Model? = nil
local hrp: BasePart? = nil
local hum: Humanoid? = nil

local now = 0
local weights: { [number]: number } = {}
local current: { [string]: any }? = nil
local lightAccum = 0
local announcer = EnvBands.newAnnouncer()
local announcedFirst = false
local overlayW, overlayKind = 0, nil
local scheduler = Hazards.newScheduler(Hz, rand)
local rest = Rest.new()
local sat, satAt = false, 0
local SIT_SETTLE_SECONDS = 1.0
local afterRound = false -- ☕ pressed on the island: a break once the round is over
-- AFK, counted from the player's OWN input (move keys, jump, a tap of ☕). Rest.luau's idle clock resets on every
-- threat and every knock, and on the deck a stray comes every 60-90 s, so an AFK player there never reached
-- IdleSeconds and stayed on every roster (check_disasterrounds_rest, 2026-10-07). Rest.luau is unchanged: the glue
-- asks it for a break (Rest.request, which still queues while a stray is inbound) once the player has given no input
-- for IdleSeconds.
local afk = 0
local restingSent = false
local knockUntil: number? = nil
local lastMoveSeq = player:GetAttribute("MoveSeq")
local quietUntil = 0
local lastPos: Vector3? = nil
local boltNext, flashBoost = 8, 0
local frameError = false

local pieceIds: { [string]: boolean } = {}
for _, b in bands do
	for _, id in b.pieces or {} do pieceIds[id] = true end
end

local function vec(v: Vector3)
	return { x = v.X, y = v.Y, z = v.Z }
end

local function sendRest(on: boolean)
	if restingSent == on then return end
	restingSent = on
	SetRestEvent:FireServer(on)
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
	hrp, hum = nil, nil
	rest = Rest.new()
	sat = false
	restFocus.Enabled = false
	knockUntil = nil
	lastPos = nil
	if scheduler.active then
		art:hideStray()
		scheduler.active = nil
	end
	if restingSent then sendRest(false) end
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local function onDeck(): boolean
	return (player:GetAttribute("InRound") or "") == ""
end

local function secondsToNext(): number
	local ends = roundFolder:GetAttribute("PhaseEnds")
	local phase = roundFolder:GetAttribute("Phase")
	local t = workspace:GetAttribute("ServerNow") or 0
	if type(ends) ~= "number" then return 0 end
	local left = math.max(0, ends - t)
	if phase == "intermission" then return left end
	local R = Config.Round
	if phase == "drop" then return left + R.DisasterSeconds + R.OutroSeconds + R.IntermissionSeconds end
	if phase == "disaster" then return left + R.OutroSeconds + R.IntermissionSeconds end
	return left + R.IntermissionSeconds
end

local function grounded(): boolean
	if not hum then return false end
	local fm = (hum :: any).FloorMaterial
	return fm ~= nil and fm ~= Enum.Material.Air
end

local function onRestPressed()
	if not restOn then return end
	afk = 0
	if Rest.isResting(rest) or rest.pending then
		Rest.stop(rest)
		unsit()
		sendRest(false)
		setRestState("off")
		localToast("Back in! Next round in " .. Round.clock(secondsToNext()) .. ".")
		return
	end
	if afterRound then
		afterRound = false
		setRestState("off")
		localToast("Break cancelled. You stay in the rounds.")
		return
	end
	if not onDeck() then
		-- a round is a clock the player races: a break never ends it early or takes you out of it (DESIGN.md §5)
		afterRound = true
		setRestState("after")
		localToast("☕ Break after this round")
		return
	end
	local result = Rest.request(rest, RestCfg, { moving = false, grounded = grounded() or now < quietUntil, threat = scheduler.active ~= nil })
	if result == "resting" then
		sat, satAt = true, now
		restFocus.Enabled = true
		if hum then pcall(function() (hum :: Humanoid).Sit = true end) end
		sendRest(true)
		setRestState("resting")
		localToast("☕ On a break — move or tap ☕ to rejoin the rounds")
	elseif result == "queued" then
		setRestState("queued")
		localToast("☕ Break as soon as you're standing still")
	end
end
if restRequest then restRequest.Event:Connect(onRestPressed) end

--============================================================================== the frame

local function frame(dt: number)
	now += dt
	if character and (hrp == nil or hrp.Parent == nil) then
		hrp = (character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		hum = (character :: Model):FindFirstChildOfClass("Humanoid")
	end
	local camPos = camera.CFrame.Position
	local survived = player:GetAttribute("Survived")
	local p = if type(survived) == "number" then survived else 0
	local bandIdx = EnvBands.indexAt(bands, p)

	-- band weights, smoothed: a survival (or a rejoin deep in the ladder) glides instead of cutting
	local targetW = EnvBands.weights(bands, p)
	for i = 1, #bands do
		local tw = targetW[i] or 0
		weights[i] = if current == nil then tw else EnvBands.approach(weights[i] or 0, tw, dt, Env.HalfLife)
	end

	-- the disaster overlay: in over OverlayFadeSeconds at the name, out over the same after the end
	local kind = roundFolder:GetAttribute("Kind")
	if kind ~= nil then
		overlayKind = kind
		overlayW = math.min(1, overlayW + dt / Env.OverlayFadeSeconds)
	else
		overlayW = math.max(0, overlayW - dt / Env.OverlayFadeSeconds)
	end

	-- lighting at LightingHz, only fields that changed
	lightAccum += dt
	if current == nil or lightAccum >= 1 / Env.LightingHz then
		local step = lightAccum
		lightAccum = 0
		local over = if overlayKind then Env.Overlays[overlayKind] else nil
		local target = {}
		for _, g in GROUPS do
			local s = EnvBands.sample(bands, p, g)
			if over and over[g] and overlayW > 0 then
				local o = over[g]
				if g == "lighting" and o.Brightness then
					-- the flood darkens: Brightness x 0.6 at full weight, as a multiplier on the band's own
					o = table.clone(o)
					o.Brightness = (s.Brightness or 2) * 0.6
				end
				s = EnvBands.overlay(s, o, overlayW)
			end
			target[g] = s
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
		-- the sea's colour follows the band (a local write: it never replicates)
		local sea = workspace:FindFirstChild("Sea")
		if sea then
			local c = EnvBands.sample(bands, p, "sea")
			local col = c and (c :: any)[1] and Color3.fromRGB(c[1], c[2], c[3]) or nil
			if col and (sea :: BasePart).Color ~= col then (sea :: BasePart).Color = col end
		end
	end

	-- scenery, critters, weather
	local pieceW: { [string]: number } = {}
	local critters: { [string]: number } = {}
	local weather: { [string]: number } = {}
	local stormW = 0
	for i, b in bands do
		local w = weights[i] or 0
		if w > 0.001 then
			for _, id in b.pieces or {} do pieceW[id] = math.min(1, (pieceW[id] or 0) + w) end
			for _, a in b.critters or {} do
				if SkyArt.hasCritter(a.kind) then critters[a.kind] = (critters[a.kind] or 0) + a.count * w end
			end
			if b.weather and SkyArt.hasWeather(b.weather.kind) then
				weather[b.weather.kind] = (weather[b.weather.kind] or 0) + b.weather.rate * w
			end
			if b.lightning then stormW += w end
		end
	end
	for id in pieceIds do art:updatePiece(id, pieceW[id] or 0, now) end
	for k, n in critters do critters[k] = math.floor(n + 0.5) end
	art:updateCritters(critters, camPos, dt, now)
	art:updateWeather(weather, camPos)
	flashBoost = EnvBands.approach(flashBoost, 0, dt, 0.08)
	if stormW > 0.35 then
		boltNext -= dt
		if boltNext <= 0 then
			boltNext = 7 + 8 * rand()
			flashBoost = 0.25 * stormW -- silent lightning in the storm bank
		end
	end

	-- the first sight of the sky says where you are; a new band is announced once (EnvBands.announce)
	if player:GetAttribute("Loaded") == true then
		if not announcedFirst then
			announcedFirst = true
			EnvBands.announce(announcer, bandIdx)
		elseif EnvBands.announce(announcer, bandIdx) then
			local b = bands[bandIdx]
			if not b.celebrate then
				localCard(b.emoji .. " " .. string.upper(b.name), "Your sky changed: " .. tostring(p) .. " disasters survived")
			end
		end
	end

	if hrp == nil or hum == nil then return end
	local root = hrp :: BasePart
	local humanoid = hum :: Humanoid

	-- the knock wears off
	if knockUntil and now >= knockUntil then
		knockUntil = nil
		pcall(function() humanoid.PlatformStand = false end)
	end

	-- server moves (drops, returns) are not the player moving: quiet for ServerMoveQuietSeconds after a MoveSeq bump
	local seq = player:GetAttribute("MoveSeq")
	if seq ~= lastMoveSeq then
		lastMoveSeq = seq
		quietUntil = now + RestCfg.ServerMoveQuietSeconds
		lastPos = root.Position
	end
	local pos = root.Position
	local speed = 0
	if lastPos and dt > 0 then
		local d = pos - (lastPos :: Vector3)
		speed = math.sqrt(d.X * d.X + d.Z * d.Z) / dt
	end
	lastPos = pos
	local md = (humanoid :: any).MoveDirection
	local moving = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true or speed > RestCfg.MoveSpeed
	local isGrounded = grounded() and knockUntil == nil
	local supported = isGrounded
	if sat and not isGrounded and knockUntil == nil then
		local vy = root.AssemblyLinearVelocity.Y
		supported = math.abs(vy) < 2 or (now - satAt) < SIT_SETTLE_SECONDS
	end
	if now < quietUntil then
		moving = false
		supported = true
	end
	local deck = onDeck()
	local input = (md ~= nil and md.Magnitude > 0.05) or (humanoid :: any).Jump == true
	afk = if input then 0 else afk + dt

	-- rest
	if restOn then
		if afterRound and deck then
			afterRound = false
			local r = Rest.request(rest, RestCfg, { moving = false, grounded = supported, threat = scheduler.active ~= nil })
			if r == "resting" then
				sat, satAt = true, now
				restFocus.Enabled = true
				pcall(function() humanoid.Sit = true end)
			end
		end
		if afk >= RestCfg.IdleSeconds and not Rest.isResting(rest) and not rest.pending and RestCfg.IdleSeconds > 0 then
			-- an AFK player is taken off the rosters: a break, asked the same way the ☕ button asks
			afk = 0
			local r = Rest.request(rest, RestCfg, { moving = false, grounded = supported, threat = scheduler.active ~= nil })
			if r == "resting" then rest.source = "idle" end
		end
		local ev = Rest.update(rest, RestCfg, dt, { moving = moving, grounded = supported, threat = scheduler.active ~= nil })
		if ev == "started" then
			if rest.source == "manual" then
				sat, satAt = true, now
				restFocus.Enabled = true
				pcall(function() humanoid.Sit = true end)
			end
		elseif ev == "woke" or ev == "dropped" or ev == "expired" then
			unsit()
		end
		if sat and not Rest.isResting(rest) then unsit() end
		local resting = Rest.isResting(rest)
		sendRest(resting)
		setRestState(if resting then "resting" elseif rest.pending then "queued" elseif afterRound then "after" else "off")
	end
	local resting = restOn and Rest.isResting(rest)

	-- the Lookout strays: only on the deck and awake; the clock is frozen (never reset) otherwise
	if hazardsOn then
		local look = camera.CFrame.LookVector
		local yaw = math.atan2(look.X, look.Z)
		local pitch = math.asin(math.clamp(look.Y, -1, 1))
		local before = if scheduler.active then scheduler.active.t else nil
		local theme = roundFolder:GetAttribute("Kind") or roundFolder:GetAttribute("LastKind") or "meteor"
		local strayKind = Hz.ByDisaster[theme] or "ember"
		if not deck and scheduler.active then
			art:hideStray()
			scheduler.active = nil
		end
		local ev = Hazards.step(scheduler, Hz, dt, {
			resting = resting or not deck,
			grounded = isGrounded,
			kinds = { strayKind },
			aim = vec(pos),
			yaw = yaw,
			pitch = pitch,
		}, rand)
		if ev and ev.type == "done" then art:hideStray() end
		local plan = scheduler.active
		if plan then
			local hp = Hazards.positionAt(plan, plan.t)
			local live = Hazards.threatLive(plan, Hz.PlayerRadius, before or 0)
			art:showStray(plan, hp, now, if live then Hazards.zone(plan, Hz.PlayerRadius) else nil, LC.FloorY)
			if Hazards.checkHit(plan, before or 0, plan.t, vec(pos), Hz.PlayerRadius) then
				plan.hit = true
				local kv = Hazards.knockVelocity(Hz, plan, vec(pos))
				pcall(function() humanoid.PlatformStand = true end)
				root.AssemblyLinearVelocity = Vector3.new(kv.x, kv.y, kv.z)
				knockUntil = now + Hz.KnockSeconds
				Rest.stop(rest)
				unsit()
				pcall(function()
					FxClient.shake(0.4, 0.9)
					FxClient.flash(Color3.fromRGB(255, 255, 255), 0.3, 0.35)
				end)
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok and not frameError then
		frameError = true
		warn("[DisasterRounds] sky frame error: " .. tostring(err))
	end
end)
