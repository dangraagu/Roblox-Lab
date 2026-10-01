-- STORMGROW — the crops on every farm, their marks, and the strikes (StarterPlayerScripts). Display only.
--
-- Every tile hitbox in workspace.Farms carries public attributes the server writes (Crop, PlantedAt, Grow,
-- Marks, LastStrike, Owner, Locked). This script draws a crop model per planted tile from them (CropArt),
-- grows it on the server clock (ClientClock), and turns a new LastStrike into the strike's show: a bolt for a
-- storm, an ice burst for a frost, a prism burst for a rainbow. Nothing here decides anything; the server
-- already has. On YOUR farm it adds the onboarding: a soft rim glow on empty tiles, an arrow to the nearest
-- one until your first harvest, the price of the next field, and a "+N" over each harvest.
--
-- TAPS (REVIEW-1 B1): a tap or a click is a ray from the camera through the screen point. It lands on the first
-- DRAWN thing of any tile (a crop part or the soil plate, Pick.luau) and goes to the server as Tap(slot, key).
-- Nothing invisible takes part, so a tile is never hidden behind something the player cannot see, and there is
-- no client-side reach: the server answers every tap on a tile, "Walk closer" included (B3).
--
-- Budgets (Config.Budget, measured by robloxemu/check_stormgrow_env.luau): at most 5 crop Parts a tile
-- (1,620 for six full farms), at most MaxMarkEmitters particle emitters (nearest marked crops within
-- MarkEmitterRange), at most MaxBolts bolts at once (nearest strikes first; a skipped bolt still leaves the
-- mark's look on the crop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Weather = require(ReplicatedStorage:WaitForChild("Weather"))
local Growth = require(ReplicatedStorage:WaitForChild("Growth"))
local Mutation = require(ReplicatedStorage:WaitForChild("Mutation"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Text = require(ReplicatedStorage:WaitForChild("Text"))
local CropArt = require(ReplicatedStorage:WaitForChild("CropArt"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))
local ClientClock = require(ReplicatedStorage:WaitForChild("ClientClock"))
local Pick = require(ReplicatedStorage:WaitForChild("Pick"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local W, M, B = Config.Weather, Config.Marks, Config.Budget
local now = ClientClock.attach(workspace, Config.Play.ClientExtrapolateMax)

local byId = {}
for _, c in Config.Crops do byId[c.id] = c end

local folder = Instance.new("Folder")
folder.Name = "StormCrops"
folder.Parent = workspace
local fxFolder = Instance.new("Folder")
fxFolder.Name = "StormStrikes"
fxFolder.Parent = workspace

local farms = workspace:WaitForChild("Farms")

type TileView = {
	hb: BasePart, key: string, slot: number, crop: string, marks: number, lastStrike: number, plantedAt: number,
	view: any?, bucket: number, ripe: boolean, phase: number, glow: SelectionBox?,
}
local tiles: { TileView } = {}

-- Tiles are registered as they ARRIVE, not only once at start (REVIEW-1 B4): the place pins StreamingEnabled =
-- false, but if a published place streams anyway, a farm that streams in later must still be drawn and tappable.
-- A tile that streams out is dropped in the frame loop (its crop goes with it); Roblox streams a part back in as
-- a new instance, which arrives here again.
local known: { [Instance]: boolean } = {}
local function addTile(hb: Instance)
	if known[hb] or not hb:IsA("BasePart") then return end
	local key, slot = hb:GetAttribute("Key"), hb:GetAttribute("Farm")
	if type(key) ~= "string" or type(slot) ~= "number" then return end
	known[hb] = true
	table.insert(tiles, {
		hb = hb :: BasePart, key = key, slot = slot, crop = "", marks = 0,
		lastStrike = hb:GetAttribute("LastStrike") or 0, plantedAt = 0, view = nil, bucket = -1,
		ripe = false, phase = #tiles * 0.37, glow = nil,
	})
end
for _, d in farms:GetDescendants() do addTile(d) end
farms.DescendantAdded:Connect(addTile)

local function soilTop(tv: TileView): CFrame
	local p = tv.hb.Position
	return CFrame.new(p.X, Config.Farm.GroundY + Config.Farm.SoilHeight * 0.6, p.Z)
end

local function mySlot(): number
	local s = player:GetAttribute("Slot")
	return if type(s) == "number" then s else 0
end

-- ── pops: "+N" over a harvest on your own farm ─────────────────────────────────────────────────────
local pops = {}
local function pop(pos: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Name = "Pop"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = fxFolder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 44)
	bb.AlwaysOnTop = true
	bb.Adornee = anchor
	bb.Parent = anchor
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.3
	l.Text = text
	l.Parent = bb
	table.insert(pops, { part = anchor, label = l, born = tick(), from = pos })
end

-- ── strikes ─────────────────────────────────────────────────────────────────────────────────────────
local bolts = {}
local bursts = {}
local function strike(tv: TileView, gained: number, t: number)
	local pos = soilTop(tv).Position + Vector3.new(0, 2, 0)
	local camPos = camera.CFrame.Position
	local dist = (pos - camPos).Magnitude
	if dist > B.BoltRange then return end -- far away: the mark's look is enough
	if gained == M.storm.bit then
		if #bolts >= B.MaxBolts then return end
		local segs = {}
		local top = pos + Vector3.new((math.random() - 0.5) * 20, 120, (math.random() - 0.5) * 20)
		local prev = top
		for i = 1, 4 do
			local nextP = if i == 4 then pos else top:Lerp(pos, i / 4) + Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8)
			local p = Instance.new("Part")
			p.Name = "StrikeBolt"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Material = Enum.Material.Neon
			p.Color = Color3.fromRGB(200, 225, 255)
			p.Size = Vector3.new(0.5, 0.5, (nextP - prev).Magnitude)
			p.CFrame = CFrame.lookAt((prev + nextP) / 2, nextP)
			p.Parent = fxFolder
			table.insert(segs, p)
			prev = nextP
		end
		table.insert(bolts, { parts = segs, untilT = tick() + 0.25 })
		if dist < 20 then
			FxClient.shake(0.35, 0.6)
		end
		if dist < 60 then
			FxClient.flash(Color3.fromRGB(220, 235, 255), 0.18, 0.25)
		end
	else
		-- frost: an expanding ice ring; rainbow: a rising prism column
		local p = Instance.new("Part")
		p.Name = if gained == M.frost.bit then "FrostBurst" else "PrismBurst"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = if gained == M.frost.bit then Color3.fromRGB(220, 240, 255) else Color3.fromHSV(math.random(), 0.7, 1)
		p.Transparency = 0.3
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.2, 2, 2)
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		p.Parent = fxFolder
		table.insert(bursts, { part = p, born = tick(), frost = gained == M.frost.bit, at = pos })
	end
end

-- ── the tile loop ───────────────────────────────────────────────────────────────────────────────────
-- tick(), not os.clock(): os.clock is CPU time and barely moves in the headless emulator, so a bolt timed
-- with it would never expire there (deep-vein Main.server.luau:1108 records the same trap).
local accum = 0
local emitterAccum = 0
local arrow: BillboardGui? = nil
local fieldSign: BillboardGui? = nil

local function ensureArrow(): BillboardGui
	if arrow == nil then
		local a = Instance.new("BillboardGui")
		a.Name = "TapArrow"
		a.Size = UDim2.fromOffset(90, 60)
		a.StudsOffset = Vector3.new(0, 4, 0)
		a.AlwaysOnTop = true
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(255, 240, 140)
		l.TextStrokeTransparency = 0.2
		l.Text = "👇 TAP"
		l.Parent = a
		a.Parent = fxFolder
		arrow = a
	end
	return arrow :: BillboardGui
end

local function ensureFieldSign(): BillboardGui
	if fieldSign == nil then
		local s = Instance.new("BillboardGui")
		s.Name = "NextFieldSign"
		s.Size = UDim2.fromOffset(200, 50)
		s.StudsOffset = Vector3.new(0, 5, 0)
		local l = Instance.new("TextLabel")
		l.Name = "Label"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 0.3
		l.BackgroundColor3 = Color3.fromRGB(60, 45, 30)
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(255, 230, 170)
		l.Parent = s
		s.Parent = fxFolder
		fieldSign = s
	end
	return fieldSign :: BillboardGui
end

local frostTint: { [BasePart]: Color3 } = {}

local function update(dt: number)
	local t = now()
	local clock = tick()
	local camPos = camera.CFrame.Position
	local me = mySlot()
	local harvestsSoFar = player:GetAttribute("Harvests") or 0
	local nearestEmpty, nearestD = nil, math.huge
	local frostKind, frostW = Weather.weight(t, W)
	local lockedShown = false
	local fields = player:GetAttribute("Fields") or 1

	-- tiles that streamed out: their crop, glow and arrow go with them
	for i = #tiles, 1, -1 do
		local tv = tiles[i]
		if not tv.hb:IsDescendantOf(workspace) then
			if tv.view then CropArt.destroy(tv.view) end -- (the view's folder with it)
			if tv.glow then tv.glow:Destroy() end
			known[tv.hb] = nil
			table.remove(tiles, i)
		end
	end

	for _, tv in tiles do
		local hb = tv.hb
		local crop = hb:GetAttribute("Crop") or ""
		local marks = hb:GetAttribute("Marks") or 0
		local at = hb:GetAttribute("PlantedAt") or 0
		local last = hb:GetAttribute("LastStrike") or 0
		local owner = hb:GetAttribute("Owner") or 0
		local mine = tv.slot == me and owner == player.UserId

		-- a harvest on my farm: the crop went away or was replanted
		if mine and tv.crop ~= "" and (crop ~= tv.crop or at ~= tv.plantedAt) then
			local c = byId[tv.crop]
			if c and t >= tv.plantedAt + c.grow - 1 then
				local v = Economy.saleValue(tv.crop, tv.marks, Config)
				pop(soilTop(tv).Position + Vector3.new(0, 4, 0), "+" .. Text.short(v), if tv.marks ~= 0 then Color3.fromRGB(255, 220, 90) else Color3.fromRGB(240, 255, 220))
			end
		end
		-- a new strike: show it, and on my farm celebrate a Tempest
		if last ~= tv.lastStrike and last > 0 then
			local gained = bit32.band(marks, bit32.bnot(tv.marks))
			if tv.crop == crop and gained ~= 0 then
				strike(tv, gained, t)
				if mine and marks == 7 then
					FxClient.flash(Color3.fromRGB(255, 255, 255), 0.45, 0.9)
					FxClient.fovPunch(8, 0.12, 0.6)
				end
			end
		end
		tv.lastStrike = last

		-- (re)build the crop model when the crop changed
		if crop ~= tv.crop or at ~= tv.plantedAt then
			if tv.view then
				CropArt.destroy(tv.view)
				tv.view = nil
			end
			tv.crop, tv.plantedAt, tv.bucket = crop, at, -1
			tv.marks = 0
			if crop ~= "" and byId[crop] then
				local tfolder = Instance.new("Folder")
				tfolder.Name = "Crop_" .. tv.slot .. "_" .. tv.key
				tfolder.Parent = folder
				tv.view = CropArt.build(tfolder, byId[crop], soilTop(tv))
			end
		end
		if tv.view then
			if marks ~= tv.marks then
				CropArt.setMarks(tv.view, marks, M)
				tv.marks = marks
			end
			local c = byId[crop]
			local stage = Growth.stage(t, at, c.grow)
			local ripe = Growth.shownRipe(t, at, c.grow, Config.Play.RipeLeadSeconds)
			local bucket = math.floor(stage * 20)
			if bucket ~= tv.bucket or ripe ~= tv.ripe then
				tv.bucket, tv.ripe = bucket, ripe
				CropArt.setStage(tv.view, stage, ripe)
			end
			if (tv.hb.Position - camPos).Magnitude < 90 then
				CropArt.animate(tv.view, clock, tv.phase)
			end
		else
			tv.marks = marks
		end

		-- my farm: rim glow on empty tiles you own, the arrow, the next field's price
		if mine then
			local locked = hb:GetAttribute("Locked") == true
			local wantGlow = crop == "" and not locked
			if wantGlow and tv.glow == nil then
				local sb = Instance.new("SelectionBox")
				sb.Name = "TileGlow"
				sb.Adornee = hb
				sb.Color3 = Color3.fromRGB(170, 255, 150)
				sb.LineThickness = 0.06
				sb.SurfaceTransparency = 0.92
				sb.SurfaceColor3 = Color3.fromRGB(170, 255, 150)
				sb.Transparency = 0.35
				sb.Parent = fxFolder
				tv.glow = sb
			elseif not wantGlow and tv.glow then
				tv.glow:Destroy()
				tv.glow = nil
			end
			if wantGlow then
				local d = (hb.Position - camPos).Magnitude
				if d < nearestD then nearestEmpty, nearestD = tv, d end
			end
			local field = hb:GetAttribute("Field") or 1
			if locked and field == fields + 1 and hb:GetAttribute("Tile") == 5 then
				local price = Economy.nextFieldPrice({ fields = fields }, Config)
				if price then
					local s = ensureFieldSign()
					s.Adornee = hb
					s.Enabled = true
					local l = s:FindFirstChild("Label") :: TextLabel
					l.Text = string.format("🧱 Field %d · %s", field, Text.int(price))
					lockedShown = true
				end
			end
			-- frost: your soil ices over while a frost runs
			local soil = hb.Parent and hb.Parent:FindFirstChild("Soil_" .. tv.key)
			if soil then
				if frostTint[soil] == nil then frostTint[soil] = (soil :: BasePart).Color end
				local w = if frostKind == "frost" then frostW else 0
				(soil :: BasePart).Color = frostTint[soil]:Lerp(Color3.fromRGB(235, 245, 255), w * 0.8)
			end
		else
			if tv.glow then
				tv.glow:Destroy()
				tv.glow = nil
			end
			-- a farm that stopped being yours (you left and rejoined into another slot) gets its soil back
			local soil = hb.Parent and hb.Parent:FindFirstChild("Soil_" .. tv.key)
			if soil and frostTint[soil] then
				(soil :: BasePart).Color = frostTint[soil]
				frostTint[soil] = nil
			end
		end
	end

	-- the first-minute arrow, until the first harvest
	if nearestEmpty and harvestsSoFar == 0 and player:GetAttribute("Loaded") == true then
		local a = ensureArrow()
		a.Adornee = nearestEmpty.hb
		a.Enabled = true
	elseif arrow then
		arrow.Enabled = false
	end
	if fieldSign and not lockedShown then fieldSign.Enabled = false end

	-- mark emitters: only the nearest MaxMarkEmitters marked crops within MarkEmitterRange
	emitterAccum += dt
	if emitterAccum >= 0.5 then
		emitterAccum = 0
		local marked = {}
		for _, tv in tiles do
			if tv.view and tv.marks ~= 0 then
				local d = (tv.hb.Position - camPos).Magnitude
				table.insert(marked, { tv = tv, d = d })
			end
		end
		table.sort(marked, function(a, b) return a.d < b.d end)
		for i, e in marked do
			CropArt.setEmitter(e.tv.view, i <= B.MaxMarkEmitters and e.d <= B.MarkEmitterRange, M)
		end
	end
end

local function fx(dt: number)
	local clock = tick()
	for i = #bolts, 1, -1 do
		if clock >= bolts[i].untilT then
			for _, p in bolts[i].parts do p:Destroy() end
			table.remove(bolts, i)
		end
	end
	for i = #bursts, 1, -1 do
		local b = bursts[i]
		local age = clock - b.born
		if age > 0.6 then
			b.part:Destroy()
			table.remove(bursts, i)
		elseif b.frost then
			local d = 2 + age * 18
			b.part.Size = Vector3.new(0.2, d, d)
			b.part.Transparency = 0.3 + age
		else
			b.part.Size = Vector3.new(0.2 + age * 20, 1.5, 1.5)
			b.part.CFrame = CFrame.new(b.at + Vector3.new(0, age * 10, 0)) * CFrame.Angles(0, 0, math.rad(90))
			b.part.Transparency = 0.3 + age
		end
	end
	for i = #pops, 1, -1 do
		local p = pops[i]
		local age = clock - p.born
		if age > 1.1 then
			p.part:Destroy()
			table.remove(pops, i)
		else
			p.part.CFrame = CFrame.new(p.from + Vector3.new(0, age * 4, 0))
			p.label.TextTransparency = math.max(0, age - 0.5) / 0.6
		end
	end
end

-- ── taps: what the player SEES under the thumb is what the server gets ──────────────────────────────────
local tapRemote = ReplicatedStorage:WaitForChild("StormRemotes"):WaitForChild("Tap") :: RemoteEvent
local PICK_PARTS = { "foliage", "produce", "ice", "halo", "spark" }
local MAX_PICK = 600 -- studs: beyond the valley wall

local function boxOf(p: BasePart, tv: TileView): any
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local sz = p.Size
	return { x = x, y = y, z = z, r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 }, hx = sz.X / 2, hy = sz.Y / 2, hz = sz.Z / 2, tv = tv }
end

-- every drawn thing a tap can land on: each tile's soil plate (its Tile_ part is the plate's exact twin) and the
-- crop parts drawn on it (a part faded out, a sprout's produce, takes no part)
local function pickBoxes(): { any }
	local out = {}
	for _, tv in tiles do
		if tv.hb.Parent ~= nil then
			table.insert(out, boxOf(tv.hb, tv))
			local v = tv.view
			if v then
				for _, k in PICK_PARTS do
					local p = v[k]
					if p ~= nil and p.Parent ~= nil and p.Transparency < 0.95 then table.insert(out, boxOf(p, tv)) end
				end
			end
		end
	end
	return out
end

local function insetY(): number
	local ok, topLeft = pcall(function()
		return GuiService:GetGuiInset()
	end)
	return if ok and topLeft then topLeft.Y else 0
end

-- the camera ray through a screen point. `viewport` = the point includes the topbar (GetMouseLocation);
-- otherwise it is in GUI-inset space (TouchTap, InputObject.Position). Roblox: the engine's own camera rays.
-- robloxemu has none, so there the same pinhole math (Pick.viewportRay: a vertical field of view).
local function rayAt(x: number, y: number, viewport: boolean): (number, number, number, number, number, number)
	local cam = workspace.CurrentCamera
	local fn = (cam :: any)[if viewport then "ViewportPointToRay" else "ScreenPointToRay"]
	if type(fn) == "function" then
		local ray = fn(cam, x, y)
		local o, d = ray.Origin, ray.Direction
		return o.X, o.Y, o.Z, d.X, d.Y, d.Z
	end
	local cx, cy, cz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cam.CFrame:GetComponents()
	local vs = cam.ViewportSize
	return Pick.viewportRay({ x = cx, y = cy, z = cz, r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 } },
		cam.FieldOfView, vs.X, vs.Y, x, if viewport then y else y + insetY())
end

-- the tile under a screen point, or nil (the ground, the sky)
local function tileAt(x: number, y: number, viewport: boolean): TileView?
	local ox, oy, oz, dx, dy, dz = rayAt(x, y, viewport)
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-9 then return nil end
	local maxT = math.min(Pick.toGround(ox, oy, oz, dx, dy, dz, Config.Farm.GroundY), MAX_PICK / len)
	local b = Pick.first(ox, oy, oz, dx, dy, dz, pickBoxes(), maxT)
	return if b then b.tv else nil
end

local function tapAt(x: number, y: number)
	local tv = tileAt(x, y, false)
	if tv then tapRemote:FireServer(tv.slot, tv.key) end
end

-- a phone: a tap (a drag is a camera pan, not a tap), unless a button or a touch control took it
UserInputService.TouchTap:Connect(function(positions: any, processed: boolean)
	if processed or type(positions) ~= "table" then return end
	local p = positions[1]
	if p then tapAt(p.X, p.Y) end
end)
-- a mouse: a click is a press and a release close together in place and time (a drag turns the camera)
local pressAt: number? = nil
local pressPos: Vector3? = nil
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	pressAt, pressPos = tick(), input.Position
end)
UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 or pressAt == nil or pressPos == nil then return end
	local held, moved = tick() - (pressAt :: number), (input.Position - (pressPos :: Vector3)).Magnitude
	pressAt, pressPos = nil, nil
	if held <= 0.6 and moved <= 12 then tapAt(input.Position.X, input.Position.Y) end
end)

