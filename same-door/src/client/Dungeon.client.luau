-- The Same Door — the dungeon you walk, built on YOUR client. StarterPlayerScripts.
--
-- What this script does, for the local player only:
--   * builds the revealed cells the server sends (Cell remote): interior walls, the veils that fill
--     every cell not yet revealed, the Seals, the Door and the hazard fixtures. It is sent only cells
--     the server has seen you walk within 2 open steps of, so it never holds more than you reached;
--   * keeps the run's display clock: it starts when THIS client sees its own root cross the line
--     (the server keeps the official clock the same way on its side), published as the player
--     attribute SameDoorClock for the HUD;
--   * runs the environment bands (Config.Env.Bands through EnvBands, verbatim from +1 Jump): light,
--     colour, decor on revealed walls, critters and weather, driven by the seals you carry, never by
--     time, glided on a 0.8 s half-life and written to Lighting at most 10 times a second;
--   * runs the day's three fork hazards (DoorHazards) on the display clock: the fixture shakes, the
--     red ring (exactly the hit zone) pulses, and an impact inside the ring knocks YOUR character down
--     for 0.8 s. The server trusts none of this and is sent nothing: deleting it saves at most the
--     knocks a careful player never takes;
--   * enforces the budgets in code: local parts, lights and emitters (Config.Budget).
-- Headless checks: robloxemu/check_samedoor_eyecandy.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Grid = require(ReplicatedStorage:WaitForChild("Grid"))
local EnvBands = require(ReplicatedStorage:WaitForChild("EnvBands"))
local Bands = require(ReplicatedStorage:WaitForChild("Bands"))
local DoorHazards = require(ReplicatedStorage:WaitForChild("DoorHazards"))
local DungeonArt = require(ReplicatedStorage:WaitForChild("DungeonArt"))

local remotes = ReplicatedStorage:WaitForChild("SameDoorRemotes")
local CellEvent = remotes:WaitForChild("Cell")
local RunEvent = remotes:WaitForChild("Run")

local player = Players.LocalPlayer
local G, B, Env, HZ = Config.Grid, Config.Budget, Config.Env, Config.Hazards
local bands = Env.Bands

-- A broken config costs the polish, never the game: warn and switch that part off.
local bandsOn, bandsErr = Bands.validate(Config, EnvBands)
if not bandsOn then
	warn("[SameDoor] Config.Env.Bands is invalid (" .. tostring(bandsErr) .. "); the halls keep one look.")
end
local hazardsOn, hazardsErr = DoorHazards.validate(HZ)
if not hazardsOn then
	warn("[SameDoor] Config.Hazards is invalid (" .. tostring(hazardsErr) .. "); hazards are OFF.")
end

local root = Instance.new("Folder")
root.Name = "SameDoorLocal"
root.Parent = workspace

--============================================================================ the run
local run: any = nil
local SIDE_LIST = { "N", "E", "S", "W" }
local NORMALS = { N = Vector3.new(0, 0, -1), S = Vector3.new(0, 0, 1), E = Vector3.new(-1, 0, 0), W = Vector3.new(1, 0, 0) }

local function setAttr(name: string, value: any)
	if player:GetAttribute(name) ~= value then player:SetAttribute(name, value) end
end

local function countParts(): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

-- A hazard knock sets PlatformStand for 0.8 s and only runHazards (ready/running) lifts it. A run that
-- ends, voids or finishes mid-knock (pause -> Leave run inside the 0.8 s) must stand the player back
-- up here, or they arrive at the fire unable to walk, in every later run too (REVIEW-1, reviewer 2).
local function releaseKnock()
	if run == nil or run.knockedUntil == nil then return end
	run.knockedUntil = nil
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand = false end
end

local function clearRun()
	releaseKnock()
	if run and run.folder then run.folder:Destroy() end
	run = nil
	setAttr("SameDoorClock", -1)
	setAttr("SameDoorWarn", false)
	setAttr("SameDoorBand", 0)
end

local function bandIndex(): number
	if run == nil then return 0 end
	return EnvBands.indexAt(bands, Bands.progress(run.seals, run.doorOpen))
end

local function wallColour(): { number }
	local i = bandIndex()
	return if bands[i] then bands[i].wall else { 90, 95, 105 }
end

