-- Biome.client — the labyrinth changes as you go deeper. Client-only; the server knows nothing of it.
--
-- Driven by the game's real progress value: the LEVEL the server sends with every LevelInfo payload
-- (the same number the HUD shows). Never by time. What it does, in frame order:
--   1. level -> band weights (Biomes + EnvBands) -> a hue grade that GLIDES on a level change (a
--      0.6 s half-life), written to Lighting at most 10x/s and only when a value differs;
--   2. a small particle box around the player (dust, fireflies, snow, embers ...), at most two kinds;
--   3. decor pieces on the walls within 24 studs (inside the torch's 28), pooled, faded in, and faded out
--      and released when their wall (a secret door) sinks into the floor;
--   4. the level's falling hazards (CellHazards): fixed cells and a fixed cycle on the LEVEL clock,
--      so everyone on a level meets the same ones; drawn only near you; a hit knocks you down;
--   5. a title card when you enter a biome, and a warning banner when a hazard near you is due.
--
-- What it must NEVER do (Biomes.luau, rule 1-3; robloxemu/check_labyrintspill_*.luau hold it to them):
--   * touch a sight field: Ambient, Brightness, ClockTime, FogStart/FogEnd, Atmosphere Density/Haze,
--     torch Range/Brightness. It writes HUES only, each at the live value's luma;
--   * recolour a wall or the floor (the theme shop sells that) or treat a secret door differently
--     from the plain wall it pretends to be;
--   * fire or create a remote, set an attribute on anything the server built, or build anything
--     collidable, queryable or touchable.
-- Rest does not live here: in a timed maze there is no pause inside a run (see BreakRoom.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Biomes = require(ReplicatedStorage:WaitForChild("Biomes"))
local CellHazards = require(ReplicatedStorage:WaitForChild("CellHazards"))
local BiomeArt = require(ReplicatedStorage:WaitForChild("BiomeArt"))
local MazeRef = require(ReplicatedStorage:WaitForChild("MazeRef"))
local Responsive = require(ReplicatedStorage:WaitForChild("Responsive"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer

do
	local ok, err = Biomes.validate(EnvBands)
	if not ok then
		-- A broken config must never half-apply: the game simply looks the way it always did.
		warn("[Labyrint] Biomes config rejected, biome visuals off: " .. tostring(err))
		return
	end
end
local HZ = Biomes.Hazards
local hazardsOn = HZ.Enabled == true
do
	local ok, err = CellHazards.validate(HZ)
	if not ok then
		warn("[Labyrint] hazard config rejected, hazards off: " .. tostring(err))
		hazardsOn = false
	end
end

local BUDGET = Biomes.Budget
local BANDS = Biomes.Bands
local BASE = Biomes.Base.look

local function c3(c: { number }): Color3
	return Color3.fromRGB(math.clamp(math.round(c[1]), 0, 255), math.clamp(math.round(c[2]), 0, 255), math.clamp(math.round(c[3]), 0, 255))
end
local function same(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.6 / 255 and math.abs(a.G - b.G) < 0.6 / 255 and math.abs(a.B - b.B) < 0.6 / 255
end

--------------------------------------------------------------------------- local world + GUI

local old = workspace:FindFirstChild("LabyrintBiomeLocal")
if old then old:Destroy() end
local folder = Instance.new("Folder")
folder.Name = "LabyrintBiomeLocal"
folder.Parent = workspace

local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("LabyrintBiome")
if oldGui then oldGui:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "LabyrintBiome"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 11
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Active = false
root.Size = UDim2.fromScale(1, 1)
root.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = root

-- The title card and the hazard banner share one slot: top centre, under the level panel (MedaljeHud's
-- NivaaPanel is 78 design px tall at y = 6) AND under the top-row buttons (upgrades, shop, records), with
-- an explicit width that keeps SIDE_CLEAR screen px free at each edge, where the records button hangs
-- lower. The width is set in applyLayout, not by a UISizeConstraint: measured by
-- robloxemu/check_labyrintspill_layout.luau on every viewport. Text only; never takes a touch.
local SLOT_Y = 100
local SIDE_CLEAR = 60
local labels: { any } = {}
local function label(name: string, y: number, h: number, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.fromOffset(460, h)
	table.insert(labels, { label = l, h = h })
	l.BackgroundTransparency = 1
	l.Active = false
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.2
	l.Text = ""
	l.Visible = false
	local t = Instance.new("UITextSizeConstraint")
	t.MaxTextSize = size
	t.Parent = l
	l.Parent = root
	return l
end
local card = label("BandCard", SLOT_Y, 40, 34)
local cardSub = label("BandCardSub", SLOT_Y + 40, 24, 20)
cardSub.TextColor3 = Color3.fromRGB(225, 225, 235)
local banner = label("HazardBanner", SLOT_Y, 36, 30)
banner.TextColor3 = Color3.fromRGB(255, 215, 90)

local function effectiveY(vy: number): number
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and inset ~= nil and type(inset.Y) == "number" and vy - inset.Y > 0 then
		return vy - inset.Y
	end
	return vy
end
local function applyLayout()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local v = cam.ViewportSize
	local l = Responsive.layout(v.X, effectiveY(v.Y), UserInputService.TouchEnabled, v.Y)
	uiScale.Scale = l.scale
	root.Size = UDim2.fromScale(1 / l.scale, 1 / l.scale)
	local w = math.max(120, math.min(460, (v.X - 2 * SIDE_CLEAR) / l.scale))
	for _, e in labels do
		e.label.Size = UDim2.fromOffset(w, e.h)
	end
end
do
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	applyLayout()
end

-- The level-complete card (HudClient) owns the middle of the screen for ~4.5 s after every level;
-- on a phone it is tall enough to reach this slot, so ours waits for it.
local function summaryCardVisible(): boolean
	local hud = playerGui:FindFirstChild("MedaljeHud")
	local r = hud and hud:FindFirstChild("Root")
	local c = r and r:FindFirstChild("OppsummeringsKort")
	return c ~= nil and (c :: any).Visible == true
end

--------------------------------------------------------------------------- state

-- Time is FRAME time: the sum of RenderStepped's dt. Everything below (the level clock the hazards run on,
-- the glide, the card timers) reads it, never a wall clock, so the emulator's virtual clock drives exactly
-- what Roblox's frames drive.
local frameClock = 0

local state = {
	inMaze = false,
	darkness = true,
	level = 1,
	accepted = 0,
	levelStart = 0,
	run = 0,         -- bumps on every maze payload: a new run (new clock, new folder, new hazards)
}

local lookCur: { [string]: any }? = nil  -- the glided look being shown
local lookAppliedAt = 0
local restored = true                    -- Atmosphere/tint/torch are at their base values

local function currentTorch(): PointLight?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local t = hrp and hrp:FindFirstChild("Torch")
	if t and t:IsA("PointLight") then return t end
	return nil
end

local function writeLook(look: { [string]: any })
	local want = c3(look.fogColor)
	if not same(Lighting.FogColor, want) then Lighting.FogColor = want end
	want = c3(look.outdoorAmbient)
	if not same(Lighting.OutdoorAmbient, want) then Lighting.OutdoorAmbient = want end
	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmos then
		want = c3(look.atmosColor)
		if not same(atmos.Color, want) then atmos.Color = want end
		want = c3(look.atmosDecay)
		if not same(atmos.Decay, want) then atmos.Decay = want end
	end
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		want = c3(look.tint)
		if not same(cc.TintColor, want) then cc.TintColor = want end
	end
	local torch = currentTorch()
	if torch then
		want = c3(look.torch)
		if not same(torch.Color, want) then torch.Color = want end
	end
	restored = false
end

-- Back to the live values for the things LightingClient does not own (it tweens fog and ambient
-- itself when you walk into the lobby).
local function restoreBase()
	if restored then return end
	restored = true
	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmos then
		atmos.Color = c3(BASE.atmosColor)
		atmos.Decay = c3(BASE.atmosDecay)
	end
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then cc.TintColor = c3(BASE.tint) end
	local torch = currentTorch()
	if torch then torch.Color = c3(BASE.torch) end
end

--------------------------------------------------------------------------- air

local airHost: BasePart? = nil
local airEmitters: { [string]: ParticleEmitter } = {}

local function setAirRates(rates: { [string]: number })
	if airHost == nil then airHost = BiomeArt.airHost(folder) end
	local host = airHost :: BasePart
	host.Parent = folder
	for kind, def in Biomes.Air do
		BiomeArt.setAir(host, airEmitters, kind, def, rates[kind] or 0)
	end
end
local function airOff()
	for _, e in airEmitters do
		e.Enabled = false
		e.Rate = 0
	end
	if airHost then airHost.Parent = nil end
end

--------------------------------------------------------------------------- maze index (grid from the replicated parts)

-- { folder, S, gCols, gRows, cols, rows, origin, walls = { ["fx,fy"] = part }, trapSet, count }.
-- Walls and secret doors go into ONE table and the name is never kept: nothing below can tell them apart.
local index: any = nil

local function buildIndex(f: Instance): any
	local floor = f:FindFirstChild("Floor")
	if floor == nil or not floor:IsA("BasePart") then return nil end
	local wallParts, trapParts = {}, {}
	local S: number? = nil
	for _, d in f:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name == "Wall" or d.Name == "SecretWall" then
				table.insert(wallParts, d)
				S = S or d.Size.X
			elseif d.Name == "Trap" then
				table.insert(trapParts, d)
			end
		end
	end
	if S == nil or S <= 0 then return nil end
	local cell = S :: number
	local gCols = math.floor(floor.Size.X / cell + 0.5)
	local gRows = math.floor(floor.Size.Z / cell + 0.5)
	local origin = floor.Position
	local function fine(p: Vector3): (number, number)
		return math.floor((p.X - origin.X) / cell + (gCols - 1) / 2 + 0.5), math.floor((p.Z - origin.Z) / cell + (gRows - 1) / 2 + 0.5)
	end
	local walls = {}
	for _, w in wallParts do
		local fx, fy = fine(w.Position)
		walls[fx .. "," .. fy] = w
	end
	local trapSet = {}
	for _, t in trapParts do
		local fx, fy = fine(t.Position)
		trapSet[math.floor((fx - 1) / 2) .. "," .. math.floor((fy - 1) / 2)] = true
	end
	return {
		folder = f, S = cell, gCols = gCols, gRows = gRows, cols = (gCols - 1) // 2, rows = (gRows - 1) // 2,
		origin = origin, walls = walls, trapSet = trapSet, count = #wallParts * 1000 + #trapParts, fine = fine,
		run = state.run, floorTop = origin.Y + floor.Size.Y / 2,
	}
end

--------------------------------------------------------------------------- decor

local active: { [string]: any } = {}   -- key "fx,fy,face" -> { piece, pid, wall, face, born, wallPos, sinkAt }
local pool: { [string]: { any } } = {}
local lastDecorCell = ""
local decorAt = 0

local function release(key: string)
	local a = active[key]
	if a == nil then return end
	BiomeArt.setPieceParent(a.piece, false)
	pool[a.pid] = pool[a.pid] or {}
	table.insert(pool[a.pid], a.piece)
	active[key] = nil
end

local function releaseAll()
	for key in active do
		release(key)
	end
	lastDecorCell = ""
end

-- (review fix) "standing" | "sinking" | "gone" (a secret door leaving its place). Position only, never the name.
local function wallState(wall: BasePart): string
	if index == nil then return "standing" end
	local y, h = wall.Position.Y, wall.Size.Y
	return Biomes.wallState(y - h / 2, y + h / 2, index.floorTop)
end

local function acquire(pid: string): any
	local list = pool[pid]
	if list and #list > 0 then return table.remove(list) end
	return BiomeArt.buildPiece(pid, Biomes.Pieces[pid], folder)
end

local function updateDecor(pos: Vector3, now: number, force: boolean)
	if index == nil then return end
	local fx0, fy0 = index.fine(pos)
	local cellKey = fx0 .. "," .. fy0 .. "," .. state.level
	if cellKey ~= lastDecorCell or force then
		lastDecorCell = cellKey
		local R = BUDGET.DecorRadius
		local rc = math.ceil(R / index.S) + 1
		local walls = index.walls
		local function isWall(x: number, y: number): boolean
			return walls[x .. "," .. y] ~= nil
		end
		local want = {}
		for fx = fx0 - rc, fx0 + rc do
			for fy = fy0 - rc, fy0 + rc do
				local wall = walls[fx .. "," .. fy]
				if wall and wall.Parent and wallState(wall) == "standing" then
					local wp = wall.Position
					local dx, dz = wp.X - pos.X, wp.Z - pos.Z
					local d = math.sqrt(dx * dx + dz * dz)
					if d <= R then
						for _, face in Biomes.openFaces(isWall, fx, fy, index.gCols, index.gRows) do
							local pid = Biomes.decorFor(EnvBands, state.level, fx, fy, face)
							if pid then
								table.insert(want, { key = fx .. "," .. fy .. "," .. face, pid = pid, wall = wall, face = face, d = d })
							end
						end
					end
				end
			end
		end
		table.sort(want, function(a, b) return a.d < b.d end)
		local keep = {}
		for i = 1, math.min(#want, BUDGET.MaxDecorPieces) do
			keep[want[i].key] = want[i]
		end
		for key, a in active do
			local w = keep[key]
			if w == nil or w.pid ~= a.pid then
				release(key)
			end
		end
		for key, w in keep do
			if active[key] == nil then
				local piece = acquire(w.pid)
				active[key] = { piece = piece, pid = w.pid, wall = w.wall, face = w.face, born = now, wallPos = nil }
				BiomeArt.placePiece(piece, w.wall, w.face, 0)
				BiomeArt.setPieceParent(piece, true)
			end
		end
	end
	-- fade in; follow a wall that moves (a secret door sinking takes its dressing down with it) while the
	-- dressing fades out, and release it once faded or once the door is under the floor: pieces on the wall
	-- top (spires, columns) reach higher than the door sinks, and would otherwise be left sticking out of the
	-- floor where the door was (review fix)
	local gone: { string }? = nil
	for key, a in active do
		local wp = a.wall.Position
		local st = wallState(a.wall)
		if a.sinkAt == nil and st ~= "standing" then a.sinkAt = now end
		local alpha = Biomes.decorAlpha(now - a.born, if a.sinkAt then now - a.sinkAt else nil)
		if st == "gone" or (a.sinkAt ~= nil and alpha <= 0) then
			gone = gone or {}
			table.insert(gone :: { string }, key)
		elseif a.piece.alpha ~= alpha or a.wallPos ~= wp then
			BiomeArt.placePiece(a.piece, a.wall, a.face, alpha)
			a.wallPos = wp
		end
	end
	if gone then
		for _, key in gone do release(key) end
	end
end

--------------------------------------------------------------------------- hazards

local hazards: { any } = {}   -- { hz, centre (Vector3), kind }
local hazardRun = -1
local views: { any } = {}
local knockUntil: number? = nil
local lastT: number? = nil
local zoneRadius = HZ.StrikeRadius + HZ.PlayerRadius

local function pickHazards()
	hazards = {}
	local kind = Biomes.hazardKindAt(EnvBands, state.level)
	if not hazardsOn or kind == nil or index == nil then return end
	local list = CellHazards.pick(state.level, index.cols, index.rows, index.trapSet, Biomes.Seed, HZ)
	for _, hz in list do
		local fx, fy = 2 * hz.cx + 1, 2 * hz.cy + 1
		local x = index.origin.X + (fx - (index.gCols - 1) / 2) * index.S
		local z = index.origin.Z + (fy - (index.gRows - 1) / 2) * index.S
		table.insert(hazards, { hz = hz, centre = Vector3.new(x, index.origin.Y + 0.5, z), kind = kind })
	end
end

local function hideViews()
	for _, v in views do BiomeArt.hideHazardView(v) end
	banner.Visible = false
end

local function releaseKnock(hum: Humanoid?)
	if knockUntil ~= nil then
		knockUntil = nil
		if hum then hum.PlatformStand = false end
	end
end

local function updateHazards(pos: Vector3, hum: Humanoid?, rootPart: BasePart?, now: number)
	local t = now - state.levelStart
	local t0 = lastT or t
	lastT = t
	if knockUntil ~= nil and now >= knockUntil then releaseKnock(hum) end
	if #hazards == 0 then
		hideViews()
		return
	end
	local alive = hum ~= nil and hum.Health > 0 and rootPart ~= nil
	local near = {}
	local bannerKind: string? = nil
	for _, h in hazards do
		local dx, dz = h.centre.X - pos.X, h.centre.Z - pos.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= HZ.ShowRadius then
			local st, p = CellHazards.stateAt(h.hz, t, HZ)
			if st ~= "idle" then table.insert(near, { h = h, d = d, st = st, p = p }) end
			if st == "warn" and d <= HZ.NearRadius + 8 then bannerKind = h.kind end
			-- the hit test runs for every hazard in range, drawn or not
			if alive and knockUntil == nil then
				local pp = { x = pos.X, y = pos.Y, z = pos.Z }
				local cc = { x = h.centre.X, y = h.centre.Y, z = h.centre.Z }
				if CellHazards.checkHit(h.hz, cc, t0, t, pp, HZ) then
					local v, stand = CellHazards.knock(cc, pp, HZ)
					local rp = rootPart :: BasePart
					local h2 = hum :: Humanoid
					h2.PlatformStand = true
					local cur = rp.AssemblyLinearVelocity
					local vy = if cur then math.min(cur.Y, 0) else 0 -- a hazard never lifts you
					rp.AssemblyLinearVelocity = Vector3.new(v.x, vy, v.z)
					knockUntil = now + stand
					FxClient.shake(0.35, 0.9)
					FxClient.flash(Color3.new(1, 1, 1), 0.35, 0.5)
				end
			end
		end
	end
	table.sort(near, function(a, b) return a.d < b.d end)
	for i = 1, BUDGET.MaxHazardsShown do
		local e = near[i]
		if e then
			if views[i] == nil then views[i] = BiomeArt.buildHazardView(folder, zoneRadius, BiomeArt.rgb(HZ.RingColor)) end
			local burstNow = #CellHazards.impactsBetween(e.h.hz, t0, t, HZ) > 0
			BiomeArt.showHazardView(views[i], e.h.kind, e.h.centre, e.st, e.p, now, burstNow)
		elseif views[i] then
			BiomeArt.hideHazardView(views[i])
		end
	end
	if bannerKind and not summaryCardVisible() then
		banner.Text = Biomes.hazardBanner(bannerKind)
		banner.Visible = true
	else
		banner.Visible = false
	end
end

--------------------------------------------------------------------------- title cards

local shownBand: number? = nil
local fanfared: { [number]: boolean } = {} -- the "YOU REACHED" fanfare plays once per biome per session
local pendingCard: any = nil
local cardUntil = 0

local function queueCard(idx: number, frontier: boolean)
	local b = BANDS[idx]
	local nextB = BANDS[idx + 1]
	local range = if nextB then string.format("Levels %d-%d", math.max(1, b.from), nextB.from - 1)
		else string.format("Level %d and beyond", b.from)
	local sub = range
	if frontier and b.hazard then
		sub = range .. "  ·  " .. Biomes.hazardIntro(b.hazard)
	end
	local title = if frontier then (b.emoji .. " YOU REACHED THE " .. string.upper(b.name) .. "!") else (b.emoji .. " " .. b.name)
	pendingCard = { title = title, sub = sub, frontier = frontier, queued = frameClock }
end

local function updateCard(now: number)
	if pendingCard ~= nil and (not summaryCardVisible() or now - pendingCard.queued > 8) then
		card.Text = pendingCard.title
		cardSub.Text = pendingCard.sub
		card.TextTransparency = 0
		cardSub.TextTransparency = 0
		card.Visible = true
		cardSub.Visible = true
		cardUntil = now + 3.5
		if pendingCard.frontier then
			FxClient.flash(Color3.fromRGB(255, 250, 235), 0.3, 0.7)
			FxClient.fovPunch(5)
		end
		pendingCard = nil
	end
	if card.Visible then
		local left = cardUntil - now
		if left <= 0 then
			card.Visible = false
			cardSub.Visible = false
		elseif left < 0.6 then
			card.TextTransparency = 1 - left / 0.6
			cardSub.TextTransparency = 1 - left / 0.6
		end
	end
	-- the hazard banner and the card share a slot; the card wins while it shows
	if card.Visible then banner.Visible = false end
end

--------------------------------------------------------------------------- level payloads

local function leaveMaze()
	state.inMaze = false
	releaseAll()
	airOff()
	hideViews()
	hazards = {}
	index = nil
	lastT = nil
	local char = player.Character
	releaseKnock(char and char:FindFirstChildOfClass("Humanoid") or nil)
	restoreBase()
	lookCur = nil
end

local function onPayload(payload: any)
	if type(payload) ~= "table" then return end
	local inLobby = payload.inLobby
	if inLobby == nil then inLobby = true end
	local darkness = payload.darkness
	if darkness == nil then darkness = true end
	local accepted = tonumber(payload.accepted)
	if inLobby then
		if accepted then state.accepted = accepted end
		if state.inMaze then leaveMaze() end
		return
	end
	local fromLobby = not state.inMaze
	local level = math.max(1, math.floor(tonumber(payload.level) or 1))
	local acceptedBefore = accepted or state.accepted
	state.inMaze = true
	state.darkness = darkness
	state.level = level
	state.levelStart = frameClock
	state.run += 1
	if accepted then state.accepted = accepted end
	index = nil
	hazards = {}
	hideViews()
	releaseAll()
	lastT = nil
	if fromLobby then
		-- entering the maze is a scene change, and LightingClient snaps the darkness in on the same
		-- payload: the hue snaps with it. Level to level inside the maze, it glides.
		lookCur = Biomes.lookAt(EnvBands, level)
	end
	-- LightingClient re-applies the plain maze preset (fog colour, outdoor ambient) on this same payload;
	-- write the grade again on the very next frame instead of waiting for the 10 Hz slot.
	lookAppliedAt = -math.huge
	local idx = Biomes.bandIndex(EnvBands, level)
	if idx ~= shownBand then
		shownBand = idx
		local frontier = idx > 1 and acceptedBefore < BANDS[idx].from and not fanfared[idx]
		if frontier then fanfared[idx] = true end
		queueCard(idx, frontier)
	end
end

do
	local hud = ReplicatedStorage:WaitForChild("HudRemotes", 30)
	local levelInfo = hud and hud:WaitForChild("LevelInfo", 30)
	if levelInfo then
		(levelInfo :: RemoteEvent).OnClientEvent:Connect(onPayload)
	else
		warn("[Labyrint] Biome.client: LevelInfo never appeared; the biome layer stays off.")
	end
end

-- A new character after a respawn has a new torch at the server's colour: re-tint it next write.
player.CharacterAdded:Connect(function()
	knockUntil = nil
	lookAppliedAt = 0
end)

--------------------------------------------------------------------------- the frame

local indexedAt = 0

RunService.RenderStepped:Connect(function(dt: number)
	frameClock += dt
	local now = frameClock
	updateCard(now)
	if not state.inMaze then return end

	-- 1. look: glide toward the level's band blend; write at most LightingHz times a second
	local target = Biomes.lookAt(EnvBands, state.level)
	lookCur = EnvBands.approachTable(lookCur, target, dt, BUDGET.GlideHalfLife)
	if state.darkness and now - lookAppliedAt >= 1 / BUDGET.LightingHz then
		lookAppliedAt = now
		writeLook(lookCur :: any)
	end

	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if rootPart == nil then return end
	local pos = (rootPart :: BasePart).Position

	-- 2. air
	local rates = EnvBands.capRates(Biomes.airAt(EnvBands, state.level), BUDGET.MaxAirEmitters, BUDGET.MaxEmitterRate, 0.05)
	setAirRates(rates)
	if airHost then (airHost :: BasePart).CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) end

	-- 3. the maze grid, from the parts the server replicated. Re-read for the first seconds of a run,
	--    while parts may still be arriving; hazards are placed once two reads agree.
	local f = MazeRef.folder(workspace, player)
	local sinceStart = now - state.levelStart
	if f ~= nil and (index == nil or index.folder ~= f or index.folder.Parent == nil
		or ((sinceStart < 4 or hazardRun ~= state.run) and now - indexedAt > 0.5)) then
		indexedAt = now
		local prev = index
		local fresh = buildIndex(f)
		if fresh then
			if prev == nil or prev.folder ~= f or prev.count ~= fresh.count or prev.run ~= state.run then
				if prev ~= nil and prev.folder ~= f then releaseAll() end
				index = fresh
				hazardRun = -1
			else
				index = fresh
				if hazardRun ~= state.run then
					hazardRun = state.run
					pickHazards()
				end
			end
		end
	end
	if index ~= nil then
		updateDecor(pos, now, false)
		-- 4. hazards
		updateHazards(pos, hum, rootPart, now)
	end
end)
