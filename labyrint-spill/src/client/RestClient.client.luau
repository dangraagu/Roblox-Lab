-- RestClient — "rest" in a timed maze: a break room BETWEEN runs, never a pause inside one.
--
-- The run clock is the medal and the record, and traps and monsters live on the server, so no pause
-- inside a run can be honest (BreakRoom.luau says why). Rest is therefore:
--   * THE LOBBY: bright, no monsters, traps, hazards or clock. A campfire corner (built here, local,
--     non-collidable) with a "Rest by the fire" prompt: you sit, the view softens, a toast says
--     nothing is running. Any move gets you up (the template's Rest state, WakeOnMove enforced).
--     Beside it, the biome board: every biome, the ones you have reached, the next one — the brag.
--   * THE DOOR: every level starts beside the 🚪 Lobby door. For its first seconds, walking out does
--     not count as a failed attempt (the server's own CONFIG.Assist.MinRunSeconds rule), and a sign on
--     the door says so, only while that is true (BreakRoom.signAlpha, with a network margin), and
--     never while the run holds a bought "Hjelp meg" guide, which a walk-out would lose (AssistState).
-- It fires no remote, creates none, and touches nothing the server built except reading it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Biomes = require(ReplicatedStorage:WaitForChild("Biomes"))
local Rest = require(ReplicatedStorage:WaitForChild("Rest"))
local BreakRoom = require(ReplicatedStorage:WaitForChild("BreakRoom"))
local BiomeArt = require(ReplicatedStorage:WaitForChild("BiomeArt"))
local MazeRef = require(ReplicatedStorage:WaitForChild("MazeRef"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))

local player = Players.LocalPlayer
local CFG = Biomes.Rest

do
	local ok, err = BreakRoom.validate(CFG, Rest)
	if not ok then
		warn("[Labyrint] rest config rejected, break room off: " .. tostring(err))
		return
	end
end

--------------------------------------------------------------------------- the campfire corner (lobby)

local old = workspace:FindFirstChild("LabyrintBreakRoom")
if old then old:Destroy() end
local room = Instance.new("Folder")
room.Name = "LabyrintBreakRoom"
room.Parent = workspace

local FIRE = Vector3.new(CFG.Campfire.x, 0, CFG.Campfire.z) -- the lobby floor's top is y = 0

local function piece(name: string, shape: string?, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): BasePart
	local p = Instance.new("Part")
	if shape == "Cylinder" then p.Shape = Enum.PartType.Cylinder end
	if shape == "Ball" then p.Shape = Enum.PartType.Ball end
	BiomeArt.inert(p)
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Parent = room
	return p
end

for k = 0, 5 do
	local a = k * math.pi / 3
	piece("FireStone", nil, Vector3.new(1.2, 0.7, 1.0),
		CFrame.new(FIRE + Vector3.new(math.cos(a) * 1.9, 0.35, math.sin(a) * 1.9)) * CFrame.Angles(0, -a, 0),
		Color3.fromRGB(88, 86, 92), Enum.Material.Slate)
end
piece("FireLog", "Cylinder", Vector3.new(2.8, 0.55, 0.55), CFrame.new(FIRE + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0.6, 0),
	Color3.fromRGB(92, 64, 40), Enum.Material.Wood)
piece("FireLog", "Cylinder", Vector3.new(2.8, 0.55, 0.55), CFrame.new(FIRE + Vector3.new(0, 0.45, 0)) * CFrame.Angles(0, -0.7, 0),
	Color3.fromRGB(84, 58, 36), Enum.Material.Wood)
for k = 0, 2 do
	local a = math.rad(200 + k * 70)
	local at = FIRE + Vector3.new(math.cos(a) * 6, 0.45, math.sin(a) * 6)
	piece("Bench", "Cylinder", Vector3.new(4.2, 0.9, 0.9), CFrame.lookAt(at, FIRE) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(110, 78, 50), Enum.Material.Wood)
end

local fire = piece("Fire", nil, Vector3.new(1.4, 0.6, 1.4), CFrame.new(FIRE + Vector3.new(0, 0.8, 0)),
	Color3.fromRGB(255, 150, 60), Enum.Material.SmoothPlastic)
fire.Transparency = 1
do
	local flames = Instance.new("ParticleEmitter")
	flames.Name = "Flames"
	flames.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 30))
	flames.LightEmission = 1
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	flames.Lifetime = NumberRange.new(0.5, 0.9)
	flames.Speed = NumberRange.new(2, 4)
	flames.SpreadAngle = Vector2.new(12, 12)
	flames.Rate = 22
	flames.Enabled = true
	flames.Parent = fire
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 115, 110))
	smoke.LightEmission = 0
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(2.5, 3.5)
	smoke.Speed = NumberRange.new(2, 3)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Rate = 5
	smoke.Enabled = true
	smoke.Parent = fire
	-- the lobby is lit already; this is warmth, not sight, and it never reaches a maze (6000+ studs away)
	local glow = Instance.new("PointLight")
	glow.Name = "FireGlow"
	glow.Color = Color3.fromRGB(255, 170, 90)
	glow.Range = 14
	glow.Brightness = 1.6
	glow.Enabled = true
	glow.Parent = fire
