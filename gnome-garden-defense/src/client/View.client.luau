-- GNOME GARDEN DEFENSE: the garden view (client, StarterPlayerScripts). Owns the camera and turns taps into pads.
--
-- REVIEW-1 (reach finding 1): from the spawn, Roblox's default camera (12.5 studs behind the gardener on the
-- deck, looking along the lawn) drew every pad under 44 px on an 844x390 phone, the three glowing ones a median
-- 3.8 px tall. The whole garden cannot be both on screen and 44 px a cell on a 390 px tall phone (9 rows under
-- the HUD: tests/GardenCam.spec.luau measures 16.8 px), so this script does what phone strategy games do:
--   * OVERVIEW: the camera (Scriptable) frames the whole garden, bed, patch, deck and board, in the screen left
--     free under the HUD (Hud.client publishes it in GardenClientState: WorldTop/WorldBand/WorldBottom);
--   * a TAP (touch, or a mouse click) is picked here: GardenCam.pickRay finds the gnome whose body was hit, else
--     the pad whose 8-stud cell is under the finger, else the nearest pad within one cell (a finger on the path
--     beside a pad). It names the pad to the HUD (PickPad/PickSeq), which opens the gnome sheet;
--   * ZOOM: on a touch screen, a tap on a cell under Config.Hud.MinTap (44 px) PICKS NOTHING: the view moves in on
--     it until it is MinTapPx or more, and the pick is the next tap, on a big cell (REVIEW-2: a finger 12 px off a
--     17 px cell opened ANOTHER pad's sheet 42% of the time). A picked pad stays zoomed, centred above the open
--     sheet. The zoom eases back to the overview ZoomIdleSeconds after the sheet closes, ZoomPeekSeconds after a
--     zoom nobody followed up, and at once on a tap on nothing;
--   * on a touch screen the overview keeps every pad out of the bottom band's corners, where Roblox's thumbstick
--     and jump button take the touch (GardenCam.fitClear; REVIEW-2);
--   * HAZARD: while a hazard is live (Garden.client's HazardLive) the view zooms on the gardener, so the red ring
--     is big enough to step out of; SKY: a celebrated band (HARVEST MOON, AURORA) looks up at its sky piece for
--     Config.Camera.SkySeconds; BOARD: next to your own board the camera reads it; FREE: a gardener who walks out
--     of their garden gets Roblox's own camera back until they return. A capture rig or cutscene that sets the
--     camera attribute ExternalCamera = true gets the camera to itself until it clears it. In the board, sky, free
--     and external views a tap picks nothing (REVIEW-2: a tap on the board picked a pad hidden behind it).
-- Taps through Roblox's own camera conventions (Camera:ScreenPointToRay) when the engine has them; headless,
-- the same ray comes from GardenCam.ray. The camera's look is smoothed (Config.Camera.HalfLife), never cut.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local GardenCam = require(ReplicatedStorage:WaitForChild("GardenCam"))
local PathGen = require(ReplicatedStorage:WaitForChild("PathGen"))
local GardenArt = require(ReplicatedStorage:WaitForChild("GardenArt"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local CC, W, T, HC = Config.Camera, Config.World, Config.Tile, Config.Hud
local BED_W, BED_D = Config.GridW * T, Config.GridH * T
local PAD_TOP = 0.6
local DECK_Z1 = BED_D + W.DeckGap + W.DeckDepth

local playerGui = player:WaitForChild("PlayerGui")
local state = playerGui:FindFirstChild("GardenClientState")
if state == nil then
	state = Instance.new("Folder")
	state.Name = "GardenClientState"
	state.Parent = playerGui
end

local function v(x: number, y: number, z: number) return { x = x, y = y, z = z } end

--============================================================================ the garden
local garden: Instance? = nil
local attempt = -1
local origin = Vector3.new(0, 0, 0)
local pads: { any } = {}

local function findGarden(): Instance?
	local gardens = workspace:FindFirstChild("Gardens")
	if not gardens then return nil end
	for _, g in gardens:GetChildren() do
		if g:GetAttribute("Owner") == player.UserId then return g end
	end
	return nil
end

local function bind()
	local g = findGarden()
	if g ~= garden then
		garden = g
		attempt = -1
	end
	if garden == nil then return end
	local a = (garden :: Instance):GetAttribute("Attempt") or 0
	if a ~= attempt then
		attempt = a
		origin = Vector3.new((garden :: Instance):GetAttribute("OriginX") or 0, (garden :: Instance):GetAttribute("OriginY") or 0,
			(garden :: Instance):GetAttribute("OriginZ") or 0)
		local path = PathGen.fromText(Config, (garden :: Instance):GetAttribute("PathCells"))
		pads = if path then PathGen.pads(Config, path) else {}
	end
end

-- the gnomes standing now: a tap on any part of one picks its pad
local function columns(): { [number]: number }
	local out = {}
	local bed = garden and (garden :: Instance):FindFirstChild("Bed")
	local gnomes = bed and bed:FindFirstChild("Gnomes")
	for _, m in (if gnomes then gnomes:GetChildren() else {}) do
		local pad = m:GetAttribute("Pad")
		if type(pad) == "number" then out[pad] = CC.GnomeHeight end
	end
	return out
end

local function myBoard(): BasePart?
	local boards = workspace:FindFirstChild("GardenBoards")
	local b = boards and boards:FindFirstChild("GardenBoard_" .. tostring(player.UserId))
	if b and b:IsA("BasePart") then return b end
	return nil
end

--============================================================================ the screen
local function screen()
	local vs = camera.ViewportSize
	local w = state:GetAttribute("ViewW") or (if vs.X > 0 then vs.X else 1280)
	local h = state:GetAttribute("ViewH") or (if vs.Y > 0 then vs.Y else 720)
	return {
		w = w, h = h,
		inset = state:GetAttribute("Inset") or 0,
		top = state:GetAttribute("WorldTop") or 0,
		band = state:GetAttribute("WorldBand") or h,
		bottom = state:GetAttribute("WorldBottom") or h,
	}
end

-- the overview's points, in bed coordinates: the bed, the carrot patch, the deck, the board's top
local OVERVIEW_POINTS = {
	v(-2, PAD_TOP, -2), v(BED_W + W.PatchLength, PAD_TOP, -2),
	v(-2, W.DeckY, DECK_Z1), v(BED_W + W.PatchLength, W.DeckY, DECK_Z1),
	v(W.BoardX - 7.3, W.DeckY + 10.2, DECK_Z1 - W.BoardBack), v(W.BoardX + 7.3, W.DeckY + 10.2, DECK_Z1 - W.BoardBack),
}

local overview: any = nil
local overviewKey = ""
local function overviewPose(sc: any): any
	local touch = UserInputService.TouchEnabled
	local key = string.format("%d:%d:%.1f:%.1f:%d:%s", sc.w, sc.h, sc.top, sc.band, attempt, tostring(touch))
	if overview == nil or key ~= overviewKey then
		overviewKey = key
		local region = { x0 = CC.Margin, y0 = sc.top + CC.Margin, x1 = sc.w - CC.Margin, y1 = sc.h - CC.Margin }
		if touch then
			-- no pad where Roblox's thumbstick or jump button takes the touch: the garden moves sideways, and only if
			-- that is not enough gets smaller; the deck and the board (no taps) may lie there
			local cells = {}
			for _, pd in pads do
				local hx = T / 2
				table.insert(cells, { v(pd.cx - hx, PAD_TOP, pd.cz - hx), v(pd.cx + hx, PAD_TOP, pd.cz - hx),
					v(pd.cx - hx, PAD_TOP, pd.cz + hx), v(pd.cx + hx, PAD_TOP, pd.cz + hx) })
			end
			local m = CC.ZoneMargin -- a pad's edge never ends exactly on a zone's (the camera still eases)
			local zones = {
				{ x0 = 0, y0 = sc.h * (1 - HC.StickH) - m, x1 = sc.w * HC.StickW + m, y1 = sc.h }, -- the thumbstick's frame
				{ x0 = sc.w * (1 - HC.JumpShare) - m, y0 = sc.band - m, x1 = sc.w, y1 = sc.h },     -- the jump button
			}
			overview = GardenCam.fitClear(OVERVIEW_POINTS, region, sc, CC.Pitch, 0, CC.Fov, cells, zones)
		else
			overview = GardenCam.fit(OVERVIEW_POINTS, region, sc, CC.Pitch, 0, CC.Fov)
		end
	end
	return overview
end

local function zoomPose(sc: any, at: any, cell: number, minPx: number): any
	local region = { x0 = 0, y0 = sc.top, x1 = sc.w, y1 = math.max(sc.top + 40, sc.bottom) }
	return GardenCam.zoomOn(at, cell, minPx, region, sc, CC.Pitch, 0, CC.Fov)
end

-- the widest red ring a hazard can draw: its hit zone around the gardener (Hazards.zone)
local RING = 0
for _, k in Config.Hazards.Kinds do
	RING = math.max(RING, 2 * ((k.hitRadius or 0) + Config.Hazards.PlayerRadius))
end

--============================================================================ state of the view
local current: any = nil      -- the pose on screen now (bed coordinates)
local zoomPad: number? = nil  -- the pad the view is zoomed on
local zoomIdleAt = math.huge  -- when the zoom lets go (the sheet closed, nothing tapped since)
local mode = "overview"
local peeking = false -- the zoom came from a tap that picked nothing (a small cell): the HUD says "tap the pad"
local tookCamera = false
local function setPeek(on: boolean)
	peeking = on
	if state:GetAttribute("ZoomPeek") ~= on then state:SetAttribute("ZoomPeek", on) end
end
local now = 0
local pickSeq = 0

local function lerp(a: number, b: number, k: number): number return a + (b - a) * k end
local function lerpV(a: any, b: any, k: number): any return v(lerp(a.x, b.x, k), lerp(a.y, b.y, k), lerp(a.z, b.z, k)) end

-- a viewport pixel -> a ray in bed coordinates (Roblox's own conventions when the engine has them)
local function rayAt(sx: number, sy: number, sc: any): (any, any)
	local ok, r = pcall(function() return (camera :: any):ScreenPointToRay(sx, sy) end)
	if ok and r ~= nil and typeof(r) == "Ray" then
		local o, d = r.Origin - origin, r.Direction.Unit
		return v(o.X, o.Y, o.Z), v(d.X, d.Y, d.Z)
	end
	return GardenCam.ray(current, sc, sx, sy + sc.inset)
end

local function onTap(sx: number, sy: number)
	-- the board view reads the board (its prompt is the action there): a tap picked a pad hidden behind it
	if garden == nil or current == nil or mode == "free" or mode == "sky" or mode == "board" or mode == "external" then return end
	local sc = screen()
	local o, d = rayAt(sx, sy, sc)
	local pad = GardenCam.pickRay(o, d, pads, T, PAD_TOP, columns(), CC.GnomeHalfWidth)
	if pad == nil then
		zoomPad = nil -- a tap on nothing: back to the whole garden
		setPeek(false)
		return
	end
	local touch = UserInputService.TouchEnabled
	local w, h = math.huge, math.huge
	if touch then
		local pd = pads[pad]
		w, h = GardenCam.cellPx(current, sc, pd.cx, pd.cz, T, PAD_TOP)
		if mode == "overview" and math.min(w, h) < HC.MinTap then
			-- a cell too small to aim at is only where to look closer: zoom there, pick nothing (REVIEW-2). The zoom
			-- and hazard views are made for aiming (their cells around the point are MinTapPx and 45 px and more
			-- once settled), so there a tap picks even while the view is still easing in
			zoomPad = pad
			zoomIdleAt = now + CC.ZoomPeekSeconds
			setPeek(true)
			return
		end
	end
	setPeek(false)
	pickSeq += 1
	state:SetAttribute("PickPad", pad)
	state:SetAttribute("PickSeq", pickSeq)
	zoomIdleAt = math.huge
	if touch and (zoomPad ~= nil or math.min(w, h) < CC.MinTapPx) then zoomPad = pad end
end

UserInputService.TouchTap:Connect(function(positions: any, processed: boolean)
	if processed or type(positions) ~= "table" or positions[1] == nil then return end
	local p = positions[1]
	onTap(p.X, p.Y)
end)
UserInputService.InputBegan:Connect(function(input: any, processed: boolean)
	if processed or input == nil or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	local p = input.Position
	if p then onTap(p.X, p.Y) end
end)

state:GetAttributeChangedSignal("SelectedPad"):Connect(function()
	local sel = state:GetAttribute("SelectedPad") or 0
	if sel == 0 then
		zoomIdleAt = now + CC.ZoomIdleSeconds
	else
		zoomIdleAt = math.huge
	end
end)

--============================================================================ every frame
local function charPos(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position end
	return nil
end

local function insideGarden(p: Vector3): boolean
	local r = p - origin
	local m = W.HedgeMargin + CC.FreeMargin
	return r.X >= -m and r.X <= BED_W + W.PatchLength + m and r.Z >= -m and r.Z <= DECK_Z1 + m
end

local boundAlive = false
local function step(dt: number)
	now += dt
	bind()
	if garden == nil then return end
	-- another camera owner (a capture rig filming a clip, a cutscene) sets this on the camera: the garden view
	-- stands down entirely until it is cleared, and never fights it (MARKETING.md: film_game.py must set it)
	if camera:GetAttribute("ExternalCamera") == true then
		if mode ~= "external" then
			mode = "external"
			state:SetAttribute("ViewMode", mode)
		end
		tookCamera = false
		current = nil
		return
	end
	local sc = screen()
	local cp = charPos()
	local phase = (garden :: Instance):GetAttribute("Phase") or "reveal"
	if zoomPad ~= nil and (now >= zoomIdleAt or (phase ~= "reveal" and phase ~= "build" and phase ~= "wave" and phase ~= "held")) then
		zoomPad = nil
	end
	if peeking and zoomPad == nil then setPeek(false) end
	-- which view
	local target: any
	local board = myBoard()
	local skyUntil = state:GetAttribute("SkyUntil")
	if cp and not insideGarden(cp) then
		mode = "free"
	elseif state:GetAttribute("HazardLive") == true and cp then
		mode = "hazard"
		local r = cp - origin
		target = zoomPose(sc, v(r.X, PAD_TOP, r.Z), RING, CC.MinTapPx)
	elseif type(skyUntil) == "number" and tick() < skyUntil then
		mode = "sky"
		local o = overviewPose(sc)
		local anchor = GardenArt.skyAnchor(tostring(state:GetAttribute("SkyPiece") or "moon")) or GardenArt.skyAnchor("moon")
		target = { pos = o.pos, look = anchor, fov = CC.SkyFov }
	elseif board and cp and ((board.Position - cp) * Vector3.new(1, 0, 1)).Magnitude <= CC.BoardViewDistance then
		mode = "board"
		local c = board.Position - origin
		local f = board.CFrame.LookVector
		target = { pos = v(c.X + f.X * CC.BoardViewBack, c.Y + 1.5, c.Z + f.Z * CC.BoardViewBack), look = v(c.X, c.Y, c.Z), fov = CC.Fov }
	elseif zoomPad ~= nil and pads[zoomPad] then
		mode = "zoom"
		local pd = pads[zoomPad :: number]
		target = zoomPose(sc, v(pd.cx, PAD_TOP, pd.cz), T, CC.MinTapPx)
	else
		mode = "overview"
		target = overviewPose(sc)
	end
	if state:GetAttribute("ViewMode") ~= mode then state:SetAttribute("ViewMode", mode) end

	if mode == "free" then
		if tookCamera then
			tookCamera = false
			current = nil
			pcall(function() camera.CameraType = Enum.CameraType.Custom end)
		end
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		pcall(function() camera.CameraType = Enum.CameraType.Scriptable end)
	end
	tookCamera = true
	if current == nil then
		current = { pos = target.pos, look = target.look, fov = target.fov }
	else
		local k = 1 - 0.5 ^ (dt / CC.HalfLife)
		if math.abs(target.fov - current.fov) < 0.01 and (current.pos.x - target.pos.x) ^ 2 + (current.pos.y - target.pos.y) ^ 2
			+ (current.pos.z - target.pos.z) ^ 2 < 1e-6 and (current.look.x - target.look.x) ^ 2 + (current.look.y - target.look.y) ^ 2
			+ (current.look.z - target.look.z) ^ 2 < 1e-6 then
			k = 1
		end
		current = { pos = lerpV(current.pos, target.pos, k), look = lerpV(current.look, target.look, k), fov = lerp(current.fov, target.fov, k) }
	end
	local p, l = current.pos, current.look
	camera.CFrame = CFrame.lookAt(origin + Vector3.new(p.x, p.y, p.z), origin + Vector3.new(l.x, l.y, l.z))
	-- the field of view is written only when this view changes it, so a punch (FxClient.fovPunch) plays out
	local fov = math.floor(current.fov * 100 + 0.5) / 100
	if state:GetAttribute("ViewFov") ~= fov then
		state:SetAttribute("ViewFov", fov)
		camera.FieldOfView = fov
	end
end

-- Roblox: bound at the camera's render priority, so a shake bound after it (FxClient.shake) still plays on top.
-- Headless the binding never runs, and RenderStepped drives it instead (once bound, RenderStepped stands down).
pcall(function()
	RunService:BindToRenderStep("GardenView", Enum.RenderPriority.Camera.Value, function(dt)
		boundAlive = true
		local ok, err = pcall(step, dt)
		if not ok then warn("[GnomeGarden] view error: " .. tostring(err)) end
	end)
end)
local warned = false
RunService.RenderStepped:Connect(function(dt)
	if boundAlive then return end
	local ok, err = pcall(step, dt)
	if not ok and not warned then
		warned = true
		warn("[GnomeGarden] view error: " .. tostring(err))
	end
end)

