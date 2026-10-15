-- DISASTER ROUNDS - the disasters' show (client only). Lives in StarterPlayerScripts.
--
-- The server draws the TRUTH: red ring Parts (with ImpactAt), the flood's red line and water, the cells' CrackAt and
-- Dropped attributes, the tornado's Path attribute and Funnel anchor. This script adds the show on top, built from
-- exactly those values and nothing else: the ring's pulse and the projectile that lands on it at ImpactAt, the red
-- tint on cells about to flood or crack, the tornado's red path ribbon and its funnel, falling chunks, Heat flames
-- over every player, confetti for a survival. Physics here is presentation only: nothing it does decides a hit.
-- Budgets (Config.Budget) are capped in code and measured headless (robloxemu/check_disasterrounds_env.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Tornado = require(ReplicatedStorage:WaitForChild("Tornado"))
local Zones = require(ReplicatedStorage:WaitForChild("Zones"))
local FxClient = require(ReplicatedStorage:WaitForChild("FxClient"))

local player = Players.LocalPlayer
local roundFolder = workspace:WaitForChild("Round")
local remotes = ReplicatedStorage:WaitForChild("DRRemotes")
local CardEvent = remotes:WaitForChild("Card")
local B = Config.Budget

local RED = Color3.fromRGB(255, 40, 40)

local lastServerNow, lastLocal = workspace:GetAttribute("ServerNow") or 0, tick()
workspace:GetAttributeChangedSignal("ServerNow"):Connect(function()
	lastServerNow = workspace:GetAttribute("ServerNow") or 0
	lastLocal = tick()
end)
local function serverNow(): number
	return lastServerNow + math.min(1.5, tick() - lastLocal)
end

local folder = Instance.new("Folder")
folder.Name = "DRLocalWorld"
folder.Parent = workspace
local function sub(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = folder
	return f
end
local projFolder, chunkFolder, ribbonFolder, debrisFolder, auraFolder, fxFolder =
	sub("Projectiles"), sub("Chunks"), sub("PathRibbon"), sub("Debris"), sub("Auras"), sub("Fx")

local function mkPart(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in props do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

local function count(f: Instance, class: string): number
	local n = 0
	for _, d in f:GetDescendants() do
		if d:IsA(class) then n += 1 end
	end
	return n
end

local function emitters(): number
	return count(fxFolder, "ParticleEmitter")
end

--============================================================================== rings and projectiles

-- one fixed compass direction per round for everything that falls from the sky (players learn where to look up)
local function radiant(): Vector3
	local id = roundFolder:GetAttribute("RoundId") or 0
	local a = (id * 2.399963) % (2 * math.pi)
	return Vector3.new(math.cos(a), 1.6, math.sin(a)).Unit
end

local PROJ = {
	meteor = { color = Color3.fromRGB(255, 170, 70), size = 3, neon = true },
	flood = { color = Color3.fromRGB(220, 230, 255), size = 1.2, neon = true },
	tornado = { color = Color3.fromRGB(130, 110, 90), size = 2.2, neon = false },
	quake = { color = Color3.fromRGB(120, 116, 110), size = 3.2, neon = false },
}
local projectiles: { [Instance]: BasePart } = {}
local ringBase: { [Instance]: number } = {}

local function updateRings(t: number)
	local rings = roundFolder:FindFirstChild("Rings")
	local live: { [Instance]: boolean } = {}
	if rings then
		for _, r in rings:GetChildren() do
			local impact = r:GetAttribute("ImpactAt")
			if type(impact) == "number" then
				live[r] = true
				-- the ring pulses faster as impact nears
				local left = math.max(0, impact - t)
				local rate = 3 + 9 * (1 - math.min(1, left / Config.Strikes.TelegraphSeconds))
				ringBase[r] = ringBase[r] or (r :: BasePart).Transparency
				;(r :: BasePart).Transparency = math.clamp(0.25 + 0.3 * math.abs(math.sin(t * rate)), 0, 0.9)
				-- the projectile lands on the ring's centre exactly at ImpactAt
				local proj = projectiles[r]
				if proj == nil and left > 0 and #projFolder:GetChildren() < B.Projectiles then
					local look = PROJ[r:GetAttribute("Theme")] or PROJ.meteor
					proj = mkPart(projFolder, { Name = "Projectile", Shape = Enum.PartType.Ball,
						Size = Vector3.new(look.size, look.size, look.size), Color = look.color,
						Material = if look.neon then Enum.Material.Neon else Enum.Material.Slate })
					projectiles[r] = proj
				end
				if proj then
					-- the ring is a red volume over every terrace it reaches (REVIEW-1 F7); the projectile lands on the
					-- top under its centre
					local rp = (r :: BasePart).Position
					local gy = r:GetAttribute("GroundY")
					local target = Vector3.new(rp.X, if type(gy) == "number" then gy else rp.Y, rp.Z)
					local frac = math.clamp(left / Config.Strikes.TelegraphSeconds, 0, 1)
					proj.Position = target + radiant() * 160 * frac
					if left <= 0 then
						proj:Destroy()
						projectiles[r] = nil
						-- an impact near you shakes the camera
						local char = player.Character
						local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
						if hrp and (hrp.Position - target).Magnitude < 20 then
							pcall(function() FxClient.shake(0.3, 0.6) end)
						end
					end
				end
			end
		end
	end
	for r, proj in projectiles do
		if not live[r] then
			proj:Destroy()
			projectiles[r] = nil
		end
	end
	for r in ringBase do
		if not live[r] then ringBase[r] = nil end
	end
end

--============================================================================== flood and quake tints

local tinted: { [Instance]: Color3 } = {}
local function tint(cell: BasePart, on: boolean)
	if on then
		if tinted[cell] == nil then
			tinted[cell] = cell.Color
			cell.Color = cell.Color:Lerp(RED, 0.65)
		end
	elseif tinted[cell] ~= nil then
		cell.Color = tinted[cell]
		tinted[cell] = nil
	end
end

local chunkFor: { [Instance]: boolean } = {}
local function dropChunks(cell: BasePart, t: number)
	if chunkFor[cell] then return end
	chunkFor[cell] = true
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and (hrp.Position - cell.Position).Magnitude > 120 then return end -- nearest cells only
	local top = cell.Position.Y + cell.Size.Y / 2
	for k = 1, B.ChunksPerCell do
		if #chunkFolder:GetChildren() >= B.Chunks then break end
		local c = mkPart(chunkFolder, { Name = "Chunk", Size = Vector3.new(3, 2, 3), Color = tinted[cell] or cell.Color,
			Material = cell.Material, Position = Vector3.new(cell.Position.X + (k % 3 - 1) * 2.4, top - 1, cell.Position.Z + (math.floor(k / 3) - 0.5) * 2.4) })
		c:SetAttribute("DieAt", t + B.ChunkSeconds)
	end
	if hrp and (hrp.Position - cell.Position).Magnitude < 30 then
		pcall(function() FxClient.shake(0.35, 0.7) end)
	end
end

local function updateCells(t: number)
	local island = roundFolder:FindFirstChild("Island")
	local cells = island and island:FindFirstChild("Cells")
	local kind = roundFolder:GetAttribute("Kind")
	local warnLevel = roundFolder:GetAttribute("WarnLevel")
	local riseEnd = roundFolder:GetAttribute("RiseEnd")
	if cells then
		for _, cell in cells:GetChildren() do
			local level = cell:GetAttribute("Level")
			local red = false
			if kind == "flood" and type(warnLevel) == "number" and type(level) == "number" and type(riseEnd) == "number" then
				red = level <= warnLevel and t < riseEnd + 0.5
			elseif kind == "quake" then
				red = cell:GetAttribute("CrackAt") ~= nil and cell:GetAttribute("Dropped") ~= true
			end
			tint(cell :: BasePart, red)
			if cell:GetAttribute("Dropped") == true then dropChunks(cell :: BasePart, t) end
		end
	end
	for cell in tinted do
		if cell.Parent == nil then tinted[cell] = nil end
	end
	-- chunks fall for ChunkSeconds and go
	for _, c in chunkFolder:GetChildren() do
		local die = c:GetAttribute("DieAt")
		if type(die) ~= "number" or t >= die then
			c:Destroy()
		else
			(c :: BasePart).Position -= Vector3.new(0, 0.6, 0)
		end
	end
	for cell in chunkFor do
		if cell.Parent == nil then chunkFor[cell] = nil end
	end
end

--============================================================================== the tornado

local funnelRings: { BasePart } = {}
-- the red path's Parts, reused frame to frame (boxes and discs); a frame parents the ones it uses and unparents the rest
local boxPool: { BasePart } = {}
local discPool: { BasePart } = {}
local FUNNEL_R = Config.Tornado.HitRadius + Config.Hits.PlayerRadius
local IC = Config.Island
-- the island's cell levels, read once per island; a dropped cell has no ground
local levelIsland: Instance? = nil
local levelCells: { [number]: BasePart } = {}
local function groundLevel(i: number, j: number): number?
	local c = levelCells[i * 100 + j]
	if c == nil or c.Parent == nil or c:GetAttribute("Dropped") == true then return nil end
	local l = c:GetAttribute("Level")
	return if type(l) == "number" then l else nil
end
local function bindLevels()
	local island = roundFolder:FindFirstChild("Island")
	if island == levelIsland then return end
	levelIsland = island
	table.clear(levelCells)
	local cells = island and island:FindFirstChild("Cells")
	if cells then
		for _, c in cells:GetChildren() do
			local i, j = c:GetAttribute("I"), c:GetAttribute("J")
			if type(i) == "number" and type(j) == "number" then levelCells[i * 100 + j] = c :: BasePart end
		end
	end
end
local function clearPath()
	for _, p in boxPool do p.Parent = nil end
	for _, p in discPool do p.Parent = nil end
end
-- The red is exactly the funnel's reach (REVIEW-1 F8): a disc of HitRadius + PlayerRadius on the funnel where it is
-- now and on every published point ahead of it, and a box as wide joining each two in a row; nothing behind the
-- funnel. Before touchdown the track starts at the touchdown point, so the path shows from the name. Every piece is a
-- red volume over every terrace it reaches (REVIEW-1 F7), from 0.05 over the lowest top to 0.25 over the highest.
local function drawPath(anchor: BasePart?)
	local _, pts = Tornado.decode(roundFolder:GetAttribute("Path"))
	if not pts or #pts == 0 then
		clearPath()
		return
	end
	bindLevels()
	local track = {}
	if anchor and anchor.Position.Y > -100 then
		table.insert(track, { x = anchor.Position.X, z = anchor.Position.Z })
	else
		table.insert(track, pts[1])
	end
	for k = 2, #pts do table.insert(track, pts[k]) end
	local nBox, nDisc = 0, 0
	local function room(): boolean return nBox + nDisc < B.PathRibbon end
	local function disc(x: number, z: number)
		if not room() then return end
		local lo, hi = Zones.redSpan(IC, Zones.cellsUnderDisk(IC, x, z, FUNNEL_R), groundLevel)
		if lo == nil or hi == nil then return end
		nDisc += 1
		local p = discPool[nDisc]
		if p == nil then
			p = mkPart(ribbonFolder, { Name = "PathDisc", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
				Color = RED, Transparency = 0.55 })
			discPool[nDisc] = p
		end
		p.Size = Vector3.new(hi - lo, 2 * FUNNEL_R, 2 * FUNNEL_R)
		p.CFrame = CFrame.new(x, (lo + hi) / 2, z) * CFrame.Angles(0, 0, math.rad(90))
		p.Parent = ribbonFolder
	end
	local function box(a: any, b: any)
		local dx, dz = b.x - a.x, b.z - a.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 0.01 or not room() then return end
		local ux, uz = dx / len, dz / len
		local mx, mz = (a.x + b.x) / 2, (a.z + b.z) / 2
		local lo, hi = Zones.redSpan(IC, Zones.cellsUnderBox(IC, mx, mz, ux, uz, len / 2, FUNNEL_R), groundLevel)
		if lo == nil or hi == nil then return end
		nBox += 1
		local p = boxPool[nBox]
		if p == nil then
			p = mkPart(ribbonFolder, { Name = "PathRibbon", Material = Enum.Material.Neon, Color = RED, Transparency = 0.55 })
			boxPool[nBox] = p
		end
		local c = Vector3.new(mx, (lo + hi) / 2, mz)
		p.Size = Vector3.new(2 * FUNNEL_R, hi - lo, len)
		p.CFrame = CFrame.lookAt(c, c + Vector3.new(ux, 0, uz))
		p.Parent = ribbonFolder
	end
	disc(track[1].x, track[1].z)
	for k = 2, #track do
		box(track[k - 1], track[k])
		disc(track[k].x, track[k].z)
	end
	for k = nBox + 1, #boxPool do boxPool[k].Parent = nil end
	for k = nDisc + 1, #discPool do discPool[k].Parent = nil end
end

local function updateTornado(t: number)
	local kind = roundFolder:GetAttribute("Kind")
	local anchor = roundFolder:FindFirstChild("Funnel") :: BasePart?
	if kind ~= "tornado" then
		clearPath()
		debrisFolder:ClearAllChildren()
		for _, r in funnelRings do r:Destroy() end
		table.clear(funnelRings)
		return
	end
	drawPath(anchor)
	if not anchor or anchor.Position.Y < -100 then
		-- before touchdown: the path is drawn, the funnel is not there yet
		debrisFolder:ClearAllChildren()
		for _, r in funnelRings do r:Destroy() end
		table.clear(funnelRings)
		return
	end
	-- the funnel: stacked spinning rings over the anchor
	if #funnelRings == 0 then
		for k = 1, 6 do
			table.insert(funnelRings, mkPart(fxFolder, { Name = "FunnelRing", Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.2, 4 + k * 3, 4 + k * 3), Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(150, 150, 140), Transparency = 0.35 }))
		end
	end
	for k, r in funnelRings do
		r.CFrame = CFrame.new(anchor.Position + Vector3.new(0, k * 3.5, 0)) * CFrame.Angles(0, t * (4 + k), 0) * CFrame.Angles(0, 0, math.rad(90))
	end
	-- debris orbiting the funnel
	while #debrisFolder:GetChildren() < B.Debris do
		mkPart(debrisFolder, { Name = "Debris", Size = Vector3.new(1.2, 0.4, 2), Material = Enum.Material.Wood,
			Color = Color3.fromRGB(130, 100, 70) })
	end
	for k, d in debrisFolder:GetChildren() do
		local a = t * 3 + k
		;(d :: BasePart).CFrame = CFrame.new(anchor.Position + Vector3.new(math.cos(a) * (6 + k % 4), 2 + k * 1.3, math.sin(a) * (6 + k % 4)))
			* CFrame.Angles(a, a * 0.7, 0)
	end
end

--============================================================================== Heat flames over every player

local auras: { [Player]: { emitter: ParticleEmitter?, board: BillboardGui?, label: TextLabel? } } = {}
local function updateAuras()
	local seen: { [Player]: boolean } = {}
	local n = 0
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local heat = plr:GetAttribute("Heat") or 0
		local survived = plr:GetAttribute("Survived") or 0
		if hrp and (heat > 0 or survived >= 21) and n < B.Auras then
			n += 1
			seen[plr] = true
			local a = auras[plr]
			if a == nil or a.emitter == nil or a.emitter.Parent ~= hrp then
				if a and a.emitter then a.emitter:Destroy() end
				if a and a.board then a.board:Destroy() end
				local e = Instance.new("ParticleEmitter")
				e.Name = "HeatAura"
				e.LightEmission = 1
				e.Lifetime = NumberRange.new(0.5, 0.9)
				e.Speed = NumberRange.new(2, 4)
				e.Size = NumberSequence.new(0.8, 0)
				e.Parent = hrp
				local bb = Instance.new("BillboardGui")
				bb.Name = "HeatBillboard"
				bb.Size = UDim2.fromOffset(80, 30)
				bb.StudsOffset = Vector3.new(0, 4, 0)
				bb.AlwaysOnTop = false
				bb.Adornee = hrp
				bb.Parent = auraFolder
				local l = Instance.new("TextLabel")
				l.Name = "HeatText"
				l.BackgroundTransparency = 1
				l.Size = UDim2.fromScale(1, 1)
				l.Font = Enum.Font.GothamBlack
				l.TextScaled = true
				l.TextColor3 = Color3.fromRGB(255, 190, 80)
				l.TextStrokeTransparency = 0.4
				l.Parent = bb
				a = { emitter = e, board = bb, label = l }
				auras[plr] = a
			end
			local e = a.emitter :: ParticleEmitter
			-- orange-gold flames, the rate growing with Heat; an amber ember aura for good once the sky has fallen
			e.Rate = if heat > 0 then 6 * heat else 3
			e.Color = ColorSequence.new(if heat > 0 then Color3.fromRGB(255, 170, 60) else Color3.fromRGB(255, 200, 120))
			local txt = if heat > 0 then "🔥" .. heat else "☄️"
			if a.label and a.label.Text ~= txt then a.label.Text = txt end
		end
	end
	for plr, a in auras do
		if not seen[plr] then
			if a.emitter then a.emitter:Destroy() end
			if a.board then a.board:Destroy() end
			auras[plr] = nil
		end
	end
end

--============================================================================== weather of the disaster itself

local rain: ParticleEmitter? = nil
local dust: ParticleEmitter? = nil
local host = mkPart(fxFolder, { Name = "DisasterFxHost", Size = Vector3.new(110, 1, 110), Transparency = 1, Position = Vector3.new(0, 60, 0) })
local function updateWeather()
	local kind = roundFolder:GetAttribute("Kind")
	if kind == "flood" and rain == nil and emitters() < B.DisasterEmitters then
		local e = Instance.new("ParticleEmitter")
		e.Name = "FloodRain"
		e.Rate = 50
		e.Speed = NumberRange.new(70, 90)
		e.Lifetime = NumberRange.new(1, 1.4)
		e.Size = NumberSequence.new(0.15)
		e.Color = ColorSequence.new(Color3.fromRGB(190, 200, 220))
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Parent = host
		rain = e
	elseif kind ~= "flood" and rain then
		rain:Destroy()
		rain = nil
	end
	if (kind == "tornado" or kind == "quake") and dust == nil and emitters() < B.DisasterEmitters then
		local e = Instance.new("ParticleEmitter")
		e.Name = "DustHaze"
		e.Rate = 12
		e.Speed = NumberRange.new(2, 6)
		e.Lifetime = NumberRange.new(3, 5)
		e.Size = NumberSequence.new(3, 8)
		e.Color = ColorSequence.new(if kind == "tornado" then Color3.fromRGB(150, 160, 130) else Color3.fromRGB(170, 140, 110))
		e.Parent = host
		dust = e
	elseif kind ~= "tornado" and kind ~= "quake" and dust then
		dust:Destroy()
		dust = nil
	end
end

--============================================================================== confetti for a survival

CardEvent.OnClientEvent:Connect(function(kind)
	if kind ~= "survived" then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp or fxFolder:FindFirstChild("Confetti") then return end
	local p = mkPart(fxFolder, { Name = "Confetti", Size = Vector3.new(1, 1, 1), Transparency = 1, Position = hrp.Position + Vector3.new(0, 3, 0) })
	local e = Instance.new("ParticleEmitter")
	e.Name = "ConfettiBurst"
	e.Rate = 0
	e.Speed = NumberRange.new(14, 24)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Lifetime = NumberRange.new(1.5, 2.5)
	e.Size = NumberSequence.new(0.35)
	-- gold, white, teal: never red
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 90)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 210, 200)),
	})
	e.Parent = p
	pcall(function() e:Emit(60) end)
	task.delay(3, function() p:Destroy() end)
end)

--============================================================================== the frame

local frameError = false
RunService.RenderStepped:Connect(function()
	local ok, err = pcall(function()
		local t = serverNow()
		updateRings(t)
		updateCells(t)
		updateTornado(t)
		updateAuras()
		updateWeather()
	end)
	if not ok and not frameError then
		frameError = true
		warn("[DisasterRounds] world frame error: " .. tostring(err))
	end
end)