local function newRun(p: any)
	clearRun()
	local folder = Instance.new("Folder")
	folder.Name = "Run"
	folder.Parent = root
	run = {
		id = p.run,
		origin = Vector3.new(p.origin.x, p.origin.y, p.origin.z),
		phase = "ready",
		seals = 0,
		doorOpen = false,
		folder = folder,
		walls = Instance.new("Folder"),
		veilsFolder = Instance.new("Folder"),
		contents = Instance.new("Folder"),
		decorFolder = Instance.new("Folder"),
		critterFolder = Instance.new("Folder"),
		cells = {}, wallsByKey = {}, veils = {}, sealModels = {}, door = nil, hazards = {},
		clock = -1, crossed = false, prevX = nil, prevZ = nil,
		knockedUntil = nil, knocks = 0, near = 0,
		decor = {}, critters = {},
	}
	run.walls.Name = "Walls"; run.walls.Parent = folder
	run.veilsFolder.Name = "Veils"; run.veilsFolder.Parent = folder
	run.contents.Name = "Contents"; run.contents.Parent = folder
	run.decorFolder.Name = "Decor"; run.decorFolder.Parent = folder
	run.critterFolder.Name = "Critters"; run.critterFolder.Parent = folder
	for cy = 0, G.H - 1 do
		for cx = 0, G.W - 1 do
			run.veils[Grid.index(cx, cy, G.W)] = DungeonArt.veil(run.veilsFolder, run.origin, cx, cy, Config)
		end
	end
	setAttr("SameDoorKnocks", 0)
	setAttr("SameDoorNear", 0)
end

local function buildCell(c: any)
	if run == nil then return end
	local i = Grid.index(c.x, c.y, G.W)
	if run.cells[i] then return end
	run.cells[i] = c
	local veil = run.veils[i]
	if veil then
		veil:Destroy()
		run.veils[i] = nil
	end
	for _, side in SIDE_LIST do
		if not Grid.hasSide(c.sides, side) then
			local key = Grid.edgeKey(c.x, c.y, side, Config)
			if not Grid.isPerimeter(key, Config) and run.wallsByKey[key] == nil then
				local seg = Grid.edgeSegment(key, Config)
				local w = DungeonArt.wall(run.walls, run.origin, seg, Config, wallColour())
				w:SetAttribute("Edge", key)
				run.wallsByKey[key] = w
			end
		end
	end
	if c.kind == "seal" then
		local m = DungeonArt.seal(run.contents, run.origin, c.x, c.y, Config)
		m:SetAttribute("Cell", c.x .. "," .. c.y)
		run.sealModels[c.x .. "," .. c.y] = m
	elseif c.kind == "door" then
		run.door = DungeonArt.door(run.contents, run.origin, c.x, c.y, Config)
		DungeonArt.setDoor(run.door, run.seals, Config)
	elseif c.kind == "hazard" and hazardsOn then
		local kind = DoorHazards.kindFor(math.max(bandIndex(), 1), HZ)
		local m = DungeonArt.hazard(run.contents, run.origin, c.x, c.y, kind, DoorHazards.ringRadius(HZ), Config)
		m:SetAttribute("Slot", c.slot)
		local wx, wz = Grid.centre(c.x, c.y, Config)
		table.insert(run.hazards, {
			slot = c.slot, model = m,
			centre = { x = run.origin.X + wx, y = run.origin.Y, z = run.origin.Z + wz },
			ring = m:FindFirstChild("Ring"), fixture = m:FindFirstChild("Fixture"), falling = m:FindFirstChild("Falling"),
		})
	end
end

CellEvent.OnClientEvent:Connect(function(p: any)
	if type(p) ~= "table" or run == nil or p.run ~= run.id or type(p.cells) ~= "table" then return end
	for _, c in p.cells do buildCell(c) end
end)

RunEvent.OnClientEvent:Connect(function(p: any)
	if type(p) ~= "table" then return end
	if p.state == "ready" and p.origin then
		newRun(p)
		return
	end
	if p.state == "hub" then
		clearRun()
		return
	end
	if run == nil or p.run ~= run.id then return end
	if p.state == "ended" then
		clearRun()
		return
	end
	if type(p.seals) == "number" and p.seals > run.seals then
		run.seals = p.seals
		if run.door then DungeonArt.setDoor(run.door, run.seals, Config) end
		-- the band changed: walls take the new band's stone
		for _, w in run.wallsByKey do w.Color = DungeonArt.rgb(wallColour()) end
		for _, d in run.decor do d:Destroy() end
		run.decor = {}
	end
	if p.taken then
		local m = run.sealModels[p.taken.x .. "," .. p.taken.y]
		if m then
			m:Destroy()
			run.sealModels[p.taken.x .. "," .. p.taken.y] = nil
		end
	end
	if p.state == "running" then
		run.phase = "running"
	elseif p.state == "finished" then
		releaseKnock()
		run.phase = "finished"
		run.doorOpen = true
		setAttr("SameDoorWarn", false)
		if type(p.timeMs) == "number" then setAttr("SameDoorClock", p.timeMs / 1000) end
	elseif p.state == "void" then
		releaseKnock()
		run.phase = "void"
		setAttr("SameDoorWarn", false)
	end
end)

