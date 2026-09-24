-- Sky.client.luau — the night sky outside the observatory, and the telescope break. CLIENT ONLY.
--
-- What it does, for THIS player only:
--   * reads the player's Day from leaderstats (the game's real progress, already public: the
--     leaderboard shows it) and blends the night-sky bands in Config.Sky.Bands through EnvBands.
--     The moon's phase follows the Day too. A changed Day GLIDES into the new sky over a few seconds
--     (GlideHalfLife); a wrong call's reset to Day 1 glides back the same way. Never a hard cut;
--   * builds and animates the sky through SkyArt, entirely BEYOND the hall's open entrance (+Z):
--     the hall is sealed everywhere else, so none of it can appear inside the hall, in its mirror or
--     in the marketing rig's crop (tests/SkyConfig.spec.luau proves every corner of every piece);
--   * runs the telescope break (Rest): the camera fades out to a view beyond the entrance that looks
--     up and away from every hall, and fades back when the player moves or presses the button.
--
-- What it never does, and why the game stays fair:
--   * it reads nothing about the pass. No PassInfo (that is ServerStorage and does not replicate
--     anyway), no zone contents beyond the zone's Index attribute, no Anomaly module. The sky is a
--     function of the Day and of its own clock, so a clean hall and an anomalous hall of the same
--     Day get the same sky, and the sky cannot hint at either;
--   * it fires no remote and writes nothing the server built. The break does not pause, re-roll or
--     delay anything: the pass stays live, the Day and the hall are exactly as they were;
--   * it writes Lighting ONLY while the camera is out at the telescope (thinner haze, a softer grade
--     on the camera), and restores it behind a black fade before the camera comes back, so the hall
--     is only ever seen under the server's own Horror preset. The one exception is set once, at start,
--     and never changed: a Sky with no sun or moon drawn (Roblox's default moon has no phases and would
--     hang behind this one). It is the same on every pass and every Day;
--   * on a phone it draws no caption over the hall that the player did not ask for (a caption there
--     sits on the right-hand wall, and this is spot-the-difference); its news waits for the break, and
--     the button carries a steady highlight meanwhile, never a blink ("The Flicker" is an anomaly);
--   * it never tells the player the Day is "safe": the streak lives only for the session, and Roblox
--     disconnects a player idle for ~20 minutes. Once Player.Idled fires, a break says so;
--   * it creates no Light and nothing collidable, touchable or ray-queryable.
-- Headless checks: robloxemu/check_anomalyobservatory_{sky,rest,hud,events,cap,occlusion,shots}.luau.
-- Design: EYECANDY.md.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local NightSky = require(ReplicatedStorage:WaitForChild("NightSky"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local SkyArt = require(ReplicatedStorage:WaitForChild("SkyArt"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local Sky = Config.Sky
-- A broken sky config must cost the polish, never the game.
do
	local ok, err = NightSky.validate(Sky, EnvBands, Rest)
	if not ok then
		warn("[AnomalySky] Config.Sky is invalid (" .. tostring(err) .. "); the night sky is off.")
		return
	end
end
local bands = Sky.Bands
local RestCfg = Sky.Rest
local View = Sky.RestView

-- One explicit Sky, set here once and never again: without one Roblox draws its default night sky,
-- whose own moon (always full) would hang behind the phased moon. CelestialBodiesShown = false hides
-- it and the sun; the skybox and its stars stay as they were. (Review 2026-09-24.)
do
	local existing = Lighting:FindFirstChildOfClass("Sky")
	local skybox = existing or Instance.new("Sky")
	skybox.CelestialBodiesShown = false
	if existing == nil then
		skybox.Name = "ObservatorySkybox"
		skybox.Parent = Lighting
	end
end

-- ------------------------------------------------------------------ UI
local DARK = Color3.fromRGB(18, 20, 30)
local ACCENT = Color3.fromRGB(120, 180, 255)
-- the button's steady "something new out there" colour (never blinked: "The Flicker" is an anomaly)
local NEWS = Color3.fromRGB(40, 60, 100)
local TAP_MIN = 44

local gui = Instance.new("ScreenGui")
gui.Name = "ObservatorySky"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- Beneath the HUD: an open HUD drawer draws over this, never the other way round. (This script
-- never touches gui.Enabled after this line: the marketing rig switches every ScreenGui off for a
-- shot and back on after, and a gui that re-enabled itself would walk into the frame.)
gui.DisplayOrder = -1
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local breakBtn = Instance.new("TextButton")
breakBtn.Name = "BreakButton"
breakBtn.BackgroundColor3 = DARK
breakBtn.BackgroundTransparency = 0.2
breakBtn.BorderSizePixel = 0
breakBtn.Font = Enum.Font.GothamBold
breakBtn.TextColor3 = ACCENT
breakBtn.TextSize = 15
breakBtn.Text = "🌙 Clear Night  ·  🔭 Break"
breakBtn.AutoButtonColor = true
breakBtn.Parent = root
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = breakBtn
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(90, 120, 170)
	s.Thickness = 1.5
	s.Transparency = 0.35
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = breakBtn
end

local caption = Instance.new("TextLabel")
caption.Name = "SkyCaption"
caption.BackgroundTransparency = 1
caption.Font = Enum.Font.GothamMedium
caption.TextColor3 = Color3.fromRGB(200, 208, 228)
caption.TextSize = 14
caption.TextWrapped = true
caption.Text = ""
caption.Parent = root

-- Full-screen black for the fade into and out of the telescope view. Visible only mid-fade.
local fade = Instance.new("Frame")
fade.Name = "BreakFade"
fade.BackgroundColor3 = Color3.new(0, 0, 0)
fade.BackgroundTransparency = 1
fade.BorderSizePixel = 0
fade.Size = UDim2.fromScale(1, 1)
fade.ZIndex = 10
fade.Visible = false
fade.Parent = gui

local layout = Responsive.layout(camera.ViewportSize.X, camera.ViewportSize.Y, UserInputService.TouchEnabled)

local function tapSize(designPx: number): number
	if layout.controlPad <= 0 then
		return designPx
	end
	return math.ceil(math.max(designPx, TAP_MIN) / layout.scale)
end

-- The HUD's own drawers (read-only). On a phone an open drawer takes priority over the break.
local function hudDrawerOpen(): boolean
	local hud = player.PlayerGui:FindFirstChild("AnomalyHud")
	local hroot = hud and hud:FindFirstChild("Root")
	if hroot == nil then return false end
	for _, name in { "Status", "Tools" } do
		local f = hroot:FindFirstChild(name)
		if f and f.Visible then return true end
	end
	return false
end

-- ------------------------------------------------------------------ state
local day = Config.Progression.StartDay
local shownDay = day
local clock = 0 -- the sky's own clock (seconds of frames), not wall time
-- What the sky is gliding toward: the Day's features, plus the land (always 1).
local function targetFor(d: number): { [string]: number }
	local t = NightSky.features(bands, EnvBands, d)
	t.land = 1
	return t
end
local target = targetFor(day)
-- Everything starts at 0, so the whole sky fades in at join instead of popping in.
local displayed = {}
for k in target do
	displayed[k] = 0
end
local phase = NightSky.moonPhase(Sky.Moon, day)
local art = nil -- SkyArt, once the player's hall exists
local restState = Rest.new()
local deathBeatUntil = -1
local captionText, captionUntil = "", 0
-- News waiting for the next break: { band = index } or { intro = true }. The button is highlighted
-- (steadily) while there is some; the break's caption says it, and seeing it clears it.
local pending: any = nil
local breakNews: string? = nil -- the news this break is showing
-- Roblox has reported the player idle (Player.Idled) and there has been no input since.
local idle = false

-- The telescope view: "hall" (normal camera), "fadingOut" (to black, leaving), "sky" (at the
-- telescope), "fadingBack" (to black, returning).
local view = "hall"
local fadeT = 0
local restClock = 0
local saved = nil -- camera + lighting as found, restored before the camera returns
local grade: ColorCorrectionEffect? = nil
local restAtmosWritten = false

local function band(): any
	return NightSky.describe(bands, EnvBands, day)
end

local function say(text: string, seconds: number)
	captionText = text
	captionUntil = clock + seconds
end

-- ------------------------------------------------------------------ layout
local function applyLayout()
	local v = camera.ViewportSize
	layout = Responsive.layout(v.X, v.Y, UserInputService.TouchEnabled)
	uiScale.Scale = layout.scale
	root.Size = UDim2.fromScale(1 / layout.scale, 1 / layout.scale)
	local h = tapSize(30)
	if layout.compact then
		-- right edge, ~42% down: clear of the top row (the HUD's toggles and help), below the HUD's
		-- toast and its detail line (0.22 of the height + 112 design px, Hud.client applyLayout), above
		-- the jump button's band, off the middle of the hall
		local rootH = v.Y / layout.scale
		local y = math.max(math.floor(rootH * 0.42), math.floor(rootH * 0.22) + 120)
		local w = if view == "hall" then tapSize(56) else tapSize(120)
		breakBtn.AnchorPoint = Vector2.new(1, 0)
		breakBtn.Size = UDim2.fromOffset(w, h)
		breakBtn.Position = UDim2.new(1, -12, 0, y)
		breakBtn.TextSize = math.floor(16 / (if layout.controlPad > 0 then layout.scale else 1))
		caption.AnchorPoint = Vector2.new(1, 0)
		caption.Size = UDim2.new(0, math.min(360, v.X / layout.scale - w - 40), 0, h)
		caption.Position = UDim2.new(1, -(12 + w + 8), 0, y)
		caption.TextXAlignment = Enum.TextXAlignment.Right
		caption.TextSize = math.floor(15 / (if layout.controlPad > 0 then layout.scale else 1))
	else
		-- top centre, under the HUD's instruction line (y 20..44)
		breakBtn.AnchorPoint = Vector2.new(0.5, 0)
		breakBtn.Size = UDim2.fromOffset(320, h)
		breakBtn.Position = UDim2.new(0.5, 0, 0, 52)
		breakBtn.TextSize = if layout.controlPad > 0 then math.floor(15 / layout.scale) else 15
		caption.AnchorPoint = Vector2.new(0.5, 0)
		caption.Size = UDim2.fromOffset(560, 36)
		caption.Position = UDim2.new(0.5, 0, 0, 52 + h + 6)
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.TextSize = 14
	end
end
applyLayout()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)

local function pendingNews(): string?
	if pending == nil then return nil end
	if pending.band then
		return NightSky.bandNews(bands[pending.band], layout.compact)
	end
	return NightSky.introNews(layout.compact)
end

local function refreshButton()
	local b = band()
	if view ~= "hall" then
		breakBtn.Text = if layout.compact then "▶ Back" else "▶ Back to the hall"
	elseif layout.compact then
		breakBtn.Text = b.emoji .. " 🔭"
	else
		breakBtn.Text = b.emoji .. " " .. b.name .. "  ·  🔭 Break"
	end
end

-- ------------------------------------------------------------------ the telescope break
local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function restCtx(): any
	local hum = humanoid()
	local moving = false
	local grounded = true
	if hum then
		local md = hum.MoveDirection
		moving = md ~= nil and md.Magnitude > 0.05
		local fm = hum.FloorMaterial
		grounded = fm == nil or fm ~= Enum.Material.Air
		if hum.Jump == true then moving = true end
	end
	return { moving = moving, grounded = grounded, threat = clock < deathBeatUntil }
end

local function atmosphere(): Atmosphere?
	local a = Lighting:FindFirstChild("FxAtmosphere")
	if a and a:IsA("Atmosphere") then return a end
	return nil
end

-- Called only while the screen is fully black: take the camera out to the telescope.
local function goOut()
	saved = {
		cameraType = camera.CameraType,
		cframe = camera.CFrame,
		fov = camera.FieldOfView,
	}
	local a = atmosphere()
	if a and View.Atmosphere then
		saved.density = a.Density
		saved.haze = a.Haze
		a.Density = View.Atmosphere.Density
		a.Haze = View.Atmosphere.Haze
		restAtmosWritten = true
	end
	if grade == nil then
		local g = Instance.new("ColorCorrectionEffect")
		g.Name = "ObservatoryBreakGrade"
		g.Saturation = View.Grade.Saturation
		g.Brightness = View.Grade.Brightness
		g.Contrast = View.Grade.Contrast
		g.Enabled = false
		g.Parent = camera
		grade = g
	end
	(grade :: ColorCorrectionEffect).Enabled = true
	breakNews = pendingNews()
	pending = nil
	restClock = 0
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = View.FovDegrees
end

-- Called only while the screen is fully black: bring the camera back exactly as it was.
local function comeBack()
	if grade then
		grade.Enabled = false
	end
	local a = atmosphere()
	if a and restAtmosWritten and saved then
		a.Density = saved.density
		a.Haze = saved.haze
	end
	restAtmosWritten = false
	if saved then
		camera.CameraType = saved.cameraType
		camera.CFrame = saved.cframe
		camera.FieldOfView = saved.fov
	end
	saved = nil
	-- whatever was announced while out here has been seen
	pending = nil
	breakNews = nil
end

local function placeRestCamera()
	if art == nil then return end
	local pose = NightSky.restPose(View, restClock)
	local o = art.origin
	local pos = Vector3.new(o.X + pose.pos.x, o.Y + pose.pos.y, o.Z + pose.pos.z)
	camera.CFrame = CFrame.lookAt(pos, pos + Vector3.new(pose.look.x, pose.look.y, pose.look.z))
end

local function startBreak()
	if view ~= "hall" then return end
	view = "fadingOut"
	fadeT = 0
	fade.Visible = true
	refreshButton()
	applyLayout()
end

local function endBreak()
	if view == "sky" or view == "fadingOut" then
		if view == "fadingOut" then
			-- still black-bound: finish the fade to black, then turn straight round
			view = "fadingBack"
			return
		end
		view = "fadingBack"
		fadeT = 0
		fade.Visible = true
	end
end

local function breakText(): string
	return NightSky.breakCaption({
		day = day, compact = layout.compact, news = pendingNews() or breakNews, idle = idle, kickMinutes = Sky.IdleKickMinutes,
	})
end

local function onBreakPressed()
	if Rest.isResting(restState) or view ~= "hall" then
		Rest.stop(restState)
		endBreak()
		return
	end
	if restState.pending then
		Rest.stop(restState)
		say("Break cancelled.", 2)
		return
	end
	-- Another script owns the camera (a cutscene, the capture rig): do not fight it.
	if camera.CameraType == Enum.CameraType.Scriptable then
		say("Not right now: the camera is busy.", 3)
		return
	end
	if art == nil then
		say("The sky is still loading.", 2)
		return
	end
	local r = Rest.request(restState, RestCfg, restCtx())
	if r == "resting" then
		startBreak()
	elseif r == "queued" then
		say("☕ Break queued: it starts when this moment is over. Keep still.", RestCfg.PendingSeconds)
	end
end

breakBtn.Activated:Connect(onBreakPressed)
-- Idle, as Roblox counts it: Player.Idled fires after about two minutes without input; any input
-- (a key, a click, a touch, a mouse move) makes the player not idle again.
pcall(function()
	player.Idled:Connect(function()
		idle = true
	end)
end)
UserInputService.InputChanged:Connect(function()
	idle = false
end)
UserInputService.InputBegan:Connect(function(input, processed)
	idle = false
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		onBreakPressed()
	end
end)

-- The death beat (a wrong call): the break waits for it, and a break in progress ends for it.
do
	local remotes = ReplicatedStorage:WaitForChild("AnomalyRemotes", 10)
	local death = remotes and remotes:FindFirstChild("Death")
	if death then
		(death :: RemoteEvent).OnClientEvent:Connect(function()
			deathBeatUntil = clock + Sky.DeathBeatSeconds
			if Rest.isResting(restState) or view ~= "hall" then
				Rest.stop(restState)
				endBreak()
			end
		end)
	end
end

player.CharacterAdded:Connect(function()
	if Rest.isResting(restState) or view ~= "hall" then
		Rest.stop(restState)
		endBreak()
	end
end)

-- ------------------------------------------------------------------ the Day
local function readDay(): number?
	local ls = player:FindFirstChild("leaderstats")
	local d = ls and ls:FindFirstChild("Day")
	if d and d:IsA("IntValue") then
		return d.Value
	end
	return nil
end

local function onDay(newDay: number)
	if newDay == day then return end
	local up = NightSky.bandUp(bands, EnvBands, day, newDay)
	day = newDay
	target = targetFor(day)
	if up then
		local b = bands[up]
		pending = { band = up }
		-- a phone's caption would sit on the hall's right-hand wall: its news waits for the break
		if not layout.compact then
			say(b.emoji .. " " .. b.name .. " tonight — press 🔭 Break (B) to watch it.", 6)
		end
	elseif pending and pending.band and EnvBands.indexAt(bands, day) < pending.band then
		pending = nil -- a wrong call took the new band away before it was seen
	end
	refreshButton()
end

-- ------------------------------------------------------------------ the frame
local ZONE_NAME = "Concourse_" .. tostring(player.UserId)
local announcedHelp = false

local function tryBuild()
	local zone = workspace:FindFirstChild(ZONE_NAME)
	if zone == nil then return end
	local index = tonumber(zone:GetAttribute("Index"))
	if index == nil then return end
	local o = NightSky.hallOrigin(Sky.Hall, index)
	art = SkyArt.new(workspace, Sky, NightSky, EnvBands, Vector3.new(o.x, o.y, o.z))
	if not announcedHelp then
		announcedHelp = true
		if layout.compact then
			-- not over the hall on a phone: the highlighted button invites, the first break explains
			pending = pending or { intro = true }
		else
			say("🔭 The sky outside changes as your Day grows. Take a break at the telescope any time (B).", 6)
		end
	end
end

-- Snap every value within 0.002 of its target onto it; true when all of them have arrived.
local function snapTable(cur: { [string]: number }, tgt: { [string]: number }): boolean
	local all = true
	for k, v in tgt do
		if math.abs((cur[k] or 0) - v) < 0.002 then
			cur[k] = v
		else
			all = false
		end
	end
	return all
end

RunService.RenderStepped:Connect(function(rawDt: number)
	local dt = math.clamp(if type(rawDt) == "number" then rawDt else 1 / 60, 0, 0.1)
	clock += dt

	local d = readDay()
	if d ~= nil then onDay(d) end

	if art == nil then tryBuild() end

	-- the sky: glide toward the Day's bands and moon (only once it exists, so a slow join still
	-- fades it in from nothing)
	if art then
		displayed = EnvBands.approachTable(displayed, target, dt, Sky.GlideHalfLife)
		local settled = snapTable(displayed, target)
		local moonTarget = NightSky.moonPhase(Sky.Moon, day)
		phase = NightSky.phaseApproach(phase, moonTarget, dt, Sky.GlideHalfLife, Sky.Moon.MaxTurnPerSecond)
		if math.abs(((moonTarget - phase + 0.5) % 1) - 0.5) < 1e-4 then
			phase = moonTarget
		else
			settled = false
		end
		art:setWeights(displayed, settled)
		art:setMoon(NightSky.moonDraw(phase), displayed.moon)
		art:step(clock)
	end

	-- the break
	local ctx = restCtx()
	local r = Rest.update(restState, RestCfg, dt, ctx)
	if r == "started" then
		startBreak()
	elseif r == "woke" then
		endBreak()
	elseif r == "expired" then
		say("The break was not taken (you kept moving).", 2.5)
	end
	if view == "fadingOut" then
		fadeT += dt
		local a = math.clamp(fadeT / View.FadeSeconds, 0, 1)
		fade.BackgroundTransparency = 1 - a
		if a >= 1 then
			goOut()
			placeRestCamera()
			view = "sky"
			fadeT = 0
		end
	elseif view == "sky" then
		restClock += dt
		placeRestCamera()
		if fadeT < View.FadeSeconds then
			fadeT += dt
			fade.BackgroundTransparency = math.clamp(fadeT / View.FadeSeconds, 0, 1)
			if fadeT >= View.FadeSeconds then fade.Visible = false end
		end
	elseif view == "fadingBack" then
		fadeT += dt
		local a = math.clamp(fadeT / View.FadeSeconds, 0, 1)
		fade.BackgroundTransparency = 1 - a
		if a >= 1 then
			comeBack()
			view = "returning"
			fadeT = 0
			captionUntil = 0
		end
	elseif view == "returning" then
		fadeT += dt
		fade.BackgroundTransparency = math.clamp(fadeT / View.FadeSeconds, 0, 1)
		if fadeT >= View.FadeSeconds then
			fade.Visible = false
			view = "hall"
			refreshButton()
			applyLayout()
		end
	end

	-- UI
	if shownDay ~= day then
		shownDay = day
		refreshButton()
	end
	breakBtn.Visible = not (layout.compact and view == "hall" and hudDrawerOpen())
	local text = ""
	if view == "sky" or view == "fadingBack" then
		text = breakText()
	elseif clock < captionUntil then
		text = captionText
	elseif not layout.compact and view == "hall" then
		local b = band()
		if b.nextIndex then
			local nb = bands[b.nextIndex]
			text = string.format("Next sky: %s %s on Day %d", nb.emoji, nb.name, nb.from)
		end
	end
	if caption.Text ~= text then caption.Text = text end
	caption.Visible = text ~= "" and breakBtn.Visible
	local bg = if pending ~= nil and view == "hall" then NEWS else DARK
	if breakBtn.BackgroundColor3 ~= bg then breakBtn.BackgroundColor3 = bg end
end)

pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
		applyLayout()
		refreshButton()
	end)
end)

refreshButton()
print("[AnomalySky] night sky ready.")
