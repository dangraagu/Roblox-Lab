-- The Same Door — the HUD, phone first. StarterPlayerScripts. Display only: it sends the server
-- nothing but three button presses (Leave, Run again, Hub), none of which carries a time, a
-- position, a seal or a finish.
--
-- Layout (DESIGN §15). A root Frame owns the UIScale (a UIScale on a ScreenGui does nothing) and is
-- sized 1/scale so it still spans the screen. Nothing tappable sits in the bottom-left or
-- bottom-right thumb zones; tap targets are >= 44 screen px on touch; the layout is redone on
-- ViewportSize and TouchEnabled. robloxemu/check_samedoor_hud.luau measures it with overlap = true.
--   top-left   DayChip     Door #N and the countdown to the next Door
--   top-centre TimerPanel  the run timer and 3 seal pips; in the hub, the Rest button instead
--   top-right  MedalPanel  the medal times (one line when compact); PauseBox in a run
--   below top  Toast       every refusal's reason, seal toasts, the hazard banner
--   centre     Card        the antechamber card, the finish card, the void card; PauseSheet
--   bottom     HintBar     first steps in the hub, and the rest line
--
-- Rest (DESIGN §9): only in the hub and only between runs (Pause.mayRest). The campfire prompt is
-- made here, client-side; a rest sends no remote and earns nothing, and any move wakes you
-- (Rest.luau, verbatim from +1 Jump).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local Medals = require(ReplicatedStorage:WaitForChild("Medals"))
local Day = require(ReplicatedStorage:WaitForChild("Day"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local Pause = require(ReplicatedStorage:WaitForChild("Pause"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local remotes = ReplicatedStorage:WaitForChild("SameDoorRemotes")
local RunEvent = remotes:WaitForChild("Run")
local ToastEvent = remotes:WaitForChild("Toast")
local DayEvent = remotes:WaitForChild("DayInfo")
local LeaveEvent = remotes:WaitForChild("Leave")
local RunAgainEvent = remotes:WaitForChild("RunAgain")
local HubEvent = remotes:WaitForChild("GoHub")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
while camera == nil do
	task.wait()
	camera = workspace.CurrentCamera
end

local M = Responsive.MARGIN
local INK = Color3.fromRGB(244, 238, 228)
local DIM = Color3.fromRGB(190, 184, 176)
local PANEL = Color3.fromRGB(22, 20, 28)
local GOLD = Color3.fromRGB(Config.Colours.SealGold[1], Config.Colours.SealGold[2], Config.Colours.SealGold[3])

--============================================================================ build
local gui = Instance.new("ScreenGui")
gui.Name = "SameDoorHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local function frame(name: string, parent: Instance, visible: boolean?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	f.Visible = visible ~= false
	f.Parent = parent
	FxClient.theme(f, { corner = 10, stroke = Color3.fromRGB(70, 64, 86) })
	return f
end

local function label(name: string, parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = color or INK
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextWrapped = true
	t.Parent = parent
	return t
end

local function button(name: string, parent: Instance, text: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.TextColor3 = INK
	b.BackgroundColor3 = Color3.fromRGB(58, 52, 74)
	b.AutoButtonColor = true
	b.Parent = parent
	FxClient.theme(b, { corner = 8, stroke = Color3.fromRGB(110, 100, 140) })
	return b
end

-- top-left: the day chip
local dayChip = frame("DayChip", root)
local dayText = label("Text", dayChip, "Door #...", 16)
dayText.Size = UDim2.new(1, -12, 1, 0)
dayText.Position = UDim2.fromOffset(6, 0)

-- top-centre: timer + pips (in a run) or the Rest button (in the hub)
local timerPanel = frame("TimerPanel", root)
local timerText = label("Timer", timerPanel, "0.00", 30)
timerText.Size = UDim2.new(1, 0, 0, 38)
local pips = {}
for k = 1, 3 do
	local pip = Instance.new("Frame")
	pip.Name = "Pip" .. k
	pip.Size = UDim2.fromOffset(16, 16)
	pip.BorderSizePixel = 0
	pip.BackgroundColor3 = Color3.fromRGB(60, 56, 70)
	pip.Parent = timerPanel
	FxClient.theme(pip, { corner = 8 })
	pips[k] = pip
end
local restPanel = frame("RestPanel", root)
local restButton = button("RestButton", restPanel, "Rest")

-- top-right: medal times and the pause button
local medalPanel = frame("MedalPanel", root)
local medalText = label("Text", medalPanel, "", 15, DIM)
medalText.TextXAlignment = Enum.TextXAlignment.Left
medalText.Size = UDim2.new(1, -12, 1, 0)
medalText.Position = UDim2.fromOffset(8, 0)
local pauseBox = frame("PauseBox", root, false)
local pauseButton = button("PauseButton", pauseBox, "II")

-- toasts and the hazard banner
local toastFrame = frame("Toast", root, false)
local toastText = label("Text", toastFrame, "", 17)
toastText.Size = UDim2.new(1, -16, 1, 0)
toastText.Position = UDim2.fromOffset(8, 0)

-- the card (antechamber / finish / void) and the pause sheet
local card = frame("Card", root, false)
local cardTitle = label("Title", card, "", 26, INK)
local cardBody = label("Body", card, "", 17, DIM)
local cardButtons = Instance.new("Frame")
cardButtons.Name = "Buttons"
cardButtons.BackgroundTransparency = 1
cardButtons.Parent = card
local againButton = button("RunAgainButton", cardButtons, "Run again")
local hubButton = button("HubButton", cardButtons, "Hub")

local sheet = frame("PauseSheet", root, false)
local sheetText = label("Text", sheet, Pause.sheet().text, 18)
local sheetButtons = Instance.new("Frame")
sheetButtons.Name = "Buttons"
sheetButtons.BackgroundTransparency = 1
sheetButtons.Parent = sheet
local leaveButton = button("LeaveButton", sheetButtons, Pause.sheet().leave)
local stayButton = button("KeepRunningButton", sheetButtons, Pause.sheet().stay)

-- the hint bar (bottom centre, above the touch controls; nothing tappable)
local hintBar = frame("HintBar", root)
local hintText = label("Text", hintBar, "", 16, INK)
hintText.Size = UDim2.new(1, -16, 1, 0)
hintText.Position = UDim2.fromOffset(8, 0)

--============================================================================ state
local state = {
	mode = "hub", -- "hub" | "ready" | "running" | "finished" | "void"
	day = nil :: any,
	run = nil :: any,
	sheetOpen = false,
	cardShownAt = 0,
	toastUntil = 0,
	clockOffset = 0,
	restPending = 0,
}
local rest = Rest.new()
local restOn = Rest.validate(Config.Rest)
local timeNow = 0

-- A control's design size: on touch it must measure >= 44 SCREEN px after the UIScale.
local function tap(scale: number, touch: boolean, base: number): number
	if not touch then return base end
	return math.max(base, math.ceil(44 / scale) + 1)
end

--============================================================================ layout
local layout = nil :: any
local function effectiveHeight(vy: number): number
	return math.max(1, vy - GuiService:GetGuiInset().Y)
end

local function applyLayout()
	local v = camera.ViewportSize
	local effY = effectiveHeight(v.Y)
	local touch = UserInputService.TouchEnabled
	layout = Responsive.layout(v.X, effY, touch, v.Y)
	local s = layout.scale
	uiScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
	local W = v.X / s -- design width
	local H = effY / s -- design height
	local compact = layout.compact
	local btn = tap(s, touch, 40)

	-- top row
	local topH = math.max(44, btn)
	local chipW = if compact then 150 else 236
	dayChip.Position = UDim2.fromOffset(M, M)
	dayChip.Size = UDim2.fromOffset(chipW, topH)
	dayText.TextSize = if compact then 15 else 17

	local timerW = 170
	timerPanel.AnchorPoint = Vector2.new(0.5, 0)
	timerPanel.Position = UDim2.new(0.5, 0, 0, M)
	timerPanel.Size = UDim2.fromOffset(timerW, 70)
	for k, pip in pips do
		pip.Position = UDim2.new(0.5, -34 + (k - 1) * 26, 0, 44)
	end
	restPanel.AnchorPoint = Vector2.new(0.5, 0)
	restPanel.Position = UDim2.new(0.5, 0, 0, M)
	restPanel.Size = UDim2.fromOffset(math.max(120, btn + 20), btn + 12)
	restButton.Position = UDim2.fromOffset(6, 6)
	restButton.Size = UDim2.new(1, -12, 0, btn)

	pauseBox.AnchorPoint = Vector2.new(1, 0)
	pauseBox.Position = UDim2.new(1, -M, 0, M)
	pauseBox.Size = UDim2.fromOffset(btn + 12, btn + 12)
	pauseButton.Position = UDim2.fromOffset(6, 6)
	pauseButton.Size = UDim2.fromOffset(btn, btn)
	local medalRight = if pauseBox.Visible then M + btn + 12 + 8 else M
	medalPanel.AnchorPoint = Vector2.new(1, 0)
	medalPanel.Position = UDim2.new(1, -medalRight, 0, M)
	local medalH = if compact then topH else 86
	medalPanel.Size = UDim2.fromOffset(if compact then 140 else 170, medalH)

	-- the toast slot, under the top row (the tallest of timer, chip, medals and the pause box)
	local topBottom = M + math.max(70, topH, medalH, btn + 12)
	local toastW = math.min(440, W - 2 * M)
	toastFrame.AnchorPoint = Vector2.new(0.5, 0)
	toastFrame.Position = UDim2.new(0.5, 0, 0, topBottom + 8)
	toastFrame.Size = UDim2.fromOffset(toastW, 40)

	-- the card slot: under the toast, never under the touch controls' band more than it must
	local cardTop = topBottom + 8 + 40 + 8
	local padDesign = layout.controlPad / s
	local cardW = math.min(460, W - 2 * M)
	local avail = H - cardTop - M
	local cardH = math.clamp(avail, 120, 260)
	for _, f in { card, sheet } do
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = UDim2.new(0.5, 0, 0, cardTop)
		f.Size = UDim2.fromOffset(cardW, cardH)
	end
	cardTitle.Position = UDim2.fromOffset(12, 8)
	cardTitle.Size = UDim2.new(1, -24, 0, 34)
	cardBody.Position = UDim2.fromOffset(12, 44)
	cardBody.Size = UDim2.new(1, -24, 1, -(44 + btn + 24))
	-- the two buttons sit side by side in the MIDDLE of the card's bottom edge, in a row no wider
	-- than 280 design px: on a short landscape phone the card's bottom reaches the touch-control
	-- band, and a full-width row put Run again under the thumbstick (measured: x 269..396 of 800)
	local rowW = math.min(cardW - 24, 280)
	cardButtons.AnchorPoint = Vector2.new(0.5, 0)
	cardButtons.Position = UDim2.new(0.5, 0, 1, -(btn + 12))
	cardButtons.Size = UDim2.fromOffset(rowW, btn)
	againButton.Size = UDim2.new(0.5, -6, 1, 0)
	againButton.Position = UDim2.fromScale(0, 0)
	hubButton.Size = UDim2.new(0.5, -6, 1, 0)
	hubButton.Position = UDim2.new(0.5, 6, 0, 0)
	sheetText.Position = UDim2.fromOffset(12, 10)
	sheetText.Size = UDim2.new(1, -24, 1, -(btn + 32))
	sheetButtons.AnchorPoint = Vector2.new(0.5, 0)
	sheetButtons.Position = UDim2.new(0.5, 0, 1, -(btn + 12))
	sheetButtons.Size = UDim2.fromOffset(rowW, btn)
	leaveButton.Size = UDim2.new(0.5, -6, 1, 0)
	leaveButton.Position = UDim2.fromScale(0, 0)
	stayButton.Size = UDim2.new(0.5, -6, 1, 0)
	stayButton.Position = UDim2.new(0.5, 6, 0, 0)

	-- the hint bar sits just above the touch controls' band
	local hintW = math.min(460, W - 2 * M)
	hintBar.AnchorPoint = Vector2.new(0.5, 1)
	hintBar.Position = UDim2.new(0.5, 0, 1, -(padDesign + M))
	hintBar.Size = UDim2.fromOffset(hintW, 40)
	-- a hint bar that would climb into the card slot hides instead of overlapping it
	local hintTop = H - padDesign - M - 40
	state.hintFits = hintTop >= cardTop + cardH + 4 or not (card.Visible or sheet.Visible)
	hintBar.Visible = hintText.Text ~= "" and state.hintFits == true
end

--============================================================================ content
local function inRun(): boolean
	return state.mode == "ready" or state.mode == "running"
end

local function inHub(): boolean
	if inRun() then return false end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp == nil then return false end
	local p = (hrp :: BasePart).Position
	return math.abs(p.X) <= 80 and math.abs(p.Z) <= 80 and p.Y < 60
end

local function showToast(msg: string, seconds: number?)
	toastText.Text = msg
	state.toastUntil = timeNow + (seconds or 3)
end

local function medalLines(): string
	local d = state.run or state.day
	if d == nil or d.perfectMs == nil then return "" end
	if layout and layout.compact then
		return "Sealer " .. Medals.formatTime(d.sealerMs)
	end
	return string.format("Sealer  %s\nGold    %s\nSilver  %s", Medals.formatTime(d.sealerMs), Medals.formatTime(d.goldMs), Medals.formatTime(d.silverMs))
end

local function setCard(title: string?, body: string?, buttons: boolean)
	if title == nil then
		card.Visible = false
		return
	end
	cardTitle.Text = title
	cardBody.Text = body or ""
	cardButtons.Visible = buttons
	card.Visible = true
	state.cardShownAt = timeNow
end

local function refresh()
	local running = inRun()
	timerPanel.Visible = state.mode ~= "hub"
	restPanel.Visible = state.mode == "hub" and inHub() and restOn and not Rest.isResting(rest)
	pauseBox.Visible = running
	sheet.Visible = state.sheetOpen and running
	if sheet.Visible then card.Visible = false end
	medalText.Text = medalLines()
	medalPanel.Visible = medalText.Text ~= ""
	local seals = if state.run then (state.run.seals or 0) else 0
	for k, pip in pips do
		pip.BackgroundColor3 = if k <= seals then GOLD else Color3.fromRGB(60, 56, 70)
	end
	-- the hint
	local hint = ""
	if Rest.isResting(rest) then
		hint = "Resting by the fire. Move to wake."
	elseif state.mode == "hub" and state.day and state.day.state == "ready" then
		hint = "Walk to the glowing arch and press E (tap ENTER)"
	elseif state.mode == "hub" and state.day then
		hint = state.day.message or ""
	end
	hintText.Text = hint
	applyLayout()
end

--============================================================================ remotes
DayEvent.OnClientEvent:Connect(function(d: any)
	if type(d) ~= "table" then return end
	state.day = d
	if type(d.serverNow) == "number" then state.clockOffset = d.serverNow - os.time() end
	refresh()
end)

-- The same facts sit as attributes on the remotes folder, so a HUD that loads after the server's
-- DayInfo went out still knows the Door at once.
local function dayFromAttributes()
	local st = remotes:GetAttribute("DayState")
	if st == nil then return end
	local d = state.day or {}
	d.state = st
	d.message = remotes:GetAttribute("DayMessage")
	d.door = remotes:GetAttribute("Door")
	d.studio = remotes:GetAttribute("Studio")
	d.perfectMs = remotes:GetAttribute("PerfectMs")
	d.silverMs = remotes:GetAttribute("SilverMs")
	d.goldMs = remotes:GetAttribute("GoldMs")
	d.sealerMs = remotes:GetAttribute("SealerMs")
	state.day = d
	refresh()
end
remotes:GetAttributeChangedSignal("DayState"):Connect(dayFromAttributes)
remotes:GetAttributeChangedSignal("Door"):Connect(dayFromAttributes)
task.defer(dayFromAttributes)

ToastEvent.OnClientEvent:Connect(function(msg: any)
	if type(msg) == "string" then showToast(msg, 3.5) end
end)

RunEvent.OnClientEvent:Connect(function(p: any)
	if type(p) ~= "table" then return end
	if p.state == "ready" then
		state.run = p
		state.mode = "ready"
		state.sheetOpen = false
		if Rest.isResting(rest) then Rest.stop(rest) end
		local lines = "Find 3 Seals, then open the Door. The clock starts at the line."
		if p.perfectMs then
			lines ..= string.format("\nSealer %s   Gold %s   Silver %s", Medals.formatTime(p.sealerMs), Medals.formatTime(p.goldMs), Medals.formatTime(p.silverMs))
		end
		if p.unranked and p.reason then lines ..= "\n" .. p.reason end
		setCard("Door #" .. tostring(p.door), lines, false)
	elseif p.state == "running" then
		if state.run == nil or p.run ~= state.run.run then return end
		state.mode = "running"
		if type(p.seals) == "number" then state.run.seals = p.seals end
		card.Visible = false
	elseif p.state == "finished" then
		if state.run == nil or p.run ~= state.run.run then return end
		state.mode = "finished"
		state.sheetOpen = false
		state.run.seals = 3
		state.finishedMs = p.timeMs
		timerText.Text = Medals.formatTime(p.timeMs)
		local title = if p.brag then "THE DOOR IS SEALED" else (tostring(p.medal) .. "  " .. Medals.formatDuration(p.timeMs))
		local lines = {}
		if p.brag then table.insert(lines, string.format("Door #%s  %s", tostring(p.door), Medals.formatDuration(p.timeMs))) end
		table.insert(lines, string.format("Best today %s   Streak %d %s", Medals.formatTime(p.bestMs), p.streak or 0,
			if (p.streak or 0) == 1 then "day" else "days"))
		if p.rankUp and p.rankLabel ~= "" then table.insert(lines, "New rank: " .. p.rankLabel) end
		if p.unranked and p.reason then table.insert(lines, p.reason) end
		if p.newDoor then table.insert(lines, "A new Door opened at 00:00 UTC. This is Door #" .. tostring(p.newDoor)) end
		setCard(title, table.concat(lines, "\n"), true)
		if p.brag then
			FxClient.flash(Color3.fromRGB(255, 250, 225), 0.7, 1.2)
			FxClient.fovPunch(10, 0.12, 0.6)
		end
	elseif p.state == "void" then
		if state.run == nil or p.run ~= state.run.run then return end
		state.mode = "void"
		state.sheetOpen = false
		setCard("Run stopped", tostring(p.reason or ""), true)
	elseif p.state == "ended" then
		if state.run == nil or p.run ~= state.run.run then return end
		state.mode = "hub"
		state.run = nil
		state.sheetOpen = false
		card.Visible = false
		if p.why == "leave" then state.restPending = 3 end
	elseif p.state == "hub" then
		state.mode = "hub"
		state.run = nil
		card.Visible = false
	end
	refresh()
end)

--============================================================================ buttons
pauseButton.Activated:Connect(function()
	if not inRun() then return end
	state.sheetOpen = true
	refresh()
end)
stayButton.Activated:Connect(function()
	state.sheetOpen = false
	refresh()
end)
leaveButton.Activated:Connect(function()
	state.sheetOpen = false
	LeaveEvent:FireServer()
	refresh()
end)
againButton.Activated:Connect(function()
	RunAgainEvent:FireServer()
end)
hubButton.Activated:Connect(function()
	HubEvent:FireServer()
end)

--============================================================================ rest
local blur = Instance.new("BlurEffect")
blur.Name = "SameDoorRest"
blur.Size = 6
blur.Enabled = false
blur.Parent = Lighting

local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function restCtx(): any
	local hum = humanoid()
	local moving, grounded = false, true
	if hum then
		local md = hum.MoveDirection
		moving = md ~= nil and md.Magnitude > 0.05
		grounded = hum.FloorMaterial ~= Enum.Material.Air
	end
	return { moving = moving, grounded = grounded, threat = false }
end

local function setResting(on: boolean)
	local hum = humanoid()
	if hum then hum.Sit = on end
	blur.Enabled = on
	refresh()
end

local function requestRest()
	if not restOn then return end
	if not Pause.mayRest({ inHub = inHub(), inRun = inRun() }) then
		showToast("You can rest by the fire in the hub, between runs.")
		return
	end
	local r = Rest.request(rest, Config.Rest, restCtx())
	if r == "resting" then
		setResting(true)
	elseif r == "queued" then
		showToast("Land first, then you will sit.")
	end
end
restButton.Activated:Connect(requestRest)

-- the campfire's own prompt, made client-side (rest is client-only)
task.spawn(function()
	local hub = workspace:WaitForChild("Hub", 30)
	local camp = hub and hub:WaitForChild("Campfire", 30)
	local fire = camp and camp:WaitForChild("Fire", 30)
	if fire == nil then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RestPrompt"
	prompt.ActionText = "Rest by the fire"
	prompt.ObjectText = "Campfire"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.World.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = fire
	prompt.Triggered:Connect(function(who)
		if who == player then requestRest() end
	end)
end)

--============================================================================ every frame
RunService.Heartbeat:Connect(function(dt: number)
	timeNow += dt
	-- the timer shows the client clock (Dungeon.client, on this client's own crossing) and snaps to
	-- the official time at the finish
	if state.mode == "ready" or state.mode == "running" then
		local c = player:GetAttribute("SameDoorClock")
		timerText.Text = if type(c) == "number" and c >= 0 then Medals.formatTime(c * 1000) else "0.00"
		if state.mode == "running" and card.Visible and timeNow - state.cardShownAt > Config.Timing.ArrivalHintSeconds then
			card.Visible = false
		end
	end
	-- the day chip
	if state.day then
		local now = os.time() + state.clockOffset
		local left = Day.secondsToNext(now, Config.Day)
		local door = tostring(state.day.door or "?")
		if state.day.studio then
			dayText.Text = "Studio door (unranked)"
		else
			dayText.Text = if layout and layout.compact then ("Door #" .. door .. "  " .. Day.clock(left))
				else ("Door #" .. door .. " - new Door in " .. Day.clock(left))
		end
	end
	-- toast slot: the hazard banner outranks toasts
	if player:GetAttribute("SameDoorWarn") == true and inRun() then
		toastText.Text = "Step out of the red ring"
		toastFrame.Visible = true
	else
		toastFrame.Visible = timeNow < state.toastUntil
	end
	-- rest
	if restOn then
		if state.restPending > 0 then
			state.restPending -= dt
			if inHub() then
				state.restPending = 0
				requestRest()
			end
		end
		local ev = Rest.update(rest, Config.Rest, dt, restCtx())
		if ev == "woke" then
			setResting(false)
		elseif ev == "started" then
			setResting(true)
		end
		if Rest.isResting(rest) and not Pause.mayRest({ inHub = inHub(), inRun = inRun() }) then
			Rest.stop(rest)
			setResting(false)
		end
	end
	local wantRest = state.mode == "hub" and inHub() and restOn and not Rest.isResting(rest)
	if restPanel.Visible ~= wantRest then refresh() end
end)

camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
-- Tap targets follow TouchEnabled, which can flip without the viewport changing (a touch laptop).
pcall(function()
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(applyLayout)
end)
refresh()