--============================================================================ lighting: hub look vs bands
-- Color3 -> { r, g, b } so EnvBands can blend it; numbers pass through.
local function arr(c: any): any
	if type(c) == "number" then return c end
	local ok, r = pcall(function() return { c.R * 255, c.G * 255, c.B * 255 } end)
	if ok and type(r[1]) == "number" then return r end
	return c
end

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
	colorCorrection = rig("ColorCorrectionEffect", "FxColorCorrection"),
	bloom = rig("BloomEffect", "FxBloom"),
}
local GROUPS = { "lighting", "colorCorrection", "bloom" }

-- The hub look, captured from what the server's Fx.applyLighting set, so leaving a run restores it.
local hubLook = {}
for _, gname in GROUPS do
	local keys = {}
	for k in bands[1][gname] do keys[k] = true end
	local t = {}
	for k in keys do
		local ok, v = pcall(function() return (targets[gname] :: any)[k] end)
		if ok and v ~= nil then t[k] = arr(v) end
	end
	hubLook[gname] = t
end

local current: { [string]: any } = {}
local lastWrite = -math.huge
local clockNow = 0
local writes = 0

local function writeGroup(inst: Instance, props: { [string]: any })
	for k, v in props do
		local value = v
		if type(v) == "table" then value = Color3.fromRGB(math.clamp(v[1], 0, 255), math.clamp(v[2], 0, 255), math.clamp(v[3], 0, 255)) end
		pcall(function() (inst :: any)[k] = value end)
	end
end

local function targetLook(): { [string]: any }
	local out = {}
	if run == nil or not bandsOn then
		for _, gname in GROUPS do out[gname] = hubLook[gname] end
		return out
	end
	local p = Bands.progress(run.seals, run.doorOpen)
	for _, gname in GROUPS do out[gname] = EnvBands.sample(bands, p, gname) end
	return out
end

--============================================================================ decor, critters, weather
local weatherHosts = {}
for k = 1, B.MaxWeatherEmitters do
	local host, em = DungeonArt.weather(root, tostring(k))
	weatherHosts[k] = { host = host, em = em, kind = nil }
end