-- hover (mouse): what a tile holds and what a tap does, for the tile under the pointer
local hoverGui = Instance.new("BillboardGui")
hoverGui.Name = "TileInfo"
hoverGui.Size = UDim2.fromOffset(230, 40)
hoverGui.StudsOffset = Vector3.new(0, 4, 0)
hoverGui.AlwaysOnTop = true
hoverGui.Enabled = false
local hoverLabel = Instance.new("TextLabel")
hoverLabel.Size = UDim2.fromScale(1, 1)
hoverLabel.BackgroundTransparency = 0.3
hoverLabel.BackgroundColor3 = Color3.fromRGB(20, 26, 36)
hoverLabel.Font = Enum.Font.GothamBold
hoverLabel.TextScaled = true
hoverLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
hoverLabel.Parent = hoverGui
hoverGui.Parent = fxFolder
local function describe(hb: BasePart): string
	local crop = hb:GetAttribute("Crop") or ""
	if hb:GetAttribute("Locked") == true then return "🧱 Locked field" end
	if crop == "" then return "Empty: tap to plant" end
	local c = byId[crop]
	if c == nil then return crop end
	local marks = hb:GetAttribute("Marks") or 0
	local at = hb:GetAttribute("PlantedAt") or 0
	local name = (if marks ~= 0 then Mutation.emoji(marks, M) .. " " .. (Mutation.variant(marks, Config.Variants) or "") .. " " else "") .. c.name
	local t = now()
	if Growth.shownRipe(t, at, c.grow, Config.Play.RipeLeadSeconds) then
		return name .. " · tap for " .. Text.int(Economy.saleValue(crop, marks, Config))
	end
	return name .. " · ripe in " .. Text.clock(Growth.remaining(t, at, c.grow))
end
local hoverTile: TileView? = nil
local lastLoc, lastCam = nil :: Vector2?, nil :: CFrame?
local function hover()
	if not UserInputService.MouseEnabled or UserInputService.TouchEnabled then
		hoverGui.Enabled = false
		return
	end
	-- pick again only when the pointer or the camera moved; the label's text (ripe in 0:12) refreshes every time
	local loc = UserInputService:GetMouseLocation()
	local camCF = workspace.CurrentCamera.CFrame
	if loc ~= lastLoc or camCF ~= lastCam then
		lastLoc, lastCam = loc, camCF
		hoverTile = if loc then tileAt(loc.X, loc.Y, true) else nil
	end
	local tv = hoverTile
	if tv and tv.hb.Parent ~= nil then
		hoverGui.Adornee = tv.hb
		hoverGui.Enabled = true
		hoverLabel.Text = describe(tv.hb)
	else
		hoverGui.Enabled = false
	end
end

local frameError = false
RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(function()
		accum += dt
		if accum >= 0.1 then
			local step = accum
			accum = 0
			update(step)
			hover()
		end
		fx(dt)
	end)
	if not ok and not frameError then
		frameError = true
		warn("[StormFarm] frame error: " .. tostring(err))
	end
end)