end

local prompt = Instance.new("ProximityPrompt")
prompt.Name = "RestPrompt"
prompt.ActionText = "Rest by the fire"
prompt.ObjectText = "☕ Break room"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = CFG.PromptDistance
prompt.RequiresLineOfSight = false
prompt.Parent = fire

-- the biome board: a post with a camera-facing sign
local post = piece("BiomeBoardPost", nil, Vector3.new(1, 9, 1), CFrame.new(FIRE + Vector3.new(5, 4.5, -7)),
	Color3.fromRGB(70, 60, 50), Enum.Material.Wood)
local board = Instance.new("BillboardGui")
board.Name = "BiomeBoard"
board.Size = UDim2.fromScale(11, 11)
board.StudsOffset = Vector3.new(0, 7.5, 0)
board.MaxDistance = 90
board.Parent = post
local boardFrame = Instance.new("Frame")
boardFrame.Size = UDim2.fromScale(1, 1)
boardFrame.BackgroundColor3 = Color3.fromRGB(24, 22, 30)
boardFrame.BackgroundTransparency = 0.12
boardFrame.Parent = board
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = boardFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = boardFrame
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 2)
	lay.Parent = boardFrame
end
local rows: { TextLabel } = {}
local function row(i: number): TextLabel
	if rows[i] then return rows[i] end
	local l = Instance.new("TextLabel")
	l.Name = "Row" .. i
	l.LayoutOrder = i
	l.Size = UDim2.new(1, 0, 1 / (#Biomes.Bands + 1), -2)
	l.BackgroundTransparency = 1
	l.Font = if i == 1 then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = boardFrame
	rows[i] = l
	return l
end

local function refreshBoard(accepted: number)
	local album, nextIdx = Biomes.album(EnvBands, accepted)
	row(1).Text = "🗺️ BIOMES YOU REACHED"
	for i, e in album do
		local l = row(i + 1)
		if e.reached then
			l.Text = string.format("%s %s  ·  L%d  ✓", e.emoji, e.name, e.from)
			l.TextColor3 = Color3.fromRGB(235, 240, 255)
		elseif i == nextIdx then
			l.Text = string.format("%s %s  ·  next at Level %d", e.emoji, e.name, e.from)
			l.TextColor3 = Color3.fromRGB(255, 215, 110)
		else
			l.Text = string.format("🔒 ???  ·  Level %d", e.from)
			l.TextColor3 = Color3.fromRGB(130, 128, 140)
		end
	end
end
refreshBoard(0)

--------------------------------------------------------------------------- the toast

local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("LabyrintBreak")
if oldGui then oldGui:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "LabyrintBreak"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11
gui.Parent = playerGui
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Active = false
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root
local toast = Instance.new("TextLabel")
toast.Name = "RestToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
-- the same slot as Biome.client's card (under the level panel and the top-row buttons, 60 screen px clear
-- of each edge; width set in applyLayout, measured by check_labyrintspill_layout.luau)
toast.Position = UDim2.new(0.5, 0, 0, 100)
toast.Size = UDim2.fromOffset(460, 36)
toast.BackgroundTransparency = 1
toast.Active = false
toast.Font = Enum.Font.GothamBold
toast.TextScaled = true
toast.TextColor3 = Color3.fromRGB(255, 236, 200)
toast.TextStrokeTransparency = 0.2
toast.Text = "☕ Resting by the fire — nothing is running. Move to get up."
toast.Visible = false
toast.Parent = root
do
	local t = Instance.new("UITextSizeConstraint")
	t.MaxTextSize = 24
	t.Parent = toast
end
local function applyLayout()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local v = cam.ViewportSize
	local inset = 0
	pcall(function()
		inset = GuiService:GetGuiInset().Y
	end)
	local l = Responsive.layout(v.X, if v.Y - inset > 0 then v.Y - inset else v.Y, UserInputService.TouchEnabled, v.Y)
	uiScale.Scale = l.scale
	root.Size = UDim2.fromScale(1 / l.scale, 1 / l.scale)
	toast.Size = UDim2.fromOffset(math.max(120, math.min(460, (v.X - 120) / l.scale)), 36)
end
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
end
applyLayout()

--------------------------------------------------------------------------- rest state

-- The door sign makes a promise about the SERVER's clock (a walk-out is free for the first seconds of the
-- run). Its elapsed time is the larger of frame time and wall time: if this client stops rendering for a
-- while (a hitch, a minimised window) the wall clock keeps counting as the server's does, so the sign can
-- only disappear early, never linger past the promise.
local frameClock = 0
-- guideActive: the server says this run holds a "Hjelp meg" guide (AssistState). A walk-out would lose it,
-- so the sign must not promise "nothing is lost" (BreakRoom.freeBreak). Never reset on a level payload: the
-- server follows every run change with a fresh AssistState, and a stale `true` can only hide the sign early.
local where = { inLobby = true, levelStart = 0, levelStartWall = 0, run = 0, guideActive = false }
local rest = Rest.new()
local dof: DepthOfFieldEffect? = nil
local sign: BillboardGui? = nil
local signLabel: TextLabel? = nil
local signRun = -1 -- the run whose sign has been put up (declared before onPayload, which sets it)