local function rootPart(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function refreshDecor(pos: Vector3)
	if run == nil or not bandsOn then return end
	local band = bandIndex()
	-- the part budget, in code: decor fills only what walls, veils, contents and critters leave
	local decorNow, critNow = 0, #run.critters
	for _ in run.decor do decorNow += 1 end
	local fixed = countParts() - decorNow - critNow
	local maxDecor = math.clamp(B.MaxLocalParts - fixed - B.MaxCritters, 0, B.MaxDecor)
	local want = {}
	for i, c in run.cells do
		for _, side in SIDE_LIST do
			if not Grid.hasSide(c.sides, side) then
				local key = Grid.edgeKey(c.x, c.y, side, Config)
				local piece = Bands.decorFor(key, side, band, Config, EnvBands.hash01)
				if piece then
					local seg = Grid.edgeSegment(key, Config)
					local n = NORMALS[side]
					local tangent = if seg.sx > seg.sz then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
					local wp = run.origin + Vector3.new(seg.x, piece.h, seg.z) + n * (G.WallThick / 2 + piece.out) + tangent * piece.u
					local d = (wp - pos).Magnitude
					if d <= Env.DecorRadius then
						table.insert(want, { id = key .. "|" .. side, pos = wp, n = n, piece = piece, d = d })
					end
				end
			end
		end
		local _ = i
	end
	table.sort(want, function(a, b) return a.d < b.d end)
	local keep = {}
	for k = 1, math.min(#want, maxDecor) do keep[want[k].id] = want[k] end
	for id, part in run.decor do
		if keep[id] == nil then
			part:Destroy()
			run.decor[id] = nil
		end
	end
	for id, w in keep do
		if run.decor[id] == nil then
			run.decor[id] = DungeonArt.decor(run.decorFolder, w.pos, w.n, w.piece)
		end
	end
end

local critterPhase = 0
local function refreshCritters(pos: Vector3, dt: number)
	if run == nil or not bandsOn then return end
	local b = bands[math.max(bandIndex(), 1)]
	local want = math.min(b.critter.count, B.MaxCritters)
	for k = #run.critters, want + 1, -1 do
		run.critters[k]:Destroy()
		run.critters[k] = nil
	end
	-- homes: the player's current cell and adjacent revealed cells; outside the grid (the antechamber,
	-- the Dawn Sanctum after the finish) the player's own spot. The first build fell back to the
	-- entrance cell there, so the Sanctum's birds circled ~150 studs away inside the closed grid.
	local lx, lz = pos.X - run.origin.X, pos.Z - run.origin.Z
	local cx, cy, kind = Grid.cellOf(lx, lz, Config)
	local homes = {}
	if kind == "grid" then
		for _, d in { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local i = Grid.index((cx :: number) + d[1], (cy :: number) + d[2], G.W)
			local c = run.cells[i]
			if c and c.x == (cx :: number) + d[1] then
				local hx, hz = Grid.centre(c.x, c.y, Config)
				table.insert(homes, { x = hx, z = hz })
			end
		end
	else
		table.insert(homes, { x = lx, z = lz })
	end
	if #homes == 0 then return end
	critterPhase += dt
	for k = 1, want do
		local home = homes[(k - 1) % #homes + 1]
		local hx, hz = home.x, home.z
		local a = critterPhase * (0.6 + 0.1 * k) + k * 1.7
		local wp = run.origin + Vector3.new(hx + math.cos(a) * 4, 9.5 + (k % 3), hz + math.sin(a) * 4)
		local c = run.critters[k]
		if c == nil or c:GetAttribute("Kind") ~= b.critter.kind then
			if c then c:Destroy() end
			c = DungeonArt.critter(run.critterFolder, wp, b)
			run.critters[k] = c
		end
		c.CFrame = CFrame.new(wp)
	end
end

local function refreshWeather(pos: Vector3)
	local rates = {}
	if run ~= nil and bandsOn then
		rates = EnvBands.capRates(Bands.weatherRates(bands, EnvBands.weights(bands, Bands.progress(run.seals, run.doorOpen))),
			B.MaxWeatherEmitters, B.MaxEmitterRate, B.MinWeatherRate)
	end
	local kinds = {}
	for kind in rates do table.insert(kinds, kind) end
	table.sort(kinds)
	for k, slot in weatherHosts do
		local kind = kinds[k]
		if kind then
			local bi = 1
			for i, b in bands do if b.weather.kind == kind then bi = i end end
			local v = Bands.weatherVelocity(bi, Config)
			slot.em.Rate = rates[kind]
			slot.em.Enabled = true
			slot.em.Color = ColorSequence.new(DungeonArt.rgb(bands[bi].weather.color))
			slot.em.Acceleration = Vector3.new(0, v.y, 0)
			slot.host.CFrame = CFrame.new(pos + Vector3.new(0, if v.y > 0 then -2 else 6, 0))
			slot.kind = kind
		else
			slot.em.Enabled = false
			slot.em.Rate = 0
			slot.kind = nil
		end
	end
end

-- Lights and emitters under budget: the torch is the server's; of the client's own glows only the
-- nearest MaxLights - 1 shine, and of the seal sparkles only the nearest MaxEmitters - weather.
local function enforceBudgets(pos: Vector3)
	local lights, emitters = {}, {}
	for _, d in root:GetDescendants() do
		if d:IsA("PointLight") then
			local p = d.Parent
			if p and p:IsA("BasePart") then table.insert(lights, { l = d, dist = (p.Position - pos).Magnitude }) end
		elseif d:IsA("ParticleEmitter") and d.Name ~= "Weather" then
			local p = d.Parent
			if p and p:IsA("BasePart") then table.insert(emitters, { e = d, dist = (p.Position - pos).Magnitude }) end
		end
	end
	table.sort(lights, function(a, b) return a.dist < b.dist end)
	table.sort(emitters, function(a, b) return a.dist < b.dist end)
	for k, x in lights do x.l.Enabled = k <= B.MaxLights - 1 end
	local weatherOn = 0
	for _, s in weatherHosts do if s.em.Enabled then weatherOn += 1 end end
	for k, x in emitters do x.e.Enabled = k <= B.MaxEmitters - weatherOn end
end

--============================================================================ hazards
local function runHazards(t0: number, t1: number, hrp: BasePart)
	if run == nil or not hazardsOn then return end
	local pos = hrp.Position
	local p = { x = pos.X, y = pos.Y, z = pos.Z }
	local warnNear = false
	for _, h in run.hazards do
		local state, prog = DoorHazards.stateAt(h.slot, t1, HZ)
		local ring, fixture, falling = h.ring :: BasePart?, h.fixture :: BasePart?, h.falling :: BasePart?
		local cx, cz = h.centre.x, h.centre.z
		if ring then
			if state == "warn" then
				ring.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(t1 * 12))
			elseif state == "debris" then
				ring.Transparency = 0.6 + 0.4 * prog
			else
				ring.Transparency = 1
			end
		end
		if fixture then
			local shake = if state == "warn" then 0.15 * math.sin(t1 * 40) else 0
			fixture.CFrame = CFrame.new(cx + shake, h.centre.y + G.WallHeight - 1.4, cz)
		end
		if falling then
			if state == "warn" and prog > 0.9 then
				local f = (prog - 0.9) / 0.1
				falling.Transparency = 0
				falling.CFrame = CFrame.new(cx, h.centre.y + (G.WallHeight - 1.4) * (1 - f) + 1.1 * f, cz)
			elseif state == "debris" then
				falling.Transparency = prog
				falling.CFrame = CFrame.new(cx, h.centre.y + 1.1, cz)
			else
				falling.Transparency = 1
			end
		end
		if state == "warn" then
			local dx, dz = p.x - cx, p.z - cz
			if dx * dx + dz * dz <= (HZ.NearRadius + 12) ^ 2 then warnNear = true end
		end
		if DoorHazards.checkHit(h.slot, h.centre, t0, t1, p, HZ) then
			local vel, secs = DoorHazards.knock(h.centre, p, HZ)
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then hum.PlatformStand = true end
			pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(vel.x, 0, vel.z) end)
			run.knockedUntil = t1 + secs
			run.knocks += 1
			setAttr("SameDoorKnocks", run.knocks)
		elseif DoorHazards.nearMiss(h.slot, h.centre, t0, t1, p, HZ) then
			run.near += 1
			setAttr("SameDoorNear", run.near)
		end
	end
	setAttr("SameDoorWarn", warnNear)
	if run.knockedUntil and t1 >= run.knockedUntil then
		run.knockedUntil = nil
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum.PlatformStand = false end
	end
end

--============================================================================ every frame
local slowTimer = 0
RunService.Heartbeat:Connect(function(dt: number)
	clockNow += dt
	local hrp = rootPart()
	-- the display clock: starts at this client's own sighting of the crossing
	if run and hrp and (run.phase == "ready" or run.phase == "running") then
		local rel = hrp.Position - run.origin
		if not run.crossed then
			if run.prevX ~= nil then
				local f = Grid.lineCrossing(run.prevX, run.prevZ, rel.X, rel.Z, Config)
				if f ~= nil then
					run.crossed = true
					run.clock = (1 - f) * dt
				end
			end
		else
			local t0 = run.clock
			run.clock += dt
			runHazards(t0, run.clock, hrp)
		end
		run.prevX, run.prevZ = rel.X, rel.Z
		setAttr("SameDoorClock", if run.crossed then run.clock else -1)
	end

	-- the look glides toward its target; Lighting is written at most LightingHz times a second
	local target = targetLook()
	for _, gname in GROUPS do
		current[gname] = EnvBands.approachTable(current[gname], target[gname], dt, Env.HalfLife)
	end
	if clockNow - lastWrite >= 1 / Env.LightingHz - 1e-9 then
		lastWrite = clockNow
		writes += 1
		for _, gname in GROUPS do writeGroup(targets[gname], current[gname]) end
		setAttr("SameDoorLightingWrites", writes)
		setAttr("SameDoorBand", bandIndex())
	end

	slowTimer += dt
	if slowTimer >= 0.25 and hrp then
		local step = slowTimer
		slowTimer = 0
		refreshDecor(hrp.Position)
		refreshCritters(hrp.Position, step)
		refreshWeather(hrp.Position)
		enforceBudgets(hrp.Position)
		setAttr("SameDoorParts", countParts())
	end
end)

setAttr("SameDoorClock", -1)