local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function setRestLook(on: boolean)
	local cam = workspace.CurrentCamera
	if on and cam then
		if dof == nil then
			local d = Instance.new("DepthOfFieldEffect")
			d.Name = "RestDoF"
			d.FarIntensity = 0.35
			d.FocusDistance = 10
			d.InFocusRadius = 12
			d.NearIntensity = 0
			dof = d
		end
		(dof :: DepthOfFieldEffect).Parent = cam
	elseif dof then
		(dof :: DepthOfFieldEffect).Parent = nil
	end
	toast.Visible = on
end

-- Rest.update stops the state itself when it returns "woke", so whether WE sat the player down is
-- tracked here: a wake-up must still stand them up.
local satByUs = false
local function stopRest()
	if Rest.isResting(rest) then Rest.stop(rest) end
	if satByUs then
		satByUs = false
		local hum = humanoid()
		if hum and hum.Sit then hum.Sit = false end
	end
	setRestLook(false)
end

prompt.Triggered:Connect(function()
	local hum = humanoid()
	if not BreakRoom.mayRest({ inLobby = where.inLobby, dead = hum == nil or hum.Health <= 0 }) then return end
	local ctx = { moving = false, grounded = true, threat = false }
	if Rest.request(rest, CFG, ctx) == "resting" and hum then
		hum.Sit = true
		satByUs = true
		setRestLook(true)
	end
end)

--------------------------------------------------------------------------- the free-break sign on the door

local function removeSign()
	if sign then (sign :: BillboardGui):Destroy() end
	sign = nil
	signLabel = nil
end

local function placeSign()
	removeSign()
	local f = MazeRef.folder(workspace, player)
	local door = f and f:FindFirstChild("LobbyDoor")
	if door == nil or not door:IsA("BasePart") then return false end
	local bb = Instance.new("BillboardGui")
	bb.Name = "BreakSign"
	bb.Size = UDim2.fromScale(9, 2.2)
	bb.StudsOffset = Vector3.new(0, 7, 0)
	bb.MaxDistance = 40
	bb.Adornee = door
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.fromRGB(255, 236, 200)
	l.TextStrokeTransparency = 0.2
	l.Text = "☕ Need a break? Walk out now — it's free, nothing is lost"
	l.Parent = bb
	bb.Parent = room -- local folder; adorned to the server's door, never parented under it
	sign = bb
	signLabel = l
	return true
end

local function onPayload(payload: any)
	if type(payload) ~= "table" then return end
	local inLobby = payload.inLobby
	if inLobby == nil then inLobby = true end
	if tonumber(payload.accepted) then refreshBoard(tonumber(payload.accepted) :: number) end
	where.inLobby = inLobby
	prompt.Enabled = inLobby
	-- the fire only burns while you are in the lobby: in a maze it would be 6000 studs of wasted
	-- particles, and the maze's budget allows no light at all
	for _, d in fire:GetChildren() do
		if d:IsA("ParticleEmitter") or d:IsA("PointLight") then (d :: any).Enabled = inLobby end
	end
	if inLobby then
		removeSign()
		return
	end
	stopRest() -- leaving the lobby ends any rest
	where.levelStart = frameClock
	where.levelStartWall = os.clock()
	where.run += 1
	if BreakRoom.signAlpha(0, CFG, where) > 0 and placeSign() then signRun = where.run end
end

-- The server's "Hjelp meg" state (read only; the server sends it on every spawn, run change and purchase).
local function onAssist(p: any)
	where.guideActive = type(p) == "table" and p.inMaze == true and p.active == true
	if where.guideActive then removeSign() end
end

do
	local hud = ReplicatedStorage:WaitForChild("HudRemotes", 30)
	local levelInfo = hud and hud:WaitForChild("LevelInfo", 30)
	if levelInfo then (levelInfo :: RemoteEvent).OnClientEvent:Connect(onPayload) end
	local assist = ReplicatedStorage:WaitForChild("AssistRemotes", 30)
	local assistState = assist and assist:WaitForChild("AssistState", 30)
	if assistState then (assistState :: RemoteEvent).OnClientEvent:Connect(onAssist) end
end

player.CharacterAdded:Connect(function()
	Rest.stop(rest)
	satByUs = false -- a new character is not sitting
	setRestLook(false)
end)

RunService.RenderStepped:Connect(function(dt: number)
	frameClock += dt
	-- the door sign
	if not where.inLobby then
		local elapsed = math.max(frameClock - where.levelStart, os.clock() - where.levelStartWall)
		local alpha = BreakRoom.signAlpha(elapsed, CFG, where)
		if alpha > 0 and sign == nil and signRun ~= where.run then
			if placeSign() then signRun = where.run end
		end
		if sign and signLabel then
			if alpha <= 0 then
				removeSign()
			else
				(signLabel :: TextLabel).TextTransparency = 1 - alpha;
				(signLabel :: TextLabel).TextStrokeTransparency = 1 - 0.8 * alpha
			end
		end
	end
	-- the rest state: any move gets you up
	local hum = humanoid()
	if hum and (Rest.isResting(rest) or rest.pending) then
		local moving = hum.MoveDirection.Magnitude > 0.1 or hum.Jump
		local grounded = hum.Sit or hum.FloorMaterial ~= Enum.Material.Air
		local ev = Rest.update(rest, CFG, dt, { moving = moving, grounded = grounded, threat = false })
		if ev == "woke" or not where.inLobby then
			stopRest()
		end
	end
end)
